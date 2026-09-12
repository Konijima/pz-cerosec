if isClient() then return end

require "CeroSec/CeroSecDefs"

--
-- Motion sensors.
--
-- A survivor drops a motion sensor on the floor of a room the computer can
-- reach, and the computer grows a /dev/sensorN that reads `motion` or `clear`.
-- Nothing is crafted, nothing is placed by us and nothing of ours is added to
-- the world: the device IS the item lying there, and picking it up takes the
-- device away.
--
-- Which item
--
-- One, and it is the one the game named after the job: Base.MotionSensor, an
-- Electronics-category module with a WorldStaticModel so it can be dropped and
-- set down (media/scripts/generated/items/normal.txt:4539-4548). Its reach is
-- CeroSec.SENSOR_RANGE, and the citation for that number is in CeroSecDefs.lua
-- beside it: the module plus two ElectronicsScrap is what the game itself calls a
-- V1 sensor, and every V1 in the game is SensorRange = 3.
--
-- And the fifteen *SensorV1/V2/V3 items are NOT devices, deliberately. They are
-- TRAP HEADS -- a pipe bomb, an aerosol bomb, a flame trap, a smoke bomb, a noise
-- trap, each with a motion sensor taped to it -- and the whole point of one is
-- that it goes off when a body comes near. A thing that explodes when it detects
-- movement is a mine, not a sensor, and a security system a survivor wires to
-- five pipe bombs is a security system that kills him. They are excluded FIRST,
-- before the item is even named, so the refusal cannot be argued around.
--
-- What is dropped and what is placed are two different objects, which is worth
-- writing down because it is the difference the exclusion is about. A dropped
-- item is an inert IsoWorldInventoryObject on getWorldObjects(); a trap that has
-- been PLACED is an armed IsoTrap on getObjects(), made through
-- media/lua/server/Traps/BuildingObjects/TrapBO.lua and IsoTrap.new(item, cell,
-- square). So a dropped pipe bomb is not live -- and it is one right-click from
-- being, which is exactly why the machine will not call it a sensor.
--
-- The reading path, proved:
--   IsoGridSquare.getWorldObjects() -> ArrayList<IsoWorldInventoryObject>
--     (javap; and vanilla's own Lua reads it exactly so --
--      media/lua/server/BuildingObjects/ISBuildUtil.lua:315,
--      media/lua/client/ISUI/ISWorldObjectContextMenu.lua:2957)
--   IsoWorldInventoryObject.getItem() -> InventoryItem   (javap)
--   InventoryItem.getFullType() -> String                (javap)
--   HandWeapon.getSensorRange() -> int                   (javap), which is the
--     SCRIPT's number on every instance: zombie.scripting.objects.Item
--     .InstanceItem(String, boolean) ends on `getfield sensorRange /
--     invokevirtual HandWeapon.setSensorRange` (javap -c, offsets 2016-2019).
--     Read here only to REFUSE a trap head, and it is the honest test for one:
--     sensorRange lives on HandWeapon and on no other InventoryItem, so an item
--     that answers a positive one is a trap with a sensor on it.
--   instanceof(item, "HandWeapon") is how the class is asked, which is the
--     idiom vanilla uses on inventory items
--     (media/lua/server/BuildingObjects/ISBuildUtil.lua:111 --
--      instanceof(item, "InventoryContainer")).
--
-- What the field of view is
--
-- The game's own sensor is in IsoTrap.updateVictimsInSensorRange, and its
-- bytecode is the whole specification (javap -c zombie.iso.objects.IsoTrap):
--
--   40: SENSOR_TIMER.Check()            -- static { new OnceEvery(1.0f) }:
--                                          ONCE A SECOND, and that is why the
--                                          sample below is once a second too
--  117: mo.getZi() == square.getZ()     -- one floor, never through a ceiling
--  135: IsoUtils.DistanceToSquared(mo.getX(), mo.getY(),
--                                  getX() + 0.5f, getY() + 0.5f)
--  162: <= getSensorRange() * getSensorRange()
--                                       -- EUCLIDEAN, squared, measured from the
--                                          CENTRE of the sensor's own tile
--  103: Type.tryCastTo(mo, IsoGameCharacter) and isInvisible() -> skip
--  219: LosUtil.lineClear(...) -- Blocked or ClearThroughClosedDoor -> skip
--
-- Five of those six are mirrored here exactly, arithmetic included: the same
-- squared comparison, the same 0.5 offsets, the same one-floor rule, the same
-- invisible skip. A BaseVehicle extends IsoMovingObject and the cast to
-- IsoGameCharacter fails on it, so the game's own sensor is NOT skipping cars --
-- and neither are we. A car is warm.
--
-- The sixth is LosUtil.lineClear, and it is the one thing here that is not the
-- game's call: no vanilla Lua anywhere touches LosUtil, so whether its nested
-- TestResults enum can be read from Lua at all is unproven, and a trace per body
-- per second per sensor is the dearest thing this file could do. What stands in
-- its place is the ROOM, which is the game's own partition of the inside of a
-- building by its walls: the field is the sensor's own room, clipped to the
-- range. A sensor with no room under it -- a base, a field -- gets the range and
-- nothing else, because there are no walls there to be seen through.
--
-- So the honest statement of the field, and it is the one the manual prints:
--   in a room, the part of THAT room within range; outside one, the range.
--
-- What movement is
--
-- The game's sensor is a proximity fuse: anybody in range at all sets it off,
-- standing still included. A PIR is not that. It sees a CHANGE in the warmth in
-- front of it and it sees nothing at all in a still room, which is why a real one
-- is sold on "pet immunity" and why a burglar who freezes is a burglar it loses.
--
-- So the sample is a signature and not a count: every body in the field,
-- quantized to STEP of a tile, sorted, joined. Movement is the signature
-- differing from the one before it -- which covers all three of the things that
-- can happen at once, without tracking anybody's identity, because a PIR does not
-- have identities either:
--
--   somebody moved   -> his entry changed
--   somebody came in -> there is an entry that was not there
--   somebody left    -> there is an entry missing
--
-- Quantized, because a body that has not moved must read as not moved. STEP is
-- the sensor's resolution and it is ours: a tenth of a tile, about twenty
-- centimetres of Knox County, below which a shuffle is not a movement.
--
-- The first sample after a sensor is discovered has nothing to compare against,
-- so it sets the baseline and reports nothing. That is a warm-up, it lasts one
-- second, and every PIR ever fitted has had one.
--
-- Whose state it is
--
-- The sensor's, not the machine's. One head on the floor has one contact in it,
-- so two computers that can both reach it read the same word -- and it is
-- sampled once however many machines are watching it. The book below is keyed by
-- where the sensor is and by nothing else.
--
-- It is never saved. A contact is five seconds long and a reload is the end of
-- it; a machine coming back up reads `clear` and warms up again, which is what a
-- sensor that has just been powered says.
--
-- When it runs
--
-- Only for machines that are ON, only on their own loaded chunks, and the
-- discovery -- the expensive half -- runs at SCAN_MS and not at SAMPLE_MS. In
-- between, a pass looks at the squares it was told about and nothing else. A
-- sensor no live machine has asked about for two scans is forgotten.
--

