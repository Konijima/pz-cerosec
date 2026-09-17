-- Living beside Computer Mod, on a bench. Run from the repo root:
--   lua5.1 tests/compat_computermod_test.lua
--
-- THIS BENCH DOES NOT PROVE THE GAME. It proves the decision and the wire
-- between our two client files against a DOUBLE of the other mod -- not against
-- the other mod, which is not in this repository and whose code is not copied
-- here. What only a game can show: that their filler really darkens the screen,
-- the real order of the two handlers on the event, and that removing their
-- filler breaks nothing else of theirs. docs/PARCOURS-TEST.md step 21 is that
-- test, and it is the one that decides.
--
-- The double reproduces the two things that matter, both read from their source
-- (Workshop 3725497089, v1.0.0):
--   * the event holds the VALUE of their function, not their table and a field
--     name (ComputerMod_ContextMenu.lua:1029). A bench whose fake event looked
--     the field up would pass a wrapper that does nothing in a real game.
--   * their filler rewrites the world sprite to the dark tile whenever their own
--     ComputerModPowerOn flag is not true (:701, :649-687), and stamps the
--     machine with an id on the way past (:699).
--

_G.require = function() end

local count = 0
local function check(what, cond)
	count = count + 1
	if not cond then error("FAIL: " .. what, 2) end
