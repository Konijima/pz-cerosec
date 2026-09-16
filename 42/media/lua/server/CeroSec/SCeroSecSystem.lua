if isClient() then return end

require "Map/SGlobalObjectSystem"
require "CeroSec/CeroSecContent"
require "CeroSec/CeroSecDefs"
-- The self-test and its generated vectors. Named here even though the game loads
-- every file under shared/ on its own, for the reason every other line in this
-- block is here: `Commands.debugact` calls CeroSecSelfTest.runAll, and a load order
-- nobody wrote down is a nil call waiting for the day the game walks shared/ in a
-- different order. The vectors are a second require because they are a second file
-- -- generated, and the runner reads CeroSecSelfTest.VECTORS when it is CALLED and
-- never at load time, which is what lets the two be loaded in either order.
require "CeroSec/CeroSecSelfTest"
require "CeroSec/CeroSecSelfTestVectors"
require "CeroSec/CeroSecNotes"
require "CeroSec/CeroSecModules"
require "CeroSec/SCeroSecDebug"
require "CeroSec/SCeroSecDevices"
require "CeroSec/SCeroSecAuto"
require "CeroSec/SCeroSecNet"
require "CeroSec/SCeroSecJobs"
require "CeroSec/SCeroSecObject"

SCeroSecSystem = SGlobalObjectSystem:derive("SCeroSecSystem")

-- The module name of the one-player replies. The global object channel has its
-- own name ("cerosec", below) and is a broadcast; this one is the module of
-- sendServerCommand(player, ...), which is what a dedicated server answers a
-- single client on.
SCeroSecSystem.MODULE = "CeroSec"

function SCeroSecSystem:new()
	return SGlobalObjectSystem.new(self, "cerosec")
end

function SCeroSecSystem:initSystem()
	SGlobalObjectSystem.initSystem(self)

	-- Fields of this system that are saved. It was nil -- nothing -- until this
	-- change: the world content needs ONE number that belongs to the save and not to
	-- a machine, and this is where it goes.
	--
	--   seed   the per-save secret, sixteen hex digits (CeroSecContent).
	--   notes  which premises have already had their desk note (CeroSecNotes).
	--   desks  what the machines of each premises already ARE -- whose desk, a
	--          display model, a spare (CeroSecContent.deskRole). Here for the same
	--          reason `notes` is: the computers of one premises are switched on over
	--          many sessions, and a table that lived in memory would give the second
	--          desk the owner the first one already has.
	--
	-- Proved at the bytecode level on projectzomboid.jar 42.20.4, because "it
	-- probably persists" is not a thing to bet a player's save on:
	--
	--   SGlobalObjectSystem.setModDataKeys(KahluaTable) clears its HashSet and adds
	--       every STRING in the table handed over (offsets 0-81; a non-string is an
	--       IllegalArgumentException, so the list is names and nothing else).
	--   SGlobalObjectSystem.save(ByteBuffer) makes a fresh table, walks the
	--       system's own modData, copies across ONLY the keys in that HashSet
	--       (rawget/rawset at 69-74 behind a HashSet.contains at 54) and writes it
	--       with KahluaTable.save at 112.
	--   SGlobalObjectSystem.load(ByteBuffer, int) reads it straight back into the
	--       same modData table (KahluaTable.load at offset 13).
	--
	-- And the Lua system object IS that modData table -- SGlobalObjectSystem.lua:19
	-- takes `system:getModData()` and gives it this class's metatable -- so
	-- `self.seed` is the field, and gos_cerosec.bin is where it lands: the same file
	-- the machines are already in, written and read with the save.
	--
	-- NOT ModData.getOrCreate/transmit, which was the other candidate. That is the
	-- global mod-data channel and its whole purpose is to be TRANSMITTED to clients
	-- -- and the secret is what every password in the county is derived from. It
	-- stays on the server. Nothing puts it in setObjectSyncKeys, nothing puts it in
	-- getInitialStateForClient, and a client is never told a password: it is told
	-- the lines a machine printed, exactly as before.
	-- The three lists are CeroSecDefs' (CeroSec.SYSTEM_SAVE_KEYS and the two
	-- below), not literals here: `seed` must be in this one and must never be in
	-- the sync one, and CeroSecSelfTest.keys is what holds them to it in a real
	-- save on the real Kahlua. A literal here is a rule nothing can read.
	self.system:setModDataKeys(CeroSec.SYSTEM_SAVE_KEYS)

	-- Fields of each GlobalObject that are saved to gos_cerosec.bin. 'os' and
	-- 'console' are nested tables; the serializer recurses into those
	-- (KahluaTableImpl.save). The console is saved so that a screen survives a
	-- save and a reload the way it survives a player walking away: the machine
	-- is what remembers, not the session.
	self.system:setObjectModDataKeys(CeroSec.OBJECT_SAVE_KEYS)

	-- Fields sent to clients on add/update. Without this the client mirror
	-- receives an empty table (SGlobalObjectNetwork saves only these keys).
	-- 'os' and 'console' are deliberately absent: the client never reads the
	-- filesystem nor the stored screen, it only ever sees the lines the server
	-- answers it with.
	-- 'disk' is a derived boolean and not part of the state: whether there is a
	-- disk in the slot, so the right-click menu can offer Insert or Eject before
	-- it sends anything. It is deliberately NOT in the saved keys above -- what is
	-- in the drive is state.floppy's to say, and the flag is worked out again on
	-- every load (SCeroSecObject:syncDisk).
	self.system:setObjectSyncKeys(CeroSec.OBJECT_SYNC_KEYS)
end

function SCeroSecSystem:newLuaObject(globalObject)
	local luaObject = SCeroSecObject:new(self, globalObject)
	-- Every machine in the save file comes through here once, at load
	-- (SGlobalObjectSystem:initLuaObjects), with its saved fields already in the
	-- table -- SGlobalObject.new hands back the GlobalObject's own modData, which is
	-- what gos_cerosec.bin was read into. So this is where a county that was left
	-- running gets into the sweep's index, and the only place it could be.
	self:indexMachine(luaObject)
	return luaObject
end

--
-- THE PER-SAVE SECRET
--
-- Sixteen hex digits, made once for the life of the save and never again. A
-- string and not a number: a Lua double carries 53 bits of mantissa, so a 64-bit
-- integer kept as one is an integer whose bottom eleven bits are a lie, and it
-- would ride into gos_cerosec.bin that way.
--
-- Everything the world content generates is hash(this, key), so this number is
-- what makes a password the same password on every reload and a different one in
-- the next save. Made LAZILY, at the first machine that needs it, rather than at
-- server start: a save where nobody ever switches a computer on never grows the
-- field, and a save that has one keeps it for ever.
--
-- The randomness is the engine's own, the way vanilla rolls anything: four draws
-- of ZombRand(65536) -- `ZombRand(double)` is on LuaManager$GlobalObject, javap'd
-- -- and the millisecond clock mixed in, so two servers started from the same
-- image at the same moment do not agree. A box with neither is a box with no
-- world in it, which is a bench, and it gets a fixed secret rather than a nil:
-- a bench must be able to reach this code, and a save with no secret would mean
-- every read of it had to answer "maybe".
SCeroSecSystem.BENCH_SECRET = "cec05ec0cec05ec0"

local function hex4(n)
	local out = ""
	local digits = "0123456789abcdef"
	for _ = 1, 4 do
		local d = math.fmod(math.floor(n), 16)
		out = string.sub(digits, d + 1, d + 1) .. out
		n = math.floor(n / 16)
	end
	return out
end

-- The method is `secret` and the field is `seed`, deliberately not one word: a
-- method and an instance field of the same name on a table whose metatable is its
-- own class is a field that SHADOWS the method the moment it is written, and the
-- second call would try to call a string.
function SCeroSecSystem:secret()
	if CeroSecContent.isSecret(self.seed) then return self.seed end
	-- No generator at all, which is a box with no game in it. The fixed secret is
	-- WRITTEN to the field rather than merely answered, so that everything in such
	-- a session agrees with everything else in it -- a paper written before a
	-- generator appeared and a machine prefilled after it would otherwise disagree
	-- for ever, which is the one failure this whole design exists to make
	-- impossible.
	if ZombRand == nil then
		self.seed = SCeroSecSystem.BENCH_SECRET
		return self.seed
	end
	local ms = 0
	if getTimestampMs ~= nil then ms = getTimestampMs() or 0 end
	local secret = ""
	local scale = 1
	for i = 1, 4 do
		local draw = math.floor(ZombRand(65536))
		-- The clock, one chunk of it per draw, so a run of ZombRand that happened to
		-- repeat does not make two saves agree.
		local slice = math.fmod(math.floor(ms / scale), 65536)
		secret = secret .. hex4(math.fmod(draw + slice, 65536))
		scale = scale * 65536
	end
	if not CeroSecContent.isSecret(secret) then return SCeroSecSystem.BENCH_SECRET end
	self.seed = secret
	CeroSec.log("the save's content secret was made")
	return secret
end

function SCeroSecSystem:isValidIsoObject(isoObject)
	return isoObject ~= nil and CeroSec.isComputerSprite(isoObject:getSpriteName())
end

-- Sent to a client when it connects, and to the local client in singleplayer.
function SCeroSecSystem:getInitialStateForClient()
	return nil
end

-- Events.OnObjectAdded only fires for objects a player or the network added
-- (AddItemToMapPacket, and ISMoveableSpriteProps.lua:2382 for placement) --
-- never for chunk loading. So reaching here means the computer was just placed:
-- it starts off, whatever it was before.
function SCeroSecSystem:OnObjectAdded(isoObject)
	if not self:isValidIsoObject(isoObject) then return end
	if not isoObject:getSquare() then return end

	local square = isoObject:getSquare()
	local luaObject = self:getLuaObjectOnSquare(square)
	if not luaObject then
		luaObject = self:newLuaObjectOnSquare(square)
		luaObject:initNew()
	end
	luaObject:resetForPlacement(isoObject)
end

-- THIS COMPUTER'S SQUARE HAS JUST BEEN MADE, for the first time in this save.
--
-- One bit written down and nothing else. Which premises it is in, what the premises
-- is called and whether there is a wire at the square are all questions about the
-- world, and they are asked one minute later on the sweep -- see the head of
-- SCeroSecAuto.lua for why they are not asked here and for the bytecode that says
-- this only ever runs on a chunk built out of the map.
--
-- NOT resetForPlacement and nothing like it: a computer created with the chunk is
-- whatever the map made it, and OnObjectAdded above is the other thing entirely --
-- a computer a survivor put down out of his hands.
function SCeroSecSystem:markBorn(isoObject)
	if not self:isValidIsoObject(isoObject) then return end
	local square = isoObject:getSquare()
	if not square then return end
	local luaObject = self:getLuaObjectOnSquare(square)
	if not luaObject then return end
	luaObject.born = true
	-- And into the sweep's list of machines with a question outstanding, which is
	-- how the sweep finds it next minute without walking the county.
	luaObject:reindex()
end

-- The client walks the player to the square in front of the screen before it
-- sends anything, but the client is not to be trusted. Vanilla's own global
-- object commands do not check proximity at all (SCampfireSystemCommands.lua),
-- so the tolerance comes from the one place vanilla decides a player is close
-- enough to interact without walking: luautils.lua:138-140, half a square of
-- centre offset and 1.6 of slack on each axis. Adjacency only -- which of the
-- four sides he stands on is the client's business.
local function isAdjacent(playerObj, x, y, z)
	if not playerObj then return false end
	local square = playerObj:getCurrentSquare()
	if not square or square:getZ() ~= z then return false end
	return math.abs(x + 0.5 - playerObj:getX()) <= 1.6
		and math.abs(y + 0.5 - playerObj:getY()) <= 1.6
end

-- Which window a command comes from. The token alone would do inside one
-- connection, but two clients pick their tokens independently, so the online id
-- goes in front of it: what is being named here is one window on one machine.
-- getOnlineID is what vanilla keys per-player server state on
-- (Fishing.ServerBobberManager, Bobber.lua:26).
local function watcherKeyOf(playerObj, token)
	return tostring(playerObj:getOnlineID()) .. "/" .. tostring(token)
end

-- A token for a window that is not there yet. Every other token in this mod is
-- the client's own -- the window picks one and stamps its commands with it -- and
-- this is the one the server has to mint, because the window it names is one the
-- server is asking the client to build (reopenFor, after a reboot). Shaped like
-- the window's own (CeroSecTerminal's newToken) with an "s" in front, so a
-- server's token and a client's can never be the same string.
SCeroSecSystem.tokenCount = 0

local function newServerToken(playerObj)
	SCeroSecSystem.tokenCount = SCeroSecSystem.tokenCount + 1
	return "s" .. tostring(playerObj:getPlayerNum()) .. "-" ..
		tostring(getTimestampMs()) .. "-" .. tostring(SCeroSecSystem.tokenCount)
end

--
-- Answering one player
--
-- The global object channel only broadcasts (SGlobalObjectSystem:sendCommand ->
-- SGlobalObjectNetwork.sendServerCommand -> sendPacket, which writes to every
-- connection), and a terminal's output is nobody else's business. So on a
-- server the answer goes out with sendServerCommand(player, ...), which
-- resolves the player's own connection (GameServer.sendServerCommand:
-- PlayerToAddressMap). In singleplayer that call does nothing at all
-- (LuaManager.GlobalObject.sendServerCommand is guarded by GameServer.server),
-- and the broadcast reaches the one player there is, so the broadcast is what
-- singleplayer uses. Both carry the player key, and the terminal only listens
-- to answers addressed to it.
--

function SCeroSecSystem:reply(playerObj, command, args)
	if isServer() then
		sendServerCommand(playerObj, SCeroSecSystem.MODULE, command, args)
	else
		self:sendCommand(command, args)
	end
end

-- Tell a terminal to shut itself: the machine is off, out of reach, or broken.
function SCeroSecSystem:replyClosed(playerObj, x, y, z, reason, token)
	self:reply(playerObj, "closed", { x = x, y = y, z = z, reason = reason, token = token })
end

--
-- Commands
--
-- client -> server, all of them carrying the computer's x, y, z and the
-- terminal's token:
--   toggle   {}                     -- rung 1
--   insertfloppy { item }           -- the id of a floppy in the sender's own
--                                      inventory; the server reads the item
--                                      itself and believes nothing about what
--                                      is written on it
--   ejectfloppy  {}                 -- give the disk back
--   installmodule   { module, index } -- screw a hardware module to the door,
--   uninstallmodule { module, index }    window or light switch at that index
--                                        on that square, or take it off again.
--                                        The x, y, z of these two are the
--                                        FIXTURE's square and not a computer's:
--                                        they are the only commands here that
--                                        are not about a machine at all.
--   open     {}                     -- give me the screen
--   input    { text }               -- the answer to whatever is being asked:
--                                      a user name, a password, or the line a
--                                      command asked for. The console knows
--                                      which, and the client never has to.
--   exec     { line }
--   complete { line, cursor }       -- Tab: what the word at the cursor may
--                                      become. Changes nothing on the machine.
--   histtail {}                     -- the history of whoever is logged in now
--   editbuf  { text }               -- the buffer as it stands, no file touched
--   editsave { text }               -- the buffer, and write it
--   editexit { }                    -- leave the editor, buffer dropped
--   interrupt {}                    -- Escape while the machine is in the
--                                      middle of something: drop the question
--                                      it asked and go back to the prompt
--   close    {}
-- server -> client, every answer carrying the token of the terminal it belongs
-- to, because a connection is not a window:
--   opened  { x, y, z, token, hostname, booted, lines, prompt, mode, mask,
--             active, edit, animate }
--   screen  { x, y, z, token, hostname, booted, lines, prompt, mode, mask,
--             active, edit }
--   closed  { x, y, z, token, reason }
--   history { x, y, z, token, lines }
--   drive   { x, y, z, player, why, detail }
--                                   -- a floppy gesture that did nothing. why is
--                                      a code and not a sentence ("gone",
--                                      "occupied", "nodisk", "refused",
--                                      "broken"); detail is the machine's own
--                                      reason when there is one. Carries no
--                                      token: the drive is mechanical and works
--                                      with no window open, so it is addressed
--                                      to a PLAYER and lands in his halo.
--   completed { x, y, z, token, line, at, start, replacement, cursor,
--             candidates }
--
-- 'completed' is the one answer that is not a screen, and it is addressed to
-- ONE window: the word a player is halfway through typing is his own and is on
-- nobody else's glass. line and at are the line and the cursor it was worked
-- out against, so a window that has typed on in the meantime can drop it;
-- start..at is what replacement takes the place of, cursor is where the caret
-- lands, and candidates is every name that matched -- sorted, for the listing a
-- second Tab prints.
--
-- There is one answer for everything that happens on a screen, and it is the
-- whole screen. The server owns the console, so the client has nothing to
-- reconstruct and nothing to guess: it draws the lines it was handed, under the
-- prompt it was handed. 'opened' is that same payload plus the one thing only
-- the opener is told: whether the BIOS is still to be played.
--
-- mode is "prompt", "shell" or "edit". Which of the machine's questions is
-- being asked is the machine's business; all that travels is the line to put on
-- the glass and whether the answer shows as stars.
--
-- edit is the editor's own screen, and the only part of an answer that is not
-- the same for everybody: it carries whether *this* window is the one holding
-- the keyboard on that buffer.
--

