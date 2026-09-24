-- What the machine SAYS when it refuses, held to what 1993 printed. Run
-- from the repo root:
--   lua5.1 tests/errors_test.lua
--
-- One bench per class of message, each against its source in 4.4BSD-Lite2:
--   a command's refusal     strerror(3), lib/libc/gen/errlst.c
--   a flag it does not know  getopt(3), lib/libc/stdlib/getopt.c, and
--                            the usage() line after it (bin/cat/cat.c)
--   what sh says itself      bin/sh/error.c's errormsg[] (lower case),
--                            exec.c ("%s: %s", E_EXEC), redir.c
--                            ("cannot create %s: %s", E_CREAT)
--   a line sh cannot parse   bin/sh/parser.c synexpect()/synerror()
--   su and passwd            usr.bin/su/su.c ("Sorry"),
--                            usr.bin/passwd/local_passwd.c (EACCES)
-- os_test pins every command's own line; this file pins the TABLE and
-- the status each kind of refusal leaves in $?, which is the state a
-- script tests and the one thing a changed wording can quietly break.

local DIR = "42/media/lua/shared/CeroSec/OS/"
local FILES = {
	"CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSDev", "CeroSecOSDisk",
	"CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath", "CeroSecOSScript", "CeroSecOSRadio",
	"CeroSecOSShell", "CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers", "CeroSecOSVM",
}
for i = 1, #FILES do
	local chunk, err = loadfile(DIR .. FILES[i] .. ".lua")
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

-- A line typed at the prompt, the way the scheduler runs one: the job is
-- made, stepped until it stops, and drained. The lines, and $? after.
local function run(state, session, line)
	session.shvars = session.shvars or {}
	session.shfuncs = session.shfuncs or {}
	local job, refusal = CeroSecOS.promptJob(state, session, line, session.shvars,
		session.status, nil, nil, session.shfuncs)
	if job == nil then return CeroSecOS.fit({ refusal }), 2 end
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
	session.status = job.status
	return CeroSecOS.fit(out), job.status
end

local function says(state, session, line, want, wantStatus)
	local lines, status = run(state, session, line)
	eq("`" .. line .. "` line count", #lines, #want)
	for i = 1, #want do eq("`" .. line .. "` line " .. i, lines[i], want[i]) end
	if wantStatus ~= nil then eq("`" .. line .. "` leaves $?", status, wantStatus) end
end

local function put(state, path, text, mode)
	local done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(), path, text, false)
	if done == nil then error("cannot write " .. path .. ": " .. tostring(reason), 2) end
	if mode ~= nil then
		CeroSecOS.getNode(state, CeroSecOS.rootSession(), path).mode = mode
	end
end

--
-- 1. strerror(3). The table is errlst.c's text, letter for letter: a bench
-- that compared the table with itself would pass whatever it said.
--
do
	local ERRLST = {
		["no such file"] = "No such file or directory",           -- 2 ENOENT
		["permission denied"] = "Permission denied",              -- 13 EACCES
		["file exists"] = "File exists",                          -- 17 EEXIST
		["not a directory"] = "Not a directory",                  -- 20 ENOTDIR
		["is a directory"] = "Is a directory",                    -- 21 EISDIR
		["file too large"] = "File too large",                    -- 27 EFBIG
		["disk full"] = "No space left on device",                -- 28 ENOSPC
		["too many levels of symbolic links"] =
			"Too many levels of symbolic links",                  -- 62 ELOOP
		["directory not empty"] = "Directory not empty",          -- 66 ENOTEMPTY
	}
	local n = 0
	for code, text in pairs(ERRLST) do
		n = n + 1
		eq("strerror of " .. code, CeroSecOS.strerror(code), text)
	end
	for code in pairs(CeroSecOS.STRERROR) do
		check("the table has nothing errlst.c does not: " .. code, ERRLST[code] ~= nil)
	end
	-- A reason no errno named goes through untouched.
	eq("a reason with no errno is left alone", CeroSecOS.strerror("is a device"), "is a device")

	local state = CeroSecOS.newState("ksp-front-01")
	local admin = CeroSecOS.login(state, "admin", "")
	says(state, admin, "cat nosuch", { "cat: nosuch: No such file or directory" }, 1)
	says(state, admin, "ls /root", { "ls: /root: Permission denied" }, 1)
	says(state, admin, "cat /etc", { "cat: /etc: Is a directory" }, 1)
end

--
-- 2. getopt(3): "illegal option -- x" under the program's name, no dash on
-- the letter, and the usage line the program prints after it.
--
do
	local state = CeroSecOS.newState("ksp-front-01")
	local admin = CeroSecOS.login(state, "admin", "")
	says(state, admin, "cat -z", { "cat: illegal option -- z",
		"usage: " .. CeroSecOS.commandUsage("cat") }, 1)
	-- The letter getopt stopped on, not the word: -lz stops on z.
	says(state, admin, "ls -lz", { "ls: illegal option -- z",
		"usage: " .. CeroSecOS.commandUsage("ls") }, 1)
	-- And the literal usage line, so the second line cannot drift silently.
	eq("cat's usage", CeroSecOS.commandUsage("cat"), "cat [-n] [file]...")
