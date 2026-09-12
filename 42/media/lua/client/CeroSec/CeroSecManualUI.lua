require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecManualBook"

--
-- The manual, open on the table.
--
-- Two leaves side by side on cream paper, a running head naming the chapter,
-- a page number at the foot of each leaf, and a contents page whose rows are
-- clicked to jump. Left and Right turn the sheet, Escape closes it, and where
-- the book was left is written on the item, so picking it up again opens it
-- where it was put down.
--
-- The player reads this, not the character: there is no timed action behind it,
-- no reading skill, no animation and no game time spent. The window is a piece
-- of paper on the screen and the survivor goes on doing whatever he was doing.
--
-- The TEXT is not here and is not this file's business: it is CeroSecManual.volumes,
-- written in shared/CeroSec/, and the shape of it is the contract
-- CeroSecManualBook documents. A missing or half-written manual opens as an
-- empty book rather than as an error.
--
-- There are THREE of them -- the User's Guide, the System Administrator's
-- Guide and the Programmer's Guide -- and a reader is opened on ONE, named by
-- its id. The window lays that volume out and nothing else: its cover, its
-- contents, its chapters. There is no fourth book behind them any more: the
-- single volume this mod shipped before the set was retired once all three
-- existed, and a shelf with nothing on it is a volume file that failed to load.
--
-- The one thing the reader does to that text before laying it out is take the
-- writer's hard wrapping back out of it -- see reflow(), below.
--

CeroSecManualUI = ISCollapsableWindow:derive("CeroSecManualUI")

-- One window per local player, the way the terminal does it.
CeroSecManualUI.instances = {}

-- The item's modData key the bookmark is written under. One word, because it
-- sits in the same table anything else may put something in.
CeroSecManualUI.PAGE_KEY = "page"

-- The bookmarks of the books that have no copy: the testing door on the
-- computer's menu (CeroSec.DEV_MANUAL_MENU) opens a volume with no item behind
-- it, and there is nowhere on an item to write where it was left. So they are
-- written here, on the module, for as long as the session lasts. Keyed by
-- volume, because the door opens three different books and the reader's place
-- in one of them is not his place in another. Not saved and not meant to be: a
-- book nobody owns has no shelf to be put back on.
CeroSecManualUI.devPages = {}

-- Paper and ink. Deliberately not CeroSec.COLORS: that palette is a phosphor
-- screen and this is a printed book, and a book that glows green would be the
-- terminal with pages.
CeroSecManualUI.PAPER = {
	page   = { r = 0.898, g = 0.878, b = 0.816 }, -- #e5e0d0, cream stock
	pageLo = { r = 0.812, g = 0.788, b = 0.718 }, -- the shade near the gutter
	edge   = { r = 0.647, g = 0.616, b = 0.541 }, -- the cut edge of the paper
	ink    = { r = 0.114, g = 0.106, b = 0.098 }, -- near black, never black
	inkDim = { r = 0.400, g = 0.376, b = 0.341 }, -- page numbers, the edition
	head   = { r = 0.353, g = 0.153, b = 0.106 }, -- the chapter head, oxblood
	code   = { r = 0.129, g = 0.259, b = 0.169 }, -- an example line, dark green
	codeBg = { r = 0.851, g = 0.831, b = 0.765 }, -- the band behind one
	link   = { r = 0.176, g = 0.267, b = 0.435 }, -- a contents row
	linkHi = { r = 0.792, g = 0.769, b = 0.694 }, -- the row under the cursor
}

-- The fonts. Vanilla ships no serif: media/fonts/EN/fonts.txt maps every
-- readable face to zomboidSmall/Medium/Large, and the one face that is not
-- them -- Handwritten -- is a scrawl the map layers use. So the body of the
-- book is the font vanilla reads its OWN book in: the Survival Guide sets
-- UIFont.NewSmall and UIFont.NewMedium on its list and its text panel
-- (media/lua/client/SurvivalGuide/SurvivalGuide.lua:3-4,47). Example lines are
-- UIFont.Code, the terminal's own monospace, so a command in the book looks
-- like the command on the screen.
CeroSecManualUI.FONT_BODY = "NewMedium"
CeroSecManualUI.FONT_HEAD = "NewLarge"
CeroSecManualUI.FONT_FOOT = "NewSmall"
CeroSecManualUI.FONT_CODE = "Code"

