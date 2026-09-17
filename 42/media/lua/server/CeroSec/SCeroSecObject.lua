if isClient() then return end

require "Map/SGlobalObject"
require "CeroSec/CeroSecContent"
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
require "CeroSec/SCeroSecAuto"

SCeroSecObject = SGlobalObject:derive("SCeroSecObject")

function SCeroSecObject:new(luaSystem, globalObject)
	return SGlobalObject.new(self, luaSystem, globalObject)
end

-- What the minute sweep's two indexes hold about this machine, written again from
-- the machine itself. Called wherever `on` or `born` is -- and the index is DERIVED
-- rather than incremented, so a caller cannot get it out of step by remembering
-- one half of a transition (the head of the housekeeping section in
-- SCeroSecSystem.lua).
function SCeroSecObject:reindex()
	local system = self.luaSystem
	if system == nil or system.indexMachine == nil then return end
	system:indexMachine(self)
end

-- The engine's own word for "this machine is leaving the system": removeLuaObject
-- calls it before the GlobalObject goes (SGlobalObjectSystem.lua:94). An index
-- entry for a machine nothing holds any more would be a machine the sweep visits
-- for ever.
function SCeroSecObject:aboutToRemoveFromSystem()
	local system = self.luaSystem
	if system == nil or system.forgetMachine == nil then return end
	system:forgetMachine(self)
end

function SCeroSecObject:initNew()
	self.v = CeroSec.STATE_VERSION
	self.on = false
	-- The AT switch at the back of the case. A machine nobody has ever
	-- switched on has never had a reason to be left on through an outage.
	self.switchOn = false
	self.facing = "S"
	-- self.disk is false and not nil, and stays a boolean for ever after: the
	-- sync is a MERGE and a nil never crosses it (see syncDisk). It is DERIVED
	-- from the OS state and is not saved: what is in the drive is state.floppy's
	-- to say, and a second copy of that in gos_cerosec.bin is a second copy that
	-- can be wrong.
	self.disk = false
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
	-- No GlobalObject means no saved switch either. The sprite is the only
	-- word we have, and a machine the sprite shows running has to have had its
	-- switch on to be running at all.
	self.switchOn = self.on
	-- The sprite says it was left running, so the sweep has to know about it: this
	-- is a machine the save file had no GlobalObject for.
	self:reindex()
	self:setOS(self:osFromIsoObject(isoObject))
	self:syncDisk()
	-- No console in the mirror, so a machine adopted from its sprite starts
	-- with a blank screen even when the sprite says it is lit.
	self.console = nil
	-- And no jobs, for the same reason read one step further: the book is only ever
	-- taken off a state on the road the SAVE FILE comes in by
	-- (SCeroSecSystem:newLuaObject), and this is the other one -- a machine built
	-- out of an item's mirror, which on a server is a table a client wrote. So
	-- whatever that mirror carries under `jobs` goes, here, before anything reads
	-- the state.
	if type(self.os) == "table" then self.os.jobs = nil end
	self:toModData(isoObject)
end

