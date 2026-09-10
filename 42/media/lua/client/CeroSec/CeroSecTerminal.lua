require "ISUI/ISCollapsableWindow"
require "ISUI/ISTextEntryBox"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecReach"

--
-- The terminal window: a 60 x 20 green screen in a beige monitor, inside a
-- plain PZ window.
--
-- It owns no state of the machine, and since the console model it owns none of
-- the screen either: the server hands it the whole screen -- the lines, the
-- prompt, and what the machine is waiting for -- and the window draws it. What
-- is left here is decoration (the cursor, the glow, the scanlines), the input
-- history of this player, and the one thing the window decides on its own: when
-- to shut, the moment the computer, the power or the player stops being what it
-- was opened for.
--

CeroSecTerminal = ISCollapsableWindow:derive("CeroSecTerminal")

-- One window per local player.
CeroSecTerminal.instances = {}

-- Cell of the screen grid. Measured once, the way ISCollapsableWindow measures
-- its own title bar font at load time (ISCollapsableWindow.lua:11-12).
local CELL_W = getTextManager():MeasureStringX(UIFont.Code, "M")
local CELL_H = getTextManager():getFontHeight(UIFont.Code)
local TITLE_H = math.max(16, getTextManager():getFontHeight(UIFont.Small) + 1)

-- Beige around the screen, black margin inside it.
local BEZEL = 14
local PAD = 6

local SCREEN_W = CeroSec.COLS * CELL_W
local SCREEN_H = CeroSec.ROWS * CELL_H
local GLASS_W = SCREEN_W + PAD * 2
local GLASS_H = SCREEN_H + PAD * 2
local HINT_H = CELL_H + 6

local WINDOW_W = GLASS_W + BEZEL * 2
local WINDOW_H = TITLE_H + GLASS_H + BEZEL * 2 + HINT_H

-- How long the machine takes to put its first screenful up. The BIOS lines
-- themselves are the server's (CeroSec.BOOT_LINES, written into the console at
-- power-on): all that is left here is the pace at which they appear, and only
-- for the player who opened the machine first.
CeroSecTerminal.BOOT_MS = 2000

-- How long a command may go unanswered before the terminal stops waiting for
-- it. Every server path answers -- open, login, exec and every refusal -- so
-- this is only ever reached when the answer was lost: a Lua error inside the
-- handler is swallowed by the pcall the game calls it through, and without this
-- the window would sit on a prompt that never comes back.
CeroSecTerminal.REPLY_TIMEOUT_MS = 10000

-- Every window stamps its commands with a token and only listens to answers
-- carrying it back. The player key would not do on its own: a server addresses
-- a *connection*, and in split screen two local players share one, so both
-- windows would read each other's output. The token is the window, not the
-- player, so it also settles the case of one player closing a terminal and
-- opening another before an answer lands.
CeroSecTerminal.tokenCount = 0

local function newToken(playerNum)
	CeroSecTerminal.tokenCount = CeroSecTerminal.tokenCount + 1
	return tostring(playerNum) .. "-" .. tostring(getTimestampMs()) ..
		"-" .. tostring(CeroSecTerminal.tokenCount)
end

--
-- Opening
--

-- The window for this player, opened on this computer. An open window on
-- another computer is closed first: one terminal per player.
function CeroSecTerminal.open(playerObj, computer)
	local playerNum = playerObj:getPlayerNum()
	local existing = CeroSecTerminal.instances[playerNum]
	if existing then existing:close() end

	local square = computer:getSquare()
	if not square then return nil end

	local x = (getCore():getScreenWidth() - WINDOW_W) / 2
	local y = (getCore():getScreenHeight() - WINDOW_H) / 2
	local window = CeroSecTerminal:new(x, y, playerObj, computer)
	window:initialise()
	window:addToUIManager()
	CeroSecTerminal.instances[playerNum] = window
	window:askForScreen()
	return window
end

