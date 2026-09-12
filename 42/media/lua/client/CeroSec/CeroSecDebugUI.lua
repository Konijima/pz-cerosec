require "ISUI/ISCollapsableWindow"
require "ISUI/ISTabPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecTerminal"

--
-- The debug window.
--
-- Six tabs of what the mod is actually doing: every computer the server holds,
-- the selected machine's filesystem and its /dev, the wire, the scheduler, and
-- the mod's own log. Read-mostly: the only three things it can change are the
-- selected machine's power and where the player is standing, and each of those
-- goes through the ordinary server commands.
--
-- IT LOOKS LIKE THE GAME'S OWN DEBUG WINDOWS and deliberately not like the
-- terminal beside it. A phosphor screen is a thing in the world that a survivor
-- reads; this is a tool, and the game already has a shape for one: an
-- ISCollapsableWindow with an ISTabPanel in it and an ISScrollingListBox per tab
-- with columns on it, which is ISEntitiesDebugWindow's shape
-- (media/lua/client/DebugUIs/DebugMenu/Entity/ISEntitiesDebugWindow.lua:46-62)
-- down to the border spacing. No colours of our own, no fonts of our own: the
-- list box's own palette and UIFont.Small, so it sits among vanilla's tools
-- rather than among ours.
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

CeroSecDebugUI.FONT = "Small"

-- The gap vanilla's own debug windows use between the window edge and what is in
-- it (UI_BORDER_SPACING, ISEntitiesDebugWindow.lua:6).
local BORDER = 10

-- Rows of info under the list. Seven, which is what the Machines tab's own
-- detail block needs; a tab with less to say leaves the rest blank rather than
-- moving the list under the reader's cursor.
local INFO_ROWS = 7

