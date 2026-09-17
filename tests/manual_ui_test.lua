-- The manual: the book laid out, and the window that turns it. Run from the
-- repo root:
--   lua5.1 tests/manual_ui_test.lua
--
-- Same shape as window_test.lua and for the same reason: the real client files
-- are loaded against a fake game -- a font of a known width, a window base
-- class that records what was painted, a button that only remembers what it was
-- told -- and what is asserted is what ends up on the paper, not what a field
-- says.
--
-- The TEXT of the manual is not this bench's business and is not in the mod
-- under test: the three volume files under shared/CeroSec/ are written
-- separately. So the bench brings a placeholder of its own -- a shelf of one
-- volume, three chapters of known length -- and that placeholder lives HERE and
-- is never shipped. A bench that read the real text would go red every time
-- somebody fixed a typo in it.
--

--
-- The game, faked.
--

_G.require = function() end
_G.getTimestampMs = function() return 1000 end

_G.UIFont = {
	Code = "Code", Small = "Small",
	NewSmall = "NewSmall", NewMedium = "NewMedium", NewLarge = "NewLarge",
}
-- Escape, Left, Right and Home, the four the window reads. The numbers are
-- org.lwjglx.input.Keyboard's names and not its values: nothing here does
-- arithmetic on a key code, so any four distinct numbers prove the same thing.
_G.Keyboard = { KEY_ESCAPE = 1, KEY_LEFT = 203, KEY_RIGHT = 205, KEY_HOME = 199 }

