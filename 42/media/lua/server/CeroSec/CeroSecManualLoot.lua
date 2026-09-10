require "CeroSec/CeroSecDefs"

--
-- Where the manual is found.
--
-- Computers are new in 1993 and a book about one is a book that lives with the
-- computers: the computer aisle of a library or a bookshop, a cyber cafe, a
-- university computing desk, the magazine rack of an electronics store. It is
-- also, once in a long while, in an office desk or on somebody's shelf at home,
-- because somebody bought one and took it to work.
--
-- The lists are vanilla's own, in
-- media/lua/server/Items/ProceduralDistributions.lua, and each weight below is
-- set against what is already IN that list rather than against a feeling. An
-- items list is a flat array of alternating name and weight, the weight is a
-- share of the list's total and not a percentage, and a fully qualified name
-- works -- vanilla writes "Base.LouisvilleMap1" that way at line 15913, which
-- is what lets a mod's own module be named.
--
--   list                        vanilla weights already there          ours
--   LibraryComputer (30719)     Book_Computer 20/10,                     4
--                               Paperback_Computer 20/20/10/10  (90)
--   UniversityLibraryComputer   Book_Computer 50/20/20/10/10   (110)      4
--     (50526)
--   BookstoreComputer (6192)    Book_Computer 20/10,                     4
--                               Magazine_Tech_New 20/10,
--                               Paperback_Computer 20/20/10/10 (110)
--   CyberCafeFilingCabinet (18481)
--                               Book_Computer 10,                        4
--                               Paperback_Computer 20, Magazine_Tech 20
--   CyberCafeDesk (18398)       Book_Computer 4, Paperback_Computer 8,   3
--                               Magazine_Tech 10
--   ControlRoomCounter (12552)  Book_Computer 4, Paperback_Computer 8,   3
--                               Magazine_Tech 10
--   UniversityDesk_Computer     Book_Computer 50/20,                     4
--     (49663)                   Magazine_Tech 50/50/20/20      (270)
--   ElectronicStoreMagazines    BookElectrician 10/8/6/4/2,              4
--     (20276)                   ElectronicsMag1-5 at 8 each    (~130)
--   OfficeDesk (36549)          Book_Business 1, Paperback_Fiction 1,    1
--                               Paperback_Business 2           (~70)
--   OfficeShelfSupplies (36944) BusinessCard 1, PaperclipBox 1,          1
--                               Twine 1                        (~200)
--   CrateBooks (13029)          Book_Computer 1,                         1
--                               Paperback_Computer 1
--   LivingRoomShelf (31715)     BookElectrician1 0.1,                    0.1
--                               BookElectrician2 0.05
--
-- So: in the computer section of a library it is about one pick in twenty-odd,
-- which over four rolls a shelf is a book a player who goes looking for it
-- finds; in a random office desk it is the rarity of a business paperback; on
-- somebody's living room shelf it is the rarity of an electrician's manual,
-- which is to say a small surprise. Rare, and findable.
--
-- The insertion is done on Events.OnPreDistributionMerge, the first of the
-- three distribution events the game fires (SuburbsDistributions.lua:208-210):
-- by then every Lua file is loaded, so ProceduralDistributions.list is there
-- whatever order the mods came in, and nothing has been rolled yet.
--
-- Note the two tables are NOT the same thing. `Distributions` is the room and
-- container map and it is what mergeDistributions merges
-- (SuburbsDistributions.lua:136-149); `ProceduralDistributions.list` is the
-- item pools and nothing merges it at all -- the Java side reads it as it
-- stands. So a pool is extended by appending to it, in place, and that is what
-- this does.
--

CeroSecManualLoot = {}

CeroSecManualLoot.ITEM = "CeroSec.Manual"

CeroSecManualLoot.WEIGHTS = {
	-- Where a computer book belongs.
	LibraryComputer = 4,
	UniversityLibraryComputer = 4,
	BookstoreComputer = 4,
	CyberCafeFilingCabinet = 4,
	CyberCafeDesk = 3,
	ControlRoomCounter = 3,
	UniversityDesk_Computer = 4,
	ElectronicStoreMagazines = 4,
	-- Where somebody who bought one put it down.
	OfficeDesk = 1,
	OfficeShelfSupplies = 1,
	CrateBooks = 1,
	LivingRoomShelf = 0.1,
}

-- Done once. The event can be fired again -- a Lua reload in a running game
-- does it -- and a second pass would double every weight.
CeroSecManualLoot.added = false

-- Is the item already somewhere in this pool? Names sit at the odd indices and
-- weights at the even ones, so only the odd ones are looked at: a weight that
-- happened to equal a name is not a thing, but a list whose length is odd
-- because somebody dropped a comma would otherwise read a weight as a name.
local function holds(items, name)
	local i = 1
	while i <= #items do
		if items[i] == name then return true end
		i = i + 2
	end
	return false
end

function CeroSecManualLoot.addTo(list, key, weight)
	local pool = list and list[key]
	if not pool or type(pool.items) ~= "table" then
		-- A list that is not there is a list vanilla renamed or dropped. Say so
		-- once and carry on: a missing shelf must not take the mod down with it.
		CeroSec.log("no distribution list named " .. tostring(key))
		return false
	end
	if holds(pool.items, CeroSecManualLoot.ITEM) then return false end
	pool.items[#pool.items + 1] = CeroSecManualLoot.ITEM
	pool.items[#pool.items + 1] = weight
	return true
end

function CeroSecManualLoot.add()
	if CeroSecManualLoot.added then return 0 end
	if not ProceduralDistributions or not ProceduralDistributions.list then return 0 end

	local count = 0
	for key, weight in pairs(CeroSecManualLoot.WEIGHTS) do
		if CeroSecManualLoot.addTo(ProceduralDistributions.list, key, weight) then
			count = count + 1
		end
	end
	CeroSecManualLoot.added = true
	CeroSec.log("manual added to " .. count .. " distribution lists")
	return count
end

Events.OnPreDistributionMerge.Add(CeroSecManualLoot.add)
