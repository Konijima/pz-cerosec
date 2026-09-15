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
		getScreenHeight = function() return 1080 end }
end
_G.getText = function(key) return key end
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
function ContextMenu:addOption(label, target, callback, ...)
	local n = select("#", ...)
	local args = { ... }
	local option = { label = label, target = target, callback = callback,
		args = args, argCount = n, arg = args[1], arg2 = args[2] }
	self.labels[#self.labels + 1] = label
	self.options[#self.options + 1] = option
	return option
end
function ContextMenu:addSubMenu(option, menu)
	self.subs[#self.subs + 1] = { option = option, menu = menu }
	menu.hungOff = option
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
	local options = {}
	local context = { addOption = function(_, label, target, callback, arg, arg2)
		options[#options + 1] = { label = label, target = target,
			callback = callback, arg = arg, arg2 = arg2 }
		return {}
	end }
	local player = newPlayer()
	_G.getSpecificPlayer = function() return player end

	local manual = newItem()
	local other = newItem("Base.Book")

	CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, context, { other })
	eq("no option for a book that is not ours", #options, 0)

	CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, context, { other, manual })
	eq("one option when the manual is in the selection", #options, 1)
	eq("named the way the menu names it", options[1].label, "ContextMenu_CeroSec_ReadUser")
	eq("carrying the manual itself", options[1].target, manual)
	eq("and opening volume one", options[1].arg2, "user")

	-- The single-volume book that shipped BEFORE the set: ONE entry and not two, and
	-- it is volume one's own label -- a second "Read the manual" beside "Read the
	-- User's Guide" would be the menu offering the same book twice under two names,
	-- which is the duplicate the set replaced.
	options = {}
	local legacy = newItem("CeroSec.Manual")
	CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, context, { legacy })
	eq("the retired book is on the menu", #options, 1)
	eq("under volume one's own label", options[1].label, "ContextMenu_CeroSec_ReadUser")
	eq("carrying that very copy", options[1].target, legacy)
	eq("and opening volume one", options[1].arg2, "user")

	-- And the two together are two entries, in the order the set is printed in: the
	-- Guide first, the book it replaced under it.
	options = {}
	CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, context, { legacy, manual })
	eq("both books, both entries", #options, 2)
	eq("the Guide first", options[1].target, manual)
	eq("and the retired book under it", options[2].target, legacy)

	-- A stack of identical items arrives as one table with an items array
	-- inside it, not as an InventoryItem. That is the shape that would slip
	-- through a naive loop, so it is the shape the test insists on.
	options = {}
	local stack = { items = { manual, newItem() } }
	CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, context, { stack })
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
		options = {}
		copies[v] = newItem(VOLUMES[v].item)
		CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, context, { other, copies[v] })
		eq(VOLUMES[v].item .. " is one option", #options, 1)
		eq("named after its own volume", options[1].label, VOLUMES[v].label)
		eq("carrying that copy", options[1].target, copies[v])
		eq("and opening that volume", options[1].arg2, VOLUMES[v].volume)
	end

	-- All three in one selection: three options, in the order the set is
	-- printed in and not in whatever order a hash walked them.
	options = {}
	CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, context,
		{ copies[3], copies[1], copies[2] })
	eq("the whole set is three options", #options, 3)
	for v = 1, #VOLUMES do
		eq("option " .. v .. " is volume " .. v, options[v].arg2, VOLUMES[v].volume)
		eq("option " .. v .. " carries volume " .. v .. "'s own copy",
			options[v].target, copies[v])
	end

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
	local options = {}
	local context = { addOption = function(_, label, target, callback, arg, arg2)
		options[#options + 1] = { label = label, target = target,
			callback = callback, arg = arg, arg2 = arg2 }
		return {}
	end }
	local reader = newReader(300.5, 700.5)
	_G.getSpecificPlayer = function() return reader end

	local book = newPhonebook()
	CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, context, { book })
	eq("a phone book is one option", #options, 1)
	eq("named the way the menu names it", options[1].label,
		"ContextMenu_CeroSec_LookUpNumbers")
	eq("carrying the copy itself", options[1].target, book)
	eq("and it is the look-up and not the reader", options[1].callback,
		CeroSecManualMenu.onLookUp)
	eq("with the survivor behind it", options[1].arg, reader)

	-- And nothing else gets it. A manual is not a phone book and a phone book is
	-- not one of the volumes: the entry is on Base.Phonebook and on nothing else.
	options = {}
	CeroSecManualMenu.OnFillInventoryObjectContextMenu(0, context,
		{ newItem("Base.Book"), newItem("CeroSec.ManualUser") })
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
	local function fullMenuOn(target)
		picked = target
		local context = ContextMenu.new()
		CeroSecContextMenu.OnFillWorldObjectContextMenu(0, context, {}, false)
		return context
	end

	local function menuOn(target)
		return fullMenuOn(target).labels
	end

	-- On, with both flags: the two options that belong to the machine, and the
	-- dev submenu LAST behind them.
	CeroSec.DEV_MANUAL_MENU = true
	CeroSec.DEV_DEBUG_MENU = true
	local labels = menuOn(computer)
	eq("a lit computer offers three entries", #labels, 3)
	eq("the machine's own first", labels[1], "ContextMenu_CeroSec_TurnOff")
	eq("then its terminal", labels[2], "ContextMenu_CeroSec_Use")
	eq("and the dev submenu last", labels[3], "ContextMenu_CeroSec_Dev")

	-- Off: no terminal, and the submenu is still there and still last, because
	-- neither door asks anything of the computer.
	labels = menuOn(off)
	eq("a dark computer offers two entries", #labels, 2)
	eq("no terminal on a dark screen", labels[1], "ContextMenu_CeroSec_TurnOn")
	eq("the submenu is still last", labels[2], "ContextMenu_CeroSec_Dev")

	-- Without BOTH flags: not an entry to be seen, on either machine. Both,
	-- because either one on is a submenu with something in it.
	CeroSec.DEV_MANUAL_MENU = false
	CeroSec.DEV_DEBUG_MENU = false
	labels = menuOn(computer)
	eq("with both flags off a lit computer is back to two", #labels, 2)
	for i = 1, #labels do
		check("and none of them is the submenu",
			labels[i] ~= "ContextMenu_CeroSec_Dev")
	end
	labels = menuOn(off)
	eq("and a dark one back to one", #labels, 1)
	eq("its own option and nothing else", labels[1], "ContextMenu_CeroSec_TurnOn")

	-- One flag on is a submenu with only that flag's doors in it. The manual's
	-- first: one volume on the bench's shelf, so one entry and nothing else.
	CeroSec.DEV_MANUAL_MENU = true
	CeroSec.DEV_DEBUG_MENU = false
	local menu = fullMenuOn(computer)
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
	eq("and it hangs off the dev entry",
		menu.subs[1].option, menu.options[3])
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
		menu.options[3].callback, nil)


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
	eq("the full drive greys the insert", insert.notAvailable, true)
	eq("with the one sentence that says what to do", insert.toolTip.description,
		"Tooltip_CeroSec_DriveFull")
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
	eq("with the walk's own reason", insert.toolTip.description, "Tooltip_CeroSec_NoAccess")
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
	eq("with the four arguments the action takes", parent.argCount, 4)

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
		"Tooltip_CeroSec_DriveFull")
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
		"Tooltip_CeroSec_NoAccess")
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
		eq("the door is still one entry on the machine's own menu", #menu.labels, 3)
		eq("and still last", menu.labels[3], "ContextMenu_CeroSec_Dev")
		eq("still exactly one submenu", #menu.subs, 1)
		eq("hung off the door", menu.subs[1].option, menu.options[3])

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
	-- The module, the three books, the four disks, the four hardware modules, the book
	-- that teaches them, the RETIRED single book -- which is declared and is not
	-- loot, because dropping an item block deletes every copy of it in every save --
	-- and, since the world-content work, the sticky note a password is written on.
	eq("fifteen blocks: the module, the three books, the retired one, the four "
		.. "disks, the four hardware modules, the Field Wiring Guide and the note",
		opens, 15)

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
	}
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
	eq("every list named was found and filled by every module",
		added, #KEYS * #CeroSecModules.LIST)

	for i = 1, #KEYS do
		local key = KEYS[i]
		local items = ProceduralDistributions.list[key].items
		eq(key .. " kept what was already in it", items[1], "Something")
		eq(key .. " still has an even number of entries", #items % 2, 0)
		eq(key .. " grew by one name and one weight per module",
			#items, 2 + 2 * #CeroSecModules.LIST)
		for m = 1, #CeroSecModules.LIST do
			local module = CeroSecModules.LIST[m]
			local at = 2 + (m - 1) * 2 + 1
			eq(key .. " has " .. module.item .. " in place " .. m, items[at], module.item)
			eq(key .. " gave it its own share of the box", items[at + 1],
				CeroSecModuleLoot.WEIGHTS[key] * CeroSecModuleLoot.SHARES[module.id])
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
	end

	-- Four recipes, no more: a fifth would be a module nothing else knows about.
	local made = 0
	for _ in pairs(recipes) do made = made + 1 end
	eq("one recipe per module and not one more", made, #CeroSecModules.LIST)

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
	eq("the guide teaches one recipe per module and not one more",
		taughtCount, #CeroSecModules.LIST)
	table.sort(names)
	for n = 1, #names do
		check("the guide names the recipe " .. names[n], taught[names[n]] == true)
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

	local function fill(items)
		local context = ContextMenu.new()
		CeroSecFloppyMenu.OnFillInventoryObjectContextMenu(0, context, items)
		return context
	end

	--
	-- Something to write with
	--
	local disk = newFloppy()
	tags = {}
	eq("no pen, no entry at all", #fill({ disk }).labels, 0)
	eq("and canWrite says so", CeroSecFloppyMenu.canWrite(player), false)

	-- Each of the six tags on its own is enough. One at a time, because a test that
	-- put all six on the survivor would pass with five of them never consulted.
	local SIX = { "t.WRITE", "t.BLUE_PEN", "t.PEN", "t.PENCIL", "t.RED_PEN",
		"t.GREEN_PEN" }
	eq("six tags, the six vanilla asks about", #CeroSecFloppyMenu.writeTags(), 6)
	for i = 1, #SIX do
		tags = { [SIX[i]] = true }
		eq(SIX[i] .. " alone is enough to write", CeroSecFloppyMenu.canWrite(player), true)
		eq("and it puts the entry on the menu", #fill({ disk }).labels, 1)
	end
	-- A tag that is not one of the six is not a pen.
	tags = { ["t.SCREWDRIVER"] = true }
	eq("a tag that is not one of the six writes nothing",
		CeroSecFloppyMenu.canWrite(player), false)

	tags = { ["t.PEN"] = true }

	--
	-- The entries
	--
	eq("nothing on a menu with no disk in the selection", #fill({}).labels, 0)
	local other = newFloppy("Base.Hammer")
	eq("and nothing for an item that is not a disk", #fill({ other }).labels, 0)

	local menu = fill({ other, disk })
	eq("an unlabelled disk offers one entry", #menu.labels, 1)
	eq("named for writing on it", menu.labels[1], "ContextMenu_CeroSec_LabelFloppy")
	eq("carrying the disk", menu.options[1].target, disk)
	eq("and the box is what it opens", menu.options[1].callback,
		CeroSecFloppyMenu.onLabel)
	eq("with the player behind it", menu.options[1].arg, player)

	-- A stack of identical disks arrives as one table with an items array inside it,
	-- which is the shape a naive loop walks straight past.
	local stack = { items = { disk, newFloppy() } }
	local stacked = fill({ stack })
	eq("a stack of disks is still one entry", #stacked.labels, 1)
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
	eq("a labelled disk offers two entries", #menu.labels, 2)
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
	eq("and the menu is back to one entry", #fill({ disk }).labels, 1)

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

print("manual_ui_test: " .. count .. " checks passed")
