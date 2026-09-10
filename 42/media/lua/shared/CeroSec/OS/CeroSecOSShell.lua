--
-- CeroSec OS core: the shell.
--
-- exec(state, session, line) -> ok, lines, control. One command line at a time:
-- double quoted strings with backslash escapes, ">" and ">>" redirection, no
-- pipes and
-- no variables yet. control is nil, "clear" or "exit": an order to the terminal
-- travels beside the output, never inside it, so no file's contents can ever be
-- mistaken for one. Errors read like a 1993 Unix, one line each:
--   cd: /root: permission denied
--   cat: notes.txt: no such file
-- Commands never touch the tree themselves; they call the four mutators in
-- CeroSecOSFS.lua, which own the permissions and the limits.
--

CeroSecOS = CeroSecOS or {}

CeroSecOS.commands = CeroSecOS.commands or {}
local commands = CeroSecOS.commands

--
-- Line parsing.
--

-- args, redirect, reason. redirect is { path = "notes.txt", append = false }.
function CeroSecOS.parseLine(line)
	local args, redirect, pending = {}, nil, nil
	local i, n = 1, #line

	while i <= n do
		local c = string.sub(line, i, i)
		if c == " " or c == "\t" then
			i = i + 1
		elseif c == ">" then
			if pending ~= nil or redirect ~= nil then
				return nil, nil, "syntax error: bad redirect"
			end
			i = i + 1
			pending = "w"
			if string.sub(line, i, i) == ">" then
				pending = "a"
				i = i + 1
			end
		else
			-- One token: bare characters, plus any number of quoted runs.
			local buf = ""
			while i <= n do
				local ch = string.sub(line, i, i)
				if ch == " " or ch == "\t" or ch == ">" then
					break
				elseif ch == "\"" then
					i = i + 1
					local closed = false
					while i <= n do
						local q = string.sub(line, i, i)
						if q == "\\" then
							local nx = string.sub(line, i + 1, i + 1)
							if nx == "" then return nil, nil, "syntax error: unterminated quote" end
							if nx == "n" then buf = buf .. "\n"
							elseif nx == "t" then buf = buf .. "\t"
							else buf = buf .. nx end
							i = i + 2
						elseif q == "\"" then
							closed = true
							i = i + 1
							break
						else
							buf = buf .. q
							i = i + 1
						end
					end
					if not closed then return nil, nil, "syntax error: unterminated quote" end
				else
					buf = buf .. ch
					i = i + 1
				end
			end
			if pending ~= nil then
				redirect = { path = buf, append = (pending == "a") }
				pending = nil
			else
				args[#args + 1] = buf
			end
		end
	end

	if pending ~= nil then return nil, nil, "syntax error: missing redirect target" end
	if redirect ~= nil and redirect.path == "" then
		return nil, nil, "syntax error: missing redirect target"
	end
	return args, redirect, nil
end

--
-- Shared bits of the commands.
--

local function fail(cmd, arg, reason)
	if arg == nil then return false, { cmd .. ": " .. reason } end
	return false, { cmd .. ": " .. arg .. ": " .. reason }
end

local function usage(cmd, form)
	return false, { cmd .. ": usage: " .. form }
end

local function isOwnerOrRoot(session, node)
	local user = CeroSecOS.userOf(session)
	return user == "root" or node.owner == user
end

local function baseName(session, path)
	local _, parts = CeroSecOS.resolve(session, path)
	if #parts == 0 then return nil end
	return parts[#parts]
end

-- "750" or "0750" -> 750. nil when it is not three octal digits.
local function parseMode(s)
	if type(s) ~= "string" then return nil end
	if string.find(s, "^0[0-7][0-7][0-7]$") ~= nil then s = string.sub(s, 2) end
	if string.find(s, "^[0-7][0-7][0-7]$") == nil then return nil end
	return tonumber(s)
end

local function permString(node)
	local s = "-"
	if node.type == "dir" then s = "d" end
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

-- ls -l columns: 10 + 2 + 8 + 2 + 31 + 2 + 5 = exactly 60.
local L_OWNER, L_NAME, L_SIZE = 8, 31, 5

local function longLine(node, name)
	local size
	if node.type == "dir" then
		size = CeroSecOS.countEntries(node)
	else
		size = #(node.data or "")
	end
	return permString(node)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.owner or "?", L_OWNER), L_OWNER)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(name, L_NAME), L_NAME)
		.. "  " .. CeroSecOS.padLeft(tostring(size), L_SIZE)
end

--
-- Commands.
--

commands.help = function(state, session, args)
	return true, {
		"CeroSec OS commands:",
		" cat cd chmod chown clear cp echo exit help hostname ls",
		" mkdir mv pwd rm touch whoami write",
		" redirect output with > file or >> file",
	}
end

