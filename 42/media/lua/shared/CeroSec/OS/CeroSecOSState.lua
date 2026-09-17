--
-- CeroSec OS core: state, validation, migration.
--
-- The state is already plain nested tables, so there is nothing to serialize;
-- what it needs instead is a gate that says whether a blob handed back by the
-- game is still something the core can run on.
--

CeroSecOS = CeroSecOS or {}

-- A fresh machine: the standard skeleton, the commands in /bin, root and admin
-- in /etc/passwd, both open, admin in /etc/sudoers, and the three shipped
-- groups in /etc/group. Nothing about the machine lives outside its own
-- filesystem -- there is no table of users beside /etc/passwd, no list of
-- commands beside /bin, no list of sudoers beside /etc/sudoers and no table of
-- groups beside /etc/group.
function CeroSecOS.newState(hostname)
	if not CeroSecOS.isValidHostname(hostname) then
		hostname = CeroSecOS.DEFAULT_HOSTNAME
	end

	local root = CeroSecOS.newDir("root", 755)
	root.children.bin = CeroSecOS.newDir("root", 755)
	CeroSecOS.fillBin(root.children.bin)
	root.children.home = CeroSecOS.newDir("root", 755)
	root.children.home.children[CeroSecOS.FACTORY_USER] =
		CeroSecOS.newDir(CeroSecOS.FACTORY_USER, CeroSecOS.HOME_MODE)
	root.children.root = CeroSecOS.newDir("root", 700)
	root.children.dev = CeroSecOS.newDir("root", 755)
	root.children.etc = CeroSecOS.newDir("root", 755)
	root.children.etc.children.hostname = CeroSecOS.newFile("root", 644, hostname)
	root.children.etc.children.motd = CeroSecOS.newFile("root", 644, CeroSecOS.MOTD)
	-- The banner over the login prompt, with the machine's own name written into
	-- it: nothing expands a token on its way to the glass, so the name goes in
	-- here and setHostname keeps it true (CeroSecOS.issueText).
	root.children.etc.children.issue =
		CeroSecOS.newFile("root", 644, CeroSecOS.issueText(hostname))
	root.children.etc.children.passwd =
		CeroSecOS.newFile("root", CeroSecOS.PASSWD_MODE, CeroSecOS.defaultPasswd())
	root.children.etc.children.group =
		CeroSecOS.newFile("root", CeroSecOS.GROUP_MODE, CeroSecOS.defaultGroup())
	root.children.etc.children.sudoers =
		CeroSecOS.newFile("root", CeroSecOS.SUDOERS_MODE, CeroSecOS.defaultSudoers())

	local state = {
		v = CeroSecOS.STATE_VERSION,
		sysv = CeroSecOS.SYSTEM_VERSION,
		hostname = hostname,
		fs = root,
		sessions = {},
	}
	-- /var and the three under it: the crontab spool, the log and the mail. Made
	-- through the one function that knows their modes, so a fresh machine, an
	-- older one being topped up and a machine the BIOS has repaired all have the
	-- same tree.
	CeroSecOS.ensureVar(state)
	-- And /dev/null, the one device that is on the disk rather than in the world.
	CeroSecOS.ensureDev(state)
	-- And /etc/hosts and /etc/hosts.equiv. The machine's own line in the first is
	-- not written here: an address is a fact about which building the computer
	-- stands in, and nothing in the engine has ever seen a building.
	CeroSecOS.ensureNet(state)
	-- And /mnt, the place a floppy is mounted on. state.floppy stays absent: a
	-- fresh machine has an empty drive, and so does every machine until somebody
	-- puts a disk in the slot.
	CeroSecOS.ensureMnt(state)
	-- And /usr/local/bin with the two directories above it, empty: where the
	-- machine's own software goes, and what the second half of DEFAULT_PATH names.
	CeroSecOS.ensureLocalBin(state)
	return state
end

--
-- Validation.
--

