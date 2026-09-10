if isClient() then return end

require "Map/SGlobalObjectSystem"
require "CeroSec/CeroSecDefs"
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

	-- Fields of this system that are saved.
	self.system:setModDataKeys(nil)

	-- Fields of each GlobalObject that are saved to gos_cerosec.bin. 'os' and
	-- 'console' are nested tables; the serializer recurses into those
	-- (KahluaTableImpl.save). The console is saved so that a screen survives a
	-- save and a reload the way it survives a player walking away: the machine
	-- is what remembers, not the session.
	self.system:setObjectModDataKeys({ 'v', 'on', 'facing', 'os', 'console' })

	-- Fields sent to clients on add/update. Without this the client mirror
	-- receives an empty table (SGlobalObjectNetwork saves only these keys).
	-- 'os' and 'console' are deliberately absent: the client never reads the
	-- filesystem nor the stored screen, it only ever sees the lines the server
	-- answers it with.
	self.system:setObjectSyncKeys({ 'v', 'on', 'facing' })
end

function SCeroSecSystem:newLuaObject(globalObject)
	return SCeroSecObject:new(self, globalObject)
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
--   toggle  {}                      -- rung 1
--   open    {}                      -- give me the screen
--   login   { text }                -- a user name, or a password: the console
--                                      knows which of the two it is waiting for
--   exec    { line }
--   close   {}
-- server -> client, every answer carrying the token of the terminal it belongs
-- to, because a connection is not a window:
--   opened  { x, y, z, token, hostname, booted, lines, prompt, mode, animate }
--   screen  { x, y, z, token, hostname, booted, lines, prompt, mode }
--   closed  { x, y, z, token, reason }
--
-- There is one answer for everything that happens on a screen, and it is the
-- whole screen. The server owns the console, so the client has nothing to
-- reconstruct and nothing to guess: it draws the lines it was handed, under the
-- prompt it was handed. 'opened' is that same payload plus the one thing only
-- the opener is told: whether the BIOS is still to be played.
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

-- The computer, its filesystem and its screen, or nil after having told the
-- player why not. Every path into a console goes through here.
function SCeroSecSystem:consoleFor(playerObj, x, y, z, token)
	-- A window with no usable token is a window nothing can be addressed to:
	-- every answer is matched on it, so there is nothing to answer here.
	if token == nil then return nil end
	local luaObject = self:computerFor(playerObj, x, y, z, token)
	if not luaObject then return nil end

	local state, reason = luaObject:osState()
	if not state then
		self:replyClosed(playerObj, x, y, z, "broken", token)
		if reason then CeroSec.log("console refused: " .. tostring(reason)) end
		return nil
	end

	local console = luaObject:consoleState()
	if not console then
		self:replyClosed(playerObj, x, y, z, "off", token)
		return nil
	end
	return luaObject, state, console
end

-- Whether an account wears the "#" prompt. nil (nobody logged in) is not one.
function SCeroSecSystem:isAdmin(state, name)
	if name == nil then return false end
	local user = CeroSecOS.getUser(state, name)
	return user ~= nil and user.admin and true or false
end

-- One screen, as a window has to be told it. The prompt is derived from the
-- console here and nowhere else, so no two windows can disagree about it.
function SCeroSecSystem:screenArgs(luaObject, state, console, token)
	return {
		x = luaObject.x, y = luaObject.y, z = luaObject.z,
		token = token,
		hostname = state.hostname,
		booted = console.booted and true or false,
		lines = console.lines,
		prompt = CeroSec.consolePrompt(console, state.hostname,
			self:isAdmin(state, console.user)),
		mode = CeroSec.consoleMode(console),
	}
end

-- The screen changed: hand it to every window open on this computer. The
-- requester is one of them and is answered here like the others, by its own
-- token -- there is no private half of a screen anybody is standing in front of.
function SCeroSecSystem:pushScreen(luaObject, state, console, exceptKey)
	if not luaObject.watchers then return end
	for key, watcher in pairs(luaObject.watchers) do
		if watcher.player and key ~= exceptKey then
			self:reply(watcher.player, "screen",
				self:screenArgs(luaObject, state, console, watcher.token))
		end
	end
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

Commands.open = function(self, playerObj, x, y, z, token)
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
	if not luaObject then return end

	local key = watcherKeyOf(playerObj, token)
	luaObject:addWatcher(key, playerObj, token)

	-- The BIOS belongs to the power-on, not to the window: the first player to
	-- open a machine that has just been switched on watches it type itself out,
	-- and it is then on the screen for whoever opens it next.
	local animate = not console.booted
	if animate then
		console.booted = true
		CeroSec.consolePushAll(console, CeroSec.BOOT_LINES)
		CeroSec.consolePush(console, CeroSecOS.MOTD)
	end

	local args = self:screenArgs(luaObject, state, console, token)
	args.animate = animate
	self:reply(playerObj, "opened", args)
	-- Somebody else may have been looking at the blank screen when it booted.
	if animate then self:pushScreen(luaObject, state, console, key) end
