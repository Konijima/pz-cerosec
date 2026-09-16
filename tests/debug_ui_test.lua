-- The debug window. Run from the repo root:
--   lua5.1 tests/debug_ui_test.lua
--
-- Same shape as manual_ui_test.lua and for the same reason: the real client file
-- is loaded against a fake game -- a font of a known width, a window base class
-- that records what was painted, a tab panel that remembers which view is in
-- front, a list box that remembers what was put in it -- and what is asserted is
-- what ends up on the glass and what goes out on the wire, not what a field says.
--
-- The SERVER half is not this bench's business and is not faked here: the
-- snapshots are built and asserted in tests/window_test.lua, against three real
-- machines on a real system. What travels between the two is a table of rows, so
-- this bench hands the window rows of its own and checks what it does with them.
--
-- Three things are worth the bench on their own:
--
--   * the six tabs exist, each with its own columns, and every column of every
--     tab is drawn -- a window whose eleventh column fell off the end would look
--     perfectly right to a test that counted rows.
--   * selecting a machine asks the server AGAIN, carrying that machine and this
--     window's own token: the Files, Devices and Scheduler tabs are answers about
--     ONE computer and a stale one under a new name is the one mistake this
--     window must not make.
--   * closing takes the tick handler off. A handler left registered by a window
--     that is gone is a closure holding a dead window, called sixty times a
--     second for the rest of the session, asking the server for snapshots nobody
--     can see. The harness below FAILS if it stays -- it counts what is actually
--     registered on Events.OnTickEvenPaused and does not take the window's word
--     for it.
--

--
-- The game, faked.
--

_G.require = function() end
_G.__now = 1000
_G.getTimestampMs = function() return _G.__now end
_G.getText = function(key) return key end
_G.isClient = function() return false end

_G.UIFont = { Code = "Code", Small = "Small" }
_G.Keyboard = { KEY_ESCAPE = 1 }

