require "CeroSec/CeroSecDefs"

--
-- The hardware modules
--
-- A computer does not talk to a door because the door is a door. It talks to it
-- because somebody climbed up with a screwdriver and wired a box to it. Eight
-- boxes, and each one buys exactly one thing:
--
--   contact   a magnetic contact   -> the machine can SEE a door or a window
--   relay     a relay              -> the machine can throw a light switch
--   strike    an electric strike   -> the machine can work a door's lock
--   operator  a door operator      -> the machine can open and shut a door
--   curtain   a curtain motor      -> it can draw and open a curtain
--   window    a window operator    -> it can raise and shut a sash
--   appliance an appliance switch  -> it can start a stove or a washer
--   genset    a generator switch   -> it can start and stop a generator
--
-- Nothing else changed about /dev: a device that is there is the same device it
-- always was, with the same words and the same refusals. What the modules decide
-- is WHICH devices are there at all (SCeroSecDevices.classify), and that is the
-- whole of the feature.
--
-- The sandbox option is the switch, and it is ON by default: a world where every
-- door in Knox County answers a computer nobody wired is the world this rung was
-- asked to stop being the only one on offer. A server owner who liked that world
-- turns CeroSec.HardwareRequired off and gets it back, untouched, down to the
-- device numbers.
--
-- Where the modules live
--
-- On the OBJECT, in its own modData, under this mod's own name:
--
--   door:getModData().cerosec = { strike = true, contact = true }
--
-- and nowhere else. Not in the machine's state -- a computer carried out of the
-- building must not take the building's wiring with it -- and not in a book on
-- the side, which would be a second truth to keep in step with the world.
--
-- IsoObject modData is saved with the chunk and travels to the other players on
-- transmitModData(); both are proved at the bytecode in
-- docs/notes/modules-proofs.md, and the second one has a server branch of its
-- own (GameServer.sendObjectModData), which matters here because our writes
-- happen on the server and most of vanilla's happen on a client.
--
-- A player-built door is an IsoThumpable, which keeps a modData field of its OWN
-- rather than the one it inherits -- and saves it itself, under its own flag
-- bit. So the same line of Lua works on both and survives a save on both; the
-- difference is invisible from here and is written down in the proofs.
--
-- Why this file is shared
--
-- Two sides ask the same questions of the same object. The server asks them to
-- decide what is under /dev and to carry an install out; the client asks them to
-- decide what to put on a right-click menu and why an entry is greyed. A rule
-- written twice is a rule that drifts, so it is written here once, and the only
-- thing either side adds is what it does with the answer.
--

CeroSecModules = CeroSecModules or {}

-- The key the modules hang on, inside the object's own modData. The mod's name,
-- lower case, like everything else this mod writes into somebody else's table.
CeroSecModules.DATA_KEY = "cerosec"

