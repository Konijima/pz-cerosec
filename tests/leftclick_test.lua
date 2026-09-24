-- The left-click shortcut onto "Use computer", on a bench. Run from the repo
-- root:
--   lua5.1 tests/leftclick_test.lua
--
-- THIS BENCH DOES NOT PROVE THE GAME. It proves the wrapper CeroSecContextMenu
-- installs on ISObjectClickHandler.doClickSpecificObject against a DOUBLE of
-- that vanilla dispatcher -- not against vanilla's own instanceof ladder, which
-- is not in this repository. What only a game can show: that
-- onObjectLeftMouseButtonDown really hands doClickSpecificObject the one
-- object it picked, and that returning true from it really skips the generic
-- click. docs/PARCOURS-TEST.md carries the step that walks it on the glass.

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
-- The game, faked -- just enough of it for CeroSecContextMenu.lua to load and
-- for its own top-level code (Events.Add) to run once. In the ORDER the game
-- loads things: this client file first, with no ISObjectClickHandler in the
-- world yet -- vanilla's lives in media/lua/server, which
-- GameLoadingState.enter() loads after LuaManager.LoadDirBase() has run
-- shared and client -- then the server file, then OnGameStart
-- (IngameState.enter()). The proof with the offsets is beside the Add in
-- CeroSecContextMenu.lua.
--

local function newEvent()
	local e = { handlers = {} }
	function e.Add(fn) e.handlers[#e.handlers + 1] = fn end
	return e
end
local function fire(e)
	for _, fn in ipairs(e.handlers) do fn() end
end
_G.Events = { OnFillWorldObjectContextMenu = newEvent(), OnGameStart = newEvent() }

_G.getText = function(key) return key end
_G.getMouseX = function() return 0 end
_G.getMouseY = function() return 0 end
_G.JoypadState = { players = {} }

-- The reach answers the menu greys "Use computer" on, set per case.
local reach = { height = "low", stand = true }
CeroSecReach = {}
function CeroSecReach.height() return reach.height end
function CeroSecReach.canStandInFront() return reach.stand end

-- vanilla's pause test reads the speed controls
-- (ISObjectClickHandler.lua:196); 1 is a running game, 0 paused.
local gameSpeed = 1
_G.UIManager = {
	getSpeedControls = function()
		return { getCurrentGameSpeed = function() return gameSpeed end }
	end,
}

-- The player, with every state doClickSpecificObject's guards read.
local state = {}
local player = {}
function player:isDead() return state.dead end
function player:getCurrentSquare() return state.square end
function player:isAiming() return state.aiming end
function player:isIgnoreContextKey() return state.ignoreKey end
function player:getVehicle() return state.vehicle end
local function resetState()
	state = { dead = false, square = {}, aiming = false, ignoreKey = false,
		vehicle = nil }
	gameSpeed = 1
	reach.height = "low"
	reach.stand = true
end
resetState()

local function load(path)
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end

-- The client phase: no vanilla dispatcher yet.
_G.ISObjectClickHandler = nil
load("42/media/lua/shared/CeroSec/CeroSecDefs.lua")
load("42/media/lua/client/CeroSec/CeroSecContextMenu.lua")

--
-- 0) Loading before the server folder is harmless and not final: nothing is
--    wrapped at load, and the hook is waiting on OnGameStart.
--
-- Red when the file goes back to calling hookLeftClick() at load: the call
-- meets a nil ISObjectClickHandler, gives up, and nothing is left on
-- OnGameStart -- the field below is never wrapped and the first click check
-- after the event fails.
--
eq("load time: nothing wrapped yet", CeroSecContextMenu.vanillaClickSpecific, nil)
eq("hookLeftClick() with no vanilla table refuses without an error",
	CeroSecContextMenu.hookLeftClick(), false)
local waiting = false
for _, fn in ipairs(Events.OnGameStart.handlers) do
	if fn == CeroSecContextMenu.hookLeftClick then waiting = true end
end
check("hookLeftClick waits on OnGameStart", waiting)

