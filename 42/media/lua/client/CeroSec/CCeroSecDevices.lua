require "CeroSec/CeroSecDefs"

--
-- The half of a device sync the engine does not do
--
-- Every other actuator in this mod broadcasts itself, or is broadcast by one
-- call of ours beside it, and in both cases the packet is the ENGINE's
-- (docs/DEVICES.md, the sync-call table). A television and a radio set are the
-- one pair where there is no such call. Everything worth writing on one lives on
-- zombie.radio.devices.DeviceData -- isTurnedOn and channel -- and the only
-- method that puts a change of either on the wire is
--
--   private void transmitDeviceDataState(short);
--      0: getstatic  #276    // GameClient.client:Z
--      3: ifeq       37                       <- not a client: return
--   15-20: sendDeviceDataStatePacket(GameClient.connection, arg)
--     37: return
--
-- a CLIENT branch with nothing else in it. The server's own broadcaster exists
-- and is private -- transmitDeviceDataStateServer(short, UdpConnection) -- and
-- every caller of it is inside the class. The one public wrapper,
-- transmitBatteryChangeServer(), passes the short 2, and the tableswitch 0..10
-- in sendDeviceDataStatePacket (offset 345) spends 2 on hasBattery and
-- powerDelta: 0 is isTurnedOn and 1 is the channel, and nothing public reaches
-- either of those.
--
-- So a server-side setIsTurnedOn(true) moves the field on the server and leaves
-- every client's copy dark and silent. The mod carries the sync itself: the
-- server writes the field and sends one `device` packet
-- (CeroSecDevices.syncWave), and this file is what the far end does with it.
--
-- WHAT THE FAR END MUST NOT DO is call the public setters. On a client
-- transmitDeviceDataState really does send, so a client that applied the change
-- with setIsTurnedOn would answer the server's packet with a packet of its own,
-- the server would relay that to everybody (receiveDeviceDataStatePacket's
-- server branch), and one crontab line would cost a round trip per client.
--
-- What it does instead is what the ENGINE does on this very path, which is why
-- it is enough:
--
--   receiveDeviceDataStatePacket, state 0, on a client -- GameServer.server is
--   false, so the test at offset 104 falls through: setIsTurnedOnInternal(
--   getBoolean()) at 124-129, the private field write, and no transmit. State 1
--   in the same branch is `putfield channel` at 179-182, a bare field write.
--
--   IsoWaveSignal.loadState(ByteBuffer), which is how a chunk's object state
--   reaches a client at all, does the same three through the PUBLIC names:
--   setTurnedOnRaw(Z) at 116-132, setChannelRaw(I) at 135-143 and
--   setDeviceVolumeRaw(F) at 146-154.
--
-- Those two public raw setters are therefore the calls:
--
--   public void setTurnedOnRaw(boolean);
--      setIsTurnedOnInternal(arg), and then the equipped-radio frequency
--      refresh, which is behind `getParent() instanceof Radio` -- an inventory
--      item, which a fixture standing on a square never is.
--   public void setChannelRaw(int);
--      0: aload_0  1: iload_1  2: putfield channel:I  5: return
--
-- AND THE SCREEN, THE GLOW AND THE SOUND ALL FOLLOW THAT FIELD on a client, with
-- nothing else called:
--
--   the picture  IsoTelevision.update() ends on updateTvScreen() at offsets
--                57-58, unconditionally, and updateTvScreen's first test is
--                deviceData.getIsTurnedOn() (12-19): true is the test screen or
--                the alternate one, false is OFFSCREEN.
--   the glow     IsoWaveSignal.update(), the not-a-server branch at 48-105:
--                getIsTurnedOn() decides updateLightSource() against
--                removeLightSourceFromWorld().
--   the sound    the same method sends a client to DeviceData.updateSimple()
--                (offset 41, out of the branch at 8-23), which calls
--                updateEmitter() at 118-125 behind GameClient.client -- and
--                updateEmitter reads isTurnedOn at 45-49 to decide whether the
--                loop sound plays.
--
-- SINGLE PLAYER NEVER COMES HERE and needs nothing: there is one process, so the
-- object the server wrote is the object the survivor is looking at, and
-- sendServerCommand does nothing at all with no GameServer behind it (the proof
-- is beside the send, in SCeroSecDevices.lua).
--
-- AND NEITHER DOES A LATE JOINER. That one is the engine's work and is written
-- down here because it looks like ours: every chunk a client loads asks the
-- server for that chunk's object state -- IsoChunk.doLoadGridsquare, offsets
-- 1650-1675, `if (GameClient.client) connection.addChunkObjectState(wx)` and the
-- same for wy -- and the server answers out of the LIVE object, through
-- ChunkObjectStateRequestPacket.parse -> IsoChunk.saveObjectState (offset 99) ->
-- IsoObject.saveState per object (124-127), where IsoWaveSignal.saveState writes
-- getIsTurnedOn() at 73-93 and getChannel() at 94-105. So a player who connects
-- an hour after cron switched the television on sees it on, and a player who
-- walks back into a chunk that was unloaded sees what it is doing now. There is
-- nothing for this file to do about either.
--