--
-- The shape of that table, and how it is changed
--
-- A door is a save file too. What is screwed to it is written into the CHUNK and
-- comes back when the chunk does, so the ids in there are as persistent as the
-- machine's filesystem and are owed the same promise: a change that renames one, or
-- drops one, or changes what one MEANS does not cost a survivor the hardware he
-- climbed up to fit.
--
-- So the table carries a version, and a chain beside it:
-- CeroSecModules.MIGRATIONS[n] takes the table at n - 1 and leaves it at n.
--
-- A table with NO version is version 1, not version 0, and that is not a guess: the
-- ids in a table written before this change are the ids version 1 has, so an absent
-- number reads as the shape it really is.
--
-- WHERE THE NUMBER GETS WRITTEN, corrected 2026-09-14. This used to say the stamp
-- goes on at the next WRITE (setOn) and never on a read. That was true only because
-- VERSION was 1 and the walk in `migrate` therefore had no iteration to make: the
-- walk has always ended each step with `fitted[VERSION_KEY] = n`, so the moment
-- VERSION moved to 2 the first READ of an older table became the thing that stamps
-- it -- on a client as well as on the server. That is harmless in both places and is
-- left as it is: on a client the write lands in a table nobody else will ever see,
-- and on the server it lands in the chunk, which is where the answer belongs. What
-- would NOT be harmless is a step that did real work being run twice, and the stamp
-- is exactly what stops that.
--
-- VERSION 2 as of the change that added the `pre` key below. Strictly it did not have
-- to move -- an absent mark reads as "not pre-fitted", which is the old behaviour on
-- every fixture in every save, and the step below therefore has nothing to convert.
-- It moves anyway, and the reason is a reader and not the code: this table now has a
-- key in it that is not one of the four ids and does not behave like one, and a shape
-- that changed without its number moving is a shape nothing can be held to afterwards.
-- The cost of moving it is one write of one number into a table that was going to be
-- read anyway.
--
-- AND IT DID NOT MOVE FOR THE MOTOR RUNG'S FOUR IDS, which is worth writing down
-- because the rule above says a shape change moves it and four new keys look
-- like one.
--
-- They are not. A key whose absence reads as the OLD BEHAVIOUR is not a shape
-- change, and an absent `curtain` reads as "no curtain motor on this fixture",
-- which is true of every fixture in every save written before this rung --
-- nobody had one to fit. There is nothing for a step to convert, and a step that
-- converted nothing would be a number moved to say something that did not
-- happen.
--
-- It is the `pre` key read the other way round. That one moved the number
-- although it had nothing to convert either, and the reason was a reader: `pre`
-- is a key in this table that is NOT one of the ids and does not behave like
-- one. These four are ids and behave exactly like the four beside them, so
-- there is nothing for a reader to be surprised by and nothing to hold the
-- shape to.
CeroSecModules.VERSION = 2
CeroSecModules.VERSION_KEY = "v"
-- MIGRATIONS[n] takes the table at n - 1 and leaves it at n.
--
-- [2] has nothing to do and says so out loud rather than being absent: a gap in the
-- chain is what `migrate` refuses to walk (it answers false and the fixture reads as
-- bare), so "no conversion needed" has to be written as a step that converts nothing.
-- What version 1 lacked is the `pre` mark, and the absence of it is already the right
-- answer for every fixture written before this change -- none of them was fitted by
-- anybody but a player.
CeroSecModules.MIGRATIONS = {}
CeroSecModules.MIGRATIONS[2] = function(_fitted) end
CeroSecModules.OLDEST_VERSION = 1

-- AND ONE KEY THAT IS NOT A MODULE: was this fixture wired before the outbreak?
--
-- The automation needs to fit a building's hardware ONCE and never again, and
-- "once" cannot be "when the modules are not there": a survivor who unscrews the
-- relay out of a light switch for the item would find it back on the plate the next
-- minute, which is a mod undoing a player's own work. So a pre-fitted fixture
-- remembers that it was pre-fitted, the mark outlives every module coming off, and
-- the walk never touches that fixture again.
--
-- It costs a handful of bytes in the chunk for the rest of the save on a fixture a
-- survivor has stripped bare, and that is the price of the promise. The last module
-- off takes the table with it exactly as before on every fixture a PLAYER wired: the
-- mark is the only thing that keeps one alive (setOn).
--
-- ADDING THIS KEY IS NOT A SHAPE CHANGE and CeroSecModules.VERSION does not move
-- for it. An absent mark reads as "not pre-fitted", which is the old behaviour
-- everywhere, and there is nothing in an older table for a step to convert. Bumping
-- the number would be worse than useless here: `migrate` stamps the new number on
-- the table it walks, and a table is walked on every READ -- including on a client,
-- where a write into a door's modData goes nowhere anybody will ever see.
CeroSecModules.PRE_KEY = "pre"

-- Which shape this table is in. A number that is not a whole one in range is not a
-- version anything here wrote, and it reads as the oldest -- the same answer an
-- absent one gets, for the same reason: the ids are what they are.
function CeroSecModules.versionOf(fitted)
	if type(fitted) ~= "table" then return nil end
	local v = fitted[CeroSecModules.VERSION_KEY]
	if type(v) ~= "number" or v ~= math.floor(v) then return CeroSecModules.OLDEST_VERSION end
	if v < CeroSecModules.OLDEST_VERSION then return CeroSecModules.OLDEST_VERSION end
	return v
end

