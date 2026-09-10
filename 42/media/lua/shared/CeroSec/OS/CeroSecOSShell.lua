--
-- CeroSec OS core: the shell.
--
-- exec(state, session, line) -> ok, lines, control, data. One command line at a
-- time: double quoted strings with backslash escapes, ">" and ">>" redirection,
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
	cat = "print a file",
	cd = "change the working directory",
	chmod = "change a file's mode",
	chown = "change a file's owner",
	clear = "clear the screen",
	cp = "copy a file",
	echo = "print its arguments",
	edit = "edit a file",
	exit = "log out",
	hash = "hash a string the way a password is",
	help = "list the commands in /bin",
	hostname = "print or set the machine's name",
	ls = "list a directory",
	mkdir = "make a directory",
	mv = "move or rename a file",
	passwd = "change a password",
	pwd = "print the working directory",
	reboot = "restart the machine",
	restart = "restart the machine",
	rm = "remove a file or a directory",
	shutdown = "switch the machine off",
	sudo = "run a command as root",
	touch = "create an empty file",
	whoami = "print the current user",
	write = "write a line into a file",
}

-- The two that do not need a file behind them. A machine can be broken from
-- inside -- root may `rm -r /bin` and that is root's right -- and a player
-- standing in front of a broken one must still be able to ask what happened and
-- to walk away from it. Everything else is an executable or it is nothing.
CeroSecOS.BUILTINS = { exit = true, help = true }

-- Column the descriptions line up in, in help. The longest name is "hostname".
local L_CMD = 9

commands.help = function(state, session, args)
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

commands.pwd = function(state, session, args)
	if #args > 1 then return usage("pwd", "pwd") end
	return true, { session.cwd }
end

commands.whoami = function(state, session, args)
	if #args > 1 then return usage("whoami", "whoami") end
	return true, { session.user }
end

-- The name is /etc/hostname and this reads it. Root may write it; nobody else
-- may, because the name is on every prompt of every session on the machine.
commands.hostname = function(state, session, args)
	if #args > 2 then return usage("hostname", "hostname [name]") end
	if args[2] == nil then return true, { CeroSecOS.hostname(state) } end
	if CeroSecOS.userOf(session) ~= "root" then return fail("hostname", nil, "permission denied") end
	local done, reason = CeroSecOS.setHostname(state, args[2])
	if done == nil then return fail("hostname", args[2], reason) end
	return true, {}
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
	return function(state, session, args)
		if #args > 1 then return usage(name, name) end
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
commands.passwd = function(state, session, args)
	if #args > 2 then return usage("passwd", "passwd [user]") end
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

continuations.passwd = function(state, session, cont, line)
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
		local done, reason = CeroSecOS.setPassword(state, name, line, session.stamp)
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
commands.hash = function(state, session, args)
	if #args < 2 or #args > 3 then return usage("hash", "hash <text> [salt]") end
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
commands.edit = function(state, session, args)
	if #args ~= 2 then return usage("edit", "edit <file>") end
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
local function rootSessionFrom(session)
	return { user = "root", cwd = session.cwd or "/", stamp = session.stamp }
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
local function sudoRun(state, session, args, from)
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

	local ok, lines, control, data = fn(state, sub, own)
	carryAs("root", control, data)
	return ok, lines, control, data
end

commands.sudo = function(state, session, args)
	-- `sudo sudo ls` is one sudo. Real sudo runs the second one as root and
	-- ends up in the same place; there is no reason to make a player type his
	-- password to be asked for it again.
	local from = 2
	while args[from] == "sudo" do from = from + 1 end
	if args[from] == nil then return usage("sudo", "sudo <command> [args]") end

	local me = CeroSecOS.userOf(session)
	-- Root is already root. No file is consulted: an /etc/sudoers with nobody
	-- in it must not be able to take sudo away from the one account that could
	-- put it back.
	if me == "root" then return sudoRun(state, session, args, from) end

	local entry = CeroSecOS.sudoer(state, me)
	if entry == nil then return false, { me .. " is not in the sudoers file." } end
	if entry.nopasswd then return sudoRun(state, session, args, from) end

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

continuations.sudo = function(state, session, cont, line)
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
	if args[1] == nil then return usage("sudo", "sudo <command> [args]") end
	return sudoRun(state, session, args, 1)
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

function CeroSecOS.exec(state, session, line)
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
		local done, wreason = CeroSecOS.writeFile(state, session, redirect.path, "", redirect.append)
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

	local ok, lines, control, data = fn(state, session, args)
	if lines == nil then lines = {} end

	-- Output goes to the file only when the command succeeded; errors stay on
	-- the screen, as they would on stderr. A command that has not finished --
	-- one that asks, or one that opens the editor -- has no output to redirect
	-- yet, so the redirection never applies to it.
	local redirectable = control ~= "prompt" and control ~= "edit"
	if ok and redirect ~= nil and redirectable then
		local text = table.concat(lines, "\n")
		local done, wreason = CeroSecOS.writeFile(state, session, redirect.path, text, redirect.append)
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
function CeroSecOS.continue(state, session, cont, line)
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
		run = { user = cont.as, cwd = session.cwd or "/", stamp = session.stamp }
	end

	local ok, lines, control, data = fn(state, run, cont, line)
	if lines == nil then lines = {} end
	if run ~= session then carryAs(cont.as, control, data) end
	return ok, CeroSecOS.fit(lines), control, data
end