local Commands = {}

-- The computer a command names, or nil after having told the player why not.
-- Every command re-checks the three things a terminal depends on: the computer
-- exists, the player is next to it, and it is on.
function SCeroSecSystem:computerFor(playerObj, x, y, z, token)
	if not isAdjacent(playerObj, x, y, z) then
		self:replyClosed(playerObj, x, y, z, "reach", token)
		return nil
	end

	local luaObject = self:getLuaObjectAt(x, y, z)
	if not luaObject then
		-- The client saw a computer we have no GlobalObject for; adopt it.
		local isoObject = self:getIsoObjectAt(x, y, z)
		if isoObject then
			self:loadIsoObject(isoObject)
			luaObject = self:getLuaObjectAt(x, y, z)
		end
	end
	if not luaObject then
		self:replyClosed(playerObj, x, y, z, "gone", token)
		return nil
	end

	if not luaObject.on then
		self:replyClosed(playerObj, x, y, z, "off", token)
		return nil
	end
	return luaObject
end

-- The computer and its screen, with no working OS required. A machine whose
-- disk has been wiped still has power and still has a screen, and that screen
-- is where it is repaired from -- so the BIOS' own two commands come in this
-- way and everything else comes in through consoleFor below.
function SCeroSecSystem:biosConsoleFor(playerObj, x, y, z, token)
	-- A window with no usable token is a window nothing can be addressed to:
	-- every answer is matched on it, so there is nothing to answer here.
	if token == nil then return nil end
	local luaObject = self:computerFor(playerObj, x, y, z, token)
	if not luaObject then return nil end

	local console = luaObject:consoleState()
	if not console then
		self:replyClosed(playerObj, x, y, z, "off", token)
		return nil
	end
	return luaObject, console
end

-- The computer, its filesystem and its screen, or nil after having told the
-- player why not. Every path that needs a filesystem goes through here.
function SCeroSecSystem:consoleFor(playerObj, x, y, z, token)
	local luaObject, console = self:biosConsoleFor(playerObj, x, y, z, token)
	if not luaObject then return nil end

	local state, reason = luaObject:osState()
	if not state then
		self:replyClosed(playerObj, x, y, z, "broken", token)
		if reason then CeroSec.log(CeroSec.LOG_WARN, "console refused: " .. tostring(reason)) end
		return nil
	end
	return luaObject, state, console
end

-- Where a keystroke goes.
--
-- A window is open on ONE computer and names that one in every command it sends.
-- What is on its glass may be a shell on another machine entirely: an rlogin puts
-- the far machine's session on this screen, and a second one puts a third
-- machine's session on it. So every command that types AT the machine resolves
-- the chain here, and what comes back is the machine whose shell is behind the
-- glass, that machine's filesystem, the console the glass is showing, and the
-- computer the window is actually standing at.
--
-- A chain that has gone -- the far machine switched off, the session closed from
-- the other side, the computer picked up -- is torn down here and the glass goes
-- back to the console it belongs to. That is the honest answer for a keystroke
-- sent to a session that is over, and it is the one place every command gets it
-- for free.
-- The chain a console is at the near end of, followed to the shell at the far
-- end of it. The machine, its filesystem and the console the glass is really
-- showing -- which is the machine's own when nothing is open.
--
-- nil when a link has gone: the session is torn down here and the caller hands
-- the local screen back, which is the honest answer for a keystroke sent to a
-- session that is over.
function SCeroSecSystem:followChain(luaObject, state, console)
	local object, at = luaObject, state
	-- Bounded by the hop ceiling and one more, so a chain can never be a loop:
	-- every link was made by an rlogin that paid for it.
	for _ = 1, CeroSecOS.HOP_MAX + 1 do
		if console.remote == nil then return object, at, console end
		local pty, far, farState = CeroSecNet.farOf(self, console)
		if pty == nil then
			CeroSecNet.hangUp(self, console)
			return nil, object, at, console
		end
		object, at, console = far, farState, pty.console
	end
	return object, at, console
end

function SCeroSecSystem:targetFor(playerObj, x, y, z, token)
	local host, state, console = self:consoleFor(playerObj, x, y, z, token)
	if not host then return nil end
	local object, at, shown = self:followChain(host, state, console)
	if object == nil then
		-- at and shown carry the near end the chain broke at, so the glass it was
		-- looking at gets its own screen back.
		self:pushScreen(at, shown, console)
		return nil
	end
	return object, at, shown, host
end

--
-- The BIOS
--
-- Before a machine hands over its login prompt it looks at what is on the disk:
-- the commands in /bin and the accounts in /etc/passwd. Root may take either
-- away -- that is what root is -- and a machine with neither is not broken so
-- much as blank, so what it says is what a 1993 machine with an empty disk
-- says, and it offers to put the system back.
--
-- The question is an ordinary console prompt with an ordinary continuation
-- token, so the window needs to know nothing about any of this: it draws the
-- prompt it is handed and sends back the line that was typed. The token's
-- command is answered HERE and never by CeroSecOS.continue, because there is no
-- session to run it under -- nobody is logged in, and on a machine with no
-- /etc/passwd nobody could be.
--

--
-- The clock
--
-- The engine has none of its own and asks for none: every call into it that can
-- change the disk is handed one, in env.now, and the number below is where it
-- comes from. It is the GAME's calendar -- the hour and the day the survivor
-- standing at the keyboard is living in -- so a file written at four in the
-- morning is stamped four in the morning, and July 1993 is July 1993.
--
-- The calls, verified with javap on zombie.GameTime and used the same way
-- vanilla Lua uses them (media/lua/server/Farming/SPlantGlobalObject.lua,
-- media/lua/server/Seasons/season.lua):
--   getYear()    full year, 1993 on a default sandbox
--   getMonth()   0..11 -- vanilla adds 1 to it everywhere it is printed
--   getDay()     0-based day of the month, which is why getDayPlusOne() exists
--   getHour()    0..23
--   getMinutes() 0..59
-- There is no getSeconds(): the game's finest hand is the minute, so the second
-- is 0 and `date` prints ":00". That is the game's clock and not a rounding of
-- ours.
--
-- A machine running where there is no GameTime -- a test harness, a load order
-- nobody expected -- is handed an env with no clock in it rather than a wrong
-- one, and the OS says "no clock".
function SCeroSecSystem:clockEnv()
	if getGameTime == nil then return {} end
	local gt = getGameTime()
	if gt == nil then return {} end
	local now = CeroSecOS.timeFromParts(gt:getYear(), gt:getMonth() + 1, gt:getDay() + 1,
		gt:getHour(), gt:getMinutes(), 0)
	if now == nil then return {} end
	return { now = now }
end

-- WHEN THE SAVE BEGAN, as the one number the engine carries. A fact about the
-- SAVE and not about any machine, which is why it is here beside the clock.
--
-- The start getters are the same zero-based encoding getMonth and getDay are:
-- GameTime's constructor sets `day` and `startDay` from one literal and `month`
-- and `startMonth` from another (javap -c zombie.GameTime, offsets 66-69 and
-- 102-105), so the "+ 1" clockEnv already puts on the current date belongs on the
-- start date too. getStartYear/getStartMonth/getStartDay are public and zero-arg.
--
-- nil for a box with no game in it, which is a bench -- and a machine prefilled
-- with no start date is a machine with no /var/log, because a log line with no
-- date on it is not a log line.
function SCeroSecSystem:startTime()
	if getGameTime == nil then return nil end
	local gt = getGameTime()
	if gt == nil then return nil end
	if gt.getStartYear == nil then return nil end
	-- Every one of the three read, and every one of them checked, the way clockEnv
	-- checks its own answer: a game that will not say what day it started is a
	-- machine with no log on it, and never a machine with a log dated in 1970.
	local year, month, day = gt:getStartYear(), gt:getStartMonth(), gt:getStartDay()
	if type(year) ~= "number" or type(month) ~= "number" or type(day) ~= "number" then
		return nil
	end
	return CeroSecOS.timeFromParts(year, month + 1, day + 1, 0, 0, 0)
end

--
-- The world outside the machine
--
-- Everything the engine is handed that is not its own filesystem: the clock,
-- and the devices under /dev. Built fresh for every line typed, because both
-- halves are answers about a moment -- what time it is, and what is standing
-- around the computer right now.
--
-- The devices need the state, because a device's NUMBER lives on it
-- (state.devmap) and has to survive a reload; a call with no state is a call
-- with no numbers, and the machine simply has no devices.
--
-- playerObj and token are who typed the line and at which window, and they
-- travel because one thing a device can be asked to do -- `dev find` on a door
-- -- is answered on ONE screen and not on the machine's: see the head of
-- SCeroSecDevices.lua. A terminal believes nothing that does not carry its own
-- token back (CeroSecTerminal:isMine), highlights included.
function SCeroSecSystem:execEnv(luaObject, state, playerObj, token)
	local env = self:clockEnv()
	if state ~= nil then
		env.devices = CeroSecDevices.envFor(luaObject, state, self, playerObj, token)
	end
	-- The wall clock, which is not the game's: `sleep 5` is five seconds of the
	-- player's life and not five of Knox County's, because it is the machine
	-- waiting and not the world turning.
	env.nowMs = getTimestampMs()
	-- The machine's jobs, so that ps, jobs and kill read the very tables the
	-- scheduler steps -- there is no second copy of a job anywhere.
	if luaObject ~= nil and luaObject.jobs ~= nil then env.jobs = luaObject.jobs.list end
	-- How long it has been up, in seconds, and its three load averages: what
	-- `uptime` and `w` print. Both are RUNTIME like the jobs -- a server that came
	-- back up counts from the restart, which is what `ruptime` already says about
	-- a machine on the wire (see upOf in SCeroSecNet.lua, the same number) -- and
	-- the averages are moved by CeroSecJobs' own pass (CeroSecOS.loadSample).
	if luaObject ~= nil and type(luaObject.upMs) == "number" then
		local up = math.floor((env.nowMs - luaObject.upMs) / 1000)
		if up < 0 then up = 0 end
		env.up = up
	end
	if luaObject ~= nil and luaObject.jobs ~= nil and type(luaObject.jobs.load) == "table" then
		env.load = luaObject.jobs.load
	end
	-- The stations the TNC has heard since the power came on, so that MHEARD reads
	-- the very list the link layer writes (CeroSecNet.heardOnAir) -- there is no
	-- second copy of it either. Handed over by REFERENCE, because MHCLEAR empties
	-- it where it lies, the way `kill` reaches the job it was handed the same way.
	if luaObject ~= nil then env.heard = luaObject.heard end
	-- The wire. Like the devices, it is an answer about a MOMENT -- which machines
	-- are on it right now, and who is sitting at them -- so it is built fresh for
	-- every line typed and never remembered.
	if luaObject ~= nil and state ~= nil then
		env.net = CeroSecNet.envFor(self, luaObject, state)
	end
	return env
end

SCeroSecSystem.BIOS_PROMPT = "Restore system? (y/n) "

-- The file sh reads at login, under the name it has had since the seventh
-- edition. It is an ordinary file in an ordinary home: the BIOS repair does not
-- touch homes, so restoring a machine never takes one away.
SCeroSecSystem.PROFILE_NAME = ".profile"

-- The state, or nil when this machine has nothing to boot. Both halves of the
-- test in one place: a state the validator refuses (osState is nil) and a state
-- that runs but is no longer an operating system are the same thing to a BIOS.
function SCeroSecSystem:biosState(luaObject)
	local state = luaObject:osState()
	if state == nil then return nil end
	local ok, reason = CeroSecOS.systemOk(state)
	if not ok then
		CeroSec.log(CeroSec.LOG_WARN,
			"no system at " .. luaObject.x .. "," .. luaObject.y .. ": " .. tostring(reason))
		return nil
	end
	return state
end

-- Is the screen the BIOS' rather than the OS'? Either the question is up, or it
-- was answered "n" and the machine is sitting on its refusal.
function SCeroSecSystem:atBios(console)
	if CeroSec.consoleHalted(console) then return true end
	local prompt = console.prompt
	return type(prompt) == "table" and type(prompt.cont) == "table"
		and prompt.cont.cmd == "bios" and true or false
end

function SCeroSecSystem:askBios(console)
	console.halted = nil
	CeroSec.consolePush(console, "No operating system found.")
	console.prompt = {
		text = SCeroSecSystem.BIOS_PROMPT,
		mask = false,
		cont = { cmd = "bios" },
	}
end

-- What the firmware says about a disk written by a LATER build of the mod: the one
-- machine with nothing to boot that the BIOS must not offer to repair.
--
-- 60 columns, like every line the engine puts on this screen.
SCeroSecSystem.NEWER_LINE = "System newer than firmware: update the mod."

-- A machine with nothing to boot, and the one place the two reasons are told
-- apart.
--
-- "No operating system found" is a QUESTION, because the BIOS can answer it: the
-- system files are gone off a disk this build understands, and the repair puts them
-- back. A state a LATER build wrote is not a question at all -- nothing here can
-- read it, and "y" would mean this build writing its own shape over a save its own
-- author could still open -- so the screen says what is wrong and stops there.
--
-- Halted and not prompting, which is what makes it a dead end rather than a
-- refusal to be argued with: atBios is true for a halted console, so the line is
-- said once and every later look at the machine leaves the screen exactly as it is.
-- Nothing is reset, nothing is written back to the disk, and the switch at the back
-- of the case still works -- turnOff has never needed a state (SCeroSecObject).
function SCeroSecSystem:sayNoSystem(luaObject, console)
	if luaObject.osNewer then
		console.prompt = nil
		console.halted = true
		CeroSec.consolePush(console, SCeroSecSystem.NEWER_LINE)
		return
	end
	self:askBios(console)
end

-- The screen, worked out again from whatever the machine is now: a repair that
-- worked means the state is back and the login prompt with it.
function SCeroSecSystem:pushBios(luaObject, console)
	self:pushScreen(luaObject, self:biosState(luaObject), console)
end

-- The answer to the BIOS' question, and every line typed while the machine is
-- sitting on "No operating system found." -- there is nothing else it can be.
function SCeroSecSystem:answerBios(luaObject, console, playerObj, token, text)
	local asked = console.prompt
	console.prompt = nil
	if asked ~= nil then CeroSec.consolePush(console, asked.text .. text) end
	local answer = string.lower(text)

	-- The way out of a machine that cannot be repaired.
	if answer == "exit" then
		console.halted = true
		self:pushBios(luaObject, console)
		self:replyClosed(playerObj, luaObject.x, luaObject.y, luaObject.z, "exit", token)
		return
	end

	if asked ~= nil and (answer == "y" or answer == "yes") then
		CeroSec.consolePush(console, "Restoring system ...")
		luaObject:restoreOS()
	elseif asked ~= nil and (answer == "n" or answer == "no") then
		-- The screen stays where it is. Anything typed at it brings the
		-- question back, which is the whole of what a halted machine does.
		console.halted = true
		self:pushBios(luaObject, console)
		return
	end

	local state = self:biosState(luaObject)
	if state == nil then
		self:sayNoSystem(luaObject, console)
	else
		console.halted = nil
		-- The banner and not the motd: this is a machine coming up to its login
		-- prompt, which is getty's screen (see bootScreen).
		CeroSec.consolePushAll(console, CeroSecOS.issueLines(state))
	end
	self:pushScreen(luaObject, state, console)
end

-- Whether an account wears the "#" prompt. nil (nobody logged in) is not one.
-- The prompt line, in one place. The user's home comes with it so that the
-- shell can say "~" instead of spelling out /home/admin on a thirty column
-- prompt -- the home is the account's, not a guess from the name.
--
-- The name is OPTIONAL and is worked out here when it is not handed over. It
-- used not to be: the echo path called this with two arguments, the prompt went
-- through tostring(nil), and every line echoed into the console read
-- "root@nil:~# date" while the live prompt and the window title -- the two
-- callers that did pass a name -- read the machine's own. One accessor, read
-- here when nobody read it for us, so a caller cannot forget it again.
function SCeroSecSystem:promptFor(state, console, hostname)
	if hostname == nil and state ~= nil then hostname = CeroSecOS.hostname(state) end
	local home = nil
	local user = CeroSecOS.getUser(state, console.user)
	if user ~= nil and type(user.home) == "string" then home = user.home end
	return CeroSec.consolePrompt(console, hostname, self:isAdmin(state, console.user), home)
end

-- What the machine is called. The file, when there is a filesystem to read it
-- out of; the name its square gives it when there is not, so a window on a
-- machine with a wiped disk still has a title.
function SCeroSecSystem:hostnameOf(luaObject, state)
	if state == nil then return luaObject:hostname() end
	return CeroSecOS.hostname(state)
end

