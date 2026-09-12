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
-- The history file
--
-- Every line an account types is appended to ~/.sh_history -- the name ksh
-- gave it and POSIX kept -- and the file is the ONLY history there is: the
-- window walks it with Up and Down, `history` prints it, `!5` and `!!` run out
-- of it, and a survivor who walks away and comes back finds what he typed
-- yesterday. It is the account's and nobody else's: mode 600, in his own home.
--
-- Two ceilings, and they are both this machine's rather than Unix's. A real
-- one caps the history by lines alone; this one caps it by lines AND by bytes,
-- because a 32K disk with a thousand lines of history on it would be a disk
-- with no room for anything a player wrote. The file is exempt from the disk
-- quota for the same reason -- a shell's own memory must not be what fills the
-- drive -- and the exemption belongs to the PATH and not to the file: exactly
-- <home>/.sh_history, owned by that account (see CeroSecOS.exemptPaths). Rename
-- one and it counts against the 32K from that moment on; rename it back and it
-- is exempt again.
--
CeroSecOS.HISTORY_NAME = ".sh_history"
CeroSecOS.HISTORY_MODE = 600
-- Entries kept. Dropped from the front, the way every shell drops them.
CeroSecOS.HISTORY_MAX = 1000
-- Bytes the file may hold, quota or no quota.
CeroSecOS.HISTORY_BYTES = 16384
-- What `history` prints with no argument: a screenful of screenfuls.
CeroSecOS.HISTORY_SHOW = 60
-- What a window is handed when it opens, to walk with Up and Down.
CeroSecOS.HISTORY_TAIL = 100

-- The exempt bytes on a whole machine. A handful of files are exempt from the
-- disk quota, each by the path it hangs at (see the exemption section of
-- CeroSecOSFS.lua): an account's own ~/.sh_history, an account's own mailbox
-- under /var/mail, and the one /var/log/cron. This is what the exemption may
-- cost in total -- four accounts' worth of each, and the log -- and it is what
-- the usage count hands out and no more: bytes past it are counted against the
-- disk like anybody's, so a machine with a dozen accounts on it has a full disk
-- and not a hidden one.
--
-- Written here rather than beside the other limits because this is the one file
-- that can see all three ceilings it is the sum of, and a sum written anywhere
-- else would be a second copy of three numbers.
CeroSecOS.MAX_EXEMPT_ACCOUNTS = 4
CeroSecOS.MAX_EXEMPT_BYTES = CeroSecOS.MAX_EXEMPT_ACCOUNTS
	* (CeroSecOS.HISTORY_BYTES + CeroSecOS.MAIL_BYTES) + CeroSecOS.CRON_LOG_BYTES
	+ CeroSecOS.WTMP_BYTES

-- And what the HISTORIES alone may cost: four of them, which is the number the
-- append path pays at every line (see CeroSecOS.historyAppend). A kind of its
-- own rather than a share of the total, so that a machine full of mail is not a
-- machine that has stopped remembering what was typed at it.
CeroSecOS.HISTORY_EXEMPT_BYTES = CeroSecOS.MAX_EXEMPT_ACCOUNTS * CeroSecOS.HISTORY_BYTES

-- The path, or nil for an account with no home on its /etc/passwd line.
function CeroSecOS.historyPath(state, name)
	local user = CeroSecOS.getUser(state, name)
	if user == nil or type(user.home) ~= "string" or user.home == "" then return nil end
	return user.home .. "/" .. CeroSecOS.HISTORY_NAME
end

-- The entries, oldest first. Read through the session's own permissions like
-- any other file, so an account cannot read another's -- and an account with
-- no history yet has an empty one rather than an error.
function CeroSecOS.historyLines(state, session)
	local path = CeroSecOS.historyPath(state, CeroSecOS.userOf(session))
	if path == nil then return {} end
	local node = CeroSecOS.getNode(state, session, path)
	if node == nil or node.type ~= "file" then return {} end
	if not CeroSecOS.can(state, session, node, "r") then return {} end
	return CeroSecOS.splitLines(node.data or "")
end

-- The last n of them, for the window to walk.
function CeroSecOS.historyTail(state, session, n)
	local lines = CeroSecOS.historyLines(state, session)
	local out = {}
	local from = #lines - (n or CeroSecOS.HISTORY_TAIL) + 1
	if from < 1 then from = 1 end
	for i = from, #lines do out[#out + 1] = lines[i] end
	return out
end

-- Put the entries back, trimmed to both ceilings. The write does NOT go
-- through writeFile: that one counts the bytes against the disk and refuses
-- anything over the 4096 a file may hold, and this file is exempt from both by
-- construction. Everything else a write owes -- the printable rule, the owner,
-- the mode, the permission to write at all -- is still paid, above.
local function historyPut(node, lines)
	while #lines > CeroSecOS.HISTORY_MAX do table.remove(lines, 1) end
	local text = table.concat(lines, "\n")
	while #text > CeroSecOS.HISTORY_BYTES and #lines > 1 do
		table.remove(lines, 1)
		text = table.concat(lines, "\n")
	end
	-- One line of its own, longer than the whole file may be: cut rather than
	-- refused, because the alternative is a history that silently stops.
	if #text > CeroSecOS.HISTORY_BYTES then text = string.sub(text, 1, CeroSecOS.HISTORY_BYTES) end
	node.data = text
end

