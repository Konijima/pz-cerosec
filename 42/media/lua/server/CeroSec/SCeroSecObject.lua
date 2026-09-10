if isClient() then return end

require "Map/SGlobalObject"
require "CeroSec/CeroSecDefs"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSPath"
require "CeroSec/OS/CeroSecOSFS"
require "CeroSec/OS/CeroSecOSUsers"
require "CeroSec/OS/CeroSecOSState"
require "CeroSec/OS/CeroSecOSShell"

SCeroSecObject = SGlobalObject:derive("SCeroSecObject")

function SCeroSecObject:new(luaSystem, globalObject)
	return SGlobalObject.new(self, luaSystem, globalObject)
end

function SCeroSecObject:initNew()
	self.v = CeroSec.STATE_VERSION
	self.on = false
	self.facing = "S"
	-- self.os stays nil until the machine is first used: an untouched computer
	-- costs nothing in gos_cerosec.bin.
end

--
-- State <-> IsoObject
--
-- The GlobalObject holds the truth. It is mirrored into
-- isoObject:getModData().movableData.cerosec on every change, so vanilla pickup
-- copies it into the item (ISMoveableSpriteProps.lua:1300) and placement copies
-- it back (ISMoveableSpriteProps.lua:2270). Both copies go through copyTable,
-- which recurses into nested tables (LuaManager.copyTable:1517), so the whole
-- filesystem rides along with the machine.
--

function SCeroSecObject:toModData(isoObject)
	if not isoObject then return end
	local modData = isoObject:getModData()
	if not modData.movableData then modData.movableData = {} end
	modData.movableData[CeroSec.MOVABLE_DATA_KEY] = {
		v = self.v,
		on = self.on,
		facing = self.facing,
		os = self.os,
	}
end

-- What the mirror in the IsoObject says, or nil. Only ever read for the OS
-- state: everything else the sprite already tells us.
function SCeroSecObject:osFromIsoObject(isoObject)
	if not isoObject or not isoObject:hasModData() then return nil end
	local modData = isoObject:getModData()
	local movableData = modData.movableData
	if not movableData then return nil end
	local mine = movableData[CeroSec.MOVABLE_DATA_KEY]
	if not mine then return nil end
	return mine.os
end

-- Called for an IsoObject that had no GlobalObject yet (fresh world, or a
-- deleted gos_cerosec.bin): adopt what the sprite says. The sprite is enough --
-- its index encodes both the facing and the on/off state -- but the OS state is
-- not in the sprite, so that one comes from the movableData mirror when there
-- is one (a computer put down before the GlobalObject file was lost).
-- loadIsoObject announces the new object to clients right after this call.
function SCeroSecObject:stateFromIsoObject(isoObject)
	local spriteName = isoObject:getSpriteName()
	self.v = CeroSec.STATE_VERSION
	self.facing = CeroSec.facingOf(spriteName) or "S"
	self.on = CeroSec.isOnSprite(spriteName)
	self.os = self:osFromIsoObject(isoObject)
	self:toModData(isoObject)
end

-- Called for an IsoObject that already has a GlobalObject, i.e. on every chunk
-- load. The client mirror starts empty on each session, so announce the object
-- rather than only updating it: an update for an object the client does not have
-- is dropped (CGlobalObjectSystem.receiveUpdateLuaObjectAt returns early).
-- CCeroSecSystem:newLuaObjectAt tolerates the repeat.
function SCeroSecObject:stateToIsoObject(isoObject)
	self:syncSprite()
	self:toModData(isoObject)
	self.luaSystem:newLuaObjectOnClient(self)
end

-- A computer that has just been placed is off, whatever it was before. Its
-- facing comes from the sprite the placement code chose, and its disk from the
-- item that was carried here.
function SCeroSecObject:resetForPlacement(isoObject)
	self.v = CeroSec.STATE_VERSION
	self.on = false
	self.facing = CeroSec.facingOf(isoObject:getSpriteName()) or "S"
	self.os = self:osFromIsoObject(isoObject) or self.os
	self.osBroken = nil
	self:dropSessions()
	self:syncSprite()
	self:toModData(isoObject)
	self:updateOnClient()
end

--
-- Sprite
--

function SCeroSecObject:syncSprite()
	local isoObject = self:getIsoObject()
	if not isoObject then return end
	local want = CeroSec.spriteFor(self.facing, self.on)
	if not want or isoObject:getSpriteName() == want then return end
	-- Same pair of calls the campfire uses (SCampfireGlobalObject.lua:93 and 283).
	isoObject:setSpriteFromName(want)
	isoObject:transmitUpdatedSpriteToClients()
