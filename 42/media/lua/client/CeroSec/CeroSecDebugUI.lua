require "ISUI/ISCollapsableWindow"
require "ISUI/ISTabPanel"
require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecContent"
require "CeroSec/CeroSecTerminal"

--
-- The debug window.
--
-- Six tabs of what the mod is actually doing: every computer the server holds,
-- the selected machine's filesystem and its /dev, the wire, the scheduler, and
-- the mod's own log. Read-mostly: what it can change is the selected machine's
-- power, where the player is standing, -- behind two clicks, and only on a
-- machine that is off -- the machine back into one nobody has ever used
-- (onReset, and docs/DEBUG.md for why that exists), and what a developer's own
-- bag holds (onGiveDisk). The self-test writes nothing of its own. Each goes
-- through the ordinary server commands.
--
-- IT LOOKS LIKE THE GAME'S OWN DEBUG WINDOWS and deliberately not like the
-- terminal beside it. A phosphor screen is a thing in the world that a survivor
-- reads; this is a tool, and the game already has a shape for one: an
-- ISCollapsableWindow with an ISTabPanel in it, an ISPanel per tab as that tab's
-- view, and an ISScrollingListBox with columns inside each view -- which is
-- ISEntitiesDebugWindow's shape
-- (media/lua/client/DebugUIs/DebugMenu/Entity/ISEntitiesDebugWindow.lua:46-62)
-- down to the border spacing. No colours of our own, no fonts of our own: the
-- list box's own palette and UIFont.Small, so it sits among vanilla's tools
-- rather than among ours.
--
-- The list is INSIDE a view and is not the view itself, and that is the whole of
-- what went wrong the first time: a list box with columns draws its header row
-- above its own top edge, so a list put where a tab view goes draws its headers on
-- the tab strip. See the long note on layout() below.
--
-- IT WORKS NOTHING OUT. Every row on it is a row the server built
-- (server/CeroSec/SCeroSecDebug.lua), and the window draws the cells it is
-- handed. The one thing it decides for itself is which tab is in front and which
-- machine is selected, because those are facts about a window.
--
-- ONE INSTANCE, and it remembers nothing between sessions: no saved position, no
-- saved tab, no saved selection. A debug window is opened to answer a question
-- and shut, and a tool that came back yesterday's shape would be a tool that has
-- to be put back.
--

CeroSecDebugUI = ISCollapsableWindow:derive("CeroSecDebugUI")

-- One window, not one per player. A second opening closes the first, the way the
-- terminal and the manual reader do -- and unlike those two, split screen is not
-- a case worth carrying: two survivors on one keyboard do not need two debug
-- windows, and the one there is belongs to whoever last asked for it.
CeroSecDebugUI.instance = nil

-- How often it asks the server again while it is open, in milliseconds of wall
-- clock. Two seconds: fast enough that a light switch thrown in the room shows
-- up while you are still looking at the window, slow enough that the snapshot is
-- not the most expensive thing on the server.
CeroSecDebugUI.REFRESH_MS = 2000

-- How long "Reset machine" stays armed after the first click, in the same wall
-- clock. Five seconds: long enough to read the sentence the reason line puts up
-- and click again, short enough that a window left alone is a window whose reset
-- is not armed any more. Two clicks are the whole guard -- there is no dialog, see
-- onReset.
CeroSecDebugUI.ARM_MS = 5000

CeroSecDebugUI.FONT = "Small"

-- What the login box opens on, and the longest it will hold.
--
-- "root" because that is the account somebody clearing a password is nearly always
-- after, and because a box that opened empty would be a button that refused on its
-- first press.
--
-- The ceiling is CeroSecOS.MAX_NAME's number, written out and not read off it: this
-- is client Lua and the constant is a shared file's, so reading it at load time
-- would be betting on a load order -- and the window is not what decides anyway.
-- What decides is the server, which holds the login to CeroSecOS.isValidName before
-- it reaches anything (Commands.debugact), so a box that let one character too many
-- through is a refusal and never a bad write.
CeroSecDebugUI.DEFAULT_LOGIN = "root"
CeroSecDebugUI.LOGIN_MAX = 32

-- The gap vanilla's own debug windows use between the window edge and what is in
-- it (UI_BORDER_SPACING, ISEntitiesDebugWindow.lua:6).
local BORDER = 10

-- Inside a column: the pad the LIST BOX ITSELF draws its header name at
-- (ISScrollingListBox.lua:560, `v.size + 10`), so a cell and the header over it
-- start on the same pixel; and the air left on the right before the next
-- column's rule, so two columns of text never touch.
local PAD = 10
local GAP = 6

-- The narrowest a column is ever drawn, in characters of the cell font. Four is
-- "here", "away", "jobs" and every other short word these lists hold, so a
-- column squeezed to the floor still says something.
local MIN_CELLS = 4

-- Rows of buttons under the list, and the air between them. Two: the nine this
-- window shipped with, and the eight an admin and a tester were given after it --
-- which on one row would be seventeen buttons and a window nobody's screen is wide
-- enough for.
local BUTTON_ROWS = 2
local ROW_GAP = 4

-- How wide the login box is, in characters of the cell font. Twelve: long enough for
-- every generated login the catalogue makes (CeroSecOS.MAX_USERNAME is sixteen and
-- the names are shorter than that) and short enough not to push the row it is on
-- past the disk combo beside it.
local LOGIN_CELLS = 12

-- Rows of info under the list. Nine: the two the WINDOW writes -- why a button
-- cannot be pressed, and how much of the list is showing -- and then seven of the
-- server's own, which is what the Machines tab's detail block needs. A tab with
-- less to say leaves the rest blank rather than moving the list under the
-- reader's cursor.
local INFO_ROWS = 9

--
-- The tabs
--
-- The name the tab wears, the token the server knows it by, and its columns.
-- The token is nil for the one tab the server has never heard of: the log is the
-- client's own ring buffer (CeroSec.logRing), which in singleplayer is every line
-- the mod wrote and on a dedicated client is the client's own -- see docs/DEBUG.md.
--
-- A column is a name and a NOMINAL width in characters. The nominal width is only
-- what the WINDOW is first opened at -- wide enough for the widest tab and no
-- wider. What a column is actually drawn at is measured, off its own header and
-- off the widest cell of the rows the server sent (fitColumns below): a cell is
-- text of a length nobody chose, and a column of a fixed number of characters is
-- a column that either wastes half the window or hands the next one's space away.
--
-- The names are PLAIN WORDS. "ess", "tel", "call", "jobs", "eyes" showing through
-- a tab strip is what a reader was handed, and half of them did not say what was
-- under them even when they were in the right place: "at" is x,y,z, "face" is
-- which way it is turned, and "eyes" was the number of windows open on it.
--
CeroSecDebugUI.TABS = {
	{
		name = "Machines", tab = "machines",
		columns = { { "x,y,z", 11 }, { "facing", 6 }, { "power", 5 }, { "chunk", 6 },
			{ "wire", 5 }, { "host", 14 }, { "address", 14 }, { "tel", 10 },
			{ "call", 8 }, { "jobs", 5 }, { "windows", 7 } },
	},
	{
		name = "Files", tab = "files",
		columns = { { "path", 34 }, { "type", 6 }, { "mode", 11 }, { "owner", 9 },
			{ "size", 7 }, { "modified", 13 }, { "nodes", 6 } },
	},
	{
		name = "Devices", tab = "devices",
		columns = { { "name", 9 }, { "kind", 7 }, { "where", 15 }, { "side", 5 },
			{ "mode", 11 }, { "offset", 9 }, { "square", 12 }, { "handle", 22 },
			{ "reads", 10 }, { "object", 7 } },
	},
	{
		name = "Network", tab = "network",
		columns = { { "link", 6 }, { "id", 14 }, { "from", 22 }, { "what", 22 },
			{ "detail", 30 } },
	},
	{
		name = "Scheduler", tab = "scheduler",
		columns = { { "machine", 11 }, { "id", 5 }, { "slot", 5 }, { "name", 12 },
			{ "state", 9 }, { "steps", 7 }, { "cpu", 6 }, { "debt", 6 },
			{ "how", 7 }, { "line", 9 }, { "cron", 6 } },
	},
	{
		name = "Log", tab = nil,
		columns = { { "level", 7 }, { "line", 80 } },
	},
}

-- The seven of the second row that act on a MACHINE, as the field the button is kept
-- in and the field the server's answer about it arrives as. One table, because the
-- greying and nothing else walks it: the buttons are made one by one in
-- createChildren, where each has a label and a handler of its own. "Give disk" is
-- not on it -- it is about a bag and is never greyed.
CeroSecDebugUI.ACT_BUTTONS = {
	{ "rootNoteButton", "canRootNote" },
	{ "staffNoteButton", "canStaffNote" },
	{ "accountsButton", "canAccounts" },
	{ "clearPassButton", "canClearPass" },
	{ "rootLoginButton", "canRootLogin" },
	{ "cronNowButton", "canCronNow" },
	{ "forceWireButton", "canForceWire" },
}

