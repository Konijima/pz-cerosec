require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecModules"
require "CeroSec/CeroSecManualLoot"

--
-- Where the hardware modules are found.
--
-- A strike, a relay, a contact and a door operator are trade stock: they were
-- sold in the electrical aisle of a hardware store, they were on the shelf of an
-- electronics shop, they rode around in the back of an electrician's van, and a
-- few of each ended up in the crate at the back of a warehouse and in the tool
-- cabinet of a garage that did its own gates. So this is a third list again, and
-- it deliberately shares almost nothing with the manual's (books) or the disks'
-- (desks where a computer stood): nobody kept a door operator on a desk.
--
-- Each base weight is set against what is already IN that list, the way the
-- manual's and the disks' are, and the comparable is named:
--
--   list                   vanilla weights already there            ours
--   ElectricianTools       ElectronicsScrap 20, ElectricWire 10,      8
--                          MotionSensor 8
--   ElectronicStoreMisc    HomeAlarm 20/10, Remote 20/10            10
--   ElectronicStoreLights  LightBulbBox 20/10, the coloured bulbs 8   4
--   CrateElectronics       ElectronicsScrap 20/10, ElectricWire      10
--                          20/10, Remote 4
--   ToolStoreTools         Screwdriver 10                             6
--   ToolCabinetMechanics   Screwdriver 10, ElectricWire 10,           6
--                          ScrewsBox 8
--   GarageTools            Screwdriver 10                             4
--   GarageMechanics        Screwdriver 6, ElectricWire 8,             4
--                          LightBulb 8
--   CrateTools             Screwdriver 6, ScrewsBox 2                 4
--
-- So: in an electrician's van and a warehouse crate of electronics a module is
-- about as common as the scrap and the wire beside it; on a shop shelf as common
-- as an alarm or a remote; in a garage half that, because most garages did their
-- own wiring and none of them did their own door hardware.
--
-- There is NO hardware store list and no shed list in Build 42 -- not one key of
-- ProceduralDistributions.lua contains "Hardware" or "Shed"
-- (docs/notes/modules-proofs.md, 9). The hardware store's shelves in this game
-- are the ToolStore and Electrician ones and a tool shed's are the Crate and
-- Garage ones, which is what the nine above are.
--
-- FOUR DIFFERENT THINGS, one box. Unlike the disks -- four colours of one disk,
-- a quarter each -- these four are not worth the same: a contact is two reed
-- switches, an operator is a motor. So the base above is what the whole box is
-- worth in that list and each module takes its own share of it, and the four
-- shares are powers of two so that every one of the thirty-six weights is exact
-- in a double rather than nearly what it says it is.
--

CeroSecModuleLoot = {}

-- What one box is worth in one list.
CeroSecModuleLoot.WEIGHTS = {
	-- The trade.
	ElectricianTools = 8,
	ElectronicStoreMisc = 10,
	ElectronicStoreLights = 4,
	CrateElectronics = 10,
	-- The hardware store, which is what this game calls a tool shop.
	ToolStoreTools = 6,
	ToolCabinetMechanics = 6,
	-- The garage and the shed, which is what this game calls a crate of tools.
	GarageTools = 4,
	GarageMechanics = 4,
	CrateTools = 4,
}

-- Each module's share of the box. Halves all the way down: a contact is the
-- everyday one, a relay is the next, a strike is a door fitting and an operator
-- is the thing one building in sixteen ever had.
--
-- AND THE FOUR THE MOTOR RUNG ADDED, on the same halving scale and placed by how
-- many buildings in Knox County really had one fitted before the outbreak:
--
--   a contactor on an oven or a washer is the commonest thing on this list
--   after a contact -- every laundrette, every restaurant kitchen and every
--   shop with a coffee machine on a timer had one, so it takes the relay's
--   share
--   a curtain motor is a shop window and an office blind, which is fewer
--   buildings than have a light on a timer -- the strike's share
--   a generator switch is a hospital, a radio station and a handful of shops
--   that could not go dark, and a window operator is a high-level opener in an
--   atrium: neither is a thing a street of houses had, so both sit beside the
--   door operator
--
-- Every one of them is a power of two, which is what makes all sixty-three of
-- these weights exact in a double rather than nearly what they say.
CeroSecModuleLoot.SHARES = {
	contact = 0.5,
	relay = 0.25,
	strike = 0.125,
	operator = 0.0625,
	appliance = 0.25,
	curtain = 0.125,
	window = 0.0625,
	genset = 0.0625,
}

