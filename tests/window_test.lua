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
	"shared/CeroSec/OS/CeroSecOSDev.lua",
	"shared/CeroSec/OS/CeroSecOSFS.lua",
	"shared/CeroSec/OS/CeroSecOSPath.lua",
	"shared/CeroSec/OS/CeroSecOSShell.lua",
	"shared/CeroSec/OS/CeroSecOSState.lua",
	"shared/CeroSec/OS/CeroSecOSSystem.lua",
	"shared/CeroSec/OS/CeroSecOSUsers.lua",
	"server/CeroSec/SCeroSecDevices.lua",
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
	CCeroSecSystem = { instance = { sendCommand = function(_, sender, command, args)
		local replies = {}
		system.reply = function(_, _, cmd, a) replies[#replies + 1] = { cmd, a } end
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
	function bench.enter(line)
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
	-- Still logged in, and the machine is already unusable.
	bench.enter("ls")
	bench.frame()
	check("the commands are gone", bench.painted("ls: command not found"))
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

local function fakeDoor(locked, north, opposite)
	local o = { __class = "IsoDoor", lockedByKey = locked, north = north,
		opposite = opposite, syncs = 0 }
	highlightable(o)
	o.getNorth = function() return o.north end
	o.getOppositeSquare = function() return o.opposite end
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

local function fakeThumpable(padlock, north)
	local o = { __class = "IsoThumpable", lockedByPadlock = padlock, canPadlock = true,
		lockedByKey = false, keyId = 0, north = north, syncs = 0 }
	highlightable(o)
	o.isDoor = function() return true end
	o.getNorth = function() return o.north end
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
	-- lock0: the exterior door, facing west and locked.
	kit.lock0 = world.put(world.squares["11,10,0"], fakeDoor(true, false, outside))
	-- win0: a window in the office, facing north and locked.
	kit.win0 = world.put(world.squares["12,10,0"], fakeWindow(true, true))
	-- light0: the office switch, on. light1: the hallway switch, off.
	kit.light0 = world.put(world.squares["11,10,0"], fakeLight(true, true))
	kit.light1 = world.put(world.squares["13,11,0"], fakeLight(false, true))
	-- lock1: between the kitchen and the hallway, facing north, unlocked.
	kit.lock1 = world.put(world.squares["11,11,0"], fakeDoor(false, true, world.squares["12,11,0"]))
	-- lock2: the player-built door, padlocked.
	kit.lock2 = world.put(world.squares["12,11,0"], fakeThumpable(true, true))

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
		"crw-rw----  root  sudo  light0  office            on",
		"crw-rw----  root  sudo  light1  hallway           off",
		"crw-rw----  root  sudo  lock0   exterior       W  locked",
		"crw-rw----  root  sudo  lock1   kitchen-hall~  N  unlocked",
		"crw-rw----  root  sudo  lock2   built          N  padlock",
		"crw-rw----  root  sudo  win0    office         N  locked",
	}
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
	eq("the door is unlocked", kit.lock0.lockedByKey, false)
	eq("and it was broadcast", kit.lock0.syncs, 1)

	-- A window, and a padlock.
	bench.enter("echo unlock > /dev/win0")
	bench.frame()
	eq("the window is unlocked", kit.win0.locked, false)
	eq("and it was broadcast", kit.win0.syncs, 1)
	bench.enter("echo unlock > /dev/lock2")
	bench.frame()
	eq("the padlock is off", kit.lock2.lockedByPadlock, false)
	eq("and it was broadcast", kit.lock2.syncs, 1)
	bench.enter("cat /dev/lock2")
	bench.frame()
	check("and the machine reads unlocked", bench.painted("unlocked"))

	-- And the everyday face of all of it, end to end through the real
	-- discovery: dev's own table, and one order carried out on the world.
	bench.enter("dev")
	bench.frame()
	-- The offsets are the real ones: the computer stands at 10,10,0 and every
	-- one of these was walked out of the fake world by SCeroSecDevices.
	local table60 = {
		"light0  office                1E 0           on",
		"light1  hallway               3E 1S          on",
		"lock0   exterior              1E 0        W  unlocked",
		"lock1   kitchen-hallway       1E 1S       N  unlocked",
		"lock2   built                 2E 1S       N  unlocked",
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
	kit.lock2.canPadlock = false
	kit.lock2.keyId = -1
	bench.enter("echo lock > /dev/lock2")
	bench.frame()
	check("no padlock", bench.painted("lock2: no padlock"))

	--
	-- dev find: which of the thirty-five is it?
	--
	-- A light answers by blinking, which the server does on its own clock and
	-- everybody in the room sees. The switch is put back exactly as it was
	-- found: a survivor who asked which light this was did not ask for the
	-- room's lighting to change.
	kit.lock2.canPadlock = true
	kit.lock2.keyId = 0
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
	eq("nothing is lit yet", kit.lock1.outline, nil)
	bench.enter("dev find lock1")
	bench.frame()
	check("the machine says what it did", bench.painted("lock1: highlighted"))
	eq("the door is outlined", kit.lock1.outline, true)
	eq("for this player, once", kit.lock1.highlights[1], "0=true")
	eq("and the window remembers it has one lit", bench.window.highlight ~= nil, true)
	-- The object was found again on the far side by its square, its class and
	-- its sprite -- and nothing else on that square was.
	eq("and the padlocked door beside it was not", kit.lock2.outline, nil)

	-- It goes out on its own, in the window's own update, six seconds later.
	_G.__now = _G.__now + CeroSecOS.DEV_FIND_SECONDS * 1000
	bench.frame()
	eq("the outline is gone", kit.lock1.outline, false)
	eq("and the window is holding nothing", bench.window.highlight, nil)
	eq("it was put out for the same player", kit.lock1.highlights[2], "0=false")

	-- A second find drops the first outline rather than leaving it lit.
	bench.enter("dev find lock1")
	bench.frame()
	bench.enter("dev find win0")
	bench.frame()
	eq("the window is lit", kit.win0.outline, true)
	eq("and the door was put out at once", kit.lock1.outline, false)

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
		return n == 6
	end)())

	-- lock0 is torn out, and the machine is reloaded from its saved state.
	kit.world.remove(kit.lock0)
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
	check("lock1 kept its number", reloaded.painted("lock1   kitchen-hall~"))
	check("lock2 kept its number", reloaded.painted("lock2   built"))
	check("win0 kept its number", reloaded.painted("win0    office"))
	-- The one that is gone leaves a GAP: nothing moved up into lock0.
	check("the gone door is not listed", not reloaded.painted("lock0 "))
	reloaded.enter("cat /dev/lock0")
	reloaded.frame()
	check("and it says which kind of not-there it is",
		reloaded.painted("lock0: no such device"))

	-- And the gap is NOT handed to the next door built: a number spent is spent
	-- for the life of the machine, or a script that says "echo lock > /dev/lock0"
	-- one day locks the wrong door the next.
	kit.world.put(kit.world.squares["10,10,0"], fakeThumpable(false, false))
	reloaded.enter("ls -l /dev")
	reloaded.frame()
	check("the new door took the next number, not the gap",
		reloaded.painted("crw-rw----  root  sudo  lock3   built          W  unlocked"))
	check("and the gap is still a gap", not reloaded.painted("lock0 "))

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

print("window_test: " .. count .. " checks passed")
