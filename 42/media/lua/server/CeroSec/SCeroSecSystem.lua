if isClient() then return end

require "Map/SGlobalObjectSystem"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecIdentity"
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

	-- Fields of each GlobalObject that are saved to gos_cerosec.bin. 'os' is a
	-- nested table; the serializer recurses into those (KahluaTableImpl.save).
	self.system:setObjectModDataKeys({ 'v', 'on', 'facing', 'os' })

	-- Fields sent to clients on add/update. Without this the client mirror
	-- receives an empty table (SGlobalObjectNetwork saves only these keys).
	-- 'os' is deliberately absent: the client never reads the filesystem, it
	-- only ever sees the lines the server answers it with.
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

-- Who is typing: CeroSec.playerKey, shared with the client (CeroSecIdentity).
local playerKeyOf = CeroSec.playerKey

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
	args.player = playerKeyOf(playerObj)
	if isServer() then
		sendServerCommand(playerObj, SCeroSecSystem.MODULE, command, args)
	else
		self:sendCommand(command, args)
	end
end

-- Tell a terminal to shut itself: the machine is off, out of reach, or broken.
function SCeroSecSystem:replyClosed(playerObj, x, y, z, reason)
	self:reply(playerObj, "closed", { x = x, y = y, z = z, reason = reason })
end

--
-- Commands
--
-- client -> server, all of them carrying the computer's x, y, z:
--   toggle  {}                      -- rung 1
--   open    {}                      -- boot preamble, and is it on?
--   login   { name, password }
--   exec    { line }
--   close   {}
-- server -> client:
--   opened  { x, y, z, lines, hostname }
--   login   { x, y, z, ok, lines, prompt }
--   exec    { x, y, z, ok, lines, control, prompt }
--   closed  { x, y, z, reason }
--

local Commands = {}

-- The computer a command names, or nil after having told the player why not.
-- Every command re-checks the three things a terminal depends on: the computer
-- exists, the player is next to it, and it is on.
function SCeroSecSystem:computerFor(playerObj, args)
	if not args or not args.x then return nil end
	if not isAdjacent(playerObj, args.x, args.y, args.z) then
		self:replyClosed(playerObj, args.x, args.y, args.z, "reach")
		return nil
	end

	local luaObject = self:getLuaObjectAt(args.x, args.y, args.z)
	if not luaObject then
		-- The client saw a computer we have no GlobalObject for; adopt it.
		local isoObject = self:getIsoObjectAt(args.x, args.y, args.z)
		if isoObject then
			self:loadIsoObject(isoObject)
			luaObject = self:getLuaObjectAt(args.x, args.y, args.z)
		end
	end
	if not luaObject then
		self:replyClosed(playerObj, args.x, args.y, args.z, "gone")
		return nil
	end

	if not luaObject.on then
		self:replyClosed(playerObj, args.x, args.y, args.z, "off")
		return nil
	end
	return luaObject
end

Commands.toggle = function(self, playerObj, args)
	if not args or not args.x then return end
	if not isAdjacent(playerObj, args.x, args.y, args.z) then return end

	local luaObject = self:getLuaObjectAt(args.x, args.y, args.z)
	if not luaObject then
		local isoObject = self:getIsoObjectAt(args.x, args.y, args.z)
		if not isoObject then return end
		self:loadIsoObject(isoObject)
		luaObject = self:getLuaObjectAt(args.x, args.y, args.z)
		if not luaObject then return end
	end
	luaObject:toggle()
end

Commands.open = function(self, playerObj, args)
	local luaObject = self:computerFor(playerObj, args)
	if not luaObject then return end

	local state, reason = luaObject:osState()
	if not state then
		self:replyClosed(playerObj, args.x, args.y, args.z, "broken")
		return
	end

	-- A new terminal starts logged out, whatever the last one left behind.
	luaObject:closeSession(playerKeyOf(playerObj))

	self:reply(playerObj, "opened", {
		x = args.x, y = args.y, z = args.z,
		hostname = state.hostname,
		lines = CeroSecOS.fit({ CeroSecOS.MOTD }),
	})
	if reason then CeroSec.log("open: " .. tostring(reason)) end
