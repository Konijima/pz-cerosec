--
-- CeroSec OS core: /dev.
--
-- The machine can reach the world it is standing in: the light switches, the
-- doors and the windows around it are files under /dev, and a survivor reads
-- one with `cat` and works it with a redirect.
--
--   cat /dev/light0            -> on
--   echo off > /dev/light0
--   echo unlock > /dev/lock1
--   echo open > /dev/door3
--   cat /dev/sensor0           -> motion
--
-- One kind is read and never written: a motion sensor dropped on the floor is a
-- sensorN whose whole vocabulary is nothing (DEV_VALUES.sensor is empty), so
-- every word written to it is "sensor0: invalid value". It wears 440 for saying
-- so (DEV_MODES).
--
-- A door is two devices when the lock on it means anything: doorN is what opens
-- and closes it, lockN is the key. Which doors get a lockN is the world's
-- business and is decided in SCeroSecDevices.lua; the core only ever sees the
-- kinds it has words for.
--
-- The OTHER way a device is read and never written is an entry marked `ro`, and
-- it is not about the kind: it is one particular device with nothing behind it
-- to carry a write out -- a door with a magnetic contact on it and no operator
-- (SCeroSecDevices.lua and CeroSecModules.lua). It is born 440 like a sensor,
-- and the write that gets past the mode is refused in its own name:
--
--   door3: operation not supported
--
-- A device node is NOT a file. It has no data, it is never written to the disk,
-- and the core never touches the world itself: what it holds is a description
-- and a state, both handed over by whoever is running the machine, and a write
-- is a call back out to that same caller.
--
--   dev = { type = "dev", owner = "root", group = "sudo", mode = 660,
--           id = "light0", kind = "light", desc = "office", side = "N",
--           pos = "3E 2N", state = "on" }
--
-- pos is where the device is from where the MACHINE is standing, worked out by
-- the caller (SCeroSecDevices.offset) because tiles are the caller's business.
-- It is what tells two devices apart when their descriptions are the same word,
-- which in a big house they usually are; `dev` prints it and `ls -l /dev` has
-- no column left for it.
--
-- Where they come from
--
-- env.devices, when the caller supplies one, with two functions:
--   list()             -> array of entries, each { id, kind, desc, side, pos,
--                         state, mode, dead, ro }. The IDS ARE THE CALLER'S: it is the
--                         server that discovers the world and that keeps a
--                         device's number stable across reloads. The core only
--                         ever renders what it is handed.
--   write(id, value)   -> ok, reason, state. Carries the world action out and
--                         answers with the state it re-read afterwards.
--   chmod(id, mode)    -> optional. Called when a chmod moved a node's mode, so
--                         the caller can remember it; a caller without one is a
--                         caller whose modes last until the machine reloads.
--   find(id, seconds)  -> optional. Make the device SHOW itself in the world for
--                         that long, and answer ok, reason, word -- the word
--                         being what it did ("blinking", "highlighted"), which
--                         is the caller's to choose because it is the caller
--                         that knows what a world can do. A caller without one
--                         is a machine whose devices cannot be pointed at, and
--                         `dev find` says "no such device" about every one of
--                         them, which is the truth from where the engine sits.
--
-- An entry marked dead is a device the caller knows about and cannot reach --
-- it was taken away, or its chunk is not loaded. It is mounted, so that `cat`
-- and `echo` can say "no such device" about a number a player has written down,
-- and it is NOT listed: a device that is not there is not on the shelf.
--
-- When they exist
--
-- Between exec and exec, never. mountDev builds the children at the top of
-- every exec and continue, unmountDev takes them away again before the answer
-- goes back, so the state the game saves holds no device of the WORLD, exactly as
-- it has since rung 1. Nothing about one is persisted by the filesystem: the
-- numbers and the modes live in the caller's own book (state.devmap, kept by
-- the server) and everything else is discovered afresh every time.
--
-- One exception, and it is not part of the world at all: /dev/null is on the disk
-- (see below). It is seeded, it is saved, and the sweep leaves it alone.
--
-- Errors
--
-- A device says its own name and nothing else:
--   light0: no power
--   lock0: no such device
--   light0: invalid value
-- because the machine is talking about the DEVICE and not about the command
-- that reached it. A refusal that is the FILESYSTEM's -- `rm /dev/light0` --
-- keeps the filesystem's grammar and comes out as "rm: /dev/light0: is a
-- device", the way every other refusal on this machine reads.
--