-- The table, walked up to this build, in place. true when it is readable at all.
--
-- A table a LATER build wrote is left exactly as it is and answers false: the ids in
-- it may mean something this build does not know, and reading them anyway would be
-- this build deciding what somebody else's hardware is. A door like that has no
-- modules as far as this build is concerned -- which is a door that does nothing,
-- not a door that loses its boxes -- and putting the newer mod back brings them all
-- back, because nothing here ever wrote over them.
function CeroSecModules.migrate(fitted)
	if type(fitted) ~= "table" then return false end
	local v = CeroSecModules.versionOf(fitted)
	if v > CeroSecModules.VERSION then return false end
	for n = v + 1, CeroSecModules.VERSION do
		local step = CeroSecModules.MIGRATIONS[n]
		if type(step) ~= "function" then return false end
		step(fitted)
		fitted[CeroSecModules.VERSION_KEY] = n
	end
	return true
end

-- The sandbox option, declared in 42/media/sandbox-options.txt and read below.
CeroSecModules.SANDBOX = "HardwareRequired"

--
-- The eight of them.
--
-- id       what the modData says, and the only name the rest of the mod uses
-- item     the item a survivor carries and the install takes out of his hands
-- skill    Perks.Electricity at or above this, to put it on or take it off
-- time     the timed action's length, in the game's own ticks, before the perk
--          takes its bite out of it (see ISCeroSecModuleAction)
-- xp       Electricity experience for fitting one, and none for taking it off
--
-- The levels are the size of the job and not a difficulty curve: a contact is
-- two wires and a magnet on a frame, a relay is the same two wires behind a
-- plate somebody has to be sure is dead first, a strike replaces the keep of a
-- lock, and an operator is a motor, an arm and a limit switch. One, one, two,
-- three -- and see the note over the list for the four the motor rung added.
--
-- The experience is set against vanilla's own electrical job: repairing a
-- generator is 5 (shared/TimedActions/ISFixGenerator.lua:71,
-- addXp(self.character, Perks.Electricity, 5)). A contact is less than that, an
-- operator more, and nothing here is worth a level.
--
-- The order is the order they are OFFERED in on the menu, which is the order a
-- survivor meets them in: what he can fit at level one first.
--
-- THE FOUR ADDED BY THE MOTOR RUNG GO ON THE END, and not in level order.
--
-- The first four have been in that order on the right-click menu since rung 4f
-- and a survivor knows where they are; a menu that reshuffles itself under him
-- because a fifth box was written is worse than a menu whose levels do not run
-- downhill. So the rule above is now the rule for each BATCH and not for the
-- whole list, and it is written down rather than left for somebody to notice.
--
-- The levels are the size of the job, like the first four. A curtain motor is a
-- small motor on a rail and a limit switch, which is the operator's job on a
-- tenth of the weight -- two. An appliance switch is a contactor behind a plate
-- somebody has to be sure is dead first, which is the relay's job on a circuit
-- that can kill him -- two. A window operator is an arm, a motor and a sash that
-- has to stop in the right place -- three, like the door operator it is. A
-- generator switch is three because of what is on the other side of it.
CeroSecModules.LIST = {
	{ id = "contact",   item = "CeroSec.MagneticContact", skill = 1, time = 80,  xp = 3 },
	{ id = "relay",     item = "CeroSec.Relay",           skill = 1, time = 100, xp = 3 },
	{ id = "strike",    item = "CeroSec.ElectricStrike",  skill = 2, time = 120, xp = 5 },
	{ id = "operator",  item = "CeroSec.DoorOperator",    skill = 3, time = 150, xp = 8 },
	{ id = "curtain",   item = "CeroSec.CurtainMotor",    skill = 2, time = 100, xp = 5 },
	{ id = "appliance", item = "CeroSec.ApplianceSwitch", skill = 2, time = 110, xp = 5 },
	{ id = "window",    item = "CeroSec.WindowOperator",  skill = 3, time = 150, xp = 8 },
	{ id = "genset",    item = "CeroSec.GeneratorSwitch", skill = 3, time = 140, xp = 8 },
}

-- The tool the job needs, whichever module it is. Vanilla's own recipes ask for
-- a screwdriver by tag (`tags[base:screwdriver]`), and this asks for the item,
-- because what is being looked for here is one thing in a survivor's bag and not
-- a slot in a crafting table.
CeroSecModules.TOOL = "Base.Screwdriver"

local byId, byItem = nil, nil

-- Built once, on the first question asked, because a list of four walked on
-- every right-click of every door in a building is a cost paid for nothing.
local function index()
	if byId ~= nil then return end
	byId, byItem = {}, {}
	for i = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[i]
		byId[module.id] = module
		byItem[module.item] = module
	end
