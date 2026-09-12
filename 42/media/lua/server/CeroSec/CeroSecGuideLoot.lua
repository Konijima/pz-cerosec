require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecManualLoot"

--
-- Where the Field Wiring Guide is found.
--
-- This is the fourth of the mod's loot tables and it is the easiest of the four
-- to reason about, because it is not a judgement at all: the guide is an
-- electronics magazine, the game already has five electronics magazines, and
-- the question "where does an electronics magazine go and how common is it
-- there" is one vanilla has already answered five times over. So this table
-- does not set a weight against what is beside it the way the manual's, the
-- disks' and the modules' do. It COPIES the family, shelf for shelf and number
-- for number.
--
-- The family is Base.ElectronicsMag1 to ElectronicsMag5
-- (media/scripts/generated/items/literature.txt:5307-5378), and these are the
-- lists in media/lua/server/Items/ProceduralDistributions.lua that hold all
-- five of them at one weight:
--
--   list                        vanilla weight, all five        ours
--   ElectronicStoreMagazines      8                               8
--   BookstoreMisc                 2                               2
--   BookstoreBlueCollar           2                               2
--   ToolStoreBooks                2                               2
--   ElectricianTools              2                               2
--   MagazineRackMixed             1                               1
--   PostOfficeMagazines           1                               1
--   CrateMagazines                1                               1
--   LibraryMagazines              1                               1
--
-- So: the magazine rack of an electronics shop is where it was sold and it is
-- four times likelier there than anywhere else; a bookshop, a tool shop and an
-- electrician's own van are next; and a mixed rack, a post office's mail, a
-- warehouse crate of magazines and a library are the long tail. A player who
-- goes looking for it in the right shop finds it; a player who does not, finds
-- it eventually, somewhere, the way one finds a magazine.
--
-- The family sits in more lists than these nine -- the living room shelves and
-- the side tables at 0.1, the drug lab and the child's bedroom, a school locker
-- -- and the guide is in NONE of them. Those are the lists where vanilla put a
-- magazine because somebody had left one lying about, and a trade handbook
-- CeroSec Systems printed for the fitters who installed their hardware is not
-- something a child had in a wardrobe. Nine lists, all of them a place the
-- thing was actually sold or shipped.
--
-- ONE item, so there is no share table here and nothing to keep exact in a
-- double: the weight in the table below is the weight that goes into the list.
--
-- Everything mechanical is the manual's and is reused rather than copied --
-- addTo (a pool is a flat array of alternating name and weight, and a name
-- already in it is not added twice), the LootAbundance sandbox option read the
-- same way, and Events.OnPreDistributionMerge, the first of the three
-- distribution events the game fires, by which point every Lua file is loaded
-- and nothing has been rolled.
--

CeroSecGuideLoot = {}

CeroSecGuideLoot.ITEM = "CeroSec.WiringGuide"

-- Vanilla's own numbers for the electronics magazine family, unchanged.
CeroSecGuideLoot.WEIGHTS = {
	-- Where it was sold.
	ElectronicStoreMagazines = 8,
	BookstoreMisc = 2,
	BookstoreBlueCollar = 2,
	ToolStoreBooks = 2,
	-- Where a fitter kept his copy.
	ElectricianTools = 2,
	-- The long tail: a rack, the mail, a crate, a library.
	MagazineRackMixed = 1,
	PostOfficeMagazines = 1,
	CrateMagazines = 1,
	LibraryMagazines = 1,
}

-- The same sandbox option the other three tables read, read the same way: a
-- value that is not a positive number is not an abundance and is ignored rather
-- than argued with.
function CeroSecGuideLoot.abundance()
	local group = SandboxVars and SandboxVars.CeroSec
	local value = group and group[CeroSecManualLoot.SANDBOX]
	if type(value) ~= "number" or value <= 0 then return 1 end
	return value
end

-- What the guide weighs in one list.
function CeroSecGuideLoot.weightFor(key, abundance)
	local base = CeroSecGuideLoot.WEIGHTS[key]
	if not base then return nil end
	return base * abundance
end

-- Done once. The event can be fired again -- a Lua reload in a running game does
-- it -- and a second pass would double every weight.
CeroSecGuideLoot.added = false

function CeroSecGuideLoot.add()
	if CeroSecGuideLoot.added then return 0 end
	if not ProceduralDistributions or not ProceduralDistributions.list then return 0 end

	local list = ProceduralDistributions.list
	local abundance = CeroSecGuideLoot.abundance()
	local count = 0
	for key in pairs(CeroSecGuideLoot.WEIGHTS) do
		local pool = list[key]
		if not pool or type(pool.items) ~= "table" then
			-- Say so once and carry on: a list vanilla renamed must not take the
			-- mod down with it.
			CeroSec.log("no distribution list named " .. tostring(key))
		else
			local weight = CeroSecGuideLoot.weightFor(key, abundance)
			if CeroSecManualLoot.addTo(list, key, CeroSecGuideLoot.ITEM, weight) then
				count = count + 1
			end
		end
	end
	CeroSecGuideLoot.added = true
	CeroSec.log("the wiring guide added in " .. count .. " places")
	return count
end

Events.OnPreDistributionMerge.Add(CeroSecGuideLoot.add)