-- A proportional font, on purpose: UIFont.Small is proportional in the game and
-- the window measures a CELL off it (the advance of one "n", as the difference
-- between two and one). A fake that answered a fixed width per character could
-- not see a cell taken off the ink of a glyph go wrong, which is the lesson
-- CeroSecTerminal and CeroSecManualUI both paid for.
local CHAR_W = 6
local INK = { n = 5, M = 9 }
local function textWidth(s)
	if s == nil or s == "" then return 0 end
	local last = string.sub(s, -1)
	return CHAR_W * (#s - 1) + (INK[last] or CHAR_W - 1)
end

-- The ADVANCE of a string off the same fake, worked out the same way the window
-- works it out (the "M" sentinel, CeroSecTerminal.lua:1416-1419): the bench
-- measures columns with the arithmetic under test rather than with a second one of
-- its own, so a column that is one glyph's ink too narrow is a column this file
-- catches instead of agreeing with.
local function adv(s)
	if s == nil or s == "" then return 0 end
	return textWidth(s .. "M") - textWidth("M")
end

-- What the window pads a cell by inside its column and leaves as air on its right
-- (PAD and GAP in CeroSecDebugUI). Here as numbers because what the bench asserts
-- is where the ink LANDS, not what the constant says.
local CELL_PAD = 10
local CELL_GAP = 6
_G.getTextManager = function()
	return {
		MeasureStringX = function(_, _, s) return textWidth(s) end,
		getFontHeight = function() return 12 end,
		getFontFromEnum = function() return { getLineHeight = function() return 12 end } end,
	}
end
_G.getCore = function()
	return { getScreenWidth = function() return 1920 end,
		getScreenHeight = function() return 1080 end }
end
_G.getTexture = function() return {} end
_G.getMouseX = function() return 0 end
_G.getMouseY = function() return 0 end
_G.instanceof = function(o, kind) return type(o) == "table" and o.__class == kind end

-- Events, with a REAL register: Add appends and Remove takes away, so a handler
-- that was never removed is a handler this bench can count. A fake whose Remove
-- did nothing would be a fake that made the leak impossible to see -- which is
-- the whole thing this file exists to catch.
_G.Events = setmetatable({}, { __index = function(t, key)
	local event = { handlers = {} }
	event.Add = function(fn) event.handlers[#event.handlers + 1] = fn end
	event.Remove = function(fn)
		for i = #event.handlers, 1, -1 do
			if event.handlers[i] == fn then table.remove(event.handlers, i) end
		end
	end
	rawset(t, key, event)
	return event
end })

local function derive(base, name)
	local o = {}
	for key, value in pairs(base) do o[key] = value end
	o.Type = name
	o.__index = o
	o.derive = base.derive
	return o
end

--
-- ISUIElement, the half of it these three classes lean on.
--
local Element = {}
function Element.setX(self, v) self.x = v end
function Element.setY(self, v) self.y = v end
function Element.setWidth(self, v) self.width = v end
function Element.setHeight(self, v) self.height = v end
function Element.getX(self) return self.x end
function Element.getY(self) return self.y end
function Element.getWidth(self) return self.width end
function Element.getHeight(self) return self.height end
function Element.getYScroll(self) return self.yScroll or 0 end
function Element.isMouseOver(self) return self.mouseOver == true end
function Element.setVisible(self, v) self.visible = v end
function Element.isVisible(self) return self.visible end
function Element.initialise() end
-- The game's own order, and it matters: ISUIElement:instantiate() makes the java
-- object and then calls self:createChildren() (ISUIElement.lua, the last line of
-- instantiate). A fake whose instantiate did nothing would leave every window in
-- this bench with no children at all -- and every assertion about a tab would be
-- an assertion about nothing.
function Element.instantiate(self)
	self.javaObject = {}
	if self.createChildren ~= nil then self:createChildren() end
end
function Element.addToUIManager(self)
	if self.javaObject == nil then self:instantiate() end
	self.onManager = true
end
function Element.removeFromUIManager(self) self.onManager = false end
function Element.addChild(self, child) self.children[#self.children + 1] = child end
function Element.drawRect() end
function Element.drawRectBorder() end
function Element.setStencilRect() end
function Element.clearStencilRect() end

local function applyElement(class)
	for key, value in pairs(Element) do class[key] = value end
end

ISCollapsableWindow = { derive = function(self, name) return derive(self, name) end }
applyElement(ISCollapsableWindow)
function ISCollapsableWindow.new(self, x, y, w, h)
	local o = setmetatable({}, self)
	o.x, o.y, o.width, o.height = x, y, w, h
	o.children = {}
	o.painted = {}
	return o
end
function ISCollapsableWindow.createChildren() end
function ISCollapsableWindow.prerender() end
function ISCollapsableWindow.render() end
function ISCollapsableWindow.onResize() end
function ISCollapsableWindow.setResizable(self, v) self.resizable = v end
function ISCollapsableWindow.setTitle(self, title) self.titleText = title end
function ISCollapsableWindow.titleBarHeight() return 16 end
function ISCollapsableWindow.resizeWidgetHeight() return 6 end
function ISCollapsableWindow.drawText(self, text, x, y)
	self.painted[#self.painted + 1] = { text = text, x = x, y = y }
end

--
-- ISPanel, which is what each tab's VIEW is: the thing the tab panel positions,
-- with the list a header row down inside it. Nothing of it is faked but the four
-- calls the window makes on it -- its geometry comes from applyElement above, so
-- what the bench reads off a view is what the window set.
--
local Panel = {}
Panel.__index = Panel
applyElement(Panel)
function Panel:noBackground() self.background = false end
ISPanel = { new = function(_, x, y, w, h)
	local o = setmetatable({}, Panel)
	o.x, o.y, o.width, o.height = x, y, w, h
	o.children = {}
	o.painted = {}
	return o
end }

--
-- ISScrollingListBox: what was put in it, in order, and the columns it was given.
--
local List = {}
List.__index = List
applyElement(List)
function List.new(x, y, w, h)
	local o = setmetatable({}, List)
	o.x, o.y, o.width, o.height = x, y, w, h
	o.items = {}
	o.columns = {}
	o.selected = 1
	o.painted = {}
	o.itemheight = 16
	o.itemPadY = 2
	o.font = "Small"
	o.textColor = { r = 1, g = 1, b = 1, a = 1 }
	o.selectedTextColor = { r = 1, g = 1, b = 1, a = 1 }
	o.children = {}
	return o
end
function List:setFont(font, padY) self.font = font; self.itemPadY = padY end
function List:addColumn(name, size)
	self.columns[#self.columns + 1] = { name = name, size = size }
end
function List:addItem(text, item)
	local entry = { text = text, item = item, index = #self.items + 1 }
	self.items[#self.items + 1] = entry
	return entry
end
function List:clear() self.items = {}; self.selected = 1 end
function List:size() return #self.items end
function List:setOnMouseDownFunction(target, fn) self.target = target; self.onmousedown = fn end
-- What the game does when a row is clicked (ISScrollingListBox:onMouseDown ->
-- invokeOnMouseDownFunction): the TARGET is called with the row's item, and the
-- selection has already moved.
function List:clickRow(index)
	self.selected = index
	self.onmousedown(self.target, self.items[index].item)
end
function List:drawSelection() end
function List:drawMouseOverHighlight() end
function List:isMouseOverScrollBar() return false end
function List:drawText(text, x, y)
	self.painted[#self.painted + 1] = { text = text, x = x, y = y }
end
-- One frame of the list: the game's own prerender walks the items and calls
-- doDrawItem on each, which is the method the window replaces.
function List:frame()
	self.painted = {}
	local y = 0
	for i = 1, #self.items do
		self.items[i].index = i
		y = self:doDrawItem(y, self.items[i], false)
	end
end
ISScrollingListBox = { new = function(_, x, y, w, h) return List.new(x, y, w, h) end }

--
-- ISTabPanel: the views it was given and which of them is in front. addView is
-- written the way the game writes it (ISTabPanel.lua:484-508) in the one respect
-- this window depends on: the view is pushed down by the tab height and is
-- visible only if it is the first.
--
local TabPanel = {}
TabPanel.__index = TabPanel
applyElement(TabPanel)
function TabPanel.new(x, y, w, h)
	local o = setmetatable({}, TabPanel)
	o.x, o.y, o.width, o.height = x, y, w, h
	o.viewList = {}
	o.children = {}
	o.tabHeight = 18
	o.tabPadX = 20
	return o
end
function TabPanel:addView(name, view)
	local entry = { name = name, id = #self.viewList + 1, view = view }
	self.viewList[#self.viewList + 1] = entry
	view:setY(self.tabHeight)
	self:addChild(view)
	if #self.viewList == 1 then
		view:setVisible(true)
		self.activeView = entry
	else
		view:setVisible(false)
	end
end
function TabPanel:getActiveViewIndex()
	if self.activeView == nil then return 1 end
	return self.activeView.id
end
function TabPanel:activateView(name)
	for i = 1, #self.viewList do
		if self.viewList[i].name == name then
			self.activeView = self.viewList[i]
			for k = 1, #self.viewList do
				self.viewList[k].view:setVisible(k == i)
			end
			return true
		end
	end
	return false
end
ISTabPanel = { new = function(_, x, y, w, h) return TabPanel.new(x, y, w, h) end }

--
-- ISButton: its label, who it calls, and whether it is there and usable.
--
local Button = {}
Button.__index = Button
applyElement(Button)
function Button:setFont(font) self.font = font end
function Button:setEnable(v) self.enabled = v end
function Button:setTitle(title) self.title = title end
ISButton = { new = function(_, x, y, w, h, title, target, onclick)
	local o = setmetatable({}, Button)
	o.x, o.y, o.width, o.height = x, y, w, h
	o.title = title
	o.target = target
	o.onclick = onclick
	o.enabled = true
	o.visible = true
	o.children = {}
	return o
end }
--
-- ISTextEntryBox: what was typed in it, and whether it may be typed in at all.
--
-- getInternalText and not getText, because that is the one the mod reads everywhere
-- (CeroSecTerminal reads it in eleven places): the java object's getText carries the
-- cursor's own formatting and getInternalText is the letters.
--
-- setMaxTextLength really TRUNCATES here. In the game it goes to the java object and
-- a box simply refuses the next keystroke; a fake that ignored it would let a bench
-- type a login longer than any /etc/passwd line could carry and then assert about a
-- string the glass could never have produced.
--
local Entry = {}
Entry.__index = Entry
applyElement(Entry)
function Entry:setMaxTextLength(n) self.maxText = n end
function Entry:setEditable(v) self.editable = v end
function Entry:getInternalText() return self.text end
function Entry:setText(str)
	local at = tostring(str or "")
	if self.maxText ~= nil and #at > self.maxText then
		at = string.sub(at, 1, self.maxText)
	end
	self.text = at
end
ISTextEntryBox = { new = function(_, title, x, y, w, h)
	local o = setmetatable({}, Entry)
	o.x, o.y, o.width, o.height = x, y, w, h
	o.text = title or ""
	o.editable = true
	o.visible = true
	o.children = {}
	return o
end }

--
-- ISComboBox: the options it was given, with the DATA on each, and which is chosen.
--
-- addOptionWithData is the one the window uses, because what travels on the wire is
-- a catalogue id and not the words on a widget (ISComboBox.lua:435-444, and
-- getSelectedData at :518).
--
local Combo = {}
Combo.__index = Combo
applyElement(Combo)
function Combo:addOptionWithData(option, data, tooltip)
	self.options[#self.options + 1] = { text = option, data = data, tooltip = tooltip }
	if self.selected == 0 then self.selected = 1 end
end
function Combo:getOptionCount() return #self.options end
function Combo:getOptionData(index)
	local at = self.options[index]
	return at ~= nil and at.data or nil
end
function Combo:getSelectedData()
	local at = self.options[self.selected]
	return at ~= nil and at.data or nil
end
function Combo:setSelected(value) self.selected = value end
function Combo:setEnabled(v) self.enabled = v end
ISComboBox = { new = function(_, x, y, w, h)
	local o = setmetatable({}, Combo)
	o.x, o.y, o.width, o.height = x, y, w, h
	o.options = {}
	o.selected = 0
	o.enabled = true
	o.visible = true
	o.children = {}
	return o
end }

-- The disk catalogue, stood in for: the window builds its combo off
-- CeroSecContent.DISKS and this bench is not loading the eight-thousand-line
-- catalogue to find out how many entries it has. What matters here is that the combo
-- is built off the table rather than off a list of the window's own, which is what a
-- fake with entries of ITS OWN names proves -- a window with a hard-coded list would
-- come out with the real ids and this bench would go red on them.
CeroSecContent = { DISKS = {
	{ id = "BENCH ONE" },
	{ id = "BENCH TWO" },
	{ id = "BENCH THREE AND A LONGER ONE" },
} }

-- What the game does when a button is pressed: the target, then the button.
local function press(button)
	button.onclick(button.target, button)
end

-- The terminal, stood in for: the window opens it and this bench records that it
-- did, because a real one would want a whole computer behind it.
CeroSecTerminal = { opened = {} }
function CeroSecTerminal.open(playerObj, computer)
	CeroSecTerminal.opened[#CeroSecTerminal.opened + 1] =
		{ player = playerObj, computer = computer }
end

-- The world, for the one thing the window asks it: is there a computer tile on
-- the selected square? nil is a chunk the streamer has not brought in.
_G.__computers = {}
_G.getCell = function()
	return {
		getGridSquare = function(_, x, y, z)
			local object = _G.__computers[x .. "," .. y .. "," .. z]
			if object == nil then return nil end
			return {
				getObjects = function()
					return { size = function() return 1 end,
						get = function(_, _) return object end }
				end,
			}
		end,
	}
end

--
-- The mod, loaded the way the game loads it.
--

local LUA = "42/media/lua/"
local FILES = {
	"shared/CeroSec/CeroSecDefs.lua",
	"client/CeroSec/CeroSecDebugUI.lua",
}
for i = 1, #FILES do
	local path = LUA .. FILES[i]
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end

-- The benches open both developer doors. The shipped defaults are false
-- (release); the blocks that need a shut door close it themselves.
CeroSec.DEV_MANUAL_MENU = true
CeroSec.DEV_DEBUG_MENU = true


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
-- One window, wired to a server that answers with rows of the bench's own.
--

local function newBench()
	-- The window the block before this one opened, SHUT and not merely forgotten.
	-- Nil-ing the instance would leave its tick handler on the event, and every
	-- handler count below would be counting the benches above it -- which is
	-- exactly the leak this file exists to catch, so the harness must not be the
	-- thing that leaks.
	if CeroSecDebugUI.instance ~= nil then CeroSecDebugUI.instance:close() end
	-- And the register really is empty afterwards. Asserted HERE, at the top of
	-- every block, because it is the one defect that does not show where it
	-- happens: a window that leaves its handler behind breaks a bench three blocks
	-- later, on a count nobody can read.
	check("no tick handler is left over from the block before",
		#Events.OnTickEvenPaused.handlers == 0)
	CeroSec.logRing = {}
	_G.__computers = {}
	CeroSecTerminal.opened = {}

	local bench = {}
	local player = {
		getPlayerNum = function() return 0 end,
		getOnlineID = function() return -1 end,
		isDead = function() return false end,
		teleports = {},
	}
	-- Standing at the machine the window opens on, which is where a survivor who
	-- right-clicked a computer is. Where he is matters now: the window greys "Open
	-- terminal" on a machine he is not beside, with the server's own tolerance
	-- (SCeroSecSystem's isAdjacent).
	player.x, player.y, player.z = 10.5, 10.5, 0
	player.getX = function() return player.x end
	player.getY = function() return player.y end
	player.getZ = function() return player.z end
	player.getCurrentSquare = function()
		return { getZ = function() return player.z end }
	end
	player.teleportTo = function(_, x, y, z)
		player.teleports[#player.teleports + 1] = { x = x, y = y, z = z }
		-- And he really is there afterwards, because the window asks where he is.
		player.x, player.y, player.z = x, y, z
	end
	bench.player = player

	-- Every command the window sent, in order, and what the fake server answers.
	bench.sent = {}
	bench.answer = nil
	_G.CCeroSecSystem = { instance = { sendCommand = function(_, sender, command, args)
		bench.sent[#bench.sent + 1] = { command = command, args = args, by = sender }
		if bench.answer == nil then return end
		local reply = bench.answer(command, args)
		if reply == nil then return end
		-- Back in through the one door the client dispatches on, so the token
		-- check is part of what is under test.
		CeroSecDebugUI.onServerAnswer("debug", reply)
	end } }

	bench.window = CeroSecDebugUI.open(player, 10, 10, 0)

	function bench.last(command)
		for i = #bench.sent, 1, -1 do
			if bench.sent[i].command == command then return bench.sent[i] end
		end
		return nil
	end

	function bench.forget() bench.sent = {} end

	function bench.tick(ms)
		_G.__now = _G.__now + (ms or 0)
		local handlers = Events.OnTickEvenPaused.handlers
		for i = 1, #handlers do handlers[i]() end
	end

	function bench.handlerCount()
		return #Events.OnTickEvenPaused.handlers
	end

	-- One frame of the window and of the list in front of it.
	function bench.frame()
		bench.window.painted = {}
		bench.window:prerender()
		bench.window:render()
		bench.list():frame()
	end

	function bench.list()
		return bench.window.lists[bench.window:activeIndex()]
	end

	function bench.view()
		return bench.window.views[bench.window:activeIndex()]
	end

	-- Which column a string was painted in, by the x it was painted at: the window
	-- draws a cell at its column's offset plus the pad, so the x names the column.
	-- -1 for ink that lands in no column at all, which is the answer that fails a
	-- check below.
	function bench.columnAt(x)
		local list = bench.list()
		if list.colX == nil then return -1 end
		for k = 1, #list.colX do
			if list.colX[k] + CELL_PAD == x then return k end
		end
		return -1
	end

	function bench.buttonNamed(label)
		for i = 1, #bench.window.buttons do
			local made = bench.window.buttons[i].button
			if made.title == label then return made end
		end
		return nil
	end

	-- Every string the window or the list in front of it painted this frame.
	function bench.painted(needle)
		local lists = { bench.window.painted, bench.list().painted }
		for l = 1, #lists do
			for i = 1, #lists[l] do
				local text = lists[l][i].text
				if type(text) == "string" and string.find(text, needle, 1, true) then
					return true
				end
			end
		end
		return false
	end

	return bench
end

-- A snapshot of the shape the server sends, for one tab. The rows are the
-- bench's, but their SHAPE is not: a row is a table of cells with the machine it
-- names on it, which is what SCeroSecDebug builds and what window_test asserts.
local function snapshot(token, tab, rows, info)
	return { token = token, tab = tab, rows = rows, info = info or {} }
end

-- Two machines the mod is doing something with. `used` is the server's own flag
-- (SCeroSecDebug.isUsed) and both carry it, because the window shows the used ones
-- by default and a bench whose rows were all filtered out would be a bench about an
-- empty list.
local function machineRows()
	return {
		{ c = { "10,10,0", "S", "on", "here", "yes", "office", "10.4.17.1",
			"555-0142", "-", "0", "1" }, x = 10, y = 10, z = 0, used = true },
		{ c = { "60,60,0", "E", "on", "away", "-", "shed", "10.9.44.1",
			"555-0911", "KE4QWZ", "2", "0" }, x = 60, y = 60, z = 0, used = true },
	}
end

-- The county as a save an hour old really answers it: one machine in use and two
-- computer sprites a chunk brought in and nobody ever touched.
local function countyRows()
	local rows = machineRows()
	rows[2] = { c = { "300,220,0", "N", "off", "away", "-", "-", "-", "-", "-", "-", "-" },
		x = 300, y = 220, z = 0, used = false }
	rows[3] = { c = { "301,220,0", "N", "off", "away", "-", "-", "-", "-", "-", "-", "-" },
		x = 301, y = 220, z = 0, used = false }
	return rows
end

-- A snapshot of the shape Commands.debug sends for a machine that cannot be
-- switched on, with the server's own words for why (CeroSecDebug.selection).
local function selected(token, fields)
	local snap = snapshot(token, "machines", machineRows(), { "machines: 2 of 2" })
	snap.x, snap.y, snap.z = 10, 10, 0
	for key, value in pairs(fields) do snap[key] = value end
	return snap
end

--
-- 1. The window, its tabs, and what it asked for
--

do
	local bench = newBench()
	local window = bench.window

	eq("the window is on the UI manager", window.onManager, true)
	eq("and it is the one instance there is", CeroSecDebugUI.instance, window)
	eq("it is resizable", window.resizable, true)
	eq("and it is named", window.titleText, "IGUI_CeroSec_Debug_Title")

	-- Six tabs, in the order the tab table declares them, each with its own list
	-- and its own columns.
	eq("six tabs", #window.panel.viewList, #CeroSecDebugUI.TABS)
	for i = 1, #CeroSecDebugUI.TABS do
		local spec = CeroSecDebugUI.TABS[i]
		eq("tab " .. i .. " is named for itself", window.panel.viewList[i].name, spec.name)
		local list = window.lists[i]
		check("tab " .. i .. " has a list", list ~= nil)
		eq("tab " .. i .. " has its own columns", #list.columns, #spec.columns)
		for k = 1, #spec.columns do
			eq("tab " .. i .. " column " .. k .. " is named", list.columns[k].name,
				spec.columns[k][1])
		end
		-- The offsets climb, and the first is at the left edge: a column at the
		-- same offset as the one before it is a column drawn on top of it.
		eq("tab " .. i .. " starts at the left edge", list.columns[1].size, 0)
		for k = 2, #list.columns do
			check("tab " .. i .. " column " .. k .. " is right of the one before it",
				list.columns[k].size > list.columns[k - 1].size)
		end
	end

	-- The first tab is in front, and opening the window asked for it.
	eq("the first tab is in front", window:activeIndex(), 1)
	local asked = bench.last("debug")
	check("opening asked the server for something", asked ~= nil)
	eq("and it asked for the tab in front", asked.args.tab, "machines")
	eq("carrying the machine it was opened on", asked.args.x, 10)
	eq("and its own token", asked.args.token, window.token)
end

--
-- 2. An answer, drawn
--

do
	local bench = newBench()
	local window = bench.window
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot(window.token, "machines", machineRows(), { "machines: 2 of 2" }))

	local list = bench.list()
	eq("both rows are in the list", #list.items, 2)
	bench.frame()

	-- EVERY cell of EVERY column, and not merely the first: eleven columns is
	-- eleven drawText calls, and a window that stopped at the tenth would look
	-- perfectly right to a bench that counted rows.
	local rows = machineRows()
	for r = 1, #rows do
		for c = 1, #rows[r].c do
			local text = rows[r].c[c]
			if text ~= "" and text ~= "-" then
				check("row " .. r .. " column " .. c .. " (" .. text .. ") is drawn",
					bench.painted(text))
			end
		end
	end
	-- And the info block under it, which is the server's own words.
	check("the info line is under the list", bench.painted("machines: 2 of 2"))

	-- The cells are drawn AT their columns and not all at the left: the second
	-- column of a row starts right of the first.
	local firstX, secondX = nil, nil
	for i = 1, #list.painted do
		if list.painted[i].text == "10,10,0" then firstX = list.painted[i].x end
		if list.painted[i].text == "office" then secondX = list.painted[i].x end
	end
	check("the first cell is near the left", firstX ~= nil and firstX < 20)
	check("and a later column is well to the right of it",
		secondX ~= nil and secondX > firstX + 40)
end

--
-- 3. An answer that is not this window's
--

do
	local bench = newBench()
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot("dbg-somebody-else", "machines", machineRows()))
	eq("a snapshot carrying another window's token is not drawn",
		#bench.list().items, 0)

	-- And a message that is not about this window at all: the client dispatches
	-- EVERY answer of the module to both windows, so the terminal's screens come
	-- through here too and must go nowhere.
	CeroSecDebugUI.onServerAnswer("screen",
		{ token = bench.window.token, lines = { "admin@office:~$ " } })
	eq("and neither is an answer for the terminal", #bench.list().items, 0)
end

--
-- 4. Selecting a machine
--

do
	local bench = newBench()
	local window = bench.window
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot(window.token, "machines", machineRows()))
	-- The Files tab has an answer about the machine that WAS selected.
	CeroSecDebugUI.onServerAnswer("debug", snapshot(window.token, "files",
		{ { c = { "/etc/passwd", "file", "-rw-r--r--", "root", "61" } } },
		{ "nodes 90 of 512" }))
	eq("the files tab holds the first machine's disk", #window.lists[2].items, 1)

	bench.forget()
	bench.list():clickRow(2)

	eq("clicking a row selects the machine it names", window.cx, 60)
	eq("and its y", window.cy, 60)
	eq("and its z", window.cz, 0)

	local asked = bench.last("debug")
	check("and the server is asked again", asked ~= nil)
	eq("for the tab in front", asked.args.tab, "machines")
	eq("naming the machine just selected", asked.args.x, 60)
	eq("and the same y", asked.args.y, 60)
	eq("under this window's own token", asked.args.token, window.token)

	-- Everything held about the machine that WAS selected is gone. A Files tab
	-- still showing the last computer's disk under a new machine's name is the one
	-- mistake this window must not make.
	eq("the other tab's stale rows are dropped", #window.lists[2].items, 0)
	eq("and so is its stale snapshot", window.snapshots["files"], nil)
	-- And the machine detail under the county list goes with them, because it is
	-- the selected machine's and the selection has just moved.
	eq("the county list's own snapshot is dropped too",
		window.snapshots["machines"], nil)
	-- But the county list's ROWS stay: they are a fact about the county, and a
	-- reader who clicked a row must not watch the list he clicked in empty itself
	-- under his cursor.
	eq("the county list keeps its rows", #window.lists[1].items, 2)
	eq("and the row he clicked is still the selected one", window.lists[1].selected, 2)

	-- Clicking the row that is already selected asks nothing: a refresh every two
	-- seconds is enough, and a round trip per click would be a round trip per
	-- twitch of the mouse.
	bench.forget()
	bench.list():clickRow(2)
	eq("clicking the selected row asks nothing", #bench.sent, 0)
end

--
-- 5. Which tab is asked for, and where an answer lands
--

do
	local bench = newBench()
	local window = bench.window
	window.panel:activateView("Devices")
	bench.forget()
	window:refresh()
	eq("the tab in front is the tab asked for", bench.last("debug").args.tab, "devices")

	-- An answer for a tab that is NOT in front lands in ITS list and not in the
	-- one the reader is looking at: a snapshot that arrived after the reader moved
	-- on belongs where it was asked for.
	CeroSecDebugUI.onServerAnswer("debug", snapshot(window.token, "network",
		{ { c = { "eth", "400.700", "2 on this wire", "2 switched on", "" } } }))
	eq("the network answer went into the network list", #window.lists[4].items, 1)
	eq("and the devices list is still empty", #window.lists[3].items, 0)

	-- Switching to it draws what already arrived, with no round trip at all.
	window.panel:activateView("Network")
	bench.forget()
	bench.frame()
	eq("switching tabs sends nothing", #bench.sent, 0)
	check("and the answer that was waiting is on the glass", bench.painted("400.700"))
end

--
-- 6. The buttons
--

do
	local bench = newBench()
	local window = bench.window

	-- Turn on and turn off go through the server, as the one act this window can
	-- do, naming the selected machine.
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_TurnOn"))
	local act = bench.last("debugact")
	check("Turn on sends an act", act ~= nil)
	eq("which is 'on'", act.args.act, "on")
	eq("on the selected machine", act.args.x, 10)
	eq("under this window's token", act.args.token, window.token)
	check("and it asks for the tab again afterwards", bench.last("debug") ~= nil)

	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_TurnOff"))
	eq("Turn off sends 'off'", bench.last("debugact").args.act, "off")

	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_Dump"))
	eq("Dump state sends 'dump'", bench.last("debugact").args.act, "dump")
	eq("and asks for no snapshot, the dump going to the log",
		bench.last("debug"), nil)

	-- The self-test: one act, no snapshot asked for -- the verdict comes back on
	-- the `debug` answer as a note, and a refresh chasing it would draw over the
	-- line it lands on.
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_SelfTest"))
	eq("Self-test sends 'selftest'", bench.last("debugact").args.act, "selftest")
	eq("on the selected machine, half of what it runs being about one",
		bench.last("debugact").args.x, 10)
	eq("and asks for no snapshot", bench.last("debug"), nil)

	-- And the disk, which is about a bag: it still carries the selection, because
	-- every command of this module does, and the server ignores it.
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_GiveDisk"))
	eq("Give diagnostics disk sends 'givedisk'",
		bench.last("debugact").args.act, "givedisk")
	eq("and asks for no snapshot", bench.last("debug"), nil)

	-- Teleport is the client's own: in singleplayer it is the vanilla debug call
	-- (IsoGameCharacter.teleportTo), on the MIDDLE of the square, which is what
	-- vanilla's own spawn-point editor does.
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_Teleport"))
	eq("teleporting sends nothing to this module", #bench.sent, 0)
	eq("the player was moved once", #bench.player.teleports, 1)
	eq("to the middle of the machine's square in x",
		bench.player.teleports[1].x, 10.5)
	eq("and in y", bench.player.teleports[1].y, 10.5)
	eq("on its own floor", bench.player.teleports[1].z, 0)

	-- Open terminal needs a computer in the WORLD: a machine whose chunk is away
	-- has nothing to open a window on, and the server would refuse the window
	-- anyway.
	press(bench.buttonNamed("IGUI_CeroSec_Debug_Terminal"))
	eq("with no chunk in there is no terminal to open", #CeroSecTerminal.opened, 0)
	local sawWarning = false
	for i = 1, #CeroSec.logRing do
		if CeroSec.logRing[i].level == CeroSec.LOG_WARN then sawWarning = true end
	end
	check("and the log says why", sawWarning)

	-- With the chunk in, it opens on the tile that is really there.
	local tile = { __class = "IsoObject",
		getSpriteName = function() return CeroSec.SPRITES_ON["S"] end }
	_G.__computers["10,10,0"] = tile
	press(bench.buttonNamed("IGUI_CeroSec_Debug_Terminal"))
	eq("with the chunk in the terminal opens", #CeroSecTerminal.opened, 1)
	eq("on the tile the world really has", CeroSecTerminal.opened[1].computer, tile)
	eq("for the player who asked", CeroSecTerminal.opened[1].player, bench.player)
end

-- With nothing selected the five buttons that act on a machine are greyed, and
-- pressing one does nothing at all: a greyed button IS the answer to "why can I
-- not do this", and a window that only greyed it would still act on it.
do
	local bench = newBench()
	local window = bench.window
	window.cx, window.cy, window.cz = nil, nil, nil
	bench.frame()
	local names = { "TurnOn", "TurnOff", "Teleport", "Terminal", "Dump" }
	for i = 1, #names do
		local made = bench.buttonNamed("IGUI_CeroSec_Debug_" .. names[i])
		eq(names[i] .. " is greyed with nothing selected", made.enabled, false)
	end
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_TurnOn"))
	eq("and pressing it sends nothing", #bench.sent, 0)
	press(bench.buttonNamed("IGUI_CeroSec_Debug_Teleport"))
	eq("nor does it move anybody", #bench.player.teleports, 0)
	-- Refresh still works: the county list is not about a machine.
	press(bench.buttonNamed("IGUI_CeroSec_Debug_Refresh"))
	check("Refresh still asks", bench.last("debug") ~= nil)
end

--
-- 7. The Log tab
--
-- The one tab with no server behind it: CeroSec.logRing is this Lua state's own
-- record of what the mod said.
--

do
	local bench = newBench()
	local window = bench.window
	CeroSec.logRing = {}
	CeroSec.log("an ordinary line")
	CeroSec.log(CeroSec.LOG_WARN, "a careful line")
	CeroSec.log(CeroSec.LOG_ERROR, "a broken line")

	window.panel:activateView("Log")
	bench.forget()
	window:refresh()
	eq("the log tab asks the server for nothing", #bench.sent, 0)

	local list = bench.list()
	eq("all three lines are there", #list.items, 3)
	bench.frame()
	check("the ordinary one is on the glass", bench.painted("an ordinary line"))
	check("and the careful one", bench.painted("a careful line"))
	check("and the broken one", bench.painted("a broken line"))

	-- The filters. Warnings is warnings and nothing else -- a filter that also
	-- passed errors would be a filter that answers a different question.
	press(bench.buttonNamed("Warnings"))
	eq("warnings only", #bench.list().items, 1)
	bench.frame()
	check("and it is the warning", bench.painted("a careful line"))
	check("the ordinary line is gone", not bench.painted("an ordinary line"))
	check("and so is the error", not bench.painted("a broken line"))

	press(bench.buttonNamed("Errors"))
	eq("errors only", #bench.list().items, 1)
	bench.frame()
	check("and it is the error", bench.painted("a broken line"))

	press(bench.buttonNamed("All"))
	eq("and All is all three again", #bench.list().items, 3)

	-- The three filter buttons are on the Log tab and on no other: they mean
	-- nothing beside a list of machines.
	bench.frame()
	eq("the filters are there on the Log tab",
		bench.buttonNamed("Warnings").visible, true)
	window.panel:activateView("Machines")
	bench.frame()
	eq("and not on any other", bench.buttonNamed("Warnings").visible, false)
	eq("while Refresh is on every tab", bench.buttonNamed("IGUI_CeroSec_Debug_Refresh").visible, true)
end

--
-- 8. The clock
--

do
	local bench = newBench()
	local window = bench.window
	eq("one tick handler while it is open", bench.handlerCount(), 1)

	bench.forget()
	bench.tick(CeroSecDebugUI.REFRESH_MS - 1)
	eq("a tick before the interval asks nothing", #bench.sent, 0)
	bench.tick(2)
	eq("and one after it asks once", #bench.sent, 1)
	eq("for the tab in front", bench.sent[1].args.tab, "machines")

	-- And it does not ask again until the next interval: a handler that asked
	-- every tick would be sixty snapshots a second.
	bench.forget()
	bench.tick(1)
	eq("the next tick asks nothing", #bench.sent, 0)
end

--
-- 9. Closing
--
-- The one that matters. A tick handler left registered by a window that is gone
-- is a closure holding a dead window, called sixty times a second for the rest of
-- the session, asking the server for snapshots nobody can see.
--
-- Counted off the EVENT and not off the window: the window's own field would say
-- whatever the window set, and what is under test is whether the game is still
-- holding the handler.
--

do
	local bench = newBench()
	local window = bench.window
	eq("the handler is registered while it is open", bench.handlerCount(), 1)

	window:close()
	eq("closing takes the handler off the event", bench.handlerCount(), 0)
	eq("and the window is off the UI manager", window.onManager, false)
	eq("and it is no longer the instance there is", CeroSecDebugUI.instance, nil)

	-- And a tick that somehow still reaches it asks nothing: the handler is gone,
	-- so this drives what is LEFT registered, which is nothing.
	bench.forget()
	bench.tick(CeroSecDebugUI.REFRESH_MS + 1)
	eq("nothing is asked after it is shut", #bench.sent, 0)

	-- Closing twice is once. A second close that took another handler off would
	-- be taking somebody else's.
	window:close()
	eq("closing twice leaves the event alone", bench.handlerCount(), 0)

	-- A second window opens, and closes the first: one handler, not two.
	local second = CeroSecDebugUI.open(bench.player, 10, 10, 0)
	eq("a second window registers one handler", bench.handlerCount(), 1)
	local third = CeroSecDebugUI.open(bench.player, 12, 10, 0)
	eq("and a third closes the second rather than adding to it",
		bench.handlerCount(), 1)
	eq("the second is shut", second.closing, true)
	eq("and the third is the instance", CeroSecDebugUI.instance, third)
	third:close()
	eq("and shutting it leaves nothing behind", bench.handlerCount(), 0)
end

--
-- 10. The layout, in numbers
--
-- What this block exists for: the tab strip and the column headers were drawn on
-- the SAME ROW, so "ess", "tel", "call", "jobs", "eyes" showed through between the
-- tab labels. A list box with columns draws its header row ABOVE its own top edge,
-- at `0 - self.itemheight` (ISScrollingListBox.lua:553-562), and ISTabPanel:addView
-- puts a view at `self.tabHeight` (:493) -- so a list that IS the view has nowhere
-- to draw its headers but on the strip.
--
-- Every number below is a pixel and not a field: what is asserted is that the four
-- bands of this window (strip, header row, rows, buttons, detail) do not reach into
-- each other, before AND after a resize.
--

local function checkBands(bench, when)
	local window = bench.window
	local panel = window.panel
	local L = window.numbers

	for i = 1, #window.views do
		local view = window.views[i]
		local list = window.lists[i]
		check(when .. ": view " .. i .. " starts at or below the tab strip",
			view.y >= panel.tabHeight)
		-- The header strip the LIST BOX draws, in the view's own coordinates: one
		-- item height, ending flush against the first row -- which is why the room
		-- for it has to be reserved above the list and cannot be found later.
		local headerTop = view.y + list.y - list.itemheight
		local headerBottom = view.y + list.y
		check(when .. ": the header row of list " .. i .. " is clear of the strip",
			headerTop >= panel.tabHeight)
		local firstRowText = view.y + list.y + (list.itemPadY or 0)
		check(when .. ": and it ends above the first row's own text",
			headerBottom < firstRowText)
		check(when .. ": list " .. i .. " ends inside the panel",
			view.y + list.y + list.height <= panel.height)
		check(when .. ": and it is given the height that is left",
			list.height > 0)
	end

	local list = window.lists[1]
	local listBottom = panel.y + window.views[1].y + list.y + list.height
	local buttonsTop = window.buttons[1].button.y
	check(when .. ": the buttons are under the list", buttonsTop >= listBottom)

	-- TWO ROWS, and every button on exactly one of them. The second row is the
	-- admin's and the tester's own eight, which on the one row this window shipped
	-- with would have been seventeen buttons and a row wider than a screen -- so what
	-- has to be asserted is not "one row" any more but that each button sits on the
	-- row it was given, that the rows do not overlap, and that the block under them
	-- is under the LAST of them.
	local rows = {}
	for i = 1, #window.buttons do
		local entry = window.buttons[i]
		local at = entry.row or 1
		check(when .. ": button " .. i .. " names a row that exists",
			at >= 1 and at <= #L.rowY)
		eq(when .. ": button " .. i .. " is on row " .. at,
			entry.button.y, L.rowY[at])
		rows[at] = true
	end
	check(when .. ": both rows are used", rows[1] == true and rows[2] == true)
	eq(when .. ": the first row is where the buttons begin", L.rowY[1], buttonsTop)
	for i = 2, #L.rowY do
		check(when .. ": row " .. i .. " is clear of the one above it",
			L.rowY[i] >= L.rowY[i - 1] + L.buttonH)
	end
	-- And the two widgets that are not buttons are on the second row with them.
	eq(when .. ": the login box is on the second row", window.loginEntry.y, L.rowY[2])
	eq(when .. ": and so is the disk list", window.diskCombo.y, L.rowY[2])

	local lastRow = L.rowY[#L.rowY]
	check(when .. ": and the detail block is under the LAST button row",
		L.infoY >= lastRow + L.buttonH)
	check(when .. ": with the whole of it above the resize widget",
		L.infoY + L.infoH <= window.height - L.rh)
end

do
	local bench = newBench()
	local window = bench.window

	-- The window round the panel, which is ISEntitiesDebugWindow's own arithmetic
	-- (:33-52): the title bar, then a border, then the panel.
	eq("the panel is a border below the title bar", window.panel.y,
		window.numbers.th + 10)
	eq("and a border in from the left", window.panel.x, 10)
	eq("as wide as the window less both borders", window.panel.width,
		window.width - 20)

	-- AND THE SECOND BUTTON ROW DOES NOT COME OUT OF THE LIST. The opening height is
	-- worked out in measure() and has to count EVERY button row; a height that had not
	-- heard of the second would open the window with a list one whole button row
	-- shorter -- which every band assertion above is perfectly happy with, because the
	-- bands still do not overlap, and which nothing else here would notice.
	--
	-- The floor is eighteen rows and not the twenty the height aims at: the aim is
	-- worked out from (FONT_H + 6) and the list's itemheight is its own number, so on
	-- this bench's font the twenty land in eighteen and a bit. What the eighteen
	-- guards is one whole button row, which is worth four of them here.
	check("the window opens with the list it is meant to have (" ..
		window.lists[1].height .. " px, " .. window.lists[1].itemheight .. " a row)",
		window.lists[1].height >= window.lists[1].itemheight * 18)

	checkBands(bench, "as opened")

	-- And after the corner is dragged. Same function, same numbers: two copies of
	-- this arithmetic is how the header row ended up on the strip.
	window:setWidth(1100)
	window:setHeight(760)
	window:onResize()
	eq("the panel followed the width", window.panel.width, 1080)
	checkBands(bench, "after a resize")
	for i = 1, #window.views do
		eq("view " .. i .. " followed the width too", window.views[i].width, 1080)
		eq("and so did its list", window.lists[i].width, 1080)
	end

	-- Smaller than it opened, as well: a window dragged in is still a window whose
	-- bands do not overlap.
	window:setWidth(700)
	window:setHeight(560)
	window:onResize()
	checkBands(bench, "after being dragged in")

	-- And at the floor it sets for the resize widget, which is the smallest it can
	-- be dragged to: ISResizeWidget's own default is nothing at all, so the floor
	-- has to be this window's own or the bands go through each other.
	check("it has a floor to drag to", window.minimumHeight ~= nil)
	check("and a width to go with it", window.minimumWidth ~= nil)
	window:setWidth(window.minimumWidth)
	window:setHeight(window.minimumHeight)
	window:onResize()
	checkBands(bench, "at its floor")
	eq("and at the floor the list is exactly one row tall",
		window.lists[1].height, window.lists[1].itemheight)
	check("with every button still inside it",
		window.buttons[#window.buttons].button.x +
			window.buttons[#window.buttons].button.width <= window.width)
end

--
-- 11. The columns
--
-- Measured off the header and off the widest cell, never overlapping, and the last
-- one absorbing what is left. A column drawn at the same offset as its neighbour is
-- the "call" that was on top of "jobs".
--

do
	local bench = newBench()
	local window = bench.window
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot(window.token, "machines", machineRows(), { "machines: 2 of 2" }))
	local list = bench.list()
	local spec = CeroSecDebugUI.TABS[1]

	eq("every column has a width", #list.colW, #spec.columns)
	for k = 1, #list.colX do
		check("column " .. k .. " has a width", list.colW[k] > 0)
		if k > 1 then
			eq("column " .. k .. " starts exactly where the one before it ends",
				list.colX[k], list.colX[k - 1] + list.colW[k - 1])
		end
		-- Room for its own header, measured the way the window measures it.
		check("column " .. k .. " has room for the word over it",
			list.colW[k] - CELL_PAD - CELL_GAP >= adv(spec.columns[k][1]))
		-- And for the widest cell under it, which is what a measured column is for.
		local widest = 0
		local rows = machineRows()
		for r = 1, #rows do
			local at = adv(rows[r].c[k])
			if at > widest then widest = at end
		end
		check("and for the widest cell in it",
			list.colW[k] - CELL_PAD - CELL_GAP >= widest)
	end
	-- The list box draws the header row and the rules at these very offsets, so
	-- they have to be the same numbers.
	for k = 1, #list.colX do
		eq("the list box's own column " .. k .. " is at the same offset",
			list.columns[k].size, list.colX[k])
	end
	eq("the last column absorbs the rest of the width",
		list.colX[#list.colX] + list.colW[#list.colW], list:getWidth())

	-- Every cell lands inside its own column. Read off what was PAINTED: the x it
	-- was drawn at names the column, and the ink has to end before the next one
	-- starts.
	bench.frame()
	local cells = 0
	for i = 1, #list.painted do
		local at = list.painted[i]
		local k = bench.columnAt(at.x)
		check("the cell '" .. tostring(at.text) .. "' is in a column", k ~= -1)
		if k ~= -1 then
			cells = cells + 1
			check("and its ink ends before column " .. (k + 1) .. " starts",
				at.x + adv(at.text) <= list.colX[k] + list.colW[k])
		end
	end
	check("and there were cells to check", cells >= 11)
end

-- A cell far too long for any column: the columns are squeezed to fit the window,
-- every one keeps its floor, and the cell that no longer fits is CUT and not drawn
-- over its neighbour.
do
	local bench = newBench()
	local window = bench.window
	local rows = machineRows()
	rows[1].c[6] = string.rep("verylonghostname", 20)
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot(window.token, "machines", rows, { "machines: 2 of 2" }))
	local list = bench.list()

	eq("the table still ends at the edge of the list",
		list.colX[#list.colX] + list.colW[#list.colW], list:getWidth())
	local floor = CELL_PAD + adv("nnnn") + CELL_GAP
	for k = 1, #list.colW do
		check("column " .. k .. " is not squeezed below its floor",
			list.colW[k] >= floor)
		if k > 1 then
			eq("and column " .. k .. " still starts where the one before ends",
				list.colX[k], list.colX[k - 1] + list.colW[k - 1])
		end
	end

	bench.frame()
	local cut = nil
	for i = 1, #list.painted do
		local at = list.painted[i]
		local k = bench.columnAt(at.x)
		if k ~= -1 then
			check("nothing is painted past its column (" .. tostring(at.text) .. ")",
				at.x + adv(at.text) <= list.colX[k] + list.colW[k])
			-- The first row's own host cell, which is the long one: the second row's
			-- is "shed" and fits anywhere.
			if k == 6 and cut == nil then cut = at.text end
		end
	end
	check("the long cell was drawn", cut ~= nil)
	check("and it was cut", cut ~= rows[1].c[6])
	eq("with the mark the rest of the mod cuts with",
		string.sub(cut, -1), "~")
end

--
-- 12. Which machines are shown, and how many of how many
--

do
	local bench = newBench()
	local window = bench.window
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot(window.token, "machines", countyRows(), { "machines: 3 of 3" }))

	-- Used only, to begin with: the two computers a chunk brought in and nobody
	-- ever touched are not what somebody opened this window to look at.
	eq("only the machines in use are listed", #bench.list().items, 1)
	eq("and it is the one in use", bench.list().items[1].item.x, 10)
	bench.frame()
	check("the count says how many of how many", bench.painted("showing 1 of 3"))
	check("and which way the filter is set", bench.painted("used only"))

	-- The button offers the other way, and pressing it shows the county.
	local made = bench.buttonNamed("IGUI_CeroSec_Debug_ShowAll")
	check("the filter button offers all of them", made ~= nil)
	bench.forget()
	press(made)
	eq("all three are listed", #bench.list().items, 3)
	eq("and it asked the server for nothing to do it", #bench.sent, 0)
	bench.frame()
	check("the count moved with it", bench.painted("showing 3 of 3"))
	check("and the mode with it", bench.painted("all machines"))
	check("the button now offers the way back",
		bench.buttonNamed("IGUI_CeroSec_Debug_ShowUsed") ~= nil)

	-- A refresh does not undo it: the filter is the window's, like which tab is in
	-- front.
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot(window.token, "machines", countyRows(), { "machines: 3 of 3" }))
	eq("a new snapshot is filtered the same way", #bench.list().items, 3)

	-- And it is the Machines tab's button and no other's.
	bench.frame()
	eq("the filter is there on the Machines tab",
		bench.buttonNamed("IGUI_CeroSec_Debug_ShowUsed").visible, true)
	window.panel:activateView("Files")
	bench.frame()
	eq("and not on any other",
		bench.buttonNamed("IGUI_CeroSec_Debug_ShowUsed").visible, false)
end

-- The cursor stays on the machine it was on, and not on the row number it was on.
--
-- THREE machines and a new order that puts the clicked one in the MIDDLE, because
-- ISScrollingListBox:clear() leaves the selection at 1: a bench whose answer was 1
-- would be a bench that passes for a window that keeps nothing at all.
do
	local bench = newBench()
	local window = bench.window
	local three = machineRows()
	three[3] = { c = { "12,10,0", "W", "on", "here", "yes", "gate", "10.4.17.2",
		"555-0143", "-", "0", "0" }, x = 12, y = 10, z = 0, used = true }
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot(window.token, "machines", three))
	bench.list():clickRow(3)
	eq("the third machine is selected", window.cx, 12)
	eq("and the cursor is on its row", bench.list().selected, 3)

	-- The same three, in the order a county answers them the moment a machine is
	-- adopted or dropped above one of them.
	local order = { three[1], three[3], three[2] }
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot(window.token, "machines", order))
	eq("all three are still listed", #bench.list().items, 3)
	eq("and the cursor followed the MACHINE, not the row number",
		bench.list().selected, 2)
	eq("which is the machine that was clicked",
		bench.list().items[bench.list().selected].item.x, 12)
end

--
-- 13. Why a button cannot be pressed
--
-- The window opened in play had "Turn on" enabled on a machine whose chunk was
-- away. The button was pressed; the server refused, because the wire is asked of a square
-- and there was nobody to ask; and nothing at all happened on the glass.
--

do
	local bench = newBench()
	local window = bench.window
	CeroSecDebugUI.onServerAnswer("debug", selected(window.token, {
		canTurnOn = false, canTurnOff = true, on = false, loaded = false,
		reason = "its chunk is away, so there is nobody to ask about the wire" ..
			" -- teleport to it first" }))
	bench.frame()

	eq("Turn on is greyed when the server says it cannot",
		bench.buttonNamed("IGUI_CeroSec_Debug_TurnOn").enabled, false)
	eq("Turn off is not, because turning off asks the world nothing",
		bench.buttonNamed("IGUI_CeroSec_Debug_TurnOff").enabled, true)
	eq("Teleport is never greyed on a selected machine",
		bench.buttonNamed("IGUI_CeroSec_Debug_Teleport").enabled, true)
	eq("Open terminal is greyed with no chunk in",
		bench.buttonNamed("IGUI_CeroSec_Debug_Terminal").enabled, false)
	check("and the first line under the list says why in the server's words",
		bench.painted("nobody to ask about the wire"))

	-- Pressing it anyway asks nothing and still says why: a window that only greyed
	-- the button would go on sending.
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_TurnOn"))
	eq("a press the window knows cannot work sends nothing", #bench.sent, 0)
	bench.frame()
	check("and it says so", bench.painted("cannot turn on"))

	-- A refusal that comes back ON THE WIRE is shown, never swallowed -- and it
	-- does not empty the lists on the way past.
	CeroSecDebugUI.onServerAnswer("debug", { token = window.token,
		error = "cannot turn on: there is no wire at its square",
		x = 10, y = 10, z = 0 })
	bench.frame()
	check("a refusal from the server is on the glass",
		bench.painted("no wire at its square"))
	eq("and the list it arrived over is untouched", #bench.list().items, 2)

	-- Somebody else's refusal is nobody's business here.
	local before = window.refusal
	CeroSecDebugUI.onServerAnswer("debug", { token = "dbg-somebody-else",
		error = "cannot turn on: some other window's machine" })
	eq("a refusal carrying another window's token is dropped", window.refusal, before)
end

-- A machine that CAN come on: nothing is greyed and there is nothing to say.
do
	local bench = newBench()
	local window = bench.window
	_G.__computers["10,10,0"] = { __class = "IsoObject",
		getSpriteName = function() return CeroSec.SPRITES_ON["S"] end }
	CeroSecDebugUI.onServerAnswer("debug", selected(window.token, {
		canTurnOn = true, canTurnOff = false, on = false, loaded = true }))
	bench.frame()
	eq("Turn on is usable", bench.buttonNamed("IGUI_CeroSec_Debug_TurnOn").enabled, true)
	eq("Turn off is greyed on a machine that is off",
		bench.buttonNamed("IGUI_CeroSec_Debug_TurnOff").enabled, false)
	eq("and the terminal is greyed on a machine that is off",
		bench.buttonNamed("IGUI_CeroSec_Debug_Terminal").enabled, false)
	check("the reason line says which of them is why",
		bench.painted("cannot open the terminal: it is off"))

	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_TurnOn"))
	eq("and the press goes out", bench.last("debugact").args.act, "on")

	-- On, in the world and beside the player: the terminal opens.
	CeroSecDebugUI.onServerAnswer("debug", selected(window.token, {
		canTurnOn = false, canTurnOff = true, on = true, loaded = true,
		reason = "it is already on" }))
	bench.frame()
	eq("with it on and the player at it the terminal is offered",
		bench.buttonNamed("IGUI_CeroSec_Debug_Terminal").enabled, true)
	eq("and nothing is greyed for a reason worth printing",
		window:reasonLine(), nil)

	-- Two squares away is not adjacent, which is the server's own answer.
	bench.player.x, bench.player.y = 14.5, 10.5
	bench.frame()
	eq("a player who walked off cannot open it",
		bench.buttonNamed("IGUI_CeroSec_Debug_Terminal").enabled, false)
	check("and is told why", bench.painted("not standing at it"))
	press(bench.buttonNamed("IGUI_CeroSec_Debug_Terminal"))
	eq("and pressing it opens nothing", #CeroSecTerminal.opened, 0)
end

--
-- 14. Reset machine, and the two clicks in front of it
--
-- The one act in this window that cannot be undone: the selected machine's whole
-- filesystem, thrown away so that its first power-on can happen a second time
-- (docs/DEBUG.md, and SCeroSecObject:resetMachine for what the server does with
-- it). What this block is about is the GUARD in front of it, because there is no
-- dialog: the first click arms and says what is about to happen to which machine,
-- the second click sends, and the arming expires by itself.
--

do
	local bench = newBench()
	local window = bench.window
	-- An off machine in the world, which is the one state a reset is allowed in.
	CeroSecDebugUI.onServerAnswer("debug", selected(window.token, {
		canTurnOn = true, canTurnOff = false, on = false, loaded = true,
		canReset = true }))
	bench.frame()
	local reset = bench.buttonNamed("IGUI_CeroSec_Debug_Reset")
	check("there is a Reset machine button", reset ~= nil)
	eq("and it comes after Dump state",
		window.buttons[6].button.title, "IGUI_CeroSec_Debug_Dump")
	eq("as the button after it", window.buttons[7].button.title,
		"IGUI_CeroSec_Debug_Reset")
	-- And the two that were appended after it are after it and in their own order:
	-- the destructive one leads the three, and a button that moved along the row
	-- would be a button somebody presses by mistake.
	eq("with Self-test next", window.buttons[8].button.title,
		"IGUI_CeroSec_Debug_SelfTest")
	eq("and the disk last of the three", window.buttons[9].button.title,
		"IGUI_CeroSec_Debug_GiveDisk")
	eq("it is usable on a machine that is off", reset.enabled, true)

	-- AND THEY ARE ALL ON THE GLASS. The opening width comes off the widest tab's
	-- nominal columns and the button row comes off the words on the buttons: a
	-- seventh button is what first made the two disagree, "Give diagnostics disk"
	-- is the widest label on the row of nine now, and a button hanging over the
	-- window's own right edge is a button somebody has to drag the corner to find.
	local widest = 0
	for i = 1, #window.buttons do
		local made = window.buttons[i].button
		if made.x + made.width > widest then widest = made.x + made.width end
	end
	check("every button is inside the window it opened at (" .. widest .. " of " ..
		window:getWidth() .. ")", widest <= window:getWidth())
	-- And the list under it went with the width, because there is one arrangement
	-- and not two.
	eq("and the list was laid out at that width", window.lists[1].width,
		window:getWidth() - 20)

	-- ONE CLICK SENDS NOTHING. It arms, and the line under the list says what the
	-- next click will do and to which machine -- by its hostname, off its own row.
	bench.forget()
	press(reset)
	eq("the first click sends nothing at all", #bench.sent, 0)
	bench.frame()
	check("and says what the next one will do", bench.painted("Click again to reset"))
	check("naming the machine by its hostname", bench.painted("office"))
	check("and where it stands", bench.painted("10,10,0"))

	-- THE SECOND CLICK SENDS IT, and asks for the tab again so the row is redrawn.
	bench.forget()
	press(reset)
	local act = bench.last("debugact")
	check("the second click sends an act", act ~= nil)
	eq("which is 'reset'", act.args.act, "reset")
	eq("on the selected machine", act.args.x, 10)
	eq("and its y", act.args.y, 10)
	eq("under this window's own token", act.args.token, window.token)
	check("and it asks for the tab again afterwards", bench.last("debug") ~= nil)

	-- And it is armed no more: a third click arms again rather than resetting again.
	bench.forget()
	press(reset)
	eq("the click after it arms instead of sending", #bench.sent, 0)
end

-- THE ARMING EXPIRES. A guard that waits for ever is a guard that is not there:
-- five seconds later the first click is forgotten and the next one arms again.
do
	local bench = newBench()
	local window = bench.window
	CeroSecDebugUI.onServerAnswer("debug", selected(window.token, {
		canTurnOn = true, canTurnOff = false, on = false, loaded = true,
		canReset = true }))
	local reset = bench.buttonNamed("IGUI_CeroSec_Debug_Reset")

	press(reset)
	check("it is armed", window:resetArmed())
	-- Just inside the five seconds it is still armed, and the sentence is still up.
	_G.__now = _G.__now + CeroSecDebugUI.ARM_MS - 1
	bench.frame()
	check("a moment before the five seconds it still is", window:resetArmed())
	check("and still says so", bench.painted("Click again to reset"))
	-- And one millisecond past them it is not.
	_G.__now = _G.__now + 1
	bench.frame()
	check("a moment after them it is not", not window:resetArmed())
	check("and the line is gone with it", not bench.painted("Click again to reset"))
	bench.forget()
	press(reset)
	eq("so the click that comes late arms and sends nothing", #bench.sent, 0)

	-- ARMED FOR ONE MACHINE. A click that armed one row and a click that fired on
	-- another would be a reset of a computer nobody aimed at.
	check("armed again by that late click", window:resetArmed())
	bench.list():clickRow(2)
	check("and moving to another machine disarms it", not window:resetArmed())
	bench.forget()
	press(reset)
	eq("so the first click on the new row only arms", #bench.sent, 0)
end

-- A MACHINE THAT IS ON is not reset: the button is greyed on the server's own
-- answer, pressing it anyway sends nothing and says why, and an arming that was
-- standing is dropped -- a machine somebody switched on between the two clicks
-- must not be reset by the second one.
do
	local bench = newBench()
	local window = bench.window
	CeroSecDebugUI.onServerAnswer("debug", selected(window.token, {
		canTurnOn = true, canTurnOff = false, on = false, loaded = true,
		canReset = true }))
	local reset = bench.buttonNamed("IGUI_CeroSec_Debug_Reset")
	press(reset)
	check("armed on a machine that was off", window:resetArmed())

	CeroSecDebugUI.onServerAnswer("debug", selected(window.token, {
		canTurnOn = false, canTurnOff = true, on = true, loaded = true,
		reason = "it is already on",
		canReset = false, resetReason = "it is on -- switch it off first" }))
	bench.frame()
	eq("Reset machine is greyed on a machine that is on", reset.enabled, false)

	bench.forget()
	press(reset)
	eq("and the armed click that follows sends nothing", #bench.sent, 0)
	check("the arming is dropped", not window:resetArmed())
	bench.frame()
	check("and the line says why in the server's own words",
		bench.painted("switch it off first"))

	-- A refusal that comes back on the WIRE is shown like any other.
	CeroSecDebugUI.onServerAnswer("debug", { token = window.token,
		error = "cannot reset: it is on -- switch it off first",
		x = 10, y = 10, z = 0 })
	bench.frame()
	check("a refusal from the server is on the glass", bench.painted("cannot reset"))
end

-- With nothing selected it is greyed like the others, and a machine the reset has
-- just emptied does not vanish out of the list under the cursor: `os` gone is
-- `used` gone, and the "used only" filter would take the row away at the very
-- moment its reader needs it.
do
	local bench = newBench()
	local window = bench.window
	window.cx, window.cy, window.cz = nil, nil, nil
	bench.frame()
	eq("Reset machine is greyed with nothing selected",
		bench.buttonNamed("IGUI_CeroSec_Debug_Reset").enabled, false)
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_Reset"))
	eq("and pressing it sends nothing", #bench.sent, 0)

	-- The county as it answers after a reset: the selected machine is one nobody has
	-- used any more.
	window.cx, window.cy, window.cz = 300, 220, 0
	local rows = countyRows()
	CeroSecDebugUI.onServerAnswer("debug", snapshot(window.token, "machines", rows))
	eq("the filter is still on used only", window.usedOnly, true)
	local shown = window.lists[1].debugRows
	local mine = false
	for i = 1, #shown do
		if shown[i].x == 300 then mine = true end
	end
	check("and the machine that was just reset is still on the glass", mine)
	eq("with the used ones beside it", #shown, 2)
	-- While the OTHER untouched machine is still filtered away: the exception is the
	-- cursor's row and not the filter giving up.
	local other = false
	for i = 1, #shown do
		if shown[i].x == 301 then other = true end
	end
	check("and the one nobody is looking at is not", not other)
end

--
-- 15. The verdict on the line under the list
--
-- The self-test answers a `note` and not an `error`, and the two are kept apart
-- on purpose: a reader has to be able to tell "PASS 138 FAIL 0" from "cannot turn
-- on", and a refusal outranks a verdict on the one line there is.
--
do
	local bench = newBench()
	local window = bench.window
	CeroSecDebugUI.onServerAnswer("debug", selected(window.token, {
		canTurnOn = false, canTurnOff = true, on = true, loaded = true }))
	bench.frame()

	CeroSecDebugUI.onServerAnswer("debug",
		{ token = window.token, note = "selftest: PASS 138 FAIL 0" })
	bench.frame()
	eq("a note goes on the reason line", window:reasonLine(),
		"selftest: PASS 138 FAIL 0")
	check("and is drawn there", bench.painted("selftest: PASS 138 FAIL 0"))
	eq("and it is not a refusal", window.refusal, nil)
	-- And no list is emptied by it: a note carries no tab, exactly as a refusal
	-- does not.
	check("the machine list is still there", #(bench.list().debugRows or {}) > 0)

	-- A refusal after it wins the line, because a machine that cannot be switched
	-- on is a thing the reader needs now.
	CeroSecDebugUI.onServerAnswer("debug",
		{ token = window.token, error = "cannot turn on: its chunk is away" })
	bench.frame()
	eq("a refusal outranks a verdict", window:reasonLine(),
		"cannot turn on: its chunk is away")
	eq("and takes the verdict with it", window.notice, nil)

	-- And a note after THAT takes the refusal away, or the window would keep
	-- showing a refusal the reader has already dealt with.
	CeroSecDebugUI.onServerAnswer("debug",
		{ token = window.token, note = "selftest: PASS 138 FAIL 1" })
	bench.frame()
	eq("and a verdict after a refusal replaces it", window:reasonLine(),
		"selftest: PASS 138 FAIL 1")

	-- Another window's note is not this window's.
	CeroSecDebugUI.onServerAnswer("debug",
		{ token = "dbg-somebody-else", note = "selftest: PASS 1 FAIL 999" })
	eq("a note carrying another window's token is dropped", window:reasonLine(),
		"selftest: PASS 138 FAIL 1")

	-- Clicking a different machine takes it away: half of what the self-test
	-- reported was about the machine that WAS selected.
	window:onRowClicked({ x = 12, y = 10, z = 0 })
	eq("and selecting another machine drops it", window.notice, nil)
end

--
-- 16. The second row: the admin's and the tester's eight
--
-- Eight acts a server owner or somebody walking the checklist wants: the two papers,
-- who is on the machine, a password taken off, any disk of the catalogue, root at the
-- glass, cron's minute by hand, and the automation's walk run to the end. What this
-- block is for is the three things the WINDOW decides about them -- which tab they
-- are on, what goes out on the wire, and whether a press that cannot work is sent
-- anyway -- and nothing about what the server does with them, which is
-- tests/window_test.lua's.
--

-- The eight, as the label the button wears and the act it sends.
local ACTS = {
	{ "RootNote", "rootnote", "canRootNote", "rootNoteReason" },
	{ "StaffNote", "staffnote", "canStaffNote", "staffNoteReason" },
	{ "Accounts", "accounts", "canAccounts", "accountsReason" },
	{ "ClearPass", "clearpass", "canClearPass", "clearPassReason" },
	{ "RootLogin", "rootlogin", "canRootLogin", "rootLoginReason" },
	{ "CronNow", "cronnow", "canCronNow", "cronNowReason" },
	{ "ForceWire", "forcewire", "canForceWire", "forceWireReason" },
}

do
	local bench = newBench()
	local window = bench.window

	-- ON THE MACHINE TAB AND NOWHERE ELSE. All eight are about the machine that is
	-- selected and the Machines tab is where one is selected, so a reader looking at a
	-- filesystem is not offered a row of buttons whose subject is off screen.
	bench.frame()
	for i = 1, #ACTS do
		local made = bench.buttonNamed("IGUI_CeroSec_Debug_" .. ACTS[i][1])
		check(ACTS[i][1] .. " is on the row", made ~= nil)
		eq("and it is there on the Machines tab", made.visible, true)
	end
	eq("Give disk is on the row too",
		bench.buttonNamed("IGUI_CeroSec_Debug_GiveAnyDisk") ~= nil, true)
	eq("the login box is there", window.loginEntry.visible, true)
	eq("and the disk list", window.diskCombo.visible, true)

	window.panel:activateView("Files")
	bench.frame()
	for i = 1, #ACTS do
		eq(ACTS[i][1] .. " is gone on another tab",
			bench.buttonNamed("IGUI_CeroSec_Debug_" .. ACTS[i][1]).visible, false)
	end
	eq("and so is the login box", window.loginEntry.visible, false)
	eq("and the disk list", window.diskCombo.visible, false)
	-- While the buttons that are about every tab stay.
	eq("Refresh is on every tab",
		bench.buttonNamed("IGUI_CeroSec_Debug_Refresh").visible, true)
	window.panel:activateView("Machines")
end

-- What each of them puts on the wire.
do
	local bench = newBench()
	local window = bench.window
	for i = 1, #ACTS do
		bench.forget()
		press(bench.buttonNamed("IGUI_CeroSec_Debug_" .. ACTS[i][1]))
		local act = bench.last("debugact")
		check(ACTS[i][1] .. " sends an act", act ~= nil)
		eq("which is '" .. ACTS[i][2] .. "'", act.args.act, ACTS[i][2])
		eq("on the selected machine", act.args.x, 10)
		eq("and on its own floor", act.args.z, 0)
		eq("under this window's token", act.args.token, window.token)
		-- None of them asks for a snapshot afterwards: what each has to say comes back
		-- as a note on the one line there is, and a refresh chasing it would draw over
		-- the line it lands on.
		eq("and it asks for no snapshot", bench.last("debug"), nil)
	end
end

-- The login box, and what Clear password carries.
do
	local bench = newBench()
	local window = bench.window
	eq("the box opens on root", window.loginEntry:getInternalText(), "root")

	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_ClearPass"))
	eq("so the first press names root", bench.last("debugact").args.login, "root")

	-- A name typed in travels as it is typed: the window judges no name, because the
	-- server holds it to the machine's own rule and answers.
	window.loginEntry:setText("rmiller")
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_ClearPass"))
	eq("and a typed one travels as it was typed",
		bench.last("debugact").args.login, "rmiller")

	-- An empty box is root again and never an empty login: a command carrying "" is a
	-- refusal the server has to answer for nothing.
	window.loginEntry:setText("")
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_ClearPass"))
	eq("an empty box falls back to root",
		bench.last("debugact").args.login, "root")

	-- And the box cannot hold a login longer than a passwd line could carry.
	window.loginEntry:setText(string.rep("a", CeroSecDebugUI.LOGIN_MAX + 8))
	eq("the box is capped at the machine's own name length",
		#window.loginEntry:getInternalText(), CeroSecDebugUI.LOGIN_MAX)
end

-- The disk list, built off the CATALOGUE and sending the id and not the words.
do
	local bench = newBench()
	local window = bench.window
	eq("there is one option per entry of the catalogue",
		window.diskCombo:getOptionCount(), #CeroSecContent.DISKS)
	eq("and the first is the catalogue's first",
		window.diskCombo:getOptionData(1), CeroSecContent.DISKS[1].id)

	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_GiveAnyDisk"))
	local act = bench.last("debugact")
	eq("Give disk sends 'anydisk'", act.args.act, "anydisk")
	eq("naming the entry the list is on", act.args.disk, CeroSecContent.DISKS[1].id)

	window.diskCombo:setSelected(3)
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_GiveAnyDisk"))
	eq("and it follows the list", bench.last("debugact").args.disk,
		CeroSecContent.DISKS[3].id)

	-- No machine is wanted: it is about a bag, exactly as the diagnostics disk is.
	window.cx, window.cy, window.cz = nil, nil, nil
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_GiveAnyDisk"))
	eq("with nothing selected it still asks",
		bench.last("debugact").args.act, "anydisk")
end

-- Greyed on the server's own answer, one act at a time -- and a press that the window
-- already knows cannot work is not sent, it is explained.
do
	for i = 1, #ACTS do
		local bench = newBench()
		local window = bench.window
		local spec = ACTS[i]
		local fields = { canTurnOn = true, canTurnOff = true, on = true, loaded = true }
		-- Every one of the seven said YES except the one under test, so what is
		-- asserted is that this act's own field greys this act's own button: a window
		-- that read one field for all of them would be green on a table like this.
		for k = 1, #ACTS do
			fields[ACTS[k][3]] = true
		end
		fields[spec[3]] = false
		fields[spec[4]] = "the bench's own reason for " .. spec[1]
		CeroSecDebugUI.onServerAnswer("debug", selected(window.token, fields))
		bench.frame()

		eq(spec[1] .. " is greyed when the server says it cannot",
			bench.buttonNamed("IGUI_CeroSec_Debug_" .. spec[1]).enabled, false)
		for k = 1, #ACTS do
			if k ~= i then
				eq("and " .. ACTS[k][1] .. " is not",
					bench.buttonNamed("IGUI_CeroSec_Debug_" .. ACTS[k][1]).enabled, true)
			end
		end

		bench.forget()
		press(bench.buttonNamed("IGUI_CeroSec_Debug_" .. spec[1]))
		eq("a press it knows cannot work sends nothing", #bench.sent, 0)
		bench.frame()
		check("and the line under the list carries the SERVER's own reason",
			bench.painted("the bench's own reason for " .. spec[1]))
	end
end

-- With nothing selected all seven are greyed and press to nothing, exactly as the
-- five above them are.
do
	local bench = newBench()
	local window = bench.window
	window.cx, window.cy, window.cz = nil, nil, nil
	bench.frame()
	for i = 1, #ACTS do
		eq(ACTS[i][1] .. " is greyed with nothing selected",
			bench.buttonNamed("IGUI_CeroSec_Debug_" .. ACTS[i][1]).enabled, false)
		bench.forget()
		press(bench.buttonNamed("IGUI_CeroSec_Debug_" .. ACTS[i][1]))
		eq("and pressing it sends nothing", #bench.sent, 0)
	end
	eq("and the login box cannot be typed in", window.loginEntry.editable, false)
end

-- Login as root opens the glass as well, through the terminal's own path: it is a
-- shortcut past the keyboard and past nothing else.
do
	local bench = newBench()
	local window = bench.window
	local tile = { __class = "IsoObject",
		getSpriteName = function() return CeroSec.SPRITES_ON["S"] end }
	_G.__computers["10,10,0"] = tile
	CeroSecDebugUI.onServerAnswer("debug", selected(window.token, {
		canTurnOn = false, canTurnOff = true, on = true, loaded = true,
		canRootLogin = true }))
	bench.forget()
	press(bench.buttonNamed("IGUI_CeroSec_Debug_RootLogin"))
	eq("the act went out", bench.last("debugact").args.act, "rootlogin")
	eq("and the terminal was opened on the tile the world has",
		#CeroSecTerminal.opened, 1)
	eq("for the player who asked", CeroSecTerminal.opened[1].player, bench.player)

	-- Refused, and the window opens nothing: a terminal on a machine whose login the
	-- server would not do is a window showing a login prompt and a lie on the line
	-- under the list.
	local other = newBench()
	CeroSecDebugUI.onServerAnswer("debug", selected(other.window.token, {
		canRootLogin = false, rootLoginReason = "somebody is already logged in as bob",
		on = true, loaded = true }))
	_G.__computers["10,10,0"] = tile
	other.frame()
	press(other.buttonNamed("IGUI_CeroSec_Debug_RootLogin"))
	eq("a refused root login opens no terminal", #CeroSecTerminal.opened, 0)
	other.frame()
	check("and says whose session is in the way",
		other.painted("already logged in as bob"))
end

print("debug_ui_test: " .. count .. " checks passed")
