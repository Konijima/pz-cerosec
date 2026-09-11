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

-- Lines one $(...) may capture. Its output never reaches a screen, so nothing
-- else bounds it.
CeroSecOS.CAPTURE_MAX = 100

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
-- screen? The one test, asked in the two places that must agree about it.
local function capturing(job)
	local caps = job.caps
	return caps ~= nil and #caps > 0
end

local function outLine(job, text)
	local caps = job.caps
	if capturing(job) then
		local buf = caps[#caps]
		if #buf < CeroSecOS.CAPTURE_MAX then buf[#buf + 1] = text end
		return
	end
	-- The screen's own rule, applied once, here: a job's line is at most sixty
	-- columns and carries no control byte, exactly like a command's.
	local fitted = CeroSecOS.fit({ text })
	for i = 1, #fitted do job.out[#job.out + 1] = fitted[i] end
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
-- value. A capture is bounded by its own ceilings instead.
local function wrapPartial(job)
	if capturing(job) then return end
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

-- opts: prog, args (args[1] is $1), name, cmd, session, id, bg.
function CeroSecOS.newJob(opts)
	local args = {}
	if type(opts.args) == "table" then
		for i = 1, #opts.args do args[i] = tostring(opts.args[i]) end
	end
	local session = opts.session or CeroSecOS.rootSession()
	return {
		id = opts.id or 1,
		-- What `ps` prints, and what the script calls itself in an error.
		name = opts.name or "sh",
		cmd = opts.cmd or opts.name or "sh",
		bg = opts.bg and true or false,
		prog = opts.prog,
		args = args,
		vars = {},
		nvars = 0,
		-- A session of the job's OWN. `cd` inside a script moves the script and
		-- not the console it was started from, the way a real shell's child
		-- cannot move its parent.
		session = {
			user = session.user,
			cwd = session.cwd or "/",
			stamp = session.stamp,
			login = CeroSecOS.loginOf(session),
			stack = CeroSecOS.copyStack(session.stack),
		},
		frames = { { k = "block", prog = opts.prog, i = 1 } },
		caps = {},
		out = {},
		partial = "",
		status = 0,
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
local function jobError(job, reason)
	flushPartial(job)
	outLine(job, CeroSecOS.scriptError(job.name, reason, job.line))
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
builtins.printf = function(job, args)
	local format = args[2]
	if format == nil then return 1 end
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
	writeText(job, out)
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

	-- A background job has nobody in front of it. It reads end of file, the
	-- way a real one reading a closed input does, and says so with its status
	-- rather than hanging forever where nobody can see it.
	if job.bg then
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

builtins.test = function(job, args, state)
	local hi = #args
	if args[1] == "[" then
		if args[hi] ~= "]" then return nil, "test: missing ']'" end
		hi = hi - 1
	end
	local v, err = testExpr(state, job.session, args, 2, hi)
	if v == nil then
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
local function applyControl(job, control, data)
	if control == nil then return true end
	if control == "prompt" and type(data) == "table" then
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
	if control == "edit" then
		flushPartial(job)
		outLine(job, "edit: not a terminal")
		job.status = 1
		return true
	end
	-- clear, shutdown, reboot and exit are the machine's, and the scheduler is
	-- what carries them out -- after the job's own output has reached the
	-- screen, exactly as a command typed at the prompt does.
	job.control = control
	return true
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

	local args = f.ex.out
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
			writeLines(job, lines)
			if ok then job.status = 0 else job.status = 1 end
			return CeroSecOS.STEP_COST_COMMAND
		end
		job.status = 0
		return 1
	end

	local name = args[1]
	local builtin = builtins[name]
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
			writeLines(job, lines)
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

	local ok, lines, control, data = CeroSecOS.runArgs(state, job.session, args, redirect, env)
	writeLines(job, lines)
	if ok then job.status = 0 else job.status = 1 end
	applyControl(job, control, data)
	return CeroSecOS.STEP_COST_COMMAND
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
local function stepOnce(state, job, env)
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
		-- One simple command. One step when the shell answers it itself, and
		-- what a command in /bin costs when it does not.
		popFrame(job)
		return runSimple(state, job, f, env)
	end

	jobError(job, "syntax error")
	return 0
end

-- break, continue and exit, carried out by unwinding frames. Never by an
-- error: a signal is an ordinary part of a shell and not a fault.
local function handleSignal(job)
	local sig = job.sig
	job.sig = nil

	if sig.k == "exit" then
		-- Inside $(...) it ends the substitution and nothing else, the way a
		-- subshell's exit does.
		local capAt = nil
		for i = #job.frames, 1, -1 do
			if job.frames[i].k == "capture" then
				capAt = i
				break
			end
		end
		if capAt ~= nil then
			while #job.frames >= capAt do popFrame(job) end
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
		used = used + stepOnce(state, job, env)
		if job.sig ~= nil then handleSignal(job) end
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

	if job.cont ~= nil then
		local cont = job.cont
		job.cont = nil
		job.ask = nil
		job.state = "running"
		local ok, lines, control, data = CeroSecOS.continue(state, job.session, cont, text, env)
		writeLines(job, lines)
		if ok then job.status = 0 else job.status = 1 end
		applyControl(job, control, data)
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
	return STATE_LETTER[job.state] or "R"
end

function CeroSecOS.jobWord(job)
	if job.state == "running" and job.blocked == "output" then return "output" end
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
	local live = 0
	for i = 1, #jobs do
		if not CeroSecOS.jobIsOver(jobs[i]) then live = live + 1 end
	end
	if live >= CeroSecOS.MAX_JOBS then return false, { who .. ": too many jobs" } end

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
		out[#out + 1] = "[" .. tostring(job.n or i) .. "] "
			.. CeroSecOS.padRight(CeroSecOS.jobWord(job), 8)
			.. " " .. CeroSecOS.truncate(job.cmd or "", 45)
	end
	return true, out
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

-- wait, typed at the prompt: a job of one line, so that the prompt is busy
-- while it waits and Escape kills the waiting and not the jobs waited on.
commands.wait = function(state, session, args, env)
	local jobs = CeroSecOS.jobsOf(env)
	local live = 0
	for i = 1, #jobs do
		if not CeroSecOS.jobIsOver(jobs[i]) then live = live + 1 end
	end
	if live >= CeroSecOS.MAX_JOBS then return false, { "wait: too many jobs" } end

	local words = { { { t = "lit", s = "wait", q = true, bare = true } } }
	for i = 2, #args do
		words[#words + 1] = { { t = "lit", s = args[i], q = true, bare = false } }
	end
	local prog = { { k = "cmd", line = 1, words = words } }
	return CeroSecOS.jobOrder("wait", prog, {}, table.concat(args, " "))
end