CCeroSecDevices = CCeroSecDevices or {}

-- The one command word this file answers to. Named here and read by the server
-- through nothing at all -- the server has its own copy in
-- CeroSecDevices.SYNC -- because a client cannot load a server file and a
-- server cannot load this one. The two are held together by a bench
-- (tests/window_test.lua) and not by a require that cannot exist.
CCeroSecDevices.COMMAND = "device"

local function squareAt(x, y, z)
	if getCell == nil then return nil end
	local cell = getCell()
	if cell == nil then return nil end
	return cell:getGridSquare(x, y, z)
end

-- The object the server wrote, found again on this side: a Java handle does not
-- travel, so what comes over is where it is, what class it is, what it looks
-- like and WHICH of that square's objects it was.
--
-- The index first, because two identical televisions on one tile is the one case
-- a class and a sprite name cannot tell apart -- and the index agrees on both
-- sides for as long as nobody has added or taken away an object on that square,
-- both lists being built from the same chunk. The class and the sprite are what
-- catch it when somebody has: an index that answers the wrong sort of thing is
-- not believed, and the scan is the answer instead.
--
-- nil for a square the streamer has not brought in, which is a client with
-- nothing to change: the chunk will ask the server for the object's state on the
-- way in (see the head of this file), so a packet missed here is not a packet
-- lost.
function CCeroSecDevices.objectAt(args)
	local square = squareAt(args.x, args.y, args.z)
	if square == nil then return nil end
	local objects = square:getObjects()
	if objects == nil then return nil end

	local function matches(object)
		if object == nil then return false end
		if not instanceof(object, args.class) then return false end
		return object:getSpriteName() == args.sprite
	end

	local index = args.index
	if type(index) == "number" and index >= 0 and index < objects:size() then
		local object = objects:get(index)
		if matches(object) then return object end
	end

	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		if matches(object) then return object end
	end
	return nil
end

-- One `device` packet, applied. Nothing is answered and nothing is sent back:
-- this is the end of the wire.
--
-- Every field is checked for its type before it is used, like every other
-- message this client believes: a packet is something that arrived, and the one
-- from a machine that is not this build has to do nothing rather than something
-- odd. A packet carrying neither field moves nothing, which is what it says.
function CCeroSecDevices.onServerAnswer(command, args)
	if command ~= CCeroSecDevices.COMMAND then return end
	if type(args) ~= "table" then return end
	if type(args.x) ~= "number" or type(args.y) ~= "number"
			or type(args.z) ~= "number" then
		return
	end
	if type(args.class) ~= "string" or args.class == "" then return end
	if type(args.sprite) ~= "string" or args.sprite == "" then return end

	local object = CCeroSecDevices.objectAt(args)
	if object == nil then return end
	if type(object.getDeviceData) ~= "function" then return end
	local data = object:getDeviceData()
	if data == nil then return end

	if type(args.on) == "boolean" then data:setTurnedOnRaw(args.on) end
	if type(args.channel) == "number" then
		data:setChannelRaw(math.floor(args.channel))
	end
end