-- The session the core runs a line on, derived from the console -- and written
-- back into it afterwards, because `cd` is a move of the machine's cursor and
-- `su` a change of who the machine is logged in as. Both of them are the
-- machine's state and are saved with it; neither is the window's.
--
-- login is the account at the glass, which is what a borrowed session (sudo's)
-- keeps a note of, and stack is the users `exit` pops back to.
function SCeroSecSystem:sessionOf(console)
	return {
		user = console.user,
		cwd = console.cwd or "/",
		stamp = getTimestampMs(),
		login = console.user,
		stack = console.stack,
		-- Which line this session is on, and how many rlogins out it is. Both are
		-- facts about the SCREEN: the survivor at the keyboard is on the console
		-- and is nought hops out, and a session that came in over the wire carries
		-- its pty's name and the depth of the chain it is part of. `who` prints
		-- the first and rlogin refuses a third hop on the second.
		line = console.line or CeroSecOS.CONSOLE_LINE,
		hops = console.hops or 0,
	}
end

-- The other half. An empty stack is no stack: what goes into gos_cerosec.bin is
-- a field or nothing, never an empty table that grows one every logout.
function SCeroSecSystem:writeSession(console, session)
	console.user = session.user
	console.cwd = session.cwd
	local stack = session.stack
	if type(stack) ~= "table" or #stack == 0 then stack = nil end
	console.stack = stack
end

-- Logging out, and the line it leaves in the machine's own record of who was on
-- it. One place, because a logout happens in two -- an `exit` answered at a
-- question, and an `exit` a job finished on -- and a `last` that only saw one of
-- them would be a `last` that told half the truth.
function SCeroSecSystem:logOut(luaObject, state, console)
	if type(console.user) == "string" then
		CeroSecOS.wtmpAppend(state, "out", console.user,
			console.line or CeroSecOS.CONSOLE_LINE, console.fromHost,
			CeroSecOS.clockOf(self:clockEnv()))
	end
	CeroSec.consoleLogout(console)
end

function SCeroSecSystem:isAdmin(state, name)
	if name == nil then return false end
	local user = CeroSecOS.getUser(state, name)
	return user ~= nil and user.admin and true or false
end

--
-- The editor
--
-- The buffer is the machine's, exactly like the screen: it is opened by a
-- command, it lives in the console, it is saved with the object, and walking
-- away and coming back finds it. What is *not* the machine's is the keyboard on
-- it: one window types, the others watch, because two people typing into one
-- buffer over a network is a merge and this is a 1993 computer.
--

-- Who a window belongs to. The token names a window and dies with it, so it
-- cannot say "the same person came back"; the online id can, and is what
-- vanilla keys per-player server state on (Bobber.lua:26). The player number
-- goes with it because split screen is two players on one connection and
-- nothing here proves the game hands each of them an online id of his own in a
-- game that never talked to a server -- getLocalPlayerByOnlineID scans the
-- local players comparing the field, which says the game expects them to
-- differ, not that they always do.
local function idOf(playerObj)
	return tostring(playerObj:getOnlineID()) .. ":" .. tostring(playerObj:getPlayerNum())
end

-- The same answer, for the machine's own watcher rules: one live window per
-- player per machine is a rule about who "the same player" is, and there is one
-- function that says (SCeroSecObject, the head of the watcher section).
function SCeroSecSystem:watcherIdOf(playerObj)
	if playerObj == nil then return nil end
	return idOf(playerObj)
end

function SCeroSecSystem:hasWatcherWithId(luaObject, id)
	if not luaObject.watchers then return false end
	for _, watcher in pairs(luaObject.watchers) do
		if watcher.player and idOf(watcher.player) == id then return true end
	end
	return false
end

-- Who is holding the keyboard on the open buffer, worked out fresh every time
-- rather than remembered. It is the one who took it, unless he is no longer
-- standing here -- he walked off, he died, he left the game -- and then it is
-- whoever is, by the first of the watcher keys so that every window agrees on
-- the same one. An editor nobody can type in is a machine nobody can use, and
-- deciding this only when a window opens left exactly that: a second player
-- already standing there, watching a buffer whose owner had gone, with no way
-- to type in it and no way to leave it.
--
-- The answer is written back into the console, so the commands that follow
-- agree with the screen that was just drawn.
function SCeroSecSystem:editorOf(luaObject, console)
	local edit = console.edit
	if edit == nil then return nil end
	if edit.by ~= nil and self:hasWatcherWithId(luaObject, edit.by) then return edit.by end

	local best = nil
	if luaObject.watchers then
		for key, watcher in pairs(luaObject.watchers) do
			if watcher.player and (best == nil or key < best.key) then
				best = { key = key, id = idOf(watcher.player) }
			end
		end
	end
	if best == nil then return edit.by end
	edit.by = best.id
	return edit.by
end

function SCeroSecSystem:isEditor(luaObject, console, playerObj)
	if console.edit == nil then return false end
	return self:editorOf(luaObject, console) == idOf(playerObj)
end

-- The editor's half of a screen. The buffer as the machine holds it, the file
-- as it stands on the disk (so a window can say whether the two differ without
-- asking), and whether this window is the one that may type.
-- The session the editor runs under. Not always the console's: `sudo edit`
-- opens the buffer as root and must save as root, so who opened it is kept on
-- the buffer and a save four minutes later is still the write the command was
-- allowed. A buffer with nobody on it -- one opened before sudo existed -- is
-- the session's, as it always was.
function SCeroSecSystem:editSession(console)
	local user = console.user
	local edit = console.edit
	if type(edit) == "table" and type(edit.user) == "string" then user = edit.user end
	return { user = user, cwd = console.cwd or "/", stamp = getTimestampMs() }
end

function SCeroSecSystem:editArgs(luaObject, state, console, playerObj)
	local edit = console.edit
	if edit == nil or state == nil then return nil end
	local disk = ""
	local session = self:editSession(console)
	local node = CeroSecOS.getNode(state, session, edit.path)
	if node ~= nil and node.type == "file" then disk = node.data or "" end
	return {
		path = edit.path,
		text = edit.text or "",
		disk = disk,
		readonly = edit.readonly and true or false,
		message = edit.message,
		-- How many times this buffer has been written. A window that asked to
		-- save and then leave waits for this to move, and not for the message
		-- line to read "Saved": a screen pushed by somebody else's keystroke in
		-- between still carries the message of the *previous* save, and leaving
		-- on that would drop the buffer that had not been written yet.
		saves = edit.saves or 0,
		mine = self:isEditor(luaObject, console, playerObj) and true or false,
	}
end

-- Which machine's windows are looking at a console.
--
-- Its own, normally. A remote session's console lives on the machine whose shell
-- is behind it and is watched from the machine the window is open on, and every
-- answer about it has to carry THAT computer's coordinates -- a terminal believes
-- nothing that does not name the computer it is standing at
-- (CeroSecTerminal:isMine).
function SCeroSecSystem:watchedAt(luaObject, console)
	local at = console.watchAt
	if type(at) ~= "table" then return luaObject end
	local object = self:getLuaObjectAt(at.x, at.y, at.z)
	if object == nil then return luaObject end
	return object
end

-- One screen, as a window has to be told it. The prompt is derived from the
-- console here and nowhere else, so no two windows can disagree about it.
function SCeroSecSystem:screenArgs(luaObject, state, console, token, playerObj)
	local hostname = self:hostnameOf(luaObject, state)
	local at = self:watchedAt(luaObject, console)
	return {
		x = at.x, y = at.y, z = at.z,
		token = token,
		hostname = hostname,
		booted = console.booted and true or false,
		lines = console.lines,
		prompt = self:promptFor(state, console, hostname),
		mode = CeroSec.consoleMode(console),
		mask = CeroSec.consoleMask(console),
		-- Whether the machine is in the middle of something, which is what
		-- Escape needs to know to tell an interrupt from a close. Worked out
		-- here like the prompt and the mask, so no window has to guess which of
		-- the machine's questions it is looking at.
		active = CeroSec.consoleActive(console),
		edit = self:editArgs(luaObject, state, console, playerObj),
		-- Who is logged in, as one short string. The window carries the Up/Down
		-- history of that account and nothing else, so this is how it knows the
		-- history it holds is no longer the right one -- after a login, an exit
		-- or an su -- and asks for the one that is. Sending the history itself
		-- with every screen would put a hundred lines on the wire every time
		-- anybody typed anything.
		user = console.user,
		-- Whether what is on the glass is a session on another machine. The
		-- window needs exactly one thing from it: Escape at an idle remote prompt
		-- closes the session instead of closing the window.
		remote = console.line ~= nil and true or false,
	}
end

-- The account's own history, to one window. Its own reply rather than a field
-- on the screen: it is a hundred lines, it is the same hundred until somebody
-- types, and it is nobody's business but the account whose lines they are.
function SCeroSecSystem:sendHistory(luaObject, state, console, playerObj, token)
	local lines = {}
	if state ~= nil and console.user ~= nil then
		lines = CeroSecOS.historyTail(state, self:sessionOf(console), CeroSecOS.HISTORY_TAIL)
	end
	-- Addressed to one window, so it names the computer that window is standing
	-- at: down an rlogin the history is the far machine's and the coordinates are
	-- still this one's.
	local seat = self:watchedAt(luaObject, console)
	self:reply(playerObj, "history", { x = seat.x, y = seat.y, z = seat.z,
		token = token, lines = lines })
end

-- The screen changed: hand it to every window open on this computer. The
-- requester is one of them and is answered here like the others, by its own
-- token -- there is no private half of a screen anybody is standing in front of.
function SCeroSecSystem:pushScreen(luaObject, state, console, exceptKey)
	-- A detached session's console is a sheet of paper and not a glass: it was
	-- opened by an rsh for a job with no terminal, nobody is looking at it, and
	-- what it collects is delivered when the session ends (SCeroSecNet, deliver).
	-- Guarded HERE rather than at each of the four callers, because the far
	-- machine's own scheduler pushes the screens its jobs wrote on and knows
	-- nothing about whose session they are.
	if console.noTty then return end
	local at = self:watchedAt(luaObject, console)
	if not at.watchers then return end
	for key, watcher in pairs(at.watchers) do
		if watcher.player and key ~= exceptKey then
			self:reply(watcher.player, "screen",
				self:screenArgs(luaObject, state, console, watcher.token, watcher.player))
		end
	end
end

-- The first screenful after a power-on: the BIOS lines, and the motd when there
-- is a system to greet from. Answers whether it did anything -- a machine
-- already booted is not booted twice, which is what keeps the second player to
-- open a computer from watching a second boot.
function SCeroSecSystem:bootScreen(console, state)
	if console.booted then return false end
	console.booted = true
	-- The card and its address, which the firmware can only announce once the
	-- server has worked out which PREMISES the computer stands in -- a shop inside a
	-- mall, or a whole house.
	-- And the telephone line under it, which is the same fact read a second way:
	-- both come off the machine's own record of the premises it stands on. The line
	-- carries the premises's NAME behind the number when the map gave it one and it
	-- fits the screen (CeroSecOS.phoneLine), because a survivor in a mall with thirty
	-- lines in it needs to know which one he is sitting at.
	-- And the TNC's banner under the modem, which is the one of the three that is
	-- read off the DISK: an address and a number are facts about where the machine
	-- stands, and a callsign is a file somebody may have written (see
	-- CeroSec.BOOT_CALL).
	local addr, tel, call = nil, nil, nil
	if state ~= nil then
		addr = CeroSecOS.address(state)
		tel = CeroSecOS.phoneLine(state)
		call = CeroSecOS.callsignOf(state)
	end
	CeroSec.consolePushAll(console, CeroSec.bootLines(addr, tel, call))
	-- And /etc/issue under the firmware's lines, which is where getty printed its
	-- banner: 4.4BSD's getty prints `im` (or the `if` issue file) and THEN the
	-- login prompt. The motd used to be here, and it was the same greeting twice
	-- on one screen -- /etc/motd is login's and is printed once the password is
	-- right (CeroSecOS.loginLines).
	if state ~= nil then CeroSec.consolePushAll(console, CeroSecOS.issueLines(state)) end
	return true
end

--
-- Off, and off and on again
--
-- `shutdown` and `reboot` are the physical button typed instead of pressed, so
-- they go through the very same turnOff/turnOn -- the sprite, the sound, the
-- console thrown away -- and not through a second, quieter path beside it.
--
-- The one difference is the windows, and the DARK between the two calls. A
-- reboot on a real machine is the power going and coming back, so it is off in
-- the meantime: the unlit sprite on the tile, no glow on the wall, no screen to
-- read. It used to be one call after the other in the same breath, which left
-- the sprite lit and the boot typing itself out inside a window that had never
-- shut -- a machine that never went down.
--
-- So it goes down properly. turnOff does what it does for a switch at the case,
-- except that the watchers are held aside across it so its own eviction says
-- nothing: what a window at a rebooting machine is told is `reboot` and not
-- `off`, which is the one word that tells the client this one is coming back.
-- Who was at the glass is remembered beside the interval, and CeroSec.REBOOT_DARK_MS
-- later the scheduler brings the machine up through turnOn -- the same road a
-- hand at the switch takes, and therefore the same power question.
--

function SCeroSecSystem:reboot(luaObject)
	local watchers = luaObject.watchers
	luaObject.watchers = nil
	local wentDown = luaObject:turnOff()
	luaObject.watchers = watchers
	-- A machine that was not on has nothing to reboot, and nothing was said to
	-- anybody: the windows are left exactly as they were.
	if not wentDown then return end

	-- Who to hand the window back to. The player and not the watcher key: the
	-- key holds the token of a window that is about to shut, and the window that
	-- comes back is a new one with a token of its own.
	local waiting = {}
	if watchers then
		for _, watcher in pairs(watchers) do
			if watcher.player then waiting[#waiting + 1] = watcher.player end
		end
	end
	self:evictWatchers(luaObject, "reboot")

	CeroSecJobs.scheduleReboot(luaObject, getTimestampMs() + CeroSec.REBOOT_DARK_MS, waiting)
end

-- The other end of the dark interval, called by the scheduler's own pass
-- (CeroSecJobs.checkReboot).
--
-- turnOn and not a quieter path beside it: the sprite, the sound, the fresh
-- console and @reboot are all its, and so is the power question -- a room that
-- went dark in those three seconds leaves the machine off, exactly as an outage
-- leaves a real one off, and the survivor switches it on by hand later.
function SCeroSecSystem:resumeReboot(luaObject, waiting)
	if not luaObject:turnOn() then return end
	local console = luaObject:consoleState()
	if not console then return end
	local state = self:biosState(luaObject)
	self:bootScreen(console, state)
	-- A machine that went down broken comes back broken, and says so.
	if state == nil and not self:atBios(console) then
		self:sayNoSystem(luaObject, console)
	end
	self:reopenFor(luaObject, state, console, waiting)
end

-- The windows that were at the glass when it went dark, handed back.
--
-- Not pushScreen: that answers a window that is open, and every one of these
-- was told to shut when the machine went down. So
-- what goes out is the first screenful of a window that does not exist yet, and
-- the client builds the box around it through the very path the walk ends in --
-- no second window class, and no second walk.
--
-- Only to a player who is still standing at the machine, and only while the
-- machine is in the world at all. One who wandered off in those three seconds
-- gets nothing and uses the computer by hand, which is the same answer the power
-- sweep gives a window whose player left.
function SCeroSecSystem:reopenFor(luaObject, state, console, waiting)
	if type(waiting) ~= "table" then return end
	if not luaObject:isLoaded() then return end
	for i = 1, #waiting do
		local playerObj = waiting[i]
		if playerObj and not playerObj:isDead()
				and isAdjacent(playerObj, luaObject.x, luaObject.y, luaObject.z) then
			local token = newServerToken(playerObj)
			luaObject:addWatcher(watcherKeyOf(playerObj, token), playerObj, token)
			local args = self:screenArgs(luaObject, state, console, token, playerObj)
			-- The BIOS types itself out for him, because he is watching the
			-- machine he just rebooted come up.
			args.animate = true
			-- Which of the local players on this connection it is for. Every other
			-- answer reaches a window that already knows; this one has to say, because
			-- the window is the thing being asked for.
			args.player = playerObj:getPlayerNum()
			self:reply(playerObj, "reopened", args)
			self:sendHistory(luaObject, state, console, playerObj, token)
		end
	end
end

-- The two orders that end a screen instead of changing it. Run after the screen
-- carrying the line that was typed has gone out, so nothing is swallowed by the
-- machine going down: what follows is either "the window is over" or a whole
-- new boot.
function SCeroSecSystem:applyPower(luaObject, control)
	if control == "shutdown" then
		luaObject:turnOff()
		return true
	end
	if control == "reboot" then
		self:reboot(luaObject)
		return true
	end
	return false
end

-- What the core ordered, beyond the lines it printed. Shared by a command and
-- by the answer to one, so a chain of prompts and a command that starts one are
-- the same thing to the console.
function SCeroSecSystem:applyOrder(console, control, data, playerObj)
	if control == "prompt" and type(data) == "table" then
		console.prompt = {
			text = tostring(data.text or ""),
			mask = data.mask and true or false,
			cont = data.cont,
		}
	elseif control == "edit" and type(data) == "table" then
		console.edit = {
			path = tostring(data.path or "/"),
			text = data.text or "",
			readonly = data.readonly and true or false,
			by = idOf(playerObj),
		}
		-- Who the command was allowed to open it as. It comes from the core,
		-- which took it from the session it ran the command on, so it is only
		-- ever the console's own user or the root a sudo already paid for.
		if type(data.user) == "string" then console.edit.user = data.user end
		-- And whether what is being edited is a CRONTAB, because a crontab is
		-- judged before it is installed: crontab(1) refuses a file with a bad
		-- line in it rather than leaving the daemon to find out at four in the
		-- morning.
		if data.crontab then console.edit.crontab = true end
	end
end

-- The order that makes a job. Kept here rather than in applyOrder because a
-- job belongs to the MACHINE and not to the console: applyOrder is handed a
-- screen, this one is handed the computer the script will run on.
--
-- A machine with no room says so on the screen and the line is over; there is
-- no queue, because a queue is a promise this machine cannot keep across a
-- reload.
function SCeroSecSystem:startJob(luaObject, console, data)
	if type(data) ~= "table" or type(data.prog) ~= "table" then return nil end
	-- The shell that asked is this console's, so what the job starts with is a
	-- copy of that shell's variables: it is a subshell of the line that was typed.
	if data.vars == nil then data.vars = CeroSecOS.copyVars(console.shvars) end
	-- With the marks beside them: a subshell inherits which names are in the
	-- environment, or a script started behind an `&` would export nothing.
	if data.exported == nil then data.exported = CeroSecOS.copyExported(console.shexport) end
	local job, reason = CeroSecJobs.start(self, luaObject, console, data, data.bg and true or false)
	if job == nil then
		CeroSec.consolePush(console, "sh: " .. tostring(reason))
	end
	return job
end

-- A buffer a client sent. Nothing is believed on its word: it is text, it is
-- printable, and it fits the file ceiling -- the rules the FILESYSTEM has,
-- checked again here because the terminal is the client.
--
-- The sixty column rule is deliberately not one of them. That one belongs to
-- the screen and not to the disk: writeFile has never had it, so the shell can
-- put a wider row in a file, and a server that refused to hold such a buffer
-- would make the file impossible to open and repair. The editor refuses the
-- 61st character a player types; it does not refuse the buffer he is fixing.
-- nil plus the line to show when it is not.
local function bufferOf(text)
	if type(text) ~= "string" then return nil, "Cannot edit: not text" end
	if #text > CeroSec.EDIT_MAX_BYTES then
		return nil, "Buffer full: " .. CeroSec.EDIT_MAX_BYTES .. " bytes"
	end
	if CeroSecOS.hasControlBytes(text) then return nil, "Cannot edit: invalid characters" end
	return text, nil
end

Commands.toggle = function(self, playerObj, x, y, z)
	if not isAdjacent(playerObj, x, y, z) then return end

	local luaObject = self:getLuaObjectAt(x, y, z)
	if not luaObject then
		local isoObject = self:getIsoObjectAt(x, y, z)
		if not isoObject then return end
		self:loadIsoObject(isoObject)
		luaObject = self:getLuaObjectAt(x, y, z)
		if not luaObject then return end
	end
	luaObject:toggle()
end

--
-- The floppy drive
--
-- The slot is mechanical: a disk goes in and comes out of a computer that is
-- switched off exactly as it does out of one that is lit, which is why these two
-- do not go through computerFor -- that one is about a terminal, and it answers
-- "off" by telling the window to shut. What they ask for is the two things any
-- interaction asks for: the machine is there, and the player is standing at it.
--
-- Nothing a client sends about the DISK is believed. What travels is the id of an
-- item in the sender's own inventory; the server looks that item up itself, reads
-- its modData itself, and refuses one that is not a disk this mod declares or
-- whose contents will not pass the engine's own gate. So a forged packet can
-- insert nothing that a machine could not already be running on.
--
-- The computer a drive command names, with no terminal and no power required.
-- nil, silently: the client's own menu greys out every case this can refuse, so
-- reaching here with a refusal means a packet nobody typed.
function SCeroSecSystem:driveFor(playerObj, x, y, z)
	if not isAdjacent(playerObj, x, y, z) then return nil end
	local luaObject = self:getLuaObjectAt(x, y, z)
	if not luaObject then
		local isoObject = self:getIsoObjectAt(x, y, z)
		if not isoObject then return nil end
		self:loadIsoObject(isoObject)
		luaObject = self:getLuaObjectAt(x, y, z)
	end
	return luaObject
end

-- A DRIVE GESTURE THAT DID NOTHING, SAID SO.
--
-- Every refusal below used to be a bare `return`, and that is the defect this
-- answers: the diagnostics disk was refused at the gate for a key the ENGINE puts
-- on the item (ownKeysOf in CeroSecOSDisk), the timed action played, the disk
-- stayed in the bag, and the only trace anywhere was a warn line that prints to
-- the console solely under CeroSec.DEBUG. Six tries, no sentence. A silent return
-- on a gesture a player made is a mod that looks broken, which is worse than a
-- mod that says no.
--
-- The wire carries a CODE and never a translated sentence: the words belong to the
-- client, which has getText and knows the survivor's language (CeroSecTerminal's
-- driveNotice). `detail` is the machine's own reason where there is one, in the
-- machine's own English, the way every other line this machine prints is.
--
-- args.player is which of the local players on the connection asked, the same
-- field `reopened` carries and for the same reason: there is no window to route
-- this by, and the halo goes over ONE survivor's head.
local function driveNotice(system, playerObj, x, y, z, why, detail)
	system:reply(playerObj, "drive", { x = x, y = y, z = z,
		player = playerObj:getPlayerNum(), why = why, detail = detail })
end

Commands.insertfloppy = function(self, playerObj, x, y, z, token, args)
	local luaObject = self:driveFor(playerObj, x, y, z)
	if not luaObject then
		driveNotice(self, playerObj, x, y, z, "gone")
		return
	end
	if luaObject:hasDisk() then
		driveNotice(self, playerObj, x, y, z, "occupied")
		return
	end
	-- The one refusal that stays silent, and the only one that is not a gesture: the
	-- client always sends the id of the disk it offered, so a packet without one is
	-- a packet nobody typed and there is no survivor waiting for an answer to it.
	if type(args) ~= "table" or type(args.item) ~= "number" then return end

	-- His own inventory and nobody else's, by the id he sent: the same lookup
	-- vanilla's own server commands make (ClientCommands.lua:377, :1181), in the
	-- recursive form, because a survivor keeps his disks in a bag like everything
	-- else.
	local item = playerObj:getInventory():getItemWithIDRecursiv(math.floor(args.item))
	if not item or not CeroSec.isFloppyType(item:getFullType()) then
		-- One sentence for the two of them, because they are the same thing from
		-- where the survivor stands: what he offered the drive is not a disk in his
		-- hands any more. He dropped it, somebody took it, or the id names something
		-- else entirely.
		driveNotice(self, playerObj, x, y, z, "nodisk")
		return
	end

	-- What is written on it, copied out of the item into a plain table of our own
	-- and put through the engine's gate before it is anywhere near the machine.
	-- A disk that fails is left in his hands rather than eaten by the drive.
	-- A blank disk out of a box by default: every item in this game has a modData
	-- table, empty or full of somebody else's business, and nothing written in it
	-- is a disk nobody has ever formatted rather than a disk to refuse.
	local disk = CeroSecOS.newFloppy()
	if item:hasModData() and CeroSecOS.dataHasDisk(item:getModData()) then
		local read, reason = CeroSecOS.diskFromData(item:getModData())
		if read == nil then
			CeroSec.log(CeroSec.LOG_WARN, "refused a disk at " .. x .. "," .. y .. "," .. z
				.. ": " .. tostring(reason))
			-- And to the survivor, not only to the log: the log is behind a debug flag
			-- and a debug window, and he is standing at the machine holding the disk.
			driveNotice(self, playerObj, x, y, z, "refused", tostring(reason))
			return
		end
		disk = read
	end

	-- The sticker, read off the ITEM and not off its modData, and written over
	-- whatever the modData said.
	--
	-- The item is where the label really lives (CeroSecFloppyMenu): setName plus
	-- setCustomName plus syncItemFields is what writes it, and syncItemFields is the
	-- engine's own sync -- there is no per-item modData transmit on InventoryItem in
	-- 42.20.4 to match it (javap zombie.inventory.InventoryItem: hasModData,
	-- getModData, copyModData, and nothing that sends one). So the name is the one
	-- reading of the label that is true on both sides of a multiplayer game, and a
	-- modData label that disagrees with it is a stale copy and not a second opinion.
	--
	-- No custom name is NO sticker, and that is why this clears rather than merely
	-- overwrites: a disk somebody erased the label from must come out of the drive
	-- with it still erased.
	--
	-- Held to CeroSecOS.labelOk on the way in, which is tighter than the slot's own
	-- gate: this is a client's string and the two commands that print it are lines
	-- on a screen.
	disk.label = nil
	if item:isCustomName() then
		local written = item:getName()
		if CeroSecOS.labelOk(written) then disk.label = written end
	end

	-- AND THE ONE DISK WHOSE STORY NEEDED A PLACE. A BBS list off a shelf carries a
	-- stub where its numbers go, because loot has no location and there was no
	-- exchange to print: this is the first moment there is a square to ask, so it is
	-- where the printing happens (CeroSecNet.fillLateDisk, and the sixth note over
	-- CeroSecContent.DISKS for the whole of why).
	--
	-- AFTER the label is read and BEFORE the disk goes in the drive: the sticker is
	-- what says which catalogue entry this is, and a disk already in a machine is a
	-- disk the survivor is reading. It is done to OUR copy -- the validated private
	-- one above -- and what is on the copy is what the drive takes and what an eject
	-- writes back onto the item, so the printing outlives the insertion by the same
	-- path everything else on the disk does. Nothing happens for every other disk in
	-- the county and nothing happens twice for this one.
	CeroSecNet.fillLateDisk(disk, x, y, nil)

	local done, refusal = luaObject:insertDisk(disk, item:getFullType())
	if not done then
		-- The drive's own two: something else got in between (occupied), or the
		-- machine's state will not pass its gate at all (broken), which is a computer
		-- the firmware has to mend and not a disk to keep trying.
		driveNotice(self, playerObj, x, y, z,
			refusal == "occupied" and "occupied" or "broken")
		return
	end

	-- Out of the container it was really in, which is the bag and not the pockets
	-- when that is where he was keeping it.
	local from = item:getContainer() or playerObj:getInventory()
	from:Remove(item)
	if isServer() then sendRemoveItemFromContainer(from, item) end
end

Commands.ejectfloppy = function(self, playerObj, x, y, z, token, args)
	local luaObject = self:driveFor(playerObj, x, y, z)
	if not luaObject then return end

	-- Everything that can refuse is asked BEFORE the disk leaves the drive, so a
	-- refusal is a gesture that did nothing rather than an eject that got half way:
	-- the disk is still in, the mount is still up, and no sound was played for it.
	local disk, fullType = luaObject:diskToEject()
	if not disk then
		-- A drive that keeps a disk says so on the machine's own glass, which is
		-- where this machine says everything. Only that one refusal: "there is no
		-- disk in it" is a gesture the menu should not have offered, and a machine
		-- whose state the validator has refused has nothing to write a line on.
		if fullType ~= "empty" and fullType ~= "broken" then
			local console = luaObject:consoleState()
			if console ~= nil then
				CeroSec.consolePush(console, CeroSecOS.fdKeptLine(fullType))
				local state = luaObject:osState()
				if state ~= nil then self:pushScreen(luaObject, state, console) end
			end
		end
		return
	end

	-- Into his hands, in the shell it went in as. The modData is written before
	-- the item is announced to the clients, or what they would be handed is a
	-- blank disk with the right colour on it.
	local inv = playerObj:getInventory()
	-- And the creation hook stands down for it. AddItem instances a REAL floppy, so
	-- the hook rolls a disk and a name onto this shell before the disk that is
	-- actually in the drive is written over it -- see CeroSecContent.ejecting.
	CeroSecContent.ejecting = true
	local item = inv:AddItem(fullType)
	CeroSecContent.ejecting = false
	-- Nowhere to put it: the survivor is carrying too much, which is a thing he can
	-- fix. Nothing has happened to the machine.
	if not item then return end
	if not CeroSecOS.writeDiskTo(item:getModData(), disk) then
		inv:Remove(item)
		if isServer() then sendRemoveItemFromContainer(inv, item) end
		CeroSec.log(CeroSec.LOG_ERROR,
			"the disk would not go onto the item at " .. x .. "," .. y .. "," .. z)
		return
	end

	-- And the sticker back onto the shell. This is not belt-and-braces: an insert
	-- DESTROYS the item and an eject makes a NEW one (inv:AddItem above), so without
	-- these three calls a disk labelled BACKUP would come out of the drive called
	-- "3.5 inch Floppy Disk" and the survivor's own handwriting would be gone. The
	-- three calls are vanilla's Rename Bag's, in its order
	-- (ISInventoryPaneContextMenu.lua:2753-2755).
	--
	-- writeDiskTo above has already put the label in the item's modData -- `label` is
	-- one of the three keys a disk owns there (CeroSecOS.DISK_KEYS) -- so the record
	-- and the name come out of the drive saying the same thing.
	if CeroSecOS.labelOk(disk.label) then
		item:setName(disk.label)
		item:setCustomName(true)
		item:syncItemFields()
		CeroSecContent.markByLabel(item, disk.label)
	else
		-- AND THIS BRANCH IS NOT BELT AND BRACES. inv:AddItem above makes a REAL
		-- floppy, so the creation hook ran on it and rolled it a disk of its own
		-- (CeroSecContent.onCreateFloppy) -- writeDiskTo has just overwritten the
		-- three keys that roll wrote, but the LOOK it put on the shell is the
		-- engine's own modData and is not a key a disk owns. A disk with nothing
		-- written on it that came out of the drive wearing a printed sticker would be
		-- the roll showing through, so the marks come off with the label -- and so
		-- does the NAME, which is the one the hook is likeliest to have left. The
		-- flag above is what stops it being written in the first place; this is the
		-- belt, because a flag that is ever missed must not be the only thing
		-- between a survivor and a blank disk called CeroSec UTILITIES 1.0.
		CeroSecContent.markLabel(item, nil)
		CeroSecContent.unname(item)
	end

	-- And only now does it come out. If it somehow does not, the item goes with it:
	-- the player holding a disk the machine still has is a duplication, which is
	-- the one failure worse than the eject not happening.
	if not luaObject:ejectDisk() then
		inv:Remove(item)
		if isServer() then sendRemoveItemFromContainer(inv, item) end
		return
	end
	if isServer() then sendAddItemToContainer(inv, item) end
end

--
-- The hardware modules
--
-- Two commands, and they are about a DOOR and not about a computer: the object
-- is named by the square it stands on and its index in that square's object
-- list, which is how vanilla's own client commands name one
-- (ISWorldObjectContextMenu.lua:3076 sends x, y, z and
-- isoObject:getObjectIndex()).
--
-- Nothing a client sends is believed. The server looks the object up itself,
-- asks the same three questions the menu asked -- does this module fit this
-- fixture, does this survivor know enough, is he carrying the module and a
-- screwdriver -- and asks the fourth the menu cannot: is he standing there. A
-- forged packet wires nothing a survivor could not have wired by hand.
--
-- Silently, like the drive commands above: the client's own menu greys out every
-- case this can refuse, so a refusal here is a packet nobody typed.
--
-- The item goes out of his hands BEFORE the module goes on the door, and comes
-- back into them BEFORE it comes off. Same rule the floppy drive runs on
-- (Commands.ejectfloppy): a survivor holding the module that is also on the door
-- is a duplication, which is the one failure worse than the gesture not
-- happening.

-- The fixture a module command names, or nil for every way a client could be
-- wrong about it: not standing there, a chunk that is not loaded, an index off
-- the end of the list, and an object no module of ours goes on.
function SCeroSecSystem:fixtureFor(playerObj, x, y, z, index)
	if not isAdjacent(playerObj, x, y, z) then return nil end
	if getCell == nil then return nil end
	local cell = getCell()
	if cell == nil then return nil end
	local square = cell:getGridSquare(x, y, z)
	if square == nil then return nil end
	local objects = square:getObjects()
	if objects == nil then return nil end
	if index < 0 or index >= objects:size() then return nil end
	local object = objects:get(index)
	if not CeroSecModules.isFittable(object) then return nil end
	return object
end

-- What both commands ask before either does anything: the module exists, it
-- fits, the survivor knows the trade and has the tool. Answers the module and
-- the object, or nil.
function SCeroSecSystem:moduleJob(playerObj, x, y, z, args)
	if type(args) ~= "table" then return nil end
	if type(args.module) ~= "string" or type(args.index) ~= "number" then return nil end
	local module = CeroSecModules.byId(args.module)
	if module == nil then return nil end

	local object = self:fixtureFor(playerObj, x, y, z, math.floor(args.index))
	if object == nil then return nil end
	if not CeroSecModules.fitsOn(object, module.id) then return nil end

	-- What he knows. Perks.Electricity is the game's own table and the level is
	-- the module's (CeroSecModules.LIST).
	if playerObj:getPerkLevel(Perks.Electricity) < module.skill then return nil end

	local inv = playerObj:getInventory()
	if inv == nil then return nil end
	-- The tool, in his bag like anything else. It is never consumed and never
	-- degraded here: vanilla degrades a screwdriver through a recipe's own
	-- flags[MayDegrade...] and there is no such thing on a timed action.
	if inv:getFirstTypeRecurse(CeroSecModules.TOOL) == nil then return nil end

	return module, object, inv
end

Commands.installmodule = function(self, playerObj, x, y, z, token, args)
	local module, object, inv = self:moduleJob(playerObj, x, y, z, args)
	if module == nil then return end

	-- One of each, and no more: a second contact on the same door buys nothing
	-- and would eat the item for it.
	local fitted = CeroSecModules.installedOn(object)
	if fitted[module.id] then return end

	local item = inv:getFirstTypeRecurse(module.item)
	if item == nil then return end

	local from = item:getContainer() or inv
	from:Remove(item)
	if isServer() then sendRemoveItemFromContainer(from, item) end

	if not CeroSecModules.setOn(object, module.id, true) then
		-- The object would not take it. Give the module back rather than eat it:
		-- nothing happened to the door and nothing should have happened to him.
		local back = inv:AddItem(module.item)
		if back ~= nil and isServer() then sendAddItemToContainer(inv, back) end
		CeroSec.log("the module would not go onto the fixture at " .. x .. "," .. y .. "," .. z)
		return
	end
	CeroSec.log(module.id .. " fitted at " .. x .. "," .. y .. "," .. z)
end

Commands.uninstallmodule = function(self, playerObj, x, y, z, token, args)
	local module, object, inv = self:moduleJob(playerObj, x, y, z, args)
	if module == nil then return end

	local fitted = CeroSecModules.installedOn(object)
	if not fitted[module.id] then return end

	-- Into his hands first, whole: a module that comes off is a module, not a
	-- pile of scrap, so it is the item it went on as.
	local item = inv:AddItem(module.item)
	if item == nil then return end

	if not CeroSecModules.setOn(object, module.id, false) then
		inv:Remove(item)
		if isServer() then sendRemoveItemFromContainer(inv, item) end
		return
	end
	if isServer() then sendAddItemToContainer(inv, item) end
	CeroSec.log(module.id .. " taken off at " .. x .. "," .. y .. "," .. z)
end

--
-- HOW OFTEN ONE PLAYER MAY OPEN A WINDOW
--
-- `open` is the dearest packet in this mod and the only one that is dear on the
-- way OUT as well: it identifies the machine, decides the boot, builds the screen,
-- and then ships the console's history lines to the client (sendHistory). Bounding
-- the watcher table stopped a flood costing the server memory; it did not stop the
-- flood itself. Measured on the 300-machine rig, five thousand opens from one
-- client: 9.4 seconds of server time before the validator was memoised
-- (SCeroSecObject:osState), 0.41 after -- better, and still not something one
-- client gets to ask for.
--
-- FOUR A SECOND, IN REAL TIME, and the packets past that are dropped with no
-- answer at all. Four because a window is a box a survivor opens with the mouse:
-- the client shuts its own previous terminal before it sends (CeroSecTerminal.open),
-- so a player who walks up to a computer sends one, and a reboot's reopen is the
-- server's own doing and comes through no packet. Nothing legitimate sends a second
-- one in the same quarter second.
--
-- NO REPLY, so a flooder learns nothing: an answer -- even a refusal -- is a
-- confirmation that the packet arrived and a second thing for the server to send.
-- It goes in CeroSec.log instead, once per second per player, which is what a
-- server owner reads.
--
-- REAL TIME AND NOT GAME TIME. getTimestampMs() is the wall clock in
-- milliseconds (zombie.Lua.LuaManager$GlobalObject.getTimestampMs, a long), and
-- vanilla throttles a client command with it on the server in exactly this shape:
-- forageServer.onRequestZone keeps lastReqMs per player and RETURNS without a word
-- when the gap is under minReqMs = 250 (media/lua/server/Foraging/
-- forageServer.lua:295-308). getGameTime() would be the wrong clock twice over --
-- it runs at the world's speed, which a sandbox option sets, and it stops when
-- nobody is on the server.
--
-- AND THE BOOK IS BOUNDED. Keyed on the online id, which is not ours, so entries
-- older than the window are dropped on the way in -- the size is the number of ids
-- that have opened a window in the last few seconds, which is the number of people
-- playing. There is no vanilla event for a player LEAVING: OnDisconnect exists
-- (LuaEventManager's event list on 42.20.4) but vanilla only ever adds to it on the
-- client, for its own connection failing (ConnectToServer.lua:386,
-- ISMPEditAccount.lua:480), and there is no OnPlayerDisconnect at all. Vanilla's
-- own answer to the same problem is to poll getOnlinePlayers() on a timer and drop
-- what is not there (forageServer.relevanceTick:455-493); age alone is cheaper and
-- is enough, because an entry is worth two numbers and expires on its own.
--
SCeroSecSystem.OPEN_PER_SECOND = 4

-- One real second, which is the window the cap is counted over.
local OPEN_WINDOW_MS = 1000
-- And how long an entry is kept for a player who has stopped asking. Four windows:
-- long enough that the walk below is not the common case, short enough that a
-- player who logs off is out of the book before the minute is.
local OPEN_BOOK_MS = 4 * OPEN_WINDOW_MS

-- May this player open a window right now? Counted here rather than in Commands.open
-- so the number and the rule live together, the way the cpu ceiling does.
function SCeroSecSystem:mayOpen(playerObj)
	-- A short (IsoPlayer.getOnlineID, javap'd on 42.20.4), so it is a whole number
	-- small enough to be a table key exactly and no string has to be built per
	-- packet -- which is the point of a gate a flood goes through.
	local id = playerObj:getOnlineID()
	if type(self.openBook) ~= "table" then self.openBook = {} end
	local book = self.openBook
	local now = getTimestampMs()

	local entry = book[id]
	-- A window of its own, whenever the last one is over -- or whenever the clock
	-- has gone backwards, which is a server that came back up under a book that
	-- cannot be about this session: a negative gap read as "not a second yet" would
	-- throttle a player for one window for no reason he could ever see.
	if entry == nil or now - entry.at >= OPEN_WINDOW_MS or now < entry.at then
		-- On the way in, because this is the one moment the book grows: everything
		-- whose own window is long over, whoever it belongs to.
		for other, old in pairs(book) do
			if now - old.at >= OPEN_BOOK_MS or now < old.at then book[other] = nil end
		end
		entry = { at = now, n = 0 }
		book[id] = entry
	end

	entry.n = entry.n + 1
	if entry.n <= SCeroSecSystem.OPEN_PER_SECOND then return true end
	-- Once per window and not once per packet: five thousand dropped packets are
	-- one line, or the log a server owner reads is the flood.
	if not entry.said then
		entry.said = true
		CeroSec.log(CeroSec.LOG_WARN,
			"dropping window openings from player " .. tostring(id) .. ": more than "
				.. SCeroSecSystem.OPEN_PER_SECOND .. " a second")
	end
	return false
end

-- WHAT A LOGIN DOES TO A CONSOLE, in one place.
--
-- Everything that happens once CeroSecOS.login has said yes: who the glass is, where
-- he is standing, the shell he is handed, when he sat down and what /var/log/wtmp is
-- told about it. It is a method and not eleven lines inside Commands.input because a
-- second caller wants exactly these gestures and no others -- the debug window's
-- "Login as root", which is the one path allowed to skip the PASSWORD and is not
-- allowed to skip anything else (docs/DEBUG.md). Two copies of this would be two
-- answers to "what is a session", and the one that drifted would be the one nobody
-- types at.
--
-- The session is CeroSecOS.login's own return: { user, cwd }.
function SCeroSecSystem:beginSession(state, console, session)
	console.user = session.user
	console.cwd = session.cwd
	-- A login is a session that has just begun: nobody has su'd yet,
	-- and a stack left behind by anything is not this one's.
	console.stack = nil
	-- A login is a fresh shell: nothing the last account set at this
	-- glass is still set, exactly as nothing of his session is. What it
	-- does start with is what a login shell has always set -- PATH, so a
	-- bare name is looked up in /bin, and HOME.
	console.shvars = CeroSecOS.loginVars(
		(CeroSecOS.getUser(state, session.user) or {}).home)
	-- And which of them a program it runs is handed: a login exports what
	-- it sets, so a script finds PATH and HOME without an export line.
	console.shexport = CeroSecOS.loginExported()
	-- And no functions: a function belongs to the shell it was told about.
	console.shfuncs = {}
	console.status = nil
	-- When, and on which line: what `who` prints and what `last` reads
	-- back out of /var/log/wtmp. The console's own line is "console" --
	-- the survivor is at the keyboard -- and a pty's is its own name,
	-- with the machine it came from beside it.
	local now = CeroSecOS.clockOf(self:clockEnv())
	console.loginAt = now or 0
	-- What login says, worked out BEFORE the arrival is written down: the
	-- "Last login" line is the login before this one, and a record already in
	-- the file would make it this one (CeroSecOS.lastLoginRecord).
	local greeting = CeroSecOS.loginLines(state, session.user)
	CeroSecOS.wtmpAppend(state, "in", session.user,
		console.line or CeroSecOS.CONSOLE_LINE, console.fromHost, now)
	CeroSec.consolePushAll(console, greeting)
end

Commands.open = function(self, playerObj, x, y, z, token)
	-- Before the machine is even looked up: what this refuses is the PACKET, and a
	-- flooder must not get a square's worth of work out of one either.
	if not self:mayOpen(playerObj) then return end

	local luaObject, console = self:biosConsoleFor(playerObj, x, y, z, token)
	if not luaObject then return end

	local key = watcherKeyOf(playerObj, token)
	luaObject:addWatcher(key, playerObj, token)

	-- Which building the computer stands in, and therefore its address. Asked
	-- here and when the machine is switched on, because those are the two moments
	-- the chunk is certainly loaded -- and written into the machine's own state,
	-- so that every other question about the wire can be answered without it.
	CeroSecNet.identify(self, luaObject, luaObject:osState())

	-- What the machine has on its disk, decided before a single line is put on
	-- the screen: the boot either ends at a login prompt or it ends at the
	-- BIOS' question, and which of the two is not the window's business.
	local state = self:biosState(luaObject)

	-- The BIOS belongs to the power-on, not to the window: the first player to
	-- open a machine that has just been switched on watches it type itself out,
	-- and it is then on the screen for whoever opens it next.
	local animate = self:bootScreen(console, state)

	-- Asked once. A machine already sitting on the question, or on the refusal
	-- that answered it, is left exactly as the last player left it.
	if state == nil and not self:atBios(console) then
		self:sayNoSystem(luaObject, console)
	end

	-- A machine with a session open on it shows the SESSION, whoever opens the
	-- window: the screen belongs to the machine, so a second survivor walking up
	-- to it -- or the first one coming back -- reads the same glass.
	local shownObj, shownState, shown = luaObject, state, console
	if state ~= nil then
		local far, farState, farConsole = self:followChain(luaObject, state, console)
		if far ~= nil then shownObj, shownState, shown = far, farState, farConsole end
	end

	local args = self:screenArgs(shownObj, shownState, shown, token, playerObj)
	args.animate = animate
	self:reply(playerObj, "opened", args)
	self:sendHistory(shownObj, shownState, shown, playerObj, token)
	-- Somebody else may have been looking at the blank screen when it booted.
	if animate then self:pushScreen(shownObj, shownState, shown, key) end
end

-- The answer to whatever is being asked. login, password and the line a command
-- asked for are one path: the console says which of them this is, and a window
-- that typed at a prompt that has since changed gets the screen back and
-- nothing else.
Commands.input = function(self, playerObj, x, y, z, token, args)
	local host, hostConsole = self:biosConsoleFor(playerObj, x, y, z, token)
	if not host then return end

	local text = args.text
	if type(text) ~= "string" then text = "" end

	-- The BIOS' question is answered before anything asks for a filesystem:
	-- there may not be one, and that is what is being asked about. It is always
	-- the computer the window is standing at -- a machine with no operating
	-- system has nothing to rlogin out of.
	if self:atBios(hostConsole) then
		self:answerBios(host, hostConsole, playerObj, token, text)
		return
	end

	-- And then wherever the glass is really typing: this machine, or a session
	-- on another one.
	local luaObject, state, console = self:targetFor(playerObj, x, y, z, token)
	if not luaObject then return end

	-- What the core ordered, if anything did. Declared out here because the
	-- power orders are carried out after the screen has gone out, and the
	-- branch that can produce one ends long before that.
	local order = nil

	local profile = false

	local waiting = CeroSec.consoleWaiting(console)
	if waiting == "login" then
		-- The name is echoed and remembered; nothing is judged until the
		-- password is in, so an unknown name looks exactly like a known one.
		if text ~= "" then
			CeroSec.consolePush(console, "login: " .. text)
			console.pending = text
		end
	elseif waiting == "password" then
		local name = console.pending
		console.pending = nil
		CeroSec.consolePush(console, CeroSec.maskedLine("password: ", text))
		local session, reason = CeroSecOS.login(state, name, text)
		if session then
			self:beginSession(state, console, session)
			-- ~/.profile, after the greeting and before the first prompt, the
			-- way sh has run it since the seventh edition. It runs as the
			-- SHELL's own job, so what it sets is still set at the prompt.
			profile = true
		else
			-- One answer for a bad name and for a bad password alike: the
			-- machine does not say which half was wrong.
			CeroSec.consolePush(console, "login incorrect")
			CeroSec.log("login refused: " .. tostring(reason))
		end
	elseif waiting == "prompt" then
		-- The question comes off the console before the answer is judged, so a
		-- command that ends here leaves nothing behind, and one that asks again
		-- puts its own question back.
		local asked = console.prompt
		console.prompt = nil
		if asked.mask then
			CeroSec.consolePush(console, CeroSec.maskedLine(asked.text, text))
		else
			CeroSec.consolePush(console, asked.text .. text)
		end
		-- A question a running job put up: the answer goes to the job and not
		-- through the core's own continuations. Which of the two it is is the
		-- token's business, exactly as it is for sudo and passwd.
		local job = nil
		if type(asked.cont) == "table" and asked.cont.cmd == "job" then
			job = CeroSecJobs.foreground(luaObject, console)
			if job == nil or job.id ~= asked.cont.id then job = nil end
		end
		if job ~= nil then
			CeroSecOS.jobInput(state, job, text,
				self:execEnv(luaObject, state, playerObj, token))
			-- A pass right here, in the hand of whoever answered: the answer may
			-- have finished the line, and the orders a finished line can give --
			-- the editor above all -- need to know whose keyboard is on the
			-- machine. `sudo reboot` ends here, on the password.
			CeroSecJobs.runMachine(self, luaObject, CeroSec.STEP_BUDGET_PER_MACHINE,
				getTimestampMs(), playerObj, token, true, console)
			return
		end

		local session = self:sessionOf(console)
		local _, lines, control, data =
			CeroSecOS.continue(state, session, asked.cont, text,
				self:execEnv(luaObject, state, playerObj, token))
		order = control
		self:writeSession(console, session)
		luaObject:mirrorOS()
		if control == "exit" then
			self:logOut(luaObject, state, console)
		elseif control == "clear" then
			CeroSec.consoleClear(console)
		else
			CeroSec.consolePushAll(console, lines)
			if control == "job" then
				self:startJob(luaObject, console, data)
			else
				self:applyOrder(console, control, data, playerObj)
			end
		end
	end
	self:pushScreen(luaObject, state, console)
	-- A window's history belongs to the account, so a login is where it is
	-- handed over. Before the profile runs: the lines are his either way, and
	-- the profile is not something he typed.
	if profile then
		self:sendHistory(luaObject, state, console, playerObj, token)
		self:runProfile(luaObject, console, playerObj, token)
	end
	-- `sudo shutdown` and `sudo reboot` end here, on the answer to the password
	-- question, and end the screen the same way they do at a shell.
	self:applyPower(luaObject, order)
end

-- A window asking for the history of whoever is logged in now. Asked for by
-- the window when the account at the glass changes under it, which is the only
-- time its copy can be the wrong account's.
Commands.histtail = function(self, playerObj, x, y, z, token)
	local luaObject, state, console = self:targetFor(playerObj, x, y, z, token)
	if not luaObject then return end
	self:sendHistory(luaObject, state, console, playerObj, token)
end

Commands.exec = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:targetFor(playerObj, x, y, z, token)
	if not luaObject then return end

	if CeroSec.consoleWaiting(console) ~= "shell" then
		self:pushScreen(luaObject, state, console)
		return
	end

	local line = args.line
	if type(line) ~= "string" then line = "" end

	-- Enter on a line with no command in it prints nothing at all. A real
	-- terminal leaves the prompt row where it was and draws a new one under it,
	-- which is the same thing to look at; here the row being typed at is drawn
	-- by the window and is not part of the screen, so echoing an empty prompt
	-- would put a second, bare prompt line above it and push the live one down.
	if string.find(line, "[^ \t]") == nil then
		self:pushScreen(luaObject, state, console)
		return
	end

	-- `~.` on a telephone call, which is cu's own escape and the near end hanging
	-- up. It is answered HERE, before the shell, before history and before the far
	-- machine is told anything, because that is what a tilde escape IS: a line read
	-- by the program holding the receiver and never sent down the line. So it is
	-- not a command over there, it is in neither machine's history, and a far shell
	-- that happened to have a file called `~.` is never asked about it.
	--
	-- Either KIND of call: a telephone call and a radio link are both a program on
	-- THIS machine holding the far end open, and `~.` is a line read by that
	-- program. One escape, because there is one program -- a survivor does not
	-- learn a second way to hang up for having dialled a different link.
	--
	-- Only at a prompt, and only on a CALL. Escape is what interrupts something
	-- running over there (and what hangs up an idle session of either kind), so
	-- there is nothing here for a line typed while the far machine is busy; and an
	-- rlogin has no tilde escape at all, because rlogin's own escape character is
	-- "~" typed as the FIRST thing on a line with no shell reading it -- a
	-- distinction a window that sends whole lines cannot make. The manual says both.
	if CeroSecOS.isCuEscape(line) and CeroSecNet.callOn(luaObject, console) ~= nil then
		CeroSec.consolePush(console, self:promptFor(state, console) .. line)
		-- A radio link is held by a cu on the near machine, and hanging the line up
		-- is the end of that program as well as of the link: the box's word for the
		-- link going down is pushed by the teardown, and cu's own last word comes
		-- from the program itself when it is let go. Read BEFORE the teardown,
		-- which is what takes the pty this is found through away.
		local pty = CeroSecOS.remoteLine(luaObject.ptys, console.line)
		local job, object = CeroSecNet.tncJobFor(self, pty)
		CeroSecNet.endSession(self, luaObject, console)
		if job ~= nil then CeroSecJobs.tncBye(self, object, job) end
		return
	end

	-- History expansion, before anything else looks at the line: `!5` and `!!`
	-- are replaced by what they name and the REPLACEMENT is what is echoed,
	-- run and remembered, exactly as csh has done it since 1978.
	local session = self:sessionOf(console)
	local expanded, refusal = CeroSecOS.historyExpand(state, session, line)
	if expanded == nil then
		CeroSec.consolePush(console, self:promptFor(state, console) .. line)
		CeroSec.consolePush(console, refusal)
		console.status = 1
		self:pushScreen(luaObject, state, console)
		return
	end
	line = expanded

	CeroSec.consolePush(console, self:promptFor(state, console) .. line)
	-- Remembered for this account, on the disk, before it is judged: a line
	-- that will not parse is still a line he typed and still one he will want
	-- to press Up on to fix.
	CeroSecOS.historyAppend(state, session, line, CeroSecOS.clockOf(self:clockEnv()))

	-- The shell is a file like everything else. A machine whose /bin/sh has
	-- been deleted has no shell to parse a line with, and says so -- the two
	-- words that still work are the two that always do, one to ask what
	-- happened and one to walk away.
	-- On /bin and not on the account's PATH: the shell is the machine's own and
	-- is where it ships, and a PATH somebody wrote into a .profile must not be
	-- able to say which program parses the next line.
	local shRefusal = CeroSecOS.whyNotRun(state, session, "sh", CeroSecOS.DEFAULT_PATH)
	local bare = string.match(line, "^%s*(%S+)%s*$")
	if shRefusal ~= nil and not (bare ~= nil and CeroSecOS.NO_SHELL_WORDS[bare]) then
		CeroSec.consolePush(console, "sh: " .. shRefusal)
		console.status = 1
		self:pushScreen(luaObject, state, console)
		return
	end

	self:startPrompt(luaObject, console, line, playerObj, token)
end

-- Tab at the prompt. The window asks, the machine answers, and the answer is
-- one word: this is the only client command that changes nothing at all -- no
-- line is echoed, no history is written, no job is made, and the screen is not
-- pushed to anybody. A player pressing Tab is a player who has typed nothing
-- yet.
--
-- Which word, and what it may become, is the engine's (CeroSecOSComplete.lua),
-- so the server does exactly two things around it: it mounts /dev, because a
-- device is a file on this machine and `cat /dev/li` must find it; and it sends
-- back the line it answered ABOUT, so a window that has typed on since can tell
-- the answer is no longer about what it is holding.
Commands.complete = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:targetFor(playerObj, x, y, z, token)
	if not luaObject then return end

	-- Nothing is completed at a question, in the editor, or while a job holds
	-- the prompt: there is no command line being typed to complete. The screen
	-- goes back so the window stops waiting on an answer it will not get.
	if CeroSec.consoleWaiting(console) ~= "shell" then
		self:pushScreen(luaObject, state, console)
		return
	end

	local line = args.line
	if type(line) ~= "string" then line = "" end
	if #line > CeroSec.INPUT_MAX then line = string.sub(line, 1, CeroSec.INPUT_MAX) end
	local at = args.cursor
	if type(at) ~= "number" then at = #line end
	at = math.floor(at)
	if at < 0 then at = 0 end
	if at > #line then at = #line end

	local env = self:execEnv(luaObject, state, playerObj, token)
	CeroSecOS.mountDev(state, env)
	-- On the console's OWN PATH, which is the one the line being typed would be
	-- looked up on: a .profile that added ~/bin has to complete what is in it.
	local done = CeroSecOS.complete(state, self:sessionOf(console), line, at,
		CeroSecOS.pathValue(console.shvars))
	CeroSecOS.unmountDev(state, env)

	local cursor = at
	if done.replacement ~= nil then cursor = done.start - 1 + #done.replacement end
	-- Addressed to the window, so it carries the computer the window is standing
	-- at and not the one whose /bin was searched: down an rlogin those are two
	-- different machines, and a terminal believes nothing that names another.
	local seat = self:watchedAt(luaObject, console)
	self:reply(playerObj, "completed", {
		x = seat.x, y = seat.y, z = seat.z, token = token,
		line = line, at = at,
		start = done.start, replacement = done.replacement, cursor = cursor,
		candidates = done.candidates,
	})
end

-- The typed line, as a job, and the first pass of it run here and now.
--
-- Run HERE rather than left to the next tick for one reason that matters: the
-- orders a command can give -- opening the editor above all -- need to know
-- whose keyboard is on the machine, and the scheduler has no player. So the
-- line a player types gets its first pass in his own hand, which is also what
-- makes an ordinary `ls` answer in the same round trip it always did; a line
-- that does not finish in that pass becomes a running job like any other and
-- the scheduler takes it from there.
--
-- Shared with the login path, which runs ~/.profile exactly this way.
-- stdin, when the caller has one to hand over: the pipe buffer the job reads its
-- standard input out of. Only an rsh brings one (CeroSecNet's rsh order) -- a
-- line typed at a glass has no pipe behind it -- and it is attached before the
-- job takes its first step, because a job that has stepped once has already read
-- end of file.
function SCeroSecSystem:startPrompt(luaObject, console, line, playerObj, token, name, stdin)
	local state = luaObject:osState()
	if state == nil then return nil end
	-- When this session last did something, which is what `w` prints in its IDLE
	-- column. Deliberately NOT one of the fields CeroSec.repairConsole keeps, so it
	-- is gone on the next load: like a job, activity is runtime, and a session that
	-- came back from a save file shows the time since it LOGGED IN -- the honest
	-- floor, because it has been idle at least that long.
	console.busyAt = getTimestampMs()
	local job, refusal = CeroSecJobs.startPrompt(self, luaObject, console, line, name)
	if job == nil then
		CeroSec.consolePush(console, tostring(refusal))
		console.status = 2
		self:pushScreen(luaObject, state, console)
		return nil
	end
	if type(stdin) == "table" then job.stdinBuf = stdin end
	-- Passes, in his own hand, while the line is still asking the MACHINE for
	-- something only a pass can give it: a job, because it ended in "&", or an
	-- order it has to carry out with the line running on past it -- a `clear`, a
	-- `wall`. The pass that does the machine's half is not the pass the line
	-- finishes in, and a prompt held for a tick after `sh spin.sh &` or after
	-- `clear; ls` would swallow the next thing typed.
	--
	-- Bounded, and the two bounds are different things. An "&" is bounded by the
	-- job slots there are -- every answer costs one and the refusal after the last
	-- is final -- and an order by nothing at all, since a loop may broadcast as
	-- often as it likes. So the ceiling is the larger of the two, and a line that
	-- reaches it simply finishes on the scheduler's own passes with the prompt
	-- coming back when it does: the job is on the book and running, which is what
	-- a long line looks like anyway.
	local turns = 0
	while true do
		job.spawned = nil
		job.ordered = nil
		CeroSecJobs.runMachine(self, luaObject, CeroSec.STEP_BUDGET_PER_MACHINE,
			getTimestampMs(), playerObj, token, true, console)
		turns = turns + 1
		if (job.spawned == nil and job.ordered == nil) or CeroSecOS.jobIsOver(job)
				or turns > CeroSecOS.MAX_LINE_TURNS then
			break
		end
	end
	return job
end

-- ~/.profile, run at login.
--
-- It is an ordinary foreground job on the shell's own environment, which is the
-- whole point: `cd /var` and `x=5` in a profile are still in force at the first
-- prompt, because there is no second shell for them to be in force in. It
-- respects the budgets and the ceilings like anything else, and its errors
-- print the way a script's do -- ".profile: line 2: ...".
--
-- The quirk that comes with all of that, and it is named in the manual: a
-- .profile with an endless loop in it leaves the account at a busy prompt.
-- Escape is a ^C there like anywhere else, so the way out is to press it and
-- then edit the file; the machine is not bricked and never was.
--
-- Only when the file is there and the account may read it. A missing one is
-- the ordinary case and says nothing at all.
function SCeroSecSystem:runProfile(luaObject, console, playerObj, token)
	local state = luaObject:osState()
	if state == nil then return end
	local session = self:sessionOf(console)
	local user = CeroSecOS.getUser(state, session.user)
	if user == nil or type(user.home) ~= "string" or user.home == "" then return end
	local path = user.home .. "/" .. SCeroSecSystem.PROFILE_NAME

	local node = CeroSecOS.getNode(state, session, path)
	if node == nil or node.type ~= "file" then return end
	if not CeroSecOS.can(state, session, node, "r") then return end
	if (node.data or "") == "" then return end

	self:startPrompt(luaObject, console, node.data, playerObj, token, SCeroSecSystem.PROFILE_NAME)
end

-- The buffer as it stands, with the file untouched. Sent while it is being
-- typed so that the machine, and not the window, is what holds the work.
Commands.editbuf = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:targetFor(playerObj, x, y, z, token)
	if not luaObject then return end
	if not self:isEditor(luaObject, console, playerObj) then
		self:pushScreen(luaObject, state, console)
		return
	end

	local text, refusal = bufferOf(args.text)
	if text == nil then
		console.edit.message = refusal
	else
		console.edit.text = text
	end
	self:pushScreen(luaObject, state, console)
end

-- The buffer, and write it. The save is CeroSecOS.writeFile and nothing else,
-- so the editor has no permissions, no limits and no printable rule of its own:
-- it gets the one line the filesystem answers with and puts it on the glass.
Commands.editsave = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:targetFor(playerObj, x, y, z, token)
	if not luaObject then return end
	if not self:isEditor(luaObject, console, playerObj) then
		self:pushScreen(luaObject, state, console)
		return
	end

	local text, refusal = bufferOf(args.text)
	if text == nil then
		console.edit.message = refusal
		self:pushScreen(luaObject, state, console)
		return
	end
	console.edit.text = text

	-- A crontab is judged before it is installed, and refused whole: one bad line
	-- and nothing is written, which is what crontab(1) does with the file it was
	-- given. The refusal is Vixie's own -- the file, the line, the field -- worn
	-- under the editor's own "Cannot save:", because that is the sentence this
	-- screen has always answered a refused save with.
	if console.edit.crontab then
		local refusal = CeroSecOS.checkCrontab(console.edit.path, text)
		if refusal ~= nil then
			console.edit.message = "Cannot save: " .. refusal
			self:pushScreen(luaObject, state, console)
			return
		end
	end

	local session = self:editSession(console)
	-- The editor's save is a write like any other, clock included: a file saved
	-- out of the editor is stamped the minute it was saved.
	local done, reason = CeroSecOS.writeFile(state, session, console.edit.path, text, false,
		CeroSecOS.clockOf(self:clockEnv()))
	if done == nil then
		console.edit.message = "Cannot save: " .. tostring(reason)
	else
		console.edit.message = "Saved " .. #text .. " bytes"
		console.edit.saves = (console.edit.saves or 0) + 1
		-- A new file has just come into being writable; say so.
		console.edit.readonly = false
		luaObject:mirrorOS()
	end
	self:pushScreen(luaObject, state, console)
end

-- Out of the editor and back to the shell. Whatever was not saved is gone, the
-- way nano's ^X with an answered question leaves it. Closing the window is not
-- this: a window that shuts leaves the machine in the editor, and the buffer
-- with it.
Commands.editexit = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:targetFor(playerObj, x, y, z, token)
	if not luaObject then return end
	if not self:isEditor(luaObject, console, playerObj) then
		self:pushScreen(luaObject, state, console)
		return
	end
	console.edit = nil
	self:pushScreen(luaObject, state, console)
end

-- Escape, while the machine is in the middle of something: ^C.
--
-- What is dropped is the question, never the session -- the shell prompt comes
-- back, or `login:` when what was half typed was a name. It is a server command
-- and not a client-side reset because the screen belongs to the machine: every
-- window standing at it sees the same ^C on the same line.
Commands.interrupt = function(self, playerObj, x, y, z, token, args)
	local host, hostConsole = self:biosConsoleFor(playerObj, x, y, z, token)
	if not host then return end

	local luaObject, state, console = host, host:osState(), hostConsole
	if not state then
		self:replyClosed(playerObj, x, y, z, "broken", token)
		return
	end
	-- A session on another machine, when that is what the glass is showing: the
	-- ^C belongs to whatever is running over there.
	if hostConsole.remote ~= nil then
		luaObject, state, console = self:targetFor(playerObj, x, y, z, token)
		if not luaObject then return end
	end

	-- Escape at an idle REMOTE prompt closes the session. There is nothing to
	-- interrupt and the window must not shut -- the survivor is still standing at
	-- his own machine -- so the one thing left to give up on is the connection.
	-- It is the only place Escape means something the local machine's own prompt
	-- does not, and the manual says so.
	if type(console.line) == "string" and not CeroSec.consoleActive(console) then
		-- Except on a RADIO link, where it means what the same key means on a
		-- TNC-2: back to the box's cmd: prompt, with the link still up. The link is
		-- held by a cu on the near machine and that program is still running, so
		-- there is somewhere to go back TO -- which is exactly what the other two
		-- links have not got, an rlogin and a telephone call being held by the
		-- console alone. `~.` is still how the line is hung up, and D still how the
		-- link is dropped; the manual says all three.
		if CeroSecNet.parkTnc(self, luaObject, console) then return end
		CeroSecNet.endSession(self, luaObject, console)
		return
	end

	-- Nothing to interrupt: the window is told what is on the screen and
	-- decides for itself what to do about it. The client asks the same question
	-- before it sends this, so reaching here means the two disagreed -- a
	-- prompt answered by somebody else in between.
	if not CeroSec.consoleActive(console) then
		self:pushScreen(luaObject, state, console)
		return
	end

	-- The line as it stood, with "^C" where the answer would have gone. Taken
	-- before anything is cleared, or it would be the prompt of the state the
	-- interrupt leaves behind rather than of the one it interrupted.
	local head = self:promptFor(state, console, self:hostnameOf(luaObject, state))
	CeroSec.consolePush(console, head .. "^C")
	-- The foreground job goes with it: Escape at a running script is the ^C of
	-- a 1993 terminal and kills what is running, question and all. The
	-- scheduler is what says "killed" on the next pass, so the two lines come
	-- out in the order they happened.
	local job = CeroSecJobs.foreground(luaObject, console)
	if job ~= nil then CeroSecOS.killJob(job, nil) end
	console.prompt = nil
	console.pending = nil

	if job == nil then
		self:pushScreen(luaObject, state, console)
		return
	end
	-- A pass right here rather than on the next tick, so the prompt comes back
	-- in the same round trip the key went out in. It is the scheduler's own
	-- pass -- it reaps the job, says "killed" if there is anything to say, and
	-- pushes the screen -- and every line it produces lands after the "^C"
	-- pushed above, which is the order they happened in.
	CeroSecJobs.runMachine(self, luaObject, CeroSec.STEP_BUDGET_PER_MACHINE,
		getTimestampMs(), playerObj, token, true, console)
end

Commands.close = function(self, playerObj, x, y, z, token)
	if token == nil then return end
	local luaObject = self:getLuaObjectAt(x, y, z)
	if not luaObject then return end
	luaObject:removeWatcher(watcherKeyOf(playerObj, token))
end

--
-- The debug window
--
-- Two commands, and neither is like the ones above: they are about the COUNTY and
-- not about a terminal, so nothing here asks whether the player is standing next
-- to anything. The x, y, z every command carries is the machine SELECTED in the
-- window -- which may be a computer on the other side of the map, or none at all
-- (0,0,0 answers to nobody and is what "nothing selected" looks like on the wire).
--
-- What is asked instead is CeroSec.debugAllowed(), here as well as on the client
-- that offered the entry: a client is not to be trusted about whether it was
-- allowed to ask. Today that is the DEV_DEBUG_MENU flag or the game's own debug
-- mode; the release gating adds the admin check beside it (see docs/DEBUG.md).
--
-- `debug` is a READ and answers a snapshot. `debugact` is the only writing thing
-- the window can do, and for `on` and `off` it does not do it itself: it calls the
-- very object methods the context menu's own commands call, so a machine switched
-- on from the debug window is switched on exactly as a survivor switches one on.
--
-- `reset` is the one act with no survivor's gesture behind it -- it makes a machine
-- nobody has ever used out of one that has been, so that a first power-on can be
-- tried a second time (SCeroSecObject:resetMachine, and docs/DEBUG.md for why it
-- exists at all). It is a developer's act and lives behind the same door as the
-- rest of this window and behind two clicks on the glass.
--

Commands.debug = function(self, playerObj, x, y, z, token, args)
	if token == nil then return end
	-- The player the ENGINE handed OnClientCommand, and never a field on args: the
	-- question is whether HE was allowed to ask, and a client answering that about
	-- itself is not a door (CeroSec.debugAllowed).
	if not CeroSec.debugAllowed(playerObj) then return end
	if type(args) ~= "table" then return end
	local tab = args.tab
	if not CeroSecDebug.isTab(tab) then return end

	-- nil for a machine nothing answers to, which is what "nothing selected" is.
	-- Deliberately NOT adopted the way computerFor adopts one: the window is a
	-- reader, and a read must not bring a computer into the system.
	local luaObject = self:getLuaObjectAt(x, y, z)
	local snapshot = CeroSecDebug.snapshotOf(self, tab, luaObject)
	if snapshot == nil then return end

	snapshot.token = token
	snapshot.tab = tab
	snapshot.x, snapshot.y, snapshot.z = x, y, z
	self:reply(playerObj, "debug", snapshot)
end

-- A refusal, back to the window that asked, on the very `debug` answer a snapshot
-- comes on -- with an `error` on it and no tab, so the window puts it on the first
-- line of the block under the list and leaves the lists it has alone.
--
-- There was no such thing until now, and that was the defect: `debugact` called
-- turnOn, turnOn refuses a machine whose chunk is away -- the wire is asked of a
-- SQUARE and there is nobody to ask -- the boolean was dropped here, nothing was
-- answered, and the window drew the same `off` two seconds later. A button that
-- cannot work looked exactly like a button that had. A refusal a player cannot read
-- is a refusal that looks like a bug in the mod.
local function refuseAct(system, playerObj, token, x, y, z, why)
	system:reply(playerObj, "debug",
		{ token = token, error = why, x = x, y = y, z = z })
end

-- The same door, for something that WORKED and has a sentence to show for it:
-- the self-test's verdict, and the receipt for a disk handed over. A `note` and
-- not an `error`, because the window greys nothing on it and a reader must be
-- able to tell "PASS 128 FAIL 0" from a refusal. Like a refusal, it carries no
-- tab, so no list is emptied by it.
local function noteAct(system, playerObj, token, x, y, z, text)
	system:reply(playerObj, "debug",
		{ token = token, note = text, x = x, y = y, z = z })
end

-- ANY DISK OF THE CATALOGUE, into his hands.
--
-- A write -- which is why it is here and not in SCeroSecDebug.lua, that file being
-- read-only with no exception. It is ejectfloppy's own path and not a shorter one:
-- AddItem, the modData written BEFORE the item is announced to the clients, the
-- sticker put on with vanilla's own three calls, and sendAddItemToContainer last. A
-- disk handed over any other way is a disk a multiplayer client never sees.
--
-- THE TELLING IS ROLLED, the way the world rolls one (CeroSecContent.onCreateFloppy):
-- a handwritten entry has a sticker per telling and three contents, so a disk handed
-- over with no roll would be the first telling for ever -- and what this button is for
-- is looking at the disk a player finds. A bench with no ZombRand gets the
-- catalogue's own default, which is telling one.
--
-- nil when he has it, or the sentence to put on the glass.
local function giveDisk(playerObj, entry, now)
	if entry == nil then return "there is no such disk in the catalogue" end
	local variant = nil
	if ZombRand ~= nil then
		variant = math.floor(ZombRand(CeroSecContent.VARIANTS)) + 1
	end
	-- Built from the catalogue at the moment it is asked for, through the very
	-- function loot builds a disk with, so the floppy in his hand is the floppy the
	-- bench weighed -- ceilings, modes, printable rule and all.
	local disk, written = CeroSecContent.diskData(entry, now, variant)
	if disk == nil then return "the catalogue would not make the disk" end
	-- BLANK is an entry with no files on purpose, so the count it has to match is
	-- zero and not the length of a table that is not there.
	local total = type(entry.files) == "table" and #entry.files or 0
	if written < total then
		return "only " .. written .. " of " .. total .. " files fitted on it"
	end

	local inv = playerObj:getInventory()
	if inv == nil then return "there is nowhere to put it" end
	-- Same as the eject, and for the same reason: this shell is about to be written
	-- over with a disk that is already built (CeroSecContent.ejecting).
	CeroSecContent.ejecting = true
	local item = inv:AddItem(CeroSec.FLOPPY_TYPES[1])
	CeroSecContent.ejecting = false
	if not item then return "he is carrying too much" end
	if not CeroSecOS.writeDiskTo(item:getModData(), disk) then
		inv:Remove(item)
		if isServer() then sendRemoveItemFromContainer(inv, item) end
		return "the disk would not go onto the item"
	end
	-- The sticker, so `mount` and `df` name it and the survivor can find it in his
	-- bag. Vanilla's Rename Bag's three calls, in its order
	-- (ISInventoryPaneContextMenu.lua:2753-2755).
	if CeroSecOS.labelOk(disk.label) then
		item:setName(disk.label)
		item:setCustomName(true)
		item:syncItemFields()
		-- Printed, like the rest of the company's media, and the look says so. Asked
		-- of the sticker rather than of the entry beside it, so this path and an
		-- eject answer the same question the same way (CeroSecContent.markByLabel).
		CeroSecContent.markByLabel(item, disk.label)
	else
		CeroSecContent.markLabel(item, nil)
		CeroSecContent.unname(item)
	end
	if isServer() then sendAddItemToContainer(inv, item) end
	-- The sticker it really came out with, beside the "it worked": the telling was
	-- rolled in here, so a caller that wanted to name the label in a receipt would
	-- otherwise have to roll it a second time and name a different one.
	return nil, disk.label
end

-- The self-test disk, which is the one entry of weight 0: no drawer in the county
-- has one and this is the only way to it (docs/CONTENT.md).
local function giveDiagnosticsDisk(playerObj, now)
	local entry = CeroSecContent.diskById(CeroSecContent.DIAG_DISK)
	if entry == nil then return "there is no diagnostics disk in the catalogue" end
	return giveDisk(playerObj, entry, now)
end

-- A PAPER, into his hands: the very sticky note a drawer or a pocket of that
-- premises would hold.
--
-- CeroSecNotes.write and not a second AddItem of our own, because the words on a
-- note are put on with three calls in an order that matters (the head of
-- CeroSecNotes.write) -- and the container is the survivor's own inventory, which is
-- a container like any drawer. The announce goes last, exactly as the disk's does: a
-- paper a multiplayer client never hears about is a paper he cannot read.
--
-- nil when he has it, or the sentence to put on the glass.
local function givePaper(playerObj, text)
	local inv = playerObj:getInventory()
	if inv == nil then return "there is nowhere to put it" end
	local item = CeroSecNotes.write(inv, text)
	if item == nil then return "he is carrying too much" end
	if isServer() then sendAddItemToContainer(inv, item) end
	return nil
end

Commands.debugact = function(self, playerObj, x, y, z, token, args)
	if token == nil then return end
	if not CeroSec.debugAllowed(playerObj) then return end
	if type(args) ~= "table" or type(args.act) ~= "string" then return end

	-- The one act that is about a survivor's BAG and not about a machine, so it is
	-- answered before the lookup every other act needs: nothing is selected when a
	-- window is first opened, 0,0,0 is what that looks like on the wire, and a
	-- "Give diagnostics disk" that refused until a row had been clicked would be a
	-- button nobody could find the use of.
	if args.act == "givedisk" then
		local why = giveDiagnosticsDisk(playerObj, CeroSecOS.clockOf(self:clockEnv()))
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "no disk: " .. why)
		else
			noteAct(self, playerObj, token, x, y, z,
				"CEROSEC DIAGNOSTICS is in your inventory -- insert it, then" ..
				" mount /dev/fd0 /mnt and sh /mnt/selftest.sh")
		end
		return
	end

	-- And the same thing for ANY entry of the catalogue, chosen off a combo. About a
	-- bag again, so it is answered in the same place and for the same reason.
	--
	-- The id is a string a client sent, so it is not believed: it is looked up in the
	-- catalogue, and a lookup that finds nothing is a refusal. Nothing is built out of
	-- it -- the entry the lookup answers is what the disk is made from
	-- (CeroSecContent.diskById).
	if args.act == "anydisk" then
		local id = args.disk
		if type(id) ~= "string" or #id > CeroSecDebug.CELL_MAX then
			refuseAct(self, playerObj, token, x, y, z, "no disk: no disk was named")
			return
		end
		local entry = CeroSecContent.diskById(id)
		local why, label = giveDisk(playerObj, entry,
			CeroSecOS.clockOf(self:clockEnv()))
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "no disk: " .. why)
		else
			noteAct(self, playerObj, token, x, y, z, id ..
				" is in your inventory, labelled " ..
				tostring(label or "nothing at all"))
		end
		return
	end

	local luaObject = self:getLuaObjectAt(x, y, z)
	if not luaObject then
		refuseAct(self, playerObj, token, x, y, z, "no machine at " ..
			tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
		return
	end

	if args.act == "on" then
		-- Asked before it is done, and the SAME question the window greys the button
		-- with (CeroSecDebug.turnOnRefusal): one rule, one place, one wording.
		local why = CeroSecDebug.turnOnRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "cannot turn on: " .. why)
		elseif not luaObject:turnOn() then
			-- Nothing above found a reason and the object refused anyway, which can
			-- only be a rule that has moved since this was written. Said plainly
			-- rather than swallowed: a silence here is how the last one hid.
			refuseAct(self, playerObj, token, x, y, z,
				"turnOn refused and did not say why")
		end
	elseif args.act == "off" then
		local why = CeroSecDebug.turnOffRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "cannot turn off: " .. why)
		elseif not luaObject:turnOff() then
			refuseAct(self, playerObj, token, x, y, z,
				"turnOff refused and did not say why")
		end
	elseif args.act == "reset" then
		-- The one act that WRITES a machine's disk, and the same question the window
		-- greys the button with: off, and nothing else (CeroSecDebug.resetRefusal).
		-- Behind the same door as everything else in here, which is the whole of the
		-- protection it has: debugAllowed was asked at the top of this function and
		-- a client is not trusted about it.
		local why = CeroSecDebug.resetRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "cannot reset: " .. why)
		elseif not luaObject:resetMachine() then
			refuseAct(self, playerObj, token, x, y, z,
				"reset refused and did not say why")
		end
	elseif args.act == "dump" then
		CeroSecDebug.dump(luaObject)
	elseif args.act == "selftest" then
		-- Every vector on THIS VM -- the game's Kahlua, in this save -- weighed
		-- against lua5.1's answers, plus the save path of the selected machine,
		-- which is the one thing no offline bench can be asked.
		local result = CeroSecSelfTest.runAll(luaObject)
		local summary = CeroSecSelfTest.summary(result)
		-- Every failing line at warn, so the Log tab's own filter finds them, and
		-- the summary at info whether it passed or not: a run that said nothing
		-- when it passed would be a run nobody could tell from a button that did
		-- not work.
		for i = 1, #result.lines do
			CeroSec.log(CeroSec.LOG_WARN, result.lines[i])
		end
		CeroSec.log(CeroSec.LOG_INFO, summary)
		-- And to the game log, which is the one place a verdict survives the
		-- session: console.txt on a client, the server's log on a dedicated one.
		-- print and not the ring, because the ring is two hundred lines long and a
		-- release note has to be pasted from somewhere.
		print("CeroSec " .. summary)
		noteAct(self, playerObj, token, x, y, z, summary ..
			(result.fail > 0 and " -- the lines are on the Log tab" or ""))
	elseif args.act == "rootnote" then
		-- THE PAPER THE DRAWER WOULD HOLD, and it is derived here exactly as the
		-- drawer derives it: the save's own secret and the premises' two bytes
		-- through CeroSecContent.rootKey (CeroSecNotes.deskNote is the same four
		-- lines). So what he is handed opens the machine in front of him.
		--
		-- AND THE PREMISES IS NOT MARKED. CeroSecNotes.premisesMark is about a
		-- PREMISES and says whether its one paper has been placed in a real
		-- container; marking it here would take the note out of the next drawer
		-- somebody opens, which is a developer's button quietly changing the world
		-- a player walks through.
		local why = CeroSecDebug.rootNoteRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "no root note: " .. why)
		else
			local b1, b2 = CeroSecDebug.profileOf(luaObject)
			local password = CeroSecContent.password(self:secret(),
				CeroSecContent.rootKey(b1, b2))
			if password == nil then
				refuseAct(self, playerObj, token, x, y, z,
					"no root note: the secret would not derive one")
			else
				local text = string.format(CeroSecNotes.ROOT_FORM, "root", password)
				local said = givePaper(playerObj, text)
				if said ~= nil then
					refuseAct(self, playerObj, token, x, y, z, "no root note: " .. said)
				else
					noteAct(self, playerObj, token, x, y, z,
						text .. " -- the drawer of this premises still has its own")
				end
			end
		end
	elseif args.act == "staffnote" then
		-- A member of staff's own login, on the paper a pocket would hold
		-- (CeroSecNotes.zombieNote). THE FIRST locked slot and never a roll: a
		-- button that handed out a different account every press would be a button
		-- nobody could use twice, and the tooltip says which one it is.
		local why = CeroSecDebug.staffNoteRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "no staff note: " .. why)
		else
			local b1, b2, profile = CeroSecDebug.profileOf(luaObject)
			local slot = CeroSecContent.lockedSlots(profile)[1]
			local secret = self:secret()
			local login = CeroSecContent.accountLogin(secret, b1, b2, slot)
			-- A profile may NAME an account, and then the login is the name it
			-- gave: the same choice makeAccounts makes, or the paper names a
			-- login the machine has not got.
			local named = profile.accounts[slot].name
			if type(named) == "string" then login = named end
			local password =
				CeroSecContent.accountPassword(secret, b1, b2, slot, login)
			-- The one thing a staff paper must never carry, and the check is here
			-- and not trusted to the catalogue for the reason zombieNote gives:
			-- the catalogue is what a content wave rewrites.
			if login == "root" then
				refuseAct(self, playerObj, token, x, y, z,
					"no staff note: slot " .. tostring(slot) .. " is root")
			elseif login == nil or password == nil then
				refuseAct(self, playerObj, token, x, y, z,
					"no staff note: the secret would not derive one")
			else
				local text = string.format(CeroSecNotes.USER_FORM, login, password)
				local said = givePaper(playerObj, text)
				if said ~= nil then
					refuseAct(self, playerObj, token, x, y, z, "no staff note: " .. said)
				else
					noteAct(self, playerObj, token, x, y, z,
						text .. " -- slot " .. tostring(slot) .. " of its premises")
				end
			end
		end
	elseif args.act == "accounts" then
		-- WHO IS ON IT, with the letters. To the server's log, where a line that
		-- size belongs and where an operator would look for it, and back to the
		-- ONE window that asked -- never broadcast, and never to any other client:
		-- reply is the asking connection's (see the head of this section).
		local why = CeroSecDebug.accountsRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "no accounts: " .. why)
		else
			local lines = CeroSecDebug.accounts(self, luaObject)
			for i = 1, #lines do
				CeroSec.log(CeroSec.LOG_INFO, lines[i])
			end
			noteAct(self, playerObj, token, x, y, z,
				tostring(lines[1]) .. " -- the lines are on the Log tab")
		end
	elseif args.act == "clearpass" then
		-- passwd -d, which on this machine is a password of NO LETTERS: an open
		-- account is one whose stored hash is the hash of "" and has been since the
		-- first machine shipped (CeroSecOS.newUser), so there is nothing to invent
		-- -- setPassword with "" is what login then lets straight through.
		local why = CeroSecDebug.clearPassRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "no password cleared: " .. why)
			return
		end
		-- The login is a string a client sent, so it is held to the machine's own
		-- rule for a name in /etc/passwd before it reaches anything
		-- (CeroSecOS.parsePasswdLine's own isValidName) -- and it never reaches a
		-- Lua pattern: getUser is a table lookup.
		local login = args.login
		if not CeroSecOS.isValidName(login) then
			refuseAct(self, playerObj, token, x, y, z,
				"no password cleared: that is not an account name")
			return
		end
		local state = luaObject:osState()
		if state == nil or CeroSecOS.getUser(state, login) == nil then
			refuseAct(self, playerObj, token, x, y, z,
				"no password cleared: no such user " .. login)
			return
		end
		local now = CeroSecOS.clockOf(self:clockEnv())
		local done, reason = CeroSecOS.setPassword(state, login, "",
			"debug" .. tostring(now), now)
		if done == nil then
			refuseAct(self, playerObj, token, x, y, z,
				"no password cleared: " .. tostring(reason))
		else
			luaObject:mirrorOS()
			noteAct(self, playerObj, token, x, y, z, login ..
				" has no password now -- log in and press return at the password")
		end
	elseif args.act == "rootlogin" then
		-- ROOT ON THE GLASS, with the password check and nothing else skipped.
		--
		-- The session is the very table CeroSecOS.login answers with, built off the
		-- account record the way that function builds it, and every gesture after
		-- it is the login's own (SCeroSecSystem:beginSession) -- the shell, the
		-- greeting, the wtmp line. So `who`, `last` and the prompt all read exactly
		-- as they read for somebody who typed the letters, which is the point: this
		-- is a shortcut past the KEYBOARD and past nothing else.
		local why = CeroSecDebug.rootLoginRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "no root login: " .. why)
		else
			local state = luaObject:osState()
			local console = luaObject.console
			local user = CeroSecOS.getUser(state, "root")
			-- Echoed on the glass, because a session nobody can see arriving reads
			-- as a machine that logged itself in.
			CeroSec.consolePush(console, "login: root")
			console.pending = nil
			self:beginSession(state, console, { user = user.name,
				cwd = user.home or "/" })
			luaObject:mirrorOS()
			self:pushScreen(luaObject, state, console)
			noteAct(self, playerObj, token, x, y, z,
				"root is logged in at its console")
		end
	elseif args.act == "cronnow" then
		-- cron's minute, by hand.
		--
		-- The minute hand is WOUND BACK and the daemon's own pass is then called:
		-- cronPass runs a line only on a minute it has not already looked at
		-- (`luaObject.cron.minute`), so a second call in the same game minute does
		-- nothing at all -- which is right for the daemon and is exactly what this
		-- button has to get past. Nothing else about the pass is changed: the lines
		-- that fire are the lines cronDue says are due at the clock the world has.
		local why = CeroSecDebug.cronNowRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "cron did not run: " .. why)
		else
			local now = CeroSecOS.clockOf(self:clockEnv())
			if now == nil then
				refuseAct(self, playerObj, token, x, y, z,
					"cron did not run: the world has no clock")
			else
				if type(luaObject.cron) ~= "table" then luaObject.cron = {} end
				luaObject.cron.minute = math.floor(now / 60) - 1
				local fired = CeroSecJobs.cronPass(self, luaObject, now)
				local queued = CeroSecJobs.atPass(self, luaObject, now)
				noteAct(self, playerObj, token, x, y, z,
					"cron fired " .. fired .. " line(s) and at started " ..
					queued .. " job(s)")
			end
		end
	elseif args.act == "forcewire" then
		-- THE AUTOMATION'S WALK, run to the end.
		--
		-- CeroSecAuto.wire walks ROOMS_PER_MINUTE rooms a game minute, so a mall
		-- takes many minutes and a tester cannot see the end of it. This calls the
		-- very same function over and over -- never a copy of the walk -- and stops
		-- on the first of two things: the record says `wired`, or a pass fitted
		-- nothing and walked nothing new. The bound is the ROOM COUNT of the
		-- premises and never "until it finishes": a walk that cannot finish must
		-- cost this command a known number of passes and not the server's frame.
		local why = CeroSecDebug.forceWireRefusal(luaObject)
		if why ~= nil then
			refuseAct(self, playerObj, token, x, y, z, "no wiring: " .. why)
		else
			local net = CeroSecOS.netRecord(luaObject.os)
			local record = CeroSecAuto.recordOf(self, net.b1, net.b2)
			local fitted, passes = 0, 0
			while passes < CeroSecDebug.WIRE_PASS_MAX do
				passes = passes + 1
				local walkedBefore = CeroSecDebug.roomsWalked(record)
				local got = CeroSecAuto.wire(self, luaObject)
				fitted = fitted + got
				if record.wired == true then break end
				-- No progress is no progress: a pass that fitted nothing and
				-- reached no new room will answer the same next time, and looping
				-- on it is the server standing still.
				if got == 0 and CeroSecDebug.roomsWalked(record) == walkedBefore then break end
			end
			noteAct(self, playerObj, token, x, y, z,
				"wired " .. fitted .. " fixture(s) in " .. passes .. " pass(es); " ..
				(record.wired == true and "the premises is finished"
					or "the premises is not finished -- rooms whose chunks are away"))
		end
	end