-- The server phase: vanilla's dispatcher, doubled -- one function, counted,
-- returning a value of its own so a fall-through can be told apart from a
-- handled click.
local originalCalls = 0
local vanilla = function(object, playerNum, playerObj)
	originalCalls = originalCalls + 1
	return "VANILLA_FALLTHROUGH"
end
_G.ISObjectClickHandler = { doClickSpecificObject = vanilla }
eq("server loaded, game not started: the field is still vanilla's",
	ISObjectClickHandler.doClickSpecificObject, vanilla)

-- The game starts.
fire(Events.OnGameStart)
check("OnGameStart armed the field",
	ISObjectClickHandler.doClickSpecificObject ~= vanilla)
eq("the original kept is vanilla's",
	CeroSecContextMenu.vanillaClickSpecific, vanilla)

local wrappedOnLoad = ISObjectClickHandler.doClickSpecificObject

local ON = CeroSec.SPRITES_ON.S
local OFF = CeroSec.SPRITES_OFF.S

local function newComputer(sprite)
	local object = { sprite = sprite }
	function object:getSpriteName() return self.sprite end
	return object
end

local useCalls = 0
local lastUseArgs = nil
CeroSecContextMenu.onUse = function(worldobjects, computer, playerObj, height)
	useCalls = useCalls + 1
	lastUseArgs = { worldobjects = worldobjects, computer = computer,
		playerObj = playerObj, height = height }
end

local function reset()
	useCalls = 0
	lastUseArgs = nil
	originalCalls = 0
	resetState()
end

--
-- 1) hookLeftClick() is idempotent: OnGameStart already armed it once, so
--    calling it again must refuse and leave the field wrapped exactly once.
--
-- Red when the guard is dropped: a second call wraps the already-wrapped
-- function again, and a left click on an ON computer queues onUse TWICE.
--
fire(Events.OnGameStart)
eq("a second OnGameStart leaves the one wrapper in place",
	ISObjectClickHandler.doClickSpecificObject, wrappedOnLoad)
eq("hookLeftClick() called again refuses (already armed)",
	CeroSecContextMenu.hookLeftClick(), false)
eq("the field is still the one wrapper, not a second one",
	ISObjectClickHandler.doClickSpecificObject, wrappedOnLoad)

reset()
local onComputer = newComputer(ON)
ISObjectClickHandler.doClickSpecificObject(onComputer, 0, player)
eq("idempotent: one left click still queues onUse once, not twice",
	useCalls, 1)

--
-- 2) A left click on an ON computer calls onUse with that computer, and the
--    wrapped dispatcher answers true (handled).
--
-- Red when leftClick is changed to return false on a match: the click falls
-- through to vanilla's own fallback and the terminal never opens.
--
reset()
onComputer = newComputer(ON)
local handled = ISObjectClickHandler.doClickSpecificObject(onComputer, 0, player)
eq("on: onUse is called once", useCalls, 1)
eq("on: onUse gets the clicked computer", lastUseArgs.computer, onComputer)
eq("on: onUse gets the clicked player", lastUseArgs.playerObj, player)
eq("on: the wrapped dispatcher reports the click handled", handled, true)
eq("on: vanilla's own dispatcher never runs for a handled click",
	originalCalls, 0)

--
-- 3) A left click on an OFF computer does nothing of ours and falls through,
--    unchanged, to the original dispatcher.
--
-- Red when the isOnSprite guard is dropped: an OFF computer would queue onUse
-- from a single click although the menu itself offers no "Use computer" on a
-- dark screen.
--
reset()
local offComputer = newComputer(OFF)
local result = ISObjectClickHandler.doClickSpecificObject(offComputer, 0, player)
eq("off: onUse is never called", useCalls, 0)
eq("off: falls through to the original dispatcher", originalCalls, 1)
eq("off: the original's own answer passes through unchanged",
	result, "VANILLA_FALLTHROUGH")

