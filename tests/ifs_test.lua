-- IFS: field splitting, POSIX.2 XCU 2.6.5, and the 1993 sh that defined it.
-- Run from the repo root:
--   lua5.1 tests/ifs_test.lua
--
-- Every expected value here was checked against `dash` (Ubuntu's /bin/sh) on
-- the machine this was written on, `a::b` and `read`'s last-name-gets-the-
-- remainder edges included; a comment says so where the rule is not the
-- obvious one.

local DIR = "42/media/lua/shared/CeroSec/OS/"
local FILES = {
	"CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSDev", "CeroSecOSDisk", "CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath", "CeroSecOSScript",
	"CeroSecOSRadio",
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

local function fresh() return CeroSecOS.newState("ksp-front-01") end
local function open(state, name)
	local session, reason = CeroSecOS.login(state, name, "")
	if session == nil then error("cannot log in as " .. name .. ": " .. tostring(reason), 2) end
	return session
end

-- Runs one line as a foreground job and drains it, the way os_test.lua's own
-- `exec` does (trimmed of the machine-order and job-book plumbing this file
-- never needs): a single `read` inside a pipe answers from what was piped to
-- it, so every read bench here is `printf ... | ( IFS=... ; read ... )` and
-- never the interactive question.
local function exec(state, session)
	return function(line)
		if session.shvars == nil then session.shvars = {} end
		if session.shfuncs == nil then session.shfuncs = {} end
		local job = CeroSecOS.promptJob(state, session, line, session.shvars,
			session.status, nil, nil, session.shfuncs)
		if job == nil then error("cannot start: " .. line, 2) end
		local out = {}
		local turns = 0
		while not CeroSecOS.jobIsOver(job) and turns < 500 do
			turns = turns + 1
			CeroSecOS.jobStep(state, job, {}, 1000)
			for i = 1, #job.out do out[#out + 1] = job.out[i] end
			job.out = {}
			if job.state == "waiting" or job.state == "sleeping" then break end
		end
		for i = 1, #job.out do out[#out + 1] = job.out[i] end
		session.status = job.status
		return CeroSecOS.fit(out), job
	end
end

local function ok(state, session, line, wantLines)
	local lines = exec(state, session)(line)
	eq("`" .. line .. "` line count", #lines, #wantLines)
	for i = 1, #wantLines do
		eq("`" .. line .. "` line " .. i, lines[i], wantLines[i])
	end
end

--
-- 1. Compatibility: a script that never touches IFS is byte for byte what it
-- always was. Every one of these is a sample already exercised elsewhere
-- (os_test.lua, the manual's own examples) with IFS untouched -- unset, the
-- state every session starts in.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "for f in a b c; do echo $f; done", { "a", "b", "c" })
	ok(state, admin, "x='a  b'; for f in $x; do echo [$f]; done", { "[a]", "[b]" })
	ok(state, admin, "x='  a b  '; echo $x", { "a b" })
	ok(state, admin, 'x="a b"; echo "$x"', { "a b" })
	ok(state, admin, "for f in $(echo a  b   c); do echo [$f]; done",
		{ "[a]", "[b]", "[c]" })
	ok(state, admin, 'f(){ read x y; echo "$x/$y"; }; printf "a b\\n" | f', { "a/b" })
	ok(state, admin, "echo $*", { "" })
	ok(state, admin, 'f(){ y="$*"; echo "[$y]"; }; f', { "[]" })
end

--
-- 2. Unset reads as the default, and default is space, tab, newline.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	check("a fresh shell's IFS is unset", admin.shvars == nil or admin.shvars.IFS == nil)
	ok(state, admin, 'x="a\tb"; for f in $x; do echo [$f]; done', { "[a]", "[b]" })
	ok(state, admin, "IFS=' \t\n'; x='a  b'; for f in $x; do echo [$f]; done",
		{ "[a]", "[b]" })
end

--
-- 3. Empty IFS: no splitting at all, ever, on any unquoted expansion.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "IFS=; x='a b c'; for f in $x; do echo [$f]; done", { "[a b c]" })
	ok(state, admin, "IFS=; x='a b'; echo $x", { "a b" })
end

--
-- 4. Whitespace vs. non-whitespace delimiters (POSIX.2 2.6.5): leading and
-- trailing IFS whitespace is ignored; a non-whitespace delimiter always
-- delimits, even next to another one, even at the very start.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	-- IFS never touches literal script text, only an unquoted expansion's
	-- result: "a:b" typed straight is one word, whatever IFS holds.
	ok(state, admin, "IFS=:; echo a:b", { "a:b" })
	ok(state, admin, "IFS=:; x=a:b; for f in $x; do echo [$f]; done", { "[a]", "[b]" })
	ok(state, admin, "IFS=:; x=a::b; for f in $x; do echo [$f]; done",
		{ "[a]", "[]", "[b]" })
	ok(state, admin, "IFS=:; x=:a; for f in $x; do echo [$f]; done", { "[]", "[a]" })
	-- Confirmed against dash: a trailing delimiter with nothing after it
	-- does NOT force a further empty field -- "a:" is one field, not two.
	ok(state, admin, "IFS=:; x=a:; for f in $x; do echo [$f]; done", { "[a]" })
	ok(state, admin, "IFS=:; x=:; for f in $x; do echo [$f]; done", { "[]" })
	-- Whitespace next to a delimiter is the SAME separator, not a second
	-- one: "a :b" (space then colon) is two fields, not three.
	ok(state, admin, "IFS=' :'; x='a :b'; for f in $x; do echo [$f]; done",
		{ "[a]", "[b]" })
	ok(state, admin, "IFS=' :'; x='a ::b'; for f in $x; do echo [$f]; done",
		{ "[a]", "[]", "[b]" })
end

--
-- 5. A delimiter split across two parts of the same word still merges
-- correctly with adjacent whitespace on either side of the boundary.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "IFS=' :'; x='a '; y=':b'; for f in $x$y; do echo [$f]; done",
		{ "[a]", "[b]" })
	ok(state, admin, "IFS=:; x=a; y=:b; for f in $x$y; do echo [$f]; done",
		{ "[a]", "[b]" })
end

--
-- 6. "$*" joins with IFS's first byte; bare $* is split on the same IFS.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, 'f(){ echo "$*"; }; f a b c', { "a b c" })
	ok(state, admin, 'f(){ echo "$*"; }; IFS=:; f a b c', { "a:b:c" })
	ok(state, admin, 'f(){ echo "$*"; }; IFS=; f a b c', { "abc" })
	ok(state, admin, "f(){ for i in $*; do echo [$i]; done; }; IFS=:; f a b c",
		{ "[a]", "[b]", "[c]" })
end

--
-- 7. `read` splits on IFS; the LAST name gets everything left on the line,
-- unsplit, with only its own leading and trailing IFS whitespace gone.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, 'f2(){ read x y; echo "$x/$y"; }; IFS=:; printf "a::b:c\\n" | f2',
		{ "a/:b:c" })
	ok(state, admin, 'f3(){ read x y z; echo "$x/$y/$z"; }; IFS=:; printf "a::b:c\\n" | f3',
		{ "a//b:c" })
	ok(state, admin, 'f2(){ read x y; echo "[$x][$y]"; }; IFS=:; printf "a:\\n" | f2',
		{ "[a][]" })
	ok(state, admin, 'f2(){ read x y; echo "[$x][$y]"; }; IFS=" :"; printf "a :: b\\n" | f2',
		{ "[a][: b]" })
	ok(state, admin, 'f2(){ read x y; echo "[$x][$y]"; }; IFS=; printf "a b c\\n" | f2',
		{ "[a b c][]" })
