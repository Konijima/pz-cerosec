require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecManualLoot"

--
-- Where the disks are found.
--
-- A box of ten 3.5-inch disks sat beside every machine that had a drive in 1993:
-- on the desk with the computer, in the filing cabinet of the cyber cafe, in the
-- supplies cupboard of an office, on the rack of an electronics shop. So this is
-- NOT the manual's distribution -- a book about a computer lives with the books,
-- and a disk lives with the computers -- and the two lists deliberately share
-- only the places where both are true.
--
-- Each weight is set against what is already IN that list rather than against a
-- feeling, exactly as the manual's are (see CeroSecManualLoot.lua for the shape
-- of a distribution list and why it is extended in place on
-- Events.OnPreDistributionMerge). The comparable is the magazine on the same
-- shelf, because that is the other thing a survivor picks up in these containers
-- and it is what "about as often as a computer magazine" means as a number:
--
--   list                        vanilla weights already there          ours
--   CyberCafeDesk (18398)       Magazine_Tech 10, Magazine_Gaming 10,   10
--                               Battery 10
--   CyberCafeFilingCabinet      Magazine_Tech 20, Magazine_Gaming 20    20
--     (18481)
--   ControlRoomCounter (12552)  Magazine_Tech 10, Pen 8, Battery 10      8
--   UniversityDesk_Computer     Magazine_Tech 50/50/20/20 (140)         20
--     (49663)
--   ElectronicStoreMagazines    Magazine_Tech_New 20/10,                10
--     (20276)                   EngineerMagazine1-2 at 8 each
--   OfficeDesk (36549)          IndexCard 10, Paperwork 20/10,           4
--                               Paperback_Business 2
--   OfficeShelfSupplies (36944) Notebook 20/10, IndexCard 10, Pen 8      8
--   LibraryComputer (30719)     Book_Computer 20/10,                     2
--                               Paperback_Computer 20/20/10/10
--   OfficeDrawers (36758)       IndexCard 10, Magazine_Business 10,      4
--                               BluePen 8
--   CrateComputer (13103)       ElectronicsScrap 10                     10
--   ElectronicStoreComputers    Mov_DesktopComputer 20                  10
--     (20180)
--
-- The last three are shelves the manual is NOT on and that is the point of them:
-- a warehouse crate of computer parts, the drawers of a desk, the computer aisle
-- of an electronics shop. Nobody kept a manual in a crate of scrap, and everybody
-- kept a box of disks beside a machine.
--
-- One list that looks like it belongs here is deliberately left out:
-- UniversityFilingCabinet_Computer, whose `items` vanilla ships EMPTY with a
-- comment saying it is in progress. Putting disks into it would make a disk the
-- only thing a computer department's filing cabinet has ever held, which is a lie
-- told by being the only one in the room.
--
-- So: on the desk of a cyber cafe a disk is as common as the magazine beside it;
-- in a random office desk it is a quarter as common as the index cards, because
-- most desks in Knox County had no computer on them; in the library it is a
-- rarity, because a library lends books and not disks.
--
-- FOUR COLOURS, one box. The weights above are the box's and each colour is a
-- QUARTER of it, which is what a box of ten mixed disks is and what keeps a
-- survivor from finding four blue ones in a row. A quarter of each of the eight
-- numbers above is exact in a double -- every one of them is a multiple of two
-- and the divisor is a power of two -- so none of the thirty-two weights is a
-- float that nearly is what it says it is.
--
-- Every disk found in the world is BLANK: nothing here writes modData, so an
-- item straight off a shelf has none at all and the drive reads it as a disk
-- with no filesystem on it (SCeroSecSystem's Commands.insertfloppy). A survivor
-- formats it himself, which is what `newfs` is for and what the manual's chapter
-- on the drive opens with.
--

CeroSecFloppyLoot = {}

-- What one box is worth in one list.
CeroSecFloppyLoot.WEIGHTS = {
	-- Where a machine with a drive in it stood.
	CyberCafeDesk = 10,
	CyberCafeFilingCabinet = 20,
	ControlRoomCounter = 8,
	UniversityDesk_Computer = 20,
	ElectronicStoreMagazines = 10,
	-- Where somebody who had one put the box down.
	OfficeDesk = 4,
	OfficeDrawers = 4,
	OfficeShelfSupplies = 8,
	LibraryComputer = 2,
	-- And where they were sold and shipped, which is a shelf no book of ours is on.
	CrateComputer = 10,
	ElectronicStoreComputers = 10,
}

-- One quarter of the box each. Written as a constant rather than as
-- 1 / #CeroSec.FLOPPY_TYPES so that adding a fifth colour is a DECISION about
-- how common a disk is and not a quiet twenty per cent cut in it.
CeroSecFloppyLoot.SHARE = 0.25

-- The same sandbox option the manual reads, and the same rule: a value that is
-- not a positive number is not an abundance and is ignored rather than argued
-- with. One number moves all thirty-two weights.
function CeroSecFloppyLoot.abundance()
	local group = SandboxVars and SandboxVars.CeroSec
	local value = group and group[CeroSecManualLoot.SANDBOX]
	if type(value) ~= "number" or value <= 0 then return 1 end
	return value
end

-- What one colour weighs in one list.
function CeroSecFloppyLoot.weightFor(key, abundance)
	local base = CeroSecFloppyLoot.WEIGHTS[key]
	if not base then return nil end
	return base * CeroSecFloppyLoot.SHARE * abundance
end

-- Done once. The event can be fired again -- a Lua reload in a running game does
-- it -- and a second pass would double every weight.
CeroSecFloppyLoot.added = false

function CeroSecFloppyLoot.add()
	if CeroSecFloppyLoot.added then return 0 end
	if not ProceduralDistributions or not ProceduralDistributions.list then return 0 end

	local list = ProceduralDistributions.list
	local abundance = CeroSecFloppyLoot.abundance()
	local count = 0
	-- The lists walked by pairs() and the colours by index: which list is reached
	-- first does not matter, but the order the four colours go INTO one is the
	-- order they are printed in, and a distribution whose contents depend on hash
	-- order is a distribution nothing can be asserted about.
	for key in pairs(CeroSecFloppyLoot.WEIGHTS) do
		local pool = list[key]
		if not pool or type(pool.items) ~= "table" then
			-- Say so once and carry on: a list vanilla renamed must not take the
			-- mod down with it.
			CeroSec.log("no distribution list named " .. tostring(key))
		else
			local weight = CeroSecFloppyLoot.weightFor(key, abundance)
			for i = 1, #CeroSec.FLOPPY_TYPES do
				-- The manual's own insert, reused rather than copied: it is the
				-- one place that knows a pool is a flat array of alternating name
				-- and weight, and that a name already in it is not added twice.
				if CeroSecManualLoot.addTo(list, key, CeroSec.FLOPPY_TYPES[i], weight) then
					count = count + 1
				end
			end
		end
	end
	CeroSecFloppyLoot.added = true
	CeroSec.log("the floppy disks added in " .. count .. " places")
	return count
end

Events.OnPreDistributionMerge.Add(CeroSecFloppyLoot.add)
