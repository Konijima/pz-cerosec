if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSRadio"

--
-- The radio, as the game has one.
--
-- The engine knows what a callsign is and what a TNC says; it has never heard of
-- an aerial. This file is the other half: which radio in the room is the
-- machine's TNC, what that radio's dial is set to, whether two stations can hear
-- each other, and the one line the whole county gets to read when they connect.
--
-- ==========================================================================
-- WHAT THE GAME'S RADIO MODEL IS. Proved before anything was designed, because
-- the design had to bend to it in three places and it is cheaper to write the
-- proof down than to rediscover it.
--
-- Everything below is either javap on
--   .../ProjectZomboid/projectzomboid/projectzomboid.jar   (42.20.4)
-- or the game's own Lua under
--   .../ProjectZomboid/projectzomboid/media/
-- decompiled-src is January's and was not used: it is older than the jar.
-- ==========================================================================
--
-- 1. A RADIO IN THE WORLD IS AN OBJECT ON A SQUARE.
--
--    zombie.iso.objects.IsoRadio extends zombie.iso.objects.IsoWaveSignal
--    extends zombie.iso.IsoObject implements zombie.radio.devices.WaveSignalDevice
--    (javap). IsoWaveSignal carries `protected DeviceData deviceData` and
--    answers getDeviceData() / setDeviceData(DeviceData).
--
--    So a radio is found the way a light switch is: walk the square's objects
--    and ask `instanceof(object, "IsoRadio")`. Vanilla's own Lua asks exactly
--    that of a world object (media/lua/client/ISUI/ISRadioAndTvMenu.lua:21,
--    client/TimedActions/ISGrabItemAction.lua:86).
--
-- 2. EVERYTHING WORTH KNOWING IS ON zombie.radio.devices.DeviceData (javap):
--
--      getChannel() / setChannel(int) / setChannelRaw(int)
--      getMinChannelRange() / getMaxChannelRange()
--      getTransmitRange() / setTransmitRange(int)
--      getIsTurnedOn() / setIsTurnedOn(boolean)
--      getPower() / setPower(float) / canBePoweredHere()
--      getIsBatteryPowered() / getHasBattery() / addBattery(DrainableComboItem)
--      getIsTwoWay() / getIsPortable() / getIsHighTier() / getIsTelevision()
--      getDeviceName() / getDeviceVolume() / isNoTransmit()
--
--    ON AND POWERED is asked the way the game's own radio UI asks it, and not
--    with a test of ours: ISRadioAction:isValidSetChannel() (and
--    :isValidMuteVolume() beside it) is
--
--      self.deviceData:getIsTurnedOn() and self.deviceData:getPower() > 0
--
--    (media/lua/client/RadioCom/ISRadioAction.lua:56-59, :85). getPower() is
--    what covers both kinds of supply -- canBePoweredHere() answers true for
--    anything battery-powered and otherwise asks the SQUARE
--    (hasGridPower / haveElectricity / getRoom, javap of canBePoweredHere) --
--    so a ham set on a dead grid and a walkie with a flat battery are both
--    getPower() == 0 and the machine says the same thing about them.
--
--    THE FREQUENCY IS KILOHERTZ. The radio UI prints
--      getChannel()/1000 .. " MHz"
--    and the tuneable span as getMinChannelRange()/1000 to
--    getMaxChannelRange()/1000
--    (media/lua/client/RadioCom/RadioWindowModules/RWMGeneral.lua:80-81). So
--    channel 144390 is 144.390 MHz, which is what CeroSecOS.radioFreqText
--    writes.
--
-- 3. WHICH RADIOS ARE TWO-WAY, and it is the item script that says so, not us.
--    Every radio item in media/scripts/generated/items/radio.txt with
--    `TwoWay = true` on it, all ten of them:
--
--      WalkieTalkie1..5, WalkieTalkieMakeShift, ManPackRadio  IsPortable = true
--      HamRadio1, HamRadio2, HamRadioMakeShift                IsPortable = false
--
--    and nothing else in the file is two-way -- a radio set and a television
--    receive and never transmit. That enumeration is why getIsPortable() is
--    enough to name the set: a two-way radio in this game is a walkie or it is a
--    ham set, with no third case.
--
--    HamRadio1 (:203-225) is the whole specification of a ham station:
--      TwoWay = true, IsPortable = false, UsesBattery = true,
--      MinChannel = 10000, MaxChannel = 500000, TransmitRange = 7500,
--      WorldObjectSprite = appliances_com_01_0
--    WalkieTalkie4 (:87-107) is a portable one: TransmitRange = 8000,
--    IsPortable = true, the same 10000..500000 span.
--
-- 4. THE HAM RADIO TILE. media/newtiledefinitions.tiles.txt, the four sprites
--    appliances_com_01_0 to _3 (one per facing), each carrying
--
--      IsoType    = IsoRadio
--      CustomItem = Base.HamRadio1
--      CustomName = Radio
--      GroupName  = Premium Technologies Ham
--      signal     = radio
--
--    So a ham radio that the MAP put in a building is already an IsoRadio with
--    device data on it. One a survivor CARRIES and puts down becomes the same
--    thing through the placement path: ISMoveableSpriteProps, isoType
--    "IsoRadio", does `obj = IsoRadio.new(getCell(), _square, getSprite(...))`
--    and then `obj:setDeviceData(_item:getDeviceData())` -- the item's own
--    channel, power and battery carried onto the world object
--    (media/lua/shared/Moveables/ISMoveableSpriteProps.lua:2129-2147). Either
--    way, one object on one square with one DeviceData, which is all this file
--    asks for.
--
-- 5. HOW A RADIO GETS ON THE AIR, and HOW RANGE IS APPLIED. This is the part
--    the design bent to.
--
--    zombie.radio.ZomboidRadio, reached from Lua as getZomboidRadio() -- which
--    vanilla's own SERVER Lua does (media/lua/server/radio/ISDynamicRadio.lua:32
--    and :145), so it is a safe call from where this mod runs.
--
--      SendTransmission(int x, int y, int channel, String line, String guid,
--                       String interactCodes, float r, float g, float b,
--                       int range, boolean isTelevision)
--
--    (javap). Its body: in GameMode.SinglePlayer it calls
--    DistributeTransmission with the same arguments; in GameMode.Server it calls
--    DistributeTransmission AND sends the line on to the clients. getGameMode()
--    is SinglePlayer when neither GameClient.client nor GameServer.server is
--    set. So one call covers a solo game and a server, which is why it is the
--    one used.
--
--    DistributeTransmission (javap -c) walks ZomboidRadio's own `devices` list
--    and for each device requires, in this order:
--
--      getDeviceData() ~= null
--      getDeviceData():getIsTurnedOn()
--      getDeviceData():getIsTelevision() == isTelevision
--      getDeviceData():getChannel() == channel
--      and the device is NOT the one on the source tile:
--        fastfloor(getX()) == x and fastfloor(getY()) == y  ->  skipped
--        (unless range == -1, which skips that test and every device hears it)
--
--    then, when range > 0:
--
--      distance = GetDistance(fastfloor(devX), fastfloor(devY), x, y)
--      line = doDeviceRangeDistortion(line, range, distance)
--
--    GetDistance is sqrt(dx^2 + dy^2) truncated to an int (javap -c), on X AND
--    Y ONLY -- there is no z in it. That is why this rung ignores floors: the
--    game's own radio does.
--
--    doDeviceRangeDistortion (javap -c) is NOT a cutoff. Below 0.9 * range the
--    line is untouched; past it, it is scrambleString'd by
--      100 * (distance - 0.9*range) / (range - 0.9*range)
--    percent, so at the range itself it is 100% scrambled and beyond it more
--    than that. A station out of range therefore hears NOISE and not silence,
--    which is what a radio does.
--
--    Finally the line is delivered: AddDeviceText(line, r, g, b, guid,
--    interactCodes, distance) on the device in a solo game, and on a server the
--    Lua event OnDeviceText(guid, interactCodes, x, y, z, line, device) -- which
--    is what media/lua/shared/RadioCom/ISRadioInteractions.lua:261 is registered
--    on and what puts the line in front of a player standing near the set. NOTE
--    the guard in front of the server branch: `interactCodes == null` returns
--    without delivering anything, so interactCodes must be a string. Vanilla's
--    own call passes null for guid and "" for interactCodes
--    (javap -c of zombie.radio.scripting.RadioChannel, offsets 114-138, which
--    also gives the only colour triple vanilla writes at a call site: 0.7, 0.5,
--    0.5, with range -1 and x,y of 0,0 for a broadcast station that is nowhere).
--
-- 6. WHY AN UNLOADED CHUNK IS A CALL THAT FAILS -- and this is the one place the
--    radio is WORSE than the telephone, honestly so.
--
--    IsoWaveSignal.addToWorld() calls ZomboidRadio.RegisterDevice(this) and
--    removeFromWorld() calls UnRegisterDevice(this) (javap -c). So the devices
--    list -- the only list a transmission is ever distributed over -- holds
--    exactly the radios whose chunk the streamer has in memory. A radio in a
--    town nobody is standing in is not in it, and its square is nil anyway
--    (SGlobalObject.getSquare, see the head of SCeroSecNet.lua).
--
--    A machine's DISK is held by the server whether its chunk is loaded or not,
--    which is why ruptime, ping, rlogin and cu all answer for a computer at the
--    other end of the county. A machine's RADIO is a tile, and a tile that is
--    not in memory does not exist. So a call to a station whose chunk is
--    unloaded gets the TNC's word for nobody answering, and that is the truth of
--    it rather than a rule we chose: there is no radio there to answer with.
--
-- 7. THE KNOB IS THE GAME'S. setChannel is called from exactly one place in the
--    game's Lua -- ISRadioAction:performSetChannel, guarded by
--    isValidSetChannel (ISRadioAction.lua:70-81) -- which is the timed action
--    behind the radio window's own frequency box. So tuning is something a
--    survivor does by walking to the set and turning it, and /dev/radio0 is
--    read-only: a machine that could retune the aerial it is talking through
--    would be a machine doing by software what the period did by hand.
--
-- ==========================================================================
--
-- WHAT IS BUILT ON TOP OF IT
--
-- The machine's TNC is a two-way radio it can reach: on its own square, or
-- anywhere in its own room when it stands in a building the map knows, or within
-- one tile when it stands in a base somebody built. One machine, one TNC, one
-- /dev/radio0 -- a TNC hangs off a serial port and a computer of 1993 has one
-- free -- so where two radios qualify the machine is wired to the first in map
-- order and the other is a radio in the room and nothing more.
--
-- A radio that is switched OFF or has no power is still the TNC and still
-- /dev/radio0: that is the whole use of the device, to be read before walking
-- over to the set.
--

