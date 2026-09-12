require "CeroSec/CeroSecPhonebook"
require "CeroSec/CeroSecManualUI"

--
-- Looking a number up in the phone book.
--
-- The client half of CeroSecPhonebook: it stamps the edition on the copy, asks
-- the server for that region's listings, and opens the manual reader on the book
-- the answer makes. Nothing here knows what a zone is and nothing here derives a
-- number -- the world is the server's (CeroSecNet.directory) and the arithmetic
-- is the OS core's (CeroSecOS.phoneOfZone).
--
-- THE EDITION IS STAMPED ONCE, the first time a copy is opened, and it is stamped
-- with the region the reader is standing in: a phone book is the book of the place
-- it was printed, and where it was found is the only thing the game can know
-- about that. After that the copy carries its region wherever it goes, so a book
-- picked up in Rosewood read in Muldraugh is still Rosewood's book -- which is
-- what carrying a phone book across a county does.
--
-- The name goes on at the same moment and for the same reason: a survivor with
-- three books in a bag has to be able to tell which exchange each of them is.
-- `zombie.inventory.InventoryItem.setName(java.lang.String)` -- javap on
-- projectzomboid.jar 42.20.4 -- and the vanilla display name is kept in front of
-- the exchange rather than replaced, so the item reads the way the player's own
-- language spells it.
--
-- IT ASKS THE SERVER EVERY TIME, and never caches the listings on the item. A
-- region's premises do not move, but the book is generated from the map and the
-- map is the server's; a listing table written into modData would be a second
-- copy of the county, out of date the day a mod added a zone, sitting in every
-- save for ever.
--

CeroSecPhonebookUI = CeroSecPhonebookUI or {}

-- The requests in flight, keyed by the token that went out with each. A token and
-- not the player, because a player may look twice before the first answer lands,
-- and the answer has to open the book that was asked for.
CeroSecPhonebookUI.pending = {}

local counter = 0

local function nextToken()
	counter = counter + 1
	return "pb" .. tostring(counter) .. "-" .. tostring(getTimestampMs())
end

-- Which region a survivor is standing in, or nil for one the world cannot place.
function CeroSecPhonebookUI.regionOf(playerObj)
	if playerObj == nil or playerObj.getX == nil then return nil end
	local x, y = playerObj:getX(), playerObj:getY()
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return CeroSecOS.phoneRegionOf(x, y)
end

-- Put the exchange on the copy's own label, once. The vanilla name in front of
-- it, so "Phonebook" stays whatever the player's language calls it.
function CeroSecPhonebookUI.rename(item, exchange)
	if item == nil or item.setName == nil or item.getName == nil then return end
	if type(exchange) ~= "number" then return end
	item:setName(getText("IGUI_CeroSec_Phonebook_Named", item:getName(),
		tostring(exchange)))
end

-- "Look up numbers": stamp the copy if it has never been opened, then ask.
--
-- A book opened where the world cannot say where the reader is -- and that is a
-- character with no position at all -- is left unstamped and unasked rather than
-- being printed for region 0,0, which is a real place on the map and would be the
-- wrong book for ever.
function CeroSecPhonebookUI.look(item, playerObj)
	if item == nil or playerObj == nil then return nil end
	local data = item.getModData and item:getModData() or nil
	if data == nil then return nil end

	local rx, ry = CeroSecPhonebook.regionOn(data)
	if rx == nil then
		local px, py = CeroSecPhonebookUI.regionOf(playerObj)
		if px == nil then return nil end
		rx, ry = CeroSecPhonebook.stampRegion(data, px, py)
		if rx == nil then return nil end
		CeroSecPhonebookUI.rename(item, CeroSecOS.phoneExchangeOfRegion(rx, ry))
	end

	local token = nextToken()
	CeroSecPhonebookUI.pending[token] = { item = item, playerObj = playerObj }
	CCeroSecSystem.instance:sendCommand(playerObj, "phonebook",
		{ rx = rx, ry = ry, token = token })
	return token
end

-- The listings came back. One answer opens one book, and the request is dropped
-- whatever happened to it: an answer for a token nobody is waiting on is an
-- answer to a look-up that has already been served.
function CeroSecPhonebookUI.onServerAnswer(command, args)
	if command ~= "listings" then return end
	if type(args) ~= "table" or type(args.token) ~= "string" then return end
	local waiting = CeroSecPhonebookUI.pending[args.token]
	if waiting == nil then return end
	CeroSecPhonebookUI.pending[args.token] = nil

	local exchange = args.exchange
	if type(exchange) ~= "number" then return end
	local document = CeroSecPhonebook.volume(exchange, args.entries, args.capped)
	return CeroSecManualUI.open(waiting.playerObj, nil, waiting.item, document)
end
