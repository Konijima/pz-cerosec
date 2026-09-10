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
		if reason then CeroSec.log("console refused: " .. tostring(reason)) end
		return nil
	end
	return luaObject, state, console
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

SCeroSecSystem.BIOS_PROMPT = "Restore system? (y/n) "

-- The state, or nil when this machine has nothing to boot. Both halves of the
-- test in one place: a state the validator refuses (osState is nil) and a state
-- that runs but is no longer an operating system are the same thing to a BIOS.
function SCeroSecSystem:biosState(luaObject)
	local state = luaObject:osState()
	if state == nil then return nil end
	local ok, reason = CeroSecOS.systemOk(state)
	if not ok then
		CeroSec.log("no system at " .. luaObject.x .. "," .. luaObject.y .. ": " .. tostring(reason))
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
		self:askBios(console)
	else
		console.halted = nil
		CeroSec.consolePushAll(console, CeroSecOS.motdLines(state))
	end
	self:pushScreen(luaObject, state, console)
end

-- Whether an account wears the "#" prompt. nil (nobody logged in) is not one.
-- The prompt line, in one place. The user's home comes with it so that the
-- shell can say "~" instead of spelling out /home/admin on a thirty column
-- prompt -- the home is the account's, not a guess from the name.
function SCeroSecSystem:promptFor(state, console, hostname)
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

-- One screen, as a window has to be told it. The prompt is derived from the
-- console here and nowhere else, so no two windows can disagree about it.
function SCeroSecSystem:screenArgs(luaObject, state, console, token, playerObj)
	local hostname = self:hostnameOf(luaObject, state)
	return {
		x = luaObject.x, y = luaObject.y, z = luaObject.z,
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

-- The same answer the opener of a freshly switched on machine gets, but to
-- every window at once: a machine that has just rebooted is a machine every
-- pair of eyes in front of it watches type itself out again.
function SCeroSecSystem:pushOpened(luaObject, state, console)
	if not luaObject.watchers then return end
	for _, watcher in pairs(luaObject.watchers) do
		if watcher.player then
			local args = self:screenArgs(luaObject, state, console, watcher.token, watcher.player)
			args.animate = true
			self:reply(watcher.player, "opened", args)
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
	CeroSec.consolePushAll(console, CeroSec.BOOT_LINES)
	if state ~= nil then CeroSec.consolePushAll(console, CeroSecOS.motdLines(state)) end
	return true
end

--
-- Off, and off and on again
--
-- `shutdown` and `reboot` are the physical button typed instead of pressed, so
-- they go through the very same turnOff/turnOn -- the sprite, the sound, the
-- console thrown away -- and not through a second, quieter path beside it.
--
-- The one difference is the windows. Turning a machine off tells every terminal
-- open on it that it is over and forgets them, which is right for a machine
-- somebody switched off at the case and wrong for one that is coming back in
-- the same breath. So a reboot holds the watchers aside across the two calls
-- and hands them the new screen itself.
--

function SCeroSecSystem:reboot(luaObject)
	local watchers = luaObject.watchers
	luaObject.watchers = nil
	luaObject:turnOff()
	luaObject.watchers = watchers

	if not luaObject:turnOn() then
		-- The room lost its power between the two. The machine stays dark, and
		-- the windows are told what the power sweep would have told them.
		self:evictWatchers(luaObject, "power")
		return
	end

	local console = luaObject:consoleState()
	if not console then
		self:evictWatchers(luaObject, "power")
		return
	end
	local state = self:biosState(luaObject)
	self:bootScreen(console, state)
	-- A machine that went down broken comes back broken, and says so.
	if state == nil and not self:atBios(console) then self:askBios(console) end
	self:pushOpened(luaObject, state, console)
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
	end
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

Commands.open = function(self, playerObj, x, y, z, token)
	local luaObject, console = self:biosConsoleFor(playerObj, x, y, z, token)
	if not luaObject then return end

	local key = watcherKeyOf(playerObj, token)
	luaObject:addWatcher(key, playerObj, token)

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
	if state == nil and not self:atBios(console) then self:askBios(console) end

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
	local luaObject, console = self:biosConsoleFor(playerObj, x, y, z, token)
	if not luaObject then return end

	local text = args.text
	if type(text) ~= "string" then text = "" end

	-- The BIOS' question is answered before anything asks for a filesystem:
	-- there may not be one, and that is what is being asked about.
	if self:atBios(console) then
		self:answerBios(luaObject, console, playerObj, token, text)
		return
	end

	local state = luaObject:osState()
	if not state then
		self:replyClosed(playerObj, x, y, z, "broken", token)
		return
	end

	-- What the core ordered, if anything did. Declared out here because the
	-- power orders are carried out after the screen has gone out, and the
	-- branch that can produce one ends long before that.
	local order = nil

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
			CeroSec.consolePushAll(console, CeroSecOS.motdLines(state))
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
		local session = { user = console.user, cwd = console.cwd or "/", stamp = getTimestampMs() }
		local _, lines, control, data = CeroSecOS.continue(state, session, asked.cont, text)
		order = control
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
	-- `sudo shutdown` and `sudo reboot` end here, on the answer to the password
	-- question, and end the screen the same way they do at a shell.
	self:applyPower(luaObject, order)
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

	-- Enter on a line with no command in it prints nothing at all. A real
	-- terminal leaves the prompt row where it was and draws a new one under it,
	-- which is the same thing to look at; here the row being typed at is drawn
	-- by the window and is not part of the screen, so echoing an empty prompt
	-- would put a second, bare prompt line above it and push the live one down.
	local blank = string.find(line, "[^ \t]") == nil

	-- The session the core runs on is derived from the console and written back
	-- into it: cd is a move of the machine's cursor, not of anybody's.
	local session = { user = console.user, cwd = console.cwd or "/", stamp = getTimestampMs() }
	local prompt = self:promptFor(state, console)
	local _, lines, control, data = CeroSecOS.exec(state, session, line)
	console.user = session.user
	console.cwd = session.cwd
	luaObject:mirrorOS()

	if control == "exit" then
		CeroSec.consoleLogout(console)
	elseif control == "clear" then
		CeroSec.consoleClear(console)
	elseif not blank then
		CeroSec.consolePush(console, prompt .. line)
		CeroSec.consolePushAll(console, lines)
		self:applyOrder(console, control, data, playerObj)
	end

	self:pushScreen(luaObject, state, console)

	-- Last, and never before the push: the line that was typed goes onto every
	-- glass at the machine first, and the machine goes down after it. A screen
	-- that ends on "# shutdown" is what a second survivor standing there has to
	-- be left with.
	self:applyPower(luaObject, control)
end

-- The buffer as it stands, with the file untouched. Sent while it is being
-- typed so that the machine, and not the window, is what holds the work.
Commands.editbuf = function(self, playerObj, x, y, z, token, args)
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
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
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
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

	local session = self:editSession(console)
	local done, reason = CeroSecOS.writeFile(state, session, console.edit.path, text, false)
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
	local luaObject, state, console = self:consoleFor(playerObj, x, y, z, token)
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
	local luaObject, console = self:biosConsoleFor(playerObj, x, y, z, token)
	if not luaObject then return end

	local state = luaObject:osState()
	if not state then
		self:replyClosed(playerObj, x, y, z, "broken", token)
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
	console.prompt = nil
	console.pending = nil

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