-- The fonts. The monospaced one is UIFont.Code, one width for every glyph, the
-- way the game's own codeMedium.fnt is. The body font is PROPORTIONAL on
-- purpose -- a narrower "i" than "M" -- because a wrapper measured against a
-- fixed width is a wrapper that has never been asked the question it exists to
-- answer, and the real UIFont.NewMedium is proportional.
-- And MeasureStringX does not answer the advance. It hands the string to
-- AngelCodeFont.getWidth(s, 0, len - 1, false), and that false makes the LAST
-- character count as its glyph's ink `width` while every other counts as its
-- `xadvance`; only the pen that draws moves by xadvance throughout. In
-- zomboidCode.fnt "M" is width=9 xadvance=8 -- a pixel WIDER in ink than the
-- cell it is drawn in -- so the answer for a lone "M" is a pixel too big for a
-- cell. CODE_INK is that, modelled the way tests/window_test.lua models it: a
-- bench whose font returned CODE_W * #s could not see a grid built on the ink go
-- wrong, and this one did not, for exactly that reason.
local CODE_W = 8
local CODE_INK = { M = 9 }
local function codeWidth(s)
	if s == nil or s == "" then return 0 end
	local last = string.sub(s, -1)
	return CODE_W * (#s - 1) + (CODE_INK[last] or CODE_W - 1)
end
local NARROW = { i = 3, l = 3, t = 4, j = 3, f = 4, r = 4, [" "] = 4 }
local WIDE = { m = 11, w = 11, M = 12, W = 12 }
local function bodyWidth(s)
	local total = 0
	for i = 1, #s do
		local char = string.sub(s, i, i)
		total = total + (NARROW[char] or WIDE[char] or 7)
	end
	return total
end
_G.getTextManager = function()
	return {
		MeasureStringX = function(_, font, s)
			if font == "Code" then return codeWidth(s) end
			return bodyWidth(s)
		end,
		getFontHeight = function(_, font)
			if font == "NewLarge" then return 18 end
			if font == "NewSmall" then return 10 end
			return 14
		end,
	}
end
_G.getCore = function()
	return { getScreenWidth = function() return 1920 end,
		getScreenHeight = function() return 1080 end,
		getObjectHighlitedColor = function() return { r = 1, g = 1, b = 1 } end }
end
_G.getText = function(key) return key end
-- A stub texture: distinct from a real one but truthy, so CeroSecMenu.setIcon's
-- nil check is the thing under test, not what a table equality would already
-- pass. Some rungs below replace this with a function returning nil, to prove
-- a missing texture never breaks the menu.
_G.getTexture = function(path) return { path = path } end
_G.getMouseX = function() return 0 end
_G.getMouseY = function() return 0 end
_G.Events = setmetatable({}, { __index = function(t, key)
	-- Events.Foo.Add(fn) -- a dot, not a colon: the game's own Lua adds its
	-- handlers that way and so does ours, so the fake must not expect a self.
	local event = { handlers = {} }
	event.Add = function(fn) event.handlers[#event.handlers + 1] = fn end
	rawset(t, key, event)
	return event
end })

-- An InventoryItem is anything the bench marked as one.
_G.instanceof = function(o, kind)
	return type(o) == "table" and o.__class == kind
end

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
function ISCollapsableWindow.createChildren() end
function ISCollapsableWindow.prerender() end
function ISCollapsableWindow.render() end
function ISCollapsableWindow.onMouseDown() return false end
function ISCollapsableWindow.initialise() end
function ISCollapsableWindow.addToUIManager() end
function ISCollapsableWindow.removeFromUIManager() end
function ISCollapsableWindow.addChild(self, child) self.children[#self.children + 1] = child end
function ISCollapsableWindow.setResizable() end
function ISCollapsableWindow.setTitle(self, title) self.titleText = title end
function ISCollapsableWindow.setVisible() end
function ISCollapsableWindow.setWantKeyEvents(self, want) self.wantKeys = want end
function ISCollapsableWindow.drawRect() end
function ISCollapsableWindow.drawText() end
-- Where the cursor is, in the window's own coordinates. Parked off the paper
-- unless a test puts it somewhere.
function ISCollapsableWindow.getMouseX(self) return self.mouseX or -1000 end
function ISCollapsableWindow.getMouseY(self) return self.mouseY or -1000 end

-- A button that remembers its label and who to call. Nothing here clicks one:
-- the tests call the window's own onPrev/onNext/onContents, which is what the
-- button calls, so the bench does not depend on ISButton's dispatch.
local Button = {}
Button.__index = Button
function Button:initialise() end
function Button:instantiate() end
function Button:setFont(font) self.font = font end
ISButton = { new = function(_, x, y, w, h, title, target, onclick)
	return setmetatable({ x = x, y = y, width = w, height = h,
		title = title, target = target, onclick = onclick }, Button)
end }

-- A context menu and its submenus, faked the way the game builds them:
-- ISContextMenu:getNew(parent) hands back a child menu and addSubMenu(option,
-- menu) hangs it off an option (ISContextMenu.lua:1075-1077,1199). What the
-- bench keeps is which option each submenu was hung off, because a submenu
-- built and filled but never attached is an entry that leads nowhere -- and
-- the entries inside it would look perfectly right to a test that only counted
-- them.
--
-- AND IT MODELS WHERE AN OPTION LANDS, because that is now part of what the mod
-- decides: every entry of this mod goes at the TOP of the menu (CeroSecMenu), so a
-- fake that appended everything and kept its labels in the order it was CALLED
-- could not tell the menu the glass shows from the order the file happens to be
-- written in. The three the game gives a mod are written here exactly as the engine
-- writes them:
--
--   * addOption appends -- `self.options[self.numOptions] = option` (:873-887).
--   * addOptionOnTop shifts every id up by one and puts the new option at index 1
--     (:914-930), which is why calling it N times reverses the N.
--   * insertOptionBefore finds an option BY NAME, shifts the tail down from there
--     and renumbers every id (:965-1001); an empty menu or a name nothing answers
--     to falls through to addOption (:967-969, :979-981), and index 1 is
--     addOptionOnTop itself (:982-984).
--
-- `labels` is a POSITIONAL mirror of options, rebuilt after every insertion: it is
-- what the blocks below read the menu off, and a mirror kept by appending would be
-- the very thing this fake exists to stop being green.
local ContextMenu = {}
ContextMenu.__index = ContextMenu
function ContextMenu.new()
	return setmetatable({ labels = {}, options = {}, subs = {} }, ContextMenu)
end
--
-- EVERY argument is kept, and the COUNT of them with it. addOption's tail is what
-- an option actually carries -- the drive's entries put the computer, the player,
-- the height and the DISK in it -- so a fake that remembered only the first two
-- could not tell a submenu entry that inserts the yellow disk from one that
-- inserts the blue. arg and arg2 stay beside args because the blocks below read
-- them by those names.
--
-- `name` is the engine's own field for the words on an option (allocOption,
-- :849-856) and `label` is the name this bench has always read it by; both are set
-- to the one string, because insertOptionBefore looks an option up by `name` and a
-- fake that had only `label` would send the mod down its fallback every time.
function ContextMenu:allocOption(label, target, callback, ...)
	local n = select("#", ...)
	local args = { ... }
	return { label = label, name = label, target = target, callback = callback,
		args = args, argCount = n, arg = args[1], arg2 = args[2] }
end
-- The ids and the label mirror, after any insertion. The engine renumbers ids in
-- insertOptionBefore (:996-998) and the window draws a submenu off `option.id`
-- (:780-781), so an id left pointing at the old row is a submenu drawn at the wrong
-- height.
function ContextMenu:resync()
	self.labels = {}
	for i = 1, #self.options do
		self.options[i].id = i
		self.labels[i] = self.options[i].label
	end
end
function ContextMenu:addOption(label, target, callback, ...)
	local option = self:allocOption(label, target, callback, ...)
	self.options[#self.options + 1] = option
	self:resync()
	return option
end
function ContextMenu:addOptionOnTop(label, target, callback, ...)
	local option = self:allocOption(label, target, callback, ...)
	table.insert(self.options, 1, option)
	self:resync()
	return option
end
function ContextMenu:insertOptionBefore(nextName, label, target, callback, ...)
	if #self.options == 0 then
		return self:addOption(label, target, callback, ...)
	end
	local index, found = 1, false
	for i = 1, #self.options do
		index = i
		if self.options[i].name == nextName then found = true; break end
	end
	if not found then return self:addOption(label, target, callback, ...) end
	if index == 1 then return self:addOptionOnTop(label, target, callback, ...) end
	local option = self:allocOption(label, target, callback, ...)
	table.insert(self.options, index, option)
	self:resync()
	return option
end
function ContextMenu:insertOptionAfter(prevName, label, target, callback, ...)
	if #self.options == 0 then
		return self:addOption(label, target, callback, ...)
	end
	local index, found = 1, false
	for i = 1, #self.options do
		index = i
		if self.options[i].name == prevName then found = true; break end
	end
	if not found then return self:addOption(label, target, callback, ...) end
	local option = self:allocOption(label, target, callback, ...)
	table.insert(self.options, index + 1, option)
	self:resync()
	return option
end

function ContextMenu:addSubMenu(option, menu)
	self.subs[#self.subs + 1] = { option = option, menu = menu }
	menu.hungOff = option
end

-- THE CHAIN A CLICK WALKS, transcribed and not invented, because keeping `parent`
-- as a field nobody read is exactly what let a third level hung off the ROOT look
-- right here and stay on the glass in the game. Vanilla: the click calls
-- closeAll() on the menu the option was clicked in (ISContextMenu.lua:60-70),
-- closeAll hides that menu and its children and then walks `parent` UP, hiding
-- each ancestor in turn (:278-292). Nothing else puts an ancestor away -- and an
-- ancestor left visible re-shows its own submenu every frame while the mouse
-- rests on the option (:441-452), which is why a skipped level brings its child
-- back with it.
ContextMenu.visible = true
function ContextMenu:hideAndChildren()
	self.visible = false
	for i = 1, #self.subs do self.subs[i].menu:hideAndChildren() end
end
function ContextMenu:closeAll()
	self:hideAndChildren()
	local parent = self.parent
	while parent do
		parent.visible = false
		parent = parent.parent
	end
end
ISContextMenu = { getNew = function(_, parent)
	local menu = ContextMenu.new()
	menu.parent = parent
	return menu
end }

--
-- The mod, loaded the way the game loads it.
--

-- The inventory pane, faked down to the one function the double-click funnels
-- through (ISInventoryPane.lua:1199 calls :doContextualDblClick(item), and the
-- real one is a ladder of elseifs over what the item IS). The bench's is a
-- recorder: what the mod's wrap has to prove is that it answers for OUR books
-- and hands every other item back to the original untouched -- not what vanilla
-- then does with a screwdriver.
--
-- Stood up BEFORE the mod files are loaded below, because CeroSecManualMenu
-- wraps this function at load time. A bench that faked the pane afterwards
-- would be a bench where the wrap never happened, and it would still pass every
-- assertion about the context menu beside it.
-- The CALLS are counted apart from the items recorded, deliberately: the pane is
-- also handed a double-click on empty space, and an item of nil appended to a
-- list does not make the list longer. Counted by the list alone, "the original
-- was called with nothing" and "the original was never called" would be the same
-- green.
ISInventoryPane = {}
ISInventoryPane.dblClicked = {}
ISInventoryPane.dblCalls = 0
function ISInventoryPane.doContextualDblClick(pane, item)
	ISInventoryPane.dblCalls = ISInventoryPane.dblCalls + 1
	ISInventoryPane.dblClicked[#ISInventoryPane.dblClicked + 1] = item
	return "vanilla"
end
local VANILLA_DBLCLICK = ISInventoryPane.doContextualDblClick

local LUA = "42/media/lua/"
local FILES = {
	"shared/CeroSec/CeroSecDefs.lua",
	-- The four hardware modules name the four items they are made of, and the
	-- item script below is checked against that list rather than against four
	-- names typed again here.
	"shared/CeroSec/CeroSecModules.lua",
	"shared/CeroSec/CeroSecManualBook.lua",
	-- The telephone directory: the generator, which is pure, and the client half
	-- that stamps the copy and opens the reader on it. The menu below requires
	-- both, because the phone book's entry sits beside the volumes'.
	"shared/CeroSec/OS/CeroSecOSNet.lua",
	"shared/CeroSec/CeroSecPhonebook.lua",
	"client/CeroSec/CeroSecPhonebookUI.lua",
	"client/CeroSec/CeroSecManualUI.lua",
	-- Where every entry of this mod goes on a menu, which the three menu files
	-- below all go through (CeroSecMenu.addTop).
	"client/CeroSec/CeroSecMenu.lua",
	"client/CeroSec/CeroSecManualMenu.lua",
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

-- Two entries of the GAME's own, put on before ours. The engine fills the world
-- menu in zombie.iso.ISWorldObjectContextMenuLogic.createMenuEntries -- called at
-- ISWorldObjectContextMenu.lua:209 -- and fires the event a mod listens on four
-- lines later at :213, so Grab and Equip are already on the menu when our own go
-- on. Without them "ours are first" would be an assertion about a menu with
-- nothing else in it, which is green whatever the mod does.
local VANILLA_ENTRIES = { "Grab", "Equip" }
local function withVanilla(menu)
	for i = 1, #VANILLA_ENTRIES do menu:addOption(VANILLA_ENTRIES[i]) end
	return menu
end

-- The leading run of OUR entries, by the mark CeroSecMenu.addTop leaves on each
-- one. Read off the mark and not off a list of labels typed here, so an entry
-- somebody adds without going through addTop is an entry this run does not count
-- and the assertions below go red on.
local function ourOptions(menu)
	local out = {}
	for i = 1, #menu.options do
		if menu.options[i].cerosec ~= true then break end
		out[#out + 1] = menu.options[i]
	end
	return out
end

local function ourLabels(menu)
	local out = {}
	local ours = ourOptions(menu)
	for i = 1, #ours do out[i] = ours[i].label end
	return out
end

-- Our block is the first N, in the order given, and the game's own entries are
-- still under it in their own order. Both halves: a menu that dropped vanilla's
-- entries would pass the first on its own.
local function checkTop(what, menu, want)
	local got = ourLabels(menu)
	eq(what .. ": " .. #want .. " of our entries lead the menu", #got, #want)
	for i = 1, #want do
		eq(what .. ": entry " .. i .. " is " .. want[i], got[i], want[i])
	end
	for i = 1, #VANILLA_ENTRIES do
		eq(what .. ": the game's " .. VANILLA_ENTRIES[i] .. " is under them",
			menu.labels[#want + i], VANILLA_ENTRIES[i])
	end
end

--
-- A manual, for the bench only. THREE chapters, of deliberately different
-- lengths: one that fits a leaf, one long enough to spill onto a second, and
-- one with an example line in the middle of it.
--
-- The long word in chapter two is there so the wrapper is asked the one
-- question it can get wrong quietly: a word wider than the leaf all on its own.
--

local EXAMPLE = "  ls -l /etc/passwd"
local LONG = string.rep("Wm", 90)

-- A shelf of ONE volume, because that is what the reader reads: there is no book
-- behind the shelf any more (the single volume this mod shipped first was retired
-- when the third was written), so a bench book is a VOLUME with an id, and the
-- cover is stamped from CeroSecOS.VERSION the way a real one is.
-- The core's net half IS loaded now (the directory's arithmetic is in it), so
-- CeroSecOS is already standing and only the version has to be put on it: the
-- file that carries the real one is not in this bench's list.
CeroSecOS = CeroSecOS or {}
CeroSecOS.VERSION = CeroSecOS.VERSION or "1.0"

local BENCH_CHAPTERS = {
		{
			title = "Getting Started",
			pages = {
				"Turn the machine on and it counts its memory.\n\n" ..
				"Then it asks who you are. Two accounts ship on every fresh " ..
				"machine and both of them have an empty password, so pressing " ..
				"Enter at the question is the whole of logging in.",
			},
		},
		{
			title = "The Shell",
			pages = {
				string.rep("The shell reads a line, runs it, and prints what came " ..
					"back. There is no pipe on this machine and there is no regex. ", 8),
				"A command is a file under /bin.\n" .. EXAMPLE ..
					"\nThat is the whole of the rule, and " .. LONG .. " is not a word.",
			},
		},
		{
			title = "Accounts",
			pages = { "Root can make an account and root can take it away." },
		},
}

-- One volume on one shelf, made fresh each time a block wants its own: the
-- reader reads CeroSecManual.volumes and a block that swapped the table has to
-- put a shelf back and not a book.
local function benchShelf(chapters, id, name)
	return { volumes = { {
		id = id or "user",
		title = nil,
		name = name or "User's Guide",
		edition = "First edition, 1993",
		chapters = chapters or BENCH_CHAPTERS,
	} } }
end

CeroSecManual = benchShelf()

-- The one volume on it, stamped, which is what a layout is handed.
local function benchVolume()
	return CeroSecManualBook.volume(nil)
end

-- What the reader stamps on the cover of it, which is what the window's title
-- bar wears.
local BENCH_TITLE = "CeroSec OS " .. CeroSecOS.VERSION .. " User's Guide"

--
-- One book, one window, one item.
--

-- A container that really holds things, because the retired book's conversion is a
-- REPLACEMENT in one: AddItem, then Remove, and the bench has to be able to say what
-- is in the bag afterwards. `refuse` is the shape the ORDER of those two halves exists
-- for -- a full bag -- and the two send* calls a multiplayer client owes the server are
-- counted rather than stubbed away.
local newItem
local function newContainer(name)
	local held = {}
	return {
		name = name or "inventory",
		held = held,
		added = 0,
		removed = 0,
		refuse = false,
		AddItem = function(self, fullType)
			-- Counted as an ATTEMPT and not as a success, so a bench can tell "it never
			-- tried" from "it tried and the bag was full".
			self.added = self.added + 1
			if self.refuse then return nil end
			local made = newItem(fullType)
			made.container = self
			held[#held + 1] = made
			return made
		end,
		Remove = function(self, item)
			self.removed = self.removed + 1
			for i = #held, 1, -1 do
				if held[i] == item then table.remove(held, i) end
			end
		end,
		holds = function(self, fullType)
			for i = 1, #held do
				if held[i].fullType == fullType then return held[i] end
			end
			return nil
		end,
	}
end

newItem = function(fullType)
	local data = {}
	return {
		__class = "InventoryItem",
		fullType = fullType or "CeroSec.ManualUser",
		getFullType = function(self) return self.fullType end,
		getModData = function() return data end,
		-- A bag of its own unless a bench puts it in one, so that any book in this file
		-- can be read -- reading the retired one replaces it in whatever it is in.
		container = nil,
		getContainer = function(self)
			if self.container == nil then self.container = newContainer() end
			return self.container
		end,
		data = data,
	}
end

local function newPlayer()
	return {
		getPlayerNum = function() return 0 end,
		isDead = function() return false end,
	}
end

-- A window on a named volume. With no volume named it is the legacy single
-- book, which is what CeroSecManual is until the shelf is stood up -- and what
-- every block below this one that says nothing about volumes is reading.
local function newVolumeWindow(volumeId, item)
	local window = CeroSecManualUI:new(0, 0, newPlayer(), volumeId, item)
	window:initialise()
	window:createChildren()
	-- What was painted this frame, and where.
	window.painted = {}
	window.rects = {}
	window.drawText = function(self, text, x, y, r, g, b, a, font)
		self.painted[#self.painted + 1] = { text = text, x = x, y = y, font = font }
	end
	window.drawRect = function(self, x, y, w, h)
		self.rects[#self.rects + 1] = { x = x, y = y, w = w, h = h }
	end
	window.frame = function(self)
		self.painted = {}
		self.rects = {}
		self:prerender()
		self:render()
	end
	return window
end

local function newWindow(item)
	return newVolumeWindow(nil, item)
end

--
-- Wrapping
--

do
	local width = 300
	local lines = CeroSecManualBook.wrap(
		"the quick brown fox jumps over the lazy dog and keeps on running " ..
		"until there is nothing left to run towards", width, bodyWidth)
	check("wrapping produced more than one line", #lines > 1)
	for i = 1, #lines do
		check("line " .. i .. " fits the width", bodyWidth(lines[i]) <= width)
		check("line " .. i .. " has no leading space", string.sub(lines[i], 1, 1) ~= " ")
	end
	eq("nothing was lost", table.concat(lines, " "),
		"the quick brown fox jumps over the lazy dog and keeps on running " ..
		"until there is nothing left to run towards")

	-- A word wider than the leaf is broken rather than drawn off the paper.
	local broken = CeroSecManualBook.wrap(LONG, width, bodyWidth)
	check("a too-long word was broken", #broken > 1)
	for i = 1, #broken do
		check("piece " .. i .. " fits", bodyWidth(broken[i]) <= width)
	end
	eq("and nothing of it was lost", table.concat(broken, ""), LONG)

	-- An empty paragraph is a blank line, not nothing.
	eq("an empty paragraph is one blank line", #CeroSecManualBook.wrap("", width, bodyWidth), 1)
end

--
-- Laying a page out: example lines are left exactly as they were typed
--

do
	local laid = CeroSecManualBook.layout(
		"before\n" .. EXAMPLE .. "\n\nafter",
		{ width = 300, rows = 20, measure = bodyWidth })
	local codeLines = {}
	for i = 1, #laid do
		if laid[i].code then codeLines[#codeLines + 1] = laid[i].text end
	end
	eq("one example line", #codeLines, 1)
	eq("untouched, spaces and all", codeLines[1], EXAMPLE)
	check("the example is marked as code", true)

	local blank = false
	for i = 1, #laid do
		if not laid[i].code and laid[i].text == "" then blank = true end
	end
	check("the paragraph break survived as a blank line", blank)
end

--
-- Reflowing: the writer's hard wrapping is not the leaf's
--
-- The manual is typed into a file by hand and its paragraphs are wrapped at the
-- writer's column. Page 87 of the printed book showed what honouring every one
-- of those newlines looked like: a full row, then a row carrying the single word
-- that had fallen off the end of the writer's line, then prose again. So a
-- single newline inside a page is a space, a blank line is the paragraph break,
-- and an example line keeps its own row.
--
-- The paragraph below is the one from that screenshot, wrapped short on purpose
-- so the bench's own leaf makes orphans out of it the same way.
--

local HARD =
	"Press Tab again on the same word and the\n" ..
	"names are listed in columns, the way ls\n" ..
	"lists them, and the line you were typing\n" ..
	"is printed again underneath.\n" ..
	"\n" ..
	"A command is a file under /bin.\n" ..
	"  ls -l /bin\n" ..
	"  ls -l /etc\n" ..
	"That is the whole of the rule."

local PARAGRAPH = "Press Tab again on the same word and the names are listed " ..
	"in columns, the way ls lists them, and the line you were typing is " ..
	"printed again underneath."

-- The words of a text, in order, whatever it was broken on. What must survive
-- every join and every wrap.
local function words(text)
	local out = {}
	for word in string.gmatch(text, "%S+") do out[#out + 1] = word end
	return table.concat(out, " ")
end

do
	local lines = {}
	for line in (CeroSecManualUI.reflow(HARD) .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end

	eq("six lines out of nine, the joined ones gone", #lines, 6)
	eq("the hard-wrapped paragraph came back as one piece", lines[1], PARAGRAPH)
	check("and the join left one space, not two",
		string.find(lines[1], "  ", 1, true) == nil)
	eq("the blank line is still the paragraph break", lines[2], "")
	eq("the prose before the example is its own line", lines[3],
		"A command is a file under /bin.")
	eq("the first example line is exactly as typed", lines[4], "  ls -l /bin")
	eq("and the second, never joined to the first", lines[5], "  ls -l /etc")
	eq("the prose after the example starts again", lines[6],
		"That is the whole of the rule.")
	eq("and not a word of it was lost", words(table.concat(lines, " ")), words(HARD))

	-- A line typed with a trailing space, or indented by one -- one space is not
	-- two, so it is prose and not an example -- joins with a single space all
	-- the same.
	eq("stray spaces around a join are collapsed",
		CeroSecManualUI.reflow("foo   \n bar"), "foo bar")
	-- A run of blank lines is the writer's spacing and it survives.
	eq("two blank lines stay two", CeroSecManualUI.reflow("a\n\n\nb"), "a\n\n\nb")
	-- Nothing to reflow is nothing at all, and an absent page is not a crash.
	eq("an empty page reflows to an empty page", CeroSecManualUI.reflow(""), "")
	eq("a page that is not a string comes back as it was",
		CeroSecManualUI.reflow(nil), nil)
end

--
-- The same page laid out: full rows, no orphans, the example block intact
--

do
	local width = 300
	local opts = { width = width, rows = 40, measure = bodyWidth }
	local manual = { title = "T", edition = "",
		chapters = { { title = "C", pages = { HARD } } } }
	local book = CeroSecManualBook.open(CeroSecManualUI.reflowed(manual), opts)
	local page = book.pages[book.chapters[1].page]
	local lines = page.lines

	check("the paragraph still needed more than one row", #lines > 4)

	-- The widest word in the paragraph: a greedy wrap can leave a row short by
	-- at most that much, so a row shorter than the leaf less that word is a row
	-- something else ended.
	local widest = 0
	for word in string.gmatch(PARAGRAPH, "%S+") do
		if bodyWidth(word) > widest then widest = bodyWidth(word) end
	end

	for i = 1, #lines - 1 do
		local line, below = lines[i], lines[i + 1]
		if not line.code and not below.code and line.text ~= "" and below.text ~= "" then
			check("row " .. i .. " is full: \"" .. line.text .. "\"",
				bodyWidth(line.text) > width - widest)
			-- And full in the only sense that settles it: the row below's first
			-- word genuinely would not have fitted on this one.
			local first = string.match(below.text, "^%S+")
			check("row " .. i .. " could not have taken \"" .. tostring(first) .. "\"",
				bodyWidth(line.text .. " " .. first) > width)
		end
	end

	-- The order the page was written in, on the page: prose, the break, prose,
	-- the two example lines side by side, prose.
	local seen = {}
	for i = 1, #lines do
		seen[#seen + 1] = (lines[i].code and "code:" or "text:") .. lines[i].text
	end
	local blank, code1, code2, after = nil, nil, nil, nil
	for i = 1, #seen do
		if seen[i] == "text:" then blank = blank or i end
		if seen[i] == "code:  ls -l /bin" then code1 = i end
		if seen[i] == "code:  ls -l /etc" then code2 = i end
		if seen[i] == "text:That is the whole of the rule." then after = i end
	end
	check("the paragraph break is on the page", blank ~= nil)
	check("both example lines are on the page", code1 ~= nil and code2 ~= nil)
	eq("and they are one block, in order", code2, code1 + 1)
	check("the break comes before them", blank < code1)
	check("the prose after them comes after", after == code2 + 1)
	eq("the example lines are drawn monospaced", lines[code1].code, true)

	-- And the paragraph itself is still every word it was, in order, across
	-- however many rows it took.
	local rows = {}
	for i = 1, blank - 1 do rows[#rows + 1] = lines[i].text end
	eq("the paragraph is word for word what was written",
		words(table.concat(rows, " ")), words(PARAGRAPH))
end

--
-- And through the reader itself: the orphan rows are gone from the glass
--

do
	-- The block above proves the pair; this one proves the reader WIRED it. A
	-- window lays the manual out as it stands, so with the reflow not called
	-- from :layout() the orphan rows would still be painted and every assertion
	-- above would still be green.
	local real = CeroSecManual

	-- What was painted on the chapter's own leaf, by font. A book of one
	-- chapter of one page, so the running head (FONT_HEAD) and the page number
	-- (FONT_FOOT) are the only other things on the sheet.
	local function paintedIn(page, font)
		CeroSecManual = benchShelf({ { title = "C", pages = { page } } })
		local window = newWindow(newItem())
		window:goToPage(window.book.chapters[1].page)
		window:frame()
		local out = {}
		for i = 1, #window.painted do
			local paint = window.painted[i]
			if paint.font == font then out[#out + 1] = paint.text end
		end
		return out
	end

	-- One paragraph and nothing else, so every consecutive pair of painted rows
	-- is a pair inside the same paragraph -- and a short row is an orphan and
	-- not the end of something.
	local hardParagraph =
		"Press Tab again on the same word and the\n" ..
		"names are listed in columns, the way ls\n" ..
		"lists them, and the line you were typing\n" ..
		"is printed again underneath."
	local prose = paintedIn(hardParagraph, CeroSecManualUI.FONT_BODY)
	local leafText = CeroSecManualUI.LEAF_COLS * CODE_W
	check("the prose was painted on more than one row", #prose > 1)
	check("and on fewer rows than the writer typed", #prose < 4)
	for i = 1, #prose - 1 do
		local first = string.match(prose[i + 1], "^%S+")
		check("painted row " .. i .. " is not an orphan-maker: \"" .. prose[i] .. "\"",
			bodyWidth(prose[i] .. " " .. first) > leafText)
	end
	eq("and the paragraph on the glass is word for word what was written",
		words(table.concat(prose, " ")), words(PARAGRAPH))

	-- The example lines reached the glass monospaced and untouched.
	local code = paintedIn(HARD, CeroSecManualUI.FONT_CODE)
	eq("two example lines were painted monospaced", #code, 2)
	eq("the first as typed", code[1], "  ls -l /bin")
	eq("the second as typed", code[2], "  ls -l /etc")

	CeroSecManual = real
end

--
-- A paragraph break that falls exactly at the foot of a leaf
--

do
	-- Six lines, a break after the third, three rows to a leaf: the break is
	-- the first thing on the second leaf, and a leaf that opens on empty paper
	-- reads as a printing fault. Written as its own tiny book because the
	-- three-chapter fixture never happens to land a break on a boundary, and a
	-- case nothing provokes is a case nothing tests.
	local manual = { title = "T", edition = "",
		chapters = { { title = "C", pages = { "aaa\nbbb\nccc\n\nddd\neee" } } } }
	local book = CeroSecManualBook.open(manual, { width = 300, rows = 3, measure = bodyWidth })
	local first = book.chapters[1].page
	eq("the leaf before the break is full", #book.pages[first].lines, 3)
	eq("the leaf after it opens on words", book.pages[first + 1].lines[1].text, "ddd")
	eq("and holds only what is left", #book.pages[first + 1].lines, 2)
end

--
-- The book: pagination over the three chapters
--

do
	local opts = { width = 300, rows = 6, measure = bodyWidth }
	local book = CeroSecManualBook.open(benchVolume(), opts)

	eq("the title came through", book.title, BENCH_TITLE)
	eq("and the edition", book.edition, "First edition, 1993")
	eq("three chapters", #book.chapters, 3)

	eq("page 1 is the title leaf", book.pages[1].kind, "title")
	eq("page 2 is the contents", book.pages[2].kind, "toc")
	eq("the contents lists every chapter", #book.pages[2].entries, 3)

	-- What the contents PRINTS, judged against the leaves themselves and not
	-- against the same field the contents was built from. A table of contents
	-- one page out is the mistake that goes unnoticed for a whole edition, and
	-- a row checked against book.chapters[n].page would agree with it happily.
	for e = 1, #book.pages[2].entries do
		local entry = book.pages[2].entries[e]
		local target = book.pages[entry.page]
		check("contents row " .. e .. " points at a leaf that exists", target ~= nil)
		eq("contents row " .. e .. " points at that chapter's own leaf",
			target.chapterIndex, entry.index)
		local before = book.pages[entry.page - 1]
		check("contents row " .. e .. " points at its FIRST leaf",
			before == nil or before.chapterIndex ~= entry.index)
		eq("contents row " .. e .. " is titled the way the leaf is headed",
			entry.title, target.chapter)
	end

	-- Every chapter opens a leaf of its own, and the contents names the leaf it
	-- really opens on -- which is the one thing a table of contents can get
	-- wrong without anybody noticing.
	for c = 1, 3 do
		local entry = book.chapters[c]
		local page = book.pages[entry.page]
		check("chapter " .. c .. " starts on a page that exists", page ~= nil)
		eq("chapter " .. c .. "'s first leaf carries its own running head",
			page.chapter, entry.title)
		eq("chapter " .. c .. " starts at the top of a leaf", page.chapterIndex, c)
		if c > 1 then
			local before = book.pages[entry.page - 1]
			check("chapter " .. c .. " did not begin halfway down the leaf before it",
				before.chapterIndex ~= c)
		end
	end

	-- Chapter two is longer than one leaf at six rows, so it spilled.
	local two = 0
	for i = 1, #book.pages do
		if book.pages[i].chapterIndex == 2 then two = two + 1 end
	end
	check("the long chapter spilled onto more than one leaf", two > 1)

	-- No leaf holds more than it was told to, and no leaf opens on the blank
	-- line that was a paragraph break at the bottom of the leaf before it.
	for i = 1, #book.pages do
		check("leaf " .. i .. " is not overfull", #book.pages[i].lines <= opts.rows)
		local first = book.pages[i].lines[1]
		check("leaf " .. i .. " does not open on a blank line",
			first == nil or first.text ~= "" or first.code)
	end

	-- Nothing was dropped on the way: the example line is still in the book,
	-- exactly as it was typed.
	local foundExample = false
	for i = 1, #book.pages do
		for l = 1, #book.pages[i].lines do
			local line = book.pages[i].lines[l]
			if line.code and line.text == EXAMPLE then foundExample = true end
		end
	end
	check("the example line survived pagination untouched", foundExample)

	-- A book is read two leaves at a time, so it has an even number of them.
	eq("the book has an even number of leaves", #book.pages % 2, 0)

	-- The sheet arithmetic.
	eq("pages 1 and 2 share a sheet",
		CeroSecManualBook.sheetOf(1), CeroSecManualBook.sheetOf(2))
	check("pages 2 and 3 do not",
		CeroSecManualBook.sheetOf(2) ~= CeroSecManualBook.sheetOf(3))
	eq("sheet 2's left leaf is page 3", CeroSecManualBook.leftOf(2), 3)

	-- A bookmark from a longer book comes back to the front rather than to an
	-- empty leaf, and so does anything that is not a number.
	eq("a page past the end falls back to the front",
		CeroSecManualBook.clampPage(book, #book.pages + 40), 1)
	eq("a nil bookmark is the front", CeroSecManualBook.clampPage(book, nil), 1)
	eq("a right-hand bookmark comes back to its own sheet",
		CeroSecManualBook.clampPage(book, 4), 3)
end

--
-- An empty book: no text file at all
--

do
	local book = CeroSecManualBook.open(nil, { width = 300, rows = 6, measure = bodyWidth })
	check("an absent manual still opens", #book.pages >= 2)
	eq("with a contents that lists nothing", #book.pages[2].entries, 0)
	eq("and still an even number of leaves", #book.pages % 2, 0)

	-- A book whose leaves come out ODD -- a title, a contents and one short
	-- chapter -- gets the blank back of the last sheet, so the reader is never
	-- shown half a spread. Without a book that naturally comes out odd, an
	-- assertion on the count is green for having nothing to correct.
	local odd = CeroSecManualBook.open(
		{ title = "T", edition = "", chapters = { { title = "C", pages = { "one line" } } } },
		{ width = 300, rows = 6, measure = bodyWidth })
	eq("three leaves of content became four", #odd.pages, 4)
	eq("and the fourth is blank paper", #odd.pages[4].lines, 0)
end

--
-- The window: what lands on the paper
--

do
	local item = newItem()
	local window = newWindow(item)

	eq("it opens at the front", window.page, 1)
	eq("the window wears the book's title", window.titleText, BENCH_TITLE)
	check("it asked for key events", window.wantKeys == true)
	eq("three buttons", #window.children, 3)

	window:frame()

	-- Nothing painted on a leaf is wider than the leaf. This is the whole of
	-- the wrapping promise, measured where it actually matters: on the glass.
	local leafText = CeroSecManualUI.LEAF_COLS * CODE_W
	for i = 1, #window.painted do
		local paint = window.painted[i]
		if paint.font == CeroSecManualUI.FONT_BODY then
			check("painted line fits the leaf: " .. paint.text,
				bodyWidth(paint.text) <= leafText)
		end
	end

	-- The leaf is built on the ADVANCE of a monospaced cell and not on the ink of
	-- a glyph. Proved on the window's own width, without the bench having to know
	-- the paddings: the ink of "M" is a pixel wider than its cell, so a grid taken
	-- as MeasureStringX("M") is a pixel per column too wide -- and moving the ink
	-- alone must move nothing at all.
	check("the bench's own Code font is honest about it",
		codeWidth("M") ~= CODE_W and codeWidth("MM") - codeWidth("M") == CODE_W)
	local honest = newWindow(newItem()).width
	CODE_INK.M = CODE_W + 5
	local fatter = newWindow(newItem()).width
	CODE_INK.M = 9
	eq("a fatter M does not widen the leaf", fatter, honest)

	-- And it really is LEAF_COLS of them across each of the two leaves: a cell
	-- one pixel wider is a book two columns' worth wider.
	CODE_W = CODE_W + 1
	local wider = newWindow(newItem()).width
	CODE_W = CODE_W - 1
	eq("a cell a pixel wider is a leaf LEAF_COLS pixels wider, twice over",
		wider - honest, 2 * CeroSecManualUI.LEAF_COLS)
	eq("and the layout comes back to what it was",
		newWindow(newItem()).width, honest)

	-- Turning the leaves.
	window:onNext()
	eq("next turned one sheet", window.page, 3)
	window:onNext()
	eq("and another", window.page, 5)
	window:onPrev()
	eq("back turned one back", window.page, 3)
	window:onPrev()
	eq("and back to the front", window.page, 1)
	window:onPrev()
	eq("the front leaf does not turn backwards", window.page, 1)

	-- The end of the book.
	local last = CeroSecManualBook.sheetCount(window.book)
	for _ = 1, last + 5 do window:onNext() end
	eq("the last sheet does not turn forwards",
		window.page, CeroSecManualBook.leftOf(last))

	-- Left and Right do what the buttons do.
	window:goToSheet(1)
	window:onKeyRelease(Keyboard.KEY_RIGHT)
	eq("Right turns forward", window.page, 3)
	window:onKeyRelease(Keyboard.KEY_LEFT)
	eq("Left turns back", window.page, 1)
	check("the window consumes the keys it reads",
		window:isKeyConsumed(Keyboard.KEY_LEFT) and
		window:isKeyConsumed(Keyboard.KEY_RIGHT) and
		window:isKeyConsumed(Keyboard.KEY_ESCAPE))

	-- Escape closes it.
	CeroSecManualUI.instances[0] = window
	window:onKeyRelease(Keyboard.KEY_ESCAPE)
	check("Escape closed the book", window.closing == true)
	eq("and the window is nobody's any more", CeroSecManualUI.instances[0], nil)
end

--
-- The contents page: a row clicked is a chapter opened
--

do
	local item = newItem()
	local window = newWindow(item)
	window:onContents()
	eq("Contents goes to the contents sheet", window.page, 1)

	window:frame()
	check("the contents rows were laid on the glass", #window.hotRows == 3)

	-- What a row PRINTS. A chapter of this book carries its own number in its
	-- title, so a row index printed in front of it reads "1.  1. Your machine".
	-- The row is the title and nothing but the title, and the page number is
	-- still right-aligned at the outer margin of the row.
	for c = 1, #window.book.chapters do
		local title = window.book.chapters[c].title
		local number = tostring(window.book.chapters[c].page)
		local row, num = nil, nil
		for i = 1, #window.painted do
			local paint = window.painted[i]
			if paint.text == title then row = paint end
			if paint.text == number and row ~= nil and paint.y == row.y then num = paint end
		end
		check("contents row " .. c .. " prints the raw title, unprefixed", row ~= nil)
		check("contents row " .. c .. " prints its page number beside it", num ~= nil)
		check("contents row " .. c .. "'s page number is to the right of the title",
			num.x > row.x)
	end

	-- And nothing on the leaf carries a row index in front of a title.
	for i = 1, #window.painted do
		local text = window.painted[i].text
		for c = 1, #window.book.chapters do
			check("no contents row is indexed: " .. tostring(text),
				text ~= tostring(c) .. ".  " .. window.book.chapters[c].title)
		end
	end

	-- Click the third row and land on the third chapter's first leaf.
	local row = window.hotRows[3]
	local handled = window:onMouseDown(row.x + 2, row.y + 2)
	check("the click was taken", handled == true)
	eq("and it opened the third chapter",
		window.page, CeroSecManualBook.clampPage(window.book, window.book.chapters[3].page))

	-- The chapter's own leaf is on this sheet, carrying its running head.
	window:frame()
	local head = false
	for i = 1, #window.painted do
		if window.painted[i].text == window.book.chapters[3].title then head = true end
	end
	check("the chapter's title is on the paper", head)

	-- A click on bare paper is not a click on a row.
	window:goToSheet(3)
	window:frame()
	eq("a text leaf offers no rows to click", #window.hotRows, 0)
end

--
-- Page memory, on the item
--

do
	local item = newItem()
	local window = newWindow(item)
	window:onNext()
	window:onNext()
	local left = window.page
	check("something was written on the item", item.data.page ~= nil)
	eq("and it is the left leaf of the sheet", item.data.page, left)
	window:close()

	-- The same item, opened again: the same two leaves.
	local again = newWindow(item)
	eq("the book opened where it was put down", again.page, left)

	-- Another copy of the book is another bookmark.
	local fresh = newWindow(newItem())
	eq("a different copy opens at the front", fresh.page, 1)

	-- A bookmark somebody scribbled on by hand does not open an empty leaf.
	item.data.page = "seventeen"
	local repaired = newWindow(item)
	eq("junk on the item is the front of the book", repaired.page, 1)
end

--
-- The inventory menu
--

do
	-- A fresh menu per selection, with the game's OWN entries already on it: the
	-- inventory menu is fully built when the event a mod listens on is fired
	-- (ISInventoryPaneContextMenu.lua:935, after Equip, Drop and the More submenu
	-- at :932), so Grab and Equip stand in for what our entries have to be above.
	--
	-- `options` is the leading run of OURS, in the order the glass shows them, which
	-- is what every assertion below reads; `menu` is the whole thing, for the ones
	-- about where the run sits.
	local menu, options
	local function fill(items)
		menu = withVanilla(ContextMenu.new())
		CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, menu, items)
		options = ourOptions(menu)
		return options
	end
	local player = newPlayer()
	_G.getSpecificPlayer = function() return player end

	local manual = newItem()
	local other = newItem("Base.Book")

	fill({ other })
	eq("no option for a book that is not ours", #options, 0)

	fill({ other, manual })
	eq("one option when the manual is in the selection", #options, 1)
	eq("named the way the menu names it", options[1].label, "ContextMenu_CeroSec_ReadUser")
	eq("carrying the manual itself", options[1].target, manual)
	eq("and opening volume one", options[1].arg2, "user")

	-- The single-volume book that shipped BEFORE the set: ONE entry and not two, and
	-- it is volume one's own label -- a second "Read the manual" beside "Read the
	-- User's Guide" would be the menu offering the same book twice under two names,
	-- which is the duplicate the set replaced.
	local legacy = newItem("CeroSec.Manual")
	fill({ legacy })
	eq("the retired book is on the menu", #options, 1)
	eq("under volume one's own label", options[1].label, "ContextMenu_CeroSec_ReadUser")
	eq("carrying that very copy", options[1].target, legacy)
	eq("and opening volume one", options[1].arg2, "user")

	-- And the two together are two entries, in the order the set is printed in: the
	-- Guide first, the book it replaced under it.
	fill({ legacy, manual })
	eq("both books, both entries", #options, 2)
	eq("the Guide first", options[1].target, manual)
	eq("and the retired book under it", options[2].target, legacy)
	-- AND BOTH OF THEM ABOVE THE GAME'S OWN. A book in a survivor's hands is a book
	-- to read, and an entry under Equip and Drop is an entry he scrolls past.
	checkTop("two books", menu,
		{ "ContextMenu_CeroSec_ReadUser", "ContextMenu_CeroSec_ReadUser" })

	-- A stack of identical items arrives as one table with an items array
	-- inside it, not as an InventoryItem. That is the shape that would slip
	-- through a naive loop, so it is the shape the test insists on.
	local stack = { items = { manual, newItem() } }
	fill({ stack })
	eq("a stack of manuals is still one option", #options, 1)
	eq("and it carries the first of the stack", options[1].target, manual)

	-- The handler is what opens the window.
	eq("the option calls the reader", options[1].callback, CeroSecManualMenu.onRead)
	eq("with the player behind it", options[1].arg, player)

	-- Three volumes, three options, each one carrying its OWN item and its own
	-- volume id. One option reading "Read the manual" three times over would be
	-- a menu nobody could use, and an option that carried the wrong id would
	-- open the right survivor at the wrong book.
	local VOLUMES = {
		{ item = "CeroSec.ManualUser", volume = "user",
			label = "ContextMenu_CeroSec_ReadUser" },
		{ item = "CeroSec.ManualAdmin", volume = "admin",
			label = "ContextMenu_CeroSec_ReadAdmin" },
		{ item = "CeroSec.ManualProgrammer", volume = "programmer",
			label = "ContextMenu_CeroSec_ReadProgrammer" },
	}
	local copies = {}
	for v = 1, #VOLUMES do
		copies[v] = newItem(VOLUMES[v].item)
		fill({ other, copies[v] })
		eq(VOLUMES[v].item .. " is one option", #options, 1)
		eq("named after its own volume", options[1].label, VOLUMES[v].label)
		eq("carrying that copy", options[1].target, copies[v])
		eq("and opening that volume", options[1].arg2, VOLUMES[v].volume)
	end

	-- All three in one selection: three options, in the order the set is
	-- printed in and not in whatever order a hash walked them.
	fill({ copies[3], copies[1], copies[2] })
	eq("the whole set is three options", #options, 3)
	for v = 1, #VOLUMES do
		eq("option " .. v .. " is volume " .. v, options[v].arg2, VOLUMES[v].volume)
		eq("option " .. v .. " carries volume " .. v .. "'s own copy",
			options[v].target, copies[v])
	end
	-- The three of them lead the menu, in the order the set is printed in, with the
	-- game's own entries under all three.
	checkTop("the whole set", menu,
		{ VOLUMES[1].label, VOLUMES[2].label, VOLUMES[3].label })

	-- Every label the menu can print is a key the mod ships a string for. A
	-- label nobody translated comes out on the menu as the key itself.
	local handle = assert(io.open("42/media/lua/shared/Translate/EN/ContextMenu.json", "r"))
	local strings = handle:read("*a")
	handle:close()
	for b = 1, #CeroSecManualMenu.BOOKS do
		local key = CeroSecManualMenu.BOOKS[b].label
		check("EN ContextMenu.json defines " .. key,
			string.find(strings, '"' .. key .. '"', 1, true) ~= nil)
	end
end

--
-- THE TELEPHONE DIRECTORY (the phone book work)
--
-- Base.Phonebook gets one entry on the inventory menu and vanilla's Read keeps its
-- own; the copy is stamped with the region it was first opened in and with the
-- exchange of it, once and never again; and what comes back off the server is laid
-- out by the reader as a book with leaves, not as a list in a box.
--
-- The server is not here. What is faked is the ONE call the client makes
-- (CCeroSecSystem.instance:sendCommand) and the one answer it gets back, so what
-- this bench asserts is the client half exactly: what goes out, what is written on
-- the item, and what ends up on the paper.
--

do
	local R = CeroSecOS.PHONE_REGION

	-- A phone book: vanilla's item, with the name the game gives it and a modData
	-- table anything may write into.
	local function newPhonebook()
		local item = newItem(CeroSecPhonebook.ITEM)
		item.displayName = "Phonebook"
		item.getName = function(self) return self.displayName end
		item.setName = function(self, name) self.displayName = name end
		return item
	end

	-- A survivor standing somewhere, which is the whole of what the stamp is made
	-- of.
	local function newReader(x, y)
		local player = newPlayer()
		player.getX = function() return x end
		player.getY = function() return y end
		return player
	end

	-- What went out on the wire, and the answer the server would have sent back.
	local sent = {}
	CCeroSecSystem = { instance = { sendCommand = function(_, playerObj, command, args)
		sent[#sent + 1] = { player = playerObj, command = command, args = args }
	end } }
	local function lastSent()
		return sent[#sent]
	end
	local function answer(entries, capped)
		local out = lastSent()
		CeroSecPhonebookUI.onServerAnswer("listings", {
			token = out.args.token,
			rx = out.args.rx, ry = out.args.ry,
			exchange = CeroSecOS.phoneExchangeOfRegion(out.args.rx, out.args.ry),
			entries = entries or {},
			capped = capped or false,
		})
		return CeroSecManualUI.instances[0]
	end

	--
	-- The menu entry
	--
	-- Same menu as the volumes' own bench above: the game's entries already on it,
	-- and ours read off the leading run.
	local menu, options
	local function fill(items)
		menu = withVanilla(ContextMenu.new())
		CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, menu, items)
		options = ourOptions(menu)
		return options
	end
	local reader = newReader(300.5, 700.5)
	_G.getSpecificPlayer = function() return reader end

	local book = newPhonebook()
	fill({ book })
	eq("a phone book is one option", #options, 1)
	eq("named the way the menu names it", options[1].label,
		"ContextMenu_CeroSec_LookUpNumbers")
	eq("carrying the copy itself", options[1].target, book)
	eq("and it is the look-up and not the reader", options[1].callback,
		CeroSecManualMenu.onLookUp)
	eq("with the survivor behind it", options[1].arg, reader)
	-- And it leads the menu, above vanilla's own Read: looking a number up is what a
	-- survivor opens a phone book for on this mod's machines.
	checkTop("a phone book", menu, { "ContextMenu_CeroSec_LookUpNumbers" })

	-- And nothing else gets it. A manual is not a phone book and a phone book is
	-- not one of the volumes: the entry is on Base.Phonebook and on nothing else.
	fill({ newItem("Base.Book"), newItem("CeroSec.ManualUser") })
	for i = 1, #options do
		check("only the volume is offered here",
			options[i].label ~= "ContextMenu_CeroSec_LookUpNumbers")
	end
	-- The phone book is never one of the volumes, which is the list the bench above
	-- holds to items this mod declares.
	for b = 1, #CeroSecManualMenu.BOOKS do
		check("the phone book is not on the shelf",
			CeroSecManualMenu.BOOKS[b].item ~= CeroSecPhonebook.ITEM)
	end
	-- Every label it can print is a string the mod ships, in both languages.
	for _, lang in ipairs({ "EN", "FR" }) do
		local handle = assert(io.open("42/media/lua/shared/Translate/" .. lang ..
			"/ContextMenu.json", "r"))
		local strings = handle:read("*a")
		handle:close()
		check(lang .. " ContextMenu.json defines the look-up",
			string.find(strings, '"' .. CeroSecManualMenu.PHONEBOOK.label .. '"',
				1, true) ~= nil)
	end
	for _, lang in ipairs({ "EN", "FR" }) do
		local handle = assert(io.open("42/media/lua/shared/Translate/" .. lang ..
			"/IG_UI.json", "r"))
		local strings = handle:read("*a")
		handle:close()
		check(lang .. " IG_UI.json defines the stamped name",
			string.find(strings, '"IGUI_CeroSec_Phonebook_Named"', 1, true) ~= nil)
	end

	--
	-- The edition: stamped once, where it was found
	--
	sent = {}
	CeroSecManualMenu.onLookUp(book, reader)
	local rx, ry = CeroSecPhonebook.regionOn(book.data)
	check("the copy is stamped at all", rx ~= nil and ry ~= nil)
	eq("the copy is stamped with the reader's region",
		tostring(rx) .. "," .. tostring(ry), "0,0")
	local exchange = CeroSecOS.phoneExchangeOfRegion(0, 0)
	eq("and its name carries the exchange", book:getName(),
		"IGUI_CeroSec_Phonebook_Named")
	eq("one look-up is one question to the server", #sent, 1)
	eq("which is the phonebook command", lastSent().command, "phonebook")
	eq("for the region on the copy", lastSent().args.rx .. "," .. lastSent().args.ry, "0,0")
	check("under a token of its own", type(lastSent().args.token) == "string")
	eq("asked as the survivor who is holding it", lastSent().player, reader)

	-- A SECOND OPEN, A REGION AWAY, IS THE SAME BOOK. This is the whole point of
	-- the stamp: a phone book carried across the county is the book of where it was
	-- printed.
	local elsewhere = newReader(R * 3 + 40.5, R * 2 + 12.5)
	local name = book:getName()
	sent = {}
	CeroSecManualMenu.onLookUp(book, elsewhere)
	local again, againY = CeroSecPhonebook.regionOn(book.data)
	eq("the region on the copy has not moved", again .. "," .. againY, "0,0")
	eq("nor has its name been stamped twice", book:getName(), name)
	eq("and it is still region 0,0 that is asked for",
		lastSent().args.rx .. "," .. lastSent().args.ry, "0,0")

	-- A FRESH COPY found over there is that region's book, which is the same rule
	-- read the other way round.
	local other = newPhonebook()
	sent = {}
	CeroSecManualMenu.onLookUp(other, elsewhere)
	eq("a copy found elsewhere is stamped elsewhere",
		lastSent().args.rx .. "," .. lastSent().args.ry, "3,2")
	check("on another exchange", CeroSecOS.phoneExchangeOfRegion(3, 2) ~= exchange)

	--
	-- The reader, on a generated book
	--
	sent = {}
	CeroSecManualMenu.onLookUp(book, reader)
	local window = answer({
		{ name = "Coffee Shop", number = "555-0416" },
		{ name = "Bakery", number = "555-0417" },
		{ name = "Coffee Shop", number = "555-9001" },
	}, false)
	check("the answer opens a reader", window ~= nil)
	eq("on the directory and not on a volume", window.book.title,
		CeroSecPhonebook.TITLE)
	eq("with the copy behind it, so the bookmark has somewhere to go",
		window.item, book)

	-- The book's own leaves: a title leaf, a contents leaf, then the exchange and
	-- the listings.
	check("it has leaves", #window.book.pages >= 4)
	eq("the first is the title leaf", window.book.pages[1].kind, "title")
	eq("the second is the contents", window.book.pages[2].kind, "toc")
	eq("whose one row is the exchange", window.book.pages[2].entries[1].title,
		"Exchange " .. exchange)

	-- What is painted, which is what a player reads. The listings are monospaced
	-- lines, because a column of dot leaders is a column only in a fixed font.
	local seen = {}
	for p = 1, #window.book.pages do
		local page = window.book.pages[p]
		for l = 1, #(page.lines or {}) do
			seen[#seen + 1] = page.lines[l]
		end
	end
	local function lineWith(needle)
		for i = 1, #seen do
			if string.find(seen[i].text, needle, 1, true) then return seen[i] end
		end
		return nil
	end
	check("the preface is on the paper", lineWith("Dial the seven digits") ~= nil)
	local listing = lineWith("Bakery")
	check("the bakery is listed", listing ~= nil)
	check("in the monospaced face", listing.code == true)
	check("with dot leaders between the name and the number",
		string.find(listing.text, "Bakery %.%.%.") ~= nil)
	check("and the number at the end",
		string.sub(listing.text, -8) == "555-0417")
	eq("every listing line is sixty columns", #listing.text, 60)
	check("the number is on no line of prose",
		lineWith("555-0417").code == true)
	-- No coordinates anywhere: where a shop is is not what a directory prints.
	for i = 1, #seen do
		check("no map coordinate on the paper",
			string.find(seen[i].text, "%d%d%d%d,%s*%d%d%d%d") == nil)
	end

	-- Turning it, and the bookmark: a directory is read like any other book.
	local before = window.page
	window:onNext()
	check("the leaves turn", window.page ~= before or
		CeroSecManualBook.sheetCount(window.book) == 1)
	eq("and where it was left is written on the copy",
		book.data[CeroSecManualUI.PAGE_KEY], window.page)

	-- A book with nothing in it opens as a book that says so, never as blank paper
	-- and never as an error.
	window:close()
	sent = {}
	CeroSecManualMenu.onLookUp(newPhonebook(), reader)
	local emptyWindow = answer({}, false)
	check("an exchange with no businesses in it still opens", emptyWindow ~= nil)
	local said = false
	for p = 1, #emptyWindow.book.pages do
		for l = 1, #(emptyWindow.book.pages[p].lines or {}) do
			if string.find(emptyWindow.book.pages[p].lines[l].text,
					"No business listings", 1, true) then said = true end
		end
	end
	check("and says there are none", said)
	emptyWindow:close()

	-- An answer nobody asked for opens nothing. A token is what pairs an answer to
	-- a look-up, and a second answer on a spent token is an answer to a question
	-- already served.
	sent = {}
	CeroSecManualUI.instances[0] = nil
	CeroSecPhonebookUI.onServerAnswer("listings",
		{ token = "never-asked", rx = 0, ry = 0, exchange = exchange, entries = {} })
	eq("an answer to nobody opens no book", CeroSecManualUI.instances[0], nil)

	--
	-- The generator itself, on its own
	--
	eq("camel case comes apart", CeroSecPhonebook.spaced("CoffeeShop"), "Coffee Shop")
	eq("three words too", CeroSecPhonebook.spaced("VariousFoodMarket"),
		"Various Food Market")
	eq("a run of capitals is left alone", CeroSecPhonebook.spaced("PileOCrepe"),
		"Pile OCrepe")
	eq("and one word stays one", CeroSecPhonebook.spaced("Bakery"), "Bakery")
	-- A name too long is cut and never wrapped: a listing on two rows is a listing
	-- whose number belongs to the row above it.
	local long = CeroSecPhonebook.entryLine(string.rep("W", 90), "555-0100")
	eq("a very long name still makes one line of sixty", #long, 60)
	check("ending in its number", string.sub(long, -8) == "555-0100")
	-- Sorted by name and then by number, so a chain's two shops never swap places
	-- between two openings.
	local sorted = CeroSecPhonebook.sorted({
		{ name = "Bakery", number = "555-9999" },
		{ name = "Coffee Shop", number = "555-0002" },
		{ name = "Bakery", number = "555-0001" },
	})
	eq("sorted by name", sorted[1].name .. "|" .. sorted[2].name .. "|" .. sorted[3].name,
		"Bakery|Bakery|Coffee Shop")
	eq("and by number within a name", sorted[1].number, "555-0001")
	-- The cap is TOLD and never guessed: a region with exactly the cap in it is not
	-- a region that was cut.
	local exact = {}
	for i = 1, CeroSecPhonebook.MAX_ENTRIES do
		exact[i] = { name = "Shop", number = "555-" .. string.format("%04d", i) }
	end
	local full = CeroSecPhonebook.volume(exchange, exact, false)
	for p = 1, #full.chapters[1].pages do
		check("a full book that was not cut says nothing about being cut",
			string.find(full.chapters[1].pages[p], "full at", 1, true) == nil)
	end
	-- And every page of a generated book obeys the manual's own two rules, which is
	-- what lets the reader lay it out: a page of at most 1000 characters, and an
	-- example line of at most 60 columns.
	for p = 1, #full.chapters[1].pages do
		local page = full.chapters[1].pages[p]
		check("page " .. p .. " is at most 1000 characters (" .. #page .. ")",
			#page <= 1000)
		for line in (page .. "\n"):gmatch("([^\n]*)\n") do
			if string.sub(line, 1, 2) == "  " then
				check("page " .. p .. " example line fits 60 columns (" .. #line .. ")",
					#line <= 60)
			end
		end
	end
end

-- Double-clicking a volume opens it
--
-- The wrap on ISInventoryPane:doContextualDblClick. Two things to prove and they
-- are not the same thing: our books open the reader, and every other item is
-- handed to the function that was there before -- because a wrap that swallowed
-- the gesture for a screwdriver would break equipping a weapon by double-click
-- for every player with this mod on.
--

do
	local player = newPlayer()
	_G.getSpecificPlayer = function() return player end
	local pane = { player = 0 }

	check("the wrap was put on at load time",
		CeroSecManualMenu.vanillaDblClick ~= nil)
	eq("and it kept the function that was there before",
		CeroSecManualMenu.vanillaDblClick, VANILLA_DBLCLICK)
	check("the pane's function is no longer the original",
		ISInventoryPane.doContextualDblClick ~= VANILLA_DBLCLICK)

	-- Each volume, through the pane's own function -- the one the game calls --
	-- and not through the mod's handler directly: what is under test is the
	-- route, and a bench that called CeroSecManualMenu.doubleClick itself would
	-- pass with the wrap never installed.
	local VOLUMES = { { item = "CeroSec.ManualUser", volume = "user" },
		{ item = "CeroSec.ManualAdmin", volume = "admin" },
		{ item = "CeroSec.ManualProgrammer", volume = "programmer" } }
	for v = 1, #VOLUMES do
		CeroSecManualUI.instances[0] = nil
		ISInventoryPane.dblClicked, ISInventoryPane.dblCalls = {}, 0
		local copy = newItem(VOLUMES[v].item)
		ISInventoryPane.doContextualDblClick(pane, copy)
		local window = CeroSecManualUI.instances[0]
		check("a double-click on " .. VOLUMES[v].item .. " opens the reader",
			window ~= nil)
		eq("on its own volume", window and window.volumeId, VOLUMES[v].volume)
		eq("carrying that copy, so the bookmark is the copy's",
			window and window.item, copy)
		eq("and the original was not called for it", ISInventoryPane.dblCalls, 0)
		window:close()
	end

	-- Anything else falls straight through, with the item as it was given.
	CeroSecManualUI.instances[0] = nil
	ISInventoryPane.dblClicked, ISInventoryPane.dblCalls = {}, 0
	local other = newItem("Base.Screwdriver")
	local answer = ISInventoryPane.doContextualDblClick(pane, other)
	eq("another item goes to the original", ISInventoryPane.dblCalls, 1)
	eq("with the item it was given", ISInventoryPane.dblClicked[1], other)
	eq("and the original's answer is handed back", answer, "vanilla")
	check("no reader was opened for it", CeroSecManualUI.instances[0] == nil)

	-- A vanilla BOOK, not just a tool: the item vanilla's own ladder reads at
	-- ISInventoryPane.lua:1102. Ours must not catch it.
	ISInventoryPane.dblClicked, ISInventoryPane.dblCalls = {}, 0
	local book = newItem("Base.Book")
	ISInventoryPane.doContextualDblClick(pane, book)
	eq("a vanilla book is still vanilla's", ISInventoryPane.dblClicked[1], book)
	check("and no reader opened on it", CeroSecManualUI.instances[0] == nil)

	-- The retired single-volume book. The double-click answers it too -- both doors go
	-- through volumeOf, so a copy in a save opens by the same gesture as the set -- and
	-- the gesture is also what CONVERTS it: the reader that opens is on the User's
	-- Guide the bag now holds and not on the book that has just left it.
	CeroSecManualUI.instances[0] = nil
	ISInventoryPane.dblClicked, ISInventoryPane.dblCalls = {}, 0
	local bag = newContainer()
	local old = newItem("CeroSec.Manual")
	old.container = bag
	bag.held[1] = old
	old:getModData()[CeroSecManualUI.PAGE_KEY] = 4
	ISInventoryPane.doContextualDblClick(pane, old)
	eq("the original was not called for it", ISInventoryPane.dblCalls, 0)
	local opened = CeroSecManualUI.instances[0]
	check("a reader opened", opened ~= nil)
	eq("on volume one", opened and opened.volumeId, "user")
	local grown = bag:holds("CeroSec.ManualUser")
	check("the bag holds the User's Guide now", grown ~= nil)
	eq("and the reader is on THAT copy", opened and opened.item, grown)
	eq("the old book is out of the bag", bag:holds("CeroSec.Manual"), nil)
	eq("it went to the shelf once", bag.added, 1)
	eq("and removed once", bag.removed, 1)
	eq("and the page he was on came with it",
		grown and grown:getModData()[CeroSecManualUI.PAGE_KEY], 4)
	if opened then opened:close() end

	-- A bag that will not take the new book: he keeps the old one and still reads it.
	-- The order of the two halves is the whole of this -- removed first, a survivor who
	-- asked to read a book would be holding neither, and the one he lost is the one
	-- thing in the world nothing can make another of.
	CeroSecManualUI.instances[0] = nil
	local full = newContainer()
	full.refuse = true
	local kept = newItem("CeroSec.Manual")
	kept.container = full
	full.held[1] = kept
	ISInventoryPane.doContextualDblClick(pane, kept)
	eq("it tried, once", full.added, 1)
	eq("and nothing was taken out of the bag", full.removed, 0)
	check("his book is still his", full:holds("CeroSec.Manual") == kept)
	local anyway = CeroSecManualUI.instances[0]
	check("and he is reading it", anyway ~= nil)
	eq("the book he has", anyway and anyway.item, kept)
	eq("on volume one all the same", anyway and anyway.volumeId, "user")
	if anyway then anyway:close() end

	-- Nothing under the cursor, and a pane whose character has gone. Both are
	-- the original's to answer -- a reader opened on a nil player is a window
	-- with no bookmark and no owner.
	ISInventoryPane.dblClicked, ISInventoryPane.dblCalls = {}, 0
	ISInventoryPane.doContextualDblClick(pane, nil)
	eq("a double-click on nothing goes to the original",
		ISInventoryPane.dblCalls, 1)
	_G.getSpecificPlayer = function() return nil end
	ISInventoryPane.dblClicked, ISInventoryPane.dblCalls = {}, 0
	ISInventoryPane.doContextualDblClick(pane, newItem("CeroSec.ManualUser"))
	eq("a pane with no character hands the book back to the original",
		ISInventoryPane.dblCalls, 1)
	check("and opens no reader", CeroSecManualUI.instances[0] == nil)
	_G.getSpecificPlayer = function() return player end

	-- Wrapping twice would make vanillaDblClick point at our own wrapper, and a
	-- double-click on a screwdriver would then recurse until the stack gave out.
	-- So: the second call does nothing, and the pane's function is untouched.
	local wrapped = ISInventoryPane.doContextualDblClick
	eq("a second hook is refused", CeroSecManualMenu.hookDoubleClick(), false)
	eq("and the wrap is the one that was already there",
		ISInventoryPane.doContextualDblClick, wrapped)
	eq("still holding the true original",
		CeroSecManualMenu.vanillaDblClick, VANILLA_DBLCLICK)
	ISInventoryPane.dblClicked, ISInventoryPane.dblCalls = {}, 0
	ISInventoryPane.doContextualDblClick(pane, newItem("Base.Screwdriver"))
	eq("and one call still reaches the original exactly once",
		ISInventoryPane.dblCalls, 1)

	-- Every book on the menu is a book the double-click knows, read off the one
	-- table both doors use. A volume added to the set with no double-click would
	-- be a book you can right-click and not open.
	for b = 1, #CeroSecManualMenu.BOOKS do
		local book2 = CeroSecManualMenu.BOOKS[b]
		eq(book2.item .. " is the same volume on both doors",
			CeroSecManualMenu.volumeOf(book2.item), book2.volume)
	end
	check("and nothing else is one of ours",
		CeroSecManualMenu.volumeOf("Base.Book") == nil)
end

--
-- The testing doors on the computer's menu (CeroSec.DEV_MANUAL_MENU and
-- CeroSec.DEV_DEBUG_MENU)
--
-- One submenu, named for the mod and not for the manual, with a door per volume
-- in it and the debug window last. Each flag decides its own entries and the
-- submenu is there when EITHER of them is on -- which is what makes turning one
-- off before release a change of one line.
--

-- A right-click on the lit computer, built by the block below and used again
-- by the volume block after it -- which asks the same door for three entries
-- instead of one.
local worldMenuOn

do
	-- The world menu is a client file of ours and it is loaded here with the
	-- pieces of the game and of the mod it leans on stood in for. Only what
	-- CeroSecContextMenu actually calls is faked; the sprite names come from
	-- the real CeroSecDefs, so a menu that stopped recognising a computer is a
	-- menu this bench notices.
	local computer = {
		getSpriteName = function() return CeroSec.SPRITES_ON["S"] end,
		getSquare = function() return {
			haveElectricity = function() return true end,
			hasGridPower = function() return true end,
			getRoom = function() return {} end,
			getX = function() return 10 end,
			getY = function() return 20 end,
			getZ = function() return 0 end,
		} end,
	}
	local off = {
		getSpriteName = function() return CeroSec.SPRITES_OFF["S"] end,
		getSquare = computer.getSquare,
	}

	local picked = computer
	CeroSecReach = {
		pickComputer = function() return picked end,
		height = function() return "mid" end,
		canStandInFront = function() return true end,
		walkToFront = function() end,
		chairInFront = function() return nil end,
		isSeatedOn = function() return false end,
	}
	JoypadState = { players = {} }
	ISTimedActionQueue = { add = function() end }
	ISCeroSecToggleAction = { new = function() return {} end }
	ISCeroSecUseAction = { new = function() return {} end }
	ISRestAction = { new = function() return {} end }
	ISWorldObjectContextMenu = {
		Test = false,
		addToolTip = function() return { setVisible = function() end } end,
	}
	local player = newPlayer()
	player.getVehicle = function() return nil end
	_G.getSpecificPlayer = function() return player end

	-- The floppy drive's two entries lean on two things the menu cannot invent:
	-- what the player is carrying, and the one bit the server syncs about the
	-- drive. Both are stood in for here and both are MOVED by the checks below,
	-- which is what makes them checks and not decoration.
	-- A LIST of disks and not one, because the whole of the insert submenu is what
	-- happens when a survivor is carrying more than one. Both lookups are served
	-- off the same list: getFirstTypeRecurse, which the old single entry used, and
	-- getAllTypeRecurse, which the submenu uses (javap zombie.inventory.ItemContainer
	-- -- it hands back an ArrayList, so the fake answers size() and get() from zero
	-- the way a Java list does, and never a Lua array from one).
	-- One disk in a pocket. getName answers the way the engine's does -- the custom
	-- name when there is one written on it, the ordinary item name otherwise (javap
	-- -c zombie.inventory.InventoryItem: getDisplayName is a single getfield on the
	-- same `name` field setName writes) -- because the submenu's entry text is built
	-- from exactly that, and a fake that answered nil for an unlabelled disk would
	-- hide a menu of empty lines.
	local GENERIC = "3.5 inch Floppy Disk"
	local function newDisk(fullType, label)
		return {
			__class = "InventoryItem",
			type = fullType,
			getFullType = function(self) return self.type end,
			getName = function(self) return label or GENERIC end,
			isCustomName = function() return label ~= nil end,
		}
	end

	local carried = {}
	local mirror = { disk = nil }
	local function javaList(t)
		return { size = function() return #t end,
			get = function(_, i) return t[i + 1] end }
	end
	player.getInventory = function()
		return {
			getFirstTypeRecurse = function(_, fullType)
				for i = 1, #carried do
					if carried[i].type == fullType then return carried[i] end
				end
				return nil
			end,
			getAllTypeRecurse = function(_, fullType)
				local hits = {}
				for i = 1, #carried do
					if carried[i].type == fullType then hits[#hits + 1] = carried[i] end
				end
				return javaList(hits)
			end,
		}
	end
	_G.CCeroSecSystem = { instance = {
		getLuaObjectAt = function(_, x, y, z)
			if x ~= 10 or y ~= 20 or z ~= 0 then return nil end
			return mirror
		end,
	} }

	local chunk = assert(loadfile(LUA .. "client/CeroSec/CeroSecContextMenu.lua"))
	chunk()

	-- The whole menu a right-click on one computer builds.
	-- The whole menu a right-click builds, the game's own entries included: the
	-- engine has already filled the menu when the event this listens on is fired
	-- (withVanilla, above), so what the blocks below read is a menu with something
	-- else in it -- which is the only kind of menu "ours are first" means anything
	-- about.
	local function fullMenuOn(target)
		picked = target
		local context = withVanilla(ContextMenu.new())
		CeroSecContextMenu.OnFillWorldObjectContextMenu(0, context, {}, false)
		return context
	end

	local function menuOn(target)
		return fullMenuOn(target).labels
	end

	-- On, with both flags: the machine's own two entries at the TOP of the menu --
	-- the terminal first, because a lit machine is there to be used -- then the
	-- game's own, and the dev submenu LAST of everything.
	CeroSec.DEV_MANUAL_MENU = true
	CeroSec.DEV_DEBUG_MENU = true
	local menu = fullMenuOn(computer)
	local labels = menu.labels
	checkTop("a lit computer", menu,
		{ "ContextMenu_CeroSec_Use", "ContextMenu_CeroSec_TurnOff" })
	eq("a lit computer with both doors is five entries", #labels, 5)
	eq("and the dev submenu is the last of them", labels[#labels],
		"ContextMenu_CeroSec_Dev")
	-- The icon: every first-level CeroSec entry carries it (RED first, see the
	-- CeroSecMenu.lua bench below for the mutation), and it never leaks onto a
	-- row inside a submenu.
	for i = 1, #menu.options do
		local opt = menu.options[i]
		if opt.name == "ContextMenu_CeroSec_Use"
				or opt.name == "ContextMenu_CeroSec_TurnOff"
				or opt.name == "ContextMenu_CeroSec_Dev" then
			check("first-level entry " .. opt.name .. " carries the icon",
				opt.iconTexture ~= nil)
		end
	end
	for i = 1, #menu.subs do
		for j = 1, #menu.subs[i].menu.options do
			check("no submenu row carries the icon",
				menu.subs[i].menu.options[j].iconTexture == nil)
		end
	end

	-- Off: no terminal, so the toggle IS the primary action and leads; and the
	-- submenu is still there and still last, because neither door asks anything of
	-- the computer.
	menu = fullMenuOn(off)
	labels = menu.labels
	checkTop("a dark computer", menu, { "ContextMenu_CeroSec_TurnOn" })
	eq("a dark computer with both doors is four entries", #labels, 4)
	eq("the submenu is still last", labels[#labels], "ContextMenu_CeroSec_Dev")

	-- Without BOTH flags: not an entry to be seen, on either machine. Both,
	-- because either one on is a submenu with something in it.
	CeroSec.DEV_MANUAL_MENU = false
	CeroSec.DEV_DEBUG_MENU = false
	menu = fullMenuOn(computer)
	labels = menu.labels
	checkTop("a lit computer with both flags off", menu,
		{ "ContextMenu_CeroSec_Use", "ContextMenu_CeroSec_TurnOff" })
	eq("with both flags off a lit computer is back to four", #labels, 4)
	for i = 1, #labels do
		check("and none of them is the submenu",
			labels[i] ~= "ContextMenu_CeroSec_Dev")
	end
	menu = fullMenuOn(off)
	labels = menu.labels
	checkTop("a dark computer with both flags off", menu,
		{ "ContextMenu_CeroSec_TurnOn" })
	eq("and a dark one back to three", #labels, 3)

	-- One flag on is a submenu with only that flag's doors in it. The manual's
	-- first: one volume on the bench's shelf, so one entry and nothing else.
	CeroSec.DEV_MANUAL_MENU = true
	CeroSec.DEV_DEBUG_MENU = false
	menu = fullMenuOn(computer)
	eq("the manual flag alone is still a submenu", #menu.subs, 1)
	eq("with the volume in it and nothing else", #menu.subs[1].menu.options, 1)

	-- And the debug flag alone, which is the shape the release is heading for:
	-- the manual is found or it is not read, and the window is a developer's.
	CeroSec.DEV_MANUAL_MENU = false
	CeroSec.DEV_DEBUG_MENU = true
	menu = fullMenuOn(computer)
	eq("the debug flag alone is a submenu too", #menu.subs, 1)
	local only = menu.subs[1].menu.options
	eq("with one entry in it", #only, 1)
	eq("and it is the window", only[1].label, "ContextMenu_CeroSec_DevDebug")
	eq("which opens the debug window", only[1].callback,
		CeroSecContextMenu.onDevDebug)
	eq("on the computer that was right-clicked", only[1].arg, computer)
	eq("and for the player who asked", only[1].target, player)

	CeroSec.DEV_MANUAL_MENU = true
	CeroSec.DEV_DEBUG_MENU = true

	-- The submenu, with both flags: one entry per volume on the shelf and the
	-- debug window LAST behind them. The bench's shelf is one volume, so it is two
	-- entries -- and it is the VOLUME's id that is carried, because there is
	-- nothing behind the shelf for a door onto "the manual in general" to open.
	menu = fullMenuOn(computer)
	eq("the dev door is the only submenu on the menu", #menu.subs, 1)
	eq("and it hangs off the dev entry, which is the last option on the menu",
		menu.subs[1].option, menu.options[#menu.options])
	local sub = menu.subs[1].menu
	eq("one volume and the window, so two entries", #sub.options, 2)
	eq("which opens the reader", sub.options[1].callback,
		CeroSecContextMenu.onDevManual)
	eq("on the volume it names", sub.options[1].arg, "user")
	eq("with the player it belongs to", sub.options[1].target, player)
	eq("and the window is last", sub.options[2].label,
		"ContextMenu_CeroSec_DevDebug")

	-- And the door's own entry does nothing itself: a parent that both opens a
	-- submenu and fires a callback fires it on the way past.
	eq("the door's own entry has no callback of its own",
		menu.options[#menu.options].callback, nil)


--
-- The floppy drive on the computer's menu
--
-- Four states and they are the four a player is ever in: no disk anywhere, a
-- disk in his pocket, a disk in the drive, and one of each. What is checked is
-- which entries appear, in which order, and which of them is greyed out with
-- which reason -- because the greying IS the answer to "why can I not do this",
-- and an entry that is simply missing answers nothing.
--

do
	local menu = fullMenuOn(computer)
	local before = #menu.labels

	-- 1. Nothing anywhere: not an entry to be seen. A player with no disk on him
	-- and a machine with none in it has no business reading about a drive.
	carried, mirror.disk = {}, nil
	local labels = menuOn(computer)
	for i = 1, #labels do
		check("with no disk anywhere there is no Insert", labels[i] ~= "ContextMenu_CeroSec_InsertFloppy")
		check("and no Eject", labels[i] ~= "ContextMenu_CeroSec_EjectFloppy")
	end

	-- 2. A disk in his pocket, an empty drive: Insert, and it works.
	carried = { newDisk(CeroSec.FLOPPY_TYPES[1]) }
	mirror.disk = nil
	menu = fullMenuOn(computer)
	local insert = nil
	for i = 1, #menu.options do
		if menu.labels[i] == "ContextMenu_CeroSec_InsertFloppy" then insert = menu.options[i] end
	end
	check("a disk in the pocket offers Insert", insert ~= nil)
	eq("which is the insert action", insert.callback, CeroSecContextMenu.onInsertFloppy)
	eq("and it is not greyed out", insert.notAvailable, nil)
	-- WHERE the three of them sit: the terminal, the switch, then the drive, all
	-- above the game's own entries and in the order the mod wants them.
	checkTop("a lit machine with a disk in his pocket", menu,
		{ "ContextMenu_CeroSec_Use", "ContextMenu_CeroSec_TurnOff",
			"ContextMenu_CeroSec_InsertFloppy" })
	for i = 1, #menu.labels do
		check("and there is nothing to eject", menu.labels[i] ~= "ContextMenu_CeroSec_EjectFloppy")
	end

	-- 3. A disk in the drive and none in his pocket: Eject, and nothing else.
	carried = {}
	mirror.disk = true
	menu = fullMenuOn(computer)
	local eject = nil
	for i = 1, #menu.options do
		if menu.labels[i] == "ContextMenu_CeroSec_EjectFloppy" then eject = menu.options[i] end
	end
	check("a disk in the drive offers Eject", eject ~= nil)
	eq("which is the eject action", eject.callback, CeroSecContextMenu.onEjectFloppy)
	eq("and it is not greyed out", eject.notAvailable, nil)
	checkTop("a lit machine with a disk in the drive", menu,
		{ "ContextMenu_CeroSec_Use", "ContextMenu_CeroSec_TurnOff",
			"ContextMenu_CeroSec_EjectFloppy" })
	for i = 1, #menu.labels do
		check("and nothing to insert", menu.labels[i] ~= "ContextMenu_CeroSec_InsertFloppy")
	end

	-- 3b. An empty drive the server has SAID is empty. That is a false and not an
	-- absence -- the update that tells a client the disk came out cannot carry a
	-- nil (SCeroSecObject:syncDisk) -- and a menu that read the flag as "there is
	-- something there" would be the eject bug all over again, one layer up.
	carried = { newDisk(CeroSec.FLOPPY_TYPES[1]) }
	mirror.disk = false
	menu = fullMenuOn(computer)
	insert, eject = nil, nil
	for i = 1, #menu.options do
		if menu.labels[i] == "ContextMenu_CeroSec_InsertFloppy" then insert = menu.options[i] end
		if menu.labels[i] == "ContextMenu_CeroSec_EjectFloppy" then eject = menu.options[i] end
	end
	check("a drive the server calls empty offers Insert", insert ~= nil)
	eq("and does not grey it", insert.notAvailable, nil)
	eq("and there is nothing to eject", eject, nil)

	-- 4. One of each. Both entries, Insert greyed with the sentence that says what
	-- to do about it -- and that sentence is the game's UI talking, not Unix: a
	-- refusal a survivor can act on standing where he is.
	carried = { newDisk(CeroSec.FLOPPY_TYPES[3]) }
	mirror.disk = true
	menu = fullMenuOn(computer)
	insert, eject = nil, nil
	for i = 1, #menu.options do
		if menu.labels[i] == "ContextMenu_CeroSec_InsertFloppy" then insert = menu.options[i] end
		if menu.labels[i] == "ContextMenu_CeroSec_EjectFloppy" then eject = menu.options[i] end
	end
	check("both entries are there", insert ~= nil and eject ~= nil)
	-- Four of ours, in the order the mod wants, and a GREYED one is at the top with
	-- the rest: a refusal a survivor can read is a refusal he can read where he is
	-- looking.
	checkTop("one of each", menu,
		{ "ContextMenu_CeroSec_Use", "ContextMenu_CeroSec_TurnOff",
			"ContextMenu_CeroSec_InsertFloppy", "ContextMenu_CeroSec_EjectFloppy" })
	eq("the full drive greys the insert", insert.notAvailable, true)
	-- In RED, and the tag spelled out: a refusal is the one line on a tooltip a
	-- survivor has to see first, and "<RGB:1,0,0> " is what vanilla writes for a
	-- refusal with no description in front of it
	-- (ISUI/ISWorldObjectContextMenu.lua:377).
	eq("with the one sentence that says what to do", insert.toolTip.description,
		"<RGB:1,0,0> Tooltip_CeroSec_DriveFull")
	eq("and the eject is offered", eject.notAvailable, nil)

	-- Out of reach greys both, for the same reason the machine's own two options
	-- are greyed and with the same string.
	local reach = CeroSecReach.canStandInFront
	CeroSecReach.canStandInFront = function() return false end
	carried = { newDisk(CeroSec.FLOPPY_TYPES[1]) }
	mirror.disk = nil
	menu = fullMenuOn(computer)
	insert = nil
	for i = 1, #menu.options do
		if menu.labels[i] == "ContextMenu_CeroSec_InsertFloppy" then insert = menu.options[i] end
	end
	check("out of reach still offers the entry", insert ~= nil)
	eq("greyed", insert.notAvailable, true)
	eq("with the walk's own reason", insert.toolTip.description,
		"<RGB:1,0,0> Tooltip_CeroSec_NoAccess")
	CeroSecReach.canStandInFront = reach

	-- The slot is mechanical: a dark machine takes a disk and gives one back.
	carried = { newDisk(CeroSec.FLOPPY_TYPES[1]) }
	mirror.disk = true
	labels = menuOn(off)
	local sawInsert, sawEject = false, false
	for i = 1, #labels do
		if labels[i] == "ContextMenu_CeroSec_InsertFloppy" then sawInsert = true end
		if labels[i] == "ContextMenu_CeroSec_EjectFloppy" then sawEject = true end
	end
	check("a dark machine still offers Insert", sawInsert)
	check("and still offers Eject", sawEject)

	-- A computer the client has no mirror for says nothing at all: a menu built on
	-- a guess about what is in the drive is a menu that offers to eject nothing.
	local get = CCeroSecSystem.instance.getLuaObjectAt
	CCeroSecSystem.instance.getLuaObjectAt = function() return nil end
	labels = menuOn(computer)
	for i = 1, #labels do
		check("no mirror, no Insert", labels[i] ~= "ContextMenu_CeroSec_InsertFloppy")
		check("no mirror, no Eject", labels[i] ~= "ContextMenu_CeroSec_EjectFloppy")
	end
	CCeroSecSystem.instance.getLuaObjectAt = get

	--
	-- More than one disk: the insert becomes a submenu
	--
	-- A drive has one slot. A survivor with four disks and one entry that silently
	-- took whichever colour came first is the complaint this answers, so from two
	-- disks up the entry is a parent with a line per disk behind it.
	--

	-- The parent option and the submenu hung off it, or nil.
	local function insertSub(m)
		for i = 1, #m.options do
			if m.labels[i] == "ContextMenu_CeroSec_InsertFloppy" then
				for j = 1, #m.subs do
					if m.subs[j].option == m.options[i] then
						return m.options[i], m.subs[j].menu
					end
				end
				return m.options[i], nil
			end
		end
		return nil, nil
	end

	-- ONE disk is still the direct entry it always was: no submenu, and the option
	-- itself carries the disk.
	local only = newDisk(CeroSec.FLOPPY_TYPES[2])
	carried = { only }
	mirror.disk = nil
	menu = fullMenuOn(computer)
	local parent, sub = insertSub(menu)
	check("one disk still offers Insert", parent ~= nil)
	check("with no submenu behind it", sub == nil)
	eq("and the option itself inserts it", parent.callback,
		CeroSecContextMenu.onInsertFloppy)
	eq("carrying that one disk", parent.args[4], only)
	-- FOUR arguments and nothing after them. Not a count of them any more: every
	-- entry of this mod goes on through CeroSecMenu.addTop, which passes vanilla's
	-- whole param1..param10 tail along because ISContextMenu:addOption spells the
	-- ten out itself (:873) and any of them may be nil. So what is asserted is that
	-- the fifth slot is empty -- the disk is the last thing the option carries.
	eq("and nothing after the disk", parent.args[5], nil)

	-- THREE disks: one parent, three entries, each carrying its OWN disk. An entry
	-- that carried the wrong one would be a menu that inserts a disk the survivor
	-- did not pick, which is the bug with a menu in front of it.
	local blue = newDisk(CeroSec.FLOPPY_TYPES[1])
	local red = newDisk(CeroSec.FLOPPY_TYPES[3])
	local green = newDisk(CeroSec.FLOPPY_TYPES[4], "PAYROLL")
	carried = { blue, red, green }
	mirror.disk = nil
	menu = fullMenuOn(computer)
	parent, sub = insertSub(menu)
	check("three disks offer Insert", parent ~= nil)
	check("as a submenu", sub ~= nil)
	eq("hung off that very option", sub.hungOff, parent)
	eq("the parent itself does nothing", parent.callback, nil)
	eq("and is not greyed", parent.notAvailable, nil)
	eq("three entries, one per disk", #sub.options, 3)
	-- The order is the order the four colours come in, which is stable from one
	-- right-click to the next: blue, yellow, red, green. Two of the three carried
	-- here are out of that order on purpose.
	local want = { blue, red, green }
	for d = 1, 3 do
		eq("entry " .. d .. " inserts a disk", sub.options[d].callback,
			CeroSecContextMenu.onInsertFloppy)
		eq("entry " .. d .. " carries its own disk", sub.options[d].args[4], want[d])
		eq("entry " .. d .. " names the same computer", sub.options[d].args[1], computer)
	end

	-- What the entries READ. The label first when there is one, and the colour
	-- always -- four unlabelled disks with no colour on them would be four
	-- identical lines, which is the menu this replaces.
	eq("an unlabelled disk reads as its item name and its colour",
		sub.labels[1], "3.5 inch Floppy Disk (IGUI_CeroSec_ColourBlue)")
	eq("the red one says red", sub.labels[2],
		"3.5 inch Floppy Disk (IGUI_CeroSec_ColourRed)")
	eq("and a labelled disk puts the handwriting first",
		sub.labels[3], "PAYROLL (IGUI_CeroSec_ColourGreen)")

	-- AND THE TWO KINDS OF STICKER READ AS THEMSELVES on this menu, which is the
	-- one screen where a survivor chooses between disks. A found program names its
	-- product and its version; a found man's disk says what he wrote on it. The two
	-- strings are written out rather than asked of the catalogue: what is proved
	-- here is that the submenu prints the item's NAME, and a bench that fetched the
	-- same name the code fetches could not see that stop happening.
	carried = { newDisk(CeroSec.FLOPPY_TYPES[1], "CeroSec UTILITIES 1.0"),
		newDisk(CeroSec.FLOPPY_TYPES[2], "my files - july") }
	menu = fullMenuOn(computer)
	parent, sub = insertSub(menu)
	eq("a printed disk names its product on the insert menu", sub.labels[1],
		"CeroSec UTILITIES 1.0 (IGUI_CeroSec_ColourBlue)")
	eq("and a handwritten one says what he wrote", sub.labels[2],
		"my files - july (IGUI_CeroSec_ColourYellow)")

	-- Two disks of the SAME colour: still two entries. A survivor keeps three blue
	-- disks as readily as one of each, and a lookup that asked for the first of each
	-- type would offer him one.
	carried = { newDisk(CeroSec.FLOPPY_TYPES[1], "A"), newDisk(CeroSec.FLOPPY_TYPES[1], "B") }
	menu = fullMenuOn(computer)
	parent, sub = insertSub(menu)
	eq("two disks of one colour are two entries", #sub.options, 2)
	eq("the first is the first", sub.labels[1], "A (IGUI_CeroSec_ColourBlue)")
	eq("and the second the second", sub.labels[2], "B (IGUI_CeroSec_ColourBlue)")

	-- A full drive with three disks on him: ONE greyed line carrying the reason, and
	-- no submenu at all. A greyed parent over a list of disks invites a pick and then
	-- refuses it; the line he needs to read is the reason.
	carried = { blue, red, green }
	mirror.disk = true
	menu = fullMenuOn(computer)
	parent, sub = insertSub(menu)
	check("the entry is still there", parent ~= nil)
	check("with nothing to choose between", sub == nil)
	eq("greyed", parent.notAvailable, true)
	eq("with the drive's own reason", parent.toolTip.description,
		"<RGB:1,0,0> Tooltip_CeroSec_DriveFull")
	eq("and nothing on it to fire", parent.callback, nil)

	-- Out of reach, same shape and the walk's own reason.
	local reach2 = CeroSecReach.canStandInFront
	CeroSecReach.canStandInFront = function() return false end
	mirror.disk = nil
	menu = fullMenuOn(computer)
	parent, sub = insertSub(menu)
	check("out of reach keeps the entry", parent ~= nil)
	check("and drops the submenu", sub == nil)
	eq("greyed with the walk's reason", parent.toolTip.description,
		"<RGB:1,0,0> Tooltip_CeroSec_NoAccess")
	CeroSecReach.canStandInFront = reach2

	-- floppiesOn itself: the order, and every copy.
	carried = { green, blue, red }
	local all = CeroSecContextMenu.floppiesOn(player)
	eq("every disk he carries", #all, 3)
	eq("blue first", all[1], blue)
	eq("then red", all[2], red)
	eq("then green", all[3], green)
	carried = {}
	eq("and nothing when he carries none", #CeroSecContextMenu.floppiesOn(player), 0)

	-- diskEntry on something that is not one of the four: the name alone, with no
	-- empty brackets after it.
	eq("a disk of no colour reads as its name alone",
		CeroSecContextMenu.diskEntry(newDisk("Base.Hammer", "X")), "X")

	-- The four colour words are keys the mod ships strings for, in both languages.
	for _, lang in ipairs({ "EN", "FR" }) do
		local handle = assert(io.open(
			"42/media/lua/shared/Translate/" .. lang .. "/IG_UI.json", "r"))
		local strings = handle:read("*a")
		handle:close()
		for t = 1, #CeroSec.FLOPPY_TYPES do
			local key = CeroSec.floppyColourKey(CeroSec.FLOPPY_TYPES[t])
			check(lang .. " IG_UI.json defines " .. tostring(key),
				key ~= nil and string.find(strings, '"' .. key .. '"', 1, true) ~= nil)
		end
	end

	carried = {}
	mirror.disk = nil

	-- Every label the drive can print is a key the mod ships a string for, in both
	-- languages: a label nobody translated comes out on the menu as the key.
	for _, lang in ipairs({ "EN", "FR" }) do
		local handle = assert(io.open(
			"42/media/lua/shared/Translate/" .. lang .. "/ContextMenu.json", "r"))
		local strings = handle:read("*a")
		handle:close()
		for _, key in ipairs({ "ContextMenu_CeroSec_InsertFloppy",
				"ContextMenu_CeroSec_EjectFloppy" }) do
			check(lang .. " ContextMenu.json defines " .. key,
				string.find(strings, '"' .. key .. '"', 1, true) ~= nil)
		end
	end
	local handle = assert(io.open("42/media/lua/shared/Translate/EN/Tooltip.json", "r"))
	local strings = handle:read("*a")
	handle:close()
	check("EN Tooltip.json defines the drive's own refusal",
		string.find(strings, '"Tooltip_CeroSec_DriveFull"', 1, true) ~= nil)

	carried, mirror.disk = {}, nil
	eq("and the menu is back where it started", #menuOn(computer), before)
end

	-- Kept for the volume block below, which builds this same menu on this same
	-- lit computer against a shelf of three.
	worldMenuOn = function() return fullMenuOn(computer) end
end

--
-- A book with no copy behind it: the door's own bookmark
--

do
	-- The door opens the reader with no item. There is nowhere on an item to
	-- write where it was left, so the bookmark is the module's -- and it must
	-- be a DIFFERENT bookmark from any copy's, or turning the pages of a book
	-- nobody owns would move somebody's real one.
	CeroSecManualUI.devPages = {}

	local item = newItem()
	local owned = newWindow(item)
	owned:onNext()
	owned:onNext()
	local ownedPage = owned.page
	owned:close()

	local dev = CeroSecManualUI:new(0, 0, newPlayer(), nil, nil)
	eq("a book with no copy opens at the front", dev.page, 1)
	check("and not where the owned copy was left", ownedPage ~= 1)

	dev:onNext()
	local devPage = dev.page
	eq("its bookmark went on the module, filed under the book it really opened",
		CeroSecManualUI.devPages["user"], devPage)
	eq("and the copy's own is untouched", item.data.page, ownedPage)
	check("the two bookmarks are not the same", devPage ~= ownedPage)

	-- Opened again, it comes back to its own page.
	local again = CeroSecManualUI:new(0, 0, newPlayer(), nil, nil)
	eq("the door reopens where the door left off", again.page, devPage)

	-- And the copy still opens on the copy's page.
	local reopened = newWindow(item)
	eq("the owned copy is where it always was", reopened.page, ownedPage)

	-- Nothing to leave anybody's hands, so nothing shuts it but the player.
	check("a book with no copy stays open", again:stillValid() == true)
	again.playerObj.isDead = function() return true end
	check("a dead reader closes it", again:stillValid() == false)

	CeroSecManualUI.devPages = {}
end

--
-- The set: three volumes on one shelf
--
-- The real text is three files the bench never reads, so the shelf here is the
-- bench's own: three volumes of two chapters each, deliberately of different
-- lengths, so a reader that opened the wrong one is a reader with the wrong
-- number of chapters and the wrong words on the paper.
--

do
	local real = CeroSecManual
	local realOS = CeroSecOS

	-- The core, for the stamp. The manual files load before it does, which is
	-- the whole reason the cover is stamped at read time and not written into
	-- the table -- so the bench has a version to stamp WITH.
	CeroSecOS = { VERSION = "1.0" }

	local function volume(id, name, one, two)
		return {
			id = id, title = nil, name = name,
			edition = "First Edition, 1993",
			-- Three authored pages to a chapter, so a volume is several sheets
			-- thick. A volume of two short chapters is two sheets, and two
			-- readers turned to different places in a two-sheet book land on
			-- the same one -- which would make a bookmark that was shared look
			-- exactly like a bookmark that was not.
			chapters = {
				{ title = "1. " .. one, pages = {
					one .. " is where it starts.",
					one .. " goes on from there.",
					one .. " is done with." } },
				{ title = "2. " .. two, pages = {
					two .. " is where it ends.",
					two .. " goes on from there.",
					two .. " is done with." } },
			},
		}
	end

	CeroSecManual = { volumes = {
		volume("user", "User's Guide", "Your machine", "The shell"),
		volume("admin", "System Administrator's Guide", "Accounts", "Backups"),
		volume("programmer", "Programmer's Guide", "The script", "The devices"),
	} }

	eq("the shelf is three volumes", #CeroSecManualBook.shelf(), 3)

	-- Each volume opens as itself: its own cover, its own edition, its own two
	-- chapters, and its own words on its own leaves.
	for v = 1, 3 do
		local want = CeroSecManual.volumes[v]
		local window = newVolumeWindow(want.id, newItem())

		eq(want.id .. " is the book that opened", window.bookId, want.id)
		eq(want.id .. "'s cover is stamped with the version and its own name",
			window.book.title, "CeroSec OS 1.0 " .. want.name)
		eq(want.id .. " wears that title on the window", window.titleText,
			"CeroSec OS 1.0 " .. want.name)
		eq(want.id .. "'s cover carries its edition", window.book.edition,
			"First Edition, 1993")
		eq(want.id .. " has two chapters", #window.book.chapters, 2)
		for c = 1, 2 do
			eq(want.id .. " chapter " .. c .. " is its own",
				window.book.chapters[c].title, want.chapters[c].title)
		end

		-- The contents leaf lists that volume's chapters and nobody else's.
		window:onContents()
		window:frame()
		eq(want.id .. "'s contents has two rows", #window.hotRows, 2)
		local titles = {}
		for i = 1, #window.painted do titles[window.painted[i].text] = true end
		for c = 1, 2 do
			check(want.id .. "'s contents prints " .. want.chapters[c].title,
				titles[want.chapters[c].title] == true)
		end
		for w = 1, 3 do
			if w ~= v then
				local other = CeroSecManual.volumes[w]
				check(want.id .. "'s contents does not print " .. other.chapters[1].title,
					titles[other.chapters[1].title] ~= true)
			end
		end

		-- And the words of its own first chapter are the words on its leaf.
		window:goToPage(window.book.chapters[1].page)
		window:frame()
		local onPaper = {}
		for i = 1, #window.painted do onPaper[window.painted[i].text] = true end
		check(want.id .. " prints its own first page",
			onPaper[want.chapters[1].pages[1]] == true)
	end

	-- Stamping is idempotent and reaches the volume itself, so a second reader
	-- opened on the same volume is not a second concatenation.
	local once = CeroSecManualBook.volume("admin").title
	local twice = CeroSecManualBook.volume("admin").title
	eq("stamping twice stamps the same cover", twice, once)

	-- An id nothing on the shelf answers to is not a book, and there is nothing
	-- behind the shelf to fall back on any more: the reader opens blank paper and
	-- says so in the log, because a shelf that cannot answer an id is a volume
	-- file that did not load and not a state the game has.
	eq("an unknown id is nobody's volume", CeroSecManualBook.volume("editor"), nil)
	local fallen = newVolumeWindow("editor", newItem())
	eq("a reader asked for a volume that is not there is filed under what it asked",
		fallen.bookId, "editor")
	eq("and holds no chapters at all", #fallen.book.chapters, 0)

	-- Nothing said about the volume is volume one: "read the manual" with
	-- nobody saying which.
	eq("no volume named is the first one", newVolumeWindow(nil, newItem()).bookId, "user")

	--
	-- A bookmark belongs to a COPY, and two copies of two volumes are two
	-- bookmarks. This is the one that would pass unnoticed if the reader wrote
	-- its place under a key it shared: both books would open on whichever was
	-- put down last.
	--
	do
		local userCopy = newItem("CeroSec.ManualUser")
		local progCopy = newItem("CeroSec.ManualProgrammer")

		local user = newVolumeWindow("user", userCopy)
		user:onNext()
		user:onNext()
		local userPage = user.page
		user:close()

		local prog = newVolumeWindow("programmer", progCopy)
		eq("the other volume's copy opens at the front", prog.page, 1)
		prog:onNext()
		local progPage = prog.page
		prog:close()

		check("the two copies are on different leaves", userPage ~= progPage)
		eq("the User's Guide kept its own place", userCopy.data.page, userPage)
		eq("the Programmer's Guide kept its own", progCopy.data.page, progPage)

		eq("and each reopens where it was put down",
			newVolumeWindow("user", userCopy).page, userPage)
		eq("each, separately",
			newVolumeWindow("programmer", progCopy).page, progPage)
	end

	--
	-- The door's own bookmarks, one per volume. There is no item to write on,
	-- so they live on the module -- and a single one of them would move the
	-- reader's place in all three books at once.
	--
	do
		CeroSecManualUI.devPages = {}

		local admin = newVolumeWindow("admin", nil)
		admin:onNext()
		local adminPage = admin.page
		eq("the door's place in the admin volume is filed under it",
			CeroSecManualUI.devPages.admin, adminPage)
		eq("and it wrote nothing against any other volume",
			CeroSecManualUI.devPages.user, nil)

		local user = newVolumeWindow("user", nil)
		eq("the door opens another volume at its front", user.page, 1)
		eq("without having moved the first", CeroSecManualUI.devPages.admin, adminPage)

		eq("and comes back to the admin volume where it left it",
			newVolumeWindow("admin", nil).page, adminPage)

		CeroSecManualUI.devPages = {}
	end

	--
	-- The door, against a shelf of three: three entries, one per volume, each
	-- one named the way its volume names itself and each one carrying its own
	-- id.
	--
	do
		CeroSec.DEV_MANUAL_MENU = true
		CeroSec.DEV_DEBUG_MENU = true
		local menu = worldMenuOn()
		eq("the door is still one entry on the machine's own menu", #menu.labels, 5)
		eq("and still last", menu.labels[#menu.labels], "ContextMenu_CeroSec_Dev")
		eq("still exactly one submenu", #menu.subs, 1)
		eq("hung off the door", menu.subs[1].option, menu.options[#menu.options])

		local sub = menu.subs[1].menu
		eq("three volumes and the window, so four entries", #sub.options, 4)
		eq("with the window last", sub.options[4].label,
			"ContextMenu_CeroSec_DevDebug")
		for v = 1, 3 do
			local want = CeroSecManual.volumes[v]
			eq("entry " .. v .. " is named after its volume", sub.options[v].label,
				want.name)
			eq("entry " .. v .. " opens the reader", sub.options[v].callback,
				CeroSecContextMenu.onDevManual)
			eq("entry " .. v .. " carries its own id", sub.options[v].arg, want.id)
		end
	end

	CeroSecManual = real
	CeroSecOS = realOS
end

--
-- The item script: the keys the game will be asked to parse
--

do
	local path = "common/media/scripts/items_cerosec.txt"
	local handle = io.open(path, "r")
	check("the item script is where the mod says it is", handle ~= nil)
	local text = handle:read("*a")
	handle:close()

	-- Braces balance. Counted OUTSIDE comments, because the comment at the top
	-- of the file talks about blocks and would otherwise be counted as one.
	local code = string.gsub(text, "/%*.-%*/", "")
	local opens, closes = 0, 0
	for _ in string.gmatch(code, "{") do opens = opens + 1 end
	for _ in string.gmatch(code, "}") do closes = closes + 1 end
	eq("braces balance", opens, closes)
	-- The module, the three books, the four disks, the NINE hardware modules, the
	-- book that teaches them, the RETIRED single book -- which is declared and is
	-- not loot, because dropping an item block deletes every copy of it in every
	-- save -- the sticky note a password is written on, and the small motor the
	-- modules that MOVE something are built around (the game ships no motor item
	-- at all).
	eq("twenty-one blocks: the module, the three books, the retired one, the "
		.. "four disks, the nine hardware modules, the Field Wiring Guide, the "
		.. "note and the small motor",
		opens, 21)

	check("it declares the module the loot table names",
		string.find(code, "module CeroSec", 1, true) ~= nil)

	-- Each item block on its own, by name: a file read as one lump would let a
	-- key missing from the third book be answered by the first book's copy of
	-- it, which is the whole of what this check exists to catch.
	local blocks = {}
	for name, body in string.gmatch(code, "item%s+([A-Za-z]+)%s*(%b{})") do
		blocks[name] = body
	end

	-- The three volumes, and those only. The single book that shipped before
	-- them was a second copy of volume one under another name and is gone.
	local BOOKS = {
		{ item = "ManualUser", icon = "CeroSecManualUser",
			name = "CeroSec OS User's Guide" },
		{ item = "ManualAdmin", icon = "CeroSecManualAdmin",
			name = "CeroSec OS System Administrator's Guide" },
		{ item = "ManualProgrammer", icon = "CeroSecManualProgrammer",
			name = "CeroSec OS Programmer's Guide" },
	}
	eq("three item blocks and no more", #BOOKS, 3)

	-- And the retired one, which is DECLARED and is not one of the set.
	--
	-- Asserted here rather than left out, because the two halves of the promise are
	-- easy to half-keep: a change that dropped the block would delete every copy in
	-- every save (the reasoning is in the script, traced through the jar), and a change
	-- that put it back into BOOKS or into the loot tables would be printing a book
	-- CeroSec Systems stopped printing.
	check("the retired single-volume item is still declared", blocks.Manual ~= nil)
	eq("under volume one's own name", string.match(blocks.Manual,
		"DisplayName%s*=%s*([^,\n]+),"), "CeroSec OS User's Manual")
	eq("and its own icon, so a copy in a crate looks like the book it was",
		string.match(blocks.Manual, "Icon%s*=%s*([^,\n]+),"), "CeroSecManual")
	check("its icon is a file the mod ships",
		io.open("common/media/textures/Item_CeroSecManual.png", "r") ~= nil)
	local inSet = false
	for m = 1, #CeroSecManualMenu.BOOKS do
		if CeroSecManualMenu.BOOKS[m].item == "CeroSec.Manual" then inSet = true end
	end
	check("it is NOT one of the three on the shelf", not inSet)
	eq("but the menu opens it as volume one",
		CeroSecManualMenu.volumeOf("CeroSec.Manual"), "user")
	eq("and reading one turns it into the Guide",
		CeroSecManualMenu.LEGACY.becomes, "CeroSec.ManualUser")
	check("and the item it becomes is declared too",
		blocks[string.match(CeroSecManualMenu.LEGACY.becomes, "^CeroSec%\.(.+)$")] ~= nil)

	--
	-- AND THE RETIRED STICKY NOTE, which is the second half-kept promise waiting to
	-- happen. Nothing is written as CeroSec.StickyNote any more -- a note is
	-- vanilla's Base.SheetPaper2 now, so that the game reads it, a pen overwrites it
	-- and a fireplace burns it -- but copies of it are lying in drawers of saves
	-- already played. The block has to still be there, and it has to still be a real
	-- item: Obsolete = true is a real script key and it stops the type spawning, but
	-- it also makes DictionaryInfo.isValid() answer false, which is the very test
	-- that DELETES the saved copy. Retired means kept, not flagged.
	--
	check("the retired sticky note is still declared", blocks.StickyNote ~= nil)
	check("and it is not obsoleted, which would delete every copy in every save",
		string.find(blocks.StickyNote or "", "Obsolete", 1, true) == nil)
	eq("with the shape it was saved with, or an old note loads as something else",
		string.match(blocks.StickyNote, "ItemType%s*=%s*([^,\n]+),"), "base:normal")
	eq("and its own name", string.match(blocks.StickyNote,
		"DisplayName%s*=%s*([^,\n]+),"), "Sticky Note")
	eq("and the icon every note still wears",
		string.match(blocks.StickyNote, "Icon%s*=%s*([^,\n]+),"), "CeroSecStickyNote")
	check("which is a file the mod ships",
		io.open("common/media/textures/Item_CeroSecStickyNote.png", "r") ~= nil)
	-- And no item block of ours replaced it: the paper a note is written on is the
	-- GAME's, which is the whole of why it can be read, written on and burnt.
	check("and no CeroSec note item took its place", blocks.Note == nil)

	for b = 1, #BOOKS do
		local book = BOOKS[b]
		local body = blocks[book.item]
		check("the script declares item " .. book.item, body ~= nil)

		local keys = {}
		for key, value in string.gmatch(body or "", "([A-Za-z]+)%s*=%s*([^,\n]+),") do
			keys[key] = value
		end
		for _, key in ipairs({ "DisplayName", "DisplayCategory", "ItemType",
				"Weight", "Icon", "StaticModel", "WorldStaticModel" }) do
			check(book.item .. " sets " .. key, keys[key] ~= nil)
		end
		eq(book.item .. " is a plain item, so vanilla adds no Read of its own",
			keys.ItemType, "base:normal")
		eq(book.item .. " is filed under Literature all the same",
			keys.DisplayCategory, "Literature")
		eq(book.item .. " is named the way the set names it",
			keys.DisplayName, book.name)
		eq(book.item .. " carries its own binding on the icon", keys.Icon, book.icon)
		eq(book.item .. " has a model in the hand", keys.StaticModel, "Book")
		eq(book.item .. " has one on the ground", keys.WorldStaticModel,
			"BookClosedGround")

		-- Icon = Foo is media/textures/Item_Foo.png, so the file has to be there
		-- under exactly that name. A volume whose icon is missing is a white
		-- question mark in the inventory and nothing logged.
		local png = io.open("common/media/textures/Item_" .. keys.Icon .. ".png", "r")
		check(book.item .. "'s icon is a file the mod ships", png ~= nil)
		if png then png:close() end

		-- And the three volumes are three DIFFERENT icons: three items pointing
		-- at one texture would look exactly like a set on the shelf and exactly
		-- the same in the pack.
		for c = 1, b - 1 do
			check(book.item .. " does not share " .. BOOKS[c].item .. "'s icon",
				book.icon ~= BOOKS[c].icon)
		end

		-- The name the game builds is the module and the item, and it is what
		-- the menu maps to a volume and the loot table inserts.
		local fullType = "CeroSec." .. book.item
		local mapped = false
		for m = 1, #CeroSecManualMenu.BOOKS do
			if CeroSecManualMenu.BOOKS[m].item == fullType then mapped = true end
		end
		check(fullType .. " is a book the inventory menu knows how to open", mapped)
	end

	-- Every line inside a block ends in a comma: the one syntax slip in a
	-- script file that costs the whole file.
	for line in string.gmatch(code, "[^\n]+") do
		local body = string.match(line, "^%s*([A-Za-z][^\n]-)%s*$")
		if body and string.find(body, "=", 1, true) then
			check("this line ends in a comma: " .. body,
				string.sub(body, -1) == ",")
		end
	end

	-- The item names in the mod's Lua are names the script really declares.
	-- This is the pair that goes wrong silently: a typo in either half is a
	-- loot table filling shelves with an item that does not exist, or a menu
	-- offering to open a book nobody can hold.
	for m = 1, #CeroSecManualMenu.BOOKS do
		local fullType = CeroSecManualMenu.BOOKS[m].item
		local short = string.match(fullType, "^CeroSec%.(.+)$")
		check(fullType .. " is declared in the item script", blocks[short] ~= nil)
	end
end

--
-- The loot table
--

do
	-- The distributions file is a server file and does not go through the UI
	-- fake, so it is loaded here with the two globals it touches standing in.
	ProceduralDistributions = { list = {} }
	local KEYS = { "LibraryComputer", "UniversityLibraryComputer", "BookstoreComputer",
		"CyberCafeFilingCabinet", "CyberCafeDesk", "ControlRoomCounter",
		"UniversityDesk_Computer", "ElectronicStoreMagazines", "OfficeDesk",
		"OfficeShelfSupplies", "CrateBooks", "LivingRoomShelf" }
	for i = 1, #KEYS do
		ProceduralDistributions.list[KEYS[i]] = { rolls = 4, items = { "Something", 10 } }
	end

	local chunk = assert(loadfile(LUA .. "server/CeroSec/CeroSecManualLoot.lua"))
	chunk()

	eq("the file hooked the first distribution event",
		#Events.OnPreDistributionMerge.handlers, 1)

	local VOLUMES = CeroSecManualLoot.VOLUMES
	eq("three volumes go on the shelves", #VOLUMES, 3)

	local added = CeroSecManualLoot.add()
	eq("every list named was found and filled by every volume",
		added, #KEYS * #VOLUMES)

	for i = 1, #KEYS do
		local key = KEYS[i]
		local items = ProceduralDistributions.list[key].items
		eq(key .. " kept what was already in it", items[1], "Something")
		eq(key .. " still has an even number of entries", #items % 2, 0)
		eq(key .. " grew by one name and one weight per volume",
			#items, 2 + 2 * #VOLUMES)

		-- The three volumes, in the order the set is printed, each with the
		-- share of volume one's weight it was given.
		for v = 1, #VOLUMES do
			local volume = VOLUMES[v]
			local at = 2 + (v - 1) * 2 + 1
			eq(key .. " has " .. volume.item .. " in place " .. v, items[at],
				volume.item)
			local share = (volume.raised and volume.raised[key]) or volume.share
			eq(key .. " gave " .. volume.item .. " its share of volume one's weight",
				items[at + 1], CeroSecManualLoot.WEIGHTS[key] * share)
		end

		-- And the book that shipped before the set is not on any shelf: it is
		-- still an item, because it is in saves, but nothing spawns it.
		for n = 1, #items, 2 do
			check(key .. " does not spawn the legacy book",
				items[n] ~= "CeroSec.Manual")
		end
	end

	-- Volume one is the weight the table was measured at, volume two is half of
	-- it and volume three a quarter -- except where the programmers were.
	eq("volume one is the weight in the table", VOLUMES[1].share, 1)
	eq("volume two is half of it", VOLUMES[2].share, 0.5)
	eq("volume three is a quarter", VOLUMES[3].share, 0.25)
	local RAISED = { "UniversityLibraryComputer", "UniversityDesk_Computer",
		"BookstoreComputer", "ElectronicStoreMagazines" }
	for r = 1, #RAISED do
		eq("volume three is raised at " .. RAISED[r],
			VOLUMES[3].raised[RAISED[r]], 0.5)
	end
	for v = 1, #VOLUMES do
		for key in pairs(VOLUMES[v].raised or {}) do
			check("a raise names a list that is in the table: " .. key,
				CeroSecManualLoot.WEIGHTS[key] ~= nil)
		end
	end

	-- The shares are halves and quarters so that no weight is a float that
	-- nearly is what it says it is. The rarest list is the one that would show
	-- it first.
	eq("the rarest weight in the set is exact",
		CeroSecManualLoot.WEIGHTS.LivingRoomShelf * VOLUMES[3].share, 0.025)

	-- Fired twice -- a Lua reload does that -- and nothing doubles.
	local lengths = {}
	for i = 1, #KEYS do
		lengths[i] = #ProceduralDistributions.list[KEYS[i]].items
	end
	CeroSecManualLoot.added = false
	eq("a second pass adds nothing", CeroSecManualLoot.add(), 0)
	for i = 1, #KEYS do
		eq(KEYS[i] .. " was not doubled",
			#ProceduralDistributions.list[KEYS[i]].items, lengths[i])
	end

	-- A list vanilla renamed is a list that is skipped, not a crash.
	CeroSecManualLoot.added = false
	ProceduralDistributions.list.LibraryComputer = nil
	eq("a missing list is skipped quietly", CeroSecManualLoot.add(), 0)

	--
	-- The sandbox option, if a sandbox option file ever declares one. Nothing
	-- declares it yet, and the point of the check is that a mod reading a var
	-- nobody declared must not be a mod that spawns nothing.
	--
	eq("with no sandbox group at all the multiplier is one",
		CeroSecManualLoot.abundance(), 1)

	SandboxVars = {}
	eq("with a SandboxVars but no group of ours it is still one",
		CeroSecManualLoot.abundance(), 1)

	SandboxVars.CeroSec = {}
	eq("with a group but no option it is still one",
		CeroSecManualLoot.abundance(), 1)

	-- Every value that is not an abundance is ignored rather than argued with:
	-- each of these, taken at face value, empties Knox County of the book.
	for _, bad in ipairs({ 0, -1, "lots", true }) do
		SandboxVars.CeroSec.LootAbundance = bad
		eq("a LootAbundance of " .. tostring(bad) .. " is not an abundance",
			CeroSecManualLoot.abundance(), 1)
	end

	SandboxVars.CeroSec.LootAbundance = 2
	eq("a number is the number", CeroSecManualLoot.abundance(), 2)

	-- And it reaches the weights, on a shelf of its own: a multiplier read and
	-- then not used would leave every assertion above green.
	ProceduralDistributions.list = { LibraryComputer = { rolls = 4, items = {} } }
	CeroSecManualLoot.added = false
	CeroSecManualLoot.add()
	local items = ProceduralDistributions.list.LibraryComputer.items
	for v = 1, #VOLUMES do
		local share = VOLUMES[v].share
		eq("volume " .. v .. "'s weight was doubled with the shelves",
			items[v * 2], CeroSecManualLoot.WEIGHTS.LibraryComputer * share * 2)
	end

	SandboxVars = nil
end


--
-- The floppy disks: four items, four icons, four models, and the files behind
-- every one of them.
--
-- Same reading as the books above and for the same reason -- a key missing from
-- the third disk must not be answered by the first disk's copy of it -- plus the
-- two things a disk has that a book does not: a model block of its own in
-- models_cerosec.txt, and the mesh and texture files that block names.
--

do
	local path = "common/media/scripts/items_cerosec.txt"
	local handle = io.open(path, "r")
	check("the item script is where the mod says it is", handle ~= nil)
	local text = handle:read("*a")
	handle:close()
	local code = string.gsub(text, "/%*.-%*/", "")

	local blocks = {}
	for name, body in string.gmatch(code, "item%s+([A-Za-z]+)%s*(%b{})") do
		blocks[name] = body
	end

	-- The four hardware modules (rung 4f). Checked here beside the disks and not
	-- with the books, because they are the same shape as a disk: an item with an
	-- icon of its own and a world model, and no StaticModel -- a module is
	-- carried in a bag and dropped on the ground, never held in a hand.
	--
	-- The world models are VANILLA names and the icons are ours: this mod ships
	-- no mesh for these four, and a WorldStaticModel nothing answers to is an
	-- item that lies on the floor as nothing at all.
	local MODULES = {
		{ item = "MagneticContact", icon = "CeroSecMagneticContact",
			name = "Magnetic Contact", model = "MotionSensor" },
		{ item = "Relay", icon = "CeroSecRelay",
			name = "Relay Module", model = "ElectronicsScrap" },
		{ item = "ElectricStrike", icon = "CeroSecElectricStrike",
			name = "Electric Strike", model = "ScrapMetal" },
		{ item = "DoorOperator", icon = "CeroSecDoorOperator",
			name = "Door Operator", model = "ScrapMetal" },
		-- And the motor rung's four. Same shape, same keys; what they add is a
		-- Tooltip each, because what an "Appliance Switch" fits is not something
		-- its name tells anybody.
		{ item = "CurtainMotor", icon = "CeroSecCurtainMotor",
			name = "Curtain Motor", model = "ScrapMetal",
			tip = "Tooltip_item_CeroSecCurtainMotor" },
		{ item = "WindowOperator", icon = "CeroSecWindowOperator",
			name = "Window Operator", model = "ScrapMetal",
			tip = "Tooltip_item_CeroSecWindowOperator" },
		{ item = "ApplianceSwitch", icon = "CeroSecApplianceSwitch",
			name = "Appliance Switch", model = "ElectronicsScrap",
			tip = "Tooltip_item_CeroSecApplianceSwitch" },
		{ item = "GeneratorSwitch", icon = "CeroSecGeneratorSwitch",
			name = "Generator Switch", model = "ScrapMetal",
			tip = "Tooltip_item_CeroSecGeneratorSwitch" },
		-- And the tuner rung's one, on the end of the end: the appliance switch's
		-- weight and the appliance switch's world model, because a board on the
		-- ground is what both of them are.
		{ item = "TunerControl", icon = "CeroSecTunerControl",
			name = "Tuner Control", model = "ElectronicsScrap",
			tip = "Tooltip_item_CeroSecTunerControl" },
	}
	eq("one entry here per module the Lua works in", #MODULES, #CeroSecModules.LIST)
	for m = 1, #MODULES do
		local want = MODULES[m]
		local body = blocks[want.item]
		check("the script declares item " .. want.item, body ~= nil)
		local keys = {}
		for key, value in string.gmatch(body or "", "([A-Za-z]+)%s*=%s*([^,\n]+),") do
			keys[key] = value
		end
		for _, key in ipairs({ "DisplayName", "DisplayCategory", "ItemType",
				"Weight", "Icon", "WorldStaticModel" }) do
			check(want.item .. " sets " .. key, keys[key] ~= nil)
		end
		eq(want.item .. "'s fallback name", keys.DisplayName, want.name)
		eq(want.item .. " files itself under Electronics", keys.DisplayCategory,
			"Electronics")
		eq(want.item .. " is a plain item", keys.ItemType, "base:normal")
		eq(want.item .. "'s icon", keys.Icon, want.icon)
		eq(want.item .. "'s world model is the vanilla one it borrows",
			keys.WorldStaticModel, want.model)
		check(want.item .. " has no hand model, being a thing in a bag",
			keys.StaticModel == nil)
		-- The icon file the name resolves to, which is what Item.DoParam asks
		-- Texture.trygetTexture for.
		local icon = io.open("common/media/textures/Item_" .. want.icon .. ".png", "r")
		check("and the icon file is there: Item_" .. want.icon .. ".png", icon ~= nil)
		if icon ~= nil then icon:close() end

		-- Both names a player reads, in both languages: a missing ItemName key
		-- prints the English fallback to a French player and says nothing about
		-- it, and a missing Tooltip key prints the KEY itself on the glass.
		local keyed = { { "ItemName.json", "CeroSec." .. want.item } }
		if want.tip ~= nil then
			eq(want.item .. "'s tooltip key", keys.Tooltip, want.tip)
			keyed[#keyed + 1] = { "Tooltip.json", want.tip }
		end
		for _, lang in ipairs({ "EN", "FR" }) do
			for _, pair in ipairs(keyed) do
				local handle = assert(io.open(
					"42/media/lua/shared/Translate/" .. lang .. "/" .. pair[1], "r"))
				local strings = handle:read("*a")
				handle:close()
				check(lang .. "/" .. pair[1] .. " defines " .. pair[2],
					string.find(strings, '"' .. pair[2] .. '"', 1, true) ~= nil)
			end
		end
	end

	-- THE SMALL MOTOR, which is not a module and is checked apart from the four:
	-- it is the PART they are built from, the game ships no motor item of any
	-- kind (docs/notes/actuators.md), and the two things it has that a module
	-- does not are the reason it is here -- a MetalValue, because it is a lump of
	-- copper and steel and vanilla's two nearest part items both carry one, and a
	-- Tooltip, because "where do I get one" is the only question a player has
	-- about it and the answer is four items long.
	do
		local body = blocks.SmallMotor
		check("the script declares item SmallMotor", body ~= nil)
		local keys = {}
		for key, value in string.gmatch(body or "", "([A-Za-z]+)%s*=%s*([^,\n]+),") do
			keys[key] = value
		end
		eq("its fallback name", keys.DisplayName, "Small Motor")
		eq("it files itself under Electronics with the modules",
			keys.DisplayCategory, "Electronics")
		eq("a plain item", keys.ItemType, "base:normal")
		eq("Base.MotionSensor's own weight, the vanilla part nearest to it",
			keys.Weight, "0.3")
		eq("its icon", keys.Icon, "CeroSecSmallMotor")
		eq("a lump of metal is what one looks like on a road",
			keys.WorldStaticModel, "ScrapMetal")
		check("no hand model, being a thing in a bag", keys.StaticModel == nil)
		eq("Base.HairDryer's whole metal value, which is where nearly all of it is",
			keys.MetalValue, "8.0")
		eq("and a tooltip key", keys.Tooltip, "Tooltip_item_CeroSecSmallMotor")
		local icon = io.open("common/media/textures/Item_CeroSecSmallMotor.png", "r")
		check("and the icon file is there: Item_CeroSecSmallMotor.png", icon ~= nil)
		if icon ~= nil then icon:close() end

		-- Both names a player reads, in both languages. A DisplayName is the
		-- fallback and nothing else: an item whose ItemName.json key is missing
		-- prints the fallback in English to a French player and says nothing about
		-- it, and an item whose Tooltip key is missing prints the KEY.
		for _, lang in ipairs({ "EN", "FR" }) do
			for _, pair in ipairs({ { "ItemName.json", "CeroSec.SmallMotor" },
					{ "Tooltip.json", "Tooltip_item_CeroSecSmallMotor" } }) do
				local handle = assert(io.open(
					"42/media/lua/shared/Translate/" .. lang .. "/" .. pair[1], "r"))
				local strings = handle:read("*a")
				handle:close()
				check(lang .. "/" .. pair[1] .. " defines " .. pair[2],
					string.find(strings, '"' .. pair[2] .. '"', 1, true) ~= nil)
			end
		end
	end

	-- The Field Wiring Guide, which is the one item in this mod that IS
	-- base:literature and is checked here for that above everything else. The
	-- four volumes at the top of the item script are base:normal on purpose --
	-- they are read by the PLAYER and vanilla must add no Read of its own --
	-- and this one is the exact opposite: vanilla's Read is the entire
	-- mechanism, and an ItemType that drifted back to base:normal would be a
	-- book with no Read option, no ReadLiterature call and therefore no recipe
	-- ever learned, with nothing logged anywhere.
	do
		local body = blocks.WiringGuide
		check("the script declares item WiringGuide", body ~= nil)
		local keys = {}
		for key, value in string.gmatch(body or "", "([A-Za-z]+)%s*=%s*([^,\n]+),") do
			keys[key] = value
		end
		eq("the guide is literature, which is what makes vanilla offer Read",
			keys.ItemType, "base:literature")
		eq("and it teaches by LearnedRecipes, B42's key -- there is no "
			.. "TeachedRecipes left in the game",
			keys.LearnedRecipes ~= nil, true)
		check("the script does not use the B41 spelling anywhere",
			string.find(code, "TeachedRecipes", 1, true) == nil)

		-- Base.ElectronicsMag1's own keys, verbatim: a magazine that weighs or
		-- files itself differently from the five the game already prints is a
		-- magazine a player can tell is a mod's.
		eq("filed where vanilla files a recipe magazine", keys.DisplayCategory,
			"RecipeResource")
		eq("half a kilo, like every vanilla magazine", keys.Weight, "0.5")
		eq("it reads like a magazine", keys.BoredomChange, "-20")
		eq("and relaxes like one", keys.StressChange, "-15")
		eq("it is tagged as one", keys.Tags, "base:magazine")
		eq("vanilla's own OnCreate, which only stamps literatureTitle",
			keys.OnCreate, "ItemCodeOnCreate.onCreateRecipeMagazine")
		eq("its fallback name", keys.DisplayName, "CeroSec Field Wiring Guide")
		eq("its tooltip key", keys.Tooltip, "Tooltip_item_CeroSecWiringGuide")

		-- Both models are Base.SmithingMag1's and both are declared in vanilla
		-- (models_items.txt:281 and :4493). A magazine with no world model is a
		-- magazine that lies on the floor as nothing at all.
		eq("a model in the hand", keys.StaticModel, "Magazine")
		eq("and one on the ground", keys.WorldStaticModel, "MagazineGround")

		local icon = io.open("common/media/textures/Item_CeroSecWiringGuide.png", "r")
		check("and the icon file is there: Item_CeroSecWiringGuide.png",
			icon ~= nil)
		if icon ~= nil then icon:close() end
	end

	-- The four ids the mod's Lua works in, against the four items the script
	-- declares: one list, two files, and a name that drifted on one side would be
	-- a menu entry that fits nothing.
	for m = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[m]
		local name = string.sub(module.item, #"CeroSec." + 1)
		check("the script declares the item " .. module.id .. " is made of: "
			.. module.item, blocks[name] ~= nil)
	end

	local mpath = "common/media/scripts/models_cerosec.txt"
	local mhandle = io.open(mpath, "r")
	check("the model script is where the items point", mhandle ~= nil)
	local mtext = mhandle:read("*a")
	mhandle:close()
	local mcode = string.gsub(mtext, "/%*.-%*/", "")
	check("the models are declared in the items' own module, so that "
		.. "ScriptManager.resolveModelScript finds them first",
		string.find(mcode, "module CeroSec", 1, true) ~= nil)
	local models = {}
	for name, body in string.gmatch(mcode, "model%s+([A-Za-z_]+)%s*(%b{})") do
		models[name] = body
	end

	-- One disk in four colours of shell: the same name, the same weight, the same
	-- everything except the icon and the model. A colour whose weight drifted
	-- would be a colour a player can tell apart in the pack, which is the one
	-- thing these four must NOT be.
	local COLOURS = { "Blue", "Yellow", "Red", "Green" }
	local NAME = "3.5 inch Floppy Disk"
	local seenIcon = {}
	for c = 1, #COLOURS do
		local item = "Floppy" .. COLOURS[c]
		local body = blocks[item]
		check("the script declares item " .. item, body ~= nil)

		local keys = {}
		for key, value in string.gmatch(body or "", "([A-Za-z]+)%s*=%s*([^,\n]+),") do
			keys[key] = value
		end
		for _, key in ipairs({ "DisplayName", "DisplayCategory", "ItemType",
				"Weight", "Icon", "WorldStaticModel" }) do
			check(item .. " sets " .. key, keys[key] ~= nil)
		end
		-- A disk is carried, never read: nothing vanilla may hang a menu on it.
		eq(item .. " is a plain item", keys.ItemType, "base:normal")
		eq(item .. " is filed under Electronics", keys.DisplayCategory, "Electronics")
		eq(item .. " carries the fallback name in words, since a double quote in a "
			.. "script value is not a thing to bet on", keys.DisplayName, NAME)
		eq(item .. " weighs what the other three weigh", keys.Weight, "0.1")
		-- No StaticModel: a disk is not held up in front of the character the way
		-- a book is, and a model in the hand that nobody asked for is a model to
		-- be wrong about.
		eq(item .. " has nothing in the hand", keys.StaticModel, nil)

		eq(item .. " carries its own shell on the icon", keys.Icon,
			"CeroSecFloppy" .. COLOURS[c])
		eq(item .. "'s model is its icon's own name", keys.WorldStaticModel, keys.Icon)
		check(item .. " does not share another disk's icon", seenIcon[keys.Icon] == nil)
		seenIcon[keys.Icon] = true

		-- Icon = Foo is media/textures/Item_Foo.png.
		local png = io.open("common/media/textures/Item_" .. keys.Icon .. ".png", "r")
		check(item .. "'s icon is a file the mod ships", png ~= nil)
		if png then png:close() end

		-- And the model block, with the mesh and the texture it names really on
		-- disk. A WorldStaticModel pointing at nothing is a disk that vanishes
		-- when it is dropped, and nothing is logged about it.
		local mbody = models[keys.WorldStaticModel]
		check("model " .. tostring(keys.WorldStaticModel) .. " is declared", mbody ~= nil)
		local mkeys = {}
		for key, value in string.gmatch(mbody or "", "([A-Za-z]+)%s*=%s*([^,\n]+),") do
			mkeys[key] = value
		end
		eq(item .. "'s model uses the one mesh", mkeys.mesh, "WorldItems/CeroSecFloppy")
		eq(item .. "'s model uses its own texture", mkeys.texture,
			"WorldItems/CeroSecFloppy_" .. COLOURS[c])
		check(item .. "'s model carries the scale the mesh was exported at",
			mkeys.scale ~= nil)

		local tex = io.open("common/media/textures/" .. mkeys.texture .. ".png", "r")
		check(item .. "'s world texture is a file the mod ships", tex ~= nil)
		if tex then tex:close() end
	end

	-- The mesh, once: four models, one FBX.
	local fbx = io.open("common/media/models_X/WorldItems/CeroSecFloppy.FBX", "r")
	check("the mesh is a file the mod ships", fbx ~= nil)
	if fbx then fbx:close() end

	-- Every line inside a model block ends in a comma, exactly as the item script
	-- is held to it: the one syntax slip that costs a whole script file.
	for line in string.gmatch(mcode, "[^\n]+") do
		local body = string.match(line, "^%s*([A-Za-z][^\n]-)%s*$")
		if body and string.find(body, "=", 1, true) then
			check("this model line ends in a comma: " .. body,
				string.sub(body, -1) == ",")
		end
	end

	-- The names the engine knows a disk by are the names the script declares.
	-- This is the pair that goes wrong silently: a typo in either half is an eject
	-- that hands back nothing, or an insert nothing will take.
	for i = 1, #CeroSec.FLOPPY_TYPES do
		local fullType = CeroSec.FLOPPY_TYPES[i]
		local item = string.match(fullType, "^CeroSec%.([A-Za-z]+)$")
		check(fullType .. " is a name the script really declares",
			item ~= nil and blocks[item] ~= nil)
		check(fullType .. " is one the engine answers to", CeroSec.isFloppyType(fullType))
	end
	eq("four of them and no more", #CeroSec.FLOPPY_TYPES, 4)
	check("and a name nobody declared is not one",
		not CeroSec.isFloppyType("CeroSec.FloppyPurple"))

	-- The two sounds the drive plays are declared, or the drive is silent and
	-- nothing says so in the log.
	local spath = "common/media/scripts/sounds_cerosec.txt"
	local shandle = io.open(spath, "r")
	check("the sound script is where the mod says it is", shandle ~= nil)
	local stext = shandle:read("*a")
	shandle:close()
	for _, sound in ipairs({ "CeroSecInsertDisc", "CeroSecEjectDisc" }) do
		check("the script declares " .. sound,
			string.find(stext, "sound " .. sound, 1, true) ~= nil)
		local ogg = io.open("common/media/sound/" .. sound .. ".ogg", "r")
		check(sound .. " is a file the mod ships", ogg ~= nil)
		if ogg then ogg:close() end
	end
end


--
-- The disks' own loot table
--
-- A different table from the manual's on purpose: a book about a computer lives
-- with the books and a disk lives with the computers. What is checked is that
-- the two do not quietly become one -- the same list, the same weight -- and
-- that every disk found in the world is BLANK, which is the whole reason `newfs`
-- is the first command the drive's chapter teaches.
--

do
	ProceduralDistributions = { list = {} }
	SandboxVars = nil
	local KEYS = {}
	for key in pairs(CeroSecFloppyLootKeys or {}) do KEYS[#KEYS + 1] = key end

	local chunk = assert(loadfile(LUA .. "server/CeroSec/CeroSecFloppyLoot.lua"))
	chunk()

	eq("the file hooked the first distribution event too",
		#Events.OnPreDistributionMerge.handlers, 2)

	KEYS = {}
	for key in pairs(CeroSecFloppyLoot.WEIGHTS) do KEYS[#KEYS + 1] = key end
	table.sort(KEYS)
	eq("eleven shelves hold disks", #KEYS, 11)
	for i = 1, #KEYS do
		ProceduralDistributions.list[KEYS[i]] = { rolls = 4, items = { "Something", 10 } }
	end

	local added = CeroSecFloppyLoot.add()
	eq("every list named was found and filled by every colour",
		added, #KEYS * #CeroSec.FLOPPY_TYPES)

	for i = 1, #KEYS do
		local key = KEYS[i]
		local items = ProceduralDistributions.list[key].items
		eq(key .. " kept what was already in it", items[1], "Something")
		eq(key .. " still has an even number of entries", #items % 2, 0)
		eq(key .. " grew by one name and one weight per colour",
			#items, 2 + 2 * #CeroSec.FLOPPY_TYPES)
		-- The four colours in the order a box came in, each a quarter of the box.
		for c = 1, #CeroSec.FLOPPY_TYPES do
			local at = 2 + (c - 1) * 2 + 1
			eq(key .. " has " .. CeroSec.FLOPPY_TYPES[c] .. " in place " .. c,
				items[at], CeroSec.FLOPPY_TYPES[c])
			eq(key .. " gave it a quarter of the box",
				items[at + 1], CeroSecFloppyLoot.WEIGHTS[key] * 0.25)
		end
		-- And no book on a disk's shelf that did not already have one: the two
		-- tables share three lists and nothing else.
		for n = 1, #items, 2 do
			check(key .. " spawns no volume of the manual",
				string.find(tostring(items[n]), "CeroSec.Manual", 1, true) == nil)
		end
	end

	-- A quarter of every one of those numbers is exact in a double.
	for i = 1, #KEYS do
		local w = CeroSecFloppyLoot.WEIGHTS[KEYS[i]] * 0.25
		eq(KEYS[i] .. "'s quarter is exact", w * 4, CeroSecFloppyLoot.WEIGHTS[KEYS[i]])
	end

	-- The two tables are not the same table. Three shelves hold both -- a cyber
	-- cafe had books and disks on the same desk -- and the rest are each other's
	-- business.
	local shared = 0
	for key in pairs(CeroSecFloppyLoot.WEIGHTS) do
		if CeroSecManualLoot.WEIGHTS[key] ~= nil then shared = shared + 1 end
	end
	check("the two tables overlap without being the same (" .. shared .. ")",
		shared > 0 and shared < #KEYS)

	-- Fired twice -- a Lua reload does that -- and nothing doubles.
	local lengths = {}
	for i = 1, #KEYS do
		lengths[i] = #ProceduralDistributions.list[KEYS[i]].items
	end
	CeroSecFloppyLoot.added = false
	eq("a second pass adds nothing", CeroSecFloppyLoot.add(), 0)
	for i = 1, #KEYS do
		eq(KEYS[i] .. " was not doubled",
			#ProceduralDistributions.list[KEYS[i]].items, lengths[i])
	end

	-- A list vanilla renamed is a list that is skipped, not a crash.
	CeroSecFloppyLoot.added = false
	ProceduralDistributions.list[KEYS[1]] = nil
	eq("a missing list is skipped quietly", CeroSecFloppyLoot.add(), 0)

	-- The same sandbox option the manual reads, read the same way.
	SandboxVars = nil
	eq("with no sandbox group at all the multiplier is one",
		CeroSecFloppyLoot.abundance(), 1)
	SandboxVars = { CeroSec = {} }
	eq("with a group but no option it is still one", CeroSecFloppyLoot.abundance(), 1)
	for _, bad in ipairs({ 0, -1, "lots", true }) do
		SandboxVars.CeroSec[CeroSecManualLoot.SANDBOX] = bad
		eq("a LootAbundance of " .. tostring(bad) .. " is not an abundance",
			CeroSecFloppyLoot.abundance(), 1)
	end
	SandboxVars.CeroSec[CeroSecManualLoot.SANDBOX] = 2
	eq("a number is the number", CeroSecFloppyLoot.abundance(), 2)

	-- And it reaches the weights: a multiplier read and then not used would
	-- leave every assertion above green.
	ProceduralDistributions.list = { OfficeDesk = { rolls = 4, items = {} } }
	CeroSecFloppyLoot.added = false
	CeroSecFloppyLoot.add()
	local items = ProceduralDistributions.list.OfficeDesk.items
	for c = 1, #CeroSec.FLOPPY_TYPES do
		eq("colour " .. c .. "'s weight was doubled with the shelves",
			items[c * 2], CeroSecFloppyLoot.WEIGHTS.OfficeDesk * 0.25 * 2)
	end
end

--
-- The hardware modules' own shelves
--
-- The third distribution table (the manual's, the disks' and now this one), and
-- what it has to be is a table that is NOT either of those: nobody kept a door
-- operator on an office desk and nobody kept a floppy disk in a garage's tool
-- cabinet. What is asserted here is the shape the other two are asserted on --
-- every list found, every module in it once, the weights exact, a second pass
-- that adds nothing, a renamed list skipped quietly and the sandbox multiplier
-- reaching the numbers -- plus the one thing only this table can be wrong about:
-- four modules that are not worth the same.
--
do
	local chunk = assert(loadfile(LUA .. "server/CeroSec/CeroSecModuleLoot.lua"))
	chunk()

	local KEYS = {}
	for key in pairs(CeroSecModuleLoot.WEIGHTS) do KEYS[#KEYS + 1] = key end
	table.sort(KEYS)
	eq("nine shelves hold hardware", #KEYS, 9)

	ProceduralDistributions.list = {}
	for i = 1, #KEYS do
		ProceduralDistributions.list[KEYS[i]] = { rolls = 4, items = { "Something", 10 } }
	end

	SandboxVars = nil
	CeroSecModuleLoot.added = false
	local added = CeroSecModuleLoot.add()
	eq("every list named was found and filled by every module and the motor",
		added, #KEYS * (#CeroSecModules.LIST + 1))

	for i = 1, #KEYS do
		local key = KEYS[i]
		local items = ProceduralDistributions.list[key].items
		eq(key .. " kept what was already in it", items[1], "Something")
		eq(key .. " still has an even number of entries", #items % 2, 0)
		eq(key .. " grew by one name and one weight per module, and the motor's",
			#items, 2 + 2 * (#CeroSecModules.LIST + 1))
		for m = 1, #CeroSecModules.LIST do
			local module = CeroSecModules.LIST[m]
			local at = 2 + (m - 1) * 2 + 1
			eq(key .. " has " .. module.item .. " in place " .. m, items[at], module.item)
			eq(key .. " gave it its own share of the box", items[at + 1],
				CeroSecModuleLoot.WEIGHTS[key] * CeroSecModuleLoot.SHARES[module.id])
		end
		-- And the part, last, and RARER than the rarest box on the shelf: a shelf
		-- held finished stock, and the road to a motor is a screwdriver and a hair
		-- dryer. A share that drifted up to the operator's would be this table
		-- saying a loose motor was as common as the thing built around one.
		do
			local at = 2 + #CeroSecModules.LIST * 2 + 1
			eq(key .. " has the motor last", items[at], CeroSecModuleLoot.MOTOR)
			eq(key .. " gave the motor its own share", items[at + 1],
				CeroSecModuleLoot.WEIGHTS[key] * CeroSecModuleLoot.MOTOR_SHARE)
			check(key .. ": a motor is rarer than a door operator",
				items[at + 1] < CeroSecModuleLoot.weightFor(key, "operator", 1))
		end
		-- Neither of the other two tables' items is on these shelves.
		for n = 1, #items, 2 do
			check(key .. " spawns no volume of the manual",
				string.find(tostring(items[n]), "CeroSec.Manual", 1, true) == nil)
			check(key .. " spawns no floppy disk",
				string.find(tostring(items[n]), "CeroSec.Floppy", 1, true) == nil)
		end
	end

	-- The four are NOT worth the same, which is the whole difference between this
	-- table and the disks': a contact is eight times an operator, in every list.
	for i = 1, #KEYS do
		local base = CeroSecModuleLoot.WEIGHTS[KEYS[i]]
		local contact = CeroSecModuleLoot.weightFor(KEYS[i], "contact", 1)
		local operator = CeroSecModuleLoot.weightFor(KEYS[i], "operator", 1)
		check(KEYS[i] .. ": a contact is commoner than an operator", contact > operator)
		eq(KEYS[i] .. ": eight times as common", contact, operator * 8)
		-- And every share of every base is exact in a double, which is what
		-- powers of two are for: the number read back is the number written.
		for id, share in pairs(CeroSecModuleLoot.SHARES) do
			local w = CeroSecModuleLoot.weightFor(KEYS[i], id, 1)
			eq(KEYS[i] .. "'s share for " .. id .. " is exact", w / share, base)
		end
	end

	-- A module nobody declared has no weight at all, and neither has a list
	-- nobody named: weightFor answers nil rather than a number made up of nils.
	eq("no weight for a module that does not exist",
		CeroSecModuleLoot.weightFor(KEYS[1], "toaster", 1), nil)
	eq("no weight for a list that does not exist",
		CeroSecModuleLoot.weightFor("NoSuchShelf", "relay", 1), nil)

	-- This table is its own: it shares no shelf at all with the disks', which
	-- is the point of it -- a computer's desk and an electrician's van are not
	-- the same room.
	local shared = 0
	for key in pairs(CeroSecModuleLoot.WEIGHTS) do
		if CeroSecFloppyLoot.WEIGHTS[key] ~= nil then shared = shared + 1 end
	end
	eq("no shelf holds both a disk and a door operator", shared, 0)

	-- Fired twice -- a Lua reload does that -- and nothing doubles.
	local lengths = {}
	for i = 1, #KEYS do
		lengths[i] = #ProceduralDistributions.list[KEYS[i]].items
	end
	CeroSecModuleLoot.added = false
	eq("a second pass adds nothing", CeroSecModuleLoot.add(), 0)
	for i = 1, #KEYS do
		eq(KEYS[i] .. " was not doubled",
			#ProceduralDistributions.list[KEYS[i]].items, lengths[i])
	end

	-- A list vanilla renamed is a list that is skipped, not a crash.
	CeroSecModuleLoot.added = false
	ProceduralDistributions.list[KEYS[1]] = nil
	eq("a missing list is skipped quietly", CeroSecModuleLoot.add(), 0)

	-- The same sandbox option the manual and the disks read, read the same way.
	SandboxVars = nil
	eq("with no sandbox group at all the multiplier is one",
		CeroSecModuleLoot.abundance(), 1)
	SandboxVars = { CeroSec = {} }
	eq("with a group but no option it is still one", CeroSecModuleLoot.abundance(), 1)
	for _, bad in ipairs({ 0, -1, "lots", true }) do
		SandboxVars.CeroSec[CeroSecManualLoot.SANDBOX] = bad
		eq("a LootAbundance of " .. tostring(bad) .. " is not an abundance",
			CeroSecModuleLoot.abundance(), 1)
	end
	SandboxVars.CeroSec[CeroSecManualLoot.SANDBOX] = 2
	eq("a number is the number", CeroSecModuleLoot.abundance(), 2)

	-- And it reaches the weights: a multiplier read and then not used would leave
	-- every assertion above green.
	ProceduralDistributions.list = { ElectricianTools = { rolls = 3, items = {} } }
	CeroSecModuleLoot.added = false
	CeroSecModuleLoot.add()
	local items = ProceduralDistributions.list.ElectricianTools.items
	for m = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[m]
		eq(module.id .. "'s weight was doubled with the shelves", items[m * 2],
			CeroSecModuleLoot.WEIGHTS.ElectricianTools
				* CeroSecModuleLoot.SHARES[module.id] * 2)
	end
	-- The motor reads the same multiplier, and it is a separate call to addTo:
	-- an abundance read once and then not passed to it would leave every
	-- assertion above green.
	eq("and so was the motor's", items[(#CeroSecModules.LIST + 1) * 2],
		CeroSecModuleLoot.WEIGHTS.ElectricianTools
			* CeroSecModuleLoot.MOTOR_SHARE * 2)
	SandboxVars = nil
end

--
-- Where the Field Wiring Guide is found
--
-- The fourth loot table, and the one that is not a judgement: the guide is an
-- electronics magazine and its nine shelves and nine weights are Base
-- ElectronicsMag1-5's own, copied out of ProceduralDistributions.lua. So what is
-- asserted here is the shape the other three are asserted on -- every list
-- found, the item in it once, the weights exact, a second pass that adds
-- nothing, a renamed list skipped quietly and the sandbox multiplier reaching
-- the numbers -- plus the one thing only this table can be wrong about: a shelf
-- or a share that is not the vanilla family's.
--
do
	local chunk = assert(loadfile(LUA .. "server/CeroSec/CeroSecGuideLoot.lua"))
	chunk()

	local KEYS = {}
	for key in pairs(CeroSecGuideLoot.WEIGHTS) do KEYS[#KEYS + 1] = key end
	table.sort(KEYS)
	eq("nine shelves hold the guide", #KEYS, 9)

	-- Vanilla's own numbers, written out again here rather than read off the
	-- table under test: a weight changed in CeroSecGuideLoot.lua would otherwise
	-- be a weight this bench agreed with. These nine are the lists in
	-- media/lua/server/Items/ProceduralDistributions.lua that hold all five
	-- ElectronicsMag items at one weight, and the number is that weight.
	local FAMILY = {
		ElectronicStoreMagazines = 8,
		BookstoreMisc = 2,
		BookstoreBlueCollar = 2,
		ToolStoreBooks = 2,
		ElectricianTools = 2,
		MagazineRackMixed = 1,
		PostOfficeMagazines = 1,
		CrateMagazines = 1,
		LibraryMagazines = 1,
	}
	for i = 1, #KEYS do
		eq(KEYS[i] .. " carries the vanilla family's own weight",
			CeroSecGuideLoot.WEIGHTS[KEYS[i]], FAMILY[KEYS[i]])
	end
	local named = 0
	for _ in pairs(FAMILY) do named = named + 1 end
	eq("and there are no shelves beyond the family's", named, #KEYS)

	-- The shop it was sold in is where it is commonest, by a factor of four over
	-- anywhere else. A table whose weights were all equal would pass every
	-- assertion above and would be a magazine that is as likely in a post box as
	-- on the rack it was printed for.
	check("the electronics shop is the likeliest place of all",
		CeroSecGuideLoot.WEIGHTS.ElectronicStoreMagazines
			> CeroSecGuideLoot.WEIGHTS.BookstoreMisc)
	eq("four times the bookshop's", CeroSecGuideLoot.WEIGHTS.ElectronicStoreMagazines,
		CeroSecGuideLoot.WEIGHTS.BookstoreMisc * 4)

	ProceduralDistributions.list = {}
	for i = 1, #KEYS do
		ProceduralDistributions.list[KEYS[i]] = { rolls = 4, items = { "Something", 10 } }
	end

	SandboxVars = nil
	CeroSecGuideLoot.added = false
	local added = CeroSecGuideLoot.add()
	eq("every list named was found and filled", added, #KEYS)

	for i = 1, #KEYS do
		local key = KEYS[i]
		local items = ProceduralDistributions.list[key].items
		eq(key .. " kept what was already in it", items[1], "Something")
		eq(key .. " still has an even number of entries", #items % 2, 0)
		eq(key .. " grew by exactly one name and one weight", #items, 4)
		eq(key .. " holds the guide", items[3], CeroSecGuideLoot.ITEM)
		eq(key .. " gave it the family's weight", items[4], FAMILY[key])
	end

	-- The guide is on every one of its nine shelves. A book missing from one
	-- shelf is a book a player never finds in the one shop he went to for it,
	-- and nothing anywhere would say so.
	for i = 1, #KEYS do
		local items = ProceduralDistributions.list[KEYS[i]].items
		local found = false
		for n = 1, #items, 2 do
			if items[n] == CeroSecGuideLoot.ITEM then found = true end
		end
		check(KEYS[i] .. " really has the guide on it", found)
	end

	-- It is a book, so it goes where books go, and it shares no shelf with the
	-- hardware it teaches: nobody kept a magazine in a crate of door operators.
	local shared = 0
	for key in pairs(CeroSecGuideLoot.WEIGHTS) do
		if CeroSecModuleLoot.WEIGHTS[key] ~= nil then shared = shared + 1 end
	end
	eq("only the electrician's van holds both the guide and the hardware",
		shared, 1)
	check("and that one is the electrician's van",
		CeroSecModuleLoot.WEIGHTS.ElectricianTools ~= nil
			and CeroSecGuideLoot.WEIGHTS.ElectricianTools ~= nil)

	-- No shelf of the guide's spawns a module, a disk or a volume of the manual.
	for i = 1, #KEYS do
		local items = ProceduralDistributions.list[KEYS[i]].items
		for n = 1, #items, 2 do
			check(KEYS[i] .. " spawns no volume of the manual",
				string.find(tostring(items[n]), "CeroSec.Manual", 1, true) == nil)
			check(KEYS[i] .. " spawns no floppy disk",
				string.find(tostring(items[n]), "CeroSec.Floppy", 1, true) == nil)
		end
	end

	-- Fired twice -- a Lua reload does that -- and nothing doubles.
	local lengths = {}
	for i = 1, #KEYS do
		lengths[i] = #ProceduralDistributions.list[KEYS[i]].items
	end
	CeroSecGuideLoot.added = false
	eq("a second pass adds nothing", CeroSecGuideLoot.add(), 0)
	for i = 1, #KEYS do
		eq(KEYS[i] .. " was not doubled",
			#ProceduralDistributions.list[KEYS[i]].items, lengths[i])
	end

	-- A list vanilla renamed is a list that is skipped, not a crash.
	CeroSecGuideLoot.added = false
	ProceduralDistributions.list[KEYS[1]] = nil
	eq("a missing list is skipped quietly", CeroSecGuideLoot.add(), 0)

	-- A list nobody named has no weight at all.
	eq("no weight for a list that does not exist",
		CeroSecGuideLoot.weightFor("NoSuchShelf", 1), nil)

	-- The same sandbox option the other three read, read the same way.
	SandboxVars = nil
	eq("with no sandbox group at all the multiplier is one",
		CeroSecGuideLoot.abundance(), 1)
	SandboxVars = { CeroSec = {} }
	eq("with a group but no option it is still one", CeroSecGuideLoot.abundance(), 1)
	for _, bad in ipairs({ 0, -1, "lots", true }) do
		SandboxVars.CeroSec[CeroSecManualLoot.SANDBOX] = bad
		eq("a LootAbundance of " .. tostring(bad) .. " is not an abundance",
			CeroSecGuideLoot.abundance(), 1)
	end
	SandboxVars.CeroSec[CeroSecManualLoot.SANDBOX] = 2
	eq("a number is the number", CeroSecGuideLoot.abundance(), 2)

	-- And it reaches the weights: a multiplier read and then not used would leave
	-- every assertion above green.
	ProceduralDistributions.list = { ElectricianTools = { rolls = 3, items = {} } }
	CeroSecGuideLoot.added = false
	CeroSecGuideLoot.add()
	eq("the guide's weight was doubled with the shelves",
		ProceduralDistributions.list.ElectricianTools.items[2],
		CeroSecGuideLoot.WEIGHTS.ElectricianTools * 2)
	SandboxVars = nil
end

--
-- The recipe script: the keys the game will be asked to parse, and the two
-- numbers it shares with the Lua
--
-- A recipe that asked for a level the install does not is a survivor who can
-- build a module he cannot fit, or the other way round, and neither of those is
-- a thing anybody would notice until they had it in their hands. The level and
-- the item name are written in two files and they are checked against each other
-- here.
--
do
	local path = "common/media/scripts/recipes_cerosec.txt"
	local handle = io.open(path, "r")
	check("the recipe script is where the mod says it is", handle ~= nil)
	local text = handle:read("*a")
	handle:close()
	local code = string.gsub(text, "/%*.-%*/", "")

	local opens, closes = 0, 0
	for _ in string.gmatch(code, "{") do opens = opens + 1 end
	for _ in string.gmatch(code, "}") do closes = closes + 1 end
	eq("braces balance", opens, closes)
	check("it declares the mod's own module",
		string.find(code, "module CeroSec", 1, true) ~= nil)

	-- One block per module, keyed by what it makes, and the craftRecipe NAMES
	-- kept beside them: the name is what the Field Wiring Guide has to say back,
	-- and it is checked against the guide at the bottom of this block.
	local recipes = {}
	local names = {}
	for name, body in string.gmatch(code, "craftRecipe%s+([A-Za-z]+)%s*(%b{})") do
		local made = string.match(body, "outputs%s*{%s*item%s+1%s+([%w%.]+)")
		check("craftRecipe " .. name .. " makes something", made ~= nil)
		recipes[made or name] = body
		names[#names + 1] = name
	end

	for m = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[m]
		local body = recipes[module.item]
		check("a recipe makes " .. module.item, body ~= nil)
		body = body or ""

		-- The keys every vanilla electrical recipe sets
		-- (media/scripts/generated/recipes/recipes_electrical.txt).
		for _, key in ipairs({ "timedAction", "time", "NeedToBeLearn",
				"SkillRequired", "Tags", "category", "AutoLearnAll", "xpAward" }) do
			check(module.item .. "'s recipe sets " .. key,
				string.find(body, key .. " =", 1, true) ~= nil)
		end
		check(module.item .. " is made with vanilla's electrical action",
			string.find(body, "timedAction = MakingElectrical", 1, true) ~= nil)
		check(module.item .. " is filed under Electrical",
			string.find(body, "category = Electrical", 1, true) ~= nil)

		-- The two numbers that are also in CeroSecModules.LIST. Read out of the
		-- file rather than compared as text, so that a level changed on one side
		-- and not the other fails HERE and not in somebody's inventory.
		local needs = tonumber(string.match(body, "SkillRequired = Electricity:(%d+)"))
		eq(module.item .. " is built at the level it is fitted at", needs, module.skill)

		-- And it is NOT known at that level, which is the whole of what the
		-- Field Wiring Guide is for. A recipe whose auto-learn sits at or under
		-- its own SkillRequired is a recipe every survivor who can craft it
		-- already knows, and a book that teaches it teaches nobody anything --
		-- which is exactly what this file said before the guide existed. The
		-- gap is vanilla's: MakeImprovisedFlashlight is 1 and 3, and
		-- MakeRemoteControllerV1 -- the electrical recipe these four are
		-- nearest to -- is 2 and 8.
		local learns = tonumber(string.match(body, "AutoLearnAll = Electricity:(%d+)"))
		check(module.item .. " still has an auto-learn level at all, the way "
			.. "every magazine-taught vanilla recipe does", learns ~= nil)
		check(module.item .. " is NOT auto-learned at the level that can craft "
			.. "it: that is what the guide is for",
			(learns or 0) > (needs or 0))
		eq(module.item .. "'s auto-learn is the remote controller's own gap "
			.. "above what it requires", learns, (needs or 0) + 6)


		-- A screwdriver, kept: it is the same tool the install asks for, and a
		-- recipe that ate it would leave a survivor unable to fit what he just
		-- made.
		check(module.item .. "'s recipe asks for a screwdriver and keeps it",
			string.find(body, "tags[base:screwdriver] mode:keep", 1, true) ~= nil)

		-- THE MOTOR AND THE RECEIVER, on exactly the modules that MOVE a piece
		-- of a fixture and on no others. A contact senses and a relay sits in a
		-- lighting circuit; a strike moves a keeper and an operator moves a
		-- door, and each does it because a machine across the building said so.
		--
		-- Asserted in BOTH directions, because only one of the two is a bug
		-- anybody would notice: a moving module that lost its motor is a recipe
		-- a survivor can suddenly build out of scrap, and nothing in the game
		-- would tell him it used to cost more.
		-- The four that move a piece of metal or of cloth, against the four that
		-- close a circuit. Written out rather than derived, because deriving it
		-- from anything would be deriving it from the same list twice.
		local MOVES = { strike = true, operator = true,
			curtain = true, window = true }
		for _, part in ipairs({ "CeroSec.SmallMotor", "Base.Receiver" }) do
			local has = string.find(body, "[" .. part .. "]", 1, true) ~= nil
			if MOVES[module.id] then
				check(module.item .. " is built round " .. part, has)
			else
				check(module.item .. " senses rather than moves, so no " .. part,
					not has)
			end
		end
		-- And the box of motor and gearing is still on the door operator: an
		-- input is added to one of these, never taken off.
		if module.id == "operator" then
			check("the door operator still takes Base.EngineParts",
				string.find(body, "[Base.EngineParts]", 1, true) ~= nil)
		end
	end

	-- Nothing is made here but the four modules and the PART the moving ones are
	-- built from. `recipes` is keyed by what a block OUTPUTS, so the motor's two
	-- blocks share one key and five is the count: anything else would be a module
	-- nothing in the Lua knows about.
	local made = 0
	for _ in pairs(recipes) do made = made + 1 end
	eq("one module each and the motor, and nothing else is made", made,
		#CeroSecModules.LIST + 1)
	eq("in one block more, because the motor has two", #names,
		#CeroSecModules.LIST + 2)

	--
	-- WHERE A SMALL MOTOR COMES FROM, and the promise that goes with it
	--
	-- Build 42 ships no motor item, so the part comes out of the four things in
	-- the game that really have one (docs/notes/actuators.md). What is asserted
	-- here is the one thing a player could be cheated by: vanilla ALREADY
	-- dismantles three of those four, and a recipe of ours that paid less than
	-- vanilla's for the same item would be a trap -- a survivor picks ours off
	-- the list, loses the scrap he would have had, and nothing tells him.
	--
	-- DismantleElectronics (recipes_electrical.txt:37-54) pays ONE
	-- Base.ElectronicsScrap for anything tagged base:miscelectronic, which is the
	-- hair dryer and the shears. DismantleMiscElectronics (:56-81) pays one scrap
	-- plus an itemMapper output, and the CD player's mapping is scrap again --
	-- so TWO. The blower fan's only tag is base:blowerfan, which is used nowhere
	-- else in media/scripts, so vanilla dismantles it not at all.
	do
		local MOTOR = "CeroSec.SmallMotor"
		local SCRAP = "Base.ElectronicsScrap"
		-- What each recipe pays, by output item: read out of the file rather than
		-- matched as text, so a `item 1` that became `item 2` is caught here.
		local function paid(body, item)
			local n = string.match(body or "",
				"outputs%s*{[^}]-item%s+(%d+)%s+" .. string.gsub(item, "%.", "%%."))
			return tonumber(n)
		end
		-- Which items one recipe takes, as a set.
		local function takes(body)
			local out = {}
			for list in string.gmatch(body or "", "item%s+1%s+%[([^%]]+)%]") do
				for one in string.gmatch(list, "[^;]+") do out[one] = true end
			end
			return out
		end

		-- Both found BY NAME and not through `recipes`, which is keyed by output:
		-- two blocks making a motor share that key and one would answer for the
		-- other, which is exactly the mistake this block exists to catch.
		local appliance = string.match(code,
			"craftRecipe%s+DismantleCeroSecMotorAppliance%s*(%b{})")
		local cd = string.match(code,
			"craftRecipe%s+DismantleCeroSecMotorCDPlayer%s*(%b{})")
		check("a recipe makes " .. MOTOR .. " out of an appliance", appliance ~= nil)
		check("and a second one makes it out of a CD player", cd ~= nil)
		check("the output key they share is the motor", recipes[MOTOR] ~= nil)

		-- Vanilla's shape, key for key: the dismantle action, the standing-up
		-- tags, the electrical tab, the experience, and a screwdriver that is
		-- KEPT and must not be broken.
		for name, body in pairs({ appliance = appliance, cdplayer = cd }) do
			for _, want in ipairs({ "timedAction = DismantleElectrical",
					"Tags = InHandCraft;Electrical", "category = Electrical",
					"xpAward = Electricity:2", "NeedToBeLearn = true",
					"tags[base:screwdriver] mode:keep flags[NoBrokenItems]" }) do
				check("the motor's " .. name .. " recipe carries vanilla's \""
					.. want .. "\"", string.find(body or "", want, 1, true) ~= nil)
			end
			-- The thing itself is consumed, which is what dismantling is.
			check("the motor's " .. name .. " recipe destroys what it opens",
				string.find(body or "", "mode:destroy", 1, true) ~= nil)
			eq("the motor's " .. name .. " recipe yields exactly one motor",
				paid(body, MOTOR), 1)
		end

		-- The four items, and only those four. A fifth would be this mod deciding
		-- that something has a motor in it which does not.
		local all = {}
		for item in pairs(takes(appliance)) do all[item] = true end
		for item in pairs(takes(cd)) do all[item] = true end
		local n = 0
		for _ in pairs(all) do n = n + 1 end
		eq("four inputs between them and no more", n, 4)
		for _, item in ipairs({ "Base.HairDryer", "Base.SheepElectricShears",
				"Base.BlowerFan", "Base.CDplayer" }) do
			check("one of them is " .. item, all[item] == true)
		end
		-- And the CD player is on its OWN recipe, which is the whole reason there
		-- are two: it is the one input vanilla already pays two scrap for.
		check("the CD player is not on the appliance recipe",
			takes(appliance)["Base.CDplayer"] == nil)

		-- The promise, as numbers. Nobody is worse off.
		eq("a hair dryer, shears or a fan pay vanilla's one scrap and the motor",
			paid(appliance, SCRAP), 1)
		eq("and a CD player pays the TWO scrap DismantleMiscElectronics pays",
			paid(cd, SCRAP), 2)
	end

	-- The book, against the recipes. LearnedRecipes is a list of craftRecipe
	-- NAMES and the game matches them as strings: a recipe renamed here and not
	-- in the item script is a book that silently teaches nothing at all, and
	-- nothing in the game would say so -- the item would load, the Read option
	-- would appear, and the crafting tab would stay empty.
	local ihandle = io.open("common/media/scripts/items_cerosec.txt", "r")
	check("the item script is where the recipes' book lives", ihandle ~= nil)
	local itext = ihandle:read("*a")
	ihandle:close()
	local icode = string.gsub(itext, "/%*.-%*/", "")
	local guide = string.match(icode, "item%s+WiringGuide%s*(%b{})")
	check("the item script declares the Field Wiring Guide", guide ~= nil)

	local taught = {}
	local taughtCount = 0
	for one in string.gmatch(
			string.match(guide or "", "LearnedRecipes%s*=%s*([^,\n]+)") or "",
			"[^;]+") do
		one = string.gsub(one, "%s", "")
		if one ~= "" then
			taught[one] = true
			taughtCount = taughtCount + 1
		end
	end
	-- One per module plus the motor's two. The dismantles are NeedToBeLearn like
	-- the other four and are taught by the same book, which is what stops a
	-- survivor being able to fit an operator and unable to make the part for one.
	eq("the guide teaches one recipe per module and the motor's two",
		taughtCount, #CeroSecModules.LIST + 2)
	eq("which is every craftRecipe in the file", taughtCount, #names)
	table.sort(names)
	for n = 1, #names do
		check("the guide names the recipe " .. names[n], taught[names[n]] == true)
	end

	-- THE NAME A PLAYER READS, in both languages. A craftRecipe has no
	-- DisplayName key of its own: the menu asks Translator.getRecipeName(name)
	-- (ISInventoryPaneContextMenu.lua:1236-1238), and that is a lookup in the
	-- `recipe` map with the RAW recipe name as the key -- no prefix. When the
	-- lookup misses, the bytecode returns the key it was handed rather than
	-- nothing, so the menu prints `DismantleCeroSecMotorCDPlayer` and no line is
	-- logged anywhere:
	--
	--   zombie.core.Translator.getRecipeName(String)
	--      0: getstatic  Field recipe:Ljava/util/Map;
	--      4: Map.get; 14: ifnull 24; 18: String.isEmpty; 21: ifeq 63
	--     61: aload_0      <- the KEY
	--     62: areturn
	--     63: aload_1      <- the translation
	--     64: areturn
	--
	-- The map is filled from the file called `Recipes` (Translator$1, the BY_NAME
	-- map: `put("Recipes", Translator.recipe)`), and lambda$loadFiles$1 calls
	-- tryFillMapFromFile then tryFillMapFromMods for every BY_NAME entry, which is
	-- how a mod's own Translate/<LANG>/Recipes.json lands in the same map.
	--
	-- Both directions. A recipe with no key prints its name at a player; a key
	-- with no recipe is a rename that left the translation behind, and nothing in
	-- the game would say so either.
	local declared = {}
	for n = 1, #names do declared[names[n]] = true end
	for _, lang in ipairs({ "EN", "FR" }) do
		local handle = assert(io.open(
			"42/media/lua/shared/Translate/" .. lang .. "/Recipes.json", "r"))
		local strings = handle:read("*a")
		handle:close()

		local keys = {}
		local keyCount = 0
		for key in string.gmatch(strings, '"([%w_]+)"%s*:') do
			keys[key] = true
			keyCount = keyCount + 1
		end
		eq(lang .. "/Recipes.json holds one name per recipe and no more",
			keyCount, #names)
		for n = 1, #names do
			check(lang .. "/Recipes.json names the recipe " .. names[n],
				keys[names[n]] == true)
			-- And it says something: an empty value is a miss too, by the same
			-- bytecode -- isEmpty at offset 18 falls through to `return the key`.
			local said = string.match(strings,
				'"' .. names[n] .. '"%s*:%s*"([^"]*)"')
			check(lang .. "'s name for " .. names[n] .. " is not empty",
				said ~= nil and said ~= "")
		end
		for key in pairs(keys) do
			check(lang .. "/Recipes.json's key " .. key .. " is a recipe",
				declared[key] == true)
		end
	end
end

--
-- Writing on a floppy: the inventory menu, the box, and the two writes
--
-- CeroSecFloppyMenu is loaded here rather than with the files at the top, because
-- it needs ISTextBox, ItemTag and a HaloTextHelper stood in for, and those are
-- this block's business and nobody else's.
--

do
	-- The game's own enum, faked as six distinct values. DISTINCT on purpose: the
	-- write test walks six tags and asks the inventory about each, and six copies of
	-- one value would let a check pass while five of the six were never asked.
	_G.ItemTag = { WRITE = "t.WRITE", BLUE_PEN = "t.BLUE_PEN", PEN = "t.PEN",
		PENCIL = "t.PENCIL", RED_PEN = "t.RED_PEN", GREEN_PEN = "t.GREEN_PEN" }

	local halos = {}
	_G.HaloTextHelper = { addBadText = function(who, text)
		halos[#halos + 1] = { who = who, text = text }
	end }

	_G.getItemNameFromFullType = function(fullType)
		return "name-of:" .. fullType
	end

	-- ISTextBox, faked down to what the pattern touches: the constructor's
	-- arguments, initialise, addToUIManager, and the entry the OK button reads
	-- through button.parent.entry (ISTextBox.lua:134 dispatches
	-- onclick(target, button, param1, param2, ...)).
	local boxes = {}
	local TextBox = {}
	TextBox.__index = TextBox
	_G.ISTextBox = { new = function(_, x, y, w, h, text, entryText, target, onclick,
			player, param1, param2)
		local box = setmetatable({ x = x, y = y, width = w, height = h,
			text = text, entryText = entryText, target = target, onclick = onclick,
			player = player, param1 = param1, param2 = param2,
			initialised = 0, added = 0 }, TextBox)
		box.entry = { text = entryText, getText = function(self) return self.text end }
		boxes[#boxes + 1] = box
		return box
	end }
	function TextBox:initialise() self.initialised = self.initialised + 1 end
	function TextBox:addToUIManager() self.added = self.added + 1 end
	-- Press a button on it, the way ISTextBox does.
	function TextBox:press(internal, typed)
		if typed ~= nil then self.entry.text = typed end
		self.onclick(self.target, { internal = internal, parent = self }, self.param1,
			self.param2)
	end

	local tags = {}
	local player = newPlayer()
	player.getInventory = function()
		return { containsTagRecurse = function(_, tag) return tags[tag] == true end }
	end
	_G.getSpecificPlayer = function() return player end

	-- The gate, spied on. CeroSecOS.labelOk is the one place the charset and the
	-- ceiling live and it is benched against the REAL core in os_test.lua; the core is
	-- not loaded here, and a copy of its rule typed into this file would be a bench
	-- whose reference is itself. So what stands in for it here records what it was
	-- asked and answers what the block tells it to -- which is what lets the checks
	-- below be about the MENU obeying the gate rather than about the rule.
	local asked = {}
	local verdict = true
	CeroSecOS.labelOk = function(v)
		asked[#asked + 1] = v
		return verdict
	end

	-- AND THE OTHER HALF OF A LABEL, spied on for the same reason the gate is.
	-- CeroSecContent.markLabel is what puts the tooltip line and the printed look
	-- on an item, it is benched against the real catalogue in content_test.lua, and
	-- the catalogue is not loaded here. So what stands in for it records what it was
	-- asked -- which is what lets the checks below be about the PEN calling it with
	-- the right answer rather than about what the mark itself writes.
	local marks = {}
	_G.CeroSecContent = _G.CeroSecContent or {}
	CeroSecContent.markLabel = function(item, printed)
		marks[#marks + 1] = { item = item, printed = printed }
	end

	local chunk = assert(loadfile(LUA .. "client/CeroSec/CeroSecFloppyMenu.lua"))
	chunk()

	-- A disk that answers the name API the way the engine does.
	local GENERIC = "3.5 inch Floppy Disk"
	local function newFloppy(fullType)
		local data = {}
		return {
			__class = "InventoryItem",
			type = fullType or CeroSec.FLOPPY_TYPES[1],
			name = GENERIC, customName = false, synced = 0, data = data,
			getFullType = function(self) return self.type end,
			getName = function(self) return self.name end,
			setName = function(self, v) self.name = v end,
			isCustomName = function(self) return self.customName end,
			setCustomName = function(self, v) self.customName = v end,
			syncItemFields = function(self) self.synced = self.synced + 1 end,
			getModData = function(self) return self.data end,
		}
	end

	-- The game's own entries first, then ours: the menu is fully built before the
	-- event this file listens on is fired (ISInventoryPaneContextMenu.lua:935), so
	-- what "one entry" means below is one entry of OURS at the top of a menu with
	-- Grab and Equip under it -- which is what `ours` counts.
	local function fill(items)
		local context = withVanilla(ContextMenu.new())
		CeroSecFloppyMenu.OnFillInventoryObjectContextMenu(0, context, items)
		return context
	end
	local function ours(items)
		return ourLabels(fill(items))
	end

	--
	-- Something to write with
	--
	local disk = newFloppy()
	tags = {}
	eq("no pen, no entry at all", #ours({ disk }), 0)
	eq("and canWrite says so", CeroSecFloppyMenu.canWrite(player), false)

	-- Each of the six tags on its own is enough. One at a time, because a test that
	-- put all six on the survivor would pass with five of them never consulted.
	local SIX = { "t.WRITE", "t.BLUE_PEN", "t.PEN", "t.PENCIL", "t.RED_PEN",
		"t.GREEN_PEN" }
	eq("six tags, the six vanilla asks about", #CeroSecFloppyMenu.writeTags(), 6)
	for i = 1, #SIX do
		tags = { [SIX[i]] = true }
		eq(SIX[i] .. " alone is enough to write", CeroSecFloppyMenu.canWrite(player), true)
		eq("and it puts the entry on the menu", #ours({ disk }), 1)
	end
	-- A tag that is not one of the six is not a pen.
	tags = { ["t.SCREWDRIVER"] = true }
	eq("a tag that is not one of the six writes nothing",
		CeroSecFloppyMenu.canWrite(player), false)

	tags = { ["t.PEN"] = true }

	--
	-- The entries
	--
	eq("nothing on a menu with no disk in the selection", #ours({}), 0)
	local other = newFloppy("Base.Hammer")
	eq("and nothing for an item that is not a disk", #ours({ other }), 0)

	local menu = fill({ other, disk })
	eq("an unlabelled disk offers one entry", #ourLabels(menu), 1)
	eq("named for writing on it", menu.labels[1], "ContextMenu_CeroSec_LabelFloppy")
	-- And it is the FIRST entry on the menu, above vanilla's own.
	checkTop("an unlabelled disk", menu, { "ContextMenu_CeroSec_LabelFloppy" })
	eq("carrying the disk", menu.options[1].target, disk)
	eq("and the box is what it opens", menu.options[1].callback,
		CeroSecFloppyMenu.onLabel)
	eq("with the player behind it", menu.options[1].arg, player)

	-- A stack of identical disks arrives as one table with an items array inside it,
	-- which is the shape a naive loop walks straight past.
	local stack = { items = { disk, newFloppy() } }
	local stacked = fill({ stack })
	eq("a stack of disks is still one entry", #ourLabels(stacked), 1)
	eq("and the pen lands on the first of it", stacked.options[1].target, disk)

	--
	-- Writing, through the box
	--
	boxes = {}
	CeroSecFloppyMenu.onLabel(disk, player)
	eq("one box opened", #boxes, 1)
	local box = boxes[1]
	eq("initialised once", box.initialised, 1)
	eq("and put on the screen once", box.added, 1)
	eq("with a nil target, so the handler's first argument is that nil",
		box.target, nil)
	eq("the handler is ours", box.onclick, CeroSecFloppyMenu.onLabelClick)
	eq("the player object is the first thing after the button", box.param1, player)
	eq("and the disk the second", box.param2, disk)
	eq("the box opens empty on an unlabelled disk", box.entryText, "")

	-- Cancel writes nothing.
	box:press("CANCEL", "IGNORED")
	eq("cancel leaves the name alone", disk.name, GENERIC)
	eq("and does not make it custom", disk.customName, false)
	eq("and writes nothing on the record", disk.data.label, nil)

	-- OK writes it: the name, the flag, the sync, and the disk's own field.
	box = boxes[1]
	marks = {}
	box:press("OK", "BACKUP 93")
	eq("the name is the label", disk.name, "BACKUP 93")
	eq("and it is a custom name, or the game would not save it", disk.customName, true)
	eq("synced once, the way Rename Bag syncs", disk.synced, 1)
	eq("and the record carries it too", disk.data.label, "BACKUP 93")
	-- A PEN CANNOT PRINT. Whatever he wrote, what he has written is handwriting,
	-- and the item is marked as such: the tooltip line and -- on a disk that came
	-- out of a box printed -- the loss of the printed look.
	eq("the pen marks the disk", #marks, 1)
	eq("as handwritten", marks[1].printed, false)
	eq("and on the disk he wrote on", marks[1].item, disk)

	-- Even when what he wrote is word for word a product's own line. The pen is
	-- what decides this and not the string: a survivor with a biro cannot make a
	-- factory sticker.
	marks = {}
	CeroSecFloppyMenu.writeLabel(disk, "CeroSec UTILITIES 1.0")
	eq("a printed line written in biro is still handwriting", marks[1].printed, false)
	CeroSecFloppyMenu.writeLabel(disk, "BACKUP 93")

	-- Now the menu says something different: change it, or take it off.
	menu = fill({ disk })
	eq("a labelled disk offers two entries", #ourLabels(menu), 2)
	-- The two of them, in this order, and both above the game's own entries.
	checkTop("a labelled disk", menu,
		{ "ContextMenu_CeroSec_RelabelFloppy", "ContextMenu_CeroSec_EraseLabel" })
	eq("change it first", menu.labels[1], "ContextMenu_CeroSec_RelabelFloppy")
	eq("then take it off", menu.labels[2], "ContextMenu_CeroSec_EraseLabel")
	eq("the first opens the same box", menu.options[1].callback,
		CeroSecFloppyMenu.onLabel)
	eq("the second erases", menu.options[2].callback, CeroSecFloppyMenu.onErase)
	eq("and labelOn reads it back", CeroSecFloppyMenu.labelOn(disk), "BACKUP 93")

	-- Relabelling opens the box with what is already written in it, so a survivor
	-- fixing a typo does not retype the line.
	boxes = {}
	CeroSecFloppyMenu.onLabel(disk, player)
	eq("the box opens on what is written there", boxes[1].entryText, "BACKUP 93")
	boxes[1]:press("OK", "WORK")
	eq("and a relabel replaces it", disk.name, "WORK")
	eq("on the record too", disk.data.label, "WORK")

	--
	-- The menu OBEYS the gate, and the gate is the OS core's
	--
	-- CeroSecOS.labelOk is the one place the charset and the ceiling live, and it is
	-- benched against the real core in os_test.lua -- the core is not loaded here and
	-- a copy of its rule typed into this file would be a bench whose reference is
	-- itself. What is asserted HERE is the other half: that the box asks the gate,
	-- asks it about exactly what was typed, and does nothing at all when it says no.
	CeroSecFloppyMenu.writeLabel(disk, "WORK")

	verdict = false
	boxes, halos, asked = {}, {}, {}
	CeroSecFloppyMenu.onLabel(disk, player)
	boxes[1]:press("OK", "whatever was typed")
	eq("the gate was asked", #asked, 1)
	eq("about exactly what was typed", asked[1], "whatever was typed")
	eq("a refusal writes no name", disk.name, "WORK")
	eq("and nothing on the record", disk.data.label, "WORK")
	eq("and the survivor is told", #halos, 1)
	eq("to his face", halos[1].who, player)
	eq("in the mod's own words", halos[1].text, "IGUI_CeroSec_LabelBad")

	-- An empty entry never reaches the gate at all: it is a survivor who changed his
	-- mind, and it gets no telling-off. A box that erased on an empty OK would erase a
	-- label somebody opened in order to READ it.
	boxes, halos, asked = {}, {}, {}
	CeroSecFloppyMenu.onLabel(disk, player)
	boxes[1]:press("OK", "")
	eq("an empty entry is not even asked about", #asked, 0)
	eq("says nothing", #halos, 0)
	eq("and changes nothing", disk.name, "WORK")

	verdict = true
	boxes, halos, asked = {}, {}, {}
	CeroSecFloppyMenu.onLabel(disk, player)
	boxes[1]:press("OK", "PAYROLL 93")
	eq("a label the gate accepts is written", disk.name, "PAYROLL 93")
	eq("on the record too", disk.data.label, "PAYROLL 93")
	eq("with nothing said about it", #halos, 0)

	--
	-- Taking it off
	--
	CeroSecFloppyMenu.writeLabel(disk, "GONE")
	local synced = disk.synced
	marks = {}
	CeroSecFloppyMenu.eraseLabel(disk)
	eq("the erase marks the disk too", #marks, 1)
	eq("as having nothing written on it at all", marks[1].printed, nil)
	eq("on the disk he rubbed out", marks[1].item, disk)
	eq("the name goes back to the item's own, looked up by full type",
		disk.name, "name-of:" .. disk.type)
	eq("it is not a custom name any more", disk.customName, false)
	eq("synced again, so the erase reaches the other side", disk.synced, synced + 1)
	eq("and the record's label is gone", disk.data.label, nil)
	eq("so labelOn reads nothing", CeroSecFloppyMenu.labelOn(disk), nil)
	eq("and the menu is back to one entry", #ours({ disk }), 1)

	-- onErase is the menu's own door onto that.
	CeroSecFloppyMenu.writeLabel(disk, "AGAIN")
	CeroSecFloppyMenu.onErase(disk, player)
	eq("the menu's erase erases", CeroSecFloppyMenu.labelOn(disk), nil)

	-- labelOn never reads an ordinary name as a label: every disk in the game has
	-- one, and reading it would put "3.5 inch Floppy Disk" in the mount listing of
	-- every machine in Kentucky.
	local fresh = newFloppy()
	eq("an unlabelled disk has no label", CeroSecFloppyMenu.labelOn(fresh), nil)
	fresh.name = "SNEAKY"
	eq("a name without the custom flag is still no label",
		CeroSecFloppyMenu.labelOn(fresh), nil)

	-- Every key this menu can print is one the mod ships a string for, in both
	-- languages.
	for _, lang in ipairs({ "EN", "FR" }) do
		for _, pair in ipairs({ { "ContextMenu.json", "ContextMenu_CeroSec_LabelFloppy" },
				{ "ContextMenu.json", "ContextMenu_CeroSec_RelabelFloppy" },
				{ "ContextMenu.json", "ContextMenu_CeroSec_EraseLabel" },
				{ "IG_UI.json", "IGUI_CeroSec_LabelFloppy" },
				{ "IG_UI.json", "IGUI_CeroSec_LabelBad" } }) do
			local handle = assert(io.open(
				"42/media/lua/shared/Translate/" .. lang .. "/" .. pair[1], "r"))
			local strings = handle:read("*a")
			handle:close()
			check(lang .. "/" .. pair[1] .. " defines " .. pair[2],
				string.find(strings, '"' .. pair[2] .. '"', 1, true) ~= nil)
		end
	end
end

--
-- The hardware menu on a fixture, and the reason it greys an entry with
--
-- The right-click menu on a door, a window, a light switch or an oven. What is
-- asserted is the WORD: the server decides the same question in one shared
-- function (CeroSecModules.fittingRefusal) and the entry has to be greyed with
-- that very answer, or a survivor reads one reason on the menu and meets
-- another on the wire -- which is the silence this whole rung was written to
-- avoid, because these commands answer nothing.
--
-- The key is BUILT from the reason word (CeroSecModuleMenu.tooltipFor), so what
-- is checked here is the key a player really gets and not a second list beside
-- the first.
--

do
	_G.Perks = { Electricity = "Electricity" }
	_G.getItemNameFromFullType = function(fullType) return fullType end
	_G.luautils = { walkAdj = function() return true end,
		walkAdjWindowOrDoor = function() return true end }
	_G.ISTimedActionQueue = { add = function() end }
	_G.ISCeroSecModuleAction = { new = function() return {} end }
	_G.SafeHouse = nil

	-- A square, with the two questions the rules ask of one: which room it is in
	-- (isInARoom, for where HE is standing) and where it is (getX/getY, for the
	-- safehouse box the FIXTURE stands in).
	local function square(x, y, inside)
		return {
			getX = function() return x end,
			getY = function() return y end,
			getZ = function() return 0 end,
			isInARoom = function() return inside end,
			getObjects = function() return { size = function() return 0 end } end,
		}
	end
	local inside = square(11, 10, true)
	local pavement = square(10, 9, false)

	-- A fixture: its class, its square, and every getter the nine fitsOn rules
	-- and the state rules ask of one. ALL of them and not just its own module's,
	-- because this menu now asks every module about every fixture -- that is what
	-- decides which lines are there at all -- and a fake with only the getters
	-- its own module needs would die on the first question somebody else's asks.
	-- modData is real, because installedOn walks it.
	local function fixture(class, sq)
		local o = { __class = class, modData = {}, square = sq, open = false,
			activated = false, curtainOpen = false, deviceOn = false }
		o.getSquare = function() return o.square end
		o.hasModData = function() return true end
		o.getModData = function() return o.modData end
		o.transmitModData = function() end
		o.IsOpen = function() return o.open end
		o.isActivated = function() return o.activated end
		o.Activated = function() return o.activated end
		o.isExterior = function() return true end
		o.isDoor = function() return true end
		-- A door's sheet: HasCurtains() answers THE DOOR when there is one and
		-- null otherwise, which is the engine's own shape (IsoDoor, offsets 0-12).
		o.hasCurtain = false
		o.HasCurtains = function() if o.hasCurtain then return o end return nil end
		o.isCurtainOpen = function() return o.curtainOpen end
		-- A set with no device data is a sprite, so the fake answers one only for
		-- the two classes that really carry it.
		o.getDeviceData = function()
			if class ~= "IsoTelevision" and class ~= "IsoRadio" then return nil end
			return { getIsTurnedOn = function() return o.deviceOn end }
		end
		-- The four calls a hover is supposed to make, recorded rather than
		-- rendered: what the bench below proves is that they are made and
		-- unmade, not what they draw.
		o.lit = nil
		o.setHighlighted = function(_, player, on) o.lit = on end
		o.setHighlightColor = function() end
		o.setOutlineHighlight = function(_, player, on) o.outline = on end
		o.setOutlineHighlightCol = function() end
		return o
	end

	local door = fixture("IsoDoor", inside)
	local light = fixture("IsoLightSwitch", inside)
	local stove = fixture("IsoStove", inside)
	local window = fixture("IsoWindow", inside)
	local curtain = fixture("IsoCurtain", inside)
	local washer = fixture("IsoClothingWasher", inside)
	local generator = fixture("IsoGenerator", inside)
	local telly = fixture("IsoTelevision", inside)
	local wireless = fixture("IsoRadio", inside)
	local fridge = fixture("IsoObject", inside)

	local stand = inside
	local carried = {}
	local level = 5
	local known = true
	local player = {
		getVehicle = function() return nil end,
		getCurrentSquare = function() return stand end,
		getUsername = function() return "carter" end,
		getPerkLevel = function() return level end,
		-- Vanilla's own one-call question, which is what the menu asks before it
		-- tells a survivor he has no box: isRecipeKnown(String) is the sandbox
		-- option, the cheat and the known list in one (javap -c, offsets 0-53).
		isRecipeKnown = function(_, name)
			return known and type(name) == "string" and name ~= ""
		end,
		getInventory = function()
			return { getFirstTypeRecurse = function(_, fullType)
				for i = 1, #carried do
					if carried[i] == fullType then return { type = fullType } end
				end
				return nil
			end }
		end,
	}
	_G.getSpecificPlayer = function() return player end

	local chunk = assert(loadfile(LUA .. "client/CeroSec/CeroSecModuleMenu.lua"))
	chunk()

	-- One row of the submenu a right-click on a fixture builds, or nil.
	--
	-- Found by the MODULE the option carries and not by its label, because every
	-- Install line on this menu has the same label key -- the module's name is
	-- the argument, and the bench's getText answers the key alone. Keyed by the
	-- label, nine entries would be one and every assertion below would be about
	-- whichever module happened to come last.
	local function entry(object, id, install)
		local want = install and "ContextMenu_CeroSec_Install"
			or "ContextMenu_CeroSec_Remove"
		local context = withVanilla(ContextMenu.new())
		CeroSecModuleMenu.OnFillWorldObjectContextMenu(0, context, { object }, false)
		for j = 1, #context.subs do
			local sub = context.subs[j].menu
			for i = 1, #sub.options do
				local module = sub.options[i].args and sub.options[i].args[3]
				if type(module) == "table" and module.id == id
						and sub.labels[i] == want then
					return sub.options[i]
				end
			end
		end
		return nil
	end

	-- Every entry carries its tooltip now, greyed or not: the module's own
	-- description, and the reason on the line UNDER it when there is one. The
	-- bench's getText answers the key alone, so the line is two keys with a break
	-- between them and each half reads on its own -- which is also what makes
	-- "it has a description and no reason" a thing that can be asserted.
	--
	-- The break is the GAME's markup and the bench spells it out rather than
	-- skipping to the text after it: "<br>" is not a command ISRichTextPanel knows
	-- (ISUI/ISRichTextPanel.lua:16-27) and its tokeniser eats the word in front of
	-- an unspaced tag (:456-481), so a pattern loose about the separator is a
	-- pattern that would have stayed green through the very defect this pins.
	local SEP = " <LINE> <RGB:1,0,0> "
	local function desc(option)
		local head = string.match(option.toolTip.description, "^(.-)" .. SEP)
		return head or option.toolTip.description
	end
	local function reason(option)
		return string.match(option.toolTip.description, SEP .. "(.*)$")
	end
	-- The ids the submenu offers, in the order it offers them.
	local function idsOn(object)
		local context = withVanilla(ContextMenu.new())
		CeroSecModuleMenu.OnFillWorldObjectContextMenu(0, context, { object }, false)
		local out = {}
		for j = 1, #context.subs do
			local sub = context.subs[j].menu
			for i = 1, #sub.options do
				local module = sub.options[i].args and sub.options[i].args[3]
				if type(module) == "table" then out[#out + 1] = module.id end
			end
		end
		return table.concat(out, " ")
	end
	-- Is there a "CeroSec: <object>" parent at all?
	local function parentOn(object)
		local context = withVanilla(ContextMenu.new())
		CeroSecModuleMenu.OnFillWorldObjectContextMenu(0, context, { object }, false)
		for i = 1, #context.labels do
			if context.labels[i] == "ContextMenu_CeroSec_Fixture" then return true end
		end
		return false
	end

	_G.SandboxVars = { CeroSec = { HardwareRequired = true } }
	carried = { "CeroSec.MagneticContact", "Base.Screwdriver" }

	--
	-- 0. WHICH LINES ARE THERE AT ALL, which is what a survivor sees first
	--
	-- A module that does not fit this SORT of fixture is not a line. Everything
	-- that could ever go on one is, carried or not: a box he has never been told
	-- about is a box he will never look for. Asserted as the WHOLE list and in
	-- order, because the way this goes wrong is the entry nobody meant to add.
	--
	carried = {}
	door.open = true
	eq("a door offers the three that go on a door", idsOn(door),
		"contact strike operator")
	eq("a light switch offers the relay and nothing else", idsOn(light), "relay")
	eq("a window offers the contact and the sash operator", idsOn(window),
		"contact window")
	eq("a curtain offers the motor", idsOn(curtain), "curtain")
	eq("an oven offers the appliance switch", idsOn(stove), "appliance")
	eq("and so does a washer", idsOn(washer), "appliance")
	eq("a generator offers its own switch", idsOn(generator), "genset")
	eq("a television offers the tuner control", idsOn(telly), "tuner")
	eq("and a radio set the same one", idsOn(wireless), "tuner")
	-- A door with a sheet on it grows a fourth line and loses none.
	door.hasCurtain = true
	eq("a door with a sheet on it offers the curtain motor too", idsOn(door),
		"contact strike operator curtain")
	door.hasCurtain = false
	-- And nothing this mod has anything to say about gets no menu at all.
	eq("a fridge offers nothing", idsOn(fridge), "")
	check("and has no CeroSec: parent entry over it", not parentOn(fridge))
	check("while a door does", parentOn(door))

	--
	-- 0b. THE PARENT IS NAMED BY THE OBJECT, and the two survol rules
	--
	-- Genre first, since neither fake fixture carries a sprite: a door and a
	-- window read as two different genres, which is what lets a click on both
	-- at once (a curtained window) show two parents and not one merged guess.
	eq("a door genre-names itself", CeroSecModuleMenu.genreName(door),
		"ContextMenu_CeroSec_GenreDoor")
	eq("a window differently", CeroSecModuleMenu.genreName(window),
		"ContextMenu_CeroSec_GenreWindow")
	check("the two genres disagree",
		CeroSecModuleMenu.genreName(door) ~= CeroSecModuleMenu.genreName(window))
	-- A microwave is an IsoStove too (isStove reads the container, not the
	-- sprite), and its own isMicrowave() -- confirmed public on the jar
	-- with javap -- is what tells the two apart when nobody renamed it.
	eq("a plain oven genre-names itself Stove",
		CeroSecModuleMenu.genreName(stove), "ContextMenu_CeroSec_GenreStove")
	stove.isMicrowave = function() return true end
	eq("and a microwave, distinctly",
		CeroSecModuleMenu.genreName(stove), "ContextMenu_CeroSec_GenreMicrowave")
	stove.isMicrowave = function() return false end
	eq("false answers Stove like no method at all",
		CeroSecModuleMenu.genreName(stove), "ContextMenu_CeroSec_GenreStove")
	stove.isMicrowave = nil
	-- The sprite's own name wins when there is one -- RED first: a fake with
	-- no getSprite at all answers the genre, then a sprite with CustomName on
	-- it answers that instead.
	eq("with no sprite, the door falls back to its genre",
		CeroSecModuleMenu.nameOf(door), "ContextMenu_CeroSec_GenreDoor")
	_G.Translator = { getMoveableDisplayName = function(n) return n end }
	door.getSprite = function()
		return { getProperties = function()
			return { has = function(_, k) return k == "CustomName" end,
				get = function(_, k) return "Vault Door" end }
		end }
	end
	eq("a sprite's CustomName beats the genre", CeroSecModuleMenu.nameOf(door),
		"Vault Door")
	door.getSprite = nil

	-- Two objects sharing one right-click get two parents, one call each: the
	-- shared helper hands the SAME sub back the second time it is asked about
	-- the SAME object, and a different one the same context.
	do
		local shared = withVanilla(ContextMenu.new())
		local subA = CeroSecModuleMenu.fixtureParent(shared, door)
		local subA2 = CeroSecModuleMenu.fixtureParent(shared, door)
		check("the same object gets the same submenu twice", subA == subA2)
		local subB = CeroSecModuleMenu.fixtureParent(shared, window)
		check("a different object gets a different one", subA ~= subB)
		local parents = 0
		for i = 1, #shared.options do
			if shared.options[i].cerosecFixture ~= nil then parents = parents + 1 end
		end
		eq("and the context carries exactly one parent per object", parents, 2)
		for i = 1, #shared.options do
			if shared.options[i].cerosecFixture ~= nil then
				check("each fixture parent carries the icon",
					shared.options[i].iconTexture ~= nil)
			end
		end
	end

	-- getTexture answering nil (asset missing, or a build without it) must not
	-- break the menu: setIcon leaves iconTexture unset rather than crash, and
	-- the option is otherwise unharmed. Reload the file with getTexture
	-- replaced, since the loaded texture is cached in a local the first time
	-- setIcon runs.
	do
		local savedGetTexture = _G.getTexture
		_G.getTexture = function() return nil end
		local chunk = assert(loadfile(LUA .. "client/CeroSec/CeroSecMenu.lua"))
		chunk()
		local lone = withVanilla(ContextMenu.new())
		CeroSecModuleMenu.fixtureParent(lone, door)
		local parent
		for i = 1, #lone.options do
			if lone.options[i].cerosecFixture == door then parent = lone.options[i] end
		end
		check("a missing texture leaves iconTexture unset", parent.iconTexture == nil)
		check("but the entry itself still exists", parent.name ~= nil)
		_G.getTexture = savedGetTexture
		chunk = assert(loadfile(LUA .. "client/CeroSec/CeroSecMenu.lua"))
		chunk()
	end

	-- Two of the SAME genre under one click -- two doors, not a door and a
	-- window -- because cerosecSub is looked up by option.cerosecFixture ==
	-- object and never by name or genre: a lookup keyed the wrong way would
	-- pass this with two different kinds and still land a second door's
	-- entries in the first door's parent.
	do
		local doorA = fixture("IsoDoor", inside)
		local doorB = fixture("IsoDoor", inside)
		local shared = withVanilla(ContextMenu.new())
		local subA = CeroSecModuleMenu.fixtureParent(shared, doorA)
		local subB = CeroSecModuleMenu.fixtureParent(shared, doorB)
		check("two doors under one click get two different submenus", subA ~= subB)
		check("asking about the first again still returns its own",
			CeroSecModuleMenu.fixtureParent(shared, doorA) == subA)
		-- And each parent's hover lights only its own door.
		local parentA, parentB
		for i = 1, #shared.options do
			if shared.options[i].cerosecFixture == doorA then parentA = shared.options[i] end
			if shared.options[i].cerosecFixture == doorB then parentB = shared.options[i] end
		end
		local menu = { player = 0 }
		parentA.onHighlight(parentA, menu, true, unpack(parentA.onHighlightParams))
		check("hovering the first door's parent lights only the first",
			doorA.lit == true and doorB.lit == nil)
		parentA.onHighlight(parentA, menu, false, unpack(parentA.onHighlightParams))
	end

	-- The survol itself: RED first (nothing lit before the hover), then lit,
	-- then dark again -- the exact toggle ISContextMenu drives through
	-- onHighlight, never called here directly by name.
	do
		local lone = withVanilla(ContextMenu.new())
		CeroSecModuleMenu.fixtureParent(lone, door)
		local parent = lone.options[1]
		local menu = { player = 0 }
		check("nothing is lit before any hover", door.lit == nil and door.outline == nil)
		parent.onHighlight(parent, menu, true, unpack(parent.onHighlightParams))
		check("hovering the parent lights the door", door.lit == true and door.outline == true)
		-- The same call with isHighlighted false is what
		-- ISContextMenu:checkHighlightedOption makes on every exit -- close,
		-- Escape, a click elsewhere, another entry hovered -- and this file never
		-- has to call it by name.
		parent.onHighlight(parent, menu, false, unpack(parent.onHighlightParams))
		check("and every exit turns it back off", door.lit == false and door.outline == false)
	end

	-- EVERY LINE CARRIES ITS DESCRIPTION, and a survivor carrying nothing at all
	-- is the case this rung exists for: greyed, with what the box does on the
	-- first line and how to get one on the second.
	carried = { "Base.Screwdriver" }
	local row = entry(door, "operator", true)
	eq("an entry for a box he has never seen is greyed", row.notAvailable, true)
	eq("and says what a door operator is", desc(row),
		"Tooltip_CeroSec_ModuleDesc_operator")
	eq("with the reason under it", reason(row), "Tooltip_CeroSec_ModuleItem")
	known = false
	row = entry(door, "operator", true)
	eq("and a survivor who has not read the guide is sent to the guide",
		reason(row), "Tooltip_CeroSec_ModuleRecipe")
	known = true

	-- Electricity 0: every line greyed with the trade, description and all.
	carried = { "CeroSec.MagneticContact", "CeroSec.ElectricStrike",
		"CeroSec.DoorOperator", "Base.Screwdriver" }
	level = 0
	for _, id in ipairs({ "contact", "strike", "operator" }) do
		row = entry(door, id, true)
		eq(id .. " is greyed at Electricity 0", row.notAvailable, true)
		eq("with the trade as the reason", reason(row), "Tooltip_CeroSec_NeedSkill")
		eq("and its own description over it", desc(row),
			"Tooltip_CeroSec_ModuleDesc_" .. id)
	end
	level = 5
	-- And with everything in hand: a live entry that still says what it is.
	row = entry(door, "contact", true)
	eq("a fittable entry is not greyed", row.notAvailable, nil)
	eq("and still carries its description", desc(row),
		"Tooltip_CeroSec_ModuleDesc_contact")
	eq("with nothing under it", reason(row), nil)

	-- The refusals about THIS fixture rather than about fixtures of its sort are
	-- lines, not silences: the strike on a door no lock bites, and a leaf of a
	-- garage door.
	local interior = fixture("IsoDoor", inside)
	interior.open = true
	interior.isExterior = function() return false end
	interior.getOppositeSquare = function() return inside end
	interior.getSquare = function() return inside end
	inside.getRoom = function() return { getName = function() return "office" end } end
	row = entry(interior, "strike", true)
	check("an interior door still offers the strike", row ~= nil)
	eq("greyed with the lock's own reason", reason(row), "Tooltip_CeroSec_NoLock")

	-- EVERY MODULE HAS A DESCRIPTION, in both languages, and nothing has one that
	-- is not a module. Both directions, because a key nobody wrote comes out on
	-- the glass as its own name and a key left behind by a module that went is a
	-- line nothing can print.
	for _, lang in ipairs({ "EN", "FR" }) do
		local handle = assert(io.open(
			"42/media/lua/shared/Translate/" .. lang .. "/Tooltip.json", "r"))
		local strings = handle:read("*a")
		handle:close()
		local seen = 0
		for i = 1, #CeroSecModules.LIST do
			local key = "Tooltip_CeroSec_ModuleDesc_" .. CeroSecModules.LIST[i].id
			check(lang .. " Tooltip.json defines " .. key,
				string.find(strings, '"' .. key .. '"', 1, true) ~= nil)
			seen = seen + 1
		end
		local defined = 0
		for _ in string.gmatch(strings, '"Tooltip_CeroSec_ModuleDesc_') do
			defined = defined + 1
		end
		eq(lang .. " has a description for the nine modules and nothing else",
			defined, seen)
		-- And the recipe and the missing box have their own lines.
		for _, key in ipairs({ "Tooltip_CeroSec_ModuleItem",
				"Tooltip_CeroSec_ModuleRecipe" }) do
			check(lang .. " Tooltip.json defines " .. key,
				string.find(strings, '"' .. key .. '"', 1, true) ~= nil)
		end
	end
	-- And every recipe the list names is really in the script file: a name with
	-- no craftRecipe behind it is a survivor told to read a book that teaches
	-- nothing.
	local handle = assert(io.open("common/media/scripts/recipes_cerosec.txt", "r"))
	local recipes = handle:read("*a")
	handle:close()
	for i = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[i]
		check("a recipe name for " .. module.id, type(module.recipe) == "string")
		check(module.recipe .. " is a craftRecipe in the scripts",
			string.find(recipes, "craftRecipe " .. module.recipe, 1, true) ~= nil)
	end

	carried = { "CeroSec.MagneticContact", "Base.Screwdriver" }

	-- 1. A shut door. The entry is THERE -- he owns the box and can go and fix
	-- the reason -- and it is greyed with the word the server refuses on.
	door.open = false
	local option = entry(door, "contact", true)
	check("a shut door still offers the install", option ~= nil)
	eq("greyed", option.notAvailable, true)
	eq("with the door's own word", reason(option), "Tooltip_CeroSec_ModuleClosed")
	eq("which is the word the server refuses on",
		CeroSecModuleMenu.tooltipFor(
			CeroSecModules.fittingRefusal(door, "contact", player)),
		reason(option))

	-- Open it and the entry comes alive.
	door.open = true
	option = entry(door, "contact", true)
	eq("an open door is not greyed", option.notAvailable, nil)
	eq("and carries no reason", reason(option), nil)
	eq("only what the box is", desc(option), "Tooltip_CeroSec_ModuleDesc_contact")

	-- 2. From the pavement, with the door open: the other word.
	stand = pavement
	option = entry(door, "contact", true)
	eq("from outside it is greyed", option.notAvailable, true)
	eq("with the word for where he is standing", reason(option),
		"Tooltip_CeroSec_ModuleOutside")
	stand = inside

	-- 3. A running oven, which is the other half of the rule: off, not open.
	carried = { "CeroSec.ApplianceSwitch", "Base.Screwdriver" }
	stove.activated = true
	option = entry(stove, "appliance", true)
	eq("a cooking oven is greyed", option.notAvailable, true)
	eq("with the word for a machine that is on", reason(option),
		"Tooltip_CeroSec_ModuleRunning")
	stove.activated = false
	option = entry(stove, "appliance", true)
	eq("a cold one is not", option.notAvailable, nil)

	-- 4. A light switch asks for nothing at all, lit or not.
	carried = { "CeroSec.Relay", "Base.Screwdriver" }
	light.activated = true
	option = entry(light, "relay", true)
	eq("a lit switch is not greyed", option.notAvailable, nil)

	-- 5. AND REMOVE IS HELD TO THE SAME RULE. A module anybody could unscrew from
	-- the pavement is the whole reason the rule exists, so the Remove entry is
	-- the one that matters most here.
	carried = { "Base.Screwdriver" }
	door.modData.cerosec = { contact = true }
	door.open = true
	stand = inside
	option = entry(door, "contact", false)
	check("a fitted module offers Remove", option ~= nil)
	eq("and is not greyed from inside with the door open", option.notAvailable, nil)

	door.open = false
	option = entry(door, "contact", false)
	eq("a shut door greys the removal", option.notAvailable, true)
	eq("with the same word the install got", reason(option),
		"Tooltip_CeroSec_ModuleClosed")

	door.open = true
	stand = pavement
	option = entry(door, "contact", false)
	eq("and so does the pavement", option.notAvailable, true)
	eq("with its own", reason(option), "Tooltip_CeroSec_ModuleOutside")
	stand = inside

	-- 6. Somebody else's safehouse, through the menu. The gate is the option and
	-- the fake is the engine's static (see the server bench for the bytecode).
	local house = { playerAllowed = function() return false end }
	_G.SafeHouse = { getSafeHouse = function() return house end }
	_G.SandboxVars = { CeroSec = { HardwareRequired = true, SafehouseModules = true } }
	option = entry(door, "contact", false)
	eq("a stranger's safehouse greys the entry", option.notAvailable, true)
	eq("with the word that says whose it is", reason(option),
		"Tooltip_CeroSec_ModuleSafehouse")
	-- And the option OFF is the default and the control.
	_G.SandboxVars = { CeroSec = { HardwareRequired = true } }
	option = entry(door, "contact", false)
	eq("with the option off it is the safehouse of nobody", option.notAvailable, nil)
	_G.SafeHouse = nil

	-- 7. The reason word IS the key, derived. A word nobody has written a line
	-- for would come out on the glass as its own name, so the derivation is
	-- asserted and not just its five answers.
	eq("the key is built from the word", CeroSecModuleMenu.tooltipFor("safehouse"),
		"Tooltip_CeroSec_ModuleSafehouse")
	eq("and from a one-letter one", CeroSecModuleMenu.tooltipFor("x"),
		"Tooltip_CeroSec_ModuleX")

	-- 8. And the fixture's own old refusals still say what they always said: the
	-- new words must not have swallowed them.
	carried = { "CeroSec.Relay", "Base.Screwdriver" }
	eq("a relay on a door is not a line at all", entry(door, "relay", true), nil)
	eq("and refusal still says so when it is asked",
		CeroSecModuleMenu.refusal(door, player,
			CeroSecModules.byId("relay"), true), "Tooltip_CeroSec_NoFixture")
	-- The box out of the door and into his bag, so that what is offered is an
	-- Install again: a module already on a fixture is a Remove and would be a
	-- different line answering a different question.
	door.modData.cerosec = nil
	carried = { "CeroSec.MagneticContact" }
	door.open = true
	option = entry(door, "contact", true)
	eq("and no screwdriver is still no screwdriver", reason(option),
		"Tooltip_CeroSec_NeedScrewdriver")

	_G.SandboxVars = nil
end

--
-- The cable menu on a fixture: which computers it offers, and why a line is grey
--
-- The other half of the menu above, held to the same rule: the server decides
-- every one of these questions in the shared one (CeroSecModules.linkRefusal and
-- unlinkRefusal) and the line has to be greyed with THAT word, built into the key
-- rather than looked up in a second list (CeroSecLinkMenu.tooltipFor).
--
-- What is different here is that the lines carry NUMBERS a survivor acts on --
-- which computer, how far it is, what the run costs, how much wire he is short --
-- so this block's getText keeps its arguments and every assertion below reads the
-- line a player really gets: "ksp-front-01, 12 tiles, 12 wire".
--
-- AND THE HOSTNAME IS READ FOR REAL, which is why the OS core is loaded here
-- rather than stood in for: the name on the line comes out of the state the server
-- mirrored into that machine's own modData, through the very function the server
-- reads /etc/hostname with (CeroSecOS.hostname). A fake hostOf would be a bench
-- for the bench's own idea of a name, and "the menu shows the hostname, the cable
-- is written against the SQUARE" is the one rule about this menu worth proving
-- twice -- so a machine is renamed below, with a cable already run to it.
--

do
	local OSDIR = LUA .. "shared/CeroSec/OS/"
	local OSFILES = { "CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron",
		"CeroSecOSDev", "CeroSecOSDisk", "CeroSecOSFS", "CeroSecOSNet",
		"CeroSecOSPath", "CeroSecOSRadio", "CeroSecOSScript", "CeroSecOSShell",
		"CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers", "CeroSecOSVM" }
	for i = 1, #OSFILES do
		local path = OSDIR .. OSFILES[i] .. ".lua"
		local chunk, err = loadfile(path)
		if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
		chunk()
	end

	-- getText, with its arguments kept: the mod's own strings put the hostname and
	-- the two numbers into the line with %1 %2 %3, and a bench that read the key
	-- alone could not tell "12 tiles, 12 wire" from "60 tiles, 4 wire".
	local realGetText = _G.getText
	_G.getText = function(key, ...)
		local n = select("#", ...)
		if n == 0 then return key end
		local args = {}
		for i = 1, n do args[i] = tostring((select(i, ...))) end
		return key .. "(" .. table.concat(args, ",") .. ")"
	end

	local walks = true
	_G.Perks = { Electricity = "Electricity" }
	_G.luautils = { walkAdj = function() return walks end,
		walkAdjWindowOrDoor = function() return walks end }
	local queued = {}
	_G.ISTimedActionQueue = { add = function(action) queued[#queued + 1] = action end }
	-- The action, recorded rather than run: what it was handed is the whole of what
	-- the click decides, and the walk is the real one above it.
	_G.ISCeroSecLinkAction = { new = function(_, character, object, mx, my, mz,
			link, wire)
		return { character = character, object = object, mx = mx, my = my, mz = mz,
			link = link, wire = wire }
	end }
	_G.SafeHouse = nil
	_G.SandboxVars = { CeroSec = { HardwareRequired = true } }

	local function square(x, y, z)
		return {
			getX = function() return x end,
			getY = function() return y end,
			getZ = function() return z end,
			isInARoom = function() return false end,
			getObjects = function() return { size = function() return 0 end } end,
		}
	end

	-- A fixture, with the getters the rules ask of one. modData is real, because
	-- everything about a cable is written in it.
	local function fixture(class, sq)
		local o = { __class = class, modData = {}, transmits = 0 }
		o.getSquare = function() return sq end
		o.hasModData = function() return true end
		o.getModData = function() return o.modData end
		o.transmitModData = function() o.transmits = o.transmits + 1 end
		o.IsOpen = function() return o.open == true end
		o.isActivated = function() return false end
		o.Activated = function() return false end
		o.isExterior = function() return true end
		o.isDoor = function() return true end
		o.HasCurtains = function() return nil end
		o.isCurtainOpen = function() return false end
		o.getDeviceData = function() return nil end
		return o
	end

	-- A machine on the client's own list of them: where it stands, and the
	-- IsoObject the server mirrors its whole state into, which is where the
	-- hostname comes from (SCeroSecObject:toModData, published by publishOS). A
	-- machine given no hostname here is a machine whose mirror has not arrived.
	local function machine(x, y, z, hostname)
		local luaObject = { x = x, y = y, z = z }
		if hostname ~= nil then
			local state = CeroSecOS.newState(hostname)
			local iso = { modData = { movableData = {
				[CeroSec.MOVABLE_DATA_KEY] = { os = state } } } }
			iso.hasModData = function() return true end
			iso.getModData = function() return iso.modData end
			-- Recorded, not rendered, exactly like the fixture's own -- what a
			-- row's survol lights is the COMPUTER and this is how the bench tells.
			iso.setHighlighted = function(_, player, on) iso.lit = on end
			iso.setHighlightColor = function() end
			iso.setOutlineHighlight = function(_, player, on) iso.outline = on end
			iso.setOutlineHighlightCol = function() end
			luaObject.state = state
			luaObject.getIsoObject = function() return iso end
			luaObject.iso = iso
		end
		return luaObject
	end

	local objects = {}
	_G.CCeroSecSystem = { instance = {
		getLuaObjectCount = function() return #objects end,
		getLuaObjectByIndex = function(_, i) return objects[i] end,
		getLuaObjectAt = function(_, x, y, z)
			for i = 1, #objects do
				local it = objects[i]
				if it.x == x and it.y == y and it.z == z then return it end
			end
			return nil
		end,
	} }

	local stand = square(10, 11, 0)
	local level = 5
	local reels = 40
	local tools = true
	local player = {
		getVehicle = function() return nil end,
		getCurrentSquare = function() return stand end,
		getUsername = function() return "carter" end,
		getPerkLevel = function() return level end,
		isRecipeKnown = function() return true end,
		getInventory = function()
			return {
				getFirstTypeRecurse = function(_, fullType)
					if tools and fullType == CeroSecModules.TOOL then
						return { type = fullType }
					end
					return nil
				end,
				-- Vanilla's count of an item it is about to consume, which is what
				-- the reel is asked for (CeroSecModules.wireCount).
				getCountTypeRecurse = function(_, fullType)
					if fullType == CeroSecModules.WIRE then return reels end
					return 0
				end,
			}
		end,
	}
	_G.getSpecificPlayer = function() return player end

	local chunk = assert(loadfile(LUA .. "client/CeroSec/CeroSecLinkMenu.lua"))
	chunk()

	-- The whole menu a right-click on a fixture builds, and the cable submenu
	-- hung off our own entry in it -- found by the OPTION it hangs off, because a
	-- submenu filled and never attached is a menu that leads nowhere and its rows
	-- would read perfectly right to a bench that only counted them.
	local function menuOn(object)
		local context = withVanilla(ContextMenu.new())
		CeroSecLinkMenu.OnFillWorldObjectContextMenu(0, context, { object }, false)
		return context
	end
	-- Matched by the FRONT of the label and not the whole of it, for the same
	-- reason rowFor below reads "ContextMenu_CeroSec_LinkTo(" that way: this
	-- block's own getText keeps its arguments, so the fixture's parent reads
	-- "ContextMenu_CeroSec_Fixture(Door)" and not the bare key.
	local function startsWith(label, want)
		return type(label) == "string" and string.sub(label, 1, #want) == want
	end
	-- The fixture's own parent -- "CeroSec: <name>" -- now shared with the
	-- module menu, one level above where "Link to computer" used to sit.
	local function fixtureSubOn(object)
		local context = menuOn(object)
		for i = 1, #context.subs do
			local parent = context.subs[i].option
			if type(parent) == "table"
					and startsWith(parent.label, "ContextMenu_CeroSec_Fixture") then
				return context.subs[i].menu, context
			end
		end
		return nil, context
	end
	local function subOn(object)
		local fixtureSub = fixtureSubOn(object)
		if fixtureSub == nil then return nil end
		for i = 1, #fixtureSub.subs do
			local parent = fixtureSub.subs[i].option
			if type(parent) == "table" and parent.label == "ContextMenu_CeroSec_Link" then
				return fixtureSub.subs[i].menu
			end
		end
		return nil
	end
	-- The rows, in the order the glass shows them.
	local function rowsOn(object)
		local sub = subOn(object)
		if sub == nil then return "" end
		return table.concat(sub.labels, " | ")
	end
	-- One row, by the computer it names: the run to it, or the cut of it.
	local function rowFor(object, host, cut)
		local sub = subOn(object)
		if sub == nil then return nil end
		local want = cut and ("ContextMenu_CeroSec_Unlink(" .. host .. ")")
			or ("ContextMenu_CeroSec_LinkTo(" .. host .. ",")
		for i = 1, #sub.labels do
			if cut and sub.labels[i] == want then return sub.options[i] end
			if not cut and string.sub(sub.labels[i], 1, #want) == want then
				return sub.options[i]
			end
		end
		return nil
	end
	-- Same two halves as the module block above, and the same reason the separator
	-- is spelled out instead of skipped over.
	local SEP = " <LINE> <RGB:1,0,0> "
	local function desc(option)
		local head = string.match(option.toolTip.description, "^(.-)" .. SEP)
		return head or option.toolTip.description
	end
	local function reason(option)
		return string.match(option.toolTip.description, SEP .. "(.*)$")
	end
	-- The click, dispatched the way the engine dispatches one: the target and then
	-- the tail addOption was given (ISContextMenu.lua:873-887).
	local function click(option)
		queued = {}
		option.callback(option.target, option.args[1], option.args[2],
			option.args[3])
	end

	-- A lamppost on the pavement with a relay in it, four computers about, and
	-- one of them out of reach.
	local post = fixture("IsoLightSwitch", square(10, 10, 0))
	local front = machine(22, 10, 0, "ksp-front-01")     -- 12 tiles, 12 wire
	local loft = machine(13, 10, 1, "ksp-loft-03")       -- 3 tiles, 7 wire
	local naked = machine(16, 14, 0, nil)                -- 8 tiles, mirror not here
	local county = machine(10, 60, 0, "ksp-far-09")      -- 50 tiles, never a line

	--
	-- 0. WHAT IS THERE AT ALL, which is the first thing this menu decides
	--
	-- A bare fixture is no submenu: a cable carries a MODULE's device to a machine,
	-- and a survivor with nothing screwed to his lamppost has not got to this
	-- feature yet -- the module menu above is already telling him so.
	objects = { county, front, loft, naked }
	eq("a bare fixture offers no cable at all", rowsOn(post), "")
	for i = 1, #menuOn(post).labels do
		check("and nothing of ours on the menu over it",
			menuOn(post).labels[i] ~= "ContextMenu_CeroSec_Link")
	end

	-- With the relay in it, the computers in range, nearest first -- and the one
	-- fifty tiles away is not a line, because it is the one thing about a cable a
	-- survivor cannot do anything about from where he is standing.
	post.modData.cerosec = { relay = true }
	eq("the fixture now offers every computer a cable would reach, nearest first",
		rowsOn(post),
		"ContextMenu_CeroSec_LinkTo(ksp-loft-03,3,7) | "
		.. "ContextMenu_CeroSec_LinkTo(" .. CeroSec.hostnameFor(16, 14) .. ",8,8) | "
		.. "ContextMenu_CeroSec_LinkTo(ksp-front-01,12,12)")
	check("and our entry is at the top of the menu",
		startsWith(menuOn(post).labels[1], "ContextMenu_CeroSec_Fixture"))
	local fixSub = fixtureSubOn(post)
	check("with Link to computer nested inside it",
		fixSub ~= nil and fixSub.labels[1] == "ContextMenu_CeroSec_Link")

	-- THE THIRD LEVEL IS HUNG OFF THE SECOND, not off the root. getNew's argument
	-- is what sets `parent` (ISContextMenu.lua:1244) and `parent` is the chain
	-- closeAll walks up after a click (:278-292): handed the root, the walk skips
	-- the fixture's own menu, which stays on the glass and re-shows the cable list
	-- every frame (:441-452). Asserted on the STATE of all three levels after the
	-- click, because the row's own callback fires either way.
	do
		local rootMenu = menuOn(post)
		local fixMenu, rowMenu = nil, nil
		for i = 1, #rootMenu.subs do
			if startsWith(rootMenu.subs[i].option.label,
					"ContextMenu_CeroSec_Fixture") then
				fixMenu = rootMenu.subs[i].menu
				for j = 1, #fixMenu.subs do
					if fixMenu.subs[j].option.label == "ContextMenu_CeroSec_Link" then
						rowMenu = fixMenu.subs[j].menu
					end
				end
			end
		end
		check("the cable list is a menu of its own", rowMenu ~= nil)
		eq("hung off the fixture's menu and not the root", rowMenu.parent, fixMenu)
		rowMenu:closeAll()
		check("a click in it puts the cable list away", rowMenu.visible == false)
		check("and the fixture's own menu with it", fixMenu.visible == false)
		check("and the root menu too", rootMenu.visible == false)
	end
	-- The floor is in the PRICE and not in the walk: the loft is three tiles away
	-- and costs seven, which is the one line on this menu where the two numbers
	-- differ and the reason both of them are shown.
	eq("a storey costs four tiles of cable and none of the walk",
		CeroSecModules.linkWire(10, 10, 0, 13, 10, 1)
		- CeroSecModules.linkTiles(10, 10, 13, 10), CeroSecModules.LINK_FLOOR_TILES)

	-- The far edge of the reel, both sides of it. Thirty is what a cable runs and
	-- thirty is a line.
	local edge = machine(40, 10, 0, "ksp-edge-30")
	objects = { edge }
	eq("a computer exactly a reel away is a line", rowsOn(post),
		"ContextMenu_CeroSec_LinkTo(ksp-edge-30,30,30)")
	objects = { machine(41, 10, 0, "ksp-past-31") }
	eq("one tile further is no line at all", rowsOn(post), "")

	-- Two computers the same price off keep their order between right-clicks: a
	-- walk of the registry in the other direction must not swap them, which is
	-- what a menu built off a hash table does to a survivor mid-click. The name
	-- breaks that tie and the square breaks it after the name, so the pair below
	-- is laid out with the two DISAGREEING -- zulu is the nearer square and alpha
	-- is the earlier name -- which is the only arrangement where "by name" is a
	-- thing the menu can be seen doing.
	local alpha = machine(22, 10, 0, "ksp-alpha-01")
	local zulu = machine(10, 22, 0, "ksp-zulu-09")
	objects = { zulu, alpha }
	local tied = rowsOn(post)
	eq("two computers twelve tiles off are named in their name's own order", tied,
		"ContextMenu_CeroSec_LinkTo(ksp-alpha-01,12,12) | "
		.. "ContextMenu_CeroSec_LinkTo(ksp-zulu-09,12,12)")
	objects = { alpha, zulu }
	eq("and the other way round the menu is the same menu", rowsOn(post), tied)
	-- And two that a survivor never renamed wear ONE name, which is a tie the name
	-- cannot break: the square breaks it, nearest corner first.
	objects = { machine(18, 10, 0, "ksp-dup-01"), machine(10, 18, 0, "ksp-dup-01") }
	eq("two computers with the same name are ordered by their square", rowsOn(post),
		"ContextMenu_CeroSec_LinkTo(ksp-dup-01,8,8) | "
		.. "ContextMenu_CeroSec_LinkTo(ksp-dup-01,8,8)")
	eq("which is the nearer corner first", subOn(post).options[1].args[3].x, 10)

	--
	-- 1. A LIVE LINE, and what it says the cable does
	--
	objects = { front, loft }
	local row = rowFor(post, "ksp-front-01")
	check("the run to the front desk is a line", row ~= nil)
	eq("it is not greyed", row.notAvailable, nil)
	eq("it says what the cable does, with the price and the computer in it",
		desc(row), "Tooltip_CeroSec_LinkDesc(12,ksp-front-01)")
	eq("and has nothing under it", reason(row), nil)

	-- Hovering this line highlights the COMPUTER it names, not the fixture --
	-- and turns back off exactly like the fixture's own parent does.
	check("nothing lit before the hover", front.iso.lit == nil)
	row.onHighlight(row, { player = 0 }, true, unpack(row.onHighlightParams))
	check("the computer lights up", front.iso.lit == true and front.iso.outline == true)
	row.onHighlight(row, { player = 0 }, false, unpack(row.onHighlightParams))
	check("and every exit turns it back off",
		front.iso.lit == false and front.iso.outline == false)
	check("the fixture itself is never touched by this row", post.lit == nil)

	-- A row for a machine whose chunk is away carries no highlight at all --
	-- nothing to call, and nothing that errors for not calling it.
	objects = { naked }
	local row2 = rowFor(post, CeroSec.hostnameFor(16, 14))
	check("an unloaded computer's row has no highlight hook", row2 ~= nil
		and row2.onHighlight == nil)
	objects = { front, loft }

	-- The click: the walk first, then the action, carrying the MACHINE's square
	-- and the price the line showed. Never the hostname -- that is a thing he
	-- types and a cable is a thing he laid.
	click(row)
	eq("the click queues one job", #queued, 1)
	eq("on this fixture", queued[1].object, post)
	eq("naming the computer's square and not its name", queued[1].mx .. ","
		.. queued[1].my .. "," .. queued[1].mz, "22,10,0")
	eq("running a cable", queued[1].link, true)
	eq("of what the line said it would cost", queued[1].wire, 12)
	eq("and it is the player's own job", queued[1].character, player)
	-- And a walk he cannot make queues nothing: the fixture is across a fence.
	walks = false
	click(row)
	eq("a fixture he cannot walk to queues no job", #queued, 0)
	walks = true

	--
	-- 2. THE RULES A CABLE DOES NOT ASK, which is the whole reason it exists
	--
	-- He is on the pavement, outdoors, at a lamppost: the module menu greys every
	-- line of that and this one greys none of it.
	eq("a cable to an outdoor fixture from the pavement is not greyed",
		rowFor(post, "ksp-front-01").notAvailable, nil)

	-- A DOOR is not a lamppost: wiring or unwiring it now asks the same
	-- envelope fitting or removing its own module would (Mathieu's rule,
	-- 2026-09-17). Standing outside a room refuses before the door's own
	-- state is even read.
	local shut = fixture("IsoDoor", square(10, 10, 0))
	shut.modData.cerosec = { contact = true }
	shut.open = false
	local shutRow = rowFor(shut, "ksp-front-01")
	eq("a shut door refuses a cable from outside a room", shutRow.notAvailable,
		true)
	eq("standing outside is refused first", reason(shutRow),
		"Tooltip_CeroSec_ModuleOutside(0)")

	-- Inside a room, the same shut door still refuses -- now for the reason
	-- fitting or removing its contact module would give, in the module menu's
	-- own words.
	stand.isInARoom = function() return true end
	shutRow = rowFor(shut, "ksp-front-01")
	eq("and a shut door refuses one from inside too", shutRow.notAvailable, true)
	eq("with the module menu's own word for a shut door", reason(shutRow),
		"Tooltip_CeroSec_ModuleClosed(0)")

	-- Opened, the same door takes a cable again. Left standing inside a room
	-- for the rest of this section, whose remaining doors care about the
	-- SKILL and OPEN state and not about where the survivor stands.
	shut.open = true
	eq("an open door takes the cable", rowFor(shut, "ksp-front-01").notAvailable,
		nil)

	--
	-- 3. WHAT IS GREYED, and the word it is greyed with
	--
	-- The reel, last and with the number in it: the one refusal on this menu a
	-- survivor meets every time he tries something ambitious.
	reels = 11
	row = rowFor(post, "ksp-front-01")
	eq("eleven reels for a twelve tile run is greyed", row.notAvailable, true)
	eq("with what to go and find", reason(row), "Tooltip_CeroSec_LinkWire(12)")
	eq("and still says what the cable does", desc(row),
		"Tooltip_CeroSec_LinkDesc(12,ksp-front-01)")
	eq("while the seven tile run is live", rowFor(post, "ksp-loft-03").notAvailable,
		nil)
	reels = 12
	eq("twelve reels is enough for twelve tiles",
		rowFor(post, "ksp-front-01").notAvailable, nil)
	reels = 40

	-- The tool and the trade, which are facts about him and not about the cable.
	tools = false
	eq("no screwdriver greys the line",
		reason(rowFor(post, "ksp-front-01")), "Tooltip_CeroSec_NeedScrewdriver(0)")
	tools = true
	-- The trade is the HIGHEST of the modules on the fixture: a door with an
	-- operator on it is Electricity 3 whatever else is screwed beside it.
	local worked = fixture("IsoDoor", square(10, 10, 0))
	worked.modData.cerosec = { contact = true, operator = true }
	worked.open = true
	level = 2
	row = rowFor(worked, "ksp-front-01")
	eq("a cable to an operator at Electricity 2 is greyed", row.notAvailable, true)
	eq("with the trade and the level it wants", reason(row),
		"Tooltip_CeroSec_NeedSkill(3)")
	eq("which is the level the hardware on it asks for",
		CeroSecModules.linkSkill(worked), 3)
	level = 5

	-- Somebody else's safehouse, which is the one refusal a cable asks that the
	-- fitting asks too -- and the worse of the two, because re-routing a door to
	-- a stranger's machine is worse than unscrewing the box off it.
	local house = { playerAllowed = function() return false end }
	_G.SafeHouse = { getSafeHouse = function() return house end }
	_G.SandboxVars = { CeroSec = { HardwareRequired = true, SafehouseModules = true } }
	row = rowFor(post, "ksp-front-01")
	eq("a stranger's safehouse greys the run", row.notAvailable, true)
	eq("with the word that says whose it is", reason(row),
		"Tooltip_CeroSec_LinkSafehouse(0)")
	eq("which is the word the server refuses on", reason(row),
		CeroSecLinkMenu.tooltipFor(
			CeroSecModules.linkRefusal(post, 22, 10, 0, player)) .. "(0)")
	_G.SandboxVars = { CeroSec = { HardwareRequired = true } }
	eq("with the option off it is the safehouse of nobody",
		rowFor(post, "ksp-front-01").notAvailable, nil)
	_G.SafeHouse = nil

	-- The fixture full: four computers is a terminal block with four pairs on it,
	-- and the fifth line says so with the cap in it.
	local full = fixture("IsoLightSwitch", square(10, 10, 0))
	full.modData.cerosec = { relay = true }
	for i = 1, CeroSecModules.LINKS_MAX do
		check("a cable to a computer nobody has been near is still a cable",
			CeroSecModules.linkOn(full, 10, 11 + i, 0, 2))
	end
	row = rowFor(full, "ksp-front-01")
	eq("a fixture with four cables greys a fifth", row.notAvailable, true)
	eq("with the cap in the line", reason(row),
		"Tooltip_CeroSec_LinkLinks(" .. CeroSecModules.LINKS_MAX .. ")")

	-- The MACHINE full, which is the one refusal the fixture's own modData cannot
	-- see: thirty-two squares on its list and no room for this one.
	local packed = machine(22, 10, 0, "ksp-packed-32")
	packed.state.links = {}
	for i = 1, CeroSecOS.LINKS_PER_MACHINE do
		packed.state.links[i] = { x = 100 + i, y = 200, z = 0 }
	end
	check("and thirty-two squares is a list the machine really holds",
		CeroSecOS.linksOk(packed.state.links))
	objects = { packed }
	row = rowFor(post, "ksp-packed-32")
	eq("a computer with a full list greys the run", row.notAvailable, true)
	eq("with its own cap in the line", reason(row),
		"Tooltip_CeroSec_LinkFull(" .. CeroSecOS.LINKS_PER_MACHINE .. ")")
	-- Unless the square on it is THIS fixture's: that is the cable the machine
	-- already carries, and running it again is what puts the fixture's own end
	-- back (the self-healing walk). A full list is never a reason to refuse it.
	packed.state.links[1] = { x = 10, y = 10, z = 0 }
	eq("a full list that already names this square is not full",
		rowFor(post, "ksp-packed-32").notAvailable, nil)

	--
	-- 4. THE CABLES ALREADY RUN, under the computers
	--
	objects = { front, loft }
	-- Written at five when the price is twelve, on purpose: what comes back is
	-- what was PAID and never the price worked out again, which is the whole of
	-- why the reel is written into the fixture's own list.
	check("a cable is written on the fixture", CeroSecModules.linkOn(post, 22, 10, 0, 5))
	eq("the computer it goes to is now on its own line, under the two runs",
		rowsOn(post),
		"ContextMenu_CeroSec_LinkTo(ksp-loft-03,3,7) | "
		.. "ContextMenu_CeroSec_LinkTo(ksp-front-01,12,12) | "
		.. "ContextMenu_CeroSec_Unlink(ksp-front-01)")
	row = rowFor(post, "ksp-front-01")
	eq("and the run to it is greyed", row.notAvailable, true)
	eq("because that computer is already on the list", reason(row),
		"Tooltip_CeroSec_LinkLinked(0)")

	local cut = rowFor(post, "ksp-front-01", true)
	check("the cut is a line of its own", cut ~= nil)
	eq("not greyed", cut.notAvailable, nil)
	eq("and it gives back the wire that was paid and not the price",
		desc(cut), "Tooltip_CeroSec_UnlinkDesc(5,ksp-front-01)")
	click(cut)
	eq("the click queues one job", #queued, 1)
	eq("cutting, not running", queued[1].link, false)
	eq("at the computer's square", queued[1].mx, 22)
	eq("for the wire on the fixture's own list", queued[1].wire, 5)
	-- And a cut asks nothing about the reel: he is being given wire, not spending
	-- it. Carrying none is the case, because that is the survivor who wants it.
	reels = 0
	eq("a survivor with no wire at all may still cut one",
		rowFor(post, "ksp-front-01", true).notAvailable, nil)
	reels = 40
	-- Whose house is asked of a cut too, for the same reason read the other way.
	_G.SafeHouse = { getSafeHouse = function() return house end }
	_G.SandboxVars = { CeroSec = { HardwareRequired = true, SafehouseModules = true } }
	cut = rowFor(post, "ksp-front-01", true)
	eq("a stranger may not cut your cable either", cut.notAvailable, true)
	eq("with the same word", reason(cut), "Tooltip_CeroSec_LinkSafehouse(0)")
	_G.SandboxVars = { CeroSec = { HardwareRequired = true } }
	_G.SafeHouse = nil

	-- A cable to a computer whose chunk is away is still here to be cut: the
	-- FIXTURE carries it, so the line is there. But no LIVE object stands on
	-- that square either, so this is the "loose cable" case: never a hostname
	-- CeroSec.hostnameFor made up for an empty tile, which a survivor would
	-- read as his machine's real name.
	objects = { loft }
	local sub = subOn(post)
	cut = nil
	for i = 1, #sub.labels do
		if sub.labels[i] == "ContextMenu_CeroSec_UnlinkLoose" then
			cut = sub.options[i]
		end
	end
	check("a cable to a computer that is not loaded is still a line", cut ~= nil)
	eq("named as a loose cable, not a fabricated hostname", cut.label,
		"ContextMenu_CeroSec_UnlinkLoose")
	eq("with the distance and the wire it cost", desc(cut),
		"Tooltip_CeroSec_UnlinkLooseDesc(12,5)")
	eq("and there is no run offered to it either", rowFor(post, "ksp-front-01"), nil)

	-- A fixture with a cable and no computer in reach still opens the submenu:
	-- the cut is the reason the menu exists at all for him.
	objects = {}
	eq("a fixture with nothing in reach still offers the cut", rowsOn(post),
		"ContextMenu_CeroSec_UnlinkLoose")

	--
	-- 5. A COMPUTER RENAMED KEEPS ITS CABLE, which is the naming rule itself
	--
	-- One line in /etc/hostname, the way root would: the menu follows it, both
	-- lines of it, and what is written on the fixture has not moved -- because
	-- what is written there is where the machine STANDS.
	objects = { front }
	local renamed = CeroSecOS.setData(front.state, CeroSecOS.rootSession(),
		CeroSecOS.HOSTNAME_PATH, "ksp-renamed\n")
	check("root renames the machine in one line", renamed ~= nil)
	eq("both lines follow the new name", rowsOn(post),
		"ContextMenu_CeroSec_LinkTo(ksp-renamed,12,12) | "
		.. "ContextMenu_CeroSec_Unlink(ksp-renamed)")
	local links = CeroSecModules.linksOn(post)
	eq("the fixture still carries one cable", #links, 1)
	eq("to the same square", links[1].x .. "," .. links[1].y .. "," .. links[1].z,
		"22,10,0")
	eq("for the same wire", links[1].wire, 5)
	eq("and the name on the line is the file's, read as the machine reads it",
		CeroSecOS.hostname(front.state), "ksp-renamed")

	--
	-- 6. THE GATE the whole menu wears
	--
	-- With the hardware option off every machine reaches every door in its
	-- building already and nothing is ever fitted, so a cable is a gesture with no
	-- effect and there is no line to click.
	_G.SandboxVars = { CeroSec = { HardwareRequired = false } }
	eq("with the hardware option off there is no cable menu", rowsOn(post), "")
	_G.SandboxVars = { CeroSec = { HardwareRequired = true } }
	check("and with it on there is", rowsOn(post) ~= "")

	--
	-- 7. THE KEY IS BUILT FROM THE WORD, and every key is a string that exists
	--
	eq("the key is derived from the refusal", CeroSecLinkMenu.tooltipFor("safehouse"),
		"Tooltip_CeroSec_LinkSafehouse")
	eq("and from a one-letter one", CeroSecLinkMenu.tooltipFor("x"),
		"Tooltip_CeroSec_LinkX")
	-- The numbers in the sentences are the CAPS and not words in a translation, so
	-- the day one of them moves the line moves with it.
	eq("the far line carries the range", CeroSecLinkMenu.numberFor("far"),
		CeroSecModules.LINK_RANGE)
	eq("the full line carries the fixture's cap", CeroSecLinkMenu.numberFor("links"),
		CeroSecModules.LINKS_MAX)
	eq("and a word with no number in its line asks for none",
		CeroSecLinkMenu.numberFor("safehouse"), 0)

	_G.getText = realGetText

	-- Every key this menu can print, in both languages -- and with as many
	-- placeholders as the code hands it arguments, because a line that is missing
	-- its %1 is a survivor told he needs electric wire without being told how
	-- much, and one that has a %1 nothing fills prints the digit 0.
	local NUMBERED = {
		{ "ContextMenu.json", "ContextMenu_CeroSec_Link", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_Fixture", 1 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_GenreDoor", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_GenreWindow", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_GenreLightSwitch", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_GenreCurtain", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_GenreStove", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_GenreMicrowave", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_GenreWasher", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_GenreGenerator", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_GenreSet", 0 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_LinkTo", 3 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_Unlink", 1 },
		{ "ContextMenu.json", "ContextMenu_CeroSec_UnlinkLoose", 0 },
		{ "Tooltip.json", "Tooltip_CeroSec_LinkDesc", 2 },
		{ "Tooltip.json", "Tooltip_CeroSec_UnlinkDesc", 2 },
		{ "Tooltip.json", "Tooltip_CeroSec_UnlinkLooseDesc", 2 },
		{ "Tooltip.json", "Tooltip_CeroSec_LinkFixture", 0 },
		{ "Tooltip.json", "Tooltip_CeroSec_LinkSafehouse", 0 },
		{ "Tooltip.json", "Tooltip_CeroSec_LinkLinked", 0 },
		{ "Tooltip.json", "Tooltip_CeroSec_LinkLinks", 1 },
		{ "Tooltip.json", "Tooltip_CeroSec_LinkFar", 1 },
		{ "Tooltip.json", "Tooltip_CeroSec_LinkFull", 1 },
		{ "Tooltip.json", "Tooltip_CeroSec_LinkWire", 1 },
	}
	for _, lang in ipairs({ "EN", "FR" }) do
		for _, entry in ipairs(NUMBERED) do
			local handle = assert(io.open(
				"42/media/lua/shared/Translate/" .. lang .. "/" .. entry[1], "r"))
			local strings = handle:read("*a")
			handle:close()
			local line = string.match(strings, '"' .. entry[2] .. '"%s*:%s*"([^"]*)"')
			check(lang .. "/" .. entry[1] .. " defines " .. entry[2], line ~= nil)
			local marks = 0
			for _ in string.gmatch(line, "%%%d") do marks = marks + 1 end
			eq(lang .. " " .. entry[2] .. " takes its arguments", marks, entry[3])
		end
	end

	_G.SandboxVars = nil
	_G.SafeHouse = nil
end

print("manual_ui_test: " .. count .. " checks passed")