end

function CeroSecModules.byId(id)
	if type(id) ~= "string" then return nil end
	index()
	return byId[id]
end

function CeroSecModules.byItem(fullType)
	if type(fullType) ~= "string" then return nil end
	index()
	return byItem[fullType]
end

--
-- Is the hardware required at all?
--
-- Read the way vanilla reads its own grouped options -- `SandboxVars.Map and
-- (SandboxVars.Map.AllowMiniMap == true)`, client/ISUI/Maps/ISMiniMap.lua:687 --
-- because SandboxVars is a plain table and a group nobody declared is simply not
-- in it.
--
-- And it fails CLOSED: anything that is not the literal false is "required".
-- A sandbox file that failed to load, a save from before this rung, a group that
-- is not there -- every one of those is a world where doors are NOT wired, which
-- a player sees at once and can fix from the sandbox screen. The other way round
-- is a world that quietly went back to magic and looks exactly like a working
-- one.
function CeroSecModules.required()
	local group = SandboxVars and SandboxVars.CeroSec
	if group == nil then return true end
	return group[CeroSecModules.SANDBOX] ~= false
end

--
-- What is fitted to one object
--
-- Always a table, never nil: "nothing is fitted" is an answer and not a missing
-- one, and every caller reads it the same way. Nothing but the ids in
-- CeroSecModules.LIST is looked at and nothing but `true` counts, so somebody else's writing in that
-- table -- or a forged one out of an old save -- fits no hardware.
--
function CeroSecModules.installedOn(object)
	local out = {}
	if object == nil then return out end
	if type(object.hasModData) ~= "function" or not object:hasModData() then return out end
	local data = object:getModData()
	if data == nil then return out end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then return out end
	-- The chain, on the way in and in one place: this is the ONE function that reads
	-- what is screwed to an object, so a table written by an older build is walked up
	-- here or nowhere. One a LATER build wrote is not read at all -- an empty answer,
	-- which is a door that does nothing rather than a door whose boxes were guessed
	-- at (see CeroSecModules.migrate).
	if not CeroSecModules.migrate(fitted) then return out end
	for i = 1, #CeroSecModules.LIST do
		local id = CeroSecModules.LIST[i].id
		if fitted[id] == true then out[id] = true end
	end
	return out
end

function CeroSecModules.installedIn(fitted, id)
	return type(fitted) == "table" and fitted[id] == true
end

--
-- WAS THIS FIXTURE WIRED BEFORE THE OUTBREAK? (see PRE_KEY)
--
-- true also for a table this build cannot read -- one a LATER build wrote. That is
-- not a shortcut: the answer is what the pre-fitting walk uses to decide whether to
-- LEAVE A FIXTURE ALONE, and a table whose ids may mean something this build does not
-- know is the last thing to write into. So "unreadable" reads as "already done",
-- which is the safe direction for both readings of the question.
function CeroSecModules.preFitted(object)
	if object == nil then return false end
	if type(object.hasModData) ~= "function" or not object:hasModData() then return false end
	local data = object:getModData()
	if data == nil then return false end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then return false end
	if not CeroSecModules.migrate(fitted) then return true end
	return fitted[CeroSecModules.PRE_KEY] == true
end

-- The mark, and only the mark: the modules themselves go on through setOn, which is
-- the one writer. The server's, like every other write into a fixture's modData.
-- false when there is nothing there to mark, which is a fixture nothing was fitted
-- to and therefore nothing to remember.
function CeroSecModules.markPreFitted(object)
	if object == nil then return false end
	local data = object:getModData()
	if data == nil then return false end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then return false end
	if not CeroSecModules.migrate(fitted) then return false end
	fitted[CeroSecModules.PRE_KEY] = true
	object:transmitModData()
	return true
end