-- Everything the game stores must be a plain nested table of strings, numbers
-- and booleans: no functions, no userdata, no metatables, no cycles.
--
-- And it must END. The cycle test catches a table that contains itself; it does not
-- catch a chain fifty thousand tables long, and that was a stack overflow out of
-- whoever asked rather than an answer. Only a hand-edited save file holds one --
-- nothing this engine writes goes that deep, and everything that arrives from
-- outside is refused before it gets here (CeroSecOS.diskShape) -- but a gate whose
-- job is to say whether a blob can be run on has to survive the blob.
--
-- The bound is deliberately FAR above anything a state can legally be, and that is
-- the whole of how it is chosen. What this walk is for is stopping a runaway; what
-- enforces the filesystem's own depth is checkNode, one gate along, which says
-- "too deep" about the node that is too deep instead of about the twentieth table
-- inside it. A belt that can fire on a legal machine is not a belt -- it is a
-- bricked computer, because osState's refusal is sticky.
--
-- Measured, the deepest legal state there is -- a disk mounted on a machine, its
-- tree as deep as the write path allows, a file at the bottom of it -- reaches 35:
-- the state, the disk, its root, then two table levels for every level down (the
-- node and its children), then the leaf's own field. Four times MAX_DEPTH is
-- sixty-four, which is most of the way to twice that and nowhere near a stack.
local PLAIN_DEPTH = 4 * CeroSecOS.MAX_DEPTH

-- And how many tables it may look at, which is a different bound from the depth
-- and is needed for a reason that is not obvious.
--
-- `seen` is popped on the way back out, which is what makes it a test for a CYCLE
-- rather than for a shared subtree -- two names for one table are not a loop, and
-- calling them one would be a false refusal. The price is that a shared table is
-- walked once per PATH to it, so twenty tables each pointing twice at the next are
-- a million paths: twenty-three tables took sixty-eight seconds here, on a gate a
-- forged state reaches on its way in (SCeroSecObject:osState). The depth bound
-- does not help, because the shape is shallow; only counting the walk does.
--
-- Eight times what the two disks can hold between them, which is 4352.
--
-- What the largest legal state really costs was written here as 576 and that was
-- measured on a machine whose nodes are FILES. A file is one table; a DIRECTORY is
-- two, the node and its `children`. So the worst legal state is the one where every
-- node is a directory -- 512 of them with 511 directories is 1023 tables, a 32-node
-- floppy all directories is 65 with the disk's own table, and the state itself is
-- the rest: **1090**, measured the same way. Four times clear rather than seven,
-- and still chosen to be nowhere near anything real: a machine as it ships is 128.
--
-- The number matters to more than this walk now. The job book is written into the
-- state under its own key at a save and the gate counts it on the next load, so
-- what is left of this budget after the worst filesystem is what bounds the book
-- (CeroSec.JOB_SAVE_TABLES, and the head of "The book across a save" in
-- SCeroSecJobs.lua). tests/window_test.lua builds the all-directory worst case and
-- asserts the three numbers add up, so the arithmetic is guarded and not merely
-- written down here.
local PLAIN_VISITS = 8 * (CeroSecOS.MAX_NODES + CeroSecOS.FLOPPY_NODES)

local function checkPlain(value, seen, where, depth, budget)
	local t = type(value)
	if t == "string" or t == "number" or t == "boolean" then return true end
	if t ~= "table" then return false, where .. ": " .. t .. " is not storable" end
	if getmetatable(value) ~= nil then return false, where .. ": has a metatable" end
	if seen[value] then return false, where .. ": cycle" end
	depth = depth or 0
	if depth > PLAIN_DEPTH then return false, where .. ": too deep" end
	budget = budget or { left = PLAIN_VISITS }
	budget.left = budget.left - 1
	if budget.left < 0 then return false, where .. ": too many tables" end
	seen[value] = true
	for k, v in pairs(value) do
		local kt = type(k)
		if kt ~= "string" and kt ~= "number" then return false, where .. ": key of type " .. kt end
		local ok, reason =
			checkPlain(v, seen, where .. "." .. tostring(k), depth + 1, budget)
		if not ok then return false, reason end
	end
	seen[value] = nil
	return true