commands.pwd = function(state, session, args)
	if #args > 1 then return usage("pwd", "pwd") end
	return true, { session.cwd }
end

commands.whoami = function(state, session, args)
	if #args > 1 then return usage("whoami", "whoami") end
	return true, { session.user }
end

commands.hostname = function(state, session, args)
	if #args > 1 then return usage("hostname", "hostname") end
	return true, { state.hostname }
end

commands.clear = function(state, session, args)
	return true, {}, "clear"
end

commands.exit = function(state, session, args)
	return true, {}, "exit"
end

commands.echo = function(state, session, args)
	if #args < 2 then return true, { "" } end
	local words = {}
	for i = 2, #args do words[#words + 1] = args[i] end
	return true, { table.concat(words, " ") }
end

commands.cd = function(state, session, args)
	if #args > 2 then return usage("cd", "cd [dir]") end
	local target = args[2]
	if target == nil or target == "" then
		local user = CeroSecOS.getUser(state, session.user)
		target = "/"
		if user ~= nil and type(user.home) == "string" then target = user.home end
	end
	local node, reason, abs = CeroSecOS.getNode(state, session, target)
	if node == nil then return fail("cd", target, reason) end
	if node.type ~= "dir" then return fail("cd", target, "not a directory") end
	if not CeroSecOS.can(state, session, node, "x") then return fail("cd", target, "permission denied") end
	session.cwd = abs
	return true, {}
end

