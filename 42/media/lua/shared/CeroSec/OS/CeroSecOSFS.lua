--
-- CeroSec OS core: the filesystem.
--
-- Every mutation in the whole OS goes through createNode, removeNode, setData
-- or moveNode, and every read through getNode. Permissions and limits are
-- enforced there and only there, so a new command cannot invent a hole.
--
-- Nodes are plain tables:
--   dir  = { type = "dir",  owner = "root",  mode = 750, children = { [name] = node } }
--   file = { type = "file", owner = "admin", mode = 640, data = "text" }
--
-- Reasons returned here are bare ("no such file"); the shell prefixes them with
-- the command and the argument as typed.
--

CeroSecOS = CeroSecOS or {}

local BITS = { r = 4, w = 2, x = 1 }

--
-- Node constructors.
--

function CeroSecOS.newDir(owner, mode)
	return { type = "dir", owner = owner or "root", mode = mode or 755, children = {} }
end

function CeroSecOS.newFile(owner, mode, data)
	return { type = "file", owner = owner or "root", mode = mode or 644, data = data or "" }
end

--
-- Permissions. Octal owner/group/other; only owner and other are enforced, the
-- group digit is kept for a later rung. root bypasses everything.
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
	else
		digit = mode % 10
	end
	local bit = BITS[what]
	return math.floor(digit / bit) % 2 == 1
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

-- Nodes and data bytes in a subtree, the node itself included.
function CeroSecOS.subtreeUsage(node)
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

-- Whole-computer usage.
function CeroSecOS.usage(state)
	if state == nil or state.fs == nil then return 0, 0 end
	return CeroSecOS.subtreeUsage(state.fs)
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
	if not CeroSecOS.isValidName(name) then return nil, nil, "invalid name" end
	if #parts + addDepth > CeroSecOS.MAX_DEPTH then return nil, nil, "path too deep" end

	local parentPath = CeroSecOS.parentOf(parts)
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
function CeroSecOS.createNode(state, session, path, node)
	local _, parts = CeroSecOS.resolve(session, path)
	local addNodes, addBytes = CeroSecOS.subtreeUsage(node)
	if node.type == "file" and #(node.data or "") > CeroSecOS.MAX_FILE_BYTES then
		return nil, "file too large"
	end
	local parent, name, reason =
		checkAttach(state, session, parts, addNodes, addBytes, subtreeDepth(node), nil)
	if parent == nil then return nil, reason end
	parent.children[name] = node
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

function CeroSecOS.removeNode(state, session, path, recursive)
	local abs, parts = CeroSecOS.resolve(session, path)
	if #parts == 0 then return nil, "permission denied" end

	local node, reason = CeroSecOS.getNode(state, session, abs)
	if node == nil then return nil, reason end
	if node.type == "dir" then
		if not recursive then return nil, "is a directory" end
		if not canRemoveTree(state, session, node) then return nil, "permission denied" end
	end

	local parentPath, name = CeroSecOS.parentOf(parts)
	local parent, preason = CeroSecOS.getNode(state, session, parentPath)
	if parent == nil then return nil, preason end
	if not CeroSecOS.can(state, session, parent, "w") then return nil, "permission denied" end

	parent.children[name] = nil
	return true, nil
end

-- Replace a file's contents. true, reason.
function CeroSecOS.setData(state, session, path, data)
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node == nil then return nil, reason end
	if node.type ~= "file" then return nil, "is a directory" end
	if not CeroSecOS.can(state, session, node, "w") then return nil, "permission denied" end
	if #data > CeroSecOS.MAX_FILE_BYTES then return nil, "file too large" end

	local _, bytes = CeroSecOS.usage(state)
	if bytes - #(node.data or "") + #data > CeroSecOS.MAX_TOTAL_BYTES then
		return nil, "disk full"
	end

	node.data = data
	return true, nil
end

-- Detach a node and reattach it elsewhere, without ever leaving it dangling:
-- the destination is fully checked before the source is unhooked.
function CeroSecOS.moveNode(state, session, fromPath, toPath)
	local fromAbs, fromParts = CeroSecOS.resolve(session, fromPath)
	local toAbs, toParts = CeroSecOS.resolve(session, toPath)
	if #fromParts == 0 then return nil, "permission denied" end

	local node, reason = CeroSecOS.getNode(state, session, fromAbs)
	if node == nil then return nil, reason end
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
function CeroSecOS.writeFile(state, session, path, text, append)
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node ~= nil then
		if node.type ~= "file" then return nil, "is a directory" end
		local data = text
		if append then
			local old = node.data or ""
			if old ~= "" then data = old .. "\n" .. text else data = text end
		end
		return CeroSecOS.setData(state, session, path, data)
	end
	if reason ~= "no such file" then return nil, reason end
	local user = CeroSecOS.userOf(session) or "root"
	local created, creason = CeroSecOS.createNode(state, session, path, CeroSecOS.newFile(user, 644, text))
	if created == nil then return nil, creason end
	return true, nil
end
