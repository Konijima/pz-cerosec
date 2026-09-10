--
-- CeroSec OS core: paths.
--
-- Paths are "/"-separated, absolute or relative to the session's cwd, with "."
-- and ".." resolved here and nowhere else. Resolution is pure string work: it
-- never looks at the filesystem, so it cannot leak anything a user may not see.
--

CeroSecOS = CeroSecOS or {}

-- A name is 1..32 characters of [A-Za-z0-9._-] and never starts with "-", so a
-- filename can never be mistaken for a flag. "." and ".." pass this test but
-- are eaten by resolve(), so they never reach a create.
function CeroSecOS.isValidName(name)
	if type(name) ~= "string" then return false end
	if #name < 1 or #name > CeroSecOS.MAX_NAME then return false end
	if string.find(name, "^%-") ~= nil then return false end
	if string.find(name, "[^A-Za-z0-9._%-]") ~= nil then return false end
	return true
end

-- path -> absolute path string, array of its components.
-- An empty or nil path means the session's cwd. Trailing slashes, doubled
-- slashes and "." are dropped; ".." pops, and popping past "/" stays at "/".
function CeroSecOS.resolve(session, path)
	local cwd = "/"
	if session ~= nil and type(session.cwd) == "string" then cwd = session.cwd end
	if path == nil or path == "" then path = cwd end

	local parts = {}
	if string.sub(path, 1, 1) ~= "/" then
		for part in string.gmatch(cwd, "[^/]+") do
			parts[#parts + 1] = part
		end
	end
	for part in string.gmatch(path, "[^/]+") do
		if part == "." then
			-- stay where we are
		elseif part == ".." then
			if #parts > 0 then parts[#parts] = nil end
		else
			parts[#parts + 1] = part
		end
	end

	return "/" .. table.concat(parts, "/"), parts
end

-- "~" and "~/..." -> the home that goes with them. Everything else, including
-- "~somebody" and a "~" anywhere but at the front, comes back untouched: this
-- is a one-account shortcut and not a directory of the machine's users, and a
-- tilde inside a name is a character isValidName refuses anyway, so it ends as
-- "no such file" rather than as somebody else's home.
--
-- Pure, like the rest of this file: the home is handed in. The shell is what
-- knows whose it is, and expands before a command ever sees the argument --
-- which is where a real shell does it too.
function CeroSecOS.expandHome(path, home)
	if type(path) ~= "string" or type(home) ~= "string" or home == "" then return path end
	if path == "~" then return home end
	if string.sub(path, 1, 2) == "~/" then return home .. "/" .. string.sub(path, 3) end
	return path
end

-- Absolute path of the directory holding the given components, plus the last
-- component. Returns nil for "/" itself, which has no parent.
-- table.concat is called with two arguments only: the four-argument form is not
-- worth betting on under Kahlua.
function CeroSecOS.parentOf(parts)
	if #parts == 0 then return nil, nil end
	local head = {}
	for i = 1, #parts - 1 do head[i] = parts[i] end
	return "/" .. table.concat(head, "/"), parts[#parts]
end

-- true when child is inside parent (or is parent). Used by mv to refuse moving
-- a directory into its own subtree.
function CeroSecOS.isInside(child, parent)
	if child == parent then return true end
	if parent == "/" then return true end
	return string.sub(child, 1, #parent + 1) == parent .. "/"
end
