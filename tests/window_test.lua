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
_G.getText = function(key) return key end
_G.UIFont = { Code = "Code", Small = "Small" }
_G.Keyboard = { KEY_ESCAPE = 1, KEY_TAB = 15 }
_G.instanceof = function() return true end
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

-- The font. Every character is CHAR_W wide, and MeasureStringX answers on the
-- string it is given -- which is what the game does with the monospaced
-- UIFont.Code (media/fonts/codeMedium.fnt: one xadvance for all 218 glyphs).
--
-- __cellMeasure is the game's answer to a *load time* measurement, when the
-- font asked for is not built yet and TextManager hands back the default,
-- proportional one instead. It is set while the mod is being loaded below and
-- cleared afterwards, so a cell taken at load time is half again too wide and
-- one taken with the game up is right. That is the gap between the "$" and the
-- block cursor in the screenshot.
local CHAR_W = 8
local FONT_H = 12
_G.__cellMeasure = 12
_G.getTextManager = function()
	return {
		MeasureStringX = function(_, _, s)
			if s == "M" and _G.__cellMeasure then return _G.__cellMeasure end
			return CHAR_W * #s
		end,
		getFontHeight = function() return FONT_H end,
	}
end
_G.getCore = function()
	return { getScreenWidth = function() return 1920 end,
		getScreenHeight = function() return 1080 end }
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
	"shared/CeroSec/OS/CeroSecOSFS.lua",
	"shared/CeroSec/OS/CeroSecOSPath.lua",
	"shared/CeroSec/OS/CeroSecOSShell.lua",
	"shared/CeroSec/OS/CeroSecOSState.lua",
	"shared/CeroSec/OS/CeroSecOSSystem.lua",
	"shared/CeroSec/OS/CeroSecOSUsers.lua",
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
	check("and greets whoever is standing there", bench.painted("CeroSec OS 1.0"))

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
	check("the BIOS is on the first glass", bench.painted("CeroSec BIOS"))
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

print("window_test: " .. count .. " checks passed")
