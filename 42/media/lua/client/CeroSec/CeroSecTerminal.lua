require "ISUI/ISCollapsableWindow"
require "ISUI/ISTextEntryBox"
require "TimedActions/ISTimedActionQueue"
require "CeroSec/CeroSecDefs"
-- For CeroSecOS.columnize: the listing a second Tab prints is packed exactly the
-- way `ls` packs a directory, by the engine's own columniser and not a copy.
require "CeroSec/OS/CeroSecOSShell"
require "CeroSec/CeroSecReach"
require "CeroSec/ISCeroSecTypeAction"

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

-- Beige around the screen, black margin inside it.
local BEZEL = 14
local PAD = 6

-- Cell of the screen grid, and everything built on it.
--
-- NOT measured at load time, the way ISCollapsableWindow measures its own title
-- bar font (ISCollapsableWindow.lua:11-12). That one only wants a row height;
-- this is the width of a column of a sixty column grid, and it is asked for
-- while the mod files are being read. TextManager answers a font request out of
-- enumToFont[ordinal] and hands back the DEFAULT font -- a proportional one,
-- whose "M" is its widest glyph -- for any entry not built yet, so a cell
-- measured then can be half again as wide as the one the text is drawn with.
-- Twenty-one characters of prompt later, that is a block cursor a dozen columns
-- to the right of the "$" it should be sitting against.
--
-- So it is measured when a window is opened, with the game up, and again
-- whenever the answer changes -- the UI font size is an option and it moves.
--
-- And it is NOT MeasureStringX("M"). MeasureStringX hands the string to
-- AngelCodeFont.getWidth(String), which is getWidth(s, 0, len - 1, FALSE), and
-- that last argument is what decides how the LAST character of the string
-- counts: false means the last one contributes its glyph's ink `width` and
-- every other one its `xadvance`. The pen that DRAWS the string (render()) only
-- ever moves by `xadvance`. The two disagree by (xadvance - width) of whatever
-- character the string happens to end on, and in media/fonts/zomboidCode.fnt
-- -- Courier New, what UIFont.Code maps to in media/fonts/EN/fonts.txt --
-- "M" is `width=9 xadvance=8`: the widest glyph of the face, one pixel WIDER
-- than the cell it is drawn in. So a cell taken as MeasureStringX("M") is a
-- pixel too wide, the block cursor overlaps the glyph to its right, and sixty
-- of them are sixty pixels of grid that the text never fills.
--
-- The advance of a string is recovered from the same call by putting a known
-- character behind it and subtracting that character's ink: measure(s .. "M")
-- is advance(s) + ink("M"), so advance(s) = measure(s .. "M") - measure("M").
-- Exact, because zomboidCode.fnt declares no kerning pair at all (and
-- getWidth adds kerning to both sides of the subtraction anyway). CELL_W is
-- that for one "M"; `advance` below is that for any string.
local CELL_W, CELL_H, TITLE_H
local SCREEN_W, SCREEN_H, GLASS_W, GLASS_H, HINT_H, WINDOW_W, WINDOW_H

-- MeasureStringX's answer for a lone "M": the INK of the glyph, not the cell.
-- Only ever the subtrahend above.
local M_INK

local function measure()
	local manager = getTextManager()
	local mInk = manager:MeasureStringX(UIFont.Code, "M")
	local cellW = manager:MeasureStringX(UIFont.Code, "MM") - mInk
	local cellH = manager:getFontHeight(UIFont.Code)
	M_INK = mInk
	if cellW == CELL_W and cellH == CELL_H then return end

	CELL_W, CELL_H = cellW, cellH
	TITLE_H = math.max(16, manager:getFontHeight(UIFont.Small) + 1)
	SCREEN_W = CeroSec.COLS * CELL_W
	SCREEN_H = CeroSec.ROWS * CELL_H
	GLASS_W = SCREEN_W + PAD * 2
	GLASS_H = SCREEN_H + PAD * 2
	HINT_H = CELL_H + 6
	WINDOW_W = GLASS_W + BEZEL * 2
	WINDOW_H = TITLE_H + GLASS_H + BEZEL * 2 + HINT_H
end

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

-- The layout cache holds this once the box has been put in its one place.
local PARKED = "parked"

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
--
-- `token` is the one case where the window does not pick its own: a machine
-- coming back from a reboot is asked for by the SERVER, which minted the token
-- and has the watcher already, so the box is built around a screen that is
-- already on its way instead of asking for one (CeroSecTerminal.reopen).
function CeroSecTerminal.open(playerObj, computer, token)
	measure()
	local playerNum = playerObj:getPlayerNum()
	local previous = CeroSecTerminal.instances[playerNum]
	if previous then previous:close() end

	local square = computer:getSquare()
	if not square then return nil end

	local x = (getCore():getScreenWidth() - WINDOW_W) / 2
	local y = (getCore():getScreenHeight() - WINDOW_H) / 2
	local window = CeroSecTerminal:new(x, y, playerObj, computer, token)
	window:initialise()
	window:addToUIManager()
	CeroSecTerminal.instances[playerNum] = window
	if token == nil then window:askForScreen() end
	return window
end

-- Sitting down at the machine: the window, and the character kept at the
-- keyboard for as long as it is open. The end of the walk
-- (ISCeroSecUseAction:perform) is one caller and the reopen after a reboot is
-- the other, so the two cannot drift apart -- a reopened window is the same
-- window with the same character at it, and there is no second window class.
function CeroSecTerminal.sitDown(playerObj, computer, height, token)
	local window = CeroSecTerminal.open(playerObj, computer, token)
	if window then window:startTyping(height) end
	return window
end