--
-- Screwing one on, and taking it off
--
-- The server's, and only the server's: what reaches a client is the object's
-- modData through transmitModData, which has a server branch of its own
-- (GameServer.sendObjectModData -- the proofs, 2) and marks the chunk to be
-- written out on the way past (flagForHotSave).
--
-- The last module off takes the table with it rather than leaving an empty one
-- behind. IsoObject.save skips a modData table that isEmpty() and this one would
-- not be empty -- it would hold one empty table -- so a door somebody wired and
-- unwired would carry a few bytes for the rest of the save otherwise.
function CeroSecModules.setOn(object, id, on)
	if object == nil or CeroSecModules.byId(id) == nil then return false end
	local data = object:getModData()
	if data == nil then return false end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then
		if not on then return true end
		fitted = {}
		data[CeroSecModules.DATA_KEY] = fitted
	end
	if on then
		fitted[id] = true
		-- And the shape it is in, stamped on the write. This is the server, and the
		-- only place a door's modules are ever written: a number put on here travels
		-- with the table (transmitModData) and is saved with the chunk, so the day a
		-- step is written there is something for it to count against. A table with no
		-- number is the oldest shape and is read as one (CeroSecModules.versionOf), so
		-- nothing depends on the stamp having happened.
		fitted[CeroSecModules.VERSION_KEY] = CeroSecModules.VERSION
	else
		fitted[id] = nil
		local left = false
		for i = 1, #CeroSecModules.LIST do
			if fitted[CeroSecModules.LIST[i].id] == true then left = true end
		end
		-- The last box off takes the table with it, version stamp and all: a door
		-- somebody wired and unwired carries nothing, exactly as it did before the
		-- stamp existed. IsoObject.save skips an EMPTY modData and a table holding only
		-- a number is not empty, so leaving one behind would be a few bytes in every
		-- chunk for the rest of the save.
		--
		-- UNLESS THE FIXTURE WAS WIRED BEFORE THE OUTBREAK, in which case the mark is
		-- the whole point of it and outlives every module (see PRE_KEY): a survivor who
		-- strips a pre-fitted switch must not find the relay back on it a minute later.
		if not left and fitted[CeroSecModules.PRE_KEY] ~= true then
			data[CeroSecModules.DATA_KEY] = nil
		end
	end
	object:transmitModData()
	return true
end

--
-- Where a module may go
--

-- The room a square is in, by its raw id ("kitchen", "office"), or nil. Here
-- rather than in SCeroSecDevices, where it used to live alone, because the rule
-- below is asked by the right-click menu too and the menu cannot load a server
-- file.
function CeroSecModules.roomName(square)
	if square == nil then return nil end
	local room = square:getRoom()
	if room == nil then return nil end
	local name = room:getName()
	if type(name) ~= "string" or name == "" then return nil end
	return name
end

-- Does this map door's lock stop anybody? Its own isExterior() first -- the
-- square carries the exterior flag and the far side is a building with a def, or
-- the other way round -- and then the rooms, because a door whose two sides have
-- a room on exactly one of them is a way out of the building whatever the tile
-- flags say.
--
-- The whole reasoning, and the couldBeOpen bytecode it is read off, is at the
-- head of SCeroSecDevices.lua: from inside a building a locked map door always
-- opens, so a lock on an interior door is a device that lies -- and a strike on
-- one is a box that does nothing, which is why this is what an install asks too.
function CeroSecModules.doorLocks(door)
	if door:isExterior() then return true end
	local here = CeroSecModules.roomName(door:getSquare())
	local there = CeroSecModules.roomName(door:getOppositeSquare())
	if here == nil and there == nil then return false end
	return here == nil or there == nil
end

-- One leaf of a double or a garage door. Vanilla's own way of asking, both
-- public statics, both -1 for an object with no such property on it
-- (server/BuildingObjects/ISBuildUtil.lua:556, ISDoubleDoor.lua:315). Here for
-- the same reason doorLocks is: an operator on one leaf of a garage door is a
-- motor on a door the machine will not work, because ToggleDoorSilent moves one
-- object and vanilla's own toggle walks every leaf.
function CeroSecModules.isManyDoors(object)
	if IsoDoor == nil then return false end
	return IsoDoor.getDoubleDoorIndex(object) ~= -1
		or IsoDoor.getGarageDoorIndex(object) ~= -1
end

-- Is it a door at all -- a map one or a built one? Vanilla asks the pair the
-- same way (ISWorldObjectContextMenu.isThumpDoor, :2176).
function CeroSecModules.isDoor(object)
	if object == nil then return false end
	if instanceof(object, "IsoDoor") then return true end
	return instanceof(object, "IsoThumpable") and object:isDoor() == true
end

function CeroSecModules.isWindow(object)
	return object ~= nil and instanceof(object, "IsoWindow")
