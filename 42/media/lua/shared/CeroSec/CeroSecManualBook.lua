--
-- The manual, laid out.
--
-- Pure Lua on purpose, the way CeroSecDefs and the OS core are: it makes no
-- game call at all. The one thing it needs from the game -- how wide a string
-- is going to be drawn -- is handed in as a function, so the same code that
-- lays the book out on a player's screen lays it out on a bench against a fake
-- font of a known width (tests/manual_ui_test.lua). Nothing here knows what a
-- window is.
--
-- What it takes is the text, written elsewhere:
--
--   CeroSecManual = {
--     title = "...", edition = "...",
--     chapters = { { title = "...", pages = { "text\n\nmore text", ... } } },
--   }
--
-- What it hands back is a flat list of PAGES, in the order they are turned,
-- each one a list of drawable lines. The book is read two pages at a time --
-- a left leaf and a right leaf -- so page 1 and 2 share a sheet, 3 and 4 the
-- next, and the whole of the two-page look is that pairing and nothing more.
--
-- An authored page is a page: the writer decides where a page ends, not the
-- layout. What the layout decides is where a LINE ends, and the one case it
-- decides a page ending is the overflow case -- an authored page whose text
-- does not fit the leaf spills onto a continuation page rather than being cut
-- off, because a manual that silently drops its last paragraph is worse than
-- a manual with an extra leaf in it.
--

CeroSec = CeroSec or {}
CeroSecManualBook = {}

-- An example line is one that starts with two spaces. It is code: it is drawn
-- in the monospaced font and it is never wrapped and never trimmed, because a
-- shell line broken across two rows is a shell line the player will mistype.
CeroSecManualBook.EXAMPLE_PREFIX = "  "

function CeroSecManualBook.isExample(line)
	return string.sub(line, 1, 2) == CeroSecManualBook.EXAMPLE_PREFIX
end

--
-- Wrapping
--

