--
-- CeroSec OS core: the step machine that runs a script.
--
-- The rule this whole file exists for: NO SCRIPT MAY LAG OR CRASH A SERVER.
-- A player writes `while true; do echo x; done` on the first day he finds a
-- computer, and the machine has to survive it, stay answerable, and keep every
-- other machine in Knox County answerable too.
--
-- So a running script is not a Lua loop. It is a JOB: a plain table holding
-- the parsed program, a stack of frames, its variables and its pending output.
-- CeroSecOS.jobStep(state, job, env, budget) walks it for at most `budget`
-- steps and returns; the scheduler on the server calls that ten times a second
-- with a budget it can afford (see SCeroSecJobs.lua). Nothing here loops until
-- it is finished, nothing here waits, and nothing here holds a function -- a
-- job is data, all the way down, which is what makes it inspectable by `ps`,
-- killable by `kill` and impossible to hide anything executable inside.
--
-- What one step is
--
--   * one simple command           -- `echo hi`, `ls /bin`, `x=$((x+1))`
--   * one iteration of a loop      -- charged when the body is entered
--   * the steps of what $(...) runs, charged to the job that asked
--
-- Everything else -- pushing the frame for an `if`, popping a finished block,
-- expanding a word -- is free, and is bounded by the size of the program,
-- which is bounded by the 4096 bytes a file may hold. So the work one pass can
-- do is bounded whatever the script says.
--
-- Every wait is a continuation
--
--   read   -> status "waiting": the console puts the question up, and the
--             answer comes back through CeroSecOS.jobInput.
--   sleep  -> status "sleeping": a wake-up time in wall-clock milliseconds
--             (env.nowMs), costing nothing at all until it comes round.
--   a command that asks a question of its own (sudo, passwd) -> the same
--             "waiting", with the core's own continuation token carried on the
--             job. Nothing new was invented for it.
--
-- Never Lua
--
-- No load, no loadstring, no setfenv, no metatables. The arithmetic in $(( ))
-- is read by the reader below, digit by digit. That is deliberate and it is
-- checked by tests/kahlua-check.sh.
--

CeroSecOS = CeroSecOS or {}

CeroSecOS.commands = CeroSecOS.commands or {}
local commands = CeroSecOS.commands

--
-- The ceilings. Every one of them is a number a runaway script runs into
-- instead of running into the server.
--

-- Variables a job may hold, and the size of one value. A script that doubles a
-- string every time round the loop dies on the second of these in a dozen
-- iterations, having used a kilobyte.
CeroSecOS.MAX_VARS = 64
CeroSecOS.MAX_VAR_BYTES = 1024

-- Frames on the job's own stack. MAX_NEST (16) is what the parser allows a
-- script to nest; this is the walker's belt, because `sh` calling `sh` nests at
-- run time and the parser never saw it.
CeroSecOS.MAX_FRAMES = 64

-- How long a run of turns that spend NO step has to be before jobStep starts
-- reading where the job stands to see whether it is getting anywhere (the guard
-- at the end of the loop there). Free work between commands is ordinary and a
-- short run of it is every pass; a run longer than this is a pass that is not
-- getting anywhere, and reading it costs several free turns, which is why it is
-- not read on every one of them.
CeroSecOS.FREE_TURNS_BEFORE_READING = 32

-- How deep `sh` may call `sh`. A script that runs itself is the shortest
-- program there is that never ends, and this is where it stops.
CeroSecOS.SCRIPT_DEPTH_MAX = 8

-- Lines a job may have waiting to go on the screen before it is made to stop
-- and let them drain. This is what turns an output flood into a trickle: the
-- job is not killed, it simply does not run again until the screen has taken
-- what it already wrote.
CeroSecOS.JOB_OUT_MAX = 40

-- What a command that leaves the shell costs, in steps.
--
-- A step is a unit of COST and not of syntax. A builtin -- an assignment, an
-- echo, a test -- is a few microseconds of table work and is worth one; a
-- command in /bin walks the filesystem, builds columns and formats lines, and
-- was measured between twenty and five hundred microseconds a call (tests/
-- hostile_test.lua carries the numbers). Charging both the same would mean a
-- budget that is honest about a loop of arithmetic and eighty times out on a
-- loop of `ls`, and the budget is the whole protection.
--
-- Thirty-two is that ratio, rounded to the middle of the measured range rather
-- than to its worst case: `ls -l` on a full /bin is the dearest command there
-- is and is still undercharged by half, which is why the county budget is set
-- where it is and not by this number alone.
CeroSecOS.STEP_COST_COMMAND = 32

-- What one pipe may hold between two stages. A pipe on a real machine is a
-- buffer in the kernel and is bounded there too -- 4096 bytes on the Unix these
-- machines are from -- and what happens when it is full is not an error, it is
-- BACK-PRESSURE: the writer stops until the reader has taken something out. So
-- there is no "pipe full" message here and there is none on a real one either;
-- the stage on the left simply does not run again until there is room, exactly
-- as a job that has filled the screen does not run again until it has drained.
--
-- Lines as well as bytes, because this machine counts output in lines
-- everywhere else and a hundred of them is what the screen limiter is already
-- bounded by. A capture is NOT: what it hands back is a word, so bytes are the
-- only ceiling it has (see outLine).
CeroSecOS.PIPE_LINES = 100
CeroSecOS.PIPE_BYTES = 4096

-- A stage that writes into a pipe nobody is reading any more is killed, and a
-- shell reports a signal as 128 plus its number. SIGPIPE is 13, so `yes | head
-- -1` leaves the writer at 141 -- which is how sh has reported it since job
-- control, and why a flood into `head` ends instead of running forever.
CeroSecOS.SIGPIPE_STATUS = 141

--
-- Small helpers
--

-- The wall clock, in milliseconds, or nil when the caller handed none. Same
-- shape as CeroSecOS.clockOf: the engine has no clock of its own and reads
-- exactly one field for this one.
function CeroSecOS.nowMsOf(env)
	if type(env) ~= "table" then return nil end
	if type(env.nowMs) ~= "number" then return nil end
	return math.floor(env.nowMs)
end

-- The machine's job book, as the caller handed it over. An array of job
-- tables, or an empty one: a machine whose caller keeps no jobs is a machine
-- where `ps` is empty and `sh` has room.
function CeroSecOS.jobsOf(env)
	if type(env) ~= "table" or type(env.jobs) ~= "table" then return {} end
	return env.jobs
end

-- How many of them are still running. The prompt's own job is NOT one of them:
-- it is the shell, not a job the shell started, so `jobs` does not list it and
-- the four-job ceiling is still four SCRIPTS and not three plus the prompt.
--
-- exceptId, when given, is a job that is not counted either: the job ASKING. A
-- command that asks whether the machine has room -- `sh`, `wait` -- is asking
-- about the jobs in its way, and the job it is running in is not one of them. It
-- is an id and not the table, because a stage of a pipeline is a shell of its own
-- that shares its pipeline's id and is not in the book at all.
function CeroSecOS.liveJobs(jobs, exceptId)
	local live = 0
	for i = 1, #jobs do
		if jobs[i].id ~= exceptId and not jobs[i].interactive
				and not CeroSecOS.jobIsOver(jobs[i]) then
			live = live + 1
		end
	end
	return live
end

-- The job whose turn it is, left on the machine's env by the walker below.
--
-- A command is handed the env and never the job it runs in -- a command is not
-- allowed to reach into the shell -- and four of them nevertheless have to know
-- where they stand: `sh` and `wait` ask whether the machine has room for what
-- they would start, `env` asks what the ENVIRONMENT is, and `type` asks whether a
-- name is a FUNCTION the shell holds. All four are facts about the shell that
-- started them and about nothing else, and all four only read. This is the one
-- thing they may ask, and nil is the honest answer for a command run straight off
-- runArgs by a bench or by the server, with no job around it at all.
function CeroSecOS.jobOf(env)
	if type(env) ~= "table" or type(env.job) ~= "table" then return nil end
	return env.job
end

-- The id of it, or nil: what liveJobs above wants.
function CeroSecOS.askingId(env)
	local job = CeroSecOS.jobOf(env)
	if job == nil then return nil end
	return job.id
end

local function trim(s)
	return (string.gsub(string.gsub(s, "^[ \t\n]+", ""), "[ \t\n]+$", ""))
end

-- What a $( ) does to what it caught, and only that: sh(1) and POSIX.2
-- 2.6.3 remove trailing NEWLINES and nothing else -- not a leading one, not
-- a blank line in the middle, not a space or tab anywhere.
local function stripTrailingNewlines(s)
	return (string.gsub(s, "\n+$", ""))
end

--
-- Output
--
-- A job writes lines, and they wait in job.out until the scheduler drains them
-- onto the screen at a rate the network can carry. Inside a $(...) they go
-- into the capture buffer instead, which is what makes the substitution work
-- and what keeps its output off the glass.
--

-- Is what this job writes being caught by a $(...) instead of going to the
-- screen? The one test, asked in the three places that must agree about it.
--
-- Not when the call running now has a `>` of its own opened INSIDE the
-- capture: `x=$(g > f)` puts what g says in f and leaves x empty, because the
-- substitution's pipe is the command's standard output before the command's own
-- redirections are applied (POSIX.2 sh, Command Substitution and Redirection).
-- rdto.depth is how many captures were open when the file was (rdtoOf); a
-- capture opened after it -- `g() { y=$(echo in); }; g > f` -- still catches.
-- An rdto with no depth is one from before this rule and keeps the old order.
local function capturing(job)
	local caps = job.caps
	if caps == nil or #caps == 0 then return false end
	local rd = job.rdto
	if rd ~= nil and rd.depth ~= nil and rd.depth >= #caps then return false end
	return true
end

-- Is what this job writes going to a SCREEN? Asked by the shell before it runs a
-- command, because a command may print differently to a person than to another
-- command -- `ls` in columns at the glass, one name a line down a pipe, exactly
-- as every ls has done since isatty existed.
--
-- FOUR things take the screen away, and they are the four doors outLine writes
-- through: a $(...) catching the output, a pipe carrying it to another command,
-- cron carrying it to somebody's mail, and a FILE the shell opened for the script
-- this job is running (`job.rdto` -- see CeroSecOS.jobRun). A stage is the one
-- that needs care: a pipeline's LAST stage writes into a pipe too, and that pipe
-- is drained onto whatever is running the pipeline (drainTail), so its answer is
-- its parent's -- which is what `stage.screen` remembers, worked out where the
-- stages are made.
local function toScreen(job)
	if capturing(job) then return false end
	if job.mailTo ~= nil then return false end
	-- The file before the pipe: a stage is born with no rdto (newStage), so one
	-- it has is its own call's `>` -- `g > f | wc` -- and that call's standard
	-- output is the file, whatever the stage's is (POSIX.2 sh, Pipelines: the
	-- pipe is assigned before the command's own redirections).
	if job.rdto ~= nil then return false end
	if job.pipe ~= nil then return job.screen == true end
	return true
end

-- Stopping the job is what a capture does when it catches too much, and the
-- error is raised from inside the writing. Declared here, written below with
-- the rest of the job's ending.
local jobError