function CeroSecTerminal:new(x, y, playerObj, computer)
	local o = ISCollapsableWindow.new(self, x, y, WINDOW_W, WINDOW_H)
	o.playerObj = playerObj
	o.playerNum = playerObj:getPlayerNum()
	o.computer = computer
	local square = computer:getSquare()
	o.cx, o.cy, o.cz = square:getX(), square:getY(), square:getZ()
	-- The square the player has to keep standing on, kept as coordinates: the
	-- square object itself is replaced when its chunk is reloaded, and a window
	-- must not shut because the world handed out a new IsoGridSquare.
	local front = CeroSecReach.frontSquare(computer)
	o.fx, o.fy, o.fz = nil, nil, nil
	if front then o.fx, o.fy, o.fz = front:getX(), front:getY(), front:getZ() end
	o.hostname = "cerosec"
	o.token = newToken(o.playerNum)

	-- The screen, as the server last described it. self.lines is what is drawn:
	-- the same thing, except while the BIOS is being revealed a line at a time.
	o.lines = {}
	o.screen = {}
	o.revealing = false
	o.revealStart = 0
	o.shown = 0
	o.history = {}
	o.historyIndex = 0
	o.scroll = 0
	o.mode = "login"
	o.prompt = ""
	o.opened = false
	o.busy = false
	o.busySince = 0
	o.lastKeySound = 0

	o.title = "CeroSec OS"
	o.resizable = false
	o.drawFrame = true
	o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
	return o
end

function CeroSecTerminal:createChildren()
	ISCollapsableWindow.createChildren(self)
	self:setResizable(false)
	self.resizeWidget:setVisible(false)
	self.resizeWidget2:setVisible(false)
	self.collapseButton:setVisible(false)

	-- The input line sits on the row right under the last line printed. Its
	-- own drawing is
	-- turned off as far as it can be -- no frame, no background, no border, and
	-- a text colour equal to the screen -- because the terminal draws the line
	-- itself, with the glow and the block cursor. What is left of the box is
	-- what it is here for: it takes the keyboard (UITextBox2.focus sets
	-- Core.currentTextEntryBox, and GameKeyboard.isKeyDown then answers false to
	-- every game key, GameKeyboard.java:118), and it hands back Enter, Escape
	-- and the arrows.
	local colors = CeroSec.COLORS
	local entry = ISTextEntryBox:new("", self:inputX(), self:inputY(0), SCREEN_W, CELL_H + 4)
	entry.font = UIFont.Code
	entry:initialise()
	entry:instantiate()
	entry:setHasFrame(false)
	entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	entry:setTextRGBA(colors.screen.r, colors.screen.g, colors.screen.b, 1)
	entry:setMaxLines(1)
	entry:setUIName("cerosec terminal entry")
	entry.onCommandEntered = function() self:onCommandEntered() end
	entry.onOtherKey = function(_, key) self:onOtherKey(key) end
	entry.onPressUp = function() self:onHistory(1) end
	entry.onPressDown = function() self:onHistory(-1) end
	entry.onTextChange = function() self:onTyped() end
	entry.onMouseWheel = function(_, del) return self:onMouseWheel(del) end
	self:addChild(entry)
	self.entry = entry

	-- Focused from the first frame, before the BIOS has finished typing: an
	-- unfocused window would let the boot sequence be walked away from with
	-- WASD and would leave Escape to the pause menu.
	--
	-- No ignoreFirstInput here. Chat calls it because a key opens the chat and
	-- that key would otherwise be typed into it (ISChat:focus, ISChat.lua:617-618);
	-- a terminal is opened by a mouse click at the end of a timed action, so
	-- there is no key to swallow and the flag would only eat the player's first
	-- real keystroke (UITextBox2.ignoreFirstInput sets ignoreFirst, and nothing
	-- clears it until an input is dropped).
	self:setEntryActive(true)
end

-- Where the input line starts on screen. The text box draws its text two
-- pixels in when it has no frame (UITextBox2.getInset), so it is placed two
-- pixels out for its text to land on our grid.
function CeroSecTerminal:inputX()
	return BEZEL + PAD - 2