CeroSecOS = CeroSecOS or {}

CeroSecOS.DEV_PATH = "/dev"

-- rw for root and for the sudo group; nothing for anybody else. Written 660
-- since the rung that mounted the first device, and true since the rung that
-- gave the middle digit meaning: an account /etc/sudoers names is in the group
-- sudo (CeroSecOS.inGroup), so it throws a light switch with a plain
-- `echo off > /dev/light0` and no sudo typed. Everybody else gets nothing.
CeroSecOS.DEV_MODE = 660

-- Every device belongs to it. Not the caller's to choose: a device's owner is
-- root by construction and its group is what makes 660 mean "the people who may
-- become root", which is a fact about the machine and not about the world.
CeroSecOS.DEV_GROUP = "sudo"

-- What may be written to each kind, and nothing else. The vocabulary is the
-- CORE's and not the world's: a value that is not one of these never reaches
-- the caller at all, which is what "light0: invalid value" is.
-- An EMPTY table is a kind with no words at all, which is what a sensor is: it
-- is mounted, it is listed, it is read, and every word written to it is
-- "sensor0: invalid value" -- there is nothing a survivor could tell a motion
-- sensor that a motion sensor would do. The kind has to be HERE and not merely
-- absent, because a kind the core has no entry for is an entry nodeFor drops on
-- the floor: absent means "not a device", empty means "read-only".
-- The floppy drive is the second empty one, and for the same reason read the
-- other way round: there is no WORD a survivor could write to a raw disk. Its
-- `w` bit is still read -- by `newfs`, which opens the device to format it, the
-- way newfs on a real machine does -- so 660 on it promises nothing a redirect
-- could ask for and everything `newfs` asks for (see CeroSecOSDisk.lua).
CeroSecOS.DEV_VALUES = {
	light  = { on = true, off = true },
	lock   = { lock = true, unlock = true },
	win    = { lock = true, unlock = true },
	door   = { open = true, close = true },
	-- The motor rung's five. A window is TWO kinds on one window and not one with
	-- four words: winN is the catch a magnetic contact senses -- lock, unlock --
	-- and windowN is the sash a window operator moves, which is a door's pair of
	-- words because it is a door's job. One node, one vocabulary, one thing its
	-- mode can promise.
	window  = { open = true, close = true },
	curtain = { open = true, close = true },
	-- An oven, a microwave and a coffee machine are one class and one kind; the
	-- washer, the dryer and the combination machine are another. Both take a light
	-- switch's words because both are a switch.
	stove   = { on = true, off = true },
	washer  = { on = true, off = true },
	gen     = { on = true, off = true },
	sensor = {},
	floppy = {},
	-- The third empty one, and it is empty for the sensor's reason read yet
	-- another way: the frequency of a radio is set on the radio's own knob, by a
	-- survivor standing in front of it, and the game has exactly one path that
	-- moves it (see proof 7 at the head of SCeroSecRadio.lua). There is no word a
	-- machine could write to an aerial.
	radio = {},
}

-- The mode a kind is born at, where DEV_MODE is not it. A sensor is read-only by
-- nature and wears it: 440, cr--r-----, root and the sudo group may read it and
-- nobody may write it -- not even root, who is refused by the vocabulary a line
-- later rather than by the mode. A device whose middle digit carried a `w` would
-- be a machine promising a write that cannot happen.
--
-- The mode is still a chmod's to move like any other (`chmod 444 /dev/sensor0`
-- opens the reading to the whole office), and it still outlives the command it
-- was typed in; this is only where it STARTS.
-- Read by root and by the sudo group, written by nobody. The mode of a device
-- there is no way to write, whatever the reason there is none.
CeroSecOS.DEV_MODE_RO = 440

CeroSecOS.DEV_MODES = {
	sensor = CeroSecOS.DEV_MODE_RO,
	-- And the radio, for the same rule and not for a second one: its vocabulary
	-- is empty, so a `w` in the middle digit would be this machine promising a
	-- write that cannot happen. 660 was the shape this rung was sketched in and
	-- 440 is what the shape already on the disk forces -- one rule, applied twice.
	radio = CeroSecOS.DEV_MODE_RO,
}

