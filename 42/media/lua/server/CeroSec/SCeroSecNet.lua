if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSNet"

--
-- The link layer, and the sessions on it.
--
-- The engine knows what a name means, what an address looks like and what a
-- trust file says. It does not and cannot know whether two computers can hear
-- each other, because that is a question about the WORLD: which building each
-- one stands in, and whether either has power. This file answers it, and it is
-- the only half of the network that knows there is a game.
--
-- The rule for this rung is one wire and nothing else: Ethernet between the
-- computers of ONE map building, both switched on. A later rung adds the phone
-- line and the radio by adding a second answer here -- reachable() -- and
-- changes no command and no engine file, which is the promise the manual makes.
--
--
-- WHY A MACHINE ANSWERS WITH ITS CHUNK UNLOADED
--
-- The whole of this rung rests on one fact about the server, so it is written
-- down here rather than assumed. SGlobalObjectSystem holds every global object
-- of its own kind for the whole map, not the loaded part of it:
--
--   * zombie.globalObjects.SGlobalObjects reads gos_<name>.bin whole at server
--     start and hands the objects to the Lua system, which builds one Lua object
--     per global object (SGlobalObjectSystem:initLuaObjects, called from
--     loadLuaObjects) -- so getLuaObjectCount() is every computer in Knox
--     County that has ever been switched on, not every computer in memory.
--   * SGlobalObject:getIsoObject() answers nil for one whose chunk is not
--     loaded: it goes through the cell's grid square, and an unloaded square is
--     not there. That is exactly why SCeroSecObject guards every call on it.
--
-- So a machine's DISK, its power flag and the record of its address are all
-- readable whatever the streamer is doing, and only three things on this rung
-- need the chunk: the power check (a square), /dev (the objects on the squares)
-- and working out which building a computer stands in. The first two already
-- guard themselves; the third is done once, when the machine is switched on,
-- and the answer is written into the machine's own state (CeroSecOS.netRecord)
-- so that nothing ever has to ask again.
--
-- tests/window_test.lua has a machine whose getIsoObject() and getSquare() both
-- answer nil and which still answers ruptime, ping and rlogin.
--

CeroSecNet = CeroSecNet or {}

--
-- Identity
--

-- The building a computer stands in, as two numbers that do not move: the
-- corner of its BuildingDef. The def and not the IsoBuilding, because
-- IsoBuilding.id is handed out by a counter at load time (idCount) and is a
-- different number next session, while def.getX() and def.getY() are where the
-- building is on the map.
--
-- nil for a computer in no building at all, which is what a player-built base
-- is: no wire, and every command says so.
function CeroSecNet.buildingOf(luaObject)
	local square = luaObject:getSquare()
	if square == nil then return nil end
	local building = square:getBuilding()
	if building == nil then return nil end
	local def = building:getDef()
	if def == nil then return nil end
	return def:getX(), def:getY()
end

-- Every machine the server holds, which is every machine in the county that has
-- ever been switched on -- loaded chunk or not (see the head of this file).
local function each(system, fn)
	for i = 1, system:getLuaObjectCount() do
		local other = system:getLuaObjectByIndex(i)
		if other ~= nil then
			local stop = fn(other)
			if stop ~= nil then return stop end
		end
	end
	return nil
end

-- The address record on a machine, read out of the state RAW -- through the
-- engine's own tolerant accessor and not through osState(). That is deliberate:
-- osState migrates, tops up and validates a whole filesystem, and a ping that
-- did it once per computer in the county would be a ping that walked every disk
-- on the map. The record is three numbers and reading it wrongly is impossible;
-- netRecord answers nil for anything that is not one.
local function recordOf(luaObject)
	return CeroSecOS.netRecord(luaObject.os)
end

-- The machine an address names, and its record. nil when no computer the server
-- holds answers to it.
function CeroSecNet.at(system, addr)
	return each(system, function(other)
		local net = recordOf(other)
		if net ~= nil and CeroSecOS.addressText(net.b1, net.b2, net.n) == addr then
			return { object = other, net = net }
		end
		return nil
	end)
end

-- Which computer of its building this one is. The lowest number nobody in the
-- same building has, exactly as a device number is the lowest its kind has never
-- used -- and once it is written into the state it is never moved: a survivor
-- who wrote 10.4.17.3 in /etc/hosts wrote down a machine and not a position in a
-- list.
local function freeNumber(system, luaObject, b1, b2)
	local taken = {}
	each(system, function(other)
		if other ~= luaObject then
			local net = recordOf(other)
			if net ~= nil and net.b1 == b1 and net.b2 == b2 then taken[net.n] = true end
		end
		return nil
	end)
	for n = 1, 254 do
		if not taken[n] then return n end
	end
	return nil