end

function CeroSecTerminal:inputY(row)
	return TITLE_H + BEZEL + PAD + (row or 0) * CELL_H - 2
end

-- The first thing a window does: ask the machine what is on its screen. Until
-- the answer lands there is nothing to show, because the window invents
-- nothing.
function CeroSecTerminal:askForScreen()
	self:setBusy()
	self:send("open", {})
end

--
-- Talking to the server
--

function CeroSecTerminal:send(command, args)
	args.x, args.y, args.z = self.cx, self.cy, self.cz
	args.token = self.token
	CCeroSecSystem.instance:sendCommand(self.playerObj, command, args)
end

-- An answer is ours when it carries our token back. Nothing else is enough:
-- the coordinates are shared by every terminal open on the same computer.
function CeroSecTerminal:isMine(args)
	return args ~= nil and args.token ~= nil and args.token == self.token
end

function CeroSecTerminal:onServerCommand(command, args)
	if not self:isMine(args) then return end

	if command == "closed" then
		self:closedByServer(args.reason)
	elseif command == "opened" then
		self.opened = true
		if args.hostname then self.hostname = args.hostname end
		-- U+00B7 MIDDLE DOT, in the window font (UIFont.Small), as decided.
		self:setTitle("CeroSec OS \194\183 " .. self.hostname)
		self:showScreen(args, args.animate)
	elseif command == "screen" then
		self:showScreen(args, false)
	end
end

-- One screen, whole, as the server described it. Everything the window shows
-- comes through here and nowhere else: there is no path by which a line appears
-- on this screen without being on the machine's.
--
-- animate is set on the one 'opened' that finds the machine freshly switched
-- on: those lines are typed out over BOOT_MS rather than dropped on the glass
-- at once. It is the only moment the window shows less than it was told.
function CeroSecTerminal:showScreen(args, animate)
	self.busy = false
	self.screen = args.lines or {}
	self.prompt = args.prompt or ""
	self.scroll = 0

	if animate and #self.screen > 0 then
		self.revealing = true
		self.revealStart = getTimestampMs()
		self.shown = 0
		self.lines = {}
		-- No prompt under a machine that is still counting its memory.
		self.bootedPrompt = self.prompt
		self.prompt = ""
		self:setMode("boot")
		return
	end

	self.revealing = false
	self.shown = #self.screen
	self.lines = self.screen
	self:setMode(args.mode)
end

function CeroSecTerminal:closedByServer(reason)
	CeroSec.log("terminal closed by the server: " .. tostring(reason))
	self:close()
end

--
-- The screen
--

-- A line the window says on its own account. There is exactly one of those --
-- the answer that never came -- and it is gone the moment the server describes
-- the screen again, which is the right lifetime for it.
function CeroSecTerminal:say(text)
	-- Never written into self.screen: that table is the server's word.
	local shown = {}
	for i = 1, #self.lines do shown[i] = self.lines[i] end
	CeroSec.ringPush(shown, text, CeroSec.CONSOLE_MAX)
	self.lines = shown
	self.scroll = 0
end

-- What the machine is waiting for: "login", "password", "shell", or "boot"
-- while the BIOS is still typing itself out. The prompt is not set here -- it
-- comes down with the screen -- so the two can never drift apart.
function CeroSecTerminal:setMode(mode)
	mode = mode or "login"
	-- Only a change empties the input line. Every screen the machine sends
	-- lands here, including the ones another player standing at the same
	-- computer caused, and a half-typed command must survive those.
	local changed = self.mode ~= mode
	self.mode = mode
	self.entry:setMasked(mode == "password")
	if changed then
		self.entry:setText("")
		self.historyIndex = 0
	end
	self:layoutEntry()
end

function CeroSecTerminal:setEntryActive(active)
	self.entryActive = active
	self.entry:setVisible(active)
	self.entry:setEditable(active)
	-- setEditable writes its own grey borderColor (ISTextEntryBox.lua:64-71) and
	-- prerender then draws it, so the border is put back out afterwards, every
	-- time: nothing of the box may show on the glass.
	self.entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	if active then
		self.entry:focus()
	else
		self.entry:unfocus()
	end
