if isClient() then return end

require "CeroSec/CeroSecContent"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecModules"
require "CeroSec/SCeroSecDevices"
require "CeroSec/SCeroSecNet"

--
-- THE PLACES THAT WERE ALREADY AUTOMATED
--
-- A shop whose lights go out at nine as a survivor walks up to it. A bank whose
-- vault bolts itself at six. A station that reads its own schedule out on the hour.
-- Nobody threw a switch: an electrician screwed the relays on in 1991, somebody put
-- a crontab on the machine, and when the road shut the machine was left running.
--
-- Everything a premises needs for that already existed, one piece at a time, and
-- this file is the three of them agreeing:
--
--   * the hardware -- a relay on a light switch, a contact and a strike on a door
--     (CeroSecModules), which is what puts a fixture under /dev at all when
--     HardwareRequired is on;
--   * the crontab -- already written by the catalogue onto the desk of whoever's
--     job it was (CeroSecContent.placeCron);
--   * a machine that is ON, because a crontab on a dark machine is a piece of
--     paper. cron's pass walks every machine that is on, once a game minute, and
--     needs nothing of the world (SCeroSecSystem:checkCron) -- so the lights really
--     do go off at 21:00, and what the player is standing near is the only thing
--     that decides whether he sees it. A timer nobody watches does nothing, exactly
--     like the real one.
--
-- WHEN THE DECISION IS MADE, and it is the whole design: the FIRST time a computer
-- sprite of that premises is created in the save, and never again.
--
-- The game has its own word for "created for the first time in this save" and it is
-- the pair of registrations at the foot of SCeroSecSystem.lua. Proved on
-- projectzomboid.jar 42.20.4, because everything here hangs off it:
--
--   zombie.Lua.MapObjects keeps two HashMaps, `onNew` and `onLoad`, and
--   OnNewWithSprite(String, LuaClosure, int) adds to the first.
--
--   MapObjects.newGridSquare(IsoGridSquare) walks EVERY object on the square
--   (the loop at offsets 60-306), takes that object's own sprite name
--   (119-143, the sprite's name or the object's spriteName field), looks it up
--   in `onNew` (158-165) and calls every closure registered for it with that
--   ONE object as the single argument (params[0] = object at 178-183, then
--   LuaCaller.protectedCallVoid at 200-219). So a registration is per SPRITE
--   NAME and a call is per OBJECT: one computer, one call.
--
--   zombie.iso.IsoChunk.doLoadGridsquare calls newGridSquare only
--   `if (this.addZombies)` (offsets 851-859) and loadGridSquare unconditionally
--   (862-864). `addZombies` is set in the LoadFromMap path -- the chunk built out
--   of the map for the first time -- and `isNewChunk()` is a getter for that very
--   field. A chunk read back out of the save has it false, so OnLoad fires and
--   OnNew does not.
--
--   THE ONE CAVEAT, said plainly: addZombies is only set when
--   Core.addZombieOnCellLoad is true, and Core.setGameMode clears it for the
--   game modes "Tutorial" and "LastStand". In those two nothing here ever
--   happens -- no premises is ever automated -- which is the right answer for a
--   tutorial and is written down rather than discovered.
--
-- WHAT THE HOOK IS ASKED FOR, and what it is NOT. It is asked for one bit: this
-- square has just been made, so write it down (SCeroSecSystem:markBorn sets
-- `born` on the machine, and it is a SAVED field so a player who quits in the
-- minute afterwards does not lose the question). Everything that needs the WORLD --
-- which premises this is, what its rooms are called, whether there is a wire at the
-- square -- is asked one minute later, on the sweep, where this mod already asks
-- every world question and where the chunk is settled. That is not caution for its
-- own sake: not one of vanilla's own fourteen MapObjects handlers asks a square for
-- its room or its building, so there is no proof that either answers during
-- newGridSquare, and an unproven call is a nil call in a callback (see the
-- sources-of-truth rule in docs/CONTRIBUTING.md).
--
-- WHERE THE ANSWER LIVES. On the system, in `auto`, saved with the save exactly as
-- `notes` and `desks` are and for the same reason: the computers of one premises are
-- created over many sessions and a table in memory would roll again.
--
--   system.auto[premisesKey] = {
--     on      = true / false   -- was this premises automated at all
--     machine = { x=, y=, z= } -- which of its computers was left running
--     wired   = true           -- and its fixtures have all been fitted
--     rooms   = { [tag] = true } -- the rooms already walked, while it is not
--                                -- finished; dropped the minute it is
--     later   = { {x=,y=,z=} }  -- fixtures still owed their cable, under
--                                -- RequireWiring; dropped once it is spent
--                                -- (cablePreFitted, resolveLater)
--   }
--
-- A list, so a table reached by a NUMERIC key: KahluaTableImpl.save writes
-- those as it writes any other (docs/notes/modules-proofs.md, the recursion
-- at type byte 2).
--
-- `on = false` is written and kept, and that is deliberate: the roll is a hash and
-- would answer the same next time, but a premises with no entry is a premises that
-- has never been asked, and the two have to be told apart or a change to the odds
-- would re-roll a county somebody is already living in.
--

