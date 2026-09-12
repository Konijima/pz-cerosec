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
_G.__gameTime = { year = 1993, month = 6, day = 7, hour = 14, minutes = 32 }
_G.getGameTime = function()
	local t = _G.__gameTime
	if t == nil then return nil end
	return {
		getYear = function() return t.year end,
		getMonth = function() return t.month end,
		getDay = function() return t.day end,
		getHour = function() return t.hour end,
		getMinutes = function() return t.minutes end,
	}
end
_G.getText = function(key) return key end
_G.UIFont = { Code = "Code", Small = "Small" }
_G.Keyboard = { KEY_ESCAPE = 1, KEY_TAB = 15 }
-- Class-aware, because the device layer tells a light switch from a door with
-- it. Anything that is not one of the fake world objects below answers true, as
-- it did before: the only other caller is the client's computer test.
_G.instanceof = function(object, class)
	if type(object) == "table" and type(object.__class) == "string" then
		return object.__class == class
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
_G.isClient = function() return false end
_G.isServer = function() return false end
_G.sendServerCommand = function() end
_G.MapObjects = { OnNewWithSprite = function() end, OnLoadWithSprite = function() end }
_G.Events = setmetatable({}, { __index = function(t, key)
	local event = { Add = function() end }
	rawset(t, key, event)
	return event
end })
_G.ISTimedActionQueue = { isPlayerDoingAction = function() return false end, add = function() end }
_G.ISCeroSecTypeAction = { new = function() return {} end }
_G.ISRestAction = { new = function() return {} end }

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
function ISCollapsableWindow.addToUIManager() end
function ISCollapsableWindow.removeFromUIManager() end
function ISCollapsableWindow.addChild(self, child) self.children[#self.children + 1] = child end
function ISCollapsableWindow.setResizable() end
function ISCollapsableWindow.setTitle(self, title) self.titleText = title end
function ISCollapsableWindow.setVisible() end
function ISCollapsableWindow.drawRect() end
function ISCollapsableWindow.drawText() end

CeroSecReach = {
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
	return o
end
SGlobalObjectSystem.initSystem = function() end
SGlobalObjectSystem.RegisterSystemClass = function() end

--
-- The mod, loaded the way the game loads it.
--

local LUA = "42/media/lua/"
local FILES = {
	"shared/CeroSec/CeroSecDefs.lua",
	"shared/CeroSec/OS/CeroSecOS.lua",
	"shared/CeroSec/OS/CeroSecOSComplete.lua",
	"shared/CeroSec/OS/CeroSecOSCron.lua",
	"shared/CeroSec/OS/CeroSecOSDev.lua",
	"shared/CeroSec/OS/CeroSecOSFS.lua",
"shared/CeroSec/OS/CeroSecOSNet.lua",
	"shared/CeroSec/OS/CeroSecOSPath.lua",
	"shared/CeroSec/OS/CeroSecOSScript.lua",
	"shared/CeroSec/OS/CeroSecOSShell.lua",
	"shared/CeroSec/OS/CeroSecOSState.lua",
	"shared/CeroSec/OS/CeroSecOSSystem.lua",
	"shared/CeroSec/OS/CeroSecOSUsers.lua",
	"shared/CeroSec/OS/CeroSecOSVM.lua",
	"server/CeroSec/SCeroSecDevices.lua",
	"server/CeroSec/SCeroSecNet.lua",
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
	object.updateOnClient = function() end
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

	local window = CeroSecTerminal:new(0, 0, player, computer)
	window:initialise()
	window:createChildren()
	local bench = { window = window, object = object, system = system, player = player }
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

	CCeroSecSystem = { instance = { sendCommand = function(_, sender, command, args)
		local replies = {}
		system.reply = function(_, _, cmd, a) replies[#replies + 1] = { cmd, a }; record(a) end
		system:OnClientCommand(command, sender, args)
		for i = 1, #replies do
			for w = 1, #bench.windows do
				bench.windows[w]:onServerCommand(replies[i][1], replies[i][2])
			end
		end
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

	-- A second player, at the same computer, with a window of his own. His own
	-- online id, because the server keys a watcher on it and split screen is
	-- the one case where two windows share a connection.
	function bench.addWindow()
		local other = {}
		for key, value in pairs(player) do other[key] = value end
		other.getPlayerNum = function() return 1 end
		other.getOnlineID = function() return -2 end
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
			for i = 1, #replies do
				for w = 1, #bench.windows do
					bench.windows[w]:onServerCommand(replies[i][1], replies[i][2])
				end
			end
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
			for i = 1, #replies do
				for w = 1, #bench.windows do
					bench.windows[w]:onServerCommand(replies[i][1], replies[i][2])
				end
			end
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

-- reboot, with a second player standing at the same glass.
do
	local bench = newBench()
	bench.login("root")
	local other = bench.addWindow()
	other:askForScreen()
	bench.frame()
	eq("the second window reads the same screen", other.mode, "shell")

	bench.enter("reboot")
	bench.frame()

	check("the first window stayed open", not bench.window.closing)
	check("and so did the second", not other.closing)
	eq("the machine came back on", bench.object.on, true)
	eq("with a screen of its own", type(bench.object.console), "table")
	eq("and nobody logged in on it", bench.object.console.user, nil)

	-- Both of them are watching the BIOS type itself out again, which is the
	-- one thing that says it really went down and came back.
	eq("the first window is replaying the boot", bench.window.revealing, true)
	eq("and so is the second", other.revealing, true)

	_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
	bench.frame()
	check("the BIOS is on the first glass", bench.painted(CeroSec.BOOT_LINES[1]))
	eq("and it ends at a login prompt", bench.window.prompt, "login: ")
	eq("for the second window too", other.prompt, "login: ")
	eq("both are at a prompt", bench.window.mode, "prompt")
	eq("and so is the other", other.mode, "prompt")

	-- And the disk came through it: a reboot is not a repair.
	bench.enter("root")
	bench.enter("")
	bench.frame()
	eq("root logs back in", bench.window.mode, "shell")
	bench.enter("ls /bin")
	bench.frame()
	check("the machine is the one it was", bench.painted("shutdown"))
end

-- sudo reboot: the same, from an account that is not root.
do
	local bench = newBench()
	bench.login("admin")
	bench.enter("sudo reboot")
	bench.frame()
	eq("sudo asks first", bench.window.prompt, "[sudo] password for admin: ")
	eq("the machine is still on while it asks", bench.object.on, true)

	bench.enter("")
	bench.frame()
	eq("and then it goes down and comes back", bench.object.on, true)
	eq("with nobody logged in", bench.object.console.user, nil)
	eq("the window stayed and is booting", bench.window.revealing, true)
	check("and it was not closed", not bench.window.closing)
end

-- A reboot on a machine that lost its power while it was down.
do
	local bench = newBench()
	bench.login("root")
	bench.object.hasPower = function() return false end
	bench.enter("reboot")
	eq("it stays dark", bench.object.on, false)
	check("and the window is told", bench.window.closing)
end

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
	check("the BIOS announces the real drive", bench.painted("Detecting drives ... hda 32K"))
	check("and never a drive the machine has not got", not bench.painted("20MB"))
	eq("because the label is the ceiling", CeroSecOS.diskLabel(), "32K")

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
	check("and its size", bench.painted("32768"))

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

-- An ArrayList as the game hands one over: 0-based get, and a size.
local function javaList(items)
	return {
		size = function() return #items end,
		get = function(_, i) return items[i + 1] end,
	}
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
		sq = { objects = {} }
		sq.getX = function() return x end
		sq.getY = function() return y end
		sq.getZ = function() return z end
		sq.getRoom = function() return room end
		sq.getBuilding = function() if room ~= nil then return world.building end return nil end
		sq.getObjects = function() return javaList(sq.objects) end
		world.squares[key] = sq
		return sq
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

-- The four kinds. Each one answers the calls SCeroSecDevices makes on it and
-- counts the syncs, because "the change reached every watcher" is the half of a
-- server-side write that a state field cannot show.
local function fakeLight(on, powered)
	local o = { __class = "IsoLightSwitch", activated = on, powered = powered, syncs = 0 }
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
	local o = { __class = "IsoDoor", lockedByKey = locked, north = north,
		opposite = opposite, exterior = exterior == true, syncs = 0 }
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
	local o = { __class = "IsoWindow", locked = locked, north = north,
		smashed = false, barricaded = false, syncs = 0 }
	highlightable(o)
	o.getNorth = function() return o.north end
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
	local o = { __class = "IsoThumpable", lockedByPadlock = padlock, canPadlock = true,
		lockedByKey = false, keyId = 0, north = north, syncs = 0 }
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

	-- Somebody smashes the window. The next listing says so, and the machine
	-- refuses to work a lock that is not there any more.
	kit.win0.smashed = true
	bench.enter("ls -l /dev/win0")
	bench.frame()
	check("the smashed window shows",
		bench.painted("crw-rw----  root  sudo  win0    office         N  smashed"))
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

	-- Nothing of any of this is on the disk.
	eq("/dev is empty between commands",
		CeroSecOS.countEntries(reloaded.object.os.fs.children.dev), 0)
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
do
	local bench = newBench()
	bench.login("admin")
	bench.script("/home/admin/spin.sh", "while true; do x=1; done\n")
	for _ = 1, 4 do
		bench.enter("sh spin.sh &")
	end
	bench.frame()
	eq("four jobs", #CeroSecJobs.book(bench.object).list, 4)
	bench.enter("sh spin.sh &")
	bench.frame()
	check("the fifth is refused", bench.painted("sh: too many jobs"))
	eq("and there are still four", #CeroSecJobs.book(bench.object).list, 4)
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
	eq("and no machine is left in the scheduler", #CeroSecJobs.machines, 0)
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

	-- And then it goes down and comes back.
	_G.__now = _G.__now + 61000
	bench.tick(1)
	-- Said, not painted: the line goes out to every window and the machine wipes
	-- its console in the same breath, so the glass has already been redrawn by
	-- the fresh boot before this bench renders.
	check("it says NOW", bench.heard("The system is going down for reboot NOW!"))
	eq("and the machine came back", bench.object.on, true)
	eq("with nobody logged in", bench.object.console.user, nil)
	eq("and nothing pending", bench.object.shutdown, nil)
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

local function newNet()
	CeroSecJobs.machines = {}
	local system = SCeroSecSystem:new()
	local objects = {}

	-- A building is two numbers and nothing else as far as the wire is
	-- concerned: the corner of its BuildingDef, which is where it stands on the
	-- map and does not move.
	local function buildingAt(bx, by)
		local def = { getX = function() return bx end, getY = function() return by end }
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

	local office = buildingAt(400, 700)
	local shed = buildingAt(900, 120)
	local net = { system = system, objects = objects, machine = machine,
		office = office, shed = shed }

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
	local window = CeroSecTerminal:new(0, 0, player, computer)
	window:initialise()
	window:createChildren()
	window.stillValid = function() return true end
	window.painted = {}
	window.rects = {}
	window.drawText = function(self, text, x, y)
		self.painted[#self.painted + 1] = { text = text, x = x, y = y }
	end
	window.drawRect = function() end
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

	function net.enter(line)
		_G.__now = _G.__now + 1000
		window.entry:setText(line or "")
		window.entry:setCursorPos(#(line or ""))
		window:onCommandEntered()
		net.frame()
	end

	function net.escape()
		_G.__now = _G.__now + 100
		window:onOtherKey(Keyboard.KEY_ESCAPE)
		net.frame()
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
	net.put(third, "/etc/hosts.equiv", net.host(net.gate), 644, "root")
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
	net.window:close()
	net.window:askForScreen()
	_G.__now = _G.__now + CeroSecTerminal.BOOT_MS + 1000
	net.frame()
	check("and it is still on the glass when the window comes back",
		net.glass("admin@" .. net.host(net.gate)))
	net.enter("hostname")
	net.tick(2)
	check("and still typing at the far machine", net.glass(net.host(net.gate)))
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

print("window_test: " .. count .. " checks passed")
