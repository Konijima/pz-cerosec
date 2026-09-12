--
-- CeroSec OS core: the floppy drive, and the second filesystem.
--
-- A 3.5-inch disk goes into the slot on the front of the case. It is an ITEM in
-- the world -- four colours of it -- and what is written on it lives in the
-- item, not in the computer: carry it to another machine and everything on it is
-- still there, under the same names and owned by the same accounts.
--
--   admin@ksp-04-11:~$ newfs /dev/fd0
--   /dev/fd0: 4096 bytes, 32 inodes
--   admin@ksp-04-11:~$ mount /dev/fd0 /mnt
--   admin@ksp-04-11:~$ cp notes.txt /mnt
--   admin@ksp-04-11:~$ umount /mnt
--
-- Three pieces, and they are deliberately three:
--
--   * THE DISK. state.floppy is the disk in the drive, or nothing at all when
--     the drive is empty. Its shape is the shape of the item's own modData,
--     because it IS the item's modData while the disk is inserted: { v, fs,
--     label }, where fs is a directory node and its absence is an unformatted
--     disk. Nothing else about a floppy is written anywhere.
--
--   * THE DEVICE. /dev/fd0 is mounted on /dev for the length of one command,
--     exactly as a light switch is (CeroSecOS.mountDev), and only while there is
--     a disk in the drive. So a saved machine never carries one, and a drive
--     nobody has put a disk into has no device file to talk to.
--
--   * THE MOUNT. state.mounts is what `mount` with no arguments prints and what
--     the filesystem walk crosses: a directory that is a mount point is the
--     ROOT OF THE DISK and not the directory on the hard drive underneath it,
--     which is what a mount has meant since there were two of them. The
--     crossing is done in CeroSecOS.getNode and nowhere else -- the same place a
--     symbolic link is followed, and for the same reason: no command had to
--     learn there is a second filesystem on the machine.
--
-- What the two filesystems do NOT share is their ceilings. The floppy holds
-- FLOPPY_BYTES and FLOPPY_NODES of its own, the hard disk holds its own, and
-- neither is ever counted against the other: a full floppy is a `df` that has not
-- moved on hda, and a full hard disk is a floppy a player can still write to.
-- That falls out of the disk living on state.floppy rather than inside state.fs --
-- the quota walk (CeroSecOS.usage) physically cannot see it -- and the write path
-- picks the ceiling by asking which filesystem the PATH is on
-- (CeroSecOS.fsFor).
--
-- A mount does not survive the power going off. Every session ends when a
-- computer is switched off and so does every mount, which is what a reboot does
-- on any machine; the disk stays in the drive, because that is a thing in the
-- world and not a thing in memory.
--

CeroSecOS = CeroSecOS or {}
CeroSecOS.commands = CeroSecOS.commands or {}

--
-- The drive
--

-- The device's name, and the path it is mounted at. One drive, because the case
-- has one slot in it.
CeroSecOS.FD_NAME = "fd0"
CeroSecOS.FD_PATH = CeroSecOS.DEV_PATH .. "/" .. CeroSecOS.FD_NAME

-- The kind the core knows it by. It is in CeroSecOS.DEV_VALUES with an EMPTY
-- vocabulary, exactly as a motion sensor is: there is no word a survivor could
-- write to a raw disk, and every one he tries is "fd0: invalid value".
CeroSecOS.FD_KIND = "floppy"

-- rw for root and for the sudo group, nothing for anybody else -- DEV_MODE, the
-- mode every device on this machine is born at.
--
-- The `w` bit is not decoration and does not promise a redirect: it is what
-- `newfs` asks for, the way newfs on a real machine opens the device for writing,
-- and the `r` bit is what `mount` asks for to read the super block. So the mode
-- on this node is the whole of who may format a disk and who may mount one --
-- there is no second list of names anywhere -- and `chmod 666 /dev/fd0` really
-- does hand the drive to the whole office.
CeroSecOS.FD_MODE = CeroSecOS.DEV_MODE

