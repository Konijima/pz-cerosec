if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecModules"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSDev"
require "CeroSec/SCeroSecSensors"
require "CeroSec/SCeroSecRadio"

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
-- Nothing it is not WIRED to, which is rung 4f's whole change: a light switch is
-- in /dev because somebody screwed a relay to it, a door because somebody fitted
-- an operator, a strike or a magnetic contact, a window because somebody fitted
-- a contact. The four modules, what each one buys and where they are kept are in
-- CeroSecModules.lua (shared, because the right-click menu asks the same
-- questions); the gate itself is `fittedOn` and `has` in classify, below.
--
-- The sandbox option CeroSec.HardwareRequired turns it off, and off is the world
-- exactly as it was before this rung -- every door, window, lock and light of the
-- building, with the same numbers -- which is why `fitted == nil` reads as "yes"
-- everywhere rather than as a second code path.
--
-- And of what it is wired to: its own building when its square has one -- every
-- room of it -- and a radius of ten tiles on the same z when it has not, which
-- is what a computer standing in a player-built base gets: a base has no
-- building and no rooms.
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
--   find    IsoObject:setHighlighted(playerNum, on, false), plus
--   (client) setHighlightColor / setOutlineHighlight / setOutlineHighlightCol
--           on the same playerNum, which is exactly the four vanilla makes on
--           hover in media/lua/client/ISUI/ISWorldObjectContextMenu.lua:281-287
--           (onHighlightWorldItem). javap has all four on zombie.iso.IsoObject
--           with an int first argument: that int is the LOCAL player (split
--           screen), so a highlight is drawn for one pair of eyes and nobody
--           else's -- which is what we want, and why this half is the client's
--           and travels as a message.
--
--   lock    IsoThumpable:setLockedByPadlock(locked)
--   (built) which calls syncIsoThumpable() itself, and syncIsoThumpable's
--           server branch is INetworkPacket.sendToRelative(SyncThumpable, ...).
--           So a padlock syncs itself. A player door held by a key goes through
--           setLockedByKey, which skips its sync on the server like the map
--           door's, so syncIsoThumpable() is called by hand after it.
--
--   door    IsoDoor:ToggleDoorSilent() / IsoThumpable:ToggleDoorSilent(), then
--           syncIsoObject(false, 0, nil, nil)
--           Silent is the whole point: ToggleDoor(character) needs a character,
--           plays a sound at him and walks every leaf of a double door through
--           forEachDoorObject. A machine has no character, so the call that
--           moves one door and nothing else is the right one -- and it is the
--           call vanilla's own Lua makes when a script opens a door with nobody
--           holding it (media/lua/client/Tutorial/Steps.lua:1288 and :1795,
--           Tutorial1.lua:331).
--           Its bytecode is: isBarricaded -> return (so a barricaded door is
--           refused HERE, by us, or the order would be swallowed in silence),
--           InvalidateSpecialObjectPaths, the LOS caches, setRecalcLightTime,
--           then setOpen(!isOpen()) and the sprite swap. No sync of any kind,
--           so the broadcast is ours -- and it is syncIsoObject and not
--           syncIsoThumpable even for a player door: SyncThumpablePacket
--           carries lockedByCode, lockedByPadlock and keyId and NOTHING else,
--           while both classes' syncIsoObjectSend writes the open flag
--           (IsoDoor: isOpen(); IsoThumpable: the open field).
--
--   sensor  nothing at all. A motion sensor is a device that is only ever READ,
--           and what it reads is not a question asked of the item lying on the
--           floor -- there is nothing on a dropped item to ask -- but what the
--           sampling book says its contact is doing. The item, its range, the
--           field of view and the once-a-second sample are all in
--           SCeroSecSensors.lua, which is where the javap for them is too.
--           Here it is one more kind in the discovery, read through
--           IsoGridSquare:getWorldObjects() instead of getObjects() because a
--           dropped item is not on the square's object list.
--
-- The lock, and the one place it means anything
--
-- A keyed door only stops a survivor who is on the wrong side of it, which is
-- why `lock` devices are no longer made for every door:
--
--   IsoDoor.couldBeOpen(chr) reads, in order: an animal is false, isBarricaded
--   is false, and then canBeOpenFromInside(chr) returns TRUE AND RETURNS --
--   before the isLockedByKey / haveThisKeyId branch is ever reached.
--   canBeOpenFromInside is: chr is an IsoPlayer, chr.isOutside() is false, and
--   chr's room is the door's own square's room or its opposite square's room,
--   and the door has no "forceLocked" property.
--
-- So from inside, a locked map door always opens; the lock is a fact about the
-- OUTSIDE of a building. A door with a room on both sides has no outside, and a
-- lock on it is a device that lies.
--
-- A player-built door is the same shape with a different test: IsoThumpable's
-- ToggleDoorActual and couldBeOpen both gate isLockedByKey on
-- chr.getCurrentSquare().has(IsoFlagType.exterior) -- the square the survivor is
-- standing on, not which side of a building it is. A base door is reachable from
-- an exterior square by construction, so every player-built door stays a `lock`
-- device exactly as it was.
--
-- And the padlock, which was the open question: a padlock does NOT stop a door
-- from being opened, from either side. IsoThumpable.ToggleDoorActual has no
-- lockedByPadlock branch at all and neither has couldBeOpen; the only reader is
-- isLockedToCharacter, which answers true for a padlock with no key in the
-- inventory and no side test whatever -- and its callers are the CONTAINER ones
-- (media/lua/server/ISObjectClickHandler.lua:283, client/ISUI/ISInventoryPage.lua)
-- plus the pick-up refusal in shared/Moveables/ISMoveableSpriteProps.lua:1222.
-- A padlock locks what is inside the door, not the door. That is why `padlock`
-- is a `lock` state and never a `door` one.
--

