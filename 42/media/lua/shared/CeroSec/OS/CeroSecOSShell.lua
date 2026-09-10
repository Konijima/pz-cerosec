--
-- CeroSec OS core: the shell.
--
-- exec(state, session, line, env) -> ok, lines, control, data. One command line
-- at a time: double quoted strings with backslash escapes, ">" and ">>" redirection,
-- no pipes and
-- no variables yet. control is nil, "clear", "exit", "prompt", "edit",
-- "shutdown" or "reboot": an order to the terminal travels beside the output,
-- never inside it, so no file's contents can ever be mistaken for one. data is
-- the payload of the two orders that carry one ("prompt" and "edit") and nil
-- for the rest.
-- Errors read like a 1993 Unix, one line each:
--   cd: /root: permission denied
--   cat: notes.txt: no such file
-- Commands never touch the tree themselves; they call the four mutators in
-- CeroSecOSFS.lua, which own the permissions and the limits.
--
-- env is the world outside the machine, and today it holds one thing: env.now,
-- the clock (see the clock section of CeroSecOS.lua). It is OPTIONAL -- a call
-- without one is a machine with no clock, which `date` says out loud and which
-- leaves every timestamp where it was -- and it is handed down to every command
-- as a fourth argument, sudo's and a continuation's included.
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

-- The one usage line there is for a command: the string in COMMAND_INFO. `man
-- ls` prints it and a wrong `ls` prints it, so the two can never drift into
-- saying different things.
local function usage(cmd)
	return false, { cmd .. ": usage: " .. (CeroSecOS.commandUsage(cmd) or cmd) }
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

-- ls -l columns: 10 perm + 2 + 8 owner + 2 + 5 size + 2 + 12 date + 2 + 17 name
-- = exactly 60. The name is LAST, the way every ls prints it, so it is the one
-- that gets cut when it is too long and the only one that ever has to be; and
-- it is not padded, because a trailing run of spaces is not something a screen
-- should be asked to hold.
local L_OWNER, L_SIZE, L_NAME = 8, 5, 17

local function longLine(node, name)
	local size
	if node.type == "dir" then
		size = CeroSecOS.countEntries(node)
	else
		size = #(node.data or "")
	end
	return permString(node)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.owner or "?", L_OWNER), L_OWNER)
		.. "  " .. CeroSecOS.padLeft(tostring(size), L_SIZE)
		.. "  " .. CeroSecOS.formatStamp(CeroSecOS.mtimeOf(node))
		.. "  " .. CeroSecOS.truncate(name, L_NAME)
end

