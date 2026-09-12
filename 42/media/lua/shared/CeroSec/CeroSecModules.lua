require "CeroSec/CeroSecDefs"

--
-- The hardware modules
--
-- A computer does not talk to a door because the door is a door. It talks to it
-- because somebody climbed up with a screwdriver and wired a box to it. Four
-- boxes, and each one buys exactly one thing:
--
--   contact   a magnetic contact   -> the machine can SEE a door or a window
--   relay     a relay              -> the machine can throw a light switch
--   strike    an electric strike   -> the machine can work a door's lock
--   operator  a door operator      -> the machine can open and shut a door
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

-- The sandbox option, declared in 42/media/sandbox-options.txt and read below.
CeroSecModules.SANDBOX = "HardwareRequired"

--
-- The four of them.
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
-- three.
--
-- The experience is set against vanilla's own electrical job: repairing a
-- generator is 5 (shared/TimedActions/ISFixGenerator.lua:71,
-- addXp(self.character, Perks.Electricity, 5)). A contact is less than that, an
-- operator more, and nothing here is worth a level.
--
-- The order is the order they are OFFERED in on the menu, which is the order a
-- survivor meets them in: what he can fit at level one first.
CeroSecModules.LIST = {
	{ id = "contact",  item = "CeroSec.MagneticContact", skill = 1, time = 80,  xp = 3 },
	{ id = "relay",    item = "CeroSec.Relay",           skill = 1, time = 100, xp = 3 },
	{ id = "strike",   item = "CeroSec.ElectricStrike",  skill = 2, time = 120, xp = 5 },
	{ id = "operator", item = "CeroSec.DoorOperator",    skill = 3, time = 150, xp = 8 },
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
-- one, and every caller reads it the same way. Nothing but the four ids is
-- looked at and nothing but `true` counts, so somebody else's writing in that
-- table -- or a forged one out of an old save -- fits no hardware.
--
function CeroSecModules.installedOn(object)
	local out = {}
	if object == nil then return out end
	if type(object.hasModData) ~= "function" or not object:hasModData() then return out end
	local data = object:getModData()
	if type(data) ~= "table" then return out end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then return out end
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

-- Anything a module of any kind could go on. What the right-click menu asks
-- first, so that a survivor right-clicking a fridge is offered nothing at all
-- rather than a menu of four refusals.
function CeroSecModules.isFittable(object)
	return CeroSecModules.isDoor(object) or CeroSecModules.isWindow(object)
		or CeroSecModules.isLightSwitch(object)
end

-- May this module go on this object? true, or false and the reason in one word,
-- which is the key the menu greys the entry with
-- (Tooltip_CeroSec_Module<Reason>).
--
-- The refusals are the ones a survivor can DO something about, and each is a
-- fact about the object and not about him: the wrong sort of fixture, a door the
-- lock means nothing on, a leaf of a garage door no machine will work. What he
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

	-- The two that work a door, and neither goes on a window: there is no window
	-- actuator in this mod and there is none in the game either -- the only call
	-- that moves a sash is IsoWindow.ToggleWindow(IsoGameCharacter), which wants
	-- a survivor standing at it (the proofs, 4). A window's module is the contact
	-- and that is the end of it.
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
--   win  ro  a contact on a window, read-only for want of an actuator
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