end

--
-- 8. Command substitution keeps internal newlines and strips only the
-- trailing ones (POSIX.2 2.6.3) -- fixed alongside this topic because
-- unquoted, those newlines are what a plain $(cmd) then splits on.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, 'echo "$(printf "a\\nb\\n")"', { "a", "b" })
	ok(state, admin, 'echo "$(printf "a\\n\\nb\\n\\n\\n")"', { "a", "", "b" })
	ok(state, admin, "for f in $(printf 'a\\nb\\n'); do echo [$f]; done",
		{ "[a]", "[b]" })
end

--
-- N. Every new shell STARTS with IFS at space, tab and newline, set and not
-- exported (POSIX.2 2.5.3), so `${#IFS}` is 3 and the save-and-restore idiom
-- restores. With IFS unset, OIFS="$IFS" saved "" and IFS="$OIFS" then turned
-- splitting OFF for the rest of the script.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	admin.shvars = CeroSecOS.loginVars("/home/admin")
	admin.shexport = CeroSecOS.loginExported()
	ok(state, admin, "echo ${#IFS}", { "3" })
	ok(state, admin, 'x="a b:c"; OIFS="$IFS"; IFS=:; for w in $x; do echo "[$w]"; done; '
		.. 'IFS="$OIFS"; for w in $x; do echo "<$w>"; done',
		{ "[a b]", "[c]", "<a>", "<b:c>" })
	-- A script is a new sh: IFS at the default again, even one exported colon.
	ok(state, admin, 'printf "echo \\${#IFS}; x=a:b; echo \\$x\\n" > s.sh', {})
	ok(state, admin, "IFS=:; export IFS; sh s.sh", { "3", "a:b" })
	ok(state, admin, 'IFS="$OIFS"; sh s.sh', { "3", "a:b" })
	-- A subshell is not a new sh: $( ) and a stage keep the caller's.
	ok(state, admin, 'IFS=:; echo $(echo ${#IFS}); echo ${#IFS} | cat; IFS="$OIFS"',
		{ "1", "1" })
	-- A job nobody handed an environment -- cron's case -- has it too.
	eq("a cron line's shell has IFS", CeroSecOS.newJob({ prog = {} }).vars.IFS, " \t\n")
	-- And a shell saved before there was one reads unset as the same three.
	local old = open(state, "admin")
	old.shvars = { PATH = CeroSecOS.DEFAULT_PATH }
	ok(state, old, "echo ${#IFS}; x='a  b'; for w in $x; do echo \"[$w]\"; done",
		{ "0", "[a]", "[b]" })
