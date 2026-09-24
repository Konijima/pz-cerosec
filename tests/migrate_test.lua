--
-- The compatibility bench: every photographed save in tests/fixtures/, walked up to
-- whatever the code is now, and held to what must still be true afterwards. Run from
-- the repo root:
--   lua5.1 tests/migrate_test.lua
--
-- The other benches build their machines with today's code, which is exactly what
-- this one must not do: a fixture built by the builder under test changes shape the
-- moment the builder does, so the chain would always be walking a state the previous
-- release never wrote. A fixture is a PHOTOGRAPH -- bytes a real build produced,
-- committed to git (tools/capture-fixture.sh) -- and this bench is the only place in
-- the suite that reads one.
--
-- What it asks, and each is a thing a careless migration really breaks:
--
--   * the gate takes the walked machine, and it is at THIS build's shape
--   * the accounts still log in, with the passwords they had
--   * the files are byte for byte what they were, and a script still RUNS
--   * the cron line is still in the spool
--   * the device numbers did not move -- light0 is the same switch tomorrow
--   * the hostname and the callsign are the machine's own
--   * the disk in the drive still mounts, with what is written on its sticker
--   * the door modules still fit, and the phone book keeps its edition
--   * walking twice changes nothing
--   * a save from a LATER build is refused and not touched
--
-- and two rules about the chain itself: that it has no hole in it, and that there IS
-- a fixture for the shape before this build's -- the save the update will actually
-- meet on somebody's disk.
--

local DIR = "42/media/lua/shared/CeroSec/OS/"
local FILES = {
	"CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSDev", "CeroSecOSDisk",
	"CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath", "CeroSecOSRadio", "CeroSecOSScript",
	"CeroSecOSShell", "CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers", "CeroSecOSVM",
}
for i = 1, #FILES do
	local path = DIR .. FILES[i] .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end

-- The two modData namespaces. They are shared files and they `require`, which the
-- game provides and lua5.1 does not, so the stub is the same one the client benches
-- use.
_G.require = function() end
_G.SandboxVars = nil
_G.IsoDoor = nil
_G.instanceof = function() return false end
local MOD_FILES = {
	"42/media/lua/shared/CeroSec/CeroSecDefs.lua",
	"42/media/lua/shared/CeroSec/CeroSecModules.lua",
	"42/media/lua/shared/CeroSec/CeroSecPhonebook.lua",
}
for i = 1, #MOD_FILES do
	local chunk, err = loadfile(MOD_FILES[i])
	if not chunk then error("cannot load " .. MOD_FILES[i] .. ": " .. tostring(err)) end
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

