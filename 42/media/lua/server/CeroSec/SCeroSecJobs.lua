if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSScript"
require "CeroSec/OS/CeroSecOSVM"

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
		luaObject.jobs = { seq = 0, list = {}, winMs = 0, winCount = 0 }
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
	local live = 0
	for i = 1, #book.list do
		if not CeroSecOS.jobIsOver(book.list[i]) then live = live + 1 end
	end
	return live
end

-- Make a job from the order the engine handed back. nil plus a reason when the
-- machine has no room for it.
function CeroSecJobs.start(system, luaObject, console, data, bg)
	local book = CeroSecJobs.book(luaObject)
	if liveCount(book) >= CeroSecOS.MAX_JOBS then return nil, "too many jobs" end
	-- The one system there is, kept where the tick can reach it. Written here
	-- rather than at load time: the tick has nothing to do until a job exists,
	-- and a job cannot exist without somebody having made one.
	CeroSecJobs.system = system

	book.seq = book.seq + 1
	local job = CeroSecOS.newJob({
		id = CeroSecJobs.FIRST_ID + book.seq - 1,
		prog = data.prog,
		args = data.args,
		name = data.name,
		cmd = data.cmd,
		bg = bg,
		session = system:sessionOf(console),
	})
	job.n = freeSlot(book)
	book.list[#book.list + 1] = job
	register(luaObject)

	if bg then
		CeroSec.consolePush(console, "[" .. job.n .. "] " .. job.id)
	else
		-- The prompt belongs to the job now: the console says so, which is what
		-- makes Escape a ^C and what keeps a second window from typing a
		-- command over the top of a running script.
		console.job = job.id
	end
	return job
end

-- Every job on this machine, gone. Reboot, shutdown, a room that lost its
-- power, a computer picked up: all four are the machine stopping, and a
-- machine that has stopped is running nothing.
function CeroSecJobs.killAll(luaObject)
	if luaObject.jobs == nil then return false end
	luaObject.jobs = nil
	forget(luaObject)
	return true
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

-- Returns the steps it spent.
function CeroSecJobs.runMachine(system, luaObject, budget, now)
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
	local console = luaObject:consoleState()
	if state == nil or console == nil then
		CeroSecJobs.killAll(luaObject)
		return 0
	end

	local env = system:execEnv(luaObject, state, nil, nil)
	env.nowMs = now
	env.jobs = book.list

	local used = 0
	local share = math.floor(budget / #book.list)
	if share < 1 then share = 1 end

	for i = 1, #book.list do
		local job = book.list[i]

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
	end

	local changed = false

	-- A statement with "&" behind it, asked for by a job that is already
	-- running. One per pass and per job, so a loop full of them makes four jobs
	-- and then says so once each time round.
	for i = 1, #book.list do
		local job = book.list[i]
		if job.spawn ~= nil then
			local order = { name = job.name, prog = { job.spawn }, args = job.args,
				cmd = job.name .. ":" .. tostring(job.spawnLine or 1) .. " &" }
			job.spawn = nil
			job.spawnLine = nil
			local made = CeroSecJobs.start(system, luaObject, console, order, true)
			if made == nil then
				CeroSec.consolePush(console, "sh: too many jobs")
				job.status = 1
			end
			changed = true
		end
	end

	-- The output, at the rate the screen and the network can take it.
	local room = outRoom(book, now)
	for i = 1, #book.list do
		local job = book.list[i]
		local kept = {}
		for k = 1, #job.out do
			if room > 0 then
				CeroSec.consolePush(console, job.out[k])
				room = room - 1
				book.winCount = book.winCount + 1
				changed = true
			else
				kept[#kept + 1] = job.out[k]
			end
		end
		job.out = kept
	end

	-- The question a foreground job is asking, put up as an ordinary console
	-- prompt with an ordinary token. The console cannot tell a script's `read`
	-- from passwd's own question, and does not have to.
	local fg = CeroSecJobs.foreground(luaObject, console)
	if fg ~= nil and fg.ask ~= nil and console.prompt == nil then
		console.prompt = { text = fg.ask.text or "", mask = fg.ask.mask and true or false,
			cont = { cmd = "job", id = fg.id } }
		changed = true
	end

	-- Reaping. A job is only taken off the machine once the last of its output
	-- has reached the screen, or the last thing it said would be lost.
	local kept = {}
	local control = nil
	for i = 1, #book.list do
		local job = book.list[i]
		if CeroSecOS.jobIsOver(job) and #job.out == 0 then
			local line = endLine(job)
			if line ~= nil then
				CeroSec.consolePush(console, line)
				book.winCount = book.winCount + 1
			end
			if console.job == job.id then
				console.job = nil
				-- The status the prompt comes back with, kept on the console the
				-- way a shell keeps $?.
				console.status = job.status
				if console.prompt ~= nil and type(console.prompt.cont) == "table"
						and console.prompt.cont.cmd == "job" then
					console.prompt = nil
				end
			end
			if job.control ~= nil then control = job.control end
			changed = true
		else
			kept[#kept + 1] = job
		end
	end
	book.list = kept
	if #book.list == 0 then forget(luaObject) end

	if changed then
		luaObject:mirrorOS()
		system:pushScreen(luaObject, state, console)
	end
	-- Last, and never before the screen has gone out: a script that ended on
	-- `reboot` is a screen every survivor at the machine watches go down.
	if control == "clear" then
		CeroSec.consoleClear(console)
		system:pushScreen(luaObject, state, console)
	elseif control ~= nil then
		system:applyPower(luaObject, control)
	end
	return used
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

	for i = 1, n do
		if total <= 0 then return end
		local share = CeroSec.STEP_BUDGET_PER_MACHINE
		if share > total then share = total end
		total = total - CeroSecJobs.runMachine(system, order[i], share, now)
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