end

--
-- N+1. Bare $@ splits exactly as bare $* does: each positional parameter a
-- field, then IFS inside each (POSIX.2 2.5.2). $@ used to be the arguments
-- joined by a blank and split again, so with IFS=: "c d" became one field
-- only by luck and "a:b c" was never two; with IFS empty every argument is
-- still its own field. And "${y:-$*}" joins on IFS's first byte like "$*".
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, 'f(){ IFS=:; for w in $@; do echo "[$w]"; done; '
		.. 'for w in $*; do echo "<$w>"; done; }; f "a:b" "c d"',
		{ "[a]", "[b]", "[c d]", "<a>", "<b>", "<c d>" })
	ok(state, admin, 'f(){ IFS=; for w in $@; do echo "[$w]"; done; '
		.. 'for w in $*; do echo "<$w>"; done; }; f "a b" c',
		{ "[a b]", "[c]", "<a b>", "<c>" })
	ok(state, admin, 'f(){ IFS=" :"; for w in $@; do echo "[$w]"; done; }; f "a " ":b"',
		{ "[a]", "[]", "[b]" })
	ok(state, admin, 'f(){ IFS=-; echo "${y:-$*}" "$*"; }; f a b', { "a-b a-b" })
	ok(state, admin, 'unset IFS; f(){ for w in pre$@post; do echo "[$w]"; done; }; f x "" y',
		{ "[prex]", "[ypost]" })
end

print("ifs_test: " .. count .. " checks passed")