end

--
-- Power
--

function SCeroSecObject:hasPower()
	local square = self:getSquare()
	if not square then return false end
	-- Same test the car battery charger uses (ISWorldObjectContextMenu.lua:460).
	return square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil)
end

--
-- The OS
--
-- The state is a plain nested table of strings, numbers and booleans, which is
-- exactly what the game's table serializer keeps (KahluaTableImpl.save writes
-- strings, doubles, booleans and nested tables, and silently drops the rest).
-- It is created on first use and never before, so a computer nobody has touched
-- carries no filesystem at all.
--

function SCeroSecObject:hostname()
	return CeroSec.hostnameFor(self.x, self.y)
end

-- The state, or nil plus a reason when it is not something the core can run on.
-- The refusal is sticky and logged once: a state the validator rejects is a
-- state we would rather stop touching than repair blindly.
function SCeroSecObject:osState()
	if self.osBroken then return nil, "refused" end

	if type(self.os) ~= "table" or self.os.v ~= CeroSecOS.STATE_VERSION then
		self.os = CeroSecOS.migrate(self.os, self:hostname())
		self:mirrorOS()
		return self.os
	end

	local ok, reason = CeroSecOS.validate(self.os)
	if not ok then
		self.osBroken = true
		CeroSec.log("os refused at " .. self.x .. "," .. self.y .. "," .. self.z .. ": " .. tostring(reason))
		return nil, reason
	end
	return self.os
end

-- Bring the IsoObject mirror in line with the state. Cheap: the mirror holds
-- the very same table, so this only matters when the mirror was never built or
-- was replaced (a fresh placement).
function SCeroSecObject:mirrorOS()
	self:toModData(self:getIsoObject())
end

-- Push the mirror out to the clients. Only done when a session ends, not on
-- every command: in multiplayer the pickup code reads the *client's* copy of
-- movableData (ISMoveableSpriteProps.lua:1300), so the copy has to be fresh by
-- the time anybody can walk away with the machine, and a filesystem is up to
-- 32 KB -- not something to send after every keystroke.
function SCeroSecObject:publishOS()
	local isoObject = self:getIsoObject()
	if not isoObject then return end
	self:toModData(isoObject)
	isoObject:transmitModData()
end

--
-- Sessions
--
-- Transient: they live for as long as the player keeps his terminal open and
-- are never written into the state (CeroSecOSUsers.login says as much). Keyed
-- by the connection, not by the character.
--

function SCeroSecObject:sessionFor(playerKey)
	if not self.sessions then return nil end
	return self.sessions[playerKey]
end

function SCeroSecObject:openSession(playerKey, session)
	if not self.sessions then self.sessions = {} end
	self.sessions[playerKey] = session
end

function SCeroSecObject:closeSession(playerKey)
	if not self.sessions then return end
	if not self.sessions[playerKey] then return end
	self.sessions[playerKey] = nil
	self:publishOS()
end

-- Every session at once: the machine went off, or lost its power.
function SCeroSecObject:dropSessions()
	local had = self.sessions ~= nil
	self.sessions = nil
	if had then self:publishOS() end
end

--
-- Toggle
--

function SCeroSecObject:turnOn()
	if self.on then return false end
	if not self:hasPower() then return false end
	self.on = true
	self:apply()
	self:playSound("CeroSecBootStart")
	return true
end

function SCeroSecObject:turnOff()
	if not self.on then return false end
	self.on = false
	-- Nobody is logged in on a machine that is off, and the terminals that were
	-- open have to be told, not merely forgotten.
	if self.luaSystem and self.luaSystem.evictSessions then
		self.luaSystem:evictSessions(self, "off")
	else
		self:dropSessions()
	end
	self:apply()
	self:playSound("CeroSecToggle")
	return true
end

function SCeroSecObject:toggle()
	if self.on then return self:turnOff() end
	return self:turnOn()
end

function SCeroSecObject:apply()
	local isoObject = self:getIsoObject()
	self:syncSprite()
	self:toModData(isoObject)
	if isoObject then isoObject:transmitModData() end
	self:updateOnClient()
	CeroSec.log("computer at " .. self.x .. "," .. self.y .. "," .. self.z .. " on=" .. tostring(self.on))
end

function SCeroSecObject:playSound(soundName)
	local square = self:getSquare()
	if not square then return end
	-- Same split STrapGlobalObject.lua:118-124 uses so nearby clients hear it.
	if isServer() then
		playServerSound(soundName, square)
	else
		square:playSound(soundName)
	end
end
