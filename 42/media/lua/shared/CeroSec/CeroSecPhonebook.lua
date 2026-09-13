require "CeroSec/OS/CeroSecOSNet"

--
-- The Knox County telephone directory.
--
-- Base.Phonebook is a vanilla item that relieves boredom and does nothing else.
-- It is a PHONE BOOK, and the county has telephone numbers in it: one per
-- premises, derived from the map (CeroSecNet.premisesOf, CeroSecOS.phoneOfZone).
-- So the book is the yellow pages of the region it was picked up in, and reading
-- it is how a survivor finds a number to dial without walking into the shop.
--
-- Three parts, and this file is the middle one:
--
--   * the SERVER enumerates the premises of one region and their numbers
--     (CeroSecNet.directory, which is where the world is asked);
--   * THIS file turns that list into a volume the manual reader can lay out --
--     pure Lua, no game call, so a bench lays out the same pages the player
--     reads;
--   * the CLIENT stamps the edition on the item and opens the reader
--     (CeroSecPhonebookUI).
--
-- WHAT IS IN IT, and what is not. A telephone directory of 1993 had two halves:
-- the white pages (households, by family name) and the yellow (businesses, by
-- trade). Only the yellow half can be printed here, and the reason is the map:
-- a business has a name in the shipped data -- the named ZombiesType zone the
-- premises rule is already built on -- and a house has none. Knox County's
-- houses hold no family names anywhere, so a white-pages line would have to be
-- invented, and this mod does not invent. A residence therefore has a line and a
-- number and is not listed, exactly as an unlisted number was not listed in 1993.
--
-- THE EDITION. A directory is a region's, because an exchange is
-- (CeroSecOS.phoneExchange): one central office, one book. Which region a given
-- copy is the book of is stamped on the item the first time it is opened -- where
-- it was found -- and never again, so carrying it across the county carries the
-- book of the place it came from, which is what carrying a phone book does.
--

CeroSec = CeroSec or {}
CeroSecPhonebook = CeroSecPhonebook or {}

-- The vanilla item this is all about. Not one of ours: the mod adds no book, it
-- gives a meaning to one the game already scatters in 22 loot spots.
CeroSecPhonebook.ITEM = "Base.Phonebook"

-- The item's modData: which region's book this copy is. One table under one key,
-- because the item's modData is shared with anything else that writes there --
-- the reader's own bookmark sits beside it.
CeroSecPhonebook.DATA_KEY = "cerosec"
CeroSecPhonebook.REGION_KEY = "region"

-- And the shape of that one table, with a chain beside it, on exactly the terms the
-- door modules have (see the head of CeroSecModules.lua): a stamp on an item is a
-- save file, and the edition written on a copy is a thing a survivor found and
-- carried, so a change that changes what is written there does not cost him the book
-- he is holding. Empty today; an absent number is the oldest shape, because the two
-- coordinates in a table written before this change are the two coordinates version 1
-- has. Stamped when the edition is (CeroSecPhonebook.stampRegion).
CeroSecPhonebook.VERSION = 1
CeroSecPhonebook.VERSION_KEY = "v"
CeroSecPhonebook.MIGRATIONS = {}
CeroSecPhonebook.OLDEST_VERSION = 1

-- The table, walked up to this build, in place. true when it is readable at all: one
-- a LATER build wrote is left exactly as it is and answers false, so the copy is a
-- copy nobody has opened yet rather than a copy this build has re-stamped with a
-- region of its own -- and putting the newer mod back gives the edition back.
function CeroSecPhonebook.migrate(mine)
	if type(mine) ~= "table" then return false end
	local v = mine[CeroSecPhonebook.VERSION_KEY]
	if type(v) ~= "number" or v ~= math.floor(v) or v < CeroSecPhonebook.OLDEST_VERSION then
		v = CeroSecPhonebook.OLDEST_VERSION
	end
	if v > CeroSecPhonebook.VERSION then return false end
	for n = v + 1, CeroSecPhonebook.VERSION do
		local step = CeroSecPhonebook.MIGRATIONS[n]
		if type(step) ~= "function" then return false end
		step(mine)
		mine[CeroSecPhonebook.VERSION_KEY] = n
	end
	return true