end

Commands.login = function(self, playerObj, args)
	local luaObject = self:computerFor(playerObj, args)
	if not luaObject then return end

	local state = luaObject:osState()
	if not state then
		self:replyClosed(playerObj, args.x, args.y, args.z, "broken")
		return
	end

	local name = args.name
	if type(name) ~= "string" then name = "" end
	local password = args.password
	if type(password) ~= "string" then password = "" end

	local session, reason = CeroSecOS.login(state, name, password)
	if not session then
		luaObject:closeSession(playerKeyOf(playerObj))
		self:reply(playerObj, "login", {
			x = args.x, y = args.y, z = args.z,
			ok = false,
			lines = CeroSecOS.fit({ "login incorrect" }),
		})
		CeroSec.log("login refused: " .. tostring(reason))
		return
	end

	luaObject:openSession(playerKeyOf(playerObj), { session = session, player = playerObj })
	local user = CeroSecOS.getUser(state, session.user)
	self:reply(playerObj, "login", {
		x = args.x, y = args.y, z = args.z,
		ok = true,
		lines = CeroSecOS.fit({ CeroSecOS.MOTD }),
		prompt = CeroSec.prompt(session.user, state.hostname, session.cwd, user and user.admin),
	})
end

Commands.exec = function(self, playerObj, args)
	local luaObject = self:computerFor(playerObj, args)
	if not luaObject then return end

	local playerKey = playerKeyOf(playerObj)
	local open = luaObject:sessionFor(playerKey)
	if not open then
		self:replyClosed(playerObj, args.x, args.y, args.z, "session")
		return
	end

	local state = luaObject:osState()
	if not state then
		luaObject:closeSession(playerKey)
		self:replyClosed(playerObj, args.x, args.y, args.z, "broken")
		return
	end

	local line = args.line
	if type(line) ~= "string" then line = "" end

	local ok, lines, control = CeroSecOS.exec(state, open.session, line)
	luaObject:mirrorOS()

	if control == "exit" then luaObject:closeSession(playerKey) end

	local user = CeroSecOS.getUser(state, open.session.user)
	self:reply(playerObj, "exec", {
		x = args.x, y = args.y, z = args.z,
		ok = ok and true or false,
		lines = lines,
		control = control,
		prompt = CeroSec.prompt(open.session.user, state.hostname, open.session.cwd, user and user.admin),
	})
end

Commands.close = function(self, playerObj, args)
	if not args or not args.x then return end
	local luaObject = self:getLuaObjectAt(args.x, args.y, args.z)
	if not luaObject then return end
	luaObject:closeSession(playerKeyOf(playerObj))
end

function SCeroSecSystem:OnClientCommand(command, playerObj, args)
	local fn = Commands[command]
	if not fn then return end
	if not playerObj then return end
	fn(self, playerObj, args)
end

--
-- Housekeeping
--

-- Tell whoever was typing on this machine that it is over, then forget them.
function SCeroSecSystem:evictSessions(luaObject, reason)
	if not luaObject.sessions then return end
	for _, open in pairs(luaObject.sessions) do
		if open.player then
			self:replyClosed(open.player, luaObject.x, luaObject.y, luaObject.z, reason)
		end
	end
	luaObject:dropSessions()
end

-- Computers on a square that lost power shut themselves off, and a session
-- whose player has wandered off, died or left is not a session any more.
function SCeroSecSystem:checkPower()
	for i = 1, self:getLuaObjectCount() do
		local luaObject = self:getLuaObjectByIndex(i)
		if luaObject.on and not luaObject:hasPower() then
			self:evictSessions(luaObject, "power")
			luaObject:turnOff()
		elseif luaObject.sessions then
			for key, open in pairs(luaObject.sessions) do
				local playerObj = open.player
				if not playerObj or playerObj:isDead()
						or not isAdjacent(playerObj, luaObject.x, luaObject.y, luaObject.z) then
					luaObject.sessions[key] = nil
					if playerObj then
						self:replyClosed(playerObj, luaObject.x, luaObject.y, luaObject.z, "reach")
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