-- The three the Log tab filters by, and the word each button wears.
CeroSecDebugUI.LEVELS = {
	{ label = "All", level = nil },
	{ label = "Warnings", level = CeroSec.LOG_WARN },
	{ label = "Errors", level = CeroSec.LOG_ERROR },
}

-- Measured with the game up and never at load time, and again whenever the
-- answer moves -- the UI font size is an option. Same shape and same reason as
-- CeroSecTerminal's measure() and CeroSecManualUI's; see the long note in the
-- terminal for what a font measured while the mod files are being read hands
-- back.
local CELL_W, FONT_H, WINDOW_W, WINDOW_H

-- MeasureStringX's answer for a lone "M": the INK of that glyph and not its cell.
-- Only ever the subtrahend in advance() below, and the same one the terminal
-- keeps for the same reason (CeroSecTerminal.lua:70-72).
local M_INK, WIDE_W

local function measure()
	local manager = getTextManager()
	local font = UIFont[CeroSecDebugUI.FONT]
	-- Set before the early return, and not after it: a font that has not moved
	-- still has to leave this behind, or the first cell measured after a second
	-- window opens is measured against nil.
	M_INK = manager:MeasureStringX(font, "M")
	-- The ADVANCE of one cell and not the ink of one glyph: MeasureStringX counts
	-- the last character of a string as its glyph's ink width, so the difference
	-- between two and one is the advance exactly. The lesson is
	-- CeroSecTerminal's; the arithmetic is the same.
	local cellW = manager:MeasureStringX(font, "nn") - manager:MeasureStringX(font, "n")
	if cellW < 1 then cellW = 1 end
	-- The advance of the widest glyph of the face, which is what tells a cell that
	-- CANNOT overflow its column from one that has to be measured: a string of n
	-- characters is at most n of these wide.
	--
	-- Four candidates and the widest of them, not "M" alone: which glyph is the
	-- widest is the FACE's business and a proportional one is free to make "W" or
	-- "@" wider than "M" -- and a bound that is one pixel too small is a cell that
	-- skips the measurement and gets drawn over its neighbour, which is the very
	-- defect this file is fixing.
	WIDE_W = cellW
	local widest = { "M", "W", "@", "%" }
	for i = 1, #widest do
		local at = manager:MeasureStringX(font, widest[i] .. "M") - M_INK
		if at > WIDE_W then WIDE_W = at end
	end
	local fontH = manager:getFontHeight(font)
	if cellW == CELL_W and fontH == FONT_H then return end

	CELL_W, FONT_H = cellW, fontH
	-- Wide enough for the widest tab's NOMINAL columns, and no wider. The pad and
	-- the gap of every column are IN it: they are room a column needs and not room
	-- it has, and a window sized as though they were free is a window that opens
	-- with its longest cells already cut.
	local widest = 0
	for i = 1, #CeroSecDebugUI.TABS do
		local columns = CeroSecDebugUI.TABS[i].columns
		local total = #columns * (PAD + GAP)
		for k = 1, #columns do total = total + columns[k][2] * CELL_W end
		if total > widest then widest = total end
	end
	WINDOW_W = widest + BORDER * 4
	-- Twenty rows of list, the detail block, and room for EVERY button row: the
	-- second row was added after this line was written and a height that had not
	-- heard of it would open the window with nineteen rows and then eighteen.
	WINDOW_H = (FONT_H + 6) * 20 + (FONT_H + 2) * INFO_ROWS + BORDER * 6 +
		(FONT_H + 8 + ROW_GAP) * (BUTTON_ROWS - 1)
end

-- How far the pen moves over a string: what drawText advances by, and so where
-- the character AFTER it would be painted. The one measurement a column and the
-- cell in it are both worked out from, or the two disagree by a character.
--
-- Not MeasureStringX itself -- that answers the INK of the last glyph in place of
-- its advance -- and the subtraction that recovers the advance from it is the
-- terminal's own (CeroSecTerminal.lua:1416-1419, and the long note at :48-66 for
-- why it is exact).
local function advance(text)
	if text == nil or text == "" then return 0 end
	return getTextManager():MeasureStringX(UIFont[CeroSecDebugUI.FONT], text .. "M") - M_INK
end