-- AND THE PART THEY ARE BUILT FROM, which is not a module and is on the same
-- shelves.
--
-- A small motor is the one input none of these recipes can make and the game
-- ships no item for (items_cerosec.txt, item SmallMotor). The road to one is a
-- screwdriver and a hair dryer, which is a road through a bathroom and not
-- through a shop; this is the other road, and it is deliberately the thinner of
-- the two.
--
-- Half the rarest module's share, which is the next power of two down and keeps
-- every one of these weights exact in a double. The shelves held finished
-- stock -- that is what a shelf is -- and a loose motor in a crate is something
-- that fell off a bench, so it is rarer than the operator it goes into. A
-- survivor who wants one takes the back off an appliance.
CeroSecModuleLoot.MOTOR = "CeroSec.SmallMotor"
CeroSecModuleLoot.MOTOR_SHARE = 0.03125

-- The same sandbox option the manual and the disks read, and the same rule: a
-- value that is not a positive number is not an abundance and is ignored rather
-- than argued with.
function CeroSecModuleLoot.abundance()
	local group = SandboxVars and SandboxVars.CeroSec
	local value = group and group[CeroSecManualLoot.SANDBOX]
	if type(value) ~= "number" or value <= 0 then return 1 end
	return value
end

-- What one module weighs in one list.
function CeroSecModuleLoot.weightFor(key, id, abundance)
	local base = CeroSecModuleLoot.WEIGHTS[key]
	local share = CeroSecModuleLoot.SHARES[id]
	if not base or not share then return nil end
	return base * share * abundance
end

-- Done once. The event can be fired again -- a Lua reload in a running game does
-- it -- and a second pass would double every weight.
CeroSecModuleLoot.added = false

function CeroSecModuleLoot.add()
	if CeroSecModuleLoot.added then return 0 end
	if not ProceduralDistributions or not ProceduralDistributions.list then return 0 end

	local list = ProceduralDistributions.list
	local abundance = CeroSecModuleLoot.abundance()
	local count = 0
	-- The lists walked by pairs() and the modules by index: which list is reached
	-- first does not matter, and the order the four go INTO one is the order they
	-- are printed in -- a distribution whose contents depend on hash order is a
	-- distribution nothing can be asserted about.
	for key in pairs(CeroSecModuleLoot.WEIGHTS) do
		local pool = list[key]
		if not pool or type(pool.items) ~= "table" then
			-- Say so once and carry on: a list vanilla renamed must not take the
			-- mod down with it.
			CeroSec.log("no distribution list named " .. tostring(key))
		else
			for i = 1, #CeroSecModules.LIST do
				local module = CeroSecModules.LIST[i]
				local weight = CeroSecModuleLoot.weightFor(key, module.id, abundance)
				-- The manual's own insert, reused rather than copied: it is the one
				-- place that knows a pool is a flat array of alternating name and
				-- weight, and that a name already in it is not added twice.
				if CeroSecManualLoot.addTo(list, key, module.item, weight) then
					count = count + 1
				end
			end
			-- The motor goes on LAST, after the four boxes, so the order one list
			-- is filled in stays the order a reader can check: the modules in
			-- CeroSecModules.LIST's own order and then the part.
			if CeroSecManualLoot.addTo(list, key, CeroSecModuleLoot.MOTOR,
					CeroSecModuleLoot.WEIGHTS[key] * CeroSecModuleLoot.MOTOR_SHARE
						* abundance) then
				count = count + 1
			end
		end
	end
	CeroSecModuleLoot.added = true
	CeroSec.log("the hardware modules added in " .. count .. " places")
	return count
end

Events.OnPreDistributionMerge.Add(CeroSecModuleLoot.add)