--
-- The fixtures
--
-- Found by NAME and not by listing the directory, which needs io.popen and a shell
-- and would make the bench depend on the order `ls` felt like answering in. The names
-- are state-v<N>.lua by construction (tools/capture-fixture.sh reads the number out of
-- the engine it captured from), so every number from the oldest shape the chain knows
-- up to this build's is probed and the ones that are there are loaded.
--
local function loadFixtures()
	local found, names = {}, {}
	for n = CeroSecOS.OLDEST_STATE_VERSION, CeroSecOS.STATE_VERSION do
		local path = "tests/fixtures/state-v" .. n .. ".lua"
		local chunk = loadfile(path)
		if chunk ~= nil then
			local fixture = chunk()
			check(path .. " returns a table", type(fixture) == "table")
			eq(path .. " says which shape it is", fixture.v, n)
			check(path .. " carries a machine", type(fixture.state) == "table")
			eq("and the machine agrees with the name", fixture.state.v, n)
			found[#found + 1] = { n = n, path = path, fixture = fixture }
			names[#names + 1] = path
		end
	end
	return found, names
end

local fixtures, names = loadFixtures()
check("there is at least one fixture", #fixtures > 0)

-- A fixture reloaded, so that every block starts from the bytes on disk rather than
-- from the table the last block mutated.
local function reload(entry)
	local chunk = loadfile(entry.path)
	return chunk()
end

--
-- 1. The chain has no hole in it
--
-- The bench that goes red on the day somebody moves STATE_VERSION and forgets the
-- step. CeroSecOS.migrate answers a fresh machine when it meets a gap, which is the
-- honest answer at runtime and a silent disaster in a release, so the gap is caught
-- here instead.
--
do
	for n = CeroSecOS.OLDEST_STATE_VERSION + 1, CeroSecOS.STATE_VERSION do
		check("there is a step for v" .. n, type(CeroSecOS.MIGRATIONS[n]) == "function")
	end
	-- And no step ABOVE this build's shape, which would be a step nothing runs: a
	-- change that wrote the migration and forgot to move the number.
	for n = CeroSecOS.STATE_VERSION + 1, CeroSecOS.STATE_VERSION + 8 do
		eq("no step for v" .. n .. ", which nothing would run", CeroSecOS.MIGRATIONS[n], nil)
	end

	-- And the fixture that matters most: the shape before this build's, which is the
	-- save the update will actually meet on somebody's disk. A release captures one
	-- before it bumps the number (docs/RELEASE.md), and this is what enforces it.
	local want = CeroSecOS.STATE_VERSION - 1
	if want >= CeroSecOS.OLDEST_STATE_VERSION then
		local got = false
		for i = 1, #fixtures do
			if fixtures[i].n == want then got = true end
		end
		check("there is a fixture for v" .. want .. ", the shape this update meets", got)
	end
end

--
-- 2. Every fixture, walked, and everything on it still there
--

local function sessionFor(state, name, password)
	local session, why = CeroSecOS.login(state, name, password or "")
	check("logging in as " .. name .. " (" .. tostring(why) .. ")", session ~= nil)
	return session
end

-- One line typed, run to the end. The machine has no single-line entry point -- a
-- command is a JOB the scheduler steps -- so this is the short form of the loop
-- os_test drives (see the note over its own `exec`): no control values, no spawns,
-- nothing this bench asks for. What matters here is that the lines came out of the
-- real engine and not out of a reimplementation of it.
local function run(state, session, line)
	if session.shvars == nil then session.shvars = {} end
	local env = { now = 725846400, nowMs = 1000, jobs = {} }
	local job, refusal = CeroSecOS.promptJob(state, session, line, session.shvars, session.status)
	if job == nil then return false, { refusal } end
	local out, turns = {}, 0
	while not CeroSecOS.jobIsOver(job) and turns < 500 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, env, 1000)
		for k = 1, #job.out do out[#out + 1] = job.out[k] end
		job.out = {}
		if job.state == "waiting" or job.state == "sleeping" then break end
		if job.spawn ~= nil then break end
	end
	for k = 1, #job.out do out[#out + 1] = job.out[k] end
	session.user = job.session.user
	session.cwd = job.session.cwd
	session.status = job.status
	return job.status == 0, out
end

-- The whole machine as one canonical string: keys sorted, numbers before strings, so
-- that two states are the same bytes when and only when they hold the same things.
--
-- This is what makes "twice is once" a real question. A field check cannot ask it: a
-- step that appended one character to the hostname on every pass, or that rewrote a
-- hash, or that added a node -- each leaves a state that validates, that logs in and
-- that reads back every file the bench names, and the only thing wrong with it is that
-- it is not the state the first pass produced.
local dump
dump = function(value, parts)
	local t = type(value)
	if t ~= "table" then
		parts[#parts + 1] = t .. ":" .. tostring(value)
		return
	end
	local nums, strs = {}, {}
	for k in pairs(value) do
		if type(k) == "number" then nums[#nums + 1] = k else strs[#strs + 1] = tostring(k) end
	end
	table.sort(nums)
	table.sort(strs)
	parts[#parts + 1] = "{"
	for j = 1, #nums do
		parts[#parts + 1] = "[" .. nums[j] .. "]="
		dump(value[nums[j]], parts)
		parts[#parts + 1] = ","
	end
	for j = 1, #strs do
		parts[#parts + 1] = strs[j] .. "="
		dump(value[strs[j]], parts)
		parts[#parts + 1] = ","
	end
	parts[#parts + 1] = "}"
end
local function canon(value)
	local parts = {}
	dump(value, parts)
	return table.concat(parts)
end

for i = 1, #fixtures do
	local entry = fixtures[i]
	local at = "v" .. entry.n .. ": "
	local fixture = reload(entry)
	local state = fixture.state

	local walked, why = CeroSecOS.migrate(state, "ksp-front-01")
	check(at .. "the machine came back", walked ~= nil)
	eq(at .. "with nothing to say", why, nil)
	check(at .. "and it is the SAME machine, not a new one", walked == state)
	eq(at .. "at this build's shape", state.v, CeroSecOS.STATE_VERSION)
	eq(at .. "and this build's contents", state.sysv, CeroSecOS.SYSTEM_VERSION)

	local ok, reason = CeroSecOS.validate(state)
	eq(at .. "the gate takes it (" .. tostring(reason) .. ")", ok, true)

	-- The accounts, and the passwords they had. Read by TRYING them, because what is
	-- stored is a hash and a migration that rewrote the field would look fine.
	check(at .. "root is still an account", CeroSecOS.getUser(state, "root") ~= nil)
	eq(at .. "and still an admin", CeroSecOS.getUser(state, "root").admin, true)
	check(at .. "admin is still an account", CeroSecOS.getUser(state, "admin") ~= nil)
	eq(at .. "and still is not one", CeroSecOS.getUser(state, "admin").admin, false)
	local sam = sessionFor(state, "sam", "letmein")
	eq(at .. "sam's home is his own", sam.cwd, "/home/sam")
	eq(at .. "and a wrong password is still wrong",
		CeroSecOS.login(state, "sam", "letmeout"), nil)

	-- The files, byte for byte.
	local notes = CeroSecOS.systemNode(state, "/home/sam/notes.txt")
	check(at .. "sam's file is there", notes ~= nil)
	eq(at .. "with what he wrote in it", notes.data, "the generator needs fuel\n")
	local todo = CeroSecOS.systemNode(state, "/home/admin/todo.txt")
	check(at .. "and admin's", todo ~= nil)
	eq(at .. "with his", todo.data, "check the back door\n")

	-- And the script RUNS, which is the half no field can prove: a file whose owner,
	-- mode or bytes a migration touched is a file the shell will not read.
	local admin = sessionFor(state, "admin", "")
	local ranOk, out = run(state, admin, "sh /home/admin/count.sh")
	eq(at .. "the script runs", ranOk, true)
	eq(at .. "and prints its first line", out[1], "one")
	eq(at .. "and its second", out[2], "two")
	eq(at .. "and nothing else", #out, 2)

	-- The cron line, in the spool where it was.
	local crontab = CeroSecOS.systemNode(state, CeroSecOS.cronPath("admin"))
	check(at .. "the crontab is still there", crontab ~= nil)
	check(at .. "with the line in it",
		string.find(crontab.data, "echo tick", 1, true) ~= nil)
	local entries = CeroSecOS.parseCrontab(crontab.data)
	eq(at .. "and it still parses to one job", #entries, 1)

	-- What the top-up SEEDED on the way in, asked of the photograph rather than of a
	-- machine this bench built: /usr/local/bin and the two directories above it are
	-- on every machine now, and a save written before SYSTEM_VERSION 21 has none of
	-- them. The one instruction the HOME disk has room for names that directory, so
	-- a machine off an old save that did not gain it is a machine where the disk
	-- lies.
	local chain = state.fs
	for j = 1, #CeroSecOS.LOCAL_BIN_DIRS do
		chain = chain.children[CeroSecOS.LOCAL_BIN_DIRS[j]]
		local where = "/" .. table.concat(CeroSecOS.LOCAL_BIN_DIRS, "/", 1, j)
		check(at .. where .. " is on the machine",
			type(chain) == "table" and chain.type == "dir")
		eq(at .. "root's", chain.owner, "root")
		eq(at .. "at 755", chain.mode, CeroSecOS.LOCAL_BIN_MODE)
	end
	-- And it is a directory the shell will look in, which is the half a field check
	-- cannot ask: a program installed there answers to its name at the prompt.
	local installed = CeroSecOS.writeFile(state, CeroSecOS.rootSession(),
		CeroSecOS.LOCAL_BIN_PATH .. "/curtains.sh", "echo curtains: open", false, 100)
	check(at .. "a program installs into it", installed ~= nil)
	CeroSecOS.getNode(state, CeroSecOS.rootSession(),
		CeroSecOS.LOCAL_BIN_PATH .. "/curtains.sh").mode = 755
	admin.shvars = CeroSecOS.loginVars("/home/admin")
	local typedOk, typedOut = run(state, admin, "curtains.sh")
	eq(at .. "and answers to its name (" .. tostring(typedOut[1]) .. ")", typedOk, true)
	eq(at .. "with what it prints", typedOut[1], "curtains: open")
	local removed = CeroSecOS.removeNode(state, CeroSecOS.rootSession(),
		CeroSecOS.LOCAL_BIN_PATH .. "/curtains.sh", false)
	check(at .. "and the bench takes its own program back off the machine",
		removed ~= nil)
	admin.shvars = nil

	-- The device numbers. light0 is the same switch tomorrow as today: the book is
	-- keyed by WHERE the device is, and a migration that rekeyed it would renumber
	-- every /dev entry under a script somebody wrote.
	check(at .. "the device book is still there", type(state.devmap) == "table")
	local light = state.devmap["light:1024:998:0::0"]
	check(at .. "and the switch is in it", type(light) == "table")
	eq(at .. "with the id it had", light.id, "light0")
	eq(at .. "and the mode it had", light.mode, 660)
	check(at .. "and the lock too", state.devmap["lock:1024:999:0:N:0"] ~= nil)

	-- The machine's own name, and the licence on its disk.
	eq(at .. "the hostname is the machine's", CeroSecOS.hostname(state), "ksp-front-01")
	local net = CeroSecOS.netRecord(state)
	check(at .. "the wire record is still there", net ~= nil)
	eq(at .. "with its address", CeroSecOS.address(state), "10.10.4.17")
	eq(at .. "and the exchange the telephone work added", net.ex, 555)
	eq(at .. "and what the premises is called", net.pz, "Coffee Shop")
	local call = CeroSecOS.callsignOf(state)
	check(at .. "and the callsign is on the disk", type(call) == "string" and call ~= "")

	-- The disk in the drive: still there, still labelled, and it still MOUNTS -- the
	-- one question that asks the whole disk rather than a field on it.
	local disk = CeroSecOS.floppyOf(state)
	check(at .. "there is still a disk in the drive", disk ~= nil)
	eq(at .. "with what is written on its sticker", disk.label, "PAYROLL 93")
	eq(at .. "at its own shape", disk.v, CeroSecOS.FLOPPY_VERSION)
	local mountOk, mountOut = run(state, admin, "mount /dev/fd0 /mnt")
	eq(at .. "the disk mounts (" .. tostring(mountOut[1]) .. ")", mountOk, true)
	-- Read THROUGH the mount and not off state.floppy.fs, which is the whole point of
	-- asking `cat`: systemNode walks the machine's own tree and never crosses a mount,
	-- so a disk whose tree survived but whose mount did not would pass a field check
	-- and fail the only question a survivor ever asks of it.
	local catOk, catOut = run(state, admin, "cat /mnt/pay.txt")
	eq(at .. "what is on the disk reads through the mount", catOk, true)
	eq(at .. "byte for byte", catOut[1], "sam 40h")
	local lsOk, lsOut = run(state, admin, "df")
	eq(at .. "and df names the sticker", lsOk, true)
	local named = false
	for j = 1, #lsOut do
		if string.find(lsOut[j], "PAYROLL 93", 1, true) then named = true end
	end
	check(at .. "somewhere in its listing", named)
	run(state, admin, "umount /mnt")

	-- The job book, which this shape does not have and must not grow one.
	--
	-- Every machine in every save written before this build has no `jobs` key under
	-- `os`, and absent has to read as "this machine was running nothing" -- which is
	-- the compatibility contract's own rule for a field a change added (read with a
	-- default, never with an assumption). So the chain does not invent one, the gate
	-- takes the machine without one, and a photograph of an older save comes through
	-- here with the key still absent.
	eq(at .. "a save from before the job book has none", state.jobs, nil)

	-- The two namespaces that are not the machine's state.
	local fittedFront = fixture.modules[1]
	local doorData = { [CeroSecModules.DATA_KEY] = fittedFront }
	local door = {
		hasModData = function() return true end,
		getModData = function() return doorData end,
		transmitModData = function() end,
	}
	local fitted = CeroSecModules.installedOn(door)
	eq(at .. "the strike still fits the front door", fitted.strike, true)
	eq(at .. "and the contact on it", fitted.contact, true)
	local switchData = { [CeroSecModules.DATA_KEY] = fixture.modules[2] }
	local switch = {
		hasModData = function() return true end,
		getModData = function() return switchData end,
		transmitModData = function() end,
	}
	eq(at .. "and the relay still fits the light switch",
		CeroSecModules.installedOn(switch).relay, true)

	-- AND NO CABLE IS INVENTED FOR A FIXTURE THAT NEVER HAD ONE. `link` is a key this
	-- build added to the very table the modules live in, so an older fixture reaches
	-- the reader through the same migration the modules do -- the number on the table
	-- moves and the boxes on it do not. Absent has to read as "nobody ran a cable to
	-- this" and never as an empty list a reader has to interpret: a fixture out of a
	-- 0.4.x save has no `link` key and must still have none after it has been read.
	eq(at .. "the front door out of an older save carries no cable",
		#CeroSecModules.linksOn(door), 0)
	eq(at .. "and none was written onto it by the reading",
		doorData[CeroSecModules.DATA_KEY][CeroSecModules.LINK_KEY], nil)
	eq(at .. "the light switch carries none either",
		#CeroSecModules.linksOn(switch), 0)
	-- The number DID move, which is the other half of the contract: a shape a reader
	-- can be held to is one the reader stamps.
	eq(at .. "and the table is at this build's shape",
		doorData[CeroSecModules.DATA_KEY][CeroSecModules.VERSION_KEY],
		CeroSecModules.VERSION)
	eq(at .. "with the strike still on it after the walk",
		CeroSecModules.installedOn(door).strike, true)
	eq(at .. "and the contact beside it",
		CeroSecModules.installedOn(door).contact, true)

	local rx, ry = CeroSecPhonebook.regionOn(fixture.phonebook)
	eq(at .. "the phone book keeps its edition (x)", rx, 7)
	eq(at .. "and (y)", ry, 9)

	-- A disk in somebody's POCKET, which comes in by the other road: the slot.
	local inHand, slotWhy = CeroSecOS.diskFromData(fixture.disk)
	check(at .. "the disk in his bag still goes in the slot (" .. tostring(slotWhy) .. ")",
		inHand ~= nil)
	eq(at .. "with its own sticker", inHand.label, "BACKUP")

	--
	-- 3. Twice is once
	--
	-- Every step is idempotent, so walking a machine again does nothing at all. In
	-- production this cannot happen -- the number has moved -- but a step that is not
	-- idempotent is a step whose second half nobody can read, and this is the only
	-- place that can say so.
	--
	-- The version is put BACK to the fixture's before the second walk, and that is the
	-- whole of what makes this a test at all. Calling migrate again as it stands runs
	-- nothing -- the number has moved, so the loop has no steps left -- which is a
	-- bench that proves the GUARD and says nothing about the steps. Winding the number
	-- back is what makes every step run a second time, on a machine they have already
	-- been over, which is exactly the property "idempotent" names.
	--
	-- Compared as BYTES and not field by field, because that is the only way to ask
	-- it: a step that appended one character to a name, rewrote a hash or added a node
	-- leaves a machine that validates, logs in and reads back every file named above,
	-- and differs only from the one the first pass produced.
	--
	-- The disk is unmounted first: a MOUNT is not part of the shape -- the bench itself
	-- mounted it two dozen lines ago -- so a mount table in the snapshot would be the
	-- bench comparing its own doing.
	CeroSecOS.unmountAll(state)
	local once = canon(state)
	state.v = entry.n
	local second = CeroSecOS.migrate(state, "ksp-front-01")
	check(at .. "a second walk hands the same machine back", second == state)
	eq(at .. "and changes not one byte of it", canon(state), once)
	eq(at .. "still at this shape", state.v, CeroSecOS.STATE_VERSION)
	eq(at .. "and the gate still takes it", CeroSecOS.validate(state), true)
	eq(at .. "sam still logs in", CeroSecOS.login(state, "sam", "letmein") ~= nil, true)
	eq(at .. "his file is still his file",
		CeroSecOS.systemNode(state, "/home/sam/notes.txt").data, "the generator needs fuel\n")
	eq(at .. "and the disk is still labelled", CeroSecOS.floppyOf(state).label, "PAYROLL 93")

	--
	-- 4. A save from a LATER build is refused, and not touched
	--
	local tomorrow = reload(entry).state
	tomorrow.v = CeroSecOS.STATE_VERSION + 1
	local refused, tWhy = CeroSecOS.migrate(tomorrow, "ksp-front-01")
	eq(at .. "a newer save is refused", refused, nil)
	eq(at .. "and says why", tWhy, "newer")
	eq(at .. "its shape is untouched", tomorrow.v, CeroSecOS.STATE_VERSION + 1)
	eq(at .. "its contents number is untouched", tomorrow.sysv, entry.fixture.sysv)
	eq(at .. "and sam's file is untouched",
		CeroSecOS.systemNode(tomorrow, "/home/sam/notes.txt").data, "the generator needs fuel")
end

--
-- 5. The shapes a v1 machine could ALSO carry, provoked
--
-- The photograph of v1 does not hold them, and cannot: the build that took it
-- converted both on every load, so what it wrote out was already converted. But a
-- SAVE can hold them -- one written by a build older still and never opened since --
-- and they are the whole of what the chain's first step is for. So the bench puts them
-- back onto the real v1 machine and asks whether the step does its work.
--
-- Without this, step 2 would be a step that never ran on anything: green for having
-- found nothing to do.
--
do
	local base = nil
	for i = 1, #fixtures do
		if fixtures[i].n == 1 then base = fixtures[i] end
	end
	if base ~= nil then
		local state = reload(base).state

		-- The accounts as a table on the state, with the passwords in CLEAR, and no
		-- /etc/passwd at all -- the shape before the file existed.
		state.fs.children.etc.children.passwd = nil
		state.users = {
			root = { name = "root", password = "toor", home = "/root", admin = true },
			sam = { name = "sam", password = "letmein", home = "/home/sam", admin = false },
		}
		-- And the quota flag, on a node it was really written on: sam's own history,
		-- which is exempt because of WHERE it is (CeroSecOS.exemptPaths derives the
		-- paths from the accounts) and not because of any flag on it -- which is the
		-- whole reason the flag is being taken off.
		local hist = CeroSecOS.newFile("sam", CeroSecOS.HISTORY_MODE, "echo hi")
		hist.nq = true
		state.fs.children.home.children.sam.children[CeroSecOS.HISTORY_NAME] = hist
		state.fs.children.etc.children.motd.nq = true

		local walked = CeroSecOS.migrate(state, "ksp-front-01")
		check("the older-still machine came back", walked == state)
		eq("at this build's shape", state.v, CeroSecOS.STATE_VERSION)
		eq("and the gate takes it", CeroSecOS.validate(state), true)

		-- The accounts are a file now, and the passwords are hashes that still work.
		eq("the accounts table is gone", state.users, nil)
		local passwd = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
		check("and /etc/passwd is there", passwd ~= nil)
		eq("owned by root", passwd.owner, "root")
		check("root's password is a hash now",
			CeroSecOS.splitHash(CeroSecOS.getUser(state, "root").password) ~= nil)
		check("and root still logs in with what he had",
			CeroSecOS.login(state, "root", "toor") ~= nil)
		eq("and not with anything else", CeroSecOS.login(state, "root", ""), nil)
		check("sam still logs in too", CeroSecOS.login(state, "sam", "letmein") ~= nil)
		eq("sam is still not an admin", CeroSecOS.getUser(state, "sam").admin, false)
		eq("and root still is", CeroSecOS.getUser(state, "root").admin, true)

		-- And the flag is off every node.
		eq("the quota flag is off the history", hist.nq, nil)
		eq("and off every other node", state.fs.children.etc.children.motd.nq, nil)
		eq("and the history is exempt all the same", CeroSecOS.exemptUsage(state), #"echo hi\n")

		-- And what was on the machine is still on it: a step that converts the
		-- accounts has no business touching anything else.
		eq("sam's file survived the conversion",
			CeroSecOS.systemNode(state, "/home/sam/notes.txt").data, "the generator needs fuel\n")
		eq("and the disk is still in the drive", CeroSecOS.floppyOf(state).label, "PAYROLL 93")

		-- Twice is once, here too, and byte for byte: the accounts conversion is the one
		-- step there IS, and a second pass that rewrote a hash or re-seeded /bin would
		-- leave a machine that still validates and still logs in.
		local once = canon(state)
		state.v = 1
		local again = CeroSecOS.migrate(state, "ksp-front-01")
		check("a second walk changes nothing", again == state)
		eq("not one byte of it", canon(state), once)
		eq("and the gate still takes it", CeroSecOS.validate(state), true)
		check("and root still logs in", CeroSecOS.login(state, "root", "toor") ~= nil)
	end
end

--
-- 5b. STATE_VERSION 3 and FLOPPY_VERSION 2: a file's last line gets its newline
--
-- The v2 photograph is what 0.6.1 and the 0.7.0 builds before this change wrote
-- (tools/capture-fixture.sh on the commit before the bump gives it back byte for
-- byte), and every text file in it ends with no "\n". Walked up, each one gains
-- exactly one byte, and nothing else in the file moves.
--
local function filesOf(node, path, into)
	into = into or {}
	if type(node) ~= "table" then return into end
	if node.type == "file" then into[path] = node.data return into end
	if type(node.children) == "table" then
		for name, child in pairs(node.children) do filesOf(child, path .. "/" .. name, into) end
	end
	return into
end

do
	local entry = nil
	for i = 1, #fixtures do
		if fixtures[i].n == 2 then entry = fixtures[i] end
	end
	check("the v2 photograph is here to walk", entry ~= nil)
	local fixture = reload(entry)
	local state = fixture.state
	-- Three files the photograph does not happen to hold, planted in it the way a
	-- v2 build would have stored them: empty, already ending in "\n" (a >> of an
	-- empty echo could leave that), and one at the ceiling a file may reach.
	local home = state.fs.children.home.children.sam or state.fs.children.home.children.admin
	check("a home to plant in", home ~= nil and home.type == "dir")
	home.children["empty.txt"] = CeroSecOS.newFile("sam", 644, "")
	home.children["closed.txt"] = CeroSecOS.newFile("sam", 644, "done\n")
	home.children["full.txt"] = CeroSecOS.newFile("sam", 644,
		string.rep("x", CeroSecOS.MAX_FILE_BYTES))
	local before = filesOf(state.fs, "")
	local standIn = {}
	for name in pairs(CeroSecOS.COMMAND_INFO) do standIn[CeroSecOS.commandDesc(name)] = true end

	local walked = CeroSecOS.migrate(state, "ksp-front-01")
	check("v2 -> 3: the machine came back", walked == state)
	local after = filesOf(state.fs, "")
	local closed, binaries = 0, 0
	for path, was in pairs(before) do
		local now = after[path]
		if now ~= nil then
			if was == "" then
				eq(path .. " is empty and stays empty", now, "")
			elseif string.sub(was, -1) == "\n" then
				eq(path .. " ended its line already and is untouched", now, was)
			elseif #was >= CeroSecOS.MAX_FILE_BYTES then
				eq(path .. " is at a file's ceiling and is left open", now, was)
			elseif standIn[was] then
				eq(path .. " is a /bin stand-in, a binary, and is untouched", now, was)
				binaries = binaries + 1
			else
				eq(path .. " gains exactly its newline", now, was .. "\n")
				closed = closed + 1
			end
		end
	end
	check("and there were text files to close (" .. closed .. ")", closed > 5)
	check("and binaries to leave alone (" .. binaries .. ")", binaries > 20)
	eq("sam's note reads the same lines", table.concat(CeroSecOS.splitLines(
		CeroSecOS.systemNode(state, "/home/sam/notes.txt").data), "|"), "the generator needs fuel")
	-- An upgrade that closed a stand-in would keep a retired command in /bin for
	-- ever: upgradeSystem retires one only when its bytes are the shipped ones.
	eq("/bin/ls is still the shipped bytes", CeroSecOS.systemNode(state, "/bin/ls").data,
		CeroSecOS.commandDesc("ls"))

	-- And the disk in the drive, which rides inside the state, on its own number.
	local inDrive = CeroSecOS.floppyOf(state)
	eq("the floppy in the drive is at this build's shape", inDrive.v, CeroSecOS.FLOPPY_VERSION)
	for path, data in pairs(filesOf(inDrive.fs, "")) do
		check("its " .. path .. " ends its line", data == "" or string.sub(data, -1) == "\n")
	end

	-- Twice is once: wound back and walked again, not one byte moves.
	local once = canon(state)
	state.v = 2
	inDrive.v = 1
	CeroSecOS.migrate(state, "ksp-front-01")
	eq("a second walk of step 3 changes nothing", canon(state), once)

	-- The disk in his POCKET, by the slot: the same step, on the way in.
	local inHand = CeroSecOS.diskFromData(fixture.disk)
	check("the pocket disk goes in", inHand ~= nil)
	eq("at this build's shape", inHand.v, CeroSecOS.FLOPPY_VERSION)
	for path, data in pairs(filesOf(inHand.fs, "")) do
		check("its " .. path .. " ends its line", data == "" or string.sub(data, -1) == "\n")
	end
end

-- A FULL floppy: the step is paid out of the disk's own 4096 bytes and never past
-- them, because the slot refuses a disk over FLOPPY_BYTES and a migration that
-- pushed one over would turn a full disk into one no drive takes.
do
	local fs = CeroSecOS.newDir("root", 755)
	fs.children.a = CeroSecOS.newFile("root", 644, string.rep("a", 2047))
	fs.children.b = CeroSecOS.newFile("root", 644, string.rep("b", 2048))
	local disk = { v = 1, fs = fs, label = "FULL" }
	local _, was = CeroSecOS.subtreeUsage(fs)
	eq("the disk is one byte short of full", was, CeroSecOS.FLOPPY_BYTES - 1)
	local inHand, why = CeroSecOS.diskFromData(disk)
	check("it still goes in the slot (" .. tostring(why) .. ")", inHand ~= nil)
	local _, now = CeroSecOS.subtreeUsage(inHand.fs)
	eq("and it is full now, not over", now, CeroSecOS.FLOPPY_BYTES)
	eq("the first file by name took the one byte there was",
		inHand.fs.children.a.data, string.rep("a", 2047) .. "\n")
	eq("and the second was left as it was", inHand.fs.children.b.data, string.rep("b", 2048))
end

--
-- 5c. SYSTEM_VERSION: an old world has every command a new machine has
--
-- The guard for the day a release adds a command and forgets the bump. 0.7.0
-- did exactly that: expr, uname and rmdir went into COMMAND_INFO, the number
-- stayed at 21, upgradeSystem returned early on every save already at 21, and
-- all three were `not found` in every world that existed. Asked of the
-- photographs, because they are what an update really meets.
--
do
	local fresh = CeroSecOS.newState("fresh")
	local shipped = {}
	for name, node in pairs(CeroSecOS.systemNode(fresh, "/bin").children) do
		if node.type == "file" then shipped[#shipped + 1] = name end
	end
	table.sort(shipped)
	check("a fresh machine ships commands (" .. #shipped .. ")", #shipped > 20)

	for i = 1, #fixtures do
		local entry = fixtures[i]
		local at = "v" .. entry.n .. " (sysv " .. tostring(entry.fixture.sysv) .. "): "
		local before = reload(entry).state
		local had = CeroSecOS.systemNode(before, "/bin").children
		local state = reload(entry).state
		CeroSecOS.migrate(state, "ksp-front-01")
		local bin = CeroSecOS.systemNode(state, "/bin").children
		for k = 1, #shipped do
			local name = shipped[k]
			local node = bin[name]
			check(at .. "/bin/" .. name .. " is there after the upgrade",
				node ~= nil and node.type == "file")
			-- A save that had the whole top-up is given only what BIN_SINCE
			-- names, so a new command with no line there is one it never gets.
			if had[name] == nil and entry.fixture.sysv >= CeroSecOS.SYSTEM_GATED then
				local since = CeroSecOS.BIN_SINCE[name]
				check(at .. name .. " is new since the photo, so BIN_SINCE dates it",
					type(since) == "number" and since > entry.fixture.sysv
					and since <= CeroSecOS.SYSTEM_VERSION)
			end
		end
	end

	-- And what a gated top-up must NOT do: put back what the owner deleted. A
	-- save at 21 had the whole top-up once; its missing /bin/wall, /etc/issue
	-- and wheel line are his deletions, and the contract is that they stay.
	local newest
	for i = 1, #fixtures do
		if fixtures[i].fixture.sysv >= CeroSecOS.SYSTEM_GATED then newest = fixtures[i] end
	end
	check("there is a photograph a gated top-up walks", newest ~= nil)
	local state = reload(newest).state
	local etc = CeroSecOS.systemNode(state, "/etc")
	CeroSecOS.systemNode(state, "/bin").children.wall = nil
	etc.children.issue = nil
	local sudoers = etc.children.sudoers.data
	local cut = string.gsub(sudoers, "%%wheel[^\n]*\n?", "")
	check("the photo had a wheel line to take out", cut ~= sudoers)
	etc.children.sudoers.data = cut
	CeroSecOS.migrate(state, "ksp-front-01")
	eq("a deleted /bin/wall stays deleted", CeroSecOS.systemNode(state, "/bin/wall"), nil)
	eq("a deleted /etc/issue stays deleted", CeroSecOS.systemNode(state, "/etc/issue"), nil)
	check("a wheel line taken out stays out", string.find(
		CeroSecOS.systemNode(state, "/etc/sudoers").data, "%wheel", 1, true) == nil)
	check("while expr still arrives", CeroSecOS.systemNode(state, "/bin/expr") ~= nil)
end

--
-- 6. The key names the fixture is written against
--
-- The fixture holds the two modData namespaces as LITERALS, because the files that
-- own them do not load without the game (tools/capture-fixture.lua says so). So the
-- names are pinned here: a rename that left the fixture behind would otherwise make
-- every assertion above pass against a table nothing reads.
--
do
	eq("the modules hang under this name", CeroSecModules.DATA_KEY, "cerosec")
	eq("the phone book stamp under this one", CeroSecPhonebook.DATA_KEY, "cerosec")
	eq("and the edition under this", CeroSecPhonebook.REGION_KEY, "region")
	eq("the three keys a disk owns", table.concat(CeroSecOS.DISK_KEYS, " "), "v fs label")
end

print("migrate_test: " .. count .. " checks passed over " ..
	#fixtures .. " fixture(s): " .. table.concat(names, ", "))
