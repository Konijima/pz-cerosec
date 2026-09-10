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
-- The TEXT is not here and is not this file's business: it is the global
-- CeroSecManual, written in shared/CeroSec/CeroSecManual.lua, and the shape of
-- it is the contract CeroSecManualBook documents. A missing or half-written
-- manual opens as an empty book rather than as an error.
--

CeroSecManualUI = ISCollapsableWindow:derive("CeroSecManualUI")

-- One window per local player, the way the terminal does it.
CeroSecManualUI.instances = {}

-- The item's modData key the bookmark is written under. One word, because it
-- sits in the same table anything else may put something in.
CeroSecManualUI.PAGE_KEY = "page"

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
	local cellW = manager:MeasureStringX(UIFont.Code, "M")
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
local function textWidth(text)
	return getTextManager():MeasureStringX(UIFont[CeroSecManualUI.FONT_BODY], text)
end

--
-- Opening
--

-- The manual as it stands right now. Read through a function and never cached,
-- because the text is a separate file and a reload of it must not leave every
-- open book showing the old edition.
function CeroSecManualUI.text()
	return CeroSecManual
end

function CeroSecManualUI.open(playerObj, item)
	measure()
	local playerNum = playerObj:getPlayerNum()
	local previous = CeroSecManualUI.instances[playerNum]
	if previous then previous:close() end

	local x = (getCore():getScreenWidth() - WINDOW_W) / 2
	local y = (getCore():getScreenHeight() - WINDOW_H) / 2
	local window = CeroSecManualUI:new(x, y, playerObj, item)
	window:initialise()
	window:addToUIManager()
	CeroSecManualUI.instances[playerNum] = window
	return window
end

function CeroSecManualUI:new(x, y, playerObj, item)
	measure()
	local o = ISCollapsableWindow.new(self, x, y, WINDOW_W, WINDOW_H)
	o.playerObj = playerObj
	o.playerNum = playerObj:getPlayerNum()
	o.item = item

	o:layout()
	-- Where the book was left. A number off modData is not to be trusted --
	-- the manual may have been rewritten since it was written there -- so it
	-- goes through the book's own clamp, which also brings it back to the left
	-- leaf of its sheet.
	local page = 1
	if item and item.getModData then
		local data = item:getModData()
		if data then page = data[CeroSecManualUI.PAGE_KEY] end
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
	self.book = CeroSecManualBook.open(CeroSecManualUI.text(), {
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
	if not item or not item.getModData then return end
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
function CeroSecManualUI:stillValid()
	local playerObj = self.playerObj
	if not playerObj or playerObj:isDead() then return false end
	if not self.item then return false end
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

		local label = tostring(entry.index) .. ".  " .. entry.title
		self:drawText(label, x, ly,
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
