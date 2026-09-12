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
	root.children.home.children.admin = CeroSecOS.newDir("admin", CeroSecOS.HOME_MODE)
	root.children.root = CeroSecOS.newDir("root", 700)
	root.children.dev = CeroSecOS.newDir("root", 755)
	root.children.etc = CeroSecOS.newDir("root", 755)
	root.children.etc.children.hostname = CeroSecOS.newFile("root", 644, hostname)
	root.children.etc.children.motd = CeroSecOS.newFile("root", 644, CeroSecOS.MOTD)
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
	return state
end

--
-- Validation.
--

-- Everything the game stores must be a plain nested table of strings, numbers
-- and booleans: no functions, no userdata, no metatables, no cycles.
local function checkPlain(value, seen, where)
	local t = type(value)
	if t == "string" or t == "number" or t == "boolean" then return true end
	if t ~= "table" then return false, where .. ": " .. t .. " is not storable" end
	if getmetatable(value) ~= nil then return false, where .. ": has a metatable" end
	if seen[value] then return false, where .. ": cycle" end
	seen[value] = true
	for k, v in pairs(value) do
		local kt = type(k)
		if kt ~= "string" and kt ~= "number" then return false, where .. ": key of type " .. kt end
		local ok, reason = checkPlain(v, seen, where .. "." .. tostring(k))
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
-- Asked twice: by validate below, of the disk that is in the drive, and by the
-- INSERT, of the disk that is about to go in (SCeroSecSystem). Those are the same
-- question and this is the one place it is answered, so a disk a machine would
-- refuse to boot with is a disk no slot will take.
--
-- ok, reason.
function CeroSecOS.validateDisk(disk)
	if type(disk) ~= "table" then return false, "floppy: not a disk" end
	local ok, reason = checkPlain(disk, {}, "floppy")
	if not ok then return false, reason end
	if disk.v ~= CeroSecOS.FLOPPY_VERSION then return false, "floppy: bad version" end
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
		checkNode(disk.fs, "", 0, { nodes = 0, max = CeroSecOS.FLOPPY_NODES })
	if not dOk then return false, "floppy" .. dReason end
	-- And the bytes, which checkNode does not ask about for the machine's own drive
	-- (being over the quota is a state a machine can be IN). A floppy is different:
	-- nothing on this machine can put a disk over its ceiling, so a disk that is
	-- over one did not come from here.
	local _, bytes = CeroSecOS.subtreeUsage(disk.fs)
	if bytes > CeroSecOS.FLOPPY_BYTES then return false, "floppy: disk full" end
	return true
end

-- The quota exemption used to be a flag on the node (`nq`), written by the one
-- function that appended to a history and read by the usage count. It is a PATH
-- now (CeroSecOS.exemptPaths) and nothing reads the field any more, so a machine
-- saved while it existed carries a field that means nothing: taken off here, on
-- the way in, rather than left to sit in the save file forever.
local function dropQuotaFlags(node)
	if type(node) ~= "table" then return end
	node.nq = nil
	if type(node.children) ~= "table" then return end
	for _, child in pairs(node.children) do dropQuotaFlags(child) end
end

-- Anything the game hands back becomes a v1 state. Today there is no older
-- schema, so nil and junk alike become a fresh machine; a v1 state passes
-- through untouched.
function CeroSecOS.migrate(state, hostname)
	if type(state) == "table" and state.v == CeroSecOS.STATE_VERSION then
		-- The accounts first: a machine saved before this rung carries them in
		-- a table on the state, and one saved before that carries their
		-- passwords in clear. validate refuses both. Repairing before the gate
		-- is what keeps such a machine's filesystem instead of throwing it away.
		CeroSecOS.migrateUsers(state)
		dropQuotaFlags(state.fs)
		-- And a mount naming a drive with nothing in it, which is a mount nothing
		-- could walk through. Before the gate, like the rest of this.
		CeroSecOS.checkMounts(state)
		-- And then the contents: a machine saved before this build has neither
		-- the executables it added nor the files, and neither is damage.
		CeroSecOS.upgradeSystem(state)
		local ok = CeroSecOS.validate(state)
		if ok then return state end
	end
	return CeroSecOS.newState(hostname)
end
