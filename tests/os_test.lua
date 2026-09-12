-- Unit tests for the CeroSecOS core. Run from the repo root:
--   lua5.1 tests/os_test.lua

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

-- A file put on the disk with its exact contents, through the filesystem
-- rather than through the prompt. Used wherever the CONTENTS are the point and
-- the shell's quoting is in the way -- a stored hash carries "$" and a passwd
-- file carries newlines, and the prompt speaks the script language now, where
-- both of those mean something inside double quotes.
local function put(state, session, path, text)
	local done, reason = CeroSecOS.writeFile(state, session, path, text, false, nil)
	if done == nil then error("cannot write " .. path .. ": " .. tostring(reason), 2) end
end

local function open(state, name, password)
	local session, reason = CeroSecOS.login(state, name, password or "")
	if session == nil then error("cannot log in as " .. name .. ": " .. tostring(reason), 2) end
	return session
end

--
-- The prompt, driven the way the server drives it.
--
-- Every line typed at this machine is parsed by CeroSecOS.parseScript and run
-- as a foreground job on the session it was typed at -- there is no second,
-- simpler shell any more. So this is what a bench has to do to type a line: make
-- the job, step it until it stops, and drain what it wrote.
--
-- The stepping loop is the SCHEDULER's work on a real machine (SCeroSecJobs.lua,
-- and tests/window_test.lua drives the real one end to end). What is NOT
-- re-implemented here is any of the meaning: the parse, the session, the
-- expansion, the commands and the ceilings are all the engine's.
--
-- Answers the four things the old single-line entry point answered -- ok, the
-- lines, the out-of-band control and its payload -- so every expectation in
-- this file still reads as it did.
local function exec(state, session, line, env)
	env = env or {}
	if type(session) == "table" and session.shvars == nil then session.shvars = {} end
	local vars = nil
	if type(session) == "table" then vars = session.shvars end
	local job, refusal = CeroSecOS.promptJob(state, session, line, vars,
		type(session) == "table" and session.status or nil)
	if job == nil then return false, CeroSecOS.fit({ refusal }) end

	-- The machine's job book, if the caller keeps one: the prompt's own job is
	-- on it while it runs, exactly as it is on a real machine, which is what
	-- `ps` sees and `jobs` deliberately does not.
	local book = env.jobs
	if book ~= nil then book[#book + 1] = job end

	local out = {}
	local turns = 0
	while not CeroSecOS.jobIsOver(job) and turns < 500 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, env, 1000)
		-- What the scheduler does between passes: take what the job wrote off
		-- its hands, so a command with more than forty lines in it is not
		-- blocked on a screen this bench does not have.
		for k = 1, #job.out do out[#out + 1] = job.out[k] end
		job.out = {}
		if job.state == "waiting" or job.state == "sleeping" then break end
		if job.spawn ~= nil then break end
	end
	for k = 1, #job.out do out[#out + 1] = job.out[k] end
	job.out = {}

	if book ~= nil then
		for i = #book, 1, -1 do
			if book[i] == job then table.remove(book, i) end
		end
	end

	-- `cd` and `su` move the console on a real machine (SCeroSecSystem:
	-- writeSession); here they move the session the bench is holding.
	if type(session) == "table" then
		session.user = job.session.user
		session.cwd = job.session.cwd
		session.stack = job.session.stack
		session.status = job.status
	end

	local control, data = job.control, job.controlData
	-- A job that stopped on a question is a command that asked one: the console
	-- cannot tell a script's `read` from passwd's, and neither can this.
	if control == nil and job.state == "waiting" and job.ask ~= nil then
		control = "prompt"
		data = { text = job.ask.text, mask = job.ask.mask, cont = job.cont }
	end
	-- A line that ended in "&" is an order to the MACHINE to make a job of it,
	-- which is what the spawn is.
	if control == nil and job.spawn ~= nil then
		control = "job"
		data = { prog = { job.spawn }, args = job.args, name = job.name, cmd = line, bg = true }
	end
	return job.status == 0, CeroSecOS.fit(out), control, data, job
end

-- Runs a line and pins the whole result: the ok flag, the line count, every
-- line, the out-of-band control value, and the 60-column rule the screen
-- depends on. wantControl defaults to nil, so every single call in this file
-- also asserts that an ordinary command orders the terminal to do nothing.
local function expect(state, session, line, wantOk, wantLines, wantControl)
	local ok, lines, control = exec(state, session, line)
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
	eq("root has 7 entries", #names, 7)
	eq("root entry 1", names[1], "bin")
	eq("root entry 2", names[2], "dev")
	eq("root entry 3", names[3], "etc")
	eq("root entry 4", names[4], "home")
	eq("root entry 5", names[5], "mnt")
	eq("root entry 6", names[6], "root")
	eq("root entry 7", names[7], "var")

	-- /mnt: a PLACE for a floppy to be mounted on, root's at 755 and empty. Empty
	-- is the whole of what it is: anything kept in it disappears from view the
	-- moment somebody mounts a disk over it.
	local mnt = state.fs.children.mnt
	eq("/mnt is root's", mnt.owner, "root")
	eq("/mnt mode", mnt.mode, CeroSecOS.MNT_MODE)
	eq("/mnt ships empty", CeroSecOS.countEntries(mnt), 0)
	eq("and nothing is mounted on a fresh machine", CeroSecOS.mountTable(state), nil)
	eq("and the drive is empty", CeroSecOS.floppyOf(state), nil)

	-- /var and the three under it: the crontab spool, root's and 700, and the
	-- two ordinary directories the log and the mail hang in.
	local var = state.fs.children.var
	eq("/var owner", var.owner, "root")
	eq("/var mode", var.mode, 755)
	eq("/var/spool/cron is root's", var.children.spool.children.cron.owner, "root")
	eq("and nobody else's", var.children.spool.children.cron.mode,
		CeroSecOS.CRON_DIR_MODE)
	eq("/var/spool mode", var.children.spool.mode, 755)
	eq("/var/log mode", var.children.log.mode, 755)
	eq("/var/mail mode", var.children.mail.mode, 755)
	-- The scratch directory: anybody may write in it, and only the owner of a
	-- file in it may take that file away (the rule is the path's, not a mode
	-- digit -- see CeroSecOS.isSticky).
	eq("/var/tmp is root's", var.children.tmp.owner, "root")
	eq("/var/tmp mode", var.children.tmp.mode, CeroSecOS.TMP_MODE)
	eq("and it is empty", CeroSecOS.countEntries(var.children.tmp), 0)
	eq("nothing is in the spool yet", CeroSecOS.countEntries(var.children.spool.children.cron), 0)
	eq("no log yet", CeroSecOS.countEntries(var.children.log), 0)
	eq("no mail yet", CeroSecOS.countEntries(var.children.mail), 0)

	eq("/home/admin exists", state.fs.children.home.children.admin.type, "dir")
	eq("/home/admin owner", state.fs.children.home.children.admin.owner, "admin")
	eq("/home/admin mode", state.fs.children.home.children.admin.mode, 750)
	eq("/root mode", state.fs.children.root.mode, 700)
	-- /dev holds exactly one node on the disk: the hole. Every other device is
	-- the world's and is mounted for the length of a command.
	eq("/dev holds one node", CeroSecOS.countEntries(state.fs.children.dev), 1)
	local null = state.fs.children.dev.children.null
	eq("and it is the null device", CeroSecOS.isNull(null), true)
	eq("owned by root", null.owner, "root")
	eq("readable and writable by everybody", null.mode, 666)
	eq("with nothing in it", null.state, "")
	eq("and it costs the disk nothing", select(2, CeroSecOS.subtreeUsage(null)), 0)
	eq("/etc/hostname data", state.fs.children.etc.children.hostname.data, "ksp-front-01")
	eq("/etc/motd data", state.fs.children.etc.children.motd.data, CeroSecOS.MOTD)
	eq("/etc/motd fits the screen", #CeroSecOS.MOTD <= 60, true)

	-- The skeleton is nine nodes plus the five of the /var tree, plus one
	-- executable per command plus /etc/passwd, /etc/sudoers and /etc/group, and
	-- every byte of it is accounted for: the machine's name, the motd, the
	-- accounts file, the sudoers file, the groups file, the two network files,
	-- and the one-line description in each executable. The /var tree is six
	-- directories and no bytes at all: what goes in it is written when something
	-- asks for it. /dev/null is a DEVICE and costs neither a node nor a byte --
	-- it is a hole, not a file.
	local binNames = CeroSecOS.binNames()
	local binBytes = 0
	for i = 1, #binNames do binBytes = binBytes + #CeroSecOS.commandDesc(binNames[i]) end
	local passwd = state.fs.children.etc.children.passwd
	local sudoers = state.fs.children.etc.children.sudoers
	local group = state.fs.children.etc.children.group
	local hosts = state.fs.children.etc.children.hosts
	local equiv = state.fs.children.etc.children["hosts.equiv"]
	local nodes, bytes = CeroSecOS.usage(state)
	eq("skeleton node count", nodes, 10 + 6 + #binNames + 5)
	eq("skeleton byte count", bytes,
		#"ksp-front-01" + #CeroSecOS.MOTD + #passwd.data + #sudoers.data
			+ #group.data + #hosts.data + #equiv.data + binBytes)

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
	eq("/etc/group owner", group.owner, "root")
	eq("/etc/group mode", group.mode, 644)
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
	local execOk, lines = exec(state, nil, "pwd")
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
	-- An empty or missing motd greets nobody: the built-in line only seeds a
	-- fresh disk, it never speaks for a file root emptied on purpose.
	do
		local quiet = CeroSecOS.newState("quiet")
		eq("motd lines from the shipped file", #CeroSecOS.motdLines(quiet), 1)
		CeroSecOS.systemNode(quiet, "/etc/motd").data = ""
		eq("empty motd prints nothing", #CeroSecOS.motdLines(quiet), 0)
		quiet.fs.children.etc.children.motd = nil
		eq("missing motd prints nothing", #CeroSecOS.motdLines(quiet), 0)
	end
	ok(state, admin, "cat /etc/hostname", { "ksp-front-01" })

	local helpLines = ok(state, admin, "help", nil)
	check("help prints something", #helpLines >= 2)
	eq("help header", helpLines[1], "CeroSec OS commands:")

	-- Packed into columns: five short names fit one row of a 60-column screen.
	ok(state, admin, "ls /", { "bin   dev   etc   home  mnt   root  var" })
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
	ok(state, admin, 'echo "hi" > ~/tilde.txt', {})
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
	ok(state, admin, 'echo "one\\ntwo" > notes.txt', {})
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
	ok(state, rootSession, 'echo "classified" > /root/secret.txt', {})
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
	ok(state, rootSession, 'echo "classified" > /root/secret.txt', {})

	bad(state, admin, "frobnicate", "frobnicate: command not found")
	bad(state, admin, "cat notes.txt", "cat: notes.txt: no such file")
	bad(state, admin, "cat /etc", "cat: /etc: is a directory")
	bad(state, admin, "cat", "cat: usage: cat [file]...")
	bad(state, admin, "cd /root", "cd: /root: permission denied")
	bad(state, admin, "cd /nope", "cd: /nope: no such file")
	bad(state, admin, "cd /etc/motd", "cd: /etc/motd: not a directory")
	bad(state, admin, "cd a b", "cd: usage: cd [dir]")
	bad(state, admin, "cat /root/secret.txt", "cat: /root/secret.txt: permission denied")
	bad(state, admin, "ls /root/x", "ls: /root/x: permission denied")
	bad(state, admin, "ls /nope", "ls: /nope: no such file")
	bad(state, admin, "ls -z", "ls: -z: unknown option")
	bad(state, admin, "ls a b", "ls: usage: ls [-1laACF] [path]")
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
	bad(state, admin, 'echo "hi" > /etc/x', "echo: /etc/x: permission denied")
	bad(state, admin, "pwd x", "pwd: usage: pwd")
	bad(state, admin, "whoami x", "whoami: usage: whoami")
	bad(state, admin, "hostname x", "hostname: permission denied")
	bad(state, admin, "hostname a b", "hostname: usage: hostname [name]")

	-- Syntax. A prompt line that will not parse never becomes a job, and the
	-- refusal is the SHELL's -- "sh: ..." -- because the shell is what could
	-- not read it. There is no line number: a typed line is line one of nothing.
	bad(state, admin, 'echo "abc', "sh: syntax error: unterminated quote")
	bad(state, admin, 'echo "abc\\', "sh: syntax error: unterminated quote")
	bad(state, admin, "echo >", "sh: syntax error: missing redirect target")
	bad(state, admin, "echo a > b > c", "sh: syntax error: bad redirect")
	-- The whole grammar of chapter 15 is the prompt's now, so its refusals are
	-- the prompt's too.
	bad(state, admin, "while true; do echo x", "sh: syntax error: missing 'done'")
	bad(state, admin, "if true", "sh: syntax error: missing 'then'")
	bad(state, admin, "done", "sh: syntax error: unexpected 'done'")

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
-- 6a. mv writes over what is already there.
--
-- rename(2) replaces its destination, and mv has done so since there was an mv.
-- What decides is w on the DIRECTORY the name is in -- the listing is what is
-- written -- and never the destination's own mode: a file nobody may write is
-- still a name somebody may make mean something else.
--
do
	local state = fresh()
	local admin = open(state, "admin")

	ok(state, admin, 'echo "new" > keep.txt', {})
	ok(state, admin, 'echo "old" > gone.txt', {})
	ok(state, admin, "mv keep.txt gone.txt", {})
	ok(state, admin, "cat gone.txt", { "new" })
	ok(state, admin, "ls", { "gone.txt" })

	-- The destination's own mode decides nothing. 400 is a file its owner may
	-- not write, and the name is still his to point somewhere else.
	ok(state, admin, 'echo "moved" > src.txt', {})
	ok(state, admin, "chmod 400 gone.txt", {})
	ok(state, admin, "mv src.txt gone.txt", {})
	ok(state, admin, "cat gone.txt", { "moved" })

	-- The directory's mode decides everything. /etc is root's at 755, so a name
	-- in it is not admin's to write over.
	ok(state, admin, 'echo "x" > mine.txt', {})
	bad(state, admin, "mv mine.txt /etc/motd", "mv: /etc/motd: permission denied")
	ok(state, admin, "cat mine.txt", { "x" })

	-- A directory destination is still moved INTO, and the collision that then
	-- happens inside it is judged like any other.
	ok(state, admin, "mkdir box", {})
	ok(state, admin, 'echo "older" > box/mine.txt', {})
	ok(state, admin, "mv mine.txt box", {})
	ok(state, admin, "cat box/mine.txt", { "x" })

	-- A directory is replaced only by a directory, and only an empty one.
	ok(state, admin, "mkdir into", {})
	ok(state, admin, "mkdir into/empty", {})
	ok(state, admin, "mkdir empty", {})
	ok(state, admin, "touch empty/inside.txt", {})
	ok(state, admin, "mv empty into", {})
	ok(state, admin, "ls into/empty", { "inside.txt" })

	ok(state, admin, "mkdir full", {})
	ok(state, admin, "touch into/full", {})
	bad(state, admin, "mv full into", "mv: into/full: not a directory")
	ok(state, admin, "rm into/full", {})
	ok(state, admin, "mkdir into/full", {})
	ok(state, admin, "touch into/full/held.txt", {})
	bad(state, admin, "mv full into", "mv: into/full: directory not empty")
	ok(state, admin, "ls into/full", { "held.txt" })

	-- And a file is never written over a directory, whichever way round.
	ok(state, admin, "touch loose.txt", {})
	ok(state, admin, "mkdir into/loose.txt", {})
	bad(state, admin, "mv loose.txt into", "mv: into/loose.txt: is a directory")

	-- The bytes the destination held are freed BY the replacement: the disk after
	-- it holds the source's bytes where the destination's used to be.
	local _, before = CeroSecOS.usage(state)
	ok(state, admin, 'echo "ab" > short.txt', {})
	ok(state, admin, 'echo "' .. string.rep("y", 200) .. '" > long.txt', {})
	local _, both = CeroSecOS.usage(state)
	eq("two files on the disk", both, before + 202)
	ok(state, admin, "mv short.txt long.txt", {})
	local _, after = CeroSecOS.usage(state)
	eq("and one of them after the replacement, holding the short file's bytes",
		after, before + 2)
	ok(state, admin, "cat long.txt", { "ab" })
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
	ok(state, rootSession, 'echo "x" > /root/note.txt', {})
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
	-- A file is not a screen, so what goes into it is one name per line: columns
	-- are for somebody reading them, and a name a line is what the next command
	-- can use (see section 46).
	ok(state, admin, "cat listing.txt",
		{ "bin", "dev", "etc", "home", "mnt", "root", "var" })
	-- Asked for outright, the columns go into the file exactly as they would have
	-- gone onto the glass.
	ok(state, admin, "ls -C / > packed.txt", {})
	ok(state, admin, "cat packed.txt", { "bin   dev   etc   home  mnt   root  var" })
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

	-- 4096 bytes is the ceiling for one file. Not reachable from the prompt any
	-- more and deliberately so: a WORD is 1024 bytes (CeroSecOS.MAX_VAR_BYTES,
	-- the script engine's own ceiling, which the prompt now shares), and a
	-- window takes 240 characters on a line anyway -- so the only thing that
	-- ever fills a file to 4096 is the editor, and this is the door it writes
	-- through.
	local bigOk = CeroSecOS.writeFile(state, admin, "big.txt", string.rep("x", 4096), false, nil)
	eq("4096 bytes is a file", bigOk, true)
	eq("4096-byte file stored", #state.fs.children.home.children.admin.children["big.txt"].data, 4096)
	local tooBig, whyTooBig =
		CeroSecOS.writeFile(state, admin, "big.txt", string.rep("x", 4097), false, nil)
	eq("4097 is not", tooBig, nil)
	eq("and says which ceiling", whyTooBig, "file too large")
	eq("refused write left the file alone",
		#state.fs.children.home.children.admin.children["big.txt"].data, 4096)
	local tooBig2 = CeroSecOS.writeFile(state, admin, "huge.txt", string.rep("x", 4097), false, nil)
	eq("and a refused create makes nothing", tooBig2, nil)
	eq("refused create made nothing", state.fs.children.home.children.admin.children["huge.txt"], nil)
	ok(state, admin, "rm big.txt", {})

	-- The word ceiling, which is what the prompt meets first.
	bad(state, admin, 'echo "' .. string.rep("x", 1025) .. '" > w.txt', "sh: word too large")

	-- The entries one directory holds, whatever the ceiling is set to: read off
	-- the engine rather than typed here, so the wave that moved it from 64 to 96
	-- (to leave room in /bin) moved this with it and did not have to be noticed.
	local full = CeroSecOS.MAX_DIR_ENTRIES
	for i = 1, full do
		local execOk = exec(state, admin, "touch f" .. i)
		if not execOk then error("touch f" .. i .. " failed") end
	end
	eq("directory holds the ceiling",
		CeroSecOS.countEntries(state.fs.children.home.children.admin), full)
	local past = "f" .. (full + 1)
	bad(state, admin, "touch " .. past, "touch: " .. past .. ": directory full")
	bad(state, admin, "mkdir d" .. (full + 1), "mkdir: d" .. (full + 1) .. ": directory full")
	-- A rename inside a full directory still works: nothing is being added.
	ok(state, admin, "mv f1 g1", {})
	eq("still at the ceiling after a rename",
		CeroSecOS.countEntries(state.fs.children.home.children.admin), full)
	bad(state, admin, "cp g1 f1", "cp: f1: directory full")
	-- A rename ONTO a name that is taken works there too: a replacement adds no
	-- entry to the listing either, so the ceiling has nothing to say about it.
	ok(state, admin, "mv f2 f3", {})
	eq("one fewer entry after a replacement",
		CeroSecOS.countEntries(state.fs.children.home.children.admin), full - 1)
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
		local execOk, lines = exec(state, rootSession, "mkdir " .. path)
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
	-- Every byte of the hard disk, whatever DISK_BYTES says it holds.
	local state = fresh()
	local rootSession = open(state, "root")
	local _, used = CeroSecOS.usage(state)
	-- Written through the filesystem and not through the prompt: a 4096-byte
	-- block is four times what one WORD may be (CeroSecOS.MAX_VAR_BYTES), and
	-- filling a disk is what the editor does.
	--
	-- How MANY blocks is worked out from the drive and never typed: the drive
	-- doubled when the floppy arrived (rung 4e) and a hand-typed seven would have
	-- left this bench filling half a disk and asserting it was full.
	local block = string.rep("y", CeroSecOS.MAX_FILE_BYTES)
	local blocks = math.floor((CeroSecOS.DISK_BYTES - used) / CeroSecOS.MAX_FILE_BYTES)
	check("the drive has room for more than one maximal file", blocks >= 2)
	for i = 1, blocks do
		local wrote = CeroSecOS.writeFile(state, rootSession, "/b" .. i, block, false, nil)
		if not wrote then error("write /b" .. i .. " failed") end
	end
	local _, now = CeroSecOS.usage(state)
	eq("every block written", now, used + blocks * CeroSecOS.MAX_FILE_BYTES)
	local room = CeroSecOS.DISK_BYTES - now
	eq("and the last of the room too",
		CeroSecOS.writeFile(state, rootSession, "/last", string.rep("z", room), false, nil), true)
	local _, full = CeroSecOS.usage(state)
	eq("disk exactly full", full, CeroSecOS.DISK_BYTES)
	ok(state, rootSession, "touch /nothing", {})            -- an empty file costs no bytes
	bad(state, rootSession, 'echo "x" > /nothing', "echo: /nothing: disk full")
	bad(state, rootSession, 'echo "x" > /brand', "echo: /brand: disk full")
	bad(state, rootSession, "cp /b1 /copy", "cp: /copy: disk full")
end

do
	-- Every node of the hard disk, whatever MAX_NODES says it holds.
	local state = fresh()
	local rootSession = open(state, "root")
	local nodes = CeroSecOS.usage(state)
	-- The skeleton (/mnt included), the /var tree, plus one executable per command,
	-- plus /etc/passwd, /etc/sudoers, /etc/group and the two network files.
	-- /dev/null is a device and is not a node the disk counts.
	eq("starting node count", nodes, 10 + 6 + #CeroSecOS.binNames() + 5)
	local made = 0
	local dir = 0
	while true do
		dir = dir + 1
		if not exec(state, rootSession, "mkdir /p" .. dir) then break end
		made = made + 1
		local full = false
		for i = 1, 64 do
			if nodes + made >= CeroSecOS.MAX_NODES then full = true break end
			if not exec(state, rootSession, "touch /p" .. dir .. "/f" .. i) then break end
			made = made + 1
		end
		if full then break end
	end
	local total = CeroSecOS.usage(state)
	eq("node ceiling reached", total, CeroSecOS.MAX_NODES)
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

	-- 10 perm + 2 + 6 owner + 1 + 6 group + 2 + 5 size + 2 + 12 date + 2 + name
	-- = 60 at most. Nothing on a fresh machine was ever stamped, so every date
	-- is the epoch: an unstamped node is mtime 0 and 0 is a real moment, not a
	-- blank. Nothing on a fresh machine has been chgrp'd either, so every group
	-- is still the owner's own name.
	local EPOCH = "Jan  1 00:00"
	local lines = ok(state, admin, "ls -l /", nil)
	eq("ls -l lists 7 entries", #lines, 7)
	eq("ls -l bin",
		lines[1],
		"drwxr-xr-x" .. "  " .. "root  " .. " " .. "root  " .. "  "
			.. CeroSecOS.padLeft(tostring(#CeroSecOS.binNames()), 5) .. "  " .. EPOCH .. "  bin")
	eq("ls -l mnt",
		lines[5],
		"drwxr-xr-x" .. "  " .. "root  " .. " " .. "root  " .. "  " .. "    0"
			.. "  " .. EPOCH .. "  mnt")
	eq("ls -l root dir",
		lines[6],
		"drwx------" .. "  " .. "root  " .. " " .. "root  " .. "  " .. "    0"
			.. "  " .. EPOCH .. "  root")
	for i = 1, #lines do
		check("ls -l line " .. i .. " fits 60 columns", #lines[i] <= 60)
	end

	local etc = ok(state, admin, "ls -l /etc", nil)
	eq("ls -l group",
		etc[1],
		"-rw-r--r--" .. "  " .. "root  " .. " " .. "root  " .. "  "
			.. CeroSecOS.padLeft(tostring(#CeroSecOS.defaultGroup()), 5)
			.. "  " .. EPOCH .. "  group")
	-- hostname, hosts and hosts.equiv sort in that order: "hostn" is before
	-- "hosts", and the dotted name is behind the bare one.
	eq("ls -l hosts",
		etc[3],
		"-rw-r--r--" .. "  " .. "root  " .. " " .. "root  " .. "  "
			.. CeroSecOS.padLeft(tostring(#CeroSecOS.defaultHosts()), 5)
			.. "  " .. EPOCH .. "  hosts")
	eq("ls -l hosts.equiv",
		etc[4],
		"-rw-r--r--" .. "  " .. "root  " .. " " .. "root  " .. "  "
			.. CeroSecOS.padLeft(tostring(#CeroSecOS.defaultEquiv()), 5)
			.. "  " .. EPOCH .. "  hosts.equiv")
	eq("ls -l motd",
		etc[5],
		"-rw-r--r--" .. "  " .. "root  " .. " " .. "root  " .. "  " .. "   52"
			.. "  " .. EPOCH .. "  motd")
	eq("ls -l sudoers",
		etc[7],
		"-r--r-----" .. "  " .. "root  " .. " " .. "root  " .. "  "
			.. CeroSecOS.padLeft(tostring(#CeroSecOS.defaultSudoers()), 5)
			.. "  " .. EPOCH .. "  sudoers")
	eq("ls -l /etc has 7 lines", #etc, 7)

	-- The group column is the node's group and not its owner once they differ.
	ok(state, rootSession, "chgrp users /etc/motd", {})
	local grouped = ok(state, admin, "ls -l /etc/motd", nil)
	eq("the group column moved", string.sub(grouped[1], 20, 25), "users ")
	eq("and the owner column did not", string.sub(grouped[1], 13, 18), "root  ")
	ok(state, rootSession, "chgrp root /etc/motd", {})

	-- Every permission digit renders.
	ok(state, admin, "touch /home/admin/perm", {})
	ok(state, admin, "chmod 777 /home/admin/perm", {})
	eq("777 renders", string.sub(ok(state, admin, "ls -l /home/admin/perm", nil)[1], 1, 10), "-rwxrwxrwx")
	ok(state, admin, "chmod 000 /home/admin/perm", {})
	eq("000 renders", string.sub(ok(state, admin, "ls -l /home/admin/perm", nil)[1], 1, 10), "----------")
	ok(state, admin, "chmod 421 /home/admin/perm", {})
	eq("421 renders", string.sub(ok(state, admin, "ls -l /home/admin/perm", nil)[1], 1, 10), "-r---w---x")
	ok(state, admin, "chmod 644 /home/admin/perm", {})

	-- The name is the LAST column and the only one that is ever cut: 12
	-- characters, then a "~" in the twelfth.
	local longName = string.rep("n", 32)
	ok(state, admin, "touch /home/admin/" .. longName, {})
	local home = ok(state, admin, "ls -l /home/admin", nil)
	local cut = nil
	for i = 1, #home do
		if string.find(home[i], "nnn", 1, true) ~= nil then cut = home[i] end
	end
	check("the long name is listed", cut ~= nil)
	eq("the long-name line is exactly 60 columns", #cut, 60)
	eq("the long name is cut with a tilde", string.sub(cut, 49), string.rep("n", 11) .. "~")

	-- A long owner is cut the same way, in its own column, and so is a long
	-- group in its own.
	addUser(state, "administrator", "", "/home/admin", false)
	ok(state, rootSession, "chown administrator /home/admin/perm", {})
	local owned = ok(state, rootSession, "ls -l /home/admin/perm", nil)
	eq("the long owner is cut with a tilde", string.sub(owned[1], 13, 18), "admin~")
	ok(state, rootSession, "chgrp administrator /home/admin/perm", {})
	local grp = ok(state, rootSession, "ls -l /home/admin/perm", nil)
	eq("the long group is cut with a tilde", string.sub(grp[1], 20, 25), "admin~")

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
	ok(state, rootSession, 'echo "' .. string.rep("q", 61) .. '" > /home/admin/wide.txt', {})
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

	-- The ceiling validate holds a file to is the biggest one can BE, which is a
	-- history's own -- not the 4096 the write path stops at. A file of 4097 is
	-- exactly what a renamed ~/.sh_history is, and refusing it here would cost a
	-- player his machine for a `mv` the machine itself allowed.
	local bigFile = fresh()
	bigFile.fs.children.etc.children.motd.data = string.rep("x", 4097)
	eq("a file bigger than a write could make it still validates",
		CeroSecOS.validate(bigFile), true)

	local oversize = fresh()
	oversize.fs.children.etc.children.motd.data = string.rep("x", CeroSecOS.HISTORY_BYTES + 1)
	local ovOk, ovReason = CeroSecOS.validate(oversize)
	eq("an oversize file is refused", ovOk, false)
	check("the reason names the size", string.find(ovReason, "file too large", 1, true) ~= nil)

	-- Over the disk quota is a state a machine can be IN and never a state it
	-- cannot be loaded from: the refusal belongs to the write path.
	--
	-- How many maximal files it takes to go past the drive is worked out from the
	-- drive, never typed: nine of them were one too many on a 32K disk and eight
	-- too few on a 64K one.
	local overTotal = fresh()
	local overBlocks =
		math.floor(CeroSecOS.MAX_TOTAL_BYTES / CeroSecOS.MAX_FILE_BYTES) + 1
	for i = 1, overBlocks do
		overTotal.fs.children[ "big" .. i ] =
			CeroSecOS.newFile("root", 644, string.rep("x", CeroSecOS.MAX_FILE_BYTES))
	end
	eq("an oversize disk still validates", CeroSecOS.validate(overTotal), true)
	local overUsed = select(2, CeroSecOS.usage(overTotal))
	check("and it really is over the disk (" .. overUsed .. ")",
		overUsed > CeroSecOS.MAX_TOTAL_BYTES)
	-- And every further write on it is refused until room is made.
	eq("a write on a full disk is refused",
		select(2, CeroSecOS.setData(overTotal, CeroSecOS.rootSession(),
			"/etc/motd", CeroSecOS.MOTD .. "!", nil)), "disk full")
	eq("a shorter line over a longer one is room being MADE, and goes in",
		CeroSecOS.setData(overTotal, CeroSecOS.rootSession(), "/etc/motd", "x", nil), true)

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
	execOk, lines, control = exec(state, admin, "clear")
	eq("clear succeeds", execOk, true)
	eq("clear prints nothing", #lines, 0)
	eq("clear controls the terminal", control, "clear")
	execOk, lines, control = exec(state, admin, "exit")
	eq("exit succeeds", execOk, true)
	eq("exit prints nothing", #lines, 0)
	eq("exit controls the terminal", control, "exit")

	-- Everything else orders nothing.
	execOk, lines, control = exec(state, admin, "pwd")
	eq("pwd controls nothing", control, nil)
	execOk, lines, control = exec(state, admin, "nosuchcommand")
	eq("an unknown command controls nothing", control, nil)
	execOk, lines, control = exec(state, admin, "")
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
	ok(state, admin, 'echo "a\\nb\\tc" > good.txt', {})
	ok(state, admin, "cat good.txt", { "a", "b\tc" })

	-- So cat can never produce a control, whatever a file holds.
	local names = CeroSecOS.childNames(state.fs.children.home.children.admin)
	for i = 1, #names do
		local _, catLines, catControl = exec(state, admin, "cat " .. names[i])
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
			local execOk, lines, control = exec(state, session, script[i])
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
		"mkdir a", "mkdir a/b", "touch a/b/c.txt", 'echo "hello" > a/b/c.txt',
		"cp a/b/c.txt a/d.txt", "mv a/d.txt a/e.txt", "chmod 600 a/e.txt",
		"echo log > a/log.txt", "echo more >> a/log.txt", "rm a/b/c.txt",
	}
	for i = 1, #script do
		local execOk, lines = exec(state, session, script[i])
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
	-- The mkpasswd command: the same function, on a string you choose. It was
	-- called `hash` until SYSTEM_VERSION 16, which was not a name any Unix would
	-- have used for anything; the tool itself is still CeroSec Systems' own, and
	-- the manual's deviations page says so.
	local state = fresh()
	local session = open(state, "admin")

	ok(state, session, "mkpasswd hunter2 abcdef", { CeroSecOS.hashPassword("hunter2", "abcdef") })
	-- Pinned, so a change to the construction is a change to this file.
	ok(state, session, "mkpasswd hunter2 abcdef",
		{ "$cs1$abcdef$" .. string.sub(CeroSecOS.hashPassword("hunter2", "abcdef"), 13) })
	ok(state, session, 'mkpasswd "" abcdef', { CeroSecOS.hashPassword("", "abcdef") })

	-- Without a salt, a fresh one each time: two runs never agree.
	local first = ok(state, session, "mkpasswd hunter2")[1]
	local second = ok(state, session, "mkpasswd hunter2")[1]
	check("a fresh salt every time", first ~= second)
	check("and both are stored passwords", CeroSecOS.splitHash(first) ~= nil)
	eq("a hash line fits the screen", #first <= CeroSecOS.COLS, true)

	bad(state, session, "mkpasswd", "mkpasswd: usage: mkpasswd <text> [salt]")
	bad(state, session, "mkpasswd a b c", "mkpasswd: usage: mkpasswd <text> [salt]")
	bad(state, session, "mkpasswd x BAD", "mkpasswd: BAD: invalid salt")
	-- Single quotes, because the prompt speaks the script language now: inside
	-- DOUBLE quotes "$b" is a variable and expands to nothing, which would make
	-- this line `mkpasswd x a` and a perfectly good salt.
	bad(state, session, "mkpasswd x 'a$b'", "mkpasswd: a$b: invalid salt")
	ok(state, session, 'mkpasswd x "a$b"', nil)

	-- And the old name is gone from the machine, not aliased to the new one.
	bad(state, session, "hash x abcdef", "hash: command not found")
end

--
-- 15. passwd, and the continuation mechanism under it.
--

-- exec/continue with the whole four-value shape kept, because that shape is
-- what the console drives an interactive command with.
local function run(state, session, line)
	local execOk, lines, control, data = exec(state, session, line)
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
	-- A prompt is not output, so nothing of the question is ever redirected into
	-- a file. The file itself is another matter: a shell opens what ">" names
	-- before the command runs, so it is there and empty while the question
	-- stands, and what goes into it is whatever the command says when the answer
	-- comes back (section 42).
	local state = fresh()
	local session = open(state, "admin")
	local step = run(state, session, "passwd > out.txt")
	eq("the prompt still comes", step.control, "prompt")
	eq("and says nothing", #step.lines, 0)
	local opened = CeroSecOS.getNode(state, session, "out.txt")
	check("the target was opened", opened ~= nil)
	eq("and is empty", opened.data, "")
end

--
-- 16. edit: what the core says about opening a file, and the save path.
--

do
	local state = fresh()
	local session = open(state, "admin")

	ok(state, session, 'echo "one\ntwo" > notes.txt', {})

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
	local write = run(state, admin, 'echo "x" > /home/admin/p.txt')
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
	-- And as tall. The core learned the height when it got a PAGER: `more` fills a
	-- screenful, and a core that thought the glass was twenty-four rows deep would
	-- page four lines off the top of it every time.
	eq("and as tall", CeroSec.ROWS, CeroSecOS.ROWS)
	eq("a screenful is the screen less the prompt's own row",
		CeroSecOS.MORE_ROWS, CeroSec.ROWS - 1)
	-- And the depth of the su stack, which the console carries and the core
	-- enforces: a repair that kept five would be a machine the core cannot get
	-- out of, and one that kept three would drop a session somebody was in.
	eq("the su stack is as deep on both sides", CeroSec.SU_MAX, CeroSecOS.SU_MAX)
	-- And the tail of the history the window walks with Up and Down. The window
	-- holds a COPY of what the server sends, so a copy shorter than the tail
	-- would throw lines away and one longer would keep lines the machine has
	-- forgotten.
	eq("the history tail is the same length on both sides",
		CeroSec.HISTORY_MAX, CeroSecOS.HISTORY_TAIL)
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
	ok(state, rootSession, 'echo "list a directory" > /bin/ls', {})
	ok(state, rootSession, "chmod 755 /bin/ls", {})
	ok(state, admin, "ls /etc/motd", { "motd" })

	-- Not executable: refused for everybody the bits refuse, and refused for
	-- root too. Root walks through r and w and through any directory, but x on
	-- a file with none of the three x bits set is the one thing a mode still
	-- says to root -- 4.4BSD's vaccess(), and a real machine's answer.
	ok(state, rootSession, "chmod 644 /bin/ls", {})
	bad(state, admin, "ls /etc/motd", "ls: permission denied")
	bad(state, rootSession, "ls /etc/motd", "ls: permission denied")
	-- One x bit anywhere is enough for root, and for nobody else: the bit for
	-- other, which admin is, still refuses admin.
	ok(state, rootSession, "chmod 001 /bin/ls", {})
	ok(state, rootSession, "ls /etc/motd", { "motd" })
	ok(state, rootSession, "chmod 010 /bin/ls", {})
	ok(state, rootSession, "ls /etc/motd", { "motd" })
	ok(state, rootSession, "chmod 100 /bin/ls", {})
	ok(state, rootSession, "ls /etc/motd", { "motd" })
	bad(state, admin, "ls /etc/motd", "ls: permission denied")
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
	ok(state, rootSession, 'echo "not yet" > /bin/telnet', {})
	ok(state, rootSession, "chmod 755 /bin/telnet", {})
	bad(state, admin, "telnet", "telnet: command not found")

	-- A copy of an executable somewhere else is not a second `ls`: a BARE name
	-- is /bin/<name> and nothing else, and a name with a slash in it is a
	-- script (rung 5a) -- so ./ls is the text of that file, handed to the
	-- machine as a program, and not the command it was copied from.
	ok(state, admin, "cp /bin/ls /home/admin/ls", {})
	ok(state, admin, "chmod 755 /home/admin/ls", {})
	ok(state, admin, "cd /home/admin", {})
	-- The prompt is a job now, so `./ls` does not ask the machine for a second
	-- one: it runs one level deeper inside the prompt's own, the way a shell's
	-- child would. What runs is the TEXT of the copied file -- "list a
	-- directory" -- whose first word is not a command.
	bad(state, admin, "./ls", "list: command not found")
	-- Without x on it, it is not runnable at all.
	ok(state, admin, "chmod 644 /home/admin/ls", {})
	bad(state, admin, "./ls", "./ls: permission denied")

	eq("the state still validates", CeroSecOS.validate(state), true)
end

do
	-- The same script, run by root. A mode still says one thing to root, and it
	-- is the x bit: a file nobody may execute is a file root may not execute
	-- either. Root reads it, writes it, deletes it, and will not RUN it.
	local state = fresh()
	local rootSession = open(state, "root")
	ok(state, rootSession, 'echo "echo hello" > /root/go.sh', {})
	ok(state, rootSession, "cd /root", {})
	ok(state, rootSession, "chmod 755 /root/go.sh", {})
	ok(state, rootSession, "./go.sh", { "hello" })

	-- No x bit anywhere: refused, in the same words an ordinary account gets.
	ok(state, rootSession, "chmod 644 /root/go.sh", {})
	bad(state, rootSession, "./go.sh", "./go.sh: permission denied")
	-- Root still reads it and still writes it: only x is gated.
	ok(state, rootSession, "cat /root/go.sh", { "echo hello" })
	ok(state, rootSession, 'echo "echo hello" > /root/go.sh', {})

	-- Any ONE of the three x bits is enough. None of these three modes gives
	-- root a bit of its own -- root is the owner here, and 010 and 001 leave
	-- the owner's digit at 6 -- and each of them still lets root run it, which
	-- is exactly what "at least one x bit" means.
	ok(state, rootSession, "chmod 100 /root/go.sh", {})
	ok(state, rootSession, "./go.sh", { "hello" })
	ok(state, rootSession, "chmod 010 /root/go.sh", {})
	ok(state, rootSession, "./go.sh", { "hello" })
	ok(state, rootSession, "chmod 001 /root/go.sh", {})
	ok(state, rootSession, "./go.sh", { "hello" })

	-- And 000 is 000 for root too.
	ok(state, rootSession, "chmod 000 /root/go.sh", {})
	bad(state, rootSession, "./go.sh", "./go.sh: permission denied")

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
	put(state, rootSession, "/etc/passwd",
		CeroSecOS.passwdLine(CeroSecOS.newUser("root", "", "/root", true))
		.. "\n" .. "bob:" .. hashOf .. ":/home/bob:admin")

	eq("admin is gone from the machine", CeroSecOS.getUser(state, "admin"), nil)
	eq("and cannot log in", CeroSecOS.login(state, "admin", ""), nil)
	local bob = CeroSecOS.login(state, "bob", "secret")
	check("the account written by hand logs in", bob ~= nil)
	eq("and lands in the home the file gave him", bob.cwd, "/home/bob")
	eq("with the powers the file gave him", CeroSecOS.getUser(state, "bob").admin, true)

	-- Re-homing an account by hand moves where cd with no argument goes.
	put(state, rootSession, "/etc/passwd",
		CeroSecOS.passwdLine(CeroSecOS.newUser("root", "", "/root", true))
		.. "\n" .. "bob:" .. hashOf .. ":/:user")
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
	ok(state, rootSession, 'echo "byhand" > /etc/hostname', {})
	ok(state, admin, "hostname", { "byhand" })

	-- A file that does not hold a name falls back to the state's copy rather
	-- than leaving the machine nameless.
	ok(state, rootSession, 'echo "NOT A NAME" > /etc/hostname', {})
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
	ok(state, rootSession, 'echo "keep me" > /home/admin/work/notes.txt', {})
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
	ok(state, rootSession, 'echo "not ours" > /bin/mine', {})
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
	-- And `restart`, which was here until SYSTEM_VERSION 16, is gone: no Unix ever
	-- had one, and the two real spellings are the two lines above.
	bad(state, rootSession, "restart", "restart: command not found")

	-- Root's alone, and each refusal wears the name that was typed.
	bad(state, admin, "shutdown", "shutdown: permission denied")
	bad(state, admin, "reboot", "reboot: permission denied")

	-- `now` is what "no time at all" means, so the two lines are one order.
	ok(state, rootSession, "shutdown now", {}, "shutdown")
	ok(state, rootSession, "shutdown -h now", {}, "shutdown")
	ok(state, rootSession, "shutdown -r now", {}, "reboot")
	ok(state, rootSession, "halt", {}, "shutdown")
	-- Nothing else is a time, and the usage says the name that was typed.
	bad(state, rootSession, "shutdown soon",
		"shutdown: usage: shutdown [-h|-r] [now|+N] | shutdown -c")
	bad(state, rootSession, "shutdown -h now extra",
		"shutdown: usage: shutdown [-h|-r] [now|+N] | shutdown -c")
	bad(state, rootSession, "reboot -f", "reboot: usage: reboot")
	bad(state, rootSession, "halt now", "halt: usage: halt")
	bad(state, admin, "halt", "halt: permission denied")

	-- Executables like every other command: taking the file away takes the
	-- order away, and the machine cannot be talked into going down by a name.
	ok(state, rootSession, "rm /bin/shutdown", {})
	bad(state, rootSession, "shutdown", "shutdown: command not found")
	eq("and reboot is untouched",
		select(3, exec(state, rootSession, "reboot")), "reboot")

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
	eq("and lists", listed.lines[1], "bin   dev   etc   home  mnt   root  var")
	ok(state, rootSession, "chmod 755 /bin/ls", {})

	-- The two orders come back out of sudo untouched.
	eq("sudo shutdown", select(3, exec(state, admin, "sudo shutdown")), "shutdown")
	eq("sudo reboot", select(3, exec(state, admin, "sudo reboot")), "reboot")
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

	-- A list somebody wrote is kept, exactly as the accounts are. The one line
	-- the repair adds to it is the `%wheel` line, and only where it is missing:
	-- the group is what `useradd -G wheel` puts an account in, and a machine whose
	-- sudoers file did not grant it would be a machine where that flag means
	-- nothing (CeroSecOS.ensureWheel).
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "kate NOPASSWD")
	CeroSecOS.restoreSystem(state)
	eq("a sudoers that still names somebody is kept, with the wheel line added",
		CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH).data,
		"kate NOPASSWD\n%" .. CeroSecOS.WHEEL_GROUP)
	CeroSecOS.restoreSystem(state)
	eq("and it is added once and not again",
		CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH).data,
		"kate NOPASSWD\n%" .. CeroSecOS.WHEEL_GROUP)
	eq("kate is still not asked", CeroSecOS.sudoer(state, "kate").nopasswd, true)

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
		exec(state, open(state, "root"), "shutdown")), "shutdown")
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
	local execOk, lines, control, data = exec(state, session, line, env)
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

	okAt(state, admin, 'echo "hello" > a.txt', {})
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
	local r = exec(state, admin, 'echo "no clock here" > d/moved.txt', nil)
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
	okAt(state, admin, "ls /", { "bin   dev   etc   home  mnt   root  var" })
	okAt(state, admin, "ls", {})
	okAt(state, admin, "touch only.txt", {})
	okAt(state, admin, "ls", { "only.txt" })
	okAt(state, admin, "mkdir sub", {})
	okAt(state, admin, "ls", { "only.txt  sub" })
	-- -F marks the directories and nothing else.
	okAt(state, admin, "ls -F", { "only.txt  sub/" })
	okAt(state, admin, "ls -F /", { "bin/   dev/   etc/   home/  mnt/   root/  var/" })
	-- The mark is part of the name, so it is what the column is measured on.
	eq("the marked names are longer", #okAt(state, admin, "ls -F /", nil)[1], 46)
end

-- 20f. ls -l, with a clock and with the flags together.
do
	local state = fresh()
	local admin = open(state, "admin")
	okAt(state, admin, "touch notes.txt", {})
	okAt(state, admin, 'echo "hello" > notes.txt', {})
	okAt(state, admin, "mkdir sub", {}, ENV2)

	okAt(state, admin, "ls -l", {
		"-rw-r--r--  admin  admin       5  Jul  8 14:32  notes.txt",
		"drwxr-xr-x  admin  admin       0  Jul  8 15:32  sub",
	})
	-- The flags are letters, so every spelling is the same line.
	local want = {
		"-rw-r--r--  admin  admin       5  Jul  8 14:32  notes.txt",
		"drwxr-xr-x  admin  admin       0  Jul  8 15:32  sub/",
	}
	okAt(state, admin, "ls -lF", want)
	okAt(state, admin, "ls -Fl", want)
	okAt(state, admin, "ls -l -F", want)
	okAt(state, admin, "ls -F -l", want)
	-- One bad letter in a run of good ones is still a bad option, and the
	-- refusal names the argument as typed.
	badAt(state, admin, "ls -lz", "ls: -lz: unknown option")
	badAt(state, admin, "ls -zl", "ls: -zl: unknown option")
	badAt(state, admin, "ls -l a b", "ls: usage: ls [-1laACF] [path]")
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
	okAt(state, admin, 'echo "' .. string.rep("x", 1000) .. '" > big.txt', {})
	local after = okAt(state, admin, "df", nil)
	local usedBefore = tonumber(string.match(lines[2], "^%a+%s+%d+%s+(%d+)"))
	local usedAfter = tonumber(string.match(after[2], "^%a+%s+%d+%s+(%d+)"))
	eq("a thousand bytes written is a thousand bytes used", usedAfter - usedBefore, 1000)
	local nodesAfter = tonumber(string.match(after[3], "^%a+%s+%d+%s+(%d+)"))
	eq("and one more node", nodesAfter - nodes, 1)

	-- Rounded up: one byte on the disk is not an empty disk.
	eq("one byte is 1%", 1, math.ceil(1 * 100 / CeroSecOS.DISK_BYTES))
	badAt(state, admin, "df -h", "df: usage: df")

	-- The BIOS says the same number the ceiling is. The LABEL is pinned against
	-- the arithmetic that builds it rather than against a typed string: what is
	-- being asserted is that whole kilobytes come out whole, on whatever drive the
	-- machine is shipping with.
	eq("the disk label", CeroSecOS.diskLabel(),
		tostring(CeroSecOS.DISK_BYTES / 1024) .. "K")
	eq("and it is the ceiling", CeroSecOS.DISK_BYTES, CeroSecOS.MAX_TOTAL_BYTES)
end

-- 20h. The text tools.
do
	local state = fresh()
	local admin = open(state, "admin")
	local text = "alpha beta\ngamma\nAlpha two\nfour\nfive\nsix\nseven\neight\nnine\nten\neleven\ntwelve"
	okAt(state, admin, 'echo "' .. text .. '" > a.txt', {})

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
	okAt(state, admin, 'echo "a.b\naxb" > dots.txt', {})
	okAt(state, admin, "grep a.b dots.txt", { "a.b" })
	-- Two files, so the name goes in front.
	okAt(state, admin, "cp a.txt b.txt", {})
	okAt(state, admin, "grep gamma a.txt b.txt", { "a.txt:gamma", "b.txt:gamma" })
	okAt(state, admin, "grep -n gamma a.txt b.txt", { "a.txt:2:gamma", "b.txt:2:gamma" })

	-- -v: the lines that do NOT hold the string. The flag does not change what a
	-- hit is, it changes which lines are wanted.
	okAt(state, admin, "grep -v a.b dots.txt", { "axb" })
	okAt(state, admin, "grep -vn a.b dots.txt", { "2:axb" })
	okAt(state, admin, "grep -v alpha dots.txt", { "a.b", "axb" })
	-- Nothing left over is nothing found, exactly as nothing matched is.
	local allmatch = runAt(state, admin, "grep -v a dots.txt", ENV)
	eq("every line held it, so -v found nothing", allmatch.ok, false)
	eq("and said nothing", #allmatch.lines, 0)

	-- -c: how many, instead of which. One line a file, and a nought is an answer
	-- and not a silence.
	okAt(state, admin, "grep -c alpha a.txt", { "1" })
	okAt(state, admin, "grep -ci alpha a.txt", { "2" })
	okAt(state, admin, "grep -cv alpha dots.txt", { "2" })
	-- -c prints instead of the lines, so -n has nothing left to number.
	okAt(state, admin, "grep -cn alpha a.txt", { "1" })
	local nonecount = runAt(state, admin, "grep -c zebra a.txt", ENV)
	eq("a count of nothing is still a refusal", nonecount.ok, false)
	eq("and the count is the whole of what it says", nonecount.lines[1], "0")
	eq("which is one line", #nonecount.lines, 1)
	-- Two files, so the name goes in front of the count too -- for the file that
	-- had none as much as for the file that had one.
	okAt(state, admin, "grep -c gamma a.txt dots.txt", { "a.txt:1", "dots.txt:0" })
	okAt(state, admin, "grep -c gamma a.txt b.txt", { "a.txt:1", "b.txt:1" })

	badAt(state, admin, "grep", "grep: usage: grep [-c] [-i] [-n] [-v] <text> [file]...")
	badAt(state, admin, "grep alpha",
		"grep: usage: grep [-c] [-i] [-n] [-v] <text> [file]...")
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
	-- The older spelling, which is what a pair of hands types: `head -1`.
	okAt(state, admin, "head -2 a.txt", { "alpha beta", "gamma" })
	okAt(state, admin, "head -1 a.txt", { "alpha beta" })
	okAt(state, admin, "tail -1 a.txt", { "twelve" })
	okAt(state, admin, "tail -5 a.txt", { "eight", "nine", "ten", "eleven", "twelve" })
	okAt(state, admin, "head -0 a.txt", {})
	okAt(state, admin, "head -99 dots.txt", { "a.b", "axb" })
	okAt(state, admin, "tail a.txt",
		{ "Alpha two", "four", "five", "six", "seven", "eight", "nine", "ten",
		  "eleven", "twelve" })
	-- More lines asked for than there are is the whole file, not a refusal.
	okAt(state, admin, "head -n 99 dots.txt", { "a.b", "axb" })
	okAt(state, admin, "tail -n 99 dots.txt", { "a.b", "axb" })
	okAt(state, admin, "touch empty.txt", {})
	okAt(state, admin, "head empty.txt", {})
	okAt(state, admin, "tail empty.txt", {})
	badAt(state, admin, "head", "head: usage: head [-n N|-N] [file]")
	badAt(state, admin, "head -n a.txt", "head: usage: head [-n N|-N] [file]")
	badAt(state, admin, "head -n -3 a.txt", "head: usage: head [-n N|-N] [file]")
	badAt(state, admin, "tail a.txt b.txt", "tail: usage: tail [-n N|-N] [file]")
	-- Digits and nothing else: `-2x` is not a number and is not a flag either.
	badAt(state, admin, "head -2x a.txt", "head: usage: head [-n N|-N] [file]")
	badAt(state, admin, "head -l a.txt", "head: usage: head [-n N|-N] [file]")
	-- An option is an option before the first file and a file after it, which is
	-- one file too many for head.
	badAt(state, admin, "head a.txt -2", "head: usage: head [-n N|-N] [file]")
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

	-- -l, -w and -c: only what was asked for, and always in POSIX's order
	-- whatever order the flags were written in. The row is the same width, so
	-- the name has 7 more columns for every number left out.
	okAt(state, admin, "wc -l a.txt", { "    12 a.txt" })
	okAt(state, admin, "wc -w a.txt", { "    14 a.txt" })
	okAt(state, admin, "wc -c dots.txt", { "     7 dots.txt" })
	okAt(state, admin, "wc -lc dots.txt", { "     2      7 dots.txt" })
	okAt(state, admin, "wc -cl dots.txt", { "     2      7 dots.txt" })
	okAt(state, admin, "wc -c -l dots.txt", { "     2      7 dots.txt" })
	okAt(state, admin, "wc -wc dots.txt", { "     2      7 dots.txt" })
	okAt(state, admin, "wc -lw dots.txt", { "     2      2 dots.txt" })
	-- All three, asked for, is what all three are by default.
	okAt(state, admin, "wc -lwc dots.txt", { "     2      2      7 dots.txt" })
	okAt(state, admin, "wc -ll dots.txt", { "     2 dots.txt" })
	-- The total row carries the same columns as the rows above it.
	okAt(state, admin, "wc -l dots.txt empty.txt",
		{ "     2 dots.txt", "     0 empty.txt", "     2 total" })
	okAt(state, admin, "wc -c dots.txt empty.txt",
		{ "     7 dots.txt", "     0 empty.txt", "     7 total" })

	badAt(state, admin, "wc", "wc: usage: wc [-clw] [file]...")
	badAt(state, admin, "wc -q dots.txt", "wc: -q: unknown option")
	badAt(state, admin, "wc /nope", "wc: /nope: no such file")
	badAt(state, admin, "wc -l /nope", "wc: /nope: no such file")
end

-- 20i. cp -r.
do
	local state = fresh()
	local admin = open(state, "admin")
	okAt(state, admin, "mkdir tree", {})
	okAt(state, admin, "mkdir tree/inner", {})
	okAt(state, admin, 'echo "buried" > tree/inner/deep.txt', {})
	okAt(state, admin, 'echo "surface" > tree/top.txt', {})

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
	okAt(state, rootSession, 'echo "his" > /home/admin/shut/secret.txt', {})
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
	okAt(state, admin, "man ls", { "ls - list a directory", "usage: ls [-1laACF] [path]" })
	okAt(state, admin, "man date", { "date - print the date and time", "usage: date [+FORMAT]" })
	badAt(state, admin, "man", "man: usage: man <command>")
	badAt(state, admin, "man ls date", "man: usage: man <command>")
	badAt(state, admin, "man nosuchthing", "man: nosuchthing: no manual entry")

	-- The description is the FILE's: rewrite /bin/ls and man says what it says.
	local rootSession = open(state, "root")
	okAt(state, rootSession, 'echo "shows you things" > /bin/ls', {})
	okAt(state, admin, "man ls", { "ls - shows you things", "usage: ls [-1laACF] [path]" })
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
		local _, out = exec(clean, open(clean, "root"), line, ENV)
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
-- 25. Accounts: useradd, userdel, id, and su (rung 3).
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

-- useradd: what it writes, and what it refuses.
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")

	-- Root's, and root's alone -- which is what makes `sudo useradd` the way an
	-- admin does it.
	badAt(state, admin, "useradd bob", "useradd: permission denied")
	eq("and nothing was made", CeroSecOS.getUser(state, "bob"), nil)

	badAt(state, rootSession, "useradd", "useradd: usage: useradd [-G group[,group...]] login")
	badAt(state, rootSession, "useradd bob carl", "useradd: usage: useradd [-G group[,group...]] login")
	badAt(state, rootSession, "useradd -x bob", "useradd: -x: unknown option")
	-- A name that begins with "-" is read as a flag, the way every shell reads
	-- one, and the refusal is about the flag it looks like.
	badAt(state, rootSession, "useradd -bob", "useradd: -bob: unknown option")
	badAt(state, rootSession, "useradd Bob", "useradd: Bob: invalid name")
	badAt(state, rootSession, "useradd 1bob", "useradd: 1bob: invalid name")
	badAt(state, rootSession, "useradd admin", "useradd: admin: already exists")
	badAt(state, rootSession, "useradd root", "useradd: root: already exists")

	okAt(state, rootSession, "useradd bob", {
		"useradd: bob: created",
		"useradd: set a password with passwd bob",
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

	-- -G wheel is what `adduser -a` was: the membership 4.4BSD gates su on, the
	-- group the shipped /etc/sudoers grants, and the flag on the /etc/passwd line
	-- written from it.
	okAt(state, rootSession, "useradd -G wheel kate", {
		"useradd: kate: created",
		"useradd: set a password with passwd kate",
	})
	eq("the flag is on the line", CeroSecOS.getUser(state, "kate").admin, true)
	check("and she really is in wheel",
		CeroSecOS.inGroup(state, "kate", CeroSecOS.WHEEL_GROUP))
	check("which is what lets her sudo", CeroSecOS.sudoer(state, "kate") ~= nil)
	eq("and the home is the same shape",
		CeroSecOS.systemNode(state, "/home/kate").mode, CeroSecOS.HOME_MODE)
	eq("the machine still validates", CeroSecOS.validate(state), true)

	-- A list, and every group on it has to exist FIRST: a typo in the second name
	-- is a typo, and a typo must not leave an account behind it.
	okAt(state, rootSession, "groupadd crew", {})
	okAt(state, rootSession, "useradd -G crew,wheel liz", nil)
	-- The primary first, then /etc/group's own order -- wheel ships above the
	-- group groupadd appended -- and then the mirrored sudo, which is there
	-- because wheel is what grants it.
	eq("both memberships", table.concat(CeroSecOS.groupsOf(state, "liz"), ","),
		"liz,wheel,crew,sudo")
	badAt(state, rootSession, "useradd -G crew,nosuch mia",
		"useradd: nosuch: no such group")
	eq("and no account was made", CeroSecOS.getUser(state, "mia"), nil)
	badAt(state, rootSession, "useradd -G '' nan", "useradd: empty group list")
	eq("nor by an empty list", CeroSecOS.getUser(state, "nan"), nil)
end

-- An existing directory is adopted, not remade.
do
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "mkdir /home/carl", {})
	okAt(state, rootSession, "chmod 700 /home/carl", {})
	okAt(state, rootSession, "echo \"keep me\" > /home/carl/notes.txt", {})

	okAt(state, rootSession, "useradd carl", {
		"useradd: carl: created",
		"useradd: set a password with passwd carl",
	})
	local home = CeroSecOS.systemNode(state, "/home/carl")
	eq("it changed hands", home.owner, "carl")
	eq("and kept the mode it had", home.mode, 700)
	eq("and everything in it", home.children["notes.txt"].data, "keep me")

	-- A file at that name is not a home, and the refusal says so.
	okAt(state, rootSession, "echo hello > /home/dave", {})
	badAt(state, rootSession, "useradd dave", "useradd: /home/dave: not a directory")
	eq("and no account was made", CeroSecOS.getUser(state, "dave"), nil)
end

-- The account and its home stand or fall together.
do
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "rm -r /home", {})

	badAt(state, rootSession, "useradd eve", "useradd: /home/eve: no such file")
	eq("the line that was written is taken back out", CeroSecOS.getUser(state, "eve"), nil)
	check("and the accounts that were there are still there", holds(state, "admin", ""))
	eq("the machine still validates", CeroSecOS.validate(state), true)
end

-- sudo useradd: the way somebody who is not root makes an account.
do
	local state = fresh()
	local admin = open(state, "admin")
	local asked = run(state, admin, "sudo useradd -G wheel bob")
	eq("sudo asks for admin's password", asked.data.text, "[sudo] password for admin: ")
	local made = answer(state, admin, asked.data.cont, "")
	eq("it succeeds", made.ok, true)
	eq("and says so", made.lines[1], "useradd: bob: created")
	eq("the account is there", CeroSecOS.getUser(state, "bob").admin, true)
	eq("the home is his", CeroSecOS.systemNode(state, "/home/bob").owner, "bob")
	eq("and the console is still admin's", admin.user, "admin")
end

-- userdel: the guards, the two files, and the home.
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")
	okAt(state, rootSession, "useradd bob", nil)
	okAt(state, rootSession, "useradd carl", nil)

	badAt(state, admin, "userdel bob", "userdel: permission denied")
	badAt(state, rootSession, "userdel", "userdel: usage: userdel [-r] login")
	badAt(state, rootSession, "userdel -x bob", "userdel: -x: unknown option")
	badAt(state, rootSession, "userdel bob carl", "userdel: usage: userdel [-r] login")
	badAt(state, rootSession, "userdel nosuch", "userdel: nosuch: no such user")
	-- Root is the way back into the machine and is not one of the accounts.
	badAt(state, rootSession, "userdel root", "userdel: root: cannot remove")

	-- The account at the glass. The session running the command is root's --
	-- that is what sudo does -- and the guard is about who is logged in.
	local asRoot = open(state, "root")
	asRoot.login = "bob"
	badAt(state, asRoot, "userdel bob", "userdel: bob: user is logged in")
	-- And a user the glass would come back to through `exit`.
	asRoot.login = "carl"
	asRoot.stack = { { user = "bob", cwd = "/home/bob" } }
	badAt(state, asRoot, "userdel bob", "userdel: bob: user is logged in")
	check("neither of them was touched", CeroSecOS.getUser(state, "bob") ~= nil)

	-- Without -r the home stays exactly where it is, owned by a name the
	-- machine no longer knows.
	okAt(state, rootSession, "userdel bob", { "userdel: bob: removed" })
	eq("the account is gone", CeroSecOS.getUser(state, "bob"), nil)
	check("and cannot log in", CeroSecOS.login(state, "bob", "") == nil)
	local home = CeroSecOS.systemNode(state, "/home/bob")
	check("the home is still there", home ~= nil)
	eq("still owned by the name that is gone", home.owner, "bob")
	eq("and `ls -l` says so", okAt(state, rootSession, "ls -l /home", nil)[2],
		"drwxr-x---  bob    bob         0  Jul  8 14:32  bob")

	-- With -r it goes, and everything under it.
	okAt(state, rootSession, "echo hello > /home/carl/notes.txt", {})
	okAt(state, rootSession, "userdel -r carl", { "userdel: carl: removed" })
	eq("the account is gone", CeroSecOS.getUser(state, "carl"), nil)
	eq("and so is the home", CeroSecOS.systemNode(state, "/home/carl"), nil)
	eq("the machine still validates", CeroSecOS.validate(state), true)
end

-- The right to become root goes with the account.
do
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "useradd bob", nil)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH,
		"# who may\nadmin\nbob NOPASSWD")
	eq("bob may sudo", CeroSecOS.sudoer(state, "bob").nopasswd, true)

	okAt(state, rootSession, "userdel bob", { "userdel: bob: removed" })
	eq("and now he is nobody", CeroSecOS.sudoer(state, "bob"), nil)
	eq("admin kept his line", CeroSecOS.sudoer(state, "admin").name, "admin")
	eq("and the comment is still in the file",
		CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH).data, "# who may\nadmin")

	-- A machine with no /etc/sudoers at all has nothing to take out of it.
	okAt(state, rootSession, "useradd dan", nil)
	okAt(state, rootSession, "rm /etc/sudoers", {})
	okAt(state, rootSession, "userdel dan", { "userdel: dan: removed" })
end

-- `sudo userdel` on the account at the glass: the borrowed session knows who
-- typed the line, so an admin cannot delete himself out from under himself.
do
	local state = fresh()
	local admin = open(state, "admin")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin NOPASSWD")
	badAt(state, admin, "sudo userdel admin", "userdel: admin: user is logged in")
	check("and he is still there", CeroSecOS.getUser(state, "admin") ~= nil)
	-- Somebody else, though, goes.
	okAt(state, admin, "sudo useradd bob", nil)
	okAt(state, admin, "sudo userdel bob", { "userdel: bob: removed" })
end

-- id.
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")

	-- The primary group first, then the /etc/group lines that name the account,
	-- then sudo when /etc/sudoers is what puts it there. A shipped machine has
	-- admin in the sudo and users lines both.
	okAt(state, admin, "id", { "uid=admin flag=user groups=admin,sudo,users" })
	okAt(state, admin, "id root", { "uid=root flag=admin groups=root" })
	okAt(state, rootSession, "id", { "uid=root flag=admin groups=root" })
	badAt(state, admin, "id nosuch", "id: nosuch: no such user")
	badAt(state, admin, "id a b", "id: usage: id [name]")

	-- groups prints the very same list, blank-separated.
	okAt(state, admin, "groups", { "admin sudo users" })
	okAt(state, admin, "groups root", { "root" })
	badAt(state, admin, "groups nosuch", "groups: nosuch: no such user")
	badAt(state, admin, "groups a b", "groups: usage: groups [name]")

	-- A brand new account is in one group: its own.
	okAt(state, rootSession, "useradd bob", nil)
	okAt(state, admin, "id bob", { "uid=bob flag=user groups=bob" })
	okAt(state, admin, "groups bob", { "bob" })
	-- -G wheel: the group, the flag on the line, and the sudo the shipped
	-- /etc/sudoers grants it, all three off the one flag.
	okAt(state, rootSession, "useradd -G wheel kate", nil)
	okAt(state, admin, "id kate", { "uid=kate flag=admin groups=kate,wheel,sudo" })
	-- sudo is the SUDOERS file, whatever /etc/group says: it is the authority
	-- and the group mirrors it.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "bob")
	okAt(state, admin, "id bob", { "uid=bob flag=user groups=bob,sudo" })
	-- admin is in the sudo group by a LINE of /etc/group, which is a share and not
	-- a power: the sudoers file above no longer names him and he may not sudo.
	okAt(state, admin, "id admin", { "uid=admin flag=user groups=admin,sudo,users" })
	-- And a line of /etc/group is the other half of it.
	okAt(state, rootSession, "usermod -G users bob", {})
	okAt(state, admin, "id bob", { "uid=bob flag=user groups=bob,users,sudo" })
end

-- su: the stack, and what exit does with it.
do
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "useradd bob", nil)

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
	okAt(state, rootSession, "useradd bob", nil)
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
	okAt(state, rootSession, "userdel bob", nil)
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

-- `su` under sudo acts on the CONSOLE, because a shell of somebody else's at
-- this glass is the whole of what su is for. `exit` under sudo is not a command
-- at all. The rest of a borrowed session is untouched: `sudo cd` still moves
-- nobody.
do
	local state = fresh()
	local admin = open(state, "admin")
	addUser(state, "bob", "", "/home/bob", false)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin NOPASSWD")

	-- Root is asked for nobody's password, so the switch happens on the line that
	-- asked for it.
	okAt(state, admin, "sudo su bob", {})
	eq("the console is bob's", admin.user, "bob")
	eq("standing in his home", admin.cwd, "/home/bob")
	eq("one deep", #admin.stack, 1)
	okAt(state, admin, "whoami", { "bob" })
	-- And exit pops it, the way it pops any su.
	eq("exit pops", runAt(state, admin, "exit").control, nil)
	eq("back to admin", admin.user, "admin")
	eq("and the stack is empty", #admin.stack, 0)

	-- `sudo su` with no name is root's, as su on its own has always been.
	okAt(state, admin, "sudo su", {})
	eq("the console is root's", admin.user, "root")
	eq("exit pops", runAt(state, admin, "exit").control, nil)
	eq("back to admin", admin.user, "admin")

	-- The ceiling is the console's, and is the same four it always was.
	for i = 1, CeroSecOS.SU_MAX do
		okAt(state, admin, "sudo su root", {})
		eq("stack " .. i, #admin.stack, i)
	end
	badAt(state, admin, "sudo su root", "su: too many levels")
	eq("and it stayed four deep", #admin.stack, CeroSecOS.SU_MAX)

	-- `sudo exit` is not a command: a shell word has no file in /bin for sudo to
	-- look up, and real sudo says so in its own name.
	badAt(state, admin, "sudo exit", "sudo: exit: command not found")
	eq("and popped nothing", #admin.stack, CeroSecOS.SU_MAX)
	eq("with nobody switched", admin.user, "root")
	-- The console's own exit still pops.
	eq("exit pops", runAt(state, admin, "exit").control, nil)

	-- `sudo cd` moves nobody: cd only ever moves the session that is logged in,
	-- and sudo's is a copy of it.
	local where = admin.cwd
	okAt(state, admin, "sudo cd /", {})
	eq("sudo cd moved nobody", admin.cwd, where)
end

-- The same, through the password: the authority travels in the token and the
-- glass it belongs to is still the glass the switch lands on.
do
	local state = fresh()
	local admin = open(state, "admin")
	addUser(state, "bob", "", "/home/bob", false)

	local asked = run(state, admin, "sudo su bob")
	eq("sudo asks first", asked.data.text, "[sudo] password for admin: ")
	local switched = answer(state, admin, asked.data.cont, "")
	eq("it succeeds", switched.ok, true)
	eq("and says nothing", #switched.lines, 0)
	eq("the console is bob's", admin.user, "bob")
	eq("one deep", #admin.stack, 1)
	eq("and the glass it came back to is admin's", admin.stack[1].user, "admin")
end

-- A machine from the last rung is topped up with this rung's four commands.
do
	local state = fresh()
	state.sysv = 3
	local added = { "useradd", "userdel", "id", "su" }
	for i = 1, #added do state.fs.children.bin.children[added[i]] = nil end
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

	-- They really run on it.
	local rootSession = open(state, "root")
	okAt(state, rootSession, "id", { "uid=root flag=admin groups=root" })
	okAt(state, rootSession, "useradd bob", nil)

	-- And the BIOS repair ships them too.
	local broken = fresh()
	broken.fs.children.bin.children.useradd = nil
	broken.fs.children.bin.children.su = nil
	CeroSecOS.restoreSystem(broken)
	check("the repair puts useradd back", broken.fs.children.bin.children.useradd ~= nil)
	check("and su", broken.fs.children.bin.children.su ~= nil)
	eq("at this build", broken.sysv, CeroSecOS.SYSTEM_VERSION)
end

-- A machine from the rung before this one is topped up with the group commands
-- and with /etc/group, and nothing else on it is touched. `gpasswd` was one of
-- them and is not any more: SYSTEM_VERSION 16 retired that name for `usermod -G`,
-- so what a version-4 machine is topped up with is the four that are left.
do
	local state = fresh()
	state.sysv = 4
	local added = { "chgrp", "groupadd", "groupdel", "groups" }
	for i = 1, #added do state.fs.children.bin.children[added[i]] = nil end
	state.fs.children.etc.children.group = nil
	state.fs.children.home.children.admin.children["mine.txt"] =
		CeroSecOS.newFile("admin", 644, "keep me")
	-- A node from before this rung has no group at all. It stays that way: the
	-- upgrade tops up the system files, it does not walk the disk.
	local old = state.fs.children.home.children.admin.children["mine.txt"]
	old.group = nil

	eq("the upgrade has something to do", CeroSecOS.upgradeSystem(state), true)
	eq("and moves the number to this build", state.sysv, CeroSecOS.SYSTEM_VERSION)
	for i = 1, #added do
		local node = state.fs.children.bin.children[added[i]]
		check("/bin/" .. added[i] .. " was seeded", node ~= nil)
		eq("/bin/" .. added[i] .. " is root's", node.owner, "root")
		eq("/bin/" .. added[i] .. " is 755", node.mode, 755)
		eq("/bin/" .. added[i] .. " describes itself", node.data, CeroSecOS.commandDesc(added[i]))
	end
	local groupNode = state.fs.children.etc.children.group
	check("/etc/group was seeded", groupNode ~= nil)
	eq("/etc/group is root's", groupNode.owner, "root")
	eq("/etc/group is 644", groupNode.mode, CeroSecOS.GROUP_MODE)
	eq("/etc/group holds the shipped four", groupNode.data, CeroSecOS.defaultGroup())
	eq("the player's file was not touched", old.data, "keep me")
	eq("and still has no group of its own", old.group, nil)
	eq("which reads as its owner", CeroSecOS.groupOf(old), "admin")
	eq("it validates", CeroSecOS.validate(state), true)
	eq("and asked once only", CeroSecOS.upgradeSystem(state), false)

	-- A /etc/group somebody has been keeping is NOT rewritten. The one line the
	-- top-up adds to it is `wheel`, empty, because /etc/sudoers grants that group
	-- and `useradd -G wheel` puts an account in it (CeroSecOS.ensureWheel).
	local kept = fresh()
	kept.sysv = 4
	CeroSecOS.setData(kept, CeroSecOS.rootSession(), CeroSecOS.GROUP_PATH, "crew:admin")
	CeroSecOS.upgradeSystem(kept)
	eq("a group file that is there is left alone, wheel apart",
		kept.fs.children.etc.children.group.data,
		"crew:admin\n" .. CeroSecOS.WHEEL_GROUP .. ":")
	check("and nobody is in it", not CeroSecOS.inGroup(kept, "admin", CeroSecOS.WHEEL_GROUP))

	-- The BIOS repair, on the same terms: a file that still holds a group is
	-- kept, one that parses to nothing is written back.
	local broken = fresh()
	broken.fs.children.bin.children.groupadd = nil
	CeroSecOS.setData(broken, CeroSecOS.rootSession(), CeroSecOS.GROUP_PATH, "crew:admin")
	CeroSecOS.restoreSystem(broken)
	check("the repair puts groupadd back", broken.fs.children.bin.children.groupadd ~= nil)
	eq("and keeps a group file that still parses, wheel apart",
		broken.fs.children.etc.children.group.data,
		"crew:admin\n" .. CeroSecOS.WHEEL_GROUP .. ":")

	local wiped = fresh()
	CeroSecOS.setData(wiped, CeroSecOS.rootSession(), CeroSecOS.GROUP_PATH, "# nothing but this")
	CeroSecOS.restoreSystem(wiped)
	eq("a group file that parses to nothing is written back",
		wiped.fs.children.etc.children.group.data, CeroSecOS.defaultGroup())

	local gone = fresh()
	gone.fs.children.etc.children.group = nil
	CeroSecOS.restoreSystem(gone)
	eq("and a missing one is written back too",
		gone.fs.children.etc.children.group.data, CeroSecOS.defaultGroup())
end

-- A machine from the rung before this one is topped up with /bin/dev, and
-- nothing else on it is touched.
do
	local state = fresh()
	state.sysv = 5
	state.fs.children.bin.children.dev = nil
	state.fs.children.home.children.admin.children["mine.txt"] =
		CeroSecOS.newFile("admin", 644, "keep me")

	eq("the upgrade has something to do", CeroSecOS.upgradeSystem(state), true)
	eq("and moves the number to this build", state.sysv, CeroSecOS.SYSTEM_VERSION)
	local node = state.fs.children.bin.children.dev
	check("/bin/dev was seeded", node ~= nil)
	eq("/bin/dev is root's", node.owner, "root")
	eq("/bin/dev is 755", node.mode, 755)
	eq("/bin/dev describes itself", node.data, CeroSecOS.commandDesc("dev"))
	eq("the player's file was not touched",
		state.fs.children.home.children.admin.children["mine.txt"].data, "keep me")
	eq("it validates", CeroSecOS.validate(state), true)
	eq("and asked once only", CeroSecOS.upgradeSystem(state), false)

	-- It really runs on it.
	okAt(state, open(state, "root"), "dev", {}, { now = FIXED })

	-- And the BIOS repair ships it too.
	local broken = fresh()
	broken.fs.children.bin.children.dev = nil
	CeroSecOS.restoreSystem(broken)
	check("the repair puts dev back", broken.fs.children.bin.children.dev ~= nil)
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
				pos = e.pos, state = e.state, mode = e.mode, dead = e.dead, ro = e.ro }
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

	-- The optional third call. A fake world points at a device by writing down
	-- that it was asked to; what a real one does is SCeroSecDevices' business
	-- and window_test's (a light blinks, a door is outlined on one screen).
	devices.finds = {}
	devices.find = function(id, seconds)
		devices.finds[#devices.finds + 1] = id .. "/" .. tostring(seconds)
		local e = byId[id]
		if e == nil then return false, "no such device" end
		if e.refuse ~= nil then return false, e.refuse end
		if e.kind == "light" then return true, nil, "blinking" end
		return true, nil, "highlighted"
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
		{ id = "light0", kind = "light", desc = "office", side = "", pos = "0 0",
			state = "on", becomes = ONOFF },
		{ id = "light1", kind = "light", desc = "hallway", side = "", pos = "3E 2N",
			state = "off", becomes = ONOFF },
		{ id = "lock0", kind = "lock", desc = "exterior", side = "W", pos = "0 5S",
			state = "locked", becomes = LOCKING },
		{ id = "lock1", kind = "lock", desc = "kitchen-hallway", side = "N",
			pos = "2W 1N", state = "unlocked", becomes = LOCKING },
		{ id = "win0", kind = "win", desc = "office", side = "N", pos = "1E 0",
			state = "locked", becomes = LOCKING },
		{ id = "lock2", kind = "lock", desc = "built", side = "N", pos = "4E 9S +1",
			state = "padlock", becomes = { lock = "padlock", unlock = "unlocked" } },
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
		"crw-rw----  root  sudo  light0  office            on",
		"crw-rw----  root  sudo  light1  hallway           off",
		"crw-rw----  root  sudo  lock0   exterior       W  locked",
		"crw-rw----  root  sudo  lock1   kitchen-hall~  N  unlocked",
		"crw-rw----  root  sudo  lock2   built          N  padlock",
		-- The hole in the disk, which is the one device on it: no description, no
		-- place in the building, no state, so the line ends at the name.
		"crw-rw-rw-  root  root  null",
		"crw-rw----  root  sudo  win0    office         N  locked",
	}, env)

	-- The short form is names, columnized like any other directory.
	okAt(state, session, "ls /dev", {
		"light0  light1  lock0   lock1   lock2   null    win0",
	}, env)

	-- The widest state there is still fits the glass.
	local wide = fakeDevices({
		{ id = "win12", kind = "win", desc = "kitchen-hallway", side = "N",
			state = "barricaded" },
	})
	-- The second line: "null" sorts before "win12" and the widest WORLD device is
	-- what this is about.
	local line = okAt(state, session, "ls -l /dev", nil, devEnv(wide))[2]
	eq("the widest device line", line,
		"crw-rw----  root  sudo  win12   kitchen-hall~  N  barricaded")
	check("and it fits the screen", #line <= CeroSecOS.COLS)

	-- A device is a character device and wears the letter for one.
	eq("the type letter", string.sub(line, 1, 1), "c")

	-- Named straight rather than listed.
	okAt(state, session, "ls -l /dev/lock1",
		{ "crw-rw----  root  sudo  lock1   kitchen-hall~  N  unlocked" }, env)
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
	okAt(state, session, "echo lock > /root/v.txt", {}, env)
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
	-- The four that are there, plus the machine's own hole in the disk.
	eq("nor in the long listing", #long, 5 + 1)
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

	-- 660 with group sudo: root's, and the sudo group's -- which is /etc/sudoers,
	-- so admin throws the switch with no sudo typed, and bob, who is in no
	-- group of the machine's but his own, gets nothing at all.
	local admin = open(state, "admin")
	okAt(state, root, "useradd bob", nil)
	local bob = open(state, "bob")

	okAt(state, admin, "cat /dev/light0", { "on" }, env)
	okAt(state, admin, "echo off > /dev/light0", {}, env)
	eq("the world was told", devices.writes[#devices.writes], "light0=off")
	okAt(state, admin, "echo on > /dev/light0", {}, env)

	local reached = #devices.writes
	badAt(state, bob, "cat /dev/light0", "light0: permission denied", env)
	badAt(state, bob, "echo off > /dev/light0", "light0: permission denied", env)
	eq("and nothing of bob's reached the world", #devices.writes, reached)
	-- The listing is the directory's business, not the device's: /dev is 755.
	okAt(state, bob, "ls -l /dev", nil, env)

	-- Two ways into the group, and either is enough. bob is in no line of
	-- /etc/group at all; naming him in /etc/sudoers puts him in the sudo group,
	-- because that file is the authority on it and the group mirrors it.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin\nbob")
	okAt(state, bob, "cat /dev/light0", { "on" }, env)
	eq("and it is not a line of /etc/group that put him there",
		string.find(CeroSecOS.systemNode(state, CeroSecOS.GROUP_PATH).data, "bob", 1, true), nil)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin")
	badAt(state, bob, "cat /dev/light0", "light0: permission denied", env)
	-- admin's own way in is the shipped /etc/group line, which outlives the
	-- sudoers file being emptied.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "# nobody")
	okAt(state, admin, "cat /dev/light0", { "on" }, env)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin")

	-- Root opens it up to everybody, and the new mode is handed to the world to
	-- remember -- the node itself is gone by the end of the command.
	okAt(state, root, "chmod 666 /dev/light0", {}, env)
	eq("the mode was handed over once", #devices.chmods, 1)
	eq("and what it was", devices.chmods[1], "light0=666")

	okAt(state, bob, "cat /dev/light0", { "on" }, env)
	okAt(state, bob, "echo off > /dev/light0", {}, env)
	okAt(state, bob, "cat /dev/light0", { "off" }, env)
	eq("the mode shows in the listing",
		okAt(state, root, "ls -l /dev/light0", nil, env)[1],
		"crw-rw-rw-  root  sudo  light0  office            off")

	-- A mode nobody moved is not handed over again.
	local before = #devices.chmods
	okAt(state, root, "cat /dev/light0", nil, env)
	eq("no chmod for a read", #devices.chmods, before)

	-- Shut again, and root still walks through it -- and so does nobody else,
	-- sudo group or not.
	okAt(state, root, "chmod 000 /dev/light0", {}, env)
	badAt(state, admin, "cat /dev/light0", "light0: permission denied", env)
	badAt(state, bob, "cat /dev/light0", "light0: permission denied", env)
	okAt(state, root, "cat /dev/light0", { "off" }, env)

	-- And a device's group is not given away: it is what makes 660 mean what it
	-- means, and only the mode of a device outlives the command.
	badAt(state, root, "chgrp users /dev/light0", "chgrp: /dev/light0: is a device", env)
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
	okAt(state, session, "echo hi > /root/x.txt", {}, env)
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

	-- Nothing of the WORLD is left on it: what is there between commands is the
	-- machine's own null device and nothing else.
	eq("/dev holds only the hole between commands",
		CeroSecOS.countEntries(state.fs.children.dev), 1)
	eq("and that is what it is",
		CeroSecOS.isNull(state.fs.children.dev.children.null), true)
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

	-- A machine with nothing around it still has the hole in its disk, and
	-- nothing else: that is the machine of every earlier rung plus one node.
	okAt(state, session, "ls /dev", { "null" }, { now = FIXED })
	okAt(state, session, "ls -l /dev", { "crw-rw-rw-  root  root  null" },
		{ now = FIXED })
	badAt(state, session, "cat /dev/light0", "cat: /dev/light0: no such file", { now = FIXED })
end

-- 21h. A chain that ends in a device: the mount is under continue too.
do
	local state = fresh()
	local session = open(state, "admin")
	local devices = mockupDevices()
	local env = devEnv(devices)

	local step = { exec(state, session, "sudo cat /dev/light0", env) }
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
		okAt(state, session, "ls /dev", { "null" }, junk[i])
		eq("and nothing of the world reaches /dev",
			CeroSecOS.countEntries(state.fs.children.dev), 1)
	end

	-- An entry that is not one is dropped; the rest are mounted.
	local devices = fakeDevices({
		{ id = "light0", kind = "light", desc = "office", side = "", state = "on" },
		{ id = "-bad", kind = "light", desc = "x", side = "", state = "on" },
		{ id = "nokind", kind = "toaster", desc = "x", side = "", state = "on" },
		{ id = "light1", kind = "light", desc = "hall", side = "", state = "off" },
	})
	okAt(state, session, "ls /dev", { "light0  light1  null" }, devEnv(devices))
end

-- 21j. `dev`: the table, and how it is ordered.
--
-- The everyday face of the same nodes. It reads and writes through devRead and
-- devWrite, exactly as `cat` and a redirect do, so what is proved here is the
-- table, the filter, the toggle and the grammar of its own refusals -- the
-- permissions and the world's answers are 21b to 21e's and are not re-proved,
-- except where they arrive by a different road (21m).
do
	local state = fresh()
	local session = open(state, "root")
	local env = devEnv(mockupDevices())

	-- Columns: 8 id + 20 desc + 2 + 10 pos + 2 + 1 side + 2 + state. The same
	-- columns as `ls -l /dev` (21a) without the mode, the owner and the group,
	-- plus the offset -- which is what tells two doors of one room apart and
	-- which `ls -l` has no room left for.
	okAt(state, session, "dev", {
		"light0  office                0 0            on",
		"light1  hallway               3E 2N          off",
		"lock0   exterior              0 5S        W  locked",
		"lock1   kitchen-hallway       2W 1N       N  unlocked",
		"lock2   built                 4E 9S +1    N  padlock",
		"win0    office                1E 0        N  locked",
	}, env)

	-- By KIND and then by NUMBER, which is what a listing sorted by name -- every
	-- other listing on this machine -- cannot do: light2 belongs before light10.
	-- A description of exactly 20 fits, and so does the widest offset there is
	-- ("10E 10N -1", ten); longer is cut with a tilde, the way everything on
	-- this screen is cut.
	local wide = fakeDevices({
		{ id = "light10", kind = "light", desc = "warehouse-loading", side = "",
			pos = "12W 30S", state = "off" },
		{ id = "light2", kind = "light", desc = "office", side = "", pos = "0 0",
			state = "on" },
		{ id = "win12", kind = "win", desc = "kitchen-hallway-pant", side = "N",
			pos = "10E 10N -1", state = "barricaded" },
		{ id = "win3", kind = "win", desc = "a description of twenty-six", side = "W",
			pos = "1W 0", state = "smashed" },
	})
	local lines = okAt(state, session, "dev", {
		"light2  office                0 0            on",
		"light10 warehouse-loading     12W 30S        off",
		"win3    a description of tw~  1W 0        W  smashed",
		"win12   kitchen-hallway-pant  10E 10N -1  N  barricaded",
	}, devEnv(wide))
	eq("the widest line there is", #lines[4], 55)
	check("and it fits the screen", #lines[4] <= CeroSecOS.COLS)

	-- One kind at a time.
	okAt(state, session, "dev light", {
		"light0  office                0 0            on",
		"light1  hallway               3E 2N          off",
	}, env)
	okAt(state, session, "dev lock", {
		"lock0   exterior              0 5S        W  locked",
		"lock1   kitchen-hallway       2W 1N       N  unlocked",
		"lock2   built                 4E 9S +1    N  padlock",
	}, env)
	okAt(state, session, "dev win", { "win0    office                1E 0        N  locked" },
		env)

	-- A kind nothing answers to right now is an empty table, not a refusal: the
	-- kind is a real one and the building simply has none of it.
	okAt(state, session, "dev win", {}, devEnv(fakeDevices({
		{ id = "light0", kind = "light", desc = "office", side = "", pos = "0 0",
			state = "on" },
	})))

	-- A machine with no devices at all is the machine of every earlier rung.
	okAt(state, session, "dev", {}, { now = FIXED })
	okAt(state, session, "dev light", {}, { now = FIXED })

	-- A device the machine remembers the number of and cannot reach is not on
	-- the table, exactly as it is not in `ls /dev` (21d).
	local withDead = fakeDevices({
		{ id = "light0", kind = "light", desc = "office", side = "", pos = "0 0",
			state = "on" },
		{ id = "lock9", kind = "lock", dead = true },
	})
	okAt(state, session, "dev", { "light0  office                0 0            on" },
		devEnv(withDead))
	okAt(state, session, "dev lock", {}, devEnv(withDead))
end

-- 21k. `dev <id>` and `dev <id> <value>`: the same road cat and a redirect take.
do
	local state = fresh()
	local session = open(state, "root")
	local devices = mockupDevices()
	local env = devEnv(devices)

	-- Reading one names it, where `cat` prints the bare state and nothing else.
	okAt(state, session, "dev light0", { "light0: on" }, env)
	okAt(state, session, "dev lock2", { "lock2: padlock" }, env)
	okAt(state, session, "cat /dev/light0", { "on" }, env)

	-- Writing one is the redirect's own order, and the answer is the state the
	-- world was re-read for -- not the word that was typed.
	okAt(state, session, "dev light0 off", { "light0: off" }, env)
	eq("the world was told once", #devices.writes, 1)
	eq("and what it was told", devices.writes[1], "light0=off")
	okAt(state, session, "cat /dev/light0", { "off" }, env)
	okAt(state, session, "dev lock1 lock", { "lock1: locked" }, env)
	okAt(state, session, "dev win0 unlock", { "win0: unlocked" }, env)

	-- A padlock says padlock and not locked, because that is what came back.
	okAt(state, session, "dev lock2 unlock", { "lock2: unlocked" }, env)
	okAt(state, session, "dev lock2 lock", { "lock2: padlock" }, env)

	-- toggle: the opposite of what it reads NOW, in the words the kind takes.
	okAt(state, session, "dev light0 toggle", { "light0: on" }, env)
	eq("and the world got a word, not \"toggle\"", devices.writes[#devices.writes],
		"light0=on")
	okAt(state, session, "dev light0 toggle", { "light0: off" }, env)
	okAt(state, session, "dev lock1 toggle", { "lock1: unlocked" }, env)
	eq("the door was unlocked", devices.writes[#devices.writes], "lock1=unlock")
	okAt(state, session, "dev lock1 toggle", { "lock1: locked" }, env)
	-- A padlocked door toggles like a locked one: unlock is what takes a padlock
	-- off, and lock is what puts it back on the door that carries one.
	okAt(state, session, "dev lock2 toggle", { "lock2: unlocked" }, env)
	eq("the padlock came off with unlock", devices.writes[#devices.writes], "lock2=unlock")
	okAt(state, session, "dev lock2 toggle", { "lock2: padlock" }, env)
	eq("and went back on with lock", devices.writes[#devices.writes], "lock2=lock")

	-- And the same machine, reached the old way, agrees about all of it.
	okAt(state, session, "cat /dev/lock2", { "padlock" }, env)
	okAt(state, session, "echo unlock > /dev/lock2", {}, env)
	okAt(state, session, "dev lock2", { "lock2: unlocked" }, env)
end

-- 21l. Every refusal dev makes. A device's is the DEVICE's, word for word what
-- the redirect answers; dev's own two are a command's and are signed like one.
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

	-- The world's own answers, identical to 21d's.
	badAt(state, session, "dev light0 on", "light0: no power", env)
	badAt(state, session, "dev win0 lock", "win0: smashed", env)
	badAt(state, session, "dev win1 lock", "win1: barricaded", env)
	badAt(state, session, "dev lock2 lock", "lock2: no padlock", env)

	-- A word the kind has no meaning for never reaches the world, and neither
	-- does a toggle of a state that has no opposite: a smashed or a barricaded
	-- window is in no state a word undoes, so dev says so instead of guessing a
	-- direction. `dev win0 lock` above is the one that does ask, and the world
	-- is the one that refuses it.
	local reached = #devices.writes
	badAt(state, session, "dev light1 yes", "light1: invalid value", env)
	badAt(state, session, "dev light1 lock", "light1: invalid value", env)
	badAt(state, session, "dev win0 toggle", "win0: cannot toggle", env)
	badAt(state, session, "dev win1 toggle", "win1: cannot toggle", env)
	eq("nothing of that reached the world", #devices.writes, reached)

	-- A number the machine remembers and cannot reach is the device's own
	-- refusal; a number nobody ever gave out is dev's, and says so with dev's
	-- name in front of it -- the same split `cat` makes between "no such
	-- device" and "no such file".
	badAt(state, session, "dev lock9", "lock9: no such device", env)
	badAt(state, session, "dev lock9 lock", "lock9: no such device", env)
	badAt(state, session, "dev light7", "dev: light7: no such device", env)
	badAt(state, session, "dev light7 on", "dev: light7: no such device", env)
	badAt(state, session, "dev light0/x on", "dev: light0/x: no such device", env)

	-- A word with no number on the end of it is a kind, and there are three.
	badAt(state, session, "dev toaster", "dev: toaster: unknown kind", env)
	badAt(state, session, "dev lights", "dev: lights: unknown kind", env)
	badAt(state, session, "dev /dev", "dev: /dev: unknown kind", env)
	-- ...but with one, it is an id, and a miss there is a miss about a device.
	badAt(state, session, "dev toaster3", "dev: toaster3: no such device", env)

	-- The usage line, and it is the one man prints (21 lines above use it).
	local line = "dev: usage: dev [kind|id [value|toggle]|find <id>]"
	badAt(state, session, "dev light1 on now", line, env)
	badAt(state, session, "dev a b c d", line, env)
	eq("and man says the same thing", okAt(state, session, "man dev", nil, env)[2],
		"usage: " .. CeroSecOS.commandUsage("dev"))

	-- /dev is not a directory anybody writes in, and dev is not a way in.
	badAt(state, session, "dev light1 on > /dev/mine", "dev: /dev/mine: read-only", env)
end

-- 21m. Who may. The node's own 660 and group sudo, reached through dev instead
-- of through cat -- the same devRead and devWrite, so the same three answers.
do
	local state = fresh()
	local root = open(state, "root")
	local devices = mockupDevices()
	local env = devEnv(devices)
	local admin = open(state, "admin")
	okAt(state, root, "useradd bob", nil)
	local bob = open(state, "bob")

	-- root, and admin, who is in /etc/sudoers and so in the group sudo.
	okAt(state, root, "dev light0", { "light0: on" }, env)
	okAt(state, admin, "dev light0", { "light0: on" }, env)
	okAt(state, admin, "dev light0 off", { "light0: off" }, env)
	okAt(state, admin, "dev light0 toggle", { "light0: on" }, env)

	-- bob, who is in no group of the machine's but his own.
	local reached = #devices.writes
	badAt(state, bob, "dev light0", "light0: permission denied", env)
	badAt(state, bob, "dev light0 off", "light0: permission denied", env)
	badAt(state, bob, "dev light0 toggle", "light0: permission denied", env)
	eq("and nothing of bob's reached the world", #devices.writes, reached)

	-- The table is the DIRECTORY's business and /dev is 755, exactly as
	-- `ls -l /dev` is his to read (21e): what he may not do is touch one.
	okAt(state, bob, "dev", nil, env)
	okAt(state, bob, "dev light", nil, env)

	-- Through sudo, since he may not otherwise -- and the chain reads the switch
	-- on the answer, the mount being under continue too (21h).
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin\nbob")
	local step = { exec(state, bob, "sudo dev light0 off", env) }
	eq("sudo asks first", step[3], "prompt")
	local ok2, lines = CeroSecOS.continue(state, bob, step[4].cont, "", env)
	eq("and works the switch as root", ok2, true)
	eq("what it said", lines[1], "light0: off")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin")

	-- A mode root opened is a mode dev honours, because it is the same node.
	okAt(state, root, "chmod 666 /dev/light0", {}, env)
	okAt(state, bob, "dev light0", { "light0: off" }, env)
	okAt(state, bob, "dev light0 on", { "light0: on" }, env)
	okAt(state, root, "chmod 000 /dev/light0", {}, env)
	badAt(state, admin, "dev light0", "light0: permission denied", env)
	okAt(state, root, "dev light0", { "light0: on" }, env)
end

-- 21n. `dev find <id>`: point at one in the world.
do
	local state = fresh()
	local session = open(state, "root")
	local devices = mockupDevices()
	local env = devEnv(devices)

	-- The word is the WORLD's: the engine hands the seconds over and prints
	-- back whatever it was told was done.
	okAt(state, session, "dev find light0", { "light0: blinking" }, env)
	eq("the world was asked once", #devices.finds, 1)
	eq("and for how long", devices.finds[1], "light0/" .. CeroSecOS.DEV_FIND_SECONDS)
	okAt(state, session, "dev find lock1", { "lock1: highlighted" }, env)
	okAt(state, session, "dev find win0", { "win0: highlighted" }, env)

	-- Nothing about the device moves: find asks a question, it does not answer
	-- one with a write.
	okAt(state, session, "dev light0", { "light0: on" }, env)
	eq("and no write went out", #devices.writes, 0)

	-- "find" is a word here and not an id, so a machine with no devices at all
	-- still parses the line and still refuses it about the DEVICE.
	badAt(state, session, "dev find light9", "dev: light9: no such device", env)
	badAt(state, session, "dev find", "dev: usage: dev [kind|id [value|toggle]|find <id>]",
		env)
	badAt(state, session, "dev find light0 now",
		"dev: usage: dev [kind|id [value|toggle]|find <id>]", env)

	-- The world's own refusal, in the device's name, exactly as a write's is.
	local dark = fakeDevices({
		{ id = "light0", kind = "light", desc = "office", side = "", pos = "0 0",
			state = "off", refuse = "no power" },
		{ id = "lock9", kind = "lock", dead = true },
	})
	badAt(state, session, "dev find light0", "light0: no power", devEnv(dark))
	badAt(state, session, "dev find lock9", "lock9: no such device", devEnv(dark))

	-- A caller with no find() at all is a machine whose devices cannot be
	-- pointed at, and it says so about the device rather than about the command.
	local blind = mockupDevices()
	blind.find = nil
	badAt(state, session, "dev find light0", "light0: no such device", devEnv(blind))
end

-- 21o. What find asks for is what it DOES: a light is switched twelve times, so
-- it takes a write's right; a door is only drawn around, so a read's is enough.
do
	local state = fresh()
	local root = open(state, "root")
	local devices = mockupDevices()
	local env = devEnv(devices)
	local admin = open(state, "admin")
	okAt(state, root, "useradd bob", nil)
	local bob = open(state, "bob")

	okAt(state, admin, "dev find light0", { "light0: blinking" }, env)
	badAt(state, bob, "dev find light0", "light0: permission denied", env)
	badAt(state, bob, "dev find lock1", "lock1: permission denied", env)

	-- 640 for everybody: bob may read it and may not write it. He may point at
	-- the door and may not blink the light.
	okAt(state, root, "chmod 644 /dev/light0", {}, env)
	okAt(state, root, "chmod 644 /dev/lock1", {}, env)
	okAt(state, bob, "dev lock1", { "lock1: unlocked" }, env)
	okAt(state, bob, "dev find lock1", { "lock1: highlighted" }, env)
	badAt(state, bob, "dev find light0", "light0: permission denied", env)
	badAt(state, bob, "dev light0 off", "light0: permission denied", env)
	-- ...and with the write digit, he may.
	okAt(state, root, "chmod 646 /dev/light0", {}, env)
	okAt(state, bob, "dev find light0", { "light0: blinking" }, env)
end


-- 21p. The `door` kind, on the engine's side of the line.
--
-- The mockup above (21a) predates doors and is left exactly as it was approved;
-- the door rows live here. Everything the engine knows about a door is: three
-- state words, two value words, a toggle table of its own, and the refusals its
-- world hands back. WHICH doors are devices and which of them also carry a lock
-- is the server's business and is proved in tests/window_test.lua against a
-- world -- the core cannot know, and must not guess.
local DOORING = { open = "open", close = "closed" }

local function doorDevices()
	return fakeDevices({
		{ id = "door0", kind = "door", desc = "exterior", side = "W",
			pos = "0 5S", state = "locked", becomes = DOORING },
		{ id = "door1", kind = "door", desc = "kitchen-hallway", side = "N",
			pos = "2W 1N", state = "closed", becomes = DOORING },
		{ id = "door2", kind = "door", desc = "built", side = "N",
			pos = "4E 9S +1", state = "open", becomes = DOORING },
		-- The lock beside door0: one door in the world, two devices here.
		{ id = "lock0", kind = "lock", desc = "exterior", side = "W",
			pos = "0 5S", state = "locked", becomes = LOCKING },
	})
end

do
	local state = fresh()
	local session = open(state, "root")
	local env = devEnv(doorDevices())

	-- `ls -l /dev`, to the character. The columns did not move: "barricaded" is
	-- still the widest state there is and an id of eight still holds door127.
	okAt(state, session, "ls -l /dev", {
		"crw-rw----  root  sudo  door0   exterior       W  locked",
		"crw-rw----  root  sudo  door1   kitchen-hall~  N  closed",
		"crw-rw----  root  sudo  door2   built          N  open",
		"crw-rw----  root  sudo  lock0   exterior       W  locked",
		"crw-rw-rw-  root  root  null",
	}, env)
	okAt(state, session, "ls /dev", { "door0  door1  door2  lock0  null" }, env)

	local wide = fakeDevices({
		{ id = "door127", kind = "door", desc = "kitchen-hallway", side = "N",
			state = "barricaded" },
	})
	-- The first line: "door127" sorts before "null".
	local line = okAt(state, session, "ls -l /dev", nil, devEnv(wide))[1]
	eq("the widest door line", line,
		"crw-rw----  root  sudo  door127 kitchen-hall~  N  barricaded")
	check("and it fits the screen", #line <= CeroSecOS.COLS)

	-- `dev`, whole and by kind. door sorts before light, lock and win, being a
	-- kind like any other and sorted like one.
	okAt(state, session, "dev", {
		"door0   exterior              0 5S        W  locked",
		"door1   kitchen-hallway       2W 1N       N  closed",
		"door2   built                 4E 9S +1    N  open",
		"lock0   exterior              0 5S        W  locked",
	}, env)
	okAt(state, session, "dev door", {
		"door0   exterior              0 5S        W  locked",
		"door1   kitchen-hallway       2W 1N       N  closed",
		"door2   built                 4E 9S +1    N  open",
	}, env)

	-- Reading one, through cat and through dev: the same node either way.
	okAt(state, session, "cat /dev/door0", { "locked" }, env)
	okAt(state, session, "cat /dev/door1", { "closed" }, env)
	okAt(state, session, "cat /dev/door2", { "open" }, env)
	okAt(state, session, "dev door1", { "door1: closed" }, env)
end

do
	-- Writing one. The two words, both roads, and the state that comes back
	-- from the world rather than from the order.
	local state = fresh()
	local session = open(state, "root")
	local devices = doorDevices()
	local env = devEnv(devices)

	okAt(state, session, "dev door1 open", { "door1: open" }, env)
	eq("the order reached the world", devices.writes[1], "door1=open")
	okAt(state, session, "cat /dev/door1", { "open" }, env)
	okAt(state, session, "dev door1 close", { "door1: closed" }, env)
	okAt(state, session, "echo open > /dev/door1", {}, env)
	okAt(state, session, "cat /dev/door1", { "open" }, env)
	okAt(state, session, "echo close > /dev/door1", {}, env)
	okAt(state, session, "cat /dev/door1", { "closed" }, env)

	-- toggle. A door's opposites are its OWN: "locked" is undone by "open" here
	-- and by "unlock" on a lock, and neither kind has ever heard of the other's
	-- word.
	okAt(state, session, "dev door1 toggle", { "door1: open" }, env)
	okAt(state, session, "dev door1 toggle", { "door1: closed" }, env)
	okAt(state, session, "dev door2 toggle", { "door2: closed" }, env)
	local reached = #devices.writes
	okAt(state, session, "dev door0 toggle", nil, env)
	eq("a locked door toggles by asking to be opened",
		devices.writes[reached + 1], "door0=open")

	-- And a word the other kind knows is no word at all here.
	badAt(state, session, "dev door1 unlock", "door1: invalid value", env)
	badAt(state, session, "dev door1 lock", "door1: invalid value", env)
	badAt(state, session, "dev door1 on", "door1: invalid value", env)
	badAt(state, session, "echo unlock > /dev/door1", "door1: invalid value", env)
	badAt(state, session, "dev lock0 open", "lock0: invalid value", env)
end

do
	-- Every refusal a door's world makes, in the door's own name, and the two
	-- that are the command's.
	local state = fresh()
	local session = open(state, "root")
	local devices = fakeDevices({
		{ id = "door0", kind = "door", desc = "exterior", side = "W",
			state = "locked", refuse = "locked" },
		{ id = "door1", kind = "door", desc = "office-hall", side = "N",
			state = "closed", refuse = "barricaded" },
		{ id = "door2", kind = "door", desc = "built", side = "N",
			state = "closed", refuse = "blocked" },
		{ id = "door9", kind = "door", dead = true },
	})
	local env = devEnv(devices)

	badAt(state, session, "dev door0 open", "door0: locked", env)
	badAt(state, session, "dev door0 toggle", "door0: locked", env)
	badAt(state, session, "echo open > /dev/door0", "door0: locked", env)
	badAt(state, session, "dev door1 open", "door1: barricaded", env)
	badAt(state, session, "dev door2 close", "door2: blocked", env)

	-- A number the machine remembers and cannot reach: mounted, never listed,
	-- and "no such device" rather than "no such file".
	badAt(state, session, "cat /dev/door9", "door9: no such device", env)
	badAt(state, session, "dev door9 open", "door9: no such device", env)
	badAt(state, session, "dev find door9", "door9: no such device", env)
	okAt(state, session, "dev door", {
		"door0   exterior                          W  locked",
		"door1   office-hall                       N  closed",
		"door2   built                             N  closed",
	}, env)

	-- A number never handed out is the COMMAND's refusal, being a name nothing
	-- answers to rather than a device with something to say.
	badAt(state, session, "dev door7", "dev: door7: no such device", env)
	badAt(state, session, "dev door7 open", "dev: door7: no such device", env)

	-- A door is only drawn around, so pointing at one takes a read's right, and
	-- the word is the world's -- including when the world refuses.
	badAt(state, session, "dev find door1", "door1: barricaded", env)
	okAt(state, session, "dev find door1", { "door1: highlighted" }, devEnv(doorDevices()))
end

--
-- 21q. The `sensor` kind: the one device that is only ever READ.
--
-- Where the world's sensors come from, what a field of view is and when a contact
-- closes is the server's business and is proved in tests/window_test.lua against
-- a world. The engine's whole half is this: a kind with NO vocabulary at all, a
-- mode of 440 to say so, and a write that never reaches the caller.
--
-- Empty and not absent is the thing that matters here. A kind CeroSecOS.DEV_VALUES
-- has no entry for is an entry nodeFor throws away -- so a sensor mounted through
-- an absent kind would be no device at all, and one mounted through a kind with a
-- word in it would be a machine promising something it cannot do.
local function sensorDevices()
	return fakeDevices({
		{ id = "sensor0", kind = "sensor", desc = "office", side = "",
			pos = "1E 0", state = "clear", mode = 440 },
		{ id = "sensor1", kind = "sensor", desc = "store", side = "",
			pos = "4E 2S", state = "motion", mode = 440 },
		{ id = "light0", kind = "light", desc = "office", side = "", pos = "0 0",
			state = "on", becomes = ONOFF },
	})
end

do
	-- The mode a kind is born at, which is the one thing the world asks the engine
	-- rather than the other way round.
	eq("a sensor is born read-only", CeroSecOS.devModeFor("sensor"), 440)
	eq("and every other kind at 660", CeroSecOS.devModeFor("light"), CeroSecOS.DEV_MODE)
	eq("a kind nobody has heard of too", CeroSecOS.devModeFor("toaster"),
		CeroSecOS.DEV_MODE)

	local state = fresh()
	local session = open(state, "root")
	local devices = sensorDevices()
	local env = devEnv(devices)

	-- cr--r-----: read for root and for sudo, write for nobody at all. No side
	-- column -- a head lying on a floor does not face a way -- so the state sits
	-- where a window's does with two blanks in front of it.
	okAt(state, session, "ls -l /dev", {
		"crw-rw----  root  sudo  light0  office            on",
		"crw-rw-rw-  root  root  null",
		"cr--r-----  root  sudo  sensor0 office            clear",
		"cr--r-----  root  sudo  sensor1 store             motion",
	}, env)

	-- Reading one, both ways round, and both words.
	okAt(state, session, "cat /dev/sensor0", { "clear" }, env)
	okAt(state, session, "cat /dev/sensor1", { "motion" }, env)
	okAt(state, session, "dev sensor0", { "sensor0: clear" }, env)
	okAt(state, session, "dev sensor1", { "sensor1: motion" }, env)

	-- The kind filters, which it can only do because the kind is in DEV_VALUES.
	okAt(state, session, "dev sensor", {
		"sensor0 office                1E 0           clear",
		"sensor1 store                 4E 2S          motion",
	}, env)

	-- And every word there is refused, in the sensor's own name. Root included:
	-- the mode is not what stops this, the vocabulary is.
	local WORDS = { "on", "off", "open", "close", "lock", "unlock", "motion",
		"clear", "yes", "1", "" }
	for i = 1, #WORDS do
		badAt(state, session, "echo " .. WORDS[i] .. " > /dev/sensor0",
			"sensor0: invalid value", env)
		if WORDS[i] ~= "" then
			badAt(state, session, "dev sensor0 " .. WORDS[i],
				"sensor0: invalid value", env)
		end
	end

	-- The assertion the rest of it rests on: the WORLD was never asked. A refusal
	-- that happened after the caller had been told to do something would be a
	-- sensor that could be changed by somebody who typed the right word.
	eq("nothing was ever written to a sensor's world", #devices.writes, 0)

	-- Nothing to toggle: there is no opposite of a fact.
	badAt(state, session, "dev sensor0 toggle", "sensor0: cannot toggle", env)

	-- Pointing at one takes a READ's right, which is all a sensor has to give.
	okAt(state, session, "dev find sensor0", { "sensor0: highlighted" }, env)

	-- 440 keeps everybody else out, and a chmod moves it and is remembered.
	local admin = open(state, "admin")
	okAt(state, admin, "cat /dev/sensor0", { "clear" }, env)
	okAt(state, session, "useradd bob", nil)
	local bob = open(state, "bob")
	badAt(state, bob, "cat /dev/sensor0", "sensor0: permission denied", env)
	okAt(state, session, "chmod 444 /dev/sensor0", {}, env)
	eq("the chmod went back to the caller", devices.chmods[1], "sensor0=444")
	okAt(state, bob, "cat /dev/sensor0", { "clear" }, env)
	-- Opening the READ to everybody opened no write, and the two refusals are not
	-- the same one: the mode is judged BEFORE the vocabulary, so a stranger with
	-- no `w` is told he may not and root is told there is nothing to say. Both are
	-- true and the order is the one every other device already runs on.
	badAt(state, bob, "echo motion > /dev/sensor0", "sensor0: permission denied", env)
	okAt(state, session, "chmod 446 /dev/sensor0", {}, env)
	badAt(state, bob, "echo motion > /dev/sensor0", "sensor0: invalid value", env)
	eq("and a w on the mode still wrote nothing to the world", #devices.writes, 0)
	okAt(state, session, "chmod 444 /dev/sensor0", {}, env)

	-- A head picked up: mounted so the number can be spoken about, never listed.
	local gone = fakeDevices({
		{ id = "sensor0", kind = "sensor", dead = true, mode = 440 },
	})
	badAt(state, session, "cat /dev/sensor0", "sensor0: no such device", devEnv(gone))
	badAt(state, session, "dev find sensor0", "sensor0: no such device", devEnv(gone))
	badAt(state, session, "echo x > /dev/sensor0", "sensor0: no such device", devEnv(gone))
	okAt(state, session, "dev sensor", {}, devEnv(gone))
end

-- 21r. A device with nothing behind it to write with.
--
-- The OTHER read-only device, and it is not a kind: a `door` like any other,
-- with the same two words in its vocabulary, on an object nobody has fitted an
-- actuator to -- a magnetic contact and no operator. What the world hands over
-- is one more field on the entry (`ro`), and the engine's whole half is here:
-- the node is born 440, and the write that walks past 440 -- root's, and root's
-- only, because root walks past every mode on this machine -- is refused in the
-- device's own name and never reaches the caller.
--
-- The fake would take that write and carry it out, which is the point of proving
-- it here rather than against a world: the refusal is the ENGINE's, not the
-- server's. The server's own belt for the same case is in
-- tests/window_test.lua, against real doors.
do
	eq("a device with no actuator is born read-only",
		CeroSecOS.devModeFor("door", true), CeroSecOS.DEV_MODE_RO)
	eq("and the same kind without the flag is not",
		CeroSecOS.devModeFor("door"), CeroSecOS.DEV_MODE)
	eq("a sensor is the same number by its kind",
		CeroSecOS.devModeFor("sensor"), CeroSecOS.DEV_MODE_RO)

	local state = fresh()
	local root = open(state, "root")
	local admin = open(state, "admin")
	local devices = fakeDevices({
		{ id = "door0", kind = "door", desc = "exterior", side = "W", pos = "0 0",
			state = "closed", ro = true, mode = 440,
			becomes = { open = "open", close = "closed" } },
		{ id = "door1", kind = "door", desc = "office", side = "N", pos = "1E 0",
			state = "closed", becomes = { open = "open", close = "closed" } },
	})
	local env = devEnv(devices)

	okAt(state, root, "ls -l /dev", {
		"cr--r-----  root  sudo  door0   exterior       W  closed",
		"crw-rw----  root  sudo  door1   office         N  closed",
		"crw-rw-rw-  root  root  null",
	}, env)

	-- Read by anybody the 4 in the middle digit covers, which is the sudo group.
	okAt(state, admin, "cat /dev/door0", { "closed" }, env)
	okAt(state, root, "dev door0", { "door0: closed" }, env)

	-- Written by nobody. The mode stops everybody but root; root is stopped by
	-- the device, with write(2)'s own word for it.
	badAt(state, admin, "echo open > /dev/door0", "door0: permission denied", env)
	badAt(state, root, "echo open > /dev/door0", "door0: operation not supported", env)
	badAt(state, root, "dev door0 open", "door0: operation not supported", env)
	-- And the word makes no difference, because it cannot: a device with nothing
	-- behind it has nothing to carry any word out with, so it is refused before
	-- the vocabulary is ever consulted.
	badAt(state, root, "echo close > /dev/door0", "door0: operation not supported", env)
	badAt(state, root, "echo banana > /dev/door0", "door0: operation not supported", env)
	badAt(state, root, "dev door0 toggle", "door0: operation not supported", env)
	eq("and not one of them reached the world", #devices.writes, 0)

	-- A chmod opens the reading; it does not invent an actuator.
	okAt(state, root, "chmod 666 /dev/door0", {}, env)
	badAt(state, root, "echo open > /dev/door0", "door0: operation not supported", env)
	eq("still nothing reached the world", #devices.writes, 0)

	-- The door beside it, with an operator on it, is untouched by any of this.
	okAt(state, root, "echo open > /dev/door1", {}, env)
	eq("the one that is wired still works", devices.writes[1], "door1=open")
	okAt(state, root, "cat /dev/door1", { "open" }, env)
end

-- 21s. A MALL. /dev is the one directory the 96-entry rule does not hold for,
-- and this is the pair of facts that says so: two hundred devices mount and list,
-- and /tmp still refuses the ninety-seventh file in the same breath.
--
-- Two hundred and not 256, so the assertion is about the exemption and not about
-- the ceiling being touched: a /dev of exactly DEV_MAX would go green on an engine
-- that had quietly clamped the mount to 96 and then to the ceiling again.
do
	local state = fresh()
	local session = open(state, "root")
	local entries = {}
	for i = 1, 200 do
		entries[i] = { id = "light" .. (i - 1), kind = "light", desc = "mall",
			side = "", state = "on" }
	end
	local env = devEnv(fakeDevices(entries))

	CeroSecOS.mountDev(state, env)
	local dir = state.fs.children.dev
	-- The 200 lights plus the machine's own null device.
	eq("two hundred devices mount in one /dev", CeroSecOS.countEntries(dir), 201)
	check("which is well past one directory's ceiling",
		CeroSecOS.countEntries(dir) > CeroSecOS.MAX_DIR_ENTRIES)
	CeroSecOS.unmountDev(state, env)
	-- And nothing of them is left behind, so the state gate never sees the mall:
	-- the 96-entry rule and the node quota are both asked of a /dev with the null
	-- device in it and nothing else (21g says the same thing about one device).
	eq("swept off again", CeroSecOS.countEntries(dir), 1)
	eq("and the machine runs on what is left", CeroSecOS.validate(state), true)

	-- And it LISTS: `dev light` is the everyday face of those nodes, and a
	-- listing that stopped at 96 would be a mall a survivor can only half reach.
	local shown = okAt(state, session, "dev light", nil, env)
	eq("all two hundred are listed", #shown, 200)
	eq("the first", string.sub(shown[1], 1, 6), "light0")
	-- light10 before light2: by kind and then by NUMBER, over two hundred of them.
	eq("in the table's own order", string.sub(shown[200], 1, 8), "light199")

	-- The rule itself has not moved anywhere else. An ordinary directory takes 96
	-- and refuses the ninety-seventh, which is the ceiling /dev is exempt FROM.
	okAt(state, session, "mkdir /root/mall", {}, env)
	for i = 1, CeroSecOS.MAX_DIR_ENTRIES do
		okAt(state, session, "touch /root/mall/f" .. i, {}, env)
	end
	eq("an ordinary directory holds one directory's worth",
		CeroSecOS.countEntries(state.fs.children.root.children.mall),
		CeroSecOS.MAX_DIR_ENTRIES)
	badAt(state, session, "touch /root/mall/last", "touch: /root/mall/last: directory full", env)
end

--
-- 22. Groups: /etc/group, the three-digit evaluation, and the five commands.
--

-- 22a. The parser. Blank lines, comments, duplicates, and everything a line
-- may not be.
do
	local g = CeroSecOS.parseGroupLine("users:admin,bob")
	eq("the name", g.name, "users")
	eq("two members", #g.members, 2)
	eq("in file order", g.members[1], "admin")
	eq("and the second", g.members[2], "bob")
	check("and by name", g.set.bob)
	check("and nobody else", not g.set.kate)

	local empty = CeroSecOS.parseGroupLine("root:")
	eq("an empty group is a group", empty.name, "root")
	eq("with nobody in it", #empty.members, 0)

	-- A line that is not one is skipped, silently, the way the other two
	-- parsers skip one.
	local BAD = {
		"", "   ", "# a comment", "\t# indented comment",
		"nocolon", "two:colons:here", ":nobody", "-bad:admin",
		"users:", -- fine, but the next ones are not
		"users:admin,", "users:,admin", "users:admin,,bob", "users:-bad",
		"users:has space", "has space:admin",
	}
	for i = 1, #BAD do
		if BAD[i] ~= "users:" then
			eq("not a group line: \"" .. BAD[i] .. "\"", CeroSecOS.parseGroupLine(BAD[i]), nil)
		end
	end

	-- A duplicate name keeps its FIRST line, the way a lookup down a file does.
	local groups, order = CeroSecOS.parseGroup(
		"# heading\n\ncrew:admin\ncrew:bob\nsomething broken\nmates:")
	eq("two groups parsed", #order, 2)
	eq("in file order", order[1], "crew")
	eq("and the second", order[2], "mates")
	check("the first crew line won", groups.crew.set.admin)
	check("and the second was dropped", not groups.crew.set.bob)

	-- What is written is what is read: one place builds a line.
	eq("a line round-trips", CeroSecOS.groupLine({ name = "crew", members = { "admin", "bob" } }),
		"crew:admin,bob")
	eq("an empty one too", CeroSecOS.groupLine({ name = "crew", members = {} }), "crew:")
end

-- 22b. What a shipped machine has, and what the cache does with it.
do
	local state = fresh()
	local groups, order = CeroSecOS.readGroups(state)
	eq("four groups ship", #order, 4)
	eq("the first", order[1], "root")
	eq("the second", order[2], "sudo")
	eq("the third", order[3], "users")
	eq("the fourth", order[4], CeroSecOS.WHEEL_GROUP)
	eq("root's is empty", #groups.root.members, 0)
	-- wheel ships empty too, and that is the whole of why a shipped machine is
	-- the machine it always was: the `%wheel` line in /etc/sudoers grants nobody
	-- until an administrator puts somebody in it (`useradd -G wheel`).
	eq("and wheel is empty", #groups[CeroSecOS.WHEEL_GROUP].members, 0)
	check("admin is in sudo", groups.sudo.set.admin)
	check("and in users", groups.users.set.admin)
	check("and in no wheel", not CeroSecOS.inGroup(state, "admin", CeroSecOS.WHEEL_GROUP))
	check("but he may still sudo, by name", CeroSecOS.sudoer(state, "admin") ~= nil)

	-- The cache is keyed on the file, so an edit is seen.
	local same = CeroSecOS.readGroups(state)
	eq("the same table while the file stands still", same, groups)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.GROUP_PATH, "crew:bob")
	local _, after = CeroSecOS.readGroups(state)
	eq("and a fresh one when it moves", #after, 1)
	eq("the new group", after[1], "crew")

	-- A machine with no /etc/group at all has no groups but the primary ones.
	local gone = fresh()
	gone.fs.children.etc.children.group = nil
	local _, none = CeroSecOS.readGroups(gone)
	eq("no file, no groups", #none, 0)
	check("but bob is still in bob", CeroSecOS.inGroup(gone, "bob", "bob"))
end

-- 22c. Who is in what. The primary group, a line in the file, and sudoers.
do
	local state = fresh()
	check("a primary group needs no line", CeroSecOS.inGroup(state, "bob", "bob"))
	check("a line puts him in", CeroSecOS.inGroup(state, "admin", "users"))
	check("sudoers puts him in sudo", CeroSecOS.inGroup(state, "admin", "sudo"))
	check("and nothing puts him anywhere else", not CeroSecOS.inGroup(state, "bob", "users"))
	check("nor in a group that does not exist", not CeroSecOS.inGroup(state, "bob", "nosuch"))
	eq("junk is not a membership", CeroSecOS.inGroup(state, nil, "users"), false)
	eq("nor is junk on the other side", CeroSecOS.inGroup(state, "bob", nil), false)

	-- The sudo mirror, from the sudoers side only.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "bob NOPASSWD")
	check("a sudoer is in the sudo group", CeroSecOS.inGroup(state, "bob", "sudo"))
	check("and admin is still in it by its line", CeroSecOS.inGroup(state, "admin", "sudo"))
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.GROUP_PATH, "sudo:\nusers:admin")
	check("with the line gone, sudoers is what is left", CeroSecOS.inGroup(state, "bob", "sudo"))
	check("and admin is out of it", not CeroSecOS.inGroup(state, "admin", "sudo"))

	-- groupExists: a line, or an account whose primary group needs no line.
	local fresh2 = fresh()
	check("a line is a group", CeroSecOS.groupExists(fresh2, "users"))
	check("an account is a group", CeroSecOS.groupExists(fresh2, "admin"))
	check("and nothing else is", not CeroSecOS.groupExists(fresh2, "crew"))
end

-- 22d. The three-digit evaluation, owner / group / other, on a matrix.
do
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "useradd bob", nil)
	okAt(state, rootSession, "useradd kate", nil)
	okAt(state, rootSession, "groupadd crew", {})
	okAt(state, rootSession, "usermod -G crew bob", {})

	local file = CeroSecOS.newFile("admin", 640, "shared")
	file.group = "crew"
	state.fs.children.home.children.admin.children["notes.txt"] = file
	okAt(state, rootSession, "chmod 755 /home/admin", {})

	local admin = { user = "admin", cwd = "/" }
	local bobS = { user = "bob", cwd = "/" }
	local kateS = { user = "kate", cwd = "/" }

	-- 640: the owner reads and writes, the group reads, everybody else nothing.
	check("the owner reads", CeroSecOS.can(state, admin, file, "r"))
	check("and writes", CeroSecOS.can(state, admin, file, "w"))
	check("a member of the group reads", CeroSecOS.can(state, bobS, file, "r"))
	check("and does not write", not CeroSecOS.can(state, bobS, file, "w"))
	check("everybody else reads nothing", not CeroSecOS.can(state, kateS, file, "r"))

	-- The middle digit really is the middle one: move it and only the group
	-- changes.
	file.mode = 660
	check("660 lets the group write", CeroSecOS.can(state, bobS, file, "w"))
	check("and still shuts everybody else out", not CeroSecOS.can(state, kateS, file, "r"))
	file.mode = 604
	check("604 shuts the group out", not CeroSecOS.can(state, bobS, file, "r"))
	check("and lets everybody else in", CeroSecOS.can(state, kateS, file, "r"))
	check("the owner is unmoved", CeroSecOS.can(state, admin, file, "w"))

	-- The owner digit wins over the group's, even when the owner is in it.
	file.mode = 470
	okAt(state, rootSession, "usermod -G users,crew admin", {})
	check("the owner is judged as the owner", not CeroSecOS.can(state, admin, file, "w"))
	check("and the member as the member", CeroSecOS.can(state, bobS, file, "w"))

	-- A primary group counts: bob is a member of group bob.
	local mine = CeroSecOS.newFile("kate", 604, "hers")
	mine.group = "bob"
	check("a primary group is a membership: bob is judged as the group, not as other",
		CeroSecOS.can(state, bobS, mine, "r") == false)
	mine.mode = 040
	check("and the group digit is what he gets", CeroSecOS.can(state, bobS, mine, "r"))
	check("while kate, who owns it, gets nothing", not CeroSecOS.can(state, kateS, mine, "r"))

	-- Root walks through all three.
	file.mode = 000
	check("root reads anything", CeroSecOS.can(state, { user = "root" }, file, "r"))

	-- And it works through the real commands, on the real disk.
	file.mode = 640
	file.group = "crew"
	okAt(state, bobS, "cat /home/admin/notes.txt", { "shared" })
	badAt(state, kateS, "cat /home/admin/notes.txt",
		"cat: /home/admin/notes.txt: permission denied")
	badAt(state, bobS, "echo x > /home/admin/notes.txt",
		"echo: /home/admin/notes.txt: permission denied")
	okAt(state, rootSession, "chmod 660 /home/admin/notes.txt", {})
	okAt(state, bobS, "echo mine > /home/admin/notes.txt", {})
	okAt(state, kateS, "ls /home/admin", nil)
end

-- 22e. chgrp: who may, and what it takes.
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")
	okAt(state, rootSession, "useradd bob", nil)
	local bob = open(state, "bob")

	okAt(state, admin, "touch /home/admin/notes.txt", {})
	eq("a fresh file is in its owner's own group",
		CeroSecOS.groupOf(state.fs.children.home.children.admin.children["notes.txt"]), "admin")

	-- The owner may give it away, to a group that exists.
	okAt(state, admin, "chgrp users /home/admin/notes.txt", {})
	eq("and it moved",
		CeroSecOS.groupOf(state.fs.children.home.children.admin.children["notes.txt"]), "users")
	-- An account is a group: its primary one.
	okAt(state, admin, "chgrp bob /home/admin/notes.txt", {})
	eq("to an account's own group",
		CeroSecOS.groupOf(state.fs.children.home.children.admin.children["notes.txt"]), "bob")

	-- A group that is not one is refused where it is typed.
	badAt(state, admin, "chgrp crew /home/admin/notes.txt", "chgrp: crew: no such group")
	badAt(state, admin, "chgrp Crew /home/admin/notes.txt", "chgrp: Crew: no such group")

	-- Not the owner and not root is not allowed, and the refusal is about the
	-- file and not about the group.
	okAt(state, rootSession, "chmod 777 /home/admin", {})
	badAt(state, bob, "chgrp bob /home/admin/notes.txt",
		"chgrp: /home/admin/notes.txt: permission denied")
	-- Root always may.
	okAt(state, rootSession, "chgrp users /home/admin/notes.txt", {})

	badAt(state, admin, "chgrp users /home/admin/nosuch", "chgrp: /home/admin/nosuch: no such file")
	badAt(state, admin, "chgrp users", "chgrp: usage: chgrp <group> <path>")
	badAt(state, admin, "chgrp a b c", "chgrp: usage: chgrp <group> <path>")

	-- chown does not touch the group, and chgrp does not touch the owner.
	okAt(state, rootSession, "chown bob /home/admin/notes.txt", {})
	local node = state.fs.children.home.children.admin.children["notes.txt"]
	eq("chown moved the owner", node.owner, "bob")
	eq("and left the group", CeroSecOS.groupOf(node), "users")
	okAt(state, rootSession, "chgrp root /home/admin/notes.txt", {})
	eq("chgrp moved the group", CeroSecOS.groupOf(node), "root")
	eq("and left the owner", node.owner, "bob")

	-- A directory is a node like any other, and a chgrp is a touch.
	okAt(state, admin, "mkdir /home/admin/sub", {})
	okAt(state, admin, "chgrp users /home/admin/sub", {})
	eq("a directory takes a group too",
		CeroSecOS.groupOf(state.fs.children.home.children.admin.children.sub), "users")
	eq("and the stamp moved with it",
		CeroSecOS.mtimeOf(state.fs.children.home.children.admin.children.sub), FIXED)
end

-- 22f. groupadd, groupdel, usermod -G -- and a dangling group.
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")
	okAt(state, rootSession, "useradd bob", nil)

	-- Root only, for all three.
	badAt(state, admin, "groupadd crew", "groupadd: permission denied")
	badAt(state, admin, "groupdel users", "groupdel: permission denied")
	badAt(state, admin, "usermod -G users bob", "usermod: permission denied")

	okAt(state, rootSession, "groupadd crew", {})
	check("the line is in the file",
		string.find(CeroSecOS.systemNode(state, CeroSecOS.GROUP_PATH).data, "\ncrew:", 1, true) ~= nil)
	eq("with nobody in it", #CeroSecOS.readGroups(state).crew.members, 0)
	badAt(state, rootSession, "groupadd crew", "groupadd: crew: already exists")
	-- An account already has a group of that name.
	badAt(state, rootSession, "groupadd bob", "groupadd: bob: already exists")
	badAt(state, rootSession, "groupadd Crew", "groupadd: Crew: invalid name")
	badAt(state, rootSession, "groupadd 1crew", "groupadd: 1crew: invalid name")
	badAt(state, rootSession, "groupadd " .. string.rep("c", 17),
		"groupadd: " .. string.rep("c", 17) .. ": invalid name")
	badAt(state, rootSession, "groupadd", "groupadd: usage: groupadd <name>")

	-- usermod -G, which SETS the list: what is on the line is what he is in
	-- afterwards, which is SVR4's rule and not gpasswd's add-one-drop-one.
	okAt(state, rootSession, "usermod -G crew bob", {})
	okAt(state, rootSession, "groups bob", { "bob crew" })
	-- Setting the same list again is not a refusal: SVR4's -G says where the
	-- account ends up, and it is already there.
	okAt(state, rootSession, "usermod -G crew bob", {})
	okAt(state, rootSession, "groups bob", { "bob crew" })
	-- A second group ADDS, and dropping it from the list takes it away: one flag,
	-- both directions, because the list is the whole answer.
	okAt(state, rootSession, "usermod -G crew,users bob", {})
	okAt(state, rootSession, "groups bob", { "bob users crew" })
	okAt(state, rootSession, "usermod -G users bob", {})
	okAt(state, rootSession, "groups bob", { "bob users" })
	badAt(state, rootSession, "usermod -G crew nosuch", "usermod: nosuch: no such user")
	badAt(state, rootSession, "usermod -G nosuch bob", "usermod: nosuch: no such group")
	-- A primary group is not a membership anybody granted, so naming it is naming
	-- a group with no line -- which is what it will always be.
	okAt(state, rootSession, "usermod -G bob bob", {})
	okAt(state, rootSession, "groups bob", { "bob" })
	badAt(state, rootSession, "usermod -a bob crew",
		"usermod: usage: usermod -G group[,group...] login")
	badAt(state, rootSession, "usermod -G bob",
		"usermod: usage: usermod -G group[,group...] login")
	-- And the one list -G will not take: an empty one. SVR4 has no spelling for
	-- "in no groups at all", and a `usermod -G ""` that quietly emptied the list
	-- would be the one way this command takes power away by accident.
	badAt(state, rootSession, "usermod -G '' bob", "usermod: empty group list")
	badAt(state, rootSession, "usermod -G crew,, bob", "usermod: empty group list")
	okAt(state, rootSession, "groups bob", { "bob" })

	-- Every other line of the file is kept exactly as it lies.
	okAt(state, rootSession, "usermod -G crew bob", {})
	local text = CeroSecOS.systemNode(state, CeroSecOS.GROUP_PATH).data
	check("the comment is still there", string.find(text, "# name:member", 1, true) ~= nil)
	check("and the shipped lines", string.find(text, "\nsudo:admin\n", 1, true) ~= nil)

	-- groupdel: the shipped three are not the machine's to lose.
	badAt(state, rootSession, "groupdel root", "groupdel: root: cannot remove")
	badAt(state, rootSession, "groupdel sudo", "groupdel: sudo: cannot remove")
	badAt(state, rootSession, "groupdel users", "groupdel: users: cannot remove")
	badAt(state, rootSession, "groupdel nosuch", "groupdel: nosuch: no such group")
	-- A primary group has no line to take out.
	badAt(state, rootSession, "groupdel bob", "groupdel: bob: no such group")
	badAt(state, rootSession, "groupdel", "groupdel: usage: groupdel <name>")

	-- A file keeps a group that has been deleted: the name dangles, and ls -l
	-- says so rather than telling a tidy lie about who it was shared with.
	okAt(state, admin, "touch /home/admin/notes.txt", {})
	okAt(state, admin, "chgrp crew /home/admin/notes.txt", {})
	okAt(state, rootSession, "groupdel crew", {})
	local node = state.fs.children.home.children.admin.children["notes.txt"]
	eq("the file still names it", CeroSecOS.groupOf(node), "crew")
	eq("and the listing shows it",
		string.sub(okAt(state, admin, "ls -l /home/admin/notes.txt", nil)[1], 20, 25), "crew  ")
	-- And nobody is in it any more, so 640 gives bob nothing.
	node.mode = 640
	check("a dangling group is nobody's",
		not CeroSecOS.can(state, { user = "bob" }, node, "r"))
	check("except the account of that name, if there is one",
		CeroSecOS.can(state, { user = "crew" }, node, "r"))
	-- Which is the whole of it: chgrp will not take the name again.
	badAt(state, admin, "chgrp crew /home/admin/notes.txt", "chgrp: crew: no such group")
end

-- 22g. A node with no group at all: what every machine saved before this rung
-- is made of.
do
	local state = fresh()
	local admin = open(state, "admin")
	local old = CeroSecOS.newFile("admin", 640, "old")
	old.group = nil
	state.fs.children.home.children.admin.children["old.txt"] = old

	eq("it reads as its owner's own group", CeroSecOS.groupOf(old), "admin")
	eq("and the listing says so",
		string.sub(okAt(state, admin, "ls -l /home/admin/old.txt", nil)[1], 20, 25), "admin ")
	eq("and validate takes it", CeroSecOS.validate(state), true)

	-- A group that is not a string is not a node.
	old.group = 7
	local ok2, reason = CeroSecOS.validate(state)
	eq("a number is not a group", ok2, false)
	eq("and it says which node", reason, "/home/admin/old.txt: bad group")
	old.group = nil
	eq("and it validates again", CeroSecOS.validate(state), true)
end


--
-- 23. Scripts: the parser (rung 5a)
--
-- A script never becomes a job until it parses, so this is the gate every
-- mistake in a file meets, and every line below is the exact string a player
-- reads.
--

local function parses(text)
	local prog, reason, line = CeroSecOS.parseScript(text)
	if prog == nil then
		error("FAIL: `" .. string.gsub(text, "\n", " | ") .. "` should parse: line "
			.. tostring(line) .. ": " .. tostring(reason), 2)
	end
	count = count + 1
	return prog
end

local function refuses(text, wantReason, wantLine)
	local prog, reason, line = CeroSecOS.parseScript(text)
	count = count + 1
	if prog ~= nil then
		error("FAIL: `" .. string.gsub(text, "\n", " | ") .. "` should not parse", 2)
	end
	eq("`" .. string.gsub(text, "\n", " | ") .. "` reason", reason, wantReason)
	if wantLine ~= nil then
		eq("`" .. string.gsub(text, "\n", " | ") .. "` line", line, wantLine)
	end
end

do
	-- Every construct there is.
	parses("echo hi")
	parses("echo hi; echo there")
	parses("echo hi\necho there\n")
	parses("#!/bin/sh\n# a comment\necho hi # and another\n")
	parses("x=1")
	parses("x=1 y=2 echo $x")
	parses("if true; then echo a; fi")
	parses("if true; then echo a; else echo b; fi")
	parses("if true; then a; elif false; then b; elif true; then c; else d; fi")
	parses("for i in a b c; do echo $i; done")
	parses("for i; do echo $i; done")
	parses("while true; do break; done")
	parses("until false; do break; done")
	parses("echo a && echo b || echo c")
	parses("sh x.sh &")
	parses("sh a.sh & sh b.sh & echo both")
	parses("echo $x ${x} $1 $9 $# $@ $? $$")
	parses("echo $(ls /bin)")
	parses("echo $((1 + 2 * (3 - 1) / 2 % 3))")
	parses("echo 'single' \"double $x\" bare\\ space")
	parses("echo hi > out.txt")
	parses("echo hi >> out.txt")
	parses("cat a | grep b")
	parses("cat a | grep b | sort | uniq -c")
	parses("cat a | sort > out.txt")
	parses("echo $(cat a | sort)")
	parses("cat a | grep b && echo found")
	parses("cat a |\n\tgrep b")
	parses("cat a | grep b &")
	parses(string.rep("cat a | ", CeroSecOS.MAX_STAGES - 1) .. "cat b")
	parses("for i in a b; do done")
	parses("")

	-- And every way of getting one wrong.
	refuses("fi", "syntax error: unexpected 'fi'", 1)
	refuses("done", "syntax error: unexpected 'done'", 1)
	refuses("then echo a", "syntax error: unexpected 'then'", 1)
	refuses("else", "syntax error: unexpected 'else'", 1)
	refuses("elif true; then a; fi", "syntax error: unexpected 'elif'", 1)
	refuses("do echo a; done", "syntax error: unexpected 'do'", 1)
	refuses("if true; then echo a", "syntax error: missing 'fi'", 1)
	-- `then` never came, and what turned up where a command should be is `fi`:
	-- the parser names what it found, which is the half a reader can see.
	refuses("if true; echo a; fi", "syntax error: unexpected 'fi'", 1)
	refuses("if true\necho a", "syntax error: missing 'then'", 2)
	refuses("while true; do echo a", "syntax error: missing 'done'", 1)
	refuses("until true; do echo a", "syntax error: missing 'done'", 1)
	refuses("for i in a; do echo a", "syntax error: missing 'done'", 1)
	refuses("for i in a; echo a; done", "syntax error: missing 'do'", 1)
	refuses("for 9bad in a; do x; done", "syntax error: not a name", 1)
	refuses("echo 'open", "syntax error: unterminated quote", 1)
	refuses("echo \"open", "syntax error: unterminated quote", 1)
	refuses("echo $(echo $(echo x))", "syntax error: bad substitution", 1)
	refuses("echo $(echo x", "syntax error: bad substitution", 1)
	refuses("echo ${x", "syntax error: bad substitution", 1)
	refuses("echo ${not a name}", "syntax error: bad substitution", 1)
	refuses("echo $((1 + 2)", "syntax error: bad substitution", 1)
	-- A pipeline parses now (rung 5b). What does not is a "|" with nothing on
	-- one side of it, and a pipeline longer than the machine will run.
	refuses("| grep b", "syntax error: unexpected '|'", 1)
	refuses("cat a |", "syntax error: unexpected end of file", 1)
	refuses("cat a | | grep b", "syntax error: unexpected '|'", 1)
	refuses(string.rep("cat a | ", CeroSecOS.MAX_STAGES) .. "cat b",
		"too many stages", 1)
	refuses("cat < a", "syntax error: unexpected '<'", 1)
	refuses("echo a >", "syntax error: missing redirect target", 1)
	refuses("echo a > b > c", "syntax error: bad redirect", 1)
	refuses("echo a && ", "syntax error: unexpected end of file", 1)

	-- The line a mistake is on is the line it was typed on.
	refuses("echo one\necho two\nfi", "syntax error: unexpected 'fi'", 3)
	refuses("echo one\n\n\nwhile true; do x", "syntax error: missing 'done'", 4)

	-- Nesting has a floor under it, and the parser is where a script meets it.
	refuses(string.rep("if true; then ", CeroSecOS.MAX_NEST + 4) .. "echo x"
		.. string.rep(" fi", CeroSecOS.MAX_NEST + 4), "too deeply nested", 1)
	parses(string.rep("if true; then ", 8) .. "echo x" .. string.rep("; fi", 8))
end

--
-- 24. Scripts: running one
--

-- A script on the disk, owned by admin and runnable by him.
local function script(state, path, text)
	local done, reason = CeroSecOS.setData(state, CeroSecOS.rootSession(), path, text)
	if done == nil then
		done, reason = CeroSecOS.writeFile(state, CeroSecOS.rootSession(), path, text, false, 100)
	end
	if done == nil then error("cannot write " .. path .. ": " .. tostring(reason), 2) end
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), path)
	node.owner = "admin"
	node.mode = 755
	return node
end

-- Run a script to the end (or until it asks something), with a fake machine
-- around it: an env with a clock and a job book, answers fed to every question
-- from `answers`, and a hard ceiling on the passes so a bench can never hang.
local JOB_ID = 42

local function runScript(state, session, text, args, answers, options)
	options = options or {}
	script(state, "/home/admin/bench.sh", text)
	local jobs = {}
	local env = { now = 740000000, nowMs = 1000, jobs = jobs }
	-- A world around the machine, for a script that reads or works a device.
	if options.devices ~= nil then env.devices = options.devices end
	-- The order `sh` hands back, asked for directly. It used to be asked for by
	-- typing `sh bench.sh`, and cannot be any more: the prompt is a job itself
	-- now, so `sh` inside it runs ONE LEVEL DEEPER in the same job rather than
	-- asking the machine for a second one (CeroSecOSVM.applyControl). What is
	-- wanted here is a script's own job, so this is the call that makes one.
	local line = "sh /home/admin/bench.sh"
	for i = 1, #(args or {}) do line = line .. " " .. args[i] end
	local ok, lines, control, data = CeroSecOS.startScript(state, session, "sh",
		"/home/admin/bench.sh", args or {}, line, env, false)
	if control ~= "job" then
		return { started = false, ok = ok, lines = CeroSecOS.fit(lines) }
	end
	local job = CeroSecOS.newJob({ id = JOB_ID, prog = data.prog, args = data.args,
		name = data.name, cmd = data.cmd, session = session, bg = options.bg })
	jobs[1] = job
	local out, asked = {}, {}
	local answerAt = 1
	local passes = 0
	while not CeroSecOS.jobIsOver(job) and passes < (options.passes or 400) do
		passes = passes + 1
		env.nowMs = env.nowMs + (options.stepMs or 100)
		-- What the WORLD does while the script runs: a door somebody opened, a
		-- light that went out. Called before the pass, with the pass number, so a
		-- bench can move the world under a script that is watching it.
		if options.between ~= nil then options.between(passes, job) end
		CeroSecOS.jobStep(state, job, env, options.budget or 100)
		for i = 1, #job.out do out[#out + 1] = job.out[i] end
		job.out = {}
		if job.state == "waiting" and job.ask ~= nil then
			asked[#asked + 1] = job.ask.text
			CeroSecOS.jobInput(state, job, (answers or {})[answerAt] or "", env)
			answerAt = answerAt + 1
		elseif job.state == "waiting" then
			break
		end
		if job.spawn ~= nil then job.spawn = nil end
	end
	for i = 1, #job.out do out[#out + 1] = job.out[i] end
	job.out = {}
	return { started = true, job = job, out = out, asked = asked, passes = passes }
end

local function prints(state, session, text, wantLines, what)
	local run = runScript(state, session, text)
	check((what or text) .. ": it started", run.started)
	eq((what or text) .. ": line count", #run.out, #wantLines)
	for i = 1, #wantLines do
		eq((what or text) .. ": line " .. i, run.out[i], wantLines[i])
	end
	return run
end

do
	local state = fresh()
	local admin = open(state, "admin")

	-- Words and quoting.
	prints(state, admin, "echo hello world", { "hello world" })
	prints(state, admin, "echo 'a  b' \"c  d\"", { "a  b c  d" })
	prints(state, admin, "x='one two'\necho $x\necho \"$x\"",
		{ "one two", "one two" })
	prints(state, admin, "echo a\\ b", { "a b" })
	prints(state, admin, "echo -n one\necho two", { "onetwo" })
	prints(state, admin, "printf '%s/%d/%%\\n' hi 7", { "hi/7/%" })

	-- What is held with no newline after it is held for one row and no longer.
	-- A screen sixty columns wide wraps when the cursor reaches its edge, so a
	-- hundred and thirty characters written in one go are two finished lines and
	-- ten characters still being typed. `echo -n one` above is the other half of
	-- the same rule: a prompt shorter than a row is still held.
	local wide = string.rep("x", 130)
	local held = runScript(state, admin, "printf %s " .. wide .. "\necho done",
		nil, nil, { passes = 1, budget = 1 })
	eq("130 characters with no newline: two rows went out", #held.out, 2)
	eq("130 characters with no newline: the first row is full", held.out[1], string.rep("x", 60))
	eq("130 characters with no newline: so is the second", held.out[2], string.rep("x", 60))
	eq("130 characters with no newline: ten are still held", held.job.partial, string.rep("x", 10))
	check("and the job is still running", not CeroSecOS.jobIsOver(held.job))
	-- Run to the end and the ten reach the screen, in front of the next line.
	prints(state, admin, "printf %s " .. wide .. "\necho done",
		{ string.rep("x", 60), string.rep("x", 60), string.rep("x", 10) .. "done" },
		"130 characters with no newline, to the end")

	-- A capture is not a screen, and the wrap must not reach it. A $(...) joins
	-- the lines it caught with a space, so folding one at sixty columns would
	-- push a space into the middle of the value -- the substitution would come
	-- back two characters longer than what was written into it.
	local caught = runScript(state, admin, "x=$(printf %s " .. wide .. ")\necho done")
	eq("a 130-character capture is byte-exact", caught.job.vars.x, wide)

	-- What a capture may hold, in bytes. A captured value is substituted into
	-- the line being built and can never become anything but a word, so the
	-- ceiling is the word's own and so is the message. A thousand bytes fit and
	-- come back exactly as they went in.
	local thousand = string.rep("y", 1000)
	local big = runScript(state, admin, "x=$(printf %s " .. thousand .. ")\necho done")
	eq("a 1000-byte capture is byte-exact", big.job.vars.x, thousand)
	eq("and its length is what was written", #(big.job.vars.x or ""), 1000)
	-- And a capture whose program never ends is stopped at that ceiling rather
	-- than growing for as long as the cpu ceiling allows. It is stopped AT THE
	-- WRITE: this program never reaches the substitution where a word is
	-- measured, because the loop inside it never finishes.
	local over = runScript(state, admin,
		"y=$(while true; do printf %s " .. string.rep("z", 100) .. "; done)\necho done")
	eq("a capture that never ends is stopped", over.job.state, "error")
	eq("with the word's own reason, on the screen", over.out[1],
		"bench.sh: line 1: word too large")
	eq("and nothing of it is held", over.job.partial, "")
	eq("and the line after it never ran", #over.out, 1)

	-- A capture that DOES end is still measured where it always was: as part of
	-- the word it is substituted into, with the `y=` counted in it, so an
	-- assignment takes 1022 bytes of capture and not 1024. The ceiling at the
	-- write is a second door on the same room and must not have moved this one
	-- -- it is only ever reached by a capture that never arrives here at all.
	eq("1022 bytes of capture into an assignment still fits",
		#(runScript(state, admin, "y=$(printf %s " .. string.rep("c", 1022) ..
			")\necho done").job.vars.y or ""), 1022)
	eq("and 1023 is still the word's own refusal",
		runScript(state, admin, "y=$(printf %s " .. string.rep("c", 1023) ..
			")\necho done").out[1], "bench.sh: line 1: word too large")

	-- Two lines, to prove the separator is counted: what a capture hands back is
	-- its lines joined by one space, and that space is a byte of the value like
	-- any other.
	local pair = runScript(state, admin, "y=$(printf '%s\\n%s' one two)\necho done")
	eq("a two-line capture is joined by one space", pair.job.vars.y, "one two")

	-- A capture is bounded by the BYTES and by nothing else. There was a
	-- hundred-line ceiling here as well and the two did not agree: a capture past
	-- the bytes refuses with "word too large", a capture past the lines was cut
	-- short in silence and handed back as though it were whole -- so 150 short
	-- lines came back as a hundred of them and no script could tell. One rule now,
	-- and it is the word's.
	local rows = {}
	for i = 1, 150 do rows[#rows + 1] = "r" .. i end
	put(state, admin, "/home/admin/rows", table.concat(rows, "\n"))
	check("150 short lines still fit a word",
		#table.concat(rows, " ") <= CeroSecOS.MAX_VAR_BYTES - 2)
	local lots = runScript(state, admin, "y=$(cat /home/admin/rows)\necho done")
	eq("a 150-line capture comes back whole", lots.job.vars.y, table.concat(rows, " "))
	eq("and the script ran on", lots.out[1], "done")

	-- And 150 lines that do NOT fit a word are refused, which is the answer a
	-- capture that is too big has always given.
	local wide = {}
	for i = 1, 150 do wide[#wide + 1] = string.rep("w", 10) end
	put(state, admin, "/home/admin/wide", table.concat(wide, "\n"))
	local over150 = runScript(state, admin, "y=$(cat /home/admin/wide)\necho done")
	eq("a capture past the kilobyte is refused", over150.out[1],
		"bench.sh: line 1: word too large")
	eq("the script stopped there", over150.job.state, "error")
	eq("and nothing was held", over150.job.vars.y, nil)
	-- Not the LINE COUNT: the capture is dropped before the error is raised, so
	-- the rest of the lines the one command had already handed over go on to the
	-- screen behind it. That is the error path as it stands and was so before this
	-- ceiling changed -- it is reached by any capture that passes the kilobyte in
	-- the middle of a command's output -- and it is not what this bench is about.
	check("the line after it never ran",
		over150.out[#over150.out] ~= "done")

	-- Variables and arithmetic.
	prints(state, admin, "x=3\ny=$((x * 2 + 1))\necho ${y}", { "7" })
	prints(state, admin, "echo $((7 / 2)) $((-7 / 2)) $((7 % 3)) $((2 * (3 + 4)))",
		{ "3 -3 1 14" })
	prints(state, admin, "echo $((nothing + 1))", { "1" })
	prints(state, admin, "echo [$empty]", { "[]" })
	-- An unquoted expansion that is empty produces no word at all.
	prints(state, admin, "echo a $empty b", { "a b" })
	-- And an unquoted one with blanks in it produces several.
	prints(state, admin, "x='a b c'\nfor w in $x; do echo [$w]; done",
		{ "[a]", "[b]", "[c]" })

	-- The script's own arguments.
	local run = runScript(state, admin, 'echo "$# [$1] [$2] [$@]"\nshift\necho "$# [$1]"',
		{ "one", "two" })
	eq("$# and $1 and $@", run.out[1], "2 [one] [two] [one two]")
	eq("shift moves them along", run.out[2], "1 [two]")

	-- $$ is the job's own id, and $? the last status.
	run = runScript(state, admin, "echo $$\nfalse\necho $?\ntrue\necho $?")
	eq("$$ is the job id", run.out[1], tostring(JOB_ID))
	eq("false is 1", run.out[2], "1")
	eq("true is 0", run.out[3], "0")

	-- Command substitution, with newlines folded to spaces.
	prints(state, admin, "echo one two > /home/admin/two.txt\necho [$(cat /home/admin/two.txt)]",
		{ "[one two]" })
	prints(state, admin, 'printf "a\\nb\\n" > /home/admin/ab.txt\necho [$(cat /home/admin/ab.txt)]',
		{ "[a b]" })

	-- Exit codes travel out of a command and into $?.
	prints(state, admin, "cat /nope\necho $?",
		{ "cat: /nope: no such file", "1" })
end

--
-- 25. Scripts: control flow
--

do
	local state = fresh()
	local admin = open(state, "admin")

	prints(state, admin, "if true; then echo yes; else echo no; fi", { "yes" })
	prints(state, admin, "if false; then echo yes; else echo no; fi", { "no" })
	prints(state, admin, "if false; then a; elif true; then echo second; else c; fi",
		{ "second" })
	prints(state, admin, "if false; then echo a; fi\necho after", { "after" })

	prints(state, admin, "for i in 1 2 3; do echo $i; done", { "1", "2", "3" })
	prints(state, admin, "i=0\nwhile [ $i -lt 3 ]; do echo $i; i=$((i+1)); done",
		{ "0", "1", "2" })
	prints(state, admin, "i=0\nuntil [ $i -ge 2 ]; do echo $i; i=$((i+1)); done",
		{ "0", "1" })

	-- Nested loops, and break/continue by depth.
	prints(state, admin,
		"for a in 1 2; do for b in x y; do echo $a$b; done; done",
		{ "1x", "1y", "2x", "2y" })
	prints(state, admin,
		"for a in 1 2; do for b in x y; do break; done; echo $a; done",
		{ "1", "2" })
	prints(state, admin,
		"for a in 1 2 3; do for b in x y; do break 2; done; echo $a; done",
		{})
	prints(state, admin,
		"for a in 1 2 3; do if [ $a = 2 ]; then continue; fi; echo $a; done",
		{ "1", "3" })
	prints(state, admin,
		"for a in 1 2; do for b in x y; do continue 2; done; echo never; done",
		{})
	-- A break with no loop around it does nothing at all, the way a shell's does.
	prints(state, admin, "break\necho after", { "after" })

	-- && and || read left to right.
	prints(state, admin, "true && echo a", { "a" })
	prints(state, admin, "false && echo a", {})
	prints(state, admin, "false || echo b", { "b" })
	prints(state, admin, "false && echo a || echo b", { "b" })
	prints(state, admin, "true || echo a && echo b", { "b" })

	-- exit ends the script where it stands, with the status it names.
	local run = runScript(state, admin, "echo one\nexit 3\necho two")
	eq("exit stops the script", #run.out, 1)
	eq("with its own status", run.job.status, 3)
	eq("and it is done and not broken", run.job.state, "done")
	-- return is the same door.
	run = runScript(state, admin, "echo one\nreturn 0\necho two")
	eq("return stops it too", #run.out, 1)
end

--
-- 26. Scripts: test, and its other name
--

do
	local state = fresh()
	local admin = open(state, "admin")
	script(state, "/home/admin/file.txt", "contents")

	local function truth(expr, want)
		local run = runScript(state, admin, "if " .. expr .. "; then echo Y; else echo N; fi")
		eq("`" .. expr .. "`", run.out[1], want and "Y" or "N")
	end

	truth("true", true)
	truth("false", false)
	truth("[ -f /home/admin/file.txt ]", true)
	truth("[ -f /home/admin ]", false)
	truth("[ -d /home/admin ]", true)
	truth("[ -e /home/admin/file.txt ]", true)
	truth("[ -e /nope ]", false)
	truth("[ -r /home/admin/file.txt ]", true)
	truth("[ -w /home/admin/file.txt ]", true)
	truth("[ -x /bin/ls ]", true)
	truth("[ -x /home/admin/file.txt ]", true)
	-- -x asks the same question the shell asks before running something, so it
	-- answers the same way for root: no x bit anywhere, no x, even for root.
	do
		local rootSession = open(state, "root")
		local function rootTruth(expr, want)
			local r = runScript(state, rootSession,
				"if " .. expr .. "; then echo Y; else echo N; fi")
			eq("root: `" .. expr .. "`", r.out[1], want and "Y" or "N")
		end
		ok(state, rootSession, "chmod 644 /home/admin/file.txt", {})
		rootTruth("[ -x /home/admin/file.txt ]", false)
		rootTruth("[ -r /home/admin/file.txt ]", true)
		rootTruth("[ -w /home/admin/file.txt ]", true)
		-- A directory is never gated on x for root.
		rootTruth("[ -x /home/admin ]", true)
		ok(state, rootSession, "chmod 700 /home/admin", {})
		rootTruth("[ -x /home/admin ]", true)
		ok(state, rootSession, "chmod 755 /home/admin", {})
		ok(state, rootSession, "chmod 001 /home/admin/file.txt", {})
		rootTruth("[ -x /home/admin/file.txt ]", true)
		ok(state, rootSession, "chmod 755 /home/admin/file.txt", {})
	end
	truth("[ -z '' ]", true)
	truth("[ -z x ]", false)
	truth("[ -n x ]", true)
	truth("[ a = a ]", true)
	truth("[ a = b ]", false)
	truth("[ a != b ]", true)
	truth("[ 2 -eq 2 ]", true)
	truth("[ 2 -ne 3 ]", true)
	truth("[ 2 -lt 3 ]", true)
	truth("[ 3 -le 3 ]", true)
	truth("[ 4 -gt 3 ]", true)
	truth("[ 3 -ge 4 ]", false)
	truth("[ ! 3 -ge 4 ]", true)
	truth("[ 1 -eq 1 -a 2 -eq 2 ]", true)
	truth("[ 1 -eq 1 -a 2 -eq 3 ]", false)
	truth("[ 1 -eq 9 -o 2 -eq 2 ]", true)
	truth("[ x ]", true)
	truth("[ ]", false)
	truth("test a = a", true)

	-- A malformed test says so and is neither true nor false.
	local run = runScript(state, admin, "[ a -zz b ]\necho $?")
	eq("an unknown operator says so", run.out[1], "test: unknown operator")
	eq("and the status is 2", run.out[2], "2")
	run = runScript(state, admin, "[ 1 -eq x ]\necho $?")
	eq("and a number that is not one says that", run.out[1], "test: integer expected")
	-- The bracket wants its other half.
	run = runScript(state, admin, "[ a = a\necho never")
	eq("a [ with no ] stops the script", run.job.state, "error")
	eq("and says where", run.out[1], "bench.sh: line 1: test: missing ']'")
end

--
-- 27. Scripts: read and sleep, the two continuations
--

do
	local state = fresh()
	local admin = open(state, "admin")

	local run = runScript(state, admin, 'read -p "name? " who\necho "hello $who"',
		nil, { "bob" })
	eq("the question was asked", run.asked[1], "name? ")
	eq("and the answer used", run.out[1], "hello bob")

	-- -n 1 takes the first character and nothing else.
	run = runScript(state, admin, 'read -n 1 -p "y/n? " a\necho [$a]', nil, { "yes" })
	eq("-n 1 takes one character", run.out[1], "[y]")

	-- -s is the mask flag, and it is the console that hides it.
	script(state, "/home/admin/secret.sh", 'read -s -p "pw: " p\necho [$p]')
	local jobs = {}
	local env = { now = 100, nowMs = 1000, jobs = jobs }
	local _, _, control, data =
		CeroSecOS.startScript(state, admin, "sh", "/home/admin/secret.sh", {}, "sh /home/admin/secret.sh", env, false)
	local job = CeroSecOS.newJob({ id = 1, prog = data.prog, args = {}, name = data.name,
		cmd = data.cmd, session = admin })
	jobs[1] = job
	CeroSecOS.jobStep(state, job, env, 100)
	eq("a read leaves the job waiting", job.state, "waiting")
	eq("with the question on it", job.ask.text, "pw: ")
	eq("and the mask flag set", job.ask.mask, true)
	eq("and it cost nothing to wait", CeroSecOS.jobStep(state, job, env, 100), "waiting")

	-- sleep is the other one: a wake-up time, and no steps until it comes.
	script(state, "/home/admin/nap.sh", "echo before\nsleep 2\necho after")
	local _, _, c2, d2 = CeroSecOS.startScript(state, admin, "sh", "/home/admin/nap.sh", {}, "sh /home/admin/nap.sh", env, false)
	local nap = CeroSecOS.newJob({ id = 2, prog = d2.prog, args = {}, name = d2.name,
		cmd = d2.cmd, session = admin })
	jobs[1] = nap
	env.nowMs = 10000
	CeroSecOS.jobStep(state, nap, env, 100)
	eq("it slept", nap.state, "sleeping")
	eq("until two seconds from now", nap.wakeMs, 12000)
	local before = nap.steps
	env.nowMs = 11000
	local status, cost = CeroSecOS.jobStep(state, nap, env, 100)
	eq("a pass while it sleeps is still asleep", status, "sleeping")
	eq("and costs nothing", cost, 0)
	eq("and spends no steps", nap.steps, before)
	env.nowMs = 12000
	CeroSecOS.jobStep(state, nap, env, 100)
	eq("and then it wakes and finishes", nap.state, "done")
	eq("having printed both lines", nap.out[2], "after")

	-- A machine with no clock cannot sleep, and says so rather than hanging.
	script(state, "/home/admin/nap.sh", "sleep 1")
	local _, _, c3, d3 = CeroSecOS.startScript(state, admin, "sh", "/home/admin/nap.sh", {}, "sh /home/admin/nap.sh", { jobs = {} }, false)
	local dry = CeroSecOS.newJob({ id = 3, prog = d3.prog, args = {}, name = d3.name,
		cmd = d3.cmd, session = admin })
	CeroSecOS.jobStep(state, dry, { jobs = {} }, 100)
	eq("no clock, no sleep", dry.state, "error")
	eq("and it says so", dry.out[1], "nap.sh: line 1: sleep: no clock")

	-- A background job has nobody in front of it: read is end of file.
	local bg = runScript(state, admin, 'read x\necho [$x] $?', nil, nil, { bg = true })
	eq("a background read reads nothing", bg.out[1], "[] 1")
end

--
-- 28. Scripts: what may be run, and by whom
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local rootSession = open(state, "root")

	-- A line that runs a script. It does NOT ask the machine for a second job
	-- any more: the prompt is a job itself, so `sh go.sh` runs one level deeper
	-- inside it, the way a shell's child would -- which is what keeps a script
	-- that runs itself meeting the depth ceiling in eight lines instead of
	-- filling the machine's four job slots in four.
	local function runsScript(line)
		local r = runAt(state, admin, line, { now = 740000000, nowMs = 1000, jobs = {} })
		eq("`" .. line .. "` ok", r.ok, true)
		eq("`" .. line .. "` orders nothing of the machine", r.control, nil)
		eq("`" .. line .. "` line count", #r.lines, 1)
		eq("`" .. line .. "` ran it", r.lines[1], "ran")
		return r
	end

	script(state, "/home/admin/go.sh", "echo ran")
	runsScript("sh /home/admin/go.sh")
	runsScript("/home/admin/go.sh")
	okAt(state, admin, "cd /home/admin", {})
	runsScript("./go.sh")
	-- The name the script calls itself in an error is its last component, not
	-- the path that was typed. Asked of the order `sh` hands back, which is
	-- what a machine with a job slot to spare would have made a job of.
	eq("a script names itself",
		select(4, CeroSecOS.startScript(state, admin, "sh", "./go.sh", {}, "./go.sh",
			{ jobs = {} }, true)).name, "go.sh")

	-- x is what a path needs; sh only needs to be able to READ it.
	okAt(state, admin, "chmod 644 /home/admin/go.sh", {})
	badAt(state, admin, "./go.sh", "./go.sh: permission denied")
	runsScript("sh /home/admin/go.sh")
	okAt(state, admin, "chmod 755 /home/admin/go.sh", {})

	-- And a file nobody may read is a file nobody may run either.
	okAt(state, admin, "chmod 700 /home/admin/go.sh", {})
	okAt(state, rootSession, "chown root /home/admin/go.sh", {})
	badAt(state, admin, "./go.sh", "./go.sh: permission denied")
	badAt(state, admin, "sh /home/admin/go.sh", "sh: /home/admin/go.sh: permission denied")

	badAt(state, admin, "sh /nope.sh", "sh: /nope.sh: no such file")
	badAt(state, admin, "sh /home", "sh: /home: is a directory")
	badAt(state, admin, "/home/admin", "/home/admin: is a directory")
	badAt(state, admin, "sh", "sh: usage: sh <file> [args]")

	-- A script that will not parse never becomes a job, and the refusal names
	-- the file and the line.
	script(state, "/home/admin/bad.sh", "echo one\nfi\n")
	badAt(state, admin, "sh /home/admin/bad.sh", "bad.sh: line 2: syntax error: unexpected 'fi'")
end

--
-- 28a. `exit` in a script is not `exit` at the glass
--
-- The bug: a script that ends itself threw the player off the machine. `exit 1`
-- in a usage-and-exit script -- the oldest shape there is in /bin -- came back
-- as the console's own logout, because the word was judged by WHOSE job it was
-- (the prompt's) and not by how deep in it the word stood. A script run from the
-- prompt is the prompt's own job one level deeper, so every `exit` in every file
-- anybody ran at the glass was a logout.
--
-- POSIX: `exit [n]` ends the innermost script -- or subshell, or pipeline stage
-- -- with status n, and only the word typed at the top level of an interactive
-- shell ends the session. ~/.profile is the one file on the other side of that
-- line, because it runs AS the login shell: bash exits the login shell there and
-- so does this machine, and the manual says so.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local rootSession = open(state, "root")
	local ENVJ = { now = 740000000, nowMs = 1000, jobs = {} }

	-- ok, the lines, the control and the job's own status, for a line that is
	-- about the status and the control above all.
	local function ran(session, line)
		local execOk, lines, control, data, job = exec(state, session, line, ENVJ)
		return { ok = execOk, lines = lines, control = control, status = job.status,
			state = job.state, job = job }
	end

	-- 1. The script Mathieu wrote, in the shape every usage message has: a
	-- refusal, a status, and a prompt to come back to.
	script(state, "/home/admin/usage.sh",
		'if [ "$1" != on ]; then\n  echo "usage: usage.sh on"\n  exit 1\nfi\necho did $1\n')
	okAt(state, admin, "cd /home/admin", {})
	local r = ran(admin, "./usage.sh")
	eq("the script printed its usage", r.lines[1], "usage: usage.sh on")
	eq("and nothing after the exit", #r.lines, 1)
	eq("the console is ordered to do NOTHING", r.control, nil)
	eq("the script ended with the status it gave", r.status, 1)
	eq("and the session is intact", admin.user, "admin")
	okAt(state, admin, "echo $?", { "1" })
	-- And the same file with its argument: past the exit, to the end.
	r = ran(admin, "./usage.sh on")
	eq("with the argument it runs through", r.lines[1], "did on")
	eq("orders nothing", r.control, nil)
	eq("and succeeds", r.status, 0)

	-- `sh file` is the same door as `./file`, and `return` is the same word as
	-- `exit`: this machine has no functions to return from.
	script(state, "/home/admin/ret.sh", "echo r\nreturn 2\necho never\n")
	r = ran(admin, "sh /home/admin/ret.sh")
	eq("sh file: the script ends", r.lines[1], "r")
	eq("and nothing after it", #r.lines, 1)
	eq("no logout", r.control, nil)
	eq("return carries its status too", r.status, 2)

	-- An exit inside a loop inside a script leaves the loop AND the script,
	-- which is what makes it different from break.
	script(state, "/home/admin/loop.sh",
		"for f in a b c; do\n  echo $f\n  exit 7\ndone\necho never\n")
	r = ran(admin, "./loop.sh")
	eq("one turn of the loop", #r.lines, 1)
	eq("the first one", r.lines[1], "a")
	eq("orders nothing", r.control, nil)
	eq("with the status", r.status, 7)

	-- 2. Inside $(...) it is a subshell's exit: the substitution ends, the line
	-- it is part of goes on, and $? is what the subshell gave.
	r = ran(admin, "echo cap=[$(echo one; exit 4)] $?")
	eq("the substitution ended where the exit was", r.lines[1], "cap=[one] 4")
	eq("and the console was ordered nothing", r.control, nil)
	-- Including a $(...) written in a file: a script with one in it carries on.
	script(state, "/home/admin/cap.sh",
		"x=$(echo one; exit 4)\necho got=[$x]\necho still here\n")
	r = ran(admin, "./cap.sh")
	eq("the script has both lines", #r.lines, 2)
	eq("the substitution's value", r.lines[1], "got=[one]")
	eq("and the script ran on", r.lines[2], "still here")
	eq("orders nothing", r.control, nil)

	-- 3. Inside a pipeline stage it ends the STAGE. The status of a pipeline is
	-- its last stage's, which is the one thing `exit` in one can be seen by.
	r = ran(admin, "echo hi | exit 5")
	eq("the pipeline took the stage's status", r.status, 5)
	eq("and nobody was logged out", r.control, nil)
	r = ran(admin, "exit 5 | cat")
	eq("a stage that exits writes nothing", #r.lines, 0)
	eq("the pipeline is its last stage's status", r.status, 0)
	eq("and still nobody was logged out", r.control, nil)
	-- A whole script as a stage: its exit is the stage's, and the pipeline's
	-- status is the reader's.
	script(state, "/home/admin/p.sh", "echo fromp\nexit 9\necho never\n")
	r = ran(admin, "sh /home/admin/p.sh | cat")
	eq("what the script wrote came down the pipe", r.lines[1], "fromp")
	eq("and nothing after its exit", #r.lines, 1)
	eq("orders nothing", r.control, nil)

	-- 4. Nested scripts: the INNERMOST one ends. b.sh exits 3; a.sh is handed a
	-- $? of 3 and runs its next line.
	script(state, "/home/admin/b.sh", "echo inb\nexit 3\necho neverb\n")
	script(state, "/home/admin/a.sh",
		"echo ina\nsh /home/admin/b.sh\necho after=$?\necho enda\n")
	r = ran(admin, "sh /home/admin/a.sh")
	eq("a.sh ran", r.lines[1], "ina")
	eq("b.sh ran", r.lines[2], "inb")
	eq("nothing of b.sh past its exit", r.lines[3], "after=3")
	eq("and a.sh carried on to its own end", r.lines[4], "enda")
	eq("four lines and no more", #r.lines, 4)
	eq("orders nothing", r.control, nil)
	eq("a.sh's own status is its last line's", r.status, 0)

	-- 5. And the word at the glass, which is the whole reason for the other
	-- meaning: it is still the logout, and it still pops an `su` first.
	r = ran(admin, "exit")
	eq("exit at the prompt is the machine's", r.control, "exit")
	-- Root becoming root is the one su that needs no password, which is what
	-- lets a bench put a stack under a console in one line.
	okAt(state, rootSession, "su root", {})
	eq("the stack is one deep", #rootSession.stack, 1)
	r = ran(rootSession, "exit")
	eq("and exit pops it rather than logging out", r.control, nil)
	eq("with the stack back to nothing", #rootSession.stack, 0)

	-- 6. ~/.profile is the one file whose exit IS the logout: it runs as the
	-- login shell, at the top level of it, the way bash's does.
	local function profile(text)
		local job = CeroSecOS.promptJob(state, admin, text, admin.shvars, admin.status,
			".profile")
		if job == nil then error("the profile would not parse", 2) end
		local out = {}
		local turns = 0
		while not CeroSecOS.jobIsOver(job) and turns < 200 do
			turns = turns + 1
			CeroSecOS.jobStep(state, job, ENVJ, 1000)
			for k = 1, #job.out do out[#out + 1] = job.out[k] end
			job.out = {}
			if job.state == "waiting" or job.state == "sleeping" then break end
		end
		return { lines = out, control = job.control, status = job.status }
	end
	local p = profile("echo in profile\nexit\necho never")
	eq("the profile ran", p.lines[1], "in profile")
	eq("and stopped at the exit", #p.lines, 1)
	eq("and logged the account out, as bash does", p.control, "exit")

	-- 7. The one exit that is NOT a script's: an order to the machine. A
	-- `shutdown` two files deep is the machine going dark, and unwinding it to
	-- the file it was written in would leave the outer script running on a
	-- machine that is off.
	script(state, "/root/down.sh", "echo going\nshutdown\necho never\n")
	script(state, "/root/outer.sh", "sh /root/down.sh\necho afterdown\n")
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), "/root/down.sh")
	node.owner = "root"
	node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), "/root/outer.sh")
	node.owner = "root"
	r = ran(rootSession, "sh /root/outer.sh")
	eq("the inner script ran", r.lines[1], "going")
	eq("and nothing else did", #r.lines, 1)
	eq("the machine was ordered off", r.control, "shutdown")
	eq("and the whole job is over", r.state, "done")
end

--
-- 29. Scripts: what a program costs, in steps
--
-- The exact count for a fixed script. A step is a unit of COST: one for
-- anything the shell answers itself, CeroSecOS.STEP_COST_COMMAND for a command
-- that goes out to /bin. This is the number the whole budget rests on, so it is
-- pinned here rather than left to be noticed.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local C = CeroSecOS.STEP_COST_COMMAND

	local function costs(text, want, what)
		local run = runScript(state, admin, text)
		eq((what or text) .. ": steps", run.job.steps, want)
	end

	-- One builtin.
	costs("echo hi", 1)
	-- Three of them.
	costs("echo a\necho b\necho c", 3)
	-- An assignment is one, and so is a test.
	costs("x=1", 1)
	costs("[ 1 = 1 ]", 1)
	-- An `if` costs its condition and its branch, and nothing for being an if.
	costs("if true; then echo a; fi", 2)
	costs("if false; then echo a; else echo b; fi", 2)
	-- A for loop: one step per iteration boundary plus the body.
	costs("for i in a b c; do echo $i; done", 6)
	-- A while loop: the condition every time round, plus the boundary, plus
	-- the body. Three turns and a fourth condition that ends it.
	costs("i=0\nwhile [ $i -lt 3 ]; do echo $i; i=$((i+1)); done", 1 + 4 + 3 + 6)
	-- A command out of /bin is worth thirty-two.
	costs("pwd", C)
	costs("pwd\npwd", 2 * C)
	costs("echo a\npwd\necho b", 2 + C)
	-- And $(...) is charged the steps of what it runs, to the job that asked.
	costs("x=$(pwd)", C + 1)
	costs("x=$(echo hi)", 2)
end

--
-- 30. Scripts: the ceilings
--

do
	local state = fresh()
	local admin = open(state, "admin")

	-- Sixty-four variables, and the next one is refused. A script does not start
	-- with an empty environment -- it starts with the one a shell is given, PATH
	-- and all -- so what is already there is counted off the ceiling rather than
	-- assumed away: the line that dies is the one that asks for the 65th.
	local base = CeroSecOS.newJob({ prog = {} }).nvars
	check("a script starts with an environment", base >= 1)
	local many = {}
	for i = 1, CeroSecOS.MAX_VARS + 1 do many[#many + 1] = "v" .. i .. "=" .. i end
	local run = runScript(state, admin, table.concat(many, "\n"))
	eq("the variable past the ceiling stops the script", run.job.state, "error")
	eq("and says which ceiling", run.out[1],
		"bench.sh: line " .. (CeroSecOS.MAX_VARS + 1 - base) .. ": too many variables")
	eq("with the status a fatal error carries", run.job.status, 2)

	-- A kilobyte is the ceiling on the WORD, "x=" and all: the word is built
	-- before anything is stored, so that is the ceiling an assignment meets.
	run = runScript(state, admin, "x=" .. string.rep("a", CeroSecOS.MAX_VAR_BYTES - 2))
	eq("a kilobyte of word fits", run.job.state, "done")
	run = runScript(state, admin, "x=" .. string.rep("a", CeroSecOS.MAX_VAR_BYTES + 1))
	eq("and one byte more does not", run.out[1], "bench.sh: line 1: word too large")

	-- A read that answers with more than a variable may hold is refused at the
	-- variable and not at the word.
	run = runScript(state, admin, "read x\necho done", nil,
		{ string.rep("b", CeroSecOS.MAX_VAR_BYTES + 1) })
	eq("a long answer is refused", run.out[1], "bench.sh: line 1: variable too large")

	-- A script that runs itself stops eight levels down.
	script(state, "/home/admin/self.sh", "sh /home/admin/self.sh")
	local jobs = {}
	local env = { now = 100, nowMs = 1000, jobs = jobs }
	local _, _, control, data = CeroSecOS.startScript(state, admin, "sh", "/home/admin/self.sh", {}, "sh /home/admin/self.sh", env, false)
	local job = CeroSecOS.newJob({ id = 1, prog = data.prog, args = {}, name = data.name,
		cmd = data.cmd, session = admin })
	jobs[1] = job
	for _ = 1, 20 do
		if CeroSecOS.jobIsOver(job) then break end
		CeroSecOS.jobStep(state, job, env, 100)
	end
	eq("a script that runs itself stops", job.state, "error")
	eq("and says why", job.out[1], "self.sh: line 1: too deeply nested")
	eq("having gone exactly as deep as it may", job.depth, CeroSecOS.SCRIPT_DEPTH_MAX)

	-- Output: a job that has filled its queue stops until it is drained, and
	-- never grows past it.
	script(state, "/home/admin/flood.sh", "while true; do echo x; done")
	local _, _, c2, d2 = CeroSecOS.startScript(state, admin, "sh", "/home/admin/flood.sh", {}, "sh /home/admin/flood.sh", env, false)
	local flood = CeroSecOS.newJob({ id = 2, prog = d2.prog, args = {}, name = d2.name,
		cmd = d2.cmd, session = admin })
	jobs[1] = flood
	for _ = 1, 20 do CeroSecOS.jobStep(state, flood, env, 100) end
	eq("the queue stops at its ceiling", #flood.out, CeroSecOS.JOB_OUT_MAX)
	eq("and the job is held, not killed", flood.state, "running")
	eq("and says what it is waiting for", flood.blocked, "output")
	local held = flood.steps
	CeroSecOS.jobStep(state, flood, env, 100)
	eq("a pass while it is held costs nothing", flood.steps, held)
	flood.out = {}
	CeroSecOS.jobStep(state, flood, env, 100)
	check("and it runs again once the screen has taken them", flood.steps > held)

	-- Every line a job writes is a screen line: sixty columns, no wider.
	script(state, "/home/admin/wide.sh", "echo " .. string.rep("w", 200))
	local _, _, c3, d3 = CeroSecOS.startScript(state, admin, "sh", "/home/admin/wide.sh", {}, "sh /home/admin/wide.sh", env, false)
	local wide = CeroSecOS.newJob({ id = 3, prog = d3.prog, args = {}, name = d3.name,
		cmd = d3.cmd, session = admin })
	jobs[1] = wide
	CeroSecOS.jobStep(state, wide, env, 100)
	check("a wide line is broken to the screen's width", #wide.out > 1)
	for i = 1, #wide.out do
		check("line " .. i .. " fits sixty columns", #wide.out[i] <= CeroSecOS.COLS)
	end
end

--
-- 31. Scripts: ps, jobs, kill and the four-job ceiling
--

do
	local state = fresh()
	local admin = open(state, "admin")
	script(state, "/home/admin/go.sh", "echo ran")

	local jobs = {}
	local env = { now = 740000000, nowMs = 1000, jobs = jobs }

	-- Nothing running but the shell -- and the shell IS something running now,
	-- because the line being typed is a job. `ps` shows it, the way every Unix
	-- ps shows the shell you typed into; `jobs` does not, because the shell is
	-- not one of the things the shell started.
	local ok, lines = exec(state, admin, "ps", env)
	eq("ps on an idle machine", #lines, 2)
	eq("is its header", lines[1], "  ID S     CPU COMMAND")
	eq("and the shell you are typing into", lines[2], "   1 R       0 ps")
	ok, lines = exec(state, admin, "jobs", env)
	eq("and jobs is empty", #lines, 0)

	-- One job, seen by both.
	local _, _, _, data = CeroSecOS.startScript(state, admin, "sh", "/home/admin/go.sh", {}, "sh /home/admin/go.sh", env, false)
	local job = CeroSecOS.newJob({ id = 42, prog = data.prog, args = {}, name = data.name,
		cmd = data.cmd, session = admin })
	job.n = 1
	jobs[1] = job
	ok, lines = exec(state, admin, "ps", env)
	eq("ps has a row for it, and one for the shell", #lines, 3)
	eq("with its id, its state and its command", lines[2],
		"  42 R       0 sh /home/admin/go.sh")
	eq("and the shell under it", lines[3], "   1 R       0 ps")
	ok, lines = exec(state, admin, "jobs", env)
	eq("jobs names its slot", lines[1], "[1] running  sh /home/admin/go.sh")

	-- kill asks; the scheduler does the deed.
	ok, lines = exec(state, admin, "kill 42", env)
	eq("kill by id is taken", ok, true)
	eq("and asks for it", job.killReq, "user")
	job.killReq = nil
	ok, lines = exec(state, admin, "kill %1", env)
	eq("kill by slot too", ok, true)
	eq("and asks for it", job.killReq, "user")
	ok, lines = exec(state, admin, "kill 99", env)
	eq("a job that is not there", lines[1], "kill: 99: no such job")
	ok, lines = exec(state, admin, "kill", env)
	eq("and kill with nothing to kill says how", lines[1], "kill: usage: kill <id>|%<n>")

	-- Four jobs is the ceiling, and it is the ENGINE that refuses the fifth.
	for i = 2, CeroSecOS.MAX_JOBS do
		jobs[i] = CeroSecOS.newJob({ id = 42 + i, prog = data.prog, args = {},
			name = "go.sh", cmd = "sh go.sh", session = admin })
	end
	eq("four jobs", #jobs, CeroSecOS.MAX_JOBS)
	badAt(state, admin, "sh /home/admin/go.sh", "sh: too many jobs", env)
	-- A job that is over does not count against it.
	jobs[1].state = "done"
	local r = CeroSecOS.startScript(state, admin, "sh", "/home/admin/go.sh", {}, "sh /home/admin/go.sh", env, false)
	eq("a finished job leaves room for another", r, true)
end



--
-- 32. chmod, in letters
--
-- The grammar chmod has had since the seventies, applied to the mode the file
-- already wears: the arithmetic is what a player should not have to do.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "echo hello > notes.txt", {})
	local node = state.fs.children.home.children.admin.children["notes.txt"]

	-- The three digits are taken apart and put back together, so a letter
	-- already there is not added to itself.
	eq("a fresh file is 644", node.mode, 644)
	ok(state, admin, "chmod u+x notes.txt", {})
	eq("u+x lights the owner's x alone", node.mode, 744)
	ok(state, admin, "chmod u+x notes.txt", {})
	eq("and saying it twice changes nothing", node.mode, 744)
	ok(state, admin, "chmod go-r notes.txt", {})
	eq("go-r puts both out", node.mode, 700)
	ok(state, admin, "chmod a=r notes.txt", {})
	eq("a=r is the whole mode, replaced", node.mode, 444)
	ok(state, admin, "chmod ug+rw,o-rwx notes.txt", {})
	eq("two clauses, left to right", node.mode, 660)
	ok(state, admin, "chmod +x notes.txt", {})
	eq("no target letter is all three", node.mode, 771)
	ok(state, admin, "chmod a= notes.txt", {})
	eq("and = with nothing after it is the way to say 000", node.mode, 0)

	-- The grammar, judged before the path: a typo in the mode is what the
	-- player got wrong.
	bad(state, admin, "chmod u+ notes.txt", "chmod: u+: invalid mode")
	bad(state, admin, "chmod u+q notes.txt", "chmod: u+q: invalid mode")
	bad(state, admin, "chmod rwx notes.txt", "chmod: rwx: invalid mode")
	bad(state, admin, "chmod zz+x /nowhere", "chmod: zz+x: invalid mode")
	bad(state, admin, "chmod u+x,,g+x notes.txt", "chmod: u+x,,g+x: invalid mode")

	-- The engine's own arithmetic, asked without a shell around it.
	eq("applyModeSpec on 000", CeroSecOS.applyModeSpec(0, "a+rwx"), 777)
	eq("applyModeSpec on 777", CeroSecOS.applyModeSpec(777, "go-w"), 755)
	eq("applyModeSpec keeps the set a set", CeroSecOS.applyModeSpec(0, "u+rr"), 400)
	eq("applyModeSpec refuses an empty spec", CeroSecOS.applyModeSpec(644, ""), nil)
	eq("applyModeSpec refuses a bad mode", CeroSecOS.applyModeSpec(999, "u+x"), nil)

	-- Ownership is the same rule it has always been.
	local rootSession = CeroSecOS.rootSession()
	ok(state, rootSession, "chmod 644 /etc/motd", {})
	bad(state, admin, "chmod u+x /etc/motd", "chmod: /etc/motd: permission denied")
end

--
-- 33. The prompt IS the script language
--
-- Everything typed goes through CeroSecOS.parseScript and runs as a job on the
-- console's own environment. The bug this section exists for: `while true; do
-- echo tick; sleep 1; done &` at the prompt answered `while: command not
-- found`, because the line went through a second, simpler parser that knew one
-- command and nothing else.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }

	-- The word that started it all.
	local r = runAt(state, admin, "while true; do echo tick; break; done", env)
	eq("`while` is a word the prompt knows", r.ok, true)
	eq("and the loop ran", r.lines[1], "tick")

	-- The whole grammar, at the prompt.
	okAt(state, admin, "true && echo yes", { "yes" }, env)
	okAt(state, admin, "false || echo no", { "no" }, env)
	okAt(state, admin, "echo a; echo b", { "a", "b" }, env)
	okAt(state, admin, "if true; then echo t; else echo f; fi", { "t" }, env)
	okAt(state, admin, "for i in 1 2 3; do echo $i; done", { "1", "2", "3" }, env)
	okAt(state, admin, "until true; do echo never; done", {}, env)
	okAt(state, admin, "echo $((2 + 3))", { "5" }, env)
	okAt(state, admin, "echo $(echo inner)", { "inner" }, env)
	okAt(state, admin, "echo 'one   two'", { "one   two" }, env)

	-- The environment is the console's and outlives the line.
	okAt(state, admin, "x=5", {}, env)
	okAt(state, admin, "echo $x", { "5" }, env)
	okAt(state, admin, 'y="$x$x"', {}, env)
	okAt(state, admin, "echo $y", { "55" }, env)

	-- $? persists too.
	eq("`false` is a status and not a line",
		select(1, exec(state, admin, "false", env)), false)
	okAt(state, admin, "echo $?", { "1" }, env)
	okAt(state, admin, "true", {}, env)
	okAt(state, admin, "echo $?", { "0" }, env)

	-- `cd` moves the CONSOLE. The job runs on the session it was typed at, not
	-- on a copy of it, which is the one thing that separates the prompt's job
	-- from a script's.
	okAt(state, admin, "cd /etc", {}, env)
	eq("the prompt moved", admin.cwd, "/etc")
	okAt(state, admin, "pwd", { "/etc" }, env)
	okAt(state, admin, "cd", {}, env)
	eq("and back home with no argument", admin.cwd, "/home/admin")

	-- A line that ends in "&" is an order to the machine, not a command.
	script(state, "/home/admin/go.sh", "echo ran")
	r = runAt(state, admin, "sh /home/admin/go.sh &", env)
	eq("an ampersand asks for a job", r.control, "job")
	eq("and says it is a background one", r.data.bg, true)

	-- The shell's own words still work, and still answer as themselves.
	okAt(state, admin, "echo -n one", { "one" }, env)
	okAt(state, admin, "printf '%s-%d\n' hi 7", { "hi-7" }, env)
	okAt(state, admin, "test 1 = 1", {}, env)
	okAt(state, admin, "[ 1 = 1 ]", {}, env)

	-- `exit` at the prompt is /bin/exit's meaning and not the builtin's: it
	-- ends the SESSION, and the job is only how it got there.
	r = runAt(state, admin, "exit", env)
	eq("exit at the prompt logs out", r.control, "exit")
	-- And inside an su it pops instead.
	local bob = addUser(state, "bob", "", "/home/bob")
	local root = open(state, "root")
	okAt(state, root, "mkdir /home/bob", {}, env)
	okAt(state, root, "su bob", {}, env)
	eq("root became bob", root.user, "bob")
	r = runAt(state, root, "exit", env)
	eq("and exit pops the stack instead of logging out", r.control, nil)
	eq("back to root", root.user, "root")
	check("and bob was a real account", bob ~= nil)

	-- A typed loop that never ends is a job the machine keeps stepping: it
	-- costs steps, it does not finish, and nothing here hangs.
	local job = select(5, exec(state, admin, "while true; do x=1; done", env))
	check("a typed endless loop is still running", not CeroSecOS.jobIsOver(job))
	check("having spent steps doing it", job.steps > 0)
end

--
-- 34. ~/.sh_history
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }

	okAt(state, admin, "history", {}, env)
	eq("a fresh account has no history file",
		state.fs.children.home.children.admin.children[CeroSecOS.HISTORY_NAME], nil)

	eq("appending makes one", CeroSecOS.historyAppend(state, admin, "ls -l", FIXED), true)
	CeroSecOS.historyAppend(state, admin, "echo two", FIXED)
	local node = state.fs.children.home.children.admin.children[CeroSecOS.HISTORY_NAME]
	check("the file is there", node ~= nil)
	eq("owned by the account", node.owner, "admin")
	eq("and readable by nobody else", node.mode, CeroSecOS.HISTORY_MODE)
	eq("holding both lines", node.data, "ls -l\necho two")

	-- history prints the last HISTORY_SHOW with numbers, bash's way.
	okAt(state, admin, "history", { "    1  ls -l", "    2  echo two" }, env)
	okAt(state, admin, "history -c", {}, env)
	okAt(state, admin, "history", {}, env)
	eq("the file is emptied, not deleted", node.data, "")
	badAt(state, admin, "history x", "history: usage: history [-c]", env)

	-- !n and !!, csh's history expansion. Only a line that is nothing but the
	-- event: there is no quoting rule for "!" on this machine.
	CeroSecOS.historyAppend(state, admin, "pwd", FIXED)
	CeroSecOS.historyAppend(state, admin, "whoami", FIXED)
	eq("!1 is the first", CeroSecOS.historyExpand(state, admin, "!1"), "pwd")
	eq("!2 is the second", CeroSecOS.historyExpand(state, admin, "!2"), "whoami")
	eq("!! is the last", CeroSecOS.historyExpand(state, admin, "!!"), "whoami")
	eq("a line with an event and nothing else only",
		CeroSecOS.historyExpand(state, admin, "echo !1"), "echo !1")
	eq("an event nothing answers to",
		select(2, CeroSecOS.historyExpand(state, admin, "!9")), "sh: !9: event not found")
	eq("and a bang that is not a number either",
		select(2, CeroSecOS.historyExpand(state, admin, "!x")), "sh: !x: event not found")

	-- The tail the window is handed.
	local tail = CeroSecOS.historyTail(state, admin, 1)
	eq("the tail is the last of them", #tail, 1)
	eq("newest", tail[1], "whoami")

	-- Both ceilings. A thousand entries, and sixteen kilobytes.
	for i = 1, 1200 do CeroSecOS.historyAppend(state, admin, "echo " .. i, FIXED) end
	local lines = CeroSecOS.splitLines(node.data)
	eq("a thousand entries and no more", #lines, CeroSecOS.HISTORY_MAX)
	check("and never past sixteen kilobytes (" .. #node.data .. ")",
		#node.data <= CeroSecOS.HISTORY_BYTES)
	eq("the oldest went first", lines[#lines], "echo 1200")

	-- Exempt from the disk quota, and the state still validates with 16K of it
	-- on a 32K disk.
	local _, bytes = CeroSecOS.usage(state)
	check("the history does not count against the disk (" .. bytes .. ")",
		bytes < CeroSecOS.DISK_BYTES)
	eq("the state validates with it there", CeroSecOS.validate(state), true)
	eq("and the exempt bytes are the history's own",
		CeroSecOS.exemptUsage(state), #node.data)
	-- Nothing hides in between the two counts: every byte on the disk is either
	-- counted against the quota or granted the exemption.
	local everyByte = select(2, CeroSecOS.subtreeUsage(state.fs))
	eq("counted plus exempt is every byte on the disk",
		bytes + CeroSecOS.exemptUsage(state), everyByte)
	-- A file past a history's own ceiling is not a state this machine will boot,
	-- wherever it hangs: that ceiling is the biggest a file can be.
	node.data = string.rep("x", CeroSecOS.HISTORY_BYTES + 1)
	eq("a file past the history ceiling is refused", CeroSecOS.validate(state), false)
	node.data = ""

	-- Nobody else may read it, so nobody else's history is in it.
	local bob = addUser(state, "bob", "", "/home/bob")
	check("bob exists", bob ~= nil)
	local rootSession = CeroSecOS.rootSession()
	eq("bob has a home", CeroSecOS.createNode(state, rootSession, "/home/bob",
		CeroSecOS.newDir("bob", CeroSecOS.HOME_MODE), nil) ~= nil, true)
	local bobs = open(state, "bob")
	eq("bob's own history starts empty", #CeroSecOS.historyLines(state, bobs), 0)
	CeroSecOS.historyAppend(state, bobs, "id", FIXED)
	eq("and goes in his own home", #CeroSecOS.historyLines(state, bobs), 1)
	badAt(state, bobs, "cat /home/admin/" .. CeroSecOS.HISTORY_NAME,
		"cat: /home/admin/" .. CeroSecOS.HISTORY_NAME .. ": permission denied", env)
end

-- 34a. The quota exemption is bounded where it is GRANTED
do
	--
	-- The exemption is decided by the PATH the file hangs at and by nothing
	-- carried on the node. So a renamed history is an ordinary file from the
	-- moment it is renamed -- it costs the disk at once -- and the old way of
	-- hiding bytes (move the history aside, let a new one grow, and the flag
	-- rode the rename) is gone.
	--
	local state = fresh()
	local admin = open(state, "admin")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }
	local hist = "/home/admin/" .. CeroSecOS.HISTORY_NAME
	local loot = "/home/admin/loot.txt"

	-- df's used column, read off the real command.
	local function dfUsed()
		local lines = okAt(state, admin, "df", nil, env)
		local used = string.match(lines[2], "^%S+%s+%d+%s+(%d+)%s+%d+%s+%d+%%$")
		check("df's used column is a number (" .. tostring(lines[2]) .. ")", used ~= nil)
		return tonumber(used)
	end

	-- A history of about nine hundred bytes, written by the one thing that
	-- writes one.
	local node = nil
	local n = 0
	while node == nil or #node.data < 900 do
		n = n + 1
		CeroSecOS.historyAppend(state, admin, "echo padding line " .. n, FIXED)
		node = state.fs.children.home.children.admin.children[CeroSecOS.HISTORY_NAME]
	end
	local size = #node.data
	check("a history of about nine hundred bytes (" .. size .. ")", size >= 900)
	local usedWithHistory = dfUsed()
	eq("the disk does not count it", CeroSecOS.exemptUsage(state), size)
	eq("and df agrees with the count", usedWithHistory,
		select(2, CeroSecOS.usage(state)))

	-- The payload: rename it, and the disk moves by the whole of it.
	okAt(state, admin, "mv " .. hist .. " " .. loot, {}, env)
	eq("renaming it costs the disk every byte of it", dfUsed() - usedWithHistory, size)
	eq("and nothing on the machine is exempt any more", CeroSecOS.exemptUsage(state), 0)

	-- And a write to it is counted like anybody's, where before the flag rode
	-- the rename and up to 64K could hide behind it.
	local usedRenamed = dfUsed()
	okAt(state, admin, "echo more >> " .. loot, {}, env)
	eq("a line appended to it is counted", dfUsed() - usedRenamed, #"\nmore")

	-- Renamed back, it is exempt again: the rule is the path and nothing else.
	okAt(state, admin, "mv " .. loot .. " " .. hist, {}, env)
	eq("renamed back, it is exempt again", CeroSecOS.exemptUsage(state), size + #"\nmore")
	eq("and the disk is back where it was", dfUsed(), usedWithHistory)

	-- The owner is half the rule: the same path, somebody else's file, is an
	-- ordinary file.
	local histNode = state.fs.children.home.children.admin.children[CeroSecOS.HISTORY_NAME]
	histNode.owner = "root"
	eq("somebody else's file at that path is not exempt", CeroSecOS.exemptUsage(state), 0)
	histNode.owner = "admin"

	-- A leftover flag from an older save buys nothing.
	okAt(state, admin, "echo hi > /home/admin/flagged", {}, env)
	local flagged = state.fs.children.home.children.admin.children.flagged
	flagged.nq = true
	eq("a node carrying the old flag is counted like any other",
		select(2, CeroSecOS.usage(state)) , usedWithHistory + #flagged.data)
	flagged.nq = nil
	okAt(state, admin, "rm /home/admin/flagged", {}, env)
end

-- 34b. Over the quota is a machine that refuses writes, not a machine that is
-- thrown away
do
	local state = fresh()
	local admin = open(state, "admin")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }
	local rootSession = CeroSecOS.rootSession()
	local hist = "/home/admin/" .. CeroSecOS.HISTORY_NAME
	local loot = "/home/admin/loot.txt"

	-- The disk filled to within a few kilobytes of its ceiling, and then a
	-- history of three renamed on top of it: the rename is allowed -- nothing is
	-- ever deleted to make room -- and the machine is over quota.
	local HIST = 3000
	-- As many maximal files as the drive takes and no more, worked out from the
	-- drive: what this bench needs is a disk with LESS room left on it than the
	-- history holds, and seven files was that on a 32K drive and nowhere near it
	-- on a 64K one.
	local before = select(2, CeroSecOS.usage(state))
	local blocks =
		math.floor((CeroSecOS.MAX_TOTAL_BYTES - before) / CeroSecOS.MAX_FILE_BYTES)
	for i = 1, blocks do
		local made = CeroSecOS.createNode(state, rootSession, "/big" .. i,
			CeroSecOS.newFile("root", 644, string.rep("x", CeroSecOS.MAX_FILE_BYTES)), nil)
		check("/big" .. i .. " went on the disk", made ~= nil)
	end
	local spare = CeroSecOS.MAX_TOTAL_BYTES - select(2, CeroSecOS.usage(state))
	check("less room left than the history holds (" .. spare .. " < " .. HIST .. ")",
		spare < HIST)
	local node = nil
	while node == nil or #node.data < HIST do
		CeroSecOS.historyAppend(state, admin, "echo padding line for the history", FIXED)
		node = state.fs.children.home.children.admin.children[CeroSecOS.HISTORY_NAME]
	end
	local was = select(2, CeroSecOS.usage(state))
	check("the disk is not over its ceiling yet (" .. was .. ")",
		was <= CeroSecOS.MAX_TOTAL_BYTES)
	okAt(state, admin, "mv " .. hist .. " " .. loot, {}, env)
	local over = select(2, CeroSecOS.usage(state))
	check("the rename put it over (" .. over .. " of " .. CeroSecOS.MAX_TOTAL_BYTES .. ")",
		over > CeroSecOS.MAX_TOTAL_BYTES)
	eq("nothing was deleted to make room",
		state.fs.children.home.children.admin.children["loot.txt"] ~= nil, true)

	-- Over quota is a runtime refusal and not corruption: the machine boots.
	eq("the state still validates", CeroSecOS.validate(state), true)
	eq("and migrate hands the same machine back", CeroSecOS.migrate(state, "ksp-front-01"), state)

	-- And every further write says so until room is made.
	badAt(state, admin, "echo more >> " .. loot, "echo: " .. loot .. ": disk full", env)
	badAt(state, admin, "touch /home/admin/another",
		"touch: /home/admin/another: disk full", env)
	okAt(state, admin, "rm " .. loot, {}, env)
	okAt(state, admin, "touch /home/admin/another", {}, env)
end

-- 34c. Every account's own history, and four of them on a machine
do
	local state = fresh()
	local env = { now = FIXED, nowMs = 1000, jobs = {} }
	local rootSession = CeroSecOS.rootSession()

	-- A home somewhere else entirely: the exemption reads /etc/passwd and not
	-- /home.
	addUser(state, "x", "", "/home/x")
	check("x has a home", CeroSecOS.createNode(state, rootSession, "/home/x",
		CeroSecOS.newDir("x", CeroSecOS.HOME_MODE), nil) ~= nil)
	local xs = open(state, "x")
	eq("x's history goes in", CeroSecOS.historyAppend(state, xs, "id", FIXED), true)
	eq("and it is exempt where his passwd line says his home is",
		CeroSecOS.exemptUsage(state), #"id")

	-- And root's own, which is exempt whatever /etc/passwd has been edited into.
	eq("root's history goes in", CeroSecOS.historyAppend(state, rootSession, "ls", FIXED), true)
	eq("and is exempt too", CeroSecOS.exemptUsage(state), #"id" + #"ls")
	local passwd = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	local kept = passwd.data
	passwd.data = "nonsense"
	eq("root's history is exempt with no passwd line at all",
		CeroSecOS.exemptUsage(state), #"ls")
	passwd.data = kept

	-- Four histories' worth on a whole machine, and the fifth account writes
	-- nothing: the ceiling is the same one it always was, and it is what the
	-- usage count hands out.
	local sessions = { xs }
	local names = { "a", "b", "c", "d", "e" }
	for i = 1, #names do
		addUser(state, names[i], "", "/home/" .. names[i])
		check(names[i] .. " has a home", CeroSecOS.createNode(state, rootSession,
			"/home/" .. names[i], CeroSecOS.newDir(names[i], CeroSecOS.HOME_MODE), nil) ~= nil)
		sessions[#sessions + 1] = open(state, names[i])
	end
	local grown, refused = 0, 0
	for i = 1, #sessions do
		local grew = false
		for _ = 1, 1200 do
			if CeroSecOS.historyAppend(state, sessions[i], "echo padding line here", FIXED) then
				grew = true
			end
		end
		if grew then grown = grown + 1 else refused = refused + 1 end
	end
	check("some accounts filled a history (" .. grown .. ")", grown > 1)
	check("and the rest were refused (" .. refused .. ")", refused > 0)
	check("the exempt bytes stayed inside their ceiling (" ..
		CeroSecOS.exemptUsage(state) .. " of " .. CeroSecOS.MAX_EXEMPT_BYTES .. ")",
		CeroSecOS.exemptUsage(state) <= CeroSecOS.MAX_EXEMPT_BYTES)
	check("and got close enough to prove it was reached (" ..
		CeroSecOS.exemptUsage(state) .. ")",
		CeroSecOS.exemptUsage(state) > CeroSecOS.HISTORY_EXEMPT_BYTES - CeroSecOS.HISTORY_BYTES)
	check("and the machine still boots after all of that",
		CeroSecOS.validate(state) == true)
	eq("the histories' own ceiling is four of them", CeroSecOS.HISTORY_EXEMPT_BYTES,
		4 * CeroSecOS.HISTORY_BYTES)
end

-- 34d. The old flag is taken off on the way in
do
	local state = fresh()
	local hist = CeroSecOS.newFile("admin", CeroSecOS.HISTORY_MODE, "echo hi")
	hist.nq = true
	state.fs.children.home.children.admin.children[CeroSecOS.HISTORY_NAME] = hist
	state.fs.children.etc.children.motd.nq = true
	local back = CeroSecOS.migrate(state, "ksp-front-01")
	eq("the machine came back", back, state)
	eq("the flag is off the history", hist.nq, nil)
	eq("and off every other node", state.fs.children.etc.children.motd.nq, nil)
	eq("and the history is exempt all the same", CeroSecOS.exemptUsage(state), #"echo hi")
end

--
-- 35. Names that begin with a dot
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }

	okAt(state, admin, "echo hi > .profile", {}, env)
	okAt(state, admin, "echo bye > plain", {}, env)

	okAt(state, admin, "ls", { "plain" }, env)
	okAt(state, admin, "ls -A", { ".profile  plain" }, env)
	okAt(state, admin, "ls -a", { ".         ..        .profile  plain" }, env)
	-- -F marks the directories, the two entries included.
	okAt(state, admin, "ls -aF", { "./        ../       .profile  plain" }, env)
	-- The later of -a and -A wins, the way a real ls reads the pair.
	okAt(state, admin, "ls -aA", { ".profile  plain" }, env)
	okAt(state, admin, "ls -Aa", { ".         ..        .profile  plain" }, env)

	-- Long form: the same rule, and "." and ".." are the directory and the one
	-- above it.
	local long = okAt(state, admin, "ls -l", nil, env)
	eq("the long form hides it too", #long, 1)
	long = okAt(state, admin, "ls -la", nil, env)
	eq("and shows four rows with -a", #long, 4)
	check("the first row is this directory", string.find(long[1], "  %.$") ~= nil)
	check("the second is the one above it", string.find(long[2], "  %.%.$") ~= nil)
	check("and the dotted file is there", string.find(long[3], "%.profile$") ~= nil)
	long = okAt(state, admin, "ls -lA", nil, env)
	eq("and two rows with -A", #long, 2)

	-- Nothing else changed: a dotted name is a name.
	okAt(state, admin, "cat .profile", { "hi" }, env)
	okAt(state, admin, "cp .profile .copy", {}, env)
	okAt(state, admin, "rm .copy", {}, env)
	badAt(state, admin, "ls -z", "ls: -z: unknown option", env)
end

--
-- 36. What lives in the shell and what lives in /bin
--
-- The six the shell runs itself are still FILES: resolved through /bin/<name>
-- before the engine runs them, so the disk is the truth about what a machine
-- can do. The reserved words and the state builtins are not, and could not be.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local root = open(state, "root")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }

	-- Every one of them has an executable.
	local names = { "echo", "printf", "test", "[", "true", "false", "sleep", "sh", "halt" }
	for i = 1, #names do
		local node = state.fs.children.bin.children[names[i]]
		check("/bin/" .. names[i] .. " is there", node ~= nil and node.type == "file")
	end

	-- Delete one and the command is gone with it.
	okAt(state, admin, "echo works", { "works" }, env)
	okAt(state, root, "rm /bin/echo", {}, env)
	badAt(state, admin, "echo works", "echo: command not found", env)

	-- Shut one and it is out of everybody's reach, root's included: 600 leaves
	-- no x bit at all, and that is the one thing a mode still says to root.
	-- Give it back one x bit and it is root's again, and still nobody else's.
	okAt(state, root, "chmod 600 /bin/printf", {}, env)
	badAt(state, admin, "printf hi", "printf: permission denied", env)
	badAt(state, root, "printf hi", "printf: permission denied", env)
	okAt(state, root, "chmod 700 /bin/printf", {}, env)
	badAt(state, admin, "printf hi", "printf: permission denied", env)
	okAt(state, root, "printf hi", { "hi" }, env)

	okAt(state, root, "rm /bin/[", {}, env)
	badAt(state, admin, "[ 1 = 1 ]", "[: command not found", env)
	okAt(state, admin, "test 1 = 1", {}, env)

	-- The reserved words and the state builtins have no file and need none:
	-- there is nothing in /bin to delete, and the words still work on a machine
	-- whose /bin has been emptied.
	local words = { "if", "then", "elif", "else", "fi", "for", "while", "until",
		"do", "done", "read", "shift", "break", "continue", "history" }
	for i = 1, #words do
		eq("no /bin/" .. words[i], state.fs.children.bin.children[words[i]], nil)
		eq("and no usage line for it", CeroSecOS.commandUsage(words[i]), nil)
	end

	-- And the four the shell IS that still carry a manual entry. `cd` cannot be
	-- a file -- a program cannot move the shell that ran it -- and neither can
	-- exit, jobs or wait, which are the shell's own or own what it started. They
	-- keep their description and their usage line and have no executable.
	local shellWords = { "cd", "exit", "jobs", "wait" }
	for i = 1, #shellWords do
		local word = shellWords[i]
		eq("no /bin/" .. word, state.fs.children.bin.children[word], nil)
		eq(word .. " is a word of the shell", CeroSecOS.isShellWord(word), true)
		eq("and not in the list /bin is filled from", (function()
			local names = CeroSecOS.binNames()
			for k = 1, #names do
				if names[k] == word then return true end
			end
			return false
		end)(), false)
		check(word .. " keeps its description", type(CeroSecOS.commandDesc(word)) == "string")
		check("and its usage line", type(CeroSecOS.commandUsage(word)) == "string")
		eq("and it runs with no file behind it", CeroSecOS.BUILTINS[word], true)
	end
	eq("ls is not one of them", CeroSecOS.isShellWord("ls"), false)
	-- A machine with no SHELL is a different question from a machine with no
	-- file: /bin/sh deleted leaves nothing to parse a line with, and the console
	-- lets exactly two words through anyway. A word of the shell is no use
	-- without the shell, so that set is not this one.
	eq("with no /bin/sh, exit is still answered", CeroSecOS.NO_SHELL_WORDS.exit, true)
	eq("and help", CeroSecOS.NO_SHELL_WORDS.help, true)
	eq("but not cd", CeroSecOS.NO_SHELL_WORDS.cd, nil)
	eq("nor jobs", CeroSecOS.NO_SHELL_WORDS.jobs, nil)
	eq("nor is pwd, which real Unix ships as a file too", CeroSecOS.isShellWord("pwd"), false)
	check("/bin/pwd is there", state.fs.children.bin.children.pwd ~= nil)
	check("/bin/su too", state.fs.children.bin.children.su ~= nil)

	okAt(state, root, "rm -r /bin", {}, env)
	-- `history` and not `true` as the condition: /bin/true is gone with the rest
	-- of /bin, and that is the point of the section above.
	okAt(state, admin, "if history; then history; fi", {}, env)
	okAt(state, admin, "for i in a; do history; done", {}, env)
	badAt(state, admin, "true", "true: command not found", env)
	-- cd on a machine with no /bin at all: it is the shell, and the shell is
	-- still standing.
	okAt(state, admin, "cd /etc", {}, env)
	eq("and it moved", admin.cwd, "/etc")
	okAt(state, admin, "cd", {}, env)
	eq("back home", admin.cwd, "/home/admin")
	CeroSecOS.restoreSystem(state)
	-- The repair puts back what a machine ships with, and these were never it.
	for i = 1, #shellWords do
		eq("the repair does not make /bin/" .. shellWords[i],
			state.fs.children.bin.children[shellWords[i]], nil)
	end
	okAt(state, admin, "cd /etc", {}, env)
	okAt(state, admin, "cd", {}, env)
	-- And the manual entry for one, which is the shell's and not a file's: man
	-- itself is a file, so this is asked of a repaired machine.
	local manCd = okAt(state, admin, "man cd", nil, env)
	eq("man cd answers", manCd[1], "cd - " .. CeroSecOS.commandDesc("cd"))
	eq("with its usage line", manCd[2], "usage: " .. CeroSecOS.commandUsage("cd"))
	eq("and says there is no file", manCd[3],
		"a word of the shell itself: no file in " .. CeroSecOS.BIN_PATH)
	okAt(state, admin, "man wait", nil, env)
	badAt(state, admin, "man telnet", "man: telnet: no manual entry", env)
	-- A word with no Lua behind it is not a command, which is the other half of
	-- the same rule.
	okAt(state, root, 'echo "not yet" > /bin/telnet', {}, env)
	okAt(state, root, "chmod 755 /bin/telnet", {}, env)
	badAt(state, admin, "telnet", "telnet: command not found", env)

	-- help lists the files, and then the words that are not files.
	local helpLines = okAt(state, admin, "help", nil, env)
	local whole = table.concat(helpLines, "\n")
	check("help names the shell's own words",
		string.find(whole, CeroSecOS.HELP_RESERVED, 1, true) ~= nil)
	check("and its state builtins",
		string.find(whole, CeroSecOS.HELP_BUILTINS, 1, true) ~= nil)
	check("under a heading that says they have no file",
		string.find(whole, "shell words (no file in " .. CeroSecOS.BIN_PATH .. "):", 1, true) ~= nil)
	check("and the block names cd", string.find(whole, "cd", 1, true) ~= nil)
	-- The listing ABOVE that heading is /bin itself, so a shell word is never a
	-- line of it -- it is named in the block below and nowhere else.
	local heading = nil
	for k = 1, #helpLines do
		if string.find(helpLines[k], "shell words", 1, true) ~= nil then heading = k end
	end
	check("the block has a heading", heading ~= nil)
	for i = 1, #shellWords do
		eq("no line of the table of files describes " .. shellWords[i], (function()
			for k = 1, heading - 1 do
				if string.sub(helpLines[k], 1, 1 + #shellWords[i]) == " " .. shellWords[i] then
					return true
				end
			end
			return false
		end)(), false)
	end
end

--
-- 36a. What is in /bin, pinned by hand
--
-- The list of files a machine ships with is a decision, not whatever the
-- description table happens to hold: written out here so that adding a name to
-- COMMAND_INFO cannot quietly put an executable on every machine, and so that
-- the four words the shell IS can never come back as files.
--

do
	local state = fresh()
	local root = open(state, "root")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }
	local WANT = "[ arp call cat chgrp chmod chown clear cp crontab cu cut date dev df"
		.. " echo edit false find grep groupadd groupdel groups halt head"
		.. " help hostname id ifconfig kill last ln ls mail man mkdir mkpasswd more mount"
		.. " mv newfs passwd ping"
		.. " printf ps pwd rcp reboot rlogin rm rsh ruptime rwho"
		.. " sh shutdown"
		.. " sleep sort su sudo tail tee test touch tr true umount uniq uptime"
		.. " useradd userdel usermod w wc which who whoami"

	eq("/bin holds exactly these",
		table.concat(CeroSecOS.childNames(state.fs.children.bin), " "), WANT)
	eq("and that is the list it is filled from",
		table.concat(CeroSecOS.binNames(), " "), WANT)

	-- The same answer through the command a player would type.
	local shown = {}
	local lines = okAt(state, root, "ls /bin", nil, env)
	for i = 1, #lines do
		for word in string.gmatch(lines[i], "%S+") do shown[#shown + 1] = word end
	end
	table.sort(shown)
	eq("ls /bin shows exactly them", table.concat(shown, " "), WANT)
end

--
-- 36b. An older machine loses the files that were never commands
--

do
	local stale = { "cd", "exit", "jobs", "wait" }

	-- A machine as SYSTEM_VERSION 7 left it: the four executables that version
	-- seeded, in the shape it seeded them in.
	local state = fresh()
	for i = 1, #stale do
		state.fs.children.bin.children[stale[i]] =
			CeroSecOS.newFile("root", 755, CeroSecOS.commandDesc(stale[i]))
	end
	state.sysv = 7
	eq("the upgrade has something to do", CeroSecOS.upgradeSystem(state), true)
	for i = 1, #stale do
		eq("/bin/" .. stale[i] .. " is gone", state.fs.children.bin.children[stale[i]], nil)
	end
	eq("and the machine is at this build", state.sysv, CeroSecOS.SYSTEM_VERSION)
	eq("and it still boots", CeroSecOS.validate(state), true)
	eq("and the boot check is happy with it", CeroSecOS.systemOk(state), true)
	local admin = open(state, "admin")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }
	okAt(state, admin, "cd /etc", {}, env)
	eq("cd still moves, with nothing in /bin to run", admin.cwd, "/etc")

	-- Anything but the shape that was shipped is a player's own file and is left
	-- exactly where it is: a deletion nobody asked for is not a migration.
	local kept = fresh()
	local bin = kept.fs.children.bin.children
	bin.cd = CeroSecOS.newFile("admin", 755, CeroSecOS.commandDesc("cd"))
	bin.exit = CeroSecOS.newFile("root", 755, "a note of my own")
	bin.jobs = CeroSecOS.newFile("root", 644, CeroSecOS.commandDesc("jobs"))
	bin.wait = CeroSecOS.newDir("root", 755)
	kept.sysv = 7
	CeroSecOS.upgradeSystem(kept)
	check("a file of another owner is left alone", bin.cd ~= nil)
	check("one with contents of its own is left alone", bin.exit ~= nil)
	check("one with another mode is left alone", bin.jobs ~= nil)
	check("and a directory is left alone", bin.wait ~= nil)
	-- And the stray file changes nothing about the word: it is the shell's, and
	-- nothing looks the file up.
	local keptAdmin = open(kept, "admin")
	okAt(kept, keptAdmin, "chmod 000 /bin/cd", {}, env)
	okAt(kept, keptAdmin, "cd /etc", {}, env)
	eq("cd is not gated on a file it does not use", keptAdmin.cwd, "/etc")
end

--
-- 37. shutdown, with a clock on it
--

do
	local state = fresh()
	local root = open(state, "root")
	local admin = open(state, "admin")
	local env = { now = FIXED, nowMs = 100000, jobs = {} }

	-- The wording is Unix's, to the exclamation mark.
	eq("five minutes", CeroSecOS.shutdownLine("reboot", 5),
		"The system is going down for reboot in 5 minutes!")
	eq("one minute is not a plural", CeroSecOS.shutdownLine("reboot", 1),
		"The system is going down for reboot in 1 minute!")
	eq("now is NOW", CeroSecOS.shutdownLine("reboot", 0),
		"The system is going down for reboot NOW!")
	eq("and a halt says halt", CeroSecOS.shutdownLine("shutdown", 5),
		"The system is going down for halt in 5 minutes!")

	-- Scheduling: the broadcast is the command's own output, so it reaches every
	-- screen at the machine the way any other line does.
	local r = runAt(state, root, "shutdown -r +5", env)
	eq("it is taken", r.ok, true)
	eq("the order is to schedule", r.control, "schedule")
	eq("five minutes out, in wall-clock milliseconds", r.data.at, 100000 + 5 * 60000)
	eq("as a reboot", r.data.kind, "reboot")
	eq("and it says so on the screen", r.lines[1],
		"The system is going down for reboot in 5 minutes!")

	-- One at a time.
	local pending = { at = r.data.at, kind = "reboot" }
	local env2 = { now = FIXED, nowMs = 100000, jobs = {}, shutdown = pending }
	badAt(state, root, "shutdown -h +1", "shutdown: already scheduled", env2)

	-- Cancelling.
	r = runAt(state, root, "shutdown -c", env2)
	eq("cancelling is taken", r.ok, true)
	eq("and ordered", r.control, "cancel")
	eq("with the one line Unix prints", r.lines[1], "shutdown: cancelled")
	badAt(state, root, "shutdown -c", "shutdown: no shutdown scheduled", env)

	-- What is not a time.
	badAt(state, root, "shutdown +0",
		"shutdown: usage: shutdown [-h|-r] [now|+N] | shutdown -c", env)
	badAt(state, root, "shutdown +9999",
		"shutdown: usage: shutdown [-h|-r] [now|+N] | shutdown -c", env)
	badAt(state, root, "shutdown -x",
		"shutdown: usage: shutdown [-h|-r] [now|+N] | shutdown -c", env)
	-- A machine with no clock cannot be given a time.
	badAt(state, root, "shutdown -r +5", "shutdown: no clock", { now = FIXED, jobs = {} })

	-- Root's, all of it.
	badAt(state, admin, "shutdown -r +5", "shutdown: permission denied", env)
	badAt(state, admin, "shutdown -c", "shutdown: permission denied", env2)
end


--
-- 38. Completion at the prompt
--
-- CeroSecOS.complete is what Tab asks. Every case below is the exact string it
-- must put in the line and the exact names it must offer, because a completion
-- that is nearly right is a completion that eats a character of somebody's
-- filename.
--

-- One completion, spelled out: the replacement, the names, and where the
-- replacement goes.
local function comp(state, session, line, cursor)
	return CeroSecOS.complete(state, session, line, cursor or #line)
end

local function completes(state, session, line, want, at)
	local r = comp(state, session, line)
	eq('"' .. line .. '" completes to "' .. tostring(want) .. '"', r.replacement, want)
	if at ~= nil then eq('"' .. line .. '" replaces from ' .. at, r.start, at) end
	return r
end

local function offers(state, session, line, want)
	local r = comp(state, session, line)
	eq('"' .. line .. '" offers ' .. want, table.concat(r.candidates, " "), want)
	return r
end

do
	local state = fresh()
	local admin = open(state, "admin")
	local root = open(state, "root")

	local function put(path, text)
		local done, reason = CeroSecOS.writeFile(state, admin, path, text or "x", false, FIXED)
		if done == nil then error("cannot write " .. path .. ": " .. tostring(reason), 2) end
	end
	local function dir(path, mode)
		local done, reason = CeroSecOS.createNode(state, admin, path,
			CeroSecOS.newDir("admin", mode or 755, FIXED), FIXED)
		if done == nil then error("cannot mkdir " .. path .. ": " .. tostring(reason), 2) end
	end

	put("/home/admin/notes.txt")
	put("/home/admin/note2.txt")
	put("/home/admin/.profile")
	dir("/home/admin/work")
	-- Enterable and unreadable: x without r, which is the one case a listing
	-- must refuse while a path through it still works.
	dir("/home/admin/closed", 300)
	put("/home/admin/closed/inside")

	--
	-- Command names, in the first word.
	--
	completes(state, admin, "ls", "ls ", 1)
	offers(state, admin, "ls", "ls")
	-- Three of them share a letter and nothing more, so the line does not move.
	completes(state, admin, "l", "l", 1)
	offers(state, admin, "l", "last ln ls")
	-- Unique, and the space says so: a command name is finished when it is found.
	completes(state, admin, "whoa", "whoami ", 1)
	-- A whole command name that is also the start of another is a prefix and not
	-- a match: `who` gets no space, because `whoami` is still on the table.
	completes(state, admin, "who", "who", 1)
	offers(state, admin, "who", "who whoami")
	-- Several: as far as they agree and not a character further.
	completes(state, admin, "grou", "group", 1)
	offers(state, admin, "grou", "groupadd groupdel groups")
	-- And not a character further than they agree: grep shares only the "gr".
	completes(state, admin, "gr", "gr", 1)
	offers(state, admin, "gr", "grep groupadd groupdel groups")
	-- The words the shell IS are candidates too, and they have no file in /bin.
	offers(state, admin, "whil", "while")
	offers(state, admin, "cd", "cd")
	offers(state, admin, "hi", "history")
	-- help is a file AND a builtin, and is offered once.
	offers(state, admin, "help", "help")
	-- Nothing at all: no match, nothing put in the line.
	completes(state, admin, "zz", nil)
	-- The first word is a NAME and never a path: there is no PATH here, so a
	-- directory of the cwd is not a command.
	completes(state, admin, "wor", nil)

	-- An executable an ordinary account may not run is not offered to him, and
	-- is offered to root.
	local lsNode = CeroSecOS.getNode(state, root, "/bin/ls")
	lsNode.mode = 700
	lsNode.owner = "root"
	completes(state, admin, "ls", nil)
	completes(state, root, "ls", "ls ", 1)
	lsNode.mode = 755
	lsNode.owner = "root"

	--
	-- Paths, everywhere else.
	--
	completes(state, admin, "cat no", "note", 5)
	offers(state, admin, "cat no", "note2.txt notes.txt")
	completes(state, admin, "cat notes", "notes.txt ", 5)
	-- A directory ends in "/" so the next component can be typed straight on.
	completes(state, admin, "ls wo", "work/", 4)
	-- Absolute, and through a parent.
	completes(state, admin, "ls /et", "/etc/", 4)
	completes(state, admin, "ls work/../not", "work/../note", 4)
	offers(state, admin, "ls /etc/h", "hostname hosts hosts.equiv")
	-- And a dotted name is one name: "hosts" is a prefix of "hosts.equiv", so
	-- neither of them finishes and the line stops where they part.
	completes(state, admin, "ls /etc/hosts", "/etc/hosts", 4)
	-- The directory half comes back exactly as it was typed.
	completes(state, admin, "cat /etc/mo", "/etc/motd ", 5)

	--
	-- The tilde: the shell's, expanded for the lookup and left alone in the line.
	--
	completes(state, admin, "cat ~", "~/", 5)
	completes(state, admin, "cat ~/not", "~/note", 5)
	completes(state, admin, "cat ~/notes", "~/notes.txt ", 5)

	--
	-- Hidden entries: only when the segment being typed starts with a dot.
	--
	offers(state, admin, "ls ", "closed note2.txt notes.txt work")
	completes(state, admin, "cat .", ".profile ", 5)
	offers(state, admin, "cat .", ".profile")

	--
	-- A directory the account may not read answers nothing at all -- not the
	-- names, and not an error either.
	--
	completes(state, admin, "cat closed/", nil)
	offers(state, admin, "cat closed/", "")
	-- Root walks through the bits, here as everywhere.
	completes(state, root, "cat /home/admin/closed/", "/home/admin/closed/inside ")
	-- And a path through a directory with no x on it is not reachable at all.
	local shut = CeroSecOS.getNode(state, admin, "/home/admin/work")
	shut.mode = 600
	completes(state, admin, "cat work/", nil)
	shut.mode = 755

	--
	-- Quoting. A double-quoted word is completed and the quote is closed for a
	-- unique file, the way ksh closes it; a single-quoted one is text and is
	-- left alone.
	--
	completes(state, admin, "cat \"no", "note", 6)
	completes(state, admin, "cat \"notes", "notes.txt\" ", 6)
	completes(state, admin, "cat 'no", nil)
	completes(state, admin, "cat \"no\" a", nil)
	-- A word carrying a variable or an escape: what it expands to is the job's
	-- business, so nothing is offered.
	completes(state, admin, "cat $x", nil)
	completes(state, admin, "cat no\\t", nil)
	completes(state, admin, "echo $((1+no", nil)

	--
	-- Where a command begins. Word one, and after each separator.
	--
	completes(state, admin, "echo a; ls", "ls ", 9)
	completes(state, admin, "echo a && ls", "ls ", 11)
	completes(state, admin, "echo a || ls", "ls ", 11)
	completes(state, admin, "echo a | ls", "ls ", 10)
	completes(state, admin, "echo a & ls", "ls ", 10)
	completes(state, admin, "echo $(ls", "ls ", 8)
	-- sudo runs a command, so the word after it is a command name.
	completes(state, admin, "sudo ls", "ls ", 6)
	completes(state, admin, "sudo sudo ls", "ls ", 11)
	-- And the word after THAT is a path again.
	completes(state, admin, "sudo cat no", "note", 10)
	-- A reserved word that opens a command is followed by one.
	completes(state, admin, "if ls", "ls ", 4)
	completes(state, admin, "while ls", "ls ", 7)
	-- A redirection is followed by a FILE and never by a command.
	completes(state, admin, "echo hi > no", "note", 11)
	completes(state, admin, "echo hi >> no", "note", 12)
	completes(state, admin, "echo hi > l", nil)

	--
	-- The caret, not the end of the line: what is to the right of it is not part
	-- of the word and is not touched.
	--
	local r = comp(state, admin, "cat no 2.txt", 6)
	eq("the word ends at the caret", r.replacement, "note")
	eq("and the replacement starts at the word", r.start, 5)
	-- An empty word at the caret is every entry of the cwd.
	offers(state, admin, "cat ", "closed note2.txt notes.txt work")
	r = comp(state, admin, "cat ", 4)
	eq("nothing typed yet, so nothing they agree on", r.replacement, "")
	eq("and the replacement goes where the word would", r.start, 5)

	--
	-- A device is a file on this machine, so a device completes like one.
	--
	local devices = fakeDevices({
		{ id = "light0", kind = "light", state = "on" },
		{ id = "light1", kind = "light", state = "off" },
		{ id = "lock0", kind = "lock", state = "locked" },
		{ id = "lock1", kind = "lock", state = "locked", dead = true },
	})
	local env = { now = FIXED, devices = devices }
	CeroSecOS.mountDev(state, env)
	completes(state, admin, "cat /dev/li", "/dev/light", 5)
	offers(state, admin, "cat /dev/li", "light0 light1")
	completes(state, admin, "cat /dev/lock0", "/dev/lock0 ", 5)
	-- A device the machine knows the number of and cannot reach is not on the
	-- shelf, exactly as `ls /dev` does not show it.
	offers(state, admin, "cat /dev/lock", "lock0")
	CeroSecOS.unmountDev(state, env)
	completes(state, admin, "cat /dev/li", nil)

	--
	-- Nothing believed on its word: junk in, an empty answer out, never a crash.
	--
	local none = { replacement = nil, candidates = {}, start = 1 }
	local function empty(what, r)
		check(what .. ": nothing offered", r.replacement == none.replacement
			and type(r.candidates) == "table" and #r.candidates == 0
			and type(r.start) == "number")
	end
	empty("no state", CeroSecOS.complete(nil, admin, "l", 1))
	empty("no session", CeroSecOS.complete(state, nil, "l", 1))
	empty("no user", CeroSecOS.complete(state, { cwd = "/" }, "l", 1))
	empty("no line", CeroSecOS.complete(state, admin, nil, 1))
	-- A cursor past the line, or before it, is clamped rather than believed.
	eq("a cursor past the end is the end", CeroSecOS.complete(state, admin, "ls", 99).replacement,
		"ls ")
	eq("and one below the start is the start",
		CeroSecOS.complete(state, admin, "ls", -5).replacement, "")
end

--
-- 39. Pipelines (rung 5b)
--
-- `a | b` is one job with two shells in it. What is pinned here: the lines
-- really travel, every stage is a SUBSHELL (so a `read` or a `cd` in one is
-- gone with it), the status of a pipeline is its last stage's, a reader that
-- closes kills the writer with 141, and the two new commands print exactly
-- what they print.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local C = CeroSecOS.STEP_COST_COMMAND
	put(state, admin, "/home/admin/fruit", "pear\napple\npear\nfig")
	put(state, admin, "/home/admin/nums", "3\n20\n100")

	-- The lines travel, and nothing of the pipe reaches the screen but the last
	-- stage's output.
	ok(state, admin, "echo hi | cat", { "hi" })
	ok(state, admin, "cat fruit | cat", { "pear", "apple", "pear", "fig" })
	ok(state, admin, "cat fruit | grep pear", { "pear", "pear" })
	ok(state, admin, "cat fruit | grep -n pear", { "1:pear", "3:pear" })
	ok(state, admin, "cat fruit | head -n 2", { "pear", "apple" })
	ok(state, admin, "cat fruit | tail -n 1", { "fig" })
	ok(state, admin, "cat fruit | wc", { "     4      4     19" })
	-- The flags work on a pipe exactly as they work on a file: there is no name
	-- to put after the numbers, and wc has never invented one.
	ok(state, admin, "cat fruit | wc -l", { "     4" })
	ok(state, admin, "cat fruit | wc -c", { "    19" })
	ok(state, admin, "cat fruit | wc -lc", { "     4     19" })
	ok(state, admin, "cat fruit | grep -v pear", { "apple", "fig" })
	ok(state, admin, "cat fruit | grep -c pear", { "2" })
	ok(state, admin, "cat fruit | grep -cv pear", { "2" })
	-- A count of nothing is one line and a refusal, down a pipe as anywhere.
	ok(state, admin, "cat fruit | grep -c plum || echo no", { "0", "no" })
	ok(state, admin, "cat fruit | head -1", { "pear" })
	ok(state, admin, "cat fruit | tail -1", { "fig" })
	-- Three stages, and the middle one really is in the middle.
	ok(state, admin, "cat fruit | sort | uniq", { "apple", "fig", "pear" })
	ok(state, admin, "cat fruit | sort | uniq -c",
		{ "      1 apple", "      1 fig", "      2 pear" })
	ok(state, admin, "cat fruit | sort | head -n 1", { "apple" })

	-- -u: the repeats dropped, which on a sorted list is what uniq does after it
	-- and is one command less in the pipeline.
	ok(state, admin, "sort -u fruit", { "apple", "fig", "pear" })
	ok(state, admin, "cat fruit | sort -u", { "apple", "fig", "pear" })
	ok(state, admin, "sort -ur fruit", { "pear", "fig", "apple" })
	ok(state, admin, "sort -u fruit | wc -l", { "     3" })
	-- What counts as a repeat is a line the comparison cannot tell from the one
	-- before it, and that comparison ends in the bytes: two spellings of the same
	-- number are two lines.
	put(state, admin, "/home/admin/dupnums", "01\n1\n1")
	ok(state, admin, "sort -nu dupnums", { "01", "1" })

	-- sort: bytes by default, numbers with -n, either of them backwards with -r.
	ok(state, admin, "sort nums", { "100", "20", "3" })
	ok(state, admin, "sort -n nums", { "3", "20", "100" })
	ok(state, admin, "sort -nr nums", { "100", "20", "3" })
	ok(state, admin, "sort -r nums", { "3", "20", "100" })
	ok(state, admin, "cat nums | sort -n", { "3", "20", "100" })
	-- A line with no number at the front of it is a zero, and ties fall back to
	-- the bytes so the answer is the same answer every time.
	put(state, admin, "/home/admin/mixed", "b\n2\na\n1")
	ok(state, admin, "sort -n mixed", { "a", "b", "1", "2" })
	-- uniq drops the line it has just seen and nothing else: it does not sort.
	ok(state, admin, "uniq fruit", { "pear", "apple", "pear", "fig" })
	ok(state, admin, "uniq -c fruit",
		{ "      1 pear", "      1 apple", "      1 pear", "      1 fig" })
	bad(state, admin, "sort -q nums", "sort: -q: unknown option")
	bad(state, admin, "uniq -q fruit", "uniq: -q: unknown option")
	bad(state, admin, "sort nope", "sort: nope: no such file")
	bad(state, admin, "uniq nope", "uniq: nope: no such file")
	-- No file and no pipe is no standard input at all, and the usage line is
	-- what a machine with no terminal input can honestly answer.
	bad(state, admin, "sort", "sort: usage: sort [-r] [-n] [-u] [file]...")
	bad(state, admin, "uniq", "uniq: usage: uniq [-c] [file]")
	bad(state, admin, "wc", "wc: usage: wc [-clw] [file]...")

	-- The status of a pipeline is the LAST stage's.
	ok(state, admin, "cat fruit | grep pear && echo yes", { "pear", "pear", "yes" })
	ok(state, admin, "cat fruit | grep plum || echo no", { "no" })
	ok(state, admin, "cat nope | wc", { "cat: nope: no such file", "     0      0      0" })
	ok(state, admin, "echo $?", { "0" })
	-- A stage's REFUSAL is not output: it goes to the screen and not down the
	-- pipe, exactly as it stays on the screen when output is redirected.
	ok(state, admin, "ls /nope | wc",
		{ "ls: /nope: no such file", "     0      0      0" })

	-- Every stage is a subshell. `read` in one really does read the pipe -- it
	-- answers 0, which is a line read and not end of file -- and the variable it
	-- set is gone the moment the pipeline is over.
	ok(state, admin, "x=here; echo there | read x; echo $x", { "here" })
	ok(state, admin, "echo there | read x; echo $?", { "0" })
	ok(state, admin, "printf '' | read x; echo $?", { "1" })
	ok(state, admin, "cd /tmp | echo x", { "x" })
	ok(state, admin, "pwd", { "/home/admin" })

	-- A pipe inside $(...), which is the shape a script really uses.
	ok(state, admin, "echo $(cat fruit | sort | head -n 1)", { "apple" })
	ok(state, admin, "x=$(cat fruit | wc); echo $x", { "4 4 19" })
	ok(state, admin, "x=$(cat fruit | wc -l); echo $x", { "4" })

	-- A redirect on a stage writes the stage's output, once: a command that
	-- reads a pipe is run again and again, and the file must not be truncated
	-- every time it is.
	ok(state, admin, "cat fruit | sort > sorted", {})
	ok(state, admin, "cat sorted", { "apple", "fig", "pear", "pear" })
	ok(state, admin, "echo one | cat > single", {})
	ok(state, admin, "cat single", { "one" })

	-- The editor cannot open on a stage: a stage has no screen. Neither can a
	-- question be answered in a stage that READS a pipe: the answer comes back
	-- through the continuation, which carries the command's own arguments and no
	-- pipe behind them, so the command would run with nothing on its input. A
	-- stage with nothing on its input asks like any other command and is answered
	-- on the console (section 42).
	ok(state, admin, "edit fruit | cat", { "edit: not a terminal" })
	expect(state, admin, "cat fruit | sudo cat", false, { "sudo: not a terminal" })
	expect(state, admin, "echo hi | passwd", false, { "passwd: not a terminal" })
	-- And a `read` with no pipe on its input reads end of file, the way a
	-- background job's does: `read x | cat` answers 1 and waits for nobody.
	ok(state, admin, "read x | cat", {})
	ok(state, admin, "echo $?", { "0" })
end

--
-- 39a. A reader that closes kills the writer: SIGPIPE, and 141
--

do
	local state = fresh()
	local admin = open(state, "admin")

	-- The flood every player writes by accident, with a `head` in front of it.
	-- It ENDS, and it ends because head closed the pipe.
	local run = runScript(state, admin, "while true; do echo y; done | head -n 1\n")
	eq("a flood into head ends", run.job.state, "done")
	eq("with the one line head asked for", #run.out, 1)
	eq("which is the line", run.out[1], "y")
	-- And in a handful of steps, not in a hundred thousand.
	check("having cost very little (" .. run.job.steps .. ")", run.job.steps < 200)

	-- The status is head's, because a pipeline's status is its last stage's --
	-- the writer's 141 is the writer's own.
	local status = runScript(state, admin,
		"while true; do echo y; done | head -n 1\necho done=$?\n")
	eq("the pipeline's status is the reader's", status.out[2], "done=0")

	-- The 141 itself, on the stage that was killed. Asked of the engine, because
	-- nothing prints it: a writer killed by a pipe closing is the ordinary end
	-- of `yes | head`, not something a player has to read about.
	eq("SIGPIPE is 128 plus 13", CeroSecOS.SIGPIPE_STATUS, 141)
	local job = CeroSecOS.newJob({
		prog = CeroSecOS.parseScript("while true; do echo y; done | head -n 1"),
		session = admin, id = 7,
	})
	local env = { now = FIXED, nowMs = 1000, jobs = { job } }
	local frame, said = nil, {}
	-- A step at a time, so the frame is still there to look at: a pipeline this
	-- short is over inside one pass of a hundred.
	for _ = 1, 400 do
		CeroSecOS.jobStep(state, job, env, 1)
		for i = 1, #job.frames do
			if job.frames[i].k == "pipe" then frame = job.frames[i] end
		end
		for i = 1, #job.out do said[#said + 1] = job.out[i] end
		job.out = {}
		if CeroSecOS.jobIsOver(job) then break end
	end
	check("the pipeline had a frame of its own", frame ~= nil)
	eq("two stages", #frame.stages, 2)
	eq("the writer was killed", frame.stages[1].state, "killed")
	eq("with 141", frame.stages[1].status, CeroSecOS.SIGPIPE_STATUS)
	-- And nothing was said about it: the one line is head's output.
	eq("one line on the screen", #said, 1)
	eq("and it is the line head read", said[1], "y")
end

--
-- 39b. What a pipeline costs, and what it holds
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local C = CeroSecOS.STEP_COST_COMMAND
	put(state, admin, "/home/admin/fruit", "pear\napple\npear\nfig")

	-- Every stage is charged to the job that asked for the pipeline, and a
	-- command that reads a pipe is charged every time it runs: cat once, and
	-- the reader once for the lines and once more for the end of them.
	local run = runScript(state, admin, "cat fruit | wc\n")
	eq("a two-stage pipeline is charged to the one job", run.job.steps, 4 * C)
	-- A builtin on the left of a pipe is still a builtin.
	local cheap = runScript(state, admin, "echo hi | cat\n")
	eq("and a builtin in a stage still costs one", cheap.job.steps, 1 + 3 * C)

	-- The pipe itself is bounded: a hundred lines and four kilobytes, which is
	-- the number the back-pressure is applied at.
	eq("a pipe holds a hundred lines", CeroSecOS.PIPE_LINES, 100)
	eq("and four kilobytes", CeroSecOS.PIPE_BYTES, 4096)

	-- sort and tail cannot answer before the end of their input, so they keep
	-- it -- and what they keep meets the pipe's own ceiling rather than growing.
	local flood = runScript(state, admin,
		"i=0\nwhile [ $i -lt 200 ]; do echo line$i; i=$((i+1)); done | sort\n",
		nil, nil, { passes = 2000 })
	eq("sort gives up on more than a pipe may hold", flood.job.state, "done")
	eq("saying so in one line", flood.out[#flood.out], "sort: input too large")

	-- wc keeps three numbers and nothing else, so the same flood is counted
	-- through to the end of it.
	local counted = runScript(state, admin,
		"i=0\nwhile [ $i -lt 200 ]; do echo line$i; i=$((i+1)); done | wc\n",
		nil, nil, { passes = 2000 })
	eq("wc counts a flood it will never hold", counted.out[#counted.out],
		"   200    200   1489")
end

--
-- 40. cron: what a crontab means (rung 5b)
--
-- The format, field for field, and Vixie's own refusals: a machine that took a
-- line he would have refused, or refused one he would have taken, is a machine
-- whose crontab(5) is a lie.
--

do
	-- Every form a field may wear.
	local function entry(line)
		local e, reason = CeroSecOS.parseCronLine(line)
		check("`" .. line .. "` parses (" .. tostring(reason) .. ")", e ~= nil)
		return e or {}
	end
	local function refused(line, want)
		local e, reason = CeroSecOS.parseCronLine(line)
		eq("`" .. line .. "` is refused", e, nil)
		eq("`" .. line .. "` says", reason, want)
	end
	local function members(set)
		local out = {}
		for k in pairs(set or {}) do out[#out + 1] = k end
		table.sort(out)
		return table.concat(out, ",")
	end

	eq("a star is every minute there is", members(entry("* * * * * x").min),
		"0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28," ..
		"29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54," ..
		"55,56,57,58,59")
	eq("one number is one minute", members(entry("5 * * * * x").min), "5")
	eq("a list is its members", members(entry("0,15,30,45 * * * * x").min), "0,15,30,45")
	eq("a range is every one of it", members(entry("10-13 * * * * x").min), "10,11,12,13")
	eq("a step over a star", members(entry("*/15 * * * * x").min), "0,15,30,45")
	eq("a step over a range", members(entry("10-20/5 * * * * x").min), "10,15,20")
	eq("and the two mixed", members(entry("0,30-32,*/20 * * * * x").min), "0,20,30,31,32,40")
	eq("the hour field", members(entry("0 0,12 * * * x").hour), "0,12")
	eq("the day of the month", members(entry("0 0 1,15 * * x").dom), "1,15")
	eq("the month", members(entry("0 0 * 1-3 * x").month), "1,2,3")
	eq("the day of the week", members(entry("0 0 * * 1-5 x").dow), "1,2,3,4,5")
	-- Seven is Sunday and so is zero: one line matches the same day either way.
	eq("seven is Sunday and so is nought", members(entry("0 0 * * 7 x").dow), "0,7")
	-- The command is the rest of the line, whole: it is shell and not a word list.
	eq("the command is the rest of the line", entry("0 4 * * * echo a; echo b").cmd,
		"echo a; echo b")
	eq("and the blanks in front of it are not part of it",
		entry("0   4   *   *   *     echo hi").cmd, "echo hi")
	-- Which fields were a bare star, because that is what the day rule turns on.
	eq("a star is remembered as one", entry("0 4 * * * x").domStar, true)
	eq("and a number is not", entry("0 4 1 * * x").domStar, false)

	-- A step only follows a star or a range. Vixie reads it nowhere else, so
	-- `5/10` is not a minute -- it is a mistake in the minute field.
	refused("5/10 * * * * x", "bad minute")
	refused("*/0 * * * * x", "bad minute")
	refused("20-10 * * * * x", "bad minute")
	refused("60 * * * * x", "bad minute")
	refused("-1 * * * * x", "bad minute")
	refused("* 24 * * * x", "bad hour")
	refused("* * 0 * * x", "bad day-of-month")
	refused("* * 32 * * x", "bad day-of-month")
	refused("* * * 0 * x", "bad month")
	refused("* * * 13 * x", "bad month")
	refused("* * * * 8 x", "bad day-of-week")
	-- Names are not accepted, and the field they are in is what says so.
	refused("* * * jan * x", "bad month")
	refused("* * * * mon x", "bad day-of-week")
	-- Too few fields: the field that was never there is the one that is named.
	refused("* * * *", "bad day-of-week")
	refused("* *", "bad day-of-month")
	-- Five fields and nothing after them is a line with no command on it.
	refused("* * * * *", "bad command")
	refused("@reboot", "bad command")
	-- A shorthand that is not one, and one with the wrong case: Vixie compares
	-- them letter for letter.
	refused("@nope echo x", "bad time specifier")
	refused("@Daily echo x", "bad time specifier")
	refused("@ echo x", "bad time specifier")

	-- Comments and blank lines are not lines at all: no entry, and no refusal.
	local function nothing(line)
		local e, reason = CeroSecOS.parseCronLine(line)
		eq("`" .. line .. "` is no entry", e, nil)
		eq("`" .. line .. "` is no refusal either", reason, nil)
	end
	nothing("")
	nothing("   ")
	nothing("# every day at four")
	nothing("   # indented")

	-- The shorthands, and what each of them is the long way round.
	eq("@hourly is on the hour", members(entry("@hourly x").min), "0")
	eq("and every hour", entry("@hourly x").hour[13], true)
	eq("@daily is midnight", members(entry("@daily x").hour), "0")
	eq("@midnight is the same thing", members(entry("@midnight x").hour), "0")
	eq("@weekly is Sunday", members(entry("@weekly x").dow), "0")
	eq("@monthly is the first", members(entry("@monthly x").dom), "1")
	eq("@yearly is the first of January", members(entry("@yearly x").month), "1")
	eq("@annually is the same thing", members(entry("@annually x").month), "1")
	eq("@reboot is not a time at all", entry("@reboot echo up").reboot, true)
	eq("and carries its command", entry("@reboot echo up").cmd, "echo up")
end

--
-- 40a. cron: when a line is due
--

do
	-- Thursday the 8th of July 1993, at 14:32 -- the machine's fixed moment.
	local parts = CeroSecOS.dateParts(FIXED)
	eq("the fixed moment is a Thursday", CeroSecOS.DAY_NAMES[parts.wday], "Thu")
	local function due(line, at)
		local e, reason = CeroSecOS.parseCronLine(line)
		check("`" .. line .. "` parses (" .. tostring(reason) .. ")", e ~= nil)
		return CeroSecOS.cronDue(e, CeroSecOS.dateParts(at or FIXED))
	end

	eq("every minute", due("* * * * * x"), true)
	eq("this minute", due("32 14 * * * x"), true)
	eq("the minute before", due("31 14 * * * x"), false)
	eq("the hour before", due("32 13 * * * x"), false)
	eq("a step that lands on it", due("*/16 * * * * x"), true)
	eq("a step that does not", due("*/15 * * * * x"), false)
	eq("this month", due("32 14 * 7 * x"), true)
	eq("next month", due("32 14 * 8 * x"), false)
	eq("this day of the month", due("32 14 8 * * x"), true)
	eq("another one", due("32 14 9 * * x"), false)
	eq("this day of the week", due("32 14 * * 4 x"), true)
	eq("another one", due("32 14 * * 5 x"), false)

	-- The rule nobody expects and every cron has: with BOTH day fields
	-- restricted, either one matching is enough.
	eq("the day of the month matches and the weekday does not",
		due("32 14 8 * 5 x"), true)
	eq("the weekday matches and the day of the month does not",
		due("32 14 9 * 4 x"), true)
	eq("and neither", due("32 14 9 * 5 x"), false)
	-- With one of them a star it is the other that decides, and not both.
	eq("a star day of the month leaves it to the weekday",
		due("32 14 * * 5 x"), false)

	-- @reboot is never due at a minute: it is due when the machine comes up, and
	-- the scheduler asks that question another way.
	eq("@reboot is due at no minute at all", due("@reboot x"), false)

	-- Midnight, and the day rolling over.
	local midnight = CeroSecOS.timeFromParts(1993, 7, 9, 0, 0, 0)
	eq("@daily at midnight", due("@daily x", midnight), true)
	eq("and the day is the ninth now", due("0 0 9 * * x", midnight), true)
	eq("@hourly at midnight too", due("@hourly x", midnight), true)
	eq("the first of the month", due("@monthly x",
		CeroSecOS.timeFromParts(1993, 8, 1, 0, 0, 0)), true)
	eq("the first of the year", due("@yearly x",
		CeroSecOS.timeFromParts(1994, 1, 1, 0, 0, 0)), true)
	-- Nothing is due on a table that is not one.
	eq("junk is never due", CeroSecOS.cronDue(nil, parts), false)
	eq("nor is a real entry at no time at all",
		CeroSecOS.cronDue(CeroSecOS.parseCronLine("* * * * * x"), nil), false)
end

--
-- 40b. cron: a whole crontab, and what crontab(1) says about a bad one
--

do
	local entries, errors = CeroSecOS.parseCrontab(
		"# the header\n\n* * * * * echo one\n0 4 * * * echo two\n")
	eq("two entries", #entries, 2)
	eq("no refusals", #errors, 0)
	eq("and each knows the line it was on", entries[1].line, 3)
	eq("the second too", entries[2].line, 4)

	-- A file with one bad line in it: the good ones are still entries, and the
	-- bad one is a refusal with its own line number.
	local some, why = CeroSecOS.parseCrontab("* * * * * echo one\n60 * * * * x\n@nope y")
	eq("the good line is an entry", #some, 1)
	eq("and the two bad ones are refusals", #why, 2)
	eq("the first names its line", why[1].line, 2)
	eq("and its reason", why[1].reason, "bad minute")
	eq("the second as well", why[2].line, 3)
	eq("and its reason", why[2].reason, "bad time specifier")

	-- What crontab(1) prints: the file, the line, the field. Vixie's shape
	-- exactly, quotes and all.
	eq("the refusal reads the way crontab prints it",
		CeroSecOS.checkCrontab("/var/spool/cron/admin", "* * * * * ok\n60 * * * * x"),
		"\"/var/spool/cron/admin\":2: bad minute")
	eq("and a file that is one is not refused at all",
		CeroSecOS.checkCrontab("/var/spool/cron/admin", "* * * * * ok"), nil)
	eq("an empty one is a file too",
		CeroSecOS.checkCrontab("/var/spool/cron/admin", ""), nil)
	eq("and so is a file of nothing but comments",
		CeroSecOS.checkCrontab("/var/spool/cron/admin", "# nothing\n\n# doing"), nil)

	-- Thirty-two lines, and the thirty-third.
	local full = string.rep("* * * * * x\n", CeroSecOS.CRON_MAX_LINES)
	eq("thirty-two entries is a crontab", CeroSecOS.checkCrontab("/f", full), nil)
	eq("and thirty-three is not",
		CeroSecOS.checkCrontab("/f", full .. "* * * * * x"),
		"\"/f\":33: too many entries")
end

--
-- 40c. crontab and mail, at the prompt
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local spool = CeroSecOS.cronPath("admin")

	-- Nothing yet, and Vixie's line for it.
	badAt(state, admin, "crontab -l", "no crontab for admin")
	badAt(state, admin, "crontab -r", "no crontab for admin")
	badAt(state, admin, "crontab", "crontab: usage: crontab -e|-l|-r")
	badAt(state, admin, "crontab -x", "crontab: usage: crontab -e|-l|-r")
	badAt(state, admin, "crontab -l -r", "crontab: usage: crontab -e|-l|-r")

	-- -e makes the file and opens the editor on it AS ROOT, which is the whole
	-- of the privilege this command has: the spool is 700 and root's, and an
	-- account that could write it could write anybody's.
	local r = runAt(state, admin, "crontab -e")
	eq("crontab -e opens the editor", r.control, "edit")
	eq("on the account's own file in the spool", r.data.path, spool)
	eq("as root", r.data.user, "root")
	eq("and says what is being edited", r.data.crontab, true)
	eq("with nothing in it yet", r.data.text, "")
	local node = CeroSecOS.systemNode(state, spool)
	check("the file is there now", node ~= nil and node.type == "file")
	eq("root's", node.owner, "root")
	eq("and nobody else's", node.mode, CeroSecOS.CRONTAB_MODE)

	-- An empty crontab is no crontab: quitting the editor without typing leaves
	-- the account exactly as it was.
	badAt(state, admin, "crontab -l", "no crontab for admin")

	-- The save, the way the editor does it -- as root, on that path.
	put(state, CeroSecOS.rootSession(), spool, "* * * * * echo tick\n0 4 * * * echo four")
	okAt(state, admin, "crontab -l", { "* * * * * echo tick", "0 4 * * * echo four" })
	-- And the file itself is still out of reach of the account it belongs to:
	-- crontab is the only way in.
	badAt(state, admin, "cat " .. spool, "cat: " .. spool .. ": permission denied")
	badAt(state, admin, "ls " .. CeroSecOS.CRON_PATH,
		"ls: " .. CeroSecOS.CRON_PATH .. ": permission denied")
	badAt(state, admin, "edit " .. spool, "edit: " .. spool .. ": permission denied")

	-- -e on a crontab that is there hands the editor what is in it.
	local again = runAt(state, admin, "crontab -e")
	eq("the editor opens on what is there", again.data.text,
		"* * * * * echo tick\n0 4 * * * echo four")

	-- -r takes it away, and there is nothing to take away twice.
	okAt(state, admin, "crontab -r", {})
	eq("the file is gone", CeroSecOS.systemNode(state, spool), nil)
	badAt(state, admin, "crontab -r", "no crontab for admin")

	-- Another account's crontab is its own: a second one gets its own file.
	addUser(state, "bob", "", "/home/bob")
	local bob = open(state, "bob", "")
	runAt(state, bob, "crontab -e")
	check("bob has a file of his own",
		CeroSecOS.systemNode(state, CeroSecOS.cronPath("bob")) ~= nil)
	eq("and it is not admin's", CeroSecOS.systemNode(state, spool), nil)

	-- mail: nothing, then something, then nothing again -- reading is what
	-- empties it.
	okAt(state, admin, "mail", { "No mail for admin" })
	badAt(state, admin, "mail -f", "mail: usage: mail")
	CeroSecOS.mailAppend(state, "admin", "ksp-front-01", "echo hi", { "hi" }, FIXED)
	okAt(state, admin, "mail", {
		"From cron  Thu Jul  8 14:32:00 1993",
		"Subject: Cron <admin@ksp-front-01> echo hi",
		"",
		"hi",
	})
	okAt(state, admin, "mail", { "No mail for admin" })
	-- The mailbox is the account's own, 600, and nobody else's to read.
	local box = CeroSecOS.systemNode(state, CeroSecOS.mailPath("admin"))
	eq("the mailbox belongs to the account", box.owner, "admin")
	eq("and nobody else reads it", box.mode, CeroSecOS.MAIL_MODE)
	badAt(state, bob, "cat " .. CeroSecOS.mailPath("admin"),
		"cat: " .. CeroSecOS.mailPath("admin") .. ": permission denied")
end

--
-- 40d. The log, the mailbox, and the two ceilings on them
--

do
	local state = fresh()
	local root = open(state, "root")
	local _, before = CeroSecOS.usage(state)

	-- A hundred lines of log and no more, oldest dropped -- the rule the history
	-- file already runs on.
	for i = 1, 250 do CeroSecOS.cronLog(state, "(admin) CMD (echo " .. i .. ")", FIXED) end
	local log = CeroSecOS.systemNode(state, CeroSecOS.CRON_LOG_PATH)
	check("the log is there", log ~= nil)
	eq("root's", log.owner, "root")
	eq("and root's to read", log.mode, CeroSecOS.CRON_LOG_MODE)
	local lines = CeroSecOS.splitLines(log.data)
	eq("a hundred lines at most", #lines, CeroSecOS.CRON_LOG_LINES)
	check("and four kilobytes at most (" .. #log.data .. ")",
		#log.data <= CeroSecOS.CRON_LOG_BYTES)
	eq("the newest is the last thing said", lines[#lines],
		CeroSecOS.formatStamp(FIXED) .. " (admin) CMD (echo 250)")
	-- It is exempt from the disk quota by its PATH, so `df` did not move.
	local _, after = CeroSecOS.usage(state)
	eq("the disk did not move", after, before)
	-- An ordinary account cannot read it at all.
	local admin = open(state, "admin")
	badAt(state, admin, "cat " .. CeroSecOS.CRON_LOG_PATH,
		"cat: " .. CeroSecOS.CRON_LOG_PATH .. ": permission denied")
	okAt(state, root, "cat " .. CeroSecOS.CRON_LOG_PATH, nil)

	-- The mailbox, the same way: bounded, exempt, and the oldest dropped.
	for i = 1, 300 do
		CeroSecOS.mailAppend(state, "admin", "ksp", nil, { "line " .. i }, FIXED)
	end
	local box = CeroSecOS.systemNode(state, CeroSecOS.mailPath("admin"))
	local mailLines = CeroSecOS.splitLines(box.data)
	eq("a hundred lines at most", #mailLines, CeroSecOS.MAIL_LINES)
	check("and four kilobytes at most (" .. #box.data .. ")",
		#box.data <= CeroSecOS.MAIL_BYTES)
	eq("the newest is the last thing said", mailLines[#mailLines], "line 300")
	local _, still = CeroSecOS.usage(state)
	eq("and the disk still did not move", still, before)
	check("the machine boots with both of them there", CeroSecOS.validate(state) == true)

	-- Renamed, a mailbox is an ordinary file from that moment on: the exemption
	-- is the PATH's and rides on nothing carried by the node.
	okAt(state, root, "mv " .. CeroSecOS.mailPath("admin") .. " /root/kept", nil)
	local _, moved = CeroSecOS.usage(state)
	check("what was exempt costs the disk the moment it is moved (" ..
		moved .. " of " .. still .. ")", moved > still)

	-- Mail with nothing in it is not a delivery at all.
	eq("no lines, no mail", CeroSecOS.mailAppend(state, "admin", "ksp", nil, {}, FIXED), false)
end

--
-- 41. Waiting on a device, which is a loop and not a command (rung 5b)
--
-- Unix has no "wait until this file says something", and neither does this
-- machine: what it has is a loop with a `sleep` in it, which is how every Unix
-- script has waited for anything since there were scripts.
--
--   while [ "$(cat /dev/door0)" = closed ]; do sleep 5; done
--
-- So what has to be TRUE is not that a command exists -- it is that this costs
-- almost nothing. A sleep is free: the job is off the processor entirely and the
-- runaway clock is stopped while it waits. What one turn of the loop costs is one
-- test, one substitution and one sleep, and nothing at all happens in between.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local C = CeroSecOS.STEP_COST_COMMAND
	local devices = fakeDevices({
		{ id = "door0", kind = "door", desc = "front", state = "closed",
			becomes = { open = "open", close = "closed" } },
	})

	local watching = "while [ \"$(cat /dev/door0)\" = closed ]; do sleep 5; done\n"
		.. "echo the door is $(cat /dev/door0)\n"

	-- The door opens on the tenth pass. The clock moves a second a pass, so the
	-- script has slept through nine seconds of it by then -- two turns of a
	-- five-second loop.
	local run = runScript(state, admin, watching, nil, nil, {
		devices = devices, stepMs = 1000, passes = 40,
		between = function(pass)
			if pass == 10 then devices.entries[1].state = "open" end
		end,
	})
	eq("the script waited and then went on", run.job.state, "done")
	eq("and says what it found", run.out[#run.out], "the door is open")

	-- What it cost. One turn is the substitution's `cat` (a command, so
	-- STEP_COST_COMMAND), the `[` that judges it, the loop boundary and the
	-- `sleep` -- and the wait itself is free, however long it is.
	local turn = C + 3
	-- Three conditions were evaluated (two that held, one that did not), two
	-- bodies ran, and the last line is one more command's worth of substitution
	-- plus its echo.
	eq("and it cost what a handful of turns costs", run.job.steps,
		3 * (C + 1) + 2 * 2 + C + 1)
	check("which is under forty steps a turn (" .. turn .. ")", turn < 40)

	-- And the same loop with the door never opening: it waits for ever and costs
	-- the machine a turn every five seconds, which is what makes this idiom the
	-- answer rather than a busy loop.
	devices.entries[1].state = "closed"
	local forever = runScript(state, admin, watching, nil, nil, {
		devices = devices, stepMs = 1000, passes = 60,
	})
	eq("it is still waiting after a minute of it", forever.job.state, "sleeping")
	-- The proof that a wait is FREE: a sleeping job is off the processor, so the
	-- runaway clock is not running on it and it can wait for days.
	eq("and it is not on the processor at all", forever.job.cpuSince, nil)
	eq("nor has it been killed for spending it",
		CeroSecOS.jobOverCpu(forever.job, 740000000 * 1000, 300), false)
	-- Twelve turns in sixty seconds, and no more: the sleep is what bounds it.
	check("and cost twelve turns of it, not sixty (" .. forever.job.steps .. ")",
		forever.job.steps <= 13 * (C + 1) + 13)
	-- A busy version of the same loop -- no sleep in it -- is what the manual
	-- tells a player not to write, and it is the flood the budget already holds
	-- back: many times the steps for the same minute of waiting.
	local busy = runScript(state, admin,
		"while [ \"$(cat /dev/door0)\" = closed ]; do :; done\n", nil, nil, {
		devices = devices, stepMs = 1000, passes = 60, budget = 100,
	})
	-- It spends every step the machine will give it, every pass, for as long as
	-- it runs -- the budget is the only thing holding it back -- while the one
	-- with a sleep in it asks for nothing at all in between.
	check("a busy loop spends the whole budget (" .. busy.job.steps .. " in 60 passes)",
		busy.job.steps > 55 * 100)
	check("and the polling loop spends a tenth of a tenth of that (" ..
		forever.job.steps .. ")", forever.job.steps * 10 < busy.job.steps)
end

--
-- 42. A question with a redirect behind it
--
-- `sudo cat /etc/passwd > copie.txt` is two halves that do not happen at the
-- same time: the command asks for a password and only runs when the answer
-- comes back, and the redirect it was typed with has to still be there when it
-- does. What is pinned here: the file gets the file, ">>" appends, a refused
-- sudo leaves the empty file a shell's open always leaves, a stage of a
-- pipeline resumes where it stood, and the paths that never ask -- root,
-- NOPASSWD -- are untouched.
--

-- A line typed at the prompt that ASKS something, driven the way the console
-- drives it: the job is stepped, and every question is answered through
-- CeroSecOS.jobInput -- the one door an answer goes through on a real machine.
-- Answers are taken in order; a question past the end of the list is answered
-- with an empty line.
local function typed(state, session, line, answers)
	if session.shvars == nil then session.shvars = {} end
	local env = { now = 740000000, nowMs = 1000 }
	local job, refusal = CeroSecOS.promptJob(state, session, line, session.shvars,
		session.status)
	if job == nil then error("cannot type `" .. line .. "`: " .. tostring(refusal), 2) end
	local out, asked = {}, {}
	local at, passes = 1, 0
	while not CeroSecOS.jobIsOver(job) and passes < 200 do
		passes = passes + 1
		CeroSecOS.jobStep(state, job, env, 100)
		for i = 1, #job.out do out[#out + 1] = job.out[i] end
		job.out = {}
		if job.state == "waiting" and job.ask ~= nil then
			asked[#asked + 1] = job.ask.text
			CeroSecOS.jobInput(state, job, (answers or {})[at] or "", env)
			at = at + 1
		elseif job.state == "waiting" then
			break
		end
	end
	for i = 1, #job.out do out[#out + 1] = job.out[i] end
	job.out = {}
	session.user, session.cwd, session.stack = job.session.user, job.session.cwd,
		job.session.stack
	return { job = job, out = out, asked = asked, status = job.status }
end

-- What a file holds, read off the disk rather than through cat: the contents
-- are the point here and a fitted line is not a file.
local function contents(state, path)
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), path)
	if node == nil then return nil end
	return node.data
end

do
	local state = fresh()
	local admin = open(state, "admin")
	local passwd = contents(state, CeroSecOS.PASSWD_PATH)
	check("the accounts file is longer than a screen line",
		#CeroSecOS.splitLines(passwd)[1] > CeroSecOS.COLS)

	-- The whole of it, and not a word of it on the screen.
	local copy = typed(state, admin, "sudo cat /etc/passwd > copie.txt", { "" })
	eq("the password was asked for", copy.asked[1], "[sudo] password for admin: ")
	eq("and only once", #copy.asked, 1)
	eq("nothing reached the screen", #copy.out, 0)
	eq("the line succeeded", copy.status, 0)
	eq("and the file is the file, whole and unfolded",
		contents(state, "/home/admin/copie.txt"), passwd)

	-- ">>" adds to what is there. The open does not: a file already there is
	-- opened and left alone, or the append would be a blank line nobody wrote.
	ok(state, admin, "echo first > log", {})
	local added = typed(state, admin, "sudo echo second >> log", { "" })
	eq("the append succeeded", added.status, 0)
	eq("and added one line", contents(state, "/home/admin/log"), "first\nsecond")

	-- A wrong password writes nothing -- but the file is there and empty, because
	-- a shell opens what ">" names before the command runs and this one is no
	-- different.
	ok(state, admin, "echo old > refused", {})
	local no = typed(state, admin, "sudo cat /etc/passwd > refused", { "wrong" })
	eq("the refusal is on the screen", no.out[1], "sudo: authentication failure")
	eq("and only that", #no.out, 1)
	eq("the line failed", no.status, 1)
	eq("the file is still there", contents(state, "/home/admin/refused"), "")

	-- A target that cannot be opened is a command that does not run: the refusal
	-- comes instead of the question, exactly as a shell refuses the line.
	local shut = typed(state, admin, "sudo cat /etc/passwd > /root/copie.txt", { "" })
	eq("nothing was asked", #shut.asked, 0)
	eq("the refusal names the target", shut.out[1],
		"sudo: /root/copie.txt: permission denied")
	eq("the line failed", shut.status, 1)
	eq("and nothing was made", contents(state, "/root/copie.txt"), nil)

	-- The redirect is the SHELL's half of the line and is opened as whoever typed
	-- it, which is why that is refused at all: root's own copy of the same line
	-- writes where root may write.
	local rootSession = open(state, "root")
	local asRoot = typed(state, rootSession, "sudo cat /etc/passwd > /root/copie.txt")
	eq("root is asked for nothing", #asRoot.asked, 0)
	eq("and it writes", contents(state, "/root/copie.txt"), passwd)

	-- NOPASSWD is the other path that never asks, and it is untouched.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.SUDOERS_PATH, "admin NOPASSWD")
	local free = typed(state, admin, "sudo cat /etc/passwd > free.txt")
	eq("nothing was asked", #free.asked, 0)
	eq("and the file is the file", contents(state, "/home/admin/free.txt"), passwd)
end

-- A stage of a pipeline asks, and the stage is what resumes.
do
	local state = fresh()
	local admin = open(state, "admin")

	local piped = typed(state, admin, "sudo echo hi | cat", { "" })
	eq("the stage's question reached the console", piped.asked[1],
		"[sudo] password for admin: ")
	eq("and the pipeline carried on", piped.out[1], "hi")
	eq("with nothing else on the screen", #piped.out, 1)
	eq("the pipeline succeeded", piped.status, 0)

	-- A refusal in a stage goes to the SCREEN and not down the pipe, which is the
	-- rule a stage's errors have always run on.
	local wrong = typed(state, admin, "sudo echo hi | cat", { "no" })
	eq("the refusal is on the screen", wrong.out[1], "sudo: authentication failure")
	eq("and nothing went down the pipe", #wrong.out, 1)

	-- Whose redirect is whose: the question is the first stage's and the file is
	-- the last stage's, and neither loses its place.
	put(state, CeroSecOS.rootSession(), "/root/secret", "alpha\nbeta")
	bad(state, admin, "cat /root/secret", "cat: /root/secret: permission denied")
	local first = typed(state, admin, "sudo cat /root/secret | head -n 1 > first.txt", { "" })
	eq("the question was asked once", #first.asked, 1)
	eq("nothing reached the screen", #first.out, 0)
	eq("and the last stage wrote what it read",
		contents(state, "/home/admin/first.txt"), "alpha")

	-- A stage that reads a pipe is still refused a question: its answer would
	-- come back to a command with nothing on its input.
	expect(state, admin, "cat first.txt | sudo cat", false, { "sudo: not a terminal" })
end

-- A chain of questions carries the redirect the whole way: nothing is written
-- while it is still asking, and what the last answer says goes to the file.
do
	local state = fresh()
	local admin = open(state, "admin")

	local chain = typed(state, admin, "sudo passwd root > done.txt",
		{ "", "hunter2", "hunter2" })
	eq("three questions", #chain.asked, 3)
	eq("the first is sudo's", chain.asked[1], "[sudo] password for admin: ")
	eq("then the new password", chain.asked[2], "New password: ")
	eq("and the retype", chain.asked[3], "Retype new password: ")
	eq("nothing reached the screen", #chain.out, 0)
	eq("the line it printed is in the file", contents(state, "/home/admin/done.txt"),
		"passwd: password updated")
	check("and root's password is the one that was typed", holds(state, "root", "hunter2"))

	-- The refusal in the middle of a chain stays on the screen, and the file that
	-- was opened for it stays empty.
	local mismatch = typed(state, admin, "sudo passwd root > out.txt",
		{ "", "hunter3", "hunter4" })
	eq("the refusal is on the screen", mismatch.out[1], "passwd: passwords do not match")
	eq("and the file is empty", contents(state, "/home/admin/out.txt"), "")
end

--
-- 41. The network (rung 6a)
--
-- The engine's half, which is everything about the wire that does not know there
-- is a game: the four files, the arithmetic that turns a building into an
-- address, the shape of every line the five listing commands print, the trust
-- rules, and the pty table a session lives in. Whether two machines can hear each
-- other is the server's and is proved in tests/window_test.lua.
--

-- The address. Two bytes out of where the building stands, and the same answer
-- every time it is asked.
do
	local b1, b2 = CeroSecOS.buildingKey(400, 700)
	check("a building has a key", b1 ~= nil and b2 ~= nil)
	check("and both halves are bytes", b1 >= 0 and b1 <= 255 and b2 >= 0 and b2 <= 255)
	local c1, c2 = CeroSecOS.buildingKey(400, 700)
	check("asked twice it is the same key", c1 == b1 and c2 == b2)
	local d1, d2 = CeroSecOS.buildingKey(401, 700)
	check("the building next door is a different one", d1 ~= b1 or d2 ~= b2)
	-- A negative coordinate is a coordinate: the map has none, and a hash that
	-- answered nil for one would be a hash with a hole in it.
	local n1, n2 = CeroSecOS.buildingKey(-40, -70)
	check("and so is a negative one", n1 ~= nil and n1 >= 0 and n2 >= 0)
	eq("junk is no key", CeroSecOS.buildingKey("x", 1), nil)

	eq("an address reads the way it is written",
		CeroSecOS.addressText(4, 17, 2), "10.4.17.2")
	eq("and three numbers are needed for one", CeroSecOS.addressText(4, 17), nil)

	check("a dotted quad is one", CeroSecOS.isAddress("10.4.17.2"))
	check("and so is the loopback", CeroSecOS.isAddress("127.0.0.1"))
	check("256 is not a byte", not CeroSecOS.isAddress("10.4.17.256"))
	check("three numbers are not an address", not CeroSecOS.isAddress("10.4.17"))
	-- A leading zero is octal in every resolver ever written, so it is not a quad
	-- here either -- reading it as ten would be disagreeing with the file.
	check("a leading zero is not a quad", not CeroSecOS.isAddress("10.4.017.2"))
	check("a single zero is", CeroSecOS.isAddress("10.0.0.1"))
	check("and a name is not", not CeroSecOS.isAddress("gate"))
end

-- The record on the state, and the accessor that will not read half of one.
do
	local state = fresh()
	eq("a fresh machine has no address", CeroSecOS.address(state), nil)
	check("and no record", CeroSecOS.netRecord(state) == nil)
	check("one is written", CeroSecOS.setNetRecord(state, 4, 17, 2) ~= nil)
	eq("and read back", CeroSecOS.address(state), "10.4.17.2")

	-- Everything a forged save could carry in that field is a machine with NO
	-- address and never a machine with half of one.
	local forgeries = {
		{}, { b1 = 4 }, { b1 = 4, b2 = 17 }, { b1 = 4, b2 = 17, n = 0 },
		{ b1 = 4, b2 = 17, n = 255 }, { b1 = 4, b2 = 17, n = 1.5 },
		{ b1 = -1, b2 = 17, n = 2 }, { b1 = 256, b2 = 17, n = 2 },
		{ b1 = "4", b2 = 17, n = 2 },
	}
	for i = 1, #forgeries do
		state.net = forgeries[i]
		eq("forgery " .. i .. " is no address", CeroSecOS.address(state), nil)
	end
	state.net = "nonsense"
	eq("nor is a string", CeroSecOS.address(state), nil)
	-- And a state carrying one still validates: the field is read through the
	-- accessor and never off the table.
	CeroSecOS.setNetRecord(state, 4, 17, 2)
	check("a machine with an address validates", CeroSecOS.validate(state))
end

-- /etc/hosts, which is the only resolver there is.
do
	local order, byName, byAddr = CeroSecOS.parseHosts(
		"# a comment\n" ..
		"127.0.0.1 localhost\n" ..
		"10.4.17.3 gate pump\n" ..
		"10.4.17.4 office   # trailing comment\n" ..
		"\n" ..
		"nonsense here\n" ..
		"10.4.17.5\n" ..
		"10.4.17.6 NotAName\n" ..
		"10.4.17.3 second")
	eq("four lines parsed", #order, 4)
	eq("a name resolves", byName.gate.addr, "10.4.17.3")
	eq("an alias resolves to the same line", byName.pump.addr, "10.4.17.3")
	eq("a trailing comment is cut off", byName.office.addr, "10.4.17.4")
	check("a line with no name is skipped", byName["10.4.17.5"] == nil)
	check("a name no hostname could be is skipped", byName.NotAName == nil)
	-- An address that appears twice keeps its FIRST line, the way a lookup down a
	-- file does -- and so does a name.
	eq("the first line for an address wins", byAddr["10.4.17.3"].names[1], "gate")
	eq("and the second name is still a name", byName.second.addr, "10.4.17.3")

	local state = fresh()
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		"10.4.17.3 gate", FIXED)
	local addr, name = CeroSecOS.resolveHost(state, "gate")
	eq("a name is resolved out of the file", addr, "10.4.17.3")
	eq("and the name comes back as it was typed", name, "gate")
	eq("a name nothing carries is nothing", CeroSecOS.resolveHost(state, "pump"), nil)
	-- An address typed straight out needs no line at all, which is what makes
	-- ping usable on a machine whose /etc/hosts somebody emptied.
	local raw, rawName = CeroSecOS.resolveHost(state, "10.9.9.9")
	eq("an address resolves to itself", raw, "10.9.9.9")
	eq("and is its own name", rawName, "10.9.9.9")
	eq("an address in the file answers with the file's name",
		select(2, CeroSecOS.resolveHost(state, "10.4.17.3")), "gate")
end

-- The machine's own line, written exactly once.
do
	local state = fresh("ksp-04-11")
	CeroSecOS.setNetRecord(state, 4, 17, 2)
	check("the line is written", CeroSecOS.writeOwnHost(state, FIXED))
	local hosts = CeroSecOS.systemNode(state, CeroSecOS.HOSTS_PATH).data
	check("and it names the machine",
		string.find(hosts, "10.4.17.2 ksp-04-11", 1, true) ~= nil)
	check("asked again it writes nothing", not CeroSecOS.writeOwnHost(state, FIXED))
	eq("and the file is byte for byte what it was",
		CeroSecOS.systemNode(state, CeroSecOS.HOSTS_PATH).data, hosts)
	-- A file the player has emptied stays emptied: the machine writes its line
	-- once and the file is his from then on. Here it writes one because the name
	-- is not in it -- which is the only case it ever writes at all.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH, "", FIXED)
	check("a name that is gone can be written again", CeroSecOS.writeOwnHost(state, FIXED))
end

-- Trust: /etc/hosts.equiv, ~/.rhosts, and the two file tests rlogind makes.
do
	eq("a blank line is nothing", CeroSecOS.parseEquivLine(""), nil)
	eq("and a comment", CeroSecOS.parseEquivLine("# gate"), nil)
	eq("a bare host is a host", CeroSecOS.parseEquivLine("gate").host, "gate")
	check("with no account on it", CeroSecOS.parseEquivLine("gate").user == nil)
	eq("a host and an account", CeroSecOS.parseEquivLine("gate admin").user, "admin")
	-- And a line may name the machine by its address instead, which is the other
	-- spelling of the same machine and needs no /etc/hosts at all.
	eq("an address is a host too", CeroSecOS.parseEquivLine("10.4.17.3").host, "10.4.17.3")
	eq("with an account behind it",
		CeroSecOS.parseEquivLine("10.4.17.3 admin").user, "admin")
	eq("a word that is neither is nothing", CeroSecOS.parseEquivLine("10.4.17"), nil)
	-- A plus trusts the whole world, which was a hole in 1993 and is one now: it
	-- does not parse, so it trusts nobody rather than everybody.
	eq("a bare plus is not a line", CeroSecOS.parseEquivLine("+"), nil)
	eq("nor is a plus and a name", CeroSecOS.parseEquivLine("+ admin"), nil)
	eq("nor three words", CeroSecOS.parseEquivLine("gate admin extra"), nil)

	local state = fresh()
	addUser(state, "bob")
	CeroSecOS.createNode(state, CeroSecOS.rootSession(), "/home/bob",
		CeroSecOS.newDir("bob", CeroSecOS.HOME_MODE), FIXED)

	-- WHO IS ASKING is an ADDRESS, and a name in a trust file is matched against it
	-- through THIS machine's /etc/hosts and through nothing else. So the caller
	-- below is 10.4.17.3 throughout, and it is called "gate" here because a line of
	-- this machine's own file says so.
	local GATE = "10.4.17.3"
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		GATE .. " gate", FIXED)

	-- Nothing trusted on a shipped machine.
	check("a shipped machine trusts nobody",
		not CeroSecOS.trusts(state, "admin", GATE, "admin"))

	-- The machine-wide half.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH, "gate", FIXED)
	check("a bare host trusts the same account on it",
		CeroSecOS.equivOk(state, GATE, "admin", "admin"))
	check("and nobody in as anybody else",
		not CeroSecOS.equivOk(state, GATE, "bob", "admin"))
	check("nor a machine the file does not name",
		not CeroSecOS.equivOk(state, "10.4.17.9", "admin", "admin"))
	-- ruserok's own rule, and the most important line in it.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH,
		"gate\ngate root", FIXED)
	check("hosts.equiv never lets root in",
		not CeroSecOS.equivOk(state, GATE, "root", "root"))

	-- The account's own half, and the two facts about the FILE that decide
	-- whether a byte of it is read at all.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH, "", FIXED)
	local path = "/home/bob/.rhosts"
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), path, "gate bob", false, FIXED)
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), path)
	node.owner = "bob"
	node.mode = 600
	check("bob's own .rhosts at 600 is read", CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	-- The second field names the account COMING IN, which is ruserok's reading of
	-- it: bob's own file saying "gate admin" is bob letting gate's admin be him.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), path, "gate admin", FIXED)
	check("a line naming another account lets THAT account in as bob",
		CeroSecOS.rhostsOk(state, "bob", GATE, "admin"))
	check("and not whoever happens to be asking",
		not CeroSecOS.rhostsOk(state, "bob", GATE, "kate"))
	check("nor bob himself, whom the line does not name",
		not CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	CeroSecOS.setData(state, CeroSecOS.rootSession(), path, "gate bob", FIXED)
	node.owner = "admin"
	check("one owned by somebody else is ignored",
		not CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	node.owner = "root"
	check("root's is read, because root owns everything anyway",
		CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	node.owner = "bob"
	node.mode = 620
	check("one the group may write is ignored",
		not CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	node.mode = 602
	check("and one the world may write",
		not CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	node.mode = 644
	check("644 is readable by all and writable by none but bob",
		CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	node.mode = 666
	check("666 is not", not CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	node.mode = 600
	-- root IS trusted by his own .rhosts, which is the other half of the rule.
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/root/.rhosts", "gate root",
		false, FIXED)
	local rootFile = CeroSecOS.getNode(state, CeroSecOS.rootSession(), "/root/.rhosts")
	rootFile.owner = "root"
	rootFile.mode = 600
	check("root's own .rhosts does let root in",
		CeroSecOS.trusts(state, "root", GATE, "root"))

	-- The write bit of one digit, which is the whole of the mode test.
	check("6 is writable", CeroSecOS.digitWritable(6))
	check("7 is writable", CeroSecOS.digitWritable(7))
	check("2 is writable", CeroSecOS.digitWritable(2))
	check("4 is not", not CeroSecOS.digitWritable(4))
	check("5 is not", not CeroSecOS.digitWritable(5))
	check("0 is not", not CeroSecOS.digitWritable(0))
end

-- /var/log/wtmp: the records, and both ceilings.
do
	eq("a record parses", CeroSecOS.parseWtmpLine("in admin ttyp0 gate 741186720").user,
		"admin")
	eq("and its host", CeroSecOS.parseWtmpLine("in admin ttyp0 gate 741186720").host, "gate")
	eq("a dash is no host at all",
		CeroSecOS.parseWtmpLine("in admin console - 741186720").host, nil)
	eq("a kind that is neither is nothing",
		CeroSecOS.parseWtmpLine("sideways admin console - 741186720"), nil)
	eq("nor is a missing field", CeroSecOS.parseWtmpLine("in admin console -"), nil)
	eq("nor a time that is not one",
		CeroSecOS.parseWtmpLine("in admin console - later"), nil)

	local state = fresh()
	check("a record is appended", CeroSecOS.wtmpAppend(state, "in", "admin",
		CeroSecOS.CONSOLE_LINE, nil, FIXED))
	local node = CeroSecOS.systemNode(state, CeroSecOS.WTMP_PATH)
	eq("the file is root's", node.owner, "root")
	eq("and 644", node.mode, CeroSecOS.WTMP_MODE)
	eq("with the record in it", node.data, "in admin console - " .. FIXED)
	check("and a logout behind it", CeroSecOS.wtmpAppend(state, "out", "admin",
		CeroSecOS.CONSOLE_LINE, nil, FIXED + 60))
	eq("two lines now", #CeroSecOS.parseWtmp(node.data), 2)
	-- Bounded by lines: the oldest go, which is why "wtmp begins" is a real
	-- answer on this machine.
	for i = 1, CeroSecOS.WTMP_LINES + 20 do
		CeroSecOS.wtmpAppend(state, "in", "admin", "ttyp0", "gate", FIXED + i)
	end
	eq("the file is bounded by lines",
		#CeroSecOS.splitLines(node.data), CeroSecOS.WTMP_LINES)
	check("and by bytes", #node.data <= CeroSecOS.WTMP_BYTES)
	-- And it costs the 32K disk nothing, by its path, exactly as the cron log
	-- does: a machine must not fill its own drive with what it said about itself.
	local exempt = CeroSecOS.exemptPaths(state)
	check("wtmp is exempt by its path", exempt[CeroSecOS.WTMP_PATH] ~= nil)
	eq("and the exemption is root's", exempt[CeroSecOS.WTMP_PATH].owner, "root")
end

-- The shape of every line the listing commands print. Pinned to the character,
-- because a column that moves is a column somebody's eye has to hunt for.
do
	eq("who, at the keyboard",
		CeroSecOS.whoLine("admin", "console", FIXED),
		"admin    console  Jul  8 14:32")
	eq("who, from the wire",
		CeroSecOS.whoLine("bob", "ttyp0", FIXED, "ksp-a-a"),
		"bob      ttyp0    Jul  8 14:32  (ksp-a-a)")
	eq("and it fits the screen", #CeroSecOS.whoLine("sixteencharname", "ttyp0",
		FIXED, "sixteencharhost") <= 60, true)

	eq("last, still logged in",
		CeroSecOS.lastLine({ user = "admin", line = "console", at = FIXED }),
		"admin    console             Jul  8 14:32  still logged in")
	eq("last, with a logout behind it",
		CeroSecOS.lastLine({ user = "bob", line = "ttyp0", host = "ksp-a-a", at = FIXED },
			FIXED + 8 * 60),
		"bob      ttyp0    ksp-a-a    Jul  8 14:32 - 14:40  (00:08)")

	eq("ruptime, one user", CeroSecOS.ruptimeLine("gate", 3 * 86400 + 2 * 3600 + 15 * 60,
		1, 0.02), "gate      up  3+02:15,  1 user,  load 0.02")
	eq("ruptime, two", CeroSecOS.ruptimeLine("ksp-a-a", 41 * 60, 2, 0),
		"ksp-a-a   up  00:41,  2 users,  load 0.00")
	eq("and a load of one job", CeroSecOS.ruptimeLine("gate", 60, 1, 1),
		"gate      up  00:01,  1 user,  load 1.00")

	eq("rwho", CeroSecOS.rwhoLine("admin", "gate", "console", FIXED),
		"admin    gate:console     Jul  8 14:32")

	eq("a span under a day", CeroSecOS.spanText(41 * 60), "00:41")
	eq("a span over one", CeroSecOS.spanText(3 * 86400 + 2 * 3600 + 15 * 60), "3+02:15")
	eq("a span of nothing", CeroSecOS.spanText(0), "00:00")
	eq("and a negative one is nothing", CeroSecOS.spanText(-5), "00:00")
end

-- The ptys, and the fifth caller.
do
	local state = fresh()
	local ptys = {}
	eq("no lines are taken", CeroSecOS.ptyCount(ptys), 0)
	for i = 1, CeroSecOS.PTY_MAX do
		local pty, reason = CeroSecOS.remoteOpen(state, ptys, { fromHost = "gate", hops = 1 })
		check("line " .. i .. " opened", pty ~= nil and reason == nil)
		eq("and it is the lowest free one", pty.line, CeroSecOS.ptyLine(i - 1))
	end
	local fifth, reason = CeroSecOS.remoteOpen(state, ptys, { fromHost = "gate", hops = 1 })
	eq("the fifth is refused", fifth, nil)
	eq("in the words a full listener answers with", reason, "refused")
	eq("four are taken", CeroSecOS.ptyCount(ptys), CeroSecOS.PTY_MAX)

	-- A line that is given back is the next one handed out.
	CeroSecOS.remoteClose(state, ptys, CeroSecOS.ptyLine(1), nil, nil)
	eq("three are taken", CeroSecOS.ptyCount(ptys), CeroSecOS.PTY_MAX - 1)
	local again = CeroSecOS.remoteOpen(state, ptys, { fromHost = "gate", hops = 1 })
	eq("and the freed line is what comes back", again.line, CeroSecOS.ptyLine(1))

	-- A keystroke can never reach a session that is over.
	eq("a line that is gone is nothing",
		CeroSecOS.remoteLine(ptys, "ttyp9"), nil)
	check("and one that is not is the pty",
		CeroSecOS.remoteLine(ptys, CeroSecOS.ptyLine(0)) ~= nil)

	-- Closing with an account on it writes the logout; closing an empty one does
	-- not, because a caller who gave up at the password was never logged in.
	CeroSecOS.remoteClose(state, ptys, CeroSecOS.ptyLine(0), "admin", FIXED)
	local wtmp = CeroSecOS.systemNode(state, CeroSecOS.WTMP_PATH)
	check("the logout is recorded",
		string.find(wtmp.data, "out admin ttyp0 gate", 1, true) ~= nil)
	local before = wtmp.data
	CeroSecOS.remoteClose(state, ptys, CeroSecOS.ptyLine(2), nil, FIXED)
	eq("a session nobody got into leaves no record", wtmp.data, before)
	eq("a line nobody has is nothing to close",
		CeroSecOS.remoteClose(state, ptys, "ttyp9", "admin", FIXED), nil)
end

-- ifconfig, ping, who, last and the r-commands, through the shell.
do
	local state = fresh()
	CeroSecOS.setNetRecord(state, 4, 17, 2)
	local admin = open(state, "admin")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		"127.0.0.1 localhost\n10.4.17.2 ksp-front-01\n10.4.17.3 gate", FIXED)

	-- A machine with no link layer at all: nothing is reachable, nothing is
	-- listed, and no command invents a word about it.
	local lines = okAt(state, admin, "ifconfig", nil, ENV)
	eq("eth0 is up", lines[1], "eth0: flags=63<UP,BROADCAST,NOTRAILERS,RUNNING>")
	eq("with the address", lines[2], "      inet 10.4.17.2 netmask 0xffffff00")
	eq("lo0 under it", lines[3], "lo0: flags=8<LOOPBACK>")
	eq("with its own", lines[4], "      inet 127.0.0.1 netmask 0xff000000")
	eq("and that is all there is", #lines, 4)
	okAt(state, admin, "ruptime", {}, ENV)
	okAt(state, admin, "rwho", {}, ENV)
	badAt(state, admin, "ping pump", "ping: unknown host pump", ENV)
	badAt(state, admin, "rlogin pump", "rlogin: pump: unknown host", ENV)
	badAt(state, admin, "rlogin gate", "rlogin: gate: No route to host", ENV)
	badAt(state, admin, "rsh gate date", "rsh: gate: No route to host", ENV)

	-- The loopback is always reachable, whatever the link layer says.
	local ping = okAt(state, admin, "ping localhost", nil, ENV)
	eq("ping names what it pings", ping[1], "PING localhost (127.0.0.1): 56 data bytes")
	eq("and the first packet answers", ping[2],
		"64 bytes from 127.0.0.1: icmp_seq=0 ttl=255 time=0.4 ms")

	-- last, on a machine with a record on it.
	CeroSecOS.wtmpAppend(state, "in", "admin", CeroSecOS.CONSOLE_LINE, nil, FIXED)
	CeroSecOS.wtmpAppend(state, "out", "admin", CeroSecOS.CONSOLE_LINE, nil, FIXED + 480)
	CeroSecOS.wtmpAppend(state, "in", "bob", "ttyp0", "gate", FIXED + 600)
	local last = okAt(state, admin, "last", nil, ENV)
	eq("the newest is first", last[1],
		"bob      ttyp0    gate       Jul  8 14:42  still logged in")
	eq("and the closed one behind it", last[2],
		"admin    console             Jul  8 14:32 - 14:40  (00:08)")
	eq("with the file's own beginning", last[4], "wtmp begins Jul  8 14:32")
	-- A name narrows it, and a name nothing carries is an empty answer and not a
	-- refusal: an account that has never logged in is not a mistake.
	local mine = okAt(state, admin, "last bob", nil, ENV)
	eq("one account only", #mine, 3)
	eq("and it is his", string.sub(mine[1], 1, 3), "bob")
	local none = okAt(state, admin, "last nobody", nil, ENV)
	eq("a name with no logins answers only the beginning", #none, 2)

	-- who, with no link layer, is nobody: the sessions are the server's answer.
	okAt(state, admin, "who", {}, ENV)

	-- And every one of them refuses the wrong argument count with its own line.
	badAt(state, admin, "ifconfig a b", "ifconfig: usage: " ..
		CeroSecOS.commandUsage("ifconfig"), ENV)
	badAt(state, admin, "ping", "ping: usage: " .. CeroSecOS.commandUsage("ping"), ENV)
	badAt(state, admin, "who x", "who: usage: " .. CeroSecOS.commandUsage("who"), ENV)
	badAt(state, admin, "rcp one", "rcp: usage: " .. CeroSecOS.commandUsage("rcp"), ENV)
	badAt(state, admin, "rcp a b", "rcp: usage: " .. CeroSecOS.commandUsage("rcp"), ENV)
	badAt(state, admin, "rcp gate:a gate:b", "rcp: usage: " ..
		CeroSecOS.commandUsage("rcp"), ENV)
end

-- arp: the cards on the wire, and the name /etc/hosts does or does not give one
--
-- The command that closes the gap between ruptime, which broadcasts NAMES, and
-- /etc/hosts, which wants an ADDRESS. What is asserted is the shape of every line
-- 4.4BSD's own arp prints, and that not one of them is built out of the name a
-- machine announced about itself.
do
	-- The card is derived and stored nowhere: the same address answers the same
	-- three bytes for ever, and no two machines of one building share one.
	local mac = CeroSecOS.etherOf("10.4.17.3")
	eq("the card carries Sun's OUI", string.sub(mac, 1, #CeroSecOS.ETHER_OUI + 1),
		CeroSecOS.ETHER_OUI .. ":")
	eq("asked twice it is the same card", CeroSecOS.etherOf("10.4.17.3"), mac)
	check("six bytes of it", string.find(mac, "^8:0:20:%x+:%x+:%x+$") ~= nil)
	check("another machine is another card", CeroSecOS.etherOf("10.4.17.4") ~= mac)
	check("and another building too", CeroSecOS.etherOf("10.9.9.3") ~= mac)
	eq("a word that is no address has no card", CeroSecOS.etherOf("gate"), nil)
	eq("nor has a quad with a byte over 255", CeroSecOS.etherOf("10.4.17.256"), nil)

	-- printf's %x, which is what makes a real one read 8:0:20:1e:2a:4b and never
	-- 08:00:20:1e:2a:4b.
	eq("a byte under sixteen is one digit", CeroSecOS.etherByte(8), "8")
	eq("and over it is two", CeroSecOS.etherByte(30), "1e")
	eq("zero is zero", CeroSecOS.etherByte(0), "0")
	eq("255 is ff", CeroSecOS.etherByte(255), "ff")
	eq("and nothing outside a byte is one", CeroSecOS.etherByte(256), nil)

	-- The three derived bytes have to be three bytes and not one repeated: a hash
	-- that answered the same number three times would pass the pattern above.
	local seen, cards = {}, 0
	for n = 1, 40 do
		local one = CeroSecOS.etherOf("10.4.17." .. n)
		local x, y, z = string.match(one, "^8:0:20:(%x+):(%x+):(%x+)$")
		check("card " .. n .. " parses", x ~= nil)
		check("and every byte of it is a byte", tonumber(x, 16) <= 255
			and tonumber(y, 16) <= 255 and tonumber(z, 16) <= 255)
		if seen[one] == nil then seen[one] = true; cards = cards + 1 end
	end
	eq("forty machines are forty cards", cards, 40)

	-- The exact cards, pinned. Derived means derived for ever: a machine off a save
	-- made today has to answer the same three bytes next year, so the arithmetic is
	-- held to its answer and not merely to its shape.
	eq("the card of 10.4.17.3", CeroSecOS.etherOf("10.4.17.3"), "8:0:20:2:18:73")
	eq("the card of 10.4.17.4", CeroSecOS.etherOf("10.4.17.4"), "8:0:20:64:6d:9")
	eq("and of a machine in another building",
		CeroSecOS.etherOf("10.9.9.3"), "8:0:20:5a:18:5b")

	-- All THREE bytes have to come from the address. A byte derived from nothing is
	-- a byte that never moves, and the pattern above would not notice one: this
	-- sweeps 320 machines over 16 buildings and counts what each byte does.
	local one, two, three = {}, {}, {}
	local c1, c2, c3 = 0, 0, 0
	for b = 0, 15 do
		for n = 1, 20 do
			local x, y, z = CeroSecOS.etherKey(4, b, n)
			if one[x] == nil then one[x] = true; c1 = c1 + 1 end
			if two[y] == nil then two[y] = true; c2 = c2 + 1 end
			if three[z] == nil then three[z] = true; c3 = c3 + 1 end
		end
	end
	check("the first byte moves with the address (" .. c1 .. ")", c1 >= 64)
	check("so does the second (" .. c2 .. ")", c2 >= 8)
	check("and so does the third (" .. c3 .. ")", c3 >= 64)
	eq("three numbers that are not three numbers have no card",
		CeroSecOS.etherKey(4, 17, 300), nil)
end

do
	local state = fresh()
	CeroSecOS.setNetRecord(state, 4, 17, 2)
	local admin = open(state, "admin")
	-- This machine is .2 and knows one name besides its own.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		"127.0.0.1 localhost\n10.4.17.2 ksp-front-01\n10.4.17.3 gate", FIXED)

	-- A wire with three machines on it, and the peers arrive under the names they
	-- BROADCAST -- the third one calling itself "gate" as well, which is exactly
	-- what a machine whose root typed `hostname gate` would do. arp must not print
	-- a word of it.
	local WIRE = { ["10.4.17.2"] = true, ["10.4.17.3"] = true, ["10.4.17.4"] = true }
	local env = { now = FIXED, net = {
		reach = function(addr)
			if WIRE[addr] then return true end
			return false, "unreach"
		end,
		peers = function()
			return {
				{ host = "gate", addr = "10.4.17.4" },
				{ host = "ksp-front-01", addr = "10.4.17.2" },
				{ host = "zzz", addr = "10.4.17.3" },
			}
		end,
	} }

	local out = okAt(state, admin, "arp -a", nil, env)
	eq("a machine is not in its own cache", #out, 2)
	eq("an address a line of /etc/hosts names is printed by that name", out[1],
		"gate (10.4.17.3) at " .. CeroSecOS.etherOf("10.4.17.3"))
	eq("and one no line names is a question mark", out[2],
		"? (10.4.17.4) at " .. CeroSecOS.etherOf("10.4.17.4"))

	-- One entry, asked for by name and by address, and the name printed is the
	-- FILE's and not the word typed.
	okAt(state, admin, "arp gate",
		{ "gate (10.4.17.3) at " .. CeroSecOS.etherOf("10.4.17.3") }, env)
	okAt(state, admin, "arp 10.4.17.3",
		{ "gate (10.4.17.3) at " .. CeroSecOS.etherOf("10.4.17.3") }, env)
	okAt(state, admin, "arp 10.4.17.4",
		{ "? (10.4.17.4) at " .. CeroSecOS.etherOf("10.4.17.4") }, env)

	-- arp(8)'s two refusals. The first is the resolver's and is signed; the second
	-- is arp's own line about a machine it resolved and has no entry for, and it
	-- carries neither the command's name nor a colon.
	badAt(state, admin, "arp pump", "arp: pump: unknown host", env)
	badAt(state, admin, "arp 10.4.17.9", "10.4.17.9 (10.4.17.9) -- no entry", env)
	badAt(state, admin, "arp ksp-front-01",
		"ksp-front-01 (10.4.17.2) -- no entry", env)
	badAt(state, admin, "arp localhost", "localhost (127.0.0.1) -- no entry", env)
	-- A machine that is switched off is a machine the wire has not heard from,
	-- which is the same answer ruptime gives by leaving it out.
	WIRE["10.4.17.3"] = nil
	badAt(state, admin, "arp gate", "gate (10.4.17.3) -- no entry", env)
	WIRE["10.4.17.3"] = true

	badAt(state, admin, "arp", "arp: usage: " .. CeroSecOS.commandUsage("arp"), env)
	badAt(state, admin, "arp -a gate", "arp: usage: "
		.. CeroSecOS.commandUsage("arp"), env)

	-- And with no link layer at all -- a machine with the wire out of it -- the
	-- cache is empty and nothing is in it.
	okAt(state, admin, "arp -a", {}, ENV)
	badAt(state, admin, "arp gate", "gate (10.4.17.3) -- no entry", ENV)
end

-- An address is accepted everywhere a host is, and resolved with no lookup
--
-- The file is EMPTY here, so nothing but the dotted quad itself can be what
-- answered: a resolver that only knew names would refuse every line below.
do
	local state = fresh()
	CeroSecOS.setNetRecord(state, 4, 17, 2)
	local admin = open(state, "admin")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH, "", FIXED)
	local env = { now = FIXED, net = {
		reach = function(addr)
			if addr == "10.4.17.3" then return true end
			return false, "unreach"
		end,
		peers = function() return { { host = "zzz", addr = "10.4.17.3" } } end,
	} }

	local ping = okAt(state, admin, "ping 10.4.17.3", nil, env)
	eq("ping takes an address and names it", ping[1],
		"PING 10.4.17.3 (10.4.17.3): 56 data bytes")
	eq("and the packet came back from it", ping[2],
		"64 bytes from 10.4.17.3: icmp_seq=0 ttl=255 time=0.4 ms")

	local r = runAt(state, admin, "rlogin 10.4.17.3", env)
	eq("rlogin takes an address", r.ok, true)
	eq("and hands the machine over by it", r.control, "rlogin")
	eq("with the address as the host", r.data.host, "10.4.17.3")
	eq("and as the address", r.data.addr, "10.4.17.3")

	-- rsh's order goes to the MACHINE and not to the console, so the shell's job
	-- is left waiting on another computer rather than carrying a control back: the
	-- order itself is read off the command.
	local shOk, _, shControl, shData = CeroSecOS.runArgs(state, admin,
		{ "rsh", "10.4.17.3", "date" }, nil, env)
	eq("rsh takes one too", shOk, true)
	eq("and hands it out as an order", shControl, "rsh")
	eq("with the command behind it", shData.cmd, "date")
	eq("and the address as the host", shData.host, "10.4.17.3")
	local sh = runAt(state, admin, "rsh 10.4.17.3 date", env)
	eq("and through the shell the line is taken and not refused", sh.ok, true)
	eq("with nothing printed here", #sh.lines, 0)

	-- rcp's remote half is host:path, and the host half of it is an address as
	-- readily as a name (CeroSecOS.splitRemote).
	local host, path = CeroSecOS.splitRemote("10.4.17.3:/tmp/log")
	eq("rcp splits an address off a path", host, "10.4.17.3")
	eq("and keeps the path whole", path, "/tmp/log")
	env.net.copy = function(spec) return true, nil, 10 end
	local cp = runAt(state, admin, "rcp /etc/motd 10.4.17.3:/tmp/log", env)
	eq("and the copy is taken", cp.ok, true)

	-- arp as well, which is the point of it: a machine whose name nobody has
	-- written down is a machine you ask about by address.
	okAt(state, admin, "arp 10.4.17.3",
		{ "? (10.4.17.3) at " .. CeroSecOS.etherOf("10.4.17.3") }, env)

	-- And a quad that is not one is still a name, and is refused as a name.
	badAt(state, admin, "ping 10.4.17.256", "ping: unknown host 10.4.17.256", env)
	badAt(state, admin, "rlogin 10.4.017.3", "rlogin: 10.4.017.3: unknown host", env)

	-- A machine off the wire is named by the address in the refusal, which is what
	-- a real one prints when it cannot name it.
	badAt(state, admin, "rlogin 10.4.17.9", "rlogin: 10.4.17.9: No route to host", env)
end

-- Where a session came from: the name /etc/hosts gives the address, else the
-- address
--
-- gethostbyaddr(3) and rlogind's own reverse lookup. It is the RECEIVING
-- machine's file that decides, and what it never uses is the name the caller
-- announced -- see CeroSecOS.originOf.
do
	local state = fresh()
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		"127.0.0.1 localhost\n10.4.17.3 gate pump", FIXED)
	eq("an address the file names is that name", CeroSecOS.originOf(state, "10.4.17.3"),
		"gate")
	eq("and the aliases are on the same line",
		table.concat(CeroSecOS.hostsNames(state, "10.4.17.3"), " "), "gate pump")
	eq("an address no line carries is itself", CeroSecOS.originOf(state, "10.4.17.4"),
		"10.4.17.4")
	eq("a name is no address to look up", CeroSecOS.originOf(state, "gate"), nil)
	eq("and an address nothing names has no names",
		#CeroSecOS.hostsNames(state, "10.4.17.4"), 0)

	-- Both of them go into wtmp, because both are origins: the host column used to
	-- take a hostname, a telephone number or a callsign, and a bare quad is the
	-- fourth shape it has to hold -- an origin it refused would be a login `last`
	-- could not read.
	check("a quad is an origin", CeroSecOS.isWtmpOrigin("10.4.17.4"))
	check("and so is a name", CeroSecOS.isWtmpOrigin("gate"))
	check("a record from an address parses",
		CeroSecOS.parseWtmpLine("in admin ttyp0 10.4.17.4 741186720") ~= nil)
	eq("with the address in the host column",
		CeroSecOS.parseWtmpLine("in admin ttyp0 10.4.17.4 741186720").host, "10.4.17.4")
	check("and it is written", CeroSecOS.wtmpAppend(state, "in", "admin", "ttyp0",
		"10.4.17.4", FIXED))
	local admin = open(state, "admin")
	local last = okAt(state, admin, "last", nil, { now = FIXED })
	eq("last prints the address where a name would be", last[1],
		"admin    ttyp0    10.4.17.4  Jul  8 14:32  still logged in")
	eq("and who puts it in its brackets",
		CeroSecOS.whoLine("admin", "ttyp0", FIXED, "10.4.17.4"),
		"admin    ttyp0    Jul  8 14:32  (10.4.17.4)")
end

-- Trust is a question about an ADDRESS, and a name only through /etc/hosts
--
-- The security rule of the two trust files, and the one this wave came to fix: a
-- machine's own /etc/hostname is a 644 file its own root may write to anything, so
-- a far machine that matched a trust line against the name a caller ANNOUNCED
-- would let anybody with root on any computer in the building type
-- `hostname gate` and walk in through a line somebody wrote about gate.
do
	local state = fresh()
	local GATE = "10.4.17.3"
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH,
		"gate", FIXED)

	-- No line of THIS machine's /etc/hosts gives that address the name, so the
	-- line in hosts.equiv is about a machine this one cannot identify.
	check("a name nothing resolves trusts nobody",
		not CeroSecOS.trusts(state, "admin", GATE, "admin"))
	-- And the name the caller calls itself buys nothing at all: it is not even a
	-- thing the question can be asked with any more.
	check("nor does the name a machine announces",
		not CeroSecOS.trusts(state, "admin", "gate", "admin"))
	check("nor a telephone number", not CeroSecOS.trusts(state, "admin", "555-0417", "admin"))
	check("nor a callsign", not CeroSecOS.trusts(state, "admin", "KD4AXR", "admin"))
	check("nor nothing at all", not CeroSecOS.trusts(state, "admin", nil, "admin"))

	-- Write the line that names it, and the same file now trusts it.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		GATE .. " gate", FIXED)
	check("a name /etc/hosts gives the caller's address is the caller",
		CeroSecOS.trusts(state, "admin", GATE, "admin"))
	-- An alias on that line is the same machine, which is what a resolver says.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		GATE .. " pump gate", FIXED)
	check("and so is an alias on it", CeroSecOS.trusts(state, "admin", GATE, "admin"))
	-- The same name on ANOTHER address is another machine.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		"10.4.17.9 gate", FIXED)
	check("the line is about one address and not about the name",
		not CeroSecOS.trusts(state, "admin", GATE, "admin"))
	check("and it is about that one", CeroSecOS.trusts(state, "admin", "10.4.17.9", "admin"))

	-- A trust line may carry the address itself, and then no /etc/hosts is needed
	-- at all: it is the machine, written the way the machine cannot argue with.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH, "", FIXED)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH,
		GATE, FIXED)
	check("an address in hosts.equiv trusts that machine",
		CeroSecOS.trusts(state, "admin", GATE, "admin"))
	check("and nobody else", not CeroSecOS.trusts(state, "admin", "10.4.17.4", "admin"))
	-- The two-word form, with an address in front of it.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH,
		GATE .. " admin", FIXED)
	addUser(state, "bob")
	check("an address and an account names the account coming in",
		CeroSecOS.equivOk(state, GATE, "admin", "bob"))
	check("and not whoever is asking", not CeroSecOS.equivOk(state, GATE, "kate", "bob"))

	-- ~/.rhosts is the same rule in the account's own file.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH, "", FIXED)
	CeroSecOS.createNode(state, CeroSecOS.rootSession(), "/home/bob",
		CeroSecOS.newDir("bob", CeroSecOS.HOME_MODE), FIXED)
	local path = "/home/bob/.rhosts"
	CeroSecOS.writeFile(state, CeroSecOS.rootSession(), path, "gate bob", false, FIXED)
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), path)
	node.owner = "bob"
	node.mode = 600
	check("a name in .rhosts that nothing resolves trusts nobody",
		not CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	CeroSecOS.setData(state, CeroSecOS.rootSession(), path, GATE .. " bob", FIXED)
	check("the address does", CeroSecOS.rhostsOk(state, "bob", GATE, "bob"))
	-- The trust words, which is the one place the rule lives.
	eq("the words a line may use are the address and its names",
		table.concat(CeroSecOS.trustWords(state, GATE) or {}, " "), GATE)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		GATE .. " gate pump", FIXED)
	eq("and every name on the line", table.concat(
		CeroSecOS.trustWords(state, GATE) or {}, " "), GATE .. " gate pump")
	eq("a caller with no address has no words",
		CeroSecOS.trustWords(state, "gate"), nil)
end

-- The hop ceiling is the session's own, and it is paid before a name is looked up.
do
	local state = fresh()
	CeroSecOS.setNetRecord(state, 4, 17, 2)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		"10.4.17.3 gate", FIXED)
	local deep = open(state, "admin")
	deep.hops = CeroSecOS.HOP_MAX
	badAt(state, deep, "rlogin gate", "rlogin: connect: Connection refused", ENV)
	badAt(state, deep, "rsh gate date", "rsh: connect: Connection refused", ENV)
	-- Even a name the file has never heard of: a chain that may not grow is a
	-- chain that has nothing to resolve.
	badAt(state, deep, "rlogin pump", "rlogin: connect: Connection refused", ENV)
end

-- host:path, the way rcp itself tells a machine from a file.
do
	eq("a plain path is local", CeroSecOS.splitRemote("notes.txt"), nil)
	eq("and so is one with a slash in front of the colon",
		CeroSecOS.splitRemote("./a:b"), nil)
	eq("a host and a path is remote", CeroSecOS.splitRemote("gate:/tmp/a"), "gate")
	eq("with the path behind it",
		select(2, CeroSecOS.splitRemote("gate:/tmp/a")), "/tmp/a")
	eq("an address is a host too", CeroSecOS.splitRemote("10.4.17.3:/tmp/a"), "10.4.17.3")
	eq("something that is neither is not remote",
		CeroSecOS.splitRemote("NotAHost:/tmp/a"), nil)
end

-- The refusals, in the words strerror has for the errno a real one would get.
do
	eq("a machine that is off", CeroSecOS.netRefusal("rlogin", "gate", "down"),
		"rlogin: gate: Host is down")
	eq("a machine with no wire to it", CeroSecOS.netRefusal("rlogin", "gate", "unreach"),
		"rlogin: gate: No route to host")
	eq("a listener with nothing to accept with",
		CeroSecOS.netRefusal("rlogin", "gate", "refused"),
		"rlogin: connect: Connection refused")
	eq("and one that will not trust this machine",
		CeroSecOS.netRefusal("rsh", "gate", "denied"), "rsh: gate: Permission denied")
end

-- /etc/hosts and /etc/hosts.equiv are made where they are missing, and never put
-- back behind a root who deleted them.
do
	local state = fresh()
	local node = CeroSecOS.systemNode(state, CeroSecOS.HOSTS_PATH)
	eq("/etc/hosts ships with the machine", node.type, "file")
	eq("root's", node.owner, "root")
	eq("and 644", node.mode, CeroSecOS.HOSTS_MODE)
	local equiv = CeroSecOS.systemNode(state, CeroSecOS.EQUIV_PATH)
	eq("/etc/hosts.equiv too", equiv.type, "file")
	eq("and it trusts nobody", #CeroSecOS.parseEquiv(equiv.data), 0)

	-- Deleted, and the BIOS repair puts them back: they are system files.
	CeroSecOS.removeNode(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH, false, FIXED)
	CeroSecOS.removeNode(state, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH, false, FIXED)
	eq("deleted", CeroSecOS.systemNode(state, CeroSecOS.HOSTS_PATH), nil)
	CeroSecOS.restoreSystem(state)
	check("the repair puts /etc/hosts back",
		CeroSecOS.systemNode(state, CeroSecOS.HOSTS_PATH) ~= nil)
	check("and /etc/hosts.equiv", CeroSecOS.systemNode(state, CeroSecOS.EQUIV_PATH) ~= nil)

	-- A file the player has written is left exactly as it lies.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		"10.1.1.1 mine", FIXED)
	CeroSecOS.restoreSystem(state)
	eq("a file with a line in it is kept",
		CeroSecOS.systemNode(state, CeroSecOS.HOSTS_PATH).data, "10.1.1.1 mine")
end

-- An older machine is topped up on the way in, once.
do
	local old = fresh()
	CeroSecOS.removeNode(old, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH, false, FIXED)
	CeroSecOS.removeNode(old, CeroSecOS.rootSession(), CeroSecOS.EQUIV_PATH, false, FIXED)
	for _, name in ipairs({ "ifconfig", "ping", "rlogin", "rsh", "rcp", "ruptime",
			"rwho", "who", "last" }) do
		CeroSecOS.removeNode(old, CeroSecOS.rootSession(), "/bin/" .. name, false, FIXED)
	end
	old.sysv = 9
	check("the upgrade has something to do", CeroSecOS.upgradeSystem(old))
	eq("and the number has moved", old.sysv, CeroSecOS.SYSTEM_VERSION)
	check("/bin/rlogin is back",
		CeroSecOS.systemNode(old, "/bin/rlogin") ~= nil)
	check("/etc/hosts is back", CeroSecOS.systemNode(old, CeroSecOS.HOSTS_PATH) ~= nil)
	check("asked again it does nothing at all", not CeroSecOS.upgradeSystem(old))
	-- And root's deletion stays a deletion at the current number.
	CeroSecOS.removeNode(old, CeroSecOS.rootSession(), "/bin/ping", false, FIXED)
	CeroSecOS.upgradeSystem(old)
	eq("rm /bin/ping is a deletion and not a suggestion",
		CeroSecOS.systemNode(old, "/bin/ping"), nil)
end

--
-- 43. PATH: where a bare name is looked up (rung 6b)
--
-- A command is a file and PATH says which directories are looked in for it. The
-- default is /bin, which is where the machine has always looked, so everything
-- above this section is a test of the default as much as of the commands in it.
--

-- The split, which is pure string work and knows nothing about a disk.
do
	local function dirs(value)
		return table.concat(CeroSecOS.pathDirs(value), "|")
	end
	eq("one directory", dirs("/bin"), "/bin")
	eq("two", dirs("/bin:/home/admin/bin"), "/bin|/home/admin/bin")
	-- An empty field is the working directory, which is what a leading, a
	-- trailing or a doubled colon has always meant.
	eq("a leading colon is here first", dirs(":/bin"), ".|/bin")
	eq("a trailing colon is here last", dirs("/bin:"), "/bin|.")
	eq("a doubled colon is here in the middle", dirs("/a::/b"), "/a|.|/b")
	eq("an empty PATH is one field, not none", dirs(""), ".")
	eq("and a value that is not a string is no fields at all", dirs(nil), "")
end

-- Absent is not empty: a shell with no PATH at all looks in /bin, and one with
-- an empty PATH looks where it stands and nowhere else.
do
	eq("no variables at all", CeroSecOS.pathValue(nil), CeroSecOS.DEFAULT_PATH)
	eq("no PATH among them", CeroSecOS.pathValue({ x = "1" }), CeroSecOS.DEFAULT_PATH)
	eq("an empty PATH is kept as it was set", CeroSecOS.pathValue({ PATH = "" }), "")
	eq("and one that is set is what is walked",
		CeroSecOS.pathValue({ PATH = "/a:/b" }), "/a:/b")

	-- What a login hands the shell: PATH, and the HOME that makes
	-- PATH=$PATH:$HOME/bin a line worth writing.
	local vars = CeroSecOS.loginVars("/home/admin")
	eq("a login sets PATH", vars.PATH, CeroSecOS.DEFAULT_PATH)
	eq("and HOME", vars.HOME, "/home/admin")
	eq("an account with no home gets no HOME", CeroSecOS.loginVars(nil).HOME, nil)
	check("and two logins never share one table",
		CeroSecOS.loginVars("/root") ~= CeroSecOS.loginVars("/root"))

	-- A script and a cron line start with the default and with nothing else:
	-- what the shell that started them has is not theirs. That is the cron trap.
	local job = CeroSecOS.newJob({ prog = {} })
	eq("a job nobody handed an environment starts with the default PATH",
		job.vars.PATH, CeroSecOS.DEFAULT_PATH)
	eq("and with nothing else in it", job.nvars, 1)
end

-- How many directories a PATH may name. The ceiling is met where the value is
-- SET, with a reason, because the length of PATH is what every command on the
-- machine costs.
do
	local state = fresh()
	local admin = open(state, "admin")
	local function path(n)
		local out = {}
		for i = 1, n do out[i] = "/d" .. i end
		return table.concat(out, ":")
	end
	admin.shvars = CeroSecOS.loginVars("/home/admin")
	ok(state, admin, "PATH=" .. path(CeroSecOS.MAX_PATH_DIRS), {})
	eq("the ceiling's worth is set", admin.shvars.PATH, path(CeroSecOS.MAX_PATH_DIRS))
	bad(state, admin, "PATH=" .. path(CeroSecOS.MAX_PATH_DIRS + 1),
		"sh: too many PATH entries")
	eq("and the refused line changed nothing", admin.shvars.PATH,
		path(CeroSecOS.MAX_PATH_DIRS))

	-- The walk stops there as well, so a value off a save file nobody can explain
	-- is slow for nobody: /bin at the end of a long one is never reached.
	local long = path(CeroSecOS.MAX_PATH_DIRS + 20) .. ":/bin"
	local found, reason, walked = CeroSecOS.lookupPath(state, admin, "ls", long)
	eq("nothing is found past the ceiling", found, nil)
	eq("and it reads as a missing command", reason, "command not found")
	eq("having walked exactly the ceiling", walked, CeroSecOS.MAX_PATH_DIRS)
	-- What the walk COST comes back with it, because the shell charges it.
	local hit, noReason, hitWalk = CeroSecOS.lookupPath(state, admin, "ls", "/d1:/d2:/bin")
	eq("a hit says where it was found", hit, "/bin/ls")
	eq("with no reason beside it", noReason, nil)
	eq("and how many directories it took", hitWalk, 3)
end

-- The walk itself, at the prompt.
do
	local state = fresh()
	local admin = open(state, "admin")
	admin.shvars = CeroSecOS.loginVars("/home/admin")

	ok(state, admin, "mkdir /home/admin/bin", {})
	ok(state, admin, 'echo "echo hello from bin" > /home/admin/bin/hello', {})
	ok(state, admin, "chmod 755 /home/admin/bin/hello", {})

	-- Not on the PATH yet: a file with x on it is not a command until a
	-- directory PATH names holds it.
	bad(state, admin, "hello", "hello: command not found")
	-- ...and the same file, by path, runs -- a word with a slash in it is never
	-- looked up at all.
	ok(state, admin, "/home/admin/bin/hello", { "hello from bin" })

	ok(state, admin, "PATH=$PATH:/home/admin/bin", {})
	ok(state, admin, "echo $PATH", { "/bin:/home/admin/bin" })
	-- A file found outside /bin is a FILE, so what runs is its text: that is
	-- what makes ~/bin an account's own commands.
	ok(state, admin, "hello", { "hello from bin" })
	ok(state, admin, "which hello", { "/home/admin/bin/hello" })
	ok(state, admin, "type hello", { "hello is /home/admin/bin/hello" })

	-- An earlier directory with something in the way does not stop the walk.
	-- POSIX's rule: the first match that is executable wins.
	ok(state, admin, "cp /bin/ls /home/admin/bin/ls", {})
	ok(state, admin, "chmod 644 /home/admin/bin/ls", {})
	ok(state, admin, "PATH=/home/admin/bin:/bin", {})
	ok(state, admin, "ls /etc/motd", { "motd" })
	eq("and which names the one that would run",
		okAt(state, admin, "which ls")[1], "/bin/ls")
	-- With x on it, the one in front wins -- and it is a script, so its text is
	-- what runs and the real ls is shadowed.
	ok(state, admin, 'echo "echo mine" > /home/admin/bin/ls', {})
	ok(state, admin, "chmod 755 /home/admin/bin/ls", {})
	ok(state, admin, "ls /etc/motd", { "mine" })
	ok(state, admin, "which ls", { "/home/admin/bin/ls" })
	ok(state, admin, "rm /home/admin/bin/ls", {})

	-- Found everywhere and runnable nowhere is "permission denied"; found
	-- nowhere at all is "command not found". The reason the walk carries is the
	-- best one it met.
	ok(state, admin, "cp /bin/ls /home/admin/bin/ls", {})
	ok(state, admin, "chmod 644 /home/admin/bin/ls", {})
	ok(state, admin, "PATH=/home/admin/bin", {})
	bad(state, admin, "ls /etc/motd", "ls: permission denied")
	bad(state, admin, "pwd", "pwd: command not found")
	-- /bin is off the PATH, so the walk cannot even find which: the refusal is
	-- about the command that was typed, as every refusal here is.
	bad(state, admin, "which ls", "which: command not found")
	-- Back on a PATH that holds it, `which` says nothing at all about a name it
	-- cannot answer for and comes back unsuccessful -- which is what
	-- `which x > /dev/null` has always been used as.
	ok(state, admin, "PATH=/bin", {})
	local silent = expect(state, admin, "which nosuch", false, {})
	eq("which prints nothing when it finds nothing", #silent, 0)
	ok(state, admin, "PATH=/home/admin/bin", {})

	-- An empty field is the working directory. Standing in the directory the
	-- script is in is not enough on a PATH that does not say so...
	ok(state, admin, "cd /home/admin/bin", {})
	ok(state, admin, "PATH=/bin", {})
	bad(state, admin, "hello", "hello: command not found")
	-- ...and a leading colon is what says so.
	ok(state, admin, "PATH=:/bin", {})
	ok(state, admin, "hello", { "hello from bin" })

	-- An empty PATH is one empty field and nothing else: the working directory,
	-- where there is no echo to run what was found.
	ok(state, admin, "PATH=", {})
	bad(state, admin, "hello", "echo: command not found")
	ok(state, admin, "cd /etc", {})
	bad(state, admin, "hello", "hello: command not found")
	-- The shell's own words are never looked up, so they still work: that is
	-- what "cd cannot be a file" means. pwd is a file and is not found.
	ok(state, admin, "cd /var", {})
	bad(state, admin, "pwd", "pwd: command not found")
end

-- The shell's own words are the shell's, whatever PATH says. Asked with an
-- empty PATH, where nothing at all can be found.
do
	local state = fresh()
	local admin = open(state, "admin")
	admin.shvars = { PATH = "" }
	ok(state, admin, "cd /var", {})
	ok(state, admin, 'if true; then echo unreachable; fi', { "true: command not found" },
		nil)
	-- ...because `true` is a FILE on this machine and is looked up like any
	-- other. The grammar around it is not, and neither is cd: the line above ran
	-- its `if` and only the command inside it was missing.
	bad(state, admin, "echo hi", "echo: command not found")
end

-- type: the three kinds of word, in sh's own wording.
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "type ls", { "ls is /bin/ls" })
	ok(state, admin, "type cd", { "cd is a shell builtin" })
	ok(state, admin, "type type", { "type is a shell builtin" })
	ok(state, admin, "type history", { "history is a shell builtin" })
	ok(state, admin, "type if", { "if is a shell keyword" })
	ok(state, admin, "type done", { "done is a shell keyword" })
	ok(state, admin, "type in", { "in is a shell keyword" })
	-- The ones the engine runs without leaving the house are files here, and are
	-- named as files: `rm /bin/echo` takes echo away.
	ok(state, admin, "type echo", { "echo is /bin/echo" })
	ok(state, admin, "type [", { "[ is /bin/[" })
	bad(state, admin, "type nosuch", "type: nosuch: not found")
	-- `type` is the shell's own word, so it has no file to find, delete or
	-- chmod -- and `which`, which answers about files only, finds nothing for it.
	eq("no /bin/type ships", CeroSecOS.systemNode(state, "/bin/type"), nil)
	check("and it is not in the list /bin is filled from", (function()
		local names = CeroSecOS.binNames()
		for i = 1, #names do
			if names[i] == "type" then return false end
		end
		return true
	end)())
	local silent = expect(state, admin, "which cd", false, {})
	eq("which finds nothing for a shell word", #silent, 0)
	ok(state, admin, "which which", { "/bin/which" })

	-- Both take one name and say so otherwise.
	bad(state, admin, "which", "which: usage: which <name>")
	bad(state, admin, "type", "type: usage: type <name>")
end

-- ~/.profile is where PATH is extended, and it is the shell's own environment
-- it extends: what it sets is set at the prompt afterwards.
do
	local state = fresh()
	local admin = open(state, "admin")
	local vars = CeroSecOS.loginVars("/home/admin")

	local made = CeroSecOS.createNode(state, admin, "/home/admin/bin",
		CeroSecOS.newDir("admin", 755), nil)
	check("the bin directory was made", made ~= nil)
	put(state, admin, "/home/admin/bin/hello", "echo hello from bin")
	local node = CeroSecOS.getNode(state, admin, "/home/admin/bin/hello")
	node.mode = 755
	put(state, admin, "/home/admin/.profile", "PATH=$PATH:$HOME/bin")

	-- The profile, run the way a login runs it: a job on the shell's own
	-- variables, named after the file.
	local profile = CeroSecOS.promptJob(state, admin, "PATH=$PATH:$HOME/bin", vars, nil,
		".profile")
	check("the profile parsed", profile ~= nil)
	local turns = 0
	while not CeroSecOS.jobIsOver(profile) and turns < 50 do
		turns = turns + 1
		CeroSecOS.jobStep(state, profile, {}, 100)
	end
	eq("the profile extended the shell's PATH", vars.PATH, "/bin:/home/admin/bin")

	-- And the very next line typed finds the command.
	admin.shvars = vars
	ok(state, admin, "hello", { "hello from bin" })

	-- A SCRIPT does not inherit it: it starts with the default, which is the
	-- classic cron trap written out.
	put(state, admin, "/home/admin/bench.sh", "echo $PATH\nhello")
	local run = runScript(state, admin, "echo $PATH\nhello")
	eq("a script starts with the default PATH", run.out[1], CeroSecOS.DEFAULT_PATH)
	eq("so the command the prompt found is not found in a script", run.out[2],
		"hello: command not found")
end

--
-- 44. Symbolic links (rung 6b)
--
-- A link is a node holding a PATH. getNode follows one and nothing else in the
-- engine does, so what is tested here is that every command inherited the right
-- behaviour: the ones that act on the FILE follow, and the three that act on the
-- LINK -- ls -l, rm, mv -- do not.
--
-- What a link POINTS AT is the arrow `ls -l` draws and nothing else: readlink(1)
-- is a 1997 command, four years late for this machine, and was retired at
-- SYSTEM_VERSION 16. So every question of the form "what does this point at" is
-- asked here the way a survivor asks it.
--

-- The target off the arrow, or nil for a name that has none. Through `ls -l`,
-- which is the whole point: the answer has to be legible ON THE SCREEN.
local function pointsAt(state, session, path)
	local ok_, lines = exec(state, session, "ls -l " .. path)
	if not ok_ or #lines ~= 1 then return nil end
	return string.match(lines[1], " %-> (.+)$")
end

do
	local state = fresh()
	local admin = open(state, "admin")

	ok(state, admin, 'echo "hello there" > notes.txt', {})
	ok(state, admin, "ln -s notes.txt link", {})

	-- The node itself: a path, as typed, and 777 that means nothing.
	local link = CeroSecOS.getNode(state, admin, "/home/admin/link", true)
	eq("it is a link", link.type, "link")
	eq("it holds the target as it was typed", link.target, "notes.txt")
	eq("its mode is 777", link.mode, 777)
	eq("and it is the account's own", link.owner, "admin")
	check("the state still validates", CeroSecOS.validate(state) == true)

	-- Reading through it is reading the file.
	ok(state, admin, "cat link", { "hello there" })
	eq("and the arrow says what it points at", pointsAt(state, admin, "link"), "notes.txt")
	-- A name that is not a link has no arrow, which is the honest answer: there is
	-- nothing to point at.
	eq("a file has no arrow", pointsAt(state, admin, "notes.txt"), nil)
	badAt(state, admin, "ls -l nosuch", "ls: nosuch: no such file")
	-- And the name that used to answer this is not on the machine at all.
	badAt(state, admin, "readlink link", "readlink: command not found")

	-- What ls says about one.
	local long = okAt(state, admin, "ls -l link")
	eq("ls -l describes the link and not the file", long[1],
		"lrwxrwxrwx  admin  admin   link -> notes.txt")
	eq("and it fits the screen", #long[1] <= CeroSecOS.COLS, true)
	local marked = okAt(state, admin, "ls -F")
	check("ls -F marks it with an at-sign",
		string.find(marked[1], "link@", 1, true) ~= nil)
	-- Named on the line, -l and -F are the two flags that ask about the LINK and
	-- not about what it points at, which is POSIX's rule for both of them.
	ok(state, admin, "ls -F link", { "link@" })
	ok(state, admin, "ls link", { "link" })

	-- Writing through it writes the file, and the link is untouched.
	ok(state, admin, 'echo "written through" > link', {})
	ok(state, admin, "cat notes.txt", { "written through" })
	eq("the link is still a link",
		CeroSecOS.getNode(state, admin, "/home/admin/link", true).type, "link")

	-- Copying one copies what it POINTS at, which is POSIX's cp.
	ok(state, admin, "cp link copy", {})
	eq("the copy is a file",
		CeroSecOS.getNode(state, admin, "/home/admin/copy", true).type, "file")
	ok(state, admin, "cat copy", { "written through" })

	-- Moving one moves the LINK.
	ok(state, admin, "mv link moved", {})
	eq("and the arrow moved with it", pointsAt(state, admin, "moved"), "notes.txt")
	check("and nothing happened to the file",
		CeroSecOS.getNode(state, admin, "/home/admin/notes.txt") ~= nil)

	-- Removing one removes the LINK.
	ok(state, admin, "rm moved", {})
	eq("the link is gone", CeroSecOS.getNode(state, admin, "/home/admin/moved"), nil)
	check("and the file it pointed at is not",
		CeroSecOS.getNode(state, admin, "/home/admin/notes.txt") ~= nil)
end

-- A link to a directory is a directory for everything that walks through it.
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "mkdir papers", {})
	ok(state, admin, 'echo "first" > papers/one.txt', {})
	ok(state, admin, "ln -s papers p", {})

	ok(state, admin, "cat p/one.txt", { "first" })
	ok(state, admin, "ls p", { "one.txt" })
	-- Named on the line with -l or -F it is the link that is spoken about; with
	-- neither, the directory it points at is listed, which is what every ls does.
	local shown = okAt(state, admin, "ls -l p")
	eq("ls -l p describes the link", shown[1], "lrwxrwxrwx  admin  admin   p -> papers")
	-- `cd` through one keeps the path as it was typed, the way a shell does.
	ok(state, admin, "ls -F p", { "p@" })
	ok(state, admin, "cd p", {})
	ok(state, admin, "pwd", { "/home/admin/p" })
	ok(state, admin, "cd ..", {})
	ok(state, admin, "pwd", { "/home/admin" })
	-- And a write through it lands in the real directory.
	ok(state, admin, 'echo "second" > p/two.txt', {})
	ok(state, admin, "ls papers", { "one.txt  two.txt" })
end

-- A link that points nowhere, and links that point at each other.
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "ln -s nowhere dangle", {})
	-- Making one is allowed: a link to a file that is not there yet is a link
	-- somebody meant to make, and it says so the moment it is used.
	badAt(state, admin, "cat dangle", "cat: dangle: no such file")
	badAt(state, admin, "cd dangle", "cd: dangle: no such file")
	eq("and the arrow still says where it was aimed",
		pointsAt(state, admin, "dangle"), "nowhere")
	local shown = okAt(state, admin, "ls -l dangle")
	eq("ls -l still describes it", shown[1],
		"lrwxrwxrwx  admin  admin   dangle -> nowhere")
	ok(state, admin, "rm dangle", {})

	-- A loop costs the hop ceiling and then says which ceiling it met.
	ok(state, admin, "ln -s b a", {})
	ok(state, admin, "ln -s a b", {})
	badAt(state, admin, "cat a", "cat: a: too many levels of symbolic links")
	badAt(state, admin, "ls -l a/x", "ls: a/x: too many levels of symbolic links")
	-- A link to itself is the same answer.
	ok(state, admin, "ln -s self self", {})
	badAt(state, admin, "cat self", "cat: self: too many levels of symbolic links")
	-- ...and the LINKS are still readable, which is what lets somebody fix it.
	eq("the arrow is still legible", pointsAt(state, admin, "a"), "b")
	ok(state, admin, "rm a", {})
	badAt(state, admin, "cat b", "cat: b: no such file")

	-- A chain shorter than the ceiling is followed all the way.
	local names = {}
	-- Exactly the ceiling's worth of links, so the last one is the last hop that
	-- is allowed and the one hung in front of it is one too many.
	for i = 1, CeroSecOS.MAX_LINK_HOPS do names[i] = "h" .. i end
	ok(state, admin, 'echo "the end" > end.txt', {})
	ok(state, admin, "ln -s end.txt " .. names[1], {})
	for i = 2, #names do
		ok(state, admin, "ln -s " .. names[i - 1] .. " " .. names[i], {})
	end
	ok(state, admin, "cat " .. names[#names], { "the end" })
	-- One more hop than the ceiling and it stops.
	ok(state, admin, "ln -s " .. names[#names] .. " over", {})
	badAt(state, admin, "cat over", "cat: over: too many levels of symbolic links")
end

-- The permissions are the TARGET's: a link is a name and grants nothing.
do
	local state = fresh()
	local admin = open(state, "admin")
	local root = open(state, "root")
	addUser(state, "bob", "", "/home/bob")
	local bob = open(state, "bob")
	CeroSecOS.createNode(state, root, "/home/bob", CeroSecOS.newDir("bob", 750), nil)

	put(state, root, "/root/secret.txt", "the code is 1234")
	-- A link anybody may read, to a file only root may.
	ok(state, root, "ln -s /root/secret.txt /home/bob/peek", {})
	local seen = CeroSecOS.getNode(state, bob, "/home/bob/peek", true)
	eq("bob can see the link itself", seen.type, "link")
	eq("and he can read the arrow", pointsAt(state, bob, "/home/bob/peek"),
		"/root/secret.txt")
	-- ...and it buys him nothing at all: /root is 700.
	badAt(state, bob, "cat /home/bob/peek", "cat: /home/bob/peek: permission denied")
	ok(state, root, "cat /home/bob/peek", { "the code is 1234" })
end

-- A link in /bin is a command for everybody who may run what it points at.
do
	local state = fresh()
	local admin = open(state, "admin")
	local root = open(state, "root")
	addUser(state, "bob", "", "/home/bob")
	local bob = open(state, "bob")

	-- admin's own script, readable and executable by everybody, in a directory
	-- everybody may walk through -- his home included, which ships at 750: a link
	-- grants nothing, so every directory on the way to the target has to let the
	-- other account through or the command is his alone.
	ok(state, root, "chmod 755 /home/admin", {})
	CeroSecOS.createNode(state, root, "/home/admin/tools", CeroSecOS.newDir("admin", 755), nil)
	put(state, admin, "/home/admin/tools/hello", "echo hello from the tools")
	local script = CeroSecOS.getNode(state, admin, "/home/admin/tools/hello")
	script.mode = 755
	ok(state, root, "ln -s /home/admin/tools/hello /bin/hello", {})

	-- Anybody's bare name finds it, because /bin is on everybody's PATH.
	ok(state, admin, "hello", { "hello from the tools" })
	ok(state, bob, "hello", { "hello from the tools" })
	ok(state, bob, "which hello", { "/bin/hello" })
	ok(state, bob, "type hello", { "hello is /bin/hello" })
	-- Take x off the TARGET and it stops being a command for anybody but root.
	script.mode = 700
	badAt(state, bob, "hello", "hello: permission denied")
	ok(state, root, "hello", { "hello from the tools" })
	-- And the link is what `ls -l /bin` says it is.
	local shown = okAt(state, root, "ls -l /bin/hello")
	eq("the link in /bin describes itself", shown[1],
		"lrwxrwxrwx  root   root    hello -> /home/admin/tools/hello")
	eq("in sixty columns exactly", #shown[1], CeroSecOS.COLS - 1)

	-- A target too long for the columns is what gets cut, and the name is kept
	-- whole: the name is what somebody typed.
	ok(state, root, "ln -s /home/admin/tools/a/very/long/way/down/there /bin/far", {})
	local cut = okAt(state, root, "ls -l /bin/far")
	eq("the target is cut with a tilde", cut[1],
		"lrwxrwxrwx  root   root    far -> /home/admin/tools/a/very/~")
	eq("and the line is the width of the screen", #cut[1], CeroSecOS.COLS)
end

-- A link inside a copied tree stays a link, and a link is a node with bytes.
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "mkdir tree", {})
	ok(state, admin, 'echo "body" > tree/real.txt', {})
	ok(state, admin, "ln -s real.txt tree/also", {})

	local before, bytesBefore = CeroSecOS.usage(state)
	ok(state, admin, "cp -r tree copy", {})
	local after, bytesAfter = CeroSecOS.usage(state)
	eq("the copy is a link and not a file",
		CeroSecOS.getNode(state, admin, "/home/admin/copy/also", true).type, "link")
	eq("pointing at the same thing it did",
		CeroSecOS.getNode(state, admin, "/home/admin/copy/also", true).target, "real.txt")
	-- Which means it now points at the copy's own file, exactly as cp -R leaves it.
	ok(state, admin, "cat copy/also", { "body" })
	eq("a link is one node like anything else", after - before, 3)
	eq("and its target text is bytes on the disk", bytesAfter - bytesBefore,
		#"body" + #"real.txt")

	-- A dangling link inside a tree is copied too: nothing is resolved.
	ok(state, admin, "ln -s gone tree/broken", {})
	ok(state, admin, "cp -r tree second", {})
	eq("the dangling one came across",
		CeroSecOS.getNode(state, admin, "/home/admin/second/broken", true).target, "gone")
end

-- What a link may hold, and what it may not.
do
	local state = fresh()
	local admin = open(state, "admin")
	-- The ceiling is the longest path this machine can address.
	local tooLong = "/" .. string.rep("a", CeroSecOS.MAX_LINK_BYTES)
	badAt(state, admin, "ln -s " .. tooLong .. " big", "ln: big: file too large")
	eq("nothing was made", CeroSecOS.getNode(state, admin, "/home/admin/big"), nil)
	-- The name is a name like any other, and a flag after the first operand is a
	-- name too -- which isValidName refuses, the way it refuses one everywhere.
	badAt(state, admin, "ln -s x -bad", "ln: -bad: invalid name")
	badAt(state, admin, "ln -z x y", "ln: -z: unknown option")
	ok(state, admin, 'echo "x" > taken.txt', {})
	badAt(state, admin, "ln -s x taken.txt", "ln: taken.txt: file exists")
	-- A directory as the second argument puts the link inside it, under the
	-- target's own last name.
	ok(state, admin, "mkdir here", {})
	ok(state, admin, "ln -s /bin/ls here", {})
	eq("and the arrow names the target", pointsAt(state, admin, "here/ls"), "/bin/ls")
	-- /dev takes nothing, links included.
	badAt(state, admin, "ln -s /bin/ls /dev/ls", CeroSecOS.DEV_PATH .. ": read-only")
	-- And a line with no -s in it is not a line this machine can carry out.
	badAt(state, admin, "ln taken.txt hard", "ln: usage: ln -s <target> <name>")
	badAt(state, admin, "ln -s one", "ln: usage: ln -s <target> <name>")

	-- A forged state: a link with nothing in it is not something to run on.
	local empty = CeroSecOS.newLink("admin", "x")
	state.fs.children.home.children.admin.children.bad = empty
	check("a link with a target validates", CeroSecOS.validate(state) == true)
	empty.target = ""
	check("one with an empty target does not", CeroSecOS.validate(state) == false)
	empty.target = string.rep("a", CeroSecOS.MAX_LINK_BYTES + 1)
	check("nor one longer than a path can be", CeroSecOS.validate(state) == false)
	empty.target = nil
	check("nor one with no target at all", CeroSecOS.validate(state) == false)
end

--
-- 45. /dev/null and /var/tmp (rung 6b)
--
-- Two places the filesystem grew. Neither is a command: one is a hole in the
-- disk, the other is a directory whose rule is the PLACE's and not a mode digit.
--

do
	local state = fresh()
	local admin = open(state, "admin")
	local root = open(state, "root")

	-- It reads nothing at all, which is not the same as one empty line.
	ok(state, admin, "cat /dev/null", {})
	-- It swallows what is written to it, and stays empty.
	ok(state, admin, "echo hello > /dev/null", {})
	ok(state, admin, "cat /dev/null", {})
	ok(state, admin, "echo again >> /dev/null", {})
	ok(state, admin, "cat /dev/null", {})
	-- A capture of it is the empty word, which is what makes it useful in a test.
	ok(state, admin, "x=$(cat /dev/null)", {})
	ok(state, admin, "echo [$x]", { "[]" })

	-- It is a DEVICE, so it wears "c" and none of the file commands will have it.
	ok(state, admin, "ls -l /dev/null", { "crw-rw-rw-  root  root  null" })
	badAt(state, admin, "rm /dev/null", "rm: /dev/null: is a device")
	badAt(state, root, "rm /dev/null", "rm: /dev/null: is a device")
	badAt(state, admin, "cp /dev/null copy", "cp: /dev/null: is a device")
	badAt(state, admin, "mv /dev/null moved", "mv: /dev/null: is a device")
	-- And nothing can be made beside it: /dev takes nothing.
	badAt(state, admin, "touch /dev/mine", CeroSecOS.DEV_PATH .. ": read-only")

	-- Everybody may write to it, which is the whole point of 666.
	local bob = addUser(state, "bob", "", "/home/bob")
	local bobSession = open(state, "bob")
	ok(state, bobSession, "echo noise > /dev/null", {})
	ok(state, bobSession, "cat /dev/null", {})

	-- It costs the disk nothing, however much is written to it.
	local nodes, bytes = CeroSecOS.usage(state)
	ok(state, admin, "echo " .. string.rep("x", 100) .. " > /dev/null", {})
	local nodesAfter, bytesAfter = CeroSecOS.usage(state)
	eq("the disk did not move", bytesAfter, bytes)
	eq("nor the node count", nodesAfter, nodes)
	check("and the machine still boots", CeroSecOS.validate(state) == true)

	-- It is not one of the world's devices, so `dev` does not list it and does
	-- not know the word.
	ok(state, root, "dev", {})
	badAt(state, root, "dev null", "dev: null: unknown kind")
end

-- The repair and the upgrade both put it back, and neither replaces what is
-- already at that name.
do
	local state = fresh()
	state.fs.children.dev.children.null = nil
	state.sysv = 10
	check("the upgrade has something to do", CeroSecOS.upgradeSystem(state))
	check("and the hole is back", CeroSecOS.isNull(state.fs.children.dev.children.null))
	-- A machine at the current number is left alone: root's deletion stays done.
	state.fs.children.dev.children.null = nil
	check("asked again it does nothing", not CeroSecOS.upgradeSystem(state))
	eq("so the deletion stands", state.fs.children.dev.children.null, nil)
	-- The BIOS is what puts it back then.
	CeroSecOS.restoreSystem(state)
	check("the repair puts it back", CeroSecOS.isNull(state.fs.children.dev.children.null))

	-- A file somebody made at that name is not ours to replace.
	local mine = CeroSecOS.newFile("root", 644, "mine")
	state.fs.children.dev.children.null = mine
	CeroSecOS.restoreSystem(state)
	eq("what was there is left exactly as it was",
		state.fs.children.dev.children.null, mine)
end

-- A device on a saved disk is a state nothing runs on -- except the hole.
do
	local state = fresh()
	check("the hole validates", CeroSecOS.validate(state) == true)
	state.fs.children.dev.children.light0 = {
		type = "dev", owner = "root", group = "sudo", mode = 660,
		id = "light0", kind = "light", desc = "", side = "", pos = "", state = "on",
	}
	check("a light switch on the disk does not", CeroSecOS.validate(state) == false)
	state.fs.children.dev.children.light0 = nil
	check("and with it gone the machine boots again", CeroSecOS.validate(state) == true)
end

-- /var/tmp: anybody writes, only the owner takes away.
do
	local state = fresh()
	local admin = open(state, "admin")
	local root = open(state, "root")
	addUser(state, "bob", "", "/home/bob")
	local bob = open(state, "bob")

	local tmp = CeroSecOS.systemNode(state, CeroSecOS.TMP_PATH)
	eq("it is root's", tmp.owner, "root")
	eq("and open to everybody", tmp.mode, 777)
	-- Three digits, so `ls -l` shows a plain one: the sticky rule is the PLACE's
	-- and there is no fourth digit anywhere on this machine to carry it.
	eq("the mode reads as it is written", CeroSecOS.permString(tmp), "drwxrwxrwx")

	ok(state, admin, 'echo "admin here" > /var/tmp/mine.txt', {})
	ok(state, bob, 'echo "bob here" > /var/tmp/bobs.txt', {})
	-- Everybody may read what is there, which is what a scratch directory is.
	ok(state, bob, "cat /var/tmp/mine.txt", { "admin here" })

	-- And nobody may take away what is not his.
	badAt(state, bob, "rm /var/tmp/mine.txt", "rm: /var/tmp/mine.txt: permission denied")
	badAt(state, admin, "rm /var/tmp/bobs.txt", "rm: /var/tmp/bobs.txt: permission denied")
	-- Nor rename it out from under him, which is the same thing done sideways.
	badAt(state, bob, "mv /var/tmp/mine.txt /home/bob/taken",
		"mv: /home/bob/taken: permission denied")
	badAt(state, bob, "mv /var/tmp/mine.txt /var/tmp/taken",
		"mv: /var/tmp/taken: permission denied")
	-- Nor write over it, which is the same thing done the other way round: a
	-- rename ONTO a name in here destroys what the name meant, and destroying
	-- somebody else's file is the one thing 777 in here does not allow.
	badAt(state, bob, "mv /var/tmp/bobs.txt /var/tmp/mine.txt",
		"mv: /var/tmp/mine.txt: permission denied")
	ok(state, bob, "cat /var/tmp/mine.txt", { "admin here" })
	check("and it is all still there",
		CeroSecOS.systemNode(state, "/var/tmp/mine.txt") ~= nil)

	-- His own, he may.
	ok(state, bob, "mv /var/tmp/bobs.txt /var/tmp/bobs2.txt", {})
	ok(state, bob, "rm /var/tmp/bobs2.txt", {})
	-- Root may anything.
	ok(state, root, "rm /var/tmp/mine.txt", {})
	eq("the directory is empty again", CeroSecOS.countEntries(tmp), 0)

	-- A directory of somebody's own in there is his, and the rule is about the
	-- NODE's owner and not about what is under it.
	ok(state, admin, "mkdir /var/tmp/work", {})
	ok(state, admin, 'echo "x" > /var/tmp/work/a.txt', {})
	badAt(state, bob, "rm -r /var/tmp/work", "rm: /var/tmp/work: permission denied")
	ok(state, admin, "rm -r /var/tmp/work", {})

	-- Nowhere else on the machine works this way: a directory somebody may write
	-- is a directory he may delete from, which is what 777 means everywhere else.
	ok(state, root, "mkdir /shared", {})
	ok(state, root, "chmod 777 /shared", {})
	ok(state, admin, 'echo "admin here" > /shared/mine.txt', {})
	ok(state, bob, "rm /shared/mine.txt", {})
	eq("only the one directory is sticky", CeroSecOS.isSticky("/shared"), false)
	eq("and it is the one", CeroSecOS.isSticky(CeroSecOS.TMP_PATH), true)
end

-- An older machine is topped up with /var/tmp too.
do
	local state = fresh()
	CeroSecOS.removeNode(state, CeroSecOS.rootSession(), CeroSecOS.TMP_PATH, true, nil)
	eq("it is gone", CeroSecOS.systemNode(state, CeroSecOS.TMP_PATH), nil)
	state.sysv = 10
	check("the upgrade has something to do", CeroSecOS.upgradeSystem(state))
	local tmp = CeroSecOS.systemNode(state, CeroSecOS.TMP_PATH)
	check("and it is back", tmp ~= nil)
	eq("at the mode it ships at", tmp.mode, CeroSecOS.TMP_MODE)
	eq("and the number has moved", state.sysv, CeroSecOS.SYSTEM_VERSION)
end

--
-- 46. ls, and who is reading it (rung 6b)
--
-- Columns are for a person. Anywhere else -- a pipe, a $( ), a file -- it is one
-- name per line, which is what makes a listing something the next command can
-- use.
--

do
	local state = fresh()
	local admin = open(state, "admin")

	-- At the glass: packed, as it has always been.
	ok(state, admin, "ls /", { "bin   dev   etc   home  mnt   root  var" })

	-- Down a pipe: a name a line. The stage on the left is not writing to a
	-- screen, and the one on the right is.
	ok(state, admin, "ls / | cat", { "bin", "dev", "etc", "home", "mnt", "root", "var" })
	ok(state, admin, "ls / | grep e", { "dev", "etc", "home" })
	ok(state, admin, "ls / | wc -l", { "     7" })
	-- Which is the whole point: a loop over a listing gets the names and not the
	-- rows they were packed into.
	ok(state, admin, "for f in $(ls /); do echo [$f]; done",
		{ "[bin]", "[dev]", "[etc]", "[home]", "[mnt]", "[root]", "[var]" })
	-- A capture of it is the names, separated the way a capture separates lines.
	ok(state, admin, "x=$(ls /)", {})
	ok(state, admin, "echo $x", { "bin dev etc home mnt root var" })

	-- Into a file: a name a line as well, because a file is not a screen either.
	ok(state, admin, "ls / > listed.txt", {})
	ok(state, admin, "cat listed.txt", { "bin", "dev", "etc", "home", "mnt", "root", "var" })

	-- And either can be asked for outright, whoever is reading.
	ok(state, admin, "ls -1 /", { "bin", "dev", "etc", "home", "mnt", "root", "var" })
	ok(state, admin, "ls -C / | cat", { "bin   dev   etc   home  mnt   root  var" })
	ok(state, admin, "ls -C / > packed.txt", {})
	ok(state, admin, "cat packed.txt", { "bin   dev   etc   home  mnt   root  var" })
	-- The later of the two wins, exactly as -a and -A do.
	ok(state, admin, "ls -1C /", { "bin   dev   etc   home  mnt   root  var" })
	ok(state, admin, "ls -C1 /", { "bin", "dev", "etc", "home", "mnt", "root", "var" })
	-- -l was always a line each and neither flag has anything to say about it.
	local long = okAt(state, admin, "ls -l1 /")
	eq("a long listing is a line each whatever else is asked", #long, 7)
	badAt(state, admin, "ls -q /", "ls: -q: unknown option")

	-- The last stage of a pipeline IS writing to the glass, so it packs: `cat`
	-- hands the lines over and the ls at the end of it is the one in front of a
	-- person.
	ok(state, admin, "cat listed.txt | sort | uniq",
		{ "bin", "dev", "etc", "home", "mnt", "root", "var" })
end

-- The other three doors to the same question, asked of the engine rather than
-- through a line: a stage that is not last, a capture, and cron's mail.
do
	local state = fresh()
	local admin = open(state, "admin")
	-- A cron job's output goes to a mailbox and not to a screen, so its `ls` is a
	-- name a line -- the same answer the pipe gets, for the same reason.
	local job = CeroSecOS.newJob({
		prog = CeroSecOS.parseScript("ls /"), session = admin, name = "cron",
	})
	job.mailTo = "admin"
	local out = {}
	local turns = 0
	while not CeroSecOS.jobIsOver(job) and turns < 50 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, { now = FIXED }, 100)
		for i = 1, #job.out do out[#out + 1] = job.out[i] end
		job.out = {}
	end
	eq("cron's ls is a name a line", #out, 7)
	eq("the first of them", out[1], "bin")
end


--
-- 47. The floppy drive, and the second filesystem (rung 4e)
--
-- The whole of it, in the order a survivor meets it: an empty slot, a blank disk
-- in it, newfs, mount, the disk as a place to put files, and back out again.
--

-- 47a. An empty slot is an empty slot.
do
	local state = fresh()
	local admin = open(state, "admin")

	eq("a fresh machine has nothing in the drive", CeroSecOS.floppyOf(state), nil)
	eq("and nothing mounted", CeroSecOS.mountTable(state), nil)
	okAt(state, admin, "ls /dev", { "null" })
	okAt(state, admin, "mount", { "/dev/hda on / type ufs (rw)" })
	-- /mnt is there, empty, and root's.
	okAt(state, admin, "ls /mnt", {})
	local mnt = CeroSecOS.systemNode(state, CeroSecOS.MNT_PATH)
	eq("/mnt is root's", mnt.owner, "root")
	eq("at 755", mnt.mode, CeroSecOS.MNT_MODE)

	-- Every command that wants the drive says the same thing about a slot with
	-- nothing in it, in the filesystem's own grammar: there is no such file.
	badAt(state, admin, "newfs /dev/fd0", "newfs: /dev/fd0: no such file")
	badAt(state, admin, "mount /dev/fd0 /mnt", "mount: /dev/fd0: no such file")
	badAt(state, admin, "cat /dev/fd0", "cat: /dev/fd0: no such file")
	badAt(state, admin, "umount /mnt", "umount: /mnt: not mounted")
	-- df is one disk's worth of rows.
	eq("df has a header and two rows", #okAt(state, admin, "df", nil), 3)
end

-- 47b. A blank disk in the slot: the drive appears, and it is a device.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy("WORK")

	okAt(state, admin, "ls /dev", { "fd0   null" })
	-- The drive's own line: root's, the sudo group's, 660, with the sticker in
	-- the column a device keeps for what it is fixed to and what is in it last.
	okAt(state, admin, "ls -l /dev",
		{ "crw-rw----  root  sudo  fd0     WORK              blank",
			"crw-rw-rw-  root  root  null" })
	okAt(state, admin, "cat /dev/fd0", { "blank" })
	-- There is no word a survivor can write to a raw disk, so every one of them
	-- is the device's own refusal.
	badAt(state, admin, "echo on > /dev/fd0", "fd0: invalid value")
	badAt(state, admin, "echo format > /dev/fd0", "fd0: invalid value")
	-- And it is a device, so the filesystem refuses to treat it as anything else.
	badAt(state, admin, "rm /dev/fd0", "rm: /dev/fd0: is a device")
	badAt(state, admin, "cp /dev/fd0 /home/admin/x", "cp: /dev/fd0: is a device")
	badAt(state, admin, "touch /dev/other", "/dev: read-only")

	-- Unformatted: mount has no super block to read, and says it in mount(8)'s own
	-- shape, about the pair.
	badAt(state, admin, "mount /dev/fd0 /mnt",
		"mount: /dev/fd0 on /mnt: Incorrect super block")
	eq("and nothing was mounted", CeroSecOS.mountTable(state), nil)

	-- A device is worth nothing on the disk, drive included: df has not moved.
	local nodes, bytes = CeroSecOS.usage(state)
	local bare = fresh()
	local bareNodes, bareBytes = CeroSecOS.usage(bare)
	eq("the drive costs the machine no node", nodes, bareNodes)
	eq("and no byte", bytes, bareBytes)
end

-- 47c. newfs, and what it prints.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()

	okAt(state, admin, "newfs /dev/fd0", { "/dev/fd0: 4096 bytes, 32 inodes" })
	-- Built from the constants and not typed: a drive that grew would move the
	-- line the machine prints, and this is what says so.
	okAt(state, admin, "newfs /dev/fd0",
		{ "/dev/fd0: " .. CeroSecOS.FLOPPY_BYTES .. " bytes, "
			.. CeroSecOS.FLOPPY_NODES .. " inodes" })
	okAt(state, admin, "cat /dev/fd0", { "ready" })

	-- The root directory is whoever formatted it, at 755. Not root's, because the
	-- sudo group may format and a disk nobody in it can write is a disk nobody
	-- can use.
	local root = CeroSecOS.floppyRoot(state)
	eq("the root of the disk belongs to whoever formatted it", root.owner, "admin")
	eq("at 755", root.mode, 755)
	eq("and it is empty", CeroSecOS.countEntries(root), 0)

	-- And it really empties: a second newfs is a format and not a suggestion.
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "echo keep > /mnt/notes.txt", {})
	okAt(state, admin, "cat /mnt/notes.txt", { "keep" })
	badAt(state, admin, "newfs /dev/fd0", "newfs: /dev/fd0: Device busy")
	okAt(state, admin, "umount /mnt", {})
	okAt(state, admin, "newfs /dev/fd0", { "/dev/fd0: 4096 bytes, 32 inodes" })
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "ls /mnt", {})
end

-- 47d. The graft: /mnt IS the disk, and every command works through it.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy("WORK")
	okAt(state, admin, "newfs /dev/fd0", nil)

	-- Something in /mnt before the mount, to prove it is COVERED and not emptied.
	-- Written by root, because /mnt is root's at 755: the place is the machine's
	-- and a survivor keeping files in it would have to be root to do it.
	local rootBefore = open(state, "root")
	okAt(state, rootBefore, "echo under > /mnt/hidden.txt", {})
	okAt(state, admin, "cat /mnt/hidden.txt", { "under" })
	local under = select(2, CeroSecOS.usage(state))

	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "mount",
		{ "/dev/hda on / type ufs (rw)", "/dev/fd0 on /mnt type ufs (rw)" })
	okAt(state, admin, "cat /dev/fd0", { "mounted" })

	-- The file underneath is out of sight and still on the hard disk, which is
	-- what a mount point has meant since there were two filesystems.
	okAt(state, admin, "ls /mnt", {})
	badAt(state, admin, "cat /mnt/hidden.txt", "cat: /mnt/hidden.txt: no such file")
	eq("and it is still costing the hard disk what it costs",
		select(2, CeroSecOS.usage(state)), under)

	-- Every command, through the graft, with nothing told about a floppy.
	okAt(state, admin, "echo hello > /mnt/notes.txt", {})
	okAt(state, admin, "cat /mnt/notes.txt", { "hello" })
	okAt(state, admin, "mkdir /mnt/sub", {})
	okAt(state, admin, "cp /mnt/notes.txt /mnt/sub/copy.txt", {})
	okAt(state, admin, "ls /mnt", { "notes.txt  sub" })
	okAt(state, admin, "cat /mnt/sub/copy.txt", { "hello" })
	okAt(state, admin, "grep hello /mnt/notes.txt", { "hello" })
	okAt(state, admin, "wc -l /mnt/notes.txt", { "     1 /mnt/notes.txt" })
	okAt(state, admin, "mv /mnt/notes.txt /mnt/renamed.txt", {})
	okAt(state, admin, "ls /mnt", { "renamed.txt  sub" })
	okAt(state, admin, "rm -r /mnt/sub", {})
	okAt(state, admin, "cd /mnt", {})

	-- And every one of those landed on the DISK and not on the machine.
	eq("the hard disk has not moved a byte", select(2, CeroSecOS.usage(state)), under)
	local disk = CeroSecOS.floppyRoot(state)
	check("the file is on the disk", disk.children["renamed.txt"] ~= nil)

	-- Out again, and the covered file is back.
	local at = open(state, "admin")
	okAt(state, at, "umount /mnt", {})
	okAt(state, at, "ls /mnt", { "hidden.txt" })
	okAt(state, at, "cat /mnt/hidden.txt", { "under" })
	okAt(state, at, "cat /dev/fd0", { "ready" })
end

-- 47e. The two disks never share a ceiling.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})

	local before = select(2, CeroSecOS.usage(state))
	local rootSession = CeroSecOS.rootSession()

	-- Fill the floppy: one maximal file is the whole of it, which is the ratio
	-- the drive was sized at.
	local block = string.rep("y", CeroSecOS.FLOPPY_BYTES)
	eq("one maximal file fills the disk",
		CeroSecOS.writeFile(state, rootSession, "/mnt/big", block, false, nil), true)
	-- Every write of a BYTE is refused. An empty file and a directory cost the
	-- disk no byte and still go in, which is the same answer the machine's own
	-- drive gives when it is full: the two ceilings are two ceilings.
	badAt(state, admin, "echo x > /mnt/more", "echo: /mnt/more: disk full")
	badAt(state, admin, "cp /mnt/big /mnt/copy", "cp: /mnt/copy: disk full")
	okAt(state, admin, "touch /mnt/empty", {})
	okAt(state, admin, "rm /mnt/empty", {})

	-- And the machine has not noticed: df on hda is where it was, and a write to
	-- the hard disk still goes in.
	eq("a full floppy did not fill the machine",
		select(2, CeroSecOS.usage(state)), before)
	okAt(state, admin, "echo fine > /home/admin/ok.txt", {})

	-- df says both, and the floppy's rows are the floppy's.
	local lines = okAt(state, admin, "df", nil)
	eq("df has a header and four rows", #lines, 5)
	eq("the drive first", string.match(lines[2], "^(%S+)"), "hda")
	eq("its nodes", string.match(lines[3], "^(%S+)"), "nodes")
	eq("then the disk", string.match(lines[4], "^(%S+)"), "fd0")
	eq("and the disk's nodes", string.match(lines[5], "^(%S+)%s+(%S+)"), "fd0")
	eq("the disk's size is the disk's",
		tonumber(string.match(lines[4], "^%S+%s+(%d+)")), CeroSecOS.FLOPPY_BYTES)
	eq("and it is full",
		tonumber(string.match(lines[4], "^%S+%s+%d+%s+(%d+)")), CeroSecOS.FLOPPY_BYTES)
	eq("the disk's node ceiling is the disk's",
		tonumber(string.match(lines[5], "^%S+%s+%S+%s+(%d+)")), CeroSecOS.FLOPPY_NODES)

	-- The other way round: a machine filled to its own ceiling still writes to
	-- the disk in the drive.
	okAt(state, admin, "rm /mnt/big", {})
	local used = select(2, CeroSecOS.usage(state))
	local blocks = math.floor((CeroSecOS.MAX_TOTAL_BYTES - used) / CeroSecOS.MAX_FILE_BYTES)
	local pad = string.rep("z", CeroSecOS.MAX_FILE_BYTES)
	for i = 1, blocks do
		CeroSecOS.writeFile(state, rootSession, "/b" .. i, pad, false, nil)
	end
	local room = CeroSecOS.MAX_TOTAL_BYTES - select(2, CeroSecOS.usage(state))
	CeroSecOS.writeFile(state, rootSession, "/last", string.rep("z", room), false, nil)
	eq("the machine is exactly full",
		select(2, CeroSecOS.usage(state)), CeroSecOS.MAX_TOTAL_BYTES)
	badAt(state, admin, "echo x > /home/admin/no.txt",
		"echo: /home/admin/no.txt: disk full")
	okAt(state, admin, "echo yes > /mnt/still.txt", {})
	okAt(state, admin, "cat /mnt/still.txt", { "yes" })
end

-- 47f. The node ceiling is the disk's too.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})

	-- The root of the disk is one of them, so there is room for one fewer.
	for i = 1, CeroSecOS.FLOPPY_NODES - 1 do
		okAt(state, admin, "touch /mnt/f" .. i, {})
	end
	eq("the disk is at its node ceiling",
		select(1, CeroSecOS.subtreeUsage(CeroSecOS.floppyRoot(state))),
		CeroSecOS.FLOPPY_NODES)
	badAt(state, admin, "touch /mnt/one-more", "touch: /mnt/one-more: disk full")
	-- And the machine, which has hundreds left, is untouched by it.
	okAt(state, admin, "touch /home/admin/plenty", {})
end

-- 47g. umount, and who is standing in it.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "mkdir /mnt/sub", {})

	-- The session that typed it, at the mount point itself and below it.
	okAt(state, admin, "cd /mnt", {})
	badAt(state, admin, "umount /mnt", "umount: /mnt: Device busy")
	okAt(state, admin, "cd /mnt/sub", {})
	badAt(state, admin, "umount /mnt", "umount: /mnt: Device busy")
	-- A path that means the mount point without being spelled like it.
	okAt(state, admin, "cd /mnt/sub/..", {})
	badAt(state, admin, "umount /mnt", "umount: /mnt: Device busy")
	okAt(state, admin, "cd /", {})
	okAt(state, admin, "umount /mnt", {})

	-- And somebody ELSE standing in it, which is the case only the machine can
	-- see: the sessions come from the caller, the same list `who` prints.
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	local env = { now = FIXED, net = {
		sessions = function()
			return { { user = "bob", line = "ttyp0", cwd = "/mnt/sub" } }
		end,
	} }
	badAt(state, admin, "umount /mnt", "umount: /mnt: Device busy", env)
	-- Somebody standing somewhere else is not somebody standing in it.
	env.net.sessions = function()
		return { { user = "bob", line = "ttyp0", cwd = "/home/admin" } }
	end
	okAt(state, admin, "umount /mnt", {}, env)
end

-- 47h. mount's own refusals, and umount's.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)

	badAt(state, admin, "mount /dev/fd0 /etc/motd", "mount: /etc/motd: not a directory")
	badAt(state, admin, "mount /dev/fd0 /nowhere", "mount: /nowhere: no such file")
	badAt(state, admin, "mount /dev/fd0 /", "mount: /: Device busy")
	-- /dev is the one other place a mount cannot be undone from: the device file
	-- umount reads to find out which drive it is unmounting lives there, so a disk
	-- mounted over it covers the only handle on itself.
	badAt(state, admin, "mount /dev/fd0 /dev", "mount: /dev: Device busy")
	okAt(state, admin, "ln -s /dev /home/admin/d", {})
	badAt(state, admin, "mount /dev/fd0 /home/admin/d",
		"mount: /home/admin/d: Device busy")
	badAt(state, admin, "mount /dev/null /mnt", "mount: /dev/null: not a floppy drive")
	badAt(state, admin, "newfs /dev/null", "newfs: /dev/null: not a floppy drive")
	badAt(state, admin, "mount /dev/fd0", "mount: usage: mount [<device> <dir>]")
	badAt(state, admin, "umount", "umount: usage: umount <dir>")
	badAt(state, admin, "newfs", "newfs: usage: newfs <device>")

	-- Mounted twice, in two ways: the place is taken, and so is the drive.
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	badAt(state, admin, "mount /dev/fd0 /mnt", "mount: /mnt: Device busy")
	okAt(state, admin, "mkdir /home/admin/elsewhere", {})
	badAt(state, admin, "mount /dev/fd0 /home/admin/elsewhere",
		"mount: /dev/fd0: Device busy")
	-- And any directory will do, not only /mnt: the mount table is keyed by the
	-- place and the machine ships exactly one place to be polite about it.
	okAt(state, admin, "umount /mnt", {})
	okAt(state, admin, "mount /dev/fd0 /home/admin/elsewhere", {})
	okAt(state, admin, "echo here > /home/admin/elsewhere/x", {})
	okAt(state, admin, "mount", { "/dev/hda on / type ufs (rw)",
		"/dev/fd0 on /home/admin/elsewhere type ufs (rw)" })
	okAt(state, admin, "umount /home/admin/elsewhere", {})
	badAt(state, admin, "umount /home/admin/elsewhere",
		"umount: /home/admin/elsewhere: not mounted")
end

-- 47i. A rename never crosses two disks.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "echo mine > /home/admin/notes.txt", {})

	badAt(state, admin, "mv /home/admin/notes.txt /mnt",
		"mv: /mnt/notes.txt: cross-device link")
	badAt(state, admin, "mv /home/admin/notes.txt /mnt/notes.txt",
		"mv: /mnt/notes.txt: cross-device link")
	-- Nothing was moved and nothing was half-moved.
	okAt(state, admin, "cat /home/admin/notes.txt", { "mine" })
	okAt(state, admin, "ls /mnt", {})

	-- The way across is the two commands the manual names.
	okAt(state, admin, "cp /home/admin/notes.txt /mnt", {})
	okAt(state, admin, "rm /home/admin/notes.txt", {})
	okAt(state, admin, "cat /mnt/notes.txt", { "mine" })
	-- And back.
	badAt(state, admin, "mv /mnt/notes.txt /home/admin/back.txt",
		"mv: /home/admin/back.txt: cross-device link")
	-- A rename INSIDE one disk is an ordinary rename, on either of them.
	okAt(state, admin, "mv /mnt/notes.txt /mnt/other.txt", {})
	okAt(state, admin, "cat /mnt/other.txt", { "mine" })
end

-- 47j. Who may format and who may mount is the mode on the drive.
do
	local state = fresh()
	local rootSession = open(state, "root")
	addUser(state, "bob", "", "/home/bob", false)
	CeroSecOS.createNode(state, rootSession, "/home/bob",
		CeroSecOS.newDir("bob", CeroSecOS.HOME_MODE), nil)
	local bob = open(state, "bob")
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()

	-- bob is in no group the device names, so both bits are shut to him.
	badAt(state, bob, "newfs /dev/fd0", "newfs: /dev/fd0: permission denied")
	badAt(state, bob, "mount /dev/fd0 /mnt", "mount: /dev/fd0: permission denied")
	badAt(state, bob, "cat /dev/fd0", "fd0: permission denied")
	-- admin is named in /etc/sudoers, which IS membership of the sudo group.
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	badAt(state, bob, "umount /mnt", "umount: /mnt: permission denied")
	okAt(state, admin, "umount /mnt", {})

	-- And the mode really is the whole of the rule: open it and bob may format.
	okAt(state, rootSession, "chmod 666 /dev/fd0", {})
	okAt(state, bob, "newfs /dev/fd0", nil)
	okAt(state, bob, "mount /dev/fd0 /mnt", {})
	okAt(state, bob, "umount /mnt", {})
	-- Half of it: readable is mountable, and not formattable.
	okAt(state, rootSession, "chmod 664 /dev/fd0", {})
	okAt(state, bob, "mount /dev/fd0 /mnt", {})
	okAt(state, bob, "umount /mnt", {})
	badAt(state, bob, "newfs /dev/fd0", "newfs: /dev/fd0: permission denied")

	-- The mode is the DRIVE's and outlives the disk that was in it: it is
	-- remembered on the machine between commands, not on the disk.
	eq("the chmod was remembered by the machine", state.fdmode, 664)
	state.floppy = CeroSecOS.newFloppy("OTHER")
	okAt(state, bob, "cat /dev/fd0", { "blank" })
	badAt(state, bob, "newfs /dev/fd0", "newfs: /dev/fd0: permission denied")
	-- And an empty slot forgets nothing either: the drive is bolted to the case.
	state.floppy = nil
	okAt(state, rootSession, "ls /dev", { "null" })
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, rootSession, "ls -l /dev", nil)
	eq("the drive is still wearing the mode it was given", state.fdmode, 664)
	badAt(state, bob, "newfs /dev/fd0", "newfs: /dev/fd0: permission denied")
end

-- 47k. A disk carried to another machine keeps everything, owners included.
do
	local a = fresh("ksp-04-11")
	local rootA = open(a, "root")
	addUser(a, "bob", "", "/home/bob", false)
	local admin = open(a, "admin")
	a.floppy = CeroSecOS.newFloppy("BOB")
	okAt(a, admin, "newfs /dev/fd0", nil)
	okAt(a, admin, "mount /dev/fd0 /mnt", {})
	-- A file of bob's on it, that only bob and root may read.
	CeroSecOS.createNode(a, rootA, "/mnt/secret.txt",
		CeroSecOS.newFile("bob", 600, "bob's notes"), nil)
	local LINE = "-rw-------  bob    bob        11  Jan  1 00:00  secret.txt"
	okAt(a, admin, "ls -l /mnt", { LINE })
	badAt(a, admin, "cat /mnt/secret.txt", "cat: /mnt/secret.txt: permission denied")

	-- Out of the drive: the disk becomes a plain table, the way it does on its
	-- way into an item's modData, and back again on the other machine.
	okAt(a, admin, "umount /mnt", {})
	local carried = CeroSecOS.diskToData(a.floppy)
	a.floppy = nil
	check("it really left the first machine", CeroSecOS.floppyOf(a) == nil)

	local b = fresh("ksp-front-02")
	local rootB = open(b, "root")
	addUser(b, "bob", "", "/home/bob", false)
	local adminB = open(b, "admin")
	local disk, why = CeroSecOS.diskFromData(carried)
	check("the second machine takes the disk: " .. tostring(why), disk ~= nil)
	b.floppy = disk

	okAt(b, adminB, "mount /dev/fd0 /mnt", {})
	okAt(b, adminB, "cat /dev/fd0", { "mounted" })
	okAt(b, adminB, "ls /mnt", { "secret.txt" })
	-- Same name, same mode, same owner -- and the same account, because an
	-- account is a NAME and the name went with the file.
	okAt(b, adminB, "ls -l /mnt", { LINE })
	badAt(b, adminB, "cat /mnt/secret.txt", "cat: /mnt/secret.txt: permission denied")
	local bobB = open(b, "bob")
	okAt(b, bobB, "cat /mnt/secret.txt", { "bob's notes" })
	-- Root reads all of it, here as anywhere.
	okAt(b, rootB, "cat /mnt/secret.txt", { "bob's notes" })

	-- The copy is a copy: writing on the second machine cannot reach the first.
	eq("the first machine's drive is still empty", CeroSecOS.floppyOf(a), nil)
	okAt(b, rootB, "echo added > /mnt/new.txt", {})
	eq("and what was carried is not the table the machine is running on",
		carried.fs.children["new.txt"], nil)
end

-- 47l. The gate on what goes into the drive, and on what a state may hold.
do
	local state = fresh()
	local admin = open(state, "admin")
	eq("a fresh machine validates", CeroSecOS.validate(state), true)

	-- A blank disk in the slot is a machine that still boots.
	state.floppy = CeroSecOS.newFloppy("WORK")
	eq("a blank disk validates", CeroSecOS.validate(state), true)
	okAt(state, admin, "newfs /dev/fd0", nil)
	eq("a formatted one does too", CeroSecOS.validate(state), true)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	eq("and a mounted one", CeroSecOS.validate(state), true)

	-- What is refused, one reason each.
	eq("a disk that is not a table", CeroSecOS.validateDisk("floppy"), false)
	eq("a disk of an unknown version", CeroSecOS.validateDisk({ v = 99 }), false)
	eq("a label longer than a sticker",
		CeroSecOS.validateDisk({ v = 1, label = string.rep("x", CeroSecOS.LABEL_MAX + 1) }),
		false)
	eq("a label of exactly a sticker is fine",
		CeroSecOS.validateDisk({ v = 1, label = string.rep("x", CeroSecOS.LABEL_MAX) }),
		true)
	eq("a root that is not a directory",
		CeroSecOS.validateDisk({ v = 1, fs = CeroSecOS.newFile("root", 644, "x") }), false)

	-- Past the disk's own ceilings, which NEITHER the boot gate nor the slot asks
	-- about -- and they are the same gate, which is the point of this block.
	--
	-- Being over a quota is a state a filesystem can be IN: that is already the
	-- rule for the machine's own drive, and the answer to it is that the next write
	-- says "disk full" until room is made. A gate that refused would cost the
	-- player his whole computer for a disk he could fix with one `rm` -- osState's
	-- refusal is sticky and the firmware repair does not reach into the drive.
	--
	-- And the SLOT may not be stricter than the boot gate, which is the half that
	-- is easy to get wrong: a machine that runs on a disk can hand it out, so a
	-- slot that refused what the boot gate accepts is a machine handing the player
	-- a disk no machine in the world will take back.
	local many = CeroSecOS.newDir("root", 755)
	for i = 1, CeroSecOS.FLOPPY_NODES do
		many.children["f" .. i] = CeroSecOS.newFile("root", 644, "")
	end
	local over = { v = 1, fs = many }
	eq("the boot gate runs on a disk past its node ceiling",
		CeroSecOS.validateDisk(over), true)
	eq("and the slot, which walks it on every command after, does not",
		CeroSecOS.diskFromData(over), nil)
	local fat = CeroSecOS.newDir("root", 755)
	fat.children["big"] = CeroSecOS.newFile("root", 644,
		string.rep("x", CeroSecOS.FLOPPY_BYTES))
	fat.children["more"] = CeroSecOS.newFile("root", 644, "x")
	local heavy = { v = 1, fs = fat }
	eq("the boot gate runs on a disk past its byte ceiling",
		CeroSecOS.validateDisk(heavy), true)
	eq("and the slot does not take that either", CeroSecOS.diskFromData(heavy), nil)
	-- Which leaves the trap, and it is closed at the other end: a disk the slot
	-- would not take never leaves the drive, so there is no disk a machine can hand
	-- the player that no machine will accept. Its ejectDisk is the server's, and
	-- window_test drives it; what is asserted here is the gate the two agree on.
	eq("the drive would keep it", CeroSecOS.validateDisk(heavy, true), false)
	-- Which is the whole round trip: a machine that ejects one can be handed it.
	do
		-- As root: the disk was forged, and its root directory is root's at 755
		-- the way a disk formatted by root would be.
		local machine = fresh()
		local who = open(machine, "root")
		machine.floppy = heavy
		okAt(machine, who, "mount /dev/fd0 /mnt", {})
		-- Over its ceiling, and it says so rather than pretending.
		badAt(machine, who, "echo x > /mnt/y", "echo: /mnt/y: disk full")
		-- And one `rm` is the way out, which is the reason the gate lets it boot.
		okAt(machine, who, "rm /mnt/big", {})
		okAt(machine, who, "echo x > /mnt/y", {})
		okAt(machine, who, "umount /mnt", {})
	end
	-- The separator is in the sentence when a disk IS refused.
	local named = CeroSecOS.newDir("root", 755)
	for i = 1, 12 do
		local sub = CeroSecOS.newDir("root", 755)
		for j = 1, 90 do sub.children["f" .. j] = CeroSecOS.newFile("root", 644, "") end
		named.children["d" .. i] = sub
	end
	eq("in a sentence with its separator in it",
		select(2, CeroSecOS.validateDisk({ v = 1, fs = named })), "floppy: too many nodes")
	-- The boot gate still bounds what a walk costs, at the machine's own ceiling:
	-- a save file is a thing somebody can write.
	local huge = CeroSecOS.newDir("root", 755)
	for i = 1, 12 do
		local sub = CeroSecOS.newDir("root", 755)
		for j = 1, 90 do sub.children["f" .. j] = CeroSecOS.newFile("root", 644, "") end
		huge.children["d" .. i] = sub
	end
	eq("a forged tree past the machine's own node ceiling is refused",
		CeroSecOS.validateDisk({ v = 1, fs = huge }), false)

	-- The copy refuses what it cannot carry, rather than dropping it quietly.
	eq("a function on a disk is not a disk",
		CeroSecOS.diskFromData({ v = 1, fs = print }), nil)
	local deep = { v = 1 }
	local at = deep
	for i = 1, CeroSecOS.DISK_COPY_DEPTH + 2 do
		at.down = {}
		at = at.down
	end
	eq("a tree deeper than the filesystem can address is not a disk",
		CeroSecOS.diskFromData(deep), nil)
	-- And a disk the gate refuses does not come through the copy either.
	local forged = CeroSecOS.newDir("root", 755)
	for i = 1, 12 do
		local sub = CeroSecOS.newDir("root", 755)
		for j = 1, 90 do sub.children["f" .. j] = CeroSecOS.newFile("root", 644, "") end
		forged.children["d" .. i] = sub
	end
	eq("a disk past what ANY filesystem here may hold is refused at the slot",
		CeroSecOS.diskFromData({ v = 1, fs = forged }), nil)
end

-- 47m. A mount naming a drive with nothing in it is swept on the way in.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "echo x > /mnt/f.txt", {})

	-- A disk taken out by a hand that never reached the eject path.
	state.floppy = nil
	eq("the mount is still written down", #state.mounts, 1)
	-- The walk does not cross it -- the directory underneath shows through -- so
	-- nothing anybody types can reach a disk that is not there.
	okAt(state, admin, "ls /mnt", {})
	eq("and the sweep takes it away", CeroSecOS.checkMounts(state), true)
	eq("leaving nothing mounted", CeroSecOS.mountTable(state), nil)
	eq("and nothing left to sweep", CeroSecOS.checkMounts(state), false)
	-- migrate runs it, which is what makes a saved state safe to run on.
	state.mounts = { { dev = "fd0", dir = "/mnt", type = "ufs" } }
	eq("migrate hands the same machine back", CeroSecOS.migrate(state, "ksp-front-01"), state)
	eq("with the mount swept off it", CeroSecOS.mountTable(state), nil)
end

-- 47m2. A mount point is not a name to take away.
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "touch /mnt/f", {})

	-- Taking the mount point away would leave the mount written down against a
	-- place that is not there any more, and every path to the disk answering "no
	-- such file" while the disk is still in the drive. EBUSY, which is what rmdir
	-- has always answered about a mount point.
	badAt(state, rootSession, "rm -r /mnt", "rm: /mnt: Device busy")
	badAt(state, rootSession, "mv /mnt /moved", "mv: /moved: Device busy")
	-- And the same deletion one level up, which is the same deletion.
	okAt(state, admin, "umount /mnt", {})
	okAt(state, rootSession, "mkdir /home/admin/here", {})
	okAt(state, admin, "mount /dev/fd0 /home/admin/here", {})
	badAt(state, rootSession, "rm -r /home/admin", "rm: /home/admin: Device busy")
	badAt(state, rootSession, "mv /home/admin /moved", "mv: /moved: Device busy")
	badAt(state, rootSession, "rm -r /home/admin/here",
		"rm: /home/admin/here: Device busy")
	-- Writing OVER one is the same unhooking from the other end, and the mutator
	-- refuses it. `mv` cannot ask for it -- a destination that is a directory takes
	-- the source INSIDE it, which through a mount point is an ordinary
	-- cross-device move -- so the rule is asked of moveNode directly.
	okAt(state, rootSession, "mkdir /spare", {})
	badAt(state, rootSession, "mv /spare /home/admin/here",
		"mv: /home/admin/here/spare: cross-device link")
	eq("and the mount point itself cannot be written over",
		select(2, CeroSecOS.moveNode(state, CeroSecOS.rootSession(),
			"/spare", "/home/admin/here", nil)), "Device busy")

	-- Unmounted, every one of them is an ordinary directory again.
	okAt(state, admin, "umount /home/admin/here", {})
	okAt(state, rootSession, "rm -r /home/admin/here", {})
	okAt(state, rootSession, "rm -r /mnt", {})
	eq("and the mount table is empty", CeroSecOS.mountTable(state), nil)

	-- Inside the disk, a rename is an ordinary rename: the rule is about the
	-- mount POINT and not about the filesystem behind it.
	CeroSecOS.ensureMnt(state)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "mv /mnt/f /mnt/g", {})
	okAt(state, admin, "ls /mnt", { "g" })
	okAt(state, admin, "rm /mnt/g", {})
end

-- 47n. An older machine gains the room and the drive, and loses nothing.
do
	local state = fresh()
	local admin = open(state, "admin")
	okAt(state, admin, "echo mine > /home/admin/notes.txt", {})
	-- A machine saved before the drive existed: no /mnt, and the three
	-- executables that came with it missing.
	state.fs.children.mnt = nil
	state.fs.children.bin.children.mount = nil
	state.fs.children.bin.children.umount = nil
	state.fs.children.bin.children.newfs = nil
	state.sysv = 11

	eq("the upgrade changed something", CeroSecOS.upgradeSystem(state), true)
	eq("the system version moved", state.sysv, CeroSecOS.SYSTEM_VERSION)
	local mnt = CeroSecOS.systemNode(state, CeroSecOS.MNT_PATH)
	check("/mnt is back", mnt ~= nil and mnt.type == "dir")
	eq("root's", mnt.owner, "root")
	eq("at 755", mnt.mode, CeroSecOS.MNT_MODE)
	eq("and empty", CeroSecOS.countEntries(mnt), 0)
	for _, name in ipairs({ "mount", "umount", "newfs" }) do
		local node = state.fs.children.bin.children[name]
		check("/bin/" .. name .. " is back", node ~= nil and node.type == "file")
		eq("with its description", node.data, CeroSecOS.commandDesc(name))
	end
	okAt(state, admin, "cat /home/admin/notes.txt", { "mine" })
	eq("a second pass does nothing", CeroSecOS.upgradeSystem(state), false)

	-- And root deleting /mnt is root's right and stays done.
	okAt(state, open(state, "root"), "rm -r /mnt", {})
	eq("the upgrade has nothing left to say", CeroSecOS.upgradeSystem(state), false)
	eq("/mnt stays deleted", CeroSecOS.systemNode(state, CeroSecOS.MNT_PATH), nil)
	-- The firmware is the way back, and it puts the place back without reaching
	-- into the drive: what is IN it is a thing in the world.
	state.floppy = CeroSecOS.newFloppy("KEEP")
	CeroSecOS.restoreSystem(state)
	local back = CeroSecOS.systemNode(state, CeroSecOS.MNT_PATH)
	check("the firmware puts /mnt back", back ~= nil and back.type == "dir")
	check("and does not reach into the drive", CeroSecOS.floppyOf(state) ~= nil)
	eq("the label is still on the sticker", state.floppy.label, "KEEP")
	okAt(state, admin, "cat /home/admin/notes.txt", { "mine" })
end

-- 47o. The commands are files, like every other command on this machine.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	for _, name in ipairs({ "mount", "umount", "newfs" }) do
		local node = state.fs.children.bin.children[name]
		check("/bin/" .. name .. " ships", node ~= nil)
		eq("root's", node.owner, "root")
		eq("at 755", node.mode, 755)
		eq("holding its own description", node.data, CeroSecOS.commandDesc(name))
	end
	-- So rm really takes one away.
	okAt(state, open(state, "root"), "rm /bin/newfs", {})
	badAt(state, admin, "newfs /dev/fd0", "newfs: command not found")
	okAt(state, admin, "mount", { "/dev/hda on / type ufs (rw)" })
end


-- 47p. Through a symbolic link, every rule is the same rule
--
-- The walk crosses a mount on the path it really took, with every link already
-- followed; the path it HANDS BACK is the one that was typed, because that is
-- what `cd` keeps and what every shell prints. Those two are not the same string,
-- and every rule about where a node lives -- which disk it is on, whether it is a
-- mount point, whether it is under /dev -- has to be asked with the first.
--
-- Asked with the second, as they were when this rung was first written, a
-- symbolic link carried a write past the ceilings of the disk it landed on, a
-- rename past the cross-device refusal, a removal past the mount-point guard, and
-- a mount onto a name no walk would ever cross. Every block below is one of those.
--
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "ln -s /mnt /home/admin/gate", {})

	-- 1. The DISK's node ceiling, reached through the link.
	for i = 1, CeroSecOS.FLOPPY_NODES - 1 do
		okAt(state, admin, "touch /home/admin/gate/f" .. i, {})
	end
	eq("the disk is at its own node ceiling and not the machine's",
		select(1, CeroSecOS.subtreeUsage(CeroSecOS.floppyRoot(state))),
		CeroSecOS.FLOPPY_NODES)
	badAt(state, admin, "touch /home/admin/gate/one-more",
		"touch: /home/admin/gate/one-more: disk full")
	-- The machine, which has hundreds left, is untouched by it.
	okAt(state, admin, "touch /home/admin/plenty", {})
	for i = 1, CeroSecOS.FLOPPY_NODES - 1 do
		okAt(state, admin, "rm /home/admin/gate/f" .. i, {})
	end

	-- 2. The DISK's byte ceiling, likewise.
	local block = string.rep("y", CeroSecOS.MAX_FILE_BYTES)
	eq("one maximal file fills the disk through the link",
		CeroSecOS.writeFile(state, rootSession, "/home/admin/gate/big", block, false, nil),
		true)
	badAt(state, admin, "echo x > /home/admin/gate/more",
		"echo: /home/admin/gate/more: disk full")
	okAt(state, admin, "echo x > /home/admin/fine", {})
	okAt(state, rootSession, "rm /home/admin/gate/big", {})

	-- 3. A rename across the two disks, spelled through the link.
	okAt(state, admin, "echo mine > /home/admin/notes.txt", {})
	badAt(state, admin, "mv /home/admin/notes.txt /home/admin/gate/notes.txt",
		"mv: /home/admin/gate/notes.txt: cross-device link")
	badAt(state, admin, "mv /home/admin/notes.txt /home/admin/gate",
		"mv: /home/admin/gate/notes.txt: cross-device link")
	okAt(state, admin, "cat /home/admin/notes.txt", { "mine" })
	-- And back the other way.
	okAt(state, admin, "cp /home/admin/notes.txt /home/admin/gate", {})
	badAt(state, admin, "mv /home/admin/gate/notes.txt /home/admin/back.txt",
		"mv: /home/admin/back.txt: cross-device link")
	-- A rename INSIDE the disk, spelled through the link, is an ordinary rename.
	okAt(state, admin, "mv /home/admin/gate/notes.txt /home/admin/gate/other.txt", {})
	okAt(state, admin, "ls /mnt", { "other.txt" })

	-- And cp's own guard against copying a directory into itself, which is the
	-- last rule in the engine that was asked of the typed path.
	okAt(state, admin, "mkdir /home/admin/tree", {})
	okAt(state, admin, "ln -s /home/admin/tree /home/admin/same", {})
	badAt(state, admin, "cp -r /home/admin/tree /home/admin/tree/in",
		"cp: /home/admin/tree/in: invalid destination")
	badAt(state, admin, "cp -r /home/admin/tree /home/admin/same/in",
		"cp: /home/admin/same/in: invalid destination")
end

do
	-- 4. The mount point itself, reached through a link: not a name to take away
	-- and not a name to move. The move is the one that matters most -- it would
	-- have grafted the floppy's own root table into state.fs, leaving two live
	-- owners of one disk, which is the thing the copy on the item boundary exists
	-- to prevent.
	local state = fresh()
	local rootSession = open(state, "root")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, rootSession, "newfs /dev/fd0", nil)
	okAt(state, rootSession, "mount /dev/fd0 /mnt", {})
	okAt(state, rootSession, "echo secret > /mnt/notes.txt", {})
	okAt(state, rootSession, "ln -s / /root/r", {})

	badAt(state, rootSession, "rm -r /root/r/mnt", "rm: /root/r/mnt: Device busy")
	badAt(state, rootSession, "mv /root/r/mnt /root/moved", "mv: /root/moved: Device busy")
	check("the mount point is still on the disk", state.fs.children.mnt ~= nil)
	eq("nothing was grafted anywhere", state.fs.children.root.children.moved, nil)
	eq("and the mount still works", CeroSecOS.mountTable(state) ~= nil, true)
	okAt(state, rootSession, "cat /mnt/notes.txt", { "secret" })
	okAt(state, rootSession, "cat /root/r/mnt/notes.txt", { "secret" })

	-- The floppy's root is the machine's only through the mount, and never a node
	-- hanging in state.fs.
	local floppy = CeroSecOS.floppyRoot(state)
	local function reaches(node, target, depth)
		if node == target then return true end
		if depth > 8 or type(node) ~= "table" or node.children == nil then return false end
		local names = CeroSecOS.childNames(node)
		for i = 1, #names do
			if reaches(node.children[names[i]], target, depth + 1) then return true end
		end
		return false
	end
	check("the disk's root is nowhere inside the machine's own tree",
		not reaches(state.fs, floppy, 0))
end

do
	-- 5. A mount made ONTO a symbolic link is written down at the place, not at
	-- the name: a mount recorded under a name that goes through a link is a mount
	-- no walk will ever cross, and one whose ceilings every write beside it would
	-- still have been judged against.
	local state = fresh()
	local rootSession = open(state, "root")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, rootSession, "newfs /dev/fd0", nil)
	okAt(state, rootSession, "mkdir /root/real", {})
	okAt(state, rootSession, "ln -s /root/real /root/link", {})
	okAt(state, rootSession, "mount /dev/fd0 /root/link", {})

	eq("the table holds the place", state.mounts[1].dir, "/root/real")
	okAt(state, rootSession, "mount", { "/dev/hda on / type ufs (rw)",
		"/dev/fd0 on /root/real type ufs (rw)" })
	-- And it is really crossed, by either spelling.
	okAt(state, rootSession, "echo on the disk > /root/link/a.txt", {})
	check("the file is on the disk", CeroSecOS.floppyRoot(state).children["a.txt"] ~= nil)
	eq("and not on the hard drive underneath",
		state.fs.children.root.children.real.children["a.txt"], nil)
	okAt(state, rootSession, "cat /root/real/a.txt", { "on the disk" })
	-- Unmounted by either spelling too, and what was underneath comes back.
	okAt(state, rootSession, "umount /root/link", {})
	okAt(state, rootSession, "ls /root/real", {})
	okAt(state, rootSession, "mount /dev/fd0 /root/real", {})
	okAt(state, rootSession, "umount /root/link", {})
	eq("nothing mounted", CeroSecOS.mountTable(state), nil)
end

do
	-- 6. A session standing in the mount through a link is a session standing in
	-- the mount. A cwd is a path as it was TYPED, so each one is walked and not
	-- merely resolved as a string.
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	okAt(state, admin, "ln -s /mnt /home/admin/gate", {})
	okAt(state, admin, "cd /home/admin/gate", {})
	eq("the prompt still says what he typed", admin.cwd, "/home/admin/gate")
	badAt(state, admin, "umount /mnt", "umount: /mnt: Device busy")
	-- And somebody else, over the wire, standing in it the same way.
	okAt(state, admin, "cd /", {})
	local env = { now = FIXED, net = {
		sessions = function()
			return { { user = "bob", line = "ttyp0", cwd = "/home/admin/gate" } }
		end,
	} }
	badAt(state, admin, "umount /mnt", "umount: /mnt: Device busy", env)
	okAt(state, admin, "umount /mnt", {})
end

do
	-- 7. /dev is read-only through a link as well. The rule was asked of the typed
	-- path, so a link into /dev was a create /dev accepted.
	local state = fresh()
	local rootSession = open(state, "root")
	-- The sentence is the FILESYSTEM's here and not the command's: the commands
	-- carry a courtesy of their own that names the directory rather than the name
	-- ("/dev: read-only", so a player who tried once does not try a second name),
	-- and that one is spelled against the path as typed. Under it is this gate,
	-- which is the one that cannot be gone round, and it answers in the ordinary
	-- grammar: the command, the name, the reason.
	okAt(state, rootSession, "ln -s /dev /root/d", {})
	badAt(state, rootSession, "touch /root/d/x", "touch: /root/d/x: read-only")
	badAt(state, rootSession, "mkdir /root/d/x", "mkdir: /root/d/x: read-only")
	eq("and nothing was made in /dev",
		CeroSecOS.countEntries(CeroSecOS.systemNode(state, CeroSecOS.DEV_PATH)), 1)
end

do
	-- 8. A removal through a link unhooks the node from where it really hangs.
	local state = fresh()
	local rootSession = open(state, "root")
	okAt(state, rootSession, "mkdir /root/real", {})
	okAt(state, rootSession, "echo x > /root/real/f.txt", {})
	okAt(state, rootSession, "ln -s /root/real /root/link", {})
	okAt(state, rootSession, "rm /root/link/f.txt", {})
	eq("the file really went", state.fs.children.root.children.real.children["f.txt"], nil)
	-- And the link itself is still a link: rm takes away the name it was given.
	check("the link is untouched", state.fs.children.root.children.link ~= nil)
	okAt(state, rootSession, "rm /root/link", {})
	check("and now it is gone", state.fs.children.root.children.link == nil)
	check("while what it pointed at stays", state.fs.children.root.children.real ~= nil)
end

do
	-- 9. A history that lands on a floppy.
	--
	-- The exemption that makes a history free is the HARD DISK's -- it exists so
	-- that `df` on hda does not move because somebody typed -- so a home with a
	-- disk mounted over it has no exemption to spend and the history is an ordinary
	-- file on that disk. Written straight onto the node, as it is on the hard
	-- drive, it grew to sixteen kilobytes on a four-kilobyte disk, and the boot
	-- gate then refused the whole computer for it.
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy()
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /home/admin", {})
	for i = 1, 400 do
		CeroSecOS.historyAppend(state, admin, "echo a line of ordinary length " .. i, FIXED)
	end
	local nodes, bytes = CeroSecOS.subtreeUsage(CeroSecOS.floppyRoot(state))
	check("the history is bounded by the disk it is on (" .. bytes .. ")",
		bytes <= CeroSecOS.FLOPPY_BYTES)
	check("and by what a file may hold", bytes <= CeroSecOS.MAX_FILE_BYTES)
	eq("it costs a node like any other file", nodes, 2)
	eq("the machine still boots", CeroSecOS.validate(state), true)
	-- It really is being kept, and the oldest lines are the ones that go.
	local kept = CeroSecOS.historyLines(state, admin)
	check("there is a history there at all", #kept > 0)
	eq("ending on the last line typed", kept[#kept], "echo a line of ordinary length 400")

	-- The machine's OWN records -- the cron log, a mailbox, /var/log/wtmp -- are not
	-- written onto a mounted disk at all. They are found by a walk that does not
	-- cross a mount and written straight onto the node, and both of those are the
	-- hard disk's rules: under a mount the create would land where the find can
	-- never see it again, and the write would put bytes on a disk that never counted
	-- them. So the machine stops keeping them until the disk is out, and leaves
	-- nothing half-done on it.
	do
		local logged = fresh()
		local su = open(logged, "root")
		logged.floppy = CeroSecOS.newFloppy()
		okAt(logged, su, "newfs /dev/fd0", nil)
		okAt(logged, su, "mount /dev/fd0 /var/log", {})
		eq("wtmp is not written onto the disk",
			CeroSecOS.wtmpAppend(logged, "in", "admin", CeroSecOS.CONSOLE_LINE, nil, FIXED),
			false)
		eq("and nothing was left on it",
			select(1, CeroSecOS.subtreeUsage(CeroSecOS.floppyRoot(logged))), 1)
		okAt(logged, su, "umount /var/log", {})
		eq("with the disk out, the machine keeps its records again",
			CeroSecOS.wtmpAppend(logged, "in", "admin", CeroSecOS.CONSOLE_LINE, nil, FIXED),
			true)
	end

	-- The hard disk's own history is untouched by any of this: sixteen kilobytes,
	-- and exempt.
	local other = fresh()
	local them = open(other, "admin")
	local before = select(2, CeroSecOS.usage(other))
	for i = 1, 400 do
		CeroSecOS.historyAppend(other, them, "echo a line of ordinary length " .. i, FIXED)
	end
	local node = CeroSecOS.systemNode(other, "/home/admin/" .. CeroSecOS.HISTORY_NAME)
	check("a history on the hard disk is still the bigger file (" .. #node.data .. ")",
		#node.data > CeroSecOS.MAX_FILE_BYTES)
	check("and still under its own ceiling", #node.data <= CeroSecOS.HISTORY_BYTES)
	eq("and still costs the drive nothing but its node",
		select(2, CeroSecOS.usage(other)), before)
end


-- 47q. The round trip over the deepest disk the write path will make
--
-- The copy that crosses the item boundary is a recursive walk with a depth budget
-- on it, and that budget counts TABLE levels while a filesystem is counted in
-- PATH components -- a node and the `children` table under it are two levels for
-- one directory. Counted in components, the budget was seven directories where
-- the write path allows fifteen: a disk deeper than that could be made, mounted,
-- read and written, and then could not be copied back out of the drive.
--
-- What made that a disaster rather than a refusal is that the write onto the item
-- cleared the item's three keys BEFORE it knew the copy had worked. So the eject
-- emptied the machine's drive, emptied the item, and said nothing.
--
-- So: as deep a disk as the machine will make, all the way out and back in. The
-- depth is taken from the machine (`mkdir` until it refuses) and never typed,
-- because the number that matters is what the WRITE PATH allows and not what
-- anybody believes it allows.
--
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy("DEEP")
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})

	local path, above, deep = "/mnt", "/mnt", 0
	while true do
		local next = path .. "/s" .. (deep + 1)
		local r = runAt(state, admin, "mkdir " .. next, ENV)
		if not r.ok then break end
		above, path, deep = path, next, deep + 1
	end
	check("the machine made a deep tree on the disk (" .. deep .. ")", deep >= 8)
	-- The file goes one level ABOVE the deepest directory: the deepest one is
	-- already at the machine's own MAX_DEPTH, and a name inside it would be one
	-- past what a path here can address. The COPY still has to carry both.
	local bottom = above .. "/f.txt"
	okAt(state, admin, "echo the bottom > " .. bottom, {})
	okAt(state, admin, "cat " .. bottom, { "the bottom" })

	-- Out, as an eject does it, and the copy has to carry the whole of it.
	local carried = CeroSecOS.diskToData(state.floppy)
	check("the disk copies out of the drive at that depth", carried ~= nil)
	-- And onto the item, the way the eject writes it -- onto a modData that already
	-- held a disk, which is the case that lost everything.
	local item = { v = 1, fs = CeroSecOS.newDir("root", 755), label = "OLD" }
	eq("and onto an item that was carrying another one",
		CeroSecOS.writeDiskTo(item, state.floppy), true)
	eq("the old label is gone", item.label, "DEEP")
	check("and the new tree is there", item.fs.children.s1 ~= nil)

	-- A write that CANNOT be made leaves the item exactly as it was, which is the
	-- ordering the disaster was made of: cleared first, a failed copy left the item
	-- blank and the machine's own copy already dropped.
	local keep = { v = 1, fs = CeroSecOS.newDir("root", 755), label = "KEEP" }
	local held = keep.fs
	eq("a copy that cannot be made writes nothing",
		CeroSecOS.writeDiskTo(keep, { v = 1, fs = print }), false)
	eq("the item still has its version", keep.v, 1)
	eq("its label", keep.label, "KEEP")
	eq("and the very filesystem it was carrying", keep.fs, held)

	-- Back into a machine, and everything is still on it.
	local other = fresh("ksp-front-02")
	local them = open(other, "admin")
	local back = CeroSecOS.diskFromData(carried)
	check("the slot takes the deep disk", back ~= nil)
	other.floppy = back
	okAt(other, them, "mount /dev/fd0 /mnt", {})
	okAt(other, them, "cat " .. bottom, { "the bottom" })

	-- The budget is derived from the two things it is made of and never typed: a
	-- node and its children are two table levels for one path component.
	eq("the copy's budget is the walk's and not the path's",
		CeroSecOS.DISK_COPY_DEPTH, 3 + 2 * CeroSecOS.MAX_DEPTH)
end


-- 47r. What "bounded" has to be able to see
--
-- The ceilings a slot asks about are asked of the disk's FILESYSTEM, and twice
-- that was not the whole disk.
--
-- A key hung on the disk beside its filesystem was weighed by nothing at all: a
-- megabyte under a name of its own rode into state.floppy, into the save file and
-- out to every client, invisible to `df` and to `ls` and undeletable by any
-- command. And a device node costs the quota nothing BY DESIGN -- which is right
-- for the machine's own /dev, built afresh every command and swept again, and is a
-- hole on a disk, where nothing sweeps and the nodes are saved: three thousand of
-- them weigh nothing, count nothing, and cost the boot gate forty milliseconds on
-- every command the machine runs afterwards.
--
do
	local tiny = CeroSecOS.newDir("root", 755)

	-- The three keys a disk owns, and nothing else. What it IS is somebody's work
	-- or somebody's payload, and either way it is not ours to carry unweighed.
	eq("a disk is its own three keys",
		table.concat(CeroSecOS.DISK_KEYS, " "), "v fs label")
	eq("and a fourth is a refusal",
		select(2, CeroSecOS.validateDisk({ v = 1, fs = tiny, junk = "x" }, true)),
		"floppy: unknown field")
	eq("a numeric one too",
		select(2, CeroSecOS.validateDisk({ v = 1, fs = tiny, [3] = "x" }, true)),
		"floppy: unknown field")
	eq("and the slot is where it is asked",
		CeroSecOS.diskFromData({ v = 1, fs = tiny, junk = string.rep("x", 100000) }), nil)
	-- The three themselves still go in, label and all.
	check("an honest disk is untouched by the rule",
		CeroSecOS.diskFromData({ v = 1, fs = tiny, label = "WORK" }) ~= nil)
	check("and one with no label", CeroSecOS.diskFromData({ v = 1, fs = tiny }) ~= nil)

	-- No device on a disk. newfs never makes one, and the boot gate lets the null
	-- kind through only because its walk is shared with the machine's own drive.
	local devs = CeroSecOS.newDir("root", 755)
	devs.children.null = CeroSecOS.newNull()
	eq("a device on a disk is a refusal, and it is named",
		select(2, CeroSecOS.validateDisk({ v = 1, fs = devs }, true)), "floppy/null: bad type")
	eq("at the slot", CeroSecOS.diskFromData({ v = 1, fs = devs }), nil)
	-- However deep it is buried, and however little the ceilings can see of it.
	local deep = CeroSecOS.newDir("root", 755)
	local sub = CeroSecOS.newDir("root", 755)
	sub.children.null = CeroSecOS.newNull()
	deep.children.d = sub
	eq("buried as deep as you like", CeroSecOS.diskFromData({ v = 1, fs = deep }), nil)
	-- A thousand of them weigh nothing and count nothing, which is the whole reason
	-- the rule is about the TYPE and not about the weight.
	local many = CeroSecOS.newDir("root", 755)
	for i = 1, 90 do many.children["n" .. i] = CeroSecOS.newNull() end
	local nodes, bytes = CeroSecOS.subtreeUsage(many)
	eq("ninety devices weigh nothing", bytes, 0)
	eq("and count as nothing", nodes, 1)
	eq("and are refused all the same",
		CeroSecOS.diskFromData({ v = 1, fs = many }), nil)

	-- The blank disk is the shape the rule was half a rule on: a floppy off a shelf
	-- has no filesystem, so the gate used to answer "nothing to check" and take
	-- whatever else was written on it -- and then one `newfs` gave it a filesystem
	-- and the disk could never come out of the drive again.
	eq("a blank disk is asked the same question",
		CeroSecOS.diskFromData({ v = 1, junk = string.rep("x", 100000) }), nil)
	check("and an honest blank one still goes in",
		CeroSecOS.diskFromData({ v = 1 }) ~= nil)

	-- The same rule one level down, which is where the rest of it was hiding: a
	-- node's fields are its kind's and nothing else, and a `children` table on a
	-- FILE node is a whole tree the quota walk never descends into.
	eq("what a node is made of is its kind's five fields and one",
		table.concat(CeroSecOS.NODE_OWN_FIELD and
			{ CeroSecOS.NODE_OWN_FIELD.dir, CeroSecOS.NODE_OWN_FIELD.file,
				CeroSecOS.NODE_OWN_FIELD.link } or {}, " "), "children data target")
	local onFs = CeroSecOS.newDir("root", 755)
	onFs.junk = "x"
	eq("junk on the disk's own root", CeroSecOS.diskFromData({ v = 1, fs = onFs }), nil)
	local onNode = CeroSecOS.newDir("root", 755)
	onNode.children.f = CeroSecOS.newFile("root", 644, "")
	onNode.children.f.junk = "x"
	eq("junk on a node inside it", CeroSecOS.diskFromData({ v = 1, fs = onNode }), nil)
	local hidden = CeroSecOS.newDir("root", 755)
	local asFile = CeroSecOS.newFile("root", 644, "")
	asFile.children = {}
	for i = 1, 40 do asFile.children["n" .. i] = CeroSecOS.newFile("root", 644, "") end
	hidden.children.h = asFile
	eq("a whole tree hung under a file node weighs nothing",
		select(2, CeroSecOS.subtreeUsage(hidden)), 0)
	eq("and is refused", CeroSecOS.diskFromData({ v = 1, fs = hidden }), nil)
	local asLink = CeroSecOS.newDir("root", 755)
	local lk = CeroSecOS.newLink("root", "/x")
	lk.children = { y = CeroSecOS.newFile("root", 644, "") }
	asLink.children.l = lk
	eq("under a link node too", CeroSecOS.diskFromData({ v = 1, fs = asLink }), nil)
	-- And an owner nothing prints is a hiding place by another name -- as is a
	-- timestamp nothing checks, in a field that only ever comes out as a date.
	local longOwner = CeroSecOS.newDir("root", 755)
	longOwner.owner = string.rep("a", CeroSecOS.MAX_NAME + 1)
	eq("an owner longer than a name may be",
		select(2, CeroSecOS.validateDisk({ v = 1, fs = longOwner }, true)),
		"floppy: invalid name")
	local longGroup = CeroSecOS.newDir("root", 755)
	longGroup.group = string.rep("a", CeroSecOS.MAX_NAME + 1)
	eq("a group likewise", CeroSecOS.diskFromData({ v = 1, fs = longGroup }), nil)
	for _, when in ipairs({ -1, CeroSecOS.MAX_STAMP + 1, 1e300 }) do
		local stamped = CeroSecOS.newDir("root", 755)
		stamped.children.f = CeroSecOS.newFile("root", 644, "")
		stamped.children.f.mtime = when
		eq("a timestamp that is not a moment (" .. tostring(when) .. ")",
			select(2, CeroSecOS.validateDisk({ v = 1, fs = stamped }, true)),
			"floppy/f: bad mtime")
	end

	-- The walk that asks all of this runs on the table the GAME handed over, before
	-- a byte of it is copied -- so it is the only thing between a crafted modData
	-- and the engine, and it has to end. It was the copy that bounded the depth,
	-- and putting this in front of the copy took that bound away: a deep chain, or
	-- a table pointing at itself, was a stack overflow out of the command handler
	-- rather than a refusal.
	local chain = CeroSecOS.newDir("root", 755)
	local at = chain
	for _ = 1, CeroSecOS.MAX_DEPTH * 4 do
		local down = CeroSecOS.newDir("root", 755)
		at.children.d = down
		at = down
	end
	eq("a chain deeper than a path can be is refused and not fallen down",
		CeroSecOS.diskFromData({ v = 1, fs = chain }), nil)
	local loop = CeroSecOS.newDir("root", 755)
	loop.children.self = loop
	eq("and a tree that contains itself, which is infinitely deep",
		CeroSecOS.diskFromData({ v = 1, fs = loop }), nil)
	-- And the breadth is refused before the names are gathered: the ceiling that
	-- says no is one comparison, and collecting and sorting four hundred thousand
	-- names to reach it was nine seconds of the server's own thread.
	local crowd = CeroSecOS.newDir("root", 755)
	for i = 1, CeroSecOS.MAX_DIR_ENTRIES + 4 do
		crowd.children["f" .. i] = CeroSecOS.newFile("root", 644, "")
	end
	eq("a directory with more in it than one may hold",
		select(2, CeroSecOS.validateDisk({ v = 1, fs = crowd }, true)),
		"floppy: directory full")

	-- The same lesson one level up: a WELL-FORMED tree -- every node legal, every
	-- directory inside its ceiling, every path inside its depth -- was walked in
	-- full three times and copied once before anything consulted the node ceiling.
	-- The count is the walk's now, so the answer arrives at the node after the last
	-- one a disk may hold.
	local crowds = CeroSecOS.newDir("root", 755)
	local into = crowds
	for i = 1, CeroSecOS.FLOPPY_NODES * 4 do
		-- One short of the ceiling, so the directory always has room for the child
		-- that carries the tree downwards: what this shape is about is the NODE
		-- count, and a directory that ran over its own would answer first.
		if CeroSecOS.countEntries(into) >= CeroSecOS.MAX_DIR_ENTRIES - 1 then
			local down = CeroSecOS.newDir("root", 755)
			into.children.s = down
			into = down
		else
			into.children["f" .. i] = CeroSecOS.newFile("root", 644, "")
		end
	end
	-- The reason names the node the count ran out on, which is the walk saying
	-- where it stopped rather than what it added up to.
	local why = select(2, CeroSecOS.diskFromData({ v = 1, fs = crowds }))
	check("more nodes than a disk holds, all of them legal: " .. tostring(why),
		string.find(tostring(why), ": too many nodes", 1, true) ~= nil)
	-- And exactly as many as it holds is not too many.
	local exact = CeroSecOS.newDir("root", 755)
	for i = 1, CeroSecOS.FLOPPY_NODES - 1 do
		exact.children["f" .. i] = CeroSecOS.newFile("root", 644, "")
	end
	check("and a disk filled to the node ceiling goes in",
		CeroSecOS.diskFromData({ v = 1, fs = exact }) ~= nil)

	-- The gate the BOOT runs has to survive the blob too. Its plainness walk has a
	-- cycle test, which catches a table containing itself and not a chain fifty
	-- thousand tables long -- nothing this engine writes goes that deep and nothing
	-- from outside gets that far, but a gate whose job is to say whether a blob can
	-- be run on must not fall down on one.
	do
		local deepState = fresh()
		local at = deepState.fs
		for _ = 1, CeroSecOS.MAX_DEPTH * 8 do
			local down = CeroSecOS.newDir("root", 755)
			at.children.d = down
			at = down
		end
		local dOk, dWhy = CeroSecOS.validate(deepState)
		eq("a state deeper than any path on it is refused", dOk, false)
		check("and says so rather than falling down: " .. tostring(dWhy),
			string.find(tostring(dWhy), "too deep", 1, true) ~= nil)

		-- And the belt is far enough out that it can never be the thing that
		-- refuses a real machine, which is the only way this check can be worse
		-- than the crash it replaced: osState's refusal is sticky, so a false
		-- refusal here is a bricked computer. The deepest state there is, measured
		-- rather than argued: a disk in the drive, its tree as deep as the write
		-- path allows, a file at the bottom of it.
		local deepest = fresh()
		deepest.floppy = CeroSecOS.newFloppy("DEEP")
		deepest.floppy.fs = CeroSecOS.newDir("root", 755)
		local bottom = deepest.floppy.fs
		for i = 1, CeroSecOS.MAX_DEPTH - 1 do
			local down = CeroSecOS.newDir("root", 755)
			bottom.children["d" .. i] = down
			bottom = down
		end
		bottom.children.f = CeroSecOS.newFile("root", 644, "x")
		eq("the deepest machine this engine can produce still boots",
			CeroSecOS.validate(deepest), true)
		-- The same tree on the machine's own drive, which is one level shallower.
		local onDrive = fresh()
		local at2 = onDrive.fs
		for i = 1, CeroSecOS.MAX_DEPTH - 1 do
			local down = CeroSecOS.newDir("root", 755)
			at2.children["d" .. i] = down
			at2 = down
		end
		at2.children.f = CeroSecOS.newFile("root", 644, "x")
		eq("and so does the deepest filesystem", CeroSecOS.validate(onDrive), true)

		-- And a bound on how much it LOOKS AT, which is a different bound from the
		-- depth and is needed for a reason the depth cannot see. The plainness walk
		-- pops what it has seen on the way back out -- which is what makes it a test
		-- for a cycle rather than for a shared subtree, two names for one table
		-- being no kind of loop -- and the price is that a shared table is walked
		-- once per PATH to it. Twenty tables each pointing twice at the next are a
		-- million paths and a shape three levels deep: sixty-eight seconds, on a
		-- gate that runs on every read of the state.
		local shared = fresh()
		local leaf = {}
		local up = leaf
		for _ = 1, 24 do up = { a = up, b = up } end
		shared.junk = up
		local sOk, sWhy = CeroSecOS.validate(shared)
		eq("a shallow state with a million paths through it is refused", sOk, false)
		check("for what it is, and not for a depth it does not have: " .. tostring(sWhy),
			string.find(tostring(sWhy), "too many tables", 1, true) ~= nil)

		-- And this belt too is far from anything legal. The largest state there is
		-- -- every node the machine may hold, and a floppy full of them in the drive
		-- -- and it still boots.
		local biggest = fresh()
		local su = CeroSecOS.rootSession()
		local made = select(1, CeroSecOS.usage(biggest))
		local nth = 0
		while made < CeroSecOS.MAX_NODES do
			nth = nth + 1
			if CeroSecOS.createNode(biggest, su, "/p" .. nth,
					CeroSecOS.newDir("root", 755), nil) == nil then break end
			made = made + 1
			for i = 1, CeroSecOS.MAX_DIR_ENTRIES - 1 do
				if made >= CeroSecOS.MAX_NODES then break end
				if CeroSecOS.createNode(biggest, su, "/p" .. nth .. "/f" .. i,
						CeroSecOS.newFile("root", 644, "x"), nil) == nil then break end
				made = made + 1
			end
		end
		eq("the bench really filled the machine",
			select(1, CeroSecOS.usage(biggest)), CeroSecOS.MAX_NODES)
		biggest.floppy = CeroSecOS.newFloppy("FULL")
		biggest.floppy.fs = CeroSecOS.newDir("root", 755)
		for i = 1, CeroSecOS.FLOPPY_NODES - 1 do
			biggest.floppy.fs.children["f" .. i] = CeroSecOS.newFile("root", 644, "x")
		end
		eq("and the largest machine there is still boots",
			CeroSecOS.validate(biggest), true)
		eq("with the disk still ejectable",
			CeroSecOS.validateDisk(biggest.floppy, true), true)
	end

	-- None of it is paid for before it is refused: the field rules are asked of the
	-- table the game handed over, and the copy that walks every byte of a disk comes
	-- after them.
	local wide = {}
	for i = 1, 20000 do wide["k" .. i] = i end
	eq("a payload under a name of its own is refused without being copied",
		CeroSecOS.diskFromData({ v = 1, deep = wide }), nil)
	local onIt = CeroSecOS.newDir("root", 755)
	onIt.wide = wide
	eq("and one hung on a node, likewise",
		CeroSecOS.diskFromData({ v = 1, fs = onIt }), nil)

	-- The line the drive says on the glass carries the REASON and never a summary
	-- of it: two of the four things that keep a disk in the drive are not a ceiling,
	-- and a line naming the wrong trouble sends the player to a df that shows him
	-- nothing wrong.
	for _, reason in ipairs({ "floppy: disk full", "floppy: too many nodes",
			"floppy: unknown field", "floppy/notes.txt: unknown field",
			"floppy: bad type" }) do
		local line = CeroSecOS.fdKeptLine(reason)
		check("the drive's line fits the screen: " .. line, #line <= CeroSecOS.COLS)
		check("and carries " .. reason,
			string.find(line, string.match(reason, "([^:]+)$"), 1, true) ~= nil)
		check("under the drive's own name",
			string.sub(line, 1, #CeroSecOS.FD_KEPT) == CeroSecOS.FD_KEPT)
	end

	-- And what the machine makes for itself passes, every time: a formatted disk
	-- with the most a survivor can put on it.
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy("WORK")
	okAt(state, admin, "newfs /dev/fd0", nil)
	okAt(state, admin, "mount /dev/fd0 /mnt", {})
	local block = string.rep("y", CeroSecOS.MAX_FILE_BYTES)
	eq("the disk is filled to its ceiling",
		CeroSecOS.writeFile(state, CeroSecOS.rootSession(), "/mnt/big", block, false, nil),
		true)
	eq("and the slot still takes it",
		CeroSecOS.diskFromData(CeroSecOS.diskToData(state.floppy)) ~= nil, true)
end

--
-- 48. The telephone line (rung 6b)
--
-- The engine's half of a call: the number, the shape of one, the words the modem
-- and cu print, and everything cu can refuse before anybody has to ask the world
-- about a dial tone. Whether a call goes through is the server's and is proved in
-- tests/window_test.lua.
--

do
	-- THE SUBSCRIBER DIGITS come off the PREMISES KEY, which is what a machine
	-- carries on its own disk -- so they are answerable for a computer whose chunk
	-- nobody has loaded, and asking twice is asking the same question.
	local b1, b2 = CeroSecOS.buildingKey(400, 700)
	local n = CeroSecOS.phoneKey(b1, b2)
	check("a premises key has a number behind it", n ~= nil)
	eq("asked twice it is the same number", CeroSecOS.phoneKey(b1, b2), n)
	check("and it is one of the ten thousand there are",
		n >= 0 and n < CeroSecOS.PHONE_NUMBERS)
	eq("junk is no number", CeroSecOS.phoneKey("x", 1), nil)
	eq("nor is half a key", CeroSecOS.phoneKey(4), nil)
	eq("nor a byte that is not one", CeroSecOS.phoneKey(256, 0), nil)

	-- ONE LINE PER PREMISES. Every computer of one premises is on one line, so the
	-- machine at the next desk answers the same number -- which is what a house is,
	-- and what a shop is.
	eq("the machine at the next desk is on the same line",
		CeroSecOS.phoneKey(b1, b2), n)

	-- Two buildings a square apart have keys near each other, and their numbers
	-- must NOT be: a county where next door is 555-0418 is a county whose
	-- telephone numbers look made up. That is what the scatter is for.
	local e1, e2 = CeroSecOS.buildingKey(401, 700)
	local far = CeroSecOS.phoneKey(e1, e2)
	check("the building next door has a number nowhere near it (" .. n .. ", " ..
		far .. ")", math.abs(far - n) > 100)

	-- A PREMISES INSIDE A BUILDING -- a shop in a mall -- has two bytes of its own,
	-- hashed out of its outline. The corner alone is not enough: a zone often starts
	-- on the building's own corner, and a shop that shared the mall's key would be
	-- the very thing the rule is there to stop.
	local z1, z2 = CeroSecOS.premisesKey(12858, 1329, 17, 11)
	check("a zone has a premises key", z1 ~= nil)
	eq("asked twice it is the same one", select(2, CeroSecOS.premisesKey(12858, 1329, 17, 11)), z2)
	check("and both bytes are bytes", z1 >= 0 and z1 < 256 and z2 >= 0 and z2 < 256)
	eq("junk is no key", CeroSecOS.premisesKey("x", 1329, 17, 11), nil)
	eq("nor is a size that is not one", CeroSecOS.premisesKey(12858, 1329, 17), nil)
	-- The building whose corner it shares is a DIFFERENT premises.
	local c1, c2 = CeroSecOS.buildingKey(12858, 1329)
	check("a zone on the building's own corner is not the building",
		z1 ~= c1 or z2 ~= c2)
	-- And two zones on one corner with different outlines are two premises, which
	-- is the mall-wide zone and the shop inside it.
	local w1, w2 = CeroSecOS.premisesKey(12858, 1329, 120, 90)
	check("two zones on one corner are two premises", z1 ~= w1 or z2 ~= w2)
	-- Their NUMBERS differ too, which is the fact that matters: two shops in a mall
	-- are two telephone lines.
	check("and two lines", CeroSecOS.phoneKey(z1, z2) ~= CeroSecOS.phoneKey(w1, w2))
	check("neither of them the mall's own",
		CeroSecOS.phoneKey(z1, z2) ~= CeroSecOS.phoneKey(c1, c2))

	-- THE EXCHANGE is a fact about the TOWN: the region the premises corner falls
	-- in, so every subscriber of one town is on one central office.
	local ex = CeroSecOS.phoneExchange(400, 700)
	check("a corner has an exchange", ex ~= nil)
	check("and it could be a central office code (" .. tostring(ex) .. ")",
		ex >= CeroSecOS.PHONE_EXCHANGE_MIN and ex <= CeroSecOS.PHONE_EXCHANGE_MAX)
	eq("junk has none", CeroSecOS.phoneExchange("x", 700), nil)
	-- Every corner of one region is one office, edge included.
	local R = CeroSecOS.PHONE_REGION
	eq("the far corner of the same region is the same office",
		CeroSecOS.phoneExchange(R - 1, R - 1), CeroSecOS.phoneExchange(0, 0))
	check("and one tile over the edge is another one",
		CeroSecOS.phoneExchange(R, 0) ~= CeroSecOS.phoneExchange(0, 0))
	-- A tile apart across a region boundary is a DIFFERENT town, and the two
	-- offices must not be consecutive either.
	check("whose code is nowhere near it",
		math.abs(CeroSecOS.phoneExchange(R, 0) - CeroSecOS.phoneExchange(0, 0)) > 1)

	-- Written one way, and only one.
	eq("seven digits", CeroSecOS.phoneText(555, 417), "555-0417")
	eq("and the first number of all is padded", CeroSecOS.phoneText(555, 0), "555-0000")
	eq("the last one is not", CeroSecOS.phoneText(999, 9999), "999-9999")
	eq("the first office there is", CeroSecOS.phoneText(200, 1), "200-0001")
	eq("there is no ten thousandth", CeroSecOS.phoneText(555, 10000), nil)
	eq("nor a negative one", CeroSecOS.phoneText(555, -1), nil)
	eq("no office under two hundred", CeroSecOS.phoneText(199, 1), nil)
	eq("nor one over nine hundred and ninety nine", CeroSecOS.phoneText(1000, 1), nil)
	eq("nor one made of a string", CeroSecOS.phoneText("555", 417), nil)

	check("a number is a number", CeroSecOS.isPhoneNumber("555-0417"))
	check("and so is another town's", CeroSecOS.isPhoneNumber("263-1940"))
	check("three digits behind the hyphen are not",
		not CeroSecOS.isPhoneNumber("555-417"))
	check("five are not", not CeroSecOS.isPhoneNumber("555-04170"))
	check("an office code beginning with 1 is not",
		not CeroSecOS.isPhoneNumber("155-0417"))
	check("nor one beginning with 0", not CeroSecOS.isPhoneNumber("055-0417"))
	check("nor two digits of one", not CeroSecOS.isPhoneNumber("55-0417"))
	check("an address is not", not CeroSecOS.isPhoneNumber("10.4.17.2"))
	check("and neither is a name", not CeroSecOS.isPhoneNumber("gate"))

	-- The machine's own line comes off the same record the address does, so the
	-- two can never disagree about whether the computer is on a premises at all.
	local state = fresh()
	eq("a machine with no record has no line", CeroSecOS.phoneOf(state), nil)
	-- A RECORD WITH NO EXCHANGE IN IT is every machine of every save written
	-- before the line belonged to the premises: it has an address and no telephone,
	-- and it stays that way until the server sees its square again.
	check("a record with three numbers is written",
		CeroSecOS.setNetRecord(state, b1, b2, 3) ~= nil)
	eq("it has an address", CeroSecOS.address(state), CeroSecOS.addressText(b1, b2, 3))
	eq("and no line at all", CeroSecOS.phoneOf(state), nil)
	-- And then it has one, and it is the premises's.
	check("the exchange is written into it",
		CeroSecOS.setNetRecord(state, b1, b2, 3, ex) ~= nil)
	eq("and the line is the premises's", CeroSecOS.phoneOf(state),
		CeroSecOS.phoneText(ex, CeroSecOS.phoneKey(b1, b2)))
	-- The other machine on the premises is on the same line, which is what one line
	-- per premises means: the last byte of the address is not in the number.
	local other = fresh()
	CeroSecOS.setNetRecord(other, b1, b2, 9, ex)
	eq("the machine at the next desk answers the same number",
		CeroSecOS.phoneOf(other), CeroSecOS.phoneOf(state))
	-- And a machine in the shop next door is on another line.
	local shop = fresh()
	CeroSecOS.setNetRecord(shop, z1, z2, 1, ex)
	check("the shop next door is on another line",
		CeroSecOS.phoneOf(shop) ~= CeroSecOS.phoneOf(state))
	-- An exchange that is not one is a forged save and not a machine with half a
	-- record: the whole record goes, address included.
	eq("an office code nobody could have written is refused",
		CeroSecOS.setNetRecord(other, b1, b2, 9, 42), nil)
	other.net = { b1 = b1, b2 = b2, n = 9, ex = 42 }
	eq("and one found in a save is no record at all",
		CeroSecOS.netRecord(other), nil)
	-- And it is nowhere on the disk: the number belongs to the line.
	eq("there is no file holding it",
		CeroSecOS.systemNode(state, "/etc/phone"), nil)
end

-- WHAT THE PREMISES IS CALLED, which is a label on the record and nothing else:
-- no link reads it, nothing is keyed by it, and the firmware is the only thing
-- that prints it.
do
	local b1, b2 = CeroSecOS.premisesKey(12858, 1329, 17, 11)
	local ex = CeroSecOS.phoneExchange(12858, 1329)
	local state = fresh()

	-- A machine whose premises is the building it stands in has no name.
	CeroSecOS.setNetRecord(state, b1, b2, 1, ex)
	eq("a premises with no name has none", CeroSecOS.premisesName(state), nil)
	eq("and the BIOS line is the number alone", CeroSecOS.phoneLine(state),
		CeroSecOS.phoneOf(state))

	-- A shop the map named carries it, and the firmware says which line it is.
	CeroSecOS.setNetRecord(state, b1, b2, 1, ex, "CoffeeShop")
	eq("a named premises carries its name", CeroSecOS.premisesName(state), "CoffeeShop")
	eq("and the BIOS line says which line it is", CeroSecOS.phoneLine(state),
		CeroSecOS.phoneOf(state) .. " (CoffeeShop)")
	check("which fits the screen",
		#CeroSec.BOOT_PHONE + #CeroSecOS.phoneLine(state) <= CeroSecOS.COLS)

	-- A name too long for the line is DROPPED and not cut in half: the number is
	-- the half a survivor has to write down, and the machine still has its line.
	local long = string.rep("a", CeroSecOS.COLS - 4)
	CeroSecOS.setNetRecord(state, b1, b2, 1, ex, long)
	eq("a name that will not fit is left off the BIOS line",
		CeroSecOS.phoneLine(state), CeroSecOS.phoneOf(state))
	check("the line itself is untouched", CeroSecOS.phoneOf(state) ~= nil)

	-- A name that is not one is dropped when the record is written, and the record
	-- is still written: a premises is its two bytes and the name is a word.
	CeroSecOS.setNetRecord(state, b1, b2, 1, ex, "bad\1name")
	eq("a name with control bytes in it is dropped", CeroSecOS.premisesName(state), nil)
	check("and the machine still has its line", CeroSecOS.phoneOf(state) ~= nil)
	-- One found in a SAVE is a forged record, which is the rule every other field
	-- of it already runs on.
	state.net = { b1 = b1, b2 = b2, n = 1, ex = ex, pz = 42 }
	eq("a name that is not a string is no record at all",
		CeroSecOS.netRecord(state), nil)
end

-- How long a dial takes, and the one setting behind it: the modem's S7 register.
do
	eq("S7 is fifteen seconds", CeroSecOS.MODEM_S7, 15)
	eq("and that is what a call with nobody at the far end costs",
		CeroSecOS.RING_TIMEOUT_MS, CeroSecOS.MODEM_S7 * 1000)
	eq("an answered call is the handshake", CeroSecOS.ringMs(nil),
		CeroSecOS.RING_ANSWER_MS)
	eq("a busy line is the busy tone", CeroSecOS.ringMs(CeroSecOS.MODEM.busy),
		CeroSecOS.RING_BUSY_MS)
	eq("and nobody answering is S7", CeroSecOS.ringMs(CeroSecOS.MODEM.noCarrier),
		CeroSecOS.RING_TIMEOUT_MS)
	-- The two that are not a ring at all: there is nothing to wait through when the
	-- receiver says so the instant it is lifted.
	eq("no dial tone is heard at once",
		CeroSecOS.ringMs(CeroSecOS.MODEM.noDialtone), 0)
	eq("and a machine with no line never lifted one",
		CeroSecOS.ringMs(CeroSecOS.CU_NO_LINE), 0)
	check("the handshake is shorter than giving up",
		CeroSecOS.RING_ANSWER_MS < CeroSecOS.RING_TIMEOUT_MS)
	check("and a busy tone is the shortest of the three",
		CeroSecOS.RING_BUSY_MS < CeroSecOS.RING_ANSWER_MS)
end

-- The words. Four are the modem's and two are cu's, and the modem's are in
-- capitals because that is how they came out of one.
do
	eq("the modem reports the speed it got", CeroSecOS.MODEM.connect, "CONNECT 2400")
	eq("a line in use", CeroSecOS.MODEM.busy, "BUSY")
	eq("no exchange", CeroSecOS.MODEM.noDialtone, "NO DIALTONE")
	eq("and a line that went away", CeroSecOS.MODEM.noCarrier, "NO CARRIER")
	eq("cu says it is connected", CeroSecOS.CU_CONNECTED, "Connected.")
	eq("and that it is not any more", CeroSecOS.CU_DISCONNECTED, "Disconnected.")
	-- The speed in the modem's line is the speed the trickle is derived from, and
	-- not a second number that can drift away from it.
	check("the speed in the line is the line's speed",
		string.find(CeroSecOS.MODEM.connect,
			tostring(CeroSecOS.PHONE_BAUD), 1, true) ~= nil)

	-- cu's escape, as a shape. Alone on a line, blanks around it allowed, and
	-- nothing else on the line at all.
	check("~. is the escape", CeroSecOS.isCuEscape("~."))
	check("with blanks around it", CeroSecOS.isCuEscape("   ~.  "))
	check("a tab is a blank", CeroSecOS.isCuEscape("\t~."))
	check("~ alone is not", not CeroSecOS.isCuEscape("~"))
	check("nor is ~.x", not CeroSecOS.isCuEscape("~.x"))
	check("nor a ~. with a command behind it", not CeroSecOS.isCuEscape("~. exit"))
	check("nor one inside a line", not CeroSecOS.isCuEscape("echo ~."))
	check("nor BSD's other escapes, which this machine has not got",
		not CeroSecOS.isCuEscape("~!") and not CeroSecOS.isCuEscape("~%put f"))
	check("and junk is not", not CeroSecOS.isCuEscape(nil))
end

-- What cu refuses on its own, with no link layer to ask: a machine with no
-- telephone, a number that is not one, and a chain already at the ceiling.
do
	local state = fresh()
	local admin = open(state, "admin")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }

	-- A machine in no building. No net record, so no line -- and cu says so in its
	-- own shape, which is the one string on this rung that is not 4.4BSD's.
	local ok, lines = CeroSecOS.runArgs(state, admin, { "cu", "555-0417" }, nil, env)
	eq("cu on a machine with no line fails", ok, false)
	eq("in its own words", lines[1], "cu: no phone line")

	-- A record with no exchange in it is still a machine with no telephone: the
	-- address is the coax's and the line is the modem's, and an older save has only
	-- the first of the two.
	CeroSecOS.setNetRecord(state, 4, 17, 2)
	local oldSave, oldLines = CeroSecOS.runArgs(state, admin, { "cu", "555-0417" }, nil, env)
	eq("a record with no exchange has no line either", oldSave, false)
	eq("and cu says the same thing about it", oldLines[1], "cu: no phone line")

	-- Now it has one, and what is refused is the shape of the number.
	CeroSecOS.setNetRecord(state, 4, 17, 2, 555)
	local shapes = { "5550417", "555-417", "gate", "10.4.17.2", "555-04170" }
	for i = 1, #shapes do
		local o, l = CeroSecOS.runArgs(state, admin, { "cu", shapes[i] }, nil, env)
		eq("cu refuses " .. shapes[i], o, false)
		eq("with the usage line", l[1], "cu: usage: cu telno")
	end
	local o, l = CeroSecOS.runArgs(state, admin, { "cu" }, nil, env)
	eq("and cu with nothing after it is the usage line too", l[1],
		"cu: usage: cu telno")
	o, l = CeroSecOS.runArgs(state, admin, { "cu", "555-0417", "555-0418" }, nil, env)
	eq("and so are two numbers", l[1], "cu: usage: cu telno")

	-- A number in the right shape, on a machine with a line, from a session that
	-- is not down a chain: nothing is left for the engine to decide, so it hands
	-- the order over.
	local ran, out, control, data =
		CeroSecOS.runArgs(state, admin, { "cu", "555-0417" }, nil, env)
	eq("a dial is an order to whoever is running the machine", ran, true)
	eq("and it prints nothing itself", #out, 0)
	eq("the order is cu's", control, "cu")
	eq("carrying the number", data.tel, "555-0417")
	eq("the account that typed it", data.user, "admin")
	eq("who is asking", data.from, "admin")
	eq("and one hop further out than the session it came from", data.hops, 1)

	-- The hop ceiling, which a call pays exactly as an rlogin does -- and what it
	-- gets is the modem's word, because on a telephone it is the modem talking.
	local deep = open(state, "admin")
	deep.hops = CeroSecOS.HOP_MAX
	local d, dl = CeroSecOS.runArgs(state, deep, { "cu", "555-0417" }, nil, env)
	eq("a chain at the ceiling cannot dial", d, false)
	eq("and the line is busy as far as it is concerned", dl[1], "BUSY")
	-- One hop short of it still can.
	deep.hops = CeroSecOS.HOP_MAX - 1
	local u, _, uc = CeroSecOS.runArgs(state, deep, { "cu", "555-0417" }, nil, env)
	eq("one hop short of it dials", u, true)
	eq("and it is still cu's order", uc, "cu")
end


--
-- 43. The radio: the callsign, the frequency, the TNC's words and `call`
-- (rung 6c)
--
-- Everything about the radio that does not know there is a world: the shape of a
-- callsign, where one comes from, the file it lives in, how a frequency is
-- written, and what `call` decides before it asks anybody whether they can hear
-- it. The aerials, the ranges and the announcement are in tests/window_test.lua,
-- which has a world to put them in.
--

do
	-- The shape. A 1993 United States amateur callsign: K, N or W, an optional
	-- second letter, ONE digit, and two or three letters.
	local GOOD = { "K4ABC", "KD4AXR", "N4AB", "KD4AB", "W4ZZZ", "N0ABC" }
	for i = 1, #GOOD do
		check(GOOD[i] .. " is a callsign", CeroSecOS.isCallsign(GOOD[i]))
	end
	local BAD = {
		"kd4axr",      -- a callsign is sent and written in capitals
		"KD44AXR",     -- two digits is no district
		"4KDAXR",      -- the district is in the middle
		"AD4AXR",      -- A is not one of the three prefixes
		"K4A",         -- a one-letter suffix was special-event only
		"KD4AXRS",     -- and a four-letter one is nothing at all
        "KD4AXR-1",    -- an SSID: this machine is one station, which is SSID 0
		"K4ABC ",
		"",
	}
	for i = 1, #BAD do
		check("\"" .. BAD[i] .. "\" is not a callsign",
			not CeroSecOS.isCallsign(BAD[i]))
	end
	check("and neither is a number", not CeroSecOS.isCallsign(4))
	check("nor nothing at all", not CeroSecOS.isCallsign(nil))

	-- The derivation: deterministic, in the fourth district, one per machine.
	local a = CeroSecOS.callsignFor(4, 17, 3)
	check("a derived callsign is one", CeroSecOS.isCallsign(a))
	eq("and it is the same one every time", CeroSecOS.callsignFor(4, 17, 3), a)
	eq("Knox County is in the fourth district", string.sub(a, -4, -4), "4")
	eq("six characters, always", #a, 6)
	check("the next machine of the building is another station",
		CeroSecOS.callsignFor(4, 17, 4) ~= a)
	check("and so is the same machine number in another building",
		CeroSecOS.callsignFor(5, 17, 3) ~= a)
	-- The multipliers are not the telephone's, so a station's call is not a
	-- rearrangement of its number.
	do
		local seen, collisions = {}, 0
		for n = 1, 254 do
			local call = CeroSecOS.callsignFor(4, 17, n)
			check("every machine of a building gets a callsign",
				CeroSecOS.isCallsign(call))
			if seen[call] then collisions = collisions + 1 end
			seen[call] = true
		end
		check("and the 254 of one building barely collide (" .. collisions .. ")",
			collisions <= 2)
	end
	check("nothing is derived from a machine with no number",
		CeroSecOS.callsignFor(4, 17, 0) == nil)
	check("nor from one past the broadcast address",
		CeroSecOS.callsignFor(4, 17, 255) == nil)
	check("nor from a key that is not one", CeroSecOS.callsignFor(4, 300, 3) == nil)
	check("nor from nothing", CeroSecOS.callsignFor(nil, nil, nil) == nil)
end

-- The file, and what the machine reads out of it.
do
	local state = fresh()
	eq("a machine with no record has no callsign to derive",
		CeroSecOS.defaultCallsign(state), nil)
	eq("and no file to read one out of", CeroSecOS.callsignOf(state), nil)
	check("so nothing was seeded", CeroSecOS.ensureCallsign(state) == false)

	-- Given a record, which is what the server writes when it works out which
	-- building the computer is standing in.
	CeroSecOS.setNetRecord(state, 4, 17, 3)
	local want = CeroSecOS.callsignFor(4, 17, 3)
	eq("the record is what a callsign is derived from",
		CeroSecOS.defaultCallsign(state), want)
	check("and the file is seeded once", CeroSecOS.ensureCallsign(state) == true)
	eq("the machine reads it back", CeroSecOS.callsignOf(state), want)
	check("and it is not seeded twice", CeroSecOS.ensureCallsign(state) == false)

	local node = CeroSecOS.systemNode(state, CeroSecOS.CALLSIGN_PATH)
	eq("root's file", node.owner, "root")
	eq("at 644, so everybody may read it and only root may write it",
		node.mode, CeroSecOS.CALLSIGN_MODE)

	-- It is the PLAYER's file from then on. A word root wrote is the callsign,
	-- and anything after it on the line is ignored the way a note would be.
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.CALLSIGN_PATH,
		"W4ZZZ (Bob's set)\nnonsense", 100)
	eq("the first word is the callsign", CeroSecOS.callsignOf(state), "W4ZZZ")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.CALLSIGN_PATH,
		"   KD4AXR   ", 100)
	eq("and the blanks around it are not part of it",
		CeroSecOS.callsignOf(state), "KD4AXR")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.CALLSIGN_PATH,
		"not-a-call", 100)
	eq("a file holding something no station could be called is no callsign",
		CeroSecOS.callsignOf(state), nil)
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.CALLSIGN_PATH,
		"", 100)
	eq("and neither is an empty one", CeroSecOS.callsignOf(state), nil)
end

-- The frequency, as a station writes it: three decimals, always.
do
	eq("two metres", CeroSecOS.radioFreqText(144390), "144.390")
	eq("the bottom of the FM band", CeroSecOS.radioFreqText(88000), "88.000")
	eq("the top of it", CeroSecOS.radioFreqText(108000), "108.000")
	eq("the lowest channel a radio in this game has",
		CeroSecOS.radioFreqText(10000), "10.000")
	eq("and the highest", CeroSecOS.radioFreqText(500000), "500.000")
	eq("a single kilohertz keeps its two leading zeroes",
		CeroSecOS.radioFreqText(144001), "144.001")
	eq("and ten keeps one", CeroSecOS.radioFreqText(144010), "144.010")
	eq("zero is zero", CeroSecOS.radioFreqText(0), "0.000")
	eq("nothing is nothing", CeroSecOS.radioFreqText(nil), nil)
	eq("and so is a negative channel", CeroSecOS.radioFreqText(-1), nil)

	-- What `cat /dev/radio0` reads: the frequency and one of three words.
	eq("on", CeroSecOS.radioStateText(144390, true, true), "144.390 on")
	eq("off", CeroSecOS.radioStateText(144390, false, true), "144.390 off")
	eq("no power beats off, because it is the reason",
		CeroSecOS.radioStateText(144390, false, false), "144.390 no power")
	eq("and a set switched on with nothing behind it says the same",
		CeroSecOS.radioStateText(144390, true, false), "144.390 no power")
end

-- The node the world hands over, rendered.
do
	eq("the radio is a kind the core has words for -- none",
		next(CeroSecOS.DEV_VALUES.radio), nil)
	eq("read-only by nature, like the sensor",
		CeroSecOS.devModeFor("radio"), 440)
	local node = { type = "dev", owner = "root", group = "sudo", mode = 440,
		id = "radio0", kind = "radio", desc = "ham", side = "",
		pos = "2E 1N", state = "144.390 on" }
	local line = CeroSecOS.devLine(node)
	check("ls -l shows a character device nobody may write",
		string.find(line, "^cr%-%-r%-%-%-%-%-") ~= nil)
	check("named", string.find(line, "radio0", 1, true) ~= nil)
	check("for what it is", string.find(line, "ham", 1, true) ~= nil)
	check("with its frequency and its state",
		string.find(line, "144.390 on", 1, true) ~= nil)
	check("and it fits the screen", #line <= CeroSecOS.COLS)
end

-- The TNC's own words, and the two lines the machine says in its own name.
do
	eq("a connect names the station", CeroSecOS.TNC.connected .. "KD4AXR",
		"*** CONNECTED to KD4AXR")
	eq("a disconnect names nobody", CeroSecOS.TNC.disconnected, "*** DISCONNECTED")
	eq("silence has a name", CeroSecOS.TNC.retry, "*** retry count exceeded")
	eq("and so has a station that will not take a second link",
		CeroSecOS.TNC.busy, "*** BUSY")
	eq("the line the county reads carries no name on the end of it",
		CeroSecOS.TNC.onAir, "*** CONNECTED")
	eq("no radio", CeroSecOS.CALL_NO_RADIO, "call: no radio")
	eq("no licence", CeroSecOS.CALL_NO_CALLSIGN, "call: no callsign")
	eq("and the air runs at 1200 baud", CeroSecOS.RADIO_BAUD, 1200)
end

-- `call`, up to the point where the world has to be asked.
do
	local state = fresh()
	local admin = open(state, "admin")
	local env = { now = FIXED, nowMs = 1000, jobs = {} }

	-- No licence: refused before anything is transmitted, and in the machine's own
	-- name rather than the TNC's, because a TNC that has no MYCALL will not key the
	-- transmitter either.
	local none, nl = CeroSecOS.runArgs(state, admin, { "call", "KD4AXR" }, nil, env)
	eq("a station with no callsign cannot call", none, false)
	eq("and says so itself", nl[1], CeroSecOS.CALL_NO_CALLSIGN)

	CeroSecOS.setNetRecord(state, 4, 17, 3)
	CeroSecOS.ensureCallsign(state)
	local mine = CeroSecOS.callsignOf(state)

	local ran, out, control, data =
		CeroSecOS.runArgs(state, admin, { "call", "KD4AXR" }, nil, env)
	eq("a call is an order to whoever is running the machine", ran, true)
	eq("and it prints nothing itself", #out, 0)
	eq("the order is call's", control, "call")
	eq("carrying the callsign", data.call, "KD4AXR")
	eq("the account that typed it", data.user, "admin")
	eq("who is asking", data.from, "admin")
	eq("and one hop further out than the session it came from", data.hops, 1)

	-- The shape is judged here and never by the world.
	local bad, bl = CeroSecOS.runArgs(state, admin, { "call", "kd4axr" }, nil, env)
	eq("a callsign in lower case is a usage error", bad, false)
	eq("and the usage line is the one the manual carries", bl[1],
		"call: usage: " .. CeroSecOS.commandUsage("call"))
	local num = CeroSecOS.runArgs(state, admin, { "call", "555-0417" }, nil, env)
	eq("a telephone number is not a callsign", num, false)
	local bare = CeroSecOS.runArgs(state, admin, { "call" }, nil, env)
	eq("and nothing at all is not either", bare, false)
	local two = CeroSecOS.runArgs(state, admin, { "call", "KD4AXR", "KE4QWZ" }, nil, env)
	eq("nor two of them", two, false)

	-- Calling oneself: the TNC would hear its own connect request, which is
	-- silence as far as AX.25 is concerned.
	local self_, sl = CeroSecOS.runArgs(state, admin, { "call", mine }, nil, env)
	eq("a station cannot connect to itself", self_, false)
	eq("and what it gets is silence", sl[1], CeroSecOS.TNC.retry)

	-- The hop ceiling, which a link pays exactly as an rlogin and a call do -- and
	-- what it gets is the TNC's word, because on the air the TNC does the talking.
	local deep = open(state, "admin")
	deep.hops = CeroSecOS.HOP_MAX
	local d, dl = CeroSecOS.runArgs(state, deep, { "call", "KD4AXR" }, nil, env)
	eq("a chain at the ceiling cannot call", d, false)
	eq("and the TNC will not take it", dl[1], CeroSecOS.TNC.busy)
	deep.hops = CeroSecOS.HOP_MAX - 1
	local u, _, uc = CeroSecOS.runArgs(state, deep, { "call", "KD4AXR" }, nil, env)
	eq("one hop short of it calls", u, true)
	eq("and it is still call's order", uc, "call")
end

-- wtmp's host column carries all three origins now, and that is the bug this
-- rung found: a callsign is CAPITALS and the column used to accept a hostname or
-- a dash, so every radio session's record was refused in silence and `last` had
-- nothing to read.
do
	check("a hostname is an origin", CeroSecOS.isWtmpOrigin("gate"))
	check("so is a telephone number", CeroSecOS.isWtmpOrigin("555-0417"))
	check("and so is a callsign", CeroSecOS.isWtmpOrigin("KD4AXR"))
	check("a word that is none of the three is not",
		not CeroSecOS.isWtmpOrigin("Not A Host"))
	check("and neither is nothing", not CeroSecOS.isWtmpOrigin(nil))

	local state = fresh()
	local now = 741186720
	check("a login off the air is recorded",
		CeroSecOS.wtmpAppend(state, "in", "admin", "ttyp0", "KD4AXR", now))
	local text = CeroSecOS.systemNode(state, CeroSecOS.WTMP_PATH).data
	check("with the callsign in the host column",
		string.find(text, "KD4AXR", 1, true) ~= nil)
	local recs = CeroSecOS.parseWtmp(text)
	eq("and it reads back", #recs, 1)
	eq("naming the station that called", recs[#recs].host, "KD4AXR")
	check("the logout too",
		CeroSecOS.wtmpAppend(state, "out", "admin", "ttyp0", "KD4AXR", now + 60))
	eq("last prints it in the host column",
		string.find(CeroSecOS.lastLine(recs[1], nil), "KD4AXR", 1, true) ~= nil,
		true)
end

--
-- 49. The seven POSIX.2 and 4.4BSD tools this machine was missing (fidelity A)
--
-- more, find, tee, cut, tr, uptime and w. Every format below is pinned against
-- the real tool's, character for character: a change to one of them has to break
-- a line here, which is the only thing that keeps "copied from the real manual"
-- true a year from now.
--

-- 49z. The jobs belong to the MACHINE, and `help` and `man` say so.
--
-- This machine has one job book per computer: four is a computer's ceiling, the
-- book is the machine's, and `jobs` lists every background job on it whoever
-- started it. A real sh lists only what that shell started. The model is kept --
-- it is what makes a survivor able to `fg` what the last one left running -- and
-- what this pins is that the WORDS a player reads say so.
do
	local state = fresh()
	local admin = open(state, "admin")

	eq("man jobs says whose the jobs are", CeroSecOS.commandDesc("jobs"),
		"list the background jobs on this machine")
	eq("and ps says it is the wider one", CeroSecOS.commandDesc("ps"),
		"list every job on this machine, and its cpu")
	check("neither of them calls them the shell's",
		string.find(CeroSecOS.commandDesc("jobs"), "shell", 1, true) == nil
		and string.find(CeroSecOS.commandDesc("ps"), "shell", 1, true) == nil)

	-- And the words a player reads really are those: `help` prints the /bin file's
	-- contents, `man` prints the same string, and a word the shell IS has no file
	-- to read it out of -- which `jobs` is, so `man jobs` answers off the table.
	local lines = okAt(state, admin, "man jobs", {
		"jobs - list the background jobs on this machine",
		"usage: jobs",
		"a word of the shell itself: no file in " .. CeroSecOS.BIN_PATH,
	})
	check("and it fits the screen", #lines[1] <= CeroSecOS.COLS)
	-- ps is a FILE, so its line comes off the disk: the same string, because
	-- fillBin writes the description into it.
	eq("and /bin/ps holds its own description",
		state.fs.children.bin.children.ps.data,
		"list every job on this machine, and its cpu")
	okAt(state, admin, "man ps",
		{ "ps - list every job on this machine, and its cpu", "usage: ps" })

	-- The behaviour is unchanged, and this is what says so: a job one session
	-- started is on the OTHER session's `jobs`.
	local env = { now = FIXED, nowMs = 1, jobs = {} }
	local bob = addUser(state, "bob", "", "/home/bob")
	local bobS = open(state, "bob")
	local job = CeroSecOS.promptJob(state, admin, "sleep 30 &", {}, nil)
	check("admin asked for a background job", job ~= nil)
	env.jobs = { job }
	CeroSecOS.jobStep(state, job, env, 1000)
	-- The order the prompt hands back is what the MACHINE carries out; the bench
	-- stands one in the book by hand, which is what the scheduler does with it.
	local spawned = CeroSecOS.newJob({
		prog = { { k = "cmd", line = 1, words = { { { t = "lit", s = "sleep", q = true,
			bare = true } }, { { t = "lit", s = "30", q = true, bare = false } } } } },
		session = { user = "admin", cwd = "/home/admin" }, cmd = "sleep 30 &",
	})
	spawned.n = 1
	env.jobs = { spawned }
	local seen = okAt(state, bobS, "jobs", nil, env)
	eq("bob sees the job admin started", #seen, 1)
	check("by its slot and its line",
		string.find(seen[1], "[1]", 1, true) == 1
		and string.find(seen[1], "sleep 30 &", 1, true) ~= nil)
	local _ = bob
end

-- 49x. Tab and `man` on the seven new commands, by the usual route.
--
-- Neither of them is wired per command and neither may ever be: completion lists
-- the executables in /bin the account may run (CeroSecOS.complete), and `man`
-- prints the description out of the /bin FILE. So a command that has a
-- COMMAND_INFO entry and a file has both by construction -- and this is the bench
-- that says the seven really got them, which is the only way to tell the wiring
-- from the claim.
do
	local state = fresh()
	local admin = open(state, "admin")
	local NEW = { "cut", "find", "more", "tee", "tr", "uptime", "w" }

	for i = 1, #NEW do
		local name = NEW[i]
		-- The file, with the description in it: what `help` lists and `man` reads.
		local node = state.fs.children.bin.children[name]
		check("/bin/" .. name .. " is there", node ~= nil and node.type == "file")
		eq("and holds its own description", node.data, CeroSecOS.commandDesc(name))
		-- man, off that file and not off the table: `man` on this machine reads the
		-- disk, so a rewritten /bin/more says what the rewrite says.
		okAt(state, admin, "man " .. name, {
			name .. " - " .. CeroSecOS.commandDesc(name),
			"usage: " .. CeroSecOS.commandUsage(name),
		})
		-- Tab: the name is offered, and a prefix that only it answers to completes
		-- the whole way with a space behind it.
		local all = CeroSecOS.complete(state, admin, string.sub(name, 1, 1), 1)
		local offered = false
		for k = 1, #all.candidates do
			if all.candidates[k] == name then offered = true end
		end
		check("Tab offers " .. name, offered)
	end

	-- Two that are unique on their first letters, completed whole.
	local one = CeroSecOS.complete(state, admin, "upt", 3)
	eq("Tab finishes uptime", one.replacement, "uptime ")
	one = CeroSecOS.complete(state, admin, "fin", 3)
	eq("and find", one.replacement, "find ")
	-- And `t` is now three commands, so Tab answers with what they share and lists
	-- them -- which is ksh's answer and the one the window prints on a second Tab.
	local many = CeroSecOS.complete(state, admin, "te", 2)
	eq("two commands begin with te", #many.candidates, 2)
	eq("and Tab offers the prefix they share", many.replacement, "te")

	-- The names that are GONE are not offered either, because there is no file: the
	-- one list completion walks is the directory itself.
	local retired = CeroSecOS.complete(state, admin, "read", 4)
	for k = 1, #retired.candidates do
		check("Tab does not offer readlink", retired.candidates[k] ~= "readlink")
	end
	badAt(state, admin, "man readlink", "man: readlink: no manual entry")
	badAt(state, admin, "man hash", "man: hash: no manual entry")
end

-- 49y. The wheel pair, the passwd flag, and the names the top-up took away.
--
-- Three things the mutation check found nothing watching: that `usermod -G` keeps
-- the /etc/passwd flag in step with the group, that a `%group` line and a name in
-- /etc/sudoers are read FIRST-MATCH-WINS down the file, and that a machine off an
-- older save file really loses the four /bin files this build retired.
--
do
	local state = fresh()
	local rootSession = open(state, "root")
	local admin = open(state, "admin")

	-- 1. The flag on the line is written from the membership, in both directions.
	okAt(state, rootSession, "useradd bob", nil)
	eq("a new account is nobody's administrator", CeroSecOS.getUser(state, "bob").admin, false)
	okAt(state, rootSession, "usermod -G wheel bob", {})
	eq("putting him in wheel writes the flag", CeroSecOS.getUser(state, "bob").admin, true)
	okAt(state, admin, "id bob", { "uid=bob flag=admin groups=bob,wheel,sudo" })
	-- And out again. A `-G` that left the flag behind would leave a "#" on the
	-- prompt of an account that may no longer sudo.
	okAt(state, rootSession, "usermod -G users bob", {})
	eq("taking him out clears it", CeroSecOS.getUser(state, "bob").admin, false)
	okAt(state, admin, "id bob", { "uid=bob flag=user groups=bob,users" })
	check("and he may not sudo any more", CeroSecOS.sudoer(state, "bob") == nil)
	-- A list that does not move the membership does not rewrite the file either.
	local before = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data
	okAt(state, rootSession, "usermod -G users bob", {})
	eq("and a change that changes nothing writes nothing",
		CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH).data, before)

	-- 2. /etc/sudoers is read down the file and the FIRST line that matches wins,
	-- which is this file's rule everywhere else. `kate NOPASSWD` above `%wheel` is
	-- kate not being asked; the same two lines the other way round is kate asked
	-- like the rest of the group.
	okAt(state, rootSession, "useradd -G wheel kate", nil)
	put(state, rootSession, CeroSecOS.SUDOERS_PATH, "kate NOPASSWD\n%wheel")
	local entry = CeroSecOS.sudoer(state, "kate")
	check("kate is in the file", entry ~= nil)
	eq("by her own line, which is above the group's", entry.nopasswd, true)
	put(state, rootSession, CeroSecOS.SUDOERS_PATH, "%wheel\nkate NOPASSWD")
	eq("and the other way round the group's line is the one that answers",
		CeroSecOS.sudoer(state, "kate").nopasswd, false)
	-- A group line grants nobody who is not in the group.
	put(state, rootSession, CeroSecOS.SUDOERS_PATH, "%wheel")
	check("wheel is what grants it", CeroSecOS.sudoer(state, "kate") ~= nil)
	check("and bob, who is not in wheel, is not granted",
		CeroSecOS.sudoer(state, "bob") == nil)
	-- A "%" in front of a name that is not a group name at all is not a line.
	put(state, rootSession, CeroSecOS.SUDOERS_PATH, "%Wheel\n%")
	check("a bad group line is skipped like any other bad line",
		CeroSecOS.sudoer(state, "kate") == nil)
end

-- 3. The four names this build retired really go, and the rule they go by.
do
	-- A machine as the version before this one left it: the four old executables
	-- in /bin, exactly as they were shipped, and the number behind.
	local state = fresh()
	state.sysv = CeroSecOS.SYSTEM_VERSION - 1
	local bin = state.fs.children.bin
	local retired = {}
	for name, desc in pairs(CeroSecOS.RETIRED_BIN) do
		bin.children[name] = CeroSecOS.newFile("root", 755, desc)
		retired[#retired + 1] = name
	end
	table.sort(retired)
	check("there are names to retire (" .. #retired .. ")", #retired >= 4)
	-- One of them is a player's own work at that name: a file he wrote himself.
	-- Nothing here is allowed to be a deletion somebody did not ask for.
	bin.children.hash = CeroSecOS.newFile("admin", 755, "mine, not yours")
	-- And one is the shipped file with a mode somebody changed, which is still the
	-- shipped file and is still not ours to judge: a chmod is not a rewrite, so it
	-- STAYS, exactly as the shell-word deletion at version 8 left one.
	bin.children.restart = CeroSecOS.newFile("root", 700, CeroSecOS.RETIRED_BIN.restart)

	eq("the top-up has something to do", CeroSecOS.upgradeSystem(state), true)

	for i = 1, #retired do
		local name = retired[i]
		if name ~= "hash" and name ~= "restart" then
			eq("/bin/" .. name .. " is gone", bin.children[name], nil)
		end
	end
	eq("a file of the player's own at a retired name is left alone",
		bin.children.hash.data, "mine, not yours")
	eq("and so is the shipped one somebody chmod'd", bin.children.restart.mode, 700)

	-- And the shell agrees: a name with no file is a name that is not found.
	local admin = open(state, "admin")
	local ENV2 = { now = 0, nowMs = 1, jobs = {} }
	local GONE = { "adduser", "deluser", "gpasswd", "readlink", "write" }
	for i = 1, #GONE do
		badAt(state, admin, GONE[i] .. " x", GONE[i] .. ": command not found", ENV2)
	end
	-- The two the bench left standing on purpose are still FILES -- and still not
	-- commands, because the engine has nothing behind them: which is the honest
	-- answer for a file in /bin with no command behind it and has been since
	-- version 8.
	badAt(state, admin, "hash x", "hash: command not found", ENV2)
	-- The chmod'd one is 700 and root's, so an ordinary account does not get as far
	-- as finding out there is nothing behind it: a file it may not run is a file it
	-- may not run, which is the answer `chmod 600 /bin/ls` has always given.
	badAt(state, admin, "restart", "restart: permission denied", ENV2)
	badAt(state, open(state, "root"), "restart", "restart: command not found", ENV2)

	-- The new names are there in their place.
	local NEW = { "useradd", "userdel", "usermod", "mkpasswd" }
	for i = 1, #NEW do
		check("/bin/" .. NEW[i] .. " was seeded", bin.children[NEW[i]] ~= nil)
		eq("and describes itself", bin.children[NEW[i]].data,
			CeroSecOS.commandDesc(NEW[i]))
	end
	eq("and the machine validates", CeroSecOS.validate(state), true)
	eq("asked once and once only", CeroSecOS.upgradeSystem(state), false)
end

-- 49a. cut: the two forms, the list grammar, and the line with no delimiter.
do
	local state = fresh()
	local admin = open(state, "admin")
	put(state, admin, "/home/admin/rows", "one,two,three\nplain line\nalpha,beta")
	put(state, admin, "/home/admin/wide", "abcdefgh")

	okAt(state, admin, "cut -c 1 wide", { "a" })
	okAt(state, admin, "cut -c 1,3 wide", { "ac" })
	okAt(state, admin, "cut -c 2-4 wide", { "bcd" })
	-- "2-" is "from the second to the end", and "-3" is "up to the third": both
	-- are cut(1)'s own, and both are a range with one half missing.
	okAt(state, admin, "cut -c 6- wide", { "fgh" })
	okAt(state, admin, "cut -c -3 wide", { "abc" })
	okAt(state, admin, "cut -c 1,7-8 wide", { "agh" })
	-- A position past the end of the line is nothing, not a blank: cut takes
	-- what is there.
	okAt(state, admin, "cut -c 20 wide", { "" })

	-- -f with a delimiter of its own. The delimiter comes back BETWEEN the
	-- fields that were kept, which is what cut does and why `cut -d, -f1,3`
	-- answers "one,three" and not "onethree".
	okAt(state, admin, "cut -d , -f 1 rows", { "one", "plain line", "alpha" })
	okAt(state, admin, "cut -d , -f 1,3 rows", { "one,three", "plain line", "alpha" })
	okAt(state, admin, "cut -d , -f 2- rows", { "two,three", "plain line", "beta" })
	-- The line with NO delimiter in it comes through whole. POSIX says so: the
	-- line is not a record, so there is no field in it to take.
	okAt(state, admin, "cut -d , -f 2 rows", { "two", "plain line", "beta" })
	-- The default delimiter is a TAB, which is cut(1)'s own and the reason -d is
	-- a flag at all.
	put(state, admin, "/home/admin/tabs", "a\tb\tc")
	okAt(state, admin, "cut -f 2 tabs", { "b" })

	badAt(state, admin, "cut -c x wide", "cut: x: invalid list")
	badAt(state, admin, "cut -c 5-2 wide", "cut: 5-2: invalid list")
	badAt(state, admin, "cut -c 0 wide", "cut: 0: invalid list")
	badAt(state, admin, "cut -c 1,, wide", "cut: 1,,: invalid list")
	badAt(state, admin, "cut wide", "cut: usage: cut -c <list> | -d <delim> -f <list> [file]...")
	badAt(state, admin, "cut -c 1", "cut: usage: cut -c <list> | -d <delim> -f <list> [file]...")
	-- A delimiter is exactly one character, which is what every cut has taken.
	badAt(state, admin, "cut -d ,, -f 1 rows",
		"cut: usage: cut -c <list> | -d <delim> -f <list> [file]...")
	badAt(state, admin, "cut -q 1 wide", "cut: -q: unknown option")
	badAt(state, admin, "cut -c 1 nosuch", "cut: nosuch: no such file")

	-- And down a pipe, which is what cut is usually on the right of.
	okAt(state, admin, "cat rows | cut -d , -f 1", { "one", "plain line", "alpha" })
end

-- 49b. tr: the ranges, the short second set, and -d.
do
	local state = fresh()
	local admin = open(state, "admin")
	put(state, admin, "/home/admin/t", "Hello, World")

	okAt(state, admin, "cat t | tr a-z A-Z", { "HELLO, WORLD" })
	okAt(state, admin, "cat t | tr A-Z a-z", { "hello, world" })
	okAt(state, admin, "cat t | tr lo 01", { "He001, W1r0d" })
	-- The LAST character of set2 stands in for the rest of set1, which is tr's
	-- own rule and what makes `tr a-z x` a line of x's.
	okAt(state, admin, "cat t | tr a-z x", { "Hxxxx, Wxxxx" })
	okAt(state, admin, "cat t | tr -d lo", { "He, Wrd" })
	okAt(state, admin, "cat t | tr -d a-z", { "H, W" })

	badAt(state, admin, "cat t | tr z-a b", "tr: z-a: invalid set")
	badAt(state, admin, "cat t | tr a-z z-a", "tr: z-a: invalid set")
	-- tr reads its standard input and nothing else: there is no file operand on
	-- any tr, so one with no pipe on its left has nothing to read.
	badAt(state, admin, "tr a-z A-Z", "tr: usage: tr [-d] <set1> [<set2>]")
	badAt(state, admin, "cat t | tr a-z", "tr: usage: tr [-d] <set1> [<set2>]")
	badAt(state, admin, "cat t | tr -d a b", "tr: usage: tr [-d] <set1> [<set2>]")
	badAt(state, admin, "cat t | tr -x a b", "tr: -x: unknown option")
end

-- 49c. tee: the screen AND the files, and the first turn is what truncates.
do
	local state = fresh()
	local admin = open(state, "admin")
	put(state, admin, "/home/admin/src", "one\ntwo\nthree")
	put(state, admin, "/home/admin/old", "was here")

	okAt(state, admin, "cat src | tee copy", { "one", "two", "three" })
	eq("and the file holds exactly what went past",
		state.fs.children.home.children.admin.children.copy.data, "one\ntwo\nthree")
	-- Two files at once, which is the whole point of a T-piece.
	okAt(state, admin, "cat src | tee a b", { "one", "two", "three" })
	eq("both of them", state.fs.children.home.children.admin.children.a.data, "one\ntwo\nthree")
	eq("byte for byte", state.fs.children.home.children.admin.children.b.data, "one\ntwo\nthree")
	-- Without -a the file is REPLACED, exactly as ">" replaces.
	okAt(state, admin, "cat src | tee old", nil)
	eq("what was there is gone",
		state.fs.children.home.children.admin.children.old.data, "one\ntwo\nthree")
	-- With -a it is added to, exactly as ">>" adds.
	okAt(state, admin, "cat src | tee -a old", nil)
	eq("and the second copy is behind the first",
		state.fs.children.home.children.admin.children.old.data,
		"one\ntwo\nthree\none\ntwo\nthree")
	-- It is a filter and it passes the lines ON, which is what makes a tee in the
	-- middle of a pipeline worth writing.
	okAt(state, admin, "cat src | tee kept | wc -l", { "     3" })
	eq("and still wrote the file", state.fs.children.home.children.admin.children.kept.data,
		"one\ntwo\nthree")

	badAt(state, admin, "tee f", "tee: usage: tee [-a] <file>...")
	badAt(state, admin, "cat src | tee", "tee: usage: tee [-a] <file>...")
	badAt(state, admin, "cat src | tee -x f", "tee: -x: unknown option")
	badAt(state, admin, "cat src | tee /etc/motd", "tee: /etc/motd: permission denied")
end

-- 49d. find: the order, the two tests, and the glob.
do
	local state = fresh()
	local admin = open(state, "admin")
	okAt(state, admin, "mkdir tree", {})
	okAt(state, admin, "mkdir tree/inner", {})
	put(state, admin, "/home/admin/tree/top.txt", "a")
	put(state, admin, "/home/admin/tree/inner/deep.txt", "b")
	put(state, admin, "/home/admin/tree/inner/deep.log", "c")

	-- Depth-first and PRE-order: the directory before what is in it, which is
	-- find's own order and the reason `find tree` starts with "tree".
	okAt(state, admin, "find tree", {
		"tree", "tree/inner", "tree/inner/deep.log", "tree/inner/deep.txt", "tree/top.txt",
	})
	-- The path printed is the one that was TYPED, with the names walked into it.
	okAt(state, admin, "find /home/admin/tree -type d",
		{ "/home/admin/tree", "/home/admin/tree/inner" })
	okAt(state, admin, "find tree -type f",
		{ "tree/inner/deep.log", "tree/inner/deep.txt", "tree/top.txt" })
	-- -name matches the LAST component, which is what find has always matched.
	okAt(state, admin, "find tree -name '*.txt'",
		{ "tree/inner/deep.txt", "tree/top.txt" })
	okAt(state, admin, "find tree -name 'deep.*'",
		{ "tree/inner/deep.log", "tree/inner/deep.txt" })
	okAt(state, admin, "find tree -name inner", { "tree/inner" })
	-- Both tests, AND-ed.
	okAt(state, admin, "find tree -name '*.txt' -type f",
		{ "tree/inner/deep.txt", "tree/top.txt" })
	okAt(state, admin, "find tree -name '*.txt' -type d", {})
	-- -print is implied, and accepted, which is POSIX's own wording.
	okAt(state, admin, "find tree -type d -print", { "tree", "tree/inner" })
	-- More than one path, each walked in turn.
	okAt(state, admin, "find tree/top.txt tree/inner/deep.log",
		{ "tree/top.txt", "tree/inner/deep.log" })

	badAt(state, admin, "find", "find: usage: find <path>... [-name <glob>] [-type f|d]")
	badAt(state, admin, "find tree -type x",
		"find: usage: find <path>... [-name <glob>] [-type f|d]")
	badAt(state, admin, "find tree -name",
		"find: usage: find <path>... [-name <glob>] [-type f|d]")
	badAt(state, admin, "find tree -depth 2", "find: -depth: unknown option")
	badAt(state, admin, "find nosuch", "find: nosuch: no such file")

	-- A directory it may not read is NAMED and not entered, and the walk goes on.
	local shut = okAt(state, open(state, "root"), "find /home /root", nil)
	local saidRoot = false
	for i = 1, #shut do
		if shut[i] == "/root" then saidRoot = true end
	end
	check("root walks into /root", saidRoot)
	local refused = expect(state, admin, "find /root", false, nil)
	eq("and an ordinary account is refused, by name", refused[1], "/root")
	eq("with the reason on the line after", refused[2], "find: /root: permission denied")

	-- A link is a LEAF: find walks the tree it was given and does not follow one,
	-- which is find's own default and what keeps a loop of links finite.
	okAt(state, admin, "ln -s tree/inner shortcut", {})
	okAt(state, admin, "find shortcut", { "shortcut" })
end

-- 49e. The glob -name matches on, on its own.
do
	local M = CeroSecOS.globMatch
	check("a plain name is itself", M("notes", "notes"))
	check("and nothing else", not M("notes", "note"))
	check("* is any run", M("notes.txt", "*.txt"))
	check("including none at all", M(".txt", "*.txt"))
	check("* on its own is everything", M("anything", "*"))
	check("and matches the empty name", M("", "*"))
	check("two stars are one", M("a-b-c", "a*b*c"))
	check("? is exactly one", M("note", "not?"))
	check("and never none", not M("not", "not?"))
	check("a set holds one of its members", M("a.c", "?.[ch]"))
	check("a range in a set", M("file7", "file[0-9]"))
	check("and not outside it", not M("filex", "file[0-9]"))
	check("a negated set", M("filex", "file[!0-9]"))
	check("with a caret too", M("filex", "file[^0-9]"))
	check("and it really excludes", not M("file7", "file[!0-9]"))
	-- The three backtracking cases a naive matcher gets wrong.
	check("a star that has to give a character back", M("aaa", "*a"))
	check("a star before a longer tail", M("abcbcd", "*bcd"))
	check("and one that cannot be satisfied", not M("abc", "*d"))
	-- A "[" with nothing closing it is not a set and stands for itself, which is
	-- what sh does with one.
	check("an unclosed bracket is a literal", M("a[b", "a[b"))
	check("nothing matches junk", not M(nil, "*"))
	check("nor is junk a pattern", not M("a", nil))
end

-- 49f. uptime and w: the 4.4BSD lines, pinned.
do
	local state = fresh()
	local admin = open(state, "admin")
	-- Three o'clock in the afternoon, a machine up two days and four hours, two
	-- sessions on it, and the load the task's own example carries.
	local AT = CeroSecOS.timeFromParts(1993, 7, 8, 15, 14, 0)
	local env = {
		now = AT, nowMs = 90000000, jobs = {},
		up = 2 * 86400 + 4 * 3600 + 3 * 60,
		load = { 0.12, 0.08, 0.05 },
		net = { sessions = function()
			return {
				{ user = "admin", line = "console", at = AT - 42 * 60, busy = AT - 3 * 60 },
				{ user = "kate", line = "ttyp0", at = AT - 13 * 60, host = "gate" },
			}
		end },
	}

	okAt(state, admin, "uptime",
		{ " 3:14PM  up 2 days,  4:03,  2 users,  load 0.12 0.08 0.05" }, env)
	badAt(state, admin, "uptime -a", "uptime: usage: uptime", env)

	-- Every piece of that line on its own, so a change to one of them says which.
	eq("the clock is twelve-hour with no space before the half",
		CeroSecOS.clockText(AT), "3:14PM")
	eq("midnight is twelve and not nought",
		CeroSecOS.clockText(CeroSecOS.timeFromParts(1993, 7, 8, 0, 5, 0)), "12:05AM")
	eq("and noon is twelve too",
		CeroSecOS.clockText(CeroSecOS.timeFromParts(1993, 7, 8, 12, 0, 0)), "12:00PM")
	eq("one minute up", CeroSecOS.upText(60), " 1 min,")
	eq("two minutes up", CeroSecOS.upText(120), " 2 mins,")
	eq("under a minute is nought minutes and says so", CeroSecOS.upText(5), " 0 mins,")
	-- uptime(1)'s three shapes for the time, in its own order: h:mm when there
	-- are both, "N hrs" on the hour, "N mins" under one.
	eq("an exact hour is hrs and not h:mm", CeroSecOS.upText(3600), " 1 hr,")
	eq("and two of them are plural", CeroSecOS.upText(2 * 3600), " 2 hrs,")
	eq("an hour and minutes is h:mm", CeroSecOS.upText(3600 + 5 * 60), "  1:05,")
	eq("and the hour is two columns", CeroSecOS.upText(11 * 3600 + 5 * 60), " 11:05,")
	eq("one day is singular", CeroSecOS.upText(86400 + 60), " 1 day, 1 min,")
	eq("two are not", CeroSecOS.upText(2 * 86400 + 60), " 2 days, 1 min,")
	eq("and the days keep their own comma",
		CeroSecOS.upText(2 * 86400 + 4 * 3600 + 3 * 60), " 2 days,  4:03,")

	-- One session is "1 user," and not "1 users,".
	local one = {
		now = AT, nowMs = 90000000, jobs = {}, up = 90, load = { 0, 0, 0 },
		net = { sessions = function()
			return { { user = "admin", line = "console", at = AT } }
		end },
	}
	okAt(state, admin, "uptime",
		{ " 3:14PM  up 1 min,  1 user,  load 0.00 0.00 0.00" }, one)
	-- And a machine nobody has told anything: no clock, nothing up, nobody on it.
	local bare = exec(state, admin, "uptime", { jobs = {} })
	eq("a machine with no clock says so rather than inventing one",
		select(2, exec(state, admin, "uptime", { jobs = {} }))[1],
		" ??:??  up 0 mins,  0 users,  load 0.00 0.00 0.00")
	check("and it fits the screen", bare ~= nil)

	-- The widest line this can make is exactly the screen: a machine up
	-- three-digit days with every session on it and every job runnable.
	local worst = {
		now = CeroSecOS.timeFromParts(1993, 7, 8, 12, 59, 0), nowMs = 1, jobs = {},
		up = 365 * 86400 + 23 * 3600 + 59 * 60, load = { 4, 4, 4 },
		net = { sessions = function()
			local rows = {}
			for i = 1, CeroSecOS.PTY_MAX + 1 do
				rows[i] = { user = "admin", line = "ttyp" .. i, at = 1 }
			end
			return rows
		end },
	}
	local wide = select(2, exec(state, admin, "uptime", worst))
	eq("the worst uptime line is one line", #wide, 1)
	eq("and it fits the sixty columns exactly", #wide[1] <= CeroSecOS.COLS, true)

	-- w: uptime's line, the header, and a row a session.
	local rows = okAt(state, admin, "w", nil, env)
	eq("w opens with uptime's own line", rows[1],
		" 3:14PM  up 2 days,  4:03,  2 users,  load 0.12 0.08 0.05")
	eq("then 4.4BSD's header", rows[2], "USER     TTY      FROM        LOGIN@ IDLE  WHAT")
	-- The console: no host, so a dash, and the line that is running in WHAT.
	eq("the console's row", rows[3], "admin    console  -           2:32PM 00:03 w")
	-- A session in from the wire wears the machine it came from, and has nothing
	-- running: a dash.
	-- kate has no activity stamp, so her IDLE is measured from her LOGIN -- the
	-- honest floor, and the thirteen minutes she has been on the machine.
	eq("and a pty's", rows[4], "kate     ttyp0    gate        3:01PM 00:13 -")
	eq("four lines and no more", #rows, 4)
	for i = 1, #rows do
		eq("w line " .. i .. " fits the screen", #rows[i] <= CeroSecOS.COLS, true)
	end
	badAt(state, admin, "w x", "w: usage: w", env)

	-- WHAT is the PROMPT's own job and nothing else. A `&` in the background and a
	-- crontab line are the machine's work and not what that session is doing, which
	-- is the rule `jobs` and `ps` already tell apart -- and a `w` that named a
	-- background job in the WHAT column would say a survivor is busy when he is
	-- standing at his prompt.
	do
		local function job(cmd, opts)
			local one = CeroSecOS.newJob({
				prog = {}, session = { user = "admin", cwd = "/home/admin" }, cmd = cmd,
				bg = opts.bg,
			})
			one.mailTo = opts.mailTo
			return one
		end
		-- Three jobs that are NOT this session's work, in front of the `w` the bench
		-- is about to type: a `&` in the background, a crontab line, and the job the
		-- MACHINE made for a `sleep` -- which is the one that matters, because it is
		-- neither of the other two and is still not what a survivor is doing.
		local busy = {
			now = AT, nowMs = 1, up = 60, load = { 0, 0, 0 },
			jobs = {
				job("sleep 300 &", { bg = true }),
				job("/home/admin/nightly.sh", { mailTo = "admin" }),
				job("sleep 5", {}),
			},
			net = { sessions = function()
				return { { user = "admin", line = "console", at = AT - 60, busy = AT - 60 } }
			end },
		}
		-- `exec` puts the prompt's own job on the book after those three, exactly as
		-- the machine does, so the walk has to pick the LAST kind and not the first.
		local rows = okAt(state, admin, "w", nil, busy)
		eq("WHAT is the line this session typed and none of the machine's own work",
			rows[3], "admin    console  -           3:13PM 00:01 w")
	end

	-- The load averages' own arithmetic, which every bench above hands in ready
	-- made. This is the one that exercises CeroSecOS.loadSample: what the scheduler
	-- calls once a pass, on the job book that IS the run queue.
	do
		local book = { list = {} }
		-- The first sample starts AT the run queue and does not climb to it from
		-- nought: a machine switched on with four jobs on it really is loaded, and an
		-- average that began at zero would say it was idle for a minute.
		for i = 1, 3 do
			book.list[i] = CeroSecOS.newJob({ prog = {}, cmd = "job " .. i })
		end
		eq("the first sample is taken", CeroSecOS.loadSample(book, 100000), true)
		eq("and it starts at the run queue", book.load[1], 3)
		eq("on all three windows", book.load[3], 3)
		-- Sampled no oftener than every five seconds, which is the interval every
		-- Unix has sampled its run queue at.
		eq("a second sample inside the interval is not taken",
			CeroSecOS.loadSample(book, 100000 + CeroSecOS.LOAD_SAMPLE_MS - 1), false)
		eq("and it moved nothing", book.load[1], 3)

		-- The machine goes idle. The one-minute average falls fast and the
		-- fifteen-minute one barely moves, which is the whole point of three windows.
		for i = 1, #book.list do CeroSecOS.killJob(book.list[i], nil) end
		local at = 100000
		for _ = 1, 12 do
			at = at + CeroSecOS.LOAD_SAMPLE_MS
			CeroSecOS.loadSample(book, at)
		end
		check("a minute idle takes most of the one-minute average (" ..
			string.format("%.3f", book.load[1]) .. ")", book.load[1] < 1.5)
		check("and leaves the fifteen-minute one nearly where it was (" ..
			string.format("%.3f", book.load[3]) .. ")", book.load[3] > 2.5)
		check("the short window really is the faster of the two",
			book.load[1] < book.load[2] and book.load[2] < book.load[3])
		-- It decays to nothing and never below it, given enough of the window it is
		-- an average over: two thousand samples is a couple of hours, which is many
		-- times the fifteen minutes the slowest of the three is named for.
		for _ = 1, 2000 do
			at = at + CeroSecOS.LOAD_SAMPLE_MS
			CeroSecOS.loadSample(book, at)
		end
		check("and it ends at nothing rather than below it (" ..
			string.format("%.4f", book.load[3]) .. ")",
			book.load[3] >= 0 and book.load[3] < 0.01)

		-- A clock that went backwards -- a reload, a server restart -- is a sample
		-- interval nobody can use: it starts again rather than dividing by a
		-- negative.
		local before = book.load[1]
		eq("a backwards clock takes no sample", CeroSecOS.loadSample(book, 1), false)
		eq("and moved nothing", book.load[1], before)
		eq("junk takes none either", CeroSecOS.loadSample(nil, 1), false)
		eq("nor does a clock that is not one", CeroSecOS.loadSample(book, "soon"), false)
	end

	-- A session the machine has no activity stamp for -- one that came back from a
	-- save file -- is idle since it LOGGED IN, which is the honest floor.
	local cold = {
		now = AT, nowMs = 1, jobs = {}, up = 60, load = { 0, 0, 0 },
		net = { sessions = function()
			return { { user = "admin", line = "console", at = AT - 90 * 60 } }
		end },
	}
	local coldRows = okAt(state, admin, "w", nil, cold)
	-- And WHAT is "w", because `w` is what that session is running: a real one
	-- names itself in its own listing too.
	eq("idle from the login when there is no keystroke to measure from",
		coldRows[3], "admin    console  -           1:44PM 01:30 w")
end

-- 49g. more: the screenful, the prompt, the three keys, and where it does NOT page.
do
	local state = fresh()
	local admin = open(state, "admin")
	local body = {}
	for i = 1, 45 do body[#body + 1] = "line " .. i end
	put(state, admin, "/home/admin/big", table.concat(body, "\n"))

	-- A screenful is the screen less the row the prompt stands on, which is
	-- more(1)'s own arithmetic.
	eq("nineteen rows to a screenful", CeroSecOS.MORE_ROWS, CeroSecOS.ROWS - 1)

	local first = run(state, admin, "more big")
	eq("it asks", first.control, "prompt")
	eq("nineteen lines and no more", #first.lines, CeroSecOS.MORE_ROWS)
	eq("the first of them", first.lines[1], "line 1")
	eq("and the last", first.lines[CeroSecOS.MORE_ROWS], "line 19")
	eq("the prompt is more(1)'s own, per cent and all", first.data.text, "--More--(42%)")
	eq("and nothing is masked", first.data.mask, false)

	-- Space: the next screenful. The per cent is of the WHOLE file, so it climbs
	-- once from nought to the end.
	local second = answer(state, admin, first.data.cont, " ")
	eq("another nineteen", #second.lines, CeroSecOS.MORE_ROWS)
	eq("carrying on where it stopped", second.lines[1], "line 20")
	eq("and the per cent has climbed", second.data.text, "--More--(84%)")

	-- Return: exactly one more line.
	local third = answer(state, admin, second.data.cont, "")
	eq("one line", #third.lines, 1)
	eq("the next one", third.lines[1], "line 39")
	eq("and it still asks", third.data.text, "--More--(86%)")

	-- q: it stops, with nothing more printed and nothing wrong.
	local quit = answer(state, admin, third.data.cont, "q")
	eq("q prints nothing", #quit.lines, 0)
	eq("asks nothing", quit.control, nil)
	eq("and is not a failure", quit.ok, true)

	-- A key more has no meaning for is a screenful, which is what more does
	-- with one.
	local other = answer(state, admin, first.data.cont, "z")
	eq("an unknown key is a screenful", #other.lines, CeroSecOS.MORE_ROWS)

	-- A file that fits asks nothing at all: a pager that put a question up after
	-- the last line would be a pager you had to dismiss.
	put(state, admin, "/home/admin/short", "one\ntwo")
	okAt(state, admin, "more short", { "one", "two" })
	badAt(state, admin, "more nosuch", "more: nosuch: no such file")
	badAt(state, admin, "more", "more: usage: more [file]...")

	-- Two files run together, which is what more does with several -- minus the
	-- banner between them, because that banner is two rows of twenty.
	put(state, admin, "/home/admin/two", "three")
	okAt(state, admin, "more short two", { "one", "two", "three" })

	-- A screen with NOBODY in front of it -- a `&` job, a crontab line -- is the
	-- other case, and it is not the same one: the output goes to a glass and no key
	-- will ever be pressed at it. Refused before a single line is printed, because
	-- a pager that put nineteen rows onto that glass and then said so would have
	-- paged nothing.
	--
	-- Handed straight to runArgs with the `keys` half of what the shell knows set
	-- false, which is what CeroSecOSVM.jobHasKeyboard answers for such a job. This
	-- bench exists because a mutation check found the refusal UNREACHABLE: runArgs
	-- built the table it hands a command out of `path` and `tty` alone and dropped
	-- `keys` on the floor, so `more` never saw it and no bench could tell.
	do
		local bgOk, bgLines = CeroSecOS.runArgs(state, admin, { "more", "big" }, nil, ENV,
			nil, { path = CeroSecOS.DEFAULT_PATH, tty = true, keys = false })
		eq("a pager with nobody at the keyboard is refused", bgOk, false)
		eq("in its own name", bgLines[1], "more: not a terminal")
		eq("and nothing at all was printed first", #bgLines, 1)
		-- And with a keyboard it pages, off the very same door: what changed is the
		-- one flag.
		local fgOk, _, fgControl = CeroSecOS.runArgs(state, admin, { "more", "big" }, nil,
			ENV, nil, { path = CeroSecOS.DEFAULT_PATH, tty = true, keys = true })
		eq("and with one it pages", fgOk, true)
		eq("which is a question", fgControl, "prompt")
	end

	-- NOT a screen: copy through with no paging at all, which is more(1)'s own
	-- answer and what keeps a pager composable.
	okAt(state, admin, "more big > out", {})
	eq("everything went into the file",
		#CeroSecOS.splitLines(state.fs.children.home.children.admin.children.out.data), 45)
	okAt(state, admin, "echo hi | more | wc -l", { "     1" })
	okAt(state, admin, "x=$(more short); echo $x", { "one two" })
end

-- 49h. more in a pipe, which is where a survivor really types it.
do
	local state = fresh()
	local admin = open(state, "admin")
	local body = {}
	for i = 1, 30 do body[#body + 1] = "row " .. i end
	put(state, admin, "/home/admin/rows", table.concat(body, "\n"))

	-- Driven as the MACHINE drives it, and it has to be: a pipeline's question is
	-- the pipeline's, the continuation lives on the stage that asked, and the
	-- answer goes back through CeroSecOS.jobInput. A bench that called
	-- CeroSecOS.continue with what `exec` handed back would be answering a token
	-- that is not there -- which is the whole difference between a command that
	-- asks and a stage that does.
	local job = CeroSecOS.promptJob(state, admin, "cat rows | more", {}, nil)
	check("the pipeline became a job", job ~= nil)
	local env = { now = FIXED, nowMs = 1, jobs = { job } }
	local prompts, lines = {}, {}
	local keys = { " ", nil }
	local given = 0
	for turn = 1, 200 do
		CeroSecOS.jobStep(state, job, env, 1000)
		for i = 1, #job.out do lines[#lines + 1] = job.out[i] end
		job.out = {}
		if CeroSecOS.jobIsOver(job) then break end
		if job.state == "waiting" and job.ask ~= nil then
			prompts[#prompts + 1] = job.ask.text
			given = given + 1
			if keys[given] == nil then break end
			check("the answer was taken", CeroSecOS.jobInput(state, job, keys[given], env))
		elseif job.state == "waiting" or job.state == "sleeping" then
			break
		end
	end
	eq("the last stage of a pipeline pages, and asks once", #prompts, 1)
	eq("and it knew how long the whole thing was", prompts[1], "--More--(63%)")
	eq("every row came out, and no row twice", #lines, 30)
	eq("the first", lines[1], "row 1")
	eq("the nineteenth is the last of the screenful", lines[19], "row 19")
	eq("the twentieth is the first of the next", lines[20], "row 20")
	eq("and the last is the last", lines[30], "row 30")
	eq("the pipeline is over", CeroSecOS.jobIsOver(job), true)

	-- A pipe longer than a pager may hold. The ceiling is the pipe's own, which
	-- is what sort and tail already meet, and it is the ceiling the token has to
	-- meet too -- what is not shown yet is carried in it.
	local flood = {}
	for i = 1, CeroSecOS.PIPE_LINES + 5 do flood[#flood + 1] = "x" end
	put(state, admin, "/home/admin/flood", table.concat(flood, "\n"))
	badAt(state, admin, "cat flood | more", "more: input too large")
end

print("os_test: " .. count .. " assertions passed")