end

-- Nothing a client sends is believed on its word. Coordinates have to be three
-- numbers before they reach any arithmetic or any Java call, and the token is a
-- string of a sane length before it is ever echoed back.
local function coordsOf(args)
	if type(args) ~= "table" then return nil end
	if type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number" then
		return nil
	end
	return math.floor(args.x), math.floor(args.y), math.floor(args.z)
end

local TOKEN_MAX = 64

local function tokenOf(args)
	local token = args.token
	if type(token) ~= "string" or #token > TOKEN_MAX then return nil end
	return token
end

--
-- The one command that is about no machine at all
--
-- Every command above names a square -- a computer's, or a fixture's -- because
-- every one of them is about a thing standing somewhere. Looking a number up in a
-- telephone directory is not: the book is in a survivor's hands and the premises
-- it lists may be a county away with nothing built on it yet. So it goes in its
-- own table, which is what the dispatcher checks before it insists on three
-- coordinates.
--
--   phonebook { rx, ry }  -- the listings of one exchange's region
--   listings  { rx, ry, exchange, entries = { { name, number } }, capped }
--
-- The REGION is what travels and not a coordinate on the map, because a region is
-- what an exchange is (CeroSecOS.phoneExchange) and it is the whole of what the
-- book was stamped with. Two numbers, floored, and nothing else is believed.
--
-- Answered to the ASKING PLAYER through self:reply, like every other answer here:
-- a book in one survivor's hands is not read out to the server.
--
local PlayerCommands = {}