CeroSecSensors = CeroSecSensors or {}

-- Once a second, which is the game's own sensor clock: IsoTrap's
-- SENSOR_TIMER is `new OnceEvery(1.0f)` and updateVictimsInSensorRange returns
-- early until it Checks true. Gated on getTimestampMs off Events.OnTick, the way
-- the device blink is (see the head of SCeroSecDevices.lua).
CeroSecSensors.SAMPLE_MS = 1000

-- How often the fields are worked out again: which machines are on, which
-- sensors they can reach, and which squares each sensor watches. A minute, the
-- same clock the book of device numbers catches up on, because it is the same
-- question asked of the same world.
CeroSecSensors.SCAN_MS = 60000

-- The sensor's resolution, in tenths of a tile. A body whose position rounds to
-- the same tenth it rounded to a second ago has not moved.
CeroSecSensors.STEP = 10

-- How many squares one sensor's field may hold. Every head has the same reach, so
-- this is CeroSec.SENSOR_RANGE's own bounding box -- 7x7 at a range of three --
-- and it is written down rather than worked out afresh because it is a CEILING:
-- the field is capped whatever the range is, so a reach somebody widens cannot
-- make one pass cost four thousand squares without this number moving too.
CeroSecSensors.FIELD_MAX = 49

-- How many sensors are sampled at all. Six machines with eight sensors each is
-- what the hostile bench drives; a hundred is well past anything a building
-- holds and is the ceiling that makes a pass's cost a number instead of a hope.
CeroSecSensors.SENSOR_MAX = 100