end
local function eq(what, got, want)
	count = count + 1
	if got ~= want then
		error("FAIL: " .. what .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
	end
end

--
-- The game, faked
--

-- The event, holding values. Add stores the function it is given; Remove drops
-- that same value by identity, the way vanilla's own does.
local Events = {}
local function newEvent()
	local e = { handlers = {} }
	function e.Add(fn) e.handlers[#e.handlers + 1] = fn end
	function e.Remove(fn)
		for i = #e.handlers, 1, -1 do
			if e.handlers[i] == fn then table.remove(e.handlers, i) end
		end
	end
	function e.fire(...)
		for i = 1, #e.handlers do e.handlers[i](...) end
	end
	return e
end
Events.OnFillWorldObjectContextMenu = newEvent()
Events.OnGameStart = newEvent()
_G.Events = Events

local activeMods = {}
_G.getActivatedMods = function()
	return {
		size = function() return #activeMods end,
		get = function(_, i) return activeMods[i + 1] end,
	}
end

_G.getText = function(key) return key end
_G.getMouseX = function() return 0 end
_G.getMouseY = function() return 0 end
_G.JoypadState = { players = {} }
_G.ISWorldObjectContextMenu = {
	Test = nil,
	addToolTip = function()
		return { setVisible = function() end }
	end,
}

-- A square, its objects, and the wiring the menu asks about.
local function newSquare(x, y)
	local square = { objects = {} }
	function square:getX() return x end
	function square:getY() return y end
	function square:getZ() return 0 end
	function square:haveElectricity() return true end
	function square:hasGridPower() return true end
	function square:getRoom() return nil end
	function square:getObjects()
		local list = self.objects
		return {
			size = function() return #list end,
			get = function(_, i) return list[i + 1] end,
		}
	end
	return square
end

-- One IsoObject. modData is flat, the way both mods write it.
local function addObject(square, sprite)
	local object = { modData = {}, sprite = sprite }
	function object:getSpriteName() return self.sprite end
	function object:setSpriteFromName(name) self.sprite = name end
	function object:transmitUpdatedSpriteToClients() end
	function object:getSquare() return square end
	function object:hasModData() return true end
	function object:getModData() return self.modData end
	square.objects[#square.objects + 1] = object
	return object
end

local function newContext()
	local context = { options = {} }
	function context:addOption(name)
		local option = { name = name }
		self.options[#self.options + 1] = option
		return option
	end
	function context:addSubMenu() end
	return context
end
_G.ISContextMenu = { getNew = function() return newContext() end }

local function named(context, name)
	for i = 1, #context.options do
		if context.options[i].name == name then return true end
	end
	return false
end

local player = {}
function player:getVehicle() return nil end
function player:getInventory()
	return { getAllTypeRecurse = function() return nil end }
end
_G.getSpecificPlayer = function() return player end

--
-- The real files, and the smallest fakes of ours they need
--

local function load(path)
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end

load("42/media/lua/shared/CeroSec/CeroSecDefs.lua")
-- The dev doors are a tool, not part of the machine, and this bench counts the
-- machine's entries.
CeroSec.debugAllowed = function() return false end

CeroSecMenu = {}
function CeroSecMenu.addTop(context, name)
	return context:addOption(name)
end

CeroSecReach = {}
function CeroSecReach.height() return "low" end
function CeroSecReach.canStandInFront() return true end
function CeroSecReach.pickComputer() return nil end

--
-- Computer Mod, doubled
--

local theirCalls = 0
ComputerModContextMenu = {}
function ComputerModContextMenu.doMenu(playerIndex, context, worldobjects, test)
	theirCalls = theirCalls + 1
	if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.Test then return true end
	local computer = nil
	for _, object in ipairs(worldobjects) do
		local objects = object:getSquare():getObjects()
		for i = 0, objects:size() - 1 do
			local candidate = objects:get(i)
			if computer == nil and CeroSec.isComputerSprite(candidate:getSpriteName()) then
				computer = candidate
			end
		end
	end
	if computer == nil then return end
	local data = computer:getModData()
	-- ensureIdentity, ComputerMod_ContextMenu.lua:699 and
	-- ComputerMod_ComputerTypes.lua:88-98: the id is the square's coordinates.
	local square = computer:getSquare()
	data.ComputerModMachineID = "PC-" .. square:getX() .. "-" .. square:getY() .. "-0"
	-- syncComputerWorldScreen, :701 and :649-687. THE TRAP: their flag decides,
	-- and on a machine CeroSec lit their flag is nil.
	if data.ComputerModPowerOn ~= true then
		local off = CeroSec.SPRITES_OFF[CeroSec.facingOf(computer:getSpriteName()) or "S"]
		if off ~= computer:getSpriteName() then
			computer:setSpriteFromName(off)
			computer:transmitUpdatedSpriteToClients()
		end
	end
	context:addOption("Computer")
end
Events.OnFillWorldObjectContextMenu.Add(ComputerModContextMenu.doMenu)

load("42/media/lua/client/CeroSec/CeroSecContextMenu.lua")
load("42/media/lua/client/CeroSec/CeroSecCompatComputerMod.lua")

-- Arming is a handler on OnGameStart, taken off the fake event rather than
-- called by name: a file that stopped registering it would fail here.
eq("the compat file registers one OnGameStart handler",
	#Events.OnGameStart.handlers, 1)
local arm = Events.OnGameStart.handlers[1]

local ON = CeroSec.SPRITES_ON.S
local OFF = CeroSec.SPRITES_OFF.S
local theirDoMenu = ComputerModContextMenu.doMenu

local function scene(sprite, theirFlag)
	local square = newSquare(10, 20)
	local computer = addObject(square, sprite)
	if theirFlag then computer:getModData().ComputerModPowerOn = true end
	return square, computer
end

local function rightClick(square)
	local context = newContext()
	theirCalls = 0
	Events.OnFillWorldObjectContextMenu.fire(0, context, square.objects, false)
	return context
end

local function onTheEvent(fn)
	for i = 1, #Events.OnFillWorldObjectContextMenu.handlers do
		if Events.OnFillWorldObjectContextMenu.handlers[i] == fn then return true end
	end
	return false
end

local function oursOnMenu(context)
	for i = 1, #context.options do
		if string.sub(context.options[i].name, 1, 19) == "ContextMenu_CeroSec" then return true end
	end
	return false
end

--
-- Their mod is not active: not one byte of behaviour changes
--
-- Red when the id check is dropped or answered by a global's presence: arming
-- would take their filler off the event in a game that has no such mod.

eq("two handlers before arming", #Events.OnFillWorldObjectContextMenu.handlers, 2)
activeMods = {}
arm()
eq("nothing is armed without the mod id", #Events.OnFillWorldObjectContextMenu.handlers, 2)
check("their filler is still on the event", onTheEvent(theirDoMenu))

local square, computer = scene(ON, false)
local context = rightClick(square)
eq("unarmed, their filler still runs", theirCalls, 1)
eq("unarmed, the screen still goes dark -- today's breakage, untouched",
	computer:getSpriteName(), OFF)
eq("unarmed, ownerOf answers nobody", CeroSecCompatComputerMod.ownerOf(computer), nil)

--
-- Their mod is active but their filler is not where this build expects it:
-- we take nothing and relay nothing
--
-- Red when the type checks are dropped: theirs = nil goes onto the event and
-- every right-click in the game relays into nothing.

activeMods = { "ComputerModkum" }
ComputerModContextMenu.doMenu = nil
arm()
eq("a missing doMenu arms nothing", #Events.OnFillWorldObjectContextMenu.handlers, 2)
check("their filler is still on the event", onTheEvent(theirDoMenu))
ComputerModContextMenu.doMenu = theirDoMenu

square, computer = scene(ON, false)
rightClick(square)
eq("fallen back, their filler still runs", theirCalls, 1)
eq("fallen back, ownerOf answers nobody", CeroSecCompatComputerMod.ownerOf(computer), nil)

--
-- Armed
--
-- Red when Remove is replaced by a wrapper on the field: their filler stays on
-- the event and every assertion about the sprite below goes red with it.

arm()
eq("armed, still two handlers", #Events.OnFillWorldObjectContextMenu.handlers, 2)
check("their filler came off the event", not onTheEvent(theirDoMenu))
check("our relay went on", onTheEvent(CeroSecCompatComputerMod.fill))

-- A machine CeroSec is running. Their filler is not called at all, because the
-- call IS what darkens the screen.
-- Red when the ownerOf == "cerosec" branch is removed: the sprite comes back
-- appliances_com_01_72 and "Use computer" leaves the menu.
square, computer = scene(ON, false)
context = rightClick(square)
eq("ours: their filler is never called", theirCalls, 0)
eq("ours: the screen stays lit", computer:getSpriteName(), ON)
check("ours: Use computer is on the menu",
	named(context, "ContextMenu_CeroSec_Use"))
eq("ours: ownerOf says so", CeroSecCompatComputerMod.ownerOf(computer), "cerosec")

-- A machine THEY booted. Their flag is true, so the lit sprite is theirs and
-- we add nothing to it.
-- Red when the guard in CeroSecContextMenu is removed, or when ownerOf asks the
-- sprite before their flag: "Use computer" appears on a session CeroSec never
-- started.
square, computer = scene(ON, true)
context = rightClick(square)
eq("theirs: their filler runs", theirCalls, 1)
eq("theirs: the screen stays lit", computer:getSpriteName(), ON)
check("theirs: not one CeroSec entry", not oursOnMenu(context))
eq("theirs: ownerOf says so",
	CeroSecCompatComputerMod.ownerOf(computer), "computermod")
eq("theirs: we never write their flag",
	computer:getModData().ComputerModPowerOn, true)

-- A dark machine belongs to nobody: both menus, and the player's click decides.
-- Red when the relay returns early on any found computer: their entry goes.
square, computer = scene(OFF, false)
context = rightClick(square)
eq("dark: their filler runs", theirCalls, 1)
check("dark: our Turn on computer is there",
	named(context, "ContextMenu_CeroSec_TurnOn"))
check("dark: their entry is there", named(context, "Computer"))
eq("dark: ownerOf answers nobody", CeroSecCompatComputerMod.ownerOf(computer), nil)

-- Nothing of ours under the cursor: the click is theirs, untouched. This is
-- what keeps their laptop on the floor and everything else of theirs alive.
-- Red when the relay returns instead of relaying on a nil computer.
square = newSquare(11, 21)
addObject(square, "furniture_seating_indoor_01_0")
context = rightClick(square)
eq("no computer: their filler runs", theirCalls, 1)
check("no computer: no CeroSec entry", not oursOnMenu(context))

-- Two computers on one square. Their id for a placed desktop is the square's
-- coordinates, so a second stamped machine here is a duplicate their server
-- sweep deletes -- and the deleted object carries our movableData.cerosec away
-- with it. We keep the click and they stamp nothing.
-- Red when sharesItsSquare is removed: their filler runs and writes the same
-- ComputerModMachineID onto both machines.
square = newSquare(12, 22)
local first = addObject(square, OFF)
local second = addObject(square, OFF)
context = rightClick(square)
eq("stacked: their filler is not called", theirCalls, 0)
eq("stacked: the first machine is unstamped",
	first:getModData().ComputerModMachineID, nil)
eq("stacked: the second machine is unstamped",
	second:getModData().ComputerModMachineID, nil)
check("stacked: our Turn on computer is still there",
	named(context, "ContextMenu_CeroSec_TurnOn"))

-- The relay holds their FUNCTION, not their table and a field name. Writing to
-- the field after registration changes nothing, which is exactly why a wrapper
-- on the field would have been dead code in a real game.
-- Red when the relay is rewritten to call ComputerModContextMenu.doMenu by
-- name: the sentinel below runs and their filler does not.
local sentinelRan = false
ComputerModContextMenu.doMenu = function() sentinelRan = true end
square = scene(OFF, false)
rightClick(square)
ComputerModContextMenu.doMenu = theirDoMenu
eq("the value on the event is the one that runs", theirCalls, 1)
check("a wrapper written onto the field is never called", not sentinelRan)

print("compat_computermod_test: " .. count .. " checks passed")