-- A cell cut to the room its column has, with the "~" the rest of the mod cuts
-- with (CeroSec.truncate). By PIXELS and not by characters, because what
-- overflows a column is ink and UIFont.Small is proportional.
--
-- A cell that does not fit is CUT and is never simply drawn: a cell drawn at its
-- natural width is a cell drawn over its neighbour's, which is what the reader
-- was looking at when "call" was on top of "jobs".
--
-- The first line is the one that runs on almost every cell: a string of n
-- characters cannot be wider than n of the widest glyph, so a short cell in a
-- roomy column is never measured at all.
local function fitText(text, room)
	if room <= 0 then return "" end
	if #text * WIDE_W <= room then return text end
	local full = advance(text)
	if full <= room then return text end
	-- Where the cut lands if the face were fixed width, and then down from there:
	-- the estimate is one or two characters out on a proportional font and the
	-- walk that follows only ever shortens, so the answer never overflows.
	local cut = math.floor(#text * room / full)
	if cut >= #text then cut = #text - 1 end
	while cut > 0 and advance(string.sub(text, 1, cut) .. "~") > room do
		cut = cut - 1
	end
	if cut <= 0 then return "" end
	return string.sub(text, 1, cut) .. "~"
end

--
-- Opening
--

-- Open it, on the machine the player right-clicked -- which is the machine that
-- starts out selected, because the survivor asking about a computer is standing
-- at one. x, y, z may be nil for a window opened with nothing selected.
function CeroSecDebugUI.open(playerObj, x, y, z)
	measure()
	local previous = CeroSecDebugUI.instance
	if previous then previous:close() end

	local ox = (getCore():getScreenWidth() - WINDOW_W) / 2
	local oy = (getCore():getScreenHeight() - WINDOW_H) / 2
	local made = CeroSecDebugUI:new(ox, oy, playerObj, x, y, z)
	made:initialise()
	made:instantiate()
	made:addToUIManager()
	CeroSecDebugUI.instance = made
	made:startTicking()
	made:refresh()
	return made
end

function CeroSecDebugUI:new(x, y, playerObj, cx, cy, cz)
	measure()
	local o = ISCollapsableWindow.new(self, x, y, WINDOW_W, WINDOW_H)
	o.playerObj = playerObj
	o.playerNum = playerObj:getPlayerNum()
	-- The token every answer has to carry back. The same shape the terminal's is,
	-- and for the same reason: a reply reaches a connection and a connection is
	-- not a window (see the head of CeroSecTerminal.lua).
	CeroSecDebugUI.tokenCount = (CeroSecDebugUI.tokenCount or 0) + 1
	o.token = "dbg-" .. tostring(o.playerNum) .. "-" .. tostring(CeroSecDebugUI.tokenCount)
	-- The machine the other tabs are about. Three numbers and not an object: the
	-- machine may be on the far side of the map with its chunk unloaded, and there
	-- is nothing there to hold.
	o.cx, o.cy, o.cz = cx, cy, cz
	-- What the server last said, per tab, so switching tabs draws the last answer
	-- at once instead of an empty list waiting for a round trip.
	o.snapshots = {}
	o.logLevel = nil
	-- Used only, to begin with. A save an hour old holds a machine for every
	-- computer SPRITE a chunk has ever brought in -- forty-four of them, dark, with
	-- nothing in any column but their position -- and the six the mod is doing
	-- something with are somewhere in the middle of that. See passes().
	o.usedOnly = true
	o.lastMs = 0
	o:setResizable(true)
	o:setTitle(getText("IGUI_CeroSec_Debug_Title"))
	return o
end

--
-- The layout
--
-- ONE function, and every number anything in this window is placed by comes out
-- of it -- because two of them disagreed. createChildren worked the panel out one
-- way and onResize another, and neither of them left room for the thing that is
-- not drawn where it is put: a list box with columns draws its header row ABOVE
-- its own top edge, at `0 - self.itemheight` (ISScrollingListBox.lua:553-562). So
-- a list laid straight into a tab view -- which ISTabPanel:addView puts at
-- `self.tabHeight`, :493 -- draws its headers ON the tab strip. That is what was
-- on the glass: "ess", "tel", "call", "jobs", "eyes" showing between the tab
-- labels.
--
-- The arithmetic is vanilla's, from the two windows that have these two shapes:
--
--   * the window round a tab panel -- title bar, then the panel inside the
--     border, and every view as tall as the panel less its tab strip:
--     ISEntitiesDebugWindow.lua:33-52, and its onResize at :67-78, which is the
--     same three lines again.
--   * the room for a header row -- the list one item-height down inside its
--     parent, which is exactly what vanilla's own column list does:
--     ISItemsListTable.lua:76 puts the list at BUTTON_HGT and :79 sets its
--     itemheight to the same number.
--
-- So each tab's view is an ISPanel at the top of the tab panel (y = tabHeight,
-- addView's own doing) and the LIST sits a header row down inside it. Nothing is
-- drawn twice on one row, and the one pixel over the item height is the list's own
-- top border, which it paints because drawBorder is set (:486-491).
--
function CeroSecDebugUI:layout()
	local out = {}
	out.th = self:titleBarHeight()
	out.rh = self:resizeWidgetHeight()
	out.buttonH = FONT_H + 8
	out.infoH = (FONT_H + 2) * INFO_ROWS
	out.panelX = BORDER
	out.panelY = out.th + BORDER
	out.panelW = self:getWidth() - BORDER * 2
	-- TWO rows of buttons and not one. The first row is the nine this window opened
	-- with; the second is the admin's and the tester's eight, which have to go
	-- SOMEWHERE and would have doubled the width of a row that already sets the
	-- window's minimum width all by itself (see createChildren). A row that runs off
	-- the right edge is a button nobody finds; a second row costs one button height
	-- and is read the way a keyboard is.
	out.panelH = self:getHeight() - out.th - out.rh -
		out.buttonH * BUTTON_ROWS - ROW_GAP * (BUTTON_ROWS - 1) - out.infoH -
		BORDER * 4
	-- The tab strip's height and the header row's are the panel's and the list's
	-- own answers, never a second copy of them: the strip is measured off the font
	-- (ISTabPanel.lua:642) and the header row is one item of the list.
	out.tabH = self.panel ~= nil and self.panel.tabHeight or 0
	out.viewH = out.panelH - out.tabH
	out.headerH = FONT_H + 2 * 2 + 1
	if self.lists ~= nil and self.lists[1] ~= nil then
		out.headerH = self.lists[1].itemheight + 1
	end
	out.listH = out.viewH - out.headerH - 1
	out.buttonsY = out.panelY + out.panelH + BORDER
	-- Every row's own top, so a widget asks for the row it is on and nothing adds a
	-- button height to a number for itself.
	out.rowY = {}
	for i = 1, BUTTON_ROWS do
		out.rowY[i] = out.buttonsY + (i - 1) * (out.buttonH + ROW_GAP)
	end
	out.infoY = self:getHeight() - out.rh - BORDER - out.infoH
	return out
end

-- Put everything where layout() says. Called once when the window is built and
-- again on every drag of its corner, so there is one arrangement and not two.
function CeroSecDebugUI:applyLayout()
	if self.panel == nil then return end
	local L = self:layout()
	self.panel:setWidth(L.panelW)
	self.panel:setHeight(L.panelH)
	for i = 1, #self.lists do
		local view = self.views[i]
		view:setWidth(L.panelW)
		view:setHeight(L.viewH)
		local list = self.lists[i]
		list:setY(L.headerH)
		list:setWidth(L.panelW)
		list:setHeight(L.listH)
		self:fitColumns(i)
	end
	for i = 1, #self.buttons do
		local entry = self.buttons[i]
		entry.button:setY(L.rowY[entry.row or 1])
	end
	-- The two widgets that are not buttons follow the row they were put on, because
	-- applyLayout is the only thing in this window that places anything.
	if self.loginEntry ~= nil then self.loginEntry:setY(L.rowY[2]) end
	if self.diskCombo ~= nil then self.diskCombo:setY(L.rowY[2]) end
	self.numbers = L
end

function CeroSecDebugUI:createChildren()
	ISCollapsableWindow.createChildren(self)

	local L = self:layout()

	self.panel = ISTabPanel:new(L.panelX, L.panelY, L.panelW, L.panelH)
	self.panel:initialise()
	self.panel.equalTabWidth = false
	self:addChild(self.panel)

	self.views = {}
	self.lists = {}
	for i = 1, #CeroSecDebugUI.TABS do
		local spec = CeroSecDebugUI.TABS[i]
		-- The view, which is what the tab panel positions, and the list INSIDE it a
		-- header row down: see the note on layout() above for why the list cannot be
		-- the view itself.
		local view = ISPanel:new(0, 0, L.panelW, L.viewH)
		view:initialise()
		view:noBackground()
		local list = ISScrollingListBox:new(0, L.headerH, L.panelW, L.listH)
		list:initialise()
		list:instantiate()
		list:setFont(CeroSecDebugUI.FONT, 2)
		-- The column headers and the rules between them are the list box's own; the
		-- offsets they are drawn at are rewritten from the rows on every fill
		-- (fitColumns), so an empty list still has its columns and a full one has
		-- them where its widest cell needs them.
		for k = 1, #spec.columns do
			list:addColumn(spec.columns[k][1], 0)
		end
		list.drawBorder = true
		-- One cell per column, drawn at the column's own offset. Assigned rather
		-- than derived: there is one kind of row in this window and six lists that
		-- draw it.
		list.doDrawItem = CeroSecDebugUI.drawRow
		list:setOnMouseDownFunction(self, CeroSecDebugUI.onRowClicked)
		list.debugTab = spec
		view:addChild(list)
		self.views[i] = view
		self.lists[i] = list
		self.panel:addView(spec.name, view)
	end

	--
	-- The buttons
	--
	-- One row under the list. Refresh first because it is the one that is used
	-- most; the three that CHANGE something in the middle, named as plainly as
	-- possible; and then the two sets that belong to ONE tab each -- the machine
	-- filter and the log levels -- which share the same stretch of the row,
	-- because they are never both there.
	--
	self.buttons = {}
	-- One pen per row, because the two rows fill independently: the second is not a
	-- continuation of the first and a single cursor would start it wherever the first
	-- happened to end.
	local at = { BORDER, BORDER }
	local row = 1
	-- onTab is the NAME of the tab a button belongs to, or nil for a button that is
	-- on every tab.
	local function button(label, fn, onTab)
		local w = advance(label) + 20
		local made = ISButton:new(at[row], L.rowY[row], w, L.buttonH, label, self, fn)
		made:initialise()
		made:instantiate()
		made:setFont(UIFont[CeroSecDebugUI.FONT])
		self:addChild(made)
		self.buttons[#self.buttons + 1] = { button = made, onTab = onTab, row = row }
		at[row] = at[row] + w + 6
		return made
	end

	button(getText("IGUI_CeroSec_Debug_Refresh"), CeroSecDebugUI.onRefresh, nil)
	self.onButton = button(getText("IGUI_CeroSec_Debug_TurnOn"),
		CeroSecDebugUI.onTurnOn, nil)
	self.offButton = button(getText("IGUI_CeroSec_Debug_TurnOff"),
		CeroSecDebugUI.onTurnOff, nil)
	self.gotoButton = button(getText("IGUI_CeroSec_Debug_Teleport"),
		CeroSecDebugUI.onTeleport, nil)
	self.termButton = button(getText("IGUI_CeroSec_Debug_Terminal"),
		CeroSecDebugUI.onTerminal, nil)
	self.dumpButton = button(getText("IGUI_CeroSec_Debug_Dump"),
		CeroSecDebugUI.onDump, nil)
	-- The three that came after, appended at the END of the row and not slotted in
	-- among the others: the row is read left to right and a button that moves is a
	-- button somebody presses by mistake. The destructive one leads them -- "Reset
	-- machine" is the only act in this window that cannot be undone, and it sits
	-- where it was put rather than being pushed along by the two that followed it.
	self.resetButton = button(getText("IGUI_CeroSec_Debug_Reset"),
		CeroSecDebugUI.onReset, nil)
	self.selfTestButton = button(getText("IGUI_CeroSec_Debug_SelfTest"),
		CeroSecDebugUI.onSelfTest, nil)
	self.giveDiskButton = button(getText("IGUI_CeroSec_Debug_GiveDisk"),
		CeroSecDebugUI.onGiveDisk, nil)

	-- The filter, on the Machines tab and nowhere else. It is made with the WIDER
	-- of the two words it wears and then given the one it is showing: a button that
	-- changed width when it was pressed would move the row under the cursor.
	local tabStart = at[row]
	local showAll = getText("IGUI_CeroSec_Debug_ShowAll")
	local showUsed = getText("IGUI_CeroSec_Debug_ShowUsed")
	local wider = showAll
	if advance(showUsed) > advance(showAll) then wider = showUsed end
	self.filterButton = button(wider, CeroSecDebugUI.onFilter, "Machines")
	self.filterButton:setTitle(self.usedOnly and showAll or showUsed)

	at[row] = tabStart
	self.levelButtons = {}
	for i = 1, #CeroSecDebugUI.LEVELS do
		local spec = CeroSecDebugUI.LEVELS[i]
		local made = button(spec.label, CeroSecDebugUI.onLevel, "Log")
		made.debugLevel = spec.level
		self.levelButtons[i] = made
	end

	--
	-- THE SECOND ROW: the admin's and the tester's own
	--
	-- Eight acts a server owner or somebody walking the checklist wants and a player
	-- must never have: the papers out of the drawer and the pocket, who is on the
	-- machine and with what letters, a password taken off, any disk of the catalogue,
	-- root straight onto the glass, cron's minute by hand, and the automation's walk
	-- run to the end. Every one of them goes through debugact behind
	-- CeroSec.debugAllowed, like everything else on this window.
	--
	-- ON THE MACHINE TAB AND NOWHERE ELSE. All eight are about the machine that is
	-- SELECTED, and the Machines tab is where a machine is selected -- so a reader who
	-- is looking at a filesystem or at the wire is not offered a row of buttons whose
	-- subject is off screen. It is the same rule the filter already wears.
	--
	row = 2
	self.rootNoteButton = button(getText("IGUI_CeroSec_Debug_RootNote"),
		CeroSecDebugUI.onRootNote, "Machines")
	self.staffNoteButton = button(getText("IGUI_CeroSec_Debug_StaffNote"),
		CeroSecDebugUI.onStaffNote, "Machines")
	self.accountsButton = button(getText("IGUI_CeroSec_Debug_Accounts"),
		CeroSecDebugUI.onAccounts, "Machines")
	self.clearPassButton = button(getText("IGUI_CeroSec_Debug_ClearPass"),
		CeroSecDebugUI.onClearPass, "Machines")

	-- WHICH ACCOUNT, typed. A box and not a combo: the accounts on a machine are
	-- whatever /etc/passwd holds, useradd included, and a list of them would be a
	-- round trip spent on something the reader already read off the Log tab. It opens
	-- on "root", which is the account somebody is nearly always after.
	local entryW = advance(string.rep("n", LOGIN_CELLS)) + 20
	self.loginEntry = ISTextEntryBox:new(CeroSecDebugUI.DEFAULT_LOGIN,
		at[row], L.rowY[row], entryW, L.buttonH)
	-- The font BEFORE initialise and never through setFont, which is the terminal's
	-- own order and for the terminal's own reason: initialise is what makes the java
	-- object, and setFont writes onto one that does not exist yet
	-- (ISTextEntryBox.lua:9-12).
	self.loginEntry.font = UIFont[CeroSecDebugUI.FONT]
	self.loginEntry:initialise()
	self.loginEntry:instantiate()
	-- And the ceiling after it, for the same reason the other way round: it goes
	-- straight to the java object. CeroSecOS.MAX_NAME is the rule the passwd parser
	-- holds a name to, so a box cannot hold a login no line could carry.
	self.loginEntry:setMaxTextLength(CeroSecDebugUI.LOGIN_MAX)
	self:addChild(self.loginEntry)
	at[row] = at[row] + entryW + 6

	self.anyDiskButton = button(getText("IGUI_CeroSec_Debug_GiveAnyDisk"),
		CeroSecDebugUI.onGiveAnyDisk, "Machines")

	-- AND WHICH DISK, off the catalogue itself rather than off a list of our own: a
	-- combo typed out here would be a second catalogue, and the day an entry is added
	-- it would be the one place that had not heard of it.
	local comboW = 0
	for i = 1, #CeroSecContent.DISKS do
		local width = advance(tostring(CeroSecContent.DISKS[i].id))
		if width > comboW then comboW = width end
	end
	comboW = comboW + 40
	self.diskCombo = ISComboBox:new(at[row], L.rowY[row], comboW, L.buttonH)
	self.diskCombo:initialise()
	self.diskCombo:instantiate()
	self.diskCombo.font = UIFont[CeroSecDebugUI.FONT]
	for i = 1, #CeroSecContent.DISKS do
		local id = CeroSecContent.DISKS[i].id
		-- The id as the option's DATA and not only as its text: what travels on the
		-- wire is the id, and a lookup by the words on a widget is a lookup that
		-- breaks the day the words are translated.
		self.diskCombo:addOptionWithData(tostring(id), id)
	end
	self:addChild(self.diskCombo)
	at[row] = at[row] + comboW + 6

	self.rootLoginButton = button(getText("IGUI_CeroSec_Debug_RootLogin"),
		CeroSecDebugUI.onRootLogin, "Machines")
	self.cronNowButton = button(getText("IGUI_CeroSec_Debug_CronNow"),
		CeroSecDebugUI.onCronNow, "Machines")
	self.forceWireButton = button(getText("IGUI_CeroSec_Debug_ForceWire"),
		CeroSecDebugUI.onForceWire, "Machines")

	self:applyLayout()

	-- A floor to drag to, set here because this is where the sizes of the things
	-- that have to fit are known. ISResizeWidget's own default is nothing at all
	-- (ISResizeWidget.lua:13-22), and a window dragged smaller than the sum of its
	-- own bands is a window whose list has a negative height; vanilla's own debug
	-- window sets its two in createChildren for the same reason
	-- (ISEntitiesDebugWindow.lua:37-38).
	--
	-- The height is exactly the one at which the list is ONE row tall: what it is
	-- now, less the room the list has now, plus one row. The width is the button
	-- row, which is the one thing in here that does not reflow.
	-- Over every row AND over the two widgets that are not buttons: the floor is the
	-- widest thing under the list, and a box left out of the sum is a box the corner
	-- can be dragged over.
	local widest = 0
	local function reach(made)
		if made == nil then return end
		local right = made:getX() + made:getWidth()
		if right > widest then widest = right end
	end
	for i = 1, #self.buttons do reach(self.buttons[i].button) end
	reach(self.loginEntry)
	reach(self.diskCombo)
	self.minimumWidth = widest + BORDER
	self.minimumHeight = self:getHeight() - self.numbers.listH +
		self.lists[1].itemheight

	-- And the window is OPENED at least that wide, which the floor above does not
	-- do on its own: the opening width is worked out from the widest tab's NOMINAL
	-- columns (measure()) and knows nothing about the button row, which comes off
	-- the words on the buttons, so the two are free to disagree. A seventh button
	-- was what first made them, and "Give diagnostics disk" is the widest label on
	-- the row now: a window that opens with its last buttons over its own right
	-- edge is a button somebody has to drag the corner to find, and a minimum
	-- nobody can drag back to, since a window cannot be made wider by dragging its
	-- own corner past the screen.
	--
	-- Widened HERE and not in measure(), because the row's width is a measurement
	-- of the buttons themselves and they do not exist until now; and reflowed with
	-- applyLayout, the only thing that places anything, so the lists and their
	-- columns come out at the new width rather than the old one.
	if self:getWidth() < self.minimumWidth then
		self:setWidth(self.minimumWidth)
		self:applyLayout()
	end
end

--
-- Which tab, and which machine
--

function CeroSecDebugUI:activeIndex()
	if self.panel == nil then return 1 end
	local index = self.panel:getActiveViewIndex()
	if type(index) ~= "number" or index < 1 or index > #CeroSecDebugUI.TABS then
		return 1
	end
	return index
end

function CeroSecDebugUI:activeSpec()
	return CeroSecDebugUI.TABS[self:activeIndex()]
end

-- Is a machine selected at all? Three numbers or nothing: every command about a
-- machine carries them and the server answers "nothing selected" for a triple
-- nothing is at.
function CeroSecDebugUI:hasMachine()
	return type(self.cx) == "number" and type(self.cy) == "number"
		and type(self.cz) == "number"
end

--
-- Talking to the server
--

function CeroSecDebugUI:send(command, args)
	-- The selected machine, in the three fields every command of this module
	-- carries. 0,0,0 is the corner of the map and no computer is ever there, so it
	-- is what "nothing selected" looks like on the wire -- the server looks the
	-- triple up and answers nil for one nothing is at.
	args.x = self.cx or 0
	args.y = self.cy or 0
	args.z = self.cz or 0
	args.token = self.token
	if CCeroSecSystem == nil or CCeroSecSystem.instance == nil then return end
	CCeroSecSystem.instance:sendCommand(self.playerObj, command, args)
end

-- Ask for the tab in front. The Log tab asks for nothing: it is the client's own
-- ring buffer and there is no round trip in it.
function CeroSecDebugUI:refresh()
	self.lastMs = getTimestampMs()
	local spec = self:activeSpec()
	if spec.tab == nil then
		self:fillLog()
		return
	end
	self:send("debug", { tab = spec.tab })
end

function CeroSecDebugUI:isMine(args)
	return args ~= nil and args.token ~= nil and args.token == self.token
end

function CeroSecDebugUI:onServerCommand(command, args)
	if command ~= "debug" then return end
	if not self:isMine(args) then return end

	-- A REFUSAL, which is not a snapshot: the server was asked to switch a machine
	-- on or off and would not. It goes on the first line of the block under the
	-- list and the lists themselves are left alone.
	--
	-- It used to go nowhere at all. `Commands.debugact` called turnOn, which
	-- refuses a machine whose chunk is away -- the wire is asked of a SQUARE and
	-- there is nobody to ask -- dropped the boolean, and answered nothing; the
	-- window drew the same `off` two seconds later. A button that cannot work
	-- looked exactly like a button that had worked.
	if type(args.error) == "string" then
		self.refusal = args.error
		self.notice = nil
		return
	end

	-- And the other half of that: something that WORKED and has a sentence to show
	-- for it -- the self-test's verdict, the receipt for a disk. Kept apart from a
	-- refusal because a reader has to be able to tell "PASS 128 FAIL 0" from
	-- "cannot turn on", and because a refusal outranks it on the one line there is.
	if type(args.note) == "string" then
		self.notice = args.note
		self.refusal = nil
		return
	end

	if type(args.tab) ~= "string" then return end
	-- What the server says the SELECTED machine can be asked to do, which is what
	-- the buttons are greyed by and what the reason line says. Kept only when the
	-- answer is about the machine that is selected NOW: a snapshot still in flight
	-- from the machine before it would grey the wrong button.
	if args.x == self.cx and args.y == self.cy and args.z == self.cz then
		self.selection = { on = args.on, loaded = args.loaded,
			canTurnOn = args.canTurnOn, canTurnOff = args.canTurnOff,
			canReset = args.canReset, resetReason = args.resetReason,
			reason = args.reason,
			-- And the admin's and the tester's eight, each with its own reason:
			-- copied one by one rather than by walking the answer, because what
			-- comes off the wire is a table a server built and only the fields
			-- this window knows the names of are read off it.
			canRootNote = args.canRootNote, rootNoteReason = args.rootNoteReason,
			canStaffNote = args.canStaffNote,
			staffNoteReason = args.staffNoteReason,
			canAccounts = args.canAccounts, accountsReason = args.accountsReason,
			canClearPass = args.canClearPass,
			clearPassReason = args.clearPassReason,
			canRootLogin = args.canRootLogin,
			rootLoginReason = args.rootLoginReason,
			canCronNow = args.canCronNow, cronNowReason = args.cronNowReason,
			canForceWire = args.canForceWire,
			forceWireReason = args.forceWireReason }
	end
	self.snapshots[args.tab] = args
	self:fill(args.tab)
end

-- Both transports land here, exactly as the terminal's answers do: the
-- singleplayer broadcast and the server's answer to one connection. Neither is
-- routing enough, so the token settles it.
function CeroSecDebugUI.onServerAnswer(command, args)
	local window = CeroSecDebugUI.instance
	if window == nil then return end
	window:onServerCommand(command, args)
end

--
-- Filling a list
--

-- Which rows a list shows.
--
-- Only the Machines tab filters, and only on the one fact that tells a computer
-- the mod is DOING something with from a sprite the streamer walked past: the
-- server's own `used` flag -- it has been switched on at least once, or it has a
-- disk of its own (SCeroSecDebug.isUsed). The server holds a machine for every
-- computer sprite any chunk has ever brought in, so a save an hour old answers
-- forty-four rows of `off away` with nothing in any other column, and the six that
-- matter are somewhere in the middle of them.
-- With ONE exception, and it is the reset's: the row a reader has his cursor on is
-- never filtered away under him. "Reset machine" is the one act that can change the
-- answer to `used` -- the state goes, so the server's flag goes false -- and a
-- machine that vanished out of the list the moment it was reset would be a machine
-- nobody could then switch on to see what the reset did, on a list that looked as
-- though the computer had been deleted. So the selected machine stays on the glass
-- whatever the filter says, and the next refresh keeps it there.
function CeroSecDebugUI:passes(index, row)
	if CeroSecDebugUI.TABS[index].tab ~= "machines" then return true end
	if not self.usedOnly then return true end
	if row.used == true then return true end
	return row.x == self.cx and row.y == self.cy and row.z == self.cz
end

-- What a row IS, for keeping the cursor on it across a refresh: a machine row is
-- named by its coordinates -- which is also what its first cell says -- and every
-- other row by its first cell. Never by its INDEX: two seconds later a machine may
-- have moved up the list, and a reader whose cursor jumped to somebody else's row
-- every two seconds would be a reader who cannot read.
local function rowKey(row)
	if type(row) ~= "table" then return nil end
	if type(row.x) == "number" then
		return tostring(row.x) .. "," .. tostring(row.y) .. "," .. tostring(row.z)
	end
	if type(row.c) == "table" then return tostring(row.c[1]) end
	return nil
end

-- Put a snapshot's rows into the list of the tab it belongs to. Never into the
-- list that happens to be in front: an answer for the Files tab that arrived
-- after the reader moved to Devices belongs in the Files list and nowhere else.
function CeroSecDebugUI:fill(tab)
	local index = nil
	for i = 1, #CeroSecDebugUI.TABS do
		if CeroSecDebugUI.TABS[i].tab == tab then index = i end
	end
	if index == nil then return end
	local snapshot = self.snapshots[tab]
	local list = self.lists[index]
	if list == nil or snapshot == nil then return end

	local wanted = nil
	if type(list.selected) == "number" and list.selected >= 1
			and list.selected <= #list.items then
		local held = list.items[list.selected]
		if type(held) == "table" then wanted = rowKey(held.item) end
	end

	list:clear()
	local rows = snapshot.rows or {}
	-- The rows the list is SHOWING, kept beside it: the columns are measured off
	-- them, on every fill and again on every drag of the window's corner.
	list.debugRows = {}
	for i = 1, #rows do
		local row = rows[i]
		if type(row) == "table" and type(row.c) == "table" and self:passes(index, row) then
			list.debugRows[#list.debugRows + 1] = row
			list:addItem(tostring(row.c[1]), row)
		end
	end
	list.debugShown = #list.debugRows
	list.debugTotal = #rows
	self:fitColumns(index)
	if wanted ~= nil then
		for i = 1, #list.items do
			if rowKey(list.items[i].item) == wanted then list.selected = i end
		end
	end
	return list
end

--
-- The columns
--
-- Measured, and not a table of constants: a cell is text of a length nobody chose.
-- Each column is as wide as the WIDER of its own header and the widest cell in the
-- rows on the glass, plus the pad the list box draws its header name at and a gap
-- before the next column's rule; nothing is narrower than MIN_CELLS characters;
-- and the last column takes whatever is left, so the table fills the window
-- instead of stopping in the middle of it.
--
-- When the natural widths do not fit -- eleven columns of long paths in an
-- eight-hundred-pixel window -- every column gives up the same FRACTION of what it
-- has above the minimum. Nothing is ever left overlapping: the cells that no longer
-- fit are cut (fitText), because a cell drawn at its natural width is a cell drawn
-- over its neighbour's, which is what "call" on top of "jobs" was.
--
-- The offsets are written back onto the list box's own columns, because the header
-- row and the rules between them are its to draw (ISScrollingListBox.lua:553-562)
-- and they have to stand over the cells.
function CeroSecDebugUI:fitColumns(index)
	local list = self.lists[index]
	local spec = CeroSecDebugUI.TABS[index]
	if list == nil or spec == nil then return end
	local rows = list.debugRows or {}
	local count = #spec.columns
	local minW = PAD + advance(string.rep("n", MIN_CELLS)) + GAP

	local widths = {}
	local total = 0
	for k = 1, count do
		local w = advance(spec.columns[k][1])
		for r = 1, #rows do
			local cells = rows[r].c
			local text = cells ~= nil and cells[k] or nil
			if text ~= nil then
				local at = advance(tostring(text))
				if at > w then w = at end
			end
		end
		w = PAD + w + GAP
		if w < minW then w = minW end
		widths[k] = w
		total = total + w
	end

	local room = list:getWidth()
	if total > room then
		local slack = total - minW * count
		local spare = room - minW * count
		if spare < 0 then spare = 0 end
		total = 0
		for k = 1, count do
			local w = minW
			if slack > 0 then
				w = minW + math.floor((widths[k] - minW) * spare / slack)
			end
			widths[k] = w
			total = total + w
		end
	end
	if total < room then widths[count] = widths[count] + (room - total) end

	local at = 0
	list.colX = {}
	list.colW = {}
	for k = 1, count do
		list.colX[k] = at
		list.colW[k] = widths[k]
		if list.columns[k] ~= nil then list.columns[k].size = at end
		at = at + widths[k]
	end
end

-- The Log tab, which comes from nowhere: CeroSec.logRing is this Lua state's own
-- record of what the mod said. Newest LAST, so it reads down the way it happened.
function CeroSecDebugUI:fillLog()
	local index = #CeroSecDebugUI.TABS
	local list = self.lists[index]
	if list == nil then return end
	list:clear()
	list.debugRows = {}
	local ring = CeroSec.logRing or {}
	for i = 1, #ring do
		local line = ring[i]
		if type(line) == "table" and
				(self.logLevel == nil or line.level == self.logLevel) then
			local row = { c = { line.level, line.text } }
			list.debugRows[#list.debugRows + 1] = row
			list:addItem(tostring(line.level), row)
		end
	end
	list.debugShown = #list.debugRows
	list.debugTotal = #ring
	self:fitColumns(index)
end

--
-- Drawing one row
--
-- Assigned onto every list box as its doDrawItem, so `self` here is the LIST and
-- not the window. It is ISScrollingListBox:doDrawItem with one thing changed: the
-- cells are drawn at the column offsets instead of the whole text at 15. The
-- selection, the mouse-over and the row border are vanilla's own calls, so a row
-- of this window highlights exactly like a row of any other.
--
-- The offsets and widths are the ones fitColumns measured -- the same numbers the
-- list box draws its header row and its rules at -- and every cell is cut to its
-- own column's room, so nothing is ever painted past the rule on its right.
--
function CeroSecDebugUI.drawRow(self, y, item, alt)
	local height = item.height or self.itemheight
	if y + self:getYScroll() + height < 0 or y + self:getYScroll() >= self.height then
		return y + height
	end

	local color = item.textColor or self.textColor
	if self.selected == item.index then
		self:drawSelection(0, y, self:getWidth(), height - 1)
		color = item.selectedTextColor or self.selectedTextColor
	elseif self.mouseoverselected == item.index and self:isMouseOver()
			and not self:isMouseOverScrollBar() then
		self:drawMouseOverHighlight(0, y, self:getWidth(), height - 1)
	end

	local padY = self.itemPadY or 0
	local cells = item.item ~= nil and item.item.c or nil
	local colX, colW = self.colX, self.colW
	if cells ~= nil and colX ~= nil then
		for i = 1, #colX do
			local text = cells[i]
			if text ~= nil and text ~= "" then
				self:drawText(fitText(tostring(text), colW[i] - PAD - GAP),
					colX[i] + PAD, y + padY,
					color.r, color.g, color.b, color.a, self.font)
			end
		end
	end
	return y + height
end

--
-- Selecting a machine
--

-- A row of the Machines tab carries the machine it names, and clicking one makes
-- it the machine every other tab is about -- which means asking the server again,
-- because the Files, Devices and Scheduler tabs are answers about ONE computer.
function CeroSecDebugUI:onRowClicked(item)
	if type(item) ~= "table" then return end
	if type(item.x) ~= "number" then return end
	if item.x == self.cx and item.y == self.cy and item.z == self.cz then return end
	self.cx, self.cy, self.cz = item.x, item.y, item.z
	-- Everything the window holds about the machine that WAS selected goes: a
	-- Files tab still showing the last computer's disk under a new machine's name
	-- is the one mistake this window must not make. Every snapshot, because even
	-- the county list carries the selected machine's own detail under it.
	--
	-- The county list's ROWS stay, and that is the exception: they are a fact about
	-- the county and not about the selection, and a reader who clicked a row must
	-- not watch the list he clicked in empty itself under his cursor.
	self.snapshots = {}
	-- And what the server said about the machine that was selected, refusal
	-- included: both were answers about a different computer.
	self.selection = nil
	self.refusal = nil
	-- The verdict goes with them: half of what the self-test reports is about the
	-- machine that WAS selected, so leaving it up under a new one would be the
	-- Files tab's own mistake made on one line.
	self.notice = nil
	for i = 1, #self.lists do
		local spec = CeroSecDebugUI.TABS[i]
		if spec.tab ~= nil and spec.tab ~= "machines" then self.lists[i]:clear() end
	end
	self:refresh()
end

--
-- The buttons
--
-- Every one of them is greyed when its act CANNOT happen, and the line under the
-- list says why -- in the server's own words for the two that go to the server,
-- because it is the server that refuses (see reasonLine).
--

function CeroSecDebugUI:onRefresh()
	self:refresh()
end

function CeroSecDebugUI:onTurnOn()
	if not self:hasMachine() then return end
	-- What the server last said about this machine, which is what the button is
	-- greyed by. A press it already knows cannot work says why instead of going
	-- out on the wire to be refused -- and nothing is assumed while the server has
	-- not answered yet: an unknown is asked, and the answer comes back as a
	-- refusal with a reason on it.
	local sel = self.selection
	if sel ~= nil and sel.canTurnOn == false then
		self.refusal = "cannot turn on: " .. tostring(sel.reason)
		return
	end
	self.refusal = nil
	self:send("debugact", { act = "on" })
	self:refresh()
end

function CeroSecDebugUI:onTurnOff()
	if not self:hasMachine() then return end
	local sel = self.selection
	if sel ~= nil and sel.canTurnOff == false then
		self.refusal = "cannot turn off: it is already off"
		return
	end
	self.refusal = nil
	self:send("debugact", { act = "off" })
	self:refresh()
end

function CeroSecDebugUI:onDump()
	if not self:hasMachine() then return end
	self:send("debugact", { act = "dump" })
end

-- Is the reset armed for the machine that is selected RIGHT NOW?
--
-- Both halves matter. The machine, because a click that armed the row above and a
-- click that fires on the row below would be a reset of a computer nobody aimed
-- at; and the clock, because an arming left standing is a trap somebody walks into
-- five minutes later when he has forgotten he ever pressed it.
function CeroSecDebugUI:resetArmed(now)
	local armed = self.armed
	if armed == nil then return false end
	if armed.x ~= self.cx or armed.y ~= self.cy or armed.z ~= self.cz then
		return false
	end
	return (now or getTimestampMs()) - armed.at < CeroSecDebugUI.ARM_MS
end

-- The one act in this window that cannot be undone: the selected machine's whole
-- filesystem, gone, so that its first power-on can happen a second time (see
-- docs/DEBUG.md).
--
-- TWO CLICKS ARE THE GUARD, and there is deliberately no dialog: a vanilla modal
-- would be one more window over a window that is already a tool, and the thing a
-- reader needs is not a box to click through but to be told what he is about to
-- do to WHICH machine -- which is what the reason line says between the two
-- clicks. The arming expires by itself, because a guard that waits for ever is a
-- guard that is not there.
function CeroSecDebugUI:onReset()
	if not self:hasMachine() then return end
	local sel = self.selection
	if sel ~= nil and sel.canReset == false then
		self.refusal = "cannot reset: " .. tostring(sel.resetReason)
		-- And the arming goes: a machine somebody has just switched on is not a
		-- machine whose second click may still land.
		self.armed = nil
		return
	end
	if self:resetArmed() then
		self.armed = nil
		self.refusal = nil
		self:send("debugact", { act = "reset" })
		self:refresh()
		return
	end
	self.armed = { at = getTimestampMs(), x = self.cx, y = self.cy, z = self.cz }
	self.refusal = nil
end

-- Run every vector on the VM the GAME has, and the save path of the selected
-- machine with them. The verdict comes back as a `note` and goes on the line
-- under the list; the failing lines go through CeroSec.log and are on the Log
-- tab, where the warn filter finds them.
--
-- A machine IS wanted, and the button says so rather than greying: half of what
-- this runs is about the selected machine's own state, and a self-test that
-- quietly skipped that half would be a pass that proved less than the one before
-- it (CeroSecSelfTest.runSave reports the refusal as a failed vector).
function CeroSecDebugUI:onSelfTest()
	self.refusal = nil
	self.notice = "self-test running..."
	self:send("debugact", { act = "selftest" })
end

-- The developer's floppy, into the survivor's bag. No machine needed: it is about
-- his inventory, and the server answers it before it looks a machine up.
function CeroSecDebugUI:onGiveDisk()
	self.refusal = nil
	self.notice = nil
	self:send("debugact", { act = "givedisk" })
end

--
-- The admin's and the tester's eight
--
-- Every one of them is the same three lines: a machine, then the answer the SERVER
-- gave about this very act, then the act. A press the window already knows cannot
-- work prints the server's own sentence instead of going out on the wire to be
-- refused -- which is the pattern the two power buttons and the reset already wear
-- (onTurnOn) -- and nothing is assumed while no answer has arrived: an unknown is
-- asked, and the reason comes back with the refusal.
--
-- None of them refreshes afterwards. What each of them has to say comes back as a
-- `note` on the one line there is, and a refresh chasing it would draw over the line
-- it lands on -- the same reason the self-test asks for no snapshot.
--

-- Is this act's own answer a no, and if so what does the server say about it? nil
-- when it may be pressed. One function and not eight copies of the test.
function CeroSecDebugUI:actWhy(can, reason)
	local sel = self.selection
	if sel == nil then return nil end
	if sel[can] == false then return tostring(sel[reason]) end
	return nil
end

-- What every one of the eight does with that answer, so the refusal on the glass and
-- the refusal on the wire are one sentence in one wording (the server's own).
function CeroSecDebugUI:sendAct(act, can, reason, prefix, extra)
	if not self:hasMachine() then return false end
	local why = self:actWhy(can, reason)
	if why ~= nil then
		self.refusal = prefix .. ": " .. why
		self.notice = nil
		return false
	end
	self.refusal = nil
	self.notice = nil
	local args = { act = act }
	if type(extra) == "table" then
		for key, value in pairs(extra) do args[key] = value end
	end
	self:send("debugact", args)
	return true
end

function CeroSecDebugUI:onRootNote()
	self:sendAct("rootnote", "canRootNote", "rootNoteReason", "no root note")
end

function CeroSecDebugUI:onStaffNote()
	self:sendAct("staffnote", "canStaffNote", "staffNoteReason", "no staff note")
end

function CeroSecDebugUI:onAccounts()
	self:sendAct("accounts", "canAccounts", "accountsReason", "no accounts")
end

-- The login is whatever is in the box, sent as it is typed: the window does not
-- judge a name -- the server holds it to CeroSecOS.isValidName and answers, and a
-- second rule here would be a second answer to "is that an account name".
function CeroSecDebugUI:onClearPass()
	local login = CeroSecDebugUI.DEFAULT_LOGIN
	if self.loginEntry ~= nil then
		local typed = self.loginEntry:getInternalText()
		if type(typed) == "string" and typed ~= "" then login = typed end
	end
	self:sendAct("clearpass", "canClearPass", "clearPassReason",
		"no password cleared", { login = login })
end

-- Any disk of the catalogue, by the id the combo is on. The DATA and not the words,
-- so what travels is the catalogue's own id (see the combo in createChildren).
--
-- No machine is wanted -- it is about a bag, exactly as the diagnostics disk is --
-- so it does not go through sendAct, which insists on one.
function CeroSecDebugUI:onGiveAnyDisk()
	self.refusal = nil
	self.notice = nil
	local id = nil
	if self.diskCombo ~= nil then id = self.diskCombo:getSelectedData() end
	if id == nil then
		self.refusal = "no disk: nothing is chosen in the list"
		return
	end
	self:send("debugact", { act = "anydisk", disk = id })
end

-- Root at the glass, and then the glass.
--
-- The terminal is opened through onTerminal and not through a second path of its
-- own, so the three conditions a window has to meet are the ones it already checks
-- (terminalWhy) and this is a shortcut past the KEYBOARD alone.
--
-- Opened right after the act and not on the answer, and the order holds: in
-- singleplayer the command has already been carried out by the time sendCommand
-- returns -- one Lua state, one thread -- and on a dedicated server both commands
-- travel this client's own connection, so the `open` the terminal sends reaches the
-- server after the login and the screen that comes back is the session's.
function CeroSecDebugUI:onRootLogin()
	if not self:sendAct("rootlogin", "canRootLogin", "rootLoginReason",
			"no root login") then
		return
	end
	if self:terminalWhy() == nil then self:onTerminal() end
end

function CeroSecDebugUI:onCronNow()
	self:sendAct("cronnow", "canCronNow", "cronNowReason", "cron did not run")
end

function CeroSecDebugUI:onForceWire()
	self:sendAct("forcewire", "canForceWire", "forceWireReason", "no wiring")
end

-- Stand the player on the selected machine's own square.
--
-- Vanilla's own debug teleport, both halves of it, copied from the one place
-- vanilla does it off a list row (ISSpawnPointsEditor:onPointDoubleClick,
-- media/lua/client/DebugUIs/ISSpawnPointsEditor.lua:130-140): the middle of the
-- square, the server command on a client and the direct call otherwise.
--
--   IsoGameCharacter.teleportTo(float, float, int)   -- javap, IsoPlayer extends it
--
-- The command form is vanilla's own text command and not ours: a client has no
-- business moving itself, and "/teleportto x,y,z" is what the game's admin
-- console takes.
function CeroSecDebugUI:onTeleport()
	if not self:hasMachine() then return end
	local x, y, z = self.cx + 0.5, self.cy + 0.5, self.cz
	if isClient() then
		SendCommandToServer("/teleportto " .. tostring(x) .. "," .. tostring(y) ..
			"," .. tostring(z))
	else
		self.playerObj:teleportTo(x, y, z)
	end
end

-- Open the terminal on the selected machine, as if it had been used from the
-- front.
--
-- It is the FRONT path and nothing quieter: CeroSecTerminal.open needs the
-- computer's IsoObject, so a machine whose chunk is away has nothing to open a
-- window on -- and the server would refuse the window anyway, because every
-- command a terminal sends is checked for adjacency (SCeroSecSystem.isAdjacent).
-- So this is a shortcut past the WALK and past the chair, and past nothing else:
-- a machine out of reach says so on the log rather than opening a window that
-- would shut itself.
function CeroSecDebugUI:onTerminal()
	if not self:hasMachine() then return end
	local why = self:terminalWhy()
	if why ~= nil then
		self.refusal = "cannot open the terminal: " .. why
		CeroSec.log(CeroSec.LOG_WARN, "debug: " .. self.refusal .. " at " ..
			tostring(self.cx) .. "," .. tostring(self.cy) .. "," .. tostring(self.cz))
		return
	end
	self.refusal = nil
	CeroSecTerminal.open(self.playerObj, self:computerObject())
end

-- Why the terminal cannot be opened on the selected machine, or nil when it can.
--
-- All three answers are the CLIENT's, and that is right: the screen has to be in
-- the world to open a window on, and where the player is standing is a fact about
-- this client. The adjacency is the server's own arithmetic, copied from the check
-- every command a terminal sends goes through (SCeroSecSystem's isAdjacent, which
-- is vanilla's luautils.lua:138-140 -- half a square of centre offset and 1.6 of
-- slack on each axis), so a window this opens is a window the server will answer.
--
--   zombie.iso.IsoMovingObject   public float getX(); getY();
--                                public IsoGridSquare getCurrentSquare();
--   zombie.iso.IsoGridSquare     public int getZ();
--
function CeroSecDebugUI:terminalWhy()
	if self:computerObject() == nil then
		return "its chunk is away, there is no screen in the world"
	end
	local sel = self.selection
	if sel ~= nil and sel.on ~= true then return "it is off" end
	local player = self.playerObj
	if player == nil then return "there is no player" end
	local square = player:getCurrentSquare()
	if square == nil or square:getZ() ~= self.cz then
		return "the player is on another floor"
	end
	if math.abs(self.cx + 0.5 - player:getX()) > 1.6
			or math.abs(self.cy + 0.5 - player:getY()) > 1.6 then
		return "the player is not standing at it"
	end
	return nil
end

-- Why the selected machine cannot be asked to do a thing, for the first line of
-- the block under the list. nil when there is nothing to say.
--
-- The server's own refusal comes first, because it is the one that answers a
-- button somebody has just pressed; then the reason it is greyed at all.
function CeroSecDebugUI:reasonLine()
	-- THREE THINGS COMPETE FOR THE ONE LINE, in this order.
	--
	-- The server's refusal first: it is the one that answers a button somebody has
	-- just pressed, it can arrive at any moment -- including to say the reset
	-- itself was refused -- and a refusal held back for the five seconds an arming
	-- lasts is a refusal the reader never sees. Arming clears it (onReset), so the
	-- two are not normally up together and this order costs the prompt nothing.
	if self.refusal ~= nil then return self.refusal end
	-- Then the armed reset, over everything the window works out for itself: it is
	-- the one line that is about what the next click will DO rather than about what
	-- a button cannot do, and it has five seconds to be read.
	if self:resetArmed() then
		return "Click again to reset " .. self:selectedHost()
	end
	-- Then a verdict a developer pressed for. Last of the three because it does not
	-- expire and can be read again, while the other two are answers to one click.
	if self.notice ~= nil then return self.notice end
	if not self:hasMachine() then
		return "nothing selected: click a row on the Machines tab"
	end
	local sel = self.selection
	if sel == nil then return nil end
	if sel.canTurnOn == false and sel.on ~= true then
		return "cannot turn on: " .. tostring(sel.reason)
	end
	local why = self:terminalWhy()
	if why ~= nil then return "cannot open the terminal: " .. why end
	return nil
end

-- What to CALL the selected machine in a sentence, for the one sentence that has
-- to name a machine: its hostname and where it stands.
--
-- Off the ROWS the Machines list is showing and not off a snapshot, because the
-- rows are what survive a click on another row (see onRowClicked) -- and off the
-- column called "host" rather than a number, so a column inserted before it does
-- not rename somebody's computer. A machine nobody has ever used has no hostname
-- at all and its coordinates are the only name it has, which is what this answers
-- for it.
function CeroSecDebugUI:selectedHost()
	local where = tostring(self.cx) .. "," .. tostring(self.cy) .. "," ..
		tostring(self.cz)
	local column = nil
	local columns = CeroSecDebugUI.TABS[1].columns
	for k = 1, #columns do
		if columns[k][1] == "host" then column = k end
	end
	local list = self.lists ~= nil and self.lists[1] or nil
	local rows = list ~= nil and list.debugRows or nil
	if column == nil or type(rows) ~= "table" then return where end
	for i = 1, #rows do
		local row = rows[i]
		if row.x == self.cx and row.y == self.cy and row.z == self.cz then
			local host = type(row.c) == "table" and row.c[column] or nil
			if type(host) == "string" and host ~= "" and host ~= "-" then
				return host .. " at " .. where
			end
		end
	end
	return where
end

-- The computer tile on the selected square, or nil when its chunk is not in.
function CeroSecDebugUI:computerObject()
	if getCell == nil then return nil end
	local cell = getCell()
	if cell == nil then return nil end
	local square = cell:getGridSquare(self.cx, self.cy, self.cz)
	if square == nil then return nil end
	local objects = square:getObjects()
	if objects == nil then return nil end
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		if CeroSec.isComputerSprite(object:getSpriteName()) then return object end
	end
	return nil
end

-- used only / all, on the Machines tab. The list is refilled from the snapshot
-- that is already in hand, so the answer is on the glass at once and no round trip
-- is spent on a question about rows the window already has.
function CeroSecDebugUI:onFilter()
	self.usedOnly = not self.usedOnly
	self.filterButton:setTitle(self.usedOnly and
		getText("IGUI_CeroSec_Debug_ShowAll") or
		getText("IGUI_CeroSec_Debug_ShowUsed"))
	if self.snapshots["machines"] == nil then
		-- Nothing in hand to sift again, so ask: a count line left over from the
		-- other mode would be a count of rows nobody is looking at.
		self:refresh()
	else
		self:fill("machines")
	end
end

-- A level button. `self` is the window and the button is the one that was
-- pressed, which is how ISButton calls a target back.
function CeroSecDebugUI:onLevel(button)
	if button == nil then return end
	self.logLevel = button.debugLevel
	self:fillLog()
end

--
-- The clock
--
-- OnTickEvenPaused and not OnTick, because a debug window is a thing somebody
-- opens with the game paused: a tool that stopped answering the moment you
-- stopped the world would be a tool for watching and never for looking. Both are
-- real events (zombie.Lua.LuaEventManager registers "OnTick" and
-- "OnTickEvenPaused"; javap of the class has both strings) and both are
-- zombie.Lua.Event, which is the class that carries Add and Remove.
--
-- Gated on getTimestampMs, which is vanilla's own way of getting under a minute
-- on a tick handler (forageServer.lua:502, and the gate inside
-- CeroSecDevices.tick).
--
-- THE HANDLER COMES OFF ON CLOSE. A tick handler left registered by a window that
-- is gone is a closure holding a dead window, called sixty times a second, for
-- the rest of the session -- and it would go on asking the server for snapshots
-- nobody can see. tests/debug_ui_test.lua fails if it stays.
--

function CeroSecDebugUI:startTicking()
	if self.tickHandler ~= nil then return end
	local window = self
	self.tickHandler = function()
		window:onTick()
	end
	Events.OnTickEvenPaused.Add(self.tickHandler)
end

function CeroSecDebugUI:stopTicking()
	if self.tickHandler == nil then return end
	Events.OnTickEvenPaused.Remove(self.tickHandler)
	self.tickHandler = nil
end

function CeroSecDebugUI:onTick()
	if self.closing then return end
	local now = getTimestampMs()
	if now - self.lastMs < CeroSecDebugUI.REFRESH_MS then return end
	self:refresh()
end

--
-- Closing
--

function CeroSecDebugUI:close()
	if self.closing then return end
	self.closing = true
	self:stopTicking()
	if CeroSecDebugUI.instance == self then CeroSecDebugUI.instance = nil end
	self:setVisible(false)
	self:removeFromUIManager()
end

--
-- Drawing
--

function CeroSecDebugUI:prerender()
	ISCollapsableWindow.prerender(self)
	if self.closing then return end

	-- The buttons that belong to ONE tab are there on that tab and on no other;
	-- everything else is always there. Worked out every frame rather than when
	-- something changes: whether a button means anything is a fact about the
	-- window right now, and a window that remembered it would be a window that
	-- forgets.
	local front = self:activeSpec().name
	for i = 1, #self.buttons do
		local entry = self.buttons[i]
		if entry.onTab ~= nil then entry.button:setVisible(entry.onTab == front) end
	end

	-- And every button is usable only when its act can happen. The two power
	-- buttons take the SERVER's answer, carried on every snapshot: it is the server
	-- that refuses, and a window that worked the rule out for itself would grey the
	-- wrong button the day the rule moved. Nothing is greyed on an answer that has
	-- not arrived -- an unknown is asked, and the refusal comes back with its reason.
	local machine = self:hasMachine()
	local sel = self.selection
	self.onButton:setEnable(machine and (sel == nil or sel.canTurnOn ~= false))
	self.offButton:setEnable(machine and (sel == nil or sel.canTurnOff ~= false))
	self.gotoButton:setEnable(machine)
	self.termButton:setEnable(machine and self:terminalWhy() == nil)
	self.dumpButton:setEnable(machine)
	-- The reset takes the server's answer like the two power buttons, and it is
	-- greyed on a machine that is ON -- which is the whole of its rule
	-- (CeroSecDebug.resetRefusal).
	self.resetButton:setEnable(machine and (sel == nil or sel.canReset ~= false))

	-- And the second row, every one of them on the server's own answer about that
	-- one act. A table of pairs rather than seven lines, because these are one rule
	-- read seven times and the names are the only thing that differs.
	for i = 1, #CeroSecDebugUI.ACT_BUTTONS do
		local spec = CeroSecDebugUI.ACT_BUTTONS[i]
		local made = self[spec[1]]
		if made ~= nil then
			made:setEnable(machine and (sel == nil or sel[spec[2]] ~= false))
		end
	end
	-- The box follows the button beside it: a name typed into a box whose button
	-- cannot be pressed is a name nobody asked for. The disk list is about a BAG and
	-- is never greyed, exactly like the button it belongs to.
	local onMachines = self:activeSpec().name == "Machines"
	if self.loginEntry ~= nil then
		self.loginEntry:setVisible(onMachines)
		self.loginEntry:setEditable(machine and (sel == nil or sel.canClearPass ~= false))
	end
	if self.diskCombo ~= nil then self.diskCombo:setVisible(onMachines) end
end

function CeroSecDebugUI:render()
	ISCollapsableWindow.render(self)
	if self.closing then return end

	local spec = self:activeSpec()
	local list = self.lists[self:activeIndex()]

	-- The block under the list, in three parts and always in this order: why a
	-- button cannot be pressed, how much of the list is on the glass, and then the
	-- server's own words. The first two are the WINDOW's and are the two things a
	-- reader was missing -- a button that did nothing said nothing, and a list
	-- showing six of forty-four said it was the county.
	local lines = {}
	lines[1] = self:reasonLine() or ""
	local mode = ""
	if spec.tab == "machines" then
		mode = self.usedOnly and "   used only" or "   all machines"
	end
	lines[2] = "showing " .. tostring(list ~= nil and list.debugShown or 0) ..
		" of " .. tostring(list ~= nil and list.debugTotal or 0) .. mode
	if spec.tab == nil then
		lines[3] = "log: " .. tostring(#(CeroSec.logRing or {})) .. " lines of " ..
			tostring(CeroSec.LOG_MAX) .. "   showing " ..
			(self.logLevel == nil and "all levels" or tostring(self.logLevel))
	else
		local snapshot = self.snapshots[spec.tab]
		local info = snapshot ~= nil and snapshot.info or { "asking the server ..." }
		for i = 1, #info do lines[#lines + 1] = info[i] end
	end

	local L = self.numbers or self:layout()
	for i = 1, INFO_ROWS do
		local text = lines[i]
		if text ~= nil then
			self:drawText(tostring(text), BORDER, L.infoY + (i - 1) * (FONT_H + 2),
				0.8, 0.8, 0.8, 1, UIFont[CeroSecDebugUI.FONT])
		end
	end
end

-- The window follows its own edges when the player drags them, exactly as
-- ISEntitiesDebugWindow does (:67-78) -- and through the SAME arithmetic the
-- window was built with, because two copies of it is how the header row ended up
-- on the tab strip. Every view, every list, every column and every button moves;
-- a view laid out once is a view that stops at the old corner.
function CeroSecDebugUI:onResize()
	ISCollapsableWindow.onResize(self)
	self:applyLayout()
end