end

-- tally carries the node ceiling it is counting against rather than reading
-- MAX_NODES itself: the same walk checks the machine's own drive and the disk in
-- its slot, and those are two different ceilings (CeroSecOS.FLOPPY_NODES).
local function checkNode(node, where, depth, tally)
	if type(node) ~= "table" then return false, where .. ": not a node" end
	if type(node.owner) ~= "string" then return false, where .. ": bad owner" end
	-- A group is optional, exactly as a timestamp is: every node of every
	-- machine saved before this build has none, and none reads as the owner's
	-- own name. One that is there has to be a string -- a number in that field
	-- would be a mode digit chosen by something nobody can name.
	if node.group ~= nil and type(node.group) ~= "string" then
		return false, where .. ": bad group"
	end
	if type(node.mode) ~= "number" then return false, where .. ": bad mode" end
	if node.mode < 0 or node.mode > 777 or node.mode ~= math.floor(node.mode) then
		return false, where .. ": bad mode"
	end
	if depth > CeroSecOS.MAX_DEPTH then return false, where .. ": too deep" end
	-- A timestamp is optional: every node of every machine saved before this
	-- build has none, and none means 0. One that is there has to be a whole
	-- number of seconds -- anything else would print as a date nobody can read.
	if node.mtime ~= nil then
		if type(node.mtime) ~= "number" then return false, where .. ": bad mtime" end
		if node.mtime ~= math.floor(node.mtime) then return false, where .. ": bad mtime" end
	end

	-- The machine's own null device, and no other device: the world's are mounted
	-- for the length of one command and swept off again (CeroSecOS.unmountDev), and
	-- so is the floppy drive -- /dev/fd0 on a saved disk is a state nothing here can
	-- be asked to run on either. It is NOT counted: a device costs the disk nothing
	-- anywhere else either (CeroSecOS.subtreeUsage), and a gate that counted it
	-- differently from the quota would refuse a machine the quota had just let fill
	-- up.
	if node.type == "dev" then
		if not CeroSecOS.isNull(node) then return false, where .. ": bad type" end
		return true
	end

	tally.nodes = tally.nodes + 1
	if tally.nodes > tally.max then return false, "too many nodes" end

	if node.type == "file" then
		if type(node.data) ~= "string" then return false, where .. ": bad data" end
		-- The biggest a file on this machine can be, which is NOT the 4096 the
		-- write path stops at: an account's ~/.sh_history is exempt from the disk
		-- quota and grows to HISTORY_BYTES, and a history that is renamed keeps
		-- its bytes -- an ordinary file, bigger than any write could have made
		-- it. Refusing that here would cost the player his whole machine for a
		-- `mv` the machine itself allowed.
		if #node.data > CeroSecOS.HISTORY_BYTES then return false, where .. ": file too large" end
		-- A blob handed back by the game never went through setData, so the
		-- printable rule is re-checked here rather than assumed.
		if CeroSecOS.hasControlBytes(node.data) then return false, where .. ": invalid characters" end
		-- And nothing here about the 32K. Being over the disk quota is a state a
		-- machine can be IN -- rename a full history and it is over at once --
		-- and the answer to it is that every further write says "disk full"
		-- until room is made, not that the save file is corrupt and the machine
		-- is thrown away. The quota lives on the write path; validate only asks
		-- whether the core can run on this at all.
		return true
	end

	-- A symbolic link: a path, as text, and never empty. An empty one would be a
	-- link the walk resolves to the directory it sits in, which is not a thing a
	-- link can mean, and `ln` refuses to make one -- so a state carrying one came
	-- from somewhere nobody can name and is not something to run on.
	if node.type == "link" then
		if type(node.target) ~= "string" then return false, where .. ": bad target" end
		if node.target == "" then return false, where .. ": bad target" end
		if #node.target > CeroSecOS.MAX_LINK_BYTES then
			return false, where .. ": target too long"
		end
		if CeroSecOS.hasControlBytes(node.target) then
			return false, where .. ": invalid characters"
		end
		return true
	end

	if node.type ~= "dir" then return false, where .. ": bad type" end
	if type(node.children) ~= "table" then return false, where .. ": bad children" end
	local names = CeroSecOS.childNames(node)
	if #names > CeroSecOS.MAX_DIR_ENTRIES then return false, where .. ": directory full" end
	for i = 1, #names do
		local name = names[i]
		if not CeroSecOS.isValidFileName(name) then return false, where .. "/" .. name .. ": invalid name" end
		local ok, reason = checkNode(node.children[name], where .. "/" .. name, depth + 1, tally)
		if not ok then return false, reason end
	end
	return true
