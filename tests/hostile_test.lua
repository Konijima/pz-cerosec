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
--     lua5.1 on an ordinary machine.
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
	"42/media/lua/shared/CeroSec/OS/CeroSecOSFS.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSPath.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSScript.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSShell.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSState.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSSystem.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSUsers.lua",
	"42/media/lua/shared/CeroSec/OS/CeroSecOSVM.lua",
	"42/media/lua/server/CeroSec/SCeroSecJobs.lua",
}
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
local system = {}
function system:execEnv(luaObject, state)
	return { now = 740000000, nowMs = _G.__now }
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

-- What a pass may cost in real time. Generous on purpose: this is a floor
-- under "the server is not being hurt", not a performance target, and a bench
-- machine under load must not turn it red. A pass is a tenth of a second of
-- game time, so anything under a millisecond is three orders of magnitude of
-- room.
local WALL_MS_PER_PASS = 4.0

local function timely(what, result)
	check(what .. ": a pass costs under " .. WALL_MS_PER_PASS .. " ms of real time (" ..
		string.format("%.3f", result.msPerPass) .. ")", result.msPerPass < WALL_MS_PER_PASS)
end

local report = {}
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
	check("a pass over six busy machines costs under " .. WALL_MS_PER_PASS .. " ms (" ..
		string.format("%.3f", msPerPass) .. ")", msPerPass < WALL_MS_PER_PASS)
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
	check("and the whole bench holds well under a megabyte (" ..
		string.format("%.0f", late) .. "K)", late < 1024)
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

check("no call ever went past its budget by more than one command (" .. worstOver .. ")",
	worstOver < CeroSecOS.STEP_COST_COMMAND)
check("and over every pass of every bench the debt was repaid (" .. totalSpent ..
	" spent of " .. totalAsked .. " asked)", totalSpent <= totalAsked)

print("hostile_test: " .. count .. " checks passed")
for i = 1, #report do print(report[i]) end