-- Called for an IsoObject that already has a GlobalObject, i.e. on every chunk
-- load. The client mirror starts empty on each session, so announce the object
-- rather than only updating it: an update for an object the client does not have
-- is dropped (CGlobalObjectSystem.receiveUpdateLuaObjectAt returns early).
-- CCeroSecSystem:newLuaObjectAt tolerates the repeat.
function SCeroSecObject:stateToIsoObject(isoObject)
	-- The chunk is back, so the one question nobody could ask while it was away
	-- is asked now and first: has the room still got a wire? Nothing asked it in
	-- the meantime -- the minute sweep skips a machine with no world to look at
	-- (checkPower below) -- so a computer whose generator ran dry or whose grid
	-- went while the survivor was on the other side of town goes dark at the
	-- moment he walks back in, and not a minute later.
	--
	-- Before the three calls below because turnOff does all three itself (apply
	-- syncs the sprite, mirrors the state and announces it), and they are
	-- idempotent, so a machine that has just gone dark is still announced with
	-- the dark sprite on it.
	self:checkPower()
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
	-- Carried here with the wire unplugged, whatever the switch was left at:
	-- the outage a picked-up machine "suffers" is not one the wire will ever
	-- come back from on its own, so there is nothing to restart it later.
	self.switchOn = false
	self:reindex()
	self.facing = CeroSec.facingOf(isoObject:getSpriteName()) or "S"
	-- Through the setter even where the item brought nothing and the machine keeps
	-- the table it had: this is the path that asks every question again -- both
	-- sticky refusals go below -- and the validator's memo is one of them.
	self:setOS(self:osFromIsoObject(isoObject) or self.os)
	-- Whatever the item's mirror said this machine was running. killAll below takes
	-- it away too -- a computer picked up is a computer that lost its power -- but
	-- that is after osState() has been asked, and the gate must never walk a book
	-- an ITEM brought: on a server that table was written by a client.
	if type(self.os) == "table" then self.os.jobs = nil end
	self.osBroken = nil
	-- And the other sticky refusal. A state a later build wrote is still one after
	-- it has been carried across town, so this does not make it readable -- osState
	-- puts the flag straight back on the next read. What it does is ask the question
	-- again about the state the ITEM brought, which need not be the one the machine
	-- refused.
	self.osNewer = nil
	-- And any reset that was waiting for a power-on. The state this machine has now
	-- is the one the ITEM brought, and prefilling over somebody's carried filesystem
	-- is the very thing the bare test exists to prevent (see turnOn).
	self.osFresh = nil
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
--
-- A real false, never a nil, and that is the whole of it: the update the line
-- below sends is a MERGE and not a replacement. The server writes only the sync
-- keys it actually HAS (TableNetworkUtils.saveSome walks the table and skips
-- what is not there) and the client rawsets each key it receives into its own
-- copy (CGlobalObjectSystem.receiveUpdateLuaObjectAt, both javap'd on 42.20.4).
-- So a key set back to nil is a key that is simply not in the packet, and the
-- client keeps the true it was told last time: the drive came out, the menu went
-- on offering Eject and greying Insert with "the drive is full".
function SCeroSecObject:syncDisk()
	local had = self.disk
	self.disk = self:hasDisk()
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
	-- Asked again, and the answer is used. Within one call it cannot have changed
	-- -- osState is deterministic and the caller has just asked -- and it is the
	-- only thing between this and handing the player a disk the machine still has,
	-- which is a duplication and not a loss. A check that costs nothing is the right
	-- price for that.
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

-- Is this machine's chunk in the world right now?
--
-- Everything the WORLD has to answer needs this first, and nothing the DISK
-- answers on its own does: a machine whose chunk the streamer has taken away
-- keeps its last state, goes on running its jobs and goes on answering the wire
-- (the head of SCeroSecNet.lua), because the state lives in gos_cerosec.bin and
-- not in the chunk.
--
-- The iso object and not the square, which is the stricter of the two. A square
-- with no computer on it any more is a machine on its way out of the system
-- (Events.OnObjectAboutToBeRemoved -> SGlobalObjectSystem:removeLuaObject for
-- one taken or destroyed, SGlobalObjectSystem:OnChunkLoaded for one that went
-- while nobody was looking), and a machine on its way out is not one to switch
-- off first.
function SCeroSecObject:isLoaded()
	return self:getIsoObject() ~= nil
end

-- Is there a wire at this machine's square?
--
-- Asked of the WORLD, so it is only an answer at all while the chunk is loaded:
-- false for a machine nobody has streamed in means "there was nobody to ask",
-- not "the room has no power". turnOn wants exactly that reading -- a machine
-- nobody can reach is a machine nobody can switch on -- and the decision that
-- switches a machine OFF wants the other, which is what checkPower below is for.
function SCeroSecObject:hasPower()
	local square = self:getSquare()
	if not square then return false end
	-- Same test the car battery charger uses (ISWorldObjectContextMenu.lua:460).
	return square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil)
end

-- The power decision for one machine, and the only place it is made: the minute
-- sweep asks it of every machine the server holds (SCeroSecSystem:checkPower)
-- and a chunk coming back asks it of the one that has just arrived
-- (stateToIsoObject).
--
-- The guard is the whole of it. hasPower is asked of the machine's SQUARE, and a
-- machine whose chunk is unloaded has none -- so without the guard a survivor who
-- walked far enough came home to a building of dark computers: the sweep read "no
-- square" as "no wire" and switched off every machine behind him. A machine out
-- of the world keeps the state it had, and the question waits for the chunk.
--
-- That is vanilla's own habit with a global object it cannot see: the campfire
-- sweep skips one whose square is gone -- "if campfire is burning (and still
-- there, I mean not destroy because of streaming)", SCampfireSystem.lua:157-159,
-- and the same guard at :100-101 -- while it goes on burning its fuel regardless
-- (lowerFuelAmount:135-138), which is the fire's own state and not the world's.
--
-- true when the machine was switched off here.
function SCeroSecObject:checkPower()
	if not self.on then return false end
	if not self:isLoaded() then return false end
	if self:hasPower() then return false end
	-- Every window open on it is told why it is over, not merely forgotten: the
	-- reason is what the glass prints.
	if self.luaSystem and self.luaSystem.evictWatchers then
		self.luaSystem:evictWatchers(self, "power")
	end
	return self:turnOff()
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

