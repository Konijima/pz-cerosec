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
--
-- startYear/startMonth/startDay are the save's FIRST day and are the same
-- zero-based encoding: GameTime's constructor sets `day` and `startDay` from one
-- literal and `month` and `startMonth` from another (javap -c zombie.GameTime),
-- so 6 and 8 here are July the 9th, 1993, which is where the default save starts
-- and where the log on a prefilled machine is dated. The world is ten days old
-- above and two days past the start here, which is deliberately not the same
-- number: a bench where the current date and the start date are one date cannot
-- tell the two getters apart.
_G.__gameTime = { year = 1993, month = 6, day = 7, hour = 14, minutes = 32,
	ageHours = 240, startYear = 1993, startMonth = 6, startDay = 8 }
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
		getStartYear = function() return t.startYear end,
		getStartMonth = function() return t.startMonth end,
		getStartDay = function() return t.startDay end,
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
--
-- PrefilledMachines is FALSE here and true in the game, for exactly the same
-- reason and it is worth spelling out: every bench in this file was written
-- against a machine that comes up with two open accounts and an empty disk, which
-- is what turning the option off IS. Left on, three hundred machines in this file
-- would come up with somebody's accounts and somebody's files on them -- the suite
-- happens to stay green, but every one of those benches would then be asking its
-- question of a machine nobody wrote it for. The content section sets it true for
-- itself and puts it back, and that section is where the option being ON is
-- proved.
_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
-- The key stands in for the sentence, because no translation table is loaded in a
-- headless harness -- plus the PARAMETERS, written after it. A refusal a player
-- reads is a sentence with the machine's own reason inside it
-- (CeroSecTerminal.driveNotice), and a fake that dropped the parameter would let a
-- bench call that sentence proved while the reason never reached the glass. That
-- the shipped string has a %1 to put it in is asserted against the EN and FR files
-- themselves, in the drive block below.
_G.getText = function(key, ...)
	local n = select("#", ...)
	if n == 0 then return key end
	local out = key
	for i = 1, n do out = out .. " " .. tostring(select(i, ...)) end
	return out
end

-- The halo over a survivor's head: the mod's door for a refusal with no screen
-- behind it, and vanilla's for the same thing. Kept in a list, because what is
-- being asserted is that a gesture which did nothing SAID so.
_G.__halos = {}
_G.HaloTextHelper = { addBadText = function(who, text)
	_G.__halos[#_G.__halos + 1] = { who = who, text = text }
end }
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
-- MapObjects, RECORDING, because the game's own answer to "created for the first
-- time in this save" is which of its two maps a closure was put in: OnNewWithSprite
-- fills `onNew`, which IsoChunk.doLoadGridsquare walks only for a chunk built out of
-- the map, and OnLoadWithSprite fills `onLoad`, which it walks for every chunk there
-- is. A fake that threw both closures away could not tell the two paths apart, and
-- the whole of the automation hangs on them being told apart.
--
-- __mapObjects.new[spriteName] and .load[spriteName] are the two maps, and
-- __fireSquare below is the engine's own walk of a square: every object on it, by
-- its OWN sprite name. The bytecode this copies, offset by offset, is at the head
-- of 42/media/lua/server/CeroSec/SCeroSecAuto.lua.
_G.__mapObjects = { new = {}, load = {} }
local function mapRegister(map)
	return function(spriteName, fn)
		if type(spriteName) ~= "string" or type(fn) ~= "function" then return end
		if map[spriteName] == nil then map[spriteName] = {} end
		map[spriteName][#map[spriteName] + 1] = fn
	end
end
_G.MapObjects = {
	OnNewWithSprite = mapRegister(_G.__mapObjects.new),
	OnLoadWithSprite = mapRegister(_G.__mapObjects.load),
}
-- `which` is "new" or "load". Answers how many closures were called, so a bench can
-- assert that the hook fired at all and not only what it did: a fire that reached
-- nothing is the shape of every green-for-nothing assertion there is.
_G.__fireSquare = function(which, square)
	local map = _G.__mapObjects[which]
	local calls = 0
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local name = object.getSpriteName ~= nil and object:getSpriteName() or nil
		local list = type(name) == "string" and map[name] or nil
		if list ~= nil then
			for k = 1, #list do
				list[k](object)
				calls = calls + 1
			end
		end
	end
	return calls
end
-- The handlers are KEPT, so that a bench can fire one. The mod hangs two things
-- on an event and nothing else can reach them: the client drops a computer's glow
-- from Events.OnObjectAboutToBeRemoved, which is what a pickup fires, and a fake
-- that threw the function away could only ever bench the other half.
_G.Events = setmetatable({}, { __index = function(t, key)
	local event = { handlers = {} }
	event.Add = function(fn) event.handlers[#event.handlers + 1] = fn end
	event.trigger = function(...)
		for i = 1, #event.handlers do event.handlers[i](...) end
	end
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
-- The CLIENT's half of the same pair, which is where a glow lives. Both base
-- classes are vanilla's, copied rather than approximated for the same reason the
-- two above are: the whole subject of the glow section at the bottom is what
-- happens INSIDE newLuaObjectAt when a chunk comes back, and the Lua that calls
-- it is Java's (media/lua/client/Map/CGlobalObject.lua and
-- CGlobalObjectSystem.lua on 42.20.4).
--
CGlobalObject = { derive = function(self, name) return derive(self, name) end }
-- A GlobalObject IS its modData table -- Java makes the table, Lua puts a
-- metatable on that very one -- so a bench's fake GlobalObject hands one over the
-- same way, and a field the client sets is a field the "packet" wrote.
CGlobalObject.new = function(self, luaSystem, globalObject)
	local o = globalObject:getModData()
	setmetatable(o, self)
	self.__index = self
	o.luaSystem = luaSystem
	o.globalObject = globalObject
	o.x = globalObject:getX()
	o.y = globalObject:getY()
	o.z = globalObject:getZ()
	return o
end
CGlobalObject.getIsoObject = function(self)
	if not self.luaSystem then return nil end
	return self.luaSystem:getIsoObjectAt(self.x, self.y, self.z)
end
CGlobalObject.getSquare = function(self)
	return getCell():getGridSquare(self.x, self.y, self.z)
end
CGlobalObject.fromModData = function(self, modData)
	for k, v in pairs(modData) do self[k] = v end
end
CGlobalObject.updateFromIsoObject = function(self)
	local isoObject = self:getIsoObject()
	if isoObject then self:fromModData(isoObject:getModData()) end
end

CGlobalObjectSystem = { derive = function(self, name) return derive(self, name) end }
CGlobalObjectSystem.RegisterSystemClass = function() end
CGlobalObjectSystem.new = function(self, name)
	local o = setmetatable({}, self)
	o.systemName = name
	-- The Java mirror: the three calls the mod and the base class make on it. A
	-- GlobalObject is keyed by its square, which is how the real lookup works
	-- (GlobalObjectLookup), so announcing the same square twice finds the first
	-- one -- the repeat the client has to survive.
	local objects, order = {}, {}
	local function key(x, y, z) return x .. "," .. y .. "," .. z end
	o.system = {
		getObjectAt = function(_, x, y, z) return objects[key(x, y, z)] end,
		getObjectCount = function() return #order end,
		getObjectByIndex = function(_, i) return order[i + 1] end,
		newObject = function(_, x, y, z)
			if objects[key(x, y, z)] then error("newObject: already one there", 2) end
			local modData = {}
			local globalObject = {
				getX = function() return x end,
				getY = function() return y end,
				getZ = function() return z end,
				getModData = function() return modData end,
			}
			objects[key(x, y, z)] = globalObject
			order[#order + 1] = globalObject
			return globalObject
		end,
		removeObject = function(_, globalObject)
			objects[key(globalObject:getX(), globalObject:getY(), globalObject:getZ())] = nil
			for i = 1, #order do
				if order[i] == globalObject then table.remove(order, i) break end
			end
		end,
	}
	o:initSystem()
	return o
end
CGlobalObjectSystem.initSystem = function() end
CGlobalObjectSystem.newLuaObjectAt = function(self, x, y, z)
	return self:newLuaObject(self.system:newObject(x, y, z))
end
CGlobalObjectSystem.getLuaObjectAt = function(self, x, y, z)
	local globalObject = self.system:getObjectAt(x, y, z)
	if globalObject then globalObject:getModData():updateFromIsoObject() end
	return globalObject and globalObject:getModData() or nil
end
CGlobalObjectSystem.getLuaObjectOnSquare = function(self, square)
	if not square then return nil end
	return self:getLuaObjectAt(square:getX(), square:getY(), square:getZ())
end
CGlobalObjectSystem.removeLuaObject = function(self, luaObject)
	if not luaObject or (luaObject.luaSystem ~= self) then return end
	self.system:removeObject(luaObject.globalObject)
end
CGlobalObjectSystem.removeLuaObjectAt = function(self, x, y, z)
	self:removeLuaObject(self:getLuaObjectAt(x, y, z))
end
CGlobalObjectSystem.getIsoObjectOnSquare = function(self, square)
	if not square then return nil end
	for i = 1, square:getObjects():size() do
		local isoObject = square:getObjects():get(i - 1)
		if self:isValidIsoObject(isoObject) then return isoObject end
	end
	return nil
end
CGlobalObjectSystem.getIsoObjectAt = function(self, x, y, z)
	local cell = getCell()
	if not cell then return nil end
	return self:getIsoObjectOnSquare(cell:getGridSquare(x, y, z))
end
CGlobalObjectSystem.getLuaObjectCount = function(self)
	return self.system:getObjectCount()
end
CGlobalObjectSystem.getLuaObjectByIndex = function(self, index)
	return self.system:getObjectByIndex(index - 1):getModData()
end

--
-- The mod, loaded the way the game loads it.
--

local LUA = "42/media/lua/"
local FILES = {
	"shared/CeroSec/CeroSecDefs.lua",
	"shared/CeroSec/CeroSecModules.lua",
	-- The world content: the catalogue and the generators the server prefills a
	-- machine from. Loaded before the OS core, which is the order the GAME loads
	-- them in (shared/CeroSec/ ahead of shared/CeroSec/OS/) and the whole reason
	-- that file may not touch CeroSecOS at its top level.
	"shared/CeroSec/CeroSecContent.lua",
	-- The telephone directory's generator: pure Lua, and the server's own
	-- enumeration (CeroSecNet.directory) names it.
	"shared/CeroSec/CeroSecPhonebook.lua",
	-- The self-test and its generated vectors, in the game's own order: the runner
	-- before the table, and neither of them touching CeroSecOS at its top level,
	-- because shared/CeroSec/ is loaded ahead of shared/CeroSec/OS/.
	"shared/CeroSec/CeroSecSelfTest.lua",
	"shared/CeroSec/CeroSecSelfTestVectors.lua",
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
	-- The premises that were automated before the outbreak. After the net layer,
	-- which it asks what a premises is, and before the object and the system, which
	-- both call into it.
	"server/CeroSec/SCeroSecAuto.lua",
	"server/CeroSec/SCeroSecDebug.lua",
	"server/CeroSec/SCeroSecJobs.lua",
	"server/CeroSec/SCeroSecObject.lua",
	-- The papers a password is found on. Loaded for real, and it REGISTERS on
	-- Events.OnFillContainer at its top level -- the fake Events above keeps
	-- handlers and can fire them, which is how the notes section below asks the
	-- game's own question.
	"server/CeroSec/CeroSecNotes.lua",
	"server/CeroSec/SCeroSecSystem.lua",
	-- The client's mirror and the glow on it. Loaded for real, and not stubbed like
	-- the CCeroSecSystem the window benches talk to: the light is the one thing in
	-- this mod that only the client has, so a stub in its place is a bench that
	-- cannot see a glow at all.
	"client/CeroSec/CCeroSecObject.lua",
	"client/CeroSec/CCeroSecSystem.lua",
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

-- The benches open both developer doors. The shipped defaults are false
-- (release); the blocks that need a shut door close it themselves.
CeroSec.DEV_MANUAL_MENU = true
CeroSec.DEV_DEBUG_MENU = true

do
	local path = FILES[#FILES]
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end
-- The game is up now, and the font it hands out for UIFont.Code is the right
-- one. Anything measured before this line was measured against the wrong one.
_G.__cellMeasure = nil

-- The real client classes, put aside: newBench below replaces the global
-- CCeroSecSystem with the stub every window bench sends its commands through, so
-- the glow section at the bottom would otherwise have nothing left to run.
local CClientSystem = CCeroSecSystem
-- And the handler the client hangs on a pickup, caught while the global still
-- names the real class (the mod's own closure reads that global, so the bench puts
-- the real one back for the moment it fires).
local OnObjectAboutToBeRemoved = Events.OnObjectAboutToBeRemoved

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
	-- On, and with a screen, without going through turnOn: a bench that booted the
	-- machine for real would also prefill it, sound it and identify it, which is
	-- four other rungs' worth of behaviour inside every window bench there is.
	-- reindex() is the one thing turnOn does that this has to do too -- the minute
	-- sweep walks an index of the machines that are on, so a machine whose `on` was
	-- written by hand is a machine no sweep would ever visit (the head of the
	-- housekeeping section in SCeroSecSystem.lua). The REAL paths into that index
	-- are benched on their own, in the county block of hostile_test.lua.
	object.on = true
	object:reindex()
	object.console = CeroSec.newConsole()
	object.consoleChecked = true
	system.getLuaObjectAt = function() return object end
	system.getIsoObjectAt = function() return nil end
	-- Every machine there is, for the walks that are not the minute sweep's: on
	-- this bench there is one.
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
	-- Every answer the server made, counted by its command word. What a screen
	-- COSTS is that number: pushScreen is one sendServerCommand per window open on
	-- the machine, so "the flood left one window" and "a screen costs one answer"
	-- are the same fact read from the two ends -- and the second is the one a
	-- player pays for.
	bench.sent = {}
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
		system.reply = function(_, _, cmd, a)
			replies[#replies + 1] = { cmd, a }
			bench.sent[cmd] = (bench.sent[cmd] or 0) + 1
			record(a)
		end
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
			-- The other answer that is not addressed to a window: the drive's refusal,
			-- which goes over a survivor's head because a drive works with the machine
			-- dark and no window open. Through the client's own door, so what is
			-- asserted is the door and not a call this bench made itself.
			if command == "drive" then
				CeroSecTerminal.onServerAnswer(command, args)
			elseif command == "reopened" then
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
	bench.enter('echo "keep me" > /home/admin/work/notes.txt')
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
	-- The BANNER over the prompt, which is getty's and is built from the file the
	-- repair has just put back. Not the motd: that one is login's, and it is not
	-- printed until somebody has got in (CeroSecOS.loginLines).
	check("and names itself over the prompt",
		bench.painted(CeroSecOS.issueText(CeroSecOS.hostname(bench.object:osState()))))
	check("and does not greet him twice", not bench.painted(CeroSecOS.MOTD))

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
-- A save written by an older build: the machine keeps everything on it
--
-- What the chain is FOR, asked at the object and not at the engine: osState is the
-- one road a saved state comes in by, and what goes in here is a state of the shape
-- before this build's -- the very thing that used to be replaced with a brand new
-- machine, filesystem and accounts and all, because the version did not match.
--
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("mkdir /home/admin/work")
	bench.enter('echo "keep me" > /home/admin/work/notes.txt')
	bench.enter("exit")
	bench.frame()

	-- The save file, as an older build left it: the shape one behind this one, and
	-- the contents number behind too. Both are what an older build really wrote.
	local saved = bench.object.os
	saved.v = CeroSecOS.STATE_VERSION - 1
	saved.sysv = 1
	bench.object.osBroken = nil
	-- And the two session flags a LOAD would arrive without, because that is what
	-- this is standing in for: the table is wound back where it lies, which nothing
	-- in the game can do, while a real older save reaches the object through
	-- gos_cerosec.bin with neither the refusal nor the validator's memo on it
	-- (osChecked is not in CeroSec.OBJECT_SAVE_KEYS). Left set, the memo would say
	-- this very table had already been through the gate -- which in this session it
	-- had, one version ago -- and the chain below would have nothing to walk.
	bench.object.osChecked = nil

	local state = bench.object:osState()
	check("the machine came back at all", state ~= nil)
	check("and it is the SAME machine, not a new one", state == saved)
	eq("at this build's shape now", state.v, CeroSecOS.STATE_VERSION)
	eq("and this build's contents", state.sysv, CeroSecOS.SYSTEM_VERSION)
	local node = CeroSecOS.systemNode(state, "/home/admin/work/notes.txt")
	check("the file in /home is still there", node ~= nil)
	eq("byte for byte", node.data, "keep me")
	check("and the accounts still log in", CeroSecOS.login(state, "admin", "") ~= nil)

	-- And it boots to a login prompt rather than to the BIOS: an older save is not
	-- damage.
	bench.window:askForScreen()
	bench.frame()
	check("and never meets the BIOS", not bench.painted("No operating system found."))
end

--
-- A save written by a LATER build: refused, untouched, and the firmware says so
--
-- The other end of the chain, and the one the mod cannot repair: the player has
-- put an older CeroSec back under a save a newer one wrote. Nothing here can read
-- the state, so nothing here touches it -- and the BIOS must not offer its
-- question, because "y" would be this build writing its own shape over a save its
-- own author could still open.
--
do
	local bench = newBench()
	bench.login("admin")
	bench.enter('echo "tomorrow" > /home/admin/n.txt')
	bench.enter("exit")
	bench.frame()

	local saved = bench.object.os
	local wrote = CeroSecOS.systemNode(saved, "/home/admin/n.txt")
	check("the file is there to begin with", wrote ~= nil)
	local was = wrote.data
	saved.v = CeroSecOS.STATE_VERSION + 1
	-- And the CONTENTS number a later build would carry, which is the witness that
	-- says whether anything here wrote to the state at all: every path that touches
	-- a machine -- the top-up and the BIOS repair alike -- ends by setting it to
	-- THIS build's number, so a state that still carries the later one is a state
	-- nothing wrote to.
	saved.sysv = CeroSecOS.SYSTEM_VERSION + 1
	bench.object.osBroken = nil
	bench.object.osNewer = nil
	-- And the validator's memo, for the reason the block above gives: a version
	-- moved where the table lies is a thing only a bench can do, and a real save
	-- from a later build reaches the object with no memo on it at all.
	bench.object.osChecked = nil

	local state, why = bench.object:osState()
	eq("the machine is refused", state, nil)
	eq("and says why", why, "newer")
	eq("the state was left at its own version", saved.v, CeroSecOS.STATE_VERSION + 1)
	eq("and its contents number is still the later build's",
		saved.sysv, CeroSecOS.SYSTEM_VERSION + 1)
	eq("and the file on it is byte for byte what it was",
		CeroSecOS.systemNode(saved, "/home/admin/n.txt").data, was)
	check("and the object still holds that very table", bench.object.os == saved)

	-- The screen. The firmware's own voice, and NOT the BIOS' question.
	bench.window:askForScreen()
	bench.frame()
	check("the firmware says what is wrong",
		bench.painted("System newer than firmware: update the mod."))
	check("and does not offer to repair it",
		not bench.painted("No operating system found."))
	eq("nothing is asked", bench.window.prompt, "")
	eq("the machine is halted", CeroSec.consoleHalted(bench.object.console), true)

	-- Typing at it says the same thing again and never the question.
	bench.enter("")
	bench.frame()
	check("still the firmware's line", bench.painted("System newer than firmware: update the mod."))
	check("and still not the BIOS' question", not bench.painted("No operating system found."))

	-- The repair itself refuses, and -- the half a return value cannot prove --
	-- writes NOTHING. A restoreSystem that ran here would put this build's system
	-- files onto a disk a later build owns and move the contents number down to
	-- ours, so the number is what says it did not run.
	eq("restoreOS does nothing", bench.object:restoreOS(), false)
	eq("and the state is still the later build's", saved.v, CeroSecOS.STATE_VERSION + 1)
	eq("and its contents number was not written down to ours",
		saved.sysv, CeroSecOS.SYSTEM_VERSION + 1)
	eq("and the file on it is still byte for byte what it was",
		CeroSecOS.systemNode(saved, "/home/admin/n.txt").data, was)
	check("and still that very table", bench.object.os == saved)

	-- And the switch at the back of the case still works, which is the whole of
	-- what a player can do about it.
	eq("it can still be switched off", bench.object:turnOff(), true)
	eq("and it is off", bench.object.on, false)
end

--
-- The two namespaces on an ITEM and an OBJECT, and their own chains
--
-- A door with boxes screwed to it and a phone book with an edition written on it are
-- save files as much as the machine is: what is in them comes back with the chunk
-- and with the item, and a change that changes their shape is owed the same promise.
-- Both carry a version now, both are walked in the ONE place they are read, and both
-- refuse to READ a table a later build wrote rather than guessing at it.
--
do
	-- An object with a modData table, which is the whole of what either namespace
	-- needs: a door for CeroSecModules, an item for CeroSecPhonebook.
	local function thing()
		local data = {}
		local o
		o = {
			transmits = 0,
			hasModData = function() return true end,
			getModData = function() return data end,
			transmitModData = function() o.transmits = o.transmits + 1 end,
		}
		return o
	end

	-- A door wired before the version existed: the ids and nothing else, which is
	-- what every door in every save carries today.
	local door = thing()
	door:getModData()[CeroSecModules.DATA_KEY] = { strike = true, contact = true }
	-- Asked BEFORE anything reads the table, which is the order that matters now that
	-- VERSION is 2: the walk in `migrate` stamps what it walks, so the first read of an
	-- older table is what moves the number on it, and a bench that asked afterwards
	-- would be asking about its own reading.
	eq("no number reads as the oldest shape",
		CeroSecModules.versionOf(door:getModData()[CeroSecModules.DATA_KEY]),
		CeroSecModules.OLDEST_VERSION)
	local fitted = CeroSecModules.installedOn(door)
	eq("an unstamped door keeps its strike", fitted.strike, true)
	eq("and its contact", fitted.contact, true)
	eq("and the read walked it up to this build and stamped it",
		door:getModData()[CeroSecModules.DATA_KEY][CeroSecModules.VERSION_KEY],
		CeroSecModules.VERSION)
	eq("without inventing a pre-fitted mark on it",
		door:getModData()[CeroSecModules.DATA_KEY][CeroSecModules.PRE_KEY], nil)
	eq("so a door an older build wired is not one this one wired",
		CeroSecModules.preFitted(door), false)

	-- The next write stamps it too, and the boxes are still there afterwards.
	eq("the server fits one more", CeroSecModules.setOn(door, "operator", true), true)
	eq("and the shape is written down",
		door:getModData()[CeroSecModules.DATA_KEY][CeroSecModules.VERSION_KEY],
		CeroSecModules.VERSION)
	fitted = CeroSecModules.installedOn(door)
	eq("the strike is still on", fitted.strike, true)
	eq("the contact is still on", fitted.contact, true)
	eq("and the operator went on", fitted.operator, true)
	eq("and the number is not read as a module", fitted[CeroSecModules.VERSION_KEY], nil)

	-- The last box off still takes the table away, stamp and all.
	CeroSecModules.setOn(door, "strike", false)
	CeroSecModules.setOn(door, "contact", false)
	CeroSecModules.setOn(door, "operator", false)
	eq("the last box off takes the stamp with it",
		door:getModData()[CeroSecModules.DATA_KEY], nil)

	-- A door a LATER build wired: not read, and not written over.
	local future = thing()
	local later = { strike = true }
	later[CeroSecModules.VERSION_KEY] = CeroSecModules.VERSION + 1
	future:getModData()[CeroSecModules.DATA_KEY] = later
	eq("a later build's door reads as nothing fitted",
		CeroSecModules.installedOn(future).strike, nil)
	eq("and its own number is untouched",
		later[CeroSecModules.VERSION_KEY], CeroSecModules.VERSION + 1)
	eq("and so is the box on it: the newer mod gives it back", later.strike, true)

	-- The phone book. A copy stamped before the version existed keeps its edition.
	local book = thing()
	book:getModData()[CeroSecPhonebook.DATA_KEY] =
		{ [CeroSecPhonebook.REGION_KEY] = { 7, 9 } }
	local rx, ry = CeroSecPhonebook.regionOn(book:getModData())
	eq("an unstamped copy keeps its region x", rx, 7)
	eq("and its region y", ry, 9)

	-- Stamping one writes the shape beside the edition, and the edition is printed
	-- once: a book carried across the county is still the book of where it was found.
	local fresh = thing()
	CeroSecPhonebook.stampRegion(fresh:getModData(), 3, 4)
	eq("a new stamp carries the shape",
		fresh:getModData()[CeroSecPhonebook.DATA_KEY][CeroSecPhonebook.VERSION_KEY],
		CeroSecPhonebook.VERSION)
	local kx = CeroSecPhonebook.stampRegion(fresh:getModData(), 11, 12)
	eq("and a second stamp changes nothing", kx, 3)

	-- A copy a LATER build stamped: read as unstamped, and left alone.
	local tomorrow = thing()
	local mine = { [CeroSecPhonebook.REGION_KEY] = { 1, 2 } }
	mine[CeroSecPhonebook.VERSION_KEY] = CeroSecPhonebook.VERSION + 1
	tomorrow:getModData()[CeroSecPhonebook.DATA_KEY] = mine
	eq("a later build's copy reads as unopened",
		CeroSecPhonebook.regionOn(tomorrow:getModData()), nil)
	eq("its number is untouched",
		mine[CeroSecPhonebook.VERSION_KEY], CeroSecPhonebook.VERSION + 1)
	eq("and so is the edition on it",
		mine[CeroSecPhonebook.REGION_KEY][1], 1)
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
-- Reported from play: "reboot should also turn the screen off, and the
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

-- ONE WINDOW PER PLAYER PER MACHINE, AND EIGHT PER MACHINE
--
-- A watcher is keyed on the token the CLIENT picked, so an `open` with a fresh
-- token each time used to add one permanent entry apiece: unbounded server
-- memory, and one sendServerCommand per entry on every later screen of that
-- machine -- paid by whoever types at it next and not by whoever sent the
-- packets. Both bounds live in SCeroSecObject:addWatcher and both are walked
-- here through the real `open` command, because a rule proved on the function
-- is not a rule on the packet.
--
-- The cost is asserted as a COUNT of answers and not in milliseconds: what is
-- wrong with a thousand watchers is a thousand packets, and a bench that timed
-- it would be measuring this machine.
do
	local bench = newBench()
	bench.login("root")

	-- One `open` packet, from whoever, with whatever token: the wire and nothing
	-- around it. The window the reply is addressed to does not exist, which is
	-- exactly what a client that never builds one looks like.
	--
	-- A REAL SECOND BETWEEN EACH, and it is not decoration. The server drops an
	-- `open` past the fourth in a second and says nothing (SCeroSecSystem:mayOpen),
	-- so a flood sent in one instant never reaches addWatcher at all -- and this
	-- block is about what happens when it DOES. Paced past the throttle, every
	-- packet below is one the server accepted, and the bounds asserted are the
	-- watcher table's own and not the rate limit's standing in for them. The
	-- throttle has its own block, on its own clock (the head of `open`'s section).
	local hadNow = _G.__now
	local function openAs(who, token)
		_G.__now = _G.__now + 1000
		CCeroSecSystem.instance:sendCommand(who, "open",
			{ x = 10, y = 10, z = 0, token = token })
	end

	-- A player of his own, standing where the first one stands. His online id is
	-- what the server keys him on, and the player number goes with it because
	-- split screen is two survivors on one connection (SCeroSecSystem.watcherIdOf).
	local function otherPlayer(id)
		local who = {}
		for key, value in pairs(bench.player) do who[key] = value end
		who.getOnlineID = function() return id end
		who.getPlayerNum = function() return 0 end
		return who
	end

	-- The first window is the one bench.login opened, and it is his.
	eq("one window on the machine to begin with", bench.object:watcherCount(), 1)

	-- A THOUSAND OPENS FROM ONE PLAYER. Every one of them a token the server has
	-- never seen, which is the whole of the defect: the key was the client's to
	-- choose and nothing else bounded the table.
	bench.closed = {}
	for i = 1, 1000 do openAs(bench.player, "flood-" .. i) end
	eq("a thousand opens from one player leave one window",
		bench.object:watcherCount(), 1)
	eq("and every window they replaced was told so", #bench.closed, 1000)
	local everyReason = true
	for i = 1, #bench.closed do
		if bench.closed[i] ~= "replaced" then everyReason = false end
	end
	check("with the one word the client shuts a box on", everyReason)

	-- AND A SCREEN STILL COSTS ONE ANSWER. The count and not the clock: the
	-- flood's cost to everybody else was one packet per entry, so one entry is
	-- one packet.
	bench.sent = {}
	local state = bench.object:osState()
	bench.system:pushScreen(bench.object, state, bench.object:consoleState())
	eq("a screen after the flood is one answer, not a thousand",
		bench.sent["screen"] or 0, 1)

	-- NINE PLAYERS AT ONE KEYBOARD, which no room holds and a forged online id
	-- costs nothing. Eight stay, and the one that went is the one that had been
	-- there longest.
	bench.closed = {}
	local crowd = {}
	for i = 1, 9 do
		crowd[i] = otherPlayer(-100 - i)
		openAs(crowd[i], "crowd-" .. i)
	end
	eq("nine players leave eight windows", bench.object:watcherCount(),
		SCeroSecObject.WATCHERS_MAX)
	-- Ten opens, nine of them new players and the first one replacing the window
	-- login left: eight survive, so two were told to shut.
	eq("two windows were told to shut", #bench.closed, 2)
	local firstToken = nil
	for _, watcher in pairs(bench.object.watchers) do
		if watcher.token == "crowd-1" then firstToken = watcher.token end
	end
	eq("and the first of the crowd is not one of the eight", firstToken, nil)
	bench.sent = {}
	bench.system:pushScreen(bench.object, state, bench.object:consoleState())
	eq("a screen costs eight answers and never more",
		bench.sent["screen"] or 0, SCeroSecObject.WATCHERS_MAX)

	-- HIS OWN WINDOW, CLOSED BY HIM, is still his own and nobody else's: the cap
	-- and the replacement both work by dropping entries, and a `close` that
	-- dropped somebody else's would be a player shutting another man's terminal.
	local mine = crowd[9]
	bench.closed = {}
	CCeroSecSystem.instance:sendCommand(mine, "close",
		{ x = 10, y = 10, z = 0, token = "crowd-9" })
	eq("a close takes exactly one window off", bench.object:watcherCount(),
		SCeroSecObject.WATCHERS_MAX - 1)
	eq("and says nothing to anybody", #bench.closed, 0)

	-- SPLIT SCREEN: TWO SURVIVORS ON ONE CLIENT, which is the one case the online id
	-- alone gets wrong. The id is the CONNECTION -- two players sharing a couch share
	-- it -- so a rule keyed on it would read the second man's window as the first
	-- man's asking twice and shut the first one, and two people at one keyboard would
	-- be left with one terminal between them. "The same player" is the id AND the
	-- player number (SCeroSecSystem.watcherIdOf, idOf).
	--
	-- Asserted as the COUNT and then as WHOSE window survived: a bench that only
	-- counted would be green on a rule that kept two windows belonging to the same
	-- man.
	local function splitPlayer(num)
		local who = {}
		for key, value in pairs(bench.player) do who[key] = value end
		who.getOnlineID = function() return -5 end
		who.getPlayerNum = function() return num end
		return who
	end
	local couch = { splitPlayer(0), splitPlayer(1) }
	bench.object:dropWatchers()
	bench.closed = {}
	openAs(couch[1], "couch-a")
	openAs(couch[2], "couch-b")
	eq("two survivors on one client keep two windows", bench.object:watcherCount(), 2)
	eq("and neither was told to shut", #bench.closed, 0)

	-- And the rule still holds for each of them on his own: the first man opening
	-- again replaces HIS window and leaves the second man's alone.
	bench.closed = {}
	openAs(couch[1], "couch-a2")
	eq("the first man's second window replaced his first", bench.object:watcherCount(), 2)
	eq("and exactly one window was told to shut", #bench.closed, 1)
	local tokens = {}
	for _, watcher in pairs(bench.object.watchers) do tokens[watcher.token] = true end
	check("his new one is there", tokens["couch-a2"] == true)
	check("his old one is gone", tokens["couch-a"] == nil)
	check("and the other survivor's is untouched", tokens["couch-b"] == true)

	-- The clock put back where the file's other blocks left it: this one wound it
	-- forward by a quarter of an hour to get past the rate limit, and the benches
	-- below measure boot animations and reboot delays against it.
	_G.__now = hadNow
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
	_G.__gameTime = { year = 1993, month = 11, day = 24, hour = 6, minutes = 5,
		ageHours = 240, startYear = 1993, startMonth = 6, startDay = 8 }
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

	-- Put back exactly as it was found, START DATE INCLUDED: a section that restored
	-- only the current date left every section after it running on a game that would
	-- not say when the save began, and a prefilled machine with no log on it.
	_G.__gameTime = { year = 1993, month = 6, day = 7, hour = 14, minutes = 32,
		ageHours = 240, startYear = 1993, startMonth = 6, startDay = 8 }
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
-- `sudo useradd` and `su` are the two of this rung that are not one command and
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

	bench.enter("sudo useradd bob")
	bench.frame()
	eq("sudo asks first", bench.window.prompt, "[sudo] password for admin: ")
	eq("and hides the answer", bench.window.mask, true)
	bench.enter("")
	bench.frame()
	check("the account was made", bench.painted("useradd: bob: created"))
	check("and the open password is said out loud",
		bench.painted("useradd: set a password with passwd bob"))
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
	check("the screen kept what was on it", bench.painted("useradd: bob: created"))

	-- The second one is a logout.
	bench.enter("exit")
	bench.frame()
	eq("the login prompt is back", bench.window.prompt, "login: ")
	eq("at a prompt, not a shell", bench.window.mode, "prompt")
	eq("nobody is logged in", bench.object.console.user, nil)
	check("and the screen was wiped", not bench.painted("useradd: bob: created"))
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
	bench.enter("sudo useradd bob")
	bench.frame()
	check("bob is on the machine", bench.painted("useradd: bob: created"))

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
	-- WHAT A WALK COSTS, in the only two things it is made of: the squares the
	-- engine handed over and the objects looked at on them. A bench that timed the
	-- pre-fitting would be timing this machine; the number of engine calls is the
	-- thing the mall bench below is really about, so the fake counts them.
	world.visits = { squares = 0, objects = 0 }
	local function counted(items, field)
		return {
			size = function() return #items end,
			get = function(_, i)
				world.visits[field] = world.visits[field] + 1
				return items[i + 1]
			end,
		}
	end
	world.forgetVisits = function()
		world.visits.squares, world.visits.objects = 0, 0
	end

	world.getGridSquare = function(_, x, y, z)
		return world.squares[x .. "," .. y .. "," .. z]
	end

	-- A room, and the squares in it. The building is every room there is: a
	-- square that belongs to a room belongs to the building.
	--
	-- It has an OUTLINE too, worked out from the squares put in it, because a real
	-- RoomDef has one: the corner and the floor are what the tenancy rule groups
	-- rooms by and what the pre-fitting names a room in a save by
	-- (CeroSecNet.buildingRooms). x2 and y2 are exclusive, as the engine's are.
	world.room = function(name, coords)
		local room = { name = name, squares = {} }
		world.rooms[name] = room
		world.roomOrder[#world.roomOrder + 1] = room
		room.getName = function() return name end
		room.getSquares = function() return counted(room.squares, "squares") end
		for i = 1, #coords do
			local x, y, z = coords[i][1], coords[i][2], coords[i][3]
			if room.x == nil or x < room.x then room.x = x end
			if room.y == nil or y < room.y then room.y = y end
			if room.x2 == nil or x + 1 > room.x2 then room.x2 = x + 1 end
			if room.y2 == nil or y + 1 > room.y2 then room.y2 = y + 1 end
			if room.level == nil then room.level = z end
		end
		-- The SUM of the room's tiles, which is what RoomDef.getArea answers, and
		-- not the box: a bench room is a handful of squares in a corner of it.
		room.area = #coords
		for i = 1, #coords do
			local sq = world.square(coords[i][1], coords[i][2], coords[i][3], room)
			room.squares[#room.squares + 1] = sq
		end
		return room
	end

	-- The building's footprint, for the one question that needs it: which PREMISES a
	-- square is in (CeroSecNet.premisesOfSquare reads getX/getY/getX2/getY2 off the
	-- def). nil is a def that will not say, which is every bench written before the
	-- automation and is why premisesOfSquare answers nothing for them -- a device
	-- bench has no premises in it and wants none.
	world.box = nil

	-- A RoomDef, as the engine hands one over: the outline, the floor, the summed
	-- area, and the LIVE room -- nil while its chunks are away, which is what
	-- getIsoRoom answers (IsoMetaGrid.getRoomByID on the def's own id).
	-- `world.loaded = false` takes the whole building away; `room.away = true` takes
	-- one room, which is the state a building half streamed in is really in.
	local function roomDef(room)
		return {
			getName = function() return room.name end,
			getIsoRoom = function()
				if world.loaded == false or room.away == true then return nil end
				return room
			end,
			getX = function() return room.x end,
			getY = function() return room.y end,
			getX2 = function() return room.x2 end,
			getY2 = function() return room.y2 end,
			getZ = function() return room.level end,
			getArea = function() return room.area end,
		}
	end
	world.roomDef = roomDef

	world.building = {
		getDef = function()
			local defs = {}
			for i = 1, #world.roomOrder do
				defs[i] = roomDef(world.roomOrder[i])
			end
			local def = { getRooms = function() return javaList(defs) end }
			if world.box ~= nil then
				local b = world.box
				def.getX = function() return b.x end
				def.getY = function() return b.y end
				def.getX2 = function() return b.x + b.w end
				def.getY2 = function() return b.y + b.h end
				def.getArea = function() return b.w * b.h end
				def.getRoomsNumber = function() return #world.roomOrder end
			end
			return def
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
		-- The square's own RoomDef, which is the door CeroSecNet.roomDefAt goes
		-- through: IsoGridSquare.getRoomDef is getRoom() and then
		-- IsoRoom.getRoomDef(), null without a room. It is what decides WHICH
		-- tenancy of a mall a square belongs to.
		sq.getRoomDef = function()
			if room == nil then return nil end
			return roomDef(room)
		end
		sq.getBuilding = function() if room ~= nil then return world.building end return nil end
		sq.getObjects = function() return counted(sq.objects, "objects") end
		sq.getWorldObjects = function() return javaList(sq.items) end
		sq.getMovingObjects = function() return javaList(sq.bodies) end
		-- The wire, asked the way the game's own Lua asks it
		-- (ISWorldObjectContextMenu.lua:460, and SCeroSecObject:hasPower). A world
		-- with `power = false` in it is a county whose grid has gone, which is the one
		-- thing that stops a premises' machine coming up on its own.
		sq.haveElectricity = function() return world.power ~= false end
		sq.hasGridPower = function() return world.power ~= false end
		sq.playSound = function() end
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
-- ONCE PER STATE, NOT ONCE PER READ: the gate, and the belts under it
--
-- validate walks every node of the filesystem and every table of the disk in the
-- drive, and osState used to run it on every read -- three times a game minute for
-- every machine that is on, and once per packet. Measured on the 300-machine rig it
-- was 0.887 of the 0.894 ms a read cost, and 104 of the 104 ms a game minute cost
-- (tests/hostile_test.lua, the county block).
--
-- So it is remembered against the TABLE it was asked about. What this block is for
-- is the other half of that sentence: the memo must never let a table nobody
-- validated through, and the two belts must go on sweeping whether the memo hit or
-- not -- because what they keep out of the save file is not a refusal, it is a
-- machine somebody loses on his next load.
--
-- WHAT IS COUNTED IS CALLS TO validate, through a wrapper, because "once" is the
-- whole claim and a bench that only read the state back would be green on a gate
-- that ran a hundred times.
--
do
	local kit = mockupWorld()
	local hadWorld = _G.__world
	_G.__world = kit.world

	local bench = newBench()
	bench.login("admin")
	bench.enter("mkdir /home/admin/keep")
	bench.frame()

	local realValidate = CeroSecOS.validate
	local validations = 0
	CeroSecOS.validate = function(state)
		validations = validations + 1
		return realValidate(state)
	end

	-- A HUNDRED READS, ONE WALK.
	local first = bench.object:osState()
	check("the machine reads at all", first ~= nil)
	validations = 0
	for _ = 1, 100 do
		local again = bench.object:osState()
		if again ~= first then check("every read is the same table", false) end
	end
	eq("a hundred reads of one machine validate nothing", validations, 0)

	-- A STATE REPLACED IS A STATE VALIDATED AGAIN, and by the real paths that
	-- replace one rather than by writing the memo away. First the developer's reset,
	-- which throws the state out and makes a fresh machine of it.
	eq("it goes off for the reset", bench.object:turnOff(), true)
	validations = 0
	eq("the reset went through", bench.object:resetMachine(), true)
	-- And the memo went with the state, which is what setOS is for. Identity alone
	-- would already be safe -- a fresh table is not the one the memo names -- so what
	-- this asserts is the OTHER half: the memo must not go on holding the filesystem
	-- that was thrown away. A server that reset a hundred machines would be holding a
	-- hundred dead filesystems of up to 32 KB each, for no reason anybody could find.
	check("the reset let go of the state it threw away",
		bench.object.osChecked ~= first)
	local afterReset = bench.object:osState()
	check("and there is a machine again", afterReset ~= nil)
	check("a different table from the one before", afterReset ~= first)
	check("which was validated", validations > 0)

	-- AND THE MEMO IS THE TABLE, NEVER A FLAG, which is what makes the line above
	-- true of a path nobody has written yet. Every writer in the mod today goes
	-- through setOS and clears it, so a boolean would behave exactly the same on
	-- every one of them -- and the day one writer forgets, a boolean is a table
	-- nothing ever validated being run on, while identity is a different table and
	-- says so. Written straight onto the field here BECAUSE no shipped path does:
	-- that is the mistake being guarded, and a bench that went through the setter
	-- would be proving the setter instead.
	local behindTheSetter = CeroSecOS.newState("sneaked")
	bench.object.os = behindTheSetter
	validations = 0
	eq("a state written behind the setter's back still reads",
		bench.object:osState(), behindTheSetter)
	check("and it was walked by the gate, memo or no memo", validations > 0)

	-- And a computer put down out of somebody's hands, carrying the state the ITEM
	-- brought: the movableData mirror is the road a state comes in by on a server,
	-- and what is in it came off a client.
	local carried = CeroSecOS.newState("carried")
	local iso = { modData = { movableData = { [CeroSec.MOVABLE_DATA_KEY] = { os = carried } } } }
	iso.getSpriteName = function() return CeroSec.SPRITES_OFF["S"] end
	iso.hasModData = function() return true end
	iso.getModData = function() return iso.modData end
	iso.transmitModData = function() end
	validations = 0
	bench.object:resetForPlacement(iso)
	check("the carried state was validated on the way in", validations > 0)
	eq("and it is the machine now", bench.object:osState(), carried)

	-- A FORGED ONE IS STILL REFUSED. Same road, and the table in the mirror is what
	-- a client on a server can write: the memo must not be what lets it past.
	local forged = { v = CeroSecOS.STATE_VERSION, sysv = CeroSecOS.SYSTEM_VERSION,
		hostname = "forged", fs = "not a filesystem" }
	iso.modData.movableData[CeroSec.MOVABLE_DATA_KEY].os = forged
	validations = 0
	bench.object:resetForPlacement(iso)
	check("the forged state was walked by the gate and not waved through",
		validations > 0)
	local refused, why = bench.object:osState()
	eq("a forged state is refused", refused, nil)
	eq("and the refusal is sticky", bench.object.osBroken, true)
	-- "refused" and not the validator's own words, because the placement above is
	-- what asked the gate and it is the gate that logged the reason: from here on the
	-- machine answers the sticky refusal, which is the behaviour and not a shortcut.
	eq("and every read after it says so", why, "refused")

	-- THE BELTS, WHICH ARE NOT MEMOISED, and the reason they are not: `os` is a saved
	-- key, so a device node left on /dev by a pass that died mid-command would go into
	-- gos_cerosec.bin and be refused on the next load -- where the memo starts empty.
	-- Provoked with the REAL mount and no unmount after it, which is exactly what an
	-- error thrown between CeroSecOS.mountDev and CeroSecOS.unmountDev leaves behind.
	local bench2 = newBench()
	bench2.login("admin")
	bench2.frame()
	local live = bench2.object:osState()
	check("the machine reads", live ~= nil)
	local env = bench2.system:execEnv(bench2.object, live, bench2.player, nil)
	CeroSecOS.mountDev(live, env)
	local devDir = CeroSecOS.systemNode(live, CeroSecOS.DEV_PATH)
	local mounted = 0
	for _, node in pairs(devDir.children) do
		if CeroSecOS.isDev(node) and not CeroSecOS.isNull(node) then mounted = mounted + 1 end
	end
	check("the office's switches really are on /dev now (" .. mounted .. ")", mounted > 0)

	-- And the read after it. The STATE and not the call: what matters is that there is
	-- no device of the world left in the table the save file would be written from.
	validations = 0
	local swept = bench2.object:osState()
	check("the machine still reads after a pass that died mid-command", swept ~= nil)
	eq("and it is the same table, so the memo held", swept, live)
	eq("nothing was validated a second time", validations, 0)
	local left = 0
	for _, node in pairs(CeroSecOS.systemNode(swept, CeroSecOS.DEV_PATH).children) do
		if CeroSecOS.isDev(node) and not CeroSecOS.isNull(node) then left = left + 1 end
	end
	eq("and not one device of the world is left in the state", left, 0)
	check("while the machine's own /dev/null is still there",
		CeroSecOS.systemNode(swept, CeroSecOS.DEV_PATH).children["null"] ~= nil)

	-- The mount table gets the same belt, on the same read: a mount naming a drive
	-- with no disk in it is one a save file can hold.
	swept.mounts = { { dir = "/mnt", dev = CeroSecOS.FD_NAME } }
	bench2.object:osState()
	eq("a mount with nothing behind it is dropped on the way out", swept.mounts, nil)

	-- AND THE ONE PATH THAT REWRITES A STATE WITHOUT REPLACING IT: the BIOS repair.
	-- restoreSystem remakes /etc, /bin and the filesystem root where the table LIES,
	-- so identity alone would say it had already been through the gate. Reached on a
	-- machine that is not refused at all, which is the case that has a memo on it: an
	-- empty /bin is "no operating system" to systemOk and a perfectly valid state to
	-- the gate, so this is the state the BIOS asks its question about with the memo
	-- set.
	local repaired = bench2.object:osState()
	repaired.fs.children.bin.children = {}
	eq("an empty /bin is no operating system", CeroSecOS.systemOk(repaired), false)
	eq("and the state is still one the core can run on",
		CeroSecOS.validate(repaired), true)
	validations = 0
	eq("the firmware repaired it", bench2.object:restoreOS(), true)
	check("and the state it rewrote went through the gate again", validations > 0)
	check("with /bin back on it",
		CeroSecOS.countEntries(repaired.fs.children.bin) > 0)

	CeroSecOS.validate = realValidate
	_G.__world = hadWorld
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
	bench.enter("useradd bob")
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

-- What a script of yours can see, end to end, at a real glass: the ENVIRONMENT
-- and not the shell's variables.
--
-- A script is a program, and a program is handed a copy of the exported names --
-- PATH and HOME from the login, and whatever `export` has added. It used to be
-- handed the prompt's own table BY REFERENCE in the foreground, so `x=hi` was
-- visible inside a file nobody had exported anything to and an assignment inside
-- a file came back out to the prompt. The engine's half is pinned in os_test;
-- what is asked here is that the console's set is the set that travels.
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/where.sh",
		'echo "HOME is [$HOME] x is [$x] w is [$w]"\n')
	bench.script("/home/admin/set.sh", "y=inside\n")

	-- w is set and never exported, and it is what the `&` case below is for: a
	-- subshell that lost the MARKS and kept the values would hand a script
	-- everything, and every assertion about an exported name would still pass.
	bench.enter("x=hi")
	bench.enter("w=secret")
	bench.enter("./where.sh")
	bench.tick(3)
	bench.frame()
	check("a login's HOME is in the environment and reaches the script",
		bench.painted("HOME is [/home/admin] x is [] w is []"))

	bench.enter("export x")
	bench.enter("./where.sh")
	bench.tick(3)
	bench.frame()
	check("and an exported variable reaches it too",
		bench.painted("HOME is [/home/admin] x is [hi] w is []"))

	-- Behind the prompt, the same answer: the `&` makes a subshell, and a
	-- subshell carries the marks as well as the values.
	--
	-- A script of its OWN, and a line that says which run wrote it: the glass
	-- keeps what has scrolled past, so an assertion about the same words would be
	-- satisfied by the foreground run above and could never go red.
	bench.script("/home/admin/bgwhere.sh",
		'echo "bg HOME is [$HOME] x is [$x] w is [$w]"\n')
	bench.enter("./bgwhere.sh &")
	bench.tick(4)
	bench.frame()
	check("behind the prompt it is the same environment",
		bench.painted("bg HOME is [/home/admin] x is [hi] w is []"))

	-- And nothing a script sets comes back, foreground or background.
	bench.enter("y=outside")
	bench.enter("./set.sh &")
	bench.tick(4)
	bench.enter("echo [$y]")
	bench.tick(2)
	bench.frame()
	check("what the background job set did not come back", bench.painted("[outside]"))
	check("and certainly not that", not bench.painted("[inside]"))
	bench.enter("./set.sh")
	bench.tick(3)
	bench.enter("echo [$y]")
	bench.tick(2)
	bench.frame()
	check("nor what the foreground one set", bench.painted("[outside]"))

	-- And a script started by a command that asked a QUESTION first: the password
	-- comes back, the continuation hands back a job order, and the shell that
	-- asked runs it one level deeper -- so the environment has to survive the
	-- question as well as the line. Its own file again, so the assertion cannot be
	-- satisfied by a line further up the glass.
	bench.script("/home/admin/suwhere.sh",
		'echo "su HOME is [$HOME] x is [$x] w is [$w]"\n')
	bench.enter("sudo sh /home/admin/suwhere.sh")
	bench.frame()
	eq("sudo asks first", bench.window.prompt, "[sudo] password for admin: ")
	bench.enter("")
	bench.tick(4)
	bench.frame()
	check("a job made off a continuation is handed the same environment",
		bench.painted("su HOME is [/home/admin] x is [hi] w is []"))

	-- The one way in is the dot, which reads the file in the shell standing there.
	bench.enter(". ./set.sh")
	bench.tick(3)
	bench.enter("echo [$y]")
	bench.tick(2)
	bench.frame()
	check("the dot reads it into this shell", bench.painted("[inside]"))
end

-- at, end to end: the queue, the minute it comes round, and the mail.
--
-- The engine's half is pinned in os_test. This is the other half: the file in
-- /var/spool/at, the sweep that reads it (the same one that reads the crontabs),
-- the job it makes, where the output goes, and -- the thing that is at's and not
-- cron's -- that a job whose time PASSED while the machine was off still runs.
do
	local bench = newBench()
	bench.login("admin")
	-- The commands go in from a FILE and not from an echo on the line: the glass
	-- keeps what has scrolled past, so a line typed with the command in it would
	-- satisfy every assertion below about what did NOT reach the screen.
	CeroSecOS.writeFile(bench.object:osState(), CeroSecOS.rootSession(),
		"/home/admin/plan", "echo lamps-out", false, 100)
	-- The bench's clock says 14:32, so 14:33 is a minute away.
	-- A pipeline takes a few passes: the stage on the right reads what the stage on
	-- the left has written, and `at` cannot answer until the pipe has closed.
	bench.enter("cat plan | at 14:33")
	bench.tick(3)
	check("at says which job and when", bench.painted("job 1 at"))
	-- The queue is a file, root's and 600, which is what makes it nobody's to read.
	local spooled = bench.fileText("/var/spool/at/1")
	check("the job is a file in the spool", spooled ~= nil)
	check("with the account and the time on its first line",
		spooled ~= nil and string.find(spooled, "^at admin %d+\n") ~= nil)
	check("and the commands after it",
		spooled ~= nil and string.find(spooled, "echo lamps-out", 1, true) ~= nil)
	bench.enter("cat /var/spool/at/1")
	bench.frame()
	check("an ordinary account cannot read it",
		bench.painted("/var/spool/at/1: permission denied"))

	-- atq lists it, and it is still there: a listing runs nothing.
	bench.enter("atq")
	bench.frame()
	check("atq lists the job", bench.painted("1  "))
	check("the queue still holds it", bench.fileText("/var/spool/at/1") ~= nil)

	-- The minute comes round. The sweep is the game's own EveryOneMinute, which is
	-- the power check and the cron pass -- and now the at pass with them.
	bench.minute()
	bench.tick(4)
	eq("the job is out of the queue", bench.fileText("/var/spool/at/1"), nil)
	local mail = bench.fileText("/var/mail/admin")
	check("and what it printed went to the account's mail", mail ~= nil)
	check("which is where a job nobody is watching prints",
		mail ~= nil and string.find(mail, "lamps-out", 1, true) ~= nil)
	check("nothing of it reached the glass", not bench.painted("lamps-out"))
	-- And the queue is empty, asked of the queue and not of the glass: what has
	-- scrolled past is still painted, so an atq that printed nothing looks exactly
	-- like the atq above that printed something.
	eq("and the queue is empty", #CeroSecOS.atJobs(bench.object:osState()), 0)

	-- A job whose time passed while nobody was sweeping. cron would let the minute
	-- go -- there is no anacron here -- but an at job is a thing somebody asked
	-- for, and it sits in the queue until it has been done.
	CeroSecOS.writeFile(bench.object:osState(), CeroSecOS.rootSession(),
		"/home/admin/plan2", "echo caught-up", false, 100)
	bench.enter("cat plan2 | at 14:35")
	bench.tick(3)
	check("the second job is queued", bench.fileText("/var/spool/at/1") ~= nil)
	-- Ten minutes of game clock with no sweep at all: the chunk was away.
	local clock = _G.__gameTime
	clock.minutes = clock.minutes + 10
	bench.minute()
	bench.tick(4)
	eq("a late job still ran", bench.fileText("/var/spool/at/1"), nil)
	check("and its output is in the mail too",
		string.find(bench.fileText("/var/mail/admin"), "caught-up", 1, true) ~= nil)

	-- atrm takes one out, and then there is nothing to run.
	bench.enter("cat plan | at 16:00")
	bench.tick(3)
	bench.enter("atrm 1")
	bench.frame()
	eq("atrm took it out of the queue", bench.fileText("/var/spool/at/1"), nil)
	local before = bench.fileText("/var/mail/admin")
	bench.minute(200)
	bench.tick(4)
	eq("so nothing ever ran it", bench.fileText("/var/mail/admin"), before)
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
-- round trip the screenshot from play was of: a loop typed at the glass.
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

-- THE LOGIN SEQUENCE, on the glass and through the protocol.
--
-- What a 1993 machine printed, in order: getty's banner (/etc/issue) under the
-- firmware's lines and over the prompt, then -- once the password is right --
-- login's own three lines, which are the last login, /etc/motd and the mail.
-- The motd used to be printed in BOTH places, which is the bug this proves gone.
do
	local bench = newBench()
	local state = bench.object:osState()
	local BANNER = CeroSecOS.issueText(CeroSecOS.hostname(state))

	bench.window:askForScreen()
	_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
	bench.frame()
	eq("the machine ends at the login prompt", bench.window.prompt, "login: ")
	check("the firmware counted itself out", bench.painted("Memory test"))
	check("the banner is over the prompt", bench.painted(BANNER))
	check("and the motd is NOT on a screen nobody has logged in on",
		not bench.painted(CeroSecOS.MOTD))
	-- The ORDER, off the glass itself: the banner is under the firmware's lines,
	-- which is where getty printed it.
	local glass = bench.glass()
	local firmware, banner = nil, nil
	for i = 1, #glass do
		if string.find(glass[i], "Booting from hda", 1, true) then firmware = i end
		if string.find(glass[i], BANNER, 1, true) then banner = i end
	end
	check("the firmware printed first", firmware ~= nil)
	check("and the banner under it", banner ~= nil and banner > firmware)

	-- THE FIRST LOGIN. Nothing to say about a last one -- this account has never
	-- been in -- and the motd once.
	bench.enter("admin")
	bench.enter("")
	bench.frame()
	eq("admin is at a shell", bench.window.mode, "shell")
	check("the first login says nothing about a last one",
		not bench.painted("Last login:"))
	check("and the motd greets him", bench.painted(CeroSecOS.MOTD))
	-- Once and not twice: the banner is still further up the same screen, so a motd
	-- printed in both places would be two copies of it here. Counted on the
	-- console's own rows and not on the glass -- the terminal paints every row twice
	-- for the phosphor behind it, so a count off bench.glass() is two of everything
	-- and could never be one.
	local function rowsSaying(text)
		local seen = 0
		local rows = bench.object.console.lines
		for i = 1, #rows do
			if rows[i] == text then seen = seen + 1 end
		end
		return seen
	end
	eq("exactly one motd on the screen", rowsSaying(CeroSecOS.MOTD), 1)

	-- THE SECOND LOGIN, at the same keyboard: the first one is named, with the date
	-- it happened and the line it was at.
	local at = bench.object.console.loginAt
	bench.enter("exit")
	bench.frame()
	eq("the machine is back at login", bench.window.prompt, "login: ")
	bench.enter("admin")
	bench.enter("")
	bench.frame()
	check("the second login names the first",
		bench.painted("Last login: " .. CeroSecOS.formatStamp(at) .. " on console"))
	check("and the motd is still printed", bench.painted(CeroSecOS.MOTD))
	check("and there is no mail to announce", not bench.painted("You have mail."))

	-- THE MAIL. Put in the spool the only way anything puts mail on this machine:
	-- cron, writing to the account whose line it ran.
	check("cron wrote to the spool", CeroSecOS.mailAppend(state, "admin",
		CeroSecOS.hostname(state), "echo hi", { "hi" }, 100))
	check("there is mail in the spool now",
		(bench.fileText(CeroSecOS.mailPath("admin")) or "") ~= "")
	bench.enter("exit")
	bench.frame()
	bench.enter("admin")
	bench.enter("")
	bench.frame()
	check("so the next login says so", bench.painted("You have mail."))
	check("and never in the new-mail wording", not bench.painted("You have new mail."))

	-- ~/.hushlogin: a login that says nothing at all. Made with `touch`, which is
	-- the whole of the gesture on a real machine too.
	bench.enter("touch .hushlogin")
	bench.frame()
	bench.enter("exit")
	bench.frame()
	bench.enter("admin")
	bench.enter("")
	bench.frame()
	eq("he is in", bench.window.mode, "shell")
	check("the motd is silenced", not bench.painted(CeroSecOS.MOTD))
	check("and so is the last login", not bench.painted("Last login:"))
	check("and so is the mail", not bench.painted("You have mail."))
	-- And it is HIS silence and not the machine's: root at the same keyboard is
	-- greeted exactly as before.
	bench.enter("exit")
	bench.frame()
	bench.enter("root")
	bench.enter("")
	bench.frame()
	check("another account is greeted", bench.painted(CeroSecOS.MOTD))
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
	check("and it is pending", CeroSecJobs.pendingShutdown(bench.object) ~= nil)
	eq("the machine is still up", bench.object.on, true)
	-- A pending order is a PROCESS, so it is in the book like any other: `jobs`
	-- shows it, under the account that gave it.
	local pending = CeroSecJobs.pendingShutdown(bench.object)
	eq("it is a job named shutdown", pending.name, "shutdown")
	eq("owned by the account that ordered it", pending.session.user, "root")
	eq("waiting, and spending nothing", pending.state, "waiting")
	bench.enter("jobs")
	bench.frame()
	check("jobs lists it", bench.painted("shutdown -r +1"))
	bench.enter("ps")
	bench.frame()
	check("and so does ps", bench.painted("shutdown -r +1"))
	-- A SECOND one is allowed, because two processes are: the first minute to
	-- arrive is the one that takes the machine down.
	bench.enter("shutdown -h +5")
	bench.frame()
	check("a second order is taken", bench.painted("going down for halt in 5"))
	check("no refusal", not bench.painted("already scheduled"))
	local two = 0
	for i = 1, #bench.object.jobs.list do
		if bench.object.jobs.list[i].shutdown ~= nil then two = two + 1 end
	end
	eq("two processes are sleeping on it", two, 2)

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
	eq("nothing is pending any more",
		CeroSecJobs.pendingShutdown(bench.object), nil)

	_G.__now = _G.__now + CeroSec.REBOOT_DARK_MS
	bench.tick(1)
	eq("and the machine came back", bench.object.on, true)
	eq("with nobody logged in", bench.object.console.user, nil)
	eq("and two windows back at it", #bench.windows, 4)
	_G.__world = nil
end

-- Calling a pending order off, which is killing the process that holds it, and
-- the warning a minute out on a longer one.
do
	local bench = newBench()
	bench.login("root")

	bench.enter("shutdown -h +2")
	bench.frame()
	check("two minutes out", bench.painted("The system is going down for halt in 2 minutes!"))
	local pending = CeroSecJobs.pendingShutdown(bench.object)
	check("it is a process", pending ~= nil)

	-- A minute passes: the warning, and still up.
	_G.__now = _G.__now + 61000
	bench.tick(1)
	check("the minute warning", bench.painted("The system is going down for halt in 1 minute!"))
	eq("still up", bench.object.on, true)

	-- `shutdown -c` is not a flag on this machine any more: it is sysvinit's.
	bench.enter("shutdown -c")
	bench.frame()
	check("the flag is gone", bench.painted("usage: shutdown [-h|-r] now|+N"))
	check("and nothing was cancelled by it",
		CeroSecJobs.pendingShutdown(bench.object) ~= nil)

	-- kill is how it is called off, by its slot or by its id, and kill says
	-- nothing at all when it worked.
	bench.enter("kill %" .. pending.n)
	bench.frame()
	bench.tick(1)
	eq("and nothing is pending", CeroSecJobs.pendingShutdown(bench.object), nil)

	-- The minute it would have gone down on comes and goes.
	_G.__now = _G.__now + 120000
	bench.tick(2)
	eq("the machine is still up", bench.object.on, true)
	eq("and the scheduler has let it go", #CeroSecJobs.machines, 0)
end

-- A pending order whose process is DEAD does not fire, and the clock is what has
-- to know it: the reaping normally takes a killed job off the book inside the very
-- pass that killed it, so this is the one thing the ordinary path cannot show --
-- the order still in the book with its job killed, which is what a pass would see
-- if anything ever killed one between two passes.
do
	local bench = newBench()
	bench.login("root")
	bench.enter("shutdown -h +1")
	bench.frame()
	local pending = CeroSecJobs.pendingShutdown(bench.object)
	check("the order is pending", pending ~= nil)
	-- Killed where it stands, and NOT reaped: no pass is run in between.
	CeroSecOS.killJob(pending, nil)
	eq("the job is dead", pending.state, "killed")
	check("and still on the book", CeroSecJobs.book(bench.object).list[1] == pending)
	-- The minute arrives and the clock looks at the book.
	CeroSecJobs.checkShutdown(CeroSecJobs.system, bench.object, _G.__now + 120000)
	eq("a dead process switches nothing off", bench.object.on, true)
	check("and the order is not pending any more",
		CeroSecJobs.pendingShutdown(bench.object) == nil)
end

-- A LINE TYPED PAST THE MINUTE does not lose the order, and this is why the
-- pending shutdown is a job that never runs rather than one asleep on a timer: a
-- pass run in a player's own hand (Commands.exec, Commands.input) steps the jobs
-- without looking at the shutdown clock at all, so an order asleep on a wake-up
-- time would come due there, run out of a program with nothing in it, and finish
-- quietly having switched nothing off.
do
	local bench = newBench()
	bench.login("root")
	bench.enter("shutdown -h +1")
	bench.frame()
	check("the order is pending", CeroSecJobs.pendingShutdown(bench.object) ~= nil)

	-- The minute passes with no scheduler pass in it, and then a line is typed:
	-- that line's own pass is the first thing to touch the book.
	_G.__now = _G.__now + 61000
	bench.enter("echo hi")
	bench.frame()
	check("the line ran", bench.painted("hi"))
	eq("the machine is still on: only the clock may switch it off",
		bench.object.on, true)
	check("and the order is still pending",
		CeroSecJobs.pendingShutdown(bench.object) ~= nil)

	-- And the scheduler's own pass is what carries it out.
	bench.tick(1)
	eq("now it is off", bench.object.on, false)
end

-- An ordinary account may not kill root's shutdown, which is kill(2)'s own rule
-- and the reason it arrived: an account that could would be an account that can
-- switch the machine off.
do
	local bench = newBench()
	bench.login("root")
	bench.enter("shutdown -h +2")
	bench.frame()
	local pending = CeroSecJobs.pendingShutdown(bench.object)
	check("root's order is pending", pending ~= nil)

	bench.enter("exit")
	bench.frame()
	bench.login("admin")
	bench.enter("kill " .. pending.id)
	bench.frame()
	bench.tick(1)
	check("an ordinary account is refused",
		bench.painted("kill: " .. pending.id .. ": Operation not permitted"))
	check("and the order stands", CeroSecJobs.pendingShutdown(bench.object) ~= nil)
	eq("and the machine is still going down at the minute", bench.object.on, true)

	-- It still fires, having survived the wrong hands.
	_G.__now = _G.__now + 121000
	bench.tick(1)
	eq("the machine is off", bench.object.on, false)
end

-- `shutdown -r +1` killed before the minute is a machine that does not reboot.
do
	local bench = newBench()
	bench.login("root")
	bench.enter("shutdown -r +1")
	bench.frame()
	local pending = CeroSecJobs.pendingShutdown(bench.object)
	bench.enter("kill " .. pending.id)
	bench.frame()
	bench.tick(1)
	_G.__now = _G.__now + 121000
	bench.tick(2)
	eq("no reboot", bench.object.on, true)
	check("and nothing is dark", bench.object.rebooting == nil)
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
	bench.enter("echo hi > notes.txt")
	bench.enter("echo hi > note2.txt")
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

	-- And a command name is completed on the shell's OWN PATH, which is the wire
	-- this end proves: the engine's half is pinned in os_test, and what is asked
	-- here is that the value the console holds is the value that walk gets. A
	-- `hello` of his own, and the PATH entry that makes it a command.
	bench.enter("mkdir bin")
	bench.enter("echo hi > bin/hello")
	bench.enter("chmod 755 bin/hello")
	bench.frame()
	bench.typed("hell")
	bench.tab()
	bench.frame()
	eq("a command of his own is not completed before the PATH names it",
		bench.window.entry:getInternalText(), "hell")
	bench.enter("PATH=$PATH:$HOME/bin")
	bench.frame()
	bench.typed("hell")
	bench.tab()
	bench.frame()
	eq("and is completed once it does",
		bench.window.entry:getInternalText(), "hello ")
	-- The same shell, and the same value: the line really runs.
	bench.enter("hello")
	bench.frame()
	check("and the name the completion offered runs", bench.heard("hi"))

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
-- THE MAP'S BUILDINGS, for the one caller that asks about a building it has no
-- machine in: the telephone directory, which has to know whether a named zone is
-- a tenancy INSIDE something (CeroSecNet.directory). A list of
-- { x, y, w, h } and getBuildingAt answers the first whose box holds the tile,
-- which is the walk zombie.iso.IsoMetaGrid.getBuildingAt(int, int) does (javap:
-- it walks `buildings` and compares x, y, getW(), getH()). x2 is EXCLUSIVE, the
-- way net.buildingAt below says it is.
_G.__buildings = {}
local function fakeBuildingDef(b)
	local def = {
		getX = function() return b.x end,
		getY = function() return b.y end,
		getX2 = function() return b.x + b.w end,
		getY2 = function() return b.y + b.h end,
	}
	-- And its rooms, for the one caller that has to measure a building it has no
	-- machine in: the phone book's tenant sweep. An entry with no `rooms` is a
	-- building nothing can be measured about, which is every zone bench above.
	if b.rooms ~= nil then
		local defs = {}
		for i = 1, #b.rooms do
			local room = b.rooms[i]
			local level = room.level or 0
			defs[i] = {
				getName = function() return room.name end,
				getX = function() return room.x end,
				getY = function() return room.y end,
				getX2 = function() return room.x + room.w end,
				getY2 = function() return room.y + room.h end,
				getZ = function() return level end,
				getArea = function() return room.area or room.w * room.h end,
			}
		end
		def.getRooms = function() return javaList(defs) end
		-- One ArrayList.size() on the real class, and what the tenancy cache is
		-- invalidated against: a building whose rooms grew (a basement spawned in
		-- play) answers a different number and its entry is thrown away.
		def.getRoomsNumber = function() return #defs end
	end
	return def
end

-- java.util.ArrayList, for the one engine call that takes an out parameter
-- (IsoMetaGrid.getBuildingsIntersecting). The game's own Lua makes one with
-- ArrayList.new() -- media/lua/server/Foraging/forageServer.lua:367 -- and this is
-- the same thing with the three methods that are used on it.
_G.ArrayList = { new = function()
	local items = {}
	return {
		add = function(_, item) items[#items + 1] = item return true end,
		size = function() return #items end,
		get = function(_, i) return items[i + 1] end,
	}
end }
-- Kept in a local as well as in the global, because one section below sets
-- _G.getWorld to NIL on purpose -- "a machine whose chunk is away" -- and every
-- section after it would otherwise be running on a map with no zones on it
-- without saying so. A section that wants the map back says `_G.getWorld =
-- zonedWorld` and means it.
local zonedWorld
_G.getWorld = function()
	return { getMetaGrid = function()
		return {
			getZonesAt = function(_, x, y, _z)
				local hits = {}
				for i = 1, #_G.__zones do
					local z = _G.__zones[i]
					if x >= z.x and x < z.x + z.w and y >= z.y and y < z.y + z.h then
						hits[#hits + 1] = fakeZone(z)
					end
				end
				return javaList(hits)
			end,
			-- getZonesIntersecting(x, y, z, w, h): every zone whose rectangle overlaps
			-- the one asked for. Zone.intersects(x,y,z,w,h) in the jar is exactly this
			-- test on the four edges (javap, and z == Integer.MAX_VALUE is its
			-- any-level case; nothing here has a zone off the ground floor).
			getZonesIntersecting = function(_, x, y, _z, w, h)
				local hits = {}
				for i = 1, #_G.__zones do
					local zone = _G.__zones[i]
					if x + w > zone.x and x < zone.x + zone.w
							and y + h > zone.y and y < zone.y + zone.h then
						hits[#hits + 1] = fakeZone(zone)
					end
				end
				return javaList(hits)
			end,
			getBuildingAt = function(_, x, y)
				for i = 1, #_G.__buildings do
					local b = _G.__buildings[i]
					if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
						return fakeBuildingDef(b)
					end
				end
				return nil
			end,
			-- getBuildingsIntersecting(x, y, w, h, out): every building whose box
			-- overlaps the rectangle, APPENDED to a list the caller hands in. An out
			-- parameter and no return value, which is the signature javap gives it,
			-- and the reason the fake fills the list instead of building one.
			--
			-- A building whose entry carries `rooms` hands them over the way
			-- buildingAt's do, so the book's tenant sweep has geometry to measure.
			getBuildingsIntersecting = function(_, x, y, w, h, out)
				for i = 1, #_G.__buildings do
					local b = _G.__buildings[i]
					if x + w > b.x and x < b.x + b.w
							and y + h > b.y and y < b.y + b.h then
						out:add(fakeBuildingDef(b))
					end
				end
			end,
		}
	end }
end

zonedWorld = _G.getWorld

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
	-- `names` is what the building's rooms are CALLED, which is a different fact
	-- from how many there are: the world content asks a building for its rooms
	-- (CeroSecNet.premisesRooms -> BuildingDef.getRooms -> RoomDef.getName) because
	-- the profile of a premises has to be the same answer from every square of it,
	-- and a def that would not list them is its own case (nil below).
	local function buildingAt(bx, by, w, h, rooms, names)
		w, h, rooms = w or 10, h or 10, rooms or 3
		local def = {
			getX = function() return bx end,
			getY = function() return by end,
			getX2 = function() return bx + w end,
			getY2 = function() return by + h end,
			getArea = function() return w * h end,
			getRoomsNumber = function() return rooms end,
		}
		-- An entry of `names` is either a bare string -- a room with a name and no
		-- outline, which is every bench written before a room could be a premises --
		-- or a table { name, x, y, w, h, level }, which is a room the tenancy rule can
		-- measure. A bare string is the case a def that will not give geometry is, and
		-- getArea answers nil for it on purpose: CeroSecContent.isTenancyName refuses a
		-- room whose area it was not told, so an old bench's building holds no
		-- tenancies and is one premises exactly as it was.
		if names ~= nil then
			local defs = {}
			for i = 1, #names do
				local entry = names[i]
				if type(entry) == "string" then
					defs[i] = { getName = function() return entry end }
				else
					local level = entry.level or 0
					defs[i] = {
						getName = function() return entry.name end,
						getX = function() return entry.x end,
						getY = function() return entry.y end,
						getX2 = function() return entry.x + entry.w end,
						getY2 = function() return entry.y + entry.h end,
						getZ = function() return level end,
						-- The SUM of the room's rectangles, which is what
						-- RoomDef.getArea answers (javap: `getfield area`, filled by
						-- CalculateBounds). A bench room is one rectangle, so it is the
						-- box -- and `area` overrides it, for the one-tile pump island
						-- and for a room drawn as an L.
						getArea = function() return entry.area or entry.w * entry.h end,
					}
				end
			end
			def.getRooms = function() return javaList(defs) end
		end
		return { getDef = function() return def end }
	end

	-- `room` is the name of the room the MACHINE stands in, which is a different
	-- question from what the building's rooms are called: the profile is the
	-- premises' and must be one answer from every square of it, and whether a
	-- computer in a shop that sells computers is stock is a fact about its own
	-- corner of the floor (CeroSecContent.isFloorRoom). nil is a machine in no named
	-- room, which is every other bench in this file and is the engine's own answer
	-- for a square whose room has no name.
	-- `room` is a bare NAME as it always was, or a table { name, x, y, w, h, level }
	-- for a bench that needs the square's own RoomDef to have an outline -- which the
	-- tenancy rule does, because which shop a back room belongs to is decided by the
	-- wall it shares (CeroSecNet.tenantOfRoom). A bare name answers getRoom and no
	-- getRoomDef, which is what a square in a building this rule cannot measure is.
	local function machine(x, y, z, building, room)
		local roomName = type(room) == "table" and room.name or room
		-- The square's own RoomDef, or nil for a square in no room the rule can
		-- measure. A local ahead of the table, because the IsoRoom the square also
		-- hands out reads the def through the very same function and a reference to
		-- `square` inside its own constructor is not `square` yet.
		local function roomDefOf()
			if type(room) ~= "table" then return nil end
			local level = room.level or 0
			return {
				getName = function() return room.name end,
				getX = function() return room.x end,
				getY = function() return room.y end,
				getX2 = function() return room.x + room.w end,
				getY2 = function() return room.y + room.h end,
				getZ = function() return level end,
				getArea = function() return room.area or room.w * room.h end,
			}
		end
		local object = SCeroSecObject:new(system, { x = x, y = y, z = z })
		local square = {
			getX = function() return x end,
			getY = function() return y end,
			getZ = function() return z end,
			getRoom = function()
				if roomName == nil then return nil end
				-- An IsoRoom has getRoomDef() as well as getName(), and the debug
				-- window reads the def through it the way the engine lets it
				-- (zombie.iso.areas.IsoRoom.getRoomDef() -> zombie.iso.RoomDef).
				return { getName = function() return roomName end,
					getRoomDef = roomDefOf }
			end,
			-- The def, which is the door CeroSecNet.roomDefAt goes through:
			-- IsoGridSquare.getRoomDef is getRoom() and then IsoRoom.getRoomDef(),
			-- null without a room.
			getRoomDef = roomDefOf,
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

	-- Explicit on every call, because the two changes that met here wanted different
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
	-- The player himself, for the benches that drive a command straight into
	-- OnClientCommand instead of through a terminal window.
	net.player = player

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

-- A session that came down the wire is named by where it came FROM, and never by
-- the line it was on: login.c prints the host INSTEAD of the terminal when the
-- record carries one, which is an if/else and not two lines.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.login("admin")
	local from = net.host(net.here)

	net.enter("rlogin gate")
	net.tick(2)
	net.enter("admin")
	net.enter("")
	net.tick(2)
	check("the far machine let him in", net.glass("admin@" .. net.host(net.gate)))
	check("and says nothing about a last login, because there was none",
		not net.glass("Last login:"))

	net.enter("exit")
	net.tick(3)
	net.forget()
	net.enter("rlogin gate")
	net.tick(2)
	net.enter("admin")
	net.enter("")
	net.tick(2)
	check("the second call names the first", net.glass("Last login:"))
	check("by the machine it came from", net.glass("from " .. from))
	check("and not by the pty it was on", not net.glass("on ttyp0"))
	-- The record it read is the one `last` reads: the far machine's wtmp.
	local wtmp = net.text(net.gate, CeroSecOS.WTMP_PATH)
	check("and that is what the far machine wrote down",
		wtmp ~= nil and string.find(wtmp, "in admin ttyp0 " .. from, 1, true) ~= nil)
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

-- LAN mail: the message goes THROUGH the rsh, into the far machine's spool
--
-- `cat note | rsh gate mail -s <subject> bob` is the line a survivor writes to
-- leave somebody a note on another machine, and it is the whole of the input half
-- of an rsh: the near machine drains the pipe before it dials, and the far
-- command reads what came over. Asserted on the far machine's MAILBOX, because
-- what a reader over there will see is the file and not what the sender was told.
do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.put(net.gate, "/etc/hosts.equiv", net.host(net.here), 644, "root")
	local far = net.gate:osState()
	CeroSecOS.addUser(far, "bob", "/home/bob", false, 1, 100)
	net.login("admin")
	net.put(net.here, "/home/admin/note", "the lights are off", 644, "admin")

	net.forget()
	net.enter("cat note | rsh gate mail -s Lights bob")
	net.tick(10)
	local box = net.text(net.gate, "/var/mail/bob")
	check("the message landed in the far machine's spool", box ~= nil)
	check("with the body that went down the near machine's pipe",
		box ~= nil and string.find(box, "the lights are off", 1, true) ~= nil)
	check("the subject crossed with it",
		box ~= nil and string.find(box, "Subject: Lights", 1, true) ~= nil)
	-- From: carries the FAR machine's name, because the far mail is what wrote it:
	-- the message was posted on gate and not carried there.
	check("and From: names the machine it was posted on",
		box ~= nil and string.find(box, "admin@" .. net.host(net.gate), 1, true) ~= nil)
	check("nothing of it was delivered on the near machine",
		net.text(net.here, "/var/mail/bob") == nil)
	eq("and no line was left open", CeroSecOS.ptyCount(net.gate.ptys), 0)

	-- The same line with nothing piped in. An rsh hands the far command an input
	-- that is already at end of file -- this machine cannot pass a terminal
	-- through one -- so mail posts the empty message and says so.
	net.forget()
	net.enter("rsh gate mail bob")
	net.tick(10)
	check("an rsh with no input sends the null-body message",
		net.glass(CeroSecOS.MAIL_NULL_BODY))
	local second = net.text(net.gate, "/var/mail/bob")
	check("and the second message is in the box too",
		second ~= nil and #second > #box)
	check("with no body under its headers",
		second ~= nil and string.find(second, "To: bob", 1, true) ~= nil)
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
			-- busyAt is not session state: it is WHEN this session last typed
			-- something, which a typed line is supposed to move (it is what `w`
			-- prints in its IDLE column), and it is dropped on the next load.
			if key ~= "lines" and key ~= "status" and key ~= "busyAt" then
				out[key] = tostring(value)
			end
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

--
-- THE TELEPHONE DIRECTORY (the phone book work)
--
-- Base.Phonebook is the yellow pages of the region it was found in, and the whole
-- of what this bench is about is that the BOOK and the LINE cannot disagree: a
-- computer put in a shop must answer on the number the book printed for that shop,
-- and the book must hold the shops of ONE exchange and nothing else.
--
-- The fake map grows two things for it: getZonesIntersecting, which is how a whole
-- region is swept, and getBuildingAt, which is how a named zone is told from a
-- named REGION -- the spawner tags a suburb "StreetPoor" and a farm "Farm" the way
-- it tags a shop "CoffeeShop", and neither of the first two is a business with a
-- telephone.
--
do
	local net = newNet()
	local R = CeroSecOS.PHONE_REGION

	-- A mall in region 0,0 with three shops in it, two of them one chain; a house
	-- with nothing named on it; a suburb-sized zone that is nobody's tenancy; and a
	-- zone exactly the mall's own size, which is the mall under another name.
	local mall = net.buildingAt(200, 300, 60, 40, 30)
	local house = net.buildingAt(500, 500, 10, 10, 3)
	-- And a second mall a region away, whose shop must not turn up in this book.
	local farMall = net.buildingAt(R + 200, 300, 60, 40, 30)
	-- And a building that straddles the boundary between the two regions, with a
	-- shop in it whose CORNER is on this side of it.
	local border = net.buildingAt(R - 24, 600, 100, 60, 30)
	_G.__buildings = {
		{ x = 200, y = 300, w = 60, h = 40 },
		{ x = 500, y = 500, w = 10, h = 10 },
		{ x = R + 200, y = 300, w = 60, h = 40 },
		{ x = R - 24, y = 600, w = 100, h = 60 },
	}
	_G.__zones = {
		{ name = "CoffeeShop", x = 210, y = 310, w = 17, h = 11 },
		{ name = "Bakery", x = 240, y = 310, w = 12, h = 10 },
		-- The same chain's second shop: one name, its own outline, its own number.
		{ name = "CoffeeShop", x = 230, y = 320, w = 17, h = 11 },
		-- A suburb. Its middle (300,300) is on no building at all, so no footprint
		-- can be bigger than it and it is not a tenancy.
		{ name = "StreetPoor", x = 100, y = 100, w = 400, h = 400 },
		-- The mall by another name: exactly its footprint, which loses on the same
		-- strictly-smaller test premisesOf runs.
		{ name = "Mall", x = 200, y = 300, w = 60, h = 40 },
		-- A zone of the wrong type, and one nobody named.
		{ name = "Nav", type = "Nav", x = 205, y = 305, w = 6, h = 6 },
		{ name = "", x = 206, y = 306, w = 6, h = 6 },
		-- Another region's shop, on another exchange.
		{ name = "Pharmacist", x = R + 210, y = 310, w = 17, h = 11 },
		-- A shop that reaches OVER the boundary. It is listed once, in the book of
		-- the region its corner is in -- which is the region its number belongs to,
		-- because the corner is what the exchange is derived from. A sweep of the
		-- next region finds it intersecting and must not print it.
		{ name = "BorderShop", x = R - 10, y = 610, w = 20, h = 10 },
	}

	-- Ask the server the way the client asks it: one command, no square, and the
	-- answer goes to the player who asked.
	local function ask(rx, ry)
		local got = nil
		net.system.reply = function(_, who, cmd, args)
			if cmd == "listings" then got = args; got.who = who end
		end
		net.system:OnClientCommand("phonebook", net.player,
			{ rx = rx, ry = ry, token = "look" })
		return got
	end

	local book = ask(0, 0)
	check("the server answers a look-up", book ~= nil)
	eq("to the survivor who asked and nobody else", book.who, net.player)
	eq("carrying the token back", book.token, "look")
	eq("for the region asked for", book.rx .. "," .. book.ry, "0,0")
	eq("under the exchange of that region", book.exchange,
		CeroSecOS.phoneExchange(0, 0))
	check("and nothing was cut", book.capped == false)

	local names = {}
	local byNumber = {}
	for i = 1, #book.entries do
		names[#names + 1] = book.entries[i].name
		byNumber[book.entries[i].number] = book.entries[i].name
	end
	table.sort(names)
	eq("four business listings and no more", #book.entries, 4)
	eq("the shops of the mall, camel case taken out",
		table.concat(names, "|"), "Bakery|Border Shop|Coffee Shop|Coffee Shop")

	-- A CHAIN is two listings with one name and two numbers, each on its own line.
	local chain = {}
	for i = 1, #book.entries do
		if book.entries[i].name == "Coffee Shop" then chain[#chain + 1] = book.entries[i].number end
	end
	eq("the chain is listed twice", #chain, 2)
	check("on two different numbers", chain[1] ~= chain[2])

	-- WHAT IS NOT IN IT. The suburb, the mall under its own name, the wrong type,
	-- the unnamed zone -- and the HOUSE, which has a line and no name to print.
	for _, absent in ipairs({ "Street Poor", "Mall", "Nav", "Pharmacist" }) do
		check(absent .. " is not a business listing",
			string.find("|" .. table.concat(names, "|") .. "|",
				"|" .. absent .. "|", 1, true) == nil)
	end

	-- THE BOOK AND THE LINE. A computer in the coffee shop the map drew at 210,310
	-- must read the book's own number off its BIOS. This is the assertion the whole
	-- change rests on: derive the number any other way and it goes red.
	local shop = net.machine(212, 312, 0, mall)
	shop:turnOn()
	local tel = telOf(shop)
	check("a machine in the coffee shop has a line", tel ~= nil)
	eq("and the book printed that very number for Coffee Shop", byNumber[tel], "Coffee Shop")
	eq("which is the premises the record names", CeroSecOS.premisesName(shop:osState()),
		"CoffeeShop")
	eq("on the book's own exchange", tonumber(string.sub(tel, 1, 3)), book.exchange)

	-- A RESIDENCE is not listed, and it is not listed because it has no name and
	-- not because it has no line: the house answers on one.
	local home = net.machine(505, 505, 0, house)
	home:turnOn()
	local homeTel = telOf(home)
	check("the house has a line of its own", homeTel ~= nil)
	eq("and no listing anywhere in the book", byNumber[homeTel], nil)

	-- ANOTHER REGION IS ANOTHER BOOK. The pharmacy is in region 1,0 and the two
	-- books share nothing -- not a listing and not an exchange.
	local far = ask(1, 0)
	eq("the next region's book has its own listing and only its own", #far.entries, 1)
	eq("which is the pharmacy and not the shop over the line",
		far.entries[1].name, "Pharmacist")
	check("on another exchange", far.exchange ~= book.exchange)
	local pharmacy = net.machine(R + 212, 312, 0, farMall)
	pharmacy:turnOn()
	eq("and the machine in it answers on the number that book printed",
		far.entries[1].number, telOf(pharmacy))

	-- And the machine in the shop over the line is on the number THIS book printed,
	-- which is the corner rule read off the BIOS.
	local straddler = net.machine(R - 5, 615, 0, border)
	straddler:turnOn()
	eq("the shop over the line answers on the number its own book printed",
		byNumber[telOf(straddler)], "Border Shop")

	-- A region with nothing in it is an empty book and not a broken one.
	local empty = ask(7, 7)
	eq("a region with no premises in it lists nothing", #empty.entries, 0)
	check("and says so without being cut", empty.capped == false)

	-- THE CAP. A region with more premises than a book holds is cut, and the answer
	-- SAYS it was cut rather than looking like a smaller county.
	local many = {}
	-- Laid out in rows INSIDE the region, because a zone whose corner falls past the
	-- region's far edge is in the next region's book by the corner rule above -- and
	-- a row of 405 zones three tiles apart would have run out of region long before
	-- it ran out of shops.
	_G.__buildings = { { x = 2 * R, y = 0, w = R, h = R } }
	for i = 1, CeroSecPhonebook.MAX_ENTRIES + 5 do
		many[i] = { name = "Shop" .. i,
			x = 2 * R + math.fmod(i, 30) * 3, y = math.floor(i / 30) * 3,
			w = 2, h = 2 }
	end
	_G.__zones = many
	local full = ask(2, 0)
	eq("the book holds its cap and not one more", #full.entries,
		CeroSecPhonebook.MAX_ENTRIES)
	check("and the answer says it was cut", full.capped == true)
	-- Which is what the last line of the last leaf prints.
	local volume = CeroSecPhonebook.volume(full.exchange, full.entries, full.capped)
	local last = volume.chapters[1].pages[#volume.chapters[1].pages]
	check("the printed book says so on its last line",
		string.find(last, "This directory is full", 1, true) ~= nil)

	_G.__zones = {}
	_G.__buildings = {}
end

--
-- A MALL IS NOT ONE PREMISES (premises v2)
--
-- The report, in the words it came in: they all share the same no matter what the
-- store is, because it's all one big building; the music store computer and the
-- dentist one have no specifics. They did, because a premises was a named zone or
-- else a whole BuildingDef and the shipped malls have no zones -- so eleven shops
-- were one profile, one staff, one telephone line and one length of coax.
--
-- The fake mall below is the shipped 12809,1294 in miniature, laid out so that every
-- branch of the rule has a square in it:
--
--   200,300 .. 260,350    the building, 60 by 50
--   musicstore     200,300  20x15   a shop
--   clothesstore   220,300  20x15   another shop, wall to wall with it -- two names
--                                   are two tenancies however long the wall is
--   dentist        200,325  20x10   a third, and a different trade
--   clothesstorage 200,335  10x8    touching the dentist and no other shop
--   breakroom      210,315  25x5    touching BOTH shops: 10 tiles of the music
--                                   store's wall and 15 of the clothes shop's, so
--                                   which one it belongs to is a question the
--                                   LENGTH decides and nothing else
--   hall           240,300   8x50   touching a shop, and nobody's all the same
--
-- What is asserted is the STATE on the machines and the papers -- the address, the
-- number, the hostname, the root password -- and not that premisesOfSquare was
-- called: the profile, the staff, the coax and the line each come through their own
-- caller, and a bench on the rule alone would leave any of those four wired to the
-- building without going red.
--
do
	local net = newNet()
	_G.__zones = {}
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = true } }

	local ROOMS = {
		musicstore = { name = "musicstore", x = 200, y = 300, w = 20, h = 15 },
		clothes = { name = "clothesstore", x = 220, y = 300, w = 20, h = 15 },
		dentist = { name = "dentist", x = 200, y = 325, w = 20, h = 10 },
		storage = { name = "clothesstorage", x = 200, y = 335, w = 10, h = 8 },
		breakroom = { name = "breakroom", x = 210, y = 315, w = 25, h = 5 },
		hall = { name = "hall", x = 240, y = 300, w = 8, h = 50 },
	}
	local roomList = { ROOMS.musicstore, ROOMS.clothes, ROOMS.dentist,
		ROOMS.storage, ROOMS.breakroom, ROOMS.hall }
	-- The shape CeroSecNet.buildingRooms hands out -- corners and not sizes, x2 and
	-- y2 exclusive, with the floor and the summed area -- for the two functions a
	-- bench calls directly with a room instead of through a def.
	local function asRoom(r)
		return { name = r.name, x = r.x, y = r.y, x2 = r.x + r.w, y2 = r.y + r.h,
			level = r.level or 0, area = r.area or r.w * r.h }
	end
	local mall = net.buildingAt(200, 300, 60, 50, 6, roomList)

	-- FIRST, THE RULE ITSELF, as a partition of the rooms. Three shops and not five
	-- and not one: the count is asserted because an assertion that "the dentist is a
	-- tenancy" would be green on a rule that made every room one.
	local groups = CeroSecNet.tenancies(CeroSecNet.buildingRooms(mall:getDef()))
	eq("the mall holds three tenancies (" .. #groups .. ")", #groups, 3)
	local byName = {}
	for g = 1, #groups do byName[groups[g][1].name] = groups[g] end
	check("the music store is one", byName.musicstore ~= nil)
	check("the dentist is one", byName.dentist ~= nil)
	check("the clothes shop is one", byName.clothesstore ~= nil)
	eq("the stock room is not a shop", byName.clothesstorage, nil)
	eq("nor is the hall", byName.hall, nil)

	-- A ROOM THAT IS NOBODY'S SHOP goes to the one whose back room it is, by the
	-- longest wall -- and the hall, which touches all three, goes to nobody.
	local mine = CeroSecNet.tenantOfRoom(groups, asRoom(ROOMS.storage))
	check("the stock room belongs to the shop it shares a wall with", mine ~= nil)
	eq("which is the dentist and not the shop whose name it wears",
		mine[1].name, "dentist")
	-- AND WHERE TWO SHOPS BOTH HAVE A CLAIM, the LENGTH of the wall decides and
	-- nothing else: the break room shows 10 tiles of wall to the music store and 15
	-- to the clothes shop. A rule that took the first shop it found touching, or the
	-- shortest wall, gets the music store here.
	local shared = CeroSecNet.tenantOfRoom(groups, asRoom(ROOMS.breakroom))
	check("a room touching two shops belongs to one of them", shared ~= nil)
	eq("the one it shares the longer wall with", shared[1].name, "clothesstore")
	eq("and the hall belongs to nobody",
		CeroSecNet.tenantOfRoom(groups, asRoom(ROOMS.hall)), nil)

	-- THREE PREMISES, THREE OF EVERYTHING. One machine in each shop, one in the
	-- dentist's stock room and one in the hall.
	local music = net.machine(205, 305, 0, mall, ROOMS.musicstore)
	local dentist = net.machine(205, 330, 0, mall, ROOMS.dentist)
	local clothes = net.machine(230, 305, 0, mall, ROOMS.clothes)
	local back = net.machine(203, 338, 0, mall, ROOMS.storage)
	local hall = net.machine(243, 310, 0, mall, ROOMS.hall)
	for _, one in ipairs({ music, dentist, clothes, back, hall }) do one:turnOn() end

	local function keyOf(object)
		local rec = CeroSecOS.netRecord(object:osState())
		if rec == nil then return nil end
		return rec.b1 .. "." .. rec.b2
	end

	-- THREE SEGMENTS. The two bytes are the segment and the line both, so three
	-- different pairs is three of each -- which is the one number everything else in
	-- this section follows from.
	local segments = {}
	for _, one in ipairs({ music, dentist, clothes }) do segments[keyOf(one)] = true end
	local count = 0
	for _ in pairs(segments) do count = count + 1 end
	eq("the three shops are on three segments", count, 3)
	eq("and the stock room is on the dentist's", keyOf(back), keyOf(dentist))
	check("while the hall is on the building's",
		keyOf(hall) ~= keyOf(dentist) and keyOf(hall) ~= keyOf(music))
	eq("which is the building key it always was", keyOf(hall),
		(function() local b1, b2 = CeroSecOS.buildingKey(200, 300) return b1 .. "." .. b2 end)())

	-- THREE LINES. The complaint's other half: only the lowest-numbered computer of
	-- the whole mall could ever be rung, the rest being unreachable by telephone.
	local tels = {}
	for _, one in ipairs({ music, dentist, clothes }) do tels[telOf(one)] = true end
	count = 0
	for _ in pairs(tels) do count = count + 1 end
	eq("and on three telephone lines", count, 3)
	eq("the stock room answers on the dentist's line", telOf(back), telOf(dentist))
	-- One mall, one central office: every shop of it is wired back to the same
	-- switch, which is the exchange of the BUILDING's corner.
	local ex = CeroSecOS.phoneExchange(200, 300)
	for _, one in ipairs({ music, dentist, clothes, hall }) do
		eq("every shop of the mall is on one exchange",
			tonumber(string.sub(telOf(one), 1, 3)), ex)
	end

	-- THE BIOS SAYS WHICH SHOP IT IS. A survivor in a mall with three lines in it
	-- needs to know which one he is sitting at, and the record carries the words.
	eq("the music store's firmware names the music store",
		CeroSecOS.premisesName(music:osState()), "Music Store")
	eq("the dentist's names the dentist",
		CeroSecOS.premisesName(dentist:osState()), "Dentist")
	eq("and the kind it was worked out from is written down",
		CeroSecOS.netRecord(music:osState()).pk, CeroSecOS.PREMISES_ROOM)
	eq("the machine in the hall is on the building and says nothing",
		CeroSecOS.premisesName(hall:osState()), nil)
	eq("and carries no kind either", CeroSecOS.netRecord(hall:osState()).pk, nil)

	-- THE PROFILES, which is the report in six words. The dentist gets the clinic's
	-- disk and the shops get the till's, and all three root passwords differ --
	-- the last being what "no specifics" meant.
	eq("the dentist's machine is the clinic's",
		string.match(dentist:osState().hostname, "^[a-z]+"),
		CeroSecContent.PROFILES.clinic.host)
	eq("the music store's is the shop's",
		string.match(music:osState().hostname, "^[a-z]+"),
		CeroSecContent.PROFILES.store.host)
	eq("and the clothes shop's is too",
		string.match(clothes:osState().hostname, "^[a-z]+"),
		CeroSecContent.PROFILES.store.host)
	-- AND THE PASSWORD ON THE PAPER IN THE DRAWER, which is the report's "no
	-- specifics" and is the assertion this whole section is really about. It is asked
	-- the way CeroSecNotes asks it -- derive the premises from a SQUARE, then the
	-- profile, then the account's password -- and checked against the machine, never
	-- by comparing two stored hashes: those are salted per machine, so two of them
	-- differ even when the password is the same and an inequality would be green on a
	-- mall that had one password for all of it.
	local secret = net.system:secret()
	-- What CeroSecNotes.deskNote writes on the paper: root's password, derived from
	-- the save's secret and the PREMISES the drawer's own square is in.
	local function paperFoundIn(square)
		local b1, b2 = CeroSecNet.premisesOfSquare(square)
		if b1 == nil then return nil end
		return CeroSecContent.password(secret, CeroSecContent.rootKey(b1, b2))
	end
	local function opens(object, password)
		if password == nil then return false end
		local user = CeroSecOS.getUser(object:osState(), "root")
		if user == nil then return false end
		return CeroSecOS.checkPassword(user, password) and true or false
	end
	local musicPaper = paperFoundIn(music:getSquare())
	local clothesPaper = paperFoundIn(clothes:getSquare())
	local dentPaper = paperFoundIn(dentist:getSquare())
	local backPaper = paperFoundIn(back:getSquare())
	local hallPaper = paperFoundIn(hall:getSquare())
	check("a paper found in the music store opens the music store's machine",
		opens(music, musicPaper))
	check("and does NOT open the clothes shop next door",
		not opens(clothes, musicPaper))
	check("the clothes shop's own paper opens the clothes shop",
		opens(clothes, clothesPaper))
	check("and not the music store", not opens(music, clothesPaper))
	check("the dentist's paper opens his machine", opens(dentist, dentPaper))
	check("and not the music store's", not opens(music, dentPaper))
	-- The stock room is the dentist's, so the paper in ITS drawer is his: one
	-- premises, one note, every machine of it.
	eq("the paper in the dentist's stock room carries the dentist's own password",
		backPaper, dentPaper)
	check("which opens the machine standing in that stock room",
		opens(back, backPaper))
	-- And the machine in the HALL is the building's, so neither shop's paper opens
	-- it -- the old behaviour, for the one part of a mall that is nobody's.
	check("the paper in the hall opens the hall's machine", opens(hall, hallPaper))
	check("and the music store's paper does not", not opens(hall, musicPaper))

	-- THE WIRE IS THE SHOP'S. What ruptime prints is env.peers (the bench for the
	-- printing itself is the ruptime section above), and the shop next door must not
	-- be on it: `ping bakery` from the coffee shop is 100% packet loss.
	local peers = CeroSecNet.envFor(net.system, music, music:osState()).peers()
	eq("the music store's wire carries the music store and nothing else", #peers, 1)
	eq("which is its own machine",
		peers[1].addr, CeroSecOS.address(music:osState()))
	local backPeers = CeroSecNet.envFor(net.system, dentist, dentist:osState()).peers()
	eq("and the dentist's carries his surgery and his stock room", #backPeers, 2)
	-- Not reachable either, which is the other half of the same wire and the half a
	-- filtered list would not prove.
	eq("the shop next door is off the wire entirely",
		CeroSecNet.reachable(net.system, music, CeroSecOS.address(clothes:osState())), nil)

	-- A BUILDING WITH ONE SHOP IS THE BUILDING, and this is the regression the rule
	-- is shaped around: a gun shop with a back office and a stock room is ONE
	-- business, and splitting its stock room off would be a worse bug than the one
	-- being fixed. 240 buildings of the shipped county are this shape.
	local gun = net.buildingAt(700, 700, 20, 20, 3, {
		{ name = "gunstore", x = 700, y = 700, w = 14, h = 20 },
		{ name = "gunstorestorage", x = 714, y = 700, w = 6, h = 10 },
		{ name = "office", x = 714, y = 710, w = 6, h = 10 },
	})
	local floor = net.machine(705, 705, 0, gun,
		{ name = "gunstore", x = 700, y = 700, w = 14, h = 20 })
	local backOffice = net.machine(716, 715, 0, gun,
		{ name = "office", x = 714, y = 710, w = 6, h = 10 })
	floor:turnOn()
	backOffice:turnOn()
	eq("a shop with a back office holds one tenancy",
		#CeroSecNet.tenancies(CeroSecNet.buildingRooms(gun:getDef())), 1)
	eq("so its two machines are on one segment", keyOf(floor), keyOf(backOffice))
	eq("and one line", telOf(floor), telOf(backOffice))
	eq("which is the building's, exactly as it was", keyOf(floor),
		(function() local b1, b2 = CeroSecOS.buildingKey(700, 700) return b1 .. "." .. b2 end)())
	eq("and its record carries no kind", CeroSecOS.netRecord(floor:osState()).pk, nil)

	-- A HOUSE IS A HOUSE. No shopfront room in it at all, and a study does not make
	-- one: `office` is 3977 rooms in the county and a tenancy word there would have
	-- split a house in two.
	local house = net.buildingAt(800, 800, 12, 12, 4, {
		{ name = "livingroom", x = 800, y = 800, w = 8, h = 12 },
		{ name = "kitchen", x = 808, y = 800, w = 4, h = 6 },
		{ name = "office", x = 808, y = 806, w = 4, h = 6 },
	})
	local study = net.machine(809, 808, 0, house,
		{ name = "office", x = 808, y = 806, w = 4, h = 6 })
	study:turnOn()
	eq("a house holds no tenancies",
		#CeroSecNet.tenancies(CeroSecNet.buildingRooms(house:getDef())), 0)
	eq("and the desk in the study is on the building",
		keyOf(study),
		(function() local b1, b2 = CeroSecOS.buildingKey(800, 800) return b1 .. "." .. b2 end)())

	-- THE ANSWER IS CACHED PER BUILDING, and it has to be: measured on the biggest
	-- mall the county has -- 498 rooms, 70 of them shopfronts -- the rule cost 2.5 ms
	-- a call, and Events.OnFillContainer asks it once for every container as loot is
	-- generated. A mall's chunk load would have spent most of a second in it.
	--
	-- What is asserted is that the cache ANSWERS THE SAME THING and that it is thrown
	-- away when the building's rooms grow, which is the one thing that can happen to a
	-- building during play (a basement). Not the milliseconds: a timing here would be
	-- a ceiling somebody raises one day, and the state is the thing that can be wrong.
	do
		CeroSecNet.forgetTenancies()
		local first = CeroSecNet.tenanciesOf(mall:getDef())
		local again = CeroSecNet.tenanciesOf(mall:getDef())
		eq("asked twice the building gives the same tenancies", #again, #first)
		check("and it is the very same table", again == first)

		-- FORGETTING IS FORGETTING, asked before anything else touches this entry: a
		-- clear that did nothing would hand the same table back, and the assertion has
		-- to be able to see that.
		CeroSecNet.forgetTenancies()
		local fresh = CeroSecNet.tenanciesOf(mall:getDef())
		eq("after a clear the answer is the same", #fresh, #first)
		check("and it was computed again", fresh ~= first)

		-- ONE ENTRY PER BUILDING, and the two buildings below have the SAME NUMBER OF
		-- ROOMS on purpose. The room count is what a stale entry is thrown away on, so
		-- a cache keyed on anything but the building would be *caught* by that count on
		-- any other pair and would quietly hand one building's shops to the other on
		-- this one -- which is the pair a county of look-alike houses really is.
		local sixShops = { ROOMS.musicstore, ROOMS.clothes, ROOMS.dentist,
			ROOMS.storage, ROOMS.breakroom, ROOMS.hall }
		local twin = net.buildingAt(300, 900, 60, 50, #sixShops, {
			{ name = "livingroom", x = 300, y = 900, w = 20, h = 15 },
			{ name = "kitchen", x = 320, y = 900, w = 20, h = 15 },
			{ name = "bedroom", x = 300, y = 925, w = 20, h = 10 },
			{ name = "bathroom", x = 300, y = 935, w = 10, h = 8 },
			{ name = "garage", x = 310, y = 915, w = 25, h = 5 },
			{ name = "hall", x = 340, y = 900, w = 8, h = 50 },
		})
		eq("the twin really has as many rooms as the mall",
			twin:getDef():getRoomsNumber(), mall:getDef():getRoomsNumber())
		eq("and it is a house all the same",
			#CeroSecNet.tenanciesOf(twin:getDef()), 0)
		eq("while the mall is still the mall",
			#CeroSecNet.tenanciesOf(mall:getDef()), #first)

		-- A BUILDING THAT GAINS A ROOM gives a new answer. Faked the way a basement
		-- arrives: the def's room list grows, so getRoomsNumber moves with it.
		local grown = { ROOMS.musicstore, ROOMS.clothes, ROOMS.dentist,
			ROOMS.storage, ROOMS.breakroom, ROOMS.hall,
			{ name = "liquorstore", x = 200, y = 341, w = 18, h = 8 } }
		local after = net.buildingAt(200, 300, 60, 50, #grown, grown)
		local grownGroups = CeroSecNet.tenanciesOf(after:getDef())
		eq("a building that gains a shop is asked again (" .. #grownGroups .. ")",
			#grownGroups, 4)
		check("which is not the answer it had", grownGroups ~= first)

		-- THE BOUND empties the cache rather than growing without end. Asserted on the
		-- SIZE and not only on the answers, because a cache that grew for ever would
		-- answer every question correctly to the end of the session -- there would be
		-- nothing to see except a table nobody measured.
		local before = CeroSecNet.tenancyCacheSize()
		check("the cache holds what has been asked about (" .. before .. ")",
			before > 0 and before <= CeroSecNet.TENANCY_CACHE_MAX)
		local peak = before
		for i = 1, CeroSecNet.TENANCY_CACHE_MAX + 2 do
			CeroSecNet.tenanciesOf(net.buildingAt(20000 + i * 40, 20000, 20, 20, 1,
				{ { name = "livingroom", x = 20000 + i * 40, y = 20000, w = 18, h = 18 } })
				:getDef())
			local now = CeroSecNet.tenancyCacheSize()
			if now > peak then peak = now end
		end
		check("and never more than its ceiling (" .. peak .. " of "
			.. CeroSecNet.TENANCY_CACHE_MAX .. ")",
			peak <= CeroSecNet.TENANCY_CACHE_MAX)
		check("having really been filled past it", peak > 1)
		eq("and a building asked after the cache filled is still right",
			#CeroSecNet.tenanciesOf(mall:getDef()), #first)
		CeroSecNet.forgetTenancies()
		eq("a clear leaves nothing behind", CeroSecNet.tenancyCacheSize(), 0)

		-- AND THE ROOM NAMES ARE ON THE SAME ENTRY, for the same caller and the same
		-- reason: what a premises is CALLED comes off the building's room names
		-- (CeroSecNet.premisesRooms), and Events.OnFillContainer asks it once per
		-- container as loot is generated. Counted on the def itself, because "it was
		-- not walked again" is a fact about the engine call and not about the answer.
		do
			local walks = 0
			local names = { "livingroom", "kitchen", "bedroom" }
			local rooms = #names
			local function countingDef()
				local def = net.buildingAt(700, 400, 20, 20, rooms, names):getDef()
				local real = def.getRooms
				def.getRooms = function(self)
					walks = walks + 1
					return real(self)
				end
				return def
			end
			CeroSecNet.forgetTenancies()
			local first = CeroSecNet.roomNamesOf(countingDef())
			eq("the building's rooms are named", #first, 3)
			eq("and getRooms was walked once", walks, 1)
			local again = CeroSecNet.roomNamesOf(countingDef())
			eq("asked again it walks nothing", walks, 1)
			check("and hands back the very same list", again == first)

			-- A basement arrives: the count moves and the entry is rebuilt, names and
			-- all. The one thing that really happens to a building during play, and the
			-- assertion that keeps the cache from outliving the fact it was built from.
			rooms = 4
			names = { "livingroom", "kitchen", "bedroom", "basement" }
			local grown = CeroSecNet.roomNamesOf(countingDef())
			eq("a building that gained a room is walked again", walks, 2)
			eq("and its names are the new ones", #grown, 4)
			CeroSecNet.forgetTenancies()
		end
	end

	-- AND THE DEBUG WINDOW SAYS WHICH SHOP, which is the tool the in-game walk uses
	-- when one of the steps above does not answer what it should
	-- (docs/PARCOURS-TEST.md step 215p). Benched because nothing else in this suite
	-- calls CeroSecDebug.premises at all: every line of it is engine calls, and an
	-- unreached one is a nil call in a window nobody can read afterwards.
	do
		local function block(object)
			return table.concat(CeroSecDebug.premises(object), "\n")
		end
		local said = block(dentist)
		check("the debug block counts the building's tenancies",
			string.find(said, "tenancies: 3", 1, true) ~= nil)
		check("and names them", string.find(said, "dentist", 1, true) ~= nil)
		check("and says which premises this square is in",
			string.find(said, "premises: room  Dentist", 1, true) ~= nil)
		check("the machine in the hall is on the building",
			string.find(block(hall), "premises: building", 1, true) ~= nil)
		-- And a machine in no building at all does not reach any of it.
		local outdoors = net.machine(9000, 9000, 0, nil)
		check("a machine outdoors says so and stops there",
			string.find(block(outdoors), "building: outdoors", 1, true) ~= nil)
		check("with no tenancy line at all",
			string.find(block(outdoors), "tenancies:", 1, true) == nil)

		-- AND WHAT THE AUTOMATION DECIDED, which is the one line on that tab that is
		-- read out of the save and not off the map. It is what the in-game walk has to
		-- look at for a mall: whether this premises is finished being wired, and how
		-- many of its rooms have been walked while it is not
		-- (docs/PARCOURS-TEST.md step 339n).
		check("a premises nothing has decided about says so",
			string.find(block(dentist), "automated: not asked yet", 1, true) ~= nil)
		local b1, b2 = CeroSecNet.premisesOfSquare(dentist:getSquare())
		local page = CeroSecAuto.page(net.system)
		page[CeroSecContent.premisesKey(b1, b2)] = { on = true,
			machine = { x = dentist.x, y = dentist.y, z = dentist.z },
			rooms = { ["0:1:2:musicstore"] = true, ["0:1:3:musicstore"] = true } }
		local walking = block(dentist)
		check("one still being walked says how far it has got",
			string.find(walking, "automated: yes  machine 205,330,0  wired no  rooms walked 2", 1, true) ~= nil)
		page[CeroSecContent.premisesKey(b1, b2)].rooms = nil
		page[CeroSecContent.premisesKey(b1, b2)].wired = true
		check("and a finished one says so with no count beside it",
			string.find(block(dentist), "wired yes", 1, true) ~= nil
				and string.find(block(dentist), "rooms walked", 1, true) == nil)
		net.system.auto = nil
	end

	-- A GAS STATION IS ONE PREMISES. Its `gasstore` rooms are the pump islands, one
	-- tile each and no two of them touching, and there are thirteen stations of this
	-- exact shape in the shipped county -- every one of them four premises with four
	-- telephone lines until a single tile stopped being a shop. Two of the four are
	-- the canopy over the pumps, on the floor above.
	local pumps = net.buildingAt(900, 900, 14, 14, 4, {
		{ name = "gasstore", x = 901, y = 901, w = 1, h = 1 },
		{ name = "gasstore", x = 911, y = 901, w = 1, h = 1 },
		{ name = "gasstore", x = 901, y = 901, w = 1, h = 1, level = 1 },
		{ name = "gasstore", x = 911, y = 901, w = 1, h = 1, level = 1 },
	})
	eq("a room of one tile is not a shop, so a gas station holds no tenancies",
		#CeroSecNet.tenancies(CeroSecNet.buildingRooms(pumps:getDef())), 0)
	local pump = net.machine(901, 901, 0, pumps,
		{ name = "gasstore", x = 901, y = 901, w = 1, h = 1 })
	local kiosk = net.machine(911, 901, 0, pumps,
		{ name = "gasstore", x = 911, y = 901, w = 1, h = 1 })
	pump:turnOn()
	kiosk:turnOn()
	eq("so its two machines are on one segment", keyOf(pump), keyOf(kiosk))
	eq("which is the building's", keyOf(pump),
		(function() local b1, b2 = CeroSecOS.buildingKey(900, 900) return b1 .. "." .. b2 end)())

	-- A SHOP WITH A MEZZANINE IS TWO TENANCIES, because the grouping is per floor:
	-- the shipped mall at 12809,1294 has `cafe` at 12858,1329 on levels 0 and 1. One
	-- dentist on two lines is the honest cost of that, and the thing that must NOT
	-- happen is the two floors landing on ONE key -- which is what a key that left the
	-- floor out would do, two rooms of one name starting on the same corner.
	local twoFloors = net.buildingAt(1000, 1000, 30, 30, 2, {
		{ name = "cafe", x = 1000, y = 1000, w = 12, h = 12 },
		{ name = "cafe", x = 1000, y = 1000, w = 12, h = 12, level = 1 },
	})
	eq("a shop on two floors is two tenancies",
		#CeroSecNet.tenancies(CeroSecNet.buildingRooms(twoFloors:getDef())), 2)
	local ground = net.machine(1005, 1005, 0, twoFloors,
		{ name = "cafe", x = 1000, y = 1000, w = 12, h = 12 })
	local upstairs = net.machine(1005, 1005, 1, twoFloors,
		{ name = "cafe", x = 1000, y = 1000, w = 12, h = 12, level = 1 })
	ground:turnOn()
	upstairs:turnOn()
	check("and the two floors are two segments, not one",
		keyOf(ground) ~= keyOf(upstairs))
	check("on two telephone lines", telOf(ground) ~= telOf(upstairs))
	eq("the upstairs key is the room key of level one", keyOf(upstairs),
		(function() local k1, k2 = CeroSecOS.roomKey(1000, 1000, 1000, 1000, 1)
			return k1 .. "." .. k2 end)())

	-- A ZONE STILL WINS. The map's own word for a tenancy beats the rooms wherever
	-- the map said one, which is what keeps every save of the shipped county where it
	-- was: put a named zone over the music store and the machine in it moves onto the
	-- zone's key.
	local before = keyOf(music)
	_G.__zones = { { name = "CoffeeShop", x = 200, y = 300, w = 17, h = 11 } }
	CeroSecNet.identify(net.system, music, music:osState())
	check("a named zone over the shop takes the premises over", keyOf(music) ~= before)
	eq("and it is the zone's key", keyOf(music),
		(function() local b1, b2 = CeroSecOS.premisesKey(200, 300, 17, 11)
			return b1 .. "." .. b2 end)())
	eq("with the zone's own name on the firmware",
		CeroSecOS.premisesName(music:osState()), "CoffeeShop")
	eq("and the zone's kind", CeroSecOS.netRecord(music:osState()).pk,
		CeroSecOS.PREMISES_ZONE)
	-- And taking the zone away again puts it back on the room's key, which is the
	-- same renumbering in the other direction and is what a map mod added and removed
	-- would do to a save.
	_G.__zones = {}
	check("taking the zone away renumbers it again",
		CeroSecNet.identify(net.system, music, music:osState()))
	eq("back onto the music store's own key", keyOf(music), before)

	-- A MACHINE SAVED UNDER v1 carries the BUILDING's two bytes, because that is what
	-- a mall was. It is renumbered the next time its square is answerable -- a new
	-- address and a new number -- and what is already written on the disk is
	-- untouched: the accounts, and therefore the paper somebody found in that mall.
	do
		local old = net.machine(206, 306, 0, mall, ROOMS.musicstore)
		old:turnOn()
		local state = old:osState()
		local b1, b2 = CeroSecOS.buildingKey(200, 300)
		-- Written the way a v1 save has it: the building's bytes, its exchange, and no
		-- premises name and no kind.
		CeroSecOS.setNetRecord(state, b1, b2, 9, CeroSecOS.phoneExchange(200, 300))
		local rootWas = CeroSecOS.getUser(state, "root").password
		local usersWere = select(2, CeroSecOS.readUsers(state))
		eq("a v1 machine in a mall is on the building's key", keyOf(old),
			b1 .. "." .. b2)
		check("and has no premises name", CeroSecOS.premisesName(state) == nil)

		check("loading it re-keys it", CeroSecNet.identify(net.system, old, state))
		eq("onto the music store's own segment", keyOf(old), keyOf(music) and
			(function() local k1, k2 = CeroSecOS.roomKey(200, 300, 200, 300, 0)
				return k1 .. "." .. k2 end)())
		eq("with the shop's name on the firmware now",
			CeroSecOS.premisesName(state), "Music Store")
		eq("and the shop's kind", CeroSecOS.netRecord(state).pk,
			CeroSecOS.PREMISES_ROOM)
		-- WHAT DID NOT CHANGE, which is the whole compatibility claim: the accounts
		-- were derived at prefill and are stored hashed, so the root note written for
		-- this machine still opens it.
		eq("root's password is the one it was prefilled with",
			CeroSecOS.getUser(state, "root").password, rootWas)
		eq("and the accounts are the accounts",
			table.concat(select(2, CeroSecOS.readUsers(state)), " "),
			table.concat(usersWere, " "))
		-- And a second load changes nothing more, which is what a renumbering that
		-- ran every power-on would break.
		local settled = keyOf(old)
		check("and a second load leaves it alone",
			not CeroSecNet.identify(net.system, old, state))
		eq("on the same segment", keyOf(old), settled)
	end

	-- THE BOOK LISTS THE SHOPS. Before this the malls were in no book at all, having
	-- no zones, so a survivor could not find the number of a shop he was not standing
	-- in -- and the shops are the only businesses in a mall.
	_G.__buildings = {
		{ x = 200, y = 300, w = 60, h = 50, rooms = roomList },
		{ x = 700, y = 700, w = 20, h = 20, rooms = {
			{ name = "gunstore", x = 700, y = 700, w = 14, h = 20 },
			{ name = "gunstorestorage", x = 714, y = 700, w = 6, h = 10 },
			{ name = "office", x = 714, y = 710, w = 6, h = 10 } } },
	}
	local listings, capped = CeroSecNet.directory(0, 0)
	local printed = {}
	local numbers = {}
	for i = 1, #listings do
		printed[#printed + 1] = listings[i].name
		numbers[listings[i].name] = listings[i].number
	end
	table.sort(printed)
	check("nothing was cut", capped == false)
	eq("the book lists the three shops of the mall and nothing else",
		table.concat(printed, "|"), "Clothes Store|Dentist|Music Store")
	-- AND THE BOOK AND THE LINE AGREE, which is the assertion the whole sweep is
	-- for: derive the number either side its own way and this goes red.
	eq("the dentist's listing is the number his machine answers on",
		numbers["Dentist"], telOf(dentist))
	eq("and the music store's is the music store's",
		numbers["Music Store"], telOf(music))
	check("the hall is not a business", numbers["Hall"] == nil)
	check("nor is the stock room", numbers["Clothes Storage"] == nil)
	check("and the gun shop, being one business in its building, is not listed",
		numbers["Gun Store"] == nil)

	_G.__zones = {}
	_G.__buildings = {}
	-- Put the world back the way the sections below it expect: a prefilled machine is
	-- this section's business and nobody else's.
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
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
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
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

-- The TNC's line, opened. Since SYSTEM_VERSION 17 there is no `call` command:
-- the box is a peripheral on a serial line and it is reached with cu, so every
-- bench that used to type one line types two -- the line, and the connect at the
-- box's own cmd: prompt. Both go in through the window's own keyboard, the second
-- through the PROMPT path, because cmd: is a question like any other.
local function tnc(net)
	say(net, "cu -l " .. CeroSecOS.TNC_DEV)
	net.tick(2)
end

-- Open the line and connect, which is what `call CALLSIGN` used to be.
local function connect(net, call, ticks)
	tnc(net)
	say(net, "C " .. call)
	net.tick(ticks or 3)
end

-- A line typed at a machine this bench has no window on, while that machine is at
-- a QUESTION rather than at its shell: the console's prompt, answered the way
-- Commands.input answers one. typeAt above is the same shape for the shell, and
-- for the same reason -- there is no window on those machines to press a key at.
local function answerAt(net, object, line, ticks)
	local console = object:consoleState()
	local state = object:osState()
	console.prompt = nil
	local job = CeroSecJobs.foreground(object, console)
	CeroSecOS.jobInput(state, job, line,
		net.system:execEnv(object, state, nil, nil))
	net.tick(ticks or 3)
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
	say(net, "echo W4ZZZ > /etc/callsign")
	net.tick(3)
	eq("root wrote a new callsign", callOf(net.here), "W4ZZZ")
	connect(net, callOf(net.far))
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
	typeAt(net, other, "cu -l " .. CeroSecOS.TNC_DEV)
	check("the line opens anyway: the box is there", ownSaid(other, CeroSecOS.TNC_BANNER))
	answerAt(net, other, "C " .. callOf(net.far))
	check("and the machine says so in its own name",
		ownSaid(other, CeroSecOS.TNC_NO_CALLSIGN))
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

	tnc(net)
	check("the box says what it is", net.glass(CeroSecOS.TNC_BANNER))
	say(net, "C " .. theirCall)
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
	connect(net, callOf(net.far), 2)
	say(net, "admin")
	say(net, "")
	net.tick(2)
	check("the link is up", net.glass("admin@" .. net.host(net.far)))
	net.forget()
	say(net, "~.")
	net.tick(3)
	check("~. hangs the link up", net.heard(CeroSecOS.TNC.disconnected))
	-- And cu with it: the program holding the line is over, which is what a tilde
	-- escape has always ended, so the shell comes back and not cmd:.
	check("and cu says its own last word", net.heard(CeroSecOS.CU_DISCONNECTED))
	eq("the line is given back", CeroSecOS.ptyCount(net.far.ptys), 0)
	check("and the glass is this machine's again",
		net.glass("admin@" .. net.host(net.here)))
	_G.__world = nil
end

-- The TNC's interrupt key, D, and K: the three ways out of a link and back, and
-- the one thing `call` could never do -- step out of a link without dropping it.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	connect(net, callOf(net.far), 2)
	say(net, "admin")
	say(net, "")
	net.tick(2)
	check("the link is up", net.glass("admin@" .. net.host(net.far)))

	-- Escape at an idle prompt over there is the TNC's interrupt key: back to
	-- cmd:, with the link still in the box's hand.
	net.forget()
	net.escape()
	net.tick(2)
	check("Escape puts the box back at its prompt", net.glass(CeroSecOS.TNC_PROMPT))
	check("and says nothing about a disconnect",
		not net.heard(CeroSecOS.TNC.disconnected))
	eq("the line over there is still taken", CeroSecOS.ptyCount(net.far.ptys), 1)
	check("and the window is not shut", not net.window.closing)

	-- K goes back in, and what is on the glass is the session that was waiting.
	say(net, "K")
	net.tick(3)
	check("K is converse again", net.glass("admin@" .. net.host(net.far)))
	eq("still one line", CeroSecOS.ptyCount(net.far.ptys), 1)

	-- And D drops it, from cmd:.
	net.escape()
	net.tick(2)
	net.forget()
	say(net, "D")
	net.tick(3)
	check("D says the box's own line", net.heard(CeroSecOS.TNC.disconnected))
	eq("and gives the line back", CeroSecOS.ptyCount(net.far.ptys), 0)
	-- And the near SCREEN is the box's dialog and not the session's copy of it.
	-- That is what the parked glass costs if it is got wrong: the session's console
	-- carries a copy of this screen taken when the link was MADE, so a teardown
	-- that painted it back over a parked screen would lose every line typed at
	-- cmd: since -- the `D` a survivor just typed among them -- and would say
	-- *** DISCONNECTED a second time under a prompt that is still up. Read off the
	-- console, because the window's painted lines are a hundred-line screen and
	-- would show the old copy just as happily.
	local lines = net.here:consoleState().lines
	local downs, echoed = 0, false
	for i = 1, #lines do
		if lines[i] == CeroSecOS.TNC.disconnected then downs = downs + 1 end
		if string.find(lines[i], CeroSecOS.TNC_PROMPT .. "D", 1, true) then echoed = true end
	end
	eq("said once and not twice", downs, 1)
	check("and the D that was typed is still on the screen", echoed)
	check("the box is still at cmd:",
		net.here:consoleState().prompt.text == CeroSecOS.TNC_PROMPT)
	check("and cu has NOT hung up", not net.heard(CeroSecOS.CU_DISCONNECTED))
	-- A second D on a box holding nothing says the same thing and nothing else.
	say(net, "D")
	net.tick(2)
	check("D with no link is still one line", net.glass(CeroSecOS.TNC.disconnected))
	say(net, "~.")
	net.tick(3)
	check("and ~. is what gives the shell back", net.heard(CeroSecOS.CU_DISCONNECTED))
	check("at this machine's prompt", net.glass("admin@" .. net.host(net.here)))
	_G.__world = nil
end

-- The set CARRIED AWAY between opening the line and connecting, which is the one
-- way a machine with an open line can have no aerial: the device check is at the
-- door (cu would not open a line with nothing behind it), so this is the path the
-- link layer's own "no radio" is left for, and a bench is what keeps that line a
-- line rather than a nil.
do
	local net = newRadioNet()
	local mine = net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	tnc(net)
	check("the line is open", net.glass(CeroSecOS.TNC_BANNER))
	-- Somebody unplugs the set and walks off with it: what is left on the square is
	-- not a two-way radio any more, so the machine has no TNC.
	mine.data.twoWay = false
	net.forget()
	say(net, "C " .. callOf(net.far))
	net.tick(3)
	check("the machine says it has no radio, in its own name",
		net.heard(CeroSecOS.TNC_NO_RADIO))
	check("having transmitted nothing", #net.air == 0)
	check("and opened no line over there", net.far.ptys == nil)
	eq("and the box is still at cmd:",
		net.here:consoleState().prompt.text, CeroSecOS.TNC_PROMPT)
	_G.__world = nil
end

-- MHEARD: what the boxes in earshot wrote down. A connect is two transmissions,
-- so both ends have each other in their list, and the power going out empties it.
do
	local net = newRadioNet()
	local mine = net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	local myCall, theirCall = callOf(net.here), callOf(net.far)

	tnc(net)
	net.forget()
	say(net, "MH")
	net.tick(2)
	check("a box that has heard nothing prints nothing",
		not net.heard(theirCall))
	say(net, "C " .. theirCall)
	net.tick(3)
	check("the link is up", net.glass(CeroSecOS.TNC.connected .. theirCall))

	-- The far machine wrote this station down, off the caller's own transmission.
	-- Read off the list rather than typed at: there is no window on that machine,
	-- and what MH prints out of a list is pinned in os_test.
	local theirs = net.far.heard
	check("the far box heard this station", theirs ~= nil and #theirs == 1)
	eq("by callsign", theirs[1].call, myCall)
	check("with a time on it", type(theirs[1].at) == "number")
	local shown = CeroSecOS.heardLines(theirs)
	check("which is what MH would print over there",
		string.find(shown[1], myCall, 1, true) == 1)

	-- And this one heard the far station answer, which is the other half of a
	-- connect. Typed at the box, because this is the machine with the window.
	net.escape()
	net.tick(2)
	net.forget()
	say(net, "MH")
	net.tick(3)
	check("MH lists the station this box heard", net.heard(theirCall))
	-- And the list itself, which is what the glass was printed from: one station,
	-- the far one, and never this station's own callsign -- a box does not hear
	-- itself, and the boot screen has this machine's call on the glass already.
	check("this box wrote the far station down", net.here.heard ~= nil)
	eq("one station in the list", #net.here.heard, 1)
	eq("and it is the far station", net.here.heard[1].call, theirCall)

	-- MHCLEAR empties it, and so does the power going out: the list is RAM in a
	-- box on a desk, with no battery behind it.
	net.forget()
	say(net, "MHCLEAR")
	net.tick(2)
	net.forget()
	say(net, "MH")
	net.tick(2)
	eq("the machine's own list is empty", #net.here.heard, 0)
	eq("the far one still has its own", #net.far.heard, 1)
	net.far:turnOff()
	eq("and the power going out takes that one", net.far.heard, nil)

	-- Eighteen deep, and the nineteenth station pushes the oldest off the bottom.
	-- Driven through the link layer, which is the half that decides who can hear
	-- what: one transmission per station, from this machine's own aerial.
	net.here.heard = nil
	local calls = {}
	for i = 1, 19 do
		calls[i] = CeroSecOS.callsignFor(4, 200, i)
		CeroSecNet.heardOnAir(net.system, CeroSecRadio.tncOf(net.far), calls[i], 1000 + i)
	end
	local list = net.here.heard
	eq("eighteen and no more", #list, CeroSecOS.MHEARD_MAX)
	eq("the nineteenth is on top", list[1].call, calls[19])
	eq("and the first one heard is gone", list[18].call, calls[2])
	local _ = mine
	_G.__world = nil
end

-- Hearing is not connecting: one transmission, so the only range in it is the
-- TRANSMITTER's, and a station out of earshot writes nothing down at all.
do
	local net = newRadioNet()
	net.aerial(net.here)
	local theirs = net.aerial(net.far)
	net.login("admin")

	-- Out of range: the far set is 50 tiles away and this bench moves it further
	-- than its own range carries.
	theirs.data.range = 10
	eq("nobody in earshot", CeroSecNet.heardOnAir(net.system,
		CeroSecRadio.tncOf(net.far), callOf(net.far), 100), 0)
	check("so nothing was written down", net.here.heard == nil)
	theirs.data.range = 7500
	eq("in earshot, one box wrote it down", CeroSecNet.heardOnAir(net.system,
		CeroSecRadio.tncOf(net.far), callOf(net.far), 100), 1)
	eq("and it is the far station's callsign",
		net.here.heard[1].call, callOf(net.far))

	-- Another frequency is another conversation, and a receiver on one heard
	-- nothing at all.
	net.here.heard = nil
	theirs.data.channel = 145010
	eq("a station on another frequency is not heard",
		CeroSecNet.heardOnAir(net.system, CeroSecRadio.tncOf(net.far),
			callOf(net.far), 100), 0)
	check("nothing written", net.here.heard == nil)
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

	-- No aerial at all: there is no line to open, and cu can see that for itself
	-- because a radio is a file under /dev and there is nothing at that name.
	say(net, "cu -l " .. CeroSecOS.TNC_DEV)
	net.tick(3)
	check("a machine with no set has no line to open",
		net.glass(CeroSecOS.tncNoDevice(CeroSecOS.TNC_DEV)))
	check("having never transmitted", #net.air == 0)
	check("and opened no line over there", net.far.ptys == nil)

	local mine = net.aerial(net.here)
	local theirs = net.aerial(net.far)

	-- This machine's own set switched off: a TNC cannot tell, so it transmits
	-- into a dead radio and the retries run out.
	mine.data.on = false
	connect(net, theirCall)
	check("a set of one's own that is off is silence, not a diagnosis",
		net.glass(CeroSecOS.TNC.retry))
	mine.data.on = true

	-- The far set switched off.
	theirs.data.on = false
	connect(net, theirCall)
	check("a far set that is off is the same silence", net.glass(CeroSecOS.TNC.retry))
	theirs.data.on = true

	-- The far set with no power.
	theirs.data.power = 0
	connect(net, theirCall)
	check("and so is a flat battery over there", net.glass(CeroSecOS.TNC.retry))
	theirs.data.power = 1

	-- Two frequencies are two conversations.
	theirs.data.channel = 145010
	connect(net, theirCall)
	check("the wrong frequency is silence too", net.glass(CeroSecOS.TNC.retry))
	theirs.data.channel = 144390

	-- Out of range: the SMALLER of the two ranges decides, so one narrow set is
	-- enough to break a link two wide ones would have carried.
	theirs.data.range = 10
	connect(net, theirCall)
	check("out of range is silence", net.glass(CeroSecOS.TNC.retry))
	theirs.data.range = 7500

	-- A callsign nobody answers to.
	connect(net, "W4ZZZ")
	check("a station the county has not got is the same line",
		net.glass(CeroSecOS.TNC.retry))

	-- A machine switched off cannot answer.
	net.far:turnOff()
	connect(net, theirCall)
	check("nor can a computer that is switched off", net.glass(CeroSecOS.TNC.retry))
	_G.__world = nil
end

-- Calling oneself, and the shape of the word.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.login("admin")
	connect(net, callOf(net.here))
	check("a station cannot connect to itself", net.glass(CeroSecOS.TNC.retry))
	-- The box is still at cmd: after that, so the rest of the words go straight in.
	-- A TNC upper-cases what you type at it, so a lower-case callsign is a
	-- callsign; a word that is not one at all gets the box's one error line.
	say(net, "C kd4axr")
	net.tick(3)
	check("a lower-case callsign is upper-cased, and is this station",
		net.glass(CeroSecOS.TNC.retry))
	say(net, "C")
	net.tick(3)
	check("a connect with nothing to connect to", net.glass(CeroSecOS.TNC.eh))
	say(net, "C 555-0142")
	net.tick(3)
	check("nor is a telephone number a callsign", net.glass(CeroSecOS.TNC.eh))
	say(net, "HELLO")
	net.tick(3)
	check("and a word the box never heard of", net.glass(CeroSecOS.TNC.eh))
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
	connect(net, callOf(net.far))
	check("a station whose chunk is not loaded cannot be raised",
		net.glass(CeroSecOS.TNC.retry))
	-- And the line hung up before the telephone is tried, or cu would be holding
	-- the serial line while a second cu wanted to dial.
	say(net, "~.")
	net.tick(2)
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
	connect(net, callOf(net.far), 2)
	say(net, "admin")
	say(net, "")
	net.tick(2)
	check("the first machine has the air", net.glass("admin@" .. net.host(net.far)))
	-- The other computer in the room, on the same aerial.
	typeAt(net, net.gate, "cu -l " .. CeroSecOS.TNC_DEV)
	answerAt(net, net.gate, "C " .. callOf(net.far))
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
	connect(net, callOf(net.far), 2)
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
	-- And the box is back at ITS prompt and not at the shell: cu is still holding
	-- the serial line, which is the whole difference between a link going away and
	-- a line being hung up.
	--
	-- Asked of the CONSOLE and not of the glass, and that is the lesson of this
	-- bench: `cmd:` is on the screen already, five lines up from when the line was
	-- opened, so a painted-line search is green on a box that has been left hanging
	-- for ever. What is asked is what the machine is WAITING for.
	local console = net.here:consoleState()
	eq("the machine is at a question", CeroSec.consoleWaiting(console), "prompt")
	eq("and it is the box's own prompt", console.prompt.text, CeroSecOS.TNC_PROMPT)
	eq("answered by the TNC", console.prompt.cont.cmd, "job")
	check("the glass is this machine's again", console.remote == nil)
	say(net, "~.")
	net.tick(2)
	eq("and ~. gives the shell back", CeroSec.consoleWaiting(net.here:consoleState()),
		"shell")
	check("with cu's own last word", net.heard(CeroSecOS.CU_DISCONNECTED))
	_G.__world = nil
end

-- call wants a terminal, exactly as rlogin and cu do: a crontab line that
-- called would be a session nobody could ever type at.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	net.crontab(net.here, "admin", "* * * * * cu -l " .. CeroSecOS.TNC_DEV)
	net.minute(2)
	eq("a crontab opens no line on the far machine",
		CeroSecOS.ptyCount(net.far.ptys), 0)
	local mail = net.text(net.here, "/var/mail/admin")
	check("and the mail says why", mail ~= nil and
		string.find(mail, "cu: not a terminal", 1, true) ~= nil)
	check("having never transmitted either", #net.air == 0)
	say(net, "cu -l " .. CeroSecOS.TNC_DEV .. " &")
	net.tick(4)
	check("a backgrounded one says it has no terminal either",
		net.heard("cu: not a terminal"))
	_G.__world = nil
end

-- 1200 baud: half what a telephone call carries, and the far machine as fast as
-- it ever was.
do
	local net = newRadioNet()
	net.aerial(net.here)
	net.aerial(net.far)
	net.login("admin")
	connect(net, callOf(net.far), 2)
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
		-- The NAME is modelled the way the engine really holds it: one field, which
		-- getName and getDisplayName both just read (javap -c
		-- zombie.inventory.InventoryItem -- getDisplayName is a single getfield on
		-- `name`), starting at the item's ordinary name and replaced wholesale by
		-- setName. So a disk with no label is a disk whose name is the generic one and
		-- NOT a disk with no name -- which is exactly the case that would let a bench
		-- pass while the server read the generic name as a label.
		local item = {
			id = self.nextID,
			type = fullType,
			data = data or {},
			name = "3.5 inch Floppy Disk",
			customName = false,
			synced = 0,
			getID = function(self) return self.id end,
			getFullType = function(self) return self.type end,
			hasModData = function(self) return true end,
			getModData = function(self) return self.data end,
			getContainer = function(self) return inv end,
			getName = function(self) return self.name end,
			setName = function(self, s) self.name = s end,
			isCustomName = function(self) return self.customName end,
			-- And it writes on the item's modData while it is at it, which is the whole
			-- of why a labelled disk could not be inserted in a real save while this
			-- bench was green: the engine rawsets `customName` on that very table with
			-- the item's name in it (javap -c zombie.inventory.InventoryItem,
			-- setCustomName(boolean): getModData at 6, ldc "customName" at 9, getfield
			-- name at 13, String.valueOf at 16, KahluaTable.rawset at 19). It is written
			-- for false as well as true -- the call is one unconditional rawset -- so
			-- taking a label off leaves the key there too.
			setCustomName = function(self, b)
				self.customName = b
				self.data.customName = tostring(self.name)
			end,
			syncItemFields = function(self) self.synced = self.synced + 1 end,
			-- And the tooltip is on that same table, because the engine puts it there
			-- rather than on a field of its own: setTooltip rawsets the key "Tooltip"
			-- on the item's modData and getTooltip reads it back from there first
			-- (javap -p -c zombie.inventory.InventoryItem, setTooltip: getModData at
			-- 1, ldc "Tooltip" at 4, rawset at 8; getTooltip: rawget at 7). So what a
			-- disk coming out of the drive is marked with is in the table the save
			-- file keeps, and this bench can count it.
			setTooltip = function(self, key) self.data.Tooltip = key end,
			getTooltip = function(self) return self.data.Tooltip end,
			-- The script behind the item, which is where the engine itself goes when
			-- it has to put an item's own name back (javap -p -c
			-- zombie.inventory.InventoryItem, setRecordedMediaIndex: getScriptItem at
			-- 69, Item.getDisplayName at 72, putfield name at 75). It answers the
			-- DisplayName in items_cerosec.txt, which is what a disk nobody has
			-- written on is called.
			getScriptItem = function()
				return { getDisplayName = function() return "3.5 inch Floppy Disk" end }
			end,
		}
		self.items[#self.items + 1] = item
		return item
	end
	-- AddItem MAKES AN ITEM, and making an item in this game runs the creation hook
	-- on it: Item.InstanceItem calls InventoryItem.initialiseItem() at 4059 and that
	-- is what reaches `OnCreate` (the whole chain is over
	-- CeroSecContent.onCreateFloppy). A fake that quietly handed back an undressed
	-- item was a fake in which the drive could not be caught handing a survivor a
	-- blank disk wearing a product's label -- the hook rolls one onto every floppy
	-- the game makes, the eject's own one included.
	function inv:AddItem(fullType)
		local item = self:add(fullType, {})
		if CeroSec.isFloppyType(fullType) then
			CeroSecContent.onCreateFloppy(item)
		end
		-- AND ONE NAME THE BENCH CAN FORCE ON, for the belt. The hook is told to
		-- stand down on the paths that write a disk onto a fresh shell, so on those
		-- paths nothing ever names it -- which leaves the code that puts the name
		-- back with nothing to do and no way to be caught not doing it. This is that
		-- flag being MISSED, which is the only thing the belt is there for.
		if self.nameNext ~= nil then
			item:setName(self.nameNext)
			item:setCustomName(true)
			self.nameNext = nil
		end
		return item
	end
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
		-- Cleared on the way IN, so what bench.told answers is this gesture's own
		-- sentence and never the one before it.
		_G.__halos = {}
		CCeroSecSystem.instance:sendCommand(bench.player, command, args)
		bench.frame()
	end

	-- What the survivor was told about the last gesture, and who was told: the
	-- string that reached the halo, or "nothing" -- which is the shape the defect
	-- had. Read off the client's own door, so a sentence here has been all the way
	-- round (deliver -> CeroSecTerminal.onServerAnswer -> driveNotice).
	function bench.told()
		local last = _G.__halos[#_G.__halos]
		if last == nil then return "nothing", nil end
		return tostring(last.text), last.who
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

	--
	-- The sticker, through the slot and back out
	--
	-- The label is written on the ITEM (its custom name) and read at the slot; the
	-- machine keeps it on the disk record and prints it on `mount` and `df`; the
	-- eject puts it back on the shell.
	--
	-- Which has to be ASSERTED and not assumed, because the item does not survive the
	-- round trip: an insert removes it and an eject makes a NEW one with AddItem, so
	-- a label that was not deliberately carried across would be gone.
	--
	local labelled = otherInv:add("CeroSec.FloppyGreen")
	labelled:setName("PAYROLL 93")
	labelled:setCustomName(true)

	-- The other machine's drive still has the red disk in it; out it comes first.
	other.send("ejectfloppy")
	eq("the drive is free", other.object:hasDisk(), false)

	other.send("insertfloppy", { item = labelled:getID() })
	eq("the labelled disk went in", other.object:hasDisk(), true)
	eq("and the machine wrote the sticker on the record",
		CeroSecOS.floppyOf(other.object:osState()).label, "PAYROLL 93")

	-- And the two commands a survivor asks "which disk is this" with say so.
	other.enter("newfs /dev/fd0")
	other.enter("mount /dev/fd0 /mnt")
	other.enter("mount")
	other.frame()
	check("mount names the disk by what is written on it",
		other.painted("/dev/fd0 on /mnt type ufs (rw) (PAYROLL 93)"))
	other.enter("df")
	other.frame()
	check("and df wears it too", other.painted("(PAYROLL 93)"))

	-- Out again: a NEW item, and the handwriting is on it.
	other.enter("umount /mnt")
	other.frame()
	other.send("ejectfloppy")
	local back = nil
	for i = 1, #otherInv.items do
		if otherInv.items[i]:getFullType() == "CeroSec.FloppyGreen" then
			back = otherInv.items[i]
		end
	end
	check("the green disk is back", back ~= nil)
	check("and it really is a new item, not the one that went in", back ~= labelled)
	eq("wearing the label", back:getName(), "PAYROLL 93")
	eq("as a custom name, or the game would not save it", back:isCustomName(), true)
	-- ONCE, and once is the whole of it: the shell is a new item and the creation
	-- hook stood down for it (CeroSecContent.ejecting), so the only name ever
	-- written on it is the sticker that was really in the drive. A second sync here
	-- would be the hook having rolled one of its own first.
	eq("synced, so the other side of a multiplayer game sees it", back.synced, 1)
	eq("and the record on it says the same thing", back:getModData().label, "PAYROLL 93")

	-- Back in, and the label is still the label: it lives on the disk and survives
	-- as many trips through the slot as the survivor makes.
	other.send("insertfloppy", { item = back:getID() })
	eq("the label survived the round trip",
		CeroSecOS.floppyOf(other.object:osState()).label, "PAYROLL 93")

	-- A disk with NO label: no sticker on the record, and no empty brackets on the
	-- two lines. The generic item name is not a label, and reading it as one would
	-- put "3.5 inch Floppy Disk" in the mount listing of every machine in Kentucky.
	other.send("ejectfloppy")
	local plain = otherInv:add("CeroSec.FloppyBlue")
	eq("its name is the ordinary one", plain:getName(), "3.5 inch Floppy Disk")
	eq("and it is not a custom name", plain:isCustomName(), false)
	other.send("insertfloppy", { item = plain:getID() })
	eq("an unlabelled disk carries no sticker",
		CeroSecOS.floppyOf(other.object:osState()).label, nil)
	other.enter("newfs /dev/fd0")
	other.enter("mount /dev/fd0 /mnt")
	other.enter("mount")
	other.frame()
	check("and mount prints the bare line",
		other.painted("/dev/fd0 on /mnt type ufs (rw)"))
	check("with the generic name nowhere near it",
		not other.painted("3.5 inch Floppy Disk"))

	-- Erased: a name the survivor took the flag off. The slot CLEARS the record
	-- rather than leaving the last label on it, or a disk somebody erased would come
	-- out of the drive still labelled.
	other.enter("umount /mnt")
	other.frame()
	other.send("ejectfloppy")
	local erased = otherInv:add("CeroSec.FloppyRed")
	erased:setName("OLD")
	erased:setCustomName(true)
	other.send("insertfloppy", { item = erased:getID() })
	eq("labelled first", CeroSecOS.floppyOf(other.object:osState()).label, "OLD")
	other.send("ejectfloppy")
	local again = nil
	for i = 1, #otherInv.items do
		if otherInv.items[i]:getFullType() == "CeroSec.FloppyRed" then
			again = otherInv.items[i]
		end
	end
	again:setCustomName(false)
	other.send("insertfloppy", { item = again:getID() })
	eq("and the erase reaches the record",
		CeroSecOS.floppyOf(other.object:osState()).label, nil)

	-- A label a CLIENT could never have typed. The slot holds what arrives to
	-- CeroSecOS.labelOk, which is tighter than the gate: the two commands that print
	-- it are lines on a screen, and a forged name with a newline in it would put a
	-- second line in the mount listing.
	other.send("ejectfloppy")
	local forged = otherInv:add("CeroSec.FloppyYellow")
	forged:setName("two\nlines")
	forged:setCustomName(true)
	other.send("insertfloppy", { item = forged:getID() })
	eq("a forged label is not written on the record",
		CeroSecOS.floppyOf(other.object:osState()).label, nil)
	eq("and the disk went in all the same", other.object:hasDisk(), true)
	other.send("ejectfloppy")
	local over = otherInv:add("CeroSec.FloppyYellow")
	over:setName(string.rep("L", CeroSecOS.LABEL_MAX + 1))
	over:setCustomName(true)
	other.send("insertfloppy", { item = over:getID() })
	eq("nor is one over the ceiling",
		CeroSecOS.floppyOf(other.object:osState()).label, nil)
	other.send("ejectfloppy")

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
	bench.object:reindex()
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

	-- An id that names nothing. AND HE IS TOLD: every refusal below used to be a
	-- bare return, which is the defect behind the defect -- the diagnostics disk was
	-- refused at the gate, the action played, and the only trace was a warn line
	-- behind a debug flag. A gesture that does nothing and says nothing is a mod that
	-- looks broken.
	bench.send("insertfloppy", { item = 999 })
	eq("an id that names nothing inserts nothing", bench.object:hasDisk(), false)
	eq("and he is told the disk is not in his hands", bench.told(),
		"IGUI_CeroSec_Drive_NoDisk")
	local _, who = bench.told()
	eq("over his own head and nobody else's", who, bench.player)
	-- An id that names something that is not a disk.
	local book = inv:add("CeroSec.ManualUser")
	bench.send("insertfloppy", { item = book:getID() })
	eq("a book is not a disk", bench.object:hasDisk(), false)
	eq("and it is still in his hands", #inv.items, 1)
	eq("and the same sentence for it, because it is the same thing to him",
		bench.told(), "IGUI_CeroSec_Drive_NoDisk")
	-- No id at all. The one refusal that stays silent: the client always sends the
	-- id of the disk it offered, so a packet without one is a packet nobody typed
	-- and there is no survivor waiting on an answer to it.
	bench.send("insertfloppy", {})
	eq("a packet with no item in it inserts nothing", bench.object:hasDisk(), false)
	eq("and answers nothing at all", bench.told(), "nothing")

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
	-- And the REASON reaches him, in the machine's own words, with the gate's
	-- "floppy: " off the front because the sentence has already named the disk.
	eq("with the gate's own reason over his head", bench.told(),
		"IGUI_CeroSec_Drive_Refused disk full")
	-- A disk of a version this machine does not know.
	local future = inv:add("CeroSec.FloppyBlue", { v = 99 })
	bench.send("insertfloppy", { item = future:getID() })
	eq("so is one from a version nobody here knows", bench.object:hasDisk(), false)
	eq("and that reason is a different sentence", bench.told(),
		"IGUI_CeroSec_Drive_Refused newer than this mod")
	-- One slot, and something in it. The menu greys this case out, so reaching it is a
	-- second push made before the news of the first came back -- and the answer is
	-- the wording the MENU uses for it, because a survivor should not read two
	-- sentences for one rule.
	local first = inv:add("CeroSec.FloppyBlue")
	bench.send("insertfloppy", { item = first:getID() })
	eq("an honest disk goes in", bench.object:hasDisk(), true)
	eq("with nothing said about it", bench.told(), "nothing")
	local second = inv:add("CeroSec.FloppyRed")
	bench.send("insertfloppy", { item = second:getID() })
	eq("the second one does not", CeroSec.floppyTypeOr(bench.object:osState().fdtype),
		"CeroSec.FloppyBlue")
	eq("and he is told to eject the first", bench.told(), "Tooltip_CeroSec_DriveFull")
	-- Out again, so what follows meets the empty drive it was written for.
	bench.send("ejectfloppy")
	eq("the drive is empty again", bench.object:hasDisk(), false)

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
	eq("and reads that the machine is not there for him",
		bench.told(), "IGUI_CeroSec_Drive_Gone")
	bench.player.getX = away
	bench.send("insertfloppy", { item = good:getID() })
	eq("and the same player standing at it does", bench.object:hasDisk(), true)
	eq("with nothing over his head about it", bench.told(), "nothing")
end

--
-- THE DISK THE DEBUG WINDOW HANDS OVER GOES IN (rung 4e)
--
-- The bug this is here for: `debugact givedisk` handed over a disk with a label on
-- it, the insert action played, and nothing happened -- no disk in the drive, no
-- sentence anywhere. The cause was two files apart from each other. Writing the
-- label calls `item:setCustomName(true)`, and that call rawsets a `customName` key
-- on the ITEM's modData (javap -c zombie.inventory.InventoryItem,
-- setCustomName(boolean), offsets 5-24), so the slot's closed-key rule met a fourth
-- key on the table and refused the disk -- every labelled disk in the world, not
-- just this one. It stayed green here because the fake only moved a flag.
--
-- So this walks the whole of it through the real paths: the debug act that makes
-- the disk, the command the client sends for it, the drive, and `mount`.
--
do
	local bench = newBench()
	local inv = wireDrive(bench)
	local answers = {}
	bench.system.reply = function(_, _, _, args) answers[#answers + 1] = args end
	bench.system:OnClientCommand("debugact", bench.player,
		{ x = 0, y = 0, z = 0, token = "dbg-0-1", act = "givedisk" })
	eq("the disk is in his bag", #inv.items, 1)
	local item = inv.items[1]
	eq("with the sticker on the shell", item:getName(), "CeroSec DIAGNOSTICS 1.0")
	-- And the sticker is PRINTED, which the survivor can see without reading it:
	-- the company's own service disk came out of the same factory as its software.
	-- Marked off the label and not off the entry beside it, so this path and an
	-- eject answer the question the same way (CeroSecContent.markByLabel).
	eq("and the tooltip says it was printed", item:getTooltip(),
		CeroSecContent.PRINTED_TOOLTIP)
	eq("and the shell wears the printed look",
		item:getModData()[CeroSecContent.ICON_KEY],
		CeroSec.floppyPrintedIcon(item:getFullType()))
	check("and the game's own key on the item beside ours",
		item:getModData().customName ~= nil)
	check("and the receipt is a note and not a refusal",
		answers[1] ~= nil and answers[1].error == nil)

	-- The id the CLIENT would send for that item, which is the one thing
	-- ISCeroSecDiskAction puts in the packet (item:getID()).
	bench.login("admin")
	bench.send("insertfloppy", { item = item:getID() })
	eq("the drive took it", bench.object:hasDisk(), true)
	eq("it left his hands", #inv.items, 0)
	eq("and nothing was said, because nothing was refused", bench.told(), "nothing")

	-- And it is the diagnostics disk, by its own label and its own file.
	eq("the sticker is the disk's label in the drive",
		CeroSecOS.floppyOf(bench.object:osState()).label, "CeroSec DIAGNOSTICS 1.0")
	bench.enter("mount /dev/fd0 /mnt")
	bench.enter("mount")
	bench.frame()
	check("and mount names it on the glass",
		bench.painted("/dev/fd0 on /mnt type ufs (rw) (CeroSec DIAGNOSTICS 1.0)"))
	bench.enter("ls /mnt")
	bench.frame()
	check("with the self-test on it", bench.painted("selftest.sh"))

	-- AND IT COMES BACK OUT LOOKING LIKE ITSELF. An insert DESTROYS the item and an
	-- eject makes a NEW one, so everything the shell was wearing has to be put back
	-- on the new one -- and that new one was made by inv:AddItem, which means the
	-- creation hook ran on it and rolled it a disk of its own before the eject
	-- overwrote the three keys a disk owns. The look the roll left behind is NOT one
	-- of those three, so it is written over here on purpose and this is what says so.
	bench.enter("umount /mnt")
	bench.frame()
	bench.send("ejectfloppy")
	eq("the disk is back in his hands", #inv.items, 1)
	local out = inv.items[1]
	eq("with the printed sticker still on it", out:getName(),
		"CeroSec DIAGNOSTICS 1.0")
	eq("and still saying it was printed", out:getTooltip(),
		CeroSecContent.PRINTED_TOOLTIP)
	eq("and still wearing the printed look",
		out:getModData()[CeroSecContent.ICON_KEY],
		CeroSec.floppyPrintedIcon(out:getFullType()))
end

--
-- AND A DISK WITH NOTHING WRITTEN ON IT COMES OUT WEARING NOTHING (rung 4e)
--
-- The other half of the eject, and the one the roll can lie about: the item the
-- drive hands back is made by inv:AddItem, the creation hook fires on it, and a
-- roll that landed on a printed entry would have dressed the shell before the disk
-- was written over it. A blank disk coming out with a product's icon on it is a
-- disk claiming to be something it has not got a byte of.
--
do
	local bench = newBench()
	local inv = wireDrive(bench)
	bench.login("admin")
	-- A disk with nothing on it, made the way the bench makes one -- inv:add, which
	-- is the container filling itself and not the game instancing an item, so
	-- nothing has been rolled onto this one.
	local blank = inv:add("CeroSec.FloppyBlue")
	eq("it went in blank", blank:getModData().v, nil)
	-- And the roll the EJECT's own item will meet, nailed to a printed entry rather
	-- than left to the box: this is the case the guard exists for, and a bench that
	-- took whatever the generator answered would be green for the wrong reason four
	-- times in five.
	local hadRand = _G.ZombRand
	_G.ZombRand = function() return 0 end
	local rolled = inv:AddItem("CeroSec.FloppyBlue")
	eq("a fresh shell really is dressed by the hook", rolled:getTooltip(),
		CeroSecContent.PRINTED_TOOLTIP)
	inv:Remove(rolled)
	bench.send("insertfloppy", { item = blank:getID() })
	eq("the blank disk went in", bench.object:hasDisk(), true)
	bench.send("ejectfloppy")
	eq("and came back out", #inv.items, 1)
	local out = inv.items[1]
	eq("with nothing written on it", out:getModData().label, nil)
	-- THE NAME, which is the mark the roll leaves that everything else here would
	-- have missed: the item the drive made is a real floppy and the hook would have
	-- named it for whatever it rolled. It comes back called what every disk out of
	-- the box is called, and not as a custom name -- a custom one is what the game
	-- saves, and it would follow the disk for the rest of the save.
	eq("and the name it came with", out:getName(), "3.5 inch Floppy Disk")
	eq("which is not a custom name", out:isCustomName(), false)
	-- And nothing was written on it either: the hook builds a whole filesystem
	-- before writeDiskTo clears it, and a shell that arrives blank never built one.
	eq("no filesystem on it", out:getModData().fs, nil)
	-- It does carry a version, and that is right: what came out is a disk record
	-- the drive made, and every disk has one. What it has not got is the tree the
	-- hook would have built on it.
	eq("only the version every disk carries", out:getModData().v,
		CeroSecOS.FLOPPY_VERSION)
	eq("nothing said about its label", out:getTooltip(), nil)
	eq("and no printed look on the shell",
		out:getModData()[CeroSecContent.ICON_KEY], nil)

	-- THE BELT, with the flag missed on purpose: a shell that arrives named anyway
	-- still comes back out of the drive called what a disk out of the box is
	-- called. Put back off the SCRIPT, because the name a custom one replaced
	-- cannot be asked of the item any more (CeroSecContent.unname).
	bench.send("insertfloppy", { item = out:getID() })
	eq("the blank disk went back in", bench.object:hasDisk(), true)
	inv.nameNext = "CeroSec UTILITIES 1.0"
	bench.send("ejectfloppy")
	local belted = inv.items[1]
	eq("a shell that arrived named comes back unnamed", belted:getName(),
		"3.5 inch Floppy Disk")
	eq("and not as a custom name", belted:isCustomName(), false)

	-- And the flag is down again afterwards, or the next floppy the world made
	-- would come out of a drawer blank for ever.
	eq("the hook is listening again", CeroSecContent.ejecting, false)
	local after = inv:AddItem("CeroSec.FloppyBlue")
	eq("and the next floppy the game makes is rolled as usual", after:getTooltip(),
		CeroSecContent.PRINTED_TOOLTIP)
	inv:Remove(after)
	_G.ZombRand = hadRand
end

--
-- Every sentence the drive can put over a survivor's head is one the mod ships, in
-- both languages: a code whose string is missing comes out on the glass as the key.
--
do
	local files = { IGUI = "IG_UI.json", Tooltip = "Tooltip.json" }
	for why, key in pairs(CeroSecTerminal.DRIVE_NOTICES) do
		local prefix = string.match(key, "^([^_]+)_")
		local file = files[prefix]
		check("the drive's " .. why .. " names a key of a file that exists: " .. key,
			file ~= nil)
		for _, lang in ipairs({ "EN", "FR" }) do
			local handle = assert(io.open(
				"42/media/lua/shared/Translate/" .. lang .. "/" .. file, "r"))
			local strings = handle:read("*a")
			handle:close()
			check(lang .. "/" .. file .. " defines " .. key,
				string.find(strings, '"' .. key .. '"', 1, true) ~= nil)
			-- The one sentence that carries the machine's own reason has somewhere to
			-- put it. A translation without the %1 is a reason nobody reads.
			if why == "refused" then
				local line = string.match(strings, '"' .. key .. '"%s*:%s*"([^"]*)"')
				check(lang .. " puts the reason in it: " .. tostring(line),
					line ~= nil and string.find(line, "%1", 1, true) ~= nil)
			end
		end
	end
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
		-- Named, because it is on a square the device scan walks now, and a plain
		-- IsoObject is not a light switch, a door or a window: the classifier asks
		-- instanceof about each object it finds (SCeroSecDevices.classify) and the
		-- fake that answers "yes" to everything would fit a relay to a computer.
		local iso = { __class = "IsoObject", sprite = CeroSec.SPRITES_OFF["S"], modData = {} }
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
		-- On its tile, which is the only place the CLIENT can find it: the client
		-- has no GlobalObject of its own to read a sprite off, it walks the square's
		-- objects (CGlobalObjectSystem:getIsoObjectOnSquare).
		here.objects[#here.objects + 1] = iso

		-- The cell, which is a different question from the machine's own square:
		-- /dev and the sensor scan are discovered through getCell
		-- (CeroSecDevices.find), so a chunk that is away has to be away from that
		-- too. Nothing else in the county is in this cell, which is all the two
		-- benches that read /dev need.
		local cell = { getGridSquare = function(_, gx, gy, gz)
			if not chunk.loaded or gz ~= 0 then return nil end
			if gx == x and gy == y then return here end
			if gx == x + 1 and gy == y then return beside end
			return nil
		end }

		-- And the cell's lampposts, which is what the glow IS. addLamppost pushes an
		-- IsoLightSource onto IsoCell.lamppostPositions and hands it back;
		-- removeLamppost takes one off. strays counts a removal aimed at a source the
		-- stack has not got: the game would shrug that off (removeLamppost only sets
		-- the source's life to 0), so it is counted here rather than thrown, and
		-- asserted at zero -- a mod that keeps aiming at lights the engine already
		-- took is a mod that thinks it has one.
		chunk.lampposts = {}
		chunk.strays = 0
		cell.getLightSourceAt = function(_, gx, gy, gz)
			for i = 1, #chunk.lampposts do
				local light = chunk.lampposts[i]
				if light.x == gx and light.y == gy and light.z == gz then return light end
			end
			return nil
		end
		cell.addLamppost = function(_, gx, gy, gz, r, g, b, radius)
			local light = { x = gx, y = gy, z = gz, r = r, g = g, b = b, radius = radius }
			chunk.lampposts[#chunk.lampposts + 1] = light
			return light
		end
		cell.removeLamppost = function(_, light)
			for i = 1, #chunk.lampposts do
				if chunk.lampposts[i] == light then
					table.remove(chunk.lampposts, i)
					return
				end
			end
			chunk.strays = chunk.strays + 1
		end
		_G.__world = cell

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
			-- What the engine does when the window of loaded chunks moves off a
			-- square, and does without a word to anybody: LightingJNI.checkLights
			-- walks IsoCell.getLamppostPositions() every pass and removes any source
			-- whose isInBounds() is false -- "inside some player's IsoChunkMap world
			-- tiles" -- or whose recorded chunk is not the chunk now covering its
			-- square (javap -c LightingJNI.checkLights, offsets 78-123, and
			-- IsoLightSource.isInBounds). The mod keeps its handle and loses the
			-- light, which is the whole bug this section is about.
			chunk.lampposts = {}
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

	-- 42b. THE GLOW THAT DID NOT COME BACK
	--
	-- "When I teleport very far and come back, the computer light is not there even
	-- though the computer is on." The sprite was right and the glow was gone, and it
	-- never came back -- not on the next chunk load, not ever.
	--
	-- Two faults, one behind the other, and both are about who OWNS the light.
	--
	-- The engine takes it. LightingJNI.checkLights walks
	-- IsoCell.getLamppostPositions() and removes any source whose isInBounds() is
	-- false -- "inside some player's IsoChunkMap world tiles" -- or whose recorded
	-- chunk is not the chunk now covering its square (javap -c on 42.20.4:
	-- checkLights offsets 78-123, IsoLightSource.isInBounds). Nothing is said to
	-- anybody. The mod kept the handle addLamppost had given it and read "I have a
	-- handle" as "there is a light", so addLight did nothing for ever after.
	--
	-- And nothing asked. The announce is the only call the client gets when a chunk
	-- comes back (the server's stateToIsoObject ends in newLuaObjectOnClient), and
	-- Java's receiveNewLuaObjectAt calls the Lua newLuaObjectAt and no other method:
	-- OnLuaObjectUpdated is named only inside receiveUpdateLuaObjectAt (javap -c
	-- CGlobalObjectSystem). A minute sweep used to paper over it, and could not: the
	-- sweep called the same syncLight that believed the same handle.
	--
	-- So the whole client half runs here for real -- CCeroSecObject and
	-- CCeroSecSystem, not the stub the window benches send commands through -- with
	-- Java's two receive methods written out in the order Java does them.
	do
		local net = newNet()
		local chunk = streamed(net, 20, 10)
		local far = chunk.object
		local client = CClientSystem:new()

		-- The synced keys, and only those: the server writes the ones it has and the
		-- client rawsets the ones it receives (TableNetworkUtils.saveSome and the copy
		-- loop in both receive methods).
		local function sync(mirror, source)
			local keys = net.system.system.syncKeys
			for i = 1, #keys do
				local value = source[keys[i]]
				if value ~= nil then mirror[keys[i]] = value end
			end
		end
		-- receiveNewLuaObjectAt: newLuaObjectAt FIRST, the copy after it. The order is
		-- the point -- a client that read its own `on` inside newLuaObjectAt would be
		-- reading the state from before the packet, which is why the glow is decided
		-- off the sprite the chunk brought with it.
		local function announce(source)
			local mirror = client:newLuaObjectAt(source.x, source.y, source.z)
			sync(mirror, source)
			return mirror
		end
		net.system.newLuaObjectOnClient = function(_, o)
			if o == far then chunk.told = chunk.told + 1 end
			announce(o)
		end
		-- receiveUpdateLuaObjectAt: the copy first, OnLuaObjectUpdated after.
		far.updateOnClient = function(self)
			local mirror = client:getLuaObjectAt(self.x, self.y, self.z)
			if not mirror then return end
			sync(mirror, self)
			client:OnLuaObjectUpdated(mirror)
		end

		local function glows() return #chunk.lampposts end

		eq("the machine is on", far.on, true)
		eq("and nothing is lit before the client has been told of it", glows(), 0)

		-- The chunk arrives, which is the announce (MapObjects.OnLoadWithSprite ->
		-- loadIsoObject -> stateToIsoObject).
		chunk.back(true)
		local mirror = client:getLuaObjectAt(20, 10, 0)
		eq("the chunk arrives and the screen glows", glows(), 1)
		eq("on the machine's own square", chunk.lampposts[1].x, 20)
		eq("one square wide", chunk.lampposts[1].radius, CeroSec.LIGHT_RADIUS)
		eq("and bluish-white, so it reads as a monitor", chunk.lampposts[1].b, CeroSec.LIGHT_B)

		-- Ten miles away. The engine drops the light and says nothing.
		chunk.away()
		eq("the survivor leaves the county and the light goes with the chunk", glows(), 0)
		check("while the client is still holding the handle it was given",
			mirror.light ~= nil)

		-- He comes home. THIS is the report.
		chunk.back(true)
		eq("he comes home to a lit screen and the glow is back", glows(), 1)

		-- And the same square is announced more than once per visit, which is the
		-- repeat newLuaObjectAt exists to tolerate.
		net.system:loadIsoObject(chunk.iso)
		net.system:loadIsoObject(chunk.iso)
		eq("announced three times over, and there is exactly one light", glows(), 1)
		eq("and nothing was ever aimed at a light the engine had already taken",
			chunk.strays, 0)

		-- Switched off while nobody could see it: there was no tile to put the dark
		-- sprite on, and there is no light to come back to.
		chunk.away()
		net.forget()
		far:turnOff()
		eq("the crontab -- or the wire -- switched it off out of view", far.on, false)
		chunk.back(true)
		eq("the dark sprite is on the tile", chunk.iso.sprite, CeroSec.SPRITES_OFF["S"])
		eq("and a dark machine comes home with no glow", glows(), 0)
		eq("with nothing aimed at a light either", chunk.strays, 0)

		-- Switched on with the chunk in, which is the other receive method.
		far:turnOn()
		eq("it goes back on", far.on, true)
		eq("and the update lights it where it stands", glows(), 1)

		-- Picked up. The client drops the glow the moment the object leaves its
		-- square -- Events.OnObjectAboutToBeRemoved, which is the earlier of the two
		-- ways it hears -- and the server's removal packet lands on
		-- removeLuaObjectAt right after. Both go through removeLight.
		local stub = CCeroSecSystem
		CCeroSecSystem = CClientSystem
		CCeroSecSystem.instance = client
		OnObjectAboutToBeRemoved.trigger(chunk.iso)
		CCeroSecSystem.instance = nil
		CCeroSecSystem = stub
		eq("picking the computer up takes its glow with it", glows(), 0)
		client:removeLuaObjectAt(20, 10, 0)
		eq("the client has no machine on that square any more",
			client:getLuaObjectAt(20, 10, 0), nil)
		eq("and the removal packet found nothing left to take", chunk.strays, 0)

		-- Put down again, lit. A machine the client has never heard of arrives by the
		-- same announce -- a placement and the first chunk of a session are one path
		-- -- so the glow comes with the state.
		local placed = announce(far)
		eq("the computer put back down is lit again", glows(), 1)
		eq("and the client knows it is on", placed.on, true)
		check("on a mirror that is not the one that was taken away", placed ~= mirror)
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
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
end

-- The control, on a world where nothing at all is wired: the option off is the
-- building as it was before this rung, every device of it, with the numbers the
-- mockup approved. This is the same assertion the first device section makes and
-- it is made again HERE, beside the gate, so that a gate which stopped reading
-- the option fails in the section it belongs to.
do
	local kit = mockupWorld()
	_G.__world = kit.world
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }

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
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
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
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
end


--
-- 45. The debug snapshots (the debug window's work)
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
-- Three facts about a PLACE and not about a computer, and the telephone work's
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
-- Picking a computer under the mouse
--
-- The screenshot of 2026-09-12: a vanilla computer on a desk at 2089,5832 with a
-- mahogany chair on 2089,5833 pulled up to it, the cursor on the monitor, and no
-- CeroSec entry on the menu at all -- the game's own debug lines naming the CHAIR
-- (Tile Report furniture_seating_indoor_02_0, Room Report x: 2089, y: 5833).
--
-- So this bench is that geometry, built out of the engine's own projection rather
-- than out of the module's: ToScreen and ToWorld below are IsoUtils.XToScreen /
-- YToScreen / XToIso / YToIso written out again from the jar
-- (32*tileScale*(x-y), 16*tileScale*(x+y), and their inverse), with a camera
-- offset that puts the desk somewhere believable on a 1920x1080 screen. If the
-- module and the projection disagree, they disagree here.
--
-- The masks are real too: each object carries a rectangle of opaque texture
-- pixels and isMaskClicked answers out of it, the way IsoSprite's does, so a
-- cursor on the chair's own pixels is a cursor the computer's mask refuses.
--

do
	local stub = CeroSecReach
	local realCore = _G.getCore

	local TS = 2 -- Core.tileScale, which is 2 in B42
	-- Chosen so the desk's screen anchor lands at 600,400.
	local CAM_X = 32 * TS * (2089 - 5832) - 600
	local CAM_Y = 16 * TS * (2089 + 5832) - 400

	local function toScreen(x, y, z)
		return 32 * TS * (x - y) - CAM_X,
			16 * TS * (y + x) + (0 - z) * 96 * TS - CAM_Y
	end
	local function toWorld(sx, sy, z)
		local x, y = sx + CAM_X, sy + CAM_Y
		return (x + 2 * y) / (64 * TS) + 3 * z, (2 * y - x) / (64 * TS) + 3 * z
	end

	_G.Core = { getTileScale = function() return TS end }
	_G.ISCoordConversion = { ToScreen = toScreen, ToWorld = toWorld }
	_G.getCore = function()
		return { getZoom = function() return 1 end,
			getScreenWidth = function() return 1920 end,
			getScreenHeight = function() return 1080 end }
	end
	_G.AdjacentFreeTileFinder = { privTrySquare = function() return true end }
	_G.IsoFlagType = { bed = "bed" }
	_G.SeatingManager = { getInstance = function() return {
		getTilePositionCount = function() return 1 end,
		getFacingDirection = function(_, object) return object.__facing end,
		getAdjacentPosition = function() return false end,
	} end }
	_G.JoypadState = { players = {} }

	local squares = {}
	local function key(x, y, z) return x .. "," .. y .. "," .. z end
	_G.__world = { getGridSquare = function(_, x, y, z)
		return squares[key(math.floor(x), math.floor(y), math.floor(z))]
	end }

	local function square(x, y, z)
		local sq = squares[key(x, y, z)]
		if sq then return sq end
		local objects = {}
		sq = {
			__objects = objects,
			getX = function() return x end,
			getY = function() return y end,
			getZ = function() return z end,
			getObjects = function() return javaList(objects) end,
			canReachTo = function() return true end,
		}
		squares[key(x, y, z)] = sq
		return sq
	end

	-- An object on a square. mask is the rectangle of opaque TEXTURE pixels
	-- (x0, y0, x1, y1 in a 64x128 sheet); raise is renderYOffset, which is what
	-- lifts a sprite standing on a table.
	local function place(x, y, z, sprite, raise, mask, texW, texH)
		local sq = square(x, y, z)
		local o
		o = {
			getSpriteName = function() return sprite end,
			getSquare = function() return sq end,
			getDir = function() return "N" end,
			getObjectIndex = function() return o.__index end,
			getOffsetX = function() return 32 * TS end,
			getOffsetY = function() return 96 * TS end,
			getRenderYOffset = function() return raise or 0 end,
			getSprite = function() return {
				getTextureForCurrentFrame = function() return {
					getWidthOrig = function() return texW or 64 end,
					getHeightOrig = function() return texH or 128 end,
				} end,
				getProperties = function() return {
					has = function(_, name)
						return o.__flags[name] == true or o.__props[name] ~= nil
					end,
					get = function(_, name) return o.__props[name] end,
				} end,
			} end,
			isMaskClicked = function(_, px, py)
				if not mask then return false end
				return px >= mask[1] and px <= mask[3] and py >= mask[2] and py <= mask[4]
			end,
			__flags = {},
			__props = {},
		}
		table.insert(sq.__objects, o)
		o.__index = #sq.__objects - 1
		return o
	end

	local path = "42/media/lua/client/CeroSec/CeroSecReach.lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()

	local menuPath = "42/media/lua/client/CeroSec/CeroSecContextMenu.lua"
	local menuChunk, menuErr = loadfile(menuPath)
	if not menuChunk then error("cannot load " .. menuPath .. ": " .. tostring(menuErr)) end
	local realEvents = _G.Events
	_G.Events = { OnFillWorldObjectContextMenu = { Add = function() end } }
	menuChunk()
	_G.Events = realEvents

	-- The screen anchor the whole bench is pinned to, so a change to the camera
	-- arithmetic above shows up as a failure here and not as ten silent misses.
	do
		-- A canary, not a proof: every cursor coordinate below was worked out by hand
		-- off this anchor, so a change to CAM_X/CAM_Y has to fail here rather than
		-- silently move ten clicks somewhere else.
		local ax, ay = toScreen(2089, 5832, 0)
		eq("the desk's anchor x", ax, 600)
		eq("the desk's anchor y", ay, 400)
		-- This one is a proof: the bench's ToWorld really does invert its ToScreen,
		-- on a square that is neither the anchor nor the origin.
		local sx, sy = toScreen(2091, 5830, 0)
		local wx, wy = toWorld(sx, sy, 0)
		eq("ToWorld inverts ToScreen on x", wx, 2091)
		eq("ToWorld inverts ToScreen on y", wy, 5830)
	end

	--
	-- The screenshot itself
	--
	-- desk at 2089,5832 carrying the computer (renderYOffset 32, a desk's
	-- surface); chair on 2089,5833 looking north at the screen; the cursor on the
	-- monitor's own pixels.
	--
	-- Monitor box: anchor 600,400 less offsetX 64 and offsetY 192 less the raise
	-- 32*2 -> 536,144, 128 by 256. Its opaque pixels are texture rows 88..120,
	-- so screen y 320..384. Chair anchor 536,432 -> box 472,240; its back reaches
	-- texture row 60, so screen y 360..496.
	local MONITOR = { 20, 88, 44, 120 }
	local CHAIRBACK = { 20, 60, 44, 128 }

	local function screenshotWorld()
		squares = {}
		local desk = place(2089, 5832, 0, "furniture_tables_high_01_0")
		desk.__flags.IsTable = true
		desk.__props.Surface = "32"
		local computer = place(2089, 5832, 0, CeroSec.SPRITES_OFF.S, 32, MONITOR)
		local chair = place(2089, 5833, 0, "furniture_seating_indoor_02_0", 0, CHAIRBACK)
		chair.__facing = CeroSec.chairFacingFor("S")
		chair.__flags[IsoFlagType.bed] = true
		return computer, chair, desk
	end

	do
		local computer, chair = screenshotWorld()
		-- The game picked the chair and handed the menu that one object, which is
		-- what the Tile Report and the Room Report in the screenshot say.
		local handed = { chair }

		-- The mouse on the monitor. 598,350 is inside the monitor's opaque band
		-- and outside the chair's.
		eq("the chair's own mask says no there",
			CeroSecReach.isMouseOn(chair, 598, 350, 0), false)
		eq("the monitor's mask says yes",
			CeroSecReach.isMouseOn(computer, 598, 350, 0), true)

		-- The desk's square has to be among the squares looked at, and the mouse's
		-- own tile is two steps of x+y behind it -- nothing like the edge of any
		-- budget. This is the number that kills the "three-tile diagonal" story.
		local wx, wy = toWorld(598, 350, 0)
		local tx, ty = math.floor(wx), math.floor(wy)
		eq("the mouse's tile", tx .. "," .. ty, "2088,5831")
		eq("the desk is this many steps of x+y ahead of it",
			(2089 + 5832) - (tx + ty), 2)
		local found = false
		for _, sq in ipairs(CeroSecReach.pickSquares(598, 350, 0, 1)) do
			if sq:getX() == 2089 and sq:getY() == 5832 then found = true end
		end
		check("the desk's square is looked at", found)

		-- And the whole answer, through the two callers.
		eq("and a desk is a mid-height surface",
			CeroSecReach.height(computer), "mid")

		eq("pickComputer finds the computer",
			CeroSecReach.pickComputer(0, 598, 350, handed), computer)
		_G.getMouseX = function() return 598 end
		_G.getMouseY = function() return 350 end
		eq("findComputer finds it too",
			CeroSecContextMenu.findComputer(handed, 0), computer)
	end

	-- The cursor on the CHAIR's own pixels, not the monitor's. The chair's back
	-- reaches up into the monitor's BOX -- 550,380 is inside it -- so a search
	-- that tested the box and not the mask would answer "computer" here. It must
	-- answer nothing: the pixels under the cursor are the chair's.
	do
		local computer, chair = screenshotWorld()
		local handed = { chair }

		local x, y, w, h = CeroSecReach.drawnBox(computer)
		check("550,380 is inside the monitor's box", CeroSec.pointInBox(550, 380, x, y, w, h))
		eq("but its mask refuses it", CeroSecReach.isMouseOn(computer, 550, 380, 0), false)
		eq("the chair's mask takes it", CeroSecReach.isMouseOn(chair, 550, 380, 0), true)

		-- The desk's square is looked at all the same, so this is the mask saying
		-- no and not the search failing to ask.
		local found = false
		for _, sq in ipairs(CeroSecReach.pickSquares(550, 380, 0, 1)) do
			if sq:getX() == 2089 and sq:getY() == 5832 then found = true end
		end
		check("the desk's square was still looked at", found)

		eq("pickComputer answers nothing", CeroSecReach.pickComputer(0, 550, 380, handed), nil)
		_G.getMouseX = function() return 550 end
		_G.getMouseY = function() return 380 end
		eq("and so does findComputer", CeroSecContextMenu.findComputer(handed, 0), nil)
	end

	-- A computer on the floor: no raise, and the cursor on its pixels finds it.
	do
		squares = {}
		local computer = place(2089, 5832, 0, CeroSec.SPRITES_OFF.S, 0, MONITOR)
		square(2089, 5833, 0)
		eq("and it is found", CeroSecReach.pickComputer(0, 601, 401, { computer }), computer)
		eq("height low", CeroSecReach.height(computer), "low")
	end

	-- A computer on a high shelf. Out of REACH -- that is height's business and
	-- the menu greys the entries out -- but still found, because a player has to
	-- be told why he cannot use it. The raise is 80, which needs six steps of
	-- x+y: exactly the last step of the game's own staircase, and the reason the
	-- window goes further.
	do
		squares = {}
		local shelf = place(2089, 5832, 0, "shelves_01_0")
		shelf.__flags.IsTable = true
		shelf.__props.Surface = "80"
		local computer = place(2089, 5832, 0, CeroSec.SPRITES_OFF.S, 80, MONITOR)
		square(2089, 5833, 0)
		eq("height high", CeroSecReach.height(computer), "high")
		local wx, wy = toWorld(600, 256, 0)
		eq("six steps of x+y ahead of the mouse's tile",
			(2089 + 5832) - (math.floor(wx) + math.floor(wy)), 6)
		eq("and it is still found",
			CeroSecReach.pickComputer(0, 600, 256, { computer }), computer)
	end

	-- worldobjects carrying the computer itself. The mouse is nowhere near it --
	-- off the bottom of the world, where no mask can be hit -- so only the pass that
	-- reads what the game handed over can answer, and deleting that pass turns this
	-- red. A computer is on its own square, which is why that pass is ONE scan and
	-- not a scan behind an "is it the computer itself" branch.
	do
		local computer = screenshotWorld()
		_G.getMouseX = function() return 5 end
		_G.getMouseY = function() return 5 end
		eq("the mask pass finds nothing at 5,5",
			CeroSecReach.pickComputer(0, 5, 5, { computer }), nil)
		eq("handed the computer itself, findComputer takes it",
			CeroSecContextMenu.findComputer({ computer }, 0), computer)
	end

	-- And handed the DESK the computer stands on: a computer on the square of a
	-- picked object is that object's computer, which is how vanilla's own
	-- one-device menus read a table-top (ISRadioAndTvMenu, ISBBQMenu). Same mouse
	-- in the weeds, so again only that pass can answer.
	do
		local computer, _, desk = screenshotWorld()
		_G.getMouseX = function() return 5 end
		_G.getMouseY = function() return 5 end
		eq("handed the desk, findComputer takes the computer on it",
			CeroSecContextMenu.findComputer({ desk }, 0), computer)
	end

	-- A joypad has no mouse at all: the first pass is the whole of its answer.
	do
		local computer, chair = screenshotWorld()
		_G.JoypadState.players = { true }
		_G.getMouseX = function() return 598 end
		_G.getMouseY = function() return 350 end
		eq("joypad: the chair's square has no computer",
			CeroSecContextMenu.findComputer({ chair }, 0), nil)
		eq("joypad: the desk's square does",
			CeroSecContextMenu.findComputer({ computer:getSquare().__objects[1] }, 0), computer)
		_G.JoypadState.players = {}
	end

	-- The box, against the renderer's own three terms. A box that forgot
	-- offsetX/offsetY sits 64 right and 192 low at tileScale 2, which is the
	-- defect this section was written to kill, so the numbers are asserted
	-- outright.
	do
		local computer = screenshotWorld()
		local x, y, w, h = CeroSecReach.drawnBox(computer)
		eq("box x is the anchor less offsetX", x, 600 - 64)
		eq("box y is the anchor less offsetY and the raise", y, 400 - 192 - 32 * TS)
		eq("box width", w, 64 * TS)
		eq("box height", h, 128 * TS)
		-- The same object with no raise sits exactly the raise lower.
		local flat = place(2088, 5831, 0, CeroSec.SPRITES_OFF.S, 0, MONITOR)
		local fx, fy = CeroSecReach.drawnBox(flat)
		local ax, ay = toScreen(2088, 5831, 0)
		eq("no raise, no lift on x", fx, ax - 64)
		eq("no raise, no lift on y", fy, ay - 192)
	end

	-- The window the candidate squares come out of, as the pure bench derived it
	-- (tests/terminal_test.lua, "which squares can be drawn over a point"). The
	-- two are two statements of one thing, and this is where they are made to
	-- agree.
	do
		eq("PICK_BEHIND", CeroSecReach.PICK_BEHIND, 2)
		eq("PICK_AHEAD", CeroSecReach.PICK_AHEAD, 12)
		eq("PICK_SIDE", CeroSecReach.PICK_SIDE, 1)
	end

	-- Past the game's own staircase. A sprite raised the full SURFACE_MAX whose
	-- pixels are HIGH in its sheet sits ten steps of x+y ahead of the mouse's tile,
	-- and the game's seven candidate steps reach six. No shipped computer sprite
	-- draws that high -- which is exactly why the game does find the monitor on the
	-- desk -- but the window is not allowed to depend on which sprite it is, so the
	-- case is built and asserted.
	do
		squares = {}
		local shelf = place(2089, 5832, 0, "shelves_01_0")
		shelf.__flags.IsTable = true
		shelf.__props.Surface = "64"
		local tall = place(2089, 5832, 0, CeroSec.SPRITES_OFF.S, 64, { 20, 8, 44, 24 })
		local wx, wy = toWorld(600, 110, 0)
		eq("ten steps of x+y ahead of the mouse's tile",
			(2089 + 5832) - (math.floor(wx) + math.floor(wy)), 10)
		eq("still found", CeroSecReach.pickComputer(0, 600, 110, { tall }), tall)
		eq("and still out of reach", CeroSecReach.height(tall), "mid")
	end

	-- The instrumentation. With CeroSec.DEBUG on, one right-click has to leave in
	-- the ring the debug window's Log tab reads: what the game handed over, with
	-- the sprite and the square of it, and every candidate the mask pass weighed
	-- with the answer it got. A line nobody can read is not instrumentation.
	do
		local computer, chair = screenshotWorld()
		_G.getMouseX = function() return 598 end
		_G.getMouseY = function() return 350 end
		local wasDebug, realPrint = CeroSec.DEBUG, _G.print
		CeroSec.DEBUG = true
		_G.print = function() end
		CeroSec.logRing = {}
		eq("with the log on, the answer is the same",
			CeroSecContextMenu.findComputer({ chair }, 0), computer)
		CeroSec.DEBUG, _G.print = wasDebug, realPrint

		local lines = {}
		for _, entry in ipairs(CeroSec.logRing) do lines[#lines + 1] = entry.text end
		local all = table.concat(lines, "\n")
		check("it says what the game handed over",
			string.find(all, "furniture_seating_indoor_02_0@2089,5833,0", 1, true) ~= nil)
		check("it says where the mouse was",
			string.find(all, "mouse 598,350", 1, true) ~= nil)
		check("it says the computer's square and raise",
			string.find(all, "at 2089,5832,0 raise 32", 1, true) ~= nil)
		check("it says the box it tested", string.find(all, "box 536,144 128x256", 1, true) ~= nil)
		check("and whether the mask took it", string.find(all, "HIT", 1, true) ~= nil)
	end

	-- A right-click that finds nothing says so, and says what it weighed on the
	-- way: that is the line a miss in game is read from.
	do
		local _, chair = screenshotWorld()
		_G.getMouseX = function() return 550 end
		_G.getMouseY = function() return 380 end
		local wasDebug, realPrint = CeroSec.DEBUG, _G.print
		CeroSec.DEBUG = true
		_G.print = function() end
		CeroSec.logRing = {}
		eq("nothing found", CeroSecContextMenu.findComputer({ chair }, 0), nil)
		CeroSec.DEBUG, _G.print = wasDebug, realPrint

		local lines = {}
		for _, entry in ipairs(CeroSec.logRing) do lines[#lines + 1] = entry.text end
		local all = table.concat(lines, "\n")
		check("the rejected candidate is named",
			string.find(all, "at 2089,5832,0 raise 32", 1, true) ~= nil)
		check("with the reason", string.find(all, "no mask", 1, true) ~= nil)
		check("and the miss is said outright",
			string.find(all, "no computer under the cursor", 1, true) ~= nil)
	end

	-- The one line that is NOT behind CeroSec.DEBUG: the cursor inside a computer's
	-- own rectangle with its mask saying no. That is the shape of every miss this
	-- section exists for, and a player has to be able to read it off the Log tab
	-- without editing a file and doing it again (docs/DEBUG.md, "The log": the
	-- append is never gated).
	do
		local _, chair = screenshotWorld()
		eq("DEBUG is off for this one", CeroSec.DEBUG, false)
		CeroSec.logRing = {}
		CeroSecReach.grazeWarned = {}
		eq("still nothing found", CeroSecReach.pickComputer(0, 550, 380, { chair }), nil)
		eq("and exactly one line about it", #CeroSec.logRing, 1)
		eq("as a warning, so the Warnings filter finds it",
			CeroSec.logRing[1].level, CeroSec.LOG_WARN)
		check("naming the box and the miss",
			string.find(CeroSec.logRing[1].text,
				"on a computer's box and not on its pixels", 1, true) ~= nil)
		check("and the square", string.find(CeroSec.logRing[1].text, "2089,5832,0", 1, true) ~= nil)

		-- Once per machine, and that is the whole of it. The rectangle is two tiles
		-- wide and four tall, so in an office the desk, the floor in front of it and
		-- the chair are all inside some monitor's box; a line per click would empty
		-- the 200-line ring inside a minute of ordinary play, and a second miss on
		-- the same machine is the same information as the first.
		eq("a second miss on the same machine says nothing more",
			CeroSecReach.pickComputer(0, 551, 381, { chair }), nil)
		eq("still one line", #CeroSec.logRing, 1)

		-- A different machine gets its own line.
		local other = place(2089, 5830, 0, CeroSec.SPRITES_OFF.S, 32, CHAIRBACK)
		square(2089, 5831, 0)
		local ox, oy, ow, oh = CeroSecReach.drawnBox(other)
		local inside = { ox + ow / 2, oy + 1 }
		check("a point inside the other machine's box but off its pixels",
			CeroSec.pointInBox(inside[1], inside[2], ox, oy, ow, oh)
				and CeroSecReach.isMouseOn(other, inside[1], inside[2], 0) == false)
		eq("nothing found on it either",
			CeroSecReach.pickComputer(0, inside[1], inside[2], { other }), nil)
		eq("and now there are two lines", #CeroSec.logRing, 2)

		-- A click nowhere near a computer's rectangle says nothing at all. A warning
		-- that fires when the mod is behaving is a warning nobody reads.
		CeroSec.logRing = {}
		eq("nothing found out in the weeds either",
			CeroSecReach.pickComputer(0, 5, 5, { chair }), nil)
		eq("and not a word about it", #CeroSec.logRing, 0)

		-- And the case that tells "on the box" from "a candidate at all" apart:
		-- 600,420 is a step BELOW the monitor's box and still inside the window the
		-- candidate squares come from, so the computer is weighed and dropped on the
		-- box. That is an ordinary click on the desk, not a miss, and it must be
		-- silent.
		local computer = screenshotWorld()
		local bx, by, bw, bh = CeroSecReach.drawnBox(computer)
		check("600,420 is outside the monitor's box",
			not CeroSec.pointInBox(600, 420, bx, by, bw, bh))
		local weighed = false
		for _, sq in ipairs(CeroSecReach.pickSquares(600, 420, 0, 1)) do
			if sq:getX() == 2089 and sq:getY() == 5832 then weighed = true end
		end
		check("but its square is still weighed", weighed)
		CeroSec.logRing = {}
		eq("nothing found there", CeroSecReach.pickComputer(0, 600, 420, { chair }), nil)
		eq("and still not a word", #CeroSec.logRing, 0)
	end

	-- The box SIZE, against the renderer's rule rather than against a constant. The
	-- renderer draws a 64x128 texture at scale 2 when tileScale is 2 and a 128x256 one
	-- at scale 1, so both come to 128 x 256 -- and anything else keeps the sprite
	-- instance's own scale, whose default is 1. A box hardcoded to 128 x 256 would
	-- give a 32x64 sprite four times the rectangle it draws into, and would divide the
	-- mask index by a scale it was never drawn at.
	do
		squares = {}
		local half = place(2089, 5832, 0, CeroSec.SPRITES_OFF.S, 0, { 0, 0, 31, 63 }, 32, 64)
		local _, _, hw, hh = CeroSecReach.drawnBox(half)
		eq("a 32x64 texture gets a 32x64 box", hw, 32)
		eq("and not a doubled one", hh, 64)

		squares = {}
		local big = place(2089, 5832, 0, CeroSec.SPRITES_OFF.S, 0, { 0, 0, 127, 255 }, 128, 256)
		local _, _, bw, bh = CeroSecReach.drawnBox(big)
		eq("a 128x256 texture is drawn at scale 1", bw, 128)
		eq("so its box is 128x256 too", bh, 256)

		squares = {}
		local std = place(2089, 5832, 0, CeroSec.SPRITES_OFF.S, 0, MONITOR)
		local _, _, sw, sh = CeroSecReach.drawnBox(std)
		eq("and a 64x128 one is doubled to the same", sw, 128)
		eq("the same way", sh, 256)

		-- A texture with no size at all is no box, not a division by zero in the
		-- middle of building a context menu.
		squares = {}
		local empty = place(2089, 5832, 0, CeroSec.SPRITES_OFF.S, 0, MONITOR, 0, 0)
		eq("no size, no box", CeroSecReach.drawnBox(empty), nil)
		eq("no size, no hit", CeroSecReach.isMouseOn(empty, 598, 350, 0), false)
	end

	-- No mouse at all, and an object with no square: neither is an error.
	do
		local computer, chair = screenshotWorld()
		eq("no mouse x, no pick", CeroSecReach.pickComputer(0, nil, 350, { chair }), nil)
		eq("no mouse y, no pick", CeroSecReach.pickComputer(0, 598, nil, { chair }), nil)
		local home = computer.getSquare
		computer.getSquare = function() return nil end
		eq("no square, no box", CeroSecReach.drawnBox(computer), nil)
		eq("no square, no hit", CeroSecReach.isMouseOn(computer, 598, 350, 0), false)
		computer.getSquare = home
	end

	_G.__world = nil
	_G.getCore = realCore
	_G.Core = nil
	_G.ISCoordConversion = nil
	_G.JoypadState = nil
	_G.getMouseX = nil
	_G.getMouseY = nil
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


--
-- 52. What the window may do, and why it may not (the debug rework)
--
-- The window greys a button and prints a reason, and neither answer is its own:
-- both are built here, by the same readings the act itself goes through. The defect
-- this block exists for: "Turn on" was offered on a machine whose chunk was away,
-- the press went out on the wire, turnOn refused for want of a square to ask about
-- the wire, and NOTHING came back -- a button that could not work looked exactly
-- like a button that had.
--

do
	local net = newNet()
	net.login("admin")

	-- The machine in the shed is on and its chunk is away, which is the state
	-- the row reported from play was in but the other way round: switch it off first.
	local away = net.far
	eq("the far machine has no chunk", away:isLoaded(), false)
	eq("switching it off works even so", away:turnOff(), true)

	local why = CeroSecDebug.turnOnRefusal(away)
	check("a machine whose chunk is away cannot be switched on", why ~= nil)
	check("and the reason names the chunk and not the wiring",
		string.find(why, "chunk is away", 1, true) ~= nil)
	check("and it says what to do about it",
		string.find(why, "teleport", 1, true) ~= nil)
	eq("turning it OFF is refused because it is already off",
		CeroSecDebug.turnOffRefusal(away), "it is already off")

	-- The same machine with its chunk in and a wire: no refusal at all. The chunk
	-- coming in is an IsoObject with modData on it, because switching a machine on
	-- mirrors its state into the tile (SCeroSecObject:toModData).
	local tile = { __class = "IsoObject",
		hasModData = function() return true end,
		getModData = function() return {} end,
		transmitModData = function() end }
	away.getIsoObject = function() return tile end
	away.hasPower = function() return true end
	eq("with the chunk in and a wire there is nothing to refuse",
		CeroSecDebug.turnOnRefusal(away), nil)
	-- And with the chunk in and no wire, the OTHER sentence -- which is the
	-- distinction a sweep once got wrong.
	away.hasPower = function() return false end
	eq("a loaded machine with no wire says the wire",
		CeroSecDebug.turnOnRefusal(away), "there is no wire at its square")
	away.hasPower = function() return true end
	eq("and it really does come on", away:turnOn(), true)
	eq("after which it cannot come on again", CeroSecDebug.turnOnRefusal(away),
		"it is already on")
	eq("and turning it off is what is left", CeroSecDebug.turnOffRefusal(away), nil)

	-- Nothing selected is a refusal too, and never an error.
	check("nothing selected cannot be switched on",
		CeroSecDebug.turnOnRefusal(nil) ~= nil)

	-- Every snapshot carries those answers, whatever tab it is for: the buttons
	-- under the list are the same six on every tab.
	local tabs = { "machines", "files", "devices", "network", "scheduler" }
	for i = 1, #tabs do
		local snap = CeroSecDebug.snapshotOf(net.system, tabs[i], net.here)
		eq(tabs[i] .. " says whether the machine can come on", snap.canTurnOn, false)
		eq("and whether it can go off", snap.canTurnOff, true)
		eq("and whether it is on", snap.on, true)
		-- This bench's machines have no IsoObject at all, which is a county nobody
		-- is standing in: loaded is the honest answer and the window greys the
		-- terminal on it.
		eq("and whether its chunk is in", snap.loaded, false)
		eq("with the reason it cannot come on", snap.reason, "it is already on")
	end
end

-- Which machines are worth a row: the flag the window's "used only" filter reads.
do
	local net = newNet()
	-- A computer sprite a chunk brought in and nobody ever touched, which is what
	-- forty-four of the reported rows were. The system makes one for every valid iso
	-- object of every loaded square, so this is not a rare case at all.
	local idle = net.machine(300, 220, 0, net.shed)
	eq("it is off", idle.on, false)
	eq("and it has no disk of its own", idle.os, nil)
	eq("so it has never been used", CeroSecDebug.isUsed(idle), false)
	eq("while a machine that is on has been", CeroSecDebug.isUsed(net.here), true)

	local snap = CeroSecDebug.snapshotOf(net.system, "machines", net.here)
	local idleRow, liveRow = nil, nil
	for i = 1, #snap.rows do
		if snap.rows[i].c[1] == "300,220,0" then idleRow = snap.rows[i] end
		if snap.rows[i].c[1] == "10,10,0" then liveRow = snap.rows[i] end
	end
	check("the untouched one is still on the list", idleRow ~= nil)
	eq("and its row says it has never been used", idleRow.used, false)
	eq("while the live one's says it has", liveRow.used, true)

	-- And a machine switched off after being used stays used: it has a disk.
	net.here:turnOff()
	eq("a machine that has been used stays used once it is off",
		CeroSecDebug.isUsed(net.here), true)
end

-- The refusal on the WIRE, through the real command door.
do
	local net = newNet()
	local away = net.far
	away:turnOff()

	local answers = {}
	net.system.reply = function(_, _, cmd, args)
		answers[#answers + 1] = { cmd = cmd, args = args }
	end

	net.system:OnClientCommand("debugact", net.player,
		{ x = 60, y = 60, z = 0, token = "dbg-0-1", act = "on" })
	eq("the server answered the press", #answers, 1)
	eq("on the same command a snapshot comes on", answers[1].cmd, "debug")
	eq("carrying the window's own token", answers[1].args.token, "dbg-0-1")
	check("with the refusal on it",
		string.find(tostring(answers[1].args.error), "cannot turn on", 1, true) ~= nil)
	check("and the reason in it",
		string.find(tostring(answers[1].args.error), "chunk is away", 1, true) ~= nil)
	eq("and no tab, so no list is emptied by it", answers[1].args.tab, nil)
	eq("the machine is still off", away.on, false)

	-- A press that CAN work answers nothing at all: the snapshot two seconds later
	-- is what says it happened, and a window that had to read a receipt would be a
	-- window that showed one.
	local tile = { __class = "IsoObject",
		hasModData = function() return true end,
		getModData = function() return {} end,
		transmitModData = function() end }
	away.getIsoObject = function() return tile end
	away.hasPower = function() return true end
	answers = {}
	net.system:OnClientCommand("debugact", net.player,
		{ x = 60, y = 60, z = 0, token = "dbg-0-1", act = "on" })
	eq("nothing is answered when it worked", #answers, 0)
	eq("and the machine came on", away.on, true)

	-- Turning off a machine that is already off is refused in the same words.
	away:turnOff()
	answers = {}
	net.system:OnClientCommand("debugact", net.player,
		{ x = 60, y = 60, z = 0, token = "dbg-0-1", act = "off" })
	eq("the press was answered", #answers, 1)
	check("with the refusal",
		string.find(tostring(answers[1].args.error), "already off", 1, true) ~= nil)

	-- And a machine nothing answers to -- which is what 0,0,0 is -- says that.
	answers = {}
	net.system:OnClientCommand("debugact", net.player,
		{ x = 0, y = 0, z = 0, token = "dbg-0-1", act = "on" })
	eq("a triple nothing is at is answered too", #answers, 1)
	check("with what is wrong with it",
		string.find(tostring(answers[1].args.error), "no machine at", 1, true) ~= nil)
end

--
-- THE SELF-TEST, through the real command door
--
-- CeroSecSelfTest.run() is the one bench that runs where the mod does, and this is
-- the bench for the bench: that the vectors pass on lua5.1 at all, that a planted
-- failure is REPORTED rather than swallowed, that the failing lines reach
-- CeroSec.log at warn so the window's Log tab can find them, that the summary
-- comes back on the `debug` answer as a note, and that the save path of the
-- selected machine is walked and not skipped.
--
do
	-- On the canonical VM, where every vector is right by definition. This is not
	-- decoration: the vectors are GENERATED from lua5.1, so a table that does not
	-- pass under lua5.1 is a generator or a body that is broken, and the in-game
	-- run would be red for a reason nothing here could place.
	local result = CeroSecSelfTest.run()
	eq("every vector passes on the VM they were generated from: "
		.. table.concat(result.lines, " / "), result.fail, 0)
	check("and there are vectors (" .. result.pass .. ")", result.pass > 100)
	eq("as many as the table holds", result.pass, #CeroSecSelfTest.VECTORS)

	-- A VECTOR THAT LIES. The whole value of the thing is that it goes red, so it
	-- is made to.
	do
		local kept = CeroSecSelfTest.VECTORS[1].want
		CeroSecSelfTest.VECTORS[1].want = "NOT WHAT THE ENGINE SAYS"
		local hurt = CeroSecSelfTest.run()
		eq("a vector that lies is one failure", hurt.fail, 1)
		eq("and every other one still passes", hurt.pass, result.pass - 1)
		check("and the line names the vector and both values: " .. (hurt.lines[1] or ""),
			string.find(hurt.lines[1] or "", CeroSecSelfTest.VECTORS[1].name, 1, true) ~= nil
				and string.find(hurt.lines[1] or "", "NOT WHAT THE ENGINE SAYS", 1, true) ~= nil)
		CeroSecSelfTest.VECTORS[1].want = kept
	end

	-- A VECTOR NOTHING EVALUATES -- a say() line taken out of the body without the
	-- table being regenerated. Counted as a failure and not skipped, which is the
	-- difference between a stale table and a green one.
	do
		local n = #CeroSecSelfTest.VECTORS
		CeroSecSelfTest.VECTORS[n + 1] =
			{ name = "a line nobody says", want = "anything" }
		local hurt = CeroSecSelfTest.run()
		eq("a vector nothing evaluated is a failure", hurt.fail, 1)
		check("and the line says the body is stale: " .. (hurt.lines[1] or ""),
			string.find(hurt.lines[1] or "", "the body is stale", 1, true) ~= nil)
		CeroSecSelfTest.VECTORS[n + 1] = nil
	end

	-- AND AN ANSWER WITH NO VECTOR, which is the same drift read the other way: a
	-- line added to the body and the table not regenerated.
	do
		local kept = CeroSecSelfTest.VECTORS[1]
		table.remove(CeroSecSelfTest.VECTORS, 1)
		local hurt = CeroSecSelfTest.run()
		eq("an answer with no vector is a failure", hurt.fail, 1)
		check("and the line says the table is stale: " .. (hurt.lines[1] or ""),
			string.find(hurt.lines[1] or "", "the table is stale", 1, true) ~= nil)
		table.insert(CeroSecSelfTest.VECTORS, 1, kept)
	end

	-- NO VECTORS AT ALL is a failure and never a pass of nothing, which is how the
	-- whole button would have gone quietly green on a build that shipped without
	-- the generated file.
	do
		local kept = CeroSecSelfTest.VECTORS
		CeroSecSelfTest.VECTORS = {}
		local none = CeroSecSelfTest.run()
		eq("an empty table is a failure", none.fail, 1)
		eq("and no passes", none.pass, 0)
		check("and it says what to run: " .. (none.lines[1] or ""),
			string.find(none.lines[1] or "", "make-selftest-vectors", 1, true) ~= nil)
		CeroSecSelfTest.VECTORS = kept
	end
end

-- The save path, which is the half no offline bench can be asked.
do
	local net = newNet()
	local machine = net.here

	-- A machine with no sprite in the world has nothing to mirror into, and the
	-- self-test says so rather than passing over it -- which is the case a
	-- developer meets first, the debug window listing every computer in the county
	-- and most of their chunks being away.
	do
		local out = CeroSecSelfTest.runSave(machine)
		eq("a machine whose chunk is away is a failure and not a skip", out.fail, 1)
		check("and it says which, in the window's own words: " .. (out.lines[1] or ""),
			string.find(out.lines[1] or "", "chunk is away", 1, true) ~= nil)
		check("and it says what to do about it: " .. (out.lines[1] or ""),
			string.find(out.lines[1] or "", "teleport to it", 1, true) ~= nil)
		eq("and nothing else was asked, there being nothing to ask", out.pass, 0)
	end

	-- And with one. The fake keeps its modData table across calls, which is what an
	-- IsoObject does and what makes the round trip a round trip at all.
	--
	-- The announcement stateToIsoObject ends in is the game's base class's and is
	-- stubbed here the way the two benches further down stub it: what is being
	-- walked is the mirror, not who is told about it.
	net.system.newLuaObjectOnClient = function() end
	local data = {}
	local tile = { __class = "IsoObject",
		hasModData = function() return true end,
		getModData = function() return data end,
		transmitModData = function() end,
		getSpriteName = function() return CeroSec.SPRITES_ON["S"] end }
	machine.getIsoObject = function() return tile end

	local out = CeroSecSelfTest.runSave(machine)
	eq("the save path comes back clean: " .. table.concat(out.lines, " / "), out.fail, 0)
	check("and it asked more than one thing (" .. out.pass .. ")", out.pass >= 6)
	check("and the mirror really is in the object's own modData",
		type(data.movableData) == "table"
			and type(data.movableData[CeroSec.MOVABLE_DATA_KEY]) == "table")

	-- A MIRROR MISSING A FIELD, which is the failure these vectors exist for: `os`
	-- is validated by the boot gate on every read, and `v`, `on` and `facing` are
	-- weighed by nothing at all -- so dropping `facing` is a computer that comes
	-- back from being carried facing the wrong way, and a green suite.
	--
	-- The mutation is a dropped field and NOT a function planted in the state,
	-- which was the first draft and does not work: osState runs validate, validate
	-- refuses a function, and the round trip never sees it. That is worth knowing
	-- rather than hiding -- it is the proof that validate's rule and the
	-- serializer's rule are the same rule -- and it is written down over
	-- CeroSecSelfTest.runSave.
	do
		local kept = machine.toModData
		machine.toModData = function(self, isoObject)
			local modData = isoObject:getModData()
			if not modData.movableData then modData.movableData = {} end
			modData.movableData[CeroSec.MOVABLE_DATA_KEY] = {
				v = self.v, on = self.on, os = self.os,
			}
		end
		local hurt = CeroSecSelfTest.runSave(machine)
		check("a mirror missing a field is reported (" ..
			table.concat(hurt.lines, " / ") .. ")", hurt.fail > 0)
		check("and the line names the fields it wanted",
			string.find(table.concat(hurt.lines, " "), "facing on os v", 1, true) ~= nil)
		machine.toModData = kept
		eq("and it is clean again with the real mirror",
			CeroSecSelfTest.runSave(machine).fail, 0)
	end

	-- AND A MIRROR THAT IS NOT THERE, which is the key being renamed or the write
	-- being dropped: every computer carried across town comes back blank.
	do
		local kept = machine.toModData
		machine.toModData = function() end
		local blank = {}
		machine.getIsoObject = function()
			return { __class = "IsoObject",
				hasModData = function() return true end,
				getModData = function() return blank end,
				transmitModData = function() end,
				getSpriteName = function() return CeroSec.SPRITES_ON["S"] end }
		end
		local hurt = CeroSecSelfTest.runSave(machine)
		check("a mirror that was never written is reported (" ..
			table.concat(hurt.lines, " / ") .. ")", hurt.fail > 0)
		machine.toModData = kept
		machine.getIsoObject = function()
			return { __class = "IsoObject",
				hasModData = function() return true end,
				getModData = function() return data end,
				transmitModData = function() end,
				getSpriteName = function() return CeroSec.SPRITES_ON["S"] end }
		end
		eq("and clean again", CeroSecSelfTest.runSave(machine).fail, 0)
	end

	-- Both halves added up, which is what the button runs.
	local all = CeroSecSelfTest.runAll(machine)
	eq("runAll adds the two up: " .. table.concat(all.lines, " / "), all.fail, 0)
	check("and counts both", all.pass > CeroSecSelfTest.run().pass)
	eq("and the summary is one line", CeroSecSelfTest.summary(all),
		"selftest: PASS " .. all.pass .. " FAIL 0")
end

-- `debugact selftest` and `debugact givedisk`, on the wire.
do
	local net = newNet()
	local machine = net.here
	net.system.newLuaObjectOnClient = function() end
	local data = {}
	machine.getIsoObject = function()
		return { __class = "IsoObject",
			hasModData = function() return true end,
			getModData = function() return data end,
			transmitModData = function() end,
			getSpriteName = function() return CeroSec.SPRITES_ON["S"] end }
	end

	local answers = {}
	net.system.reply = function(_, _, cmd, args)
		answers[#answers + 1] = { cmd = cmd, args = args }
	end

	-- A clean run: the verdict comes back as a NOTE and not as an error, on the
	-- `debug` answer, with no tab -- so the window puts it on the line under the
	-- list and empties no list for it.
	--
	-- `print` is caught, because the verdict going to the GAME LOG is a requirement
	-- and not a nicety: the log ring is two hundred lines and dies with the session,
	-- and RELEASE.md's step 6a says to paste the summary into the release notes --
	-- which means it has to be somewhere a release can be pasted FROM, and that is
	-- console.txt on a client and the server's own log on a dedicated one. Without
	-- this the line could be deleted and every other assertion here would stay green.
	CeroSec.logRing = {}
	local printed = {}
	local realPrint = print
	_G.print = function(text) printed[#printed + 1] = tostring(text) end
	net.system:OnClientCommand("debugact", net.player,
		{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "selftest" })
	_G.print = realPrint
	do
		local said = nil
		for i = 1, #printed do
			if string.find(printed[i], "FAIL 0", 1, true) ~= nil then said = printed[i] end
		end
		check("the verdict goes to the game log through print: "
			.. table.concat(printed, " / "), said ~= nil)
		check("named so a reader knows whose it is: " .. tostring(said),
			said ~= nil and string.find(said, "CeroSec", 1, true) ~= nil)
	end
	eq("the server answered the press", #answers, 1)
	eq("on the same command a snapshot comes on", answers[1].cmd, "debug")
	eq("carrying the window's own token", answers[1].args.token, "dbg-0-1")
	eq("and no tab, so no list is emptied by it", answers[1].args.tab, nil)
	eq("a clean run is not an error", answers[1].args.error, nil)
	check("and the verdict is on the note: " .. tostring(answers[1].args.note),
		string.find(tostring(answers[1].args.note), "FAIL 0", 1, true) ~= nil)

	-- The log, which is what the window's Log tab draws. The summary at info,
	-- whatever happened, because a run that said nothing when it passed is a run
	-- nobody can tell from a button that did not work.
	do
		local infos, warns = 0, 0
		local summary = nil
		for i = 1, #CeroSec.logRing do
			local line = CeroSec.logRing[i]
			if line.level == CeroSec.LOG_INFO then
				infos = infos + 1
				if string.find(line.text, "PASS", 1, true) ~= nil then summary = line.text end
			elseif line.level == CeroSec.LOG_WARN then
				warns = warns + 1
			end
		end
		eq("a clean run logs no warnings", warns, 0)
		check("and logs the summary at info: " .. tostring(summary), summary ~= nil)
	end

	-- A PLANTED FAILING VECTOR: the line has to reach CeroSec.log at WARN, which is
	-- the level the Log tab's own filter button reads, and the note has to send the
	-- reader there.
	do
		local kept = CeroSecSelfTest.VECTORS[2].want
		CeroSecSelfTest.VECTORS[2].want = "A LIE"
		CeroSec.logRing = {}
		answers = {}
		net.system:OnClientCommand("debugact", net.player,
			{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "selftest" })
		check("the verdict says one failed: " .. tostring(answers[1].args.note),
			string.find(tostring(answers[1].args.note), "FAIL 1", 1, true) ~= nil)
		check("and sends the reader to the Log tab",
			string.find(tostring(answers[1].args.note), "Log tab", 1, true) ~= nil)
		local warned = nil
		for i = 1, #CeroSec.logRing do
			if CeroSec.logRing[i].level == CeroSec.LOG_WARN then
				warned = CeroSec.logRing[i].text
			end
		end
		check("and the failing line is in the log at warn: " .. tostring(warned),
			warned ~= nil and string.find(warned, "A LIE", 1, true) ~= nil)
		CeroSecSelfTest.VECTORS[2].want = kept
	end

	-- THE DISK, into his hands, the way the drive hands one over: an item of one of
	-- our four types, the catalogue written into its modData, the sticker on the
	-- shell, and the container told.
	do
		local inv = newInventory()
		net.player.getInventory = function() return inv end
		answers = {}
		-- With NOTHING selected, which is what 0,0,0 is: it is about his bag and not
		-- about a machine, and a button that needed a row clicked first would be a
		-- button nobody finds the use of.
		net.system:OnClientCommand("debugact", net.player,
			{ x = 0, y = 0, z = 0, token = "dbg-0-1", act = "givedisk" })
		eq("a disk is handed over with no machine selected", #inv.items, 1)
		local item = inv.items[1]
		check("it is one of our floppy items", CeroSec.isFloppyType(item:getFullType()))
		eq("with the sticker on the shell", item:getName(), "CeroSec DIAGNOSTICS 1.0")
		check("and the custom name flag set, so the game keeps it",
			item:isCustomName())
		check("and the fields synced", item.synced > 0)
		-- And what is written on it is a disk the slot would take, with the suite on
		-- it: read back through the engine's own reader and not out of the fake.
		local disk = CeroSecOS.diskFromData(item:getModData())
		check("the modData carries a disk", type(disk) == "table")
		check("which the slot would take", CeroSecOS.validateDisk(disk, true))
		check("with selftest.sh on it",
			type(disk.fs) == "table" and type(disk.fs.children) == "table"
				and disk.fs.children["selftest.sh"] ~= nil)
		check("and the receipt is a note and not an error: "
			.. tostring(answers[1] and answers[1].args.note),
			answers[1] ~= nil and type(answers[1].args.note) == "string"
				and answers[1].args.error == nil)

		-- A bag that will not take it: nothing happens, and the reason is on the
		-- glass rather than a disk that half arrived.
		inv.AddItem = function() return nil end
		answers = {}
		net.system:OnClientCommand("debugact", net.player,
			{ x = 0, y = 0, z = 0, token = "dbg-0-1", act = "givedisk" })
		eq("a bag that is full gets no second disk", #inv.items, 1)
		check("and is told why: " .. tostring(answers[1] and answers[1].args.error),
			answers[1] ~= nil
				and string.find(tostring(answers[1].args.error), "carrying too much",
					1, true) ~= nil)
	end

	-- AND BOTH ARE BEHIND THE SAME DOOR as the rest of the window. A client is not
	-- to be trusted about whether it was allowed to ask.
	do
		local was = CeroSec.DEV_DEBUG_MENU
		CeroSec.DEV_DEBUG_MENU = false
		local inv = newInventory()
		net.player.getInventory = function() return inv end
		answers = {}
		net.system:OnClientCommand("debugact", net.player,
			{ x = 0, y = 0, z = 0, token = "dbg-0-1", act = "givedisk" })
		net.system:OnClientCommand("debugact", net.player,
			{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "selftest" })
		eq("a forged givedisk on a released build hands nothing over", #inv.items, 0)
		eq("and a forged selftest answers nothing", #answers, 0)
		CeroSec.DEV_DEBUG_MENU = was
	end
end

--
-- The pager, driven the way a player drives it (fidelity A)
--
-- `more` asks a question, and a question on this machine is a console PROMPT: the
-- window draws it, the player types at it, and the answer goes back through the
-- same door a password goes through. Every other bench for `more` calls the
-- engine; this one presses the keys.
--
-- Which is the bench that matters, because the pager's three keys are a shape
-- nothing else on the machine has: Space and Return and q, read off a line rather
-- than off a keystroke, at a prompt the window has to be told to draw.
--
do
	local bench = newBench()
	bench.login("admin")

	local body = {}
	for i = 1, 45 do body[#body + 1] = "row " .. i end
	bench.script("/home/admin/long", table.concat(body, "\n"))

	bench.enter("more long")
	bench.frame()
	-- The prompt is on the glass, in more(1)'s own words, and the window is in
	-- the mode that draws one.
	eq("more's question reached the window", bench.window.prompt, "--More--(42%)")
	eq("the window is at a prompt", bench.window.mode, "prompt")
	eq("and nothing is masked about it", bench.window.mask, false)
	eq("the machine holds the question", bench.object.console.prompt.text, "--More--(42%)")
	check("the first screenful is painted", bench.painted("row 1"))
	check("all nineteen rows of it", bench.painted("row 19"))
	check("and not the twentieth", not bench.painted("row 20"))

	-- Space, then Enter: the next screenful. Which is the console's own shape and
	-- not more's -- there is one input line here and Enter is what sends it -- and
	-- it is the same shape `read -n 1` already has.
	bench.enter(" ")
	bench.frame()
	check("the next screenful came", bench.painted("row 20"))
	eq("and it asks again, further on", bench.window.prompt, "--More--(84%)")

	-- A bare Enter: exactly one more line.
	bench.enter("")
	bench.frame()
	check("one line further", bench.painted("row 39"))
	eq("and the per cent moved by one line's worth", bench.window.prompt, "--More--(86%)")

	-- q: the pager stops, the question comes off the machine, and the shell is
	-- back with its own prompt.
	bench.enter("q")
	bench.frame()
	eq("q took the question off the machine", bench.object.console.prompt, nil)
	eq("and the window is at the shell again", bench.window.mode, "shell")
	check("with the shell's prompt on the glass", bench.painted("admin@"))
	check("and nothing past where it stopped", not bench.painted("row 40"))

	-- Escape at a --More-- is a ^C like anywhere else: the pager is a job and
	-- Escape is this machine's interrupt.
	bench.enter("more long")
	bench.frame()
	eq("it asks again", bench.window.prompt, "--More--(42%)")
	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	check("the window is still open", not bench.window.closing)
	check("the interrupted prompt is on the glass", bench.painted("--More--(42%)^C"))
	eq("the question is off the machine", bench.object.console.prompt, nil)
	eq("and the shell is back", bench.window.mode, "shell")

	-- And down a pipe, which is how a survivor reads a long listing. The question
	-- belongs to the PIPELINE and the answer has to find its way back to the stage
	-- that asked it, which is the one thing about `more` the console cannot see.
	bench.enter("cat long | more")
	-- A pipeline takes a pass or two: the stage on the right runs before the one
	-- on its left has written anything, which is what makes the back-pressure fall
	-- out, and the pager only asks once its input has ended.
	bench.tick(3)
	eq("the last stage of a pipeline asks too", bench.window.prompt, "--More--(42%)")
	check("and its screenful is on the glass", bench.painted("row 1"))
	bench.enter("q")
	bench.frame()
	eq("and q ends the pipeline", bench.object.console.prompt, nil)
	eq("the shell is back", bench.window.mode, "shell")

	-- A file that fits asks nothing at all: no prompt, no mode change, straight
	-- back to the shell.
	bench.script("/home/admin/short", "one\ntwo")
	bench.enter("more short")
	bench.frame()
	eq("a short file asks nothing", bench.object.console.prompt, nil)
	eq("and the window never left the shell", bench.window.mode, "shell")
	check("both lines are on the glass", bench.painted("one") and bench.painted("two"))
end

--
-- WHAT IS ALREADY ON A MACHINE NOBODY HAS SWITCHED ON
--
-- The world half of the world-content work. What each profile PUTS on a machine is
-- tests/content_test.lua's -- it builds every one of them and runs every script --
-- and this is the other half, which only the world can answer:
--
--   * the profile comes off the PREMISES the machine stands in, by the same rule
--     the telephone line does;
--   * it happens at the FIRST power-on and at no other moment, and never to a
--     machine that already had a state;
--   * the option off is the bare machine this mod shipped with.
--
-- The option is ON for this section and put back afterwards, which is the shape
-- the hardware sections use.
--
do
	local net = newNet()
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = true } }
	-- The map back: a section above took getWorld away to prove what a machine with
	-- no chunk says, and a premises is a question about zones.
	_G.getWorld = zonedWorld
	-- A shop inside the office building, strictly smaller than its footprint, which
	-- is what makes it a premises at all.
	_G.__zones = { { name = "FrontOffice", x = 8, y = 8, w = 6, h = 6 } }

	-- net.here stands at 10,10 inside that zone. It has never been switched on in
	-- this bench, so this call is its first.
	local machine = net.machine(10, 10, 0, net.office)
	check("the machine starts with no state at all", machine.os == nil)
	machine:turnOn()
	local state = machine:osState()
	check("and switching it on gives it one", state ~= nil)

	-- The office profile: more accounts than the two a bare machine ships with, and
	-- root is no longer open.
	local users, order = CeroSecOS.readUsers(state)
	check("a machine in an office comes up with people on it (" .. #order .. ")",
		#order > 2)
	check("and root is not open any more",
		not CeroSecOS.checkPassword(users.root, ""))
	-- AND THE FACTORY ACCOUNT IS OFF IT, through the real power-on and not only in the
	-- catalogue's own bench: it is the one way into a machine that needs nothing found,
	-- so root's hashed password is worth nothing while it is there.
	eq("the factory account is gone",
		CeroSecOS.getUser(state, CeroSecOS.FACTORY_USER), nil)
	eq("and it cannot sudo any more",
		CeroSecOS.sudoer(state, CeroSecOS.FACTORY_USER), nil)
	eq("and its home went with it",
		CeroSecOS.systemNode(state, CeroSecOS.FACTORY_HOME), nil)
	check("its name says which premises it is", state.hostname ~= "ksp-7t-jc"
		and string.find(state.hostname, "^acct%-") ~= nil)
	eq("and /etc/hostname agrees with it",
		CeroSecOS.systemNode(state, CeroSecOS.HOSTNAME_PATH).data, state.hostname)
	check("the premises name is on the record",
		CeroSecOS.premisesName(state) == "FrontOffice")
	check("there is a week of log on it",
		CeroSecOS.systemNode(state, CeroSecOS.LOG_PATH .. "/messages") ~= nil)
	check("and the machine boots", (CeroSecOS.validate(state)))

	-- THE PASSWORD A PLAYER WILL FIND. Derived from the premises and the save's own
	-- secret, by the same two calls the paper in the drawer makes -- so this is the
	-- assertion that the note and the machine agree, made on a real machine in a
	-- real building.
	local b1, b2 = CeroSecNet.premisesOf(machine)
	local note = CeroSecContent.password(net.system:secret(),
		CeroSecContent.rootKey(b1, b2))
	check("the password on the paper logs root in",
		CeroSecOS.checkPassword(CeroSecOS.readUsers(state).root, note))

	-- AND IT HAPPENS ONCE. Switching the machine off and on again is not a second
	-- first boot: the accounts, the files and the hostname are the ones already
	-- there.
	local before = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data
	machine:turnOff()
	machine:turnOn()
	eq("switching it off and on again does not prefill it twice",
		CeroSecOS.systemNode(machine:osState(), CeroSecOS.PASSWD_PATH).data, before)

	-- A MACHINE SOMEBODY HAS ALREADY USED, which is what every computer in an
	-- existing save is: a state is put on it by hand -- an old machine, two open
	-- accounts, a file of somebody's -- and it comes up untouched.
	do
		local old = net.machine(11, 10, 0, net.office)
		old.os = CeroSecOS.newState("ksp-b-a")
		CeroSecOS.writeFile(old.os, CeroSecOS.rootSession(), "/home/admin/mine.txt",
			"my work", false, nil)
		local was = CeroSecOS.systemNode(old.os, CeroSecOS.PASSWD_PATH).data
		old:turnOn()
		local now = old:osState()
		eq("an existing machine keeps its accounts",
			CeroSecOS.systemNode(now, CeroSecOS.PASSWD_PATH).data, was)
		eq("and its hostname", now.hostname, "ksp-b-a")
		check("and the file somebody wrote on it",
			CeroSecOS.systemNode(now, "/home/admin/mine.txt") ~= nil)
		check("and root is still open", CeroSecOS.checkPassword(
			CeroSecOS.readUsers(now).root, ""))
	end

	-- A MACHINE IN NO BUILDING AT ALL, which is a player-built base: bare, exactly
	-- as it has no address and no telephone line.
	do
		local outside = net.machine(5000, 5000, 0, nil)
		outside:turnOn()
		local bare = outside:osState()
		local _, ord = CeroSecOS.readUsers(bare)
		eq("a machine in no building comes up bare", #ord, 2)
		check("with root open", CeroSecOS.checkPassword(
			CeroSecOS.readUsers(bare).root, ""))
	end

	-- A MACHINE SOMEBODY NEVER LOGGED OUT OF (wave 7c)
	--
	-- One machine in four, and the catalogue's half of it -- the wtmp record with no
	-- logout behind it, the history that does not end on a shutdown -- is
	-- tests/content_test.lua's. THIS is the half only the world can answer: that the
	-- console the power-on made really comes up at that man's prompt, with no
	-- password asked, and that the machine is otherwise an ordinary prefilled one.
	--
	-- Which square is a SEARCH and not a number: the roll is one in four and it is
	-- keyed on the machine, so the bench walks the county until it finds a desk that
	-- was left logged in. The walk is bounded, and not finding one is a red.
	--
	-- ONE MACHINE PER OFFICE, and that is not tidiness: an office has three people
	-- in it, so the fourth machine of ONE premises is a SPARE DESK, and nobody was
	-- ever logged in at a spare desk (CeroSecContent.deskRole). Twenty-five machines
	-- inside the FrontOffice zone are one premises -- three desks and twenty-two
	-- spares -- so the walk would have three rolls to find a live session among, and
	-- a one-in-four roll missing three times is a red for no fault.
	--
	-- So each machine gets an office of its OWN: its own building, away from the
	-- zone, with an office room in it so the profile is still the office's.
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = true } }
		local found, state, login = nil, nil, nil
		for n = 1, 25 do
			if found == nil then
				local bx, by = 2000 + n * 20, 3000
				local one = net.machine(bx + 2, by + 2, 0,
					net.buildingAt(bx, by, 10, 10, 1, { "office" }))
				one:turnOn()
				local console = one:consoleState()
				if type(console) == "table" and type(console.user) == "string" then
					found, state, login = one, one:osState(), console.user
				end
			end
		end
		check("some desk in an office was left logged in", found ~= nil)
		if found ~= nil then
			local console = found:consoleState()
			-- What the WINDOW is told, which is the thing a player meets: a shell and
			-- not a login prompt, and nothing masked.
			eq("and the console is at a shell", CeroSec.consoleWaiting(console), "shell")
			eq("so the window types commands and not answers",
				CeroSec.consoleMode(console), "shell")
			check("and nothing on it is masked", not CeroSec.consoleMask(console))
			-- His own home, his own environment: a session restored without those is a
			-- prompt in the wrong directory with no PATH on it.
			local user = CeroSecOS.getUser(state, login)
			check("the account is really on the machine", user ~= nil)
			eq("and the prompt is standing in his home", console.cwd, user.home)
			check("with the environment a login hands a shell",
				type(console.shvars) == "table" and console.shvars.PATH ~= nil
					and console.shvars.HOME == user.home)
			check("and when he sat down", type(console.loginAt) == "number")
			-- THE BIOS STILL PRINTS. `booted` is deliberately left alone, so the first
			-- window on this machine sees the firmware and the banner above the prompt
			-- rather than a bare prompt on a blank screen.
			check("the machine has not been booted onto a screen yet", not console.booted)
			-- And `last` says the same thing the console does, which is the pair this
			-- wave is built on.
			local wtmp = CeroSecOS.systemNode(state, CeroSecOS.WTMP_PATH)
			check("there are login records on it", wtmp ~= nil)
			local recs = CeroSecOS.parseWtmp(wtmp.data or "")
			check("and the newest is his, with no logout behind it",
				#recs > 0 and recs[#recs].kind == "in" and recs[#recs].user == login)
			eq("and the console agrees with it about when", console.loginAt,
				recs[#recs].at)
			-- His history is there and does not end on a halt.
			local hist = CeroSecOS.systemNode(state,
				user.home .. "/" .. CeroSecOS.HISTORY_NAME)
			check("his history is on the disk", hist ~= nil)
			local lines = CeroSecOS.splitLines(hist.data or "")
			check("and it does not end on a shutdown (" .. tostring(lines[#lines]) .. ")",
				lines[#lines] ~= CeroSecContent.HIST_HALT)
			check("and the machine boots", (CeroSecOS.validate(state)))
		end
	end

	-- THE OPTION OFF, which is the control and is the world this mod shipped with.
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
		local plain = net.machine(12, 10, 0, net.office)
		plain:turnOn()
		local bare = plain:osState()
		local _, ord = CeroSecOS.readUsers(bare)
		eq("with the option off a machine comes up with two accounts", #ord, 2)
		check("root open", CeroSecOS.checkPassword(CeroSecOS.readUsers(bare).root, ""))
		-- AND THE FACTORY ACCOUNT IS STILL THERE, open, which is the other half of the
		-- rule a prefilled machine follows: the account describes a machine nobody ever
		-- set up, and with the option off that is every machine in the county.
		local factory = CeroSecOS.getUser(bare, CeroSecOS.FACTORY_USER)
		check("the factory account is on it", factory ~= nil)
		check("and open", CeroSecOS.checkPassword(factory, ""))
		check("and may still sudo",
			CeroSecOS.sudoer(bare, CeroSecOS.FACTORY_USER) ~= nil)
		eq("and the name the coordinates give it", bare.hostname,
			CeroSec.hostnameFor(12, 10))
		eq("and no log", CeroSecOS.systemNode(bare, CeroSecOS.LOG_PATH .. "/messages"),
			nil)
	end

	-- THE SHOP THAT SELLS COMPUTERS, on the wire
	--
	-- The catalogue's half of this -- what a display model is, and that five of them
	-- and one back-room machine come out one desk and five models -- is
	-- tests/content_test.lua section 4h. THIS is the half only the world can answer:
	-- that the room the machine stands in really reaches the catalogue. The wire is
	-- the whole risk here, because a square that answered no room at all would leave
	-- every bench in section 4h green while putting the shop's ledger on a machine
	-- the public types at.
	do
		_G.__zones = {}
		_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = true } }
		local shop = net.buildingAt(5000, 6000, 20, 20, 2,
			{ "electronicsstore", "electronicsstorage" })
		local model = net.machine(5005, 6005, 0, shop, "electronicsstore")
		model:turnOn()
		local onFloor = model:osState()
		eq("a machine on the shop floor comes up on the dealer's disk",
			string.match(onFloor.hostname, "^[a-z0-9]+"), CeroSecContent.DEMO.host)
		local demo = CeroSecOS.getUser(onFloor, CeroSecContent.DEMO.login)
		check("with the demo account waiting", demo ~= nil)
		check("and open", CeroSecOS.checkPassword(demo, ""))
		eq("and the dealer's card on it",
			CeroSecOS.systemNode(onFloor, CeroSecOS.MOTD_PATH).data,
			CeroSecContent.DEMO.motd)
		local _, ord = CeroSecOS.readUsers(onFloor)
		-- root and demo, and nobody else: not the shop's people, because it is stock --
		-- and not the factory `admin` either, because this is a machine somebody set up
		-- and a prefilled machine gives that account up (CeroSecContent.prefill).
		eq("and the shop's people are not on stock (" .. table.concat(ord, " ") .. ")",
			#ord, 2)
		eq("nor is the factory account", CeroSecOS.getUser(onFloor,
			CeroSecOS.FACTORY_USER), nil)

		local back = net.machine(5006, 6006, 0, shop, "electronicsstorage")
		back:turnOn()
		local inBack = back:osState()
		eq("and the machine in the back room is the shop's own",
			string.match(inBack.hostname, "^[a-z0-9]+"),
			CeroSecContent.PROFILES.showroom.host)
		local _, backOrd = CeroSecOS.readUsers(inBack)
		-- root and the showroom's two people: more than the demo image's two, and the
		-- factory account is not among them on this machine either.
		check("with the shop's people on it (" .. table.concat(backOrd, " ") .. ")",
			#backOrd > 2)
		eq("and not the factory account",
			CeroSecOS.getUser(inBack, CeroSecOS.FACTORY_USER), nil)

		-- AND THE PAPER IN THE BACK-ROOM DRAWER OPENS BOTH OF THEM, which is the
		-- reason a display model keeps the premises' root and not a factory password:
		-- one note, one premises, every machine of it.
		local b1, b2 = CeroSecNet.premisesOf(model)
		check("the shop is a premises", b1 ~= nil)
		local paper = CeroSecContent.password(net.system:secret(),
			CeroSecContent.rootKey(b1, b2))
		check("the drawer's paper opens the display model",
			CeroSecOS.checkPassword(CeroSecOS.getUser(onFloor, "root"), paper))
		check("and the shop's own machine",
			CeroSecOS.checkPassword(CeroSecOS.getUser(inBack, "root"), paper))

		-- AND THE REGISTER IS ON THE SYSTEM, which is where the save will take it.
		local page = CeroSecContent.deskEntry(net.system.desks, b1, b2)
		check("the shop has a page in the register", type(page) == "table")
		local desks, models = 0, 0
		for _, v in pairs(page.desks) do
			if type(v) == "number" then desks = desks + 1 end
			if v == CeroSecContent.DESK_FLOOR then models = models + 1 end
		end
		eq("holding the one desk", desks, 1)
		eq("and the one display model", models, 1)
		-- AND IT IS A SHAPE THE SAVE CAN WRITE. gos_cerosec.bin is KahluaTable.save
		-- walking the system's modData, which carries strings, numbers and tables and
		-- nothing else -- so a register that held a machine object, or a key that was
		-- not a string, would be a save that does not come back. The page is walked
		-- rather than the declaration read: this is the table that really got written.
		for tag, v in pairs(page.desks) do
			eq("the register's key is a string (" .. tostring(tag) .. ")", type(tag),
				"string")
			check("and its value is a slot or a word (" .. tostring(v) .. ")",
				type(v) == "number" or v == CeroSecContent.DESK_FLOOR
					or v == CeroSecContent.DESK_SPARE)
		end
	end
	_G.__zones = {}
	_G.getWorld = nil
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
end

--
-- THE PAPERS A PASSWORD IS FOUND ON
--
-- The other half of the same change: the note in the drawer and the note in a dead
-- man's pocket, both fired through the engine's own event with the engine's own
-- three arguments (Events.OnFillContainer, LootLog.lua:7).
--
-- The one thing every assertion in here is really about: the paper and the machine
-- AGREE. They never talk to each other -- both derive the password out of the
-- save's secret and the premises -- so the note is written here, the machine is
-- switched on afterwards, and the password off the paper is typed at it.
--
do
	local net = newNet()
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = true } }
	_G.getWorld = zonedWorld
	_G.__zones = { { name = "FrontOffice", x = 8, y = 8, w = 6, h = 6 } }
	-- The handler reaches the system the way every server-wide hook in this mod
	-- does: through the class's own instance, which vanilla's RegisterSystemClass
	-- sets and this bench sets by hand.
	local hadInstance = SCeroSecSystem.instance
	SCeroSecSystem.instance = net.system

	-- A container the game is filling: the three things the handler touches, and
	-- nothing else. AddItem answers an item the way ItemContainer.AddItem(String)
	-- does -- javap: it answers the InventoryItem, or null.
	local function newContainer(square, full)
		local box = { items = {} }
		box.getSourceGrid = function() return square end
		box.AddItem = function(_, fullType)
			if full then return nil end
			local item = { type = fullType, name = nil, custom = false, synced = 0 }
			item.getFullType = function() return item.type end
			item.setName = function(_, text) item.name = text end
			item.getName = function() return item.name end
			item.setCustomName = function(_, flag) item.custom = flag end
			item.isCustomName = function() return item.custom end
			item.syncItemFields = function() item.synced = item.synced + 1 end
			box.items[#box.items + 1] = item
			return item
		end
		return box
	end

	local inside = net.machine(10, 10, 0, net.office):getSquare()
	local street = net.machine(5000, 5000, 0, nil):getSquare()

	-- A DRAWER IN THE OFFICE.
	local desk = newContainer(inside)
	Events.OnFillContainer.trigger("office", "desk", desk)
	eq("a desk in an office gets one paper", #desk.items, 1)
	local note = desk.items[1]
	eq("and it is the note item", note:getFullType(), CeroSecNotes.ITEM)
	check("with the password written on its name (" .. tostring(note:getName()) .. ")",
		string.find(note:getName(), "^Sticky note: root / %w+$") ~= nil)
	check("and the name is a custom one, or the translated name would win",
		note:isCustomName())
	eq("and it was sent", note.synced, 1)

	-- ONE PER PREMISES. Every other drawer in that office is empty.
	local second = newContainer(inside)
	Events.OnFillContainer.trigger("office", "desk", second)
	eq("the second drawer of the same office has none", #second.items, 0)
	local cabinet = newContainer(inside)
	Events.OnFillContainer.trigger("office", "filingcabinet", cabinet)
	eq("nor the filing cabinet", #cabinet.items, 0)

	-- AND THE MACHINE AGREES WITH IT. Switched on AFTER the paper was written,
	-- which is the order a survivor meets them in.
	local machine = net.machine(11, 11, 0, net.office)
	machine:turnOn()
	local typed = string.match(note:getName(), "/ (%w+)$")
	check("the password off the paper logs root in at the machine",
		CeroSecOS.checkPassword(CeroSecOS.readUsers(machine:osState()).root, typed))

	-- NOTHING OUTSIDE A BUILDING.
	do
		local outdoors = newContainer(street)
		Events.OnFillContainer.trigger("", "counter", outdoors)
		eq("a counter in no building gets nothing", #outdoors.items, 0)
	end

	-- AND NOT IN A FRIDGE. A password goes in the drawer you open every morning.
	do
		local net2 = newNet()
		SCeroSecSystem.instance = net2.system
		local sq = net2.machine(10, 10, 0, net2.office):getSquare()
		local fridge = newContainer(sq)
		Events.OnFillContainer.trigger("office", "fridge", fridge)
		eq("a fridge in the same office gets nothing", #fridge.items, 0)
		-- And the premises is NOT marked by the fridge: the desk still gets its note.
		local drawer = newContainer(sq)
		Events.OnFillContainer.trigger("office", "desk", drawer)
		eq("while the desk beside it still gets one", #drawer.items, 1)
		SCeroSecSystem.instance = net.system
	end

	-- A DRAWER THE GAME COULD NOT PUT ANYTHING IN. The premises is left unmarked,
	-- so the next drawer carries the note instead of the password being lost.
	do
		local net3 = newNet()
		SCeroSecSystem.instance = net3.system
		local sq = net3.machine(10, 10, 0, net3.office):getSquare()
		local crammed = newContainer(sq, true)
		Events.OnFillContainer.trigger("office", "desk", crammed)
		eq("a full drawer takes nothing", #crammed.items, 0)
		local next2 = newContainer(sq)
		Events.OnFillContainer.trigger("office", "desk", next2)
		eq("and the next drawer carries the note", #next2.items, 1)
		SCeroSecSystem.instance = net.system
	end

	--
	-- A DEAD MAN'S POCKET
	--
	-- The engine fires the same event with the room name "Zombie" and the
	-- container type "inventorymale" or "inventoryfemale" (ItemPickerJava, offsets
	-- 47, 60 and 433), and returns -- a body never sees the room distributions.
	--
	do
		local net4 = newNet()
		SCeroSecSystem.instance = net4.system
		local sq = net4.machine(10, 10, 0, net4.office):getSquare()

		-- ZombRand answers 0 for everything in this file, so every roll comes in:
		-- one body, one paper, which is what this first assertion is about.
		local pockets = newContainer(sq)
		Events.OnFillContainer.trigger("Zombie", "inventorymale", pockets)
		eq("a body in the office carries a paper", #pockets.items, 1)
		local paper = pockets.items[1]
		check("with a login and a password on it (" .. tostring(paper:getName()) .. ")",
			string.find(paper:getName(), "^Note: %w+ / %w+$") ~= nil)
		check("and it is NOT root's", string.find(paper:getName(), "root", 1, true) == nil)

		-- AND IT LOGS THAT ACCOUNT IN, on the machine in the same office.
		local box = net4.machine(12, 12, 0, net4.office)
		box:turnOn()
		local who, word = string.match(paper:getName(), "^Note: (%w+) / (%w+)$")
		local user = CeroSecOS.readUsers(box:osState())[who]
		check("the login on the paper is an account on the machine (" .. tostring(who)
			.. ")", user ~= nil)
		check("and the password beside it logs him in",
			CeroSecOS.checkPassword(user, word))
		check("and he is not an administrator's account by accident",
			not CeroSecOS.checkPassword(CeroSecOS.readUsers(box:osState()).root, word))

		-- A BODY IN THE STREET carries nothing: no building, no premises, no staff.
		local outside = newContainer(street)
		Events.OnFillContainer.trigger("Zombie", "inventoryfemale", outside)
		eq("a body in the street carries nothing", #outside.items, 0)

		-- ONE IN TWENTY. ZombRand is replaced for this one measurement -- the file's
		-- own always answers 0, which is every roll coming in -- and two hundred
		-- bodies are searched. A paper on every corpse is a paper nobody reads.
		local hadRand = _G.ZombRand
		local seed = 0
		_G.ZombRand = function(n)
			-- A cycle and not a random number: a bench whose rate depends on a
			-- generator is a bench that is red on somebody else's machine.
			seed = seed + 1
			return math.fmod(seed * 7, math.floor(n))
		end
		local carried = 0
		for i = 1, 200 do
			local body = newContainer(sq)
			Events.OnFillContainer.trigger("Zombie", "inventorymale", body)
			carried = carried + #body.items
		end
		_G.ZombRand = hadRand
		check("about one body in twenty carries a paper (" .. carried .. " of 200)",
			carried >= 4 and carried <= 20)
		-- And a body does not consume the premises' desk note: the two are different
		-- papers and only the desk one is once-per-premises.
		local drawer2 = newContainer(sq)
		Events.OnFillContainer.trigger("office", "desk", drawer2)
		eq("and the drawer still has root's note waiting", #drawer2.items, 1)
		SCeroSecSystem.instance = net.system
	end

	--
	-- THE HOUSE WITH A STUDY IN IT
	--
	-- The regression, and it is the one the whole design promises cannot happen. A
	-- profile used to be decided from the ROOM THE CALLER STOOD IN: the desk in the
	-- study answered "office" -- root password, so a note went into the drawer --
	-- and the computer in the living room of the SAME HOUSE answered "residential",
	-- which has none. The paper named a password nothing in the county had.
	--
	-- Both sides ask the BUILDING now (CeroSecNet.premisesRooms), so this asks the
	-- only question that matters: the paper is written from a drawer in one room and
	-- typed at a machine in another.
	--
	do
		local net7 = newNet()
		SCeroSecSystem.instance = net7.system
		_G.__zones = {}
		-- A house with four rooms, one of which the map calls a study. No zone on it
		-- at all, which is what the shipped map gives a house.
		local home = net7.buildingAt(2000, 2000, 12, 12, 4,
			{ "kitchen", "livingroom", "bedroom", "office" })
		-- The drawer is in the STUDY; the computer is in the LIVING ROOM. Two
		-- different rooms of one building, which is the whole point.
		local study = net7.machine(2004, 2004, 0, home)
		local sitting = net7.machine(2008, 2008, 0, home)
		study:getSquare().getRoom = function()
			return { getName = function() return "office" end }
		end
		sitting:getSquare().getRoom = function()
			return { getName = function() return "livingroom" end }
		end

		local drawer = newContainer(study:getSquare())
		Events.OnFillContainer.trigger("office", "desk", drawer)
		eq("a study in a house gets a paper", #drawer.items, 1)
		local word = string.match(drawer.items[1]:getName(), "/ (%w+)$")
		check("and it names a password", word ~= nil)

		-- AND IT OPENS THE MACHINE IN THE LIVING ROOM.
		sitting:turnOn()
		local root = CeroSecOS.readUsers(sitting:osState()).root
		check("the paper from the study opens the machine in the living room",
			CeroSecOS.checkPassword(root, word))
		check("which is not an open machine", not CeroSecOS.checkPassword(root, ""))

		-- And the machine in the study itself, of course.
		study:turnOn()
		check("and the machine in the study too", CeroSecOS.checkPassword(
			CeroSecOS.readUsers(study:osState()).root, word))

		-- AND THE OTHER SIDE OF THE SAME RULE: a drawer in the KITCHEN of a house
		-- that has a study somewhere in it still gets the paper, because what decides
		-- is the BUILDING and not the room the drawer stands in. This is the case
		-- that catches the notes half of the old bug -- the drawer's own room says
		-- "kitchen", which on its own is a house with no root password at all.
		local other = net7.buildingAt(2500, 2500, 12, 12, 4,
			{ "kitchen", "livingroom", "bedroom", "office" })
		local kitchenDesk = net7.machine(2504, 2504, 0, other)
		kitchenDesk:getSquare().getRoom = function()
			return { getName = function() return "kitchen" end }
		end
		local kdrawer2 = newContainer(kitchenDesk:getSquare())
		Events.OnFillContainer.trigger("kitchen", "counter", kdrawer2)
		eq("a kitchen drawer in a house with a study gets the paper", #kdrawer2.items, 1)
		local kword = string.match(kdrawer2.items[1]:getName(), "/ (%w+)$")
		kitchenDesk:turnOn()
		check("and it opens the machine standing in that kitchen",
			CeroSecOS.checkPassword(CeroSecOS.readUsers(kitchenDesk:osState()).root, kword))

		-- A house with NO study is a house to everybody in it: no paper anywhere.
		local plain = net7.buildingAt(3000, 3000, 12, 12, 3,
			{ "kitchen", "livingroom", "bedroom" })
		local kitchen = net7.machine(3004, 3004, 0, plain)
		kitchen:getSquare().getRoom = function()
			return { getName = function() return "kitchen" end }
		end
		local kdrawer = newContainer(kitchen:getSquare())
		Events.OnFillContainer.trigger("kitchen", "counter", kdrawer)
		eq("a house with no study in it gets no paper", #kdrawer.items, 0)
		kitchen:turnOn()
		check("and its machine is open", CeroSecOS.checkPassword(
			CeroSecOS.readUsers(kitchen:osState()).root, ""))
		_G.__zones = { { name = "FrontOffice", x = 8, y = 8, w = 6, h = 6 } }
		SCeroSecSystem.instance = net.system
	end

	-- A PREMISES WHOSE PROFILE IS EMPTY has no machine content and therefore
	-- nothing to write on a paper.
	--
	-- The profile is taken out of the catalogue HERE, for the length of this block,
	-- and this is the fix to a bench that went stale: it used to name the bank,
	-- which was an empty slot until the world-content work filled it, and it then asserted that a
	-- bank in Knox County has no password in its drawer -- which had become false.
	-- What is under test is the MECHANISM (prefill answers nil for an id nobody has
	-- written, and CeroSecNotes writes nothing for it), and a mechanism has to be
	-- tested by provoking the state it is for rather than by borrowing a gap in the
	-- catalogue that the next change will close.
	do
		local net5 = newNet()
		SCeroSecSystem.instance = net5.system
		_G.__zones = { { name = "Bank", x = 8, y = 8, w = 6, h = 6 } }
		local had = CeroSecContent.PROFILES.bank
		CeroSecContent.PROFILES.bank = nil
		local sq = net5.machine(10, 10, 0, net5.office):getSquare()
		local drawer = newContainer(sq)
		Events.OnFillContainer.trigger("bank", "desk", drawer)
		eq("a premises nobody has written a profile for gets no paper", #drawer.items, 0)
		local body = newContainer(sq)
		Events.OnFillContainer.trigger("Zombie", "inventorymale", body)
		eq("and neither do the dead in it", #body.items, 0)
		CeroSecContent.PROFILES.bank = had
		check("and the catalogue is put back", CeroSecContent.PROFILES.bank ~= nil)
		_G.__zones = { { name = "FrontOffice", x = 8, y = 8, w = 6, h = 6 } }
		SCeroSecSystem.instance = net.system
	end

	-- AND A PREMISES WHOSE PROFILE HAS NO ROOT PASSWORD, which is the case the
	-- shipped catalogue really has: a house. The paper's derivation and the
	-- machine's are one derivation, so a profile with no root password has no note
	-- anywhere -- and that has to be asserted of a REAL entry, or the day every
	-- profile carries a password nothing would notice that the rule had stopped
	-- being exercised.
	do
		local net6 = newNet()
		SCeroSecSystem.instance = net6.system
		check("the house is a written profile with no root password",
			CeroSecContent.PROFILES.residential ~= nil
				and not CeroSecContent.PROFILES.residential.root)
		_G.__zones = {}
		local house = net6.buildingAt(4000, 4000, 12, 12, 3,
			{ "kitchen", "livingroom", "bedroom" })
		local desk = net6.machine(4004, 4004, 0, house)
		desk:getSquare().getRoom = function()
			return { getName = function() return "bedroom" end }
		end
		local drawer = newContainer(desk:getSquare())
		Events.OnFillContainer.trigger("bedroom", "dresser", drawer)
		eq("a house's dresser carries no password", #drawer.items, 0)
		desk:turnOn()
		check("because the machine in it has none",
			CeroSecOS.checkPassword(CeroSecOS.readUsers(desk:osState()).root, ""))
		_G.__zones = { { name = "FrontOffice", x = 8, y = 8, w = 6, h = 6 } }
		SCeroSecSystem.instance = net.system
	end

	-- THE THIRD ARGUMENT IS NOT ALWAYS A CONTAINER. ItemPickerJava fires this event
	-- from ten places, and four of them hand over an ItemPickerContainer -- a
	-- distribution table, not a container at all (offset 1207, room name
	-- "Container"). The handler asks the engine's own instanceof BEFORE it touches
	-- the thing, and that is what this proves: the object here SCREAMS if anything
	-- reads a field off it, so the bench is red on the touch and not merely on the
	-- outcome.
	--
	-- Written the obvious way first -- a plain table and "no note was written" --
	-- this bench stayed green with the gate deleted, because the container-type gate
	-- refuses a bag's type anyway. An assertion that passes for the wrong reason is
	-- not an assertion.
	do
		local net8 = newNet()
		SCeroSecSystem.instance = net8.system
		local touched = nil
		local notAContainer = setmetatable({}, { __index = function(_, key)
			touched = tostring(key)
			error("the handler read '" .. touched .. "' off an ItemPickerContainer", 0)
		end })
		local hadInstanceof = _G.instanceof
		_G.instanceof = function(object, class)
			if object == notAContainer then return false end
			return hadInstanceof(object, class)
		end
		local ok, why = pcall(function()
			Events.OnFillContainer.trigger("Container", "Base.Bag_Schoolbag", notAContainer)
		end)
		_G.instanceof = hadInstanceof
		check("a thing that is not a container is never read: " .. tostring(why), ok)
		eq("not one field of it", touched, nil)
		SCeroSecSystem.instance = net.system
	end

	-- A CORPSE'S SECOND ARGUMENT IS AN OUTFIT NAME and not "inventorymale": at
	-- offsets 106-133 a container whose parent is an IsoDeadBody has its type
	-- replaced by getOutfitName(). The handler keys off the FIRST argument, and this
	-- is what says so.
	do
		local net9 = newNet()
		SCeroSecSystem.instance = net9.system
		local sq = net9.machine(10, 10, 0, net9.office):getSquare()
		local pockets = newContainer(sq)
		Events.OnFillContainer.trigger("Zombie", "OfficeWorker", pockets)
		eq("a corpse whose type is an outfit name still carries a paper",
			#pockets.items, 1)
		check("and it is a login and not root",
			string.find(pockets.items[1]:getName(), "^Note: %w+ / %w+$") ~= nil
				and string.find(pockets.items[1]:getName(), "root", 1, true) == nil)
		SCeroSecSystem.instance = net.system
	end

	-- THE SAVE'S OWN KEYS. The one line this whole change rests on, and until it was
	-- written down here nothing in the suite could see it: setModDataKeys(nil) --
	-- neither the secret nor the notes persisted -- left every bench green. What
	-- that regression costs is a re-rolled secret on every reload, so every password
	-- in the county changes and every paper already lying in the world is wrong for
	-- ever.
	--
	-- The recorder is the fake Java system above, which keeps what the MOD passed
	-- (SGlobalObjectSystem.new in this file calls initSystem, the way vanilla's own
	-- new does at Map/SGlobalObjectSystem.lua:24).
	do
		local saved = net.system.system.modDataKeys
		check("the system names the fields it saves", type(saved) == "table")
		-- AND THEY ARE THE CONSTANTS, by identity. CeroSecSelfTest.keys asks those
		-- three tables the "seed is saved and never synced" question inside a real
		-- game, which is only worth anything while the tables it reads are the very
		-- ones handed over here: a literal list at the call site would make the
		-- self-test's answer a fact about a copy.
		eq("and the list is the constant, not a copy of it", saved,
			CeroSec.SYSTEM_SAVE_KEYS)
		eq("so is the machines' saved list",
			net.system.system.objectModDataKeys, CeroSec.OBJECT_SAVE_KEYS)
		eq("and the client sync list", net.system.system.syncKeys,
			CeroSec.OBJECT_SYNC_KEYS)
		local seen = {}
		for i = 1, #saved do seen[saved[i]] = true end
		check("the per-save secret is saved", seen.seed == true)
		check("and so is which premises already has its paper", seen.notes == true)

		-- AND THE SECRET IS NEVER SENT TO A CLIENT. It is what every password in the
		-- county derives from; the sync list is the client channel.
		local sync = net.system.system.syncKeys
		check("the client sync list is named", type(sync) == "table")
		for i = 1, #sync do
			check("the client is not sent the secret (" .. sync[i] .. ")",
				sync[i] ~= "seed")
			check("nor the paper bookkeeping (" .. sync[i] .. ")", sync[i] ~= "notes")
		end
		eq("and the system tells a joining client nothing at all",
			net.system:getInitialStateForClient(), nil)
	end

	-- THE OPTION OFF is no papers at all, which is the world this mod shipped with.
	do
		local net6 = newNet()
		SCeroSecSystem.instance = net6.system
		_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
		local sq = net6.machine(10, 10, 0, net6.office):getSquare()
		local drawer = newContainer(sq)
		Events.OnFillContainer.trigger("office", "desk", drawer)
		eq("with the option off a desk gets nothing", #drawer.items, 0)
		local body = newContainer(sq)
		Events.OnFillContainer.trigger("Zombie", "inventorymale", body)
		eq("and a body carries nothing", #body.items, 0)
	end

	SCeroSecSystem.instance = hadInstance
	_G.__zones = {}
	_G.getWorld = nil
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
end

--
-- 53. The developer's reset (the debug window's one irreversible act)
--
-- A machine whose FIRST power-on went wrong halfway through is a machine there is
-- no second try on: prefill runs once in the life of a computer and never again, so
-- a half filled disk stays half filled for ever and the bug that made it cannot be
-- provoked twice. "Reset machine" is what makes a machine nobody has ever used out
-- of one that has been used (SCeroSecObject:resetMachine), and this is the bench
-- for it: the state really goes, the DISK really stays, and the power-on after it
-- really does prefill the machine again -- with the same accounts, because the
-- accounts come out of the save's own secret and the premises, neither of which a
-- reset touches.
--
do
	local net = newNet()
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = true } }
	_G.getWorld = zonedWorld
	_G.__zones = { { name = "FrontOffice", x = 8, y = 8, w = 6, h = 6 } }

	local machine = net.machine(10, 10, 0, net.office)
	machine:turnOn()
	local state = machine:osState()

	-- THE WITNESS, and it is not a formality: everything below compares a machine
	-- before a reset with the same machine after one, and a bench whose machine came
	-- up bare would be comparing two empty disks and passing.
	local users, order = CeroSecOS.readUsers(state)
	check("the machine came up with somebody's accounts on it (" .. #order .. ")",
		#order > 2)
	local b1, b2 = CeroSecNet.premisesOf(machine)
	local paper = CeroSecContent.password(net.system:secret(),
		CeroSecContent.rootKey(b1, b2))
	check("and the paper in the drawer opens it", CeroSecOS.checkPassword(users.root, paper))
	local namesWas = table.concat(order, " ")
	local hostWas = state.hostname

	-- Something of the player's own on the disk, which is what a reset is allowed to
	-- destroy and the papers in the drawer are not.
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/mine.txt", "my work",
		false, nil)
	check("with a file of his own on it",
		CeroSecOS.systemNode(state, "/mine.txt") ~= nil)

	-- And a disk in the drive: a player carried it here, it is a thing in the world,
	-- and the one thing a reset must not throw away.
	local fs = CeroSecOS.newDir("root", 755)
	fs.children.notes = CeroSecOS.newFile("root", 644, "his own disk")
	state.floppy = { v = CeroSecOS.FLOPPY_VERSION, fs = fs }
	state.fdtype = "CeroSec.FloppyRed"
	machine:syncDisk()
	eq("and a disk in its drive", machine:hasDisk(), true)

	-- And the premises has already had its paper. That bookkeeping is the SYSTEM's
	-- and is about a PREMISES (CeroSecNotes.premisesMark), so a reset must not touch
	-- it: the note in the drawer names a password derived from the secret and the
	-- premises, both of which survive this, and clearing the mark would put a second
	-- paper in the next drawer somebody opens.
	CeroSecNotes.markNote(net.system, b1, b2)

	-- A machine that is ON is not reset: it would have its jobs and its screen taken
	-- away behind the back of everybody standing at it.
	eq("a running machine refuses the reset",
		CeroSecDebug.resetRefusal(machine), "it is on -- switch it off first")
	eq("and nothing selected refuses it too",
		CeroSecDebug.resetRefusal(nil), "nothing is selected")

	machine:turnOff()
	eq("switched off there is nothing to refuse", CeroSecDebug.resetRefusal(machine), nil)

	-- The state the reset is judged against is PROVOKED and not waited for. A machine
	-- that is off has no jobs and no windows -- turnOff took them -- so a bench that
	-- only switched it off would assert zero against zero and stay green with the
	-- killing taken out of the reset altogether.
	machine.jobs = { next = 7, list = { { id = 1, state = "running", prog = {} } } }
	machine.watchers = { ["p0-1"] = { player = net.player, token = "1" } }
	machine.rebooting = { at = 1, waiting = {} }
	machine.heard = { { call = "KE4QWZ", at = 1 } }
	machine.console = CeroSec.newConsole()
	-- What the server says to a window it is closing, kept: a window is TOLD the
	-- machine is over and never merely forgotten.
	local told = {}
	net.system.reply = function(_, _, cmd, args)
		told[#told + 1] = { cmd = cmd, args = args }
	end

	eq("the reset says it happened", machine:resetMachine(), true)
	eq("the window standing at it was told", #told, 1)
	eq("in the words a window shuts itself on", told[1].cmd, "closed")

	eq("the state is gone", machine.os ~= nil and machine.os.fs ~= nil
		and CeroSecOS.systemNode(machine.os, "/mine.txt") or nil, nil)
	eq("every job with it", machine.jobs, nil)
	eq("every window", machine.watchers, nil)
	eq("the dark interval of a reboot", machine.rebooting, nil)
	eq("the stations the TNC had heard", machine.heard, nil)
	eq("and the screen", machine.console, nil)
	eq("it is still off", machine.on, false)

	-- THE DISK IS STILL IN THE DRIVE, with what is written on it.
	eq("the disk did not leave the drive", machine:hasDisk(), true)
	eq("and the client is told so", machine.disk, true)
	eq("with what was written on it",
		machine.os.floppy.fs.children.notes.data, "his own disk")
	eq("in the shell it came in", machine.os.fdtype, "CeroSec.FloppyRed")
	-- And the paper already placed is still on the books.
	eq("the note this premises had is not handed out again",
		CeroSecNotes.hasNote(net.system, b1, b2), true)

	-- AND THE POWER-ON AFTER IT PREFILLS AGAIN, which is the whole point.
	--
	-- With the window's own detail block asked in between, because that is what a
	-- developer actually does -- the reset is a button on a window that reads the
	-- selected machine's disk every two seconds -- and osState is what MAKES a state
	-- out of nothing: a reset remembered as "self.os is nil" would be undone by the
	-- refresh that followed it.
	CeroSecDebug.snapshotOf(net.system, "files", machine)

	eq("it comes back on", machine:turnOn(), true)
	local now = machine:osState()
	local usersNow, orderNow = CeroSecOS.readUsers(now)
	eq("with the same accounts as before", table.concat(orderNow, " "), namesWas)
	eq("and the same name on the machine", now.hostname, hostWas)
	-- The PASSWORDS and not the bytes of /etc/passwd: every hash is salted with a
	-- salt of its own (the $cs1$ field), so the same password written twice is two
	-- different lines -- and what a player holds is the paper, which is what this
	-- types at it.
	check("so the paper already in the drawer still opens it",
		CeroSecOS.checkPassword(usersNow.root, paper))
	eq("the file the player had written is gone",
		CeroSecOS.systemNode(now, "/mine.txt"), nil)
	eq("and the disk is still in the drive", machine:hasDisk(), true)
	local passwdNow = CeroSecOS.systemNode(now, CeroSecOS.PASSWD_PATH).data

	-- And it is ONCE again: the machine that has just been prefilled is a machine
	-- somebody has used, and switching it off and on does not fill it twice.
	machine:turnOff()
	machine:turnOn()
	eq("the power-on after that is not a first one",
		CeroSecOS.systemNode(machine:osState(), CeroSecOS.PASSWD_PATH).data, passwdNow)

	_G.__zones = {}
	_G.getWorld = nil
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
end

-- Through the real command door: the refusal a window prints, and the door that is
-- shut.
do
	local net = newNet()
	local machine = net.here
	local answers = {}
	net.system.reply = function(_, _, cmd, args)
		answers[#answers + 1] = { cmd = cmd, args = args }
	end

	-- On, so it is refused -- and answered, because a refusal a player cannot read
	-- is a refusal that looks like a bug in the mod.
	eq("the machine is on", machine.on, true)
	local was = machine.os
	net.system:OnClientCommand("debugact", net.player,
		{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "reset" })
	eq("the press was answered", #answers, 1)
	check("with the refusal",
		string.find(tostring(answers[1].args.error), "cannot reset", 1, true) ~= nil)
	check("in the server's own words",
		string.find(tostring(answers[1].args.error), "switch it off first", 1, true) ~= nil)
	eq("and the state is exactly the one it had", machine.os, was)

	-- Off, it happens, and a press that worked answers nothing at all: the snapshot
	-- two seconds later is what says so.
	machine:turnOff()
	answers = {}
	net.system:OnClientCommand("debugact", net.player,
		{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "reset" })
	eq("nothing is answered when it worked", #answers, 0)
	eq("and the machine has no state at all", machine.os, nil)

	-- Every snapshot says whether the selected machine may be reset, whatever tab it
	-- is for, because the button under the list is on every tab.
	local tabs = { "machines", "files", "devices", "network", "scheduler" }
	for i = 1, #tabs do
		local snap = CeroSecDebug.snapshotOf(net.system, tabs[i], machine)
		eq(tabs[i] .. " says an off machine may be reset", snap.canReset, true)
		eq("with nothing to say about why not", snap.resetReason, nil)
	end
	local snap = CeroSecDebug.snapshotOf(net.system, "machines", net.gate)
	eq("and a machine that is on may not", snap.canReset, false)
	eq("with the reason", snap.resetReason, "it is on -- switch it off first")

	-- THE DOOR SHUT. Every command of this window asks CeroSec.debugAllowed, and the
	-- release turns the flag off: with no debug mode around it the reset is not a
	-- refusal, it is nothing at all -- the command does not answer and does not act.
	local hadFlag = CeroSec.DEV_DEBUG_MENU
	CeroSec.DEV_DEBUG_MENU = false
	eq("the door really is shut", CeroSec.debugAllowed(), false)
	net.gate:turnOff()
	local gateState = net.gate.os
	answers = {}
	net.system:OnClientCommand("debugact", net.player,
		{ x = 12, y = 10, z = 0, token = "dbg-0-1", act = "reset" })
	eq("a reset through a shut door answers nothing", #answers, 0)
	eq("and resets nothing", net.gate.os, gateState)
	CeroSec.DEV_DEBUG_MENU = hadFlag
end


--
-- 54. The admin's and the tester's eight acts (the debug window's tools)
--
-- Eight more things the window may ask the server for, and every one of them is
-- driven HERE through the real OnClientCommand door, because the wire from the button
-- to the state is what the window is: a bench that called the act's function would
-- prove the function and nothing about the command that reaches it.
--
-- What is asserted is the STATE each act leaves behind -- the paper in the bag with
-- the words the drawer would have carried, the digest of an account really cleared,
-- the disk with the sticker the world puts on one, the session logged in as root, a
-- crontab line's own mail on the disk, the premises' record really `wired` -- and then
-- every refusal in the server's own words, and then the door shut, which answers
-- nothing and does nothing.
--
do
	local net = newNet()
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = true } }
	_G.getWorld = zonedWorld
	_G.__zones = { { name = "FrontOffice", x = 8, y = 8, w = 6, h = 6 } }

	-- THE MACHINE THE HARNESS ALREADY HAS at 10,10,0 and not a second one on the same
	-- square: getLuaObjectAt walks the list and answers the FIRST, so a bench that
	-- stood a second computer there would drive every command into the first one and
	-- assert about the other -- which is a bench that passes while nothing it names is
	-- what it touched.
	--
	-- It is switched on already and therefore not prefilled (the zones and the sandbox
	-- option are set above, after newNet ran), so it is reset and switched on again --
	-- which is the one thing that makes a first power-on happen twice
	-- (SCeroSecObject:resetMachine, and section 53).
	local machine = net.here
	machine:turnOff()
	eq("the machine was reset", machine:resetMachine(), true)
	eq("and comes back on", machine:turnOn(), true)
	local state = machine:osState()
	local b1, b2 = CeroSecNet.premisesOf(machine)
	local secret = net.system:secret()

	local answers = {}
	net.system.reply = function(_, _, cmd, args)
		answers[#answers + 1] = { cmd = cmd, args = args }
	end
	local inv = newInventory()
	net.player.getInventory = function() return inv end

	local function ask(act, extra)
		answers = {}
		local args = { x = 10, y = 10, z = 0, token = "dbg-0-1", act = act }
		if type(extra) == "table" then
			for key, value in pairs(extra) do args[key] = value end
		end
		net.system:OnClientCommand("debugact", net.player, args)
		return answers[1]
	end
	local function noteOf(answer)
		if answer == nil then return nil end
		return answer.args.note
	end
	local function errorOf(answer)
		if answer == nil then return nil end
		return answer.args.error
	end

	-- The witness, and it is not a formality: this machine has to have come up with
	-- somebody's accounts on it, or every assertion below is about an empty disk.
	local users, order = CeroSecOS.readUsers(state)
	check("the machine came up prefilled (" .. #order .. " accounts)", #order > 2)
	-- WHICH premises, and whose people, through the very function the acts go through
	-- -- and then held to being the same premises the paper is keyed on, which is what
	-- makes the words below assertable at all.
	local pb1, pb2, profile, pwhy = CeroSecDebug.profileOf(machine)
	eq("the premises can be asked", pwhy, nil)
	eq("and it is the premises the note is keyed on", pb1, b1)
	eq("in both bytes", pb2, b2)
	check("and its profile has a root password",
		type(profile) == "table" and profile.root == true)

	--
	-- 1. GIVE ROOT NOTE: the paper the drawer would hold, and the drawer keeps its own
	--
	do
		local paper = CeroSecContent.password(secret, CeroSecContent.rootKey(b1, b2))
		local wanted = string.format(CeroSecNotes.ROOT_FORM, "root", paper)
		eq("no paper has been placed for this premises yet",
			CeroSecNotes.hasNote(net.system, b1, b2), false)

		local answer = ask("rootnote")
		eq("one item went into the bag", #inv.items, 1)
		local item = inv.items[1]
		eq("and it is a sticky note", item:getFullType(), CeroSecNotes.ITEM)
		-- THE EXACT WORDS the drawer would have carried, derived here by the bench out
		-- of the secret and the premises the way the drawer derives them
		-- (CeroSecNotes.deskNote): a note that named any other password would be a
		-- paper that does not open the machine in front of it.
		eq("with the very words a desk of this premises would carry",
			item:getName(), wanted)
		check("and the custom-name flag, so the game keeps them", item:isCustomName())
		check("and the fields synced", item.synced > 0)
		-- And the password on it really is the machine's.
		check("the letters on it open root on that machine",
			CeroSecOS.checkPassword(CeroSecOS.getUser(state, "root"), paper))
		-- THE BOOKKEEPING IS UNTOUCHED, which is the one thing this act must not do:
		-- the mark says a premises' one paper has been placed in a real container, and
		-- setting it here would take the note out of the next drawer a player opens.
		eq("the premises is still unmarked, so its drawer still carries one",
			CeroSecNotes.hasNote(net.system, b1, b2), false)
		check("and the receipt is a note and not an error: " .. tostring(noteOf(answer)),
			type(noteOf(answer)) == "string" and errorOf(answer) == nil)
		check("with the words on it, so the reader need not open his bag",
			string.find(tostring(noteOf(answer)), paper, 1, true) ~= nil)
	end

	--
	-- 2. GIVE STAFF NOTE: one locked account's own login, and never root's
	--
	do
		local slot = CeroSecContent.lockedSlots(profile)[1]
		check("the profile has a locked account", slot ~= nil)
		local login = profile.accounts[slot].name
		if type(login) ~= "string" then
			login = CeroSecContent.accountLogin(secret, b1, b2, slot)
		end
		local password = CeroSecContent.accountPassword(secret, b1, b2, slot, login)
		local wanted = string.format(CeroSecNotes.USER_FORM, login, password)

		local before = #inv.items
		local answer = ask("staffnote")
		eq("a second paper went into the bag", #inv.items, before + 1)
		local item = inv.items[#inv.items]
		eq("in the pocket's own shape and not the drawer's", item:getName(), wanted)
		check("it never names root",
			string.find(item:getName(), "root", 1, true) == nil)
		-- And that login really is on the machine, with that password.
		local user = CeroSecOS.getUser(state, login)
		check("the login on it is an account the machine has: " .. tostring(login),
			user ~= nil)
		check("and the letters open it", CeroSecOS.checkPassword(user, password))
		check("and the slot is named in the receipt: " .. tostring(noteOf(answer)),
			string.find(tostring(noteOf(answer)), "slot " .. slot, 1, true) ~= nil)
	end

	--
	-- 3. SHOW ACCOUNTS: every account, and the letters for the ones the catalogue made
	--
	do
		CeroSec.logRing = {}
		local answer = ask("accounts")
		check("it answered with a note and not a refusal: " .. tostring(noteOf(answer)),
			type(noteOf(answer)) == "string" and errorOf(answer) == nil)
		-- The LINES are on the log, at info, which is the level the Log tab's All
		-- button shows: a note is one line and this is one line per account.
		local logged = {}
		for i = 1, #CeroSec.logRing do
			if CeroSec.logRing[i].level == CeroSec.LOG_INFO then
				logged[#logged + 1] = CeroSec.logRing[i].text
			end
		end
		-- One line for the machine and one per account, and the COUNT is asserted
		-- because a list that quietly held one name would pass every test below.
		eq("one line for the machine and one an account", #logged, #order + 1)
		local all = table.concat(logged, "\n")
		for i = 1, #order do
			check("the line for " .. order[i] .. " is there",
				string.find(all, order[i], 1, true) ~= nil)
		end
		-- THE LETTERS, for root, which is the half of this a tester is actually after.
		local paper = CeroSecContent.password(secret, CeroSecContent.rootKey(b1, b2))
		check("root's password is on the log in clear",
			string.find(all, paper, 1, true) ~= nil)
		-- And the SECRET itself never is: it is the server's and the one number every
		-- password in the county comes out of.
		eq("and the save's own secret is not",
			string.find(all, tostring(secret), 1, true), nil)
		-- An OPEN account is said to be open rather than given letters it has not got.
		local openName = nil
		for i = 1, #order do
			if CeroSecOS.checkPassword(users[order[i]], "") then openName = order[i] end
		end
		if openName ~= nil then
			check("an open account says so",
				string.find(all, "OPEN", 1, true) ~= nil)
		end
	end

	--
	-- 4. CLEAR PASSWORD: passwd -d, which on this machine is the hash of ""
	--
	do
		local before = CeroSecOS.getUser(state, "root").password
		check("root has a password nobody has typed",
			not CeroSecOS.checkPassword(CeroSecOS.getUser(state, "root"), ""))

		local answer = ask("clearpass", { login = "root" })
		check("it worked: " .. tostring(noteOf(answer)),
			type(noteOf(answer)) == "string" and errorOf(answer) == nil)
		-- THE STATE: the stored digest is a new one and it is the digest of nothing, so
		-- login lets an empty answer through -- which is what an account that ships
		-- open has always been (CeroSecOS.newUser).
		local now = CeroSecOS.getUser(state, "root")
		check("the stored digest changed", now.password ~= before)
		check("and it is the digest of no letters at all",
			CeroSecOS.checkPassword(now, ""))
		check("so login takes an empty password", CeroSecOS.login(state, "root", "") ~= nil)
		-- And the paper in the drawer no longer opens it, which is the honest
		-- consequence and is worth pinning: this act really did take a password off.
		local paper = CeroSecContent.password(secret, CeroSecContent.rootKey(b1, b2))
		eq("and the old letters do not open it any more",
			CeroSecOS.checkPassword(now, paper), false)

		-- A login the machine has not got, and a string that is not a name at all.
		check("an account that is not there is refused",
			string.find(tostring(errorOf(ask("clearpass", { login = "nobody" }))),
				"no such user", 1, true) ~= nil)
		check("and a string no /etc/passwd line could carry is refused before that",
			string.find(tostring(errorOf(ask("clearpass", { login = "a/b:c" }))),
				"not an account name", 1, true) ~= nil)
		check("and so is no login at all",
			string.find(tostring(errorOf(ask("clearpass", {}))),
				"not an account name", 1, true) ~= nil)
	end

	--
	-- 5. GIVE DISK: any entry of the catalogue, built the way the world builds one
	--
	do
		local entry = CeroSecContent.diskById("UTILITIES")
		check("the catalogue has the entry", entry ~= nil)
		local before = #inv.items
		local answer = ask("anydisk", { disk = "UTILITIES" })
		eq("a disk went into the bag", #inv.items, before + 1)
		local item = inv.items[#inv.items]
		check("it is one of our floppy items", CeroSec.isFloppyType(item:getFullType()))
		-- THE STICKER THE WORLD PUTS ON ONE, asked of the catalogue by the LABEL: a
		-- handwritten entry has one per telling and the act rolls which, so what is
		-- asserted is that the name on the shell is a sticker THIS entry can wear and
		-- not a string of the act's own (CeroSecContent.diskByLabel).
		eq("with a sticker of that very entry",
			CeroSecContent.diskByLabel(item:getName()), entry)
		check("and the custom-name flag", item:isCustomName())
		local disk = CeroSecOS.diskFromData(item:getModData())
		check("the modData carries a disk", type(disk) == "table")
		check("which the slot would take", CeroSecOS.validateDisk(disk, true))
		eq("labelled the same thing the shell is", disk.label, item:getName())
		-- Every file of the entry really is on it: a disk handed over half written is
		-- a disk the bench never weighed.
		local children = type(disk.fs) == "table" and disk.fs.children or {}
		local made = 0
		for _ in pairs(children) do made = made + 1 end
		check("with files on it (" .. made .. ")", made > 0)
		check("and the receipt names the label: " .. tostring(noteOf(answer)),
			string.find(tostring(noteOf(answer)), "UTILITIES", 1, true) ~= nil)

		-- A LATE DISK gets its stub, exactly as a found one does: nothing is filled in
		-- until it is first inserted, which is the hole `late` was dug for.
		local bbs = CeroSecContent.diskById("BBS LIST")
		if bbs ~= nil then
			ask("anydisk", { disk = "BBS LIST" })
			local late = CeroSecOS.diskFromData(inv.items[#inv.items]:getModData())
			local stub = late ~= nil and type(late.fs) == "table"
				and late.fs.children[CeroSecContent.lateFile(bbs)] or nil
			check("the late file is on it as a stub", stub ~= nil)
		end

		-- An id the catalogue has not got, and an id that is not a string.
		local held = #inv.items
		check("an id nothing answers to is refused",
			string.find(tostring(errorOf(ask("anydisk", { disk = "NO SUCH DISK" }))),
				"no such disk", 1, true) ~= nil)
		check("and naming no disk at all is refused",
			string.find(tostring(errorOf(ask("anydisk", {}))),
				"no disk was named", 1, true) ~= nil)
		eq("and neither handed anything over", #inv.items, held)
	end

	--
	-- 6. LOGIN AS ROOT: the password check skipped and nothing else
	--
	do
		local console = machine.console
		eq("nobody is logged in at the glass", console.user, nil)
		local wtmpBefore = CeroSecOS.systemNode(state, CeroSecOS.WTMP_PATH)
		local before = wtmpBefore ~= nil and #(wtmpBefore.data or "") or 0

		local answer = ask("rootlogin")
		check("it worked: " .. tostring(noteOf(answer)),
			type(noteOf(answer)) == "string" and errorOf(answer) == nil)
		-- THE SESSION, on the machine's own console: who it is, where he is standing,
		-- and the environment a login hands a shell -- every one of them the login's
		-- own gestures (SCeroSecSystem:beginSession), because this is a shortcut past
		-- the keyboard and past nothing else.
		eq("root is at the glass", console.user, "root")
		eq("in root's own home", console.cwd, "/root")
		check("with a login shell's variables set", type(console.shvars) == "table")
		check("and PATH among them", console.shvars.PATH ~= nil)
		eq("and no su stack under him", console.stack, nil)
		check("and the moment he sat down", type(console.loginAt) == "number")
		-- AND /var/log/wtmp KNOWS, which is what `last` and `who` read: a session that
		-- left no record would be a session the machine itself cannot account for.
		local wtmp = CeroSecOS.systemNode(state, CeroSecOS.WTMP_PATH)
		check("wtmp grew", wtmp ~= nil and #(wtmp.data or "") > before)
		check("and names root",
			string.find(tostring(wtmp.data), "root", 1, true) ~= nil)

		-- Asked again, it is refused: the glass belongs to whoever is in it.
		check("a second login is refused while somebody is in the session",
			string.find(tostring(errorOf(ask("rootlogin"))),
				"already logged in as root", 1, true) ~= nil)
	end

	--
	-- 7. RUN CRON NOW: a crontab line, without waiting for the minute
	--
	do
		-- A line of root's own that mails a word. MAIL and not a redirection, because
		-- what cron does with a job's output is mail it (CeroSecJobs, `job.mailTo`), so
		-- the effect on the disk is /var/mail/root growing -- and the effect is the
		-- assertion.
		local now = CeroSecOS.clockOf(net.system:clockEnv())
		-- writeFile and not setData: root may have no crontab at all on this premises
		-- -- the office's nightly line is an ACCOUNT's and lives in his own file
		-- (docs/CONTENT.md) -- and setData writes over a file that is already there.
		local made = CeroSecOS.writeFile(state, CeroSecOS.rootSession(),
			CeroSecOS.cronPath("root"), "* * * * * echo cronranhere", false, now)
		check("root's crontab was installed", made ~= nil)
		local mailBefore = CeroSecOS.systemNode(state, CeroSecOS.mailPath("root"))
		local before = mailBefore ~= nil and #(mailBefore.data or "") or 0

		-- The daemon's own sweep would do nothing right now: it has already looked at
		-- this minute, which is exactly what the button has to get past.
		eq("the daemon's own pass fires nothing this minute",
			CeroSecJobs.cronPass(net.system, machine, now), 0)

		local answer = ask("cronnow")
		check("the act says what it did: " .. tostring(noteOf(answer)),
			type(noteOf(answer)) == "string" and errorOf(answer) == nil)
		-- At least one, and the number is read off the note rather than pinned at one:
		-- a prefilled office has a crontab of its own and the line this bench added is
		-- not the only one that can be due in the same minute (docs/CONTENT.md, the
		-- nightly total).
		local fired = tonumber(string.match(tostring(noteOf(answer)),
			"cron fired (%d+) line")) or 0
		check("and it fired at least the line this bench installed (" .. fired .. ")",
			fired >= 1)
		-- The job cron made is on the scheduler's book, and stepping it is what puts
		-- the output in the mail: a bench that stopped at the note would have proved
		-- that a number was printed.
		net.tick(20)
		local mail = CeroSecOS.systemNode(state, CeroSecOS.mailPath("root"))
		check("root's mailbox grew", mail ~= nil and #(mail.data or "") > before)
		check("with what the line printed",
			string.find(tostring(mail.data), "cronranhere", 1, true) ~= nil)
	end
	_G.__zones = {}
	_G.getWorld = nil
	_G.SandboxVars = { CeroSec = { HardwareRequired = false, PrefilledMachines = false } }
end

--
-- 8. FORCE WIRE: the automation's walk, run to the end
--
-- The walk is ROOMS_PER_MINUTE rooms a game minute (CeroSecAuto.ROOMS_PER_MINUTE),
-- so a premises of more rooms than that takes several minutes and a tester cannot see
-- the end of it. This act calls the very same function over and over until the record
-- says `wired`, and the bench gives the premises MORE rooms than one pass can walk --
-- which is the only shape in which "it loops" can be told from "one call was enough".
--
do
	local net = newNet()

	-- A building of twenty rooms, built here rather than off net.buildingAt: the walk
	-- reads each room's live IsoRoom to find its squares
	-- (CeroSecDevices.fixturesInRooms, `room.def:getIsoRoom()`), and the shared
	-- harness's buildings have no live rooms at all. Every room answers a live one
	-- with no squares in it, so nothing is FITTED here -- what a fixture getting its
	-- modules costs and proves is CeroSecAuto's own bench -- and what this proves is
	-- the walk being driven to the end.
	local ROOMS = 20
	local defs = {}
	for i = 1, ROOMS do
		local at = i
		defs[i] = {
			getName = function() return "room" .. at end,
			getX = function() return 400 + at end,
			getY = function() return 700 end,
			getX2 = function() return 401 + at end,
			getY2 = function() return 701 end,
			getZ = function() return 0 end,
			getArea = function() return 1 end,
			getIsoRoom = function()
				return { getSquares = function()
					return { size = function() return 0 end,
						get = function() return nil end }
				end }
			end,
		}
	end
	local def = {
		getX = function() return 400 end,
		getY = function() return 700 end,
		getX2 = function() return 430 end,
		getY2 = function() return 730 end,
		getArea = function() return 900 end,
		getRoomsNumber = function() return ROOMS end,
		getRooms = function() return javaList(defs) end,
	}
	local building = { getDef = function() return def end }
	local machine = net.machine(20, 20, 0, building)
	machine:turnOn()
	local b1, b2 = CeroSecNet.premisesOf(machine)
	check("the machine has a premises", b1 ~= nil)
	check("and it has more rooms than one pass walks",
		ROOMS > CeroSecAuto.ROOMS_PER_MINUTE)

	local answers = {}
	net.system.reply = function(_, _, cmd, args)
		answers[#answers + 1] = { cmd = cmd, args = args }
	end
	local function ask()
		answers = {}
		net.system:OnClientCommand("debugact", net.player,
			{ x = 20, y = 20, z = 0, token = "dbg-0-1", act = "forcewire" })
		return answers[1]
	end

	-- A premises nobody has asked about has no record at all.
	check("with no record it is refused",
		string.find(tostring(ask().args.error), "not been asked yet", 1, true) ~= nil)

	-- A premises that rolled NO is left alone, and a "force" that wired one would be
	-- this window inventing a world rather than hurrying one up.
	net.system.auto = {}
	net.system.auto[CeroSecContent.premisesKey(b1, b2)] =
		{ on = false, machine = { x = 20, y = 20, z = 0 } }
	check("a premises that rolled no is refused",
		string.find(tostring(ask().args.error), "rolled no", 1, true) ~= nil)

	-- And one that rolled yes is walked to the end.
	local record = { on = true, machine = { x = 20, y = 20, z = 0 } }
	net.system.auto[CeroSecContent.premisesKey(b1, b2)] = record
	eq("it is not wired to begin with", record.wired, nil)
	-- One pass of the walk on its own cannot finish it, which is what makes the loop
	-- the thing under test.
	CeroSecAuto.wire(net.system, machine)
	eq("one pass of the walk leaves it unfinished", record.wired, nil)
	eq("having walked exactly one pass of rooms",
		CeroSecDebug.roomsWalked(record), CeroSecAuto.ROOMS_PER_MINUTE)

	local answer = ask()
	eq("the act answered", answer ~= nil, true)
	eq("with a note and no refusal", answer.args.error, nil)
	-- THE STATE: the record says the premises is finished.
	eq("the premises is wired", record.wired, true)
	check("and the note says so: " .. tostring(answer.args.note),
		string.find(tostring(answer.args.note), "finished", 1, true) ~= nil)
	check("and how many passes it spent",
		string.find(tostring(answer.args.note), "pass(es)", 1, true) ~= nil)

	-- Asked again, there is nothing left to do and it says so rather than looping.
	check("a premises already wired is refused",
		string.find(tostring(ask().args.error), "already wired", 1, true) ~= nil)
	net.system.auto = nil
end

--
-- 9. THE REFUSALS THE EIGHT WEAR, and the door shut over all of them
--
do
	local net = newNet()
	local answers = {}
	net.system.reply = function(_, _, cmd, args)
		answers[#answers + 1] = { cmd = cmd, args = args }
	end
	local inv = newInventory()
	net.player.getInventory = function() return inv end

	-- A machine nobody has ever used: no state, and the three acts that read or write
	-- a disk say so rather than reading a filesystem osState would have INVENTED for
	-- them -- which is the trap the reset's own flag was written for.
	local idle = net.machine(300, 220, 0, net.shed)
	eq("it has no state at all", idle.os, nil)
	local disky = { "accounts", "clearpass" }
	for i = 1, #disky do
		answers = {}
		net.system:OnClientCommand("debugact", net.player,
			{ x = 300, y = 220, z = 0, token = "dbg-0-1", act = disky[i],
				login = "root" })
		eq(disky[i] .. " was answered", #answers, 1)
		check("with the disk's own refusal: " .. tostring(answers[1].args.error),
			string.find(tostring(answers[1].args.error), "never been switched on",
				1, true) ~= nil)
	end
	eq("and the machine still has no state", idle.os, nil)

	-- Off: root cannot be logged in and cron cannot run.
	local off = { rootlogin = "it is off", cronnow = "it is off" }
	for act, why in pairs(off) do
		answers = {}
		net.system:OnClientCommand("debugact", net.player,
			{ x = 300, y = 220, z = 0, token = "dbg-0-1", act = act })
		check(act .. " on a machine that is off says so: "
			.. tostring(answers[1] and answers[1].args.error),
			answers[1] ~= nil and
				string.find(tostring(answers[1].args.error), why, 1, true) ~= nil)
	end

	-- A machine in no building at all -- a player's own base -- has no premises, so
	-- neither paper can be derived.
	local outdoors = net.machine(500, 500, 0, nil)
	outdoors:turnOn()
	local papers = { "rootnote", "staffnote" }
	for i = 1, #papers do
		answers = {}
		net.system:OnClientCommand("debugact", net.player,
			{ x = 500, y = 500, z = 0, token = "dbg-0-1", act = papers[i] })
		check(papers[i] .. " outdoors says there is no premises: "
			.. tostring(answers[1] and answers[1].args.error),
			answers[1] ~= nil and
				string.find(tostring(answers[1].args.error), "no building", 1, true) ~= nil)
	end
	eq("and nothing went into the bag", #inv.items, 0)

	-- A machine whose CHUNK is away cannot be asked what its premises is at all, and
	-- the sentence names the chunk and not the building -- the distinction the power
	-- sweep once got wrong.
	local away = net.far
	away.getSquare = function() return nil end
	answers = {}
	net.system:OnClientCommand("debugact", net.player,
		{ x = 60, y = 60, z = 0, token = "dbg-0-1", act = "rootnote" })
	check("a chunk that is away is named as the reason: "
		.. tostring(answers[1] and answers[1].args.error),
		answers[1] ~= nil and
			string.find(tostring(answers[1].args.error), "chunk is away", 1, true) ~= nil)

	-- Every snapshot carries all eight answers, whatever tab it is for, because the
	-- buttons are on every tab's window.
	local fields = {
		{ "canRootNote", "rootNoteReason" },
		{ "canStaffNote", "staffNoteReason" },
		{ "canAccounts", "accountsReason" },
		{ "canClearPass", "clearPassReason" },
		{ "canRootLogin", "rootLoginReason" },
		{ "canCronNow", "cronNowReason" },
		{ "canForceWire", "forceWireReason" },
	}
	local tabs = { "machines", "files", "devices", "network", "scheduler" }
	for t = 1, #tabs do
		local snap = CeroSecDebug.snapshotOf(net.system, tabs[t], idle)
		for f = 1, #fields do
			local can, reason = fields[f][1], fields[f][2]
			eq(tabs[t] .. " says whether " .. can, type(snap[can]), "boolean")
			-- A no always has a sentence and a yes never does, which is what the
			-- window prints and what greys the button: a field that said no with
			-- nothing to say would be a button greyed for no readable reason.
			if snap[can] == false then
				check(tabs[t] .. ": " .. can .. " carries its own reason",
					type(snap[reason]) == "string")
			else
				eq(tabs[t] .. ": " .. can .. " has nothing to say", snap[reason], nil)
			end
		end
		-- The three that want a machine that is ON are refused on this one, whatever
		-- the window has asked about it.
		eq(tabs[t] .. " refuses cron on a machine that is off", snap.canCronNow, false)
		eq("and root at its glass", snap.canRootLogin, false)
	end

	-- AND ONE SEAM WORTH WRITING DOWN, because it is surprising and it is not this
	-- rule's doing: the disk acts are refused on a machine nobody has ever used, and
	-- the WINDOW'S OWN REFRESH stops that being true. Every snapshot of the Machines
	-- tab asks osState of the selected machine for its detail block, and osState MAKES
	-- a state out of nothing -- which is the same fact the reset's osFresh flag exists
	-- for (docs/DEBUG.md). So after one refresh these two read the fresh machine's own
	-- two factory accounts, which is what the computer would have if somebody switched
	-- it on, and is harmless. What must never happen is the act inventing one ITSELF,
	-- which is why the refusal reads luaObject.os raw and never osState.
	do
		local pristine = net.machine(301, 220, 0, net.shed)
		eq("it has no state", pristine.os, nil)
		check("so the act refuses it",
			CeroSecDebug.accountsRefusal(pristine) ~= nil)
		eq("and asking again did not make one", pristine.os, nil)
		CeroSecDebug.snapshotOf(net.system, "machines", pristine)
		eq("the window's own refresh made one for it", type(pristine.os), "table")
		eq("after which the act is allowed",
			CeroSecDebug.accountsRefusal(pristine), nil)
	end

	-- THE DOOR SHUT. Every one of the eight asks CeroSec.debugAllowed, and with the
	-- flag off and no debug mode around it a forged command is not a refusal: it is
	-- nothing at all.
	local hadFlag = CeroSec.DEV_DEBUG_MENU
	CeroSec.DEV_DEBUG_MENU = false
	eq("the door really is shut", CeroSec.debugAllowed(), false)
	local acts = { "rootnote", "staffnote", "accounts", "clearpass", "anydisk",
		"rootlogin", "cronnow", "forcewire" }
	answers = {}
	for i = 1, #acts do
		net.system:OnClientCommand("debugact", net.player,
			{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = acts[i],
				login = "root", disk = "UTILITIES" })
	end
	eq("not one of the eight answered anything", #answers, 0)
	eq("and nothing was handed over", #inv.items, 0)
	CeroSec.DEV_DEBUG_MENU = hadFlag
end

--
-- 10. THE DOOR AN ADMIN COMES THROUGH (multiplayer)
--
-- A dedicated server has no debug mode -- it is a thing a CLIENT is started with --
-- so with the release flag off nobody could reach this window on a server at all,
-- admin or not. The third condition is the access level of the player the ENGINE
-- handed OnClientCommand, and it is asked of him and never of anything a client sent.
--
do
	local net = newNet()
	local answers = {}
	net.system.reply = function(_, _, cmd, args)
		answers[#answers + 1] = { cmd = cmd, args = args }
	end
	local hadFlag = CeroSec.DEV_DEBUG_MENU
	CeroSec.DEV_DEBUG_MENU = false

	-- The engine's own comparison: IsoPlayer.isAccessLevel is getAccessLevel() and
	-- String.equalsIgnoreCase (javap, offsets 0-8), so a role spelled "Admin" answers
	-- the same as one spelled "admin".
	local function playerAt(level)
		local who = {}
		for key, value in pairs(net.player) do who[key] = value end
		who.getAccessLevel = function() return level end
		who.isAccessLevel = function(_, want)
			return string.lower(level) == string.lower(want)
		end
		return who
	end

	local admin = playerAt("admin")
	eq("an admin is allowed with the flag off and no debug mode",
		CeroSec.debugAllowed(admin), true)
	eq("a player with no role at all is not",
		CeroSec.debugAllowed(playerAt("none")), false)
	eq("and neither is a moderator, which is the narrower of vanilla's two rules",
		CeroSec.debugAllowed(playerAt("moderator")), false)
	eq("a role spelled with a capital is still the admin role",
		CeroSec.debugAllowed(playerAt("Admin")), true)

	-- And the commands answer him. A snapshot for the admin, nothing for the other.
	answers = {}
	net.system:OnClientCommand("debug", admin,
		{ x = 10, y = 10, z = 0, token = "dbg-0-1", tab = "machines" })
	eq("the admin gets his snapshot", #answers, 1)
	eq("on the machines tab", answers[1].args.tab, "machines")

	answers = {}
	net.system:OnClientCommand("debug", playerAt("none"),
		{ x = 10, y = 10, z = 0, token = "dbg-0-1", tab = "machines" })
	eq("and an ordinary player gets nothing", #answers, 0)

	-- An ACT, not only a read: the machine really goes off for the admin and really
	-- does not for anybody else.
	eq("the machine is on", net.here.on, true)
	net.system:OnClientCommand("debugact", playerAt("none"),
		{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "off" })
	eq("an ordinary player's press does nothing", net.here.on, true)
	net.system:OnClientCommand("debugact", admin,
		{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "off" })
	eq("the admin's press switches it off", net.here.on, false)

	-- AND A CLIENT CANNOT SAY SO ITSELF. The level is read off the player object the
	-- engine handed over; a field on args claiming it is not read at all, and this is
	-- the assertion that says so -- an ordinary player sending every spelling of it.
	local liar = playerAt("none")
	net.here:turnOn()
	answers = {}
	net.system:OnClientCommand("debugact", liar,
		{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "off",
			admin = true, accessLevel = "admin", access = "admin",
			level = "admin", isAdmin = true })
	eq("a client that says it is an admin is not one", net.here.on, true)
	eq("and is answered nothing at all", #answers, 0)

	CeroSec.DEV_DEBUG_MENU = hadFlag
end

--
-- THE PREMISES THAT WERE ALREADY AUTOMATED (wave 7e)
--
-- A shop whose lights go out at nine as a survivor walks up to it, before he has
-- touched anything. Three things have to be true at the same time for that and they
-- were each true separately already: the relays are on the switches, the crontab is
-- on the right desk, and the machine is ON. This is the section that proves the
-- three are true AT ONCE, in a real building, through the real hooks.
--
-- WHAT IS ASSERTED, and why each one is here rather than the obvious thing beside
-- it:
--
--   * the hook that FIRES is the NEW one. The game's own distinction between "this
--     square has just been made" and "this square has been read back out of the
--     save" is which of MapObjects' two maps a closure sits in, so the bench fires
--     each map by hand, through the engine's own per-object walk (__fireSquare at
--     the head of this file), and asserts what each one did and did not do.
--   * the decision is in the SAVE and is made once. Asserted on the system's own
--     table, and then asserted again not to move when a second computer of the same
--     premises is created.
--   * the lights are asserted on the SWITCH OBJECT and not on the crontab: a
--     crontab that parses is not a light that went out. The cron pass, the shell,
--     /dev, the discovery and the module modData are all the real ones.
--
do
	local hadZones, hadWorld, hadCell = _G.__zones, _G.getWorld, _G.__world
	local hadSandbox = _G.SandboxVars
	local hadInstance = SCeroSecSystem.instance
	local clock = _G.__gameTime
	local hadHour, hadMin, hadDay = clock.hour, clock.minutes, clock.day
	_G.getWorld = zonedWorld
	_G.__zones = {}
	_G.Perks = { Electricity = "Electricity" }

	-- The rooms of the shop, and they are the map's own words: "clothsstore" reaches
	-- the `store` profile through CeroSecContent.PREMISES_WORDS and "storageroom"
	-- reaches nothing, so the building is a shop with a back room. Named here rather
	-- than inline because the profile the roll is made against has to be the profile
	-- the prefill then builds, and both come off this list.
	local SHOP_ROOMS = { "clothsstore", "storageroom" }
	local SECRET = SCeroSecSystem.BENCH_SECRET

	-- A building corner whose premises rolls the way the bench wants. A SEARCH and
	-- not a number: the roll is a hash of the premises and of the word "auto", so the
	-- honest way to get one of each is to walk the county until one turns up -- which
	-- is what a player walking Knox County does. Not finding one is a red.
	local function cornerRolling(want)
		for i = 0, 400 do
			local bx, by = 7000 + i * 20, 4000 + i * 7
			local b1, b2 = CeroSecOS.buildingKey(bx, by)
			if b1 ~= nil and CeroSecContent.automated(SECRET, b1, b2, "store") == want then
				return bx, by, b1, b2
			end
		end
		return nil
	end

	-- The shop itself. Two rooms, two light switches, the front door onto the street,
	-- a window, and squares for the computers in the back room. Laid out so that the
	-- two lights are the only lights there are, which is what makes them light0 and
	-- light1 -- the very names the store profile's crontab was written with.
	local function newShop(bx, by)
		-- A new world is a new county, and the building cache is keyed on the
		-- building's CORNER: every shop in this section is searched for and the
		-- search answers the same corner every time, so without this the second
		-- shop would be handed the first shop's rooms -- and its RoomDefs, which
		-- answer with the first world's squares. The game does the same thing at
		-- the same moment, for the same reason (CeroSecNet.forgetTenancies).
		CeroSecNet.forgetTenancies()
		local world = FakeWorld.new()
		world.box = { x = bx, y = by, w = 10, h = 10 }
		local kit = { world = world, bx = bx, by = by }
		kit.floor = world.room(SHOP_ROOMS[1], { { bx + 1, by + 1, 0 }, { bx + 2, by + 1, 0 } })
		-- A row of eight squares in the back room, and the row is that long for one
		-- reason: whose desk a machine is is a hash of its own square
		-- (CeroSecContent.ownerSlot), so a bench that wants a desk the hash would NOT
		-- have picked has to have somewhere to look for one.
		local back = {}
		for n = 1, 8 do back[n] = { bx + n, by + 2, 0 } end
		kit.back = world.room(SHOP_ROOMS[2], back)
		-- The street: no room, so the door onto it is the way out of the building and
		-- its lock is a lock that stops somebody (CeroSecModules.doorLocks).
		local street = world.square(bx + 1, by, 0, nil)
		kit.light0 = world.put(world.squares[(bx + 1) .. "," .. (by + 1) .. ",0"],
			fakeLight(true, true))
		kit.light1 = world.put(world.squares[(bx + 2) .. "," .. (by + 1) .. ",0"],
			fakeLight(true, true))
		kit.front = world.put(world.squares[(bx + 1) .. "," .. (by + 1) .. ",0"],
			fakeDoor(true, false, street))
		kit.win0 = world.put(world.squares[(bx + 2) .. "," .. (by + 1) .. ",0"],
			fakeWindow(true, true))
		-- The interior door between the two rooms: a room on both sides, so its lock
		-- stops nobody and a strike on it would be a box that does nothing.
		kit.inner = world.put(world.squares[(bx + 1) .. "," .. (by + 2) .. ",0"],
			fakeDoor(false, true, world.squares[(bx + 1) .. "," .. (by + 1) .. ",0"]))
		return kit
	end

	-- A vanilla computer, as the chunk brings it in: off, facing south, and carrying
	-- the modData an IsoObject carries. The sprite is real and is what MapObjects
	-- dispatches on, and setSpriteFromName is real too, so a machine the server
	-- switches on is a machine whose SPRITE changed -- which is the whole of what a
	-- player sees from the doorway.
	local function fakeComputer()
		local o = fittable({ __class = "IsoObject" })
		o.sprite = CeroSec.SPRITES_OFF["S"]
		o.sprites = 0
		o.getSpriteName = function() return o.sprite end
		o.setSpriteFromName = function(_, name) o.sprite = name end
		o.transmitUpdatedSpriteToClients = function() o.sprites = o.sprites + 1 end
		return o
	end

	-- One county: a real SCeroSecSystem with a real object registry over the fake
	-- world, and the machines put into it the way newNet does -- the GlobalObject
	-- first, because the fake SGlobalObjectSystem.loadIsoObject takes the branch for a
	-- square the server already knows and says so loudly when it cannot.
	local function newCounty(kit)
		CeroSecJobs.machines = {}
		local system = SCeroSecSystem:new()
		-- The save's secret, WRITTEN rather than left to be made: SCeroSecSystem:secret
		-- mixes the millisecond clock into ZombRand, so a fresh system in this file
		-- answers a different sixteen digits every time it is asked and the roll this
		-- whole section searches for could not be searched for. Written the way a LOADED
		-- SAVE hands one over -- the field is what the file holds -- so nothing here
		-- reaches past the door the game uses.
		system.seed = SECRET
		local objects = {}
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
		system.newLuaObjectOnClient = function() end
		system.reply = function() end
		SCeroSecSystem.instance = system

		local county = { system = system, objects = objects, kit = kit }

		function county.machine(x, y, z)
			local square = kit.world.squares[x .. "," .. y .. "," .. (z or 0)]
			local iso = fakeComputer()
			kit.world.put(square, iso)
			local object = SCeroSecObject:new(system, { x = x, y = y, z = z or 0 })
			object.getIsoObject = function() return iso end
			object.getSquare = function() return square end
			object.updateOnClient = function() end
			object:initNew()
			objects[#objects + 1] = object
			object.iso = iso
			object.square = square
			return object
		end

		-- The game's minute hand, which is the only clock the automation and cron have:
		-- Events.EveryOneMinute calls checkPower and then checkCron, in that order, and
		-- the scheduler is what actually steps the jobs cron made.
		function county.minute(times)
			for _ = 1, (times or 1) do
				clock.minutes = clock.minutes + 1
				if clock.minutes >= 60 then
					clock.minutes = 0
					clock.hour = clock.hour + 1
					if clock.hour >= 24 then
						clock.hour = 0
						clock.day = clock.day + 1
					end
				end
				system:checkPower()
				system:checkCron()
				for _ = 1, 8 do
					_G.__now = _G.__now + CeroSec.JOB_PASS_MS
					CeroSecJobs.tick()
				end
			end
		end

		-- Wind the clock to a time of day. FORWARD only: cron's pass keeps the minute
		-- it last saw and does nothing when the clock has not moved past it
		-- (CeroSecJobs.cronPass, `if minute <= last`), which is right on a real machine
		-- and would make a bench that asked for seven in the morning after nine at
		-- night silently prove nothing. So an earlier hour is the NEXT day, which is
		-- what the morning after nine o'clock is.
		function county.at(hour, minute)
			if hour * 60 + minute <= clock.hour * 60 + clock.minutes then
				clock.day = clock.day + 1
			end
			clock.hour, clock.minutes = hour, minute
		end

		return county
	end

	local function pageOf(system, b1, b2)
		if type(system.auto) ~= "table" then return nil end
		return system.auto[CeroSecContent.premisesKey(b1, b2)]
	end

	--
	-- 1. THE HOOK: which of the two maps the mod is on, and what each one does
	--
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = true, PrefilledMachines = true } }
		-- The registration itself, which is what the automation is built on: all four
		-- computer sprites of a facing on BOTH maps, and the closure on `onNew` is not
		-- the closure on `onLoad` -- a mod that registered one function on both could
		-- not tell a new square from a reloaded one at all.
		local news, loads = 0, 0
		for f = 1, #CeroSec.FACINGS do
			local facing = CeroSec.FACINGS[f]
			local off, on = CeroSec.SPRITES_OFF[facing], CeroSec.SPRITES_ON[facing]
			for _, name in ipairs({ off, on }) do
				local newList = _G.__mapObjects.new[name]
				local loadList = _G.__mapObjects.load[name]
				check("the sprite " .. name .. " is registered on OnNewWithSprite",
					type(newList) == "table" and #newList == 1)
				check("and on OnLoadWithSprite",
					type(loadList) == "table" and #loadList == 1)
				check("and the two are not the same closure (" .. name .. ")",
					newList[1] ~= loadList[1])
				news = news + #newList
				loads = loads + #loadList
			end
		end
		eq("eight sprites on each map, no more and no less", news, 8)
		eq("and eight on the other", loads, 8)

		local bx, by, b1, b2 = cornerRolling(true)
		check("some shop in the county rolled automated", bx ~= nil)
		local kit = newShop(bx, by)
		_G.__world = kit.world
		local county = newCounty(kit)

		-- THE DESK THE OWNER HASH WOULD NOT HAVE PICKED, and the bench stands the
		-- machine on it deliberately. The store has two accounts and the nightly job is
		-- the FIRST one's, so a square whose hash picks the second is the only square
		-- where "the job is in his crontab" can tell the automation's own choice of desk
		-- (CeroSecContent.prefill, `want`) from a coincidence -- and on any other square
		-- that assertion is green whether the code asks for the job's desk or not.
		local store = CeroSecContent.PROFILES.store
		local jobSlot = CeroSecContent.jobSlot(store)
		eq("the store's nightly job is the first account's", jobSlot, 1)
		--
		-- Asked of deskRole ITSELF, with a register of its own and no preference in it,
		-- because that is the function the automation then asks with one: a bench that
		-- searched with CeroSecContent.ownerSlot would be searching with the wrong hash
		-- -- deskRole hands out a free slot by key(mkey, "desk") and never calls
		-- ownerSlot at all once there is a register -- and would find a square it had no
		-- reason to believe anything about. (It did, and every mutation of the
		-- preference stayed green on it.)
		local mx, otherSlot = nil, nil
		for n = 1, 8 do
			if mx == nil then
				local mkey = CeroSecContent.machineKey(b1, b2, bx + n, by + 2, 0)
				local probe = CeroSecContent.deskEntry({}, b1, b2)
				local _, had = CeroSecContent.deskRole(probe,
					CeroSecContent.deskTag(bx + n, by + 2, 0), SECRET, mkey, store,
					false, false)
				if had ~= jobSlot then mx, otherSlot = bx + n, had end
			end
		end
		check("a square in the back room is somebody else's desk by the hash", mx ~= nil)
		check("and it is the other account (" .. tostring(otherSlot) .. ")",
			otherSlot ~= nil and otherSlot ~= jobSlot)
		local machine = county.machine(mx, by + 2, 0)

		-- THE LOAD PATH FIRST, which is a chunk read back out of the save. It fires
		-- per object -- the count says so, because a fire that reached nothing would
		-- satisfy every assertion under it -- and it decides nothing and wires nothing.
		eq("the load hook fired once for the one computer on the square",
			_G.__fireSquare("load", machine.square), 1)
		eq("a chunk read back out of the save marks nothing", machine.born, nil)
		eq("and decides nothing about the premises", pageOf(county.system, b1, b2), nil)
		eq("and wires no fixture", CeroSecModules.preFitted(kit.light0), false)
		eq("and leaves the machine off", machine.on, false)
		county.minute()
		eq("and a minute later it has still decided nothing",
			pageOf(county.system, b1, b2), nil)
		eq("and the machine is still off", machine.on, false)

		-- THE NEW PATH, which is the square being made for the first time. One bit, and
		-- ONLY one bit: nothing about the world is asked inside the callback.
		eq("the new hook fires per object too",
			_G.__fireSquare("new", machine.square), 1)
		eq("a square made in this save is marked", machine.born, true)
		eq("and the callback itself decided nothing", pageOf(county.system, b1, b2), nil)
		eq("and wired nothing", CeroSecModules.preFitted(kit.light0), false)
		eq("and switched nothing on", machine.on, false)
		check("and the bit is saved with the machine",
			CeroSecSelfTest.holds(CeroSec.OBJECT_SAVE_KEYS, "born"))

		--
		-- 2. THE SWEEP: the decision, the hardware, and the machine
		--
		county.at(20, 55)
		county.minute()
		local record = pageOf(county.system, b1, b2)
		check("the sweep wrote the premises' page", type(record) == "table")
		eq("and it says the shop was automated", record.on, true)
		check("and which of its computers was left running",
			type(record.machine) == "table" and record.machine.x == mx
				and record.machine.y == by + 2 and record.machine.z == 0)
		eq("the question is not asked again", machine.born, nil)
		eq("and the page is in the save", CeroSecSelfTest.holds(CeroSec.SYSTEM_SAVE_KEYS,
			"auto"), true)

		-- THE HARDWARE. Every fixture of the premises, through the same modData the
		-- install command writes, so the discovery cannot tell it from a player's own.
		eq("the floor switch has its relay",
			CeroSecModules.installedOn(kit.light0).relay, true)
		eq("and so has the sign switch", CeroSecModules.installedOn(kit.light1).relay, true)
		eq("the front door has its contact",
			CeroSecModules.installedOn(kit.front).contact, true)
		eq("and its strike, because its lock stops somebody",
			CeroSecModules.installedOn(kit.front).strike, true)
		eq("the interior door has a contact", CeroSecModules.installedOn(kit.inner).contact,
			true)
		eq("and NO strike, because a lock on it would stop nobody",
			CeroSecModules.installedOn(kit.inner).strike, nil)
		eq("and no operator anywhere: a shop did not open its own doors",
			CeroSecModules.installedOn(kit.front).operator, nil)
		eq("the window has its contact", CeroSecModules.installedOn(kit.win0).contact, true)
		eq("and no strike, there being no lock on a window a machine works",
			CeroSecModules.installedOn(kit.win0).strike, nil)
		eq("every one of them is marked as wired before the outbreak",
			CeroSecModules.preFitted(kit.light0) and CeroSecModules.preFitted(kit.front)
				and CeroSecModules.preFitted(kit.win0), true)
		eq("and the walk knows it saw the whole building", record.wired, true)

		-- THE MACHINE. On, prefilled as the shop, and its SPRITE says so -- which is
		-- the only part of this a player sees before he walks in.
		eq("the machine is on", machine.on, true)
		eq("and the sprite a player sees from the doorway is the lit one",
			machine.iso:getSpriteName(), CeroSec.SPRITES_ON["S"])
		local state = machine:osState()
		check("it has a filesystem", state ~= nil)
		eq("and it came up as the shop", string.match(state.hostname, "^[a-z0-9]+"),
			CeroSecContent.PROFILES.store.host)

		-- THE CRONTAB, and whose it is: the desk of the person whose job the nightly
		-- lights are. Derived here the way a paper in the drawer derives it, so a
		-- prefill that gave the machine somebody else's desk is a red.
		local slot = jobSlot
		local login = CeroSecContent.accountLogin(SECRET, b1, b2, slot)
		check("that account is on the machine", CeroSecOS.getUser(state, login) ~= nil)
		local tab = CeroSecOS.systemNode(state, CeroSecOS.cronPath(login))
		check("and the nightly job is in HIS crontab", tab ~= nil)
		check("with the nine o'clock line in it",
			string.find(tab.data or "", "0 21 * * * sh $HOME/bin/lights.sh light0 light1",
				1, true) ~= nil)
		check("and the morning line beside it",
			string.find(tab.data or "", "0 7 * * * sh $HOME/bin/lamps.sh light0 light1",
				1, true) ~= nil)
		check("and crontab(1) itself accepts the file",
			CeroSecOS.checkCrontab(CeroSecOS.cronPath(login), tab.data) == nil)

		--
		-- 3. NINE O'CLOCK. The lights are asserted on the SWITCH, through the real cron
		-- pass, the real shell, the real /dev and the real discovery.
		--
		eq("the lights are on at five to nine", kit.light0.activated, true)
		county.at(20, 59)
		county.minute()
		eq("at nine the floor light goes out on its own", kit.light0.activated, false)
		eq("and the sign with it", kit.light1.activated, false)
		check("and the world was told about it", kit.light0.syncs > 0)

		-- AND BACK ON IN THE MORNING, which is the other half of a timer.
		county.at(6, 59)
		county.minute()
		eq("at seven the floor light comes back on", kit.light0.activated, true)
		eq("and the sign with it", kit.light1.activated, true)

		--
		-- 4. THE RELAY COMES OFF, AND STAYS OFF
		--
		-- A pre-fitted module is real hardware: it comes off into a survivor's hands and
		-- gives him the item, because the uninstall asks nothing about where it came
		-- from. And the light then stops answering -- which is the reading a player gets
		-- and the reason the mark on the fixture has to outlive the module.
		do
			local inv = newInventory()
			local player = {
				getPlayerNum = function() return 0 end,
				getOnlineID = function() return -1 end,
				isDead = function() return false end,
				playSoundLocal = function() end,
				getCurrentSquare = function() return { getZ = function() return 0 end } end,
				getX = function() return bx + 1.5 end,
				getY = function() return by + 1.5 end,
				getInventory = function() return inv end,
				getPerkLevel = function() return 5 end,
			}
			inv:add("Base.Screwdriver")
			-- The light switch is the SECOND object on that square (the switch went down
			-- before the door), so the index is what tells the two apart.
			local index = nil
			local objects = kit.world.squares[(bx + 1) .. "," .. (by + 1) .. ",0"].objects
			for i = 1, #objects do
				if objects[i] == kit.light0 then index = i - 1 end
			end
			check("the bench can name the floor switch", index ~= nil)
			county.system:OnClientCommand("uninstallmodule", player,
				{ x = bx + 1, y = by + 1, z = 0, index = index, module = "relay" })
			eq("the relay came off", CeroSecModules.installedOn(kit.light0).relay, nil)
			check("and it is a relay in his bag",
				inv:getFirstTypeRecurse("CeroSec.Relay") ~= nil)
			check("and the fixture still remembers it was wired before the outbreak",
				CeroSecModules.preFitted(kit.light0))

			-- The light no longer answers: nine o'clock comes round and the switch with no
			-- relay on it is not a device at all.
			kit.light0.activated = true
			kit.light1.activated = true
			local was = kit.light0.syncs
			county.at(20, 59)
			county.minute()
			eq("the stripped switch is not touched again", kit.light0.activated, true)
			eq("and nothing was broadcast about it", kit.light0.syncs, was)
			eq("while the one still wired goes out", kit.light1.activated, false)

			-- AND THE WALK DOES NOT PUT IT BACK, which is the whole point of the mark: a
			-- second computer of the same shop is created, the sweep walks the building
			-- again, and the switch the survivor stripped is left exactly as he left it.
			local second = county.machine(bx + 8, by + 2, 0)
			record.wired = nil
			eq("the second computer is marked new",
				_G.__fireSquare("new", second.square) > 0 and second.born, true)
			county.minute()
			eq("the shop's page still says what it said", record.on, true)
			check("and still names the FIRST computer",
				record.machine.x == mx and record.machine.y == by + 2)
			eq("and the stripped switch has no relay back on it",
				CeroSecModules.installedOn(kit.light0).relay, nil)
			eq("nor is the second machine switched on", second.on, false)
		end
	end

	--
	-- 5. A SHOP THAT ROLLED THE OTHER WAY
	--
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = true, PrefilledMachines = true } }
		local bx, by, b1, b2 = cornerRolling(false)
		check("some shop in the county rolled the other way", bx ~= nil)
		local kit = newShop(bx, by)
		_G.__world = kit.world
		local county = newCounty(kit)
		local machine = county.machine(bx + 2, by + 2, 0)
		_G.__fireSquare("new", machine.square)
		county.at(20, 59)
		county.minute()
		local record = pageOf(county.system, b1, b2)
		check("the premises was asked", type(record) == "table")
		eq("and the answer is written down as a no", record.on, false)
		eq("no fixture is wired", CeroSecModules.preFitted(kit.light0), false)
		eq("no module went on", CeroSecModules.installedOn(kit.light0).relay, nil)
		eq("the machine stays off", machine.on, false)
		eq("and the lights stay on", kit.light0.activated, true)
		eq("and the question is not asked again", machine.born, nil)

		-- AND THE SURVIVOR SWITCHES IT ON HIMSELF, which is what he does with every
		-- computer he finds. From that minute on it is a machine that is ON in a
		-- premises nobody automated, which is the one case the sweep's own walk has to
		-- refuse -- and the only case that reaches the question it asks, every other
		-- machine in this section being dark.
		machine:turnOn()
		eq("the machine he found comes up", machine.on, true)
		county.minute(2)
		eq("a shop nobody automated grows no relays",
			CeroSecModules.installedOn(kit.light0).relay, nil)
		eq("nor contacts on its doors", CeroSecModules.installedOn(kit.front).contact, nil)
		eq("and it is still not marked as wired", record.wired, nil)
		eq("and its lights are his to throw", kit.light0.activated, true)
	end

	--
	-- 6. A SHOP WITH NO POWER. No grid, no automation -- and the hardware is fitted
	-- anyway, because a grid that went down does not unscrew a relay.
	--
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = true, PrefilledMachines = true } }
		local bx, by = cornerRolling(true)
		local kit = newShop(bx, by)
		kit.world.power = false
		_G.__world = kit.world
		local county = newCounty(kit)
		local machine = county.machine(bx + 2, by + 2, 0)
		_G.__fireSquare("new", machine.square)
		county.at(20, 59)
		county.minute()
		eq("a machine with no wire at its square stays off", machine.on, false)
		eq("it has no filesystem at all", machine.os, nil)
		eq("and nothing fired at nine", kit.light0.activated, true)
		eq("but the relay is on the switch", CeroSecModules.installedOn(kit.light0).relay,
			true)
	end

	--
	-- 7. THE OPTION OFF, which is the control: the world this mod shipped with.
	--
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = true, PrefilledMachines = false } }
		local bx, by, b1, b2 = cornerRolling(true)
		local kit = newShop(bx, by)
		_G.__world = kit.world
		local county = newCounty(kit)
		local machine = county.machine(bx + 2, by + 2, 0)
		_G.__fireSquare("new", machine.square)
		county.at(20, 59)
		county.minute()
		eq("with PrefilledMachines off no premises is asked at all",
			pageOf(county.system, b1, b2), nil)
		eq("nothing is wired", CeroSecModules.preFitted(kit.light0), false)
		eq("the machine stays off", machine.on, false)
		eq("the lights stay on", kit.light0.activated, true)
		eq("and the question is not asked again", machine.born, nil)
	end

	--
	-- 8. A HOUSE IS NEVER AUTOMATED, and it is not on a list of exceptions: a
	-- residential profile has no crontab in it, so there is no nightly job to leave
	-- running (CeroSecContent.hasJob). Asked of every profile the catalogue ships, so
	-- that a profile which loses its crontab stops being a candidate on its own.
	--
	do
		eq("a house has no nightly job", CeroSecContent.hasJob("residential"), false)
		local ids = CeroSecContent.PROFILE_IDS
		local with, without = 0, 0
		for i = 1, #ids do
			local id = ids[i]
			if CeroSecContent.hasJob(id) then with = with + 1 else without = without + 1 end
			-- And the roll can only ever say yes to one that has a job. Walked over a
			-- spread of premises, because one pair of bytes proves nothing about a hash.
			for n = 0, 40 do
				local b1, b2 = CeroSecOS.buildingKey(6000 + n * 13, 3000 + n * 29)
				if CeroSecContent.automated(SECRET, b1, b2, id) then
					check("only a profile with a nightly job is ever automated (" .. id .. ")",
						CeroSecContent.hasJob(id))
				end
			end
		end
		check("most of the catalogue has a job (" .. with .. ")", with >= 9)
		eq("and the house is the one that has none", without, 1)

		-- ABOUT ONE IN THREE, counted over the county rather than asserted as a
		-- constant: a roll that always said yes and a roll that always said no would
		-- both satisfy every "the shop was automated" assertion above, one of them by
		-- automating Knox County entirely.
		local yes, total = 0, 0
		for n = 0, 299 do
			local b1, b2 = CeroSecOS.buildingKey(5000 + n * 17, 8000 + n * 11)
			total = total + 1
			if CeroSecContent.automated(SECRET, b1, b2, "store") then yes = yes + 1 end
		end
		check("about a third of the shops are automated (" .. yes .. " of " .. total .. ")",
			yes > total / 6 and yes < total / 2)
	end

	--
	-- 9. A DISPLAY MODEL IS NEVER THE MACHINE THAT WAS LEFT RUNNING, and the shop's
	-- own back-room machine takes the slot when it turns up -- in either order, which
	-- is what "as their chunks arrive" means.
	--
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = true, PrefilledMachines = true } }
		-- A shop that SELLS computers: the sales floor and the back room, as the map
		-- spells them (CeroSecContent.FLOOR_ROOMS).
		local bx, by, b1, b2 = nil, nil, nil, nil
		for i = 0, 400 do
			local x, y = 9000 + i * 20, 2000 + i * 9
			local k1, k2 = CeroSecOS.buildingKey(x, y)
			if k1 ~= nil and CeroSecContent.automated(SECRET, k1, k2, "showroom") then
				bx, by, b1, b2 = x, y, k1, k2
				break
			end
		end
		check("some electronics shop rolled automated", bx ~= nil)

		local world = FakeWorld.new()
		world.box = { x = bx, y = by, w = 10, h = 10 }
		world.room("electronicsstore", { { bx + 1, by + 1, 0 } })
		world.room("electronicsstorage", { { bx + 1, by + 2, 0 } })
		local kit = { world = world }
		kit.light0 = world.put(world.squares[(bx + 1) .. "," .. (by + 1) .. ",0"],
			fakeLight(true, true))
		_G.__world = world
		local county = newCounty(kit)

		-- The machine in the WINDOW first, which is the order that matters: it must not
		-- take the slot, and the premises must still be decided.
		local model = county.machine(bx + 1, by + 1, 0)
		_G.__fireSquare("new", model.square)
		county.minute()
		local record = pageOf(county.system, b1, b2)
		check("the shop was asked", type(record) == "table")
		eq("and it was automated", record.on, true)
		eq("but no machine carries it yet", record.machine, nil)
		eq("the display model stays off", model.on, false)

		-- Then the one in the back room, which is the shop's own.
		local back = county.machine(bx + 1, by + 2, 0)
		_G.__fireSquare("new", back.square)
		county.minute()
		check("the back-room machine takes the slot",
			type(record.machine) == "table" and record.machine.y == by + 2)
		eq("and it is the one that was left running", back.on, true)
		eq("the display model is still off", model.on, false)
		eq("and it came up as the shop and not as the dealer's disk",
			string.match(back:osState().hostname, "^[a-z0-9]+"),
			CeroSecContent.PROFILES.showroom.host)
	end

	--
	-- 10. IN ANY CHUNK ORDER. A room of the building whose chunks are away answers no
	-- live room at all, so the walk cannot see its fixtures -- and has to come back for
	-- them, once, and then stop coming back.
	--
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = true, PrefilledMachines = true } }
		local bx, by, b1, b2 = cornerRolling(true)
		local kit = newShop(bx, by)
		_G.__world = kit.world
		-- The shop floor is not in the world yet: the survivor came in the back way.
		kit.floor.away = true
		local county = newCounty(kit)
		local machine = county.machine(bx + 2, by + 2, 0)
		_G.__fireSquare("new", machine.square)
		county.minute()
		local record = pageOf(county.system, b1, b2)
		eq("the shop was automated", record.on, true)
		eq("the back room's door got its contact",
			CeroSecModules.installedOn(kit.inner).contact, true)
		eq("the floor's switch did not, its room being away",
			CeroSecModules.installedOn(kit.light0).relay, nil)
		eq("and the walk does not call itself finished", record.wired, nil)

		-- The floor arrives.
		kit.floor.away = nil
		county.minute()
		eq("the floor switch gets its relay when its chunks come in",
			CeroSecModules.installedOn(kit.light0).relay, true)
		eq("and the sign switch with it", CeroSecModules.installedOn(kit.light1).relay,
			true)
		eq("and now the walk is finished", record.wired, true)

		-- And finished means finished: a module taken off after that is a module that
		-- stays off, which is the state a survivor leaves a building in.
		CeroSecModules.setOn(kit.light1, "relay", false)
		county.minute(2)
		eq("a relay taken off a finished premises is not put back",
			CeroSecModules.installedOn(kit.light1).relay, nil)
	end

	--
	-- 11. A MACHINE IN NO BUILDING -- a player's own base -- is never automated, and
	-- is never asked twice about it.
	--
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = true, PrefilledMachines = true } }
		local world = FakeWorld.new()
		-- No room, so no building: the square is the outdoors.
		local square = world.square(3000, 3000, 0, nil)
		local kit = { world = world }
		_G.__world = world
		local county = newCounty(kit)
		local machine = county.machine(3000, 3000, 0)
		_G.__fireSquare("new", square)
		eq("the computer is marked new", machine.born, true)
		county.minute()
		eq("a base is not a premises and is not asked again", machine.born, nil)
		eq("nothing was written for it", county.system.auto ~= nil
			and next(county.system.auto) or nil, nil)
		eq("and it stays off", machine.on, false)
	end

	--
	-- 12. A FIVE-HUNDRED-ROOM MALL, WHOSE CHUNKS NEVER ALL ARRIVE AT ONCE
	--
	-- The defect this bench owns, in one sentence: the pre-fitting walked the WHOLE
	-- building every game minute and only ever called itself finished on a pass where
	-- every room of it answered a live room TOGETHER -- which on a mall no player's
	-- chunk radius covers is a pass that never comes, so the mall was re-walked room
	-- by room, square by square, object by object, every minute for as long as the
	-- carrier machine was on, and independently for every automated premises in it.
	--
	-- The mall here is the shape of the shipped ones in miniature: thirty shops of
	-- sixteen rooms each and twenty halls, five hundred rooms, a thousand squares, a
	-- light switch on every one of them. The streamer rolls -- twenty rooms in the
	-- world at a time and twenty DIFFERENT ones every minute -- so the old walk could
	-- not finish here at all and the new one has to finish without ever seeing the
	-- building whole.
	--
	-- What is asserted is the COUNT OF ENGINE CALLS and not a clock: what was wrong
	-- was the number of squares and objects handed over, a bench that timed it would
	-- be timing this machine, and the fake counts both (FakeWorld's `visits`).
	--
	do
		_G.SandboxVars = { CeroSec = { HardwareRequired = true, PrefilledMachines = true } }
		local SHOPS, PER_SHOP, HALLS = 30, 16, 20
		local SQUARES_PER_ROOM = 2
		local CARRIER = 3
		-- Every shop wears the same name, and they are still thirty tenancies: two
		-- rooms of one name are one shop only where they share a WALL, and the shops
		-- are laid out a tile apart (CeroSecNet.tenancies).
		local TRADE = "clothsstore"

		-- The corner of the shop that carries the timer is its room nearest the
		-- origin, which is the tenancy's anchor and therefore the premises' own key
		-- (CeroSecNet.tenancyAnchor). Searched for, like every other roll in this
		-- section: the honest way to get a mall whose third shop was automated is to
		-- walk the county until one turns up.
		local function mallRolling()
			for i = 0, 400 do
				local bx, by = 9000 + i * 23, 5000 + i * 11
				local b1, b2 = CeroSecOS.roomKey(bx, by, bx + CARRIER * 3, by, 0)
				if b1 ~= nil and CeroSecContent.automated(SECRET, b1, b2, "store") then
					return bx, by, b1, b2
				end
			end
			return nil
		end
		local bx, by, b1, b2 = mallRolling()
		check("some mall in the county has an automated shop in it", bx ~= nil)

		CeroSecNet.forgetTenancies()
		local world = FakeWorld.new()
		world.box = { x = bx, y = by, w = 200, h = 200 }
		-- Nothing is in the world to begin with: the survivor is walking up to it.
		world.loaded = true
		local lights = {}
		for s = 0, SHOPS - 1 do
			lights[s] = {}
			for r = 0, PER_SHOP - 1 do
				local x0, y0 = bx + s * 3, by + r
				local room = world.room(TRADE, { { x0, y0, 0 }, { x0 + 1, y0, 0 } })
				room.away = true
				-- A switch on each of its two squares, so what a walked room costs is
				-- two squares and two objects and the arithmetic below is the room's.
				lights[s][r] = {
					world.put(world.squares[x0 .. "," .. y0 .. ",0"], fakeLight(true, true)),
					world.put(world.squares[(x0 + 1) .. "," .. y0 .. ",0"],
						fakeLight(true, true)),
				}
			end
		end
		-- The common parts, which are nobody's and are never any premises' rooms.
		for h = 1, HALLS do
			local x0, y0 = bx + 150, by + h
			local room = world.room("hall" .. h, { { x0, y0, 0 }, { x0 + 1, y0, 0 } })
			room.away = true
			world.put(world.squares[x0 .. "," .. y0 .. ",0"], fakeLight(true, true))
			world.put(world.squares[(x0 + 1) .. "," .. y0 .. ",0"], fakeLight(true, true))
		end
		local order = world.roomOrder
		eq("the mall has five hundred rooms", #order, SHOPS * PER_SHOP + HALLS)

		-- THE RULE FIRST: thirty shops and not one, and not five hundred. Asserted
		-- because every count below would be green on a mall the rule read as one
		-- premises -- which is the bug premises v2 was written for.
		local groups = CeroSecNet.tenanciesOf(world.building:getDef())
		eq("and thirty tenancies in it", #groups, SHOPS)

		_G.__world = world
		local county = newCounty({ world = world })
		-- The carrier's own machine, on the second square of its shop's first room.
		local machine = county.machine(bx + CARRIER * 3 + 1, by, 0)

		-- The streamer: twenty rooms live, rolling by twenty a minute, so the mall is
		-- never in the world at once and each room comes back only after a full turn
		-- of the building. The shops were created one after the other, so a window
		-- lands mostly inside ONE shop -- which is what makes a minute where more of
		-- this premises' rooms are live than the cap allows, and that minute is the
		-- one the per-minute assertion below is about.
		local LIVE = 20
		local function stream(minute)
			local n = #order
			for i = 1, n do order[i].away = true end
			local first = ((minute - 1) * LIVE) % n
			for k = 0, LIVE - 1 do order[(first + k) % n + 1].away = nil end
		end

		-- A quiet hour: the store's crontab fires at nine at night and seven in the
		-- morning, and a line that reaches for /dev walks the building itself
		-- (CeroSecDevices.find) -- which would be a second walk in the counts below.
		county.at(2, 0)
		stream(1)
		_G.__fireSquare("new", machine.square)
		world.forgetVisits()
		county.minute()
		local record = pageOf(county.system, b1, b2)
		check("the mall's third shop was automated", type(record) == "table"
			and record.on == true)
		eq("and its machine is the one that was left running", record.machine.x,
			bx + CARRIER * 3 + 1)
		eq("the first minute did not call the premises finished", record.wired, nil)

		-- THE MINUTES. Every one of them measured on its own, so the assertion is
		-- about the worst minute and not about an average that a cheap minute pays for.
		local worstSquares, worstObjects = 0, 0
		local totalSquares, totalObjects = world.visits.squares, world.visits.objects
		local wiredAt = record.wired and 1 or nil
		local seenAt5 = nil
		for m = 2, 40 do
			stream(m)
			world.forgetVisits()
			county.minute()
			local sq, ob = world.visits.squares, world.visits.objects
			if sq > worstSquares then worstSquares = sq end
			if ob > worstObjects then worstObjects = ob end
			totalSquares, totalObjects = totalSquares + sq, totalObjects + ob
			if m == 5 then seenAt5 = record.wired end
			if wiredAt == nil and record.wired == true then wiredAt = m end
		end

		-- (i) NO MINUTE COSTS MORE THAN THE CAP, which is the whole of the fix.
		-- Equality and not "under": a bench where the cap was never reached would be
		-- green on a walk with no cap in it at all, and the streaming above is
		-- arranged so that one minute really does have more of this premises' rooms
		-- in the world than it is allowed to walk.
		eq("the worst minute walks exactly the cap's worth of rooms (" ..
			worstSquares .. " squares)",
			worstSquares, CeroSecAuto.ROOMS_PER_MINUTE * SQUARES_PER_ROOM)
		check("and no minute looked at more objects than that (" .. worstObjects .. ")",
			worstObjects <= CeroSecAuto.ROOMS_PER_MINUTE * SQUARES_PER_ROOM + 1)

		-- (ii) NO ROOM IS WALKED TWICE. The premises has sixteen rooms of two squares,
		-- so the whole of the wiring costs thirty-two squares -- ONCE, over the forty
		-- minutes -- and one object per square plus the computer standing on its own.
		eq("the whole wiring cost the premises' rooms and no more (" ..
			totalSquares .. " squares over " .. #order .. " rooms of mall)",
			totalSquares, PER_SHOP * SQUARES_PER_ROOM)
		eq("and one object a square, plus the computer on its own square (" ..
			totalObjects .. ")", totalObjects, PER_SHOP * SQUARES_PER_ROOM + 1)

		-- (iii) IT CONVERGES, in a bounded number of minutes, and not on the first
		-- one: a premises that called itself finished before its rooms had arrived
		-- would leave a shop with half its relays for ever. More than one turn of the
		-- streamer, because the cap defers rooms it saw and may not walk and the set
		-- is what brings it back to them.
		check("the premises finishes wiring itself (minute " .. tostring(wiredAt) .. ")",
			wiredAt ~= nil)
		check("and it took more than one turn of the streamer to do it",
			wiredAt ~= nil and wiredAt > 5)
		eq("so it was not finished at minute five", seenAt5, nil)
		eq("and the room set is dropped the minute it is", record.rooms, nil)

		-- (iv) AND THE OTHER TWENTY-NINE SHOPS ARE UNTOUCHED. The premises' own
		-- sixteen rooms are wired, and nothing else in the mall is: a mall wired
		-- because one shop of it had a timer would be relays in twenty-nine other
		-- people's premises.
		local mineFitted, mineBare = 0, 0
		for r = 0, PER_SHOP - 1 do
			for i = 1, SQUARES_PER_ROOM do
				if CeroSecModules.installedOn(lights[CARRIER][r][i]).relay == true then
					mineFitted = mineFitted + 1
				else
					mineBare = mineBare + 1
				end
			end
		end
		eq("every switch of the automated shop has its relay",
			mineFitted, PER_SHOP * SQUARES_PER_ROOM)
		eq("and not one of them was missed", mineBare, 0)
		local elsewhere = 0
		for s = 0, SHOPS - 1 do
			if s ~= CARRIER then
				for r = 0, PER_SHOP - 1 do
					for i = 1, SQUARES_PER_ROOM do
						if CeroSecModules.installedOn(lights[s][r][i]).relay ~= nil then
							elsewhere = elsewhere + 1
						end
					end
				end
			end
		end
		eq("and no other shop in the mall grew one", elsewhere, 0)
	end

	_G.__zones, _G.getWorld, _G.__world = hadZones, hadWorld, hadCell
	_G.SandboxVars = hadSandbox
	SCeroSecSystem.instance = hadInstance
	clock.hour, clock.minutes, clock.day = hadHour, hadMin, hadDay
end

-- Sending at the glass: the body typed, and Escape giving up on it
--
-- LAST IN THE FILE on purpose. Run where it belongs -- beside the cron and mail
-- benches above -- it turns the mall-password bench near the end of this file
-- red: "the music store's paper does not open the clothes shop". Each HALF of
-- this block run there is green, and so is a probe bench that logs in, makes an
-- account or advances the clock by any number of lines, so what that bench
-- depends on is something cumulative this pair of sends crosses and neither half
-- reaches. Worth pinning down by whoever owns that bench -- a bench whose
-- assertions depend on what ran before it is a bench that will go red for
-- somebody's unrelated change -- and it is not what this block is about.
--
-- The engine's half of this is benched in os_test (nothing is written until the
-- dot). This is the half only a console can prove: Escape at mail's own bare
-- prompt is the ^C of a 1993 terminal, the question goes off the machine, the
-- shell comes back -- and no mailbox was touched on the way.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("sudo useradd bob")
	bench.frame()
	bench.enter("")
	bench.frame()
	check("bob exists to send to", bench.painted("useradd: bob: created"))
	eq("and has no mailbox yet", bench.fileText("/var/mail/bob"), nil)

	bench.enter("mail -s Note bob")
	bench.frame()
	-- mail(1) prints nothing while a body is being typed, so the prompt is bare.
	eq("mail asks for a body with no prompt of its own", bench.window.prompt, "")
	eq("and the machine is in the middle of something", bench.window.active, true)
	eq("the body is not masked", bench.window.mask, false)
	bench.enter("the lights are off")
	bench.frame()
	bench.enter("and the door is locked")
	bench.frame()
	eq("two lines typed and nothing delivered", bench.fileText("/var/mail/bob"), nil)
	eq("and it is still asking", bench.window.prompt, "")

	bench.window:onOtherKey(Keyboard.KEY_ESCAPE)
	bench.frame()
	check("the window is still open", not bench.window.closing)
	eq("the question is off the machine", bench.object.console.prompt, nil)
	eq("and the shell is back", bench.window.mode, "shell")
	eq("nothing is going on any more", bench.window.active, false)
	eq("and the message was never sent", bench.fileText("/var/mail/bob"), nil)

	-- The same body again, ended with the dot this time.
	bench.enter("mail -s Note bob")
	bench.frame()
	bench.enter("the lights are off")
	bench.frame()
	bench.enter(".")
	bench.frame()
	eq("the dot gave the prompt back", bench.window.mode, "shell")
	local box = bench.fileText("/var/mail/bob")
	check("and this one was delivered", box ~= nil)
	check("with the subject", box ~= nil and
		string.find(box, "Subject: Note", 1, true) ~= nil)
	check("and the body", box ~= nil and
		string.find(box, "the lights are off", 1, true) ~= nil)
	check("and not the dot", box == nil or
		string.find(box, "\n.\n", 1, true) == nil)
end

--
-- A script's output follows the redirect of the line that started it, ON THE
-- GLASS (debts 2).
--
-- os_test proves the file; this proves the SCREEN, which is the half that was
-- wrong: the redirect belonged to the word `sh`, so the script's lines came out on
-- the console while the file stayed empty. A bench that only read the file would be
-- green on a machine that wrote it AND printed it.
--
do
	local bench = newBench()
	bench.login("admin")
	-- Words nothing else on the glass carries: `painted` looks for a substring, and
	-- a script called two.sh would match its own name in the echoed command line.
	bench.script("/home/admin/pair.sh", "echo alpha\necho beta\n")

	bench.enter("sh pair.sh > out")
	bench.tick(30)
	bench.frame()
	eq("nothing of the script reached the glass", bench.painted("alpha"), false)
	eq("and neither did its second line", bench.painted("beta"), false)
	eq("the file has it", bench.fileText("/home/admin/out"), "alpha\nbeta")

	-- And with no redirect on the line the very same script paints, so the
	-- assertion above is about the redirect and not about a script that never ran.
	bench.enter("sh pair.sh")
	bench.tick(30)
	bench.frame()
	eq("the same script paints when nothing took the screen away",
		bench.painted("alpha"), true)

	-- A refusal inside a redirected script still reaches the glass, because a
	-- refusal is not output.
	bench.script("/home/admin/err.sh", "echo good\nls /nope\n")
	bench.enter("sh err.sh > eout")
	bench.tick(30)
	bench.frame()
	eq("the refusal is on the screen", bench.painted("/nope: no such file"), true)
	eq("and the file holds only what was printed",
		bench.fileText("/home/admin/eout"), "good")
end

--
-- Shell functions at the glass: the console keeps one, and keeps it as TEXT
-- (debts 2).
--
-- os_test proves what a function does; this proves that the CONSOLE holds it -- a
-- definition typed on one line is found by the next, and survives the window being
-- closed and opened again, because it is the machine that keeps it and not the
-- window.
--
do
	local bench = newBench()
	bench.login("admin")

	bench.enter("greet() { echo hello $1; }")
	bench.tick(10)
	bench.frame()
	-- Kept as the TEXT of the definition, which is what may be written to a save
	-- file: a body is nested tables, and nothing player-controlled is handed back out
	-- of modData and then run.
	eq("the console holds the text of it",
		bench.object:consoleState().shfuncs.greet, "greet() { echo hello $1; }")

	bench.enter("greet world")
	bench.tick(10)
	bench.frame()
	eq("and the next line finds it", bench.painted("hello world"), true)

	-- The window closed and opened again is a different window on the same machine,
	-- so the function is still there.
	local fresh = bench.reopen()
	bench.enterOn(fresh, "greet again")
	bench.tick(10)
	bench.frame()
	eq("a new window on the same machine still has it",
		bench.paintedOn(fresh, "hello again"), true)

	-- A logout takes it, the way it takes the variables: somebody walking up to a
	-- logged-out machine gets a shell, not the last one's.
	bench.enterOn(fresh, "exit")
	bench.tick(5)
	bench.frame()
	eq("a logout took the functions with the session",
		bench.object:consoleState().shfuncs, nil)
end

--
-- The console handed back by the game: a function survives the round trip, and a
-- forged one cannot smuggle anything through it.
--
do
	local held = CeroSec.repairConsole({
		lines = {},
		shfuncs = {
			greet = "greet() { echo hi; }",
			spaced = "spaced () { echo hi; }",
			-- Every one of these is dropped, and each for its own reason.
			["not a name"] = "x() { :; }",
			wrong = "other() { echo no; }",
			bell = "bell() { echo " .. string.char(7) .. "; }",
			big = "big() { echo " .. string.rep("y", CeroSecOS.MAX_FUNC_BYTES) .. "; }",
			notext = 7,
		},
	})
	eq("the two that are functions survive", #CeroSecOS.funcNames(held.shfuncs), 2)
	eq("kept as the text they were written as", held.shfuncs.greet,
		"greet() { echo hi; }")
	eq("the blank-before-brackets spelling too", held.shfuncs.spaced,
		"spaced () { echo hi; }")
	eq("a name that is not a name is dropped", held.shfuncs["not a name"], nil)
	-- The one check that is this table's own: text that declares another name would
	-- be a function answering to the wrong word.
	eq("text that declares another name is dropped", held.shfuncs.wrong, nil)
	eq("a control byte in the text is dropped", held.shfuncs.bell, nil)
	eq("text past the ceiling is dropped", held.shfuncs.big, nil)
	eq("a value that is not text is dropped", held.shfuncs.notext, nil)

	-- A forged console cannot hand back a thousand of them.
	local many = { lines = {}, shfuncs = {} }
	for i = 1, CeroSecOS.MAX_FUNCS * 4 do
		many.shfuncs["f" .. i] = "f" .. i .. "() { echo " .. i .. "; }"
	end
	eq("and no more of them than a shell may hold",
		#CeroSecOS.funcNames(CeroSec.repairConsole(many).shfuncs), CeroSecOS.MAX_FUNCS)
	eq("a fresh console holds none, and a table to put them in",
		#CeroSecOS.funcNames(CeroSec.newConsole().shfuncs), 0)
end

--
-- wall: a line on EVERY terminal of the machine (debts 2).
--
-- os_test proves the order and its wording; this proves the delivery, which is the
-- half only the machine can do. Two windows at the same glass, and then a session
-- that came in over the wire -- a survivor logged in from the gate is exactly the
-- person a "lights out in five" is for, and a broadcast that missed him would be a
-- broadcast that missed the one who cannot see the room.
--
do
	local bench = newBench()
	bench.login("admin")
	local second = bench.addWindow()
	second:askForScreen()
	_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
	bench.frame()

	bench.enter("echo lights out in five | wall")
	bench.tick(10)
	bench.frame()
	eq("the banner is on the glass it was typed at",
		bench.painted("Broadcast Message from admin@"), true)
	eq("with the line and the time", bench.painted("(console) at"), true)
	eq("and the text under it", bench.painted("lights out in five"), true)
	-- The SECOND window is the half that says it is a broadcast: it typed nothing.
	eq("and on the other window at the same glass",
		bench.paintedOn(second, "Broadcast Message from admin@"), true)
	eq("with the text", bench.paintedOn(second, "lights out in five"), true)
	-- wall itself printed nothing where it was typed: what reached the glass is the
	-- broadcast, once, and not a copy beside it.
	local seen = 0
	for i = 1, #bench.object:consoleState().lines do
		if bench.object:consoleState().lines[i] == "lights out in five" then
			seen = seen + 1
		end
	end
	eq("the text is on the machine's screen exactly once", seen, 1)

	-- And the shape this whole fix is about: a broadcast with a statement AFTER
	-- it. wall(1) is an ordinary program and the line goes on past it, so the
	-- order is queued on the job and the pass carries it out (CeroSecOSVM's
	-- machineOrder, SCeroSecJobs.runMachine). Until this, the order was the job's
	-- LAST word -- which is exactly why every broadcast benched above is written
	-- at the end of its line, and why nothing here went red while `echo before;
	-- wall f; echo after` printed only `before`.
	bench.enter("echo save your work | wall; echo sent")
	bench.tick(10)
	bench.frame()
	eq("the statement after the broadcast ran", bench.painted("sent"), true)
	eq("and the broadcast went out all the same",
		bench.painted("save your work"), true)
	eq("on the other window at the same glass too",
		bench.paintedOn(second, "save your work"), true)

	-- A file named on the line, with a statement after it, and the order STILL
	-- in its place: the broadcast is on the screen above the line that follows it,
	-- because the job does not step again until the pass has taken the order.
	bench.enter("clear")
	bench.tick(4)
	CeroSecOS.writeFile(bench.object:osState(), CeroSecOS.rootSession(),
		"/home/admin/notice", "the doors lock at six", false, 100)
	bench.enter("wall /home/admin/notice; echo after")
	bench.tick(10)
	bench.frame()
	local lines = bench.object:consoleState().lines
	local broadcastAt, afterAt = nil, nil
	for i = 1, #lines do
		if lines[i] == "the doors lock at six" then broadcastAt = i end
		if lines[i] == "after" then afterAt = i end
	end
	check("the broadcast is on the screen", broadcastAt ~= nil)
	check("and so is the line after it", afterAt ~= nil)
	check("in that order, which is the order they were written in",
		broadcastAt ~= nil and afterAt ~= nil and broadcastAt < afterAt)
end

-- A CRONTAB line that broadcasts, and the statement after it (debts 2).
--
-- The case with nobody in front of it, and the one the defect hurt most: a
-- broadcast from cron is 4.4BSD's own way of warning a machine, and until this
-- the line died at its own `wall` -- everything after it was thrown away, in
-- silence, on a machine nobody was watching.
do
	local bench = newBench()
	bench.login("admin")
	CeroSecOS.writeFile(bench.object:osState(), CeroSecOS.rootSession(),
		"/var/spool/cron/admin", "* * * * * wall /etc/motd; echo done", false, 100)
	bench.enter("clear")
	bench.frame()

	-- The minute the machine came into view is not a minute it was there for.
	bench.minute()
	eq("nothing ran for the minute it arrived in", bench.fileText("/var/mail/admin"), nil)

	bench.minute()
	bench.frame()
	check("the broadcast reached the glass nobody is at",
		bench.painted("Broadcast Message from admin@"))
	local mail = bench.fileText("/var/mail/admin")
	check("the line after the broadcast ran", mail ~= nil)
	check("and what it printed is in the mail, where a cron line's output goes",
		mail ~= nil and string.find(mail, "done", 1, true) ~= nil)
	check("and not on the glass", not bench.painted("done"))
end

do
	local net = newNet()
	net.name(net.here, net.gate, "gate")
	net.login("admin")
	net.enter("rlogin gate")
	net.tick(2)
	net.enter("admin")
	net.enter("")
	net.tick(2)
	check("the session is up", net.glass("admin@" .. net.host(net.gate)))
	eq("and the far machine has a pty", CeroSecOS.ptyCount(net.gate.ptys), 1)

	-- Broadcast on the FAR machine, from the session. It has to reach the pty's own
	-- screen -- which is this window -- and the far machine's own console, where
	-- nobody is standing at all.
	net.forget()
	net.enter("echo the lights go off | wall")
	net.tick(4)
	net.frame()
	check("the broadcast reached the session's screen",
		net.glass("Broadcast Message from admin@" .. net.host(net.gate)))
	check("with the text", net.glass("the lights go off"))
	local own = net.gate:consoleState()
	local onGlass, onOwn = false, false
	for i = 1, #own.lines do
		if string.find(own.lines[i], "Broadcast Message from admin@", 1, true) then
			onOwn = true
		end
		if own.lines[i] == "the lights go off" then onGlass = true end
	end
	check("and the far machine's own console has it too", onOwn)
	check("with the text", onGlass)

	-- The same thing with a statement AFTER it, which is the shape that used to
	-- cost the rest of the line. Down a session it costs more than a line: the pty
	-- is a shell somebody is holding, and a job that ended at its own broadcast
	-- left the far prompt to come back with everything after the `wall` unrun.
	net.forget()
	net.enter("wall /etc/motd; echo after")
	net.tick(4)
	net.frame()
	check("the statement after the broadcast ran in the session",
		net.glass("after"))
	check("and the broadcast is on the session's screen",
		net.glass("Broadcast Message from admin@" .. net.host(net.gate)))
	local second = net.gate:consoleState()
	local againOnOwn = false
	for i = 1, #second.lines do
		if string.find(second.lines[i], "Broadcast Message from admin@", 1, true) then
			againOnOwn = true
		end
	end
	check("and on the far machine's own console, as a broadcast must be", againOnOwn)
end

--
-- 55. Reading ONE FILE back for the pane (the Files tab's double-click)
--
-- The wire from the double-click to the bytes: a `readfile` act through the real
-- OnClientCommand door, and what comes back read off the reply. What is asserted is
-- the TEXT -- the lines a file really holds, the cap with its own last line, the two
-- notations a byte that cannot be printed is shown in -- and then every refusal the
-- path can earn, and then the door shut, which answers nothing.
--
do
	local net = newNet()
	-- The machine the harness already has, and its state as the act itself reads it:
	-- `readfile` is a READ and asks nothing about the power, because a disk is a disk
	-- whether the screen is lit or not -- which is the same rule the reset wears.
	local machine = net.here
	local state = machine:osState()
	check("the machine has a filesystem", type(state.fs) == "table")

	local answers = {}
	net.system.reply = function(_, _, cmd, args)
		answers[#answers + 1] = { cmd = cmd, args = args }
	end
	local function ask(path)
		answers = {}
		net.system:OnClientCommand("debugact", net.player,
			{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "readfile", path = path })
		return answers[1]
	end

	-- A file of the player's own, written through the machine's own door so that what
	-- is read back is a file the engine really holds.
	local session = CeroSecOS.rootSession()
	eq("a file is written", CeroSecOS.writeFile(state, session, "/root/notes.txt",
		"one\ntwo\nthree\n", false, 0) ~= nil, true)

	local got = ask("/root/notes.txt")
	check("the server answered", got ~= nil)
	eq("on the same command a snapshot comes on", got.cmd, "debug")
	eq("carrying the window's own token", got.args.token, "dbg-0-1")
	eq("and no tab, so no list is emptied by it", got.args.tab, nil)
	eq("it names the file it is about", got.args.path, "/root/notes.txt")
	eq("three lines", #got.args.text, 3)
	eq("the first", got.args.text[1], "one")
	eq("the second", got.args.text[2], "two")
	eq("the third", got.args.text[3], "three")

	-- A line with no newline after it is still a line, and an empty file is no lines
	-- at all: a pane showing one blank row for an empty file would be a pane that
	-- cannot be told from a file holding one empty line.
	eq("a last line with no newline is a line",
		#CeroSecDebug.showBytes("a\nb"), 2)
	eq("and an empty file is no lines", #CeroSecDebug.showBytes(""), 0)
	eq("while one newline IS one empty line",
		#CeroSecDebug.showBytes("\n"), 1)

	-- THE TWO NOTATIONS, on the bytes themselves: caret for the low half and its
	-- DEL, three octal digits for the high. Every one of them asserted, because a
	-- window that dropped an unprintable byte would be a window that showed a file
	-- the machine has not got.
	local shown = CeroSecDebug.showBytes("a" .. string.char(9) .. "b" ..
		string.char(13) .. string.char(0) .. string.char(127) .. string.char(200))
	eq("one line, since none of them is a newline", #shown, 1)
	eq("a tab is ^I, a return ^M, a nul ^@, DEL ^? and 0310 octal",
		shown[1], "a^Ib^M^@^?\\310")

	-- THE CAP, and the line that says what was left. Provoked with a file OVER it and
	-- not asserted against the length of a file that fits, which would be an
	-- assertion no cap has to pass.
	local big = string.rep("x", CeroSecDebug.FILE_BYTES_MAX + 500)
	local node = CeroSecOS.getNode(state, session, "/root/notes.txt")
	node.data = big
	got = ask("/root/notes.txt")
	eq("the file comes back in two lines: the bytes and what was cut",
		#got.args.text, 2)
	eq("and the bytes are exactly the cap",
		#got.args.text[1], CeroSecDebug.FILE_BYTES_MAX)
	eq("with the rest counted on the line under them", got.args.text[2],
		"[... 500 more bytes]")

	-- AND THE LINE CAP, which is the same bound said the other way: four kilobytes of
	-- newlines is four thousand lines and the pane draws six.
	node.data = string.rep("\n", CeroSecDebug.FILE_LINES_MAX + 20)
	got = ask("/root/notes.txt")
	eq("the lines are capped", #got.args.text, CeroSecDebug.FILE_LINES_MAX + 1)
	eq("and the last of them says how many were left", got.args.text[#got.args.text],
		"[... 20 more lines]")

	-- THE REFUSALS, each in the server's own words and each on the `error` field a
	-- refusal has always come back on.
	local function refusal(path)
		local answer = ask(path)
		if answer == nil then return nil end
		return answer.args.error
	end
	check("a file that is not there is refused",
		string.find(tostring(refusal("/root/nope.txt")), "no such file", 1, true) ~= nil)
	check("a directory is refused for being one",
		string.find(tostring(refusal("/etc")), "is a dir", 1, true) ~= nil)
	check("/ is refused for being one too",
		string.find(tostring(refusal("/")), "directory", 1, true) ~= nil)
	check("a relative path is refused",
		string.find(tostring(refusal("notes.txt")), "absolute", 1, true) ~= nil)
	check("no path at all is refused",
		string.find(tostring(refusal(nil)), "no path", 1, true) ~= nil)
	-- A component no filesystem of this machine could hold. It could not resolve to
	-- anything anyway -- the tree is a table of ours -- and it is refused BEFORE the
	-- walk, because a door that is only safe because of what is behind it stops being
	-- safe when what is behind it moves.
	check("a component the machine could not hold is refused",
		string.find(tostring(refusal("/root/a b")),
			"could hold", 1, true) ~= nil)
	check("and a path deeper than the machine allows",
		string.find(tostring(refusal("/" .. string.rep("a/", CeroSecOS.MAX_DEPTH + 2))),
			"too deep", 1, true) ~= nil)
	-- `..` cannot leave the tree and is refused all the same: CeroSecOS.resolve eats it
	-- in pure string work, so what reaches the walk here is /root/notes.txt.
	got = ask("/root/../root/notes.txt")
	eq("a path with .. in it resolves and is answered", got.args.error, nil)
	check("with the file's own text on it", type(got.args.text) == "table")

	-- AND THE DOOR SHUT: no flag, no debug mode, no admin. It answers nothing at all,
	-- which is what every act of this window does behind it.
	local flag, debugMode = CeroSec.DEV_DEBUG_MENU, _G.isDebugEnabled
	CeroSec.DEV_DEBUG_MENU = false
	_G.isDebugEnabled = function() return false end
	answers = {}
	net.system:OnClientCommand("debugact", net.player,
		{ x = 10, y = 10, z = 0, token = "dbg-0-1", act = "readfile",
			path = "/root/notes.txt" })
	eq("behind a shut door the read answers nothing", #answers, 0)
	CeroSec.DEV_DEBUG_MENU = flag
	_G.isDebugEnabled = debugMode
end

print("window_test: " .. count .. " checks passed")