PlayerCommands.phonebook = function(self, playerObj, args)
	local rx, ry = args.rx, args.ry
	if type(rx) ~= "number" or type(ry) ~= "number" then return end
	rx, ry = math.floor(rx), math.floor(ry)
	local entries, capped = CeroSecNet.directory(rx, ry)
	self:reply(playerObj, "listings", {
		rx = rx, ry = ry,
		token = tokenOf(args),
		exchange = CeroSecOS.phoneExchangeOfRegion(rx, ry),
		entries = entries,
		capped = capped,
	})
end

function SCeroSecSystem:OnClientCommand(command, playerObj, args)
	if not playerObj then return end
	-- The commands about no square, first: insisting on three coordinates for one
	-- of those would refuse it, and the refusal would be silent.
	local free = PlayerCommands[command]
	if free then
		if type(args) ~= "table" then return end
		free(self, playerObj, args)
		return
	end

	local fn = Commands[command]
	if not fn then return end
	local x, y, z = coordsOf(args)
	if not x then return end
	fn(self, playerObj, x, y, z, tokenOf(args), args)
end

--
-- Housekeeping
--

--
-- THE MACHINES THE MINUTE SWEEP HAS TO LOOK AT
--
-- gos_cerosec.bin holds every computer in Knox County -- nine thousand five
-- hundred buildings' worth, all of them in memory whether their chunks are loaded
-- or not (the head of SCeroSecNet.lua) -- and the sweep used to walk all of them
-- twice a game minute. Measured under lua5.1 at the scale a server really has
-- (300 machines, 40 of them on): checkPower 25 ms a call, checkCron 48 ms, and
-- 580 ms on the first minute. Every one of those milliseconds was spent on a
-- machine that is DARK, which has nothing to answer: the power question returns at
-- once for a machine that is off (SCeroSecObject:checkPower), a dark machine has
-- no windows, no /dev to refresh and no crontab to run.
--
-- So two indexes, both on the system and neither of them saved -- setModDataKeys
-- names the four keys that are (initSystem above), so anything else here is
-- session state:
--
--   onMachines   every machine that is ON. The power check, the watchers, /dev and
--                cron's minute are all about those and only those.
--   newMachines  every machine whose square was made in this save and has not been
--                settled yet (`born`). These may be OFF and still have to be
--                visited: the automation's question is what switches one on.
--
-- WHERE THEY ARE WRITTEN, and it is every place the two fields are, through one
-- function that reads the machine rather than being told what changed
-- (SCeroSecObject:reindex): turnOn, turnOff, the sprite a chunk with no
-- GlobalObject is adopted from, a computer put down out of somebody's hands, and
-- the two bits the automation writes. A machine ARRIVING comes through
-- newLuaObject -- which the engine calls for every object in the save file at
-- load (SGlobalObjectSystem:initLuaObjects) with the saved fields already in the
-- table, so a county left running is in the index before the first minute -- and
-- one LEAVING through aboutToRemoveFromSystem, which removeLuaObject calls.
--
-- AND THEY HEAL. An entry that is neither `on` nor `born` when the sweep reaches
-- it is dropped there and then, so a transition nobody reported costs one visit
-- and never a machine that is swept for ever. The other direction cannot be
-- healed cheaply and is not guessed at: a machine whose `on` was written behind
-- these calls' back is a machine the sweep does not know about, which is why the
-- index is written by the field's own writers and by nothing else.
--