end

-- What the cover says. English, like the manual volumes and for the same reason:
-- it is a 1993 American book and not a label on the interface.
CeroSecPhonebook.TITLE = "Knox County Telephone Directory"
CeroSecPhonebook.EDITION = "1993 Edition"

-- The two lines under the exchange, and the whole of what the book says in its
-- own voice.
CeroSecPhonebook.PREFACE =
	"Business listings. Dial the seven digits. Toll-free within the county."

-- How many listings one book holds. A region of Knox County has nothing like
-- this many premises in it; the cap is here so that a map with a thousand named
-- zones in one region cannot hand a client a thousand-page book, and it says so
-- on the last line when it bites rather than quietly printing a shorter county.
CeroSecPhonebook.MAX_ENTRIES = 400

-- A leaf of the reader is 64 monospaced columns and an example line carries two
-- of them as its indent (CeroSecManualUI.LEAF_COLS), so a listing line is 58 and
-- the two spaces in front of it make 60 -- which is the width the manual's own
-- example lines are held to.
CeroSecPhonebook.LINE_COLS = 58

-- How many listings go on one leaf. The reader fits 22 rows
-- (CeroSecManualUI.LEAF_ROWS), and it is not the rows that decide this: an
-- authored page is held to 1000 CHARACTERS by the manual's own rule, and sixteen
-- listings of sixty columns with their newlines between them is 975 of them.
-- Twenty would be 1219, which is a page the rest of the book would not be allowed
-- to have.
CeroSecPhonebook.PAGE_LINES = 16

-- A zone name as a person reads it: "CoffeeShop" -> "Coffee Shop". The map data
-- is one word in camel case because it is a spawner key, and a directory printed
-- in spawner keys is a directory nobody would read.
--
-- THE RULE: a space in front of a capital that follows a lower-case letter or a
-- digit. Deliberately that and nothing cleverer -- a run of capitals is left
-- alone ("PileOCrepe" keeps its O against its C), because the alternative is
-- guessing where a word ends inside an acronym and this file does not guess.
function CeroSecPhonebook.spaced(name)
	if type(name) ~= "string" then return nil end
	local out = ""
	for i = 1, #name do
		local char = string.sub(name, i, i)
		local before = i > 1 and string.sub(name, i - 1, i - 1) or ""
		if string.find(char, "%u") and string.find(before, "[%l%d]") then
			out = out .. " "
		end
		out = out .. char
	end
	return out
end

