if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSNet"

--
-- The link layer, and the sessions on it.
--
-- The engine knows what a name means, what an address looks like and what a
-- trust file says. It does not and cannot know whether two computers can hear
-- each other, because that is a question about the WORLD: which building each
-- one stands in, and whether either has power. This file answers it, and it is
-- the only half of the network that knows there is a game.
--
-- There are two links, and the promise the manual made about the second one is
-- kept here and nowhere else:
--
--   * ETHERNET (reachable): a length of coax between the computers of ONE
--     PREMISES, both switched on. Every r-command goes down it and nothing else.
--   * THE TELEPHONE (reachablePhone): one line per PREMISES, one call at a time,
--     the county's exchange alive, both machines on. Distance does not matter and
--     neither does which premises is which -- that is what a telephone IS.
--
-- A premises is a shop inside a mall or a whole house, and which it is comes out
-- of the map (CeroSecNet.premisesOf below). Both links come off the same two
-- bytes, so two shops in one mall are two segments and two telephone lines.
--
-- The second one added one command (cu) and one answer here; it changed no other
-- command, which is what "a new kind of link and not a new command to learn"
-- meant.
--
--
-- WHY A MACHINE ANSWERS WITH ITS CHUNK UNLOADED
--
-- The whole of this rung rests on one fact about the server, so it is written
-- down here rather than assumed. SGlobalObjectSystem holds every global object
-- of its own kind for the whole map, not the loaded part of it:
--
--   * zombie.globalObjects.SGlobalObjects reads gos_<name>.bin whole at server
--     start and hands the objects to the Lua system, which builds one Lua object
--     per global object (SGlobalObjectSystem:initLuaObjects, called from
--     loadLuaObjects) -- so getLuaObjectCount() is every computer in Knox
--     County that has ever been switched on, not every computer in memory.
--   * SGlobalObject:getIsoObject() answers nil for one whose chunk is not
--     loaded: it goes through the cell's grid square, and an unloaded square is
--     not there. That is exactly why SCeroSecObject guards every call on it.
--
-- So a machine's DISK, its power flag and the record of its address are all
-- readable whatever the streamer is doing, and only three things on this rung
-- need the chunk: the power check (a square), /dev (the objects on the squares)
-- and working out which building a computer stands in. The first two already
-- guard themselves; the third is done once, when the machine is switched on,
-- and the answer is written into the machine's own state (CeroSecOS.netRecord)
-- so that nothing ever has to ask again.
--
-- tests/window_test.lua has a machine whose getIsoObject() and getSquare() both
-- answer nil and which still answers ruptime, ping and rlogin.
--

CeroSecNet = CeroSecNet or {}

-- The kind of zone a premises is tagged with. ZombiesType is the spawner's own
-- kind, and it is the one a shop inside a mall carries.
CeroSecNet.PREMISES_TYPE = "ZombiesType"

--
-- The wire's own log
--
-- Every session this file makes or refuses, in order, bounded. It exists for the
-- debug window's Network tab: a refusal is the one thing about the wire that
-- leaves no trace anywhere -- the pty was never made, nothing was written to a
-- disk, and the line the player read went to a screen that has scrolled -- so
-- "why will this machine not rlogin into that one" is a question nothing could
-- answer after the fact.
--
-- RUNTIME state like the ptys and the jobs beside it, and for the same reason: a
-- server that came back up has no sessions, so it can have no history of them.
-- Nothing reads it but a debug window and nothing is decided by it.
--
CeroSecNet.EVENT_MAX = 50

CeroSecNet.events = CeroSecNet.events or {}
CeroSecNet.eventSeq = CeroSecNet.eventSeq or 0

-- One line. `cmd` is the command that asked (rlogin, rsh, cu, ...), `to` what it
-- asked for, `what` what happened -- which for a refusal is the machine's own
-- refusal line and not a word of this file's invention.
function CeroSecNet.note(luaObject, cmd, to, what)
	CeroSecNet.eventSeq = CeroSecNet.eventSeq + 1
	local from = nil
	if luaObject ~= nil then
		from = tostring(luaObject.x) .. "," .. tostring(luaObject.y)
			.. "," .. tostring(luaObject.z)
	end
	CeroSec.ringPush(CeroSecNet.events, {
		n = CeroSecNet.eventSeq,
		at = getTimestampMs(),
		from = from,
		cmd = tostring(cmd),
		to = to and tostring(to) or "",
		what = tostring(what),
	}, CeroSecNet.EVENT_MAX)
end

-- What a session was asked for, in the words the command was given: a name, an
-- address, a number or a callsign, whichever of the four this one is.
local function askedFor(data, radio)
	if type(radio) == "table" and type(radio.call) == "string" then return radio.call end
	if type(data) ~= "table" then return "" end
	if type(data.tel) == "string" then return data.tel end
	if type(data.host) == "string" then return data.host end
	if type(data.addr) == "string" then return data.addr end
	return ""
end

--
-- Identity
--

-- The building a computer stands in, as two numbers that do not move: the
-- corner of its BuildingDef. The def and not the IsoBuilding, because
-- IsoBuilding.id is handed out by a counter at load time (idCount) and is a
-- different number next session, while def.getX() and def.getY() are where the
-- building is on the map.
--
-- nil for a computer in no building at all, which is what a player-built base
-- is: no wire, and every command says so.
local function defOf(luaObject)
	local square = luaObject:getSquare()
	if square == nil then return nil end
	local building = square:getBuilding()
	if building == nil then return nil end
	local def = building:getDef()
	if def == nil then return nil end
	return def, square
end

function CeroSecNet.buildingOf(luaObject)
	local def = defOf(luaObject)
	if def == nil then return nil end
	return def:getX(), def:getY()
end

--
-- WHICH PREMISES A COMPUTER STANDS IN
--
-- One line and one length of coax per PREMISES, and a building is not one: a
-- shopping mall is one BuildingDef with thirty shops in it, and a house is one
-- BuildingDef with one household in it. The map knows the difference, and this is
-- where it is asked.
--
-- THE RULE. The premises is the named zone of type ZombiesType containing the
-- machine's square whose area is strictly smaller than the building's own
-- footprint; the smallest of them when several qualify; otherwise the building
-- itself, exactly as it was before.
--
-- Why ZombiesType and why the area test. Map designers tag the shops inside a mall
-- with small named ZombiesType zones -- "CoffeeShop", 17 by 11 -- because that is
-- how the spawner is told what kind of dead to put in a shop; it is the only place
-- in the shipped map data where a shop has an outline of its own (a RoomDef's name
-- is a loot type, "clothsstore", and says nothing about tenancy). The zones a HOUSE
-- sits in are the other kind: a suburb, a district, a whole town, all of them
-- bigger than the house. So the area test is the whole of what tells a tenancy from
-- a region, and a zone exactly the building's size is the building under another
-- name and loses on the same test.
--
-- Proved at the bytecode level on projectzomboid.jar 42.20.4, because every engine
-- call on this rung has to be:
--
--   zombie.iso.IsoWorld.getMetaGrid() -> zombie.iso.IsoMetaGrid
--   zombie.iso.IsoMetaGrid.getZonesAt(int, int, int)
--       -> java.util.ArrayList<zombie.iso.zones.Zone>
--   zombie.iso.zones.Zone.getName()   -> String (getfield name)
--   zombie.iso.zones.Zone.getType()   -> String (getfield type)
--   zombie.iso.zones.Zone.getX/getY() -> int    (getfield x, y)
--   zombie.iso.zones.Zone.getWidth()  -> int    (getfield w)
--   zombie.iso.zones.Zone.getHeight() -> int    (getfield h)
--   zombie.iso.BuildingDef.getX/getY/getX2/getY2() -> int
--
-- The getters and not the public fields, which is what the game's own Lua does
-- (media/lua/shared/Traps/TrapSystem.lua:12-17 walks getZonesAt and asks
-- zone:getType(); client/DebugUIs/DebugContextMenu.lua:1239 does the same).
--
-- Asked only where the chunk is certainly loaded -- the two moments identify is
-- called -- and the answer is written into the machine's own record, so nothing
-- ever asks the world twice.
--

