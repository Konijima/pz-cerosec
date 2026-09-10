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
--   toggle   {}                     -- rung 1
--   open     {}                     -- give me the screen
--   input    { text }               -- the answer to whatever is being asked:
--                                      a user name, a password, or the line a
--                                      command asked for. The console knows
--                                      which, and the client never has to.
--   exec     { line }
--   editbuf  { text }               -- the buffer as it stands, no file touched
--   editsave { text }               -- the buffer, and write it
--   editexit { }                    -- leave the editor, buffer dropped
--   close    {}
-- server -> client, every answer carrying the token of the terminal it belongs
-- to, because a connection is not a window:
--   opened  { x, y, z, token, hostname, booted, lines, prompt, mode, mask,
--             edit, animate }
--   screen  { x, y, z, token, hostname, booted, lines, prompt, mode, mask, edit }
--   closed  { x, y, z, token, reason }
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
-- vanilla keys per-player server state on (Bobber.lua:26).
local function idOf(playerObj)
	return tostring(playerObj:getOnlineID())
end

function SCeroSecSystem:hasWatcherWithId(luaObject, id)
	if not luaObject.watchers then return false end
	for _, watcher in pairs(luaObject.watchers) do
		if watcher.player and idOf(watcher.player) == id then return true end
	end
	return false
end

-- Take the keyboard on the open buffer, if it is going. It is going when
-- nobody holds it, or when the one who did is no longer standing here -- he
-- walked off, he died, he logged out of the game -- because an editor nobody
-- can type in is a machine nobody can use.
function SCeroSecSystem:claimEditor(luaObject, console, playerObj)
	local edit = console.edit
	if edit == nil then return false end
	local id = idOf(playerObj)
	if edit.by == id then return true end
	if edit.by ~= nil and self:hasWatcherWithId(luaObject, edit.by) then return false end
	edit.by = id
	return true
end

function SCeroSecSystem:isEditor(console, playerObj)
	return console.edit ~= nil and console.edit.by == idOf(playerObj)
end

-- The editor's half of a screen. The buffer as the machine holds it, the file
-- as it stands on the disk (so a window can say whether the two differ without
-- asking), and whether this window is the one that may type.
function SCeroSecSystem:editArgs(state, console, playerObj)
	local edit = console.edit
	if edit == nil then return nil end
	local disk = ""
	local session = { user = console.user, cwd = console.cwd or "/" }
	local node = CeroSecOS.getNode(state, session, edit.path)
	if node ~= nil and node.type == "file" then disk = node.data or "" end
	return {
		path = edit.path,
		text = edit.text or "",
		disk = disk,
		readonly = edit.readonly and true or false,
		message = edit.message,
		mine = self:isEditor(console, playerObj) and true or false,
	}
end

-- One screen, as a window has to be told it. The prompt is derived from the
-- console here and nowhere else, so no two windows can disagree about it.
function SCeroSecSystem:screenArgs(luaObject, state, console, token, playerObj)
	return {
		x = luaObject.x, y = luaObject.y, z = luaObject.z,
		token = token,
		hostname = state.hostname,
		booted = console.booted and true or false,
		lines = console.lines,
		prompt = CeroSec.consolePrompt(console, state.hostname,
			self:isAdmin(state, console.user)),
		mode = CeroSec.consoleMode(console),
		mask = CeroSec.consoleMask(console),
		edit = self:editArgs(state, console, playerObj),
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
				self:screenArgs(luaObject, state, console, watcher.token, watcher.player))
		end
	end
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
	end
end

-- A buffer a client sent. Nothing is believed on its word: it is text, it fits
-- the ceilings, and every line fits the screen -- the same three rules the
-- terminal enforces under the fingers, checked again here because the terminal
-- is the client. nil plus the line to show when it is not.
local function bufferOf(text)
	if type(text) ~= "string" then return nil, "Cannot edit: not text" end
	local refusal = CeroSec.editRefusal(text)
	if refusal ~= nil then return nil, refusal end
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

	-- An editor left open by somebody who is no longer here changes hands to
	-- whoever walks up next: a buffer nobody can type in is a dead machine.
	self:claimEditor(luaObject, console, playerObj)

	local args = self:screenArgs(luaObject, state, console, token, playerObj)
	args.animate = animate
	self:reply(playerObj, "opened", args)
	-- Somebody else may have been looking at the blank screen when it booted.
	if animate then self:pushScreen(luaObject, state, console, key) end
end

-- The answer to whatever is being asked. login, password and the line a command
-- asked for are one path: the console says which of them this is, and a window
-- that typed at a prompt that has since changed gets the screen back and
-- nothing else.
Commands.input = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
	if not luaObject then return end

	local text = args.text
	if type(text) ~= "string" then text = "" end

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
			console.user = session.user
			console.cwd = session.cwd
			CeroSec.consolePush(console, CeroSecOS.MOTD)
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
		local session = { user = console.user, cwd = console.cwd or "/" }
		local _, lines, control, data = CeroSecOS.continue(state, session, asked.cont, text)
		console.user = session.user
		console.cwd = session.cwd
		luaObject:mirrorOS()
		if control == "exit" then
			CeroSec.consoleLogout(console)
		elseif control == "clear" then
			CeroSec.consoleClear(console)
		else
			CeroSec.consolePushAll(console, lines)
			self:applyOrder(console, control, data, playerObj)
		end
	end
	self:pushScreen(luaObject, state, console)
end

Commands.exec = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
	if not luaObject then return end

	if CeroSec.consoleWaiting(console) ~= "shell" then
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
	local _, lines, control, data = CeroSecOS.exec(state, session, line)
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
		self:applyOrder(console, control, data, playerObj)
	end

	self:pushScreen(luaObject, state, console)
end

-- The buffer as it stands, with the file untouched. Sent while it is being
-- typed so that the machine, and not the window, is what holds the work.
Commands.editbuf = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
	if not luaObject then return end
	if not self:isEditor(console, playerObj) then
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
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
	if not luaObject then return end
	if not self:isEditor(console, playerObj) then
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

	local session = { user = console.user, cwd = console.cwd or "/" }
	local done, reason = CeroSecOS.writeFile(state, session, console.edit.path, text, false)
	if done == nil then
		console.edit.message = "Cannot save: " .. tostring(reason)
	else
		console.edit.message = "Saved " .. #text .. " bytes"
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
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
	if not luaObject then return end
	if not self:isEditor(console, playerObj) then
		self:pushScreen(luaObject, state, console)
		return
	end
	console.edit = nil
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
