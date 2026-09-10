-- Unit tests for the CeroSecOS core. Run from the repo root:
--   lua5.1 tests/os_test.lua

local DIR = "42/media/lua/shared/CeroSec/OS/"
local FILES = {
	"CeroSecOS", "CeroSecOSFS", "CeroSecOSPath",
	"CeroSecOSShell", "CeroSecOSState", "CeroSecOSUsers",
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

local function fresh(hostname)
	return CeroSecOS.newState(hostname or "ksp-front-01")
end

local function open(state, name, password)
	local session, reason = CeroSecOS.login(state, name, password or "")
	if session == nil then error("cannot log in as " .. name .. ": " .. tostring(reason), 2) end
	return session
end

-- Runs a line and pins the whole result: the ok flag, the line count, every
-- line, the out-of-band control value, and the 60-column rule the screen
-- depends on. wantControl defaults to nil, so every single call in this file
-- also asserts that an ordinary command orders the terminal to do nothing.
local function expect(state, session, line, wantOk, wantLines, wantControl)
	local ok, lines, control = CeroSecOS.exec(state, session, line)
	eq("`" .. line .. "` ok", ok, wantOk)
	eq("`" .. line .. "` control", control, wantControl)
	local wide = false
	for i = 1, #lines do
		if #lines[i] > CeroSecOS.COLS then wide = true end
	end
	check("`" .. line .. "` every line fits 60 columns", not wide)
	-- wantLines nil means "the caller inspects the lines itself".
	if wantLines ~= nil then
		eq("`" .. line .. "` line count", #lines, #wantLines)
		for i = 1, #wantLines do
			eq("`" .. line .. "` line " .. i, lines[i], wantLines[i])
		end
	end
	return lines
end

local function ok(state, session, line, wantLines, wantControl)
	return expect(state, session, line, true, wantLines, wantControl)
end

local function bad(state, session, line, errorLine)
	return expect(state, session, line, false, { errorLine })
end

--
-- 1. Fresh state and the standard skeleton.
--

do
	local state = fresh()
	eq("schema version", state.v, 1)
	eq("hostname", state.hostname, "ksp-front-01")
	eq("sessions start empty", #state.sessions, 0)
	eq("fs root is a dir", state.fs.type, "dir")
	eq("fs root owner", state.fs.owner, "root")

	local names = CeroSecOS.childNames(state.fs)
	eq("root has 5 entries", #names, 5)
	eq("root entry 1", names[1], "bin")
	eq("root entry 2", names[2], "dev")
	eq("root entry 3", names[3], "etc")
	eq("root entry 4", names[4], "home")
	eq("root entry 5", names[5], "root")

	eq("/home/admin exists", state.fs.children.home.children.admin.type, "dir")
	eq("/home/admin owner", state.fs.children.home.children.admin.owner, "admin")
	eq("/home/admin mode", state.fs.children.home.children.admin.mode, 750)
	eq("/root mode", state.fs.children.root.mode, 700)
	eq("/dev is empty", CeroSecOS.countEntries(state.fs.children.dev), 0)
	eq("/etc/hostname data", state.fs.children.etc.children.hostname.data, "ksp-front-01")
	eq("/etc/motd data", state.fs.children.etc.children.motd.data, CeroSecOS.MOTD)
	eq("/etc/motd fits the screen", #CeroSecOS.MOTD <= 60, true)

	local nodes, bytes = CeroSecOS.usage(state)
	eq("skeleton node count", nodes, 9)
	eq("skeleton byte count", bytes, #"ksp-front-01" + #CeroSecOS.MOTD)

	eq("default hostname", CeroSecOS.newState().hostname, CeroSecOS.DEFAULT_HOSTNAME)
	eq("empty hostname falls back", CeroSecOS.newState("").hostname, CeroSecOS.DEFAULT_HOSTNAME)
	check("newState returns a fresh tree", CeroSecOS.newState().fs ~= CeroSecOS.newState().fs)

	eq("root user home", state.users.root.home, "/root")
	eq("root user is admin", state.users.root.admin, true)
	eq("admin user home", state.users.admin.home, "/home/admin")
	eq("admin user is not admin", state.users.admin.admin, false)
end

--
-- 2. Names and path resolution.
--

do
	eq("name: simple", CeroSecOS.isValidName("notes"), true)
	eq("name: dotted", CeroSecOS.isValidName("notes.txt"), true)
	eq("name: dashed inside", CeroSecOS.isValidName("a-b"), true)
	eq("name: 32 chars", CeroSecOS.isValidName(string.rep("a", 32)), true)
	eq("name: 33 chars", CeroSecOS.isValidName(string.rep("a", 33)), false)
	eq("name: empty", CeroSecOS.isValidName(""), false)
	eq("name: leading dash", CeroSecOS.isValidName("-r"), false)
	eq("name: space", CeroSecOS.isValidName("bad name"), false)
	eq("name: slash", CeroSecOS.isValidName("a/b"), false)
	eq("name: underscore", CeroSecOS.isValidName("a_b"), true)
	eq("name: plus is not in the set", CeroSecOS.isValidName("a+b"), false)
	eq("name: star is not in the set", CeroSecOS.isValidName("a*b"), false)
	eq("name: not a string", CeroSecOS.isValidName(nil), false)

	local s = { user = "admin", cwd = "/home/admin" }
	eq("resolve /", CeroSecOS.resolve(s, "/"), "/")
	eq("resolve empty is cwd", CeroSecOS.resolve(s, ""), "/home/admin")
	eq("resolve nil is cwd", CeroSecOS.resolve(s, nil), "/home/admin")
	eq("resolve .", CeroSecOS.resolve(s, "."), "/home/admin")
	eq("resolve ..", CeroSecOS.resolve(s, ".."), "/home")
	eq("resolve ../..", CeroSecOS.resolve(s, "../.."), "/")
	eq("resolve past the root", CeroSecOS.resolve(s, "../../../.."), "/")
	eq("resolve relative", CeroSecOS.resolve(s, "sub"), "/home/admin/sub")
	eq("resolve trailing slash", CeroSecOS.resolve(s, "sub/"), "/home/admin/sub")
	eq("resolve doubled slashes", CeroSecOS.resolve(s, "//etc//"), "/etc")
	eq("resolve mixed dots", CeroSecOS.resolve(s, "/a/./b/../c"), "/a/c")
	eq("resolve ./ prefix", CeroSecOS.resolve(s, "./sub/./x"), "/home/admin/sub/x")
	eq("resolve from /", CeroSecOS.resolve({ user = "root", cwd = "/" }, "x"), "/x")
	eq("resolve without a session", CeroSecOS.resolve(nil, "x"), "/x")

	local _, parts = CeroSecOS.resolve(s, "/a/b/c")
	eq("resolve returns components", #parts, 3)
	eq("component 1", parts[1], "a")
	eq("component 3", parts[3], "c")

	local parent, name = CeroSecOS.parentOf(parts)
	eq("parentOf path", parent, "/a/b")
	eq("parentOf name", name, "c")
	local _, topName = CeroSecOS.parentOf({ "a" })
	eq("parentOf of a top-level name", topName, "a")
	eq("parentOf of / is nil", CeroSecOS.parentOf({}), nil)

	eq("isInside self", CeroSecOS.isInside("/a", "/a"), true)
	eq("isInside child", CeroSecOS.isInside("/a/b", "/a"), true)
	eq("isInside sibling", CeroSecOS.isInside("/ab", "/a"), false)
	eq("isInside unrelated", CeroSecOS.isInside("/b", "/a"), false)
end

--
-- 3. Users, login, sessions.
--

do
	local state = fresh()
	local session, reason = CeroSecOS.login(state, "admin", "")
	eq("login reason is nil on success", reason, nil)
	eq("session user", session.user, "admin")
	eq("session cwd is the home", session.cwd, "/home/admin")

	local rootSession = CeroSecOS.login(state, "root", "")
	eq("root session cwd", rootSession.cwd, "/root")

	local none, why = CeroSecOS.login(state, "nobody", "")
	eq("unknown user gives no session", none, nil)
	eq("unknown user reason", why, "no such user")

	state.users.root.password = "hunter2"
	local denied, why2 = CeroSecOS.login(state, "root", "wrong")
	eq("bad password gives no session", denied, nil)
	eq("bad password reason", why2, "wrong password")
	check("good password logs in", CeroSecOS.login(state, "root", "hunter2") ~= nil)
	eq("checkPassword on nil user", CeroSecOS.checkPassword(nil, ""), false)
	eq("checkPassword nil means empty", CeroSecOS.checkPassword(state.users.admin, nil), true)

	-- The session is never written into the state.
	eq("login does not touch state.sessions", #state.sessions, 0)

	-- exec without a session refuses rather than assuming anything.
	local execOk, lines = CeroSecOS.exec(state, nil, "pwd")
	eq("exec without a session fails", execOk, false)
	eq("exec without a session says so", lines[1], "not logged in")
end

--
-- 4. Permission bits.
--

do
	local state = fresh()
	local admin = { user = "admin", cwd = "/home/admin" }
	local root = { user = "root", cwd = "/root" }
	local node = { type = "file", owner = "admin", mode = 640, data = "" }

	eq("owner r on 640", CeroSecOS.can(state, admin, node, "r"), true)
	eq("owner w on 640", CeroSecOS.can(state, admin, node, "w"), true)
	eq("owner x on 640", CeroSecOS.can(state, admin, node, "x"), false)
	local other = { user = "guest", cwd = "/" }
	eq("other r on 640", CeroSecOS.can(state, other, node, "r"), false)
	node.mode = 644
	eq("other r on 644", CeroSecOS.can(state, other, node, "r"), true)
	eq("other w on 644", CeroSecOS.can(state, other, node, "w"), false)
	node.mode = 755
	eq("other x on 755", CeroSecOS.can(state, other, node, "x"), true)
	node.mode = 700
	eq("root bypasses 700", CeroSecOS.can(state, root, node, "w"), true)
	eq("other on 700", CeroSecOS.can(state, other, node, "r"), false)
	-- The group digit is stored but never enforced.
	node.mode = 707
	eq("group digit is ignored, other wins", CeroSecOS.can(state, other, node, "w"), true)
	node.mode = 770
	eq("group digit alone grants nothing", CeroSecOS.can(state, other, node, "r"), false)
	eq("no session, no access", CeroSecOS.can(state, nil, node, "r"), false)
end

--
-- 5. Commands: happy paths.
--

do
	local state = fresh()
	local admin = open(state, "admin")

	ok(state, admin, "", {})
	ok(state, admin, "   ", {})
	ok(state, admin, "pwd", { "/home/admin" })
	ok(state, admin, "whoami", { "admin" })
	ok(state, admin, "hostname", { "ksp-front-01" })
	ok(state, admin, "clear", {}, "clear")
	ok(state, admin, "exit", {}, "exit")
	ok(state, admin, "echo hello world", { "hello world" })
	ok(state, admin, "echo", { "" })
	ok(state, admin, 'echo "a  b"', { "a  b" })
	ok(state, admin, 'echo "a \\"q\\" b"', { 'a "q" b' })
	ok(state, admin, 'echo "a\\nb"', { "a", "b" })
	ok(state, admin, "cat /etc/motd", { CeroSecOS.MOTD })
	ok(state, admin, "cat /etc/hostname", { "ksp-front-01" })

	local helpLines = ok(state, admin, "help", nil)
	check("help prints something", #helpLines >= 2)
	eq("help header", helpLines[1], "CeroSec OS commands:")

	ok(state, admin, "ls /", { "bin", "dev", "etc", "home", "root" })
	ok(state, admin, "ls", {})
	ok(state, admin, "mkdir sub", {})
	ok(state, admin, "ls", { "sub" })
	ok(state, admin, "cd sub", {})
	ok(state, admin, "pwd", { "/home/admin/sub" })
	ok(state, admin, "cd ..", {})
	ok(state, admin, "pwd", { "/home/admin" })
	ok(state, admin, "cd /etc/", {})
	ok(state, admin, "pwd", { "/etc" })
	ok(state, admin, "cd", {})
	eq("bare cd goes home", admin.cwd, "/home/admin")

	ok(state, admin, "touch notes.txt", {})
	ok(state, admin, "cat notes.txt", {})           -- an empty file prints nothing
	ok(state, admin, "touch notes.txt", {})         -- touching twice is fine
	ok(state, admin, 'write notes.txt "one\\ntwo"', {})
	ok(state, admin, "cat notes.txt", { "one", "two" })
	ok(state, admin, "cp notes.txt copy.txt", {})
	ok(state, admin, "cat copy.txt", { "one", "two" })
	ok(state, admin, "cp notes.txt sub", {})        -- into a directory
	ok(state, admin, "ls sub", { "notes.txt" })
	ok(state, admin, "mv copy.txt renamed.txt", {})
	ok(state, admin, "ls", { "notes.txt", "renamed.txt", "sub" })
	ok(state, admin, "mv renamed.txt sub", {})      -- into a directory
	ok(state, admin, "ls sub", { "notes.txt", "renamed.txt" })
	ok(state, admin, "rm sub/renamed.txt", {})
	ok(state, admin, "ls sub", { "notes.txt" })
	ok(state, admin, "rm -r sub", {})
	ok(state, admin, "ls", { "notes.txt" })
	ok(state, admin, "chmod 600 notes.txt", {})
	eq("chmod took", state.fs.children.home.children.admin.children["notes.txt"].mode, 600)
	ok(state, admin, "chmod 0640 notes.txt", {})
	eq("four-digit chmod took", state.fs.children.home.children.admin.children["notes.txt"].mode, 640)
	ok(state, admin, "cat notes.txt notes.txt", { "one", "two", "one", "two" })

	-- cat of several files in one go, and rm of several paths.
	bad(state, admin, "touch a.txt b.txt", "touch: usage: touch <file>")
	ok(state, admin, "touch a.txt", {})
	ok(state, admin, "touch b.txt", {})
	ok(state, admin, "rm a.txt b.txt", {})
	ok(state, admin, "ls", { "notes.txt" })

	-- root can go where admin cannot.
	local rootSession = open(state, "root")
	ok(state, rootSession, "cd /root", {})
	ok(state, rootSession, "pwd", { "/root" })
	ok(state, rootSession, 'write /root/secret.txt "classified"', {})
	ok(state, rootSession, "cat /root/secret.txt", { "classified" })
	ok(state, rootSession, "chown admin /root/secret.txt", {})
	eq("chown took", state.fs.children.root.children["secret.txt"].owner, "admin")
end

--
-- 6. Commands: the exact error lines.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local rootSession = open(state, "root")
	ok(state, rootSession, 'write /root/secret.txt "classified"', {})

	bad(state, admin, "frobnicate", "frobnicate: command not found")
	bad(state, admin, "cat notes.txt", "cat: notes.txt: no such file")
	bad(state, admin, "cat /etc", "cat: /etc: is a directory")
	bad(state, admin, "cat", "cat: usage: cat <file>")
	bad(state, admin, "cd /root", "cd: /root: permission denied")
	bad(state, admin, "cd /nope", "cd: /nope: no such file")
	bad(state, admin, "cd /etc/motd", "cd: /etc/motd: not a directory")
	bad(state, admin, "cd a b", "cd: usage: cd [dir]")
	bad(state, admin, "cat /root/secret.txt", "cat: /root/secret.txt: permission denied")
	bad(state, admin, "ls /root/x", "ls: /root/x: permission denied")
	bad(state, admin, "ls /nope", "ls: /nope: no such file")
	bad(state, admin, "ls -z", "ls: -z: unknown option")
	bad(state, admin, "ls a b", "ls: usage: ls [-l] [path]")
	bad(state, admin, "mkdir", "mkdir: usage: mkdir <dir>")
	bad(state, admin, "mkdir a b", "mkdir: usage: mkdir <dir>")
	bad(state, admin, "mkdir /etc/x", "mkdir: /etc/x: permission denied")
	bad(state, admin, "mkdir /nope/x", "mkdir: /nope/x: no such file")
	bad(state, admin, 'mkdir "/home/admin/bad name"', "mkdir: /home/admin/bad name: invalid name")
	bad(state, admin, "touch /etc/x", "touch: /etc/x: permission denied")
	bad(state, admin, "touch /etc", "touch: /etc: is a directory")
	bad(state, admin, "touch", "touch: usage: touch <file>")
	bad(state, admin, "rm", "rm: usage: rm [-r] <path>")
	bad(state, admin, "rm /", "rm: /: permission denied")
	bad(state, admin, "rm /etc/motd", "rm: /etc/motd: permission denied")
	bad(state, admin, "rm /nope", "rm: /nope: no such file")
	bad(state, admin, "rm -z x", "rm: -z: unknown option")
	bad(state, admin, "mv", "mv: usage: mv <src> <dst>")
	bad(state, admin, "mv a", "mv: usage: mv <src> <dst>")
	bad(state, admin, "mv /nope /home/admin/x", "mv: /nope: no such file")
	bad(state, admin, "cp", "cp: usage: cp <src> <dst>")
	bad(state, admin, "cp /etc /home/admin/x", "cp: /etc: is a directory")
	bad(state, admin, "cp /nope /home/admin/x", "cp: /nope: no such file")
	bad(state, admin, "chmod", "chmod: usage: chmod <mode> <path>")
	bad(state, admin, "chmod 999 /etc/motd", "chmod: 999: invalid mode")
	bad(state, admin, "chmod 75 /etc/motd", "chmod: 75: invalid mode")
	bad(state, admin, "chmod rwx /etc/motd", "chmod: rwx: invalid mode")
	bad(state, admin, "chmod 755 /etc/motd", "chmod: /etc/motd: permission denied")
	bad(state, admin, "chown", "chown: usage: chown <user> <path>")
	bad(state, admin, "chown nobody /etc/motd", "chown: nobody: no such user")
	bad(state, admin, "chown admin /etc/motd", "chown: /etc/motd: permission denied")
	bad(state, admin, "write /etc/x", "write: usage: write <file> <text>")
	bad(state, admin, 'write /etc/x "hi"', "write: /etc/x: permission denied")
	bad(state, admin, "pwd x", "pwd: usage: pwd")
	bad(state, admin, "whoami x", "whoami: usage: whoami")
	bad(state, admin, "hostname x", "hostname: usage: hostname")

	-- Syntax.
	bad(state, admin, 'echo "abc', "syntax error: unterminated quote")
	bad(state, admin, 'echo "abc\\', "syntax error: unterminated quote")
	bad(state, admin, "echo >", "syntax error: missing redirect target")
	bad(state, admin, "echo a > b > c", "syntax error: bad redirect")

	-- Existing target, and a directory into itself.
	ok(state, admin, "mkdir /home/admin/d1", {})
	bad(state, admin, "mkdir /home/admin/d1", "mkdir: /home/admin/d1: file exists")
	ok(state, admin, "touch /home/admin/f1", {})
	bad(state, admin, "cp /home/admin/f1 /home/admin/f1", "cp: /home/admin/f1: file exists")
	bad(state, admin, "mv /home/admin/d1 /home/admin/d1/inner",
		"mv: /home/admin/d1/inner: invalid destination")
	bad(state, admin, "rm /home/admin/d1", "rm: /home/admin/d1: is a directory")

	-- Several failures in one command line, in order.
	expect(state, admin, "cat /nope1 /nope2", false, {
		"cat: /nope1: no such file",
		"cat: /nope2: no such file",
	})
end

--
-- 7. Permissions enforced by the shell.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local rootSession = open(state, "root")

	-- x is what lets you traverse: drop it and even a listing fails.
	ok(state, admin, "mkdir /home/admin/box", {})
	ok(state, admin, "touch /home/admin/box/thing", {})
	ok(state, admin, "chmod 600 /home/admin/box", {})
	bad(state, admin, "cd /home/admin/box", "cd: /home/admin/box: permission denied")
	bad(state, admin, "cat /home/admin/box/thing", "cat: /home/admin/box/thing: permission denied")
	ok(state, rootSession, "cat /home/admin/box/thing", {})

	-- r is what lets you list.
	ok(state, admin, "chmod 100 /home/admin/box", {})
	bad(state, admin, "ls /home/admin/box", "ls: /home/admin/box: permission denied")
	ok(state, admin, "cat /home/admin/box/thing", {})   -- x alone still traverses

	-- w is what lets you create and delete inside.
	ok(state, admin, "chmod 500 /home/admin/box", {})
	bad(state, admin, "touch /home/admin/box/other", "touch: /home/admin/box/other: permission denied")
	bad(state, admin, "rm /home/admin/box/thing", "rm: /home/admin/box/thing: permission denied")
	ok(state, admin, "chmod 700 /home/admin/box", {})
	ok(state, admin, "rm /home/admin/box/thing", {})

	-- Owner may chmod, a stranger may not; root always may.
	ok(state, rootSession, 'write /root/note.txt "x"', {})
	ok(state, rootSession, "chmod 701 /root", {})        -- open the door, not the file
	bad(state, admin, "chmod 777 /root/note.txt", "chmod: /root/note.txt: permission denied")
	ok(state, rootSession, "chown admin /root/note.txt", {})
	ok(state, admin, "chmod 777 /root/note.txt", {})     -- now admin owns it
	eq("owner chmod took", state.fs.children.root.children["note.txt"].mode, 777)
	ok(state, admin, "chown root /root/note.txt", {})    -- owner may give it away
	bad(state, admin, "chown admin /root/note.txt", "chown: /root/note.txt: permission denied")

	-- rm -r refuses a subtree the user cannot fully enter.
	ok(state, rootSession, "mkdir /home/admin/sealed", {})
	ok(state, rootSession, "mkdir /home/admin/sealed/inner", {})
	ok(state, rootSession, "chmod 700 /home/admin/sealed/inner", {})
	bad(state, admin, "rm -r /home/admin/sealed", "rm: /home/admin/sealed: permission denied")
	ok(state, rootSession, "rm -r /home/admin/sealed", {})
end

--
-- 8. Redirection.
--

do
	local state = fresh()
	local admin = open(state, "admin")

	ok(state, admin, "echo hello > notes.txt", {})
	ok(state, admin, "cat notes.txt", { "hello" })
	ok(state, admin, "echo again >> notes.txt", {})
	ok(state, admin, "cat notes.txt", { "hello", "again" })
	ok(state, admin, "echo fresh > notes.txt", {})
	ok(state, admin, "cat notes.txt", { "fresh" })
	ok(state, admin, "ls / > listing.txt", {})
	ok(state, admin, "cat listing.txt", { "bin", "dev", "etc", "home", "root" })
	ok(state, admin, "echo x>tight.txt", {})            -- no spaces around >
	ok(state, admin, "cat tight.txt", { "x" })
	ok(state, admin, "> empty.txt", {})                 -- bare redirect creates the file
	ok(state, admin, "cat empty.txt", {})
	eq("bare redirect made a file", state.fs.children.home.children.admin.children["empty.txt"].type, "file")
	ok(state, admin, 'echo ">" > arrow.txt', {})        -- a quoted > is data
	ok(state, admin, "cat arrow.txt", { ">" })

	-- A failing command writes nothing: errors behave like stderr.
	bad(state, admin, "cat /nope > out.txt", "cat: /nope: no such file")
	bad(state, admin, "cat out.txt", "cat: out.txt: no such file")

	-- A redirect the user may not perform reports against the target.
	bad(state, admin, "echo hi > /etc/x", "echo: /etc/x: permission denied")
	bad(state, admin, "echo hi > /etc", "echo: /etc: is a directory")
end

--
-- 9. Limits.
--

do
	local state = fresh()
	local admin = open(state, "admin")

	-- 4096 bytes is the ceiling for one file.
	ok(state, admin, 'write big.txt "' .. string.rep("x", 4096) .. '"', {})
	eq("4096-byte file stored", #state.fs.children.home.children.admin.children["big.txt"].data, 4096)
	bad(state, admin, 'write big.txt "' .. string.rep("x", 4097) .. '"', "write: big.txt: file too large")
	eq("refused write left the file alone",
		#state.fs.children.home.children.admin.children["big.txt"].data, 4096)
	bad(state, admin, 'write huge.txt "' .. string.rep("x", 4097) .. '"', "write: huge.txt: file too large")
	eq("refused create made nothing", state.fs.children.home.children.admin.children["huge.txt"], nil)
	ok(state, admin, "rm big.txt", {})

	-- 64 entries per directory.
	for i = 1, 64 do
		local execOk = CeroSecOS.exec(state, admin, "touch f" .. i)
		if not execOk then error("touch f" .. i .. " failed") end
	end
	eq("directory holds 64", CeroSecOS.countEntries(state.fs.children.home.children.admin), 64)
	bad(state, admin, "touch f65", "touch: f65: directory full")
	bad(state, admin, "mkdir d65", "mkdir: d65: directory full")
	-- A rename inside a full directory still works: nothing is being added.
	ok(state, admin, "mv f1 g1", {})
	eq("still 64 after a rename", CeroSecOS.countEntries(state.fs.children.home.children.admin), 64)
	bad(state, admin, "cp g1 f1", "cp: f1: directory full")
end

do
	-- Depth: 16 components below / are fine, the 17th is not.
	local state = fresh()
	local rootSession = open(state, "root")
	-- Short names on purpose: the error line must still fit the screen.
	local letters = { "a", "b", "c", "d", "e", "f", "g", "h",
		"i", "j", "k", "l", "m", "n", "o", "p" }
	local path = ""
	for i = 1, 16 do
		path = path .. "/" .. letters[i]
		local execOk, lines = CeroSecOS.exec(state, rootSession, "mkdir " .. path)
		if not execOk then error("mkdir " .. path .. " failed: " .. tostring(lines[1])) end
	end
	eq("16 levels are allowed", CeroSecOS.validate(state), true)
	bad(state, rootSession, "mkdir " .. path .. "/q", "mkdir: " .. path .. "/q: path too deep")
	bad(state, rootSession, "touch " .. path .. "/q", "touch: " .. path .. "/q: path too deep")
	-- Moving a subtree into itself is refused before anything else.
	bad(state, rootSession, "mv /a /a/b/c", "mv: /a/b/c/a: invalid destination")
	-- And moving a deep subtree one level deeper busts the depth limit.
	ok(state, rootSession, "mkdir /z", {})
	bad(state, rootSession, "mv /a /z", "mv: /z/a: path too deep")
end

do
	-- 32768 bytes on the whole computer.
	local state = fresh()
	local rootSession = open(state, "root")
	local _, used = CeroSecOS.usage(state)
	local block = string.rep("y", 4096)
	for i = 1, 7 do
		local execOk = CeroSecOS.exec(state, rootSession, 'write /b' .. i .. ' "' .. block .. '"')
		if not execOk then error("write /b" .. i .. " failed") end
	end
	local _, now = CeroSecOS.usage(state)
	eq("seven blocks written", now, used + 7 * 4096)
	local room = 32768 - now
	ok(state, rootSession, 'write /last "' .. string.rep("z", room) .. '"', {})
	local _, full = CeroSecOS.usage(state)
	eq("disk exactly full", full, 32768)
	ok(state, rootSession, "touch /nothing", {})            -- an empty file costs no bytes
	bad(state, rootSession, 'write /nothing "x"', "write: /nothing: disk full")
	bad(state, rootSession, 'write /brand "x"', "write: /brand: disk full")
	bad(state, rootSession, "cp /b1 /copy", "cp: /copy: disk full")
end

do
	-- 256 nodes on the whole computer.
	local state = fresh()
	local rootSession = open(state, "root")
	local nodes = CeroSecOS.usage(state)
	eq("starting node count", nodes, 9)
	local made = 0
	local dir = 0
	while true do
		dir = dir + 1
		if not CeroSecOS.exec(state, rootSession, "mkdir /p" .. dir) then break end
		made = made + 1
		local full = false
		for i = 1, 64 do
			if 9 + made >= 256 then full = true break end
			if not CeroSecOS.exec(state, rootSession, "touch /p" .. dir .. "/f" .. i) then break end
			made = made + 1
		end
		if full then break end
	end
	local total = CeroSecOS.usage(state)
	eq("node ceiling reached", total, 256)
	-- The last directory still has room for an entry; the computer does not.
	local last = "/p" .. dir .. "/last"
	check("the last directory is not full itself",
		CeroSecOS.countEntries(state.fs.children["p" .. dir]) < 64)
	bad(state, rootSession, "touch " .. last, "touch: " .. last .. ": disk full")
	bad(state, rootSession, "mkdir /lastdir", "mkdir: /lastdir: disk full")
	eq("state at the ceiling is still valid", CeroSecOS.validate(state), true)
end

--
-- 10. ls -l: exact columns, and the 60-character rule.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local rootSession = open(state, "root")

	-- 10 perm + 2 + 8 owner + 2 + 31 name + 2 + 5 size = 60.
	local lines = ok(state, admin, "ls -l /", nil)
	eq("ls -l lists 5 entries", #lines, 5)
	eq("ls -l bin",
		lines[1],
		"drwxr-xr-x" .. "  " .. "root    " .. "  " .. "bin" .. string.rep(" ", 28) .. "  " .. "    0")
	eq("ls -l root dir",
		lines[5],
		"drwx------" .. "  " .. "root    " .. "  " .. "root" .. string.rep(" ", 27) .. "  " .. "    0")
	for i = 1, #lines do
		eq("ls -l line " .. i .. " is exactly 60 columns", #lines[i], 60)
	end

	local etc = ok(state, admin, "ls -l /etc", nil)
	eq("ls -l motd",
		etc[2],
		"-rw-r--r--" .. "  " .. "root    " .. "  " .. "motd" .. string.rep(" ", 27) .. "  "
			.. "   52")
	eq("ls -l /etc has 2 lines", #etc, 2)

	-- Every permission digit renders.
	ok(state, admin, "touch /home/admin/perm", {})
	ok(state, admin, "chmod 777 /home/admin/perm", {})
	eq("777 renders", string.sub(ok(state, admin, "ls -l /home/admin/perm", nil)[1], 1, 10), "-rwxrwxrwx")
	ok(state, admin, "chmod 000 /home/admin/perm", {})
	eq("000 renders", string.sub(ok(state, admin, "ls -l /home/admin/perm", nil)[1], 1, 10), "----------")
	ok(state, admin, "chmod 421 /home/admin/perm", {})
	eq("421 renders", string.sub(ok(state, admin, "ls -l /home/admin/perm", nil)[1], 1, 10), "-r---w---x")
	ok(state, admin, "chmod 644 /home/admin/perm", {})

	-- A name at the 32-character limit is cut to 31 with a "~".
	local longName = string.rep("n", 32)
	ok(state, admin, "touch /home/admin/" .. longName, {})
	local home = ok(state, admin, "ls -l /home/admin", nil)
	local cut = nil
	for i = 1, #home do
		if string.find(home[i], "nnn", 1, true) ~= nil then cut = home[i] end
	end
	check("the long name is listed", cut ~= nil)
	eq("the long-name line is still 60 columns", #cut, 60)
	eq("the long name is cut with a tilde", string.sub(cut, 23, 53), string.rep("n", 30) .. "~")

	-- A long owner is cut the same way.
	state.users.administrator = CeroSecOS.newUser("administrator", "", "/home/admin", false)
	ok(state, rootSession, "chown administrator /home/admin/perm", {})
	local owned = ok(state, rootSession, "ls -l /home/admin/perm", nil)
	eq("the long owner is cut with a tilde", string.sub(owned[1], 13, 20), "adminis~")
	eq("the long-owner line is still 60 columns", #owned[1], 60)

	-- Plain ls of a single file prints its name.
	ok(state, admin, "ls /etc/motd", { "motd" })

	-- Nothing the core prints is ever wider than the screen: a long echo wraps.
	local wrapped = ok(state, admin, "echo " .. string.rep("w", 130), nil)
	eq("a 130-character line wraps into 3", #wrapped, 3)
	eq("wrap piece 1", #wrapped[1], 60)
	eq("wrap piece 2", #wrapped[2], 60)
	eq("wrap piece 3", #wrapped[3], 10)
	eq("wrap keeps the text", wrapped[1] .. wrapped[2] .. wrapped[3], string.rep("w", 130))

	-- And a long stored line wraps on cat too.
	ok(state, rootSession, 'write /home/admin/wide.txt "' .. string.rep("q", 61) .. '"', {})
	local catted = ok(state, admin, "cat /home/admin/wide.txt", nil)
	eq("cat wraps at 60", #catted, 2)
	eq("cat wrap piece 1", #catted[1], 60)
	eq("cat wrap piece 2", #catted[2], 1)
end

--
-- 11. validate and migrate.
--

do
	local state = fresh()
	eq("a fresh state validates", CeroSecOS.validate(state), true)

	local nilOk, nilReason = CeroSecOS.validate(nil)
	eq("nil does not validate", nilOk, false)
	eq("nil reason", nilReason, "state is not a table")

	local wrongVersion = fresh()
	wrongVersion.v = 2
	eq("a v2 state is refused", CeroSecOS.validate(wrongVersion), false)

	local noRoot = fresh()
	noRoot.users.root = nil
	local nrOk, nrReason = CeroSecOS.validate(noRoot)
	eq("a state without root is refused", nrOk, false)
	eq("no-root reason", nrReason, "no root user")

	local badHost = fresh()
	badHost.hostname = "not a hostname"
	eq("a bad hostname is refused", CeroSecOS.validate(badHost), false)

	local withFunction = fresh()
	withFunction.fs.children.etc.children.motd.data = print
	local fnOk, fnReason = CeroSecOS.validate(withFunction)
	eq("a function in the state is refused", fnOk, false)
	check("the reason names the function", string.find(fnReason, "function", 1, true) ~= nil)

	local withCycle = fresh()
	withCycle.fs.children.home.children.loop = withCycle.fs
	local cyOk, cyReason = CeroSecOS.validate(withCycle)
	eq("a cycle is refused", cyOk, false)
	check("the reason names the cycle", string.find(cyReason, "cycle", 1, true) ~= nil)

	local oversize = fresh()
	oversize.fs.children.etc.children.motd.data = string.rep("x", 4097)
	local ovOk, ovReason = CeroSecOS.validate(oversize)
	eq("an oversize file is refused", ovOk, false)
	check("the reason names the size", string.find(ovReason, "file too large", 1, true) ~= nil)

	local overTotal = fresh()
	for i = 1, 9 do
		overTotal.fs.children[ "big" .. i ] = CeroSecOS.newFile("root", 644, string.rep("x", 4096))
	end
	eq("an oversize disk is refused", CeroSecOS.validate(overTotal), false)

	local badNode = fresh()
	badNode.fs.children.etc.children.motd.type = "socket"
	eq("an unknown node type is refused", CeroSecOS.validate(badNode), false)

	local badMode = fresh()
	badMode.fs.children.etc.mode = 999
	eq("an out-of-range mode is refused", CeroSecOS.validate(badMode), false)

	local badChildName = fresh()
	badChildName.fs.children["bad name"] = CeroSecOS.newDir("root", 755)
	eq("an invalid child name is refused", CeroSecOS.validate(badChildName), false)

	local badUser = fresh()
	badUser.users.admin.admin = "yes"
	eq("a non-boolean admin flag is refused", CeroSecOS.validate(badUser), false)

	local mismatched = fresh()
	mismatched.users.admin.name = "someone"
	eq("a user keyed under the wrong name is refused", CeroSecOS.validate(mismatched), false)

	-- migrate.
	local migrated = CeroSecOS.migrate(nil)
	eq("migrate(nil) gives a v1 state", migrated.v, 1)
	eq("migrate(nil) validates", CeroSecOS.validate(migrated), true)
	eq("migrate(nil) uses the default hostname", migrated.hostname, CeroSecOS.DEFAULT_HOSTNAME)
	eq("migrate takes a hostname", CeroSecOS.migrate(nil, "ksp-back-02").hostname, "ksp-back-02")
	eq("migrate of junk gives a v1 state", CeroSecOS.migrate("garbage").v, 1)
	eq("migrate of an empty table gives a v1 state", CeroSecOS.migrate({}).v, 1)

	local live = fresh()
	check("migrate passes a valid v1 state through", CeroSecOS.migrate(live) == live)
	local broken = fresh()
	broken.users.root = nil
	check("migrate replaces a broken v1 state", CeroSecOS.migrate(broken) ~= broken)
	eq("the replacement validates", CeroSecOS.validate(CeroSecOS.migrate(broken)), true)
end

--
-- 12. Control travels out of band, and no file can ever look like an order.
--
-- The sentinels this core used to put inside the output array ("\1CLEAR",
-- "\1EXIT") were forgeable: writing those very bytes into a file and running
-- cat produced a line byte-identical to a genuine exit. Control is now exec's
-- third return value, and control bytes never reach a file in the first place.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local rootSession = open(state, "root")

	-- No sentinel is left anywhere to compare against.
	eq("no CLEAR sentinel", CeroSecOS.CLEAR, nil)
	eq("no EXIT sentinel", CeroSecOS.EXIT, nil)

	-- The two commands that steer the terminal say so beside the output.
	local lines, control
	local execOk
	execOk, lines, control = CeroSecOS.exec(state, admin, "clear")
	eq("clear succeeds", execOk, true)
	eq("clear prints nothing", #lines, 0)
	eq("clear controls the terminal", control, "clear")
	execOk, lines, control = CeroSecOS.exec(state, admin, "exit")
	eq("exit succeeds", execOk, true)
	eq("exit prints nothing", #lines, 0)
	eq("exit controls the terminal", control, "exit")

	-- Everything else orders nothing.
	execOk, lines, control = CeroSecOS.exec(state, admin, "pwd")
	eq("pwd controls nothing", control, nil)
	execOk, lines, control = CeroSecOS.exec(state, admin, "nosuchcommand")
	eq("an unknown command controls nothing", control, nil)
	execOk, lines, control = CeroSecOS.exec(state, admin, "")
	eq("an empty line controls nothing", control, nil)

	-- hasControlBytes: the rule itself.
	eq("plain text is clean", CeroSecOS.hasControlBytes("hello"), false)
	eq("newline is allowed", CeroSecOS.hasControlBytes("a\nb"), false)
	eq("tab is allowed", CeroSecOS.hasControlBytes("a\tb"), false)
	eq("empty is clean", CeroSecOS.hasControlBytes(""), false)
	eq("SOH is refused", CeroSecOS.hasControlBytes(string.char(1)), true)
	eq("NUL is refused", CeroSecOS.hasControlBytes(string.char(0)), true)
	eq("ESC is refused", CeroSecOS.hasControlBytes(string.char(27)), true)
	eq("CR is refused", CeroSecOS.hasControlBytes("a\rb"), true)
	eq("byte 31 is refused", CeroSecOS.hasControlBytes(string.char(31)), true)
	eq("byte 32 is fine", CeroSecOS.hasControlBytes(string.char(32)), false)
	eq("a control byte buried in text is found",
		CeroSecOS.hasControlBytes("harmless" .. string.char(1) .. "text"), true)

	-- The old attack, replayed: writeFile refuses the bytes outright.
	local forged = "\1EXIT"
	local wrote, wreason = CeroSecOS.writeFile(state, rootSession, "/evil.txt", forged)
	eq("writeFile refuses control bytes", wrote, nil)
	eq("writeFile reason", wreason, "invalid characters")
	eq("nothing was created", state.fs.children["evil.txt"], nil)

	-- setData, the other mutator, refuses them too.
	local set, sreason = CeroSecOS.setData(state, rootSession, "/etc/motd", "\1CLEAR")
	eq("setData refuses control bytes", set, nil)
	eq("setData reason", sreason, "invalid characters")
	eq("the file was left alone", state.fs.children.etc.children.motd.data, CeroSecOS.MOTD)

	-- createNode refuses a file carrying them, and a whole subtree carrying
	-- them: a network rung will hand over trees, not just single files.
	local bad1, breason = CeroSecOS.createNode(state, rootSession, "/planted.txt",
		CeroSecOS.newFile("root", 644, string.char(27) .. "[2J"))
	eq("createNode refuses a dirty file", bad1, nil)
	eq("createNode reason", breason, "invalid characters")
	local tree = CeroSecOS.newDir("root", 755)
	tree.children.inner = CeroSecOS.newDir("root", 755)
	tree.children.inner.children["x.txt"] = CeroSecOS.newFile("root", 644, string.char(7))
	local bad2, treason = CeroSecOS.createNode(state, rootSession, "/dropped", tree)
	eq("createNode refuses a dirty subtree", bad2, nil)
	eq("subtree reason", treason, "invalid characters")
	eq("nothing was planted", state.fs.children.dropped, nil)
	eq("subtreeHasControlBytes agrees", CeroSecOS.subtreeHasControlBytes(tree), true)
	eq("a clean subtree passes", CeroSecOS.subtreeHasControlBytes(state.fs), false)

	-- Through the shell, the refusal reads like every other error.
	bad(state, admin, 'write dirty.txt "' .. string.char(1) .. '"',
		"write: dirty.txt: invalid characters")
	bad(state, admin, 'echo "' .. string.char(1) .. '" > dirty.txt',
		"echo: dirty.txt: invalid characters")
	eq("no dirty file exists",
		state.fs.children.home.children.admin.children["dirty.txt"], nil)

	-- The escape table cannot manufacture one: \1 is a backslash escape that
	-- yields the character "1", not the byte 1.
	ok(state, admin, 'echo "\\1"', { "1" })
	ok(state, admin, 'echo "\\1" > tame.txt', {})
	ok(state, admin, "cat tame.txt", { "1" })
	eq("the file holds the digit, not the byte",
		state.fs.children.home.children.admin.children["tame.txt"].data, "1")

	-- Newline and tab still go in and come back out.
	ok(state, admin, 'write good.txt "a\\nb\\tc"', {})
	ok(state, admin, "cat good.txt", { "a", "b\tc" })

	-- So cat can never produce a control, whatever a file holds.
	local names = CeroSecOS.childNames(state.fs.children.home.children.admin)
	for i = 1, #names do
		local _, catLines, catControl = CeroSecOS.exec(state, admin, "cat " .. names[i])
		eq("cat " .. names[i] .. " controls nothing", catControl, nil)
		for j = 1, #catLines do
			check("cat " .. names[i] .. " line " .. j .. " is printable",
				not CeroSecOS.hasControlBytes(catLines[j]))
		end
	end

	-- And a forged modData blob is refused before it can be run.
	local smuggled = fresh()
	smuggled.fs.children.etc.children.motd.data = "\1EXIT"
	local vOk, vReason = CeroSecOS.validate(smuggled)
	eq("validate rejects smuggled control bytes", vOk, false)
	eq("validate reason", vReason, "/etc/motd: invalid characters")
	local smuggledDeep = fresh()
	smuggledDeep.fs.children.home.children.admin.children["n.txt"] =
		CeroSecOS.newFile("admin", 644, "ok" .. string.char(0))
	eq("validate rejects them deep in the tree", CeroSecOS.validate(smuggledDeep), false)
	local clean = fresh()
	clean.fs.children.etc.children.motd.data = "a\nb\tc"
	eq("validate still accepts newline and tab", CeroSecOS.validate(clean), true)
end

--
-- 13. Determinism: the same input twice gives the same output, byte for byte.
--

do
	local script = {
		"mkdir work", "cd work", "touch zeta", "touch alpha", "touch mid",
		"echo one > alpha", "echo two >> alpha", "ls", "ls -l", "cat alpha",
		"mkdir deep", "mv zeta deep", "ls -l deep", "cd ..", "ls -l work",
		"cat /etc/motd", "pwd", "whoami", "hostname", "rm -r work", "ls",
	}
	local runs = {}
	for pass = 1, 2 do
		local state = fresh()
		local session = open(state, "admin")
		local out = {}
		for i = 1, #script do
			local execOk, lines, control = CeroSecOS.exec(state, session, script[i])
			out[#out + 1] = tostring(execOk) .. "/" .. tostring(control)
			for j = 1, #lines do out[#out + 1] = lines[j] end
		end
		runs[pass] = out
	end
	eq("both passes produced the same number of lines", #runs[1], #runs[2])
	local same = true
	for i = 1, #runs[1] do
		if runs[1][i] ~= runs[2][i] then same = false end
	end
	check("both passes produced identical output", same)
	check("the script actually produced output", #runs[1] > 30)
end

--
-- 14. The state stays plain after a working session.
--

do
	local state = fresh()
	local session = open(state, "admin")
	local script = {
		"mkdir a", "mkdir a/b", "touch a/b/c.txt", 'write a/b/c.txt "hello"',
		"cp a/b/c.txt a/d.txt", "mv a/d.txt a/e.txt", "chmod 600 a/e.txt",
		"echo log > a/log.txt", "echo more >> a/log.txt", "rm a/b/c.txt",
	}
	for i = 1, #script do
		local execOk, lines = CeroSecOS.exec(state, session, script[i])
		if not execOk then error(script[i] .. ": " .. tostring(lines[1])) end
	end
	local vOk, vReason = CeroSecOS.validate(state)
	eq("the state still validates", vOk, true)
	eq("no complaint", vReason, nil)
	eq("sessions are still not persisted", #state.sessions, 0)
	eq("the session is a runtime object", session.cwd, "/home/admin")
end

print("os_test: " .. count .. " assertions passed")
