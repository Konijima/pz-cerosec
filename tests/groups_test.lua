-- { list; } and ( list ): the brace group and the subshell, POSIX.2 XCU
-- 2.9.4, as 4.4BSD-Lite2 sh builds them (parser.c's command(): TBEGIN and
-- TLP, NBRACE-less and NSUBSHELL; eval.c's evalsubshell forks, a brace
-- list is evaltree in place). Run from the repo root:
--   lua5.1 tests/groups_test.lua
--
-- The syntax errors and the statuses are what dash (Ubuntu's /bin/sh, the
-- same parser.c lineage) printed for the same line, except where a comment
-- says otherwise; the rest is 4.4BSD-Lite2's wording (`directory
-- nonexistent`, wc's eight columns), as everywhere on this machine.
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
-- And the console's own repair, which is the path a save comes back by: the
-- functions a shell holds are handed back through CeroSec.repairConsole.
do
	local path = "42/media/lua/shared/CeroSec/CeroSecDefs.lua"
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
-- it, so a read in a pipe reads the pipe and
-- never asks.
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

local function bad(state, session, line, want)
	local job, reason = CeroSecOS.promptJob(state, session, line, session.shvars,
		session.status, nil, nil, session.shfuncs)
	eq("`" .. line .. "` never becomes a job", job, nil)
	eq("`" .. line .. "` says", reason, want)
end

local function put(state, path, text)
	local done, why = CeroSecOS.writeFile(state, CeroSecOS.rootSession(), path, text, false, 100)
	if done == nil then error("cannot write " .. path .. ": " .. tostring(why), 2) end
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), path)
	node.owner = "admin"
	node.mode = 755
end

--
-- 1. Redirects, pipes, && and || take the group whole.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "{ echo a; echo b; } > g; cat g", { "a", "b" })
	-- 2>&1 after the group joins the two streams of everything in it.
	ok(state, admin, "{ echo o; cat nosuch; } > g 2>&1; cat g",
		{ "o", "cat: nosuch: No such file or directory" })
	ok(state, admin, "{ echo a; echo b 1>&2; } 2>/dev/null", { "a" })
	ok(state, admin, "( echo a; echo b ) > g; cat g", { "a", "b" })
	-- A target the group cannot open: nothing in it runs, and the shell says
	-- what it says for a simple command's (`echo a > /nope/x`).
	ok(state, admin, "{ echo ran; } > /nope/x; echo $?",
		{ "cannot create /nope/x: directory nonexistent", "1" })
	ok(state, admin, "( echo ran ) > /nope/x; echo $?",
		{ "cannot create /nope/x: directory nonexistent", "1" })
	ok(state, admin, "{ echo a; echo b; } | wc -l", { "       2" })
	ok(state, admin, "( echo a; echo b ) | wc -l", { "       2" })
	ok(state, admin, "echo x | { read v; echo got $v; }", { "got x" })
	ok(state, admin, "true && { echo y; } || { echo n; }", { "y" })
	ok(state, admin, "false && { echo y; } || { echo n; }", { "n" })
	ok(state, admin, "( false ) || echo failed", { "failed" })
	ok(state, admin, "{ false; true; } && echo last", { "last" })
end

--
-- 2. A group in front of a reader that is over. The group is not a command of
-- its own: the first command inside it runs, and the stage stops after it
-- (the "pipe" entry of CeroSecOS.DEVIATIONS). Before the fix nothing inside
-- ran at all and f was never made.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "{ echo a > f; echo b > g; } | true; cat f; ls g",
		{ "a", "ls: g: No such file or directory" })
	ok(state, admin, "( echo a > f2; echo b > g2 ) | true; cat f2; ls g2",
		{ "a", "ls: g2: No such file or directory" })
end

--
-- 3. What a subshell changes stays in it: variables, the working directory,
-- the positional parameters (set -- and shift), functions and traps. Asked
-- on the NEXT line too, where a leak through the console's own tables shows.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "v=1; ( v=2; echo in $v ); echo out $v", { "in 2", "out 1" })
	ok(state, admin, "( v=9; export w=8; cd /; g() { :; } )", {})
	ok(state, admin, "echo v=$v w=$w; pwd", { "v=1 w=", "/home/admin" })
	ok(state, admin, "g", { "g: not found" })
	ok(state, admin, "set -- a b; ( set -- x; echo $# $1 ); echo $# $1", { "1 x", "2 a" })
	ok(state, admin, "set -- a b c; ( shift; echo $1 ); echo $1", { "b", "a" })
	-- The braces are this shell: the same lines, changed.
	ok(state, admin, "v=1; { v=2; }; echo $v", { "2" })
	ok(state, admin, "set -- a b c; { shift; }; echo $1", { "b" })
	-- A subshell starts with the parent's functions and variables.
	ok(state, admin, "h() { echo h; }; x=5; ( h; echo $x )", { "h", "5" })
end

--
-- 4. exit, return, break and traps. A subshell is a wall for all of them;
-- braces are not.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "( exit 7 ); echo $?", { "7" })
	-- exit with no number is the status of the last command (XCU exit;
	-- 4.4BSD-Lite2 main.c exitcmd).
	ok(state, admin, "false; ( exit ); echo $?", { "1" })
	ok(state, admin, "( exec echo a ); echo b", { "a", "b" })
	ok(state, admin, "f() { ( return 2 ); echo r $?; }; f", { "r 2" })
	ok(state, admin, "f() { { return 3; }; echo no; }; f; echo $?", { "3" })
	ok(state, admin, "for i in 1 2; do ( break ); echo i$i; done", { "i1", "i2" })
	ok(state, admin, "for i in 1 2; do { break; }; echo no; done; echo i=$i", { "i=1" })

	-- At the glass, `(exit)` is not a logout; `{ exit; }` is what `exit` is.
	local _, job = exec(state, admin)("( exit 3 )")
	eq("(exit) at the prompt orders the console nothing", job.control, nil)
	local _, job2 = exec(state, admin)("exit")
	local _, job3 = exec(state, admin)("{ exit; }")
	check("exit at the prompt orders one (" .. tostring(job2.control) .. ")",
		job2.control ~= nil)
	eq("{ exit; } at the prompt is exit", job3.control, job2.control)

	put(state, "/home/admin/braces.sh", "echo top\n{ exit 3; }\necho never\n")
	ok(state, admin, "sh braces.sh; echo $?", { "top", "3" })
	put(state, "/home/admin/trap.sh",
		"trap 'echo outer' EXIT\n( trap 'echo inner' EXIT; exit 2 )\necho sub $?\n")
	ok(state, admin, "sh trap.sh", { "inner", "sub 2", "outer" })
	-- A trap set in braces is the script's own and fires at its end.
	put(state, "/home/admin/btrap.sh", "{ trap 'echo t' EXIT; }\necho after\n")
	ok(state, admin, "sh btrap.sh", { "after", "t" })
	-- Written over several lines, as a script writes them.
	put(state, "/home/admin/multi.sh",
		"x=1\n{\n  echo in\n  x=2\n}\n(\n  x=3\n  echo sub $x\n)\necho $x\n")
	ok(state, admin, "sh multi.sh", { "in", "sub 3", "2" })
end

--
-- 5. Nesting, and groups inside $( ).
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "{ { { echo deep; }; }; }", { "deep" })
	ok(state, admin, "( ( ( echo deep ) ) )", { "deep" })
	ok(state, admin, "( { ( echo mixed ); } )", { "mixed" })
	ok(state, admin, "echo $( ( echo a ) ) $( { echo b; } )", { "a b" })
	ok(state, admin, "x=$( v=2; ( v=3 ); echo $v ); echo $x", { "2" })
end

--
-- 6. A function body may be any compound command (XCU 2.9.5; parser.c:
-- `n->nfunc.body = command()`): the subshell one runs in a copy at every
-- call, and a redirect after its ")" is the call's.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "f() ( x=2; echo in $x ); x=1; f; echo $x", { "in 2", "1" })
	-- Kept from one line to the next, as its source is re-read.
	ok(state, admin, "f", { "in 2" })
	ok(state, admin, "g() ( echo gg ) > gf; g; cat gf", { "gg" })
	-- The source it keeps ends on its last token, a `2>&1` included: a
	-- redirect token without an end kept the text "e" alone, and the next
	-- line found no function there.
	ok(state, admin, "e() ( echo o; cat nosuch ) 2>&1", {})
	ok(state, admin, "e | wc -l", { "       2" })
	ok(state, admin, "m() if true; then echo yes; fi; m", { "yes" })
	-- XCU 2.9.5: `function_body : compound_command`. parser.c and dash take
	-- a simple command too; POSIX does not, and neither does this machine.
	bad(state, admin, "n() echo x", "Syntax error: word unexpected (expecting \"{\")")
end

--
-- 7. { and } are reserved words: only where a command starts. ( and ) are
-- operators everywhere outside quotes.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "echo {", { "{" })
	ok(state, admin, "echo a } b", { "a } b" })
	ok(state, admin, "for i in { }; do echo $i; done", { "{", "}" })
	ok(state, admin, "echo '(a)' \"{\"", { "(a) {" })
	ok(state, admin, "type {", { "{ is a shell keyword" })
	-- `{echo` is a word; the `}` after the `;` starts a command. dash:
	-- `Syntax error: "}" unexpected`.
	bad(state, admin, "{echo a;}", "Syntax error: \"}\" unexpected")
	bad(state, admin, "}", "Syntax error: \"}\" unexpected")
	bad(state, admin, ")", "Syntax error: \")\" unexpected")
	bad(state, admin, "echo a (b)", "Syntax error: \"(\" unexpected")
	-- One word before "(" is a function definition, which wants ")" next:
	-- parser.c's `if (readtoken() != TRP) synexpect(TRP)`.
	bad(state, admin, "echo (a)", "Syntax error: word unexpected (expecting \")\")")
	-- The empty list is refused, as for every other body.
	bad(state, admin, "{ }", "Syntax error: \"}\" unexpected")
	bad(state, admin, "( )", "Syntax error: \")\" unexpected")
	bad(state, admin, "{ echo a", "Syntax error: end of file unexpected (expecting \"}\")")
	bad(state, admin, "( echo a", "Syntax error: end of file unexpected (expecting \")\")")
	bad(state, admin, "{ echo; } foo", "Syntax error: word unexpected")
	bad(state, admin, "( echo ) foo", "Syntax error: word unexpected")
end

--
-- 8. Deep nesting is refused at the machine's own ceiling, before anything
-- runs; the subshell's endless loop is hostile_test's business.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	local deep = string.rep("( ", 40) .. "echo x" .. string.rep(" )", 40)
	local job, reason = CeroSecOS.promptJob(state, admin, deep, {}, 0)
	eq("forty brackets deep never becomes a job", job, nil)
	eq("and says why", reason, "sh: too deeply nested")
	local braces = string.rep("{ ", 40) .. "echo x;" .. string.rep(" }", 40)
	job, reason = CeroSecOS.promptJob(state, admin, braces, {}, 0)
	eq("forty braces deep never becomes a job", job, nil)
	eq("and says why", reason, "sh: too deeply nested")
end

--
-- 9. A line with no command name answers with the status of its last
-- command substitution (POSIX.2 XCU 2.9.1), and a bare return with the
-- status of the last command run (XCU return). dash printed each of these.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "x=$(exit 4); echo $?", { "4" })
	ok(state, admin, "x=$(false); echo $?", { "1" })
	ok(state, admin, "x=`false`; echo $?", { "1" })
	ok(state, admin, "$(false); echo $?", { "1" })
	ok(state, admin, "x=$(true) y=$(false); echo $?", { "1" })
	ok(state, admin, "x=$(false) y=$(true); echo $?", { "0" })
	ok(state, admin, "x=$(false) > g; echo $?", { "1" })
	-- A command name still has the last word, and no substitution is 0.
	ok(state, admin, "x=$(false) true; echo $?", { "0" })
	ok(state, admin, "false; x=1; echo $?", { "0" })
	ok(state, admin, "f() { false; return; }; f; echo $?", { "1" })
	ok(state, admin, "f() { true; return; }; false; f; echo $?", { "0" })
	ok(state, admin, "f() { false; return 0; }; f; echo $?", { "0" })
end

--
-- 10. Every spelling of a definition the parser takes survives a save: the
-- text the shell kept goes back through CeroSec.repairConsole, the way a
-- console comes back out of modData, and each one still runs.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	local forms = {
		{ "a", "a(){ echo a; }", { "a" } },
		{ "b", "b (){ echo b; }", { "b" } },
		{ "c", "c ( ) { echo c; }", { "c" } },
		{ "d", "d\t(\t)\t{ echo d; }", { "d" } },
		{ "e", "e()\n{ echo e; }", { "e" } },
		{ "s", "s() ( echo s )", { "s" } },
		{ "r", "r() ( echo r; cat nosuch ) 2>&1", { "r",
			"cat: nosuch: No such file or directory" }, "r > o; cat o" },
		{ "t", "t() { echo t > tf; cat tf; }", { "t" } },
	}
	for i = 1, #forms do ok(state, admin, forms[i][2], {}) end
	local held = CeroSec.repairConsole({ lines = {}, shfuncs = admin.shfuncs })
	eq("every one of them comes back", #CeroSecOS.funcNames(held.shfuncs), #forms)
	local back = open(state, "admin")
	back.shfuncs = held.shfuncs
	for i = 1, #forms do
		local f = forms[i]
		eq("`" .. f[2] .. "` is kept as it was typed", held.shfuncs[f[1]],
			admin.shfuncs[f[1]])
		ok(state, back, f[4] or f[1], f[3])
	end
end

print("groups_test: " .. count .. " assertions passed")