local function machineKey(luaObject)
	return luaObject.x .. "," .. luaObject.y .. "," .. luaObject.z
end

function SCeroSecSystem:indexMachine(luaObject)
	if luaObject == nil then return end
	if type(self.onMachines) ~= "table" then self.onMachines = {} end
	if type(self.newMachines) ~= "table" then self.newMachines = {} end
	local key = machineKey(luaObject)
	self.onMachines[key] = luaObject.on == true and luaObject or nil
	self.newMachines[key] = luaObject.born == true and luaObject or nil
end

-- Out of both, for a machine that has left the system: picked up, smashed, or its
-- square destroyed.
function SCeroSecSystem:forgetMachine(luaObject)
	if luaObject == nil then return end
	local key = machineKey(luaObject)
	if type(self.onMachines) == "table" then self.onMachines[key] = nil end
	if type(self.newMachines) == "table" then self.newMachines[key] = nil end
end

-- One index as an array, taken BEFORE the walk that uses it: a machine switched on
-- or off inside the walk writes the index, and a table walked with `pairs` while it
-- is being written to is a table Kahlua makes no promise about.
local function machineList(index)
	local out = {}
	if type(index) ~= "table" then return out end
	for _, luaObject in pairs(index) do out[#out + 1] = luaObject end
	return out
end

-- The machines that are on, for the sweeps that are only about those.
function SCeroSecSystem:onMachineList()
	return machineList(self.onMachines)
end

-- Tell every window open on this machine that it is over, then forget them.
function SCeroSecSystem:evictWatchers(luaObject, reason)
	if not luaObject.watchers then return end
	for _, watcher in pairs(luaObject.watchers) do
		if watcher.player then
			self:replyClosed(watcher.player, luaObject.x, luaObject.y, luaObject.z,
				reason, watcher.token)
		end
	end
	luaObject:dropWatchers()
end

-- Computers on a square that lost power shut themselves off, and a window whose
-- player has wandered off, died or left is not a window any more. Nothing of
-- the screen is lost by either: the console belongs to the machine, and only a
-- machine going dark clears it.
--
-- The two lists are the sweep's indexes and not every computer in the county (the
-- head of this section): a dark machine has no power question, no window and no
-- /dev, so it is not visited at all. Everything here that needs the WORLD is asked
-- only of a machine the world still has: the address, the power and the book of
-- device numbers all go through a square. A machine whose chunk is away keeps the
-- state it had and is asked again the moment the chunk comes back
-- (SCeroSecObject:stateToIsoObject). What the machine's own DISK answers is not in
-- here at all and goes on regardless -- cron's pass below, and the jobs the
-- scheduler steps.
function SCeroSecSystem:checkPower()
	-- The machines that are on, taken before anything below settles one: a machine
	-- the automation switches on this minute has had everything done for it by
	-- settle and joins this list next minute, which is the order the single walk
	-- this replaces had too.
	local live = self:onMachineList()

	-- WAS THIS PREMISES AUTOMATED BEFORE THE OUTBREAK, for a computer whose square
	-- was made in this save and whose chunk is in so the question is answerable at
	-- all. FIRST in the sweep, and therefore ahead of cron's pass in the same
	-- minute (the event below calls checkPower and then checkCron): a crontab line
	-- that comes due this very minute has to find its lights already under /dev.
	--
	-- The square and not isLoaded(): what is wanted is a world to ask, and a
	-- machine on its way out of the system is one the answer would not survive.
	local fresh = machineList(self.newMachines)
	for i = 1, #fresh do
		local luaObject = fresh[i]
		if luaObject.born ~= true then
			-- Settled by somebody else since the index was written. One visit, and out.
			self:indexMachine(luaObject)
		elseif luaObject:getSquare() ~= nil then
			CeroSecAuto.settle(self, luaObject)
		end
	end

	for i = 1, #live do
		local luaObject = live[i]
		if luaObject.on ~= true then
			-- Dark since the index was written, and the index heals here.
			self:indexMachine(luaObject)
		else
			local loaded = luaObject:isLoaded()
			-- The rest of an automated premises' fixtures as their chunks arrive.
			-- Two table lookups for a machine this is not about (CeroSecAuto.wire).
			CeroSecAuto.wire(self, luaObject)
			-- A machine that has been running since before this rung, or one carried
			-- into a building while it was switched on, has no address yet. Asked only
			-- of a machine that has not got one, so the sweep costs nothing on a
			-- county where every computer is already numbered.
			if loaded and CeroSecOS.netRecord(luaObject.os) == nil then
				CeroSecNet.identify(self, luaObject, luaObject:osState())
			end
			-- The power decision is the machine's own, so that the sweep and a chunk
			-- coming back cannot disagree about it, and it is where the rule about an
			-- unloaded chunk lives: no square, no decision.
			local wentDark = luaObject:checkPower()
			if not wentDark and luaObject.watchers then
				for key, watcher in pairs(luaObject.watchers) do
					local playerObj = watcher.player
					if not playerObj or playerObj:isDead()
							or not isAdjacent(playerObj, luaObject.x, luaObject.y, luaObject.z) then
						luaObject.watchers[key] = nil
						if playerObj then
							self:replyClosed(playerObj, luaObject.x, luaObject.y, luaObject.z,
								"reach", watcher.token)
						end
						luaObject:publishOS()
					end
				end
				-- And the devices, for a machine somebody is standing at. Nothing on
				-- the glass moves -- a line already printed stays printed, here as on
				-- any terminal -- but the book of numbers catches up, so a window
				-- that was smashed or a door that was built while the screen was open
				-- already has its number by the time `ls /dev` is typed. A machine out
				-- of the world is skipped: /dev is the squares around it and there are
				-- none, so the walk would cost a chunk's worth of nothing.
				if loaded and luaObject.watchers then
					CeroSecDevices.refresh(luaObject, luaObject:osState())
				end
			end
		end
	end
