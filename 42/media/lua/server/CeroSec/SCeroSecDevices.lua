if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSDev"

--
-- The world, as devices.
--
-- The engine knows nothing about Project Zomboid: it renders /dev and refuses
-- what may not be written, and everything that touches a light switch, a door
-- or a window happens HERE. What the two agree on is a list of entries and one
-- call (see the head of CeroSecOSDev.lua).
--
-- What a machine can reach
--
-- Its own building when its square has one -- every room of it -- and a radius
-- of ten tiles on the same z when it has not, which is what a computer standing
-- in a player-built base gets: a base has no building and no rooms.
--
-- Nothing outside the loaded world exists. The game only keeps the chunks
-- around the players (13x13 of 8 tiles) and there is no unload event, so a
-- device is not "gone", it is simply not found this pass -- and a machine in a
-- town nobody is standing in cannot act on anything. That is why the discovery
-- runs afresh at every command instead of being remembered: the answer is only
-- true for the moment it is asked.
--
-- The numbers
--
-- light0 is the same light switch tomorrow as it is today. The numbering is
-- worked out once, from the candidates sorted by (kind, x, y, z, side), and
-- then written into the machine's own state at os.devmap, keyed by where the
-- device is. A device that goes away leaves its entry there -- the number is
-- spent for the life of that machine -- so nothing is ever renumbered under a
-- player who wrote "echo off > /dev/light3" into a script.
--
--   state.devmap["light:1024:998:0::0"] = { id = "light0", kind = "light",
--                                           n = 0, mode = 660 }
--
-- The mode rides along, because a chmod on a device has to outlive the command
-- it was typed in and the node itself is thrown away at the end of one.
--
-- The calls, and why these ones
--
-- Every one of them is verified with javap against
-- projectzomboid.jar (42.20.4) and used the way the game's own Lua uses it. The
-- point that matters is WHO BROADCASTS: our writes happen on the server, and
-- most of vanilla's happen on a client, so a setter that syncs for a player
-- does not necessarily sync for us.
--
--   light   IsoLightSwitch:setActive(on)
--           setActive(Z) -> setActive(Z,Z,Z), which ends on
--           syncIsoObject(false, activated, null); that method's server branch
--           walks GameServer.udpEngine.connections and sends SyncIsoObject to
--           each. So the light syncs ITSELF from the server and we add nothing.
--           It also answers with the state it settled on, which is why the
--           result is read back rather than assumed.
--
--   lock    IsoDoor:setLockedByKey(locked) then
--           syncIsoObject(false, 0, nil, nil)
--           setLockedByKey(Z,Z) explicitly SKIPS its own sync when
--           GameServer.server is true, so the sync is ours to make -- exactly
--           the pair vanilla makes in
--           media/lua/shared/TimedActions/ISLockDoor.lua:52-56.
--           IsoObject:syncIsoObject with bClient false is the server broadcast.
--
--   win     IsoWindow:setIsLocked(locked) then
--           syncIsoObject(false, 0, nil, nil)
--           setIsLocked is a bare field write with no sync of any kind, and
--           IsoWindow:syncIsoObjectSend writes `locked` into the packet.
--
--   lock    IsoThumpable:setLockedByPadlock(locked)
--   (built) which calls syncIsoThumpable() itself, and syncIsoThumpable's
--           server branch is INetworkPacket.sendToRelative(SyncThumpable, ...).
--           So a padlock syncs itself. A player door held by a key goes through
--           setLockedByKey, which skips its sync on the server like the map
--           door's, so syncIsoThumpable() is called by hand after it.
--

CeroSecDevices = CeroSecDevices or {}

-- Tiles around the machine, on its own z, when it is not in a building.
CeroSecDevices.RADIUS = 10

-- How many entries os.devmap may hold. A number spent is spent for the life of
-- the machine, so this is what stops a computer carried across the map from
-- growing a book of dead devices in the save file.
CeroSecDevices.MAP_MAX = 128

-- The room a square is in, by its raw id ("kitchen", "office"), or nil.
local function roomName(square)
	if square == nil then return nil end
	local room = square:getRoom()
	if room == nil then return nil end
	local name = room:getName()
	if type(name) ~= "string" or name == "" then return nil end
	return name
end

--
-- Classifying one object
--
-- nil when it is not a device. The state strings are the machine's whole
-- vocabulary and are written here, once.
--

