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
	player.teleportTo = function(_, x, y, z)
		player.teleports[#player.teleports + 1] = { x = x, y = y, z = z }
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

local function machineRows()
	return {
		{ c = { "10,10,0", "S", "on", "here", "yes", "office", "10.4.17.1",
			"555-0142", "-", "0", "1" }, x = 10, y = 10, z = 0 },
		{ c = { "60,60,0", "E", "on", "away", "-", "shed", "10.9.44.1",
			"555-0911", "KE4QWZ", "2", "0" }, x = 60, y = 60, z = 0 },
	}
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

print("debug_ui_test: " .. count .. " checks passed")