end

-- Give this machine its address, if it has not got one for the building it is
-- standing in now. Answers true when it wrote one.
--
-- Called when a computer is switched on and when a window opens on it, which are
-- the two moments the chunk is certainly loaded. A machine carried into another
-- building is renumbered the next time either happens -- the b1/b2 it carries no
-- longer match where it stands -- and one carried out of every building keeps
-- the record it had until it is put back inside one, because there is nothing to
-- replace it with and a machine with no address at all is not something to
-- invent.
function CeroSecNet.identify(system, luaObject, state)
	if state == nil then return false end
	local bx, by = CeroSecNet.buildingOf(luaObject)
	if bx == nil then return false end
	local b1, b2 = CeroSecOS.buildingKey(bx, by)
	if b1 == nil then return false end

	local net = CeroSecOS.netRecord(state)
	if net ~= nil and net.b1 == b1 and net.b2 == b2 then return false end

	local n = freeNumber(system, luaObject, b1, b2)
	if n == nil then return false end
	if CeroSecOS.setNetRecord(state, b1, b2, n) == nil then return false end
	-- And the machine's own line in /etc/hosts, once. After this the file is the
	-- player's: a name he added stays, a line he deleted stays deleted.
	CeroSecOS.writeOwnHost(state, CeroSecOS.clockOf(system:clockEnv()))
	luaObject:mirrorOS()
	return true
end

--
-- Reachability
--

-- Can `from` hear the machine at `addr` right now?
-- the machine, or nil plus which of strerror's words to wear:
--   "down"    it is on this wire and it is switched off
--   "unreach" there is no wire between here and there at all
function CeroSecNet.reachable(system, from, addr)
	-- The loopback reaches this machine and nothing else, whatever building it is
	-- in and whether it has a wire at all -- which is what a loopback is. The
	-- engine already answers a ping on it; this is the other half, so that
	-- `rlogin localhost` opens a second session on the machine one is sitting at
	-- rather than being refused by a link layer that was looking for a cable.
	if addr == CeroSecOS.LOOPBACK_ADDR then
		if not from.on then return nil, "down" end
		return from
	end
	local mine = recordOf(from)
	if mine == nil then return nil, "unreach" end
	local found = CeroSecNet.at(system, addr)
	if found == nil then return nil, "unreach" end
	-- The Ethernet rule, and the whole of it: the same map building.
	if found.net.b1 ~= mine.b1 or found.net.b2 ~= mine.b2 then return nil, "unreach" end
	if not found.object.on then return nil, "down" end
	return found.object
end