end

--
-- 3. What sh says itself: lower case, from its own table, and the status a
-- script tests -- 127 for nothing to run, 126 for something it may not.
--
do
	local state = CeroSecOS.newState("ksp-front-01")
	local admin = CeroSecOS.login(state, "admin", "")
	says(state, admin, "nosuch", { "nosuch: not found" }, 127)
	says(state, admin, "./missing.sh", { "./missing.sh: not found" }, 127)
	put(state, "/home/admin/noexec.sh", "echo hi", 644)
	CeroSecOS.getNode(state, CeroSecOS.rootSession(), "/home/admin/noexec.sh").owner = "admin"
	says(state, admin, "./noexec.sh", { "./noexec.sh: permission denied" }, 126)
	-- Found on PATH and not runnable: find_command's own EACCES, the same
	-- lower-case word, and 126.
	CeroSecOS.getNode(state, CeroSecOS.rootSession(), "/bin/date").mode = 644
	says(state, admin, "date", { "date: permission denied" }, 126)
	-- A directory run is execve(2)'s EACCES.
	says(state, admin, "/home/admin", { "/home/admin: permission denied" }, 126)
	-- A redirect sh could not open: redir.c's line, signed by nobody at the
	-- prompt, and the command never ran.
	says(state, admin, "echo hi > /etc/x", { "cannot create /etc/x: permission denied" })
	check("and the line failed", admin.status ~= 0)
	says(state, admin, "echo hi > /nodir/x", { "cannot create /nodir/x: directory nonexistent" })
	says(state, admin, "echo hi > /etc", { "cannot create /etc: is a directory" })
	eq("ENOSPC at a redirect is sh's own", CeroSecOS.sherror("disk full"), "file system full")
end

--
-- 4. Syntax: synerror()'s "Syntax error: " and synexpect()'s token names,
-- bare at the prompt and "name: line: " in a file.
--
do
	local state = CeroSecOS.newState("ksp-front-01")
	local admin = CeroSecOS.login(state, "admin", "")
	says(state, admin, "fi", { "Syntax error: \"fi\" unexpected" }, 2)
	says(state, admin, "cat a | | b", { "Syntax error: \"|\" unexpected" }, 2)
	says(state, admin, "echo \"open", { "Syntax error: Unterminated quoted string" }, 2)
	says(state, admin, "for i in a; echo a; done",
		{ "Syntax error: word unexpected (expecting \"do\")" }, 2)
	put(state, "/home/admin/bad.sh", "echo one\nfi\n")
	says(state, admin, "sh bad.sh", { "bad.sh: 2: Syntax error: \"fi\" unexpected" })
	eq("a syntax error in a file", CeroSecOS.scriptError("x.sh", "Syntax error: Bad substitution", 4),
		"x.sh: 4: Syntax error: Bad substitution")
	eq("any other error in a file keeps its line", CeroSecOS.scriptError("x.sh", "divide by zero", 4),
		"x.sh: line 4: divide by zero")
end

--
-- 5. su and passwd: su.c's bare "Sorry"; passwd's EACCES under its own
-- name, for a wrong old password and for a token nobody wrote.
--
do
	local state = CeroSecOS.newState("ksp-front-01")
	local admin = CeroSecOS.login(state, "admin", "")
	local ok, lines = CeroSecOS.continue(state, admin, { cmd = "su", user = "root" }, "wrong")
	eq("a wrong su password fails", ok, false)
	eq("su says", lines[1], "Sorry")
	eq("and only that", #lines, 1)
	CeroSecOS.setPassword(state, "admin", "hunter2", nil, nil)
	ok, lines = CeroSecOS.continue(state, admin,
		{ cmd = "passwd", step = "old", user = "admin" }, "wrong")
	eq("a wrong old password fails", ok, false)
	eq("passwd says", lines[1], "passwd: Permission denied")
	ok, lines = CeroSecOS.continue(state, admin,
		{ cmd = "passwd", step = "nobody-wrote-this", user = "admin" }, "x")
	eq("a forged step fails", ok, false)
	eq("in the same words", lines[1], "passwd: Permission denied")
end

--
-- 6. What was fixed is no longer declared, and what is left still is.
--
do
	local named = {}
	for i = 1, #CeroSecOS.DEVIATIONS do named[CeroSecOS.DEVIATIONS[i].name] = true end
	for _, gone in ipairs({ "refusal", "getopt", "su" }) do
		check("no longer a deviation: " .. gone, not named[gone])
	end
	for _, kept in ipairs({ "syntax", "errno", "sh", "sudo" }) do
		check("still declared: " .. kept, named[kept])
	end
end

print("errors_test: " .. count .. " assertions passed")