CeroSecRadio = CeroSecRadio or {}

-- How far a machine in a player-built base may look for its set, in tiles, on
-- its own floor. One, which is a desk and the floor beside it: a TNC is a box
-- with a foot of cable to the radio and a survivor who put the set across the
-- room did not wire it to the computer.
--
-- A machine in a building the map knows looks at its ROOM instead, which is
-- larger and is right for the same reason: a room the map drew is one office and
-- the cable runs along the wall.
CeroSecRadio.REACH = 1

-- The kind, once, so the device layer and the link layer cannot spell it two
-- ways.
CeroSecRadio.KIND = "radio"

-- What the set is called in the description column: the two things a two-way
-- radio in this game can be, and the enumeration in the proof above (3) is why
-- getIsPortable() decides it.
CeroSecRadio.HAM = "ham"
CeroSecRadio.WALKIE = "walkie"

--
-- Reading one
--

-- The device data of an object, or nil for anything that is not a radio with
-- any. Every read below goes through here, so an object the game handed back
-- with no data on it is an object this file simply does not see.
local function dataOf(object)
	if object == nil then return nil end
	if not instanceof(object, "IsoRadio") then return nil end
	local data = object:getDeviceData()
	if data == nil then return nil end
	return data
end

-- One radio, as the four facts the rest of this file works on. nil for a set
-- that is not two-way: a receiver cannot be a TNC, because a TNC has to
-- TRANSMIT, and there is nothing to be done about a radio that only listens.
--
-- The whole of the game's API is asked here and nowhere else, so that a bench
-- with a fake radio on a fake square proves everything above this line.
function CeroSecRadio.read(object)
	local data = dataOf(object)
	if data == nil then return nil end
	if not data:getIsTwoWay() then return nil end
	local channel = data:getChannel()
	if type(channel) ~= "number" then return nil end
	local kind = CeroSecRadio.HAM
	if data:getIsPortable() then kind = CeroSecRadio.WALKIE end
	local range = data:getTransmitRange()
	if type(range) ~= "number" or range < 0 then range = 0 end
	return {
		channel = math.floor(channel),
		range = math.floor(range),
		-- Vanilla's own pair, in vanilla's own order (proof 2).
		on = data:getIsTurnedOn() and true or false,
		powered = (tonumber(data:getPower()) or 0) > 0,
		kind = kind,
	}