-- One line onto the end of the account's history. Quiet on every refusal: a
-- history that cannot be written is not a reason to refuse the command the
-- player typed.
function CeroSecOS.historyAppend(state, session, line, now)
	if type(line) ~= "string" or line == "" then return false end
	if CeroSecOS.hasControlBytes(line) then return false end
	local name = CeroSecOS.userOf(session)
	local path = CeroSecOS.historyPath(state, name)
	if path == nil then return false end

	local node, reason = CeroSecOS.getNode(state, session, path)
	if node == nil then
		if reason ~= "no such file" then return false end
		local made = CeroSecOS.createNode(state, session, path,
			CeroSecOS.newFile(name, CeroSecOS.HISTORY_MODE, ""), now)
		if made == nil then return false end
		node = made
	end
	if node.type ~= "file" then return false end
	if not CeroSecOS.can(state, session, node, "w") then return false end

	-- The exemption has a machine-wide ceiling and this is where it is paid.
	-- What the other histories already hold plus what this one is about to hold
	-- has to fit, or the line is dropped: a machine with accounts enough would
	-- otherwise write history no `df` on it ever mentions.
	-- Histories alone: what a mailbox or the cron log holds is exempt too and is
	-- bounded by its own ceiling, and a full mailbox must not be what stops a
	-- shell remembering what was typed.
	local others = CeroSecOS.exemptOthers(state, node, "history")
	-- What this one may GROW to, not what it holds now: the ceiling has to be
	-- one nothing can creep past a line at a time. Four histories' worth.
	if others + CeroSecOS.HISTORY_BYTES > CeroSecOS.HISTORY_EXEMPT_BYTES then return false end

	local lines = CeroSecOS.splitLines(node.data or "")
	lines[#lines + 1] = line
	historyPut(node, lines)
	if now ~= nil then node.mtime = now end
	return true
end

-- history -c. The file is emptied, not deleted: an account that has cleared
-- its history still has one, and the next line typed goes into it.
function CeroSecOS.historyClear(state, session, now)
	local path = CeroSecOS.historyPath(state, CeroSecOS.userOf(session))
	if path == nil then return false end
	local node = CeroSecOS.getNode(state, session, path)
	if node == nil or node.type ~= "file" then return true end
	if not CeroSecOS.can(state, session, node, "w") then return false end
	node.data = ""
	if now ~= nil then node.mtime = now end
	return true
end

-- History expansion: `!!` is the last line and `!5` is the fifth, run as
-- though it had been typed again -- csh's, and every shell's since.
--
-- One deviation, and it is deliberate: only a line that is NOTHING BUT the
-- event is expanded. There is no globbing on this machine and no quoting rule
-- for "!" either, so expanding one in the middle of a line would make every
-- exclamation mark a player types a trap.
--
-- line, or nil plus the refusal. A line with no event in it comes straight
-- back, which is what every line is.
function CeroSecOS.historyExpand(state, session, line)
	if type(line) ~= "string" then return line end
	local word = string.match(line, "^[ \t]*(![^ \t]*)[ \t]*$")
	if word == nil then return line end

	local lines = CeroSecOS.historyLines(state, session)
	local want = nil
	if word == "!!" then
		want = #lines
	else
		want = tonumber(string.match(word, "^!(%d+)$") or "")
	end
	if want == nil or want < 1 or want > #lines then
		return nil, "sh: " .. word .. ": event not found"
	end
	return lines[want]
end

--
-- Shared bits of the commands.
--

local function fail(cmd, arg, reason)
	if arg == nil then return false, { cmd .. ": " .. reason } end
	return false, { cmd .. ": " .. arg .. ": " .. reason }
end

--
-- What the shell knows, beside the arguments
--
-- A command is handed one more thing than its words: a small table of what the
-- SHELL knows about the line -- where a bare name is looked up (PATH) and
-- whether what the command writes is going to a screen at all. Neither is a fact
-- about the filesystem, so neither is looked up by whoever needs it; they travel
-- together, built once by the walker (CeroSecOSVM.runSimple) and passed down.
--
-- A caller that hands over none -- a bench calling straight in -- is a shell with
-- the default PATH standing in front of a terminal, which is where a person
-- typing is.
--
local function shPath(sh)
	if type(sh) ~= "table" or type(sh.path) ~= "string" then return CeroSecOS.DEFAULT_PATH end
	return sh.path
end

-- false only when the shell SAID so: a pipe, a capture or a redirect is what
-- takes the screen away, and nothing else may be read as having taken it.
local function shTty(sh)
	if type(sh) ~= "table" then return true end
	return sh.tty ~= false
end

-- The one usage line there is for a command: the string in COMMAND_INFO. `man
-- ls` prints it and a wrong `ls` prints it, so the two can never drift into
-- saying different things.
local function usage(cmd)
	return false, { cmd .. ": usage: " .. (CeroSecOS.commandUsage(cmd) or cmd) }
end

--
-- Standard input
--
-- A pipeline hands the command on the right of the "|" a reader (see the pipe
-- section of CeroSecOSVM.lua). Nothing else on this machine does: there is no
-- keyboard behind a command, so a command with no file named and no pipe on its
-- left has no standard input at all and prints its usage line, which is the only
-- honest answer a machine with no terminal input can give.
--
-- The six commands that read it -- cat, grep, head, tail, wc, sort and uniq --
-- all ask for it the same way, HERE, so the rule is written once: a file named
-- on the line wins, the way it does on every Unix, and only a line with no file
-- on it reads the pipe.
--
-- What comes back is the reader, with `want` already set on it: the pipeline
-- reads that to know this command is going to keep reading, and calls it again
-- on whatever the stage to its left has written by then. `carry` is the
-- command's own scratch table, kept between one call and the next, which is what
-- lets `wc` count a pipe it will never see the end of in one pass.
local function stdinOf(stdin, paths)
	if #paths > 0 then return nil end
	if type(stdin) ~= "table" then return nil end
	stdin.want = true
	return stdin
end

-- What a command that cannot answer before it has seen ALL of its input may
-- hold while it waits for the end of it. `sort` cannot print a line until it
-- knows there is no smaller one coming, and `tail` cannot know which lines were
-- the last ones -- so both of them keep what they have read, and what they keep
-- has to have a ceiling or a pipe with no end to it is an unbounded string with
-- a command in front of it.
--
-- A pipe's own ceiling is the one they get: a hundred lines and four kilobytes.
-- Past it the command gives up and says so, which is the same answer this
-- machine gives a word, a variable and a file that outgrow theirs. Every other
-- reader -- cat, grep, head, wc, uniq -- keeps nothing at all and has no ceiling
-- to meet: they answer a line at a time, which is why `yes | wc -l` counts for
-- ever on this machine exactly as it does on a real one.
local function holdLine(carry, line)
	if carry.lines == nil then
		carry.lines = {}
		carry.bytes = 0
	end
	carry.lines[#carry.lines + 1] = line
	carry.bytes = carry.bytes + #line + 1
	return #carry.lines <= CeroSecOS.PIPE_LINES and carry.bytes <= CeroSecOS.PIPE_BYTES
end

-- The paths on a command line, with args[1] -- the command's own name -- left
-- where it is.
local function operands(args)
	local paths = {}
	for i = 2, #args do paths[#paths + 1] = args[i] end
	return paths
end

-- The flag letters a command takes, together or apart -- `-lw` and `-l -w` are
-- the same line, which is POSIX's rule and every Unix's -- and the operands
-- behind them. nil plus the word that is not an option when the line carries
-- one, which the caller words its own refusal about.
--
-- Only the words BEFORE the first operand are options. `grep -i x -n` looks for
-- the string "-n" in a file called "x", which is what a grep with no "--" in it
-- has always done, and is why the needle is the first operand here and not a
-- case of its own.
local function flagsOf(args, letters)
	local flags, rest = {}, {}
	for i = 2, #args do
		local a = args[i]
		if #rest == 0 and string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				local flag = string.sub(a, c, c)
				if string.find(letters, flag, 1, true) == nil then return nil, a end
				flags[flag] = true
			end
		else
			rest[#rest + 1] = a
		end
	end
	return flags, rest
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

--
-- Symbolic modes
--
-- The other half of chmod's grammar, and the half a person actually types:
-- `u+x` rather than working out that 640 has to become 740. One clause is
-- [ugoa]* then one of + - =, then the letters rwx; clauses are separated by
-- commas and applied left to right to the mode the file ALREADY wears, which
-- is what makes `chmod u+x` different from `chmod 744`.
--
-- No target letter means all three, the way chmod has read a bare `+x` since
-- the seventies. The letters are a SET and not a sum -- `u+rr` is r and not
-- eight -- so each digit is taken apart into its three bits and put back
-- together, and nothing here adds an octal digit to itself.
--
-- `=` with no letter after it is the one clause that may be empty: `a=` takes
-- everything away, which is the only way to say 000 in this grammar. `u+` and
-- `u-` are not clauses and are an invalid mode.
--

-- One octal digit -> its three bits.
local function digitBits(d)
	local r = d >= 4
	if r then d = d - 4 end
	local w = d >= 2
	if w then d = d - 2 end
	return r, w, d >= 1
end

local function bitsDigit(r, w, x)
	local d = 0
	if r then d = d + 4 end
	if w then d = d + 2 end
	if x then d = d + 1 end
	return d
end

-- One clause, applied to the three digits in place. false when it is not one.
local function applyClause(bits, clause)
	local i, n = 1, #clause
	local who = { false, false, false }
	local named = false
	while i <= n do
		local c = string.sub(clause, i, i)
		if c == "u" then who[1] = true
		elseif c == "g" then who[2] = true
		elseif c == "o" then who[3] = true
		elseif c == "a" then who[1], who[2], who[3] = true, true, true
		else break end
		named = true
		i = i + 1
	end
	if not named then who[1], who[2], who[3] = true, true, true end

	local op = string.sub(clause, i, i)
	if op ~= "+" and op ~= "-" and op ~= "=" then return false end
	i = i + 1

	local r, w, x = false, false, false
	local letters = false
	while i <= n do
		local c = string.sub(clause, i, i)
		if c == "r" then r = true
		elseif c == "w" then w = true
		elseif c == "x" then x = true
		else return false end
		letters = true
		i = i + 1
	end
	if not letters and op ~= "=" then return false end

	for k = 1, 3 do
		if who[k] then
			local hr, hw, hx = digitBits(bits[k])
			if op == "=" then
				bits[k] = bitsDigit(r, w, x)
			elseif op == "+" then
				bits[k] = bitsDigit(hr or r, hw or w, hx or x)
			else
				bits[k] = bitsDigit(hr and not r, hw and not w, hx and not x)
			end
		end
	end
	return true
end

-- mode, or nil when the spec is not one. The mode that comes back is in the
-- same three-octal-digit form every mode on this machine is written in.
function CeroSecOS.applyModeSpec(mode, spec)
	if type(mode) ~= "number" or type(spec) ~= "string" or spec == "" then return nil end
	if mode < 0 or mode > 777 then return nil end
	local bits = {
		math.floor(mode / 100),
		math.floor(math.fmod(math.floor(mode / 10), 10)),
		math.floor(math.fmod(mode, 10)),
	}
	for k = 1, 3 do
		if bits[k] > 7 then return nil end
	end
	local from = 1
	while true do
		local p = string.find(spec, ",", from, true)
		local clause = nil
		if p == nil then clause = string.sub(spec, from) else clause = string.sub(spec, from, p - 1) end
		if not applyClause(bits, clause) then return nil end
		if p == nil then break end
		from = p + 1
	end
	return bits[1] * 100 + bits[2] * 10 + bits[3]
end

-- The children of a directory that are worth listing. Everything, except a
-- device the machine knows the number of and cannot reach: it is mounted so
-- that `cat /dev/lock0` can say "no such device" about a number a player wrote
-- down, and it is not on the shelf, because it is not there.
-- A name that begins with a dot is HIDDEN, the way it has been since the
-- third edition of Unix: `ls` walks past it and `ls -a` does not. Nothing else
-- on this machine treats it as special -- `cat .profile` reads it and `edit
-- .sh_history` opens it, because a name is a name and there is no globbing
-- here for a dot to hide from.
--
-- Not local: completion lists a directory too (CeroSecOSComplete.lua), and the
-- rule about what is on the shelf must be written down once.
function CeroSecOS.listedNames(node, all)
	local names = CeroSecOS.childNames(node)
	local out = {}
	for i = 1, #names do
		local child = node.children[names[i]]
		local hidden = string.sub(names[i], 1, 1) == "."
		if not (type(child) == "table" and child.dead) and (all or not hidden) then
			out[#out + 1] = names[i]
		end
	end
	return out
end

-- ls -l columns: 10 perm + 2 + 6 owner + 1 + 6 group + 2 + 5 size + 2 + 12 date
-- + 2 + 12 name = exactly 60.
--
--   -rw-r-----  admin  users     412  Jul  8 14:32  notes.txt
--
-- The owner and the group sit side by side with a single space between their
-- fields, the way every ls prints the pair, and six characters is what a
-- sixty-column screen leaves for either once the middle digit has a column of
-- its own to explain it. The name is LAST, the way every ls prints it, so it is
-- the one that gets cut when it is too long and the only one that ever has to
-- be; and it is not padded, because a trailing run of spaces is not something a
-- screen should be asked to hold.
local L_OWNER, L_GROUP, L_SIZE, L_NAME = 6, 6, 5, 12

local function longLine(node, name)
	local size
	if node.type == "dir" then
		size = CeroSecOS.countEntries(node)
	else
		size = #(node.data or "")
	end
	return CeroSecOS.permString(node)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.owner or "?", L_OWNER), L_OWNER)
		.. " " .. CeroSecOS.padRight(
			CeroSecOS.truncate(CeroSecOS.groupOf(node), L_GROUP), L_GROUP)
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
-- One exception, and it is the only one: an entry marked `shell = true` is a
-- word the shell IS, and a word the shell is has no file. It still has its
-- description and its usage line here, because `help` lists it and `man` prints
-- it -- what it does not have is an executable to find, to delete or to chmod.
--
CeroSecOS.COMMAND_INFO = {
	["["]    = { desc = "evaluate an expression", usage = "[ <expression> ]" },
	adduser  = { desc = "add an account", usage = "adduser [-a] <name>" },
	cat      = { desc = "print a file", usage = "cat [file]..." },
	-- The five words the SHELL is, and so the five with no file in /bin: a
	-- program cannot move the shell that ran it, and cannot own its jobs either
	-- (see CeroSecOS.isShellWord, and the note above CeroSecOS.BUILTINS).
	cd       = { desc = "change the working directory", usage = "cd [dir]", shell = true },
	chgrp    = { desc = "change a file's group", usage = "chgrp <group> <path>" },
	chmod    = { desc = "change a file's mode", usage = "chmod <mode> <path>" },
	chown    = { desc = "change a file's owner", usage = "chown <user> <path>" },
	clear    = { desc = "clear the screen", usage = "clear" },
	cp       = { desc = "copy a file or a tree", usage = "cp [-r] <src> <dst>" },
	crontab  = { desc = "list, edit or drop your crontab", usage = "crontab -e|-l|-r" },
	date     = { desc = "print the date and time", usage = "date [+FORMAT]" },
	deluser  = { desc = "remove an account", usage = "deluser [-r] <name>" },
	dev      = { desc = "list and work the devices",
		usage = "dev [kind|id [value|toggle]|find <id>]" },
	df       = { desc = "report disk space", usage = "df" },
	echo     = { desc = "print its arguments", usage = "echo [text...]" },
	edit     = { desc = "edit a file", usage = "edit <file>" },
	exit     = { desc = "log out", usage = "exit", shell = true },
	fg       = { desc = "bring a background job to the front",
		usage = "fg [%<n>|<id>]", shell = true },
	["false"] = { desc = "do nothing, unsuccessfully", usage = "false" },
	gpasswd  = { desc = "add or drop a group member", usage = "gpasswd -a|-d <user> <group>" },
	grep     = { desc = "find a string in files",
		usage = "grep [-c] [-i] [-n] [-v] <text> [file]..." },
	groupadd = { desc = "make a group", usage = "groupadd <name>" },
	groupdel = { desc = "remove a group", usage = "groupdel <name>" },
	groups   = { desc = "print an account's groups", usage = "groups [name]" },
	hash     = { desc = "hash a string the way a password is", usage = "hash <text> [salt]" },
	halt     = { desc = "switch the machine off", usage = "halt" },
	head     = { desc = "print the first lines of a file",
		usage = "head [-n N|-N] [file]" },
	help     = { desc = "list the commands in /bin", usage = "help" },
	hostname = { desc = "print or set the machine's name", usage = "hostname [name]" },
	id       = { desc = "print an account and its groups", usage = "id [name]" },
	ifconfig = { desc = "show the network interfaces",
		usage = "ifconfig [-a|<interface>]" },
	jobs     = { desc = "list the machine's jobs", usage = "jobs", shell = true },
	kill     = { desc = "stop a job", usage = "kill <id>|%<n>" },
	last     = { desc = "list the logins on this machine", usage = "last [name]" },
	ls       = { desc = "list a directory", usage = "ls [-laAF] [path]" },
	mail     = { desc = "read the mail cron left you", usage = "mail" },
	man      = { desc = "describe a command", usage = "man <command>" },
	mkdir    = { desc = "make a directory", usage = "mkdir <dir>" },
	mv       = { desc = "move or rename a file", usage = "mv <src> <dst>" },
	passwd   = { desc = "change a password", usage = "passwd [user]" },
	pwd      = { desc = "print the working directory", usage = "pwd" },
	reboot   = { desc = "restart the machine", usage = "reboot" },
	restart  = { desc = "restart the machine", usage = "restart" },
	ping     = { desc = "see whether a machine answers", usage = "ping <host|address>" },
	printf   = { desc = "print a formatted string", usage = "printf <format> [arg...]" },
	ps       = { desc = "list the machine's jobs and their cpu", usage = "ps" },
	rcp      = { desc = "copy a file to or from another machine",
		usage = "rcp <src> <dst>, one of them <host>:<path>" },
	rlogin   = { desc = "log in on another machine", usage = "rlogin <host> [-l user]" },
	rm       = { desc = "remove a file or a directory", usage = "rm [-r] <path>..." },
	rsh      = { desc = "run one command on another machine",
		usage = "rsh <host> [-l user] <command>..." },
	ruptime  = { desc = "list the machines on the wire", usage = "ruptime" },
	rwho     = { desc = "list who is logged in on them", usage = "rwho" },
	sh       = { desc = "run a script", usage = "sh <file> [args]" },
	shutdown = { desc = "switch the machine off",
		usage = "shutdown [-h|-r] [now|+N] | shutdown -c" },
	sleep    = { desc = "wait for a number of seconds", usage = "sleep <seconds>" },
	sort     = { desc = "sort lines", usage = "sort [-r] [-n] [-u] [file]..." },
	su       = { desc = "become another user", usage = "su [name]" },
	sudo     = { desc = "run a command as root", usage = "sudo <command> [args]" },
	tail     = { desc = "print the last lines of a file",
		usage = "tail [-n N|-N] [file]" },
	test     = { desc = "evaluate an expression", usage = "test <expression>" },
	touch    = { desc = "create a file, or stamp it", usage = "touch <file>" },
	-- A word the shell IS, like cd: `type` has to know the shell's own words and
	-- the PATH it looks a name up on, and neither of those is anything a file in
	-- /bin could be handed.
	type     = { desc = "say what a word is", usage = "type <name>", shell = true },
	uniq     = { desc = "drop repeated lines", usage = "uniq [-c] [file]" },
	["true"]  = { desc = "do nothing, successfully", usage = "true" },
	wait     = { desc = "wait for the background jobs", usage = "wait [id]...", shell = true },
	wc       = { desc = "count lines, words and bytes", usage = "wc [-clw] [file]..." },
	which    = { desc = "find a command on PATH", usage = "which <name>" },
	who      = { desc = "list who is logged in here", usage = "who [am i]" },
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

-- Is this word the shell itself? A word that is has no file in /bin, so nothing
-- looks one up for it and nothing seeds one -- `cd` cannot be a file, in Unix or
-- here: a program cannot move the shell that ran it.
function CeroSecOS.isShellWord(name)
	local info = (CeroSecOS.COMMAND_INFO or {})[name]
	if type(info) ~= "table" then return false end
	return info.shell == true
end

-- The commands that run with no file behind them. Two kinds, and they are not
-- the same kind: the shell's own words have no file to look up at all, and
-- `help` has one and is run without it anyway. A machine can be broken from
-- inside -- root may `rm -r /bin` and that is root's right -- and a player
-- standing in front of a broken one must still be able to ask what happened and
-- to walk away from it. Everything else is an executable or it is nothing.
--
-- Derived from the table above rather than listed beside it: a word marked
-- `shell` there is one here by construction, and the two cannot drift apart.
CeroSecOS.BUILTINS = { help = true }
for name, info in pairs(CeroSecOS.COMMAND_INFO) do
	if info.shell == true then CeroSecOS.BUILTINS[name] = true end
end

-- And the two a machine with no SHELL still answers, which is a different
-- question: /bin/sh deleted is a machine with nothing to parse a line with, and
-- the console lets exactly these two through anyway -- one to ask what happened,
-- one to walk away. A word of the shell is no use without the shell, so this is
-- deliberately not the set above.
CeroSecOS.NO_SHELL_WORDS = { exit = true, help = true }

-- What lives in the shell and what lives in /bin.
--
-- Unix has always had three kinds of word at a prompt, and this machine has
-- the same three:
--
--   * the reserved words -- if then elif else fi for while until do done --
--     which are grammar and were never commands at all;
--   * the shell's own words -- cd, exit, fg, jobs, wait, and read, shift, break,
--     continue, history -- which change the shell itself or own what it
--     started, and could not be a separate program if they tried: a program
--     cannot move the shell that ran it, and cannot be handed its job table
--     either. None of them is a file, and /bin never had any business holding
--     one -- the five that carry a COMMAND_INFO entry are marked `shell` there;
--     the rest are the engine's builtins and were never in that table at all;
--   * everything else, which is a FILE in /bin.
--
-- The third kind includes the ones a shell runs for speed without leaving the
-- house: echo, printf, test, [, true, false and sleep are executed inside the
-- engine and are still resolved through /bin/<name> first, exactly as `ls` is.
-- So `rm /bin/sleep` really does take sleep away, and `chmod 600 /bin/echo`
-- really does put echo out of an ordinary account's reach -- which is the whole
-- doctrine of this machine: the files are the truth about what it can do. Real
-- Unix ships /bin/pwd, /bin/su, /bin/kill and /bin/echo, and so does this one.
--
-- BUILTINS above is the other half of the same idea: the shell's own words,
-- which have no file, plus help -- the one command a player needs answered on a
-- machine whose /bin has been destroyed, so that he can ask what happened; exit
-- being a shell word is what lets him walk away from it.
CeroSecOS.BUILTIN_FILES = {
	echo = true, printf = true, sleep = true, test = true,
	["["] = true, ["true"] = true, ["false"] = true,
}

-- The words that are the shell's own, for `help` to list under the table of
-- files. Reserved words first, then the builtins that change the shell.
CeroSecOS.HELP_RESERVED = "if then elif else fi for while until do done"
CeroSecOS.HELP_BUILTINS = "cd exit fg jobs wait read shift break continue history type"

-- The same words as a set, derived from the line `help` prints rather than
-- listed a second time beside it: a word `help` says is the shell's own is one
-- here by construction, and the two cannot drift apart. `type` is what reads it.
CeroSecOS.SHELL_BUILTINS = {}
for word in string.gmatch(CeroSecOS.HELP_BUILTINS, "[^ ]+") do
	CeroSecOS.SHELL_BUILTINS[word] = true
end

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
	-- The words that are not files and never were. Kept apart from the table
	-- above, and after it, because the table IS /bin: a name in the block below
	-- has no executable to find, to delete or to chmod.
	out[#out + 1] = "shell words (no file in " .. CeroSecOS.BIN_PATH .. "):"
	out[#out + 1] = " " .. CeroSecOS.HELP_RESERVED
	out[#out + 1] = " " .. CeroSecOS.HELP_BUILTINS
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
	-- -a is everything, the two directory entries included; -A is everything
	-- except those two. The later of the two wins, which is how a real ls reads
	-- a line that carries both.
	local dots, hiddenToo = false, false
	for i = 2, #args do
		local a = args[i]
		if string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				local flag = string.sub(a, c, c)
				if flag == "l" then
					long = true
				elseif flag == "F" then
					classify = true
				elseif flag == "a" then
					dots, hiddenToo = true, true
				elseif flag == "A" then
					dots, hiddenToo = false, true
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
		-- A device that is not there is not listed inside /dev either, so
		-- naming it straight gets the same answer a listing gives.
		if node.dead then return fail("ls", shown, "no such file") end
		if long then
			if CeroSecOS.isDev(node) then return true, { CeroSecOS.devLine(node) } end
			return true, { longLine(node, name) }
		end
		return true, { CeroSecOS.truncate(name, CeroSecOS.COLS) }
	end
	if not CeroSecOS.can(state, session, node, "r") then return fail("ls", shown, "permission denied") end

	-- One array of what is being listed, so the long form and the columns are
	-- looking at the same thing. "." and ".." are not children of anything --
	-- they are the directory itself and the one above it -- so they are put in
	-- here rather than found by walking, and they sort first because "." is
	-- ahead of every letter in the character order childNames sorts by.
	local entries = {}
	if dots then
		entries[#entries + 1] = { name = ".", node = node }
		local up = CeroSecOS.getNode(state, session, shown .. "/..")
		if up ~= nil then entries[#entries + 1] = { name = "..", node = up } end
	end
	local names = CeroSecOS.listedNames(node, hiddenToo)
	for i = 1, #names do
		entries[#entries + 1] = { name = names[i], node = node.children[names[i]] }
	end

	local out = {}
	for i = 1, #entries do
		local child = entries[i].node
		local label = entries[i].name
		if classify and child.type == "dir" then label = label .. "/" end
		if long then
			-- A device has no size and no date; what stands in those columns is
			-- what it is and what it is doing (CeroSecOS.devLine).
			if CeroSecOS.isDev(child) then
				out[#out + 1] = CeroSecOS.devLine(child)
			else
				out[#out + 1] = longLine(child, label)
			end
		else
			out[#out + 1] = label
		end
	end
	if long then return true, out end
	return true, CeroSecOS.columnize(out, CeroSecOS.COLS)
end

-- Is this path a name inside /dev? Creating one is refused, and the refusal
-- names the DIRECTORY rather than the name that was typed: what is read-only is
-- /dev, and a player who tried once should not have to try a second name to
-- find that out.
local function underDev(session, path)
	local _, parts = CeroSecOS.resolve(session, path)
	local parentPath = CeroSecOS.parentOf(parts)
	return parentPath == CeroSecOS.DEV_PATH
end

local function devReadOnly()
	return false, { CeroSecOS.DEV_PATH .. ": read-only" }
end

commands.mkdir = function(state, session, args, env)
	if #args ~= 2 then return usage("mkdir") end
	if underDev(session, args[2]) then return devReadOnly() end
	local dir = CeroSecOS.newDir(CeroSecOS.userOf(session), 755)
	local created, reason = CeroSecOS.createNode(state, session, args[2], dir, CeroSecOS.clockOf(env))
	if created == nil then return fail("mkdir", args[2], reason) end
	return true, {}
end

commands.touch = function(state, session, args, env)
	if #args ~= 2 then return usage("touch") end
	local now = CeroSecOS.clockOf(env)
	local node, reason = CeroSecOS.getNode(state, session, args[2])
	if node == nil and underDev(session, args[2]) then return devReadOnly() end
	if node ~= nil then
		if node.type ~= "file" then return fail("touch", args[2], CeroSecOS.notAFile(node)) end
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

commands.cat = function(state, session, args, env, stdin)
	-- With no file, the pipe: `grep on /dev/null | cat` is cat copying its
	-- standard input, which is the whole of what cat has ever done.
	local input = stdinOf(stdin, operands(args))
	if input ~= nil then
		local out = {}
		for i = 1, #input.lines do out[#out + 1] = input.lines[i] end
		return true, out
	end
	if #args < 2 then return usage("cat") end
	local out, ok = {}, true
	for i = 2, #args do
		local p = args[i]
		local node, reason = CeroSecOS.getNode(state, session, p)
		if node == nil then
			ok = false
			out[#out + 1] = "cat: " .. p .. ": " .. reason
		elseif CeroSecOS.isDev(node) then
			-- A device answers with its state, and refuses in its OWN name:
			-- what a player is being told about is the light switch, not the
			-- command he reached it with.
			local text, refusal = CeroSecOS.devRead(state, session, node)
			if text == nil then
				ok = false
				out[#out + 1] = refusal
			else
				out[#out + 1] = text
			end
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

--
-- dev
--
-- The everyday face of /dev, and nothing more than that. Every read here goes
-- through CeroSecOS.devRead and every write through CeroSecOS.devWrite -- the
-- same two calls `cat /dev/light0` and `echo off > /dev/light0` reach -- so the
-- permissions, the vocabulary and every refusal are word for word what the
-- plumbing already answers. What it adds is a table to read at a glance, a
-- filter by kind, and a `toggle` that works the opposite out for you.
--
--   admin@ksp-04-11:~$ dev
--   door0   exterior            3E 2N    W  locked
--   light0  office              0 2N        on
--   lock0   exterior            3E 2N    W  locked
--   admin@ksp-04-11:~$ dev light0
--   light0: on
--   admin@ksp-04-11:~$ dev light0 off
--   light0: off
--   admin@ksp-04-11:~$ dev find lock1
--   lock1: highlighted
--
-- The columns are `ls -l /dev`'s without the mode, the owner and the group --
-- they read the same on every device -- plus the one column `ls -l` has no room
-- for and the thing a survivor actually picks a device out by: where it is from
-- where the machine stands (see SCeroSecDevices.offset). Room ids repeat and an
-- offset does not.
--
-- 8 id + 20 desc + 2 + 10 pos + 2 + 1 side + 2 + state, which puts the widest
-- state ("barricaded") on column 55. The description is 20 against `ls -l`'s
-- 13: wider than the listing that has a mode and an owner in front of it, and
-- narrower than it would be if the offset were not the better name.
local D_ID, D_DESC, D_POS, D_SIDE = 8, 20, 10, 1

local function devRow(node)
	return CeroSecOS.padRight(CeroSecOS.truncate(node.id or "?", D_ID), D_ID)
		.. CeroSecOS.padRight(CeroSecOS.truncate(node.desc or "", D_DESC), D_DESC)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.pos or "", D_POS), D_POS)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.side or "", D_SIDE), D_SIDE)
		.. "  " .. (node.state or "")
end

-- The number on the end of an id, or -1 for an id that carries none. Every id
-- the world hands out is a kind with a number after it (see the numbering in
-- SCeroSecDevices.lua); one that is not sorts ahead of them and then by name.
local function devNumber(id)
	local digits = string.match(id or "", "%d+$")
	if digits == nil then return -1 end
	return tonumber(digits)
end

-- Kind, then number. NOT by name, which is what every other listing on this
-- machine sorts by and what would put light10 between light1 and light2.
local function devBefore(a, b)
	if a.kind ~= b.kind then return a.kind < b.kind end
	local na, nb = devNumber(a.id), devNumber(b.id)
	if na ~= nb then return na < nb end
	return (a.id or "") < (b.id or "")
end

-- One word is a kind or it is an id, and the digits on the end are what tell
-- them apart: an id is a kind with a number after it, and no kind ends in one.
-- So `dev lock` filters, `dev lock9` names a device, and a word that is neither
-- is refused in the grammar of whichever one it was trying to be.
local function looksLikeId(word)
	return string.find(word, "%d$") ~= nil
end

-- The node one id names, through the same lookup `cat /dev/<id>` uses. A name
-- with a slash in it, a name nothing answers to, and anything at that name that
-- is not a device all come back nil, and the caller says "no such device" about
-- every one of them: from where the player stands they are the same miss.
local function devNodeOf(state, session, id)
	local node = CeroSecOS.getNode(state, session, CeroSecOS.DEV_PATH .. "/" .. id)
	if not CeroSecOS.isDev(node) then return nil end
	return node
end

-- What `toggle` writes, by the state it found. The words are the ones
-- CeroSecOS.DEV_VALUES already takes, so a toggle is a write whose value was
-- worked out for you and never a path of its own. A padlocked door toggles like
-- a locked one: "unlock" is what takes a padlock off, and "lock" is what puts it
-- back on a door that carries one (SCeroSecDevices.lua's `act`).
--
-- Nothing else has an opposite. A window that is smashed or barricaded is not in
-- a state a word undoes, so `dev win0 toggle` says so instead of guessing a
-- direction -- and `dev win0 lock` still asks the world, which refuses in its
-- own name ("win0: smashed").
--
-- By KIND and then by state, because one word means two things: "locked" is a
-- lock's state, which "unlock" undoes, and it is also a door's, which "open"
-- undoes -- and a door has no idea what the word "unlock" is. A locked door
-- toggles to "open" rather than refusing, so the machine goes and asks and the
-- world answers "door3: locked" in its own name, which tells a survivor which
-- device to go and turn.
local DEV_OPPOSITE = {
	light = { on = "off", off = "on" },
	lock  = { locked = "unlock", padlock = "unlock", unlocked = "lock" },
	win   = { locked = "unlock", unlocked = "lock" },
	door  = { open = "close", closed = "open", locked = "open" },
}

-- The table, whole or filtered by kind. A device the machine remembers the
-- number of and cannot reach is not on it, exactly as `ls /dev` has it.
local function devTable(state, session, kind)
	local dir, reason = CeroSecOS.getNode(state, session, CeroSecOS.DEV_PATH)
	if dir == nil then return fail("dev", CeroSecOS.DEV_PATH, reason) end
	if dir.type ~= "dir" then return fail("dev", CeroSecOS.DEV_PATH, "not a directory") end
	if not CeroSecOS.can(state, session, dir, "r") then
		return fail("dev", CeroSecOS.DEV_PATH, "permission denied")
	end

	local names = CeroSecOS.childNames(dir)
	local found = {}
	for i = 1, #names do
		local node = dir.children[names[i]]
		if CeroSecOS.isDev(node) and not node.dead
				and (kind == nil or node.kind == kind) then
			found[#found + 1] = node
		end
	end
	table.sort(found, devBefore)

	local out = {}
	for i = 1, #found do out[i] = devRow(found[i]) end
	return true, out
end

commands.dev = function(state, session, args, env)
	if #args > 3 then return usage("dev") end
	if #args == 1 then return devTable(state, session, nil) end

	local word = args[2]

	-- `dev find <id>`: point at one in the world. "find" is a word and not an
	-- id -- no id has ever been anything but a kind with a number after it --
	-- so there is nothing here for it to collide with.
	if word == "find" then
		if #args ~= 3 then return usage("dev") end
		local target = devNodeOf(state, session, args[3])
		if target == nil then return fail("dev", args[3], "no such device") end
		local how, refusal = CeroSecOS.devFind(state, session, target, env)
		if how == nil then return false, { refusal } end
		return true, { target.id .. ": " .. how }
	end
	if #args == 2 and not looksLikeId(word) then
		-- A kind is one the core has words for, and no other.
		if CeroSecOS.DEV_VALUES[word] == nil then return fail("dev", word, "unknown kind") end
		return devTable(state, session, word)
	end

	local node = devNodeOf(state, session, word)
	if node == nil then return fail("dev", word, "no such device") end

	if #args == 2 then
		local text, refusal = CeroSecOS.devRead(state, session, node)
		if text == nil then return false, { refusal } end
		return true, { node.id .. ": " .. text }
	end

	local value = args[3]
	if value == "toggle" then
		local text, refusal = CeroSecOS.devRead(state, session, node)
		if text == nil then return false, { refusal } end
		local opposites = DEV_OPPOSITE[node.kind]
		value = nil
		if opposites ~= nil then value = opposites[text] end
		if value == nil then return false, { node.id .. ": cannot toggle" } end
	end

	local done, refusal = CeroSecOS.devWrite(state, session, node, value, env)
	if done == nil then return false, { refusal } end
	-- The state the world was re-read for, off the node devWrite put it on --
	-- not read again through devRead, because a machine that took the order and
	-- then refused to say what happened would be worse than one that never took
	-- it.
	return true, { node.id .. ": " .. (node.state or "") }
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
	-- Said about the SOURCE, before the destination is worked out: what is a
	-- device is the thing being moved, and mv's other refusals all name the
	-- target because it is the target they are about.
	if CeroSecOS.isDev(node) then return fail("mv", src, "is a device") end

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
	-- A device cannot be copied: what would come out is a file holding the word
	-- "on", which is a lie about a light switch.
	if CeroSecOS.isDev(node) then return fail("cp", src, "is a device") end
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

-- chmod. An octal mode, or a symbolic one applied to the mode the file already
-- wears. Which of the two it is is decided BEFORE the path is looked at, so
-- `chmod zzz nosuchfile` still answers about the mode: a typo in the mode is
-- the thing the player got wrong and is what he should be told about.
commands.chmod = function(state, session, args, env)
	if #args ~= 3 then return usage("chmod") end
	local mode = parseMode(args[2])
	-- Tried against 000 only to judge the grammar; the real mode is the file's
	-- and is not known until the node is in hand.
	local symbolic = mode == nil and CeroSecOS.applyModeSpec(0, args[2]) ~= nil
	if mode == nil and not symbolic then return fail("chmod", args[2], "invalid mode") end
	local node, reason = CeroSecOS.getNode(state, session, args[3])
	if node == nil then return fail("chmod", args[3], reason) end
	if not isOwnerOrRoot(session, node) then return fail("chmod", args[3], "permission denied") end
	if symbolic then
		mode = CeroSecOS.applyModeSpec(node.mode, args[2])
		if mode == nil then return fail("chmod", args[2], "invalid mode") end
	end
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
	-- A device is root's, always. Only the MODE of one is remembered across a
	-- command (see CeroSecOS.mountDev), so an owner given away here would be
	-- back to root by the next line, and a change that does not last is a
	-- change not to accept.
	if CeroSecOS.isDev(node) then return fail("chown", args[3], "is a device") end
	if not isOwnerOrRoot(session, node) then return fail("chown", args[3], "permission denied") end
	node.owner = user.name
	local now = CeroSecOS.clockOf(env)
	if now ~= nil then node.mtime = now end
	return true, {}
end

-- chgrp. The owner's to give away and root's to take, exactly as chown is: a
-- file is shared by the account that owns it, and asking root every time would
-- make sharing a thing only root does.
--
-- The group has to EXIST -- a line in /etc/group, or an account, whose primary
-- group needs no line -- so that a typo is caught at the moment it is typed
-- rather than three days later when nobody can read the file. A group that is
-- deleted afterwards is a different thing: the name stays on the file, dangling,
-- and it is `ls -l` that says so.
commands.chgrp = function(state, session, args, env)
	if #args ~= 3 then return usage("chgrp") end
	if not CeroSecOS.groupExists(state, args[2]) then
		return fail("chgrp", args[2], "no such group")
	end
	local node, reason = CeroSecOS.getNode(state, session, args[3])
	if node == nil then return fail("chgrp", args[3], reason) end
	-- A device's group is what makes its 660 mean "whoever may sudo", and only
	-- the MODE of one is remembered across a command (see CeroSecOS.mountDev),
	-- so a group given away here would be back to sudo by the next line.
	if CeroSecOS.isDev(node) then return fail("chgrp", args[3], "is a device") end
	if not isOwnerOrRoot(session, node) then return fail("chgrp", args[3], "permission denied") end
	node.group = args[2]
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
	if node.type ~= "file" then
		return nil, cmd .. ": " .. path .. ": " .. CeroSecOS.notAFile(node)
	end
	if not CeroSecOS.can(state, session, node, "r") then
		return nil, cmd .. ": " .. path .. ": permission denied"
	end
	return CeroSecOS.splitLines(node.data or ""), nil, node
end

-- Is this line one of the ones grep was asked for? -v is the whole of the
-- difference between "holds the string" and "is a line grep prints": the flag
-- does not change what a hit is, it changes which lines are wanted.
--
-- The needle is already lowered by the caller when -i is on, because it is
-- lowered once for a file and not once for a line.
local function grepHit(line, needle, ignore, invert)
	local hay = line
	if ignore then hay = string.lower(hay) end
	local held = string.find(hay, needle, 1, true) ~= nil
	if invert then return not held end
	return held
end

-- grep. A plain substring and not a pattern: string.find's fourth argument is
-- what makes "a.b" mean the three characters and not "a, anything, b". There is
-- no regex on this machine and none is promised.
commands.grep = function(state, session, args, env, stdin)
	local flags, rest = flagsOf(args, "cinv")
	if flags == nil then return fail("grep", rest, "unknown option") end
	local ignore, numbered = flags.i == true, flags.n == true
	local counting, invert = flags.c == true, flags.v == true
	if #rest < 1 then return usage("grep") end

	local needle = rest[1]
	if ignore then needle = string.lower(needle) end

	-- With a string and no file, the pipe. The line numbers are the PIPE's --
	-- counted from the first line that came down it, not restarted every time
	-- grep is called -- and whether anything was found is carried the same way,
	-- so `... | grep x` answers 0 for a hit that came down in an earlier turn.
	local files = {}
	for i = 2, #rest do files[#files + 1] = rest[i] end
	local input = stdinOf(stdin, files)
	if input ~= nil then
		local carry = input.carry
		if carry.n == nil then carry.n = 0 end
		if carry.hits == nil then carry.hits = 0 end
		local out = {}
		for i = 1, #input.lines do
			carry.n = carry.n + 1
			if grepHit(input.lines[i], needle, ignore, invert) then
				carry.found = true
				carry.hits = carry.hits + 1
				if not counting then
					local prefix = ""
					if numbered then prefix = tostring(carry.n) .. ":" end
					out[#out + 1] = prefix .. input.lines[i]
				end
			end
		end
		-- -c has one line to say and cannot say it before the end of the pipe:
		-- a count of what has arrived so far is not a count of anything.
		if counting then
			if not input.eof then return true, {} end
			out[1] = tostring(carry.hits)
		end
		if not carry.found then return false, out end
		return true, out
	end
	if #files == 0 then return usage("grep") end
	-- The file's name goes in front of a hit only when there is more than one
	-- file to tell apart, which is what grep has always done.
	local many = #files > 1
	local out, found, okAll = {}, false, true

	for i = 1, #files do
		local path = files[i]
		local lines, refusal = fileLines(state, session, "grep", path)
		if lines == nil then
			okAll = false
			out[#out + 1] = refusal
		else
			local hits = 0
			for n = 1, #lines do
				if grepHit(lines[n], needle, ignore, invert) then
					found = true
					hits = hits + 1
					if not counting then
						local prefix = ""
						if many then prefix = path .. ":" end
						if numbered then prefix = prefix .. tostring(n) .. ":" end
						out[#out + 1] = prefix .. lines[n]
					end
				end
			end
			-- -c is a line a file, and says nought as readily as it says three:
			-- the count IS the answer, so an empty one is still an answer. It
			-- prints instead of the lines, and -n has nothing left to number.
			if counting then
				local prefix = ""
				if many then prefix = path .. ":" end
				out[#out + 1] = prefix .. tostring(hits)
			end
		end
	end

	-- grep answers "did you find anything". Nothing found is a refusal even
	-- when every file was read without trouble -- and a -c that counted nothing
	-- is nothing found, however many zeroes it printed.
	if not found then return false, out end
	return okAll, out
end

-- -n N, or the older -N: `head -1` and `tail -5` are how the two of them were
-- spelled before -n existed, they are still what a pair of hands types, and
-- every Unix still takes them. Nothing else. Answers the count and the paths, or
-- nil for a line that is not one -- which the caller turns into the usage
-- string.
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
		elseif #rest == 0 and string.match(a, "^%-%d+$") ~= nil then
			n = tonumber(string.sub(a, 2))
			i = i + 1
		elseif #rest == 0 and string.sub(a, 1, 1) == "-" and a ~= "-" then
			return nil
		else
			rest[#rest + 1] = a
			i = i + 1
		end
	end
	return n, rest
end

commands.head = function(state, session, args, env, stdin)
	local n, rest = lineCount(args)
	if n == nil then return usage("head") end

	-- With no file, the pipe -- and head is the one command that CLOSES it. Once
	-- it has the lines it was asked for it will read no more, and a pipe with
	-- nobody reading it kills whatever is writing into it: that is how
	-- `yes | head -1` ends on a real machine, and it is how it ends here.
	local input = stdinOf(stdin, rest)
	if input ~= nil then
		local carry = input.carry
		if carry.n == nil then carry.n = 0 end
		local out = {}
		for i = 1, #input.lines do
			if carry.n >= n then break end
			carry.n = carry.n + 1
			out[#out + 1] = input.lines[i]
		end
		if carry.n >= n then input.done = true end
		return true, out
	end

	if #rest ~= 1 then return usage("head") end
	local lines, refusal = fileLines(state, session, "head", rest[1])
	if lines == nil then return false, { refusal } end
	local out = {}
	for i = 1, #lines do
		if i > n then break end
		out[#out + 1] = lines[i]
	end
	return true, out
end

commands.tail = function(state, session, args, env, stdin)
	local n, rest = lineCount(args)
	if n == nil then return usage("tail") end

	-- With no file, the pipe. Which lines were the last ones is not known until
	-- the pipe closes, so what is kept is the last n of what has come down it so
	-- far -- and nothing is printed until the end of it.
	local input = stdinOf(stdin, rest)
	if input ~= nil then
		local carry = input.carry
		if carry.keep == nil then carry.keep = {} end
		for i = 1, #input.lines do
			carry.keep[#carry.keep + 1] = input.lines[i]
			carry.bytes = (carry.bytes or 0) + #input.lines[i] + 1
			-- Only the last n are ever kept, so a pipe with no end to it costs
			-- tail nothing more than the lines it was asked for.
			while #carry.keep > n do
				carry.bytes = carry.bytes - #carry.keep[1] - 1
				table.remove(carry.keep, 1)
			end
			if #carry.keep > CeroSecOS.PIPE_LINES or carry.bytes > CeroSecOS.PIPE_BYTES then
				carry.over = true
			end
		end
		if carry.over then
			input.done = true
			return fail("tail", nil, "input too large")
		end
		if not input.eof then return true, {} end
		return true, carry.keep
	end

	if #rest ~= 1 then return usage("tail") end
	local lines, refusal = fileLines(state, session, "tail", rest[1])
	if lines == nil then return false, { refusal } end
	local first = #lines - n + 1
	if first < 1 then first = 1 end
	local out = {}
	for i = first, #lines do out[#out + 1] = lines[i] end
	return true, out
end

-- wc: lines, words, bytes, name -- or whichever of the three -l, -w and -c ask
-- for, always in that order however the flags were written, which is POSIX's
-- rule and not a choice. No flag at all is all three, which is the one place the
-- default is written down.
--
-- A number is 6 columns and a space, so three of them is 21 of the screen's 60
-- and the name has the 39 left; ask for one number and the name has 53. The row
-- is the same width whatever was asked for, which is what keeps a column of them
-- a column.
local W_NUM, W_ROW = 6, 60
local WC_ORDER = { "l", "w", "c" }

-- The numbers on their own, which is the whole line when what was counted came
-- down a pipe: there is no name to put after them, and wc has never invented
-- one. Answers the text and HOW MANY numbers are in it, because what is left of
-- the row for a name is what the caller needs next.
local function wcCounts(want, counts)
	local out, shown = "", 0
	for i = 1, #WC_ORDER do
		local key = WC_ORDER[i]
		if want[key] then
			if shown > 0 then out = out .. " " end
			out = out .. CeroSecOS.padLeft(tostring(counts[key] or 0), W_NUM)
			shown = shown + 1
		end
	end
	return out, shown
end

local function wcLine(want, counts, name)
	local out, shown = wcCounts(want, counts)
	return out .. " " .. CeroSecOS.truncate(name, W_ROW - 7 * shown)
end

-- A word is a run of anything that is not a blank. Newlines count as blanks:
-- the data is one string with newlines in it, not a list of lines.
local function wordsIn(text)
	local n = 0
	for _ in string.gmatch(text, "[^ \t\n]+") do n = n + 1 end
	return n
end

commands.wc = function(state, session, args, env, stdin)
	local want, paths = flagsOf(args, "clw")
	if want == nil then return fail("wc", paths, "unknown option") end
	-- No flag is every flag. Asked here, once, so that the pipe and the files
	-- below both count what they were asked for and nothing else.
	if not (want.l or want.w or want.c) then
		want.l, want.w, want.c = true, true, true
	end

	-- With no file, the pipe. Three running totals and nothing else is kept, so
	-- a pipe that never ends is counted for as long as it runs without wc ever
	-- holding more than three numbers. All three are kept whatever was asked
	-- for: the numbers cost nothing to carry and the flags only decide what is
	-- printed at the end of it.
	local input = stdinOf(stdin, paths)
	if input ~= nil then
		local carry = input.carry
		for i = 1, #input.lines do
			local line = input.lines[i]
			-- The newlines BETWEEN the lines are bytes of what came down the
			-- pipe, and the one that would have followed the last line is not:
			-- it is the same text a file of those lines holds, so `wc f` and
			-- `cat f | wc` answer with the same three numbers.
			if (carry.l or 0) > 0 then carry.c = (carry.c or 0) + 1 end
			carry.l = (carry.l or 0) + 1
			carry.w = (carry.w or 0) + wordsIn(line)
			carry.c = (carry.c or 0) + #line
		end
		if not input.eof then return true, {} end
		return true, { (wcCounts(want, carry)) }
	end
	if #paths == 0 then return usage("wc") end
	local out, okAll = {}, true
	local total, counted = { l = 0, w = 0, c = 0 }, 0
	for i = 1, #paths do
		local path = paths[i]
		local lines, refusal, node = fileLines(state, session, "wc", path)
		if lines == nil then
			okAll = false
			out[#out + 1] = refusal
		else
			local data = node.data or ""
			local counts = { l = #lines, w = wordsIn(data), c = #data }
			counted = counted + 1
			total.l = total.l + counts.l
			total.w = total.w + counts.w
			total.c = total.c + counts.c
			out[#out + 1] = wcLine(want, counts, path)
		end
	end
	if counted > 1 then
		out[#out + 1] = wcLine(want, total, "total")
	end
	return okAll, out
end

--
-- sort and uniq
--
-- The two commands a pipeline is usually built to reach. Both of them take a
-- file as well, exactly as they do on a real machine: `sort names` and
-- `sort < names` are the same answer, and this machine has no "<" yet.
--

-- Byte order, worked out here rather than left to "<". Lua's own comparison on
-- strings is the C library's strcoll, which answers by the LOCALE -- and under
-- the game's Kahlua it is Java's, which compares by code unit. Neither is a
-- promise worth making about what `sort` prints, so the bytes are compared here,
-- which is what sort in the C locale does and what a 1993 machine did.
local function beforeBytes(a, b)
	local n = #a
	if #b < n then n = #b end
	for i = 1, n do
		local x, y = string.byte(a, i), string.byte(b, i)
		if x ~= y then return x < y end
	end
	return #a < #b
end

-- The number at the front of a line, the way sort -n reads one: blanks, an
-- optional sign, digits. A line with no number at the front of it is zero, which
-- is what every sort has done with one.
local function leadingNumber(line)
	local digits = string.match(line, "^[ \t]*([%-+]?%d+)")
	if digits == nil then return 0 end
	return tonumber(digits) or 0
end

-- Is a before b? The one comparison sort makes, asked in one place so that -r
-- is that comparison the other way round and not a second rule.
local function sortLess(a, b, numeric)
	if numeric then
		local x, y = leadingNumber(a), leadingNumber(b)
		-- Equal numbers fall back to the bytes, so two lines that sort the same
		-- numerically still come out in one order and not in whichever one the
		-- sort happened to leave them in.
		if x ~= y then return x < y end
	end
	return beforeBytes(a, b)
end

-- lines, sorted. The array is the caller's and is sorted in place -- and with
-- -u, what comes back is a NEW array with the repeats dropped: on a sorted list
-- that is the neighbour test uniq makes and not a second rule. What counts as a
-- repeat is a line the comparison above cannot tell from the one before it, and
-- that comparison ends in the bytes -- so `sort -nu` keeps both "01" and "1",
-- which are the same number and are not the same line.
local function sortLines(lines, reverse, numeric, unique)
	table.sort(lines, function(a, b)
		if reverse then return sortLess(b, a, numeric) end
		return sortLess(a, b, numeric)
	end)
	if not unique then return lines end
	local out = {}
	for i = 1, #lines do
		if #out == 0 or lines[i] ~= out[#out] then out[#out + 1] = lines[i] end
	end
	return out
end

commands.sort = function(state, session, args, env, stdin)
	local flags, paths = flagsOf(args, "nru")
	if flags == nil then return fail("sort", paths, "unknown option") end
	local reverse, numeric, unique = flags.r == true, flags.n == true, flags.u == true

	-- With no file, the pipe. Nothing can be printed before the end of it: the
	-- smallest line may still be coming, so what has arrived is kept -- under the
	-- ceiling a pipe itself has -- until the pipe closes.
	local input = stdinOf(stdin, paths)
	if input ~= nil then
		local carry = input.carry
		for i = 1, #input.lines do
			if not holdLine(carry, input.lines[i]) then carry.over = true end
		end
		if carry.over then
			-- It has given up, so it will read no more: the pipe closes, which
			-- is what stops whatever is writing into it. A `sort` that went on
			-- reading a flood it has already refused would be a refusal that
			-- costs the machine exactly as much as no refusal at all.
			input.done = true
			return fail("sort", nil, "input too large")
		end
		if not input.eof then return true, {} end
		return true, sortLines(carry.lines or {}, reverse, numeric, unique)
	end

	if #paths == 0 then return usage("sort") end
	local all, out, okAll = {}, {}, true
	for i = 1, #paths do
		local lines, why = fileLines(state, session, "sort", paths[i])
		if lines == nil then
			okAll = false
			out[#out + 1] = why
		else
			for k = 1, #lines do all[#all + 1] = lines[k] end
		end
	end
	if not okAll then return false, out end
	return true, sortLines(all, reverse, numeric, unique)
end

-- What `uniq -c` puts in front of a line. Seven columns and a space, which is
-- the width uniq has counted in for as long as it has had a -c.
local function uniqLine(count, line, counting)
	if not counting then return line end
	return CeroSecOS.padLeft(tostring(count), 7) .. " " .. line
end

-- One line into uniq's running state, and whatever that finishes. ADJACENT
-- lines only: uniq has never sorted anything, which is why it is the command
-- after `sort` and not instead of it.
local function uniqStep(carry, line, counting, out)
	if carry.prev == nil then
		carry.prev = line
		carry.count = 1
		return
	end
	if carry.prev == line then
		carry.count = carry.count + 1
		return
	end
	out[#out + 1] = uniqLine(carry.count, carry.prev, counting)
	carry.prev = line
	carry.count = 1
end

local function uniqEnd(carry, counting, out)
	if carry.prev == nil then return end
	out[#out + 1] = uniqLine(carry.count, carry.prev, counting)
	carry.prev = nil
end

commands.uniq = function(state, session, args, env, stdin)
	local flags, paths = flagsOf(args, "c")
	if flags == nil then return fail("uniq", paths, "unknown option") end
	local counting = flags.c == true

	-- With no file, the pipe. One line and one count is all uniq ever holds, so
	-- there is no ceiling for it to meet.
	local input = stdinOf(stdin, paths)
	if input ~= nil then
		local carry, out = input.carry, {}
		for i = 1, #input.lines do uniqStep(carry, input.lines[i], counting, out) end
		if input.eof then uniqEnd(carry, counting, out) end
		return true, out
	end

	if #paths ~= 1 then return usage("uniq") end
	local lines, why = fileLines(state, session, "uniq", paths[1])
	if lines == nil then return false, { why } end
	local carry, out = {}, {}
	for i = 1, #lines do uniqStep(carry, lines[i], counting, out) end
	uniqEnd(carry, counting, out)
	return true, out
end

-- man. The description is the FILE's, exactly like help's: a machine whose /bin
-- has been cut down has no manual for what is no longer on it, and one whose
-- /bin/ls somebody rewrote says what that file says. The usage line is the
-- shell's own, so it is the one a wrong command line prints back.
commands.man = function(state, session, args, env)
	if #args ~= 2 then return usage("man") end
	local name = args[2]
	-- A word the shell itself is has no file to read the entry out of, and its
	-- entry is the shell's own: `man cd` answers on a machine where /bin is
	-- nothing but a memory, because cd is still there.
	if CeroSecOS.isShellWord(name) then
		local out = { name .. " - " .. CeroSecOS.commandDesc(name) }
		out[#out + 1] = "usage: " .. CeroSecOS.commandUsage(name)
		out[#out + 1] = "a word of the shell itself: no file in " .. CeroSecOS.BIN_PATH
		return true, out
	end
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

-- What every Unix has broadcast to every terminal on the machine since the
-- seventies, word for word. The two shapes that are not a plural are the two
-- Unix has always had: one minute, and now.
function CeroSecOS.shutdownLine(control, minutes)
	local word = "halt"
	if control == "reboot" then word = "reboot" end
	local head = "The system is going down for " .. word .. " "
	if type(minutes) ~= "number" or minutes <= 0 then return head .. "NOW!" end
	if minutes == 1 then return head .. "in 1 minute!" end
	return head .. "in " .. tostring(math.floor(minutes)) .. " minutes!"
end

-- How long a "+N" may be. A day is longer than anybody sits at one of these
-- and short enough that the arithmetic cannot run off the end of a number.
CeroSecOS.SHUTDOWN_MAX_MINUTES = 1440

-- shutdown [-h|-r] [now|+N], and shutdown -c.
--
-- `-h` halts and `-r` reboots, exactly as they do on a real one; with neither,
-- the machine halts. `now` and no time at all are the same thing. `+N` puts
-- the order N minutes out, broadcasts it to every screen standing at the
-- machine, and broadcasts again a minute before -- and the timer is the
-- SCHEDULER's, because the core has no clock of its own and no machine to
-- switch off.
--
-- One pending order per machine: a second is refused rather than quietly
-- replacing the first, so nobody is told the machine is going down at two
-- different times.
commands.shutdown = function(state, session, args, env)
	local control, i = "shutdown", 2

	if args[2] == "-c" then
		if #args > 2 then return usage("shutdown") end
		if CeroSecOS.userOf(session) ~= "root" then
			return fail("shutdown", nil, "permission denied")
		end
		if type(env) ~= "table" or type(env.shutdown) ~= "table" then
			return fail("shutdown", nil, "no shutdown scheduled")
		end
		return true, { "shutdown: cancelled" }, "cancel"
	end

	if args[2] == "-h" then
		i = 3
	elseif args[2] == "-r" then
		control = "reboot"
		i = 3
	end
	if #args > i then return usage("shutdown") end
	if CeroSecOS.userOf(session) ~= "root" then
		return fail("shutdown", nil, "permission denied")
	end

	local when = args[i]
	if when == nil or when == "now" then return true, {}, control end
	local minutes = string.match(when, "^%+(%d+)$")
	if minutes == nil then return usage("shutdown") end
	minutes = tonumber(minutes)
	if minutes < 1 or minutes > CeroSecOS.SHUTDOWN_MAX_MINUTES then
		return usage("shutdown")
	end

	if type(env) == "table" and type(env.shutdown) == "table" then
		return fail("shutdown", nil, "already scheduled")
	end
	local nowMs = CeroSecOS.nowMsOf(env)
	if nowMs == nil then return fail("shutdown", nil, "no clock") end

	return true, { CeroSecOS.shutdownLine(control, minutes) }, "schedule",
		{ at = nowMs + minutes * 60000, kind = control }
end

commands.reboot = powerCommand("reboot", "reboot")
-- halt, the other name shutdown has had since the seventies: `shutdown -h now`
-- with nothing to type in front of it.
commands.halt = powerCommand("halt", "shutdown")
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
		if node.type ~= "file" then return fail("edit", path, CeroSecOS.notAFile(node)) end
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
	-- Refused here rather than at the save: nano lets you type into a buffer it
	-- can never write, this does not, and /dev can never take a file.
	if underDev(session, path) then return devReadOnly() end
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
		-- The terminal is the terminal whoever the command runs as: `sudo rlogin`
		-- is one hop further out than the session that typed it, and `sudo who am
		-- i` names the line it was typed on.
		line = session.line,
		hops = session.hops,
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
local function sudoRun(state, session, args, from, env, sh)
	local name = args[from]
	local sub = rootSessionFrom(session)

	-- A path is a script here too, so `sudo ./setup` is the same thing as
	-- `./setup` with root's own permissions on the file.
	if string.find(name, "/", 1, true) ~= nil then
		local rest = {}
		for i = from + 1, #args do rest[#rest + 1] = args[i] end
		local own = {}
		for i = from, #args do own[#own + 1] = args[i] end
		return CeroSecOS.startScript(state, sub, name, name, rest,
			table.concat(own, " "), env, true)
	end

	-- `exit` is not a program and could not be one: it ends the SESSION that ran
	-- it, and there is no /bin/exit for sudo to find. Real sudo says exactly this
	-- about it, in its own name, because the name it looked up is the one it could
	-- not find. (`cd` is the same kind of word and this machine has answered
	-- `sudo cd` quietly since sudo arrived -- see the note in the manual.)
	if name == "exit" then return false, { "sudo: exit: command not found" } end

	local fn = commands[name]
	if fn == nil then return false, { name .. ": command not found" } end

	-- Looked up on the caller's own PATH, as root: the authority sudo lends is
	-- root's rights on the file, not a second PATH of its own -- real sudo of
	-- this era reset nothing about the environment either.
	if not CeroSecOS.BUILTINS[name] then
		local refusal = CeroSecOS.whyNotRun(state, sub, name, shPath(sh))
		if refusal ~= nil then return false, { name .. ": " .. refusal } end
	end

	-- Every command reads args[1] as its own name, so the tail is handed over
	-- with the name back in front of it.
	local own = {}
	for i = from, #args do own[#own + 1] = args[i] end

	-- Which session is the real one at the glass. `su` is the one command that
	-- needs it: `sudo su bob` is a shell of bob's at this computer, the way it is
	-- on a real machine, so it pushes on the CONSOLE's stack and not on the copy
	-- that dies with this command. Given here and not in rootSessionFrom, because
	-- a sudo'd SCRIPT is a shell of its own: `su` inside one moves that shell and
	-- not the glass, exactly as it does inside a script nobody sudo'd.
	-- session.real when there is one: a chain of sudos resolves to the one
	-- session none of them borrowed.
	sub.real = session.real or session

	local ok, lines, control, data = fn(state, sub, own, env, nil, sh)
	carryAs("root", control, data)
	return ok, lines, control, data
end

commands.sudo = function(state, session, args, env, stdin, sh)
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
	if me == "root" then return sudoRun(state, session, args, from, env, sh) end

	local entry = CeroSecOS.sudoer(state, me)
	if entry == nil then return false, { me .. " is not in the sudoers file." } end
	if entry.nopasswd then return sudoRun(state, session, args, from, env, sh) end

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

continuations.sudo = function(state, session, cont, line, env, sh)
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
	return sudoRun(state, session, args, 1, env, sh)
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
-- its /etc/passwd line carries, and every group it is in -- its own primary
-- group first, then the /etc/group lines that name it, then "sudo" when
-- /etc/sudoers is what puts it there. Anybody may ask, about anybody: who may
-- become root is not a secret on a machine where the answer is a file the
-- kernel reads out loud at every sudo.
commands.id = function(state, session, args, env)
	if #args > 2 then return usage("id") end
	local name = args[2]
	if name == nil or name == "" then name = CeroSecOS.userOf(session) end
	local user = CeroSecOS.getUser(state, name)
	if user == nil then return fail("id", name, "no such user") end
	local flag = "user"
	if user.admin then flag = "admin" end
	local groups = CeroSecOS.groupsOf(state, user.name)
	return true, { "uid=" .. user.name .. " flag=" .. flag
		.. " groups=" .. table.concat(groups, ",") }
end

-- groups. The same list id prints, on its own and separated by blanks, which is
-- how `groups` has printed it since it was one line of shell. Anybody may ask,
-- about anybody, for the reason id may be asked: /etc/group is world-readable
-- and the answer is already on the disk for whoever wants to cat it.
commands.groups = function(state, session, args, env)
	if #args > 2 then return usage("groups") end
	local name = args[2]
	if name == nil or name == "" then name = CeroSecOS.userOf(session) end
	if CeroSecOS.getUser(state, name) == nil then return fail("groups", name, "no such user") end
	return true, { table.concat(CeroSecOS.groupsOf(state, name), " ") }
end

--
-- Groups
--
-- Making, unmaking and filling one is root's, and root's alone: /etc/group says
-- who may read whose files, so it is root's file the way /etc/passwd is. An
-- admin does it the way he does everything else that is root's -- `sudo
-- groupadd crew` -- and there is no second rule for who may.
--
-- What /etc/group is NOT is the authority on sudo. /etc/sudoers is, and stays:
-- the group "sudo" here MIRRORS it -- id and groups show it for a name the
-- sudoers file carries, whether a line in this file names him or not -- and
-- putting somebody in the sudo group by hand shares the group's files with him
-- without giving him root. Only /etc/sudoers does that.
--

commands.groupadd = function(state, session, args, env)
	if #args ~= 2 then return usage("groupadd") end
	if CeroSecOS.userOf(session) ~= "root" then return fail("groupadd", nil, "permission denied") end
	local name = args[2]
	if not CeroSecOS.isValidGroupName(name) then return fail("groupadd", name, "invalid name") end
	if CeroSecOS.groupExists(state, name) then return fail("groupadd", name, "already exists") end
	local done, reason = CeroSecOS.addGroup(state, name, CeroSecOS.clockOf(env))
	if done == nil then return fail("groupadd", name, reason) end
	return true, {}
end

-- The three shipped groups cannot be taken away: root's own, the one the
-- devices belong to, and the one an account joins to share a file. Files still
-- carrying any other name are left carrying it -- a dangling group is what
-- `ls -l` will show, and it is the truth rather than a tidy lie about who those
-- files were shared with.
commands.groupdel = function(state, session, args, env)
	if #args ~= 2 then return usage("groupdel") end
	if CeroSecOS.userOf(session) ~= "root" then return fail("groupdel", nil, "permission denied") end
	local name = args[2]
	if CeroSecOS.GROUP_KEEP[name] then return fail("groupdel", name, "cannot remove") end
	local groups = CeroSecOS.readGroups(state)
	-- A primary group has no line to take out, so this is about the file and
	-- only about the file: `groupdel bob` on an account is "no such group".
	if groups[name] == nil then return fail("groupdel", name, "no such group") end
	local done, reason = CeroSecOS.removeGroup(state, name, CeroSecOS.clockOf(env))
	if done == nil then return fail("groupdel", name, reason) end
	return true, {}
end

-- gpasswd -a bob crew / gpasswd -d bob crew. A primary group is not a
-- membership anybody granted, so it is not one anybody may grant or take away:
-- `gpasswd -a bob bob` is refused as "no such group", because there is no line
-- for it and never will be.
commands.gpasswd = function(state, session, args, env)
	if #args ~= 4 then return usage("gpasswd") end
	local flag = args[2]
	if flag ~= "-a" and flag ~= "-d" then return usage("gpasswd") end
	if CeroSecOS.userOf(session) ~= "root" then return fail("gpasswd", nil, "permission denied") end
	local name, group = args[3], args[4]
	if CeroSecOS.getUser(state, name) == nil then return fail("gpasswd", name, "no such user") end
	local done, reason =
		CeroSecOS.setGroupMember(state, name, group, flag == "-a", CeroSecOS.clockOf(env))
	if done == nil then return fail("gpasswd", group, reason) end
	return true, {}
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

-- The session `su` acts on. Its own, normally -- and under `sudo` the CONSOLE's,
-- because `sudo su bob` is a shell of bob's at this glass and not a switch inside
-- a borrowed session that is about to end. sudoRun is what hands the link over,
-- and only to a command it runs itself.
local function suTarget(session)
	if session.borrowed and type(session.real) == "table" then return session.real end
	return session
end

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
	local target = suTarget(session)
	local stack = target.stack
	if type(stack) == "table" and #stack >= CeroSecOS.SU_MAX then
		return false, { "su: too many levels" }
	end
	if CeroSecOS.userOf(session) == "root" then return suSwitch(target, user) end
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
	return suSwitch(suTarget(session), user)
end

--
-- Resolving a command
--
-- A name typed at the shell is a FILE, and PATH says which directories are
-- looked in for it, left to right. The default is one directory -- /bin, where
-- the commands ship -- so a machine nobody has touched behaves exactly as it did
-- when /bin was the only place there was.
--
-- PATH is an ordinary shell variable: a login sets it, `.profile` may add to it
-- (PATH=$PATH:$HOME/bin), and a script or a cron line starts with the default
-- and never with the shell's, which is the classic cron trap and is named in the
-- manual. What is NOT looked up is a reserved word or one of the shell's own
-- words: `if` is grammar and `cd` cannot be a file, so no PATH can hold either.
-- A word with a "/" in it is a path and is not searched for at all.
--

-- The value a lookup walks, off the shell's own variables.
--
-- Absent is not empty. A shell whose PATH nobody set looks in /bin -- the way a
-- real sh falls back on a path of its own when the variable is not in the
-- environment, and what keeps a machine saved before there was a PATH on it able
-- to run a command. An EMPTY value is a value: one empty field, which is the
-- working directory and nothing else, so `PATH= ls` is "command not found".
function CeroSecOS.pathValue(vars)
	if type(vars) ~= "table" or type(vars.PATH) ~= "string" then
		return CeroSecOS.DEFAULT_PATH
	end
	return vars.PATH
end

-- The environment a login hands the shell, which is where PATH comes from at a
-- prompt. HOME goes in with it: it is the other thing a login shell has always
-- set, and it is what makes PATH=$PATH:$HOME/bin a line worth writing in a
-- .profile. A fresh table every time, so no two shells ever share one.
function CeroSecOS.loginVars(home)
	local vars = { PATH = CeroSecOS.DEFAULT_PATH }
	if type(home) == "string" and home ~= "" then vars.HOME = home end
	return vars
end

-- Where a name is found, walked left to right. absolute path, or nil plus the
-- bare reason -- the caller puts the name in front of it, so the two lines a
-- player ever sees are
--   ls: command not found
--   ls: permission denied
--
-- POSIX's rule and every sh's: the first candidate that is a file with x on it
-- for whoever typed it WINS, and a candidate that cannot be run does not stop the
-- search -- a copy of `ls` in ~/bin with no x on it is a file in the way, not a
-- command, and /bin/ls behind it still runs. What the walk carries is the best
-- REFUSAL it met on the way, so a name found everywhere and runnable nowhere
-- says "permission denied", and a name nothing answers to at all says "command
-- not found".
-- The third answer is how many directories were actually looked in, which is
-- what the walk COST: the shell charges it (see CeroSecOSVM.runSimple), because a
-- long PATH makes every command on the machine dearer and a budget that could not
-- see that would not be a budget.
--
-- At most MAX_PATH_DIRS of them. A PATH with more in it is refused where it is
-- set, so the only way to reach this bound is a value off a save file; what is
-- past it is not looked at, and the machine is slow for nobody.
function CeroSecOS.lookupPath(state, session, name, path)
	if path == nil then path = CeroSecOS.DEFAULT_PATH end
	local dirs = CeroSecOS.pathDirs(path)
	local refusal = nil
	local last = #dirs
	if last > CeroSecOS.MAX_PATH_DIRS then last = CeroSecOS.MAX_PATH_DIRS end
	for i = 1, last do
		local node, reason, abs = CeroSecOS.getNode(state, session, dirs[i] .. "/" .. name)
		if node == nil then
			-- Nothing there, a PATH entry that is not a directory, a PATH entry
			-- shut to this account: none of the three stops the walk, and the
			-- last one is worth saying when nothing further along answers.
			if reason ~= "no such file" and reason ~= "not a directory" then
				refusal = reason
			end
		elseif node.type ~= "file" then
			-- A directory called /bin/ls is not a command and neither is a
			-- device: both are something in the way, exactly as a file with no x
			-- on it is, and saying "is a directory" about a name the player never
			-- typed as a path would only puzzle him.
		elseif CeroSecOS.can(state, session, node, "x") then
			return abs, nil, i
		else
			refusal = "permission denied"
		end
	end
	if refusal ~= nil then return nil, refusal, last end
	return nil, "command not found", last
end

-- nil when the command may run, or the bare reason it may not. The path it was
-- found at comes back beside the nil, for the caller that needs to know WHICH
-- file answered.
function CeroSecOS.whyNotRun(state, session, name, path)
	local found, refusal, walked = CeroSecOS.lookupPath(state, session, name, path)
	if found == nil then return refusal, nil, walked end
	return nil, found, walked
end

--
-- which: where a name would be found, and nothing else.
--
-- It says nothing when it has nothing to say: a name no PATH entry answers to
-- prints no line at all and comes back unsuccessful, which is what makes
-- `which thing > /dev/null` the test it has been used as since csh shipped it.
--
-- It answers about FILES, because that is all a PATH holds: `which cd` finds
-- nothing, exactly as it finds nothing on a real machine, and `type` is the word
-- that knows about the shell's own.
commands.which = function(state, session, args, env, stdin, sh)
	if #args ~= 2 then return usage("which") end
	local found = CeroSecOS.lookupPath(state, session, args[2], shPath(sh))
	if found == nil then return false, {} end
	return true, { found }
end

-- type: which of the three kinds of word this is, in sh's own wording.
--
--   admin@ksp-04-11:~$ type ls
--   ls is /bin/ls
--   admin@ksp-04-11:~$ type cd
--   cd is a shell builtin
--   admin@ksp-04-11:~$ type if
--   if is a shell keyword
--
-- The order is the shell's own order of looking: a reserved word is grammar and
-- was never a command, the shell's own words come next, and everything else is a
-- file found on PATH. So a `ls` of your own in ~/bin is named by its own path
-- here -- type says what WOULD run and never what ships.
--
-- The commands the engine runs without leaving the house -- echo, printf, test,
-- true, false, sleep -- are files in /bin on this machine and are named as files,
-- because that is what they are here: `rm /bin/echo` takes echo away.
commands.type = function(state, session, args, env, stdin, sh)
	if #args ~= 2 then return usage("type") end
	local name = args[2]
	if CeroSecOS.RESERVED[name] then return true, { name .. " is a shell keyword" } end
	if CeroSecOS.SHELL_BUILTINS[name] or CeroSecOS.isShellWord(name) then
		return true, { name .. " is a shell builtin" }
	end
	local found = CeroSecOS.lookupPath(state, session, name, shPath(sh))
	if found == nil then return fail("type", name, "not found") end
	return true, { name .. " is " .. found }
end

--
-- The one entry point.
--

-- A redirect whose target is a device: the text goes to the WORLD and not to
-- the disk. nil when the target is not one, so the ordinary write follows.
-- true or false plus the lines, exactly like a command.
local function redirectToDevice(state, session, path, text, env)
	local node = CeroSecOS.getNode(state, session, path)
	if not CeroSecOS.isDev(node) then return nil end
	local done, refusal = CeroSecOS.devWrite(state, session, node, text, env)
	if done == nil then return false, CeroSecOS.fit({ refusal }) end
	return true, {}
end

-- Output, into whatever ">" named: a device if the target is one, a file
-- otherwise. Used by a command's own redirect and by a script's builtins, so
-- `echo hi > f` writes the same way whoever ran the echo.
-- true plus the lines, or false plus the refusal.
function CeroSecOS.writeRedirect(state, session, who, redirect, text, env)
	local devOk, devLines = redirectToDevice(state, session, redirect.path, text, env)
	if devOk ~= nil then return devOk, devLines end
	local done, reason = CeroSecOS.writeFile(state, session, redirect.path, text,
		redirect.append, CeroSecOS.clockOf(env))
	if done == nil then
		return false, CeroSecOS.fit({ who .. ": " .. redirect.path .. ": " .. reason })
	end
	return true, {}
end

-- OPENING what ">" named, with nothing to put in it yet. A shell opens the
-- target before the command runs -- that is why `cat nosuch > f` leaves an
-- empty f behind on a real machine -- and this is the one place on this one
-- where that matters: a command that has to ASK something (sudo) has not
-- written a byte and will not until the answer comes back, so the file is made
-- here and written when it does.
--
-- A device is not opened. It has no contents to truncate, only a state to be
-- put into, and putting it into one is what the write itself does.
-- true plus the lines, or false plus the refusal, exactly like the write.
function CeroSecOS.openRedirect(state, session, who, redirect, env)
	local node = CeroSecOS.getNode(state, session, redirect.path)
	if CeroSecOS.isDev(node) then return true, {} end
	-- ">>" creates what is not there and truncates nothing, which is the whole
	-- difference between the two: a file already there is opened and left
	-- exactly as it is, because appending nothing to it would be a blank line
	-- the command never wrote.
	if redirect.append and node ~= nil and node.type == "file" then return true, {} end
	local done, reason = CeroSecOS.writeFile(state, session, redirect.path, "", false,
		CeroSecOS.clockOf(env))
	if done == nil then
		return false, CeroSecOS.fit({ who .. ": " .. redirect.path .. ": " .. reason })
	end
	return true, {}
end

--
-- The prompt
--
-- Every line a player types is parsed by CeroSecOS.parseScript and run as a
-- foreground JOB, on the console's own environment. There is no second,
-- simpler parser beside the script language and there never will be again:
-- `while true; do echo tick; sleep 1; done &` at the prompt is the same
-- grammar it is inside a file, because it IS the same grammar. The engine has
-- one shell.
--
-- What comes back is a job, not an answer. The steps it costs, the output it
-- trickles, the questions it asks and the ceiling it dies on are the
-- scheduler's, exactly as a script's are -- so a typed infinite loop trickles
-- and dies the way one written into a file does, and cannot lag a server.
--
-- job, or nil plus the one line to print.
--
-- vars is the console's own variable table and is taken BY REFERENCE: `x=5`
-- then `echo $x` on the next line is the same table, which is what makes the
-- prompt an environment and not a series of unrelated commands. status is the
-- $? the prompt came back with.
-- name, when given, is a FILE being run on the shell's environment -- the
-- login profile -- rather than a line somebody typed. It changes two things
-- and nothing else: what a parse error and a run-time error call themselves,
-- and what `ps` shows.
function CeroSecOS.promptJob(state, session, line, vars, status, name)
	if type(state) ~= "table" or state.fs == nil then return nil, "no filesystem" end
	if type(session) ~= "table" or type(session.user) ~= "string" then
		return nil, "not logged in"
	end
	if type(line) ~= "string" then return nil, "sh: syntax error" end

	local prog, reason, where = CeroSecOS.parseScript(line)
	-- No line number for a typed line: it is line one of nothing, and
	-- "sh: line 1:" in front of every typo would be a number that never says
	-- anything. A file has lines and is named after itself, like any script.
	if prog == nil then
		if name ~= nil then return nil, CeroSecOS.scriptError(name, reason, where) end
		return nil, "sh: " .. reason
	end

	local cmd = line
	if name ~= nil then cmd = name end
	local job = CeroSecOS.newJob({
		prog = prog, name = name or "sh", cmd = cmd, session = session,
		vars = vars, status = status,
	})
	-- What makes it the PROMPT's job rather than a script's: `cd` moves the
	-- console, `exit` logs out instead of ending the script, `edit` may open on
	-- the glass, and it holds no job slot of its own.
	job.interactive = true
	-- The line as it was typed, and the mark that says it WAS typed: a job with
	-- one names itself "sh" and prints no line number, because a prompt line is
	-- line one of nothing. ~/.profile has neither.
	if name == nil then job.promptLine = line end
	return job
end


-- One command, already split into words. The shell's own entry point above
-- calls it, and so does a script: the two must run a command the same way or
-- `ls` in a file is not the `ls` at the prompt.
-- The tilde is the shell's, not the filesystem's: it is expanded once, before
-- any command is handed its arguments, so `cd ~`, `ls ~`, `cat ~/notes.txt`
-- and `echo hi > ~/notes.txt` all work and no command has to know about it.
-- args[1] is a command name and is left alone -- there is no ~/bin on this
-- machine and a command is not a path.
--
-- Called on BOTH doors a command line goes through: the one below, and the
-- walker's own for the builtins it runs without leaving the house
-- (CeroSecOSVM.runSimple). A builtin that did not get the expansion was a
-- builtin for which `~` was four characters of filename.
--
-- Idempotent: a path that has already been expanded no longer starts with a
-- tilde, so running it twice is running it once.
function CeroSecOS.expandTilde(state, session, args, redirect)
	local user = CeroSecOS.getUser(state, session.user)
	if user == nil or type(user.home) ~= "string" then return end
	for i = 2, #args do args[i] = CeroSecOS.expandHome(args[i], user.home) end
	if redirect ~= nil then
		redirect.path = CeroSecOS.expandHome(redirect.path, user.home)
	end
end

function CeroSecOS.runArgs(state, session, args, redirect, env, stdin, sh)
	local path, tty = shPath(sh), shTty(sh)
	CeroSecOS.expandTilde(state, session, args, redirect)

	-- A bare redirection still creates (or truncates) the file.
	if #args == 0 then
		if redirect == nil then return true, {} end
		local devOk, devLines = redirectToDevice(state, session, redirect.path, "", env)
		if devOk ~= nil then return devOk, devLines end
		local done, wreason = CeroSecOS.writeFile(state, session, redirect.path, "",
			redirect.append, CeroSecOS.clockOf(env))
		if done == nil then return false, CeroSecOS.fit({ redirect.path .. ": " .. wreason }) end
		return true, {}
	end

	local name = args[1]

	-- A name with a slash in it is a PATH and is never looked up: ./backup and
	-- /home/admin/backup are the file itself, run because it carries x for
	-- whoever typed it. PATH is for BARE names only, which is what it has always
	-- been for.
	if string.find(name, "/", 1, true) ~= nil then
		local rest = {}
		for i = 2, #args do rest[#rest + 1] = args[i] end
		local ok, lines, control, data = CeroSecOS.startScript(state, session, name, name,
			rest, table.concat(args, " "), env, true)
		return ok, CeroSecOS.fit(lines), control, data
	end

	local fn = commands[name]
	-- The shell's own words are never looked up. `cd` is not a file -- a program
	-- cannot move the shell that ran it -- so there is nothing on any PATH that
	-- could answer for one, and `help` is the word a machine with nothing left in
	-- /bin still answers.
	if CeroSecOS.BUILTINS[name] then
		if fn == nil then return false, CeroSecOS.fit({ name .. ": command not found" }) end
	else
		local found, refusal, walked = CeroSecOS.lookupPath(state, session, name, path)
		-- What the walk cost, back into the table the shell handed down: the
		-- walker charges it, and a caller that gave no table is a caller that is
		-- not charging anything either.
		if type(sh) == "table" then sh.walked = walked end
		if found == nil then return false, CeroSecOS.fit({ name .. ": " .. refusal }) end
		-- WHICH file answered decides what runs. One in /bin is the machine's own
		-- executable and the engine is what is behind it -- a file there with no
		-- command behind it is not a command, exactly as it never was. One found
		-- anywhere else is a file, and a file that is run is a script: that is
		-- what makes ~/bin an account's own commands, and what lets a name there
		-- shadow the one in /bin when PATH names it first, which is the whole
		-- point of a PATH.
		local _, parts = CeroSecOS.resolve(nil, found)
		if CeroSecOS.parentOf(parts) ~= CeroSecOS.BIN_PATH then
			local rest = {}
			for i = 2, #args do rest[#rest + 1] = args[i] end
			local ok, lines, control, data = CeroSecOS.startScript(state, session, found, found,
				rest, table.concat(args, " "), env, true)
			return ok, CeroSecOS.fit(lines), control, data
		end
		if fn == nil then return false, CeroSecOS.fit({ name .. ": command not found" }) end
	end

	local ok, lines, control, data = fn(state, session, args, env, stdin,
		{ path = path, tty = tty })
	if lines == nil then lines = {} end

	-- Output goes to the file only when the command succeeded; errors stay on
	-- the screen, as they would on stderr. A command that has not finished --
	-- one that asks, or one that opens the editor -- has no output to redirect
	-- yet, so the redirection never applies to it.
	-- "job" joins them: a script that has just been handed to the machine has
	-- printed nothing yet, and its output goes to the screen as it is made.
	local redirectable = control ~= "prompt" and control ~= "edit" and control ~= "job"
	if ok and redirect ~= nil and redirectable then
		-- ">" and ">>" are the same order to a device: it has no contents to
		-- append to, only a state to be put into.
		local wroteOk, wroteLines =
			CeroSecOS.writeRedirect(state, session, name, redirect, table.concat(lines, "\n"), env)
		return wroteOk, wroteLines, control
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
--
-- redirect is what the line that STARTED the chain was typed with, when it was
-- typed with one: `sudo cat /etc/passwd > copie.txt` is a redirect the command
-- had not earned yet when it asked for a password, and it is carried on the job
-- until the answer comes back (CeroSecOSVM.jobInput). It is a plain table --
-- path, append, and the name to put in front of a refusal -- exactly like the
-- one a command is handed.
local continueLine

function CeroSecOS.continue(state, session, cont, line, env, redirect, sh)
	-- A chain that ends in a command is a command, so /dev is under it too:
	-- `sudo cat /dev/light0` asks for a password first and reads the switch
	-- afterwards, on the answer.
	CeroSecOS.mountDev(state, env)
	local ok, lines, control, data = continueLine(state, session, cont, line, env, redirect, sh)
	CeroSecOS.unmountDev(state, env)
	return ok, lines, control, data
end

continueLine = function(state, session, cont, line, env, redirect, sh)
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
			line = session.line,
			hops = session.hops,
			-- Which session is the real one at the glass, for the one command
			-- that acts on it: `sudo su bob` answered a password first is still
			-- bob at this computer (see suTarget).
			real = session.real or session,
		}
	end

	local ok, lines, control, data = fn(state, run, cont, line, env, sh)
	if lines == nil then lines = {} end
	if run ~= session then carryAs(cont.as, control, data) end

	-- What the chain finally said goes where ">" pointed, on exactly the rule
	-- runArgs above runs on: the file when the command succeeded, the screen when
	-- it did not, and nothing at all while it is still asking. Written here, on
	-- the lines as the command made them -- a redirect is not a screen and a line
	-- on its way into a file is not folded at sixty columns.
	--
	-- Opened as whoever typed it and not as whoever the chain runs as, which is
	-- the shell's own rule and the reason `sudo cat /etc/passwd > /root/copie`
	-- is still refused: the redirect is the shell's half of the line.
	local redirectable = control ~= "prompt" and control ~= "edit" and control ~= "job"
	if ok and redirect ~= nil and redirectable then
		local wroteOk, wroteLines = CeroSecOS.writeRedirect(state, session,
			redirect.who or cont.cmd, redirect, table.concat(lines, "\n"), env)
		return wroteOk, wroteLines, control
	end

	return ok, CeroSecOS.fit(lines), control, data
end
