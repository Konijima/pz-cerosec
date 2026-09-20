require "CeroSec/CeroSecDefs"

--
-- The hardware modules
--
-- A computer does not talk to a door because the door is a door. It talks to it
-- because somebody climbed up with a screwdriver and wired a box to it. Eight
-- boxes, and each one buys exactly one thing:
--
--   contact   a magnetic contact   -> the machine can SEE a door or a window
--   relay     a relay              -> the machine can throw a light switch
--   strike    an electric strike   -> the machine can work a door's lock
--   operator  a door operator      -> the machine can open and shut a door
--   curtain   a curtain motor      -> it can draw and open a curtain
--   window    a window operator    -> it can raise and shut a sash
--   appliance an appliance switch  -> it can start a stove or a washer
--   genset    a generator switch   -> it can start and stop a generator
--   tuner     a tuner control      -> it can switch a television or a radio set
--                                     on and off and move its dial
--
-- Nothing else changed about /dev: a device that is there is the same device it
-- always was, with the same words and the same refusals. What the modules decide
-- is WHICH devices are there at all (SCeroSecDevices.classify), and that is the
-- whole of the feature.
--
-- The sandbox option is the switch, and it is ON by default: a world where every
-- door in Knox County answers a computer nobody wired is the world this rung was
-- asked to stop being the only one on offer. A server owner who liked that world
-- turns CeroSec.HardwareRequired off and gets it back, untouched, down to the
-- device numbers.
--
-- Where the modules live
--
-- On the OBJECT, in its own modData, under this mod's own name:
--
--   door:getModData().cerosec = { strike = true, contact = true }
--
-- and nowhere else. Not in the machine's state -- a computer carried out of the
-- building must not take the building's wiring with it -- and not in a book on
-- the side, which would be a second truth to keep in step with the world.
--
-- IsoObject modData is saved with the chunk and travels to the other players on
-- transmitModData(); both are proved at the bytecode in
-- docs/notes/modules-proofs.md, and the second one has a server branch of its
-- own (GameServer.sendObjectModData), which matters here because our writes
-- happen on the server and most of vanilla's happen on a client.
--
-- A player-built door is an IsoThumpable, which keeps a modData field of its OWN
-- rather than the one it inherits -- and saves it itself, under its own flag
-- bit. So the same line of Lua works on both and survives a save on both; the
-- difference is invisible from here and is written down in the proofs.
--
-- Why this file is shared
--
-- Two sides ask the same questions of the same object. The server asks them to
-- decide what is under /dev and to carry an install out; the client asks them to
-- decide what to put on a right-click menu and why an entry is greyed. A rule
-- written twice is a rule that drifts, so it is written here once, and the only
-- thing either side adds is what it does with the answer.
--

CeroSecModules = CeroSecModules or {}

-- The key the modules hang on, inside the object's own modData. The mod's name,
-- lower case, like everything else this mod writes into somebody else's table.
CeroSecModules.DATA_KEY = "cerosec"

--
-- The shape of that table, and how it is changed
--
-- A door is a save file too. What is screwed to it is written into the CHUNK and
-- comes back when the chunk does, so the ids in there are as persistent as the
-- machine's filesystem and are owed the same promise: a change that renames one, or
-- drops one, or changes what one MEANS does not cost a survivor the hardware he
-- climbed up to fit.
--
-- So the table carries a version, and a chain beside it:
-- CeroSecModules.MIGRATIONS[n] takes the table at n - 1 and leaves it at n.
--
-- A table with NO version is version 1, not version 0, and that is not a guess: the
-- ids in a table written before this change are the ids version 1 has, so an absent
-- number reads as the shape it really is.
--
-- WHERE THE NUMBER GETS WRITTEN, corrected 2026-09-14. This used to say the stamp
-- goes on at the next WRITE (setOn) and never on a read. That was true only because
-- VERSION was 1 and the walk in `migrate` therefore had no iteration to make: the
-- walk has always ended each step with `fitted[VERSION_KEY] = n`, so the moment
-- VERSION moved to 2 the first READ of an older table became the thing that stamps
-- it -- on a client as well as on the server. That is harmless in both places and is
-- left as it is: on a client the write lands in a table nobody else will ever see,
-- and on the server it lands in the chunk, which is where the answer belongs. What
-- would NOT be harmless is a step that did real work being run twice, and the stamp
-- is exactly what stops that.
--
-- VERSION 2 as of the change that added the `pre` key below. Strictly it did not have
-- to move -- an absent mark reads as "not pre-fitted", which is the old behaviour on
-- every fixture in every save, and the step below therefore has nothing to convert.
-- It moves anyway, and the reason is a reader and not the code: this table now has a
-- key in it that is not one of the four ids and does not behave like one, and a shape
-- that changed without its number moving is a shape nothing can be held to afterwards.
-- The cost of moving it is one write of one number into a table that was going to be
-- read anyway.
--
-- AND IT DID NOT MOVE FOR THE MOTOR RUNG'S FOUR IDS, which is worth writing down
-- because the rule above says a shape change moves it and four new keys look
-- like one.
--
-- They are not. A key whose absence reads as the OLD BEHAVIOUR is not a shape
-- change, and an absent `curtain` reads as "no curtain motor on this fixture",
-- which is true of every fixture in every save written before this rung --
-- nobody had one to fit. There is nothing for a step to convert, and a step that
-- converted nothing would be a number moved to say something that did not
-- happen.
--
-- It is the `pre` key read the other way round. That one moved the number
-- although it had nothing to convert either, and the reason was a reader: `pre`
-- is a key in this table that is NOT one of the ids and does not behave like
-- one. These four are ids and behave exactly like the four beside them, so
-- there is nothing for a reader to be surprised by and nothing to hold the
-- shape to.
--
-- AND IT DID NOT MOVE FOR `tuner` EITHER, for that same sentence a ninth time.
-- An absent `tuner` reads as "no tuner control on this fixture", which is true of
-- every television and every radio set in every save written before the rung that
-- added it -- nobody had one to fit. A step converting nothing is a number moved
-- to say something that did not happen.
--
-- VERSION 3 as of the LINK key below, and it moves for `pre`'s reason read a
-- second time rather than for the four ids' reason read a tenth. An absent link
-- list reads as "no cable runs to this fixture", which is true of every fixture in
-- every save written before it, so there is nothing for a step to convert -- but
-- `link` is a key in this table that is not one of the ids and does not behave
-- like one: it is a LIST and not a boolean, and a shape that has grown a list
-- without its number moving is a shape nothing can be held to afterwards. The cost
-- is one write of one number into a table that was going to be read anyway.
CeroSecModules.VERSION = 3
CeroSecModules.VERSION_KEY = "v"
-- MIGRATIONS[n] takes the table at n - 1 and leaves it at n.
--
-- [2] has nothing to do and says so out loud rather than being absent: a gap in the
-- chain is what `migrate` refuses to walk (it answers false and the fixture reads as
-- bare), so "no conversion needed" has to be written as a step that converts nothing.
-- What version 1 lacked is the `pre` mark, and the absence of it is already the right
-- answer for every fixture written before this change -- none of them was fitted by
-- anybody but a player.
--
-- [3] has nothing to do either, for the same sentence: what version 2 lacked is the
-- link list, and a fixture written before it is a fixture nobody had run a cable to.
CeroSecModules.MIGRATIONS = {}
CeroSecModules.MIGRATIONS[2] = function(_fitted) end
CeroSecModules.MIGRATIONS[3] = function(_fitted) end
CeroSecModules.OLDEST_VERSION = 1

-- AND ONE KEY THAT IS NOT A MODULE: was this fixture wired before the outbreak?
--
-- The automation needs to fit a building's hardware ONCE and never again, and
-- "once" cannot be "when the modules are not there": a survivor who unscrews the
-- relay out of a light switch for the item would find it back on the plate the next
-- minute, which is a mod undoing a player's own work. So a pre-fitted fixture
-- remembers that it was pre-fitted, the mark outlives every module coming off, and
-- the walk never touches that fixture again.
--
-- It costs a handful of bytes in the chunk for the rest of the save on a fixture a
-- survivor has stripped bare, and that is the price of the promise. The last module
-- off takes the table with it exactly as before on every fixture a PLAYER wired: the
-- mark is the only thing that keeps one alive (setOn).
--
-- ADDING THIS KEY IS NOT A SHAPE CHANGE and CeroSecModules.VERSION does not move
-- for it. An absent mark reads as "not pre-fitted", which is the old behaviour
-- everywhere, and there is nothing in an older table for a step to convert. Bumping
-- the number would be worse than useless here: `migrate` stamps the new number on
-- the table it walks, and a table is walked on every READ -- including on a client,
-- where a write into a door's modData goes nowhere anybody will ever see.
CeroSecModules.PRE_KEY = "pre"

