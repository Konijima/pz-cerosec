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
--   tuner     a tuner control      -> it can switch a television or a radio set
--                                     on and off and move its dial
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
--
-- AND IT DID NOT MOVE FOR `tuner` EITHER, for that same sentence a ninth time.
-- An absent `tuner` reads as "no tuner control on this fixture", which is true of
-- every television and every radio set in every save written before the rung that
-- added it -- nobody had one to fit. A step converting nothing is a number moved
-- to say something that did not happen.
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
--
-- AND THE NINTH GOES ON THE END OF THE END, by the same rule read a third time: a
-- survivor knows where the first eight are on the menu and a ninth that pushed
-- them about would be worse than a list whose levels do not run downhill.
--
-- A tuner control is two at the same reading as the appliance switch it sits
-- beside: a box behind a plate on a set that holds a few hundred volts on its
-- chassis long after it is unplugged, and a ribbon into a tuner that is already
-- there (it is what every radio in this game is built round --
-- Base.RadioReceiver, and see the recipe). Nothing in it turns, so it takes no
-- motor and no receiver of its own.
--
-- recipe   the craftRecipe that makes one, in common/media/scripts/
--          recipes_cerosec.txt, all nine taught by CeroSec.WiringGuide
--
-- The recipe name is here so that a survivor who is offered a module he has
-- never heard of can be told the one thing that would get him one: the book.
-- The menu asks the engine whether he knows it (IsoGameCharacter.isRecipeKnown,
-- which is one call over the sandbox option, the cheat and the known list --
-- see CeroSecModuleMenu). It has nothing to do with FITTING one, which asks for
-- the box and never for the knowledge: it is what the greyed line SAYS.
CeroSecModules.LIST = {
	{ id = "contact",   item = "CeroSec.MagneticContact", skill = 1, time = 80,  xp = 3,
		recipe = "MakeCeroSecMagneticContact" },
	{ id = "relay",     item = "CeroSec.Relay",           skill = 1, time = 100, xp = 3,
		recipe = "MakeCeroSecRelay" },
	{ id = "strike",    item = "CeroSec.ElectricStrike",  skill = 2, time = 120, xp = 5,
		recipe = "MakeCeroSecElectricStrike" },
	{ id = "operator",  item = "CeroSec.DoorOperator",    skill = 3, time = 150, xp = 8,
		recipe = "MakeCeroSecDoorOperator" },
	{ id = "curtain",   item = "CeroSec.CurtainMotor",    skill = 2, time = 100, xp = 5,
		recipe = "MakeCeroSecCurtainMotor" },
	{ id = "appliance", item = "CeroSec.ApplianceSwitch", skill = 2, time = 110, xp = 5,
		recipe = "MakeCeroSecApplianceSwitch" },
	{ id = "window",    item = "CeroSec.WindowOperator",  skill = 3, time = 150, xp = 8,
		recipe = "MakeCeroSecWindowOperator" },
	{ id = "genset",    item = "CeroSec.GeneratorSwitch", skill = 3, time = 140, xp = 8,
		recipe = "MakeCeroSecGeneratorSwitch" },
	{ id = "tuner",     item = "CeroSec.TunerControl",   skill = 2, time = 110, xp = 5,
		recipe = "MakeCeroSecTunerControl" },
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

--
-- THE TELEVISION AND THE RADIO SET, which are one class twice over
--
-- zombie.iso.objects.IsoTelevision and zombie.iso.objects.IsoRadio both extend
-- IsoWaveSignal, which carries `protected DeviceData deviceData` and answers
-- getDeviceData() -- and DeviceData is where everything a set has is kept, the
-- switch and the dial included (javap; the whole list is at the head of
-- SCeroSecRadio.lua, proof 2). The two classes are SIBLINGS and neither is the
-- other, so they are asked apart, and they are two kinds under /dev because a
-- survivor does not think of a television and a radio as one thing.
--
-- AND THE DEVICE DATA IS PART OF THE QUESTION. A set with none is a sprite: the
-- switch and the dial are on the data and there is nothing else to write. A map
-- tile always has one -- IsoWaveSignal.load makes it when the stream did not
-- carry one (offsets 7-23) -- and a set a survivor puts down carries the item's
-- own (ISMoveableSpriteProps.lua:2129-2147, setDeviceData) -- so this is a guard
-- and not a case. It is asked HERE, once, because the install and the discovery
-- must not disagree about what a set is: a tuner fitted to something /dev then
-- refuses to show is a box a survivor cannot get back.
function CeroSecModules.isTelevision(object)
	if object == nil then return false end
	if not instanceof(object, "IsoTelevision") then return false end
	return object:getDeviceData() ~= nil
end

-- A radio SET, which is the receiver and not the TNC. The same object can be
-- both: a ham set in the room is the machine's /dev/radio0, read-only, because
-- the aerial's frequency is the survivor's (SCeroSecRadio.lua, proof 7), and with
-- a tuner control screwed to it, it is also an rxN whose switch and dial the
-- machine works. That is the door's own shape -- doorN opens and lockN keys, one
-- object, two vocabularies -- and the TNC's own reading does not change for it.
function CeroSecModules.isRadioSet(object)
	if object == nil then return false end
	if not instanceof(object, "IsoRadio") then return false end
	return object:getDeviceData() ~= nil
end

function CeroSecModules.isTuneable(object)
	return CeroSecModules.isTelevision(object) or CeroSecModules.isRadioSet(object)
end

-- Anything a module of any kind could go on. What the right-click menu asks
-- first, so that a survivor right-clicking a fridge is offered nothing at all
-- rather than a menu of eight refusals.
function CeroSecModules.isFittable(object)
	return CeroSecModules.isDoor(object) or CeroSecModules.isWindow(object)
		or CeroSecModules.isLightSwitch(object)
		or CeroSecModules.isCurtain(object) or CeroSecModules.isStove(object)
		or CeroSecModules.isWasher(object) or CeroSecModules.isGenerator(object)
		or CeroSecModules.isTuneable(object)
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

	-- A television or a radio set, and nothing else: a tuner control is a box
	-- behind the back panel of a receiver, wired to the tuner that is already in
	-- it. A set with no device data on it is not one of these (isTuneable), and it
	-- is the one refusal here a survivor really cannot do anything about -- which
	-- is why it reads as the wrong sort of fixture rather than as a fault: from
	-- where he stands the thing on that tile is not a set the machine can wire.
	if id == "tuner" then
		if CeroSecModules.isTuneable(object) then return true end
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
-- WHERE HE IS STANDING, WHAT THE FIXTURE IS DOING, AND WHOSE HOUSE IT IS
--
-- fitsOn answers what a module CAN go on and never changes from one minute to
-- the next: it is a fact about the fixture's shape. These three are facts about
-- RIGHT NOW, and they are all three refusals of the same gesture, so they are
-- asked in one function -- the turnOnRefusal shape the debug window and the
-- server already share (SCeroSecDebug.turnOnRefusal): one rule, one place, one
-- wording, and the day a rule moves the greyed entry moves with it.
--
-- 1. INSIDE. A module screwed to the skin of a building is a module anybody can
--    unscrew from the pavement, and a survivor who wired his front door would
--    find the contact gone and the door opened with it. So the job is done from
--    inside, and "inside" is asked of the square HE is standing on and never of
--    the fixture's: a door stands on the room's own square (which is why
--    doorLocks reads getSquare against getOppositeSquare and calls the pair
--    "exactly one of them has a room") and he stands on one side of it or the
--    other. The inside side is in a room; the pavement is not. An interior door
--    has a room on both sides, so both sides are allowed, which is the answer a
--    survivor expects.
--
--    isInARoom() and not getRoom() ~= nil, and the difference is a base: the
--    call is `getRoom() != null || getIsoWorldRegion().isPlayerRoom()` (javap -c
--    zombie.iso.IsoGridSquare.isInARoom, offsets 0-31), so a room a PLAYER built
--    -- four walls the map has no RoomDef for -- reads as inside, and getRoom()
--    alone would refuse a man standing in the middle of his own base. Vanilla
--    asks it that way itself (server/BuildingObjects/ISEmptyGraves.lua:169,
--    server/Vehicles/Vehicles.lua:667).
--
--    A GENERATOR IS EXEMPT and it is the only one. It is an outdoor machine by
--    construction -- a generator indoors poisons the room, which is the game's
--    own rule -- so a check that asked for a room would be a module nobody could
--    ever fit. Every other fixture here is reached from inside a building.
--
-- 2. OPEN FOR WHAT OPENS, OFF FOR WHAT SWITCHES ON. Nobody fits an operator to a
--    door while it is shut, a motor to a sash he cannot reach round, or a
--    contactor to an oven that is cooking. The state asked for is the state of
--    the thing the MODULE is screwed to, which is why a curtain motor on a door
--    asks about the sheet and a strike on the same door asks about the door:
--    one fixture, two jobs, two answers.
--
--    Every getter is the one the device layer already reads the state with
--    (SCeroSecDevices.stateOf), proven by javap against the shipped jar:
--      IsoDoor.IsOpen()          IsoThumpable.IsOpen()   IsoWindow.IsOpen()
--      IsoCurtain.IsOpen()       IsoDoor.isCurtainOpen()
--      IsoStove.Activated()      IsoClothingWasher.isActivated() (and the dryer
--      and the combination machine)  IsoGenerator.isActivated()
--      DeviceData.getIsTurnedOn() through IsoWaveSignal.getDeviceData()
--
--    A window's IsOpen() is a sash that really moved, so it already excludes a
--    barricaded, sealed or smashed window: none of those opens. That is why
--    there is no second word for them here.
--
--    IT IS ASKED OF A REMOVAL TOO. Taking a contactor out of a running oven is
--    the same hand in the same place, and the door a man is unscrewing a strike
--    from is the door that swings into him.
--
--    A PRE-FITTED FIXTURE IS NOT AFFECTED. The 1991 walk writes modData and
--    performs no player action at all (CeroSecModules.markPreFitted / setOn),
--    so it never comes past here.
--
-- 3. SOMEBODY ELSE'S SAFEHOUSE, and only when the server asked for it
--    (SandboxVars.CeroSec.SafehouseModules, off by default). A safehouse's own
--    vanilla rule is about LOOTING and fitting is not looting -- nothing leaves
--    the building and nothing is taken out of a container -- so that rule is not
--    borrowed and this option is the only gate. On, a fixture standing in a
--    safehouse takes a module from the people the safehouse allows and nobody
--    else; off, it is open to anybody, which is the world as it was before the
--    option existed.
--
--    SafeHouse.getSafeHouse(square) is asked of the FIXTURE's square and not of
--    his: what is being protected is somebody's door, and a man on the pavement
--    outside a safehouse is exactly the case this exists for. It is
--    isSafeHouse(square, null, false) (javap -c, offsets 0-6) down to
--    findSafeHouse, a walk of safehouseList comparing x/y against each one's
--    box; nil when no safehouse covers the square, which is every square in
--    single player.
--
--    playerAllowed(IsoPlayer) is vanilla's own membership question and admins
--    pass it without a branch of ours: the bytecode is `players.contains(
--    getUsername()) || owner.equals(getUsername()) || role.hasCapability(
--    CanGoInsideSafehouses)` (javap -c zombie.iso.areas.SafeHouse.playerAllowed,
--    offsets 0-46), and that capability is the one vanilla's own safehouse
--    interact check reads for the same purpose (isSafehouseAllowInteract,
--    offsets 23-44). So the owner, his members and an admin may wire it, and
--    that is the allowance vanilla gives its own looting rule.
--
-- nil for "he may", or the reason in one word, which is the key the menu greys
-- with: Tooltip_CeroSec_Module<Reason>.
--

CeroSecModules.SANDBOX_SAFEHOUSE = "SafehouseModules"

-- Does the safehouse gate apply at all?
--
-- It fails OPEN, which is the opposite direction to required() above, and the
-- reason is the compatibility contract rather than a preference: a new sandbox
-- option defaults to the OLD behaviour, and the old behaviour is a world with no
-- gate. A sandbox file that failed to load must not be a world where nobody can
-- touch his own hardware, because that is a refusal a player cannot see the
-- cause of -- where the hardware gate failing closed gives him an empty /dev,
-- which he can read off the screen.
function CeroSecModules.safehouseGated()
	local group = SandboxVars and SandboxVars.CeroSec
	if group == nil then return false end
	return group[CeroSecModules.SANDBOX_SAFEHOUSE] == true
end

-- Which square's room decides, or nil for a fixture nobody has to be inside for.
local function needsInside(object)
	return not CeroSecModules.isGenerator(object)
end

-- The state the fixture has to be in for THIS module, or nil when the module has
-- none. A light switch is the one that asks for nothing: a relay goes behind a
-- plate whose only state is the light it works, and a machine that would not let
-- a man wire a switch while the light was on would be a rule about nothing.
local function stateRefusal(object, id)
	if id == "relay" then return nil end

	if id == "curtain" then
		-- The two curtains, told apart the way SCeroSecDevices tells them apart:
		-- an IsoCurtain answers IsOpen(), a door's own sheet answers
		-- isCurtainOpen() and there is no second object to ask.
		if CeroSecModules.isCurtain(object) then
			if not object:IsOpen() then return "drawn" end
			return nil
		end
		if not object:isCurtainOpen() then return "drawn" end
		return nil
	end

	if id == "appliance" then
		-- The oven's getter is Activated() with a capital A and the laundry's is
		-- isActivated(); they are two classes and two spellings, not one.
		if CeroSecModules.isStove(object) then
			if object:Activated() then return "running" end
			return nil
		end
		if object:isActivated() then return "running" end
		return nil
	end

	if id == "genset" then
		if object:isActivated() then return "running" end
		return nil
	end

	if id == "tuner" then
		local data = object:getDeviceData()
		if data ~= nil and data:getIsTurnedOn() then return "running" end
		return nil
	end

	-- contact, strike, operator and window: the thing that opens, whichever of
	-- the three classes it is. All three answer IsOpen().
	if not object:IsOpen() then return "closed" end
	return nil
end

function CeroSecModules.fittingRefusal(object, id, playerObj)
	if object == nil or playerObj == nil then return "outside" end
	if CeroSecModules.byId(id) == nil then return "outside" end

	-- WHOSE HOUSE FIRST. It is the one of the three he cannot change by doing
	-- anything at the fixture, and it is the one that should not be answered
	-- round: a stranger told "open it first" has been told what state somebody
	-- else's door is in.
	if CeroSecModules.safehouseGated() and SafeHouse ~= nil then
		local square = object:getSquare()
		if square ~= nil then
			local house = SafeHouse.getSafeHouse(square)
			if house ~= nil and not house:playerAllowed(playerObj) then
				return "safehouse"
			end
		end
	end

	if needsInside(object) then
		local square = playerObj:getCurrentSquare()
		-- No square at all is a survivor the world cannot place, and the honest
		-- answer for one is the refusal: nothing here is worth guessing at.
		if square == nil or not square:isInARoom() then return "outside" end
	end

	return stateRefusal(object, id)
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
--   tv       the tuner control, on a television
--   rx       the same control, on a radio set -- which keeps its own /dev/radio0
--            beside it when it is the machine's TNC, because a receiver's dial
--            and an aerial's are two questions
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
