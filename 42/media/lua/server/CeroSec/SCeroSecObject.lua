if isClient() then return end

require "Map/SGlobalObject"
require "CeroSec/CeroSecDefs"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSPath"
require "CeroSec/OS/CeroSecOSDev"
require "CeroSec/OS/CeroSecOSDisk"
require "CeroSec/OS/CeroSecOSFS"
require "CeroSec/OS/CeroSecOSNet"
require "CeroSec/OS/CeroSecOSUsers"
require "CeroSec/OS/CeroSecOSState"
require "CeroSec/OS/CeroSecOSSystem"
require "CeroSec/OS/CeroSecOSScript"
require "CeroSec/OS/CeroSecOSShell"
require "CeroSec/OS/CeroSecOSComplete"
require "CeroSec/OS/CeroSecOSVM"
require "CeroSec/SCeroSecNet"
require "CeroSec/SCeroSecJobs"

SCeroSecObject = SGlobalObject:derive("SCeroSecObject")

function SCeroSecObject:new(luaSystem, globalObject)
	return SGlobalObject.new(self, luaSystem, globalObject)
end

function SCeroSecObject:initNew()
	self.v = CeroSec.STATE_VERSION
	self.on = false
	self.facing = "S"
	-- self.disk stays nil until a disk goes in the slot. It is DERIVED from the
	-- OS state and is not saved: what is in the drive is state.floppy's to say,
	-- and a second copy of that in gos_cerosec.bin is a second copy that can be
	-- wrong.
	-- self.os stays nil until the machine is first used: an untouched computer
	-- costs nothing in gos_cerosec.bin. self.console stays nil until the
	-- machine is switched on: a screen only exists while there is power.
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
	-- The console is deliberately not in here. It is a screen, not a disk: a
	-- computer that is picked up is a computer that lost its power, and
	-- resetForPlacement clears it anyway. Mirroring it would only put a hundred
	-- lines of text in every item that is carried across town.
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
	self:syncDisk()
	-- No console in the mirror, so a machine adopted from its sprite starts
	-- with a blank screen even when the sprite says it is lit.
	self.console = nil
	self:toModData(isoObject)
end

-- Called for an IsoObject that already has a GlobalObject, i.e. on every chunk
-- load. The client mirror starts empty on each session, so announce the object
-- rather than only updating it: an update for an object the client does not have
-- is dropped (CGlobalObjectSystem.receiveUpdateLuaObjectAt returns early).
-- CCeroSecSystem:newLuaObjectAt tolerates the repeat.
function SCeroSecObject:stateToIsoObject(isoObject)
	self:syncSprite()
	-- Derived, so it is worked out again on every chunk load rather than read off
	-- a field the save file might disagree with.
	self:syncDisk()
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
	-- The disk that was in the slot travelled with the machine, inside the OS
	-- state. A computer put down on the other side of town still has it -- and
	-- nothing is mounted any more, for the reason the power switch has: it was
	-- carried, so it lost its power on the way. One `mount` is the way back.
	self:syncDisk()
	local placed = self:osState()
	if placed ~= nil then CeroSecOS.unmountAll(placed) end
	-- A computer being picked up is a computer that lost its power: every session
	-- on it and every session it had open ends, and the glass at the far end of
	-- each is told.
	CeroSecNet.closeSessions(self.luaSystem, self)
	self.console = nil
	CeroSecJobs.killAll(self)
	self:dropWatchers()
	self:syncSprite()
	self:toModData(isoObject)
	self:updateOnClient()
end

--
-- The drive
--
-- What is IN the drive is state.floppy's to say and lives in the OS state, so it
-- rides in movableData with the filesystem and travels with the machine when
-- somebody picks it up: a computer carried across town still has the disk in its
-- slot, exactly as a real one would. There is deliberately no "eject it to the
-- floor first" -- a disk in a drive is in the drive.
--
-- self.disk is the one bit of that the CLIENT is told, because the right-click
-- menu has to know whether to offer Insert or Eject before anything is sent. It
-- is a boolean and nothing more: what is written on the disk is nobody's business
-- but the machine's.
--

-- Is there a disk in the slot? Read off the OS state raw rather than through
-- osState(), because the menu asks this about machines that are off and about
-- machines whose disk the validator has refused, and neither is a reason to
-- pretend the slot is empty.
function SCeroSecObject:hasDisk()
	return type(self.os) == "table" and type(self.os.floppy) == "table"
end

-- Bring the flag the client sees in line with the state.
function SCeroSecObject:syncDisk()
	local had = self.disk
	self.disk = self:hasDisk() or nil
	if had ~= self.disk then self:updateOnClient() end
end

-- Put a disk in. true, or nil plus the reason.
--
-- disk is a plain table the caller has already lifted out of the item's modData
-- and validated (CeroSecOS.validateDisk); fullType is the shell it came in, kept
-- on the machine so the survivor gets HIS disk back and not a blue one.
function SCeroSecObject:insertDisk(disk, fullType)
	local state = self:osState()
	if state == nil then return nil, "broken" end
	if state.floppy ~= nil then return nil, "occupied" end
	state.floppy = disk
	state.fdtype = fullType
	self:mirrorOS()
	self:publishOS()
	self:syncDisk()
	self:playSound("CeroSecInsertDisc")
	return true