-- One printed listing: the name, dot leaders, the number, in 58 columns. The
-- leaders are what a directory has instead of a table, and they are what makes a
-- column of numbers readable on paper.
--
-- A name too long for the line is cut rather than wrapped: a listing that ran
-- onto a second row would be a listing whose number belonged to the row above
-- it. Nothing on the shipped map comes near the limit.
function CeroSecPhonebook.entryLine(name, number)
	if type(name) ~= "string" or type(number) ~= "string" then return nil end
	-- name, a space, the leaders, a space, the number.
	local room = CeroSecPhonebook.LINE_COLS - #number - 2
	local shown = name
	-- Two leaders at the least, so the line never reads as one word.
	if #shown > room - 2 then shown = string.sub(shown, 1, room - 2) end
	local dots = string.rep(".", room - #shown)
	return "  " .. shown .. " " .. dots .. " " .. number
end

-- The listings of a region, sorted the way a directory is: by name, and by
-- number within one name. Two shops of one chain are two listings with one name
-- and two numbers, each on its own line, which is what a directory printed.
--
-- Sorted HERE and not on the wire, so the order cannot depend on what order the
-- map handed its zones over.
function CeroSecPhonebook.sorted(entries)
	local out = {}
	for i = 1, #entries do
		local entry = entries[i]
		if type(entry) == "table" and type(entry.name) == "string"
				and type(entry.number) == "string" then
			out[#out + 1] = { name = entry.name, number = entry.number }
		end
	end
	table.sort(out, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.number < b.number
	end)
	return out
end

-- The whole book, as the volume shape CeroSecManualBook.open takes: a cover, one
-- chapter named after the exchange, a preface leaf and then the listings.
--
-- `capped` is told and not worked out here: whether the county was cut is the
-- enumerator's fact (it is the one that counted), and a book that guessed it
-- from having exactly MAX_ENTRIES lines would lie on a region with exactly that
-- many premises in it.
function CeroSecPhonebook.volume(exchange, entries, capped)
	local listings = CeroSecPhonebook.sorted(entries or {})
	local head = "Exchange " .. tostring(exchange)

	local pages = { head .. "\n\n" .. CeroSecPhonebook.PREFACE }

	local page = {}
	local function flush()
		if #page == 0 then return end
		pages[#pages + 1] = table.concat(page, "\n")
		page = {}
	end
	for i = 1, #listings do
		page[#page + 1] = CeroSecPhonebook.entryLine(listings[i].name, listings[i].number)
		if #page >= CeroSecPhonebook.PAGE_LINES then flush() end
	end
	-- The cap, on the last line of the last leaf and nowhere else: a reader who
	-- has turned to the end is the one who needs to be told the end is not the
	-- end of the county.
	if capped then
		page[#page + 1] = "This directory is full at " ..
			CeroSecPhonebook.MAX_ENTRIES .. " listings. Others in this exchange " ..
			"are not printed here."
	end
	flush()
	-- A region with nothing named in it is a region with no businesses in it, and
	-- the book says so rather than opening on blank paper.
	if #pages == 1 then
		pages[2] = "No business listings for this exchange."
	end

	return {
		id = CeroSecPhonebook.DATA_KEY .. ":phonebook",
		title = CeroSecPhonebook.TITLE,
		name = CeroSecPhonebook.TITLE,
		edition = CeroSecPhonebook.EDITION,
		chapters = { { title = head, pages = pages } },
	}
end

--
-- What is written on the copy
--

-- The region a copy is the book of, or nil for one nobody has opened yet.
-- Believed only when it is two numbers: modData is on the item and an item
-- travels.
function CeroSecPhonebook.regionOn(data)
	if type(data) ~= "table" then return nil end
	local mine = data[CeroSecPhonebook.DATA_KEY]
	if type(mine) ~= "table" then return nil end
	-- The chain, in the ONE place the stamp is read, so a copy written by an older
	-- build is walked up here or nowhere. One a later build wrote reads as unstamped:
	-- the number on it is not a number this build knows, and inventing an edition for
	-- it would be worse than opening the book on the place it was picked up.
	if not CeroSecPhonebook.migrate(mine) then return nil end
	local region = mine[CeroSecPhonebook.REGION_KEY]
	if type(region) ~= "table" then return nil end
	local rx, ry = region[1], region[2]
	if type(rx) ~= "number" or type(ry) ~= "number" then return nil end
	return math.floor(rx), math.floor(ry)
end

-- Stamp the edition on a copy, once. Hands back the region it now carries,
-- which is the one it already carried if it had one -- a book is printed once
-- and this is the whole of why a directory carried across the county is still
-- the directory of where it was found.
function CeroSecPhonebook.stampRegion(data, rx, ry)
	local was, wasY = CeroSecPhonebook.regionOn(data)
	if was ~= nil then return was, wasY end
	if type(data) ~= "table" then return nil end
	if type(rx) ~= "number" or type(ry) ~= "number" then return nil end
	local mine = data[CeroSecPhonebook.DATA_KEY]
	if type(mine) ~= "table" then
		mine = {}
		data[CeroSecPhonebook.DATA_KEY] = mine
	end
	mine[CeroSecPhonebook.REGION_KEY] = { math.floor(rx), math.floor(ry) }
	-- And the shape it is written in, beside it: the one write there is, so the one
	-- place the stamp goes.
	mine[CeroSecPhonebook.VERSION_KEY] = CeroSecPhonebook.VERSION
	return math.floor(rx), math.floor(ry)
end
