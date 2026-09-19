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
-- The book itself lives on the luaObject and is stepped from there. It is not
-- one of the object's saved keys -- it is written into the machine's own STATE
-- when the world is saved and read back out of it when the world is loaded, and
-- the section "The book across a save" at the bottom of this file is the whole
-- of that. What ends a job is still its own last line, `kill`, Escape, the cpu
-- ceiling and the machine going dark; leaving the game is not one of them,
-- because a computer the world saved was never switched off.
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
		console.shexport = CeroSecOS.loginExported()
	end
	-- console.shexport may be nil, and nil is not "nothing is exported": it is a
	-- console saved before this build, whose variables a script shared whole, so
	-- the engine reads it as all of them (the variables section of
	-- CeroSecOSVM.lua). It is passed as it stands for exactly that reason.
	-- The functions the shell holds, by reference like the variables: a definition
	-- typed on one line is there on the next, and it is the console that keeps it.
	-- Made here rather than at the login, because a console saved before there were
	-- functions on this machine has no such table and a shell with none is a shell
	-- that has defined none.
	if type(console.shfuncs) ~= "table" then console.shfuncs = {} end
	local job, refusal = CeroSecOS.promptJob(state, system:sessionOf(console), line,
		console.shvars, console.status, name, console.shexport, console.shfuncs)
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
		exported = data.exported,
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
	-- A pending shutdown goes with them, and now it goes with them for nothing but
	-- being in the book: it is an order given to a machine that is running, and a
	-- machine that has stopped is not running it any more. `shutdown -r +5` does
	-- not survive the power going out, and the README and the manual say so.
	local had = luaObject.jobs ~= nil
	luaObject.jobs = nil
	-- And the copy the save file would have carried. Raw and not through osState(),
	-- because what has to go is whatever is in the table the serializer will reach --
	-- a machine whose state the gate has refused has one too, and it is exactly the
	-- machine whose stale book must not come back.
	--
	-- The save path clears it as well (writeBook, for a machine with no book), so
	-- this is the second porter and not the only one. What it buys on its own is the
	-- state being clean BETWEEN saves: `os` rides into the IsoObject's movableData on
	-- every mirror and out to the clients on every publish, and a machine somebody
	-- has just switched off should not be handing anybody a list of what it used to
	-- be running.
	if type(luaObject.os) == "table" then luaObject.os.jobs = nil end
	-- And a dark interval, for the same reason one notch further along: this is
	-- only ever reached from turnOff, and a machine that has just been switched off
	-- is not a machine somebody rebooted. The order matters and is the reboot's own
	-- (SCeroSecSystem:reboot schedules AFTER the turnOff); what this catches is the
	-- machine switched on by hand while it was dark and then switched off again,
	-- which must stay off.
	luaObject.rebooting = nil
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
-- `shutdown -r +5` is an order with a clock on it, and it is A PROCESS -- which is
-- what BSD's shutdown(8) is: it forks, prints its pid and sleeps until the
-- minute. So it is a JOB on this machine, in the ordinary book, with an id and a
-- slot, owned by the account that gave the order; `jobs` and `ps` show it, `wait`
-- waits for it, and `kill` is what calls it off, because killing the process is
-- how a real one is called off and there is no `-c` on a 1993 shutdown.
--
-- It is a job that never runs. state "waiting" is the whole of it: jobStep answers
-- a waiting job in one test and spends nothing, and nothing ever wakes it -- the
-- clock it is waiting on is the SCHEDULER's pass (CeroSecJobs.checkShutdown
-- below), which is where it was before and has to stay, because a machine with a
-- shutdown pending and nothing running must still go down at the minute it was
-- told to. A "sleeping" job with a wake time would have been the prettier shape
-- and was rejected: a pass run in a player's hand (Commands.exec, Commands.input)
-- steps jobs without looking at any clock but its own, so the order would have
-- come due, run out of a program with nothing in it, and finished quietly having
-- switched nothing off.
--
-- What is on the job: `job.shutdown`, which is the order -- when, which kind, and
-- whether the minute's warning has gone out. Everything else about it is what
-- every other job has.
--
-- NOT SAVED with the rest of the book, and the reason is its clock. `at` is a
-- moment on getTimestampMs -- the wall clock the scheduler counts passes on --
-- and an order given against it cannot be carried across a save and still mean
-- what it said: the world stood still while the game was shut and the wall clock
-- did not. It falls out of the save rule anyway, because a pending order is a
-- job whose state is "waiting" and only a running or a sleeping job is written
-- (CeroSecJobs.jobSurvives). So a reload forgets it and the machine stays up,
-- which is what the README, the manual and docs/PARCOURS-TEST.md have always
-- said. It survives a window closing, because a job belongs to the machine and
-- not to anybody standing at it, and it does not survive the power going out or
-- the computer being picked up, because neither of those is a machine any more
-- (CeroSecJobs.killAll).
--

-- The pending order on a machine, or nil. The first one, and there can be two:
-- a second `shutdown +N` is a second process, exactly as it is on a real BSD.
function CeroSecJobs.pendingShutdown(luaObject)
	local book = luaObject.jobs
	if book == nil then return nil end
	for i = 1, #book.list do
		local job = book.list[i]
		if job.shutdown ~= nil and not CeroSecOS.jobIsOver(job) then return job end
	end
	return nil
end

-- job, or nil plus the reason: the machine's own ceiling, met here like every
-- other job's, because a pending shutdown spends a process slot like every other.
function CeroSecJobs.schedule(system, luaObject, console, data)
	if type(data) ~= "table" or type(data.at) ~= "number" then return nil end
	local book = CeroSecJobs.book(luaObject)
	if liveCount(book) >= CeroSecOS.MAX_JOBS then return nil, "too many jobs" end
	local session = system:sessionOf(console)
	local job = CeroSecOS.newJob({
		-- A program with nothing in it, because there is nothing to run: what this
		-- job does is BE there until the minute comes.
		prog = {},
		name = "shutdown",
		cmd = data.cmd or "shutdown",
		bg = true,
		-- The account that gave the order, which is the account the command ran as
		-- and so is root for a `sudo shutdown +5`. It is what `kill` reads.
		session = { user = data.user or session.user, cwd = "/", stamp = session.stamp },
	})
	job.shutdown = { at = data.at, kind = data.kind or "shutdown", warned = false }
	job.state = "waiting"
	return enrol(system, luaObject, console, job, true)
end

--
-- The dark interval of a reboot
--
-- A machine that is coming back is off in the meantime, and "in the meantime" is
-- this pass -- the same clock the pending shutdown above is counted on, for the
-- same reason: there is no timer anywhere else on the machine.
--
-- RUNTIME state like that one, and not among the object's saved keys: a server
-- that went down while a machine was dark comes back with the machine off, which
-- is what a real one does when the power goes while it is down. The survivor
-- switches it on by hand.
--
-- It holds the players who were at the glass when it went dark, because they are
-- the ones the window is handed back to (SCeroSecSystem:reopenFor).
--

function CeroSecJobs.scheduleReboot(luaObject, at, waiting)
	if type(at) ~= "number" then return nil end
	luaObject.rebooting = { at = at, waiting = waiting }
	register(luaObject)
	return luaObject.rebooting
end

-- The moment the interval is up, on every pass, beside the shutdown clock. A
-- machine somebody switched on by hand while it was dark is simply let go: it is
-- already up, and turnOn says so.
function CeroSecJobs.checkReboot(system, luaObject, now)
	local pending = luaObject.rebooting
	if pending == nil then return end
	if pending.at - now > 0 then return end
	luaObject.rebooting = nil
	system:resumeReboot(luaObject, pending.waiting)
end

-- One line onto the machine's screen, and out to every window standing at it.
-- A broadcast is not a reply: it reaches everybody or it is not a broadcast.
local function broadcast(system, luaObject, line)
	local console = luaObject:consoleState()
	if console == nil then return end
	CeroSec.consolePush(console, line)
	system:pushScreen(luaObject, luaObject:osState(), console)