-- What the drive says about itself when it is read. A device on this machine
-- answers with its state -- `cat /dev/light0` is "on" -- so the drive answers
-- with what is in it: a disk nobody has formatted, one that is ready, or one that
-- is mounted somewhere. It is not the disk's CONTENTS: those are read through the
-- mount, which is the only way a filesystem was ever read.
--
-- "blank" and not "unformatted", and the reason is the column it has to fit in:
-- `ls -l /dev` puts a device's state last and the widest one on the machine
-- ("barricaded", ten characters) lands exactly on column 60 (see
-- CeroSecOS.devLine). An eleventh character would be a listing that wraps. It is
-- also the word a box of them was sold under.
CeroSecOS.FD_BLANK = "blank"
CeroSecOS.FD_READY = "ready"
CeroSecOS.FD_MOUNTED = "mounted"

-- Where a disk is mounted on a machine nobody has told otherwise. Shipped empty
-- and root's at 755, which is what /mnt has been on every Unix that had one.
CeroSecOS.MNT_NAME = "mnt"
CeroSecOS.MNT_PATH = "/" .. CeroSecOS.MNT_NAME
CeroSecOS.MNT_MODE = 755

-- The filesystem type, in the one word `mount` prints and df's own listing
-- leans on. There is one on this machine and it is the one 4.4BSD's disks wore.
CeroSecOS.FS_TYPE = "ufs"

--
-- The disk
--

-- The schema of what is written on a floppy, which is the schema of the item's
-- modData. Separate from CeroSecOS.STATE_VERSION on purpose: a disk is carried
-- between machines and outlives any one of them, so what shape it is in is its
-- own fact.
CeroSecOS.FLOPPY_VERSION = 1

-- How long a volume label may be. Eleven bytes, which is what a DOS volume label
-- held in 1993 and what the sticker on the front of a 3.5-inch disk had room for.
-- Nothing reads a label but the drive's own listing today; it is here because a
-- disk with no name on it is a disk nobody can tell from the other three in the
-- drawer.
CeroSecOS.LABEL_MAX = 11

-- A blank, unformatted disk: no filesystem at all. What a new one out of the box
-- is, and what `newfs` is for.
function CeroSecOS.newFloppy(label)
	local disk = { v = CeroSecOS.FLOPPY_VERSION }
	if type(label) == "string" and label ~= "" and #label <= CeroSecOS.LABEL_MAX then
		disk.label = label
	end
	return disk
end

-- The root directory a `newfs` leaves behind.
--
-- Owned by whoever ran it, at 755. On a real machine newfs leaves the root
-- directory root's, because only root could ever have run newfs -- here the sudo
-- group may (that is what the `w` bit on /dev/fd0 means), and a disk whose root
-- directory belonged to an account that may not write it would be a disk nobody
-- could put anything on. So the owner is the account that formatted it, which is
-- the one reading of "root's disk" that is true of every machine this can run on.
function CeroSecOS.newFloppyRoot(owner, now)
	return CeroSecOS.newDir(owner or "root", 755, now)
end

-- The disk in the drive, or nil when the drive is empty. The ONE place
-- state.floppy is read, so a state carrying junk at that name is a machine with
-- an empty drive and never a machine with a broken one.
function CeroSecOS.floppyOf(state)
	if type(state) ~= "table" then return nil end
	local disk = state.floppy
	if type(disk) ~= "table" then return nil end
	return disk
end

-- The root of the filesystem on the disk in the drive, or nil: no disk, or a disk
-- nobody has formatted.
function CeroSecOS.floppyRoot(state)
	local disk = CeroSecOS.floppyOf(state)
	if disk == nil then return nil end
	local root = disk.fs
	if type(root) ~= "table" or root.type ~= "dir" or type(root.children) ~= "table" then
		return nil
	end
	return root
end

--
-- The mount table
--

-- Every mount on the machine, or nil when there is none. nil and not an empty
-- table: what goes into the save file is a field or nothing, never a table that
-- is there to say there is nothing in it.
function CeroSecOS.mountTable(state)
	if type(state) ~= "table" then return nil end
	local mounts = state.mounts
	if type(mounts) ~= "table" or #mounts == 0 then return nil end
	return mounts
