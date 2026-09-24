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

-- The same rule, for a name on the DISK, with two exceptions that are Unix's
-- own. The test command has been two files since the seventies, `test` and
-- `[`, and a machine that could not hold /bin/[ would be a machine where
-- `[ -f f ]` is a builtin with no file behind it while every other command has
-- one. And a file may begin with "-": 4.4BSD's namei refuses only "/" and NUL
-- in a name, and `rm -- -f` (getopt(3)'s "--") and `rm ./-f` are how a Unix
-- user has always got rid of one. The flag worry isValidName answers is a
-- worry about LOGINS and hostnames, which are written into lines other
-- programs read; nothing in the engine builds a command line out of a file's
-- name. Nothing else punctuational is allowed in (the "errno" entry of
-- CeroSecOS.DEVIATIONS, "invalid characters"), and an account or a group is
-- still isValidName's -- there is no user called "[" or "-f".
function CeroSecOS.isValidFileName(name)
	if name == "[" then return true end
	if type(name) == "string" and string.sub(name, 1, 1) == "-" then
		-- The same length and characters, the dash let through in front.
		return CeroSecOS.isValidName("x" .. string.sub(name, 2))
	end
	return CeroSecOS.isValidName(name)
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

-- The directories a command name is looked for in, in the order PATH names
-- them. Pure string work like the rest of this file: nothing here looks at the
-- disk, and a directory that is not one is the walk's problem and not the
-- split's.
--
-- An empty field is the working directory, which is what a leading, a trailing
-- or a doubled colon has meant since PATH existed -- ":/bin" looks here first --
-- and it comes back as "." so it is resolved against the session's cwd like any
-- other relative path. So an empty PATH is one field and not none: it is the
-- working directory, and nothing in /bin answers a bare name at all.
function CeroSecOS.pathDirs(value)
	local dirs = {}
	if type(value) ~= "string" then return dirs end
	local from = 1
	while true do
		local p = string.find(value, ":", from, true)
		local piece
		if p == nil then
			piece = string.sub(value, from)
		else
			piece = string.sub(value, from, p - 1)
		end
		if piece == "" then piece = "." end
		dirs[#dirs + 1] = piece
		if p == nil then return dirs end
		from = p + 1
	end
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