end

function CeroSecModules.isLightSwitch(object)
	return object ~= nil and instanceof(object, "IsoLightSwitch")
end

--
-- The fixtures the motor rung added, and the ONE thing worth knowing about
-- curtains: there are two of them and they are not the same object.
--
-- A window's curtain and a player-built frame's are an IsoCurtain of their own,
-- on the square's object list like any other fixture. A DOOR's curtain is a pair
-- of fields on the door -- `hasCurtain` and `curtainOpen` -- and there is no
-- second object at all: IsoDoor.HasCurtains() answers THE DOOR when hasCurtain
-- is set and null otherwise (offsets 0-12), which is why vanilla's own menu
-- re-fetches before it reads a sprite (ISWorldObjectContextMenu.lua:2238).
--
-- So a curtain motor goes on either, and the two are told apart here once
-- (docs/notes/actuators.md, 1).
function CeroSecModules.isCurtain(object)
	return object ~= nil and instanceof(object, "IsoCurtain")
end

-- A door that has a sheet on it. Never a curtain the module could go on TWICE:
-- the door carries the fields and the door is what a motor is screwed to.
function CeroSecModules.doorHasCurtain(object)
	if object == nil then return false end
	if not instanceof(object, "IsoDoor") then return false end
	return object:HasCurtains() ~= nil
end

function CeroSecModules.hasCurtain(object)
	return CeroSecModules.isCurtain(object) or CeroSecModules.doorHasCurtain(object)
end

-- The oven, the microwave AND the coffee machine, which are one class in this
-- game: isMicrowave() and isStove() read the CONTAINER's type and not the
-- sprite, and newtiledefinitions.tiles.txt gives every GroupName = Coffee tile
-- `IsoType = IsoStove` with `container = stove` (actuators.md, 3). So a coffee
-- machine needs nothing of its own and gets none.
function CeroSecModules.isStove(object)
	return object ~= nil and instanceof(object, "IsoStove")
end

-- The laundry. Three classes and not four: IsoStackedWasherDryer is left out
-- deliberately and the reason is the study's own -- no tile in any of the game's
-- five .tiles.txt files carries that IsoType, so nothing on the map makes one,
-- and it is the one of the four that splits into TWO switches
-- (setWasherActivated / setDryerActivated). Half a device on an object nobody
-- has is worse than no device.
function CeroSecModules.isWasher(object)
	if object == nil then return false end
	return instanceof(object, "IsoClothingWasher")
		or instanceof(object, "IsoClothingDryer")
		or instanceof(object, "IsoCombinationWasherDryer")
end

function CeroSecModules.isGenerator(object)
	return object ~= nil and instanceof(object, "IsoGenerator")
end

-- Anything a module of any kind could go on. What the right-click menu asks
-- first, so that a survivor right-clicking a fridge is offered nothing at all
-- rather than a menu of eight refusals.
function CeroSecModules.isFittable(object)
	return CeroSecModules.isDoor(object) or CeroSecModules.isWindow(object)
		or CeroSecModules.isLightSwitch(object)
		or CeroSecModules.isCurtain(object) or CeroSecModules.isStove(object)
		or CeroSecModules.isWasher(object) or CeroSecModules.isGenerator(object)
end