-- The sensors being sampled: key -> record. Never saved (see above).
--
--   record = { x, y, z,          where the head is
--              range,            how far it sees (CeroSec.SENSOR_RANGE)
--              field = { {x,y,z}, ... },   the squares it watches
--              sig,              the signature of the last sample
--              holdUntil,        ms until the contact opens again
--              refMs }           when a live machine last asked about it
CeroSecSensors.book = {}

CeroSecSensors.lastSampleMs = 0
CeroSecSensors.lastScanMs = 0

-- Where a sensor hangs in the book. The same shape SCeroSecDevices keys its
-- numbering on, minus the kind and the side, which a sensor has neither of that
-- matters: a head is where it is.
-- n is the ordinal among the sensors on that square, so two heads lying on one
-- tile are two records and not one. It is the order the game lists the square's
-- world objects in, which is the same thing the device numbering already leans on
-- for two devices of one kind on one square (see CeroSecDevices.scanSquare).
function CeroSecSensors.keyAt(x, y, z, n)
	return x .. ":" .. y .. ":" .. z .. ":" .. (n or 0)
end

--
-- The item
--

-- The one item a machine will call a sensor. Written down because it has to be:
-- the module carries no field that tells it apart from a fuse or a battery, so
-- what identifies it is its name, and this is the one place that name appears.
CeroSecSensors.ITEM = "Base.MotionSensor"

-- Is this item a trap head -- a bomb with a motion sensor taped to it? The test
-- is the game's own field and not a list of the fifteen names: sensorRange lives
-- on HandWeapon and on no other InventoryItem, so a positive one is a weapon that
-- senses, which is a mine.
--
-- Asked BEFORE the name, so that nothing which explodes can ever become a device
-- -- not a vanilla trap, not a modded one, and not one somebody named
-- Base.MotionSensor.
local function isTrapHead(item)
	if not instanceof(item, "HandWeapon") then return false end
	local range = item:getSensorRange()
	return type(range) == "number" and range > 0
end

-- How far one dropped object sees, or nil when it is not a sensor at all.
function CeroSecSensors.rangeOf(object)
	if object == nil then return nil end
	local item = object:getItem()
	if item == nil then return nil end
	if isTrapHead(item) then return nil end
	if item:getFullType() ~= CeroSecSensors.ITEM then return nil end
	return CeroSec.SENSOR_RANGE
end

