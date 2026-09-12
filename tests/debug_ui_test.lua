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
	for i = 1, #window.buttons do
		eq(when .. ": button " .. i .. " is on the same row",
			window.buttons[i].button.y, buttonsTop)
	end
	check(when .. ": and the detail block is under the buttons",
		L.infoY >= buttonsTop + L.buttonH)
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
do
	local bench = newBench()
	local window = bench.window
	CeroSecDebugUI.onServerAnswer("debug",
		snapshot(window.token, "machines", machineRows()))
	bench.list():clickRow(2)
	eq("the second machine is selected", window.cx, 60)

	-- The same two machines, the other way round, which is what a county answers
	-- the moment one of them is adopted or dropped.
	local rows = machineRows()
	local swap = { rows[2], rows[1] }
	CeroSecDebugUI.onServerAnswer("debug", snapshot(window.token, "machines", swap))
	eq("both are still listed", #bench.list().items, 2)
	eq("and the cursor followed the MACHINE, not the row number",
		bench.list().selected, 1)
	eq("which is the machine that was clicked",
		bench.list().items[bench.list().selected].item.x, 60)
end

--
-- 13. Why a button cannot be pressed
--
-- The window Mathieu opened had "Turn on" enabled on a machine whose chunk was
-- away. He pressed it; the server refused, because the wire is asked of a square
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

print("debug_ui_test: " .. count .. " checks passed")