CeroSecAuto = {}

-- The system's page, made on the first question asked of it.
function CeroSecAuto.page(system)
	if type(system) ~= "table" then return {} end
	if type(system.auto) ~= "table" then system.auto = {} end
	return system.auto
end

-- One premises' entry, or nil for a premises nothing has decided about. Never makes
-- one: "has this been asked" is the question half the callers here are asking.
function CeroSecAuto.recordOf(system, b1, b2)
	if type(system) ~= "table" or type(system.auto) ~= "table" then return nil end
	local record = system.auto[CeroSecContent.premisesKey(b1, b2)]
	if type(record) ~= "table" then return nil end
	return record
end

-- Is the machine at x, y, z the one this premises left running? What the prefill
-- asks, so that the desk it builds is the desk of whoever's crontab it is
-- (CeroSecContent.prefill, `opts.auto`).
function CeroSecAuto.isMachineAt(system, b1, b2, x, y, z)
	local record = CeroSecAuto.recordOf(system, b1, b2)
	if record == nil or record.on ~= true then return false end
	local at = record.machine
	if type(at) ~= "table" then return false end
	return at.x == x and at.y == y and at.z == z
end

--
-- THE HARDWARE
--

-- What an electrician fitted to one fixture before the outbreak, as module ids.
--
--   a light switch   a relay, which is the only thing a machine can throw
--   a window         a contact, and there is no second module for one: the game
--                    has no call that moves a sash without a survivor standing at
--                    it (docs/notes/modules-proofs.md, 4)
--   a door           a contact always, and a strike where the lock means anything
--                    (CeroSecModules.fitsOn -- exterior, or a built door)
--
-- AND NEVER AN OPERATOR. A door operator is a motor, an arm and a limit switch, and
-- a 1993 shop did not have one on the stockroom door: what it had was a magnetic
-- contact on the frame to know the door was shut and an electric strike to bolt it.
-- A building that opened its own doors would also be a building that opens them for
-- the dead.
--
-- AND NONE OF THE MOTOR RUNG'S FOUR, for that same sentence four more times. A
-- window that opens itself is a hole in the wall the dead can walk through; a
-- curtain that opens itself is the same thing for a survivor trying to hide; a
-- stove that lights itself is a kitchen fire nobody is standing in; and a
-- generator that starts itself is a noise in an empty street. Every one of those
-- is a thing a PLAYER may decide to build, with a box he carried and a
-- screwdriver -- and it is not a thing the world does to him on a map he has
-- never been to. The list this function answers is therefore unchanged, and the
-- new fixtures fall through it: isFittable now finds a stove and a generator, so
-- the pre-fitting walk sifts them, and `fit` answers false and leaves them alone.
function CeroSecAuto.modulesFor(object)
	local out = {}
	if CeroSecModules.isLightSwitch(object) then
		out[#out + 1] = "relay"
		return out
	end
	if CeroSecModules.isWindow(object) then
		out[#out + 1] = "contact"
		return out
	end
	if not CeroSecModules.isDoor(object) then return out end
	out[#out + 1] = "contact"
	if (CeroSecModules.fitsOn(object, "strike")) then out[#out + 1] = "strike" end
	return out
end

-- Fit them, through CeroSecModules.setOn and nothing else: the modules a survivor
-- screws on and the modules an electrician screwed on in 1991 are the same boxes in
-- the same table, so the discovery cannot tell them apart and must not be able to.
-- One consequence is chosen rather than tolerated: a pre-fitted module comes off
-- into a survivor's hands and gives him the item, because it is real hardware and
-- Commands.uninstallmodule asks nothing about where it came from.
--
-- The mark goes on LAST and is what makes this happen once (CeroSecModules.PRE_KEY).
function CeroSecAuto.fit(object)
	local ids = CeroSecAuto.modulesFor(object)
	if #ids == 0 then return false end
	local any = false
	for i = 1, #ids do
		if CeroSecModules.setOn(object, ids[i], true) then any = true end
	end
	if not any then return false end
	-- The /dev cache holds what a machine could reach a moment ago, and a fixture
	-- this walk just wired was not on that list. The sweep runs a room at a time
	-- through a whole building, so this is dropped per fixture rather than per
	-- building: the cost is one table thrown away and the alternative is a shop
	-- whose relays do not answer until the minute turns.
	CeroSecDevices.invalidate()
	return CeroSecModules.markPreFitted(object)
end

-- How many rooms of one premises the sweep walks in one game minute. The bound
-- on the whole of this, and it is a bound on ENGINE calls: a room costs its
-- squares and their objects, and eight rooms is the biggest shop in the county
-- twice over. A premises of more rooms than this takes several minutes to finish
-- and that is invisible -- the relays were screwed on in 1991 and nothing a
-- player can see happens at the moment one is written.
CeroSecAuto.ROOMS_PER_MINUTE = 8

-- WHICH ROOMS ARE THIS PREMISES', asked of the machine's own square through the
-- one rule there is about what a premises is (CeroSecNet.premisesOfSquare), and
-- narrowed to the TENANCY only where the premises really is a tenancy: a shop in
-- a mall is the rooms of its own group, and everything else -- a house, a school,
-- a shop with a back office, and a named ZONE inside a bigger building -- is the
-- building's rooms. A zone is not narrowed because its rooms are not a group the
-- room rule knows about, and walking the building's is the conservative answer:
-- more rooms, walked once each, and the fixtures still sifted one by one below.
--
-- nil when the world cannot say, which is a machine whose premises has moved out
-- from under it and a minute where nothing is walked.
local function premisesRoomsOf(square, b1, b2)
	local q1, q2, _, _, kind = CeroSecNet.premisesOfSquare(square)
	if q1 ~= b1 or q2 ~= b2 then return nil end
	local building = square:getBuilding()
	if building == nil then return nil end
	local def = building:getDef()
	if def == nil then return nil end
	if kind == CeroSecOS.PREMISES_ROOM then
		return CeroSecNet.tenantOfRoom(CeroSecNet.tenanciesOf(def),
			CeroSecNet.roomDefAt(square))
	end
	return CeroSecNet.roomsOf(def)
end

-- AND UNDER CeroSec.RequireWiring, THE CABLE TO THE MACHINE. With that option on
-- nothing reaches /dev without a cable (CeroSecDevices.find, skipFixtures), and a
-- pre-fitted fixture is no exception: the electrician of 1991 ran the wire as well
-- as the box. Off (the default), no cable is written -- the building walk already
-- finds the fixture for free, and a cable would be four fields of modData on every
-- fixture of every automated shop in the county buying nothing.
--
-- Commands.linkmodule's own order, both ends or neither: the machine's room
-- (LINKS_PER_MACHINE) is asked first, the fixture's end is written, then the
-- machine's. The price is CeroSecModules.linkWire's, the one the menu quotes, so
-- CeroSec.FreeWiring and the nested-basement waiver apply as they would to a
-- survivor's cable -- and what an unlink gives back is that price, for the reason
-- a pre-fitted module comes off as an item (CeroSecAuto.fit): it is real hardware.
--
-- The range is checked HERE and not left to linkOn: linkOn only bounds the price,
-- and under FreeWiring the price is 0 whatever the distance. A fixture past the
-- range, a fixture already carrying LINKS_MAX cables, a machine already carrying
-- LINKS_PER_MACHINE: no cable, no error, and the sweep goes on. The fixture is
-- marked pre-fitted all the same, so the walk does not come back for it; a
-- survivor can run that cable himself, which is what a fixture the electrician
-- could not reach is for.
--
-- GOING FORWARD ONLY. A premises the walk finished (`wired`) before this existed,
-- or while the option was off, is not walked again when a server switches it on,
-- and a room already in `record.rooms` is not either: re-walking would need a new
-- key in the save and a second walk of every automated shop in the county. Those
-- fixtures then stand exactly where a survivor's own fitted-but-uncabled fixture
-- stands under the option -- off /dev until a cable is run -- which is the one
-- rule the option has, with no exception for who screwed the box on.
--
-- A MACHINE WITH NO STATE YET is the first walk of all: the decision fits the
-- hardware BEFORE it switches the machine on (CeroSecAuto.decide says why), and
-- the state is made by that switching on -- asking osState here would make it
-- first and cost the machine its prefill (SCeroSecObject:turnOn, `bare`). So
-- that answer is "later", and the walk writes the fixture's filing square into
-- the record (`record.later`), SAVED, because the machine may not come up in
-- that minute at all -- a shop first found with its grid already gone -- and a
-- list in memory would be lost with the minute. The cables are run by the next
-- turnOn of THAT machine that succeeds, whenever it comes: the decision's own a
-- moment later, or a survivor's with a generator a month after
-- (CeroSecAuto.resolveLater, called from SCeroSecObject:turnOn).
--
-- A SAVE FROM BEFORE `later` has no such field and reads it as nothing owed: a
-- shop found dark under the old build keeps its fixtures uncabled, as it did.
--
-- true when both ends were written; false and "later" when only the missing
-- state stopped it.
local function cablePreFitted(luaObject, object)
	if not CeroSecModules.wiringRequired() then return false end
	local fSquare = object:getSquare()
	if fSquare == nil then return false end
	local state = luaObject.os
	if type(state) ~= "table" then return false, "later" end
	local fx, fy, fz = fSquare:getX(), fSquare:getY(), fSquare:getZ()
	local mx, my, mz = luaObject.x, luaObject.y, luaObject.z
	if not CeroSecModules.nestedFree(fx, fy, fz, mx, my, mz)
			and CeroSecModules.linkSpan(fx, fy, fz, mx, my, mz)
				> CeroSecModules.linkRange() then
		return false
	end
	-- The machine's book names the FILING square, a gate's anchor (Commands.
	-- linkmodule says why).
	local ax, ay, az = CeroSecModules.placeOf(object)
	if ax == nil then ax, ay, az = fx, fy, fz end
	local book = CeroSecOS.linkSquares(state)
	if CeroSecOS.linkAt(book, ax, ay, az) == nil
			and #book >= CeroSecOS.LINKS_PER_MACHINE then
		return false
	end
	local wire = CeroSecModules.linkWire(fx, fy, fz, mx, my, mz)
	if not CeroSecModules.linkOn(object, mx, my, mz, wire) then return false end
	CeroSecOS.addLink(state, ax, ay, az)
	return true
end

-- Fit whatever of this premises' fixtures the world can answer for right now, and
-- write down that it is finished when every room of it has been walked once.
--
-- THE WALK IS THE PREMISES' ROOMS, a few of them per minute, and each room is
-- walked ONCE IN THE LIFE OF THE PREMISES (CeroSecDevices.fixturesInRooms). The
-- fixtures are then sifted back down to this premises all the same: the sift asks
-- the one rule there is about what a premises is, of each fixture's own square
-- (CeroSecNet.premisesOfSquare) -- and of fixtures only, never of every square of
-- the building, because that question costs a zone lookup and there are four
-- hundred squares to a shop and a dozen fixtures. A room of the building that is
-- nobody's, or another tenancy's, therefore grows no relays even where the room
-- list is the building's.
--
-- IN ANY CHUNK ORDER, and that is what this is for. A building's rooms come into
-- the world as the streamer brings their chunks in, and a RoomDef whose chunks are
-- away answers no live room at all. This used to walk the WHOLE building every
-- minute and only finish on a pass where every room of it answered at once -- which
-- on a five-hundred-room mall is a pass no player's chunk radius ever gives, so the
-- mall was re-walked room by room, square by square, object by object, every game
-- minute for as long as the carrier machine was on. Now a room that answered is
-- written down (`record.rooms`, the set of tags) and never asked again, and the
-- premises is finished when the set covers it -- which happens whatever order the
-- chunks arrive in and cannot fail to happen.
--
-- THE SET IS SPENT WHEN IT IS FULL and is dropped then, so what a finished premises
-- costs in gos_cerosec.bin is the three fields it always cost. It is read with a
-- default and written only under a record that is not `wired` (CeroSecAuto.wire
-- returns before this for one that is), so a save from before this change -- which
-- has no set and may have `wired` already -- reads exactly as it did.
--
-- Answers how many fixtures were fitted. Those whose cable waits on the
-- machine's state go into `record.later` (cablePreFitted says why).
--
-- By the FILING square (CeroSecModules.placeOf), the one a machine's cable book
-- names too: a gate's walked leaf is re-made on another square at every toggle
-- and its anchor is not. Once per square: two fixtures on one square (a switch
-- and a window) are one entry, and resolveLater tries every fixture on it.
local function owe(record, object)
	local x, y, z = CeroSecModules.placeOf(object)
	if x == nil then return end
	if type(record.later) ~= "table" then record.later = {} end
	local owed = record.later
	for i = 1, #owed do
		local at = owed[i]
		if at.x == x and at.y == y and at.z == z then return end
	end
	owed[#owed + 1] = { x = x, y = y, z = z }
end

local function wirePremises(luaObject, b1, b2, record)
	-- No square, no world to ask: a machine whose chunk is away costs the two table
	-- lookups in CeroSecAuto.wire and this one test, and is asked again next minute.
	local square = luaObject:getSquare()
	if square == nil then return 0 end
	local rooms = premisesRoomsOf(square, b1, b2)
	if rooms == nil or #rooms == 0 then return 0 end

	if type(record.rooms) ~= "table" then record.rooms = {} end
	local done = record.rooms
	local list, walked = CeroSecDevices.fixturesInRooms(rooms, done,
		CeroSecAuto.ROOMS_PER_MINUTE)
	for i = 1, #walked do done[walked[i]] = true end

	local fitted, cabled = 0, 0
	for i = 1, #list do
		local object = list[i].object
		if not CeroSecModules.preFitted(object) then
			local q1, q2 = CeroSecNet.premisesOfSquare(list[i].square)
			if q1 == b1 and q2 == b2 then
				if CeroSecAuto.fit(object) then
					fitted = fitted + 1
					local ok, why = cablePreFitted(luaObject, object)
					if ok then
						cabled = cabled + 1
					elseif why == "later" then
						owe(record, object)
					end
				end
			end
		end
	end
	-- Once for the walk and not per cable: the menu counts a machine's cables off
	-- this mirror (Commands.linkmodule), and the /dev cache is dropped again
	-- because fit dropped it BEFORE the cable was on.
	if cabled > 0 then
		luaObject:publishOS()
		CeroSecDevices.invalidate()
	end

	-- Finished only when the SET covers the premises. Counted over the room list
	-- and not over the set: a basement spawned under the building after the fact
	-- adds a room, and a count of tags would have said "done" with it unwalked.
	local whole = true
	for i = 1, #rooms do
		if rooms[i].tag == nil or not done[rooms[i].tag] then whole = false end
	end
	if whole then
		record.wired = true
		record.rooms = nil
	end
	if fitted > 0 then
		CeroSec.log("the premises " .. b1 .. "." .. b2 .. " was already wired: "
			.. fitted .. " fixture(s) got their modules, " .. cabled .. " a cable")
	end
	return fitted
end

-- The cables the first walk could not run for want of a state, run once the
-- machine is up and has one. Same rule, same skips, same publish. Called from
-- SCeroSecObject:turnOn, every power-on of every machine, once the state and
-- the network record exist -- so it is written to cost a machine that carries
-- no premises two table lookups, the same door CeroSecAuto.wire uses.
--
-- ONE PLACE, and settle does not call it a second time: settle's own turnOn is
-- a turnOn, so its cables are run inside it and the list is spent by then.
--
-- THE LIST IS SPENT IN ONE GO. The state exists now, so cablePreFitted can no
-- longer answer "later": every other false is the range, LINKS_MAX or
-- LINKS_PER_MACHINE, which the next power-on would answer the same, and the
-- survivor's cable to run (see the head of cablePreFitted). So is a square
-- with no pre-fitted fixture on it any more, which somebody took down. What is
-- KEPT is a square that is not loaded: a fixture in a chunk that is away is
-- still a fixture, exactly as scanLinked keeps a cable it cannot see.
--
-- A fixture a survivor cabled to this machine himself in the meantime is
-- refused by linkOn ("linked") and writes nothing.
--
-- Answers how many cables were run.
function CeroSecAuto.resolveLater(system, luaObject)
	if type(system) ~= "table" or type(system.auto) ~= "table" then return 0 end
	local net = CeroSecOS.netRecord(luaObject.os)
	if net == nil then return 0 end
	local record = CeroSecAuto.recordOf(system, net.b1, net.b2)
	if record == nil or type(record.later) ~= "table" then return 0 end
	if not CeroSecAuto.isMachineAt(system, net.b1, net.b2,
			luaObject.x, luaObject.y, luaObject.z) then
		return 0
	end
	local owed, kept = record.later, {}
	local cell = nil
	if getCell ~= nil then cell = getCell() end
	local cabled = 0
	for i = 1, #owed do
		local at = owed[i]
		if type(at) == "table" and type(at.x) == "number"
				and type(at.y) == "number" and type(at.z) == "number" then
			local square = cell ~= nil and cell:getGridSquare(at.x, at.y, at.z) or nil
			if square == nil then
				kept[#kept + 1] = { x = at.x, y = at.y, z = at.z }
			else
				local objects = square:getObjects()
				for k = 0, (objects ~= nil and objects:size() or 0) - 1 do
					local object = objects:get(k)
					if CeroSecModules.isFittable(object)
							and CeroSecModules.preFitted(object)
							and cablePreFitted(luaObject, object) then
						cabled = cabled + 1
					end
				end
			end
		end
	end
	if #kept > 0 then record.later = kept else record.later = nil end
	if cabled > 0 then
		luaObject:publishOS()
		CeroSecDevices.invalidate()
		CeroSec.log("the premises' machine at " .. luaObject.x .. "," .. luaObject.y
			.. "," .. luaObject.z .. " is up: " .. cabled .. " cable(s) run to it")
	end
	return cabled
end

-- The sweep's own door into the walk above, and it is written to cost NOTHING in a
-- save where no premises has ever been automated: two table lookups and a read of a
-- record the machine already carries. The premises comes off the machine's own
-- network record (CeroSecOS.netRecord -- two bytes written at the power-on, no
-- world involved) rather than being asked of the map again, because this is walked
-- for every computer in the county once a game minute.
function CeroSecAuto.wire(system, luaObject)
	if type(system) ~= "table" or type(system.auto) ~= "table" then return 0 end
	local net = CeroSecOS.netRecord(luaObject.os)
	if net == nil then return 0 end
	local record = CeroSecAuto.recordOf(system, net.b1, net.b2)
	if record == nil or record.wired == true then return 0 end
	-- "A premises that rolled no is left alone" is carried THREE times -- here, in
	-- isMachineAt, and by settle never filling the machine slot under a `no` -- and
	-- that is written down because it changes what a green mutation means: breaking any
	-- ONE of the three leaves the suite green, and a reader who did not know would go
	-- looking for a hole in the bench instead of a second carrier. Breaking all three
	-- turns tests/window_test.lua's "no fixture is wired" red, which is the assertion
	-- that owns the rule. All three are kept: the cost is a comparison and the failure
	-- they stand against is a building that wires itself behind the player.
	if record.on ~= true then return 0 end
	if not CeroSecAuto.isMachineAt(system, net.b1, net.b2,
			luaObject.x, luaObject.y, luaObject.z) then
		return 0
	end
	-- Only the count: a machine this far has a network record, and so a state,
	-- so nothing here waits on one.
	local fitted = wirePremises(luaObject, net.b1, net.b2, record)
	return fitted
end

--
-- THE DECISION
--

-- May this machine be the one the premises left running? A display model on a
-- showroom's sales floor may not, and it is the one exception there is: the machine
-- with the timer on it is the shop's own machine in the back, not a computer in the
-- window with the dealer's demonstration disk on it. Which is also what the desk
-- register already says such a machine is (CeroSecContent.deskRole).
local function mayCarry(luaObject, id)
	if id ~= CeroSecContent.SHOWROOM then return true end
	return not CeroSecContent.isFloorRoom(
		CeroSecModules.roomName(luaObject:getSquare()))
end

-- WAS THIS PREMISES AUTOMATED, asked once in the life of the premises and then
-- acted on. Called from the minute sweep for a machine whose square was created in
-- this save (`born`), and from nowhere else.
--
-- The flag is cleared FIRST and unconditionally. Every refusal below is an ANSWER
-- to the question -- the option is off, the machine is in no building, the premises
-- rolled a no -- and a flag left standing would ask the same question again next
-- minute, for ever, of a machine in a player's own base.
--
-- true when this machine was switched on as its premises' automated one.
function CeroSecAuto.settle(system, luaObject)
	luaObject.born = nil
	-- And out of the sweep's list of machines with a question outstanding: the
	-- question is being answered here, whatever the answer turns out to be
	-- (SCeroSecSystem:indexMachine).
	luaObject:reindex()
	if system == nil then return false end
	-- The same gate the prefill and the papers wear, and read through the same
	-- function: a world with PrefilledMachines off has nothing already on its
	-- machines, and a building that wires itself would be exactly that.
	if not CeroSecContent.enabled() then return false end

	-- Which premises, and what its profile is -- both by the rules that already
	-- exist and in the order the prefill asks them in, because the profile this
	-- decides on has to be the profile the prefill then builds
	-- (SCeroSecObject:prefill). A machine in no building is in no premises: a
	-- player's own base is never automated and never asked again.
	local b1, b2, _, pz, pk = CeroSecNet.premisesOf(luaObject)
	if b1 == nil then return false end
	local id = CeroSecContent.profileFor(pz,
		CeroSecNet.premisesRooms(luaObject:getSquare(), pz, pk))

	local page = CeroSecAuto.page(system)
	local key = CeroSecContent.premisesKey(b1, b2)
	local record = page[key]
	if type(record) ~= "table" then
		record = { on = CeroSecContent.automated(system:secret(), b1, b2, id) }
		page[key] = record
		CeroSec.log("the premises " .. b1 .. "." .. b2 .. " (" .. id .. ") was "
			.. (record.on and "automated" or "not automated") .. " before the outbreak")
	end
	if record.on ~= true then return false end

	-- WHICH of its computers, and it is the first one created that may carry it. A
	-- showroom is the one premises where that is not simply the first: a machine on
	-- the sales floor leaves the slot empty and the first back-room machine created
	-- takes it. Filling an empty slot is not a second decision and re-rolls nothing.
	if type(record.machine) ~= "table" then
		if not mayCarry(luaObject, id) then return false end
		record.machine = { x = luaObject.x, y = luaObject.y, z = luaObject.z }
	end
	if not CeroSecAuto.isMachineAt(system, b1, b2,
			luaObject.x, luaObject.y, luaObject.z) then
		return false
	end

	-- The hardware BEFORE the machine, and the order is the point: cron's pass is
	-- the second half of the same minute hand (Events.EveryOneMinute calls
	-- checkPower and then checkCron), so a crontab line that comes due this minute
	-- has to find /dev already holding the lights. It is also fitted whether or not
	-- the machine then comes up: the relays were screwed on in 1991 and a grid that
	-- went down does not unscrew them, so a survivor who brings a generator to a
	-- dead shop finds a building that answers.
	wirePremises(luaObject, b1, b2, record)

	-- And the machine, through the ordinary power check and no other door: turnOn
	-- refuses a square with no wire at it, so a premises whose grid is gone stays
	-- dark and nothing here fires. That is not a failure to work around -- no grid,
	-- no automation -- and it is not retried: what the first walk wired stays wired,
	-- and the machine is a machine somebody can switch on by hand like any other.
	if not luaObject:turnOn() then
		CeroSec.log("the automated machine at " .. luaObject.x .. "," .. luaObject.y
			.. "," .. luaObject.z .. " has no power and stays off")
		return false
	end
	CeroSec.log("the machine at " .. luaObject.x .. "," .. luaObject.y .. ","
		.. luaObject.z .. " was left running by its premises, with its crontab")
	-- Up, so it has a state now, and the cables the walk above had to leave
	-- were run by that turnOn itself (CeroSecAuto.resolveLater): not here too.
	return true
end