-- The state put in place, and the ONE road it goes in by: every path that hands
-- this machine a table writes it here so that the memo under the validator
-- (osState below) is dropped with it.
--
-- self.osChecked is the memo and it holds the TABLE, never a flag. A flag would
-- go stale the moment a state was replaced -- a fresh machine, a computer put
-- down out of somebody's hands, a chain that walked -- and a stale flag here is a
-- table nothing ever validated being run on. Identity cannot go stale: a
-- different table is a different table.
function SCeroSecObject:setOS(state)
	self.os = state
	self.osChecked = nil
end

-- The state, or nil plus a reason when it is not something the core can run on.
-- The refusal is sticky and logged once: a state the validator rejects is a
-- state we would rather stop touching than repair blindly.
--
-- And it is the ONE road a saved state comes in by. Everything that hands this
-- object a state writes self.os and then asks here -- a chunk coming back
-- (stateToIsoObject), a machine adopted from its sprite (stateFromIsoObject), a
-- computer put down out of somebody's hands (resetForPlacement, both through
-- osFromIsoObject) -- so the migration chain runs on every one of them and on none
-- of them twice: at the current version it has no steps to walk.
--
-- ONCE PER STATE, NOT ONCE PER READ.
--
-- Measured on the 300-machine rig (tests/hostile_test.lua, the county block) at
-- 104 ms a game minute with 40 machines running, and the validator was 0.887 of
-- the 0.894 ms one read costs -- 99%: it walks every node of the filesystem and
-- every table of the disk in the drive, and the sweep reads the state three times
-- a minute for every machine that is on, plus once per packet. So the answer is
-- remembered against the table it was given about, and a read whose table has not
-- been replaced returns it without walking anything.
--
-- WHAT THAT IS SAFE AGAINST, said plainly, because the memo must never let a
-- table nobody validated through. validate is a gate on what comes in from
-- OUTSIDE -- a save file, an item's modData, a client's packet -- and there are
-- five paths that hand this object one, all of them through setOS above
-- (stateToIsoObject, resetForPlacement, the chain and the BIOS repair below, and
-- the developer's reset). What every other writer in the mod does is write INSIDE
-- the table the gate already passed, through the write path's own rules: a file is
-- held to its bytes and its printable characters by setData, a name to
-- isValidFileName, a directory to MAX_DIR_ENTRIES, the tree to MAX_NODES. There is
-- no write in this engine that makes a state validate would refuse -- grepped, key
-- by key -- and the one that writes a whole subtree at once is the disk going into
-- the drive, which arrives already migrated and validated against the SLOT's
-- stricter bound (CeroSecOS.diskFromData -> insertDisk).
--
-- The two belts below stay on the read path and are not memoised: measured at
-- 0.0044 and 0.0005 ms, half a percent of the read between them, and what they
-- guard is the state as it will be SAVED (see below).
function SCeroSecObject:osState()
	if self.osBroken then return nil, "refused" end
	-- A state a LATER build wrote, which nothing here can read. Sticky like the
	-- refusal above, and for a stronger reason: those bytes are somebody else's and
	-- are not ours to repair (see the migration section of CeroSecOSState.lua).
	if self.osNewer then return nil, "newer" end

	-- This very table has been through the gate. The two belts still run -- they
	-- are cheap and they are not the validator -- and nothing else has to.
	if self.osChecked ~= nil and self.osChecked == self.os then
		CeroSecOS.unmountDev(self.os)
		CeroSecOS.checkMounts(self.os)
		return self.os
	end

	-- The chain. It used to be here that a version that was not the current one
	-- became a FRESH MACHINE -- self.os was replaced wholesale and the filesystem,
	-- the accounts and the disk in the drive went with it -- which is why
	-- STATE_VERSION had never been moved: bumping it would have wiped every
	-- computer in every save on the first load.
	local was = self.os
	local wasV = type(was) == "table" and was.v or nil
	local migrated, why = CeroSecOS.migrate(self.os, self:hostname())
	if migrated == nil then
		self.osNewer = true
		CeroSec.log(CeroSec.LOG_ERROR,
			"os newer than this build at " .. self.x .. "," .. self.y .. "," .. self.z
				.. ": v" .. tostring(wasV) .. " > v" .. tostring(CeroSecOS.STATE_VERSION))
		return nil, why
	end
	-- The mirror is only rebuilt when something actually moved -- a fresh machine,
	-- or a state the chain walked -- because this runs on every command and the
	-- mirror holds the very same table the rest of the time (see mirrorOS).
	if migrated ~= was or migrated.v ~= wasV then
		self:setOS(migrated)
		self:mirrorOS()
	end

	-- The devices under /dev are mounted for the length of one scheduler pass and
	-- taken away again by CeroSecOS.jobStep. This is the belt to that pair of
	-- braces: a
	-- command that died in the middle would leave nodes the validator refuses --
	-- a working machine turned "broken" by a light switch -- so the gate every
	-- read of the state goes through sweeps them first. On a healthy machine
	-- there is nothing to sweep and this walks an empty /dev.
	--
	-- ON EVERY READ AND NOT ONCE PER STATE, unlike the validator under it, and for
	-- a reason that is about the SAVE and not about the gate: `os` is a saved key
	-- (CeroSec.OBJECT_SAVE_KEYS), so a node left on /dev by a command that died
	-- mid-pass would go into gos_cerosec.bin, and the next load -- where the memo
	-- starts empty -- would validate it and refuse the machine. Sweeping it here is
	-- what stops that, and it has to happen whether this table has been through
	-- the gate before or not. The three mount windows are all in one pair of braces
	-- with no early return between them (CeroSecOS.jobStep, CeroSecOS.continue,
	-- Commands.complete), so the only thing that leaves a node behind is an error
	-- thrown inside one -- and an error is exactly what no `end` can catch.
	CeroSecOS.unmountDev(self.os)
	-- And the same belt under the mount table: a mount naming a drive with nothing
	-- in it is a mount nothing can walk through, and it is dropped rather than left
	-- to answer "no such file" about every path under it for ever. On a healthy
	-- machine this walks a table of one or of none.
	CeroSecOS.checkMounts(self.os)

	local ok, reason = CeroSecOS.validate(self.os)
	if not ok then
		self.osBroken = true
		CeroSec.log(CeroSec.LOG_ERROR,
			"os refused at " .. self.x .. "," .. self.y .. "," .. self.z
				.. ": " .. tostring(reason))
		return nil, reason
	end
	-- Through the gate, and remembered against the table it was asked about. After
	-- the refusal above and never before it: a memo set on the way in would be a
	-- memo standing for a walk that then said no.
	self.osChecked = self.os
	return self.os
end

-- The BIOS' own repair, and the only path that touches a state the validator
-- has already refused: a machine whose disk is unreadable is exactly the
-- machine this is for, so it runs on self.os raw rather than on osState().
--
-- Every state the chain can READ is repaired in place, which is what keeps /home:
-- the version is walked up to this build first and the system files are then put
-- back onto the machine that was already there. Only what the chain cannot read --
-- junk, nothing at all, a save older than the oldest step -- comes back as a fresh
-- machine, and that is migrate's decision and not this one's.
--
-- A state a LATER build wrote is not repaired at all. There is nothing here that
-- can read it, so a repair would be this build writing its own shape over a save
-- whose own author could still open it; the screen says what is wrong instead
-- (SCeroSecSystem:sayNoSystem) and the BIOS never asks its question.
--
-- true when the machine boots afterwards.
function SCeroSecObject:restoreOS()
	if self.osNewer then return false end
	local migrated = CeroSecOS.migrate(self.os, self:hostname())
	if migrated == nil then
		self.osNewer = true
		return false
	end
	if migrated ~= self.os then
		-- A fresh machine: it ships with everything restoreSystem would put back.
		self:setOS(migrated)
	else
		CeroSecOS.restoreSystem(self.os)
		-- Rewritten WHERE IT LIES, so the table is the same one and identity alone
		-- would say it had already been through the gate. This is the one path in
		-- the mod that remakes /etc, /bin and the filesystem root of a table it does
		-- not replace, so the memo is dropped by hand rather than by the setter.
		self.osChecked = nil
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
		-- And the note of the job that was holding this glass, put back -- but only
		-- for a job that really came back off the save (CeroSecJobs.restoreForeground
		-- has the reason it is not the repair's business). Once per machine per
		-- session, here, before anything reads the screen.
		CeroSecJobs.restoreForeground(self, self.console)
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
-- AND THE TABLE IS BOUNDED, both ways, because the key is not ours: it is the
-- online id and the TOKEN THE CLIENT PICKED (SCeroSecSystem.watcherKeyOf), so
-- one `open` per fresh random token used to add one permanent entry apiece.
-- Every entry is a sendServerCommand on every later screen of that machine --
-- paid by everybody who types at it afterwards, not by whoever sent the
-- packets -- and the minute sweep only drops an entry whose player has walked
-- off, which somebody standing at the keyboard never does.
--
-- Two rules, and the first is the one that matters:
--
--   * ONE LIVE WINDOW PER PLAYER PER MACHINE. A second `open` from the same
--     player is the same man at the same keyboard, so his earlier window goes
--     and is TOLD it has gone. The client already shuts its own previous box
--     (CeroSecTerminal.open, one terminal per player), so in play this
--     replaces nothing; what it bounds is a client that never closes.
--   * and WATCHERS_MAX of them per machine whatever the players, oldest first,
--     so a crowd of forged online ids cannot do by numbers what one cannot do
--     by tokens.
--
-- The same player is the same by idOf and not by the online id alone: split
-- screen is two survivors on one connection (SCeroSecSystem.watcherIdOf).
--

-- Eight windows at one computer. Twice what a room holds standing up, and
-- twice the four sessions the machine will take (CeroSecOS.PTY_MAX), so a
-- ceiling nothing legitimate reaches.
SCeroSecObject.WATCHERS_MAX = 8

-- The identity the two rules are keyed on, asked of the system rather than
-- worked out here: two answers to "the same player" is two rules.
function SCeroSecObject:watcherIdOf(playerObj)
	if playerObj == nil then return nil end
	local system = self.luaSystem
	if system == nil or system.watcherIdOf == nil then return nil end
	return system:watcherIdOf(playerObj)
end

function SCeroSecObject:watcherCount()
	if not self.watchers then return 0 end
	local n = 0
	for _ in pairs(self.watchers) do n = n + 1 end
	return n
end

-- One window told why it is over, and forgotten. The reason word reaches the
-- client's closedByServer, which shuts the box whatever the word is.
function SCeroSecObject:closeWatcher(key, reason)
	if not self.watchers then return end
	local watcher = self.watchers[key]
	if watcher == nil then return end
	self.watchers[key] = nil
	if watcher.player ~= nil and self.luaSystem ~= nil
			and self.luaSystem.replyClosed ~= nil then
		self.luaSystem:replyClosed(watcher.player, self.x, self.y, self.z,
			reason, watcher.token)
	end
end

-- The entry that goes when the machine is full: the oldest, by the counter each
-- one is stamped with as it goes in. `pairs` is no order at all, and a victim
-- chosen by it would be a victim chosen by the hash of somebody's token.
local function oldestKey(watchers)
	local key, seq = nil, nil
	for k, watcher in pairs(watchers) do
		local at = watcher.seq or 0
		if seq == nil or at < seq then key, seq = k, at end
	end
	return key
end

function SCeroSecObject:addWatcher(key, playerObj, token)
	if not self.watchers then self.watchers = {} end
	-- The same window asking again is not a second window: it overwrites, and
	-- neither rule below is asked anything about it.
	if self.watchers[key] == nil then
		-- His own earlier windows. Collected before any is dropped, because a
		-- table walked while it is being written to is a table Kahlua makes no
		-- promise about.
		local id = self:watcherIdOf(playerObj)
		if id ~= nil then
			local mine = nil
			for other, watcher in pairs(self.watchers) do
				if watcher.id == id then
					if mine == nil then mine = {} end
					mine[#mine + 1] = other
				end
			end
			if mine ~= nil then
				for i = 1, #mine do self:closeWatcher(mine[i], "replaced") end
			end
		end
		-- And the machine's ceiling, counting the one about to go in.
		while self:watcherCount() >= SCeroSecObject.WATCHERS_MAX do
			local victim = oldestKey(self.watchers)
			if victim == nil then break end
			self:closeWatcher(victim, "replaced")
		end
	end
	self.watcherSeq = (self.watcherSeq or 0) + 1
	self.watchers[key] = { player = playerObj, token = token, id = self:watcherIdOf(playerObj),
		seq = self.watcherSeq }
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

--
-- WHAT IS ALREADY ON A MACHINE NOBODY HAS EVER SWITCHED ON
--
-- Called from turnOn and from nowhere else, for a machine whose state was made a
-- moment ago and never for one that already had one: a computer somebody has used
-- is HIS, and a change that prefilled an existing machine would be a change that wrote
-- over somebody's accounts and somebody's files. The test is the one thing that
-- cannot lie about it -- whether self.os was a table before osState was asked --
-- and it is made in turnOn, before the call.
--
-- ONE CONSEQUENCE, and it is chosen rather than overlooked. resetForPlacement asks
-- osState too, so a computer somebody PICKS UP and PUTS DOWN has a state from that
-- moment on and comes up bare when it is finally switched on -- even if nobody ever
-- typed at it. That is the right way round: the test is "has this machine got a
-- filesystem", which is a fact, and the alternative is a flag saying "has anybody
-- really used it", which is a second opinion about the same thing and the sort of
-- thing that goes wrong in a save. The cost is that carrying an untouched office
-- machine out of its building loses it its profile -- and the paper in the drawer
-- is then a paper for a machine that is not there any more, which is a true thing
-- about a looted office.
--
-- Here and not in a migration step, for the reason the address is not in one
-- either: this needs the WORLD. Which premises the machine stands in is a question
-- about a square, and most machines in a save have no chunk loaded. turnOn is the
-- moment the chunk is certainly there, because the power check has just proved it.
--
-- The profile id, or nil for a machine left bare. The password it derived is
-- deliberately NOT answered and never logged: the letters exist for the length of
-- one call and the only place they are ever written is the paper in the drawer,
-- which derives them again for itself.
function SCeroSecObject:prefill(state)
	if state == nil then return nil end
	if not CeroSecContent.enabled() then return nil end
	local system = self.luaSystem
	if system == nil or system.secret == nil then return nil end

	-- Which premises, by the one rule there is about what a premises is
	-- (CeroSecNet.premisesOfSquare). nil is a computer in no building at all, which
	-- is what a player-built base is: it gets a bare machine, exactly as it gets no
	-- address and no telephone line.
	local b1, b2, _, pz, pk = CeroSecNet.premisesOf(self)
	if b1 == nil then return nil end

	-- And what the BUILDING's rooms are called, which is the second question and is
	-- asked only because the first so often has no answer: the shipped map names the
	-- shops inside a mall with zones and names a house with nothing at all.
	--
	-- The BUILDING's rooms and NOT this machine's own square's room, and that is not
	-- a detail: a paper in a drawer of the same premises asks the very same question
	-- (CeroSecNotes.onFillContainer) and the two must get one answer. Asked of the
	-- square, a house with a study in it answered "office" to the desk in the study
	-- and "residential" to the computer in the living room, and the note named a
	-- password no machine had. See the head of CeroSecNet.premisesRooms.
	local rooms = CeroSecNet.premisesRooms(self:getSquare(), pz, pk)

	-- AND THE ONE ROOM THIS MACHINE ITSELF STANDS IN, which is a different question
	-- from the one above and is asked for a different thing: the profile is the
	-- premises' and must be the same from every square of it, but whether a computer
	-- in a shop that sells computers is STOCK or the shop's own is a fact about this
	-- machine's own corner of the floor (CeroSecContent.isFloorRoom).
	--
	-- Proved on projectzomboid.jar 42.20.4:
	--
	--   zombie.iso.IsoGridSquare.getRoom() -> zombie.iso.areas.IsoRoom
	--   zombie.iso.areas.IsoRoom.getName() -> String
	--
	-- The live room and not the def, and it is answerable here for the one reason
	-- the whole prefill is here: the power check has just proved this machine's own
	-- chunk is in, and a square's room is set when its chunk is loaded.
	-- (IsoGridSquare.getRoomDef goes through getRoom at offset 1 and answers null
	-- without one, so there is no colder door to use.) A machine in no room at all
	-- answers nothing, which isFloorRoom reads as the floor.
	local room = nil
	do
		local square = self:getSquare()
		if square ~= nil and square.getRoom ~= nil then
			local at = square:getRoom()
			if at ~= nil and at.getName ~= nil then
				local name = at:getName()
				if type(name) == "string" and name ~= "" then room = name end
			end
		end
	end

	-- The premises' page of the register: what the OTHER machines of this premises
	-- already are. It is the system's and it is saved with the save, because a
	-- hash cannot know it and a chunk-bounded walk of the building cannot be trusted
	-- to -- the head of CeroSecContent.deskRole is the whole argument.
	if type(system.desks) ~= "table" then system.desks = {} end
	local desks = CeroSecContent.deskEntry(system.desks, b1, b2)

	local id, _, _, live, role = CeroSecContent.prefill(state, {
		secret = system:secret(),
		b1 = b1, b2 = b2, x = self.x, y = self.y, z = self.z,
		premises = pz, rooms = rooms, room = room, desks = desks,
		-- IS THIS THE MACHINE ITS PREMISES LEFT RUNNING (SCeroSecAuto)? Two things
		-- follow on the disk and both are the catalogue's: the desk is the one whose
		-- crontab does the nightly job -- or the job would be in the catalogue and on
		-- no machine in the county -- and somebody was more likely to have been left
		-- logged in at it. Read out of the system's own page rather than passed down
		-- from the caller, because the answer is written in the save and a flag handed
		-- through turnOn would be a second copy of it.
		auto = CeroSecAuto.isMachineAt(system, b1, b2, self.x, self.y, self.z),
		start = system:startTime(),
		now = CeroSecOS.clockOf(system:clockEnv()),
		-- The numbers a man at this desk could have rung, for the `cu` line in his
		-- shell history. Asked of the WORLD here because the catalogue has none and
		-- must not guess: a history naming an exchange that is not the one under the
		-- survivor's feet is the lie the BBS disk refuses to tell. A region the map
		-- named nothing in answers an empty list, and the history has no `cu` line.
		numbers = CeroSecNet.regionNumbers(self.x, self.y, b1, b2,
			CeroSecContent.DIAL_MAX),
	})
	if id == nil then return nil end

	-- SOMEBODY WHO NEVER LOGGED OUT.
	--
	-- About one machine in four (CeroSecContent.liveSession) -- one in TWO on a machine
	-- its premises left running, which is a machine nobody shut down -- and never the
	-- military post. The console was made a moment ago by turnOn, so this is the one place
	-- where what the catalogue decided about the last fortnight reaches the glass:
	-- the account, his home as the working directory, the moment wtmp says he sat
	-- down, and the environment a login hands a shell. A player who opens this
	-- machine gets his prompt and is asked for nothing.
	--
	-- `booted` IS LEFT ALONE, deliberately: the BIOS lines and the motd still print,
	-- because a screen that came up already at a prompt with nothing above it reads
	-- as a machine that is broken rather than as a machine somebody left running.
	--
	-- AND A DECLARED DEVIATION, because it is one. A real Unix cannot restore a
	-- session across a power cut and neither can this one -- a survivor's own machine
	-- comes back to `login:` every time, and that is right. What this does is choose
	-- the story: wtmp says a man logged in on the morning of it and never logged out,
	-- and the console agrees with wtmp instead of with the boot sequence. It is the
	-- only place in the catalogue where the fiction is worth the fidelity, it is
	-- stated here rather than hidden, and it happens once in the life of a machine.
	if type(live) == "table" and type(live.user) == "string"
			and type(self.console) == "table" then
		local user = CeroSecOS.getUser(state, live.user)
		if user ~= nil then
			self.console.user = live.user
			self.console.cwd = user.home or "/"
			self.console.loginAt = live.at
			self.console.shvars = CeroSecOS.loginVars(user.home)
			self.console.shexport = CeroSecOS.loginExported()
			self.console.shfuncs = {}
			CeroSec.log("computer at " .. self.x .. "," .. self.y .. "," .. self.z
				.. " was left logged in as " .. live.user)
		end
	end
	self:mirrorOS()
	CeroSec.log("computer at " .. self.x .. "," .. self.y .. "," .. self.z
		.. " came up prefilled as " .. id .. " (" .. tostring(role)
		.. ", room " .. tostring(room) .. ")")
	return id
end

function SCeroSecObject:turnOn()
	if self.on then return false end
	if not self:hasPower() then return false end
	self.on = true
	-- The switch is on the moment the machine is: this is the only place it
	-- is set to true, so a save from before it existed only gets one once
	-- something here actually gets switched on again.
	self.switchOn = true
	self:reindex()
	-- A fresh screen, with the BIOS still to be typed on it. It was just made
	-- here, so there is nothing to repair and nothing to check.
	self.console = CeroSec.newConsole()
	self.consoleChecked = true
	-- When it came up, for ruptime. Runtime state like the jobs: a server that
	-- came back up forgets it, and ruptime counts from the restart.
	self.upMs = getTimestampMs()
	-- Whether there was a machine here at all a moment ago. Read BEFORE osState is
	-- asked, because osState is what makes one: after the call there is always a
	-- table and nothing can tell the two cases apart any more.
	--
	-- Or the developer's reset said so, which is the one other way in
	-- (resetMachine below). It has to be a flag and not the absence of a state,
	-- because the absence does not survive being LOOKED at: osState makes a fresh
	-- machine out of nothing, so the debug window's own detail block -- which asks
	-- osState of the selected machine every two seconds -- would give a machine its
	-- state back between the reset and the press that was meant to prefill it.
	local bare = type(self.os) ~= "table" or self.osFresh == true
	self.osFresh = nil
	local state = self:osState()
	-- What is already on it, once in the life of the machine (see prefill above).
	-- Before identify, so that the hostname a profile gives it is the name that
	-- goes into /etc/hosts and onto the prompt.
	if bare then self:prefill(state) end
	-- Which building it stands in, and therefore its address. Here rather than at
	-- the first command because the power check has just proved the chunk is
	-- loaded, which is the one thing working a building out needs.
	CeroSecNet.identify(self.luaSystem, self, state)
	self:apply()
	self:playSound("CeroSecBootStart")
	-- @reboot, which is the one crontab line that is not a time: the machine has
	-- just come up, so it is due now and never again until it comes up again.
	CeroSecJobs.atBoot(self.luaSystem, self)
	return true
end

-- switchOff, when true, is a hand actually reaching for the switch: `halt`,
-- `shutdown`, the menu's "Turn off computer" and the debug window's off button
-- all pass it, and it is what leaves self.switchOn false behind them so an
-- outage later finds nothing to restart. Left out (checkPower, below, and
-- SCeroSecSystem:reboot's own call) it is a wire going, not a switch, and
-- self.switchOn is untouched -- which is the whole of what tells the two apart
-- come the next minute the power sweep looks at this machine.
function SCeroSecObject:turnOff(switchOff)
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
	-- A hand at the switch leaves it off; an outage does not touch it, which
	-- is what lets the power sweep tell the two apart afterwards.
	if switchOff then self.switchOn = false end
	self:reindex()
	-- Everything that was running is gone with the power, which is what a
	-- switch at the back of the case does. reboot goes through here too, so a
	-- machine that comes back comes back running nothing.
	CeroSecJobs.killAll(self)
	-- And the minute cron last looked at goes with them: a machine that comes
	-- back is a machine that has only just come into view, so it runs nothing for
	-- the minute it arrived in and nothing at all for the minutes it was dark.
	self.cron = nil
	-- And the stations the TNC had heard. That list is RAM in a box on the desk --
	-- a TNC-2 kept MHEARD in memory with no battery behind it -- so the power going
	-- empties it, and `MH` on a machine that has just come up prints nothing.
	self.heard = nil
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
	-- The menu's own hand at the switch: a player asking for this machine to
	-- go off is a player who means it to stay off.
	if self.on then return self:turnOff(true) end
	return self:turnOn()
end

--
-- The developer's reset
--
-- A MACHINE THAT HAS NEVER BEEN USED, made out of one that has. It exists for the
-- one thing nothing else in the mod can do: prefill runs at the FIRST power-on and
-- at no other moment, so a machine whose first power-on went wrong halfway through
-- is a machine there is no way to try again on -- it is half filled for ever, and
-- the bug that half filled it cannot be seen a second time. The debug window's own
-- button (docs/DEBUG.md), behind CeroSec.debugAllowed and nothing a player can
-- reach.
--
-- OFF ONLY, and the refusal is the window's to print (CeroSecDebug.resetRefusal):
-- everything below is what turnOff already did, plus the disk, and a machine that
-- is running would have its jobs stopped and its screen taken away by a button
-- that says nothing about either.
--
-- THE DISK STAYS IN THE DRIVE. What is in the slot is a thing in the WORLD -- a
-- player carried it here -- and it lives in the machine's state only because that
-- is where the state serializer can keep it (see the drive section above). So it
-- is lifted out, the state is thrown away, and it is put back into the fresh one:
-- the alternative is a reset that destroys somebody's floppy, and there is
-- deliberately no "eject it to the floor first" here either, for the reason the
-- pickup path gives -- a disk in a drive is in the drive.
--
-- And the NOTE in the drawer is not touched: that bookkeeping is the system's
-- (CeroSecNotes.premisesMark) and it is about a premises and not about a machine.
-- The paper that is already in a desk names a password derived from the save's
-- secret and the premises, both of which this leaves exactly as they are, so the
-- machine that comes back up is a machine that paper still opens.
--
-- true when the machine was reset.
function SCeroSecObject:resetMachine()
	if self.on then return false end

	-- Out of the state before the state goes.
	local floppy, fdtype = nil, nil
	if type(self.os) == "table" then
		floppy = self.os.floppy
		fdtype = self.os.fdtype
	end

	-- Everything a machine that stopped has stopped, said in the order turnOff says
	-- it: the jobs and the pending order with them (CeroSecJobs.killAll drops
	-- self.rebooting and takes the machine off the scheduler's book), then the
	-- windows, which are told rather than forgotten.
	CeroSecJobs.killAll(self)
	if self.luaSystem and self.luaSystem.evictWatchers then
		self.luaSystem:evictWatchers(self, "off")
	else
		self:dropWatchers()
	end
	-- No sessions to close: they went when the machine went off, which is the one
	-- state this is allowed in.
	self:setOS(nil)
	-- Both sticky refusals with it. They were about the state that has just gone,
	-- and a fresh machine that came up "broken" would be a machine nothing could
	-- explain.
	self.osBroken = nil
	self.osNewer = nil
	self.console = nil
	self.consoleChecked = nil
	self.heard = nil
	self.cron = nil
	self.upMs = nil
	-- And the one thing that is not an erasure: what the next power-on is to do
	-- (see turnOn).
	self.osFresh = true

	if floppy ~= nil then
		-- osState on a nil state is what MAKES a fresh machine, so this is the same
		-- machine the next power-on would have found -- with the drive filled again.
		local state = self:osState()
		if state ~= nil then
			state.floppy = floppy
			state.fdtype = fdtype
		end
	end

	self:syncDisk()
	self:mirrorOS()
	self:publishOS()
	self:updateOnClient()
	CeroSec.log("computer at " .. self.x .. "," .. self.y .. "," .. self.z
		.. " was reset to a machine nobody has used"
		.. (floppy ~= nil and ", disk kept in the drive" or ""))
	return true
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