--
-- AND ONE MORE THAT IS NOT A MODULE EITHER: the cables run to this fixture
--
-- A fixture in the machine's own building is on its /dev for nothing, because the
-- building was wired before the outbreak and the walls it is wired through are
-- still standing. Everything else -- a lamppost on the street, a porch lamp on a
-- wall the room walk does not reach, a gate at the end of the drive, a shop across
-- the car park -- is reached the way an electrician would reach it: he runs a
-- cable to it.
--
-- So a LINK is one entry in this list, and it names a MACHINE by where the machine
-- STANDS:
--
--   door:getModData().cerosec.link = { { x = 1024, y = 998, z = 0, wire = 12 } }
--
-- By the position and never by the hostname, which is a file its own root may
-- write to anything (/etc/hostname): a cable is a fact about two places, and a
-- machine renamed on Tuesday is the same machine at the same desk. The menu SHOWS
-- the hostname, because that is what a survivor calls it.
--
-- `wire` is what the run cost, kept on the entry rather than worked out again from
-- the two positions, for one reason: it is what comes BACK. An unlink hands the
-- player that many cables and so does a sledgehammer through the fixture
-- (SCeroSecFixtures), and a refund that recomputed the distance would pay a
-- different number the day the arithmetic moved -- or pay nothing at all for a
-- machine somebody has since picked up.
--
-- It is written on BOTH sides: here, so the fixture knows which machines to
-- answer, and in the machine's own state (os.links), so the discovery knows which
-- squares to visit without walking the county. Either side alone would be a walk
-- of every fixture in Knox County or a walk of every machine in it; the pair is
-- what makes `find` visit exactly the squares somebody paid for. They are kept in
-- step by the one thing that can: each side drops what the other no longer
-- carries, on the next walk (see SCeroSecDevices' link walk).
CeroSecModules.LINK_KEY = "link"

-- How many machines one fixture may answer. Four, which is a terminal block with
-- four pairs on it: a shared door between two premises is the case this exists
-- for, and a fixture wired to thirty machines is a fixture whose modData is a
-- table somebody is filling up for fun.
CeroSecModules.LINKS_MAX = 4

-- How far a cable goes, in tiles, and it is the WHOLE number paid for: thirty.
-- Past that the answer is another computer for that part of the building, worked
-- from the first one down the coax or over the telephone -- which is a machine a
-- survivor has to find and put on a desk, and is the reason there is a limit at
-- all.
CeroSecModules.LINK_RANGE = 30

-- Tiles around a machine with no room of its own, on its own floor -- the same
-- ten SCeroSecDevices.lua's building walk falls back to when the machine has no
-- building (CeroSecDevices.RADIUS, SCeroSecDevices.lua:~184). A second copy and
-- not a shared read of that one: this file is shared and that one is
-- server-only, so a pure dedicated client, greying the cable menu's rows
-- through reachRefusal below, never loads it at all. The two move together by
-- hand; change one, change the other.
CeroSecModules.OUTDOOR_RADIUS = 10

-- What a floor costs. A cable does not go through a slab where it likes: it goes
-- up the inside of a wall, through the joists and along the ceiling of the room
-- below, which is about four tiles of cable for one storey -- a storey being some
-- ten feet and a tile some two and a half. Whole tiles, so the sum stays whole.
CeroSecModules.LINK_FLOOR_TILES = 4

-- The timed action, in the game's own ticks: per TILE, capped, before the perk
-- takes its bite out of it the way the fitting action's does
-- (ISCeroSecLinkAction). Twelve a tile makes the shortest run about a sixth of
-- fitting a contact and the cap three times it: paying out a reel is a walk, and
-- the walk is what the cap is about -- nobody stands still for thirty tiles of it.
CeroSecModules.LINK_TIME = 12
CeroSecModules.LINK_TIME_MAX = 240

-- The smallest whole number of tiles that covers a flat distance, and it is worked
-- out WITHOUT math.sqrt: the smallest n whose square covers dx*dx + dy*dy.
--
-- Not an optimisation. A cable is paid for in whole cables, so the answer is a
-- whole number either way -- and a whole number worked out by integer arithmetic
-- is the same whole number on Kahlua as on lua5.1, where a float that lands a
-- millionth under 12 would be eleven cables on one VM and twelve on the other.
-- Nothing in this mod had ever asked for math.sqrt, and this is not the place to
-- start (docs/CONTRIBUTING.md, Kahlua purity).
--
-- The loop is bounded by the range, because nothing past it is ever paid for: a
-- fixture further away answers LINK_RANGE + 1, which is the refusal and not a
-- price.
local function ceilSqrt(square)
	local n = 0
	while n * n < square do
		n = n + 1
		if n > CeroSecModules.LINK_RANGE then return n end
	end
	return n
end

-- How far apart two squares are on the floor, in whole tiles, and it is the number
-- the menu SHOWS: "twelve tiles" is what a survivor paces out, while what he pays
-- has the storeys in it as well (linkWire).
function CeroSecModules.linkTiles(fx, fy, mx, my)
	local dx, dy = fx - mx, fy - my
	return ceilSqrt(dx * dx + dy * dy)
end

-- What a cable from a fixture to a machine costs, in whole tiles of
-- Base.ElectricWire. Euclidean on x and y -- a cable is run across a floor and not
-- around the corners of it -- plus LINK_FLOOR_TILES a floor, and never less than
-- one: a machine on the very square the fixture stands on is still a cable.
--
-- ceil(a + k) is ceil(a) + k for a whole k, so adding the floors after the
-- rounding is the same number as adding them before it, and this way nothing is
-- ever a float.
function CeroSecModules.linkWire(fx, fy, fz, mx, my, mz)
	local dz = fz - mz
	if dz < 0 then dz = -dz end
	local wire = CeroSecModules.linkTiles(fx, fy, mx, my)
		+ dz * CeroSecModules.LINK_FLOOR_TILES
	if wire < 1 then return 1 end
	return wire
end

-- Is that entry one this build wrote? The three positions are whole numbers and
-- the wire is a whole number of tiles inside the range -- which is the same bound
-- the cost is held to, so a forged entry cannot be a refund of a thousand cables.
-- An entry that is not one is not READ, which is a cable that was never run.
local function linkOk(entry)
	if type(entry) ~= "table" then return false end
	local x, y, z, wire = entry.x, entry.y, entry.z, entry.wire
	if type(x) ~= "number" or x ~= math.floor(x) then return false end
	if type(y) ~= "number" or y ~= math.floor(y) then return false end
	if type(z) ~= "number" or z ~= math.floor(z) then return false end
	if type(wire) ~= "number" or wire ~= math.floor(wire) then return false end
	if wire < 1 or wire > CeroSecModules.LINK_RANGE then return false end
	return true
end

-- Every cable run to this fixture, as a list of copies: { x, y, z, wire }.
--
-- Always a list, never nil, and never the table the game holds: a caller that
-- wants to change one calls linkOn or unlinkOn, which are the two writers. Read
-- through installedOn's own gate -- the migration chain and a table a LATER build
-- wrote -- so a fixture whose modules this build will not read has no cables
-- either, which is the same answer to the same question.
function CeroSecModules.ownLinksOn(object)
	local out = {}
	if object == nil then return out end
	if type(object.hasModData) ~= "function" or not object:hasModData() then return out end
	local data = object:getModData()
	if data == nil then return out end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then return out end
	if not CeroSecModules.migrate(fitted) then return out end
	local links = fitted[CeroSecModules.LINK_KEY]
	if type(links) ~= "table" then return out end
	for i = 1, #links do
		local entry = links[i]
		if linkOk(entry) and #out < CeroSecModules.LINKS_MAX then
			out[#out + 1] = { x = entry.x, y = entry.y, z = entry.z, wire = entry.wire }
		end
	end
	return out
end

-- Every cable run to this fixture AS A WHOLE: the ones on the object itself and,
-- for a leaf of a double or a garage door, the ones on its other leaves
-- (CeroSecModules.gateParts), each machine once. A cable is run to the opening and
-- goes on the anchor leaf (linkOn), but a world may hold one on another leaf from
-- before a gate was one device, and it is still a cable to this gate.
function CeroSecModules.linksOn(object)
	local out = CeroSecModules.ownLinksOn(object)
	local parts = CeroSecModules.gateParts(object)
	if parts == nil then return out end
	for i = 1, #parts do
		if parts[i] ~= object then
			local more = CeroSecModules.ownLinksOn(parts[i])
			for j = 1, #more do
				local e = more[j]
				if CeroSecModules.linkIndexOf(out, e.x, e.y, e.z) == nil
					and #out < CeroSecModules.LINKS_MAX then
					out[#out + 1] = e
				end
			end
		end
	end
	return out
end

-- Which entry of that list names the machine at x, y, z, or nil.
function CeroSecModules.linkIndexOf(links, x, y, z)
	if type(links) ~= "table" then return nil end
	for i = 1, #links do
		local entry = links[i]
		if type(entry) == "table" and entry.x == x and entry.y == y and entry.z == z then
			return i
		end
	end
	return nil
end

-- What this fixture's cable to that machine cost, or nil when there is none.
function CeroSecModules.wireOf(object, x, y, z)
	local links = CeroSecModules.linksOn(object)
	local at = CeroSecModules.linkIndexOf(links, x, y, z)
	if at == nil then return nil end
	return links[at].wire
end

-- The list, written back and broadcast. The server's, like every other write into
-- a fixture's modData (transmitModData, the proofs, 2).
--
-- An EMPTY list takes itself off the table rather than sitting there as an empty
-- one, and the table goes with it if nothing else is left -- the same rule the last
-- module off obeys, and for the same reason: IsoObject.save skips a modData table
-- that is empty altogether and a table holding one empty list is not empty.
local function writeLinks(object, links)
	local data = object:getModData()
	if data == nil then return false end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then
		if #links == 0 then return true end
		fitted = {}
		data[CeroSecModules.DATA_KEY] = fitted
	end
	if #links == 0 then
		fitted[CeroSecModules.LINK_KEY] = nil
		if CeroSecModules.isBare(fitted) then data[CeroSecModules.DATA_KEY] = nil end
	else
		fitted[CeroSecModules.LINK_KEY] = links
		fitted[CeroSecModules.VERSION_KEY] = CeroSecModules.VERSION
	end
	object:transmitModData()
	return true
end

-- Run one. true, or false and the reason in one word.
--
-- On the anchor leaf when the fixture is a gate (gateParts), and counted against
-- the whole gate's cables: one opening has one cable budget.
function CeroSecModules.linkOn(object, x, y, z, wire)
	if object == nil then return false, "fixture" end
	local links = CeroSecModules.linksOn(object)
	if CeroSecModules.linkIndexOf(links, x, y, z) ~= nil then return false, "linked" end
	if #links >= CeroSecModules.LINKS_MAX then return false, "links" end
	if type(wire) ~= "number" or wire < 1 or wire > CeroSecModules.LINK_RANGE then
		return false, "far"
	end
	local parts = CeroSecModules.gateParts(object)
	local holder = parts and parts[1] or object
	local own = CeroSecModules.ownLinksOn(holder)
	own[#own + 1] = { x = x, y = y, z = z, wire = math.floor(wire) }
	if not writeLinks(holder, own) then return false, "fixture" end
	return true
end

-- Take one off, from whichever leaf holds it. The wire that comes back, or nil when
-- there was no cable.
function CeroSecModules.unlinkOn(object, x, y, z)
	if object == nil then return nil end
	local holders = CeroSecModules.gateParts(object) or { object }
	local wire = nil
	for i = 1, #holders do
		local own = CeroSecModules.ownLinksOn(holders[i])
		local at = CeroSecModules.linkIndexOf(own, x, y, z)
		if at ~= nil then
			local w = own[at].wire
			table.remove(own, at)
			-- The SUM: a legacy gate can carry the same cable on two leaves, each
			-- paid for, and one cut hands back every tile that was bought.
			if writeLinks(holders[i], own) then wire = (wire or 0) + w end
		end
	end
	return wire
end

-- What every cable from this fixture to that machine cost, summed over the leaves of
-- a gate (a fixture that is no gate has the one). nil when there is none. The refund
-- of a cut, where wireOf is the price of the one the discovery reads.
function CeroSecModules.wireTotal(object, x, y, z)
	if object == nil then return nil end
	local holders = CeroSecModules.gateParts(object) or { object }
	local total = nil
	for i = 1, #holders do
		local own = CeroSecModules.ownLinksOn(holders[i])
		local at = CeroSecModules.linkIndexOf(own, x, y, z)
		if at ~= nil then total = (total or 0) + own[at].wire end
	end
	return total
end

-- Where a fixture's devices and cables are FILED: the square of its anchor leaf for
-- a gate, its own for anything else. x, y, z, or nil for an object with no square.
-- The machine's cable book names this square, because a leaf of a map double door
-- is taken away and made again on another square at every toggle and the anchor is
-- the one that is not.
function CeroSecModules.placeOf(object)
	if object == nil then return nil end
	local parts = CeroSecModules.gateParts(object)
	local at = (parts and parts[1] or object):getSquare()
	if at == nil then return nil end
	return at:getX(), at:getY(), at:getZ()
end

-- The same two, for the ONE object and nothing else: what the engine's
-- OnObjectAboutToBeRemoved handler sheds (SCeroSecFixtures). A gate's leaf is taken
-- away and put back on every toggle of a map double door (toggleDoubleDoorObject
-- removes the tile object of part 2 or 3 and makes a new one), and the handler that
-- refunds what was on the leaf being removed must refund THAT leaf's boxes and
-- cables, not the gate's, or every toggle would strip the anchor.
function CeroSecModules.unlinkOwn(object, x, y, z)
	if object == nil then return nil end
	local own = CeroSecModules.ownLinksOn(object)
	local at = CeroSecModules.linkIndexOf(own, x, y, z)
	if at == nil then return nil end
	local wire = own[at].wire
	table.remove(own, at)
	if not writeLinks(object, own) then return nil end
	return wire
end

-- Which shape this table is in. A number that is not a whole one in range is not a
-- version anything here wrote, and it reads as the oldest -- the same answer an
-- absent one gets, for the same reason: the ids are what they are.
function CeroSecModules.versionOf(fitted)
	if type(fitted) ~= "table" then return nil end
	local v = fitted[CeroSecModules.VERSION_KEY]
	if type(v) ~= "number" or v ~= math.floor(v) then return CeroSecModules.OLDEST_VERSION end
	if v < CeroSecModules.OLDEST_VERSION then return CeroSecModules.OLDEST_VERSION end
	return v
end

-- The table, walked up to this build, in place. true when it is readable at all.
--
-- A table a LATER build wrote is left exactly as it is and answers false: the ids in
-- it may mean something this build does not know, and reading them anyway would be
-- this build deciding what somebody else's hardware is. A door like that has no
-- modules as far as this build is concerned -- which is a door that does nothing,
-- not a door that loses its boxes -- and putting the newer mod back brings them all
-- back, because nothing here ever wrote over them.
function CeroSecModules.migrate(fitted)
	if type(fitted) ~= "table" then return false end
	local v = CeroSecModules.versionOf(fitted)
	if v > CeroSecModules.VERSION then return false end
	for n = v + 1, CeroSecModules.VERSION do
		local step = CeroSecModules.MIGRATIONS[n]
		if type(step) ~= "function" then return false end
		step(fitted)
		fitted[CeroSecModules.VERSION_KEY] = n
	end
	return true
end

-- The sandbox option, declared in 42/media/sandbox-options.txt and read below.
CeroSecModules.SANDBOX = "HardwareRequired"

--
-- The eight of them.
--
-- id       what the modData says, and the only name the rest of the mod uses
-- item     the item a survivor carries and the install takes out of his hands
-- skill    Perks.Electricity at or above this, to put it on or take it off
-- time     the timed action's length, in the game's own ticks, before the perk
--          takes its bite out of it (see ISCeroSecModuleAction)
-- xp       Electricity experience for fitting one, and none for taking it off
--
-- The levels are the size of the job and not a difficulty curve: a contact is
-- two wires and a magnet on a frame, a relay is the same two wires behind a
-- plate somebody has to be sure is dead first, a strike replaces the keep of a
-- lock, and an operator is a motor, an arm and a limit switch. One, one, two,
-- three -- and see the note over the list for the four the motor rung added.
--
-- The experience is set against vanilla's own electrical job: repairing a
-- generator is 5 (shared/TimedActions/ISFixGenerator.lua:71,
-- addXp(self.character, Perks.Electricity, 5)). A contact is less than that, an
-- operator more, and nothing here is worth a level.
--
-- The order is the order they are OFFERED in on the menu, which is the order a
-- survivor meets them in: what he can fit at level one first.
--
-- THE FOUR ADDED BY THE MOTOR RUNG GO ON THE END, and not in level order.
--
-- The first four have been in that order on the right-click menu since rung 4f
-- and a survivor knows where they are; a menu that reshuffles itself under him
-- because a fifth box was written is worse than a menu whose levels do not run
-- downhill. So the rule above is now the rule for each BATCH and not for the
-- whole list, and it is written down rather than left for somebody to notice.
--
-- The levels are the size of the job, like the first four. A curtain motor is a
-- small motor on a rail and a limit switch, which is the operator's job on a
-- tenth of the weight -- two. An appliance switch is a contactor behind a plate
-- somebody has to be sure is dead first, which is the relay's job on a circuit
-- that can kill him -- two. A window operator is an arm, a motor and a sash that
-- has to stop in the right place -- three, like the door operator it is. A
-- generator switch is three because of what is on the other side of it.
--
-- AND THE NINTH GOES ON THE END OF THE END, by the same rule read a third time: a
-- survivor knows where the first eight are on the menu and a ninth that pushed
-- them about would be worse than a list whose levels do not run downhill.
--
-- A tuner control is two at the same reading as the appliance switch it sits
-- beside: a box behind a plate on a set that holds a few hundred volts on its
-- chassis long after it is unplugged, and a ribbon into a tuner that is already
-- there (it is what every radio in this game is built round --
-- Base.RadioReceiver, and see the recipe). Nothing in it turns, so it takes no
-- motor and no receiver of its own.
--
-- recipe   the craftRecipe that makes one, in common/media/scripts/
--          recipes_cerosec.txt, all nine taught by CeroSec.WiringGuide
--
-- The recipe name is here so that a survivor who is offered a module he has
-- never heard of can be told the one thing that would get him one: the book.
-- The menu asks the engine whether he knows it (IsoGameCharacter.isRecipeKnown,
-- which is one call over the sandbox option, the cheat and the known list --
-- see CeroSecModuleMenu). It has nothing to do with FITTING one, which asks for
-- the box and never for the knowledge: it is what the greyed line SAYS.
CeroSecModules.LIST = {
	{ id = "contact",   item = "CeroSec.MagneticContact", skill = 1, time = 80,  xp = 3,
		recipe = "MakeCeroSecMagneticContact" },
	{ id = "relay",     item = "CeroSec.Relay",           skill = 1, time = 100, xp = 3,
		recipe = "MakeCeroSecRelay" },
	{ id = "strike",    item = "CeroSec.ElectricStrike",  skill = 2, time = 120, xp = 5,
		recipe = "MakeCeroSecElectricStrike" },
	{ id = "operator",  item = "CeroSec.DoorOperator",    skill = 3, time = 150, xp = 8,
		recipe = "MakeCeroSecDoorOperator" },
	{ id = "curtain",   item = "CeroSec.CurtainMotor",    skill = 2, time = 100, xp = 5,
		recipe = "MakeCeroSecCurtainMotor" },
	{ id = "appliance", item = "CeroSec.ApplianceSwitch", skill = 2, time = 110, xp = 5,
		recipe = "MakeCeroSecApplianceSwitch" },
	{ id = "window",    item = "CeroSec.WindowOperator",  skill = 3, time = 150, xp = 8,
		recipe = "MakeCeroSecWindowOperator" },
	{ id = "genset",    item = "CeroSec.GeneratorSwitch", skill = 3, time = 140, xp = 8,
		recipe = "MakeCeroSecGeneratorSwitch" },
	{ id = "tuner",     item = "CeroSec.TunerControl",   skill = 2, time = 110, xp = 5,
		recipe = "MakeCeroSecTunerControl" },
}

-- The tool the job needs, whichever module it is. Vanilla's own recipes ask for
-- a screwdriver by tag (`tags[base:screwdriver]`), and this asks for the item,
-- because what is being looked for here is one thing in a survivor's bag and not
-- a slot in a crafting table.
CeroSecModules.TOOL = "Base.Screwdriver"

local byId, byItem = nil, nil

-- Built once, on the first question asked, because a list of four walked on
-- every right-click of every door in a building is a cost paid for nothing.
local function index()
	if byId ~= nil then return end
	byId, byItem = {}, {}
	for i = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[i]
		byId[module.id] = module
		byItem[module.item] = module
	end
end

function CeroSecModules.byId(id)
	if type(id) ~= "string" then return nil end
	index()
	return byId[id]
end

function CeroSecModules.byItem(fullType)
	if type(fullType) ~= "string" then return nil end
	index()
	return byItem[fullType]
end

--
-- Is the hardware required at all?
--
-- Read the way vanilla reads its own grouped options -- `SandboxVars.Map and
-- (SandboxVars.Map.AllowMiniMap == true)`, client/ISUI/Maps/ISMiniMap.lua:687 --
-- because SandboxVars is a plain table and a group nobody declared is simply not
-- in it.
--
-- And it fails CLOSED: anything that is not the literal false is "required".
-- A sandbox file that failed to load, a save from before this rung, a group that
-- is not there -- every one of those is a world where doors are NOT wired, which
-- a player sees at once and can fix from the sandbox screen. The other way round
-- is a world that quietly went back to magic and looks exactly like a working
-- one.
function CeroSecModules.required()
	local group = SandboxVars and SandboxVars.CeroSec
	if group == nil then return true end
	return group[CeroSecModules.SANDBOX] ~= false
end

--
-- What is fitted to one object
--
-- Always a table, never nil: "nothing is fitted" is an answer and not a missing
-- one, and every caller reads it the same way. Nothing but the ids in
-- CeroSecModules.LIST is looked at and nothing but `true` counts, so somebody else's writing in that
-- table -- or a forged one out of an old save -- fits no hardware.
--
function CeroSecModules.ownedBy(object)
	local out = {}
	if object == nil then return out end
	if type(object.hasModData) ~= "function" or not object:hasModData() then return out end
	local data = object:getModData()
	if data == nil then return out end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then return out end
	-- The chain, on the way in and in one place: this is the ONE function that reads
	-- what is screwed to an object, so a table written by an older build is walked up
	-- here or nowhere. One a LATER build wrote is not read at all -- an empty answer,
	-- which is a door that does nothing rather than a door whose boxes were guessed
	-- at (see CeroSecModules.migrate).
	if not CeroSecModules.migrate(fitted) then return out end
	for i = 1, #CeroSecModules.LIST do
		local id = CeroSecModules.LIST[i].id
		if fitted[id] == true then out[id] = true end
	end
	return out
end

-- What is fitted to this fixture AS A WHOLE, which for one leaf of a double or a
-- garage door is what is fitted to any leaf of it (CeroSecModules.gateParts): a gate
-- is one opening and a survivor who looks at any leaf of it sees the one operator,
-- the one strike. Everything that asks "what does this fixture carry" -- the menu,
-- the device walk, the install and the removal -- asks this one, and only the two
-- that shed a fixture's own boxes when the ENGINE takes the object away ask
-- ownedBy and write with setOwn / unlinkOwn, for the reason given on unlinkOwn.
--
-- A union, and not the anchor's table alone, because a world may already hold a
-- strike or a contact on any leaf: those were allowed on every leaf before there
-- was a gate device (only the operator was refused, as `manydoors`). Reading all of
-- them means an existing world loses nothing by this.
function CeroSecModules.installedOn(object)
	local out = CeroSecModules.ownedBy(object)
	local parts = CeroSecModules.gateParts(object)
	if parts == nil then return out end
	for i = 1, #parts do
		if parts[i] ~= object then
			local more = CeroSecModules.ownedBy(parts[i])
			for id in pairs(more) do out[id] = true end
		end
	end
	return out
end

function CeroSecModules.installedIn(fitted, id)
	return type(fitted) == "table" and fitted[id] == true
end

-- Is there NOTHING left on this fixture worth keeping a table for? No module, no
-- pre-fitting mark, and no cable run to it.
--
-- Asked of the table itself and not of the object, because the one caller is the
-- writer that is holding it (setOn): what it decides is whether the last module off
-- takes the table with it, which IsoObject.save's isEmpty() branch is the whole
-- reason for. The two keys that are not ids are both asked HERE, so a third one
-- added some day has one place to be asked in rather than two conditions to be
-- forgotten at.
function CeroSecModules.isBare(fitted)
	if type(fitted) ~= "table" then return true end
	for i = 1, #CeroSecModules.LIST do
		if fitted[CeroSecModules.LIST[i].id] == true then return false end
	end
	if fitted[CeroSecModules.PRE_KEY] == true then return false end
	local links = fitted[CeroSecModules.LINK_KEY]
	if type(links) == "table" and #links > 0 then return false end
	return true
end

--
-- WAS THIS FIXTURE WIRED BEFORE THE OUTBREAK? (see PRE_KEY)
--
-- true also for a table this build cannot read -- one a LATER build wrote. That is
-- not a shortcut: the answer is what the pre-fitting walk uses to decide whether to
-- LEAVE A FIXTURE ALONE, and a table whose ids may mean something this build does not
-- know is the last thing to write into. So "unreadable" reads as "already done",
-- which is the safe direction for both readings of the question.
local function ownPreFitted(object)
	if object == nil then return false end
	if type(object.hasModData) ~= "function" or not object:hasModData() then return false end
	local data = object:getModData()
	if data == nil then return false end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then return false end
	if not CeroSecModules.migrate(fitted) then return true end
	return fitted[CeroSecModules.PRE_KEY] == true
end

-- For a gate: marked on ANY leaf. The modules go on the anchor whichever leaf the
-- walk was at, so the mark goes there too (markPreFitted) and every leaf the walk
-- reaches afterwards reads "done"; a world where only a non-anchor leaf carries the
-- mark from before is read as done as well, which is the safe direction (see above).
function CeroSecModules.preFitted(object)
	local parts = CeroSecModules.gateParts(object)
	if parts == nil then return ownPreFitted(object) end
	for i = 1, #parts do
		if ownPreFitted(parts[i]) then return true end
	end
	return false
end

-- The mark, and only the mark: the modules themselves go on through setOn, which is
-- the one writer. The server's, like every other write into a fixture's modData.
-- false when there is nothing there to mark, which is a fixture nothing was fitted
-- to and therefore nothing to remember. On the anchor leaf of a gate, where setOn
-- put the modules.
function CeroSecModules.markPreFitted(object)
	if object == nil then return false end
	local parts = CeroSecModules.gateParts(object)
	if parts ~= nil then object = parts[1] end
	local data = object:getModData()
	if data == nil then return false end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then return false end
	if not CeroSecModules.migrate(fitted) then return false end
	fitted[CeroSecModules.PRE_KEY] = true
	object:transmitModData()
	return true
end

--
-- Screwing one on, and taking it off
--
-- The server's, and only the server's: what reaches a client is the object's
-- modData through transmitModData, which has a server branch of its own
-- (GameServer.sendObjectModData -- the proofs, 2) and marks the chunk to be
-- written out on the way past (flagForHotSave).
--
-- The last module off takes the table with it rather than leaving an empty one
-- behind. IsoObject.save skips a modData table that isEmpty() and this one would
-- not be empty -- it would hold one empty table -- so a door somebody wired and
-- unwired would carry a few bytes for the rest of the save otherwise.
function CeroSecModules.setOwn(object, id, on)
	if object == nil or CeroSecModules.byId(id) == nil then return false end
	local data = object:getModData()
	if data == nil then return false end
	local fitted = data[CeroSecModules.DATA_KEY]
	if type(fitted) ~= "table" then
		if not on then return true end
		fitted = {}
		data[CeroSecModules.DATA_KEY] = fitted
	end
	if on then
		fitted[id] = true
		-- And the shape it is in, stamped on the write. This is the server, and the
		-- only place a door's modules are ever written: a number put on here travels
		-- with the table (transmitModData) and is saved with the chunk, so the day a
		-- step is written there is something for it to count against. A table with no
		-- number is the oldest shape and is read as one (CeroSecModules.versionOf), so
		-- nothing depends on the stamp having happened.
		fitted[CeroSecModules.VERSION_KEY] = CeroSecModules.VERSION
	else
		fitted[id] = nil
		local left = false
		for i = 1, #CeroSecModules.LIST do
			if fitted[CeroSecModules.LIST[i].id] == true then left = true end
		end
		-- The last box off takes the table with it, version stamp and all: a door
		-- somebody wired and unwired carries nothing, exactly as it did before the
		-- stamp existed. IsoObject.save skips an EMPTY modData and a table holding only
		-- a number is not empty, so leaving one behind would be a few bytes in every
		-- chunk for the rest of the save.
		--
		-- UNLESS THE FIXTURE WAS WIRED BEFORE THE OUTBREAK, in which case the mark is
		-- the whole point of it and outlives every module (see PRE_KEY): a survivor who
		-- strips a pre-fitted switch must not find the relay back on it a minute later.
		--
		-- OR A CABLE IS STILL RUN TO IT, which is the same rule one key along and for
		-- the same reason: what a link owes the player is the wire it cost, and a table
		-- taken away with a link still in it is a refund nobody can ever claim.
		if not left and CeroSecModules.isBare(fitted) then
			data[CeroSecModules.DATA_KEY] = nil
		end
	end
	object:transmitModData()
	return true
end

-- The same, for a fixture as a whole (see installedOn): a module goes on the ANCHOR
-- leaf of a gate and comes off whichever leaf holds it. setOwn is the one that
-- touches exactly the object it is given, for the drop paths that must not spread.
function CeroSecModules.setOn(object, id, on)
	if object == nil or CeroSecModules.byId(id) == nil then return false end
	local parts = CeroSecModules.gateParts(object)
	if parts == nil then return CeroSecModules.setOwn(object, id, on) end
	if on then return CeroSecModules.setOwn(parts[1], id, true) end
	-- Off: from EVERY leaf that holds it, and HOW MANY that was is the second answer.
	-- A world from before a gate was one device can hold the same box on several
	-- leaves (a strike or a contact was allowed on each, and the pre-fitting walk
	-- fitted each), and the survivor paid for each: the caller hands back one item
	-- per box that came off, so nothing bought is lost by the merge.
	local n = 0
	for i = 1, #parts do
		if CeroSecModules.ownedBy(parts[i])[id] then
			CeroSecModules.setOwn(parts[i], id, false)
			n = n + 1
		end
	end
	return true, n
end

--
-- Where a module may go
--

-- The room a square is in, by its raw id ("kitchen", "office"), or nil. Here
-- rather than in SCeroSecDevices, where it used to live alone, because the rule
-- below is asked by the right-click menu too and the menu cannot load a server
-- file.
function CeroSecModules.roomName(square)
	if square == nil then return nil end
	local room = square:getRoom()
	if room == nil then return nil end
	local name = room:getName()
	if type(name) ~= "string" or name == "" then return nil end
	return name
end

-- Does this map door's lock stop anybody? Its own isExterior() first -- the
-- square carries the exterior flag and the far side is a building with a def, or
-- the other way round -- and then the rooms, because a door whose two sides have
-- a room on exactly one of them is a way out of the building whatever the tile
-- flags say.
--
-- The whole reasoning, and the couldBeOpen bytecode it is read off, is at the
-- head of SCeroSecDevices.lua: from inside a building a locked map door always
-- opens, so a lock on an interior door is a device that lies -- and a strike on
-- one is a box that does nothing, which is why this is what an install asks too.
function CeroSecModules.doorLocks(door)
	if door:isExterior() then return true end
	local here = CeroSecModules.roomName(door:getSquare())
	local there = CeroSecModules.roomName(door:getOppositeSquare())
	if here == nil and there == nil then return false end
	return here == nil or there == nil
end

-- One leaf of a double or a garage door: "double", "garage", or nil. Vanilla's own
-- way of asking, both public statics, both -1 for an object with no such property
-- on it (server/BuildingObjects/ISBuildUtil.lua:556, ISDoubleDoor.lua:315).
--
-- A gate is ONE opening with several leaves, and the vanilla toggle moves them
-- together (IsoDoor.toggleDoubleDoor / toggleGarageDoor flip every leaf; the packet
-- for one moves the rest on every client). So the machine treats it as one door:
-- one operator, one strike, one device. Which leaf holds the boxes is gateParts.
function CeroSecModules.gateKind(object)
	if IsoDoor == nil or object == nil then return nil end
	if IsoDoor.getDoubleDoorIndex(object) ~= -1 then return "double" end
	if IsoDoor.getGarageDoorIndex(object) ~= -1 then return "garage" end
	return nil
end

-- Every leaf of the gate this object is one leaf of, ANCHOR FIRST, or nil for an
-- object that is no gate. The anchor is where a module or a cable is written, so it
-- must be the leaf that is never taken away:
--   * double: the hinge leaves 1 and 4 never move; leaves 2 and 3 are removed and
--     made again on another square at every toggle
--     (IsoDoor.toggleDoubleDoorObject), and a map door's new leaf does NOT inherit
--     the old one's modData (a built one's does). So 1, 4, 2, 3, in that order.
--   * garage: the leaves are never recreated; the first of the chain.
-- The object asked about is always in the list, so the union reads never miss it.
function CeroSecModules.gateParts(object)
	local kind = CeroSecModules.gateKind(object)
	if kind == nil then return nil end
	local out = {}
	local seen = false
	if kind == "double" then
		local order = { 1, 4, 2, 3 }
		for n = 1, #order do
			local leaf = IsoDoor.getDoubleDoorObject(object, order[n])
			if leaf ~= nil then
				out[#out + 1] = leaf
				if leaf == object then seen = true end
			end
		end
	else
		local leaf = IsoDoor.getGarageDoorFirst(object) or object
		while leaf ~= nil and #out < 8 do
			out[#out + 1] = leaf
			if leaf == object then seen = true end
			leaf = IsoDoor.getGarageDoorNext(leaf)
		end
	end
	if not seen then out[#out + 1] = object end
	return out
end

function CeroSecModules.isManyDoors(object)
	return CeroSecModules.gateKind(object) ~= nil
end

-- Is it a door at all -- a map one or a built one? Vanilla asks the pair the
-- same way (ISWorldObjectContextMenu.isThumpDoor, :2176).
function CeroSecModules.isDoor(object)
	if object == nil then return false end
	if instanceof(object, "IsoDoor") then return true end
	return instanceof(object, "IsoThumpable") and object:isDoor() == true
end

function CeroSecModules.isWindow(object)
	return object ~= nil and instanceof(object, "IsoWindow")
end

function CeroSecModules.isLightSwitch(object)
	return object ~= nil and instanceof(object, "IsoLightSwitch")
end

--
-- The fixtures the motor rung added, and the ONE thing worth knowing about
-- curtains: there are two of them and they are not the same object.
--
-- A window's curtain and a player-built frame's are an IsoCurtain of their own,
-- on the square's object list like any other fixture. A DOOR's curtain is a pair
-- of fields on the door -- `hasCurtain` and `curtainOpen` -- and there is no
-- second object at all: IsoDoor.HasCurtains() answers THE DOOR when hasCurtain
-- is set and null otherwise (offsets 0-12), which is why vanilla's own menu
-- re-fetches before it reads a sprite (ISWorldObjectContextMenu.lua:2238).
--
-- So a curtain motor goes on either, and the two are told apart here once
-- (docs/notes/actuators.md, 1).
function CeroSecModules.isCurtain(object)
	return object ~= nil and instanceof(object, "IsoCurtain")
end

-- A door that has a sheet on it. Never a curtain the module could go on TWICE:
-- the door carries the fields and the door is what a motor is screwed to.
function CeroSecModules.doorHasCurtain(object)
	if object == nil then return false end
	if not instanceof(object, "IsoDoor") then return false end
	return object:HasCurtains() ~= nil
end

function CeroSecModules.hasCurtain(object)
	return CeroSecModules.isCurtain(object) or CeroSecModules.doorHasCurtain(object)
end

-- The oven, the microwave AND the coffee machine, which are one class in this
-- game: isMicrowave() and isStove() read the CONTAINER's type and not the
-- sprite, and newtiledefinitions.tiles.txt gives every GroupName = Coffee tile
-- `IsoType = IsoStove` with `container = stove` (actuators.md, 3). So a coffee
-- machine needs nothing of its own and gets none.
function CeroSecModules.isStove(object)
	return object ~= nil and instanceof(object, "IsoStove")
end

-- The laundry. Three classes and not four: IsoStackedWasherDryer is left out
-- deliberately and the reason is the study's own -- no tile in any of the game's
-- five .tiles.txt files carries that IsoType, so nothing on the map makes one,
-- and it is the one of the four that splits into TWO switches
-- (setWasherActivated / setDryerActivated). Half a device on an object nobody
-- has is worse than no device.
function CeroSecModules.isWasher(object)
	if object == nil then return false end
	return instanceof(object, "IsoClothingWasher")
		or instanceof(object, "IsoClothingDryer")
		or instanceof(object, "IsoCombinationWasherDryer")
end

function CeroSecModules.isGenerator(object)
	return object ~= nil and instanceof(object, "IsoGenerator")
end

--
-- THE TELEVISION AND THE RADIO SET, which are one class twice over
--
-- zombie.iso.objects.IsoTelevision and zombie.iso.objects.IsoRadio both extend
-- IsoWaveSignal, which carries `protected DeviceData deviceData` and answers
-- getDeviceData() -- and DeviceData is where everything a set has is kept, the
-- switch and the dial included (javap; the whole list is at the head of
-- SCeroSecRadio.lua, proof 2). The two classes are SIBLINGS and neither is the
-- other, so they are asked apart, and they are two kinds under /dev because a
-- survivor does not think of a television and a radio as one thing.
--
-- AND THE DEVICE DATA IS PART OF THE QUESTION. A set with none is a sprite: the
-- switch and the dial are on the data and there is nothing else to write. A map
-- tile always has one -- IsoWaveSignal.load makes it when the stream did not
-- carry one (offsets 7-23) -- and a set a survivor puts down carries the item's
-- own (ISMoveableSpriteProps.lua:2129-2147, setDeviceData) -- so this is a guard
-- and not a case. It is asked HERE, once, because the install and the discovery
-- must not disagree about what a set is: a tuner fitted to something /dev then
-- refuses to show is a box a survivor cannot get back.
function CeroSecModules.isTelevision(object)
	if object == nil then return false end
	if not instanceof(object, "IsoTelevision") then return false end
	return object:getDeviceData() ~= nil
end

-- A radio SET, which is the receiver and not the TNC. The same object can be
-- both: a ham set in the room is the machine's /dev/radio0, read-only, because
-- the aerial's frequency is the survivor's (SCeroSecRadio.lua, proof 7), and with
-- a tuner control screwed to it, it is also an rxN whose switch and dial the
-- machine works. That is the door's own shape -- doorN opens and lockN keys, one
-- object, two vocabularies -- and the TNC's own reading does not change for it.
function CeroSecModules.isRadioSet(object)
	if object == nil then return false end
	if not instanceof(object, "IsoRadio") then return false end
	return object:getDeviceData() ~= nil
end

function CeroSecModules.isTuneable(object)
	return CeroSecModules.isTelevision(object) or CeroSecModules.isRadioSet(object)
end

-- Anything a module of any kind could go on. What the right-click menu asks
-- first, so that a survivor right-clicking a fridge is offered nothing at all
-- rather than a menu of eight refusals.
function CeroSecModules.isFittable(object)
	return CeroSecModules.isDoor(object) or CeroSecModules.isWindow(object)
		or CeroSecModules.isLightSwitch(object)
		or CeroSecModules.isCurtain(object) or CeroSecModules.isStove(object)
		or CeroSecModules.isWasher(object) or CeroSecModules.isGenerator(object)
		or CeroSecModules.isTuneable(object)
end

-- May this module go on this object? true, or false and the reason in one word,
-- which is the key the menu greys the entry with
-- (Tooltip_CeroSec_Module<Reason>).
--
-- The refusals are the ones a survivor can DO something about, and each is a
-- fact about the object and not about him: the wrong sort of fixture, a door the
-- lock means nothing on, a leaf of a garage door no machine will work. A window
-- that is boarded or a stove that is broken is NOT one of these: those are facts
-- about what the fixture is doing today, they are the device's refusals rather
-- than the install's, and a motor screwed to a boarded window works the day the
-- boards come off. What he
-- is carrying, what he knows and whether he is standing there are asked
-- elsewhere, because those are facts about HIM.
function CeroSecModules.fitsOn(object, id)
	local module = CeroSecModules.byId(id)
	if module == nil or object == nil then return false, "fixture" end

	if id == "relay" then
		if not CeroSecModules.isLightSwitch(object) then return false, "fixture" end
		return true
	end

	if id == "contact" then
		if CeroSecModules.isDoor(object) or CeroSecModules.isWindow(object) then return true end
		return false, "fixture"
	end

	if id == "curtain" then
		if CeroSecModules.hasCurtain(object) then return true end
		-- A door with no sheet on it is not a refusal a survivor can do anything
		-- about by arguing: he hangs a sheet and the entry appears.
		return false, "fixture"
	end

	if id == "appliance" then
		if CeroSecModules.isStove(object) or CeroSecModules.isWasher(object) then
			return true
		end
		return false, "fixture"
	end

	if id == "genset" then
		if CeroSecModules.isGenerator(object) then return true end
		return false, "fixture"
	end

	-- A television or a radio set, and nothing else: a tuner control is a box
	-- behind the back panel of a receiver, wired to the tuner that is already in
	-- it. A set with no device data on it is not one of these (isTuneable), and it
	-- is the one refusal here a survivor really cannot do anything about -- which
	-- is why it reads as the wrong sort of fixture rather than as a fault: from
	-- where he stands the thing on that tile is not a set the machine can wire.
	if id == "tuner" then
		if CeroSecModules.isTuneable(object) then return true end
		return false, "fixture"
	end

	--
	-- THE WINDOW OPERATOR, and the sentence that used to be here was not exact.
	--
	-- It said: "there is no window actuator in this mod and there is none in the
	-- game either -- the only call that moves a sash is
	-- IsoWindow.ToggleWindow(IsoGameCharacter), which wants a survivor standing
	-- at it". The call is right and the reason was not. ToggleWindow never
	-- DEREFERENCES the character: every use of the argument is behind a null
	-- guard (the barricade test at offsets 37-49 is skipped for null, the
	-- IsoZombie test at 93-97 is false for it, the music call at 166-197 is
	-- behind an ifnull) and the sync at offset 147 is unconditional. What is true
	-- is three other things, all in the bytecode and all of them side effects a
	-- motor really would have:
	--
	--   offsets 50-54   `locked = false`, unconditionally, before the sash moves.
	--                   The motor throws the catch as it opens, which is what an
	--                   operator does and why `win0` keeps the latch and this
	--                   keeps the sash.
	--   offsets 86-118  the house alarm goes off, every time, when the sash ends
	--                   up open: the sandbox check is consulted only for an
	--                   IsoZombie, so a null character falls straight into
	--                   handleAlarm(). Kept, documented, and in the manual.
	--   offsets 37-49   the barricade test is the one thing it asks the character
	--                   for, so it is skipped -- and a boarded window would move
	--                   behind its boards. Refused HERE instead (SCeroSecDevices'
	--                   `act`), the way a barricaded door already is.
	--
	-- And there are two more silent returns above all of that which the study did
	-- not name: `permaLocked` at offsets 21-28 and `destroyed` at 29-36. Both are
	-- refused before the call for the door's reason -- a `return` that does
	-- nothing is an order swallowed.
	--
	-- So a window operator is buildable and it is built. It goes on a window and
	-- on nothing else.
	if id == "window" then
		if CeroSecModules.isWindow(object) then return true end
		return false, "fixture"
	end

	-- The two that work a door itself, and neither goes on a window.
	if not CeroSecModules.isDoor(object) then return false, "fixture" end

	-- An operator goes on any leaf of a gate too: the machine works the WHOLE gate
	-- through the vanilla toggle (SCeroSecDevices, the door act), never one leaf.
	if id == "operator" then return true end

	-- strike: only where the lock bites. A built door's always does.
	if instanceof(object, "IsoDoor") and not CeroSecModules.doorLocks(object) then
		return false, "nolock"
	end
	return true
end

--
-- WHERE HE IS STANDING, WHAT THE FIXTURE IS DOING, AND WHOSE HOUSE IT IS
--
-- fitsOn answers what a module CAN go on and never changes from one minute to
-- the next: it is a fact about the fixture's shape. These three are facts about
-- RIGHT NOW, and they are all three refusals of the same gesture, so they are
-- asked in one function -- the turnOnRefusal shape the debug window and the
-- server already share (SCeroSecDebug.turnOnRefusal): one rule, one place, one
-- wording, and the day a rule moves the greyed entry moves with it.
--
-- 1. INSIDE. A module screwed to the skin of a building is a module anybody can
--    unscrew from the pavement, and a survivor who wired his front door would
--    find the contact gone and the door opened with it. So the job is done from
--    inside, and "inside" is asked of the square HE is standing on and never of
--    the fixture's: a door stands on the room's own square (which is why
--    doorLocks reads getSquare against getOppositeSquare and calls the pair
--    "exactly one of them has a room") and he stands on one side of it or the
--    other. The inside side is in a room; the pavement is not. An interior door
--    has a room on both sides, so both sides are allowed, which is the answer a
--    survivor expects.
--
--    isInARoom() and not getRoom() ~= nil, and the difference is a base: the
--    call is `getRoom() != null || getIsoWorldRegion().isPlayerRoom()` (javap -c
--    zombie.iso.IsoGridSquare.isInARoom, offsets 0-31), so a room a PLAYER built
--    -- four walls the map has no RoomDef for -- reads as inside, and getRoom()
--    alone would refuse a man standing in the middle of his own base. Vanilla
--    asks it that way itself (server/BuildingObjects/ISEmptyGraves.lua:169,
--    server/Vehicles/Vehicles.lua:667).
--
--    A GENERATOR IS EXEMPT and it is the only one. It is an outdoor machine by
--    construction -- a generator indoors poisons the room, which is the game's
--    own rule -- so a check that asked for a room would be a module nobody could
--    ever fit. Every other fixture here is reached from inside a building.
--
-- 2. OPEN FOR WHAT OPENS, OFF FOR WHAT SWITCHES ON. Nobody fits an operator to a
--    door while it is shut, a motor to a sash he cannot reach round, or a
--    contactor to an oven that is cooking. The state asked for is the state of
--    the thing the MODULE is screwed to, which is why a curtain motor on a door
--    asks about the sheet and a strike on the same door asks about the door:
--    one fixture, two jobs, two answers.
--
--    Every getter is the one the device layer already reads the state with
--    (SCeroSecDevices.stateOf), proven by javap against the shipped jar:
--      IsoDoor.IsOpen()          IsoThumpable.IsOpen()   IsoWindow.IsOpen()
--      IsoCurtain.IsOpen()       IsoDoor.isCurtainOpen()
--      IsoStove.Activated()      IsoClothingWasher.isActivated() (and the dryer
--      and the combination machine)  IsoGenerator.isActivated()
--      DeviceData.getIsTurnedOn() through IsoWaveSignal.getDeviceData()
--
--    A window's IsOpen() is a sash that really moved, so it already excludes a
--    barricaded, sealed or smashed window: none of those opens. That is why
--    there is no second word for them here.
--
--    IT IS ASKED OF A REMOVAL TOO. Taking a contactor out of a running oven is
--    the same hand in the same place, and the door a man is unscrewing a strike
--    from is the door that swings into him.
--
--    A PRE-FITTED FIXTURE IS NOT AFFECTED. The 1991 walk writes modData and
--    performs no player action at all (CeroSecModules.markPreFitted / setOn),
--    so it never comes past here.
--
-- 3. SOMEBODY ELSE'S SAFEHOUSE, and only when the server asked for it
--    (SandboxVars.CeroSec.SafehouseModules, off by default). A safehouse's own
--    vanilla rule is about LOOTING and fitting is not looting -- nothing leaves
--    the building and nothing is taken out of a container -- so that rule is not
--    borrowed and this option is the only gate. On, a fixture standing in a
--    safehouse takes a module from the people the safehouse allows and nobody
--    else; off, it is open to anybody, which is the world as it was before the
--    option existed.
--
--    SafeHouse.getSafeHouse(square) is asked of the FIXTURE's square and not of
--    his: what is being protected is somebody's door, and a man on the pavement
--    outside a safehouse is exactly the case this exists for. It is
--    isSafeHouse(square, null, false) (javap -c, offsets 0-6) down to
--    findSafeHouse, a walk of safehouseList comparing x/y against each one's
--    box; nil when no safehouse covers the square, which is every square in
--    single player.
--
--    playerAllowed(IsoPlayer) is vanilla's own membership question and admins
--    pass it without a branch of ours: the bytecode is `players.contains(
--    getUsername()) || owner.equals(getUsername()) || role.hasCapability(
--    CanGoInsideSafehouses)` (javap -c zombie.iso.areas.SafeHouse.playerAllowed,
--    offsets 0-46), and that capability is the one vanilla's own safehouse
--    interact check reads for the same purpose (isSafehouseAllowInteract,
--    offsets 23-44). So the owner, his members and an admin may wire it, and
--    that is the allowance vanilla gives its own looting rule.
--
-- nil for "he may", or the reason in one word, which is the key the menu greys
-- with: Tooltip_CeroSec_Module<Reason>.
--

CeroSecModules.SANDBOX_SAFEHOUSE = "SafehouseModules"

-- Does the safehouse gate apply at all?
--
-- It fails OPEN, which is the opposite direction to required() above, and the
-- reason is the compatibility contract rather than a preference: a new sandbox
-- option defaults to the OLD behaviour, and the old behaviour is a world with no
-- gate. A sandbox file that failed to load must not be a world where nobody can
-- touch his own hardware, because that is a refusal a player cannot see the
-- cause of -- where the hardware gate failing closed gives him an empty /dev,
-- which he can read off the screen.
function CeroSecModules.safehouseGated()
	local group = SandboxVars and SandboxVars.CeroSec
	if group == nil then return false end
	return group[CeroSecModules.SANDBOX_SAFEHOUSE] == true
end

-- Whose house is it? nil or "safehouse", and it is one function because it is one
-- rule: every gesture at a fixture asks it the same way, off the same option, and a
-- rule written out three times is a rule that will one day answer three things.
--
-- It is the one refusal a survivor cannot get round by doing something at the
-- fixture, which is why it is asked first everywhere it is asked at all.
-- AND IT ASKS THE SQUARE THE FIXTURE BELONGS TO, not only the one it stands on.
-- findSafeHouse is `x >= X && x < X2 && y >= Y && y < Y2` on the square handed in
-- (javap -c zombie.iso.areas.SafeHouse.findSafeHouse, offsets 28-69) and a claim
-- covers the building's own tiles. But a door, a window and a curtain ARE the wall
-- and stand on ONE of the two squares they divide, which for a SOUTH or EAST
-- exterior wall is the pavement -- outside every box. Asked of that square alone,
-- the front door of a claimed safehouse came back as nobody's, and a stranger in
-- the street could run a cable to it and work it from his own machine.
local function houseRefusal(object, playerObj)
	if not CeroSecModules.safehouseGated() or SafeHouse == nil then return nil end
	local square = object:getSquare()
	if square == nil then return nil end
	local house = SafeHouse.getSafeHouse(square)
	if house == nil and (CeroSecModules.isDoor(object)
			or CeroSecModules.isWindow(object) or CeroSecModules.isCurtain(object)) then
		-- The other side of the wall, from the engine (getOppositeSquare exists on
		-- IsoDoor, IsoWindow, IsoThumpable and IsoCurtain, and on nothing else this
		-- reads), and nil when its chunk is away.
		local opposite = object:getOppositeSquare()
		if opposite ~= nil then house = SafeHouse.getSafeHouse(opposite) end
	end
	if house ~= nil and not house:playerAllowed(playerObj) then return "safehouse" end
	return nil
end

-- Does a survivor have to be standing INSIDE to work on this fixture?
--
-- THE ENVELOPE, and only the envelope: the door, the window and the curtain -- the
-- things a stranger would strip to get in or to blind the alarm. That is what the
-- rule was written for, and a module anybody could unscrew from the pavement is
-- what it exists to stop.
--
-- Nothing else is asked. A PORCH LAMP is the case a relay is for -- an outdoor
-- light on a timer, screwed to the outside of the house, reached from the pavement
-- because there is nowhere else to stand -- and a rule that wanted a room round it
-- would be a module nobody could fit to the thing it was made for. The same goes
-- for an appliance, a set or a generator a survivor has dragged outside: they are
-- fitted where they stand. The generator used to be the one exemption and it is
-- now one of five, for its own reason read wider.
local function needsInside(object)
	return CeroSecModules.isDoor(object) or CeroSecModules.isWindow(object)
		or CeroSecModules.isCurtain(object)
end

-- The state the fixture has to be in for THIS module, or nil when the module has
-- none. A light switch is the one that asks for nothing: a relay goes behind a
-- plate whose only state is the light it works, and a machine that would not let
-- a man wire a switch while the light was on would be a rule about nothing.
local function stateRefusal(object, id)
	if id == "relay" then return nil end

	if id == "curtain" then
		-- The two curtains, told apart the way SCeroSecDevices tells them apart:
		-- an IsoCurtain answers IsOpen(), a door's own sheet answers
		-- isCurtainOpen() and there is no second object to ask.
		if CeroSecModules.isCurtain(object) then
			if not object:IsOpen() then return "drawn" end
			return nil
		end
		if not object:isCurtainOpen() then return "drawn" end
		return nil
	end

	if id == "appliance" then
		-- The oven's getter is Activated() with a capital A and the laundry's is
		-- isActivated(); they are two classes and two spellings, not one.
		if CeroSecModules.isStove(object) then
			if object:Activated() then return "running" end
			return nil
		end
		if object:isActivated() then return "running" end
		return nil
	end

	if id == "genset" then
		if object:isActivated() then return "running" end
		return nil
	end

	if id == "tuner" then
		local data = object:getDeviceData()
		if data ~= nil and data:getIsTurnedOn() then return "running" end
		return nil
	end

	-- contact, strike, operator and window: the thing that opens, whichever of
	-- the three classes it is. All three answer IsOpen().
	if not object:IsOpen() then return "closed" end
	return nil
end

-- The same envelope a module's own fitting or removal asks for -- needsInside,
-- and then whichever module actually fitted answers its own moment -- asked
-- again for a CABLE. The rule: a stranger who could not walk in and unscrew
-- a strike off a shut door may not wire it, or unwire it, from the street
-- either. A fixture can carry more than one of our modules (a door's
-- own operator beside a contact, or a curtain motor on its sheet) and each
-- keeps its own moment, so every one fitted is asked and the first "no" wins
-- -- never a copy of stateRefusal's rules, the same calls fittingRefusal makes.
local function envelopeRefusal(object, playerObj)
	if not needsInside(object) then return nil end
	-- A bare fixture (a module already taken off, the cable left behind and
	-- still owed its wire) has no state to protect and asks nothing here: the
	-- comment on unlinkRefusal's own bare-fixture case still holds.
	if not CeroSecModules.anyFitted(object) then return nil end
	local square = playerObj:getCurrentSquare()
	if square == nil or not square:isInARoom() then return "outside" end
	local fitted = CeroSecModules.installedOn(object)
	for i = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[i]
		if fitted[module.id] then
			local stop = stateRefusal(object, module.id)
			if stop ~= nil then return stop end
		end
	end
	return nil
end

function CeroSecModules.fittingRefusal(object, id, playerObj)
	if object == nil or playerObj == nil then return "outside" end
	if CeroSecModules.byId(id) == nil then return "outside" end

	-- WHOSE HOUSE FIRST. It is the one of the three he cannot change by doing
	-- anything at the fixture, and it is the one that should not be answered
	-- round: a stranger told "open it first" has been told what state somebody
	-- else's door is in.
	local house = houseRefusal(object, playerObj)
	if house ~= nil then return house end

	if needsInside(object) then
		local square = playerObj:getCurrentSquare()
		-- No square at all is a survivor the world cannot place, and the honest
		-- answer for one is the refusal: nothing here is worth guessing at.
		if square == nil or not square:isInARoom() then return "outside" end
	end

	return stateRefusal(object, id)
end

-- Is there any of our hardware on this fixture at all? The question a cable asks
-- first and the menu asks before it draws anything, so it is one function: the ids
-- are a closed list and "anything on it" must not become nine answers in two files.
function CeroSecModules.anyFitted(object)
	local fitted = CeroSecModules.installedOn(object)
	for i = 1, #CeroSecModules.LIST do
		if fitted[CeroSecModules.LIST[i].id] then return true end
	end
	return false
end

--
-- RUNNING A CABLE
--
-- A link is not a module: nothing is screwed to the fixture and nothing comes out
-- of a box. It is a cable from a machine to hardware that is already there. It
-- USED to skip the two rules about the moment the fitting wears -- inside, and
-- open or off or drawn back -- on the reasoning that a cable lands on the
-- terminals of a box somebody had already fitted and does not need the door to
-- swing.
--
-- That let a stranger stand in the street, wire a shut front door from outside
-- it, and unlock it -- a job unscrewing the strike itself would have refused him.
-- The rule since 2026-09-17, written because of that hole: wiring a fixture is
-- only possible where fitting or removing one of its modules would be, so
-- linking and unlinking now
-- ask envelopeRefusal (above) too, the SAME needsInside and stateRefusal calls
-- fittingRefusal makes and never a second copy of them.
--
-- WHAT IT ASKS, in order: whose house it is (a stranger who may not fit a strike
-- to your door may not re-route your door to HIS machine either, and of the two
-- that is the worse one), then the envelope, same as fitting or unfitting a
-- module would.
--
-- nil for "he may", or the reason in one word, which is the key the menu greys
-- with (Tooltip_CeroSec_Link<Reason>, except outside/closed/drawn, which read
-- the module menu's own Tooltip_CeroSec_Module<Reason> -- one sentence for one
-- shut door, not two):
--
--   fixture   nothing is wired here at all, so there is nothing to reach
--   safehouse somebody else's, with the option on
--   outside   needs a room, and he is not standing in one
--   closed    a door or window fitted here is shut
--   drawn     a curtain fitted here is not open
--   linked    this machine is already on the list
--   reach     the machine's OWN /dev already has this fixture, cable-free
--   links     the fixture is full (LINKS_MAX)
--   far       past LINK_RANGE
--
-- What he is CARRYING is not asked here, for the reason the module's bag is not
-- asked in fittingRefusal: it is a fact about him and it is asked by each side in
-- its own words (the menu greys with the count, the server refuses).

-- Would SCeroSecDevices' own building walk (server/CeroSec/SCeroSecDevices.lua)
-- have listed this fixture on the machine's /dev without any cable at all? If
-- so, a link buys nothing and would list the same device twice.
--
-- DELIBERATELY NARROW, because a wrong "reach" is the one refusal that leaves
-- a survivor no way at all to reach a fixture: it only fires when BOTH squares
-- carry a real building, never a guess.
--
-- The machine's square asks getRoom() ~= nil, not isInARoom() -- a player-built
-- base is isInARoom() true with getBuilding() nil on every one of its squares
-- ("a base has no building and no rooms", SCeroSecDevices.lua), and the
-- building walk never runs for one, so a base machine never reaches this far.
--
-- The fixture's square is its own, and for one of the three envelope kinds
-- (needsInside, above) its opposite square too -- a door, window or curtain
-- IS the wall, and which of its two squares carries the room depends on the
-- wall: a north or west door stands on its OWN square and SCeroSecDevices'
-- building walk finds it there, a south or east door stands on its NEIGHBOUR
-- and the walk finds it off that square instead (SCeroSecDevices.lua:913-919,
-- the far-edge scan). Asking only object:getSquare() left every south and
-- east exterior door unrefused: the walk had already listed the fixture off
-- the far side. Checking either side is the same rule the walk itself reads
-- by, never a second geometry.
--
-- getBuilding() is getRoom() and then IsoRoom.getBuilding
-- (javap -c zombie.iso.IsoGridSquare.getBuilding, offsets 0-15,
-- SCeroSecDevices.lua), so it answers nil for a chunk that has not streamed in
-- as much as for a square with no building at all -- either way, nil is "do
-- not refuse", never "refuse".
--
-- Mirror of CeroSecDevices.find's no-building branch and scanOutdoorSquare
-- (SCeroSecDevices.lua:1400-1470): the report this answers is a generator five
-- squares from a computer sitting outside, wired to nothing, already on that
-- machine's /dev -- and the cable menu still offered to sell a wire for it.
--
-- Copies scanOutdoorSquare's own gates, one by one:
--   same z            the radius loop never changes z (SCeroSecDevices.lua:1462-1466)
--   a SQUARE           r tiles each way, not a circle, bounds included (:1462-1466)
--   no room            the fixture's OWN square must have none (:1402) -- a
--                      square with a room belongs to that room's building,
--                      radius or not
--
-- What it does NOT copy: scanOutdoorSquare also keeps a wall fixture (door,
-- window, curtain, light switch) whose sprite FACES a room out of the walk
-- (facesARoom, SCeroSecDevices.lua:1370-1379), which means reading
-- MoveType/Facing/attachedN off the sprite the way `faces` does
-- (SCeroSecDevices.lua:1050-1069). That reading is not repeated here, so a
-- wall fixture answers doubt, not "reach": a cable it did not need costs
-- wire, but a wrongly claimed "reach" the walk never actually grants would
-- grey the row AND get refused, leaving the survivor no way to the fixture at
-- all -- the one mistake this function exists to never make.
local function outdoorReachRefusal(object, mx, my, mz)
	if needsInside(object) or CeroSecModules.isLightSwitch(object) then return nil end
	local ownSquare = object:getSquare()
	if ownSquare == nil then return nil end
	if ownSquare:getZ() ~= mz then return nil end
	if ownSquare:getRoom() ~= nil then return nil end
	local r = CeroSecModules.OUTDOOR_RADIUS
	if math.abs(ownSquare:getX() - mx) > r or math.abs(ownSquare:getY() - my) > r then
		return nil
	end
	return "reach"
end

local function reachRefusal(object, mx, my, mz)
	-- Cable-only, decided in game: neither walk below ever lists a generator by
	-- proximity any more (SCeroSecDevices.classify's allowGen,
	-- SCeroSecDevices.lua:~637), building or radius, so "reach" would grey a
	-- cable this machine can never actually save -- the fixture stays offered,
	-- for the one wire that reaches it.
	if CeroSecModules.isGenerator(object) then return nil end
	if getCell == nil then return nil end
	local cell = getCell()
	if cell == nil then return nil end
	local machineSquare = cell:getGridSquare(mx, my, mz)
	if machineSquare == nil then return nil end
	if machineSquare:getRoom() == nil then
		return outdoorReachRefusal(object, mx, my, mz)
	end
	local building = machineSquare:getBuilding()
	if building == nil then return nil end

	local ownSquare = object:getSquare()
	if ownSquare ~= nil and ownSquare:getBuilding() == building then return "reach" end
	-- Mirror of SCeroSecDevices.scanFarEdge (SCeroSecDevices.lua:1073): the walk
	-- only lists a south/east envelope fixture off its OPPOSITE square when its
	-- OWN square has no room -- a door whose own square has a room is the
	-- neighbouring building's wall (SCeroSecDevices.lua:~1109-1112) and never
	-- makes it into this building's /dev. Checking the opposite square without
	-- that same guard claimed "reach" for a door this machine's /dev never
	-- lists, which is worse than the original unrefused door: it greys the row
	-- AND the server refuses, so the machine loses its only way to the door.
	if needsInside(object) and ownSquare ~= nil and ownSquare:getRoom() == nil then
		local opposite = object:getOppositeSquare()
		if opposite ~= nil and opposite:getBuilding() == building then return "reach" end
	end
	return nil
end

function CeroSecModules.linkRefusal(object, x, y, z, playerObj)
	if object == nil or playerObj == nil then return "fixture" end
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return "fixture"
	end

	-- A cable to a bare fixture buys nothing: a link is what carries a MODULE's
	-- device to a machine, and a fixture with no module on it has no device for
	-- either of them to argue about.
	if not CeroSecModules.anyFitted(object) then return "fixture" end

	-- Whose house, first and for fittingRefusal's own reason.
	local house = houseRefusal(object, playerObj)
	if house ~= nil then return house end

	-- Then the envelope: wiring a closed door is the same job as unscrewing a
	-- strike from it, and asks the same question (envelopeRefusal, above).
	local envelope = envelopeRefusal(object, playerObj)
	if envelope ~= nil then return envelope end

	local square = object:getSquare()
	if square == nil then return "fixture" end
	local links = CeroSecModules.linksOn(object)
	if CeroSecModules.linkIndexOf(links, x, y, z) ~= nil then return "linked" end
	local reach = reachRefusal(object, x, y, z)
	if reach ~= nil then return reach end
	if #links >= CeroSecModules.LINKS_MAX then return "links" end
	if CeroSecModules.linkWire(square:getX(), square:getY(), square:getZ(), x, y, z)
			> CeroSecModules.LINK_RANGE then
		return "far"
	end
	return nil
end

-- TAKING ONE OFF, which asks less -- and asks one thing differently.
--
-- Nothing is paid, so nothing is counted: no range, no room on the fixture, and
-- nothing about what he is carrying. What is left is whose house it is, for the
-- reason above read the other way -- a stranger must not be able to cut your door
-- off your machine -- and that there is a cable here at all.
--
-- AND A BARE FIXTURE IS NOT REFUSED HERE, where running a cable to one is. A module
-- that has come off a fixture somebody had cabled leaves the cable run and the reel
-- owed: refusing the unlink would be a survivor who can only get his wire back by
-- taking the door down.
--
--   fixture   no fixture, or no cable from that machine to this one
--   safehouse somebody else's, with the option on
function CeroSecModules.unlinkRefusal(object, x, y, z, playerObj)
	if object == nil or playerObj == nil then return "fixture" end
	local house = houseRefusal(object, playerObj)
	if house ~= nil then return house end
	-- The same envelope taking a module off asks: unjamming a door is the
	-- price of unscrewing a strike from it, and of unwiring it too.
	local envelope = envelopeRefusal(object, playerObj)
	if envelope ~= nil then return envelope end
	if CeroSecModules.wireOf(object, x, y, z) == nil then return "fixture" end
	return nil
end

-- What the trade costs. The HIGHEST level of the modules on that fixture, which is
-- the one reading that cannot lock a survivor out of his own work: anybody who
-- could fit the hardware can cable it, and nobody who could not fit it can
-- re-route somebody else's. A fixture with nothing on it is refused a line earlier
-- and never reaches here, so 0 is a fixture whose modules this build cannot read.
function CeroSecModules.linkSkill(object)
	local fitted = CeroSecModules.installedOn(object)
	local want = 0
	for i = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[i]
		if fitted[module.id] and module.skill > want then want = module.skill end
	end
	return want
end

-- The cable itself, which is the game's own item and not one of ours: vanilla's
-- Base.ElectricWire (media/scripts/generated/items/normal.txt:4518, an
-- Electronics-category normal item weighing 0.1). Thirty of them is three
-- kilograms, which is a reel a survivor notices carrying.
CeroSecModules.WIRE = "Base.ElectricWire"

-- How many he has on him, counted the way vanilla counts an item it is about to
-- consume: ItemContainer.getCountTypeRecurse(String), which walks the bags inside
-- the bag -- the call vanilla's own menu makes for exactly this
-- (ISWorldObjectContextMenu.lua:1895). A name with a dot in it is matched against
-- getFullType (ItemContainer.compareType, offsets 0-31), which is why the full
-- type is what is asked for.
function CeroSecModules.wireCount(inv)
	if inv == nil or type(inv.getCountTypeRecurse) ~= "function" then return 0 end
	return tonumber(inv:getCountTypeRecurse(CeroSecModules.WIRE)) or 0
end

--
-- What a machine sees through one object's modules
--
-- Asked by the discovery, once per object, and the shape of the answer is the
-- shape of the feature:
--
--   door     the operator, and nothing else, gives a door that OPENS
--   door ro  a contact alone gives a door that can only be read
--   lock     the strike
--   win  ro  a contact on a window: the sash and the latch, READ. The latch
--            stopped being writable when the hardware gate came in and the
--            reason it gave was wrong; the reason it is still read-only is that
--            a contact is a sensor and senses.
--   window   the window operator, which is what MOVES a sash
--   curtain  the curtain motor, on an IsoCurtain or on a door's own sheet
--   stove    the appliance switch, on an oven, a microwave or a coffee machine
--   washer   the same switch, on a washer, a dryer or a combination machine
--   gen      the generator switch
--   light    the relay
--   tv       the tuner control, on a television
--   rx       the same control, on a radio set -- which keeps its own /dev/radio0
--            beside it when it is the machine's TNC, because a receiver's dial
--            and an aerial's are two questions
--
-- `ro` is carried right through to the device node, which is born 440 for it and
-- refuses a write in the engine (CeroSecOSDev). A module fitted later moves the
-- node from read-only to read-write on the next command, and it keeps its number
-- (CeroSecDevices.number): the key a number hangs on is where the device is and
-- which kind it is, and neither of those moved when the hardware did.
--
-- That decision is the discovery's and is made in SCeroSecDevices.classify, one
-- layer up from here, because it is the only place that knows what a kind is.
--