end

-- ok, reason.
function CeroSecOS.validate(state)
	if type(state) ~= "table" then return false, "state is not a table" end
	local ok, reason = checkPlain(state, {}, "state")
	if not ok then return false, reason end

	if state.v ~= CeroSecOS.STATE_VERSION then return false, "bad version" end
	-- Which contents the machine was built with. A state that has never been
	-- through upgradeSystem has none, and upgradeSystem runs before this gate on
	-- every load -- so reaching here without one means a blob nothing brought up
	-- to date, and that is not something to run on.
	if type(state.sysv) ~= "number" then return false, "bad system version" end
	if type(state.hostname) ~= "string" or not CeroSecOS.isValidName(state.hostname) then
		return false, "bad hostname"
	end
	if type(state.fs) ~= "table" then return false, "bad fs" end
	if state.fs.type ~= "dir" then return false, "fs root is not a directory" end
	local fsOk, fsReason =
		checkNode(state.fs, "", 0, { nodes = 0, max = CeroSecOS.MAX_NODES })
	if not fsOk then return false, fsReason end

	-- The cables this machine has run, when it has run any: a list of squares, and
	-- the shape of it is the engine's because the key is in the state (see
	-- CeroSecOS.linksOk). Absent on every machine saved before the key existed and
	-- on every machine nobody has run a cable from, which is what "no cables" is.
	local linksOk, linksWhy = CeroSecOS.linksOk(state.links)
	if not linksOk then return false, linksWhy end

	-- The disk in the drive, when there is one.
	if state.floppy ~= nil then
		local dOk, dReason = CeroSecOS.validateDisk(state.floppy)
		if not dOk then return false, dReason end
	end

	-- The accounts are a FILE now, so this is all validate has to say about
	-- them: that the file is there and that it is root's. What is in it is the
	-- parser's business and nobody else's -- a passwd full of malformed lines is
	-- a machine nobody can log in to, which the boot check calls "no operating
	-- system" and the BIOS repairs. It is not a state the core cannot run on.
	local passwd = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	if passwd == nil then return false, "no " .. CeroSecOS.PASSWD_PATH end
	if passwd.type ~= "file" then return false, CeroSecOS.PASSWD_PATH .. ": not a file" end
	if passwd.owner ~= "root" then return false, CeroSecOS.PASSWD_PATH .. ": not root's" end
	return true
end