end

-- cron's own minute hand.
--
-- Every machine that is ON, once a game minute: the same index the power check
-- walks, because the two ask the same question of the same list and a second walk
-- would only be a second chance to disagree about it.
--
-- The chunk is not one of the conditions, and that is the decision: a crontab is
-- the machine's own business and needs nothing of the world -- a script that
-- writes a file, mails a report or shuts the machine down runs as well out of
-- sight as in it. Only the lines that reach for /dev find the world gone, and
-- they are told "no such device" like any other line about a device out of
-- reach. (The pass USED to stop for a machine out of view, but only because the
-- power sweep switched such a machine off first, which was the bug above.)
function SCeroSecSystem:checkCron()
	local now = CeroSecOS.clockOf(self:clockEnv())
	if now == nil then return end
	local live = self:onMachineList()
	for i = 1, #live do
		local luaObject = live[i]
		if luaObject.on ~= true then
			self:indexMachine(luaObject)
		else
			CeroSecJobs.cronPass(self, luaObject, now)
			-- And the at queue, on the same sweep and the same minute: one walk of
			-- the list, because the two ask the same question of the same machines.
			CeroSecJobs.atPass(self, luaObject, now)
		end
	end
end

SGlobalObjectSystem.RegisterSystemClass(SCeroSecSystem)