CeroSecDevices = CeroSecDevices or {}

-- Tiles around the machine, on its own z, when it is not in a building.
CeroSecDevices.RADIUS = 10

-- Pointing at one
--
-- `dev find` has to answer the one question a listing cannot: WHICH of the
-- thirty-five it is. A light says so itself -- it blinks, and everybody in the
-- room sees it. A door and a window have nothing to do that with, so the
-- requesting player's own client draws an outline around it and nobody else's
-- does.
--
-- The blink is a server-side timer, and the timer is Events.OnTick gated on
-- getTimestampMs(), which is vanilla's own way of getting under a minute on a
-- server: media/lua/server/Foraging/forageServer.lua:455-460 keeps a
-- _nextRelevanceMs and returns early until the clock passes it, registered at
-- line 502 with Events.OnTick.Add. EveryOneMinute, which is what the rest of
-- this mod runs on, cannot blink anything.
-- How long a flip lasts. How long the whole blink lasts is NOT here: the engine
-- hands the seconds over with the request (CeroSecOS.DEV_FIND_SECONDS), so
-- there is one number for it and it is the one the manual quotes.
CeroSecDevices.BLINK_MS = 500

-- The lights blinking right now. Never saved: a blink is six seconds long and a
-- reload is the end of it, which is the right end for a thing whose whole
-- purpose is to answer a question somebody asked ten seconds ago.
CeroSecDevices.blinks = {}

-- How many entries os.devmap may hold. A number spent is spent for the life of
-- the machine, so this is what stops a computer carried across the map from
-- growing a book of dead devices in the save file.
CeroSecDevices.MAP_MAX = 128

-- The room a square is in, by its raw id ("kitchen", "office"), or nil.
--
-- Both of these moved to CeroSecModules (shared) at rung 4f and are forwarded
-- here so that every call site below reads as it always did. They moved because
-- the right-click menu asks the same two questions -- is this a door a lock
-- means anything on? -- and a client cannot load a server file, and a rule
-- written on both sides is a rule that drifts.
local function roomName(square)
	return CeroSecModules.roomName(square)
end