-- Break one word that is wider than the leaf all on its own. Nothing in the
-- manual should ever be such a word, but a leaf narrowed by the player's font
-- size makes one out of an ordinary word, and a line wider than the page is a
-- line drawn over the margin and off the paper. Characters, since there is
-- nothing else left to break on.
local function breakWord(word, width, measure)
	local parts = {}
	local current = ""
	for i = 1, #word do
		local char = string.sub(word, i, i)
		local grown = current .. char
		if current ~= "" and measure(grown) > width then
			parts[#parts + 1] = current
			current = char
		else
			current = grown
		end
	end
	if current ~= "" then parts[#parts + 1] = current end
	-- A width so small that not even one character fits: give up on breaking
	-- rather than hand back an empty list and lose the word entirely.
	if #parts == 0 then parts[1] = word end
	return parts
end

-- Greedy word wrap of one paragraph. `measure(text)` answers how wide the text
-- will be drawn, in whatever unit the caller works in; `width` is in that same
-- unit. Always at least one line, so an empty paragraph is a blank line and
-- not nothing at all.
function CeroSecManualBook.wrap(text, width, measure)
	local lines = {}
	local current = nil
	for word in string.gmatch(text, "%S+") do
		local candidate = current and (current .. " " .. word) or word
		if current and measure(candidate) > width then
			lines[#lines + 1] = current
			current = nil
			candidate = word
		end
		if current == nil and measure(word) > width then
			local parts = breakWord(word, width, measure)
			for i = 1, #parts - 1 do lines[#lines + 1] = parts[i] end
			current = parts[#parts]
		else
			current = candidate
		end
	end
	if current then lines[#lines + 1] = current end
	if #lines == 0 then lines[1] = "" end
	return lines
end

--
-- Laying a page out
--

-- One authored page becomes a list of drawable lines: { text = ..., code = }.
-- `\n` is the paragraph break the contract names, and a run of them is kept as
-- blank lines so the writer's spacing survives. Example lines come through
-- exactly as they were typed.
function CeroSecManualBook.layout(text, opts)
	local out = {}
	-- gmatch on "([^\n]*)\n?" would loop forever on the empty tail in 5.1, so
	-- the split is walked by hand.
	local start = 1
	while true do
		local stop = string.find(text, "\n", start, true)
		local piece = stop and string.sub(text, start, stop - 1) or string.sub(text, start)
		if CeroSecManualBook.isExample(piece) then
			out[#out + 1] = { text = piece, code = true }
		elseif string.match(piece, "%S") then
			local lines = CeroSecManualBook.wrap(piece, opts.width, opts.measure)
			for i = 1, #lines do out[#out + 1] = { text = lines[i], code = false } end
		else
			out[#out + 1] = { text = "", code = false }
		end
		if not stop then break end
		start = stop + 1
	end
	return out
end

-- Cut a list of drawable lines into leaves of at most `rows` lines. A blank
-- line at the top of a continuation leaf is dropped: it was a paragraph break
-- and there is nothing above it any more.
local function paginate(lines, rows)
	local pages = {}
	local i = 1
	while i <= #lines do
		local page = {}
		while i <= #lines and #page < rows do
			if #page > 0 or lines[i].text ~= "" then page[#page + 1] = lines[i] end
			i = i + 1
		end
		if #page > 0 then pages[#pages + 1] = page end
	end
	if #pages == 0 then pages[1] = {} end
	return pages
end

--
-- The book
--

-- Lay the whole manual out. `opts` is { width, rows, measure }: the width of a
-- leaf and how many lines fit on one, in the caller's units, and the measuring
-- function. Hands back
--
--   { title, edition, pages = { page, ... }, chapters = { { title, page } } }
--
-- where a page is { kind, chapter, lines, entries }: `kind` is "title", "toc"
-- or "text"; `chapter` is the running head the leaf carries; `entries` is the
-- table of contents' clickable rows, present only on a "toc" page. The index
-- of a page in `pages` is its printed page number.
function CeroSecManualBook.open(manual, opts)
	local book = {
		title = (manual and manual.title) or "Manual",
		edition = (manual and manual.edition) or "",
		pages = {},
		chapters = {},
	}
	local pages = book.pages

	-- The title leaf. Drawn from the two header fields, not laid out: it is
	-- centred by the window, and centring is a drawing decision.
	pages[1] = { kind = "title", chapter = nil, lines = {} }

	local chapters = (manual and manual.chapters) or {}

	-- The contents leaf, or leaves. Its rows have to name the page each chapter
	-- starts on, and that is not known until the chapters have been laid out --
	-- so the chapters are laid out first, against a starting number that
	-- assumes a contents of the right length, and the length is settled by
	-- counting rows against `rows` before anything else is placed.
	local tocRows = #chapters
	local tocPages = math.max(1, math.ceil(tocRows / math.max(1, opts.rows)))
	if tocRows == 0 then tocPages = 1 end

	local first = 1 + tocPages + 1

	-- Each chapter opens a new leaf: a chapter that began halfway down the
	-- previous one is a chapter the reader cannot find.
	local number = first
	local body = {}
	for c = 1, #chapters do
		local chapter = chapters[c]
		book.chapters[c] = { title = chapter.title or "", page = number }
		local authored = chapter.pages or {}
		if #authored == 0 then authored = { "" } end
		for p = 1, #authored do
			local laid = CeroSecManualBook.layout(authored[p], opts)
			local leaves = paginate(laid, opts.rows)
			for l = 1, #leaves do
				body[#body + 1] = {
					kind = "text",
					chapter = chapter.title or "",
					chapterIndex = c,
					lines = leaves[l],
				}
				number = number + 1
			end
		end
	end

	-- Now the contents, with the numbers the chapters really landed on.
	local row = 0
	for t = 1, tocPages do
		local entries = {}
		for _ = 1, opts.rows do
			row = row + 1
			if row > #book.chapters then break end
			entries[#entries + 1] = {
				index = row,
				title = book.chapters[row].title,
				page = book.chapters[row].page,
			}
		end
		pages[#pages + 1] = { kind = "toc", chapter = nil, lines = {}, entries = entries }
	end

	for i = 1, #body do pages[#pages + 1] = body[i] end

	-- A book is read two leaves at a time, so it always has an even number of
	-- them: the back of the last leaf is blank paper, not half a sheet.
	if #pages % 2 == 1 then
		pages[#pages + 1] = { kind = "text", chapter = nil, lines = {} }
	end

	return book
end

--
-- Turning the leaves
--

-- The sheet a page number is printed on, counting from 1. Pages 1 and 2 are on
-- sheet 1, 3 and 4 on sheet 2.
function CeroSecManualBook.sheetOf(page)
	return math.floor((page - 1) / 2) + 1
end

-- The left page of a sheet. The right one is that plus one, and it may be past
-- the end of a book with an odd number of leaves -- which open() makes sure
-- never happens.
function CeroSecManualBook.leftOf(sheet)
	return (sheet - 1) * 2 + 1
end

function CeroSecManualBook.sheetCount(book)
	return math.max(1, math.ceil(#book.pages / 2))
end

-- Where a page number that came off modData should actually land: on a sheet
-- of this book, and on the left leaf of it. A saved number from a longer book
-- -- the manual was rewritten between two saves -- comes back to the front
-- rather than to an empty leaf, and anything that is not a number at all is
-- the front too.
function CeroSecManualBook.clampPage(book, page)
	if type(page) ~= "number" then return 1 end
	page = math.floor(page)
	if page < 1 or page > #book.pages then return 1 end
	return CeroSecManualBook.leftOf(CeroSecManualBook.sheetOf(page))
end