Events.EveryOneMinute.Add(function()
	if SCeroSecSystem.instance then
		SCeroSecSystem.instance:checkPower()
		SCeroSecSystem.instance:checkCron()
	end
end)

-- Chunk loading does not fire OnObjectAdded, so register the computer sprites
-- with MapObjects the way the campfire does (MOCampfire.lua:42-44, 90-92).
local PRIORITY = 5

local function LoadComputer(isoObject)
	if not SCeroSecSystem.instance then return end
	SCeroSecSystem.instance:loadIsoObject(isoObject)
end

-- And the same object, the FIRST time this save has ever seen it. Two closures and
-- not one flag, because the two maps in MapObjects are what tells them apart and
-- nothing in the callback can: `onNew` is walked only for a chunk built out of the
-- map (IsoChunk.doLoadGridsquare, `if (this.addZombies)` at offsets 851-859) and
-- `onLoad` for every chunk there is, new or read back out of the save. The bytecode
-- and the one game-mode caveat are at the head of SCeroSecAuto.lua.
--
-- The adoption first and the bit afterwards, in that order: markBorn writes on the
-- GlobalObject and there is not one until loadIsoObject has made it.
local function NewComputer(isoObject)
	LoadComputer(isoObject)
	if not SCeroSecSystem.instance then return end
	SCeroSecSystem.instance:markBorn(isoObject)
end

for _, facing in ipairs(CeroSec.FACINGS) do
	MapObjects.OnNewWithSprite(CeroSec.SPRITES_OFF[facing], NewComputer, PRIORITY)
	MapObjects.OnLoadWithSprite(CeroSec.SPRITES_OFF[facing], LoadComputer, PRIORITY)
	MapObjects.OnNewWithSprite(CeroSec.SPRITES_ON[facing], NewComputer, PRIORITY)
	MapObjects.OnLoadWithSprite(CeroSec.SPRITES_ON[facing], LoadComputer, PRIORITY)
end
