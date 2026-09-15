-- The hostile bench. Run from the repo root:
--   lua5.1 tests/hostile_test.lua
--
-- Every other test asks whether a script does what it says. This one asks the
-- only question that matters to somebody running a server: CAN A PLAYER'S
-- SCRIPT HURT ANYBODY ELSE? So every program in here is written to be as
-- expensive as four lines of shell can be -- an endless loop, a script that
-- runs itself, a string that doubles every turn, a flood of output, a flood with
-- no newline anywhere in it, a hundred background jobs asked for at once, a
-- substitution inside a loop -- and each one is driven through the REAL
-- scheduler for a thousand passes while the cost of a pass is watched.
--
-- What is asserted, for every one of them:
--
--   * no pass ever spends more steps than the budget it was handed,
--   * the cost of a pass is FLAT: the thousandth is no dearer than the tenth,
--   * the console never holds more than its hundred lines,
--   * the memory the whole state occupies stops growing,
--   * what a job holds part way through a row never passes one row,
--   * a job that spins with no wait in it is killed by the cpu ceiling, and
--     one that is merely slow is not,
--   * a pass costs less than WALL_MS_PER_PASS milliseconds of real time under
--     lua5.1 on an ordinary machine -- every millisecond ceiling in here being
--     scaled to the speed this machine actually has, measured in this process right
--     before the first timed section (see CALIB_REF_MS).
--
-- The scheduler here is the real SCeroSecJobs.lua. What is faked is the game
-- around it: the clock, the events, and a computer with a console on it --
-- three tables, because everything the scheduler needs from a machine is
-- osState(), consoleState() and mirrorOS().

--
-- The game, faked.
--

_G.require = function() end
_G.isClient = function() return false end
_G.isServer = function() return false end
_G.__now = 1000000
_G.getTimestampMs = function() return _G.__now end
_G.Events = setmetatable({}, { __index = function(t, key)
	local event = { Add = function() end }
	rawset(t, key, event)
	return event
end })

local FILES = {
	"42/media/lua/shared/CeroSec/CeroSecDefs.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOS.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSComplete.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSCron.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSDev.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSDisk.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSFS.lua",
"42/media/lua/shared/CeroSec/OS/CeroSecOSNet.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSPath.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSRadio.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSScript.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSShell.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSState.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSSystem.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSUsers.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSVM.lua",
	"42/media/lua/server/CeroSec/SCeroSecNet.lua",
	"42/media/lua/server/CeroSec/SCeroSecJobs.lua",
	"42/media/lua/server/CeroSec/SCeroSecSensors.lua",
	"42/media/lua/server/CeroSec/SCeroSecRadio.lua",
	-- And the SERVER itself, for the county block at the foot of this file: the
	-- minute sweep and the watcher table are the two things in this mod whose cost
	-- is paid by every machine in Knox County at once, and neither of them can be
	-- reached through the three-table fake the scheduler benches run on. Loaded in
	-- the game's own order, after the OS core and the layers they call into.
	"42/media/lua/shared/CeroSec/CeroSecModules.lua",
	"42/media/lua/shared/CeroSec/CeroSecContent.lua",
	"42/media/lua/shared/CeroSec/CeroSecPhonebook.lua",
	"42/media/lua/server/CeroSec/SCeroSecDevices.lua",
	"42/media/lua/server/CeroSec/SCeroSecAuto.lua",
	"42/media/lua/server/CeroSec/SCeroSecDebug.lua",
	"42/media/lua/server/CeroSec/SCeroSecObject.lua",
	"42/media/lua/server/CeroSec/SCeroSecSystem.lua",
}
-- What the sensor pass asks of the game, and nothing else: a cell to look squares
-- up in, and a class test. Both nil-safe, so every bench in this file that is not
-- about sensors runs in a world with none.
_G.__world = nil
_G.getCell = function() return _G.__world end
_G.instanceof = function(object, class)
	return type(object) == "table" and object.__class == class
end

--
-- The two base classes the server's own files derive from, and the handful of
-- engine calls their top level makes. Vanilla's, copied rather than approximated,
-- because the county block below is about what the system does with the objects it
-- holds: SGlobalObject.new hands back the GlobalObject's OWN modData table -- which
-- is what the save file was read into -- and that is the whole reason a machine
-- loaded from a save arrives with `on` already set (media/lua/server/Map/
-- SGlobalObject.lua:63-79 and SGlobalObjectSystem.lua:11-53 on 42.20.4).
--
local function derive(base, name)
	local o = {}
	for key, value in pairs(base) do o[key] = value end
	o.Type = name
	o.__index = o
	o.derive = base.derive
	return o
end

SGlobalObject = { derive = function(self, name) return derive(self, name) end }
SGlobalObject.new = function(self, luaSystem, globalObject)
	local o = globalObject:getModData()
	setmetatable(o, self)
	self.__index = self
	o.luaSystem = luaSystem
	o.globalObject = globalObject
	o.x, o.y, o.z = globalObject:getX(), globalObject:getY(), globalObject:getZ()
	return o
end
SGlobalObject.aboutToRemoveFromSystem = function() end

SGlobalObjectSystem = { derive = function(self, name) return derive(self, name) end }
SGlobalObjectSystem.new = function(self, name)
	local o = setmetatable({}, self)
	o.systemName = name
	o.system = {
		setModDataKeys = function(s, keys) s.modDataKeys = keys end,
		setObjectModDataKeys = function(s, keys) s.objectModDataKeys = keys end,
		setObjectSyncKeys = function(s, keys) s.syncKeys = keys end,
		sendCommand = function() end,
	}
	o:initSystem()
	return o
end
SGlobalObjectSystem.initSystem = function() end
SGlobalObjectSystem.RegisterSystemClass = function() end
SGlobalObjectSystem.newLuaObjectOnClient = function() end
-- The sprite registrations the server makes at load, recorded and not run: which
-- of the two maps a closure sits in is what the automation hangs on, and that is
-- window_test's subject, not this file's.
_G.MapObjects = { OnNewWithSprite = function() end, OnLoadWithSprite = function() end }
_G.sendServerCommand = function() end
_G.ZombRand = function(n) return n and 0 or 0 end
-- The world's clock, as the sweep reads it (SCeroSecSystem:clockEnv). Two in the
-- morning: cron's minute hand is walked below and a crontab due in the minute
-- being measured would be a second thing in the measurement.
_G.__hour, _G.__minute = 2, 0
_G.getGameTime = function()
	return {
		getYear = function() return 1993 end,
		getMonth = function() return 6 end,
		getDay = function() return 7 end,
		getHour = function() return _G.__hour end,
		getMinutes = function() return _G.__minute end,
	}
end

for i = 1, #FILES do
	local chunk, err = loadfile(FILES[i])
	if not chunk then error("cannot load " .. FILES[i] .. ": " .. tostring(err)) end
	chunk()
end

local count = 0
local function check(what, cond)
	count = count + 1
	if not cond then error("FAIL: " .. what, 2) end
end
local function eq(what, got, want)
	count = count + 1
	if got ~= want then
		error("FAIL: " .. what .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
	end
end

--
-- The instrument: every call into the engine's stepper, counted, and its
-- budget checked at the door. This is what makes "never more than the budget"
-- an assertion about the ENGINE and not about the bench's arithmetic.
--
-- A pass may go over its budget by at most ONE COMMAND: a step is counted once
-- it has been taken, and a command out of /bin costs thirty-two of them, so a
-- job with three steps left that starts one overspends by twenty-nine. What is
-- overspent is carried as a debt and the next pass is that much shorter, so the
-- average over any run of passes is exactly the budget -- which is what the
-- totals below check, alongside the per-call ceiling.
local realStep = CeroSecOS.jobStep
local tickSteps = 0
local worstOver = 0
local totalAsked, totalSpent = 0, 0
CeroSecOS.jobStep = function(state, job, env, budget)
	local status, used = realStep(state, job, env, budget)
	tickSteps = tickSteps + used
	totalAsked = totalAsked + budget
	totalSpent = totalSpent + used
	if used > budget and used - budget > worstOver then worstOver = used - budget end
	check("a step call never spends more than its budget and one command (" ..
		used .. " of " .. budget .. ")", used <= budget + CeroSecOS.STEP_COST_COMMAND)
	return status, used
end

--
-- A computer, with just enough of one to be scheduled.
--

local pushes = 0
local powered = nil
-- The devices the bench's machines have. nil for every case but one -- a machine
-- with no devices at all, which is what most of these programs run on -- and a
-- door for the one case that polls one (section 14b).
local benchDevices = nil
local system = {}
function system:execEnv(luaObject, state)
	return { now = 740000000, nowMs = _G.__now, devices = benchDevices }
end
function system:sessionOf(console)
	return { user = console.user or "admin", cwd = console.cwd or "/home/admin", stamp = 1 }
end
-- The console is the machine's, so a `cd` or an `su` inside the prompt's own
-- job is written back into it -- the real server's SCeroSecSystem:writeSession,
-- which this bench owes the scheduler now that the prompt is a job.
function system:writeSession(console, session)
	console.user = session.user
	console.cwd = session.cwd
	console.stack = session.stack
end
function system:pushScreen() pushes = pushes + 1 end
function system:applyPower(luaObject, control) powered = control end

local function newMachine()
	local state = CeroSecOS.newState("ksp")
	local console = CeroSec.newConsole()
	console.user = "admin"
	console.cwd = "/home/admin"
	local machine = { on = true, console = console, x = 1, y = 2, z = 0 }
	function machine:osState() return state end
	function machine:consoleState() return self.console end
	function machine:mirrorOS() end
	CeroSecJobs.machines = {}
	CeroSecJobs.lastMs = 0
	return machine, state, console
end

local function put(state, path, text)
	local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(), path, text, false, 100)
	if done == nil then error("cannot write " .. path .. ": " .. tostring(reason), 2) end
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), path)
	node.owner = "admin"
	node.mode = 755
end

-- Type a line at the machine, the way the server's Commands.exec does: the line
-- becomes a foreground job on the console's own environment, and the scheduler
-- takes it from there. There is no shorter path any more -- the prompt IS the
-- script engine -- which is exactly what this bench has to beat on.
local function typeLine(system_, machine, state, console, line)
	local job, refusal = CeroSecJobs.startPrompt(system_, machine, console, line)
	if job == nil then CeroSec.consolePush(console, tostring(refusal)) end
	return job
end

-- The job a script left running on this machine: the first one that is not the
-- shell.
local function scriptJob(machine)
	local book = machine.jobs
	if book == nil then return nil end
	for i = 1, #book.list do
		if not book.list[i].interactive then return book.list[i] end
	end
	return nil
end

--
-- The drive: a thousand passes of the real scheduler, watching the cost of
-- each one.
--
-- stepMs is how far the wall clock moves between passes. A hundred is what the
-- game does; a benchmark that wants to reach the five-minute cpu ceiling in a
-- thousand passes moves it by a second instead, and says so.
--
local PASSES = 1000