-- How wide a leaf is, counted in columns of the monospaced font. An example
-- line is never wrapped, so the leaf has to be wide enough to hold one: the
-- terminal is sixty columns and an example carries its two spaces of indent,
-- which is where 64 comes from.
CeroSecManualUI.LEAF_COLS = 64
CeroSecManualUI.LEAF_ROWS = 22

local BORDER = 14      -- from the window edge to the paper
local GUTTER = 22      -- between the two leaves
local PAD_X = 20       -- from the paper edge to the text
local PAD_Y = 10
local RULE = 6         -- from the running head's rule down to the first line

-- Measured with the game up, never at load time, and again whenever the answer
-- changes -- the UI font size is an option and it moves. Same reason and same
-- shape as CeroSecTerminal's measure(); see the note there for what a font
-- measured while the mod files are being read hands back.
local BODY_H, CODE_H, HEAD_H, FOOT_H, CELL_W
local LINE_H, LEAF_W, LEAF_H, BOOK_W, TITLE_H, FOOT_BAR, WINDOW_W, WINDOW_H
local generation = 0

local function measure()
	local manager = getTextManager()
	-- The ADVANCE of one monospaced cell, not the ink of one glyph.
	-- MeasureStringX counts the last character of a string as its glyph's ink
	-- `width` and every other as its `xadvance`, while the pen that draws only
	-- ever moves by `xadvance` -- and in zomboidCode.fnt "M" is width=9
	-- xadvance=8, a pixel WIDER in ink than the cell it is drawn in. So
	-- MeasureStringX("M") is a cell a pixel too wide and a leaf LEAF_COLS pixels
	-- too wide; the subtraction below is the advance exactly, whatever the ink of
	-- the glyph happens to be. Same reasoning, same shape and the same lesson as
	-- CeroSecTerminal's CELL_W -- see the long note there.
	local cellW = manager:MeasureStringX(UIFont.Code, "MM") -
		manager:MeasureStringX(UIFont.Code, "M")
	local bodyH = manager:getFontHeight(UIFont[CeroSecManualUI.FONT_BODY])
	if cellW == CELL_W and bodyH == BODY_H then return end

	CELL_W, BODY_H = cellW, bodyH
	CODE_H = manager:getFontHeight(UIFont[CeroSecManualUI.FONT_CODE])
	HEAD_H = manager:getFontHeight(UIFont[CeroSecManualUI.FONT_HEAD])
	FOOT_H = manager:getFontHeight(UIFont[CeroSecManualUI.FONT_FOOT])
	-- One line box for both faces: a monospaced line taller than a body line
	-- must not sit on the line under it.
	LINE_H = math.max(BODY_H, CODE_H) + 2

	LEAF_W = CELL_W * CeroSecManualUI.LEAF_COLS + PAD_X * 2
	LEAF_H = PAD_Y + HEAD_H + RULE + LINE_H * CeroSecManualUI.LEAF_ROWS + FOOT_H + PAD_Y
	BOOK_W = LEAF_W * 2 + GUTTER
	TITLE_H = math.max(16, manager:getFontHeight(UIFont.Small) + 1)
	FOOT_BAR = FOOT_H + 14
	WINDOW_W = BOOK_W + BORDER * 2
	WINDOW_H = TITLE_H + LEAF_H + BORDER * 2 + FOOT_BAR

	-- The layout moved, so every book laid out against the old one is stale.
	generation = generation + 1
end

-- What the text is measured with while a leaf is being laid out. The body font
-- is the one that wraps; the monospaced lines are never wrapped, so they never
-- reach here.
--
-- MeasureStringX itself, ink of the last glyph and all, and deliberately: this
-- places nothing. It answers "does this line fit the leaf", and the error is the
-- side bearing of whatever character the line happens to end on -- a pixel or
-- two, always in the direction of fitting slightly more than would fit, against
-- a leaf with twenty pixels of margin. Where an answer PLACES something -- the
-- cell the monospaced grid is built on, above -- the advance is what is asked
-- for, because a pixel per column is a column by the end of a row.
local function textWidth(text)
	return getTextManager():MeasureStringX(UIFont[CeroSecManualUI.FONT_BODY], text)
end

--
-- Opening
--