end

Commands.login = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
	if not luaObject then return end

	local text = args.text
	if type(text) ~= "string" then text = "" end

	local mode = CeroSec.consoleMode(console)
	if mode == "login" then
		-- The name is echoed and remembered; nothing is judged until the
		-- password is in, so an unknown name looks exactly like a known one.
		if text ~= "" then
			CeroSec.consolePush(console, "login: " .. text)
			console.pending = text
		end
	elseif mode == "password" then
		local name = console.pending
		console.pending = nil
		CeroSec.consolePush(console, CeroSec.maskedLine("password: ", text))
		local session, reason = CeroSecOS.login(state, name, text)
		if session then
			console.user = session.user
			console.cwd = session.cwd
			CeroSec.consolePush(console, CeroSecOS.MOTD)
		else
			-- One answer for a bad name and for a bad password alike: the
			-- machine does not say which half was wrong.
			CeroSec.consolePush(console, "login incorrect")
			CeroSec.log("login refused: " .. tostring(reason))
		end
	end
	-- A window that typed at the wrong prompt gets the screen back and nothing
	-- else: the console is what decides what it is waiting for.
	self:pushScreen(luaObject, state, console)
end

Commands.exec = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
	if not luaObject then return end

	if CeroSec.consoleMode(console) ~= "shell" then
		self:pushScreen(luaObject, state, console)
		return
	end

	local line = args.line
	if type(line) ~= "string" then line = "" end

	-- The session the core runs on is derived from the console and written back
	-- into it: cd is a move of the machine's cursor, not of anybody's.
	local session = { user = console.user, cwd = console.cwd or "/" }
	local prompt = CeroSec.consolePrompt(console, state.hostname,
		self:isAdmin(state, console.user))
	local _, lines, control = CeroSecOS.exec(state, session, line)
	console.user = session.user
	console.cwd = session.cwd
	luaObject:mirrorOS()

	if control == "exit" then
		CeroSec.consoleLogout(console)
	elseif control == "clear" then
		CeroSec.consoleClear(console)
	else
		CeroSec.consolePush(console, prompt .. line)
		CeroSec.consolePushAll(console, lines)
	end

	self:pushScreen(luaObject, state, console)
end

Commands.close = function(self, playerObj, x, y, z, token)
	if token == nil then return end
	local luaObject = self:getLuaObjectAt(x, y, z)
	if not luaObject then return end
	luaObject:removeWatcher(watcherKeyOf(playerObj, token))
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

function SCeroSecSystem:OnClientCommand(command, playerObj, args)
	local fn = Commands[command]
	if not fn then return end
	if not playerObj then return end
	local x, y, z = coordsOf(args)
	if not x then return end
	fn(self, playerObj, x, y, z, tokenOf(args), args)
end

--
-- Housekeeping
--

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
function SCeroSecSystem:checkPower()
	for i = 1, self:getLuaObjectCount() do
		local luaObject = self:getLuaObjectByIndex(i)
		if luaObject.on and not luaObject:hasPower() then
			self:evictWatchers(luaObject, "power")
			luaObject:turnOff()
		elseif luaObject.watchers then
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
		end
	end
end

SGlobalObjectSystem.RegisterSystemClass(SCeroSecSystem)

Events.EveryOneMinute.Add(function()
	if SCeroSecSystem.instance then SCeroSecSystem.instance:checkPower() end
end)

-- Chunk loading does not fire OnObjectAdded, so register the computer sprites
-- with MapObjects the way the campfire does (MOCampfire.lua:42-44, 90-92).
local PRIORITY = 5

local function LoadComputer(isoObject)
	if not SCeroSecSystem.instance then return end
	SCeroSecSystem.instance:loadIsoObject(isoObject)
end

for _, facing in ipairs(CeroSec.FACINGS) do
	MapObjects.OnNewWithSprite(CeroSec.SPRITES_OFF[facing], LoadComputer, PRIORITY)
	MapObjects.OnLoadWithSprite(CeroSec.SPRITES_OFF[facing], LoadComputer, PRIORITY)
	MapObjects.OnNewWithSprite(CeroSec.SPRITES_ON[facing], LoadComputer, PRIORITY)
	MapObjects.OnLoadWithSprite(CeroSec.SPRITES_ON[facing], LoadComputer, PRIORITY)
end