function CeroSecTerminal:new(x, y, playerObj, computer, token)
	-- open() measured before it chose x and y; a window made any other way
	-- (a test bench) still gets a measured grid rather than none at all.
	measure()
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
	-- The server's token when it is the server that asked for this window, and
	-- one of our own otherwise.
	o.token = token or newToken(o.playerNum)

	-- The screen, as the server last described it. self.lines is what is drawn:
	-- the same thing, except while the BIOS is being revealed a line at a time.
	o.lines = {}
	o.screen = {}
	o.revealing = false
	o.revealStart = 0
	o.shown = 0
	-- What Up and Down walk: the account's own ~/.sh_history, as the machine
	-- last handed it over. The window keeps no history of its own.
	o.history = {}
	o.historyIndex = 0
	o.historyUser = nil
	-- What the last Tab made of the line, so a second Tab on the same word
	-- knows it is the second: the line and the cursor the machine's answer left
	-- behind, and the names it said matched.
	o.tabLine = nil
	o.tabCursor = nil
	o.tabNames = nil
	o.screenUser = nil
	o.scroll = 0
	o.mode = "prompt"
	o.prompt = ""
	o.mask = false
	-- Whether the machine is in the middle of something. The machine's word,
	-- and the only thing Escape looks at to tell an interrupt from a close.
	o.active = false
	-- Whether what is on the glass is a session on another machine. The machine's
	-- word again, and Escape is the only thing that reads it: at an idle remote
	-- prompt there is a connection to give up on, so the key is an interrupt
	-- rather than the close of a window nobody asked to shut.
	o.remote = false

	-- The editor. edit is the machine's word about it -- the path, the buffer,
	-- the file on the disk, and whether this window is the one holding the
	-- keyboard on it -- and everything else here belongs to this window alone:
	-- where the seventeen row view starts, whether the save question is up, and
	-- the last buffer the box was known to hold something legal in.
	o.edit = nil
	o.editTopRow = 1
	o.editAsk = false
	o.editPrev = nil
	o.editMessage = nil
	o.editSynced = nil
	o.editSyncAt = 0
	o.editLeaving = false
	o.editLeaveFrom = 0
	o.editLeaveMessage = ""
	o.opened = false
	o.busy = false
	o.busySince = 0
	o.lastKeySound = 0
	o.lastKeyAt = 0
	-- The character at the keyboard: the open-ended typing action, the height
	-- it plays the loot animation at, a chair he owes a sit to, and -- when there
	-- is no chair -- a step back to the stand point he owes the keyboard.
	o.typeAction = nil
	o.typeHeight = nil
	o.wantSit = nil
	o.wantStand = nil

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
	local entry = ISTextEntryBox:new("", 0, WINDOW_H + CELL_H, SCREEN_W * 3, CELL_H * 2)
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
	entry.onPressUp = function() self:onKeystroke(); self:onHistory(1) end
	entry.onPressDown = function() self:onKeystroke(); self:onHistory(-1) end
	entry.onTextChange = function() self:onKeystroke() end
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
	elseif command == "highlight" then
		self:startHighlight(args)
	elseif command == "completed" then
		self:onCompleted(args)
	elseif command == "history" then
		-- The account's own lines, as the machine holds them (~/.sh_history).
		-- Up and Down walk THESE: the window remembers nothing of its own any
		-- more, so a survivor who walks away, comes back and presses Up gets
		-- what he typed yesterday.
		self.history = args.lines or {}
		self.historyIndex = 0
		self.historyUser = self.screenUser
	end
end

--
-- `dev find` on a door or a window
--
-- A light answers "which one am I" by blinking, which the server does and
-- everybody in the room sees. A door and a window have nothing to do that with,
-- so the server tells the ONE window that asked where to look, and the outline
-- is drawn here, for this player and nobody else at the same computer: every
-- one of vanilla's four highlight calls takes the local player number first
-- (media/lua/client/ISUI/ISWorldObjectContextMenu.lua:281-287).
--
-- The object is found again on this side rather than sent over: a Java handle
-- does not travel, and the square plus the class plus the sprite name is what
-- the server had to work with too.
--

-- A dropped sensor is not on the square's object list -- a world item lives on
-- getWorldObjects() (media/lua/client/ISUI/ISWorldObjectContextMenu.lua:2957 reads
-- it exactly so) -- and it has no sprite name to be told apart by, being drawn
-- from a model. So it is found by the item it IS, which is what the server sent.
--
-- The FIRST of its type on that tile. Two identical heads on one square is the
-- one case where the outline may land on the other one; they are both sensors,
-- both in the same place, and a player who dropped two on one tile is looking at
-- the right square either way.
function CeroSecTerminal:itemAt(args)
	local square = self:squareAt(args)
	if square == nil then return nil end
	local objects = square:getWorldObjects()
	if objects == nil then return nil end
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local item = object:getItem()
		if item ~= nil and item:getFullType() == args.item then return object end
	end
	return nil
end

function CeroSecTerminal:squareAt(args)
	if getCell == nil then return nil end
	local cell = getCell()
	if cell == nil then return nil end
	return cell:getGridSquare(args.x, args.y, args.z)
end

function CeroSecTerminal:objectAt(args)
	if args.class == "IsoWorldInventoryObject" then return self:itemAt(args) end
	local square = self:squareAt(args)
	if square == nil then return nil end
	local objects = square:getObjects()
	if objects == nil then return nil end
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		if instanceof(object, args.class) and object:getSpriteName() == args.sprite then
			return object
		end
	end
	return nil
end

function CeroSecTerminal:startHighlight(args)
	-- Both are always sent and one of them is always blank: a fixture carries a
	-- sprite and a dropped item carries a type. What must be a string is the pair,
	-- so a message missing either is a message this window does nothing with.
	if type(args.class) ~= "string" or type(args.sprite) ~= "string"
			or type(args.item) ~= "string" then
		return
	end
	-- One at a time: a second `dev find` drops the first outline rather than
	-- leaving it lit until its own clock runs out.
	self:stopHighlight()

	local object = self:objectAt(args)
	if object == nil then return end

	local seconds = args.seconds
	if type(seconds) ~= "number" or seconds <= 0 then seconds = 6 end

	local color = getCore():getObjectHighlitedColor()
	object:setHighlighted(self.playerNum, true, false)
	if color ~= nil then
		object:setHighlightColor(self.playerNum, color)
		object:setOutlineHighlight(self.playerNum, true)
		object:setOutlineHighlightCol(self.playerNum, color)
	end
	self.highlight = { object = object, until_ = getTimestampMs() + seconds * 1000 }
end

function CeroSecTerminal:stopHighlight()
	local lit = self.highlight
	if lit == nil then return end
	self.highlight = nil
	local object = lit.object
	if object == nil then return end
	object:setHighlighted(self.playerNum, false, false)
	object:setOutlineHighlight(self.playerNum, false)
end

-- Checked every frame, like everything else this window is responsible for: the
-- outline is this window's to take away, and a window that closed with one lit
-- takes it away on the way out.
function CeroSecTerminal:updateHighlight()
	local lit = self.highlight
	if lit == nil then return end
	if getTimestampMs() < lit.until_ then return end
	self:stopHighlight()
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
	self.active = args.active and true or false
	self.remote = args.remote and true or false
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
	-- Whose history the window is holding. The machine says who is logged in
	-- with every screen; when that is no longer who the history belongs to --
	-- a login, an exit, an su -- the window asks for the right one. One short
	-- string on the wire instead of a hundred lines.
	self.screenUser = args.user
	if self.opened and self.screenUser ~= self.historyUser then
		self.historyUser = self.screenUser
		self.history = {}
		self.historyIndex = 0
		self:send("histtail", {})
	end
	self.mask = args.mask and true or false
	self:setMode(args.mode)
	-- After setMode, never before: a change of mode empties the input line, and
	-- the buffer is loaded into that same line.
	self:applyEdit(args.edit)
