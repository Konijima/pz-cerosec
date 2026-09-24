-- The shell's own words that change the SHELL -- set, unset, exec, trap --
-- and the parameter expansions inside braces. Run from the repo root:
--   lua5.1 tests/builtins_test.lua
--
-- Every line here is typed at a prompt the way the server types one
-- (SCeroSecJobs.typeLine): a job made by CeroSecOS.promptJob on a console's
-- own variables, its exported set and its functions, stepped until it stops.
-- The exported set is the one a LOGIN hands a console (loginExported), not
-- nil: nil means "a machine saved before export existed, everything is
-- exported", and a bench on that would pass whether or not an unexported
-- variable leaks.

local DIR = "42/media/lua/shared/CeroSec/OS/"
local FILES = {
	"CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSDev", "CeroSecOSDisk",
	"CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath", "CeroSecOSScript", "CeroSecOSRadio",
	"CeroSecOSShell", "CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers",
	"CeroSecOSVM",
}
for i = 1, #FILES do
	local path = DIR .. FILES[i] .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
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

-- A machine with admin logged in, and the console's three tables.
local function machine()
	local state = CeroSecOS.newState("ksp-front-01")
	local session, reason = CeroSecOS.login(state, "admin", "")
	if session == nil then error("cannot log in: " .. tostring(reason)) end
	local user = CeroSecOS.getUser(state, "admin")
	local console = {
		session = session,
		vars = CeroSecOS.loginVars(user.home),
		exported = CeroSecOS.loginExported(),
		funcs = {},
		status = 0,
	}
	return state, console
end

-- One typed line, to the end. ok, the lines, the job.
local function exec(state, console, line)
	local job, refusal = CeroSecOS.promptJob(state, console.session, line, console.vars,
		console.status, nil, console.exported, console.funcs)
	if job == nil then return false, CeroSecOS.fit({ refusal }), nil end
	local out, turns = {}, 0
	while not CeroSecOS.jobIsOver(job) and turns < 500 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, {}, 1000)
		job.orders = nil
		for k = 1, #job.out do out[#out + 1] = job.out[k] end
		job.out = {}
		if job.state == "waiting" or job.state == "sleeping" or job.spawn ~= nil then break end
	end
	for k = 1, #job.out do out[#out + 1] = job.out[k] end
	job.out = {}
	check("`" .. line .. "` came to an end", CeroSecOS.jobIsOver(job))
	console.status = job.status
	return job.status == 0, CeroSecOS.fit(out), job
end

local function expect(state, console, line, wantOk, wantLines)
	local good, lines, job = exec(state, console, line)
	eq("`" .. line .. "` ok", good, wantOk)
	eq("`" .. line .. "` line count", #lines, #wantLines)
	for i = 1, #wantLines do
		eq("`" .. line .. "` line " .. i, lines[i], wantLines[i])
	end
	return lines, job
end
local function ok(state, console, line, wantLines)
	return expect(state, console, line, true, wantLines)
end
local function bad(state, console, line, errorLine)
	return expect(state, console, line, false, { errorLine })
end

-- A script on admin's disk, runnable by him.
local function script(state, path, text)
	local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(), path, text,
		false, 100)
	if done == nil then error("cannot write " .. path .. ": " .. tostring(reason), 2) end
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), path)
	node.owner = "admin"
	node.mode = 755
end

--
-- 1. set
--