local function doorDesc(door)
	local here = roomName(door:getSquare())
	local there = roomName(door:getOppositeSquare())
	-- A door with nothing but the outdoors on one side of it is the way in.
	if here == nil or there == nil then return "exterior" end
	if here == there then return here end
	return here .. "-" .. there
end

local function windowState(win)
	-- Broken and boarded first: either of them is what a survivor needs to be
	-- told, and neither is something a lock has anything to say about.
	if win:isSmashed() then return "smashed" end
	if win:isBarricaded() then return "barricaded" end
	if win:isLocked() then return "locked" end
	return "unlocked"
end

local function thumpState(thump)
	if thump:isLockedByPadlock() then return "padlock" end
	if thump:isLockedByKey() then return "locked" end
	return "unlocked"
end

function CeroSecDevices.classify(object)
	if object == nil then return nil end

	if instanceof(object, "IsoLightSwitch") then
		return {
			kind = "light", side = "",
			desc = roomName(object:getSquare()) or "exterior",
			state = object:isActivated() and "on" or "off",
		}
	end

	if instanceof(object, "IsoDoor") then
		return {
			kind = "lock",
			side = object:getNorth() and "N" or "W",
			desc = doorDesc(object),
			state = object:isLockedByKey() and "locked" or "unlocked",
		}
	end

	if instanceof(object, "IsoWindow") then
		return {
			kind = "win",
			side = object:getNorth() and "N" or "W",
			desc = roomName(object:getSquare()) or "exterior",
			state = windowState(object),
		}
	end

	-- Player-built. A base has no building and no rooms, so there is no room id
	-- to name it with and "built" is the truth about it. Only doors: a
	-- player-built window frame has no lock this rung.
	if instanceof(object, "IsoThumpable") and object:isDoor() then
		return {
			kind = "lock",
			side = object:getNorth() and "N" or "W",
			desc = "built",
			state = thumpState(object),
		}
	end

	return nil
end

--
-- Where it is
--
-- Room ids repeat -- a big house has three doors whose description is the same
-- word -- so the thing that tells two devices apart is where they are, and that
-- is what this column is: how far east or west of the machine, how far north or
-- south, and the floor when it is not the machine's own.
--
--   3E 2N      three tiles east and two north of the computer
--   0 2N       due north of it
--   0 0        its own square
--   3E 2N +1   one floor up
--
-- The axes are the game's own: x grows to the EAST and y grows to the SOUTH
-- (IsoGridSquare's getX/getY, the same pair every vanilla direction helper
-- reads), so a device with a smaller y than the machine's is north of it. Both
-- halves are always printed, a zero as a bare "0", so the column reads as one
-- shape and never as a sentence.
--
-- Pure arithmetic, and deliberately: it is the one part of a device's line that
-- can be proved without a world under it (tests/window_test.lua).
function CeroSecDevices.offset(dx, dy, dz)
	local east = "0"
	if dx > 0 then
		east = tostring(dx) .. "E"
	elseif dx < 0 then
		east = tostring(-dx) .. "W"
	end

	local north = "0"
	if dy > 0 then
		north = tostring(dy) .. "S"
	elseif dy < 0 then
		north = tostring(-dy) .. "N"
	end

	local out = east .. " " .. north
	if dz > 0 then
		out = out .. " +" .. tostring(dz)
	elseif dz < 0 then
		out = out .. " " .. tostring(dz)
	end
	return out
end

--
-- Finding them
--