end

--
-- Keeping the keyboard
--
-- Focus in this game is one static field: UITextBox2.focus sets
-- Core.currentTextEntryBox to the box, unfocus clears it, and Core.updateKeyboard
-- hands the keys to whatever is in it. Any other box that is clicked puts
-- ITSELF in there (UITextBox2.onMouseDown: Core.currentTextEntryBox = this),
-- so a click on the inventory's filter, on the chat, or on anything else with a
-- text box takes our keyboard away and nothing gives it back.
--
-- Our box is one line tall, transparent and sitting on the prompt row, so
-- "click the terminal to type again" used to mean hitting a few invisible
-- pixels. It now means what it says: every mouse press on the window, wherever
-- it lands, hands the keyboard back to the box. Same wiring as the chat, which
-- routes the presses of every piece of itself into one handler
-- (ISChat.lua:82-96, 175, 198, 354-355) -- except that ours is a single window
-- painting its own glass, so one override on the window is the whole surface.
--

-- Hand the keyboard back to the input line. Cheap enough to call on every
-- press: focus() is two field writes.
function CeroSecTerminal:focusEntry()
	if self.closing or not self.entry or not self.entryActive then return end
	-- A dropped-input flag from anywhere would eat the first thing typed after
	-- the click, which is exactly the keystroke the player means.
	self.entry.javaObject:setIgnoreFirst(false)
	if not self.entry:isFocused() then self.entry:focus() end
end

-- The press also brings the window to the front and starts a drag, so the
-- parent still gets it (ISCollapsableWindow.lua:270-280). The close button and
-- the input box are children and consume their own presses: the button closes,
-- and the box focuses itself (UITextBox2.onMouseDown).
function CeroSecTerminal:onMouseDown(x, y)
	self:focusEntry()
	return ISCollapsableWindow.onMouseDown(self, x, y)
end

-- And again on the release, the way the chat wires both halves of the click
-- (ISChat.lua:1019 and ISChat.lua:979): a global OnMouseDown handler firing
-- between the two must not be able to leave the window looking focused and
-- deaf.
function CeroSecTerminal:onMouseUp(x, y)
	self:focusEntry()
	return ISCollapsableWindow.onMouseUp(self, x, y)
end

-- Which row the prompt is on: right under the last line printed, the way a
-- terminal fills its screen, and pinned to the last row once the screen is
-- full. The entry box follows it.
function CeroSecTerminal:inputRow()
	local rows = self:viewRows()
	local shown = #self.lines - self.scroll
	if shown < 0 then shown = 0 end
	if shown > rows then shown = rows end
	return shown
end

-- The entry starts where the prompt ends, so the prompt is drawn by us and
-- never typed over, and it may only hold what still fits on the line.
function CeroSecTerminal:layoutEntry()
	local prompt = self.prompt or ""
	local row = self:inputRow()
	if self.laidOut == prompt and self.laidOutRow == row then return end
	self.laidOut, self.laidOutRow = prompt, row

	local width = getTextManager():MeasureStringX(UIFont.Code, prompt)
	self.entry:setX(self:inputX() + width)
	self.entry:setY(self:inputY(row))
	self.entry:setWidth(SCREEN_W - width)
	-- 60 columns is the whole line, prompt included.
	local room = CeroSec.COLS - #prompt
	if room < 1 then room = 1 end
	self.entry:setMaxTextLength(room)
end

--
-- Input
--

function CeroSecTerminal:onTyped()
	-- A keyboard heard through a monitor speaker, at most once a second.
	local now = getTimestampMs()
	if now - self.lastKeySound < 1000 then return end
	self.lastKeySound = now
	self.playerObj:playSoundLocal("CeroSecKeyboardFast")
end