-- How big the open capture has become: the value it would hand back if it
-- closed now, which is its lines joined by "\n", plus whatever is held
-- part way through a line. Kept as a running total on the buffer rather than
-- measured, because it is asked on every write a captured job makes.
local function captureBytes(job, extra)
	local buf = job.caps[#job.caps]
	local bytes = buf.bytes or 0
	if #buf > 0 then bytes = bytes + 1 end
	return bytes + #(extra or "")
end

-- A $(...) that caught more than a word may hold. The ceiling is the WORD's
-- own: what a capture hands back is substituted into the line being built and
-- can never become anything else, so it meets MAX_VAR_BYTES one way or the
-- other -- and it has to meet it here, at the write, because a capture whose
-- program never ends never reaches the substitution to be measured there.
--
-- The captures are dropped BEFORE the error is raised. outLine sends a line to
-- the innermost open capture, so an error about a capture, raised while that
-- capture is still open, would go into it: a job that died in silence with a
-- blank screen.
local function captureTooLarge(job)
	job.caps = {}
	job.partial = ""
	jobError(job, "word too large")
end

-- Where a line about what went wrong goes, written below with errLine.
local routeErr

-- notFile is a line that is NOT output: a refusal, or something the machine has to
-- say about the job. It skips the redirect door below the way a refusal already
-- skips the pipe -- `ls /nope > f` puts the refusal on the screen and not in the
-- file, and a script whose standard output the shell pointed at a file is the same
-- rule one level up.
-- partial is true only when this line is the LAST byte the writer had and
-- carried no newline behind it (flushPartial, below) -- `printf a` at the end
-- of a job, not a line a command actually terminated. It is how the sink
-- (a file's own bytes, or the next stage of a pipe) learns whether to close
-- with "\n" of its own: unset on every other call, so any further output
-- clears it again and only the true last write of a target decides.
local function outLine(job, text, notFile, partial)
	-- A job that has ENDED writes nowhere. One door, because a dead process has
	-- one: whatever was still being handed over when it died is not something
	-- anybody is owed.
	--
	-- The line that made this a rule: a capture past the word ceiling. `x=$(cat
	-- big)` drops the captures, says "word too large" and stops the job -- and the
	-- rest of the lines `cat` had ALREADY handed over went on arriving, straight
	-- onto the glass, because the captures were gone and nothing was catching them
	-- any more. A file's contents spilled across the middle of the line being
	-- built, under a refusal that said the value was too big to keep. The refusal
	-- is the whole of the answer; the line is untouched.
	--
	-- Raised where the writing is, and not at the ceiling, because the ceiling is
	-- met in three places (outLine below, wrapPartial, and the substitution) and
	-- every one of them ends the job in the middle of somebody's output.
	if CeroSecOS.jobIsOver(job) then return end
	local caps = job.caps
	-- A $( ) catches the standard OUTPUT and nothing else: sh(1) substitutes
	-- "the standard output of the command", and the error of one still reaches
	-- the terminal -- `x=$(cat nosuch)` says so on the glass and leaves x empty.
	-- `2>&1` inside it is what puts an error in the word (routeErr below).
	if capturing(job) and not notFile then
		-- One ceiling, and it is the WORD's: what a capture hands back is
		-- substituted into the line being built, so bytes are the only thing that
		-- can be too many of. There was a hundred-LINE cap here as well, and the
		-- two did not agree with each other -- a capture past the bytes REFUSES
		-- with "word too large", a capture past the lines was silently cut short
		-- and handed back as if it were whole, which is the one answer a shell
		-- must never give. So `x=$(cat 150-short-lines)` is whole while it fits a
		-- word, and says so when it does not.
		local buf = caps[#caps]
		if captureBytes(job, text) > CeroSecOS.MAX_VAR_BYTES then
			captureTooLarge(job)
			return
		end
		if #buf > 0 then buf.bytes = (buf.bytes or 0) + 1 end
		buf.bytes = (buf.bytes or 0) + #text
		buf[#buf + 1] = text
		-- The same open-or-closed fact the file door keeps (to.open, below): a
		-- builtin's `> f` is caught here and written by linesToText, which
		-- ends the last line only when the writer did -- `printf a > f`.
		buf.open = partial == true
		return
	end
	-- The FILE the shell opened for the script this job is running. A redirect is
	-- not a screen either, so the line goes over whole -- uncut, unwrapped -- the
	-- way it goes down a pipe, and for the same reason: what reads it is a file and
	-- not a person. It is held in a buffer and written by the pass (jobFlush below),
	-- because outLine is handed a job and nothing else -- no filesystem, no clock --
	-- and a write needs both. What bounds the buffer is the SCREEN's own limiter,
	-- asked of it in jobStep: forty lines, then the job is made to stop and let them
	-- drain, exactly as a flood onto the glass is.
	--
	-- Ahead of the pipe, because in a stage the file IS the call's own: a stage is
	-- born with no rdto (newStage), and `g > f | wc -l` sends what g says into f
	-- and nothing down the pipe, so wc counts 0. POSIX.2 sh, Pipelines: the
	-- pipe is assigned to a command BEFORE the redirections that are part of
	-- it. A stage's buffer is written by pipeStep and jobFlush, which walk the
	-- stages for it.
	if job.rdto ~= nil and not notFile then
		local to = job.rdto
		-- `f >&2`: the standard output of what runs in this frame is a copy of the
		-- standard error it was called with, and goes where that went.
		if to.toErr then
			routeErr(job, text, to.spec)
			return
		end
		to.buf[#to.buf + 1] = text
		to.open = partial == true
		return
	end
	-- A stage of a pipeline writes into the pipe, and a pipe is not a screen:
	-- the line goes over whole, uncut and unwrapped, because the thing reading
	-- it is another command and not a person. The ceiling on how much may sit
	-- there is not here either -- it is back-pressure, asked before the stage is
	-- stepped at all (see pipeStep), the way the screen limiter is.
	if job.pipe ~= nil then
		local buf = job.pipe
		buf.lines[#buf.lines + 1] = text
		buf.bytes = buf.bytes + #text + 1
		buf.open = partial == true
		return
	end
	-- The screen's own rule, applied once, here: a job's line is at most sixty
	-- columns and carries no control byte, exactly like a command's.
	local fitted = CeroSecOS.fit({ text })
	for i = 1, #fitted do job.out[#job.out + 1] = fitted[i] end
end

-- A line about what went WRONG, which is not output. A pipeline is the one
-- place the difference shows: a stage's error belongs on the screen and not
-- down the pipe, exactly as `ls /nope > f` puts the refusal on the screen and
-- not in the file -- this machine has no second channel, so the rule is the
-- same one, written once, in both places.
--
-- `2>` is the one thing that moves it, and job.errRd is where a `2>` on the
-- command, function or script that is running now sent it (runSimple):
--   { path, who, buf }        a file, buffered and written like job.rdto
--   { out, depth, rdto }      `2>&1`: the standard output as it was when the
--                             line was read -- the captures under `depth` and
--                             the file `rdto` -- so `2>&1 > f` puts the error
--                             where the output WAS and not into f (sh(1):
--                             redirections are read left to right).
-- With none, a stage hands the line to the shell that runs the pipeline, whose
-- own `2>` then counts -- `f 2>/dev/null` silences a pipeline inside f -- and
-- the shell at the top puts it on the screen.
routeErr = function(job, text, spec)
	if spec ~= nil then
		if spec.buf ~= nil then
			spec.buf[#spec.buf + 1] = text
			return
		end
		local caps = job.caps
		local above = nil
		if #caps > spec.depth then
			above = {}
			for i = spec.depth + 1, #caps do above[#above + 1] = caps[i] end
			for i = #caps, spec.depth + 1, -1 do caps[i] = nil end
		end
		local rdto = job.rdto
		job.rdto = spec.rdto
		outLine(job, text)
		job.rdto = rdto
		if above ~= nil then
			for i = 1, #above do caps[#caps + 1] = above[i] end
		end
		return
	end
	if job.errTo ~= nil then
		routeErr(job.errTo, text, job.errTo.errRd)
		return
	end
	outLine(job, text, true)
end

local function errLine(job, text)
	routeErr(job, text, job.errRd)
end

-- The row a job is part way through, wrapped the way a screen sixty columns
-- wide wraps: the moment the held text fills a row, that row is finished and
-- goes out as a line. `echo -n` still leaves the cursor where it was, because a
-- prompt shorter than a row is what it always was.
--
-- This is also the only ceiling on job.partial, and it is the reason there is
-- one. The flood limiter counts LINES in job.out, so text with no newline in it
-- ever -- `while true; do printf %s x; done` -- reached no limiter at all: it
-- grew the held string a byte a turn, kilobyte after kilobyte, said nothing on
-- the screen, and was ended only by the five-minute cpu ceiling. Wrapping puts
-- it back on the same twenty-lines-a-second leash as every other flood and
-- bounds what is held to one row.
--
-- Only on the way to the screen. Inside a $(...) the text is not going to a
-- screen and must not be folded as if it were: the capture joins its lines
-- with "\n" (POSIX.2 2.6.3), so a wrap there would push newlines into the
-- middle of the captured value. What bounds it there is the capture's byte
-- ceiling, measured on what is held as well as on what has been caught --
-- the same flood written into a substitution instead of onto a screen must
-- meet a ceiling of its own, or it is the same unbounded string one door
-- along.
local function wrapPartial(job)
	if capturing(job) then
		if captureBytes(job, job.partial) > CeroSecOS.MAX_VAR_BYTES then
			captureTooLarge(job)
		end
		return
	end
	-- Into the FILE the shell opened for this script, the pipe's reasoning again: a
	-- file is not sixty columns wide, so a row's worth of text with no newline in
	-- it must not be folded as if it were -- `printf %s` into a file writes what it
	-- was given -- and it cannot be held for ever either. Same ceiling as the pipe,
	-- because the thing that is full is a buffer either way.
	if job.rdto ~= nil then
		while #job.partial >= CeroSecOS.PIPE_BYTES do
			outLine(job, string.sub(job.partial, 1, CeroSecOS.PIPE_BYTES))
			job.partial = string.sub(job.partial, CeroSecOS.PIPE_BYTES + 1)
		end
		return
	end
	-- Into a pipe, the same reasoning and a different ceiling. A pipe is not
	-- sixty columns wide, so text with no newline in it is not folded at the
	-- screen's width -- but it cannot be held for ever either, or `while true;
	-- do printf x; done | cat` is the unbounded string again with a pipe in
	-- front of it. A pipe's own buffer is what bounds it: once a row's worth of
	-- bytes is held with no newline, that much goes down the pipe, which is
	-- exactly what a full kernel buffer does to a writer that never ends a line.
	if job.pipe ~= nil then
		while #job.partial >= CeroSecOS.PIPE_BYTES do
			outLine(job, string.sub(job.partial, 1, CeroSecOS.PIPE_BYTES))
			job.partial = string.sub(job.partial, CeroSecOS.PIPE_BYTES + 1)
		end
		return
	end
	while #job.partial >= CeroSecOS.COLS do
		outLine(job, string.sub(job.partial, 1, CeroSecOS.COLS))
		job.partial = string.sub(job.partial, CeroSecOS.COLS + 1)
	end
end

-- Text with newlines in it, the way printf and echo write. Everything up to
-- the last newline becomes lines; what is after it waits, so `echo -n` really
-- does leave the cursor where it was.
local function writeText(job, text)
	local start = 1
	while true do
		local p = string.find(text, "\n", start, true)
		if p == nil then
			job.partial = (job.partial or "") .. string.sub(text, start)
			wrapPartial(job)
			return
		end
		outLine(job, (job.partial or "") .. string.sub(text, start, p - 1))
		job.partial = ""
		start = p + 1
	end
end

local function flushPartial(job)
	if job.partial ~= nil and job.partial ~= "" then
		-- partial=true: this line carries no newline behind it. It is the
		-- LAST thing this job wrote if nothing else follows, which is what
		-- lets the sink decide whether to close with a "\n" of its own.
		outLine(job, job.partial, nil, true)
	end
	job.partial = ""
end

-- A command's returned lines, same door a builtin's writeText uses. `lines`
-- may carry an `open` field (cat, and the /bin printf and echo doors): true
-- when its own last line had no newline behind it -- read straight off the
-- source, a file or a pipe that ended without one -- so a command whose
-- INPUT is unterminated hands the same fact to whoever it writes to,
-- exactly the way `printf a | cat; echo b` glues onto one line on a real sh.
local function writeLines(job, lines)
	if type(lines) ~= "table" then return end
	local n = #lines
	if n == 0 then return end
	-- The job's own last line may still be open -- `printf a; cat f` -- and
	-- then this command's first line is the REST of it, because a real one
	-- writes bytes onto the same standard output and nothing between: "aa".
	local first = 1
	if job.partial ~= nil and job.partial ~= "" then
		if n == 1 and lines.open == true then
			writeText(job, lines[1])
			return
		end
		writeText(job, lines[1] .. "\n")
		first = 2
	end
	if lines.open == true then
		for i = first, n - 1 do outLine(job, lines[i]) end
		-- The last line goes through writeText's own partial, which folds it
		-- at the pipe/file/screen width the same way any other unterminated
		-- text does, and leaves it open for whatever writes next.
		writeText(job, lines[n])
		return
	end
	for i = first, n do outLine(job, lines[i]) end
end

-- The same, for the lines of a command that FAILED: they go where an error
-- goes. Outside a pipeline that is the very same place, which is why every
-- other caller can keep using writeLines.
local function errLines(job, lines)
	if type(lines) ~= "table" then return end
	if #lines > 0 then flushPartial(job) end
	for i = 1, #lines do errLine(job, lines[i]) end
end

--
-- Variables, and which of them are the ENVIRONMENT
--
-- A shell has two things and they are not the same thing: the variables it
-- holds, and the environment it hands to a program it runs. `x=5` makes a
-- variable of its own; `export x` puts that name in the environment; and a
-- program started from there is handed the environment and never the rest of
-- them. That is sh's oldest distinction and the reason `export` exists at all.
--
-- So a job carries two tables. job.vars is name -> value, as it always was;
-- job.exported is the SET of names that are in the environment. Both travel the
-- way the prompt's variables travel -- by reference, so `export PATH` on one
-- line is still in force on the next -- and both are copied for a subshell.
--
-- job.exported may be nil, and nil is not the empty set: it means a caller that
-- said nothing about the environment, and the honest reading of that is that
-- everything it holds is in it. That is what a machine saved before this build
-- has to read as, because before it a script shared the prompt's variables
-- whole; and it is what a bench calling promptJob with a bare table is. A fresh
-- login says which ones out loud (CeroSecOS.loginExported).
--

local function getVar(job, name)
	local v = job.vars[name]
	if v == nil then return "" end
	return v
end

-- IFS, POSIX.2 2.6.5: unset reads as space, tab, newline; getVar cannot say
-- that (it turns nil into ""), so field splitting reads job.vars.IFS itself.
local IFS_DEFAULT = " \t\n"
local function getIFS(job)
	local v = job.vars.IFS
	if v == nil then return IFS_DEFAULT end
	return v
end

-- "$*"'s join character (POSIX.2 2.5.3): the first byte of IFS, a blank when
-- IFS is unset, none at all when it is set empty.
local function ifsJoinChar(job)
	local v = job.vars.IFS
	if v == nil then return " " end
	if v == "" then return "" end
	return string.sub(v, 1, 1)
end

-- Splits an IFS value into two membership tables: the space/tab/newline
-- bytes it holds (IFS whitespace, collapsed and ignored at the ends) and
-- every other byte it holds (an IFS delimiter, which delimits on its own
-- even next to another one). A character loop over the value, never a
-- pattern built from it -- IFS is the player's (tests/pattern-check.lua).
local function ifsClasses(ifs)
	local ws, delim = {}, {}
	for i = 1, #ifs do
		local c = string.sub(ifs, i, i)
		if c == " " or c == "\t" or c == "\n" then ws[c] = true
		else delim[c] = true end
	end
	return ws, delim
end

-- nil, or the reason it may not be set. The two ceilings live here and nowhere
-- else, so every road into a variable meets them.
local function setVar(job, name, value)
	if #value > CeroSecOS.MAX_VAR_BYTES then return "variable too large" end
	-- PATH is the one variable whose LENGTH is a cost to everybody: every command
	-- the shell runs walks it, so the ceiling on how many directories it may name
	-- is met here, where the value is set, the way every other ceiling on this
	-- machine is met where the thing is made.
	if name == "PATH" and #CeroSecOS.pathDirs(value) > CeroSecOS.MAX_PATH_DIRS then
		return "too many PATH entries"
	end
	if job.vars[name] == nil then
		if job.nvars >= CeroSecOS.MAX_VARS then return "too many variables" end
		job.nvars = job.nvars + 1
	end
	job.vars[name] = value
	return nil
end

-- Mark a name as being in the environment. nil, or the reason it may not be.
-- The set is made on demand, because a job that never exports anything is a job
-- whose environment is what it was handed.
--
-- Bounded by MAX_VARS like the variables themselves: a name may be marked
-- without being set, so the set is not bounded by the table beside it, and
-- `while true; do export ...; done` would otherwise be a string that grows for
-- ever one door along from the one that already meets this ceiling.
local function markExported(job, name)
	if job.exported == nil then
		-- The names it already holds were already in it -- that is what nil
		-- meant -- so they go in with this one, or an `export` would be a way of
		-- taking every other variable OUT of the environment.
		local set = {}
		for held, _ in pairs(job.vars) do set[held] = true end
		job.exported = set
	end
	if job.exported[name] ~= true then
		local n = 0
		for _, on in pairs(job.exported) do
			if on == true then n = n + 1 end
		end
		if n >= CeroSecOS.MAX_VARS then return "too many variables" end
	end
	job.exported[name] = true
	return nil
end

-- The environment a job hands a PROGRAM it runs: a new table with the exported
-- names in it and nothing else. What a child does with it is its own -- this is
-- a copy, and an assignment in a script never comes back.
function CeroSecOS.exportedVars(vars, exported)
	local out = {}
	if type(vars) ~= "table" then return out end
	for name, value in pairs(vars) do
		if exported == nil or exported[name] == true then out[name] = value end
	end
	return out
end

-- The same set, copied, for a job that is handed one: a child's `export` marks
-- the child's environment and not its parent's.
function CeroSecOS.copyExported(exported)
	if type(exported) ~= "table" then return nil end
	local out = {}
	for name, on in pairs(exported) do
		if on == true then out[name] = true end
	end
	return out
end

-- Every exported name it holds, sorted: what `env` prints and what `export`
-- with nothing after it lists. Sorted because pairs is not ordered and a
-- listing that came back in a different order every time could not be a page of
-- the manual -- ash walks its own hash table here, which is an order nothing
-- could print twice.
function CeroSecOS.envNames(vars, exported)
	local names = {}
	if type(vars) ~= "table" then return names end
	for name, _ in pairs(vars) do
		if exported == nil or exported[name] == true then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

--
-- Functions
--
-- A shell function is the shell's own, like a variable, and what the shell holds is
-- the SOURCE of it: `job.funcs` is name -> the text of the definition. The body is
-- read out of that text by the parser, once per job, and cached in `job.fprog` --
-- which is the job's alone and never travels anywhere, because a parsed program is
-- nested tables and nothing player-controlled is handed back out of a save file as
-- one. The console keeps the text (CeroSec.repairConsole bounds it exactly as it
-- bounds a variable's value), so `greet` still works after a reload.
--
-- job.funcs travels the way job.vars travels: BY REFERENCE for the prompt, so a
-- definition on one line is there on the next; a COPY for a subshell -- a stage, an
-- `&`, a $( ) -- because a fork inherits its parent's functions and what it defines
-- afterwards is its own; and NONE for a script, which is a new sh. `. file` is the
-- one that brings them in, being the shell reading a file into itself.

function CeroSecOS.copyFuncs(funcs)
	if type(funcs) ~= "table" then return nil end
	local out = {}
	for name, src in pairs(funcs) do
		if type(src) == "string" then out[name] = src end
	end
	return out
end

-- The body of one, parsed. nil plus the reason for a text that will not parse, which
-- can only be a console handed back with something in it that was never a function.
local function funcBody(job, name)
	if type(job.fprog) == "table" and job.fprog[name] ~= nil then return job.fprog[name] end
	local src = job.funcs[name]
	if type(src) ~= "string" then return nil, "not a function" end
	local prog, reason, where = CeroSecOS.parseScript(src)
	if prog == nil then return nil, CeroSecOS.scriptError(name, reason, where) end
	-- The definition parsed on its own is one statement, and that statement is the
	-- definition: what is wanted is the body inside it.
	local node = prog[1]
	if type(node) ~= "table" or node.k ~= "func" or type(node.body) ~= "table" then
		return nil, "not a function"
	end
	if job.fprog == nil then job.fprog = {} end
	job.fprog[name] = node.body
	return node.body
end

-- A definition carried out. nil, or the reason it may not be.
local function defineFunc(job, node)
	if type(node.src) ~= "string" or #node.src > CeroSecOS.MAX_FUNC_BYTES then
		return "function too large"
	end
	if job.funcs == nil then job.funcs = {} end
	if job.funcs[node.name] == nil then
		local n = 0
		for _, _ in pairs(job.funcs) do n = n + 1 end
		if n >= CeroSecOS.MAX_FUNCS then return "too many functions" end
	end
	job.funcs[node.name] = node.src
	-- Redefined: the body cached from the old text is not this one's.
	if type(job.fprog) == "table" then job.fprog[node.name] = nil end
	return nil
end

-- Every function a shell holds, sorted: what `type` asks about and what a bench
-- counts. Sorted for the reason envNames is -- pairs is not an order.
function CeroSecOS.funcNames(funcs)
	local names = {}
	if type(funcs) ~= "table" then return names end
	for name, src in pairs(funcs) do
		if type(src) == "string" then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

--
-- The job
--

-- A COPY of a shell's variables, for something that starts AS a subshell of it:
-- a stage of a pipeline, or a statement behind an `&`. It begins with everything
-- its parent held -- PATH, HOME, whatever was set at the prompt -- which is what
-- a fork gives a child, and what it does with them afterwards is its own: `x=5`
-- in a background job leaves the shell that started it alone.
function CeroSecOS.copyVars(vars)
	local out = {}
	if type(vars) == "table" then
		for name, value in pairs(vars) do out[name] = value end
	end
	return out
end

-- opts: prog, args (args[1] is $1), name, cmd, session, id, bg, vars, exported,
-- funcs, status.
--
-- vars, when given, is taken BY REFERENCE and is the caller's to keep: it is
-- how the prompt has an environment that outlives one line. Anything that is a
-- subshell of another hands a COPY in (CeroSecOS.copyVars above), and what is
-- handed nothing at all -- a cron line -- starts with the default below, which
-- is cron's own trap and is the one place it is still right.
--
-- exported travels the same way and means the same thing it means on the job
-- (the head of the variables section): the set of names that are in the
-- ENVIRONMENT, or nil for a caller that said nothing, which reads as all of them.
function CeroSecOS.newJob(opts)
	local args = {}
	if type(opts.args) == "table" then
		for i = 1, #opts.args do args[i] = tostring(opts.args[i]) end
	end
	local session = opts.session or CeroSecOS.rootSession()
	local vars, nvars = opts.vars, 0
	local exported = opts.exported
	if type(exported) ~= "table" then exported = nil end
	if type(vars) ~= "table" then
		-- The initial environment of a shell nobody handed one: PATH, and the
		-- default at that. That is the CRON line's case -- cron hands in the
		-- account's own loginVars and nothing of whatever was typed at a prompt,
		-- which is the classic cron trap and is why the manual says to write the
		-- whole path in a crontab line. A script run by hand is handed a copy of
		-- its parent's ENVIRONMENT instead, and a subshell -- a stage, an `&` -- a
		-- copy of everything its parent held.
		vars = { PATH = CeroSecOS.DEFAULT_PATH }
		nvars = 1
		-- And it is an environment and not a shell variable: a machine with no
		-- PATH in front of a cron line could not run a command at all.
		if exported == nil then exported = { PATH = true } end
	else
		for _, _ in pairs(vars) do nvars = nvars + 1 end
	end
	local status = 0
	if type(opts.status) == "number" then status = math.floor(opts.status) end
	return {
		id = opts.id or 1,
		-- What `ps` prints, and what the script calls itself in an error.
		name = opts.name or "sh",
		cmd = opts.cmd or opts.name or "sh",
		bg = opts.bg and true or false,
		-- $!: the id of the last job an `&` in this shell started, or nil.
		lastBg = type(opts.lastBg) == "number" and opts.lastBg or nil,
		prog = opts.prog,
		args = args,
		vars = vars,
		nvars = nvars,
		exported = exported,
		-- The shell's functions, by reference like the variables and for the same
		-- reason: a definition on one line is still there on the next.
		funcs = opts.funcs,
		-- A session of the job's OWN. `cd` inside a script moves the script and
		-- not the console it was started from, the way a real shell's child
		-- cannot move its parent.
		session = {
			user = session.user,
			cwd = session.cwd or "/",
			stamp = session.stamp,
			login = CeroSecOS.loginOf(session),
			stack = CeroSecOS.copyStack(session.stack),
			-- Which terminal the job is running on, and how many rlogins out it
			-- is. Both are facts about the SCREEN and not about the job, so they
			-- travel into it rather than being looked up: `who am i` in a script
			-- names the line the script was started from, and an rlogin inside a
			-- session is one hop further out than the session is.
			line = session.line,
			hops = session.hops,
		},
		frames = { { k = "block", prog = opts.prog, i = 1 } },
		caps = {},
		out = {},
		partial = "",
		status = status,
		steps = 0,
		state = "running",
		depth = 1,
		line = 1,
	}
end

local function finish(job, state)
	flushPartial(job)
	job.state = state
	job.frames = {}
	job.caps = {}
end

-- A script that went wrong: the file, the line, the reason. The job stops
-- where it stands, with status 2, the way a shell stops on a fatal error.
function jobError(job, reason)
	flushPartial(job)
	-- A typed line has no line number worth printing: it is line one of
	-- nothing, and "sh: line 1:" in front of every refusal would be a number
	-- that never says anything. A file -- a script, or ~/.profile -- has lines,
	-- and so does a script the typed line went on to run: past the first level
	-- the job is inside a file again (`sh spin.sh` at the prompt), and that
	-- file's name and line are what a player has to be told.
	if job.promptLine ~= nil and job.depth == 1 then
		errLine(job, "sh: " .. reason)
	else
		errLine(job, CeroSecOS.scriptError(job.name, reason, job.line))
	end
	job.status = 2
	finish(job, "error")
end

function CeroSecOS.killJob(job, reason)
	if job.state == "done" or job.state == "killed" or job.state == "error" then return false end
	-- A job killed in the middle of a dial has hung up, and the thing holding the
	-- line says what a hang-up sounds like. The word is the DIALLER's -- the
	-- command wrote it into the ring when it lifted the receiver -- so nothing here
	-- knows what a modem is; it says the line it was handed, through the job's own
	-- output door, and lets the line go.
	if type(job.ring) == "table" and job.ring.abort ~= nil then
		outLine(job, tostring(job.ring.abort))
	end
	job.ring = nil
	job.killReason = reason
	job.status = 130
	finish(job, "killed")
	return true
end

--
-- Frames
--

local function popFrame(job)
	local frames = job.frames
	local f = frames[#frames]
	if f == nil then return end
	frames[#frames] = nil
	if f.k == "capture" then
		flushPartial(job)
		local buf = job.caps[#job.caps]
		job.caps[#job.caps] = nil
		-- The lines it caught, joined back the way they came apart: outLine
		-- split the command's output at each newline, table.concat with "\n"
		-- puts them back, and only the newline(s) left at the very end are
		-- gone (sh(1), POSIX.2 2.6.3) -- a captured "a\n\nb\n" is "a\n\nb",
		-- the blank line kept and the run of trailing ones the only casualty.
		-- Splitting IT further, if this word is unquoted, is field
		-- splitting's job below, on IFS like any other expansion's result.
		job.capval = stripTrailingNewlines(table.concat(buf or {}, "\n"))
		job.hasCap = true
		-- And the shell it was a SUBSHELL of comes back with its own variables.
		-- POSIX.2: a command substitution is executed in a subshell environment,
		-- so `x=1; y=$(x=2; echo $x); echo $x` prints 1 on every sh there has ever
		-- been -- the 2 belonged to a process that is gone. It leaked here, because
		-- a capture is a frame on the very job that asked for it and the job has one
		-- table of variables.
		if f.oldVars ~= nil then
			job.vars = f.oldVars
			job.nvars = f.oldNvars
			-- nil is a value: a shell that never said which of its variables are the
			-- environment gets that back and not the set the subshell was handed.
			job.exported = f.oldExported
			-- The working directory is the subshell's too. `cd` inside a $(...) moved
			-- the shell that asked -- `echo $(cd /etc; pwd)` left the prompt standing
			-- in /etc -- and on a real machine it cannot: the chdir was the child's.
			-- Only the directory, because that is the whole of what `cd` moves; `su`
			-- pushes on the CONSOLE's stack and is the console's to pop.
			job.session.cwd = f.oldCwd
			-- And the functions: a subshell inherits them and what it defines is its
			-- own, exactly as a stage of a pipeline's are.
			job.funcs = f.oldFuncs
		end
	elseif f.deep or f.func then
		-- A file -- or a FUNCTION -- that has finished: the shell that ran it comes
		-- back exactly as it was. `deep` and not "it kept some arguments", because the
		-- dot command keeps the caller's arguments AND its variables and is still one
		-- level deeper -- a file that dots itself has to meet the depth ceiling. A
		-- function is not one level deeper, because it is not another shell: what
		-- bounds a recursion is the frame stack (MAX_FRAMES), the way it bounds
		-- everything else the walker pushes.
		if f.deep then job.depth = job.depth - 1 end
		-- The name is put back whichever kind of file it was: a refusal inside a
		-- dotted file names THAT file and the line in it, because that is where
		-- the line is, and the shell that dotted it is itself again afterwards.
		if f.oldName ~= nil then job.name = f.oldName end
		if f.oldArgs ~= nil then job.args = f.oldArgs end
		if f.oldVars ~= nil then
			job.vars = f.oldVars
			job.nvars = f.oldNvars
			-- nil is a value here: a shell that said nothing about its environment
			-- gets that back, and not the set the child was handed.
			job.exported = f.oldExported
		end
		if f.hadFuncs then
			job.funcs = f.oldFuncs
			-- The bodies cached from the child's own definitions go with them.
			job.fprog = f.oldFprog
		end
		-- And the file the shell had opened for it is closed: what the script wrote
		-- and nobody has written yet goes on a queue, IN ORDER, before the target
		-- changes back -- flushing it here is not possible, because popFrame has no
		-- filesystem and no clock to write with. The queue is emptied before the
		-- next step (flushDone, at the top of stepOnce), so the command after this
		-- one finds the file whole, as it does after a real sh closed it.
		if f.hadRdto then
			-- The row it was part way through goes in the FILE, like the rest of what
			-- it wrote: the redirect is closed here, and a partial flushed afterwards
			-- would find the target gone and land on the glass instead. `printf aaa`
			-- with no newline in a redirected script printed on the screen and left an
			-- empty file, which is the whole of what this line is for.
			flushPartial(job)
			if job.rdto ~= nil then
				if job.rdDone == nil then job.rdDone = {} end
				job.rdDone[#job.rdDone + 1] = job.rdto
			end
			job.rdto = f.oldRdto
		end
		-- The `2>` of the call, closed the same way and onto the same queue.
		if f.hadErd then
			local e = job.errRd
			if e ~= nil and e.buf ~= nil then
				if job.rdDone == nil then job.rdDone = {} end
				job.rdDone[#job.rdDone + 1] = e
			end
			job.errRd = f.oldErd
		end
	end
end

-- true, or false after having failed the job.
local function pushFrame(job, frame)
	if #job.frames >= CeroSecOS.MAX_FRAMES then
		jobError(job, "too deeply nested")
		return false
	end
	job.frames[#job.frames + 1] = frame
	return true
end

--
-- Arithmetic, $(( ))
--
-- Read here, by hand, on integers. There is no eval on this machine and there
-- never will be: what a player types into a file is data, and the only thing
-- that ever looks at it is the reader below.
--

local function arithSkip(s, i)
	while i <= #s and string.find(string.sub(s, i, i), "^[ \t]") ~= nil do i = i + 1 end
	return i
end

local arithSum

-- What a piece of TEXT is worth in a sum: the whole number in it, and nought
-- when there is not one. Written once, because every expansion inside $(( ))
-- ends here -- a variable, an argument, ${name} -- and the rule an empty
-- variable is nought by is the rule an empty argument has to be nought by.
local function argNumber(text)
	local v = tonumber(text)
	if v == nil then return 0 end
	return math.floor(v)
end

-- A number, a variable, a parenthesised sum, or a unary minus.
local function arithUnit(job, s, i)
	i = arithSkip(s, i)
	local c = string.sub(s, i, i)
	if c == "-" then
		local v, j, err = arithUnit(job, s, i + 1)
		if err ~= nil then return nil, j, err end
		return -v, j
	end
	if c == "+" then return arithUnit(job, s, i + 1) end
	if c == "(" then
		local v, j, err = arithSum(job, s, i + 1)
		if err ~= nil then return nil, j, err end
		j = arithSkip(s, j)
		if string.sub(s, j, j) ~= ")" then return nil, j, "bad arithmetic" end
		return v, j + 1
	end
	-- A dollar in front of a name is allowed and means the same thing: inside
	-- $(( )) a bare name is already the variable.
	--
	-- And the dollars that are NOT names. A real sh expands the inside of $(( ))
	-- before it evaluates it -- POSIX.2 puts arithmetic expansion after parameter
	-- expansion and command substitution, so `$((5 % $1))` reaches the reader with
	-- the first argument already in it -- and a reader that only knew [A-Za-z_]
	-- answered "bad arithmetic" for every one of them. They are the same four the
	-- word reader knows (readDollar in CeroSecOSScript.lua), read the same way, so
	-- `$1` means one thing on this machine wherever it is written.
	if c == "$" then
		local nx = string.sub(s, i + 1, i + 1)
		if string.find(nx, "^[0-9]") ~= nil then
			-- One digit, like everywhere else here: $1..$9 are the arguments and
			-- $0 is what the script is called, which is a name and so is nought.
			local n = tonumber(nx)
			local text
			if n == 0 then text = job.name else text = job.args[n] or "" end
			return argNumber(text), i + 2
		end
		if nx == "#" then return #job.args, i + 2 end
		if nx == "?" then return math.floor(job.status), i + 2 end
		if nx == "$" then return math.floor(job.id), i + 2 end
		if nx == "!" then return argNumber(job.lastBg ~= nil and tostring(job.lastBg) or ""), i + 2 end
		if nx == "{" then
			local j = i + 2
			local name = ""
			while j <= #s and string.sub(s, j, j) ~= "}" do
				name = name .. string.sub(s, j, j)
				j = j + 1
			end
			if j > #s or not CeroSecOS.isVarName(name) then return nil, j, "bad arithmetic" end
			return argNumber(getVar(job, name)), j + 1
		end
		i = i + 1
	end
	if string.find(c, "^[0-9]") ~= nil then
		local j = i
		while j <= #s and string.find(string.sub(s, j, j), "^[0-9]") ~= nil do j = j + 1 end
		return tonumber(string.sub(s, i, j - 1)), j
	end
	if string.find(string.sub(s, i, i), "^[A-Za-z_]") ~= nil then
		local j = i
		while j <= #s and string.find(string.sub(s, j, j), "^[A-Za-z0-9_]") ~= nil do j = j + 1 end
		local name = string.sub(s, i, j - 1)
		return argNumber(getVar(job, name)), j
	end
	return nil, i, "bad arithmetic"
end

local function arithProduct(job, s, i)
	local left, j, err = arithUnit(job, s, i)
	if err ~= nil then return nil, j, err end
	while true do
		j = arithSkip(s, j)
		local c = string.sub(s, j, j)
		if c ~= "*" and c ~= "/" and c ~= "%" then return left, j end
		local right, k, rerr = arithUnit(job, s, j + 1)
		if rerr ~= nil then return nil, k, rerr end
		if c == "*" then
			left = left * right
		else
			if right == 0 then return nil, k, "divide by zero" end
			-- Truncated towards zero, the way C and every shell divide.
			local q = left / right
			if q < 0 then q = math.ceil(q) else q = math.floor(q) end
			if c == "/" then left = q else left = left - right * q end
		end
		j = k
	end
end

arithSum = function(job, s, i)
	local left, j, err = arithProduct(job, s, i)
	if err ~= nil then return nil, j, err end
	while true do
		j = arithSkip(s, j)
		local c = string.sub(s, j, j)
		if c ~= "+" and c ~= "-" then return left, j end
		local right, k, rerr = arithProduct(job, s, j + 1)
		if rerr ~= nil then return nil, k, rerr end
		if c == "+" then left = left + right else left = left - right end
		j = k
	end
end

-- value as a string, or nil plus the reason.
local function arithEval(job, expr)
	local v, j, err = arithSum(job, expr, 1)
	if err ~= nil then return nil, err end
	j = arithSkip(expr, j)
	if j <= #expr then return nil, "bad arithmetic" end
	return tostring(math.floor(v))
end

--
-- Expansion
--
-- A parsed word is an array of parts; this turns it into zero, one or several
-- FIELDS. A quoted part is one field whatever is in it; an unquoted expansion
-- is split on blanks. A word made only of empty unquoted expansions produces no
-- field at all, which is why `rm $nothing` is `rm` and not `rm ""`.
--

-- A $(...) opened: the frame that runs it, and the SUBSHELL it runs in.
--
-- POSIX.2 executes a command substitution in a subshell environment, so it is
-- handed a copy of the shell's variables, of its exported set and of its working
-- directory, and popFrame puts all three back. One function, because a capture is
-- opened from two places now -- a word, and the inside of a $(( )) -- and two
-- copies of a rule about what a subshell inherits would be two rules.
--
-- false when the frame stack is full, the job already failed by then.
local function pushCapture(job, prog)
	local frame = { k = "capture", prog = prog, i = 1,
		oldVars = job.vars, oldNvars = job.nvars, oldExported = job.exported,
		oldCwd = job.session.cwd, oldFuncs = job.funcs }
	if not pushFrame(job, frame) then return false end
	job.vars = CeroSecOS.copyVars(job.vars)
	job.exported = CeroSecOS.copyExported(job.exported)
	job.funcs = CeroSecOS.copyFuncs(job.funcs)
	job.caps[#job.caps + 1] = {}
	return true
end

-- words is an array of parsed words; nosplit is set for the right-hand side of
-- an assignment, which a shell never splits into fields.
local function newExpansion(words, nosplit)
	local kept = {}
	for i = 1, #words do kept[i] = words[i] end
	return { words = kept, wi = 1, pi = 1, buf = "", mask = "", open = false, nosplit = nosplit,
		fields = {}, fieldMasks = {}, out = {}, outMasks = {}, counts = {},
		-- IFS state for addSplit: ifsWs nil means "IFS unset, use the plain
		-- whitespace splitter verbatim"; wsClosed is the one bit an IFS
		-- delimiter needs across two parts of the same word (see addSplit).
		ifsWs = nil, ifsDelim = nil, wsClosed = false }
end

-- The mask beside ex.buf: "g" for a byte a pathname expansion may still read
-- as "*", "?" or "[", "l" for one that may not -- quoted, escaped, or handed
-- down through a place sh never globs (see CeroSecOS.expandGlob's header).
local function closeField(ex)
	ex.fields[#ex.fields + 1] = ex.buf
	ex.fieldMasks[#ex.fieldMasks + 1] = ex.mask
	ex.buf = ""
	ex.mask = ""
	ex.open = false
end

-- An unquoted expansion's text: every run of IFS delimiters in it ends a
-- field and starts the next one, which is what makes `for f in $list` walk
-- a list. `glob` is carried onto every byte handed in: a value that came out
-- of an unquoted "$x" still globs, which is what makes `x='*'; echo $x`
-- expand. Called once per PART of a word, so the field it is building may
-- already be open (from an earlier part of the same word) and may still be
-- open when it returns (for a later part to add to) -- ex.buf/ex.mask/
-- ex.open carry that across calls, exactly as they did before IFS existed.
local function addSplit(ex, text, glob)
	if text == "" then return end
	if ex.ifsWs == nil then
		-- IFS unset: the default splitter, byte for byte as it always was,
		-- so a script that never touches IFS is unchanged by this feature.
		local tokens = {}
		for piece in string.gmatch(text, "[^ \t\n]+") do tokens[#tokens + 1] = piece end
		if #tokens == 0 then
			-- Blanks and nothing else: it closes the open field and opens none.
			if ex.open then closeField(ex) end
			return
		end
		local mc = glob and "g" or "l"
		if string.find(text, "^[ \t\n]") ~= nil and ex.open then closeField(ex) end
		for i = 1, #tokens do
			if i > 1 then closeField(ex) end
			ex.buf = ex.buf .. tokens[i]
			ex.mask = ex.mask .. string.rep(mc, #tokens[i])
			ex.open = true
		end
		if string.find(text, "[ \t\n]$") ~= nil then closeField(ex) end
		return
	end

	-- IFS is set (maybe to "", which holds no byte in either table below, so
	-- every byte falls through to the plain "content" branch and the whole
	-- text becomes one unsplit run -- POSIX.2 2.6.5's "no splitting occurs").
	--
	-- A character loop over the WORD now too, matching the one over IFS
	-- above it: the word is the player's exactly as much as IFS is.
	--
	-- wsClosed is the one bit of state a delimiter needs to see across the
	-- boundary between two parts of a word: an IFS delimiter, along with any
	-- IFS whitespace next to it on EITHER side, is one separator (POSIX.2's
	-- "along with any adjacent IFS white space"), so `x="a "; y=":b"; $x$y`
	-- with IFS=" :" is two fields, not three, even though the space and the
	-- colon arrive in different addSplit calls. It is true only right after
	-- a field closed on pure whitespace, and it is spent (false) the moment
	-- a delimiter uses it, content starts, or a field closes on a delimiter
	-- of its own -- that delimiter already IS the boundary, nothing is left
	-- to merge into it.
	local ws, delim = ex.ifsWs, ex.ifsDelim
	local mc = glob and "g" or "l"
	local n = #text
	for i = 1, n do
		local c = string.sub(text, i, i)
		if ex.open then
			if delim[c] then
				closeField(ex)
				ex.wsClosed = false
			elseif ws[c] then
				closeField(ex)
				ex.wsClosed = true
			else
				ex.buf = ex.buf .. c
				ex.mask = ex.mask .. mc
			end
		else
			if delim[c] then
				if ex.wsClosed then
					-- Adjacent to the whitespace that just closed a field:
					-- the same separator, not a second one.
					ex.wsClosed = false
				else
					-- A delimiter on its own (or a second one in a row)
					-- always delimits, empty field and all: closeField on
					-- an empty, still-open buf pushes "" and nothing else.
					closeField(ex)
				end
			elseif not ws[c] then
				ex.buf = c
				ex.mask = mc
				ex.open = true
			end
			-- ws[c] while already closed: more of the same separator, and
			-- nothing to do.
		end
	end
end

-- "done" when every word is expanded, "sub" when a $(...) has been pushed and
-- the walker must run it first, or nil plus the reason.
local function expandStep(job, state, ex, env)
	-- Read IFS once per entry (this walker returns to the caller and is
	-- re-entered for every $( ) it must run first, and job.vars is back to
	-- the outer shell's by the time it is). nil means unset: addSplit keeps
	-- its old path verbatim for that case.
	local ifsRaw = job.vars.IFS
	if not ex.ifsCached or ifsRaw ~= ex.ifsRaw then
		ex.ifsRaw, ex.ifsCached = ifsRaw, true
		if ifsRaw == nil then ex.ifsWs, ex.ifsDelim = nil, nil
		else ex.ifsWs, ex.ifsDelim = ifsClasses(ifsRaw) end
	end
	while ex.wi <= #ex.words do
		local parts = ex.words[ex.wi]

		while ex.pi <= #parts do
			local part = parts[ex.pi]
			local text = nil

			if part.t == "lit" then
				text = part.s
			elseif part.t == "var" then
				text = getVar(job, part.name)
			elseif part.t == "arg" then
				if part.n == 0 then text = job.name else text = job.args[part.n] or "" end
			elseif part.t == "count" then
				text = tostring(#job.args)
			elseif part.t == "status" then
				text = tostring(job.status)
			elseif part.t == "job" then
				text = tostring(job.id)
			elseif part.t == "star" then
				-- One string, joined by IFS's first byte -- a blank if IFS is
				-- unset, nothing if it is set empty (POSIX.2 2.5.3). Quoted it
				-- is one field; bare it is split like any other expansion,
				-- below, on the very same IFS.
				text = table.concat(job.args, ifsJoinChar(job))
			elseif part.t == "bang" then
				-- Empty until an `&` has started something, as in any sh.
				if job.lastBg ~= nil then text = tostring(job.lastBg) else text = "" end
			elseif part.t == "arith" then
				-- The expansions in POSIX.2's order: command substitution first, the
				-- sum afterwards. A sum with no $( ) in it has no `parts` and is read
				-- straight, which is every sum anybody writes.
				local expr = part.expr
				if part.parts ~= nil then
					if ex.ai == nil then
						ex.ai = 1
						ex.abuf = ""
					end
					while ex.ai <= #part.parts do
						local piece = part.parts[ex.ai]
						if piece.t == "sub" then
							if not job.hasCap then
								if not pushCapture(job, piece.prog) then return nil, nil end
								return "sub"
							end
							ex.abuf = ex.abuf .. job.capval
							job.hasCap = false
							job.capval = nil
						else
							ex.abuf = ex.abuf .. piece.s
						end
						ex.ai = ex.ai + 1
						-- The same ceiling the word meets, met on the way in: what a
						-- capture inside a sum hands back is a string being built, and a
						-- string being built has one ceiling on this machine.
						if #ex.abuf > CeroSecOS.MAX_VAR_BYTES then return nil, "word too large" end
					end
					expr = ex.abuf
					ex.ai = nil
					ex.abuf = nil
				end
				local v, err = arithEval(job, expr)
				if v == nil then return nil, err end
				text = v
			elseif part.t == "all" then
				-- "$@" is one field per argument: it is the one expansion that
				-- is a list and not a string. A bare $@ is $*'s string, split on
				-- blanks like every other unquoted expansion (POSIX.2 2.5.2), so
				-- an argument with a blank in it becomes two words there.
				--
				-- Where nothing is split -- the right of `x=`, a case subject or
				-- pattern -- it is ONE field, the arguments joined by a blank,
				-- $@'s own rule and not $*'s IFS-joined one: `x=$@` and
				-- `x="$@"` with a and b set x to "a b" in dash and bash alike,
				-- whatever IFS holds, and `case "$@" in "a b")` matches. As a list
				-- it made the assignment two words, the second with no "=" in
				-- it, and runSimple's setVar fell over on it.
				local allGlob = (not part.q) and (not ex.nosplit)
				local allMc = allGlob and "g" or "l"
				if ex.nosplit then
					local joined = table.concat(job.args, " ")
					ex.buf = ex.buf .. joined
					ex.mask = ex.mask .. string.rep("l", #joined)
					ex.open = true
				elseif allGlob then addSplit(ex, table.concat(job.args, " "), true) end
				for a = 1, #job.args do
					if allGlob or ex.nosplit then break end
					if a > 1 then closeField(ex) end
					ex.buf = ex.buf .. job.args[a]
					ex.mask = ex.mask .. string.rep(allMc, #job.args[a])
					ex.open = true
				end
				ex.pi = ex.pi + 1
				text = nil
			elseif part.t == "sub" then
				if not job.hasCap then
					if not pushCapture(job, part.prog) then return nil, nil end
					return "sub"
				end
				text = job.capval
				job.hasCap = false
				job.capval = nil
			end

			if text ~= nil then
				-- "lit" globs when it was typed bare (addLit's `bare`); every
				-- other expansion globs when it was unquoted and not on the
				-- right of "=" -- except "arith", which never globs: "$(( 2*3 ))"
				-- is a sum and a "*" in it is multiplication, never a pattern.
				local glob
				if part.t == "lit" then
					glob = part.bare == true and not ex.nosplit
				elseif part.t == "arith" then
					glob = false
				else
					glob = (not part.q) and (not ex.nosplit)
				end
				if part.t == "lit" or part.q or ex.nosplit then
					ex.buf = ex.buf .. text
					ex.mask = ex.mask .. string.rep(glob and "g" or "l", #text)
					ex.open = true
				else
					addSplit(ex, text, glob)
				end
				ex.pi = ex.pi + 1
			end

			if #ex.buf > CeroSecOS.MAX_VAR_BYTES then return nil, "word too large" end
		end

		if ex.open then closeField(ex) end
		-- How many fields this word turned into, so the caller can tell a
		-- redirect's target apart from the arguments in front of it.
		ex.counts[ex.wi] = #ex.fields
		for i = 1, #ex.fields do
			ex.out[#ex.out + 1] = ex.fields[i]
			ex.outMasks[#ex.outMasks + 1] = ex.fieldMasks[i]
		end
		ex.fields = {}
		ex.fieldMasks = {}
		ex.wi = ex.wi + 1
		ex.pi = 1
		-- A new word starts a new run: nothing before it to merge a leading
		-- delimiter into (`:a` is an empty field then "a", not one field).
		ex.wsClosed = false
	end
	return "done"
end

--
-- test, and its other name
--

local testExpr

local function testUnary(state, session, op, arg)
	if op == "-z" then return #arg == 0 end
	if op == "-n" then return #arg > 0 end
	-- -h is 4.4BSD's (bin/test/operators.c lists it, test.1 says "exists
	-- and is a symbolic link", test.c answers it with lstat). -L is the
	-- letter later tests gave the same question; 4.4BSD's test has -h alone,
	-- and -L is kept so a script written for either reads the same.
	-- The one test here that must NOT follow the link, so it asks getNode with
	-- noFollow rather than the node every other letter below shares.
	if op == "-h" or op == "-L" then
		local lnode = CeroSecOS.getNode(state, session, arg, true)
		return lnode ~= nil and lnode.type == "link"
	end
	local node = CeroSecOS.getNode(state, session, arg)
	if op == "-e" then return node ~= nil end
	if op == "-f" then return node ~= nil and node.type == "file" end
	if op == "-d" then return node ~= nil and node.type == "dir" end
	-- -s: there, and st_size greater than zero (test.c's ISSIZE). A directory
	-- on a 4.4BSD disk is never size zero -- it holds . and .. at least, a
	-- block of them -- so one answers true whatever is in it.
	if op == "-s" then
		if node == nil then return false end
		if node.type == "dir" then return true end
		return #(node.data or "") > 0
	end
	if node == nil then return false end
	if op == "-r" then return CeroSecOS.can(state, session, node, "r") end
	if op == "-w" then return CeroSecOS.can(state, session, node, "w") end
	if op == "-x" then return CeroSecOS.can(state, session, node, "x") end
	return nil
end

local NUMERIC = { ["-eq"] = true, ["-ne"] = true, ["-lt"] = true, ["-le"] = true,
	["-gt"] = true, ["-ge"] = true }

local function testBinary(left, op, right)
	if op == "=" then return left == right end
	if op == "!=" then return left ~= right end
	if NUMERIC[op] then
		local a, b = tonumber(left), tonumber(right)
		if a == nil or b == nil then return nil, "test: integer expected" end
		if op == "-eq" then return a == b end
		if op == "-ne" then return a ~= b end
		if op == "-lt" then return a < b end
		if op == "-le" then return a <= b end
		if op == "-gt" then return a > b end
		return a >= b
	end
	return nil
end

-- true/false, or nil plus the line to print. -o binds loosest, then -a, then
-- "!", the way test has always read its arguments.
testExpr = function(state, session, args, lo, hi)
	if lo > hi then return false end

	for k = hi, lo, -1 do
		if args[k] == "-o" then
			local a, aerr = testExpr(state, session, args, lo, k - 1)
			if a == nil then return nil, aerr end
			local b, berr = testExpr(state, session, args, k + 1, hi)
			if b == nil then return nil, berr end
			return a or b
		end
	end
	for k = hi, lo, -1 do
		if args[k] == "-a" then
			local a, aerr = testExpr(state, session, args, lo, k - 1)
			if a == nil then return nil, aerr end
			local b, berr = testExpr(state, session, args, k + 1, hi)
			if b == nil then return nil, berr end
			return a and b
		end
	end
	if args[lo] == "!" then
		local v, err = testExpr(state, session, args, lo + 1, hi)
		if v == nil then return nil, err end
		return not v
	end

	local n = hi - lo + 1
	if n == 1 then return args[lo] ~= "" end
	if n == 2 then
		local v = testUnary(state, session, args[lo], args[lo + 1])
		if v == nil then return nil, "test: unknown operator" end
		return v
	end
	if n == 3 then
		local v, err = testBinary(args[lo], args[lo + 1], args[lo + 2])
		if v == nil then
			if err ~= nil then return nil, err end
			return nil, "test: unknown operator"
		end
		return v
	end
	return nil, "test: argument expected"
end

--
-- The builtins a script has
--
-- These are the shell's own and need no file in /bin, exactly as `exit` and
-- `help` need none at the prompt: a machine whose /bin has been emptied still
-- has an `if` and an `echo`, because neither of them was ever a program.
--
-- Each returns the exit status, or nil plus a fatal reason for the job.
--

local builtins = {}

-- The one builtin whose redirect is NOT a capture round what it printed.
--
-- runSimple catches a builtin's own lines and writes them through the redirect
-- door, which is right for every word that prints something. The dot prints
-- nothing: it RUNS A FILE, in this shell, and what `>` names is where that file's
-- output goes -- so the dot is handed the redirect and opens it itself, exactly as
-- the shell does for `sh` and for `./thing`.
local BUILTIN_TAKES_REDIRECT = { ["."] = true }

builtins["true"] = function() return 0 end
builtins["false"] = function() return 1 end

builtins.echo = function(job, args)
	local from, newline = 2, true
	if args[2] == "-n" then
		from = 3
		newline = false
	end
	local words = {}
	for i = from, #args do words[#words + 1] = args[i] end
	local text = table.concat(words, " ")
	if newline then text = text .. "\n" end
	writeText(job, text)
	return 0
end

-- printf(1)'s field: [-][0][width][.precision]conversion. `-` left-justifies
-- (the default is right), `0` pads with zeros instead of blanks and only
-- means anything where there is no `-` beside it (printf.c: "if the left
-- adjustment flag is set, the zero-padding flag is ignored"). Bounded at 64 --
-- this machine's screen is 60 columns and nothing typed at a prompt needs a
-- field wider than one, and CeroSecOS.hostileTest is what a `%999999999s`
-- would otherwise be handed to.
local PRINTF_MAX_FIELD = 64

local function printfPad(body, width, left, zero, sign)
	sign = sign or ""
	if width == nil or width <= #sign + #body then return sign .. body end
	local fill = width - #sign - #body
	if left then return sign .. body .. string.rep(" ", fill) end
	if zero then return sign .. string.rep("0", fill) .. body end
	return string.rep(" ", fill) .. sign .. body
end

-- Division, not string.format: Kahlua's %x and %o are not proven (there is no
-- bit library either), so the digits are found the way K&R's itoa does it, one
-- remainder at a time. Bounded by the width of the number itself -- a 53-bit
-- float in base 8 is at most eighteen digits -- and never by anything a
-- player types.
-- %x and %o are unsigned in C, and a negative argument is really the bit
-- pattern of a signed int reread as one -- which wants a word size this
-- engine has no bit library to fix at (docs/CONTRIBUTING.md's Kahlua purity
-- rule). Clamped to zero instead of guessing a width: a survivor typing
-- `printf %x -1` gets 0, not a wrong answer dressed as a right one.
local function toBase(v, base, digits)
	v = math.floor(v)
	if v < 0 then v = 0 end
	if v == 0 then return "0" end
	local s = ""
	while v > 0 do
		local d = v - base * math.floor(v / base)
		s = string.sub(digits, d + 1, d + 1) .. s
		v = math.floor(v / base)
	end
	return s
end

-- One pass over the format, from args[from]. Answers the text and the next
-- unread argument index, so the caller can tell whether the pass consumed
-- anything -- which is what decides whether the format is reused (see the
-- head of CeroSecOS.printfText).
local function printfPass(format, args, from)
	local out, i, a = "", 1, from
	while i <= #format do
		local c = string.sub(format, i, i)
		if c == "\\" then
			local nx = string.sub(format, i + 1, i + 1)
			if nx == "n" then out = out .. "\n"; i = i + 2
			elseif nx == "t" then out = out .. "\t"; i = i + 2
			elseif nx == "\\" then out = out .. "\\"; i = i + 2
			-- \NNN, up to three octal digits, sh(1)'s printf and the C escape it
			-- is named after (K&R A2.5.2): the byte that octal names.
			elseif string.match(nx, "^[0-7]$") ~= nil then
				-- Kahlua's tonumber(s, base) is not trusted for anything but
				-- base 10 (tests/kahlua-probe.lua), so the octal value is added
				-- up a digit at a time instead of handed to it with an 8.
				local j, val = i + 1, 0
				local n = 0
				while j <= #format and n < 3 and string.match(string.sub(format, j, j), "^[0-7]$") ~= nil do
					val = val * 8 + tonumber(string.sub(format, j, j))
					j = j + 1
					n = n + 1
				end
				-- The byte, unless it is a control byte: nothing typed at
				-- this machine may put one on a screen or a disk (the line
				-- itself is refused with one in it, and writeFile refuses
				-- them too -- docs/SECURITY.md), so \NNN naming anything
				-- below a blank other than a tab or a newline, or DEL,
				-- makes nothing. A declared deviation ("printf").
				val = val % 256
				if val == 9 or val == 10 or (val >= 32 and val ~= 127) then
					out = out .. string.char(val)
				end
				i = j
			else out = out .. "\\" .. nx; i = i + 2 end
		elseif c == "%" then
			local j = i + 1
			local left, zero = false, false
			while true do
				local f = string.sub(format, j, j)
				if f == "-" then left = true; j = j + 1
				elseif f == "0" then zero = true; j = j + 1
				else break end
			end
			local width = nil
			local wDigits = string.match(format, "^%d+", j)
			if wDigits ~= nil then
				width = tonumber(wDigits)
				j = j + #wDigits
			end
			local prec = nil
			if string.sub(format, j, j) == "." then
				j = j + 1
				local pDigits = string.match(format, "^%d+", j) or "0"
				prec = tonumber(pDigits)
				j = j + #pDigits
			end
			if width ~= nil and width > PRINTF_MAX_FIELD then width = PRINTF_MAX_FIELD end
			if prec ~= nil and prec > PRINTF_MAX_FIELD then prec = PRINTF_MAX_FIELD end
			local conv = string.sub(format, j, j)
			if conv == "%" then
				out = out .. "%"
			elseif conv == "s" then
				local v = tostring(args[a] or "")
				a = a + 1
				if prec ~= nil then v = string.sub(v, 1, prec) end
				out = out .. printfPad(v, width, left, false)
			elseif conv == "c" then
				local v = string.sub(tostring(args[a] or ""), 1, 1)
				a = a + 1
				out = out .. printfPad(v, width, left, false)
			elseif conv == "d" then
				local v = tonumber(args[a] or "0") or 0
				a = a + 1
				v = math.floor(v)
				local sign = ""
				if v < 0 then sign = "-"; v = -v end
				local digits = tostring(v)
				-- Precision on a numeric conversion is a MINIMUM digit count
				-- (printf(3)), not a truncation: `%.4d` on 3 is "0003", and
				-- `%.0d` on 0 is nothing at all -- no digit, not even a zero.
				if prec ~= nil then
					if prec == 0 and v == 0 then digits = ""
					elseif #digits < prec then digits = string.rep("0", prec - #digits) .. digits end
				end
				out = out .. printfPad(digits, width, left, zero and prec == nil, sign)
			elseif conv == "x" or conv == "o" then
				local v = tonumber(args[a] or "0") or 0
				a = a + 1
				local digits = toBase(v, conv == "x" and 16 or 8, "0123456789abcdef")
				if prec ~= nil and #digits < prec then
					digits = string.rep("0", prec - #digits) .. digits
				end
				out = out .. printfPad(digits, width, left, zero and prec == nil)
			elseif conv == "" then
				out = out .. "%"
			else
				-- An unknown conversion prints as it stood in the format, flags,
				-- width and precision included -- `%5.2f` comes out `%5.2f`, not
				-- `%f` with the field thrown away (this machine has no %f: no
				-- floating point conversion is trusted here, printf(3)'s NUL
				-- termination and rounding wanting more than Kahlua's numbers
				-- prove). No argument is consumed either: the operand is still
				-- waiting for the conversion that would have read it.
				out = out .. string.sub(format, i, j)
			end
			i = j + 1
		else
			out = out .. c
			i = i + 1
		end
	end
	return out, a
end

-- printf(1): the format is reused for as many arguments as there are, POSIX's
-- own rule ("the format operand shall be reused as often as necessary to
-- satisfy the argument operands") -- `printf '%s\n' a b c` is three lines, not
-- one truncated to the first name. Reused only while a PASS is actually
-- eating an argument, so a format with no conversion in it -- `printf hello
-- extra` -- prints once and stops, the way a real printf does not spin on
-- operands it has nowhere to put.
function CeroSecOS.printfText(args)
	local format = args[2]
	if format == nil then return nil end
	local out, a = "", 3
	repeat
		local before = a
		local piece
		piece, a = printfPass(format, args, a)
		out = out .. piece
	until a > #args or a == before
	return out
end

builtins.printf = function(job, args)
	local text = CeroSecOS.printfText(args)
	if text == nil then return 1 end
	writeText(job, text)
	return 0
end

-- history. The shell's own memory, so the shell is what prints it: there is no
-- /bin/history and there could not be one -- a separate program could not
-- clear the history of the shell that ran it.
--
-- The numbers are the entry's position in the file as it stands. A real shell
-- counts them from the first line of the session and never reuses one; this
-- one renumbers when the oldest are dropped, which is what a machine that
-- keeps its history on the disk and nowhere else can honestly say.
builtins.history = function(job, args, state, env)
	if args[2] == "-c" and #args == 2 then
		CeroSecOS.historyClear(state, job.session, CeroSecOS.clockOf(env))
		return 0
	end
	if #args > 1 then
		errLines(job, { "history: usage: history [-c]" })
		return 1
	end
	local lines = CeroSecOS.historyLines(state, job.session)
	local from = #lines - CeroSecOS.HISTORY_SHOW + 1
	if from < 1 then from = 1 end
	for i = from, #lines do
		writeText(job, CeroSecOS.padLeft(tostring(i), 5) .. "  " .. lines[i] .. "\n")
	end
	return 0
end

builtins.shift = function(job, args)
	local n = 1
	if args[2] ~= nil then
		n = tonumber(args[2])
		if n == nil or n < 0 then return 1 end
		n = math.floor(n)
	end
	if n > #job.args then return 1 end
	local kept = {}
	for i = n + 1, #job.args do kept[#kept + 1] = job.args[i] end
	job.args = kept
	return 0
end

-- export: which of this shell's variables a program it runs is handed.
--
-- `export NAME` marks a name, `export NAME=value` sets it and marks it in one
-- line, and several names may be marked at once -- POSIX.2's export, and sh's
-- since the seventh edition. It has to be the shell's own word for the reason
-- `cd` has to be: a program cannot reach into the shell that ran it, so nothing
-- in /bin could mark anything.
--
-- With no operand it LISTS, in the re-inputtable form POSIX.2 asks of it:
-- `export NAME=value`, one a line, sorted (pairs is not an order and a listing
-- nothing could print twice is not a listing). `env` prints the same set the
-- other way, without the word in front.
--
-- A name that is not one is fatal, the way it is for `read` and for the same
-- reason: export is one of sh's special built-ins, and a special built-in that
-- is handed nonsense ends a script rather than carrying on with a variable it
-- could not have.
builtins.export = function(job, args)
	if #args == 1 then
		local names = CeroSecOS.envNames(job.vars, job.exported)
		for i = 1, #names do
			writeText(job, "export " .. names[i] .. "=" .. job.vars[names[i]] .. "\n")
		end
		return 0
	end
	for i = 2, #args do
		local a = args[i]
		local eq = string.find(a, "=", 1, true)
		local name = a
		if eq ~= nil then name = string.sub(a, 1, eq - 1) end
		if not CeroSecOS.isVarName(name) then return nil, "export: not a name" end
		if eq ~= nil then
			local reason = setVar(job, name, string.sub(a, eq + 1))
			if reason ~= nil then return nil, reason end
		end
		local reason = markExported(job, name)
		if reason ~= nil then return nil, reason end
	end
	return 0
end

-- The dot command: where a shell reads a file INTO ITSELF.
--
-- `. file` is not `sh file`. A program is handed a copy of the environment and
-- what it sets dies with it, so the dot is the one way a file's assignments land
-- in the shell that asked for them -- which is what ~/.profile is read with, and
-- the whole reason a PATH line in a file is worth writing. sh's since the
-- seventh edition, POSIX.2's "dot"; `source` is csh's word for it, came to bash
-- from there, and is not on this machine.
--
-- The file is looked for on PATH when the name has no "/" in it, which is what
-- POSIX.2 says of it, and then tried as it was typed -- so `. setup` and
-- `. ./setup` both read the file in front of you, and neither needs x on it:
-- nothing here EXECUTES the file, the shell reads it.
--
-- No operand after the file. The 1993 form takes none; the arguments form is
-- later.
-- redirect, when the line carried one, is the dot's own to carry out, and not the
-- caps wrapper runSimple puts round every other builtin's: the dot RUNS A FILE, so
-- what `>` names belongs to the lines that file prints and not to the nothing the
-- word itself prints. `. setup > log` wrote an empty log and put the file's output
-- on the glass. Same door `sh` uses, one argument along (BUILTIN_TAKES_REDIRECT).
builtins["."] = function(job, args, state, env, redirect, sinks)
	-- Refusals, so the standard error's: not caught by a $( ), and into what a
	-- `2>` on the dot named. runSimple leaves job.errRd alone for a word that
	-- takes its own redirect, so the dot puts its own in place for them.
	local function refuse(line)
		local erd = nil
		if type(sinks) == "table" then erd = sinks.erd end
		local outer = job.errRd
		if erd ~= nil then job.errRd = erd end
		errLines(job, { line })
		job.errRd = outer
		if erd ~= nil and erd.buf ~= nil and #erd.buf > 0 then
			local text = CeroSecOS.linesToText(erd.buf)
			erd.buf = {}
			local ok, lines = CeroSecOS.writeRedirect(state, job.session, ".",
				{ path = erd.path, append = true }, text, env)
			if not ok then errLines(job, lines) end
		end
	end
	if #args ~= 2 then
		refuse(".: usage: " .. (CeroSecOS.commandUsage(".") or ". <file>"))
		return 1
	end
	local path = args[2]
	if string.find(path, "/", 1, true) == nil then
		local found = CeroSecOS.lookupPath(state, job.session, path,
			CeroSecOS.pathValue(job.vars))
		if found ~= nil then path = found end
	end
	local text, refusal = CeroSecOS.readScript(state, job.session, ".", path, false)
	if text == nil then
		refuse(refusal)
		return 1
	end
	local prog, reason, where = CeroSecOS.parseScript(text)
	if prog == nil then
		refuse(CeroSecOS.scriptError(CeroSecOS.baseNameOf(path), reason, where))
		return 1
	end
	-- What `>` named, opened where a shell opens it: before the file runs, so a
	-- target that cannot be opened is a dot that does not read anything.
	local target = nil
	if redirect ~= nil then
		local openOk, openLines =
			CeroSecOS.openRedirect(state, job.session, ".", redirect, env)
		if not openOk then
			errLines(job, openLines)
			return 1
		end
		target = { path = redirect.path, who = "." }
	end
	-- What runSimple worked out from the whole line, `2>` and `>&2` included,
	-- when it is the shell that called: the same file, and the errors' sink.
	local erd = nil
	if type(sinks) == "table" then
		target = sinks.target
		erd = sinks.erd
	end
	-- In place: the caller's arguments, the caller's variables, and everything
	-- the file sets left behind in them.
	if not CeroSecOS.jobRun(job, prog, job.args, CeroSecOS.baseNameOf(path), true,
			target, erd) then
		return nil
	end
	return 0
end

builtins.exit = function(job, args)
	local n = 0
	if args[2] ~= nil then n = math.floor(tonumber(args[2]) or 0) end
	job.sig = { k = "exit", n = n }
	return n
end
-- `return` leaves a FUNCTION, and the file a `.` read: POSIX's own two places for
-- it. Its own signal since there are functions to return from -- it was `exit` under
-- another name while there were none.
--
-- With neither around it, it is `exit`: POSIX leaves that case unspecified, a real
-- sh of 1993 took it as the end of the script, and so does every script already
-- written on every machine in the county.
builtins["return"] = function(job, args)
	local n = 0
	if args[2] ~= nil then n = math.floor(tonumber(args[2]) or 0) end
	job.sig = { k = "return", n = n }
	return n
end

local function loopSignal(job, args, kind)
	local n = 1
	if args[2] ~= nil then
		n = tonumber(args[2])
		if n == nil or n < 1 then return 1 end
		n = math.floor(n)
	end
	job.sig = { k = kind, n = n }
	return 0
end

builtins["break"] = function(job, args) return loopSignal(job, args, "break") end
builtins["continue"] = function(job, args) return loopSignal(job, args, "continue") end

-- read's fields. POSIX.2 read and the ksh88 manual page: the line is split on
-- blanks, the first word goes to the first name, the second to the second, and
-- the LAST name gets whatever is left of the line, blanks inside it and all --
-- which is what makes `read cmd rest` the way to take a line apart. Names with
-- no word left for them are set empty. Leading and trailing blanks are dropped.
--
-- Without -r a backslash is the escape it is everywhere else in sh: it is taken
-- away and the character behind it is kept as it stands, so `a\ b` is one word.
-- -r keeps every backslash as typed. A backslash at the very end of a line asks
-- a real read for the next line; this console hands over one line and nothing
-- after it (the `more` entry of CeroSecOS.DEVIATIONS), so it is dropped.
--
-- A character loop and never a pattern: the line, and IFS, are the player's.
--
-- Interior fields (all but the last) split exactly as any unquoted expansion
-- does (addSplit above): an IFS delimiter, with any IFS whitespace adjacent
-- to it, is one boundary, and a second delimiter in the same run still
-- delimits its own -- possibly empty -- field. The LAST name never re-splits:
-- it is everything left on the line after that one boundary, with only ITS
-- OWN leading and trailing IFS whitespace gone -- POSIX.2's read hands the
-- rest of the line to the last variable, delimiters and all, not a rejoin of
-- further fields. `dash` on this box is the oracle every one of these rules
-- was checked against, `a::b` through a lone `read x y z` included.
local function readFields(job, line, raw, count)
	local chars, prot = {}, {}
	local i, n = 1, #line
	while i <= n do
		local c = string.sub(line, i, i)
		if c == "\\" and not raw then
			if i < n then
				chars[#chars + 1] = string.sub(line, i + 1, i + 1)
				prot[#prot + 1] = true
			end
			i = i + 2
		else
			chars[#chars + 1] = c
			prot[#prot + 1] = false
			i = i + 1
		end
	end
	local total = #chars

	local ifs = getIFS(job)
	if ifs == "" then
		-- IFS null: no field splitting at all. The whole line, untouched,
		-- is the first name; every other name is left empty.
		local fields = {}
		local word = {}
		for j = 1, total do word[#word + 1] = chars[j] end
		fields[1] = table.concat(word)
		for f = 2, count do fields[f] = "" end
		return fields
	end
	local ws, delim = ifsClasses(ifs)
	local function isW(k) return not prot[k] and ws[chars[k]] end
	local function isD(k) return not prot[k] and delim[chars[k]] end
	local function slice(a, b)
		local word = {}
		for j = a, b do word[#word + 1] = chars[j] end
		return table.concat(word)
	end

	local fields, k = {}, 1
	local open, start, wsClosed = false, 1, false
	local f = 1
	while f < count do
		local val = nil
		while k <= total do
			if open then
				if isD(k) then
					val, wsClosed = slice(start, k - 1), false
					k, open = k + 1, false
					break
				elseif isW(k) then
					val, wsClosed = slice(start, k - 1), true
					k, open = k + 1, false
					break
				else
					k = k + 1
				end
			elseif isD(k) then
				if wsClosed then
					-- Adjacent to the whitespace that just closed a field:
					-- the same boundary, not a second one.
					wsClosed = false
					k = k + 1
				else
					val = ""
					k = k + 1
					break
				end
			elseif isW(k) then
				k = k + 1
			else
				open, start = true, k
				k = k + 1
			end
		end
		if val == nil then
			-- The line ran out before this field closed on its own.
			if open then val, open = slice(start, total), false
			else val = "" end
			k = total + 1
		end
		fields[f] = val
		f = f + 1
	end

	-- The one absorption a delimiter right after a whitespace-close still
	-- owes, same as inside addSplit: at most one, and only if the run has
	-- not already spent it.
	if not open and wsClosed and k <= total and isD(k) then k = k + 1 end
	while k <= total and isW(k) do k = k + 1 end
	local last = total
	while last >= k and isW(last) do last = last - 1 end
	fields[count] = slice(k, last)
	return fields
end

-- Every name, set from one line, from each of the three places a line reaches
-- read: the pipe, end of file, and the answer typed at the question.
local function assignFields(job, names, line, raw)
	local fields = readFields(job, line, raw, #names)
	for i = 1, #names do
		local reason = setVar(job, names[i], fields[i])
		if reason ~= nil then return reason end
	end
	return nil
end

-- read: the continuation every interactive script is built on. The job stops
-- where it stands, the console puts the question up, and the next line typed
-- comes back through CeroSecOS.jobInput.
builtins.read = function(job, args, state, env)
	local prompt, mask, count, raw, names = "", false, nil, false, {}
	local i = 2
	while i <= #args do
		local a = args[i]
		if #names > 0 then
			names[#names + 1] = a
			i = i + 1
		elseif a == "-p" then
			prompt = args[i + 1] or ""
			i = i + 2
		elseif a == "-s" then
			mask = true
			i = i + 1
		elseif a == "-r" then
			raw = true
			i = i + 1
		elseif a == "-n" then
			-- -n N: the first N characters of the answer. A count that is not a
			-- whole number above nought is ksh's "bad number".
			local want = args[i + 1] or ""
			count = tonumber(want)
			if count == nil or count < 1 or count ~= math.floor(count)
					or string.find(want, "^[0-9]+$") == nil then
				return nil, "read: " .. want .. ": bad number"
			end
			i = i + 2
		elseif string.sub(a, 1, 1) == "-" and #a > 1 then
			return nil, "read: " .. a .. ": unknown option"
		else
			names[#names + 1] = a
			i = i + 1
		end
	end
	if #names == 0 then return nil, "read: not a name" end
	for k = 1, #names do
		if not CeroSecOS.isVarName(names[k]) then return nil, "read: not a name" end
	end

	-- A stage of a pipeline reads the PIPE, because that is what its standard
	-- input is. It is also a subshell, and its variables die with it -- which is
	-- why `echo hi | read x` leaves x empty in the shell that typed it, on this
	-- machine exactly as on every other one with a pipeline in it.
	if job.stdinBuf ~= nil then
		local buf = job.stdinBuf
		if #buf.lines > 0 then
			local line = buf.lines[1]
			-- -n N on a stream takes N characters and leaves the rest where it
			-- was, for the next read: `printf 'abcdef\nxy\n' | while read -n 2 a`
			-- gives ab, cd, ef, an empty one, xy and an empty one under bash, the
			-- empty ones being the newline itself, left behind by a read that had
			-- already taken its N. A shorter line is taken whole, newline too.
			if count ~= nil and #line >= count then
				buf.lines[1] = string.sub(line, count + 1)
				buf.bytes = buf.bytes - count
				line = string.sub(line, 1, count)
			else
				table.remove(buf.lines, 1)
				buf.bytes = buf.bytes - #line - 1
			end
			if buf.bytes < 0 then buf.bytes = 0 end
			local reason = assignFields(job, names, line, raw)
			if reason ~= nil then return nil, reason end
			return 0
		end
		if buf.eof then
			local reason = assignFields(job, names, "", raw)
			if reason ~= nil then return nil, reason end
			return 1
		end
		-- Nothing in the pipe yet: the stage stops where it stands and the one
		-- to its left is what runs next. The command has not run, so the frame
		-- stays and the read is asked again when there is a line.
		job.again = true
		job.blocked = "input"
		return job.status
	end

	-- A background job has nobody in front of it, and neither has a stage of a
	-- pipeline whose standard input is not a pipe (`read x | cat`). Both read end
	-- of file, the way a real one reading a closed input does, and say so with
	-- their status rather than hanging forever where nobody can see it.
	if job.bg or job.inPipe then
		local reason = assignFields(job, names, "", raw)
		if reason ~= nil then return nil, reason end
		return 1
	end

	flushPartial(job)
	job.ask = { names = names, text = prompt, mask = mask, count = count, raw = raw }
	job.state = "waiting"
	return 0
end

-- sleep is a program on a real machine (/bin/sleep, 4.4BSD sleep.c), so what
-- it cannot do it says and answers with a status -- 1, sleep.c's usage exit --
-- and the script that ran it goes on to its next line, as it would anywhere.
-- It says so on the standard ERROR, where sleep.c's usage() prints:
-- `sleep abc > f` leaves f empty, `x=$(sleep abc)` leaves x empty, and
-- `2>/dev/null` hushes it.
builtins.sleep = function(job, args, state, env)
	local n = tonumber(args[2] or "")
	if n == nil or n < 0 then
		errLines(job, { "sleep: invalid interval" })
		return 1
	end
	local now = CeroSecOS.nowMsOf(env)
	-- A machine with no clock cannot sleep; it says so rather than sleeping
	-- forever or not at all.
	if now == nil then
		errLines(job, { "sleep: no clock" })
		return 1
	end
	job.wakeMs = now + math.floor(n * 1000)
	job.state = "sleeping"
	return 0
end

-- The expression, judged. Shared by the builtin below and by /bin's own door
-- into it (`sudo test -f /root/notes`), so there is one evaluator and one set
-- of refusals.
-- true/false, or nil plus the line to print. test and [ are a program on a real
-- machine (/bin/test, /bin/[ -- 4.4BSD test.c), and a program that cannot judge
-- its expression prints why and exits 2: a missing ']' included, which test.c
-- reports through the same syntax() as every other malformed expression. The
-- script that ran it goes on. Why is on the standard error, where test.c's
-- err() writes it: `[ 1 -eq x ] | wc -l` counts nought, `2>/dev/null` hushes it.
function CeroSecOS.evalTest(state, session, args)
	local hi = #args
	if args[1] == "[" then
		if args[hi] ~= "]" then return nil, "test: missing ']'" end
		hi = hi - 1
	end
	return testExpr(state, session, args, 2, hi)
end

builtins.test = function(job, args, state)
	local v, err = CeroSecOS.evalTest(state, job.session, args)
	if v == nil then
		errLines(job, { err })
		return 2
	end
	if v then return 0 end
	return 1
end
builtins["["] = builtins.test

-- wait: hold the job until every background job named is gone. Written as a
-- builtin so that `wait` typed at the prompt and `wait` inside a script are the
-- same thing -- the prompt's one is a job of a single line (see commands.wait).
builtins.wait = function(job, args, state, env)
	local ids = {}
	local jobs = CeroSecOS.jobsOf(env)
	for i = 2, #args do
		local id = args[i]
		if string.sub(id, 1, 1) == "%" then id = string.sub(id, 2) end
		id = tonumber(id)
		if id == nil then return nil, "wait: " .. args[i] .. ": no such job" end
		local found = false
		for k = 1, #jobs do
			if jobs[k].id == id and jobs[k] ~= job then found = true end
		end
		if not found then return nil, "wait: " .. args[i] .. ": no such job" end
		ids[#ids + 1] = id
	end
	if #ids == 0 then
		for k = 1, #jobs do
			if jobs[k] ~= job and jobs[k].bg then ids[#ids + 1] = jobs[k].id end
		end
	end
	if #ids == 0 then return 0 end
	job.waitFor = ids
	job.state = "waiting"
	return 0
end

--
-- Running one simple command
--

-- Has this job a CONTROLLING TERMINAL -- a screen with somebody in front of it,
-- whose attention the job holds?
--
-- Three ways of having none, and every one of them is a job that runs with
-- nobody there:
--
--   * it is not the prompt's own job (`job.interactive`) -- a crontab line and a
--     `&` are the machine's work and not a pair of hands';
--   * it is a stage of a pipeline -- what it writes goes to the stage on its
--     right and not to a glass;
--   * it is inside a $(...) -- a subshell whose output is being collected, which
--     is a pipe wearing another name.
--
-- What is deliberately NOT on the list is DEPTH. `./nightly.sh` run from the
-- prompt is the prompt's own job one level deeper, and a terminal is inherited:
-- that is what real Unix does, and it is the difference between a script an
-- operator runs and a script cron runs. `exitLeavesTheMachine` below is this
-- rule plus the depth rule, because `exit` is the one order a file may not give
-- on its shell's behalf.
local function jobHasTerminal(job)
	if not job.interactive then return false end
	if job.inPipe then return false end
	for i = 1, #job.frames do
		if job.frames[i].k == "capture" then return false end
	end
	return true
end

-- And the question a COMMAND asks, which is not quite the same one: is there a
-- pair of hands that could press a key for this command?
--
-- The difference is the pipe. A stage of a pipeline has no terminal of its own --
-- what it writes goes to the stage on its right -- but the pipeline it is part of
-- may very well be the line somebody just typed, and its question travels up to
-- that pipeline (pipeStep carries it, jobInput hands the answer back down). So
-- `ls -l | more` has a keyboard behind it and `* * * * * ls -l | more` has not,
-- and a test that stopped at `job.inPipe` could not tell them apart.
--
-- The walk up `errTo` is what asks the pipeline: a stage keeps a link to the job
-- the machine is holding, because that is where its errors go, and that job is
-- the one with the keyboard. Bounded by how deep pipelines nest.
--
-- What is asked of the job at the top is exactly what jobHasTerminal asks: it is
-- the prompt's own job, not a `&`, and nothing is catching its output.
local function jobHasKeyboard(job)
	if not toScreen(job) then return false end
	local owner = job
	local hops = 0
	while owner.errTo ~= nil and hops < CeroSecOS.MAX_FRAMES do
		owner = owner.errTo
		hops = hops + 1
	end
	if owner.bg then return false end
	return owner.interactive == true
end

-- EVERY order a command can hand back, and what it does to the job that gave
-- it. Three dispositions and no fourth:
--
--   "vm"       the VM itself deals with it and the job goes on -- a wait, a
--              question, a script one level deeper, a link on the radio.
--   "machine"  only the machine can do it, and the job goes on PAST it the way
--              a caller goes on past any other program: the order is queued on
--              the job (job.orders) and the pass carries it out.
--   "exit"     the order ends the whole job, because there is nothing left for
--              the job to do -- the machine is going dark, the account is being
--              logged out, a session or a buffer has taken the glass.
--
-- It is a table and not a comment because of `wall`. wall(1) is an ordinary
-- program -- `wall notice; echo sent` prints `sent` on every Unix there has
-- been -- and it arrived here as a name applyControl had no case for, so it
-- fell to the generic end of this function, which ends the job with `all`:
-- `echo before; wall f; echo after` printed `before` and stopped, and a crontab
-- line died at its own broadcast. Every bench stayed green because the only
-- shape they wrote was `echo hi | wall`, where the order is the LAST thing the
-- job does and the end of it costs nothing. So the generic end refuses a name
-- that is not written down here instead of obeying it (see the foot of this
-- function), and tests/os_test.lua walks the table against the dispositions it
-- expects -- a new order has to say which of the three it is, in this table, or
-- the machine says so out loud.
CeroSecOS.KNOWN_ORDERS = {
	sleep = "vm",
	prompt = "vm",
	job = "vm",
	tnc = "vm",
	rsh = "vm",
	wall = "machine",
	clear = "machine",
	edit = "exit",
	exit = "exit",
	fg = "exit",
	schedule = "exit",
	shutdown = "exit",
	reboot = "exit",
	rlogin = "exit",
	cu = "exit",
}

-- How many passes one typed line may have IN THE HAND of whoever typed it,
-- while it asks the machine for a job of its own or for an order carried out
-- (SCeroSecSystem:startPrompt). Four is the job book, which bounds the "&" half
-- of it; sixteen leaves room for a line that clears its screen and broadcasts a
-- few times, and a line that wants more finishes on the scheduler's own passes
-- like any other long one.
CeroSecOS.MAX_LINE_TURNS = 16

-- An order for the MACHINE, queued on the job that gave it, with the job left
-- running.
--
-- A list and not a field: a script can broadcast twice before a pass gets round
-- to it, and an order that overwrote the one before it would be a broadcast
-- nobody ever read. The pass drains the list and empties it
-- (CeroSecJobs.runMachine); until it does, jobStep will not step this job
-- again, which is what puts the machine's own act BETWEEN the lines either side
-- of it -- `echo a; clear; echo b` clears the glass after `a` and not after `b`.
-- That is exactly how an `&` waits for the machine to make its job (job.spawn),
-- and for the same reason.
local function machineOrder(job, control, data)
	if job.orders == nil then job.orders = {} end
	job.orders[#job.orders + 1] = { control = control, data = data }
end

-- The order every control the core can hand back is dealt with. A script is
-- not a screen: an editor cannot open on it, so `edit` is refused where it was
-- typed rather than half-opened somewhere nobody is looking.
local function applyControl(job, control, data, env)
	if control == nil then return true end
	-- A command that has to WAIT. ping spaces its three packets a second apart
	-- and rcp takes as long as the wire takes; neither of those is a question and
	-- neither is a `sleep` somebody typed, so the command hands back how long it
	-- wants and a token to be woken with. The job goes to sleep exactly as
	-- `sleep 1` leaves it -- off the processor, costing nothing while it waits --
	-- and when it comes round the token is answered with an empty line.
	--
	-- A machine with no clock cannot wait, so the command runs on at once: that
	-- is the same answer `sleep` gives one, except that here there is nothing to
	-- refuse -- the waiting is the command's own pacing and not something typed.
	if control == "sleep" and type(data) == "table" then
		-- A wait that ENDS IN A DIAL -- which is the ring of a telephone call --
		-- is refused here if there is nobody standing at the machine, and refused
		-- BEFORE the wait rather than after it: a crontab line must not hold a
		-- telephone line open for fifteen seconds to be told the thing the door
		-- would have told it at once. The word is the command's own, so the
		-- refusal reads the same as the one the order itself gets below.
		if data.dial ~= nil and not jobHasTerminal(job) then
			flushPartial(job)
			errLine(job, tostring(data.dial) .. ": not a terminal")
			job.status = 1
			return true
		end
		flushPartial(job)
		local now = CeroSecOS.nowMsOf(env)
		local ms = tonumber(data.ms)
		-- And the line the wait is HOLDING, when it is holding one. It lives on
		-- the job, never beside it: a job that has gone -- killed, interrupted,
		-- over its cpu -- has let go of the line by the same act, so the busy rule
		-- reads the jobs and there is nothing to leak (CeroSecNet.lineBusy).
		if type(data.ring) == "table" then job.ring = data.ring end
		if now ~= nil and ms ~= nil and ms > 0 then
			job.cont = data.cont
			job.timer = true
			job.wakeMs = now + math.floor(ms)
			job.state = "sleeping"
			return true
		end
		job.cont = data.cont
		job.timer = true
		job.wakeMs = 0
		job.state = "sleeping"
		return true
	end
	if control == "prompt" and type(data) == "table" then
		-- A stage that READS a pipe cannot be answered. Its question would come
		-- back through the continuation, and a continuation is one call with a
		-- command's own arguments in it and no pipe behind it -- so `cat f | sudo
		-- cat` would ask for a password and then run a `cat` with nothing on its
		-- input. Refused where it was typed, in the name of the command that
		-- asked -- the same answer `edit` gets, and for the same reason.
		--
		-- A stage with nothing on its input asks like any other command:
		-- `sudo echo hi | cat` puts the password question up on the console
		-- (pipeStep carries it out of the stage) and resumes the stage with the
		-- answer, which is what real sudo does with a pipeline behind it.
		--
		-- And a BACKGROUND job cannot be answered either -- a crontab line or a
		-- `&` -- for the plainer reason that nobody is standing in front of it. Its
		-- question is only ever put up for the job that HOLDS the prompt
		-- (CeroSecJobs.runMachine), so `* * * * * su root` used to leave a job
		-- waiting for an answer that could never come: four of those and the
		-- machine had no job slot left for anything, ever. The same answer `read`
		-- gives one, which is end of file and a status to say so.
		-- ...unless the stage has said it will read NO MORE. `job.stdinBuf.closed`
		-- is the stage's own word for that, set by runSimple out of the reader's
		-- `done` flag, and it is the whole of what the refusal above was about: a
		-- continuation has no pipe behind it, and a stage that has finished reading
		-- has no pipe left to miss. `ls -l | more` is what needs it -- the pager
		-- reads its input to the end and only then puts its first question up.
		if (job.inPipe and job.stdinBuf ~= nil and not job.stdinBuf.closed) or job.bg then
			flushPartial(job)
			local who = "sh"
			if type(data.cont) == "table" and type(data.cont.cmd) == "string" then
				who = data.cont.cmd
			end
			errLine(job, who .. ": not a terminal")
			job.status = 1
			return true
		end
		flushPartial(job)
		job.cont = data.cont
		job.ask = { text = tostring(data.text or ""), mask = data.mask and true or false,
			cont = true }
		job.state = "waiting"
		return true
	end
	-- `sh` inside a script. It does NOT ask the machine for a second job: it
	-- runs here, one level deeper, the way a shell's child would -- so a script
	-- that runs itself meets the depth ceiling in eight lines instead of
	-- filling the machine's four job slots in four.
	--
	-- data.rd is the redirect the line carried, when it carried one, already opened
	-- by the shell (runSimple): the file the script's standard output goes to, which
	-- is the process's and not the word `sh`'s.
	if control == "job" and type(data) == "table" then
		if CeroSecOS.jobRun(job, data.prog, data.args, data.name, false, data.rd,
				data.erd) then
			job.status = 0
		end
		return true
	end
	-- The editor opens on a SCREEN, and a script has none: a job running in the
	-- background has nobody in front of it and a buffer nobody can see is a
	-- machine stuck. The prompt's own job does have one, and is the one job the
	-- order goes through.
	if control == "edit" and not job.interactive then
		flushPartial(job)
		errLine(job, "edit: not a terminal")
		job.status = 1
		return true
	end
	-- rlogin opens a SESSION, and a session is a terminal handed to another
	-- machine: rlogin(1) puts its own terminal into raw mode and hands the far
	-- end everything typed on it, so a job with no terminal has nothing to give
	-- and nowhere to put what comes back. Refused here, where it was written, the
	-- same answer and for the same reason as `edit`.
	--
	-- Without this a crontab line was a way to reach out from a machine nobody
	-- was standing at and land a logged-in session on its physical glass: the
	-- order carries the screen the job was writing to, and for a job with no
	-- session of its own that screen is the machine's own console. A survivor who
	-- walked up found somebody else's computer on it.
	--
	-- cu is the same thing down a telephone line -- a session on the far machine,
	-- on this glass -- so it is refused in the same place and in its own name: a
	-- crontab that could dial out would land a logged-in session on the physical
	-- screen of a machine nobody was standing at, whichever kind of link it used
	-- to get there.
	if (control == "rlogin" or control == "cu") and not jobHasTerminal(job) then
		flushPartial(job)
		errLine(job, control .. ": not a terminal")
		job.status = 1
		return true
	end
	-- The TNC's command mode, which is the third of them and is refused for the
	-- same reason twice over: it is a DIALOG -- a prompt and an answer, with
	-- nobody there to give one -- and what it can be driven to do is open a
	-- session on the far machine on THIS glass. On the air it would be worse than
	-- either of the other two: a crontab that connected out would also key a
	-- transmitter and put two callsigns over the county every time it ran, on a
	-- machine nobody was standing at. Refused here, before the line is opened, so
	-- nothing is transmitted at all. Signed `cu`, because cu is the program.
	if control == "tnc" and type(data) == "table" then
		if not jobHasTerminal(job) then
			flushPartial(job)
			errLine(job, "cu: not a terminal")
			job.status = 1
			return true
		end
		flushPartial(job)
		-- What the BOX says when the line opens, and it is written here rather than
		-- printed by the command: a banner is the thing on the end of a line saying
		-- hello, so a line that was never opened -- a crontab's, a background job's
		-- -- must not have anything to say. It used to be the command's own output
		-- and so reached the mail of a cron line that had just been refused.
		if type(data.lines) == "table" then writeLines(job, data.lines) end
		-- Something only the machine can do to the LINK -- connect, drop, enter
		-- converse, hang up. The job waits on it exactly as an rsh waits on its
		-- dial: off the processor, costing nothing, with the order carried out
		-- after the lines it printed have reached the glass (CeroSecJobs.runMachine
		-- reads job.dial). What comes back is another turn at cmd:, or the end of
		-- the program.
		if type(data.link) == "table" then
			data.link.control = "tnclink"
			job.dial = data.link
			job.state = "waiting"
			job.cpuSince = nil
			return true
		end
		job.cont = data.cont
		job.ask = { text = tostring(data.text or ""), mask = false, cont = true }
		job.state = "waiting"
		return true
	end
	-- rsh WAITS.
	--
	-- It needs no terminal and never has -- it is one command and a pipe back,
	-- which is why a crontab calls rsh and not rlogin -- and it takes no glass
	-- either: the session it opens is for the command's output and not for a pair
	-- of hands. So the order is marked detached whoever gave it, the server points
	-- no console at the far machine, and what the far command printed comes back
	-- into THIS job's output stream (CeroSecOS.jobRemote below) -- the glass for a
	-- line typed at the prompt, the pipe for a stage, the word for a $(...), the
	-- mail for a cron line. One door, the same one everything else this job wrote
	-- went through.
	--
	-- The dial itself is asked OF THE MACHINE, exactly as an `&` is (job.spawn):
	-- only the machine can reach another machine. The job goes to sleep on it --
	-- state "waiting", costing nothing at all, no cpu clock running -- and the far
	-- machine's own budget pays for the far command. When it is done, its lines
	-- and its status arrive and the job runs on at the next line of the script,
	-- which is what rsh has always done. Before this, an rsh ENDED the job that
	-- gave it: `rsh gate date` was the last thing a script ever did, and
	-- `rsh gate hostname | wc -l` answered 0.
	if control == "rsh" and type(data) == "table" then
		flushPartial(job)
		-- Whose output stream the answer belongs in. The ID and not the job: a
		-- stage of a pipeline is a shell of its own that shares its pipeline's id
		-- and is in no job book, and the pipeline is what the machine holds.
		data.noTty = { job = job.id }
		job.dial = data
		job.state = "waiting"
		job.cpuSince = nil
		return true
	end
	-- `clear` is an escape sequence a program writes to its OWN terminal, so a job
	-- with none writes it where everything else it writes goes: into the mail for a
	-- cron line, down the pipe for a stage, into the word for a $(...) -- and this
	-- machine strips control bytes off every line (CeroSecOS.fit), so nothing is
	-- left of it anywhere. What it may not do is wipe the glass of a machine
	-- nobody is standing at: `* * * * * clear` took the screen a survivor was
	-- reading, once a minute, and left no sign of why.
	--
	-- The job runs ON, exactly as it does when the order IS given: the only thing
	-- withheld is the order. `clear` is a program like any other -- `clear; ls`
	-- lists on a fresh screen -- and until SYSTEM_VERSION 20 both halves of this
	-- ended the job instead, so a script's `clear` was the last line of it ever
	-- run.
	if control == "clear" and not jobHasTerminal(job) then
		flushPartial(job)
		return true
	end
	-- An order the machine carries out with the job still running: `clear` on the
	-- glass it was typed at, and `wall` on every terminal of the machine. Both are
	-- ordinary programs -- nothing about either of them ends the thing that ran it
	-- -- and both have to be done by whoever owns the screens, so what is left
	-- here is the queue and the pass is what empties it.
	--
	-- The output goes first (flushPartial), because a broadcast that landed in
	-- front of the line the job was still holding would read as the job's own.
	if CeroSecOS.KNOWN_ORDERS[control] == "machine" then
		flushPartial(job)
		machineOrder(job, control, data)
		return true
	end
	-- clear, edit, shutdown, reboot and exit are the machine's, and whoever is
	-- running the machine is what carries them out -- after the job's own output
	-- has reached the screen, so nothing a player typed is swallowed by the
	-- machine going down.
	--
	-- The job ENDS here, the way a real shell's exec does: a line that has
	-- ordered the machine off has nothing left to say, and the rest of `shutdown;
	-- echo bye` is not something to run on a machine that is going dark. The
	-- WHOLE job, script or no script: `shutdown` two files deep is still the
	-- machine going dark, and unwinding to the file it was written in would
	-- leave the outer one running on a machine that is off. That is what `all`
	-- says, and it is the one exit that does not stop at a script's edge.
	--
	-- And an order NOBODY here knows is refused rather than obeyed. What used to
	-- happen to one was the worst of the three answers at once: the job was ended
	-- with `all` -- the rest of the script gone, silently -- and the name went on
	-- to the server's applyPower, which is the machine's power switch. A `wall`
	-- that belongs in the queue above, a name misspelt in a command, a new order
	-- nobody wired up: all three read as "switch the machine off, and never mind
	-- the rest of the line". The line below is what says so out loud, in the job's
	-- own error stream where a bench and a player both see it.
	if CeroSecOS.KNOWN_ORDERS[control] ~= "exit" then
		flushPartial(job)
		errLine(job, "sh: " .. tostring(control) .. ": unknown order")
		job.status = 1
		if CeroSec ~= nil and CeroSec.log ~= nil then
			CeroSec.log(CeroSec.LOG_WARN,
				"applyControl: unknown order " .. tostring(control))
		end
		return true
	end
	job.control = control
	job.controlData = data
	flushPartial(job)
	job.sig = { k = "exit", n = job.status, all = true }
	return true
end

-- Is this `exit` the one that leaves the MACHINE, or the one that leaves a
-- script? Only the word typed at the glass is the first kind, and "at the glass"
-- is a terminal (jobHasTerminal above: the prompt's own job, outside every pipe
-- and every $(...)) plus one thing more that is `exit`'s alone:
--
--   * the TOP level of it: `./lights.sh` is the prompt's own job one level
--     deeper (CeroSecOS.jobRun), and an `exit 1` inside a file is the file
--     ending with status 1 and the prompt coming back -- which is POSIX, and
--     is the whole reason a usage-and-exit script does not throw a player off
--     the machine.
--
-- Depth is `exit`'s and not rlogin's: a script run in the foreground INHERITS
-- the terminal it was started from, so `rlogin gate` in a file works, while
-- `exit` in a file ends the file.
--
-- ~/.profile is deliberately on the other side of this line: it runs AS the
-- login shell, at depth one, so its `exit` logs out -- which is what bash does
-- with a profile and what the manual says here.
local function exitLeavesTheMachine(job)
	if not jobHasTerminal(job) then return false end
	if job.depth > 1 then return false end
	return true
end

-- The answer to a continuation, whatever woke it: a line somebody typed, or a
-- clock the command itself asked to be woken by. One place, because the two must
-- do the same thing to the job -- the chain's authority, its redirect, its
-- output and the order it may give are the chain's and not the caller's.
local function resumeCont(state, job, text, env)
	local cont = job.cont
	local pending = job.contRedirect
	local erd = job.contErd
	job.cont = nil
	job.contRedirect = nil
	job.contErd = nil
	job.ask = nil
	-- The ring is over, whichever way it ended, so the line is not held any more.
	-- Cleared BEFORE the continuation runs: the continuation of a dial that was
	-- answered asks the world for that line a second time, at the door.
	job.ring = nil
	job.state = "running"
	-- The redirect the line was typed with goes back down with the answer: the
	-- chain is where the command finally runs, and the writing belongs beside
	-- the writing every other command's redirect goes through.
	local ok, lines, control, data =
		CeroSecOS.continue(state, job.session, cont, text, env, pending,
			{ path = CeroSecOS.pathValue(job.vars), tty = pending == nil and toScreen(job) })
	-- A chain that is still asking -- `sudo passwd root > out` -- has still
	-- written nothing, so its redirect waits for the next answer.
	if pending ~= nil and control == "prompt" then job.contRedirect = pending end
	if erd ~= nil and control == "prompt" then job.contErd = erd end
	if ok then
		writeLines(job, lines)
		job.status = 0
	else
		-- A refusal is not output, so in a stage it goes to the screen and
		-- not down the pipe -- the rule every other command already runs on.
		-- And into the file `2>` named, when the line named one.
		local outer = job.errRd
		if erd ~= nil then job.errRd = erd end
		errLines(job, lines)
		job.errRd = outer
		if erd ~= nil and erd.buf ~= nil and #erd.buf > 0 then
			local text = CeroSecOS.linesToText(erd.buf)
			erd.buf = {}
			local errOk, errWrote = CeroSecOS.writeRedirect(state, job.session, erd.who,
				{ path = erd.path, append = true }, text, env)
			if not errOk then errLines(job, errWrote) end
		end
		job.status = 1
	end
	applyControl(job, control, data, env)
end

-- Pathname expansion over a whole field list, in place of the loop this used
-- to be duplicated as: `for f in *.txt` globs the very same way a simple
-- command's arguments do (CeroSecOS.expandGlob's header explains the mask),
-- because a word list is a word list whether `for` reads it or a command does.
-- Second return is the total directory entries the expansion visited, for
-- the caller to charge (see CeroSecOS.GLOB_ENTRIES_PER).
local function globFields(state, session, out, masks)
	local expanded = {}
	local visited = 0
	for i = 1, #out do
		local matches, entries = CeroSecOS.expandGlob(state, session, out[i], masks[i])
		if type(entries) == "number" then visited = visited + entries end
		if matches == nil or #matches == 0 then
			expanded[#expanded + 1] = out[i]
		else
			for m = 1, #matches do expanded[#expanded + 1] = matches[m] end
		end
	end
	return expanded, visited
end

local function runSimple(state, job, f, env)
	local node = f.node

	-- The assignments in front of the command. Their right-hand sides were
	-- expanded without splitting, so each is exactly one field.
	if f.exA ~= nil then
		local values = f.exA.out
		for i = 1, #values do
			local eq = string.find(values[i], "=", 1, true)
			local reason = setVar(job, string.sub(values[i], 1, eq - 1),
				string.sub(values[i], eq + 1))
			if reason ~= nil then
				jobError(job, reason)
				return 1
			end
		end
	end

	-- A COPY of what the words expanded to, because a command that reads a pipe
	-- is run more than once off the same frame: the redirect's target is taken
	-- off the end below, and a second call must find the line as it was written
	-- and not as the first call left it.
	local args = {}
	local masks = {}
	for i = 1, #f.ex.out do
		args[i] = f.ex.out[i]
		masks[i] = f.ex.outMasks[i]
	end
	local redirect, errTarget = nil, nil
	-- The redirect's target is the last word of the expansion -- the `2>` one's,
	-- when there is one, after it (pushNode) -- and it has to be exactly one
	-- field: a target that is two names, or none, is a line the machine cannot
	-- carry out and will not guess at. It is also never globbed -- sh reads a
	-- redirect's target as one word and never a pattern, so it is popped off
	-- here, before the glob stage below ever sees the word it came from.
	local lastWord = #f.ex.words
	if node.errRedirect ~= nil then
		if (f.ex.counts[lastWord] or 0) ~= 1 then
			jobError(job, "ambiguous redirect")
			return 1
		end
		errTarget = { path = args[#args], append = node.errRedirect.append }
		args[#args] = nil
		masks[#masks] = nil
		lastWord = lastWord - 1
	end
	if node.redirect ~= nil then
		if (f.ex.counts[lastWord] or 0) ~= 1 then
			jobError(job, "ambiguous redirect")
			return 1
		end
		redirect = { path = args[#args], append = node.redirect.append }
		args[#args] = nil
		masks[#masks] = nil
	end
	-- Where the two descriptors go (CeroSecOSScript's parseSimple): "1" and "2"
	-- are where they already went, "w" is the file ">" named, "e" the one "2>" did.
	local outGoes = node.out or (redirect ~= nil and "w" or "1")
	local errGoes = node.err or "2"
	if errTarget ~= nil then CeroSecOS.expandTilde(state, job.session, {}, errTarget) end

	if #args == 0 then
		if errTarget ~= nil then
			local openOk, openLines =
				CeroSecOS.openRedirect(state, job.session, "sh", errTarget, env)
			if not openOk then
				errLines(job, openLines)
				job.status = 1
				return CeroSecOS.STEP_COST_COMMAND
			end
		end
		if redirect ~= nil then
			local ok, lines = CeroSecOS.runArgs(state, job.session, {}, redirect, env, nil,
				{ path = CeroSecOS.pathValue(job.vars), tty = false })
			errLines(job, lines)
			if ok then job.status = 0 else job.status = 1 end
			return CeroSecOS.STEP_COST_COMMAND
		end
		if errTarget ~= nil then
			job.status = 0
			return CeroSecOS.STEP_COST_COMMAND
		end
		job.status = 0
		return 1
	end

	-- "~" is the shell's, expanded before the glob stage below sees the word --
	-- POSIX's own order. What it puts in the word is a system path, not
	-- anything the survivor typed, so a word it touched globs no further: a
	-- home directory is never read back as a pattern of its own text.
	local beforeTilde = {}
	for i = 2, #args do beforeTilde[i] = args[i] end
	CeroSecOS.expandTilde(state, job.session, args, redirect)
	for i = 2, #args do
		if args[i] ~= beforeTilde[i] then masks[i] = string.rep("l", #args[i]) end
	end

	-- Pathname expansion. Every field globs, argv[0] included -- the same word
	-- a real sh would hand to execve after its own passes over it -- and a
	-- word with no unquoted "*", "?" or "[" in it, which is nearly every word
	-- anybody types, costs this loop one no-op string scan and nothing more.
	local globVisited
	args, globVisited = globFields(state, job.session, args, masks)

	-- What the glob walk itself cost, on top of the flat command charge every
	-- field already gets: a pattern is run once per entry of every directory
	-- it opened, the same shape a PATH walk's extra directories cost below
	-- (walkCost) and a BRE pattern's bytes cost through sh.cost. Charged as
	-- debt for the same reason those are: `while true; do echo /wide/*; done`
	-- must slow down instead of costing this pass five hundred names for free.
	if type(globVisited) == "number" and globVisited > 0 then
		local globCost = math.floor(globVisited / CeroSecOS.GLOB_ENTRIES_PER)
		if globCost > 0 then
			job.debt = (job.debt or 0) + globCost
			job.steps = job.steps + globCost
		end
	end

	local name = args[1]

	-- What ">" and "2>" name is OPENED here, before anything is looked up or run,
	-- which is the order every sh has: the shell forks, opens the redirections,
	-- and only then execs. So a target that cannot be opened is a command that
	-- never runs -- `rm f > /etc/hosts` leaves f alone -- and one that can is
	-- there, created or emptied, whatever the command does next: `cat nosuch >
	-- out` and `nosuchcmd > out` both leave an empty out, as on any Unix.
	--
	-- Once per command: a pipe reader, or a command that asked for another turn,
	-- comes back through this frame, and must not empty what it has already
	-- written. f.opened is the frame's own and nothing else reads it.
	--
	-- A job saved by 0.6 has no f.opened: its frame said the same thing with
	-- f.rd.wrote, set once the target had been emptied and written. A frame
	-- that carries it is one whose file is open already, so the first turn
	-- under this build adds to it rather than emptying what that job wrote.
	if not f.opened and f.rd ~= nil and f.rd.wrote == true then f.opened = true end
	if not f.opened and (redirect ~= nil or errTarget ~= nil) then
		f.opened = true
		local targets = { redirect, errTarget }
		for i = 1, 2 do
			if targets[i] ~= nil then
				local openOk, openLines =
					CeroSecOS.openRedirect(state, job.session, name, targets[i], env)
				if not openOk then
					errLines(job, openLines)
					job.status = 1
					return CeroSecOS.STEP_COST_COMMAND
				end
			end
		end
	end

	-- The two sinks as a frame or a command is handed them. outFile is the file
	-- the standard output goes to, if a file; errSpec is job.errRd's shape
	-- (routeErr), and nil where the errors go where they already went. Both are
	-- worked out from the job as it is NOW, before anything below changes it,
	-- because `2>&1` and `>&2` mean the other descriptor as the line found it.
	local outFile = nil
	if outGoes == "w" then outFile = redirect elseif outGoes == "e" then outFile = errTarget end
	local errSpec = nil
	if errGoes == "w" or errGoes == "e" then
		local to = redirect
		if errGoes == "e" then to = errTarget end
		errSpec = { path = to.path, who = name, buf = {} }
		-- `> f 2>&1`: ONE open file behind both descriptors, so the lines go into
		-- it in the order they were said. Where the output is caught -- a builtin's
		-- buffer, a frame's file -- the errors join that very buffer (sameOut);
		-- a command that hands its lines back all at once needs no such care.
		if errGoes == outGoes then errSpec.same = true end
	elseif errGoes == "1" then
		errSpec = { out = true, depth = #job.caps, rdto = job.rdto }
	end
	local outerErr = job.errRd
	-- What a frame's standard output becomes: a file, or `>&2`'s copy of the
	-- standard error the call found.
	local frameTarget = nil
	if outFile ~= nil then
		frameTarget = { path = outFile.path, who = name }
	elseif outGoes == "2" then
		frameTarget = { toErr = true, spec = outerErr }
	end

	-- A FUNCTION the shell holds. Looked for before /bin and before the builtins that
	-- are files there (echo, printf, test), which is POSIX's order -- a function is
	-- found after the special built-ins and before everything else -- and AFTER the
	-- words the shell itself is, because `cd`, `exit`, `export` and `read` change the
	-- shell and nothing may stand in front of them.
	--
	-- It runs in THIS shell: no new job, no new variables, no new depth. What is
	-- swapped is the positional parameters, and nothing else at all -- there is no
	-- `local` in a 1993 sh, so a variable a function sets is the shell's.
	if type(job.funcs) == "table" and job.funcs[name] ~= nil
			and not CeroSecOS.isShellWord(name) and not CeroSecOS.SHELL_BUILTINS[name] then
		local body, reason = funcBody(job, name)
		if body == nil then
			errLines(job, CeroSecOS.fit({ name .. ": " .. tostring(reason) }))
			-- A function with no body left is a name nothing answers to: 127, as
			-- for any command not found (see CeroSecOS.notRunStatus).
			job.status = 1
			if reason == "not a function" then job.status = CeroSecOS.notRunStatus("command not found") end
			return 1
		end
		-- The redirect on the call is the FUNCTION's, the way it is a script's: one
		-- sign catches everything the whole of it prints. Opened above, where a
		-- shell opens it, and handed to the frame -- `2>` with it.
		local target = frameTarget
		local kept = {}
		for i = 2, #args do kept[#kept + 1] = args[i] end
		local frame = { k = "block", prog = body, i = 1, func = true, ret = true,
			oldArgs = job.args }
		if target ~= nil then
			frame.hadRdto = true
			frame.oldRdto = job.rdto
		end
		if errSpec ~= nil then
			frame.hadErd = true
			frame.oldErd = job.errRd
		end
		if not pushFrame(job, frame) then return 1 end
		if target ~= nil then job.rdto = CeroSecOS.rdtoOf(target, #job.caps) end
		if errSpec ~= nil then job.errRd = CeroSecOS.sameOut(job, errSpec) end
		job.args = kept
		-- $0 is NOT the function's name: POSIX leaves it the script's, and so does
		-- every sh -- which is why job.name is untouched here.
		return 1
	end

	local builtin = builtins[name]
	-- `exit` at a prompt is not `exit` in a script. In a file, in a $(...) or in
	-- a stage it ends that and nothing else, which is the builtin above; at the
	-- glass it logs the account out or pops an `su`, which is the shell word's
	-- job and always has been. One word, two meanings, and the shell knows which
	-- house it is standing in -- which is a question of DEPTH and not only of
	-- whose job it is.
	if builtin ~= nil and name == "exit" and exitLeavesTheMachine(job) then builtin = nil end
	-- The builtins that are also files in /bin are looked up there FIRST. The
	-- speed of running one inside the engine is an implementation detail; which
	-- commands a machine has is not, and it is written on the disk. So
	-- `rm /bin/sleep` takes sleep away and `chmod 600 /bin/echo` puts echo out
	-- of reach, exactly as they do for `ls`.
	local builtinWalk = 0
	if builtin ~= nil and CeroSecOS.BUILTIN_FILES[name] then
		local refusal, _, walked =
			CeroSecOS.whyNotRun(state, job.session, name, CeroSecOS.pathValue(job.vars))
		-- The same charge as below, for the same reason: a builtin that is a file
		-- in /bin is looked up like any other command, and the walk is what it is.
		if type(walked) == "number" and walked > 1 then builtinWalk = walked - 1 end
		if refusal ~= nil then
			errLines(job, CeroSecOS.fit({ name .. ": " .. refusal }))
			job.status = CeroSecOS.notRunStatus(refusal)
			return 1 + builtinWalk
		end
	end
	if builtin ~= nil then
		-- A builtin writes to the job's own output, so a redirect on one is a
		-- capture: its lines are caught the way $(...) catches them and then
		-- written through the very same door a command's redirect goes through.
		--
		-- Except the dot, which runs a FILE and takes its redirect itself
		-- (BUILTIN_TAKES_REDIRECT): catching what the word printed would catch
		-- nothing and leave the file writing to the glass.
		--
		-- The file was opened above, so what was caught is ADDED to it. `>&2` is
		-- caught the same way and handed to the errors the line found; `2>` is
		-- job.errRd for as long as the builtin runs, and its file written after.
		local ownRedirect = BUILTIN_TAKES_REDIRECT[name] == true
		local catch = not ownRedirect and (outFile ~= nil or outGoes == "2")
		if catch then job.caps[#job.caps + 1] = {} end
		local handRedirect, sinks = nil, nil
		if ownRedirect then
			handRedirect = outFile
			sinks = { target = frameTarget, erd = errSpec }
		elseif errSpec ~= nil then
			job.errRd = errSpec
			if catch then job.errRd = CeroSecOS.sameOut(job, errSpec) end
		end
		local status, fatal = builtin(job, args, state, env, handRedirect, sinks)
		if catch then flushPartial(job) end
		if not ownRedirect then job.errRd = outerErr end
		local sinkOk, sinkLines = true, {}
		if not ownRedirect and errSpec ~= nil and errSpec.buf ~= nil
				and #errSpec.buf > 0 then
			sinkOk, sinkLines = CeroSecOS.writeRedirect(state, job.session, name,
				{ path = errSpec.path, append = true }, CeroSecOS.linesToText(errSpec.buf), env)
		end
		if catch then
			local buf = job.caps[#job.caps]
			job.caps[#job.caps] = nil
			if outFile ~= nil then
				local ok, lines = CeroSecOS.writeRedirect(state, job.session, name,
					{ path = outFile.path, append = true }, CeroSecOS.linesToText(buf), env)
				if not ok then sinkOk, sinkLines = ok, lines end
			else
				errLines(job, buf)
			end
		end
		if not sinkOk then
			errLines(job, sinkLines)
			job.status = 1
			return 1
		end
		if status == nil then
			if fatal ~= nil then jobError(job, fatal) end
			return 1 + builtinWalk
		end
		job.status = status
		return 1 + builtinWalk
	end

	-- The standard input this command has, which on this machine is a pipe and
	-- nothing else: there is no keyboard behind a command, so a stage with no
	-- pipe on its left is a command with no standard input at all.
	--
	-- The reader is handed the frame's own carry, so a command that has to see
	-- all of its input before it can answer -- sort, wc -- keeps what it has
	-- read between one call and the next. `want` is the command saying it IS
	-- reading the pipe (it was given no file), and `done` is it saying it will
	-- read no more, which is what closes the pipe on the stage behind it.
	local stdin = nil
	if job.stdinBuf ~= nil then
		if f.rd == nil then f.rd = { carry = {} } end
		-- open: the writer on the other end of the pipe ended its last line
		-- with no "\n" behind it -- `printf a | cat` -- so a reader that
		-- passes the bytes on (cat) can leave the same line open instead of
		-- closing it with a terminator nothing on the real pipe ever wrote.
		stdin = { lines = job.stdinBuf.lines, eof = job.stdinBuf.eof,
			open = job.stdinBuf.open, carry = f.rd.carry, want = false, done = false }
	end

	-- A command that reads a pipe is run more than once, and a redirect on one
	-- must not truncate the file it has already written to. So the redirect is
	-- not handed to the command at all where there is a pipe: it is carried out
	-- below, through the very same door -- the first write replaces, every one
	-- after it appends, and a call that produced nothing writes nothing.
	-- What the shell knows and the command does not: where a bare name is looked
	-- up, and whether what it writes is going to a screen. A redirect is the third
	-- thing that takes the screen away and is the shell's own half of the line, so
	-- it is answered here rather than inside toScreen.
	--
	-- And the other kind of command that runs more than once: one that has more
	-- work than a pass's budget and hands the machine back rather than doing it
	-- all. `find -exec` is the one there is: it runs COMMANDS, and a command that
	-- ran sixty of them in one call would overspend the budget sixty times over --
	-- the one thing the whole step machine is built to prevent, and the invariant
	-- tests/hostile_test.lua holds every call to.
	--
	-- Two fields say it, on the table the shell already hands down: `again` asks
	-- for another turn and `carry` is what the command wants handed back when it
	-- gets one. Nothing is allocated for a command that asks for neither, which is
	-- every command but that one.
	local resumed = f.rd ~= nil and f.rd.carry ~= nil
	local sh = { path = CeroSecOS.pathValue(job.vars), tty = outFile == nil and toScreen(job),
		keys = jobHasKeyboard(job) }
	if resumed then sh.carry = f.rd.carry end
	-- The redirect is never handed to the command: the file was opened above, so
	-- every write is made HERE and appends -- the first one onto the file the
	-- open emptied, every later one (a pipe reader's, a resumed command's) after
	-- what the one before it wrote. A target must not be truncated twice by one
	-- command, and now it is truncated once, before the command runs.
	-- The errors are job.errRd's for as long as the command runs, and put back
	-- before anything below prints on the shell's behalf.
	if errSpec ~= nil then job.errRd = errSpec end
	local ok, lines, control, data =
		CeroSecOS.runArgs(state, job.session, args, nil, env, stdin, sh)
	if sh.again == true and job.state == "running" then
		if f.rd == nil then f.rd = {} end
		f.rd.carry = sh.carry
		job.again = true
	end
	if stdin ~= nil and stdin.want then
		f.rd.want = true
		-- Everything that was in the pipe has been read: a command is handed
		-- the whole of what is there and takes all of it.
		job.stdinBuf.lines = {}
		job.stdinBuf.bytes = 0
		if stdin.done then job.stdinBuf.closed = true end
		-- Not finished until its input is: the same command runs again next
		-- turn, on whatever the stage to its left has written by then.
		if not stdin.done and not job.stdinBuf.eof then job.again = true end
	end
	-- runArgs' old rule, kept: a command that has not finished -- one that asks,
	-- opens the editor, has handed back a script or gone to wait for another
	-- machine -- has written nothing yet, and what it hands back now is for the
	-- screen. Its redirect is carried below, to where its lines will land.
	local redirectable = control ~= "prompt" and control ~= "edit" and control ~= "job"
		and control ~= "rsh"
	-- Output goes to the file only when the command succeeded; the lines of one
	-- that failed are its errors, and go where errors go. A command that half
	-- failed hands back one list with both in it, and this machine has one
	-- stream: the whole of it is the errors' (docs/SCRIPTING.md).
	-- Except a command that said its lines are output even though it failed
	-- (grep -c counting nothing, sh.outOnFail): routed as output, status 1.
	local asOut = ok or sh.outOnFail == true
	local toErr = false
	if asOut and outFile ~= nil and redirectable then
		local wrote = f.rd ~= nil and f.rd.wrote == true
		-- A device is written even when there is nothing to say, once: it has no
		-- contents for the open to empty, only a state the write puts it into.
		if #lines > 0 or not wrote then
			local wroteOk, wroteLines = CeroSecOS.writeRedirect(state, job.session, name,
				{ path = outFile.path, append = true }, CeroSecOS.linesToText(lines), env)
			if f.rd ~= nil then f.rd.wrote = true end
			lines = wroteLines
			if not wroteOk then
				ok = false
				asOut = false
			end
		else
			lines = {}
		end
	elseif asOut and outGoes == "2" and redirectable then
		toErr = true
	end
	if asOut and not toErr then writeLines(job, lines) end
	if not asOut then errLines(job, lines) end
	-- The command is over, and its `2>` with it: what it said there goes into the
	-- file now, after it, and `>&2`'s output goes to the errors the line found.
	job.errRd = outerErr
	if errSpec ~= nil and errSpec.buf ~= nil and #errSpec.buf > 0 then
		local text = CeroSecOS.linesToText(errSpec.buf)
		errSpec.buf = {}
		local errOk, errWrote = CeroSecOS.writeRedirect(state, job.session, name,
			{ path = errSpec.path, append = true }, text, env)
		if not errOk then
			errLines(job, errWrote)
			ok = false
		end
	end
	if toErr then errLines(job, lines) end
	-- A command that could not be RUN at all -- not found, or found and not
	-- executable -- says so with its own status (sh.status, set by runArgs).
	if ok then job.status = 0 else job.status = sh.status or 1 end

	-- A command that hands back a JOB -- `sh a.sh`, `./a.sh`, a name on PATH that
	-- turned out to be a script -- has printed nothing and never will: what the
	-- redirect names belongs to the PROCESS it started, exactly as it does on a real
	-- machine. The file was opened above, before anything ran, and is handed to the
	-- frame the script runs in (applyControl's "job", CeroSecOS.jobRun) with the
	-- `2>` beside it. A command that failed to start still leaves the file there,
	-- empty, which is what `cat nosuch > f` does on any Unix.
	--
	-- No `append` on it: the open has truncated (or made) the file, so every write
	-- from here on ADDS -- which is what a process writing to an open file does, and
	-- what keeps a script's second line from replacing its first.
	if control == "job" and type(data) == "table" then
		if frameTarget ~= nil then data.rd = frameTarget end
		if errSpec ~= nil then data.erd = errSpec end
	end
	applyControl(job, control, data, env)

	-- A command that has ASKED something has written nothing yet, so runArgs left
	-- its redirect alone -- and the redirect must not be forgotten there, or
	-- `sudo cat /etc/passwd > copie.txt` prints the file on the screen when the
	-- password comes back. The target is opened here, where a shell opens it, and
	-- the pending write is carried on the job until the answer arrives
	-- (CeroSecOS.jobInput). A stage carries its own, which is what puts a
	-- pipeline's position in it: the answer goes to the stage that asked, and the
	-- stage writes where that stage was told to.
	--
	-- Asked of the job and not of the control, because a question the job was
	-- refused -- a stage reading a pipe -- is not a question anybody will answer,
	-- and its redirect is the ordinary one runArgs has already dealt with.
	-- What the lookup cost, on top of the command itself. The first directory is
	-- what STEP_COST_COMMAND was measured on -- every command was a walk of /bin --
	-- so what is charged here is the directories past it, one step each: a walk of
	-- a filesystem is not a table lookup and the budget has to see it.
	local walkCost = 0
	if type(sh.walked) == "number" and sh.walked > 1 then walkCost = sh.walked - 1 end
	-- And what the command itself says its work cost, where a command does work the
	-- price of a command does not cover: `grep` with a real pattern walks every byte
	-- of every line for every piece of it, and a budget that could not see that would
	-- not be a budget (CeroSecOS.BRE_STEPS_PER carries the arithmetic).
	-- Charged as DEBT and not as steps spent on this pass, which is the one thing that
	-- had to be got right: the pass's own invariant is that it may overspend by at
	-- most ONE COMMAND (tests/hostile_test.lua holds every call to it), and a command
	-- reporting five hundred steps of work would break it. The debt is exactly the
	-- machinery for this -- what is overspent is carried and the next passes are that
	-- much shorter -- so the work is paid for afterwards and the average over any run
	-- of passes is still the budget. Counted in job.steps as well, because `ps` shows
	-- that column and a runaway is recognised by it.
	if type(sh.cost) == "number" and sh.cost > 0 then
		job.debt = (job.debt or 0) + sh.cost
		job.steps = job.steps + sh.cost
	end


	-- An rsh is the other command that has written nothing yet: it has gone to
	-- wait for another machine, and the lines it will hand back are the far
	-- command's (CeroSecOS.jobRemote). Same shape, same reason, same file -- opened
	-- above, before the command ran, so a target that cannot be opened never got
	-- as far as asking. The `2>` waits beside it, for the errors the answer brings.
	if job.cont ~= nil or job.dial ~= nil then
		if outFile ~= nil then
			-- append: the open emptied it, and nothing has been written since.
			local pending = { path = outFile.path, append = true, who = name }
			if job.dial ~= nil then job.dialRedirect = pending else job.contRedirect = pending end
		end
		if errSpec ~= nil then
			if job.dial ~= nil then job.dialErd = errSpec else job.contErd = errSpec end
		end
	end
	return CeroSecOS.STEP_COST_COMMAND + walkCost
end

--
-- Pipelines
--
-- `a | b | c` is ONE job with three shells inside it. Each stage is a job table
-- of its own -- its own frames, its own variables, its own status -- which is
-- what a subshell is, and what makes `echo hi | read x` leave x alone in the
-- shell that typed it.
--
-- They do not run one after another. A pipeline whose stages ran in turn would
-- have to hold the whole of one stage's output before the next one started, and
-- `yes | head -1` would never end. So the stages run TOGETHER, a step at a
-- time, and the rule for whose step it is has two halves:
--
--   * the RIGHTMOST stage that can run, runs. A stage that can run is one that
--     is not waiting for a line that is not there yet and is not writing into
--     a pipe that is already full.
--   * a stage whose reader has finished is killed, with 141 -- SIGPIPE, as sh
--     reports it. That is what ends the flood in `yes | head -1`: head reads
--     its one line, closes its input, and the writer dies where it stands.
--     Only a stage that has started and is writing into the pipe: one inside
--     its own call's `>` is writing into a file, and write(2) raises SIGPIPE
--     on a pipe and nothing else.
--
-- Reading right to left is what makes the back-pressure fall out: the last
-- stage runs until it has read everything there is, and only then does the one
-- to its left get a turn to write more.
--
-- Nothing here is concurrent in the sense of two things happening at once --
-- there is one step machine and it takes one step -- and nothing here is a
-- coroutine, which Kahlua does not have. It is a stack of frames with a table
-- of shells hanging off one of them.
--

local stepOnce, handleSignal, flushDone, jobFlush

-- One pipe. lines is what is in it, eof says the stage on the left has
-- finished, closed says the stage on the right will read no more.
local function newPipe()
	return { lines = {}, bytes = 0, eof = false, closed = false }
end

local function pipeFull(buf)
	return #buf.lines >= CeroSecOS.PIPE_LINES or buf.bytes >= CeroSecOS.PIPE_BYTES
end

-- One stage: a shell of its own, on a copy of everything the pipeline's own
-- shell holds. The copy is the point -- it is what a subshell is -- and it is
-- why a `cd`, an assignment or a `read` inside a stage is gone the moment the
-- pipeline is over.
local function newStage(job, node, out, into, last)
	local stage = CeroSecOS.newJob({
		prog = { node }, args = job.args, name = job.name, cmd = job.cmd,
		session = job.session, status = job.status,
		vars = CeroSecOS.copyVars(job.vars),
		-- A stage is a subshell, so it is handed a COPY of the functions the way it
		-- is handed a copy of the variables: `greet | cat` calls the greet the shell
		-- holds, and a definition inside a stage dies with the stage.
		funcs = CeroSecOS.copyFuncs(job.funcs),
	})
	stage.pipe = out
	stage.stdinBuf = into
	-- Whether what this stage writes ends up on a screen. Only the last one can:
	-- its pipe is drained onto whoever is running the pipeline, so it inherits the
	-- answer from there, and every stage in front of it is writing to a command.
	stage.screen = last == true and toScreen(job)
	-- The same process as far as anything a script can ask is concerned: $$ is
	-- the shell's own number and a subshell does not get a new one, and how deep
	-- the scripts are nested is the pipeline's depth and not one more.
	stage.id = job.id
	stage.depth = job.depth
	stage.line = node.line or job.line
	stage.promptLine = job.promptLine
	-- No screen and no keyboard: a stage is not what a person is standing in
	-- front of, so `edit` is refused in one and a `read` with no pipe on its
	-- input reads end of file, exactly as a background job's does.
	stage.inPipe = true
	-- And a stage of a pipeline nobody is standing in front of has no more of a
	-- keyboard than the pipeline: `sudo echo hi | cat` asks at the prompt, the
	-- same line with a `&` behind it has nobody to ask.
	stage.bg = job.bg
	-- Where what goes wrong goes. Not into the pipe: an error is not output.
	stage.errTo = job
	return stage
end

-- What the last stage wrote, onto whatever is running the pipeline: the screen,
-- or the capture an enclosing $(...) has open. The one place a pipeline's output
-- leaves it.
local function drainTail(job, buf)
	local lines = buf.lines
	if #lines == 0 then return end
	local open = buf.open == true
	buf.lines = {}
	buf.bytes = 0
	buf.open = false
	if open then
		-- The pipeline's own last line had no newline behind it: leave it
		-- open on the job draining the pipe too, through the same partial a
		-- builtin's writeText uses, instead of closing it with a "\n" the
		-- pipe never carried (`printf a | cat; echo b` glues onto one line).
		for i = 1, #lines - 1 do outLine(job, lines[i]) end
		writeText(job, lines[#lines])
		return
	end
	for i = 1, #lines do outLine(job, lines[i]) end
end

-- A stage whose reader has gone. sh reports a signal as 128 plus its number and
-- SIGPIPE is 13; nothing is printed, because a writer killed by a pipe closing
-- is the ordinary end of `yes | head -1` and not a fault anybody has to read
-- about.
local function sigpipe(stage)
	stage.partial = ""
	stage.status = CeroSecOS.SIGPIPE_STATUS
	finish(stage, "killed")
end

-- One step of one stage. The stage is an ordinary job and the walker below is
-- the ordinary walker; what is not ordinary is who calls it -- the frame and not
-- the scheduler -- so the pass's own work (the clock, the devices, the debt) is
-- the pipeline's and is not done a second time here.
local function stageStep(state, stage, env)
	if CeroSecOS.jobIsOver(stage) then return 0 end
	if stage.state == "sleeping" then
		local now = CeroSecOS.nowMsOf(env)
		if now == nil or now >= (stage.wakeMs or 0) then
			stage.state = "running"
			stage.wakeMs = nil
		else
			return 0
		end
	end
	if stage.state ~= "running" then return 0 end
	stage.blocked = nil
	local used = stepOnce(state, stage, env)
	if stage.sig ~= nil then handleSignal(stage) end
	return used
end

-- Can this stage take a step at all, this instant?
--
-- Asked BEFORE the walk below picks a stage, because picking one that cannot
-- step is how a sleeping pipeline used to spin: stageStep answers nought for a
-- stage that is asleep, the walk returned that nought as the turn's cost, and
-- the turn had moved nothing -- so the next turn did the same, for as many
-- turns as the pass allowed. A stage with time left on its clock is not a stage
-- to step; it is a stage to WAIT for, which is the tail of pipeStep's job.
local function stageRunnable(stage, env)
	if CeroSecOS.jobIsOver(stage) then return false end
	if stage.state == "sleeping" then
		local now = CeroSecOS.nowMsOf(env)
		return now == nil or now >= (stage.wakeMs or 0)
	end
	return stage.state == "running"
end

-- The stage a question came out of, and the frame that remembers it. A
-- pipeline is one job as far as the machine is concerned -- one screen, one
-- prompt token, one answer -- so the question travels up to the job and the
-- answer has to find its way back down to the shell that asked it. The
-- innermost pipeline first: `$(sudo cat f | head -n 1)` inside another one is
-- answered where it was asked.
local function askingStage(job)
	local frames = job.frames
	if frames == nil then return nil end
	for i = #frames, 1, -1 do
		local f = frames[i]
		if f.k == "pipe" and f.asking ~= nil then
			local stage = f.stages[f.asking]
			if stage ~= nil then return f, stage end
		end
	end
	return nil
end

-- The same, for the stage that is waiting on an rsh. One at a time: the dial
-- travels up to the job because the machine knows nothing of stages, and the
-- answer has to find its way back to the shell that asked for it.
local function dialingStage(job)
	local frames = job.frames
	if frames == nil then return nil end
	for i = #frames, 1, -1 do
		local f = frames[i]
		if f.k == "pipe" and f.dialling ~= nil then
			local stage = f.stages[f.dialling]
			if stage ~= nil then return f, stage end
		end
	end
	return nil
end

-- What the far machine answered, into the job that has been waiting for it.
--
-- The lines go through the job's own door (writeLines), so where they end up is
-- whatever this job was writing to and not this function's business: the glass,
-- the pipe the stage is writing into, the word a $(...) is collecting, the mail a
-- cron line's output goes to. The status is the far command's, which is what `$?`
-- after an rsh means on every machine that has one.
--
-- Answers true when there was a job waiting; the caller has a session to close
-- either way.
-- failed says the lines are a REFUSAL and not output: a dial that never got
-- through is the machine talking, so it goes where every other refusal goes --
-- the screen, and never down a pipe or into a captured word.
-- state and env, when the caller has them, are what a redirect on the rsh needs:
-- `rsh gate date > out` opened `out` when the order was given and the far
-- machine's lines are what goes in it. A caller that hands none writes to the
-- job's own output, which is what a machine with no filesystem to hand could do
-- anyway.
function CeroSecOS.jobRemote(job, lines, status, failed, state, env)
	if type(job) ~= "table" then return false end
	local frame, stage = dialingStage(job)
	local target = job
	if stage ~= nil then
		frame.dialling = nil
		target = stage
	end
	job.dial = nil
	-- The session is over, so the line it was on is not this job's to hang up any
	-- more. Cleared here and not by the machine, because the delivery IS the end of
	-- it -- and a line that has been given back is a line the far machine may hand
	-- to somebody else in the next second.
	job.remote = nil
	-- A stage killed by the pipe closing in front of it (`rsh gate yes | head -1`)
	-- is a stage with nowhere to put what came back. The session still closes.
	if CeroSecOS.jobIsOver(target) then return false end
	local pending = target.dialRedirect
	local erd = target.dialErd
	target.dialRedirect = nil
	target.dialErd = nil
	if type(lines) == "table" then
		if failed then
			-- A refusal is not output and never goes where output was going: not
			-- down a pipe, not into a word, and not into the file `>` named --
			-- only into the one `2>` did, when the line named one.
			local outer = target.errRd
			if erd ~= nil then target.errRd = erd end
			errLines(target, lines)
			target.errRd = outer
			if erd ~= nil and erd.buf ~= nil and #erd.buf > 0 and type(state) == "table" then
				local text = CeroSecOS.linesToText(erd.buf)
				erd.buf = {}
				local errOk, errWrote = CeroSecOS.writeRedirect(state, target.session, erd.who,
					{ path = erd.path, append = true }, text, env)
				if not errOk then errLines(target, errWrote) end
			end
		elseif pending ~= nil and type(state) == "table" then
			local ok, refusal = CeroSecOS.writeRedirect(state, target.session, pending.who,
				pending, CeroSecOS.linesToText(lines), env)
			if not ok then
				errLines(target, refusal)
				status = 1
			end
		else
			writeLines(target, lines)
		end
	end
	if type(status) == "number" then target.status = math.floor(status) end
	flushPartial(target)
	target.state = "running"
	if target ~= job and job.state == "waiting" then job.state = "running" end
	return true
end

-- Is there anything for this stage to read?
local function inputReady(buf)
	if buf == nil then return true end
	return #buf.lines > 0 or buf.eof
end

-- One turn of a pipeline. Answers what the turn cost, the way every other frame
-- does.
local function pipeStep(state, job, f, env)
	local stages, pipes = f.stages, f.pipes
	local n = #stages

	-- What the last stage has written goes out first, so the pipeline's output
	-- reaches the screen at the same rate everything else does.
	drainTail(job, pipes[n])

	-- An order for the machine a stage GAVE AND WENT ON PAST -- a broadcast, a
	-- clear. It travels up to the job at once, and not when the stage is over the
	-- way the orders that end a job do below: the queue is what holds the machine's
	-- act in its place, and a queue left on a stage is a broadcast the pass cannot
	-- see. Every stage, in stage order, so a pipeline with two of them broadcasts
	-- twice.
	for i = 1, n do
		local stage = stages[i]
		if stage.orders ~= nil then
			for k = 1, #stage.orders do
				machineOrder(job, stage.orders[k].control, stage.orders[k].data)
			end
			stage.orders = nil
		end
	end

	-- An rsh a stage has asked for. The machine knows nothing of stages, so the
	-- order travels up to the job and the frame remembers which stage it belongs
	-- to (CeroSecOS.jobRemote sends the answer back down). One at a time: a
	-- pipeline with two rsh in it dials the second when the first is done, and the
	-- stage that is waiting is not a stage the walk below will step.
	if job.dial == nil and f.dialling == nil then
		for i = 1, n do
			local stage = stages[i]
			if stage.dial ~= nil then
				f.dialling = i
				job.dial = stage.dial
				stage.dial = nil
				break
			end
		end
	end

	-- The book-keeping the whole rule below reads: a stage that is over has
	-- written everything it will write, and will read nothing more.
	local over = 0
	for i = 1, n do
		local stage = stages[i]
		if CeroSecOS.jobIsOver(stage) then
			over = over + 1
			pipes[i].eof = true
			if i > 1 then pipes[i - 1].closed = true end
			-- An order the machine has to carry out -- shutdown, clear -- given
			-- inside a stage is still an order: it travels up to the job the
			-- machine is holding, because a stage is not something the machine
			-- knows about. An order the stage went ON past is not one of these: it
			-- is in the queue, which is emptied at the head of every turn.
			if stage.control ~= nil and job.control == nil then
				job.control = stage.control
				job.controlData = stage.controlData
			end
			-- What it wrote into a file of its own goes on the disk now, before the
			-- pipeline is popped and the stage with it: `g() { echo a; exit 3; }; g >
			-- f | wc -l` ends the stage with the call's frame still open, and the
			-- next command must find f whole.
			jobFlush(state, stage, env)
		end
	end

	if over == n then
		-- The status of a pipeline is the status of its LAST stage, which is
		-- what every shell has answered since pipelines existed.
		job.status = stages[n].status
		popFrame(job)
		return 0
	end

	for i = n, 1, -1 do
		local stage = stages[i]
		if not CeroSecOS.jobIsOver(stage) then
			-- SIGPIPE is what WRITING into a pipe nobody reads earns (write(2),
			-- EPIPE), so a stage whose standard output is not the pipe is not
			-- killed for it: one inside its own call's `>` -- `g > f | true` --
			-- writes into f and runs on, as it does under sh. And a stage whose
			-- first command has not run yet is let run it: sh starts every
			-- command of the pipeline, so `echo a > f | true` leaves a in f even
			-- when true was over before echo ever ran here (job.ran, stepOnce).
			if i < n and pipes[i].closed and stage.ran and stage.rdto == nil then
				sigpipe(stage)
				return 0
			end
			if not stageRunnable(stage, env) then
				-- Asleep with time left on its clock, or waiting on something
				-- that is not this turn's business. Nothing to step here; the
				-- walk goes on to the left and, if nothing there can step
				-- either, the tail below parks the whole pipeline.
			elseif stage.blocked == "input" then
				if inputReady(stage.stdinBuf) then
					return stageStep(state, stage, env)
				end
			elseif i < n and pipeFull(pipes[i]) then
				-- Its reader has not taken what is there yet. Nothing to do
				-- here; the stage to the left is no help either, so the loop
				-- walks on and finds the one that is.
			else
				-- A file of the stage's own (`g > f | cat`) is not the pipe and has
				-- no reader to hold it back, and jobStep's forty-line limiter asks
				-- the job and never a stage. So it is written here, at the same
				-- forty lines, or `g() { while true; do echo x; done; }` would
				-- grow one table for as long as the pass lasts.
				local rd, erd = stage.rdto, stage.errRd
				if (rd ~= nil and rd.buf ~= nil and #rd.buf >= CeroSecOS.JOB_OUT_MAX)
						or (erd ~= nil and erd.buf ~= nil
							and #erd.buf >= CeroSecOS.JOB_OUT_MAX) then
					jobFlush(state, stage, env)
					if CeroSecOS.jobIsOver(stage) then return 0 end
				end
				return stageStep(state, stage, env)
			end
		end
	end

	-- Nothing could step because a stage is standing at a question: the question
	-- becomes the pipeline's own and the whole job waits on it, exactly as it
	-- waits when a command that is not in a pipeline asks one. Asked after the
	-- walk and not before it, so a pipeline still drains and still moves what it
	-- can while one of its stages holds a question -- and the answer comes back
	-- through CeroSecOS.jobInput, which hands it to the stage.
	for i = 1, n do
		local stage = stages[i]
		if stage.state == "waiting" and stage.ask ~= nil then
			f.asking = i
			job.ask = stage.ask
			job.state = "waiting"
			job.cpuSince = nil
			return 0
		end
	end

	-- Nothing could step, so the pipeline takes a state of its own -- which is
	-- the whole point of the walk having refused to step a stage that cannot
	-- step. Either the pipeline is ASLEEP -- `sleep 5 | cat` costs nothing for
	-- five seconds, exactly as a bare `sleep` does, and the pipeline's wake is
	-- the earliest of its stages' -- or every stage is waiting on a pipe, and
	-- the pipeline is BLOCKED: the scheduler is told so and skips it for the
	-- rest of the pass at no cost at all. Neither is a reason to kill anything:
	-- the writer of a pipe nobody reads is stopped by SIGPIPE above, when its
	-- reader goes, and not by a turn that found nothing to do.
	local wake = nil
	for i = 1, n do
		local stage = stages[i]
		if stage.state == "sleeping" and type(stage.wakeMs) == "number" then
			if wake == nil or stage.wakeMs < wake then wake = stage.wakeMs end
		end
	end
	if wake ~= nil then
		job.wakeMs = wake
		job.state = "sleeping"
		return 0
	end
	-- Waiting on a pipe is not spending the processor, so the runaway clock
	-- stops, exactly as it stops for a job held back by the screen.
	job.blocked = "input"
	job.cpuSince = nil
	return 0
end

--
-- The walker
--

local function pushNode(job, node)
	job.line = node.line or job.line
	if node.k == "cmd" then
		local words = {}
		for i = 1, #node.words do words[i] = node.words[i] end
		if node.redirect ~= nil then words[#words + 1] = node.redirect.word end
		if node.errRedirect ~= nil then words[#words + 1] = node.errRedirect.word end
		local frame = { k = "cmd", node = node, line = node.line,
			phase = "expand", ex = newExpansion(words, false) }
		if node.assigns ~= nil and #node.assigns > 0 then
			frame.phase = "assign"
			frame.exA = newExpansion(node.assigns, true)
		end
		return pushFrame(job, frame)
	end
	if node.k == "list" then
		return pushFrame(job, { k = "list", node = node, line = node.line, i = 1, phase = "run" })
	end
	if node.k == "pipe" then
		local pipes, stages = {}, {}
		for i = 1, #node.stages do pipes[i] = newPipe() end
		for i = 1, #node.stages do
			stages[i] = newStage(job, node.stages[i], pipes[i], pipes[i - 1],
				i == #node.stages)
		end
		return pushFrame(job, { k = "pipe", node = node, line = node.line,
			stages = stages, pipes = pipes })
	end
	if node.k == "if" then
		return pushFrame(job, { k = "if", node = node, line = node.line, ci = 1, phase = "cond" })
	end
	if node.k == "loop" then
		return pushFrame(job, { k = "loop", node = node, line = node.line, phase = "cond" })
	end
	if node.k == "for" then
		return pushFrame(job, { k = "for", node = node, line = node.line,
			phase = "expand", ex = newExpansion(node.words or {}, false) })
	end
	if node.k == "func" then
		-- A DEFINITION, which makes no frame and runs nothing: it puts the text of the
		-- function in the shell and answers 0, exactly as an assignment does.
		local reason = defineFunc(job, node)
		if reason ~= nil then
			jobError(job, reason)
			return false
		end
		job.status = 0
		return true
	end
	if node.k == "case" then
		-- The subject is expanded WITHOUT field splitting, which is POSIX's rule for
		-- it: `case $file in` is one word however many blanks are in the value, or a
		-- name with a space in it could not be matched at all.
		return pushFrame(job, { k = "case", node = node, line = node.line,
			phase = "word", ci = 1, pi = 1, ex = newExpansion({ node.word }, true) })
	end
	jobError(job, "syntax error")
	return false
end

-- One turn of the machine. Returns how many steps it cost -- 0 for the frame
-- work between commands, 1 for a command or a loop iteration.
stepOnce = function(state, job, env)
	-- Whose turn this is, for the two commands that may ask (CeroSecOS.jobOf).
	-- Written on every turn and for a STAGE as well as for a job, so it is never
	-- last pass's job and never the pipeline instead of the shell in it.
	if type(env) == "table" then env.job = job end
	-- What a call that is over wrote goes on the disk before anything else
	-- runs, so the next command reads the file whole (flushDone).
	if job.rdDone ~= nil and not flushDone(state, job, env) then return 0 end
	local frames = job.frames
	local f = frames[#frames]
	if f == nil then
		finish(job, "done")
		return 0
	end

	if f.k == "block" or f.k == "capture" then
		if f.i > #f.prog then
			popFrame(job)
			return 0
		end
		local node = f.prog[f.i]
		f.i = f.i + 1
		-- A statement with "&" behind it is asked OF THE MACHINE and not run
		-- here: only the scheduler may make a job, because only it knows how
		-- many there already are. The copy is the same statement without its
		-- ampersand, so the job that comes of it does not ask again.
		if node.k == "list" and node.bg then
			job.spawn = { k = "list", line = node.line, items = node.items, ops = node.ops }
			job.spawnLine = node.line
			job.status = 0
			return 0
		end
		pushNode(job, node)
		return 0
	end

	if f.k == "list" then
		if f.phase == "run" then
			local item = f.node.items[f.i]
			if item == nil then
				popFrame(job)
				return 0
			end
			f.phase = "after"
			pushNode(job, item)
			return 0
		end
		-- Back from an item: the operator in front of the next one decides
		-- whether it runs at all.
		while true do
			local op = f.node.ops[f.i]
			if op == nil then
				popFrame(job)
				return 0
			end
			f.i = f.i + 1
			if (op == "&&" and job.status == 0) or (op == "||" and job.status ~= 0) then
				f.phase = "run"
				return 0
			end
		end
	end

	if f.k == "if" then
		if f.phase == "cond" then
			local clause = f.node.clauses[f.ci]
			f.phase = "test"
			pushFrame(job, { k = "block", prog = clause.cond, i = 1 })
			return 0
		end
		if f.phase == "test" then
			if job.status == 0 then
				f.phase = "done"
				pushFrame(job, { k = "block", prog = f.node.clauses[f.ci].body, i = 1 })
				return 0
			end
			f.ci = f.ci + 1
			if f.node.clauses[f.ci] ~= nil then
				f.phase = "cond"
				return 0
			end
			if f.node.otherwise ~= nil then
				f.phase = "done"
				pushFrame(job, { k = "block", prog = f.node.otherwise, i = 1 })
				return 0
			end
			-- No branch ran: an `if` that decided nothing is not a failure.
			job.status = 0
			popFrame(job)
			return 0
		end
		popFrame(job)
		return 0
	end

	if f.k == "loop" then
		if f.phase == "cond" then
			f.phase = "test"
			pushFrame(job, { k = "block", prog = f.node.cond, i = 1 })
			return 0
		end
		if f.phase == "test" then
			local truth = job.status == 0
			if f.node.negate then truth = not truth end
			if not truth then
				job.status = f.last or 0
				popFrame(job)
				return 0
			end
			f.phase = "body"
			pushFrame(job, { k = "block", prog = f.node.body, i = 1 })
			-- The iteration boundary, and the reason `while true; do :; done`
			-- costs the machine exactly one step per turn and never more.
			return 1
		end
		f.last = job.status
		f.phase = "cond"
		return 0
	end

	if f.k == "for" then
		if f.phase == "expand" then
			if f.node.words == nil then
				-- `for x; do` walks the script's own arguments.
				f.words = {}
				for i = 1, #job.args do f.words[i] = job.args[i] end
				f.phase = "iter"
				f.i = 1
				return 0
			end
			local how, reason = expandStep(job, state, f.ex, env)
			if how == nil then
				if reason ~= nil then jobError(job, reason) end
				return 0
			end
			if how == "sub" then return 0 end
			f.words = globFields(state, job.session, f.ex.out, f.ex.outMasks)
			f.ex = nil
			f.phase = "iter"
			f.i = 1
			return 0
		end
		if f.phase == "iter" then
			local value = f.words[f.i]
			if value == nil then
				job.status = f.last or 0
				popFrame(job)
				return 0
			end
			f.i = f.i + 1
			local reason = setVar(job, f.node.var, value)
			if reason ~= nil then
				jobError(job, reason)
				return 0
			end
			f.phase = "body"
			pushFrame(job, { k = "block", prog = f.node.body, i = 1 })
			return 1
		end
		f.last = job.status
		f.phase = "iter"
		return 0
	end

	-- case: the subject expanded once, then the patterns one at a time until one of
	-- them matches -- and not one pattern further. POSIX expands a pattern when it
	-- comes to it, so a $( ) in a clause below the one that matched never runs, and
	-- never costs the job a step.
	if f.k == "case" then
		if f.phase == "word" then
			local how, reason = expandStep(job, state, f.ex, env)
			if how == nil then
				if reason ~= nil then jobError(job, reason) end
				return 0
			end
			if how == "sub" then return 0 end
			f.subject = f.ex.out[1] or ""
			f.ex = nil
			f.phase = "pat"
			return 0
		end
		if f.phase == "pat" then
			local clause = f.node.clauses[f.ci]
			if clause == nil then
				-- No pattern matched, which is not a failure: POSIX gives a case that
				-- decided nothing a status of nought, exactly as an `if` gets one.
				job.status = 0
				popFrame(job)
				return 0
			end
			local pat = clause.pats[f.pi]
			if pat == nil then
				f.ci = f.ci + 1
				f.pi = 1
				return 0
			end
			if f.ex == nil then f.ex = newExpansion({ pat }, true) end
			local how, reason = expandStep(job, state, f.ex, env)
			if how == nil then
				if reason ~= nil then jobError(job, reason) end
				return 0
			end
			if how == "sub" then return 0 end
			local text = f.ex.out[1] or ""
			f.ex = nil
			-- The shell's own three, and the shell's own matcher: `*`, `?` and a
			-- `[...]` set, walked rather than turned into a Lua pattern -- the very
			-- call `find -name` matches with, so a glob means one thing on this
			-- machine wherever it is written.
			-- ONE STEP for the comparison, and that is the whole reason a case is not
			-- free work like an `if`'s frame. A case of forty alternatives really does
			-- forty comparisons, each one an expansion and a walk of two strings, and
			-- the same thing written as forty `[ "$x" = p ]` would cost forty steps --
			-- so this costs forty too, or a loop of them would do forty times the work
			-- the budget believes it is buying. Measured: with the comparison free, a
			-- loop over a forty-pattern case cost 7.6 ms a pass against a ceiling of 4.
			-- Expanding the pattern is still free, like every other expansion; what is
			-- charged is the comparison the expansion was for.
			if CeroSecOS.globMatch(f.subject, text) then
				f.phase = "body"
				pushFrame(job, { k = "block", prog = clause.body, i = 1 })
				return 1
			end
			f.pi = f.pi + 1
			return 1
		end
		-- The clause has run; its status is the case's, which is POSIX's rule.
		popFrame(job)
		return 0
	end

	if f.k == "cmd" then
		if f.phase == "assign" or f.phase == "expand" then
			local ex = f.ex
			if f.phase == "assign" then ex = f.exA end
			local how, reason = expandStep(job, state, ex, env)
			if how == nil then
				if reason ~= nil then jobError(job, reason) end
				return 0
			end
			if how == "sub" then return 0 end
			if f.phase == "assign" then f.phase = "expand" else f.phase = "run" end
			return 0
		end
		-- A command that is reading a pipe with nothing in it yet has not run
		-- and costs nothing: the stage stops where it stands, its frame stays
		-- where it is, and the stage to its left is what runs next.
		if f.rd ~= nil and f.rd.want and job.stdinBuf ~= nil
				and not inputReady(job.stdinBuf) then
			job.blocked = "input"
			return 0
		end
		-- One simple command. One step when the shell answers it itself, and
		-- what a command in /bin costs when it does not.
		--
		-- A command that is still reading its input is not finished with it and
		-- has to run again: its frame goes back exactly as it was, carry and all,
		-- which is what lets `sort` read a pipe a line at a time and still be
		-- one command.
		popFrame(job)
		job.again = nil
		-- A command has run: in a stage, from here on a closed pipe in front of
		-- it is a SIGPIPE (pipeStep), and not before -- the first command opens
		-- its redirect even when the reader is already gone.
		job.ran = true
		local cost = runSimple(state, job, f, env)
		if job.again ~= nil and job.state == "running" then pushFrame(job, f) end
		job.again = nil
		return cost
	end
	if f.k == "pipe" then
		return pipeStep(state, job, f, env)
	end

	jobError(job, "syntax error")
	return 0
end

-- break, continue and exit, carried out by unwinding frames. Never by an
-- error: a signal is an ordinary part of a shell and not a fault.
handleSignal = function(job)
	local sig = job.sig
	job.sig = nil

	-- `return`: out of the nearest FUNCTION, or the nearest file a `.` read, and no
	-- further. With neither around it, it is an `exit` -- see the builtin.
	if sig.k == "return" then
		local at = nil
		for i = #job.frames, 1, -1 do
			local f = job.frames[i]
			if f.func or f.ret then
				at = i
				break
			end
			-- A subshell is a wall: `$(return)` returns from nothing outside itself.
			if f.k == "capture" then break end
		end
		if at ~= nil then
			while #job.frames >= at do popFrame(job) end
			job.status = sig.n
			return
		end
		sig = { k = "exit", n = sig.n }
	end

	if sig.k == "exit" then
		-- `exit` ends the INNERMOST thing there is to end, which is POSIX: the
		-- script it is written in, or the subshell it is written in, whichever
		-- is nearer. A $(...) is a capture frame and a script is a frame with
		-- the caller's arguments hanging off it (CeroSecOS.jobRun) -- so `sh
		-- b.sh` with an `exit 3` in it ends b, hands a.sh a $? of 3, and a.sh
		-- goes on with its next line. Only an `exit` with nothing of either
		-- kind around it is the end of the job.
		--
		-- `all` is the one exception and it is not really an exit at all: it is
		-- an order to the machine (shutdown, clear, a logout) travelling out
		-- through this door, and those end everything.
		local at = nil
		if not sig.all then
			for i = #job.frames, 1, -1 do
				local f = job.frames[i]
				-- A FUNCTION frame is not one of them, though it keeps the caller's
				-- arguments like a script's: `exit` inside a function ends the shell or
				-- the script it is in, which is POSIX and is the whole difference between
				-- it and `return`.
				if f.k == "capture" or (f.oldArgs ~= nil and not f.func) then
					at = i
					break
				end
			end
		end
		if at ~= nil then
			while #job.frames >= at do popFrame(job) end
			job.status = sig.n
			return
		end
		job.status = sig.n
		finish(job, "done")
		return
	end

	-- A break with no loop around it is a break that does nothing, exactly as
	-- it does nothing in a real shell.
	local loops = 0
	for i = 1, #job.frames do
		local k = job.frames[i].k
		if k == "capture" then loops = 0 end
		if k == "loop" or k == "for" then loops = loops + 1 end
	end
	if loops == 0 then return end

	local n = sig.n
	if n > loops then n = loops end
	while #job.frames > 0 do
		local f = job.frames[#job.frames]
		if f.k == "loop" or f.k == "for" then
			n = n - 1
			if n == 0 then
				if sig.k == "break" then
					popFrame(job)
				elseif f.k == "loop" then
					f.last = job.status
					f.phase = "cond"
				else
					f.last = job.status
					f.phase = "iter"
				end
				return
			end
		end
		popFrame(job)
	end
end

-- Where the job IS, in as few characters as reading it costs.
--
-- Two turns that answer the same thing here, with no step spent between them,
-- are two turns that did nothing -- and a third would do nothing either, so the
-- pass ends. What it reads is everything a turn can move without spending a
-- step: the job's state and what it is blocked on, how deep the frame stack is
-- and where the top frame stands (the program counter), and -- because a
-- pipeline's turn moves its stages and not the job -- what every stage of a
-- pipe frame is doing. Built only on a turn that spent nothing, which on an
-- ordinary pass is a handful of turns at most, so the normal path pays nothing
-- for it.
-- Where one shell stands: how deep its frames go and what the frame on top of
-- them is busy with. The program counter, for a job or for one stage of a
-- pipeline -- which is a job.
local function frameKey(job)
	local frames = job.frames
	local n = #frames
	local f = frames[n]
	if f == nil then return n .. " -" end
	local key = n .. " " .. tostring(f.k) .. " " .. tostring(f.phase) .. " " ..
		tostring(f.i) .. " " .. tostring(f.node)
	-- A word being expanded is a turn's worth of progress that costs no step, so
	-- where the expansion has got to is part of where the shell stands.
	-- A sum with a $( ) in it stands still at one part while its pieces are run,
	-- so where THAT has got to is part of where the shell stands too (ex.ai, and
	-- the text it has gathered). Without it two turns inside `$(($(date +%s) + 1))`
	-- read the same, and the pass would end on a job that was getting somewhere.
	if f.ex ~= nil then
		key = key .. " " .. tostring(f.ex.wi) .. " " .. tostring(f.ex.pi) ..
			" " .. #f.ex.fields .. " " .. #f.ex.buf ..
			" " .. tostring(f.ex.ai) .. " " .. #(f.ex.abuf or "")
	end
	if f.exA ~= nil then
		key = key .. " " .. tostring(f.exA.wi) .. " " .. tostring(f.exA.pi) ..
			" " .. #f.exA.fields .. " " .. #f.exA.buf ..
			" " .. tostring(f.exA.ai) .. " " .. #(f.exA.abuf or "")
	end
	-- Which clause it is on, and which pattern of it: a `case` walks its patterns a
	-- turn at a time and spends no step doing it, and an `if` walks its elifs the
	-- same way. Without this a case of forty patterns looked the same on two turns
	-- running and the pass ended on a job that was getting somewhere -- so it took
	-- three passes to do what one should.
	if f.ci ~= nil then key = key .. " c" .. f.ci .. " " .. tostring(f.pi) end
	return key
end

local function progressKey(job)
	-- The redirect's buffer counts with job.out: a script whose output the shell
	-- pointed at a file is writing there instead of onto the glass, and a turn that
	-- put a line in it is a turn that got somewhere.
	local held = #job.out
	if job.rdto ~= nil then held = held + #job.rdto.buf end
	if job.errRd ~= nil and job.errRd.buf ~= nil then held = held + #job.errRd.buf end
	local key = tostring(job.state) .. " " .. tostring(job.blocked) ..
		" " .. held .. " " .. #(job.partial or "") .. " " .. frameKey(job)
	local frames = job.frames
	local f = frames[#frames]
	if f ~= nil and f.stages ~= nil then
		for i = 1, #f.stages do
			local stage = f.stages[i]
			key = key .. " |" .. tostring(stage.state) .. " " .. tostring(stage.blocked) ..
				" " .. tostring(stage.steps) .. " " .. #f.pipes[i].lines ..
				" " .. tostring(f.pipes[i].eof) .. " " .. frameKey(stage)
		end
	end
	return key
end

--
-- The one entry point the scheduler uses.
-- What a redirected script has written, onto the disk. Called at the end of the
-- pass, because that is where a filesystem and a clock are to be had: outLine is
-- handed a job and nothing else, so it buffers and this writes.
--
-- Every write APPENDS. The shell truncated the target when it opened it (runSimple)
-- so the first pass adds to an empty file, and a pass that replaced instead of
-- adding would lose everything the pass before it wrote.
--
-- A write that cannot be made -- the file at its 4096 bytes, the disk at its 64K,
-- root having taken the directory away under the job -- is the end of the output,
-- so it is the end of the job: 4.4BSD sends SIGXFSZ for the first of those and the
-- default action is to terminate, and a script that went on running with nowhere to
-- write would be doing work nobody can ever read. The refusal goes to the SCREEN,
-- where every other refusal about a redirect goes.
local function flushOne(state, job, to, env)
	if #to.buf == 0 then return true end
	-- Every line in this chunk gets its own "\n" behind it -- writeFile's
	-- append is a raw concat now the file carries its own terminators -- and
	-- so does the LAST one, unless it is truly the job's own unterminated
	-- last line (to.open, set by outLine's partial flush): `printf a > f`
	-- leaves f without one, `echo a > f` does not.
	local text = table.concat(to.buf, "\n")
	if not to.open then text = text .. "\n" end
	to.buf = {}
	to.open = false
	local ok, lines = CeroSecOS.writeRedirect(state, job.session, to.who,
		{ path = to.path, append = true }, text, env)
	if ok then return true end
	-- Not into the very file that just refused: the refusal goes where errors
	-- went before it was opened.
	if job.errRd == to then job.errRd = nil end
	errLines(job, lines)
	return false
end

-- The files of calls that are OVER (popFrame's rdDone), written now. Called
-- before every step as well as at the end of the pass: `h > o; wc -l o` ran
-- wc on the same pass h ended, before the last of h's lines had reached the
-- disk, and counted 80 of 100. A closed file is a whole file. Only these: the
-- redirect still open keeps its buffer to the end of the pass, so a pass makes
-- the same writes it did and only WHEN moves. false when a write was refused,
-- and the job is over then, as jobFlush has always ended it.
flushDone = function(state, job, env)
	local done = job.rdDone
	if done == nil then return true end
	job.rdDone = nil
	local good = true
	for i = 1, #done do
		if not flushOne(state, job, done[i], env) then good = false end
	end
	if not good and not CeroSecOS.jobIsOver(job) then
		job.rdto = nil
		job.errRd = nil
		job.status = 1
		finish(job, "done")
	end
	return good
end

jobFlush = function(state, job, env)
	local bad = false
	if not flushDone(state, job, env) then bad = true end
	if job.rdto ~= nil then
		if not flushOne(state, job, job.rdto, env) then bad = true end
	end
	if job.errRd ~= nil and job.errRd.buf ~= nil then
		if not flushOne(state, job, job.errRd, env) then bad = true end
	end
	if bad and not CeroSecOS.jobIsOver(job) then
		job.rdto = nil
		job.errRd = nil
		job.status = 1
		finish(job, "done")
	end
	-- And the files the STAGES of a running pipeline hold: `g > f | cat` is
	-- g writing into its own f from inside a stage (outLine), which is a job
	-- the scheduler never sees, so the pass that ends writes its lines too --
	-- the same once a pass the shell's own file gets. Bounded by how deep the
	-- frames go (MAX_FRAMES), like every other walk of them.
	local frames = job.frames
	if frames == nil then return end
	for i = 1, #frames do
		local stages = frames[i].stages
		if frames[i].k == "pipe" and stages ~= nil then
			for k = 1, #stages do jobFlush(state, stages[k], env) end
		end
	end
end

--
-- Runs at most `budget` steps and answers with the job's status and what it
-- cost. Re-entrant by construction: everything it needs is on the job.
--
function CeroSecOS.jobStep(state, job, env, budget)
	if type(job) ~= "table" then return "error", 0 end
	if job.state == "done" or job.state == "killed" or job.state == "error" then
		return job.state, 0
	end
	if type(state) ~= "table" or state.fs == nil then
		jobError(job, "no filesystem")
		return job.state, 0
	end

	local now = CeroSecOS.nowMsOf(env)
	if job.state == "sleeping" then
		if now == nil or now >= (job.wakeMs or 0) then
			job.state = "running"
			job.wakeMs = nil
			job.cpuSince = now
			-- A wait a COMMAND asked for rather than a `sleep` somebody typed:
			-- the continuation it left behind is answered here, with nothing
			-- typed, and the waking costs the one step a builtin costs.
			if job.timer then
				job.timer = nil
				resumeCont(state, job, "", env)
				jobFlush(state, job, env)
				return job.state, 1
			end
		else
			return "sleeping", 0
		end
	end
	if job.state == "waiting" then return "waiting", 0 end
	if job.spawn ~= nil then return "running", 0 end
	-- An order for the machine that the machine has not carried out yet. The job
	-- is not over and not asleep -- it has simply called a program that the server
	-- runs -- and it waits here for the same reason an `&` waits: what comes after
	-- the line must not be written before the machine has done the line.
	if job.orders ~= nil then return "running", 0 end

	if type(budget) ~= "number" or budget < 1 then budget = 1 end
	if job.cpuSince == nil then job.cpuSince = now end

	-- The debt.
	--
	-- A step is only counted once it has been taken, and a command out of /bin
	-- costs thirty-two of them -- so a job that starts one with three steps left
	-- in its budget overspends by twenty-nine. That cannot be helped without
	-- knowing a command's price before running it, and it must not be allowed to
	-- add up: what is overspent is carried, and the next pass is that much
	-- shorter. Over any run of passes the average is exactly the budget, and the
	-- most one pass can go over is one command.
	local owed = job.debt or 0
	if owed > 0 then
		if owed >= budget then
			job.debt = owed - budget
			return job.state, 0
		end
		budget = budget - owed
		job.debt = 0
	end

	-- The devices under /dev exist for the length of this pass, exactly as they
	-- exist for the length of one command at the prompt.
	CeroSecOS.mountDev(state, env)

	local used = 0
	-- The belt on the free work between commands: pushing and popping frames
	-- costs no step, and is bounded by the program's own size, but a guard that
	-- cannot be reasoned away is cheaper than the argument that it cannot run
	-- away.
	local turns, maxTurns = 0, budget * 8 + 1000
	-- What the job looked like after the last turn that spent nothing. Two of
	-- those in a row with the same answer is a turn that moved nothing at all,
	-- and the pass ends there rather than doing it again until maxTurns -- which
	-- is what `sleep 300 | cat` did, nineteen thousand times a pass. maxTurns
	-- stays as the last resort behind this, and says so when it is reached.
	--
	-- Not on the first free turn, and not on the thirtieth: free work between
	-- commands is ORDINARY -- pushing a frame, popping a finished block,
	-- expanding a word -- and reading where the job stands costs several of those
	-- turns. So the reading starts only once the run of them is longer than any
	-- one command's worth, which is a run an ordinary pass does not have and a
	-- spin has for ever. Measured: with the reading on every free turn, a pass of
	-- `while true; do x=1; done` cost a quarter more than it had; with this, it
	-- costs what it costed.
	local zeroRun, zeroKey = 0, nil
	-- A signal left behind by something that ran OUTSIDE the loop -- the answer
	-- to a question, which goes through jobInput -- is dealt with before a step
	-- is taken, or `sudo shutdown` would run one more command after the machine
	-- had been ordered off.
	if job.sig ~= nil then handleSignal(job) end
	while used < budget and job.state == "running" and turns < maxTurns do
		turns = turns + 1
		if job.spawn ~= nil then break end
		if job.orders ~= nil then break end
		-- The flood limiter, and the file's own half of it. A script whose output
		-- the shell pointed at a file is not writing onto the glass, so #job.out
		-- stays at nought for ever and the limiter that bounds every other flood
		-- would never fire: `while true; do echo x; done > f` would grow one Lua
		-- table without a ceiling for the whole pass. The buffer meets the same
		-- forty lines and the pass ends so that jobFlush can empty it.
		local screenFull = #job.out >= CeroSecOS.JOB_OUT_MAX
		local fileFull = job.rdto ~= nil and #job.rdto.buf >= CeroSecOS.JOB_OUT_MAX
		-- And the file `2>` named for the function or script running now: the
		-- same buffer, the same forty lines.
		if job.errRd ~= nil and job.errRd.buf ~= nil
				and #job.errRd.buf >= CeroSecOS.JOB_OUT_MAX then
			fileFull = true
		end
		if screenFull or fileFull then
			job.blocked = "output"
			-- Waiting on the screen is not spending the processor, so the
			-- runaway clock starts again when it runs again. Waiting on the DISK is
			-- different: nothing is holding the job back but the end of this pass, and
			-- a loop redirected at a device -- which never fills up, having no
			-- contents -- would otherwise run for ever with the clock stopped. So the
			-- clock is only stopped for the screen.
			if screenFull then job.cpuSince = nil end
			break
		end
		job.blocked = nil
		local spent = used
		used = used + stepOnce(state, job, env)
		if job.sig ~= nil then handleSignal(job) end
		-- A pipeline with nothing it can do this instant -- every stage waiting
		-- on a pipe -- is not something to spin on for the rest of the budget.
		if job.blocked == "input" then break end
		if used == spent then
			zeroRun = zeroRun + 1
			if zeroRun > CeroSecOS.FREE_TURNS_BEFORE_READING then
				local key = progressKey(job)
				if key == zeroKey then break end
				zeroKey = key
			end
		else
			zeroRun, zeroKey = 0, nil
		end
	end
	if turns >= maxTurns then
		-- The belt held where the braces should have. Nothing is broken by it --
		-- the pass ends, which is what it is for -- but a job that reaches it is
		-- a job whose turns move nothing that progressKey can see, and that is
		-- worth knowing about.
		if CeroSec ~= nil and CeroSec.log ~= nil then
			CeroSec.log(CeroSec.LOG_WARN, "jobStep: maxTurns reached on job " .. tostring(job.id) ..
				" (" .. tostring(job.cmd) .. ")")
		end
	end
	job.steps = job.steps + used
	if used > budget then job.debt = (job.debt or 0) + used - budget end

	if job.state == "waiting" or job.state == "sleeping" then job.cpuSince = nil end
	if job.state == "done" or job.state == "error" then flushPartial(job) end

	-- And what a redirected script wrote goes on the disk, after the pass rather
	-- than at every line: a write is a walk of the filesystem and a job that wrote
	-- forty lines this pass must not do forty of them.
	jobFlush(state, job, env)

	CeroSecOS.unmountDev(state, env)
	return job.state, used
end

-- A line the MACHINE has to say about a job -- "too many jobs" when the job
-- asked for one it cannot have. It goes in the job's own output queue and not
-- straight onto the screen, so it drains at the same twenty lines a second as
-- everything else and a loop full of refusals is as quiet as a loop full of
-- echoes.
-- It is a line ABOUT the job and not the job's output, so it goes where a refusal
-- goes: the screen, never the file a redirected script is writing into.
function CeroSecOS.jobSay(job, line)
	outLine(job, line, true)
end

-- Has this job been on the processor without a break for longer than it may
-- be? Answered here rather than in the scheduler so the number and the rule
-- live together, and so a test can ask it without a server.
function CeroSecOS.jobOverCpu(job, nowMs, limitS)
	if type(job) ~= "table" or job.cpuSince == nil then return false end
	if type(nowMs) ~= "number" then return false end
	if type(limitS) ~= "number" then return false end
	return nowMs - job.cpuSince > limitS * 1000
end

-- The answer to whatever the job asked: a `read`, or a question a command of
-- its own put up (sudo's password). Same shape either way, because the console
-- cannot tell them apart and must not have to.
function CeroSecOS.jobInput(state, job, text, env)
	if type(job) ~= "table" or job.state ~= "waiting" then return false end
	if type(text) ~= "string" then text = "" end
	-- The answer runs a command outside the walker's loop, so the job it belongs
	-- to is named here as well (see stepOnce): `sudo sh nightly.sh` runs its `sh`
	-- when the password comes back.
	if type(env) == "table" then env.job = job end

	-- A question a STAGE of a pipeline asked. The answer is the stage's, not the
	-- pipeline's: the frame remembers which one asked and the stage is fed the
	-- way any other job is, so its own continuation, its own redirect and its own
	-- pipe all still belong to it.
	local frame, stage = askingStage(job)
	if stage ~= nil then
		frame.asking = nil
		job.ask = nil
		job.state = "running"
		return CeroSecOS.jobInput(state, stage, text, env)
	end

	if job.cont ~= nil then
		resumeCont(state, job, text, env)
		return true
	end

	local ask = job.ask
	if ask == nil then
		job.state = "running"
		return false
	end
	job.ask = nil
	job.state = "running"
	local value = text
	if ask.count ~= nil then value = string.sub(text, 1, ask.count) end
	-- A question asked before read took several names (a job saved waiting on
	-- one) still carries the one name it had.
	local names = ask.names
	if names == nil then names = { ask.var } end
	if ask.one then value = string.sub(text, 1, 1) end
	-- And read the line as it stood, which is what it did then.
	local raw = ask.raw == true or ask.names == nil
	local reason = assignFields(job, names, value, raw)
	if reason ~= nil then
		jobError(job, reason)
		return true
	end
	job.status = 0
	return true
end

-- A job held on `wait` whose jobs have all gone.
function CeroSecOS.jobWaitDone(job, jobs)
	if job.waitFor == nil then return true end
	for i = 1, #job.waitFor do
		local id = job.waitFor[i]
		for k = 1, #jobs do
			local other = jobs[k]
			if other.id == id and other ~= job and other.state ~= "done"
					and other.state ~= "killed" and other.state ~= "error" then
				return false
			end
		end
	end
	return true
end

-- A nested script: `sh` inside a job runs in the SAME job, one level deeper.
-- No second job is made, because a script that runs itself would otherwise be
-- a machine full of jobs in four lines.
--
-- inPlace is the DOT command: `. file` reads the file in the shell that is
-- standing there, so it keeps that shell's arguments and -- the whole point of
-- it -- its variables, and what the file sets is still set afterwards. It is
-- still a level deeper, because a file that dots itself must meet the ceiling
-- like a file that runs itself.
--
-- Everything else is a PROGRAM, and a program is handed a COPY of the
-- environment: the exported names and their values, and nothing else the shell
-- was holding. What it sets never comes back, which is the rule the dot command
-- exists to get round -- on this machine as on the one it is copied from.
-- target, when the line that started the file carried a redirect, is where its
-- STANDARD OUTPUT goes: { path, append, who }. A process's redirect belongs to the
-- process, so a script started by `sh a.sh > out` writes into `out` and not onto
-- the glass -- and a script started from inside that one inherits it, because
-- nothing closed it. Before this the redirect belonged to the word `sh`, which
-- prints nothing, so `out` came out empty and the script's own lines went to the
-- screen. The pipe and the capture were never wrong: those are doors on the JOB,
-- and a script runs in the job that asked for it.
-- What a frame's standard output is, made from what the shell opened for it: a
-- file ({ path, who }), or `>&2`'s copy of the standard error the call found
-- ({ toErr, spec }, which outLine hands to routeErr). The buffer is there on
-- both, empty on the second, so everything that counts it counts nought. depth is
-- how many $( ) captures were open when it was, which is what lets it win over
-- them (capturing).
function CeroSecOS.rdtoOf(target, depth)
	if target.toErr then
		return { toErr = true, spec = target.spec, buf = {}, depth = depth }
	end
	return { path = target.path, who = target.who, buf = {}, depth = depth }
end

-- The `2>` of a line that sent both descriptors into one file, turned into
-- `2>&1` on the output as it is NOW -- the catch buffer on top of job.caps, or
-- the frame's own job.rdto -- so the two share one buffer and keep their order.
-- Any other spec is handed back as it is.
function CeroSecOS.sameOut(job, spec)
	if not spec.same then return spec end
	return { out = true, depth = #job.caps, rdto = job.rdto }
end

function CeroSecOS.jobRun(job, prog, args, name, inPlace, target, erd)
	if job.depth >= CeroSecOS.SCRIPT_DEPTH_MAX then
		jobError(job, "too deeply nested")
		return false
	end
	job.depth = job.depth + 1
	-- `ret` marks the frame `return` may leave: POSIX gives it a function and the file
	-- a dot read, and a file run as a PROGRAM is neither -- `return` in one is the end
	-- of the script, which is what `exit` does there too.
	local frame = { k = "block", prog = prog, i = 1, deep = true,
		oldName = job.name, ret = inPlace == true }
	if target ~= nil then
		frame.hadRdto = true
		frame.oldRdto = job.rdto
	end
	-- And the `2>` the line carried, the process's as much as its `>` is.
	if erd ~= nil then
		frame.hadErd = true
		frame.oldErd = job.errRd
	end
	local kept = nil
	if not inPlace then
		kept = {}
		for i = 1, #args do kept[i] = args[i] end
		frame.oldArgs = job.args
		frame.oldVars = job.vars
		frame.oldNvars = job.nvars
		frame.oldExported = job.exported
		-- And the FUNCTIONS: a script is a new sh, and a new sh has none. POSIX is
		-- plain about it -- a function is not in the environment, so nothing carries
		-- one to a child -- and `. file` is the one way a file's definitions land in
		-- the shell that asked for them, which is the whole reason the dot exists.
		frame.oldFuncs = job.funcs
		frame.oldFprog = job.fprog
		frame.hadFuncs = true
	end
	if not pushFrame(job, frame) then
		job.depth = job.depth - 1
		return false
	end
	if target ~= nil then job.rdto = CeroSecOS.rdtoOf(target, #job.caps) end
	if erd ~= nil then job.errRd = CeroSecOS.sameOut(job, erd) end
	job.name = name
	if not inPlace then
		job.args = kept
		job.funcs = nil
		job.fprog = nil
		local child = CeroSecOS.exportedVars(job.vars, job.exported)
		local n = 0
		for _, _ in pairs(child) do n = n + 1 end
		job.vars = child
		job.nvars = n
		-- Every variable a child was handed is in the child's environment, so
		-- what it passes on again is what it was given plus what it exports. A
		-- COPY of the set, because a script's `export` is the script's.
		job.exported = CeroSecOS.copyExported(job.exported)
	end
	return true
end

--
-- What a job looks like from the outside
--

local STATE_LETTER = {
	running = "R", sleeping = "S", waiting = "W",
	done = "Z", killed = "Z", error = "Z",
}

function CeroSecOS.jobLetter(job)
	if job.blocked == "output" then return "O" end
	-- A pipeline waiting on a pipe is asleep in the kernel, and that is the
	-- letter every ps has printed for it: S.
	if job.blocked == "input" then return "S" end
	return STATE_LETTER[job.state] or "R"
end

function CeroSecOS.jobWord(job)
	if job.state == "running" and job.blocked == "output" then return "output" end
	if job.state == "running" and job.blocked == "input" then return "sleeping" end
	-- A wait of its own, and worth its own word: a job held on an rsh is waiting
	-- for ANOTHER MACHINE and not for somebody at this keyboard to type
	-- something. One word, like "output" above and for the same reason -- the
	-- column `jobs` prints it in is eight characters wide, because the row after
	-- it is the line that was typed and the screen is sixty.
	if job.state == "waiting" and (job.dial ~= nil or job.remote ~= nil) then
		return "remote"
	end
	return job.state
end

function CeroSecOS.jobIsOver(job)
	return job.state == "done" or job.state == "killed" or job.state == "error"
end

--
-- The commands
--

-- How a refusal about a script is signed. `sh notes` is sh's refusal about a
-- file; `./notes` is the file's own, and signing that one "sh:" would name a
-- command the player never typed.
local function scriptLabel(who, path)
	if who == path then return path end
	return who .. ": " .. path
end

-- The script a name points at, as text. needX says whether it has to be
-- executable (./thing) or merely readable (sh thing).
-- text, or nil plus the line to print.
function CeroSecOS.readScript(state, session, who, path, needX)
	local label = scriptLabel(who, path)
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node == nil then return nil, label .. ": " .. reason end
	if node.type == "dir" then return nil, label .. ": is a directory" end
	if node.type ~= "file" then return nil, label .. ": " .. CeroSecOS.notAFile(node) end
	if needX and not CeroSecOS.can(state, session, node, "x") then
		return nil, label .. ": permission denied"
	end
	if not CeroSecOS.can(state, session, node, "r") then
		return nil, label .. ": permission denied"
	end
	return node.data or ""
end

-- The order that makes a job. Handed back by `sh`, by `./thing` and by `wait`,
-- and carried out by whoever is running the machine: the engine has no job
-- book of its own, on purpose -- a job outlives a command and belongs to the
-- machine, not to the line that typed it.
function CeroSecOS.jobOrder(name, prog, args, cmd)
	return true, {}, "job", { name = name, prog = prog, args = args, cmd = cmd }
end

-- sh <file> [args]. The file is read, parsed and handed over as a program; a
-- script that will not parse never becomes a job.
function CeroSecOS.startScript(state, session, who, path, args, line, env, needX)
	local jobs = CeroSecOS.jobsOf(env)
	-- The jobs in the way, which do not include the one this `sh` is running in:
	-- a script runs INSIDE the job that asked for it (CeroSecOS.jobRun) and asks
	-- the machine for no second one, so counting the asker made the fourth
	-- `./thing &` refuse itself while the fourth typed loop went through.
	if CeroSecOS.liveJobs(jobs, CeroSecOS.askingId(env)) >= CeroSecOS.MAX_JOBS then
		return false, { who .. ": too many jobs" }
	end

	local text, refusal = CeroSecOS.readScript(state, session, who, path, needX)
	if text == nil then return false, { refusal } end

	local name = CeroSecOS.baseNameOf(path)
	local prog, reason, where = CeroSecOS.parseScript(text)
	if prog == nil then return false, { CeroSecOS.scriptError(name, reason, where) } end

	return CeroSecOS.jobOrder(name, prog, args, line)
end

-- The last component of a path, for what a script calls itself in an error.
function CeroSecOS.baseNameOf(path)
	local out = path
	while true do
		local p = string.find(out, "/", 1, true)
		if p == nil then break end
		out = string.sub(out, p + 1)
	end
	if out == "" then return path end
	return out
end

-- How many jobs one machine may have at once. Four is what a screen a hundred
-- lines deep and a prompt one line wide can be asked to keep track of.
CeroSecOS.MAX_JOBS = 4

commands.sh = function(state, session, args, env)
	if #args < 2 then
		return false, { "sh: usage: " .. (CeroSecOS.commandUsage("sh") or "sh <file> [args]") }
	end
	local rest = {}
	for i = 3, #args do rest[#rest + 1] = args[i] end
	return CeroSecOS.startScript(state, session, "sh", args[2], rest,
		table.concat(args, " "), env, false)
end

-- ps: what the machine is running, in the four columns a sixty-column screen
-- has room for. The steps are the job's own count and are what a runaway
-- script is recognised by: they climb, fast, and nothing else does.
commands.ps = function(state, session, args, env)
	if #args > 1 then return false, { "ps: usage: " .. CeroSecOS.commandUsage("ps") } end
	local jobs = CeroSecOS.jobsOf(env)
	local out = { "  ID S     CPU COMMAND" }
	for i = 1, #jobs do
		local job = jobs[i]
		out[#out + 1] = CeroSecOS.padLeft(tostring(job.id), 4)
			.. " " .. CeroSecOS.jobLetter(job)
			.. " " .. CeroSecOS.padLeft(tostring(job.steps), 7)
			.. " " .. CeroSecOS.truncate(job.cmd or "", 45)
	end
	return true, out
end

commands.jobs = function(state, session, args, env)
	if #args > 1 then return false, { "jobs: usage: " .. CeroSecOS.commandUsage("jobs") } end
	local jobs = CeroSecOS.jobsOf(env)
	local out = {}
	for i = 1, #jobs do
		local job = jobs[i]
		-- Not the shell you are typing into, and not a cron line -- but every
		-- OTHER background job on the machine, whichever session asked for it.
		--
		-- That is this machine's model and it is worth saying plainly: a job
		-- belongs to the MACHINE and not to the shell that typed it. Four is the
		-- ceiling a machine has, not a ceiling a session has; the book is the
		-- machine's (luaObject.jobs); a survivor who walks away leaves his jobs
		-- running, and the next survivor to sit down sees them in `jobs` and may
		-- `fg` and `kill` them. A real sh lists only what that shell started,
		-- because on a real Unix a job is a process group the shell owns; here
		-- there is one book per computer and no shell owns anything.
		--
		-- So the description in COMMAND_INFO says "the background jobs on this
		-- machine", `help` and `man jobs` print that, and the manual says it
		-- outright. `ps` is still the wider one: it shows the prompt's own job
		-- and the cron lines too.
		if not job.interactive and job.mailTo == nil then
			out[#out + 1] = "[" .. tostring(job.n or i) .. "] "
				.. CeroSecOS.padRight(CeroSecOS.jobWord(job), 8)
				.. " " .. CeroSecOS.truncate(job.cmd or "", 45)
		end
	end
	return true, out
end

-- fg: the other half of "&".
--
-- POSIX job control, as much of it as a machine with no ^Z has: `fg` brings a
-- background job to the front, which means two things and nothing more -- what it
-- writes goes on the screen as it is written, and Escape is its ^C. There is no
-- `bg`, because there are no STOPPED jobs here to start again: nothing suspends a
-- job on this machine, so the only direction a job can be moved in is forwards.
--
-- With no argument it is the job that was started LAST, which is what every shell
-- means by "the current job". `%1` names a slot the way `jobs` prints one and
-- `kill` takes one; a bare number is an id, for the same reason kill takes one.
--
-- What comes back is the command line, printed the way sh prints it when it
-- brings a job forward, and an ORDER: only the machine can move the console's
-- attention from one job to another, so the engine says which job and the
-- scheduler does it.
commands.fg = function(state, session, args, env)
	if #args > 2 then return false, { "fg: usage: " .. CeroSecOS.commandUsage("fg") } end
	local jobs = CeroSecOS.jobsOf(env)

	local target = nil
	if args[2] == nil then
		for i = 1, #jobs do
			local job = jobs[i]
			-- The shell's own job is not one of them, and neither is a cron job:
			-- nobody started that one, so nobody may pull it forward.
			if not job.interactive and job.mailTo == nil and not CeroSecOS.jobIsOver(job) then
				if target == nil or job.id > target.id then target = job end
			end
		end
		if target == nil then return false, { "fg: no current job" } end
	else
		local want = args[2]
		local bySlot = false
		if string.sub(want, 1, 1) == "%" then
			want = string.sub(want, 2)
			bySlot = true
		end
		local n = tonumber(want)
		if n == nil then return false, { "fg: " .. args[2] .. ": no such job" } end
		for i = 1, #jobs do
			local job = jobs[i]
			local matches = false
			if bySlot then matches = job.n == n else matches = job.id == n end
			if matches and not job.interactive and job.mailTo == nil
					and not CeroSecOS.jobIsOver(job) then
				target = job
			end
		end
		if target == nil then return false, { "fg: " .. args[2] .. ": no such job" } end
	end

	return true, { target.cmd or "" }, "fg", { id = target.id }
end

-- kill: a request, not a deed. The scheduler is what takes a job off the
-- machine, because it is what has to tell the screen about it -- so this sets
-- the flag and answers, and the job is gone by the next pass.
--
-- WHOSE JOB IT IS. kill(2) is root, or the account the process belongs to, and
-- nobody else: a survivor may not stop what somebody else started, and EPERM is
-- what he gets. That rule arrived with the pending shutdown -- `shutdown +5` is a
-- process of root's now, and an ordinary account that could kill it could switch
-- the machine's own order off -- and it is applied to every job, because there is
-- no version of it that is only about one command.
--
-- It does not touch the deviation beside it. The jobs are still the MACHINE's:
-- `jobs` and `ps` list every one of them whoever started it, and `fg` still pulls
-- one forward, because a survivor who sits down at a glass has to be able to SEE
-- what is running and to watch it. What he may not do is stop another account's
-- work, which is Unix's rule and not this machine's.
--
-- THE SIGNAL. 4.4BSD-Lite2's bin/kill/kill.c: `-s name`, `-name` and
-- `-number`, and `-l` to list them. A name is matched without regard to case
-- and with or without "sig" in front (signame_to_signum: strncasecmp(sig,
-- "sig", 3), then strcasecmp against sys_signame), and the names are
-- lib/libc/gen/siglist.c's sys_signame, lower case, in number order -- so
-- this table is that one and not this engine's invention.
--
-- There is no process under a job, only a script the scheduler steps, so the
-- one thing a signal can do here is end it, which is the default action
-- sigaction(2)'s table gives HUP, INT, QUIT, KILL and TERM alike. Those five
-- are honoured. A signal that would stop, resume or merely be reported --
-- STOP, TSTP and CONT among them -- is refused by name, a declared deviation
-- (CeroSecOS.DEVIATIONS, "kill"), rather than faking a pause nothing behind
-- it could hold. Signal 0 is kill(2)'s own "is it there": the job is looked
-- up and left alone.
local KILL_NAMES = {
	"hup", "int", "quit", "ill", "trap", "abrt", "emt", "fpe",
	"kill", "bus", "segv", "sys", "pipe", "alrm", "term", "urg",
	"stop", "tstp", "cont", "chld", "ttin", "ttou", "io", "xcpu",
	"xfsz", "vtalrm", "prof", "winch", "info", "usr1", "usr2",
}
local KILL_HONOURED = { [1] = true, [2] = true, [3] = true, [9] = true, [15] = true }

-- printsignals(): NSIG is 32, and kill.c breaks the line after NSIG / 2 and
-- after NSIG - 1, so the list is always these two lines.
local function killSignalLines()
	local a, b = {}, {}
	for n = 1, #KILL_NAMES do
		if n <= 16 then a[#a + 1] = KILL_NAMES[n] else b[#b + 1] = KILL_NAMES[n] end
	end
	return table.concat(a, " "), table.concat(b, " ")
end

-- nosig(): warnx's line, then the list, both on the error side.
local function killNoSig(name)
	local a, b = killSignalLines()
	return false, { "kill: unknown signal " .. name .. "; valid signals:", a, b }
end

-- The number for a name, or nil: string.lower on both sides is strcasecmp,
-- and a plain comparison, never a pattern, is what reads the typed word.
local function killNumberOf(name)
	local low = string.lower(name)
	if string.sub(low, 1, 3) == "sig" then low = string.sub(low, 4) end
	for n = 1, #KILL_NAMES do
		if KILL_NAMES[n] == low then return n end
	end
	return nil
end

commands.kill = function(state, session, args, env)
	local usageLines = { "kill: usage: " .. CeroSecOS.commandUsage("kill") }
	if args[2] == nil then return false, usageLines end
	local signum, at = 15, 2
	local first = args[2]
	if first == "-l" then
		-- kill -l: the list, on the output side (printsignals(stdout)).
		if #args > 2 then return false, usageLines end
		local a, b = killSignalLines()
		return true, { a, b }
	elseif first == "-s" then
		if args[3] == nil then
			return false, { "kill: option requires an argument -- s", usageLines[1] }
		end
		if args[3] == "0" then signum = 0 else
			signum = killNumberOf(args[3])
			if signum == nil then return killNoSig(args[3]) end
		end
		at = 4
	elseif string.sub(first, 1, 1) == "-" then
		local rest = string.sub(first, 2)
		local c = string.sub(rest, 1, 1)
		if string.match(c, "^%a$") ~= nil then
			signum = killNumberOf(rest)
			if signum == nil then return killNoSig(rest) end
		elseif string.match(c, "^%d$") ~= nil then
			-- strtol and `*ep`: every character a digit, or the number is
			-- illegal outright; then 1..NSIG-1, or unknown.
			if string.match(rest, "^%d+$") == nil then
				return false, { "kill: illegal signal number: " .. rest }
			end
			signum = tonumber(rest)
			if signum < 1 or signum > #KILL_NAMES then return killNoSig(rest) end
		else
			return killNoSig(rest)
		end
		at = 3
	end
	if #args ~= at then return false, usageLines end
	if signum ~= 0 and not KILL_HONOURED[signum] then
		return false, { "kill: " .. KILL_NAMES[signum] .. ": not honoured" }
	end
	local jobs = CeroSecOS.jobsOf(env)
	local want = args[at]
	local bySlot = false
	if string.sub(want, 1, 1) == "%" then
		want = string.sub(want, 2)
		bySlot = true
	end
	local n = tonumber(want)
	if n == nil then return false, { "kill: " .. args[at] .. ": no such job" } end
	for i = 1, #jobs do
		local job = jobs[i]
		local matches = false
		if bySlot then matches = job.n == n else matches = job.id == n end
		if matches and not CeroSecOS.jobIsOver(job) then
			local me = CeroSecOS.userOf(session)
			local owner = (job.session or {}).user
			if me ~= "root" and owner ~= nil and owner ~= me then
				return false, { "kill: " .. args[at] .. ": Operation not permitted" }
			end
			-- Whichever of the five it was, the job ends the one way this
			-- scheduler ends one, and says "killed" as it always has.
			if signum ~= 0 then job.killReq = "user" end
			return true, {}
		end
	end
	return false, { "kill: " .. args[at] .. ": no such job" }
end

--
-- /bin's own doors into the six the shell runs itself
--
-- The shell reaches these through builtins[] and never comes here, because a
-- word typed at a prompt or written in a file goes through runSimple. This is
-- the OTHER door every command has -- `sudo <name>` -- and it exists so that
-- /bin/printf and /bin/test are not two files with nothing behind them.
--
-- Nothing is implemented twice: printf formats through CeroSecOS.printfText and
-- test judges through CeroSecOS.evalTest, the very calls the builtins make.
-- `sleep` cannot be answered at all without a job to put to sleep, so it asks
-- for one -- the same one-line job `wait` asks for, below.
--

commands["true"] = function(state, session, args, env)
	return true, {}
end

commands["false"] = function(state, session, args, env)
	return false, {}
end

commands.printf = function(state, session, args, env)
	local text = CeroSecOS.printfText(args)
	if text == nil then return false, {} end
	local lines = CeroSecOS.splitLines(text)
	-- printf writes only what its own format asked for -- no "\n" unless one
	-- is in it -- so `sudo printf a` leaves its line open exactly as the
	-- builtin's own writeText does (builtins.printf, above).
	if not CeroSecOS.endsLine(text) then lines.open = true end
	return true, lines
end

local function testCommand(state, session, args, env)
	local v, err = CeroSecOS.evalTest(state, session, args)
	if v == nil then return false, { err } end
	return v, {}
end

commands.test = testCommand
commands["["] = testCommand

commands.sleep = function(state, session, args, env)
	local words = { { { t = "lit", s = "sleep", q = true, bare = true } } }
	for i = 2, #args do
		words[#words + 1] = { { t = "lit", s = args[i], q = true, bare = false } }
	end
	local prog = { { k = "cmd", line = 1, words = words } }
	return CeroSecOS.jobOrder("sleep", prog, {}, table.concat(args, " "))
end

-- wait, typed at the prompt: a job of one line, so that the prompt is busy
-- while it waits and Escape kills the waiting and not the jobs waited on.
commands.wait = function(state, session, args, env)
	local jobs = CeroSecOS.jobsOf(env)
	-- The asker is not one of the jobs in its way, exactly as in startScript
	-- above: the `wait` runs in the job that typed it and asks for no other.
	if CeroSecOS.liveJobs(jobs, CeroSecOS.askingId(env)) >= CeroSecOS.MAX_JOBS then
		return false, { "wait: too many jobs" }
	end

	local words = { { { t = "lit", s = "wait", q = true, bare = true } } }
	for i = 2, #args do
		words[#words + 1] = { { t = "lit", s = args[i], q = true, bare = false } }
	end
	local prog = { { k = "cmd", line = 1, words = words } }
	return CeroSecOS.jobOrder("wait", prog, {}, table.concat(args, " "))
end
