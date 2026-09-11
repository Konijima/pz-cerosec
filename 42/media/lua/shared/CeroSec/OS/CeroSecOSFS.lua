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
	return "is a directory"
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
-- file are exempt from the 32K, and all three are things a machine writes
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

-- Does any file in this subtree carry a byte that must never be stored? Whole
-- trees arrive at createNode (a copy today, a network transfer at a later
-- rung), so the check cannot stop at the node itself.
function CeroSecOS.subtreeHasControlBytes(node)
	if node.type == "file" then return CeroSecOS.hasControlBytes(node.data or "") end
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
function CeroSecOS.getNode(state, session, path)
	local abs, parts = CeroSecOS.resolve(session, path)
	local node = state.fs
	for i = 1, #parts do
		if node.type ~= "dir" then return nil, "not a directory", abs end
		if not CeroSecOS.can(state, session, node, "x") then return nil, "permission denied", abs end
		local child = node.children[parts[i]]
		if child == nil then return nil, "no such file", abs end
		node = child
	end
	return node, nil, abs
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
local function checkAttach(state, session, parts, addNodes, addBytes, addDepth, fromParent)
	if #parts == 0 then return nil, nil, "file exists" end
	local name = parts[#parts]
	if not CeroSecOS.isValidFileName(name) then return nil, nil, "invalid name" end
	if #parts + addDepth > CeroSecOS.MAX_DEPTH then return nil, nil, "path too deep" end

	local parentPath = CeroSecOS.parentOf(parts)
	-- /dev is not a directory anybody writes into. Its contents are the world
	-- around the machine, worked out afresh at every command, so a file put
	-- there would be gone by the next one -- and root is not told a lie about a
	-- write that will not last. The commands that create say so in their own
	-- words; this is the gate under all of them, so cp and mv cannot go round.
	if parentPath == CeroSecOS.DEV_PATH then return nil, nil, "read-only" end
	local parent, reason = CeroSecOS.getNode(state, session, parentPath)
	if parent == nil then return nil, nil, reason end
	if parent.type ~= "dir" then return nil, nil, "not a directory" end
	if parent.children[name] ~= nil then return nil, nil, "file exists" end
	if not CeroSecOS.can(state, session, parent, "w") then return nil, nil, "permission denied" end
	if parent ~= fromParent and CeroSecOS.countEntries(parent) >= CeroSecOS.MAX_DIR_ENTRIES then
		return nil, nil, "directory full"
	end

	if addNodes > 0 or addBytes > 0 then
		local nodes, bytes = CeroSecOS.usage(state)
		if nodes + addNodes > CeroSecOS.MAX_NODES then return nil, nil, "disk full" end
		if bytes + addBytes > CeroSecOS.MAX_TOTAL_BYTES then return nil, nil, "disk full" end
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

function CeroSecOS.removeNode(state, session, path, recursive, now)
	local abs, parts = CeroSecOS.resolve(session, path)
	if #parts == 0 then return nil, "permission denied" end

	local node, reason = CeroSecOS.getNode(state, session, abs)
	if node == nil then return nil, reason end
	-- A device is not the machine's to take away: unplugging a light switch is
	-- done with a screwdriver, standing in front of it.
	if CeroSecOS.isDev(node) then return nil, "is a device" end
	if node.type == "dir" then
		if not recursive then return nil, "is a directory" end
		if not canRemoveTree(state, session, node) then return nil, "permission denied" end
	end

	local parentPath, name = CeroSecOS.parentOf(parts)
	local parent, preason = CeroSecOS.getNode(state, session, parentPath)
	if parent == nil then return nil, preason end
	if not CeroSecOS.can(state, session, parent, "w") then return nil, "permission denied" end

	parent.children[name] = nil
	if now ~= nil then parent.mtime = now end
	return true, nil
end

-- Replace a file's contents. true, reason.
function CeroSecOS.setData(state, session, path, data, now)
	local node, reason = CeroSecOS.getNode(state, session, path)
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
	local _, before = CeroSecOS.usage(state)
	local old = node.data
	node.data = data
	local _, after = CeroSecOS.usage(state)
	if after > CeroSecOS.MAX_TOTAL_BYTES and after > before then
		node.data = old
		return nil, "disk full"
	end

	if now ~= nil then node.mtime = now end
	return true, nil
end

-- Detach a node and reattach it elsewhere, without ever leaving it dangling:
-- the destination is fully checked before the source is unhooked.
function CeroSecOS.moveNode(state, session, fromPath, toPath, now)
	local fromAbs, fromParts = CeroSecOS.resolve(session, fromPath)
	local toAbs, toParts = CeroSecOS.resolve(session, toPath)
	if #fromParts == 0 then return nil, "permission denied" end

	local node, reason = CeroSecOS.getNode(state, session, fromAbs)
	if node == nil then return nil, reason end
	if CeroSecOS.isDev(node) then return nil, "is a device" end
	if CeroSecOS.isInside(toAbs, fromAbs) then return nil, "invalid destination" end

	local fromParentPath, fromName = CeroSecOS.parentOf(fromParts)
	local fromParent, freason = CeroSecOS.getNode(state, session, fromParentPath)
	if fromParent == nil then return nil, freason end
	if not CeroSecOS.can(state, session, fromParent, "w") then return nil, "permission denied" end

	local parent, name, areason =
		checkAttach(state, session, toParts, 0, 0, subtreeDepth(node), fromParent)
	if parent == nil then return nil, areason end

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