-- What a kind's node is mounted at when nobody has chmodded it. The one place
-- DEV_MODES is read, so a kind with no entry is DEV_MODE and never nil.
--
-- `ro` is the SECOND way a device can be read-only, and it is not about the kind
-- at all: a door with a magnetic contact on it and no operator is a door the
-- machine can see and cannot move, and it is a `door` like any other. The kind
-- says what words exist; this says whether this particular one has anything
-- behind it to carry them out. Either is 440, for the same reason: a `w` in the
-- middle digit would be a machine promising a write that cannot happen.
function CeroSecOS.devModeFor(kind, ro)
	if ro then return CeroSecOS.DEV_MODE_RO end
	local mode = CeroSecOS.DEV_MODES[kind]
	if type(mode) ~= "number" then return CeroSecOS.DEV_MODE end
	return mode
end

--
-- /dev/null
--
-- The one device that is not part of the world and the one that is written to the
-- DISK: it is there whether anybody is standing in the building or not, it reads
-- empty, and it swallows whatever is written to it. So it is seeded like any other
-- system file (CeroSecOS.ensureDev), it survives a save, and the sweep that takes
-- the world's devices off /dev leaves it exactly where it is.
--
-- It is a device and not an empty file, because that is what it is on a real
-- machine and because the difference shows: `rm /dev/null` is "is a device",
-- `ls -l` wears "c", and nothing can put contents into it.
--
-- 666, the mode a real one wears: everybody may read it and everybody may write
-- to it, which is the whole point of it -- `cmd > /dev/null` is what a script
-- writes when it wants an answer and not the noise.
CeroSecOS.NULL_NAME = "null"
CeroSecOS.NULL_MODE = 666
CeroSecOS.NULL_PATH = CeroSecOS.DEV_PATH .. "/" .. CeroSecOS.NULL_NAME

function CeroSecOS.newNull()
	return {
		type = "dev", owner = "root", group = "root", mode = CeroSecOS.NULL_MODE,
		id = CeroSecOS.NULL_NAME, kind = CeroSecOS.NULL_NAME,
		desc = "", side = "", pos = "", state = "",
	}
end

-- Is this node the machine's own null device? Asked by the sweep, which must not
-- take it away, and by validate, which accepts no other device on a saved disk.
function CeroSecOS.isNull(node)
	return type(node) == "table" and node.type == "dev"
		and node.kind == CeroSecOS.NULL_NAME
end

-- /dev, with the null device in it. Made where either is missing and left exactly
-- as it lies where they are not -- root deleting /dev is root's right and stays
-- done, the way it does for /bin.
function CeroSecOS.ensureDev(state)
	local dir = CeroSecOS.ensureSystemDir(state, "dev")
	if dir == nil then return nil end
	-- Only where the name is free: anything else at it is somebody's own work and
	-- is not ours to replace, which is the rule every other thing seeded here runs
	-- on.
	if dir.children[CeroSecOS.NULL_NAME] == nil
			and CeroSecOS.countEntries(dir) < CeroSecOS.DEV_MAX then
		dir.children[CeroSecOS.NULL_NAME] = CeroSecOS.newNull()
	end
	return dir
end

-- How many nodes /dev may hold.
--
-- 256, written here rather than taken from MAX_DIR_ENTRIES, which it used to be.
-- That ceiling moved because /bin outgrew it, and how many COMMANDS ship is no
-- reason to mount more of the world: what is built here is built afresh at the
-- top of every command, so this number is a cost paid over and over and the
-- other one is not.
--
-- It was 64, and 64 was a machine in the middle of a shopping mall that could not
-- see half the mall: a computer in one store of a mall is in a BUILDING with every
-- other store's lights, doors and windows in it, and the map has buildings with
-- several hundred of them. A survivor who cannot see a light through `dev` cannot
-- reach it at all, and a ceiling that hides the world is worse than a listing that
-- takes a few screens.
--
-- So /dev is the one directory the 96-entry rule (CeroSecOS.MAX_DIR_ENTRIES) does
-- not hold for, and that is not an exemption written anywhere: the rule guards the
-- WRITE path, and the write path refuses /dev as read-only one gate earlier
-- (CeroSecOSFS, "read-only"), while the state gate refuses any device of the world
-- on a saved disk at all. Nothing can put an entry in /dev but the mount, so the
-- mount's own ceiling is the only one there is -- and it is this one.
CeroSecOS.DEV_MAX = 256