-- Enter. Nothing is echoed here: the line goes to the machine, and it comes
-- back on the screen the machine sends everybody standing at it. That round
-- trip is what makes the second player see the first one typing.
function CeroSecTerminal:onCommandEntered()
	if self.busy or self.revealing then return end
	local text = self.entry:getInternalText() or ""
	self.entry:setText("")
	self.historyIndex = 0

	if self.mode == "login" then
		-- An empty name is not a login attempt, it is a bare Enter.
		if text == "" then return end
		self:setBusy()
		self:send("login", { text = text })
		return
	end

	if self.mode == "password" then
		-- An empty password is one: the accounts ship open.
		self:setBusy()
		self:send("login", { text = text })
		return
	end

	if self.mode == "shell" then
		if text ~= "" then
			CeroSec.ringPush(self.history, text, CeroSec.HISTORY_MAX)
		end
		self:setBusy()
		self:send("exec", { line = text })
	end
end

function CeroSecTerminal:setBusy()
	self.busy = true
	self.busySince = getTimestampMs()
end

-- An answer that never came. Say so and give the line back rather than leave a
-- dead prompt.
function CeroSecTerminal:checkTimeout()
	if not self.busy then return end
	if getTimestampMs() - self.busySince < CeroSecTerminal.REPLY_TIMEOUT_MS then return end
	self.busy = false
	self:say("cerosec: no answer from the machine")
end

function CeroSecTerminal:onHistory(delta)
	if self.mode ~= "shell" then return end
	local index, text = CeroSec.historyPick(self.history, self.historyIndex, delta)
	self.historyIndex = index
	self.entry:setText(text)
end

-- Escape and nothing else: the game hands a focused text box exactly two keys,
-- Escape (1) and Tab (15), and dispatches every other key to a method of its
-- own (Core.updateKeyboardAux in the shipped build). PageUp and PageDown never
-- arrive, and cannot be polled for either -- isKeyPressed and isShiftKeyDown
-- both answer false while a box is taking text (GameKeyboard.isKeyDown). So the
-- scrollback scrolls with the wheel; see the note in docs/TEST-rung2.md.
function CeroSecTerminal:onOtherKey(key)
	if key == Keyboard.KEY_ESCAPE then self:close() end
end

function CeroSecTerminal:viewRows()
	if self.entryActive then return CeroSec.ROWS - 1 end
	return CeroSec.ROWS
end

