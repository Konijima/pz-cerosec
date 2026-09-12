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
function CeroSecOS.liveJobs(jobs)
	local live = 0
	for i = 1, #jobs do
		if not jobs[i].interactive and not CeroSecOS.jobIsOver(jobs[i]) then live = live + 1 end
	end
	return live
end

local function trim(s)
	return (string.gsub(string.gsub(s, "^[ \t\n]+", ""), "[ \t\n]+$", ""))
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
local function capturing(job)
	local caps = job.caps
	return caps ~= nil and #caps > 0
end

-- Stopping the job is what a capture does when it catches too much, and the
-- error is raised from inside the writing. Declared here, written below with
-- the rest of the job's ending.
local jobError

-- How big the open capture has become: the value it would hand back if it
-- closed now, which is its lines joined by one separator, plus whatever is held
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

local function outLine(job, text)
	local caps = job.caps
	if capturing(job) then
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
local function errLine(job, text)
	if job.errTo ~= nil then
		outLine(job.errTo, text)
		return
	end
	outLine(job, text)
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
-- screen and must not be folded as if it were: the capture joins its lines with
-- a space, so a wrap there would push spaces into the middle of the captured
-- value. What bounds it there is the capture's byte ceiling, measured on what
-- is held as well as on what has been caught -- the same flood written into a
-- substitution instead of onto a screen must meet a ceiling of its own, or it
-- is the same unbounded string one door along.
local function wrapPartial(job)
	if capturing(job) then
		if captureBytes(job, job.partial) > CeroSecOS.MAX_VAR_BYTES then
			captureTooLarge(job)
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
		outLine(job, job.partial)
	end
	job.partial = ""
end

local function writeLines(job, lines)
	if type(lines) ~= "table" then return end
	if #lines > 0 then flushPartial(job) end
	for i = 1, #lines do outLine(job, lines[i]) end
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
-- Variables
--

local function getVar(job, name)
	local v = job.vars[name]
	if v == nil then return "" end
	return v
end

-- nil, or the reason it may not be set. The two ceilings live here and nowhere
-- else, so every road into a variable meets them.
local function setVar(job, name, value)
	if #value > CeroSecOS.MAX_VAR_BYTES then return "variable too large" end
	if job.vars[name] == nil then
		if job.nvars >= CeroSecOS.MAX_VARS then return "too many variables" end
		job.nvars = job.nvars + 1
	end
	job.vars[name] = value
	return nil
end

--
-- The job
--

-- opts: prog, args (args[1] is $1), name, cmd, session, id, bg, vars, status.
--
-- vars, when given, is taken BY REFERENCE and is the caller's to keep: it is
-- how the prompt has an environment that outlives one line. A script is never
-- handed one -- its variables are its own and die with it, the way a child
-- shell's do.
function CeroSecOS.newJob(opts)
	local args = {}
	if type(opts.args) == "table" then
		for i = 1, #opts.args do args[i] = tostring(opts.args[i]) end
	end
	local session = opts.session or CeroSecOS.rootSession()
	local vars, nvars = opts.vars, 0
	if type(vars) ~= "table" then
		vars = {}
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
		prog = opts.prog,
		args = args,
		vars = vars,
		nvars = nvars,
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
		-- Newlines become spaces, the way every shell folds a substitution.
		job.capval = trim(table.concat(buf or {}, " "))
		job.hasCap = true
	elseif f.oldArgs ~= nil then
		job.args = f.oldArgs
		job.name = f.oldName
		job.depth = job.depth - 1
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
	if c == "$" then i = i + 1 end
	if string.find(c, "^[0-9]") ~= nil then
		local j = i
		while j <= #s and string.find(string.sub(s, j, j), "^[0-9]") ~= nil do j = j + 1 end
		return tonumber(string.sub(s, i, j - 1)), j
	end
	if string.find(string.sub(s, i, i), "^[A-Za-z_]") ~= nil then
		local j = i
		while j <= #s and string.find(string.sub(s, j, j), "^[A-Za-z0-9_]") ~= nil do j = j + 1 end
		local name = string.sub(s, i, j - 1)
		local v = tonumber(getVar(job, name))
		if v == nil then v = 0 end
		return math.floor(v), j
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

