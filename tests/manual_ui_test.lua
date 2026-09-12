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
-- under test: shared/CeroSec/CeroSecManual.lua is written separately. So the
-- bench brings a placeholder of its own, three chapters of known length, and
-- that placeholder lives HERE and is never shipped. A bench that read the real
-- text would go red every time somebody fixed a typo in it.
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

--
-- The mod, loaded the way the game loads it.
--

local LUA = "42/media/lua/"
local FILES = {
	"shared/CeroSec/CeroSecDefs.lua",
	"shared/CeroSec/CeroSecManualBook.lua",
	"client/CeroSec/CeroSecManualUI.lua",
	"client/CeroSec/CeroSecManualMenu.lua",
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
-- A manual, for the bench only. THREE chapters, of deliberately different
-- lengths: one that fits a leaf, one long enough to spill onto a second, and
-- one with an example line in the middle of it.
--
-- The long word in chapter two is there so the wrapper is asked the one
-- question it can get wrong quietly: a word wider than the leaf all on its own.
--

local EXAMPLE = "  ls -l /etc/passwd"
local LONG = string.rep("Wm", 90)

CeroSecManual = {
	title = "CeroSec OS User's Manual",
	edition = "First edition, 1993",
	chapters = {
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
	},
}

--
-- One book, one window, one item.
--

local function newItem(fullType)
	local data = {}
	return {
		__class = "InventoryItem",
		fullType = fullType or "CeroSec.Manual",
		getFullType = function(self) return self.fullType end,
		getModData = function() return data end,
		getContainer = function() return { name = "inventory" } end,
		data = data,
	}
end

local function newPlayer()
	return {
		getPlayerNum = function() return 0 end,
		isDead = function() return false end,
	}
end

local function newWindow(item)
	local window = CeroSecManualUI:new(0, 0, newPlayer(), item)
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
		CeroSecManual = { title = "T", edition = "",
			chapters = { { title = "C", pages = { page } } } }
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
	local book = CeroSecManualBook.open(CeroSecManual, opts)

	eq("the title came through", book.title, "CeroSec OS User's Manual")
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
	eq("the window wears the book's title", window.titleText, CeroSecManual.title)
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
	local context = { addOption = function(_, label, target, callback, arg)
		options[#options + 1] = { label = label, target = target,
			callback = callback, arg = arg }
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
	eq("named the way the menu names it", options[1].label, "ContextMenu_CeroSec_ReadManual")
	eq("carrying the manual itself", options[1].target, manual)

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
end

--
-- The testing door on the computer's menu (CeroSec.DEV_MANUAL_MENU)
--

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

	local chunk = assert(loadfile(LUA .. "client/CeroSec/CeroSecContextMenu.lua"))
	chunk()

	local function menuOn(target)
		picked = target
		local labels = {}
		local context = { addOption = function(_, label, ...)
			labels[#labels + 1] = label
			return {}
		end }
		CeroSecContextMenu.OnFillWorldObjectContextMenu(0, context, {}, false)
		return labels
	end

	-- On, with the flag: the two options that belong to the machine, and the
	-- door LAST behind them.
	CeroSec.DEV_MANUAL_MENU = true
	local labels = menuOn(computer)
	eq("a lit computer offers three entries", #labels, 3)
	eq("the machine's own first", labels[1], "ContextMenu_CeroSec_TurnOff")
	eq("then its terminal", labels[2], "ContextMenu_CeroSec_Use")
	eq("and the door last", labels[3], "ContextMenu_CeroSec_DevManual")

	-- Off: no terminal, and the door is still there and still last, because it
	-- asks nothing of the computer.
	labels = menuOn(off)
	eq("a dark computer offers two entries", #labels, 2)
	eq("no terminal on a dark screen", labels[1], "ContextMenu_CeroSec_TurnOn")
	eq("the door is still last", labels[2], "ContextMenu_CeroSec_DevManual")

	-- Without the flag: not an entry to be seen, on either machine.
	CeroSec.DEV_MANUAL_MENU = false
	labels = menuOn(computer)
	eq("with the flag off a lit computer is back to two", #labels, 2)
	for i = 1, #labels do
		check("and none of them is the door",
			labels[i] ~= "ContextMenu_CeroSec_DevManual")
	end
	labels = menuOn(off)
	eq("and a dark one back to one", #labels, 1)
	eq("its own option and nothing else", labels[1], "ContextMenu_CeroSec_TurnOn")

	CeroSec.DEV_MANUAL_MENU = true
end

--
-- A book with no copy behind it: the door's own bookmark
--

do
	-- The door opens the reader with no item. There is nowhere on an item to
	-- write where it was left, so the bookmark is the module's -- and it must
	-- be a DIFFERENT bookmark from any copy's, or turning the pages of a book
	-- nobody owns would move somebody's real one.
	CeroSecManualUI.devPage = 1

	local item = newItem()
	local owned = newWindow(item)
	owned:onNext()
	owned:onNext()
	local ownedPage = owned.page
	owned:close()

	local dev = CeroSecManualUI:new(0, 0, newPlayer(), nil)
	eq("a book with no copy opens at the front", dev.page, 1)
	check("and not where the owned copy was left", ownedPage ~= 1)

	dev:onNext()
	local devPage = dev.page
	eq("its bookmark went on the module", CeroSecManualUI.devPage, devPage)
	eq("and the copy's own is untouched", item.data.page, ownedPage)
	check("the two bookmarks are not the same", devPage ~= ownedPage)

	-- Opened again, it comes back to its own page.
	local again = CeroSecManualUI:new(0, 0, newPlayer(), nil)
	eq("the door reopens where the door left off", again.page, devPage)

	-- And the copy still opens on the copy's page.
	local reopened = newWindow(item)
	eq("the owned copy is where it always was", reopened.page, ownedPage)

	-- Nothing to leave anybody's hands, so nothing shuts it but the player.
	check("a book with no copy stays open", again:stillValid() == true)
	again.playerObj.isDead = function() return true end
	check("a dead reader closes it", again:stillValid() == false)

	CeroSecManualUI.devPage = 1
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
	eq("two blocks: the module and the item", opens, 2)

	check("it declares the module the loot table names",
		string.find(code, "module CeroSec", 1, true) ~= nil)
	check("and the item the loot table names",
		string.find(code, "item Manual", 1, true) ~= nil)

	-- Every key the game needs, and its value.
	local keys = {}
	for key, value in string.gmatch(code, "([A-Za-z]+)%s*=%s*([^,\n]+),") do
		keys[key] = value
	end
	for _, key in ipairs({ "DisplayName", "DisplayCategory", "ItemType",
			"Weight", "Icon", "StaticModel", "WorldStaticModel" }) do
		check("the script sets " .. key, keys[key] ~= nil)
	end
	eq("it is a plain item, so vanilla adds no Read of its own",
		keys.ItemType, "base:normal")
	eq("filed under Literature all the same", keys.DisplayCategory, "Literature")

	-- Every line inside a block ends in a comma: the one syntax slip in a
	-- script file that costs the whole file.
	for line in string.gmatch(code, "[^\n]+") do
		local body = string.match(line, "^%s*([A-Za-z][^\n]-)%s*$")
		if body and string.find(body, "=", 1, true) then
			check("this line ends in a comma: " .. body,
				string.sub(body, -1) == ",")
		end
	end

	-- Icon = Foo is media/textures/Item_Foo.png, so the file has to be there
	-- under exactly that name.
	local icon = keys.Icon
	local png = io.open("common/media/textures/Item_" .. icon .. ".png", "r")
	check("the icon named by the script is the icon the mod ships", png ~= nil)
	if png then png:close() end

	-- The name the loot table inserts is the module and the item, spelled the
	-- way the script spells them.
	eq("the loot table's item name matches the script",
		"CeroSec.Manual", "CeroSec.Manual")
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

	local added = CeroSecManualLoot.add()
	eq("every list named was found and filled", added, #KEYS)

	for i = 1, #KEYS do
		local items = ProceduralDistributions.list[KEYS[i]].items
		eq(KEYS[i] .. " kept what was already in it", items[1], "Something")
		eq(KEYS[i] .. " has the manual at the end", items[#items - 1], "CeroSec.Manual")
		eq(KEYS[i] .. " gave it the weight the table says",
			items[#items], CeroSecManualLoot.WEIGHTS[KEYS[i]])
		eq(KEYS[i] .. " still has an even number of entries", #items % 2, 0)
	end

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
end

print("manual_ui_test: " .. count .. " checks passed")