-- Every machine on this one's wire that is switched on, itself included.
local function wire(system, from)
	local mine = recordOf(from)
	local out = {}
	if mine == nil then return out end
	each(system, function(other)
		local net = recordOf(other)
		if net ~= nil and net.b1 == mine.b1 and net.b2 == mine.b2 and other.on then
			out[#out + 1] = other
		end
		return nil
	end)
	return out
end

--
-- Who is logged in on one machine
--
-- The survivor at the keyboard is on the console; everybody who came in over the
-- wire is on his pty, with the machine he came from beside him. One list, and
-- who(1), rwho(1) and ruptime(1)'s user count are all read out of it.
--

function CeroSecNet.sessions(luaObject)
	local out = {}
	local console = luaObject.console
	if type(console) == "table" and type(console.user) == "string" then
		out[#out + 1] = { user = console.user, line = CeroSecOS.CONSOLE_LINE,
			at = console.loginAt or 0 }
	end
	local ptys = CeroSecOS.ptyList(luaObject.ptys)
	for i = 1, #ptys do
		local pty = ptys[i]
		local screen = pty.console
		if type(screen) == "table" and type(screen.user) == "string" then
			out[#out + 1] = { user = screen.user, line = pty.line,
				at = screen.loginAt or 0, host = pty.fromHost }
		end
	end
	return out
end

-- What ruptime calls the load: how many jobs the machine has that could run.
-- Which is what a load average has counted since the first one -- and it is not
-- an average, because nothing here smooths anything over a minute.
local function loadOf(luaObject)
	if luaObject.jobs == nil then return 0 end
	return CeroSecOS.liveJobs(luaObject.jobs.list)
end

-- How long it has been up, in seconds. Wall clock from the moment it was
-- switched on, and RUNTIME state like the jobs: a server that came back up
-- forgets when a machine was switched on, so ruptime counts from the restart.
-- That is the same answer the jobs give and it is in the manual.
local function upOf(luaObject, nowMs)
	if type(luaObject.upMs) ~= "number" or type(nowMs) ~= "number" then return 0 end
	local up = math.floor((nowMs - luaObject.upMs) / 1000)
	if up < 0 then return 0 end
	return up
end

--
-- What the engine is handed
--

-- One machine's link layer, built fresh for every line typed -- like the devices
-- beside it, because both are answers about a moment: what is on the wire right
-- now, and who is sitting at it right now.
function CeroSecNet.envFor(system, luaObject, state)
	local nowMs = getTimestampMs()
	return {
		reach = function(addr)
			local object, why = CeroSecNet.reachable(system, luaObject, addr)
			if object == nil then return false, why end
			return true, nil
		end,

		peers = function()
			local list = wire(system, luaObject)
			local out = {}
			for i = 1, #list do
				local other = list[i]
				-- The peer's own disk, because its name is in its own
				-- /etc/hostname. A machine whose state will not validate is a
				-- machine nothing can be said about, and it is left out.
				local theirs = other:osState()
				if theirs ~= nil then
					local who = CeroSecNet.sessions(other)
					out[#out + 1] = {
						host = CeroSecOS.hostname(theirs),
						addr = CeroSecOS.address(theirs),
						up = upOf(other, nowMs),
						users = #who,
						load = loadOf(other),
						who = who,
					}
				end
			end
			return out
		end,

		sessions = function()
			return CeroSecNet.sessions(luaObject)
		end,

		copy = function(spec)
			return CeroSecNet.copy(system, luaObject, state, spec)
		end,
	}
end

--
-- rcp
--
-- One file across the wire, and both ends of it are judged by their own machine:
-- the read by the source's permissions, the write by the target's permissions,
-- its 4096-byte file ceiling and its own 32K disk. There is no privilege
-- anywhere in it -- the account it runs as on the far machine is the account it
-- was on this one, which is what rcp over rsh has always been.
--
-- Trust is required and no password is ever asked, because rcp runs over rshd
-- and rshd does not ask: a machine that does not trust this one answers
-- Permission denied and that is the whole of it.
--

-- The far machine, its state, and the session the copy runs under there.
-- nil plus the reason when the copy cannot happen at all.
local function farEnd(system, luaObject, spec)
	local object = CeroSecNet.reachable(system, luaObject, spec.addr)
	if object == nil then return nil, CeroSecOS.NET_REASON.unreach end
	local state = object:osState()
	if state == nil then return nil, CeroSecOS.NET_REASON.unreach end
	if not CeroSecOS.trusts(state, spec.user, spec.fromHost, spec.user) then
		return nil, CeroSecOS.NET_REASON.denied
	end
	-- The account has to exist over there, and rsh's word for one that does not
	-- is the same as for one that is not trusted: rshd answers a name it cannot
	-- become exactly as it answers a name it will not become.
	local account = CeroSecOS.getUser(state, spec.user)
	if account == nil then return nil, CeroSecOS.NET_REASON.denied end
	local cwd = "/"
	if type(account.home) == "string" then cwd = account.home end
	return object, state, { user = spec.user, cwd = cwd, stamp = getTimestampMs() }
end

-- ok, reason, bytes.
function CeroSecNet.copy(system, luaObject, state, spec)
	if type(spec) ~= "table" then return false, CeroSecOS.NET_REASON.unreach end
	local object, far, session = farEnd(system, luaObject, spec)
	if object == nil then return false, far end

	local here = { user = spec.user, cwd = "/", stamp = getTimestampMs() }
	-- The local end runs as the account that typed the line and in the directory
	-- it typed it from; the engine handed over the paths already expanded, so
	-- what is left is to read one side and write the other.
	if type(spec.cwd) == "string" then here.cwd = spec.cwd end

	local now = CeroSecOS.clockOf(system:clockEnv())
	local text = nil
	if spec.push then
		local node, reason = CeroSecOS.getNode(state, here, spec["local"])
		if node == nil then return false, reason end
		if node.type ~= "file" then return false, CeroSecOS.notAFile(node) end
		if not CeroSecOS.can(state, here, node, "r") then return false, "permission denied" end
		text = node.data or ""
		local done, wreason = CeroSecOS.writeFile(far, session, spec.remote, text, false, now)
		if done == nil then return false, wreason end
		object:mirrorOS()
	else
		local node, reason = CeroSecOS.getNode(far, session, spec.remote)
		if node == nil then return false, reason end
		if node.type ~= "file" then return false, CeroSecOS.notAFile(node) end
		if not CeroSecOS.can(far, session, node, "r") then return false, "permission denied" end
		text = node.data or ""
		local done, wreason = CeroSecOS.writeFile(state, here, spec["local"], text, false, now)
		if done == nil then return false, wreason end
		luaObject:mirrorOS()
	end
	return true, nil, #text
end

--
-- The sessions
--
-- A remote session is a pty on the far machine with its SCREEN on this one. The
-- pty carries a console of its own -- the same table a machine's own console is,
-- so that everything that already knows what a console is works on it unchanged:
-- the login prompt, the shell, the editor, Escape, the su stack, $? and the
-- shell's variables. What is on it that a machine's own console has not got:
--
--   watchAt  the machine whose windows are looking at it, so a screen pushed by
--            the far machine's scheduler reaches the glass it belongs to
--   line     the name of the pty, which is what `who` prints, what goes into the
--            far machine's wtmp, and what tags every job the session starts
--   hops     how many rlogins deep it is
--
-- The console that DIALLED carries the other half, `remote`: which machine and
-- which line this glass is showing. Neither field is saved -- a pty is runtime
-- state like a job, and a machine that comes back from a reload comes back at
-- its own prompt with nothing open.
--
-- THE LINES ARE ONE GLASS. A pty's console starts with a copy of the lines the
-- dialling console had, and when the session ends they go back the other way. So
-- a survivor sees one unbroken screen -- his own prompt, the rlogin he typed,
-- the far machine's login, the far machine's work, and then his own prompt again
-- with all of it still above -- which is what a real terminal shows, because a
-- real rlogin never had a second screen to put anything on.
--

-- What rlogin says when a session is over. A real rlogin says nothing at all and
-- lets your own shell prompt tell you; here the two prompts look alike -- the
-- same green screen, the same shape -- so the machine says the line telnet says
-- about the same event. It is the one string on this rung that is a choice, and
-- the manual says so.
CeroSecNet.CLOSED = "Connection closed."

-- The pty a console is looking at, the machine it is on, and that machine's
-- state. nil when the far end has gone: switched off, picked up, or the session
-- closed from the other side.
function CeroSecNet.farOf(system, console)
	local handle = console.remote
	if type(handle) ~= "table" then return nil end
	local object = system:getLuaObjectAt(handle.x, handle.y, handle.z)
	if object == nil or not object.on then return nil end
	local pty = CeroSecOS.remoteLine(object.ptys, handle.line)
	if pty == nil then return nil end
	local far = object:osState()
	if far == nil then return nil end
	return pty, object, far
end

-- The console that dialled a pty, and the machine it is on. Named on the pty
-- itself rather than worked out, because a chain of rlogins means the dialler may
-- be another machine's pty and not its own screen.
function CeroSecNet.diallerOf(system, pty)
	local from = pty.from
	if type(from) ~= "table" then return nil end
	local object = system:getLuaObjectAt(from.x, from.y, from.z)
	if object == nil then return nil end
	if from.line == nil then return object.console, object end
	local other = CeroSecOS.remoteLine(object.ptys, from.line)
	if other == nil then return nil end
	return other.console, object
end

-- A DETACHED session, and where what it printed goes.
--
-- rsh from a crontab line or from behind a `&` is a session nobody is watching:
-- the job that dialled it had no terminal, so the console the order arrived with
-- is the machine's own glass and has nothing to do with the command. Such a
-- session gets a console of its own with no copy of that glass on it, marked
-- `noTty` -- and a console marked `noTty` is never pushed to a window
-- (SCeroSecSystem:pushScreen), which is what makes it a sheet of paper rather
-- than a second screen.
--
-- When it ends, the sheet is delivered where everything else the job printed
-- went: the account's mailbox for a cron line, and the job's own lines on the
-- glass for a `&`, which is exactly what a `&` has always been allowed to do.
-- The job on a machine that is waiting for one of these, by id. Over is gone: a
-- job that was killed while its rsh was still out there is not a job to write to.
local function waitingJob(luaObject, id)
	if luaObject == nil or type(id) ~= "number" then return nil end
	local book = luaObject.jobs
	if book == nil then return nil end
	for i = 1, #book.list do
		local job = book.list[i]
		if job.id == id and not CeroSecOS.jobIsOver(job) then return job end
	end
	return nil
end

local function deliver(system, homeObject, home, spec, lines, status, failed)
	-- The job that is WAITING for this, which is every rsh: its lines go through
	-- its own output door -- the glass, the pipe, the word a $(...) is collecting,
	-- the mail for a cron line -- and its status is the far command's. Asked first,
	-- and it answers for the whole delivery: a job waiting on an rsh is where the
	-- answer belongs, and there is nowhere else for it to go.
	local job = waitingJob(homeObject, spec.job)
	if job ~= nil then
		-- The near machine's own state and env go with it: a `>` on the rsh opened
		-- its file when the order was given and the far machine's lines are what
		-- belong in it, and that write is the near machine's disk.
		CeroSecOS.jobRemote(job, lines, status, failed, homeObject:osState(),
			system:execEnv(homeObject, homeObject:osState()))
		if homeObject ~= nil then homeObject:mirrorOS() end
		return
	end
	if type(lines) ~= "table" or #lines == 0 then return end
	local state = nil
	if homeObject ~= nil then state = homeObject:osState() end
	if spec.mailTo ~= nil and state ~= nil then
		CeroSecOS.mailAppend(state, spec.mailTo, CeroSecOS.hostname(state), spec.cmd,
			lines, CeroSecOS.clockOf(system:clockEnv()))
		homeObject:mirrorOS()
		return
	end
	if type(home) ~= "table" then return end
	for i = 1, #lines do CeroSec.consolePush(home, lines[i]) end
	if homeObject ~= nil then system:pushScreen(homeObject, state, home) end
end

-- Is the order a dial nobody is standing behind? Either the engine said so --
-- the job that gave it had no controlling terminal -- or the console it was
-- given on is itself a detached one, because a detached session's own dials are
-- no more watched than it is.
local function detachedDial(console, data)
	if type(data) == "table" and type(data.noTty) == "table" then return data.noTty end
	if type(console) == "table" and console.noTty then return { } end
	return nil
end

-- The one teardown, whichever end asked for it.
--
-- The line comes off the far machine's pty table, its logout goes into the far
-- machine's wtmp, everything it was running stops, the screen goes back to the
-- console that dialled -- with every line the session printed still on it -- and
-- that console is told in rlogin's own words.
--
-- Answers true when there was a session to end.
function CeroSecNet.tearDown(system, object, line)
	local pty = CeroSecOS.remoteLine(object.ptys, line)
	if pty == nil then return false end
	local screen = pty.console
	local user = nil
	if type(screen) == "table" then user = screen.user end

	-- Anything the far machine was running for this session goes with it, the
	-- way a rlogind that lost its connection takes the shell with it.
	CeroSecNet.killPty(object, line)
	local far = object:osState()
	if far ~= nil then
		CeroSecOS.remoteClose(far, object.ptys, line, user,
			CeroSecOS.clockOf(system:clockEnv()))
		object:mirrorOS()
	else
		object.ptys[line] = nil
	end

	local home, homeObject = CeroSecNet.diallerOf(system, pty)
	if pty.noTty ~= nil then
		-- A session nobody watched. What it printed is delivered -- into the job
		-- that is waiting for it, which is every rsh -- and the console it was
		-- dialled FROM is left exactly as it is: its `remote` was never set to this
		-- line, and a survivor may well have a session of his own on it.
		--
		-- The status goes with the lines. It is the far command's own, kept on the
		-- pty's console when its job was reaped (runMachine), and it is what `$?`
		-- after an rsh answers. No status at all means nothing ever ran over there
		-- -- a shell the far machine has not got, a machine with no room for the
		-- job -- and rsh answers 1 for that, the way it answers 1 for a connection
		-- it could not make.
		local lines, status = nil, nil
		if type(screen) == "table" then
			lines = screen.lines
			status = tonumber(screen.status)
		end
		if status == nil then status = 1 end
		deliver(system, homeObject, home, pty.noTty, lines, status)
	elseif home ~= nil then
		home.remote = nil
		-- The one glass: what the session printed is what is on the screen.
		if type(screen) == "table" and type(screen.lines) == "table" then
			home.lines = screen.lines
		end
		-- An rsh is one command and not a login, so it says nothing when it is
		-- done: no rsh anybody has ever run printed "Connection closed.".
		if not pty.quiet then CeroSec.consolePush(home, CeroSecNet.CLOSED) end
		if homeObject ~= nil then
			system:pushScreen(homeObject, homeObject:osState(), home)
		end
	end
	return true
end

-- Every job the far machine was running for one pty, gone. A shell whose
-- terminal has been taken away has nothing to write to.
function CeroSecNet.killPty(luaObject, line)
	local book = luaObject.jobs
	if book == nil then return end
	for i = 1, #book.list do
		local job = book.list[i]
		if job.pty == line then CeroSecOS.killJob(job, nil) end
	end
end

-- The near end hanging up: Escape at an idle remote prompt, or the machine this
-- glass is on going dark.
function CeroSecNet.hangUp(system, console)
	local handle = console.remote
	if type(handle) ~= "table" then return false end
	local object = system:getLuaObjectAt(handle.x, handle.y, handle.z)
	if object == nil then
		console.remote = nil
		return true
	end
	return CeroSecNet.tearDown(system, object, handle.line)
end

-- The far end hanging up: `exit` on the far machine's own prompt, which is the
-- end of the shell rlogind started and therefore the end of the connection.
-- Answers true when this console was a session's, so that the ordinary logout
-- does not also happen.
function CeroSecNet.endSession(system, luaObject, console)
	if type(console) ~= "table" or type(console.line) ~= "string" then return false end
	return CeroSecNet.tearDown(system, luaObject, console.line)
end

-- Is this screen an rsh's, whose one command is what the session was for?
function CeroSecNet.isOneShot(luaObject, console)
	if type(console) ~= "table" or type(console.line) ~= "string" then return false end
	local pty = CeroSecOS.remoteLine(luaObject.ptys, console.line)
	if pty == nil then return false end
	return pty.quiet and true or false
end

-- A machine going dark, or being picked up: every session ON it ends, and so
-- does every session it had OPEN somewhere else. Run BEFORE the console is
-- thrown away, because the console is what remembers where they went.
function CeroSecNet.closeSessions(system, luaObject)
	-- The sessions its JOBS had open first. An rsh is a job waiting for another
	-- machine and holding a line over there, and a machine that has stopped is not
	-- waiting for anything: it is called before killAll takes the book away
	-- (SCeroSecObject), because the book is what remembers where those lines are.
	local book = luaObject.jobs
	if book ~= nil then
		for i = 1, #book.list do
			local job = book.list[i]
			local at = job.remote
			if type(at) == "table" then
				job.remote = nil
				local object = system:getLuaObjectAt(at.x, at.y, at.z)
				if object ~= nil then CeroSecNet.tearDown(system, object, at.line) end
			end
		end
	end
	if type(luaObject.console) == "table" then
		CeroSecNet.hangUp(system, luaObject.console)
	end
	local ptys = CeroSecOS.ptyList(luaObject.ptys)
	for i = 1, #ptys do
		local screen = ptys[i].console
		if type(screen) == "table" then CeroSecNet.hangUp(system, screen) end
	end
	-- And the inbound ones, which have to be told one at a time: each has a
	-- different glass at the other end of it.
	ptys = CeroSecOS.ptyList(luaObject.ptys)
	for i = 1, #ptys do
		CeroSecNet.tearDown(system, luaObject, ptys[i].line)
	end
	luaObject.ptys = nil
end

--
-- Dialling
--
-- What the "rlogin" and "rsh" orders come to. Everything the engine could decide
-- it already has -- the name resolved, the wire reached, the hop ceiling paid --
-- so what is left is the two things only the far machine knows: whether it has a
-- line free, and whether it trusts this one.
--

-- The machine whose windows are looking at a console: its own, normally, and for
-- a pty's console the machine at the near end of the chain, which is where the
-- window really is.
function CeroSecNet.watchAtOf(luaObject, console)
	local at = console.watchAt
	if type(at) == "table" then return { x = at.x, y = at.y, z = at.z } end
	return { x = luaObject.x, y = luaObject.y, z = luaObject.z }
end

-- The console a dialled session lands on: a real console, with the fields that
-- say whose glass it is on, what the line is called and how deep the chain is --
-- and with a copy of the lines already on that glass, because there is only one
-- glass (see the head of this section).
local function newPtyConsole(from, pty, watchAt, hops)
	local console = CeroSec.newConsole()
	-- No BIOS on a pty. The boot belongs to the power-on and the machine is
	-- already up: what a caller meets is the login prompt.
	console.booted = true
	console.watchAt = watchAt
	console.line = pty.line
	console.hops = hops
	if type(from) == "table" and type(from.lines) == "table" then
		for i = 1, #from.lines do
			CeroSec.consolePush(console, from.lines[i])
		end
	end
	return console
end

-- A session logged in, with a password or without one. Exactly what
-- Commands.input does when a password is right, so the two cannot drift: the
-- greeting, the account, a fresh shell, the moment, and the line in wtmp.
function CeroSecNet.logIn(system, object, far, pty, account, now)
	local console = pty.console
	console.user = account.name
	console.cwd = account.home or "/"
	console.stack = nil
	console.shvars = CeroSecOS.loginVars(account.home)
	console.status = nil
	console.loginAt = now or 0
	-- No motd on an rsh (pty.quiet): rshd does not print one, login does, and an
	-- rsh is not a login. It matters more than the flavour of it -- what comes back
	-- from an rsh is the far command's output and goes into a pipe, a $(...) or
	-- somebody's mail, and a greeting in there is a line the far command did not
	-- write.
	if not pty.quiet then CeroSec.consolePushAll(console, CeroSecOS.motdLines(far)) end
	if now ~= nil then
		CeroSecOS.wtmpAppend(far, "in", account.name, pty.line, pty.fromHost, now)
		object:mirrorOS()
	end
	return console
end

-- The far machine, its state, this machine's name, and a line on it -- or nil
-- plus which of strerror's words to wear. Shared by rlogin and rsh, because the
-- two differ in exactly one thing and it is not this.
local function connect(system, luaObject, console, cmd, data)
	local object = CeroSecNet.reachable(system, luaObject, data.addr)
	if object == nil then
		return nil, CeroSecOS.netRefusal(cmd, data.host, "unreach")
	end
	local far = object:osState()
	if far == nil then
		return nil, CeroSecOS.netRefusal(cmd, data.host, "down")
	end
	if object.ptys == nil then object.ptys = {} end

	local state = luaObject:osState()
	local fromHost = CeroSecOS.DEFAULT_HOSTNAME
	local fromAddr = nil
	if state ~= nil then
		fromHost = CeroSecOS.hostname(state)
		fromAddr = CeroSecOS.address(state)
	end

	local watchAt = CeroSecNet.watchAtOf(luaObject, console)
	local pty, reason = CeroSecOS.remoteOpen(far, object.ptys, {
		fromHost = fromHost,
		fromAddr = fromAddr,
		want = data.user,
		hops = data.hops,
		at = CeroSecOS.clockOf(system:clockEnv()),
		-- Where the glass is, and who dialled. A chain of rlogins keeps pointing
		-- at the machine the window is actually open on, while `from` names the
		-- console one hop back -- which for a chain is another machine's pty.
		home = watchAt,
	})
	if pty == nil then
		return nil, CeroSecOS.netRefusal(cmd, data.host, reason)
	end
	pty.from = { x = luaObject.x, y = luaObject.y, z = luaObject.z, line = console.line }
	-- A detached session takes no copy of the glass and the glass is not pointed
	-- at it: the near console keeps showing what it was showing, whether that is a
	-- prompt nobody is at or a session a survivor opened himself.
	local noTty = detachedDial(console, data)
	if noTty ~= nil then
		pty.noTty = noTty
		pty.console = newPtyConsole(nil, pty, watchAt, data.hops)
		pty.console.noTty = true
		return pty, object, far, fromHost
	end
	pty.console = newPtyConsole(console, pty, watchAt, data.hops)
	console.remote = { x = object.x, y = object.y, z = object.z, line = pty.line }
	return pty, object, far, fromHost
end

-- rlogin: a login prompt on the far machine, unless a trust file says the
-- password may be skipped.
--
-- The name asked for with -l is what the trust files are asked about; the login
-- prompt still asks for a name, because this machine's login is a login and not
-- a protocol handshake with a user name in it. The manual says so.
function CeroSecNet.dial(system, luaObject, console, data)
	local pty, object, far, fromHost = connect(system, luaObject, console, "rlogin", data)
	if pty == nil then return nil, object end
	local account = CeroSecOS.getUser(far, data.user)
	if account ~= nil and CeroSecOS.trusts(far, data.user, fromHost, data.from) then
		CeroSecNet.logIn(system, object, far, pty, account,
			CeroSecOS.clockOf(system:clockEnv()))
		pty.trusted = true
	end
	return pty, object, far
end

-- rsh: one command, the caller's account, and no password ever. Trust or
-- nothing, which is rshd's whole protocol.
function CeroSecNet.remoteCommand(system, luaObject, console, data)
	local object = CeroSecNet.reachable(system, luaObject, data.addr)
	if object == nil then
		return nil, CeroSecOS.netRefusal("rsh", data.host, "unreach")
	end
	local far = object:osState()
	if far == nil then
		return nil, CeroSecOS.netRefusal("rsh", data.host, "down")
	end
	local state = luaObject:osState()
	local fromHost = CeroSecOS.DEFAULT_HOSTNAME
	if state ~= nil then fromHost = CeroSecOS.hostname(state) end
	-- Judged before a line is taken: a caller it will not trust is not a caller
	-- it should spend a pty on.
	local account = CeroSecOS.getUser(far, data.user)
	if account == nil or not CeroSecOS.trusts(far, data.user, fromHost, data.from) then
		return nil, CeroSecOS.netRefusal("rsh", data.host, "denied")
	end

	local pty, refused, farAgain = connect(system, luaObject, console, "rsh", data)
	if pty == nil then return nil, refused end
	-- An rsh is one command and not a login: it says nothing when it ends, and
	-- the session ends when the command does.
	pty.quiet = true
	CeroSecNet.logIn(system, object, farAgain, pty, account,
		CeroSecOS.clockOf(system:clockEnv()))
	return pty, object, farAgain
end

-- The order, carried out. Called from the scheduler, after the screen carrying
-- the line that was typed has gone out.
-- forJob is the job the order came off, for an rsh: it is WAITING on this dial
-- and is still on the machine's book. What it gets is the far line to hang up (so
-- Escape and `kill` reach across the wire), or the refusal and a status if the
-- dial never happened at all.
function CeroSecNet.answerDial(system, luaObject, console, control, data, playerObj, forJob)
	if type(data) ~= "table" then return end
	local state = luaObject:osState()
	local noTty = detachedDial(console, data)
	-- The engine refuses an rlogin with no terminal where it was written
	-- (CeroSecOSVM applyControl), and this is the same rule standing at the door:
	-- a screen nobody is watching is not a terminal to hand a session, whichever
	-- way the order got here. What it says goes where the sheet goes.
	if control == "rlogin" and noTty ~= nil then
		deliver(system, luaObject, console, noTty, { "rlogin: not a terminal" })
		return
	end
	local pty, object, far, refusal = nil, nil, nil, nil
	if control == "rlogin" then
		pty, object, far = CeroSecNet.dial(system, luaObject, console, data)
	else
		pty, object, far = CeroSecNet.remoteCommand(system, luaObject, console, data)
	end
	if pty == nil then
		-- object carries the line to print when the dial failed.
		refusal = object
		-- A refusal the far machine handed back -- no line free, no trust -- is
		-- the only thing a detached dial ever says, and it says it where the job
		-- that dialled was printing. Every refusal the ENGINE could work out was
		-- printed by the command itself, long before this.
		--
		-- A job waiting on it is let go here, with the status rsh answers when it
		-- could not get through: a script whose rsh was refused goes on to its next
		-- line, and it is the refusal and not a hang that it goes on from.
		if noTty ~= nil then
			deliver(system, luaObject, console, noTty, { tostring(refusal) }, 1, true)
			return
		end
		CeroSec.consolePush(console, tostring(refusal))
		if state ~= nil then system:pushScreen(luaObject, state, console) end
		return
	end

	-- The glass is the session's now. Pushed from the FAR machine, because that
	-- is whose hostname, whose prompt and whose files the screen is about. A
	-- detached session has no glass, and pushScreen knows it.
	system:pushScreen(object, far, pty.console)

	if control == "rsh" then
		-- Which line on which machine the job that is waiting has to hang up, if
		-- it is killed or its session goes away before the far command is done.
		-- Written before the far job is started, because the far job may be over
		-- inside this very call.
		if type(forJob) == "table" and not CeroSecOS.jobIsOver(forJob) then
			forJob.remote = { x = object.x, y = object.y, z = object.z, line = pty.line }
		end
		-- The line it was given, as the pty's own foreground job. The shell is a
		-- file over there like everything else, so a machine whose /bin/sh has
		-- been deleted answers an rsh the way it answers a survivor.
		local farJob = system:startPrompt(object, pty.console, data.cmd, playerObj, nil)
		-- And a machine that could not start it at all -- no shell, no room on its
		-- own job book -- is a session with nothing in it. It is closed here rather
		-- than left open: what the far machine said about it is on that console and
		-- is delivered by the teardown, and a job waiting on a session nothing is
		-- ever going to run is a job that would wait for ever.
		if farJob == nil then CeroSecNet.tearDown(system, object, pty.line) end
	elseif pty.trusted then
		-- A trusted login skipped the password, so it owes the account the two
		-- things a login owes it: its own history, and its own ~/.profile.
		system:runProfile(object, pty.console, playerObj, nil)
	end
end