-- One volume of the manual as it stands right now, and the id it is filed
-- under. Read through a function and never cached, because the text is in
-- separate files and a reload of one of them must not leave every open book
-- showing the old edition.
--
-- The cover carries the OS' version and a manual file cannot build it at load
-- time (the core loads after all of them), so it is stamped here, at the last
-- moment before the layout reads it. A half-written table that never gets a
-- stamp is still an empty book and never an error.
--
-- There is no book behind an id nothing answers to and there is no fallback
-- left: the set is three shipped files, each of which puts itself on the shelf
-- at load time, so an empty shelf is not a state the game has -- it is a file
-- that failed to load. That is a bug and it is said where an operator can read
-- it; the window still opens, as an empty book, because a reader is the wrong
-- place to take a client down from.
function CeroSecManualUI.text(volumeId)
	local volume = CeroSecManualBook.volume(volumeId)
	if volume then return volume, volume.id end

	if CeroSec ~= nil and CeroSec.log ~= nil then
		CeroSec.log(CeroSec.LOG_ERROR, "manual: nothing on the shelf answers to " .. tostring(volumeId) ..
			" -- a CeroSecManual volume file did not load")
	end
	return nil, volumeId or CeroSecManualBook.NO_VOLUME
end

--
-- Reflowing an authored page
--
-- The text is typed into a file by hand, so its paragraphs are hard-wrapped at
-- whatever column the writer's editor sat at -- and a leaf is not that column.
-- Handing that straight to the layout, which ends a line at every `\n`, printed
-- each of the writer's lines and then wrapped what was left of it again: a
-- seventy-column line on a sixty-four-column leaf came out as a full row and
-- then a row holding the one word that fell off it. That is what page 87 looked
-- like -- prose, then a line reading "the", then prose again.
--
-- So inside a page a SINGLE newline is a SPACE: the paragraph is joined back
-- into one piece and wrapped once, against the leaf. A BLANK line is the
-- paragraph break, and typing one is the only way the writer gets a break. An
-- example line -- two leading spaces, drawn monospaced and never wrapped -- is
-- never joined to anything: it keeps its own row whatever is above or below it,
-- and the newline between an example and prose is a real break on both sides.
--
-- This rewrites the TEXT and nothing else. The wrapping, the widths, the fonts
-- and the pagination are the book's (CeroSecManualBook) and are untouched: what
-- reaches it is the same contract it already documents, with the writer's
-- accidental line endings taken back out of it first.
function CeroSecManualUI.reflow(text)
	if type(text) ~= "string" then return text end
	local out = {}      -- the lines to hand on, in the order they were written
	local para = nil    -- the prose gathered so far, waiting for what ends it
	-- Walked by hand rather than by gmatch, for the reason CeroSecManualBook's
	-- own splitter is: "([^\n]*)\n?" loops forever on the empty tail in 5.1.
	local start = 1
	while true do
		local stop = string.find(text, "\n", start, true)
		local piece = stop and string.sub(text, start, stop - 1) or string.sub(text, start)
		if CeroSecManualBook.isExample(piece) then
			if para then out[#out + 1] = para; para = nil end
			out[#out + 1] = piece
		elseif string.match(piece, "%S") then
			-- Trimmed at both ends, because the join is what puts the single
			-- space between two of these: a line typed with a trailing space, or
			-- indented by one, would otherwise be joined with two or three.
			local prose = string.match(piece, "^%s*(.-)%s*$")
			para = para and (para .. " " .. prose) or prose
		else
			if para then out[#out + 1] = para; para = nil end
			out[#out + 1] = ""
		end
		if not stop then break end
		start = stop + 1
	end
	if para then out[#out + 1] = para end
	return table.concat(out, "\n")
end

-- The manual with every authored page reflowed, which is what the layout is
-- given. A fresh table of the four fields the layout reads, because the text
-- is a global anybody may be reading and a reader must not rewrite it.
function CeroSecManualUI.reflowed(manual)
	if type(manual) ~= "table" then return manual end
	local chapters = {}
	local authored = manual.chapters or {}
	for c = 1, #authored do
		local chapter = authored[c]
		local pages = {}
		local written = chapter.pages or {}
		for p = 1, #written do pages[p] = CeroSecManualUI.reflow(written[p]) end
		chapters[c] = { title = chapter.title, pages = pages }
	end
	return { title = manual.title, name = manual.name,
		edition = manual.edition, chapters = chapters }
end

-- The book a window is reading, and the id its bookmark is filed under: a
-- volume off the shelf, or a DOCUMENT handed in whole.
--
-- A document is a book that is not on the shelf because it is not the same book
-- twice: the telephone directory is generated from the county as it stands and
-- one copy of it is the listings of one region (CeroSecPhonebook). It is the
-- same SHAPE a volume is -- title, edition, chapters of pages -- so the whole
-- of what the reader does differently with one is not go and look for it, and
-- everything after this line treats the two alike.
function CeroSecManualUI:source()
	if type(self.document) == "table" then
		return self.document, self.document.id or CeroSecManualBook.NO_VOLUME
	end
	return CeroSecManualUI.text(self.volumeId)
end

-- Open a volume. `volumeId` is one of the ids on the shelf, or nil for "the
-- manual" with nothing said about which, which is the first volume. `document`
-- is a book handed in instead of looked up, and it wins over the id.
--
-- The player stays the first argument and not the volume: the window belongs
-- to him, it is his instance that a second opening closes, and he is what
-- closes it when he dies.
function CeroSecManualUI.open(playerObj, volumeId, item, document)
	measure()
	local playerNum = playerObj:getPlayerNum()
	local previous = CeroSecManualUI.instances[playerNum]
	if previous then previous:close() end

	local x = (getCore():getScreenWidth() - WINDOW_W) / 2
	local y = (getCore():getScreenHeight() - WINDOW_H) / 2
	local window = CeroSecManualUI:new(x, y, playerObj, volumeId, item, document)
	window:initialise()
	window:addToUIManager()
	CeroSecManualUI.instances[playerNum] = window
	return window
end

function CeroSecManualUI:new(x, y, playerObj, volumeId, item, document)
	measure()
	local o = ISCollapsableWindow.new(self, x, y, WINDOW_W, WINDOW_H)
	o.playerObj = playerObj
	o.playerNum = playerObj:getPlayerNum()
	o.volumeId = volumeId
	o.item = item
	o.document = document

	o:layout()
	-- Where the book was left. A number off modData is not to be trusted --
	-- the manual may have been rewritten since it was written there -- so it
	-- goes through the book's own clamp, which also brings it back to the left
	-- leaf of its sheet. With no item there is no modData, and the bookmark is
	-- the module's own for THIS volume: the door's place in the Programmer's
	-- Guide is not its place in the User's Guide.
	local page = CeroSecManualUI.devPages[o.bookId]
	if item and item.getModData then
		local data = item:getModData()
		page = data and data[CeroSecManualUI.PAGE_KEY]
	end
	o.page = CeroSecManualBook.clampPage(o.book, page)

	o:setResizable(false)
	o:setTitle(o.book.title)
	o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
	o.backgroundColor = { r = 0.078, g = 0.071, b = 0.063, a = 0.95 }
	-- Left, Right and Escape reach a window only when it says it wants them
	-- (ISUIElement:setWantKeyEvents, ISUIElement.lua:1828, and the vanilla
	-- windows that use it: ISVehicleAnimalUI.lua:439, ISSetKeybindDialog.lua:133).
	o:setWantKeyEvents(true)
	return o
end

-- Lay the text out against the geometry as it stands. Called when the window
-- is made and again whenever the measured layout has moved under it.
function CeroSecManualUI:layout()
	local text, bookId = self:source()
	-- What the reader really ended up with. The bookmark of a book with no copy
	-- is filed under this, and it is never nil: a bookmark table cannot be keyed
	-- by nothing, and a reader opened on "the manual" is reading volume one.
	self.bookId = bookId
	self.book = CeroSecManualBook.open(CeroSecManualUI.reflowed(text), {
		width = LEAF_W - PAD_X * 2,
		rows = CeroSecManualUI.LEAF_ROWS,
		measure = textWidth,
	})
	self.generation = generation
	-- The rows the contents page put on the glass last frame, kept so a click
	-- can be matched against what was actually drawn rather than against what
	-- the layout thinks is there.
	self.hotRows = {}
end

function CeroSecManualUI:createChildren()
	ISCollapsableWindow.createChildren(self)

	local h = FOOT_H + 8
	local w = math.max(70, getTextManager():MeasureStringX(UIFont[CeroSecManualUI.FONT_FOOT],
		getText("IGUI_CeroSec_Manual_Contents")) + 20)
	local y = TITLE_H + BORDER + LEAF_H + (FOOT_BAR - h) / 2

	self.prevButton = ISButton:new(BORDER, y, w, h,
		getText("IGUI_CeroSec_Manual_Prev"), self, CeroSecManualUI.onPrev)
	self.prevButton:initialise()
	self.prevButton:instantiate()
	self.prevButton:setFont(UIFont[CeroSecManualUI.FONT_FOOT])
	self:addChild(self.prevButton)

	self.tocButton = ISButton:new(BORDER + BOOK_W / 2 - w / 2, y, w, h,
		getText("IGUI_CeroSec_Manual_Contents"), self, CeroSecManualUI.onContents)
	self.tocButton:initialise()
	self.tocButton:instantiate()
	self.tocButton:setFont(UIFont[CeroSecManualUI.FONT_FOOT])
	self:addChild(self.tocButton)

	self.nextButton = ISButton:new(BORDER + BOOK_W - w, y, w, h,
		getText("IGUI_CeroSec_Manual_Next"), self, CeroSecManualUI.onNext)
	self.nextButton:initialise()
	self.nextButton:instantiate()
	self.nextButton:setFont(UIFont[CeroSecManualUI.FONT_FOOT])
	self:addChild(self.nextButton)
end

--
-- Turning the leaves
--

function CeroSecManualUI:sheet()
	return CeroSecManualBook.sheetOf(self.page)
end

-- Go to a sheet number, clamped to the book, and remember it on the item. The
-- bookmark is the LEFT page of the sheet, so a book reopened is a book open at
-- the same two leaves and not at the right-hand one alone.
function CeroSecManualUI:goToSheet(sheet)
	local last = CeroSecManualBook.sheetCount(self.book)
	if sheet < 1 then sheet = 1 end
	if sheet > last then sheet = last end
	self.page = CeroSecManualBook.leftOf(sheet)
	self:remember()
end

-- Go to a printed page number: the sheet it is on.
function CeroSecManualUI:goToPage(page)
	self:goToSheet(CeroSecManualBook.sheetOf(page))
end

function CeroSecManualUI:onPrev()
	self:goToSheet(self:sheet() - 1)
end

function CeroSecManualUI:onNext()
	self:goToSheet(self:sheet() + 1)
end

-- The contents leaf is always the second one, right behind the title page.
function CeroSecManualUI:onContents()
	self:goToPage(2)
end

function CeroSecManualUI:remember()
	local item = self.item
	if not item or not item.getModData then
		CeroSecManualUI.devPages[self.bookId] = self.page
		return
	end
	local data = item:getModData()
	if not data then return end
	data[CeroSecManualUI.PAGE_KEY] = self.page
end

-- Left and Right turn the sheet, Escape closes. Keys reach the window through
-- setWantKeyEvents; isKeyConsumed is what stops Escape also reaching whatever
-- is behind it (the pattern ISVehicleAnimalUI.lua:483-494 uses).
function CeroSecManualUI:isKeyConsumed(key)
	if key == Keyboard.KEY_ESCAPE then return true end
	if key == Keyboard.KEY_LEFT or key == Keyboard.KEY_RIGHT then return true end
	return false
end

function CeroSecManualUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then
		self:close()
	elseif key == Keyboard.KEY_LEFT then
		self:onPrev()
	elseif key == Keyboard.KEY_RIGHT then
		self:onNext()
	elseif key == Keyboard.KEY_HOME then
		self:goToSheet(1)
	end
end

-- A click on a contents row goes to that chapter. hotRows is what was drawn
-- last frame, in window coordinates, so nothing here has to work the layout
-- out a second time and get it slightly different.
function CeroSecManualUI:onMouseDown(x, y)
	for i = 1, #self.hotRows do
		local row = self.hotRows[i]
		if x >= row.x and x < row.x + row.w and y >= row.y and y < row.y + row.h then
			self:goToPage(row.page)
			return true
		end
	end
	return ISCollapsableWindow.onMouseDown(self, x, y)
end

--
-- Closing
--

function CeroSecManualUI:close()
	if self.closing then return end
	self.closing = true
	if CeroSecManualUI.instances[self.playerNum] == self then
		CeroSecManualUI.instances[self.playerNum] = nil
	end
	self:setVisible(false)
	self:removeFromUIManager()
end

-- The book shuts when the player stops being able to hold it: he is dead, or
-- the item has left his hands. Nothing else -- walking, fighting and driving
-- are all things a survivor can do with a book open in front of the player.
--
-- A book opened with no item behind it -- the testing door on the computer's
-- menu -- has nothing to leave anybody's hands, so the player is the whole of
-- the test for it.
function CeroSecManualUI:stillValid()
	local playerObj = self.playerObj
	if not playerObj or playerObj:isDead() then return false end
	if not self.item then return true end
	local container = self.item:getContainer()
	if not container then return false end
	return true
end

--
-- Drawing
--

function CeroSecManualUI:prerender()
	if not self.closing and not self:stillValid() then
		self:close()
		return
	end
	-- The font size moved under the open book: lay it out again, and keep the
	-- reader on the page he was on rather than at the front.
	if self.generation ~= generation then
		local was = self.page
		self:layout()
		self.page = CeroSecManualBook.clampPage(self.book, was)
	end
	ISCollapsableWindow.prerender(self)
	self:drawPaper()
end

function CeroSecManualUI:drawPaper()
	local paper = CeroSecManualUI.PAPER
	local top = TITLE_H + BORDER

	for leaf = 0, 1 do
		local x = BORDER + leaf * (LEAF_W + GUTTER)
		self:drawRect(x, top, LEAF_W, LEAF_H, 1, paper.page.r, paper.page.g, paper.page.b)
		self:drawRect(x - 1, top - 1, LEAF_W + 2, 1, 1, paper.edge.r, paper.edge.g, paper.edge.b)
		self:drawRect(x - 1, top + LEAF_H, LEAF_W + 2, 1, 1, paper.edge.r, paper.edge.g, paper.edge.b)
		self:drawRect(x - 1, top - 1, 1, LEAF_H + 2, 1, paper.edge.r, paper.edge.g, paper.edge.b)
		self:drawRect(x + LEAF_W, top - 1, 1, LEAF_H + 2, 1, paper.edge.r, paper.edge.g, paper.edge.b)
		-- The paper curves into the gutter: a few darkening columns on the
		-- inner edge of each leaf, which is the whole of the two-page look.
		for i = 0, 5 do
			local alpha = (6 - i) / 22
			local gx = (leaf == 0) and (x + LEAF_W - 1 - i) or (x + i)
			self:drawRect(gx, top, 1, LEAF_H, alpha, paper.pageLo.r, paper.pageLo.g, paper.pageLo.b)
		end
	end
end

function CeroSecManualUI:render()
	local top = TITLE_H + BORDER
	self.hotRows = {}
	for leaf = 0, 1 do
		local page = self.page + leaf
		local x = BORDER + leaf * (LEAF_W + GUTTER)
		self:drawLeaf(self.book.pages[page], page, x, top)
	end
	ISCollapsableWindow.render(self)
end

function CeroSecManualUI:drawLeaf(page, number, x, top)
	if not page then return end
	local paper = CeroSecManualUI.PAPER
	local textX = x + PAD_X
	local textW = LEAF_W - PAD_X * 2
	local y = top + PAD_Y

	if page.kind == "title" then
		self:drawTitleLeaf(x, top)
	elseif page.kind == "toc" then
		self:drawHead(getText("IGUI_CeroSec_Manual_Contents"), textX, y, textW)
		self:drawContents(page, textX, top + PAD_Y + HEAD_H + RULE, textW)
	else
		if page.chapter and page.chapter ~= "" then
			self:drawHead(page.chapter, textX, y, textW)
		end
		self:drawLines(page.lines, textX, top + PAD_Y + HEAD_H + RULE, textW)
	end

	-- The page number, at the foot, on the outer corner the way a book prints
	-- it: the left leaf's on the left, the right leaf's on the right.
	local footY = top + LEAF_H - PAD_Y - FOOT_H
	local label = tostring(number)
	local fx = textX
	if number % 2 == 0 then
		fx = x + LEAF_W - PAD_X -
			getTextManager():MeasureStringX(UIFont[CeroSecManualUI.FONT_FOOT], label)
	end
	self:drawText(label, fx, footY,
		paper.inkDim.r, paper.inkDim.g, paper.inkDim.b, 1, UIFont[CeroSecManualUI.FONT_FOOT])
end

function CeroSecManualUI:drawHead(text, x, y, width)
	local paper = CeroSecManualUI.PAPER
	self:drawText(text, x, y, paper.head.r, paper.head.g, paper.head.b, 1,
		UIFont[CeroSecManualUI.FONT_HEAD])
	self:drawRect(x, y + HEAD_H + 2, width, 1, 1, paper.edge.r, paper.edge.g, paper.edge.b)
end

function CeroSecManualUI:drawTitleLeaf(x, top)
	local paper = CeroSecManualUI.PAPER
	local manager = getTextManager()
	local centre = x + LEAF_W / 2
	local y = top + LEAF_H / 3

	local title = self.book.title
	local w = manager:MeasureStringX(UIFont[CeroSecManualUI.FONT_HEAD], title)
	self:drawText(title, centre - w / 2, y,
		paper.head.r, paper.head.g, paper.head.b, 1, UIFont[CeroSecManualUI.FONT_HEAD])

	self:drawRect(x + PAD_X * 2, y + HEAD_H + 8, LEAF_W - PAD_X * 4, 1, 1,
		paper.edge.r, paper.edge.g, paper.edge.b)

	local edition = self.book.edition
	if edition and edition ~= "" then
		local ew = manager:MeasureStringX(UIFont[CeroSecManualUI.FONT_BODY], edition)
		self:drawText(edition, centre - ew / 2, y + HEAD_H + 18,
			paper.inkDim.r, paper.inkDim.g, paper.inkDim.b, 1,
			UIFont[CeroSecManualUI.FONT_BODY])
	end
end

function CeroSecManualUI:drawLines(lines, x, y, width)
	local paper = CeroSecManualUI.PAPER
	for i = 1, #lines do
		local line = lines[i]
		local ly = y + (i - 1) * LINE_H
		if line.code then
			-- A faint band behind the monospaced run, so an example reads as a
			-- block of screen and not as a differently shaped sentence.
			self:drawRect(x - 4, ly - 1, width + 8, LINE_H, 1,
				paper.codeBg.r, paper.codeBg.g, paper.codeBg.b)
			self:drawText(line.text, x, ly,
				paper.code.r, paper.code.g, paper.code.b, 1,
				UIFont[CeroSecManualUI.FONT_CODE])
		elseif line.text ~= "" then
			self:drawText(line.text, x, ly,
				paper.ink.r, paper.ink.g, paper.ink.b, 1,
				UIFont[CeroSecManualUI.FONT_BODY])
		end
	end
end

function CeroSecManualUI:drawContents(page, x, y, width)
	local paper = CeroSecManualUI.PAPER
	local manager = getTextManager()
	local entries = page.entries or {}
	local mx, my = self:getMouseX(), self:getMouseY()

	for i = 1, #entries do
		local entry = entries[i]
		local ly = y + (i - 1) * LINE_H
		local over = mx >= x - 4 and mx < x + width + 4 and my >= ly - 1 and my < ly - 1 + LINE_H
		if over then
			self:drawRect(x - 4, ly - 1, width + 8, LINE_H, 1,
				paper.linkHi.r, paper.linkHi.g, paper.linkHi.b)
		end

		-- The title as the chapter carries it, and nothing in front of it: a
		-- chapter already numbered on its own leaf ("1. Your machine") read
		-- "1.  1. Your machine" with a row index prefixed to it.
		self:drawText(entry.title, x, ly,
			paper.link.r, paper.link.g, paper.link.b, 1, UIFont[CeroSecManualUI.FONT_BODY])

		local number = tostring(entry.page)
		local nw = manager:MeasureStringX(UIFont[CeroSecManualUI.FONT_BODY], number)
		self:drawText(number, x + width - nw, ly,
			paper.inkDim.r, paper.inkDim.g, paper.inkDim.b, 1,
			UIFont[CeroSecManualUI.FONT_BODY])

		self.hotRows[#self.hotRows + 1] =
			{ x = x - 4, y = ly - 1, w = width + 8, h = LINE_H, page = entry.page }
	end
end