-- Names packed into columns the way ls does on a 60-column screen: laid out
-- column-major -- read DOWN a column, not across a row, which is what Unix ls
-- has always done -- two spaces between columns, every column as wide as the
-- longest name there is. One name too wide for the screen ends up alone on its
-- line, cut with a "~" like everything else.
function CeroSecOS.columnize(names, width)
	local out = {}
	if #names == 0 then return out end

	local longest = 0
	for i = 1, #names do
		if #names[i] > longest then longest = #names[i] end
	end
	if longest > width then longest = width end

	local colw = longest + 2
	local cols = math.floor((width + 2) / colw)
	if cols < 1 then cols = 1 end
	if cols > #names then cols = #names end
	local rows = math.floor((#names + cols - 1) / cols)

	for r = 1, rows do
		local line = ""
		for c = 1, cols do
			local i = (c - 1) * rows + r
			if i <= #names then
				local name = CeroSecOS.truncate(names[i], width)
				-- The last name on a row carries no padding.
				if i + rows <= #names then
					line = line .. CeroSecOS.padRight(name, colw)
				else
					line = line .. name
				end
			end
		end
		out[#out + 1] = line
	end
	return out
end

--
-- Commands.
--

--
-- What is in /bin
--
-- One line each, and it is the file's contents: `cat /bin/ls` prints it, `ls -l
-- /bin` sizes it, and `help` is nothing but a listing of the directory. So a
-- machine whose /bin has been cut down says so by having a shorter help, and a
-- machine with no /bin at all cannot describe commands it no longer has.
--
-- This table is also the list fillBin builds from: a command that is not in
-- here gets no executable, and one with no Lua behind it is a file the shell
-- will refuse to run. os_test pins the two sets against each other.
--
CeroSecOS.COMMAND_INFO = {
	adduser  = { desc = "add an account", usage = "adduser [-a] <name>" },
	cat      = { desc = "print a file", usage = "cat <file>..." },
	cd       = { desc = "change the working directory", usage = "cd [dir]" },
	chmod    = { desc = "change a file's mode", usage = "chmod <mode> <path>" },
	chown    = { desc = "change a file's owner", usage = "chown <user> <path>" },
	clear    = { desc = "clear the screen", usage = "clear" },
	cp       = { desc = "copy a file or a tree", usage = "cp [-r] <src> <dst>" },
	date     = { desc = "print the date and time", usage = "date [+FORMAT]" },
	deluser  = { desc = "remove an account", usage = "deluser [-r] <name>" },
	df       = { desc = "report disk space", usage = "df" },
	echo     = { desc = "print its arguments", usage = "echo [text...]" },
	edit     = { desc = "edit a file", usage = "edit <file>" },
	exit     = { desc = "log out", usage = "exit" },
	grep     = { desc = "find a string in files", usage = "grep [-i] [-n] <text> <file>..." },
	hash     = { desc = "hash a string the way a password is", usage = "hash <text> [salt]" },
	head     = { desc = "print the first lines of a file", usage = "head [-n N] <file>" },
	help     = { desc = "list the commands in /bin", usage = "help" },
	hostname = { desc = "print or set the machine's name", usage = "hostname [name]" },
	id       = { desc = "print an account and its groups", usage = "id [name]" },
	ls       = { desc = "list a directory", usage = "ls [-lF] [path]" },
	man      = { desc = "describe a command", usage = "man <command>" },
	mkdir    = { desc = "make a directory", usage = "mkdir <dir>" },
	mv       = { desc = "move or rename a file", usage = "mv <src> <dst>" },
	passwd   = { desc = "change a password", usage = "passwd [user]" },
	pwd      = { desc = "print the working directory", usage = "pwd" },
	reboot   = { desc = "restart the machine", usage = "reboot" },
	restart  = { desc = "restart the machine", usage = "restart" },
	rm       = { desc = "remove a file or a directory", usage = "rm [-r] <path>..." },
	shutdown = { desc = "switch the machine off", usage = "shutdown" },
	su       = { desc = "become another user", usage = "su [name]" },
	sudo     = { desc = "run a command as root", usage = "sudo <command> [args]" },
	tail     = { desc = "print the last lines of a file", usage = "tail [-n N] <file>" },
	touch    = { desc = "create a file, or stamp it", usage = "touch <file>" },
	wc       = { desc = "count lines, words and bytes", usage = "wc <file>..." },
	whoami   = { desc = "print the current user", usage = "whoami" },
	write    = { desc = "write a line into a file", usage = "write <file> <text>" },
}

-- The two halves of an entry, read through a function and never off the table:
-- an entry is a table now, and a caller reaching into it is a caller that
-- breaks the day it grows a third field.
--
-- The description is what goes INTO /bin/<name> and what help and man print
-- back out of it; the usage line lives here only, because it is the shell's
-- grammar and not a fact about the machine's disk.
function CeroSecOS.commandDesc(name)
	local info = (CeroSecOS.COMMAND_INFO or {})[name]
	if type(info) ~= "table" then return nil end
	return info.desc
end

function CeroSecOS.commandUsage(name)
	local info = (CeroSecOS.COMMAND_INFO or {})[name]
	if type(info) ~= "table" then return nil end
	return info.usage
end

-- The two that do not need a file behind them. A machine can be broken from
-- inside -- root may `rm -r /bin` and that is root's right -- and a player
-- standing in front of a broken one must still be able to ask what happened and
-- to walk away from it. Everything else is an executable or it is nothing.
CeroSecOS.BUILTINS = { exit = true, help = true }

-- Column the descriptions line up in, in help. The longest name is "hostname".
local L_CMD = 9

commands.help = function(state, session, args, env)
	local bin, reason = CeroSecOS.getNode(state, session, CeroSecOS.BIN_PATH)
	if bin == nil and reason ~= "no such file" then
		return fail("help", CeroSecOS.BIN_PATH, reason)
	end

	local names = {}
	if bin ~= nil and bin.type == "dir" then names = CeroSecOS.childNames(bin) end
	if #names == 0 then
		-- Said by the one command that still answers on a machine with nothing
		-- left to run, so it says the way back as well as the trouble.
		return false, {
			"help: no commands in " .. CeroSecOS.BIN_PATH .. ": the system is damaged.",
			"help: switch the computer off and on to repair it.",
		}
	end

	local out = { "CeroSec OS commands:" }
	for i = 1, #names do
		local node = bin.children[names[i]]
		if node.type == "file" then
			out[#out + 1] = " " .. CeroSecOS.padRight(names[i], L_CMD) .. (node.data or "")
		end
	end
	out[#out + 1] = " redirect output with > file or >> file"
	return true, out
end

commands.pwd = function(state, session, args, env)
	if #args > 1 then return usage("pwd") end
	return true, { session.cwd }
end

commands.whoami = function(state, session, args, env)
	if #args > 1 then return usage("whoami") end
	return true, { session.user }
end

-- The name is /etc/hostname and this reads it. Root may write it; nobody else
-- may, because the name is on every prompt of every session on the machine.
commands.hostname = function(state, session, args, env)
	if #args > 2 then return usage("hostname") end
	if args[2] == nil then return true, { CeroSecOS.hostname(state) } end
	if CeroSecOS.userOf(session) ~= "root" then return fail("hostname", nil, "permission denied") end
	local done, reason = CeroSecOS.setHostname(state, args[2], CeroSecOS.clockOf(env))
	if done == nil then return fail("hostname", args[2], reason) end
	return true, {}
end

commands.clear = function(state, session, args, env)
	return true, {}, "clear"
end

-- exit. The end of the session -- unless this console got here through su, in
-- which case it is the end of THAT one: the stack pops, the glass goes back to
-- who it was and where he stood, and nobody is logged out. Only ever the
-- console's own session; a borrowed one (`sudo exit`) has a copy of the stack
-- that dies with the command, and logs out the way it always has.
commands.exit = function(state, session, args, env)
	local stack = session.stack
	if not session.borrowed and type(stack) == "table" and #stack > 0 then
		local back = stack[#stack]
		stack[#stack] = nil
		session.user = back.user
		session.cwd = back.cwd or "/"
		return true, {}
	end
	return true, {}, "exit"
end

commands.echo = function(state, session, args, env)
	if #args < 2 then return true, { "" } end
	local words = {}
	for i = 2, #args do words[#words + 1] = args[i] end
	return true, { table.concat(words, " ") }
end

commands.cd = function(state, session, args, env)
	if #args > 2 then return usage("cd") end
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

commands.ls = function(state, session, args, env)
	-- Flags are letters, so "-lF", "-Fl" and "-l -F" are the same line. A bare
	-- "-" is not a flag and never was: it is a name, and a name is what the
	-- error about it should be about.
	local long, classify, path = false, false, nil
	for i = 2, #args do
		local a = args[i]
		if string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				local flag = string.sub(a, c, c)
				if flag == "l" then
					long = true
				elseif flag == "F" then
					classify = true
				else
					return fail("ls", a, "unknown option")
				end
			end
		elseif path == nil then
			path = a
		else
			return usage("ls")
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
	if long then
		local out = {}
		for i = 1, #names do
			local child = node.children[names[i]]
			local label = names[i]
			if classify and child.type == "dir" then label = label .. "/" end
			out[#out + 1] = longLine(child, label)
		end
		return true, out
	end

	local labels = {}
	for i = 1, #names do
		labels[i] = names[i]
		if classify and node.children[names[i]].type == "dir" then
			labels[i] = names[i] .. "/"
		end
	end
	return true, CeroSecOS.columnize(labels, CeroSecOS.COLS)
end

commands.mkdir = function(state, session, args, env)
	if #args ~= 2 then return usage("mkdir") end
	local dir = CeroSecOS.newDir(CeroSecOS.userOf(session), 755)
	local created, reason = CeroSecOS.createNode(state, session, args[2], dir, CeroSecOS.clockOf(env))
	if created == nil then return fail("mkdir", args[2], reason) end
	return true, {}
end

commands.touch = function(state, session, args, env)
	if #args ~= 2 then return usage("touch") end
	local now = CeroSecOS.clockOf(env)
	local node, reason = CeroSecOS.getNode(state, session, args[2])
	if node ~= nil then
		if node.type ~= "file" then return fail("touch", args[2], "is a directory") end
		-- Moving a timestamp is a write: a file you may not write is a file you
		-- may not stamp, which is what a real touch says too. On a machine with
		-- no clock there is nothing to move and the file is left alone.
		if not CeroSecOS.can(state, session, node, "w") then
			return fail("touch", args[2], "permission denied")
		end
		if now ~= nil then node.mtime = now end
		return true, {}
	end
	if reason ~= "no such file" then return fail("touch", args[2], reason) end
	local file = CeroSecOS.newFile(CeroSecOS.userOf(session), 644, "")
	local created, creason = CeroSecOS.createNode(state, session, args[2], file, now)
	if created == nil then return fail("touch", args[2], creason) end
	return true, {}
end

commands.cat = function(state, session, args, env)
	if #args < 2 then return usage("cat") end
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

commands.rm = function(state, session, args, env)
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
	if #paths == 0 then return usage("rm") end

	local out, ok = {}, true
	for i = 1, #paths do
		local done, reason =
			CeroSecOS.removeNode(state, session, paths[i], recursive, CeroSecOS.clockOf(env))
		if done == nil then
			ok = false
			out[#out + 1] = "rm: " .. paths[i] .. ": " .. reason
		end
	end
	return ok, out
end

commands.mv = function(state, session, args, env)
	if #args ~= 3 then return usage("mv") end
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

	local done, mreason = CeroSecOS.moveNode(state, session, src, target, CeroSecOS.clockOf(env))
	if done == nil then return fail("mv", target, mreason) end
	return true, {}
end

-- Every node of a subtree readable? A copy walks the whole of it, so a
-- directory you cannot enter is not a directory you can copy -- and the refusal
-- comes BEFORE anything is written, so a `cp -r` that cannot finish leaves
-- nothing half copied behind it.
local function canCopyTree(state, session, node)
	if not CeroSecOS.can(state, session, node, "r") then return false end
	if node.type ~= "dir" then return true end
	if not CeroSecOS.can(state, session, node, "x") then return false end
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do
		if not canCopyTree(state, session, node.children[names[i]]) then return false end
	end
	return true
end

commands.cp = function(state, session, args, env)
	local recursive, paths = false, {}
	for i = 2, #args do
		local a = args[i]
		-- Only before the first path: "cp -r a -b" has no second flag in it,
		-- and a name that begins with "-" is refused by isValidName anyway.
		if #paths == 0 and string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				if string.sub(a, c, c) ~= "r" then return fail("cp", a, "unknown option") end
			end
			recursive = true
		else
			paths[#paths + 1] = a
		end
	end
	if #paths ~= 2 then return usage("cp") end
	local src, dst = paths[1], paths[2]

	local node, reason, srcAbs = CeroSecOS.getNode(state, session, src)
	if node == nil then return fail("cp", src, reason) end
	if node.type ~= "file" and not recursive then return fail("cp", src, "is a directory") end
	if not canCopyTree(state, session, node) then return fail("cp", src, "permission denied") end

	local target = dst
	local dstNode = CeroSecOS.getNode(state, session, dst)
	if dstNode ~= nil and dstNode.type == "dir" then
		local name = baseName(session, src)
		if name == nil then return fail("cp", src, "permission denied") end
		target = dst .. "/" .. name
	end

	-- A directory never goes inside itself: the copy would be a child of what
	-- is being copied. Judged on the RESOLVED paths, so "." and ".." cannot
	-- walk around it -- the same test mv makes for the same reason.
	if node.type == "dir" then
		local targetAbs = CeroSecOS.resolve(session, target)
		if CeroSecOS.isInside(targetAbs, srcAbs) then
			return fail("cp", target, "invalid destination")
		end
	end

	-- The copy is the caller's, and it is stamped with now: cp without -p makes
	-- a new file, and a new file is new.
	local copy = CeroSecOS.copyNode(node, CeroSecOS.userOf(session))
	local created, creason =
		CeroSecOS.createNode(state, session, target, copy, CeroSecOS.clockOf(env))
	if created == nil then return fail("cp", target, creason) end
	return true, {}
end

commands.chmod = function(state, session, args, env)
	if #args ~= 3 then return usage("chmod") end
	local mode = parseMode(args[2])
	if mode == nil then return fail("chmod", args[2], "invalid mode") end
	local node, reason = CeroSecOS.getNode(state, session, args[3])
	if node == nil then return fail("chmod", args[3], reason) end
	if not isOwnerOrRoot(session, node) then return fail("chmod", args[3], "permission denied") end
	node.mode = mode
	-- One timestamp for the two a real filesystem has: a chmod moves the ctime
	-- there and moves this one here.
	local now = CeroSecOS.clockOf(env)
	if now ~= nil then node.mtime = now end
	return true, {}
end

commands.chown = function(state, session, args, env)
	if #args ~= 3 then return usage("chown") end
	local user = CeroSecOS.getUser(state, args[2])
	if user == nil then return fail("chown", args[2], "no such user") end
	local node, reason = CeroSecOS.getNode(state, session, args[3])
	if node == nil then return fail("chown", args[3], reason) end
	if not isOwnerOrRoot(session, node) then return fail("chown", args[3], "permission denied") end
	node.owner = user.name
	local now = CeroSecOS.clockOf(env)
	if now ~= nil then node.mtime = now end
	return true, {}
end

-- Internal: how the editor saves. The editor UI is not part of the core.
commands.write = function(state, session, args, env)
	if #args ~= 3 then return usage("write") end
	local done, reason =
		CeroSecOS.writeFile(state, session, args[2], args[3], false, CeroSecOS.clockOf(env))
	if done == nil then return fail("write", args[2], reason) end
	return true, {}
end

--
-- The clock, and the disk
--

-- date. The machine's clock is the world's: what is on the screen is the hour
-- and the day the survivor typing is living in. A machine nobody handed a clock
-- says so rather than inventing one -- a wrong date is worse than no date on a
-- screen somebody is meant to trust.
--
-- With a +FORMAT it prints the pieces instead, strftime's way -- and %s prints
-- the clock itself, the number seconds are counted in and the number a file's
-- mtime carries, which is what a script on this machine has to do arithmetic
-- on. The codes are CeroSecOS.formatTime's; anything it does not know is copied
-- out as it was typed.
--
-- No clock is no clock, format or not: a machine that answered `date +%s` with
-- a zero would be a machine handing out a wrong number rather than none.
commands.date = function(state, session, args, env)
	if #args > 2 then return usage("date") end
	local now = CeroSecOS.clockOf(env)
	if now == nil then return fail("date", nil, "no clock") end
	local form = args[2]
	if form == nil then return true, { CeroSecOS.formatDate(now) } end
	if string.sub(form, 1, 1) ~= "+" then return usage("date") end
	return true, { CeroSecOS.formatTime(now, string.sub(form, 2)) }
end

-- df. Two lines, because this machine has two ceilings and either of them is
-- what a write dies on: the bytes on the disk and the nodes on it. Both are
-- counted off the tree at the moment it is asked -- there is no counter kept
-- beside the filesystem that could ever disagree with it.
local D_NAME, D_NUM, D_PCT = 10, 5, 4

local function dfLine(name, total, used)
	local avail = total - used
	if avail < 0 then avail = 0 end
	-- Rounded UP, the way df has always rounded it: a disk with one byte on it
	-- does not report 0%.
	local pct = 0
	if total > 0 then pct = math.ceil(used * 100 / total) end
	return CeroSecOS.padRight(CeroSecOS.truncate(name, D_NAME), D_NAME)
		.. "  " .. CeroSecOS.padLeft(tostring(total), D_NUM)
		.. "  " .. CeroSecOS.padLeft(tostring(used), D_NUM)
		.. "  " .. CeroSecOS.padLeft(tostring(avail), D_NUM)
		.. "  " .. CeroSecOS.padLeft(tostring(pct) .. "%", D_PCT)
end

commands.df = function(state, session, args, env)
	if #args > 1 then return usage("df") end
	local nodes, bytes = CeroSecOS.usage(state)
	return true, {
		CeroSecOS.padRight("Filesystem", D_NAME)
			.. "  " .. CeroSecOS.padLeft("Size", D_NUM)
			.. "  " .. CeroSecOS.padLeft("Used", D_NUM)
			.. "  " .. CeroSecOS.padLeft("Avail", D_NUM)
			.. "  " .. CeroSecOS.padLeft("Use%", D_PCT),
		dfLine(CeroSecOS.DISK_NAME, CeroSecOS.DISK_BYTES, bytes),
		dfLine("nodes", CeroSecOS.MAX_NODES, nodes),
	}
end

--
-- Text tools
--

-- The lines of one file, or nil plus the one-line refusal already worded. Three
-- commands read files this way, so the three of them refuse in the same words.
-- The node comes back too, because wc counts bytes and not lines.
local function fileLines(state, session, cmd, path)
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node == nil then return nil, cmd .. ": " .. path .. ": " .. reason end
	if node.type ~= "file" then return nil, cmd .. ": " .. path .. ": is a directory" end
	if not CeroSecOS.can(state, session, node, "r") then
		return nil, cmd .. ": " .. path .. ": permission denied"
	end
	return CeroSecOS.splitLines(node.data or ""), nil, node
end

-- grep. A plain substring and not a pattern: string.find's fourth argument is
-- what makes "a.b" mean the three characters and not "a, anything, b". There is
-- no regex on this machine and none is promised.
commands.grep = function(state, session, args, env)
	local ignore, numbered, rest = false, false, {}
	for i = 2, #args do
		local a = args[i]
		if #rest == 0 and string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				local flag = string.sub(a, c, c)
				if flag == "i" then
					ignore = true
				elseif flag == "n" then
					numbered = true
				else
					return fail("grep", a, "unknown option")
				end
			end
		else
			rest[#rest + 1] = a
		end
	end
	if #rest < 2 then return usage("grep") end

	local needle = rest[1]
	if ignore then needle = string.lower(needle) end
	-- The file's name goes in front of a hit only when there is more than one
	-- file to tell apart, which is what grep has always done.
	local many = #rest > 2
	local out, found, okAll = {}, false, true

	for i = 2, #rest do
		local path = rest[i]
		local lines, refusal = fileLines(state, session, "grep", path)
		if lines == nil then
			okAll = false
			out[#out + 1] = refusal
		else
			for n = 1, #lines do
				local hay = lines[n]
				if ignore then hay = string.lower(hay) end
				if string.find(hay, needle, 1, true) ~= nil then
					found = true
					local prefix = ""
					if many then prefix = path .. ":" end
					if numbered then prefix = prefix .. tostring(n) .. ":" end
					out[#out + 1] = prefix .. lines[n]
				end
			end
		end
	end

	-- grep answers "did you find anything". Nothing found is a refusal even
	-- when every file was read without trouble.
	if not found then return false, out end
	return okAll, out
end

-- -n N, and nothing else. Answers the count and the paths, or nil for a line
-- that is not one -- which the caller turns into the usage string.
local function lineCount(args)
	local n, rest = 10, {}
	local i = 2
	while i <= #args do
		local a = args[i]
		if a == "-n" then
			local value = tonumber(args[i + 1] or "")
			if value == nil or value < 0 or value ~= math.floor(value) then return nil end
			n = value
			i = i + 2
		elseif #rest == 0 and string.sub(a, 1, 1) == "-" and a ~= "-" then
			return nil
		else
			rest[#rest + 1] = a
			i = i + 1
		end
	end
	return n, rest
end

commands.head = function(state, session, args, env)
	local n, rest = lineCount(args)
	if n == nil or #rest ~= 1 then return usage("head") end
	local lines, refusal = fileLines(state, session, "head", rest[1])
	if lines == nil then return false, { refusal } end
	local out = {}
	for i = 1, #lines do
		if i > n then break end
		out[#out + 1] = lines[i]
	end
	return true, out
end

commands.tail = function(state, session, args, env)
	local n, rest = lineCount(args)
	if n == nil or #rest ~= 1 then return usage("tail") end
	local lines, refusal = fileLines(state, session, "tail", rest[1])
	if lines == nil then return false, { refusal } end
	local first = #lines - n + 1
	if first < 1 then first = 1 end
	local out = {}
	for i = first, #lines do out[#out + 1] = lines[i] end
	return true, out
end

-- wc: lines, words, bytes, name. 6 + 1 + 6 + 1 + 6 + 1 = 21 columns of numbers,
-- so the name has 39 left of the screen.
local W_NUM, W_NAME = 6, 39

local function wcLine(lines, words, bytes, name)
	return CeroSecOS.padLeft(tostring(lines), W_NUM)
		.. " " .. CeroSecOS.padLeft(tostring(words), W_NUM)
		.. " " .. CeroSecOS.padLeft(tostring(bytes), W_NUM)
		.. " " .. CeroSecOS.truncate(name, W_NAME)
end

-- A word is a run of anything that is not a blank. Newlines count as blanks:
-- the data is one string with newlines in it, not a list of lines.
local function wordsIn(text)
	local n = 0
	for _ in string.gmatch(text, "[^ \t\n]+") do n = n + 1 end
	return n
end

commands.wc = function(state, session, args, env)
	if #args < 2 then return usage("wc") end
	local out, okAll = {}, true
	local totalLines, totalWords, totalBytes, counted = 0, 0, 0, 0
	for i = 2, #args do
		local path = args[i]
		local lines, refusal, node = fileLines(state, session, "wc", path)
		if lines == nil then
			okAll = false
			out[#out + 1] = refusal
		else
			local data = node.data or ""
			counted = counted + 1
			totalLines = totalLines + #lines
			totalWords = totalWords + wordsIn(data)
			totalBytes = totalBytes + #data
			out[#out + 1] = wcLine(#lines, wordsIn(data), #data, path)
		end
	end
	if counted > 1 then
		out[#out + 1] = wcLine(totalLines, totalWords, totalBytes, "total")
	end
	return okAll, out
end

-- man. The description is the FILE's, exactly like help's: a machine whose /bin
-- has been cut down has no manual for what is no longer on it, and one whose
-- /bin/ls somebody rewrote says what that file says. The usage line is the
-- shell's own, so it is the one a wrong command line prints back.
commands.man = function(state, session, args, env)
	if #args ~= 2 then return usage("man") end
	local name = args[2]
	local node, reason = CeroSecOS.getNode(state, session, CeroSecOS.BIN_PATH .. "/" .. name)
	if node == nil then
		if reason ~= "no such file" and reason ~= "not a directory" then
			return fail("man", name, reason)
		end
		return fail("man", name, "no manual entry")
	end
	if node.type ~= "file" then return fail("man", name, "no manual entry") end

	local out = {}
	local desc = node.data or ""
	if desc == "" then
		out[#out + 1] = name
	else
		out[#out + 1] = name .. " - " .. desc
	end
	local form = CeroSecOS.commandUsage(name)
	if form ~= nil then out[#out + 1] = "usage: " .. form end
	return true, out
end

--
-- Power
--
-- The two commands that end the screen they are typed on. Neither of them does
-- anything itself: the core has no machine to switch off, so what comes back is
-- an order, and the server -- which owns the sprite, the sound, the power and
-- the windows -- is what carries it out.
--
-- Root only. Everything a machine holds is on the disk and survives, so this is
-- not about losing work; it is that a second survivor standing at the same
-- glass loses his session, and that is not an ordinary account's to take.
--
local function powerCommand(name, control)
	return function(state, session, args, env)
		if #args > 1 then return usage(name) end
		if CeroSecOS.userOf(session) ~= "root" then return fail(name, nil, "permission denied") end
		return true, {}, control
	end
end

commands.shutdown = powerCommand("shutdown", "shutdown")
commands.reboot = powerCommand("reboot", "reboot")
-- The same order under the other name it has been called by since the eighties.
-- Its own executable and its own refusal line, so `restart` never answers as
-- something the player did not type.
commands.restart = powerCommand("restart", "reboot")

--
-- Interactive commands.
--
-- A command that has to ask something answers with control "prompt" and a
-- payload: the line to put under the cursor, whether the answer is to be
-- masked, and an opaque token. The console stores the token beside everything
-- else it keeps, hands the next line typed to CeroSecOS.continue, and gets back
-- the very same shape -- so an interactive command is a chain of ordinary
-- returns and not a coroutine, which Kahlua does not have.
--
-- The token is a plain table of strings, because it lives in the machine's
-- console and the console is serialized into the save file.
--

CeroSecOS.continuations = CeroSecOS.continuations or {}
local continuations = CeroSecOS.continuations

local function ask(text, mask, cont)
	return true, {}, "prompt", { text = text, mask = mask and true or false, cont = cont }
end

-- passwd. Own password: old, new, retype. root is asked for nobody's old
-- password, its own included -- that is what being root is -- and is the only
-- account that may change somebody else's.
--
-- Nothing of a password ever reaches the token: between "New password:" and
-- "Retype new password:" what is carried is the hash of the answer, with its
-- own salt, and the retype is judged by hashing it the same way. The token
-- lives in the machine's console and the console is written to the save file,
-- so anything in clear there would be the one place on the machine that still
-- handed a password over.
commands.passwd = function(state, session, args, env)
	if #args > 2 then return usage("passwd") end
	local me = CeroSecOS.userOf(session)
	local name = args[2]
	if name == nil or name == "" then name = me end
	if CeroSecOS.getUser(state, name) == nil then return false, { "passwd: no such user" } end
	if name ~= me and me ~= "root" then return false, { "passwd: permission denied" } end
	if me == "root" then
		return ask("New password: ", true, { cmd = "passwd", step = "new", user = name })
	end
	return ask("Old password: ", true, { cmd = "passwd", step = "old", user = name })
end

continuations.passwd = function(state, session, cont, line, env)
	local name = cont.user
	local user = CeroSecOS.getUser(state, name)
	if user == nil then return false, { "passwd: no such user" } end

	-- Asked again, at every step. The token is the server's and no client can
	-- forge one today, but a chain that carries the account it is about must
	-- carry the authority to touch it too: a check that lives only in the
	-- command is a check one refactor away from being no check at all.
	local me = CeroSecOS.userOf(session)
	if name ~= me and me ~= "root" then return false, { "passwd: permission denied" } end

	if cont.step == "old" then
		if not CeroSecOS.checkPassword(user, line) then
			return false, { "passwd: authentication failure" }
		end
		return ask("New password: ", true, { cmd = "passwd", step = "new", user = name })
	end

	if cont.step == "new" then
		-- The token is stored in the machine's console and the console is
		-- written to the save file, so what goes in it is the HASH of the new
		-- password and not the password. Otherwise the one window between this
		-- question and the next would be the one place on the machine where a
		-- password sits in clear -- which is the thing the hashing was for.
		local salt = CeroSecOS.newSalt(state, name .. tostring(session.stamp))
		return ask("Retype new password: ", true,
			{ cmd = "passwd", step = "retype", user = name,
			  salt = salt, want = CeroSecOS.hashPassword(line, salt) })
	end

	if cont.step == "retype" then
		if CeroSecOS.hashPassword(line, cont.salt) ~= (cont.want or "") then
			return false, { "passwd: passwords do not match" }
		end
		local done, reason =
			CeroSecOS.setPassword(state, name, line, session.stamp, CeroSecOS.clockOf(env))
		if done == nil then return false, { "passwd: " .. reason } end
		return true, { "passwd: password updated" }
	end

	-- A token with a step nobody wrote: refuse the way a wrong answer is
	-- refused, and change nothing.
	return false, { "passwd: authentication failure" }
end

-- hash. The same function the passwords go through, on a string you choose, so
-- what a stored password looks like is something the machine can show you. A
-- salt of your own makes it reproducible; without one you get a fresh salt and
-- a line that is different every time, which is the point of a salt.
commands.hash = function(state, session, args, env)
	if #args < 2 or #args > 3 then return usage("hash") end
	local salt = args[3]
	if salt == nil or salt == "" then
		salt = CeroSecOS.newSalt(state, args[2] .. tostring(session.stamp))
	end
	if not CeroSecOS.isValidSalt(salt) then return fail("hash", salt, "invalid salt") end
	if CeroSecOS.hasControlBytes(args[2]) then return fail("hash", args[2], "invalid characters") end
	-- fit() breaks anything wider than the screen across lines, so a long salt
	-- wraps instead of being cut.
	return true, { CeroSecOS.hashPassword(args[2], salt) }
end

-- edit. The editor itself is the terminal's; all the core does is say whether
-- the file can be opened, hand over its text, and say whether it may be written
-- back. Saving goes through CeroSecOS.writeFile like every other write.
commands.edit = function(state, session, args, env)
	if #args ~= 2 then return usage("edit") end
	local path = args[2]
	local node, reason, abs = CeroSecOS.getNode(state, session, path)
	if node ~= nil then
		if node.type ~= "file" then return fail("edit", path, "is a directory") end
		if not CeroSecOS.can(state, session, node, "r") then
			return fail("edit", path, "permission denied")
		end
		return true, {}, "edit", {
			path = abs,
			text = node.data or "",
			readonly = not CeroSecOS.can(state, session, node, "w"),
			-- Who the buffer was opened by, so that the save four minutes later
			-- is the write this command was allowed. Under sudo that is root
			-- and not the account logged in at the glass.
			user = CeroSecOS.userOf(session),
		}
	end
	if reason ~= "no such file" then return fail("edit", path, reason) end

	-- A file that is not there yet opens empty, but only where it could be
	-- created: nano lets you type into a buffer it can never write, this does
	-- not, so the only refusal an editor can end on is a full disk.
	local _, parts = CeroSecOS.resolve(session, path)
	if #parts == 0 then return fail("edit", path, "is a directory") end
	if not CeroSecOS.isValidName(parts[#parts]) then return fail("edit", path, "invalid name") end
	local parentPath = CeroSecOS.parentOf(parts)
	local parent, preason = CeroSecOS.getNode(state, session, parentPath)
	if parent == nil then return fail("edit", path, preason) end
	if parent.type ~= "dir" then return fail("edit", path, "not a directory") end
	if not CeroSecOS.can(state, session, parent, "w") then
		return fail("edit", path, "permission denied")
	end
	return true, {}, "edit",
		{ path = abs, text = "", readonly = false, user = CeroSecOS.userOf(session) }
end

--
-- sudo
--
-- Run one command as root without being root. /etc/sudoers says who may, and
-- whether he is asked for his own password first (see CeroSecOSUsers.lua).
--
-- What "as root" means here is one thing and nothing more: the command runs on
-- a session of its own, root's, with the caller's working directory. The
-- console's session is not touched, so `sudo cd /root` moves nothing and the
-- account logged in at the glass is the same account after the command as
-- before it. There is no timestamp and no remembered authority: every sudo
-- that needs a password asks for it.
--

-- The temporary session. Fresh each time, so nothing survives one command into
-- the next.
-- It is BORROWED: it carries who is really at the glass and a copy of the users
-- that glass would come back to, so a command can tell "who am I running as"
-- from "who typed this" -- and it owns neither. Anything it pushes or pops is
-- the copy's, which is what keeps `sudo su` from moving the console and
-- `sudo exit` a logout rather than somebody else's su to unwind.
local function rootSessionFrom(session)
	return {
		user = "root", cwd = session.cwd or "/", stamp = session.stamp,
		login = CeroSecOS.loginOf(session),
		stack = CeroSecOS.copyStack(session.stack),
		borrowed = true,
	}
end

-- A chain that is running as somebody else keeps running as him: the mark goes
-- onto every token the chain hands on, so `sudo passwd root` is still root's
-- when it asks for the new password twice. Nothing else ever writes it.
local function carryAs(as, control, data)
	if as == nil then return end
	if control ~= "prompt" then return end
	if type(data) ~= "table" or type(data.cont) ~= "table" then return end
	data.cont.as = as
end

-- Run args[from], args[from + 1], ... as root. The command is resolved the way
-- the shell resolves one -- /bin/<name>, x for the session that runs it -- so
-- root walks through a mode the caller could not, which is the point, and a
-- command that is not in /bin is not found for root either.
local function sudoRun(state, session, args, from, env)
	local name = args[from]
	local fn = commands[name]
	if fn == nil then return false, { name .. ": command not found" } end

	local sub = rootSessionFrom(session)
	if not CeroSecOS.BUILTINS[name] then
		local refusal = CeroSecOS.whyNotRun(state, sub, name)
		if refusal ~= nil then return false, { name .. ": " .. refusal } end
	end

	-- Every command reads args[1] as its own name, so the tail is handed over
	-- with the name back in front of it.
	local own = {}
	for i = from, #args do own[#own + 1] = args[i] end

	local ok, lines, control, data = fn(state, sub, own, env)
	carryAs("root", control, data)
	return ok, lines, control, data
end

commands.sudo = function(state, session, args, env)
	-- `sudo sudo ls` is one sudo. Real sudo runs the second one as root and
	-- ends up in the same place; there is no reason to make a player type his
	-- password to be asked for it again.
	local from = 2
	while args[from] == "sudo" do from = from + 1 end
	if args[from] == nil then return usage("sudo") end

	local me = CeroSecOS.userOf(session)
	-- Root is already root. No file is consulted: an /etc/sudoers with nobody
	-- in it must not be able to take sudo away from the one account that could
	-- put it back.
	if me == "root" then return sudoRun(state, session, args, from, env) end

	local entry = CeroSecOS.sudoer(state, me)
	if entry == nil then return false, { me .. " is not in the sudoers file." } end
	if entry.nopasswd then return sudoRun(state, session, args, from, env) end

	-- Nothing of the password goes into the token, not even a hash of it: the
	-- answer is judged against /etc/passwd when it arrives, which is the one
	-- place a password is ever judged. What the token carries is the command
	-- that was typed and the account it was typed by -- and the token lives in
	-- the machine's console, which is written to the save file.
	local rest = {}
	for i = from, #args do rest[#rest + 1] = args[i] end
	return ask("[sudo] password for " .. me .. ": ", true,
		{ cmd = "sudo", user = me, args = rest })
end

continuations.sudo = function(state, session, cont, line, env)
	local me = CeroSecOS.userOf(session)

	-- Asked again, at the answer: a token names the account it was issued for,
	-- and a chain that survived a logout is not an authorisation for whoever
	-- logged in next.
	if type(cont.user) ~= "string" or cont.user ~= me then
		return false, { "sudo: authentication failure" }
	end
	if not CeroSecOS.checkPassword(CeroSecOS.getUser(state, me), line) then
		-- One attempt. Real sudo gives three; this machine has a physical lock
		-- on it -- you have to be standing at the keyboard -- and a second
		-- survivor is watching the same glass.
		return false, { "sudo: authentication failure" }
	end
	-- And the list is read again: a name taken out of /etc/sudoers between the
	-- question and the answer is a name that may no longer run this.
	if CeroSecOS.sudoer(state, me) == nil then
		return false, { me .. " is not in the sudoers file." }
	end

	local args = cont.args
	if type(args) ~= "table" then return false, { "sudo: authentication failure" } end
	for i = 1, #args do
		if type(args[i]) ~= "string" then return false, { "sudo: authentication failure" } end
	end
	if args[1] == nil then return usage("sudo") end
	return sudoRun(state, session, args, 1, env)
end

--
-- Accounts
--
-- Making and unmaking one is root's, and root's alone: /etc/passwd is root's
-- file, and an account is a way into the machine. So an admin does it the way
-- he does everything else that is root's -- `sudo adduser bob` -- and there is
-- no second rule for who may.
--
-- Both commands are ordinary writes to ordinary files: the account is a line in
-- /etc/passwd, the home is a directory made with createNode, and the ceilings,
-- the permission bits and the printable rule are the filesystem's exactly as
-- they are for a player. A full disk refuses an adduser the way it refuses a
-- touch.
--
-- What the "admin" flag on the line MEANS is: nothing, today. No command
-- consults it; the two things that grant power are being root and being named
-- in /etc/sudoers. Its one visible effect is the "#" on the prompt. It is
-- carried, printed by `id` and set by `adduser -a` so that a later rung has
-- something to give meaning to -- and the README says so rather than letting a
-- player believe he has just made somebody powerful.
--

commands.adduser = function(state, session, args, env)
	if CeroSecOS.userOf(session) ~= "root" then return fail("adduser", nil, "permission denied") end

	local admin, name = false, nil
	for i = 2, #args do
		local a = args[i]
		if name == nil and string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				if string.sub(a, c, c) ~= "a" then return fail("adduser", a, "unknown option") end
			end
			admin = true
		elseif name == nil then
			name = a
		else
			return usage("adduser")
		end
	end
	if name == nil or name == "" then return usage("adduser") end
	if not CeroSecOS.isValidUserName(name) then return fail("adduser", name, "invalid name") end
	if CeroSecOS.getUser(state, name) ~= nil then return fail("adduser", name, "already exists") end

	local now = CeroSecOS.clockOf(env)
	local home = CeroSecOS.HOME_PATH .. "/" .. name
	local node, reason = CeroSecOS.getNode(state, session, home)
	if node == nil and reason ~= "no such file" then return fail("adduser", home, reason) end
	if node ~= nil and node.type ~= "dir" then return fail("adduser", home, "not a directory") end

	-- The account first and the home second, so that a refusal on the way --
	-- a full disk, a /home that is not there any more -- takes the account back
	-- out and leaves the machine exactly as it was. Half an account is worse
	-- than none: it is a name in the file with nowhere to stand.
	local done, wreason = CeroSecOS.addUser(state, name, home, admin, session.stamp, now)
	if done == nil then return fail("adduser", name, wreason) end

	if node == nil then
		local made, creason = CeroSecOS.createNode(state, session, home,
			CeroSecOS.newDir(name, CeroSecOS.HOME_MODE), now)
		if made == nil then
			CeroSecOS.removeUser(state, name, now)
			return fail("adduser", home, creason)
		end
	else
		-- A directory that is already there is ADOPTED, not remade: it changes
		-- hands and keeps its mode and everything in it. Somebody's files are
		-- not an obstacle to giving him an account.
		node.owner = name
		if now ~= nil then node.mtime = now end
	end

	-- The password is empty, and an empty password is a way in. Said out loud
	-- on the line after, because a machine that quietly ships an open account
	-- is a machine nobody remembers to close.
	return true, {
		"adduser: " .. name .. ": created",
		"adduser: set a password with passwd " .. name,
	}
end

commands.deluser = function(state, session, args, env)
	if CeroSecOS.userOf(session) ~= "root" then return fail("deluser", nil, "permission denied") end

	local removeHome, name = false, nil
	for i = 2, #args do
		local a = args[i]
		if name == nil and string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				if string.sub(a, c, c) ~= "r" then return fail("deluser", a, "unknown option") end
			end
			removeHome = true
		elseif name == nil then
			name = a
		else
			return usage("deluser")
		end
	end
	if name == nil or name == "" then return usage("deluser") end

	-- Root is not one of the accounts: it is the way back into the machine, and
	-- a computer with no root on it is a computer whose BIOS is the only way in.
	-- Asked before the file is even looked at, so the answer is the same on a
	-- machine somebody has been editing by hand.
	if name == "root" then return fail("deluser", name, "cannot remove") end

	local user = CeroSecOS.getUser(state, name)
	if user == nil then return fail("deluser", name, "no such user") end
	-- Not the account at the glass, and not one the glass would come back to
	-- through `exit`: pulling either out from under a live session leaves
	-- somebody logged in as nobody.
	if CeroSecOS.isLoggedIn(session, name) then return fail("deluser", name, "user is logged in") end

	local now = CeroSecOS.clockOf(env)

	-- The home first, while the account still exists to own it. Without -r it
	-- stays exactly where it is, owned by a name the machine no longer knows --
	-- which is what `ls -l` will show, and it is the truth rather than a tidy
	-- lie about whose files those were.
	if removeHome then
		local home = user.home
		local node, reason = CeroSecOS.getNode(state, session, home)
		if node == nil then
			if reason ~= "no such file" then return fail("deluser", home, reason) end
		else
			local gone, greason = CeroSecOS.removeNode(state, session, home, true, now)
			if gone == nil then return fail("deluser", home, greason) end
		end
	end

	local done, reason = CeroSecOS.removeUser(state, name, now)
	if done == nil then return fail("deluser", name, reason) end
	-- And the right to become root with it: a name left in /etc/sudoers is a
	-- line waiting for whoever is given that name next.
	local dropped, sreason = CeroSecOS.removeSudoer(state, name, now)
	if dropped == nil then return fail("deluser", CeroSecOS.SUDOERS_PATH, sreason) end

	return true, { "deluser: " .. name .. ": removed" }
end

-- id. What the machine knows about an account in one line: the name, the flag
-- its /etc/passwd line carries, and whether /etc/sudoers names it. Anybody may
-- ask, about anybody: who may become root is not a secret on a machine where
-- the answer is a file the kernel reads out loud at every sudo.
commands.id = function(state, session, args, env)
	if #args > 2 then return usage("id") end
	local name = args[2]
	if name == nil or name == "" then name = CeroSecOS.userOf(session) end
	local user = CeroSecOS.getUser(state, name)
	if user == nil then return fail("id", name, "no such user") end
	local flag = "user"
	if user.admin then flag = "admin" end
	local groups = "-"
	if CeroSecOS.sudoer(state, user.name) ~= nil then groups = "sudo" end
	return true, { "uid=" .. user.name .. " flag=" .. flag .. " groups=" .. groups }
end

--
-- su
--
-- Become somebody else at this glass without logging out. The console keeps a
-- stack of who it was and where he stood, `exit` pops it, and the stack is the
-- MACHINE's: it is written into the console and saved with it, so a survivor
-- who walks away two users deep comes back two users deep.
--
-- The password asked for is the TARGET's, the way su has always asked for it,
-- and it is judged in the one place a password is judged. Nothing of it goes
-- into the token -- what the token carries is the name being switched to -- and
-- root is asked for nobody's password, its own included, which is the rule
-- passwd already runs on.
--

local function suSwitch(session, user)
	local stack = session.stack
	if type(stack) ~= "table" then stack = {} end
	-- Asked here as well as before the question: the stack could have grown
	-- while the password was being typed, and a ceiling that is only checked on
	-- the way in is not a ceiling.
	if #stack >= CeroSecOS.SU_MAX then return false, { "su: too many levels" } end
	stack[#stack + 1] = { user = session.user, cwd = session.cwd or "/" }
	session.stack = stack
	session.user = user.name
	session.cwd = user.home or "/"
	return true, {}
end

commands.su = function(state, session, args, env)
	if #args > 2 then return usage("su") end
	local name = args[2]
	if name == nil or name == "" then name = "root" end
	local user = CeroSecOS.getUser(state, name)
	if user == nil then return fail("su", name, "no such user") end
	local stack = session.stack
	if type(stack) == "table" and #stack >= CeroSecOS.SU_MAX then
		return false, { "su: too many levels" }
	end
	if CeroSecOS.userOf(session) == "root" then return suSwitch(session, user) end
	return ask("Password: ", true, { cmd = "su", user = name })
end

continuations.su = function(state, session, cont, line, env)
	-- The account is looked up again at the answer: one taken out of the file
	-- between the question and the answer is one nobody becomes.
	local user = CeroSecOS.getUser(state, cont.user)
	if user == nil then return false, { "su: authentication failure" } end
	if CeroSecOS.userOf(session) ~= "root" and not CeroSecOS.checkPassword(user, line) then
		-- One attempt, exactly as sudo gives one, and for the same reason: this
		-- machine has a physical lock on it.
		return false, { "su: authentication failure" }
	end
	return suSwitch(session, user)
end

--
-- Resolving a command
--
-- A name typed at the shell is a file in /bin and nothing else. There is no
-- PATH, no ./thing and no command hiding in a home directory: /bin/<name> or
-- the machine has never heard of it.
--
-- nil when the command may run, or the bare reason it may not -- the caller
-- puts the name in front of it, so the two lines a player ever sees here are
--   ls: command not found
--   ls: permission denied
--
function CeroSecOS.whyNotRun(state, session, name)
	local node, reason = CeroSecOS.getNode(state, session, CeroSecOS.BIN_PATH .. "/" .. name)
	if node == nil then
		-- Nothing there, /bin itself gone, /bin turned into a file: from where
		-- the shell stands they are the same answer. A refusal on the way in --
		-- /bin chmodded shut -- is not, and says what it is.
		if reason == "no such file" or reason == "not a directory" then return "command not found" end
		return reason
	end
	-- A directory called /bin/ls is not a command, and saying "is a directory"
	-- about something the player never named as a path would only puzzle him.
	if node.type ~= "file" then return "command not found" end
	if not CeroSecOS.can(state, session, node, "x") then return "permission denied" end
	return nil
end

--
-- The one entry point.
--

function CeroSecOS.exec(state, session, line, env)
	if type(state) ~= "table" or state.fs == nil then return false, { "no filesystem" } end
	if type(session) ~= "table" or type(session.user) ~= "string" then
		return false, { "not logged in" }
	end
	if type(line) ~= "string" then return false, { "syntax error" } end

	local args, redirect, reason = CeroSecOS.parseLine(line)
	if args == nil then return false, CeroSecOS.fit({ reason }) end

	-- The tilde is the shell's, not the filesystem's: it is expanded here, once,
	-- before any command is handed its arguments, so `cd ~`, `ls ~`, `cat
	-- ~/notes.txt` and `echo hi > ~/notes.txt` all work and no command has to
	-- know about it. args[1] is a command name and is left alone -- there is no
	-- ~/bin on this machine and a command is not a path.
	local home = nil
	local user = CeroSecOS.getUser(state, session.user)
	if user ~= nil and type(user.home) == "string" then home = user.home end
	if home ~= nil then
		for i = 2, #args do args[i] = CeroSecOS.expandHome(args[i], home) end
		if redirect ~= nil then redirect.path = CeroSecOS.expandHome(redirect.path, home) end
	end

	-- A bare redirection still creates (or truncates) the file.
	if #args == 0 then
		if redirect == nil then return true, {} end
		local done, wreason = CeroSecOS.writeFile(state, session, redirect.path, "",
			redirect.append, CeroSecOS.clockOf(env))
		if done == nil then return false, CeroSecOS.fit({ redirect.path .. ": " .. wreason }) end
		return true, {}
	end

	local name = args[1]
	local fn = commands[name]
	if fn == nil then return false, CeroSecOS.fit({ name .. ": command not found" }) end
	if not CeroSecOS.BUILTINS[name] then
		local refusal = CeroSecOS.whyNotRun(state, session, name)
		if refusal ~= nil then return false, CeroSecOS.fit({ name .. ": " .. refusal }) end
	end

	local ok, lines, control, data = fn(state, session, args, env)
	if lines == nil then lines = {} end

	-- Output goes to the file only when the command succeeded; errors stay on
	-- the screen, as they would on stderr. A command that has not finished --
	-- one that asks, or one that opens the editor -- has no output to redirect
	-- yet, so the redirection never applies to it.
	local redirectable = control ~= "prompt" and control ~= "edit"
	if ok and redirect ~= nil and redirectable then
		local text = table.concat(lines, "\n")
		local done, wreason = CeroSecOS.writeFile(state, session, redirect.path, text,
			redirect.append, CeroSecOS.clockOf(env))
		if done == nil then
			return false, CeroSecOS.fit({ name .. ": " .. redirect.path .. ": " .. wreason })
		end
		return true, {}, control
	end

	return ok, CeroSecOS.fit(lines), control, data
end

-- The other half of the entry point: the answer to a prompt exec asked for.
-- Same shape in, same shape out, so a console feeds a chain of prompts the way
-- it feeds a chain of commands.
--
-- A token that is not one -- a forged console, a chain abandoned and answered
-- afterwards -- is refused here rather than trusted, and nothing of the state
-- is touched on the way out.
function CeroSecOS.continue(state, session, cont, line, env)
	if type(state) ~= "table" or state.fs == nil then return false, { "no filesystem" } end
	if type(session) ~= "table" or type(session.user) ~= "string" then
		return false, { "not logged in" }
	end
	if type(line) ~= "string" then line = "" end
	if type(cont) ~= "table" or type(cont.cmd) ~= "string" then
		return false, CeroSecOS.fit({ "cerosec: nothing to answer" })
	end
	local fn = continuations[cont.cmd]
	if fn == nil then return false, CeroSecOS.fit({ "cerosec: nothing to answer" }) end

	-- A chain started under sudo goes on running as root. The authority belongs
	-- to the chain and not to the line that answers it, so it travels in the
	-- token -- written there by sudo and by nothing else -- and the console's
	-- own session is left exactly as it was, cwd included.
	local run = session
	if type(cont.as) == "string" and cont.as ~= session.user then
		run = {
			user = cont.as, cwd = session.cwd or "/", stamp = session.stamp,
			login = CeroSecOS.loginOf(session),
			stack = CeroSecOS.copyStack(session.stack),
			borrowed = true,
		}
	end

	local ok, lines, control, data = fn(state, run, cont, line, env)
	if lines == nil then lines = {} end
	if run ~= session then carryAs(cont.as, control, data) end
	return ok, CeroSecOS.fit(lines), control, data
end