end

-- The mount on exactly this directory, and where in the table it sits.
function CeroSecOS.mountAt(state, dir)
	local mounts = CeroSecOS.mountTable(state)
	if mounts == nil then return nil end
	for i = 1, #mounts do
		local m = mounts[i]
		if type(m) == "table" and m.dir == dir then return m, i end
	end
	return nil
end

-- The mount a path is ON: the one whose directory is the path itself or an
-- ancestor of it. The longest match wins, so a mount inside a mount would answer
-- for its own subtree -- there is one mount on this machine today and the rule
-- costs nothing, and a rule that answered the shortest match would be a rule that
-- had to be rewritten the day there are two.
function CeroSecOS.mountFor(state, abs)
	local mounts = CeroSecOS.mountTable(state)
	if mounts == nil or type(abs) ~= "string" then return nil end
	local best = nil
	for i = 1, #mounts do
		local m = mounts[i]
		if type(m) == "table" and type(m.dir) == "string"
				and CeroSecOS.isInside(abs, m.dir) then
			if best == nil or #m.dir > #best.dir then best = m end
		end
	end
	return best
end

-- The root node a mount point stands for, or nil when the mount names a drive
-- that has nothing in it. Asked by the walk at every component, so it is one
-- table lookup and one type test and nothing else.
function CeroSecOS.mountedRoot(state, mount)
	if type(mount) ~= "table" then return nil end
	if mount.dev ~= CeroSecOS.FD_NAME then return nil end
	return CeroSecOS.floppyRoot(state)
end