local function scanSquare(square, found, seen)
	if square == nil then return end
	local objects = square:getObjects()
	if objects == nil then return end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local entry = CeroSecDevices.classify(object)
		if entry ~= nil then
			entry.x, entry.y, entry.z = x, y, z
			entry.object = object
			-- Where it is, as a string, and that is the key its number hangs
			-- on. Two devices of one kind facing the same way on one square are
			-- told apart by an ordinal -- the object index would have done it
			-- too, and it is not stable across a reload.
			local base = entry.kind .. ":" .. x .. ":" .. y .. ":" .. z .. ":" .. entry.side
			local n = 0
			while seen[base .. ":" .. n] do n = n + 1 end
			entry.key = base .. ":" .. n
			seen[entry.key] = true
			found[#found + 1] = entry
		end
	end
end

-- Every device the machine at x, y, z can reach right now, unnumbered.
function CeroSecDevices.find(x, y, z)
	local found, seen = {}, {}
	if getCell == nil then return found end
	local cell = getCell()
	if cell == nil then return found end

	local square = cell:getGridSquare(x, y, z)
	local building = nil
	if square ~= nil then building = square:getBuilding() end

	if building ~= nil then
		-- Every room of the building, through its definition: BuildingDef
		-- getRooms() is an ArrayList of RoomDef (the way
		-- media/lua/shared/Util/BuildingHelper.lua reads it), and a RoomDef
		-- answers getIsoRoom() with the live room -- nil while its chunks are
		-- not loaded, which is a room the machine cannot act on.
		local def = building:getDef()
		local rooms = nil
		if def ~= nil then rooms = def:getRooms() end
		if rooms ~= nil then
			for i = 0, rooms:size() - 1 do
				local room = rooms:get(i):getIsoRoom()
				if room ~= nil then
					local squares = room:getSquares()
					if squares ~= nil then
						for j = 0, squares:size() - 1 do
							scanSquare(squares:get(j), found, seen)
						end
					end
				end
			end
		end
		return found
	end

	-- No building: a square of ten tiles around the machine, on its own floor.
	-- A square the game has not loaded is simply nil and is skipped.
	local r = CeroSecDevices.RADIUS
	for dx = -r, r do
		for dy = -r, r do
			scanSquare(cell:getGridSquare(x + dx, y + dy, z), found, seen)
		end
	end
	return found
end

--
-- Numbering them
--

-- The order the numbers are handed out in, and it must not depend on the order
-- the world was walked in: kind, then x, then y, then z, then the side, then
-- the ordinal that tells two devices on one square apart.
local function before(a, b)
	if a.kind ~= b.kind then return a.kind < b.kind end
	if a.x ~= b.x then return a.x < b.x end
	if a.y ~= b.y then return a.y < b.y end
	if a.z ~= b.z then return a.z < b.z end
	if a.side ~= b.side then return a.side < b.side end
	return a.key < b.key
end

-- The book of numbers, made when it is first needed.
local function devmapOf(state)
	if type(state.devmap) ~= "table" then state.devmap = {} end
	return state.devmap
end

-- Give every found device its id, out of the book or freshly out of the
-- smallest number that kind has never used. Answers the entries, plus the ones
-- the book knows and the world did not hand back.
function CeroSecDevices.number(state, found)
	local map = devmapOf(state)

	local used, entries = {}, 0
	for _, record in pairs(map) do
		if type(record) == "table" and type(record.kind) == "string"
				and type(record.n) == "number" then
			used[record.kind .. ":" .. record.n] = true
		end
		entries = entries + 1
	end

	table.sort(found, before)

	local live = {}
	for i = 1, #found do
		local entry = found[i]
		local record = map[entry.key]
		if type(record) ~= "table" or type(record.id) ~= "string" then
			-- A number is spent for the life of the machine, so the book is
			-- capped: a computer carried across the map must not grow one entry
			-- per light switch in the county.
			if entries < CeroSecDevices.MAP_MAX then
				local n = 0
				while used[entry.kind .. ":" .. n] do n = n + 1 end
				used[entry.kind .. ":" .. n] = true
				record = { id = entry.kind .. tostring(n), kind = entry.kind, n = n,
					mode = CeroSecOS.DEV_MODE }
				map[entry.key] = record
				entries = entries + 1
			else
				record = nil
			end
		end
		if record ~= nil then
			entry.id = record.id
			if type(record.mode) == "number" then entry.mode = record.mode end
			live[#live + 1] = entry
		end
	end

	return live
end

--
-- What the engine is handed
--

-- One machine's devices, discovered now. Everything below closes over this one
-- table, so list() and write() cannot disagree about what is there.
local function build(luaObject, state)
	local live = CeroSecDevices.number(state, CeroSecDevices.find(luaObject.x, luaObject.y, luaObject.z))

	local byId, seen = {}, {}
	local list = {}
	for i = 1, #live do
		local entry = live[i]
		byId[entry.id] = entry
		seen[entry.id] = true
		list[#list + 1] = {
			id = entry.id, kind = entry.kind, desc = entry.desc,
			side = entry.side, state = entry.state,
			-- Where it is, from where the machine is standing. Worked out here
			-- and not by the engine: the engine has no idea there are tiles.
			pos = CeroSecDevices.offset(entry.x - luaObject.x, entry.y - luaObject.y,
				entry.z - luaObject.z),
			mode = entry.mode or CeroSecOS.DEV_MODE,
		}
	end

	-- And the numbers the machine remembers and cannot reach. They are mounted
	-- but never listed, so that a player who wrote one down is told "no such
	-- device" instead of "no such file" -- the difference between a device that
	-- is out of reach and a path he mistyped.
	local map = devmapOf(state)
	for _, record in pairs(map) do
		if type(record) == "table" and type(record.id) == "string" and not seen[record.id] then
			if #list >= CeroSecOS.DEV_MAX then break end
			seen[record.id] = true
			list[#list + 1] = {
				id = record.id, kind = record.kind, dead = true,
				mode = record.mode or CeroSecOS.DEV_MODE,
			}
		end
	end

	return list, byId, map
end

-- Is the object we found still where we found it? Belt and braces: list() and
-- write() happen inside one command, so nothing should have moved -- but a
-- Java handle to an object that has been taken off its square is exactly the
-- kind of thing that answers questions and changes nothing.
local function alive(entry)
	local object = entry.object
	if object == nil then return false end
	local square = object:getSquare()
	if square == nil then return false end
	return square:getX() == entry.x and square:getY() == entry.y and square:getZ() == entry.z
end

-- The world action, per kind. ok, reason, state.
local function act(entry, value)
	local object = entry.object

	if entry.kind == "light" then
		local want = value == "on"
		-- The switch's own rule for whether it can be thrown at all: a bulb,
		-- and electricity or a charged battery (IsoLightSwitch.canSwitchLight).
		-- A switch with no bulb in it reads the same way, which is what a
		-- survivor flicking it would find too.
		if not object:canSwitchLight() then return false, "no power" end
		object:setActive(want)
		-- setActive syncs itself from the server and answers with what it
		-- settled on; the state is read back rather than assumed.
		local now = object:isActivated() and "on" or "off"
		if (now == "on") ~= want then return false, "no power" end
		return true, nil, now
	end

	if entry.kind == "win" then
		if object:isSmashed() then return false, "smashed" end
		if object:isBarricaded() then return false, "barricaded" end
		object:setIsLocked(value == "lock")
		object:syncIsoObject(false, 0, nil, nil)
		return true, nil, windowState(object)
	end

	-- lock: a map door, or a player-built one.
	if instanceof(object, "IsoDoor") then
		object:setLockedByKey(value == "lock")
		object:syncIsoObject(false, 0, nil, nil)
		return true, nil, object:isLockedByKey() and "locked" or "unlocked"
	end

	local want = value == "lock"
	if object:isLockedByPadlock() or object:canBeLockByPadlock() then
		-- setLockedByPadlock syncs itself, on the server included.
		object:setLockedByPadlock(want)
		return true, nil, thumpState(object)
	end
	-- A padlock is set to keyId -1 when it is taken off
	-- (media/lua/shared/TimedActions/ISPadlockAction.lua:46), and a door built
	-- with no lock at all carries 0, so a real key is a positive one.
	if object:getKeyId() > 0 then
		object:setLockedByKey(want)
		object:syncIsoThumpable()
		return true, nil, thumpState(object)
	end
	return false, "no padlock"
end

-- The env.devices table for one machine. Built once per command: the discovery
-- is the expensive half and nothing may ask the world twice inside one line and
-- get two answers.
function CeroSecDevices.envFor(luaObject, state)
	local list, byId, map = build(luaObject, state)

	return {
		list = function()
			return list
		end,

		write = function(id, value)
			local entry = byId[id]
			if entry == nil or not alive(entry) then return false, "no such device" end
			local ok, reason, after = act(entry, value)
			if not ok then return false, reason end
			-- The list the engine is holding is updated too, so a `cat` in the
			-- same breath agrees with what was just done.
			if type(after) == "string" then
				entry.state = after
				for i = 1, #list do
					if list[i].id == id then list[i].state = after end
				end
			end
			return true, nil, after
		end,

		-- A chmod on a device node. The node itself is thrown away at the end of
		-- the command, so this is where the new mode survives.
		chmod = function(id, mode)
			for key, record in pairs(map) do
				if type(record) == "table" and record.id == id then
					record.mode = mode
					return
				end
			end
		end,
	}
end

-- The one-minute sweep. Nothing on a screen changes -- a line already printed
-- is a line already printed -- but the book of numbers is brought up to date,
-- so a device that appeared since the machine was last used already has its
-- number by the time somebody types `ls /dev`.
function CeroSecDevices.refresh(luaObject, state)
	if state == nil then return end
	CeroSecDevices.number(state, CeroSecDevices.find(luaObject.x, luaObject.y, luaObject.z))
end