-- Every sensor lying on one square, in the order the game lists them. A list and
-- not one, because two heads on one tile are two devices.
function CeroSecSensors.onSquare(square)
	local out = {}
	if square == nil then return out end
	local objects = square:getWorldObjects()
	if objects == nil then return out end
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local range = CeroSecSensors.rangeOf(object)
		if range ~= nil then
			out[#out + 1] = { object = object, range = range }
		end
	end
	return out
end

-- The full type of the item a sensor is, which is what travels to a client that
-- has to find the same object again. Always CeroSecSensors.ITEM today and asked of
-- the item anyway, because what the client must look for is what is THERE.
function CeroSecSensors.typeOf(object)
	if object == nil then return "" end
	local item = object:getItem()
	if item == nil then return "" end
	local full = item:getFullType()
	if type(full) ~= "string" then return "" end
	return full
end

--
-- The field
--

-- The squares one sensor watches: its own tile and everything within `range` of
-- it, on its own floor, clipped to its room where it has one.
--
-- The clip is done by MEMBERSHIP of the room's own square list and never by
-- comparing two rooms for identity: room:getSquares() is the call the discovery
-- already makes (SCeroSecDevices.find), a square's x, y and z are what it is,
-- and a set of those three needs nothing of Java to be asked twice.
--
-- What comes back is COORDINATES and not square handles. A pass a minute later
-- looks them up again: a handle to a square whose chunk has gone is exactly the
-- kind of thing that answers questions and means nothing.
function CeroSecSensors.fieldOf(square, range)
	local field = {}
	if square == nil then return field end
	local sx, sy, sz = square:getX(), square:getY(), square:getZ()

	local inRoom = nil
	local room = square:getRoom()
	if room ~= nil then
		local squares = room:getSquares()
		if squares ~= nil then
			inRoom = {}
			for i = 0, squares:size() - 1 do
				local sq = squares:get(i)
				if sq ~= nil then
					inRoom[sq:getX() .. ":" .. sq:getY() .. ":" .. sq:getZ()] = true
				end
			end
		end
	end

	-- The bounding box is how the squares are ENUMERATED and never what decides
	-- whether a body is seen: that is the real distance, taken against the body's
	-- own position when the sample happens, exactly as the game takes it.
	for dx = -range, range do
		for dy = -range, range do
			local x, y = sx + dx, sy + dy
			if inRoom == nil or inRoom[x .. ":" .. y .. ":" .. sz] then
				if #field >= CeroSecSensors.FIELD_MAX then return field end
				field[#field + 1] = { x, y, sz }
			end
		end
	end
	return field
end

--
-- The sample
--

-- Is this body one the sensor may see? The game's own two tests, in its own
-- order: an invisible CHARACTER is skipped, anything that is not a character --
-- a car -- is not, and then the squared euclidean distance from the centre of the
-- sensor's tile against the range squared.
local function sees(record, mo)
	if instanceof(mo, "IsoGameCharacter") and mo:isInvisible() then return false end
	local dx = mo:getX() - (record.x + 0.5)
	local dy = mo:getY() - (record.y + 0.5)
	return dx * dx + dy * dy <= record.range * record.range
end

-- One reading of the infrared in front of one head, as a string. Sorted, because
-- the order the world lists bodies in is not the sensor's business and two
-- samples of one still room have to come out the same.
function CeroSecSensors.signature(record)
	if getCell == nil then return "" end
	local cell = getCell()
	if cell == nil then return "" end

	local step = CeroSecSensors.STEP
	local marks = {}
	local field = record.field
	for i = 1, #field do
		local at = field[i]
		local square = cell:getGridSquare(at[1], at[2], at[3])
		if square ~= nil then
			local bodies = square:getMovingObjects()
			if bodies ~= nil then
				for j = 0, bodies:size() - 1 do
					local mo = bodies:get(j)
					if mo ~= nil and sees(record, mo) then
						marks[#marks + 1] = math.floor(mo:getX() * step) .. ","
							.. math.floor(mo:getY() * step)
					end
				end
			end
		end
	end

	table.sort(marks)
	return table.concat(marks, " ")
end

-- One second of one sensor. The contact closes for SENSOR_HOLD_S whenever the
-- picture is not the picture it was, and the first reading of a new head sets the
-- baseline without closing anything -- the warm-up.
function CeroSecSensors.sampleOne(record, now)
	local sig = CeroSecSensors.signature(record)
	if record.sig ~= nil and sig ~= record.sig then
		record.holdUntil = now + CeroSec.SENSOR_HOLD_S * 1000
	end
	record.sig = sig
end

-- What a sensor reads, in the words /dev prints. A head nobody is sampling --
-- one whose machine went off between the discovery and the read -- has no record
-- and reads `clear`, which is the truth about a sensor with nothing behind it.
function CeroSecSensors.stateAt(x, y, z, n, now)
	local record = CeroSecSensors.book[CeroSecSensors.keyAt(x, y, z, n)]
	if record == nil then return "clear" end
	if record.holdUntil ~= nil and now < record.holdUntil then return "motion" end
	return "clear"
end

--
-- The passes
--

-- Put one head in the book, or keep the one already there alive. The field is
-- worked out once here and reused by every sample until the next scan.
function CeroSecSensors.register(square, n, range, now)
	local key = CeroSecSensors.keyAt(square:getX(), square:getY(), square:getZ(), n)
	local record = CeroSecSensors.book[key]
	if record == nil then
		local count = 0
		for _ in pairs(CeroSecSensors.book) do count = count + 1 end
		if count >= CeroSecSensors.SENSOR_MAX then return nil end
		record = { x = square:getX(), y = square:getY(), z = square:getZ() }
		CeroSecSensors.book[key] = record
	end
	-- The range and the field are re-read, not kept: a head picked up and a
	-- bigger one dropped on the same tile is a different sensor with the same
	-- number, and the field of a room somebody has knocked a wall out of has
	-- changed.
	record.range = range
	record.field = CeroSecSensors.fieldOf(square, range)
	record.refMs = now
	return record
end

-- Every sensor in one list of discovered devices, into the book. Called with
-- whatever CeroSecDevices.find just handed back, so the reach is the device
-- layer's own and a sensor no machine could make a device of is a sensor nobody
-- samples.
--
-- Called from two places, and that is on purpose. The scan below is the one that
-- keeps a machine's sensors sampled while nobody is standing at it; a command
-- typed at the glass registers through here as well (CeroSecDevices.build), so a
-- head dropped on the floor ten seconds ago is warm by the time the next `cat`
-- comes round rather than at the top of the next minute.
function CeroSecSensors.registerFound(found, now)
	for k = 1, #found do
		local entry = found[k]
		if entry.kind == "sensor" and entry.object ~= nil then
			local square = entry.object:getSquare()
			if square ~= nil then
				CeroSecSensors.register(square, entry.n or 0, entry.range or 0, now)
			end
		end
	end
end

-- The discovery: every machine that is on, every sensor it can reach.
--
-- The walk is the same one the power check and cron make
-- (SCeroSecSystem:checkPower), because it is the same list and a second walk
-- would only be a second chance to disagree with it. A machine that is OFF is
-- not walked at all, which is the whole of "a sensor is wired to a computer": no
-- machine on, no pass, no cost.
function CeroSecSensors.scan(system, now)
	if system ~= nil then
		for i = 1, system:getLuaObjectCount() do
			local luaObject = system:getLuaObjectByIndex(i)
			if luaObject ~= nil and luaObject.on then
				CeroSecSensors.registerFound(
					CeroSecDevices.find(luaObject.x, luaObject.y, luaObject.z), now)
			end
		end
	end

	-- And forget the heads nobody asked about. Two scans of grace, so a machine
	-- turned off and on again inside a minute keeps its sensors warm.
	for key, record in pairs(CeroSecSensors.book) do
		if now - (record.refMs or 0) > 2 * CeroSecSensors.SCAN_MS then
			CeroSecSensors.book[key] = nil
		end
	end
end

-- One second, every head in the book. Nothing at all when the book is empty,
-- which is every second of every game where no machine is on beside a sensor.
function CeroSecSensors.samplePass(now)
	for _, record in pairs(CeroSecSensors.book) do
		CeroSecSensors.sampleOne(record, now)
	end
end

-- The clock. One Events.OnTick handler for both cadences: the scan is a minute
-- and the sample is a second, and both are gated on getTimestampMs, which is
-- vanilla's own way of getting under a minute on a server (forageServer.lua:455-
-- 460, registered at :502).
function CeroSecSensors.tick(system)
	local now = getTimestampMs()

	if now - CeroSecSensors.lastScanMs >= CeroSecSensors.SCAN_MS then
		CeroSecSensors.lastScanMs = now
		CeroSecSensors.scan(system, now)
	end

	if now - CeroSecSensors.lastSampleMs >= CeroSecSensors.SAMPLE_MS then
		CeroSecSensors.lastSampleMs = now
		CeroSecSensors.samplePass(now)
	end
end

Events.OnTick.Add(function()
	CeroSecSensors.tick(SCeroSecSystem and SCeroSecSystem.instance or nil)
end)