end

--
-- Finding it
--

-- The two-way radios on one square, in the order the square holds them.
local function onSquare(square, found)
	if square == nil then return end
	local objects = square:getObjects()
	if objects == nil then return end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local set = CeroSecRadio.read(object)
		if set ~= nil then
			set.object = object
			set.x, set.y, set.z = x, y, z
			found[#found + 1] = set
		end
	end
end

-- Map order, so that a room with two sets in it is wired to the same one every
-- session: x, then y, then z. Nothing else is needed -- two radios on one square
-- are told apart by the order the square holds them, which is the order they
-- were put there in, and that does not move either.
local function before(a, b)
	if a.x ~= b.x then return a.x < b.x end
	if a.y ~= b.y then return a.y < b.y end
	return a.z < b.z
end

-- The machine's TNC: the set it is wired to, or nil for a machine with no radio
-- in reach. Discovered afresh every time it is asked, exactly as the lights and
-- the doors are -- a radio is a thing somebody can pick up and carry away, and
-- the answer is only true for the moment it is asked.
function CeroSecRadio.tncAt(x, y, z)
	if getCell == nil then return nil end
	local cell = getCell()
	if cell == nil then return nil end
	local here = cell:getGridSquare(x, y, z)
	-- No square at all is a chunk the streamer has not brought in. There is no
	-- radio to find and there is no pretending otherwise (proof 6).
	if here == nil then return nil end

	local found = {}
	local room = here:getRoom()
	if room ~= nil then
		local squares = room:getSquares()
		if squares ~= nil then
			for i = 0, squares:size() - 1 do
				onSquare(squares:get(i), found)
			end
		end
	else
		local r = CeroSecRadio.REACH
		for dx = -r, r do
			for dy = -r, r do
				onSquare(cell:getGridSquare(x + dx, y + dy, z), found)
			end
		end
	end
	if #found == 0 then return nil end
	table.sort(found, before)
	return found[1]
end

-- The TNC of a machine, by the machine. nil for one that has no radio in reach
-- and for one whose own square is not loaded.
function CeroSecRadio.tncOf(luaObject)
	if luaObject == nil then return nil end
	return CeroSecRadio.tncAt(luaObject.x, luaObject.y, luaObject.z)
end

--
-- The device
--

-- The TNC as an entry for /dev, in the shape SCeroSecDevices hands the engine.
-- nil for a machine with no set in reach, which is a machine with no
-- /dev/radio0 -- and `dev radio0` on it says "no such device", which is the
-- truth.
--
-- The key is the RADIO's place and not the machine's, like every other device:
-- the number is spent on that set, so a survivor who wrote `cat /dev/radio0`
-- into a script is still reading the same aerial tomorrow.
-- Where a set IS, as one string. The device layer's number hangs on it and so
-- does the one-connection-per-radio rule, which is why it is written once: two
-- machines in one room share a set, and they have to agree about which set that
-- is down to the character.
function CeroSecRadio.keyOf(set)
	if type(set) ~= "table" then return nil end
	return CeroSecRadio.KIND .. ":" .. set.x .. ":" .. set.y .. ":" .. set.z
		.. "::0"
end

function CeroSecRadio.entryAt(x, y, z)
	local set = CeroSecRadio.tncAt(x, y, z)
	if set == nil then return nil end
	return {
		kind = CeroSecRadio.KIND,
		side = "",
		desc = set.kind,
		state = CeroSecOS.radioStateText(set.channel, set.on, set.powered),
		x = set.x, y = set.y, z = set.z,
		object = set.object,
		key = CeroSecRadio.keyOf(set),
		set = set,
	}
end

--
-- On the air
--
-- The one line the rest of the county reads. Every connect and every disconnect
-- goes out as a real transmission on the real frequency, so a survivor listening
-- on 144.390 with a walkie in his hand sees
--
--   KD4AXR de KE4QWZ *** CONNECTED
--
-- in his radio window -- the station called, "de" (which is what a Morse
-- operator has put between two callsigns since there were two callsigns), the
-- station calling, and what the TNC did. It is not decoration: it is the whole
-- security lesson of the rung made visible, because the one thing a radio cannot
-- do is keep quiet, and the only defence is to change frequency.
--
-- Sent through ZomboidRadio.SendTransmission with the TRANSMITTING radio's own
-- tile and its own transmit range, so that the game applies its own distance
-- distortion and the transmitter does not hear itself (proof 5). Arguments that
-- are not ours to choose are vanilla's: guid nil, interactCodes "" -- which is a
-- string and not nil, because the server branch drops a transmission whose
-- interactCodes is null -- and the colour triple 0.7, 0.5, 0.5, which is the one
-- vanilla writes at a call site of its own.
--
-- It announces from the CALLER's set on the caller's frequency. The two stations
-- are on one frequency by the time this is called, which is what made the link,
-- so one transmission is heard by everybody either of them could reach; a second
-- one from the far set would be the same line twice for anybody in the middle.
--

CeroSecRadio.DE = " de "
CeroSecRadio.AIR_R = 0.7
CeroSecRadio.AIR_G = 0.5
CeroSecRadio.AIR_B = 0.5

-- The line, built where the words are so that the two halves of the rung cannot
-- disagree about what a survivor with a walkie reads.
function CeroSecRadio.airLine(called, calling, what)
	return tostring(called) .. CeroSecRadio.DE .. tostring(calling) .. " " .. what
end

-- Put one line on the air from a set. Silent -- and it must be silent -- when
-- the game cannot be asked: a server whose radio subsystem is not up is a server
-- where a call still works and nobody overhears it, which is the failure a
-- player can neither see nor be hurt by. A call that could not be made at all
-- because the announcement failed would be the other kind.
function CeroSecRadio.transmit(set, line)
	if type(set) ~= "table" or type(line) ~= "string" then return false end
	if getZomboidRadio == nil then return false end
	local radio = getZomboidRadio()
	if radio == nil then return false end
	radio:SendTransmission(set.x, set.y, set.channel, line, nil, "",
		CeroSecRadio.AIR_R, CeroSecRadio.AIR_G, CeroSecRadio.AIR_B,
		set.range, false)
	return true
end

-- What a connect and a disconnect sound like to anybody listening.
function CeroSecRadio.announce(set, called, calling, what)
	return CeroSecRadio.transmit(set, CeroSecRadio.airLine(called, calling, what))
end
