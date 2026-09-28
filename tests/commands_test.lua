-- The commands that came in with 0.7.0 -- rmdir, expr, uname -- and the
-- flags and output formats brought into line with 4.4BSD beside them, each
-- line typed at a prompt and its answer held against what the 4.4BSD tool
-- (or the tool the comment above the command names) printed. Run from the
-- repo root:
--   lua5.1 tests/commands_test.lua
--
-- Every case runs, and every failure is listed, before the exit status says
-- whether any did: breaking one command on purpose shows every line it
-- turns red, not only the first.

local DIR = "42/media/lua/shared/CeroSec/OS/"
local FILES = {
	"CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSDev", "CeroSecOSDisk",
	"CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath", "CeroSecOSScript", "CeroSecOSRadio",
	"CeroSecOSShell", "CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers", "CeroSecOSVM",
}
for i = 1, #FILES do
	local path = DIR .. FILES[i] .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end

local count, failed = 0, {}
local function eq(what, got, want)
	count = count + 1
	if got ~= want then
		failed[#failed + 1] = what .. ": got " .. tostring(got) .. ", want " .. tostring(want)
	end
end

local FIXED = CeroSecOS.timeFromParts(1993, 7, 8, 14, 32, 0)

local function open(state, name)
	local session, reason = CeroSecOS.login(state, name, "")
	if session == nil then error("cannot log in as " .. name .. ": " .. tostring(reason), 2) end
	session.shvars, session.shfuncs = {}, {}
	return session
end

-- A line at the prompt, run to its end: its lines, and $? after it.
local function exec(state, session, line, env)
	env = env or { now = FIXED, nowMs = 1000, jobs = {} }
	local job, refusal = CeroSecOS.promptJob(state, session, line, session.shvars,
		session.status, nil, nil, session.shfuncs)
	if job == nil then return { refusal }, 2 end
	local out, turns = {}, 0
	while not CeroSecOS.jobIsOver(job) and turns < 500 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, env, 1000)
		for k = 1, #job.out do out[#out + 1] = job.out[k] end
		job.out = {}
		if job.state == "waiting" or job.state == "sleeping" or job.spawn ~= nil then break end
	end
	for k = 1, #job.out do out[#out + 1] = job.out[k] end
	session.user = job.session.user
	session.cwd = job.session.cwd
	session.status = job.status
	return out, job.status
end

-- The whole answer, every line in order, and the status.
local function case(state, session, line, want, wantStatus, env)
	local got, status = exec(state, session, line, env)
	local gotText = table.concat(got, "|")
	-- Folded at the screen's width the way every line of output is.
	local wantText = table.concat(CeroSecOS.fit(want), "|")
	eq("`" .. line .. "`", gotText, wantText)
	if wantStatus ~= nil then eq("`" .. line .. "` status", status, wantStatus) end
end

local state = CeroSecOS.newState("ksp-front-01")
local admin = open(state, "admin")
local root = open(state, "root")

--
-- rmdir: 4.4BSD's rmdir.c, no flags at all.
--
case(state, admin, "mkdir e; rmdir e; ls", {}, 0)
case(state, admin, "mkdir f; touch f/x; rmdir f", { "rmdir: f: Directory not empty" }, 1)
case(state, admin, "touch g; rmdir g", { "rmdir: g: Not a directory" }, 1)
case(state, admin, "rmdir nosuch", { "rmdir: nosuch: No such file or directory" }, 1)
-- A failure does not stop the operands after it.
case(state, admin, "mkdir h; rmdir nosuch h; echo $?; ls h", {
	"rmdir: nosuch: No such file or directory", "1",
	"ls: h: No such file or directory" }, 1)
case(state, admin, "rmdir -p f", {
	"rmdir: illegal option -- p", "usage: rmdir <dir>..." }, 1)
case(state, admin, "rmdir", { "rmdir: usage: rmdir <dir>..." }, 1)
case(state, admin, "rm -r f g", {}, 0)
-- A mount point is EBUSY, whatever the disk on it holds.
state.floppy = CeroSecOS.newFloppy()
case(state, admin, "newfs /dev/fd0 > /dev/null; mount /dev/fd0 /mnt; touch /mnt/f", {}, 0)
case(state, root, "rmdir /mnt", { "rmdir: /mnt: Device busy" }, 1)
case(state, admin, "umount /mnt", {}, 0)
-- And it is a word the shell completes, like every name in /bin.
local done = CeroSecOS.complete(state, admin, "rmd", 3)
eq("rmd completes to rmdir", type(done) == "table" and done.replacement or tostring(done), "rmdir ")

