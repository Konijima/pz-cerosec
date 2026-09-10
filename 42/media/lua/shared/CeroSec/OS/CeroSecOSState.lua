--
-- CeroSec OS core: state, validation, migration.
--
-- The state is already plain nested tables, so there is nothing to serialize;
-- what it needs instead is a gate that says whether a blob handed back by the
-- game is still something the core can run on.
--

CeroSecOS = CeroSecOS or {}

-- A fresh machine: the standard skeleton, root and admin, both open.
function CeroSecOS.newState(hostname)
	if type(hostname) ~= "string" or hostname == "" then
		hostname = CeroSecOS.DEFAULT_HOSTNAME
	end

	local root = CeroSecOS.newDir("root", 755)
	root.children.bin = CeroSecOS.newDir("root", 755)
	root.children.home = CeroSecOS.newDir("root", 755)
	root.children.home.children.admin = CeroSecOS.newDir("admin", 750)
	root.children.root = CeroSecOS.newDir("root", 700)
	root.children.dev = CeroSecOS.newDir("root", 755) -- reserved for the device rung
	root.children.etc = CeroSecOS.newDir("root", 755)
	root.children.etc.children.hostname = CeroSecOS.newFile("root", 644, hostname)
	root.children.etc.children.motd = CeroSecOS.newFile("root", 644, CeroSecOS.MOTD)

	return {
		v = CeroSecOS.STATE_VERSION,
		hostname = hostname,
		users = {
			root = CeroSecOS.newUser("root", "", "/root", true),
			admin = CeroSecOS.newUser("admin", "", "/home/admin", false),
		},
		fs = root,
		sessions = {},
	}
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

local function checkNode(node, where, depth, tally)
	if type(node) ~= "table" then return false, where .. ": not a node" end
	if type(node.owner) ~= "string" then return false, where .. ": bad owner" end
	if type(node.mode) ~= "number" then return false, where .. ": bad mode" end
	if node.mode < 0 or node.mode > 777 or node.mode ~= math.floor(node.mode) then
		return false, where .. ": bad mode"
	end
	if depth > CeroSecOS.MAX_DEPTH then return false, where .. ": too deep" end

	tally.nodes = tally.nodes + 1
	if tally.nodes > CeroSecOS.MAX_NODES then return false, "too many nodes" end

	if node.type == "file" then
		if type(node.data) ~= "string" then return false, where .. ": bad data" end
		if #node.data > CeroSecOS.MAX_FILE_BYTES then return false, where .. ": file too large" end
		-- A blob handed back by the game never went through setData, so the
		-- printable rule is re-checked here rather than assumed.
		if CeroSecOS.hasControlBytes(node.data) then return false, where .. ": invalid characters" end
		tally.bytes = tally.bytes + #node.data
		if tally.bytes > CeroSecOS.MAX_TOTAL_BYTES then return false, "disk full" end
		return true
	end

	if node.type ~= "dir" then return false, where .. ": bad type" end
	if type(node.children) ~= "table" then return false, where .. ": bad children" end
	local names = CeroSecOS.childNames(node)
	if #names > CeroSecOS.MAX_DIR_ENTRIES then return false, where .. ": directory full" end
	for i = 1, #names do
		local name = names[i]
		if not CeroSecOS.isValidName(name) then return false, where .. "/" .. name .. ": invalid name" end
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
	if type(state.hostname) ~= "string" or not CeroSecOS.isValidName(state.hostname) then
		return false, "bad hostname"
	end
	if type(state.users) ~= "table" then return false, "bad users" end
	if type(state.users.root) ~= "table" then return false, "no root user" end
	for name, user in pairs(state.users) do
		if type(name) ~= "string" or not CeroSecOS.isValidName(name) then return false, "bad user name" end
		if user.name ~= name then return false, "user " .. name .. ": name mismatch" end
		-- Never a cleartext password: what is stored is "$cs1$<salt>$<hash>" and
		-- nothing else. A state saved before this rung is repaired by migrate,
		-- which runs before this gate; anything still in clear when it gets
		-- here was forged.
		if CeroSecOS.splitHash(user.password) == nil then
			return false, "user " .. name .. ": bad password"
		end
		if type(user.home) ~= "string" then return false, "user " .. name .. ": bad home" end
		if type(user.admin) ~= "boolean" then return false, "user " .. name .. ": bad admin flag" end
	end

	if type(state.fs) ~= "table" then return false, "bad fs" end
	if state.fs.type ~= "dir" then return false, "fs root is not a directory" end
	return checkNode(state.fs, "", 0, { nodes = 0, bytes = 0 })
end

-- Anything the game hands back becomes a v1 state. Today there is no older
-- schema, so nil and junk alike become a fresh machine; a v1 state passes
-- through untouched.
function CeroSecOS.migrate(state, hostname)
	if type(state) == "table" and state.v == CeroSecOS.STATE_VERSION then
		-- Passwords first: a machine saved before this rung carries them in
		-- clear, and validate refuses those. Repairing before the gate is what
		-- keeps such a machine's filesystem instead of throwing it away.
		CeroSecOS.migrateUsers(state)
		local ok = CeroSecOS.validate(state)
		if ok then return state end
	end
	return CeroSecOS.newState(hostname)
end