end

-- What is in the drive and whether it may come out, WITHOUT taking it out. The
-- disk and the shell it goes back into, or nil plus the reason.
--
-- Split from the taking-out on purpose. An eject is four things that can each
-- refuse -- there is a disk, it may leave, there is a hand to put it in, and it
-- will go onto the item -- and doing any of them after the disk has left the drive
-- is how an eject ends half done: two sounds for a gesture that achieved nothing,
-- a mount dropped for no reason, and a player told nothing at all.
--
-- "It may leave" is the one that is not obvious. A disk no slot would take must
-- not go out into his hands: out there it is a disk nobody in the world will
-- accept and no screen says why, while in the machine it is a disk `df` explains
-- and one `rm` fixes. Nothing the write path can do makes one -- a disk is held to
-- its ceilings at every write -- so this is the belt under that and not the rule.
function SCeroSecObject:diskToEject()
	local state = self:osState()
	if state == nil then return nil, "broken" end
	local disk = state.floppy
	if disk == nil then return nil, "empty" end
	local fits, why = CeroSecOS.validateDisk(disk, true)
	if not fits then
		CeroSec.log("the drive at " .. self.x .. "," .. self.y .. "," .. self.z
			.. " kept the disk: " .. tostring(why))
		return nil, why
	end
	return disk, CeroSec.floppyTypeOr(state.fdtype)
end

-- And now it really leaves. Called only once everything above has been answered,
-- so from here there is nothing left that can refuse.
--
-- The mount goes with it, and nothing is lost by that: every write on this
-- machine is finished by the time the command that made it answered -- there is
-- no buffer between a file and the state it lives in -- so an unmount is
-- bookkeeping and never a flush. That is why ejecting a mounted disk is allowed
-- at all: on a machine with write-behind it would be how you lose a file.
function SCeroSecObject:ejectDisk()
	local disk, fullType = self:diskToEject()
	if disk == nil then return nil, fullType end
	local state = self:osState()
	CeroSecOS.unmountAll(state)
	state.floppy = nil
	state.fdtype = nil
	self:mirrorOS()
	self:publishOS()
	self:syncDisk()
	self:playSound("CeroSecEjectDisc")
	return disk, fullType
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

	-- A machine saved before passwords were hashed carries them in clear, and
	-- the validator refuses those. That is the one repair a state of the current
	-- version gets, and it happens before the gate rather than after it: the
	-- alternative is throwing away a working filesystem over a password field.
	CeroSecOS.migrateUsers(self.os)
	-- The same two repairs CeroSecOS.migrate does, and for the same reason: they
	-- happen before the gate rather than after it. A machine saved by an older
	-- build is missing the executables that build never had, and topping it up
	-- is not throwing a working filesystem away.
	CeroSecOS.upgradeSystem(self.os)
	-- The devices under /dev are mounted for the length of one scheduler pass and
	-- taken away again by CeroSecOS.jobStep. This is the belt to that pair of
	-- braces: a
	-- command that died in the middle would leave nodes the validator refuses --
	-- a working machine turned "broken" by a light switch -- so the gate every
	-- read of the state goes through sweeps them first. On a healthy machine
	-- there is nothing to sweep and this walks an empty /dev.
	CeroSecOS.unmountDev(self.os)
	-- And the same belt under the mount table: a mount naming a drive with nothing
	-- in it is a mount nothing can walk through, and it is dropped rather than left
	-- to answer "no such file" about every path under it for ever. On a healthy
	-- machine this walks a table of one or of none.
	CeroSecOS.checkMounts(self.os)

	local ok, reason = CeroSecOS.validate(self.os)
	if not ok then
		self.osBroken = true
		CeroSec.log("os refused at " .. self.x .. "," .. self.y .. "," .. self.z .. ": " .. tostring(reason))
		return nil, reason
	end
	return self.os
end

-- The BIOS' own repair, and the only path that touches a state the validator
-- has already refused: a machine whose disk is unreadable is exactly the
-- machine this is for, so it runs on self.os raw rather than on osState().
--
-- A state of the current version is repaired in place, which is what keeps
-- /home: migrate would hand back a brand new machine instead. Anything else --
-- a version we do not know, junk, nothing at all -- has no filesystem worth
-- keeping and goes through migrate.
--
-- true when the machine boots afterwards.
function SCeroSecObject:restoreOS()
	if type(self.os) ~= "table" or self.os.v ~= CeroSecOS.STATE_VERSION then
		self.os = CeroSecOS.migrate(self.os, self:hostname())
	else
		CeroSecOS.restoreSystem(self.os)
	end
	-- The refusal was sticky on purpose; the repair is the one thing that lifts
	-- it, and osState below is what decides whether it stays lifted.
	self.osBroken = nil
	self:mirrorOS()
	local state = self:osState()
	if state == nil then return false end
	return CeroSecOS.systemOk(state) and true or false