-- Add one. The caller has checked everything; this is the bookkeeping.
function CeroSecOS.addMount(state, dev, dir)
	if type(state.mounts) ~= "table" then state.mounts = {} end
	state.mounts[#state.mounts + 1] =
		{ dev = dev, dir = dir, type = CeroSecOS.FS_TYPE }
	return state.mounts[#state.mounts]
end

-- Take one away. true when there was one there.
function CeroSecOS.dropMount(state, dir)
	local _, at = CeroSecOS.mountAt(state, dir)
	if at == nil then return false end
	table.remove(state.mounts, at)
	-- A field or nothing: an empty table in the save file is a table that grows
	-- one every time somebody mounts and unmounts a disk.
	if #state.mounts == 0 then state.mounts = nil end
	return true
end

-- Everything unmounted. What the power going off does, and what an eject does to
-- the one mount the ejected disk was under.
function CeroSecOS.unmountAll(state)
	if type(state) ~= "table" then return false end
	if state.mounts == nil then return false end
	state.mounts = nil
	return true
end

-- The belt under every mount on a state the game has just handed back: a mount
-- whose device has no formatted disk behind it is a mount that cannot be walked
-- through, and it is dropped rather than left to answer "no such file" about
-- every path under it for ever.
--
-- A save file can hold one: a computer whose disk was taken out by a hand that
-- never reached the eject path, a blob somebody forged. true when it changed
-- something.
function CeroSecOS.checkMounts(state)
	local mounts = CeroSecOS.mountTable(state)
	if mounts == nil then return false end
	local kept, dropped = {}, false
	for i = 1, #mounts do
		local m = mounts[i]
		if type(m) == "table" and type(m.dir) == "string"
				and CeroSecOS.mountedRoot(state, m) ~= nil then
			kept[#kept + 1] = m
		else
			dropped = true
		end
	end
	if not dropped then return false end
	if #kept == 0 then kept = nil end
	state.mounts = kept
	return true
end

--
-- Which filesystem a path is on
--
-- Every ceiling on this machine except two is the MACHINE's: a name is 32
-- characters and a file is 4096 bytes wherever it is written, because those are
-- facts about the software. The two that are the DISK's are how many bytes and
-- how many nodes it holds, and those are what this answers.
--
-- The descriptor is built fresh and never cached: what the answer depends on is
-- the mount table, and the mount table changes under a command's feet the moment
-- that command is `umount`.
--

-- dev, the mount point, the root node, and the two ceilings.
function CeroSecOS.fsFor(state, abs)
	local mount = CeroSecOS.mountFor(state, abs)
	if mount ~= nil then
		local root = CeroSecOS.mountedRoot(state, mount)
		if root ~= nil then
			return { dev = mount.dev, at = mount.dir, root = root,
				bytes = CeroSecOS.FLOPPY_BYTES, nodes = CeroSecOS.FLOPPY_NODES }
		end
	end
	return { dev = CeroSecOS.DISK_NAME, at = "/", root = state.fs,
		bytes = CeroSecOS.MAX_TOTAL_BYTES, nodes = CeroSecOS.MAX_NODES }
end

-- What is on that filesystem right now: nodes, and the bytes its quota counts.
--
-- The hard disk's answer is CeroSecOS.usage's, exemptions and all -- a history
-- and a mailbox are the MACHINE writing about itself and do not fill its drive.
-- A floppy's is the plain weight of its tree: nothing exempt is ever on one (every
-- exempt path is under /home, /root or /var, and none of those is a mount point),
-- and a rule that pretended otherwise would be a rule nothing could reach.
function CeroSecOS.fsUsage(state, fs)
	if fs.at == "/" then return CeroSecOS.usage(state) end
	return CeroSecOS.subtreeUsage(fs.root)
end

--
-- The device file
--

-- What the drive's state reads as. Asked at mount time, so it is the truth about
-- the moment the command was typed.
function CeroSecOS.fdState(state)
	if CeroSecOS.floppyRoot(state) == nil then return CeroSecOS.FD_BLANK end
	if CeroSecOS.fdMount(state) ~= nil then return CeroSecOS.FD_MOUNTED end
	return CeroSecOS.FD_READY
end

-- The mount the drive is under, or nil. The drive has one disk in it, so a mount
-- naming fd0 is THE mount of this drive wherever its directory is.
function CeroSecOS.fdMount(state)
	local mounts = CeroSecOS.mountTable(state)
	if mounts == nil then return nil end
	for i = 1, #mounts do
		local m = mounts[i]
		if type(m) == "table" and m.dev == CeroSecOS.FD_NAME then return m end
	end
	return nil
end

-- The drive's node, or nil when there is no disk in it.
--
-- Its mode is the MACHINE's and not the disk's -- the drive is bolted to the case
-- and a chmod on it outlives the disk that happened to be in it when it was typed
-- -- so it is remembered on the state (state.fdmode) between commands, the way the
-- world's devices have their modes remembered in the server's own book.
function CeroSecOS.newFloppyDev(state)
	local disk = CeroSecOS.floppyOf(state)
	if disk == nil then return nil end
	local mode = state.fdmode
	if type(mode) ~= "number" or mode < 0 or mode > 777 or mode ~= math.floor(mode) then
		mode = CeroSecOS.FD_MODE
	end
	local label = ""
	if type(disk.label) == "string" then label = disk.label end
	return {
		type = "dev", owner = "root", group = CeroSecOS.DEV_GROUP, mode = mode,
		id = CeroSecOS.FD_NAME, kind = CeroSecOS.FD_KIND,
		-- The sticker on the front of the disk, in the column `ls -l /dev` and
		-- `dev` keep for what a device is fixed to.
		desc = label, side = "", pos = "",
		state = CeroSecOS.fdState(state),
	}
end

-- Is this node the drive? Asked by the sweep, which remembers its mode before it
-- takes it away, and by validate, which accepts no device at all on a saved disk
-- beyond the hole in it.
function CeroSecOS.isFloppyDev(node)
	return type(node) == "table" and node.type == "dev"
		and node.kind == CeroSecOS.FD_KIND
end

--
-- The commands
--

local commands = CeroSecOS.commands

local function fail(cmd, arg, reason)
	if arg == nil then return false, { cmd .. ": " .. reason } end
	return false, { cmd .. ": " .. arg .. ": " .. reason }
end

local function usage(cmd)
	return false, { cmd .. ": usage: " .. (CeroSecOS.commandUsage(cmd) or cmd) }
end

-- The drive's node, by the path as it was typed: the node, or nil plus the bare
-- reason for the caller to put its own name in front of. Everything below reaches
-- the drive this way and never through state.floppy, so a machine with no disk in
-- it says "no such file" about /dev/fd0 exactly as it says it about anything else
-- that is not there, and a chmod on the drive is obeyed by all three commands.
local function driveNode(state, session, path)
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node == nil then return nil, reason end
	if not CeroSecOS.isFloppyDev(node) then return nil, "not a floppy drive" end
	return node
end

--
-- newfs
--
-- The disk, emptied and given a filesystem. What is on it is gone -- that is what
-- formatting a disk is -- and what comes back is the one line a real newfs ends
-- its super block summary on, cut down to the two numbers this machine has: the
-- bytes it holds and the inodes.
--
--   admin@ksp-04-11:~$ newfs /dev/fd0
--   /dev/fd0: 4096 bytes, 32 inodes
--
-- 4.4BSD's newfs prints a block of super-block figures -- cylinder groups, the
-- backup super block addresses -- and not one of those is a thing this machine
-- has. Printing them would be printing hardware that is not there, so what is
-- printed is the two figures that are, in newfs's own shape: the device, a colon,
-- and the sizes.
--
-- A mounted disk is not formatted under the feet of whoever is reading it.
--
commands.newfs = function(state, session, args, env)
	if #args ~= 2 then return usage("newfs") end
	local node, reason = driveNode(state, session, args[2])
	if node == nil then return fail("newfs", args[2], reason) end
	if not CeroSecOS.can(state, session, node, "w") then
		return fail("newfs", args[2], "permission denied")
	end
	local mount = CeroSecOS.fdMount(state)
	if mount ~= nil then return fail("newfs", args[2], "Device busy") end

	local disk = CeroSecOS.floppyOf(state)
	disk.v = CeroSecOS.FLOPPY_VERSION
	disk.fs = CeroSecOS.newFloppyRoot(CeroSecOS.userOf(session), CeroSecOS.clockOf(env))
	return true, { args[2] .. ": " .. CeroSecOS.FLOPPY_BYTES .. " bytes, "
		.. CeroSecOS.FLOPPY_NODES .. " inodes" }
end

--
-- mount
--
-- With no arguments, what is mounted, one line each, in mount(8)'s own shape:
--
--   /dev/hda on / type ufs (rw)
--   /dev/fd0 on /mnt type ufs (rw)
--
-- The hard disk's line is first and is always there: it is the root filesystem and
-- it is mounted whether anybody said so or not, which is what every mount on every
-- Unix has printed since there was one. It is not in state.mounts and must not be
-- -- a machine whose root could be unmounted is a machine with no root.
--
-- With a device and a directory, the mount itself. Only a directory may be mounted
-- on, and never "/": the root is already mounted, and a machine that let it be
-- covered would be a machine with no way back to its own /bin.
--
CeroSecOS.MOUNT_RW = "(rw)"

function CeroSecOS.mountLine(dev, dir, kind)
	return CeroSecOS.DEV_PATH .. "/" .. dev .. " on " .. dir
		.. " type " .. (kind or CeroSecOS.FS_TYPE) .. " " .. CeroSecOS.MOUNT_RW
end

local function mountList(state)
	local out = { CeroSecOS.mountLine(CeroSecOS.DISK_NAME, "/", CeroSecOS.FS_TYPE) }
	local mounts = CeroSecOS.mountTable(state)
	if mounts ~= nil then
		for i = 1, #mounts do
			local m = mounts[i]
			if type(m) == "table" then
				out[#out + 1] = CeroSecOS.mountLine(m.dev, m.dir, m.type)
			end
		end
	end
	return out
end

commands.mount = function(state, session, args, env)
	if #args == 1 then return true, mountList(state) end
	if #args ~= 3 then return usage("mount") end
	local devPath, dir = args[2], args[3]

	local node, reason = driveNode(state, session, devPath)
	if node == nil then return fail("mount", devPath, reason) end
	-- Reading the super block is a read of the device, and that is the whole of
	-- who may mount a disk: 660 on the drive means root and the sudo group.
	if not CeroSecOS.can(state, session, node, "r") then
		return fail("mount", devPath, "permission denied")
	end

	local dirNode, dreason, dirAbs = CeroSecOS.getNode(state, session, dir)
	if dirNode == nil then return fail("mount", dir, dreason) end
	if dirNode.type ~= "dir" then return fail("mount", dir, "not a directory") end
	if dirAbs == "/" then return fail("mount", dir, "Device busy") end
	-- Already something there, or this very drive already mounted somewhere else.
	if CeroSecOS.mountAt(state, dirAbs) ~= nil then
		return fail("mount", dir, "Device busy")
	end
	if CeroSecOS.fdMount(state) ~= nil then
		return fail("mount", devPath, "Device busy")
	end

	-- An unformatted disk has no super block on it, and that is the sentence a
	-- real mount answers with. Said about the pair -- the device and the place --
	-- because that is the shape 4.4BSD's mount reports a refusal in.
	if CeroSecOS.floppyRoot(state) == nil then
		return false, { "mount: " .. devPath .. " on " .. dirAbs
			.. ": Incorrect super block" }
	end

	CeroSecOS.addMount(state, CeroSecOS.FD_NAME, dirAbs)
	return true, {}
end

--
-- umount
--
-- The mount point, not the device: `umount /mnt`. What is refused is a mount
-- somebody is standing in -- any session on the machine whose working directory is
-- the mount point or below it -- because unmounting the ground under a survivor
-- who is reading a file is the one thing a filesystem must never do.
--
-- The sessions come from the caller (env.net.sessions, the same list `who`
-- prints), plus the session that typed the command, which is known here whether
-- anybody handed a list over or not.
--
local function cwdsOf(state, session, env)
	local out = {}
	if type(session) == "table" and type(session.cwd) == "string" then
		out[#out + 1] = session.cwd
	end
	if type(env) ~= "table" or type(env.net) ~= "table" then return out end
	if type(env.net.sessions) ~= "function" then return out end
	local list = env.net.sessions()
	if type(list) ~= "table" then return out end
	for i = 1, #list do
		local one = list[i]
		if type(one) == "table" and type(one.cwd) == "string" then out[#out + 1] = one.cwd end
	end
	return out
end

-- Is anybody standing on it? A cwd is a path as it was typed, so it is resolved
-- before it is compared -- "/mnt/." and "/mnt" are the same place.
function CeroSecOS.mountBusy(state, session, env, dir)
	local cwds = cwdsOf(state, session, env)
	for i = 1, #cwds do
		local abs = CeroSecOS.resolve(nil, cwds[i])
		if CeroSecOS.isInside(abs, dir) then return true end
	end
	return false
end

commands.umount = function(state, session, args, env)
	if #args ~= 2 then return usage("umount") end
	local dir = args[2]
	local dirAbs = CeroSecOS.resolve(session, dir)
	local mount = CeroSecOS.mountAt(state, dirAbs)
	-- Nothing mounted there. mount(8)'s own answer for it, which names the thing
	-- the player got wrong: the place, not the disk.
	if mount == nil then return fail("umount", dir, "not mounted") end

	local node, reason = driveNode(state, session,
		CeroSecOS.DEV_PATH .. "/" .. mount.dev)
	if node == nil then return fail("umount", dir, reason) end
	if not CeroSecOS.can(state, session, node, "r") then
		return fail("umount", dir, "permission denied")
	end

	if CeroSecOS.mountBusy(state, session, env, dirAbs) then
		return fail("umount", dir, "Device busy")
	end

	CeroSecOS.dropMount(state, dirAbs)
	return true, {}
end