-- The zones on a square, as a plain array. An empty one for a game with no world
-- to ask, which is what a bench without one is and what a server mid-load can be.
local function zonesAt(square)
	if getWorld == nil then return {} end
	local world = getWorld()
	if world == nil then return {} end
	local grid = world:getMetaGrid()
	if grid == nil then return {} end
	local list = grid:getZonesAt(square:getX(), square:getY(), square:getZ())
	if list == nil then return {} end
	local out = {}
	for i = 0, list:size() - 1 do
		local zone = list:get(i)
		if zone ~= nil then out[#out + 1] = zone end
	end
	return out
end

-- The premises: two bytes, the exchange behind them, and what it is called.
-- nil for a computer in no building at all, which is what a player-built base is.
function CeroSecNet.premisesOf(luaObject)
	local def, square = defOf(luaObject)
	if def == nil then return nil end
	local bx, by = def:getX(), def:getY()
	if type(bx) ~= "number" or type(by) ~= "number" then return nil end

	-- The building's own footprint, which is what a tenancy has to be smaller than.
	-- 0 for a def that will not say -- and a footprint of nothing is a building no
	-- zone can be inside, so every zone loses and the building wins, which is the
	-- answer this rung had before there were zones in it.
	local area = 0
	local x2, y2 = def:getX2(), def:getY2()
	if type(x2) == "number" and type(y2) == "number" then
		area = (x2 - bx) * (y2 - by)
	end

	local best, bestArea = nil, nil
	if area > 0 then
		local zones = zonesAt(square)
		for i = 1, #zones do
			local zone = zones[i]
			local name = zone:getName()
			if zone:getType() == CeroSecNet.PREMISES_TYPE
					and type(name) == "string" and name ~= "" then
				local w, h = zone:getWidth(), zone:getHeight()
				if type(w) == "number" and type(h) == "number" then
					local own = w * h
					-- Strictly smaller, and the smallest of the ones that are: a shop
					-- inside a shop is the shop a survivor is standing in.
					if own > 0 and own < area and (bestArea == nil or own < bestArea) then
						best, bestArea = zone, own
					end
				end
			end
		end
	end

	if best == nil then
		local b1, b2 = CeroSecOS.buildingKey(bx, by)
		if b1 == nil then return nil end
		return b1, b2, CeroSecOS.phoneExchange(bx, by), nil
	end
	local zx, zy = best:getX(), best:getY()
	local b1, b2 = CeroSecOS.premisesKey(zx, zy, best:getWidth(), best:getHeight())
	if b1 == nil then return nil end
	return b1, b2, CeroSecOS.phoneExchange(zx, zy), best:getName()
end

-- Every machine the server holds, which is every machine in the county that has
-- ever been switched on -- loaded chunk or not (see the head of this file).
local function each(system, fn)
	for i = 1, system:getLuaObjectCount() do
		local other = system:getLuaObjectByIndex(i)
		if other ~= nil then
			local stop = fn(other)
			if stop ~= nil then return stop end
		end
	end
	return nil
end

-- The address record on a machine, read out of the state RAW -- through the
-- engine's own tolerant accessor and not through osState(). That is deliberate:
-- osState migrates, tops up and validates a whole filesystem, and a ping that
-- did it once per computer in the county would be a ping that walked every disk
-- on the map. The record is three numbers and reading it wrongly is impossible;
-- netRecord answers nil for anything that is not one.
local function recordOf(luaObject)
	return CeroSecOS.netRecord(luaObject.os)
end

-- The machine an address names, and its record. nil when no computer the server
-- holds answers to it.
function CeroSecNet.at(system, addr)
	return each(system, function(other)
		local net = recordOf(other)
		if net ~= nil and CeroSecOS.addressText(net.b1, net.b2, net.n) == addr then
			return { object = other, net = net }
		end
		return nil
	end)
end

-- Which computer of its building this one is. The lowest number nobody in the
-- same building has, exactly as a device number is the lowest its kind has never
-- used -- and once it is written into the state it is never moved: a survivor
-- who wrote 10.4.17.3 in /etc/hosts wrote down a machine and not a position in a
-- list.
local function freeNumber(system, luaObject, b1, b2)
	local taken = {}
	each(system, function(other)
		if other ~= luaObject then
			local net = recordOf(other)
			if net ~= nil and net.b1 == b1 and net.b2 == b2 then taken[net.n] = true end
		end
		return nil
	end)
	for n = 1, 254 do
		if not taken[n] then return n end
	end
	return nil
end

-- Give this machine its address, if it has not got one for the building it is
-- standing in now. Answers true when it wrote one.
--
-- Called when a computer is switched on and when a window opens on it, which are
-- the two moments the chunk is certainly loaded. A machine carried into another
-- building is renumbered the next time either happens -- the b1/b2 it carries no
-- longer match where it stands -- and one carried out of every building keeps
-- the record it had until it is put back inside one, because there is nothing to
-- replace it with and a machine with no address at all is not something to
-- invent.
function CeroSecNet.identify(system, luaObject, state)
	if state == nil then return false end
	-- The PREMISES and not the building: a shop in a mall is its own, and a house is
	-- the building. Both links come off these two bytes -- the segment and the line
	-- -- so two shops in one mall are two of each.
	--
	-- The exchange comes back beside them because it cannot be derived from them:
	-- the key is two bytes of a hash and a region is a coordinate, which is the whole
	-- reason the exchange is a FIELD in the record (see the note over
	-- CeroSecOS.phoneExchange).
	local b1, b2, ex, pz = CeroSecNet.premisesOf(luaObject)
	if b1 == nil then return false end

	local net = CeroSecOS.netRecord(state)
	if net ~= nil and net.b1 == b1 and net.b2 == b2 then
		-- Already on this premises's wire. Two things may still be missing, and both
		-- are the same fact: every machine saved before the line belonged to the
		-- premises carries the building bytes and no exchange, so it has NO TELEPHONE
		-- -- an empty line in the BIOS, and `cu: no phone line` -- until the record is
		-- made again where it stands. This is that moment: the chunk is loaded, so the
		-- square is answerable, and nothing has to be migrated anywhere else.
		--
		-- A machine whose bytes already match is a machine whose PREMISES has not
		-- moved, so only the two labels can have: the exchange and the name.
		if net.ex ~= nil and net.pz == pz then return false end
		if ex == nil then return false end
		if CeroSecOS.setNetRecord(state, b1, b2, net.n, ex, pz) == nil then return false end
		luaObject:mirrorOS()
		return true
	end

	local n = freeNumber(system, luaObject, b1, b2)
	if n == nil then return false end
	if CeroSecOS.setNetRecord(state, b1, b2, n, ex, pz) == nil then return false end
	-- And the machine's own line in /etc/hosts, once. After this the file is the
	-- player's: a name he added stays, a line he deleted stays deleted.
	CeroSecOS.writeOwnHost(state, CeroSecOS.clockOf(system:clockEnv()))
	-- And the station's callsign, which is derived from the very three numbers
	-- just written and is therefore answerable for the first time now. Seeded
	-- here as well as in ensureNet, so that a machine which has only this moment
	-- learned which building it stands in gets its licence without waiting for a
	-- reload -- the same pair of places /etc/hosts's own line is written from.
	CeroSecOS.ensureCallsign(state)
	luaObject:mirrorOS()
	return true
end

--
-- Reachability
--

-- Can `from` hear the machine at `addr` right now?
-- the machine, or nil plus which of strerror's words to wear:
--   "down"    it is on this wire and it is switched off
--   "unreach" there is no wire between here and there at all
local function reachableOn(system, from, addr)
	-- The loopback reaches this machine and nothing else, whatever building it is
	-- in and whether it has a wire at all -- which is what a loopback is. The
	-- engine already answers a ping on it; this is the other half, so that
	-- `rlogin localhost` opens a second session on the machine one is sitting at
	-- rather than being refused by a link layer that was looking for a cable.
	if addr == CeroSecOS.LOOPBACK_ADDR then
		if not from.on then return nil, "down" end
		return from
	end
	local mine = recordOf(from)
	if mine == nil then return nil, "unreach" end
	local found = CeroSecNet.at(system, addr)
	if found == nil then return nil, "unreach" end
	-- The Ethernet rule, and the whole of it: the same map building.
	if found.net.b1 ~= mine.b1 or found.net.b2 ~= mine.b2 then return nil, "unreach" end
	if not found.object.on then return nil, "down" end
	return found.object
end

-- The same question, with a line in the wire's log behind it. Wrapped rather than
-- noted at each of the six ways out, so a seventh cannot be added without one.
--
-- This is where a REFUSAL about the wire is decided -- every command that names a
-- far machine asks here first (env.net.reach), and a name that was refused left
-- no trace anywhere before this: no pty was made, nothing was written to a disk,
-- and the line the player read is on a screen that has scrolled.
function CeroSecNet.reachable(system, from, addr)
	local object, why = reachableOn(system, from, addr)
	CeroSecNet.note(from, "eth", addr, object ~= nil and "reachable" or tostring(why))
	return object, why
end

-- Every machine on this one's wire that is switched on, itself included.
local function wire(system, from)
	local mine = recordOf(from)
	local out = {}
	if mine == nil then return out end
	each(system, function(other)
		local net = recordOf(other)
		if net ~= nil and net.b1 == mine.b1 and net.b2 == mine.b2 and other.on then
			out[#out + 1] = other
		end
		return nil
	end)
	return out
end

--
-- The telephone
--
-- THE EXCHANGE IS THE COUNTY GRID. A telephone exchange in 1993 was a building
-- full of switches on the mains with batteries for a few hours, and Knox County's
-- power goes off on a day the sandbox chose. When it does, the exchange goes with
-- it: there is no dial tone, and a call is not a thing anybody can place. That is
-- the one rule that makes the telephone a different kind of link from the coax --
-- the coax is two machines and a wire and goes on working with a generator behind
-- each of them, and the telephone needs a third party who is not there any more.
--
-- Whether the grid is alive is asked the way the game's own Lua asks it
-- (media/lua/client/ISUI/ISButtonPrompt.lua:520, and the same arithmetic in
-- media/lua/server/radio/ISWeatherChannel.lua:153-154):
--
--   day = getGameTime():getWorldAgeHours() / 24
--         + (getSandboxOptions():getTimeSinceApo() - 1) * 30
--   alive = ElecShutModifier > -1 and day < ElecShutModifier
--
-- The > -1 is not a nil guard, it is the option's own bottom: zombie.SandboxOptions
-- randomElectricityShut answers -1 for the first setting of ElecShut, which is
-- the power already off at the start, and 2147483647 for the last, which is the
-- power that never goes (javap'd on projectzomboid.jar). So -1 means there is no
-- day on which it goes off because it went off before the first one, and a day
-- number can never be under it.
--
-- Asked of the option and not of a square, deliberately: square:hasGridPower()
-- answers about a place, and the exchange is not in the room with the computer.
--
CeroSecNet.SANDBOX = "PhoneService"

-- The option a server may set, if a sandbox option file ever declares one, read
-- the way vanilla reads its own grouped options -- `SandboxVars.Map and
-- (SandboxVars.Map.AllowWorldMap == true)`, ISWorldMap.lua:1493 -- because
-- SandboxVars is a plain table and a group nobody declared is simply not in it.
-- Nothing here creates the option; this is the hook it would land in.
--
--   "grid"   the exchange lives as long as the county's power does (the default)
--   "never"  there is no telephone service at all, from the first day
--   "always" the exchange is on a generator and outlives the grid
--
-- Anything else is not one of the three and is ignored rather than argued with.
function CeroSecNet.phoneService()
	local group = SandboxVars and SandboxVars.CeroSec
	local value = group and group[CeroSecNet.SANDBOX]
	if value == "never" or value == "always" then return value end
	return "grid"
end

-- Is the county's power still on? true when the game cannot be asked at all: a
-- mod that could not read the option must not quietly take the telephone out of
-- every server it cannot interrogate, and the failure it would cause -- a call
-- that goes through -- is the one a player can see and report.
function CeroSecNet.gridAlive()
	if getGameTime == nil or getSandboxOptions == nil then return true end
	local time = getGameTime()
	local options = getSandboxOptions()
	if time == nil or options == nil then return true end
	local off = options:getElecShutModifier()
	if type(off) ~= "number" or off <= -1 then return false end
	local day = time:getWorldAgeHours() / 24 + (options:getTimeSinceApo() - 1) * 30
	if type(day) ~= "number" then return true end
	return day < off
end

function CeroSecNet.exchangeAlive()
	local mode = CeroSecNet.phoneService()
	if mode == "never" then return false end
	if mode == "always" then return true end
	return CeroSecNet.gridAlive()
end

-- The PREMISES's line, which IS its number: one premises, one line, one number,
-- shared by every computer standing on it. nil for a machine that has none -- one
-- in no building at all, and one whose record was written before the line belonged
-- to the premises rather than to the whole building.
--
-- The number is the KEY the busy rule is asked in, and that is the whole of what
-- changed when the line stopped being the building's: the key is the two bytes of
-- the PREMISES now, so a mall is thirty lines and not one that thirty shops took
-- turns on.
local function lineKey(net)
	if net == nil or net.ex == nil then return nil end
	return CeroSecOS.phoneText(net.ex, CeroSecOS.phoneKey(net.b1, net.b2))
end

-- One place, read two ways, and the two can never disagree: keyOf is what the busy
-- rule and a pty's own record of the call are keyed by, lineOf is what `who`,
-- `last`, the BIOS line and cu print. They are the same string.
function CeroSecNet.keyOf(luaObject)
	return lineKey(recordOf(luaObject))
end

-- This machine's number, or nil for one with no line.
function CeroSecNet.lineOf(luaObject)
	return lineKey(recordOf(luaObject))
end

-- The dial a machine is in the middle of, or nil. One at a time and no more: the
-- line is busy for the length of the ring, so a second dial off the same machine
-- cannot get past the busy rule to start one.
--
-- Read off the JOB BOOK and never off a field beside it, which is the doctrine the
-- busy rule below already runs on one level up (the pty table IS the record of a
-- call). A ring is a job asleep on a clock; a job that has gone -- killed by
-- Escape, by `kill`, by the cpu ceiling, by the machine going dark -- has hung up
-- by the same act, and there is nothing left holding anything. A counter beside the
-- jobs would be a line busy for ever with nobody on it.
--
-- It costs a walk of a book that holds four jobs at the most, and only for a
-- machine that has a book at all: a machine at its prompt has none.
function CeroSecNet.ringOf(luaObject)
	if luaObject == nil then return nil end
	local book = luaObject.jobs
	if book == nil or type(book.list) ~= "table" then return nil end
	for i = 1, #book.list do
		local job = book.list[i]
		if type(job.ring) == "table" and not CeroSecOS.jobIsOver(job) then
			return job.ring
		end
	end
	return nil
end

-- Is a line in use right now?
--
-- DERIVED and never counted. A call is two things -- a pty on the machine that
-- answered and a glass at the machine that dialled -- and both of them are on the
-- pty, so the pty table IS the record of who is on the telephone. A counter
-- beside it would be a second truth that leaks: a machine picked up mid-call, a
-- server restarted with a call open, a teardown down a path somebody forgot,
-- and the line is busy for ever with nobody on it. Walking the county costs what
-- a ping costs and cannot be wrong.
--
-- Both ENDS make the line busy, which is what one line per premises means: a shop
-- whose other machine has dialled OUT cannot take a call either.
--
-- And a line that is RINGING is busy too, at both ends, for the length of the
-- ring: a modem that has lifted the receiver and is waiting for an answer is
-- holding the line, and the far telephone that is ringing cannot take a second
-- call. That half is not on a pty -- there is no session yet -- so it is read off
-- the JOB that is dialling (CeroSecNet.ringOf), which is the same doctrine one step
-- along: the thing that is waiting IS the record of the ring, and a job that has
-- gone away has let the line go with it. Nothing is counted anywhere.
function CeroSecNet.lineBusy(system, key)
	if key == nil then return false end
	return each(system, function(other)
		local ring = CeroSecNet.ringOf(other)
		if ring ~= nil and (ring.tel == key or ring.to == key) then return true end
		local ptys = CeroSecOS.ptyList(other.ptys)
		if #ptys == 0 then return nil end
		local theirs = CeroSecNet.keyOf(other)
		for i = 1, #ptys do
			local pty = ptys[i]
			if type(pty.phone) == "table" then
				-- The machine that DIALLED is on the pty; the machine that
				-- ANSWERED is the one the pty is on.
				if pty.phone.key == key or theirs == key then return true end
			end
		end
		return nil
	end) and true or false
end

-- Who answers a number. Every computer of the premises shares the line, so the one
-- that picks up is the one with the lowest address on it -- the desk the modem is on
-- -- and it is the same desk every time, which is what makes a number something a
-- player can write down. A machine that is switched off cannot answer; a premises
-- where every machine is off is a telephone ringing in an empty shop.
--
-- Two PREMISES on one number is the same answer read once more: ten thousand
-- subscriber numbers to a region, so the derivation lets two of them land on one,
-- and the lowest n of the pair picks up. Either way it is a PARTY LINE, which is
-- what a rural exchange really sold in 1993, and the manual says so.
function CeroSecNet.atPhone(system, tel)
	if tel == nil then return nil end
	local best, bestNet = nil, nil
	each(system, function(other)
		if not other.on then return nil end
		local net = recordOf(other)
		if net == nil then return nil end
		if lineKey(net) ~= tel then return nil end
		if bestNet == nil or net.n < bestNet.n then
			best, bestNet = other, net
		end
		return nil
	end)
	return best
end

-- Can `from` place a call to that number right now?
-- the machine that answers, or nil plus the word the MODEM prints.
local function reachablePhoneOn(system, from, tel)
	if not from.on then return nil, CeroSecOS.MODEM.noCarrier end
	local mine = recordOf(from)
	-- No line at all. The command itself has already said so in cu's own words
	-- before it ever got here; this is the door saying the same thing, and there
	-- is no modem to print anything for a machine that has none.
	if mine == nil then return nil, CeroSecOS.CU_NO_LINE end
	-- No exchange, no dial tone. Asked before the line, because a dead exchange is
	-- what the receiver tells you first.
	if not CeroSecNet.exchangeAlive() then return nil, CeroSecOS.MODEM.noDialtone end
	local myKey = lineKey(mine)
	-- This premises's own line, in use by somebody: a survivor on the other
	-- machine in the shop is on the telephone, and there is one telephone.
	if CeroSecNet.lineBusy(system, myKey) then return nil, CeroSecOS.MODEM.busy end
	local object = CeroSecNet.atPhone(system, tel)
	-- Nobody answered: a number no building has, or a building with every machine
	-- switched off. The two are deliberately the same word -- a caller finds out
	-- nothing about a county he cannot reach, which is what a telephone is like.
	if object == nil then return nil, CeroSecOS.MODEM.noCarrier end
	local theirKey = CeroSecNet.keyOf(object)
	-- This premises's own number, dialled from inside it: the line is busy because
	-- the caller is the one using it.
	if theirKey == myKey then return nil, CeroSecOS.MODEM.busy end
	if CeroSecNet.lineBusy(system, theirKey) then return nil, CeroSecOS.MODEM.busy end
	return object
end

-- And the telephone's, logged for the reason the wire's is: what the modem said
-- is a line on a screen and nothing else.
function CeroSecNet.reachablePhone(system, from, tel)
	local object, why = reachablePhoneOn(system, from, tel)
	CeroSecNet.note(from, "tel", tel, object ~= nil and "answered" or tostring(why))
	return object, why
end

-- Who would answer that number, asked in FULL: the line layer's own question plus
-- the one thing dialPhone used to ask after it -- a machine sitting at the
-- firmware's question has no operating system to answer a modem with, and nobody
-- picking up is nobody picking up.
--
-- One function because it is asked twice about one call: once when the modem goes
-- off-hook, to work out which of the three things the ring will end in, and once at
-- the door when the ring is over, because four seconds is time enough for the far
-- machine to have been switched off.
function CeroSecNet.ringAnswer(system, from, tel)
	local found, word = CeroSecNet.reachablePhone(system, from, tel)
	if found == nil then return nil, word end
	if found:osState() == nil then return nil, CeroSecOS.MODEM.noCarrier end
	return found
end

-- The call a screen is on, when it is on one: what makes the trickle slower than
-- the wire and what makes a teardown speak somebody else's words.
--
-- Either KIND of call. A telephone call and a radio link are two different links
-- with two different voices and two different speeds, and exactly one thing is
-- the same about both of them: they are not the coax. Every place that asks this
-- question is asking that one -- the trickle, `~.`, and which line a teardown
-- prints -- and each reads the pty afterwards to find out which it got.
function CeroSecNet.callOn(luaObject, console)
	if luaObject == nil or type(console) ~= "table" then return nil end
	if type(console.line) ~= "string" then return nil end
	local pty = CeroSecOS.remoteLine(luaObject.ptys, console.line)
	if pty == nil then return nil end
	if type(pty.phone) ~= "table" and type(pty.radio) ~= "table" then return nil end
	return pty
end

-- Lines that call may still take this second. The window is kept on the PTY,
-- beside the line it belongs to, because the ceiling is the LINE's: two calls
-- into one machine are two lines and each gets its own 2400 baud, while the
-- machine's own twenty a second still holds over both of them.
function CeroSecNet.callRoom(pty, now)
	if type(pty.outMs) ~= "number" or now - pty.outMs >= 1000 then
		pty.outMs = now
		pty.outCount = 0
	end
	-- Which link's ceiling, read off the pty: 2400 baud down a telephone line and
	-- 1200 over the air, which is the number each link really ran at and therefore
	-- two different handfuls on the screen.
	local per = CeroSec.PHONE_LINES_PER_S
	if type(pty.radio) == "table" then per = CeroSec.RADIO_LINES_PER_S end
	local room = per - (pty.outCount or 0)
	if room < 0 then return 0 end
	return room
end

--
-- The radio
--
-- THERE IS NO THIRD PARTY AND NO WIRE. That is the whole of what makes this link
-- different from the other two, and everything below follows from it:
--
--   * the coax is two machines and a length of cable, and goes on working with a
--     generator behind each of them;
--   * the telephone needs the county's exchange, which is a building full of
--     switches on the mains, so it dies when the grid does;
--   * the radio needs nothing but two aerials in earshot -- and therefore it
--     works after the grid has gone, and it is the only link that does.
--
-- What it pays for that is three things the other two never pay:
--
--   1. DISTANCE. A transmitter has a range and the game says what it is
--      (DeviceData.getTransmitRange, 7500 for a ham set and 8000 for a walkie),
--      measured on x and y with no z in it, which is the game's own arithmetic
--      (proof 5 in SCeroSecRadio.lua). The link holds out to the SMALLER of the
--      two ranges, because a link is two transmissions and the weaker one decides.
--
--   2. A CHUNK. A radio is a tile, and a tile the streamer has not brought in
--      does not exist -- it is not even in the list a transmission is
--      distributed over (proof 6). A machine's DISK the server holds whatever the
--      streamer is doing, which is why ruptime, ping, rlogin and cu all answer
--      for a computer nobody is standing near; a machine's RADIO it does not. So
--      a call to a station in an empty town gets the TNC's word for silence, and
--      that is honest rather than convenient: there is no aerial there to answer
--      with.
--
--   3. EVERYBODY HEARS IT. Every connect and every disconnect goes out as a real
--      transmission on the real frequency, so anybody in the county with a walkie
--      tuned to it reads the two callsigns (CeroSecRadio.announce). The other two
--      links are private by construction and this one cannot be, which is what a
--      radio IS.
--
-- And the identity is a FILE. /etc/callsign, root's and writable, so a callsign
-- is what a station says it is -- which is why no trust file is asked over the
-- air and a password is asked every time.
--
-- ONE LINK PER RADIO, both ends. A TNC has one connection in it, and two
-- machines in one room share one set: the second one cannot get on the air while
-- the first one is on it. Derived and never counted, exactly as the telephone's
-- busy line is -- the pty table IS the record of who is on the air.
--

-- This machine's callsign, off its own disk. nil for a machine with no
-- /etc/callsign that is a callsign, which is a station with no licence.
function CeroSecNet.callsignOf(luaObject)
	local state = luaObject:osState()
	if state == nil then return nil end
	return CeroSecOS.callsignOf(state)
end

-- Which set a machine is wired to, as the key the busy rule is asked in. nil for
-- a machine with no radio in reach and for one whose square is not loaded.
function CeroSecNet.radioKeyOf(luaObject)
	return CeroSecRadio.keyOf(CeroSecRadio.tncOf(luaObject))
end

-- Who answers a callsign. Every machine the server holds is asked -- the whole
-- county, loaded or not -- because the file is on the disk and the disk is here;
-- whether it can be HEARD is the next question and not this one.
--
-- A machine that is switched off cannot answer. Two machines that answer to one
-- callsign -- which the derivation allows, the county being bigger than the
-- callsigns are (CeroSecOS.callsignFor) -- are two stations answering one
-- connect, and the first in the county's own order is the one reached. On the air
-- that is exactly what happens and there is nothing in AX.25 that arbitrates it
-- either.
function CeroSecNet.atCall(system, call)
	if type(call) ~= "string" then return nil end
	return each(system, function(other)
		if not other.on then return nil end
		if CeroSecNet.callsignOf(other) ~= call then return nil end
		return other
	end)
end

-- Is that set on the air right now?
--
-- Both ENDS make it busy, which is what one connection per TNC means: the
-- machine that CALLED holds the caller's set (pty.radio.key) and the machine that
-- ANSWERED holds its own. Walked rather than counted, for the reason
-- CeroSecNet.lineBusy is walked rather than counted: a counter beside the ptys is
-- a second truth that leaks, and the walk cannot be wrong.
--
-- The far machine's own set is worked out only for a machine that HAS a pty, so
-- the county is not scanned for aerials on a question about somebody's screen.
function CeroSecNet.radioBusy(system, key)
	if key == nil then return false end
	return each(system, function(other)
		local ptys = CeroSecOS.ptyList(other.ptys)
		if #ptys == 0 then return nil end
		local theirs = nil
		for i = 1, #ptys do
			local pty = ptys[i]
			if type(pty.radio) == "table" then
				if pty.radio.key == key then return true end
				if theirs == nil then theirs = CeroSecNet.radioKeyOf(other) end
				if theirs == key then return true end
			end
		end
		return nil
	end) and true or false
end

-- Are two sets in earshot of each other? The smaller of the two ranges against
-- the distance between the MACHINES, squared on both sides so that nothing here
-- takes a square root.
--
-- The machines and not the sets, deliberately: a machine is where a survivor is
-- standing and a set is on the desk beside it, so the two differ by a tile out of
-- thousands, and the position that matters to a player is the one he can see on
-- the map. The ANNOUNCEMENT uses the set's own tile, because that one is the
-- game's to measure and the game measures from the transmitter (proof 5).
--
-- At exactly the range the game scrambles a line a hundred per cent, so a link
-- out at the range is a link that could not pass a byte; the comparison is
-- therefore strictly inside it.
function CeroSecNet.radioInRange(from, to, mine, theirs)
	local reach = mine.range
	if theirs.range < reach then reach = theirs.range end
	if reach <= 0 then return false end
	local dx = to.x - from.x
	local dy = to.y - from.y
	return dx * dx + dy * dy < reach * reach
end

-- Can `from` raise that station right now?
-- the machine that answers plus both sets, or nil plus the one line to print.
--
-- ONE refusal covers every way a call goes unanswered -- no such station, a
-- machine switched off, a set switched off, a flat battery, the wrong frequency,
-- too far, a chunk nobody has loaded -- and it is the TNC's own
-- "*** retry count exceeded". That is not laziness: a station that hears nothing
-- back learns NOTHING about why, which is the one thing a radio has in common
-- with a telephone and the reason both links are worse to diagnose than a wire.
-- The machine says what it can see for itself (no set at all, no callsign) in its
-- own name, and everything beyond its own aerial is silence.
local function reachableRadioOn(system, from, call)
	if not from.on then return nil, CeroSecOS.TNC.retry end
	-- No set in reach: the machine can see that for itself, there being no
	-- /dev/radio0 on it, and it says so rather than keying a transmitter it has
	-- not got.
	local mine = CeroSecRadio.tncOf(from)
	if mine == nil then return nil, CeroSecOS.CALL_NO_RADIO end
	-- A set that is switched off, or has nothing behind it, is NOT one of those: a
	-- TNC's only cables are the audio and the press-to-talk, so it cannot tell
	-- whether the radio in front of it is alive. It transmits into a dead set and
	-- the retries run out. `cat /dev/radio0` is how a survivor finds out, and the
	-- manual says so.
	if not mine.on or not mine.powered then return nil, CeroSecOS.TNC.retry end
	local myKey = CeroSecRadio.keyOf(mine)
	if CeroSecNet.radioBusy(system, myKey) then return nil, CeroSecOS.TNC.busy end

	local object = CeroSecNet.atCall(system, call)
	if object == nil then return nil, CeroSecOS.TNC.retry end
	local theirs = CeroSecRadio.tncOf(object)
	if theirs == nil then return nil, CeroSecOS.TNC.retry end
	if not theirs.on or not theirs.powered then return nil, CeroSecOS.TNC.retry end
	-- Two frequencies are two conversations. It is the one refusal of the six that
	-- a survivor can do something about from where he is sitting, and he cannot
	-- learn it from here -- which is why the announcement matters and why the
	-- manual tells him to agree a frequency first.
	if theirs.channel ~= mine.channel then return nil, CeroSecOS.TNC.retry end
	local theirKey = CeroSecRadio.keyOf(theirs)
	-- One set serving both ends: two machines in one room, and the station is
	-- calling itself. A TNC will not connect to its own radio.
	if theirKey == myKey then return nil, CeroSecOS.TNC.busy end
	if CeroSecNet.radioBusy(system, theirKey) then return nil, CeroSecOS.TNC.busy end
	if not CeroSecNet.radioInRange(from, object, mine, theirs) then
		return nil, CeroSecOS.TNC.retry
	end
	return object, nil, mine, theirs
end

-- And the air's. The refusal here is the one worth a log more than either of the
-- other two: six different things answer with the same word, on purpose, because
-- a station that gets no reply learns nothing about why -- so the reason the
-- SERVER had is the only place the truth exists at all.
function CeroSecNet.reachableRadio(system, from, call)
	local object, why, mine, theirs = reachableRadioOn(system, from, call)
	CeroSecNet.note(from, "radio", call, object ~= nil and "connected" or tostring(why))
	return object, why, mine, theirs
end

-- Does a link that was made still hold? Asked on every keystroke that goes down
-- it, for the reason the telephone's exchange is asked there: the radio is a link
-- that can go away with both machines still switched on and nobody having typed
-- anything -- somebody turns the set off, carries it out of the room, or turns
-- the knob -- and the moment a player finds out about a dead link is the moment
-- he touches it.
--
-- Costed deliberately: it is two room scans, and only for a session that is on
-- the air. The alternative is a link that goes on working after the aerial has
-- been unplugged, which is the failure a player would report as a bug.
function CeroSecNet.radioHolds(system, pty, object)
	local at = pty.from
	if type(at) ~= "table" then return false end
	local caller = system:getLuaObjectAt(at.x, at.y, at.z)
	if caller == nil or not caller.on then return false end
	local mine = CeroSecRadio.tncOf(caller)
	local theirs = CeroSecRadio.tncOf(object)
	if mine == nil or theirs == nil then return false end
	if not mine.on or not mine.powered then return false end
	if not theirs.on or not theirs.powered then return false end
	if mine.channel ~= theirs.channel then return false end
	-- The set the link was MADE on, and not merely any set in the room: a survivor
	-- who carried a second radio in has not moved the link onto it.
	if CeroSecRadio.keyOf(mine) ~= pty.radio.key then return false end
	return CeroSecNet.radioInRange(caller, object, mine, theirs)
end

--
-- Who is logged in on one machine
--
-- The survivor at the keyboard is on the console; everybody who came in over the
-- wire is on his pty, with the machine he came from beside him. One list, and
-- who(1), rwho(1) and ruptime(1)'s user count are all read out of it.
--

function CeroSecNet.sessions(luaObject)
	local out = {}
	local console = luaObject.console
	if type(console) == "table" and type(console.user) == "string" then
		out[#out + 1] = { user = console.user, line = CeroSecOS.CONSOLE_LINE,
			at = console.loginAt or 0 }
	end
	local ptys = CeroSecOS.ptyList(luaObject.ptys)
	for i = 1, #ptys do
		local pty = ptys[i]
		local screen = pty.console
		if type(screen) == "table" and type(screen.user) == "string" then
			out[#out + 1] = { user = screen.user, line = pty.line,
				at = screen.loginAt or 0, host = pty.fromHost }
		end
	end
	return out
end

-- What ruptime calls the load: how many jobs the machine has that could run.
-- Which is what a load average has counted since the first one -- and it is not
-- an average, because nothing here smooths anything over a minute.
local function loadOf(luaObject)
	if luaObject.jobs == nil then return 0 end
	return CeroSecOS.liveJobs(luaObject.jobs.list)
end

-- How long it has been up, in seconds. Wall clock from the moment it was
-- switched on, and RUNTIME state like the jobs: a server that came back up
-- forgets when a machine was switched on, so ruptime counts from the restart.
-- That is the same answer the jobs give and it is in the manual.
local function upOf(luaObject, nowMs)
	if type(luaObject.upMs) ~= "number" or type(nowMs) ~= "number" then return 0 end
	local up = math.floor((nowMs - luaObject.upMs) / 1000)
	if up < 0 then return 0 end
	return up
end

--
-- What the engine is handed
--

-- One machine's link layer, built fresh for every line typed -- like the devices
-- beside it, because both are answers about a moment: what is on the wire right
-- now, and who is sitting at it right now.
function CeroSecNet.envFor(system, luaObject, state)
	local nowMs = getTimestampMs()
	return {
		reach = function(addr)
			local object, why = CeroSecNet.reachable(system, luaObject, addr)
			if object == nil then return false, why end
			return true, nil
		end,

		peers = function()
			local list = wire(system, luaObject)
			local out = {}
			for i = 1, #list do
				local other = list[i]
				-- The peer's own disk, because its name is in its own
				-- /etc/hostname. A machine whose state will not validate is a
				-- machine nothing can be said about, and it is left out.
				local theirs = other:osState()
				if theirs ~= nil then
					local who = CeroSecNet.sessions(other)
					out[#out + 1] = {
						host = CeroSecOS.hostname(theirs),
						addr = CeroSecOS.address(theirs),
						up = upOf(other, nowMs),
						users = #who,
						load = loadOf(other),
						who = who,
					}
				end
			end
			return out
		end,

		sessions = function()
			return CeroSecNet.sessions(luaObject)
		end,

		-- Would a call to that number be answered, and if not, what does the modem
		-- say? nil for "somebody would pick up". It is the whole of what the engine
		-- needs to know before it starts ringing: which of the three outcomes this
		-- dial is going to have, so it can hold the line for as long as that outcome
		-- takes (CeroSecOS.ringMs). The dial itself is still the machine's, and the
		-- question is asked again at the door.
		phone = function(tel)
			local object, word = CeroSecNet.ringAnswer(system, luaObject, tel)
			if object == nil then return word end
			return nil
		end,

		copy = function(spec)
			return CeroSecNet.copy(system, luaObject, state, spec)
		end,
	}
end

--
-- rcp
--
-- One file across the wire, and both ends of it are judged by their own machine:
-- the read by the source's permissions, the write by the target's permissions,
-- its 4096-byte file ceiling and its own 64K disk. There is no privilege
-- anywhere in it -- the account it runs as on the far machine is the account it
-- was on this one, which is what rcp over rsh has always been.
--
-- Trust is required and no password is ever asked, because rcp runs over rshd
-- and rshd does not ask: a machine that does not trust this one answers
-- Permission denied and that is the whole of it.
--

-- The far machine, its state, and the session the copy runs under there.
-- nil plus the reason when the copy cannot happen at all.
local function farEnd(system, luaObject, spec)
	local object = CeroSecNet.reachable(system, luaObject, spec.addr)
	if object == nil then return nil, CeroSecOS.NET_REASON.unreach end
	local state = object:osState()
	if state == nil then return nil, CeroSecOS.NET_REASON.unreach end
	-- The ADDRESS the copy is coming from, never the name this machine announces:
	-- rshd is handed a socket and the trust files are lists of machines, not of
	-- things a caller says about itself (see the trust note in connect()).
	if not CeroSecOS.trusts(state, spec.user, spec.fromAddr, spec.user) then
		return nil, CeroSecOS.NET_REASON.denied
	end
	-- The account has to exist over there, and rsh's word for one that does not
	-- is the same as for one that is not trusted: rshd answers a name it cannot
	-- become exactly as it answers a name it will not become.
	local account = CeroSecOS.getUser(state, spec.user)
	if account == nil then return nil, CeroSecOS.NET_REASON.denied end
	local cwd = "/"
	if type(account.home) == "string" then cwd = account.home end
	return object, state, { user = spec.user, cwd = cwd, stamp = getTimestampMs() }
end

-- ok, reason, bytes.
function CeroSecNet.copy(system, luaObject, state, spec)
	if type(spec) ~= "table" then return false, CeroSecOS.NET_REASON.unreach end
	local object, far, session = farEnd(system, luaObject, spec)
	if object == nil then return false, far end

	local here = { user = spec.user, cwd = "/", stamp = getTimestampMs() }
	-- The local end runs as the account that typed the line and in the directory
	-- it typed it from; the engine handed over the paths already expanded, so
	-- what is left is to read one side and write the other.
	if type(spec.cwd) == "string" then here.cwd = spec.cwd end

	local now = CeroSecOS.clockOf(system:clockEnv())
	local text = nil
	if spec.push then
		local node, reason = CeroSecOS.getNode(state, here, spec["local"])
		if node == nil then return false, reason end
		if node.type ~= "file" then return false, CeroSecOS.notAFile(node) end
		if not CeroSecOS.can(state, here, node, "r") then return false, "permission denied" end
		text = node.data or ""
		local done, wreason = CeroSecOS.writeFile(far, session, spec.remote, text, false, now)
		if done == nil then return false, wreason end
		object:mirrorOS()
	else
		local node, reason = CeroSecOS.getNode(far, session, spec.remote)
		if node == nil then return false, reason end
		if node.type ~= "file" then return false, CeroSecOS.notAFile(node) end
		if not CeroSecOS.can(far, session, node, "r") then return false, "permission denied" end
		text = node.data or ""
		local done, wreason = CeroSecOS.writeFile(state, here, spec["local"], text, false, now)
		if done == nil then return false, wreason end
		luaObject:mirrorOS()
	end
	return true, nil, #text
end

--
-- The sessions
--
-- A remote session is a pty on the far machine with its SCREEN on this one. The
-- pty carries a console of its own -- the same table a machine's own console is,
-- so that everything that already knows what a console is works on it unchanged:
-- the login prompt, the shell, the editor, Escape, the su stack, $? and the
-- shell's variables. What is on it that a machine's own console has not got:
--
--   watchAt  the machine whose windows are looking at it, so a screen pushed by
--            the far machine's scheduler reaches the glass it belongs to
--   line     the name of the pty, which is what `who` prints, what goes into the
--            far machine's wtmp, and what tags every job the session starts
--   hops     how many rlogins deep it is
--
-- The console that DIALLED carries the other half, `remote`: which machine and
-- which line this glass is showing. Neither field is saved -- a pty is runtime
-- state like a job, and a machine that comes back from a reload comes back at
-- its own prompt with nothing open.
--
-- THE LINES ARE ONE GLASS. A pty's console starts with a copy of the lines the
-- dialling console had, and when the session ends they go back the other way. So
-- a survivor sees one unbroken screen -- his own prompt, the rlogin he typed,
-- the far machine's login, the far machine's work, and then his own prompt again
-- with all of it still above -- which is what a real terminal shows, because a
-- real rlogin never had a second screen to put anything on.
--

-- What rlogin says when a session is over. A real rlogin says nothing at all and
-- lets your own shell prompt tell you; here the two prompts look alike -- the
-- same green screen, the same shape -- so the machine says the line telnet says
-- about the same event. It is the one string on this rung that is a choice, and
-- the manual says so.
CeroSecNet.CLOSED = "Connection closed."

-- And what a CALL says when it is over, which is not the same line: rlogin's
-- connection closed and a telephone call did not, it hung up. Two endings, and
-- they are cu's and the modem's:
--
--   Disconnected.  either end hung up on purpose -- `~.` here, `exit` there
--   NO CARRIER     the line went away underneath it: a machine lost its power,
--                  somebody picked one up, or the county's exchange died
--
-- The difference is worth a line of screen because it is the difference between
-- "I am done" and "something happened", and on a telephone that is the only
-- diagnosis there is.
-- And what a RADIO LINK says, which is a third pair and the TNC's own: a TNC-2
-- printed "*** DISCONNECTED" when either end let go, and when the link failed
-- under it -- the final poll retried and never answered -- it printed
-- "*** retry count exceeded" first. So the split is exactly the modem's split
-- read in the TNC's voice: one line for "I am done" and another for "something
-- happened", and on a radio, as on a telephone, that is the only diagnosis there
-- is.
local function closingLine(pty, why)
	if type(pty.radio) == "table" then
		if why == "carrier" then return CeroSecOS.TNC.retry end
		return CeroSecOS.TNC.disconnected
	end
	if type(pty.phone) ~= "table" then return CeroSecNet.CLOSED end
	if why == "carrier" then return CeroSecOS.MODEM.noCarrier end
	return CeroSecOS.CU_DISCONNECTED
end

-- The pty a console is looking at, the machine it is on, and that machine's
-- state. nil when the far end has gone: switched off, picked up, or the session
-- closed from the other side.
function CeroSecNet.farOf(system, console)
	local handle = console.remote
	if type(handle) ~= "table" then return nil end
	local object = system:getLuaObjectAt(handle.x, handle.y, handle.z)
	if object == nil or not object.on then return nil end
	local pty = CeroSecOS.remoteLine(object.ptys, handle.line)
	if pty == nil then return nil end
	local far = object:osState()
	if far == nil then return nil end
	-- A call whose exchange has died since it was placed. This is the one link
	-- that can fail with both machines still switched on and nothing in the world
	-- having moved, so it is asked HERE -- the one place every keystroke on a
	-- session goes through -- rather than by a timer of its own: the carrier is
	-- gone the moment anybody touches the line, which is when a player finds out
	-- about a dropped telephone call anyway.
	--
	-- Torn down here and not left to the caller, so the words are the modem's.
	if type(pty.phone) == "table" and not CeroSecNet.exchangeAlive() then
		CeroSecNet.tearDown(system, object, handle.line, "carrier")
		return nil
	end
	-- And a radio link whose aerial has gone: a set switched off, carried out of
	-- the room, retuned, or a machine walked out of range. Asked in the same place
	-- and for the same reason -- it is the one place every keystroke on a session
	-- goes through, and a link is dead the moment anybody touches it.
	if type(pty.radio) == "table" and not CeroSecNet.radioHolds(system, pty, object) then
		CeroSecNet.tearDown(system, object, handle.line, "carrier")
		return nil
	end
	return pty, object, far
end

-- The console that dialled a pty, and the machine it is on. Named on the pty
-- itself rather than worked out, because a chain of rlogins means the dialler may
-- be another machine's pty and not its own screen.
function CeroSecNet.diallerOf(system, pty)
	local from = pty.from
	if type(from) ~= "table" then return nil end
	local object = system:getLuaObjectAt(from.x, from.y, from.z)
	if object == nil then return nil end
	if from.line == nil then return object.console, object end
	local other = CeroSecOS.remoteLine(object.ptys, from.line)
	if other == nil then return nil end
	return other.console, object
end

-- A DETACHED session, and where what it printed goes.
--
-- rsh from a crontab line or from behind a `&` is a session nobody is watching:
-- the job that dialled it had no terminal, so the console the order arrived with
-- is the machine's own glass and has nothing to do with the command. Such a
-- session gets a console of its own with no copy of that glass on it, marked
-- `noTty` -- and a console marked `noTty` is never pushed to a window
-- (SCeroSecSystem:pushScreen), which is what makes it a sheet of paper rather
-- than a second screen.
--
-- When it ends, the sheet is delivered where everything else the job printed
-- went: the account's mailbox for a cron line, and the job's own lines on the
-- glass for a `&`, which is exactly what a `&` has always been allowed to do.
-- The job on a machine that is waiting for one of these, by id. Over is gone: a
-- job that was killed while its rsh was still out there is not a job to write to.
local function waitingJob(luaObject, id)
	if luaObject == nil or type(id) ~= "number" then return nil end
	local book = luaObject.jobs
	if book == nil then return nil end
	for i = 1, #book.list do
		local job = book.list[i]
		if job.id == id and not CeroSecOS.jobIsOver(job) then return job end
	end
	return nil
end

local function deliver(system, homeObject, home, spec, lines, status, failed)
	-- The job that is WAITING for this, which is every rsh: its lines go through
	-- its own output door -- the glass, the pipe, the word a $(...) is collecting,
	-- the mail for a cron line -- and its status is the far command's. Asked first,
	-- and it answers for the whole delivery: a job waiting on an rsh is where the
	-- answer belongs, and there is nowhere else for it to go.
	local job = waitingJob(homeObject, spec.job)
	if job ~= nil then
		-- The near machine's own state and env go with it: a `>` on the rsh opened
		-- its file when the order was given and the far machine's lines are what
		-- belong in it, and that write is the near machine's disk.
		CeroSecOS.jobRemote(job, lines, status, failed, homeObject:osState(),
			system:execEnv(homeObject, homeObject:osState()))
		if homeObject ~= nil then homeObject:mirrorOS() end
		return
	end
	if type(lines) ~= "table" or #lines == 0 then return end
	local state = nil
	if homeObject ~= nil then state = homeObject:osState() end
	if spec.mailTo ~= nil and state ~= nil then
		CeroSecOS.mailAppend(state, spec.mailTo, CeroSecOS.hostname(state), spec.cmd,
			lines, CeroSecOS.clockOf(system:clockEnv()))
		homeObject:mirrorOS()
		return
	end
	if type(home) ~= "table" then return end
	for i = 1, #lines do CeroSec.consolePush(home, lines[i]) end
	if homeObject ~= nil then system:pushScreen(homeObject, state, home) end
end

-- Is the order a dial nobody is standing behind? Either the engine said so --
-- the job that gave it had no controlling terminal -- or the console it was
-- given on is itself a detached one, because a detached session's own dials are
-- no more watched than it is.
local function detachedDial(console, data)
	if type(data) == "table" and type(data.noTty) == "table" then return data.noTty end
	if type(console) == "table" and console.noTty then return { } end
	return nil
end

-- The one teardown, whichever end asked for it.
--
-- The line comes off the far machine's pty table, its logout goes into the far
-- machine's wtmp, everything it was running stops, the screen goes back to the
-- console that dialled -- with every line the session printed still on it -- and
-- that console is told in rlogin's own words.
--
-- why is "carrier" when it was the LINK that went and not somebody hanging up:
-- it is the difference between NO CARRIER and Disconnected. on a telephone call,
-- and nothing at all on a wire, where a session that ends says one line whatever
-- ended it.
--
-- Answers true when there was a session to end.
-- One line on the air about a link, from the CALLER's set: the two callsigns and
-- what the TNC did. Re-read from the world and never off a copy kept on the pty,
-- because by the time a link ends the set may have been carried somewhere else --
-- and a set that is gone is a transmitter that cannot say anything, which is
-- silence and not a line invented for it.
function CeroSecNet.announceRadio(system, pty, what)
	if type(pty.radio) ~= "table" then return false end
	local at = pty.from
	if type(at) ~= "table" then return false end
	local caller = system:getLuaObjectAt(at.x, at.y, at.z)
	if caller == nil then return false end
	local set = CeroSecRadio.tncOf(caller)
	if set == nil then return false end
	return CeroSecRadio.announce(set, pty.radio.to, pty.radio.call, what)
end

function CeroSecNet.tearDown(system, object, line, why)
	local pty = CeroSecOS.remoteLine(object.ptys, line)
	if pty == nil then return false end
	-- The other half of the wire's log: a session that ends, with the reason it
	-- was given. Noted here rather than at the several callers, for the reason the
	-- connect wrapper exists.
	CeroSecNet.note(object, "close", line, why or "closed")
	-- The county hears a link go down exactly as it heard it come up. Sent FIRST,
	-- while the pty is still on the table and the machine that dialled can still
	-- be found: a teardown is about to take both of those away.
	if type(pty.radio) == "table" then
		CeroSecNet.announceRadio(system, pty, CeroSecOS.TNC.disconnected)
	end
	local screen = pty.console
	local user = nil
	if type(screen) == "table" then user = screen.user end

	-- Anything the far machine was running for this session goes with it, the
	-- way a rlogind that lost its connection takes the shell with it.
	CeroSecNet.killPty(object, line)
	local far = object:osState()
	if far ~= nil then
		CeroSecOS.remoteClose(far, object.ptys, line, user,
			CeroSecOS.clockOf(system:clockEnv()))
		object:mirrorOS()
	else
		object.ptys[line] = nil
	end

	local home, homeObject = CeroSecNet.diallerOf(system, pty)
	if pty.noTty ~= nil then
		-- A session nobody watched. What it printed is delivered -- into the job
		-- that is waiting for it, which is every rsh -- and the console it was
		-- dialled FROM is left exactly as it is: its `remote` was never set to this
		-- line, and a survivor may well have a session of his own on it.
		--
		-- The status goes with the lines. It is the far command's own, kept on the
		-- pty's console when its job was reaped (runMachine), and it is what `$?`
		-- after an rsh answers. No status at all means nothing ever ran over there
		-- -- a shell the far machine has not got, a machine with no room for the
		-- job -- and rsh answers 1 for that, the way it answers 1 for a connection
		-- it could not make.
		local lines, status = nil, nil
		if type(screen) == "table" then
			lines = screen.lines
			status = tonumber(screen.status)
		end
		if status == nil then status = 1 end
		deliver(system, homeObject, home, pty.noTty, lines, status)
	elseif home ~= nil then
		home.remote = nil
		-- The one glass: what the session printed is what is on the screen.
		if type(screen) == "table" and type(screen.lines) == "table" then
			home.lines = screen.lines
		end
		-- An rsh is one command and not a login, so it says nothing when it is
		-- done: no rsh anybody has ever run printed "Connection closed.".
		if not pty.quiet then CeroSec.consolePush(home, closingLine(pty, why)) end
		if homeObject ~= nil then
			system:pushScreen(homeObject, homeObject:osState(), home)
		end
	end
	return true
end

-- Every job the far machine was running for one pty, gone. A shell whose
-- terminal has been taken away has nothing to write to.
function CeroSecNet.killPty(luaObject, line)
	local book = luaObject.jobs
	if book == nil then return end
	for i = 1, #book.list do
		local job = book.list[i]
		if job.pty == line then CeroSecOS.killJob(job, nil) end
	end
end

-- The near end losing the session: the machine this glass is on going dark, or a
-- chain whose far end is no longer there.
--
-- Always the LINK's teardown and never a hangup, which is why it does not take a
-- reason: every caller of it is a machine or a wire that went away. Escape at an
-- idle remote prompt and `~.` go through endSession instead, and those two are
-- somebody hanging up.
function CeroSecNet.hangUp(system, console)
	local handle = console.remote
	if type(handle) ~= "table" then return false end
	local object = system:getLuaObjectAt(handle.x, handle.y, handle.z)
	if object == nil then
		console.remote = nil
		return true
	end
	return CeroSecNet.tearDown(system, object, handle.line, "carrier")
end

-- The far end hanging up: `exit` on the far machine's own prompt, which is the
-- end of the shell rlogind started and therefore the end of the connection.
-- Answers true when this console was a session's, so that the ordinary logout
-- does not also happen.
function CeroSecNet.endSession(system, luaObject, console)
	if type(console) ~= "table" or type(console.line) ~= "string" then return false end
	return CeroSecNet.tearDown(system, luaObject, console.line)
end

-- Is this screen an rsh's, whose one command is what the session was for?
function CeroSecNet.isOneShot(luaObject, console)
	if type(console) ~= "table" or type(console.line) ~= "string" then return false end
	local pty = CeroSecOS.remoteLine(luaObject.ptys, console.line)
	if pty == nil then return false end
	return pty.quiet and true or false
end

-- A machine going dark, or being picked up: every session ON it ends, and so
-- does every session it had OPEN somewhere else. Run BEFORE the console is
-- thrown away, because the console is what remembers where they went.
function CeroSecNet.closeSessions(system, luaObject)
	-- The sessions its JOBS had open first. An rsh is a job waiting for another
	-- machine and holding a line over there, and a machine that has stopped is not
	-- waiting for anything: it is called before killAll takes the book away
	-- (SCeroSecObject), because the book is what remembers where those lines are.
	local book = luaObject.jobs
	if book ~= nil then
		for i = 1, #book.list do
			local job = book.list[i]
			local at = job.remote
			if type(at) == "table" then
				job.remote = nil
				local object = system:getLuaObjectAt(at.x, at.y, at.z)
				if object ~= nil then CeroSecNet.tearDown(system, object, at.line, "carrier") end
			end
		end
	end
	if type(luaObject.console) == "table" then
		CeroSecNet.hangUp(system, luaObject.console)
	end
	local ptys = CeroSecOS.ptyList(luaObject.ptys)
	for i = 1, #ptys do
		local screen = ptys[i].console
		if type(screen) == "table" then CeroSecNet.hangUp(system, screen) end
	end
	-- And the inbound ones, which have to be told one at a time: each has a
	-- different glass at the other end of it.
	ptys = CeroSecOS.ptyList(luaObject.ptys)
	for i = 1, #ptys do
		-- "carrier", because this is a machine that has STOPPED and not a survivor
		-- hanging up: what the glass at the other end has to read about a call is that
		-- the line went away, which is what a modem says about it.
		CeroSecNet.tearDown(system, luaObject, ptys[i].line, "carrier")
	end
	luaObject.ptys = nil
end

--
-- Dialling
--
-- What the "rlogin" and "rsh" orders come to. Everything the engine could decide
-- it already has -- the name resolved, the wire reached, the hop ceiling paid --
-- so what is left is the two things only the far machine knows: whether it has a
-- line free, and whether it trusts this one.
--

-- The machine whose windows are looking at a console: its own, normally, and for
-- a pty's console the machine at the near end of the chain, which is where the
-- window really is.
function CeroSecNet.watchAtOf(luaObject, console)
	local at = console.watchAt
	if type(at) == "table" then return { x = at.x, y = at.y, z = at.z } end
	return { x = luaObject.x, y = luaObject.y, z = luaObject.z }
end

-- The console a dialled session lands on: a real console, with the fields that
-- say whose glass it is on, what the line is called and how deep the chain is --
-- and with a copy of the lines already on that glass, because there is only one
-- glass (see the head of this section).
local function newPtyConsole(from, pty, watchAt, hops)
	local console = CeroSec.newConsole()
	-- No BIOS on a pty. The boot belongs to the power-on and the machine is
	-- already up: what a caller meets is the login prompt.
	console.booted = true
	console.watchAt = watchAt
	console.line = pty.line
	console.hops = hops
	-- Where the session came from, on the CONSOLE as well as on the pty. The
	-- login path writes wtmp off the console it is standing at
	-- (SCeroSecSystem Commands.input, and the logout in logOut does the same), so
	-- a pty console with no fromHost on it is a session whose "in" record says it
	-- came from nowhere -- which is what the machine's own keyboard says. It was
	-- true of every rlogin that asked for a password since the wire was built; the
	-- telephone is what made it visible, because a call's origin is the only thing
	-- the far machine ever learns about the caller.
	console.fromHost = pty.fromHost
	if type(from) == "table" and type(from.lines) == "table" then
		for i = 1, #from.lines do
			CeroSec.consolePush(console, from.lines[i])
		end
	end
	return console
end

-- A session logged in, with a password or without one. Exactly what
-- Commands.input does when a password is right, so the two cannot drift: the
-- greeting, the account, a fresh shell, the moment, and the line in wtmp.
function CeroSecNet.logIn(system, object, far, pty, account, now)
	local console = pty.console
	console.user = account.name
	console.cwd = account.home or "/"
	console.stack = nil
	console.shvars = CeroSecOS.loginVars(account.home)
	console.status = nil
	console.loginAt = now or 0
	-- No motd on an rsh (pty.quiet): rshd does not print one, login does, and an
	-- rsh is not a login. It matters more than the flavour of it -- what comes back
	-- from an rsh is the far command's output and goes into a pipe, a $(...) or
	-- somebody's mail, and a greeting in there is a line the far command did not
	-- write.
	if not pty.quiet then CeroSec.consolePushAll(console, CeroSecOS.motdLines(far)) end
	if now ~= nil then
		CeroSecOS.wtmpAppend(far, "in", account.name, pty.line, pty.fromHost, now)
		object:mirrorOS()
	end
	return console
end

-- The far machine, its state, this machine's name, and a line on it -- or nil
-- plus which of strerror's words to wear. Shared by rlogin and rsh, because the
-- two differ in exactly one thing and it is not this.
-- found, when the caller has already worked out which machine answers: that is
-- the telephone, where the far end is decided by a number and not by an address
-- and the refusals are the modem's words rather than strerror's.
-- radio, when the link is the air: the { call, to, key } the pty carries, worked
-- out by dialRadio because it is the half that has both sets in its hand.
local function connectTo(system, luaObject, console, cmd, data, found, radio)
	local object = found
	if object == nil then
		object = CeroSecNet.reachable(system, luaObject, data.addr)
		if object == nil then
			return nil, CeroSecOS.netRefusal(cmd, data.host, "unreach")
		end
	end
	local far = object:osState()
	if far == nil then
		return nil, CeroSecOS.netRefusal(cmd, data.host, "down")
	end
	if object.ptys == nil then object.ptys = {} end

	local state = luaObject:osState()
	local fromHost = CeroSecOS.DEFAULT_HOSTNAME
	local fromAddr = nil
	if state ~= nil then fromAddr = CeroSecOS.address(state) end
	-- WHAT THE FAR MACHINE CALLS THIS ONE. Its own /etc/hosts decides, off the
	-- address the session arrived from -- and when no line of it carries that
	-- address, the origin is the dotted quad itself (CeroSecOS.originOf). That is
	-- rlogind's own reverse lookup, and it is deliberately NOT this machine's
	-- /etc/hostname: a hostname is a file its own root may write to anything, so a
	-- far machine that recorded the name a caller announced would be recording
	-- whatever it was told -- and, before this, would have TRUSTED it. What a
	-- machine announces about itself is the business of ruptime and rwho, which are
	-- reports and not credentials.
	if fromAddr ~= nil then
		fromHost = CeroSecOS.originOf(far, fromAddr) or fromAddr
	end
	-- WHERE A CALL SAYS IT CAME FROM. A session that arrived over the wire is
	-- named by the machine it came from, because on one length of coax that name
	-- means something to everybody on it. A call is named by the NUMBER it was
	-- placed from: the far machine has never heard of this one's hostname, has no
	-- line in /etc/hosts for it and no way to check one, and what a survivor over
	-- there needs is the thing he could ring back. So `who` prints (555-0142),
	-- `last` prints it in the host column, and that is what goes into wtmp.
	--
	-- It is also the honest answer to the security question a call raises: an
	-- inbound telephone session is from a stranger, and a number is what a
	-- stranger has instead of a name.
	local phone = nil
	if type(data.tel) == "string" then
		local tel = CeroSecNet.lineOf(luaObject)
		if tel == nil then return nil, CeroSecOS.CU_NO_LINE end
		fromHost = tel
		fromAddr = nil
		phone = { tel = tel, key = CeroSecNet.keyOf(luaObject) }
	end
	-- WHERE A RADIO LINK SAYS IT CAME FROM: the CALLSIGN, for the telephone's
	-- reason taken one step further. The far machine has never heard of this one's
	-- hostname and there is no address in a transmission either -- what arrives
	-- over the air is a callsign, and a callsign is the only thing a survivor over
	-- there could answer back to. So `who` prints (KE4QWZ), `last` prints it in the
	-- host column, and that is what goes into wtmp.
	--
	-- And it is the honest answer to the security question, which is sharper here
	-- than on the telephone: a number is at least a fact about a wall, and a
	-- callsign is a file. What the far machine records is what the caller SAID he
	-- was called.
	if type(radio) == "table" then
		fromHost = radio.call
		fromAddr = nil
	end

	local watchAt = CeroSecNet.watchAtOf(luaObject, console)
	local pty, reason = CeroSecOS.remoteOpen(far, object.ptys, {
		fromHost = fromHost,
		fromAddr = fromAddr,
		want = data.user,
		hops = data.hops,
		at = CeroSecOS.clockOf(system:clockEnv()),
		-- Where the glass is, and who dialled. A chain of rlogins keeps pointing
		-- at the machine the window is actually open on, while `from` names the
		-- console one hop back -- which for a chain is another machine's pty.
		home = watchAt,
	})
	if pty == nil then
		return nil, CeroSecOS.netRefusal(cmd, data.host, reason)
	end
	pty.from = { x = luaObject.x, y = luaObject.y, z = luaObject.z, line = console.line }
	-- And the call it came in on, when that is what it is: the number that dialled
	-- and the building whose line is now busy. It is the whole of what makes this
	-- pty a call rather than a session -- the trickle, the busy rule and the two
	-- endings are all read off it.
	pty.phone = phone
	-- And the link it came in over, when that is what it is. Everything that makes
	-- this pty a radio link rather than a session is read off it: the trickle, the
	-- one-connection-per-set rule, the keystroke-by-keystroke check that the aerial
	-- is still there, the two endings, and the line the county hears.
	pty.radio = radio
	-- A detached session takes no copy of the glass and the glass is not pointed
	-- at it: the near console keeps showing what it was showing, whether that is a
	-- prompt nobody is at or a session a survivor opened himself.
	local noTty = detachedDial(console, data)
	if noTty ~= nil then
		pty.noTty = noTty
		pty.console = newPtyConsole(nil, pty, watchAt, data.hops)
		pty.console.noTty = true
		return pty, object, far, fromHost, fromAddr
	end
	pty.console = newPtyConsole(console, pty, watchAt, data.hops)
	console.remote = { x = object.x, y = object.y, z = object.z, line = pty.line }
	return pty, object, far, fromHost, fromAddr
end

-- The same call, with a line in the wire's log behind it. Wrapped rather than
-- noted at each of the six ways out of connectTo, so a seventh cannot be added
-- without a line: every session on this machine is made or refused HERE.
local function connect(system, luaObject, console, cmd, data, found, radio)
	local pty, object, far, fromHost, fromAddr =
		connectTo(system, luaObject, console, cmd, data, found, radio)
	if pty ~= nil then
		CeroSecNet.note(luaObject, cmd, askedFor(data, radio),
			"open " .. tostring(pty.line) .. " as " .. tostring(fromHost))
	end
	-- A refusal is NOT noted here: every refusal about the wire, the telephone and
	-- the air is decided in the three reachable* doors above and is noted there, and
	-- a second line for the same "no" would be one fact twice.
	return pty, object, far, fromHost, fromAddr
end

-- rlogin: a login prompt on the far machine, unless a trust file says the
-- password may be skipped.
--
-- The name asked for with -l is what the trust files are asked about; the login
-- prompt still asks for a name, because this machine's login is a login and not
-- a protocol handshake with a user name in it. The manual says so.
function CeroSecNet.dial(system, luaObject, console, data)
	local pty, object, far, fromHost, fromAddr =
		connect(system, luaObject, console, "rlogin", data)
	if pty == nil then return nil, object end
	local account = CeroSecOS.getUser(far, data.user)
	-- The trust question is asked about the ADDRESS the session came from and never
	-- about fromHost, which is only what the far machine has decided to CALL it.
	if account ~= nil and CeroSecOS.trusts(far, data.user, fromAddr, data.from) then
		CeroSecNet.logIn(system, object, far, pty, account,
			CeroSecOS.clockOf(system:clockEnv()))
		pty.trusted = true
	end
	return pty, object, far
end

-- cu: the same session down the telephone, and always a password.
--
-- No trust file is asked, and that is not an omission: /etc/hosts.equiv and
-- ~/.rhosts are lists of MACHINES, and the far machine cannot tell which machine
-- is on the other end of a telephone call -- there is no address in a call, only
-- a number, and a number is a building. ruserok has never had an answer for one.
-- So the caller meets `login:` and `password:` however trusted his own computer
-- is on its own coax, which is also the only thing standing between a county full
-- of survivors and everybody else's disks.
--
-- The refusals here are the modem's words and they come back as ONE line, which
-- is what a modem gives you: the reason a call did not happen is the last thing
-- printed before the receiver goes down.
function CeroSecNet.dialPhone(system, luaObject, console, data)
	local found, word = CeroSecNet.ringAnswer(system, luaObject, data.tel)
	if found == nil then return nil, word end
	local pty, object, far = connect(system, luaObject, console, "cu", data, found)
	-- The one thing left that can refuse a call the exchange put through: a far
	-- machine with all four of its lines taken by sessions off its own coax. It is
	-- a busy signal and not a "connection refused" -- a caller with a receiver to
	-- his ear hears the same tone whether the line is in use or the switchboard is
	-- full. (object carries connect's own refusal line, which is not a modem's.)
	if pty == nil then return nil, CeroSecOS.MODEM.busy end
	-- The modem's own two lines, then cu's, on the glass the call is now on: the
	-- pty's console carries a copy of everything that was on the screen, so these
	-- land under the `cu` the survivor typed and above the far machine's `login:`.
	CeroSec.consolePush(pty.console, CeroSecOS.MODEM.connect)
	CeroSec.consolePush(pty.console, CeroSecOS.CU_CONNECTED)
	return pty, object, far
end

-- call: the same session over the air, and always a password.
--
-- No trust file is asked, and here it is not merely that /etc/hosts.equiv and
-- ~/.rhosts are lists of MACHINES. A callsign is a file root can write
-- (/etc/callsign), so a machine that trusted one would be trusting a string
-- anybody with a radio and an editor can choose. The caller meets `login:` and
-- `password:` however trusted his own computer is on its own coax, and however
-- respectable the callsign he announced.
--
-- The refusals are the TNC's words and come back as ONE line, which is what a
-- TNC gives you: the reason a link did not happen is the last thing it prints
-- before the prompt comes back.
function CeroSecNet.dialRadio(system, luaObject, console, data)
	local found, word, mine, theirs = CeroSecNet.reachableRadio(system, luaObject, data.call)
	if found == nil then return nil, word end
	-- A machine with no operating system on it -- one sitting at the firmware's
	-- own question -- has nothing to answer a connect with. The retries run out,
	-- which is all a station ever learns about it.
	if found:osState() == nil then return nil, CeroSecOS.TNC.retry end
	-- Whose station this is, read off this machine's own disk. It cannot be nil:
	-- the command refused a machine with no callsign before the order was given.
	local call = CeroSecNet.callsignOf(luaObject)
	if call == nil then return nil, CeroSecOS.CALL_NO_CALLSIGN end
	local radio = { call = call, to = data.call, key = CeroSecRadio.keyOf(mine) }
	local pty, object, far = connect(system, luaObject, console, "call", data, found, radio)
	-- The one thing left that can refuse a link the air carried: a far machine with
	-- all four of its lines taken by sessions off its own coax. It is the TNC's
	-- busy and not a "connection refused" -- a station that hears a DM back hears
	-- the same thing whether the far TNC has a link already or the far computer has
	-- no terminal left. (object carries connect's own refusal line, which is not a
	-- TNC's.)
	if pty == nil then return nil, CeroSecOS.TNC.busy end
	-- The TNC's own line on the glass the link is now on: the pty's console carries
	-- a copy of everything that was on the screen, so this lands under the `call`
	-- the survivor typed and above the far machine's `login:`.
	CeroSec.consolePush(pty.console, CeroSecOS.TNC.connected .. data.call)
	-- And the same event on the air, which is the half that is not on anybody's
	-- glass: every walkie in the county tuned to that frequency and inside the
	-- weaker of the two ranges reads it. Sent here rather than from tearDown's
	-- counterpart so that both ends of a link are announced by the one set, in the
	-- one place, with the one pair of callsigns.
	CeroSecRadio.announce(mine, data.call, call, CeroSecOS.TNC.onAir)
	return pty, object, far
end

-- rsh: one command, the caller's account, and no password ever. Trust or
-- nothing, which is rshd's whole protocol.
function CeroSecNet.remoteCommand(system, luaObject, console, data)
	local object = CeroSecNet.reachable(system, luaObject, data.addr)
	if object == nil then
		return nil, CeroSecOS.netRefusal("rsh", data.host, "unreach")
	end
	local far = object:osState()
	if far == nil then
		return nil, CeroSecOS.netRefusal("rsh", data.host, "down")
	end
	local state = luaObject:osState()
	local fromAddr = nil
	if state ~= nil then fromAddr = CeroSecOS.address(state) end
	-- Judged before a line is taken: a caller it will not trust is not a caller
	-- it should spend a pty on. The caller is its ADDRESS -- see the trust note in
	-- connect() above -- and a machine with no wire in it has none and is trusted
	-- by nobody.
	local account = CeroSecOS.getUser(far, data.user)
	if account == nil or not CeroSecOS.trusts(far, data.user, fromAddr, data.from) then
		return nil, CeroSecOS.netRefusal("rsh", data.host, "denied")
	end

	local pty, refused, farAgain = connect(system, luaObject, console, "rsh", data)
	if pty == nil then return nil, refused end
	-- An rsh is one command and not a login: it says nothing when it ends, and
	-- the session ends when the command does.
	pty.quiet = true
	CeroSecNet.logIn(system, object, farAgain, pty, account,
		CeroSecOS.clockOf(system:clockEnv()))
	return pty, object, farAgain
end

-- The order, carried out. Called from the scheduler, after the screen carrying
-- the line that was typed has gone out.
-- forJob is the job the order came off, for an rsh: it is WAITING on this dial
-- and is still on the machine's book. What it gets is the far line to hang up (so
-- Escape and `kill` reach across the wire), or the refusal and a status if the
-- dial never happened at all.
function CeroSecNet.answerDial(system, luaObject, console, control, data, playerObj, forJob)
	if type(data) ~= "table" then return end
	local state = luaObject:osState()
	local noTty = detachedDial(console, data)
	-- The engine refuses an rlogin with no terminal where it was written
	-- (CeroSecOSVM applyControl), and this is the same rule standing at the door:
	-- a screen nobody is watching is not a terminal to hand a session, whichever
	-- way the order got here. What it says goes where the sheet goes.
	if (control == "rlogin" or control == "cu" or control == "call") and noTty ~= nil then
		deliver(system, luaObject, console, noTty, { control .. ": not a terminal" })
		return
	end
	local pty, object, far, refusal = nil, nil, nil, nil
	if control == "rlogin" then
		pty, object, far = CeroSecNet.dial(system, luaObject, console, data)
	elseif control == "cu" then
		pty, object, far = CeroSecNet.dialPhone(system, luaObject, console, data)
	elseif control == "call" then
		pty, object, far = CeroSecNet.dialRadio(system, luaObject, console, data)
	else
		pty, object, far = CeroSecNet.remoteCommand(system, luaObject, console, data)
	end
	if pty == nil then
		-- object carries the line to print when the dial failed.
		refusal = object
		-- A refusal the far machine handed back -- no line free, no trust -- is
		-- the only thing a detached dial ever says, and it says it where the job
		-- that dialled was printing. Every refusal the ENGINE could work out was
		-- printed by the command itself, long before this.
		--
		-- A job waiting on it is let go here, with the status rsh answers when it
		-- could not get through: a script whose rsh was refused goes on to its next
		-- line, and it is the refusal and not a hang that it goes on from.
		if noTty ~= nil then
			deliver(system, luaObject, console, noTty, { tostring(refusal) }, 1, true)
			return
		end
		CeroSec.consolePush(console, tostring(refusal))
		if state ~= nil then system:pushScreen(luaObject, state, console) end
		return
	end

	-- The glass is the session's now. Pushed from the FAR machine, because that
	-- is whose hostname, whose prompt and whose files the screen is about. A
	-- detached session has no glass, and pushScreen knows it.
	system:pushScreen(object, far, pty.console)

	if control == "rsh" then
		-- Which line on which machine the job that is waiting has to hang up, if
		-- it is killed or its session goes away before the far command is done.
		-- Written before the far job is started, because the far job may be over
		-- inside this very call.
		if type(forJob) == "table" and not CeroSecOS.jobIsOver(forJob) then
			forJob.remote = { x = object.x, y = object.y, z = object.z, line = pty.line }
		end
		-- The line it was given, as the pty's own foreground job. The shell is a
		-- file over there like everything else, so a machine whose /bin/sh has
		-- been deleted answers an rsh the way it answers a survivor.
		local farJob = system:startPrompt(object, pty.console, data.cmd, playerObj, nil)
		-- And a machine that could not start it at all -- no shell, no room on its
		-- own job book -- is a session with nothing in it. It is closed here rather
		-- than left open: what the far machine said about it is on that console and
		-- is delivered by the teardown, and a job waiting on a session nothing is
		-- ever going to run is a job that would wait for ever.
		if farJob == nil then CeroSecNet.tearDown(system, object, pty.line) end
	elseif pty.trusted then
		-- A trusted login skipped the password, so it owes the account the two
		-- things a login owes it: its own history, and its own ~/.profile.
		system:runProfile(object, pty.console, playerObj, nil)
	end
end