end

-- Bring the IsoObject mirror in line with the state. Cheap: the mirror holds
-- the very same table, so this only matters when the mirror was never built or
-- was replaced (a fresh placement).
function SCeroSecObject:mirrorOS()
	self:toModData(self:getIsoObject())
end

-- Push the mirror out to the clients. Only done when a window closes, not on
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
-- The console
--
-- One screen per computer, and it is the machine's: what is on it, who is
-- logged in and where he stands in the filesystem all live here, are saved with
-- the object, and are the same for everybody who opens a window on it. It is
-- created when the machine is switched on and destroyed when it goes dark.
--

function SCeroSecObject:consoleState()
	if not self.on then return nil end
	-- Once per load, whatever shape it came back in. It used to be repaired
	-- only when it was not a table or its lines were not a table, which is the
	-- one case a console off the disk never is: everything else the save file
	-- could carry -- a half-written prompt token, a buffer with no path, a
	-- forged modData -- went straight through the gate it was written for.
	-- consoleChecked is not in the saved keys, so it is false again on the next
	-- load and the repair happens exactly once per machine per session.
	if not self.consoleChecked then
		self.consoleChecked = true
		if self.console ~= nil then self.console = CeroSec.repairConsole(self.console) end
	end
	if type(self.console) ~= "table" or type(self.console.lines) ~= "table" then
		-- Never seen, or handed back as something that is not a console.
		self.console = CeroSec.repairConsole(self.console)
	end
	return self.console
end

--
-- Watchers
--
-- Every window open on this computer, so that a change to the screen reaches
-- all of them and not only the one that caused it. Transient: the player
-- objects in here are never saved (they are not in the object's modData keys)
-- and they are pruned on close, on eviction and by the sweep.
--

function SCeroSecObject:addWatcher(key, playerObj, token)
	if not self.watchers then self.watchers = {} end
	self.watchers[key] = { player = playerObj, token = token }
end

function SCeroSecObject:removeWatcher(key)
	if not self.watchers then return end
	if not self.watchers[key] then return end
	self.watchers[key] = nil
	self:publishOS()
end

-- Every window at once: the machine went off, or lost its power.
function SCeroSecObject:dropWatchers()
	local had = self.watchers ~= nil
	self.watchers = nil
	if had then self:publishOS() end
end

--
-- Toggle
--

function SCeroSecObject:turnOn()
	if self.on then return false end
	if not self:hasPower() then return false end
	self.on = true
	-- A fresh screen, with the BIOS still to be typed on it. It was just made
	-- here, so there is nothing to repair and nothing to check.
	self.console = CeroSec.newConsole()
	self.consoleChecked = true
	-- When it came up, for ruptime. Runtime state like the jobs: a server that
	-- came back up forgets it, and ruptime counts from the restart.
	self.upMs = getTimestampMs()
	-- Which building it stands in, and therefore its address. Here rather than at
	-- the first command because the power check has just proved the chunk is
	-- loaded, which is the one thing working a building out needs.
	CeroSecNet.identify(self.luaSystem, self, self:osState())
	self:apply()
	self:playSound("CeroSecBootStart")
	-- @reboot, which is the one crontab line that is not a time: the machine has
	-- just come up, so it is due now and never again until it comes up again.
	CeroSecJobs.atBoot(self.luaSystem, self)
	return true
end

function SCeroSecObject:turnOff()
	if not self.on then return false end
	-- The sessions first, before the console is thrown away: it is what remembers
	-- where the outbound one went, and the inbound ones have a glass each to tell.
	-- A survivor logged in at the keyboard gets his logout written too, or `last`
	-- would say he is still there for ever.
	local state = self:osState()
	if state ~= nil and type(self.console) == "table"
			and type(self.console.user) == "string" then
		CeroSecOS.wtmpAppend(state, "out", self.console.user, CeroSecOS.CONSOLE_LINE,
			nil, CeroSecOS.clockOf(self.luaSystem:clockEnv()))
	end
	CeroSecNet.closeSessions(self.luaSystem, self)
	-- And every mount, which is what a reboot does on any machine: a mount is a
	-- thing in memory and the power has just gone. The DISK stays in the slot --
	-- that is a thing in the world -- so the way back is one `mount` after the
	-- machine comes up.
	if state ~= nil then CeroSecOS.unmountAll(state) end
	self.on = false
	-- Everything that was running is gone with the power, which is what a
	-- switch at the back of the case does. reboot goes through here too, so a
	-- machine that comes back comes back running nothing.
	CeroSecJobs.killAll(self)
	-- And the minute cron last looked at goes with them: a machine that comes
	-- back is a machine that has only just come into view, so it runs nothing for
	-- the minute it arrived in and nothing at all for the minutes it was dark.
	self.cron = nil
	-- A dark screen remembers nothing, and the terminals that were open have to
	-- be told, not merely forgotten.
	self.console = nil
	if self.luaSystem and self.luaSystem.evictWatchers then
		self.luaSystem:evictWatchers(self, "off")
	else
		self:dropWatchers()
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