--
-- Classifying one object
--
-- nil when it is not a device, otherwise the LIST of devices it is -- one
-- object can be two, because an exterior door is both the thing that opens and
-- the thing that locks, and a survivor works those with different words. The
-- state strings are the machine's whole vocabulary and are written here, once.
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

-- Does this map door's lock stop anybody? Its own isExterior() first -- the
-- square carries the exterior flag and the far side is a building with a def,
-- or the other way round -- and then the rooms, because a door whose two sides
-- have a room on exactly one of them is a way out of the building whatever the
-- tile flags say. The room test is the same reading doorDesc makes, so a device
-- whose description says "exterior" is always one the lock means something on.
local function doorLocks(door)
	return CeroSecModules.doorLocks(door)
end

-- One leaf of a double or a garage door. ToggleDoorSilent moves ONE object, and
-- vanilla's own toggle walks every leaf of the thing (forEachDoorObject, inside
-- ToggleDoorActual), so a machine that called Silent on one half would leave the
-- other half shut. Those are not `door` devices -- they are still `lock` ones,
-- because setLockedByKey is per-object in vanilla too.
--
-- `IsoDoor.getGarageDoorIndex(object) ~= -1` is vanilla's own way of asking
-- (media/lua/server/BuildingObjects/ISBuildUtil.lua:556, and :315 of
-- ISDoubleDoor.lua for the double-door one). Both are public statics and both
-- answer -1 for an object with no DOUBLE_DOOR / GARAGE_DOOR property on it.
-- Moved to CeroSecModules with the two above and for the same reason: an
-- operator is refused on a leaf of a garage door at the menu, by this test.
local function isManyDoors(object)
	return CeroSecModules.isManyDoors(object)
end