--
-- The tabs
--
-- The name the tab wears, the token the server knows it by, and its columns.
-- The token is nil for the one tab the server has never heard of: the log is the
-- client's own ring buffer (CeroSec.logRing), which in singleplayer is every line
-- the mod wrote and on a dedicated client is the client's own -- see docs/DEBUG.md.
--
-- A column is a name and a width in characters, which is turned into a pixel
-- offset once the font has been measured. Characters and not pixels, because the
-- cells are text of a known length and the UI font size is an option that moves.
--
CeroSecDebugUI.TABS = {
	{
		name = "Machines", tab = "machines",
		columns = { { "at", 11 }, { "face", 5 }, { "power", 5 }, { "chunk", 6 },
			{ "wire", 5 }, { "host", 14 }, { "address", 14 }, { "tel", 10 },
			{ "call", 8 }, { "jobs", 5 }, { "eyes", 5 } },
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

local function measure()
	local manager = getTextManager()
	-- The ADVANCE of one cell and not the ink of one glyph: MeasureStringX counts
	-- the last character of a string as its glyph's ink width, so the difference
	-- between two and one is the advance exactly. The lesson is
	-- CeroSecTerminal's; the arithmetic is the same.
	local cellW = manager:MeasureStringX(UIFont[CeroSecDebugUI.FONT], "nn") -
		manager:MeasureStringX(UIFont[CeroSecDebugUI.FONT], "n")
	if cellW < 1 then cellW = 1 end
	local fontH = manager:getFontHeight(UIFont[CeroSecDebugUI.FONT])
	if cellW == CELL_W and fontH == FONT_H then return end

	CELL_W, FONT_H = cellW, fontH
	-- Wide enough for the widest tab's columns, and no wider: the Log tab's
	-- eighty-character line is what sets it.
	local widest = 0
	for i = 1, #CeroSecDebugUI.TABS do
		local total = 0
		local columns = CeroSecDebugUI.TABS[i].columns
		for k = 1, #columns do total = total + columns[k][2] end
		if total > widest then widest = total end
	end
	WINDOW_W = widest * CELL_W + BORDER * 4
	WINDOW_H = (FONT_H + 6) * 20 + (FONT_H + 2) * INFO_ROWS + BORDER * 6
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
	o.lastMs = 0
	o:setResizable(true)
	o:setTitle(getText("IGUI_CeroSec_Debug_Title"))
	return o
end

function CeroSecDebugUI:createChildren()
	ISCollapsableWindow.createChildren(self)

	local th = self:titleBarHeight()
	local rh = self:resizeWidgetHeight()
	self.th, self.rh = th, rh

	local buttonH = FONT_H + 8
	local infoH = (FONT_H + 2) * INFO_ROWS
	local panelH = self:getHeight() - th - rh - buttonH - infoH - BORDER * 4

	self.panel = ISTabPanel:new(BORDER, th + BORDER, self:getWidth() - BORDER * 2, panelH)
	self.panel:initialise()
	self.panel.equalTabWidth = false
	self:addChild(self.panel)

	self.lists = {}
	for i = 1, #CeroSecDebugUI.TABS do
		local spec = CeroSecDebugUI.TABS[i]
		local list = ISScrollingListBox:new(0, 0, self.panel:getWidth(),
			panelH - self.panel.tabHeight)
		list:initialise()
		list:instantiate()
		list:setFont(CeroSecDebugUI.FONT, 2)
		-- The column headers and the rules between them are the list box's own
		-- (ISScrollingListBox:prerender, the `#self.columns > 0` block): it draws
		-- them one row ABOVE the first item, which is why the list is pushed down
		-- by one row height below.
		local at = 0
		for k = 1, #spec.columns do
			list:addColumn(spec.columns[k][1], at)
			at = at + spec.columns[k][2] * CELL_W
		end
		list.drawBorder = true
		-- One cell per column, drawn at the column's own offset. Assigned rather
		-- than derived: there is one kind of row in this window and six lists that
		-- draw it.
		list.doDrawItem = CeroSecDebugUI.drawRow
		list:setOnMouseDownFunction(self, CeroSecDebugUI.onRowClicked)
		list.debugTab = spec
		self.lists[i] = list
		self.panel:addView(spec.name, list)
	end

	--
	-- The buttons
	--
	-- One row under the list. Refresh first because it is the one that is used
	-- most; the three that CHANGE something in the middle, named as plainly as
	-- possible; and the log filters last, shown only on the tab they mean
	-- anything on.
	--
	local y = th + BORDER + panelH + BORDER
	self.buttons = {}
	local at = BORDER
	local function button(label, fn, onLog)
		local w = getTextManager():MeasureStringX(UIFont[CeroSecDebugUI.FONT], label) + 20
		local made = ISButton:new(at, y, w, buttonH, label, self, fn)
		made:initialise()
		made:instantiate()
		made:setFont(UIFont[CeroSecDebugUI.FONT])
		self:addChild(made)
		self.buttons[#self.buttons + 1] = { button = made, onLog = onLog }
		at = at + w + 6
		return made
	end

	button(getText("IGUI_CeroSec_Debug_Refresh"), CeroSecDebugUI.onRefresh, false)
	self.onButton = button(getText("IGUI_CeroSec_Debug_TurnOn"),
		CeroSecDebugUI.onTurnOn, false)
	self.offButton = button(getText("IGUI_CeroSec_Debug_TurnOff"),
		CeroSecDebugUI.onTurnOff, false)
	self.gotoButton = button(getText("IGUI_CeroSec_Debug_Teleport"),
		CeroSecDebugUI.onTeleport, false)
	self.termButton = button(getText("IGUI_CeroSec_Debug_Terminal"),
		CeroSecDebugUI.onTerminal, false)
	self.dumpButton = button(getText("IGUI_CeroSec_Debug_Dump"),
		CeroSecDebugUI.onDump, false)

	self.levelButtons = {}
	for i = 1, #CeroSecDebugUI.LEVELS do
		local spec = CeroSecDebugUI.LEVELS[i]
		local made = button(spec.label, CeroSecDebugUI.onLevel, true)
		made.debugLevel = spec.level
		self.levelButtons[i] = made
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
	if type(args.tab) ~= "string" then return end
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

	-- The selection is kept across a refresh by WHAT it was and not by where it
	-- was: two seconds later a machine may have moved up the list, and a reader
	-- whose cursor jumped to somebody else's row every two seconds would be a
	-- reader who cannot read.
	local wanted = nil
	if type(list.selected) == "number" and list.selected >= 1
			and list.selected <= #list.items then
		local held = list.items[list.selected]
		if type(held) == "table" and type(held.item) == "table" then
			wanted = held.item.c[1]
		end
	end

	list:clear()
	local rows = snapshot.rows or {}
	for i = 1, #rows do
		local row = rows[i]
		if type(row) == "table" and type(row.c) == "table" then
			list:addItem(tostring(row.c[1]), row)
		end
	end
	if wanted ~= nil then
		for i = 1, #list.items do
			if list.items[i].item.c[1] == wanted then list.selected = i end
		end
	end
	return list
end

-- The Log tab, which comes from nowhere: CeroSec.logRing is this Lua state's own
-- record of what the mod said. Newest LAST, so it reads down the way it happened.
function CeroSecDebugUI:fillLog()
	local list = self.lists[#CeroSecDebugUI.TABS]
	if list == nil then return end
	list:clear()
	local ring = CeroSec.logRing or {}
	for i = 1, #ring do
		local line = ring[i]
		if type(line) == "table" and
				(self.logLevel == nil or line.level == self.logLevel) then
			list:addItem(tostring(line.level), { c = { line.level, line.text } })
		end
	end
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
	local spec = self.debugTab
	local cells = item.item ~= nil and item.item.c or nil
	if cells ~= nil and spec ~= nil then
		local at = 0
		for i = 1, #spec.columns do
			local text = cells[i]
			if text ~= nil and text ~= "" then
				self:drawText(tostring(text), at + 4, y + padY,
					color.r, color.g, color.b, color.a, self.font)
			end
			at = at + spec.columns[i][2] * CELL_W
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
	for i = 1, #self.lists do
		local spec = CeroSecDebugUI.TABS[i]
		if spec.tab ~= nil and spec.tab ~= "machines" then self.lists[i]:clear() end
	end
	self:refresh()
end

--
-- The buttons
--

function CeroSecDebugUI:onRefresh()
	self:refresh()
end

function CeroSecDebugUI:onTurnOn()
	if not self:hasMachine() then return end
	self:send("debugact", { act = "on" })
	self:refresh()
end

function CeroSecDebugUI:onTurnOff()
	if not self:hasMachine() then return end
	self:send("debugact", { act = "off" })
	self:refresh()
end

function CeroSecDebugUI:onDump()
	if not self:hasMachine() then return end
	self:send("debugact", { act = "dump" })
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
	local computer = self:computerObject()
	if computer == nil then
		CeroSec.log(CeroSec.LOG_WARN, "debug: no computer in the world at " ..
			tostring(self.cx) .. "," .. tostring(self.cy) .. "," .. tostring(self.cz))
		return
	end
	CeroSecTerminal.open(self.playerObj, computer)
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

	-- The three level buttons belong to the Log tab and are not there on any
	-- other; everything else is always there. And the five that act on a machine
	-- are greyed with nothing selected. Worked out every frame rather than when
	-- something changes: whether a button means anything is a fact about the
	-- window right now, and a window that remembered it would be a window that
	-- forgets.
	local onLog = self:activeSpec().tab == nil
	for i = 1, #self.buttons do
		local entry = self.buttons[i]
		if entry.onLog then entry.button:setVisible(onLog) end
	end
	local machine = self:hasMachine()
	self.onButton:setEnable(machine)
	self.offButton:setEnable(machine)
	self.gotoButton:setEnable(machine)
	self.termButton:setEnable(machine)
	self.dumpButton:setEnable(machine)
end

function CeroSecDebugUI:render()
	ISCollapsableWindow.render(self)
	if self.closing then return end

	local spec = self:activeSpec()
	local lines = nil
	if spec.tab == nil then
		lines = { "log: " .. tostring(#(CeroSec.logRing or {})) .. " lines of " ..
			tostring(CeroSec.LOG_MAX) .. "   showing " ..
			(self.logLevel == nil and "all levels" or tostring(self.logLevel)) }
	else
		local snapshot = self.snapshots[spec.tab]
		lines = snapshot ~= nil and snapshot.info or { "asking the server ..." }
	end

	local y = self:getHeight() - self.rh - BORDER - (FONT_H + 2) * INFO_ROWS
	for i = 1, INFO_ROWS do
		local text = lines[i]
		if text ~= nil then
			self:drawText(tostring(text), BORDER, y + (i - 1) * (FONT_H + 2),
				0.8, 0.8, 0.8, 1, UIFont[CeroSecDebugUI.FONT])
		end
	end
end

-- The window follows its own edges when the player drags them, exactly as
-- ISEntitiesDebugWindow does (:66-77): the panel and every view in it are told
-- the new size, because a view laid out once is a view that stops at the old
-- corner.
function CeroSecDebugUI:onResize()
	ISCollapsableWindow.onResize(self)
	if self.panel == nil then return end
	local buttonH = FONT_H + 8
	local infoH = (FONT_H + 2) * INFO_ROWS
	local panelH = self:getHeight() - self.th - self.rh - buttonH - infoH - BORDER * 4
	self.panel:setWidth(self:getWidth() - BORDER * 2)
	self.panel:setHeight(panelH)
	for i = 1, #self.lists do
		self.lists[i]:setWidth(self.panel:getWidth())
		self.lists[i]:setHeight(panelH - self.panel.tabHeight)
	end
	local y = self.th + BORDER + panelH + BORDER
	for i = 1, #self.buttons do
		self.buttons[i].button:setY(y)
	end
end
