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
--
-- A door is two devices when the lock on it means anything: doorN is what opens
-- and closes it, lockN is the key. Which doors get a lockN is the world's
-- business and is decided in SCeroSecDevices.lua; the core only ever sees the
-- kinds it has words for.
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
--                         state, mode, dead }. The IDS ARE THE CALLER'S: it is the
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
-- goes back, so the state the game saves has an empty /dev in it exactly as it
-- has since rung 1. Nothing about a device is persisted by the filesystem: the
-- numbers and the modes live in the caller's own book (state.devmap, kept by
-- the server) and everything else is discovered afresh every time.
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
CeroSecOS.DEV_VALUES = {
	light = { on = true, off = true },
	lock  = { lock = true, unlock = true },
	win   = { lock = true, unlock = true },
	door  = { open = true, close = true },
}

-- How many nodes /dev may hold: a machine in the middle of a shopping mall is
-- not a machine with four hundred entries in one listing.
--
-- 64, written here rather than taken from MAX_DIR_ENTRIES, which it used to be.
-- That ceiling moved because /bin outgrew it, and how many COMMANDS ship is no
-- reason to mount more of the world: what is built here is built afresh at the
-- top of every command, so this number is a cost paid over and over and the
-- other one is not.
CeroSecOS.DEV_MAX = 64

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
		mode = CeroSecOS.DEV_MODE
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
	}
	if type(entry.desc) == "string" then node.desc = entry.desc end
	if type(entry.side) == "string" then node.side = entry.side end
	if type(entry.pos) == "string" then node.pos = entry.pos end
	if type(entry.state) == "string" then node.state = entry.state end
	if entry.dead then
		node.dead = true
		node.state = ""
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
		if CeroSecOS.isDev(node) then
			if devices ~= nil and type(devices.chmod) == "function"
					and node.mode ~= node.mounted then
				devices.chmod(node.id, node.mode)
			end
			dir.children[names[i]] = nil
		end
	end
end

-- Build /dev's children from what the caller can see right now. Anything
-- already there under a name a device wants is LEFT alone: /dev is read-only to
-- everybody, so nothing should be, and a machine whose save file carries
-- something odd at that name is a machine we would rather show the oddity than
-- quietly overwrite.
function CeroSecOS.mountDev(state, env)
	CeroSecOS.unmountDev(state, env)
	local devices = CeroSecOS.devicesOf(env)
	if devices == nil then return end
	local dir = devDir(state)
	if dir == nil then return end

	local list = devices.list()
	if type(list) ~= "table" then return end

	local room = CeroSecOS.DEV_MAX - CeroSecOS.countEntries(dir)
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

-- The state as text, or nil plus the line to print.
function CeroSecOS.devRead(state, session, node)
	if node.dead then return refuse(node, "no such device") end
	if not CeroSecOS.can(state, session, node, "r") then
		return refuse(node, "permission denied")
	end
	return node.state or "", nil
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

	local word = trim(value)
	local allowed = CeroSecOS.DEV_VALUES[node.kind]
	if allowed == nil or not allowed[word] then return refuse(node, "invalid value") end

	local devices = CeroSecOS.devicesOf(env)
	if devices == nil then return refuse(node, "no such device") end

	local ok, reason, after = devices.write(node.id, word)
	if not ok then
		if type(reason) ~= "string" or reason == "" then reason = "no such device" end
		return refuse(node, reason)
	end
	-- The state comes back from the world and is not assumed from the order: a
	-- switch that was thrown and did not move says so on the next `cat`.
	if type(after) == "string" then node.state = after end
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
	return CeroSecOS.permString(node)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.owner or "?", V_OWNER), V_OWNER)
		.. "  " .. CeroSecOS.padRight(
			CeroSecOS.truncate(CeroSecOS.groupOf(node), V_GROUP), V_GROUP)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.id or "?", V_ID), V_ID)
		.. CeroSecOS.padRight(CeroSecOS.truncate(node.desc or "", V_DESC), V_DESC)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.side or "", V_SIDE), V_SIDE)
		.. "  " .. (node.state or "")
end