-- open, closed, or locked -- three words and not four, because locked implies
-- closed and a survivor reading "locked" has been told both things. `locks` is
-- whether this door is one the lock means anything on (doorLocks, above): an
-- interior door with a key in it still opens from either side, so it reads
-- "closed" and opens.
--
-- IsOpen() is the one name both classes answer to (IsoDoor's forwards to its
-- isOpen(), IsoThumpable's reads its open field).
local function doorState(object, locks)
	if object:IsOpen() then return "open" end
	if locks and object:isLockedByKey() then return "locked" end
	return "closed"
end

-- The hardware, when the sandbox option asks for any (CeroSecModules.required).
-- A table of four booleans, empty when nothing is fitted, and nil -- meaning "do
-- not ask" -- when the option is off, which is the whole of how the old world is
-- kept: every branch below reads `fitted == nil` as "yes, of course".
local function fittedOn(object)
	if not CeroSecModules.required() then return nil end
	return CeroSecModules.installedOn(object)
end

local function has(fitted, id)
	return fitted == nil or fitted[id] == true
end

function CeroSecDevices.classify(object)
	if object == nil then return nil end

	local fitted = fittedOn(object)

	if instanceof(object, "IsoLightSwitch") then
		-- No relay, no light. Not a light switch that refuses: a light switch the
		-- machine has never heard of, which is what an unwired one is.
		if not has(fitted, "relay") then return nil end
		return { {
			kind = "light", side = "",
			desc = roomName(object:getSquare()) or "exterior",
			state = object:isActivated() and "on" or "off",
		} }
	end

	if instanceof(object, "IsoDoor") then
		local side = object:getNorth() and "N" or "W"
		local desc = doorDesc(object)
		local locks = doorLocks(object)
		local out = {}
		-- The operator is what MOVES a door and the contact is what sees it, so a
		-- door with only a contact on it is the same doorN with the same words
		-- and no way to carry them out (`ro`): it reads open, closed or locked,
		-- and every write to it is "operation not supported".
		local moves, sees = has(fitted, "operator"), has(fitted, "contact")
		if (moves or sees) and not isManyDoors(object) then
			out[#out + 1] = { kind = "door", side = side, desc = desc,
				locks = locks, state = doorState(object, locks), ro = not moves }
		end
		if locks and has(fitted, "strike") then
			out[#out + 1] = { kind = "lock", side = side, desc = desc,
				state = object:isLockedByKey() and "locked" or "unlocked" }
		end
		return out
	end

	if instanceof(object, "IsoWindow") then
		-- A contact and nothing else, ever: the only call in the game that moves a
		-- sash is IsoWindow.ToggleWindow(IsoGameCharacter) and it wants a survivor
		-- standing at it (docs/notes/modules-proofs.md, 4). So a wired window is a
		-- window the machine can look at, and the lock a machine used to be able
		-- to throw from across the building is one more thing that needed a hand.
		if not has(fitted, "contact") then return nil end
		return { {
			kind = "win",
			side = object:getNorth() and "N" or "W",
			desc = roomName(object:getSquare()) or "exterior",
			state = windowState(object),
			ro = fitted ~= nil,
		} }
	end

	-- Player-built. A base has no building and no rooms, so there is no room id
	-- to name it with and "built" is the truth about it. Only doors: a
	-- player-built window frame has no lock this rung.
	if instanceof(object, "IsoThumpable") and object:isDoor() then
		local side = object:getNorth() and "N" or "W"
		local out = {}
		local moves, sees = has(fitted, "operator"), has(fitted, "contact")
		if (moves or sees) and not isManyDoors(object) then
			out[#out + 1] = { kind = "door", side = side, desc = "built",
				locks = true, state = doorState(object, true), ro = not moves }
		end
		if has(fitted, "strike") then
			out[#out + 1] = { kind = "lock", side = side, desc = "built",
				state = thumpState(object) }
		end
		return out
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

-- The sensors lying on one square. Not classify's business: a dropped item is not
-- on the square's object list at all -- it is an IsoWorldInventoryObject on
-- getWorldObjects() -- so it is walked here, beside the other list and not inside
-- it. Everything about what makes one a sensor is in SCeroSecSensors.lua.
local function scanWorldItems(square, found, seen, x, y, z)
	local sensors = CeroSecSensors.onSquare(square)
	for i = 1, #sensors do
		local sensor = sensors[i]
		local entry = {
			kind = "sensor", side = "",
			-- A dropped head is the player's own doing wherever it lies, so the
			-- room names it where there is one and "built" does where there is
			-- not -- the same word a player-built door wears.
			desc = roomName(square) or "built",
			x = x, y = y, z = z, object = sensor.object,
			range = sensor.range,
			-- Which of the heads on this tile it is. Carried because the sampling
			-- book is keyed by it too, and both have to mean the same thing.
			n = i - 1,
		}
		local base = "sensor:" .. x .. ":" .. y .. ":" .. z .. ":"
		local n = 0
		while seen[base .. ":" .. n] do n = n + 1 end
		entry.key = base .. ":" .. n
		seen[entry.key] = true
		found[#found + 1] = entry
	end
end

local function scanSquare(square, found, seen)
	if square == nil then return end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	scanWorldItems(square, found, seen, x, y, z)
	local objects = square:getObjects()
	if objects == nil then return end
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		-- A list, because one object can be two devices: an exterior door is
		-- what opens AND what locks.
		local entries = CeroSecDevices.classify(object) or {}
		for k = 1, #entries do
			local entry = entries[k]
			entry.x, entry.y, entry.z = x, y, z
			entry.object = object
			-- Where it is, as a string, and that is the key its number hangs
			-- on. Two devices of one kind facing the same way on one square are
			-- told apart by an ordinal -- the object index would have done it
			-- too, and it is not stable across a reload. The kind is in the key,
			-- so door3 and lock1 on the same door hang on two keys and neither
			-- number moves when the other kind's numbering changes.
			local base = entry.kind .. ":" .. x .. ":" .. y .. ":" .. z .. ":" .. entry.side
			local n = 0
			while seen[base .. ":" .. n] do n = n + 1 end
			entry.key = base .. ":" .. n
			seen[entry.key] = true
			found[#found + 1] = entry
		end
	end
end

-- The machine's TNC, added to whatever the walk found. It is not discovered by
-- the walk and must not be: the radio's reach is its OWN -- the machine's room,
-- or a tile around it in a base -- and it is narrower than either branch below,
-- because a TNC is a box with a foot of cable to the set and not a thing that
-- works across a building. The rule and every game call behind it are in
-- SCeroSecRadio.lua.
--
-- One entry at the most, because a machine has one serial port. A radio already
-- found at that key -- which cannot happen, radios not being on the walk -- is
-- left alone, so the belt is the same one scanSquare wears.
local function withTnc(found, seen, x, y, z)
	local entry = CeroSecRadio.entryAt(x, y, z)
	if entry == nil then return found end
	if seen[entry.key] then return found end
	seen[entry.key] = true
	found[#found + 1] = entry
	return found
end

-- Every device the machine at x, y, z can reach right now, unnumbered.
function CeroSecDevices.find(x, y, z)
	local found, seen = {}, {}
	if getCell == nil then return found end
	local cell = getCell()
	if cell == nil then return found end

	local square = cell:getGridSquare(x, y, z)
	-- No square at all is a chunk the streamer has not brought in, and a machine
	-- that is not in the world reaches nothing: no /dev, and nothing for the
	-- sensor scan to sample (CeroSecSensors.scan). The same rule and the same
	-- guard the radio wears one layer down (CeroSecRadio.tncAt), and it is here
	-- rather than inside the two branches below because the no-building branch
	-- would otherwise walk four hundred squares that cannot be there -- once a
	-- minute, for every machine in the county the player has walked away from.
	if square == nil then return found end

	local building = square:getBuilding()

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
		return withTnc(found, seen, x, y, z)
	end

	-- No building: a square of ten tiles around the machine, on its own floor.
	-- A square the game has not loaded is simply nil and is skipped.
	local r = CeroSecDevices.RADIUS
	for dx = -r, r do
		for dy = -r, r do
			scanSquare(cell:getGridSquare(x + dx, y + dy, z), found, seen)
		end
	end
	return withTnc(found, seen, x, y, z)
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
				-- The mode a kind is born at, which is not the same for every kind:
				-- a sensor cannot be written to and wears 440 for saying so
				-- (CeroSecOS.DEV_MODES) -- and neither can a device with nothing
				-- behind it to write with, which is what `ro` is.
				record = { id = entry.kind .. tostring(n), kind = entry.kind, n = n,
					ro = entry.ro == true,
					mode = CeroSecOS.devModeFor(entry.kind, entry.ro) }
				map[entry.key] = record
				entries = entries + 1
			else
				record = nil
			end
		end
		if record ~= nil then
			-- The hardware behind a device can change under it: somebody fits an
			-- operator to a door that had only a contact on it, or takes one off.
			-- The NUMBER does not move for that -- it hangs on where the device is
			-- and which kind it is, and neither of those moved -- but the mode goes
			-- back to what a device of that shape is born at. A chmod does not
			-- survive the hardware, and must not: the other way round is a door
			-- with an operator on it that nobody may write to, because it was
			-- read-only the first time it was seen.
			--
			-- Both sides are read as booleans, so a record written before this rung
			-- -- which carries no `ro` at all -- is a read-write one and not a
			-- changed one, and no chmod is thrown away by a reload.
			if (record.ro == true) ~= (entry.ro == true) then
				record.ro = entry.ro == true
				record.mode = CeroSecOS.devModeFor(entry.kind, entry.ro)
			end
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
	local found = CeroSecDevices.find(luaObject.x, luaObject.y, luaObject.z)

	-- A sensor's state is not read off the object: there is nothing on a dropped
	-- item to read. It is what the sampling book says the contact is doing right
	-- now, and asking for it is also what puts a head just dropped on the floor
	-- into that book (see the head of SCeroSecSensors.lua).
	local now = getTimestampMs()
	CeroSecSensors.registerFound(found, now)

	local live = CeroSecDevices.number(state, found)
	for i = 1, #live do
		local entry = live[i]
		if entry.kind == "sensor" then
			entry.state = CeroSecSensors.stateAt(entry.x, entry.y, entry.z, entry.n, now)
		end
	end

	local byId, seen = {}, {}
	local list = {}
	for i = 1, #live do
		local entry = live[i]
		byId[entry.id] = entry
		seen[entry.id] = true
		list[#list + 1] = {
			id = entry.id, kind = entry.kind, desc = entry.desc,
			side = entry.side, state = entry.state,
			-- Whether anything is wired behind it. The engine mounts a node that
			-- says so and refuses every write to it in its own name.
			ro = entry.ro,
			-- Where it is, from where the machine is standing. Worked out here
			-- and not by the engine: the engine has no idea there are tiles.
			pos = CeroSecDevices.offset(entry.x - luaObject.x, entry.y - luaObject.y,
				entry.z - luaObject.z),
			mode = entry.mode or CeroSecOS.devModeFor(entry.kind, entry.ro),
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
				id = record.id, kind = record.kind, dead = true, ro = record.ro,
				mode = record.mode or CeroSecOS.devModeFor(record.kind, record.ro),
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

-- Is the doorway itself in the way? The game's own test and nothing of ours:
-- IsoDoor.isObstructed() -> the static isDoorObstructed(IsoObject), which
-- answers true when the door's square is isSolid() or isSolidTrans(), when it
-- has an IsoObjectType.tree on it, or when a vehicle in the chunk
-- isIntersectingSquareWithShadow of it. IsoThumpable has the same method,
-- forwarding to the same static.
--
-- It is exactly the test couldBeOpen makes at offset 108 before it will let a
-- survivor through, so a door the machine refuses is a door nobody could open by
-- hand either -- which is the whole rule here. A survivor STANDING in the
-- doorway is not one of these: vanilla lets a door swing through him
-- (ISOpenCloseDoor:complete calls ToggleDoor and checks nothing first), so the
-- machine does too. A refusal the game does not make is a refusal we would have
-- invented.
local function blocked(object)
	return object:isObstructed()
end

-- The world action, per kind. ok, reason, state.
local function act(entry, value)
	local object = entry.object

	-- Nothing is ever written to a sensor: the engine has no word for the kind
	-- (CeroSecOS.DEV_VALUES.sensor is empty) so a write is refused a layer up and
	-- never arrives here. This is the belt: a device that reached the world with
	-- no action for it must refuse in its own name and not fall through to the
	-- lock branch below, which would ask a dropped pipe bomb about its padlock.
	if entry.kind == "sensor" then return false, "invalid value" end

	-- And the radio, the same belt for the same reason: its vocabulary is empty
	-- too (the knob is the survivor's -- proof 7 in SCeroSecRadio.lua), so a write
	-- is refused a layer up and never arrives. If one ever did, it refuses in its
	-- own name rather than falling through to the lock branch below and asking an
	-- aerial about its padlock.
	if entry.kind == CeroSecRadio.KIND then return false, "invalid value" end

	-- And the third belt, for the devices this rung made: a door with a magnetic
	-- contact on it and no operator, or a window, which has no actuator in the
	-- game at all. The engine refuses these a layer up -- by the mode, and then by
	-- the node's own `ro` -- so nothing should arrive here. If one ever does, it
	-- says the same thing the engine says rather than quietly working the door
	-- with hardware nobody fitted.
	if entry.ro then return false, "operation not supported" end

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

	if entry.kind == "door" then
		local want = value == "open"
		-- Barricaded first, and by us: ToggleDoorSilent's first two
		-- instructions are isBarricaded and return, so a machine that did not
		-- check would swallow the order and report the state it already had.
		if object:isBarricaded() then return false, "barricaded" end
		-- The computer is not a key. A locked door is only locked at all when
		-- the lock means something on it (entry.locks), and the way past it is
		-- `unlock` on the lock device beside it.
		if want and entry.locks and object:isLockedByKey() then
			return false, "locked"
		end
		if blocked(object) then return false, "blocked" end
		-- Silent TOGGLES, so a door already where it is asked to be is left
		-- alone and nothing is broadcast: two `dev door0 open` in a row are one
		-- open door, not an open one and a shut one.
		if object:IsOpen() ~= want then
			object:ToggleDoorSilent()
			-- ToggleDoorSilent syncs nothing. syncIsoObject's server branch
			-- walks GameServer.udpEngine.connections, and both classes'
			-- syncIsoObjectSend writes the open flag.
			object:syncIsoObject(false, 0, nil, nil)
		end
		return true, nil, doorState(object, entry.locks)
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

--
-- The blink
--

-- Is the object we found still where we found it? Named apart from `alive`
-- above because a blink outlives the command that started it: the square is
-- looked at again on every tick, and a light carried away mid-blink is a light
-- the sweep drops rather than one it keeps calling setActive on.
local function stillThere(blink)
	local object = blink.object
	if object == nil then return false end
	local square = object:getSquare()
	if square == nil then return false end
	return square:getX() == blink.x and square:getY() == blink.y
		and square:getZ() == blink.z
end

local function throw(blink, on)
	if not stillThere(blink) then return false end
	blink.object:setActive(on)
	return true
end

-- Put the switch back where it was found. A blink that ends is a blink that
-- leaves nothing behind: a survivor who asked which light this was does not
-- want the room's lighting changed for having asked.
local function restore(blink)
	throw(blink, blink.was)
end

-- Drop a light's blink without restoring it. What a WRITE does: somebody who
-- has just typed `dev light0 off` means it, and a blink that ended a second
-- later by putting the light back on would be the machine arguing.
function CeroSecDevices.dropBlink(id)
	local kept = {}
	local blinks = CeroSecDevices.blinks
	for i = 1, #blinks do
		if blinks[i].id ~= id then kept[#kept + 1] = blinks[i] end
	end
	CeroSecDevices.blinks = kept
end

-- One tick of every blink there is. Nothing at all when there are none, which
-- is every tick of every game that is not answering `dev find` right now.
function CeroSecDevices.tick()
	local blinks = CeroSecDevices.blinks
	if #blinks == 0 then return end
	local now = getTimestampMs()

	local kept = {}
	for i = 1, #blinks do
		local blink = blinks[i]
		if now >= blink.endMs or not stillThere(blink) then
			restore(blink)
		else
			if now >= blink.nextMs then
				-- now + BLINK_MS and not nextMs + BLINK_MS: a server that was
				-- busy for two seconds owes nobody four catch-up flips.
				blink.nextMs = now + CeroSecDevices.BLINK_MS
				blink.on = not blink.on
				throw(blink, blink.on)
			end
			kept[#kept + 1] = blink
		end
	end
	CeroSecDevices.blinks = kept
end

-- Start one, or push the end of the one already running out. ok, reason.
local function blink(entry, seconds)
	local object = entry.object
	-- The switch's own rule, the same one a write asks (act, above): a light
	-- that cannot be thrown cannot be blinked either, and says the same thing
	-- about it.
	if not object:canSwitchLight() then return false, "no power" end

	local now = getTimestampMs()
	local endMs = now + seconds * 1000
	local blinks = CeroSecDevices.blinks
	for i = 1, #blinks do
		if blinks[i].id == entry.id then
			blinks[i].endMs = endMs
			return true
		end
	end

	blinks[#blinks + 1] = {
		id = entry.id, object = object,
		x = entry.x, y = entry.y, z = entry.z,
		-- What to put back, read now and not assumed from the state string.
		was = object:isActivated(),
		on = object:isActivated(),
		nextMs = now, endMs = endMs,
	}
	return true
end

-- The class the client is to look for on that square. The server already knows
-- which it is -- it classified the object to make a device of it -- so the
-- client is told rather than left to guess between a map door and a built one.
local function classOf(entry)
	-- A dropped sensor is not on the square's object list at all, so the client
	-- is told to look at the OTHER list -- and the thing that tells one head from
	-- another there is the item's full type and not a sprite name (a world item is
	-- drawn from a model). See CeroSecTerminal:objectAt.
	if entry.kind == "sensor" then return "IsoWorldInventoryObject" end
	if entry.kind == "win" then return "IsoWindow" end
	-- A radio is a fixture with a sprite like a light switch, so the outline finds
	-- it the ordinary way: `dev find radio0` is how a survivor with two sets in the
	-- room learns which one his machine is wired to.
	if entry.kind == CeroSecRadio.KIND then return "IsoRadio" end
	if instanceof(entry.object, "IsoDoor") then return "IsoDoor" end
	return "IsoThumpable"
end

-- The env.devices table for one machine. Built once per command: the discovery
-- is the expensive half and nothing may ask the world twice inside one line and
-- get two answers.
--
-- system and playerObj are the road back to ONE pair of eyes, and they are
-- optional: a call without them is a machine whose doors cannot be highlighted
-- (the light still blinks, being a thing the world does and not a thing a
-- screen does). They are handed down from the command being run, because a
-- highlight belongs to whoever typed the line and to nobody else standing at
-- the same computer.
function CeroSecDevices.envFor(luaObject, state, system, playerObj, token)
	local list, byId, map = build(luaObject, state)

	return {
		list = function()
			return list
		end,

		write = function(id, value)
			local entry = byId[id]
			if entry == nil or not alive(entry) then return false, "no such device" end
			-- A write ends any blink that light was in the middle of, and does
			-- NOT put the old state back: the word just typed is the newer of
			-- the two intentions.
			CeroSecDevices.dropBlink(id)
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

		-- Point at one for `seconds`. A light blinks where everybody can see it;
		-- a door or a window is outlined on the requesting player's screen and
		-- on no other, which is what the int first argument of vanilla's
		-- setHighlighted is for (see the head of this file).
		find = function(id, seconds)
			local entry = byId[id]
			if entry == nil or not alive(entry) then return false, "no such device" end

			if entry.kind == "light" then
				local ok, reason = blink(entry, seconds)
				if not ok then return false, reason end
				return true, nil, "blinking"
			end

			if system == nil or playerObj == nil then return false, "no such device" end
			-- The device's own square, not the computer's: what travels with a
			-- highlight is where to look, and the token of the window that
			-- asked, which is the only thing a terminal believes.
			-- A fixture is found again on the far side by what it LOOKS like and a
			-- dropped item by what it IS: getSpriteName on a world item answers a
			-- model's name or nothing at all, so a sensor travels on the item's
			-- full type instead and the client uses whichever its class calls for.
			-- Only one of the two is ever asked of an object, because getItem is a
			-- question a light switch has no answer to.
			local sprite, item = "", ""
			if entry.kind == "sensor" then
				item = CeroSecSensors.typeOf(entry.object)
			else
				sprite = entry.object:getSpriteName()
			end
			system:reply(playerObj, "highlight", {
				x = entry.x, y = entry.y, z = entry.z, token = token,
				class = classOf(entry), sprite = sprite, item = item,
				seconds = seconds,
			})
			return true, nil, "highlighted"
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

-- The blink clock. Vanilla's own way of getting under a minute on a server
-- (forageServer.lua:502, and the gate inside CeroSecDevices.tick).
Events.OnTick.Add(function()
	CeroSecDevices.tick()
end)

-- The one-minute sweep. Nothing on a screen changes -- a line already printed
-- is a line already printed -- but the book of numbers is brought up to date,
-- so a device that appeared since the machine was last used already has its
-- number by the time somebody types `ls /dev`.
function CeroSecDevices.refresh(luaObject, state)
	if state == nil then return end
	CeroSecDevices.number(state, CeroSecDevices.find(luaObject.x, luaObject.y, luaObject.z))
end
