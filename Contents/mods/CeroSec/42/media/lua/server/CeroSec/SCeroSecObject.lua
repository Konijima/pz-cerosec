if isClient() then return end

require "Map/SGlobalObject"
require "CeroSec/CeroSecDefs"

SCeroSecObject = SGlobalObject:derive("SCeroSecObject")

function SCeroSecObject:new(luaSystem, globalObject)
	return SGlobalObject.new(self, luaSystem, globalObject)
end

function SCeroSecObject:initNew()
	self.v = CeroSec.STATE_VERSION
	self.on = false
	self.facing = "S"
end

--
-- State <-> IsoObject
--
-- The GlobalObject holds the truth. It is mirrored into
-- isoObject:getModData().movableData.cerosec on every change, so vanilla pickup
-- copies it into the item (ISMoveableSpriteProps.lua:1300) and placement copies
-- it back (ISMoveableSpriteProps.lua:2270).
--

function SCeroSecObject:toModData(isoObject)
	if not isoObject then return end
	local modData = isoObject:getModData()
	if not modData.movableData then modData.movableData = {} end
	modData.movableData[CeroSec.MOVABLE_DATA_KEY] = {
		v = self.v,
		on = self.on,
		facing = self.facing,
	}
end

-- Called for an IsoObject that had no GlobalObject yet (fresh world, or a
-- deleted gos_cerosec.bin): adopt what the sprite says. The sprite is enough --
-- its index encodes both the facing and the on/off state -- so rung 1 never
-- needs to read the movableData mirror back. The mirror exists so that pickup
-- carries the state into the item for the later rungs (os, hostname).
-- loadIsoObject announces the new object to clients right after this call.
function SCeroSecObject:stateFromIsoObject(isoObject)
	local spriteName = isoObject:getSpriteName()
	self.v = CeroSec.STATE_VERSION
	self.facing = CeroSec.facingOf(spriteName) or "S"
	self.on = CeroSec.isOnSprite(spriteName)
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
-- facing comes from the sprite the placement code chose.
function SCeroSecObject:resetForPlacement(isoObject)
	self.v = CeroSec.STATE_VERSION
	self.on = false
	self.facing = CeroSec.facingOf(isoObject:getSpriteName()) or "S"
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