-- May this module go on this object? true, or false and the reason in one word,
-- which is the key the menu greys the entry with
-- (Tooltip_CeroSec_Module<Reason>).
--
-- The refusals are the ones a survivor can DO something about, and each is a
-- fact about the object and not about him: the wrong sort of fixture, a door the
-- lock means nothing on, a leaf of a garage door no machine will work. A window
-- that is boarded or a stove that is broken is NOT one of these: those are facts
-- about what the fixture is doing today, they are the device's refusals rather
-- than the install's, and a motor screwed to a boarded window works the day the
-- boards come off. What he
-- is carrying, what he knows and whether he is standing there are asked
-- elsewhere, because those are facts about HIM.
function CeroSecModules.fitsOn(object, id)
	local module = CeroSecModules.byId(id)
	if module == nil or object == nil then return false, "fixture" end

	if id == "relay" then
		if not CeroSecModules.isLightSwitch(object) then return false, "fixture" end
		return true
	end

	if id == "contact" then
		if CeroSecModules.isDoor(object) or CeroSecModules.isWindow(object) then return true end
		return false, "fixture"
	end

	if id == "curtain" then
		if CeroSecModules.hasCurtain(object) then return true end
		-- A door with no sheet on it is not a refusal a survivor can do anything
		-- about by arguing: he hangs a sheet and the entry appears.
		return false, "fixture"
	end

	if id == "appliance" then
		if CeroSecModules.isStove(object) or CeroSecModules.isWasher(object) then
			return true
		end
		return false, "fixture"
	end

	if id == "genset" then
		if CeroSecModules.isGenerator(object) then return true end
		return false, "fixture"
	end

	--
	-- THE WINDOW OPERATOR, and the sentence that used to be here was not exact.
	--
	-- It said: "there is no window actuator in this mod and there is none in the
	-- game either -- the only call that moves a sash is
	-- IsoWindow.ToggleWindow(IsoGameCharacter), which wants a survivor standing
	-- at it". The call is right and the reason was not. ToggleWindow never
	-- DEREFERENCES the character: every use of the argument is behind a null
	-- guard (the barricade test at offsets 37-49 is skipped for null, the
	-- IsoZombie test at 93-97 is false for it, the music call at 166-197 is
	-- behind an ifnull) and the sync at offset 147 is unconditional. What is true
	-- is three other things, all in the bytecode and all of them side effects a
	-- motor really would have:
	--
	--   offsets 50-54   `locked = false`, unconditionally, before the sash moves.
	--                   The motor throws the catch as it opens, which is what an
	--                   operator does and why `win0` keeps the latch and this
	--                   keeps the sash.
	--   offsets 86-118  the house alarm goes off, every time, when the sash ends
	--                   up open: the sandbox check is consulted only for an
	--                   IsoZombie, so a null character falls straight into
	--                   handleAlarm(). Kept, documented, and in the manual.
	--   offsets 37-49   the barricade test is the one thing it asks the character
	--                   for, so it is skipped -- and a boarded window would move
	--                   behind its boards. Refused HERE instead (SCeroSecDevices'
	--                   `act`), the way a barricaded door already is.
	--
	-- And there are two more silent returns above all of that which the study did
	-- not name: `permaLocked` at offsets 21-28 and `destroyed` at 29-36. Both are
	-- refused before the call for the door's reason -- a `return` that does
	-- nothing is an order swallowed.
	--
	-- So a window operator is buildable and it is built. It goes on a window and
	-- on nothing else.
	if id == "window" then
		if CeroSecModules.isWindow(object) then return true end
		return false, "fixture"
	end

	-- The two that work a door itself, and neither goes on a window.
	if not CeroSecModules.isDoor(object) then return false, "fixture" end

	if id == "operator" then
		if CeroSecModules.isManyDoors(object) then return false, "manydoors" end
		return true
	end

	-- strike: only where the lock bites. A built door's always does.
	if instanceof(object, "IsoDoor") and not CeroSecModules.doorLocks(object) then
		return false, "nolock"
	end
	return true
end

--
-- What a machine sees through one object's modules
--
-- Asked by the discovery, once per object, and the shape of the answer is the
-- shape of the feature:
--
--   door     the operator, and nothing else, gives a door that OPENS
--   door ro  a contact alone gives a door that can only be read
--   lock     the strike
--   win  ro  a contact on a window: the sash and the latch, READ. The latch
--            stopped being writable when the hardware gate came in and the
--            reason it gave was wrong; the reason it is still read-only is that
--            a contact is a sensor and senses.
--   window   the window operator, which is what MOVES a sash
--   curtain  the curtain motor, on an IsoCurtain or on a door's own sheet
--   stove    the appliance switch, on an oven, a microwave or a coffee machine
--   washer   the same switch, on a washer, a dryer or a combination machine
--   gen      the generator switch
--   light    the relay
--
-- `ro` is carried right through to the device node, which is born 440 for it and
-- refuses a write in the engine (CeroSecOSDev). A module fitted later moves the
-- node from read-only to read-write on the next command, and it keeps its number
-- (CeroSecDevices.number): the key a number hangs on is where the device is and
-- which kind it is, and neither of those moved when the hardware did.
--
-- That decision is the discovery's and is made in SCeroSecDevices.classify, one
-- layer up from here, because it is the only place that knows what a kind is.
--
