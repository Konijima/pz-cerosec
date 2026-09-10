-- Unit tests for the CeroSecOS core. Run from the repo root:
--   lua5.1 tests/os_test.lua

local DIR = "42/media/lua/shared/CeroSec/OS/"
local FILES = {
	"CeroSecOS", "CeroSecOSDev", "CeroSecOSFS", "CeroSecOSPath", "CeroSecOSShell",
	"CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers",
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

-- What is stored is a hash, so a password is checked by trying it and never by
-- reading the field.
local function holds(state, name, password)
	return CeroSecOS.checkPassword(CeroSecOS.getUser(state, name), password)
end

-- The accounts are a file now, so a test that wants another one writes a line
-- into it -- through setData, the way root would with the editor.
local function addUser(state, name, password, home, admin)
	local user = CeroSecOS.newUser(name, password or "", home or ("/home/" .. name), admin)
	local node = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	local text = node.data
	if text ~= "" then text = text .. "\n" end
	local done, reason = CeroSecOS.setData(state, CeroSecOS.rootSession(),
		CeroSecOS.PASSWD_PATH, text .. CeroSecOS.passwdLine(user))
	if done == nil then error("cannot add " .. name .. ": " .. tostring(reason), 2) end
	return user
end

-- The stored field of one account, replaced where it lies and NOT through
-- setData: what goes in is often something no write would take, which is the
-- point -- it is how a forged file or an older save is put on the disk.
local function setStored(state, name, stored)
	local node = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	local lines = CeroSecOS.splitLines(node.data)
	for i = 1, #lines do
		if string.sub(lines[i], 1, #name + 1) == name .. ":" then
			local _, _, home, kind = string.match(lines[i], "^([^:]*):([^:]*):([^:]*):([^:]*)$")
			lines[i] = name .. ":" .. stored .. ":" .. home .. ":" .. kind
		end
	end
	node.data = table.concat(lines, "\n")
end

-- What the account's line holds, read back out of the file.
local function stored(state, name)
	local user = CeroSecOS.getUser(state, name)
	if user == nil then return nil end
	return user.password
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

	-- The skeleton is nine nodes plus one executable per command plus
	-- /etc/passwd and /etc/sudoers, and every byte of it is accounted for: the
	-- machine's name, the motd, the accounts file, the sudoers file, and the
	-- one-line description in each executable.
	local binNames = CeroSecOS.binNames()
	local binBytes = 0
	for i = 1, #binNames do binBytes = binBytes + #CeroSecOS.commandDesc(binNames[i]) end
	local passwd = state.fs.children.etc.children.passwd
	local sudoers = state.fs.children.etc.children.sudoers
	local nodes, bytes = CeroSecOS.usage(state)
	eq("skeleton node count", nodes, 9 + #binNames + 2)
	eq("skeleton byte count", bytes,
		#"ksp-front-01" + #CeroSecOS.MOTD + #passwd.data + #sudoers.data + binBytes)

	eq("default hostname", CeroSecOS.newState().hostname, CeroSecOS.DEFAULT_HOSTNAME)
	eq("empty hostname falls back", CeroSecOS.newState("").hostname, CeroSecOS.DEFAULT_HOSTNAME)
	eq("a hostname that is not one falls back",
		CeroSecOS.newState("Not A Host").hostname, CeroSecOS.DEFAULT_HOSTNAME)
	check("newState returns a fresh tree", CeroSecOS.newState().fs ~= CeroSecOS.newState().fs)

	-- The accounts are a file and nothing else: no table of users beside it.
	eq("no users table on the state", state.users, nil)
	eq("/etc/passwd owner", passwd.owner, "root")
	eq("/etc/passwd mode", passwd.mode, 600)
	eq("/etc/sudoers owner", sudoers.owner, "root")
	eq("/etc/sudoers mode", sudoers.mode, 440)
	eq("admin ships in the sudoers file", CeroSecOS.sudoer(state, "admin").name, "admin")
	eq("and is asked for his password", CeroSecOS.sudoer(state, "admin").nopasswd, false)
	eq("nobody else ships in it", CeroSecOS.sudoer(state, "root"), nil)
	eq("root user home", CeroSecOS.getUser(state, "root").home, "/root")
	eq("root user is admin", CeroSecOS.getUser(state, "root").admin, true)
	eq("admin user home", CeroSecOS.getUser(state, "admin").home, "/home/admin")
	eq("admin user is not admin", CeroSecOS.getUser(state, "admin").admin, false)

	-- Every command has an executable and every executable has a command.
	for i = 1, #binNames do
		local node = state.fs.children.bin.children[binNames[i]]
		check("/bin/" .. binNames[i] .. " exists", node ~= nil)
		eq("/bin/" .. binNames[i] .. " is a file", node.type, "file")
		eq("/bin/" .. binNames[i] .. " owner", node.owner, "root")
		eq("/bin/" .. binNames[i] .. " mode", node.mode, 755)
		eq("/bin/" .. binNames[i] .. " describes itself",
			node.data, CeroSecOS.commandDesc(binNames[i]))
		check("/bin/" .. binNames[i] .. " has a command behind it",
			CeroSecOS.commands[binNames[i]] ~= nil)
	end
	local described = 0
	for name, _ in pairs(CeroSecOS.COMMAND_INFO) do
		described = described + 1
		-- Every command carries both halves, and the usage line begins with the
		-- name it is the usage of: a usage that names another command is the
		-- one way this table can lie to a player.
		check(name .. " has a description", type(CeroSecOS.commandDesc(name)) == "string")
		local form = CeroSecOS.commandUsage(name)
		check(name .. " has a usage line", type(form) == "string")
		eq(name .. "'s usage line names it", string.sub(form, 1, #name), name)
	end
	local implemented = 0
	for _, _ in pairs(CeroSecOS.commands) do implemented = implemented + 1 end
	eq("every command is in /bin", implemented, described)
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

	-- Nothing sets a password by writing the field: the stored string is a
	-- hash, and setPassword is the one thing that makes one.
	eq("setting a password works", CeroSecOS.setPassword(state, "root", "hunter2"), true)
	local denied, why2 = CeroSecOS.login(state, "root", "wrong")
	eq("bad password gives no session", denied, nil)
	eq("bad password reason", why2, "wrong password")
	check("good password logs in", CeroSecOS.login(state, "root", "hunter2") ~= nil)
	eq("checkPassword on nil user", CeroSecOS.checkPassword(nil, ""), false)
	eq("checkPassword nil means empty", CeroSecOS.checkPassword(CeroSecOS.getUser(state, "admin"), nil), true)

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

	-- Packed into columns: five short names fit one row of a 60-column screen.
	ok(state, admin, "ls /", { "bin   dev   etc   home  root" })
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

	--
	-- The tilde. Expanded by the shell, once, before any command sees its
	-- arguments -- so it is every command's and not cd's.
	--
	ok(state, admin, "cd /etc", {})
	ok(state, admin, "cd ~", {})
	-- Which is the cwd the prompt shortens back to "~" (terminal_test.lua).
	eq("cd ~ goes home", admin.cwd, "/home/admin")
	ok(state, admin, "mkdir ~/box", {})
	ok(state, admin, "cd ~/box", {})
	eq("cd ~/box is under the home", admin.cwd, "/home/admin/box")
	ok(state, admin, "cd ~", {})
	ok(state, admin, "ls ~", { "box  sub" })
	ok(state, admin, 'write ~/tilde.txt "hi"', {})
	ok(state, admin, "cat ~/tilde.txt", { "hi" })
	ok(state, admin, "cd /etc", {})
	ok(state, admin, "cat ~/tilde.txt", { "hi" })   -- and from anywhere else
	ok(state, admin, "echo one > ~/tilde.txt", {})
	ok(state, admin, "cat ~/tilde.txt", { "one" })
	ok(state, admin, "rm ~/tilde.txt", {})
	ok(state, admin, "rm -r ~/box", {})
	ok(state, admin, "cd ~", {})

	-- A tilde that is not the shortcut is a name, and a name may not hold one.
	bad(state, admin, "cd ~root", "cd: ~root: no such file")
	bad(state, admin, "cd ~/nope", "cd: /home/admin/nope: no such file")
	bad(state, admin, "cd a~b", "cd: a~b: no such file")
	ok(state, admin, "echo a~b", { "a~b" })         -- not a path, not touched

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
	ok(state, admin, "ls", { "notes.txt    renamed.txt  sub" })
	ok(state, admin, "mv renamed.txt sub", {})      -- into a directory
	ok(state, admin, "ls sub", { "notes.txt    renamed.txt" })
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
	-- The tilde is the account's home, so root's is /root and not /home/root.
	ok(state, rootSession, "cd /etc", {})
	ok(state, rootSession, "cd ~", {})
	ok(state, rootSession, "pwd", { "/root" })
	ok(state, rootSession, "cat ~/../etc/hostname", { "ksp-front-01" })
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
	bad(state, admin, "cat", "cat: usage: cat <file>...")
	bad(state, admin, "cd /root", "cd: /root: permission denied")
	bad(state, admin, "cd /nope", "cd: /nope: no such file")
	bad(state, admin, "cd /etc/motd", "cd: /etc/motd: not a directory")
	bad(state, admin, "cd a b", "cd: usage: cd [dir]")
	bad(state, admin, "cat /root/secret.txt", "cat: /root/secret.txt: permission denied")
	bad(state, admin, "ls /root/x", "ls: /root/x: permission denied")
	bad(state, admin, "ls /nope", "ls: /nope: no such file")
	bad(state, admin, "ls -z", "ls: -z: unknown option")
	bad(state, admin, "ls a b", "ls: usage: ls [-lF] [path]")
	bad(state, admin, "mkdir", "mkdir: usage: mkdir <dir>")
	bad(state, admin, "mkdir a b", "mkdir: usage: mkdir <dir>")
	bad(state, admin, "mkdir /etc/x", "mkdir: /etc/x: permission denied")
	bad(state, admin, "mkdir /nope/x", "mkdir: /nope/x: no such file")
	bad(state, admin, 'mkdir "/home/admin/bad name"', "mkdir: /home/admin/bad name: invalid name")
	bad(state, admin, "touch /etc/x", "touch: /etc/x: permission denied")
	bad(state, admin, "touch /etc", "touch: /etc: is a directory")
	bad(state, admin, "touch", "touch: usage: touch <file>")
	bad(state, admin, "rm", "rm: usage: rm [-r] <path>...")
	bad(state, admin, "rm /", "rm: /: permission denied")
	bad(state, admin, "rm /etc/motd", "rm: /etc/motd: permission denied")
	bad(state, admin, "rm /nope", "rm: /nope: no such file")
	bad(state, admin, "rm -z x", "rm: -z: unknown option")
	bad(state, admin, "mv", "mv: usage: mv <src> <dst>")
	bad(state, admin, "mv a", "mv: usage: mv <src> <dst>")
	bad(state, admin, "mv /nope /home/admin/x", "mv: /nope: no such file")
	bad(state, admin, "cp", "cp: usage: cp [-r] <src> <dst>")
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
	bad(state, admin, "hostname x", "hostname: permission denied")
	bad(state, admin, "hostname a b", "hostname: usage: hostname [name]")

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
	-- What went into the file is what was on the screen: the packed row, not a
	-- name per line. A redirect stores the OUTPUT and never a second rendering.
	ok(state, admin, "cat listing.txt", { "bin   dev   etc   home  root" })
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
	-- The skeleton, plus one executable per command, plus /etc/passwd and
	-- /etc/sudoers.
	eq("starting node count", nodes, 9 + #CeroSecOS.binNames() + 2)
	local made = 0
	local dir = 0
	while true do
		dir = dir + 1
		if not CeroSecOS.exec(state, rootSession, "mkdir /p" .. dir) then break end
		made = made + 1
		local full = false
		for i = 1, 64 do
			if nodes + made >= 256 then full = true break end
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

	-- 10 perm + 2 + 8 owner + 2 + 5 size + 2 + 12 date + 2 + name = 60 at most.
	-- Nothing on a fresh machine was ever stamped, so every date is the epoch:
	-- an unstamped node is mtime 0 and 0 is a real moment, not a blank.
	local EPOCH = "Jan  1 00:00"
	local lines = ok(state, admin, "ls -l /", nil)
	eq("ls -l lists 5 entries", #lines, 5)
	eq("ls -l bin",
		lines[1],
		"drwxr-xr-x" .. "  " .. "root    " .. "  "
			.. CeroSecOS.padLeft(tostring(#CeroSecOS.binNames()), 5) .. "  " .. EPOCH .. "  bin")
	eq("ls -l root dir",
		lines[5],
		"drwx------" .. "  " .. "root    " .. "  " .. "    0" .. "  " .. EPOCH .. "  root")
	for i = 1, #lines do
		check("ls -l line " .. i .. " fits 60 columns", #lines[i] <= 60)
	end

	local etc = ok(state, admin, "ls -l /etc", nil)
	eq("ls -l motd",
		etc[2],
		"-rw-r--r--" .. "  " .. "root    " .. "  " .. "   52" .. "  " .. EPOCH .. "  motd")
	eq("ls -l sudoers",
		etc[4],
		"-r--r-----" .. "  " .. "root    " .. "  "
			.. CeroSecOS.padLeft(tostring(#CeroSecOS.defaultSudoers()), 5)
			.. "  " .. EPOCH .. "  sudoers")
	eq("ls -l /etc has 4 lines", #etc, 4)

	-- Every permission digit renders.
	ok(state, admin, "touch /home/admin/perm", {})
	ok(state, admin, "chmod 777 /home/admin/perm", {})
	eq("777 renders", string.sub(ok(state, admin, "ls -l /home/admin/perm", nil)[1], 1, 10), "-rwxrwxrwx")
	ok(state, admin, "chmod 000 /home/admin/perm", {})
	eq("000 renders", string.sub(ok(state, admin, "ls -l /home/admin/perm", nil)[1], 1, 10), "----------")
	ok(state, admin, "chmod 421 /home/admin/perm", {})
	eq("421 renders", string.sub(ok(state, admin, "ls -l /home/admin/perm", nil)[1], 1, 10), "-r---w---x")
	ok(state, admin, "chmod 644 /home/admin/perm", {})

	-- The name is the LAST column and the only one that is ever cut: 17
	-- characters, then a "~".
	local longName = string.rep("n", 32)
	ok(state, admin, "touch /home/admin/" .. longName, {})
	local home = ok(state, admin, "ls -l /home/admin", nil)
	local cut = nil
	for i = 1, #home do
		if string.find(home[i], "nnn", 1, true) ~= nil then cut = home[i] end
	end
	check("the long name is listed", cut ~= nil)
	eq("the long-name line is exactly 60 columns", #cut, 60)
	eq("the long name is cut with a tilde", string.sub(cut, 44), string.rep("n", 16) .. "~")

	-- A long owner is cut the same way, in its own column.
	addUser(state, "administrator", "", "/home/admin", false)
	ok(state, rootSession, "chown administrator /home/admin/perm", {})
	local owned = ok(state, rootSession, "ls -l /home/admin/perm", nil)
	eq("the long owner is cut with a tilde", string.sub(owned[1], 13, 20), "adminis~")

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

	local noSysv = fresh()
	noSysv.sysv = nil
	local svOk, svReason = CeroSecOS.validate(noSysv)
	eq("a state with no system version is refused", svOk, false)
	eq("and says so", svReason, "bad system version")
	local badSysv = fresh()
	badSysv.sysv = "2"
	eq("nor is one that is not a number", CeroSecOS.validate(badSysv), false)

	-- The accounts are a file, so this is what validate has left to say about
	-- them: it is there, it is a file, and it is root's.
	local noPasswd = fresh()
	noPasswd.fs.children.etc.children.passwd = nil
	local nrOk, nrReason = CeroSecOS.validate(noPasswd)
	eq("a state without /etc/passwd is refused", nrOk, false)
	eq("no-passwd reason", nrReason, "no /etc/passwd")

	local passwdDir = fresh()
	passwdDir.fs.children.etc.children.passwd = CeroSecOS.newDir("root", 755)
	local pdOk, pdReason = CeroSecOS.validate(passwdDir)
	eq("a /etc/passwd that is a directory is refused", pdOk, false)
	eq("and says so", pdReason, "/etc/passwd: not a file")

	local passwdMine = fresh()
	passwdMine.fs.children.etc.children.passwd.owner = "admin"
	local pmOk, pmReason = CeroSecOS.validate(passwdMine)
	eq("a /etc/passwd that is not root's is refused", pmOk, false)
	eq("and says so", pmReason, "/etc/passwd: not root's")

	-- A file full of nonsense is NOT a state the core cannot run on: it is a
	-- machine nobody can log in to, which is the boot check's business.
	local unparseable = fresh()
	unparseable.fs.children.etc.children.passwd.data = "nonsense"
	eq("an unparseable /etc/passwd still validates", CeroSecOS.validate(unparseable), true)
	eq("but there is nobody on the machine", CeroSecOS.hasUsers(unparseable), false)
	eq("and the boot check says so", CeroSecOS.systemOk(unparseable), false)

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
	broken.fs.children.etc.children.passwd = nil
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

--
-- 14b. Passwords are hashed, and nothing anywhere holds one in clear.
--

do
	-- The shape of what is stored.
	local stored = CeroSecOS.hashPassword("hunter2", "abcdef")
	eq("the tag names the construction", string.sub(stored, 1, 5), "$cs1$")
	eq("the salt is in it", string.sub(stored, 6, 11), "abcdef")
	eq("then a separator", string.sub(stored, 12, 12), "$")
	eq("then 32 hex digits", #string.sub(stored, 13), 32)
	eq("and they are hex", string.find(string.sub(stored, 13), "[^0-9a-f]"), nil)
	eq("the whole thing fits a screen line", #stored <= CeroSecOS.COLS, true)

	local salt, hash = CeroSecOS.splitHash(stored)
	eq("split gives the salt back", salt, "abcdef")
	eq("split gives the hash back", hash, string.sub(stored, 13))

	-- Deterministic: the same password and the same salt, always the same line.
	eq("the same twice", CeroSecOS.hashPassword("hunter2", "abcdef"), stored)
	eq("and a third time", CeroSecOS.hashPassword("hunter2", "abcdef"), stored)
	eq("an empty password is hashed like any other",
		#CeroSecOS.hashPassword("", "abcdef"), #stored)
	check("and is not the same line", CeroSecOS.hashPassword("", "abcdef") ~= stored)
	eq("what is not a string is the empty password",
		CeroSecOS.hashPassword(nil, "abcdef"), CeroSecOS.hashPassword("", "abcdef"))

	-- The salt is what makes two accounts with one password look different.
	check("another salt, another hash",
		CeroSecOS.hashPassword("hunter2", "abcdeg") ~= stored)

	-- Avalanche: one byte different, and most of the digits move. 32 hex digits
	-- with nothing in common would differ in about 30 of them.
	local function moved(a, b)
		local n = 0
		for i = 1, #a do
			if string.sub(a, i, i) ~= string.sub(b, i, i) then n = n + 1 end
		end
		return n
	end
	local one = string.sub(CeroSecOS.hashPassword("hunter2", "abcdef"), 13)
	local two = string.sub(CeroSecOS.hashPassword("hunter3", "abcdef"), 13)
	check("one byte of the password moves most of the digits", moved(one, two) >= 24)
	local saltA = string.sub(CeroSecOS.hashPassword("hunter2", "abcdef"), 13)
	local saltB = string.sub(CeroSecOS.hashPassword("hunter2", "abcdff"), 13)
	check("one byte of the salt moves most of them too", moved(saltA, saltB) >= 24)
	-- Length alone changes it: "ab" and "abc" do not start from the same place.
	check("a longer password is a different hash",
		CeroSecOS.hashPassword("ab", "abcdef") ~= CeroSecOS.hashPassword("abc", "abcdef"))

	-- Salts.
	eq("a salt is six base 36 digits", #CeroSecOS.newSalt(nil, "x"), CeroSecOS.SALT_DIGITS)
	eq("and only base 36 digits", string.find(CeroSecOS.newSalt(nil, "y"), "[^0-9a-z]"), nil)
	local salts = {}
	for i = 1, 200 do
		local s = CeroSecOS.newSalt({ hostname = "ksp-1-1" }, "root")
		check("salt " .. i .. " (" .. s .. ") has not been given out before", salts[s] == nil)
		salts[s] = true
	end
	eq("a valid salt", CeroSecOS.isValidSalt("abc123"), true)
	eq("upper case is not a salt", CeroSecOS.isValidSalt("ABC"), false)
	eq("a dollar is not a salt", CeroSecOS.isValidSalt("a$b"), false)
	eq("an empty salt is not one", CeroSecOS.isValidSalt(""), false)
	eq("a salt is not a table", CeroSecOS.isValidSalt({}), false)

	-- Anything that is not one of our lines is not a stored password.
	for _, junk in ipairs({
		"hunter2", "", "$cs1$$abc", "$cs2$abcdef$" .. string.rep("a", 32),
		"$cs1$abcdef$" .. string.rep("a", 31), "$cs1$abcdef$" .. string.rep("a", 33),
		"$cs1$abcdef$" .. string.rep("g", 32), "$cs1$ABCDEF$" .. string.rep("a", 32),
		"$cs1$abcdef$" .. string.rep("a", 32) .. "\n",
	}) do
		eq("not a stored password: " .. string.format("%q", junk),
			CeroSecOS.splitHash(junk), nil)
	end
	eq("nor is a number", CeroSecOS.splitHash(7), nil)
	eq("nor is nil", CeroSecOS.splitHash(nil), nil)
end

do
	-- The budget. A login is one hash, so this is what a login costs. Kahlua is
	-- several times slower than lua5.1, and the ceiling that matters is about a
	-- fifth of a second there. The measurement is about 5 ms on an idle
	-- machine; the budget is ten times that, because a test that runs while the
	-- machine is busy must not go red for it.
	local start = os.clock()
	local N = 10
	for i = 1, N do CeroSecOS.hashPassword("hunter2", "abcdef") end
	local ms = (os.clock() - start) / N * 1000
	check("a hash costs less than 50 ms under lua5.1 (measured " ..
		string.format("%.1f", ms) .. " ms at " .. CeroSecOS.HASH_ROUNDS .. " rounds)", ms < 50)
end

do
	-- A fresh machine: open accounts, and not a password in clear anywhere.
	local state = fresh()
	check("root ships open", CeroSecOS.login(state, "root", "") ~= nil)
	check("admin ships open", CeroSecOS.login(state, "admin", "") ~= nil)
	check("root's stored password is a hash", CeroSecOS.splitHash(stored(state, "root")) ~= nil)
	check("and it is not the word", stored(state, "root") ~= "")
	-- Two accounts, the same (empty) password, two different lines.
	check("two accounts with one password do not look alike",
		stored(state, "root") ~= stored(state, "admin"))
	eq("the state validates", CeroSecOS.validate(state), true)

	-- A password in clear is not a password: the parser drops the whole line,
	-- so the account is simply not on the machine. Nobody logs in as somebody
	-- whose line does not parse -- least of all with the word itself.
	setStored(state, "admin", "hunter2")
	eq("a cleartext line is skipped", CeroSecOS.getUser(state, "admin"), nil)
	eq("and nobody logs in on it", CeroSecOS.login(state, "admin", "hunter2"), nil)
	check("the other account is untouched", CeroSecOS.getUser(state, "root") ~= nil)
	setStored(state, "admin", "$cs1$abcdef$" .. string.rep("z", 32))
	eq("nor is a hash with digits that are not hex accepted",
		CeroSecOS.getUser(state, "admin"), nil)
end

-- A machine saved before /etc/passwd: the accounts are a table on the state and
-- there is no accounts file, no /bin and nothing to run. Built here rather than
-- copied from a save file, because that is the only shape such a save has.
local function oldState(rootPassword, adminPassword)
	local state = fresh()
	-- A save from before the contents were numbered carries no number.
	state.sysv = nil
	state.fs.children.etc.children.passwd = nil
	state.fs.children.bin = CeroSecOS.newDir("root", 755)
	state.users = {
		root = { name = "root", password = rootPassword, home = "/root", admin = true },
		admin = { name = "admin", password = adminPassword, home = "/home/admin", admin = false },
	}
	state.fs.children.etc.children.kept = CeroSecOS.newFile("root", 644, "still here")
	return state
end

do
	-- Passwords in clear AND no file: migrate hashes them, writes the file,
	-- fills /bin, and drops the table. The accounts go on working.
	local migrated = CeroSecOS.migrate(oldState("toor", ""), "ksp-front-01")
	check("the machine was kept, not replaced",
		migrated.fs.children.etc.children.kept ~= nil)
	eq("the users table is gone", migrated.users, nil)
	check("the accounts are a file now",
		migrated.fs.children.etc.children.passwd ~= nil)
	eq("owned by root", migrated.fs.children.etc.children.passwd.owner, "root")
	eq("and closed to everybody else", migrated.fs.children.etc.children.passwd.mode, 600)
	check("root's password is a hash now",
		CeroSecOS.splitHash(stored(migrated, "root")) ~= nil)
	check("and so is the empty one",
		CeroSecOS.splitHash(stored(migrated, "admin")) ~= nil)
	check("root still logs in with what he had",
		CeroSecOS.login(migrated, "root", "toor") ~= nil)
	check("and not with anything else", CeroSecOS.login(migrated, "root", "") == nil)
	check("admin still logs in with nothing",
		CeroSecOS.login(migrated, "admin", "") ~= nil)
	eq("admin is still not an admin", CeroSecOS.getUser(migrated, "admin").admin, false)
	eq("root still is one", CeroSecOS.getUser(migrated, "root").admin, true)
	eq("and the state validates now", CeroSecOS.validate(migrated), true)
	-- A machine converted this way boots: it was made before there were
	-- executables, so the migration gives it the ones it never had.
	eq("the converted machine boots", CeroSecOS.systemOk(migrated), true)
	local session = open(migrated, "admin")
	ok(migrated, session, "pwd", { "/home/admin" })

	-- Running it twice changes nothing: the table is gone and the file stands.
	local before = stored(migrated, "root")
	CeroSecOS.migrateUsers(migrated)
	eq("a second pass leaves the hash alone", stored(migrated, "root"), before)

	-- Nothing to do, and nothing thrown.
	local empty = {}
	eq("no users, no complaint", CeroSecOS.migrateUsers(empty), empty)
	eq("not a state, no complaint", CeroSecOS.migrateUsers("x"), "x")
end

do
	-- A file on the disk wins over a table beside it: what the machine has been
	-- running on is not something a migration may quietly replace.
	local state = oldState("toor", "toor")
	state.fs.children.etc.children.passwd = CeroSecOS.newFile("root", 600,
		CeroSecOS.passwdLine(CeroSecOS.newUser("root", "onthedisk", "/root", true)))
	CeroSecOS.migrateUsers(state)
	eq("the table is dropped", state.users, nil)
	check("the file is the one that was there",
		CeroSecOS.login(state, "root", "onthedisk") ~= nil)
	eq("and not the table", CeroSecOS.login(state, "root", "toor"), nil)
	eq("an account only the table had is gone", CeroSecOS.getUser(state, "admin"), nil)
end

do
	-- The hash command: the same function, on a string you choose.
	local state = fresh()
	local session = open(state, "admin")

	ok(state, session, "hash hunter2 abcdef", { CeroSecOS.hashPassword("hunter2", "abcdef") })
	-- Pinned, so a change to the construction is a change to this file.
	ok(state, session, "hash hunter2 abcdef",
		{ "$cs1$abcdef$" .. string.sub(CeroSecOS.hashPassword("hunter2", "abcdef"), 13) })
	ok(state, session, 'hash "" abcdef', { CeroSecOS.hashPassword("", "abcdef") })

	-- Without a salt, a fresh one each time: two runs never agree.
	local first = ok(state, session, "hash hunter2")[1]
	local second = ok(state, session, "hash hunter2")[1]
	check("a fresh salt every time", first ~= second)
	check("and both are stored passwords", CeroSecOS.splitHash(first) ~= nil)
	eq("a hash line fits the screen", #first <= CeroSecOS.COLS, true)

	bad(state, session, "hash", "hash: usage: hash <text> [salt]")
	bad(state, session, "hash a b c", "hash: usage: hash <text> [salt]")
	bad(state, session, "hash x BAD", "hash: BAD: invalid salt")
	bad(state, session, 'hash x "a$b"', "hash: a$b: invalid salt")
end

--
-- 15. passwd, and the continuation mechanism under it.
--

-- exec/continue with the whole four-value shape kept, because that shape is
-- what the console drives an interactive command with.
local function run(state, session, line)
	local execOk, lines, control, data = CeroSecOS.exec(state, session, line)
	return { ok = execOk, lines = lines, control = control, data = data }
end

local function answer(state, session, cont, line)
	local aOk, lines, control, data = CeroSecOS.continue(state, session, cont, line)
	return { ok = aOk, lines = lines, control = control, data = data }
end

-- A prompt step: it asks, it says nothing, and it hands back a token that is a
-- plain table of strings -- the shape the console can save.
local function asks(step, text, mask)
	eq("`" .. text .. "` succeeds", step.ok, true)
	eq("`" .. text .. "` prints nothing", #step.lines, 0)
	eq("`" .. text .. "` orders a prompt", step.control, "prompt")
	eq("`" .. text .. "` prompt text", step.data.text, text)
	eq("`" .. text .. "` mask", step.data.mask, mask)
	check("`" .. text .. "` carries a token", type(step.data.cont) == "table")
	eq("`" .. text .. "` token names its command", step.data.cont.cmd, "passwd")
	return step.data.cont
end

local function says(step, line)
	eq("`" .. line .. "` line count", #step.lines, 1)
	eq("`" .. line .. "`", step.lines[1], line)
	return step
end

do
	local state = fresh()
	local session = open(state, "admin")

	-- Happy path: old, new, retype.
	local cont = asks(run(state, session, "passwd"), "Old password: ", true)
	eq("the token names the account", cont.user, "admin")
	eq("the first step is the old password", cont.step, "old")
	cont = asks(answer(state, session, cont, ""), "New password: ", true)
	cont = asks(answer(state, session, cont, "hunter2"), "Retype new password: ", true)
	local done = answer(state, session, cont, "hunter2")
	eq("the chain ends", done.control, nil)
	eq("and it worked", done.ok, true)
	says(done, "passwd: password updated")
	eq("the password is the new one", holds(state, "admin", "hunter2"), true)

	-- And the machine judges it: the old one no longer opens the account.
	check("the old password is refused", CeroSecOS.login(state, "admin", "") == nil)
	check("the new password is taken", CeroSecOS.login(state, "admin", "hunter2") ~= nil)

	-- Wrong old password: one line, and nothing changed.
	cont = asks(run(state, session, "passwd"), "Old password: ", true)
	local refused = answer(state, session, cont, "wrong")
	eq("a wrong old password fails", refused.ok, false)
	eq("and ends the chain", refused.control, nil)
	says(refused, "passwd: authentication failure")
	eq("the password is untouched", holds(state, "admin", "hunter2"), true)

	-- Mismatch: the retype has to be the same string.
	cont = asks(run(state, session, "passwd"), "Old password: ", true)
	cont = asks(answer(state, session, cont, "hunter2"), "New password: ", true)
	cont = asks(answer(state, session, cont, "abc"), "Retype new password: ", true)
	local mismatch = answer(state, session, cont, "abd")
	eq("a mismatch fails", mismatch.ok, false)
	says(mismatch, "passwd: passwords do not match")
	eq("the password is untouched", holds(state, "admin", "hunter2"), true)

	-- An empty new password is a password: the accounts ship that way.
	cont = asks(run(state, session, "passwd"), "Old password: ", true)
	cont = asks(answer(state, session, cont, "hunter2"), "New password: ", true)
	cont = asks(answer(state, session, cont, ""), "Retype new password: ", true)
	says(answer(state, session, cont, ""), "passwd: password updated")
	eq("the password is empty again", holds(state, "admin", ""), true)

	-- Somebody else's password is root's business and nobody else's.
	says(run(state, session, "passwd root"), "passwd: permission denied")
	says(run(state, session, "passwd nobody"), "passwd: no such user")
	eq("no such user fails", run(state, session, "passwd nobody").ok, false)
	says(run(state, session, "passwd a b"), "passwd: usage: passwd [user]")
end

do
	local state = fresh()
	local session = open(state, "root")

	-- root is asked for nobody's old password, its own included.
	local cont = asks(run(state, session, "passwd"), "New password: ", true)
	eq("root changes root", cont.user, "root")
	cont = asks(answer(state, session, cont, "toor"), "Retype new password: ", true)
	says(answer(state, session, cont, "toor"), "passwd: password updated")
	eq("root's password", holds(state, "root", "toor"), true)

	-- And root sets somebody else's without knowing it.
	cont = asks(run(state, session, "passwd admin"), "New password: ", true)
	eq("the token names the account", cont.user, "admin")
	cont = asks(answer(state, session, cont, "letmein"), "Retype new password: ", true)
	says(answer(state, session, cont, "letmein"), "passwd: password updated")
	eq("admin's password", holds(state, "admin", "letmein"), true)
	says(run(state, session, "passwd nobody"), "passwd: no such user")

	-- A password the machine will not store.
	cont = asks(run(state, session, "passwd admin"), "New password: ", true)
	cont = asks(answer(state, session, cont, string.rep("x", 33)), "Retype new password: ", true)
	says(answer(state, session, cont, string.rep("x", 33)), "passwd: password too long")
	cont = asks(run(state, session, "passwd admin"), "New password: ", true)
	cont = asks(answer(state, session, cont, "a\1b"), "Retype new password: ", true)
	says(answer(state, session, cont, "a\1b"), "passwd: invalid characters")
	eq("admin's password survived both", holds(state, "admin", "letmein"), true)

	-- The state a chain leaves behind is still storable.
	eq("the state still validates", CeroSecOS.validate(state), true)
end

do
	-- An abandoned chain. The console drops the token and runs the next command;
	-- the token is then a dead thing, and answering it later changes nothing.
	local state = fresh()
	local session = open(state, "admin")
	local cont = asks(run(state, session, "passwd"), "Old password: ", true)
	cont = asks(answer(state, session, cont, ""), "New password: ", true)

	-- The next thing typed is a command, not an answer: it runs normally.
	ok(state, session, "mkdir notes", {})
	eq("the abandoned chain changed no password", holds(state, "admin", ""), true)

	-- And the token, answered afterwards, still only asks: nothing was reserved
	-- for it and nothing is left half-done.
	local late = answer(state, session, cont, "zzz")
	eq("a stale token still only asks", late.control, "prompt")
	eq("the password is still the old one", holds(state, "admin", ""), true)

	-- A token that is not one is refused, and refused the same way twice.
	for _, junk in ipairs({ "not a table", 7, {}, { cmd = "frobnicate" }, { cmd = 1 } }) do
		local bogus = answer(state, session, junk, "x")
		eq("a bogus token fails", bogus.ok, false)
		eq("a bogus token orders nothing", bogus.control, nil)
		eq("a bogus token says so", bogus.lines[1], "cerosec: nothing to answer")
	end
	local nilCont = answer(state, session, nil, "x")
	eq("no token at all fails", nilCont.ok, false)
	eq("no token at all says so", nilCont.lines[1], "cerosec: nothing to answer")

	eq("nothing of it reached the state", CeroSecOS.validate(state), true)
end

do
	-- The chain carries the account it is about, so it carries the authority to
	-- touch it at EVERY step and not only at the first. No client can forge a
	-- token today -- it never leaves the server -- but a check that lives only
	-- in the command is a check one refactor away from being no check at all.
	local state = fresh()
	addUser(state, "bob", "", "/home/bob", false)
	local session = open(state, "bob")

	says(run(state, session, "passwd root"), "passwd: permission denied")

	-- The token the command refused to hand out, handed in anyway.
	local forged = { cmd = "passwd", step = "new", user = "root" }
	local step = answer(state, session, forged, "pwned")
	eq("a forged token is refused", step.ok, false)
	eq("and asks nothing", step.control, nil)
	says(step, "passwd: permission denied")

	-- Every step of it, not just the first.
	says(answer(state, session, { cmd = "passwd", step = "old", user = "root" }, ""),
		"passwd: permission denied")
	says(answer(state, session, { cmd = "passwd", step = "retype", user = "root",
		salt = "abcdef", want = CeroSecOS.hashPassword("pwned", "abcdef") }, "pwned"),
		"passwd: permission denied")

	check("root's password is untouched", holds(state, "root", ""))
	check("and the forged one never took", not holds(state, "root", "pwned"))

	-- His own is still his own.
	local cont = asks(run(state, session, "passwd"), "Old password: ", true)
	cont = asks(answer(state, session, cont, ""), "New password: ", true)
	cont = asks(answer(state, session, cont, "bobs"), "Retype new password: ", true)
	says(answer(state, session, cont, "bobs"), "passwd: password updated")
	check("bob changed bob", holds(state, "bob", "bobs"))
end

do
	-- Nothing of a password reaches the token. The console it lives in is
	-- written to the save file, so the one window between the two questions
	-- must not be the one place on the machine that hands a password over.
	local state = fresh()
	local session = open(state, "admin")
	local cont = asks(run(state, session, "passwd"), "Old password: ", true)
	cont = asks(answer(state, session, cont, ""), "New password: ", true)
	cont = asks(answer(state, session, cont, "hunter2"), "Retype new password: ", true)

	eq("the token is at the retype", cont.step, "retype")
	check("it carries a salt", CeroSecOS.isValidSalt(cont.salt))
	check("and a hash, not a password", CeroSecOS.splitHash(cont.want) ~= nil)
	for key, value in pairs(cont) do
		if type(value) == "string" then
			check("no field of the token is the password (" .. key .. ")", value ~= "hunter2")
			check("nor holds it (" .. key .. ")",
				string.find(value, "hunter2", 1, true) == nil)
		end
	end

	-- And it still judges the retype the way it always did.
	says(answer(state, session, cont, "hunter3"), "passwd: passwords do not match")
	check("so nothing changed", holds(state, "admin", ""))
	cont = asks(run(state, session, "passwd"), "Old password: ", true)
	cont = asks(answer(state, session, cont, ""), "New password: ", true)
	cont = asks(answer(state, session, cont, "hunter2"), "Retype new password: ", true)
	says(answer(state, session, cont, "hunter2"), "passwd: password updated")
	check("the password took", holds(state, "admin", "hunter2"))

	-- The whole chain is still something the game can serialize.
	eq("the state validates", CeroSecOS.validate(state), true)
end

do
	-- A prompt is not output, so it is never redirected into a file either.
	local state = fresh()
	local session = open(state, "admin")
	local step = run(state, session, "passwd > out.txt")
	eq("the prompt still comes", step.control, "prompt")
	eq("and no file was made", CeroSecOS.getNode(state, session, "out.txt"), nil)
end

--
-- 16. edit: what the core says about opening a file, and the save path.
--

do
	local state = fresh()
	local session = open(state, "admin")

	ok(state, session, 'write notes.txt "one\ntwo"', {})

	-- An existing file the user owns: its text, and writable.
	local step = run(state, session, "edit notes.txt")
	eq("edit succeeds", step.ok, true)
	eq("edit prints nothing", #step.lines, 0)
	eq("edit orders the editor", step.control, "edit")
	eq("edit hands back the absolute path", step.data.path, "/home/admin/notes.txt")
	eq("edit hands back the text", step.data.text, "one\ntwo")
	eq("edit says it is writable", step.data.readonly, false)

	-- A file that is not there yet, in a directory that is: an empty buffer.
	step = run(state, session, "edit fresh.txt")
	eq("a new file opens", step.control, "edit")
	eq("a new file is empty", step.data.text, "")
	eq("a new file is writable", step.data.readonly, false)
	eq("a new file is not created by opening it",
		CeroSecOS.getNode(state, session, "fresh.txt"), nil)

	-- A directory that is not there: the same refusal as any other command.
	bad(state, session, "edit nowhere/a.txt", "edit: nowhere/a.txt: no such file")
	bad(state, session, "edit /etc/deep/a.txt", "edit: /etc/deep/a.txt: no such file")
	-- A directory that is there but is not writable by this user.
	bad(state, session, "edit /etc/new.txt", "edit: /etc/new.txt: permission denied")
	-- A directory is not a file.
	bad(state, session, "edit /etc", "edit: /etc: is a directory")
	bad(state, session, "edit /", "edit: /: is a directory")
	bad(state, session, "edit notes.txt/x", "edit: notes.txt/x: not a directory")
	-- A name the machine cannot create is refused at the name, not at the save.
	bad(state, session, "edit -bad", "edit: -bad: invalid name")
	bad(state, session, "edit " .. string.rep("a", 33), "edit: " .. string.rep("a", 33) .. ": invalid name")
	bad(state, session, "edit", "edit: usage: edit <file>")
	bad(state, session, "edit a b", "edit: usage: edit <file>")

	-- A file the user may not even look at.
	ok(state, session, "chmod 000 notes.txt", {})
	bad(state, session, "edit notes.txt", "edit: notes.txt: permission denied")
	-- Readable but not writable: it opens, marked read-only.
	ok(state, session, "chmod 400 notes.txt", {})
	step = run(state, session, "edit notes.txt")
	eq("a read-only file opens", step.control, "edit")
	eq("and says so", step.data.readonly, true)
	eq("with its text", step.data.text, "one\ntwo")
end

do
	-- The admin's own directory, seen from root, and root's own from the admin.
	local state = fresh()
	local admin = open(state, "admin")
	local root = open(state, "root")

	bad(state, admin, "edit /root/secret.txt", "edit: /root/secret.txt: permission denied")
	local step = run(state, root, "edit /root/secret.txt")
	eq("root opens a new file in its own home", step.control, "edit")
	eq("root is never read-only", step.data.readonly, false)

	-- root reads a file nobody else may: still writable, because root.
	local write = run(state, admin, 'write /home/admin/p.txt "x"')
	eq("the admin wrote it", write.ok, true)
	local chmod = run(state, admin, "chmod 000 /home/admin/p.txt")
	eq("and shut it", chmod.ok, true)
	step = run(state, root, "edit /home/admin/p.txt")
	eq("root opens it anyway", step.control, "edit")
	eq("and may write it", step.data.readonly, false)
end

do
	-- The save path the editor uses is writeFile, the same one the write command
	-- and ">" go through: permissions, limits and the printable rule, in one
	-- place. The editor never gets its own.
	local state = fresh()
	local session = open(state, "admin")
	ok(state, session, "touch notes.txt", {})

	local done, reason = CeroSecOS.writeFile(state, session, "notes.txt", "hello\nworld", false)
	eq("a save works", done, true)
	eq("with no complaint", reason, nil)
	eq("and lands in the file", state.fs.children.home.children.admin.children["notes.txt"].data,
		"hello\nworld")

	-- A file that may not be written.
	ok(state, session, "chmod 400 notes.txt", {})
	done, reason = CeroSecOS.writeFile(state, session, "notes.txt", "nope", false)
	eq("a read-only file refuses", done, nil)
	eq("and says why", reason, "permission denied")
	ok(state, session, "chmod 644 notes.txt", {})

	-- The file ceiling.
	done, reason = CeroSecOS.writeFile(state, session, "notes.txt",
		string.rep("x", CeroSecOS.MAX_FILE_BYTES), false)
	eq("exactly the limit fits", done, true)
	done, reason = CeroSecOS.writeFile(state, session, "notes.txt",
		string.rep("x", CeroSecOS.MAX_FILE_BYTES + 1), false)
	eq("one byte over refuses", done, nil)
	eq("and says why", reason, "file too large")
	eq("and left the file alone",
		#state.fs.children.home.children.admin.children["notes.txt"].data,
		CeroSecOS.MAX_FILE_BYTES)

	-- The printable rule: a byte below 0x20 that is not newline or tab.
	done, reason = CeroSecOS.writeFile(state, session, "notes.txt", "a\1b", false)
	eq("a control byte refuses", done, nil)
	eq("and says why", reason, "invalid characters")
	done, reason = CeroSecOS.writeFile(state, session, "notes.txt", "a\tb\nc", false)
	eq("tab and newline are text", done, true)

	-- A directory is not a buffer.
	done, reason = CeroSecOS.writeFile(state, session, "/etc", "x", false)
	eq("a directory refuses", done, nil)
	eq("and says why", reason, "is a directory")

	-- A path in a directory this user may not write.
	done, reason = CeroSecOS.writeFile(state, session, "/etc/new.txt", "x", false)
	eq("a closed directory refuses", done, nil)
	eq("and says why", reason, "permission denied")

	eq("the state still validates", CeroSecOS.validate(state), true)
end

do
	-- The client's ceilings and the core's are the same numbers, named twice on
	-- purpose: the terminal never loads the OS core, so a drift between them
	-- would be a screen that refuses what the machine accepts, or worse.
	local defs, derr = loadfile("42/media/lua/shared/CeroSec/CeroSecDefs.lua")
	if not defs then error("cannot load the defs: " .. tostring(derr)) end
	defs()
	eq("the editor's byte ceiling is the file ceiling",
		CeroSec.EDIT_MAX_BYTES, CeroSecOS.MAX_FILE_BYTES)
	eq("the editor's line width is the screen width", CeroSec.EDIT_MAX_LINE, CeroSecOS.COLS)
	eq("the screen is as wide as the core thinks", CeroSec.COLS, CeroSecOS.COLS)
	-- And the depth of the su stack, which the console carries and the core
	-- enforces: a repair that kept five would be a machine the core cannot get
	-- out of, and one that kept three would drop a session somebody was in.
	eq("the su stack is as deep on both sides", CeroSec.SU_MAX, CeroSecOS.SU_MAX)
end

--
-- 17. /bin: a command is a file, and taking the file away takes the command.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local rootSession = open(state, "root")

	-- The two error lines, in full.
	ok(state, rootSession, "rm /bin/ls", {})
	bad(state, admin, "ls", "ls: command not found")
	bad(state, rootSession, "ls", "ls: command not found")
	-- Everything else still runs.
	ok(state, admin, "pwd", { "/home/admin" })

	-- Put it back by hand: an executable is an ordinary file, so root can.
	ok(state, rootSession, 'write /bin/ls "list a directory"', {})
	ok(state, rootSession, "chmod 755 /bin/ls", {})
	ok(state, admin, "ls /etc/motd", { "motd" })

	-- Not executable: refused for everybody the bits refuse, and root bypasses
	-- them the way root bypasses every other bit on the machine.
	ok(state, rootSession, "chmod 644 /bin/ls", {})
	bad(state, admin, "ls /etc/motd", "ls: permission denied")
	ok(state, rootSession, "ls /etc/motd", { "motd" })
	-- x for the owner only is x for root only.
	ok(state, rootSession, "chmod 700 /bin/ls", {})
	bad(state, admin, "ls /etc/motd", "ls: permission denied")
	ok(state, rootSession, "chmod 755 /bin/ls", {})
	ok(state, admin, "ls /etc/motd", { "motd" })

	-- A directory called /bin/pwd is not a command.
	ok(state, rootSession, "rm /bin/pwd", {})
	ok(state, rootSession, "mkdir /bin/pwd", {})
	bad(state, admin, "pwd", "pwd: command not found")

	-- /bin shut to everybody but root: the way in is what refuses, and it says
	-- so rather than pretending the command was never there.
	ok(state, rootSession, "chmod 700 /bin", {})
	bad(state, admin, "whoami", "whoami: permission denied")
	ok(state, rootSession, "whoami", { "root" })
	ok(state, rootSession, "chmod 755 /bin", {})

	-- A file in /bin with no command behind it is not a command either.
	ok(state, rootSession, 'write /bin/telnet "not yet"', {})
	ok(state, rootSession, "chmod 755 /bin/telnet", {})
	bad(state, admin, "telnet", "telnet: command not found")

	-- A copy of an executable somewhere else is a file and nothing more:
	-- commands are found in /bin only.
	ok(state, admin, "cp /bin/ls /home/admin/ls", {})
	ok(state, admin, "chmod 755 /home/admin/ls", {})
	ok(state, admin, "cd /home/admin", {})
	bad(state, admin, "./ls", "./ls: command not found")

	eq("the state still validates", CeroSecOS.validate(state), true)
end

do
	-- The whole of /bin gone. exit and help are what is left, and help says the
	-- machine is damaged instead of listing commands it no longer has.
	local state = fresh()
	local rootSession = open(state, "root")
	ok(state, rootSession, "rm -r /bin", {})

	bad(state, rootSession, "ls", "ls: command not found")
	bad(state, rootSession, "cat /etc/motd", "cat: command not found")
	bad(state, rootSession, "passwd", "passwd: command not found")
	local damaged = expect(state, rootSession, "help", false, nil)
	eq("help says the system is damaged", damaged[1],
		"help: no commands in /bin: the system is damaged.")
	eq("and says the way back", damaged[2], "help: switch the computer off and on to repair it.")
	-- exit still leaves, and it is still an order and not a line of text.
	ok(state, rootSession, "exit", {}, "exit")

	-- The boot check calls that machine unbootable, and validate does not: the
	-- state is perfectly storable, there is just no operating system in it.
	eq("the state is still storable", CeroSecOS.validate(state), true)
	local sysOk, sysWhy = CeroSecOS.systemOk(state)
	eq("but there is no system on it", sysOk, false)
	eq("and it says why", sysWhy, "no /bin")

	-- An empty /bin counts as none at all.
	local emptied = fresh()
	CeroSecOS.systemNode(emptied, "/bin").children = {}
	local eOk, eWhy = CeroSecOS.systemOk(emptied)
	eq("an empty /bin is no /bin", eOk, false)
	eq("and it says so", eWhy, "/bin is empty")
end

--
-- 18. /etc/passwd: the format, the parser, and what a bad line does.
--

do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")

	-- The file, as it is on the disk.
	local node = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	local lines = CeroSecOS.splitLines(node.data)
	eq("two accounts ship", #lines, 2)
	local name, hash, home, kind = string.match(lines[1], "^([^:]*):([^:]*):([^:]*):([^:]*)$")
	eq("field 1 is the name", name, "root")
	check("field 2 is a stored hash", CeroSecOS.splitHash(hash) ~= nil)
	eq("field 3 is the home", home, "/root")
	eq("field 4 says what he is", kind, "admin")
	eq("and the ordinary account says the other thing",
		string.match(lines[2], "^[^:]*:[^:]*:[^:]*:([^:]*)$"), "user")

	-- Root reads it; nobody else does.
	bad(state, admin, "cat /etc/passwd", "cat: /etc/passwd: permission denied")
	local shown = ok(state, rootSession, "cat /etc/passwd", nil)
	check("root reads it", #shown > 0)

	-- One line, parsed.
	local one = CeroSecOS.parsePasswdLine(lines[1])
	eq("the name comes back", one.name, "root")
	eq("the home comes back", one.home, "/root")
	eq("and the flag is a boolean", one.admin, true)

	-- Every way a line can be wrong, and every one of them is skipped.
	local hashOf = CeroSecOS.hashPassword("", "abcdef")
	local badLines = {
		"",
		"root",
		"root:" .. hashOf .. ":/root",
		"root:" .. hashOf .. ":/root:admin:extra",
		"root:" .. hashOf .. ":/root:wheel",
		"root:hunter2:/root:admin",
		"root:$cs1$abcdef$zzzz:/root:admin",
		"-root:" .. hashOf .. ":/root:admin",
		"ro ot:" .. hashOf .. ":/root:admin",
		"root:" .. hashOf .. ":root:admin",
		"root:" .. hashOf .. "::admin",
	}
	for i = 1, #badLines do
		eq("bad line " .. i .. " is skipped", CeroSecOS.parsePasswdLine(badLines[i]), nil)
	end

	-- A malformed line in the middle of a good file takes only itself out.
	local mixed = CeroSecOS.parsePasswd(
		"root:" .. hashOf .. ":/root:admin\nrubbish\nbob:" .. hashOf .. ":/home/bob:user")
	check("the line before it survives", mixed.root ~= nil)
	check("the line after it survives", mixed.bob ~= nil)
	eq("and the rubbish is nobody", mixed.rubbish, nil)

	-- A name that appears twice keeps its first line, the way a lookup down a
	-- file does.
	local twice = CeroSecOS.parsePasswd(
		"bob:" .. CeroSecOS.hashPassword("first", "abcdef") .. ":/home/bob:user\n"
		.. "bob:" .. CeroSecOS.hashPassword("second", "abcdef") .. ":/tmp:admin")
	eq("the first line wins", twice.bob.home, "/home/bob")
	eq("and its flag with it", twice.bob.admin, false)
end

do
	-- The parser is the truth: root editing the file by hand changes who may
	-- log in and where he lands.
	local state = fresh()
	local rootSession = open(state, "root")
	ok(state, rootSession, "mkdir /home/bob", {})

	local hashOf = CeroSecOS.hashPassword("secret", "abcdef")
	ok(state, rootSession,
		'write /etc/passwd "' .. CeroSecOS.passwdLine(CeroSecOS.newUser("root", "", "/root", true))
		.. "\\n" .. "bob:" .. hashOf .. ':/home/bob:admin"', {})

	eq("admin is gone from the machine", CeroSecOS.getUser(state, "admin"), nil)
	eq("and cannot log in", CeroSecOS.login(state, "admin", ""), nil)
	local bob = CeroSecOS.login(state, "bob", "secret")
	check("the account written by hand logs in", bob ~= nil)
	eq("and lands in the home the file gave him", bob.cwd, "/home/bob")
	eq("with the powers the file gave him", CeroSecOS.getUser(state, "bob").admin, true)

	-- Re-homing an account by hand moves where cd with no argument goes.
	ok(state, rootSession,
		'write /etc/passwd "' .. CeroSecOS.passwdLine(CeroSecOS.newUser("root", "", "/root", true))
		.. "\\n" .. "bob:" .. hashOf .. ':/:user"', {})
	local moved = CeroSecOS.login(state, "bob", "secret")
	eq("the new home takes effect at once", moved.cwd, "/")
	eq("and so does the new flag", CeroSecOS.getUser(state, "bob").admin, false)

	-- The cache follows the file and not a clock: the very same read, before
	-- and after a write, gives two different answers.
	eq("before", CeroSecOS.getUser(state, "carol"), nil)
	local text = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.PASSWD_PATH,
		text .. "\ncarol:" .. hashOf .. ":/:user")
	check("after", CeroSecOS.getUser(state, "carol") ~= nil)
end

do
	-- passwd rewrites the file, and only the one line in it.
	local state = fresh()
	addUser(state, "bob", "bobpw", "/home/bob", false)
	local before = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data
	eq("three accounts", #CeroSecOS.splitLines(before), 3)

	eq("the write reports success", CeroSecOS.setPassword(state, "bob", "newpw"), true)
	local after = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data
	local wasLines = CeroSecOS.splitLines(before)
	local isLines = CeroSecOS.splitLines(after)
	eq("still three accounts", #isLines, 3)
	eq("root's line is untouched", isLines[1], wasLines[1])
	eq("admin's line is untouched", isLines[2], wasLines[2])
	check("bob's line changed", isLines[3] ~= wasLines[3])
	check("and it is still a line", CeroSecOS.parsePasswdLine(isLines[3]) ~= nil)
	eq("bob keeps his home", CeroSecOS.getUser(state, "bob").home, "/home/bob")
	check("the new password works", holds(state, "bob", "newpw"))
	check("the old one does not", not holds(state, "bob", "bobpw"))
	check("nobody else moved", holds(state, "admin", ""))

	eq("a password for nobody", CeroSecOS.setPassword(state, "nobody", "x"), nil)

	-- A stored hash is always the same length, so setPassword can never make the
	-- file bigger and a password change can never run a disk out. What it goes
	-- through can still be shown: fill the disk to eight free bytes and hand
	-- the rewrite something longer than a hash. The whole file goes through
	-- setData, so it is refused there, and refused whole -- /etc/passwd is left
	-- exactly as it was rather than half rewritten.
	local rootSession = open(state, "root")
	-- One file holds at most MAX_FILE_BYTES, so filling a disk takes several.
	local filler = 0
	while true do
		local _, used = CeroSecOS.usage(state)
		local free = CeroSecOS.MAX_TOTAL_BYTES - used - 8
		if free <= 0 then break end
		if free > CeroSecOS.MAX_FILE_BYTES then free = CeroSecOS.MAX_FILE_BYTES end
		filler = filler + 1
		ok(state, rootSession, "touch /f" .. filler, {})
		CeroSecOS.setData(state, rootSession, "/f" .. filler, string.rep("x", free))
	end
	local held = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data
	local users, order = CeroSecOS.readUsers(state)
	local done, reason = CeroSecOS.writePasswd(state, users, order, "bob",
		CeroSecOS.hashPassword("x", "abcdef") .. string.rep("z", 100))
	eq("a rewrite that does not fit is refused", done, nil)
	eq("and says why", reason, "disk full")
	eq("and the file is exactly as it was",
		CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data, held)
	check("so bob still logs in with what he had", holds(state, "bob", "newpw"))
	check("and root does too", holds(state, "root", ""))
end

--
-- 19. /etc/hostname: the file is the name.
--

do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")

	ok(state, admin, "hostname", { "ksp-front-01" })
	bad(state, admin, "hostname other", "hostname: permission denied")
	eq("and nothing was written", CeroSecOS.hostname(state), "ksp-front-01")

	ok(state, rootSession, "hostname ksp-back-02", {})
	ok(state, admin, "hostname", { "ksp-back-02" })
	ok(state, admin, "cat /etc/hostname", { "ksp-back-02" })
	eq("the state's own copy follows", state.hostname, "ksp-back-02")
	eq("and the state still validates", CeroSecOS.validate(state), true)

	-- Every way a name can be wrong.
	local badNames = {
		"", "-lead", "Upper", "has space", "under_score", "dot.ted",
		string.rep("a", CeroSecOS.HOSTNAME_MAX + 1),
	}
	for i = 1, #badNames do
		eq("`" .. badNames[i] .. "` is not a hostname", CeroSecOS.isValidHostname(badNames[i]), false)
	end
	eq("sixteen characters is a hostname",
		CeroSecOS.isValidHostname(string.rep("a", CeroSecOS.HOSTNAME_MAX)), true)
	eq("one character is a hostname", CeroSecOS.isValidHostname("a"), true)
	eq("digits and dashes are a hostname", CeroSecOS.isValidHostname("ksp-4rw-44z"), true)

	bad(state, rootSession, "hostname Upper", "hostname: Upper: invalid name")
	bad(state, rootSession, "hostname -x", "hostname: -x: invalid name")
	eq("and none of them landed", CeroSecOS.hostname(state), "ksp-back-02")

	-- Written by hand: the file is what the machine answers with.
	ok(state, rootSession, 'write /etc/hostname "byhand"', {})
	ok(state, admin, "hostname", { "byhand" })

	-- A file that does not hold a name falls back to the state's copy rather
	-- than leaving the machine nameless.
	ok(state, rootSession, 'write /etc/hostname "NOT A NAME"', {})
	eq("nonsense in the file falls back", CeroSecOS.hostname(state), "ksp-back-02")
	ok(state, rootSession, "rm /etc/hostname", {})
	eq("no file at all falls back too", CeroSecOS.hostname(state), "ksp-back-02")
	eq("and with no state either, the default",
		CeroSecOS.hostname(nil), CeroSecOS.DEFAULT_HOSTNAME)

	-- Blanks around the name are not part of it; blanks inside it are not a
	-- name at all.
	local spaced = fresh()
	CeroSecOS.systemNode(spaced, CeroSecOS.HOSTNAME_PATH).data = "  spaced  "
	eq("the name is trimmed", CeroSecOS.hostname(spaced), "spaced")
	CeroSecOS.systemNode(spaced, CeroSecOS.HOSTNAME_PATH).data = "two words"
	eq("two words are not a name", CeroSecOS.hostname(spaced), "ksp-front-01")
end

--
-- 20. restoreSystem: what the BIOS puts back, and what it must never touch.
--

do
	local state = fresh()
	local rootSession = open(state, "root")

	-- A machine somebody lived on, and then wiped.
	ok(state, rootSession, "mkdir /home/admin/work", {})
	ok(state, rootSession, 'write /home/admin/work/notes.txt "keep me"', {})
	ok(state, rootSession, "hostname ksp-mine", {})
	eq("the root password is changed", CeroSecOS.setPassword(state, "root", "hunter2"), true)
	ok(state, rootSession, "rm -r /bin", {})
	eq("nothing to boot", CeroSecOS.systemOk(state), false)

	eq("the repair reports success", CeroSecOS.restoreSystem(state), true)
	eq("the machine boots again", CeroSecOS.systemOk(state), true)
	eq("and validates", CeroSecOS.validate(state), true)

	-- What was there is still there.
	local kept = CeroSecOS.systemNode(state, "/home/admin/work/notes.txt")
	check("a file in /home survived", kept ~= nil)
	eq("with its contents", kept.data, "keep me")
	eq("the name survived", CeroSecOS.hostname(state), "ksp-mine")
	check("and the root password survived", holds(state, "root", "hunter2"))
	check("the empty one does not work", not holds(state, "root", ""))

	-- The commands are back, all of them, and runnable.
	local names = CeroSecOS.binNames()
	local bin = CeroSecOS.systemNode(state, "/bin")
	eq("every command is back", CeroSecOS.countEntries(bin), #names)
	local session = open(state, "root", "hunter2")
	ok(state, session, "pwd", { "/root" })

	-- Twice changes nothing.
	local before = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data
	local nodes, bytes = CeroSecOS.usage(state)
	eq("a second repair reports success", CeroSecOS.restoreSystem(state), true)
	local nodes2, bytes2 = CeroSecOS.usage(state)
	eq("the same nodes", nodes2, nodes)
	eq("the same bytes", bytes2, bytes)
	eq("and the same accounts", CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data, before)
end

do
	-- A machine with no accounts left gets the two it shipped with, and only
	-- then: a file that still parses is never replaced.
	local state = fresh()
	CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data = "rubbish"
	CeroSecOS.restoreSystem(state)
	check("the default accounts are back", CeroSecOS.getUser(state, "root") ~= nil)
	check("both of them", CeroSecOS.getUser(state, "admin") ~= nil)
	check("and they ship open", holds(state, "root", ""))
	eq("the file is root's", CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).owner, "root")
	eq("and closed to everybody else",
		CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).mode, CeroSecOS.PASSWD_MODE)

	-- A file with one hand-written account in it is kept exactly as it is.
	local mine = fresh()
	local line = "bob:" .. CeroSecOS.hashPassword("x", "abcdef") .. ":/:admin"
	CeroSecOS.systemNode(mine, CeroSecOS.PASSWD_PATH).data = line
	CeroSecOS.restoreSystem(mine)
	eq("the file is kept", CeroSecOS.systemNode(mine, CeroSecOS.PASSWD_PATH).data, line)
	eq("root is not put back on it", CeroSecOS.getUser(mine, "root"), nil)
end

do
	-- The repair is authoritative for the executables and for nothing else: an
	-- executable somebody shut is opened again, and a file of his own in /bin
	-- is left where it is.
	local state = fresh()
	local rootSession = open(state, "root")
	ok(state, rootSession, "chmod 000 /bin/ls", {})
	ok(state, rootSession, 'write /bin/mine "not ours"', {})
	ok(state, rootSession, "chown admin /bin/ls", {})

	CeroSecOS.restoreSystem(state)
	local ls = CeroSecOS.systemNode(state, "/bin/ls")
	eq("the executable is open again", ls.mode, 755)
	eq("and root's again", ls.owner, "root")
	eq("with its description", ls.data, CeroSecOS.commandDesc("ls"))
	local mine = CeroSecOS.systemNode(state, "/bin/mine")
	check("a file of his own is still there", mine ~= nil)
	eq("untouched", mine.data, "not ours")

	-- Nothing at all to work with, and nothing thrown.
	eq("no state, no repair", CeroSecOS.restoreSystem(nil), nil)
	eq("junk, no repair", CeroSecOS.restoreSystem("x"), nil)

	-- A machine whose whole tree is gone is rebuilt from nothing, and the
	-- /etc and /bin it gets are a machine that boots.
	local wiped = fresh()
	wiped.fs = nil
	CeroSecOS.restoreSystem(wiped)
	eq("a wiped machine boots", CeroSecOS.systemOk(wiped), true)
	eq("and validates", CeroSecOS.validate(wiped), true)
	check("and somebody can log in", CeroSecOS.login(wiped, "root", "") ~= nil)
end

--
-- 21. shutdown and reboot: an order, and root's alone.
--

do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")

	-- The order goes out of band, with nothing on the screen: the machine
	-- going dark is what the player sees, and a line of text is not it.
	ok(state, rootSession, "shutdown", {}, "shutdown")
	ok(state, rootSession, "reboot", {}, "reboot")
	eq("restart is reboot under its other name",
		select(3, CeroSecOS.exec(state, rootSession, "restart")), "reboot")

	-- Root's alone, and each refusal wears the name that was typed.
	bad(state, admin, "shutdown", "shutdown: permission denied")
	bad(state, admin, "reboot", "reboot: permission denied")
	bad(state, admin, "restart", "restart: permission denied")

	-- No arguments, and the usage says the name that was typed too.
	bad(state, rootSession, "shutdown now", "shutdown: usage: shutdown")
	bad(state, rootSession, "reboot -f", "reboot: usage: reboot")
	bad(state, rootSession, "restart now", "restart: usage: restart")

	-- Executables like every other command: taking the file away takes the
	-- order away, and the machine cannot be talked into going down by a name.
	ok(state, rootSession, "rm /bin/shutdown", {})
	bad(state, rootSession, "shutdown", "shutdown: command not found")
	eq("and reboot is untouched",
		select(3, CeroSecOS.exec(state, rootSession, "reboot")), "reboot")

	-- Nothing on the disk moved: the core has no machine to switch off.
	eq("the state still validates", CeroSecOS.validate(state), true)
end

--
-- 22. /etc/sudoers: the format and the parser.
--

do
	eq("a bare name", CeroSecOS.parseSudoersLine("admin").name, "admin")
	eq("and it is asked for a password", CeroSecOS.parseSudoersLine("admin").nopasswd, false)
	eq("NOPASSWD", CeroSecOS.parseSudoersLine("kate NOPASSWD").nopasswd, true)
	eq("blanks around it are not part of it",
		CeroSecOS.parseSudoersLine("  \tkate\tNOPASSWD  ").name, "kate")

	eq("a blank line is nothing", CeroSecOS.parseSudoersLine(""), nil)
	eq("blanks are nothing", CeroSecOS.parseSudoersLine("   "), nil)
	eq("a comment is nothing", CeroSecOS.parseSudoersLine("# admin"), nil)
	eq("an indented comment too", CeroSecOS.parseSudoersLine("   # admin"), nil)
	eq("a name that could not be a name is skipped",
		CeroSecOS.parseSudoersLine("-admin"), nil)
	eq("nor can a line with a colon in it",
		CeroSecOS.parseSudoersLine("admin:x"), nil)
	eq("a word that is not NOPASSWD is skipped", CeroSecOS.parseSudoersLine("admin ALL"), nil)
	eq("lower case is not the flag", CeroSecOS.parseSudoersLine("admin nopasswd"), nil)
	eq("three words are not a line", CeroSecOS.parseSudoersLine("admin NOPASSWD ALL"), nil)
	eq("not a string", CeroSecOS.parseSudoersLine(nil), nil)

	local entries, order = CeroSecOS.parseSudoers(
		"# who may\n\nadmin\nkate NOPASSWD\n-admin\nadmin NOPASSWD\n")
	eq("three lines parsed, two names", #order, 2)
	eq("in the order the file has them", order[1], "admin")
	eq("and the second", order[2], "kate")
	eq("a name that appears twice keeps its first line", entries.admin.nopasswd, false)
	eq("kate is passwordless", entries.kate.nopasswd, true)

	-- The file is the list: a rewrite is seen at once, and no cache survives it.
	local state = fresh()
	eq("admin ships listed", CeroSecOS.sudoer(state, "admin").name, "admin")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "kate NOPASSWD")
	eq("admin is off the list the moment the file says so",
		CeroSecOS.sudoer(state, "admin"), nil)
	eq("and kate is on it", CeroSecOS.sudoer(state, "kate").nopasswd, true)

	-- A machine with no sudoers file at all is a machine where nobody may sudo.
	local bare = fresh()
	CeroSecOS.systemNode(bare, CeroSecOS.ETC_PATH).children.sudoers = nil
	eq("no file, nobody listed", CeroSecOS.sudoer(bare, "admin"), nil)

	-- It is root's, and read-only even to him without meaning it: 440.
	local node = CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH)
	eq("owner", node.owner, "root")
	eq("mode", node.mode, CeroSecOS.SUDOERS_MODE)
	local adminSession = open(state, "admin")
	bad(state, adminSession, "cat /etc/sudoers", "cat: /etc/sudoers: permission denied")
end

--
-- 23. sudo: every path, and the exact line each one says.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local rootSession = open(state, "root")

	bad(state, admin, "sudo", "sudo: usage: sudo <command> [args]")

	-- Root is already root, and no file is consulted: an /etc/sudoers with
	-- nobody in it must not take sudo from the one account that can put it back.
	ok(state, rootSession, "sudo whoami", { "root" })

	-- Listed with a password: the question, and nothing on the screen with it.
	local asked = run(state, admin, "sudo whoami")
	eq("sudo asks", asked.control, "prompt")
	eq("it says nothing while it asks", #asked.lines, 0)
	eq("the prompt names the account", asked.data.text, "[sudo] password for admin: ")
	eq("and is masked", asked.data.mask, true)
	eq("the token names its command", asked.data.cont.cmd, "sudo")
	eq("and the account it was issued for", asked.data.cont.user, "admin")
	-- Nothing of the password is in the token, not even a hash: what is in it is
	-- the command that was typed.
	eq("no password material in the token", asked.data.cont.passwd, nil)
	eq("nor a hash of one", asked.data.cont.want, nil)
	eq("the command is", asked.data.cont.args[1], "whoami")

	-- The wrong password: one line, one attempt, and back to the shell.
	says(answer(state, admin, asked.data.cont, "wrong"), "sudo: authentication failure")
	eq("and the wrong answer is refused", answer(state, admin, asked.data.cont, "wrong").ok, false)

	-- The right one runs it as root.
	local ran = answer(state, admin, asked.data.cont, "")
	eq("it succeeds", ran.ok, true)
	eq("as root", ran.lines[1], "root")
	eq("and orders nothing", ran.control, nil)

	-- The console's own session is untouched by any of it.
	eq("still admin", admin.user, "admin")
	eq("still where he was", admin.cwd, "/home/admin")
	local moved = run(state, admin, "sudo cd /root")
	eq("sudo cd succeeds", moved.control, "prompt")
	answer(state, admin, moved.data.cont, "")
	eq("and moves nobody", admin.cwd, "/home/admin")

	-- What sudo is for: a file admin cannot read.
	bad(state, admin, "cat /etc/passwd", "cat: /etc/passwd: permission denied")
	local catted = answer(state, admin, run(state, admin, "sudo cat /etc/passwd").data.cont, "")
	eq("sudo cat /etc/passwd succeeds", catted.ok, true)
	check("and prints the file", string.find(catted.lines[1], "root:$cs1$", 1, true) == 1)

	-- Not in the file. Real sudo's line, and it does not start with "sudo:".
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "# nobody")
	bad(state, admin, "sudo ls", "admin is not in the sudoers file.")

	-- NOPASSWD runs it there and then.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin NOPASSWD")
	ok(state, admin, "sudo whoami", { "root" })
	-- Nested sudo is one sudo.
	ok(state, admin, "sudo sudo sudo whoami", { "root" })
	bad(state, admin, "sudo sudo", "sudo: usage: sudo <command> [args]")

	-- A command that is not one, and one whose executable is gone: sudo says
	-- what the shell would say, under the command's own name.
	bad(state, admin, "sudo nosuch", "nosuch: command not found")
	ok(state, rootSession, "rm /bin/ls", {})
	bad(state, admin, "sudo ls", "ls: command not found")
	CeroSecOS.restoreSystem(state)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin NOPASSWD")

	-- Root walks through a mode admin cannot: that is the whole point.
	ok(state, rootSession, "chmod 700 /bin/ls", {})
	bad(state, admin, "ls /", "ls: permission denied")
	local listed = run(state, admin, "sudo ls /")
	eq("sudo ls runs", listed.ok, true)
	eq("and lists", listed.lines[1], "bin   dev   etc   home  root")
	ok(state, rootSession, "chmod 755 /bin/ls", {})

	-- The two orders come back out of sudo untouched.
	eq("sudo shutdown", select(3, CeroSecOS.exec(state, admin, "sudo shutdown")), "shutdown")
	eq("sudo reboot", select(3, CeroSecOS.exec(state, admin, "sudo reboot")), "reboot")
end

-- A token is not an authorisation on its own.
do
	local state = fresh()
	local admin = open(state, "admin")
	addUser(state, "kate", "", "/home/kate", false)
	local kate = open(state, "kate")

	local asked = run(state, admin, "sudo whoami")
	-- Answered by somebody else -- a chain left behind by a session that logged
	-- out, and a name that is not in the file either.
	says(answer(state, kate, asked.data.cont, ""), "sudo: authentication failure")
	-- Taken off the list between the question and the answer.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "# nobody")
	says(answer(state, admin, asked.data.cont, ""), "admin is not in the sudoers file.")
	-- A token with a command that is not a table of strings.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin")
	says(answer(state, admin, { cmd = "sudo", user = "admin", args = "ls" }, ""),
		"sudo: authentication failure")
	says(answer(state, admin, { cmd = "sudo", user = "admin", args = { 7 } }, ""),
		"sudo: authentication failure")
end

-- sudo + passwd: the whole chain runs as root, and the console does not.
do
	local state = fresh()
	local admin = open(state, "admin")
	eq("admin may not touch root's password",
		run(state, admin, "passwd root").lines[1], "passwd: permission denied")

	local gate = run(state, admin, "sudo passwd root")
	eq("sudo asks for admin's password first", gate.data.text, "[sudo] password for admin: ")
	-- Root is asked for nobody's old password, its own included: the chain that
	-- comes back is root's chain and not admin's.
	local new = answer(state, admin, gate.data.cont, "")
	eq("and then passwd asks as root", new.data.text, "New password: ")
	eq("the token carries the authority the chain was given", new.data.cont.as, "root")
	local retype = answer(state, admin, new.data.cont, "hunter2")
	eq("the retype is still root's", retype.data.text, "Retype new password: ")
	eq("and still carries it", retype.data.cont.as, "root")
	says(answer(state, admin, retype.data.cont, "hunter2"), "passwd: password updated")

	check("root's password is the one that was typed", holds(state, "root", "hunter2"))
	check("and the empty one no longer gets in", not holds(state, "root", ""))
	eq("the console is still admin's", admin.user, "admin")
	eq("and still where it was", admin.cwd, "/home/admin")

	-- A token that says "as" without a sudo behind it is exactly as strong as
	-- the one thing that writes it, which is sudo: this is what a forged
	-- console would carry, and it is a decision made on the server's own state.
	eq("continue runs a marked chain as the name on it",
		answer(state, admin, { cmd = "passwd", step = "new", user = "root", as = "root" },
			"x").control, "prompt")
end

-- sudo + edit: the buffer is opened as root, so the save is root's.
do
	local state = fresh()
	local admin = open(state, "admin")

	local mine = run(state, admin, "edit /etc/motd")
	eq("admin opens /etc/motd", mine.control, "edit")
	eq("as himself", mine.data.user, "admin")
	eq("read-only", mine.data.readonly, true)

	local opened = answer(state, admin, run(state, admin, "sudo edit /etc/motd").data.cont, "")
	eq("sudo opens the same file", opened.control, "edit")
	eq("as root", opened.data.user, "root")
	eq("and writable", opened.data.readonly, false)
	eq("at the same path", opened.data.path, "/etc/motd")

	-- A file that is not there yet, in a directory admin cannot write.
	local made = answer(state, admin, run(state, admin, "sudo edit /root/notes.txt").data.cont, "")
	eq("a new file under /root opens", made.control, "edit")
	eq("as root", made.data.user, "root")
	eq("empty", made.data.text, "")
	bad(state, admin, "edit /root/notes.txt", "edit: /root/notes.txt: permission denied")
end

-- The repair, and /etc/sudoers.
do
	local state = fresh()

	-- A list somebody wrote is kept, exactly as the accounts are.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "kate NOPASSWD")
	CeroSecOS.restoreSystem(state)
	eq("a sudoers that still names somebody is kept",
		CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH).data, "kate NOPASSWD")

	-- One that names nobody is not a list.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "rubbish line here")
	CeroSecOS.restoreSystem(state)
	local node = CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH)
	eq("an unparseable one is written back", node.data, CeroSecOS.defaultSudoers())
	eq("root's", node.owner, "root")
	eq("440", node.mode, CeroSecOS.SUDOERS_MODE)
	eq("and admin is on it again", CeroSecOS.sudoer(state, "admin").name, "admin")

	-- A missing one is written back too, and the repair stays idempotent.
	CeroSecOS.systemNode(state, CeroSecOS.ETC_PATH).children.sudoers = nil
	CeroSecOS.restoreSystem(state)
	eq("a missing one comes back",
		CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH).data, CeroSecOS.defaultSudoers())
	local before = CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH)
	CeroSecOS.restoreSystem(state)
	eq("and a second repair changes nothing",
		CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH).data, before.data)

	-- A machine with no sudoers file still boots: who may sudo is not what
	-- makes a machine an operating system.
	CeroSecOS.systemNode(state, CeroSecOS.ETC_PATH).children.sudoers = nil
	eq("no sudoers, still a system", CeroSecOS.systemOk(state), true)
	eq("and still valid", CeroSecOS.validate(state), true)
end

--
-- 24. upgradeSystem: an older machine topped up, once, and never again.
--

-- A machine as rung 2c left it: no system version, none of the executables that
-- wave added, no /etc/sudoers -- and a command its owner deleted on purpose.
local function rung2cState()
	local state = fresh()
	state.sysv = nil
	local bin = state.fs.children.bin
	bin.children.sudo = nil
	bin.children.shutdown = nil
	bin.children.reboot = nil
	bin.children.restart = nil
	bin.children.cat = nil
	state.fs.children.etc.children.sudoers = nil
	state.fs.children.home.children.admin.children =
		{ ["notes.txt"] = CeroSecOS.newFile("admin", 644, "keep me") }
	return state
end

do
	local state = rung2cState()
	eq("as it stands, the core will not run on it", CeroSecOS.validate(state), false)

	eq("the upgrade says it did something", CeroSecOS.upgradeSystem(state), true)
	eq("and the machine is at this build's contents", state.sysv, CeroSecOS.SYSTEM_VERSION)
	eq("it validates now", CeroSecOS.validate(state), true)

	-- Every standard executable is back, this wave's four included.
	local names = CeroSecOS.binNames()
	for i = 1, #names do
		local node = state.fs.children.bin.children[names[i]]
		check("/bin/" .. names[i] .. " is there", node ~= nil)
		eq("/bin/" .. names[i] .. " is root's", node.owner, "root")
		eq("/bin/" .. names[i] .. " is 755", node.mode, 755)
		eq("/bin/" .. names[i] .. " describes itself", node.data, CeroSecOS.commandDesc(names[i]))
	end
	check("sudo among them", state.fs.children.bin.children.sudo ~= nil)
	check("shutdown too", state.fs.children.bin.children.shutdown ~= nil)
	check("reboot too", state.fs.children.bin.children.reboot ~= nil)
	check("restart too", state.fs.children.bin.children.restart ~= nil)
	-- A machine behind on its contents is topped up whole: there is no telling
	-- a command deleted last week from one this build added, so `cat` comes
	-- back too. It is the LAST time that happens to this machine.
	check("and cat, which its owner had deleted", state.fs.children.bin.children.cat ~= nil)

	local sudoers = state.fs.children.etc.children.sudoers
	check("/etc/sudoers was written", sudoers ~= nil)
	eq("root's", sudoers.owner, "root")
	eq("440", sudoers.mode, CeroSecOS.SUDOERS_MODE)
	eq("with the shipped list", sudoers.data, CeroSecOS.defaultSudoers())
	eq("so admin may sudo again", CeroSecOS.sudoer(state, "admin").name, "admin")

	-- Nothing else was touched.
	eq("what was in /home is still there",
		state.fs.children.home.children.admin.children["notes.txt"].data, "keep me")
	eq("and the accounts are the ones that were on the disk",
		CeroSecOS.hasUsers(state), true)

	-- Idempotent, and inert from here on.
	eq("a second pass has nothing to do", CeroSecOS.upgradeSystem(state), false)
	state.fs.children.bin.children.ls = nil
	eq("still nothing to do", CeroSecOS.upgradeSystem(state), false)
	eq("and the deletion stands", state.fs.children.bin.children.ls, nil)
end

-- At this build's contents, nothing is ever seeded: root's deletions are root's.
do
	local state = fresh()
	eq("a fresh machine is already current", state.sysv, CeroSecOS.SYSTEM_VERSION)
	local rootSession = open(state, "root")
	ok(state, rootSession, "rm /bin/ls", {})
	eq("the upgrade does nothing", CeroSecOS.upgradeSystem(state), false)
	eq("ls stays deleted", state.fs.children.bin.children.ls, nil)
	bad(state, rootSession, "ls /", "ls: command not found")
	-- Through the load path too, which is where it would bite.
	CeroSecOS.migrate(state, "ksp-front-01")
	eq("and stays deleted across a load", state.fs.children.bin.children.ls, nil)
end

-- The upgrade fills gaps; it never replaces what is at a name.
do
	local state = rung2cState()
	state.fs.children.bin.children.sudo = CeroSecOS.newDir("admin", 755)
	state.fs.children.bin.children.mine = CeroSecOS.newFile("admin", 644, "not ours")
	state.fs.children.etc.children.sudoers =
		CeroSecOS.newFile("root", 440, "not a sudoers line at all")

	CeroSecOS.upgradeSystem(state)
	eq("a directory sitting on the name is left alone",
		state.fs.children.bin.children.sudo.type, "dir")
	eq("and it is still its owner's", state.fs.children.bin.children.sudo.owner, "admin")
	eq("a file of your own in /bin is untouched",
		state.fs.children.bin.children.mine.data, "not ours")
	-- A sudoers that is there but says nothing is NOT the upgrade's business:
	-- filling a gap and repairing a file are two different gestures, and the
	-- second one is the BIOS'.
	eq("an unparseable sudoers is left where it is",
		state.fs.children.etc.children.sudoers.data, "not a sudoers line at all")
	eq("but the number moved, so it is asked once and once only",
		state.sysv, CeroSecOS.SYSTEM_VERSION)
	-- And the BIOS is what puts that one right.
	CeroSecOS.restoreSystem(state)
	eq("the repair rewrites it",
		state.fs.children.etc.children.sudoers.data, CeroSecOS.defaultSudoers())
	eq("and the executable is an executable again",
		state.fs.children.bin.children.sudo.type, "file")
end

-- Nothing to work with, and nothing thrown.
do
	eq("no state, no upgrade", CeroSecOS.upgradeSystem(nil), false)
	eq("junk, no upgrade", CeroSecOS.upgradeSystem("x"), false)
	local noBin = rung2cState()
	noBin.fs.children.bin = nil
	noBin.fs.children.etc = nil
	eq("a machine with no /bin and no /etc is still numbered",
		CeroSecOS.upgradeSystem(noBin), true)
	eq("at this build", noBin.sysv, CeroSecOS.SYSTEM_VERSION)
	-- It is not bootable, and that is the BIOS' business and not the upgrade's.
	eq("and the boot check says so", CeroSecOS.systemOk(noBin), false)
end

-- The repair leaves a machine at this build's contents.
do
	local state = rung2cState()
	CeroSecOS.restoreSystem(state)
	eq("a repaired machine is current", state.sysv, CeroSecOS.SYSTEM_VERSION)
	eq("so the upgrade has nothing left to do", CeroSecOS.upgradeSystem(state), false)
	eq("and it validates", CeroSecOS.validate(state), true)
end

-- The whole load path, on a machine as rung 2c left it: it boots, and sudo works.
do
	local state = CeroSecOS.migrate(rung2cState(), "ksp-front-01")
	eq("it is the machine that was there, not a new one",
		state.fs.children.home.children.admin.children["notes.txt"].data, "keep me")
	eq("it boots", CeroSecOS.systemOk(state), true)
	local admin = open(state, "admin")
	ok(state, admin, "sudo whoami", nil, "prompt")
	local asked = run(state, admin, "sudo whoami")
	eq("sudo asks for a password on it", asked.data.text, "[sudo] password for admin: ")
	eq("and runs", answer(state, admin, asked.data.cont, "").lines[1], "root")
	eq("shutdown is there for root", select(3,
		CeroSecOS.exec(state, open(state, "root"), "shutdown")), "shutdown")
end

--
-- 20. The clock, the columns, the disk and the text tools (rung 2e).
--

-- Everything below runs on a FIXED clock, handed in the way the server hands
-- the game's: one number in env.now and nothing else. A test that read a real
-- clock would be a test that passes today and fails in July.
local FIXED = CeroSecOS.timeFromParts(1993, 7, 8, 14, 32, 0)
local ENV = { now = FIXED }
-- A second moment, an hour later, for telling "was stamped" from "was already
-- stamped": a mutation that does nothing would still look right against one.
local LATER = FIXED + 3600
local ENV2 = { now = LATER }

-- The same shape as ok()/bad() above, with a clock in it.
local function runAt(state, session, line, env)
	local execOk, lines, control, data = CeroSecOS.exec(state, session, line, env)
	for i = 1, #lines do
		check("`" .. line .. "` line " .. i .. " fits 60 columns", #lines[i] <= CeroSecOS.COLS)
	end
	return { ok = execOk, lines = lines, control = control, data = data }
end

local function okAt(state, session, line, wantLines, env)
	local r = runAt(state, session, line, env or ENV)
	eq("`" .. line .. "` ok", r.ok, true)
	if wantLines ~= nil then
		eq("`" .. line .. "` line count", #r.lines, #wantLines)
		for i = 1, #wantLines do eq("`" .. line .. "` line " .. i, r.lines[i], wantLines[i]) end
	end
	return r.lines
end

local function badAt(state, session, line, wantLine, env)
	local r = runAt(state, session, line, env or ENV)
	eq("`" .. line .. "` refused", r.ok, false)
	eq("`" .. line .. "` line count", #r.lines, 1)
	eq("`" .. line .. "` says", r.lines[1], wantLine)
end

-- 20a. The arithmetic. A calendar in, the same calendar out.
do
	eq("the fixed moment prints", CeroSecOS.formatDate(FIXED), "Thu Jul  8 14:32:00 1993")
	eq("and in the ls -l column", CeroSecOS.formatStamp(FIXED), "Jul  8 14:32")
	eq("the ls -l column is 12 wide, always", #CeroSecOS.formatStamp(FIXED), 12)
	eq("and 12 wide on a two-digit day",
		#CeroSecOS.formatStamp(CeroSecOS.timeFromParts(1993, 12, 25, 0, 5, 0)), 12)
	eq("a two-digit day", CeroSecOS.formatStamp(CeroSecOS.timeFromParts(1993, 12, 25, 0, 5, 0)),
		"Dec 25 00:05")

	-- 0 is a real moment and not a blank: it is what an unstamped node prints.
	eq("zero is the epoch", CeroSecOS.formatDate(0), "Thu Jan  1 00:00:00 1970")
	eq("and in the column", CeroSecOS.formatStamp(0), "Jan  1 00:00")

	-- Round trip, on the corners a civil-calendar conversion gets wrong: the
	-- leap day, the last second of a year, a century that is not a leap year
	-- and one that is.
	local corners = {
		{ 1970, 1, 1, 0, 0, 0 }, { 1993, 7, 8, 14, 32, 0 }, { 1992, 2, 29, 12, 0, 0 },
		{ 1993, 12, 31, 23, 59, 59 }, { 1900, 3, 1, 0, 0, 0 }, { 2000, 2, 29, 6, 30, 0 },
		{ 2038, 1, 19, 3, 14, 7 },
	}
	for i = 1, #corners do
		local c = corners[i]
		local t = CeroSecOS.timeFromParts(c[1], c[2], c[3], c[4], c[5], c[6])
		local back = CeroSecOS.dateParts(t)
		eq("round trip " .. i .. " year", back.year, c[1])
		eq("round trip " .. i .. " month", back.month, c[2])
		eq("round trip " .. i .. " day", back.day, c[3])
		eq("round trip " .. i .. " hour", back.hour, c[4])
		eq("round trip " .. i .. " minute", back.min, c[5])
		eq("round trip " .. i .. " second", back.sec, c[6])
	end

	-- The days of the week, against dates nobody has to take on trust.
	eq("1969-12-31 was a Wednesday",
		CeroSecOS.formatDate(CeroSecOS.timeFromParts(1969, 12, 31, 0, 0, 0)),
		"Wed Dec 31 00:00:00 1969")
	eq("2000-01-01 was a Saturday",
		CeroSecOS.formatDate(CeroSecOS.timeFromParts(2000, 1, 1, 0, 0, 0)),
		"Sat Jan  1 00:00:00 2000")
	eq("2026-09-10 is a Thursday",
		CeroSecOS.formatDate(CeroSecOS.timeFromParts(2026, 9, 10, 9, 5, 0)),
		"Thu Sep 10 09:05:00 2026")
	-- A day is 86400 seconds and the name of the day moves with it, all seven.
	local start = CeroSecOS.timeFromParts(1993, 7, 4, 0, 0, 0)
	local wanted = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
	for i = 1, 7 do
		eq("day " .. i .. " of the week",
			string.sub(CeroSecOS.formatDate(start + (i - 1) * 86400), 1, 3), wanted[i])
	end

	-- What a clock is, and what it is not.
	eq("a number is a clock", CeroSecOS.clockOf({ now = 5 }), 5)
	eq("a fraction is cut to the second", CeroSecOS.clockOf({ now = 5.7 }), 5)
	eq("no env, no clock", CeroSecOS.clockOf(nil), nil)
	eq("an empty env, no clock", CeroSecOS.clockOf({}), nil)
	eq("a string is not a clock", CeroSecOS.clockOf({ now = "1993" }), nil)
	eq("junk is not a clock", CeroSecOS.clockOf("later"), nil)
	eq("an unstamped node is at zero", CeroSecOS.mtimeOf(CeroSecOS.newFile("root", 644, "")), 0)
	eq("and so is a nil", CeroSecOS.mtimeOf(nil), 0)
end

-- 20b. date.
do
	local state = fresh()
	local admin = open(state, "admin")
	okAt(state, admin, "date", { "Thu Jul  8 14:32:00 1993" })
	-- No env at all is the machine with no clock, and it says so rather than
	-- printing the epoch as if it were the hour.
	local r = runAt(state, admin, "date", nil)
	eq("no clock refused", r.ok, false)
	eq("no clock says so", r.lines[1], "date: no clock")
	local junk = runAt(state, admin, "date", { now = "half past" })
	eq("a clock that is not one is no clock", junk.lines[1], "date: no clock")
	-- An argument that is not a format at all: a date is READ off this machine,
	-- never set on it, so "date now" is a wrong line and not a clock change.
	badAt(state, admin, "date now", "date: usage: date [+FORMAT]")
	badAt(state, admin, "date +%s +%s", "date: usage: date [+FORMAT]")
end

-- 20b2. date +FORMAT: the pieces, and the number underneath them.
do
	local state = fresh()
	local admin = open(state, "admin")

	-- The one a script is really after: the clock itself, as an integer.
	okAt(state, admin, "date +%s", { "742141920" })
	eq("and it is the number the env carried", tostring(FIXED), "742141920")

	-- Every code, one at a time, on Thursday the 8th of July 1993 at 14:32:00.
	okAt(state, admin, "date +%Y", { "1993" })
	okAt(state, admin, "date +%m", { "07" })
	okAt(state, admin, "date +%d", { "08" })
	-- %d zero-pads and %e blank-pads: that is the whole difference between them.
	okAt(state, admin, "date +%e", { " 8" })
	okAt(state, admin, "date +%H", { "14" })
	okAt(state, admin, "date +%M", { "32" })
	okAt(state, admin, "date +%S", { "00" })
	okAt(state, admin, "date +%j", { "189" })
	okAt(state, admin, "date +%a", { "Thu" })
	okAt(state, admin, "date +%b", { "Jul" })
	okAt(state, admin, "date +%%", { "%" })

	-- Together, with the text between them kept exactly as typed.
	okAt(state, admin, "date \"+%Y-%m-%d %H:%M:%S\"", { "1993-07-08 14:32:00" })
	okAt(state, admin, "date \"+it is %H:%M on %a\"", { "it is 14:32 on Thu" })
	okAt(state, admin, "date +", { "" })

	-- A code this machine does not have is copied out as it was typed, "%" and
	-- all -- including a "%" at the very end of the format, which has no code
	-- after it at all.
	okAt(state, admin, "date +%q", { "%q" })
	okAt(state, admin, "date +%", { "%" })
	okAt(state, admin, "date +%Y%q%m", { "1993%q07" })

	-- The other end of the year, where the padding is what is being asked
	-- about: the first of January is day 001 and the 31st of December is 366 in
	-- a leap year.
	local newYear = { now = CeroSecOS.timeFromParts(1996, 1, 1, 9, 5, 4) }
	okAt(state, admin, "date \"+%Y-%m-%d %H:%M:%S %j [%e]\"",
		{ "1996-01-01 09:05:04 001 [ 1]" }, newYear)
	local endOfLeap = { now = CeroSecOS.timeFromParts(1996, 12, 31, 23, 59, 59) }
	okAt(state, admin, "date +%j", { "366" }, endOfLeap)
	okAt(state, admin, "date +%a", { "Tue" }, endOfLeap)

	-- No clock is no clock, format or not.
	local r = runAt(state, admin, "date +%s", nil)
	eq("no clock refused", r.ok, false)
	eq("and says so", r.lines[1], "date: no clock")

	-- The round trip that makes %s worth having: the number it prints is the
	-- number the filesystem stamps a file with at that same moment.
	okAt(state, admin, "touch stamped.txt", {})
	local node = CeroSecOS.systemNode(state, "/home/admin/stamped.txt")
	eq("the file carries the clock", tostring(CeroSecOS.mtimeOf(node)),
		okAt(state, admin, "date +%s", nil)[1])
end

-- 20c. mtime, on every mutation there is.
do
	local state = fresh()
	local admin = open(state, "admin")
	local home = state.fs.children.home.children.admin

	-- A fresh machine has never been touched: nothing on it carries a stamp.
	eq("a shipped node has no mtime", home.mtime, nil)
	eq("which reads as zero", CeroSecOS.mtimeOf(home), 0)

	okAt(state, admin, "touch a.txt", {})
	eq("touch stamps the file", CeroSecOS.mtimeOf(home.children["a.txt"]), FIXED)
	eq("and the directory it landed in", CeroSecOS.mtimeOf(home), FIXED)

	okAt(state, admin, "touch a.txt", {}, ENV2)
	eq("touching it again moves the stamp", CeroSecOS.mtimeOf(home.children["a.txt"]), LATER)
	eq("but not the directory: the listing did not change",
		CeroSecOS.mtimeOf(home), FIXED)

	okAt(state, admin, 'write a.txt "hello"', {})
	eq("a write moves it", CeroSecOS.mtimeOf(home.children["a.txt"]), FIXED)
	okAt(state, admin, "echo more >> a.txt", {}, ENV2)
	eq("an append moves it", CeroSecOS.mtimeOf(home.children["a.txt"]), LATER)
	okAt(state, admin, "echo fresh > b.txt", {})
	eq("a redirect that creates stamps", CeroSecOS.mtimeOf(home.children["b.txt"]), FIXED)

	okAt(state, admin, "mkdir d", {}, ENV2)
	eq("mkdir stamps the directory", CeroSecOS.mtimeOf(home.children.d), LATER)
	eq("and its parent's listing changed", CeroSecOS.mtimeOf(home), LATER)

	okAt(state, admin, "cp a.txt d/c.txt", {})
	eq("a copy is a new file, stamped now", CeroSecOS.mtimeOf(home.children.d.children["c.txt"]), FIXED)
	eq("and the directory it landed in", CeroSecOS.mtimeOf(home.children.d), FIXED)

	okAt(state, admin, "chmod 600 a.txt", {}, ENV2)
	eq("chmod moves it", CeroSecOS.mtimeOf(home.children["a.txt"]), LATER)
	okAt(state, admin, "chmod 644 a.txt", {})
	local rootSession = open(state, "root")
	okAt(state, rootSession, "chown root /home/admin/b.txt", {}, ENV2)
	eq("chown moves it", CeroSecOS.mtimeOf(home.children["b.txt"]), LATER)

	okAt(state, admin, "mv a.txt d/moved.txt", {})
	eq("mv stamps what moved", CeroSecOS.mtimeOf(home.children.d.children["moved.txt"]), FIXED)
	eq("and the listing it left", CeroSecOS.mtimeOf(home), FIXED)
	eq("and the listing it arrived in", CeroSecOS.mtimeOf(home.children.d), FIXED)

	okAt(state, admin, "rm d/c.txt", {}, ENV2)
	eq("rm moves the directory's stamp", CeroSecOS.mtimeOf(home.children.d), LATER)

	-- A machine with no clock mutates exactly as it did before this rung: the
	-- write happens, nothing is stamped, and nothing already stamped moves.
	local was = CeroSecOS.mtimeOf(home.children.d.children["moved.txt"])
	local r = CeroSecOS.exec(state, admin, 'write d/moved.txt "no clock here"', nil)
	eq("the write still happens", r, true)
	eq("and leaves the stamp where it was",
		CeroSecOS.mtimeOf(home.children.d.children["moved.txt"]), was)
	eq("the data did change", home.children.d.children["moved.txt"].data, "no clock here")

	-- A stamp is a write. Somebody who may not write the file may not move it.
	okAt(state, rootSession, "touch /root/his.txt", {})
	badAt(state, admin, "touch /root/his.txt", "touch: /root/his.txt: permission denied")

	eq("and all of it still validates", CeroSecOS.validate(state), true)
end

-- 20d. What the game hands back: nodes with no mtime, and nodes with a bad one.
do
	local state = fresh()
	eq("a machine with no stamps anywhere validates", CeroSecOS.validate(state), true)
	-- One node stamped, the rest not: exactly what a machine looks like the
	-- first time somebody types on it after this build lands.
	state.fs.children.home.children.admin.mtime = FIXED
	eq("half stamped is still valid", CeroSecOS.validate(state), true)

	local admin = open(state, "admin")
	local listed = okAt(state, admin, "ls -l /", nil)
	eq("an unstamped node lists at the epoch",
		string.find(listed[1], "Jan  1 00:00", 1, true) ~= nil, true)

	local bad1 = fresh()
	bad1.fs.children.etc.mtime = "yesterday"
	local vOk, vReason = CeroSecOS.validate(bad1)
	eq("a stamp that is not a number is refused", vOk, false)
	eq("and says which node", vReason, "/etc: bad mtime")
	local bad2 = fresh()
	bad2.fs.children.etc.mtime = 1.5
	eq("half a second is refused", CeroSecOS.validate(bad2), false)
end

-- 20e. ls in columns.
do
	-- The packer, on its own, at the corners.
	eq("nothing packs into nothing", #CeroSecOS.columnize({}, 60), 0)
	local one = CeroSecOS.columnize({ "solo" }, 60)
	eq("one name is one line", #one, 1)
	eq("with no padding after it", one[1], "solo")

	-- Column-major: read DOWN the columns. Six names of 4, so the column is 6
	-- wide and ten fit -- capped at six, one row.
	local six = CeroSecOS.columnize({ "aa", "bb", "cc", "dd", "ee", "ff" }, 60)
	eq("six short names are one row", #six, 1)
	eq("packed across", six[1], "aa  bb  cc  dd  ee  ff")

	-- Names wide enough that only two columns fit: 20 + 2 = 22, and 62 / 22 is
	-- two. Five names, so three rows, and the first column holds the first
	-- three names -- which is what column-major means.
	local wide = {}
	for i = 1, 5 do wide[i] = string.rep("x", 19) .. tostring(i) end
	local packed = CeroSecOS.columnize(wide, 60)
	eq("five wide names make three rows", #packed, 3)
	eq("row 1 is name 1 then name 4", packed[1], wide[1] .. "  " .. wide[4])
	eq("row 2 is name 2 then name 5", packed[2], wide[2] .. "  " .. wide[5])
	eq("row 3 is name 3 alone, no padding", packed[3], wide[3])

	-- Two names that would need 62 columns get one each.
	local tight = CeroSecOS.columnize({ string.rep("y", 30), string.rep("z", 30) }, 60)
	eq("30 + 2 + 30 does not fit 60", #tight, 2)
	eq("first alone", tight[1], string.rep("y", 30))
	-- 29 + 2 + 29 does fit.
	local just = CeroSecOS.columnize({ string.rep("y", 29), string.rep("z", 29) }, 60)
	eq("but 29 + 2 + 29 does", #just, 1)
	eq("exactly 60 columns", #just[1], 60)

	-- A name wider than the screen is cut with a "~" and stands alone.
	local huge = CeroSecOS.columnize({ string.rep("w", 80), "b" }, 60)
	eq("an over-wide name gets a line to itself", #huge, 2)
	eq("cut to the screen", huge[1], string.rep("w", 59) .. "~")
	eq("and it really is 60 wide", #huge[1], 60)
	eq("the other name follows", huge[2], "b")

	-- And through the command.
	local state = fresh()
	local admin = open(state, "admin")
	okAt(state, admin, "ls /", { "bin   dev   etc   home  root" })
	okAt(state, admin, "ls", {})
	okAt(state, admin, "touch only.txt", {})
	okAt(state, admin, "ls", { "only.txt" })
	okAt(state, admin, "mkdir sub", {})
	okAt(state, admin, "ls", { "only.txt  sub" })
	-- -F marks the directories and nothing else.
	okAt(state, admin, "ls -F", { "only.txt  sub/" })
	okAt(state, admin, "ls -F /", { "bin/   dev/   etc/   home/  root/" })
	-- The mark is part of the name, so it is what the column is measured on.
	eq("the marked names are longer", #okAt(state, admin, "ls -F /", nil)[1], 33)
end

-- 20f. ls -l, with a clock and with the flags together.
do
	local state = fresh()
	local admin = open(state, "admin")
	okAt(state, admin, "touch notes.txt", {})
	okAt(state, admin, 'write notes.txt "hello"', {})
	okAt(state, admin, "mkdir sub", {}, ENV2)

	okAt(state, admin, "ls -l", {
		"-rw-r--r--  admin         5  Jul  8 14:32  notes.txt",
		"drwxr-xr-x  admin         0  Jul  8 15:32  sub",
	})
	-- The flags are letters, so every spelling is the same line.
	local want = {
		"-rw-r--r--  admin         5  Jul  8 14:32  notes.txt",
		"drwxr-xr-x  admin         0  Jul  8 15:32  sub/",
	}
	okAt(state, admin, "ls -lF", want)
	okAt(state, admin, "ls -Fl", want)
	okAt(state, admin, "ls -l -F", want)
	okAt(state, admin, "ls -F -l", want)
	-- One bad letter in a run of good ones is still a bad option, and the
	-- refusal names the argument as typed.
	badAt(state, admin, "ls -lz", "ls: -lz: unknown option")
	badAt(state, admin, "ls -zl", "ls: -zl: unknown option")
	badAt(state, admin, "ls -l a b", "ls: usage: ls [-lF] [path]")
end

-- 20g. df, against a state whose numbers are known.
do
	local state = fresh()
	local admin = open(state, "admin")
	local nodes, bytes = CeroSecOS.usage(state)

	local function pct(used, total) return math.ceil(used * 100 / total) end
	local lines = okAt(state, admin, "df", nil)
	eq("df prints three lines", #lines, 3)
	eq("the header", lines[1], "Filesystem   Size   Used  Avail  Use%")
	eq("the disk", lines[2],
		CeroSecOS.padRight("hda", 10) .. "  " .. CeroSecOS.padLeft(tostring(CeroSecOS.DISK_BYTES), 5)
			.. "  " .. CeroSecOS.padLeft(tostring(bytes), 5)
			.. "  " .. CeroSecOS.padLeft(tostring(CeroSecOS.DISK_BYTES - bytes), 5)
			.. "  " .. CeroSecOS.padLeft(tostring(pct(bytes, CeroSecOS.DISK_BYTES)) .. "%", 4))
	eq("the nodes", lines[3],
		CeroSecOS.padRight("nodes", 10) .. "  " .. CeroSecOS.padLeft(tostring(CeroSecOS.MAX_NODES), 5)
			.. "  " .. CeroSecOS.padLeft(tostring(nodes), 5)
			.. "  " .. CeroSecOS.padLeft(tostring(CeroSecOS.MAX_NODES - nodes), 5)
			.. "  " .. CeroSecOS.padLeft(tostring(pct(nodes, CeroSecOS.MAX_NODES)) .. "%", 4))

	-- And the numbers MOVE with the disk, which is the only thing that makes
	-- them numbers and not decoration.
	okAt(state, admin, 'write big.txt "' .. string.rep("x", 1000) .. '"', {})
	local after = okAt(state, admin, "df", nil)
	local usedBefore = tonumber(string.match(lines[2], "^%a+%s+%d+%s+(%d+)"))
	local usedAfter = tonumber(string.match(after[2], "^%a+%s+%d+%s+(%d+)"))
	eq("a thousand bytes written is a thousand bytes used", usedAfter - usedBefore, 1000)
	local nodesAfter = tonumber(string.match(after[3], "^%a+%s+%d+%s+(%d+)"))
	eq("and one more node", nodesAfter - nodes, 1)

	-- Rounded up: one byte on the disk is not an empty disk.
	eq("one byte is 1%", 1, math.ceil(1 * 100 / CeroSecOS.DISK_BYTES))
	badAt(state, admin, "df -h", "df: usage: df")

	-- The BIOS says the same number the ceiling is.
	eq("the disk label", CeroSecOS.diskLabel(), "32K")
	eq("and it is the ceiling", CeroSecOS.DISK_BYTES, CeroSecOS.MAX_TOTAL_BYTES)
end

-- 20h. The text tools.
do
	local state = fresh()
	local admin = open(state, "admin")
	local text = "alpha beta\ngamma\nAlpha two\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven\ntwelve"
	okAt(state, admin, 'write a.txt "' .. text .. '"', {})

	-- grep: a plain substring, and the flags.
	okAt(state, admin, "grep alpha a.txt", { "alpha beta" })
	okAt(state, admin, "grep -n alpha a.txt", { "1:alpha beta" })
	okAt(state, admin, "grep -i alpha a.txt", { "alpha beta", "Alpha two" })
	okAt(state, admin, "grep -in alpha a.txt", { "1:alpha beta", "3:Alpha two" })
	okAt(state, admin, "grep -ni alpha a.txt", { "1:alpha beta", "3:Alpha two" })
	-- Nothing found is a refusal, with nothing printed.
	local miss = runAt(state, admin, "grep zebra a.txt", ENV)
	eq("no hit is a refusal", miss.ok, false)
	eq("and says nothing", #miss.lines, 0)
	-- A pattern is not a pattern: the dot is a dot.
	okAt(state, admin, 'write dots.txt "a.b\naxb"', {})
	okAt(state, admin, "grep a.b dots.txt", { "a.b" })
	-- Two files, so the name goes in front.
	okAt(state, admin, "cp a.txt b.txt", {})
	okAt(state, admin, "grep gamma a.txt b.txt", { "a.txt:gamma", "b.txt:gamma" })
	okAt(state, admin, "grep -n gamma a.txt b.txt", { "a.txt:2:gamma", "b.txt:2:gamma" })
	badAt(state, admin, "grep", "grep: usage: grep [-i] [-n] <text> <file>...")
	badAt(state, admin, "grep alpha", "grep: usage: grep [-i] [-n] <text> <file>...")
	badAt(state, admin, "grep -q alpha a.txt", "grep: -q: unknown option")
	badAt(state, admin, "grep alpha /nope", "grep: /nope: no such file")
	badAt(state, admin, "grep alpha /etc", "grep: /etc: is a directory")
	badAt(state, admin, "grep alpha /etc/passwd", "grep: /etc/passwd: permission denied")

	-- head and tail. Ten lines by default.
	okAt(state, admin, "head a.txt",
		{ "alpha beta", "gamma", "Alpha two", "four", "five", "six", "seven", "eight",
		  "nine", "ten" })
	okAt(state, admin, "head -n 2 a.txt", { "alpha beta", "gamma" })
	okAt(state, admin, "head -n 0 a.txt", {})
	okAt(state, admin, "tail -n 2 a.txt", { "eleven", "twelve" })
	okAt(state, admin, "tail a.txt",
		{ "Alpha two", "four", "five", "six", "seven", "eight", "nine", "ten",
		  "eleven", "twelve" })
	-- More lines asked for than there are is the whole file, not a refusal.
	okAt(state, admin, "head -n 99 dots.txt", { "a.b", "axb" })
	okAt(state, admin, "tail -n 99 dots.txt", { "a.b", "axb" })
	okAt(state, admin, "touch empty.txt", {})
	okAt(state, admin, "head empty.txt", {})
	okAt(state, admin, "tail empty.txt", {})
	badAt(state, admin, "head", "head: usage: head [-n N] <file>")
	badAt(state, admin, "head -n a.txt", "head: usage: head [-n N] <file>")
	badAt(state, admin, "head -n -3 a.txt", "head: usage: head [-n N] <file>")
	badAt(state, admin, "tail a.txt b.txt", "tail: usage: tail [-n N] <file>")
	badAt(state, admin, "head /nope", "head: /nope: no such file")
	badAt(state, admin, "tail /etc", "tail: /etc: is a directory")

	-- wc: lines, words, bytes, name, and a total when there is more than one.
	okAt(state, admin, "wc dots.txt", { "     2      2      7 dots.txt" })
	okAt(state, admin, "wc empty.txt", { "     0      0      0 empty.txt" })
	okAt(state, admin, "wc dots.txt empty.txt", {
		"     2      2      7 dots.txt",
		"     0      0      0 empty.txt",
		"     2      2      7 total",
	})
	local counted = okAt(state, admin, "wc a.txt", nil)
	eq("wc counts a.txt", counted[1], "    12     14     " .. #text .. " a.txt")
	badAt(state, admin, "wc", "wc: usage: wc <file>...")
	badAt(state, admin, "wc /nope", "wc: /nope: no such file")
end

-- 20i. cp -r.
do
	local state = fresh()
	local admin = open(state, "admin")
	okAt(state, admin, "mkdir tree", {})
	okAt(state, admin, "mkdir tree/inner", {})
	okAt(state, admin, 'write tree/inner/deep.txt "buried"', {})
	okAt(state, admin, 'write tree/top.txt "surface"', {})

	badAt(state, admin, "cp tree copy", "cp: tree: is a directory")
	okAt(state, admin, "cp -r tree copy", {}, ENV2)
	local copy = state.fs.children.home.children.admin.children.copy
	eq("the tree came over", copy.children.inner.children["deep.txt"].data, "buried")
	eq("and the file at the top", copy.children["top.txt"].data, "surface")
	eq("the copy is the caller's", copy.children.inner.owner, "admin")
	eq("every node of it is stamped now",
		CeroSecOS.mtimeOf(copy.children.inner.children["deep.txt"]), LATER)
	eq("the root of the copy too", CeroSecOS.mtimeOf(copy), LATER)
	-- The original is untouched.
	eq("and the original still has no stamp on its listing",
		CeroSecOS.mtimeOf(state.fs.children.home.children.admin.children.tree.children.inner), FIXED)

	-- Never into itself, whichever way the path is spelled.
	badAt(state, admin, "cp -r tree tree/again", "cp: tree/again: invalid destination")
	badAt(state, admin, "cp -r tree tree/inner/../x", "cp: tree/inner/../x: invalid destination")
	badAt(state, admin, "cp -r tree tree", "cp: tree/tree: invalid destination")
	badAt(state, admin, "cp -r . here", "cp: here: invalid destination")
	badAt(state, admin, "cp -z tree x", "cp: -z: unknown option")
	badAt(state, admin, "cp -r tree", "cp: usage: cp [-r] <src> <dst>")

	-- A tree you cannot walk is a tree you cannot copy, and nothing of it is
	-- written before the refusal.
	local rootSession = open(state, "root")
	okAt(state, rootSession, "mkdir /home/admin/shut", {})
	okAt(state, rootSession, 'write /home/admin/shut/secret.txt "his"', {})
	okAt(state, rootSession, "chmod 700 /home/admin/shut", {})
	badAt(state, admin, "cp -r shut mine", "cp: shut: permission denied")
	eq("and nothing was written",
		state.fs.children.home.children.admin.children.mine, nil)

	-- Into an existing directory, by the source's own name.
	okAt(state, admin, "mkdir box", {})
	okAt(state, admin, "cp -r tree box", {})
	eq("it landed under its name",
		state.fs.children.home.children.admin.children.box.children.tree.children["top.txt"].data,
		"surface")
	eq("the state is still plain and legal", CeroSecOS.validate(state), true)
end

-- 20j. man, and the one usage line.
do
	local state = fresh()
	local admin = open(state, "admin")
	okAt(state, admin, "man ls", { "ls - list a directory", "usage: ls [-lF] [path]" })
	okAt(state, admin, "man date", { "date - print the date and time", "usage: date [+FORMAT]" })
	badAt(state, admin, "man", "man: usage: man <command>")
	badAt(state, admin, "man ls date", "man: usage: man <command>")
	badAt(state, admin, "man nosuchthing", "man: nosuchthing: no manual entry")

	-- The description is the FILE's: rewrite /bin/ls and man says what it says.
	local rootSession = open(state, "root")
	okAt(state, rootSession, 'write /bin/ls "shows you things"', {})
	okAt(state, admin, "man ls", { "ls - shows you things", "usage: ls [-lF] [path]" })
	-- And a command that is gone has no manual.
	okAt(state, rootSession, "rm /bin/ls", {})
	badAt(state, admin, "man ls", "man: ls: no manual entry")

	-- Every usage refusal in the OS prints the string man prints. Nothing here
	-- is a list written by hand: it is derived from the table, so a command
	-- added tomorrow is covered the day it is added.
	local names = CeroSecOS.binNames()
	local printed = 0
	for i = 1, #names do
		local form = CeroSecOS.commandUsage(names[i])
		-- Six words of nonsense: past the argument count of everything there is.
		-- A fresh machine and a fresh root session each time, so a command that
		-- goes through with them changes nothing the next one will see.
		local clean = fresh()
		local line = names[i] .. " zz1 zz2 zz3 zz4 zz5 zz6"
		local _, out = CeroSecOS.exec(clean, open(clean, "root"), line, ENV)
		-- Not every command HAS a wrong argument count -- echo takes anything --
		-- but every one that says "usage" says this one.
		if #out > 0 and string.find(out[1], ": usage: ", 1, true) ~= nil then
			printed = printed + 1
			eq(names[i] .. " prints its own usage line", out[1],
				names[i] .. ": usage: " .. form)
		end
	end
	-- Most of the commands do have one, and if that number ever collapses the
	-- loop above has stopped exercising anything.
	check("most commands refused with a usage line (" .. printed .. ")", printed >= 20)
end

-- 20k. A machine from the last rung is topped up with this one's commands.
do
	local state = fresh()
	-- As rung 2d left it: numbered 2, and without anything this rung adds.
	state.sysv = 2
	local added = { "date", "df", "grep", "head", "tail", "wc", "man" }
	for i = 1, #added do state.fs.children.bin.children[added[i]] = nil end
	-- Something of the player's, to prove the upgrade is not a restore.
	state.fs.children.home.children.admin.children["mine.txt"] =
		CeroSecOS.newFile("admin", 644, "keep me")

	eq("the upgrade has something to do", CeroSecOS.upgradeSystem(state), true)
	eq("and moves the number to this build", state.sysv, CeroSecOS.SYSTEM_VERSION)
	for i = 1, #added do
		local node = state.fs.children.bin.children[added[i]]
		check("/bin/" .. added[i] .. " was seeded", node ~= nil)
		eq("/bin/" .. added[i] .. " is root's", node.owner, "root")
		eq("/bin/" .. added[i] .. " is 755", node.mode, 755)
		eq("/bin/" .. added[i] .. " describes itself", node.data, CeroSecOS.commandDesc(added[i]))
	end
	eq("the player's file was not touched",
		state.fs.children.home.children.admin.children["mine.txt"].data, "keep me")
	eq("it validates", CeroSecOS.validate(state), true)
	eq("and asked once only", CeroSecOS.upgradeSystem(state), false)

	-- The new commands really run on it.
	local admin = open(state, "admin")
	okAt(state, admin, "date", { "Thu Jul  8 14:32:00 1993" })
	eq("and df is there", #okAt(state, admin, "df", nil), 3)

	-- The BIOS repair ships them too.
	local broken = fresh()
	broken.fs.children.bin.children.date = nil
	broken.fs.children.bin.children.man = nil
	CeroSecOS.restoreSystem(broken)
	check("the repair puts date back", broken.fs.children.bin.children.date ~= nil)
	check("and man", broken.fs.children.bin.children.man ~= nil)
	eq("at this build", broken.sysv, CeroSecOS.SYSTEM_VERSION)
end

--
-- 25. Accounts: adduser, deluser, id, and su (rung 3).
--

-- The name rule for an account the machine MAKES. Narrower than a file name on
-- purpose, and every name it takes is a file name, because a home directory is
-- made out of it.
do
	local good = { "b", "bob", "b0", "bob_1", "bob-1", "abcdefghijklmnop" }
	for i = 1, #good do
		check("`" .. good[i] .. "` is a name", CeroSecOS.isValidUserName(good[i]))
		check("and a file name too", CeroSecOS.isValidName(good[i]))
	end
	local bad_ = { "", "Bob", "1bob", "-bob", "_bob", "bo.b", "bo b", "bob!",
		"abcdefghijklmnopq", "root ", 7, nil }
	for i = 1, #bad_ do
		check("`" .. tostring(bad_[i]) .. "` is not one", not CeroSecOS.isValidUserName(bad_[i]))
	end
	eq("sixteen characters", CeroSecOS.MAX_USERNAME, 16)
end

-- adduser: what it writes, and what it refuses.
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")

	-- Root's, and root's alone -- which is what makes `sudo adduser` the way an
	-- admin does it.
	badAt(state, admin, "adduser bob", "adduser: permission denied")
	eq("and nothing was made", CeroSecOS.getUser(state, "bob"), nil)

	badAt(state, rootSession, "adduser", "adduser: usage: adduser [-a] <name>")
	badAt(state, rootSession, "adduser bob carl", "adduser: usage: adduser [-a] <name>")
	badAt(state, rootSession, "adduser -x bob", "adduser: -x: unknown option")
	-- A name that begins with "-" is read as a flag, the way every shell reads
	-- one, and the refusal is about the flag it looks like.
	badAt(state, rootSession, "adduser -bob", "adduser: -bob: unknown option")
	badAt(state, rootSession, "adduser Bob", "adduser: Bob: invalid name")
	badAt(state, rootSession, "adduser 1bob", "adduser: 1bob: invalid name")
	badAt(state, rootSession, "adduser admin", "adduser: admin: already exists")
	badAt(state, rootSession, "adduser root", "adduser: root: already exists")

	okAt(state, rootSession, "adduser bob", {
		"adduser: bob: created",
		"adduser: set a password with passwd bob",
	})

	local bob = CeroSecOS.getUser(state, "bob")
	check("the account is in the file", bob ~= nil)
	eq("with its home", bob.home, "/home/bob")
	eq("and no flag", bob.admin, false)
	check("its password is stored like every other", CeroSecOS.splitHash(bob.password) ~= nil)
	check("and it is the empty one", holds(state, "bob", ""))
	check("which is not any other", not holds(state, "bob", "hunter2"))
	-- The line was appended: the accounts that were there are untouched.
	eq("root is still root", CeroSecOS.getUser(state, "root").home, "/root")
	check("and admin still gets in", holds(state, "admin", ""))

	local home = CeroSecOS.systemNode(state, "/home/bob")
	check("the home directory is there", home ~= nil)
	eq("it is a directory", home.type, "dir")
	eq("it is his", home.owner, "bob")
	eq("and it is 750", home.mode, CeroSecOS.HOME_MODE)
	eq("stamped with the clock the command was handed", CeroSecOS.mtimeOf(home), FIXED)
	eq("the machine still validates", CeroSecOS.validate(state), true)

	-- He can log in, and he lands in his own home.
	local session = open(state, "bob")
	eq("logged in as himself", session.user, "bob")
	eq("in his own home", session.cwd, "/home/bob")
	okAt(state, session, "pwd", { "/home/bob" })
	okAt(state, session, "whoami", { "bob" })
	-- 750: nobody else goes in there.
	badAt(state, admin, "ls /home/bob", "ls: /home/bob: permission denied")

	-- -a writes the flag, and nothing else changes.
	okAt(state, rootSession, "adduser -a kate", {
		"adduser: kate: created",
		"adduser: set a password with passwd kate",
	})
	eq("the flag is on the line", CeroSecOS.getUser(state, "kate").admin, true)
	eq("and the home is the same shape",
		CeroSecOS.systemNode(state, "/home/kate").mode, CeroSecOS.HOME_MODE)
	eq("the machine still validates", CeroSecOS.validate(state), true)
end

-- An existing directory is adopted, not remade.
do
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "mkdir /home/carl", {})
	okAt(state, rootSession, "chmod 700 /home/carl", {})
	okAt(state, rootSession, "write /home/carl/notes.txt \"keep me\"", {})

	okAt(state, rootSession, "adduser carl", {
		"adduser: carl: created",
		"adduser: set a password with passwd carl",
	})
	local home = CeroSecOS.systemNode(state, "/home/carl")
	eq("it changed hands", home.owner, "carl")
	eq("and kept the mode it had", home.mode, 700)
	eq("and everything in it", home.children["notes.txt"].data, "keep me")

	-- A file at that name is not a home, and the refusal says so.
	okAt(state, rootSession, "write /home/dave hello", {})
	badAt(state, rootSession, "adduser dave", "adduser: /home/dave: not a directory")
	eq("and no account was made", CeroSecOS.getUser(state, "dave"), nil)
end

-- The account and its home stand or fall together.
do
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "rm -r /home", {})

	badAt(state, rootSession, "adduser eve", "adduser: /home/eve: no such file")
	eq("the line that was written is taken back out", CeroSecOS.getUser(state, "eve"), nil)
	check("and the accounts that were there are still there", holds(state, "admin", ""))
	eq("the machine still validates", CeroSecOS.validate(state), true)
end

-- sudo adduser: the way somebody who is not root makes an account.
do
	local state = fresh()
	local admin = open(state, "admin")
	local asked = run(state, admin, "sudo adduser -a bob")
	eq("sudo asks for admin's password", asked.data.text, "[sudo] password for admin: ")
	local made = answer(state, admin, asked.data.cont, "")
	eq("it succeeds", made.ok, true)
	eq("and says so", made.lines[1], "adduser: bob: created")
	eq("the account is there", CeroSecOS.getUser(state, "bob").admin, true)
	eq("the home is his", CeroSecOS.systemNode(state, "/home/bob").owner, "bob")
	eq("and the console is still admin's", admin.user, "admin")
end

-- deluser: the guards, the two files, and the home.
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")
	okAt(state, rootSession, "adduser bob", nil)
	okAt(state, rootSession, "adduser carl", nil)

	badAt(state, admin, "deluser bob", "deluser: permission denied")
	badAt(state, rootSession, "deluser", "deluser: usage: deluser [-r] <name>")
	badAt(state, rootSession, "deluser -x bob", "deluser: -x: unknown option")
	badAt(state, rootSession, "deluser bob carl", "deluser: usage: deluser [-r] <name>")
	badAt(state, rootSession, "deluser nosuch", "deluser: nosuch: no such user")
	-- Root is the way back into the machine and is not one of the accounts.
	badAt(state, rootSession, "deluser root", "deluser: root: cannot remove")

	-- The account at the glass. The session running the command is root's --
	-- that is what sudo does -- and the guard is about who is logged in.
	local asRoot = open(state, "root")
	asRoot.login = "bob"
	badAt(state, asRoot, "deluser bob", "deluser: bob: user is logged in")
	-- And a user the glass would come back to through `exit`.
	asRoot.login = "carl"
	asRoot.stack = { { user = "bob", cwd = "/home/bob" } }
	badAt(state, asRoot, "deluser bob", "deluser: bob: user is logged in")
	check("neither of them was touched", CeroSecOS.getUser(state, "bob") ~= nil)

	-- Without -r the home stays exactly where it is, owned by a name the
	-- machine no longer knows.
	okAt(state, rootSession, "deluser bob", { "deluser: bob: removed" })
	eq("the account is gone", CeroSecOS.getUser(state, "bob"), nil)
	check("and cannot log in", CeroSecOS.login(state, "bob", "") == nil)
	local home = CeroSecOS.systemNode(state, "/home/bob")
	check("the home is still there", home ~= nil)
	eq("still owned by the name that is gone", home.owner, "bob")
	eq("and `ls -l` says so", okAt(state, rootSession, "ls -l /home", nil)[2],
		"drwxr-x---  bob           0  Jul  8 14:32  bob")

	-- With -r it goes, and everything under it.
	okAt(state, rootSession, "write /home/carl/notes.txt hello", {})
	okAt(state, rootSession, "deluser -r carl", { "deluser: carl: removed" })
	eq("the account is gone", CeroSecOS.getUser(state, "carl"), nil)
	eq("and so is the home", CeroSecOS.systemNode(state, "/home/carl"), nil)
	eq("the machine still validates", CeroSecOS.validate(state), true)
end

-- The right to become root goes with the account.
do
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "adduser bob", nil)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH,
		"# who may\nadmin\nbob NOPASSWD")
	eq("bob may sudo", CeroSecOS.sudoer(state, "bob").nopasswd, true)

	okAt(state, rootSession, "deluser bob", { "deluser: bob: removed" })
	eq("and now he is nobody", CeroSecOS.sudoer(state, "bob"), nil)
	eq("admin kept his line", CeroSecOS.sudoer(state, "admin").name, "admin")
	eq("and the comment is still in the file",
		CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH).data, "# who may\nadmin")

	-- A machine with no /etc/sudoers at all has nothing to take out of it.
	okAt(state, rootSession, "adduser dan", nil)
	okAt(state, rootSession, "rm /etc/sudoers", {})
	okAt(state, rootSession, "deluser dan", { "deluser: dan: removed" })
end

-- `sudo deluser` on the account at the glass: the borrowed session knows who
-- typed the line, so an admin cannot delete himself out from under himself.
do
	local state = fresh()
	local admin = open(state, "admin")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin NOPASSWD")
	badAt(state, admin, "sudo deluser admin", "deluser: admin: user is logged in")
	check("and he is still there", CeroSecOS.getUser(state, "admin") ~= nil)
	-- Somebody else, though, goes.
	okAt(state, admin, "sudo adduser bob", nil)
	okAt(state, admin, "sudo deluser bob", { "deluser: bob: removed" })
end

-- id.
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")

	okAt(state, admin, "id", { "uid=admin flag=user groups=sudo" })
	okAt(state, admin, "id root", { "uid=root flag=admin groups=-" })
	okAt(state, rootSession, "id", { "uid=root flag=admin groups=-" })
	badAt(state, admin, "id nosuch", "id: nosuch: no such user")
	badAt(state, admin, "id a b", "id: usage: id [name]")

	okAt(state, rootSession, "adduser bob", nil)
	okAt(state, admin, "id bob", { "uid=bob flag=user groups=-" })
	okAt(state, rootSession, "adduser -a kate", nil)
	okAt(state, admin, "id kate", { "uid=kate flag=admin groups=-" })
	-- The groups column is the sudoers file and nothing else.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "bob")
	okAt(state, admin, "id bob", { "uid=bob flag=user groups=sudo" })
	okAt(state, admin, "id admin", { "uid=admin flag=user groups=-" })
end

-- su: the stack, and what exit does with it.
do
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "adduser bob", nil)

	badAt(state, rootSession, "su nosuch", "su: nosuch: no such user")
	badAt(state, rootSession, "su a b", "su: usage: su [name]")

	-- Root is asked for nobody's password.
	okAt(state, rootSession, "su bob", {})
	eq("the session is his", rootSession.user, "bob")
	eq("and stands in his home", rootSession.cwd, "/home/bob")
	eq("the stack is one deep", #rootSession.stack, 1)
	eq("and remembers who it was", rootSession.stack[1].user, "root")
	eq("and where he stood", rootSession.stack[1].cwd, "/root")
	okAt(state, rootSession, "whoami", { "bob" })

	-- exit pops, and orders the terminal nothing at all: nobody logged out.
	local popped = runAt(state, rootSession, "exit")
	eq("exit succeeds", popped.ok, true)
	eq("it says nothing", #popped.lines, 0)
	eq("and orders nothing", popped.control, nil)
	eq("the session is root's again", rootSession.user, "root")
	eq("standing where he was", rootSession.cwd, "/root")
	eq("and the stack is empty", #rootSession.stack, 0)

	-- With nothing left on it, exit is a logout again.
	eq("exit logs out", runAt(state, rootSession, "exit").control, "exit")
end

-- su from an account that is not root: the question, the token, and the answer.
do
	local state = fresh()
	local admin = open(state, "admin")
	local rootSession = open(state, "root")
	okAt(state, rootSession, "adduser bob", nil)
	CeroSecOS.setPassword(state, "bob", "hunter2", "x", FIXED)

	local asked = run(state, admin, "su bob")
	eq("it asks", asked.control, "prompt")
	eq("with su's own line", asked.data.text, "Password: ")
	eq("masked", asked.data.mask, true)
	eq("it says nothing while it asks", #asked.lines, 0)
	eq("the token names its command", asked.data.cont.cmd, "su")
	eq("and the account being switched to", asked.data.cont.user, "bob")
	-- Nothing of the password is in the token, not even a hash of one: the
	-- answer is judged against /etc/passwd when it arrives.
	eq("no password in the token", asked.data.cont.passwd, nil)
	eq("no hash of one either", asked.data.cont.want, nil)
	eq("and no salt to make one with", asked.data.cont.salt, nil)

	says(answer(state, admin, asked.data.cont, "wrong"), "su: authentication failure")
	eq("and nobody was switched", admin.user, "admin")
	eq("nor given a stack", admin.stack, nil)

	-- The right one, and the target's own -- not the caller's.
	says(answer(state, admin, { cmd = "su", user = "bob" }, ""), "su: authentication failure")
	local switched = answer(state, admin, asked.data.cont, "hunter2")
	eq("it succeeds", switched.ok, true)
	eq("silently", #switched.lines, 0)
	eq("and orders nothing", switched.control, nil)
	eq("the session is bob's", admin.user, "bob")
	eq("in bob's home", admin.cwd, "/home/bob")
	eq("with admin under it", admin.stack[1].user, "admin")

	-- Bare `su` means root.
	local toRoot = run(state, admin, "su")
	eq("it asks for a password", toRoot.control, "prompt")
	eq("root's", toRoot.data.cont.user, "root")
	answer(state, admin, toRoot.data.cont, "")
	eq("and he is root now", admin.user, "root")
	eq("two deep", #admin.stack, 2)
	-- Out again, one at a time.
	runAt(state, admin, "exit")
	eq("back to bob", admin.user, "bob")
	runAt(state, admin, "exit")
	eq("back to admin", admin.user, "admin")
	eq("where he started", admin.cwd, "/home/admin")
	eq("and out of the machine on the next one", runAt(state, admin, "exit").control, "exit")

	-- An account taken out of the file between the question and the answer.
	local gone = run(state, admin, "su bob")
	okAt(state, rootSession, "deluser bob", nil)
	says(answer(state, admin, gone.data.cont, "hunter2"), "su: authentication failure")
	eq("and nobody was switched", admin.user, "admin")
end

-- The stack has a floor and a ceiling.
do
	local state = fresh()
	local rootSession = open(state, "root")
	eq("four deep", CeroSecOS.SU_MAX, 4)
	-- Root becoming root: a switch like any other as far as the stack is
	-- concerned, and the one that can be repeated without a password.
	for i = 1, CeroSecOS.SU_MAX do
		okAt(state, rootSession, "su root", {})
		eq("stack " .. i, #rootSession.stack, i)
	end
	badAt(state, rootSession, "su root", "su: too many levels")
	eq("and it stayed four deep", #rootSession.stack, CeroSecOS.SU_MAX)
	eq("with nobody switched", rootSession.user, "root")

	-- The same ceiling at the answer, not only at the question: the stack can
	-- grow while a password is being typed.
	local admin = open(state, "admin")
	local asked = run(state, admin, "su root")
	admin.stack = { { user = "a", cwd = "/" }, { user = "b", cwd = "/" },
		{ user = "c", cwd = "/" }, { user = "d", cwd = "/" } }
	says(answer(state, admin, asked.data.cont, ""), "su: too many levels")
	eq("and nobody was switched", admin.user, "admin")
end

-- A borrowed session carries a COPY of the stack: `sudo su` moves nobody and
-- `sudo exit` is a logout, not somebody else's su to unwind.
do
	local state = fresh()
	local admin = open(state, "admin")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin NOPASSWD")

	answer(state, admin, run(state, admin, "su root").data.cont, "")
	eq("the console is root's", admin.user, "root")
	eq("one deep", #admin.stack, 1)

	okAt(state, admin, "sudo su admin", {})
	eq("sudo su moved nobody", admin.user, "root")
	eq("and pushed nothing", #admin.stack, 1)

	eq("sudo exit is a logout", runAt(state, admin, "sudo exit").control, "exit")
	eq("and popped nothing", #admin.stack, 1)
	-- The console's own exit still pops.
	eq("exit pops", runAt(state, admin, "exit").control, nil)
	eq("back to admin", admin.user, "admin")
end

-- A machine from the last rung is topped up with this rung's four commands.
do
	local state = fresh()
	state.sysv = 3
	local added = { "adduser", "deluser", "id", "su" }
	for i = 1, #added do state.fs.children.bin.children[added[i]] = nil end
	state.fs.children.home.children.admin.children["mine.txt"] =
		CeroSecOS.newFile("admin", 644, "keep me")

	eq("the upgrade has something to do", CeroSecOS.upgradeSystem(state), true)
	eq("and moves the number to this build", state.sysv, 4)
	for i = 1, #added do
		local node = state.fs.children.bin.children[added[i]]
		check("/bin/" .. added[i] .. " was seeded", node ~= nil)
		eq("/bin/" .. added[i] .. " is root's", node.owner, "root")
		eq("/bin/" .. added[i] .. " is 755", node.mode, 755)
		eq("/bin/" .. added[i] .. " describes itself", node.data, CeroSecOS.commandDesc(added[i]))
	end
	eq("the player's file was not touched",
		state.fs.children.home.children.admin.children["mine.txt"].data, "keep me")
	eq("it validates", CeroSecOS.validate(state), true)
	eq("and asked once only", CeroSecOS.upgradeSystem(state), false)

	-- They really run on it.
	local rootSession = open(state, "root")
	okAt(state, rootSession, "id", { "uid=root flag=admin groups=-" })
	okAt(state, rootSession, "adduser bob", nil)

	-- And the BIOS repair ships them too.
	local broken = fresh()
	broken.fs.children.bin.children.adduser = nil
	broken.fs.children.bin.children.su = nil
	CeroSecOS.restoreSystem(broken)
	check("the repair puts adduser back", broken.fs.children.bin.children.adduser ~= nil)
	check("and su", broken.fs.children.bin.children.su ~= nil)
	eq("at this build", broken.sysv, CeroSecOS.SYSTEM_VERSION)
end

--
-- 21. /dev
--
-- The engine's whole half of the devices: it renders them, it judges what may
-- be written to one, and it hands the rest to whoever is running the machine.
-- Nothing here knows there is a world -- env.devices is a fake, and that is the
-- point: the core must be provable without a game under it.
--

-- A fake env.devices. An entry may carry `refuse`, the reason its world answers
-- with, and `becomes`, what the state turns into for a value that is accepted.
local function fakeDevices(entries)
	local devices = { entries = entries, writes = {}, chmods = {} }
	local byId = {}
	for i = 1, #entries do byId[entries[i].id] = entries[i] end

	devices.list = function()
		-- A fresh array each call, the way a real discovery hands one over.
		local out = {}
		for i = 1, #devices.entries do
			local e = devices.entries[i]
			out[i] = { id = e.id, kind = e.kind, desc = e.desc, side = e.side,
				state = e.state, mode = e.mode, dead = e.dead }
		end
		return out
	end

	devices.write = function(id, value)
		devices.writes[#devices.writes + 1] = id .. "=" .. value
		local e = byId[id]
		if e == nil then return false, "no such device" end
		if e.refuse ~= nil then return false, e.refuse end
		if e.becomes ~= nil and e.becomes[value] ~= nil then e.state = e.becomes[value] end
		return true, nil, e.state
	end

	devices.chmod = function(id, mode)
		devices.chmods[#devices.chmods + 1] = id .. "=" .. tostring(mode)
		local e = byId[id]
		if e ~= nil then e.mode = mode end
	end

	return devices
end

local ONOFF = { on = "on", off = "off" }
local LOCKING = { lock = "locked", unlock = "unlocked" }

-- The world of the approved mockup, exactly.
local function mockupDevices()
	return fakeDevices({
		{ id = "light0", kind = "light", desc = "office", side = "", state = "on",
			becomes = ONOFF },
		{ id = "light1", kind = "light", desc = "hallway", side = "", state = "off",
			becomes = ONOFF },
		{ id = "lock0", kind = "lock", desc = "exterior", side = "W", state = "locked",
			becomes = LOCKING },
		{ id = "lock1", kind = "lock", desc = "kitchen-hallway", side = "N",
			state = "unlocked", becomes = LOCKING },
		{ id = "win0", kind = "win", desc = "office", side = "N", state = "locked",
			becomes = LOCKING },
		{ id = "lock2", kind = "lock", desc = "built", side = "N", state = "padlock",
			becomes = { lock = "padlock", unlock = "unlocked" } },
	})
end

local function devEnv(devices)
	return { now = FIXED, devices = devices }
end

-- 21a. What `ls -l /dev` prints, to the character.
do
	local state = fresh()
	local session = open(state, "root")
	local env = devEnv(mockupDevices())

	-- The approved mockup. The listing is by NAME, the way every other listing
	-- on this machine is -- childNames sorts, and a directory whose order
	-- depended on the order the world was walked in would not be the same twice.
	okAt(state, session, "ls -l /dev", {
		"crw-rw----  root  light0  office              on",
		"crw-rw----  root  light1  hallway             off",
		"crw-rw----  root  lock0   exterior         W  locked",
		"crw-rw----  root  lock1   kitchen-hallway  N  unlocked",
		"crw-rw----  root  lock2   built            N  padlock",
		"crw-rw----  root  win0    office           N  locked",
	}, env)

	-- The short form is names, columnized like any other directory.
	okAt(state, session, "ls /dev", {
		"light0  light1  lock0   lock1   lock2   win0",
	}, env)

	-- The widest state there is still fits the glass.
	local wide = fakeDevices({
		{ id = "win12", kind = "win", desc = "kitchen-hallway", side = "N",
			state = "barricaded" },
	})
	local line = okAt(state, session, "ls -l /dev", nil, devEnv(wide))[1]
	eq("the widest device line", line,
		"crw-rw----  root  win12   kitchen-hallway  N  barricaded")
	check("and it fits the screen", #line <= CeroSecOS.COLS)

	-- A device is a character device and wears the letter for one.
	eq("the type letter", string.sub(line, 1, 1), "c")

	-- Named straight rather than listed.
	okAt(state, session, "ls -l /dev/lock1",
		{ "crw-rw----  root  lock1   kitchen-hallway  N  unlocked" }, env)
	okAt(state, session, "ls /dev/lock1", { "lock1" }, env)
end

-- 21b. Reading one.
do
	local state = fresh()
	local session = open(state, "root")
	local env = devEnv(mockupDevices())

	okAt(state, session, "cat /dev/light0", { "on" }, env)
	okAt(state, session, "cat /dev/light1", { "off" }, env)
	okAt(state, session, "cat /dev/lock0", { "locked" }, env)
	okAt(state, session, "cat /dev/lock1", { "unlocked" }, env)
	okAt(state, session, "cat /dev/lock2", { "padlock" }, env)
	okAt(state, session, "cat /dev/win0", { "locked" }, env)
	-- Several at once, like any other cat.
	okAt(state, session, "cat /dev/light0 /dev/light1", { "on", "off" }, env)
	-- And into a file: the state of the world, written to the disk.
	okAt(state, session, "cat /dev/light0 > /root/seen.txt", {}, env)
	okAt(state, session, "cat /root/seen.txt", { "on" }, env)
end

-- 21c. Writing one: the order reaches the world, and the state comes back.
do
	local state = fresh()
	local session = open(state, "root")
	local devices = mockupDevices()
	local env = devEnv(devices)

	okAt(state, session, "echo off > /dev/light0", {}, env)
	eq("the world was told once", #devices.writes, 1)
	eq("and what it was told", devices.writes[1], "light0=off")
	okAt(state, session, "cat /dev/light0", { "off" }, env)

	okAt(state, session, "echo unlock > /dev/lock0", {}, env)
	okAt(state, session, "cat /dev/lock0", { "unlocked" }, env)
	okAt(state, session, "echo lock > /dev/win0", {}, env)
	okAt(state, session, "echo unlock > /dev/lock2", {}, env)
	okAt(state, session, "cat /dev/lock2", { "unlocked" }, env)

	-- ">>" is the same order: a device has no contents to append to.
	okAt(state, session, "echo on >> /dev/light1", {}, env)
	okAt(state, session, "cat /dev/light1", { "on" }, env)
	eq("every write reached the world", #devices.writes, 5)

	-- The blanks around a word are the shell's, not the player's.
	okAt(state, session, 'echo "  off  " > /dev/light1', {}, env)
	eq("trimmed on the way out", devices.writes[#devices.writes], "light1=off")
	okAt(state, session, "cat /dev/light1", { "off" }, env)

	-- Any command's output can be the order, not only echo's.
	okAt(state, session, "write /root/v.txt lock", {}, env)
	okAt(state, session, "cat /root/v.txt > /dev/lock1", {}, env)
	okAt(state, session, "cat /dev/lock1", { "locked" }, env)
end

-- 21d. Every refusal a device makes, in its own name.
do
	local state = fresh()
	local session = open(state, "root")
	local devices = fakeDevices({
		{ id = "light0", kind = "light", desc = "office", side = "", state = "off",
			refuse = "no power" },
		{ id = "light1", kind = "light", desc = "office", side = "", state = "on",
			becomes = ONOFF },
		{ id = "win0", kind = "win", desc = "office", side = "N", state = "smashed",
			refuse = "smashed" },
		{ id = "win1", kind = "win", desc = "office", side = "W", state = "barricaded",
			refuse = "barricaded" },
		{ id = "lock2", kind = "lock", desc = "built", side = "N", state = "unlocked",
			refuse = "no padlock" },
		{ id = "lock9", kind = "lock", dead = true },
	})
	local env = devEnv(devices)

	badAt(state, session, "echo on > /dev/light0", "light0: no power", env)
	badAt(state, session, "echo lock > /dev/win0", "win0: smashed", env)
	badAt(state, session, "echo lock > /dev/win1", "win1: barricaded", env)
	badAt(state, session, "echo lock > /dev/lock2", "lock2: no padlock", env)

	-- A word the kind has no meaning for never reaches the world at all. The
	-- four refusals above did reach it -- "no power" is the WORLD's answer --
	-- so what is counted here is the moves this block adds, which is none.
	local reached = #devices.writes
	badAt(state, session, "echo yes > /dev/light1", "light1: invalid value", env)
	badAt(state, session, "echo lock > /dev/light1", "light1: invalid value", env)
	badAt(state, session, "echo on > /dev/lock2", "lock2: invalid value", env)
	badAt(state, session, "echo > /dev/light1", "light1: invalid value", env)
	eq("nothing of that reached the world", #devices.writes, reached)

	-- A device the machine remembers the number of and cannot reach. It is NOT
	-- in the listing -- it is not there -- and naming it says which of the two
	-- kinds of "not there" it is.
	local shown = okAt(state, session, "ls /dev", nil, env)[1]
	check("the dead one is not listed", string.find(shown, "lock9", 1, true) == nil)
	local long = okAt(state, session, "ls -l /dev", nil, env)
	eq("nor in the long listing", #long, 5)
	badAt(state, session, "ls /dev/lock9", "ls: /dev/lock9: no such file", env)
	badAt(state, session, "cat /dev/lock9", "lock9: no such device", env)
	badAt(state, session, "echo lock > /dev/lock9", "lock9: no such device", env)

	-- A name nobody ever gave out is an ordinary miss.
	badAt(state, session, "cat /dev/light7", "cat: /dev/light7: no such file", env)
end

-- 21e. The mode, and that it lasts.
do
	local state = fresh()
	local root = open(state, "root")
	local devices = mockupDevices()
	local env = devEnv(devices)

	-- 660: root's and the sudo group's. The group triplet is not evaluated yet,
	-- so today that means root alone.
	local admin = open(state, "admin")
	badAt(state, admin, "cat /dev/light0", "light0: permission denied", env)
	badAt(state, admin, "echo off > /dev/light0", "light0: permission denied", env)
	eq("and nothing reached the world", #devices.writes, 0)
	-- The listing is the directory's business, not the device's: /dev is 755.
	okAt(state, admin, "ls -l /dev", nil, env)

	-- Root opens it up, and the new mode is handed to the world to remember --
	-- the node itself is gone by the end of the command.
	okAt(state, root, "chmod 666 /dev/light0", {}, env)
	eq("the mode was handed over once", #devices.chmods, 1)
	eq("and what it was", devices.chmods[1], "light0=666")

	okAt(state, admin, "cat /dev/light0", { "on" }, env)
	okAt(state, admin, "echo off > /dev/light0", {}, env)
	okAt(state, admin, "cat /dev/light0", { "off" }, env)
	eq("the mode shows in the listing",
		okAt(state, root, "ls -l /dev/light0", nil, env)[1],
		"crw-rw-rw-  root  light0  office              off")

	-- A mode nobody moved is not handed over again.
	local before = #devices.chmods
	okAt(state, root, "cat /dev/light0", nil, env)
	eq("no chmod for a read", #devices.chmods, before)

	-- Shut again, and root still walks through it.
	okAt(state, root, "chmod 000 /dev/light0", {}, env)
	badAt(state, admin, "cat /dev/light0", "light0: permission denied", env)
	okAt(state, root, "cat /dev/light0", { "off" }, env)
end

-- 21f. A device is not a file, and /dev is not a directory anybody writes in.
do
	local state = fresh()
	local session = open(state, "root")
	local env = devEnv(mockupDevices())

	badAt(state, session, "rm /dev/light0", "rm: /dev/light0: is a device", env)
	badAt(state, session, "rm -r /dev/light0", "rm: /dev/light0: is a device", env)
	badAt(state, session, "mv /dev/light0 /root/x", "mv: /dev/light0: is a device", env)
	badAt(state, session, "cp /dev/light0 /root/x", "cp: /dev/light0: is a device", env)
	badAt(state, session, "cp -r /dev/light0 /root/x", "cp: /dev/light0: is a device", env)
	badAt(state, session, "edit /dev/light0", "edit: /dev/light0: is a device", env)
	badAt(state, session, "chown admin /dev/light0", "chown: /dev/light0: is a device", env)
	badAt(state, session, "touch /dev/light0", "touch: /dev/light0: is a device", env)
	badAt(state, session, "write /dev/light0 on", "write: /dev/light0: is a device", env)
	badAt(state, session, "head /dev/light0", "head: /dev/light0: is a device", env)
	badAt(state, session, "tail /dev/light0", "tail: /dev/light0: is a device", env)
	badAt(state, session, "wc /dev/light0", "wc: /dev/light0: is a device", env)
	badAt(state, session, "grep on /dev/light0", "grep: /dev/light0: is a device", env)

	-- Nothing may be made in /dev, and the refusal names the DIRECTORY: it is
	-- /dev that is read-only, not the name that was tried.
	badAt(state, session, "mkdir /dev/mine", "/dev: read-only", env)
	badAt(state, session, "touch /dev/mine", "/dev: read-only", env)
	badAt(state, session, "edit /dev/mine", "/dev: read-only", env)
	badAt(state, session, "echo hi > /dev/mine", "echo: /dev/mine: read-only", env)
	okAt(state, session, "write /root/x.txt hi", {}, env)
	badAt(state, session, "cp /root/x.txt /dev/mine", "cp: /dev/mine: read-only", env)
	badAt(state, session, "mv /root/x.txt /dev/mine", "mv: /dev/mine: read-only", env)
	check("and nothing landed there",
		state.fs.children.dev.children.mine == nil)
end

-- 21g. Nothing of a device is ever on the disk.
do
	local state = fresh()
	local session = open(state, "root")
	local env = devEnv(mockupDevices())

	local nodesBefore, bytesBefore = CeroSecOS.usage(state)
	okAt(state, session, "ls -l /dev", nil, env)
	okAt(state, session, "cat /dev/light0", nil, env)

	eq("/dev is empty between commands", CeroSecOS.countEntries(state.fs.children.dev), 0)
	eq("the state still validates", CeroSecOS.validate(state), true)
	local nodesAfter, bytesAfter = CeroSecOS.usage(state)
	eq("the disk did not move", bytesAfter, bytesBefore)
	eq("nor the node count", nodesAfter, nodesBefore)

	-- Not even in the middle of the command: a machine whose df moved because
	-- somebody walked past a light switch would be a machine whose ceilings
	-- depend on the weather.
	local df = okAt(state, session, "df", nil, env)
	local plain = okAt(state, session, "df", nil, { now = FIXED })
	eq("df says the same with devices mounted", df[2], plain[2])
	eq("and the same about the nodes", df[3], plain[3])

	-- A machine with no devices at all is the machine of every earlier rung.
	okAt(state, session, "ls /dev", {}, { now = FIXED })
	okAt(state, session, "ls -l /dev", {}, { now = FIXED })
	badAt(state, session, "cat /dev/light0", "cat: /dev/light0: no such file", { now = FIXED })
end

-- 21h. A chain that ends in a device: the mount is under continue too.
do
	local state = fresh()
	local session = open(state, "admin")
	local devices = mockupDevices()
	local env = devEnv(devices)

	local step = { CeroSecOS.exec(state, session, "sudo cat /dev/light0", env) }
	eq("sudo asks first", step[3], "prompt")
	local ok2, lines = CeroSecOS.continue(state, session, step[4].cont, "", env)
	eq("and reads the switch as root", ok2, true)
	eq("what it read", lines[1], "on")

	-- A redirect under a sudo that does not have to ask goes out at once. One
	-- that DOES ask never reaches its redirect at all -- exec drops it when the
	-- command answers "prompt", and continue has no redirect to apply -- which
	-- is the shell as it has been since rung 2 and not a device's business.
	local root = open(state, "root")
	okAt(state, root, "sudo echo off > /dev/light0", {}, env)
	eq("the world was told", devices.writes[#devices.writes], "light0=off")
end

-- 21i. A caller that hands over junk is a machine with no devices, never one
-- with broken ones.
do
	local state = fresh()
	local session = open(state, "root")
	local junk = {
		{ now = FIXED, devices = "yes" },
		{ now = FIXED, devices = {} },
		{ now = FIXED, devices = { list = 4, write = 4 } },
		{ now = FIXED, devices = { list = function() return "no" end,
			write = function() return false end } },
	}
	for i = 1, #junk do
		okAt(state, session, "ls /dev", {}, junk[i])
		eq("and /dev stays empty", CeroSecOS.countEntries(state.fs.children.dev), 0)
	end

	-- An entry that is not one is dropped; the rest are mounted.
	local devices = fakeDevices({
		{ id = "light0", kind = "light", desc = "office", side = "", state = "on" },
		{ id = "-bad", kind = "light", desc = "x", side = "", state = "on" },
		{ id = "nokind", kind = "toaster", desc = "x", side = "", state = "on" },
		{ id = "light1", kind = "light", desc = "hall", side = "", state = "off" },
	})
	okAt(state, session, "ls /dev", { "light0  light1" }, devEnv(devices))
end

print("os_test: " .. count .. " assertions passed")
