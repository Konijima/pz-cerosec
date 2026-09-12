-- The window and the machine, wired to each other. Run from the repo root:
--   lua5.1 tests/window_test.lua
--
-- terminal_test.lua covers the pure helpers and os_test.lua the core. Neither
-- of them proves the one thing a player actually does: type a line, have the
-- machine answer, and see the answer on the glass. `edit notes.txt` came back
-- as a bare prompt in the game with nothing on the screen and nothing in the
-- log, and every piece of it tested green on its own -- because the piece that
-- was broken (a method the window called on itself once a frame and that was
-- not written) is not a piece any of those tests touch.
--
-- So this file runs the real client file and the real server files against a
-- fake game: a text box that holds text and a cursor, a window base class that
-- records what was painted, and a computer with a console on it. The client's
-- sendCommand goes into the server's OnClientCommand and the server's replies
-- come back into the window, which is the whole round trip.
--
-- What is asserted is what is PAINTED, not what a field says: a field can be
-- right while the screen shows the shell.
--

--
-- The game, faked.
--

_G.require = function() end
_G.__now = 1000
_G.getTimestampMs = function() return _G.__now end
_G.ZombRand = function() return 0 end

-- The game's clock. Vanilla's GameTime has two 0-BASED getters -- getMonth()
-- and getDay() -- which is why every caller in the game's own Lua adds one to
-- them (media/lua/server/Farming/SPlantGlobalObject.lua, and getDayPlusOne()
-- exists for exactly that reason). The fake counts the same way, so a server
-- that forgot to add the one is a server this bench fails: a fake handing over
-- 1-based numbers would let the wrong arithmetic pass.
-- ageHours is how long the world has been running, which is the number the
-- grid question is asked in: ten days here, with the power set to go on day a
-- hundred (__sandbox below), so the default world has a dial tone in it. The
-- two benches that move this clock put it back the way they found it.
_G.__gameTime = { year = 1993, month = 6, day = 7, hour = 14, minutes = 32,
	ageHours = 240 }
_G.getGameTime = function()
	local t = _G.__gameTime
	if t == nil then return nil end
	return {
		getYear = function() return t.year end,
		getMonth = function() return t.month end,
		getDay = function() return t.day end,
		getHour = function() return t.hour end,
		getMinutes = function() return t.minutes end,
		-- How long the world has been running, which is the other half of the
		-- grid question. Vanilla's own number, in hours and not days.
		getWorldAgeHours = function() return t.ageHours or 0 end,
	}
end
-- The county's power, which is what the telephone exchange runs on. These are
-- exactly the calls the game's own Lua makes to ask whether the grid is still up
-- (media/lua/client/ISUI/ISButtonPrompt.lua:520 and
-- media/lua/server/radio/ISWeatherChannel.lua:153): the age of the world in
-- hours, the day the power is set to go, and how long the apocalypse had been
-- running when the character arrived.
--
-- The power goes on day a hundred and the world is ten days old (__gameTime
-- above), so the default world this bench runs in has a dial tone. A bench that
-- wants the grid dead moves elecShut; one that wants to see what the mod does
-- with a game it cannot ask at all sets __sandbox to nil.
_G.__sandbox = { elecShut = 100, timeSinceApo = 1 }
_G.getSandboxOptions = function()
	local s = _G.__sandbox
	if s == nil then return nil end
	return {
		getElecShutModifier = function() return s.elecShut end,
		getTimeSinceApo = function() return s.timeSinceApo end,
	}
end
-- The sandbox options a MOD declares, which is a different table from the
-- getSandboxOptions() object above: SandboxVars is a plain Lua table the game
-- fills in from 42/media/sandbox-options.txt, and a group nobody declared is
-- simply not in it (CeroSecModules.required).
--
-- HardwareRequired is FALSE here and true in the game, deliberately: every bench
-- in this file that was written before rung 4f is a bench about the world as it
-- was, where a door is a device because it is a door. Those benches are the
-- control for the option being off, and they are not to be touched. The hardware
-- section at the bottom sets it true for itself and puts it back.
_G.SandboxVars = { CeroSec = { HardwareRequired = false } }
_G.getText = function(key) return key end
_G.UIFont = { Code = "Code", Small = "Small" }
_G.Keyboard = { KEY_ESCAPE = 1, KEY_TAB = 15 }
-- Class-aware, because the device layer tells a light switch from a door with
-- it. Anything that is not one of the fake world objects below answers true, as
-- it did before: the only other caller is the client's computer test.
--
-- And hierarchy-aware where the game has one, because the sensor asks about a
-- SUPERCLASS: `instanceof(body, "IsoGameCharacter")` has to be true of a zombie
-- and of a survivor and false of a car, which is the game's own shape --
-- IsoZombie extends IsoGameCharacter extends IsoMovingObject, IsoPlayer the same
-- way, and BaseVehicle extends IsoMovingObject and stops there (all javap'd). A
-- fake that answered only on the exact name would let a sensor which skipped the
-- invisible test on zombies pass.
local PARENT = {
	IsoZombie = "IsoGameCharacter",
	IsoPlayer = "IsoGameCharacter",
	IsoGameCharacter = "IsoMovingObject",
	BaseVehicle = "IsoMovingObject",
	HandWeapon = "InventoryItem",
}
_G.instanceof = function(object, class)
	if type(object) == "table" and type(object.__class) == "string" then
		local name = object.__class
		while name ~= nil do
			if name == class then return true end
			name = PARENT[name]
		end
		return false
	end
	return true
end

-- The two statics the device layer asks about a door before it will call
-- ToggleDoorSilent on it: is this one leaf of a double door, or of a garage
-- door? Vanilla answers -1 for an object with no such property on it
-- (media/lua/server/BuildingObjects/ISBuildUtil.lua:556), and so does this.
_G.IsoDoor = {
	getDoubleDoorIndex = function(object)
		if type(object) == "table" and type(object.doubleDoor) == "number" then
			return object.doubleDoor
		end
		return -1
	end,
	getGarageDoorIndex = function(object)
		if type(object) == "table" and type(object.garageDoor) == "number" then
			return object.garageDoor
		end
		return -1
	end,
}

-- The cell, when a bench has laid a world out. nil is a game with no world in
-- it, which is what every bench that is not about devices runs on.
_G.__world = nil
_G.getCell = function() return _G.__world end
-- The local players, by player number. Vanilla's own way of turning the number
-- an answer carries into the survivor it belongs to, and the only way the client
-- has of doing it: getSpecificPlayer is what the context menu uses
-- (CeroSecContextMenu.addEntries) and what the reopen after a reboot uses, since
-- the window it is asked to make has nobody to ask yet. Filled in by newBench.
_G.__players = {}
_G.getSpecificPlayer = function(num) return _G.__players[num] end
_G.isClient = function() return false end
_G.isServer = function() return false end
_G.sendServerCommand = function() end
_G.MapObjects = { OnNewWithSprite = function() end, OnLoadWithSprite = function() end }
_G.Events = setmetatable({}, { __index = function(t, key)
	local event = { Add = function() end }
	rawset(t, key, event)
	return event
end })
-- The action queue, recording. Everything the mod queues lands in __queued, in
-- order, so a bench can say WHERE a walk was aimed and not merely that one
-- happened. clear() empties the list the way it empties the queue.
_G.__queued = {}
_G.ISTimedActionQueue = {
	isPlayerDoingAction = function() return false end,
	add = function(action) _G.__queued[#_G.__queued + 1] = action; return action end,
	clear = function() _G.__queued = {} end,
}
_G.ISCeroSecTypeAction = { new = function(_, character, object, height, window)
	return { __what = "type", character = character, object = object,
		height = height, window = window }
end }
_G.ISRestAction = { new = function(_, character, chair) return { __what = "rest",
	character = character, chair = chair } end }
-- The walk to a float point, built the way vanilla builds it: the goal is a
-- table tagged 'LocationF' and the three coordinates (ISPathFindAction.lua:122,
-- media/lua/client/Vehicles/TimedActions/ISPathFindAction.lua on 42.20.4).
_G.ISPathFindAction = { pathToLocationF = function(_, character, x, y, z)
	return { __what = "walk", character = character, goal = { "LocationF", x, y, z } }
end }

-- The font. UIFont.Code is monospaced -- media/fonts/EN/fonts.txt maps Code to
-- zomboidCode.fnt, and all 613 of its glyphs declare xadvance=8 -- so the pen
-- moves CHAR_W per character and nothing here is proportional.
--
-- MeasureStringX does NOT answer that, and this bench used to pretend it did.
-- It hands the string to AngelCodeFont.getWidth(String), which is
-- getWidth(s, 0, len - 1, false), and that false makes the LAST character of
-- the string count as its glyph's ink `width` while every other counts as its
-- `xadvance`. Only the pen that draws (render()) moves by xadvance throughout.
-- So the answer is short -- or long -- by (xadvance - ink) of whatever
-- character the string ends on, and that is a different number per character:
-- in zomboidCode.fnt `a` is width=7, `b` is width=8, `l` is width=6, the space
-- is width=2, and `M` is width=9 -- a pixel WIDER than the cell it is drawn in.
-- INK below is those real numbers, and this fake answers the way the game does.
-- A bench that returned CHAR_W * #s could not see a cursor placed on
-- MeasureStringX go wrong, which is how the first fix passed and the glass
-- stayed crooked.
--
-- __cellMeasure is the game's answer to a *load time* measurement, when the
-- font asked for is not built yet and TextManager hands back the default,
-- proportional one instead. It is set while the mod is being loaded below and
-- cleared afterwards, so a cell taken at load time is half again too wide and
-- one taken with the game up is right. That is the gap between the "$" and the
-- block cursor in the screenshot.
local CHAR_W = 8
local FONT_H = 12
local INK = { M = 9, a = 7, b = 8, l = 6, s = 7, [" "] = 2 }
_G.__cellMeasure = 12
_G.getTextManager = function()
	return {
		MeasureStringX = function(_, _, s)
			if s == nil or s == "" then return 0 end
			if _G.__cellMeasure then return _G.__cellMeasure * #s end
			local last = string.sub(s, -1)
			return CHAR_W * (#s - 1) + (INK[last] or CHAR_W - 1)
		end,
		getFontHeight = function() return FONT_H end,
	}
end
-- getObjectHighlitedColor is the colour vanilla outlines a world object with
-- (ISWorldObjectContextMenu's onHighlightWorldItem reads the same one off
-- getCore()); the window asks for it before it lights a door.
_G.getCore = function()
	return { getScreenWidth = function() return 1920 end,
		getScreenHeight = function() return 1080 end,
		getObjectHighlitedColor = function() return { r = 1, g = 1, b = 1 } end }
end

-- The text box: the two things the window reads out of it (the text and an
-- absolute cursor index) and the calls it makes on it.
local Box = {}
Box.__index = Box
function Box.new()
	local o = setmetatable({}, Box)
	o.text = ""
	o.cursor = 0
	o.focused = false
	o.javaObject = { setIgnoreFirst = function() end }
	return o
end
function Box:initialise() end
function Box:instantiate() end
function Box:setHasFrame() end
function Box:setTextRGBA() end
function Box:setUIName() end
function Box:setMaxLines(n) self.maxLines = n end
function Box:setMaxTextLength(n) self.maxTextLength = n end
function Box:setMultipleLine(b) self.multipleLine = b end
function Box:setMasked(b) self.masked = b end
function Box:setVisible(b) self.visible = b end
function Box:setEditable(b) self.editable = b end
function Box:focus() self.focused = true end
function Box:unfocus() self.focused = false end
function Box:isFocused() return self.focused end
function Box:setText(s) self.text = s or ""; self.cursor = 0 end
function Box:getInternalText() return self.text end
function Box:getCursorPos() return self.cursor end
function Box:setCursorPos(n) self.cursor = n end
function Box:setX(v) self.x = v end
function Box:setY(v) self.y = v end
function Box:setWidth(v) self.width = v end
function Box:setHeight(v) self.height = v end
-- What a player at the keyboard does.
function Box:type(s)
	self.text = string.sub(self.text, 1, self.cursor) .. s .. string.sub(self.text, self.cursor + 1)
	self.cursor = self.cursor + #s
end
ISTextEntryBox = { new = function(_, _, _, _, _, _) return Box.new() end }

-- An ArrayList as the game hands one over: 0-based get, and a size.
local function javaList(items)
	return {
		size = function() return #items end,
		get = function(_, i) return items[i + 1] end,
	}
end

local function derive(base, name)
	local o = {}
	for key, value in pairs(base) do o[key] = value end
	o.Type = name
	o.__index = o
	o.derive = base.derive
	return o
end

ISCollapsableWindow = { derive = function(self, name) return derive(self, name) end }
function ISCollapsableWindow.new(self, x, y, w, h)
	local o = setmetatable({}, self)
	o.x, o.y, o.width, o.height = x, y, w, h
	o.children = {}
	return o
end
function ISCollapsableWindow.createChildren(self)
	self.resizeWidget = { setVisible = function() end }
	self.resizeWidget2 = { setVisible = function() end }
	self.collapseButton = { setVisible = function() end }
end
function ISCollapsableWindow.prerender() end
function ISCollapsableWindow.render() end
function ISCollapsableWindow.onMouseDown() end
function ISCollapsableWindow.onMouseUp() end
function ISCollapsableWindow.initialise() end
-- The game's own order, and not a no-op: addToUIManager instantiates an element
-- that has not been instantiated yet, and instantiate() is what calls
-- createChildren (ISUIElement.lua:1365-1371 and :993-1007). The windows this
-- bench builds by hand call createChildren themselves; a window the CLIENT builds
-- -- CeroSecTerminal.open, which is the path a reopen after a reboot goes through
-- -- has only this, exactly as in the game.
function ISCollapsableWindow.addToUIManager(self)
	if self.instantiated then return end
	self.instantiated = true
	self:createChildren()
end
function ISCollapsableWindow.removeFromUIManager() end
function ISCollapsableWindow.addChild(self, child) self.children[#self.children + 1] = child end
function ISCollapsableWindow.setResizable() end
function ISCollapsableWindow.setTitle(self, title) self.titleText = title end
function ISCollapsableWindow.setVisible() end
function ISCollapsableWindow.drawRect() end
function ISCollapsableWindow.drawText() end

CeroSecReach = {
	-- The desk the computer stands on, as the context menu reads it and as the
	-- reopen after a reboot reads it again: a table, which is "mid".
	height = function() return "mid" end,
	-- Where a player using this computer on his feet belongs, and whether he is
	-- already standing there. "Already there" by default, which is the world every
	-- bench written before the stand point was written in: resettle with no chair
	-- then has nothing to do, exactly as it had nothing to do before. The drift
	-- benches set __drifted for themselves and put it back.
	standPoint = function()
		local x, y = CeroSec.standPoint(9, 10, "S")
		return x, y, 0
	end,
	atStandPoint = function() return not CeroSecReach.__drifted end,
	approachPoint = function() return CeroSecReach.standPoint() end,
	frontSquare = function() return { getX = function() return 9 end,
		getY = function() return 10 end, getZ = function() return 0 end } end,
	chairInFront = function() return nil end,
	isSeatedOn = function() return false end,
	standingSquare = function() return { getX = function() return 9 end,
		getY = function() return 10 end, getZ = function() return 0 end } end,
}

SGlobalObject = { derive = function(self, name) return derive(self, name) end }
SGlobalObject.new = function(self, luaSystem, globalObject)
	local o = setmetatable({}, self)
	o.luaSystem = luaSystem
	o.x, o.y, o.z = globalObject.x, globalObject.y, globalObject.z
	return o
end
SGlobalObjectSystem = { derive = function(self, name) return derive(self, name) end }
SGlobalObjectSystem.new = function(self, name)
	local o = setmetatable({}, self)
	o.name = name
	-- The Java system, with the three key lists the mod fills. Vanilla's own new()
	-- calls initSystem right here (media/lua/server/Map/SGlobalObjectSystem.lua:24)
	-- and that is what fills them, so the sync list the client mirror below is
	-- built from is the MOD's list and never a copy of it in this file.
	o.system = {
		setModDataKeys = function(s, keys) s.modDataKeys = keys end,
		setObjectModDataKeys = function(s, keys) s.objectModDataKeys = keys end,
		setObjectSyncKeys = function(s, keys) s.syncKeys = keys end,
	}
	o:initSystem()
	return o
end
SGlobalObjectSystem.initSystem = function() end
SGlobalObjectSystem.RegisterSystemClass = function() end
-- The two the game itself brings, copied rather than approximated: the unload
-- section at the bottom is about what happens INSIDE loadIsoObject when a chunk
-- comes back, which is the one path a bench cannot fake without them
-- (media/lua/server/Map/SGlobalObjectSystem.lua:128-149).
SGlobalObjectSystem.getLuaObjectOnSquare = function(self, square)
	if not square then return nil end
	return self:getLuaObjectAt(square:getX(), square:getY(), square:getZ())
end
SGlobalObjectSystem.loadIsoObject = function(self, isoObject)
	if not isoObject or not isoObject:getSquare() then return end
	if not self:isValidIsoObject(isoObject) then return end
	local luaObject = self:getLuaObjectOnSquare(isoObject:getSquare())
	if luaObject then
		luaObject:stateToIsoObject(isoObject)
		return
	end
	-- Vanilla's other branch makes a brand new GlobalObject out of the sprite,
	-- which needs the Java system this bench has none of. No bench here takes it:
	-- a computer the server has never seen is a different rung, and an error is
	-- better than a silent nothing if one ever does.
	error("loadIsoObject: no luaObject to load onto", 2)
end

--
-- The mod, loaded the way the game loads it.
--

local LUA = "42/media/lua/"
local FILES = {
	"shared/CeroSec/CeroSecDefs.lua",
	"shared/CeroSec/CeroSecModules.lua",
	"shared/CeroSec/OS/CeroSecOS.lua",
	"shared/CeroSec/OS/CeroSecOSComplete.lua",
	"shared/CeroSec/OS/CeroSecOSCron.lua",
	"shared/CeroSec/OS/CeroSecOSDev.lua",
	"shared/CeroSec/OS/CeroSecOSDisk.lua",
	"shared/CeroSec/OS/CeroSecOSFS.lua",
"shared/CeroSec/OS/CeroSecOSNet.lua",
	"shared/CeroSec/OS/CeroSecOSPath.lua",
	"shared/CeroSec/OS/CeroSecOSRadio.lua",
	"shared/CeroSec/OS/CeroSecOSScript.lua",
	"shared/CeroSec/OS/CeroSecOSShell.lua",
	"shared/CeroSec/OS/CeroSecOSState.lua",
	"shared/CeroSec/OS/CeroSecOSSystem.lua",
	"shared/CeroSec/OS/CeroSecOSUsers.lua",
	"shared/CeroSec/OS/CeroSecOSVM.lua",
	"server/CeroSec/SCeroSecSensors.lua",
	"server/CeroSec/SCeroSecRadio.lua",
	"server/CeroSec/SCeroSecDevices.lua",
	"server/CeroSec/SCeroSecNet.lua",
	"server/CeroSec/SCeroSecDebug.lua",
	"server/CeroSec/SCeroSecJobs.lua",
	"server/CeroSec/SCeroSecObject.lua",
	"server/CeroSec/SCeroSecSystem.lua",
	-- The one under test is loaded from a path the caller may override, so the
	-- same bench can be pointed at an older window and made to fail.
	nil,
}
FILES[#FILES + 1] = os.getenv("CEROSEC_TERMINAL") or (LUA .. "client/CeroSec/CeroSecTerminal.lua")
for i = 1, #FILES - 1 do
	local path = LUA .. FILES[i]
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end
do
	local path = FILES[#FILES]
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end
-- The game is up now, and the font it hands out for UIFont.Code is the right
-- one. Anything measured before this line was measured against the wrong one.
_G.__cellMeasure = nil

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
-- One computer, one player, one window, wired together.
--

local function newBench()
	-- The scheduler's list of machines is a module-level one, like the game's:
	-- a bench that left a job running would otherwise have it stepped by the
	-- next bench's ticks. One bench, one county.
	CeroSecJobs.machines = {}
	-- And the client's registry of open windows, for the same reason: a window
	-- the game itself made -- which is what a reopen after a reboot is -- lives in
	-- there, and a bench must not inherit the last bench's.
	CeroSecTerminal.instances = {}
	_G.__players = {}
	local player = {
		getPlayerNum = function() return 0 end,
		getOnlineID = function() return -1 end,
		isDead = function() return false end,
		playSoundLocal = function() end,
		getCurrentSquare = function() return { getZ = function() return 0 end } end,
		getX = function() return 10.5 end,
		getY = function() return 10.5 end,
	}
	local computer = {
		getSquare = function() return { getX = function() return 10 end,
			getY = function() return 10 end, getZ = function() return 0 end } end,
		getSpriteName = function() return CeroSec.SPRITES_ON["S"] end,
	}

	local system = SCeroSecSystem:new()
	local object = SCeroSecObject:new(system, { x = 10, y = 10, z = 0 })
	object.getIsoObject = function() return nil end
	object.getSquare = function() return nil end
	object.playSound = function() end
	object.syncSprite = function() end
	object:initNew()
	object.hasPower = function() return true end
	object.on = true
	object.console = CeroSec.newConsole()
	object.consoleChecked = true
	system.getLuaObjectAt = function() return object end
	system.getIsoObjectAt = function() return nil end
	-- The sweep Events.EveryOneMinute walks: the power check and cron's own pass
	-- ask the system for every machine there is, and on this bench there is one.
	system.getLuaObjectCount = function() return 1 end
	system.getLuaObjectByIndex = function() return object end

	_G.__players[0] = player

	local window = CeroSecTerminal:new(0, 0, player, computer)
	window:initialise()
	window:createChildren()
	local bench = { window = window, object = object, system = system, player = player,
		computer = computer }

	-- The CLIENT's copy of this machine, and the one mechanism the game has for
	-- keeping it in step with the server's. The server writes the sync keys it
	-- HAS -- TableNetworkUtils.saveSome walks the table and skips a key that is
	-- not in it -- and the client rawsets each key it RECEIVES into its own copy
	-- (CGlobalObjectSystem.receiveUpdateLuaObjectAt; both javap'd on 42.20.4). So
	-- it is a merge and not a replacement: a key the server sets back to nil never
	-- crosses, and the client keeps what it was told last time. Faked exactly that
	-- way on purpose -- a fake that copied the whole table would let a server that
	-- nils a synced key pass, which is the bug that put "Eject floppy" on the menu
	-- of a machine whose drive was empty.
	bench.client = {}
	object.updateOnClient = function(self)
		local keys = system.system.syncKeys
		for i = 1, #keys do
			local value = self[keys[i]]
			if value ~= nil then bench.client[keys[i]] = value end
		end
	end
	-- Every window open on this computer. One to begin with; a second player
	-- standing at the same glass is bench.addWindow().
	bench.windows = { window }

	-- The wire. One call in, the server's answers straight back out -- to every
	-- window there is, because that is what the server does: it answers a
	-- connection, and each window keeps only what carries its own token.
	-- Every line the server ever put on a screen, in order. The glass only ever
	-- shows the LAST screen, and some lines are the last thing a machine says
	-- before it goes down and wipes the console -- a reboot's own broadcast is
	-- one. This is where those are looked for.
	bench.said = {}
	-- Why a window was told to shut, in the order the reasons went out. The reason
	-- is the server's word and the client only logs it, so it is caught on the
	-- wire: "off" is a machine somebody switched off, "reboot" is one that is
	-- coming back, and the client tells them apart by nothing else.
	bench.closed = {}
	local function record(a)
		if type(a) ~= "table" or type(a.lines) ~= "table" then return end
		for i = 1, #a.lines do bench.said[#bench.said + 1] = a.lines[i] end
	end
	function bench.heard(needle)
		for i = 1, #bench.said do
			if string.find(bench.said[i], needle, 1, true) then return true end
		end
		return false
	end

	-- Every answer the server produced, to whoever it is for. Written once, below,
	-- because the three ways a bench makes the server speak -- a line typed, a
	-- scheduler pass, the minute hand -- all deliver the same way, and one of the
	-- answers makes a window instead of reaching one.
	local deliver

	CCeroSecSystem = { instance = { sendCommand = function(_, sender, command, args)
		local replies = {}
		system.reply = function(_, _, cmd, a) replies[#replies + 1] = { cmd, a }; record(a) end
		system:OnClientCommand(command, sender, args)
		deliver(replies)
	end } }

	local function watch(w)
		w.stillValid = function() return true end
		w.painted = {}
		w.rects = {}
		w.drawText = function(self, text, x, y)
			self.painted[#self.painted + 1] = { text = text, x = x, y = y }
		end
		w.drawRect = function(self, x, y, width, height)
			self.rects[#self.rects + 1] = { x = x, y = y, w = width, h = height }
		end
		return w
	end
	-- What the glass shows, and where.
	watch(window)

	-- The client's own door for an answer that is not addressed to any window,
	-- because the window it names does not exist yet: a machine that has finished
	-- rebooting asks for one (CeroSecTerminal.onServerAnswer -> reopen), which
	-- builds it through CeroSecTerminal.open exactly as the end of the walk does.
	-- It lands in the client's registry and not in this bench's list, so it is
	-- adopted from there -- a real window, made by the real path.
	local function adopt()
		for _, w in pairs(CeroSecTerminal.instances) do
			local known = false
			for i = 1, #bench.windows do
				if bench.windows[i] == w then known = true end
			end
			if not known then
				watch(w)
				bench.windows[#bench.windows + 1] = w
			end
		end
	end

	function deliver(replies)
		for i = 1, #replies do
			local command, args = replies[i][1], replies[i][2]
			if command == "closed" then
				bench.closed[#bench.closed + 1] = args.reason
			end
			if command == "reopened" then
				CeroSecTerminal.onServerAnswer(command, args)
				adopt()
			else
				for w = 1, #bench.windows do
					bench.windows[w]:onServerCommand(command, args)
				end
			end
		end
	end

	-- A second player, at the same computer, with a window of his own. His own
	-- online id, because the server keys a watcher on it and split screen is
	-- the one case where two windows share a connection.
	function bench.addWindow()
		local other = {}
		for key, value in pairs(player) do other[key] = value end
		other.getPlayerNum = function() return 1 end
		other.getOnlineID = function() return -2 end
		_G.__players[1] = other
		local w = CeroSecTerminal:new(0, 0, other, computer)
		w:initialise()
		w:createChildren()
		watch(w)
		bench.windows[#bench.windows + 1] = w
		return w
	end

	-- The scheduler's own clock, driven by hand. One call is one pass of
	-- CeroSecJobs.tick with the wall clock moved on by a pass's worth of
	-- milliseconds, and every screen the pass produced delivered to every
	-- window -- which is exactly what the server does on Events.OnTick.
	function bench.tick(times, stepMs)
		for _ = 1, (times or 1) do
			_G.__now = _G.__now + (stepMs or CeroSec.JOB_PASS_MS)
			local replies = {}
			system.reply = function(_, _, cmd, a) replies[#replies + 1] = { cmd, a }; record(a) end
			CeroSecJobs.tick()
			deliver(replies)
		end
		bench.frame()
	end

	-- The game's minute hand: what Events.EveryOneMinute does on a real server,
	-- which is the power sweep and cron's pass over every machine whose chunk is
	-- loaded. The game clock moves a minute first, because that is what the event
	-- means -- a bench that fired the pass without moving it would be a bench
	-- cron correctly ignores.
	function bench.minute(times)
		for _ = 1, (times or 1) do
			local clock = _G.__gameTime
			clock.minutes = clock.minutes + 1
			if clock.minutes >= 60 then
				clock.minutes = 0
				clock.hour = clock.hour + 1
				if clock.hour >= 24 then
					clock.hour = 0
					clock.day = clock.day + 1
				end
			end
			local replies = {}
			system.reply = function(_, _, cmd, a) replies[#replies + 1] = { cmd, a }; record(a) end
			system:checkPower()
			system:checkCron()
			deliver(replies)
		end
		-- And the passes a job needs to actually run: cron makes a job, the
		-- scheduler is what steps it.
		bench.tick(4)
	end

	-- What is in one of the machine's own files, read the way the kernel reads
	-- /etc/passwd -- by absolute path, with no session: the two cron writes are
	-- root's and 600, which is the point of them.
	function bench.fileText(path)
		local node = CeroSecOS.systemNode(bench.object:osState(), path)
		if type(node) ~= "table" or node.type ~= "file" then return nil end
		return node.data or ""
	end

	-- Put a script on the disk, the way the editor would, and make it runnable.
	function bench.script(path, text)
		local state = object:osState()
		local session = { user = "admin", cwd = "/home/admin", stamp = 1 }
		local done, reason = CeroSecOS.writeFile(state, session, path, text, false, 100)
		if done == nil then error("cannot write " .. path .. ": " .. tostring(reason), 2) end
		local node = CeroSecOS.getNode(state, session, path)
		node.mode = 755
		return node
	end

	function bench.frame()
		for i = 1, #bench.windows do
			local w = bench.windows[i]
			w.painted = {}
			w.rects = {}
			w:prerender()
			w:render()
		end
	end

	-- Type a line and press Enter, the way the box hands it over.
	--
	-- The wall clock moves a second first, and it has to. Every line is a JOB
	-- now, and what a job writes reaches the screen at CeroSec.JOB_OUT_PER_SEC
	-- lines a second, per machine -- so a bench that typed fifty lines inside
	-- the same millisecond would run out of that second's room and watch the
	-- rest of its output sit in the queue. A player types slower than that; a
	-- bench that did not move the clock would be asserting against a machine
	-- nobody is sitting at.
	function bench.enter(line)
		_G.__now = _G.__now + 1000
		window.entry:setText(line or "")
		window.entry:setCursorPos(#(line or ""))
		window:onCommandEntered()
	end

	-- Every line of text painted on the glass this frame.
	function bench.glass()
		local out = {}
		for i = 1, #window.painted do out[#out + 1] = window.painted[i].text end
		return out
	end

	function bench.painted(needle)
		for i = 1, #window.painted do
			local text = window.painted[i].text
			if type(text) == "string" and string.find(text, needle, 1, true) then return true end
		end
		return false
	end

	-- Open, let the BIOS finish typing itself out, and log in.
	function bench.login(name, password)
		window:askForScreen()
		_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
		bench.frame()
		bench.enter(name)
		bench.enter(password or "")
		bench.frame()
	end

	-- A window closed and opened again, on the same machine. Everything the
	-- machine holds -- the screen, the session, the shell's variables, the
	-- history -- has to be there when it comes back; everything the WINDOW held
	-- is gone, because this is a different window.
	function bench.reopen()
		local w = bench.windows[#bench.windows]
		w:close()
		for i = #bench.windows, 1, -1 do
			if bench.windows[i] == w then table.remove(bench.windows, i) end
		end
		local fresh = bench.addWindow()
		fresh:askForScreen()
		_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
		bench.frame()
		return fresh
	end

	-- Put a line in the box with the caret at the end, WITHOUT pressing Enter:
	-- what a player has half typed when he reaches for Tab.
	function bench.typed(line, cursor)
		window.entry:setText(line or "")
		window.entry:setCursorPos(cursor or #(line or ""))
	end

	-- Tab, the way the game delivers it: one of the two keys a focused text box
	-- is handed, straight into onOtherKey.
	function bench.tab()
		_G.__now = _G.__now + 100
		window:onOtherKey(Keyboard.KEY_TAB)
	end

	-- Type a line at a window that is not the first one.
	function bench.enterOn(w, line)
		_G.__now = _G.__now + 1000
		w.entry:setText(line or "")
		w.entry:setCursorPos(#(line or ""))
		w:onCommandEntered()
	end

	-- Every line of text painted on one window's glass this frame.
	function bench.paintedOn(w, needle)
		for i = 1, #w.painted do
			local text = w.painted[i].text
			if type(text) == "string" and string.find(text, needle, 1, true) then return true end
		end
		return false
	end

	return bench
end

--
-- Opening a file with edit
--
-- The bug this bench exists for: `edit notes.txt` in the home directory came
-- back as a prompt with no editor on the glass at all.
--

do
	local bench = newBench()
	bench.login("admin")
	eq("logged in at a shell", bench.window.mode, "shell")

	bench.enter("edit notes.txt")
	bench.frame()

	eq("the machine is in the editor", CeroSec.consoleWaiting(bench.object.console), "edit")
	eq("and so is the window", bench.window.mode, "edit")
	check("the window holds the keyboard on the buffer", bench.window:editing())
	-- The screen, not the fields: the title bar of nano's shape, the key bar
	-- under it, and no shell prompt anywhere.
	check("the editor's title bar names the file", bench.painted("/home/admin/notes.txt"))
	check("the key bar says how to leave", bench.painted("Esc exit"))
	check("the key bar says how to save", bench.painted("Tab save"))
	check("nothing of the shell is on the glass", not bench.painted("admin@"))

	-- A file that does not exist yet opens empty and writable.
	eq("the buffer is empty", bench.window:bufferText(), "")
	eq("and it may be written", bench.window.edit.readonly, false)

	-- Typing in it and saving with Tab puts the file on the disk.
	bench.window.entry:type("hello")
	bench.frame()
	check("what is typed is on the glass", bench.painted("hello"))
	bench.window:onOtherKey(Keyboard.KEY_TAB)
	bench.frame()
	local state = bench.object:osState()
	local session = { user = "admin", cwd = "/home/admin", stamp = 1 }
	local node = CeroSecOS.getNode(state, session, "/home/admin/notes.txt")
	check("the file is on the disk", node ~= nil and node.type == "file")
	eq("with what was typed in it", node.data, "hello")
	check("and the machine says so", bench.painted("Saved 5 bytes"))

	-- Escape leaves the editor and the shell is back.
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	eq("Escape leaves the editor", bench.window.mode, "shell")
	check("the shell prompt is back", bench.painted("admin@"))
end

-- A file that is already there opens with its contents.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("echo hello > notes.txt")
	bench.frame()
	bench.enter("edit notes.txt")
	bench.frame()
	eq("an existing file opens in the editor", bench.window.mode, "edit")
	eq("with what is in it", bench.window:bufferText(), "hello")
	check("and its name on the bar", bench.painted("/home/admin/notes.txt"))
end

-- A file the account may read and not write opens read-only, and says so.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("edit /etc/motd")
	bench.frame()
	eq("a system file still opens", bench.window.mode, "edit")
	eq("read-only", bench.window.edit.readonly, true)
	check("the bar says so", bench.painted("[read-only]"))
	-- Tab on it refuses at the door rather than at the write.
	bench.window:onOtherKey(Keyboard.KEY_TAB)
	bench.frame()
	check("saving is refused", bench.painted("Cannot save: permission denied"))
end

-- A directory is not a file, and the refusal stays in the shell.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("edit /etc")
	bench.frame()
	eq("a directory does not open an editor", bench.window.mode, "shell")
	check("and the shell says why", bench.painted("is a directory"))
end

--
-- Enter on an empty line
--
-- It used to echo the prompt with nothing after it, which put a bare prompt row
-- on the screen under the one being typed at -- the second prompt line in the
-- screenshot. The line being typed at is drawn by the window; a prompt with
-- nothing on it is not a line of output.
--

do
	local bench = newBench()
	bench.login("admin")
	local before = #bench.object.console.lines
	bench.enter("")
	bench.frame()
	eq("an empty line prints nothing", #bench.object.console.lines, before)
	bench.enter("   ")
	bench.frame()
	eq("nor does a line of spaces", #bench.object.console.lines, before)
	-- A line with a command in it still echoes.
	bench.enter("pwd")
	bench.frame()
	check("a real command still echoes", #bench.object.console.lines > before)
end

--
-- The block cursor sits at the end of the prompt
--
-- It sat about twelve columns to the right of it in the game, with an empty gap
-- between the "$" and the block. The row and the column are counted, and
-- terminal_test.lua pins that; what was wrong is where a column IS on the
-- glass, which came from a cell width measured once at load time -- see the
-- font above -- and multiplied by a twenty-one character prompt.
--
-- So the grid is measured with the game up, and the cursor is put at the width
-- of the text in front of it rather than at a count of cells.
--

do
	local bench = newBench()
	bench.login("admin")
	bench.frame()

	local prompt = bench.window.prompt
	eq("the prompt is the shell's", prompt, "admin@ksp-a-a:~$ ")

	-- The block is the one rect as wide as a character on the input row.
	local block = nil
	for i = 1, #bench.window.rects do
		local rect = bench.window.rects[i]
		if rect.w <= CHAR_W * 2 and rect.h >= FONT_H then block = rect end
	end
	check("there is a block cursor", block ~= nil)
	local promptX = nil
	for i = 1, #bench.window.painted do
		local paint = bench.window.painted[i]
		if paint.text == prompt then promptX = paint.x end
	end
	check("the prompt is painted", promptX ~= nil)
	eq("the cursor sits right after the prompt", block.x, promptX + CHAR_W * #prompt)
	eq("and is one character wide", block.w, CHAR_W)

	-- And with something typed, the text starts at the end of the prompt and
	-- the cursor at the end of the text.
	bench.window.entry:type("ls")
	bench.frame()
	local typedX = nil
	for i = 1, #bench.window.painted do
		if bench.window.painted[i].text == "ls" then typedX = bench.window.painted[i].x end
	end
	check("what is typed is painted", typedX ~= nil)
	eq("right after the prompt, no gap", typedX, promptX + CHAR_W * #prompt)
	block = nil
	for i = 1, #bench.window.rects do
		local rect = bench.window.rects[i]
		if rect.w <= CHAR_W * 2 and rect.h >= FONT_H then block = rect end
	end
	eq("and the cursor after what was typed", block.x, promptX + CHAR_W * (#prompt + 2))
end

--
-- Both halves of the blink are the same cursor
--
-- On the glass the block jumped a column between one half of the blink and the
-- other: lit, it sat a column right of the last character typed, with a gap;
-- dark, a column left of it, with that character drawn inverted under it. One
-- cursor, two columns. So the column is asserted in both halves here, on the
-- same frame's worth of paint, and the column past the end of the text -- the
-- gap that was on the glass -- is asserted empty.
--

do
	local bench = newBench()
	bench.login("admin")
	local prompt = bench.window.prompt

	-- The block is the one rect a character wide on the input row.
	local function blockOf(window)
		local found = nil
		for i = 1, #window.rects do
			local rect = window.rects[i]
			if rect.w <= CHAR_W * 2 and rect.h >= FONT_H then found = rect end
		end
		return found
	end
	-- What was painted at a given x, if anything, ignoring the glow copy that
	-- drawScreenText lays down at an offset.
	local function paintedAt(window, x)
		local out = {}
		for i = 1, #window.painted do
			local paint = window.painted[i]
			if paint.x == x then out[#out + 1] = paint.text end
		end
		return out
	end
	-- Render one frame in each half of the blink, and answer what each half
	-- painted. The clock is the window's only blink input.
	local function bothPhases()
		local phases = {}
		for _ = 1, 2 do
			local lit = math.floor(_G.__now / CeroSec.CURSOR_BLINK_MS) % 2 == 0
			bench.frame()
			phases[lit and "lit" or "dark"] = {
				block = blockOf(bench.window),
				painted = paintedAt(bench.window, blockOf(bench.window) and blockOf(bench.window).x or -1),
			}
			_G.__now = _G.__now + CeroSec.CURSOR_BLINK_MS
		end
		return phases
	end

	-- Nothing typed: both halves put the block right after the prompt.
	local phase = bothPhases()
	check("the lit half draws a block", phase.lit.block ~= nil)
	check("the dark half draws one too", phase.dark.block ~= nil)
	eq("and both at the same column", phase.lit.block.x, phase.dark.block.x)

	-- One character typed: the block is right after it, in both halves, with
	-- nothing in the column past it and no character painted under it.
	bench.window.entry:type("a")
	local promptX = nil
	bench.frame()
	for i = 1, #bench.window.painted do
		if bench.window.painted[i].text == prompt then promptX = bench.window.painted[i].x end
	end
	check("the prompt is painted", promptX ~= nil)
	local endX = promptX + CHAR_W * (#prompt + 1)
	phase = bothPhases()
	eq("one char: the lit block is right after it", phase.lit.block.x, endX)
	eq("one char: the dark block is at the same column", phase.dark.block.x, endX)
	eq("one char: nothing is painted under the lit block", #phase.lit.painted, 0)
	eq("one char: nor under the dark one", #phase.dark.painted, 0)
	-- The gap: the column one past the end of the text is empty in both halves.
	for name, half in pairs(phase) do
		check(name .. ": no block a column past the text",
			half.block.x ~= endX + CHAR_W)
		eq(name .. ": and nothing painted there", #paintedAt(bench.window, endX + CHAR_W), 0)
	end

	-- Two characters, and the same again: no gap after the b.
	bench.window.entry:type("b")
	phase = bothPhases()
	eq("ab: the lit block is right after the b", phase.lit.block.x, endX + CHAR_W)
	eq("ab: and the dark one with it", phase.dark.block.x, endX + CHAR_W)

	-- The cursor walked back into the middle of what was typed: now it covers
	-- the b, in both halves -- inverted under the lit block, and still there,
	-- not eaten, while the block is dark.
	bench.window.entry:setCursorPos(1)
	phase = bothPhases()
	eq("mid: the lit block is on the b", phase.lit.block.x, endX)
	eq("mid: and so is the dark one", phase.dark.block.x, endX)
	local function covers(list, glyph)
		for i = 1, #list do if list[i] == glyph then return true end end
		return false
	end
	check("mid: the lit half paints the b under its block", covers(phase.lit.painted, "b"))
	check("mid: and the dark half paints it too", covers(phase.dark.painted, "b"))
end

--
-- The BIOS, end to end
--
-- Root may wipe the machine he is standing at -- that is what root is, and the
-- protection is that root has a password. So the way back cannot be a guard on
-- the command; it has to be underneath the operating system, where a player
-- who has just destroyed one can still reach it.
--
-- The whole round trip: break /bin, log out, open the window again, refuse the
-- repair, come back to the question, take it, and use the machine.
--

do
	local bench = newBench()
	bench.login("root")
	eq("root is at a shell", bench.window.mode, "shell")

	-- Something of his own on the disk, to see it survive.
	bench.enter("mkdir /home/admin/work")
	bench.enter('write /home/admin/work/notes.txt "keep me"')
	bench.frame()

	bench.enter("rm -r /bin")
	bench.frame()
	-- Still logged in, and the machine is already unusable. The SHELL is a file
	-- in /bin like everything else, so what is missing now is not `ls`: it is
	-- the thing that would have read the line `ls` was on.
	bench.enter("ls")
	bench.frame()
	check("the shell itself is gone", bench.painted("sh: command not found"))
	bench.enter("help")
	bench.frame()
	check("help says the system is damaged", bench.painted("the system is damaged"))

	-- exit is a builtin, so a player can always leave a machine he has wiped.
	bench.enter("exit")
	bench.frame()
	eq("exit still works with no /bin", bench.window.mode, "prompt")

	-- Opening the window again: the BIOS looks at the disk first.
	bench.window:askForScreen()
	bench.frame()
	check("the BIOS says there is nothing to boot", bench.painted("No operating system found."))
	eq("and it asks", bench.window.prompt, "Restore system? (y/n) ")
	eq("at an ordinary prompt", bench.window.mode, "prompt")
	eq("with nothing masked", bench.window.mask, false)
	check("and no login prompt under it", not bench.painted("login: "))

	-- n: the screen stays on the refusal, and nothing is being asked.
	bench.enter("n")
	bench.frame()
	check("the message is still there", bench.painted("No operating system found."))
	eq("and nothing is asked", bench.window.prompt, "")
	eq("halted", CeroSec.consoleWaiting(bench.object.console), "halted")
	eq("but the window still has the keyboard", bench.window.mode, "prompt")

	-- Anything typed at a halted machine brings the question back.
	bench.enter("")
	bench.frame()
	eq("the question comes back", bench.window.prompt, "Restore system? (y/n) ")
	eq("and the machine is not halted any more", CeroSec.consoleHalted(bench.object.console), false)

	-- Anything that is not an answer asks again rather than guessing.
	bench.enter("maybe")
	bench.frame()
	eq("a non-answer asks again", bench.window.prompt, "Restore system? (y/n) ")

	-- y repairs it, and the machine goes on to its login prompt.
	bench.enter("y")
	bench.frame()
	eq("the machine boots", bench.window.prompt, "login: ")
	-- The greeting, read off the constant it is built from: a version typed
	-- into a bench is a second place the number lives.
	check("and greets whoever is standing there", bench.painted(CeroSecOS.MOTD))

	bench.enter("root")
	bench.enter("")
	bench.frame()
	eq("root is back at a shell", bench.window.mode, "shell")
	bench.enter("ls /home/admin/work")
	bench.frame()
	check("ls works again", bench.painted("notes.txt"))

	-- And what was on the disk is still on it, byte for byte.
	local state = bench.object:osState()
	check("the machine validates", state ~= nil)
	local node = CeroSecOS.systemNode(state, "/home/admin/work/notes.txt")
	check("the file in /home survived the repair", node ~= nil)
	eq("with its contents", node.data, "keep me")
end

-- A machine wiped and left: the next player to open the window meets the
-- question, and not somebody else's answer to it.
do
	local bench = newBench()
	bench.login("root")
	bench.enter("rm -r /bin")
	bench.frame()
	bench.enter("exit")
	bench.frame()

	bench.window:askForScreen()
	bench.frame()
	bench.enter("n")
	bench.frame()
	eq("the first player left it halted", CeroSec.consoleHalted(bench.object.console), true)

	-- The screen belongs to the machine, so a window opened on it now finds the
	-- refusal and not a fresh question.
	bench.window:askForScreen()
	bench.frame()
	eq("a window opened on it finds the refusal", bench.window.prompt, "")
	check("with the message on the glass", bench.painted("No operating system found."))
	eq("and the machine is still halted", CeroSec.consoleHalted(bench.object.console), true)
end

--
-- Escape: an interrupt when the machine is in the middle of something, a close
-- when it is not.
--
-- The rule lives in two halves that must agree: the server says whether the
-- machine is busy (screenArgs.active) and the window decides what Escape does
-- with that. Neither half is worth testing without the other -- a window that
-- interrupted the wrong thing and a server that said the wrong thing look the
-- same from the chair.
--

do
	local bench = newBench()
	bench.login("admin")
	bench.frame()
	eq("nothing is going on at a shell", bench.window.active, false)

	-- A second pair of eyes at the same glass: the interrupt is the machine's,
	-- so what it leaves behind is on his screen too and not only on the screen
	-- of the man who pressed the key.
	local other = bench.addWindow()
	other:askForScreen()

	bench.enter("passwd")
	bench.frame()
	eq("passwd asks", bench.window.prompt, "Old password: ")
	eq("and the second window is asked the same thing", other.prompt, "Old password: ")
	eq("and the machine says it is in the middle of something", bench.window.active, true)
	eq("the answer is masked", bench.window.mask, true)

	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	check("the window is still open", not bench.window.closing)
	check("the interrupted line is on the glass", bench.painted("Old password: ^C"))
	eq("the question is off the machine", bench.object.console.prompt, nil)
	eq("and the shell is back", bench.window.mode, "shell")
	check("with its prompt", bench.painted("admin@"))
	eq("nothing is going on any more", bench.window.active, false)
	eq("and the session is untouched", bench.object.console.user, "admin")
	check("the second window saw the ^C too", other.painted ~= nil and (function()
		for i = 1, #other.painted do
			local text = other.painted[i].text
			if type(text) == "string" and string.find(text, "Old password: ^C", 1, true) then
				return true
			end
		end
		return false
	end)())
	eq("and is back at the shell as well", other.mode, "shell")

	-- And the shell still works afterwards: what was dropped was the question.
	bench.enter("whoami")
	bench.frame()
	check("the shell answers", bench.painted("admin"))
end

-- Idle, Escape closes -- and the machine keeps everything.
do
	local bench = newBench()
	bench.login("admin")
	bench.frame()
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	check("Escape at an idle shell closes the window", bench.window.closing)
	eq("the machine is still on", bench.object.on, true)
	eq("and still logged in", bench.object.console.user, "admin")
end

-- Half way through a login: the name goes, the login prompt comes back.
do
	local bench = newBench()
	bench.window:askForScreen()
	_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
	bench.frame()
	eq("at the login prompt", bench.window.prompt, "login: ")
	eq("with nothing going on", bench.window.active, false)

	bench.enter("admin")
	bench.frame()
	eq("the password is being asked for", bench.window.prompt, "password: ")
	eq("and that is something to interrupt", bench.window.active, true)

	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	check("the window is still open", not bench.window.closing)
	check("the interrupted line is on the glass", bench.painted("password: ^C"))
	eq("and the machine is back at login", bench.window.prompt, "login: ")
	eq("with no name half typed", bench.object.console.pending, nil)
	eq("and nobody logged in", bench.object.console.user, nil)

	-- Escape at the bare login prompt is a close, not an interrupt: there is
	-- nothing behind it to give up on.
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	check("Escape at login closes", bench.window.closing)
end

-- The BIOS' question is not interruptible: there is nothing behind it.
do
	local bench = newBench()
	bench.login("root")
	bench.enter("rm -r /bin")
	bench.frame()
	bench.window:askForScreen()
	bench.frame()
	eq("the BIOS is asking", bench.window.prompt, "Restore system? (y/n) ")
	eq("and that is not something to interrupt", bench.window.active, false)
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	check("Escape closes, as it always has", bench.window.closing)
	check("and the question is still on the machine",
		bench.object.console.prompt ~= nil)
end

-- A sudo question is interruptible like any other.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("sudo cat /etc/passwd")
	bench.frame()
	eq("sudo asks", bench.window.prompt, "[sudo] password for admin: ")
	eq("masked", bench.window.mask, true)
	eq("and interruptible", bench.window.active, true)
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	check("the line is on the glass", bench.painted("[sudo] password for admin: ^C"))
	eq("and the shell is back", bench.window.mode, "shell")
	-- Nothing of the file leaked on the way past.
	check("and the accounts were not printed", not bench.painted("$cs1$"))
end

--
-- shutdown and reboot, from the chair
--

do
	local bench = newBench()
	bench.login("admin")
	bench.enter("shutdown")
	bench.frame()
	check("admin is refused", bench.painted("shutdown: permission denied"))
	eq("and the machine is still on", bench.object.on, true)
	check("and the window is still open", not bench.window.closing)
end

do
	local bench = newBench()
	bench.login("root")
	bench.enter("shutdown")
	eq("the machine is off", bench.object.on, false)
	eq("its screen is gone with it", bench.object.console, nil)
	check("and the window shut itself", bench.window.closing)
end

--
-- reboot: the machine goes dark, and the window comes back
--
-- Mathieu, in the game: "reboot should also turn the screen off, and the
-- terminal UI should open again once it booted." It used to be turnOff and
-- turnOn in the same breath, which left the sprite lit and the boot typing
-- itself out inside a window that had never shut -- a machine that never went
-- down. So what is asserted here is the physical machine as much as the glass:
-- the unlit tile, the client's copy the glow is drawn from, the three dark
-- seconds, and then a NEW window with a token of its own.

-- The machine as the WORLD has it: the tile's own object with the sprite on it,
-- the square it stands on, and the cell that answers for that square. newBench
-- stubs all three out, because most of this file is about the glass -- but a
-- reboot is a machine going physically off and physically back, so the sprite is
-- half of what is being asserted, and the client cannot find the computer to put
-- a window back on without the cell.
local function embody(bench)
	local kit = { loaded = true }
	-- __class, because the device layer asks what an object on a square IS before
	-- it makes a /dev entry of it (CeroSecDevices.classify), and the plain
	-- IsoObject a vanilla computer tile is is none of the things it looks for.
	local iso = { __class = "IsoObject", sprite = CeroSec.SPRITES_ON["S"], modData = {} }
	iso.getSpriteName = function() return iso.sprite end
	iso.setSpriteFromName = function(_, name) iso.sprite = name end
	iso.transmitUpdatedSpriteToClients = function() end
	iso.hasModData = function() return true end
	iso.getModData = function() return iso.modData end
	iso.transmitModData = function() end
	local square = {
		getX = function() return 10 end,
		getY = function() return 10 end,
		getZ = function() return 0 end,
		getRoom = function() return nil end,
		getBuilding = function() return nil end,
		getObjects = function() return javaList({ iso }) end,
		-- The other two lists a square answers with, and the socket. Empty and
		-- live: the computer's own tile is the only thing in this cell, so /dev on
		-- this machine is the door-and-light-less room it really is.
		getWorldObjects = function() return javaList({}) end,
		getMovingObjects = function() return javaList({}) end,
		haveElectricity = function() return true end,
		hasGridPower = function() return false end,
	}
	iso.getSquare = function() return kit.loaded and square or nil end
	kit.iso = iso
	-- The stubs off: the real syncSprite, with a real iso object to put a sprite
	-- on and a real square under it.
	bench.object.syncSprite = nil
	bench.object.getIsoObject = function() return kit.loaded and iso or nil end
	bench.object.getSquare = function() return kit.loaded and square or nil end
	-- And the cell the CLIENT looks the computer up in, which is a different
	-- question from the machine's own square: the reopen is handed coordinates and
	-- has to find the tile itself, because a Java handle does not travel.
	_G.__world = { getGridSquare = function(_, x, y, z)
		if not kit.loaded then return nil end
		if x == 10 and y == 10 and z == 0 then return square end
		return nil
	end }
	return kit
end

-- The dark interval, counted the way the server counts it: the scheduler's own
-- pass on the wall clock, like a pending `shutdown +N`.
local function waitOutTheDark(bench)
	_G.__now = _G.__now + CeroSec.REBOOT_DARK_MS
	bench.tick(1)
end

do
	local bench = newBench()
	local kit = embody(bench)
	bench.login("root")
	eq("the tile starts lit", kit.iso.sprite, CeroSec.SPRITES_ON["S"])

	bench.enter("reboot")
	bench.frame()

	-- Off, physically. The sprite is what somebody in the room sees; the client's
	-- copy of `on` is what the screen's glow is drawn from
	-- (CCeroSecObject:syncLight), and it is the only server-side proof of a glow
	-- there is.
	eq("the machine is off", bench.object.on, false)
	eq("the tile is the unlit sprite", kit.iso.sprite, CeroSec.SPRITES_OFF["S"])
	eq("the client was told, so the glow is gone", bench.client.on, false)
	eq("and there is no screen to read", bench.object.console, nil)
	check("the window shut", bench.window.closing)
	eq("and it was told this machine is coming back",
		bench.closed[#bench.closed], "reboot")
	eq("nobody is watching a dark machine", bench.object.watchers, nil)

	-- And it stays dark. Three seconds of a 1993 desktop, and nothing in them.
	bench.tick(10)
	eq("a second in it is still off", bench.object.on, false)
	eq("with nothing reopened", #bench.windows, 1)

	waitOutTheDark(bench)
	eq("then it comes back on", bench.object.on, true)
	eq("the tile is lit again", kit.iso.sprite, CeroSec.SPRITES_ON["S"])
	eq("the client was told, so the glow is back", bench.client.on, true)
	eq("and a window came with it", #bench.windows, 2)

	local back = bench.windows[2]
	check("a window of its own, on a fresh token", back.token ~= bench.window.token)
	eq("at the same machine", back.cx, 10)
	eq("and the character is at the keyboard again", back.typeHeight ~= nil, true)
	eq("it is watching the BIOS type itself out", back.revealing, true)

	_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
	bench.frame()
	check("the BIOS is on the new glass", bench.paintedOn(back, CeroSec.BOOT_LINES[1]))
	eq("and it ends at a login prompt", back.prompt, "login: ")
	eq("with nobody logged in", bench.object.console.user, nil)

	-- And the disk came through it: a reboot is not a repair.
	bench.enterOn(back, "root")
	bench.enterOn(back, "")
	bench.enterOn(back, "ls /bin")
	bench.frame()
	check("the machine is the one it was", bench.paintedOn(back, "shutdown"))
end

-- Two pairs of eyes at the same glass: both windows go, and both come back.
do
	local bench = newBench()
	local kit = embody(bench)
	bench.login("root")
	local other = bench.addWindow()
	other:askForScreen()
	bench.frame()
	eq("the second window reads the same screen", other.mode, "shell")

	bench.enter("reboot")
	bench.frame()
	check("the first window shut", bench.window.closing)
	check("and so did the second", other.closing)
	eq("both were told the same word", bench.closed[#bench.closed], "reboot")
	eq("the tile is unlit for both of them", kit.iso.sprite, CeroSec.SPRITES_OFF["S"])

	waitOutTheDark(bench)
	eq("and two windows came back", #bench.windows, 4)
	local first, second = bench.windows[3], bench.windows[4]
	check("each on its own token", first.token ~= second.token)
	eq("one for each survivor", first.playerNum ~= second.playerNum, true)
	eq("both replaying the boot", first.revealing and second.revealing, true)
end

-- A second survivor standing at the same desk who never opened a terminal. The
-- window comes back for the WATCHERS and not for whoever happens to be standing
-- there: he was not looking at a screen before the reboot and he is not handed one
-- after it.
do
	local bench = newBench()
	embody(bench)
	bench.login("root")
	-- A window of his own, never opened on the machine: the server has never heard
	-- of him, which is exactly what a bystander is.
	bench.addWindow()

	bench.enter("reboot")
	bench.frame()
	waitOutTheDark(bench)
	eq("the machine came back", bench.object.on, true)
	eq("one window came back, not two", #bench.windows, 3)
	eq("and the one that did is the one that was open",
		bench.windows[3].playerNum, bench.window.playerNum)
end

-- A survivor who walked away from the desk while the screen was dark.
do
	local bench = newBench()
	local kit = embody(bench)
	bench.login("root")
	bench.enter("reboot")
	bench.frame()
	check("his window shut with the machine", bench.window.closing)

	-- Ten squares away by the time it comes up. Nothing opens under him: he walks
	-- back and uses the computer by hand, like anybody arriving at a lit screen.
	bench.player.getX = function() return 20.5 end

	waitOutTheDark(bench)
	eq("the machine came back up", bench.object.on, true)
	eq("the tile is lit", kit.iso.sprite, CeroSec.SPRITES_ON["S"])
	eq("but no window did", #bench.windows, 1)
	eq("and nobody is watching it", bench.object.watchers, nil)
end

-- The power went while the machine was down, which is the one thing a real
-- machine cannot come back from on its own.
do
	local bench = newBench()
	local kit = embody(bench)
	bench.login("root")
	bench.enter("reboot")
	bench.frame()
	bench.object.hasPower = function() return false end

	waitOutTheDark(bench)
	eq("it stays dark", bench.object.on, false)
	eq("the tile stays unlit", kit.iso.sprite, CeroSec.SPRITES_OFF["S"])
	eq("no window came back", #bench.windows, 1)
	eq("and nothing is pending any more", bench.object.rebooting, nil)

	-- And a hand at the switch is what brings it back, once there is a wire again.
	bench.object.hasPower = function() return true end
	bench.object:toggle()
	eq("switched on by hand", bench.object.on, true)
	eq("and the tile with it", kit.iso.sprite, CeroSec.SPRITES_ON["S"])
end

-- Switched on by hand while it was dark, and switched off again. The order that
-- was given was a reboot, but a hand at the case has overtaken it: the machine
-- stays off, and nothing comes back three seconds later.
do
	local bench = newBench()
	local kit = embody(bench)
	bench.login("root")
	bench.enter("reboot")
	bench.frame()
	bench.object:toggle()
	eq("switched on by hand", bench.object.on, true)
	bench.object:toggle()
	eq("and off again", bench.object.on, false)
	eq("the dark interval went with it", bench.object.rebooting, nil)

	waitOutTheDark(bench)
	eq("it stays off", bench.object.on, false)
	eq("the tile stays unlit", kit.iso.sprite, CeroSec.SPRITES_OFF["S"])
	eq("and no window came back", #bench.windows, 1)
end

-- A machine whose chunk went away while it was dark: it comes up, because power
-- and jobs are the machine's own business, but nothing is opened on a tile the
-- client cannot see.
do
	local bench = newBench()
	local kit = embody(bench)
	bench.login("root")
	bench.enter("reboot")
	bench.frame()
	kit.loaded = false

	waitOutTheDark(bench)
	eq("no window on a machine out of the world", #bench.windows, 1)
	eq("and nobody is watching it", bench.object.watchers, nil)
end

-- halt is the other order, and it is unchanged: off, and no coming back.
do
	local bench = newBench()
	local kit = embody(bench)
	bench.login("root")
	bench.enter("halt")
	bench.frame()
	eq("the machine is off", bench.object.on, false)
	eq("the tile is unlit", kit.iso.sprite, CeroSec.SPRITES_OFF["S"])
	eq("the window was told it is over, not that it is coming back",
		bench.closed[#bench.closed], "off")
	eq("nothing is pending", bench.object.rebooting, nil)

	waitOutTheDark(bench)
	eq("and it is still off three seconds later", bench.object.on, false)
	eq("with no window back", #bench.windows, 1)
end

-- sudo reboot: the same, from an account that is not root.
do
	local bench = newBench()
	local kit = embody(bench)
	bench.login("admin")
	bench.enter("sudo reboot")
	bench.frame()
	eq("sudo asks first", bench.window.prompt, "[sudo] password for admin: ")
	eq("the machine is still on while it asks", bench.object.on, true)

	bench.enter("")
	bench.frame()
	eq("and then it goes dark", bench.object.on, false)
	eq("tile and all", kit.iso.sprite, CeroSec.SPRITES_OFF["S"])
	check("with the window shut", bench.window.closing)

	waitOutTheDark(bench)
	eq("and comes back", bench.object.on, true)
	eq("with nobody logged in", bench.object.console.user, nil)
	eq("and his window back", #bench.windows, 2)
end

-- The world this section laid out is its own. Every bench above it runs on a game
-- with no cell at all, and so does every bench below.
_G.__world = nil


-- sudo edit: the buffer is root's, and it saves.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("edit /etc/motd")
	bench.frame()
	eq("admin gets it read-only", bench.window.edit.readonly, true)
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()

	bench.enter("sudo edit /etc/motd")
	bench.frame()
	eq("sudo asks first", bench.window.mode, "prompt")
	bench.enter("")
	bench.frame()
	eq("and then the editor is up", bench.window.mode, "edit")
	eq("writable", bench.window.edit.readonly, false)
	eq("as root", bench.object.console.edit.user, "root")
	check("with the file on the bar", bench.painted("/etc/motd"))

	bench.window.entry:setText("welcome to the lab")
	bench.window.entry:setCursorPos(18)
	bench.window:onOtherKey(Keyboard.KEY_TAB)
	bench.frame()
	check("the save went through", bench.painted("Saved 18 bytes"))
	local state = bench.object:osState()
	eq("and the file on the disk is the new one",
		CeroSecOS.systemNode(state, "/etc/motd").data, "welcome to the lab")
	eq("still root's", CeroSecOS.systemNode(state, "/etc/motd").owner, "root")
	eq("and the console is still admin's", bench.object.console.user, "admin")
end

-- A machine saved by an older build, opened for the first time on this one. The
-- top-up happens on the load path (SCeroSecObject:osState), which is the only
-- place it can: nothing else is called before the validator gets a look.
do
	local bench = newBench()
	local old = CeroSecOS.newState("ksp-old")
	old.sysv = nil
	old.fs.children.bin.children.sudo = nil
	old.fs.children.bin.children.shutdown = nil
	old.fs.children.bin.children.reboot = nil
	old.fs.children.bin.children.restart = nil
	old.fs.children.etc.children.sudoers = nil
	old.fs.children.home.children.admin.children =
		{ ["notes.txt"] = CeroSecOS.newFile("admin", 644, "keep me") }
	bench.object.os = old

	bench.login("admin")
	eq("it boots straight to its shell", bench.window.mode, "shell")
	check("and never meets the BIOS", not bench.painted("No operating system found."))

	bench.enter("sudo whoami")
	bench.frame()
	eq("sudo is on it now", bench.window.prompt, "[sudo] password for admin: ")
	bench.enter("")
	bench.frame()
	check("and it runs", bench.painted("root"))

	bench.enter("ls /home/admin")
	bench.frame()
	check("what was on the disk is still on it", bench.painted("notes.txt"))
	eq("and the machine is at this build's contents",
		bench.object:osState().sysv, CeroSecOS.SYSTEM_VERSION)
end

--
-- The BIOS tells the truth about the drive, and the clock is the game's.
--

do
	local bench = newBench()
	bench.login("admin")

	-- The number on the BIOS line is the ceiling a write really dies on, and
	-- not the 20MB that used to be typed into the boot lines by hand.
	check("the BIOS announces the real drive", bench.painted(
		"Detecting drives ... hda " .. CeroSecOS.diskLabel()))
	check("and never a drive the machine has not got", not bench.painted("20MB"))
	eq("because the label is the ceiling", CeroSecOS.diskLabel(),
		tostring(CeroSecOS.DISK_BYTES / 1024) .. "K")

	-- The whole round trip for the clock: the game's calendar, through the
	-- server, onto the glass.
	bench.enter("date")
	bench.frame()
	check("date shows the game's calendar", bench.painted("Thu Jul  8 14:32:00 1993"))

	-- And it FOLLOWS the game: a machine whose clock never moved would pass the
	-- line above and fail this one.
	_G.__gameTime = { year = 1993, month = 11, day = 24, hour = 6, minutes = 5 }
	bench.enter("date")
	bench.frame()
	check("and moves with it", bench.painted("Sat Dec 25 06:05:00 1993"))

	-- A file written at that minute carries it, on the disk and on the screen.
	bench.enter("touch gift.txt")
	bench.enter("ls -l")
	bench.frame()
	check("a file it wrote is listed with that minute", bench.painted("Dec 25 06:05  gift.txt"))
	local node = CeroSecOS.systemNode(bench.object:osState(), "/home/admin/gift.txt")
	check("and the node really carries it", node ~= nil)
	eq("to the second", CeroSecOS.mtimeOf(node),
		CeroSecOS.timeFromParts(1993, 12, 25, 6, 5, 0))

	-- df on the real machine, through the wire.
	bench.enter("df")
	bench.frame()
	check("df names the drive", bench.painted("hda"))
	check("and its size", bench.painted(tostring(CeroSecOS.DISK_BYTES)))

	_G.__gameTime = { year = 1993, month = 6, day = 7, hour = 14, minutes = 32 }
end

--
-- The machine's name, on the title bar, under the cursor, and in the echo
--
-- From a screenshot of the live game: after `hostname office` the title bar and
-- the prompt being typed at both read "office", while every line echoed into
-- the console read "root@nil:~# date". One fact read down two paths -- and the
-- echo path asked for a prompt without handing over the name, so it was built
-- through tostring(nil). The three of them are asserted together here, because
-- two of them were right the whole time.
--

do
	local bench = newBench()
	bench.login("root")
	bench.enter("hostname office")
	bench.enter("date")
	bench.frame()
	check("the echoed line carries the machine's name",
		bench.painted("root@office:~# date"))
	check("and no line says nil", not bench.painted("root@nil"))
	eq("the live prompt has it too", bench.window.prompt, "root@office:~# ")

	-- The title is set on `opened`, so it is the reopen that renames the window
	-- -- and the lines that were echoed before it keep the name they were echoed
	-- with, because they are the machine's own screen and not a redraw.
	bench.window:askForScreen()
	bench.frame()
	eq("the title is the name too", bench.window.titleText, "CeroSec OS \194\183 office")
	check("and the echo survived the reopen", bench.painted("root@office:~# date"))

	-- Off and on: the name is a file on the disk, so it comes back with it.
	bench.enter("reboot")
	_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
	bench.frame()
	bench.enter("root")
	bench.enter("")
	bench.enter("date")
	bench.frame()
	eq("the prompt after a reboot", bench.window.prompt, "root@office:~# ")
	check("and the echo after it", bench.painted("root@office:~# date"))
	eq("the file is what says so",
		CeroSecOS.hostname(bench.object:osState()), "office")
end

--
-- Accounts, from the chair
--
-- `sudo adduser` and `su` are the two of this rung that are not one command and
-- one answer: sudo asks for a password before it runs anything, su asks for
-- another and then changes who the machine is logged in as. What is asserted is
-- the PROMPT on the glass -- the machine's own line under the cursor -- because
-- a console field can say bob while the screen still shows admin's dollar.
--

do
	local bench = newBench()
	local host = CeroSec.hostnameFor(10, 10)
	bench.login("admin")
	eq("admin is at his own prompt", bench.window.prompt, "admin@" .. host .. ":~$ ")

	bench.enter("sudo adduser bob")
	bench.frame()
	eq("sudo asks first", bench.window.prompt, "[sudo] password for admin: ")
	eq("and hides the answer", bench.window.mask, true)
	bench.enter("")
	bench.frame()
	check("the account was made", bench.painted("adduser: bob: created"))
	check("and the open password is said out loud",
		bench.painted("adduser: set a password with passwd bob"))
	check("the machine really has him",
		CeroSecOS.getUser(bench.object:osState(), "bob") ~= nil)

	bench.enter("su bob")
	bench.frame()
	eq("su asks for a password", bench.window.prompt, "Password: ")
	eq("masked", bench.window.mask, true)
	bench.enter("")
	bench.frame()
	eq("and the glass is bob's", bench.window.prompt, "bob@" .. host .. ":~$ ")
	eq("still a shell", bench.window.mode, "shell")
	bench.enter("whoami")
	bench.enter("pwd")
	bench.frame()
	check("the machine agrees", bench.painted("bob"))
	check("and stands in his home", bench.painted("/home/bob"))
	eq("the console is his", bench.object.console.user, "bob")
	eq("the stack is on the machine, not in the window",
		type(bench.object.console.stack), "table")
	eq("with admin one deep under him", #bench.object.console.stack, 1)
	eq("who is admin", bench.object.console.stack[1].user, "admin")

	-- The first exit pops back, and logs nobody out.
	bench.enter("exit")
	bench.frame()
	eq("back to admin", bench.window.prompt, "admin@" .. host .. ":~$ ")
	eq("still logged in", bench.window.mode, "shell")
	eq("the console says so too", bench.object.console.user, "admin")
	eq("and the stack is gone rather than left empty", bench.object.console.stack, nil)
	check("the screen kept what was on it", bench.painted("adduser: bob: created"))

	-- The second one is a logout.
	bench.enter("exit")
	bench.frame()
	eq("the login prompt is back", bench.window.prompt, "login: ")
	eq("at a prompt, not a shell", bench.window.mode, "prompt")
	eq("nobody is logged in", bench.object.console.user, nil)
	check("and the screen was wiped", not bench.painted("adduser: bob: created"))
end

--
-- `sudo su` is the other way to become somebody, and it lands on the same
-- glass: what is asserted here is the PROMPT again, because the whole of what
-- sudo used to do to a console was nothing at all.
--

do
	local bench = newBench()
	local host = CeroSec.hostnameFor(10, 10)
	bench.login("admin")
	CeroSecOS.setData(bench.object:osState(), CeroSecOS.rootSession(),
		CeroSecOS.SUDOERS_PATH, "admin NOPASSWD")
	bench.enter("sudo adduser bob")
	bench.frame()
	check("bob is on the machine", bench.painted("adduser: bob: created"))

	bench.enter("sudo su bob")
	bench.frame()
	eq("the glass is bob's", bench.window.prompt, "bob@" .. host .. ":~$ ")
	eq("the console says so too", bench.object.console.user, "bob")
	eq("with admin one deep under him", #bench.object.console.stack, 1)

	bench.enter("exit")
	bench.frame()
	eq("and exit gives the glass back", bench.window.prompt, "admin@" .. host .. ":~$ ")
	eq("still logged in", bench.window.mode, "shell")

	-- `sudo su` with no name is root's, and root wears the hash.
	bench.enter("sudo su")
	bench.frame()
	eq("the glass is root's", bench.window.prompt, "root@" .. host .. ":~# ")
	eq("standing in root's own home", bench.object.console.cwd, "/root")

	-- And `exit` under sudo is not a command, so it logs nobody out: the shell
	-- word has no file in /bin for sudo to look up.
	bench.enter("sudo exit")
	bench.frame()
	check("sudo says what it could not find",
		bench.painted("sudo: exit: command not found"))
	eq("and the glass is still root's", bench.window.prompt, "root@" .. host .. ":~# ")

	bench.enter("exit")
	bench.frame()
	eq("the console's own exit pops", bench.window.prompt, "admin@" .. host .. ":~$ ")
end

--
-- /dev, through the whole machine
--
-- os_test proves the engine against a fake env.devices. This proves the other
-- half: a fake WORLD -- squares, rooms, a building, and the four kinds of thing
-- that become a device -- walked by the real SCeroSecDevices, numbered into the
-- real state, mounted by the real engine, and put on the real glass by the real
-- window. What is asserted is what a player would read.
--
-- The world is the mockup's, laid out so that the numbering lands on it: two
-- rooms plus a kitchen, two map doors (one exterior), one window, two light
-- switches and one player-built door with a padlock.
--

-- The offset column, on its own. Pure arithmetic on three numbers, so it is
-- proved without a world at all -- every direction, both floors, and the two
-- shapes that are easy to get backwards: x grows EAST and y grows SOUTH, so a
-- smaller y is north.
do
	local o = CeroSecDevices.offset
	eq("the machine's own square", o(0, 0, 0), "0 0")
	eq("east", o(3, 0, 0), "3E 0")
	eq("west", o(-3, 0, 0), "3W 0")
	eq("north is a SMALLER y", o(0, -2, 0), "0 2N")
	eq("south is a bigger one", o(0, 2, 0), "0 2S")
	eq("both halves", o(3, -2, 0), "3E 2N")
	eq("and the other two corners", o(-3, 2, 0), "3W 2S")
	eq("one floor up", o(3, -2, 1), "3E 2N +1")
	eq("one floor down", o(3, -2, -1), "3E 2N -1")
	eq("two floors up, on the same square", o(0, 0, 2), "0 0 +2")
	eq("and two digits do not change the shape", o(-12, 30, 0), "12W 30S")
	-- The widest a real one gets, and the column dev keeps for it.
	eq("the widest offset there is", #o(-10, -10, -1), 10)
end

local FakeWorld = {}

function FakeWorld.new()
	local world = { squares = {}, rooms = {}, roomOrder = {} }

	world.getGridSquare = function(_, x, y, z)
		return world.squares[x .. "," .. y .. "," .. z]
	end

	-- A room, and the squares in it. The building is every room there is: a
	-- square that belongs to a room belongs to the building.
	world.room = function(name, coords)
		local room = { name = name, squares = {} }
		world.rooms[name] = room
		world.roomOrder[#world.roomOrder + 1] = room
		room.getName = function() return name end
		room.getSquares = function() return javaList(room.squares) end
		for i = 1, #coords do
			local sq = world.square(coords[i][1], coords[i][2], coords[i][3], room)
			room.squares[#room.squares + 1] = sq
		end
		return room
	end

	world.building = {
		getDef = function()
			local defs = {}
			for i = 1, #world.roomOrder do
				local room = world.roomOrder[i]
				defs[i] = { getIsoRoom = function() return world.loaded ~= false and room or nil end }
			end
			return { getRooms = function() return javaList(defs) end }
		end,
	}

	-- One square. A square with a room is inside the building; one without is
	-- the outdoors, which is what makes a door "exterior".
	world.square = function(x, y, z, room)
		local key = x .. "," .. y .. "," .. z
		local sq = world.squares[key]
		if sq ~= nil then return sq end
		-- Three lists and not one, because the game keeps three: the fixtures
		-- (getObjects), the items lying on the floor (getWorldObjects) and the
		-- bodies standing on it (getMovingObjects). A fake that put a dropped
		-- sensor on getObjects would let a discovery that walked the wrong list
		-- pass.
		sq = { objects = {}, items = {}, bodies = {} }
		sq.getX = function() return x end
		sq.getY = function() return y end
		sq.getZ = function() return z end
		sq.getRoom = function() return room end
		sq.getBuilding = function() if room ~= nil then return world.building end return nil end
		sq.getObjects = function() return javaList(sq.objects) end
		sq.getWorldObjects = function() return javaList(sq.items) end
		sq.getMovingObjects = function() return javaList(sq.bodies) end
		world.squares[key] = sq
		return sq
	end

	-- Drop an item on a square, the way a survivor does.
	world.drop = function(square, object)
		object.square = square
		object.getSquare = function() return object.square end
		square.items[#square.items + 1] = object
		return object
	end

	-- Pick one up again: gone from the world, and the number it had stays spent.
	world.pickUp = function(object)
		local list = object.square.items
		for i = 1, #list do
			if list[i] == object then table.remove(list, i); break end
		end
		object.square = nil
		object.getSquare = function() return nil end
	end

	-- Put a body on a square, at a position inside it. The position is a FLOAT and
	-- the square is only where it is filed: a sensor that read the square's own
	-- integer x and y instead of the body's own could not tell a survivor who
	-- crossed a tile from one who stood still in the middle of it, and every one
	-- of the assertions below about standing still would pass on nothing.
	--
	-- square nil takes the body out of the world altogether.
	world.stand = function(object, square, fx, fy)
		if object.square ~= nil then
			local list = object.square.bodies
			for i = 1, #list do
				if list[i] == object then table.remove(list, i); break end
			end
		end
		object.square = square
		if square ~= nil then square.bodies[#square.bodies + 1] = object end
		if fx ~= nil then object.fx, object.fy = fx, fy end
		return object
	end

	world.put = function(square, object)
		object.square = square
		object.getSquare = function() return object.square end
		square.objects[#square.objects + 1] = object
		return object
	end

	-- Take a device off its square, the way a survivor with a sledgehammer does.
	world.remove = function(object)
		local list = object.square.objects
		for i = 1, #list do
			if list[i] == object then table.remove(list, i); break end
		end
		object.square = nil
		object.getSquare = function() return nil end
	end

	return world
end

-- Everything a hardware module can be screwed to carries modData, because the
-- game's own do: IsoObject keeps a KahluaTable and saves it with the chunk under
-- its own flag bit, and IsoThumpable keeps a second one of its own and saves
-- that (docs/notes/modules-proofs.md, 1). transmitModData is COUNTED and not
-- merely answered, for the same reason a sync is: "the other players were told"
-- is the half of a server-side write that no field on the object can show.
local function fittable(o)
	o.modData = {}
	o.transmits = 0
	o.hasModData = function() return true end
	o.getModData = function() return o.modData end
	o.transmitModData = function() o.transmits = o.transmits + 1 end
	return o
end

-- Screw one on, the way the install command does. A bench that wrote the table
-- itself would be a bench agreeing with itself about the shape of it.
local function fit(object, id)
	local data = object:getModData()
	if data[CeroSecModules.DATA_KEY] == nil then data[CeroSecModules.DATA_KEY] = {} end
	data[CeroSecModules.DATA_KEY][id] = true
	return object
end

local function unfit(object, id)
	local data = object:getModData()
	local fitted = data[CeroSecModules.DATA_KEY]
	if fitted ~= nil then fitted[id] = nil end
	return object
end

-- The four kinds. Each one answers the calls SCeroSecDevices makes on it and
-- counts the syncs, because "the change reached every watcher" is the half of a
-- server-side write that a state field cannot show.
local function fakeLight(on, powered)
	local o = fittable({ __class = "IsoLightSwitch", activated = on, powered = powered, syncs = 0 })
	o.isActivated = function() return o.activated end
	o.canSwitchLight = function() return o.powered end
	o.setActive = function(_, want)
		-- The real one refuses silently when it cannot be thrown, and syncs
		-- itself from the server when it can.
		if not o.powered then return o.activated end
		o.activated = want
		o.syncs = o.syncs + 1
		return o.activated
	end
	return o
end

-- Everything the client needs to point at one: the sprite name the server sends
-- so the object can be found again on the far side, and the four highlight
-- calls, which take the LOCAL player number first and are recorded so a test can
-- say whose eyes it was drawn for.
local spriteN = 0
local function highlightable(o)
	spriteN = spriteN + 1
	o.sprite = "cerosec_fake_" .. spriteN
	o.highlights = {}
	o.getSpriteName = function() return o.sprite end
	o.setHighlighted = function(_, player, on)
		o.highlights[#o.highlights + 1] = tostring(player) .. "=" .. tostring(on)
	end
	o.setHighlightColor = function() end
	o.setOutlineHighlight = function(_, _, on) o.outline = on end
	o.setOutlineHighlightCol = function() end
	return o
end

-- The door half both classes share: what opens, what refuses, and the toggle
-- that moves it. ToggleDoorSilent is written the way the bytecode is -- it does
-- NOTHING at all on a barricaded door and it syncs nothing ever -- so a machine
-- that forgot either fact is a machine this bench fails.
local function openable(o)
	o.open = false
	o.barricaded = false
	o.obstructed = false
	o.silentToggles = 0
	o.IsOpen = function() return o.open end
	o.isBarricaded = function() return o.barricaded end
	o.isObstructed = function() return o.obstructed end
	o.ToggleDoorSilent = function()
		o.silentToggles = o.silentToggles + 1
		if o.barricaded then return end
		o.open = not o.open
	end
	return o
end

local function fakeDoor(locked, north, opposite, exterior)
	local o = fittable({ __class = "IsoDoor", lockedByKey = locked, north = north,
		opposite = opposite, exterior = exterior == true, syncs = 0 })
	highlightable(o)
	openable(o)
	o.getNorth = function() return o.north end
	o.getOppositeSquare = function() return o.opposite end
	-- The game's own flag-and-building test. The bench sets it by hand and the
	-- room test beside it is what SCeroSecDevices works out for itself, so both
	-- halves of doorLocks are reachable here.
	o.isExterior = function() return o.exterior end
	o.isLockedByKey = function() return o.lockedByKey end
	-- The real setter skips its own sync on a server, which is why the sync
	-- below is a separate call and why this fake does not make one.
	o.setLockedByKey = function(_, want) o.lockedByKey = want end
	o.syncIsoObject = function() o.syncs = o.syncs + 1 end
	return o
end

local function fakeWindow(locked, north)
	local o = fittable({ __class = "IsoWindow", locked = locked, north = north,
		smashed = false, barricaded = false, open = false, syncs = 0 })
	highlightable(o)
	o.getNorth = function() return o.north end
	-- The sash. NOT openable() above, deliberately: that one also writes a
	-- ToggleDoorSilent, and there is no call in the game that moves a window
	-- without a survivor standing at it -- a fake that answered one would be a
	-- fake claiming a call we could make.
	o.IsOpen = function() return o.open end
	o.isLocked = function() return o.locked end
	o.isSmashed = function() return o.smashed end
	o.isBarricaded = function() return o.barricaded end
	o.setIsLocked = function(_, want) o.locked = want end
	o.syncIsoObject = function() o.syncs = o.syncs + 1 end
	return o
end

-- No getOppositeSquare on this one, deliberately: the exterior rule is a map
-- door's business and a built door never has it asked. A fake that answers a
-- call nothing makes is a fake that claims a call we make.
local function fakeThumpable(padlock, north)
	local o = fittable({ __class = "IsoThumpable", lockedByPadlock = padlock, canPadlock = true,
		lockedByKey = false, keyId = 0, north = north, syncs = 0 })
	highlightable(o)
	openable(o)
	o.isDoor = function() return true end
	o.getNorth = function() return o.north end
	o.syncIsoObject = function() o.syncs = o.syncs + 1 end
	o.isLockedByPadlock = function() return o.lockedByPadlock end
	o.canBeLockByPadlock = function() return o.canPadlock end
	o.isLockedByKey = function() return o.lockedByKey end
	o.getKeyId = function() return o.keyId end
	-- The real one syncs itself, padlock or not.
	o.setLockedByPadlock = function(_, want)
		if o.lockedByPadlock ~= want then o.syncs = o.syncs + 1 end
		o.lockedByPadlock = want
	end
	o.setLockedByKey = function(_, want) o.lockedByKey = want end
	o.syncIsoThumpable = function() o.syncs = o.syncs + 1 end
	return o
end

-- A dropped item: an IsoWorldInventoryObject holding an InventoryItem. That is the
-- path the discovery walks and the path the game has --
-- IsoGridSquare.getWorldObjects -> IsoWorldInventoryObject.getItem ->
-- InventoryItem.getFullType, all javap'd.
--
-- getSpriteName is deliberately NOT written on it: a world item has no sprite to
-- be found again by, and a server that sent one for a sensor would be calling a
-- method that answers nothing on the real thing.
local function fakeDropped(item)
	local o = { __class = "IsoWorldInventoryObject", item = item, highlights = {} }
	o.getItem = function() return o.item end
	-- The four vanilla makes on hover, the same four a door and a window get, and
	-- recorded the same way so a test can say whose eyes it was drawn for. Written
	-- out here rather than through highlightable() because that one also writes a
	-- getSpriteName, and this object must not have one.
	o.setHighlighted = function(_, player, on)
		o.highlights[#o.highlights + 1] = tostring(player) .. "=" .. tostring(on)
	end
	o.setHighlightColor = function() end
	o.setOutlineHighlight = function(_, _, on) o.outline = on end
	o.setOutlineHighlightCol = function() end
	return o
end

-- The one item that is a device: the bare module, which carries no SensorRange of
-- its own -- it is a component, and CeroSec.SENSOR_RANGE is what the mod says its
-- reach is (media/scripts/generated/items/normal.txt:4539).
local function fakeSensor()
	local item = { __class = "InventoryItem" }
	item.getFullType = function() return "Base.MotionSensor" end
	return fakeDropped(item)
end

-- A TRAP HEAD, which must never be a device: a bomb with a motion sensor taped to
-- it. A HandWeapon answering a positive SensorRange, which is what the fifteen
-- *SensorV1/V2/V3 items are (weapon.txt: PipeBombSensorV1 :838 = 3, V2 :869 = 4,
-- V3 :900 = 6) -- so a bench that let one through would be a machine calling a
-- pipe bomb a sensor.
local function fakeTrapHead(range, fullType)
	local item = { __class = "HandWeapon", range = range, fullType = fullType }
	item.getSensorRange = function() return item.range end
	item.getFullType = function() return item.fullType end
	return fakeDropped(item)
end

-- An ordinary dropped item, so that "any world item is a sensor" cannot pass.
local function fakeJunk()
	local item = { __class = "InventoryItem" }
	item.getFullType = function() return "Base.Hammer" end
	return fakeDropped(item)
end

-- A body in the field: a survivor, a zombie, or a car. All three are
-- IsoMovingObjects in the game (BaseVehicle extends IsoMovingObject, javap), and
-- only a character can be invisible -- which is exactly the shape of the game's
-- own filter, IsoTrap.updateVictimsInSensorRange offset 103.
local function fakeBody(class, invisible)
	local o = { __class = class, fx = 0, fy = 0, invisible = invisible == true }
	o.getX = function() return o.fx end
	o.getY = function() return o.fy end
	if class ~= "BaseVehicle" then
		o.isInvisible = function() return o.invisible end
	end
	return o
end

-- The mockup's world, around the computer at 10,10,0.
local function mockupWorld()
	local world = FakeWorld.new()
	local office = world.room("office", { {10,10,0}, {11,10,0}, {12,10,0} })
	local kitchen = world.room("kitchen", { {11,11,0} })
	local hallway = world.room("hallway", { {12,11,0}, {13,11,0} })

	-- Outside: no room, so a door onto it is the way in.
	local outside = world.square(11, 9, 0, nil)

	local kit = {}
	-- door0 AND lock0: the front door, facing west, locked, with the outdoors
	-- on one side of it. One object, two devices -- the thing that opens and the
	-- key -- and that is the whole point of this rung.
	kit.front = world.put(world.squares["11,10,0"], fakeDoor(true, false, outside))
	-- win0: a window in the office, facing north and locked.
	kit.win0 = world.put(world.squares["12,10,0"], fakeWindow(true, true))
	-- light0: the office switch, on. light1: the hallway switch, off.
	kit.light0 = world.put(world.squares["11,10,0"], fakeLight(true, true))
	kit.light1 = world.put(world.squares["13,11,0"], fakeLight(false, true))
	-- door1 and NOTHING else: between the kitchen and the hallway, so a room on
	-- both sides and a lock that could not stop anybody. It opens; it has no key.
	kit.inner = world.put(world.squares["11,11,0"], fakeDoor(false, true, world.squares["12,11,0"]))
	-- door2 and lock1: the player-built door, padlocked. The padlock locks what
	-- is behind it and not the door, so the door still reads closed.
	kit.built = world.put(world.squares["12,11,0"], fakeThumpable(true, true))

	kit.world = world
	kit.office, kit.kitchen, kit.hallway = office, kitchen, hallway
	return kit
end

do
	local kit = mockupWorld()
	_G.__world = kit.world

	local bench = newBench()
	bench.login("admin")
	bench.enter("su root")
	bench.enter("")
	bench.frame()
	eq("root is at the glass", bench.object.console.user, "root")

	-- The listing, exactly as the mockup approved it -- discovered from the
	-- world, numbered into the machine's own state, and painted on the glass.
	bench.enter("ls -l /dev")
	bench.frame()
	local want = {
		"crw-rw----  root  sudo  door0   exterior       W  locked",
		"crw-rw----  root  sudo  door1   kitchen-hall~  N  closed",
		"crw-rw----  root  sudo  door2   built          N  closed",
		"crw-rw----  root  sudo  light0  office            on",
		"crw-rw----  root  sudo  light1  hallway           off",
		"crw-rw----  root  sudo  lock0   exterior       W  locked",
		"crw-rw----  root  sudo  lock1   built          N  padlock",
		"crw-rw----  root  sudo  win0    office         N  locked",
	}
	-- The interior door is a door and NOT a lock: a key on it stops nobody, so
	-- there is no lock device for it to lie through.
	check("no lock device for the interior door", not bench.painted("kitchen-hall~  N  unlocked"))
	for i = 1, #want do
		check("the glass shows: " .. want[i], bench.painted(want[i]))
	end

	-- Reading one.
	bench.enter("cat /dev/light1")
	bench.frame()
	check("cat says off", bench.painted("off"))

	-- Throwing a switch reaches the world, and the world says so back.
	bench.enter("echo on > /dev/light1")
	bench.frame()
	eq("the switch moved", kit.light1.activated, true)
	eq("and it was broadcast", kit.light1.syncs, 1)
	bench.enter("cat /dev/light1")
	bench.frame()
	check("and the machine reads it back", bench.painted("on"))

	-- Unlocking a keyed door: the setter, and the sync that vanilla makes by
	-- hand because the setter skips its own on a server.
	bench.enter("echo unlock > /dev/lock0")
	bench.frame()
	eq("the door is unlocked", kit.front.lockedByKey, false)
	eq("and it was broadcast", kit.front.syncs, 1)

	-- A window, and a padlock.
	bench.enter("echo unlock > /dev/win0")
	bench.frame()
	eq("the window is unlocked", kit.win0.locked, false)
	eq("and it was broadcast", kit.win0.syncs, 1)
	bench.enter("echo unlock > /dev/lock1")
	bench.frame()
	eq("the padlock is off", kit.built.lockedByPadlock, false)
	eq("and it was broadcast", kit.built.syncs, 1)
	bench.enter("cat /dev/lock1")
	bench.frame()
	check("and the machine reads unlocked", bench.painted("unlocked"))

	-- And the everyday face of all of it, end to end through the real
	-- discovery: dev's own table, and one order carried out on the world.
	bench.enter("dev")
	bench.frame()
	-- The offsets are the real ones: the computer stands at 10,10,0 and every
	-- one of these was walked out of the fake world by SCeroSecDevices.
	local table60 = {
		"door0   exterior              1E 0        W  closed",
		"door1   kitchen-hallway       1E 1S       N  closed",
		"door2   built                 2E 1S       N  closed",
		"light0  office                1E 0           on",
		"light1  hallway               3E 1S          on",
		"lock0   exterior              1E 0        W  unlocked",
		"lock1   built                 2E 1S       N  unlocked",
		"win0    office                2E 0        N  unlocked",
	}
	for i = 1, #table60 do
		check("dev's table shows: " .. table60[i], bench.painted(table60[i]))
	end
	bench.enter("dev light0 off")
	bench.frame()
	eq("the switch moved", kit.light0.activated, false)
	eq("and it was broadcast", kit.light0.syncs, 1)
	check("and dev said what it read back", bench.painted("light0: off"))
	bench.enter("dev light0 toggle")
	bench.frame()
	eq("the toggle put it back", kit.light0.activated, true)
	check("and said so", bench.painted("light0: on"))

	--
	-- Doors: the thing that opens, beside the key that holds it
	--
	-- door0 and lock0 are ONE object. The front door was unlocked a few lines
	-- up, so it opens -- silently, through ToggleDoorSilent, with no character
	-- anywhere in the call -- and the open flag is broadcast by hand because
	-- Silent syncs nothing.
	eq("the front door starts shut", kit.front.open, false)
	bench.enter("dev door0 open")
	bench.frame()
	check("and the machine says what it read back", bench.painted("door0: open"))
	eq("the door is open in the world", kit.front.open, true)
	eq("through the silent toggle, once", kit.front.silentToggles, 1)
	eq("and it was broadcast", kit.front.syncs, 2)

	-- Asked for what it already is: nothing is toggled and nothing is sent. A
	-- toggle called twice is a shut door, which is not what was asked for.
	bench.enter("dev door0 open")
	bench.frame()
	check("still open", bench.painted("door0: open"))
	eq("no second toggle", kit.front.silentToggles, 1)
	eq("and no second broadcast", kit.front.syncs, 2)

	bench.enter("dev door0 toggle")
	bench.frame()
	check("toggle shut it", bench.painted("door0: closed"))
	eq("shut in the world", kit.front.open, false)
	eq("and that one moved it", kit.front.silentToggles, 2)

	-- The key is the OTHER device, and a computer is not a key. Lock the front
	-- door through lock0: door0 then READS locked and refuses to open, and the
	-- way past it is unlock, not a harder shove.
	bench.enter("dev lock0 lock")
	bench.frame()
	check("the lock says so", bench.painted("lock0: locked"))
	bench.enter("dev door0")
	bench.frame()
	check("and the door reads locked", bench.painted("door0: locked"))
	bench.enter("dev door0 open")
	bench.frame()
	check("and refuses to open", bench.painted("door0: locked"))
	eq("nothing was toggled", kit.front.silentToggles, 2)
	bench.enter("dev door0 toggle")
	bench.frame()
	check("toggle is refused in the same words", bench.painted("door0: locked"))
	-- Closing a locked door is not refused: a key is what you need to come IN.
	bench.enter("dev door0 close")
	bench.frame()
	check("closing a shut locked door is no refusal", bench.painted("door0: locked"))
	bench.enter("dev lock0 unlock")
	bench.enter("dev door0 open")
	bench.frame()
	check("unlock first, then open", bench.painted("door0: open"))
	bench.enter("dev door0 close")
	bench.frame()

	-- The interior door: a room on both sides, so the lock could stop nobody
	-- and there is no lock device for it at all. A key turned on it by hand
	-- changes neither what it reads nor what it does.
	bench.enter("dev lock1")
	bench.frame()
	check("the built door is what lock1 is", bench.painted("lock1: unlocked"))
	kit.inner.lockedByKey = true
	bench.enter("dev door1")
	bench.frame()
	check("a key on an interior door changes nothing", bench.painted("door1: closed"))
	bench.enter("dev door1 open")
	bench.frame()
	check("and it opens anyway", bench.painted("door1: open"))
	eq("really open", kit.inner.open, true)
	eq("and broadcast", kit.inner.syncs, 1)
	bench.enter("dev door1 close")
	bench.frame()
	kit.inner.lockedByKey = false

	-- Barricaded: ToggleDoorSilent returns without doing anything at all on a
	-- barricaded door, so the refusal has to be the machine's and has to come
	-- before the call, or the order would be swallowed in silence.
	local toggles = kit.inner.silentToggles
	kit.inner.barricaded = true
	bench.enter("dev door1 open")
	bench.frame()
	check("barricaded", bench.painted("door1: barricaded"))
	eq("and nothing was even attempted", kit.inner.silentToggles, toggles)
	bench.enter("dev door1 toggle")
	bench.frame()
	check("toggle says the same", bench.painted("door1: barricaded"))
	kit.inner.barricaded = false

	-- Blocked: the game's own obstruction test and nothing else -- a solid tile,
	-- a tree, a vehicle across it. A survivor standing in the doorway is NOT
	-- one: vanilla lets a door swing through him, so the machine does too, and a
	-- refusal the game does not make is one we would have invented.
	kit.inner.obstructed = true
	bench.enter("dev door1 open")
	bench.frame()
	check("blocked by the doorway itself", bench.painted("door1: blocked"))
	eq("and nothing moved", kit.inner.silentToggles, toggles)
	bench.enter("dev door1 toggle")
	bench.frame()
	check("toggle says the same", bench.painted("door1: blocked"))
	kit.inner.obstructed = false
	bench.enter("dev door1 open")
	bench.frame()
	check("and once the doorway is clear it opens", bench.painted("door1: open"))
	bench.enter("dev door1 close")
	bench.frame()

	-- The player-built door: the padlock locks what is behind it and not the
	-- door, so a padlocked base door still opens, exactly as it does for a
	-- survivor clicking it.
	bench.enter("dev lock1 lock")
	bench.frame()
	check("the padlock is back on", bench.painted("lock1: padlock"))
	bench.enter("dev door2")
	bench.frame()
	check("and the door still reads closed", bench.painted("door2: closed"))
	bench.enter("dev door2 open")
	bench.frame()
	check("and opens", bench.painted("door2: open"))
	eq("really open", kit.built.open, true)
	bench.enter("dev door2 close")
	bench.frame()

	-- A key on a built door is what the lock there means, and it stops the
	-- machine the way an exterior map door's does.
	kit.built.lockedByKey = true
	bench.enter("dev door2 open")
	bench.frame()
	check("a keyed built door is locked", bench.painted("door2: locked"))
	kit.built.lockedByKey = false

	-- Only words a door knows, and only the kinds the machine has.
	bench.enter("dev door0 unlock")
	bench.frame()
	check("a lock's word is not a door's", bench.painted("door0: invalid value"))
	bench.enter("dev door")
	bench.frame()
	check("door is a kind", bench.painted("door0   exterior"))
	bench.enter("dev door9")
	bench.frame()
	check("and a number never handed out is the command's refusal",
		bench.painted("dev: door9: no such device"))

	-- Put the padlock back where the rest of this bench expects it.
	bench.enter("dev lock1 unlock")
	bench.frame()

	-- The sash, which is what a magnetic contact is FOR and which a window device
	-- could always see and never said. It is read with the option OFF as well as
	-- on: what a window IS does not depend on what is screwed to it.
	kit.win0.open = true
	bench.enter("dev win0")
	bench.frame()
	check("an open window reads open", bench.painted("win0: open"))
	bench.enter("ls -l /dev/win0")
	bench.frame()
	check("and the listing says so too",
		bench.painted("crw-rw----  root  sudo  win0    office         N  open"))
	-- Open beats the latch, the way a door's open beats its lock: the word is
	-- about the hole in the wall and not about the catch on it.
	eq("the latch is untouched and unasked", kit.win0.locked, false)
	kit.win0.locked = true
	bench.enter("clear")
	bench.enter("dev win0")
	bench.frame()
	check("a locked window that is open still reads open",
		bench.painted("win0: open"))
	check("and says nothing about the catch", not bench.painted("win0: locked"))
	-- And nothing undoes it: a window's two words are lock and unlock, and
	-- guessing a direction for a sash no machine can move would be an invention.
	bench.enter("dev win0 toggle")
	bench.frame()
	check("there is no opposite to open", bench.painted("win0: cannot toggle"))
	kit.win0.open = false
	bench.enter("dev win0")
	bench.frame()
	check("shut again, the latch is the word", bench.painted("win0: locked"))
	kit.win0.locked = false

	-- Somebody smashes the window. The next listing says so, and the machine
	-- refuses to work a lock that is not there any more.
	kit.win0.smashed = true
	kit.win0.open = true
	-- The glass wiped first, because a negative assertion on a screen that keeps
	-- a hundred lines of scrollback is an assertion about everything typed
	-- before it (CeroSec.CONSOLE_MAX).
	bench.enter("clear")
	bench.enter("ls -l /dev/win0")
	bench.frame()
	check("the smashed window shows",
		bench.painted("crw-rw----  root  sudo  win0    office         N  smashed"))
	-- Broken beats the sash: there is no window left to be open, so the word a
	-- survivor needs is the one about the glass.
	check("and not what the sash is doing", not bench.painted("N  open"))
	kit.win0.open = false
	bench.enter("echo lock > /dev/win0")
	bench.frame()
	check("and refuses to be locked", bench.painted("win0: smashed"))

	-- A switch with no power: the world refuses, and nothing moves.
	kit.light0.powered = false
	bench.enter("echo off > /dev/light0")
	bench.frame()
	check("no power", bench.painted("light0: no power"))
	eq("and the switch did not move", kit.light0.activated, true)
	kit.light0.powered = true

	-- A player door with neither padlock nor key.
	kit.built.canPadlock = false
	kit.built.keyId = -1
	bench.enter("echo lock > /dev/lock1")
	bench.frame()
	check("no padlock", bench.painted("lock1: no padlock"))

	--
	-- dev find: which of the thirty-five is it?
	--
	-- A light answers by blinking, which the server does on its own clock and
	-- everybody in the room sees. The switch is put back exactly as it was
	-- found: a survivor who asked which light this was did not ask for the
	-- room's lighting to change.
	kit.built.canPadlock = true
	kit.built.keyId = 0
	eq("the switch is on to begin with", kit.light0.activated, true)
	eq("and nothing is blinking", #CeroSecDevices.blinks, 0)
	bench.enter("dev find light0")
	bench.frame()
	check("the machine says what it did", bench.painted("light0: blinking"))
	eq("one blink is booked", #CeroSecDevices.blinks, 1)

	-- The first tick after the order flips it: the answer is wanted now, not in
	-- half a second.
	_G.__now = _G.__now + 16
	CeroSecDevices.tick()
	eq("off", kit.light0.activated, false)
	_G.__now = _G.__now + 100
	CeroSecDevices.tick()
	eq("and a tick inside the half second changes nothing", kit.light0.activated, false)
	_G.__now = _G.__now + CeroSecDevices.BLINK_MS
	CeroSecDevices.tick()
	eq("on", kit.light0.activated, true)
	_G.__now = _G.__now + CeroSecDevices.BLINK_MS
	CeroSecDevices.tick()
	eq("off", kit.light0.activated, false)

	-- And when the six seconds are up it stops, on the state it started from.
	_G.__now = _G.__now + CeroSecOS.DEV_FIND_SECONDS * 1000
	CeroSecDevices.tick()
	eq("the blink is over", #CeroSecDevices.blinks, 0)
	eq("and the switch is where it was found", kit.light0.activated, true)

	-- A write during a blink ends it, and is NOT undone by the restore: the
	-- word just typed is the newer of the two intentions.
	bench.enter("dev find light0")
	bench.frame()
	eq("blinking again", #CeroSecDevices.blinks, 1)
	bench.enter("dev light0 off")
	bench.frame()
	eq("the write dropped the blink", #CeroSecDevices.blinks, 0)
	eq("and the light is off", kit.light0.activated, false)
	_G.__now = _G.__now + CeroSecOS.DEV_FIND_SECONDS * 1000
	CeroSecDevices.tick()
	eq("and stays off", kit.light0.activated, false)
	bench.enter("dev light0 on")
	bench.frame()

	-- A switch with no power cannot be blinked either, and says the same thing
	-- about it that a write does.
	kit.light0.powered = false
	bench.enter("dev find light0")
	bench.frame()
	check("no power", bench.painted("light0: no power"))
	eq("and nothing was booked", #CeroSecDevices.blinks, 0)
	kit.light0.powered = true

	-- A door has nothing to blink with. The server tells the ONE window that
	-- asked where to look, and that window's own client draws the outline --
	-- for its own player number and nobody else's.
	eq("nothing is lit yet", kit.inner.outline, nil)
	bench.enter("dev find door1")
	bench.frame()
	check("the machine says what it did", bench.painted("door1: highlighted"))
	eq("the door is outlined", kit.inner.outline, true)
	eq("for this player, once", kit.inner.highlights[1], "0=true")
	eq("and the window remembers it has one lit", bench.window.highlight ~= nil, true)
	-- The object was found again on the far side by its square, its class and
	-- its sprite -- and nothing else on that square was.
	eq("and the padlocked door beside it was not", kit.built.outline, nil)

	-- It goes out on its own, in the window's own update, six seconds later.
	_G.__now = _G.__now + CeroSecOS.DEV_FIND_SECONDS * 1000
	bench.frame()
	eq("the outline is gone", kit.inner.outline, false)
	eq("and the window is holding nothing", bench.window.highlight, nil)
	eq("it was put out for the same player", kit.inner.highlights[2], "0=false")

	-- A second find drops the first outline rather than leaving it lit.
	bench.enter("dev find door1")
	bench.frame()
	bench.enter("dev find win0")
	bench.frame()
	eq("the window is lit", kit.win0.outline, true)
	eq("and the door was put out at once", kit.inner.outline, false)

	-- Closing the window takes the outline with it.
	_G.__now = _G.__now + 100
	bench.window:close()
	eq("nothing is left lit", kit.win0.outline, false)
	bench.window.closing = nil

	--
	-- The numbers hold across a reload, with one device gone.
	--
	local before = {}
	for key, record in pairs(bench.object.os.devmap) do before[key] = record.id end
	check("the book has an entry per device", (function()
		local n = 0
		for _ in pairs(before) do n = n + 1 end
		-- Eight, not six: the front door and the built one are each two.
		return n == 8
	end)())

	-- The front door is torn out -- door0 AND lock0 with it, one object being
	-- both -- and the machine is reloaded from its saved state.
	kit.world.remove(kit.front)
	local saved = bench.object.os
	local reloaded = newBench()
	reloaded.object.os = saved
	reloaded.login("admin")
	reloaded.enter("su root")
	reloaded.enter("")
	reloaded.enter("ls -l /dev")
	reloaded.frame()

	check("light0 kept its number", reloaded.painted("light0  office"))
	check("light1 kept its number", reloaded.painted("light1  hallway"))
	check("door1 kept its number", reloaded.painted("door1   kitchen-hall~"))
	check("door2 kept its number", reloaded.painted("door2   built"))
	check("lock1 kept its number", reloaded.painted("lock1   built"))
	check("win0 kept its number", reloaded.painted("win0    office"))
	-- The one that is gone leaves TWO gaps: nothing moved up into either.
	check("the gone door is not listed", not reloaded.painted("door0 "))
	check("nor its lock", not reloaded.painted("lock0 "))
	reloaded.enter("cat /dev/door0")
	reloaded.frame()
	check("and it says which kind of not-there it is",
		reloaded.painted("door0: no such device"))
	reloaded.enter("cat /dev/lock0")
	reloaded.frame()
	check("the lock too", reloaded.painted("lock0: no such device"))

	-- And the gaps are NOT handed to the next door built: a number spent is
	-- spent for the life of the machine, or a script that says
	-- "echo open > /dev/door0" one day opens the wrong door the next. The new
	-- door is two devices and takes the next free number of EACH kind.
	kit.world.put(kit.world.squares["10,10,0"], fakeThumpable(false, false))
	reloaded.enter("ls -l /dev")
	reloaded.frame()
	check("the new door took the next number, not the gap",
		reloaded.painted("crw-rw----  root  sudo  door3   built          W  closed"))
	check("and so did its lock",
		reloaded.painted("crw-rw----  root  sudo  lock2   built          W  unlocked"))
	check("and the gaps are still gaps", not reloaded.painted("door0 "))
	check("both of them", not reloaded.painted("lock0 "))

	--
	-- A chmod outlives the command it was typed in.
	--
	reloaded.enter("chmod 666 /dev/light0")
	reloaded.enter("ls -l /dev/light0")
	reloaded.frame()
	check("the mode stuck", reloaded.painted("crw-rw-rw-  root  sudo  light0"))
	reloaded.enter("exit")
	reloaded.enter("ls -l /dev/light0")
	reloaded.frame()
	check("and it is still there for admin", reloaded.painted("crw-rw-rw-  root  sudo  light0"))
	reloaded.enter("cat /dev/light0")
	reloaded.frame()
	check("who may now read it", reloaded.painted("on"))

	-- Nothing of any of this is on the disk: what is left in /dev between commands
	-- is the machine's own null device and nothing of the world.
	eq("/dev holds only the hole between commands",
		CeroSecOS.countEntries(reloaded.object.os.fs.children.dev), 1)
	eq("and that is what it is",
		CeroSecOS.isNull(reloaded.object.os.fs.children.dev.children.null), true)
	eq("and the state still validates", CeroSecOS.validate(reloaded.object.os), true)

	_G.__world = nil
end

--
-- crw-rw----  root  sudo: a device is root's and the sudo group's, and the sudo
-- group is /etc/sudoers. So the account a shipped machine gives a survivor --
-- admin, who is in that file -- throws a light switch with no sudo typed and no
-- password asked, while an ordinary account gets nothing at all.
--
-- This is the whole point of the middle digit having been given meaning, and it
-- is asserted through the real window, on the real world objects, because a
-- session table built by hand cannot prove that the account at the glass is the
-- one the permission was worked out for.
--
do
	local kit = mockupWorld()
	_G.__world = kit.world

	local bench = newBench()
	bench.login("admin")
	bench.frame()
	eq("admin is at the glass and is not root", bench.object.console.user, "admin")

	bench.enter("id")
	bench.frame()
	check("and the machine says he is in the sudo group",
		bench.painted("uid=admin flag=user groups=admin,sudo,users"))

	-- The switch is off. One line, no sudo, no password prompt.
	eq("the switch starts off", kit.light1.activated, false)
	bench.enter("echo on > /dev/light1")
	bench.frame()
	eq("the shell is still a shell", bench.window.mode, "shell")
	check("nothing was asked for", not bench.painted("[sudo] password for admin: "))
	check("and nothing was refused", not bench.painted("light1: permission denied"))
	eq("the light is on", kit.light1.activated, true)
	eq("and the world was told", kit.light1.syncs, 1)

	-- And an account that is in no group of the machine's gets nothing, on the
	-- very same switch.
	bench.enter("su root")
	bench.enter("")
	bench.enter("adduser bob")
	bench.enter("exit")
	bench.frame()
	eq("back to admin", bench.object.console.user, "admin")
	bench.enter("su bob")
	bench.enter("")
	bench.frame()
	eq("bob is at the glass", bench.object.console.user, "bob")
	bench.enter("echo off > /dev/light1")
	bench.frame()
	check("bob is refused", bench.painted("light1: permission denied"))
	eq("and the switch did not move", kit.light1.activated, true)

	_G.__world = nil
end

--
-- Out of reach, and out of a building.
--

do
	-- A machine whose chunks are not loaded: the rooms answer with no live room
	-- at all, so nothing is found and nothing can be acted on. The numbers are
	-- still in the book -- they are the machine's, not the world's.
	local kit = mockupWorld()
	_G.__world = kit.world
	local bench = newBench()
	bench.login("admin")
	bench.enter("su root")
	bench.enter("")
	bench.enter("ls /dev")
	bench.frame()
	check("everything is there while the chunks are", bench.painted("light0"))

	kit.world.loaded = false
	bench.enter("ls -l /dev")
	bench.frame()
	check("and nothing is when they are not", not bench.painted("light0  office"))
	bench.enter("echo off > /dev/light0")
	bench.frame()
	check("a device out of reach cannot be worked",
		bench.painted("light0: no such device"))
	eq("and the switch did not move", kit.light0.activated, true)
	_G.__world = nil
end

do
	-- A player base: no building, no rooms, so the radius rule decides. The
	-- padlocked door two tiles away is in; a light switch twenty tiles away is
	-- not, and neither is one a floor up.
	local world = FakeWorld.new()
	-- The tile the computer itself stands on, which a world has to have before
	-- the machine reaches anything at all: no square of its own is a chunk the
	-- streamer has not brought in, and such a machine finds no devices
	-- (CeroSecDevices.find, and CeroSecRadio.tncAt one layer down).
	world.square(10, 10, 0, nil)
	local near = world.put(world.square(12, 10, 0, nil), fakeThumpable(true, true))
	local far = world.put(world.square(10 + CeroSecDevices.RADIUS + 1, 10, 0, nil),
		fakeLight(true, true))
	local upstairs = world.put(world.square(11, 10, 1, nil), fakeLight(true, true))
	_G.__world = world

	local bench = newBench()
	bench.login("admin")
	bench.enter("su root")
	bench.enter("")
	bench.enter("ls -l /dev")
	bench.frame()
	check("the door in the base is a device",
		bench.painted("crw-rw----  root  sudo  lock0   built          N  padlock"))
	check("the far switch is not", not bench.painted("light0"))
	eq("nor the one upstairs", far ~= upstairs, true)

	-- The edge of the radius is in.
	world.put(world.square(10 + CeroSecDevices.RADIUS, 10, 0, nil), fakeLight(false, true))
	bench.enter("ls -l /dev")
	bench.frame()
	check("a switch exactly at the radius is a device",
		bench.painted("crw-rw----  root  sudo  light0  exterior          off"))
	_G.__world = nil
end

do
	-- A garage door, and a double door: several objects making one opening.
	-- ToggleDoorSilent moves the object it is called on and nothing else, while
	-- vanilla's own toggle walks every leaf of the thing, so a leaf is NOT a
	-- `door` device -- a machine that opened one would leave the other half
	-- shut. It is still a `lock` one, setLockedByKey being per-object in vanilla
	-- too.
	local world = FakeWorld.new()
	world.room("garage", { {10,10,0}, {11,10,0} })
	local outside = world.square(11, 9, 0, nil)
	local leaf = world.put(world.squares["11,10,0"], fakeDoor(true, false, outside))
	leaf.garageDoor = 0
	_G.__world = world

	local bench = newBench()
	bench.login("admin")
	bench.enter("su root")
	bench.enter("")
	bench.enter("ls -l /dev")
	bench.frame()
	check("a garage door leaf is a lock",
		bench.painted("crw-rw----  root  sudo  lock0   exterior       W  locked"))
	check("and is not a door", not bench.painted("door0"))

	-- A double door reads exactly the same way.
	leaf.garageDoor = nil
	leaf.doubleDoor = 1
	bench.enter("ls -l /dev")
	bench.frame()
	check("a double door leaf is no door either", not bench.painted("door0"))
	check("and still locks", bench.painted("lock0   exterior"))

	-- So there is nothing there to open, and the refusal is the command's.
	bench.enter("dev door0 open")
	bench.frame()
	check("nothing to open", bench.painted("dev: door0: no such device"))
	_G.__world = nil
end

do
	-- The exterior rule has two halves and the game's own is the first. This
	-- door has a room on BOTH sides, so the room test says no -- and
	-- isExterior() says yes, because that is what the tile flags and the
	-- building on the far side say. A device is made where the LOCK bites, and
	-- the game is the authority on where that is.
	local world = FakeWorld.new()
	local porch = world.room("porch", { {10,10,0}, {11,10,0} })
	local far = world.square(11, 9, 0, porch)
	world.put(world.squares["11,10,0"], fakeDoor(true, false, far, true))
	_G.__world = world

	local bench = newBench()
	bench.login("admin")
	bench.enter("su root")
	bench.enter("")
	bench.enter("ls -l /dev")
	bench.frame()
	check("the game's own exterior flag makes the lock",
		bench.painted("crw-rw----  root  sudo  lock0   porch          W  locked"))
	check("and the door is there beside it",
		bench.painted("crw-rw----  root  sudo  door0   porch          W  locked"))
	_G.__world = nil
end

--
-- Motion sensors (rung 4d)
--
-- A sensor is an item on the floor and nothing of ours in the world, so the whole
-- of it is proved against the fake world: three heads dropped in two rooms, and
-- bodies that walk, stand still, enter, leave, sit behind a wall, drive, and go
-- invisible.
--
-- The one thing a bench cannot fake is the CADENCE, so it drives it: the game's
-- Events.OnTick handler is CeroSecSensors.tick and the clock it reads is
-- getTimestampMs, which is _G.__now here. Every sample below is a tick with the
-- clock moved by hand, which is exactly the sequence the server takes.
--

-- The world the sensor cases run in.
--
--   office  a 4x4 room, x 10..13 and y 10..13, the computer at its corner
--   store   ONE square at 14,10 -- next door to the office and NOT in it, which
--           is the wall: the two squares touch and a PIR does not see through it
--
--   sensor0  at 11,10 in the office
--   sensor1  at 13,10 in the office
--   sensor2  at 14,10 in the store
--
-- Every head has the same reach, CeroSec.SENSOR_RANGE, because there is one item
-- and it has one. Also on the floor: a hammer, and a PIPE BOMB WITH A SENSOR ON
-- IT -- neither of them is a device, and the second is the one that matters.
local function sensorWorld()
	local world = FakeWorld.new()
	local coords = {}
	for x = 10, 13 do
		for y = 10, 13 do coords[#coords + 1] = { x, y, 0 } end
	end
	world.room("office", coords)
	world.room("store", { {14,10,0} })

	local kit = { world = world }
	kit.head0 = world.drop(world.squares["11,10,0"], fakeSensor())
	kit.head1 = world.drop(world.squares["13,10,0"], fakeSensor())
	kit.head2 = world.drop(world.squares["14,10,0"], fakeSensor())
	kit.junk = world.drop(world.squares["12,10,0"], fakeJunk())
	-- A pipe bomb with a V1 sensor taped to it, lying in the same room as the
	-- heads. It is NOT a device and never will be: a thing that explodes when it
	-- detects movement is a mine, and a machine that called it sensor3 would be
	-- offering a survivor a security system that kills him.
	kit.bomb = world.drop(world.squares["12,12,0"],
		fakeTrapHead(3, "Base.PipeBombSensorV1"))
	return kit
end

-- A bench with the sampling book emptied. The book is module-level, like the
-- scheduler's list of machines, so one section must not inherit another's
-- contacts.
local function sensorBench()
	CeroSecSensors.book = {}
	CeroSecSensors.lastSampleMs = 0
	CeroSecSensors.lastScanMs = 0
	local bench = newBench()
	bench.login("admin")
	bench.enter("su root")
	bench.enter("")
	return bench
end

-- One second of the server's own clock: the tick handler, with the wall clock
-- moved first. Everything about the timeline below is built out of this.
local function second(bench, seconds)
	for _ = 1, (seconds or 1) do
		_G.__now = _G.__now + 1000
		CeroSecSensors.tick(bench.system)
	end
end

do
	local kit = sensorWorld()
	_G.__world = kit.world
	local bench = sensorBench()

	-- The listing. Three heads, two rooms, no side -- a PIR is not fixed to a
	-- wall the way a window is -- and 440: cr--r-----, because a sensor is read
	-- and never written and its mode says so before anybody tries.
	bench.enter("ls -l /dev")
	bench.frame()
	check("sensor0 is the head in the office",
		bench.painted("cr--r-----  root  sudo  sensor0 office            clear"))
	check("sensor1 is the one beside it",
		bench.painted("cr--r-----  root  sudo  sensor1 office            clear"))
	check("sensor2 is the one in the store",
		bench.painted("cr--r-----  root  sudo  sensor2 store             clear"))
	-- Three heads and no fourth: the hammer is not a device and NEITHER IS THE
	-- PIPE BOMB, which is the one refusal this whole rung turns on.
	check("a hammer on the floor is not a device", not bench.painted("sensor3"))

	-- The table, with the offset column that tells two heads in one room apart.
	bench.enter("dev sensor")
	bench.frame()
	check("the table gives sensor0 its place",
		bench.painted("sensor0 office                1E 0           clear"))
	check("and sensor1 its own",
		bench.painted("sensor1 office                3E 0           clear"))
	check("and sensor2 in the next room",
		bench.painted("sensor2 store                 4E 0           clear"))

	-- Read one. Nothing has moved and nothing ever has, so it is clear.
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("a sensor in a still room reads clear", bench.painted("clear"))

	--
	-- The timeline
	--

	-- A zombie in the middle of the office, one tile from sensor0. The FIRST
	-- sample only sets the baseline: a sensor that has just been powered has
	-- nothing to compare against, and it says nothing rather than firing.
	local z = fakeBody("IsoZombie")
	kit.world.stand(z, kit.world.squares["12,10,0"], 12.5, 10.5)
	second(bench)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("the first sample is a warm-up and not a contact", bench.painted("clear"))

	-- He takes a step. The picture is not the picture it was, so the contact
	-- closes.
	kit.world.stand(z, kit.world.squares["12,11,0"], 12.5, 11.5)
	second(bench)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("a body that moved closes the contact", bench.painted("motion"))

	-- And then he stops. The contact is held for SENSOR_HOLD_S whatever happens
	-- next, so four seconds of a perfectly still room still read motion.
	second(bench, 4)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("the hold outlasts the movement that started it", bench.painted("motion"))

	-- Six seconds after the last step, with the zombie still standing in the
	-- field: clear. That is the quirk, and it is the PIR's and not a bug.
	second(bench, 3)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("a body standing still in the field reads clear", bench.painted("clear"))

	-- The other head in the same room saw the same step, and has opened again too.
	bench.enter("cat /dev/sensor1")
	bench.frame()
	check("and so has the head beside it", bench.painted("clear"))

	_G.__world = nil
end

do
	-- A trap head is NEVER a device, and it is the only refusal here that is about
	-- what a machine should not offer rather than about what the world holds.
	--
	-- Every grade of every one of the five: each is a HandWeapon with a positive
	-- SensorRange, which is a bomb with a motion sensor taped to it. A room floored
	-- with them grows no sensorN at all -- and then ONE bare module in the same room
	-- grows sensor0, so what refuses them is the refusal and not an empty world.
	local world = FakeWorld.new()
	world.room("office", { {10,10,0}, {11,10,0}, {12,10,0}, {13,10,0} })
	local TRAPS = { "PipeBomb", "Aerosolbomb", "NoiseTrap", "SmokeBomb", "FlameTrap" }
	local RANGES = { 3, 4, 6 }
	for t = 1, #TRAPS do
		for g = 1, 3 do
			world.drop(world.squares["1" .. g .. ",10,0"],
				fakeTrapHead(RANGES[g], "Base." .. TRAPS[t] .. "SensorV" .. g))
		end
	end
	_G.__world = world
	local bench = sensorBench()

	bench.enter("dev sensor")
	bench.frame()
	check("fifteen trap heads on the floor are no device at all",
		not bench.painted("sensor0"))
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("and naming one is a path nothing answers to",
		bench.painted("cat: /dev/sensor0: no such file"))

	-- The same room, one bare module in it.
	world.drop(world.squares["10,10,0"], fakeSensor())
	bench.enter("dev sensor")
	bench.frame()
	check("while the module beside them is sensor0", bench.painted("sensor0 office"))
	_G.__world = nil
end

do
	-- The wall. sensor1 is at 13,10 and the store square at 14,10 is ONE tile away
	-- from it -- well inside its reach and on the other side of a wall. A survivor
	-- shuffling about in the store must not reach it, and must reach the head
	-- standing in the store with him.
	local kit = sensorWorld()
	_G.__world = kit.world
	local bench = sensorBench()

	local chr = fakeBody("IsoPlayer")
	kit.world.stand(chr, kit.world.squares["14,10,0"], 14.5, 10.5)
	second(bench)
	kit.world.stand(chr, kit.world.squares["14,10,0"], 14.2, 10.8)
	second(bench)

	bench.enter("cat /dev/sensor1")
	bench.frame()
	check("a PIR does not see through a wall one tile away", bench.painted("clear"))
	bench.enter("cat /dev/sensor2")
	bench.frame()
	check("the head in that room does see him", bench.painted("motion"))
	_G.__world = nil
end

do
	-- The range, and the SHAPE of it. The game's own sensor measures a squared
	-- euclidean distance from the centre of its own tile
	-- (IsoTrap.updateVictimsInSensorRange: DistanceToSquared(mo.getX(), mo.getY(),
	-- getX() + 0.5f, getY() + 0.5f) <= range * range), so a body two tiles east
	-- and three south of a head is 3.6 tiles away and is NOT seen at a reach of
	-- three -- while a sensor that counted tiles the square way would have called
	-- that 3 and fired. It is on sensor0's square list, so what refuses it is the
	-- distance and not the box the squares were gathered in.
	local kit = sensorWorld()
	_G.__world = kit.world
	local bench = sensorBench()

	local chr = fakeBody("IsoPlayer")
	kit.world.stand(chr, kit.world.squares["13,13,0"], 13.5, 13.5)
	second(bench)
	kit.world.stand(chr, kit.world.squares["13,13,0"], 13.1, 13.9)
	second(bench)

	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("3.6 tiles is past a reach of 3, corner or not", bench.painted("clear"))
	-- The same body, three tiles due south of the other head: exactly on its reach,
	-- and <= is what the game writes, so it is seen.
	bench.enter("cat /dev/sensor1")
	bench.frame()
	check("and three tiles due south is inside it", bench.painted("motion"))
	_G.__world = nil
end

do
	-- Coming in and going out, which a signature catches without following
	-- anybody: an entry that was not there, and an entry that is missing.
	local kit = sensorWorld()
	_G.__world = kit.world
	local bench = sensorBench()

	second(bench)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("an empty room is clear", bench.painted("clear"))

	local chr = fakeBody("IsoPlayer")
	kit.world.stand(chr, kit.world.squares["11,10,0"], 11.5, 10.5)
	second(bench)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("somebody walking in closes it", bench.painted("motion"))

	second(bench, 6)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("and it opens again while he stands there", bench.painted("clear"))

	kit.world.stand(chr, nil)
	second(bench)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("him leaving closes it again", bench.painted("motion"))
	_G.__world = nil
end

do
	-- A car is warm. The game's own sensor casts to IsoGameCharacter and skips
	-- only an INVISIBLE one, so a BaseVehicle -- which extends IsoMovingObject and
	-- not IsoGameCharacter -- falls straight through to the distance test and sets
	-- the thing off. An invisible survivor does not, which is the other half of
	-- the same branch.
	local kit = sensorWorld()
	_G.__world = kit.world
	local bench = sensorBench()

	local car = fakeBody("BaseVehicle")
	kit.world.stand(car, kit.world.squares["11,11,0"], 11.5, 11.5)
	second(bench)
	kit.world.stand(car, kit.world.squares["11,12,0"], 11.5, 12.5)
	second(bench)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("a car crossing the field sets it off", bench.painted("motion"))

	second(bench, 6)
	local ghost = fakeBody("IsoPlayer", true)
	kit.world.stand(ghost, kit.world.squares["11,10,0"], 11.5, 10.5)
	second(bench)
	kit.world.stand(ghost, kit.world.squares["12,10,0"], 12.5, 10.5)
	second(bench)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("an invisible survivor does not", bench.painted("clear"))
	_G.__world = nil
end

do
	-- Nothing may be written to one, and the machine says so in the sensor's own
	-- name. The word never reaches the world at all: the kind has no vocabulary,
	-- so the refusal is the engine's.
	local kit = sensorWorld()
	_G.__world = kit.world
	local bench = sensorBench()

	bench.enter("echo on > /dev/sensor0")
	bench.frame()
	check("a sensor cannot be told anything", bench.painted("sensor0: invalid value"))
	bench.enter("dev sensor0 motion")
	bench.frame()
	check("nor through dev", bench.painted("sensor0: invalid value"))
	bench.enter("dev sensor0 clear")
	bench.frame()
	check("nor with the word it reads", bench.painted("sensor0: invalid value"))
	-- And there is no opposite of a fact, so there is nothing to toggle.
	bench.enter("dev sensor0 toggle")
	bench.frame()
	check("and there is nothing to toggle", bench.painted("sensor0: cannot toggle"))

	-- root reads it, and so does a member of sudo at 440. Nobody else.
	bench.enter("exit")
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("admin is in sudo and reads it", bench.painted("clear"))
	_G.__world = nil
end

do
	-- Picked up. The head is gone from the world, so the number is spent and
	-- naming it answers about the DEVICE and not about the path.
	local kit = sensorWorld()
	_G.__world = kit.world
	local bench = sensorBench()

	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("it is there to begin with", bench.painted("clear"))

	kit.world.pickUp(kit.head0)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("a sensor picked up is no such device",
		bench.painted("sensor0: no such device"))
	bench.enter("dev sensor")
	bench.frame()
	-- The row and not the id: the refusal printed a second ago has the id in it
	-- and is still in the scrollback, so a needle of "sensor0" would find the
	-- machine's own words about it being gone.
	check("and it is off the table", not bench.painted("sensor0 office"))
	check("while the other two are still on it", bench.painted("sensor1 office"))

	-- A fresh head dropped on the same tile takes sensor0 BACK, and that is the
	-- numbering doing what it has always done rather than a special case: a number
	-- hangs on where the device is (state.devmap is keyed by the place), so
	-- swapping a V1 for a V3 on the same shelf leaves every script that named
	-- sensor0 pointing at the sensor on that shelf. A head dropped somewhere else
	-- is somewhere else and gets the next number never used.
	kit.world.drop(kit.world.squares["11,10,0"], fakeSensor())
	bench.enter("dev sensor")
	bench.frame()
	check("a new head on the same tile is sensor0 again", bench.painted("sensor0 office"))
	kit.world.drop(kit.world.squares["12,11,0"], fakeSensor())
	bench.enter("dev sensor")
	bench.frame()
	check("and one on a new tile takes the next number", bench.painted("sensor3 office"))
	_G.__world = nil
end

do
	-- `dev find` on one. A head has nothing to blink with, so the requesting
	-- player's own screen outlines it -- and the client finds it again on the
	-- OTHER list, by the item it is, because a dropped item has no sprite name.
	local kit = sensorWorld()
	_G.__world = kit.world
	local bench = sensorBench()

	bench.enter("dev find sensor0")
	bench.frame()
	check("a sensor is pointed at with an outline",
		bench.painted("sensor0: highlighted"))
	eq("and it was drawn for the player who typed it", kit.head0.highlights[1], "0=true")
	check("with the outline on", kit.head0.outline == true)
	-- The other two were not touched: a find lights ONE thing.
	eq("and for nobody else's sensor", #kit.head1.highlights, 0)
	_G.__world = nil
end

do
	-- No building: a sensor dropped in a base. There is no room to name it with,
	-- so it reads `built` the way a player-built door does, and the field is the
	-- range and nothing else -- there are no walls out there to be seen through.
	local world = FakeWorld.new()
	for x = 8, 16 do
		for y = 8, 16 do world.square(x, y, 0, nil) end
	end
	local head = world.drop(world.squares["12,10,0"], fakeSensor())
	_G.__world = world
	local bench = sensorBench()

	bench.enter("dev sensor")
	bench.frame()
	check("a head in a base reads built", bench.painted("sensor0 built"))

	-- Two tiles from it and no room between them: seen.
	local chr = fakeBody("IsoPlayer")
	world.stand(chr, world.squares["14,10,0"], 14.5, 10.5)
	second(bench)
	world.stand(chr, world.squares["14,10,0"], 14.5, 10.9)
	second(bench)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("and sees two tiles out with nothing in the way", bench.painted("motion"))

	second(bench, 6)
	-- Four tiles from a reach of three: not seen, and the head is not even looking
	-- at that square.
	world.stand(chr, world.squares["16,10,0"], 16.5, 10.5)
	second(bench)
	world.stand(chr, world.squares["16,10,0"], 16.5, 10.9)
	second(bench)
	bench.enter("cat /dev/sensor0")
	bench.frame()
	check("and not four tiles out", bench.painted("clear"))
	-- The item it is, and the reach the mod gives it -- the module carries no
	-- SensorRange of its own, which is why the number is the mod's and cited.
	eq("the head is the bare module", head.item.getFullType(), CeroSecSensors.ITEM)
	eq("and its reach is the module's own", CeroSec.SENSOR_RANGE, 3)
	_G.__world = nil
end

do
	-- The computer off is the sensor unwired. The sampling walk asks the system
	-- for its machines and skips every one that is not on, so a county of dark
	-- computers costs a pass that touches nothing at all.
	local kit = sensorWorld()
	_G.__world = kit.world
	local bench = sensorBench()
	bench.enter("cat /dev/sensor0")
	bench.frame()

	CeroSecSensors.book = {}
	bench.object.on = false
	second(bench, 61)
	local held = 0
	for _ in pairs(CeroSecSensors.book) do held = held + 1 end
	eq("a machine that is off samples nothing", held, 0)

	-- On again, and the next scan finds them.
	bench.object.on = true
	second(bench, 61)
	held = 0
	for _ in pairs(CeroSecSensors.book) do held = held + 1 end
	eq("and one that is on finds all three", held, 3)
	_G.__world = nil
end

--
-- Scripts, through the glass (rung 5a)
--
-- The engine is bench-tested in os_test and the scheduler in hostile_test.
-- What is here is the round trip: a line typed at a window, a job made on the
-- server, output arriving over several passes, a question answered at the
-- prompt, and Escape.
--

-- A script printing lines, drop by drop.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/hello.sh", "echo one\necho two\necho three\n")

	-- The line a player types gets its first pass in his own hand (see
	-- SCeroSecSystem:startPrompt), so a script this short is over before the
	-- answer goes back -- exactly as `ls` has always been. A LINE is a job now;
	-- it is not a job the player has to wait for.
	bench.enter("sh hello.sh")
	bench.frame()
	check("the line that started it is on the glass", bench.painted("sh hello.sh"))
	check("the first line arrives", bench.painted("one"))
	check("and the second", bench.painted("two"))
	check("and the third", bench.painted("three"))
	eq("the prompt is back", bench.window.mode, "shell")
	eq("and the machine agrees", CeroSec.consoleWaiting(bench.object.console), "shell")
	eq("with the status the script ended on", bench.object.console.status, 0)
	check("the shell prompt is on the glass again", bench.painted("admin@ksp"))
end

-- A script that does NOT finish in that first pass is a job, and the window is
-- told there is nothing to type at.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/slow.sh", "i=0\nwhile true; do i=$((i+1)); done\n")

	bench.enter("sh slow.sh")
	bench.frame()
	eq("the machine is running a job", CeroSec.consoleWaiting(bench.object.console), "job")
	eq("and the window knows it", bench.window.mode, "job")
	-- The echoed line has a prompt in it, of course; what must not be there is
	-- a LIVE one under it, waiting to be typed at.
	eq("there is no prompt to type at", bench.window.prompt, "")
	eq("and no row is given to one", bench.window:inputHeight(), 0)
	check("and Escape would interrupt it", bench.window.active)

	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	eq("which brings the prompt straight back", bench.window.mode, "shell")
	check("with the ^C on the glass", bench.painted("^C"))
end

-- A script that prints as fast as it can is a trickle and not a flood: the
-- machine puts at most CeroSec.JOB_OUT_PER_SEC lines on the screen a second,
-- however many the job has made.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/flood.sh", "while true; do echo x; done\n")

	bench.enter("sh flood.sh")
	-- Counted from AFTER the pass the typed line got in the player's own hand:
	-- that pass is in the second the key was pressed in, and what is being
	-- measured here is one whole second of a job flooding on its own.
	local before = #bench.object.console.lines
	-- Ten passes is one second of wall clock.
	bench.tick(10)
	local made = #bench.object.console.lines - before
	check("a second of flooding put at most twenty lines on the screen (" .. made .. ")",
		made <= CeroSec.JOB_OUT_PER_SEC + 1)
	check("and it did put some there", made > 0)
	eq("the screen never holds more than its hundred lines",
		#bench.object.console.lines <= CeroSec.CONSOLE_MAX, true)

	local job = CeroSecJobs.foreground(bench.object, bench.object.console)
	check("the job is still alive and simply slow", job ~= nil)
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.tick(1)
end

-- read -p, answered at the window.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/ask.sh", 'read -p "name? " who\necho "hello $who"\n')

	bench.enter("sh ask.sh")
	bench.tick(1)
	eq("the script's question is the console's prompt", bench.window.mode, "prompt")
	eq("and it is the question the script asked", bench.window.prompt, "name? ")
	check("Escape would interrupt it", bench.window.active)

	bench.enter("bob")
	bench.tick(2)
	check("the answer was echoed with its question", bench.painted("name? bob"))
	check("and the script used it", bench.painted("hello bob"))
	bench.tick(2)
	eq("the prompt is back", bench.window.mode, "shell")
end

-- Escape kills a running loop, with ^C on the screen.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/spin.sh", "while true; do x=1; done\n")

	bench.enter("sh spin.sh")
	bench.tick(3)
	eq("it is still running", bench.window.mode, "job")
	local job = CeroSecJobs.foreground(bench.object, bench.object.console)
	check("and it has spent steps doing it", job ~= nil and job.steps > 0)

	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	check("^C is on the glass", bench.painted("^C"))
	bench.tick(1)
	check("and the machine says it killed it", bench.painted("killed"))
	eq("the prompt is back", bench.window.mode, "shell")
	eq("and the machine is running nothing", #CeroSecJobs.book(bench.object).list, 0)
	check("the window did not close", not bench.window.closing)
end

-- A background job: [1] on the way in, [1] done on the way out.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/bg.sh", "echo working\n")

	bench.enter("sh bg.sh &")
	bench.frame()
	eq("the prompt is not taken by a background job", bench.window.mode, "shell")
	-- Slot one, id forty-THREE: the shell that read the line is a job too now
	-- and took forty-two, the way a real shell holds a pid of its own and its
	-- children get later ones.
	check("the machine announced it", bench.painted("[1] 43"))

	bench.tick(3)
	check("its output came to the same screen", bench.painted("working"))
	check("and its end is announced", bench.painted("[1] done"))
end

-- A statement behind an `&` is a SUBSHELL: it starts with a copy of the
-- variables the shell that wrote it was holding.
--
-- It used to start with PATH and nothing else at all -- not even HOME -- so the
-- same file answered differently in the foreground and behind the prompt, and
-- Volume 3 had a page showing the gap as though it were a rule. cron is the
-- only thing on this machine that starts with an environment of its own, and
-- that one is real: it is the oldest trap in Unix and the book keeps it.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/where.sh", 'echo "HOME is [$HOME] x is [$x]"\n')
	bench.script("/home/admin/set.sh", "y=inside\n")

	bench.enter("x=hi")
	bench.enter("./where.sh")
	bench.tick(3)
	bench.frame()
	check("in the foreground it has the shell's variables",
		bench.painted("HOME is [/home/admin] x is [hi]"))

	bench.enter("./where.sh &")
	bench.tick(4)
	bench.frame()
	check("and behind the prompt it has the same ones",
		bench.painted("HOME is [/home/admin] x is [hi]"))

	-- A COPY, and not the shell's own table: what a job behind the prompt sets is
	-- its own and dies with it, which is what a subshell is.
	bench.enter("y=outside")
	bench.enter("./set.sh &")
	bench.tick(4)
	bench.enter("echo [$y]")
	bench.tick(2)
	bench.frame()
	check("what the background job set did not come back", bench.painted("[outside]"))
	check("and certainly not that", not bench.painted("[inside]"))
end

-- ps, jobs and kill, from the prompt, on a job that is running.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/spin.sh", "while true; do x=1; done\n")

	bench.enter("sh spin.sh &")
	bench.tick(2)
	bench.enter("ps")
	bench.frame()
	check("ps has a header", bench.painted("  ID S     CPU COMMAND"))
	check("and the job in it", bench.painted("sh spin.sh"))

	bench.enter("jobs")
	bench.frame()
	check("jobs names the slot", bench.painted("[1] running"))

	bench.enter("kill %1")
	bench.tick(2)
	check("the machine says it killed it", bench.painted("[1] killed"))
	eq("and it is gone", #CeroSecJobs.book(bench.object).list, 0)

	bench.enter("kill %1")
	bench.frame()
	check("killing it again finds nothing", bench.painted("kill: %1: no such job"))
end

-- Four jobs is the ceiling, and the fifth is refused where it was typed.
--
-- Counted the same way whichever way a job starts, which it was not: a script
-- behind an `&` runs INSIDE the job the machine made for it and asks the machine
-- for no second one, and `sh` used to count that job among the ones in its way --
-- so the fourth `./spin.sh &` refused itself, with the machine's own words, while
-- the fourth typed loop went through. Both are asserted here, side by side.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/spin.sh", "while true; do x=1; done\n")
	for _ = 1, 4 do
		bench.enter("./spin.sh &")
		bench.tick(1)
	end
	bench.frame()
	eq("four background scripts are running",
		CeroSecOS.liveJobs(CeroSecJobs.book(bench.object).list), 4)
	check("and none of them refused itself", not bench.painted("too many jobs"))
	bench.enter("./spin.sh &")
	bench.tick(1)
	bench.frame()
	check("the fifth is refused", bench.painted("sh: too many jobs"))
	eq("and there are still four",
		CeroSecOS.liveJobs(CeroSecJobs.book(bench.object).list), 4)
end

-- The same ceiling, the same count, for four typed loops: no file, no `sh`, and
-- the fifth refused in the same words.
do
	local bench = newBench()
	bench.login("admin")
	for _ = 1, 4 do
		bench.enter("while true; do x=1; done &")
		bench.tick(1)
	end
	bench.frame()
	eq("four typed loops are running",
		CeroSecOS.liveJobs(CeroSecJobs.book(bench.object).list), 4)
	bench.enter("while true; do x=1; done &")
	bench.tick(1)
	bench.frame()
	check("the fifth is refused", bench.painted("sh: too many jobs"))
	eq("and there are still four",
		CeroSecOS.liveJobs(CeroSecJobs.book(bench.object).list), 4)
end

-- Reboot kills everything that was running.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/spin.sh", "while true; do x=1; done\n")
	bench.enter("sh spin.sh &")
	bench.tick(1)
	eq("a job is running", #CeroSecJobs.book(bench.object).list, 1)

	bench.enter("sudo reboot")
	bench.enter("")
	bench.frame()
	check("the machine has no job book left", bench.object.jobs == nil)
	-- The one thing the scheduler still holds it for is the dark interval: a
	-- machine that is coming back is counted on the same pass a pending shutdown
	-- is (CeroSecJobs.checkReboot).
	eq("the machine is in the scheduler for the dark alone", #CeroSecJobs.machines, 1)
	eq("and that is all it is there for", bench.object.jobs, nil)

	_G.__now = _G.__now + CeroSec.REBOOT_DARK_MS
	bench.tick(2)
	eq("it came back running nothing", bench.object.on, true)
	eq("and the scheduler has let it go", #CeroSecJobs.machines, 0)
end

--
-- The prompt IS the shell (rung 5a.1)
--
-- os_test drives the engine and hostile_test the scheduler. What is here is the
-- round trip Mathieu's screenshot was of: a loop typed at the glass.
--

-- The line from the screenshot.
do
	local bench = newBench()
	bench.login("admin")

	bench.enter("while true; do echo tick; sleep 1; done &")
	bench.frame()
	check("the loop is not an unknown command", not bench.painted("while: command not found"))
	eq("the prompt came straight back", bench.window.mode, "shell")
	check("and the machine announced a job", bench.painted("[1] "))

	bench.enter("jobs")
	bench.frame()
	-- "sleeping" and not "running": the loop is between two ticks, waiting on
	-- its own `sleep 1`, which is what `jobs` is supposed to say about it.
	check("jobs names the slot", bench.painted("[1] sleeping"))
	check("and carries the line that was typed",
		bench.painted("while true; do echo tick; sleep 1; done"))

	bench.tick(12)
	check("it ticks", bench.painted("tick"))

	bench.enter("kill %1")
	bench.tick(2)
	check("and kill stops it", bench.painted("[1] killed"))
	eq("with nothing left running", #CeroSecJobs.book(bench.object).list, 0)
end

-- The shell's variables are the machine's: they outlive the window.
do
	local bench = newBench()
	bench.login("admin")

	-- What a login puts in them before anybody types: the two a login shell has
	-- always set, and the real server is what set them here.
	eq("a login sets PATH", bench.object.console.shvars.PATH, CeroSecOS.DEFAULT_PATH)
	eq("and HOME", bench.object.console.shvars.HOME, "/home/admin")

	bench.enter("x=5")
	bench.enter("echo $x")
	bench.frame()
	check("a variable set at the prompt reads back", bench.painted("5"))

	local w = bench.reopen()
	bench.enterOn(w, "echo [$x]")
	bench.frame()
	check("and survives the window closing", bench.paintedOn(w, "[5]"))
	eq("the machine holds it", bench.object.console.shvars.x, "5")

	-- A logout takes them, the way it takes the session.
	bench.enterOn(w, "exit")
	bench.frame()
	eq("nobody is logged in", bench.object.console.user, nil)
	eq("and the variables are gone", bench.object.console.shvars, nil)
end

-- Up and Down walk ~/.sh_history, which the machine keeps.
do
	local bench = newBench()
	bench.login("admin")

	bench.enter("pwd")
	bench.enter("whoami")
	bench.frame()

	local state = bench.object:osState()
	local session = bench.system:sessionOf(bench.object.console)
	local lines = CeroSecOS.historyLines(state, session)
	eq("the machine wrote both lines down", #lines, 2)
	eq("oldest first", lines[1], "pwd")
	eq("newest last", lines[2], "whoami")

	-- A brand new window, handed the account's own history when it opened.
	local w = bench.reopen()
	eq("the new window was handed the history", #w.history, 2)
	w:onHistory(1)
	eq("Up is the last line typed", w.entry:getInternalText(), "whoami")
	w:onHistory(1)
	eq("again is the one before it", w.entry:getInternalText(), "pwd")
	w:onHistory(-1)
	eq("and Down comes back", w.entry:getInternalText(), "whoami")

	-- history, !! and !n at the glass.
	bench.enterOn(w, "history")
	bench.frame()
	check("history numbers them", bench.paintedOn(w, "    1  pwd"))
	bench.enterOn(w, "!1")
	bench.frame()
	check("an event is echoed as what it expanded to", bench.paintedOn(w, "$ pwd"))
	check("and it ran", bench.paintedOn(w, "/home/admin"))
	bench.enterOn(w, "!99")
	bench.frame()
	check("an event nothing answers to says so", bench.paintedOn(w, "sh: !99: event not found"))

	bench.enterOn(w, "history -c")
	bench.enterOn(w, "history")
	bench.frame()
	eq("and clearing empties the file",
		#CeroSecOS.historyLines(state, bench.system:sessionOf(bench.object.console)), 1)
end

-- A password is not history.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("passwd")
	bench.enter("")
	bench.enter("hunter2")
	bench.enter("hunter2")
	bench.frame()
	local state = bench.object:osState()
	local lines = CeroSecOS.historyLines(state, bench.system:sessionOf(bench.object.console))
	for i = 1, #lines do
		check("nothing answered at a prompt is in the history", lines[i] ~= "hunter2")
	end
	check("the command itself is", (function()
		for i = 1, #lines do
			if lines[i] == "passwd" then return true end
		end
		return false
	end)())
end

-- ~/.profile, at login.
do
	local bench = newBench()
	local state = bench.object:osState()
	local session = { user = "admin", cwd = "/home/admin", stamp = 1 }
	local done, reason = CeroSecOS.writeFile(state, session, "/home/admin/.profile",
		"echo welcome home\ngreeting=hello\ncd /etc\n", false, 100)
	if done == nil then error("cannot write .profile: " .. tostring(reason)) end

	bench.login("admin")
	bench.frame()
	check("the profile ran after the motd", bench.painted("welcome home"))
	eq("what it set is set at the prompt", bench.object.console.shvars.greeting, "hello")
	eq("and where it went is where the prompt is", bench.object.console.cwd, "/etc")
	bench.enter("echo $greeting")
	bench.frame()
	check("readable from the prompt", bench.painted("hello"))
	eq("the prompt is a prompt", bench.window.mode, "shell")
	-- Not history: nobody typed it.
	local lines = CeroSecOS.historyLines(state, bench.system:sessionOf(bench.object.console))
	for i = 1, #lines do
		check("the profile is not in the history", lines[i] ~= "cd /etc")
	end
end

-- A profile that will not parse says so the way a script does, and the account
-- is still logged in.
do
	local bench = newBench()
	local state = bench.object:osState()
	local session = { user = "admin", cwd = "/home/admin", stamp = 1 }
	CeroSecOS.writeFile(state, session, "/home/admin/.profile", "echo one\nfi\n", false, 100)

	bench.login("admin")
	bench.frame()
	check("it names the file and the line",
		bench.painted(".profile: line 2: syntax error: unexpected 'fi'"))
	eq("and the account is at a prompt", bench.window.mode, "shell")
end

-- A profile that loops forever leaves a busy prompt, and Escape is the way out.
-- Documented as the quirk it is (chapter on the profile).
do
	local bench = newBench()
	local state = bench.object:osState()
	local session = { user = "admin", cwd = "/home/admin", stamp = 1 }
	CeroSecOS.writeFile(state, session, "/home/admin/.profile",
		"while true; do x=1; done\n", false, 100)

	bench.login("admin")
	bench.frame()
	eq("the machine is busy with it", CeroSec.consoleWaiting(bench.object.console), "job")
	eq("and there is nothing to type at", bench.window.prompt, "")
	check("but Escape is armed", bench.window.active)

	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	eq("which gives the account its prompt", bench.window.mode, "shell")
	check("with the ^C on the glass", bench.painted("^C"))
end

-- A profile nobody may read is a profile that does not run.
do
	local bench = newBench()
	local state = bench.object:osState()
	local session = { user = "admin", cwd = "/home/admin", stamp = 1 }
	CeroSecOS.writeFile(state, session, "/home/admin/.profile", "echo secret\n", false, 100)
	CeroSecOS.getNode(state, session, "/home/admin/.profile").mode = 0
	CeroSecOS.getNode(state, session, "/home/admin/.profile").owner = "root"

	bench.login("admin")
	bench.frame()
	check("it did not run", not bench.painted("secret"))
	eq("and the account is at a prompt", bench.window.mode, "shell")
end

-- shutdown -r +1: the broadcast, the warning, and the reboot.
do
	local bench = newBench()
	local kit = embody(bench)
	bench.login("root")
	local other = bench.addWindow()
	other:askForScreen()

	bench.enter("shutdown -r +1")
	bench.frame()
	check("the machine tells everybody at it",
		bench.painted("The system is going down for reboot in 1 minute!"))
	check("the second pair of eyes too",
		bench.paintedOn(other, "The system is going down for reboot in 1 minute!"))
	check("and it is pending", bench.object.shutdown ~= nil)
	eq("the machine is still up", bench.object.on, true)
	-- A second one is refused rather than replacing the first.
	bench.enter("shutdown -h +5")
	bench.frame()
	check("only one at a time", bench.painted("shutdown: already scheduled"))

	-- Nothing happens until the minute is up.
	bench.tick(5)
	eq("still up", bench.object.on, true)

	-- And then it goes down: the timer's reboot is the typed one's reboot, dark
	-- interval and all.
	_G.__now = _G.__now + 61000
	bench.tick(1)
	-- Said, not painted: the line goes out to every window and the machine wipes
	-- its console in the same breath, so there is no glass left to paint it on.
	check("it says NOW", bench.heard("The system is going down for reboot NOW!"))
	eq("the machine is off", bench.object.on, false)
	eq("the tile is unlit", kit.iso.sprite, CeroSec.SPRITES_OFF["S"])
	check("both windows shut", bench.window.closing and other.closing)
	eq("and both were told why", bench.closed[#bench.closed], "reboot")
	eq("nothing is pending any more", bench.object.shutdown, nil)

	_G.__now = _G.__now + CeroSec.REBOOT_DARK_MS
	bench.tick(1)
	eq("and the machine came back", bench.object.on, true)
	eq("with nobody logged in", bench.object.console.user, nil)
	eq("and two windows back at it", #bench.windows, 4)
	_G.__world = nil
end

-- shutdown -c, and a warning a minute out on a longer one.
do
	local bench = newBench()
	bench.login("root")

	bench.enter("shutdown -h +2")
	bench.frame()
	check("two minutes out", bench.painted("The system is going down for halt in 2 minutes!"))

	-- A minute passes: the warning, and still up.
	_G.__now = _G.__now + 61000
	bench.tick(1)
	check("the minute warning", bench.painted("The system is going down for halt in 1 minute!"))
	eq("still up", bench.object.on, true)

	bench.enter("shutdown -c")
	bench.frame()
	check("cancelled", bench.painted("shutdown: cancelled"))
	eq("and nothing is pending", bench.object.shutdown, nil)

	-- The minute it would have gone down on comes and goes.
	_G.__now = _G.__now + 120000
	bench.tick(2)
	eq("the machine is still up", bench.object.on, true)
	eq("and the scheduler has let it go", #CeroSecJobs.machines, 0)
end

-- halt is shutdown -h now under the name it has had since the seventies.
do
	local bench = newBench()
	bench.login("root")
	bench.enter("halt")
	bench.frame()
	eq("the machine is off", bench.object.on, false)
end

--
-- Tab: completion, end to end
--
-- The engine's half is pinned in os_test. This is the other half: the key the
-- game delivers, the round trip, and what is in the box and on the glass
-- afterwards. A completion that is right in the engine and puts the word in the
-- wrong place in the line is a completion nobody can use.
--

do
	local bench = newBench()
	bench.login("admin")

	-- Two files whose names share a prefix, and one that does not.
	bench.enter("write notes.txt hi")
	bench.enter("write note2.txt hi")
	bench.enter("mkdir work")
	bench.frame()

	-- One Tab, several names: as far as they agree, and the caret after it.
	bench.typed("cat no")
	bench.tab()
	bench.frame()
	eq("the word is completed as far as the names agree",
		bench.window.entry:getInternalText(), "cat note")
	eq("and the caret is after it", bench.window.entry:getCursorPos(), 8)
	eq("the window remembers the two names", #bench.window.tabNames, 2)
	-- Nothing of it reached the machine's screen: Tab is not a command.
	check("the machine echoed nothing", not bench.heard("cat note"))

	-- The second Tab, on the same word: the names, in columns, like ls.
	bench.tab()
	bench.frame()
	check("the second Tab lists the names", bench.painted("note2.txt"))
	check("both of them", bench.painted("notes.txt"))
	check("in one row, the way ls packs them", bench.painted("note2.txt  notes.txt"))
	-- And the prompt line is under the listing, with the word still in it.
	check("the prompt is re-drawn under the listing", bench.painted("cat note"))
	-- The listing is the WINDOW\'s line and never the machine\'s.
	check("the machine put no listing on its screen",
		not bench.heard("note2.txt  notes.txt"))
	eq("and the box is untouched by the listing",
		bench.window.entry:getInternalText(), "cat note")

	-- One more character and it is unique: the whole name, and a space.
	bench.typed("cat notes")
	bench.tab()
	bench.frame()
	eq("a unique file completes whole, with a space",
		bench.window.entry:getInternalText(), "cat notes.txt ")
	eq("and the caret is past the space", bench.window.entry:getCursorPos(), 14)

	-- A unique directory ends in a slash instead.
	bench.typed("cd wo")
	bench.tab()
	bench.frame()
	eq("a unique directory completes with a slash",
		bench.window.entry:getInternalText(), "cd work/")

	-- The first word is a command name.
	bench.typed("whoa")
	bench.tab()
	bench.frame()
	eq("the first word completes to a command",
		bench.window.entry:getInternalText(), "whoami ")

	-- What is to the right of the caret is kept.
	bench.typed("cat no > out.txt", 6)
	bench.tab()
	bench.frame()
	eq("the rest of the line is kept",
		bench.window.entry:getInternalText(), "cat note > out.txt")
	eq("and the caret sits where the word ends", bench.window.entry:getCursorPos(), 8)

	-- Nothing matches: the line is left exactly as it was typed.
	bench.typed("cat zzz")
	bench.tab()
	bench.frame()
	eq("nothing matched, nothing changed",
		bench.window.entry:getInternalText(), "cat zzz")

	-- And the line still runs, so nothing the completion did broke it.
	bench.typed("")
	bench.enter("cat notes.txt")
	bench.frame()
	check("the completed name is a real file", bench.painted("hi"))
end

-- Where Tab is NOT completion: a question, a running job, and the editor.
do
	local bench = newBench()

	-- At the login prompt: nothing goes over the wire and nothing changes.
	bench.window:askForScreen()
	_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
	bench.frame()
	eq("the machine is asking for a name", bench.window.mode, "prompt")
	bench.typed("ad")
	bench.tab()
	bench.frame()
	eq("Tab at a question types nothing", bench.window.entry:getInternalText(), "ad")
	eq("and the window is not left waiting on an answer", bench.window.busy, false)

	bench.enter("admin")
	bench.enter("")
	bench.frame()
	eq("logged in", bench.window.mode, "shell")

	-- While a job holds the prompt there is no line to complete.
	bench.enter("sleep 3")
	bench.frame()
	eq("a job has the prompt", bench.window.mode, "job")
	bench.typed("ca")
	bench.tab()
	bench.frame()
	eq("Tab at a running job types nothing", bench.window.entry:getInternalText(), "ca")
	eq("and does not leave the window waiting", bench.window.busy, false)

	-- The job finishes and the prompt comes back; Tab completes again.
	_G.__now = _G.__now + 4000
	bench.tick(2)
	eq("the prompt is back", bench.window.mode, "shell")
	bench.typed("whoa")
	bench.tab()
	bench.frame()
	eq("and Tab completes at it", bench.window.entry:getInternalText(), "whoami ")
end

-- In the editor Tab is still nano\'s save, and completes nothing.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("edit notes.txt")
	bench.frame()
	eq("in the editor", bench.window.mode, "edit")

	bench.window.entry:type("ca")
	bench.tab()
	bench.frame()
	eq("the buffer is what was typed and nothing was completed",
		bench.window:bufferText(), "ca")
	-- Tab saved it, which is what Tab has always done in here.
	local session = { user = "admin", cwd = "/home/admin" }
	local node = CeroSecOS.getNode(bench.object:osState(), session, "/home/admin/notes.txt")
	check("Tab wrote the file", node ~= nil and node.data == "ca")
end

--
-- cron, end to end (rung 5b)
--
-- The one thing none of the other benches can prove: a machine with nobody
-- standing at it does something at the minute it was told to, and what it says
-- about it is where cron says it -- the account's mail and the log, never the
-- glass.
--

-- crontab -e through the editor, refused and then installed.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("crontab -l")
	bench.frame()
	check("no crontab yet, and Vixie's line for it", bench.painted("no crontab for admin"))

	bench.enter("crontab -e")
	bench.frame()
	eq("the editor is on the glass", bench.window.mode, "edit")
	check("on the account's own file in the spool",
		bench.painted("/var/spool/cron/admin"))
	eq("and it is empty", bench.window:bufferText(), "")

	-- A line that is not one: refused, whole, with the file, the line and the
	-- field -- and nothing is installed.
	bench.window.entry:type("60 * * * * echo hi")
	bench.tab()
	bench.frame()
	check("a bad minute is refused where it was typed",
		bench.painted("\"/var/spool/cron/admin\":1: bad minute"))
	eq("and nothing was written", bench.fileText("/var/spool/cron/admin"), "")

	-- The same line with a minute that is one.
	bench.window.entry:setText("30 * * * * echo hi")
	bench.window.entry:setCursorPos(18)
	bench.tab()
	bench.frame()
	check("a crontab that parses is installed", bench.painted("Saved 18 bytes"))
	eq("and is on the disk", bench.fileText("/var/spool/cron/admin"), "30 * * * * echo hi")

	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.enter("crontab -l")
	bench.frame()
	check("crontab -l reads it back", bench.painted("30 * * * * echo hi"))
	-- And the file is still out of the account's reach: crontab is the way in.
	bench.enter("cat /var/spool/cron/admin")
	bench.frame()
	check("the spool is nobody's to read", bench.painted("permission denied"))

	bench.enter("crontab -r")
	bench.enter("crontab -l")
	bench.frame()
	check("and -r takes it away", bench.painted("no crontab for admin"))
end

-- A line that comes due: it runs at the next minute, once, and what it printed
-- is in the mail and not on the glass.
do
	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"* * * * * echo tick", false, 100)
	bench.enter("clear")
	bench.frame()

	-- The minute the machine came into view is not a minute it was there for.
	bench.minute()
	eq("nothing ran for the minute it arrived in", bench.fileText("/var/mail/admin"), nil)

	bench.minute()
	local mail = bench.fileText("/var/mail/admin")
	check("the next minute ran it", mail ~= nil)
	check("and what it printed is in the mail", string.find(mail, "tick", 1, true) ~= nil)
	check("with the subject cron writes", string.find(mail, "Subject: Cron <admin@", 1, true) ~= nil)
	check("nothing of it reached the glass", not bench.painted("tick"))
	check("and no job was announced on it", not bench.painted("[1]"))
	-- The log has the line, and it is root's.
	local log = bench.fileText("/var/log/cron")
	check("the log says what ran", string.find(log, "(admin) CMD (echo tick)", 1, true) ~= nil)
	eq("one line in it", #CeroSecOS.splitLines(log), 1)

	-- Once per minute, and not twice: the same minute again runs nothing.
	bench.minute(1)
	eq("the next minute ran it once more", #CeroSecOS.splitLines(bench.fileText("/var/log/cron")), 2)
	local before = bench.fileText("/var/log/cron")
	local replies = {}
	bench.system.reply = function() end
	bench.system:checkCron()
	bench.system:checkCron()
	eq("and a second pass inside the same minute runs nothing",
		bench.fileText("/var/log/cron"), before)

	-- mail shows it and empties it: reading your mail is what marks it read.
	bench.enter("mail")
	bench.frame()
	check("mail puts it on the glass", bench.painted("tick"))
	bench.enter("mail")
	bench.frame()
	check("and there is none left", bench.painted("No mail for admin"))
end

-- A missed minute is a minute that is gone: nothing is caught up.
do
	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"* * * * * echo tick", false, 100)
	bench.minute()
	-- The chunk was not loaded for ten minutes: the game clock moved and nobody
	-- swept. Exactly one minute is run when the sweep comes back, and it is THIS
	-- one -- not the ten that went by.
	_G.__gameTime.minutes = _G.__gameTime.minutes + 10
	bench.minute()
	eq("one minute ran, not eleven",
		#CeroSecOS.splitLines(bench.fileText("/var/log/cron")), 1)
end

-- The four-job ceiling is the machine's, and cron does not get to lift it: a
-- line that cannot start is skipped, and the log says so in cron's own words.
do
	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"* * * * * echo tick", false, 100)
	-- Four jobs of the player's own, which is every slot the machine has. A
	-- `sleep` is the cheapest way to hold one: it spends nothing at all while it
	-- waits, and it is still a job.
	for _ = 1, CeroSecOS.MAX_JOBS do bench.enter("sleep 900 &") end
	bench.tick(2)
	eq("the machine is full", CeroSecOS.liveJobs(CeroSecJobs.book(bench.object).list),
		CeroSecOS.MAX_JOBS)

	bench.minute()
	bench.minute()
	local log = bench.fileText("/var/log/cron")
	check("cron could not start it", string.find(log, "(CRON) error (can't fork)", 1, true) ~= nil)
	check("and nothing was mailed", bench.fileText("/var/mail/admin") == nil)
	check("nor said on the glass", not bench.painted("can't fork"))
end

-- @reboot, at power-on.
do
	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"@reboot echo up", false, 100)
	-- No minute is ever due for it.
	bench.minute(3)
	eq("a minute is not a boot", bench.fileText("/var/mail/admin"), nil)

	-- The switch at the back of the case, off and on again.
	bench.object:turnOff()
	bench.object:turnOn()
	bench.tick(4)
	local mail = bench.fileText("/var/mail/admin")
	check("@reboot ran when the machine came up", mail ~= nil)
	check("and what it printed is in the mail",
		mail ~= nil and string.find(mail, "up", 1, true) ~= nil)
	local log = bench.fileText("/var/log/cron")
	check("the log has it once", #CeroSecOS.splitLines(log) == 1)
end

-- A cron line that works the building: the light is on at the next minute, and
-- nobody typed anything.
do
	local kit = mockupWorld()
	_G.__world = kit.world

	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()
	-- The office switch, off to begin with.
	kit.light0.activated = false
	-- admin is in the sudoers file, so he is in the group `sudo`, so 660 on a
	-- device is his to write -- no sudo typed, exactly as at the prompt.
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"* * * * * echo on > /dev/light0", false, 100)
	bench.minute()
	eq("the switch has not moved yet", kit.light0.activated, false)

	bench.minute()
	eq("the light came on at the next minute", kit.light0.activated, true)
	eq("and the world was told", kit.light0.syncs >= 1, true)
	check("nothing was said on the glass", not bench.painted("light0"))
	local log = bench.fileText("/var/log/cron")
	check("the log says what ran",
		string.find(log, "(admin) CMD (echo on > /dev/light0)", 1, true) ~= nil)
	-- A device write prints nothing, so there is nothing to mail.
	eq("and there was nothing to mail", bench.fileText("/var/mail/admin"), nil)
	_G.__world = nil
end

--
-- fg: the other half of "&" (rung 5b)
--

do
	local bench = newBench()
	bench.login("admin")

	-- Nothing to bring forward yet.
	bench.enter("fg")
	bench.frame()
	check("fg with no jobs says so", bench.painted("fg: no current job"))
	bench.enter("fg %9")
	bench.frame()
	check("and a slot nobody holds says so too", bench.painted("fg: %9: no such job"))

	-- A background job, announced with its slot and its id.
	bench.script("/home/admin/slow.sh", "sleep 30\necho finished\n")
	bench.enter("sh slow.sh &")
	bench.tick(2)
	bench.frame()
	check("the job was announced with its slot", bench.painted("[1] "))
	eq("and the prompt is free", bench.object.console.job, nil)
	bench.enter("jobs")
	bench.frame()
	check("jobs lists it", bench.painted("sh slow.sh"))

	-- fg brings it forward: sh prints the command line, and the prompt is the
	-- job's now.
	bench.enter("fg %1")
	bench.tick(2)
	bench.frame()
	check("fg prints the command it brought forward", bench.painted("sh slow.sh &"))
	local job = CeroSecJobs.book(bench.object).list[1]
	check("there is still one job", job ~= nil)
	eq("the prompt belongs to it now", bench.object.console.job, job.id)
	eq("and it is no longer a background job", job.bg, false)

	-- Escape is its ^C, exactly as it is for a script started in the foreground.
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	check("Escape killed it", bench.heard("^C"))
	eq("and the machine is running nothing", #CeroSecJobs.book(bench.object).list, 0)
	eq("the prompt is back", bench.object.console.job, nil)
	check("and it never said 'finished'", not bench.heard("finished"))
end

-- A job brought forward and left to finish says nothing at the end of it: "[1]
-- done" is a message to a shell that was not waiting, and this one was.
do
	local bench = newBench()
	bench.login("admin")
	-- A few seconds of sleep in front of it, so it is still there to be brought
	-- forward: a job of one echo is over before the line that started it is, and
	-- typing a line is a second of the wall clock by itself.
	bench.script("/home/admin/quick.sh", "sleep 4\necho working\n")
	bench.enter("sh quick.sh &")
	bench.tick(1)
	bench.frame()
	local job = CeroSecJobs.book(bench.object).list[1]
	check("it is running", job ~= nil and not CeroSecOS.jobIsOver(job))
	bench.enter("fg")
	bench.frame()
	check("it was brought forward", bench.object.console.job == job.id)
	bench.tick(60)
	bench.frame()
	check("what it printed is on the glass", bench.heard("working"))
	check("and nothing was said about a slot ending", not bench.heard("[1] done"))
	eq("the prompt came back", bench.object.console.job, nil)
end

-- fg by id, the way kill takes one, and a job that has already finished is not
-- one to bring forward.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/slow.sh", "sleep 30\n")
	bench.enter("sh slow.sh &")
	bench.tick(2)
	local job = CeroSecJobs.book(bench.object).list[1]
	bench.enter("fg " .. job.id)
	bench.tick(1)
	bench.frame()
	eq("an id names a job too", bench.object.console.job, job.id)
	-- And the prompt is the job's now, so there is nothing to type at: Escape is
	-- the way out of a foreground job, exactly as it is for a script started in
	-- front of you.
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.tick(2)
	bench.frame()
	eq("Escape took it away", #CeroSecJobs.book(bench.object).list, 0)
	bench.enter("fg " .. job.id)
	bench.frame()
	check("and a job that is gone is no job at all",
		bench.painted("fg: " .. job.id .. ": no such job"))
end

-- A cron job is nobody's to bring forward: the shell did not start it.
do
	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"* * * * * sleep 30", false, 100)
	bench.minute()
	bench.minute()
	local list = CeroSecJobs.book(bench.object).list
	local cron = nil
	for i = 1, #list do if list[i].mailTo ~= nil then cron = list[i] end end
	check("cron started one", cron ~= nil)
	bench.enter("jobs")
	bench.frame()
	check("jobs does not list it", not bench.painted("sleep 30"))
	bench.enter("fg")
	bench.frame()
	check("and fg will not have it", bench.painted("fg: no current job"))
	bench.enter("fg " .. cron.id)
	bench.frame()
	check("not even by its id", bench.painted("fg: " .. cron.id .. ": no such job"))
	-- ps shows it, because ps shows what the MACHINE is running.
	bench.enter("ps")
	bench.frame()
	check("ps does show it", bench.painted("sleep 30"))
end

-- A crontab line whose command will not parse, and one belonging to an account
-- that is not on the machine any more. Neither is run; both are answered where a
-- real cron answers them.
do
	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"* * * * * if true", false, 100)
	-- A crontab for somebody who is not in /etc/passwd: Vixie calls it an orphan
	-- and does not run it, and neither does this.
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/ghost",
		"* * * * * echo boo", false, 100)
	bench.minute()
	bench.minute()

	-- The one that parses as a line but not as shell: sh says what is wrong with
	-- it, in the mail, because that is where a cron job's output goes.
	local mail = bench.fileText("/var/mail/admin")
	check("the mail carries sh's own refusal", mail ~= nil and
		string.find(mail, "sh: line 1: syntax error: missing 'then'", 1, true) ~= nil)
	local log = bench.fileText("/var/log/cron")
	check("the log says the orphan was not run",
		string.find(log, "(ghost) ORPHAN (no passwd entry)", 1, true) ~= nil)
	check("and nothing of either reached the glass", not bench.painted("boo"))
	eq("the ghost got no mail", bench.fileText("/var/mail/ghost"), nil)
end

-- A line written into the spool BY HAND, as root, with a field that is not one:
-- crontab(1) would have refused it, so the daemon is what finds it -- the good
-- lines around it still run and the bad one is logged.
do
	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"* * * * * echo good\n60 * * * * echo bad", false, 100)
	bench.minute()
	bench.minute()
	local log = bench.fileText("/var/log/cron")
	check("the bad line is named, with its line and its field",
		string.find(log, "\"/var/spool/cron/admin\":2: bad minute", 1, true) ~= nil)
	check("and the good one ran", string.find(log, "CMD (echo good)", 1, true) ~= nil)
	local mail = bench.fileText("/var/mail/admin")
	check("with its output in the mail", mail ~= nil and
		string.find(mail, "good", 1, true) ~= nil)
	check("and nothing of the bad one", mail ~= nil and
		string.find(mail, "bad", 1, true) == nil)
end

--
-- 40. The network (rung 6a)
--
-- Two machines in one building and one in another, all three real
-- SCeroSecObjects on one real SCeroSecSystem, with the real link layer between
-- them. What is asserted is what a player would read on the glass.
--
-- The bench deliberately gives the machines nothing but a SQUARE and a BUILDING
-- DEF -- no IsoObject at all, exactly as SGlobalObject answers for a chunk the
-- streamer has not brought in -- and one of the three has its square taken away
-- after it has been switched on, which is the state a computer at the far end of
-- the county is in. It still answers ruptime, ping, rlogin and rcp, because the
-- server holds its disk whatever the streamer is doing (see the head of
-- SCeroSecNet.lua).
--

-- THE MAP'S ZONES, which is where a premises comes from.
--
-- A list of { name, type, x, y, w, h } a bench lays out, and getZonesAt answers the
-- ones covering a tile -- which is what zombie.iso.IsoMetaGrid.getZonesAt does
-- (proved at the bytecode level at the head of SCeroSecNet.lua). Empty is a map
-- with no zones on it, which is what every bench but the premises ones runs on.
_G.__zones = {}
local function fakeZone(z)
	return {
		getName = function() return z.name end,
		getType = function() return z.type or "ZombiesType" end,
		getX = function() return z.x end,
		getY = function() return z.y end,
		getWidth = function() return z.w end,
		getHeight = function() return z.h end,
	}
end
_G.getWorld = function()
	return { getMetaGrid = function()
		return { getZonesAt = function(_, x, y, _z)
			local hits = {}
			for i = 1, #_G.__zones do
				local z = _G.__zones[i]
				if x >= z.x and x < z.x + z.w and y >= z.y and y < z.y + z.h then
					hits[#hits + 1] = fakeZone(z)
				end
			end
			return javaList(hits)
		end }
	end }
end

local function newNet()
	CeroSecJobs.machines = {}
	local system = SCeroSecSystem:new()
	local objects = {}

	-- A building is its corner, its footprint, its area and its room count: the
	-- wire only ever wanted the corner of the BuildingDef, the premises rule wants
	-- how big the building is (a named zone is a premises only inside a building it
	-- is SMALLER than), and the debug window's premises block asks for all six
	-- (SCeroSecDebug.premises).
	--
	-- x2 IS EXCLUSIVE, which is javap on zombie.iso.BuildingDef: getW() is
	-- `getfield x2; getfield x; isub` and getH() the same on y, with no iconst_1
	-- anywhere -- so the width is x2 - x and the far corner is one PAST the last
	-- tile. The fake says bx + w for that reason.
	--
	-- getArea() is not the box: it walks `rooms` and sums RoomDef.getArea(), so it
	-- is the floor a building really has. w * h here is the box, which is the area
	-- of a rectangular building with no gaps -- close enough for a bench that only
	-- reads the number back out, and NOT the number the premises rule uses (that one
	-- derives the footprint from the corners, the way getW/getH do).
	local function buildingAt(bx, by, w, h, rooms)
		w, h, rooms = w or 10, h or 10, rooms or 3
		local def = {
			getX = function() return bx end,
			getY = function() return by end,
			getX2 = function() return bx + w end,
			getY2 = function() return by + h end,
			getArea = function() return w * h end,
			getRoomsNumber = function() return rooms end,
		}
		return { getDef = function() return def end }
	end

	local function machine(x, y, z, building)
		local object = SCeroSecObject:new(system, { x = x, y = y, z = z })
		local square = {
			getX = function() return x end,
			getY = function() return y end,
			getZ = function() return z end,
			getRoom = function() return nil end,
			getBuilding = function() return building end,
			getObjects = function() return { size = function() return 0 end } end,
		}
		object.getIsoObject = function() return nil end
		object.getSquare = function() return square end
		object.updateOnClient = function() end
		object.playSound = function() end
		object.syncSprite = function() end
		object:initNew()
		object.hasPower = function() return true end
		objects[#objects + 1] = object
		return object
	end

	system.getLuaObjectCount = function() return #objects end
	system.getLuaObjectByIndex = function(_, i) return objects[i] end
	system.getLuaObjectAt = function(_, x, y, z)
		for i = 1, #objects do
			local o = objects[i]
			if o.x == x and o.y == y and o.z == z then return o end
		end
		return nil
	end
	system.getIsoObjectAt = function() return nil end

	-- Explicit on every call, because the two waves that met here wanted different
	-- defaults: the debug benches read the size and the area back out of the office
	-- (10x10, area 100, 3 rooms), and the premises benches need the building to be
	-- strictly bigger than the zones they put inside it.
	local office = buildingAt(400, 700, 10, 10, 3)
	local shed = buildingAt(900, 120, 10, 10, 3)
	local net = { system = system, objects = objects, machine = machine,
		office = office, shed = shed, buildingAt = buildingAt }

	-- Two in the office, one in the shed down the road.
	net.here = machine(10, 10, 0, office)
	net.gate = machine(12, 10, 0, office)
	net.far = machine(60, 60, 0, shed)
	for i = 1, #objects do objects[i]:turnOn() end

	-- A window on the first one, wired the way newBench wires its own.
	local player = {
		getPlayerNum = function() return 0 end,
		getOnlineID = function() return -1 end,
		isDead = function() return false end,
		playSoundLocal = function() end,
		getCurrentSquare = function() return { getZ = function() return 0 end } end,
		getX = function() return 10.5 end,
		getY = function() return 10.5 end,
	}
	local computer = {
		getSquare = function() return { getX = function() return 10 end,
			getY = function() return 10 end, getZ = function() return 0 end } end,
		getSpriteName = function() return CeroSec.SPRITES_ON["S"] end,
	}
	local function newWindow()
		local w = CeroSecTerminal:new(0, 0, player, computer)
		w:initialise()
		w:createChildren()
		w.stillValid = function() return true end
		w.painted = {}
		w.rects = {}
		w.drawText = function(self, text, x, y)
			self.painted[#self.painted + 1] = { text = text, x = x, y = y }
		end
		w.drawRect = function() end
		return w
	end
	local window = newWindow()
	net.window = window

	net.said = {}
	local function record(a)
		if type(a) ~= "table" or type(a.lines) ~= "table" then return end
		for i = 1, #a.lines do net.said[#net.said + 1] = a.lines[i] end
	end
	CCeroSecSystem = { instance = { sendCommand = function(_, sender, command, args)
		local replies = {}
		system.reply = function(_, _, cmd, a) replies[#replies + 1] = { cmd, a }; record(a) end
		system:OnClientCommand(command, sender, args)
		for i = 1, #replies do window:onServerCommand(replies[i][1], replies[i][2]) end
	end } }

	function net.tick(times)
		for _ = 1, (times or 1) do
			_G.__now = _G.__now + CeroSec.JOB_PASS_MS
			local replies = {}
			system.reply = function(_, _, cmd, a) replies[#replies + 1] = { cmd, a }; record(a) end
			CeroSecJobs.tick()
			for i = 1, #replies do window:onServerCommand(replies[i][1], replies[i][2]) end
		end
		net.frame()
	end

	function net.frame()
		window.painted = {}
		window:prerender()
		window:render()
	end

	-- A window the client has SHUT takes no more keys. The game has it off the UI
	-- manager and the machine has its watcher off the book, so every screen the
	-- server pushes afterwards goes nowhere and the glass stands exactly as it
	-- stood -- which a bench that kept typing at it would read as an answer. That
	-- is how "Escape at an idle prompt breaks the next rlogin" was reported: the
	-- window was gone, and the still glass was mistaken for a stale one. So the
	-- keyboard helpers refuse, and net.reopen is the way back.
	local function atTheKeyboard()
		if window.closing then
			error("the window was closed -- net.reopen() is the way back to a glass", 3)
		end
	end

	function net.enter(line)
		atTheKeyboard()
		_G.__now = _G.__now + 1000
		window.entry:setText(line or "")
		window.entry:setCursorPos(#(line or ""))
		window:onCommandEntered()
		net.frame()
	end

	function net.escape()
		atTheKeyboard()
		_G.__now = _G.__now + 100
		window:onOtherKey(Keyboard.KEY_ESCAPE)
		net.frame()
	end

	-- The window closed and opened again on the same computer, which is the only
	-- way back to a glass Escape shut. A NEW window with a token of its own:
	-- everything the machine holds -- the screen, the session, the shell's
	-- variables -- is still there, and everything the window held is gone. The
	-- same shape as bench.reopen, which the benches above the wire use.
	function net.reopen()
		if not window.closing then window:close() end
		window = newWindow()
		net.window = window
		window:askForScreen()
		_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
		net.frame()
		return window
	end

	-- How many windows the machine is still pushing screens to. Escape at an idle
	-- prompt shuts a window, and a shut window that kept its watcher would have
	-- the machine talking to a glass nobody is in front of.
	function net.watchers(object)
		local watchers = (object or net.here).watchers
		if watchers == nil then return 0 end
		local n = 0
		for _ in pairs(watchers) do n = n + 1 end
		return n
	end

	-- The BOTTOM of the glass: what the machine is asking for NOW. A session that
	-- has been and gone leaves its prompt in the scrollback for good, so "is the
	-- far prompt anywhere on the glass" is not the question a bench about a NEW
	-- session may ask -- net.glass would answer yes to yesterday's.
	function net.bottom()
		for i = #window.painted, 1, -1 do
			local text = window.painted[i].text
			if type(text) == "string" and text ~= "" then return text end
		end
		return ""
	end

	function net.glass(needle)
		for i = 1, #window.painted do
			local text = window.painted[i].text
			if type(text) == "string" and string.find(text, needle, 1, true) then return true end
		end
		return false
	end

	function net.heard(needle)
		for i = 1, #net.said do
			if string.find(net.said[i], needle, 1, true) then return true end
		end
		return false
	end

	-- Forget every line said so far. A screen is a hundred lines and a bench that
	-- asks "was this never said" has to ask it of one command and not of the whole
	-- session before it.
	function net.forget()
		net.said = {}
	end

	function net.login(name, password)
		window:askForScreen()
		_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
		net.frame()
		net.enter(name)
		net.enter(password or "")
	end

	-- Write a file on any of the three, as root, the way the editor would.
	function net.put(object, path, text, mode, owner)
		local state = object:osState()
		local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(), path,
			text, false, 100)
		if done == nil then error("cannot write " .. path .. ": " .. tostring(reason), 2) end
		local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), path)
		if mode ~= nil then node.mode = mode end
		if owner ~= nil then node.owner = owner end
		return node
	end

	function net.text(object, path)
		local node = CeroSecOS.systemNode(object:osState(), path)
		if type(node) ~= "table" or node.type ~= "file" then return nil end
		return node.data or ""
	end

	function net.addr(object)
		return CeroSecOS.address(object:osState())
	end

	function net.host(object)
		return CeroSecOS.hostname(object:osState())
	end

	-- Name the other two in this machine's /etc/hosts, which is the only resolver
	-- there is: a survivor who has not written a line cannot say "gate".
	function net.name(object, other, as)
		local state = object:osState()
		local node = CeroSecOS.systemNode(state, CeroSecOS.HOSTS_PATH)
		CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
			(node.data or "") .. "\n" .. net.addr(other) .. " " .. as, 100)
	end

	-- A minute of the world's clock, which is what cron keeps its time by, plus
	-- the passes the job cron makes needs to actually run. The same shape as
	-- newBench's own minute, because a crontab on a machine with a wire in it is
	-- still a crontab.
	-- The minute itself, with no passes behind it: a bench that wants to look at
	-- the machine BETWEEN the passes cron's job needs has to be able to take them
	-- one at a time.
	function net.cron()
		local clock = _G.__gameTime
		clock.minutes = clock.minutes + 1
		if clock.minutes >= 60 then
			clock.minutes = 0
			clock.hour = clock.hour + 1
			if clock.hour >= 24 then
				clock.hour = 0
				clock.day = clock.day + 1
			end
		end
		local replies = {}
		system.reply = function(_, _, cmd, a) replies[#replies + 1] = { cmd, a }; record(a) end
		system:checkPower()
		system:checkCron()
		for i = 1, #replies do window:onServerCommand(replies[i][1], replies[i][2]) end
	end

	function net.minute(times)
		for _ = 1, (times or 1) do
			net.cron()
			net.tick(4)
		end
	end

	-- A crontab for an account on any of the three, written where crontab(1)
	-- writes it.
	function net.crontab(object, user, text)
		local state = object:osState()
		local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(),
			"/var/spool/cron/" .. user, text, false, 100)
		if done == nil then error("cannot write crontab: " .. tostring(reason), 2) end
	end

	-- The other two machines know THIS one by name, and that is a line of THEIR
	-- /etc/hosts. It has to be: a name in a trust file is matched against the
	-- caller's address through the file of the machine being ASKED
	-- (CeroSecOS.trustWords), never against the name the caller announces -- so a
	-- bench that writes this machine's name into a trust file over there needs the
	-- far machine to be able to resolve it, which is the first job the manual gives
	-- an administrator. Written here so that those benches are about TRUST.
	--
	-- This machine's own /etc/hosts is left exactly as the machine wrote it: one
	-- line, its own. The benches about the resolver -- arp, ping, and what `who`
	-- prints about a caller nobody has written down -- depend on that.
	net.name(net.gate, net.here, net.host(net.here))
	net.name(net.far, net.here, net.host(net.here))

	return net
end

--
-- Identity: an address per machine, the same three numbers for one building.
--

do
	local net = newNet()
	local a, b, c = net.addr(net.here), net.addr(net.gate), net.addr(net.far)
	check("every machine has an address", a ~= nil and b ~= nil and c ~= nil)
	check("and it is on the ten network", string.sub(a, 1, 3) == "10.")
	-- The first three numbers are the building's and the last is the machine's.
	local netA = string.match(a, "^(%d+%.%d+%.%d+)%.%d+$")
	local netB = string.match(b, "^(%d+%.%d+%.%d+)%.%d+$")
	local netC = string.match(c, "^(%d+%.%d+%.%d+)%.%d+$")
	eq("two machines in one building share a network", netB, netA)
	check("a machine in another building does not", netC ~= netA)
	check("and the two in one building are two machines", a ~= b)
	eq("the first is .1", a, netA .. ".1")
	eq("the second is .2", b, netA .. ".2")

	-- Derived from where the building stands, so it is the same answer twice.
	local b1, b2 = CeroSecOS.buildingKey(400, 700)
	eq("the address is the building's key and the machine's number",
		a, CeroSecOS.addressText(b1, b2, 1))

	-- And the machine wrote itself one line of /etc/hosts and no more.
	local hosts = net.text(net.here, "/etc/hosts")
	check("the machine's own line is in /etc/hosts",
		string.find(hosts, a .. " " .. net.host(net.here), 1, true) ~= nil)
	check("and so is the loopback",
		string.find(hosts, "127.0.0.1 localhost", 1, true) ~= nil)
	-- Asked again, nothing moves: the file is the player's from here on.
	CeroSecNet.identify(net.system, net.here, net.here:osState())
	eq("identify twice writes nothing twice", net.text(net.here, "/etc/hosts"), hosts)
end

--
-- ifconfig, and the BIOS line
--

do
	local net = newNet()
	net.login("admin")
	check("the BIOS announced the card", net.heard("Ethernet: eth0 " .. net.addr(net.here)))

	net.enter("ifconfig")
	check("ifconfig names eth0", net.glass("eth0: flags=63<UP,BROADCAST,NOTRAILERS,RUNNING>"))
	check("with the address on it", net.glass("inet " .. net.addr(net.here)
		.. " netmask 0xffffff00"))
	check("and the loopback under it", net.glass("lo0: flags=8<LOOPBACK>"))
	net.enter("ifconfig eth9")
	check("a card that is not there", net.glass("ifconfig: interface eth9 does not exist"))
end

-- A computer in no building has no wire, and says so rather than inventing one.
do
	local net = newNet()
	local loose = net.machine(80, 80, 0, nil)
	loose:turnOn()
	eq("a machine in no building has no address", CeroSecOS.address(loose:osState()), nil)
	local ok, lines = CeroSecOS.runArgs(loose:osState(),
		{ user = "root", cwd = "/root" }, { "ifconfig" }, nil, { now = 0 })
	eq("ifconfig says the card is down", lines[1], "eth0: flags=2<BROADCAST>")
	check("and prints no inet line for it",
		string.find(lines[2], "lo0", 1, true) ~= nil)
end

--
-- ruptime and rwho
--

do
	local net = newNet()
	net.login("admin")
	-- Somebody logged in on gate as well, so the counts are two different
	-- numbers rather than the same one twice.
	local gateConsole = net.gate:consoleState()
	gateConsole.user = "root"
	gateConsole.cwd = "/root"
	gateConsole.loginAt = 100

	_G.__now = _G.__now + 65000
	net.enter("ruptime")
	local host = net.host(net.here)
	local gate = net.host(net.gate)
	check("this machine is on the list", net.glass(host))
	check("and so is the other one in the building", net.glass(gate))
	check("with one user on it", net.glass("1 user,"))
	check("the machine down the road is not", not net.glass(net.host(net.far)))
	check("and the load is printed the way ruptime prints it", net.glass("load 0.00"))

	net.enter("rwho")
	check("rwho names the account and where it is sitting",
		net.glass("root") and net.glass(gate .. ":console"))
	check("and the one at this keyboard", net.glass("admin"))
end

--
-- ping
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.name(net.here, net.far, "shed")
	net.login("admin")

	net.enter("ping gate")
	check("ping names what it is pinging",
		net.heard("PING gate (" .. net.addr(net.gate) .. "): 56 data bytes"))
	check("the first packet answered",
		net.heard("64 bytes from " .. net.addr(net.gate) .. ": icmp_seq=0 ttl=255 time=0.4 ms"))
	-- The other two are a second apart, so the job is asleep in between.
	check("nothing of the second packet yet", not net.heard("icmp_seq=1"))
	net.tick(4)
	check("still asleep after four passes", not net.heard("icmp_seq=1"))
	net.tick(12)
	check("the second packet came round", net.heard("icmp_seq=1"))
	net.tick(12)
	check("and the third", net.heard("icmp_seq=2"))
	check("with the statistics behind it", net.heard("--- gate ping statistics ---"))
	check("three out of three", net.heard("3 packets transmitted, 3 packets received, 0% packet loss"))
	check("and a round trip", net.heard("round-trip min/avg/max = 0.4/0.4/0.4 ms"))

	-- A name nothing carries is refused before a packet is sent.
	net.enter("ping pump")
	check("an unknown name is ping's own refusal", net.glass("ping: unknown host pump"))
end

-- A machine nothing can reach, on a bench where no packet has ever arrived: the
-- screen is a hundred lines and every push carries all of them, so "this was
-- never said" is only a true question of a session that has not said it yet.
do
	local net = newNet()
	net.name(net.here, net.far, "shed")
	net.login("admin")
	net.enter("ping shed")
	net.tick(30)
	check("the machine down the road never answers", not net.heard("bytes from"))
	check("and the summary says so",
		net.heard("3 packets transmitted, 0 packets received, 100% packet loss"))
	check("with no round trip on it", not net.heard("min/avg/max"))
end

-- A switched-off machine on the same wire is a machine that answers nothing.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.login("admin")
	net.gate:turnOff()
	net.enter("ping gate")
	net.tick(30)
	check("a dark machine answers nothing", not net.heard("bytes from"))
	check("and the loss is total",
		net.heard("3 packets transmitted, 0 packets received, 100% packet loss"))
end

--
-- rlogin: with a password, with a trust file, and refused
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(2)
	check("the far machine asks who is there", net.glass("login:"))
	eq("and the window is drawing the far machine's screen", net.window.mode, "prompt")
	net.enter("admin")
	net.enter("")
	net.tick(2)
	local gate = net.host(net.gate)
	check("the prompt is the far machine's", net.glass("admin@" .. gate))

	-- Every line typed is the far machine's now.
	net.enter("hostname")
	net.tick(2)
	check("hostname answers with the far machine's name", net.glass(gate))
	net.enter("pwd")
	net.tick(2)
	check("and pwd with the far machine's home", net.glass("/home/admin"))

	-- Who is logged in over there, and where he came from.
	net.enter("who")
	net.tick(2)
	check("who names the pty", net.glass("ttyp0"))
	check("and the machine the session came from", net.glass("(" .. net.host(net.here) .. ")"))

	-- The local machine's history kept the rlogin line and nothing typed over
	-- there; the far machine's history kept what was typed on it.
	local here = net.text(net.here, "/home/admin/.sh_history")
	check("the local history has the rlogin line",
		string.find(here, "rlogin gate", 1, true) ~= nil)
	check("and not what was typed on the far machine",
		string.find(here, "hostname", 1, true) == nil)
	local there = net.text(net.gate, "/home/admin/.sh_history")
	check("the far machine's history has it", there ~= nil and
		string.find(there, "hostname", 1, true) ~= nil)

	-- exit ends the session and the glass comes back.
	net.forget()
	net.enter("exit")
	net.tick(3)
	check("the session says it is over", net.heard("Connection closed."))
	check("and the local prompt is back", net.glass("admin@" .. net.host(net.here)))
	eq("the far machine has no pty left", CeroSecOS.ptyCount(net.gate.ptys), 0)
	check("and the local console is looking at nothing",
		net.here:consoleState().remote == nil)
end

-- A wrong password is one answer and no session.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/nothing", "x")
	local state = net.gate:osState()
	CeroSecOS.setPassword(state, "admin", "hunter2", 1, 100)
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(2)
	net.enter("admin")
	net.enter("wrong")
	net.tick(2)
	check("the far machine refuses", net.heard("login incorrect"))
	check("and asks again", net.glass("login:"))
	eq("the pty is still open while it asks", CeroSecOS.ptyCount(net.gate.ptys), 1)
	-- A remote login prompt with nothing typed at it is not the machine being in
	-- the middle of something, so Escape there is what closes the connection.
	net.escape()
	net.tick(3)
	eq("Escape closed the session", CeroSecOS.ptyCount(net.gate.ptys), 0)
	check("and the local prompt is back", net.glass("admin@" .. net.host(net.here)))
end

-- ~/.rhosts, and the two ways it is ignored.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	local from = net.host(net.here)
	-- Owned by somebody else: ignored without a word.
	net.put(net.gate, "/home/admin/.rhosts", from .. " admin", 600, "bob")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(2)
	check("a .rhosts that is not the account's own is ignored", net.glass("login:"))
	net.escape()
	net.tick(3)

	-- The account's own, but the world may write it: ignored as well.
	net.put(net.gate, "/home/admin/.rhosts", from .. " admin", 666, "admin")
	net.enter("rlogin gate")
	net.tick(2)
	check("nor is one anybody may write", net.glass("login:"))
	net.escape()
	net.tick(3)

	-- And now properly: 600, owned by admin.
	net.put(net.gate, "/home/admin/.rhosts", from .. " admin", 600, "admin")
	net.enter("rlogin gate")
	net.tick(3)
	check("a trusted login is asked for no password",
		net.glass("admin@" .. net.host(net.gate)))
	check("and is logged in", net.gate.ptys.ttyp0.console.user == "admin")
	-- wtmp on the far machine says who came in and from where.
	local wtmp = net.text(net.gate, "/var/log/wtmp")
	check("the far machine's wtmp has the login",
		string.find(wtmp, "in admin ttyp0 " .. from, 1, true) ~= nil)
	net.enter("exit")
	net.tick(3)
	check("and the logout behind it",
		string.find(net.text(net.gate, "/var/log/wtmp"), "out admin ttyp0 " .. from,
			1, true) ~= nil)
end

-- rlogin -l, and a .rhosts that names the account coming in.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	-- bob exists over there, with a home and a .rhosts of his own naming the
	-- account that will be asking.
	local far = net.gate:osState()
	CeroSecOS.addUser(far, "bob", "/home/bob", false, 1, 100)
	CeroSecOS.createNode(far, CeroSecOS.rootSession(), "/home/bob",
		CeroSecOS.newDir("bob", CeroSecOS.HOME_MODE), 100)
	net.put(net.gate, "/home/bob/.rhosts", net.host(net.here) .. " admin", 600, "bob")
	net.login("admin")
	net.enter("rlogin gate -l bob")
	net.tick(3)
	check("admin is let in as bob with no password",
		net.glass("bob@" .. net.host(net.gate)))
	eq("and the session is his", net.gate.ptys.ttyp0.console.user, "bob")
	net.enter("whoami")
	net.tick(2)
	check("whoami says so", net.glass("bob"))
	net.enter("exit")
	net.tick(3)

	-- And a line naming somebody else is not a line about admin.
	net.put(net.gate, "/home/bob/.rhosts", net.host(net.here) .. " kate", 600, "bob")
	net.enter("rlogin gate -l bob")
	net.tick(3)
	check("a line naming another account asks for a password", net.glass("login:"))
	net.escape()
	net.tick(3)
end

-- /etc/hosts.equiv is the machine's own half of the same question.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(3)
	check("a bare host name trusts the same account on it",
		net.glass("admin@" .. net.host(net.gate)))
	-- And it never trusts root, which is ruserok's own rule.
	eq("hosts.equiv does not let root in",
		CeroSecOS.equivOk(net.gate:osState(), net.host(net.here), "root", "root"), false)
end

--
-- 40b. Naming a neighbour, end to end (rung 6d)
--
-- The gap a survivor actually falls into: ruptime lists a machine by the name it
-- broadcasts, `ping <that name>` says unknown host, and until there was an arp
-- there was nothing on the disk that told him the ADDRESS to write down. The whole
-- repair, typed on the glass and nowhere else.
--
do
	local net = newNet()
	net.login("root")
	local gate = net.host(net.gate)
	local addr = net.addr(net.gate)

	net.enter("ruptime")
	check("ruptime lists the other machine by the name it broadcasts", net.glass(gate))
	net.enter("ping " .. gate)
	check("and nothing on this machine resolves that name",
		net.glass("ping: unknown host " .. gate))

	net.enter("arp -a")
	check("arp has the address, with no name for it",
		net.glass("? (" .. addr .. ") at " .. CeroSecOS.etherOf(addr)))
	check("and this machine is not in its own cache",
		not net.glass("(" .. net.addr(net.here) .. ")"))

	-- The line, written by hand, which is what the manual tells him to do.
	net.enter('echo "' .. addr .. ' gate" >> /etc/hosts')
	net.enter("arp -a")
	check("now arp names it", net.glass("gate (" .. addr .. ") at "))
	net.enter("ping gate")
	check("and ping reaches it", net.heard("PING gate (" .. addr .. "): 56 data bytes"))
	net.tick(30)
	check("all three packets came back",
		net.heard("3 packets transmitted, 3 packets received, 0% packet loss"))

	-- And the address needs no line at all: rlogin takes one straight.
	net.enter("rlogin " .. addr)
	net.tick(2)
	check("rlogin by address opens a session", net.glass("login:"))
	net.escape()
	net.tick(3)
end

--
-- 40c. A machine cannot name itself into trust
--
-- /etc/hostname is a file the machine's OWN root may write to anything, and
-- ruptime broadcasts what it says. If a trust line were matched against that name,
-- anybody with root on any computer in the building could type `hostname gate` and
-- walk in through a line somebody wrote about gate. The line is matched against the
-- caller's ADDRESS through the far machine's own /etc/hosts instead, and this is
-- the bench that says so.
--
do
	local net = newNet()
	-- gate trusts whatever ITS /etc/hosts calls "pump", and names nothing pump.
	net.put(net.gate, "/etc/hosts.equiv", "pump", 644, "root")
	net.name(net.here, net.gate, "gate")
	local was = net.host(net.here)

	-- This machine renames itself pump. Root's own file, root's own right.
	net.put(net.here, "/etc/hostname", "pump", 644, "root")
	eq("the machine now calls itself pump", net.host(net.here), "pump")

	net.login("admin")
	net.enter("rlogin gate")
	net.tick(3)
	check("the far machine asks for a password anyway", net.glass("login:"))
	eq("and nobody is logged in on the line",
		net.gate.ptys.ttyp0.console.user, nil)
	-- What the far machine calls the session is what ITS file says, which is the
	-- name this machine used to announce -- and never the one it announces now.
	net.enter("admin")
	net.enter("")
	net.tick(2)
	net.enter("who")
	net.tick(2)
	check("who names the caller off the far machine's own /etc/hosts",
		net.glass("(" .. was .. ")"))
	check("and not the name the caller announces", not net.glass("(pump)"))
	net.enter("exit")
	net.tick(3)

	-- Write the line gate was missing and the same trust file lets him in.
	net.name(net.gate, net.here, "pump")
	net.enter("rlogin gate")
	net.tick(3)
	check("a name the far machine's /etc/hosts resolves is the caller",
		net.glass("admin@" .. net.host(net.gate)))
	net.enter("exit")
	net.tick(3)
end

--
-- 40d. A caller nobody has written down is named by its address
--
-- rlogind's own reverse lookup, and the honest answer when it finds nothing: the
-- dotted quad, in who's brackets, in last's host column and in wtmp. A trust line
-- may carry the same quad, which is the one spelling of a machine that nothing on
-- the far end has to be told.
--
do
	local net = newNet()
	-- gate forgets this machine's name, and trusts its ADDRESS instead.
	net.put(net.gate, "/etc/hosts", "127.0.0.1 localhost", 644, "root")
	net.put(net.gate, "/etc/hosts.equiv", net.addr(net.here), 644, "root")
	net.name(net.here, net.gate, "gate")
	net.login("admin")

	net.enter("rlogin gate")
	net.tick(3)
	check("an address in hosts.equiv trusts the machine at it",
		net.glass("admin@" .. net.host(net.gate)))
	net.enter("who")
	net.tick(2)
	check("who names the session by the address", net.glass("(" .. net.addr(net.here) .. ")"))
	net.enter("last")
	net.tick(2)
	check("and last has it in the host column", net.glass(net.addr(net.here)))
	net.enter("exit")
	net.tick(3)
	local wtmp = net.text(net.gate, "/var/log/wtmp")
	check("wtmp recorded the address as the origin",
		string.find(wtmp, "in admin ttyp0 " .. net.addr(net.here), 1, true) ~= nil)
	check("and the logout behind it",
		string.find(wtmp, "out admin ttyp0 " .. net.addr(net.here), 1, true) ~= nil)
end

--
-- last
--

do
	local net = newNet()
	net.login("admin")
	net.enter("last")
	check("last names the account at the keyboard", net.glass("admin"))
	check("on the console", net.glass("console"))
	check("and says he is still there", net.glass("still logged in"))
	check("with the file's own beginning under it", net.glass("wtmp begins"))
	net.enter("exit")
	net.tick(2)
	net.login("admin")
	net.enter("last")
	check("a session that ended carries how long it lasted", net.glass(" - "))
end

--
-- rsh
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.login("admin")

	-- No trust, no password, no command.
	net.enter("rsh gate hostname")
	net.tick(3)
	check("rsh never asks and never runs without trust",
		net.glass("rsh: gate: Permission denied"))
	eq("and took no line on the far machine", CeroSecOS.ptyCount(net.gate.ptys), 0)

	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.forget()
	net.enter("rsh gate hostname")
	net.tick(4)
	check("with trust it runs and the answer comes back", net.heard(net.host(net.gate)))
	check("and says nothing about a connection", not net.heard("Connection closed."))
	net.tick(4)
	eq("the session closed when the command was done",
		CeroSecOS.ptyCount(net.gate.ptys), 0)
	check("and the local prompt is back", net.glass("admin@" .. net.host(net.here)))
end

--
-- rlogin wants a terminal
--
-- The hole this section closes: a crontab line is a job with NOBODY in front of
-- it, and the console the scheduler hands its orders to is the machine's OWN
-- glass. So `* * * * * rlogin gate` used to dial out and land the session on the
-- physical screen -- a survivor walking up to the machine found himself logged
-- into another computer with nothing to say how he got there, and a `&` behind
-- the line did the same. 4.4BSD's rlogin opens a terminal on the far end and
-- needs one on this end to hand it: no terminal, no session.
--
-- The rule, four ways of having no terminal: a cron line, a `&`, a `$(...)` and
-- a stage of a pipeline. A script run from the prompt in the FOREGROUND keeps
-- the terminal it was started from, which is what real Unix does and is the
-- whole reason an operator's `./nightly.sh` still works.
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	-- gate trusts here, so a session that got through would need no password:
	-- the worst case, which is the one worth asserting.
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")

	-- 1. From cron.
	net.crontab(net.here, "admin", "* * * * * rlogin gate")
	net.minute(2)
	eq("a crontab rlogin opens no line on the far machine",
		CeroSecOS.ptyCount(net.gate.ptys), 0)
	eq("and the glass in front of the survivor is still his own",
		net.here.console.remote, nil)
	local log = net.text(net.here, "/var/log/cron")
	check("cron ran the line", log ~= nil and
		string.find(log, "CMD (rlogin gate)", 1, true) ~= nil)
	local mail = net.text(net.here, "/var/mail/admin")
	check("and what it said went in the mail, in rlogin's own words",
		mail ~= nil and string.find(mail, "rlogin: not a terminal", 1, true) ~= nil)
	check("nothing of it reached the glass", not net.glass("not a terminal"))

	-- Never, however many minutes go by: a crontab is not a thing that gets
	-- through on the tenth try.
	net.crontab(net.here, "admin", "")
	net.minute(4)
	eq("still no line on the far machine", CeroSecOS.ptyCount(net.gate.ptys), 0)
	eq("and still his own glass", net.here.console.remote, nil)

	-- 2. In the background.
	net.forget()
	net.enter("rlogin gate &")
	net.tick(6)
	check("a backgrounded rlogin says it has no terminal",
		net.heard("rlogin: not a terminal"))
	eq("and takes no line", CeroSecOS.ptyCount(net.gate.ptys), 0)
	eq("the glass is the survivor's", net.here.console.remote, nil)

	-- 3. Inside a substitution, which is a subshell whose output is a pipe: there
	-- is nowhere for a session to go. The refusal lands IN the substitution,
	-- because this machine has one channel and a capture catches what a command
	-- says whether it went right or wrong (CeroSecOSVM, errLine) -- the same
	-- answer `$(ls /nope)` gives. What matters is the line it did not take.
	net.forget()
	net.enter("x=$(rlogin gate); echo [$x]")
	net.tick(6)
	check("a substitution gets the same answer",
		net.heard("[rlogin: not a terminal]"))
	eq("and takes no line", CeroSecOS.ptyCount(net.gate.ptys), 0)
	eq("the glass is the survivor's", net.here.console.remote, nil)

	-- 4. A stage of a pipeline.
	net.forget()
	net.enter("rlogin gate | cat")
	net.tick(6)
	check("a pipeline stage gets the same answer", net.heard("rlogin: not a terminal"))
	eq("and takes no line", CeroSecOS.ptyCount(net.gate.ptys), 0)
	eq("the glass is still the survivor's", net.here.console.remote, nil)
end

--
-- A script in the foreground keeps the terminal it was started from
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")

	net.put(net.here, "/home/admin/go.sh", "rlogin gate", 755, "admin")
	net.enter("./go.sh")
	net.tick(6)
	check("the session opened", net.glass("admin@" .. net.host(net.gate)))
	eq("and the far machine has a line", CeroSecOS.ptyCount(net.gate.ptys), 1)
	check("no refusal was printed", not net.heard("not a terminal"))
end

--
-- rsh needs no terminal, and never takes one
--
-- Real rsh runs without a terminal: it is one command and a pipe back, which is
-- the whole reason it is what a crontab calls. What it may never do is what
-- rlogin may never do either -- put a session on a screen nobody asked. So a
-- crontab's rsh runs, and what comes back is MAIL.
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")

	-- A command with a `sleep` in front of it, deliberately: everything else an
	-- rsh runs is over inside the one pass that opened the session, and a session
	-- that never outlives a pass is a session no assertion between passes can
	-- look at. This one holds its line on the far machine for a second.
	net.crontab(net.here, "admin", "* * * * * rsh gate \"sleep 1; hostname\"")

	-- Watched after EVERY pass and not once at the end: the teardown puts `remote`
	-- back to nil either way, so an assertion made afterwards cannot tell a glass
	-- that was never taken from a glass that was taken and given back -- and one
	-- pass is long enough for the survivor's window to have been told.
	local taken, opened = false, false
	for _ = 1, 2 do
		net.cron()
		for _ = 1, 24 do
			net.tick(1)
			if net.here.console.remote ~= nil then taken = true end
			if CeroSecOS.ptyCount(net.gate.ptys) > 0 then opened = true end
		end
	end
	-- The witness is not an empty one: the rsh really did run inside the passes
	-- that were watched, which is what makes `taken` false worth anything.
	eq("the line on the far machine was taken while the glass was watched",
		opened, true)
	eq("and the survivor's glass was never pointed at it", taken, false)

	local mail = net.text(net.here, "/var/mail/admin")
	check("the far machine's answer came back in the mail",
		mail ~= nil and string.find(mail, net.host(net.gate), 1, true) ~= nil)
	-- And nothing else the session did: what an rsh hands back is the command's
	-- output. rshd prints no greeting -- that is login's job -- and a motd in
	-- somebody's mail every minute is a line the command never wrote.
	check("with no greeting in it",
		mail ~= nil and string.find(mail, "unauthorized access", 1, true) == nil)
	eq("the line was given back when the command was done",
		CeroSecOS.ptyCount(net.gate.ptys), 0)
	check("and nothing of it was painted", not net.glass(net.host(net.gate)))
	check("nor ever said to a window", not net.heard(net.host(net.gate)))
end

--
-- rsh WAITS, and what comes back goes where the job was writing
--
-- rsh is one command and a pipe back, and the pipe back is the point: the job
-- that gave the order is PARKED while the far machine runs the command, and what
-- the far command printed arrives in that job's own output stream -- the glass for
-- a line typed at the prompt, the pipe for a stage, the word for a $(...), the
-- mail for a cron line -- with the far command's status in $?. Then the job runs
-- on.
--
-- Before this an rsh ENDED the job that gave it, which made `rsh gate date` the
-- last thing any script ever did and `rsh gate hostname | wc -l` answer 0. What
-- it still may not do is hand the glass over: the session is for the command's
-- output and not for a pair of hands.
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")

	net.forget()
	net.enter("rsh gate hostname &")
	net.tick(10)
	check("a backgrounded rsh runs and the answer reaches the glass",
		net.glass(net.host(net.gate)))
	eq("and the glass was never pointed at the far machine",
		net.here.console.remote, nil)
	eq("the line was given back", CeroSecOS.ptyCount(net.gate.ptys), 0)
end

-- In a pipeline: the stage behind it reads the far machine's lines, which is
-- what a real rsh has always fed.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")

	net.forget()
	net.enter("rsh gate hostname | wc -l")
	net.tick(10)
	-- One line, which is the whole assertion about what an rsh hands back: the far
	-- machine's greeting is not in it (rshd prints none -- that is login's job),
	-- and neither is anything else the session did. A motd down the pipe would
	-- make this two.
	check("the stage behind it counted the line it was fed", net.glass("     1"))
	check("and the line itself went down the pipe and not onto the glass",
		not net.glass(net.host(net.gate)))
	eq("nothing was taken over", net.here.console.remote, nil)
	eq("and no line was left open", CeroSecOS.ptyCount(net.gate.ptys), 0)
end

-- In a $(...), and in a script that goes on afterwards with the far command's
-- own status in $?.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")

	net.forget()
	net.enter("x=$(rsh gate hostname); echo [$x] $?")
	net.tick(10)
	check("the word is what the far machine printed",
		net.glass("[" .. net.host(net.gate) .. "] 0"))

	net.put(net.here, "/home/admin/two.sh",
		"rsh gate hostname\necho \"after $?\"\nrsh gate false\necho \"then $?\"\n",
		755, "admin")
	net.forget()
	net.enter("./two.sh")
	net.tick(16)
	check("a script goes on to its next line", net.glass("after 0"))
	check("with the far command's status in $?, whatever it was",
		net.glass("then 1"))
	eq("and both lines were given back", CeroSecOS.ptyCount(net.gate.ptys), 0)

	-- And into a file, which is the fourth door the same lines can go through.
	-- The file was opened when the order was given, the way a shell opens it, and
	-- what lands in it is what the far machine printed.
	net.forget()
	net.enter("rsh gate hostname > kept.txt")
	net.tick(10)
	eq("the file holds the far machine's answer",
		net.text(net.here, "/home/admin/kept.txt"), net.host(net.gate))

	-- rcp was in the same trap next door, for a plainer reason: a redirect on a
	-- command that hands back an ORDER used to drop the order's data on the way
	-- out of runArgs, so `rcp ... > out` became a wait with nothing to wait on and
	-- the job ended there. It waits for the wire and goes on.
	net.forget()
	net.enter("rcp kept.txt gate:/home/admin/copy.txt > log.txt; echo \"copied $?\"")
	net.tick(12)
	check("the copy said how it went", net.glass("copied 0"))
	eq("and the far machine has the file",
		net.text(net.gate, "/home/admin/copy.txt"), net.host(net.gate))
end

-- A machine that will not have us: the refusal comes back into the job that is
-- waiting, as a refusal and not as output, and the script goes on from it.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.login("admin")

	net.put(net.here, "/home/admin/try.sh",
		"rsh gate hostname | wc -l\necho \"piped $?\"\n" ..
		"rsh gate hostname\necho \"alone $?\"\n", 755, "admin")
	net.forget()
	net.enter("./try.sh")
	net.tick(16)
	check("rshd's own word for a machine that does not trust this one",
		net.glass("rsh: gate: Permission denied"))
	check("the refusal did not go down the pipe: the stage read nothing",
		net.glass("     0"))
	-- A pipeline's status is its LAST stage's, which is `wc` and which worked --
	-- POSIX, and nothing to do with the rsh in front of it. The rsh's own status
	-- is the line after it: 1, which is what rsh answers for a connection it
	-- could not make.
	check("the script went on past the pipeline", net.glass("piped 0"))
	check("and past the rsh, with rsh's own status", net.glass("alone 1"))
	eq("no line was taken on the far machine", CeroSecOS.ptyCount(net.gate.ptys), 0)
end

-- A remote command that never ends holds the job here, at no cost, until Escape
-- -- and Escape takes the far session down with it.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")

	net.forget()
	net.enter("rsh gate \"while true; do x=1; done\" &")
	net.tick(4)
	local job = nil
	local list = CeroSecJobs.book(net.here).list
	for i = 1, #list do
		if not list[i].interactive then job = list[i] end
	end
	check("the job is on the machine", job ~= nil)
	eq("waiting for the far machine and nothing else", job.state, "waiting")
	eq("with a word of its own", CeroSecOS.jobWord(job), "remote")
	eq("one line out there", CeroSecOS.ptyCount(net.gate.ptys), 1)

	net.enter("jobs")
	net.tick(2)
	check("`jobs` says so", net.glass("[1] remote"))

	local spent = job.steps
	net.tick(10)
	eq("the wait costs nothing at all", job.steps, spent)
	eq("and it is the far machine that is busy", CeroSecOS.ptyCount(net.gate.ptys), 1)

	net.enter("kill %1")
	net.tick(4)
	check("kill ends it", CeroSecOS.jobIsOver(job))
	eq("and the far session goes with it", CeroSecOS.ptyCount(net.gate.ptys), 0)
	check("the far machine is running nothing",
		net.gate.jobs == nil or #net.gate.jobs.list == 0)
end

-- And the other way a near end goes away: the machine it was waiting on is
-- switched off. A machine that has stopped is not waiting for anything, so the
-- line it was holding over there is given back.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")

	net.enter("rsh gate \"while true; do x=1; done\" &")
	net.tick(4)
	eq("a line is open out there", CeroSecOS.ptyCount(net.gate.ptys), 1)

	net.here:turnOff()
	eq("the switch at the back gives it back", CeroSecOS.ptyCount(net.gate.ptys), 0)
	-- The far job is killed with the line, and what is left of it on the far
	-- machine's book is a job that is over, waiting to be reaped like any other.
	local running = 0
	local list = net.gate.jobs ~= nil and net.gate.jobs.list or {}
	for i = 1, #list do
		if not CeroSecOS.jobIsOver(list[i]) then running = running + 1 end
	end
	eq("and the far machine is running nothing", running, 0)
end

--
-- The same rule standing at the door
--
-- The engine refuses an rlogin with no terminal where it is written, and
-- CeroSecNet.answerDial refuses one again when the console it arrives on is a
-- detached session's sheet of paper. Two porters, so it is asked of both: this is
-- the second one, called the way the scheduler calls it.
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")

	local sheet = CeroSec.newConsole()
	sheet.booted = true
	sheet.user = "admin"
	sheet.cwd = "/home/admin"
	sheet.noTty = true
	CeroSecNet.answerDial(net.system, net.here, sheet, "rlogin",
		{ host = net.host(net.gate), addr = net.addr(net.gate), user = "admin",
			from = "admin", hops = 1 })
	eq("a dial off a sheet of paper opens no line",
		CeroSecOS.ptyCount(net.gate.ptys), 0)
	local said = false
	for i = 1, #sheet.lines do
		if sheet.lines[i] == "rlogin: not a terminal" then said = true end
	end
	eq("and says so on the sheet", said, true)
	eq("the survivor's glass is untouched", net.here.console.remote, nil)
end

--
-- rcp, both ways, and the far machine's quota
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.put(net.here, "/etc/hosts.equiv", net.host(net.gate), 644, "root")
	net.login("admin")

	net.enter("echo hello > notes.txt")
	net.tick(2)
	net.enter("rcp notes.txt gate:/home/admin/there.txt")
	-- The wire takes as long as it takes, so the command is asleep.
	net.tick(8)
	eq("the file landed on the far machine", net.text(net.gate, "/home/admin/there.txt"),
		"hello")
	check("and nothing was said about it", not net.glass("rcp:"))

	-- And back again, under another name.
	net.enter("rcp gate:/home/admin/there.txt back.txt")
	net.tick(8)
	eq("and comes back", net.text(net.here, "/home/admin/back.txt"), "hello")

	-- The far machine's own ceilings, not this one's: a file too big for a file.
	local big = string.rep("y", CeroSecOS.MAX_FILE_BYTES + 1)
	local state = net.here:osState()
	CeroSecOS.getNode(state, CeroSecOS.rootSession(), "/home/admin/notes.txt").data = big
	net.enter("rcp notes.txt gate:/home/admin/big.txt")
	net.tick(4)
	check("the far machine refuses what will not fit a file",
		net.glass("rcp: /home/admin/big.txt: file too large"))
	eq("and nothing landed", net.text(net.gate, "/home/admin/big.txt"), nil)

	-- A machine that does not trust this one refuses the copy outright.
	net.put(net.gate, "/etc/hosts.equiv", "# nobody", 644, "root")
	net.enter("rcp back.txt gate:/home/admin/no.txt")
	net.tick(4)
	check("rcp with no trust", net.glass("rcp: gate: Permission denied"))
end

--
-- The limits: four sessions, two hops, another building, an unknown name
--

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.name(net.here, net.far, "shed")
	net.login("admin")

	net.enter("rlogin shed")
	net.tick(2)
	check("a machine in another building has no wire to it",
		net.glass("rlogin: shed: No route to host"))
	net.enter("rlogin pump")
	net.tick(2)
	check("and a name nothing carries", net.glass("rlogin: pump: unknown host"))

	net.gate:turnOff()
	net.enter("rlogin gate")
	net.tick(2)
	check("a dark machine on the wire is down", net.glass("rlogin: gate: Host is down"))
	net.gate:turnOn()

	-- Four lines in by hand, and the fifth is refused.
	local far = net.gate:osState()
	net.gate.ptys = {}
	for i = 1, CeroSecOS.PTY_MAX do
		local pty = CeroSecOS.remoteOpen(far, net.gate.ptys, { fromHost = "other", hops = 1 })
		check("line " .. i .. " opened", pty ~= nil)
	end
	eq("four lines are taken", CeroSecOS.ptyCount(net.gate.ptys), CeroSecOS.PTY_MAX)
	net.enter("rlogin gate")
	net.tick(2)
	check("the fifth caller is refused", net.glass("rlogin: connect: Connection refused"))
	net.gate.ptys = {}
end

-- Two hops, and the third refused.
do
	local net = newNet()
	local third = net.machine(14, 10, 0, net.office)
	third:turnOn()
	net.name(net.here, net.gate, "gate")
	net.name(net.gate, third, "pump")
	net.name(third, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	-- third trusts the machine ITS OWN /etc/hosts calls "gate", which is the line
	-- above: a trust line is a name this machine can resolve to the caller's
	-- address, and third has never heard gate announce anything.
	net.put(third, "/etc/hosts.equiv", "gate", 644, "root")
	net.put(net.gate, "/etc/hosts.equiv",
		net.host(net.here) .. "\n" .. net.host(third), 644, "root")
	net.login("admin")

	net.enter("rlogin gate")
	net.tick(3)
	check("one hop out", net.glass("admin@" .. net.host(net.gate)))
	net.enter("rlogin pump")
	net.tick(3)
	check("two hops out", net.glass("admin@" .. net.host(third)))
	eq("and the chain is two long",
		CeroSecOS.ptyCount(net.gate.ptys) + CeroSecOS.ptyCount(third.ptys), 2)
	net.enter("rlogin gate")
	net.tick(3)
	check("the third hop is refused", net.glass("rlogin: connect: Connection refused"))

	-- The far machine going dark ends the whole chain behind it.
	net.forget()
	third:turnOff()
	net.enter("hostname")
	net.tick(3)
	check("a session whose machine went dark is over", net.heard("Connection closed."))
end

-- A machine whose chunk nobody has loaded still answers.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	-- Switched on, numbered, and then the streamer takes its square away: this
	-- is exactly what SGlobalObject answers for an unloaded chunk.
	net.gate.getSquare = function() return nil end
	net.gate.getIsoObject = function() return nil end
	eq("the unloaded machine has no square", net.gate:getSquare(), nil)
	net.login("admin")

	net.enter("ruptime")
	check("and is still on the wire", net.glass(net.host(net.gate)))
	net.enter("ping gate")
	net.tick(30)
	check("and still answers a ping",
		net.heard("3 packets transmitted, 3 packets received, 0% packet loss"))
	net.enter("rlogin gate")
	net.tick(3)
	check("and still takes a login", net.glass("admin@" .. net.host(net.gate)))
	net.enter("echo deep > /home/admin/deep.txt")
	net.tick(3)
	eq("and its disk is really written", net.text(net.gate, "/home/admin/deep.txt"), "deep")
end

-- Shutting the far machine down from inside the session closes it.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(3)
	net.forget()
	net.enter("sudo halt")
	net.enter("")
	net.tick(4)
	eq("the far machine is off", net.gate.on, false)
	check("and the session said so", net.heard("Connection closed."))
	check("with the local prompt back", net.glass("admin@" .. net.host(net.here)))
end

-- And rebooting it from inside the session closes it the same way. A reboot is
-- the far machine going down, whatever it does three seconds later: the words the
-- remote end reads are the words it has always read, and the window that comes
-- back at the end of a dark interval is a LOCAL one -- there is nobody standing
-- at the machine on the other end of the wire.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(3)
	net.forget()
	net.enter("sudo reboot")
	net.enter("")
	net.tick(4)
	eq("the far machine is dark", net.gate.on, false)
	check("and the session said so, in the same words", net.heard("Connection closed."))
	check("with the local prompt back", net.glass("admin@" .. net.host(net.here)))
	eq("no session is left on it", CeroSecOS.ptyCount(net.gate.ptys), 0)

	_G.__now = _G.__now + CeroSec.REBOOT_DARK_MS
	net.tick(1)
	eq("the far machine came back up", net.gate.on, true)
	eq("with nobody logged in", net.gate.console.user, nil)
	eq("and nobody watching it", net.gate.watchers, nil)
end

-- The editor travels: the buffer belongs to the session, so it is the far
-- machine's file that opens and the far machine's disk that is written.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(3)
	net.enter("edit remote.txt")
	net.tick(2)
	eq("the window is in the editor", net.window.mode, "edit")
	check("on the far machine's path", net.glass("/home/admin/remote.txt"))
	check("and this window holds the keyboard", net.window:editing())
	net.window.entry:type("over there")
	net.frame()
	net.window:onOtherKey(Keyboard.KEY_TAB)
	net.tick(2)
	eq("the far machine's disk has it",
		net.text(net.gate, "/home/admin/remote.txt"), "over there")
	eq("and this machine's has nothing at that name",
		net.text(net.here, "/home/admin/remote.txt"), nil)
	net.window:onOtherKey(Keyboard.KEY_ESCAPE)
	net.tick(2)
	eq("Escape leaves the editor and not the session", net.window.mode, "shell")
	check("the far machine's prompt is back", net.glass("admin@" .. net.host(net.gate)))
end

-- A window that opens on a machine with a session on it shows the session: the
-- screen belongs to the machine, so a second survivor walking up reads the same
-- glass as the first.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(3)
	check("the session is up", net.glass("admin@" .. net.host(net.gate)))
	-- The window closes and opens again, which is what walking away and coming
	-- back is: the machine still holds the session.
	net.reopen()
	-- The BOTTOM of the glass, not "anywhere on it": a session that had ended
	-- would leave its prompt in the scrollback and pass the looser question.
	eq("and it is still on the glass when the window comes back",
		net.bottom(), "admin@" .. net.host(net.gate) .. ":~$ ")
	net.enter("hostname")
	net.tick(2)
	check("and still typing at the far machine", net.glass(net.host(net.gate)))
end

-- A refused rlogin, Escape, and the rlogin that works afterwards.
--
-- Reported as a bug in the window: after `rlogin nosuchhost` was refused,
-- Escape "left the glass painting the local prompt" while the next `rlogin gate`
-- opened a real trusted session on the far machine. It is not one, and the two
-- halves of it are worth holding down separately, because each is a thing that
-- could break.
--
-- The refusal is the resolver's and never reaches the wire, so it must leave the
-- console EXACTLY as the line found it -- no half-dialled session, nothing
-- pending, no flag for the next command to trip over. And Escape at an idle
-- local prompt shuts the window, which is what it is for: there is no session to
-- give up on and the machine is not in the middle of anything. A shut window is
-- gone from the UI manager and its watcher is off the machine's book, so nothing
-- the server pushes afterwards can reach it -- which is the whole of what the
-- report saw. The way back to a glass is the way back in the game: open the
-- computer again.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/home/admin/.rhosts", net.host(net.here) .. " admin", 600, "admin")
	net.login("admin")

	-- Every field the console carries, before the line and after it. Asked of the
	-- whole table and not of the three fields a guess would name: what a refusal
	-- must not leave behind is anything at all.
	--
	-- Two are the shell's own and are asked about separately below: the lines on
	-- the glass, and $? -- a command that failed has to leave a failing status,
	-- and a refused rlogin failed.
	local function marks()
		local out, console = {}, net.here:consoleState()
		for key, value in pairs(console) do
			if key ~= "lines" and key ~= "status" then out[key] = tostring(value) end
		end
		return out, #console.lines
	end
	local before, rows = marks()
	net.enter("rlogin nosuchhost")
	net.tick(3)
	check("the resolver refuses the name", net.glass("rlogin: nosuchhost: unknown host"))
	local after, rowsAfter = marks()
	for key, value in pairs(after) do
		eq("the refusal left the console's " .. key .. " alone", value, before[key])
	end
	for key in pairs(before) do
		check("and took nothing off it (" .. key .. ")", after[key] ~= nil)
	end
	eq("the line it printed and the line that was typed, and no more",
		rowsAfter, rows + 2)
	eq("nothing was dialled", CeroSecOS.ptyCount(net.gate.ptys), 0)
	eq("and $? says the command failed", net.here:consoleState().status, 1)

	-- And the refusal that comes back from the WIRE, which is the one that could
	-- leave a half-dialled session behind: the resolver's refusal never reaches
	-- the far machine, and the dial the far machine turns down does. Its four
	-- lines are taken, so the fifth caller is refused where the pty would have
	-- been opened.
	local far = net.gate:osState()
	-- The table the far machine keeps its lines in, made the way the dial makes it
	-- (SCeroSecNet connect): a machine nobody has called yet has no lines at all.
	if net.gate.ptys == nil then net.gate.ptys = {} end
	for i = 1, CeroSecOS.PTY_MAX do
		local pty = CeroSecOS.remoteOpen(far, net.gate.ptys,
			{ fromHost = "busy" .. i, want = "admin", hops = 1, at = 100 })
		check("a line on the far machine is taken (" .. i .. ")", pty ~= nil)
	end
	before, rows = marks()
	net.enter("rlogin gate")
	net.tick(3)
	check("the far machine turns the fifth caller down",
		net.glass("rlogin: connect: Connection refused"))
	after, rowsAfter = marks()
	for key, value in pairs(after) do
		eq("the far machine's refusal left the console's " .. key .. " alone",
			value, before[key])
	end
	for key in pairs(before) do
		check("and took nothing off it either (" .. key .. ")", after[key] ~= nil)
	end
	eq("with no fifth line opened", CeroSecOS.ptyCount(net.gate.ptys),
		CeroSecOS.PTY_MAX)
	for i = 0, CeroSecOS.PTY_MAX - 1 do
		net.gate.ptys[CeroSecOS.ptyLine(i)] = nil
	end

	-- Escape, with nothing to interrupt and no session to give up on.
	eq("the machine has one window on it", net.watchers(), 1)
	net.escape()
	check("Escape shut the window", net.window.closing)
	eq("and the machine stopped pushing screens to it", net.watchers(), 0)
	local ok = pcall(net.enter, "rlogin gate")
	eq("a shut window takes no more keys", ok, false)

	-- The way back, and the session that was said not to show.
	net.reopen()
	eq("the machine hands the new window its own prompt",
		net.bottom(), "admin@" .. net.host(net.here) .. ":~$ ")
	net.enter("rlogin gate")
	net.tick(3)
	eq("a trusted rlogin opens one session over there",
		CeroSecOS.ptyCount(net.gate.ptys), 1)
	check("without asking for a password", net.gate.ptys.ttyp0.trusted)
	eq("and the far machine's prompt is at the bottom of the glass",
		net.bottom(), "admin@" .. net.host(net.gate) .. ":~$ ")
	net.enter("hostname")
	net.tick(2)
	check("which is whose keyboard it now is", net.glass(net.host(net.gate)))
end

-- The same, after a session that ENDED properly. `exit` puts the glass back on
-- the local shell, so the Escape after it is the idle one again -- and the far
-- machine's prompt is in the scrollback for good, which is why every question
-- here is about the BOTTOM of the glass.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/home/admin/.rhosts", net.host(net.here) .. " admin", 600, "admin")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(3)
	local gate = "admin@" .. net.host(net.gate) .. ":~$ "
	eq("the session is on the glass", net.bottom(), gate)
	net.enter("exit")
	net.tick(3)
	eq("and exit hands the glass back to the local shell",
		net.bottom(), "admin@" .. net.host(net.here) .. ":~$ ")
	eq("with no line left open over there", CeroSecOS.ptyCount(net.gate.ptys), 0)
	check("and nothing remote on the console", net.here:consoleState().remote == nil)

	-- Escape is the idle one: there is nothing to interrupt and nothing to hang up.
	net.escape()
	check("so it shuts the window", net.window.closing)
	eq("and takes its watcher with it", net.watchers(), 0)

	net.reopen()
	net.enter("rlogin gate")
	net.tick(3)
	eq("the second session opens", CeroSecOS.ptyCount(net.gate.ptys), 1)
	-- The first session's prompt is up in the scrollback: a bench that asked
	-- net.glass this would be green whether the second session happened or not.
	eq("and the far prompt is at the bottom of the glass again", net.bottom(), gate)
end

-- The loopback: a second session on the machine one is sitting at. It needs no
-- wire and no building, which is what a loopback is for.
do
	local net = newNet()
	net.login("admin")
	net.enter("rlogin localhost")
	net.tick(2)
	check("the machine asks who is there", net.glass("login:"))
	net.enter("admin")
	net.enter("")
	net.tick(2)
	eq("a line is taken on the machine itself", CeroSecOS.ptyCount(net.here.ptys), 1)
	net.enter("who")
	net.tick(2)
	check("who shows the keyboard", net.glass("console"))
	check("and the session beside it", net.glass("ttyp0"))
	net.enter("exit")
	net.tick(3)
	eq("and it closes like any other", CeroSecOS.ptyCount(net.here.ptys), 0)
end

--
-- The telephone (rung 6b)
--
-- Two buildings four hundred squares apart, which is what makes this section
-- about the telephone and not about the coax: not one of the commands in the
-- chapter before this one reaches from the office to the shed, and cu does.
--
-- The number is the BUILDING's, so the office's two machines share one, and it
-- is derived from the corner of the building's def the way the address is --
-- which means the bench can work out what it should be without being told.
--

local function telOf(object)
	return CeroSecOS.phoneOf(object:osState())
end

-- What is on a machine's OWN glass, for the machines this bench has no window
-- on: a third computer dialling is a real line typed at a real prompt, and the
-- server path it goes through is the one Commands.exec ends in.
local function ownSaid(object, needle)
	local lines = object:consoleState().lines
	for i = 1, #lines do
		if string.find(lines[i], needle, 1, true) then return true end
	end
	return false
end

local function typeAt(net, object, line, ticks)
	local console = object:consoleState()
	console.booted = true
	console.user = "admin"
	console.cwd = "/home/admin"
	net.system:startPrompt(object, console, line, nil, nil)
	net.tick(ticks or 3)
end

-- THE RING. A modem prints nothing at all while it dials and the far end rings,
-- so every bench below has to sit through the ring the outcome it is asserting on
-- costs: CeroSecOS.RING_ANSWER_MS of wall clock for a call that is answered,
-- RING_BUSY_MS for a busy line and RING_TIMEOUT_MS -- the modem's S7 -- for one
-- nobody picks up. A pass is CeroSec.JOB_PASS_MS of that clock.
--
-- Two passes over: one for the pass the wait is set up in and one for the pass
-- after it, which is where the result code is actually written. Derived from the
-- constants and not written out, deliberately -- this is the bench's own PACING
-- and not a claim about the numbers; what asserts the numbers is os_test 48 and
-- the timing bench below, which reads the clock itself.
local function ringPasses(ms)
	return math.ceil(ms / CeroSec.JOB_PASS_MS) + 2
end

local function ringOut(net, ms)
	net.tick(ringPasses(ms or CeroSecOS.RING_ANSWER_MS))
end

-- `cu`, and the ring behind it, in one line -- because a bench that dialled and
-- looked at the glass in the same breath would be looking at a modem still
-- dialling, and would read the silence as an answer.
local function dial(net, tel, ms)
	net.enter("cu " .. tel)
	ringOut(net, ms)
end

-- The number, the BIOS line, and a machine with no line at all.
do
	local net = newNet()
	local b1, b2 = CeroSecOS.buildingKey(400, 700)
	local ex = CeroSecOS.phoneExchange(400, 700)
	-- ONE LINE PER PREMISES, and with no zone on the map a premises is the whole
	-- building: both office machines are on one line, worked out from the building
	-- key and the region the building stands in -- facts the bench derives for
	-- itself without being told.
	eq("the office's number is the premises's", telOf(net.here),
		CeroSecOS.phoneText(ex, CeroSecOS.phoneKey(b1, b2)))
	eq("and the other machine in the room answers on the same one",
		telOf(net.gate), telOf(net.here))
	check("the shed down the road has a different one",
		telOf(net.far) ~= telOf(net.here))
	-- ONE CENTRAL OFFICE TO A TOWN. The office and the shed are inside one
	-- PHONE_REGION square, so both are wired back to one switch and share the first
	-- three digits -- which is the point of the exchange: the numbers of one place
	-- look like each other.
	eq("both are on one central office",
		string.sub(telOf(net.far), 1, 3), string.sub(telOf(net.here), 1, 3))
	-- And a building in the next region along is on ANOTHER switch.
	local town = net.machine(300, 300, 0, net.buildingAt(1200, 40, 10, 10, 3))
	town:turnOn()
	check("a building a region away is on another central office",
		string.sub(telOf(town), 1, 3) ~= string.sub(telOf(net.here), 1, 3))
	check("seven digits, and the office code does not start with 0 or 1",
		string.find(telOf(net.here), "^[2-9]%d%d%-%d%d%d%d") ~= nil)
	check("and the machine knows it is one", CeroSecOS.isPhoneNumber(telOf(net.here)))

	-- The firmware announces it under the card, which is the only place it is
	-- written: nothing on the disk holds it.
	net.login("admin")
	check("the BIOS announces the line", net.glass("Phone line: " .. telOf(net.here)))
	check("under the card", net.glass("Ethernet: eth0 " .. net.addr(net.here)))
	local ok, lines = CeroSecOS.runArgs(net.here:osState(),
		{ user = "root", cwd = "/root" }, { "cat", "/etc/phone" }, nil, { now = 0 })
	eq("and there is no file to read it out of", ok, false)
	check("no such file", string.find(lines[1], "no such file", 1, true) ~= nil)

	-- AN OLDER SAVE. Every machine written before the line belonged to the premises
	-- carries the building bytes and no exchange, and such a machine has NO
	-- telephone at all -- there is no region on its disk to work one out from. It
	-- gets one the next time the server sees where it is standing, which is the next
	-- time it is switched on or a window opens on it, and nothing is migrated
	-- anywhere else.
	local old = net.gate:osState()
	local was = CeroSecOS.netRecord(old)
	CeroSecOS.setNetRecord(old, was.b1, was.b2, was.n)
	net.gate:mirrorOS()
	eq("a record with no exchange in it has no line", telOf(net.gate), nil)
	eq("but it still has an address", CeroSecOS.address(old),
		CeroSecOS.addressText(was.b1, was.b2, was.n))
	net.gate:turnOff()
	net.gate:turnOn()
	eq("switching it on gives it the line it should have had",
		telOf(net.gate), CeroSecOS.phoneText(ex, CeroSecOS.phoneKey(b1, b2)))

	-- A computer in a base somebody built is in no building, so there is nothing
	-- to derive either a wire or a telephone from.
	local loose = net.machine(80, 80, 0, nil)
	loose:turnOn()
	eq("a machine in no building has no line", telOf(loose), nil)
	typeAt(net, loose, "cu " .. telOf(net.far))
	check("and cu says so in its own words", ownSaid(loose, "cu: no phone line"))
	check("having never lifted the receiver", net.far.ptys == nil)
end

-- A SHOP IN A MALL IS A PREMISES, and a house is not thirty of them.
--
-- The map tags the shops inside a mall with small named ZombiesType zones. Three
-- machines in ONE building: one in each of two such zones and one in neither, which
-- is three premises -- three telephone lines and three lengths of coax -- and the
-- rule that keeps a house one premises is the AREA test.
do
	local net = newNet()
	-- A mall: the office building, 10 by 10, with two 6x6 shops in it -- both
	-- strictly smaller than its footprint, which is what the area test asks.
	_G.__zones = {
		{ name = "CoffeeShop", x = 8, y = 8, w = 6, h = 6 },
		{ name = "Bakery", x = 20, y = 8, w = 6, h = 6 },
	}
	-- net.here is at 10,10 (the coffee shop), net.gate at 12,10 (the coffee shop
	-- too), and a third machine at 22,10 (the bakery). A fourth stands in the mall
	-- and in neither shop.
	local baker = net.machine(22, 10, 0, net.office)
	local hall = net.machine(35, 35, 0, net.office)
	for _, m in ipairs({ net.here, net.gate, baker, hall }) do
		m:turnOff()
		m:turnOn()
	end

	-- THREE PREMISES, THREE NUMBERS.
	check("the coffee shop has a line", telOf(net.here) ~= nil)
	eq("and both its machines are on it", telOf(net.gate), telOf(net.here))
	check("the bakery next door has another", telOf(baker) ~= telOf(net.here))
	check("and the mall's own floor a third",
		telOf(hall) ~= telOf(net.here) and telOf(hall) ~= telOf(baker))
	-- All three on one central office, because one building is one town.
	eq("all three are on one central office",
		string.sub(telOf(baker), 1, 3), string.sub(telOf(net.here), 1, 3))

	-- THREE SEGMENTS. The premises decides the coax too, so the shop next door is
	-- not on this one's wire at all -- which is what two businesses in one building
	-- had.
	local mine = CeroSecOS.netRecord(net.here:osState())
	local theirs = CeroSecOS.netRecord(baker:osState())
	check("the bakery is on another segment",
		mine.b1 ~= theirs.b1 or mine.b2 ~= theirs.b2)
	eq("and the coffee shop's two machines are on one",
		CeroSecOS.netRecord(net.gate:osState()).b1, mine.b1)
	net.login("admin")
	net.name(net.here, baker, "bakery")
	net.enter("ping bakery")
	net.tick(40)
	check("so no r-command reaches it", net.glass("100% packet loss"))
	-- While the telephone does, which is the whole point of a line per premises.
	dial(net, telOf(baker))
	check("and the telephone does", net.glass("CONNECT 2400"))

	-- And the firmware says WHICH line this is, because a survivor in a mall with
	-- thirty of them needs to know.
	check("the BIOS names the premises",
		net.glass("Phone line: " .. telOf(net.here) .. " (CoffeeShop)"))
	eq("which is on the record and not worked out twice",
		CeroSecOS.premisesName(net.here:osState()), "CoffeeShop")
	eq("a machine on the mall floor has no premises name",
		CeroSecOS.premisesName(hall:osState()), nil)
	_G.__zones = {}
end

-- THE AREA TEST, which is the whole of what tells a tenancy from a region.
do
	local net = newNet()
	local house = net.machine(500, 500, 0, net.buildingAt(2000, 2000, 10, 10, 3))
	house:turnOn()
	local alone = telOf(house)
	check("a house with no zone on it has a line", alone ~= nil)

	-- A named zone BIGGER than the building is a suburb and not a tenancy: the
	-- house keeps the one line it had.
	_G.__zones = { { name = "Suburb", x = 400, y = 400, w = 400, h = 400 } }
	house:turnOff()
	house:turnOn()
	eq("a zone bigger than the building is no premises", telOf(house), alone)

	-- A zone EXACTLY the building's area is the building under another name, and
	-- loses on the same test -- strictly smaller, or nothing.
	_G.__zones = { { name = "Same", x = 495, y = 495, w = 10, h = 10 } }
	house:turnOff()
	house:turnOn()
	eq("a zone the building's own size is no premises either", telOf(house), alone)

	-- One tile smaller IS one, and the house is suddenly a shop.
	_G.__zones = { { name = "Shop", x = 495, y = 495, w = 10, h = 9 } }
	house:turnOff()
	house:turnOn()
	check("a zone smaller than the building is a premises", telOf(house) ~= alone)
	eq("and it is named", CeroSecOS.premisesName(house:osState()), "Shop")

	-- The SMALLEST of the ones that qualify: a shop inside a shop is the shop the
	-- survivor is standing in.
	_G.__zones = {
		{ name = "Shop", x = 495, y = 495, w = 10, h = 9 },
		{ name = "Kiosk", x = 498, y = 498, w = 4, h = 4 },
	}
	house:turnOff()
	house:turnOn()
	eq("the smallest qualifying zone wins",
		CeroSecOS.premisesName(house:osState()), "Kiosk")

	-- A CONTROL first, because the two refusals below would be green on a zone that
	-- simply misses the machine's square: the same outline with the right type and a
	-- name IS a premises, so what the two of them prove is the type and the name.
	_G.__zones = { { name = "Control", x = 498, y = 498, w = 4, h = 4 } }
	house:turnOff()
	house:turnOn()
	check("a zone of that outline does reach the machine", telOf(house) ~= alone)
	eq("and it is the one named", CeroSecOS.premisesName(house:osState()), "Control")

	-- A zone of the WRONG TYPE is not a premises whatever its size: the rule is
	-- ZombiesType, which is the kind a shop is tagged with.
	_G.__zones = { { name = "Nav", type = "Nav", x = 498, y = 498, w = 4, h = 4 } }
	house:turnOff()
	house:turnOn()
	eq("a zone of another type is no premises", telOf(house), alone)
	-- And one with no name at all is not one either.
	_G.__zones = { { name = "", x = 498, y = 498, w = 4, h = 4 } }
	house:turnOff()
	house:turnOn()
	eq("nor is a zone nobody named", telOf(house), alone)
	_G.__zones = {}
end

-- A call, end to end: the modem, cu, the far machine's login, the work, and the
-- A call, end to end: the modem, cu, the far machine's login, the work, and the
-- two commands over there that name the number it came from.
do
	local net = newNet()
	net.login("admin")
	local tel = telOf(net.far)
	local mine = telOf(net.here)

	dial(net, tel)
	check("the modem answers first", net.glass("CONNECT 2400"))
	check("and then cu", net.glass("Connected."))
	check("the far machine asks who is there", net.glass("login:"))
	-- No trust file is asked over the telephone, so the password is asked even
	-- though the far machine trusts this one on its own coax.
	net.put(net.far, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.enter("admin")
	net.enter("")
	net.tick(2)
	local shed = net.host(net.far)
	check("the prompt is the far machine's", net.glass("admin@" .. shed))
	eq("a line is taken over there", CeroSecOS.ptyCount(net.far.ptys), 1)

	net.enter("hostname")
	net.tick(3)
	check("and every line typed is the far machine's", net.glass(shed))

	-- Who is on it, and where from: a call has no host name in it, so what the far
	-- machine knows about the caller is the number he can be rung back on.
	net.enter("who")
	net.tick(3)
	check("who names the pty", net.glass("ttyp0"))
	check("and the number that called", net.glass("(" .. mine .. ")"))
	net.enter("last")
	net.tick(3)
	check("last has it too", net.glass(mine))
	check("and wtmp is where it read it",
		string.find(net.text(net.far, "/var/log/wtmp"), mine, 1, true) ~= nil)

	-- rsh does not dial. It is a network command and the shed is in another
	-- building, which is the whole of what No route to host means.
	net.name(net.here, net.far, "shed")
	net.forget()
	net.enter("exit")
	net.tick(3)
	check("the call says it is over in cu's own word", net.heard("Disconnected."))
	check("and not in rlogin's", not net.heard("Connection closed."))
	eq("the line is given back", CeroSecOS.ptyCount(net.far.ptys), 0)

	net.enter("rsh shed hostname")
	net.tick(3)
	check("rsh will not use the telephone", net.glass("rsh: shed: No route to host"))
	net.enter("rcp notes.txt shed:/tmp/notes.txt")
	net.tick(3)
	check("and neither will rcp", net.glass("rcp: shed: No route to host"))
end

-- ~. is the near end hanging up, and it never reaches the far shell.
do
	local net = newNet()
	net.login("admin")
	dial(net, telOf(net.far))
	net.enter("admin")
	net.enter("")
	net.tick(2)
	check("the call is up", net.glass("admin@" .. net.host(net.far)))
	net.forget()
	net.enter("~.")
	net.tick(3)
	check("~. hangs up", net.heard("Disconnected."))
	eq("the line is given back", CeroSecOS.ptyCount(net.far.ptys), 0)
	check("and the glass is this machine's again",
		net.glass("admin@" .. net.host(net.here)))
	-- It was never a command anywhere: not over there, and not in this machine's
	-- history either, because the shell here never saw it.
	local there = net.text(net.far, "/home/admin/.sh_history")
	check("the far machine never heard of it",
		there == nil or string.find(there, "~.", 1, true) == nil)
	local here = net.text(net.here, "/home/admin/.sh_history")
	check("and neither did this one", string.find(here, "~.", 1, true) == nil)
	-- A ~. at one's own prompt is an ordinary line and gets an ordinary refusal.
	net.enter("~.")
	net.tick(3)
	check("off a call it is just a word", net.glass("~.: command not found"))
end

-- ONE LINE PER MODEM: a third machine dialling a line that is in use, the machine
-- at the next desk, and the two ends a ring holds.
do
	local net = newNet()
	local other = net.machine(200, 200, 0, (function()
		local def = { getX = function() return 1200 end, getY = function() return 40 end,
			getX2 = function() return 1240 end, getY2 = function() return 80 end }
		return { getDef = function() return def end }
	end)())
	other:turnOn()
	net.login("admin")
	local tel = telOf(net.far)

	dial(net, tel)
	check("the call is up", net.glass("CONNECT 2400"))

	-- The shed's line is busy, and so is this machine's -- a modem that has dialled
	-- out cannot take a call either.
	typeAt(net, other, "cu " .. tel, ringPasses(CeroSecOS.RING_BUSY_MS))
	check("a third machine gets the busy signal", ownSaid(other, "BUSY"))
	eq("and no second line was taken over there",
		CeroSecOS.ptyCount(net.far.ptys), 1)
	typeAt(net, other, "cu " .. telOf(net.here), ringPasses(CeroSecOS.RING_BUSY_MS))
	check("and so does one dialling the machine that dialled",
		ownSaid(other, "BUSY"))
	eq("no line on this machine either", CeroSecOS.ptyCount(net.here.ptys or {}), 0)

	-- Hang up. ~. is only read at a shell prompt -- at the far machine's login it
	-- would be a name -- so this logs in to do it.
	net.enter("admin")
	net.enter("")
	net.tick(2)
	net.forget()
	net.enter("~.")
	net.tick(3)
	check("the call is over", net.heard("Disconnected."))

	-- The machine at the next desk is on THIS premises, so its number is this
	-- machine's own and dialling it is dialling a line one is already on.
	eq("the next desk is on the same line", telOf(net.gate), telOf(net.here))
	dial(net, telOf(net.gate), CeroSecOS.RING_BUSY_MS)
	check("so dialling it is busy", net.glass("BUSY"))
	eq("and nothing was opened", CeroSecOS.ptyCount(net.gate.ptys or {}), 0)

	-- One's OWN number is busy for the same reason: the caller is using the line.
	dial(net, telOf(net.here), CeroSecOS.RING_BUSY_MS)
	check("dialling one's own modem is dialling a line one is using",
		net.glass("BUSY"))
end

-- BOTH ENDS ARE BUSY WHILE IT RINGS. A modem that has gone off-hook is holding
-- its line before anybody has answered, and the telephone that is ringing cannot
-- take a second call either -- so a fifteen-second ring is fifteen seconds in
-- which neither number is free.
do
	local net = newNet()
	local other = net.machine(200, 200, 0, (function()
		local def = { getX = function() return 1200 end, getY = function() return 40 end,
			getX2 = function() return 1240 end, getY2 = function() return 80 end }
		return { getDef = function() return def end }
	end)())
	other:turnOn()
	net.login("admin")
	local mine, theirs = telOf(net.here), telOf(net.far)

	-- Ringing, and no further along than that: the machine is asleep on a clock
	-- with nothing on the glass, and the far machine has no line taken.
	net.enter("cu " .. theirs)
	net.tick(4)
	check("nothing is on the glass while it rings", not net.glass("CONNECT 2400"))
	check("nor any word at all", not net.glass("NO CARRIER") and not net.glass("BUSY"))
	eq("and no line is open over there", CeroSecOS.ptyCount(net.far.ptys or {}), 0)
	local ring = CeroSecNet.ringOf(net.here)
	check("the dialling job is what holds the line", ring ~= nil)
	eq("this end of it", ring.tel, mine)
	eq("and the end it is ringing", ring.to, theirs)
	check("the caller's own line reads busy", CeroSecNet.lineBusy(net.system, mine))
	check("and so does the line that is ringing",
		CeroSecNet.lineBusy(net.system, theirs))

	-- A third machine dialling either of them, mid-ring, gets the busy signal.
	typeAt(net, other, "cu " .. theirs, ringPasses(CeroSecOS.RING_BUSY_MS))
	check("a third machine dialling the ringing telephone is refused",
		ownSaid(other, "BUSY"))

	-- And the ring finishes into a call, the line held all the way through.
	ringOut(net)
	check("the call goes through in the end", net.glass("CONNECT 2400"))
	eq("and now it is a session", CeroSecOS.ptyCount(net.far.ptys), 1)
	eq("with nothing left ringing", CeroSecNet.ringOf(net.here), nil)
end

-- HOW LONG A DIAL TAKES, read off the clock: four seconds to CONNECT, two to
-- BUSY, and the modem's S7 -- fifteen -- to NO CARRIER.
--
-- Measured as a NUMBER OF PASSES and not as a "before/after" on the glass: a
-- bench that only asserted the word appeared would be green on a modem that
-- answered instantly. The numbers are written out rather than read off the
-- constants for the reason the 2400-baud bench writes its own out -- a bound whose
-- reference is its own source proves nothing.
do
	local net = newNet()
	net.login("admin")

	-- Four seconds is forty passes of a hundred milliseconds. At thirty-five there
	-- is still nothing; by forty-five the modem has answered.
	net.enter("cu " .. telOf(net.far))
	net.tick(35)
	check("nothing at three and a half seconds", not net.glass("CONNECT 2400"))
	net.tick(10)
	check("and the carrier at four and a bit", net.glass("CONNECT 2400"))
	net.enter("admin")
	net.enter("")
	net.tick(2)
	net.forget()
	net.enter("~.")
	net.tick(3)

	-- Two seconds for a busy tone: one's own number is always busy.
	net.forget()
	net.enter("cu " .. telOf(net.here))
	net.tick(15)
	check("nothing at a second and a half", not net.glass("BUSY"))
	net.tick(10)
	check("and the busy tone at two and a bit", net.glass("BUSY"))

	-- Fifteen seconds for a number nobody answers: the machine is switched off, so
	-- the modem waits out S7 and gives up.
	local dark = telOf(net.far)
	net.far:turnOff()
	net.forget()
	net.enter("cu " .. dark)
	net.tick(140)
	check("nothing at fourteen seconds", not net.glass("NO CARRIER"))
	net.tick(20)
	check("and NO CARRIER at fifteen and a bit", net.glass("NO CARRIER"))
	net.far:turnOn()
end

-- A PARTY LINE, which is what several telephones on one line is and what a rural
-- exchange really sold in 1993. There are two ways to be on one here and they end
-- in the same answer: several machines of ONE premises, and two PREMISES that
-- hashed onto one number. The lowest address answers, every time, and the line is
-- busy for all of them while it is up.
do
	local net = newNet()
	net.login("admin")
	-- The second kind, made rather than hunted for: the record is what the number
	-- comes off, so a machine can be given another premises's two bytes. A shop on
	-- the mall floor landing on the shed's number is exactly what ten thousand
	-- subscriber numbers to a region allows.
	local twin = net.machine(300, 300, 0, net.shed)
	twin:turnOn()
	local state = twin:osState()
	local mine = CeroSecOS.netRecord(net.far:osState())
	check("the shed's own machine has a record", mine ~= nil)
	-- The same two bytes and the same exchange, and therefore the same number. The
	-- address collides too, which is what two subscribers on one line looked like
	-- from the exchange's side: there is nothing on this rung that routes.
	CeroSecOS.setNetRecord(state, mine.b1, mine.b2, mine.n + 1, mine.ex)
	twin:mirrorOS()
	eq("and the twin answers to the same number", telOf(twin), telOf(net.far))

	dial(net, telOf(net.far))
	check("the call goes through", net.glass("CONNECT 2400"))
	eq("the lowest address on the line is the one that picked up",
		CeroSecOS.ptyCount(net.far.ptys), 1)
	eq("and the other subscriber took no line",
		CeroSecOS.ptyCount(twin.ptys or {}), 0)
	-- The line is one line: the twin cannot dial out while it is up.
	typeAt(net, twin, "cu " .. telOf(net.here), ringPasses(CeroSecOS.RING_BUSY_MS))
	check("the other subscriber's telephone is busy too", ownSaid(twin, "BUSY"))
end

-- ESCAPE ABORTS A DIAL, and the word for it is the modem's own: a dial the DTE
-- gave up on ends in NO CARRIER, which is what a Hayes modem prints when the
-- receiver goes down before a carrier came up.
do
	local net = newNet()
	net.login("admin")
	local dark = telOf(net.far)
	net.far:turnOff()
	net.enter("cu " .. dark)
	net.tick(20)
	check("it is still ringing", not net.glass("NO CARRIER"))
	check("and holding the line", CeroSecNet.ringOf(net.here) ~= nil)
	net.forget()
	net.escape()
	net.tick(3)
	check("Escape hangs up in the modem's own word", net.heard("NO CARRIER"))
	eq("and the line is let go with it", CeroSecNet.ringOf(net.here), nil)
	check("nothing is holding the caller's number",
		not CeroSecNet.lineBusy(net.system, telOf(net.here)))
	check("nor the one it was ringing", not CeroSecNet.lineBusy(net.system, dark))
	-- And the prompt is back, so the next line is taken.
	net.far:turnOn()
	net.forget()
	dial(net, dark)
	check("the machine dials again straight afterwards", net.glass("CONNECT 2400"))
end

-- The exchange is the county's grid: no power, no dial tone, and a call that was
-- up when it went is a call with no carrier.
do
	local net = newNet()
	net.login("admin")
	local tel = telOf(net.far)

	-- The grid dies: the world is ten days old and the power was set to go on day
	-- five. Both halves are set here rather than relied on, because an earlier
	-- bench in this file puts the clock back and leaves the world newborn.
	_G.__gameTime.ageHours = 240
	_G.__sandbox.elecShut = 5
	dial(net, tel)
	check("no exchange, no dial tone", net.glass("NO DIALTONE"))
	check("and nothing was opened", net.far.ptys == nil)

	-- The option a server can set, read the way vanilla reads its own.
	_G.SandboxVars = { CeroSec = { PhoneService = "always" } }
	dial(net, tel)
	check("an exchange on a generator still answers", net.glass("CONNECT 2400"))
	eq("a line is taken", CeroSecOS.ptyCount(net.far.ptys), 1)

	-- And the grid coming back under a call that is up: nothing happens to it,
	-- because the call was never the grid's to begin with on this setting.
	_G.SandboxVars = { CeroSec = { PhoneService = "grid" } }
	net.forget()
	net.enter("admin")
	net.tick(3)
	check("the call it was on is gone with the exchange", net.heard("NO CARRIER"))
	eq("and the line is back", CeroSecOS.ptyCount(net.far.ptys), 0)

	-- never, which is a server with no telephone service at all.
	_G.SandboxVars = { CeroSec = { PhoneService = "never" } }
	_G.__sandbox.elecShut = 100
	check("the grid is back", CeroSecNet.gridAlive())
	dial(net, tel)
	check("and never means never", net.glass("NO DIALTONE"))
	-- Put back what the file runs on, which is not nil any more: a world with no
	-- CeroSec group at all is a world where the hardware IS required
	-- (CeroSecModules.required fails closed), and every device bench after this
	-- one is about the world with the option off.
	_G.SandboxVars = { CeroSec = { HardwareRequired = false } }
	_G.__gameTime.ageHours = 0
end

-- Nobody there: a number no building has, and a building with its machines off.
do
	local net = newNet()
	net.login("admin")
	local dark = telOf(net.far)
	net.far:turnOff()
	dial(net, dark, CeroSecOS.RING_TIMEOUT_MS)
	check("a dark machine does not answer", net.glass("NO CARRIER"))
	net.far:turnOn()
	-- A number in the right shape that nobody in the county has. Built by walking
	-- the subscriber numbers of this bench's own exchange until one is free, because
	-- with a line per MODEM there are three numbers to miss and not two.
	local nobody = nil
	for n = 0, 20 do
		local try = CeroSecOS.phoneText(CeroSecOS.phoneExchange(400, 700), n)
		if try ~= telOf(net.here) and try ~= telOf(net.gate) and try ~= telOf(net.far) then
			nobody = try
			break
		end
	end
	check("there is a number in this county nobody answers to", nobody ~= nil)
	dial(net, nobody, CeroSecOS.RING_TIMEOUT_MS)
	check("a number nobody has does not answer either", net.glass("NO CARRIER"))
	-- And a word that is not a number at all never reaches the exchange.
	net.enter("cu 5551219")
	net.tick(3)
	check("a word that is no number is the usage line",
		net.glass("cu: usage: cu telno"))
	net.enter("cu")
	net.tick(3)
	check("and so is cu with nothing after it", net.glass("cu: usage: cu telno"))
end

-- A call dies with the machine at either end of it.
do
	local net = newNet()
	net.login("admin")
	dial(net, telOf(net.far))
	net.enter("admin")
	net.enter("")
	net.tick(2)
	check("the call is up", net.glass("admin@" .. net.host(net.far)))
	net.forget()
	net.far:turnOff()
	net.enter("hostname")
	net.tick(3)
	check("the far machine going dark drops the carrier", net.heard("NO CARRIER"))
	check("and the glass is this machine's again",
		net.glass("admin@" .. net.host(net.here)))
end

-- The hop rule holds on the telephone, and a chain pays it whichever links it
-- is made of: a wire, then a call, and the third is refused.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(3)
	check("one hop out, over the wire", net.glass("admin@" .. net.host(net.gate)))
	dial(net, telOf(net.far))
	net.enter("admin")
	net.enter("")
	net.tick(3)
	check("two hops out, the second by telephone",
		net.glass("admin@" .. net.host(net.far)))
	dial(net, telOf(net.here), CeroSecOS.RING_BUSY_MS)
	check("and the third hop is refused", net.glass("BUSY"))
	eq("with no third line anywhere",
		CeroSecOS.ptyCount(net.gate.ptys) + CeroSecOS.ptyCount(net.far.ptys), 2)
end

-- cu wants a terminal, exactly as rlogin does: a crontab line that dialled would
-- land a logged-in session on the glass of a machine nobody is standing at.
do
	local net = newNet()
	net.login("admin")
	net.crontab(net.here, "admin", "* * * * * cu " .. telOf(net.far))
	net.minute(2)
	eq("a crontab cu opens no line on the far machine",
		CeroSecOS.ptyCount(net.far.ptys), 0)
	local mail = net.text(net.here, "/var/mail/admin")
	check("and what it said went in the mail, in cu's own words",
		mail ~= nil and string.find(mail, "cu: not a terminal", 1, true) ~= nil)

	net.enter("cu " .. telOf(net.far) .. " &")
	net.tick(3)
	check("a backgrounded cu says it has no terminal",
		net.heard("cu: not a terminal"))
	net.enter("x=$(cu " .. telOf(net.far) .. "); echo [$x]")
	net.tick(3)
	check("and so does one inside a substitution",
		net.heard("[cu: not a terminal]"))
end

-- 2400 baud: a call is four lines a second and the machine at the far end is as
-- fast as it ever was.
do
	local net = newNet()
	net.login("admin")
	dial(net, telOf(net.far))
	net.enter("admin")
	net.enter("")
	net.tick(2)
	local pty = CeroSecOS.ptyList(net.far.ptys)[1]
	check("the session is a call", pty ~= nil and type(pty.phone) == "table")
	eq("and it came from this building's line", pty.phone.tel, telOf(net.here))

	-- Twenty lines asked for at once. The machine's own ceiling is twenty a
	-- second and the line's is four, so the line is what is counted here.
	local before = #pty.console.lines
	net.enter("for i in 1 2 3 4 5 6 7 8 9 10; do echo $i; done")
	-- One second of passes, and no more.
	net.tick(9)
	local after = #pty.console.lines - before
	-- Eight and not four, and the number is written out rather than taken from
	-- CeroSec.PHONE_LINES_PER_S: a bound that reads the constant it is meant to
	-- hold moves with it, and a bench whose reference is its own source proves
	-- nothing. Eight is two of the line's seconds, because these passes straddle
	-- one -- the line typed moved the clock a second on its own -- and ten lines at
	-- the machine's own twenty a second would all be here at once.
	check("a second of a call carries about four lines (" .. after .. ")",
		after >= 2 and after <= 8)
	-- The rest arrives; nothing was thrown away.
	net.tick(40)
	check("and the whole of it arrives in the end", net.glass("10"))
end

-- Whose budget a remote session spends, through the real scheduler.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(3)
	net.enter("while true; do echo deep; done &")
	net.tick(4)
	check("the loop is a job on the far machine",
		net.gate.jobs ~= nil and #net.gate.jobs.list > 0)
	-- The near machine has the shell that typed `rlogin` and nothing else, and
	-- that one is over: what is running is over there.
	check("and the machine at the keyboard is running nothing",
		net.here.jobs == nil or #net.here.jobs.list == 0)
	net.tick(10)
	check("it is still running over there", #net.gate.jobs.list > 0)
	check("and still nothing over here",
		net.here.jobs == nil or #net.here.jobs.list == 0)
	-- And closing the session takes it away: a shell whose terminal has gone has
	-- nothing left to write to.
	net.escape()
	net.tick(4)
	eq("closing the session took the job with it",
		net.gate.jobs == nil or #net.gate.jobs.list, 0)
end

--
-- 41. The radio (rung 6c)
--
-- The two buildings of the section above, with aerials in them. What makes this
-- section about the RADIO and not about the telephone is that every bench in it
-- runs with the county's exchange irrelevant and the radios themselves are what
-- decide: a frequency, a transmit range, a switch and a battery.
--
-- The world is a FakeWorld, laid out beside the machines rather than under them:
-- CeroSecRadio asks getCell() for the squares around a computer, which is a
-- different question from the one the machines' own getSquare answers (that one
-- is the building, and the address comes off it). So a bench can give a machine
-- an aerial, take it away, switch it off or move it out of the room without
-- touching anything the link layer of the rung before this one reads.
--
-- And the AIR is faked too: getZomboidRadio hands back one method, and every
-- transmission the mod makes lands in a list. That is the only way to prove the
-- announcement at all -- what is asserted about it is what the mod passed to the
-- game, argument by argument, against the proof at the head of SCeroSecRadio.lua.
--

-- One radio, answering the six calls CeroSecRadio.read makes on its DeviceData
-- and nothing else. The defaults are a ham set on two metres: HamRadio1's own
-- TransmitRange of 7500 and IsPortable false
-- (media/scripts/generated/items/radio.txt:203-225).
local function fakeRadio(opts)
	opts = opts or {}
	local o = { __class = "IsoRadio" }
	local data = {}
	data.getIsTwoWay = function() return opts.twoWay ~= false end
	data.getIsPortable = function() return opts.portable == true end
	data.getChannel = function() return opts.channel or 144390 end
	data.getTransmitRange = function() return opts.range or 7500 end
	data.getIsTurnedOn = function() return opts.on ~= false end
	data.getPower = function() return opts.power or 1 end
	o.data = opts
	o.getDeviceData = function() return data end
	o.getSpriteName = function() return "cerosec_fake_ham" end
	return o
end

-- Everything the mod put on the air since the list was last emptied.
local function newAir()
	local air = {}
	_G.getZomboidRadio = function()
		return {
			SendTransmission = function(_, x, y, channel, line, guid, codes,
					r, g, b, range, tv)
				air[#air + 1] = { x = x, y = y, channel = channel, line = line,
					guid = guid, codes = codes, r = r, g = g, b = b,
					range = range, tv = tv }
			end,
		}
	end
	return air
end

local function heardOnAir(air, needle)
	for i = 1, #air do
		if type(air[i].line) == "string"
				and string.find(air[i].line, needle, 1, true) then
			return air[i]
		end
	end
	return nil
end

-- A net with a world under it. The aerials go in by hand, per bench.
local function newRadioNet()
	local net = newNet()
	net.world = FakeWorld.new()
	_G.__world = net.world
	net.air = newAir()
	-- The set on a machine's own square, which is the commonest case and the one
	-- a survivor builds himself: a ham radio on the desk the computer is on.
	function net.aerial(object, opts, dx, dy)
		local x = object.x + (dx or 0)
		local y = object.y + (dy or 0)
		local square = net.world.square(x, y, object.z, opts and opts.room or nil)
		return net.world.put(square, fakeRadio(opts))
	end
	-- The machine's own square, with nothing on it. A bench needs this whenever it
	-- puts the set somewhere ELSE, because a machine whose own square the streamer
	-- has not brought in has no TNC at all -- which is the chunk rule, and is a
	-- bench of its own below.
	function net.ground(object)
		return net.world.square(object.x, object.y, object.z, nil)
	end
	return net
end

local function callOf(object)
	return CeroSecOS.callsignOf(object:osState())
end

-- Wait for the window to finish TYPING what it was given. A terminal reveals a
-- screenful a character at a time and refuses a line while it is doing it
-- (CeroSecTerminal:onCommandEntered returns on self.revealing), so a bench that
-- asks a machine two things in a row after a four-line answer has the second one
-- silently dropped. It cost an hour: the far machine had simply never been told.
local function settle(net)
	for _ = 1, 200 do
		if not net.window.revealing and net.window.mode ~= "job" then return end
		net.tick(1)
	end
end

-- A line typed once the machine is ready for one. Both halves matter and both
-- were learnt the hard way here: a window mid-REVEAL drops the line, and so does
-- one whose screen still says a job is running -- and a radio link releases two
-- lines a second, so a four-line answer keeps the far machine "busy" for two
-- whole seconds of wall clock. A bench that typed at it in the meantime asserted
-- against a machine that had never been told.
local function say(net, line)
	settle(net)
	net.enter(line)
end

--
-- The callsign: a file, derived, per machine, and announced by the firmware.
--

do
	local net = newRadioNet()
	local here, gate, far = callOf(net.here), callOf(net.gate), callOf(net.far)
	check("the machine has a callsign", CeroSecOS.isCallsign(here))
	check("so has the one beside it", CeroSecOS.isCallsign(gate))
	check("and the shed down the road", CeroSecOS.isCallsign(far))
	-- Per MACHINE and not per premises, which is what makes it a STATION: the
	-- telephone number is the premises's and two computers in one office share it.
	check("the two machines in the office are two stations", here ~= gate)
	eq("and they do share the one telephone line", telOf(net.here), telOf(net.gate))
	check("a callsign is not a rearrangement of the number either",
		string.find(here, string.sub(telOf(net.here), 5), 1, true) == nil)
	check("the shed is a third station", far ~= here and far ~= gate)
	-- Kentucky is the fourth call district, and that digit is a fact about the map.
	eq("every station is in the fourth district", string.sub(here, -4, -4), "4")

	-- It is a FILE, at the mode a root-owned file everybody may read wears.
	local node = CeroSecOS.systemNode(net.here:osState(), CeroSecOS.CALLSIGN_PATH)
	check("/etc/callsign is a file", node ~= nil and node.type == "file")
	eq("root's", node.owner, "root")
	eq("at 644", node.mode, CeroSecOS.CALLSIGN_MODE)

	-- The firmware announces it, under the modem.
	net.login("admin")
	check("the BIOS announces the callsign", net.glass("Callsign: " .. here))
	check("under the telephone", net.glass("Phone line: " .. telOf(net.here)))
	say(net, "cat /etc/callsign")
	net.tick(3)
	check("and it is readable by an ordinary account", net.glass(here))

	-- A machine in no building has no record, so there is nothing to derive from
	-- and no licence -- the same shape as its missing address and missing number.
	local loose = net.machine(80, 80, 0, nil)
	loose:turnOn()
	eq("a machine in no building has no callsign", callOf(loose), nil)
	_G.__world = nil
end

-- Root may change it, and that is the whole security lesson: the callsign is
-- what a station SAYS it is.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	say(net, "su root")
	say(net, "")
	say(net, "write /etc/callsign W4ZZZ")
	net.tick(3)
	eq("root wrote a new callsign", callOf(net.here), "W4ZZZ")
	say(net, "call " .. callOf(net.far))
	net.tick(3)
	check("the link is up", net.glass(CeroSecOS.TNC.connected .. callOf(net.far)))
	say(net, "admin")
	say(net, "")
	net.tick(2)
	say(net, "who")
	net.tick(3)
	check("and the far machine records the name it was given", net.glass("(W4ZZZ)"))

	-- A callsign nothing could be called is no callsign at all: the machine
	-- refuses to transmit rather than announcing rubbish.
	local other = net.machine(14, 10, 0, net.office)
	other:turnOn()
	net.aerial(other, nil, 0, 0)
	local st = other:osState()
	CeroSecOS.setData(st, CeroSecOS.rootSession(), CeroSecOS.CALLSIGN_PATH, "not-a-call", 100)
	eq("a file that is not a callsign is no callsign", callOf(other), nil)
	typeAt(net, other, "call " .. callOf(net.far))
	check("and call says so in its own name",
		ownSaid(other, CeroSecOS.CALL_NO_CALLSIGN))
	_G.__world = nil
end

--
-- The firmware's three lines about hardware. Here and not in defs_test.lua
-- because bootLines asks the core for the size of the drive, and defs_test does
-- not load the core.
--
-- The firmware's three lines about hardware, in the order it finds them in: the
-- card in a slot, the modem behind it, the TNC on the serial port.
do
	local plain = CeroSec.bootLines(nil, nil, nil)
	for i = 1, #plain do
		check("a machine with no links announces none (" .. plain[i] .. ")",
			string.find(plain[i], "Ethernet:", 1, true) == nil
			and string.find(plain[i], "Phone line:", 1, true) == nil
			and string.find(plain[i], "Callsign:", 1, true) == nil)
	end

	local full = CeroSec.bootLines("10.4.17.3", "555-0417", "KD4AXR")
	local at = {}
	for i = 1, #full do
		if string.find(full[i], "Detecting drives", 1, true) then at.disk = i end
		if full[i] == "Ethernet: eth0 10.4.17.3" then at.card = i end
		if full[i] == "Phone line: 555-0417" then at.phone = i end
		if full[i] == "Callsign: KD4AXR" then at.call = i end
		if string.find(full[i], "Booting", 1, true) then at.boot = i end
	end
	check("the card is announced", at.card ~= nil)
	check("the modem too", at.phone ~= nil)
	check("and the TNC", at.call ~= nil)
	check("the card comes after the drive", at.card > at.disk)
	check("the modem under the card", at.phone == at.card + 1)
	check("the TNC under the modem", at.call == at.phone + 1)
	check("and all three before the machine boots", at.boot > at.call)
	check("nothing was written into the template",
		CeroSec.BOOT_LINES[CeroSec.BOOT_DISK_LINE] == "Detecting drives ... hda ")

	-- A callsign with no telephone number is nothing this mod can be today -- the
	-- two come off one record -- and the line still lands in the right place
	-- rather than over the top of "Booting from hda".
	local odd = CeroSec.bootLines("10.4.17.3", nil, "KD4AXR")
	local oat = {}
	for i = 1, #odd do
		if odd[i] == "Ethernet: eth0 10.4.17.3" then oat.card = i end
		if odd[i] == "Callsign: KD4AXR" then oat.call = i end
		if string.find(odd[i], "Booting", 1, true) then oat.boot = i end
	end
	check("a callsign with no number still goes under the card",
		oat.call == oat.card + 1)
	check("and still before the boot", oat.boot > oat.call)
end

--
-- /dev/radio0: the TNC as a device.
--

do
	local net = newRadioNet()
	local set = net.aerial(net.here, { channel = 144390 })
	net.login("admin")
	say(net, "dev radio")
	net.tick(3)
	check("the TNC is a device", net.glass("radio0"))
	check("named for what it is", net.glass("ham"))
	check("with its frequency and its state", net.glass("144.390 on"))
	say(net, "cat /dev/radio0")
	net.tick(3)
	check("and cat reads the same two facts", net.glass("144.390 on"))

	-- Read-only: the knob is on the set (proof 7), so the node carries no `w` for
	-- anybody and the refusal an ordinary account gets is the MODE's. The sensor
	-- wears the same 440 for the same reason.
	say(net, "echo 145.010 > /dev/radio0")
	net.tick(3)
	check("nothing may be written to an aerial",
		net.glass("radio0: permission denied"))
	say(net, "ls -l /dev/radio0")
	net.tick(3)
	check("and the mode says so", net.glass("cr--r-----"))
	-- Root is past the mode and is refused by the VOCABULARY instead, which is
	-- where the real answer is: there is no word a machine could write to an
	-- aerial.
	say(net, "su root")
	say(net, "")
	say(net, "echo 145.010 > /dev/radio0")
	net.tick(3)
	check("and not even root has a word for one",
		net.glass("radio0: invalid value"))
	say(net, "exit")
	net.tick(2)

	-- The set itself, read through the device: switched off, and with nothing
	-- behind it.
	set.data.on = false
	say(net, "cat /dev/radio0")
	net.tick(3)
	check("a set switched off says so", net.glass("144.390 off"))
	set.data.on = true
	set.data.power = 0
	say(net, "cat /dev/radio0")
	net.tick(3)
	check("and one with a flat battery says that", net.glass("144.390 no power"))

	-- Carried away. The NUMBER is spent for the life of the machine, so the name
	-- is still mounted and still answers -- "no such device" and not "no such
	-- file", which is the difference between a set that is gone and a path
	-- somebody mistyped.
	net.world.remove(set)
	say(net, "clear")
	say(net, "dev radio")
	net.tick(3)
	check("a set that has gone is not listed", not net.glass("144.390"))
	say(net, "cat /dev/radio0")
	net.tick(3)
	check("but the number it had still answers",
		net.glass("radio0: no such device"))
	_G.__world = nil
end

-- What is NOT a TNC: a receive-only set, and one out of reach.
do
	local net = newRadioNet()
	net.aerial(net.here, { twoWay = false })
	net.login("admin")
	say(net, "dev radio")
	net.tick(3)
	check("a radio that cannot transmit is no TNC", not net.glass("radio0"))
	say(net, "cat /dev/radio0")
	net.tick(3)
	check("and nothing was ever mounted at that name",
		net.glass("cat: /dev/radio0: no such file"))
	_G.__world = nil

	local other = newRadioNet()
	other.ground(other.here)
	-- Two tiles away, and the machine is in no room the world knows: a base gets
	-- one tile and no more.
	other.aerial(other.here, nil, 2, 0)
	other.login("admin")
	say(other, "dev radio")
	other.tick(3)
	check("a set across the room is not wired to the machine",
		not other.glass("radio0"))
	-- One tile away is the desk beside it.
	other.aerial(other.here, nil, 1, 0)
	say(other, "dev radio")
	other.tick(3)
	check("and one on the next tile is", other.glass("radio0"))
	_G.__world = nil
end

-- In a building the map knows, the reach is the ROOM: a set anywhere in the
-- office is on the office's cable.
do
	local net = newRadioNet()
	local room = net.world.room("office", { { 10, 10, 0 }, { 16, 10, 0 } })
	net.world.put(net.world.square(16, 10, 0, room), fakeRadio({}))
	net.login("admin")
	say(net, "dev radio")
	net.tick(3)
	check("a set six tiles away but in the same room is the TNC",
		net.glass("radio0"))
	local _ = room
	_G.__world = nil
end

--
-- A link, end to end.
--

do
	local net = newRadioNet()
	local mine = net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	local myCall, theirCall = callOf(net.here), callOf(net.far)

	say(net, "call " .. theirCall)
	net.tick(2)
	check("the TNC answers first",
		net.glass(CeroSecOS.TNC.connected .. theirCall))
	check("and the far machine asks who is there", net.glass("login:"))
	-- No trust file is asked over the air, and this one would have been enough on
	-- the coax.
	net.put(net.far, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	say(net, "admin")
	say(net, "")
	net.tick(2)
	local shed = net.host(net.far)
	check("the prompt is the far machine's", net.glass("admin@" .. shed))
	eq("a line is taken over there", CeroSecOS.ptyCount(net.far.ptys), 1)

	-- What the far machine knows about the caller is what he said he was called.
	say(net, "who")
	net.tick(3)
	check("who names the pty", net.glass("ttyp0"))
	check("and the callsign that called", net.glass("(" .. myCall .. ")"))
	net.forget()
	say(net, "last")
	net.tick(3)
	check("last has it too", net.heard(myCall))
	check("and wtmp is where it read it",
		string.find(net.text(net.far, "/var/log/wtmp"), myCall, 1, true) ~= nil)

	-- The air. One transmission for the connect, from the CALLER's set, on the
	-- caller's frequency, with the caller's range -- and interactCodes a STRING,
	-- which is the one argument a server drops a transmission for being nil
	-- (proof 5).
	local on = heardOnAir(net.air, CeroSecOS.TNC.onAir)
	check("the connect went out over the air", on ~= nil)
	eq("naming the station called and the station calling", on.line,
		theirCall .. " de " .. myCall .. " " .. CeroSecOS.TNC.onAir)
	eq("from the transmitting set's own tile", on.x, net.here.x)
	eq("and its own y", on.y, net.here.y)
	eq("on the frequency the link was made on", on.channel, 144390)
	eq("with the set's own transmit range", on.range, 7500)
	eq("not a television", on.tv, false)
	eq("and interactCodes a string, never nil", type(on.codes), "string")
	local _ = mine

	settle(net)
	net.forget()
	say(net, "exit")
	net.tick(3)
	check("the link says it is over in the TNC's own word",
		net.heard(CeroSecOS.TNC.disconnected))
	check("and not in rlogin's", not net.heard("Connection closed."))
	eq("the line is given back", CeroSecOS.ptyCount(net.far.ptys), 0)
	check("and the county heard that too",
		heardOnAir(net.air, CeroSecOS.TNC.disconnected) ~= nil)
	_G.__world = nil
end

-- ~. hangs up a radio link exactly as it hangs up a call: one program holds the
-- far end, so there is one escape.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	say(net, "call " .. callOf(net.far))
	net.tick(2)
	say(net, "admin")
	say(net, "")
	net.tick(2)
	check("the link is up", net.glass("admin@" .. net.host(net.far)))
	net.forget()
	say(net, "~.")
	net.tick(3)
	check("~. hangs up", net.heard(CeroSecOS.TNC.disconnected))
	eq("the line is given back", CeroSecOS.ptyCount(net.far.ptys), 0)
	check("and the glass is this machine's again",
		net.glass("admin@" .. net.host(net.here)))
	_G.__world = nil
end

--
-- The refusals, one rule at a time. Every one of them is the TNC's own line,
-- except the two the machine can see without transmitting.
--

do
	local net = newRadioNet()
	net.login("admin")
	local theirCall = callOf(net.far)

	-- No aerial at all: the machine can see that for itself.
	say(net, "call " .. theirCall)
	net.tick(3)
	check("a machine with no set says so in its own name",
		net.glass(CeroSecOS.CALL_NO_RADIO))
	check("having never transmitted", #net.air == 0)
	check("and opened no line over there", net.far.ptys == nil)

	local mine = net.aerial(net.here)
	local theirs = net.aerial(net.far)

	-- This machine's own set switched off: a TNC cannot tell, so it transmits
	-- into a dead radio and the retries run out.
	mine.data.on = false
	say(net, "call " .. theirCall)
	net.tick(3)
	check("a set of one's own that is off is silence, not a diagnosis",
		net.glass(CeroSecOS.TNC.retry))
	mine.data.on = true

	-- The far set switched off.
	theirs.data.on = false
	say(net, "call " .. theirCall)
	net.tick(3)
	check("a far set that is off is the same silence", net.glass(CeroSecOS.TNC.retry))
	theirs.data.on = true

	-- The far set with no power.
	theirs.data.power = 0
	say(net, "call " .. theirCall)
	net.tick(3)
	check("and so is a flat battery over there", net.glass(CeroSecOS.TNC.retry))
	theirs.data.power = 1

	-- Two frequencies are two conversations.
	theirs.data.channel = 145010
	say(net, "call " .. theirCall)
	net.tick(3)
	check("the wrong frequency is silence too", net.glass(CeroSecOS.TNC.retry))
	theirs.data.channel = 144390

	-- Out of range: the SMALLER of the two ranges decides, so one narrow set is
	-- enough to break a link two wide ones would have carried.
	theirs.data.range = 10
	say(net, "call " .. theirCall)
	net.tick(3)
	check("out of range is silence", net.glass(CeroSecOS.TNC.retry))
	theirs.data.range = 7500

	-- A callsign nobody answers to.
	say(net, "call W4ZZZ")
	net.tick(3)
	check("a station the county has not got is the same line",
		net.glass(CeroSecOS.TNC.retry))

	-- A machine switched off cannot answer.
	net.far:turnOff()
	say(net, "call " .. theirCall)
	net.tick(3)
	check("nor can a computer that is switched off", net.glass(CeroSecOS.TNC.retry))
	_G.__world = nil
end

-- Calling oneself, and the shape of the word.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.login("admin")
	say(net, "call " .. callOf(net.here))
	net.tick(3)
	check("a station cannot connect to itself", net.glass(CeroSecOS.TNC.retry))
	say(net, "call kd4axr")
	net.tick(3)
	check("a callsign in lower case is not one", net.glass("call: usage: call CALLSIGN"))
	say(net, "call")
	net.tick(3)
	check("and neither is nothing at all", net.glass("call: usage: call CALLSIGN"))
	say(net, "call 555-0142")
	net.tick(3)
	check("nor a telephone number", net.glass("call: usage: call CALLSIGN"))
	_G.__world = nil
end

-- THE UNLOADED CHUNK, which is the one thing the radio is worse at than the
-- telephone: a radio is a tile, and a tile the streamer has not brought in does
-- not exist. The far machine's DISK is still here -- it answers ruptime and it
-- answers cu -- and its aerial is not.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.login("admin")
	-- No square in the world at the shed at all, which is exactly what an
	-- unloaded chunk answers.
	say(net, "call " .. callOf(net.far))
	net.tick(3)
	check("a station whose chunk is not loaded cannot be raised",
		net.glass(CeroSecOS.TNC.retry))
	-- And the same machine over the telephone, in the same breath: the disk is
	-- here and the link that does not need a tile still reaches it.
	say(net, "cu " .. telOf(net.far))
	ringOut(net)
	check("while the telephone reaches it perfectly well", net.glass("CONNECT 2400"))
	_G.__world = nil
end

-- ONE LINK PER RADIO, both ends. Two machines in one room share a set, so the
-- second one is not getting on the air.
do
	local net = newRadioNet()
	local room = net.world.room("office", { { 10, 10, 0 }, { 12, 10, 0 } })
	net.world.put(net.world.square(10, 10, 0, room), fakeRadio({}))
	net.aerial(net.far)
	net.login("admin")
	say(net, "call " .. callOf(net.far))
	net.tick(2)
	say(net, "admin")
	say(net, "")
	net.tick(2)
	check("the first machine has the air", net.glass("admin@" .. net.host(net.far)))
	-- The other computer in the room, on the same aerial.
	typeAt(net, net.gate, "call " .. callOf(net.far))
	check("and the one beside it is told the set is busy",
		ownSaid(net.gate, CeroSecOS.TNC.busy))
	local _ = room
	_G.__world = nil
end

-- A link that goes away underneath a session: somebody switches the far set off
-- while somebody else is typing at it. The next keystroke is what finds out, and
-- what it reads is not the same line as a hangup.
do
	local net = newRadioNet()
	net.aerial(net.here)
	local theirs = net.aerial(net.far)
	net.login("admin")
	say(net, "call " .. callOf(net.far))
	net.tick(2)
	say(net, "admin")
	say(net, "")
	net.tick(2)
	check("the link is up", net.glass("admin@" .. net.host(net.far)))
	net.forget()
	theirs.data.on = false
	say(net, "hostname")
	net.tick(3)
	check("the keystroke finds the link gone", net.heard(CeroSecOS.TNC.retry))
	check("and not a hangup", not net.heard(CeroSecOS.TNC.disconnected))
	eq("the line is given back", CeroSecOS.ptyCount(net.far.ptys), 0)
	check("and the glass is this machine's again",
		net.glass("admin@" .. net.host(net.here)))
	_G.__world = nil
end

-- call wants a terminal, exactly as rlogin and cu do: a crontab line that
-- called would be a session nobody could ever type at.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	net.crontab(net.here, "admin", "* * * * * call " .. callOf(net.far))
	net.minute(2)
	eq("a crontab call opens no line on the far machine",
		CeroSecOS.ptyCount(net.far.ptys), 0)
	local mail = net.text(net.here, "/var/mail/admin")
	check("and the mail says why", mail ~= nil and
		string.find(mail, "call: not a terminal", 1, true) ~= nil)
	check("having never transmitted either", #net.air == 0)
	say(net, "call " .. callOf(net.far) .. " &")
	net.tick(4)
	check("a backgrounded call says it has no terminal either",
		net.heard("call: not a terminal"))
	_G.__world = nil
end

-- 1200 baud: half what a telephone call carries, and the far machine as fast as
-- it ever was.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	say(net, "call " .. callOf(net.far))
	net.tick(2)
	say(net, "admin")
	say(net, "")
	net.tick(2)
	local pty = CeroSecOS.ptyList(net.far.ptys)[1]
	check("the session is a radio link", pty ~= nil and type(pty.radio) == "table")
	eq("and it came from this station", pty.radio.call, callOf(net.here))
	check("and not down a telephone line", pty.phone == nil)

	local before = #pty.console.lines
	say(net, "for i in 1 2 3 4 5 6 7 8 9 10; do echo $i; done")
	net.tick(9)
	local after = #pty.console.lines - before
	-- Four and not two, and written out rather than read off the constant: these
	-- passes straddle a second, so two of the air's seconds may land. Ten lines at
	-- the machine's own twenty a second would all be here at once, and four a
	-- second is what the TELEPHONE carries.
	check("a second on the air carries about two lines (" .. after .. ")",
		after >= 1 and after <= 4)
	net.tick(60)
	check("and the whole of it arrives in the end", net.glass("10"))
	_G.__world = nil
end

--
-- The script that threw a player off the machine
--
-- Typed at the glass, as root, with the file exactly as it was written: a usage
-- check, an `exit 1`, and a loop over the lights. The bug was that the usage
-- line arrived and then the console logged out to `login:` -- because `exit`
-- inside a file was being judged as `exit` typed at the prompt. What is asserted
-- here is what is PAINTED: the usage line, a prompt back, and root still at it.
--
do
	local kit = mockupWorld()
	_G.__world = kit.world

	local bench = newBench()
	bench.login("admin")
	bench.enter("su root")
	bench.enter("")
	bench.frame()
	eq("root is at the glass", bench.object.console.user, "root")

	bench.script("/home/admin/lights.sh", table.concat({
		"#!/bin/sh",
		'if [ "$1" != on -a "$1" != off ]; then',
		'  echo "usage: lights.sh on|off"',
		"  exit 1",
		"fi",
		"for l in $(ls /dev | grep light); do",
		"  dev $l $1",
		"done",
	}, "\n"))
	bench.enter("cd /home/admin")
	bench.frame()

	-- The BOTTOM of the glass, which is where a logout shows. The login prompt
	-- this session began at is still up in the scrollback and always will be, so
	-- "is there a `login:` anywhere" is not the question -- what the machine is
	-- asking for NOW is.
	local function bottom()
		local painted = bench.glass()
		for i = #painted, 1, -1 do
			local text = painted[i]
			if type(text) == "string" and text ~= "" then return text end
		end
		return ""
	end

	-- No argument: the usage line, and nothing else.
	bench.enter("./lights.sh")
	bench.frame()
	check("the usage line is on the glass", bench.painted("usage: lights.sh on|off"))
	-- The prompt is back and it is root's, which is the whole bug: a logout
	-- would have left `login:` at the bottom of the glass and no prompt at all.
	eq("the bottom of the glass is root's prompt again",
		string.sub(bottom(), 1, 5), "root@")
	check("and not a login prompt", string.find(bottom(), "login:", 1, true) == nil)
	eq("the session is still root's", bench.object.console.user, "root")
	eq("the window is still at a shell", bench.window.mode, "shell")
	eq("and $? is the status the script gave", bench.object.console.status, 1)

	-- Nothing was touched on the way out: the lights are as the world made them.
	eq("the office light is still on", kit.light0.activated, true)
	eq("and the hallway light still off", kit.light1.activated, false)

	-- And the same file with its argument does the job it was written for. More
	-- than one pass this time: the loop is a job like any other and the player's
	-- own pass is only the first of them.
	--
	-- `ls /dev | grep light` catches the two lights and nothing else, because a
	-- pipe is not a screen: ls writes one name a line down one (rung 6b), so the
	-- loop is handed light0 and light1 and not whatever shared a packed row with
	-- them. Before that it was handed rows, said "invalid value" at a door and a
	-- window on its way past, and came back with the last `dev`'s status.
	bench.enter("./lights.sh off")
	bench.tick(8)
	eq("the office light went off", kit.light0.activated, false)
	eq("the hallway light stayed off", kit.light1.activated, false)
	check("and dev said what it read back", bench.painted("light0: off"))
	check("and again for the other one", bench.painted("light1: off"))
	-- Nothing but the lights was reached: a door in the same directory is not
	-- something the loop ever names now.
	check("no door was asked for a light's word", not bench.painted("invalid value"))
	eq("so the script came back successful", bench.object.console.status, 0)
	eq("the bottom of the glass is a prompt", string.sub(bottom(), 1, 5), "root@")
	eq("root is still standing there", bench.object.console.user, "root")

	bench.enter("./lights.sh on")
	bench.tick(8)
	eq("on turns them on", kit.light0.activated, true)
	eq("both of them", kit.light1.activated, true)
	eq("root is still there", bench.object.console.user, "root")
	eq("and still at a shell", bench.window.mode, "shell")

	_G.__world = nil
end


--
-- The rest of the audit: every order a job with no terminal can give
--
-- rlogin was the one that handed a session over. The same question asked of
-- every other order the engine can hand the machine, from a crontab line -- the
-- job with nobody in front of it that is easiest for a player to write:
--
--   prompt (su, passwd, sudo)  answered: nobody can be asked, so it is not asked
--   clear                      withheld: the glass is not this job's to wipe
--   edit                       refused already ("edit: not a terminal")
--   exit                       ends the line, never the session (main's own fix)
--   fg                         refused by fg itself, before any order
--   rsh                        runs, detached (the section above)
--   rcp, sleep                 no screen in them at all
--   schedule, shutdown, reboot  cron's to give, and a real cron gives them
--
-- The prompt one was a machine-killer and not a nuisance: a question that could
-- never be answered left the job waiting for ever, and four of those are every
-- job slot the machine has -- after `* * * * * su root` had run four times, that
-- computer could not run a single command again.
--

do
	local net = newNet()
	net.login("admin")

	local function fromCron(line)
		net.crontab(net.here, "admin", "* * * * * " .. line)
		net.minute(2)
		net.crontab(net.here, "admin", "")
		local mail = net.text(net.here, "/var/mail/admin") or ""
		CeroSecOS.writeFile(net.here:osState(), CeroSecOS.rootSession(),
			"/var/mail/admin", "", false, 100)
		local live = 0
		local book = net.here.jobs
		if book ~= nil then live = #book.list end
		return mail, live
	end

	-- su, passwd and sudo: each signs the refusal with its own name, which is the
	-- shape every refusal on this machine has.
	local mail, live = fromCron("su root")
	check("su from cron says it has no terminal",
		string.find(mail, "su: not a terminal", 1, true) ~= nil)
	eq("and leaves no job waiting for an answer", live, 0)
	eq("and nobody was made root", net.here.console.user, "admin")

	mail = fromCron("passwd admin")
	check("passwd from cron says the same",
		string.find(mail, "passwd: not a terminal", 1, true) ~= nil)

	mail = fromCron("sudo cat /etc/shadow")
	check("and so does sudo",
		string.find(mail, "sudo: not a terminal", 1, true) ~= nil)
	check("and the file it wanted is not in the mail",
		string.find(mail, "root:", 1, true) == nil)

	-- Four of them, which is every job slot there is: the machine is still a
	-- machine afterwards.
	fromCron("su root")
	fromCron("su root")
	fromCron("su root")
	fromCron("su root")
	net.enter("echo alive")
	net.tick(3)
	check("four unanswerable questions later the machine still runs a line",
		net.glass("alive"))

	-- clear: the glass a survivor is reading is not a cron line's to wipe.
	net.enter("echo keep-me")
	net.tick(3)
	check("the line is on the glass", net.glass("keep-me"))
	local before = #net.here.console.lines
	check("the glass has lines on it", before > 0)
	fromCron("clear")
	eq("a cron clear leaves every one of them", #net.here.console.lines, before)
	check("including the one that was being read", net.glass("keep-me"))
	-- And the word still clears it when a pair of hands types it.
	net.enter("clear")
	net.tick(3)
	check("typed at the glass it still clears", not net.glass("keep-me"))

	-- edit, which the machine refused before any of this was written: the file has
	-- to exist, or the refusal is about the file and not about the terminal.
	net.put(net.here, "/home/admin/notes", "hello", 644, "admin")
	mail = fromCron("edit /home/admin/notes")
	check("edit from cron says it has no terminal",
		string.find(mail, "edit: not a terminal", 1, true) ~= nil)

	-- exit, which main's own fix is about: a cron line is not a way to log the
	-- console out.
	net.enter("echo still-here")
	net.tick(3)
	fromCron("exit")
	eq("a cron exit leaves the account at the glass", net.here.console.user, "admin")
	check("and the glass it was reading", net.glass("still-here"))

	-- A pipeline in the BACKGROUND, which is the other way to have no keyboard: a
	-- stage of it has no more of one than the pipeline. `sudo echo hi | cat` asks
	-- at the prompt, and the same line with a `&` behind it has nobody to ask --
	-- so it is told, rather than waiting for ever in a job slot.
	net.forget()
	net.enter("sudo echo hi | cat &")
	net.tick(10)
	check("a backgrounded pipeline that asks is told there is no terminal",
		net.heard("sudo: not a terminal"))
	eq("and nothing is left waiting for an answer",
		net.here.jobs == nil or #net.here.jobs.list, 0)
	-- The same line in the foreground still asks, because somebody is there.
	net.forget()
	net.enter("sudo echo hi | cat")
	net.tick(4)
	check("in the foreground it asks for the password",
		net.glass("[sudo] password for admin:"))
	net.escape()
	net.tick(4)

	-- fg: refused by fg itself, which never gets as far as an order.
	mail = fromCron("fg")
	check("fg from cron has no job to bring forward",
		string.find(mail, "fg: no current job", 1, true) ~= nil)
end


--
-- The floppy drive, all the way round (rung 4e)
--
-- The one thing neither os_test nor the item-script bench can prove: a disk that
-- goes from a survivor's pocket into a machine, gets written on, comes back out
-- as an item, and is read on a DIFFERENT computer. Every piece of that is green
-- on its own; what is asserted here is the round trip.
--
-- The inventory is faked to exactly what the server touches -- an id, a full
-- type, a modData table and a container -- because that is the whole of the game
-- API this path uses, and a fake with more in it would be a fake asserting
-- against itself.
--

local function newInventory()
	local inv = { items = {}, nextID = 100 }
	function inv:add(fullType, data)
		self.nextID = self.nextID + 1
		local item = {
			id = self.nextID,
			type = fullType,
			data = data or {},
			getID = function(self) return self.id end,
			getFullType = function(self) return self.type end,
			hasModData = function(self) return true end,
			getModData = function(self) return self.data end,
			getContainer = function(self) return inv end,
		}
		self.items[#self.items + 1] = item
		return item
	end
	function inv:AddItem(fullType) return self:add(fullType, {}) end
	function inv:Remove(item)
		for i = #self.items, 1, -1 do
			if self.items[i] == item then table.remove(self.items, i) end
		end
	end
	function inv:getItemWithIDRecursiv(id)
		for i = 1, #self.items do
			if self.items[i].id == id then return self.items[i] end
		end
		return nil
	end
	function inv:getFirstTypeRecurse(fullType)
		for i = 1, #self.items do
			if self.items[i].type == fullType then return self.items[i] end
		end
		return nil
	end
	return inv
end

-- Give a bench an inventory and a record of what the drive was heard to do.
local function wireDrive(bench)
	local inv = newInventory()
	bench.player.getInventory = function() return inv end
	bench.inv = inv
	bench.sounds = {}
	bench.object.playSound = function(_, name) bench.sounds[#bench.sounds + 1] = name end
	function bench.heardSound(name)
		for i = 1, #bench.sounds do
			if bench.sounds[i] == name then return true end
		end
		return false
	end
	function bench.send(command, args)
		args = args or {}
		args.x, args.y, args.z = 10, 10, 0
		CCeroSecSystem.instance:sendCommand(bench.player, command, args)
		bench.frame()
	end
	return inv
end

do
	local bench = newBench()
	local inv = wireDrive(bench)
	bench.login("admin")

	-- Nothing in the slot: no device, and the machine says so in the ordinary way.
	bench.enter("ls /dev")
	bench.frame()
	check("a machine with an empty slot has no drive file", not bench.painted("fd0"))
	bench.enter("newfs /dev/fd0")
	bench.frame()
	check("and newfs says so", bench.painted("newfs: /dev/fd0: no such file"))

	-- A blank disk out of an office drawer.
	local disk = inv:add("CeroSec.FloppyRed")
	eq("he is carrying one", #inv.items, 1)
	bench.send("insertfloppy", { item = disk:getID() })

	eq("the disk left his hands", #inv.items, 0)
	check("and the drive was heard to take it", bench.heardSound("CeroSecInsertDisc"))
	eq("the machine knows there is one in it", bench.object:hasDisk(), true)
	eq("and the client is told the one bit it needs", bench.object.disk, true)
	eq("and its own copy has it", bench.client.disk, true)
	eq("so its menu would offer Eject", CeroSec.diskInDrive(bench.client), true)

	-- And now there is a drive to talk to.
	bench.enter("ls /dev")
	bench.frame()
	check("the drive file is there", bench.painted("fd0"))
	bench.enter("cat /dev/fd0")
	bench.frame()
	check("and it is blank", bench.painted("blank"))

	-- Format, mount, write.
	bench.enter("newfs /dev/fd0")
	bench.frame()
	check("newfs printed its summary", bench.painted("/dev/fd0: 4096 bytes, 32 inodes"))
	bench.enter("mount /dev/fd0 /mnt")
	bench.enter("echo the pumps are at the depot > /mnt/notes.txt")
	bench.enter("cat /mnt/notes.txt")
	bench.frame()
	check("the file is on the disk", bench.painted("the pumps are at the depot"))
	bench.enter("df")
	bench.frame()
	check("df names the disk", bench.painted("fd0"))
	bench.enter("umount /mnt")
	bench.frame()
	-- Asserted on the machine and not on the glass: every line the survivor typed
	-- is still on the screen above him, echoes and all, so "notes.txt is not
	-- painted" is a question the console cannot answer honestly.
	local unmounted = bench.object:osState()
	eq("nothing is mounted", CeroSecOS.mountTable(unmounted), nil)
	eq("and /mnt is the empty directory it ships as",
		CeroSecOS.countEntries(CeroSecOS.systemNode(unmounted, CeroSecOS.MNT_PATH)), 0)

	-- Out it comes, in the shell it went in as, with everything on it.
	bench.send("ejectfloppy")
	eq("the disk is back in his hands", #inv.items, 1)
	eq("in the colour it went in as", inv.items[1]:getFullType(), "CeroSec.FloppyRed")
	check("and the drive was heard to give it back", bench.heardSound("CeroSecEjectDisc"))
	eq("the slot is empty", bench.object:hasDisk(), false)
	-- A real false and not a nil, and then the client's OWN copy, which is the
	-- half the flag exists for: the disk was back in his hands and the menu went
	-- on greying Insert with "the drive is full" and offering Eject, because a nil
	-- is not something the update carries (the merge above).
	eq("and the client is told", bench.object.disk, false)
	eq("and its own copy says the slot is empty", bench.client.disk, false)
	eq("so its menu offers Insert and not Eject",
		CeroSec.diskInDrive(bench.client), false)
	local carried = inv.items[1]:getModData()
	eq("the item carries the disk's own version", carried.v, CeroSecOS.FLOPPY_VERSION)
	check("and its filesystem", type(carried.fs) == "table")
	check("with the file on it", carried.fs.children["notes.txt"] ~= nil)

	eq("and there is no drive file to find any more",
		CeroSecOS.systemNode(bench.object:osState(), CeroSecOS.FD_PATH), nil)

	-- One at a time. A second disk in his pocket goes nowhere while the first is
	-- in the drive.
	bench.send("insertfloppy", { item = inv.items[1]:getID() })
	eq("the first went back in", bench.object:hasDisk(), true)
	local second = inv:add("CeroSec.FloppyBlue")
	bench.send("insertfloppy", { item = second:getID() })
	eq("the second stayed in his hands", #inv.items, 1)
	eq("and it is the one he still has", inv.items[1]:getFullType(), "CeroSec.FloppyBlue")

	-- Ejecting a MOUNTED disk unmounts it first and loses nothing: every write is
	-- finished by the time the command that made it answered.
	bench.enter("mount /dev/fd0 /mnt")
	bench.enter("echo and the keys are under the mat >> /mnt/notes.txt")
	bench.frame()
	bench.send("ejectfloppy")
	eq("it came out", bench.object:hasDisk(), false)
	local state = bench.object:osState()
	eq("with nothing left mounted", CeroSecOS.mountTable(state), nil)
	eq("and /mnt is a plain empty directory again",
		CeroSecOS.countEntries(CeroSecOS.systemNode(state, CeroSecOS.MNT_PATH)), 0)
	local red = nil
	for i = 1, #inv.items do
		if inv.items[i]:getFullType() == "CeroSec.FloppyRed" then red = inv.items[i] end
	end
	check("the red disk is back", red ~= nil)
	local lines = red:getModData().fs.children["notes.txt"].data
	check("with BOTH lines on it", string.find(lines, "under the mat", 1, true) ~= nil
		and string.find(lines, "at the depot", 1, true) ~= nil)

	--
	-- The other machine.
	--
	local other = newBench()
	local otherInv = wireDrive(other)
	other.login("admin")
	-- The very same item, carried across town: the same table the first machine
	-- handed back, put into the second machine's world.
	local moved = otherInv:add(red:getFullType(), red:getModData())
	other.send("insertfloppy", { item = moved:getID() })
	eq("the second machine took it", other.object:hasDisk(), true)

	other.enter("cat /dev/fd0")
	other.frame()
	check("and it is a formatted disk, not a blank one", other.painted("ready"))
	other.enter("mount /dev/fd0 /mnt")
	other.enter("cat /mnt/notes.txt")
	other.frame()
	check("the note is readable on the other machine",
		other.painted("the pumps are at the depot"))
	check("both lines of it", other.painted("and the keys are under the mat"))

	-- And the first machine has nothing left of it.
	eq("the first machine's drive is empty", bench.object:hasDisk(), false)
	eq("and nothing was left behind in its /mnt",
		CeroSecOS.countEntries(
			CeroSecOS.systemNode(bench.object:osState(), CeroSecOS.MNT_PATH)), 0)
end

--
-- A computer picked up with a disk in it
--
-- The disk stays in the drive, because that is what a disk in a drive does. It
-- rides in movableData with the filesystem, which is what vanilla's own pickup
-- and placement copy (ISMoveableSpriteProps.lua:1300 and :2270).
--
do
	local bench = newBench()
	local inv = wireDrive(bench)
	bench.login("admin")

	-- A fake IsoObject, with the one thing the mirror needs: a modData table that
	-- survives between calls, the way the game's does.
	local modData = {}
	local iso = {
		getModData = function() return modData end,
		hasModData = function() return true end,
		transmitModData = function() end,
		getSpriteName = function() return CeroSec.SPRITES_OFF["S"] end,
		setSpriteFromName = function() end,
		transmitUpdatedSpriteToClients = function() end,
	}
	bench.object.getIsoObject = function() return iso end

	local disk = inv:add("CeroSec.FloppyGreen")
	bench.send("insertfloppy", { item = disk:getID() })
	bench.enter("newfs /dev/fd0")
	bench.enter("mount /dev/fd0 /mnt")
	bench.enter("echo generator fuel: four cans > /mnt/log.txt")
	bench.frame()

	-- What vanilla copies into the item when the computer is picked up.
	bench.object:toModData(iso)
	local mirror = modData.movableData[CeroSec.MOVABLE_DATA_KEY]
	check("the mirror carries the machine's own state", type(mirror.os) == "table")
	check("with the disk still in its drive", type(mirror.os.floppy) == "table")
	check("and the file on the disk",
		mirror.os.floppy.fs.children["log.txt"] ~= nil)
	eq("and the shell it goes back into", mirror.os.fdtype, "CeroSec.FloppyGreen")

	-- Put down again. The power went with the pickup, so nothing is mounted any
	-- more -- which is what a reboot does on any machine -- and the disk is still
	-- in the slot.
	bench.object:resetForPlacement(iso)
	eq("the machine came back off", bench.object.on, false)
	local state = bench.object:osState()
	check("the disk is still in the drive", CeroSecOS.floppyOf(state) ~= nil)
	eq("nothing is mounted any more", CeroSecOS.mountTable(state), nil)
	eq("and the client is still told there is a disk in it", bench.object.disk, true)
	eq("in its own copy too", bench.client.disk, true)

	-- Switched back on, one `mount` is the whole of the way back.
	bench.object.on = true
	bench.object.console = CeroSec.newConsole()
	bench.object.consoleChecked = true
	bench.login("admin")
	bench.enter("mount /dev/fd0 /mnt")
	bench.enter("cat /mnt/log.txt")
	bench.frame()
	check("and the note is still there", bench.painted("generator fuel: four cans"))
end

--
-- Nothing a client sends about a disk is believed
--
do
	local bench = newBench()
	local inv = wireDrive(bench)
	bench.login("admin")

	-- An id that names nothing.
	bench.send("insertfloppy", { item = 999 })
	eq("an id that names nothing inserts nothing", bench.object:hasDisk(), false)
	-- An id that names something that is not a disk.
	local book = inv:add("CeroSec.ManualUser")
	bench.send("insertfloppy", { item = book:getID() })
	eq("a book is not a disk", bench.object:hasDisk(), false)
	eq("and it is still in his hands", #inv.items, 1)
	-- No id at all.
	bench.send("insertfloppy", {})
	eq("a packet with no item in it inserts nothing", bench.object:hasDisk(), false)

	-- A disk whose contents will not pass the engine's own gate: refused at the
	-- slot, and left in his hands rather than eaten. What arrives there is a table
	-- off a save file or off a client, and it is walked on every command from then
	-- on, so the ceilings are asked here.
	local forged = inv:add("CeroSec.FloppyBlue", { v = 1, fs = { type = "dir",
		owner = "root", mode = 755, children = {
			big = { type = "file", owner = "root", mode = 644,
				data = string.rep("x", CeroSecOS.FLOPPY_BYTES + 1) },
		} } })
	bench.send("insertfloppy", { item = forged:getID() })
	eq("a forged disk is refused", bench.object:hasDisk(), false)
	eq("and stays in his hands", #inv.items, 2)
	-- A disk of a version this machine does not know.
	local future = inv:add("CeroSec.FloppyBlue", { v = 99 })
	bench.send("insertfloppy", { item = future:getID() })
	eq("so is one from a version nobody here knows", bench.object:hasDisk(), false)

	-- Ejecting an empty drive gives him nothing.
	local had = #inv.items
	bench.sounds = {}
	bench.send("ejectfloppy")
	eq("an empty drive hands nothing back", #inv.items, had)
	check("and says nothing about it", not bench.heardSound("CeroSecEjectDisc"))

	-- A player who is not standing at the machine gets nothing either.
	local away = bench.player.getX
	bench.player.getX = function() return 40.5 end
	local good = inv:add("CeroSec.FloppyBlue")
	bench.send("insertfloppy", { item = good:getID() })
	eq("a player across the room inserts nothing", bench.object:hasDisk(), false)
	bench.player.getX = away
	bench.send("insertfloppy", { item = good:getID() })
	eq("and the same player standing at it does", bench.object:hasDisk(), true)
end


--
-- The drive keeps a disk no slot would take
--
-- A machine that runs on a disk has to be able to hand it out, or the player is
-- left holding one nobody will accept with nothing on any screen to say why. So
-- the refusal is made where he can still do something: an over-ceiling disk does
-- not leave the drive. Nothing the write path can do makes one -- this is the belt
-- under that -- and what it catches is a state with a way out of it: the disk is
-- still in the machine, `df` says what is wrong, and one `rm` fixes it.
--
do
	local bench = newBench()
	local inv = wireDrive(bench)
	bench.login("root")

	-- Forged past the disk's own byte ceiling, straight onto the machine, which is
	-- the one way such a disk can exist at all.
	local fs = CeroSecOS.newDir("root", 755)
	fs.children.a = CeroSecOS.newFile("root", 644, string.rep("x", CeroSecOS.MAX_FILE_BYTES))
	fs.children.b = CeroSecOS.newFile("root", 644, string.rep("x", CeroSecOS.MAX_FILE_BYTES))
	local state = bench.object:osState()
	state.floppy = { v = CeroSecOS.FLOPPY_VERSION, fs = fs }
	state.fdtype = "CeroSec.FloppyRed"
	bench.object:syncDisk()

	-- The machine runs on it perfectly well.
	eq("the machine still boots", CeroSecOS.validate(state), true)
	bench.enter("mount /dev/fd0 /mnt")
	bench.enter("ls /mnt")
	bench.frame()
	check("and reads it", bench.painted("a"))
	bench.enter("df")
	bench.frame()
	check("df says what is wrong with it", bench.painted("fd0"))
	bench.enter("echo x > /mnt/c")
	bench.frame()
	check("and every write says so", bench.painted("disk full"))

	-- But it does not come out.
	bench.sounds = {}
	bench.send("ejectfloppy")
	eq("the drive kept it", bench.object:hasDisk(), true)
	eq("and handed him nothing", #inv.items, 0)
	check("and made no sound it had not earned",
		not bench.heardSound("CeroSecEjectDisc"))
	-- Nor is it a gesture that says nothing: the machine has a screen of its own
	-- and the drive talks on it, or the player is left with a menu entry that does
	-- nothing for a reason he cannot reach.
	bench.frame()
	-- And the line carries the REASON: two of the four things that keep a disk in
	-- the drive are not "over a ceiling", and a line that names the wrong trouble
	-- sends the player to a `df` that shows him nothing wrong.
	check("the drive said why on the glass",
		bench.painted(CeroSecOS.fdKeptLine("floppy: disk full")))
	check("and the reason is in it", bench.painted("disk full"))
	-- And the mount it was under is still up: a refused eject is a gesture that did
	-- nothing at all, not one that got half way.
	eq("nothing was unmounted", CeroSecOS.mountTable(bench.object:osState()) ~= nil, true)
	-- `ls` and not `cat`: the file is four thousand bytes of one character and the
	-- machine drains its output at twenty lines a second, so a cat here would still
	-- be printing when the next line was typed.
	bench.enter("ls -l /mnt")
	bench.frame()
	check("and the disk still reads", bench.painted("4096"))

	-- One rm is the way out, and then it comes out and goes back in.
	bench.sounds = {}
	bench.enter("rm /mnt/b")
	bench.frame()
	bench.send("ejectfloppy")
	eq("now it comes out", bench.object:hasDisk(), false)
	check("with the sound of it", bench.heardSound("CeroSecEjectDisc"))
	eq("into his hands", #inv.items, 1)
	eq("in the shell it was in", inv.items[1]:getFullType(), "CeroSec.FloppyRed")
	-- And every slot in the world takes it, which is the invariant the whole of
	-- this is for: a disk a machine hands out is a disk a machine accepts.
	local other = newBench()
	local otherInv = wireDrive(other)
	other.login("admin")
	local moved = otherInv:add(inv.items[1]:getFullType(), inv.items[1]:getModData())
	other.send("insertfloppy", { item = moved:getID() })
	eq("the next machine took it", other.object:hasDisk(), true)
	other.enter("mount /dev/fd0 /mnt")
	other.enter("ls /mnt")
	other.frame()
	check("with the file still on it", other.painted("a"))
end

--
-- 42. The chunk that went away (rung 6d)
--
-- "When I go far, some of my computers get shut down; I come back and they are
-- off." The cause was the minute sweep in SCeroSecSystem: hasPower is asked of
-- the machine's SQUARE, a chunk the streamer has taken away has none, and the
-- sweep read "no square" as "no wire in the room" and switched the machine off
-- -- every computer the survivor had walked away from, once a minute, for ever.
--
-- The rule now, and it is vanilla's own habit with a global object it cannot see
-- (SCampfireSystem.lua:157-159 skips a campfire whose square is gone -- "and
-- still there, I mean not destroy because of streaming" -- while
-- lowerFuelAmount:135-138 goes on burning its fuel regardless): a machine out of the
-- world keeps the state it had. It stays on, it keeps its jobs and its crontab,
-- and it keeps answering the wire, because none of the three is a thing in the
-- world. Only what the world owns is gone: /dev, the sensor heads, and the power
-- question itself -- and the power question is asked again, at once, the moment
-- the chunk comes back.
--
-- The event a bench cannot see is the one that does NOT fire. A chunk unloading
-- does not fire Events.OnObjectAboutToBeRemoved: the only two callers of that
-- event in 42.20.4 are IsoGridSquare.RemoveTileObject (javap'd:
-- LuaEventManager.triggerEvent at offset 177 of RemoveTileObject(IsoObject,
-- boolean)) and the RemoveItemFromSquarePacket, i.e. a player or the network
-- taking the object off its square. IsoChunk never calls RemoveTileObject at all;
-- what it fires when it lets its squares go is "ReuseGridsquare"
-- (IsoChunk.doReuseGridsquares:3044). So the vanilla handler that removes the Lua
-- object -- and with it the disk, the jobs and the sessions -- runs when the
-- computer is picked up or smashed, and never because the player walked away.
--

do
	-- The corner of the office the player's own machine stands in (net.office up
	-- in newNet), so the streamed machine is in the same building and therefore
	-- on the same wire: the Ethernet rule is one building.
	local OFFICE_X, OFFICE_Y = 400, 700

	-- One more machine on a real newNet, with everything the WORLD owns behind a
	-- single switch: its square, its iso object, the room its devices are in and
	-- the cell that answers for its tiles. machine() up in newNet stubs hasPower
	-- and syncSprite, because the benches above it are about the wire; here both
	-- stubs come off and the real questions are asked of a real square, which is
	-- the whole subject of this section.
	local function streamed(net, x, y)
		local chunk = { loaded = true, powered = true, told = 0, sprites = {} }

		local function newSquare(sx, sy, objects)
			local sq = { objects = objects or {}, items = {}, bodies = {} }
			sq.getX = function() return sx end
			sq.getY = function() return sy end
			sq.getZ = function() return 0 end
			sq.getRoom = function() return chunk.room end
			sq.getBuilding = function() return chunk.building end
			sq.getObjects = function() return javaList(sq.objects) end
			sq.getWorldObjects = function() return javaList(sq.items) end
			sq.getMovingObjects = function() return javaList(sq.bodies) end
			-- The wall socket: the two calls hasPower makes, in the order it makes
			-- them (ISWorldObjectContextMenu.lua:460). One switch for both, because
			-- what this bench means by no power is a dark building and not which of
			-- the generator and the county grid went.
			sq.haveElectricity = function() return chunk.powered end
			sq.hasGridPower = function() return false end
			return sq
		end

		chunk.light = fakeLight(true, true)
		local here = newSquare(x, y)
		local beside = newSquare(x + 1, y, { chunk.light })
		-- The tile it is on, which is what FakeWorld.put gives a device and what
		-- the device layer asks of one before it acts on it (the alive() check in
		-- SCeroSecDevices): a switch whose chunk is away is not on a square either.
		chunk.light.getSquare = function() return chunk.loaded and beside or nil end
		chunk.room = { getName = function() return "office" end,
			getSquares = function() return javaList({ here, beside }) end }
		local def = {
			getX = function() return OFFICE_X end,
			getY = function() return OFFICE_Y end,
			getX2 = function() return OFFICE_X + 40 end,
			getY2 = function() return OFFICE_Y + 40 end,
			-- A RoomDef answers no IsoRoom for a room whose chunks are not in,
			-- which is what FakeWorld's own building def does further up.
			getRooms = function() return javaList({
				{ getIsoRoom = function() return chunk.loaded and chunk.room or nil end },
			}) end,
		}
		chunk.building = { getDef = function() return def end }

		-- The tile's own object, which is what a chunk brings back with it. Its
		-- sprite starts OFF because that is what is on the tile before anybody has
		-- switched the machine on.
		local iso = { sprite = CeroSec.SPRITES_OFF["S"], modData = {} }
		iso.getSpriteName = function() return iso.sprite end
		iso.setSpriteFromName = function(_, name)
			iso.sprite = name
			chunk.sprites[#chunk.sprites + 1] = name
		end
		iso.transmitUpdatedSpriteToClients = function() end
		iso.hasModData = function() return true end
		iso.getModData = function() return iso.modData end
		iso.transmitModData = function() end
		iso.getSquare = function() return chunk.loaded and here or nil end
		chunk.iso = iso

		-- The cell, which is a different question from the machine's own square:
		-- /dev and the sensor scan are discovered through getCell
		-- (CeroSecDevices.find), so a chunk that is away has to be away from that
		-- too. Nothing else in the county is in this cell, which is all the two
		-- benches that read /dev need.
		_G.__world = { getGridSquare = function(_, gx, gy, gz)
			if not chunk.loaded or gz ~= 0 then return nil end
			if gx == x and gy == y then return here end
			if gx == x + 1 and gy == y then return beside end
			return nil
		end }

		-- The client's end of a chunk coming back: stateToIsoObject announces the
		-- object, which is what puts the screen's glow back on
		-- (CCeroSecSystem:newLuaObjectAt -> syncLight). Counted, because "the
		-- client was told" is the only server-side proof of a light there is.
		net.system.newLuaObjectOnClient = function(_, o)
			if o == chunk.object then chunk.told = chunk.told + 1 end
		end

		local object = net.machine(x, y, 0, chunk.building)
		object.hasPower = nil
		object.syncSprite = nil
		object.getSquare = function() return chunk.loaded and here or nil end
		object.getIsoObject = function() return chunk.loaded and iso or nil end
		chunk.object = object
		object:turnOn()

		-- And it knows the survivor's machine by name, exactly as the other two in
		-- newNet do and for the same reason: a name in one of its trust files is
		-- matched against the caller's ADDRESS through ITS own /etc/hosts
		-- (CeroSecOS.trustWords), never against the name the caller announces. The
		-- line is written now, while the chunk is in, because /etc/hosts is a file
		-- on the disk and the whole point of this section is that the disk does not
		-- go away with the chunk -- so what this names goes on being named while
		-- the machine is out of the world.
		net.name(object, net.here, net.host(net.here))

		-- The streamer, both ways. Away takes the square, the iso object, the room
		-- and the tiles all at once, which is what one chunk going out of memory
		-- does. Back puts the very same ones in again and then hands the iso object
		-- to the system exactly as the game does: MapObjects.OnLoadWithSprite ->
		-- LoadComputer -> loadIsoObject (the foot of SCeroSecSystem.lua).
		function chunk.away()
			chunk.loaded = false
		end
		function chunk.back(powered)
			chunk.powered = powered ~= false
			chunk.loaded = true
			net.system:loadIsoObject(iso)
		end

		return chunk
	end

	-- The whole of the report, in one bench: ten minutes out of view with a
	-- session open on it and a crontab due every minute.
	do
		local net = newNet()
		local chunk = streamed(net, 20, 10)
		local far = chunk.object
		net.name(net.here, far, "deep")
		net.put(far, "/etc/hosts.equiv", net.host(net.here), 644, "root")
		net.crontab(far, "admin", "* * * * * echo alive >> /home/admin/log")
		net.login("admin")

		net.enter("rlogin deep")
		net.tick(3)
		check("the far machine takes the login", net.glass("admin@" .. net.host(far)))
		-- And its light switch is a device while the chunk is in, which is what
		-- makes the refusal below a refusal and not an empty bench.
		net.enter("dev light0 off")
		net.tick(2)
		eq("the switch it reaches really moves", chunk.light.activated, false)
		check("and dev said what it read back", net.glass("light0: off"))

		-- One minute with the chunk still in, so that cron has looked at the clock
		-- once: the minute a machine comes into view in is never a minute it runs
		-- anything for, and a bench that skipped this would be counting nine.
		net.minute(1)
		eq("and nothing has run yet", net.text(far, "/home/admin/log"), nil)

		-- The survivor walks out of town. Nothing else changes: the machine is on,
		-- somebody is logged into it from the wire, its crontab is due.
		chunk.away()
		eq("its square is gone", far:getSquare(), nil)
		eq("and so is its iso object", far:getIsoObject(), nil)
		eq("which is what the machine itself says", far:isLoaded(), false)

		net.forget()
		net.minute(10)
		eq("ten minutes of the sweep leave it on", far.on, true)
		check("with nothing said about power", not net.heard("Connection closed."))
		eq("the session is still open", CeroSecOS.ptyCount(far.ptys), 1)
		eq("its screen was never thrown away", type(far.console), "table")

		-- And it is still a machine: the line goes out of view and comes back.
		net.enter("hostname")
		net.tick(2)
		check("the far machine still answers", net.glass(net.host(far)))

		-- cron kept its minute hand. Ten minutes out of view, ten lines, whatever
		-- the streamer was doing: a crontab is the disk's and not the world's.
		local log = net.text(far, "/home/admin/log")
		eq("cron fired every minute it was out of view",
			log ~= nil and #CeroSecOS.splitLines(log), 10)

		-- The one thing that is really gone is the world. The number is still in
		-- the machine's book -- a number is spent for the life of the machine --
		-- so what it gets is "no such device" and not "no such file": the
		-- difference between a switch out of reach and a path he mistyped.
		net.forget()
		net.enter("dev light0 on")
		net.tick(2)
		check("the switch out of view refuses by name", net.glass("light0: no such device"))
		eq("and nothing moved in the world", chunk.light.activated, false)
		eq("the machine is still on for having been asked", far.on, true)
	end

	-- He comes home, and the building still has its wire.
	do
		local net = newNet()
		local chunk = streamed(net, 20, 10)
		local far = chunk.object
		net.name(net.here, far, "deep")
		net.put(far, "/etc/hosts.equiv", net.host(net.here), 644, "root")
		net.login("admin")
		net.enter("rlogin deep")
		net.tick(3)

		chunk.away()
		net.minute(3)
		chunk.told = 0
		chunk.sprites = {}
		chunk.back(true)
		eq("the machine that was on is still on", far.on, true)
		eq("the sprite on the tile is the lit one", chunk.iso.sprite, CeroSec.SPRITES_ON["S"])
		check("and the client was told, so the glow is back", chunk.told >= 1)
		eq("the session survived the whole errand", CeroSecOS.ptyCount(far.ptys), 1)

		-- /dev is back with the chunk, by the number it always had.
		net.enter("dev light0 off")
		net.tick(2)
		eq("and the switch answers again", chunk.light.activated, false)
	end

	-- He comes home, and the generator ran dry while he was away. THIS is where
	-- the machine goes dark: at the first moment there is a room to ask, and not
	-- because nobody could see it.
	do
		local net = newNet()
		local chunk = streamed(net, 20, 10)
		local far = chunk.object
		net.name(net.here, far, "deep")
		net.put(far, "/etc/hosts.equiv", net.host(net.here), 644, "root")
		net.login("admin")
		net.enter("rlogin deep")
		net.tick(3)

		chunk.away()
		net.minute(3)
		eq("out of view it is still on", far.on, true)
		net.forget()
		chunk.back(false)
		eq("the chunk came back to a dark room and the machine went off",
			far.on, false)
		eq("the sprite on the tile went dark with it",
			chunk.iso.sprite, CeroSec.SPRITES_OFF["S"])
		eq("its screen is gone", far.console, nil)
		check("and the session was told", net.heard("Connection closed."))

		-- The first check and not the second: no minute of the sweep has run.
		net.enter("rlogin deep")
		net.tick(2)
		check("and it is down for anybody who calls", net.glass("rlogin: deep: Host is down"))
	end

	-- A machine switched off while nobody could see it. The sprite could not
	-- follow -- there was no tile to put it on -- so the tile is caught up when
	-- the chunk comes back, with the power still on.
	do
		local net = newNet()
		local chunk = streamed(net, 20, 10)
		local far = chunk.object
		net.name(net.here, far, "deep")
		net.put(far, "/etc/hosts.equiv", net.host(net.here), 644, "root")
		-- root's crontab, because halt is root's command (CeroSecOSShell's
		-- commands.shutdown refuses anybody else) and cron runs a line as the
		-- account whose crontab it is.
		net.crontab(far, "root", "* * * * * halt")
		net.login("admin")

		-- One minute in view for cron's minute hand, then out of town.
		net.minute(1)
		eq("nothing has run yet", far.on, true)
		chunk.away()
		net.minute(2)
		eq("the crontab shut it down out of view", far.on, false)
		eq("and the tile it left behind still shows the lit sprite",
			chunk.iso.sprite, CeroSec.SPRITES_ON["S"])

		chunk.told = 0
		chunk.back(true)
		eq("the chunk comes back to the dark sprite",
			chunk.iso.sprite, CeroSec.SPRITES_OFF["S"])
		check("and the client is told, so no glow comes back with it", chunk.told >= 1)
		eq("a dark machine is not switched on by its chunk arriving", far.on, false)
	end

	-- The control: the sweep still switches off a machine it CAN see. Without
	-- this the guard above could be a guard on everything.
	do
		local net = newNet()
		local chunk = streamed(net, 20, 10)
		local far = chunk.object
		net.name(net.here, far, "deep")
		net.put(far, "/etc/hosts.equiv", net.host(net.here), 644, "root")
		net.login("admin")
		net.enter("rlogin deep")
		net.tick(3)
		net.forget()

		-- The chunk stays in and the room loses its power.
		chunk.powered = false
		eq("it is still on until the sweep looks", far.on, true)
		net.minute(1)
		eq("the first minute of the sweep switched it off", far.on, false)
		eq("with the dark sprite on its tile", chunk.iso.sprite, CeroSec.SPRITES_OFF["S"])
		check("and the session was told", net.heard("Connection closed."))
	end

	-- THE ADDRESS AND THE CHUNK, which are two books and not one -- the seam
	-- between this section and the wire.
	--
	-- A machine is NUMBERED out of the world: CeroSecNet.identify reads the
	-- building off a square, so it only ever happens while the chunk is in (turnOn,
	-- a window opening, and the minute sweep for a machine that has not got a
	-- number yet). A machine is TRUSTED out of its RECORD, which is three numbers
	-- in the state and therefore on the disk the server holds whether the chunk is
	-- in or not. So the two halves come apart exactly here: a machine already
	-- numbered goes on being reached and trusted by that number with no square, no
	-- tile and no room left around it.
	do
		local net = newNet()
		local chunk = streamed(net, 20, 10)
		local far = chunk.object
		local addr = net.addr(far)
		-- By the ADDRESS and by nothing else: the line streamed() wrote is taken
		-- back out of the far machine's resolver, so there is no name for this
		-- machine over there to fall back on, and admin's own list is the only file
		-- that says anything about the caller.
		net.put(far, "/etc/hosts", "127.0.0.1 localhost", 644, "root")
		net.put(far, "/home/admin/.rhosts", net.addr(net.here), 600, "admin")
		net.login("admin")

		chunk.away()
		eq("the chunk is away", far:isLoaded(), false)
		eq("and the machine kept the number it was given", net.addr(far), addr)

		-- Typed as the quad, because a name for it would be a line of THIS
		-- machine's /etc/hosts and the far end is what this bench is about.
		net.enter("rlogin " .. addr)
		net.tick(3)
		check("a machine out of the world still takes a trusted login",
			net.glass("admin@" .. net.host(far)))
		net.enter("who")
		net.tick(2)
		check("and names the caller by the address it came from",
			net.glass("(" .. net.addr(net.here) .. ")"))
		net.enter("exit")
		net.tick(3)
	end

	-- The other half, which is the one that would have been a hole: numbering
	-- WAITS for the chunk. A computer switched on in a base somebody built has no
	-- address -- no map building, no wire -- and carrying it into a building does
	-- not give it one while nobody is looking: the sweep has no square to read the
	-- building off. So until the chunk comes in it is on nobody's wire, and the
	-- most generous trust file in the county is a file about a machine that cannot
	-- call. The chunk arrives, the sweep numbers it, and the same line lets the
	-- survivor in.
	do
		local net = newNet()
		local inWorld, building = true, nil
		local iso = { modData = {} }
		iso.hasModData = function() return true end
		iso.getModData = function() return iso.modData end
		iso.transmitModData = function() end
		iso.getSpriteName = function() return CeroSec.SPRITES_OFF["S"] end
		iso.setSpriteFromName = function() end
		iso.transmitUpdatedSpriteToClients = function() end

		local old = net.machine(24, 10, 0, nil)
		local square = {
			getX = function() return 24 end,
			getY = function() return 10 end,
			getZ = function() return 0 end,
			getRoom = function() return nil end,
			getBuilding = function() return building end,
			getObjects = function() return javaList({}) end,
			haveElectricity = function() return true end,
			hasGridPower = function() return false end,
		}
		old.getSquare = function() return inWorld and square or nil end
		old.getIsoObject = function() return inWorld and iso or nil end
		-- The real power question, off the real square: the stub machine() puts
		-- there is for the benches about the wire.
		old.hasPower = nil

		-- Switched on in the base: a building the map knows is the one thing the
		-- wire needs, and there is none.
		old:turnOn()
		eq("a machine in no building is on", old.on, true)
		eq("and has no address to be on a wire with", net.addr(old), nil)

		-- Carried into the office, and the quarter goes out of memory before the
		-- minute turns.
		building = net.office
		inWorld = false
		net.put(old, "/home/admin/.rhosts", net.addr(net.here), 600, "admin")
		net.login("admin")

		net.minute(3)
		eq("three minutes of the sweep leave it unnumbered", net.addr(old), nil)
		eq("because there was no square to read its building off",
			old:isLoaded(), false)
		net.enter("rlogin " .. net.host(old))
		net.tick(2)
		-- Nothing to escape from: the refusal is the resolver's and no session was
		-- ever begun, so the survivor is at his own prompt already.
		check("and nothing resolves it, so nobody calls it",
			net.glass("rlogin: " .. net.host(old) .. ": unknown host"))

		-- The survivor comes back, and the first minute with the chunk in is the
		-- minute it joins the wire.
		inWorld = true
		net.minute(1)
		local addr = net.addr(old)
		check("the chunk comes in and the sweep numbers it", addr ~= nil)
		net.enter("rlogin " .. addr)
		net.tick(3)
		check("and the list that said nothing now takes the login",
			net.glass("admin@" .. net.host(old)))
		net.enter("exit")
		net.tick(3)
	end

	_G.__world = nil
end

--
-- The hardware modules
--
-- Rung 4f: a door, a window and a light switch are only in /dev when somebody
-- has screwed a module to them. The sandbox option CeroSec.HardwareRequired is
-- the switch, it is ON in the game, and every OTHER device bench in this file
-- is the control for it being off -- they run on the default this file sets at
-- the top and they were not touched for this rung.
--
-- What is asserted here is the same thing those assert: what is on the GLASS.
-- The wiring itself is written straight into the object's modData, the way the
-- install command writes it, and the install command's own half is the section
-- after this one.
--

do
	local kit = mockupWorld()
	_G.__world = kit.world
	_G.SandboxVars = { CeroSec = { HardwareRequired = true } }

	local bench = newBench()
	bench.login("admin")

	-- Nothing is wired, so there is nothing to reach -- and the machine is the
	-- same machine, in the same building, with the same doors in it.
	bench.enter("dev")
	bench.frame()
	check("no door is a device", not bench.painted("exterior"))
	check("no light is a device", not bench.painted("office"))
	check("no window is a device", not bench.painted("win0"))
	bench.enter("ls /dev")
	bench.frame()
	check("and /dev holds nothing of the world", not bench.painted("door0"))
	check("nor a light", not bench.painted("light0"))
	-- A number a player wrote down last week is not a path he mistyped.
	bench.enter("dev light0")
	bench.frame()
	check("a device nobody fitted is no such device",
		bench.painted("dev: light0: no such device"))

	-- A relay on the office switch, and only on that one.
	fit(kit.light0, "relay")
	bench.enter("dev")
	bench.frame()
	check("the switch with a relay on it is a device", bench.painted("light0  office"))
	check("the one without is still not", not bench.painted("hallway"))
	bench.enter("echo off > /dev/light0")
	bench.frame()
	eq("and it throws the switch", kit.light0.activated, false)
	eq("and it was broadcast", kit.light0.syncs, 1)

	-- An operator on the door between the kitchen and the hallway, which is a
	-- door no lock means anything on: one device, and it opens.
	fit(kit.inner, "operator")
	bench.enter("echo open > /dev/door0")
	bench.frame()
	eq("the door with an operator on it opens", kit.inner.open, true)
	eq("the world was told", kit.inner.syncs, 1)
	bench.enter("cat /dev/door0")
	bench.frame()
	check("and it reads back open", bench.painted("open"))
	check("no lock device came with it", not bench.painted("lock0"))

	-- A magnetic contact on the front door: the machine can SEE it and cannot
	-- move it. Same kind, same words, nothing behind them.
	fit(kit.front, "contact")
	bench.enter("cat /dev/door1")
	bench.frame()
	check("a door with only a contact on it reads", bench.painted("locked"))
	bench.enter("ls -l /dev")
	bench.frame()
	check("and wears a mode that promises nothing",
		bench.painted("cr--r-----  root  sudo  door1   exterior"))
	check("while the one with an operator wears rw",
		bench.painted("crw-rw----  root  sudo  door0   kitchen-hall~"))

	-- admin is in the sudo group, so 440 lets him read it and stops him there.
	bench.enter("echo open > /dev/door1")
	bench.frame()
	check("an ordinary account is refused by the mode",
		bench.painted("door1: permission denied"))
	eq("and the door was never asked", kit.front.silentToggles, 0)

	-- root walks past the mode, the way root walks past every mode on this
	-- machine, and is refused by the device itself.
	bench.enter("su root")
	bench.enter("")
	bench.frame()
	eq("root is at the glass", bench.object.console.user, "root")
	bench.enter("echo open > /dev/door1")
	bench.frame()
	check("and root is refused by the hardware that is not there",
		bench.painted("door1: operation not supported"))
	eq("the door still never moved", kit.front.silentToggles, 0)
	eq("and nothing was broadcast about it", kit.front.syncs, 0)
	-- `dev` is the same refusal through the other door into it.
	bench.enter("dev door1 open")
	bench.frame()
	check("dev says the same thing", bench.painted("door1: operation not supported"))

	-- A strike is the lock and nothing else: the door it is on still does not
	-- open, and the key it carries now answers.
	fit(kit.front, "strike")
	bench.enter("echo unlock > /dev/lock0")
	bench.frame()
	eq("the strike works the lock", kit.front.lockedByKey, false)
	eq("and it was broadcast", kit.front.syncs, 1)
	bench.enter("echo open > /dev/door1")
	bench.frame()
	check("and the door is still a door with no operator on it",
		bench.painted("door1: operation not supported"))

	-- The number is spent for the life of the machine, hardware or no hardware:
	-- taking the contact off makes the device unreachable and taking it back on
	-- gives back the SAME id, which is what a script that says door1 depends on.
	unfit(kit.front, "contact")
	bench.enter("dev door1")
	bench.frame()
	-- Mounted and not listed: the machine remembers the number and cannot reach
	-- it, which is "no such device" in the DEVICE's own name and not "no such
	-- file" in the filesystem's.
	check("a device whose module came off is out of reach",
		bench.painted("door1: no such device"))
	-- The lock on the same door is a device of its own with a module of its own,
	-- and it is untouched: what came off was the contact.
	bench.enter("cat /dev/lock0")
	bench.frame()
	check("while the strike on the same door still answers", bench.painted("unlocked"))
	fit(kit.front, "contact")
	bench.enter("cat /dev/door1")
	bench.frame()
	check("and it comes back as the same device", bench.painted("closed"))

	-- And the hardware CHANGING under a device moves its mode with it, without
	-- moving its number: an operator fitted to the door that had a contact on it
	-- is the same door1, read-write now, and it opens.
	fit(kit.front, "operator")
	bench.enter("ls -l /dev")
	bench.frame()
	check("the same device wears rw once an operator is on it",
		bench.painted("crw-rw----  root  sudo  door1   exterior"))
	bench.enter("echo open > /dev/door1")
	bench.frame()
	eq("and now it opens", kit.front.open, true)

	-- A window takes a contact and there is no second module for it: the game
	-- has no call that moves a sash without a survivor standing at it, so a
	-- wired window is one the machine reads.
	fit(kit.win0, "contact")
	bench.enter("dev win0")
	bench.frame()
	check("a wired window reads its latch", bench.painted("win0: locked"))
	-- And its sash, which is the whole of what a magnetic contact does: it is a
	-- switch on the frame, and what closes it is the window being shut.
	kit.win0.open = true
	bench.enter("dev win0")
	bench.frame()
	check("and the contact sees the sash", bench.painted("win0: open"))
	kit.win0.open = false
	bench.enter("echo unlock > /dev/win0")
	bench.frame()
	check("and refuses every word", bench.painted("win0: operation not supported"))
	eq("the window was not touched", kit.win0.locked, true)
	eq("and nothing was broadcast about it", kit.win0.syncs, 0)

	-- The server's OWN belt for the same case, asked directly. Everything above
	-- this line is refused by the engine before the world layer is reached, so
	-- the only way to see the second guard do anything is to call the world layer
	-- itself -- which is what a caller with its own idea of /dev would be.
	do
		local env = CeroSecDevices.envFor(bench.object, bench.object:osState())
		local done, reason = env.write("win0", "unlock")
		eq("the world layer refuses it too", done, false)
		eq("in the same words", reason, "operation not supported")
		eq("and the window is still locked", kit.win0.locked, true)
		local opened, whyNot = env.write("door1", "close")
		eq("while the door with an operator on it takes the order", opened, true)
		eq("with nothing to say about it", whyNot, nil)
		eq("and it shut", kit.front.open, false)
	end

	_G.__world = nil
	_G.SandboxVars = { CeroSec = { HardwareRequired = false } }
end

-- The control, on a world where nothing at all is wired: the option off is the
-- building as it was before this rung, every device of it, with the numbers the
-- mockup approved. This is the same assertion the first device section makes and
-- it is made again HERE, beside the gate, so that a gate which stopped reading
-- the option fails in the section it belongs to.
do
	local kit = mockupWorld()
	_G.__world = kit.world
	_G.SandboxVars = { CeroSec = { HardwareRequired = false } }

	local bench = newBench()
	bench.login("admin")
	bench.enter("ls -l /dev")
	bench.frame()
	local want = {
		"crw-rw----  root  sudo  door0   exterior       W  locked",
		"crw-rw----  root  sudo  door1   kitchen-hall~  N  closed",
		"crw-rw----  root  sudo  door2   built          N  closed",
		"crw-rw----  root  sudo  light0  office            on",
		"crw-rw----  root  sudo  light1  hallway           off",
		"crw-rw----  root  sudo  lock0   exterior       W  locked",
		"crw-rw----  root  sudo  lock1   built          N  padlock",
		"crw-rw----  root  sudo  win0    office         N  locked",
	}
	for i = 1, #want do
		check("with the option off, the glass still shows: " .. want[i],
			bench.painted(want[i]))
	end
	_G.__world = nil
end

-- And a world the sandbox says nothing about at all -- a server whose options
-- file failed to load, or a save from before this rung. It fails CLOSED: no
-- hardware, no devices, which is a thing a player sees at once and can fix from
-- the sandbox screen. The other way round is a world that quietly went back to
-- magic and looks exactly like a working one.
do
	local kit = mockupWorld()
	_G.__world = kit.world
	_G.SandboxVars = nil

	local bench = newBench()
	bench.login("admin")
	bench.enter("dev")
	bench.frame()
	check("no options at all is not a world of open doors",
		not bench.painted("exterior"))
	check("nor of lights", not bench.painted("office"))

	-- The same machine, the same second, with the group there and the option off.
	_G.SandboxVars = { CeroSec = { HardwareRequired = false } }
	bench.enter("dev")
	bench.frame()
	check("and the option said out loud brings the building back",
		bench.painted("exterior"))

	_G.__world = nil
	kit = nil
end

--
-- Fitting a module, and taking it off
--
-- The server's half of the right-click menu: two commands that name a FIXTURE --
-- the square it stands on and its index in that square's object list, the way
-- vanilla's own client commands name a world object -- and that believe nothing
-- else the client sent.
--
-- Everything the menu greys out is asked again here, and one thing the menu
-- cannot ask is asked only here: whether the survivor is actually standing next
-- to the thing. Each refusal is proved by what did NOT happen -- the module is
-- not on the door, the item is still in his bag -- because these commands answer
-- nothing: a refusal here is a packet nobody typed.
--
do
	local kit = mockupWorld()
	_G.__world = kit.world
	_G.SandboxVars = { CeroSec = { HardwareRequired = true } }
	-- The game's own perk table. Only ever handed straight back to
	-- getPerkLevel, so what it holds does not matter and that it is the SAME
	-- value on both sides does.
	_G.Perks = { Electricity = "Electricity" }

	local bench = newBench()
	local inv = newInventory()
	local level = 0
	bench.player.getInventory = function() return inv end
	bench.player.getPerkLevel = function(_, perk)
		if perk ~= Perks.Electricity then return 0 end
		return level
	end
	bench.login("admin")

	-- One packet, the way a client sends it.
	local function send(command, sx, sy, index, id)
		CCeroSecSystem.instance:sendCommand(bench.player, command,
			{ x = sx, y = sy, z = 0, index = index, module = id })
		bench.frame()
	end

	local function carrying(fullType)
		return inv:getFirstTypeRecurse(fullType) ~= nil
	end
	local function fittedOn(object, id)
		return CeroSecModules.installedOn(object)[id] == true
	end

	-- The office light switch is the second object on the door's own square, so
	-- the index is what tells the two apart and a bench that always sent 0 would
	-- prove nothing about it.
	local SQ = { 11, 10 }
	local DOOR, LIGHT = 0, 1

	-- Nothing at all: no module in the bag.
	level = 5
	send("installmodule", SQ[1], SQ[2], LIGHT, "relay")
	eq("no relay in the bag, no relay on the wall", fittedOn(kit.light0, "relay"), false)

	-- The module, and no screwdriver.
	inv:add("CeroSec.Relay")
	send("installmodule", SQ[1], SQ[2], LIGHT, "relay")
	eq("a module and no tool fits nothing", fittedOn(kit.light0, "relay"), false)
	check("and the module is still his", carrying("CeroSec.Relay"))

	-- The tool, and not the trade.
	inv:add("Base.Screwdriver")
	level = 0
	send("installmodule", SQ[1], SQ[2], LIGHT, "relay")
	eq("a relay wants one level of Electricity", fittedOn(kit.light0, "relay"), false)
	check("and the module is still his", carrying("CeroSec.Relay"))

	-- The wrong fixture, with everything else in hand: a relay is a light
	-- switch's module and the door on the same square is not a light switch.
	level = 5
	send("installmodule", SQ[1], SQ[2], DOOR, "relay")
	eq("a relay does not go on a door", fittedOn(kit.front, "relay"), false)
	check("and the module is still his", carrying("CeroSec.Relay"))

	-- And now, with the three of them.
	level = 1
	send("installmodule", SQ[1], SQ[2], LIGHT, "relay")
	eq("the relay is on the switch", fittedOn(kit.light0, "relay"), true)
	check("the module left his bag", not carrying("CeroSec.Relay"))
	check("the screwdriver did not", carrying("Base.Screwdriver"))
	eq("and every other player was told", kit.light0.transmits, 1)

	-- The machine can see it now, end to end.
	bench.enter("dev")
	bench.frame()
	check("and the switch is a device", bench.painted("light0  office"))

	-- A second one buys nothing and eats nothing.
	inv:add("CeroSec.Relay")
	send("installmodule", SQ[1], SQ[2], LIGHT, "relay")
	check("a second relay is not fitted twice", carrying("CeroSec.Relay"))
	eq("and nothing was broadcast for it", kit.light0.transmits, 1)
	inv:Remove(inv:getFirstTypeRecurse("CeroSec.Relay"))

	-- The lock rule, which is the discovery's own and is asked at the menu and
	-- again here: the door between the kitchen and the hallway has a room on
	-- both sides, so a key on it stops nobody and a strike on it would be a box
	-- that does nothing.
	level = 5
	inv:add("CeroSec.ElectricStrike")
	send("installmodule", 11, 11, 0, "strike")
	eq("no strike on a door whose lock means nothing", fittedOn(kit.inner, "strike"), false)
	check("and the strike is still his", carrying("CeroSec.ElectricStrike"))
	-- The front door is the way out of the building, and that one takes it.
	send("installmodule", SQ[1], SQ[2], DOOR, "strike")
	eq("the strike is on the front door", fittedOn(kit.front, "strike"), true)
	check("and it left his bag", not carrying("CeroSec.ElectricStrike"))

	-- The operator is the level-three job, and the level is asked for the
	-- MODULE and not for the mod.
	inv:add("CeroSec.DoorOperator")
	level = 2
	send("installmodule", 11, 11, 0, "operator")
	eq("two levels is not enough for an operator", fittedOn(kit.inner, "operator"), false)
	level = 3
	send("installmodule", 11, 11, 0, "operator")
	eq("three is", fittedOn(kit.inner, "operator"), true)
	bench.enter("echo open > /dev/door0")
	bench.frame()
	eq("and the door it is on opens from the machine", kit.inner.open, true)

	-- Standing there is the one thing the menu cannot ask, so it is asked here
	-- and nowhere else. The window is two squares away.
	inv:add("CeroSec.MagneticContact")
	level = 5
	send("installmodule", 12, 10, 0, "contact")
	eq("a fixture out of reach takes nothing", fittedOn(kit.win0, "contact"), false)
	check("and the contact is still his", carrying("CeroSec.MagneticContact"))

	-- An object that is not there, and a square that is not in the world.
	send("installmodule", SQ[1], SQ[2], 9, "contact")
	check("an index off the end of the list does nothing",
		carrying("CeroSec.MagneticContact"))
	send("installmodule", 400, 400, 0, "contact")
	check("nor does a chunk the streamer never brought in",
		carrying("CeroSec.MagneticContact"))
	-- And a module nobody declared.
	send("installmodule", SQ[1], SQ[2], DOOR, "toaster")
	check("nor a module nobody has ever heard of",
		carrying("CeroSec.MagneticContact"))

	-- Taking one off: the item comes back whole, the device goes, and the object
	-- keeps the modules that are still on it.
	local before = kit.light0.transmits
	send("uninstallmodule", SQ[1], SQ[2], LIGHT, "relay")
	eq("the relay is off the switch", fittedOn(kit.light0, "relay"), false)
	check("and back in his bag", carrying("CeroSec.Relay"))
	eq("and everybody was told", kit.light0.transmits, before + 1)
	bench.enter("dev light0")
	bench.frame()
	check("the machine cannot reach the switch any more",
		bench.painted("light0: no such device"))
	-- The last module off takes the table with it: an empty one would ride in
	-- the save file for the rest of the world's life, because IsoObject.save
	-- only skips modData that is empty ALTOGETHER.
	eq("and nothing of ours is left on the object",
		kit.light0:getModData()[CeroSecModules.DATA_KEY], nil)

	-- Taking one off asks for the trade and the tool, like fitting one.
	level = 0
	send("uninstallmodule", SQ[1], SQ[2], DOOR, "strike")
	eq("no trade, no removal", fittedOn(kit.front, "strike"), true)
	level = 5
	inv:Remove(inv:getFirstTypeRecurse("Base.Screwdriver"))
	send("uninstallmodule", SQ[1], SQ[2], DOOR, "strike")
	eq("no tool, no removal", fittedOn(kit.front, "strike"), true)
	inv:add("Base.Screwdriver")
	send("uninstallmodule", SQ[1], SQ[2], DOOR, "strike")
	eq("with both, the strike comes off", fittedOn(kit.front, "strike"), false)
	check("and it is his again", carrying("CeroSec.ElectricStrike"))
	-- One module off a fixture that carries two leaves the other one alone.
	fit(kit.front, "contact")
	fit(kit.front, "strike")
	send("uninstallmodule", SQ[1], SQ[2], DOOR, "contact")
	eq("the contact came off", fittedOn(kit.front, "contact"), false)
	eq("and the strike beside it did not", fittedOn(kit.front, "strike"), true)

	_G.__world = nil
	_G.SandboxVars = { CeroSec = { HardwareRequired = false } }
end


--
-- 45. The debug snapshots (the debug wave)
--
-- What the debug window is handed, built by the server: the machine list, the
-- file tree, /dev, the wire and the scheduler. The window itself is
-- tests/debug_ui_test.lua; this is the half that reads the county.
--
-- What is asserted is the ROWS, because a row is what a player reads. Three
-- things are worth a bench of their own and each has one below: a machine whose
-- chunk is away is still in the list (the whole reason the server holds every
-- disk), every cap holds against a disk that is over it, and the devices
-- snapshot is the device layer's own discovery and not a second one.
--

-- Which cell of which row, by the first cell. Rows are found by what they say
-- and never by their index: a list that grew a row at the top would otherwise
-- move every assertion below it and none of them would notice.
local function rowWith(snap, first)
	for i = 1, #snap.rows do
		if snap.rows[i].c[1] == first then return snap.rows[i] end
	end
	return nil
end

local function infoHas(snap, needle)
	for i = 1, #snap.info do
		if string.find(snap.info[i], needle, 1, true) then return true end
	end
	return false
end

-- The machine list, over the network bench's three machines: two in the office
-- and one in the shed, none of them with an IsoObject -- which is a chunk the
-- streamer has not brought in.
do
	local net = newNet()
	net.login("admin")

	-- One of the three brought into the world, so "here" and "away" are both on
	-- the glass and a snapshot that answered the same word for every machine
	-- could not pass.
	net.here.getIsoObject = function() return { __class = "IsoObject" } end

	local snap = CeroSecDebug.snapshotOf(net.system, "machines", net.here)
	eq("every machine the server holds is listed", #snap.rows, 3)

	local here = rowWith(snap, "10,10,0")
	local far = rowWith(snap, "60,60,0")
	check("the machine the window is at is on the list", here ~= nil)
	check("and so is the one down the road", far ~= nil)
	eq("the loaded one says so", here.c[4], "here")
	eq("the one whose chunk is away says THAT", far.c[4], "away")
	-- The bug this row exists for: a machine out of the world has no square, so
	-- there is nobody to ask about its wiring -- and "no" would be a lie, the
	-- same lie that once switched off every computer behind a walking survivor
	-- (SCeroSecObject:checkPower).
	eq("and nothing is claimed about the wire it cannot be asked about", far.c[5], "-")
	eq("it is still on and still says so", far.c[3], "on")
	eq("with its own hostname off its own disk", far.c[6], net.host(net.far))
	eq("and its own address", far.c[7], net.addr(net.far))

	-- A row carries the machine it names, which is what makes it selectable.
	eq("a row names its machine", far.x, 60)
	eq("and its y", far.y, 60)
	eq("and its z", far.z, 0)

	check("the list says how many of how many it is showing",
		infoHas(snap, "machines: 3 of 3"))
	-- And the detail of the SELECTED machine, under the list.
	check("the selected machine's console is described", infoHas(snap, "console booted="))
	check("with its jobs and its windows", infoHas(snap, "windows "))

	-- Nothing selected is a list with no detail under it and never an error.
	local none = CeroSecDebug.snapshotOf(net.system, "machines", nil)
	eq("with nothing selected the list is still the list", #none.rows, 3)
	check("and it says so", infoHas(none, "no machine selected"))
end

-- The file tree, and the cap on it. Six hundred nodes against a cap of 512: the
-- disk's own node ceiling is 512 too, so the nodes are made by hand, past the
-- gate, exactly as a forged save would arrive.
do
	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()

	-- Six hundred files, in ten directories of sixty: the machine's own ceilings
	-- are 512 nodes and 96 entries a directory, so a disk this size is not a disk
	-- the engine would let a player make -- which is the point. The nodes go in
	-- behind the gate and the machine is handed back RAW, the way a forged save
	-- or a state written by an older build arrives, because what is under test is
	-- the cap on the WIRE and not the cap on the disk.
	local dir = CeroSecOS.systemNode(state, "/home/admin")
	check("there is a home to fill", type(dir) == "table" and dir.type == "dir")
	for d = 1, 10 do
		local sub = CeroSecOS.newDir("admin", 755, 1000)
		dir.children["d" .. d] = sub
		for i = 1, 60 do
			sub.children["f" .. i] = CeroSecOS.newFile("admin", 644, "x", 1000)
		end
	end
	local forgedNodes = CeroSecOS.usage(state)
	check("the disk really is over the cap (" .. forgedNodes .. " nodes)",
		forgedNodes > CeroSecDebug.FILE_MAX)
	-- The validator would throw a disk this size out, and rightly: the bench
	-- hands the state over itself so that the snapshot is asked about the tree it
	-- was given rather than about nothing at all.
	bench.object.osState = function() return state end

	local snap = CeroSecDebug.snapshotOf(bench.system, "files", bench.object)
	eq("the tree stops at the cap", #snap.rows, CeroSecDebug.FILE_MAX)
	check("and says it did", infoHas(snap, "rows 512 (cap 512)"))
	-- The root is the first row whatever the walk found, because the walk starts
	-- there: a tree whose first row was a file would be a tree walked upwards.
	eq("the walk starts at the root", snap.rows[1].c[1], "/")
	eq("which is a directory", snap.rows[1].c[2], "dir")
	eq("with the mode ls would print", snap.rows[1].c[3],
		CeroSecOS.permString(state.fs))

	local passwd = rowWith(snap, "/etc/passwd")
	check("a real file of the machine is on the list", passwd ~= nil)
	eq("with its owner", passwd.c[4], "root")
	eq("and its size in bytes", passwd.c[5],
		tostring(#(CeroSecOS.systemNode(state, "/etc/passwd").data or "")))

	-- The ceilings, read off the functions that enforce them.
	local nodes, bytes = CeroSecOS.usage(state)
	check("the disk's own numbers are reported",
		infoHas(snap, "nodes " .. nodes .. " of " .. CeroSecOS.MAX_NODES))
	check("and its bytes", infoHas(snap, "bytes " .. bytes .. " of "))

	-- No cell on the wire is longer than the cap, whatever is on the disk: a
	-- forged node name is a string a client would otherwise be handed whole.
	--
	-- The name begins with a "0" so that it sorts to the FRONT of the directory
	-- and is inside the five hundred and twelve rows the snapshot sends. A long
	-- name buried past the cap would be a name the bench never saw, and the
	-- assertion would have been green for having read nothing -- which is exactly
	-- what happened the first time this was written.
	local long = "0" .. string.rep("z", 399)
	dir.children[long] = CeroSecOS.newFile("admin", 644, "x", 1000)
	snap = CeroSecDebug.snapshotOf(bench.system, "files", bench.object)
	local sawLong = false
	local worst = 0
	for i = 1, #snap.rows do
		for k = 1, #snap.rows[i].c do
			local text = snap.rows[i].c[k]
			if #text > worst then worst = #text end
			if string.find(text, "0zzzz", 1, true) then sawLong = true end
		end
	end
	check("the four-hundred-character name really is in the rows sent", sawLong)
	check("and no cell is longer than the cell cap (" .. worst .. ")",
		worst <= CeroSecDebug.CELL_MAX)
end

-- /dev, against the mockup's world: the same discovery the engine is handed,
-- numbered the same way, with the world facts the engine has no use for beside
-- it.
do
	local kit = mockupWorld()
	_G.__world = kit.world

	local bench = newBench()
	bench.login("admin")
	local state = bench.object:osState()

	-- What `find` answers, numbered by the layer that owns the numbering. The
	-- snapshot has to agree with THIS and not with a walk of its own: the numbers
	-- are spent for the life of the machine, and a second numbering would hand
	-- out different ones.
	local found = CeroSecDevices.number(state,
		CeroSecDevices.find(bench.object.x, bench.object.y, bench.object.z))
	local want = {}
	for i = 1, #found do want[found[i].id] = found[i] end

	local snap = CeroSecDebug.snapshotOf(bench.system, "devices", bench.object)
	eq("one row per device find answered", #snap.rows, #found)
	for i = 1, #snap.rows do
		local id = snap.rows[i].c[1]
		local entry = want[id]
		check("the snapshot names " .. id .. " and find did too", entry ~= nil)
		eq(id .. " is the kind find said", snap.rows[i].c[2], entry.kind)
		eq(id .. " is where find said", snap.rows[i].c[7],
			entry.x .. "," .. entry.y .. "," .. entry.z)
	end

	-- The two rows the mockup is built around, spelled out: the front door is a
	-- door AND a lock on one object, and a light switch reads its own state.
	local door0 = rowWith(snap, "door0")
	check("the front door is a device", door0 ~= nil)
	eq("and it is a door", door0.c[2], "door")
	eq("with the handle the server would tell a client to look for", door0.c[8],
		kit.front:getSpriteName())
	eq("and its object is still on its square", door0.c[10], "here")
	local light0 = rowWith(snap, "light0")
	check("the office switch is a device", light0 ~= nil)
	eq("and it reads what the switch reads", light0.c[9], "on")

	-- A sensor: no sprite to be found again by (it is drawn from a model), and a
	-- record in the sampling book.
	kit.world.drop(kit.world.squares["10,10,0"], fakeSensor())
	snap = CeroSecDebug.snapshotOf(bench.system, "devices", bench.object)
	local sensor0 = rowWith(snap, "sensor0")
	check("a dropped head is a device", sensor0 ~= nil)
	-- A world item is drawn from a model and has no sprite name at all, so what
	-- the server would point a client at is the ITEM -- and that is what the
	-- column shows, because it shows the handle a highlight carries and not a
	-- field (CeroSecDevices.handleOf).
	eq("its handle is the item and not a sprite", sensor0.c[8], "Base.MotionSensor")

	-- And a light switch has no handle at all: it blinks where everybody can see
	-- it, so nothing about it is ever addressed to one screen and getSpriteName is
	-- a call the mod does not make on a switch.
	eq("a light carries no handle", rowWith(snap, "light0").c[8], "-")
	check("and the sampling book has a record of it",
		infoHas(snap, "sensor0: range "))

	-- Picked up again: the number stays spent and the row says the object is
	-- gone, which is the difference between a device out of reach and a path
	-- somebody mistyped.
	local dead = nil
	for i = 1, #snap.rows do
		if snap.rows[i].c[1] == "door0" then dead = snap.rows[i] end
	end
	check("door0 is there before anything is taken away", dead ~= nil)

	_G.__world = nil
end

-- The wire: the segments, the exchange, the sessions that are up, and the log of
-- what was made and refused.
do
	local net = newNet()
	-- The wire's log is module-level state like the scheduler's list of machines,
	-- so a bench that asks what is IN it starts with its own empty one: the
	-- benches above this have been making and dropping sessions for eight thousand
	-- lines and the ring is long since full.
	CeroSecNet.events = {}
	net.login("admin")
	net.forget()

	local snap = CeroSecDebug.snapshotOf(net.system, "network", nil)
	-- Two buildings, so two segments and two telephone lines.
	local segments = 0
	for i = 1, #snap.rows do
		if snap.rows[i].c[1] == "eth" then segments = segments + 1 end
	end
	eq("one segment per building", segments, 2)
	check("and the list says so", infoHas(snap, "segments 2"))
	check("the exchange is described", rowWith(snap, "tel") ~= nil)

	-- A refusal leaves a line in the wire's own log, which is the one thing
	-- about the network that used to leave no trace at all: the pty was never
	-- made and the screen has scrolled.
	-- The last thing the wire was asked, whatever it was. Asserted on the CONTENT
	-- and never on the count: the ring is fifty lines deep and a full one does not
	-- grow, so "one more event than before" is an assertion that goes quiet the
	-- moment the bench above it has been busy.
	local function lastEvent()
		return CeroSecNet.events[#CeroSecNet.events]
	end

	-- A name nothing resolves never reaches the wire at all -- the resolver
	-- refuses it -- so the refusal that is worth logging is the one about the
	-- WIRE: a real machine, a real address, and no coax between two buildings.
	CeroSecNet.events = {}
	net.enter("rlogin nosuchmachine")
	net.tick(2)
	eq("a name nothing resolves is not a wire event", #CeroSecNet.events, 0)

	net.enter("rlogin " .. net.addr(net.far))
	net.tick(2)
	local event = lastEvent()
	check("a refused connection is noted", event ~= nil)
	eq("as a question about the coax", event.cmd, "eth")
	eq("naming the address it was asked about", event.to, net.addr(net.far))
	eq("with the reason the link layer had", event.what, "unreach")
	snap = CeroSecDebug.snapshotOf(net.system, "network", nil)
	local said = false
	for i = 1, #snap.rows do
		local row = snap.rows[i]
		if row.c[1] == "evt" and row.c[4] == net.addr(net.far)
				and row.c[5] == "unreach" then
			said = true
		end
	end
	check("and the refusal is on the Network tab", said)

	-- A session that IS up is a pty, and a pty is where a session lives.
	net.enter("rlogin " .. net.addr(net.gate))
	net.tick(3)
	net.enter("admin")
	net.enter("")
	net.tick(3)
	snap = CeroSecDebug.snapshotOf(net.system, "network", nil)
	local pty = nil
	for i = 1, #snap.rows do
		if snap.rows[i].c[1] == "pty" then pty = snap.rows[i] end
	end
	check("an open session is listed as a pty", pty ~= nil)
	eq("on the line the engine gave it", pty.c[2], "ttyp0")
	net.enter("exit")
	net.tick(3)

	-- The log is bounded: fifty is fifty whatever the county does.
	for _ = 1, CeroSecNet.EVENT_MAX * 2 do
		CeroSecNet.note(net.here, "rlogin", "nowhere", "refused")
	end
	eq("the wire's log holds its cap and no more", #CeroSecNet.events,
		CeroSecNet.EVENT_MAX)
end

-- The scheduler: the jobs the machines are running, with the budgets beside
-- them, and the selected machine's crontab as cron itself reads it.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/slow.sh", "sleep 30\n")
	bench.enter("sh slow.sh &")
	bench.tick(1)

	local snap = CeroSecDebug.snapshotOf(bench.system, "scheduler", bench.object)
	local job = CeroSecJobs.book(bench.object).list[1]
	check("the machine has a job", job ~= nil)
	local row = rowWith(snap, "10,10,0")
	check("and the scheduler tab lists one", row ~= nil)
	eq("by the id the scheduler gave it", row.c[2], tostring(job.id))
	eq("with the word the engine prints for its state", row.c[5],
		CeroSecOS.jobWord(job))
	check("the budgets are beside them",
		infoHas(snap, "budget per tick " .. CeroSec.STEP_BUDGET_PER_TICK))
	check("and the cpu ceiling",
		infoHas(snap, "cpu limit " .. CeroSec.JOB_CPU_LIMIT_S .. "s"))

	-- A crontab line, read through the engine's own parser and judged due by the
	-- engine's own cronDue -- never by arithmetic of the window's.
	local state = bench.object:osState()
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"* * * * * echo tick", false, 100)
	snap = CeroSecDebug.snapshotOf(bench.system, "scheduler", bench.object)
	check("the crontab line is listed", infoHas(snap, "echo tick"))
	check("and every minute is due now", infoHas(snap, "DUE NOW"))

	-- A line nothing could have installed is named as bad, in the parser's words.
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/var/spool/cron/admin",
		"60 * * * * echo never", false, 100)
	snap = CeroSecDebug.snapshotOf(bench.system, "scheduler", bench.object)
	check("a bad field is named", infoHas(snap, "BAD (bad minute)"))
end

-- The dump, which is the one thing that writes nowhere but the log.
do
	local bench = newBench()
	bench.login("admin")
	local said = {}
	local realPrint = print
	print = function(text) said[#said + 1] = tostring(text) end
	local written = CeroSecDebug.dump(bench.object)
	print = realPrint
	check("the dump printed something", written > 0)
	-- The cap, plus the one line that says the dump was cut there. A state is
	-- hundreds of nodes and a log file is somebody's text editor.
	check("it is bounded (" .. written .. " lines)",
		written <= CeroSecDebug.DUMP_MAX + 1)
	eq("and it printed exactly what it counted", #said, written)
	check("a disk this size really did hit the cap",
		written == CeroSecDebug.DUMP_MAX + 1)
	eq("and the last line says where it was cut",
		said[#said], "CeroSec dump: cut at " .. CeroSecDebug.DUMP_MAX .. " lines")
	local named = false
	for i = 1, #said do
		if string.find(said[i], "os.fs", 1, true) then named = true end
	end
	check("the filesystem is in it", named)
end

--
-- Where the machine stands: the building's footprint, the room, and the zones
--
-- Three facts about a PLACE and not about a computer, and the telephone wave's
-- rules are going to be written against them: a survivor at a computer in a mall
-- has to be able to see that the named zone he is in is SMALLER than the building
-- around it.
--
-- The bench asks for the premises of the SECOND machine while the first is right
-- there in front of it, because "the list comes from the square asked" is the one
-- thing a block of this kind gets wrong quietly: a premises block that always
-- answered for the first machine would read perfectly right on a bench with one.
--
do
	local net = newNet()

	-- A metagrid: which zones a square is inside, per square. Two on the office's
	-- square, one on the shed's, and none on a third -- so a snapshot that answered
	-- the same list for every machine, or one zone for a square with two, fails.
	--
	-- getZonesAt answers an ArrayList, walked 0..size()-1 exactly as vanilla walks
	-- it (SpawnRateChecker.lua:70-72), and a Zone answers the seven getters the
	-- premises block reads. The two zones on the office's square are deliberately a
	-- different SHAPE: one rectangle, whose total area is its box, and one whose
	-- total area is smaller than its box -- which is what a polygon zone is, and
	-- what makes reporting both numbers worth doing.
	local function zone(kind, name, x, y, w, h, area)
		return {
			getType = function() return kind end,
			getName = function() return name end,
			getX = function() return x end,
			getY = function() return y end,
			getZ = function() return 0 end,
			getWidth = function() return w end,
			getHeight = function() return h end,
			getTotalArea = function() return area or (w * h) end,
		}
	end
	local zonesBySquare = {
		["10,10,0"] = { zone("TownZone", "Muldraugh", 0, 0, 300, 300),
			zone("LootZone", "Mall", 8, 8, 20, 20, 240) },
		["60,60,0"] = { zone("Forest", nil, 50, 50, 40, 40) },
	}
	local asked = {}
	_G.getWorld = function()
		return {
			getMetaGrid = function()
				return {
					getZonesAt = function(_, x, y, z)
						local key = x .. "," .. y .. "," .. z
						asked[#asked + 1] = key
						local list = zonesBySquare[key]
						if list == nil then return javaList({}) end
						return javaList(list)
					end,
				}
			end,
		}
	end

	-- A room on the office's square, through its RoomDef the way vanilla reads one
	-- (ISInventoryPage.lua:1418). The shed's square has none.
	local function roomNamed(name)
		return {
			getName = function() return "wrong: the def is what is asked" end,
			getRoomDef = function() return { getName = function() return name end } end,
		}
	end
	local function withRoom(object, room)
		local square = object:getSquare()
		local old = square.getRoom
		square.getRoom = function() return room end
		return old
	end
	withRoom(net.here, roomNamed("office"))

	-- The office's own machine.
	local snap = CeroSecDebug.snapshotOf(net.system, "machines", net.here)
	check("the building's footprint is reported", infoHas(snap, "building: 400,700 to"))
	check("with its size", infoHas(snap, "10x10"))
	check("and its area and room count", infoHas(snap, "area 100  rooms 3"))
	check("the room is the one the def names", infoHas(snap, "room: office"))
	check("both zones are counted", infoHas(snap, "zones: 2"))
	check("the town zone is there with its box",
		infoHas(snap, "zone TownZone name Muldraugh  0,0 300x300  box 90000"))
	-- The whole point of reporting two numbers: a zone whose real area is smaller
	-- than its bounding box is the named zone inside the building.
	check("and the mall zone, whose area is smaller than its box",
		infoHas(snap, "zone LootZone name Mall  8,8 20x20  box 400  area 240"))

	-- The SECOND machine, in the other building, with the first one still on the
	-- list above it: a different footprint, no room, and one zone with no name.
	snap = CeroSecDebug.snapshotOf(net.system, "machines", net.far)
	check("the other building's footprint is the one reported",
		infoHas(snap, "building: 900,120 to"))
	check("and not the first machine's", not infoHas(snap, "building: 400,700 to"))
	check("a square with no room says so", infoHas(snap, "room: none"))
	check("one zone, not two", infoHas(snap, "zones: 1"))
	check("a zone with no name says so rather than inventing one",
		infoHas(snap, "zone Forest name -  50,50 40x40"))
	check("and the first machine's zones are nowhere on it",
		not infoHas(snap, "Muldraugh"))
	-- The grid was asked about the square of the machine that was SELECTED.
	eq("the last square the grid was asked about is the selected machine's",
		asked[#asked], "60,60,0")

	-- A square with nothing on it at all: no building, no room, no zone. Every
	-- answer is a "none" and none of them is an error.
	local outdoors = net.machine(500, 500, 0, nil)
	outdoors:turnOn()
	snap = CeroSecDebug.snapshotOf(net.system, "machines", outdoors)
	check("a machine in no map building says outdoors",
		infoHas(snap, "building: outdoors"))
	check("with no room", infoHas(snap, "room: none"))
	check("and no zones", infoHas(snap, "zones: none"))

	-- And a machine whose chunk is away has no square to ask any of it of, which is
	-- the same rule /dev and the power check wear.
	local away = net.machine(700, 700, 0, net.office)
	away:turnOn()
	away.getSquare = function() return nil end
	snap = CeroSecDebug.snapshotOf(net.system, "machines", away)
	check("a machine out of the world claims nothing about where it stands",
		infoHas(snap, "premises: no square (the chunk is away)"))
	check("and says nothing about a building", not infoHas(snap, "building:"))

	_G.getWorld = nil
end

-- The log ring: two hundred lines, and the two hundred and first drops the
-- oldest. It is not gated on CeroSec.DEBUG -- the print is, the ring is not --
-- because a Log tab that needed DEBUG turned on first would be empty exactly
-- when somebody opens it to find out what went wrong.
do
	CeroSec.logRing = {}
	eq("DEBUG is off, as it ships", CeroSec.DEBUG, false)
	CeroSec.log("first")
	eq("and the line is in the ring all the same", #CeroSec.logRing, 1)
	eq("at the info level, which is what a caller that says nothing means",
		CeroSec.logRing[1].level, CeroSec.LOG_INFO)
	eq("with the text it was given", CeroSec.logRing[1].text, "first")

	CeroSec.log(CeroSec.LOG_WARN, "careful")
	eq("a level given is the level kept", CeroSec.logRing[2].level, CeroSec.LOG_WARN)
	eq("and the text is still the text", CeroSec.logRing[2].text, "careful")

	-- Two hundred more on top of the two above: the cap is two hundred, so the two
	-- oldest go and the ring holds "line 1" to "line 200".
	for i = 1, CeroSec.LOG_MAX do CeroSec.log("line " .. i) end
	eq("the ring holds its cap and no more", #CeroSec.logRing, CeroSec.LOG_MAX)
	eq("the front of it is the oldest line still kept",
		CeroSec.logRing[1].text, "line 1")
	eq("and the newest is the last one written",
		CeroSec.logRing[CeroSec.LOG_MAX].text, "line " .. CeroSec.LOG_MAX)
	-- And the two that fell off really are gone, which is the half a count cannot
	-- prove: a ring that kept them and dropped from the WRONG end would have the
	-- right length and the wrong lines.
	local stale = false
	for i = 1, #CeroSec.logRing do
		local text = CeroSec.logRing[i].text
		if text == "first" or text == "careful" then stale = true end
	end
	check("the two oldest were dropped", not stale)

	-- And one of the mod's own refusals really does carry a level, so the
	-- window's filter has something to filter: a state the validator throws out
	-- is an error and says so.
	CeroSec.logRing = {}
	local bench = newBench()
	bench.object.os = { v = CeroSecOS.STATE_VERSION, fs = "not a filesystem" }
	bench.object.osBroken = nil
	eq("the validator refuses it", bench.object:osState(), nil)
	local level = nil
	for i = 1, #CeroSec.logRing do
		if string.find(CeroSec.logRing[i].text, "os refused at", 1, true) then
			level = CeroSec.logRing[i].level
		end
	end
	eq("and the refusal is logged as an error", level, CeroSec.LOG_ERROR)
	CeroSec.logRing = {}
end

--
-- Standing at the keyboard
--
-- The screenshot: a player using a computer with no chair stood in the MIDDLE of
-- the front square, a visible step short of the desk, typing at the air. Where
-- he is walked to is the whole of the fix, so these benches run the REAL reach
-- module -- not the stub the rest of this file uses -- against a world built by
-- hand, and read the coordinates out of the walk it queues.
--

do
	local stub = CeroSecReach

	-- The world. Squares by coordinate, each with the objects a bench puts on it.
	local squares = {}
	local function key(x, y, z) return x .. "," .. y .. "," .. z end
	local function square(x, y, z, objects)
		local sq = {
			getX = function() return x end,
			getY = function() return y end,
			getZ = function() return z end,
			getObjects = function() return javaList(objects or {}) end,
			canReachTo = function() return true end,
		}
		squares[key(x, y, z)] = sq
		return sq
	end
	_G.__world = { getGridSquare = function(_, x, y, z) return squares[key(x, y, z)] end }
	-- The two vanilla calls canStandInFront leans on, both answering yes: what
	-- these benches are about is the POINT, and a blocked square is its own bench
	-- in the rung 2 manual.
	_G.AdjacentFreeTileFinder = { privTrySquare = function() return true end }
	_G.IsoFlagType = { bed = "bed" }
	-- The seat point, as the game hands it over: a Vector3f the call fills in.
	-- __seat is where this fake world puts it; nil is the game refusing the place.
	_G.__seat = nil
	_G.Vector3f = { new = function()
		local v = { vx = 0, vy = 0, vz = 0 }
		v.x = function(s) return s.vx end
		v.y = function(s) return s.vy end
		v.z = function(s) return s.vz end
		return v
	end }
	_G.SeatingManager = { getInstance = function() return {
		getTilePositionCount = function() return 1 end,
		getFacingDirection = function(_, object) return object.__facing end,
		getAdjacentPosition = function(_, _, _, _, _, _, _, position)
			if _G.__seat == nil then return false end
			position.vx, position.vy, position.vz = _G.__seat[1], _G.__seat[2], _G.__seat[3]
			return true
		end,
	} end }

	local path = "42/media/lua/client/CeroSec/CeroSecReach.lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()

	-- A computer at 10,10 facing the given way, and its front square. The chair,
	-- when a bench wants one, stands on the front square and looks back at the
	-- screen (CeroSec.chairFacingFor).
	local function world(facing, withChair)
		squares = {}
		local chair = nil
		local dx, dy = CeroSec.frontOffset(facing)
		local computer = {
			getSpriteName = function() return CeroSec.SPRITES_ON[facing] end,
		}
		local front
		if withChair then
			chair = {
				__facing = CeroSec.chairFacingFor(facing),
				getSprite = function() return { getProperties = function() return {
					has = function(_, name) return name == IsoFlagType.bed end,
				} end } end,
			}
			front = square(10 + dx, 10 + dy, 0, { chair })
			chair.getSquare = function() return front end
		else
			front = square(10 + dx, 10 + dy, 0, {})
		end
		local home = square(10, 10, 0, { computer })
		computer.getSquare = function() return home end
		return computer, front, chair
	end

	-- A player at a float position, standing.
	local function stander(x, y)
		return {
			getX = function() return x end,
			getY = function() return y end,
			getCurrentSquare = function() return squares[key(math.floor(x), math.floor(y), 0)] end,
			isSittingOnFurniture = function() return false end,
			getSitOnFurnitureObject = function() return nil end,
		}
	end

	local function walkGoal()
		for i = #_G.__queued, 1, -1 do
			local action = _G.__queued[i]
			if action.goal then return action.goal[2], action.goal[3], action.goal[4] end
		end
		return nil
	end

	-- The stand point of each facing, through the module rather than through the
	-- arithmetic: the square it reads is the FRONT square, and the axis it shifts
	-- on is the facing's.
	local WANT = {
		S = { 10.5, 11.2 },
		N = { 10.5, 9.8 },
		E = { 11.2, 10.5 },
		W = { 9.8, 10.5 },
	}
	for _, facing in ipairs(CeroSec.FACINGS) do
		local computer = world(facing, false)
		local x, y, z = CeroSecReach.standPoint(computer)
		eq("stand point x, facing " .. facing, x, WANT[facing][1])
		eq("stand point y, facing " .. facing, y, WANT[facing][2])
		eq("stand point z, facing " .. facing, z, 0)
	end

	-- No square under the computer, no stand point -- and no error.
	do
		local computer = world("S", false)
		local home = computer:getSquare()
		computer.getSquare = function() return nil end
		eq("no square, no stand point", CeroSecReach.standPoint(computer), nil)
		computer.getSquare = function() return home end
	end

	-- The walk, standing: a player across the room is aimed at the stand point
	-- and not at the middle of the square.
	do
		local computer, front = world("S", false)
		local player = stander(4.5, 4.5)
		_G.__queued = {}
		local arrived = false
		check("walkToFront runs", CeroSecReach.walkToFront(player, computer,
			function() arrived = true end, true))
		check("and the follow-up is queued", arrived)
		local x, y, z = walkGoal()
		eq("standing: walked to the stand point x", x, 10.5)
		eq("standing: walked to the stand point y", y, 11.2)
		eq("standing: same level", z, front:getZ())
		check("standing: not the middle of the square", y ~= 11.5)
	end

	-- The walk, standing, from INSIDE the front square and at its middle -- the
	-- player the screenshot shows. The walk is still queued: a tenth of a tile is
	-- a walk, and skipping it is what left him short of the desk.
	do
		local computer = world("S", false)
		local player = stander(10.5, 11.5)
		_G.__queued = {}
		CeroSecReach.walkToFront(player, computer, function() end, true)
		local x, y = walkGoal()
		check("already on the square: still a walk", x ~= nil)
		eq("already on the square: to the stand point x", x, 10.5)
		eq("already on the square: to the stand point y", y, 11.2)
	end

	-- With a chair there, nothing changes: the seat point is the game's answer and
	-- the sit places the character itself.
	do
		local computer = world("S", true)
		_G.__seat = { 10.42, 11.61, 0 }
		local player = stander(4.5, 4.5)
		_G.__queued = {}
		CeroSecReach.walkToFront(player, computer, function() end, true)
		local x, y = walkGoal()
		eq("a chair: walked to the seat point x", x, 10.42)
		eq("a chair: walked to the seat point y", y, 11.61)
	end

	-- A seat point the game refuses, or one outside the front square, falls back
	-- to the stand point -- never to a point on somebody else's tile.
	do
		local computer = world("S", true)
		_G.__seat = nil
		local player = stander(4.5, 4.5)
		_G.__queued = {}
		CeroSecReach.walkToFront(player, computer, function() end, true)
		local x, y = walkGoal()
		eq("no seat point: the stand point x", x, 10.5)
		eq("no seat point: the stand point y", y, 11.2)

		_G.__seat = { 10.5, 12.5, 0 }
		_G.__queued = {}
		CeroSecReach.walkToFront(player, computer, function() end, true)
		x, y = walkGoal()
		eq("a seat point off the square: the stand point x", x, 10.5)
		eq("a seat point off the square: the stand point y", y, 11.2)
	end

	-- The toggle asks for no seat, so a chair standing there is not aimed at: the
	-- switch is thrown from the stand point.
	do
		local computer = world("S", true)
		_G.__seat = { 10.42, 11.61, 0 }
		local player = stander(4.5, 4.5)
		_G.__queued = {}
		CeroSecReach.walkToFront(player, computer, function() end)
		local x, y = walkGoal()
		eq("the toggle walks to the stand point x", x, 10.5)
		eq("the toggle walks to the stand point y", y, 11.2)
	end

	-- East and west shift on x and not on y. This is the mutation guard: a module
	-- that shifted the wrong axis gives 10.5, 10.2 here and 10.5 is the x of it.
	do
		local computer = world("E", false)
		local player = stander(4.5, 4.5)
		_G.__queued = {}
		CeroSecReach.walkToFront(player, computer, function() end, true)
		local x, y = walkGoal()
		eq("E: the shift is on x", x, 11.2)
		eq("E: y is the middle", y, 10.5)
	end

	-- Already at the keyboard, asked as the window asks it.
	do
		local computer = world("S", false)
		check("at the stand point", CeroSecReach.atStandPoint(stander(10.5, 11.2), computer))
		check("a hair off it is still at it",
			CeroSecReach.atStandPoint(stander(10.53, 11.17), computer))
		check("the middle of the square is not at it",
			not CeroSecReach.atStandPoint(stander(10.5, 11.5), computer))
		check("no player, not at it", not CeroSecReach.atStandPoint(nil, computer))
		local home = computer:getSquare()
		computer.getSquare = function() return nil end
		check("no stand point, not at it",
			not CeroSecReach.atStandPoint(stander(10.5, 11.2), computer))
		computer.getSquare = function() return home end
	end

	_G.__world = nil
	_G.__seat = nil
	CeroSecReach = stub
end

--
-- Drifting off the keyboard
--
-- Getting the keyboard back is also getting the character back to it. With no
-- chair to sit on that means the stand point, and only when he has really left
-- it: a click that changed nothing must queue nothing, or every press on the
-- window would cancel the typing action and start another.
--

do
	local bench = newBench()
	bench.frame()
	-- The character is at the keyboard, which is what the use action leaves behind
	-- (ISCeroSecUseAction -> CeroSecTerminal.sitDown -> startTyping), and the box
	-- has the keys.
	bench.window:startTyping("mid")
	bench.window:setEntryActive(true)

	-- Standing where he belongs: a click hands the keyboard back and nothing else.
	_G.__queued = {}
	CeroSecReach.__drifted = false
	bench.window:onMouseDown(0, 0)
	bench.window:updateSettle()
	local walks = 0
	for i = 1, #_G.__queued do
		if _G.__queued[i].__what == "walk" then walks = walks + 1 end
	end
	eq("at the keyboard: no walk queued", walks, 0)
	eq("and the typing action is untouched", bench.window.wantStand, nil)

	-- Shoved half a tile off it: the same click walks him back, and the typing
	-- action goes in behind the walk.
	CeroSecReach.__drifted = true
	bench.window:onMouseDown(0, 0)
	eq("drifted: the window owes him a step", bench.window.wantStand, true)
	eq("and the typing action was let go of", bench.window.typeAction, nil)

	_G.__queued = {}
	bench.window:updateSettle()
	eq("the debt is paid once", bench.window.wantStand, nil)
	local walk, typed = nil, nil
	for i = 1, #_G.__queued do
		if _G.__queued[i].__what == "walk" then walk = _G.__queued[i] end
		if _G.__queued[i].__what == "type" then typed = i end
	end
	check("a walk was queued", walk ~= nil)
	local sx, sy = CeroSec.standPoint(9, 10, "S")
	eq("aimed at the stand point x", walk.goal[2], sx)
	eq("aimed at the stand point y", walk.goal[3], sy)
	check("and the typing action behind it", typed ~= nil and typed > 1)

	-- A second click while the step is still owed queues nothing more.
	bench.window:onMouseDown(0, 0)
	bench.window:onMouseDown(0, 0)
	eq("one debt, not three", bench.window.wantStand, true)
	_G.__queued = {}
	bench.window:updateSettle()
	walks = 0
	for i = 1, #_G.__queued do
		if _G.__queued[i].__what == "walk" then walks = walks + 1 end
	end
	eq("and one walk", walks, 1)

	-- Back at the keyboard by the time the queue is free: nothing is walked.
	CeroSecReach.__drifted = true
	bench.window:onMouseDown(0, 0)
	CeroSecReach.__drifted = false
	_G.__queued = {}
	bench.window:updateSettle()
	walks = 0
	for i = 1, #_G.__queued do
		if _G.__queued[i].__what == "walk" then walks = walks + 1 end
	end
	eq("arrived on his own: no walk", walks, 0)

	-- Closing the window drops the debt with everything else.
	CeroSecReach.__drifted = true
	bench.window:onMouseDown(0, 0)
	eq("owed again", bench.window.wantStand, true)
	bench.window:close()
	eq("closed: nothing owed", bench.window.wantStand, nil)
	CeroSecReach.__drifted = false
end


print("window_test: " .. count .. " checks passed")