commands.ls = function(state, session, args)
	local long, path = false, nil
	for i = 2, #args do
		local a = args[i]
		if a == "-l" then
			long = true
		elseif string.sub(a, 1, 1) == "-" and a ~= "-" then
			return fail("ls", a, "unknown option")
		elseif path == nil then
			path = a
		else
			return usage("ls", "ls [-l] [path]")
		end
	end

	local shown = path
	if shown == nil then shown = "." end
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node == nil then return fail("ls", shown, reason) end

	if node.type ~= "dir" then
		local name = baseName(session, path) or shown
		if long then return true, { longLine(node, name) } end
		return true, { CeroSecOS.truncate(name, CeroSecOS.COLS) }
	end
	if not CeroSecOS.can(state, session, node, "r") then return fail("ls", shown, "permission denied") end

	local names = CeroSecOS.childNames(node)
	local out = {}
	for i = 1, #names do
		if long then
			out[#out + 1] = longLine(node.children[names[i]], names[i])
		else
			out[#out + 1] = CeroSecOS.truncate(names[i], CeroSecOS.COLS)
		end
	end
	return true, out
end

commands.mkdir = function(state, session, args)
	if #args ~= 2 then return usage("mkdir", "mkdir <dir>") end
	local dir = CeroSecOS.newDir(CeroSecOS.userOf(session), 755)
	local created, reason = CeroSecOS.createNode(state, session, args[2], dir)
	if created == nil then return fail("mkdir", args[2], reason) end
	return true, {}
end

commands.touch = function(state, session, args)
	if #args ~= 2 then return usage("touch", "touch <file>") end
	local node, reason = CeroSecOS.getNode(state, session, args[2])
	if node ~= nil then
		if node.type ~= "file" then return fail("touch", args[2], "is a directory") end
		return true, {} -- nothing to stamp: the core has no clock yet
	end
	if reason ~= "no such file" then return fail("touch", args[2], reason) end
	local file = CeroSecOS.newFile(CeroSecOS.userOf(session), 644, "")
	local created, creason = CeroSecOS.createNode(state, session, args[2], file)
	if created == nil then return fail("touch", args[2], creason) end
	return true, {}
end

commands.cat = function(state, session, args)
	if #args < 2 then return usage("cat", "cat <file>") end
	local out, ok = {}, true
	for i = 2, #args do
		local p = args[i]
		local node, reason = CeroSecOS.getNode(state, session, p)
		if node == nil then
			ok = false
			out[#out + 1] = "cat: " .. p .. ": " .. reason
		elseif node.type ~= "file" then
			ok = false
			out[#out + 1] = "cat: " .. p .. ": is a directory"
		elseif not CeroSecOS.can(state, session, node, "r") then
			ok = false
			out[#out + 1] = "cat: " .. p .. ": permission denied"
		else
			local lines = CeroSecOS.splitLines(node.data)
			for j = 1, #lines do out[#out + 1] = lines[j] end
		end
	end
	return ok, out
end

commands.rm = function(state, session, args)
	local recursive, paths = false, {}
	for i = 2, #args do
		local a = args[i]
		if a == "-r" then
			recursive = true
		elseif string.sub(a, 1, 1) == "-" and a ~= "-" then
			return fail("rm", a, "unknown option")
		else
			paths[#paths + 1] = a
		end
	end
	if #paths == 0 then return usage("rm", "rm [-r] <path>") end

	local out, ok = {}, true
	for i = 1, #paths do
		local done, reason = CeroSecOS.removeNode(state, session, paths[i], recursive)
		if done == nil then
			ok = false
			out[#out + 1] = "rm: " .. paths[i] .. ": " .. reason
		end
	end
	return ok, out
end

commands.mv = function(state, session, args)
	if #args ~= 3 then return usage("mv", "mv <src> <dst>") end
	local src, dst = args[2], args[3]

	local node, reason = CeroSecOS.getNode(state, session, src)
	if node == nil then return fail("mv", src, reason) end

	local target = dst
	local dstNode = CeroSecOS.getNode(state, session, dst)
	if dstNode ~= nil and dstNode.type == "dir" then
		local name = baseName(session, src)
		if name == nil then return fail("mv", src, "permission denied") end
		target = dst .. "/" .. name
	end

	local done, mreason = CeroSecOS.moveNode(state, session, src, target)
	if done == nil then return fail("mv", target, mreason) end
	return true, {}
end

commands.cp = function(state, session, args)
	if #args ~= 3 then return usage("cp", "cp <src> <dst>") end
	local src, dst = args[2], args[3]

	local node, reason = CeroSecOS.getNode(state, session, src)
	if node == nil then return fail("cp", src, reason) end
	if node.type ~= "file" then return fail("cp", src, "is a directory") end
	if not CeroSecOS.can(state, session, node, "r") then return fail("cp", src, "permission denied") end

	local target = dst
	local dstNode = CeroSecOS.getNode(state, session, dst)
	if dstNode ~= nil and dstNode.type == "dir" then
		local name = baseName(session, src)
		if name == nil then return fail("cp", src, "permission denied") end
		target = dst .. "/" .. name
	end

	local copy = CeroSecOS.copyNode(node, CeroSecOS.userOf(session))
	local created, creason = CeroSecOS.createNode(state, session, target, copy)
	if created == nil then return fail("cp", target, creason) end
	return true, {}
end

commands.chmod = function(state, session, args)
	if #args ~= 3 then return usage("chmod", "chmod <mode> <path>") end
	local mode = parseMode(args[2])
	if mode == nil then return fail("chmod", args[2], "invalid mode") end
	local node, reason = CeroSecOS.getNode(state, session, args[3])
	if node == nil then return fail("chmod", args[3], reason) end
	if not isOwnerOrRoot(session, node) then return fail("chmod", args[3], "permission denied") end
	node.mode = mode
	return true, {}
end

commands.chown = function(state, session, args)
	if #args ~= 3 then return usage("chown", "chown <user> <path>") end
	local user = CeroSecOS.getUser(state, args[2])
	if user == nil then return fail("chown", args[2], "no such user") end
	local node, reason = CeroSecOS.getNode(state, session, args[3])
	if node == nil then return fail("chown", args[3], reason) end
	if not isOwnerOrRoot(session, node) then return fail("chown", args[3], "permission denied") end
	node.owner = user.name
	return true, {}
end

-- Internal: how the editor saves. The editor UI is not part of the core.
commands.write = function(state, session, args)
	if #args ~= 3 then return usage("write", "write <file> <text>") end
	local done, reason = CeroSecOS.writeFile(state, session, args[2], args[3], false)
	if done == nil then return fail("write", args[2], reason) end
	return true, {}
end

--
-- The one entry point.
--

function CeroSecOS.exec(state, session, line)
	if type(state) ~= "table" or state.fs == nil then return false, { "no filesystem" } end
	if type(session) ~= "table" or type(session.user) ~= "string" then
		return false, { "not logged in" }
	end
	if type(line) ~= "string" then return false, { "syntax error" } end

	local args, redirect, reason = CeroSecOS.parseLine(line)
	if args == nil then return false, CeroSecOS.fit({ reason }) end

	-- A bare redirection still creates (or truncates) the file.
	if #args == 0 then
		if redirect == nil then return true, {} end
		local done, wreason = CeroSecOS.writeFile(state, session, redirect.path, "", redirect.append)
		if done == nil then return false, CeroSecOS.fit({ redirect.path .. ": " .. wreason }) end
		return true, {}
	end

	local name = args[1]
	local fn = commands[name]
	if fn == nil then return false, CeroSecOS.fit({ name .. ": command not found" }) end

	local ok, lines, control = fn(state, session, args)
	if lines == nil then lines = {} end

	-- Output goes to the file only when the command succeeded; errors stay on
	-- the screen, as they would on stderr.
	if ok and redirect ~= nil then
		local text = table.concat(lines, "\n")
		local done, wreason = CeroSecOS.writeFile(state, session, redirect.path, text, redirect.append)
		if done == nil then
			return false, CeroSecOS.fit({ name .. ": " .. redirect.path .. ": " .. wreason })
		end
		return true, {}, control
	end

	return ok, CeroSecOS.fit(lines), control
end