--
-- expr: arithmetic, comparison, | and &, status 0/1/2.
--
case(state, admin, "expr 2 + 3 \\* 4", { "14" }, 0)
case(state, admin, "expr \\( 2 + 3 \\) \\* 4", { "20" }, 0)
case(state, admin, "expr -7 / 2", { "-3" }, 0)
case(state, admin, "expr -7 % 2", { "-1" }, 0)
case(state, admin, "expr 3 - 3", { "0" }, 1)
case(state, admin, "expr 10 \\< 9", { "0" }, 1)
case(state, admin, "expr b \\> a", { "1" }, 0)
case(state, admin, "expr 10 = 10", { "1" }, 0)
case(state, admin, "expr '' \\| x", { "x" }, 0)
case(state, admin, "expr 0 \\& x", { "0" }, 1)
-- 4.4BSD's expr.y: yyerror prints the words bare and exits 2.
case(state, admin, "expr a + 1", { "non-numeric argument" }, 2)
case(state, admin, "expr 1 / 0", { "Divide by zero" }, 2)
case(state, admin, "expr 1 % 0", { "Remainder by zero" }, 2)
case(state, admin, "expr 1 +", { "syntax error" }, 2)
case(state, admin, "expr", { "syntax error" }, 2)
case(state, admin, "expr " .. string.rep("\\( ", 33) .. "1" .. string.rep(" \\)", 33),
	{ "yacc stack overflow" }, 2)
case(state, admin, "expr " .. string.rep("\\( ", 32) .. "1" .. string.rep(" \\)", 32),
	{ "1" }, 0)
-- 2 is expr's own, and the next command starts from nothing.
case(state, admin, "expr 1 +; false; echo $?", { "syntax error", "1" }, 0)
case(state, admin, "x=$(expr 4 \\* 5); echo $x", { "20" }, 0)

--
-- uname: -s alone by default, and -a in uname.c's fixed order.
--
case(state, admin, "uname", { "CeroSec OS" }, 0)
case(state, admin, "uname -n", { "ksp-front-01" }, 0)
case(state, admin, "uname -ns", { "CeroSec OS ksp-front-01" }, 0)
case(state, admin, "uname -a", { "CeroSec OS ksp-front-01 " .. CeroSecOS.VERSION
	.. " SYSTEM_VERSION " .. tostring(CeroSecOS.SYSTEM_VERSION) }, 0)
case(state, admin, "uname -x", {
	"uname: illegal option -- x", "usage: uname [-asnrv]" }, 1)
case(state, admin, "uname foo", { "uname: usage: uname [-asnrv]" }, 1)

--
-- rm -f: ENOENT forgiven and nothing else.
--
case(state, admin, "rm -f nosuch; echo $?", { "0" }, 0)
case(state, admin, "rm nosuch", { "rm: nosuch: No such file or directory" }, 1)
case(state, admin, "rm -f /etc/motd", { "rm: /etc/motd: Permission denied" }, 1)
case(state, admin, "mkdir d; touch d/a; rm -rf d; ls", {}, 0)
case(state, admin, "rm -f", { "rm: usage: rm [-rf] <path>..." }, 1)

--
-- kill: signals by number and by name, 4.4BSD kill.c's refusals.
--
do
	local env = { now = FIXED, nowMs = 1000, jobs = {} }
	local function job(id)
		local j = CeroSecOS.newJob({ id = id, prog = {}, args = {}, name = "sh",
			cmd = "sh go.sh", session = admin })
		j.n = 1
		env.jobs = { j }
		return j
	end
	local j = job(42)
	case(state, admin, "kill -9 %1", {}, 0, env)
	eq("kill -9 asks for the job", j.killReq, "user")
	j = job(42)
	case(state, admin, "kill -s KILL 42", {}, 0, env)
	eq("kill -s KILL asks", j.killReq, "user")
	j = job(42)
	case(state, admin, "kill -s sigterm %1", {}, 0, env)
	eq("a name in any case, with sig in front", j.killReq, "user")
	j = job(42)
	case(state, admin, "kill -HUP %1", {}, 0, env)
	eq("kill -HUP asks", j.killReq, "user")
	j = job(42)
	case(state, admin, "kill -s 0 %1", {}, 0, env)
	eq("signal 0 only looks", j.killReq, nil)
	-- kill.c's two lines, each folded at the last blank that fits sixty
	-- columns, never inside a name (the "kill" deviation).
	local list1 = "hup int quit ill trap abrt emt fpe kill bus segv sys pipe"
	local list1b = "alrm term urg"
	local list2 = "stop tstp cont chld ttin ttou io xcpu xfsz vtalrm prof winch"
	local list2b = "info usr1 usr2"
	case(state, admin, "kill -l", { list1, list1b, list2, list2b }, 0, env)
	case(state, admin, "kill -FOO %1", {
		"kill: unknown signal FOO; valid signals:", list1, list1b, list2, list2b }, 1, env)
	case(state, admin, "kill -99 %1", {
		"kill: unknown signal 99; valid signals:", list1, list1b, list2, list2b }, 1, env)
	case(state, admin, "kill -9x %1", { "kill: illegal signal number: 9x" }, 1, env)
	case(state, admin, "kill -s", { "kill: option requires an argument -- s",
		"kill: usage: kill [-<signal>|-s <signal>] <id>|%<n>" }, 1, env)
	j = job(42)
	case(state, admin, "kill -STOP %1", { "kill: stop: not honoured" }, 1, env)
	eq("and a refused signal asks nothing", j.killReq, nil)