function CeroSecOS.isDev(node)
	return type(node) == "table" and node.type == "dev"
end

-- The one place env.devices is read, so a caller that passes junk is a machine
-- with no devices and never a machine with broken ones.
function CeroSecOS.devicesOf(env)
	if type(env) ~= "table" then return nil end
	local devices = env.devices
	if type(devices) ~= "table" then return nil end
	if type(devices.list) ~= "function" or type(devices.write) ~= "function" then return nil end
	return devices
end

--
-- Mounting.
--

local function devDir(state)
	local node = CeroSecOS.systemNode(state, CeroSecOS.DEV_PATH)
	if type(node) ~= "table" or node.type ~= "dir" or type(node.children) ~= "table" then
		return nil
	end
	return node
end

-- One entry off the caller's list -> one node, or nil when the entry is not
-- one. Names are ids and ids are path components, so an id that is not a valid
-- name is an entry no path could ever reach and is dropped here.
local function nodeFor(entry)
	if type(entry) ~= "table" then return nil end
	local id = entry.id
	if type(id) ~= "string" or not CeroSecOS.isValidName(id) then return nil end
	if CeroSecOS.DEV_VALUES[entry.kind] == nil then return nil end

	local mode = entry.mode
	if type(mode) ~= "number" or mode < 0 or mode > 777 or mode ~= math.floor(mode) then
		mode = CeroSecOS.devModeFor(entry.kind, entry.ro)
	end

	local node = {
		type = "dev",
		owner = "root",
		group = CeroSecOS.DEV_GROUP,
		mode = mode,
		id = id,
		kind = entry.kind,
		desc = "",
		side = "",
		pos = "",
		state = "",
		-- The rest of the line, for a kind that has more than a word to say. Empty
		-- on every kind but the generator; see CeroSecOS.devText.
		detail = "",
	}
	-- A device with nothing behind it to carry a write out. The caller decides
	-- which those are -- it is the only side that knows what is wired to what --
	-- and the node carries the fact so that a write is refused HERE, before the
	-- world is asked anything (devWrite, below).
	if entry.ro then node.ro = true end
	if type(entry.desc) == "string" then node.desc = entry.desc end
	if type(entry.side) == "string" then node.side = entry.side end
	if type(entry.pos) == "string" then node.pos = entry.pos end
	if type(entry.state) == "string" then node.state = entry.state end
	if type(entry.detail) == "string" then node.detail = entry.detail end
	if entry.dead then
		node.dead = true
		node.state = ""
		node.detail = ""
	end
	return node
end

-- Take every device node off /dev, and tell the caller about any mode a chmod
-- moved while they were mounted. Called before a mount as well as after one, so
-- a mount is never laid on top of an older one.
function CeroSecOS.unmountDev(state, env)
	local dir = devDir(state)
	if dir == nil then return end
	local devices = CeroSecOS.devicesOf(env)
	local names = CeroSecOS.childNames(dir)
	for i = 1, #names do
		local node = dir.children[names[i]]
		-- Every device except the machine's own: /dev/null is on the disk and is
		-- not something the world hands over, so the sweep is not about it.
		if CeroSecOS.isDev(node) and not CeroSecOS.isNull(node) then
			-- The floppy drive is not the world's either -- it is bolted to the case
			-- -- so its mode is remembered on the machine's own state rather than in
			-- the caller's book of devices. A chmod on it outlives the disk that
			-- happened to be in it when it was typed.
			if CeroSecOS.isFloppyDev(node) then
				if node.mode ~= node.mounted then state.fdmode = node.mode end
			elseif devices ~= nil and type(devices.chmod) == "function"
					and node.mode ~= node.mounted then
				devices.chmod(node.id, node.mode)
			end
			dir.children[names[i]] = nil
		end
	end
end

-- The floppy drive, which is a device of the MACHINE and not of the world: it is
-- there whenever there is a disk in it, with no caller to ask and nothing to
-- discover. First on, so that a building with sixty-four light switches in it
-- cannot push the drive off the end of DEV_MAX -- a survivor can walk away from a
-- light he cannot reach through the machine, and he cannot walk away from the
-- disk he just put in the slot. The room that is left comes back.
local function mountDrive(state, dir, room)
	if room <= 0 then return room end
	if dir.children[CeroSecOS.FD_NAME] ~= nil then return room end
	local node = CeroSecOS.newFloppyDev(state)
	if node == nil then return room end
	node.mounted = node.mode
	dir.children[CeroSecOS.FD_NAME] = node
	return room - 1