-- watch, when given, is called after every pass: what a case wants to assert
-- about the machine DURING the run and not only at the end of it.
local function drive(machine, passes, stepMs, watch)
	local perPass = {}
	local worst = 0
	local clockStart = os.clock()
	for _ = 1, (passes or PASSES) do
		_G.__now = _G.__now + (stepMs or CeroSec.JOB_PASS_MS)
		tickSteps = 0
		CeroSecJobs.tick()
		perPass[#perPass + 1] = tickSteps
		if tickSteps > worst then worst = tickSteps end
		check("the console never holds more than its hundred lines",
			#machine.console.lines <= CeroSec.CONSOLE_MAX)
		if watch ~= nil then watch() end
	end
	local seconds = os.clock() - clockStart
	return { perPass = perPass, worst = worst,
		msPerPass = seconds * 1000 / (passes or PASSES) }
end

-- Flat: the last hundred passes cost no more than the first hundred did, give
-- or take the budget itself. A cost that climbs is the shape every one of
-- these programs is trying to produce.
local function flat(what, result)
	local n = #result.perPass
	local early, late = 0, 0
	for i = 1, 100 do early = early + result.perPass[i] end
	for i = n - 99, n do late = late + result.perPass[i] end
	check(what .. ": the cost of a pass does not climb (first 100: " .. early ..
		", last 100: " .. late .. ")", late <= early + CeroSec.STEP_BUDGET_PER_MACHINE)
	check(what .. ": no pass went past the machine's budget (" .. result.worst .. ")",
		result.worst <= CeroSec.STEP_BUDGET_PER_MACHINE + CeroSecOS.STEP_COST_COMMAND)
end

--
-- The machine's own speed, measured here, in this process, before anything is
-- timed.
--
-- Every millisecond ceiling below used to be a bare number, and a bare number
-- says as much about who else is on the machine as it does about the engine: on
-- a machine that is also running the game and other heavy work (load average 5
-- to 9) the ceilings went red two runs in three at 4.1 to 5.5 ms, on the
-- untouched base as much as on a branch that changed no engine file. A red that
-- says nothing about the code is noise, and noise is worse than no ceiling at
-- all -- so the ceilings stay, and what moves is the yardstick.
--
-- CALIBWORK is a fixed pure-Lua workload -- arithmetic and table writes, no
-- allocation that grows, nothing of the engine in it -- sized to take a few tens
-- of milliseconds. It is run three times and the CHEAPEST run is kept, because
-- the cheapest is the one that got the most of the cpu. Divided by the value
-- below it gives a scale factor: 1 on an idle machine, 2 on one that is half
-- taken, and every ceiling is multiplied by max(1, scale). An idle machine
-- therefore keeps exactly the strict number it always had; a loaded one gets an
-- allowance in proportion to how slow IT is, not a free pass -- and past 3x the
-- bench refuses to pretend it measured anything.
--
-- CALIB_REF_MS is the idle value, measured on one machine (lua5.1, 12 hardware
-- threads) on 2026-09-12: min-of-3 run three times in a row from the shell,
-- giving 23.24, 23.74 and 24.12 ms, and 23.0 taken as the floor under those.
-- Honest caveat: that machine was NOT idle while it was measured -- the game and
-- other heavy work were on it, load average 4.5 -- so the true idle figure is a
-- little lower than 23 and this reference is a little high, which makes the
-- scale it derives a little low, i.e. the ceilings a little stricter than
-- intended rather than looser. Re-measure it on a genuinely quiet machine and it
-- should only come down. It is a measurement of ONE machine: if the ceilings
-- read wrong on yours, re-measure rather than guess.
local CALIB_REF_MS = 23.0
local CALIB_MAX_SCALE = 3
local CALIB_N = 500000

local function calibWork()
	local t = {}
	local acc = 1
	for i = 1, CALIB_N do
		acc = (acc * 1103515245 + 12345) % 2147483648
		t[(i % 256) + 1] = acc + i * 0.5
	end
	return acc + t[1]
end

local function calibrate()
	calibWork()
	local best = nil
	for _ = 1, 3 do
		local at = os.clock()
		calibWork()
		local ms = (os.clock() - at) * 1000
		if best == nil or ms < best then best = ms end
	end
	return best
end

local CALIB_MS = calibrate()
local CALIB_SCALE = CALIB_MS / CALIB_REF_MS
if CALIB_SCALE < 1 then CALIB_SCALE = 1 end
if CALIB_SCALE > CALIB_MAX_SCALE then
	error(string.format(
		"FAIL: machine too loaded to measure: rerun idle (calibration %.2f ms against a " ..
		"reference of %.2f ms is a scale of %.2fx, past the %dx cap)",
		CALIB_MS, CALIB_REF_MS, CALIB_SCALE, CALIB_MAX_SCALE), 0)
end

-- A ceiling in milliseconds, as this machine may be held to it.
local function ceiling(ms)
	return ms * CALIB_SCALE
end

-- What a pass may cost in real time. Generous on purpose: this is a floor
-- under "the server is not being hurt", not a performance target, and a bench
-- machine under load must not turn it red. A pass is a tenth of a second of
-- game time, so anything under a millisecond is three orders of magnitude of
-- room. Scaled by the calibration above, like every ms ceiling in this file.
local WALL_MS_PER_PASS = 4.0

local function timely(what, result)
	local limit = ceiling(WALL_MS_PER_PASS)
	check(what .. ": a pass costs under " .. string.format("%.3f", limit) ..
		" ms of real time (" .. string.format("%.3f", result.msPerPass) .. ")",
		result.msPerPass < limit)
end

local report = {}
report[#report + 1] = string.format(
	"  %-22s %6.2f ms raw (ref %.2f), scale %.2fx on every ms ceiling",
	"calibration", CALIB_MS, CALIB_REF_MS, CALIB_SCALE)
local function note(what, result, extra)
	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/pass%s",
		what, result.worst, result.msPerPass, extra or "")
end

--
-- 1. The endless loop. The first program every player writes by accident.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/spin.sh", "while true; do x=1; done\n")
	typeLine(system, machine, state, console, "sh spin.sh")

	local result = drive(machine, PASSES)
	flat("endless loop", result)
	timely("endless loop", result)
	note("endless loop", result)

	local job = CeroSecJobs.foreground(machine, console)
	check("it is still running after a thousand passes", job ~= nil)
	check("having spent a great many steps doing it (" .. job.steps .. ")", job.steps > 50000)
	eq("and having said nothing at all", #console.lines, 0)
end

--
-- 2. The same loop, left long enough to meet the cpu ceiling. The clock moves
-- a second a pass here, so a thousand passes is a thousand seconds and the
-- five minute ceiling is really reached.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/spin.sh", "while true; do x=1; done\n")
	local job = typeLine(system, machine, state, console, "sh spin.sh")

	local result = drive(machine, PASSES, 1000)
	flat("cpu ceiling", result)
	eq("the job was killed", job.state, "killed")
	eq("and it says why", job.killReason, "cpu limit")
	local said = console.lines[#console.lines]
	eq("the screen says so in one line", said, "killed: cpu limit")
	eq("the prompt came back", console.job, nil)
	eq("and the machine is running nothing", #CeroSecJobs.book(machine).list, 0)
	note("cpu ceiling", result, " (killed)")
end

--
-- 3. A script that runs itself. Eight levels down it is refused, and the whole
-- thing is over in one pass -- no second job was ever made.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/self.sh", "sh /home/admin/self.sh\n")
	local job = typeLine(system, machine, state, console, "sh self.sh")

	local result = drive(machine, PASSES)
	flat("deep recursion", result)
	timely("deep recursion", result)
	eq("it stopped itself", job.state, "error")
	eq("with the reason on the screen", console.lines[#console.lines],
		"self.sh: line 1: too deeply nested")
	eq("and it never made a second job", #CeroSecJobs.book(machine).list, 0)
	note("deep recursion", result, " (too deeply nested)")
end

--
-- 4. A string that doubles every time round the loop. Ten iterations is a
-- kilobyte, and the eleventh is refused.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/grow.sh", 'x=a\nwhile true; do x="$x$x"; done\n')
	local job = typeLine(system, machine, state, console, "sh grow.sh")

	local result = drive(machine, PASSES)
	flat("doubling string", result)
	timely("doubling string", result)
	eq("it stopped on the ceiling", job.state, "error")
	-- "word too large" and not "variable too large": the doubled string is
	-- refused while the WORD is being built, one expansion before anybody tries
	-- to store it. Both ceilings are the same 1024 bytes, and this is the one
	-- the doubling meets first.
	eq("and said which", console.lines[#console.lines], "grow.sh: line 2: word too large")
	check("nothing it built is still held", job.vars.x == nil or #job.vars.x <= CeroSecOS.MAX_VAR_BYTES)
	note("doubling string", result, " (word too large)")
end

--
-- 5. A flood of output. It never floods: twenty lines a second reach the
-- screen and the job is held back between them, so it lives, slowly, and the
-- cpu ceiling never touches it -- waiting on the screen is a wait.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/flood.sh", "while true; do echo x; done\n")
	local job = typeLine(system, machine, state, console, "sh flood.sh")

	local result = drive(machine, PASSES)
	flat("output flood", result)
	timely("output flood", result)
	check("the job is alive and merely slow", not CeroSecOS.jobIsOver(job))
	eq("its output queue is bounded", #job.out <= CeroSecOS.JOB_OUT_MAX + 4, true)
	eq("the screen holds its hundred lines and no more", #console.lines, CeroSec.CONSOLE_MAX)
	-- A thousand passes is a hundred seconds of wall clock, so at twenty lines
	-- a second the machine allowed about two thousand lines through -- and not
	-- the hundreds of thousands the job could have made.
	check("about twenty lines a second got through (" .. job.steps .. " steps)",
		job.steps < 100 * CeroSec.JOB_OUT_PER_SEC * 20)
	note("output flood", result, " (trickling)")
end

--
-- 6. A flood with no newline in it, which is the same flood wearing a hat.
--
-- `printf %s x` and `echo -n x` write a character and never finish a line, and
-- the limiter above counts LINES: only a finished one reaches job.out, so for as
-- long as what a job held was unbounded, this wrote nothing to the screen, met
-- no limiter of any kind, and grew the held string a byte a turn -- thirty-three
-- kilobytes in the thousand passes below -- until the five minute cpu ceiling
-- happened to end it. The screen's own wrap, applied to what is held, is what
-- puts it back on the same leash: a row's worth of held text IS a finished line.
--
-- So what is asserted is the bound, every pass, for both ways of writing it.
--

local ROW = string.rep("x", CeroSecOS.COLS)

do
	local programs = {
		{ "printf, a byte a turn", "while true; do printf %s x; done\n" },
		{ "echo -n, a byte a turn", "while true; do echo -n x; done\n" },
		{ "echo -n, a row a turn", "while true; do echo -n " .. ROW .. "; done\n" },
	}
	for i = 1, #programs do
		local what, program = programs[i][1], programs[i][2]
		local machine, state, console = newMachine()
		put(state, "/home/admin/nonl.sh", program)
		local job = typeLine(system, machine, state, console, "sh nonl.sh")
		local worstHeld = 0
		local result = drive(machine, PASSES, nil, function()
			local held = #(job.partial or "")
			if held > worstHeld then worstHeld = held end
			check(what .. ": what the job holds never passes one row (" .. held .. ")",
				held <= CeroSecOS.COLS)
		end)
		flat(what, result)
		timely(what, result)
		check(what .. ": the job is alive and merely slow", not CeroSecOS.jobIsOver(job))
		check(what .. ": its output queue is bounded (" .. #job.out .. ")",
			#job.out <= CeroSecOS.JOB_OUT_MAX + 4)
		eq(what .. ": the screen holds its hundred lines and no more",
			#console.lines, CeroSec.CONSOLE_MAX)
		-- And it reaches the screen at all, which is the other half of the bug:
		-- the old behaviour was thirty-three kilobytes held and a blank screen.
		check(what .. ": what it wrote reached the screen", #console.lines > 0)
		note(what, result, " (held at most " .. worstHeld .. " bytes)")
	end
end

--
-- 6b. The same flood, left long enough to meet the cpu ceiling, and the two
-- honest halves of what the wrap does about it.
--
-- A job WAITING on the screen is not spending the processor, so the runaway
-- clock starts again when it runs again and a job held back by the limiter is
-- never killed by the cpu ceiling however long it lives. That is what a row a
-- turn gets: blocked on output on all but the first of a thousand passes, a
-- thousand seconds of game clock, alive.
--
-- A byte a turn does NOT get it, and the bench says so rather than pretending.
-- Sixty turns of the loop buy one line, so it produces about one and a half
-- lines a pass against a drain of twenty a second and never backs the queue up
-- far enough to be held at all. It is a compute loop that happens to print, the
-- cpu ceiling is the right thing to end it, and case 2 is where that is proved.
-- What the wrap owes here is the BOUND, and the bound holds either way.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/row.sh", "while true; do echo -n " .. ROW .. "; done\n")
	local job = typeLine(system, machine, state, console, "sh row.sh")
	local blockedPasses = 0
	local result = drive(machine, PASSES, 1000, function()
		if job.blocked == "output" then blockedPasses = blockedPasses + 1 end
		check("a row a turn: what the job holds never passes one row",
			#(job.partial or "") <= CeroSecOS.COLS)
	end)
	flat("newline-less trickle", result)
	check("it was held back by the screen on nearly every pass (" .. blockedPasses ..
		" of " .. PASSES .. ")", blockedPasses > PASSES - 10)
	check("so a thousand seconds later it is alive and not killed",
		not CeroSecOS.jobIsOver(job))
	eq("nothing was killed", job.killReason, nil)
	note("newline-less trickle", result, " (blocked " .. blockedPasses .. " passes)")
end

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/byte.sh", "while true; do printf %s x; done\n")
	local job = typeLine(system, machine, state, console, "sh byte.sh")
	drive(machine, PASSES, 1000, function()
		check("a byte a turn: what the job holds never passes one row",
			#(job.partial or "") <= CeroSecOS.COLS)
	end)
	-- The bound held for the whole run; the cpu ceiling ended it, as it should.
	eq("a byte a turn is ended by the cpu ceiling, not by a heap", job.state, "killed")
	eq("and it says why", job.killReason, "cpu limit")
	eq("what it held went with it", job.partial, "")
end

--
-- 6c. Memory, for this flood on its own: a byte a turn for a thousand passes
-- used to be a string that grew every one of them.
--

do
	collectgarbage("collect")
	local machine, state, console = newMachine()
	put(state, "/home/admin/nonl.sh", "while true; do printf %s x; done\n")
	typeLine(system, machine, state, console, "sh nonl.sh")
	drive(machine, 100)
	collectgarbage("collect")
	local early = collectgarbage("count")
	drive(machine, 900)
	collectgarbage("collect")
	local late = collectgarbage("count")
	check("a newline-less flood stops growing (" .. string.format("%.0f", early) ..
		"K after 100 passes, " .. string.format("%.0f", late) .. "K after 1000)",
		late - early < 50)
	local _ = console
end

--
-- 6d. The same flood written into a $(...) instead of onto a screen.
--
-- The wrap above deliberately does not reach a capture -- folding one would push
-- spaces into the middle of the captured value -- so for as long as that was the
-- whole story, this was the newline-less flood one door along: thirty-three
-- kilobytes held, nothing on the screen, no limiter touched. What bounds it here
-- is the capture's own ceiling, in BYTES, counting what is held as well as what
-- has been caught, and a capture that passes it fails its command the way any
-- oversized word does.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/cap.sh", "y=$(while true; do printf %s x; done)\n")
	local job = typeLine(system, machine, state, console, "sh cap.sh")
	local worstHeld = 0
	drive(machine, PASSES, nil, function()
		local held = #(job.partial or "")
		if held > worstHeld then worstHeld = held end
		check("a captured flood never holds more than a word (" .. held .. ")",
			held <= CeroSecOS.MAX_VAR_BYTES)
	end)
	eq("the capture was stopped", job.state, "error")
	eq("with the word's own reason", console.lines[#console.lines],
		"cap.sh: line 1: word too large")
	eq("and nothing of it is still held", job.partial, "")
	check("it never became a variable", job.vars.y == nil)
	check("and it was stopped early, not left to the cpu ceiling (" .. job.steps ..
		" steps)", job.steps < 50000)
	report[#report + 1] = string.format("  %-22s held at most %d bytes, %d steps",
		"captured flood", worstHeld, job.steps)
end

--
-- 7. A hundred background jobs, asked for as fast as a loop can ask.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/spin.sh", "while true; do x=1; done\n")
	put(state, "/home/admin/fork.sh", "while true; do sh /home/admin/spin.sh & done\n")
	typeLine(system, machine, state, console, "sh fork.sh")

	local worstJobs = 0
	for _ = 1, PASSES do
		_G.__now = _G.__now + CeroSec.JOB_PASS_MS
		tickSteps = 0
		CeroSecJobs.tick()
		local n = #CeroSecJobs.book(machine).list
		if n > worstJobs then worstJobs = n end
		-- The book holds the shell as well as what the shell started: the line
		-- typed at the prompt is a job too. So the ceiling on the book is the
		-- four slots plus the one shell, and CeroSecOS.liveJobs is what the
		-- ceiling itself is counted with.
		check("never more jobs than the machine allows (" .. n .. ")",
			n <= CeroSecOS.MAX_JOBS + 1)
		check("and never more SLOTS than it allows",
			CeroSecOS.liveJobs(CeroSecJobs.book(machine).list) <= CeroSecOS.MAX_JOBS)
		check("the console never holds more than its hundred lines",
			#machine.console.lines <= CeroSec.CONSOLE_MAX)
	end
	eq("the machine filled its four slots", worstJobs, CeroSecOS.MAX_JOBS + 1)
	local refused = false
	for i = 1, #console.lines do
		if console.lines[i] == "sh: too many jobs" then refused = true end
	end
	check("and said so on the screen", refused)
end

--
-- 8. A substitution bomb: a command run inside a loop, its output captured
-- every turn. The steps of what it runs are charged to the job that asked, so
-- this is expensive per turn and flat per pass, which is the whole point.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/bomb.sh", "while true; do y=$(ls /bin); done\n")
	local job = typeLine(system, machine, state, console, "sh bomb.sh")

	local result = drive(machine, PASSES)
	flat("substitution bomb", result)
	timely("substitution bomb", result)
	check("it is still running and still bounded", not CeroSecOS.jobIsOver(job))
	check("the captured value never went past the word ceiling",
		job.vars.y == nil or #job.vars.y <= CeroSecOS.MAX_VAR_BYTES)
	note("substitution bomb", result)
end

--
-- 8b. The same bomb INSIDE A SUM (debts 2).
--
-- `$(( $(cmd) + 1 ))` is a command substitution the ARITHMETIC asks for, and it
-- is a second door into the same capture frame: the sum stands still at one part
-- while the program inside it runs. So it has to be charged and bounded exactly as
-- the door above is, and it has to keep moving -- a loop like this must go round
-- thousands of times over a thousand passes and not stall on the pass's own spin
-- guard. (What that guard reads of the sum's own position -- ex.ai, ex.abuf in
-- progressKey -- is not what carries this bench: the capture's FRAME is pushed and
-- popped, which the guard already sees. It is in the key because it is state a
-- turn moves without spending a step, which is the rule that key is built on.)
--
do
	local machine, state, console = newMachine()
	put(state, "/home/admin/sumbomb.sh",
		"while true; do y=$(( $(ls /bin | wc -l) + 1 )); done\n")
	local job = typeLine(system, machine, state, console, "sh sumbomb.sh")

	local result = drive(machine, PASSES)
	flat("sum substitution bomb", result)
	timely("sum substitution bomb", result)
	check("it is still running and still bounded", not CeroSecOS.jobIsOver(job))
	-- And it is really COMPUTING, not standing still: the sum came out as a number
	-- and came out more than once. A bench that only watched the cost would be
	-- green on a loop that never finished one turn.
	check("the sum was worked out (" .. tostring(job.vars.y) .. ")",
		job.vars.y ~= nil and tonumber(job.vars.y) ~= nil)
	check("and many times over (" .. job.steps .. " steps)", job.steps > PASSES)
	note("sum substitution bomb", result)
end

--
-- 8c. A flood REDIRECTED INTO A FILE (debts 2).
--
-- `sh flood.sh > f` points the script's standard output at a file, and the flood
-- limiter that bounds every other flood counts lines in job.out -- which a
-- redirected script never touches. So the buffer the lines wait in meets the same
-- forty, and the pass ends there so the pass's own write can empty it; and the
-- runaway clock must NOT be stopped while it waits, because a target with no
-- contents to fill (a device) would otherwise run for ever.
--
-- The program is a `cat` of a hundred lines in a loop, and not an `echo`: one echo
-- is one line and the step budget alone already holds a pass to about thirty of
-- them, so an echo loop could never reach the ceiling this is about. A command that
-- writes a hundred lines for its thirty-two steps can, three times over in a pass
-- -- and what the ceiling does is end the pass after the first.
--
-- What is measured is the size of the chunk each write actually carries, taken at
-- CeroSecOS.writeRedirect: the pass empties the buffer before it returns, so reading
-- the buffer after a tick would read nought and prove nothing.
--
do
	local machine, state, console = newMachine()
	local LINES = 100
	put(state, "/home/admin/lines", string.rep("y\n", LINES - 1) .. "y")
	put(state, "/home/admin/flood.sh",
		"while true; do cat /home/admin/lines; done\n")

	local realWrite = CeroSecOS.writeRedirect
	local worstChunk, writes = 0, 0
	CeroSecOS.writeRedirect = function(st, session, who, redirect, text, env)
		writes = writes + 1
		local n, at = 1, 1
		while true do
			local p = string.find(text, "\n", at, true)
			if p == nil then break end
			n = n + 1
			at = p + 1
		end
		if n > worstChunk then worstChunk = n end
		return realWrite(st, session, who, redirect, text, env)
	end

	local job = typeLine(system, machine, state, console, "sh flood.sh > f")

	-- Read at the door of every step call and not after the tick: the scheduler
	-- steps a job more than once in a pass, and what `blocked` says after the tick
	-- is only what the LAST of those calls left behind.
	local outerStep = CeroSecOS.jobStep
	local sawHeld, clockHeld = false, true
	CeroSecOS.jobStep = function(st, j, env, budget)
		local status, used = outerStep(st, j, env, budget)
		if j == job and j.blocked == "output" and j.rdto ~= nil then
			sawHeld = true
			-- Held back by the DISK is not held back by the screen: nothing but the
			-- end of the pass is stopping this job, so the cpu clock goes on running.
			if j.cpuSince == nil then clockHeld = false end
		end
		return status, used
	end

	for _ = 1, 80 do
		_G.__now = _G.__now + CeroSec.JOB_PASS_MS
		tickSteps = 0
		CeroSecJobs.tick()
		check("the console never holds more than its hundred lines",
			#machine.console.lines <= CeroSec.CONSOLE_MAX)
	end
	CeroSecOS.jobStep = outerStep
	CeroSecOS.writeRedirect = realWrite

	check("the flood really did write (" .. writes .. " writes)", writes > 0)
	-- The ceiling plus ONE command's worth, which is the same shape the step budget
	-- is overspent by and for the same reason: the buffer is looked at before a
	-- command runs, never in the middle of one. Without the ceiling a pass carries a
	-- command's worth for every command its budget affords -- three of them here.
	check("no write carried more than the ceiling and one command (" ..
		worstChunk .. " lines)", worstChunk <= CeroSecOS.JOB_OUT_MAX + LINES)
	check("the job was held back by the file at least once", sawHeld)
	check("and the runaway clock was not stopped while it was", clockHeld)
	-- It ends on the FILE's own ceiling, not on a buffer that grew for ever.
	eq("the flood is over", CeroSecOS.jobIsOver(job), true)
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), "/home/admin/f")
	check("and the file holds what fitted (" .. #(node.data or "") .. " bytes)",
		#(node.data or "") > 0 and #(node.data or "") <= CeroSecOS.MAX_FILE_BYTES)
	report[#report + 1] = string.format("  %-22s worst %4d lines/write, %d writes",
		"redirected flood", worstChunk, writes)
end

--
-- 8d. A `case` of forty patterns, in a loop (debts 2).
--
-- A case of forty alternatives does forty comparisons every time round, and each
-- one is an expansion and a walk of two strings. Charged a step each, which is what
-- the same thing written as forty `[ "$x" = p ]` would cost -- and it has to be:
-- with the comparison counted as free work (which is how the frame was written
-- first) a pass over this cost 7.6 ms against a ceiling of 4, because a hundred
-- loop iterations were four thousand comparisons the budget could not see.
--
-- The last pattern is the one that matches, so every one of them is walked.
--
do
	local machine, state, console = newMachine()
	local pats = {}
	for i = 1, 39 do pats[#pats + 1] = "p" .. i end
	pats[#pats + 1] = "hit"
	put(state, "/home/admin/sw.sh",
		"while true; do case hit in " .. table.concat(pats, "|") ..
		") x=1;; esac; done\n")
	local job = typeLine(system, machine, state, console, "sh sw.sh")

	local result = drive(machine, PASSES)
	flat("case of forty", result)
	timely("case of forty", result)
	check("it is still running and still bounded", not CeroSecOS.jobIsOver(job))
	-- And really going round: the loop iteration is the one step a turn of this
	-- costs, so the steps are the turns and there have to be thousands of them.
	check("the loop went round (" .. job.steps .. " steps)", job.steps > PASSES)
	note("case of forty", result)
end

--
-- 8e. A function that calls itself, and a loop that calls one (debts 2).
--
-- A function runs in the shell that holds it: no job, no new shell, one frame a
-- call. So what bounds a recursion is the frame stack and nothing else, and a
-- recursion that never ends has to reach that ceiling and STOP -- inside the budget,
-- with a line saying which ceiling it was, and without spending a pass climbing back
-- up. `f() { f; }` is the shortest program there is that never ends, and it is two
-- words shorter than the script that runs itself.
--
do
	local machine, state, console = newMachine()
	put(state, "/home/admin/rec.sh", "f() { f; }\nf\n")
	local job = typeLine(system, machine, state, console, "sh rec.sh")

	local result = drive(machine, 200)
	flat("runaway recursion", result)
	timely("runaway recursion", result)
	eq("the recursion is over", CeroSecOS.jobIsOver(job), true)
	local said = false
	for i = 1, #console.lines do
		if string.find(console.lines[i], "too deeply nested", 1, true) ~= nil then
			said = true
		end
	end
	check("and the screen says which ceiling it was", said)
	note("runaway recursion", result)
end

do
	local machine, state, console = newMachine()
	-- A function called every time round a loop, doing a command's worth of work in
	-- it: the call is a step and the body is charged as any other line is, so this
	-- has to be as flat as the same loop written without the function.
	put(state, "/home/admin/fnloop.sh",
		"each() { x=$1; }\nwhile true; do each 1; done\n")
	local job = typeLine(system, machine, state, console, "sh fnloop.sh")

	local result = drive(machine, PASSES)
	flat("function in a loop", result)
	timely("function in a loop", result)
	check("it is still running and still bounded", not CeroSecOS.jobIsOver(job))
	check("the loop went round (" .. job.steps .. " steps)", job.steps > PASSES)
	-- And the frame stack did NOT grow: a call that forgot to pop would climb one
	-- frame a turn and hit "too deeply nested" in sixty, which is the bug this is
	-- here to catch.
	check("the frame stack stayed shallow (" .. #job.frames .. ")",
		#job.frames < 12)
	note("function in a loop", result)
end

--
-- 9. Four of the worst of them at once, on four machines, sharing one budget.
-- What is being watched here is the ceiling on the WHOLE county: no pass may
-- spend more than CeroSec.STEP_BUDGET_PER_TICK however many machines there are.
--

do
	CeroSecJobs.machines = {}
	CeroSecJobs.lastMs = 0
	local machines = {}
	for m = 1, 6 do
		local state = CeroSecOS.newState("ksp")
		local console = CeroSec.newConsole()
		console.user = "admin"
		console.cwd = "/home/admin"
		local machine = { on = true, console = console, x = m, y = 0, z = 0 }
		function machine:osState() return state end
		function machine:consoleState() return self.console end
		function machine:mirrorOS() end
		put(state, "/home/admin/spin.sh", "while true; do x=1; done\n")
		typeLine(system, machine, state, console, "sh spin.sh")
		machines[m] = machine
	end

	local worst = 0
	local served = {}
	local clockStart = os.clock()
	for _ = 1, PASSES do
		_G.__now = _G.__now + CeroSec.JOB_PASS_MS
		tickSteps = 0
		CeroSecJobs.tick()
		if tickSteps > worst then worst = tickSteps end
	end
	local msPerPass = (os.clock() - clockStart) * 1000 / PASSES

	check("no pass spent more than the county's budget (" .. worst .. ")",
		worst <= CeroSec.STEP_BUDGET_PER_TICK + CeroSecOS.STEP_COST_COMMAND)
	-- Round-robin: six machines sharing a budget that only reaches ten of them
	-- must all have run. A machine that never ran is a machine whose script
	-- hangs forever, which is the bug this is here for.
	for m = 1, 6 do
		local job = CeroSecJobs.book(machines[m]).list[1]
		served[m] = job.steps
		check("machine " .. m .. " was served (" .. job.steps .. " steps)", job.steps > 0)
	end
	-- And fairly: the busiest machine did not get more than twice what the
	-- quietest did.
	local low, high = served[1], served[1]
	for m = 2, 6 do
		if served[m] < low then low = served[m] end
		if served[m] > high then high = served[m] end
	end
	check("and fairly (" .. low .. " .. " .. high .. ")", high <= low * 2)
	local sixCeiling = ceiling(WALL_MS_PER_PASS)
	check("a pass over six busy machines costs under " ..
		string.format("%.3f", sixCeiling) .. " ms (" ..
		string.format("%.3f", msPerPass) .. ")", msPerPass < sixCeiling)
	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/pass",
		"six machines", worst, msPerPass)
end

--
-- 10. Memory. Everything above ran; what is left behind must be a few hundred
-- kilobytes of Lua and not a heap that grew with every pass.
--

do
	collectgarbage("collect")
	local before = collectgarbage("count")
	local machine, state, console = newMachine()
	put(state, "/home/admin/spin.sh", "while true; do echo x; done\n")
	typeLine(system, machine, state, console, "sh spin.sh")
	drive(machine, 100)
	collectgarbage("collect")
	local early = collectgarbage("count")
	drive(machine, 900)
	collectgarbage("collect")
	local late = collectgarbage("count")

	-- The job is a fixed shape: a program, a stack of frames, sixty-four
	-- variables at most and forty lines of output at most. Nine hundred more
	-- passes of it may not cost fifty kilobytes.
	check("the state stops growing (" .. string.format("%.0f", early) .. "K after 100 passes, " ..
		string.format("%.0f", late) .. "K after 1000)", late - early < 50)
	-- The FLOOR of this one is the mod itself: every engine file and every server
	-- file this bench loads is Lua in the heap before a machine exists, and rung
	-- 6c added two files to that (CeroSecOSRadio and SCeroSecRadio) which carried
	-- it past a megabyte on their own. So the number moved to 1152K and the
	-- assertion above it did not: what catches a leak is `late - early`, which is
	-- growth over nine hundred passes and is unaffected by how much source was
	-- read at the top of the file. This one catches a heap that has doubled.
	--
	-- 1280K since fidelity A, and it moved for the same reason a third time: seven
	-- commands went into CeroSecOSShell.lua -- more, find, tee, cut, tr, uptime and
	-- w -- and the source of them is in the heap before a machine exists. Measured
	-- at 1153K, which is what 1152 was catching.
	--
	-- Measured at 1171K once fidelity A met main: the phone lines, the reboot and
	-- the reworked debug window are more source read at the top of the file too.
	-- 1280 still holds it with room, and it still catches a heap that has doubled,
	-- so the number did not move a fourth time.
	--
	-- A fourth time, and the same reason a fourth time: the wave that paid the
	-- debts put `env`, `export`, `.`, `find -exec`, `tar` and `at` into the engine
	-- files, and the source of them is in the heap before a machine exists.
	-- Measured at 1299K, which is what 1280 was catching. 1440 holds it with the
	-- same room the last three numbers held theirs, and `late - early` -- growth
	-- over nine hundred passes, which is what catches a LEAK -- did not move at all.
	--
	-- And a fifth time, for the same reason and a bigger one: this file now loads
	-- the SERVER -- the object, the system, the devices, the automation, the debug
	-- window and the world content -- because the county block at the foot of it
	-- benches the minute sweep and the watcher table, and neither can be reached
	-- through the three-table fake the scheduler benches run on. That is another
	-- eight files of source in the heap before a machine exists. Measured at 2119K,
	-- which is what 1440 was catching; 2560 holds it with the room the four numbers
	-- before it held theirs -- a fifth clear, the way 1440 stood a fifth over 1299 --
	-- and `late - early`, growth over nine hundred passes, which is the assertion
	-- that catches a LEAK, did not move at all.
	check("and the whole bench holds well under 2560K (" ..
		string.format("%.0f", late) .. "K)", late < 2560)
	report[#report + 1] = string.format("  %-22s %.0fK after 100 passes, %.0fK after 1000",
		"memory", early, late)
	local _ = before
end

--
-- 11. A loop typed at the PROMPT (rung 5a.1)
--
-- The prompt is the script engine now, so the worst thing a player can type is
-- the worst thing he could write into a file -- and it has to be just as
-- harmless. No file at all here: this is the line going straight into the shell.
--

do
	local machine, state, console = newMachine()
	local job = typeLine(system, machine, state, console, "while true; do echo tick; done")
	check("the line became a job", job ~= nil)

	local result = drive(machine, PASSES)
	flat("typed endless loop", result)
	timely("typed endless loop", result)
	check("it is still running after a thousand passes", not CeroSecOS.jobIsOver(job))
	-- Fewer steps than the silent loop above spends, and that is the trickle
	-- working: a job with forty lines waiting is held back until the screen has
	-- taken them, which is CeroSec.JOB_OUT_PER_SEC a second.
	check("having spent steps and been held back (" .. job.steps .. ")",
		job.steps > 1000 and job.steps < 50000)
	eq("and the prompt is still the job's", console.job, job.id)
	note("typed endless loop", result)
end

-- The same line, left long enough to meet the cpu ceiling. A typed loop dies
-- exactly the way a script's does.
do
	local machine, state, console = newMachine()
	local job = typeLine(system, machine, state, console, "while true; do x=1; done")

	local result = drive(machine, PASSES, 1000)
	flat("typed cpu ceiling", result)
	eq("the typed loop was killed", job.state, "killed")
	eq("and it says why", job.killReason, "cpu limit")
	eq("the prompt came back", console.job, nil)
	eq("and the machine is running nothing", #CeroSecJobs.book(machine).list, 0)
	note("typed cpu ceiling", result, " (killed)")
end

--
-- 12. A ~/.profile that never ends
--
-- It runs at login, on the shell's own environment, so it is the prompt's own
-- job -- which means the ceilings that hold a typed loop hold this too, and the
-- account is left at a busy prompt rather than at a locked machine.
--

do
	local machine, state, console = newMachine()
	local text = "while true; do echo hello; done\n"
	local wrote = CeroSecOS.writeFile(state, CeroSecOS.rootSession(),
		"/home/admin/.profile", text, false, 100)
	if wrote == nil then error("cannot write .profile") end
	-- Run the way SCeroSecSystem:runProfile runs it: the file's text as the
	-- program, named after the file.
	local session = system:sessionOf(console)
	console.shvars = {}
	local job = CeroSecOS.promptJob(state, session, text, console.shvars, nil, ".profile")
	job.id = 42
	machine.jobs = { seq = 1, list = { job }, winMs = 0, winCount = 0 }
	console.job = 42
	CeroSecJobs.machines = { machine }
	CeroSecJobs.system = system

	local result = drive(machine, PASSES)
	flat("endless profile", result)
	timely("endless profile", result)
	check("the account is at a busy prompt and not at a dead machine",
		not CeroSecOS.jobIsOver(job))
	eq("which Escape is the way out of", console.job, 42)
	check("and it never flooded", #console.lines <= CeroSec.CONSOLE_MAX)
	-- The way out, exactly as Commands.interrupt takes it.
	CeroSecOS.killJob(job, nil)
	-- Enough passes for the last of what it wrote to reach the screen: a job is
	-- only taken off the machine once it has, or the last thing it said would be
	-- lost. Forty lines at CeroSec.JOB_OUT_PER_SEC a second is two seconds.
	drive(machine, 40)
	eq("the prompt comes back", console.job, nil)
	note("endless profile", result)
end

--
-- 13. A history flood
--
-- Five thousand lines typed. ~/.sh_history keeps a thousand of them and never
-- goes past sixteen kilobytes, and the disk it does not count against still has
-- room on it.
--

do
	local machine, state, console = newMachine()
	local session = system:sessionOf(console)
	local _, before = CeroSecOS.usage(state)

	local clockStart = os.clock()
	for i = 1, 5000 do
		CeroSecOS.historyAppend(state, session, "echo line " .. i, 100)
	end
	local seconds = os.clock() - clockStart

	local node = CeroSecOS.getNode(state, session, "/home/admin/" .. CeroSecOS.HISTORY_NAME)
	check("the file is there", node ~= nil)
	local lines = CeroSecOS.splitLines(node.data)
	check("a thousand entries at most (" .. #lines .. ")", #lines <= CeroSecOS.HISTORY_MAX)
	check("and sixteen kilobytes at most (" .. #node.data .. ")",
		#node.data <= CeroSecOS.HISTORY_BYTES)
	eq("the newest is the last thing typed", lines[#lines], "echo line 5000")
	eq("and its mode never moved", node.mode, CeroSecOS.HISTORY_MODE)

	-- It is exempt from the quota, so the disk is where it was.
	local _, after = CeroSecOS.usage(state)
	eq("the disk did not move", after, before)
	check("and the machine still boots with it there (" .. #node.data .. " bytes)",
		CeroSecOS.validate(state) == true)
	-- The disk still has its room: a file may still be written beside it.
	local room = CeroSecOS.writeFile(state, session, "/home/admin/notes.txt",
		string.rep("n", 4096), false, 100)
	eq("with room to spare", room, true)

	report[#report + 1] = string.format("  %-22s %d entries, %d bytes, %.0f ms for 5000",
		"history flood", #lines, #node.data, seconds * 1000)
end

--
-- 14. A flood into a pipe (rung 5b)
--
-- The shape a pipeline adds to the list of ways to hurt a server: an endless
-- writer with something small in front of it. Three of them.
--
--   `head -n 1` reads its one line and closes the pipe, which kills the writer
--   with 141 -- so the whole thing is over in one pass and costs almost nothing.
--
--   `cat`, which never closes anything, is the flood with a pipe in the middle
--   of it: bounded by back-pressure at a hundred lines, then by the screen
--   limiter, exactly as the flood with no pipe in it is.
--
--   `sort`, which cannot answer before the end of its input, meets the ceiling
--   on what a stage may hold and gives up -- and closes the pipe on the way
--   out, so the writer stops too.
--

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/pipehead.sh", "while true; do echo y; done | head -n 1\n")
	local job = typeLine(system, machine, state, console, "sh pipehead.sh")

	local result = drive(machine, PASSES)
	flat("pipe into head", result)
	timely("pipe into head", result)
	eq("the pipeline is over", CeroSecOS.jobIsOver(job), true)
	eq("and the machine is running nothing", #CeroSecJobs.book(machine).list, 0)
	eq("one line reached the screen", #console.lines, 1)
	eq("and it is the line head read", console.lines[1], "y")
	check("having cost the machine almost nothing (" .. job.steps .. ")", job.steps < 300)
	note("pipe into head", result, " (SIGPIPE)")
end

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/pipecat.sh", "while true; do echo y; done | cat\n")
	local job = typeLine(system, machine, state, console, "sh pipecat.sh")

	local result = drive(machine, PASSES, nil, function()
		-- The pipe itself never grows past what a pipe holds, however long the
		-- writer runs: this is the back-pressure, watched during the run and not
		-- only at the end of it.
		local frame = nil
		for i = 1, #job.frames do
			if job.frames[i].k == "pipe" then frame = job.frames[i] end
		end
		if frame ~= nil then
			for i = 1, #frame.pipes do
				local buf = frame.pipes[i]
				check("a pipe never holds more than a pipe holds (" .. #buf.lines .. ")",
					#buf.lines <= CeroSecOS.PIPE_LINES + CeroSecOS.JOB_OUT_MAX)
				check("nor more bytes than one holds (" .. buf.bytes .. ")",
					buf.bytes <= CeroSecOS.PIPE_BYTES * 2)
			end
		end
	end)
	flat("pipe into cat", result)
	timely("pipe into cat", result)
	check("the pipeline is alive and merely slow", not CeroSecOS.jobIsOver(job))
	eq("the screen holds its hundred lines and no more", #console.lines, CeroSec.CONSOLE_MAX)
	note("pipe into cat", result, " (trickling)")
end

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/pipesort.sh", "while true; do echo y; done | sort\n")
	local job = typeLine(system, machine, state, console, "sh pipesort.sh")

	local result = drive(machine, PASSES)
	flat("pipe into sort", result)
	timely("pipe into sort", result)
	eq("the pipeline is over", CeroSecOS.jobIsOver(job), true)
	eq("it said why, once", #console.lines, 1)
	eq("and that is the line", console.lines[1], "sort: input too large")
	note("pipe into sort", result, " (input too large)")
end

--
-- 14b. A pipeline that is ASLEEP (rung 5b)
--
-- The shape that is not a flood and hurt the server anyway. `sleep 300` on its
-- own costs a thousandth of a millisecond a pass: the scheduler looks at the
-- wake-up time and goes away. `sleep 300 | cat` cost THREE MILLISECONDS a pass
-- for the whole five minutes -- a thousand times a bare sleep, and more than any
-- flood in this file -- because the turn that found nothing to do in a pipeline
-- was not a turn that parked it: the walk stepped the sleeping stage, the stage
-- answered nought, and the pass did that again some nineteen thousand times
-- until the runaway belt stopped it.
--
-- So what is asserted here is the opposite of everything above: not that a
-- program which spends is bounded, but that a program which spends NOTHING costs
-- nothing. Five sleeping pipelines, including the polling idiom the manual
-- teaches (`cat /dev/door0; sleep 5` in a loop, with something on the other side
-- of a pipe), and every one of them must be as cheap as a bare sleep -- and must
-- still wake up and finish, which is the other half of the bargain.
--

-- What a pass may cost while the job on the machine is asleep. A bare sleep
-- costs a thousandth of a millisecond; this is fifty times that, which is room
-- for the measurement on a loaded bench machine and no room at all for a spin.
local WALL_MS_ASLEEP = 0.05

-- Drive a machine whose job spends its time asleep, and watch two things pass by
-- pass: the steps the job has spent do not move while it is sleeping the SAME
-- sleep -- a job asleep spends nothing, and a number that climbs is the spin
-- coming back -- and the real time a pass costs stays under the ceiling above.
--
-- The same sleep is what the wake-up time says it is: the polling loop below
-- wakes, works and lies down again inside one pass, and the steps it spent
-- working are its own and not a spin.
local function asleepDrive(what, machine, job, passes, stepMs)
	local was, wake, steps = nil, nil, nil
	local result = drive(machine, passes, stepMs, function()
		if was == "sleeping" and job.state == "sleeping" and job.wakeMs == wake then
			check(what .. ": a sleeping job spends no steps (" .. job.steps ..
				" after " .. steps .. ")", job.steps == steps)
		end
		was, wake, steps = job.state, job.wakeMs, job.steps
	end)
	local limit = ceiling(WALL_MS_ASLEEP)
	check(what .. ": a pass costs under " .. string.format("%.4f", limit) ..
		" ms of real time while asleep (" .. string.format("%.4f", result.msPerPass) ..
		")", result.msPerPass < limit)
	flat(what, result)
	return result
end

-- The clock, taken past a sleep, and the machine driven until whatever was
-- waiting on it has finished. Asleep must not mean stuck.
local function wakeUp(machine, ms, passes)
	_G.__now = _G.__now + ms
	return drive(machine, passes or 40)
end

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/sleepcat.sh", "sleep 300 | cat\necho awake\n")
	local job = typeLine(system, machine, state, console, "sh sleepcat.sh")

	local result = asleepDrive("sleep | cat", machine, job, PASSES)
	timely("sleep 300 | cat", result)
	eq("it is still asleep after a hundred seconds", job.state, "sleeping")
	eq("and has said nothing", #console.lines, 0)
	check("having spent a handful of steps and no more (" .. job.steps .. ")",
		job.steps < 100)

	wakeUp(machine, 300000)
	eq("past the sleep, the pipeline is over", CeroSecOS.jobIsOver(job), true)
	eq("the line after it ran", #console.lines, 1)
	eq("and that is the line", console.lines[1], "awake")
	note("sleep 300 | cat", result, " (asleep)")
end

do
	local machine, state, console = newMachine()
	-- `read` in a pipe reads the pipe, and the pipe it is given closes when the
	-- sleep on the other end of it finishes: two seconds asleep, then end of
	-- file, which is a read that answers nothing and fails.
	put(state, "/home/admin/sleepread.sh", "sleep 2 | read x\necho done [$x]\n")
	local job = typeLine(system, machine, state, console, "sh sleepread.sh")

	local result = asleepDrive("sleep | read", machine, job, PASSES)
	timely("sleep 2 | read x", result)
	eq("two seconds of sleep were enough to finish it", CeroSecOS.jobIsOver(job), true)
	eq("the line after it ran", #console.lines, 1)
	eq("and the read read nothing", console.lines[1], "done []")
	note("sleep 2 | read x", result, " (asleep)")
end

do
	local machine, state, console = newMachine()
	put(state, "/home/admin/sleepsleep.sh", "sleep 300 | sleep 300\necho awake\n")
	local job = typeLine(system, machine, state, console, "sh sleepsleep.sh")

	local result = asleepDrive("sleep | sleep", machine, job, PASSES)
	timely("sleep 300 | sleep 300", result)
	eq("both stages are asleep, so the pipeline is", job.state, "sleeping")

	wakeUp(machine, 300000)
	eq("past the sleep, the pipeline is over", CeroSecOS.jobIsOver(job), true)
	eq("and the line after it ran", console.lines[1], "awake")
	note("sleep 300 | sleep 300", result, " (asleep)")
end

do
	local machine, state, console = newMachine()
	-- Three stages, the middle one asleep. The stage on the left has written
	-- everything it will write and gone; the one on the right is waiting on
	-- input that will not come for five minutes -- so the pipeline as a whole is
	-- the middle stage's sleep, and nothing else.
	put(state, "/home/admin/sleepmid.sh", "echo y | sleep 300 | cat\necho awake\n")
	local job = typeLine(system, machine, state, console, "sh sleepmid.sh")

	local result = asleepDrive("sleeping middle", machine, job, PASSES)
	timely("3 stages, middle asleep", result)
	eq("the pipeline is asleep", job.state, "sleeping")
	eq("and nothing has reached the screen", #console.lines, 0)

	wakeUp(machine, 300000)
	eq("past the sleep, the pipeline is over", CeroSecOS.jobIsOver(job), true)
	-- `sleep` does not pass its input on -- nothing does unless it was written to
	-- do it -- so the "y" the first stage wrote dies in the first pipe and the
	-- last stage reads end of file.
	eq("the line after it ran, and only it", #console.lines, 1)
	eq("and that is the line", console.lines[1], "awake")
	note("3 stages, middle asleep", result, " (asleep)")
end

do
	-- The polling idiom the manual teaches, with a pipe behind it: watch a door,
	-- wait five seconds, go round. Fifty passes of sleep for every pass of work,
	-- for as long as the player leaves it running -- which is a program that must
	-- cost very nearly nothing, piped or not.
	local door = { entries = { { id = "door0", kind = "door", desc = "exterior",
		side = "W", pos = "0 5S", state = "closed" } } }
	door.list = function()
		local e = door.entries[1]
		return { { id = e.id, kind = e.kind, desc = e.desc, side = e.side,
			pos = e.pos, state = e.state } }
	end
	door.write = function() return false, "no" end
	benchDevices = door

	local machine, state, console = newMachine()
	put(state, "/home/admin/poll.sh",
		"while true; do cat /dev/door0; sleep 5; done | cat\n")
	local job = typeLine(system, machine, state, console, "sh poll.sh")

	local result = asleepDrive("door poll, piped", machine, job, PASSES)
	timely("door poll, piped", result)
	check("it is alive after a hundred seconds", not CeroSecOS.jobIsOver(job))
	-- A hundred seconds is twenty turns of a five-second loop, so the reader on
	-- the other side of the pipe has had twenty words out of it and no more.
	check("and has read the door about twenty times (" .. #console.lines .. ")",
		#console.lines >= 18 and #console.lines <= 22)
	eq("the last word it read is the door's", console.lines[#console.lines], "closed")
	note("door poll, piped", result, " (polling)")
	benchDevices = nil
end

--
-- 14c. What a pass that spends nothing costs, counted in Lua calls
--
-- The number above is real time, which is the thing that hurts a server but is
-- also the thing a loaded bench machine is worst at measuring. This is the same
-- assertion counted instead of timed: every call into the engine's stepper that
-- comes back having spent NO STEP is counted, in Lua calls, with debug.sethook
-- -- which lives here in the bench and never anywhere near the engine, because
-- an engine that instruments itself is an engine that pays for it in the game.
--
-- Twenty calls is the ceiling: a job asleep, or one whose pass could not begin,
-- is a table lookup, a clock and a return. Anything more is work being done on
-- behalf of a job that is not doing any.
--

local ZERO_CALLS = 20

do
	local calls, worstZero, zeroPasses, what = 0, 0, 0, "?"
	local instrumented = CeroSecOS.jobStep
	local hook = function() calls = calls + 1 end
	CeroSecOS.jobStep = function(state, job, env, budget)
		calls = 0
		debug.sethook(hook, "c")
		local status, used = instrumented(state, job, env, budget)
		debug.sethook()
		if used == 0 then
			zeroPasses = zeroPasses + 1
			if calls > worstZero then worstZero = calls end
			check(what .. ": a pass that spent no step costs at most " .. ZERO_CALLS ..
				" Lua calls (" .. calls .. ")", calls <= ZERO_CALLS)
		end
		return status, used
	end

	local cases = {
		{ "sleep", "sleep 300\n" },
		{ "sleep | cat", "sleep 300 | cat\n" },
		{ "sleep | sleep", "sleep 300 | sleep 300\n" },
		{ "sleeping middle", "echo y | sleep 300 | cat\n" },
	}
	for i = 1, #cases do
		what = cases[i][1]
		local machine, state, console = newMachine()
		put(state, "/home/admin/zero.sh", cases[i][2])
		typeLine(system, machine, state, console, "sh zero.sh")
		drive(machine, 200)
	end

	CeroSecOS.jobStep = instrumented
	check("and there were such passes to count (" .. zeroPasses .. ")", zeroPasses > 700)
	report[#report + 1] = string.format("  %-22s worst %4d Lua calls over %d passes",
		"a pass spending 0 steps", worstZero, zeroPasses)
end

--
-- 15. Thirty-two cron lines, all due every minute, on six machines (rung 5b)
--
-- The shape cron adds to the list: a player who fills his crontab and waits. Six
-- machines, thirty-two lines each, every one of them due every single minute --
-- a hundred and ninety-two jobs asked for a minute, on a county whose ceiling is
-- four jobs a machine.
--
-- What has to be true: the cost of a pass is FLAT -- the thousandth minute is no
-- dearer than the tenth -- the four-job ceiling holds, the log and the mailboxes
-- stay inside their own ceilings, and the disk does not move, because every byte
-- of what cron writes about itself is exempt and bounded.
--

do
	CeroSecJobs.machines = {}
	CeroSecJobs.lastMs = 0
	-- The game clock, which is cron's clock: it moves a minute at a time, and
	-- the sweep is what a real server does on Events.EveryOneMinute.
	local minute = 0
	local system2 = {}
	function system2:execEnv(luaObject, state)
		return { now = 740000000 + minute * 60, nowMs = _G.__now }
	end
	function system2:clockEnv() return { now = 740000000 + minute * 60 } end
	function system2:sessionOf(console)
		return { user = console.user or "admin", cwd = "/home/admin", stamp = 1 }
	end
	function system2:writeSession() end
	function system2:pushScreen() end
	function system2:applyPower() end

	local machines, states = {}, {}
	local lines = {}
	for i = 1, CeroSecOS.CRON_MAX_LINES do lines[i] = "* * * * * echo line" .. i end
	local crontab = table.concat(lines, "\n")
	for m = 1, 6 do
		local state = CeroSecOS.newState("ksp")
		local console = CeroSec.newConsole()
		console.user = "admin"
		console.cwd = "/home/admin"
		local machine = { on = true, console = console, x = m, y = 0, z = 0 }
		function machine:osState() return state end
		function machine:consoleState() return self.console end
		function machine:mirrorOS() end
		local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(),
			CeroSecOS.cronPath("admin"), crontab, false, 100)
		if done == nil then error("cannot write the crontab: " .. tostring(reason)) end
		machines[m], states[m] = machine, state
	end

	local _, diskBefore = CeroSecOS.usage(states[1])
	local perMinute = {}
	local worst = 0
	local clockStart = os.clock()
	-- A hundred minutes, and ten passes of the scheduler inside each of them:
	-- that is a second of game time per minute, which is more scheduler than a
	-- real machine gets between two minutes and so a harder bench.
	for _ = 1, 100 do
		minute = minute + 1
		local spent = 0
		for m = 1, 6 do CeroSecJobs.cronPass(system2, machines[m], 740000000 + minute * 60) end
		-- What cron hands a line: its own environment, and not the shell's. The
		-- default PATH and the account's home, which is what Vixie's cron puts in
		-- one -- and the reason a line that worked at a prompt because ~/bin was on
		-- the PATH there does not work here.
		if minute == 2 then
			local fired = CeroSecJobs.book(machines[1]).list[1]
			check("cron fired something", fired ~= nil)
			eq("with the default PATH", fired.vars.PATH, CeroSecOS.DEFAULT_PATH)
			eq("and the account's HOME", fired.vars.HOME, "/home/admin")
			eq("and nothing else at all", fired.nvars, 2)
		end
		for _ = 1, 10 do
			_G.__now = _G.__now + CeroSec.JOB_PASS_MS
			tickSteps = 0
			CeroSecJobs.system = system2
			CeroSecJobs.pass(_G.__now)
			spent = spent + tickSteps
			if tickSteps > worst then worst = tickSteps end
		end
		perMinute[#perMinute + 1] = spent
		for m = 1, 6 do
			check("no machine ever holds more than four jobs (" ..
				#CeroSecJobs.book(machines[m]).list .. ")",
				CeroSecOS.liveJobs(CeroSecJobs.book(machines[m]).list) <= CeroSecOS.MAX_JOBS)
			check("and nothing of it reaches the screen",
				#machines[m].console.lines == 0)
		end
	end
	local msPerMinute = (os.clock() - clockStart) * 1000 / 100

	check("no pass spent more than the county's budget (" .. worst .. ")",
		worst <= CeroSec.STEP_BUDGET_PER_TICK + CeroSecOS.STEP_COST_COMMAND)
	-- Flat: the last ten minutes cost no more than the first ten did.
	local early, late = 0, 0
	for i = 1, 10 do early = early + perMinute[i] end
	for i = 91, 100 do late = late + perMinute[i] end
	check("the cost of a minute does not climb (first 10: " .. early ..
		", last 10: " .. late .. ")", late <= early + CeroSec.STEP_BUDGET_PER_TICK)

	-- The log and the mailbox are bounded, and the disk is where it was: every
	-- byte cron wrote about itself is exempt by its path and capped at the write.
	for m = 1, 6 do
		local log = CeroSecOS.systemNode(states[m], CeroSecOS.CRON_LOG_PATH)
		check("the log is there", log ~= nil)
		check("a hundred lines at most (" .. #CeroSecOS.splitLines(log.data) .. ")",
			#CeroSecOS.splitLines(log.data) <= CeroSecOS.CRON_LOG_LINES)
		check("and four kilobytes at most (" .. #log.data .. ")",
			#log.data <= CeroSecOS.CRON_LOG_BYTES)
		local box = CeroSecOS.systemNode(states[m], CeroSecOS.mailPath("admin"))
		check("the mailbox is there", box ~= nil)
		check("a hundred lines at most (" .. #CeroSecOS.splitLines(box.data) .. ")",
			#CeroSecOS.splitLines(box.data) <= CeroSecOS.MAIL_LINES)
		check("and four kilobytes at most (" .. #box.data .. ")",
			#box.data <= CeroSecOS.MAIL_BYTES)
		check("the machine still boots with both of them on it",
			CeroSecOS.validate(states[m]) == true)
	end
	local _, diskAfter = CeroSecOS.usage(states[1])
	eq("and the disk did not move", diskAfter, diskBefore)

	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/minute",
		"192 cron jobs/minute", worst, msPerMinute)
end

--
-- 19a. A queue full of at jobs, waiting
--
-- A waiting job is not a running one and must cost NOTHING: it is a file in a
-- spool, and the only work it makes is the sweep that reads the queue once a game
-- minute. What this drives is the fullest queue a directory can hold, on six
-- machines, for a hundred minutes -- with every job due far enough away that none
-- of them ever runs, so what is measured is the WAITING and nothing else.
--
-- Then the other end of it: a queue where every job is due at once. Four jobs is
-- all a machine has, and an at job that cannot start is left in the queue and tried
-- again -- unlike a cron line, which is skipped because it will come round again --
-- so the queue drains four at a time and never loses one.
--
do
	-- The scheduler needs a system to ask the clock of, exactly as the cron bench
	-- above builds one: these benches are not the server and there is no world here.
	local NOW = 740000000
	local atMinute = 0
	local system3 = {}
	function system3:execEnv() return { now = NOW + atMinute * 60, nowMs = _G.__now } end
	function system3:clockEnv() return { now = NOW + atMinute * 60 } end
	function system3:sessionOf(console)
		return { user = console.user or "admin", cwd = "/home/admin", stamp = 1 }
	end
	function system3:writeSession() end
	function system3:pushScreen() end
	function system3:applyPower() end

	local machines, states = {}, {}
	local queued = 0
	for m = 1, 6 do
		local state = CeroSecOS.newState("ksp")
		local console = CeroSec.newConsole()
		console.user = "admin"
		console.cwd = "/home/admin"
		local machine = { on = true, console = console, x = m, y = 0, z = 0 }
		function machine:osState() return state end
		function machine:consoleState() return self.console end
		function machine:mirrorOS() end
		-- As many as the spool will hold, every one of them due a day away.
		local n = 1
		while true do
			local made = CeroSecOS.createNode(state, CeroSecOS.rootSession(),
				CeroSecOS.atJobPath(n),
				CeroSecOS.newFile("root", CeroSecOS.AT_JOB_MODE,
					CeroSecOS.atText("admin", NOW + 86400, "echo job" .. n)), 100)
			if made == nil then break end
			n = n + 1
		end
		queued = n - 1
		machines[m], states[m] = machine, state
	end
	check("the queue is as full as a directory gets (" .. queued .. ")",
		queued >= CeroSecOS.MAX_DIR_ENTRIES - 1)

	local worst, worstMinuteMs = 0, 0
	local clockStart = os.clock()
	for minute = 1, 100 do
		atMinute = minute
		local at = os.clock()
		for m = 1, 6 do CeroSecJobs.atPass(system3, machines[m], NOW + minute * 60) end
		local ms = (os.clock() - at) * 1000
		if ms > worstMinuteMs then worstMinuteMs = ms end
		for _ = 1, 10 do
			_G.__now = _G.__now + CeroSec.JOB_PASS_MS
			tickSteps = 0
			for m = 1, 6 do
				CeroSecJobs.runMachine(system3, machines[m],
					CeroSec.STEP_BUDGET_PER_MACHINE, _G.__now, nil, nil, true, nil)
			end
			if tickSteps > worst then worst = tickSteps end
		end
	end
	local msPerMinute = (os.clock() - clockStart) * 1000 / 100
	-- NOTHING ran, so nothing was spent: a waiting job costs no step at all.
	eq("a hundred minutes of waiting cost not one step", worst, 0)
	for m = 1, 6 do
		eq("and no job was made on machine " .. m,
			#CeroSecJobs.book(machines[m]).list, 0)
		eq("and the queue is where it was", #CeroSecOS.atJobs(states[m]), queued)
	end
	-- And what the sweep itself costs. It happens once a game MINUTE -- six seconds
	-- of wall clock at ten passes a second -- so the room here is not a pass's but
	-- sixty of them; ten times the per-pass ceiling is still three orders of
	-- magnitude of it, and the number is printed so a reader can check the claim.
	check("a minute of the sweep over six full queues is far under a pass's own " ..
		"ceiling times ten (" .. string.format("%.3f", worstMinuteMs) .. " ms)",
		worstMinuteMs < ceiling(WALL_MS_PER_PASS) * 10)
	report[#report + 1] = string.format(
		"  %-22s worst %4d steps/pass, %6.3f ms/minute (%d jobs x 6 machines)",
		"at queues waiting", worst, msPerMinute, queued)

	-- And now every one of them is due. The machine has four job slots, so it takes
	-- them four at a time -- and loses none: a job that could not start is still in
	-- the queue next minute.
	local machine = machines[1]
	local state = states[1]
	local drained = 0
	for minute = 101, 400 do
		atMinute = minute + 1440
		CeroSecJobs.atPass(system3, machine, NOW + 86400 + minute * 60)
		for _ = 1, 10 do
			_G.__now = _G.__now + CeroSec.JOB_PASS_MS
			tickSteps = 0
			CeroSecJobs.runMachine(system3, machine,
				CeroSec.STEP_BUDGET_PER_MACHINE, _G.__now, nil, nil, true, nil)
		end
		check("never more than four jobs at once (" ..
			CeroSecOS.liveJobs(CeroSecJobs.book(machine).list) .. ")",
			CeroSecOS.liveJobs(CeroSecJobs.book(machine).list) <= CeroSecOS.MAX_JOBS)
		if #CeroSecOS.atJobs(state) == 0 then
			drained = minute
			break
		end
	end
	check("the whole queue drained (" .. tostring(drained) .. " minutes for "
		.. queued .. " jobs)", drained > 0)
	-- Every one of them ran: what they printed is in the mail, and the mailbox is
	-- bounded like cron's because it is cron's.
	local box = CeroSecOS.systemNode(state, CeroSecOS.mailPath("admin"))
	check("and every one of them was mailed", box ~= nil and #box.data > 0)
	check("a hundred lines at most (" .. #CeroSecOS.splitLines(box.data) .. ")",
		#CeroSecOS.splitLines(box.data) <= CeroSecOS.MAIL_LINES)
	check("the machine still boots", CeroSecOS.validate(state) == true)
end

--
-- 20. A loop left running down an rlogin (rung 6a)
--
-- The whole promise of a remote session is whose budget it spends. A survivor
-- who rlogins into the machine across the room and leaves a loop running there
-- has made THAT machine slow at THAT one thing: the four job slots it fills are
-- its own, the twenty lines a second are its own, and the computer he is
-- standing at is at an idle prompt with nothing running on it at all.
--
-- The session's screen is bounded like any other -- it IS a console, the same
-- table the machine's own screen is -- and the glass it is showing on belongs to
-- a machine the scheduler never touches.
--

-- A pty on a machine, with a screen of its own, exactly as CeroSecNet.dial makes
-- one. The server half is not loaded here; what is being measured is the
-- SCHEDULER, and a pty is a table with a console on it.
local function attach(far, farState, here, n)
	if far.ptys == nil then far.ptys = {} end
	local pty = CeroSecOS.remoteOpen(farState, far.ptys,
		{ fromHost = "ksp-here", hops = 1, at = 740000000 })
	check("line " .. (n or 1) .. " opened", pty ~= nil)
	local screen = CeroSec.newConsole()
	screen.booted = true
	screen.line = pty.line
	screen.hops = 1
	screen.user = "admin"
	screen.cwd = "/home/admin"
	screen.watchAt = { x = here.x, y = here.y, z = here.z }
	pty.console = screen
	pty.from = { x = here.x, y = here.y, z = here.z }
	return pty
end

do
	local here = newMachine()
	here.x = 9
	local far, farState = newMachine()
	local pty = attach(far, farState, here)

	typeLine(system, far, farState, pty.console, "while true; do echo deep; done")
	local result = drive(far, PASSES, nil, function()
		check("the session's screen never holds more than its hundred lines",
			#pty.console.lines <= CeroSec.CONSOLE_MAX)
		check("and the machine at the glass is running nothing",
			here.jobs == nil or #here.jobs.list == 0)
	end)
	flat("a loop down an rlogin", result)
	check("the loop is still going", #far.jobs.list > 0)
	check("it wrote on the session's screen", #pty.console.lines > 0)
	eq("and not a line on the machine's own", #far.console.lines, 0)
	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/pass",
		"rlogin loop", result.worst, result.msPerPass)
end

-- Four of them at once, which is every job slot the machine has. The machine is
-- as slow as it was with one and no slower: the budget is the MACHINE's and is
-- shared, exactly as it is for four loops somebody typed at the keyboard.
do
	local here = newMachine()
	here.x = 9
	local far, farState = newMachine()
	local ptys = {}
	for i = 1, CeroSecOS.PTY_MAX do
		ptys[i] = attach(far, farState, here, i)
		typeLine(system, far, farState, ptys[i].console, "while true; do echo x; done")
	end
	eq("four sessions are in", CeroSecOS.ptyCount(far.ptys), CeroSecOS.PTY_MAX)
	eq("and the machine is full", #far.jobs.list, CeroSecOS.MAX_JOBS)

	local result = drive(far, PASSES, nil, function()
		for i = 1, #ptys do
			check("session " .. i .. "'s screen is bounded",
				#ptys[i].console.lines <= CeroSec.CONSOLE_MAX)
		end
		check("the machine at the glass is still running nothing",
			here.jobs == nil or #here.jobs.list == 0)
	end)
	flat("four inbound loops", result)
	-- A fifth caller is refused, which is what keeps that number four.
	local fifth, reason = CeroSecOS.remoteOpen(farState, far.ptys, { fromHost = "x", hops = 1 })
	eq("the fifth caller is refused", fifth, nil)
	eq("in a listener's own words", reason, "refused")
	-- And every one of the four really wrote, so none of them was starved out.
	for i = 1, #ptys do
		check("session " .. i .. " got its turn", #ptys[i].console.lines > 0)
	end
	local _, bytes = CeroSecOS.usage(farState)
	check("and the far machine's disk did not move (" .. bytes .. ")", bytes < 4000)
	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/pass",
		"4 inbound loops", result.worst, result.msPerPass)
end

--
-- A crontab of rlogin lines, on every machine in the county
--
-- The one a reviewer found: a cron line is a job with nobody in front of it, and
-- an rlogin from one used to hand the machine's OWN physical glass to another
-- computer, logged in. So this is the cheapest way a player could write that
-- attack -- thirty-two of them a minute on six machines, with a link layer that
-- says every wire reaches and a host that always resolves, so every single line
-- gets as far as the order -- and what is asserted is that it costs flat, says so
-- in the mail, and opens NOTHING.
--
-- Deliberately without a world behind it: the refusal is the ENGINE's, so if a
-- single line ever got as far as the link layer, CeroSecNet would be asked for a
-- machine by a system that has no getLuaObjectCount and the bench would die
-- rather than pass quietly.
--

do
	CeroSecJobs.machines = {}
	CeroSecJobs.lastMs = 0
	local minute = 0
	local system3 = {}
	-- A link layer that reaches everything: nothing is refused for being out of
	-- earshot, so every line spends what a line that really dials would spend.
	function system3:execEnv(luaObject, state)
		return { now = 740000000 + minute * 60, nowMs = _G.__now,
			net = { reach = function() return true end } }
	end
	function system3:clockEnv() return { now = 740000000 + minute * 60 } end
	function system3:sessionOf(console)
		return { user = console.user or "admin", cwd = "/home/admin", stamp = 1 }
	end
	function system3:writeSession() end
	function system3:pushScreen() end
	function system3:applyPower() end

	local LINES = 32
	local machines, states = {}, {}
	local lines = {}
	-- An address and not a name: it resolves with nothing written in /etc/hosts,
	-- which keeps the bench about the rlogin and not about the resolver.
	for i = 1, LINES do lines[i] = "* * * * * rlogin 10.99.1." .. i end
	local crontab = table.concat(lines, "\n")
	for m = 1, 6 do
		local state = CeroSecOS.newState("ksp")
		local console = CeroSec.newConsole()
		console.user = "admin"
		console.cwd = "/home/admin"
		local machine = { on = true, console = console, x = 20 + m, y = 0, z = 0 }
		function machine:osState() return state end
		function machine:consoleState() return self.console end
		function machine:mirrorOS() end
		local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(),
			CeroSecOS.cronPath("admin"), crontab, false, 100)
		if done == nil then error("cannot write the crontab: " .. tostring(reason)) end
		machines[m], states[m] = machine, state
	end

	local perMinute, worst = {}, 0
	local clockStart = os.clock()
	for _ = 1, 100 do
		minute = minute + 1
		local spent = 0
		for m = 1, 6 do CeroSecJobs.cronPass(system3, machines[m], 740000000 + minute * 60) end
		for _ = 1, 10 do
			_G.__now = _G.__now + CeroSec.JOB_PASS_MS
			tickSteps = 0
			CeroSecJobs.system = system3
			CeroSecJobs.pass(_G.__now)
			spent = spent + tickSteps
			if tickSteps > worst then worst = tickSteps end
		end
		perMinute[#perMinute + 1] = spent
		for m = 1, 6 do
			check("no machine ever holds more than four jobs",
				CeroSecOS.liveJobs(CeroSecJobs.book(machines[m]).list) <= CeroSecOS.MAX_JOBS)
			-- The two that matter: not a line was opened anywhere, and not a
			-- character of it reached the glass a survivor would be standing at.
			check("not one session was opened", machines[m].ptys == nil)
			check("and the machine's own glass is untouched",
				#machines[m].console.lines == 0)
			check("nor pointed at anything", machines[m].console.remote == nil)
		end
	end
	local msPerMinute = (os.clock() - clockStart) * 1000 / 100

	check("no pass spent more than the county's budget (" .. worst .. ")",
		worst <= CeroSec.STEP_BUDGET_PER_TICK + CeroSecOS.STEP_COST_COMMAND)
	-- Flat, counted from the SECOND minute: the passes of the first happen before
	-- cron has fired for the first time, so it spends nothing at all and a window
	-- that included it would be comparing ten minutes of work against nine.
	local early, late = 0, 0
	for i = 2, 11 do early = early + perMinute[i] end
	for i = 91, 100 do late = late + perMinute[i] end
	eq("the first minute is before cron has fired", perMinute[1], 0)
	check("and the second one already has work in it", perMinute[2] > 0)
	check("the cost of a minute does not climb (minutes 2-11: " .. early ..
		", last 10: " .. late .. ")", late <= early + CeroSec.STEP_BUDGET_PER_TICK)

	-- And every one of them said WHY, in rlogin's own words, in the account's
	-- mailbox -- which is bounded, like every other thing cron writes.
	for m = 1, 6 do
		local box = CeroSecOS.systemNode(states[m], CeroSecOS.mailPath("admin"))
		check("the mailbox is there", box ~= nil)
		check("and it is rlogin that is talking",
			string.find(box.data, "rlogin: not a terminal", 1, true) ~= nil)
		check("a hundred lines at most (" .. #CeroSecOS.splitLines(box.data) .. ")",
			#CeroSecOS.splitLines(box.data) <= CeroSecOS.MAIL_LINES)
		check("and four kilobytes at most (" .. #box.data .. ")",
			#box.data <= CeroSecOS.MAIL_BYTES)
		check("the machine still boots with it on it",
			CeroSecOS.validate(states[m]) == true)
	end

	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/minute",
		LINES .. " cron rlogins", worst, msPerMinute)
end

--
-- A crontab of cu lines, on every machine in the county (rung 6b)
--
-- The telephone reaches ANOTHER BUILDING, which is the one thing the coax never
-- did: a cron line that could dial would be a way to land a logged-in session on
-- the physical glass of a computer on the other side of Knox County, once a
-- minute, from a machine nobody is standing at. So the same attack the rlogin
-- section above is here for is written again with the new link, and what is
-- asserted is the same three things: it costs flat, it says so in the mail, and
-- it opens NOTHING.
--
-- Deliberately without a world behind it, exactly as the rlogin one is: the
-- refusal is the ENGINE's, so if a single line ever got as far as the link layer,
-- CeroSecNet would be asked for a dial tone by a system that has no
-- getLuaObjectCount and the bench would die rather than pass quietly.
--

do
	CeroSecJobs.machines = {}
	CeroSecJobs.lastMs = 0
	local minute = 0
	local system4 = {}
	function system4:execEnv(luaObject, state)
		return { now = 740000000 + minute * 60, nowMs = _G.__now,
			net = { reach = function() return true end } }
	end
	function system4:clockEnv() return { now = 740000000 + minute * 60 } end
	function system4:sessionOf(console)
		return { user = console.user or "admin", cwd = "/home/admin", stamp = 1 }
	end
	function system4:writeSession() end
	function system4:pushScreen() end
	function system4:applyPower() end

	local LINES = 32
	local machines, states = {}, {}
	local lines = {}
	-- Thirty-two different numbers, so nothing is deduplicated anywhere by
	-- accident: each line is a call to a building of its own.
	for i = 1, LINES do
		lines[i] = "* * * * * cu 555-" .. string.sub("000" .. tostring(i), -4)
	end
	local crontab = table.concat(lines, "\n")
	for m = 1, 6 do
		local state = CeroSecOS.newState("ksp")
		-- A machine IN a building: it has a line of its own, so nothing here is
		-- refused for the cheap reason. The record is what a line is derived from,
		-- exchange and all -- a record with no exchange in it is a machine with no
		-- telephone, and every one of these lines would be refused on the spot.
		CeroSecOS.setNetRecord(state, 4, 17, m, 555)
		local console = CeroSec.newConsole()
		console.user = "admin"
		console.cwd = "/home/admin"
		local machine = { on = true, console = console, x = 40 + m, y = 0, z = 0 }
		function machine:osState() return state end
		function machine:consoleState() return self.console end
		function machine:mirrorOS() end
		local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(),
			CeroSecOS.cronPath("admin"), crontab, false, 100)
		if done == nil then error("cannot write the crontab: " .. tostring(reason)) end
		machines[m], states[m] = machine, state
	end
	check("every machine of this county has a telephone line",
		CeroSecOS.phoneOf(states[1]) ~= nil)

	local perMinute, worst = {}, 0
	local clockStart = os.clock()
	for _ = 1, 100 do
		minute = minute + 1
		local spent = 0
		for m = 1, 6 do CeroSecJobs.cronPass(system4, machines[m], 740000000 + minute * 60) end
		for _ = 1, 10 do
			_G.__now = _G.__now + CeroSec.JOB_PASS_MS
			tickSteps = 0
			CeroSecJobs.system = system4
			CeroSecJobs.pass(_G.__now)
			spent = spent + tickSteps
			if tickSteps > worst then worst = tickSteps end
		end
		perMinute[#perMinute + 1] = spent
		for m = 1, 6 do
			check("no machine ever holds more than four jobs",
				CeroSecOS.liveJobs(CeroSecJobs.book(machines[m]).list) <= CeroSecOS.MAX_JOBS)
			check("not one call was opened", machines[m].ptys == nil)
			check("and the machine's own glass is untouched",
				#machines[m].console.lines == 0)
			check("nor pointed at anything", machines[m].console.remote == nil)
		end
	end
	local msPerMinute = (os.clock() - clockStart) * 1000 / 100

	check("no pass spent more than the county's budget (" .. worst .. ")",
		worst <= CeroSec.STEP_BUDGET_PER_TICK + CeroSecOS.STEP_COST_COMMAND)
	local early, late = 0, 0
	for i = 2, 11 do early = early + perMinute[i] end
	for i = 91, 100 do late = late + perMinute[i] end
	eq("the first minute is before cron has fired", perMinute[1], 0)
	check("and the second one already has work in it", perMinute[2] > 0)
	check("the cost of a minute does not climb (minutes 2-11: " .. early ..
		", last 10: " .. late .. ")", late <= early + CeroSec.STEP_BUDGET_PER_TICK)

	for m = 1, 6 do
		local box = CeroSecOS.systemNode(states[m], CeroSecOS.mailPath("admin"))
		check("the mailbox is there", box ~= nil)
		check("and it is cu that is talking",
			string.find(box.data, "cu: not a terminal", 1, true) ~= nil)
		check("and never the box, which was there to be opened",
			string.find(box.data, CeroSecOS.TNC_BANNER, 1, true) == nil)
		check("a hundred lines at most (" .. #CeroSecOS.splitLines(box.data) .. ")",
			#CeroSecOS.splitLines(box.data) <= CeroSecOS.MAIL_LINES)
		check("and four kilobytes at most (" .. #box.data .. ")",
			#box.data <= CeroSecOS.MAIL_BYTES)
		check("the machine still boots with it on it",
			CeroSecOS.validate(states[m]) == true)
	end

	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/minute",
		LINES .. " cron cu dials", worst, msPerMinute)
end

--
-- A call left open, with a loop running down it (rung 6b)
--
-- The worst a caller can do with a line he has: log in and start something that
-- never stops writing. A telephone session is a pty like any other, so the
-- machine's ceilings hold it -- and it has one more of its own, the line's 2400
-- baud, which must not be a way to make the machine work harder either: what the
-- line cannot carry is KEPT, and a job holding lines is a job that is not run.
--
-- So the assertions are the pty section's, plus the one that is new: no second of
-- any call ever carried more than CeroSec.PHONE_LINES_PER_S lines.
--

do
	local here = newMachine()
	here.x = 9
	local far, farState = newMachine()
	local pty = attach(far, farState, here)
	-- What makes it a call and not a session on the wire: where it came from is a
	-- number, and the pty carries the line it is on.
	pty.phone = { tel = "555-0142", key = "4.17" }
	pty.fromHost = "555-0142"

	typeLine(system, far, farState, pty.console, "while true; do echo deep; done")
	local worstSecond = 0
	local result = drive(far, PASSES, nil, function()
		local room = CeroSec.PHONE_LINES_PER_S - (pty.outCount or 0)
		if (pty.outCount or 0) > worstSecond then worstSecond = pty.outCount end
		check("no second of the call carried more than the line can (" ..
			tostring(pty.outCount) .. ")", room >= 0)
		check("the call's screen never holds more than its hundred lines",
			#pty.console.lines <= CeroSec.CONSOLE_MAX)
		check("and the machine at the glass is running nothing",
			here.jobs == nil or #here.jobs.list == 0)
	end)
	flat("a loop down a call", result)
	timely("a loop down a call", result)
	check("the loop is still going", #far.jobs.list > 0)
	check("it wrote on the call's screen", #pty.console.lines > 0)
	eq("and not a line on the machine's own", #far.console.lines, 0)
	-- The trickle really bit: a second of this loop on the machine's own glass is
	-- CeroSec.JOB_OUT_PER_SEC lines, and a second of it down a call is four.
	-- Four written out, not read off CeroSec.PHONE_LINES_PER_S: a bound taken from
	-- the constant it is there to hold would move with it and prove nothing.
	eq("a second of a call is four lines and never twenty", worstSecond, 4)
	check("which is well under the machine's own ceiling",
		4 < CeroSec.JOB_OUT_PER_SEC)
	-- And what the line could not carry is still in the job, bounded by the row
	-- ceiling like every other job's output and not growing for ever.
	check("the job's held output is bounded (" .. #far.jobs.list[1].out .. ")",
		#far.jobs.list[1].out <= CeroSecOS.JOB_OUT_MAX)
	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/pass",
		"a call left open", result.worst, result.msPerPass)
end

--
-- FOUR TELEPHONES RINGING (rung 6b)
--
-- A dial is a WAIT now: the modem goes off-hook and there is nothing on the glass
-- until the far end answers or S7 runs out, and S7 is fifteen seconds. So four
-- machines of the county can be in the middle of a dial at once, for fifteen
-- seconds each, and a ring that spun the scheduler would be the cheapest attack in
-- this file -- fifteen seconds of a machine's whole budget for one typed line, from
-- four machines, for as long as somebody keeps typing it.
--
-- It must cost NOTHING, and nothing is what is asserted: not a step spent by any
-- machine on any pass for as long as the four of them are ringing. The mechanism is
-- the VM's own sleep (jobStep answers "sleeping" and spends nought before it ever
-- reaches the walker), which is the same mechanism the sleeping pipelines above are
-- proved on -- this is that proof again with a telephone in front of it.
--
-- A world where NOBODY answers, so every one of the four rings out the full S7 and
-- the bench never reaches a link layer it has not got: the continuation of an
-- unanswered dial prints a word and gives no order, so nothing here ever asks
-- CeroSecNet for a dial.
--

do
	CeroSecJobs.machines = {}
	CeroSecJobs.lastMs = 0
	local ringSystem = {}
	function ringSystem:execEnv(luaObject, state)
		return { now = 740000000, nowMs = _G.__now,
			net = { phone = function() return CeroSecOS.MODEM.noCarrier end } }
	end
	function ringSystem:clockEnv() return { now = 740000000 } end
	function ringSystem:sessionOf(console)
		return { user = console.user or "admin", cwd = "/home/admin", stamp = 1 }
	end
	function ringSystem:writeSession() end
	function ringSystem:pushScreen() end
	function ringSystem:applyPower() end

	local RINGERS = 4
	local machines, consoles, lifted = {}, {}, {}
	for m = 1, RINGERS do
		local state = CeroSecOS.newState("ksp")
		-- A machine with a line of its own: the record carries the exchange, or the
		-- engine refuses the dial before it ever lifts the receiver.
		CeroSecOS.setNetRecord(state, 4, 17, m, 555)
		local console = CeroSec.newConsole()
		console.user = "admin"
		console.cwd = "/home/admin"
		local machine = { on = true, console = console, x = 80 + m, y = 0, z = 0 }
		function machine:osState() return state end
		function machine:consoleState() return self.console end
		function machine:mirrorOS() end
		machines[m], consoles[m] = machine, console
		local job = CeroSecJobs.startPrompt(ringSystem, machine, console,
			"cu 555-01" .. string.sub("00" .. tostring(m), -2))
		if job == nil then error("the dial was refused before it rang") end
	end

	-- One pass to lift the four receivers: startPrompt puts the line on the book and
	-- the scheduler is what runs it, which is where the wait is asked for.
	_G.__now = _G.__now + CeroSec.JOB_PASS_MS
	CeroSecJobs.system = ringSystem
	CeroSecJobs.pass(_G.__now)

	-- Every machine is asleep on its modem, and none of them has said anything.
	for m = 1, RINGERS do
		local job = CeroSecJobs.book(machines[m]).list[1]
		eq("machine " .. m .. " is asleep on the ring", job.state, "sleeping")
		eq("and has said nothing", #consoles[m].lines, 0)
		lifted[m] = job.steps
	end

	-- Fourteen seconds of passes, which is inside S7: all four still ringing, and
	-- not one step spent by anybody. Read off the same wrapper every other bench in
	-- this file counts with.
	local RINGING = 140
	local worst, spentAny = 0, 0
	local clockStart = os.clock()
	for _ = 1, RINGING do
		_G.__now = _G.__now + CeroSec.JOB_PASS_MS
		tickSteps = 0
		CeroSecJobs.system = ringSystem
		CeroSecJobs.pass(_G.__now)
		if tickSteps > worst then worst = tickSteps end
		spentAny = spentAny + tickSteps
	end
	local msPerPass = (os.clock() - clockStart) * 1000 / RINGING
	eq("no pass over four ringing telephones spends a single step", worst, 0)
	eq("nor do all of them together", spentAny, 0)
	-- And the real time, against the sleeping ceiling times the number of machines:
	-- WALL_MS_ASLEEP is what ONE machine asleep may cost a pass, and a pass here
	-- walks four of them. The steps above are the assertion that matters; this is
	-- the belt that says the walk itself did not become the cost.
	local asleepCeiling = ceiling(WALL_MS_ASLEEP * RINGERS)
	check("and a pass costs under " .. string.format("%.4f", asleepCeiling) ..
		" ms of real time (" ..
		string.format("%.4f", msPerPass) .. ")", msPerPass < asleepCeiling)
	for m = 1, RINGERS do
		local job = CeroSecJobs.book(machines[m]).list[1]
		eq("machine " .. m .. " is still ringing after fourteen seconds",
			job.state, "sleeping")
		eq("having spent nothing since it lay down", job.steps, lifted[m])
		eq("and still said nothing", #consoles[m].lines, 0)
	end

	-- And the ring ENDS. Past S7 the modem gives up, in its own word, and the job
	-- is over -- because a bench that proved a dial costs nothing would otherwise
	-- be just as green on a dial that hangs for ever.
	for _ = 1, 40 do
		_G.__now = _G.__now + CeroSec.JOB_PASS_MS
		CeroSecJobs.system = ringSystem
		CeroSecJobs.pass(_G.__now)
	end
	for m = 1, RINGERS do
		local book = CeroSecJobs.book(machines[m])
		eq("machine " .. m .. "'s dial is over past S7", #book.list, 0)
		local said = false
		for i = 1, #consoles[m].lines do
			if string.find(consoles[m].lines[i], CeroSecOS.MODEM.noCarrier, 1, true) then
				said = true
			end
		end
		check("and the modem gave up in its own word", said)
	end
	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.4f ms/pass",
		RINGERS .. " ringing dials", worst, msPerPass)
end

--
-- FOUR TNCs SITTING AT cmd: (rung 6c, SYSTEM_VERSION 17)
--
-- `cu -l /dev/radio0` is a PROGRAM now, and a program that spends its life waiting
-- for a line to be typed at it: the box prints its prompt and then nothing happens
-- at all until somebody types. Four machines of the county can be sitting at that
-- prompt at once, indefinitely -- nothing times it out, unlike a dial, which S7
-- ends after fifteen seconds -- so a box that spun the scheduler would be worse
-- than the ringing telephones above: it would be for ever.
--
-- It must cost NOTHING, and nothing is what is asserted: not a step spent by any
-- machine on any pass while the four of them sit there. The mechanism is the VM's
-- own wait (jobStep answers "waiting" and spends nought before it reaches the
-- walker), which is the mechanism a `read` in a script is already proved on -- this
-- is that proof again with a TNC in front of it.
--
-- And it ENDS, on `~.`, because a bench that proved a prompt costs nothing would
-- otherwise be just as green on a program that could never be got out of.
--

do
	CeroSecJobs.machines = {}
	CeroSecJobs.lastMs = 0
	-- A world with one radio on it, which is all tncOpen asks for: /dev is mounted
	-- for the length of a command and the line has to be a node in it.
	local function oneRadio()
		return {
			list = function()
				return { { id = "radio0", kind = "radio", desc = "ham", side = "",
					pos = "2E 1N", state = "144.390 on", mode = 440 } }
			end,
			write = function() return false, "permission denied" end,
		}
	end
	local tncSystem = {}
	function tncSystem:execEnv(luaObject, state)
		return { now = 740000000, nowMs = _G.__now, devices = oneRadio(),
			jobs = luaObject.jobs ~= nil and luaObject.jobs.list or nil,
			heard = luaObject.heard }
	end
	function tncSystem:clockEnv() return { now = 740000000 } end
	function tncSystem:sessionOf(console)
		return { user = console.user or "admin", cwd = "/home/admin", stamp = 1 }
	end
	function tncSystem:writeSession() end
	function tncSystem:pushScreen() end
	function tncSystem:applyPower() end

	local BOXES = 4
	local machines, consoles, opened = {}, {}, {}
	for m = 1, BOXES do
		local state = CeroSecOS.newState("ksp")
		CeroSecOS.setNetRecord(state, 4, 17, m)
		CeroSecOS.ensureCallsign(state)
		local console = CeroSec.newConsole()
		console.user = "admin"
		console.cwd = "/home/admin"
		local machine = { on = true, console = console, x = 90 + m, y = 0, z = 0 }
		function machine:osState() return state end
		function machine:consoleState() return self.console end
		function machine:mirrorOS() end
		machines[m], consoles[m] = machine, console
		local job = CeroSecJobs.startPrompt(tncSystem, machine, console,
			"cu -l " .. CeroSecOS.TNC_DEV)
		if job == nil then error("the line was refused before it opened") end
	end

	-- One pass to open the four lines: startPrompt puts the line on the book and the
	-- scheduler is what runs it, which is where the question is asked for.
	_G.__now = _G.__now + CeroSec.JOB_PASS_MS
	CeroSecJobs.system = tncSystem
	CeroSecJobs.pass(_G.__now)

	for m = 1, BOXES do
		local job = CeroSecJobs.book(machines[m]).list[1]
		eq("box " .. m .. " is waiting at its prompt", job.state, "waiting")
		eq("with the TNC's own prompt up", consoles[m].prompt.text, CeroSecOS.TNC_PROMPT)
		local said = false
		for i = 1, #consoles[m].lines do
			if consoles[m].lines[i] == CeroSecOS.TNC_BANNER then said = true end
		end
		check("and the banner on the glass", said)
		opened[m] = job.steps
	end

	-- Thirty seconds of passes -- twice the whole of S7, because nothing ends this
	-- one -- and not a step spent by anybody.
	local SITTING = 300
	local worst, spentAny = 0, 0
	local clockStart = os.clock()
	for _ = 1, SITTING do
		_G.__now = _G.__now + CeroSec.JOB_PASS_MS
		tickSteps = 0
		CeroSecJobs.system = tncSystem
		CeroSecJobs.pass(_G.__now)
		if tickSteps > worst then worst = tickSteps end
		spentAny = spentAny + tickSteps
	end
	local msPerPass = (os.clock() - clockStart) * 1000 / SITTING
	eq("no pass over four boxes at cmd: spends a single step", worst, 0)
	eq("nor do all of them together", spentAny, 0)
	local sittingCeiling = ceiling(WALL_MS_ASLEEP * BOXES)
	check("and a pass costs under " .. string.format("%.4f", sittingCeiling) ..
		" ms of real time (" .. string.format("%.4f", msPerPass) .. ")",
		msPerPass < sittingCeiling)
	for m = 1, BOXES do
		local job = CeroSecJobs.book(machines[m]).list[1]
		eq("box " .. m .. " is still at cmd: after thirty seconds", job.state, "waiting")
		eq("having spent nothing since the line opened", job.steps, opened[m])
	end

	-- And `~.` gets out of it: the line is hung up, cu says its own last word and
	-- the job is gone off the book.
	for m = 1, BOXES do
		local machine = machines[m]
		local job = CeroSecJobs.book(machine).list[1]
		consoles[m].prompt = nil
		CeroSecOS.jobInput(machine:osState(), job, "~.",
			tncSystem:execEnv(machine, machine:osState()))
	end
	for _ = 1, 5 do
		_G.__now = _G.__now + CeroSec.JOB_PASS_MS
		CeroSecJobs.system = tncSystem
		CeroSecJobs.pass(_G.__now)
	end
	for m = 1, BOXES do
		eq("box " .. m .. "'s line is hung up", #CeroSecJobs.book(machines[m]).list, 0)
		local said = false
		for i = 1, #consoles[m].lines do
			if consoles[m].lines[i] == CeroSecOS.CU_DISCONNECTED then said = true end
		end
		check("and cu said so in its own word", said)
	end
	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.4f ms/pass",
		BOXES .. " boxes at cmd:", worst, msPerPass)
end

--
-- A radio link left open, with a loop running down it (rung 6c)
--
-- The same worst case one link down. A radio session is a pty like any other, so
-- the machine's ceilings hold it, and the air's own 1200 baud is HALF the
-- telephone's -- which must not be a way to make the machine work harder either:
-- what the air cannot carry is KEPT, and a job holding lines is a job that is not
-- run.
--

do
	local here = newMachine()
	here.x = 7
	local far, farState = newMachine()
	local pty = attach(far, farState, here)
	-- What makes it a radio link and not a call: no number and no line, a
	-- CALLSIGN, and the set it was made on.
	pty.radio = { call = "KD4AXR", to = "KE4QWZ", key = "radio:7:0:0::0" }
	pty.fromHost = "KD4AXR"

	typeLine(system, far, farState, pty.console, "while true; do echo deep; done")
	local worstSecond = 0
	local result = drive(far, PASSES, nil, function()
		local room = CeroSec.RADIO_LINES_PER_S - (pty.outCount or 0)
		if (pty.outCount or 0) > worstSecond then worstSecond = pty.outCount end
		check("no second of the link carried more than the air can (" ..
			tostring(pty.outCount) .. ")", room >= 0)
		check("the link's screen never holds more than its hundred lines",
			#pty.console.lines <= CeroSec.CONSOLE_MAX)
		check("and the machine at the glass is running nothing",
			here.jobs == nil or #here.jobs.list == 0)
	end)
	flat("a loop down a radio link", result)
	timely("a loop down a radio link", result)
	check("the loop is still going", #far.jobs.list > 0)
	check("it wrote on the link's screen", #pty.console.lines > 0)
	eq("and not a line on the machine's own", #far.console.lines, 0)
	-- Two written out and not read off CeroSec.RADIO_LINES_PER_S, for the reason
	-- the telephone's four is written out: a bound taken from the constant it is
	-- there to hold would move with it and prove nothing.
	eq("a second on the air is two lines and never twenty", worstSecond, 2)
	check("which is half what a telephone call carries",
		worstSecond * 2 == CeroSec.PHONE_LINES_PER_S)
	check("the job's held output is bounded (" .. #far.jobs.list[1].out .. ")",
		#far.jobs.list[1].out <= CeroSecOS.JOB_OUT_MAX)
	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/pass",
		"a loop down a link", result.worst, result.msPerPass)
end

--
-- Thirty-two crontab lines that all open the TNC's LINE (rung 6c)
--
-- The county's worst radio abuse: every machine's crontab full of `cu -l
-- /dev/radio0`, every minute, for a hundred minutes. Nothing may be opened and --
-- the assertion this bench exists for -- NOTHING MAY BE TRANSMITTED: a crontab
-- that could reach the box would sit at a cmd: prompt nobody can type at, four
-- job slots at a time, and anything it was driven to would key a transmitter and
-- put two callsigns over the county from a machine nobody was standing at. The
-- refusal is in the engine, before the line is ever opened (CeroSecOSVM's `tnc`
-- control asks jobHasTerminal), so the count below is of transmissions the mod
-- made and it must be zero.
--

do
	local air = 0
	local before = _G.getZomboidRadio
	_G.getZomboidRadio = function()
		return { SendTransmission = function() air = air + 1 end }
	end

	local system5 = { }
	function system5:clockEnv() return { now = 740000000 } end
	-- With a radio in every room, so that what refuses these lines is the TERMINAL
	-- rule and not a missing device: a bench where the line could not be opened
	-- anyway would be green on a machine that let cron open one.
	function system5:execEnv(object, state)
		return { now = 740000000, nowMs = _G.__now, devices = {
			list = function()
				return { { id = "radio0", kind = "radio", desc = "ham", side = "",
					pos = "2E 1N", state = "144.390 on", mode = 440 } }
			end,
			write = function() return false, "permission denied" end,
		} }
	end
	function system5:pushScreen() end
	function system5:reply() end
	function system5:getLuaObjectAt() return nil end
	function system5:getLuaObjectCount() return 0 end
	function system5:getLuaObjectByIndex() return nil end
	function system5:startPrompt(object, console, line)
		return CeroSecJobs.start(system5, object, console, line, nil, nil)
	end

	-- The crontab ceiling, which is what "a crontab full of them" means.
	local LINES = 32
	local lines = {}
	for i = 1, LINES do lines[i] = "* * * * * cu -l " .. CeroSecOS.TNC_DEV end
	local crontab = table.concat(lines, "\n")

	local machines, states = {}, {}
	for m = 1, 6 do
		local machine, state = newMachine()
		machine.x = 100 + m
		CeroSecOS.setNetRecord(state, 4, 17, m)
		CeroSecOS.ensureCallsign(state)
		local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(),
			CeroSecOS.cronPath("admin"), crontab, false, 100)
		if done == nil then error("cannot write the crontab: " .. tostring(reason)) end
		machines[m], states[m] = machine, state
	end
	check("every machine of this county has a callsign",
		CeroSecOS.callsignOf(states[1]) ~= nil)

	local perMinute, worst = {}, 0
	local clockStart = os.clock()
	local minute2 = 0
	for _ = 1, 100 do
		minute2 = minute2 + 1
		local spent = 0
		for m = 1, 6 do CeroSecJobs.cronPass(system5, machines[m], 740000000 + minute2 * 60) end
		for _ = 1, 10 do
			_G.__now = _G.__now + CeroSec.JOB_PASS_MS
			tickSteps = 0
			CeroSecJobs.system = system5
			CeroSecJobs.pass(_G.__now)
			spent = spent + tickSteps
			if tickSteps > worst then worst = tickSteps end
		end
		perMinute[#perMinute + 1] = spent
		for m = 1, 6 do
			check("no machine ever holds more than four jobs",
				CeroSecOS.liveJobs(CeroSecJobs.book(machines[m]).list) <= CeroSecOS.MAX_JOBS)
			check("not one link was opened", machines[m].ptys == nil)
			check("and the machine's own glass is untouched",
				#machines[m].console.lines == 0)
			check("nor pointed at anything", machines[m].console.remote == nil)
		end
		eq("and not one byte went over the air", air, 0)
	end
	local msPerMinute = (os.clock() - clockStart) * 1000 / 100

	check("no pass spent more than the county's budget (" .. worst .. ")",
		worst <= CeroSec.STEP_BUDGET_PER_TICK + CeroSecOS.STEP_COST_COMMAND)
	local early, late = 0, 0
	for i = 2, 11 do early = early + perMinute[i] end
	for i = 91, 100 do late = late + perMinute[i] end
	eq("the first minute is before cron has fired", perMinute[1], 0)
	check("and the second one already has work in it", perMinute[2] > 0)
	check("the cost of a minute does not climb (minutes 2-11: " .. early ..
		", last 10: " .. late .. ")", late <= early + CeroSec.STEP_BUDGET_PER_TICK)

	for m = 1, 6 do
		local box = CeroSecOS.systemNode(states[m], CeroSecOS.mailPath("admin"))
		check("the mailbox is there", box ~= nil)
		check("and it is cu that is talking",
			string.find(box.data, "cu: not a terminal", 1, true) ~= nil)
		check("and never the box, which was there to be opened",
			string.find(box.data, CeroSecOS.TNC_BANNER, 1, true) == nil)
		check("the machine still boots with it on it",
			CeroSecOS.validate(states[m]) == true)
	end

	_G.getZomboidRadio = before
	report[#report + 1] = string.format("  %-22s worst %4d steps/pass, %6.3f ms/minute",
		LINES .. " cron TNC lines", worst, msPerMinute)
end

--
-- 21. The longest PATH there can be (rung 6b)
--
-- Every command a shell runs is a walk along PATH, so the length of that string
-- is the price of every command on the machine. Two programs here, and they are
-- the two halves of the same question:
--
--   * the worst PATH a player may SET -- eight directories, seven of them not
--     there, /bin at the very end, so every lookup walks the whole way;
--   * a PATH nobody could have set, three hundred and forty fields of it,
--     written straight into the console the way a forged save file would.
--
-- Both have to stay flat, stay timely, and stay inside the budget -- and the
-- first one has to be charged for what it costs, which is what makes the second
-- bounded rather than merely unlikely.
--

local function longPath(fields)
	local out = {}
	for _ = 1, fields - 1 do out[#out + 1] = "/nope" end
	out[#out + 1] = "/bin"
	return table.concat(out, ":")
end

do
	local machine, state, console = newMachine()
	local worstLegal = longPath(CeroSecOS.MAX_PATH_DIRS)
	eq("it is as many directories as a shell may have",
		#CeroSecOS.pathDirs(worstLegal), CeroSecOS.MAX_PATH_DIRS)

	-- `test` is one of the commands the engine runs without leaving the house and
	-- is still looked up as a file, so this is the walk and nothing else: no
	-- output, no writing, one lookup an iteration.
	put(state, "/home/admin/walk.sh",
		"PATH=" .. worstLegal .. "\nwhile true; do test 1 = 1; done\n")
	local job = typeLine(system, machine, state, console, "sh walk.sh")

	local result = drive(machine, PASSES)
	flat("worst legal PATH", result)
	timely("worst legal PATH", result)
	note("worst legal PATH", result)

	check("it is still running", job ~= nil and not CeroSecOS.jobIsOver(job))
	eq("and it has said nothing at all", #console.lines, 0)
	eq("the command was found at the end of the walk", job.status, 0)
	eq("the PATH is the one it set", job.vars.PATH, worstLegal)
	check("the machine still boots", CeroSecOS.validate(state) == true)
end

-- One longer than that is refused where it is set, and the line says which
-- ceiling it met. A player cannot buy himself a dearer machine.
do
	local machine, state, console = newMachine()
	local tooMany = longPath(CeroSecOS.MAX_PATH_DIRS + 1)
	put(state, "/home/admin/greedy.sh", "PATH=" .. tooMany .. "\necho reached\n")
	local job = typeLine(system, machine, state, console, "sh greedy.sh")
	drive(machine, 20)
	eq("the script stopped on the ceiling", job.state, "error")
	eq("and said which", console.lines[#console.lines],
		"greedy.sh: line 1: too many PATH entries")
	eq("nothing after it ran", #console.lines, 1)
end

-- And the one nobody could have typed: a console off a save file with a
-- kilobyte of PATH in it. The walk stops at the ceiling, so what it costs is
-- eight directories whatever the string says.
do
	local machine, state, console = newMachine()
	local field = "/a:"
	local fields = math.floor(CeroSecOS.MAX_VAR_BYTES / #field)
	local forged = string.rep(field, fields) .. "/bin"
	check("the forged PATH is hundreds of fields deep (" ..
		#CeroSecOS.pathDirs(forged) .. ")", #CeroSecOS.pathDirs(forged) > 300)

	-- The bound itself, asked of the walk directly: /bin is the last field of
	-- that string and is never reached, and the walk says how far it went.
	local found, reason, walked =
		CeroSecOS.lookupPath(state, system:sessionOf(console), "ls", forged)
	eq("the walk finds nothing past the ceiling", found, nil)
	eq("and says so", reason, "command not found")
	eq("having looked in exactly the ceiling's worth of directories", walked,
		CeroSecOS.MAX_PATH_DIRS)

	-- And under the scheduler, with a loop looking a name up every iteration.
	-- The loop is a `for` over a list of words: `while` would need a command for
	-- its condition, and on this PATH there is no command to be had.
	console.shvars = { PATH = forged }
	local words = {}
	for i = 1, 200 do words[i] = "w" .. i end
	local job = typeLine(system, machine, state, console,
		"for i in " .. table.concat(words, " ") .. "; do test 1 = 1; done")

	local result = drive(machine, 400)
	flat("forged long PATH", result)
	timely("forged long PATH", result)
	note("forged long PATH", result)

	check("every iteration said the same thing",
		string.find(console.lines[#console.lines] or "", "command not found", 1, true) ~= nil)
	check("the console never kept more than its hundred lines",
		#console.lines <= CeroSec.CONSOLE_MAX)
	check("the machine still boots", CeroSecOS.validate(state) == true)
end

--
-- 22. A symbolic link that points at itself (rung 6b)
--
-- A link is a path the walk follows, so a loop of them is the cheapest endless
-- walk a player can write: two links pointing at each other, and one `cat`.
-- What bounds it is MAX_LINK_HOPS, counted per resolution, and what this asks is
-- whether a loop looked up as fast as the machine allows stays flat.
--

do
	local machine, state, console = newMachine()
	local root = CeroSecOS.rootSession()
	-- The worst shape there is: a chain as long as the ceiling allows, ending in a
	-- link back to its own front, so every lookup walks the whole way before it
	-- gives up.
	local names = {}
	for i = 1, CeroSecOS.MAX_LINK_HOPS do names[i] = "/home/admin/L" .. i end
	for i = 1, #names do
		local target = names[i + 1] or names[1]
		local made, why = CeroSecOS.createNode(state, root, names[i],
			CeroSecOS.newLink("admin", target), 100)
		if made == nil then error("cannot make " .. names[i] .. ": " .. tostring(why)) end
	end

	-- The bound itself: the resolution ends, with the reason, and not after some
	-- number of hops that depends on how the loop was drawn.
	local node, reason = CeroSecOS.getNode(state, system:sessionOf(console), names[1])
	eq("the walk gives up", node, nil)
	eq("and says which ceiling it met", reason, "too many levels of symbolic links")

	put(state, "/home/admin/loop.sh", "while true; do cat /home/admin/L1; done\n")
	local job = typeLine(system, machine, state, console, "sh loop.sh")

	local result = drive(machine, PASSES)
	flat("symlink loop", result)
	timely("symlink loop", result)
	note("symlink loop", result)

	check("it is still running", job ~= nil and not CeroSecOS.jobIsOver(job))
	check("saying the same thing every time round",
		string.find(console.lines[#console.lines] or "", "too many levels", 1, true) ~= nil)
	check("the console never kept more than its hundred lines",
		#console.lines <= CeroSec.CONSOLE_MAX)
	check("the machine still boots with the loop on its disk",
		CeroSecOS.validate(state) == true)

	-- And a link that points at a path DEEPER than the machine can address is the
	-- other way a walk could have run away: it says so instead.
	local deep = "/" .. string.rep("d/", CeroSecOS.MAX_DEPTH) .. "d"
	local made = CeroSecOS.createNode(state, root, "/home/admin/deep",
		CeroSecOS.newLink("admin", deep), 100)
	check("the deep link was made", made ~= nil)
	local _, why = CeroSecOS.getNode(state, system:sessionOf(console), "/home/admin/deep")
	eq("and following it is refused by the depth ceiling", why, "path too deep")
end

--
-- 25. rsh, which WAITS (rung 6c)
--
-- rsh blocks now: the job that gave it is parked -- state "waiting", no cpu
-- clock running, nothing on the processor -- while the FAR machine runs the
-- command on its own budget, and when the answer comes back the job runs on.
-- Which makes a loop of them the cheapest expensive-looking program a player can
-- write, and puts two questions to this bench:
--
--   * a script dialling over and over costs this machine nothing that climbs,
--     and cannot fill the far machine either -- one command at a time is all a
--     blocking rsh can have out there;
--   * a remote command that never ends holds ONE job here, at no cost, until
--     somebody takes it away -- and taking it away takes the far session with
--     it, wherever the far command had got to.
--
-- The link layer is faked the way section 19's is (every wire reaches), and the
-- two machines are real: the far one runs a real shell on a real pty and its
-- jobs are stepped by the same scheduler.
--

local function newNetBench()
	CeroSecJobs.machines = {}
	CeroSecJobs.lastMs = 0
	local objects = {}
	local nsys = {}
	function nsys:execEnv(luaObject, state)
		return { now = 740000000, nowMs = _G.__now,
			net = { reach = function() return true end } }
	end
	function nsys:clockEnv() return { now = 740000000 } end
	function nsys:sessionOf(console)
		return { user = console.user or "admin", cwd = console.cwd or "/home/admin",
			stamp = 1, line = console.line, hops = console.hops }
	end
	function nsys:writeSession(console, session)
		console.user = session.user
		console.cwd = session.cwd
		console.stack = session.stack
	end
	function nsys:pushScreen() pushes = pushes + 1 end
	function nsys:applyPower() end
	function nsys:getLuaObjectCount() return #objects end
	function nsys:getLuaObjectByIndex(i) return objects[i] end
	function nsys:getLuaObjectAt(x, y, z)
		for i = 1, #objects do
			local o = objects[i]
			if o.x == x and o.y == y and o.z == z then return o end
		end
		return nil
	end
	-- The one thing a dial asks of the server that this bench has to answer: the
	-- far machine's shell, as its pty's own foreground job. The real server takes
	-- a pass in the caller's hand here and the scheduler's next tick does it
	-- instead, which is one pass later and nothing else.
	function nsys:startPrompt(luaObject, console, line)
		local job, refusal = CeroSecJobs.startPrompt(self, luaObject, console, line)
		if job == nil then CeroSec.consolePush(console, tostring(refusal)) end
		return job
	end

	local function machine(x, name, n)
		local state = CeroSecOS.newState(name)
		local console = CeroSec.newConsole()
		console.booted = true
		console.user = "admin"
		console.cwd = "/home/admin"
		-- `os` is the MIRRORED state, and the link layer reads the address off that
		-- rather than off osState(): a ping must not walk every disk in the county
		-- (SCeroSecNet's recordOf). The real object mirrors on every write; here the
		-- table is the same one, which is the same fact.
		local m = { on = true, console = console, x = x, y = 0, z = 0, os = state }
		function m:osState() return state end
		function m:consoleState() return self.console end
		function m:mirrorOS() end
		CeroSecOS.setNetRecord(state, 1, 1, n)
		objects[#objects + 1] = m
		return m, state, console
	end

	local here, hereState, hereConsole = machine(1, "ksp-here", 1)
	local far, farState, farConsole = machine(2, "ksp-far", 2)
	-- "gate" is the far machine, and the far machine trusts this one: rshd's whole
	-- protocol, so that every line gets as far as a real command over there.
	local hosts = CeroSecOS.systemNode(hereState, CeroSecOS.HOSTS_PATH)
	CeroSecOS.setData(hereState, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		(hosts.data or "") .. "\n" .. CeroSecOS.address(farState) .. " gate", 100)
	-- And it can NAME this one, which is what makes that trust line about a
	-- machine: a name in /etc/hosts.equiv is resolved through the far machine's own
	-- /etc/hosts and never against the name a caller announces
	-- (CeroSecOS.trustWords).
	local farHosts = CeroSecOS.systemNode(farState, CeroSecOS.HOSTS_PATH)
	CeroSecOS.setData(farState, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		(farHosts.data or "") .. "\n" .. CeroSecOS.address(hereState) .. " "
		.. CeroSecOS.hostname(hereState), 100)
	CeroSecOS.writeFile(farState, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH,
		CeroSecOS.hostname(hereState), false, 100)
	return { sys = nsys, here = here, hereState = hereState, hereConsole = hereConsole,
		far = far, farState = farState, farConsole = farConsole }
end

do
	local bench = newNetBench()
	put(bench.hereState, "/home/admin/dial.sh", "while true; do rsh gate true; done\n")
	local job = typeLine(bench.sys, bench.here, bench.hereState, bench.hereConsole,
		"sh dial.sh")
	check("the dialling script started", job ~= nil)

	local result = drive(bench.here, PASSES, nil, function()
		check("the far machine never holds more than one line of this script's",
			CeroSecOS.ptyCount(bench.far.ptys) <= 1)
		check("nor more than its own four jobs",
			#CeroSecJobs.book(bench.far).list <= CeroSecOS.MAX_JOBS)
		check("and the near console keeps its hundred lines",
			#bench.hereConsole.lines <= CeroSec.CONSOLE_MAX)
	end)
	flat("a loop of rsh", result)
	timely("a loop of rsh", result)
	note("a loop of rsh", result)

	-- The witness: it really did dial, over and over, and it really is still
	-- going round -- a flat cost on a script that never reached the wire would
	-- prove nothing at all.
	check("the script went round many times (" .. tostring(job.steps) .. " steps)",
		job.steps > 100)
	check("it is still running", not CeroSecOS.jobIsOver(job))
	-- It really reached the far machine, over and over: that machine's own wtmp
	-- has a line in and a line out for every dial, which is what rshd logs.
	local wtmp = CeroSecOS.systemNode(bench.farState, CeroSecOS.WTMP_PATH)
	local ins = 0
	for _ in string.gmatch(wtmp ~= nil and wtmp.data or "", "\nin ") do ins = ins + 1 end
	check("the far machine logged many sessions in (" .. ins .. ")", ins > 5)
	check("and this machine's own glass stayed empty",
		#bench.hereConsole.lines == 0)
end

do
	local bench = newNetBench()
	put(bench.hereState, "/home/admin/hold.sh",
		"rsh gate \"while true; do x=1; done\"\necho after\n")
	local job = typeLine(bench.sys, bench.here, bench.hereState, bench.hereConsole,
		"sh hold.sh")

	-- Two passes to get the dial out of the door, and then the steps it has spent
	-- are the steps it will have spent: what a wait costs is nothing.
	drive(bench.here, 2)
	eq("the job is waiting", job.state, "waiting")
	local spent = job.steps
	local result = drive(bench.here, 200, nil, function()
		check("the waiting job is off the processor", job.cpuSince == nil)
		eq("and spends nothing while it waits", job.steps, spent)
	end)
	flat("rsh waiting on a loop", result)
	note("rsh waiting on a loop", result, " (waiting)")

	eq("it is waiting still", job.state, "waiting")
	eq("and `jobs` has a word of its own for it", CeroSecOS.jobWord(job), "remote")
	-- The far machine is the one doing the work, on its own budget: the loop is
	-- its pty's own foreground job, which is why `liveJobs` is not what counts it.
	check("the far machine is the one doing the work",
		#CeroSecJobs.book(bench.far).list >= 1)
	eq("one line out there", CeroSecOS.ptyCount(bench.far.ptys), 1)
	check("and the script has not gone on", #bench.hereConsole.lines == 0)

	-- Escape, which is what a survivor does: the job goes, and the far session
	-- goes with it wherever the far command had got to.
	job.killReq = true
	_G.__now = _G.__now + CeroSec.JOB_PASS_MS
	CeroSecJobs.tick()
	_G.__now = _G.__now + CeroSec.JOB_PASS_MS
	CeroSecJobs.tick()
	check("the job is over", CeroSecOS.jobIsOver(job))
	eq("the line was given back", CeroSecOS.ptyCount(bench.far.ptys), 0)
	eq("and the far machine is running nothing at all",
		#CeroSecJobs.book(bench.far).list, 0)
	check("nothing of the loop reached this machine's glass",
		not string.find(table.concat(bench.hereConsole.lines, "\n"), "after", 1, true))
end

do
	-- The other way a remote that never ends comes back: the FAR machine's cpu
	-- ceiling. Five minutes of its processor with no wait in it and the far job is
	-- killed, which ends the session, which is what finally answers the job that
	-- has been waiting here -- with 130, the status a killed job carries.
	local bench = newNetBench()
	put(bench.hereState, "/home/admin/hold.sh",
		"rsh gate \"while true; do x=1; done\"\necho \"after $?\"\n")
	local job = typeLine(bench.sys, bench.here, bench.hereState, bench.hereConsole,
		"sh hold.sh")
	-- A second a pass, which is how this bench reaches a five-minute ceiling in a
	-- few hundred passes (section 9 does the same).
	local passes = CeroSec.JOB_CPU_LIMIT_S + 20
	local result = drive(bench.here, passes, 1000)
	flat("rsh waiting on the far cpu ceiling", result)
	note("rsh, far cpu ceiling", result, " (killed over there)")

	check("the far machine killed it", CeroSecOS.ptyCount(bench.far.ptys) == 0)
	check("the job that was waiting is running again", CeroSecOS.jobIsOver(job))
	local said = table.concat(bench.hereConsole.lines, "\n")
	check("and went on with the status of a killed command: " .. said,
		string.find(said, "after 130", 1, true) ~= nil)
end

--
-- 20. Motion sensors (rung 4d)
--
-- The one thing in this mod that costs something every second whether anybody is
-- typing or not. Every other program in this file is a player's; this one is the
-- SERVER's, and the question is the same: what does the worst county cost?
--
-- The worst county: six computers, all on, eight motion sensors each, forty
-- squares in every field and a body standing on half of them -- and every body
-- moving every second, so no sample is ever cheap and no contact is ever open.
-- Forty-eight sensors is more than a shopping mall would hold and a hundred and
-- ninety-two bodies is a horde.
--
-- Driven for a thousand seconds, which is the whole of a sixteen-minute siege.
-- What must be true is what is true of every other pass in this file: FLAT -- the
-- thousandth second is no dearer than the tenth -- and cheap in real time.
--
do
	local SENSORS, FIELD, BODIES, SECONDS = 48, 40, 20, 1000

	-- A world of squares, each with its bodies on it. Nothing else: the sample
	-- pass looks up a square and asks it for its moving objects, and those are the
	-- only two calls it makes.
	local world = { squares = {} }
	world.getGridSquare = function(_, x, y, z)
		return world.squares[x .. "," .. y .. "," .. z]
	end
	local function squareAt(x, y, z)
		local key = x .. "," .. y .. "," .. z
		local sq = world.squares[key]
		if sq ~= nil then return sq end
		sq = { bodies = {} }
		sq.getMovingObjects = function()
			return { size = function() return #sq.bodies end,
				get = function(_, i) return sq.bodies[i + 1] end }
		end
		world.squares[key] = sq
		return sq
	end

	local bodies = {}
	CeroSecSensors.book = {}
	for s = 1, SENSORS do
		-- Every sensor in its own patch of the map, so no two share a square and
		-- the cost is the whole forty-eight times forty and not a cache hit.
		local ox, oy = s * 100, s * 100
		local record = { x = ox, y = oy, z = 0, range = CeroSec.SENSOR_RANGE,
			field = {} }
		-- The squares of the field, NEAREST FIRST. Nearest first because the bodies
		-- go on the first twenty of them, and a body outside the reach is a body the
		-- distance test throws away cheaply -- which would make this bench measure
		-- an empty room and call it a horde.
		local box = {}
		local r = CeroSecSensors.FIELD_MAX
		for dx = -8, 8 do
			for dy = -8, 8 do box[#box + 1] = { dx, dy, dx * dx + dy * dy } end
		end
		table.sort(box, function(a, b)
			if a[3] ~= b[3] then return a[3] < b[3] end
			if a[1] ~= b[1] then return a[1] < b[1] end
			return a[2] < b[2]
		end)
		eq("the field is no wider than the ceiling allows", FIELD <= r, true)
		for i = 1, FIELD do
			local x, y = ox + box[i][1], oy + box[i][2]
			record.field[i] = { x, y, 0 }
			local square = squareAt(x, y, 0)
			if i <= BODIES then
				-- Half of them warm, and every one of them inside the range so the
				-- distance test never gets to refuse anybody: the expensive path is
				-- the one where every body counts.
				local body = { __class = "IsoZombie", fx = x + 0.5, fy = y + 0.5,
					bx = x, by = y, step = 0 }
				body.getX = function() return body.fx end
				body.getY = function() return body.fy end
				body.isInvisible = function() return false end
				square.bodies[#square.bodies + 1] = body
				bodies[#bodies + 1] = body
			end
		end
		CeroSecSensors.book["h" .. s] = record
	end
	eq("forty-eight heads in the book", SENSORS, 48)
	eq("and a horde in front of them", #bodies, SENSORS * BODIES)

	-- One second: every body shuffles inside its own tile, and then the pass. Inside
	-- the tile, because a body that walked off across the map would leave the field
	-- and the bench would end up measuring an empty room. It also keeps every one of
	-- them inside the reach, which the nearest-first ordering above put them within.
	local function pass()
		for i = 1, #bodies do
			local b = bodies[i]
			b.step = (b.step + 1) % 4
			b.fx = b.bx + 0.2 + b.step * 0.2
			b.fy = b.by + 0.8 - b.step * 0.2
		end
		_G.__now = _G.__now + CeroSecSensors.SAMPLE_MS
		CeroSecSensors.samplePass(_G.__now)
	end

	_G.__world = world
	-- Warm, so the first hundred is not paying for the first signature of every
	-- head -- which is the one that has nothing to compare against.
	for _ = 1, 20 do pass() end

	local function timed(n)
		local at = os.clock()
		for _ = 1, n do pass() end
		return (os.clock() - at) * 1000 / n
	end

	local first = timed(100)
	for _ = 1, SECONDS - 200 do pass() end
	local last = timed(100)

	-- Flat. The same rule every program above is held to: a cost that climbs is a
	-- server that dies at hour three, and the book here is a table that could
	-- quietly grow a signature per body per second if a sample kept anything.
	check(string.format("the sensor pass is flat (%.3f ms then %.3f ms)", first, last),
		last <= first * 2 + 0.5)

	-- And cheap. Once a SECOND and not once a tick, so what this is a fraction of
	-- is a whole second and not a frame: the measured number on an ordinary
	-- machine is about five milliseconds, half a percent of it, for a county
	-- nobody will ever build. Twenty is the ceiling and it is generous on purpose,
	-- the way WALL_MS_PER_PASS is: this is a floor under "the server is not being
	-- hurt" and a loaded machine must not turn it red -- and it is scaled by
	-- the calibration, like every other ms ceiling here.
	local sensorCeiling = ceiling(20)
	check(string.format("and costs %.3f ms a second for 48 heads and 960 bodies (under %.3f)",
		last, sensorCeiling), last < sensorCeiling)

	-- The contacts are all closed, which is the other half of the bargain: a pass
	-- that was cheap because it saw nothing would prove nothing.
	local closed = 0
	for _, record in pairs(CeroSecSensors.book) do
		if record.holdUntil ~= nil and _G.__now < record.holdUntil then closed = closed + 1 end
	end
	eq("every head saw the horde it was standing in", closed, SENSORS)

	-- Nothing grew. A sample keeps ONE string per head and the horde is not
	-- remembered body by body.
	local held = 0
	for _ in pairs(CeroSecSensors.book) do held = held + 1 end
	eq("and the book is still forty-eight rows", held, SENSORS)

	report[#report + 1] = string.format(
		"  %-22s worst %4d squares/s, %6.3f ms/s (48 heads, 960 bodies)",
		"sensor sampling", SENSORS * FIELD, last)

	-- And the empty county, which is what almost every server is: no head in the
	-- book, and a pass that touches nothing at all.
	CeroSecSensors.book = {}
	local at = os.clock()
	for _ = 1, SECONDS do
		_G.__now = _G.__now + CeroSecSensors.SAMPLE_MS
		CeroSecSensors.samplePass(_G.__now)
	end
	local idle = (os.clock() - at) * 1000 / SECONDS
	local idleCeiling = ceiling(0.01)
	check(string.format("a county with no sensor in it costs %.4f ms a second (under %.4f)",
		idle, idleCeiling), idle < idleCeiling)
	_G.__world = nil
end

--
-- 22. The pager waiting, and find on a full disk (fidelity A)
--
-- Two new commands whose cost a hostile player would reach for: one that WAITS
-- for a keypress and one that walks the whole tree.
--

-- 22a. A `more` standing at its prompt costs NOTHING.
--
-- The one thing a pager must never do is spin. A job waiting on an answer is off
-- the processor -- the scheduler's own rule for `read` and for sudo's password --
-- and this is the bench that says `more` is on the same side of it: a thousand
-- passes with the question up, and not one step spent.
do
	local machine, state, console = newMachine()
	local body = {}
	for i = 1, 200 do body[#body + 1] = "line " .. i end
	put(state, "/home/admin/long", table.concat(body, "\n"))

	typeLine(system, machine, state, console, "more /home/admin/long")
	-- The first pass prints the screenful and puts the question up.
	local opening = drive(machine, 1, CeroSec.JOB_PASS_MS)
	local fg = nil
	for i = 1, #machine.jobs.list do
		if machine.jobs.list[i].interactive then fg = machine.jobs.list[i] end
	end
	check("the pager is still on the machine", fg ~= nil)
	eq("and it is waiting", fg.state, "waiting")
	check("with more's own prompt up",
		console.prompt ~= nil and string.find(console.prompt.text, "--More--", 1, true) ~= nil)

	local waiting = drive(machine, PASSES, CeroSec.JOB_PASS_MS)
	local spent = 0
	for i = 1, #waiting.perPass do spent = spent + waiting.perPass[i] end
	eq("a thousand passes at the --More-- prompt cost nothing at all", spent, 0)
	eq("and the job is where it was", fg.state, "waiting")
	flat("more waiting", waiting)
	timely("more waiting", waiting)
	note("more at its prompt", waiting, " (0 steps over " .. PASSES .. " passes)")

	-- And it is still answerable: the wait was a wait and not a death.
	local answered = console.prompt
	console.prompt = nil
	CeroSecOS.jobInput(state, fg, "q", system:execEnv(machine, state))
	check("the token was the job's", answered.cont.cmd == "job")
	drive(machine, 5, CeroSec.JOB_PASS_MS)
	eq("q ended it", CeroSecOS.jobIsOver(fg), true)
end

-- 22b. find over a tree with every node on the disk in it.
--
-- MAX_NODES is 512, so this is the widest walk a machine can be asked for, and
-- it is ONE command: the budget has to cover it in one pass, or a `find /` would
-- be a command that never finishes.
do
	local machine, state, console = newMachine()
	-- A tree as deep as a path may go and as wide as the nodes allow: 15 levels
	-- with a handful of files at each, until the disk says no.
	local root = CeroSecOS.rootSession()
	local made = 0
	local path = "/home/admin"
	for depth = 1, CeroSecOS.MAX_DEPTH - 3 do
		path = path .. "/d"
		if CeroSecOS.createNode(state, root, path, CeroSecOS.newDir("admin", 755), 100) == nil then
			break
		end
		made = made + 1
		for f = 1, 30 do
			local file = path .. "/f" .. f .. ".txt"
			if CeroSecOS.writeFile(state, root, file, "x", false, 100) == nil then break end
			made = made + 1
		end
	end
	local nodes = CeroSecOS.usage(state)
	check("the disk really is nearly full of nodes (" .. nodes .. " of "
		.. CeroSecOS.MAX_NODES .. ")", nodes > CeroSecOS.MAX_NODES / 2)
	check("and the tree is most of them (" .. made .. ")", made > 200)

	-- Counted down a pipe and not into a file: five hundred paths is more text
	-- than a file on this machine may hold (4096 bytes), and what this bench is
	-- about is the COST of the walk rather than where its answer went.
	--
	-- /home and not /: a walk that meets a directory it may not read comes back
	-- UNSUCCESSFUL, and an unsuccessful command's lines are a refusal on this
	-- machine -- they go to the screen and never down a pipe, which is the rule
	-- `cat good bad | wc -l` already runs on. So `find / | wc -l` as an ordinary
	-- account counts nothing and prints everything, and the tree this bench built
	-- is under /home anyway.
	typeLine(system, machine, state, console, "find /home | wc -l")
	local walk = drive(machine, PASSES, CeroSec.JOB_PASS_MS)
	flat("find over the disk", walk)
	timely("find over the disk", walk)
	local counted = nil
	for i = 1, #console.lines do
		local n = string.match(console.lines[i], "^%s*(%d+)%s*$")
		if n ~= nil then counted = tonumber(n) end
	end
	check("the walk counted what it walked (" .. tostring(counted) .. ")",
		counted ~= nil and counted > 200)
	-- Every node it may read, and it is ONE command: a walk that needed two passes
	-- would be a `find /` that a player could never finish.
	note("find over the disk", walk, " (" .. nodes .. " nodes, " .. tostring(counted) .. " found)")

	-- The same walk with no test on it at all, which is the most output one
	-- command on this machine can produce: it trickles at the screen's own rate
	-- and does not blow the console.
	local machine2, state2, console2 = newMachine()
	for depth = 1, 8 do
		local p = "/home/admin"
		for k = 1, depth do p = p .. "/d" end
		CeroSecOS.createNode(state2, root, p, CeroSecOS.newDir("admin", 755), 100)
		for f = 1, 20 do
			CeroSecOS.writeFile(state2, root, p .. "/f" .. f, "x", false, 100)
		end
	end
	typeLine(system, machine2, state2, console2, "find /home")
	local flood = drive(machine2, PASSES, CeroSec.JOB_PASS_MS)
	flat("find at the glass", flood)
	timely("find at the glass", flood)
	check("the console still holds only its hundred lines",
		#console2.lines <= CeroSec.CONSOLE_MAX)
	note("find at the glass", flood)
end

-- 22b1. find -exec, which is the one command that runs other commands.
--
-- Every exec is a command's worth of work -- a PATH walk, a file read, a file
-- written -- and a command that ran sixty of them in one call would overspend the
-- pass sixty times over. The whole step machine exists to stop that, and the
-- invariant at the head of this file holds every call to "the budget and one
-- command": so find does FIND_EXEC_TURN of them and hands the machine back,
-- keeping where it had got to in the frame's own carry, exactly as `sort` does
-- while it reads a pipe.
--
-- What this drives is a loop of the dearest legal line there is: a find whose
-- every match runs a command, over a tree of a hundred of them, for a thousand
-- passes. It has to stay flat, stay under the wall-clock ceiling, and -- the
-- point -- never spend more in one call than a pass may.
do
	local machine, state, console = newMachine()
	local root = CeroSecOS.rootSession()
	CeroSecOS.createNode(state, root, "/home/admin/tree",
		CeroSecOS.newDir("admin", 755), 100)
	local matches = 0
	for i = 1, 100 do
		if CeroSecOS.writeFile(state, root, "/home/admin/tree/f" .. i .. ".log",
				"x", false, 100) == nil then
			break
		end
		matches = matches + 1
	end
	check("the tree holds a hundred matches (" .. matches .. ")", matches >= 64)
	put(state, "/home/admin/sweep.sh",
		"while true; do find /home/admin/tree -name '*.log' -exec chmod 644 {} ';' ; done\n")

	typeLine(system, machine, state, console, "sh /home/admin/sweep.sh")
	local swept = drive(machine, PASSES, CeroSec.JOB_PASS_MS)
	-- flat() is what says the call never went past the budget by more than one
	-- command, on top of the invariant every jobStep call is held to.
	flat("find -exec in a loop", swept)
	timely("find -exec in a loop", swept)
	-- And it really ran them: a sweep that refused to start would be flat too.
	local mode = CeroSecOS.getNode(state, root, "/home/admin/tree/f1.log").mode
	eq("the exec'd command really ran", mode, 644)
	note("find -exec in a loop", swept, " (" .. matches .. " matches a sweep)")

	-- The gathered form beside it: the same sweep, FIND_EXEC_BATCH names to a
	-- command, which is two turns instead of a hundred.
	local machine2, state2, console2 = newMachine()
	CeroSecOS.createNode(state2, root, "/home/admin/tree",
		CeroSecOS.newDir("admin", 755), 100)
	local many = 0
	for i = 1, 100 do
		if CeroSecOS.writeFile(state2, root, "/home/admin/tree/f" .. i .. ".log",
				"x", false, 100) == nil then
			break
		end
		many = many + 1
	end
	put(state2, "/home/admin/gather.sh",
		"while true; do find /home/admin/tree -name '*.log' -exec chmod 644 {} + ; done\n")
	typeLine(system, machine2, state2, console2, "sh /home/admin/gather.sh")
	local gathered = drive(machine2, PASSES, CeroSec.JOB_PASS_MS)
	flat("find -exec gathered", gathered)
	timely("find -exec gathered", gathered)
	local batches = math.ceil(many / CeroSecOS.FIND_EXEC_BATCH)
	check("a gathered sweep of " .. many .. " names is " .. batches ..
		" commands and not " .. many, batches * 4 < many)
	note("find -exec gathered", gathered,
		" (" .. many .. " matches, " .. batches .. " to a sweep)")
end

-- 22b2. tar, which reads a whole tree and writes it as one file.
--
-- The archive is a FILE, so what tar can be asked to do is bounded by the disk
-- twice over: it cannot read more than 64K and it cannot write more than the 4096
-- bytes a file holds. What this drives is the dearest legal `tar cf` there is --
-- a home filled until the disk refuses another byte -- in a loop, for a thousand
-- passes. One command, and it has to stay one: a walk that needed two passes
-- would be a `tar` a player could never finish.
do
	local machine, state, console = newMachine()
	local root = CeroSecOS.rootSession()
	-- A home as big as the disk will take, in files as big as a file gets: what a
	-- survivor who has been living on the machine for a week has.
	local made, bytes = 0, 0
	for i = 1, 64 do
		local text = string.rep("x", 900)
		if CeroSecOS.writeFile(state, root, "/home/admin/f" .. i .. ".txt", text,
				false, 100) == nil then
			break
		end
		made = made + 1
		bytes = bytes + #text
	end
	local used = select(2, CeroSecOS.usage(state))
	check("the home really is most of the disk (" .. used .. " of "
		.. CeroSecOS.MAX_TOTAL_BYTES .. " bytes in " .. made .. " files)",
		bytes > CeroSecOS.MAX_TOTAL_BYTES / 4)
	put(state, "/home/admin/back.sh",
		"while true; do tar cf /home/admin/home.tar /home/admin; done\n")

	typeLine(system, machine, state, console, "sh /home/admin/back.sh")
	local backed = drive(machine, PASSES, CeroSec.JOB_PASS_MS)
	flat("tar of a full home", backed)
	timely("tar of a full home", backed)
	-- It is the DISK that refuses it and not tar: an archive is a file, and the
	-- whole home does not fit in one. The refusal is the point -- the walk happened,
	-- every byte of it, and the write was weighed like any other.
	local refused = false
	for i = 1, #console.lines do
		if string.find(console.lines[i], "file too large", 1, true) ~= nil then
			refused = true
		end
	end
	check("a home bigger than a file is refused by the disk, not by tar", refused)
	note("tar of a full home", backed, " (" .. made .. " files, " .. bytes .. " bytes)")

	-- And the archive that DOES fit, in a loop: the same walk, and a write of
	-- nearly a whole file every pass it gets.
	local machine2, state2, console2 = newMachine()
	CeroSecOS.createNode(state2, root, "/home/admin/keep",
		CeroSecOS.newDir("admin", 755), 100)
	local kept = 0
	for i = 1, 20 do
		if CeroSecOS.writeFile(state2, root, "/home/admin/keep/f" .. i .. ".txt",
				string.rep("y", 100), false, 100) == nil then
			break
		end
		kept = kept + 1
	end
	put(state2, "/home/admin/back.sh",
		"while true; do tar cf /home/admin/keep.tar /home/admin/keep; done\n")
	typeLine(system, machine2, state2, console2, "sh /home/admin/back.sh")
	local wrote = drive(machine2, PASSES, CeroSec.JOB_PASS_MS)
	flat("tar of a home that fits", wrote)
	timely("tar of a home that fits", wrote)
	local archive = CeroSecOS.getNode(state2, root, "/home/admin/keep.tar")
	check("and the archive is there, weighing what it holds (" ..
		#(archive and archive.data or "") .. " bytes for " .. kept .. " files)",
		archive ~= nil and #archive.data > kept * 100)
	note("tar of a home that fits", wrote, " (" .. kept .. " files an archive)")
end

-- 22c. The per-character filters, on the widest line a file can hold.
--
-- `cut -c` and `tr` walk every byte of every line, and a line on this machine may
-- be a whole file: four kilobytes on one row. Both of them built their answer with
-- `out = out .. c`, which is a new string per character -- measured at 4.2 ms for
-- one `cut -c 1-4096`, the whole of a pass's wall-clock budget spent by ONE
-- command, and a loop around it was a way to make a server slow. They build a
-- table and join it once now, and this is the bench that says so: a loop that does
-- nothing but that, for a thousand passes.
do
	local machine, state, console = newMachine()
	put(state, "/home/admin/wide", string.rep("abcdefgh", 512))
	put(state, "/home/admin/grind.sh",
		"while true; do cut -c 1-4096 /home/admin/wide > /dev/null; done\n")

	typeLine(system, machine, state, console, "sh /home/admin/grind.sh")
	local ground = drive(machine, PASSES, CeroSec.JOB_PASS_MS)
	flat("cut over a maximal line", ground)
	timely("cut over a maximal line", ground)
	note("cut, 4096 cols in a loop", ground)

	local machine2, state2, console2 = newMachine()
	put(state2, "/home/admin/wide", string.rep("abcdefgh", 512))
	put(state2, "/home/admin/grind.sh",
		"while true; do cat /home/admin/wide | tr a-z A-Z > /dev/null; done\n")
	typeLine(system, machine2, state2, console2, "sh /home/admin/grind.sh")
	local translated = drive(machine2, PASSES, CeroSec.JOB_PASS_MS)
	flat("tr over a maximal line", translated)
	timely("tr over a maximal line", translated)
	note("tr, 4096 cols in a loop", translated)
end

--
-- 22d. grep with a PATTERN, on the widest line a file can hold (debts 2).
--
-- A plain substring is one C call whatever the file is; a basic regular expression
-- is a walk of every byte of every line for every piece of the pattern. Measured on
-- one four-kilobyte line: five milliseconds for an honest pattern, twenty-two for
-- the dearest one the piece ceiling allows -- against a per-pass budget of four.
--
-- So grep hands the shell what its walk cost and the shell charges it in steps
-- (CeroSecOS.BRE_STEPS_PER), and the pass DEBT is what turns that into an average
-- the machine can afford: one dear command may still overspend a pass, which is the
-- bargain the debt was written for, and the next passes are that much shorter. What
-- this bench holds is the average and the flatness -- and that the loop still gets
-- somewhere, because a charge nobody can pay would be a grep that never runs.
--
do
	local machine, state, console = newMachine()
	put(state, "/home/admin/wide", string.rep("abcdefgh", 512))
	put(state, "/home/admin/grind.sh",
		"while true; do grep -c 'a.*q' /home/admin/wide > /dev/null; done\n")
	local job = typeLine(system, machine, state, console, "sh /home/admin/grind.sh")
	local hunted = drive(machine, PASSES, CeroSec.JOB_PASS_MS)
	flat("grep over a maximal line", hunted)
	timely("grep over a maximal line", hunted)
	check("and the loop went round (" .. job.steps .. " steps)", job.steps > PASSES)
	note("grep pattern, 4096 cols", hunted)

	-- The dearest pattern the ceiling allows, in the same loop. This is the one a
	-- crafted line would use, and what makes it affordable is the charge and not the
	-- matcher: without it the average pass is five times the budget.
	local machine2, state2, console2 = newMachine()
	put(state2, "/home/admin/wide", string.rep("a", 4096))
	put(state2, "/home/admin/grind.sh",
		"while true; do grep -c '" .. string.rep("a*", 15) ..
		"q' /home/admin/wide > /dev/null; done\n")
	local job2 = typeLine(system, machine2, state2, console2, "sh /home/admin/grind.sh")
	local crafted = drive(machine2, PASSES, CeroSec.JOB_PASS_MS)
	flat("the dearest pattern", crafted)
	timely("the dearest pattern", crafted)
	note("grep worst pattern", crafted)
	check("and it is still running (" .. job2.steps .. " steps)",
		not CeroSecOS.jobIsOver(job2))
end

--
-- 26. THE COUNTY: the minute sweep, and the windows open on one machine
--
-- Every bench above is about one player's script on one machine. These two are
-- about the other axis, which is the one a server operator feels: gos_cerosec.bin
-- holds EVERY computer in Knox County -- nine thousand five hundred buildings'
-- worth, all of them in memory whether their chunks are loaded or not -- and two
-- pieces of this mod used to scale with that number instead of with what is
-- actually happening.
--
-- Measured here before the change, at 300 machines with 40 of them on, under
-- lua5.1: the power check cost 25 ms a call and cron's minute 48 ms, every game
-- minute, on the main thread, and 580 ms on the first minute of a fresh county.
-- Almost all of it was spent on machines that are DARK, which have nothing to
-- answer: no power question, no window, no /dev, no crontab.
--
-- WHAT IS ASSERTED IS THE NUMBER OF MACHINES VISITED, and the milliseconds are
-- the second assertion and not the first. A timing says as much about this box as
-- about the code -- which is what the calibration at the head of this file is for
-- -- while "the sweep touched forty machines and not three hundred" is a fact
-- about the sweep. Both are here; the count is the one that cannot drift.
--
do
	local N, ON, CRON = 300, 40, 10
	local LOADED = 60
	-- The world content off, and put back at the end of the block: what a machine
	-- comes up carrying is four other rungs' worth of behaviour and this block is
	-- about the cost of the sweep. A world with no sandbox group at all reads as
	-- prefilling ON (CeroSecContent.enabled fails open on the option, closed on the
	-- hardware), so it is said here rather than left to the file's other benches.
	local hadSandbox = _G.SandboxVars
	_G.SandboxVars = { CeroSec = { PrefilledMachines = false, HardwareRequired = false } }

	-- The engine's own doors into the system, which is how the machines get in:
	-- newLuaObject is what SGlobalObjectSystem:initLuaObjects calls for every
	-- object in the save file, with the saved fields already in the table. So a
	-- county that was left running is a county of modData tables with `on` in
	-- them, exactly as the file on disk has it.
	local system = SCeroSecSystem:new()
	local objects = {}
	system.getLuaObjectCount = function() return #objects end
	-- Counted: this is the county walk's own door, and a sweep that goes through it
	-- is a sweep with no index (26a).
	local byIndex = 0
	system.getLuaObjectByIndex = function(_, i)
		byIndex = byIndex + 1
		return objects[i]
	end
	system.getLuaObjectAt = function(_, x, y, z)
		for i = 1, #objects do
			local o = objects[i]
			if o.x == x and o.y == y and o.z == z then return o end
		end
		return nil
	end
	system.getIsoObjectAt = function() return nil end
	system.newLuaObjectOnClient = function() end
	local answers = {}
	system.reply = function(_, _, command)
		answers[command] = (answers[command] or 0) + 1
	end
	system.seed = "0123456789abcdef"

	-- One machine, as the save file hands it over. `saved` is what is written in
	-- gos_cerosec.bin for it, and nothing else is: a machine that was left running
	-- carries `on` and a console, one that was not carries neither.
	local function place(i, saved, forceLoaded)
		local x, y, z = i, 1, 0
		-- The tile itself, with the modData the mirror is written into: a machine
		-- that runs a job mirrors its state onto the object (SCeroSecObject:mirrorOS).
		local iso = { __class = "IsoObject", modData = {} }
		iso.getSpriteName = function() return CeroSec.SPRITES_OFF["S"] end
		iso.setSpriteFromName = function() end
		iso.transmitUpdatedSpriteToClients = function() end
		iso.hasModData = function() return true end
		iso.getModData = function() return iso.modData end
		iso.transmitModData = function() end
		local square = {
			getX = function() return x end,
			getY = function() return y end,
			getZ = function() return z end,
			getRoom = function() return nil end,
			getBuilding = function() return nil end,
			getObjects = function() return { size = function() return 0 end } end,
			getWorldObjects = function() return { size = function() return 0 end } end,
			getMovingObjects = function() return { size = function() return 0 end } end,
			haveElectricity = function() return true end,
			hasGridPower = function() return true end,
			playSound = function() end,
		}
		local globalObject = {
			getX = function() return x end,
			getY = function() return y end,
			getZ = function() return z end,
			getModData = function() return saved end,
		}
		local luaObject = system:newLuaObject(globalObject)
		-- Most of the county is not in the world: the server holds the disk and
		-- nobody is standing anywhere near the square. A minority answer isLoaded()
		-- -- and one machine is forced into the world, because the developer's own
		-- "Turn on" refuses a machine whose chunk is away and says so
		-- (CeroSecDebug.turnOnRefusal).
		local loaded = forceLoaded == true or i <= LOADED
		luaObject.getIsoObject = function() return loaded and iso or nil end
		luaObject.getSquare = function() return loaded and square or nil end
		luaObject.playSound = function() end
		luaObject.syncSprite = function() end
		luaObject.updateOnClient = function() end
		luaObject.hasPower = function() return true end
		objects[#objects + 1] = luaObject
		return luaObject
	end

	local function newSaved(on, name)
		local saved = { v = CeroSec.STATE_VERSION, facing = "S" }
		if not on then return saved end
		saved.on = true
		saved.os = CeroSecOS.newState(name)
		local console = CeroSec.newConsole()
		console.booted = true
		console.user = "admin"
		console.cwd = "/home/admin"
		saved.console = console
		return saved
	end

	local crontab = "* * * * * echo tick\n0 21 * * * echo lights\n"
	for i = 1, N do
		local on = i <= ON
		local saved = newSaved(on, "ksp" .. i)
		if on and i <= CRON then
			local done, reason = CeroSecOS.writeFile(saved.os, CeroSecOS.rootSession(),
				CeroSecOS.cronPath("admin"), crontab, false, 100)
			if done == nil then error("cannot write the crontab: " .. tostring(reason)) end
		end
		place(i, saved)
	end
	eq("three hundred machines in the county", system:getLuaObjectCount(), N)
	eq("and forty of them were left running", #system:onMachineList(), ON)

	--
	-- 26a. THE MINUTE SWEEP VISITS THE MACHINES THAT ARE ON, AND NO OTHERS
	--
	-- Counted at the two doors the sweep goes through per machine: the power
	-- decision, which is the object's own (SCeroSecObject:checkPower), and cron's
	-- pass. A machine that is off reaches neither, so the two counts ARE the number
	-- of machines each half of the sweep looked at.
	--
	local powerVisits, cronVisits = 0, 0
	local realCheckPower = SCeroSecObject.checkPower
	SCeroSecObject.checkPower = function(self)
		powerVisits = powerVisits + 1
		return realCheckPower(self)
	end
	local realCronPass = CeroSecJobs.cronPass
	CeroSecJobs.cronPass = function(sys, luaObject, now)
		cronVisits = cronVisits + 1
		return realCronPass(sys, luaObject, now)
	end

	local function nowMs() return os.clock() * 1000 end

	-- ONE CAVEAT, said plainly, because it is the difference between this rig and a
	-- real county: these three hundred machines stand in no building, so the one
	-- walk left in the sweep that IS the county's never runs here -- a machine
	-- without an address gets one from CeroSecNet.identify, and the lowest free
	-- number on its wire is worked out by walking every machine the server holds
	-- (freeNumber, in SCeroSecNet.lua). That is once in the life of each machine and
	-- it is what made the first minute of a fresh county cost 580 ms when this was
	-- measured. It is not what the index below is about and it is not fixed by it.
	_G.__minute = 1
	system:checkPower()
	system:checkCron()

	-- THE MINUTES A SERVER SPENDS ITS LIFE IN.
	powerVisits, cronVisits, byIndex = 0, 0, 0
	local worstMinute = 0
	local minutes = 2
	local at = nowMs()
	for m = 2, minutes + 1 do
		_G.__minute = m
		local before = nowMs()
		system:checkPower()
		system:checkCron()
		local cost = nowMs() - before
		if cost > worstMinute then worstMinute = cost end
	end
	local perMinute = (nowMs() - at) / minutes

	-- THE ASSERTION THIS BLOCK IS FOR, and it is a count and not a clock: the sweep
	-- never asks the system for a machine by index, which is the county walk's only
	-- door. Three hundred machines in the file, forty decided about.
	eq("the steady sweep never walks the county", byIndex, 0)
	eq("the power check visited the machines that are on and no others",
		powerVisits, ON * minutes)
	eq("and cron's minute visited the same ones", cronVisits, ON * minutes)

	-- AND THE MILLISECONDS, PER MACHINE THAT IS ON and not per minute, because that
	-- is what the cost is made of once the county is out of the walk -- and the
	-- honest measurement is worth writing down, because it is not where the index
	-- was expected to help. Each half of the sweep reads the machine's state, and
	-- the read used to go through the validator every time -- the gate that keeps a
	-- forged state out of the engine, which walks every node of the filesystem:
	-- 0.887 of the 0.894 ms one read cost, three reads to a game minute, 2.5 ms a
	-- running machine and 104 a minute here. The validator is now asked once per
	-- STATE and not once per read (SCeroSecObject:osState), which is what the
	-- numbers below are: 2.67, 3.30 and 3.24 ms a minute over three runs, 0.067 to
	-- 0.083 ms a running machine, worst single minute 4.39. The 260 DARK machines
	-- the walk used to visit cost about 0.014 ms each -- four field tests and no
	-- state -- so taking them out of the walk was worth 3 ms of the 105 at this
	-- scale. What it is really worth is that the number does not move when the
	-- county grows, which is the block below: gos_cerosec.bin holds nine thousand
	-- five hundred buildings' worth.
	--
	-- The ceiling is GENEROUS on purpose, like WALL_MS_PER_PASS at the head of this
	-- file: it is a floor under "the server is not being hurt" and not a performance
	-- target, and what it has to catch is the county coming back into the walk or the
	-- validator coming back onto the read path -- not a box that is also running a
	-- game. ONE against a measured 0.083, down from the eight it was when the same
	-- read cost 2.5: a ceiling comes down from a measurement and never up, and the
	-- memo breaking puts the read back at 2.5, which this refuses with room to
	-- spare. Measured on a machine at load average 4 to 6, so the true idle figure
	-- is lower than the numbers quoted, and the calibration scales the ceiling like
	-- every other one here. The number that cannot drift is the visit count above,
	-- and this one is second to it on purpose.
	local limit = ceiling(1) * ON
	check("a game minute over three hundred machines costs under " ..
		string.format("%.2f", limit) .. " ms (" .. string.format("%.3f", perMinute) ..
		" average, " .. string.format("%.3f", worstMinute) .. " worst, " ..
		string.format("%.3f", perMinute / ON) .. " a running machine)",
		perMinute < limit)
	report[#report + 1] = string.format(
		"  %-22s %6.2f ms/minute avg, %.2f worst, %d of %d machines visited",
		"county sweep", perMinute, worstMinute, powerVisits / minutes, N)

	-- AND IT DOES NOT GROW WITH THE COUNTY, which is the whole of what the index
	-- buys: the same forty running machines with seven hundred more dark ones behind
	-- them in the file. gos_cerosec.bin really is that shape -- every computer that
	-- has ever been switched on in Knox County is in it, loaded chunk or not, and a
	-- long-running server's file grows all session. At three hundred the county walk
	-- was worth only about three of the hundred milliseconds a minute costs; at a
	-- thousand it would be four times that, and at the county's own scale it is the
	-- sweep.
	for i = 1, 700 do place(N + 100 + i, newSaved(false, "dark" .. i)) end
	eq("a thousand machines in the county", system:getLuaObjectCount(), N + 700)
	powerVisits, cronVisits, byIndex = 0, 0, 0
	_G.__minute = 20
	local bigBefore = nowMs()
	system:checkPower()
	system:checkCron()
	local bigMs = nowMs() - bigBefore
	eq("the sweep over a thousand machines still visits forty", powerVisits, ON)
	eq("and still never walks the county", byIndex, 0)
	check("and the minute costs what it cost at three hundred (" ..
		string.format("%.2f", bigMs) .. " ms against " ..
		string.format("%.2f", perMinute) .. ")", bigMs < limit)
	report[#report + 1] = string.format(
		"  %-22s %6.2f ms/minute, %d of %d machines visited",
		"county of a thousand", bigMs, powerVisits, N + 700)

	--
	-- 26b. EVERY WAY A MACHINE COMES ON IS A WAY INTO THE INDEX
	--
	-- The index is written by the writers of `on` and by nobody else, so a path
	-- that switched a machine on without telling it would be a machine the sweep
	-- never visits again -- a crontab that stops running, and nothing in the log.
	-- Each path is walked here, and what is asserted is the INDEX and not the
	-- field: a bench that read `.on` back would be green on no index at all.
	--
	local function indexed(luaObject)
		local list = system:onMachineList()
		for i = 1, #list do
			if list[i] == luaObject then return true end
		end
		return false
	end

	do
		-- The one every player uses: the context menu, which is a `toggle` packet.
		local spare = place(N + 1, newSaved(false, "menu"), true)
		local player = {
			getPlayerNum = function() return 0 end,
			getOnlineID = function() return -1 end,
			isDead = function() return false end,
			playSoundLocal = function() end,
			getCurrentSquare = function() return { getZ = function() return 0 end } end,
			getX = function() return spare.x + 0.5 end,
			getY = function() return spare.y + 0.5 end,
		}
		check("a machine nobody switched on is not in the index", not indexed(spare))
		system:OnClientCommand("toggle", player, { x = spare.x, y = spare.y, z = spare.z })
		eq("the context menu switched it on", spare.on, true)
		check("and it is in the sweep's index", indexed(spare))
		system:OnClientCommand("toggle", player, { x = spare.x, y = spare.y, z = spare.z })
		eq("switched off again", spare.on, false)
		check("and out of the index", not indexed(spare))

		-- The developer's own button, which goes through the debug channel and the
		-- window's own refusal before it reaches turnOn.
		local hadFlag = CeroSec.DEV_DEBUG_MENU
		CeroSec.DEV_DEBUG_MENU = true
		system:OnClientCommand("debugact", player,
			{ x = spare.x, y = spare.y, z = spare.z, token = "t", act = "on" })
		CeroSec.DEV_DEBUG_MENU = hadFlag
		eq("the debug window switched it on", spare.on, true)
		check("and that path indexes it too", indexed(spare))

		-- A REBOOT, which is the one power cycle that comes back on its own: the
		-- machine goes down now and the scheduler brings it up three seconds later.
		system:reboot(spare)
		eq("a rebooting machine is down", spare.on, false)
		check("and out of the index while it is dark", not indexed(spare))
		_G.__now = _G.__now + CeroSec.REBOOT_DARK_MS + 1
		CeroSecJobs.checkReboot(system, spare, _G.__now)
		eq("and comes back up by itself", spare.on, true)
		check("and is in the index when it does", indexed(spare))

		-- A computer picked up and put down again: off, and out.
		local iso = { __class = "IsoObject", modData = {},
			getSpriteName = function() return CeroSec.SPRITES_OFF["S"] end,
			hasModData = function() return true end }
		iso.getModData = function() return iso.modData end
		iso.transmitModData = function() end
		spare:resetForPlacement(iso)
		eq("a computer put down out of somebody's hands is off", spare.on, false)
		check("and is not swept", not indexed(spare))

		-- And a machine LEAVING the system altogether, which is the engine's own
		-- hook: an entry pointing at a machine nothing holds would be swept for ever.
		spare.on = true
		spare:reindex()
		check("on again for the last case", indexed(spare))
		spare:aboutToRemoveFromSystem()
		check("a machine out of the system is out of the index", not indexed(spare))
		for i = #objects, 1, -1 do
			if objects[i] == spare then table.remove(objects, i) end
		end
	end

	--
	-- 26c. A FLOOD OF `open` PACKETS FROM ONE PLAYER
	--
	-- The watcher table is keyed on the token the CLIENT picked, so five thousand
	-- opens with a fresh token each used to leave five thousand permanent entries
	-- on that machine -- server memory that is never given back, and one
	-- sendServerCommand per entry on every later screen of the machine, paid by
	-- whoever types at it next. One live window per player per machine, and eight
	-- per machine whatever the online ids say (SCeroSecObject.WATCHERS_MAX).
	--
	do
		local target = objects[1]
		local function playerAt(id)
			return {
				getPlayerNum = function() return 0 end,
				getOnlineID = function() return id end,
				isDead = function() return false end,
				playSoundLocal = function() end,
				getCurrentSquare = function() return { getZ = function() return 0 end } end,
				getX = function() return target.x + 0.5 end,
				getY = function() return target.y + 0.5 end,
			}
		end
		local one = playerAt(-11)
		local FLOOD = 5000
		answers = {}
		local before = nowMs()
		for i = 1, FLOOD do
			system:OnClientCommand("open", one,
				{ x = target.x, y = target.y, z = target.z, token = "f" .. i .. "-" .. ZombRand(9) })
		end
		local floodMs = nowMs() - before
		eq("five thousand opens from one player leave one window",
			target:watcherCount(), 1)
		eq("and every window they replaced was told so", answers["closed"] or 0, FLOOD - 1)

		-- WHAT IT COSTS EVERYBODY ELSE, which is the whole of the defect: a screen
		-- on that machine is one answer per window open on it.
		answers = {}
		system:pushScreen(target, target:osState(), target:consoleState())
		eq("a screen after the flood is one answer", answers["screen"] or 0, 1)

		-- NINE PLAYERS AT ONE KEYBOARD, which no room holds and a forged online id
		-- costs nothing to invent.
		answers = {}
		for i = 1, 9 do
			system:OnClientCommand("open", playerAt(-100 - i),
				{ x = target.x, y = target.y, z = target.z, token = "crowd" .. i })
		end
		eq("nine players leave eight windows", target:watcherCount(),
			SCeroSecObject.WATCHERS_MAX)
		local oldest = false
		for _, watcher in pairs(target.watchers) do
			if watcher.token == "crowd1" then oldest = true end
		end
		check("and the one that went is the oldest of them", not oldest)
		answers = {}
		system:pushScreen(target, target:osState(), target:consoleState())
		eq("and a screen costs eight answers and never more",
			answers["screen"] or 0, SCeroSecObject.WATCHERS_MAX)

		-- And the sweep is no dearer for having been flooded.
		answers = {}
		powerVisits = 0
		local sweepBefore = nowMs()
		_G.__minute = 30
		system:checkPower()
		system:checkCron()
		local after = nowMs() - sweepBefore
		eq("the flooded county still visits the machines that are on",
			powerVisits, ON)
		check("and a minute after the flood costs no more than any other (" ..
			string.format("%.3f", after) .. " ms against " ..
			string.format("%.2f", limit) .. ")", after < limit)
		report[#report + 1] = string.format(
			"  %-22s %6.3f ms for %d opens, %d watcher(s) left",
			"5000 open packets", floodMs, FLOOD, target:watcherCount())
	end

	SCeroSecObject.checkPower = realCheckPower
	CeroSecJobs.cronPass = realCronPass
	_G.SandboxVars = hadSandbox
end

check("no call ever went past its budget by more than one command (" .. worstOver .. ")",
	worstOver < CeroSecOS.STEP_COST_COMMAND)
check("and over every pass of every bench the debt was repaid (" .. totalSpent ..
	" spent of " .. totalAsked .. " asked)", totalSpent <= totalAsked)

print("hostile_test: " .. count .. " checks passed")
for i = 1, #report do print(report[i]) end
