--
-- CeroSec OS core: the filesystem.
--
-- Every mutation in the whole OS goes through createNode, removeNode, setData
-- or moveNode, and every read through getNode. Permissions and limits are
-- enforced there and only there, so a new command cannot invent a hole.
--
-- Nodes are plain tables:
--   dir  = { type = "dir",  owner = "root",  group = "root",  mode = 750,
--            children = { [name] = node } }
--   file = { type = "file", owner = "admin", group = "users", mode = 640,
--            data = "text" }
--   link = { type = "link", owner = "admin", group = "admin", mode = 777,
--            target = "../notes.txt" }
--
-- A link holds a PATH, exactly as it was typed, and nothing else: it is followed
-- by getNode below and by nothing else in the whole engine, so no command has to
-- know about one. Its own mode is 777 and means nothing -- what is asked of a
-- link is asked of what it points at, which is what a symbolic link is -- and a
-- link that points nowhere is an ordinary "no such file" on use and a line of its
-- own in `ls -l`. There are no HARD links on this machine: two names for one node
-- would be one table under two keys, and the game copies the state table by
-- recursion (ISMoveableSpriteProps' copyTable, and the save file itself), so the
-- second name would become a second FILE the first time somebody picked the
-- computer up. A link that quietly stops being a link is worse than no hard
-- links, so `ln` makes symbolic ones and says so.
--
-- The group is what the middle digit of the mode is about, and a node that has
-- none reads as its owner's own name -- every node of every machine saved before
-- this build has none, validate accepts them, and nothing anywhere reads
-- node.group off the field (see CeroSecOS.groupOf).
--
-- and each of them may carry an mtime: the clock exec was handed at the moment
-- the node was last touched (see the clock section of CeroSecOS.lua). Absent is
-- 0 -- every node saved before this build has none and validate accepts them --
-- so it is read with CeroSecOS.mtimeOf and never off the field.
--
-- The mutators below all take that clock as a last argument, and nil means "no
-- clock": the mutation happens, nothing is stamped. This machine has ONE
-- timestamp where Unix has three, so it stands for mtime and for ctime both --
-- a chmod and a mv move it, where a real one would only have moved the ctime.
--
-- Reasons returned here are bare ("no such file"); the shell prefixes them with
-- the command and the argument as typed.
--

CeroSecOS = CeroSecOS or {}

local BITS = { r = 4, w = 2, x = 1 }

--
-- Node constructors.
--

-- A fresh node belongs to the group of its owner's own name -- his primary
-- group, the one every account has without a line in /etc/group. That is what
-- a real umask-less machine does, and it means a file starts shared with
-- nobody until somebody says otherwise with chgrp.
function CeroSecOS.newDir(owner, mode, mtime)
	local who = owner or "root"
	local node = { type = "dir", owner = who, group = who, mode = mode or 755, children = {} }
	if mtime ~= nil then node.mtime = mtime end
	return node
end

-- A symbolic link. Always 777: the bits on a link are not read by anything, here
-- or on a real machine, and writing them as anything else would invite somebody
-- to believe they were.
function CeroSecOS.newLink(owner, target, mtime)
	local who = owner or "root"
	local node =
		{ type = "link", owner = who, group = who, mode = 777, target = target or "" }
	if mtime ~= nil then node.mtime = mtime end
	return node
end

function CeroSecOS.newFile(owner, mode, data, mtime)
	local who = owner or "root"
	local node =
		{ type = "file", owner = who, group = who, mode = mode or 644, data = data or "" }
	if mtime ~= nil then node.mtime = mtime end
	return node
end

--
-- Permissions. Octal owner/group/other, and all three digits are read: the
-- owner's if the account owns it, else the group's if the account is in the
-- node's group, else everybody else's. Membership is CeroSecOS.inGroup's
-- question -- a primary group, a line in /etc/group, or /etc/sudoers for the
-- group "sudo" -- and root bypasses everything before any of it is asked.
--

function CeroSecOS.userOf(session)
	if session == nil or type(session.user) ~= "string" then return nil end
	return session.user
end

function CeroSecOS.can(state, session, node, what)
	local user = CeroSecOS.userOf(session)
	if user == nil then return false end
	if user == "root" then return true end
	local mode = node.mode or 0
	local digit
	if node.owner == user then
		digit = math.floor(mode / 100) % 10
	elseif CeroSecOS.inGroup(state, user, CeroSecOS.groupOf(node)) then
		digit = math.floor(mode / 10) % 10
	else
		digit = mode % 10
	end
	local bit = BITS[what]
	return math.floor(digit / bit) % 2 == 1
end

-- The mode as `ls -l` writes it: the type letter and nine bits. A device is a
-- character device and wears "c", the way a real /dev entry does.
function CeroSecOS.permString(node)
	local s = "-"
	if node.type == "dir" then
		s = "d"
	elseif node.type == "dev" then
		s = "c"
	elseif node.type == "link" then
		s = "l"
	end
	local mode = node.mode or 0
	local digits = { math.floor(mode / 100) % 10, math.floor(mode / 10) % 10, mode % 10 }
	for i = 1, 3 do
		local d = digits[i]
		if math.floor(d / 4) % 2 == 1 then s = s .. "r" else s = s .. "-" end
		if math.floor(d / 2) % 2 == 1 then s = s .. "w" else s = s .. "-" end
		if d % 2 == 1 then s = s .. "x" else s = s .. "-" end
	end
	return s
end

-- Why a node is not a file, in the words the commands print. Every command that
-- wanted to read or write text and found something else says it through here,
-- so a device never comes back as "is a directory".
function CeroSecOS.notAFile(node)
	if CeroSecOS.isDev(node) then return "is a device" end
	-- No command reaches this with a link today: everything that wanted text
	-- asked getNode, and getNode follows one. It is here so that the day one does
	-- ask without following, the machine says what it found instead of calling a
	-- link a directory -- and it is deliberately not in the manual, because
	-- nothing a player can type produces it.
	if CeroSecOS.isLink(node) then return "is a link" end
	return "is a directory"
end

function CeroSecOS.isLink(node)
	return type(node) == "table" and node.type == "link"
end

-- Sorted child names. pairs() order is not defined, and the core must be
-- deterministic, so nothing ever iterates children for output without this.
function CeroSecOS.childNames(node)
	local names = {}
	if node.children ~= nil then
		for name, _ in pairs(node.children) do
			names[#names + 1] = name
		end
	end
	table.sort(names)
	return names
end

function CeroSecOS.countEntries(node)
	local n = 0
	if node.children ~= nil then
		for _, _ in pairs(node.children) do n = n + 1 end
	end
	return n
end

-- Nodes and data bytes in a subtree, the node itself included. Every byte of
-- it: this is what a subtree COSTS, asked of a node that is about to be
-- attached, and a node about to be attached is not yet anywhere -- so the
-- quota's exemption, which is a question about a PATH, cannot be asked here.
-- A device costs nothing: it is not on the disk, it is mounted for the length
-- of one command, and a machine whose `df` moved because somebody walked past a
-- light switch would be a machine whose ceilings depend on the weather.
function CeroSecOS.subtreeUsage(node)
	if node.type == "dev" then return 0, 0 end
	local nodes, bytes = 1, 0
	if node.type == "file" then
		bytes = #(node.data or "")
	elseif node.type == "link" then
		-- The path it holds is bytes on the disk like any others: a link is a node
		-- and what is written in it is what it costs.
		bytes = #(node.target or "")
	elseif node.children ~= nil then
		local names = CeroSecOS.childNames(node)
		for i = 1, #names do
			local n, b = CeroSecOS.subtreeUsage(node.children[names[i]])
			nodes = nodes + n
			bytes = bytes + b
		end
	end
	return nodes, bytes
end

--
-- What the disk quota does not count
--
-- What the MACHINE writes about itself does not fill the drive. Three kinds of
-- file are exempt from the 64K, and all three are things a machine writes
-- without anybody asking it to:
--
--   * an account's own ~/.sh_history -- `df` must not move because somebody
--     typed;
--   * an account's own mailbox under /var/mail -- a cron job at four in the
--     morning must not cost the player his disk;
--   * /var/log/cron -- a machine that stopped logging because the log filled
--     the disk would go quiet exactly when something is wrong.
--
-- The exemption is decided by the PATH and by nothing carried on the node:
-- exactly <home>/.sh_history for an account /etc/passwd names, plus root's own,
-- exactly /var/mail/<name> for one, exactly /var/log/cron -- and owned by that
-- account. So a history that is renamed is an ordinary file from the moment it is
-- renamed -- it counts, immediately -- and one renamed back is exempt again.
-- There is no flag to ride a rename and no way to stack the exemption up by
-- moving files aside.
--
-- Two ceilings bound what the exemption can cost: one of its own for any single
-- file, and MAX_EXEMPT_BYTES for the whole machine. Bytes past either are not
-- exempt -- they are counted against the disk like any others, which is a full
-- disk and never a machine that will not boot.
--

-- The exempt paths, each mapped to the account it belongs to, the most it may be
-- granted, and WHICH of the three it is: the kind is what lets the history's own
-- ceiling be asked about histories alone (see CeroSecOS.historyAppend), so a
-- full mailbox is not what stops a shell remembering what was typed.
function CeroSecOS.exemptPaths(state)
	local paths = {}
	local function rule(path, owner, max, kind)
		paths[path] = { owner = owner, max = max, kind = kind }
	end
	local users, order = CeroSecOS.readUsers(state)
	for i = 1, #order do
		local user = users[order[i]]
		-- Through resolve, so a home written "/home/admin/" in the file names
		-- the same path the walk below builds.
		local abs = CeroSecOS.resolve(nil, user.home .. "/" .. CeroSecOS.HISTORY_NAME)
		rule(abs, user.name, CeroSecOS.HISTORY_BYTES, "history")
		rule(CeroSecOS.mailPath(user.name), user.name, CeroSecOS.MAIL_BYTES, "mail")
	end
	-- Root's own, whatever /etc/passwd says: a machine whose passwd has been
	-- edited into nonsense still has a root history at the place root's history
	-- has always been, and it must not start costing him his disk for it.
	rule("/root/" .. CeroSecOS.HISTORY_NAME, "root", CeroSecOS.HISTORY_BYTES, "history")
	rule(CeroSecOS.CRON_LOG_PATH, "root", CeroSecOS.CRON_LOG_BYTES, "log")
	-- And the machine's record of who logged in on it, which is the same kind of
	-- file for the same reason: a machine must not fill its own disk with what it
	-- said about itself while nobody was looking.
	rule(CeroSecOS.WTMP_PATH, "root", CeroSecOS.WTMP_BYTES, "log")
	return paths
end

-- The disk, walked once: nodes, the bytes the quota counts, the bytes it does
-- not. path is the absolute path of node ("" at the root, so a child of it
-- reads "/bin"), budget what is left of the machine-wide exemption, and ignore
-- a node left out of the walk altogether -- what the OTHER histories hold is
-- what historyAppend has to ask before it grows this one.
local function walkUsage(node, path, exempt, budget, ignore)
	if type(node) ~= "table" or node.type == "dev" then return 0, 0, 0 end
	if node == ignore then return 1, 0, 0 end
	if node.type == "link" then
		-- Never exempt: the exemption is for what the MACHINE writes about itself,
		-- and a link is something somebody made.
		return 1, #(node.target or ""), 0
	end
	if node.type == "file" then
		local size = #(node.data or "")
		local rule = exempt[path]
		if rule == nil or rule.owner ~= node.owner then return 1, size, 0 end
		local grant = size
		if grant > rule.max then grant = rule.max end
		if grant > budget.left then grant = budget.left end
		budget.left = budget.left - grant
		-- Counted towards the answer only when it is the kind being asked about.
		-- The BUDGET is spent either way: the machine-wide ceiling is one ceiling
		-- and not one per kind.
		if budget.kind ~= nil and rule.kind ~= budget.kind then
			return 1, size - grant, 0
		end
		return 1, size - grant, grant
	end
	local nodes, bytes, exempted = 1, 0, 0
	if node.children ~= nil then
		local names = CeroSecOS.childNames(node)
		for i = 1, #names do
			-- Sorted, so which history gets the last of the machine's exemption
			-- is the same answer every time it is asked.
			local n, b, e =
				walkUsage(node.children[names[i]], path .. "/" .. names[i], exempt, budget, ignore)
			nodes = nodes + n
			bytes = bytes + b
			exempted = exempted + e
		end
	end
	return nodes, bytes, exempted
end

local function walkState(state, ignore, kind)
	if type(state) ~= "table" or type(state.fs) ~= "table" then return 0, 0, 0 end
	return walkUsage(state.fs, "", CeroSecOS.exemptPaths(state),
		{ left = CeroSecOS.MAX_EXEMPT_BYTES, kind = kind }, ignore)
end

-- Whole-computer usage: nodes, and the bytes the quota counts.
function CeroSecOS.usage(state)
	local nodes, bytes = walkState(state, nil)
	return nodes, bytes
end

-- The bytes the quota does NOT count, on the whole machine.
function CeroSecOS.exemptUsage(state)
	local _, _, exempted = walkState(state, nil)
	return exempted
end

-- The same, with one node left out, and optionally counting one kind of exempt
-- file only: what everybody ELSE's history holds.
function CeroSecOS.exemptOthers(state, node, kind)
	local _, _, exempted = walkState(state, node, kind)
	return exempted
end

-- Is there a device anywhere in this subtree? Asked of a DISK and of nothing else:
-- a device costs the quota nothing by design (see CeroSecOS.subtreeUsage), which is
-- right for the machine's own /dev -- built afresh every command and swept again --
-- and is a hole on a disk, where nothing sweeps and the nodes are saved.
function CeroSecOS.hasDevUnder(node)
	if type(node) ~= "table" then return false end
	if node.type == "dev" then return true end
	if node.children == nil then return false end
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do
		if CeroSecOS.hasDevUnder(node.children[names[i]]) then return true end
	end
	return false
end

-- The path of the first file in this subtree that is bigger than a file may be, or
-- nil. Asked of a DISK and of nothing else: a node on the machine's own drive may
-- reach HISTORY_BYTES, because a history is exempt from the quota and grows past
-- what a write may put in one file -- and that exemption is the hard drive's, so
-- nothing on a disk has it and MAX_FILE_BYTES is the whole of what a file there
-- may be.
function CeroSecOS.tooBigOn(node, where)
	where = where or ""
	if type(node) ~= "table" then return nil end
	if node.type == "file" then
		if #(node.data or "") > CeroSecOS.MAX_FILE_BYTES then return where end
		return nil
	end
	if node.children == nil then return nil end
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do
		local found = CeroSecOS.tooBigOn(node.children[names[i]], where .. "/" .. names[i])
		if found ~= nil then return found end
	end
	return nil
end

-- Does any file in this subtree carry a byte that must never be stored? Whole
-- trees arrive at createNode (a copy today, a network transfer at a later
-- rung), so the check cannot stop at the node itself.
function CeroSecOS.subtreeHasControlBytes(node)
	if node.type == "file" then return CeroSecOS.hasControlBytes(node.data or "") end
	if node.type == "link" then return CeroSecOS.hasControlBytes(node.target or "") end
	if node.children == nil then return false end
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do
		if CeroSecOS.subtreeHasControlBytes(node.children[names[i]]) then return true end
	end
	return false
end

-- Deepest path length under a subtree, counting the subtree root as 0.
local function subtreeDepth(node)
	if node.type ~= "dir" or node.children == nil then return 0 end
	local deepest = 0
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do
		local d = 1 + subtreeDepth(node.children[names[i]])
		if d > deepest then deepest = d end
	end
	return deepest
end

--
-- Reading.
--

-- node, reason, absolute path. Traversing a directory needs x on it; the last
-- component itself is not tested, so getNode("/root") succeeds for admin and
-- it is cd that refuses to enter.
--
-- Symbolic links are followed HERE and nowhere else in the engine, which is why
-- no command had to learn about them: a link in the middle of a path is the
-- directory it names, and a link at the end of one is the file it names. The path
-- that comes back is still the path as it was TYPED -- the logical one, the way
-- `cd` keeps it and every shell prints it -- and never where the links landed.
--
-- noFollow leaves the LAST component alone, which is the difference between stat
-- and lstat and the difference between reading a link's target and reading the
-- file it points at. The commands that act on the link itself -- ls -l, rm, mv,
-- readlink -- ask for it; everything else follows, the way everything else on a
-- real machine does.
--
-- The walk is bounded twice: MAX_LINK_HOPS links in one resolution, and
-- MAX_DEPTH components once a target has been hung on the front of what is left.
-- So a link that points at itself costs eight hops and then says so, and a pair
-- that point at each other costs the same -- there is no path through here that
-- does not end.
--
-- The FOURTH return is the path the walk really took: the components as they
-- stood at the end of it, with every link already followed. It is not the same
-- thing as the third -- `cd /root/link` keeps `/root/link`, because that is the
-- path the survivor typed and the one every shell prints -- and the difference is
-- what every RULE about where a node lives has to be asked with. Which disk it is
-- on, whether it is a mount point, whether it is under /dev: those are facts about
-- the place the walk landed, and the logical path is a name for that place and not
-- the place. Asking them of the logical path is how a symbolic link was able to
-- carry a write past the ceilings of the disk it landed on.
-- The absolute path of the first n components of a walk. Built a piece at a time
-- rather than with table.concat's four-argument form, which is not worth betting
-- on under Kahlua.
local function pathUpTo(parts, n)
	local head = {}
	for k = 1, n do head[k] = parts[k] end
	return "/" .. table.concat(head, "/")
end

function CeroSecOS.getNode(state, session, path, noFollow)
	local abs, parts = CeroSecOS.resolve(session, path)
	local node = state.fs
	-- Is there a second filesystem on this machine at all? Asked once, because the
	-- answer is nil on every machine with an empty drive and the walk must not pay
	-- for a floppy nobody put in (see CeroSecOSDisk.lua).
	local mounts = CeroSecOS.mountTable(state)
	local hops = 0
	local i = 1
	while i <= #parts do
		if node.type ~= "dir" then return nil, "not a directory", abs end
		if not CeroSecOS.can(state, session, node, "x") then return nil, "permission denied", abs end
		local child = node.children[parts[i]]
		if child == nil then return nil, "no such file", abs end
		if child.type == "link" and not (noFollow and i == #parts) then
			hops = hops + 1
			if hops > CeroSecOS.MAX_LINK_HOPS then
				return nil, "too many levels of symbolic links", abs
			end
			-- The target is read from where the LINK is, so a relative one means
			-- what it says: "notes.txt" beside the link, "../notes.txt" above it.
			-- Whatever was still to walk is hung back on the end, and the walk
			-- starts again from the root -- which is what makes a link to a
			-- directory a directory for the rest of the path.
			local here = {}
			for k = 1, i - 1 do here[k] = parts[k] end
			local _, walk = CeroSecOS.resolve({ cwd = "/" .. table.concat(here, "/") },
				child.target or "")
			for k = i + 1, #parts do walk[#walk + 1] = parts[k] end
			if #walk > CeroSecOS.MAX_DEPTH then return nil, "path too deep", abs end
			parts = walk
			node = state.fs
			i = 1
		else
			node = child
			-- A mount point is the ROOT OF THE MOUNTED DISK and not the directory
			-- that is on the hard drive underneath it, which is what a mount has
			-- meant since there were two filesystems. Crossed here and nowhere
			-- else -- the same place a symbolic link is followed, and for the same
			-- reason: no command in the engine had to learn there is a floppy.
			--
			-- A mount whose drive is empty is not crossed and the directory
			-- underneath shows through. Nothing can leave one behind -- the eject
			-- path unmounts, and CeroSecOS.checkMounts sweeps a forged one off on
			-- the way in -- so this is the belt and not the rule.
			if mounts ~= nil then
				local mount = CeroSecOS.mountAt(state, pathUpTo(parts, i))
				if mount ~= nil then
					local root = CeroSecOS.mountedRoot(state, mount)
					if root ~= nil then node = root end
				end
			end
			i = i + 1
		end
	end
	return node, nil, abs, "/" .. table.concat(parts, "/")
end

-- Where a path WOULD be, whether or not anything is there: the physical path of
-- its parent with the last component on the end.
--
-- This is what a create has to be judged with -- which disk it lands on, and
-- whether it lands under /dev -- and a create is the one case getNode cannot
-- answer, because the thing being asked about is not there yet. The parent IS
-- there, or the create is about to fail for a reason of its own, so the walk is
-- asked about the parent and the name is put back on.
--
-- physical path, physical parent path, name. All three nil for "/" itself, which
-- has no parent and is nothing anybody creates.
function CeroSecOS.physicalOf(state, session, path)
	local _, parts = CeroSecOS.resolve(session, path)
	if #parts == 0 then return nil, nil, nil end
	local parentPath, name = CeroSecOS.parentOf(parts)
	local _, _, _, parentPhys = CeroSecOS.getNode(state, session, parentPath)
	-- A parent the walk could not reach is a parent that will refuse the create in
	-- its own words a line later; the logical path is the best answer there is for
	-- it and is never used to grant anything.
	if parentPhys == nil then parentPhys = parentPath end
	if parentPhys == "/" then return "/" .. name, parentPhys, name end
	return parentPhys .. "/" .. name, parentPhys, name
end

-- A node the machine itself reads, by absolute path, with no session and no
-- permission check. This is the ONE read in the whole core that does not go
-- through getNode, and it exists because the kernel has to read /etc/passwd
-- before anybody is logged in -- the file is root's and mode 600, so there is
-- no session that could read it and no session to read it with.
--
-- Nothing a command can reach ever calls this: it is used by the passwd parser,
-- by the boot check and by the BIOS repair, and by nothing else.
function CeroSecOS.systemNode(state, path)
	if type(state) ~= "table" or type(state.fs) ~= "table" then return nil end
	local _, parts = CeroSecOS.resolve(nil, path)
	local node = state.fs
	for i = 1, #parts do
		if node.type ~= "dir" or node.children == nil then return nil end
		node = node.children[parts[i]]
		if node == nil then return nil end
	end
	return node
end

-- The session the machine acts under when it writes one of its own files: a
-- passwd rewrite, a hostname change. Fresh each time, so nothing can be left
-- behind in it, and root so that the write lands wherever the file is -- but
-- still through setData and writeFile, so the ceilings and the printable rule
-- apply to the kernel exactly as they apply to a player.
function CeroSecOS.rootSession()
	return { user = "root", cwd = "/" }
end

--
-- Writing.
--

-- Shared gate for createNode and moveNode: is it legal to attach a node under
-- this path? Returns parent node, name, reason.
-- addNodes/addBytes are what the attachment costs the computer (zero for a
-- move, which only changes where an already counted node hangs).
-- fromParent, when given, is the directory the node is leaving: a rename inside
-- a full directory must not trip the entry limit.
-- replace says a name already taken is not a refusal but a REPLACEMENT, which is
-- what rename(2) does and what a move is (see CeroSecOS.moveNode). A replacement
-- takes no new entry in the listing either, so the entry limit is not asked
-- about it: a full directory can still have one of its own names written over.
local function checkAttach(state, session, parts, addNodes, addBytes, addDepth, fromParent,
		replace)
	if #parts == 0 then return nil, nil, "file exists" end
	local name = parts[#parts]
	if not CeroSecOS.isValidFileName(name) then return nil, nil, "invalid name" end

	local parentPath = CeroSecOS.parentOf(parts)
	local parent, reason, _, parentPhys = CeroSecOS.getNode(state, session, parentPath)
	if parent == nil then return nil, nil, reason end
	-- Everything below is a question about WHERE the parent is, and the answer is
	-- the path the walk really took and never the one that was typed: a symbolic
	-- link is a name for a place and not the place. Asked of the typed path, a link
	-- into /dev was a create /dev accepted, and a link into a mounted disk was a
	-- write judged against the wrong drive's ceilings.
	if parentPhys == nil then parentPhys = parentPath end
	local _, physParts = CeroSecOS.resolve(nil, parentPhys)
	if #physParts + 1 + addDepth > CeroSecOS.MAX_DEPTH then
		return nil, nil, "path too deep"
	end
	-- /dev is not a directory anybody writes into. Its contents are the world
	-- around the machine, worked out afresh at every command, so a file put
	-- there would be gone by the next one -- and root is not told a lie about a
	-- write that will not last. The commands that create say so in their own
	-- words; this is the gate under all of them, so cp and mv cannot go round.
	if parentPhys == CeroSecOS.DEV_PATH then return nil, nil, "read-only" end
	if parent.type ~= "dir" then return nil, nil, "not a directory" end
	local taken = parent.children[name] ~= nil
	if taken and not replace then return nil, nil, "file exists" end
	if not CeroSecOS.can(state, session, parent, "w") then return nil, nil, "permission denied" end
	if not taken and parent ~= fromParent
			and CeroSecOS.countEntries(parent) >= CeroSecOS.MAX_DIR_ENTRIES then
		return nil, nil, "directory full"
	end

	-- Which disk this lands on, and therefore which two ceilings it is judged
	-- against: the floppy's when the path is under a mount point, the machine's own
	-- drive otherwise. Neither is ever counted against the other -- a full floppy
	-- is a `df` that has not moved on hda (see CeroSecOS.fsFor).
	if addNodes > 0 or addBytes > 0 then
		local fs = CeroSecOS.fsFor(state, parentPhys)
		local nodes, bytes = CeroSecOS.fsUsage(state, fs)
		if nodes + addNodes > fs.nodes then return nil, nil, "disk full" end
		if bytes + addBytes > fs.bytes then return nil, nil, "disk full" end
	end

	return parent, name, nil
end

-- Attach a freshly built node at path. node, reason.
-- The whole attached subtree is stamped with the clock, and so is the directory
-- it lands in: a directory's mtime is when its listing last changed, which is
-- what Unix means by it.
function CeroSecOS.createNode(state, session, path, node, now)
	local _, parts = CeroSecOS.resolve(session, path)
	local addNodes, addBytes = CeroSecOS.subtreeUsage(node)
	if node.type == "file" and #(node.data or "") > CeroSecOS.MAX_FILE_BYTES then
		return nil, "file too large"
	end
	if CeroSecOS.subtreeHasControlBytes(node) then return nil, "invalid characters" end
	local parent, name, reason =
		checkAttach(state, session, parts, addNodes, addBytes, subtreeDepth(node), nil)
	if parent == nil then return nil, reason end
	CeroSecOS.stampTree(node, now)
	parent.children[name] = node
	if now ~= nil then parent.mtime = now end
	return node, nil
end

-- true, reason. A directory needs recursive; a recursive removal needs w and x
-- all the way down, so a user cannot drop a subtree he cannot enter.
local function canRemoveTree(state, session, node)
	if node.type ~= "dir" then return true end
	if not CeroSecOS.can(state, session, node, "w") then return false end
	if not CeroSecOS.can(state, session, node, "x") then return false end
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do
		if not canRemoveTree(state, session, node.children[names[i]]) then return false end
	end
	return true
end

--
-- The sticky directory
--
-- /var/tmp is 777: everybody may make a file in it, which is what a scratch
-- directory is for. On a machine where writing a directory were the whole of the
-- question, it would also mean everybody may delete everybody else's work -- so
-- the one thing it does NOT mean is that, and this is where it is refused.
--
-- Only the owner of a node in it, and root, may take that node away or rename it
-- out. The rule is the DIRECTORY's and is decided by the path, exactly as the
-- quota exemptions are: a real machine carries it as a fourth mode digit (1777)
-- and every mode on this one is three digits, in `ls -l`, in chmod's grammar and
-- on the disk, so there is nowhere to put a bit that only one directory would
-- ever wear. What follows from that is written down where it can be read: `ls -l`
-- shows a plain drwxrwxrwx, and the manual says the rule is the place's.
--
-- true when this parent path protects what is in it.
function CeroSecOS.isSticky(parentPath)
	return parentPath == CeroSecOS.TMP_PATH
end

-- May this session take that node out of that directory? Asked by a removal and
-- by a move, because a rename out of a sticky directory is a removal from it.
local function stickyOk(state, session, parentPath, node)
	if not CeroSecOS.isSticky(parentPath) then return true end
	local user = CeroSecOS.userOf(session)
	if user == "root" then return true end
	return node.owner == user
end

function CeroSecOS.removeNode(state, session, path, recursive, now)
	local abs, parts = CeroSecOS.resolve(session, path)
	if #parts == 0 then return nil, "permission denied" end

	-- The link and not what it points at: `rm` takes away the name it was given,
	-- which for a symbolic link is the link. Deleting what a link points at is
	-- done by naming that.
	local node, reason, _, phys = CeroSecOS.getNode(state, session, abs, true)
	if node == nil then return nil, reason end
	-- Where the node really IS, which is where it has to be unhooked from: a path
	-- with a link in the middle of it names a place somewhere else entirely, and
	-- unhooking it from the typed path's parent would take a name away from a
	-- directory that never held it.
	if phys == nil then phys = abs end
	local _, physParts = CeroSecOS.resolve(nil, phys)
	if #physParts == 0 then return nil, "permission denied" end
	-- A device is not the machine's to take away: unplugging a light switch is
	-- done with a screwdriver, standing in front of it.
	if CeroSecOS.isDev(node) then return nil, "is a device" end
	-- And neither is a directory something is mounted on, nor one with a mount
	-- somewhere under it: taking it away would leave a mount written down against
	-- a place that is not there any more (see CeroSecOS.mountUnder).
	if CeroSecOS.mountUnder(state, phys) ~= nil then return nil, "Device busy" end
	if node.type == "dir" then
		if not recursive then return nil, "is a directory" end
		if not canRemoveTree(state, session, node) then return nil, "permission denied" end
	end

	local parentPath, name = CeroSecOS.parentOf(physParts)
	local parent, preason = CeroSecOS.getNode(state, session, parentPath)
	if parent == nil then return nil, preason end
	if not CeroSecOS.can(state, session, parent, "w") then return nil, "permission denied" end
	if not stickyOk(state, session, parentPath, node) then return nil, "permission denied" end

	parent.children[name] = nil
	if now ~= nil then parent.mtime = now end
	return true, nil
end

-- Replace a file's contents. true, reason.
function CeroSecOS.setData(state, session, path, data, now)
	local node, reason, _, phys = CeroSecOS.getNode(state, session, path)
	if node == nil then return nil, reason end
	if node.type ~= "file" then return nil, CeroSecOS.notAFile(node) end
	if not CeroSecOS.can(state, session, node, "w") then return nil, "permission denied" end
	if #data > CeroSecOS.MAX_FILE_BYTES then return nil, "file too large" end
	if CeroSecOS.hasControlBytes(data) then return nil, "invalid characters" end

	-- What the write costs is asked of the disk itself, before and after, rather
	-- than worked out by arithmetic on this one file: whether its bytes count at
	-- all is a question about where it hangs (see the exemption above), and a
	-- subtraction here would be a second answer to it.
	--
	-- A write is refused when it takes the disk PAST the ceiling. One that is
	-- already past it -- a history renamed into an ordinary file is bytes that
	-- were exempt a moment ago -- still lets a shorter line be written over a
	-- longer one, because that is room being made and not room being taken.
	--
	-- And it is asked of the disk the FILE is on, which is the floppy when the file
	-- is under a mount point: a note written on a disk fills the disk and never the
	-- machine it happens to be plugged into.
	local fs = CeroSecOS.fsFor(state, phys)
	local _, before = CeroSecOS.fsUsage(state, fs)
	local old = node.data
	node.data = data
	local _, after = CeroSecOS.fsUsage(state, fs)
	if after > fs.bytes and after > before then
		node.data = old
		return nil, "disk full"
	end

	if now ~= nil then node.mtime = now end
	return true, nil
end

-- Detach a node and reattach it elsewhere, without ever leaving it dangling:
-- the destination is fully checked before the source is unhooked.
--
-- A destination that already exists is REPLACED, which is what rename(2) does and
-- what `mv` has done since there was an mv: the name is made to mean the source,
-- and what it used to mean is gone. Three things stand in the way and the
-- destination's own mode is NOT one of them -- a file you may not write is still a
-- name you may make mean something else, because what is written is the
-- DIRECTORY's listing and w on the directory is the permission for that:
--
--   * a directory is replaced only by a directory, and only an empty one
--     ("directory not empty"): what rename answers with ENOTEMPTY;
--   * a directory is never replaced by a file ("is a directory"), nor a file by a
--     directory ("not a directory");
--   * a sticky directory's rule holds over the name being written as well as the
--     one being taken away: replacing somebody else's file in /var/tmp is
--     destroying it, which is the one thing 777 there does not allow.
--
-- The bytes the destination held are freed by the replacement itself -- one
-- assignment, the old node dropped as the new one lands -- so a move never asks
-- the disk for room it is about to give back.
function CeroSecOS.moveNode(state, session, fromPath, toPath, now)
	local fromAbs, fromParts = CeroSecOS.resolve(session, fromPath)
	if #fromParts == 0 then return nil, "permission denied" end

	-- The link and not its target, exactly as with a removal: moving a link moves
	-- the link, and a relative target now means something else, which is what it
	-- means on every machine that has ever had them.
	local node, reason, _, fromPhys = CeroSecOS.getNode(state, session, fromAbs, true)
	if node == nil then return nil, reason end
	if CeroSecOS.isDev(node) then return nil, "is a device" end

	-- Both ends as the walk really reaches them, and every rule below asked with
	-- those and never with what was typed. A link in the middle of either path
	-- names a place on another filesystem, in another directory, possibly under a
	-- mount -- and a rename judged on the name instead of the place unhooked a node
	-- from a directory that never held it, and carried a tree onto a disk whose
	-- ceilings it had never been shown.
	if fromPhys == nil then fromPhys = fromAbs end
	local _, fromPhysParts = CeroSecOS.resolve(nil, fromPhys)
	if #fromPhysParts == 0 then return nil, "permission denied" end
	local toPhys = CeroSecOS.physicalOf(state, session, toPath)
	if toPhys == nil then return nil, "file exists" end
	local _, toParts = CeroSecOS.resolve(nil, toPhys)
	-- A mount point is not a name to move, and neither is a directory with a mount
	-- under it; nor is a name that would be WRITTEN OVER one, which is the same
	-- unhooking done from the other end.
	if CeroSecOS.mountUnder(state, fromPhys) ~= nil then return nil, "Device busy" end
	if CeroSecOS.mountUnder(state, toPhys) ~= nil then return nil, "Device busy" end
	-- A rename is ONE filesystem's operation and cannot reach across two, which is
	-- what rename(2) answers EXDEV to -- "Cross-device link", in the words the
	-- system has used for it since there were two devices. The way across is `cp`
	-- and then `rm`: two acts, because they can fail separately, and a machine that
	-- hid a half-finished copy behind the word "mv" would be a machine that lost a
	-- file while saying it had moved one. The manual says so.
	--
	-- Judged here and not in `mv`, so that the order of the refusals is the order
	-- the mutator checks them in: a mount point named as the source is Device busy
	-- and not a cross-device link, which is the truer of the two sentences about it.
	if CeroSecOS.fsFor(state, fromPhys).at ~= CeroSecOS.fsFor(state, toPhys).at then
		return nil, "cross-device link"
	end
	if CeroSecOS.isInside(toPhys, fromPhys) then return nil, "invalid destination" end

	local fromParentPath, fromName = CeroSecOS.parentOf(fromPhysParts)
	local fromParent, freason = CeroSecOS.getNode(state, session, fromParentPath)
	if fromParent == nil then return nil, freason end
	if not CeroSecOS.can(state, session, fromParent, "w") then return nil, "permission denied" end
	-- Moving a file OUT of a sticky directory is taking it away from it, so it is
	-- the same question a removal asks. Moving one IN is not: making a name in a
	-- directory you may write is what 777 means.
	if not stickyOk(state, session, fromParentPath, node) then return nil, "permission denied" end

	local parent, name, areason =
		checkAttach(state, session, toParts, 0, 0, subtreeDepth(node), fromParent, true)
	if parent == nil then return nil, areason end

	-- What is about to be written over, judged before anything is unhooked.
	local old = parent.children[name]
	if old ~= nil and old ~= node then
		-- Not through a move. A device is the world around the machine and is not
		-- a name on the disk to be written over (see removeNode).
		if CeroSecOS.isDev(old) then return nil, "is a device" end
		if node.type == "dir" then
			if old.type ~= "dir" then return nil, "not a directory" end
			if CeroSecOS.countEntries(old) > 0 then return nil, "directory not empty" end
		elseif old.type == "dir" then
			return nil, "is a directory"
		end
		local toParentPath = CeroSecOS.parentOf(toParts)
		if not stickyOk(state, session, toParentPath, old) then return nil, "permission denied" end
	end

	fromParent.children[fromName] = nil
	parent.children[name] = node
	if now ~= nil then
		-- The node itself as well as the two listings: one timestamp standing
		-- in for the ctime a real filesystem would have moved here.
		node.mtime = now
		fromParent.mtime = now
		parent.mtime = now
	end
	return true, nil
end

-- Deep copy of a node, used by cp. Plain tables only, so this stays trivial.
function CeroSecOS.copyNode(node, owner)
	if node.type == "file" then
		return CeroSecOS.newFile(owner or node.owner, node.mode, node.data)
	end
	-- A link inside a copied tree is copied AS A LINK, which is what cp -R does:
	-- following one would be a copy that walks out of the tree it was given, and
	-- a link to an ancestor would be a copy with no end to it. A link named on the
	-- line is a different question and is followed (see commands.cp).
	if node.type == "link" then
		return CeroSecOS.newLink(owner or node.owner, node.target)
	end
	local copy = CeroSecOS.newDir(owner or node.owner, node.mode)
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do
		copy.children[names[i]] = CeroSecOS.copyNode(node.children[names[i]], owner)
	end
	return copy
end

-- Write text to a path, creating the file when it is missing. Used by the
-- write command and by ">" / ">>" redirection alike.
function CeroSecOS.writeFile(state, session, path, text, append, now)
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node ~= nil then
		-- A device is not written this way. The redirect path in the shell
		-- catches one before it ever reaches here, and the editor, `write` and
		-- everything else that saves text is refused: a device has no contents
		-- to replace.
		if node.type ~= "file" then return nil, CeroSecOS.notAFile(node) end
		local data = text
		if append then
			local old = node.data or ""
			if old ~= "" then data = old .. "\n" .. text else data = text end
		end
		return CeroSecOS.setData(state, session, path, data, now)
	end
	if reason ~= "no such file" then return nil, reason end
	local user = CeroSecOS.userOf(session) or "root"
	local created, creason =
		CeroSecOS.createNode(state, session, path, CeroSecOS.newFile(user, 644, text), now)
	if created == nil then return nil, creason end
	return true, nil
end