-- One disk, on its own.
--
-- It is not part of state.fs and is never counted against the machine's quota
-- (see CeroSecOSDisk.lua), so it is walked on its own here, against its OWN node
-- ceiling: a disk forged past what a floppy holds is a disk the write path would
-- never have made and is not something to run on.
--
-- An UNFORMATTED disk is a disk with no filesystem on it -- the normal state of a
-- new one out of the box -- so a missing tree is not a fault.
--
-- Two questions, and which one is asked is `bounded`:
--
--   * the BOOT GATE (validate, below) asks the SHAPE -- whether the core can run
--     on this disk at all. It does not ask the ceilings, for the reason the
--     machine's own drive is not asked either: being over a quota is a state a
--     filesystem can be IN, and the answer to it is that the next write says "disk
--     full" until somebody makes room. A boot gate that refused would cost the
--     player his whole COMPUTER for a disk he could have fixed with one `rm` --
--     osState's refusal is sticky and the firmware repair does not reach into the
--     drive.
--   * the SLOT (CeroSecOS.diskFromData) asks the CEILINGS as well, because what
--     arrives there is an item's modData -- a table off a save file, or, on a
--     server, off a client -- and a walk over it is paid for on every command from
--     then on. A disk of four kilobytes costs the boot gate nothing; a forged one
--     of eight megabytes is the same walk, on every keystroke, on the server.
--
-- Which leaves the obvious trap, and it is closed at the OTHER end. A machine that
-- runs on a disk must be able to hand it out, or the player is left holding one no
-- slot in the world will take, with nothing on the screen to say why. So the
-- refusal is made where he can still do something about it: a disk the slot would
-- not take does not leave the drive (SCeroSecObject:ejectDisk). It is still in the
-- machine, `df` still says what is wrong with it, and one `rm` is the way out.
-- Nothing the write path can do makes such a disk; this is the belt under that.
--
-- The ceilings are the DISK's, per file included: MAX_FILE_BYTES and not the
-- HISTORY_BYTES a node on the hard drive may reach, because that larger number is
-- the history exemption's and the exemption belongs to the hard drive alone (see
-- CeroSecOS.historyAppend). Nothing on a disk is ever exempt from anything.
--
-- What a disk is ALLOWED TO BE MADE OF -- its keys, and the fields of every node
-- on it -- with nothing read that is not a key.
--
-- Split out and asked FIRST, of the table the game handed over and before a byte of
-- it is copied, because that copy is what a payload is paid for in: four hundred
-- thousand keys under a name nobody here has ever written cost half a second to
-- walk and one comparison to refuse. Everything in here refuses on the first thing
-- it finds and never descends past it.
--
-- Three rules:
--
--   * the disk's own keys. The ceilings are asked of disk.fs, so anything hung on
--     the disk beside it was weighed by nothing at all: a megabyte under a name of
--     its own rode into state.floppy, into the save file and out to every client,
--     invisible to `df` and to `ls` and undeletable by any command.
--     CeroSecOS.DISK_KEYS is the whole of what a disk owns, and a key that is not
--     one of them is a refusal and not a value to drop quietly -- the same rule the
--     copy runs on, for the same reason: what it is is somebody's work, or
--     somebody's payload, and either way it is not ours to carry unlooked at. Asked
--     of a BLANK disk too, which is the shape that made this half a rule the first
--     time: a floppy off a shelf has no filesystem, the gate answered "nothing to
--     check" and took whatever else was written on it, and then one `newfs` gave it
--     a filesystem and the disk could never come out again.
--
--     This is asked of a disk RECORD -- a table this engine made, out of the keys a
--     disk owns. It is NOT asked of an item's modData: that table belongs to the
--     game, which writes `customName` in it itself, and the keys of ours are picked
--     out of it before anything here sees them (CeroSecOS.diskFromData's ownKeysOf).
--     So a stranger's key reaching this rule is a record somebody built wrong, and
--     the refusal names the key, because the one that cost a release was read off a
--     log line that did not.
--   * the SHAPE of its tree -- how deep it goes, how wide one directory is, and
--     what every node on it is made of (CeroSecOS.diskShape). That last is where
--     the other half of the first rule was hiding: checkNode reads the fields it
--     knows for a node's own kind and ignores every other key, and subtreeUsage
--     weighs `data` and `target` and descends only into a directory's children --
--     so junk on a node, and a whole tree hung under a FILE node, were
--     unvalidated, unweighed and uncounted.
--
-- A key, as a refusal may print it. The name is what makes the next one of these
-- readable off a log line instead of reproducible only in game, and it goes onto a
-- screen -- so a key that is not a short printable name is named by what it is and
-- not quoted at all: nothing shapes a line on this machine's glass except the
-- machine.
local function fieldName(key)
	if type(key) == "number" then return "'" .. tostring(key) .. "'" end
	if type(key) ~= "string" then return "of type " .. type(key) end
	if #key > CeroSecOS.LABEL_MAX or CeroSecOS.hasControlBytes(key) then
		return "of " .. #key .. " bytes"
	end
	return "'" .. key .. "'"
end

-- ok, reason.
function CeroSecOS.diskFieldsOk(disk)
	if type(disk) ~= "table" then return false, "floppy: not a disk" end
	for key in pairs(disk) do
		local known = false
		for i = 1, #CeroSecOS.DISK_KEYS do
			if key == CeroSecOS.DISK_KEYS[i] then known = true end
		end
		-- And a name an OLDER disk owned, which a migration is on its way to taking
		-- off: this gate runs before any step could, so a step that renamed a key
		-- would otherwise never see a disk carrying the old name
		-- (CeroSecOS.DISK_LEGACY_KEYS).
		for i = 1, #CeroSecOS.DISK_LEGACY_KEYS do
			if key == CeroSecOS.DISK_LEGACY_KEYS[i] then known = true end
		end
		if not known then
			return false, "floppy: unknown field " .. fieldName(key)
		end
	end
	if type(disk.fs) ~= "table" then return true end
	local at, why = CeroSecOS.diskShape(disk.fs)
	if at ~= nil then return false, "floppy" .. at .. ": " .. why end
	return true
end

-- ok, reason.
function CeroSecOS.validateDisk(disk, bounded)
	if type(disk) ~= "table" then return false, "floppy: not a disk" end
	if disk.v ~= CeroSecOS.FLOPPY_VERSION then return false, "floppy: bad version" end

	-- The FIELD rules come first, and they are asked of the table the game handed
	-- over rather than of a copy of it: see CeroSecOS.diskFieldsOk.
	if bounded then
		local fOk, fReason = CeroSecOS.diskFieldsOk(disk)
		if not fOk then return false, fReason end
	end

	local ok, reason = checkPlain(disk, {}, "floppy")
	if not ok then return false, reason end
	if disk.label ~= nil then
		if type(disk.label) ~= "string" then return false, "floppy: bad label" end
		if #disk.label > CeroSecOS.LABEL_MAX then return false, "floppy: bad label" end
		if CeroSecOS.hasControlBytes(disk.label) then return false, "floppy: bad label" end
	end
	if disk.fs == nil then return true end
	if type(disk.fs) ~= "table" or disk.fs.type ~= "dir" then
		return false, "floppy: root is not a directory"
	end
	local dOk, dReason =
		checkNode(disk.fs, "", 0, { nodes = 0, max = CeroSecOS.MAX_NODES })
	if not dOk then
		-- checkNode's reasons are "<path>: <why>", and the path is relative to the
		-- disk's own root, so the word "floppy" goes straight in front of it. Two of
		-- them are not paths at all ("too many nodes"), and those want the separator
		-- putting in -- which is what "floppytoo many nodes" was.
		local head = string.sub(dReason, 1, 1)
		if head ~= ":" and head ~= "/" then dReason = ": " .. dReason end
		return false, "floppy" .. dReason
	end
	if not bounded then return true end

	-- The node ceiling is not asked here: CeroSecOS.diskShape carries the count and
	-- stops the walk on it, which is the whole point of counting there -- asked at
	-- this end, the answer arrives after the tree has been walked three times and
	-- copied once.
	local _, bytes = CeroSecOS.subtreeUsage(disk.fs)
	if bytes > CeroSecOS.FLOPPY_BYTES then return false, "floppy: disk full" end
	local big = CeroSecOS.tooBigOn(disk.fs)
	if big ~= nil then return false, "floppy" .. big .. ": file too large" end
	return true
end

--
-- Migration
--
-- A machine is a table in gos_cerosec.bin, written by a build that is not this
-- one. CeroSecOS.STATE_VERSION is the shape this build reads, and
-- CeroSecOS.MIGRATIONS is what turns an older shape into it: MIGRATIONS[n] takes
-- a state that is at n - 1 and leaves it at n, so a v1 state meeting a v4 build
-- walks 2, then 3, then 4, and keeps everything on it.
--
-- Three rules, and the first is what this section exists for:
--
--   * a state OLDER than this build is MIGRATED and never thrown away. It used to
--     be thrown away: every version that was not the current one became a fresh
--     machine -- the filesystem, the accounts, the disk in the drive, all of it --
--     so the first bump of STATE_VERSION would have wiped every computer in every
--     save. Which is exactly why the number had never been moved, and why nothing
--     that belonged in the SHAPE could ever be changed.
--   * a state NEWER than this build is REFUSED, and not touched. The player has
--     put an older mod back under a save a later one wrote, and there is nothing
--     here that can read it -- a migration runs forwards only. So the bytes stay
--     exactly as they are, the machine says so on its screen and the switch at the
--     back of the case still works: putting the newer mod back is the whole of the
--     repair, and a build that "fixed" a state it could not read would have
--     destroyed a save its own author could still open.
--   * a state with NO version, or one below the oldest step there is, is a fresh
--     machine. That is what a pre-release save is -- nothing shipped that wrote
--     one -- and it is the one case where something is lost.
--
-- Every step is IDEMPOTENT: run twice on one table it leaves it as the first run
-- did. Nothing in production depends on that -- the version moves as each step
-- lands -- but tests/migrate_test.lua holds every step to it, because a step that
-- is not idempotent is a step whose second half nobody can read.
--
-- And a step never asks the WORLD anything. It is handed a table and nothing else:
-- which building a machine stands in, what is on its square and who is logged in
-- at it are not facts a save file holds, and a step that needed one of them could
-- not run for a machine whose chunk nobody has loaded -- which is most of them.
-- The top-ups that DO need the world stay where the square is answerable and are
-- called from there: the address, the telephone exchange and the premises name in
-- CeroSecNet.identify, the devices under /dev in the scheduler. The mount table
-- and /dev are swept on the way in by SCeroSecObject:osState, once, beside this.
--
CeroSecOS.MIGRATIONS = {}

-- The oldest shape the chain can start from: below this there is no step to run,
-- because nothing was ever released that wrote one.
CeroSecOS.OLDEST_STATE_VERSION = 1

-- The quota exemption used to be a flag on the node (`nq`), written by the one
-- function that appended to a history and read by the usage count. It is a PATH
-- now (CeroSecOS.exemptPaths) and nothing reads the field any more, so a machine
-- saved while it existed carries a field that means nothing.
local function dropQuotaFlags(node)
	if type(node) ~= "table" then return end
	node.nq = nil
	if type(node.children) ~= "table" then return end
	for _, child in pairs(node.children) do dropQuotaFlags(child) end
end

-- 2: the accounts file, and the quota flags.
--
-- Both of these were repaired on EVERY read of the state, and neither could ever
-- stop being: there was no number anywhere that could say the repair had already
-- happened, so `nq` was swept off every node of every machine for the rest of the
-- save's life and the accounts table was looked for on every command.
--
--   * the accounts. They lived in a table on the state (state.users) and their
--     passwords were once in clear; /etc/passwd is the truth now, and the file
--     wins over the table wherever a state somehow has both
--     (CeroSecOS.migrateUsers, which also fills a /bin such a machine never had).
--   * the quota exemption, above.
--
-- Idempotent by construction: migrateUsers returns at once when there is no
-- table, and a walk that clears a field that is already nil clears nothing.
CeroSecOS.MIGRATIONS[2] = function(state)
	CeroSecOS.migrateUsers(state)
	dropQuotaFlags(state.fs)
end

-- One disk, brought up to this build. Its own chain, against its own number
-- (CeroSecOS.FLOPPY_VERSION): a floppy is carried between machines and outlives any
-- one of them, so what shape it is in is its own fact and not the machine's.
--
--   disk, nil            walked, and ready for the gate.
--   nil, "newer"         written by a LATER build: refused, and not touched.
--   nil, "bad version"   no version, or older than the oldest step there is.
--
-- The last one is NOT a blank disk handed back. A machine that formatted a floppy it
-- could not read would be a machine that wipes somebody's work to make it fit, so a
-- disk the chain cannot read is left exactly as it is and refused where it stands --
-- at the slot with a reason on the screen (CeroSecOS.diskFromData), or by the gate
-- for one already in the drive, which is what happened to such a disk before there
-- was a chain at all.
function CeroSecOS.migrateDisk(disk)
	if type(disk) ~= "table" then return nil, "floppy: not a disk" end
	local v = disk.v
	if type(v) == "number" and v > CeroSecOS.FLOPPY_VERSION then return nil, "newer" end
	if type(v) ~= "number" or v ~= math.floor(v)
			or v < CeroSecOS.OLDEST_FLOPPY_VERSION then
		return nil, "floppy: bad version"
	end
	for n = v + 1, CeroSecOS.FLOPPY_VERSION do
		local step = CeroSecOS.DISK_MIGRATIONS[n]
		if type(step) ~= "function" then return nil, "floppy: bad version" end
		step(disk)
		disk.v = n
	end
	return disk, nil
end

-- A saved state, brought up to this build.
--
--   state, nil     ready for the gate: the same table, migrated where it lies, or
--                  a fresh machine where there was nothing to keep.
--   nil, "newer"   refused and NOT touched -- see the head of this section.
--
-- The caller validates, and this deliberately does not: a state of a version it
-- CAN read is kept even when the gate then refuses it, because the way back from a
-- filesystem the core cannot run on is the BIOS (SCeroSecObject:restoreOS), which
-- keeps /home -- and handing back a fresh machine instead would be this function
-- throwing away the very thing it exists to save. It used to do exactly that, and
-- it was invisible because the only states that ever reached it were junk.
function CeroSecOS.migrate(state, hostname)
	if type(state) ~= "table" then return CeroSecOS.newState(hostname), nil end

	local v = state.v
	if type(v) == "number" and v > CeroSecOS.STATE_VERSION then return nil, "newer" end
	-- And the disk in the drive, asked FIRST -- before a single step writes anything
	-- -- because "not touched" has to mean it. A floppy a later build wrote makes the
	-- whole machine unreadable and gets the same answer for the same reason: nothing
	-- here can read what is in the slot, and putting the newer mod back is the repair.
	local inDrive = state.floppy
	if type(inDrive) == "table" and type(inDrive.v) == "number"
			and inDrive.v > CeroSecOS.FLOPPY_VERSION then
		return nil, "newer"
	end
	if type(v) ~= "number" or v ~= math.floor(v)
			or v < CeroSecOS.OLDEST_STATE_VERSION then
		return CeroSecOS.newState(hostname), nil
	end

	for n = v + 1, CeroSecOS.STATE_VERSION do
		local step = CeroSecOS.MIGRATIONS[n]
		-- A hole in the chain, which is not a thing a shipped build can have: the
		-- bench walks every number from the oldest to this one and goes red on a
		-- missing step (tests/migrate_test.lua). Reached anyway, the honest answer
		-- is a fresh machine and not a half-migrated one -- a state left between two
		-- shapes is a state nothing can ever read again.
		if type(step) ~= "function" then return CeroSecOS.newState(hostname), nil end
		step(state)
		-- Moved as each step lands and not once at the end, so a state that dies
		-- half way through -- a step that errors, a server killed under it -- comes
		-- back at the version it really reached and walks the rest on the next load.
		state.v = n
	end

	-- And the disk in the drive, walked on its own number. Here and not at the slot
	-- because a disk RIDES INSIDE the state: one that was in the drive when the game
	-- was saved comes back with the machine and never passes CeroSecOS.diskFromData
	-- again. A newer one was refused above; one the chain cannot read is left exactly
	-- as it is for the gate to refuse, which is what happened to it before.
	if type(state.floppy) == "table" then CeroSecOS.migrateDisk(state.floppy) end

	-- And the CONTENTS, which is the other number and is not part of the chain: a
	-- machine saved before this build has neither the executables it added nor the
	-- files it seeds, and neither is damage (CeroSecOS.upgradeSystem).
	CeroSecOS.upgradeSystem(state)
	return state, nil
end