end

-- Build /dev's children from what the caller can see right now, plus the drive on
-- the front of the case. Anything already there under a name a device wants is
-- LEFT alone: /dev is read-only to everybody, so nothing should be, and a machine
-- whose save file carries something odd at that name is a machine we would rather
-- show the oddity than quietly overwrite.
function CeroSecOS.mountDev(state, env)
	CeroSecOS.unmountDev(state, env)
	local dir = devDir(state)
	if dir == nil then return end
	-- The drive goes on whether the caller handed any world over or not: a machine
	-- on a bench with no building around it still has a slot on the front of it.
	local room = CeroSecOS.DEV_MAX - CeroSecOS.countEntries(dir)
	room = mountDrive(state, dir, room)

	local devices = CeroSecOS.devicesOf(env)
	if devices == nil then return end

	local list = devices.list()
	if type(list) ~= "table" then return end

	for i = 1, #list do
		if room <= 0 then return end
		local node = nodeFor(list[i])
		if node ~= nil and dir.children[node.id] == nil then
			-- What it was mounted with, so unmountDev can tell a chmod from a
			-- mode the caller handed over.
			node.mounted = node.mode
			dir.children[node.id] = node
			room = room - 1
		end
	end
end

--
-- Reading and writing one.
--

-- Every refusal a device makes, worded once: the device's own name and the
-- reason, with nothing of the command in front of it.
local function refuse(node, reason)
	return nil, tostring(node.id) .. ": " .. reason
end

--
-- WHAT A DEVICE READS, and why it is not always the same as what a table shows
--
-- Every kind but one has one word for what it is doing, and the two listings
-- have a column for exactly that: `ls -l /dev` puts the widest state on column
-- 60 and `dev` on column 55, on a terminal 60 wide that does not wrap.
--
-- A generator has more to say than a word. Whether it is running is the thing a
-- survivor can hear from the yard; what he cannot hear is how long it will go on
-- running, and that is two numbers and a fact -- `on fuel 62 condition 80
-- connected`. So the word goes in `state`, where the columns are, and the rest
-- goes in `detail`, and this is the one place they are put back together: `cat`
-- and `dev <id>` read the whole line, the tables read the word.
--
-- A node with no detail reads exactly as it always did, which is every kind but
-- the generator and every device written before this rung.
function CeroSecOS.devText(node)
	local state = node.state or ""
	local detail = node.detail
	if type(detail) ~= "string" or detail == "" then return state end
	if state == "" then return detail end
	return state .. " " .. detail
end

-- The state as text, or nil plus the line to print.
function CeroSecOS.devRead(state, session, node)
	if node.dead then return refuse(node, "no such device") end
	if not CeroSecOS.can(state, session, node, "r") then
		return refuse(node, "permission denied")
	end
	-- The null device has no state and never will: what it reads is nothing at
	-- all, which is not the same as an empty LINE (see commands.cat).
	return CeroSecOS.devText(node), nil
end

-- What a redirect hands over is a line of output, so the blanks around it are
-- the shell's and not the player's: "echo on" and "echo \"on\"" have to be the
-- same order.
local function trim(text)
	if type(text) ~= "string" then return "" end
	return string.match(text, "^[ \t\n]*(.-)[ \t\n]*$") or ""
end