--
-- 4) A left click on some other object -- not a CeroSec computer at all --
--    is untouched: falls through the same way.
--
reset()
local other = newComputer("furniture_seating_indoor_01_0")
result = ISObjectClickHandler.doClickSpecificObject(other, 0, player)
eq("other: onUse is never called", useCalls, 0)
eq("other: falls through to the original dispatcher", originalCalls, 1)
eq("other: the original's own answer passes through unchanged",
	result, "VANILLA_FALLTHROUGH")

--
-- 5) A left click on a computer the Computer Mod owns is not hijacked either,
--    the same compat guard the right-click menu already applies
--    (CeroSecContextMenu.OnFillWorldObjectContextMenu, and
--    tests/compat_computermod_test.lua for the menu side of the same guard).
--
reset()
local theirs = newComputer(ON)
theirs.mockOwner = "computermod"
_G.CeroSecCompatComputerMod = {
	ownerOf = function(object) return object.mockOwner end,
}
result = ISObjectClickHandler.doClickSpecificObject(theirs, 0, player)
eq("computermod: onUse is never called", useCalls, 0)
eq("computermod: falls through to the original dispatcher", originalCalls, 1)
eq("computermod: the original's own answer passes through unchanged",
	result, "VANILLA_FALLTHROUGH")
_G.CeroSecCompatComputerMod = nil

--
-- 6) Every guard vanilla's own dispatcher opens with
--    (ISObjectClickHandler.lua:196-205), the vehicle the menu refuses, the
--    height it greys out and a front square nobody can stand on: each one
--    leaves the click to the original, and onUse -- whose walk clears the
--    action queue -- never runs.
--
-- Red when any one guard is dropped from leftClick: that case queues onUse
-- and answers true instead of the original's own answer.
--
local refusals = {
	{ "paused", function() gameSpeed = 0 end },
	{ "dead", function() state.dead = true end },
	{ "no current square", function() state.square = nil end },
	{ "aiming", function() state.aiming = true end },
	{ "ignoring the context key", function() state.ignoreKey = true end },
	{ "in a vehicle", function() state.vehicle = {} end },
	{ "out of reach (high)", function() reach.height = "high" end },
	{ "cannot stand in front", function() reach.stand = false end },
}
for _, case in ipairs(refusals) do
	reset()
	case[2]()
	result = ISObjectClickHandler.doClickSpecificObject(newComputer(ON), 0, player)
	eq(case[1] .. ": onUse is never called", useCalls, 0)
	eq(case[1] .. ": falls through to the original dispatcher", originalCalls, 1)
	eq(case[1] .. ": the original's own answer passes through unchanged",
		result, "VANILLA_FALLTHROUGH")
end

-- No player at all is vanilla's first half of the dead test: refused
-- before anything is asked of him.
reset()
result = ISObjectClickHandler.doClickSpecificObject(newComputer(ON), 0, nil)
eq("no player: onUse is never called", useCalls, 0)
eq("no player: falls through", result, "VANILLA_FALLTHROUGH")

-- And the same case with none of them set still acts, so the refusals above
-- are the guards and not a click that never worked.
reset()
result = ISObjectClickHandler.doClickSpecificObject(newComputer(ON), 0, player)
eq("control: onUse is called", useCalls, 1)
eq("control: handled", result, true)

--
-- 7) ISCeroSecUseAction:isValid holds the menu's height line too: an action
--    queued for a machine out of reach is invalid, one at desk height is not.
--
-- Red when the height test is dropped from isValid.
--
_G.ISBaseTimedAction = {
	derive = function(self, name) local t = {}; t.__index = t; return t end,
}
load("42/media/lua/client/CeroSec/ISCeroSecUseAction.lua")
local front = {}
CeroSecReach.frontSquare = function() return front end
CeroSecReach.standingSquare = function() return front end
local machine = newComputer(ON)
function machine:getSquare() return {} end
local function action(height)
	return setmetatable({ object = machine, character = player, height = height },
		ISCeroSecUseAction)
end
eq("use action: valid at desk height", action("mid"):isValid(), true)
eq("use action: invalid out of reach", action("high"):isValid(), false)

print("leftclick_test: " .. count .. " checks passed")