end

-- wall(1): lines onto EVERY terminal of the machine.
--
-- Which is more than the one above reaches. The machine's own console is one
-- terminal; every inbound session has one of its own (pty.console), on somebody
-- else's glass, and a broadcast that missed those would be a broadcast that missed
-- the people most likely to be caught out by it -- a survivor logged in from the
-- gate does not see the lights go off through the window.
--
-- The lines go through CeroSec.consolePush like everything else, so each one meets
-- the console's own rules once: sixty columns, no control byte, a hundred lines kept.
function CeroSecJobs.wall(system, luaObject, state, lines)
	if type(lines) ~= "table" or #lines == 0 then return end
	local screens = {}
	local own = luaObject:consoleState()
	if own ~= nil then screens[#screens + 1] = own end
	local ptys = CeroSecOS.ptyList(luaObject.ptys)
	for i = 1, #ptys do
		if type(ptys[i].console) == "table" then screens[#screens + 1] = ptys[i].console end
	end
	for i = 1, #screens do
		CeroSec.consolePushAll(screens[i], lines)
		system:pushScreen(luaObject, state, screens[i])
	end
end

-- The warning a minute out, and then the deed. Run for every machine that has a
-- pending order, on every pass, before any job is stepped: a machine with a
-- shutdown pending and nothing running must still go down at the minute it was
-- told to.
--
-- The lines are BROADCAST and not written into the job's own output, which is the
-- one place this differs from an ordinary process: "the system is going down" is a
-- message to every terminal on the machine -- wall's job on a real one -- and not
-- a line for whoever happened to type the order. So it goes to the machine's own
-- console, where every window standing at the glass reads it.
--
-- Two pending orders are two clocks and both are read. The first minute to arrive
-- takes the machine down and killAll takes the other order with it, which is what
-- happens on a real machine and needs nothing written here to make it so.
function CeroSecJobs.checkShutdown(system, luaObject, now)
	local book = luaObject.jobs
	if book == nil then return end
	for i = 1, #book.list do
		local job = book.list[i]
		local pending = job.shutdown
		if pending ~= nil and not CeroSecOS.jobIsOver(job) then
			-- A machine that is already off has no order to carry out. It is not
			-- cleared here: the power going out took the whole book with it.
			if not luaObject.on then return end
			local left = pending.at - now
			if left <= 0 then
				broadcast(system, luaObject, CeroSecOS.shutdownLine(pending.kind, 0))
				system:applyPower(luaObject, pending.kind)
				return
			end
			if not pending.warned and left <= 60000 then
				pending.warned = true
				broadcast(system, luaObject, CeroSecOS.shutdownLine(pending.kind, 1))
			end
		end
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
		-- And they are an ENVIRONMENT: a cron line runs a script, and a script is
		-- handed the exported names. PATH and HOME being exported is what makes a
		-- crontab line able to find a command at all.
		exported = CeroSecOS.loginExported(),
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

-- at: the one job, at the one time
--
-- The same machinery, read by the same sweep a minute: the queue is
-- /var/spool/at, a job is a file in it, and a job whose time has come becomes an
-- ordinary background job of that account's with its output going to that
-- account's mail -- cronFire does all of it, because there is nothing about an at
-- job that is different once it is running.
--
-- What IS different is the clock. cron's minute is either due or it is gone; an at
-- job is a thing somebody asked for and it sits in the queue until it has been
-- done, so a job whose time passed while the machine was off runs when the machine
-- comes back. That is what atrun does on a real one, and it is why there is no
-- "minute it last looked at" here: the question is whether the time has COME, not
-- whether this is the minute.
--
-- The file goes when the job starts, and only then: a job the machine had no room
-- for (four is the ceiling) is still in the queue next minute, which is the whole
-- difference between a queue and a crontab. cron SKIPS a line it cannot fork and
-- says so in the log, because the line will come round again; an at job would be
-- lost.
function CeroSecJobs.atPass(system, luaObject, now)
	if type(now) ~= "number" then return 0 end
	if not luaObject.on then return 0 end
	local state = luaObject:osState()
	local console = luaObject:consoleState()
	if state == nil or console == nil then return 0 end

	local jobs = CeroSecOS.atJobs(state)
	local fired = 0
	for i = 1, #jobs do
		local job = jobs[i]
		if job.when <= now then
			local account = CeroSecOS.getUser(state, job.user)
			if account == nil then
				-- An account that is not on the machine any more. Vixie's word for a
				-- crontab in that state, and his behaviour: it is not run -- and the
				-- job goes, because nothing will ever run it and a queue full of jobs
				-- belonging to nobody is a queue nobody can read.
				cronSay(state, job.user, "ORPHAN (no passwd entry)", now)
				CeroSecOS.removeNode(state, CeroSecOS.rootSession(),
					CeroSecOS.atJobPath(job.n), false, now)
			else
				local entry = { cmd = job.cmd }
				if cronFire(system, luaObject, console, state, job.user,
						account.home, entry, now) ~= nil then
					-- Started: the job is out of the queue. Before this line it was
					-- started once a minute for ever.
					CeroSecOS.removeNode(state, CeroSecOS.rootSession(),
						CeroSecOS.atJobPath(job.n), false, now)
					fired = fired + 1
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

--
-- Putting a cu back at the TNC's prompt
--
-- A `cu -l /dev/radio0` is a job that spends its life waiting: at cmd: for a line
-- to be typed, and then -- if the box has a link -- for that link to end or for
-- the survivor to interrupt back out of converse. Waiting costs nothing at all:
-- no clock runs and jobStep answers a waiting job in one test.
--
-- Between those two states the job holds no continuation, which is what keeps a
-- prompt off the glass while the session is on it. So the two doors back in are
-- here, and they are the only things on the server that touch a job's cont: one
-- says a line and asks again, the other says cu's last word and lets the program
-- end. The SHAPES are the engine's (CeroSecOS.tncSayCont, CeroSecOS.tncByeCont) --
-- nothing here knows what a continuation looks like inside.
--
-- `line` is the TNC's own word for whatever happened, or nil for nothing to say;
-- `to` is the station the link is STILL up to, or nil for a box with no link.
-- A pass follows, in whatever hand this was called in, so the prompt reaches the
-- glass in the same round trip as the key that caused it.
local function resumeTnc(system, luaObject, job, cont, line)
	if luaObject == nil or job == nil or not luaObject.on then return false end
	if CeroSecOS.jobIsOver(job) or job.state ~= "waiting" then return false end
	local state = luaObject:osState()
	if state == nil then return false end
	job.cont = cont
	if not CeroSecOS.jobInput(state, job, line or "",
			system:execEnv(luaObject, state, nil, nil)) then
		return false
	end
	CeroSecJobs.runMachine(system, luaObject, CeroSec.STEP_BUDGET_PER_MACHINE,
		getTimestampMs(), nil, nil, true, nil)
	return true
end

function CeroSecJobs.tncSay(system, luaObject, job, line, to)
	return resumeTnc(system, luaObject, job, CeroSecOS.tncSayCont(to), line)
end

function CeroSecJobs.tncBye(system, luaObject, job)
	return resumeTnc(system, luaObject, job, CeroSecOS.tncByeCont(), nil)
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
				vars = CeroSecOS.copyVars(job.vars),
				-- And the marks with them: a subshell knows which of its names are
				-- in the environment, or `./thing &` would hand that script nothing
				-- while the same line without the `&` handed it PATH and HOME.
				exported = CeroSecOS.copyExported(job.exported) }
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
		-- Orders the job gave that the MACHINE carries out with the job still
		-- running: a `wall` on every terminal, a `clear` on its own glass. They are
		-- taken whether or not the job is over -- a script broadcasts in the middle
		-- of itself -- and the job does not step again until they are gone from
		-- here (CeroSecOS.jobStep), so what the line after the broadcast writes is
		-- written after the broadcast went out and not before it.
		--
		-- Queued in order and carried out in order, with the other orders, after
		-- every screen has gone out: a broadcast paints screens that are not this
		-- job's, and a clear takes one away.
		--
		-- A session that has GONE takes its `clear` with it: the screen the order
		-- was for is not there any more, and the machine's own glass is somebody
		-- else's. A broadcast is the exception and needs no screen of its own --
		-- it walks every terminal there is -- so it goes out whatever became of
		-- the one it was written at.
		if job.orders ~= nil then
			local screen = screenOf(job)
			for k = 1, #job.orders do
				local control = job.orders[k].control
				if screen ~= nil or control == "wall" then
					orders[#orders + 1] = { console = screen or own, control = control,
						data = job.orders[k].data, forJob = job }
				end
			end
			job.orders = nil
			-- What tells the caller this pass carried one out, for the same reason
			-- `job.spawned` tells it about an `&`: the pass that does the machine's
			-- half of a line is never the pass the line finishes in, so a prompt
			-- held after it would swallow the next thing typed
			-- (SCeroSecSystem:startPrompt).
			job.ordered = true
		end
		-- An rsh a job is WAITING on, and a far session a job that has died left
		-- open. Both are collected with the orders below and carried out after
		-- every screen has gone out, because dialling paints the far machine's
		-- glass and a teardown paints this one's.
		--
		-- The job is not ended by either: an rsh is a wait and not an exit, so the
		-- order is given while the job that gave it is still on the book -- which
		-- is what lets the answer come back into it (CeroSecOS.jobRemote).
		if job.dial ~= nil and not CeroSecOS.jobIsOver(job) then
			-- Which KIND of dial. An rsh is the usual one and says so by carrying no
			-- control of its own; the TNC's dialog carries "tnclink", because what it
			-- asks for is a connect, a disconnect or a converse on a link this very
			-- job is holding (CeroSecNet.tncLink).
			orders[#orders + 1] = { console = screenOf(job) or own,
				control = job.dial.control or "rsh", data = job.dial, forJob = job }
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
	if #book.list == 0 and luaObject.rebooting == nil then
		forget(luaObject)
	end

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
		-- The pending order, as a process. A machine with no room for one says so
		-- where the line was typed, exactly as it does for an `&` it cannot start.
		local job, reason = CeroSecJobs.schedule(system, luaObject, console, data)
		if job == nil then
			CeroSec.consolePush(console, "shutdown: " .. tostring(reason))
			system:pushScreen(luaObject, state, console)
		end
	elseif control == "rlogin" or control == "rsh" or control == "cu" then
		CeroSecNet.answerDial(system, luaObject, console, control, data, playerObj, order.forJob)
	elseif control == "tnclink" then
		-- The TNC's dialog asking for something only the machine can do to a radio
		-- link. It is not a dial like the three above -- there is no session to
		-- open in three of the four cases -- and the job that asked lives through
		-- all of them, which is why it is handed over.
		CeroSecNet.tncLink(system, luaObject, console, data, order.forJob)
	elseif control == "hangup" and type(data) == "table" then
		-- A far session whose near end has gone. Nothing is delivered anywhere:
		-- the job that was waiting for it is over, and what the far machine wrote
		-- has nobody left to read it.
		local object = system:getLuaObjectAt(data.x, data.y, data.z)
		if object ~= nil then CeroSecNet.tearDown(system, object, data.line) end
	elseif control == "wall" and type(data) == "table" then
		CeroSecJobs.wall(system, luaObject, state, data.lines)
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
	-- Before the jobs are stepped, and that is the whole reason the pending order
	-- is a job that never runs rather than one asleep on a timer.
	for i = 1, n do CeroSecJobs.checkShutdown(system, order[i], now) end
	-- And the dark interval of a machine that is coming back, which is the same
	-- kind of clock and is owed the same punctuality: a player is standing in
	-- front of an unlit screen waiting for it.
	for i = 1, n do CeroSecJobs.checkReboot(system, order[i], now) end

	for i = 1, n do
		local machine = order[i]
		if machine.jobs ~= nil and #machine.jobs.list > 0 then
			if total <= 0 then return end
			local share = CeroSec.STEP_BUDGET_PER_MACHINE
			if share > total then share = total end
			total = total - CeroSecJobs.runMachine(system, machine, share, now)
		elseif machine.rebooting == nil then
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

--
-- The book across a save
--
-- A computer the world saved and loaded again was never switched off. Nobody
-- pulled the plug, the room still has its wire, and a daemon somebody started
-- with `&` last week is a daemon that is still running -- exactly as it would be
-- on a Unix box that nobody powered down. Until this change it was not: the book
-- was memory and a reload has none, so `sh autoclose.sh start &`, quitting to the
-- menu and coming back found a machine at its prompt with the doors it was
-- watching left open. That is the bug this section closes.
--
-- WHERE IT GOES. Inside the machine's own state, at `os.jobs`, and not as a
-- sixth saved key: `os` is already in CeroSec.OBJECT_SAVE_KEYS and the
-- serializer recurses into it. An added key inside a state is not a shape change
-- (docs/CONTRIBUTING.md, the compatibility contract), so nothing moves --
-- not STATE_VERSION, not SYSTEM_VERSION, not the saved keys -- and a build that
-- has never heard of the key reads a machine with one and ignores it, because
-- CeroSecOS.validate is not a closed namespace over the state's keys the way a
-- disk's is (CeroSecOS.diskFieldsOk).
--
-- WHEN IT IS WRITTEN. Events.OnSave, and there is one moment and this is it:
-- zombie.GameWindow.save(boolean) triggers "OnSave" at bytecode offset 302 and
-- calls zombie.globalObjects.SGlobalObjects.save() at offset 418 of the same
-- method (javap -p -c on 42.20.4), so the event runs before gos_cerosec.bin is
-- written and what the handler leaves on the state is what the save carries. A
-- snapshot on every scheduler pass was the other candidate and was rejected on
-- the arithmetic: ten copies of four job tables a second for every machine in
-- the county, for the sake of a thing that happens when a player quits.
--
-- WHEN IT IS READ. SCeroSecSystem:newLuaObject, which the engine calls once for
-- every machine in the save file with its saved fields already in the table
-- (SGlobalObject.new hands back the GlobalObject's own modData, :63-78). It is
-- the one road every machine comes in by, chunk loaded or not -- and a machine
-- out in a county nobody has walked through keeps its jobs the way it keeps its
-- cron, because neither is a thing in the world.
--
-- AND IT IS READ THERE AND NOWHERE ELSE, which is what keeps a CLIENT out of it.
-- A state also arrives from an ITEM's movableData -- a computer carried across
-- town, which on a server is a table a client wrote -- and that road ends in
-- SCeroSecObject:resetForPlacement, which switches the machine off and calls
-- killAll. So no job is ever built out of a table a client handed over. What is
-- read here is gos_cerosec.bin, which is the same trust the filesystem in it
-- already has, and it is still read through a gate (jobFromData below).
--
-- WHAT SURVIVES, and it is decided per job rather than for the book:
--
--   * a background `&` job, and a cron or `at` child, whose output goes to a
--     mailbox on the disk. Both survive.
--   * the foreground job of the machine's OWN glass, because the console is
--     saved and comes back with it. The console's note of it is put back by
--     SCeroSecObject:consoleState, once, after the repair -- never by the
--     repair, so that a console naming a job that did not come back is a
--     console at its prompt and not a screen with nothing to type at.
--   * NOT a job whose terminal was a session that came in over the wire
--     (job.pty). luaObject.ptys is not saved -- a reload has no sessions -- so
--     its screen is gone, and a job with nowhere to write is one the scheduler
--     kills anyway (runMachine, screenOf).
--   * NOT the line a player was in the middle of typing (job.interactive): a
--     machine comes back at its prompt, which is where the console's repair has
--     always left it.
--   * NOT a job that is WAITING. A pending `shutdown`, a `read` with its question
--     on the glass, a `cu` sitting at the TNC's cmd:, a `wait` -- each of them is
--     waiting on something a reload does not have: a wall clock that stood still,
--     a prompt token on a screen, a radio link, another job. One rule covers the
--     four and leaves no continuation to be handed back out of a save file.
--   * NOT a job holding something the WORLD owns: a session at the far end
--     (job.remote), a dial in flight (job.dial), a radio link (job.ring), an
--     order the machine has not carried out yet (job.orders), an `&` it has asked
--     for and not been given (job.spawn), a kill it has been asked for.
--   * a job in the MIDDLE OF A PIPELINE survives, at the step it was at, when
--     every stage of it is running, asleep or over: `ls /dev | grep ^door` is what
--     a polling daemon is in the middle of at one save in ten (see the graph form
--     below). A stage that is asking or waiting, or holding any of the things
--     above, refuses the whole job by name (stageRefused), exactly as the job
--     itself would be refused.
--
-- THE CLOCK. A sleep is saved as the milliseconds it has LEFT and not as the
-- moment it is due. getTimestampMs is System.currentTimeMillis (javap
-- zombie.Lua.LuaManager$GlobalObject), so an absolute wake time would survive a
-- save honestly enough -- but the world stood still while the game was shut, and
-- a machine that was never switched off did not spend those hours asleep. Left
-- is what it means: a daemon that had 400 ms of its `sleep 1` to go has 400 ms of
-- it to go, and a `sleep 3600` started a minute before you quit still has
-- fifty-nine minutes on it when you come back. The runaway clock (job.cpuSince)
-- is NOT carried: continuous processor time is what it counts, and a job that has
-- just been rebuilt has spent none.
--

-- What a value costs, in one walk: the bytes the serializer writes and the
-- number of TABLES, which is the budget CeroSecOS.validate spends on the state.
-- Both are wanted and neither is worth a second walk. The depth guard is not
-- about legality -- a live job has no cycle in it -- but this walks tables off a
-- save file too, and an unbounded recursion there is a server that does not come
-- up.
--
-- WHERE the count starts is the caller's to say, because the state gate counts from
-- the root of the STATE (CeroSecOSState checkPlain, 64 tables down at most) and a
-- book entry sits three levels below it: state, jobs, list, entry -- and the graph
-- one more level down again, at `packed`. A walk that counted from the job's own
-- root let through a job whose deepest table was sixty-four down from `packed`
-- and sixty-seven from the state, which the gate then refuses as too deep: a
-- refusal that is sticky, on a machine that was doing nothing wrong.
local WEIGH_DEPTH = 64
-- entry (at 3, so 2 above it), and packed a level below it
local ENTRY_BASE = 2
local PACKED_BASE = ENTRY_BASE + 1

local function weigh(value, tally, depth)
	local t = type(value)
	if t == "string" then return #value + 2 end
	if t == "number" then return 8 end
	if t == "boolean" then return 1 end
	if t ~= "table" then return 0 end
	depth = (depth or 0) + 1
	tally.tables = tally.tables + 1
	if depth > WEIGH_DEPTH then
		tally.over = true
		tally.deep = true
		return 0
	end
	if tally.tables > tally.max then
		tally.over = true
		return 0
	end
	local bytes = 0
	for k, sub in pairs(value) do
		bytes = bytes + weigh(k, tally, depth) + weigh(sub, tally, depth)
	end
	return bytes
end

CeroSecJobs.weigh = weigh

-- The parse tree's own shape, asked of a program that came off a save file.
--
-- Not the grammar: what the walker does with a node it does not know is already
-- an answer -- pushNode ends the job with `sh: syntax error` -- so what is needed
-- here is only that the walker cannot be made to INDEX something that is not a
-- table. One rule does it, and it was checked against every program this parser
-- makes -- every script the world content ships, plus one line of every shape the
-- grammar has, each made into a job and handed back through the gate
-- (tests/window_test.lua, section 44d): every value at an integer key is a table,
-- `k` and `t` are strings where they appear, and the one exception is `ops` -- a
-- list node's `&&`, `||` and `;`, which really are strings in an array.
--
-- `done` is the set of tables already answered for, and it is passed by the graph
-- form's gate only: a tree that came out of a graph is shared between the job, its
-- frames and its stages, and a forged graph can share one table many times over,
-- so walking it once per path would be the cost of a bomb.
local function programOk(value, depth, done)
	if type(value) ~= "table" then return false end
	depth = (depth or 0) + 1
	if depth > WEIGH_DEPTH then return false end
	if done ~= nil then
		if done[value] then return true end
		done[value] = true
	end
	for k, sub in pairs(value) do
		if type(k) == "number" then
			if type(sub) ~= "table" then return false end
		elseif k == "k" or k == "t" then
			if type(sub) ~= "string" then return false end
		elseif k == "ops" then
			if type(sub) ~= "table" then return false end
			for i = 1, #sub do
				if type(sub[i]) ~= "string" then return false end
			end
		end
		if type(sub) == "table" and k ~= "ops" then
			if not programOk(sub, depth, done) then return false end
		end
	end
	return true
end

-- How many pipelines may sit inside one another. A stage is a job, so a stage may
-- itself be running a pipeline (`a | for x in $(b | c); do ..; done | d`); a real
-- script nests a level or two, and the bound is what lets both the save and the
-- gate recurse without trusting the shape they are handed.
local MAX_NEST = 8

local stageRefused

-- The frames of one job or stage, asked for what a pipeline in them holds.
local function framesRefused(frames, depth)
	for i = 1, #frames do
		local frame = frames[i]
		if type(frame) ~= "table" then return "bad frame" end
		if frame.stages ~= nil then
			-- A PIPELINE IN FLIGHT is saved, stage by stage (the graph form above), when
			-- every stage is somewhere a save can put it back: running, asleep, or
			-- finished. What is refused is refused by NAME, below.
			if frame.asking ~= nil then return "a stage is waiting" end
			if frame.dialling ~= nil then return "a stage on the wire" end
			if type(frame.stages) ~= "table" or type(frame.pipes) ~= "table" then
				return "bad frame"
			end
			-- The counts the reader (pipeOk) insists on, asked at the save too, so that
			-- a job it would drop is left out here with a reason in the log and not
			-- written to be dropped a session later.
			if #frame.stages > CeroSecOS.MAX_STAGES or #frame.pipes ~= #frame.stages then
				return "bad frame"
			end
			for k = 1, #frame.stages do
				local why = stageRefused(frame.stages[k], depth + 1)
				if why ~= nil then return why end
			end
		end
	end
	return nil
end

-- One stage of a pipeline. It is a job of its own, so it is asked what a job is
-- asked, minus what only the job holding the glass has (job.pty, job.interactive)
-- -- and plus what only a stage can be caught doing. The reasons are the ones the
-- top job's rule already has, said of a stage:
--
--   * waiting: a stage at a question (ask, cont), at a `wait` (waitFor), at a
--     shutdown (timer) or in any state but running, asleep or over. pipeStep has
--     no road from a saved stage back to any of them -- the question lives on the
--     job, the answer is routed by frame.asking -- so restoring one would restore
--     a stuck job, and a stuck job is worse than a job that did not come back.
--   * the wire: a dial or a radio link, or a session at the far end.
--   * mid-order: an order for the machine (orders, control), an `&` asked for and
--     not granted, a kill asked for and not delivered.
--
-- A stage that is OVER is fine and is common: in `cat f | grep x | wc -l` the
-- first one is done long before the last. Its frames are gone and its pipe says
-- eof, which is exactly what its reader still has to be told.
function stageRefused(stage, depth)
	if type(stage) ~= "table" then return "bad frame" end
	if depth > MAX_NEST then return "too deep" end
	if not CeroSecOS.jobIsOver(stage) and stage.state ~= "running"
			and stage.state ~= "sleeping" then
		return "a stage is waiting"
	end
	if stage.ask ~= nil or stage.cont ~= nil or stage.waitFor ~= nil
			or stage.timer ~= nil then
		return "a stage is waiting"
	end
	if stage.dial ~= nil or stage.ring ~= nil or stage.remote ~= nil then
		return "a stage on the wire"
	end
	if stage.orders ~= nil or stage.control ~= nil or stage.spawn ~= nil
			or stage.killReq ~= nil then
		return "a stage mid-order"
	end
	if type(stage.prog) ~= "table" or type(stage.frames) ~= "table" then
		return "no program"
	end
	return framesRefused(stage.frames, depth)
end

-- Which jobs are written, and the word for why one is not. nil when it survives.
function CeroSecJobs.jobRefused(job)
	if type(job) ~= "table" then return "not a job" end
	if CeroSecOS.jobIsOver(job) then return "over" end
	if job.state ~= "running" and job.state ~= "sleeping" then return "waiting" end
	if job.pty ~= nil then return "a session" end
	if job.remote ~= nil or job.dial ~= nil or job.ring ~= nil then return "the wire" end
	if job.orders ~= nil or job.spawn ~= nil or job.killReq ~= nil then return "mid-order" end
	if type(job.prog) ~= "table" or type(job.frames) ~= "table" then return "no program" end
	return framesRefused(job.frames, 0)
end

-- What is left OUT of a job, and it is a deny-list on purpose.
--
-- An allow-list would silently drop a field the VM grows next, and a job that
-- comes back missing one of them is a job that runs subtly wrong -- which is the
-- failure nobody would ever find. A deny-list fails the other way: a new field
-- rides along, and it is safe to let it, because the engine's own door rule says
-- what a job may hold. CeroSecOSVM makes no game call, keeps no coroutine, no
-- metatable and no function anywhere in a job, so there is nothing in one that
-- could be a handle to something the save file cannot carry.
--
-- fprog is the only thing, and it is a CACHE: the function bodies parsed out of
-- the text in job.funcs, rebuilt on the first call after the load. The frames
-- carry their own copy of it (oldFprog, the caller's, put back on the way out of
-- a script) and that goes for the same reason. Which table a name is dropped
-- from is decided by the ROLE of the table in the walk (internValue): a job, a
-- stage, a frame.

-- The plain copy, which is what a book entry in the FLAT form is read through (a
-- job written before the graph form: the entry is the job itself, and it is a
-- tree). `seen` is kept along the PATH being walked, exactly as
-- CeroSecOS.validate's own checkPlain keeps it, so a table that leads back to
-- itself is caught here and the job is refused instead of being copied until the
-- depth guard gives out.
--
-- flags carries what went wrong back up, because the copy answers a table and a
-- table cannot also say "no".
local function copyJobData(value, drop, depth, seen, flags)
	if type(value) ~= "table" then return value end
	depth = (depth or 0) + 1
	if depth > WEIGH_DEPTH then
		flags.deep = true
		return nil
	end
	if seen[value] then
		flags.cycle = true
		return nil
	end
	seen[value] = true
	local out = {}
	for k, sub in pairs(value) do
		if drop == nil or not drop[k] then
			out[k] = copyJobData(sub, nil, depth, seen, flags)
		end
	end
	seen[value] = nil
	return out
end

-- THE GRAPH FORM: a job written with the identity it has in memory.
--
-- The serializer has no identity map (docs/notes/modules-proofs.md), so a table
-- reached from several places is written once per place and comes back as as many
-- tables. For a job that is not a nicety, it is two problems:
--
--   * WEIGHT. The parse tree of the script is reached from job.prog, from the
--     frames that walk it and from every stage of a pipeline: one copy of the text
--     is three copies of the tree, and the shipped autoclose.sh was 925 tables
--     asleep and 1205 in the middle of `ls /dev | grep ^door`, against a book of
--     2048 for the whole machine.
--   * MEANING. A pipe is ONE table held by the stage that writes it, the stage
--     that reads it and the frame that drains it; a stage's `errTo` is the job that
--     owns the pipeline. A tree copy hands back three pipes that never meet, and
--     a writer's `eof` that reaches nobody.
--
-- So the first time a table is reached it is copied, and every later reach is the
-- marker { ["$ref"] = id }, the copy it points at carrying ["$id"] = id. Only a
-- table that IS reached twice gets an id, so a job with no sharing in it costs
-- what it always did. A ref is one small table, and what the state gate counts is
-- tables: the shipped daemon mid-pipeline is about 370 of them (351 distinct and
-- 19 markers, measured) and not 1205.
--
-- The walk carries a ROLE and not a list of names to drop: `fprog` is dropped from
-- a job (and from a stage, which is one) and `oldFprog` from a frame, and nowhere
-- else, because job.vars maps the player's own names to text and a player may call
-- a variable `fprog`. The same walk turns every sleeping job's wakeMs, the
-- pipeline's stages included, into what is LEFT of it (see the header above).
--
-- What a sleep may have LEFT, in milliseconds: a thousand million seconds, thirty
-- one years, which is more than any script means by `sleep`. A number the clock
-- cannot do arithmetic on -- `sleep inf`, `sleep nan`, where the shell's tonumber
-- reads them -- is written as this, and it is the most a save file may claim: a
-- job that asks for more is forged (shapeOfJob), because NaN and infinity compare
-- false with every clock there is, so a job that carried one would be asleep for
-- ever whatever the machine did.
local SLEEP_MAX_MS = 1e12

local INTERN_ROLE = {
	-- what a table reached under a key of a role is, by the key
	job = { frames = "frames" },
	frame = { stages = "stages" },
}

local function internValue(value, role, st, depth)
	if type(value) ~= "table" then return value end
	local prior = st.seen[value]
	if prior ~= nil then
		if prior["$id"] == nil then
			st.nextId = st.nextId + 1
			prior["$id"] = st.nextId
		end
		return { ["$ref"] = prior["$id"] }
	end
	depth = depth + 1
	if depth > WEIGH_DEPTH then
		st.flags.deep = true
		return nil
	end
	local out = {}
	st.seen[value] = out
	for k, sub in pairs(value) do
		if type(k) == "table" or type(k) == "function" then
			st.flags.badkey = true
		elseif k == "$id" or k == "$ref" then
			-- The one thing the form cannot say: a table that already means a marker.
			st.flags.clash = true
		elseif role == "job" and (k == "fprog" or k == "cpuSince") then
			-- dropped: a cache, and the machine's own clock
		elseif role == "frame" and k == "oldFprog" then
			-- dropped: the caller's cache, put back on the way out of a script
		else
			local child = "plain"
			if role == "job" then child = INTERN_ROLE.job[k] or "plain"
			elseif role == "frame" then child = INTERN_ROLE.frame[k] or "plain"
			elseif role == "frames" then child = "frame"
			elseif role == "stages" then child = "job" end
			out[k] = internValue(sub, child, st, depth)
		end
	end
	if role == "job" then
		out.wakeMs = nil
		if value.state == "sleeping" and type(value.wakeMs) == "number"
				and type(st.nowMs) == "number" then
			local left = value.wakeMs - st.nowMs
			if left ~= left or left > SLEEP_MAX_MS then
				left = SLEEP_MAX_MS
			elseif left < 0 then
				left = 0
			end
			out.sleepLeft = left
		end
	end
	return out
end

-- A job as a graph, or nil plus the flags that say why not. Pure: nothing on the
-- job is touched. `base` is how many tables sit above the job where it will be
-- written (see WEIGH_DEPTH); the save says three, and a caller that only wants the
-- shape says nothing.
function CeroSecJobs.intern(job, nowMs, base)
	local st = { seen = {}, nextId = 0, flags = {}, nowMs = nowMs }
	local out = internValue(job, "job", st, base or 0)
	return out, st.flags
end

-- The way back, in two passes and in no order at all. What a save file hands back
-- is a tree of tables, and `pairs` may walk it in a different order than it was
-- written in, so a ref can be met before the table it names. Pass one only READS:
-- it counts every table against `max` (a forged file is bounded by what a real
-- one may cost), bounds the depth, and registers every ["$id"]. Pass two replaces
-- each marker by the table registered under its id and takes the ids off. A
-- marker is exactly one key, a number, so that a table that merely looks like one
-- is refused and not half-resolved. Nothing is evaluated: it is shape and
-- numbers all the way down.
--
-- The tables of `packed` are the ones handed back, so it is the caller's copy and
-- not the save file's that must go in.
function CeroSecJobs.resolve(packed, max)
	if type(packed) ~= "table" then return nil, "not a table" end
	local registry, count = {}, 0
	local function markerOf(t)
		local ref = t["$ref"]
		if ref == nil then return false end
		local n = 0
		for _ in pairs(t) do n = n + 1 end
		if n ~= 1 or type(ref) ~= "number" then return nil end
		return true
	end
	local function collect(t, depth)
		count = count + 1
		if count > max then return "too large" end
		if depth > WEIGH_DEPTH then return "too deep" end
		local marker = markerOf(t)
		if marker == nil then return "bad ref" end
		if marker then return nil end
		local id = t["$id"]
		if id ~= nil then
			if type(id) ~= "number" or id ~= id or id < 1 or id ~= math.floor(id) then
				return "bad id"
			end
			if registry[id] ~= nil then return "duplicate id" end
			registry[id] = t
		end
		for k, sub in pairs(t) do
			if type(k) == "table" then return "bad key" end
			if type(sub) == "table" then
				local why = collect(sub, depth + 1)
				if why ~= nil then return why end
			end
		end
		return nil
	end
	if packed["$ref"] ~= nil then return nil, "bad ref" end
	local why = collect(packed, 1)
	if why ~= nil then return nil, why end
	local function replace(t)
		local swap = nil
		for k, sub in pairs(t) do
			if type(sub) == "table" then
				local ref = sub["$ref"]
				if ref ~= nil then
					local target = registry[ref]
					if target == nil then return "bad ref" end
					swap = swap or {}
					swap[#swap + 1] = k
					swap[#swap + 1] = target
				else
					local bad = replace(sub)
					if bad ~= nil then return bad end
				end
			end
		end
		if swap ~= nil then
			for i = 1, #swap, 2 do t[swap[i]] = swap[i + 1] end
		end
		t["$id"] = nil
		return nil
	end
	local bad = replace(packed)
	if bad ~= nil then return nil, bad end
	return packed
end

-- One job as the save file will hold it, or nil plus the word for why not.
--
-- The entry is { packed = <the job as a graph> } and not the job itself. The name
-- of the key is what keeps a build from before the graph form honest: it finds no
-- `id` and no `prog` on an entry it does not know, and drops that ONE job with a
-- line in the log (jobFromData's gate) instead of running half of one. The flat
-- entry, which is what every build wrote until now, is still read.
function CeroSecJobs.jobToData(job, nowMs, fg)
	local refusal = CeroSecJobs.jobRefused(job)
	if refusal ~= nil then return nil, refusal end
	-- The prompt's own job is saved only while it is really the one holding the
	-- glass, because that is the only thing that can give it its shell back
	-- (CeroSecJobs.restoreForeground). One that is not is a shell nobody would be
	-- typing at, and it is left where every job used to be left.
	if job.interactive and not fg then return nil, "an orphan prompt" end
	local packed, flags = CeroSecJobs.intern(job, nowMs, PACKED_BASE)
	if flags.deep then return nil, "too deep" end
	if flags.clash or flags.badkey then return nil, "not plain data" end
	-- Whether this one was holding the glass. Worked out by the caller, which is
	-- the only place that has the console to ask.
	if fg then packed.fg = true end
	return { packed = packed }
end

-- An array of strings, and nothing else in it. What a job holds under `out` and
-- `args` reaches the screen and the expansions as text, so a table at one of those
-- positions is not a wrong value, it is a concatenation that throws.
local function stringArray(list)
	if type(list) ~= "table" then return false end
	for i = 1, #list do
		if type(list[i]) ~= "string" then return false end
	end
	return true
end

-- A table of name -> text, the shape job.vars and job.funcs are. `want` is what a
-- value has to be, because job.exported is name -> true.
local function stringMap(map, want)
	if type(map) ~= "table" then return false end
	for name, value in pairs(map) do
		if type(name) ~= "string" then return false end
		if want == "boolean" then
			if value ~= true then return false end
		elseif type(value) ~= "string" then
			return false
		end
	end
	return true
end

-- The shape of a job or of one stage of a pipeline, asked of what came off a save
-- file. The same rule for both, because a stage IS a job: what the walker indexes
-- has to be a table, what it prints or concatenates has to be a string.
local shapeOfJob

-- What a pipe says it holds: bytes is the running total of what is in `lines`
-- (each line and its newline; the VM adds it on the write and takes it off on the
-- read), so it is a finite whole number, nowhere above what a save may carry and
-- nowhere above what the lines really add up to. NaN is what pipeFull cannot
-- answer -- it is never full, and a writer that never waits is a job that eats
-- memory -- and a number past what is in it is a pipe that is full of nothing.
-- The ceiling is NOT PIPE_LINES or PIPE_BYTES: those are back-pressure, asked
-- before a stage is stepped, and one step of `cat` puts a whole file in (2041 short
-- lines and 8162 bytes, measured), so a legal pipe passes both.
local function pipeBytesOk(pipe)
	local bytes = pipe.bytes
	if bytes ~= bytes or bytes < 0 or bytes > CeroSec.JOB_SAVE_BYTES
			or bytes ~= math.floor(bytes) then
		return false
	end
	local held = 0
	for i = 1, #pipe.lines do held = held + #pipe.lines[i] + 1 end
	return bytes <= held
end

-- One pipe frame: the counts and the links the walker relies on. `pipes[i]` is
-- what stage i writes and what stage i+1 reads, the frame drains the last one, and
-- every stage answers its refusals to the job that owns the pipeline -- so those
-- are TESTED to be the same tables, and not merely tables of the right shape, or
-- a forged graph could hand the walker a pipeline whose stages never meet.
local function pipeOk(frame, owner, depth, ctx)
	local stages, pipes = frame.stages, frame.pipes
	if type(stages) ~= "table" or type(pipes) ~= "table" then return "bad frame" end
	local n = #stages
	if n < 1 or n > CeroSecOS.MAX_STAGES or #pipes ~= n then return "bad frame" end
	if frame.asking ~= nil or frame.dialling ~= nil then return "bad frame" end
	for i = 1, n do
		local pipe, stage = pipes[i], stages[i]
		if type(pipe) ~= "table" or type(pipe.bytes) ~= "number"
				or type(pipe.eof) ~= "boolean" or type(pipe.closed) ~= "boolean"
				or not stringArray(pipe.lines) then
			return "bad frame"
		end
		-- One pipe each: two stages that write into the same table are one pipe with
		-- two writers and a reader that is told eof by whichever ends first.
		if ctx.pipes[pipe] then return "bad frame" end
		ctx.pipes[pipe] = true
		if not pipeBytesOk(pipe) then return "bad frame" end
		if type(stage) ~= "table" or ctx.stages[stage] then return "bad frame" end
		if stage.pipe ~= pipe or stage.stdinBuf ~= pipes[i - 1] or stage.errTo ~= owner then
			return "bad frame"
		end
		ctx.stages[stage] = true
		local why = shapeOfJob(stage, true, depth + 1, ctx)
		if why ~= nil then return why end
	end
	return nil
end

function shapeOfJob(job, isStage, depth, ctx)
	if depth > MAX_NEST then return "too deep" end
	if isStage and (type(job.name) ~= "string" or type(job.cmd) ~= "string") then
		return "no name"
	end
	if type(job.session) ~= "table" or type(job.session.user) ~= "string" then
		return "no session"
	end
	if not stringMap(job.vars) then return "no shell" end
	if not stringArray(job.out) or not stringArray(job.args) then return "no shell" end
	if job.exported ~= nil and not stringMap(job.exported, "boolean") then
		return "no shell"
	end
	if job.funcs ~= nil and not stringMap(job.funcs) then return "no shell" end
	-- The clock of a sleep is a number of milliseconds and one that is finite: what
	-- the walker compares it with is the machine's own clock, and nothing compares
	-- true with NaN or with more than there is. Below nought is what the save
	-- itself clamps and restoreClocks clamps again; the ceiling is SLEEP_MAX_MS.
	local left = job.sleepLeft
	if left ~= nil and (type(left) ~= "number" or left ~= left
			or left > SLEEP_MAX_MS or left < -SLEEP_MAX_MS) then
		return "bad clock"
	end
	if not programOk(job.prog, 0, ctx.done) then return "bad program" end
	local frames = job.frames
	if type(frames) ~= "table" or #frames > CeroSecOS.MAX_FRAMES then
		return "bad frames"
	end
	-- A stage that is over has no frames left; nothing else has none.
	if #frames < 1 and not (isStage and CeroSecOS.jobIsOver(job)) then
		return "bad frames"
	end
	for i = 1, #frames do
		local frame = frames[i]
		if type(frame) ~= "table" or type(frame.k) ~= "string" then return "bad frame" end
		-- The two fields a frame walks into. A frame that carries neither is one
		-- of the walker's own and is left alone.
		if frame.prog ~= nil and not programOk(frame.prog, 0, ctx.done) then
			return "bad frame"
		end
		if frame.node ~= nil and not programOk(frame.node, 0, ctx.done) then
			return "bad frame"
		end
		if frame.stages ~= nil then
			if not ctx.graph then return "a pipeline" end
			local why = pipeOk(frame, job, depth, ctx)
			if why ~= nil then return why end
		end
	end
	return nil
end

-- No cycle in what the graph came back as, except the one the engine makes itself:
-- a stage's errTo. Marked along the path and finished once, so a graph that shares
-- a table many times over is walked once and not once per way in.
local function acyclic(value, ctx, depth)
	if type(value) ~= "table" then return true end
	local mark = ctx.mark[value]
	if mark == 1 then return false end
	if mark == 2 then return true end
	if depth > 2 * WEIGH_DEPTH then return false end
	ctx.mark[value] = 1
	for k, sub in pairs(value) do
		if not (k == "errTo" and ctx.stages[value]) then
			if not acyclic(sub, ctx, depth + 1) then return false end
		end
	end
	ctx.mark[value] = 2
	return true
end

-- The clocks of a job and of every stage under it, put back the other way round
-- from the save: a sleep that had so much LEFT is due that much after now.
local function restoreClocks(job, nowMs, depth)
	local left = job.sleepLeft
	job.sleepLeft = nil
	job.wakeMs = nil
	if job.state == "sleeping" then
		if type(left) ~= "number" or left < 0 then left = 0 end
		job.wakeMs = (nowMs or 0) + left
	end
	job.cpuSince = nil
	if depth > MAX_NEST or type(job.frames) ~= "table" then return end
	for i = 1, #job.frames do
		local frame = job.frames[i]
		if type(frame) == "table" and type(frame.stages) == "table" then
			for k = 1, #frame.stages do restoreClocks(frame.stages[k], nowMs, depth + 1) end
		end
	end
end

-- One job back off the save file, or nil plus the reason. This is the gate: what
-- comes through it is a table out of gos_cerosec.bin, and the belt every other
-- thing in the state gets is the belt it gets.
--
-- What it asks is DERIVED from what the engine does with a field and not from the
-- defects anybody has met: a field the walker indexes has to be a table, a field it
-- prints or concatenates has to be a string, and everything the SAVE refuses to
-- write is refused again on the way in through the very same rule
-- (CeroSecJobs.jobRefused), so a forged book cannot hand back a job holding a dial,
-- a radio link or an order the machine would carry out -- in a stage as in the job.
--
-- Two forms come in. { packed = graph } is what is written now: the size is asked
-- of the graph before anything is built from it, then it is resolved (two passes,
-- CeroSecJobs.resolve) and the resolved job is asked what the flat one is, plus
-- what a pipeline has -- the pipes and the stages have to be the same tables the
-- walker will index, stage by stage, and nothing but the stages' own errTo may
-- lead back to where it came from. The flat form, an entry that is the job itself,
-- is read as it always was and cannot carry a pipeline: no build ever wrote one.
function CeroSecJobs.jobFromData(data, nowMs)
	if type(data) ~= "table" then return nil, "not a table" end
	local graph = data.packed ~= nil
	local ctx = { graph = graph, stages = {}, pipes = {}, done = {}, mark = {} }
	local root = data
	if graph then
		if type(data.packed) ~= "table" then return nil, "not a table" end
		local one = { tables = 0, max = CeroSec.JOB_SAVE_TABLES }
		local bytes = weigh(data.packed, one)
		if one.over or bytes > CeroSec.JOB_SAVE_BYTES then return nil, "too large" end
		local why
		root, why = CeroSecJobs.resolve(data.packed, CeroSec.JOB_SAVE_TABLES)
		if root == nil then return nil, why end
	end
	if type(root.id) ~= "number" then return nil, "no id" end
	if root.n ~= nil and (type(root.n) ~= "number" or root.n < 1
			or root.n > CeroSecOS.MAX_JOBS) then
		return nil, "bad slot"
	end
	if root.state ~= "running" and root.state ~= "sleeping" then return nil, "bad state" end
	if type(root.name) ~= "string" or type(root.cmd) ~= "string" then return nil, "no name" end
	if root.interactive and not root.fg then return nil, "an orphan prompt" end
	if root.errTo ~= nil then return nil, "bad frame" end
	local why = shapeOfJob(root, false, 0, ctx)
	if why ~= nil then return nil, why end
	local job = root
	if graph then
		if not acyclic(root, ctx, 0) then return nil, "a cycle" end
	else
		-- A copy and never the table off the save file itself: what the scheduler
		-- steps has to be ours, and the state this came out of is cleared behind it.
		-- The same cycle guard as on the way out, for a table that has been through a
		-- file.
		local flags = {}
		job = copyJobData(root, nil, 0, {}, flags)
		if flags.cycle then return nil, "a cycle" end
		if flags.deep then return nil, "too deep" end
	end
	-- The clock again, the other way round.
	restoreClocks(job, nowMs, 0)
	-- Whatever the last pass left of the machine's half of a line. The pass that
	-- rebuilt this job is not the pass that made it, so neither flag means
	-- anything any more (SCeroSecSystem:startPrompt reads them).
	job.spawned = nil
	job.ordered = nil
	-- And the save's own rule, asked again on the way in. What the writer will not
	-- write is what the reader will not take -- a job holding a dial, a session at
	-- the far end, a radio link, an order the machine has not carried out, or a
	-- pipeline with a stage that is asking or waiting -- so a forged book cannot
	-- hand one back by putting on the state something no save would ever have made.
	local refusal = CeroSecJobs.jobRefused(job)
	if refusal ~= nil then return nil, refusal end
	return job
end

-- The reasons a job is left out of a save that are not news: what the job is
-- doing (asking, dialling, holding a session) and not what is wrong with it.
local NOT_SAVED_QUIETLY = {
	["over"] = true, ["waiting"] = true, ["a session"] = true, ["the wire"] = true,
	["mid-order"] = true, ["an orphan prompt"] = true, ["a stage is waiting"] = true,
	["a stage on the wire"] = true, ["a stage mid-order"] = true,
}

-- The machine's book onto its state, at the save. Answers how many jobs went in.
function CeroSecJobs.writeBook(luaObject, nowMs)
	local book = luaObject.jobs
	if book == nil or #book.list == 0 or not luaObject.on then
		-- Nothing running, so the copy on the state goes -- raw, and without asking
		-- the gate: what has to go is whatever is in the table the serializer will
		-- reach, and a machine running nothing is not one to spend a walk of a
		-- filesystem on at the moment somebody is quitting.
		if type(luaObject.os) == "table" then luaObject.os.jobs = nil end
		return 0
	end
	local state = luaObject:osState()
	if state == nil then return 0 end
	local console = luaObject.console
	local held = nil
	if type(console) == "table" and type(console.job) == "number" then held = console.job end

	local list, over, spent = {}, 0, 0
	local where = "the machine at " .. luaObject.x .. "," .. luaObject.y .. ","
		.. luaObject.z
	for i = 1, #book.list do
		local job = book.list[i]
		local data, why = CeroSecJobs.jobToData(job, nowMs, held ~= nil and job.id == held)
		if data == nil then
			-- A job that is waiting, or holds a session, is left out as a matter of
			-- course and the log is not the place for it. Anything else is a job the
			-- player had running that will not be there when he comes back for a
			-- reason he cannot see, so it says why.
			if why ~= nil and not NOT_SAVED_QUIETLY[why] then
				CeroSec.log(CeroSec.LOG_ERROR, where .. " left a job out of the save: "
					.. why)
			end
		else
			-- Weighed once, against the machine's own ceiling and against what is
			-- left of the book's: a job past CeroSec.JOB_SAVE_BYTES is refused on its
			-- own account, and one that fits is still refused when the jobs before it
			-- have spent the table budget the state gate is going to count. Counted
			-- from where the entry will sit in the state, so that the depth the gate
			-- is going to see is the depth that is asked (WEIGH_DEPTH).
			local one = { tables = 0, max = CeroSec.JOB_SAVE_TABLES }
			local bytes = weigh(data, one, ENTRY_BASE)
			if one.deep then
				CeroSec.log(CeroSec.LOG_ERROR, where .. " left a job out of the save: too deep")
			elseif one.over or bytes > CeroSec.JOB_SAVE_BYTES
					or spent + one.tables > CeroSec.JOB_SAVE_TABLES then
				over = over + 1
			else
				spent = spent + one.tables
				list[#list + 1] = data
			end
		end
	end
	if #list == 0 then
		state.jobs = nil
	else
		-- seq goes with them, or the ids handed out after the load would be ids
		-- that are already on the machine.
		state.jobs = { seq = book.seq, list = list }
	end
	if over > 0 then
		CeroSec.log(CeroSec.LOG_ERROR, where .. " left " .. over
			.. " job(s) out of the save: too large")
	end
	return #list
end

-- Every machine in the county, at the save.
--
-- The county and not CeroSecJobs.machines, which was the first shape and was
-- wrong: a machine whose last job ENDED is not one the scheduler holds any more --
-- runMachine forgets it the pass its book empties -- so a save taken after that
-- would never reach it and the job it was running at the save BEFORE would still
-- be on its state, to come back on the next load as a job somebody had already
-- watched finish. A bench found it.
--
-- What makes the walk affordable is that it decides on two raw field reads: a
-- machine with no book and nothing on its state is passed over without a call.
-- Three hundred dark machines cost six hundred reads, once, at the moment the game
-- is saving anyway.
function CeroSecJobs.saveBooks()
	local system = CeroSecJobs.system
	if system == nil then return end
	local now = 0
	if getTimestampMs ~= nil then now = getTimestampMs() end
	local n = system:getLuaObjectCount()
	for i = 1, n do
		local luaObject = system:getLuaObjectByIndex(i)
		if luaObject ~= nil and (luaObject.jobs ~= nil
				or (type(luaObject.os) == "table" and luaObject.os.jobs ~= nil)) then
			CeroSecJobs.writeBook(luaObject, now)
		end
	end
end

-- And the way back in, for one machine, at load. Answers how many jobs came
-- back. The state is read raw and not through osState(): this runs for every
-- machine in the save file, and walking the validator over a county of them
-- before anybody has looked at one is the cost that gate exists to avoid -- the
-- first real read does it, and a machine the gate then refuses is a machine
-- runMachine kills the book of on its first pass.
function CeroSecJobs.readBook(system, luaObject)
	if type(luaObject.os) ~= "table" then return 0 end
	local saved = luaObject.os.jobs
	-- Taken off the state whatever comes of it. A book is a thing a machine is
	-- RUNNING, not a thing that lies on its disk: leaving it there would have the
	-- next save write it again over a book that has since been killed, and a
	-- second load resurrect a job somebody stopped.
	luaObject.os.jobs = nil
	if type(saved) ~= "table" or type(saved.list) ~= "table" then return 0 end
	if not luaObject.on then return 0 end

	local now = 0
	if getTimestampMs ~= nil then now = getTimestampMs() end
	local book = CeroSecJobs.book(luaObject)
	if type(saved.seq) == "number" and saved.seq > book.seq then
		book.seq = math.floor(saved.seq)
	end
	local back = 0
	for i = 1, #saved.list do
		-- The machine's own ceiling, asked the way enrol asks it: the prompt's own
		-- job holds no slot and counts against nothing, so a forged list of five
		-- cannot put a fifth SCRIPT on a machine that takes four.
		if liveCount(book) >= CeroSecOS.MAX_JOBS then break end
		local job, why = CeroSecJobs.jobFromData(saved.list[i], now)
		if job == nil then
			CeroSec.log(CeroSec.LOG_ERROR, "the machine at " .. luaObject.x .. ","
				.. luaObject.y .. "," .. luaObject.z .. " dropped a saved job: "
				.. tostring(why))
		else
			book.list[#book.list + 1] = job
			back = back + 1
		end
	end
	if back == 0 then
		-- Nothing came back, so there is no book to keep and no machine to
		-- schedule: killAll puts both back the way they were.
		CeroSecJobs.killAll(luaObject)
		return 0
	end
	register(luaObject)
	if system ~= nil then CeroSecJobs.system = system end
	return back
end

-- The note the console keeps of the job holding its prompt, put back.
--
-- Here and not in CeroSec.repairConsole, and that is the whole safety of it: the
-- repair knows nothing about jobs, so a console it handed back with `job` still
-- on it would be a screen with nothing to type at whenever the job it named had
-- not come back -- and there is no way out of that but the switch. So the repair
-- goes on dropping it, and the note is put back only for a job that is really on
-- the book. Called once per machine per session, from SCeroSecObject:consoleState,
-- after the repair and before anything reads the screen.
-- And with it the one thing a COPY of a job gets wrong: the shell it runs on.
--
-- The prompt's own job holds the console's variables, its exported set and its
-- functions BY REFERENCE -- that is what makes `x=5` on one line and `echo $x` on
-- the next the same environment. A save writes two copies of one table and a load
-- hands back two tables, so a job rebuilt from one would be setting variables
-- nobody would ever read again.
--
-- Which level holds them depends on where the job is. A typed line holds them
-- itself; a line that went on to run a FILE is a new sh and swapped them for a
-- copy, keeping the console's on the frame it will pop back through
-- (CeroSecOS.jobRun: oldVars, oldExported, oldFuncs). So the console's tables go
-- back at the outermost place they were kept, which is the first frame carrying
-- them, or the job itself when no frame does. Nothing is merged and nothing is
-- lost by it: the two copies held the same thing when they were written.
local function reattachShell(job, console)
	local holder = job
	for i = 1, #job.frames do
		local frame = job.frames[i]
		if type(frame) == "table" and frame.hadFuncs then
			holder = frame
			break
		end
	end
	if holder == job then
		if type(console.shvars) == "table" then job.vars = console.shvars end
		if type(console.shexport) == "table" then job.exported = console.shexport end
		if type(console.shfuncs) == "table" then job.funcs = console.shfuncs end
	else
		if type(console.shvars) == "table" then holder.oldVars = console.shvars end
		if type(console.shexport) == "table" then holder.oldExported = console.shexport end
		if type(console.shfuncs) == "table" then holder.oldFuncs = console.shfuncs end
	end
end

function CeroSecJobs.restoreForeground(luaObject, console)
	if type(console) ~= "table" or console.job ~= nil then return false end
	local book = luaObject.jobs
	if book == nil then return false end
	for i = 1, #book.list do
		local job = book.list[i]
		if job.fg then
			job.fg = nil
			if not CeroSecOS.jobIsOver(job) and job.pty == nil then
				console.job = job.id
				reattachShell(job, console)
				return true
			end
		end
	end
	return false
end

Events.OnSave.Add(function()
	CeroSecJobs.saveBooks()
end)