end

function CeroSecTerminal:closedByServer(reason)
	CeroSec.log("terminal closed by the server: " .. tostring(reason))
	self:close()
end

--
-- The screen
--

-- A line the window says on its own account. There are two of those -- the
-- answer that never came, and the listing a second Tab prints -- and both are
-- gone the moment the server describes the screen again, which is the right
-- lifetime for either: neither is something the machine put on its screen.
function CeroSecTerminal:say(text)
	-- Never written into self.screen: that table is the server's word.
	local shown = {}
	for i = 1, #self.lines do shown[i] = self.lines[i] end
	CeroSec.ringPush(shown, text, CeroSec.CONSOLE_MAX)
	self.lines = shown
	self.scroll = 0
end

-- What the machine is waiting for: "prompt" (a name, a password, or a line a
-- command asked for -- which of the three is the machine's business), "shell",
-- "edit", or "boot" while the BIOS is still typing itself out. The prompt line
-- and the mask flag are not decided here -- they come down with the screen --
-- so the window and the machine can never drift apart about them.
function CeroSecTerminal:setMode(mode)
	mode = mode or "prompt"
	-- Only a change empties the input line. Every screen the machine sends
	-- lands here, including the ones another player standing at the same
	-- computer caused, and a half-typed command must survive those.
	local changed = self.mode ~= mode
	self.mode = mode
	self.entry:setMasked(self.mask and true or false)
	if changed then
		self.entry:setText("")
		self.historyIndex = 0
		self.editPrev = nil
		self.tabLine, self.tabCursor, self.tabNames = nil, nil, nil
	end
	self:configureEntry()
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
-- Our box is not on the glass at all -- it is parked outside the window, where
-- the stencil clips everything it paints -- so a click can never land on it and
-- "click the terminal to type again" cannot mean hitting it. It means what it
-- says: every mouse press on the window, wherever it lands, hands the keyboard
-- back to the box, and puts the character back at the keyboard with it
-- (resettle). Same wiring as the chat, which
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
	self:resettle()
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

-- How many rows the line being typed takes. One, until it wraps.
function CeroSecTerminal:inputHeight()
	-- Nothing is drawn to type at while a script has the machine: the row the
	-- prompt would be on is the next line of the script's own output.
	if not self.entryActive or self.mode == "edit" or self.mode == "job" then return 0 end
	local rows = CeroSec.inputRows(self.prompt or "", self.entry:getInternalText() or "", nil)
	return #rows
end

-- Which row the prompt is on: right under the last line printed, the way a
-- terminal fills its screen, and pinned so the whole wrapped line still fits.
function CeroSecTerminal:inputRow()
	local rows = self:viewRows()
	local shown = #self.lines - self.scroll
	if shown < 0 then shown = 0 end
	if shown > rows then shown = rows end
	return shown
end

-- Am I the one typing in the editor?
function CeroSecTerminal:editing()
	return self.mode == "edit" and self.edit ~= nil and self.edit.mine and true or false
end

-- One line or a whole buffer. The box is the only thing in this game that can
-- take a keystroke, so it is used for both, and the two want it set up
-- differently: maxLines gates Enter (UITextBox2.onKeyEnter refuses when
-- lines.size() >= getMaxLines(), and the constructor leaves it at 1), and
-- multipleLine is what makes Enter insert a newline instead of calling
-- onCommandEntered.
function CeroSecTerminal:configureEntry()
	local editing = self:editing()
	if self.entryEditing == editing then return end
	self.entryEditing = editing
	if editing then
		self.entry:setMultipleLine(true)
		self.entry:setMaxLines(CeroSec.EDIT_MAX_BYTES)
		self.entry:setMaxTextLength(CeroSec.EDIT_MAX_BYTES)
	else
		self.entry:setMultipleLine(false)
		self.entry:setMaxLines(1)
		self.entry:setMaxTextLength(CeroSec.INPUT_MAX)
	end
	-- The layout cache cannot survive a change of shape.
	self.laidOut = nil
end

-- Put the cursor back at an absolute offset into the buffer.
--
-- UITextBox2.getCursorPos answers an absolute index -- putCharacter,
-- onKeyLeft, onKeyRight, onKeyBack and onKeyDelete all substring the text at
-- it -- but setCursorPos, in multiple-line mode, clamps what it is given
-- against the length of the *display line* the cursor happens to be on, which
-- is not the same number. In single line mode it clamps against the whole
-- text, which is. So the flag is turned off around the one call; both are plain
-- field writes (setMultipleLine, setCursorPos).
function CeroSecTerminal:setCursor(offset)
	self.entry:setMultipleLine(false)
	self.entry:setCursorPos(offset or 0)
	self.entry:setMultipleLine(self.entryEditing and true or false)
end

-- The box is parked off the glass, in every mode. It has to keep being
-- *rendered* -- UITextBox2.render is what repaginates it and what recomputes
-- the display line its Up and Down keys walk -- and there is no way to make it
-- draw nothing: its caret colour is a hardcoded field with no setter. So it is
-- put outside the window's own stencil rect, where every pixel it paints is
-- clipped away. ISCollapsableWindow:prerender sets that rect to
-- (0, 0, width, height) and :render clears it, and UIElement.render calls the
-- Lua prerender, then the children, then the Lua render -- so the children are
-- drawn with the rect in force. UIElement.render only *skips* a child outside
-- its parent when the parent's renderClippedChildren is false, and that field
-- is true from the constructor.
--
-- Three screens wide so a full row is never soft-wrapped by the box's own
-- pagination: Paginate() splits the text on "\n" and then on the box's width,
-- and it is those pieces that the editor's Up and Down keys walk.
--
-- Everything on the glass -- the prompt, what has been typed, the wrap onto the
-- next row, the block cursor -- is drawn by the window.
function CeroSecTerminal:layoutEntry()
	if self.laidOut == PARKED then return end
	self.laidOut = PARKED
	self.entry:setX(0)
	self.entry:setY(WINDOW_H + CELL_H)
	self.entry:setWidth(SCREEN_W * 3)
	self.entry:setHeight(CELL_H * CeroSec.EDIT_ROWS)
end

--
-- Input
--

-- One click per key. Four single keys cut out of the old long typing sample,
-- picked at random so a held key does not sound like a machine, plus a heavier
-- one for Enter. Played the way the vanilla map screen plays its own
-- interaction sounds -- character:playSoundLocal (ISMap.lua:210,245) -- so it
-- costs no packet, is heard by the player at the keyboard, and is nothing a
-- zombie can walk towards.
CeroSecTerminal.KEY_SOUNDS = { "CeroSecKey1", "CeroSecKey2", "CeroSecKey3", "CeroSecKey4" }

-- Two clicks closer together than this are one press as far as the ear is
-- concerned; below it they smear instead of ticking. Nothing above it is
-- throttled: a fast typist gets a fast keyboard.
CeroSecTerminal.KEY_MIN_MS = 40

function CeroSecTerminal:onKeystroke(sound)
	local now = getTimestampMs()
	self.lastKeyAt = now
	if now - self.lastKeySound < CeroSecTerminal.KEY_MIN_MS then return end
	self.lastKeySound = now
	if sound == nil then
		local list = CeroSecTerminal.KEY_SOUNDS
		sound = list[ZombRand(#list) + 1]
	end
	self.playerObj:playSoundLocal(sound)
end

-- Has a key been pressed in the last so many milliseconds? What the typing
-- action asks to decide whether the hands are on the keyboard.
function CeroSecTerminal:typingRecently(ms)
	if self.lastKeyAt == 0 then return false end
	return getTimestampMs() - self.lastKeyAt < ms
end

-- Does this window have the keyboard? Focus in this game is one static field,
-- and the box knows whether it is the one in it.
function CeroSecTerminal:hasKeyboard()
	return self.entry ~= nil and self.entry:isFocused() and true or false
end

--
-- The character at the keyboard
--
-- One open-ended timed action holds the typing animation and the facing for as
-- long as the window is open (ISCeroSecTypeAction). The queue is strictly
-- sequential, so that action is at its head and nothing can be queued behind it
-- and expect to run: anything the window wants done -- sitting back down --
-- means getting rid of it first and putting a fresh one in once the queue is
-- free again. That is what updateSettle does, a frame at a time, on what it can
-- see rather than on when a stop is assumed to have landed.
--

function CeroSecTerminal:startTyping(height)
	self.typeHeight = height or self.typeHeight or "mid"
end

function CeroSecTerminal:stopTyping()
	local action = self.typeAction
	self.typeAction = nil
	-- Not forceStop: the flag is read by isValid, which the engine asks every
	-- tick, so the action goes on the engine's own schedule and not on a guess
	-- about when a stop takes effect.
	if action then action.cancelled = true end
end

-- Getting the keyboard back puts the character back the way the window found
-- him: in the chair if there is one, at the keyboard if there is not, and facing
-- the screen. He is never walked off the front square -- stepping off it closes
-- the window (stillValid) -- so this only ever undoes a stand-up, a look around,
-- or a drift of a few tenths of a tile inside the square.
function CeroSecTerminal:resettle()
	if self.closing or self.typeHeight == nil then return end
	if not self:stillValid() then return end
	local chair = CeroSecReach.chairInFront(self.computer)
	if chair == nil then
		-- Nothing to sit on: the character is on his feet, and where he belongs
		-- on his feet is the stand point, against the desk (CeroSecReach). A
		-- shove, a step back from a zombie or a walk cut short inside the square
		-- leaves him short of it, and this is what walks the tenth of a tile
		-- back. Only when he has really drifted: a click on the window that
		-- changed nothing must queue nothing, or every press would restart the
		-- typing action.
		if self.wantStand then return end
		if CeroSecReach.atStandPoint(self.playerObj, self.computer) then return end
		self.wantStand = true
		self:stopTyping()
		return
	end
	if CeroSecReach.isSeatedOn(self.playerObj, chair) then return end
	if self.wantSit ~= nil then return end
	self.wantSit = chair
	self:stopTyping()
end

function CeroSecTerminal:updateSettle()
	if self.closing or self.typeHeight == nil then return end
	local playerObj = self.playerObj
	if not playerObj or playerObj:isDead() then return end
	-- Never on top of what vanilla is already doing: the sit is a timed action
	-- of its own, and a second one queued while it runs would sit him down
	-- twice (ISTimedActionQueue.isPlayerDoingAction, ISTimedActionQueue.lua:268,
	-- which is empty character actions plus a short list of states).
	if ISTimedActionQueue.isPlayerDoingAction(playerObj) then return end

	local chair = self.wantSit
	if chair ~= nil then
		self.wantSit = nil
		if chair:getSquare() and not CeroSecReach.isSeatedOn(playerObj, chair) then
			-- To the seat point first, exactly like the way in: the rest action
			-- reads the character's position to decide which side of the chair
			-- he is taking, and a character who stood up and stepped half a tile
			-- would sit back down facing the wrong way (CeroSecReach.seatSpot).
			local x, y, z = CeroSecReach.approachPoint(playerObj, self.computer)
			if x ~= nil then
				ISTimedActionQueue.add(ISPathFindAction:pathToLocationF(playerObj, x, y, z))
			end
			-- The same call the context menu makes on the way in, which is the
			-- one the vanilla menu makes (ISWorldObjectContextMenu.lua:948).
			ISTimedActionQueue.add(ISRestAction:new(playerObj, chair, true))
			return
		end
	end

	-- The same walk, for a character with no chair to take: to the stand point,
	-- and then the typing action goes back in behind it (below). The walk is the
	-- whole of it -- the turn is the typing action's own waitToStart.
	if self.wantStand then
		self.wantStand = nil
		if not CeroSecReach.atStandPoint(playerObj, self.computer) then
			local x, y, z = CeroSecReach.approachPoint(playerObj, self.computer)
			if x ~= nil then
				ISTimedActionQueue.add(ISPathFindAction:pathToLocationF(playerObj, x, y, z))
			end
		end
	end

	if self.typeAction == nil then
		local action = ISCeroSecTypeAction:new(playerObj, self.computer, self.typeHeight, self)
		self.typeAction = action
		ISTimedActionQueue.add(action)
	end
end

-- Enter. Nothing is echoed here: the line goes to the machine, and it comes
-- back on the screen the machine sends everybody standing at it. That round
-- trip is what makes the second player see the first one typing.
function CeroSecTerminal:onCommandEntered()
	if self.busy or self.revealing then return end
	local text = self.entry:getInternalText() or ""
	self.entry:setText("")
	self.historyIndex = 0
	self.tabLine, self.tabCursor, self.tabNames = nil, nil, nil
	self:onKeystroke("CeroSecKeyEnter")

	if self.mode == "prompt" then
		-- An empty answer at the very first prompt is a bare Enter and not a
		-- login attempt; everywhere else it is an answer, because an empty
		-- password is one -- the accounts ship open.
		if text == "" and not self.mask and self.prompt == "login: " then return end
		self:setBusy()
		self:send("input", { text = text })
		return
	end

	if self.mode == "shell" then
		-- Kept here too, so Up works on the line just typed without waiting for
		-- the machine to hand the file back. The file is still the truth: the
		-- next screen that changes account replaces the lot.
		if text ~= "" then
			CeroSec.ringPush(self.history, text, CeroSec.HISTORY_MAX)
		end
		self:setBusy()
		self:send("exec", { line = text })
	end
	-- "job" falls through: Enter at a running script is Enter at a machine that
	-- is not listening, and sending it would only make the server answer with
	-- the screen it already sent.
end

--
-- The editor
--
-- The buffer belongs to the machine, like the screen: edit <file> puts it in
-- the console, and the window is handed it. While this window is the one typing
-- in it, the text box holds the truth between two syncs, and the machine's copy
-- is only taken back when this window was not already on this file -- opening
-- it, or coming back to it after walking away. A screen the machine sends
-- because somebody else moved must never take the buffer out from under the
-- fingers.
--

-- What the machine last said about the buffer.
function CeroSecTerminal:applyEdit(edit)
	local was = self.edit
	self.edit = edit
	if edit == nil then
		self.editAsk = false
		self.editLeaving = false
		self.editMessage = nil
		self.editPrev = nil
		return
	end
	if not edit.mine then
		self.editAsk = false
		self.editLeaving = false
		return
	end
	if was == nil or not was.mine or was.path ~= edit.path then
		self:loadBuffer(edit.text or "")
		return
	end
	-- The answer to the save question: y saves and *then* leaves, so leaving
	-- waits for the machine to say the write happened. What is waited on is the
	-- machine's count of writes to this buffer, not the words on the message
	-- line: a screen pushed by somebody else's keystroke in between carries the
	-- message of the *previous* save, and leaving on that would drop a buffer
	-- that had not been written yet. An error keeps the buffer and puts the
	-- reason on the message line, which is what nano does.
	if self.editLeaving then
		if (edit.saves or 0) > self.editLeaveFrom then
			self.editLeaving = false
			self:send("editexit", {})
		elseif (edit.message or "") ~= self.editLeaveMessage then
			self.editLeaving = false
		end
	end
end

-- The machine's buffer becomes this window's.
function CeroSecTerminal:loadBuffer(text)
	self:configureEntry()
	self.entry:setText(text)
	-- SetText leaves the cursor at the start, which is where nano opens a file.
	self.editPrev = { text = text, pos = 0 }
	self.editTopRow = 1
	self.editAsk = false
	self.editMessage = nil
	self.editSynced = text
	self.editSyncAt = getTimestampMs()
	self.editLeaving = false
end

-- The buffer this window is showing. While the save question is up the box has
-- been emptied to catch the answer, so the last accepted text is the buffer.
function CeroSecTerminal:bufferText()
	if not self:editing() then
		if self.edit then return self.edit.text or "" end
		return ""
	end
	if self.editAsk then return self.editPrev and self.editPrev.text or "" end
	return self.entry:getInternalText() or ""
end

function CeroSecTerminal:editModified()
	if not self.edit then return false end
	return self:bufferText() ~= (self.edit.disk or "")
end

-- Every frame, while this window is the one typing. Three jobs: catch the
-- answer to the save question, refuse a keystroke the machine could never
-- store, and hand the buffer to the machine now and then.
function CeroSecTerminal:updateEditor()
	if not self:editing() then return end
	if self.editAsk then
		self:pollAnswer()
		return
	end

	local text = self.entry:getInternalText() or ""
	local prev = self.editPrev
	if prev == nil then
		self.editPrev = { text = text, pos = self.entry:getCursorPos() or 0 }
		return
	end

	if text ~= prev.text then
		local refusal = CeroSec.editRefusal(text)
		if refusal ~= nil and CeroSec.editBadness(text) >= CeroSec.editBadness(prev.text) then
			-- Refused under the fingers: the character never lands, and the
			-- cursor goes back where it was before it was typed. Only when it
			-- made things no better, though -- a file the shell wrote can hold
			-- a row wider than the screen, and an editor that undid the
			-- backspaces on it would be an editor that could never fix it.
			self.entry:setText(prev.text)
			self:setCursor(prev.pos)
			self.editMessage = refusal
			return
		end
		-- UITextBox2.onKeyEnter inserts the newline itself in multiple-line mode
		-- and does not call onTextChange, so a new row is where Enter is heard.
		if #CeroSec.editLines(text) > #CeroSec.editLines(prev.text) then
			self:onKeystroke("CeroSecKeyEnter")
		end
		self.editPrev = { text = text, pos = self.entry:getCursorPos() or 0 }
		-- Accepted, but say so while it is still over a ceiling: the buffer is
		-- getting better and is not there yet.
		self.editMessage = refusal
	else
		prev.pos = self.entry:getCursorPos() or 0
		-- The box stops taking typed characters at UITextBox2.textEntryMaxLength
		-- (2000, no setter): nothing happens and nothing is said, so say it.
		if #text >= CeroSec.EDIT_TYPED_MAX and self.editMessage == nil then
			self.editMessage = "Buffer full: " .. CeroSec.EDIT_TYPED_MAX .. " typed characters"
		end
	end

	self:syncBuffer(false)
end

-- The question under the buffer. y and n are letters, and a focused text box
-- eats letters -- the game hands it exactly two keys, Escape and Tab
-- (Core.updateKeyboardAux). So while the question stands the box is emptied,
-- and whatever lands in it is the answer: one character, read and thrown away.
function CeroSecTerminal:pollAnswer()
	local typed = self.entry:getInternalText() or ""
	if typed == "" then return end
	self.entry:setText("")
	self:editKey(string.sub(typed, 1, 1))
end

function CeroSecTerminal:beginAsk()
	self.editAsk = true
	self.editMessage = nil
	self.entry:setText("")
end

function CeroSecTerminal:endAsk()
	self.editAsk = false
	local prev = self.editPrev
	if prev then
		self.entry:setText(prev.text)
		self:setCursor(prev.pos)
	end
end

-- One key, one decision, and the decision itself is CeroSec.editKeyAction --
-- pure, and tested without a game.
function CeroSecTerminal:editKey(key)
	if not self:editing() then return end
	local readonly = self.edit.readonly and true or false
	local state = self.editAsk and "ask" or "edit"
	local action = CeroSec.editKeyAction(state, key, self:editModified(), readonly)

	if action == "again" then
		if state == "ask" then self.entry:setText("") end
		return
	end
	if action == "cancel" then
		self:endAsk()
		return
	end
	if action == "ask" then
		self:beginAsk()
		return
	end
	if action == "leave" then
		self.editAsk = false
		self.editLeaving = false
		self:send("editexit", {})
		return
	end
	if action == "save" then
		self:sendSave()
		return
	end
	if action == "saveleave" then
		-- The buffer is still what it was before the question went up.
		self.editAsk = false
		self.editLeaving = true
		self.editLeaveFrom = self.edit.saves or 0
		self.editLeaveMessage = self.edit.message or ""
		self:sendSave()
		return
	end
	if action == "readonly" then
		self.editMessage = "Cannot save: permission denied"
	end
end

function CeroSecTerminal:sendSave()
	local text = self:bufferText()
	self.editMessage = nil
	self.editSynced = text
	self.editSyncAt = getTimestampMs()
	self:send("editsave", { text = text })
end

-- Hand the buffer to the machine, so that the work is the machine's and not
-- this window's. Only when it has changed, and -- unless the window is on its
-- way out -- never more often than EDIT_SYNC_MS.
function CeroSecTerminal:syncBuffer(force)
	if not self:editing() then return end
	local text = self:bufferText()
	if text == self.editSynced then return end
	local now = getTimestampMs()
	if not force and now - self.editSyncAt < CeroSec.EDIT_SYNC_MS then return end
	self.editSynced = text
	self.editSyncAt = now
	self:send("editbuf", { text = text })
end

-- What the bottom row says. The question first, then whatever this window has
-- to say on its own account, then the machine's word.
function CeroSecTerminal:editMessageLine()
	if self.editAsk then return "Save modified buffer? (y/n)" end
	if self.editMessage then return self.editMessage end
	if self.edit and not self.edit.mine then return "Another user is editing" end
	if self.edit then return self.edit.message end
	return nil
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

--
-- Tab: completion
--
-- Tab is one of exactly two keys the game hands a focused text box, and in the
-- shell it is free -- the editor's Tab is nano's ^O and is not touched. What the
-- word may become is the machine's word and never this window's: the line and
-- the cursor go over, the answer comes back, and nothing is guessed here.
--
-- Two presses, the way ksh has answered since the eighties. The first completes
-- as far as the names agree; the second, on the same word and with several names
-- to choose from, prints them in columns. The prompt row is drawn under the
-- screen in this window, so a listing pushed onto the screen leaves the prompt
-- and the half-typed line right below it -- which is the third row ksh draws.
--

function CeroSecTerminal:onTab()
	-- Only at a shell prompt: a question, a password, a running job and the
	-- editor have no command line being typed at them. Busy is the answer that
	-- has not come back yet, and revealing is a machine still counting memory.
	if self.mode ~= "shell" then return end
	if self.busy or self.revealing then return end

	local text = self.entry:getInternalText() or ""
	local cursor = self.entry:getCursorPos() or 0
	if cursor < 0 then cursor = 0 end
	if cursor > #text then cursor = #text end

	-- The second press: the same word, still several names. Answered here from
	-- what the machine already said, so a listing costs no round trip.
	if self.tabLine == text and self.tabCursor == cursor
			and self.tabNames ~= nil and #self.tabNames > 1 then
		self:listCompletions(self.tabNames)
		return
	end

	self.tabLine, self.tabCursor, self.tabNames = nil, nil, nil
	self:onKeystroke()
	self:setBusy()
	self:send("complete", { line = text, cursor = cursor })
end

-- What the machine made of the word. Applied only when the box still holds the
-- line the answer is about: a player who kept typing while it was in the air
-- must not have an older word put back under his fingers.
function CeroSecTerminal:onCompleted(args)
	self.busy = false
	if self.mode ~= "shell" then return end

	local text = self.entry:getInternalText() or ""
	local at = args.at
	if args.line ~= text or type(at) ~= "number" or at ~= self.entry:getCursorPos() then
		return
	end

	if type(args.replacement) == "string" and type(args.start) == "number" then
		-- The word to the left of the cursor is replaced and the rest of the
		-- line is kept, exactly as an insertion at the caret would leave it.
		local head = string.sub(text, 1, args.start - 1)
		local tail = string.sub(text, at + 1)
		local whole = head .. args.replacement .. tail
		-- setText does not go through the box's own length ceiling, so the one
		-- thing that could carry a line past it is checked here.
		if #whole <= CeroSec.INPUT_MAX then
			self.entry:setText(whole)
			self:setCursor(args.cursor)
		end
	end

	self.tabLine = self.entry:getInternalText() or ""
	self.tabCursor = self.entry:getCursorPos() or 0
	self.tabNames = args.candidates
	if type(self.tabNames) ~= "table" then self.tabNames = {} end
end

-- The names, in columns, the way `ls` packs them on a sixty column screen --
-- the engine's own columniser, so a listing is laid out exactly as a directory
-- listing is.
function CeroSecTerminal:listCompletions(names)
	local lines = CeroSecOS.columnize(names, CeroSec.COLS)
	for i = 1, #lines do self:say(lines[i]) end
end

-- Escape and Tab: the game hands a focused text box exactly two keys,
-- Escape (1) and Tab (15), and dispatches every other key to a method of its
-- own (Core.updateKeyboardAux in the shipped build). PageUp and PageDown never
-- arrive, and cannot be polled for either -- isKeyPressed and isShiftKeyDown
-- both answer false while a box is taking text (GameKeyboard.isKeyDown). So the
-- scrollback scrolls with the wheel; see the note in docs/TEST-rung2.md.
function CeroSecTerminal:onOtherKey(key)
	-- In the editor those two keys are nano's ^X and ^O -- the only two the
	-- game will let through -- and neither of them closes the window. The
	-- window shuts on the close box, or by walking away.
	if self:editing() then
		if key == Keyboard.KEY_ESCAPE then self:editKey("escape") end
		if key == Keyboard.KEY_TAB then self:editKey("tab") end
		return
	end
	-- Outside the editor Tab is completion, and only at a shell prompt: onTab
	-- is what decides that, so there is one place that knows when a word may be
	-- completed.
	if key == Keyboard.KEY_TAB then
		self:onTab()
		return
	end
	if key ~= Keyboard.KEY_ESCAPE then return end

	-- Escape interrupts what the machine is in the middle of, and closes the
	-- window when it is not in the middle of anything: the ^C of a 1993
	-- terminal, which never shut anything, and the close of a window that has
	-- nothing to give up on. Which of the two it is is the machine's word
	-- (args.active) and never something worked out from the prompt on the
	-- glass -- the window cannot tell "New password: " from any other question,
	-- and should not have to.
	-- A remote session is the one place Escape means something at an IDLE prompt
	-- too: the survivor is still standing at his own machine, so the window has
	-- nothing to shut, and what there is to give up on is the connection. The
	-- machine decides which of the two it is; the window only asks.
	if self.active or self.remote then
		self:setBusy()
		self:send("interrupt", {})
		return
	end
	self:close()
end

function CeroSecTerminal:viewRows()
	return CeroSec.ROWS - self:inputHeight()
end

function CeroSecTerminal:scrollBy(rows)
	self.scroll = CeroSec.clampScroll(self.scroll + rows, #self.lines, self:viewRows())
end

function CeroSecTerminal:onMouseWheel(del)
	-- In the editor the view follows the cursor and nothing else, the way nano
	-- does it: a wheel that scrolled it would be pulled straight back on the
	-- next frame. Swallowed rather than passed on, so the wheel over an editor
	-- does not scroll whatever is behind the window.
	if self.mode == "edit" then return true end
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
	-- Walking away leaves the machine in the editor with the buffer it has, so
	-- the last of it goes out now rather than at the next tick that will not
	-- come. The file is not touched: this is the screen, not a save.
	if self.opened then self:syncBuffer(true) end
	-- The character stops being at the keyboard the moment the window does.
	self:stopTyping()
	self:stopHighlight()
	self.wantSit = nil
	self.wantStand = nil
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
	self:setMode("prompt")
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
	self:updateHighlight()
	self:checkTimeout()
	self:updateSettle()
	self:configureEntry()
	self:updateEditor()
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

	-- The editor takes the whole glass: two inverted bars, seventeen rows of
	-- the buffer and a line for what the machine has to say. Nothing of the
	-- shell is on the screen while it is up.
	if self.mode == "edit" and self.edit then
		self:drawEditor(left, top)
		self:drawScanlines()
		ISCollapsableWindow.render(self)
		return
	end

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

	-- "job": the machine is running a script and there is no prompt to draw.
	-- What a player types while it runs goes nowhere and is never shown -- the
	-- moment the script asks something the mode is "prompt" again and the line
	-- is back, empty, ready for the answer.
	if self.entryActive and self.mode ~= "job" then
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

-- How far the pen moves over a string: what drawText advances by, and so where
-- the character AFTER that string is painted. The one place the font is asked,
-- so the columns of a drawn row and the block cursor on it are placed by the
-- same answer or they disagree by a character.
--
-- Not MeasureStringX itself -- that answers the ink of the last glyph in place
-- of its advance; see CELL_W at the top of the file for why, and for why this
-- subtraction is exact.
local function advance(text)
	if text == nil or text == "" then return 0 end
	return getTextManager():MeasureStringX(UIFont.Code, text .. "M") - M_INK
end

-- Where a column of a drawn row is on the glass: the width of everything in
-- front of it, measured on the very text that was painted and in the font it
-- was painted with. Counting cells instead is only right for as long as the
-- cell is exactly what the font advances by, and the cell is one measurement
-- taken at one moment -- which is how the block cursor came to sit a dozen
-- columns to the right of the end of the prompt.
function CeroSecTerminal:columnX(x, text, column)
	if column <= 0 then return x end
	return x + advance(string.sub(text, 1, column))
end

-- The prompt, what has been typed, and the block cursor over it. A line longer
-- than the glass wraps onto the rows under it, the way a terminal does, and the
-- cursor follows it there: the rows and the cursor's place on them are worked
-- out by CeroSec.inputRows, which is pure and tested headless.
--
-- Which column a character is in is counted; where that column IS on the glass
-- is the pen's advance over the text in front of it, asked of the font on the
-- very string that was painted. Counting cells instead is only right for as
-- long as the cell is exactly what the font advances by.
function CeroSecTerminal:drawInput(x, y)
	local colors = CeroSec.COLORS
	local prompt = self.prompt or ""
	local text = self.entry:getInternalText() or ""
	if self.mask then text = string.rep("*", #text) end

	local rows, row, col = CeroSec.inputRows(prompt, text, self.entry:getCursorPos())
	local head = #prompt
	if head > CeroSec.COLS - 1 then head = CeroSec.COLS - 1 end

	for i = 1, #rows do
		local ry = y + (i - 1) * CELL_H
		if i == 1 then
			self:drawScreenText(string.sub(rows[1], 1, head), x, ry, colors.dim)
			self:drawScreenText(string.sub(rows[1], head + 1), self:columnX(x, rows[1], head), ry, colors.text)
		else
			self:drawScreenText(rows[i], x, ry, colors.text)
		end
	end

	-- Solid block, on for half a second and off for half a second, and both
	-- halves at the same column: CeroSec.cursorSpan answers where the block is
	-- and which character it covers, and the two halves differ only in the
	-- colours. Lit, the block is the text colour and the character it covers is
	-- repainted in the screen's own colour, so the cursor never hides what it
	-- is on; dark, the block is the screen's colour and the character goes back
	-- to the colour of its row. At the end of the line there is no character to
	-- cover and none is drawn. Column 60 is the one place it lies -- a full row
	-- has nowhere to put the cursor after its last character -- and there it
	-- sits on that character instead.
	local cell = col
	if cell > CeroSec.COLS - 1 then cell = CeroSec.COLS - 1 end
	local line = rows[row] or ""
	local ahead, typed, index = "", line, cell
	if row == 1 and cell >= head then
		ahead, typed, index = string.sub(line, 1, head), string.sub(line, head + 1), cell - head
	end
	local span, under, width = CeroSec.cursorSpan(ahead, typed, index, advance)
	local cx = x + span
	local cy = y + (row - 1) * CELL_H
	-- The block is the advance of the character it covers -- the cell, on a
	-- monospaced face -- and never CELL_W measured elsewhere.
	local cw = width or CELL_W
	if CeroSec.DEBUG then
		CeroSec.log("cursor: index " .. tostring(index) .. "/" .. tostring(#typed) ..
			" row " .. tostring(row) .. " col " .. tostring(cell) ..
			" x " .. tostring(cx) .. " block " .. tostring(cw) ..
			" cell " .. tostring(CELL_W) .. " under " .. tostring(under))
	end
	local lit = math.floor(getTimestampMs() / CeroSec.CURSOR_BLINK_MS) % 2 == 0
	local block = lit and colors.text or colors.screen
	self:drawRect(cx, cy, cw, CELL_H, 1, block.r, block.g, block.b)
	if under and under ~= " " then
		local ink = colors.screen
		if not lit then ink = (ahead == "" and row == 1) and colors.dim or colors.text end
		self:drawText(under, cx, cy, ink.r, ink.g, ink.b, 1, UIFont.Code)
	end
end

-- The editor's screen. Every row of it is composed by CeroSec.editScreen,
-- which is pure and tested headless; what is left here is the paint: two
-- inverted bars, the text, and the block cursor.
function CeroSecTerminal:drawEditor(left, top)
	local colors = CeroSec.COLORS
	local mine = self:editing()
	local text = self:bufferText()
	local lines = CeroSec.editLines(text)

	local row, col = 1, 0
	if mine then
		local offset = self.entry:getCursorPos() or 0
		if self.editAsk then offset = self.editPrev and self.editPrev.pos or 0 end
		row, col = CeroSec.editCursor(text, offset)
	end
	self.editTopRow = CeroSec.editTop(self.editTopRow, row, #lines, CeroSec.EDIT_ROWS)

	local flag = nil
	if self.edit.readonly then
		flag = "read-only"
	elseif self:editModified() then
		flag = "modified"
	end

	local screen = CeroSec.editScreen(text, self.editTopRow, self.edit.path, flag,
		self:editMessageLine())

	self:drawBar(screen[1], left, top)
	for i = 2, 1 + CeroSec.EDIT_ROWS do
		self:drawScreenText(screen[i], left, top + (i - 1) * CELL_H, colors.text)
	end
	self:drawBar(screen[CeroSec.ROWS - 1], left, top + (CeroSec.ROWS - 2) * CELL_H)
	self:drawScreenText(screen[CeroSec.ROWS], left, top + (CeroSec.ROWS - 1) * CELL_H, colors.dim)

	if not mine or self.editAsk then return end

	-- The block, at the same column in both halves of the blink, and the
	-- character it covers repainted over it: in the screen's own colour while
	-- the block is lit, in the text's while it is dark, so a cursor in the
	-- middle of a line neither hides what it is on nor eats it for half a
	-- second. Column 60 is the one place it lies -- a full line has nowhere to
	-- put the cursor after its last character -- and it sits on that character
	-- instead.
	local cell = col
	if cell > CeroSec.COLS - 1 then cell = CeroSec.COLS - 1 end
	local span, under, width = CeroSec.cursorSpan("", lines[row] or "", cell, advance)
	local x = left + span
	local y = top + (row - self.editTopRow + 1) * CELL_H
	local lit = math.floor(getTimestampMs() / CeroSec.CURSOR_BLINK_MS) % 2 == 0
	local block = lit and colors.text or colors.screen
	self:drawRect(x, y, width or CELL_W, CELL_H, 1, block.r, block.g, block.b)
	if under then
		local ink = lit and colors.screen or colors.text
		self:drawText(under, x, y, ink.r, ink.g, ink.b, 1, UIFont.Code)
	end
end

-- An inverted row: the dim green filled in, the screen's own colour written on
-- it. No halo -- a glow around dark text on a light bar is a smudge.
function CeroSecTerminal:drawBar(text, x, y)
	local colors = CeroSec.COLORS
	self:drawRect(x, y, SCREEN_W, CELL_H, 1,
		colors.barBack.r, colors.barBack.g, colors.barBack.b)
	self:drawText(text or "", x, y,
		colors.barText.r, colors.barText.g, colors.barText.b, 1, UIFont.Code)
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
	-- The one answer that is not for a window: it is the request for one. It
	-- carries no window's token because the window it names has not been made
	-- yet, so it never goes round the loop below.
	if command == "reopened" then
		CeroSecTerminal.reopen(args)
		return
	end
	for _, window in pairs(CeroSecTerminal.instances) do
		window:onServerCommand(command, args)
	end
end

-- The computer at these coordinates, found on this side. A Java handle does not
-- travel, so the square is asked for here the way `dev find` asks for one
-- (objectAt), and the sprite is what says which object on the tile it is.
local function computerAt(x, y, z)
	if getCell == nil then return nil end
	local cell = getCell()
	if cell == nil then return nil end
	local square = cell:getGridSquare(x, y, z)
	if square == nil then return nil end
	local objects = square:getObjects()
	if objects == nil then return nil end
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		if CeroSec.isComputerSprite(object:getSpriteName()) then return object end
	end
	return nil
end

-- A machine this player was sitting at has finished rebooting. The server kept
-- his place across the dark interval, minted the token and added the watcher, so
-- nothing is asked for and nothing is invented: the window is built around the
-- screen that arrived with the message, and the `opened` handler does the rest
-- of it exactly as it does for a window that asked.
--
-- The height is worked out here rather than sent, the same way the context menu
-- works it out (CeroSecReach.height): it is a fact about the desk the computer
-- stands on, which the client can see and which did not change while the machine
-- was dark.
function CeroSecTerminal.reopen(args)
	if type(args.player) ~= "number" or args.token == nil then return end
	local playerObj = getSpecificPlayer(args.player)
	if not playerObj or playerObj:isDead() then return end
	local computer = computerAt(args.x, args.y, args.z)
	if computer == nil then return end
	-- The player has to be able to be there. Asked again on this side because
	-- this is the side that knows where he is standing THIS frame, and because a
	-- window that opened onto a square he is not on would shut itself the next
	-- one (stillValid).
	local front = CeroSecReach.frontSquare(computer)
	if front == nil then return end
	local square = CeroSecReach.standingSquare(playerObj, computer)
	if square == nil or square:getX() ~= front:getX() or square:getY() ~= front:getY()
			or square:getZ() ~= front:getZ() then
		return
	end
	local window = CeroSecTerminal.sitDown(playerObj, computer,
		CeroSecReach.height(computer), args.token)
	if window == nil then return end
	window:onServerCommand("opened", args)
end

-- Shut whatever terminal is open on this computer, wherever the news came from.
function CeroSecTerminal.closeAt(x, y, z)
	for _, window in pairs(CeroSecTerminal.instances) do
		if window.cx == x and window.cy == y and window.cz == z then window:close() end
	end
end
