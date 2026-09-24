-- A file's last line carries its newline: the storage rule, and every consumer
-- of it held to what a real Unix answers. Run from the repo root:
--   lua5.1 tests/newline_test.lua
--
-- Until STATE_VERSION 3 a stored file was its lines joined by "\n" with nothing
-- after the last one, a declared deviation. Now "\n" TERMINATES a line: `echo a`
-- stores two bytes and `printf a` one (POSIX echo writes its operands "followed
-- by a <newline>"; printf writes only what its format asks for), wc -l counts the
-- newline bytes (POSIX wc), and a command that copies bytes -- cat, head, tail,
-- tee, cp -- carries a missing final newline through instead of inventing one.
-- The migration of old saves is tests/migrate_test.lua's; the harness below is
-- os_test's own, copied, so that what a line typed at the prompt does is the
-- engine's and nothing else.

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
	local done, reason = CeroSecOS.setData(state, CeroSecOS.rootSession(),
		CeroSecOS.PASSWD_PATH, CeroSecOS.appendLine(node.data, CeroSecOS.passwdLine(user)))
	if done == nil then error("cannot add " .. name .. ": " .. tostring(reason), 2) end
	-- And the HOME, which `useradd` makes and which an account without one is not a
	-- machine anybody could have: a line in /etc/passwd naming a directory that is
	-- not there is a forged file, and the commands that write in a home -- `mail`
	-- keeping read mail in ~/mbox is the one that found this -- would be benched
	-- against a machine no useradd ever built.
	if type(user.home) == "string" and user.home ~= ""
			and CeroSecOS.getNode(state, CeroSecOS.rootSession(), user.home) == nil then
		local made = CeroSecOS.createNode(state, CeroSecOS.rootSession(), user.home,
			CeroSecOS.newDir(name, 750))
		if made == nil then error("cannot make a home for " .. name, 2) end
	end
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
	-- The shell's functions, the way the console keeps them (CeroSec.newConsole): a
	-- table of its own, by reference, so a definition on one line is there on the
	-- next. Without it every bench below would be a shell that had forgotten.
	if type(session) == "table" and session.shfuncs == nil then session.shfuncs = {} end
	local vars, funcs = nil, nil
	if type(session) == "table" then
		vars = session.shvars
		funcs = session.shfuncs
	end
	local job, refusal = CeroSecOS.promptJob(state, session, line, vars,
		type(session) == "table" and session.status or nil, nil, nil, funcs)
	if job == nil then return false, CeroSecOS.fit({ refusal }) end

	-- The machine's job book, if the caller keeps one: the prompt's own job is
	-- on it while it runs, exactly as it is on a real machine, which is what
	-- `ps` sees and `jobs` deliberately does not.
	local book = env.jobs
	if book ~= nil then book[#book + 1] = job end

	local out = {}
	-- The orders the line gave that the MACHINE carries out while the job runs on
	-- past them -- a `clear`, a `wall`. They are queued on the job and the
	-- scheduler is what empties the queue (SCeroSecJobs.runMachine); here the
	-- scheduler is this loop, and emptying it is not optional: a job with an order
	-- still on it does not step again, which is the whole point of the queue.
	local orders = {}
	local turns = 0
	while not CeroSecOS.jobIsOver(job) and turns < 500 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, env, 1000)
		if job.orders ~= nil then
			for k = 1, #job.orders do orders[#orders + 1] = job.orders[k] end
			job.orders = nil
		end
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
	if job.orders ~= nil then
		for k = 1, #job.orders do orders[#orders + 1] = job.orders[k] end
		job.orders = nil
	end

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
	-- An order for the machine that the job went on past. The FIRST of them is
	-- the one the line gave -- a bench types one line at a time -- and it is
	-- answered here under the same name it used to be answered under, back when
	-- such an order was the last word of the job that gave it.
	if control == nil and orders[1] ~= nil then
		control = orders[1].control
		data = orders[1].data
	end
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
	return job.status == 0, CeroSecOS.fit(out), control, data, job, orders
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

local function data(state, path)
	local node = CeroSecOS.getNode(state, CeroSecOS.rootSession(), path)
	if node == nil then return nil end
	return node.data
end

--
-- 1. What is stored
--
do
	local state = fresh()
	local admin = open(state, "admin")
	ok(state, admin, "echo a > f", {})
	eq("echo leaves its newline behind", data(state, "/home/admin/f"), "a\n")
	ok(state, admin, "wc -c f", { "       2 f" })
	ok(state, admin, "wc -l f", { "       1 f" })
	ok(state, admin, "printf a > g", {})
	eq("printf leaves only what its format asked for", data(state, "/home/admin/g"), "a")
	ok(state, admin, "wc -c g", { "       1 g" })
	-- wc -l counts newlines, not lines: a last line with none is not counted.
	ok(state, admin, "wc -l g", { "       0 g" })
	ok(state, admin, "wc g", { "       0       1       1 g" })
	-- >> writes after the last byte, whatever it is.
	ok(state, admin, "echo -n x > h; echo y >> h", {})
	eq(">> glues onto an open last line", data(state, "/home/admin/h"), "xy\n")
	ok(state, admin, "cat h", { "xy" })
	ok(state, admin, "echo one > two; echo two >> two", {})
	eq("and after a closed one starts a line", data(state, "/home/admin/two"), "one\ntwo\n")
	ok(state, admin, "wc -l two", { "       2 two" })
	-- An empty file has no line to end.
	ok(state, admin, "printf '' > e", {})
	eq("an empty write is an empty file", data(state, "/home/admin/e"), "")
	-- The builtin's 2> is a file like any other: its lines end.
	exec(state, admin, "cat /nosuch 2> err")
	eq("an error line in a file ends too", data(state, "/home/admin/err"),
		"cat: /nosuch: No such file or directory\n")
end

--
-- 2. What the screen shows
--
do
	local state = fresh()
	local admin = open(state, "admin")
	put(state, admin, "/home/admin/g", "a")
	put(state, admin, "/home/admin/f", "a\n")
	-- A pipeline ends an unfinished last line where the pipe did: the next
	-- command's output follows it on the same line, as on a real terminal.
	ok(state, admin, "printf a | cat; echo b", { "ab" })
	ok(state, admin, "cat g; echo b", { "ab" })
	ok(state, admin, "cat f; echo b", { "a", "b" })
	-- cat copies bytes, so an open file runs straight into the next one.
	ok(state, admin, "cat g f", { "aa" })
	ok(state, admin, "cat f g", { "a", "a" })
	ok(state, admin, "cat g g g; echo", { "aaa" })
	-- And the bytes of one command run into the next one's the same way.
	ok(state, admin, "printf a; cat f", { "aa" })
	ok(state, admin, "printf a; cat f f", { "aa", "a" })
	ok(state, admin, "echo 2 | cat g - f", { "a2", "a" })
	ok(state, admin, "head -n 1 g; echo b", { "ab" })
	ok(state, admin, "tail -n 1 g; echo b", { "ab" })
	ok(state, admin, "cat g | head -n 1; echo b", { "ab" })
	ok(state, admin, "cat g | tail -n 1; echo b", { "ab" })
	-- A filter that writes LINES terminates each one, the last included.
	ok(state, admin, "grep a g; echo b", { "a", "b" })
	ok(state, admin, "sort g; echo b", { "a", "b" })
end

--
-- 3. What goes on down a pipe and into a file
--
do
	local state = fresh()
	local admin = open(state, "admin")
	put(state, admin, "/home/admin/g", "a")
	put(state, admin, "/home/admin/f", "a\n")
	local cases = {
		{ "printf a | cat > o", "a" },
		{ "cat g > o", "a" },
		{ "cat f g > o", "a\na" },
		{ "cat g f > o", "aa\n" },
		{ "printf a | tee o", "a" },
		{ "echo a | tee o", "a\n" },
		{ "head -n 1 g > o", "a" },
		{ "tail -n 1 g > o", "a" },
		{ "cat g | head -n 1 > o", "a" },
		{ "cat g | tail -n 1 > o", "a" },
		{ "printf 'b\\na' > u; sort u > o", "a\nb\n" },
		{ "grep a g > o", "a\n" },
		{ "uniq g > o", "a\n" },
		{ "cut -c 1 g > o", "a\n" },
		{ "cat g | grep a > o", "a\n" },
		{ "cp g o", "a" },
		{ "cp f o", "a\n" },
		{ "x=$(cat f); echo \"$x\" > o", "a\n" },
		{ "printf a > o; cat f >> o", "aa\n" },
	}
	for i = 1, #cases do
		local line, want = cases[i][1], cases[i][2]
		exec(state, admin, "rm -f o")
		exec(state, admin, line)
		eq("`" .. line .. "` stores", data(state, "/home/admin/o"), want)
	end
	ok(state, admin, "printf a | wc -c", { "       1" })
	ok(state, admin, "echo a | wc -c", { "       2" })
	ok(state, admin, "cat g | wc -l", { "       0" })
	ok(state, admin, "cat f | wc -l", { "       1" })
	-- `wc f` and `cat f | wc` agree, open or closed.
	ok(state, admin, "wc g", { "       0       1       1 g" })
	ok(state, admin, "cat g | wc", { "       0       1       1" })
	ok(state, admin, "wc f", { "       1       1       2 f" })
	ok(state, admin, "cat f | wc", { "       1       1       2" })
end

--
-- 4. A script, a crontab, the editor's buffer, a mailbox
--
do
	local state = fresh()
	local admin = open(state, "admin")
	-- A script is read as lines, open last line or not: an old save's scripts
	-- (no final newline) run as they did.
	put(state, admin, "/home/admin/new.sh", "echo one\necho two\n")
	put(state, admin, "/home/admin/old.sh", "echo one\necho two")
	ok(state, admin, "sh new.sh", { "one", "two" })
	ok(state, admin, "sh old.sh", { "one", "two" })

	-- crontab(1) takes a file of lines ending in newlines.
	eq("a crontab of terminated lines parses",
		CeroSecOS.checkCrontab("/var/spool/cron/admin", "30 * * * * echo hi\n"), nil)
	eq("and an old open one still does",
		CeroSecOS.checkCrontab("/var/spool/cron/admin", "30 * * * * echo hi"), nil)

	-- The editor edits lines: the file's final newline is not a line of the
	-- buffer, and the save puts it back, so open-then-save is the same bytes.
	for _, bytes in ipairs({ "one\ntwo\n", "one\n\n", "" }) do
		local buffer = CeroSecOS.bufferOf(bytes)
		eq("the buffer of " .. string.format("%q", bytes) .. " saves back byte for byte",
			CeroSecOS.bufferBytes(buffer), bytes)
		eq("and twice is once", CeroSecOS.bufferBytes(CeroSecOS.bufferOf(
			CeroSecOS.bufferBytes(buffer))), bytes)
	end
	-- vi adds the newline an open file lacked (POSIX ex(1), write).
	eq("an open file saves closed", CeroSecOS.bufferBytes(CeroSecOS.bufferOf("one")), "one\n")
	ok(state, admin, "echo hi > notes", {})
	local _, lines, control, edit = exec(state, admin, "edit notes")
	eq("edit opens", control, "edit")
	eq("with the lines and not the terminator", edit.text, "hi")

	-- Two messages into one box: each one's lines, the "From " line between.
	CeroSecOS.mailSend(state, "admin", "root", "ksp-front-01", "one", { "first" }, 0)
	CeroSecOS.mailSend(state, "admin", "root", "ksp-front-01", "two", { "second" }, 60)
	local box = data(state, CeroSecOS.mailPath("admin"))
	eq("the box ends its last line", string.sub(box, -1), "\n")
	local froms = 0
	for _, line in ipairs(CeroSecOS.splitLines(box)) do
		if string.sub(line, 1, 5) == "From " then froms = froms + 1 end
	end
	eq("and holds two messages", froms, 2)
	check("the second From starts its own line", string.find(box, "\nFrom root", 1, true) ~= nil)

	-- The accounts file, appended to by useradd, stays one account a line.
	local before = data(state, CeroSecOS.PASSWD_PATH)
	eq("/etc/passwd ends its line", string.sub(before, -1), "\n")
	CeroSecOS.addUser(state, "bob", "/home/bob", false, nil, 0)
	check("useradd adds a line", CeroSecOS.getUser(state, "bob") ~= nil)
	eq("and the file still ends in one newline", string.sub(data(state, CeroSecOS.PASSWD_PATH), -2),
		string.sub(data(state, CeroSecOS.PASSWD_PATH), -2, -2) .. "\n")
	check("with no empty line in it",
		string.find(data(state, CeroSecOS.PASSWD_PATH), "\n\n", 1, true) == nil)
end

--
-- 5. The skeleton ships text files, and binaries
--
do
	local state = fresh()
	for _, path in ipairs({ "/etc/hostname", "/etc/motd", "/etc/issue", "/etc/passwd",
			"/etc/group", "/etc/sudoers" }) do
		local text = data(state, path)
		eq(path .. " ends its last line", string.sub(text, -1), "\n")
	end
	eq("/bin/ls is the shipped bytes, a binary with no newline",
		data(state, "/bin/ls"), CeroSecOS.commandDesc("ls"))
end

--
-- 6. The editor's save: what a file already holds is never refused
--
-- CeroSecOS.saveBuffer, which the server's editsave calls. The buffer is
-- lines and the file is bytes, and between the two a save of an untouched
-- buffer must write the file back as it was -- including the two files the
-- plain rule gets wrong: one empty line ("\n", whose buffer is the empty
-- file's), and an open last line on a disk with no byte left for its "\n".
--
local function saved(state, session, path, buffer)
	return CeroSecOS.saveBuffer(state, session, path, buffer, nil)
end

do
	local state = fresh()
	local admin = open(state, "admin")
	local path = "/home/admin/rt"
	-- Every ending there is, opened and saved untouched. Only the open file
	-- changes, and that is vi's own rule: it adds the newline a file lacked.
	for _, pair in ipairs({ { "", "" }, { "\n", "\n" }, { "a", "a\n" },
			{ "a\n", "a\n" }, { "a\n\n", "a\n\n" } }) do
		put(state, admin, path, pair[1])
		local at = string.format("%q", pair[1])
		local done, why, bytes, incomplete = saved(state, admin, path,
			CeroSecOS.bufferOf(pair[1]))
		check(at .. " saves (" .. tostring(why) .. ")", done ~= nil)
		eq(at .. " saved untouched is " .. string.format("%q", pair[2]),
			data(state, path), pair[2])
		eq(at .. ": the bytes it reports are the bytes it wrote", bytes, pair[2])
		eq(at .. ": and the last line is complete", incomplete, false)
		-- And again, which is what a second Tab does.
		saved(state, admin, path, CeroSecOS.bufferOf(data(state, path)))
		eq(at .. ": twice is once", data(state, path), pair[2])
	end
	-- `echo > f` stores one empty line, and an untouched save keeps it one.
	ok(state, admin, "echo > /home/admin/blank", {})
	eq("echo > f is one empty line", data(state, "/home/admin/blank"), "\n")
	saved(state, admin, "/home/admin/blank", CeroSecOS.bufferOf("\n"))
	eq("which an untouched save leaves one empty line", data(state, "/home/admin/blank"), "\n")
	-- An empty buffer over NO file is an empty file, as it always was.
	saved(state, admin, "/home/admin/new", "")
	eq("an empty buffer makes an empty file", data(state, "/home/admin/new"), "")
end

-- The machine at its quota, and the file an old save left open on it: the
-- v2->v3 walk had no byte to close it with, so its "\n" is exactly what the
-- disk refuses.
do
	local state = fresh()
	local admin = open(state, "admin")
	local home = CeroSecOS.systemNode(state, "/home/admin")
	local old = string.rep("x", 99) .. "y"
	local _, used = CeroSecOS.usage(state)
	local left = CeroSecOS.MAX_TOTAL_BYTES - used - #old
	local n = 0
	while left > 0 do
		n = n + 1
		local size = math.min(left, CeroSecOS.MAX_FILE_BYTES)
		home.children["fill" .. n] = CeroSecOS.newFile("admin", 644, string.rep("f", size))
		left = left - size
	end
	home.children.old = CeroSecOS.newFile("admin", 644, old)
	local _, now = CeroSecOS.usage(state)
	eq("the machine is at its quota", now, CeroSecOS.MAX_TOTAL_BYTES)
	local path = "/home/admin/old"
	local _, plain = CeroSecOS.writeFile(state, admin, path, old .. "\n", false, nil)
	eq("the plain rule's bytes are refused", plain, "disk full")

	local done, why, bytes, incomplete = saved(state, admin, path, CeroSecOS.bufferOf(old))
	check("saved untouched, it is not refused (" .. tostring(why) .. ")", done ~= nil)
	eq("it is the same bytes", data(state, path), old)
	eq("and it says so", bytes, old)
	eq("with the last line open", incomplete, true)

	-- Edited, same length: the same rule and not a refusal.
	local edited = "z" .. string.sub(old, 2)
	done, why, bytes, incomplete = saved(state, admin, path, edited)
	check("edited at the limit, it saves (" .. tostring(why) .. ")", done ~= nil)
	eq("the edited bytes, open", data(state, path), edited)
	eq("and says so", incomplete, true)

	-- A buffer that grows by more than its newline is refused, as any write
	-- past the quota is, and the file is left as it was.
	done, why = saved(state, admin, path, edited .. "zz")
	eq("a buffer that grows is still refused", why, "disk full")
	eq("and the file is untouched", data(state, path), edited)
end

-- The same on a floppy at its 4096 bytes: the disk the file is on is the one
-- that is full, whatever room the machine has.
do
	local state = fresh()
	local admin = open(state, "admin")
	state.floppy = CeroSecOS.newFloppy("WORK")
	-- Formatted first, as os_test's floppies are: newfs makes the disk's root
	-- the formatter's own, which is what lets admin mount and write it.
	ok(state, admin, "newfs /dev/fd0", { "/dev/fd0: " .. CeroSecOS.FLOPPY_BYTES
		.. " bytes, " .. CeroSecOS.FLOPPY_NODES .. " inodes" })
	ok(state, admin, "mount /dev/fd0 /mnt", {})
	local root = CeroSecOS.floppyRoot(state)
	local old = string.rep("n", 2095) .. "m"
	root.children.fill = CeroSecOS.newFile("admin", 644,
		string.rep("f", CeroSecOS.FLOPPY_BYTES - #old))
	root.children.note = CeroSecOS.newFile("admin", 644, old)
	local _, full = CeroSecOS.subtreeUsage(root)
	eq("the floppy is full", full, CeroSecOS.FLOPPY_BYTES)
	local _, plain = CeroSecOS.writeFile(state, admin, "/mnt/note", old .. "\n", false, nil)
	eq("the plain rule's bytes are refused", plain, "disk full")

	local done, why, bytes, incomplete = saved(state, admin, "/mnt/note", CeroSecOS.bufferOf(old))
	check("saved untouched on the floppy, not refused (" .. tostring(why) .. ")", done ~= nil)
	eq("the same bytes", CeroSecOS.floppyRoot(state).children.note.data, old)
	eq("with the last line open", incomplete, true)
	eq("and nothing else", bytes, old)
end

print("newline_test: " .. count .. " assertions passed")
