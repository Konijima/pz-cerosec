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
-- THREE VOLUMES, one shelf. The weights above are volume one's -- the User's
-- Guide, the book everyone who bought a machine got -- and the other two are a
-- SHARE of them rather than two more tables of twelve numbers: a share is the
-- decision, and twelve numbers copied and halved by hand is twelve chances to
-- mistype one. CeroSec Systems printed fewer of each:
--
--   1  User's Guide                    1     in the box with the machine
--   2  System Administrator's Guide    1/2   bought by whoever ran the office
--   3  Programmer's Guide              1/4   bought by the one person writing
--                                            anything for it
--
-- with volume three raised back to a half in the four lists where somebody
-- would actually have been writing code -- the two university lists, the
-- bookshop's computer aisle and the electronics store -- because a programmer's
-- manual is rare everywhere except where the programmers were.
--
-- The shares are halves and quarters on purpose and not a taste: a weight of
-- 0.1 times 0.25 is exactly 0.025 in a double, so none of the twelve times
-- three numbers is a float that nearly is what it says it is.
--
-- CeroSec.Manual -- the single book that shipped before the set -- is NOT in
-- any of this any more. It is still an item, because it is in saves, but the
-- thing a player finds from here on is one of the three volumes.
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

-- Volume one's shares, and the base every other volume's is taken from.
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

-- The set, in the order it is printed. An ordered list and not a map keyed by
-- item: pairs() would append the three volumes to a pool in a different order
-- from one game to the next, and a distribution list whose contents depend on
-- hash order is a list nothing can be asserted about.
CeroSecManualLoot.VOLUMES = {
	{ item = "CeroSec.ManualUser", share = 1 },
	{ item = "CeroSec.ManualAdmin", share = 0.5 },
	{ item = "CeroSec.ManualProgrammer", share = 0.25,
		-- Where the programmers were.
		raised = {
			UniversityLibraryComputer = 0.5,
			UniversityDesk_Computer = 0.5,
			BookstoreComputer = 0.5,
			ElectronicStoreMagazines = 0.5,
		} },
}

-- The sandbox option, if a sandbox option file ever defines one: every weight
-- multiplied, so a server that wants the set common or all but absent moves one
-- number instead of thirty-six.
--
-- Read the way vanilla reads its own grouped options -- `SandboxVars.Map and
-- (SandboxVars.Map.AllowWorldMap == true)`, ISWorldMap.lua:1493 -- because
-- SandboxVars is a plain table and a group nobody declared is simply not in it.
-- Nothing here creates the option; this is the hook it would land in.
--
-- A value that is not a positive number is not an abundance, and it is ignored
-- rather than argued with: a nil, a string, a zero or a negative would each
-- take every book out of the world quietly.
CeroSecManualLoot.SANDBOX = "LootAbundance"

function CeroSecManualLoot.abundance()
	local group = SandboxVars and SandboxVars.CeroSec
	local value = group and group[CeroSecManualLoot.SANDBOX]
	if type(value) ~= "number" or value <= 0 then return 1 end
	return value
end

-- What one volume weighs in one list: its share of volume one's weight, raised
-- where that volume was actually sold, times the abundance.
function CeroSecManualLoot.weightFor(volume, key, abundance)
	local base = CeroSecManualLoot.WEIGHTS[key]
	if not base then return nil end
	local share = (volume.raised and volume.raised[key]) or volume.share
	return base * share * abundance
end

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

function CeroSecManualLoot.addTo(list, key, item, weight)
	local pool = list and list[key]
	-- A list that is not there is a list vanilla renamed or dropped, and it is
	-- add() that says so -- once for the list, not once per volume standing in
	-- front of it.
	if not pool or type(pool.items) ~= "table" then return false end
	if holds(pool.items, item) then return false end
	pool.items[#pool.items + 1] = item
	pool.items[#pool.items + 1] = weight
	return true
end

function CeroSecManualLoot.add()
	if CeroSecManualLoot.added then return 0 end
	if not ProceduralDistributions or not ProceduralDistributions.list then return 0 end

	local list = ProceduralDistributions.list
	local abundance = CeroSecManualLoot.abundance()
	local count = 0
	-- The lists walked by pairs() and the volumes by index: which list is
	-- reached first does not matter, but the order the three volumes go INTO
	-- one is the order they are printed in.
	for key in pairs(CeroSecManualLoot.WEIGHTS) do
		local pool = list[key]
		if not pool or type(pool.items) ~= "table" then
			-- Say so once and carry on: a missing shelf must not take the mod
			-- down with it.
			CeroSec.log("no distribution list named " .. tostring(key))
		else
			for v = 1, #CeroSecManualLoot.VOLUMES do
				local volume = CeroSecManualLoot.VOLUMES[v]
				local weight = CeroSecManualLoot.weightFor(volume, key, abundance)
				if CeroSecManualLoot.addTo(list, key, volume.item, weight) then
					count = count + 1
				end
			end
		end
	end
	CeroSecManualLoot.added = true
	CeroSec.log("the manual set added in " .. count .. " places")
	return count
end

Events.OnPreDistributionMerge.Add(CeroSecManualLoot.add)