do
	local state, c = machine()
	-- POSIX.2 set: `set --` and a plain operand replace $1.. and $#.
	ok(state, c, "set -- a b c; echo $# $1 $3", { "3 a c" })
	ok(state, c, "set x y; echo $#:$1:$2", { "2:x:y" })
	ok(state, c, "set -- a; set --; echo $#", { "0" })
	-- "$@" is the new list, one field each.
	ok(state, c, "set -- 'a b' c; for w in \"$@\"; do echo \"<$w>\"; done",
		{ "<a b>", "<c>" })
	-- A function's own `set --` is the function's.
	ok(state, c, "f(){ set -- z; }; set -- a b; f; echo $1", { "a" })
	c.funcs.f = nil

	-- No operand: every variable, NAME=value, sorted -- the unexported too.
	-- 4.4BSD's showvars printed the text as it stands, unquoted.
	ok(state, c, "Qz=1", {})
	local _, listed = exec(state, c, "set")
	local names = {}
	for name in pairs(c.vars) do names[#names + 1] = name end
	table.sort(names)
	-- As text and not line by line: IFS holds a newline, and showvars
	-- printed it as it stands, so its one entry is two lines on the glass.
	local want = {}
	for i = 1, #names do want[i] = names[i] .. "=" .. c.vars[names[i]] end
	eq("set lists every variable", table.concat(listed, "\n"), table.concat(want, "\n"))
	local seen = false
	for i = 1, #listed do if listed[i] == "Qz=1" then seen = true end end
	check("and an unexported one is among them", seen)
	check("which really is unexported", c.exported.Qz == nil)

	-- The flags are refused: nothing here traces, stops on failure or flags
	-- an unset name, and saying one was turned on would be a lie.
	bad(state, c, "set -e", "sh: set: Illegal option -e")
	bad(state, c, "set -x", "sh: set: Illegal option -x")
	bad(state, c, "set -u", "sh: set: Illegal option -u")
end

--
-- 2. unset
--

do
	local state, c = machine()
	ok(state, c, "Q=1; unset Q; echo \"[$Q]\"", { "[]" })
	-- Unset, not empty: ${Q-w} tells the two apart.
	ok(state, c, "Q=1; unset Q; echo ${Q-gone}", { "gone" })
	ok(state, c, "Q=; echo \"[${Q-gone}]\"", { "[]" })
	-- Out of the environment too: a name set again afterwards is not exported.
	ok(state, c, "export Q=1; unset Q", {})
	check("unset takes the name out of the exported set", c.exported.Q == nil)
	-- -v says what the default already means.
	ok(state, c, "Q=1; unset -v Q; echo ${Q-gone}", { "gone" })
	-- A name never set is not an error.
	ok(state, c, "unset nosuch; echo $?", { "0" })
	-- -f drops a function.
	ok(state, c, "f(){ echo hi; }; f", { "hi" })
	bad(state, c, "unset -f f; f", "f: not found")
	-- ash's words for a name that cannot be one.
	bad(state, c, "unset 1x", "sh: unset: 1x: bad variable name")

	-- The seat is given back: seventy set-and-unset pairs in one shell stay
	-- under the MAX_VARS ceiling (64) that seventy sets alone would pass.
	local line = {}
	for i = 1, CeroSecOS.MAX_VARS + 6 do line[#line + 1] = "v" .. i .. "=1; unset v" .. i end
	line[#line + 1] = "echo done"
	ok(state, c, table.concat(line, "; "), { "done" })
end

--
-- 3. The environment of a pipeline stage: only what is exported.
--

do
	local state, c = machine()
	-- env's lines, whichever door they left by.
	local function has(lines, want)
		for i = 1, #lines do if lines[i] == want then return true end end
		return false
	end
	local _, plain = exec(state, c, "Q=1; env")
	check("`Q=1; env` does not show Q", not has(plain, "Q=1"))
	local _, piped = exec(state, c, "Q=1; env | cat")
	check("`Q=1; env | cat` does not show Q either", not has(piped, "Q=1"))
	local _, marked = exec(state, c, "export Q; env | cat")
	check("an exported Q does go down the pipe", has(marked, "Q=1"))
	check("and so does HOME, exported at login", has(marked, "HOME=/home/admin"))
end

--
-- 4. exec
--

do
	local state, c = machine()
	ok(state, c, "exec echo a; echo b", { "a" })
	-- The status is the exec'd command's.
	expect(state, c, "exec false; echo no", false, {})
	eq("exec false leaves 1", c.status, 1)
	-- No operand: nothing happens and the line goes on.
	ok(state, c, "exec; echo yes", { "yes" })
	-- A redirect with nothing to run is refused, not silently dropped.
	bad(state, c, "exec > f", "sh: exec: redirect with no command")
	-- exec ends the SCRIPT it is in, not the shell that ran the script.
	script(state, "/home/admin/b.sh", "exec echo in\necho after\n")
	ok(state, c, "sh /home/admin/b.sh; echo back $?", { "in", "back 0" })
	-- And the trap of the shell exec replaced never runs.
	ok(state, c, "trap 'echo T' EXIT; exec echo E", { "E" })
end

--
-- 5. trap
--

do
	local state, c = machine()
	ok(state, c, "trap 'echo bye' EXIT; echo hi", { "hi", "bye" })
	ok(state, c, "trap 'echo bye' 0; echo hi", { "hi", "bye" })
	-- The listing, quoted so it can be typed back in; `trap -` resets it.
	ok(state, c, "trap 'echo it'\"'\"'s' EXIT; trap; trap - EXIT; trap",
		{ "trap -- 'echo it'\\''s' EXIT" })
	-- A number first means no action: `trap 0` resets.
	ok(state, c, "trap 'echo x' 0; trap 0; echo y", { "y" })
	-- An action and no condition names nothing (4.4BSD trap.c).
	ok(state, c, "trap 'echo x'; echo y", { "y" })
	-- There is no signal a job here can catch: trap.c's own refusal.
	bad(state, c, "trap 'echo x' INT", "sh: trap: INT: bad trap")
	bad(state, c, "trap 'echo x' TERM", "sh: trap: TERM: bad trap")
	-- One refused condition refuses the line.
	bad(state, c, "trap 'echo x' EXIT HUP", "sh: trap: HUP: bad trap")
	-- $? in the action is the status the shell is leaving with, and is
	-- still that status afterwards.
	expect(state, c, "trap 'echo st=$?' EXIT; false", false, { "st=1" })
	eq("the action's own success does not change it", c.status, 1)
	-- Once, even when the action sets the trap again.
	ok(state, c, "trap 'trap \"echo again\" EXIT; echo once' EXIT", { "once" })
	-- A function sets the SHELL's trap: it fires when the shell ends.
	ok(state, c, "f(){ trap 'echo inner' EXIT; }; f; echo after", { "after", "inner" })
	c.funcs.f = nil
	-- A $( ) is a shell of its own, and what its trap prints is caught --
	-- with the newline between them, which $( ) keeps (POSIX.2 2.6.3).
	ok(state, c, "x=$(trap 'echo sub' EXIT; echo val); echo \"[$x]\"", { "[val", "sub]" })
	ok(state, c, "trap 'echo outer' EXIT; x=$(echo in); echo $x", { "in", "outer" })
end

do
	local state, c = machine()
	-- A script's trap runs when the script ends, on its end or on `exit`,
	-- and the script does not go on past the exit afterwards.
	script(state, "/home/admin/a.sh",
		"trap 'echo cleanup' EXIT\necho one\nexit 3\necho never\n")
	ok(state, c, "sh /home/admin/a.sh; echo rc=$?", { "one", "cleanup", "rc=3" })
	script(state, "/home/admin/b.sh", "trap 'echo cleanup' EXIT\necho one\n")
	ok(state, c, "sh /home/admin/b.sh; echo rc=$?", { "one", "cleanup", "rc=0" })
	-- `exit n` in the action is the script's status.
	script(state, "/home/admin/c.sh", "trap 'echo st=$?; exit 5' EXIT\nfalse\n")
	ok(state, c, "sh /home/admin/c.sh; echo rc=$?", { "st=1", "rc=5" })
	-- A script's trap is the script's: the caller has none afterwards, and
	-- the caller's own is neither run by the script nor lost to it.
	ok(state, c, "sh /home/admin/b.sh; trap", { "one", "cleanup" })
	script(state, "/home/admin/d.sh", "trap\necho d\n")
	ok(state, c, "trap 'echo outer' EXIT; sh /home/admin/d.sh; echo mid",
		{ "d", "mid", "outer" })
end

--
-- 6. Parameter expansion inside braces
--

do
	local state, c = machine()
	-- System V's four, with and without the colon.
	ok(state, c, "x=; echo ${x:-d} \"[${x-d}]\" \"[${x:+a}]\" ${x+set}", { "d [] [] set" })
	ok(state, c, "unset x; echo ${x:-d} ${x-d} \"[${x:+a}]\" \"[${x+set}]\"", { "d d [] []" })
	ok(state, c, "x=v; echo ${x:-d} ${x-d} ${x:+a} ${x+set}", { "v v a set" })
	ok(state, c, "unset x; echo ${x:=new} $x", { "new new" })
	ok(state, c, "x=; echo \"[${x=new}]\" ${x:=now} $x", { "[] now now" })
	-- The word is a word: parameters in it are read.
	ok(state, c, "unset z; echo ${z:-$HOME}", { "/home/admin" })
	ok(state, c, "unset z; echo \"${z:-a  b}\"", { "a  b" })
	-- :? and ? -- 4.4BSD expand.c's words when the word is left out.
	bad(state, c, "unset y; echo ${y:?}", "sh: y: parameter null or not set")
	bad(state, c, "unset y; echo ${y?}", "sh: y: parameter not set")
	ok(state, c, "y=; echo \"[${y?}]\"", { "[]" })
	bad(state, c, "y=; echo ${y:?custom msg}", "sh: y: custom msg")
	-- ksh88's length.
	ok(state, c, "x=abcdef; echo ${#x}", { "6" })
	ok(state, c, "unset x; echo ${#x}", { "0" })
	-- The four trims, shortest and longest from each end.
	ok(state, c, "v=/usr/lib/foo.tar.gz; echo ${v#*/} ${v##*/}",
		{ "usr/lib/foo.tar.gz foo.tar.gz" })
	ok(state, c, "v=/usr/lib/foo.tar.gz; echo ${v%.*} ${v%%.*}",
		{ "/usr/lib/foo.tar /usr/lib/foo" })
	ok(state, c, "v=abcabc; echo ${v#*b} ${v##*b} ${v%b*} ${v%%b*}",
		{ "cabc c abca a" })
	ok(state, c, "v=abcabc; echo ${v#[ab]} ${v%[!c]c} ${v#?} ${v#x}",
		{ "bcabc abca bcabc abcabc" })
	-- Quoting: a quoted or backslashed * is a star, a bare one is anything;
	-- the value of $p is a pattern and the value of "$p" is text.
	ok(state, c, "v='a*b'; echo ${v#\"a*\"} ${v#a\\*} ${v#a*}", { "b b *b" })
	ok(state, c, "p='*.gz'; v=a.gz; echo ${v%$p} \"${v%\"$p\"}\"", { "a a.gz" })
	-- Positional parameters in braces, $10 and past.
	ok(state, c, "set -- a b; echo ${1:-d} ${3:-d} ${#1} ${2} ${10-ten}", { "a d 1 b ten" })
	ok(state, c, "set -- 1 2 3 4 5 6 7 8 9 ten; echo ${10} $10", { "ten 10" })
	bad(state, c, "echo ${1=x}", "sh: 1: bad variable name")
	-- The special parameters in braces are their bare selves.
	ok(state, c, "set -- 'a b' c; for w in \"${@}\"; do echo \"<$w>\"; done; echo ${#} ${*}",
		{ "<a b>", "<c>", "2 a b c" })
	ok(state, c, "false; echo ${?}; echo \"[${!}]\"", { "1", "[]" })
	-- One substitution deep, and a bounded pattern.
	bad(state, c, "echo ${x:-$(echo no)}", "Syntax error: Bad substitution")
	bad(state, c, "x=aaa; echo ${x#" .. string.rep("a", CeroSecOS.MAX_TRIM_ITEMS + 1) .. "}",
		"sh: x: pattern too long")
	ok(state, c, "x=aaa; echo \"[${x#" .. string.rep("a", CeroSecOS.MAX_TRIM_ITEMS) .. "}]\"",
		{ "[aaa]" })
end

print("builtins_test: " .. count .. " checks passed")