function CeroSecTerminal:scrollBy(rows)
	self.scroll = CeroSec.clampScroll(self.scroll + rows, #self.lines, self:viewRows())
end

function CeroSecTerminal:onMouseWheel(del)
	-- One notch, three rows, the way a terminal scrolls.
	self:scrollBy(-del * 3)
	return true
end

--
-- Closing
--

function CeroSecTerminal:close()
	if self.closing then return end
	self.closing = true
	if self.entry then self.entry:unfocus() end
	if self.opened then self:send("close", {}) end
	if CeroSecTerminal.instances[self.playerNum] == self then
		CeroSecTerminal.instances[self.playerNum] = nil
	end
	self:setVisible(false)
	self:removeFromUIManager()
end

-- Everything that makes an open terminal stop making sense. Checked every
-- frame, because none of it is something the server can be relied on to notice
-- first: a player who steps aside has not sent anything at all.
function CeroSecTerminal:stillValid()
	local playerObj = self.playerObj
	if not playerObj or playerObj:isDead() then return false end
	if not self.computer or not self.computer:getSquare() then return false end
	if not CeroSec.isOnSprite(self.computer:getSpriteName()) then return false end
	if not self.fx then return false end
	-- Not getCurrentSquare: a player seated on the chair in front of the screen
	-- counts as standing on the chair's square, so the sit does not shut the
	-- window under him (CeroSecReach.standingSquare). Standing up does not close
	-- it either, and never has: the rule is the square, not the posture.
	local square = CeroSecReach.standingSquare(playerObj, self.computer)
	if not square then return false end
	if square:getX() ~= self.fx or square:getY() ~= self.fy or square:getZ() ~= self.fz then
		return false
	end
	return true
end

--
-- Drawing
--

-- The BIOS typing itself out. Nothing is invented: the lines being revealed are
-- the ones the server already put on the console, one at a time, and the moment
-- the last one is up the window is showing exactly what every other window on
-- this machine shows.
function CeroSecTerminal:updateReveal()
	if not self.revealing then return end
	local count = #self.screen
	local elapsed = getTimestampMs() - self.revealStart
	local want = math.floor(elapsed / (CeroSecTerminal.BOOT_MS / count))
	if want > count then want = count end
	while self.shown < want do
		self.shown = self.shown + 1
		self.lines[#self.lines + 1] = self.screen[self.shown]
		self.scroll = 0
	end
	if self.shown < count then return end

	self.revealing = false
	self.lines = self.screen
	self.prompt = self.bootedPrompt or ""
	self:setMode("login")
	-- The login prompt is the first thing anyone types at, so make sure the
	-- keyboard is here for it: two seconds of BIOS is long enough for a click
	-- somewhere else to have taken it.
	self:focusEntry()
end

function CeroSecTerminal:prerender()
	if not self.closing and not self:stillValid() then
		self:close()
		return
	end
	self:updateReveal()
	self:checkTimeout()
	self:layoutEntry()
	ISCollapsableWindow.prerender(self)
	self:drawMonitor()
end

-- The beige box, its two lights, and the black glass in the middle. No rounded
-- corners anywhere: the game draws rectangles.
function CeroSecTerminal:drawMonitor()
	local colors = CeroSec.COLORS
	local top = TITLE_H
	local bezelH = GLASS_H + BEZEL * 2

	self:drawRect(0, top, WINDOW_W, bezelH, 1, colors.bezel.r, colors.bezel.g, colors.bezel.b)
	-- Light from the top left, shade at the bottom right: two one pixel edges.
	self:drawRect(0, top, WINDOW_W, 1, 1, colors.bezelHi.r, colors.bezelHi.g, colors.bezelHi.b)
	self:drawRect(0, top, 1, bezelH, 1, colors.bezelHi.r, colors.bezelHi.g, colors.bezelHi.b)
	self:drawRect(0, top + bezelH - 1, WINDOW_W, 1, 1, colors.bezelLo.r, colors.bezelLo.g, colors.bezelLo.b)
	self:drawRect(WINDOW_W - 1, top, 1, bezelH, 1, colors.bezelLo.r, colors.bezelLo.g, colors.bezelLo.b)

	local glassX, glassY = BEZEL, top + BEZEL
	self:drawRect(glassX, glassY, GLASS_W, GLASS_H, 1, colors.screen.r, colors.screen.g, colors.screen.b)
	-- The glass sits in the beige, so the shading runs the other way around it.
	self:drawRect(glassX - 1, glassY - 1, GLASS_W + 2, 1, 1, colors.bezelLo.r, colors.bezelLo.g, colors.bezelLo.b)
	self:drawRect(glassX - 1, glassY - 1, 1, GLASS_H + 2, 1, colors.bezelLo.r, colors.bezelLo.g, colors.bezelLo.b)
	self:drawRect(glassX - 1, glassY + GLASS_H, GLASS_W + 2, 1, 1, colors.bezelHi.r, colors.bezelHi.g, colors.bezelHi.b)
	self:drawRect(glassX + GLASS_W, glassY - 1, 1, GLASS_H + 2, 1, colors.bezelHi.r, colors.bezelHi.g, colors.bezelHi.b)

	-- The power light, bottom right of the bezel.
	local ledY = top + bezelH - BEZEL / 2 - 2
	self:drawRect(WINDOW_W - BEZEL - 6, ledY, 4, 4, 1, colors.text.r, colors.text.g, colors.text.b)

	self:drawText(getText("IGUI_CeroSec_Hint"), BEZEL, top + bezelH + 3,
		colors.dim.r, colors.dim.g, colors.dim.b, 1, UIFont.Code)
end

function CeroSecTerminal:render()
	local colors = CeroSec.COLORS
	local left = BEZEL + PAD
	local top = TITLE_H + BEZEL + PAD

	-- The scrollback, oldest first, with the prompt on the row right after it.
	local rows = self:viewRows()
	local last = #self.lines - self.scroll
	local first = last - rows + 1
	if first < 1 then first = 1 end
	local row = 0
	for i = first, last do
		self:drawScreenText(self.lines[i], left, top + row * CELL_H, colors.text)
		row = row + 1
	end

	if self.entryActive then
		self:drawInput(left, top + self:inputRow() * CELL_H)
	end

	-- Scrolled up: say so on the top row, where nothing else is being typed.
	if self.scroll > 0 then
		self:drawScreenText("-- more --", left + SCREEN_W - 10 * CELL_W, top, colors.bright)
	end

	self:drawScanlines()

	-- The parent's render is what clears the stencil its prerender set
	-- (ISCollapsableWindow.lua:194-196) and draws the window frame over
	-- everything, so it runs last and is never skipped.
	ISCollapsableWindow.render(self)
end

-- The prompt, what has been typed, and the block cursor over it.
function CeroSecTerminal:drawInput(x, y)
	local colors = CeroSec.COLORS
	local prompt = self.prompt or ""
	self:drawScreenText(prompt, x, y, colors.dim)

	local text = self.entry:getInternalText() or ""
	if self.mode == "password" then text = string.rep("*", #text) end
	local textX = x + getTextManager():MeasureStringX(UIFont.Code, prompt)
	self:drawScreenText(text, textX, y, colors.text)

	-- Solid block, on for half a second and off for half a second. The cell is
	-- painted in both halves -- green, then the screen's own colour -- because
	-- the text box draws a caret of its own in a hardcoded lavender
	-- (UITextBox2.textEntryCursorColour, no setter) and this is what buries it.
	local before = string.sub(text, 1, self.entry:getCursorPos() or #text)
	local cursorX = textX + getTextManager():MeasureStringX(UIFont.Code, before)
	local lit = math.floor(getTimestampMs() / CeroSec.CURSOR_BLINK_MS) % 2 == 0
	local block = lit and colors.text or colors.screen
	self:drawRect(cursorX, y, CELL_W, CELL_H, 1, block.r, block.g, block.b)
end

-- One line of phosphor: a faint copy one pixel off, then the line itself.
function CeroSecTerminal:drawScreenText(text, x, y, color)
	if text == nil then return end
	if CeroSec.UI_GLOW then
		self:drawText(text, x + CeroSec.GLOW_OFFSET, y + CeroSec.GLOW_OFFSET,
			color.r, color.g, color.b, CeroSec.GLOW_ALPHA, UIFont.Code)
	end
	self:drawText(text, x, y, color.r, color.g, color.b, 1, UIFont.Code)
end

-- One dark line every three pixels over the glass. About sixty rects for a
-- twenty row screen, not one per pixel.
function CeroSecTerminal:drawScanlines()
	if not CeroSec.UI_SCANLINES then return end
	local glassX, glassY = BEZEL, TITLE_H + BEZEL
	local y = 0
	while y < GLASS_H do
		self:drawRect(glassX, glassY + y, GLASS_W, 1, CeroSec.SCANLINE_ALPHA, 0, 0, 0)
		y = y + CeroSec.SCANLINE_STEP
	end
end

--
-- The one door the server knocks on
--

-- Both transports land here: the singleplayer broadcast, which every window
-- sees, and the server's answer to one connection, which every local player on
-- that connection sees. Neither is routing enough, so isMine settles it on the
-- token and nothing else.
function CeroSecTerminal.onServerAnswer(command, args)
	if not args then return end
	for _, window in pairs(CeroSecTerminal.instances) do
		window:onServerCommand(command, args)
	end
end

-- Shut whatever terminal is open on this computer, wherever the news came from.
function CeroSecTerminal.closeAt(x, y, z)
	for _, window in pairs(CeroSecTerminal.instances) do
		if window.cx == x and window.cy == y and window.cz == z then window:close() end
	end
end