-- true, or nil plus the line to print. The core never touches the world: what
-- it does here is judge the value against the kind and hand the rest to the
-- caller, which is the only thing that knows there is a world at all.
function CeroSecOS.devWrite(state, session, node, value, env)
	if node.dead then return refuse(node, "no such device") end
	if not CeroSecOS.can(state, session, node, "w") then
		return refuse(node, "permission denied")
	end

	-- The null device takes anything and does nothing with it. Answered before the
	-- vocabulary and before the world is asked, because there is no world behind
	-- it: it is a hole in the disk, and a machine with no devices around it still
	-- has one.
	if CeroSecOS.isNull(node) then return true, nil end

	-- A device with nothing behind it to do the writing. Before the vocabulary,
	-- deliberately: what word was typed cannot matter to a device that has no way
	-- to carry any of them out, and a machine that judged the word first would be
	-- telling a survivor to try another one.
	--
	-- 440 means such a device is normally refused a line above, by the mode, and
	-- this is what answers root after a `chmod 660` -- the one door the mode
	-- leaves open. "operation not supported" is write(2)'s own EOPNOTSUPP, in the
	-- lower case every other reason on this machine is written in.
	if node.ro then return refuse(node, "operation not supported") end

	local word = trim(value)
	local allowed = CeroSecOS.DEV_VALUES[node.kind]
	if allowed == nil or not allowed[word] then return refuse(node, "invalid value") end

	local devices = CeroSecOS.devicesOf(env)
	if devices == nil then return refuse(node, "no such device") end

	local ok, reason, after, detail = devices.write(node.id, word)
	if not ok then
		if type(reason) ~= "string" or reason == "" then reason = "no such device" end
		return refuse(node, reason)
	end
	-- The state comes back from the world and is not assumed from the order: a
	-- switch that was thrown and did not move says so on the next `cat`. And so
	-- does the rest of the line, for the one kind that has one.
	if type(after) == "string" then node.state = after end
	if type(detail) == "string" then node.detail = detail end
	return true, nil
end

-- How long a device shows itself for. Long enough to walk to a window and look
-- up, short enough that a survivor who typed it twice is not left with a light
-- flashing at him.
CeroSecOS.DEV_FIND_SECONDS = 6

-- Point at one. The word it did it with, or nil plus the line to print.
--
-- What it asks for is what it DOES: a light is switched, twelve times, so it
-- takes the same "w" a write takes; a door or a window is only drawn around, so
-- reading it is enough. A rule that asked for one right and did the other would
-- be a light somebody may not switch, switching.
function CeroSecOS.devFind(state, session, node, env)
	if node.dead then return refuse(node, "no such device") end
	local need = "r"
	if node.kind == "light" then need = "w" end
	if not CeroSecOS.can(state, session, node, need) then
		return refuse(node, "permission denied")
	end

	local devices = CeroSecOS.devicesOf(env)
	if devices == nil or type(devices.find) ~= "function" then
		return refuse(node, "no such device")
	end

	local ok, reason, word = devices.find(node.id, CeroSecOS.DEV_FIND_SECONDS)
	if not ok then
		if type(reason) ~= "string" or reason == "" then reason = "no such device" end
		return refuse(node, reason)
	end
	if type(word) ~= "string" or word == "" then word = "found" end
	return word, nil
end

--
-- ls -l
--
-- A device has no size and no date -- it is not on the disk and was not written
-- at a time -- so those two columns are what it IS instead: what it is fixed
-- to, which way it faces, and what it is doing.
--
--   crw-rw----  root  sudo  lock1   kitchen-hall~  N  unlocked
--
-- 10 perm + 2 + 4 owner + 2 + 4 group + 2 + 8 id + 13 desc + 2 + 1 side + 2 +
-- state, which puts the widest state ("barricaded") exactly on column 60. The
-- owner is always "root" and the group always "sudo", so four is the whole of
-- either; what paid for the group column is the description, cut from 15 to 13.
-- /dev holds nothing but devices -- creating in it is refused -- so these
-- columns never have to line up with an ordinary file's.
--
local V_OWNER, V_GROUP, V_ID, V_DESC, V_SIDE = 4, 4, 8, 13, 1

function CeroSecOS.devLine(node)
	local head = CeroSecOS.permString(node)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.owner or "?", V_OWNER), V_OWNER)
		.. "  " .. CeroSecOS.padRight(
			CeroSecOS.truncate(CeroSecOS.groupOf(node), V_GROUP), V_GROUP)
		.. "  "
	-- The hole in the disk has no description, no place in the building and no
	-- state, so its line ends at its name rather than carrying three columns of
	-- blanks: a listing does not pad what it has nothing to say about.
	if CeroSecOS.isNull(node) then return head .. CeroSecOS.NULL_NAME end
	return head .. CeroSecOS.padRight(CeroSecOS.truncate(node.id or "?", V_ID), V_ID)
		.. CeroSecOS.padRight(CeroSecOS.truncate(node.desc or "", V_DESC), V_DESC)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.side or "", V_SIDE), V_SIDE)
		.. "  " .. (node.state or "")
end