-- words is an array of parsed words; nosplit is set for the right-hand side of
-- an assignment, which a shell never splits into fields.
local function newExpansion(words, nosplit)
	local kept = {}
	for i = 1, #words do kept[i] = words[i] end
	return { words = kept, wi = 1, pi = 1, buf = "", open = false, nosplit = nosplit,
		fields = {}, out = {}, counts = {} }
end

local function closeField(ex)
	ex.fields[#ex.fields + 1] = ex.buf
	ex.buf = ""
	ex.open = false
end

-- An unquoted expansion's text: every run of blanks in it ends a field and
-- starts the next one, which is what makes `for f in $list` walk a list.
local function addSplit(ex, text)
	if text == "" then return end
	local tokens = {}
	for piece in string.gmatch(text, "[^ \t\n]+") do tokens[#tokens + 1] = piece end
	if #tokens == 0 then
		-- Blanks and nothing else: it closes the open field and opens none.
		if ex.open then closeField(ex) end
		return
	end
	if string.find(text, "^[ \t\n]") ~= nil and ex.open then closeField(ex) end
	for i = 1, #tokens do
		if i > 1 then closeField(ex) end
		ex.buf = ex.buf .. tokens[i]
		ex.open = true
	end
	if string.find(text, "[ \t\n]$") ~= nil then closeField(ex) end
end

-- "done" when every word is expanded, "sub" when a $(...) has been pushed and
-- the walker must run it first, or nil plus the reason.
local function expandStep(job, state, ex, env)
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
			elseif part.t == "arith" then
				local v, err = arithEval(job, part.expr)
				if v == nil then return nil, err end
				text = v
			elseif part.t == "all" then
				-- $@ is one field per argument, quoted or not: it is the one
				-- expansion that is a list and not a string.
				for a = 1, #job.args do
					if a > 1 then closeField(ex) end
					ex.buf = ex.buf .. job.args[a]
					ex.open = true
				end
				ex.pi = ex.pi + 1
				text = nil
			elseif part.t == "sub" then
				if not job.hasCap then
					if not pushFrame(job, { k = "capture", prog = part.prog, i = 1 }) then
						return nil, nil
					end
					job.caps[#job.caps + 1] = {}
					return "sub"
				end
				text = job.capval
				job.hasCap = false
				job.capval = nil
			end

			if text ~= nil then
				if part.t == "lit" or part.q or ex.nosplit then
					ex.buf = ex.buf .. text
					ex.open = true
				else
					addSplit(ex, text)
				end
				ex.pi = ex.pi + 1
			end

			if #ex.buf > CeroSecOS.MAX_VAR_BYTES then return nil, "word too large" end
		end

		if ex.open then closeField(ex) end
		-- How many fields this word turned into, so the caller can tell a
		-- redirect's target apart from the arguments in front of it.
		ex.counts[ex.wi] = #ex.fields
		for i = 1, #ex.fields do ex.out[#ex.out + 1] = ex.fields[i] end
		ex.fields = {}
		ex.wi = ex.wi + 1
		ex.pi = 1
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
	local node = CeroSecOS.getNode(state, session, arg)
	if op == "-e" then return node ~= nil end
	if op == "-f" then return node ~= nil and node.type == "file" end
	if op == "-d" then return node ~= nil and node.type == "dir" end
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

-- printf, with the three conversions worth having on a machine this size.
-- The formatting, apart from the writing: the builtin below writes it into the
-- job and `sudo printf` returns it as lines, and there is ONE implementation of
-- the conversions.
function CeroSecOS.printfText(args)
	local format = args[2]
	if format == nil then return nil end
	local out, i, a = "", 1, 3
	while i <= #format do
		local c = string.sub(format, i, i)
		if c == "\\" then
			local nx = string.sub(format, i + 1, i + 1)
			if nx == "n" then out = out .. "\n"
			elseif nx == "t" then out = out .. "\t"
			elseif nx == "\\" then out = out .. "\\"
			else out = out .. "\\" .. nx end
			i = i + 2
		elseif c == "%" then
			local nx = string.sub(format, i + 1, i + 1)
			if nx == "%" then
				out = out .. "%"
			elseif nx == "s" then
				out = out .. (args[a] or "")
				a = a + 1
			elseif nx == "d" then
				local v = tonumber(args[a] or "0")
				if v == nil then v = 0 end
				out = out .. tostring(math.floor(v))
				a = a + 1
			else
				out = out .. c .. nx
			end
			i = i + 2
		else
			out = out .. c
			i = i + 1
		end
	end
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
		writeText(job, "history: usage: history [-c]\n")
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

builtins.exit = function(job, args)
	local n = 0
	if args[2] ~= nil then n = math.floor(tonumber(args[2]) or 0) end
	job.sig = { k = "exit", n = n }
	return n
end
-- `return` inside a script is the same door: this machine has no functions to
-- return from, so the only thing it can mean is the end of the script.
builtins["return"] = builtins.exit

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

-- read: the continuation every interactive script is built on. The job stops
-- where it stands, the console puts the question up, and the next line typed
-- comes back through CeroSecOS.jobInput.
builtins.read = function(job, args, state, env)
	local prompt, mask, one, name = "", false, false, nil
	local i = 2
	while i <= #args do
		local a = args[i]
		if a == "-p" then
			prompt = args[i + 1] or ""
			i = i + 2
		elseif a == "-s" then
			mask = true
			i = i + 1
		elseif a == "-n" then
			if args[i + 1] ~= "1" then return nil, "read: only -n 1" end
			one = true
			i = i + 2
		elseif string.sub(a, 1, 1) == "-" and #a > 1 then
			return nil, "read: " .. a .. ": unknown option"
		else
			name = a
			i = i + 1
		end
	end
	if name == nil or not CeroSecOS.isVarName(name) then return nil, "read: not a name" end

	-- A stage of a pipeline reads the PIPE, because that is what its standard
	-- input is. It is also a subshell, and its variables die with it -- which is
	-- why `echo hi | read x` leaves x empty in the shell that typed it, on this
	-- machine exactly as on every other one with a pipeline in it.
	if job.stdinBuf ~= nil then
		local buf = job.stdinBuf
		if #buf.lines > 0 then
			local line = table.remove(buf.lines, 1)
			buf.bytes = buf.bytes - #line - 1
			if buf.bytes < 0 then buf.bytes = 0 end
			local reason = setVar(job, name, line)
			if reason ~= nil then return nil, reason end
			return 0
		end
		if buf.eof then
			local reason = setVar(job, name, "")
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
		local reason = setVar(job, name, "")
		if reason ~= nil then return nil, reason end
		return 1
	end

	flushPartial(job)
	job.ask = { var = name, text = prompt, mask = mask, one = one }
	job.state = "waiting"
	return 0
end

builtins.sleep = function(job, args, state, env)
	local n = tonumber(args[2] or "")
	if n == nil or n < 0 then return nil, "sleep: invalid interval" end
	local now = CeroSecOS.nowMsOf(env)
	-- A machine with no clock cannot sleep; it says so rather than sleeping
	-- forever or not at all.
	if now == nil then return nil, "sleep: no clock" end
	job.wakeMs = now + math.floor(n * 1000)
	job.state = "sleeping"
	return 0
end

-- The expression, judged. Shared by the builtin below and by /bin's own door
-- into it (`sudo test -f /root/notes`), so there is one evaluator and one set
-- of refusals.
-- true/false, or nil plus the line to print and whether it is FATAL. A bracket
-- with no other half is a mistake in the script and stops it; an expression
-- that cannot be judged is a status of two and the script goes on. The two
-- answers were already different before this evaluator was shared, and the
-- difference is the third return rather than two call sites that each remember.
function CeroSecOS.evalTest(state, session, args)
	local hi = #args
	if args[1] == "[" then
		if args[hi] ~= "]" then return nil, "test: missing ']'", true end
		hi = hi - 1
	end
	local v, err = testExpr(state, session, args, 2, hi)
	return v, err, false
end

builtins.test = function(job, args, state)
	local v, err, fatal = CeroSecOS.evalTest(state, job.session, args)
	if v == nil then
		if fatal then return nil, err end
		flushPartial(job)
		outLine(job, err)
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
		flushPartial(job)
		local now = CeroSecOS.nowMsOf(env)
		local ms = tonumber(data.ms)
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
		if job.inPipe and job.stdinBuf ~= nil then
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
	if control == "job" and type(data) == "table" then
		if CeroSecOS.jobRun(job, data.prog, data.args, data.name) then job.status = 0 end
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
	job.control = control
	job.controlData = data
	flushPartial(job)
	job.sig = { k = "exit", n = job.status, all = true }
	return true
end

-- Is this `exit` the one that leaves the MACHINE, or the one that leaves a
-- script? Only the word typed at the glass is the first kind, and "at the glass"
-- is three things at once, every one of which has to hold:
--
--   * the prompt's own job (`job.interactive`) -- a background job, a cron line
--     and a stage of a pipeline have nobody standing in front of them;
--   * the TOP level of it: `./lights.sh` is the prompt's own job one level
--     deeper (CeroSecOS.jobRun), and an `exit 1` inside a file is the file
--     ending with status 1 and the prompt coming back -- which is POSIX, and
--     is the whole reason a usage-and-exit script does not throw a player off
--     the machine;
--   * outside every $(...): a substitution is a subshell, and a subshell's
--     `exit` ends the subshell.
--
-- ~/.profile is deliberately on the other side of this line: it runs AS the
-- login shell, at depth one, so its `exit` logs out -- which is what bash does
-- with a profile and what the manual says here.
local function exitLeavesTheMachine(job)
	if not job.interactive then return false end
	if job.inPipe then return false end
	if job.depth > 1 then return false end
	for i = 1, #job.frames do
		if job.frames[i].k == "capture" then return false end
	end
	return true
end

-- The answer to a continuation, whatever woke it: a line somebody typed, or a
-- clock the command itself asked to be woken by. One place, because the two must
-- do the same thing to the job -- the chain's authority, its redirect, its
-- output and the order it may give are the chain's and not the caller's.
local function resumeCont(state, job, text, env)
	local cont = job.cont
	local pending = job.contRedirect
	job.cont = nil
	job.contRedirect = nil
	job.ask = nil
	job.state = "running"
	-- The redirect the line was typed with goes back down with the answer: the
	-- chain is where the command finally runs, and the writing belongs beside
	-- the writing every other command's redirect goes through.
	local ok, lines, control, data =
		CeroSecOS.continue(state, job.session, cont, text, env, pending)
	-- A chain that is still asking -- `sudo passwd root > out` -- has still
	-- written nothing, so its redirect waits for the next answer.
	if pending ~= nil and control == "prompt" then job.contRedirect = pending end
	if ok then
		writeLines(job, lines)
		job.status = 0
	else
		-- A refusal is not output, so in a stage it goes to the screen and
		-- not down the pipe -- the rule every other command already runs on.
		errLines(job, lines)
		job.status = 1
	end
	applyControl(job, control, data, env)
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
	for i = 1, #f.ex.out do args[i] = f.ex.out[i] end
	local redirect = nil
	if node.redirect ~= nil then
		-- The redirect's target is the last word of the expansion, and it has
		-- to be exactly one field: a target that is two names, or none, is a
		-- line the machine cannot carry out and will not guess at.
		local count = f.ex.counts[#f.ex.words] or 0
		if count ~= 1 then
			jobError(job, "ambiguous redirect")
			return 1
		end
		redirect = { path = args[#args], append = node.redirect.append }
		args[#args] = nil
	end

	if #args == 0 then
		if redirect ~= nil then
			local ok, lines = CeroSecOS.runArgs(state, job.session, {}, redirect, env)
			errLines(job, lines)
			if ok then job.status = 0 else job.status = 1 end
			return CeroSecOS.STEP_COST_COMMAND
		end
		job.status = 0
		return 1
	end

	CeroSecOS.expandTilde(state, job.session, args, redirect)

	local name = args[1]
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
	if builtin ~= nil and CeroSecOS.BUILTIN_FILES[name] then
		local refusal = CeroSecOS.whyNotRun(state, job.session, name)
		if refusal ~= nil then
			errLines(job, CeroSecOS.fit({ name .. ": " .. refusal }))
			job.status = 1
			return 1
		end
	end
	if builtin ~= nil then
		-- A builtin writes to the job's own output, so a redirect on one is a
		-- capture: its lines are caught the way $(...) catches them and then
		-- written through the very same door a command's redirect goes through.
		if redirect ~= nil then job.caps[#job.caps + 1] = {} end
		local status, fatal = builtin(job, args, state, env)
		if redirect ~= nil then
			flushPartial(job)
			local buf = job.caps[#job.caps]
			job.caps[#job.caps] = nil
			local ok, lines = CeroSecOS.writeRedirect(state, job.session, name, redirect,
				table.concat(buf, "\n"), env)
			errLines(job, lines)
			if not ok then
				job.status = 1
				return 1
			end
		end
		if status == nil then
			if fatal ~= nil then jobError(job, fatal) end
			return 1
		end
		job.status = status
		return 1
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
		stdin = { lines = job.stdinBuf.lines, eof = job.stdinBuf.eof,
			carry = f.rd.carry, want = false, done = false }
	end

	-- A command that reads a pipe is run more than once, and a redirect on one
	-- must not truncate the file it has already written to. So the redirect is
	-- not handed to the command at all where there is a pipe: it is carried out
	-- below, through the very same door -- the first write replaces, every one
	-- after it appends, and a call that produced nothing writes nothing.
	local ok, lines, control, data =
		CeroSecOS.runArgs(state, job.session, args, stdin == nil and redirect or nil,
			env, stdin)
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
	if stdin ~= nil and redirect ~= nil and ok then
		local wrote = f.rd ~= nil and f.rd.wrote == true
		if #lines > 0 or not wrote then
			local target = { path = redirect.path, append = redirect.append or wrote }
			local wroteOk, wroteLines = CeroSecOS.writeRedirect(state, job.session, name,
				target, table.concat(lines, "\n"), env)
			if f.rd ~= nil then f.rd.wrote = true end
			lines = wroteLines
			ok = wroteOk
		else
			lines = {}
		end
	end
	if ok then
		writeLines(job, lines)
		job.status = 0
	else
		errLines(job, lines)
		job.status = 1
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
	if redirect ~= nil and job.cont ~= nil then
		local openOk, openLines =
			CeroSecOS.openRedirect(state, job.session, name, redirect, env)
		if openOk then
			job.contRedirect = { path = redirect.path, append = redirect.append, who = name }
		else
			-- A target that cannot be opened is a command that does not run, the
			-- way it is on a real shell. The question goes with it: there is
			-- nothing left for an answer to do.
			job.cont = nil
			job.ask = nil
			job.state = "running"
			errLines(job, openLines)
			job.status = 1
		end
	end
	return CeroSecOS.STEP_COST_COMMAND
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

local stepOnce, handleSignal

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
local function newStage(job, node, out, into)
	local stage = CeroSecOS.newJob({
		prog = { node }, args = job.args, name = job.name, cmd = job.cmd,
		session = job.session, status = job.status,
	})
	local vars, nvars = {}, 0
	for k, v in pairs(job.vars) do
		vars[k] = v
		nvars = nvars + 1
	end
	stage.vars = vars
	stage.nvars = nvars
	stage.pipe = out
	stage.stdinBuf = into
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
	buf.lines = {}
	buf.bytes = 0
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
			-- knows about.
			if stage.control ~= nil and job.control == nil then
				job.control = stage.control
				job.controlData = stage.controlData
			end
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
			if i < n and pipes[i].closed then
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
			stages[i] = newStage(job, node.stages[i], pipes[i], pipes[i - 1])
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
	jobError(job, "syntax error")
	return false
end

-- One turn of the machine. Returns how many steps it cost -- 0 for the frame
-- work between commands, 1 for a command or a loop iteration.
stepOnce = function(state, job, env)
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
			f.words = f.ex.out
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
				if f.k == "capture" or f.oldArgs ~= nil then
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
	if f.ex ~= nil then
		key = key .. " " .. tostring(f.ex.wi) .. " " .. tostring(f.ex.pi) ..
			" " .. #f.ex.fields .. " " .. #f.ex.buf
	end
	if f.exA ~= nil then
		key = key .. " " .. tostring(f.exA.wi) .. " " .. tostring(f.exA.pi) ..
			" " .. #f.exA.fields .. " " .. #f.exA.buf
	end
	return key
end

local function progressKey(job)
	local key = tostring(job.state) .. " " .. tostring(job.blocked) ..
		" " .. #job.out .. " " .. #(job.partial or "") .. " " .. frameKey(job)
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
				return job.state, 1
			end
		else
			return "sleeping", 0
		end
	end
	if job.state == "waiting" then return "waiting", 0 end
	if job.spawn ~= nil then return "running", 0 end

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
		if #job.out >= CeroSecOS.JOB_OUT_MAX then
			job.blocked = "output"
			-- Waiting on the screen is not spending the processor, so the
			-- runaway clock starts again when it runs again.
			job.cpuSince = nil
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
			CeroSec.log("jobStep: maxTurns reached on job " .. tostring(job.id) ..
				" (" .. tostring(job.cmd) .. ")")
		end
	end
	job.steps = job.steps + used
	if used > budget then job.debt = (job.debt or 0) + used - budget end

	if job.state == "waiting" or job.state == "sleeping" then job.cpuSince = nil end
	if job.state == "done" or job.state == "error" then flushPartial(job) end

	CeroSecOS.unmountDev(state, env)
	return job.state, used
end

-- A line the MACHINE has to say about a job -- "too many jobs" when the job
-- asked for one it cannot have. It goes in the job's own output queue and not
-- straight onto the screen, so it drains at the same twenty lines a second as
-- everything else and a loop full of refusals is as quiet as a loop full of
-- echoes.
function CeroSecOS.jobSay(job, line)
	outLine(job, line)
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
	if ask.one then value = string.sub(text, 1, 1) end
	local reason = setVar(job, ask.var, value)
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
function CeroSecOS.jobRun(job, prog, args, name)
	if job.depth >= CeroSecOS.SCRIPT_DEPTH_MAX then
		jobError(job, "too deeply nested")
		return false
	end
	job.depth = job.depth + 1
	local kept = {}
	for i = 1, #args do kept[i] = args[i] end
	if not pushFrame(job, { k = "block", prog = prog, i = 1,
			oldArgs = job.args, oldName = job.name }) then
		return false
	end
	job.args = kept
	job.name = name
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
	if CeroSecOS.liveJobs(jobs) >= CeroSecOS.MAX_JOBS then
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
		-- Not the shell you are typing into: `jobs` lists what the shell
		-- STARTED, the way it has since job control was invented. `ps` is the
		-- one that shows everything the machine is running, the prompt's own
		-- job included -- and a cron job, which the shell did not start either.
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
commands.kill = function(state, session, args, env)
	if #args ~= 2 then return false, { "kill: usage: " .. CeroSecOS.commandUsage("kill") } end
	local jobs = CeroSecOS.jobsOf(env)
	local want = args[2]
	local bySlot = false
	if string.sub(want, 1, 1) == "%" then
		want = string.sub(want, 2)
		bySlot = true
	end
	local n = tonumber(want)
	if n == nil then return false, { "kill: " .. args[2] .. ": no such job" } end
	for i = 1, #jobs do
		local job = jobs[i]
		local matches = false
		if bySlot then matches = job.n == n else matches = job.id == n end
		if matches and not CeroSecOS.jobIsOver(job) then
			job.killReq = "user"
			return true, {}
		end
	end
	return false, { "kill: " .. args[2] .. ": no such job" }
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
	return true, CeroSecOS.splitLines(text)
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
	if CeroSecOS.liveJobs(jobs) >= CeroSecOS.MAX_JOBS then
		return false, { "wait: too many jobs" }
	end

	local words = { { { t = "lit", s = "wait", q = true, bare = true } } }
	for i = 2, #args do
		words[#words + 1] = { { t = "lit", s = args[i], q = true, bare = false } }
	end
	local prog = { { k = "cmd", line = 1, words = words } }
	return CeroSecOS.jobOrder("wait", prog, {}, table.concat(args, " "))
end
