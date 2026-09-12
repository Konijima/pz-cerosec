if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSCron"
require "CeroSec/OS/CeroSecOSScript"
require "CeroSec/OS/CeroSecOSVM"
require "CeroSec/SCeroSecNet"

--
-- The scheduler.
--
-- The engine can run a script a step at a time (CeroSecOSVM.lua). This is what
-- decides HOW MANY steps, and when, and what happens to the output -- the half
-- that knows there is a server with other things to do.
--
-- Ten passes a second, on the same Events.OnTick clock the device blink runs on
-- (see the head of SCeroSecDevices.lua: OnTick gated on getTimestampMs is
-- vanilla's own way of getting under a minute, forageServer.lua:502). Each pass
-- has CeroSec.STEP_BUDGET_PER_TICK steps to hand out across every machine with
-- a job on it, and no machine may take more than CeroSec.STEP_BUDGET_PER_MACHINE
-- of them. The machines are served round-robin, starting one further along
-- every pass, so a machine at the end of the list is not the machine that never
-- runs.
--
-- A starved job is not a broken job: it simply runs slower. Nothing here ever
-- refuses to schedule; the only things that end a job are its own last line,
-- `kill`, Escape, the cpu ceiling, and the machine going dark.
--
-- The jobs are RUNTIME state and are deliberately not in the object's saved
-- keys: a reload forgets them, the console's note of a foreground job is
-- dropped by CeroSec.repairConsole, and what a player finds after a server
-- restart is a prompt. A script that must survive a restart is a script the
-- player starts again -- which is the honest thing for a machine that has no
-- process table on its disk.
--

CeroSecJobs = CeroSecJobs or {}

-- Every machine with at least one job. An array and not a set, because the
-- round-robin needs an order and pairs() has none.
CeroSecJobs.machines = CeroSecJobs.machines or {}
CeroSecJobs.cursor = 0
CeroSecJobs.lastMs = 0

-- The first job on a machine is 42. A job id is not a slot number -- `[1] 42`
-- is job one, id forty-two -- so the two can never be read as each other.
CeroSecJobs.FIRST_ID = 42

--
-- The book of jobs, per machine
--

function CeroSecJobs.book(luaObject)
	if luaObject.jobs == nil then
		luaObject.jobs = { seq = 0, list = {}, winMs = 0, winCount = 0, outCursor = 0 }
	end
	return luaObject.jobs
end

local function register(luaObject)
	local machines = CeroSecJobs.machines
	for i = 1, #machines do
		if machines[i] == luaObject then return end
	end
	machines[#machines + 1] = luaObject
end

local function forget(luaObject)
	local machines = CeroSecJobs.machines
	local kept = {}
	for i = 1, #machines do
		if machines[i] ~= luaObject then kept[#kept + 1] = machines[i] end
	end
	CeroSecJobs.machines = kept
end

-- The lowest slot number nobody is using. Slots are what `[1]` means and what
-- `kill %1` names; they are reused, ids are not.
local function freeSlot(book)
	for n = 1, CeroSecOS.MAX_JOBS do
		local taken = false
		for i = 1, #book.list do
			if book.list[i].n == n then taken = true end
		end
		if not taken then return n end
	end
	return CeroSecOS.MAX_JOBS
end

local function liveCount(book)
	return CeroSecOS.liveJobs(book.list)
end

-- Make a job from the order the engine handed back. nil plus a reason when the
-- machine has no room for it.
-- Put a job on the machine and start scheduling it. The two makers below hand
-- the job over ready-made; everything from here down is the book-keeping every
-- job needs whoever built it.
local function enrol(system, luaObject, console, job, bg)
	local book = CeroSecJobs.book(luaObject)
	-- Which screen it belongs to. A console with a line name is a pty's -- a
	-- session that came in over the wire -- and every job it starts is tagged with
	-- it, so the scheduler knows whose glass to write on and so the session taking
	-- its shell away takes its jobs too.
	if console ~= nil and type(console.line) == "string" then job.pty = console.line end
	book.seq = book.seq + 1
	job.id = CeroSecJobs.FIRST_ID + book.seq - 1
	-- The prompt's own job holds no slot: `[1]` is what the shell STARTED, and
	-- the shell is not one of the things it started.
	if not job.interactive then job.n = freeSlot(book) end
	book.list[#book.list + 1] = job
	register(luaObject)
	CeroSecJobs.system = system

	if job.mailTo ~= nil then
		-- A cron job is the MACHINE's and not the shell's: it holds no slot,
		-- because `[1]` is what the shell started and the shell started nothing;
		-- it says nothing on the screen, because nobody is standing there; and
		-- the prompt is not waiting on it. `ps` shows it, `jobs` does not, and
		-- `kill <id>` takes it away like anything else.
		job.n = nil
	elseif job.interactive then
		-- The prompt belongs to it until it is over, exactly as it does for a
		-- foreground script: that is what makes Escape a ^C on a typed loop.
		console.job = job.id
	elseif bg then
		CeroSec.consolePush(console, "[" .. job.n .. "] " .. job.id)
	else
		console.job = job.id
	end
	return job
end

-- The line a player typed, as the machine's foreground job. The console's own
-- variables and its $? go in by reference, so `x=5` on one line and `echo $x`
-- on the next are the same environment -- and walking away and coming back
-- finds it, because the console is machine state and is saved with the object.
--
-- job, or nil plus the one line to print.
-- name is what the job calls itself in an error and what `ps` shows; it is
-- "sh" for a typed line and the file's own name for ~/.profile, which is run
-- exactly this way.
function CeroSecJobs.startPrompt(system, luaObject, console, line, name)
	local state = luaObject:osState()
	if state == nil then return nil, "no filesystem" end
	-- A console that has none -- one saved before there was a PATH on this
	-- machine, or one whose variables a repair dropped -- gets what a login gives
	-- one, rather than an empty environment nothing could look a name up in.
	if type(console.shvars) ~= "table" then
		local account = CeroSecOS.getUser(state, system:sessionOf(console).user)
		console.shvars = CeroSecOS.loginVars(account ~= nil and account.home or nil)
	end
	local job, refusal = CeroSecOS.promptJob(state, system:sessionOf(console), line,
		console.shvars, console.status, name)
	if job == nil then return nil, refusal end
	return enrol(system, luaObject, console, job, false)
end

function CeroSecJobs.start(system, luaObject, console, data, bg)
	local book = CeroSecJobs.book(luaObject)
	if liveCount(book) >= CeroSecOS.MAX_JOBS then return nil, "too many jobs" end
	local job = CeroSecOS.newJob({
		prog = data.prog,
		args = data.args,
		name = data.name,
		cmd = data.cmd,
		bg = bg,
		session = system:sessionOf(console),
		-- The variables the shell that asked for this job was holding, copied:
		-- a statement behind an `&` is a subshell of it and starts with what it
		-- had. The caller does the copying, because only the caller knows whose
		-- shell it was; a caller that hands none gets the default environment,
		-- which is cron's case and nobody else's.
		vars = data.vars,
	})
	return enrol(system, luaObject, console, job, bg)
end

-- Every job on this machine, gone. Reboot, shutdown, a room that lost its
-- power, a computer picked up: all four are the machine stopping, and a
-- machine that has stopped is running nothing.
function CeroSecJobs.killAll(luaObject)
	-- A pending shutdown goes with them. It is an order given to a machine that
	-- is running, and a machine that has stopped is not running it any more:
	-- `shutdown -r +5` does not survive the power going out, and the README and
	-- the manual say so.
	local had = luaObject.jobs ~= nil or luaObject.shutdown ~= nil
	luaObject.jobs = nil
	luaObject.shutdown = nil
	-- NOT the minute cron last looked at. This is called every pass on a machine
	-- that has finished what it was running, and forgetting the minute there
	-- would make every job that ended cost cron the minute after it -- the note
	-- belongs to the machine being UP and is dropped by turnOff, which is the
	-- only thing that makes a machine stop being up.
	forget(luaObject)
	return had
end

--
-- The pending shutdown
--
-- `shutdown -r +5` is an order with a clock on it, and the clock is this pass:
-- there is no timer anywhere else on the machine. It is RUNTIME state -- it is
-- not among the object's saved keys -- so a server restart forgets it and the
-- machine simply stays up, which is the honest answer for a machine with no
-- process table on its disk.
--
-- It survives a window closing, because it belongs to the machine and not to
-- anybody standing at it, and it does not survive the power going out or the
-- computer being picked up, because neither of those is a machine any more.
--

function CeroSecJobs.schedule(luaObject, data)
	if type(data) ~= "table" or type(data.at) ~= "number" then return nil end
	luaObject.shutdown = { at = data.at, kind = data.kind or "shutdown", warned = false }
	register(luaObject)
	return luaObject.shutdown
end

-- One line onto the machine's screen, and out to every window standing at it.
-- A broadcast is not a reply: it reaches everybody or it is not a broadcast.
local function broadcast(system, luaObject, line)
	local console = luaObject:consoleState()
	if console == nil then return end
	CeroSec.consolePush(console, line)
	system:pushScreen(luaObject, luaObject:osState(), console)
end

-- The warning a minute out, and then the deed. Run for every machine that has
-- one, on every pass, before any job is stepped: a machine with a shutdown
-- pending and nothing running must still go down at the minute it was told to.
function CeroSecJobs.checkShutdown(system, luaObject, now)
	local pending = luaObject.shutdown
	if pending == nil then return end
	if not luaObject.on then
		luaObject.shutdown = nil
		return
	end
	local left = pending.at - now
	if left <= 0 then
		luaObject.shutdown = nil
		broadcast(system, luaObject, CeroSecOS.shutdownLine(pending.kind, 0))
		system:applyPower(luaObject, pending.kind)
		return
	end
	if not pending.warned and left <= 60000 then
		pending.warned = true
		broadcast(system, luaObject, CeroSecOS.shutdownLine(pending.kind, 1))
	end
end

--
-- cron
--
-- The daemon, which is not a process: there is no room on a machine this size
-- for one, and there is no need for one either -- a pass once a game minute over
-- every machine that is switched on is exactly what crond does with its own
-- sleep. Switched on, and not "in view": a machine whose chunk the streamer has
-- taken away keeps its power, its jobs and its crontab, because none of the three
-- is a thing in the world (SCeroSecSystem:checkCron, and the head of
-- SCeroSecNet.lua).
--
-- What a crontab MEANS is the core's (CeroSecOSCron.lua); what is here is
-- the clock, the job-making and the four-job ceiling, because only the machine
-- knows how many jobs it already has.
--
-- The minute it last looked at is RUNTIME state, like the jobs themselves. So a
-- machine that has only just come into view -- a chunk loading, a server coming
-- up, a computer switched on -- looks at the minute it arrived in, runs nothing
-- for it, and starts firing from the next one. Nothing is ever run late and
-- nothing is ever run twice: real cron does not go back for a minute it slept
-- through either, which is the whole reason anacron was written, and there is no
-- anacron here.
--

-- What a line of the log says about a job, in the shape a real cron's syslog
-- line says it: who it was, and what ran.
local function cronSay(state, user, text, now)
	CeroSecOS.cronLog(state, "(" .. tostring(user) .. ") " .. text, now)
end

-- One due line, started as a background job of that account. The 4-job ceiling
-- is the machine's and is not lifted for cron: a line that cannot start is
-- SKIPPED and said so in the log, the way a cron that cannot fork says it.
local function cronFire(system, luaObject, console, state, user, home, entry, now)
	local book = CeroSecJobs.book(luaObject)
	if liveCount(book) >= CeroSecOS.MAX_JOBS then
		cronSay(state, "CRON", "error (can't fork)", now)
		return nil
	end

	cronSay(state, user, "CMD (" .. entry.cmd .. ")", now)

	local prog, reason, where = CeroSecOS.parseScript(entry.cmd)
	if prog == nil then
		-- A command that will not parse never becomes a job, exactly as `sh` on
		-- a broken file does not -- and what sh would have said goes to the
		-- account's mail, because that is where a cron job's output goes.
		CeroSecOS.mailAppend(state, user, CeroSecOS.hostname(state), entry.cmd,
			{ CeroSecOS.scriptError("sh", reason, where) }, now)
		return nil
	end

	local job = CeroSecOS.newJob({
		prog = prog,
		name = "cron",
		cmd = entry.cmd,
		bg = true,
		session = { user = user, cwd = home or "/", stamp = 1 },
		-- Cron's own environment, and not the shell's: the default PATH and the
		-- account's home, which is exactly what Vixie's cron puts in one. A line
		-- that worked at a prompt because ~/bin was on the PATH there does not
		-- work here, and the manual says so.
		vars = CeroSecOS.loginVars(home),
	})
	-- Where what it prints goes. Set before it is enrolled, because that is what
	-- tells the book this is not the shell's job.
	job.mailTo = user
	return enrol(system, luaObject, console, job, false)
end

-- One pass of the daemon over one machine. now is the GAME clock, in seconds:
-- cron keeps the world's time and not the wall clock, because "every day at
-- four" means four in Knox County.
function CeroSecJobs.cronPass(system, luaObject, now)
	if type(now) ~= "number" then return 0 end
	if not luaObject.on then return 0 end
	local state = luaObject:osState()
	local console = luaObject:consoleState()
	if state == nil or console == nil then return 0 end

	local minute = math.floor(now / 60)
	if luaObject.cron == nil then luaObject.cron = {} end
	local last = luaObject.cron.minute
	luaObject.cron.minute = minute
	-- The minute it arrived in is not a minute it was there for.
	if last == nil then return 0 end
	if minute <= last then return 0 end

	local dir = CeroSecOS.systemNode(state, CeroSecOS.CRON_PATH)
	if type(dir) ~= "table" or dir.type ~= "dir" then return 0 end
	local names = CeroSecOS.childNames(dir)
	local parts = CeroSecOS.dateParts(now)
	local fired = 0

	for i = 1, #names do
		local user = names[i]
		local node = dir.children[user]
		if type(node) == "table" and node.type == "file" then
			local account = CeroSecOS.getUser(state, user)
			if account == nil then
				-- A crontab for an account that is not on the machine any more.
				-- Vixie's word for it, and his behaviour: it is not run.
				cronSay(state, user, "ORPHAN (no passwd entry)", now)
			else
				local entries, errors = CeroSecOS.parseCrontab(node.data or "")
				for k = 1, #errors do
					-- A line nobody could have installed through crontab(1),
					-- which means one written by hand as root. The good lines
					-- still run; this one is said once a minute it would have
					-- been due in, which is what a log is for.
					cronSay(state, user, "ERROR (" ..
						CeroSecOS.cronError(CeroSecOS.cronPath(user), errors[k].line,
							errors[k].reason) .. ")", now)
				end
				for k = 1, #entries do
					if CeroSecOS.cronDue(entries[k], parts) then
						if cronFire(system, luaObject, console, state, user,
								account.home, entries[k], now) ~= nil then
							fired = fired + 1
						end
					end
				end
			end
		end
	end
	if fired > 0 then luaObject:mirrorOS() end
	return fired
end

-- @reboot, which is the one line that is not a time. Run when the machine comes
-- up -- the switch at the back of the case, or a `reboot` -- and never caught up
-- afterwards: a machine that was off at four in the morning did not reboot at
-- four in the morning.
function CeroSecJobs.atBoot(system, luaObject)
	if system == nil then system = CeroSecJobs.system end
	if system == nil then return 0 end
	if not luaObject.on then return 0 end
	local state = luaObject:osState()
	local console = luaObject:consoleState()
	if state == nil or console == nil then return 0 end

	local now = CeroSecOS.clockOf(system:clockEnv())
	local dir = CeroSecOS.systemNode(state, CeroSecOS.CRON_PATH)
	if type(dir) ~= "table" or dir.type ~= "dir" then return 0 end
	local names = CeroSecOS.childNames(dir)
	local fired = 0
	for i = 1, #names do
		local node = dir.children[names[i]]
		local account = CeroSecOS.getUser(state, names[i])
		if type(node) == "table" and node.type == "file" and account ~= nil then
			local entries = CeroSecOS.parseCrontab(node.data or "")
			for k = 1, #entries do
				if entries[k].reboot then
					if cronFire(system, luaObject, console, state, names[i],
							account.home, entries[k], now) ~= nil then
						fired = fired + 1
					end
				end
			end
		end
	end
	if fired > 0 then luaObject:mirrorOS() end
	return fired
end

function CeroSecJobs.foreground(luaObject, console)
	if console == nil or console.job == nil then return nil end
	local book = luaObject.jobs
	if book == nil then return nil end
	for i = 1, #book.list do
		if book.list[i].id == console.job then return book.list[i] end
	end
	return nil
end

--
-- One pass over one machine
--

-- How a job's end reads on the screen. A foreground job that simply finished
-- says nothing at all -- the prompt coming back is the message, exactly as it
-- is on a real machine -- and everything else says one line.
local function endLine(job)
	local word = nil
	if job.state == "killed" then
		word = "killed"
		if job.killReason ~= nil then word = word .. ": " .. job.killReason end
	elseif job.state == "error" then
		word = nil -- the script already printed the line that stopped it
	elseif job.bg then
		if job.status == 0 then word = "done" else word = "exit " .. job.status end
	end
	if word == nil then return nil end
	if job.bg then return "[" .. (job.n or 1) .. "] " .. word end
	return word
end

-- Lines the machine may put on the screen this pass. The window is one second
-- wide and CeroSec.JOB_OUT_PER_SEC lines deep, per MACHINE and not per job: a
-- machine with four flooding jobs is as quiet as a machine with one.
local function outRoom(book, now)
	if now - book.winMs >= 1000 then
		book.winMs = now
		book.winCount = 0
	end
	local room = CeroSec.JOB_OUT_PER_SEC - book.winCount
	if room < 0 then return 0 end
	return room
end

-- One pass over one machine, and the one place a job's output, its questions,
-- its end and its orders reach the screen.
--
-- playerObj and token are who typed the line this pass is serving and at which
-- window, and both are nil on an ordinary tick: the scheduler has no player.
-- Two things need them. `edit` has to know whose keyboard is on the buffer, and
-- `dev find` is answered on ONE screen rather than on the machine's (see the
-- head of SCeroSecDevices.lua) -- so both can only ever come out of a pass the
-- server runs in somebody's hand, which is what Commands.exec runs.
--
-- force makes the screen go out whether or not this pass changed anything: the
-- line a player typed was pushed before the pass and has to reach the glass
-- even when the command printed nothing at all.
--
-- Returns the steps it spent.
function CeroSecJobs.runMachine(system, luaObject, budget, now, playerObj, token,
		force, forConsole)
	local book = luaObject.jobs
	if book == nil or #book.list == 0 then
		CeroSecJobs.killAll(luaObject)
		return 0
	end
	if not luaObject.on then
		CeroSecJobs.killAll(luaObject)
		return 0
	end
	local state = luaObject:osState()
	local own = luaObject:consoleState()
	if state == nil or own == nil then
		CeroSecJobs.killAll(luaObject)
		return 0
	end

	-- Which screen a job writes to.
	--
	-- A job the survivor at the keyboard started writes to the machine's own
	-- console. One started down an rlogin writes to the pty's, which is on
	-- somebody else's glass -- and a pty that has GONE, because the session was
	-- closed while the job was still running, is a shell with no terminal: the
	-- job goes with it, exactly as it goes when the machine is switched off.
	local function screenOf(job)
		if job.pty == nil then return own end
		local pty = CeroSecOS.remoteLine(luaObject.ptys, job.pty)
		if pty == nil then return nil end
		return pty.console
	end

	-- Every screen this pass touched, so each is pushed once and no more. A
	-- machine with the survivor at its keyboard and three sessions in from the
	-- wire has four of them, and a line written on one is nobody else's business.
	local dirty, dirtyList = {}, {}
	local function touch(console)
		if console == nil or dirty[console] then return end
		dirty[console] = true
		dirtyList[#dirtyList + 1] = console
	end
	if force then touch(forConsole or own) end

	-- The load averages, moved on. Once a pass and no oftener than every five
	-- seconds (CeroSecOS.loadSample decides), on the run queue this very book is:
	-- what `uptime` and `w` print. Before execEnv, so the numbers a command reads
	-- this pass are this pass's.
	CeroSecOS.loadSample(book, now)

	local env = system:execEnv(luaObject, state, playerObj, token)
	env.nowMs = now
	env.jobs = book.list

	local used = 0
	local share = math.floor(budget / #book.list)
	if share < 1 then share = 1 end

	for i = 1, #book.list do
		local job = book.list[i]

		-- The session it was running for has gone. Nothing it writes has anywhere
		-- to go, so it stops here.
		if job.pty ~= nil and screenOf(job) == nil then
			CeroSecOS.killJob(job, nil)
		end
		-- A `wait` whose jobs have all gone.
		if job.state == "waiting" and job.waitFor ~= nil
				and CeroSecOS.jobWaitDone(job, book.list) then
			job.waitFor = nil
			job.state = "running"
		end
		-- `kill` asked; the deed is done here, where the screen can be told.
		if job.killReq ~= nil and not CeroSecOS.jobIsOver(job) then
			CeroSecOS.killJob(job, nil)
			job.killReq = nil
		end
		-- The runaway ceiling. Continuous processor time with no wait in it:
		-- a job asleep, waiting on an answer or held back by the screen has
		-- stopped the clock, which is why an idle script lives forever and a
		-- spinning one does not.
		if CeroSecOS.jobOverCpu(job, now, CeroSec.JOB_CPU_LIMIT_S) then
			CeroSecOS.killJob(job, "cpu limit")
		end

		if not CeroSecOS.jobIsOver(job) then
			local left = budget - used
			if left > share then left = share end
			if left > 0 then
				local _, cost = CeroSecOS.jobStep(state, job, env, left)
				used = used + cost
			end
		end
		-- The prompt's job runs ON the console's session and not on a copy of
		-- it: `cd` typed at the glass moves the machine's cursor, and `su`
		-- changes who the machine is logged in as. Written back every pass,
		-- because the job may move it at any step and the screen that goes out
		-- below has to agree with it. The console is the job's own, which down an
		-- rlogin is the pty's: a `cd` typed there moves that session and not the
		-- survivor's who is standing at the far machine.
		if job.interactive then
			local screen = screenOf(job)
			if screen ~= nil then system:writeSession(screen, job.session) end
		end
	end

	-- A statement with "&" behind it, asked for by a job that is already
	-- running. One per pass and per job, so a loop full of them makes four jobs
	-- and then says so once each time round.
	for i = 1, #book.list do
		local job = book.list[i]
		if job.spawn ~= nil then
			-- What `jobs` and `ps` call it. A line typed at the prompt is
			-- called by the line that was typed; a statement inside a file is
			-- called by the file and the line it is on.
			local cmd = job.name .. ":" .. tostring(job.spawnLine or 1) .. " &"
			if job.promptLine ~= nil then cmd = job.promptLine end
			local order = { name = job.name, prog = { job.spawn }, args = job.args,
				cmd = cmd,
				-- A COPY of what the shell that wrote the `&` was holding. That is
				-- what a subshell gets on every Unix there has ever been, and
				-- without it `./where.sh &` ran with PATH and nothing else -- not
				-- even HOME -- while the same file in the foreground had the lot.
				vars = CeroSecOS.copyVars(job.vars) }
			job.spawn = nil
			job.spawnLine = nil
			-- What tells the caller this pass answered an "&". A line typed at
			-- the prompt is served pass by pass in the player's own hand
			-- (SCeroSecSystem:startPrompt) and the pass that MAKES a job is
			-- never the pass the line finishes in, so it has to know.
			job.spawned = true
			local screen = screenOf(job)
			local made = nil
			if screen ~= nil then
				made = CeroSecJobs.start(system, luaObject, screen, order, true)
			end
			if made == nil then
				-- Said by the job that asked, so it drains at the same rate its
				-- own output does: a loop full of refusals is as quiet as a
				-- loop full of echoes.
				CeroSecOS.jobSay(job, "sh: too many jobs")
				job.status = 1
			end
			touch(screen)
		end
	end

	-- The output, at the rate the screen and the network can take it. The rate is
	-- the MACHINE's and is shared by every screen on it: four sessions trickling
	-- at once cost the server what one does.
	--
	-- Shared round-robin, one job further along every pass. Sharing it from the
	-- front of the list instead is how a fourth job never drains AT ALL while the
	-- first three keep refilling -- and a job whose output cannot drain is a job
	-- that never runs again, so that is not a slow job but a stopped one. The
	-- machines are served the same way and for the same reason
	-- (CeroSecJobs.pass). It took four inbound rlogins to make it visible;
	-- tests/hostile_test.lua has them.
	local room = outRoom(book, now)
	local count = #book.list
	-- Moved on only when there was room to hand out, and that matters: a machine
	-- gets its twenty lines in the FIRST pass of each second and nothing in the
	-- nine after it, so a cursor that moved every pass would move ten places a
	-- second -- two, modulo four jobs -- and two of four jobs would never lead the
	-- rotation at all. Moved on per draining pass, each of them leads in turn.
	if room > 0 then
		book.outCursor = math.fmod((book.outCursor or 0) + 1, count)
	end
	for k = 1, count do
		local job = book.list[math.fmod(book.outCursor + k - 1, count) + 1]
		-- Except a cron job's, which never reaches a screen at all: it is mailed
		-- to the account that asked for it, the way cron has answered since V7.
		-- There is no rate to keep to -- a disk is not a network -- and the
		-- mailbox is bounded where it is written.
		if job.mailTo ~= nil then
			if #job.out > 0 then
				local cmd = nil
				-- The header goes on the first delivery only: one message per
				-- job, however many passes it took to write it.
				if not job.mailed then
					cmd = job.cmd
					job.mailed = true
				end
				CeroSecOS.mailAppend(state, job.mailTo, CeroSecOS.hostname(state), cmd,
					job.out, CeroSecOS.clockOf(env))
				job.out = {}
				touch(own)
			end
		elseif screenOf(job) == nil then
			-- The session this job was writing to has gone. There is nowhere for
			-- the lines to go, so they go -- a job whose output nothing can ever
			-- drain is a job that is never reaped, and a machine that kept one
			-- would keep a job slot spent on a terminal nobody is at.
			job.out = {}
		else
			local screen = screenOf(job)
			-- And a second ceiling under the machine's, for a job writing down a
			-- TELEPHONE line: 2400 baud is CeroSec.PHONE_LINES_PER_S lines a second
			-- and no more. It is the LINE's ceiling and not the machine's -- the
			-- window is kept on the call itself -- so two calls into one computer
			-- each trickle at their own speed while the machine's twenty a second
			-- still holds over both of them and over its own glass.
			--
			-- Nothing is thrown away: what the line could not carry this second is
			-- kept exactly as what the screen could not take is kept, and goes out
			-- in the passes after it. A player watching a call sees a `cat` arrive
			-- four lines at a time, which is what a modem looked like.
			local call = CeroSecNet.callOn(luaObject, screen)
			local slow = nil
			if call ~= nil then slow = CeroSecNet.callRoom(call, now) end
			local kept = {}
			for k = 1, #job.out do
				if room > 0 and (slow == nil or slow > 0) then
					CeroSec.consolePush(screen, job.out[k])
					room = room - 1
					book.winCount = book.winCount + 1
					if slow ~= nil then
						slow = slow - 1
						call.outCount = call.outCount + 1
					end
					touch(screen)
				else
					kept[#kept + 1] = job.out[k]
				end
			end
			job.out = kept
		end
	end

	-- The question a foreground job is asking, put up as an ordinary console
	-- prompt with an ordinary token. The console cannot tell a script's `read`
	-- from passwd's own question, and does not have to. Asked of every screen on
	-- the machine, because each has a foreground job of its own.
	local screens = { own }
	do
		local ptys = CeroSecOS.ptyList(luaObject.ptys)
		for i = 1, #ptys do
			if type(ptys[i].console) == "table" then screens[#screens + 1] = ptys[i].console end
		end
	end
	for s = 1, #screens do
		local screen = screens[s]
		local fg = CeroSecJobs.foreground(luaObject, screen)
		if fg ~= nil and fg.ask ~= nil and screen.prompt == nil then
			screen.prompt = { text = fg.ask.text or "", mask = fg.ask.mask and true or false,
				cont = { cmd = "job", id = fg.id } }
			touch(screen)
		end
	end

	-- Reaping. A job is only taken off the machine once the last of its output
	-- has reached the screen, or the last thing it said would be lost.
	--
	-- An order a job gave belongs to the screen that job was writing to, so the
	-- orders are collected as pairs and carried out after every screen has gone
	-- out. A machine can have four of them in one pass.
	local kept, orders = {}, {}
	for i = 1, #book.list do
		local job = book.list[i]
		-- An rsh a job is WAITING on, and a far session a job that has died left
		-- open. Both are collected with the orders below and carried out after
		-- every screen has gone out, because dialling paints the far machine's
		-- glass and a teardown paints this one's.
		--
		-- The job is not ended by either: an rsh is a wait and not an exit, so the
		-- order is given while the job that gave it is still on the book -- which
		-- is what lets the answer come back into it (CeroSecOS.jobRemote).
		if job.dial ~= nil and not CeroSecOS.jobIsOver(job) then
			orders[#orders + 1] = { console = screenOf(job) or own, control = "rsh",
				data = job.dial, forJob = job }
			job.dial = nil
		end
		if job.remote ~= nil and CeroSecOS.jobIsOver(job) then
			-- Escape, `kill`, the cpu limit, the session the job was writing to
			-- going away: whichever it was, nobody is listening at this end any
			-- more and the far machine is told, the way rshd's connection dropping
			-- tells it.
			orders[#orders + 1] = { console = screenOf(job) or own, control = "hangup",
				data = job.remote }
			job.remote = nil
		end
		if CeroSecOS.jobIsOver(job) and #job.out == 0 then
			local screen = screenOf(job)
			-- A cron job says nothing when it ends either: "[1] done" is a
			-- message to whoever started it, and nobody started this one.
			local line = nil
			if job.mailTo == nil then line = endLine(job) end
			if line ~= nil and screen ~= nil then
				CeroSec.consolePush(screen, line)
				book.winCount = book.winCount + 1
			end
			if screen ~= nil and screen.job == job.id then
				screen.job = nil
				-- The status the prompt comes back with, kept on the console the
				-- way a shell keeps $?.
				screen.status = job.status
				if screen.prompt ~= nil and type(screen.prompt.cont) == "table"
						and screen.prompt.cont.cmd == "job" then
					screen.prompt = nil
				end
				-- An rsh is one command and the session was for it: when it is
				-- over, so is the connection. Carried out with the other orders,
				-- after the last of its output has reached the glass.
				if CeroSecNet.isOneShot(luaObject, screen) then
					orders[#orders + 1] = { console = screen, control = "endsession" }
				end
			end
			if job.control ~= nil and screen ~= nil then
				orders[#orders + 1] = { console = screen, control = job.control,
					data = job.controlData }
			end
			touch(screen)
		else
			kept[#kept + 1] = job
		end
	end
	book.list = kept
	if #book.list == 0 and luaObject.shutdown == nil then forget(luaObject) end

	if #dirtyList > 0 then
		luaObject:mirrorOS()
		for i = 1, #dirtyList do
			system:pushScreen(luaObject, state, dirtyList[i])
		end
	end

	-- Last, and never before the screens have gone out: a line that ended on
	-- `reboot` is a screen every survivor at the machine watches go down.
	for i = 1, #orders do
		CeroSecJobs.applyControl(system, luaObject, state, book, orders[i], playerObj)
	end
	return used
end

-- One order a finished job gave, carried out. Pulled out of runMachine because a
-- machine can now finish four lines in one pass -- one at its own keyboard and
-- one down each session -- and each order belongs to the screen its job was
-- writing to.
function CeroSecJobs.applyControl(system, luaObject, state, book, order, playerObj)
	local console = order.console
	local control = order.control
	local data = order.data
	if control == "clear" then
		CeroSec.consoleClear(console)
		system:pushScreen(luaObject, state, console)
	elseif control == "exit" then
		-- `exit` at the glass logs the account out. Down an rlogin it is the end
		-- of the SESSION: the shell rlogind started has gone, so there is nothing
		-- left to be logged into and the connection closes, which is what every
		-- rlogin has done since the first one.
		if CeroSecNet.endSession(system, luaObject, console) then return end
		system:logOut(luaObject, state, console)
		system:pushScreen(luaObject, state, console)
	elseif control == "edit" then
		system:applyOrder(console, control, data, playerObj)
		system:pushScreen(luaObject, state, console)
	elseif control == "fg" and type(data) == "table" then
		-- `fg`: the console's attention moves to a job it already has. Only the
		-- machine can do it -- the engine has no console -- and it is two things
		-- and nothing more: the job stops being a background job, so what it
		-- writes is no longer announced with a slot and its end says nothing, and
		-- the prompt belongs to it, which is what makes Escape its ^C.
		for i = 1, #book.list do
			local job = book.list[i]
			if job.id == data.id and not CeroSecOS.jobIsOver(job) then
				job.bg = false
				console.job = job.id
				system:pushScreen(luaObject, state, console)
			end
		end
	elseif control == "schedule" then
		CeroSecJobs.schedule(luaObject, data)
	elseif control == "cancel" then
		luaObject.shutdown = nil
	elseif control == "rlogin" or control == "rsh" or control == "cu"
			or control == "call" then
		CeroSecNet.answerDial(system, luaObject, console, control, data, playerObj, order.forJob)
	elseif control == "hangup" and type(data) == "table" then
		-- A far session whose near end has gone. Nothing is delivered anywhere:
		-- the job that was waiting for it is over, and what the far machine wrote
		-- has nobody left to read it.
		local object = system:getLuaObjectAt(data.x, data.y, data.z)
		if object ~= nil then CeroSecNet.tearDown(system, object, data.line) end
	elseif control == "endsession" then
		CeroSecNet.endSession(system, luaObject, console)
	elseif control ~= nil then
		system:applyPower(luaObject, control)
	end
end


--
-- One pass over every machine
--

function CeroSecJobs.pass(now)
	local machines = CeroSecJobs.machines
	if #machines == 0 then return end
	local system = CeroSecJobs.system
	if system == nil then return end

	local total = CeroSec.STEP_BUDGET_PER_TICK
	local n = #machines
	local start = CeroSecJobs.cursor
	CeroSecJobs.cursor = CeroSecJobs.cursor + 1

	-- A copy of the list, because runMachine may take a machine out of it.
	local order = {}
	for i = 1, n do order[i] = machines[(start + i - 1) % n + 1] end

	-- The clocks first, and all of them: a shutdown is not something a machine
	-- at the wrong end of a busy county may be late for, and it costs no steps.
	for i = 1, n do CeroSecJobs.checkShutdown(system, order[i], now) end

	for i = 1, n do
		local machine = order[i]
		if machine.jobs ~= nil and #machine.jobs.list > 0 then
			if total <= 0 then return end
			local share = CeroSec.STEP_BUDGET_PER_MACHINE
			if share > total then share = total end
			total = total - CeroSecJobs.runMachine(system, machine, share, now)
		elseif machine.shutdown == nil then
			-- Nothing running and nothing pending: it is not a machine the
			-- scheduler has anything to do with any more.
			forget(machine)
		end
	end
end

function CeroSecJobs.tick()
	if #CeroSecJobs.machines == 0 then return end
	local now = getTimestampMs()
	if now - CeroSecJobs.lastMs < CeroSec.JOB_PASS_MS then return end
	CeroSecJobs.lastMs = now
	CeroSecJobs.pass(now)
end

Events.OnTick.Add(function()
	CeroSecJobs.tick()
end)