end

--
-- tail +N: from line N to the end.
--
case(state, admin, "printf 'a\\nb\\nc\\n' > t; tail +2 t", { "b", "c" }, 0)
case(state, admin, "printf 'a\\nb\\nc\\n' | tail +3", { "c" }, 0)
case(state, admin, "tail +1 t", { "a", "b", "c" }, 0)

--
-- printf: field, flags, conversions, reuse, \NNN.
--
case(state, admin, "printf '[%5s][%-5s][%.2s]\\n' ab ab abc", { "[   ab][ab   ][ab]" }, 0)
case(state, admin, "printf '[%05d][%-4d][%.3d][%d]\\n' 42 7 5 -3", { "[00042][7   ][005][-3]" }, 0)
case(state, admin, "printf '%x %o %c %%\\n' 255 8 hello", { "ff 10 h %" }, 0)
case(state, admin, "printf '%s\\n' a b c", { "a", "b", "c" }, 0)
case(state, admin, "printf '%s=%d\\n' a 1 b 2", { "a=1", "b=2" }, 0)
case(state, admin, "printf 'x\\101\\102\\n'", { "xAB" }, 0)
-- \NNN names no control byte here: \1 makes nothing, \011 is a tab.
case(state, admin, "printf 'a\\1b\\011c\\n'", { "ab\tc" }, 0)

--
-- test -s, -h, -L.
--
case(state, admin, "touch empty; echo x > full; ln -s full lnk", {}, 0)
case(state, admin, "[ -s full ] && echo y", { "y" }, 0)
case(state, admin, "[ -s empty ] || echo n", { "n" }, 0)
case(state, admin, "[ -s nosuch ] || echo n", { "n" }, 0)
case(state, admin, "mkdir dd; [ -s dd ] && echo y", { "y" }, 0)
case(state, admin, "[ -h lnk ] && echo y", { "y" }, 0)
case(state, admin, "[ -L lnk ] && echo y", { "y" }, 0)
case(state, admin, "[ -h full ] || echo n", { "n" }, 0)

--
-- touch with several names; a failure does not stop the rest.
--
case(state, admin, "touch t1 t2 t3; ls t1 t2 t3", { "t1  t2  t3" }, 0)
case(state, admin, "touch /etc/x t4; echo $?; ls t4", {
	"touch: /etc/x: Permission denied", "1", "t4" }, 0)

--
-- The output formats: wc's " %7ld", uniq -c's "%4d ", which's csh line.
--
case(state, admin, "printf 'a b\\nc\\n' > w; wc w", { "       2       3       6 w" }, 0)
case(state, admin, "wc -l w", { "       2 w" }, 0)
case(state, admin, "cat w | wc -l", { "       2" }, 0)
case(state, admin, "printf 'a\\na\\nb\\n' | uniq -c", { "   2 a", "   1 b" }, 0)
-- 4.3BSD's which.csh ended on that echo, so its status is 0.
case(state, admin, "which nosuch", { "no nosuch in " .. string.gsub(CeroSecOS.DEFAULT_PATH, ":", " ") }, 0)
case(state, admin, "which nosuch > /dev/null; echo $?", { "0" }, 0)
case(state, admin, "which ls", { "/bin/ls" }, 0)

--
-- useradd and userdel say nothing when they did it.
--
case(state, root, "useradd bob", {}, 0)
case(state, root, "grep -c '^bob:' /etc/passwd", { "1" }, 0)
case(state, root, "userdel bob", {}, 0)
case(state, root, "grep -c '^bob:' /etc/passwd", { "0" }, 1)

if #failed > 0 then
	for i = 1, #failed do print("FAIL: " .. failed[i]) end
	print(#failed .. " of " .. count .. " checks failed")
	os.exit(1)
end
print("commands_test: " .. count .. " checks passed")
