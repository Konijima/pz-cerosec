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
--   cd: can't cd to /root
--   cat: notes.txt: No such file or directory
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
-- The lines, oldest dropped until they fit, as one blob. The ceiling is handed
-- in because a history does not always land on the machine's own drive: see
-- CeroSecOS.historyAppend.
local function historyText(lines, ceiling)
	while #lines > CeroSecOS.HISTORY_MAX do table.remove(lines, 1) end
	local text = CeroSecOS.linesToText(lines)
	while #text > ceiling and #lines > 1 do
		table.remove(lines, 1)
		text = CeroSecOS.linesToText(lines)
	end
	-- One line of its own, longer than the whole file may be: cut rather than
	-- refused, because the alternative is a history that silently stops.
	if #text > ceiling then text = string.sub(text, 1, ceiling) end
	return text
end

local function historyPut(node, lines)
	node.data = historyText(lines, CeroSecOS.HISTORY_BYTES)
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

	-- Where the history really is.
	--
	-- Everything above this line is about the EXEMPTION, and the exemption belongs
	-- to the hard disk: it exists so that `df` on hda does not move because
	-- somebody typed, and it is what lets this write go straight onto the node
	-- instead of through the quota. A home with a disk mounted over it is not the
	-- hard disk, and there is no exemption there to spend -- so a history on a
	-- floppy is an ORDINARY file on that floppy: bounded by what a file may hold,
	-- counted against the disk like anything else, and refused when the disk is
	-- full. Which is exactly what writing it through setData is.
	local _, _, _, phys = CeroSecOS.getNode(state, session, path)
	local fs = CeroSecOS.fsFor(state, phys or path)
	if fs.at ~= "/" then
		local text = historyText(lines, CeroSecOS.MAX_FILE_BYTES)
		return CeroSecOS.setData(state, session, path, text, now) == true
	end

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
-- event is expanded. "!" carries no quoting rule of its own here, so
-- expanding one in the middle of a line would make every exclamation mark a
-- player types a trap.
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
	reason = CeroSecOS.strerror(reason)
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

-- And whether there is a pair of HANDS behind the command, which is the other
-- question and the one a pager has to ask: a `&` job and a crontab line write to
-- a glass and will never have a key pressed at them, while a stage of a pipeline
-- somebody just typed will (see jobHasKeyboard in CeroSecOSVM.lua, which is where
-- the answer is worked out). Same rule as above: false only when the shell said
-- so, so a bench calling straight in is a person standing at the keyboard.
--
-- On CeroSecOS rather than local to this file: `mail` reads its input the same
-- way and lives with the mailbox (CeroSecOSCron.lua), and a second copy of a
-- rule about standard input is a second answer to it. The file-local names below
-- are kept so that no call site here had to change.
function CeroSecOS.shKeys(sh)
	if type(sh) ~= "table" then return true end
	return sh.keys ~= false
end
local shKeys = CeroSecOS.shKeys

-- The one usage line there is for a command: the string in COMMAND_INFO. `man
-- ls` prints it and a wrong `ls` prints it, so the two can never drift into
-- saying different things.
local function usage(cmd)
	return false, { cmd .. ": usage: " .. (CeroSecOS.commandUsage(cmd) or cmd) }
end

-- A flag getopt(3) does not know, 4.3BSD's own two lines: "illegal option --
-- x" and then the usage a bad getopt() call always prints right after (see the
-- "getopt" entry above). ch is whatever the caller has at hand for the bad
-- flag -- a whole word like "-z" or a bare letter out of a "-rf" a loop is
-- walking one character at a time -- and the leading dashes are stripped
-- either way, because getopt's own message never carries one.
local function badOption(cmd, ch)
	local letter = string.sub(string.gsub(tostring(ch), "^%-+", ""), 1, 1)
	return false, { cmd .. ": illegal option -- " .. letter,
		"usage: " .. (CeroSecOS.commandUsage(cmd) or cmd) }
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
function CeroSecOS.stdinOf(stdin, paths)
	if #paths > 0 then return nil end
	if type(stdin) ~= "table" then return nil end
	stdin.want = true
	return stdin
end
local stdinOf = CeroSecOS.stdinOf

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
function CeroSecOS.holdLine(carry, line)
	if carry.lines == nil then
		carry.lines = {}
		carry.bytes = 0
	end
	carry.lines[#carry.lines + 1] = line
	carry.bytes = carry.bytes + #line + 1
	return #carry.lines <= CeroSecOS.PIPE_LINES and carry.bytes <= CeroSecOS.PIPE_BYTES
end
local holdLine = CeroSecOS.holdLine

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
-- third edition of Unix: `ls` walks past it and `ls -a` does not. No other
-- command treats it as special when it is TYPED -- `cat .profile` reads it and
-- `edit .sh_history` opens it, because a name given straight is a name and
-- not a pattern. Only a "*" or a "?" the shell expands has to spell the dot
-- to match it (CeroSecOS.expandGlob).
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

-- A link's own long line. It says what it points AT, because that is the whole of
-- what a link is: the size and the date of one are the length of the path in it
-- and the moment it was made, and neither is anything a player is looking for.
-- The columns in front of it are the ordinary ones, so a listing still lines up.
--
--   lrwxrwxrwx  admin  admin  notes -> ../notes.txt
--
-- 10 perm + 2 + 6 owner + 1 + 6 group + 2 = 27, which leaves 33 for the pair. The
-- longest a target may be is far more than that, so it is the TARGET that is cut
-- and the name is kept whole: the name is what a player typed.
local L_LINK = CeroSecOS.COLS - (10 + 2 + L_OWNER + 1 + L_GROUP + 2)

local function linkLine(node, name)
	local head = CeroSecOS.permString(node)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(node.owner or "?", L_OWNER), L_OWNER)
		.. " " .. CeroSecOS.padRight(
			CeroSecOS.truncate(CeroSecOS.groupOf(node), L_GROUP), L_GROUP)
		.. "  "
	return head .. CeroSecOS.truncate(name .. " -> " .. (node.target or ""), L_LINK)
end

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
	-- The dot, which is a word the SHELL is for the plainest reason there is: it
	-- reads a file into the shell standing there, and nothing a program did could
	-- have that effect. sh's since the seventh edition. `source` is csh's name for
	-- it and is not here; the manual's deviations page is where a name that is not
	-- here is said to be missing, and this one never was.
	["."]    = { desc = "read a file in this shell", usage = ". <file>", shell = true },
	-- Two forms and no flag that CHANGES a line, because an Ethernet address here
	-- is derived and stored nowhere: see the head of arp in CeroSecOSNet.lua.
	arp      = { desc = "show the cards on the wire",
		usage = "arp -a | arp <host|address>" },
	-- at(1) and its two other names, which are the same programs under the names
	-- 1993 had them under: atq is `at -l` and atrm is `at -r`, and POSIX.2 gives at
	-- those two flags as well. The commands come from the standard input, which is
	-- at's own rule and on this machine is a pipe -- see the head of commands.at.
	at       = { desc = "run commands once, at a time you name",
		usage = "at HH:MM | at -l | at -r <job>..." },
	atq      = { desc = "list the jobs waiting to run", usage = "atq" },
	atrm     = { desc = "take a waiting job out of the queue", usage = "atrm <job>..." },
	cat      = { desc = "print a file", usage = "cat [-n] [file]..." },
	-- The five words the SHELL is, and so the five with no file in /bin: a
	-- program cannot move the shell that ran it, and cannot own its jobs either
	-- (see CeroSecOS.isShellWord, and the note above CeroSecOS.BUILTINS).
	cd       = { desc = "change the working directory", usage = "cd [dir]", shell = true },
	chgrp    = { desc = "change a file's group", usage = "chgrp <group> <path>" },
	chmod    = { desc = "change a file's mode", usage = "chmod <mode> <path>..." },
	chown    = { desc = "change a file's owner", usage = "chown <user> <path>..." },
	clear    = { desc = "clear the screen", usage = "clear" },
	cp       = { desc = "copy a file or a tree", usage = "cp [-r] <src>... <dst>" },
	crontab  = { desc = "list, edit or drop your crontab", usage = "crontab -e|-l|-r" },
	-- The two forms cut(1) has and they are exclusive: -c cuts characters out of a
	-- line and -f cuts fields out of a record, and a line carrying both is a line
	-- that cannot be carried out.
	cut      = { desc = "cut out selected parts of each line",
		usage = "cut -c <list> | -d <delim> -f <list> [file]..." },
	-- The operand is "telno" and not "<number>": it is cu(1)'s own name for it,
	-- and a usage line is the one place a command speaks the manual's language.
	-- Both of cu's forms, because cu(1) has two: a number to dial, or `-l` and a
	-- LINE to open with whatever is on the end of it. The line on this machine is
	-- the radio, and what answers on it is the TNC (CeroSecOS.tncOpen).
	cu       = { desc = "call another machine, or open a line",
		usage = "cu telno | cu -l line" },
	date     = { desc = "print the date and time", usage = "date [+FORMAT]" },
	dev      = { desc = "list and work the devices",
		usage = "dev [kind|id [value|toggle]|find <id>]" },
	df       = { desc = "report disk space", usage = "df" },
	echo     = { desc = "print its arguments", usage = "echo [text...]" },
	edit     = { desc = "edit a file", usage = "edit <file>" },
	-- POSIX's env with neither of its two other halves: no -i, and no
	-- NAME=value in front of a utility to run. Both of those are about the
	-- environment a PROGRAM is handed, and the shell already has the second --
	-- `NAME=value command` -- while the commands on this machine read nothing
	-- out of an environment but PATH. So what is here is the listing, which is
	-- the half a survivor types, and the manual page says the other two are not.
	env      = { desc = "print the environment", usage = "env" },
	-- A word the shell IS, like cd: it marks which of the SHELL's own variables a
	-- program it runs is handed, and nothing in /bin could reach them.
	export   = { desc = "put a variable in the environment",
		usage = "export NAME[=value]...", shell = true },
	exit     = { desc = "log out", usage = "exit", shell = true },
	-- POSIX.2's grammar, minus `:` -- see the head of commands.expr for why, and
	-- the manual's deviations page for the declaration.
	expr     = { desc = "evaluate an expression", usage = "expr <expression>" },
	fg       = { desc = "bring a background job to the front",
		usage = "fg [%<n>|<id>]", shell = true },
	["false"] = { desc = "do nothing, unsuccessfully", usage = "false" },
	-- POSIX's own subset: the two tests a survivor needs and the action that is
	-- implied when he gives none. No -o, no parentheses, no -exec.
	-- POSIX's own subset, and the synopsis 4.4BSD's find(1) carries: a path and an
	-- EXPRESSION. The expression is the two tests a survivor needs, the action that
	-- is implied when he names none, and the one that runs something -- `-name`,
	-- `-type`, `-print` and `-exec`, in both of -exec's forms. No -o, no
	-- parentheses, no -newer and no -size: the manual page names what is here, and
	-- the whole of what is here fits on it.
	find     = { desc = "walk a tree and print what is in it",
		usage = "find <path>... [expression]" },
	-- A basic regular expression, POSIX.2's: `^ $ . * [...]` and the backslash, and
	-- not `\( \)` or `\{ \}` -- the manual's page names the two that are missing.
	-- `-e` because a pattern that starts with a dash has no other spelling.
	grep     = { desc = "find a pattern in files",
		usage = "grep [-cinv] [-e pattern] [pattern] [file]..." },
	groupadd = { desc = "make a group", usage = "groupadd <name>" },
	groupdel = { desc = "remove a group", usage = "groupdel <name>" },
	groups   = { desc = "print an account's groups", usage = "groups [name]" },
	halt     = { desc = "switch the machine off", usage = "halt" },
	head     = { desc = "print the first lines of a file",
		usage = "head [-n N|-N] [file]" },
	help     = { desc = "list the commands in /bin", usage = "help" },
	hostname = { desc = "print or set the machine's name", usage = "hostname [name]" },
	id       = { desc = "print an account and its groups", usage = "id [name]" },
	ifconfig = { desc = "show the network interfaces",
		usage = "ifconfig [-a|<interface>]" },
	-- The jobs on THIS MACHINE and not "the shell's": four is the ceiling a
	-- machine has, they are shared between every session on it, and `jobs` lists
	-- every one of them whoever started it (see the head of commands.jobs).
	jobs     = { desc = "list the background jobs on this machine",
		usage = "jobs", shell = true },
	kill     = { desc = "stop a job", usage = "kill [-<signal>|-s <signal>] <id>|%<n>" },
	last     = { desc = "list the logins on this machine", usage = "last [name]" },
	-- Symbolic only, and the usage line says so: see the note above
	-- CeroSecOS.newLink for why this machine has no hard links.
	ln       = { desc = "make a symbolic link", usage = "ln -s <target> <name>" },
	ls       = { desc = "list a directory", usage = "ls [-1laACF] [path]..." },
	-- Berkeley Mail's two halves under one name, which is what mail(1) is: no
	-- recipient is reading your own box, and a recipient is sending. The body
	-- comes from the standard input either way -- a pipe, or the terminal until a
	-- line holding a single "." -- because that is where mail has always read it.
	mail     = { desc = "read your mail, or send a message",
		usage = "mail [-f] [-s subject] [user...]" },
	man      = { desc = "describe a command", usage = "man <command>" },
	mkdir    = { desc = "make a directory", usage = "mkdir <dir>" },
	-- CeroSec Systems' own, and the manual's deviations page says so: no Unix of
	-- 1993 shipped a command that hashed a string you chose. The name is the one
	-- the job would have been given -- crypt(3) is the library call and `mkpasswd`
	-- is what a tool that makes one is called.
	mkpasswd = { desc = "hash a string the way a password is",
		usage = "mkpasswd <text> [salt]" },
	more     = { desc = "show a file a screenful at a time", usage = "more [file]..." },
	-- The floppy drive's three. `mount` with nothing after it is the listing, which
	-- is why the whole of its operand half is optional.
	mount    = { desc = "list the filesystems, or mount one",
		usage = "mount [<device> <dir>]" },
	mv       = { desc = "move or rename a file", usage = "mv <src>... <dst>" },
	newfs    = { desc = "put a filesystem on a disk", usage = "newfs <device>" },
	passwd   = { desc = "change a password", usage = "passwd [user]" },
	pwd      = { desc = "print the working directory", usage = "pwd" },
	reboot   = { desc = "restart the machine", usage = "reboot" },
	ping     = { desc = "see whether a machine answers", usage = "ping <host|address>" },
	printf   = { desc = "print a formatted string", usage = "printf <format> [arg...]" },
	ps       = { desc = "list every job on this machine, and its cpu", usage = "ps" },
	rcp      = { desc = "copy a file to or from another machine",
		usage = "rcp <src> <dst>, one is <host|address>:<path>" },
	rlogin   = { desc = "log in on another machine", usage = "rlogin <host|address> [-l user]" },
	rm       = { desc = "remove a file or a directory", usage = "rm [-rf] <path>..." },
	-- 4.4BSD's rmdir(1): a directory that already has nothing in it, or `rm -r`
	-- for one that has not. No -p: see the head of commands.rmdir.
	rmdir    = { desc = "remove an empty directory", usage = "rmdir <dir>..." },
	rsh      = { desc = "run one command on another machine",
		usage = "rsh <host|address> [-l user] <command>..." },
	ruptime  = { desc = "list the machines on the wire", usage = "ruptime" },
	rwho     = { desc = "list who is logged in on them", usage = "rwho" },
	sh       = { desc = "run a script", usage = "sh <file> [args]" },
	shutdown = { desc = "switch the machine off",
		usage = "shutdown [-h|-r] now|+N" },
	sleep    = { desc = "wait for a number of seconds", usage = "sleep <seconds>" },
	sort     = { desc = "sort lines", usage = "sort [-r] [-n] [-u] [file]..." },
	su       = { desc = "become another user", usage = "su [name]" },
	sudo     = { desc = "run a command as root", usage = "sudo <command> [args]" },
	-- The three keys and the one modifier tar(1) had in 1993, called the way tar was
	-- called then: one word of letters, no dash in front of it. No `z` (compress was
	-- a program of its own), no -C and no -p. The CONTAINER is this machine's own
	-- and the deviations page says so -- see the head of commands.tar.
	tar      = { desc = "store files in one archive",
		usage = "tar c|x|t[v]f <archive> [path]..." },
	tail     = { desc = "print the last lines of a file",
		usage = "tail [-n N|-N|+N] [file]" },
	tee      = { desc = "copy the input to the screen and to files",
		usage = "tee [-a] <file>..." },
	test     = { desc = "evaluate an expression", usage = "test <expression>" },
	touch    = { desc = "create a file, or stamp it", usage = "touch <file>..." },
	-- Ranges only. The character classes are POSIX.2's and a survivor types a-z,
	-- so they are what is here -- and the manual says which is missing.
	tr       = { desc = "translate or delete characters",
		usage = "tr [-d] <set1> [<set2>]" },
	-- A word the shell IS, like cd: `type` has to know the shell's own words and
	-- the PATH it looks a name up on, and neither of those is anything a file in
	-- /bin could be handed.
	type     = { desc = "say what a word is", usage = "type <name>", shell = true },
	umount   = { desc = "unmount a filesystem", usage = "umount <dir>" },
	-- No -m: see the head of commands.uname for why.
	uname    = { desc = "print system information", usage = "uname [-asnrv]" },
	uniq     = { desc = "drop repeated lines", usage = "uniq [-c] [file]" },
	uptime   = { desc = "show how long the machine has been up", usage = "uptime" },
	-- The three account commands, under the names System V gave them in 1989 and
	-- Solaris 2 shipped in 1992. The operand is "login" because that is what
	-- useradd(1M), userdel(1M) and usermod(1M) call it, and a usage line is the
	-- one place a command speaks the manual's language.
	useradd  = { desc = "add an account",
		usage = "useradd [-G group[,group...]] login" },
	userdel  = { desc = "remove an account", usage = "userdel [-r] login" },
	-- SVR4's -G SETS the supplementary list: what is on the line is what the
	-- account is in afterwards, and what is not on it is a group it has left. It
	-- is not gpasswd's add-one-drop-one, and the manual page says so.
	usermod  = { desc = "set an account's supplementary groups",
		usage = "usermod -G group[,group...] login" },
	["true"]  = { desc = "do nothing, successfully", usage = "true" },
	w        = { desc = "show who is logged in and what they are doing", usage = "w" },
	-- wall(1), and anybody may: the real one is setgid tty and not setuid root,
	-- because a broadcast is not a privilege. The operand is a file, which is
	-- wall(1)'s own, and with none it reads the standard input -- a pipe here.
	wall     = { desc = "write a line to every terminal", usage = "wall [file]" },
	wait     = { desc = "wait for the background jobs", usage = "wait [id]...", shell = true },
	wc       = { desc = "count lines, words and bytes", usage = "wc [-clw] [file]..." },
	which    = { desc = "find a command on PATH", usage = "which <name>" },
	who      = { desc = "list who is logged in here", usage = "who [am i]" },
	whoami   = { desc = "print the current user", usage = "whoami" },
}

--
-- WHAT IS NOT UNIX HERE
--
-- This machine is a 1993 Unix and everything on it is copied from one: 4.4BSD,
-- SunOS 4, System V Release 4, POSIX.2 of 1992. Nothing is invented -- except
-- the handful of things below, and the rule is that every one of them is
-- DECLARED, in the manual, in the player's own hands, on a page of Volume 1.
--
-- This is that list, and it is what the page is checked against
-- (tests/manual_test.lua): a deviation nobody wrote down is a lie the machine
-- tells, and a page that has quietly lost an entry fails the bench rather than
-- going stale in the reader's hands.
--
-- `name` is the word the page has to carry. `gone` marks a name that is NOT on
-- this machine and is here because a player may have heard of it or seen it on an
-- older one -- the page has to say where it went.
--
-- And `world` marks the third kind: a deviation that is not a COMMAND at all, so
-- there is no /bin file and no COMMAND_INFO entry for the bench to weigh it
-- against. One of those cannot be checked by its name alone -- `login` is a word
-- the page already uses about the login: prompt -- so an entry marked `world`
-- carries the `phrase` the page has to say, literally, and the bench looks for
-- that instead. A sentence is what a reader needs anyway; a word is what a command
-- needs.
--
-- Two more kinds: `shell` is a word of the shell (CeroSecOS.SHELL_BUILTINS)
-- rather than a file, and `absent` is a name a 1993 Unix had and this one has
-- NOT -- no command, no shell word, never retired.
--
-- EVERY entry carries a `phrase`, and is held to it, which is how a
-- declaration is kept from being a word on a page that says nothing about it. It
-- has to fit on ONE line of the page: the pages are wrapped prose and the bench
-- looks for the phrase literally, so a sentence broken across two lines is a
-- sentence it will not find. And the phrase is what the bench reads the page
-- BACK by: a paragraph of the page that holds no entry's phrase is a
-- declaration this list does not have, and goes red (tests/manual_test.lua).
-- Several entries may share one phrase when one sentence declares them all.
--
CeroSecOS.DEVIATIONS = {
	-- Not a Unix command at all. `man -k` and `apropos` are what a real one had,
	-- and both want a whatis database this machine has no room for; what is here
	-- instead is a listing of /bin, which is why a machine whose /bin has been cut
	-- down has a shorter help and one with no /bin cannot describe itself.
	{ name = "help", phrase = "help is not a Unix command",
		why = "no Unix had it; it lists /bin, and man -k wants a database" },
	-- The world, which no Unix of any year had: doors, lights, locks and windows
	-- are under /dev and `dev` is the everyday face of them. Everything it does
	-- goes through the same two calls `cat /dev/light0` and `echo off >
	-- /dev/light0` reach, so it adds a table to read and no power.
	{ name = "dev", phrase = "dev is not one either",
		why = "the building is not something a 1993 Unix had to work" },
	-- CeroSec Systems' own: crypt(3) was the library call and nothing in /bin
	-- wrapped it. It was called `hash` until SYSTEM_VERSION 16, which was not a
	-- name any Unix would have used.
	{ name = "mkpasswd", phrase = "mkpasswd is ours",
		why = "no 1993 tool hashed a string you chose" },
	-- A screen editor under a name 4.3BSD gave to a LINE editor: the real edit(1)
	-- is ex in its friendly mode, one line at a time. This one is a full-screen
	-- buffer with Tab to save and Escape to leave, because a line editor on a
	-- glass a survivor is standing at would be cruelty. vi is what it should be
	-- called and vi is four thousand lines of C.
	{ name = "edit", phrase = "edit is a SCREEN editor",
		why = "a screen editor under 4.3BSD's name for a line editor" },
	-- Real for the year and still not part of Unix: sudo was Bob Coggeshall and
	-- Cliff Spencer's, 1980, passed around by hand and installed by an
	-- administrator who wanted it. So it is on this machine the way it was on a
	-- real one -- an add-on, with /etc/sudoers deciding -- and not as something
	-- the system shipped.
	{ name = "sudo", phrase = "sudo is real for the year",
		why = "an add-on of the era, not part of any Unix" },
	-- The jobs belong to the MACHINE and not to the shell that typed them: one
	-- book per computer, four to a computer, and `jobs` lists every background job
	-- on it whoever started it. On a real Unix a job is a process group the shell
	-- owns. Kept on purpose -- it is what lets a survivor pick up what the last
	-- one left running -- and said plainly instead (see commands.jobs).
	{ name = "jobs", phrase = "jobs lists the background jobs on the MACHINE",
		why = "the jobs are the machine's, not the shell's" },
	-- And the one name that is GONE: `hash` was renamed to mkpasswd, and the page
	-- has to say so, because a player who used it last week will type it.
	{ name = "hash", gone = true, phrase = "It was called hash on this machine",
		why = "renamed mkpasswd at SYSTEM_VERSION 16" },
	-- The pager's keys. more(1) reads the KEY you press; this console has one
	-- input line and Enter is what sends it, so Space is a space and then Enter.
	-- The console's deviation rather than the pager's, and `read -n 1` has had the
	-- same shape since it was written.
	{ name = "more", phrase = "more and read -n want Enter",
		why = "its keys need Enter behind them: the console reads a line" },
	-- The radio's serial line, and the box's own first line. `cu -l line` is
	-- cu(1)'s own flag and the TNC-2 command set behind it is the TNC-2's, so the
	-- two things this machine made up are: the line is a CHARACTER DEVICE naming a
	-- radio (/dev/radio0) where a real cu is handed /dev/ttya and reads
	-- /etc/remote, which this machine has not got; and the banner the box prints
	-- when the line opens, a real TNC-2 having printed whatever its vendor's
	-- firmware printed.
	{ name = "cu", phrase = "cu -l opens a LINE instead of dialling",
		why = "-l names /dev/radio0, and the TNC's banner line is ours" },
	-- The CONTAINER a tar makes, and nothing else about tar: the three keys, the one
	-- modifier, what a member carries and who may put an owner back are all tar's
	-- own. But a real archive is 512-byte blocks with a 512-byte header in front of
	-- every member, and on a machine whose floppy holds 4096 bytes that would cost a
	-- ten-line note a quarter of the disk it was being carried on. So the container
	-- is TEXT -- a header line and the bytes after it -- and it is honest about what
	-- it costs (see the head of commands.tar).
	{ name = "tar", phrase = "the archive is a text file",
		why = "512-byte blocks would cost one note a quarter of the floppy" },
	-- ln, which a 1993 one made a HARD link with: `ln a b` was a second NAME for
	-- one file, and this machine cannot hold one -- two names for one node would
	-- be one table under two keys, and the game copies the state table by
	-- recursion, so the second name would become a second FILE the first time
	-- somebody picked the computer up (the head of CeroSecOS.newLink has it). A
	-- link that quietly stops being a link is worse than no hard links, so -s is
	-- required; the page carries the answer a player gets without it, because a
	-- declaration that does not say what happens is not one.
	{ name = "ln", phrase = "ln: usage: ln -s <target> <name>",
		why = "no hard links: the state is copied by recursion, so the second name" ..
			" would become a second file" },
	-- mail can only reach an account ON THIS MACHINE. A 4.4BSD mail handed
	-- `bob@gate` or `gate!bob` would have tried -- sendmail would have looked the
	-- host up and uucp would have queued the file -- and there is no uucp on this
	-- disk and no mailer behind the wire, so both spellings are refused where they
	-- are typed. The page carries the answer a player gets, because a declaration
	-- that does not say what happens is not one; the wire itself is reached with
	-- `rsh <host> mail <user>`, which is the LAN mail a script writes.
	{ name = "mail", phrase = "Cannot send mail: no mailer",
		why = "no uucp and no mailer on the wire: a remote address is refused" },
	-- Not a command: the one machine in four that is found at somebody's prompt
	-- after the power came back. No Unix can restore a session across a power cut
	-- and this one cannot either -- a survivor's own machine comes back to `login:`
	-- every time. What is deviated from is the STORY the prefilled machines tell:
	-- the console agrees with /var/log/wtmp, which says a man sat down on the
	-- morning of it and never logged out, instead of agreeing with the boot
	-- sequence. It happens once in the life of a machine.
	{ name = "login", world = true,
		phrase = "was never logged out",
		why = "a machine found at a prompt is one wtmp says nobody logged out of" },
	-- Not a command either: the SHELL's two streams. A command on this machine
	-- hands back one list of lines and a flag, so one that half failed -- `cat
	-- good nosuch` -- has its output and its error in the same list and nothing to
	-- tell them apart. The whole of it is taken for the errors: out of what ">"
	-- named, into what "2>" did (CeroSecOSVM's runSimple). A real cat writes the
	-- good file down fd 1 and the complaint down fd 2.
	{ name = "stderr", world = true,
		phrase = "one stream and not two",
		why = "a command that half failed hands back output and errors in one list" },
	-- And the second name that is GONE: `call CALLSIGN` was this machine's own
	-- command for the radio until SYSTEM_VERSION 17. No Unix had one -- a TNC was
	-- a box on a serial line -- and a player who used it last week will type it.
	{ name = "call", gone = true, phrase = "There was a call CALLSIGN command here",
		why = "the TNC is driven with cu -l /dev/radio0 since SYSTEM_VERSION 17" },
	-- Two cuts the sixty columns make: 4.4BSD's uptime prints "load averages:"
	-- and its w prints the weekday a login began.
	{ name = "uptime", phrase = "uptime says \"load\" where 4.4BSD says",
		why = "sixty columns: \"load\" for \"load averages:\"" },
	{ name = "w", phrase = "prints the clock where a real one prints a weekday",
		why = "sixty columns: the clock where a weekday was" },

	-- What is left of the machine's own WORDING, where it is not 1993's. Kept
	-- because each one says plainly what went wrong, and each says why below.
	-- self-test's vectors, and each one says plainly what went wrong.
	--
	-- The words themselves are 1993's now: strerror(3) for a command's
	-- refusal (CeroSecOS.STRERROR), getopt(3)'s two lines for a flag,
	-- sh's own lower-case table for what sh says (CeroSecOS.sherror,
	-- .execError, .cannotCreate), synerror()'s "Syntax error:", su's
	-- "Sorry" and login's "Login incorrect". What is left is below.
	--
	-- An open quote, or a line that ends in | or &&, is a line sh waited
	-- for (PS2, bin/sh/parser.c); this parser has one line and refuses it.
	{ name = "syntax", world = true,
		phrase = "a quote left open is refused",
		why = "one typing line: no PS2 continuation, so the line is refused" },
	-- Reasons kept in this machine's own words: a device and a name with
	-- characters the disk will not keep, which no errno named, and a file
	-- that grows past its size at a ">", where sh's errormsg[] had no row
	-- for EFBIG and printed "error 27" (a command says File too large).
	{ name = "errno", world = true,
		phrase = "is a device, invalid characters and file too large",
		why = "no errno, or no word in sh's table, so the machine's own" },
	-- 4.4BSD sh's error() signs with commandname: nothing at the prompt,
	-- the script's name inside a script, and no line number. This one signs
	-- its own run-time errors "sh:" at the prompt and "name: line N:" in a
	-- file, and a redirect it cannot open is never signed.
	{ name = "sh",
		phrase = "signs its own complaints sh:",
		why = "a run-time error names the shell and the line a script stopped on" },
	-- sudo's own wrong-password line is not pinned down the way su's and
	-- passwd's are: the 1980s sudo that would have been on a 1993 machine is
	-- not in circulation to read, and "it probably said X" is exactly the
	-- guess CONTRIBUTING.md refuses. Kept until a real source turns up.
	{ name = "sudo", phrase = "authentication failure",
		why = "sudo's own wrong-password wording has no source to check it against" },

	-- The FILES and the SHELL. (A file's last line used to have no "\n"
	-- after it, and IFS used to be an ordinary name; both are real
	-- since 0.7.0 and those deviations are gone.)
	-- One > (or >>) and one 2> per command, and < is refused by the lexer
	-- (CeroSecOSScript: "redirection unexpected"). sh took any number of each.
	{ name = "redirect", world = true,
		phrase = "One > and one 2> to a command, and no <",
		why = "a command has one output, one error and no input redirect" },
	-- System V sh's :- := :? :+ and ksh88's ${#x} and #/##/%/%% read
	-- inside braces (readDollar's "{" arm, CeroSecOSScript.lua); what is
	-- refused is a SECOND substitution inside the word or the pattern --
	-- a $( ), a backquote or another ${x:-y} -- one level deep, the same
	-- ceiling a catch inside a catch already meets (readCommandSub).
	{ name = "braces", world = true,
		phrase = "the ceiling a catch inside a catch already has",
		why = "the word after :- := :? :+ # ## % %% may hold no second substitution" },
	-- CeroSecOS.MAX_TRIM_ITEMS: a trim walks the value once per piece of
	-- its pattern (CeroSecOSVM's trimRun), and ksh88 had no such ceiling.
	{ name = "braces", world = true, phrase = "A pattern is at most 32 pieces",
		why = "a trim costs a walk of the value per piece, like grep's pattern" },
	-- read's flags are bash's (2.0 for -n): in ksh88 -p read from the
	-- co-process and -s saved the line to the history file.
	{ name = "read", shell = true, phrase = "read -p, read -s and read -n",
		why = "-p prompts, -s hides, -n counts: bash's, not ksh88's" },
	-- ksh88 had fc and r; !! and !n are csh's, and history -c is bash's.
	{ name = "history", shell = true, phrase = "!!, !n and history -c are csh's",
		why = "csh's and bash's history words, not sh's or ksh88's" },
	-- A stage whose reader is over is stopped once it has run a command,
	-- written or not (CeroSecOSVM's pipeline stepper, stage.ran). A real
	-- sh runs every stage to its end; write(2) raises SIGPIPE only on the
	-- next write into the closed pipe (pipe(7)). So `{ echo a > f; echo b
	-- > g; } | true` never makes g, and `sleep 5 | true` ends at once.
	{ name = "pipe", world = true,
		phrase = "A stage of a pipe stops as soon as the command reading it",
		why = "a stage is stopped when its reader ends, not on its next write" },
	-- sh(1) took -c and a command string; commands.sh takes a file only.
	{ name = "sh", phrase = "sh -c is not here",
		why = "sh runs a script file, never a string" },

	-- ACCOUNTS. /etc/passwd is name:hash:home:flag, root's, mode 600
	-- (CeroSecOS.passwdLine); a 1993 one was seven fields at mode 644 with the
	-- hash in master.passwd (4.4BSD) or /etc/shadow (SVR4).
	{ name = "shadow", world = true, phrase = "/etc/passwd has four fields",
		why = "four fields and the hash, at mode 600: no uids to hide behind" },
	-- There are no numeric ids to print.
	{ name = "id", phrase = "id prints uid=admin flag=user",
		why = "names and a flag, because there are no numbers" },
	-- SCeroSecSystem:promptFor hands consolePrompt isAdmin(): the admin FLAG,
	-- where sh gave "#" to uid 0 alone.
	{ name = "prompt", world = true,
		phrase = "Any account with the admin flag gets the # prompt",
		why = "the flag, not uid 0, earns the #" },
	-- The screen is rows, never a cursor: a job's last line with no "\n"
	-- behind it (outLine's partial) still lands as a row of its own on
	-- console.lines, the typed line is pushed as prompt .. line on a row of
	-- its own (SCeroSecSystem, the three consolePush calls of the Enter
	-- path), and the window draws the prompt on the row after the last one
	-- (CeroSecTerminal:inputRow). A tty put it at the cursor: `printf a`
	-- then the prompt read "a$ ".
	{ name = "prompt", world = true,
		phrase = "the prompt starts on the next row",
		why = "the glass is a list of rows and the prompt takes its own" },

	-- What is not HERE. ls /bin is the whole list of programs, and the page
	-- says so; these are named because a script reaches for them first.
	-- `absent` marks a name that is neither a command, a word of the shell
	-- nor a retired one.
	-- builtins.set (CeroSecOSVM.lua) refuses -e, -x and -u: nothing here
	-- traces a script, stops it on a failed command, or flags an unset
	-- variable, and claiming one of those turned on would be a lie.
	{ name = "set", shell = true, phrase = "set has no -e, -x or -u",
		why = "nothing here traces a script, stops on failure or flags an unset variable" },
	-- Every way a job is ended goes through CeroSecOS.killJob, on the spot:
	-- SIGKILL, which no trap catches (builtins.trap, CeroSecOSVM.lua). And
	-- jobError ends the job without the trap, where sh ran it on its way out.
	{ name = "trap", shell = true, phrase = "trap catches EXIT and nothing else",
		why = "kill, Escape and the cpu ceiling end a job outright" },
	-- A typed line is a job of its own (CeroSecOS.promptJob): the console
	-- keeps its variables, exports and functions and nothing else, so $1..,
	-- a trap, and what exec replaces are the line's.
	{ name = "set", shell = true, phrase = "each line is a shell of its own",
		why = "a typed line is a job; the console keeps variables, not $1.. or traps" },
	{ name = "exec", shell = true, phrase = "exec ends the line, not the login",
		why = "the shell exec would replace is the line's job" },
	-- runSimple refuses it: a redirect here is opened for one command.
	{ name = "exec", shell = true, phrase = "file with no command is refused",
		why = "a redirect belongs to one command and ends with it" },
	-- expr has arithmetic and comparison now, but no : -- the manual's own
	-- words say why (a matcher that only answers whether, never where).
	{ name = "expr", phrase = "expr has no :",
		why = "the matcher grep uses cannot hand back where a match ended" },
	-- No -m: see the head of commands.uname for why.
	{ name = "uname", phrase = "uname has no -m",
		why = "no hardware name was ever put in this machine to print" },
	-- kill honours the five signals whose default action ends a job outright,
	-- and refuses the rest by name -- STOP and CONT among them, since nothing
	-- here can pause or resume a job the way a real process can be.
	{ name = "kill", phrase = "kill -9 and kill -s KILL, TERM, HUP, INT or QUIT end a job",
		why = "STOP and CONT are refused: a job cannot be paused and resumed here" },
	-- CeroSecOS.printfText knows %s, %c, %d, %x, %o and %%, with a width, a
	-- precision and the "-" and "0" flags, but no %f; and its \NNN makes no
	-- control byte (printfPass), where printf.c stored whatever byte it named.
	{ name = "printf", phrase = "printf has no %f",
		why = "no floating point conversion is trusted here, and no control byte" },
	-- 4.4BSD's bin/ls/print.c printlong: "%s %*u %-*s  %-*s  " -- the mode, the
	-- link count, owner and group. longLine has no count: sixty columns hold
	-- the name or the count, and it keeps the name.
	{ name = "ls", phrase = "ls -l has no link count",
		why = "the column is the name's on a sixty-column screen" },
	-- 4.4BSD's bin/date/date.c: its default format puts the zone, %Z,
	-- before the year. The world's clock carries no zone, and nothing on
	-- the machine sets TZ.
	{ name = "date", phrase = "date prints no time zone",
		why = "no zone was ever set on this machine" },
	-- CeroSecOS.saveBytes: a buffer of exactly MAX_FILE_BYTES is saved with
	-- no final newline, where nvi (4.4BSD-Lite2 contrib, ex/ex_write.c)
	-- always wrote one; the message is vi 3.7's (4.3BSD ucb/ex/ex_io.c).
	{ name = "edit", phrase = "saves a file of 4096 bytes without its last newline",
		why = "the newline would carry the file past the ceiling" },
}

--
-- What this build TOOK AWAY
--
-- A name that was in the table above and is not any more, with the description
-- the file in /bin shipped with. A machine saved before the change has that
-- file, and `ls /bin` on it would still offer a command nothing is behind: the
-- top-up deletes it (see CeroSecOS.upgradeSystem), and only where it is exactly
-- what was shipped -- owner root, mode 755, that very description. Anything else
-- at that name is a player's own work and stays.
--
-- The same mechanism, and the same rule, that took /bin/cd and /bin/exit away
-- when those became words of the shell. What is different is only the reason:
-- these are names 1993 did not have.
--
--   useradd, userdel, usermod  the System V names, 1989
--   mkpasswd                   the old `hash`, renamed
--   echo ... > file            the old `write`. The real write(1) MESSAGES another
--                              account; putting text in a file has always been a
--                              redirection, and this machine has had one all along
--   ln -s, and `ls -l`         the old `readlink`, which is 1997 -- a decade late.
--                              What a link points at is in the arrow `ls -l` draws
--   reboot, shutdown -r        the old `restart`, which was invented here
--   cu -l /dev/radio0          the old `call`, which was invented here too: a TNC
--                              was a peripheral on a serial line, and the way to
--                              a serial line is cu(1)
--
CeroSecOS.RETIRED_BIN = {
	adduser  = "add an account",
	call     = "call another machine on the radio",
	deluser  = "remove an account",
	gpasswd  = "add or drop a group member",
	hash     = "hash a string the way a password is",
	readlink = "print what a link points at",
	restart  = "restart the machine",
	write    = "write a line into a file",
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
CeroSecOS.HELP_RESERVED = "if then elif else fi for while until do done case esac"
CeroSecOS.HELP_BUILTINS =
	"cd . export exit fg jobs wait read shift break continue history type" ..
	" set unset exec trap"

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
	-- Wrapped at the screen's width rather than trusted to fit it. The list grew
	-- past sixty columns the day `export` and `.` joined it, and a line that does
	-- not fit is a line the screen CUTS -- so the words are laid out here, where
	-- their number is known, instead of being counted by hand every time one is
	-- added.
	local words = {}
	for word in string.gmatch(CeroSecOS.HELP_RESERVED .. " " .. CeroSecOS.HELP_BUILTINS,
			"[^ ]+") do
		words[#words + 1] = word
	end
	local line = ""
	for i = 1, #words do
		if line == "" then
			line = " " .. words[i]
		elseif #line + 1 + #words[i] <= CeroSecOS.COLS then
			line = line .. " " .. words[i]
		else
			out[#out + 1] = line
			line = " " .. words[i]
		end
	end
	if line ~= "" then out[#out + 1] = line end
	return true, out
end

commands.pwd = function(state, session, args, env)
	if #args > 1 then return usage("pwd") end
	return true, { session.cwd }
end

-- env: the environment, one NAME=value a line.
--
-- The environment is not the shell's variables: it is the ones that have been
-- exported, which is the set a program run from that shell is handed (see the
-- variables section of CeroSecOSVM.lua). So `x=5; env` does not show x and
-- `export x; env` does, which is the whole of what this command is for -- it
-- answers the question "what will a script of mine actually see".
--
-- A real env(1) prints its own environment, which it was handed at exec. This one
-- asks the shell for it through the one door a command has (CeroSecOS.jobOf) --
-- there is no exec here to carry a copy in -- and nil is an empty environment,
-- which is the honest answer for an env run with no shell around it at all.
--
-- Sorted, because pairs is not an order: a listing that came back differently
-- every time could not be a page of the manual.
commands.env = function(state, session, args, env)
	if #args > 1 then return usage("env") end
	local job = CeroSecOS.jobOf(env)
	if job == nil then return true, {} end
	local names = CeroSecOS.envNames(job.vars, job.exported)
	local out = {}
	for i = 1, #names do out[#out + 1] = names[i] .. "=" .. job.vars[names[i]] end
	return true, out
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

-- uname [-amnrsv], 4.4BSD-Lite2's usr.bin/uname/uname.c: getopt on
-- "amnrsv", no operand, and the fields always printed in one order whatever
-- order the flags came in -- sysname, nodename, release, version, machine,
-- each read by sysctl (kern.ostype, kern.hostname, kern.osrelease,
-- kern.version, hw.machine) and joined by one blank. No flag at all is -s.
--
-- sysname is CeroSecOS.issueText's own words for this machine, "CeroSec OS";
-- nodename is CeroSecOS.hostname, the same name `hostname` prints; release is
-- CeroSecOS.VERSION, the number on the box; version is the build under it,
-- SYSTEM_VERSION, the same number upgradeSystem reads to know a save is
-- behind. -m is not here: nothing on this machine ever named the hardware
-- under it the way struct utsname's machine field would, and inventing one
-- would be answering with a chip nobody ever put in this box.
local UNAME_FLAGS = { a = true, s = true, n = true, r = true, v = true }
commands.uname = function(state, session, args, env)
	local want, any = {}, false
	for i = 2, #args do
		local a = args[i]
		if string.sub(a, 1, 1) ~= "-" or a == "-" then return usage("uname") end
		for c = 2, #a do
			local flag = string.sub(a, c, c)
			if UNAME_FLAGS[flag] == nil then return badOption("uname", flag) end
			want[flag] = true
			any = true
		end
	end
	if not any then want.s = true end
	if want.a then want.s, want.n, want.r, want.v = true, true, true, true end

	local sysname = "CeroSec OS"
	local nodename = CeroSecOS.hostname(state)
	local release = CeroSecOS.VERSION
	local version = "SYSTEM_VERSION " .. tostring(CeroSecOS.SYSTEM_VERSION)

	local fields = {}
	if want.s then fields[#fields + 1] = sysname end
	if want.n then fields[#fields + 1] = nodename end
	if want.r then fields[#fields + 1] = release end
	if want.v then fields[#fields + 1] = version end
	return true, { table.concat(fields, " ") }
end

-- expr(1), POSIX.2's own grammar (the same one 4.4BSD's V7-descended expr
-- carries): lowest to highest, ARG | ARG, ARG & ARG, the six comparisons,
-- + -, then * / %, and ( EXPR ) to override any of it. Read a token at a
-- time off args, never through Lua's pattern matcher (docs/SECURITY.md).
--
-- Not here: `:` against a pattern, `match`, `substr`, `index` and `length`.
-- A bare `:` wants a matcher that can hand back where a match ENDED, and
-- CeroSecOS.breMatch above answers only whether one exists (see its own
-- head comment) -- built that way on purpose, so an anchored walk never
-- pays for remembering a position nothing here needed until now. Teaching
-- it to also could only be done straight against Kahlua's own strings, so
-- it stays undone rather than reached for with string.find on a player's
-- own pattern. Declared on the manual's deviations page.
--
-- Exit status is expr(1)'s own: 0 when the value is neither empty nor "0",
-- 1 when it is, 2 for anything that stopped it. The words are 4.4BSD's
-- bin/expr/expr.y (the 1993 CSRG tree), whose yyerror prints the message
-- bare, with no "expr:" in front, and exits 2: yacc's "syntax error",
-- "non-numeric argument", "Divide by zero" and "Remainder by zero". A
-- bracket nested past EXPR_DEPTH is yaccpar's own "yacc stack overflow",
-- which is where a real parser's state stack ran out too -- and what keeps
-- a script full of \( from walking the Lua stack down.
local exprOr, exprAnd, exprRel, exprAdd, exprMul, exprPrimary
local EXPR_DEPTH = 32
local exprDepth = 0

local function exprIsInt(s)
	return string.match(s, "^%-?%d+$") ~= nil
end

-- Truncated toward zero, the way C's / and % (and so expr(1)'s) work --
-- floor would answer -1 for -7 / 2 where C and expr both say -3.
local function exprDiv(a, b)
	local q = a / b
	if q < 0 then return -math.floor(-q) end
	return math.floor(q)
end

local function exprCompare(op, a, b)
	local na, nb = nil, nil
	if exprIsInt(a) and exprIsInt(b) then na, nb = tonumber(a), tonumber(b) end
	local x, y = na or a, nb or b
	if op == "=" then return x == y end
	if op == "!=" then return x ~= y end
	if op == "<" then return x < y end
	if op == "<=" then return x <= y end
	if op == ">" then return x > y end
	return x >= y
end

exprPrimary = function(t, i, hi)
	if i > hi then return nil, "syntax error", i end
	if t[i] == "(" then
		if exprDepth >= EXPR_DEPTH then return nil, "yacc stack overflow", i end
		exprDepth = exprDepth + 1
		local v, err, ni = exprOr(t, i + 1, hi)
		exprDepth = exprDepth - 1
		if err ~= nil then return nil, err, ni end
		if t[ni] ~= ")" then return nil, "syntax error", ni end
		return v, nil, ni + 1
	end
	return t[i], nil, i + 1
end

exprMul = function(t, i, hi)
	local v, err, ni = exprPrimary(t, i, hi)
	if err ~= nil then return nil, err, ni end
	while t[ni] == "*" or t[ni] == "/" or t[ni] == "%" do
		local op = t[ni]
		local w, werr, nj = exprPrimary(t, ni + 1, hi)
		if werr ~= nil then return nil, werr, nj end
		if not exprIsInt(v) or not exprIsInt(w) then
			return nil, "non-numeric argument", nj
		end
		local a, b = tonumber(v), tonumber(w)
		if op == "*" then
			v = tostring(math.floor(a * b))
		else
			if b == 0 and op == "/" then return nil, "Divide by zero", nj end
			if b == 0 then return nil, "Remainder by zero", nj end
			if op == "/" then v = tostring(exprDiv(a, b))
			else v = tostring(math.floor(a - exprDiv(a, b) * b)) end
		end
		ni = nj
	end
	return v, nil, ni
end

exprAdd = function(t, i, hi)
	local v, err, ni = exprMul(t, i, hi)
	if err ~= nil then return nil, err, ni end
	while t[ni] == "+" or t[ni] == "-" do
		local op = t[ni]
		local w, werr, nj = exprMul(t, ni + 1, hi)
		if werr ~= nil then return nil, werr, nj end
		if not exprIsInt(v) or not exprIsInt(w) then
			return nil, "non-numeric argument", nj
		end
		local a, b = tonumber(v), tonumber(w)
		if op == "+" then v = tostring(math.floor(a + b)) else v = tostring(math.floor(a - b)) end
		ni = nj
	end
	return v, nil, ni
end

local EXPR_REL = { ["="] = true, ["!="] = true, ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }
exprRel = function(t, i, hi)
	local v, err, ni = exprAdd(t, i, hi)
	if err ~= nil then return nil, err, ni end
	while EXPR_REL[t[ni]] do
		local op = t[ni]
		local w, werr, nj = exprAdd(t, ni + 1, hi)
		if werr ~= nil then return nil, werr, nj end
		v = exprCompare(op, v, w) and "1" or "0"
		ni = nj
	end
	return v, nil, ni
end

exprAnd = function(t, i, hi)
	local v, err, ni = exprRel(t, i, hi)
	if err ~= nil then return nil, err, ni end
	while t[ni] == "&" do
		local w, werr, nj = exprRel(t, ni + 1, hi)
		if werr ~= nil then return nil, werr, nj end
		if v == "" or v == "0" or w == "" or w == "0" then v = "0" end
		ni = nj
	end
	return v, nil, ni
end

exprOr = function(t, i, hi)
	local v, err, ni = exprAnd(t, i, hi)
	if err ~= nil then return nil, err, ni end
	while t[ni] == "|" do
		local w, werr, nj = exprAnd(t, ni + 1, hi)
		if werr ~= nil then return nil, werr, nj end
		if v == "" or v == "0" then v = w end
		ni = nj
	end
	return v, nil, ni
end

commands.expr = function(state, session, args, env, stdin, sh)
	-- No operand at all is a grammar with nothing to parse: yacc's
	-- "syntax error" and 2, the same as any other malformed line.
	local v, err, ni = nil, "syntax error", 2
	exprDepth = 0
	if #args >= 2 then v, err, ni = exprOr(args, 2, #args) end
	if err == nil and ni ~= #args + 1 then err = "syntax error" end
	if err ~= nil then
		if type(sh) == "table" then sh.status = 2 end
		return false, { err }
	end
	local falsy = (v == "" or v == "0")
	if falsy and type(sh) == "table" then sh.outOnFail = true end
	return not falsy, { v }
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
	-- One refusal for every way in which the directory is not there to go
	-- into: 4.4BSD-Lite2 bin/sh/cd.c cdcmd tries each CDPATH candidate that
	-- stat(2)s as a directory, and when none of them docd()s -- missing, a
	-- file, no x -- falls through to error("can't cd to %s", dest), which
	-- error.c signs with the builtin's name.
	local node, _, abs = CeroSecOS.getNode(state, session, target)
	if node == nil or node.type ~= "dir" or not CeroSecOS.can(state, session, node, "x") then
		return false, { "cd: can't cd to " .. target }
	end
	session.cwd = abs
	return true, {}
end

--
-- ls, and who is reading it
--
-- Columns are for a PERSON. The moment the output is going anywhere else -- down
-- a pipe, into a $( ), into a file -- ls prints one name per line, which is what
-- every ls has done since it learned to ask isatty, and which is the difference
-- between
--
--   for l in $(ls /dev | grep light); do ...
--
-- picking out the lights and picking out whatever else happened to share a row
-- with them. The shell is what knows whether there is a screen on the other end
-- and says so (see the `tty` half of what a command is handed).
--
-- Either way can be asked for outright: -1 is one per line and -C is columns,
-- the later of the two winning, exactly as -a and -A already do here. -l is one
-- per line by its nature and neither flag has anything to say about it.
-- One directory's listing, as lines, before any columns are made of them.
-- nil plus the refusal when it cannot be read.
local function lsDir(state, session, node, shown, o)
	if not CeroSecOS.can(state, session, node, "r") then
		return nil, "ls: " .. shown .. ": Permission denied"
	end

	-- One array of what is being listed, so the long form and the columns are
	-- looking at the same thing. "." and ".." are not children of anything --
	-- they are the directory itself and the one above it -- so they are put in
	-- here rather than found by walking, and they sort first because "." is
	-- ahead of every letter in the character order childNames sorts by.
	local entries = {}
	if o.dots then
		entries[#entries + 1] = { name = ".", node = node }
		local up = CeroSecOS.getNode(state, session, shown .. "/..")
		if up ~= nil then entries[#entries + 1] = { name = "..", node = up } end
	end
	local names = CeroSecOS.listedNames(node, o.hiddenToo)
	for i = 1, #names do
		entries[#entries + 1] = { name = names[i], node = node.children[names[i]] }
	end

	local out = {}
	for i = 1, #entries do
		local child = entries[i].node
		local label = entries[i].name
		if o.classify and child.type == "dir" then label = label .. "/" end
		-- A link wears "@", the way it has since 4.2BSD: it is not a directory and
		-- it is not an ordinary file, and which of the two it POINTS at is not
		-- something a one-character mark should be asked to say.
		if o.classify and CeroSecOS.isLink(child) then label = label .. "@" end
		if o.long then
			-- A device has no size and no date; what stands in those columns is
			-- what it is and what it is doing (CeroSecOS.devLine).
			if CeroSecOS.isDev(child) then
				out[#out + 1] = CeroSecOS.devLine(child)
			elseif CeroSecOS.isLink(child) then
				out[#out + 1] = linkLine(child, label)
			else
				out[#out + 1] = longLine(child, label)
			end
		else
			out[#out + 1] = label
		end
	end
	return out
end

-- ls [-lFaA1C] [path]... -- as many operands as the line holds. 4.4BSD ls.c and
-- the System V one both answer in the same order: the names that could not be
-- found, then every operand that is not a directory, as ONE group and printed
-- as it was typed (`ls /etc/passwd` is /etc/passwd, not passwd), then each
-- directory's contents, under its own name and a colon when there was more
-- than one operand to tell apart, a blank line between. Each group in the
-- character order childNames sorts a listing by.
commands.ls = function(state, session, args, env, stdin, sh)
	-- Flags are letters, so "-lF", "-Fl" and "-l -F" are the same line. A bare
	-- "-" is not a flag and never was: it is a name, and a name is what the
	-- error about it should be about.
	-- -a is everything, the two directory entries included; -A is everything
	-- except those two. The later of the two wins, which is how a real ls reads
	-- a line that carries both.
	local o = { long = false, classify = false, dots = false, hiddenToo = false }
	local paths = {}
	-- nil until the line says: a line that says neither is answered by whether
	-- there is a screen there.
	local columns = nil
	for i = 2, #args do
		local a = args[i]
		if string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				local flag = string.sub(a, c, c)
				if flag == "l" then
					o.long = true
				elseif flag == "F" then
					o.classify = true
				elseif flag == "a" then
					o.dots, o.hiddenToo = true, true
				elseif flag == "A" then
					o.dots, o.hiddenToo = false, true
				elseif flag == "1" then
					columns = false
				elseif flag == "C" then
					columns = true
				else
					return badOption("ls", flag)
				end
			end
		else
			paths[#paths + 1] = a
		end
	end
	-- Columns when there is somebody to read them, one name a line when there is
	-- not -- unless the line said which, in which case it said which.
	if columns == nil then columns = shTty(sh) end
	local function shape(lines)
		if o.long or not columns then return lines end
		return CeroSecOS.columnize(lines, CeroSecOS.COLS)
	end

	local many = #paths > 1
	if #paths == 0 then paths[1] = false end
	local errs, files, dirs = {}, {}, {}
	for i = 1, #paths do
		local path = paths[i] or nil
		local shown = path or "."
		-- A link NAMED on the line is followed, so `ls linkdir` lists the directory
		-- it points at. -l and -F are the two flags that ask about the link ITSELF
		-- -- POSIX says so, and it is what they are for: one draws the arrow, the
		-- other marks the at-sign. The children of a directory are never followed.
		local node, reason = CeroSecOS.getNode(state, session, path, o.long or o.classify)
		-- A device that is not there is not listed inside /dev either, so naming
		-- it straight gets the same answer a listing gives.
		if node ~= nil and node.type ~= "dir" and node.dead then
			node, reason = nil, "no such file"
		end
		if node == nil then
			errs[#errs + 1] = "ls: " .. shown .. ": " .. CeroSecOS.strerror(reason)
		elseif node.type ~= "dir" then
			files[#files + 1] = { name = shown, node = node }
		else
			dirs[#dirs + 1] = { name = shown, node = node }
		end
	end
	local function byName(x, y) return x.name < y.name end
	table.sort(errs)
	table.sort(files, byName)
	table.sort(dirs, byName)

	local out, ok = {}, #errs == 0
	for i = 1, #errs do out[#out + 1] = errs[i] end
	local group = {}
	for i = 1, #files do
		local node, name = files[i].node, files[i].name
		if o.long then
			if CeroSecOS.isDev(node) then
				group[#group + 1] = CeroSecOS.devLine(node)
			elseif CeroSecOS.isLink(node) then
				group[#group + 1] = linkLine(node, name)
			else
				group[#group + 1] = longLine(node, name)
			end
		else
			if o.classify and CeroSecOS.isLink(node) then name = name .. "@" end
			group[#group + 1] = CeroSecOS.truncate(name, CeroSecOS.COLS)
		end
	end
	local said = #files > 0
	group = shape(group)
	for i = 1, #group do out[#out + 1] = group[i] end
	for i = 1, #dirs do
		local lines, refusal = lsDir(state, session, dirs[i].node, dirs[i].name, o)
		if lines == nil then
			ok = false
			out[#out + 1] = refusal
		else
			if many then
				if said then out[#out + 1] = "" end
				out[#out + 1] = dirs[i].name .. ":"
			end
			lines = shape(lines)
			for k = 1, #lines do out[#out + 1] = lines[k] end
			said = true
		end
	end
	return ok, out
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

-- touch(1) took any number of names, one line of arguments and one file each
-- (4.4BSD's touch.c: `while (*argv) { ... argv++; }`), each answered on its
-- own -- a name that failed does not stop the ones after it, only the exit
-- status the line as a whole ends with.
local function touchOne(state, session, path, now)
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node == nil and underDev(session, path) then return devReadOnly() end
	if node ~= nil then
		if node.type ~= "file" then return fail("touch", path, CeroSecOS.notAFile(node)) end
		-- Moving a timestamp is a write: a file you may not write is a file you
		-- may not stamp, which is what a real touch says too. On a machine with
		-- no clock there is nothing to move and the file is left alone.
		if not CeroSecOS.can(state, session, node, "w") then
			return fail("touch", path, "permission denied")
		end
		if now ~= nil then node.mtime = now end
		return true, {}
	end
	if reason ~= "no such file" then return fail("touch", path, reason) end
	local file = CeroSecOS.newFile(CeroSecOS.userOf(session), 644, "")
	local created, creason = CeroSecOS.createNode(state, session, path, file, now)
	if created == nil then return fail("touch", path, creason) end
	return true, {}
end

commands.touch = function(state, session, args, env)
	if #args < 2 then return usage("touch") end
	local now = CeroSecOS.clockOf(env)
	local out, ok = {}, true
	for i = 2, #args do
		local done, lines = touchOne(state, session, args[i], now)
		if not done then
			ok = false
			for k = 1, #lines do out[#out + 1] = lines[k] end
		end
	end
	return ok, out
end

-- cat [-n] [file]... -- and "-" among the files is the standard input, read
-- at that place in the line (POSIX.2 cat; 4.4BSD cat.c's `if (*argv == "-")
-- fp = stdin`), so `echo head | cat - body` puts the pipe's line on top. -n is
-- cat.c's: every output line numbered, "%6d\t", the count running on across
-- every file of the line.
--
-- The pipe may arrive over several turns (CeroSecOS.stdinOf), so where the
-- line has got to is kept in `carry`: which operand is next, the count, and
-- whether one failed. A file before the "-" is printed once, on the first
-- turn, and the ones after it on the turn the pipe ends. With no pipe at all
-- "-" reads end of file straight away, as a background job's and a cron
-- line's input already does.
commands.cat = function(state, session, args, env, stdin)
	local number, paths, ended = false, {}, false
	for i = 2, #args do
		local a = args[i]
		-- Only before the first operand, and never "-", which is a name for
		-- the standard input and not a flag. "--" ends them, as getopt(3)
		-- ends them for cat.c: `cat -- -n` reads -n as a file's name.
		if #paths == 0 and not ended and a == "--" then
			ended = true
		elseif #paths == 0 and not ended and a ~= "-" and string.sub(a, 1, 1) == "-" then
			for c = 2, #a do
				if string.sub(a, c, c) ~= "n" then return badOption("cat", string.sub(a, c, c)) end
			end
			number = true
		else
			paths[#paths + 1] = a
		end
	end
	-- With no file, the pipe: `grep on /dev/null | cat` is cat copying its
	-- standard input, which is the whole of what cat has ever done.
	if #paths == 0 then
		if type(stdin) ~= "table" then return usage("cat") end
		paths[1] = "-"
	end
	local reads = false
	for i = 1, #paths do
		if paths[i] == "-" then reads = true end
	end
	local input, carry = nil, {}
	if reads and type(stdin) == "table" then
		input = stdin
		input.want = true
		if type(input.carry) == "table" then carry = input.carry end
	end
	if carry.pos == nil then carry.pos = 1 end
	if carry.n == nil then carry.n = 0 end

	local out = {}
	-- Whatever cat read LAST in this call decides whether its own output ends
	-- open: a file (or a drained pipe) with no final newline behind it is
	-- cat's own last line with none either, which is what lets `cat noeol`
	-- and `cat noeol | cat` print the same missing newline a real one does.
	local lastOpen = false
	-- And while the last source's last line is open, the next line cat reads
	-- is the REST of it: cat copies bytes, so `cat noeol f` prints the two
	-- glued together, exactly as a real one does (cat(1), 4.4BSD: the files
	-- are "read sequentially" onto the standard output and nothing between).
	local glue = false
	local function put(line)
		if glue and #out > 0 then
			out[#out] = out[#out] .. line
			glue = false
			return
		end
		glue = false
		if number then
			carry.n = carry.n + 1
			local num = tostring(carry.n)
			if #num < 6 then num = string.rep(" ", 6 - #num) .. num end
			line = num .. "\t" .. line
		end
		out[#out + 1] = line
	end
	while carry.pos <= #paths do
		local p = paths[carry.pos]
		if p == "-" then
			-- A second "-" finds the pipe already at its end, as cat.c's second
			-- read of stdin does.
			if input ~= nil and not carry.drained then
				for j = 1, #input.lines do put(input.lines[j]) end
				-- Not at the end of the pipe yet: the rest of the line waits
				-- for the turn that is. An open line not yet glued to anything
				-- is left open, and the VM glues what comes next onto it.
				if not input.eof then
					if glue and #out > 0 then out.open = true end
					return not carry.bad, out
				end
				carry.drained = true
				lastOpen = input.open == true
				glue = lastOpen
			end
		else
			local node, reason = CeroSecOS.getNode(state, session, p)
			if node == nil then
				carry.bad = true
				glue, lastOpen = false, false
				out[#out + 1] = "cat: " .. p .. ": " .. CeroSecOS.strerror(reason)
			elseif CeroSecOS.isDev(node) then
				-- A device answers with its state, and refuses in its OWN name:
				-- what a player is being told about is the light switch, not the
				-- command he reached it with.
				local text, refusal = CeroSecOS.devRead(state, session, node)
				if text == nil then
					carry.bad = true
					out[#out + 1] = refusal
				else
					-- Through splitLines like a file's contents, which is what makes
					-- `cat /dev/null` print NOTHING rather than one empty line: a
					-- device that reads empty has no lines in it, the same way an
					-- empty file has none.
					local said = CeroSecOS.splitLines(text)
					for j = 1, #said do put(said[j]) end
					if text ~= "" then glue, lastOpen = false, false end
				end
			elseif node.type ~= "file" then
				carry.bad = true
				out[#out + 1] = "cat: " .. p .. ": Is a directory"
			elseif not CeroSecOS.can(state, session, node, "r") then
				carry.bad = true
				out[#out + 1] = "cat: " .. p .. ": Permission denied"
			else
				local lines = CeroSecOS.splitLines(node.data)
				for j = 1, #lines do put(lines[j]) end
				if node.data ~= "" then
					lastOpen = not CeroSecOS.endsLine(node.data)
					glue = lastOpen
				end
			end
		end
		carry.pos = carry.pos + 1
	end
	if lastOpen then out.open = true end
	return not carry.bad, out
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
-- 9 id + 20 desc + 2 + 10 pos + 2 + 1 side + 2 + state, which puts the widest
-- state ("barricaded") on column 56 of the glass's 60. The description is 20
-- against `ls -l`'s 12: wider than the listing that has a mode and an owner in
-- front of it, and narrower than it would be if the offset were not the better
-- name.
--
-- NINE AND NOT EIGHT, because eight is the widest id this machine hands out and a
-- column exactly as wide as its content has no gap left in it: `curtain0` -- the
-- first curtain of the first house -- printed as `curtain0office`, with the room
-- name against the name of the device, and `window10` and `sensor10` would have
-- done the same. The page in the admin's manual always showed the space; the
-- column is what was wrong. Nine leaves one for an id of eight and none for one of
-- nine (`curtain10`, which is eleven curtains in one building), and a tenth
-- character would have to come out of `ls -l`'s room column, which is at 12
-- already.
local D_ID, D_DESC, D_POS, D_SIDE = 9, 20, 10, 1

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
--
-- And the motor rung's five, each with the two states a word undoes and nothing
-- else. A window0 that is smashed, boarded or sealed has no opposite, a stove
-- that is broken has none, and `dev window0 toggle` on any of them says "cannot
-- toggle" rather than guessing a direction for a sash that will not move -- while
-- `dev window0 open` still asks the world, which refuses in its own name.
local DEV_OPPOSITE = {
	light = { on = "off", off = "on" },
	lock  = { locked = "unlock", padlock = "unlock", unlocked = "lock" },
	win   = { locked = "unlock", unlocked = "lock" },
	door  = { open = "close", closed = "open", locked = "open" },
	window  = { open = "close", closed = "open" },
	curtain = { open = "close", closed = "open" },
	stove   = { on = "off", off = "on" },
	washer  = { on = "off", off = "on" },
	gen     = { on = "off", off = "on" },
	-- A television and a radio set toggle on the SWITCH and never on the dial:
	-- `channel 203` has no opposite, and a set has no state word for what it is
	-- tuned to -- the dial is in `detail`, beside the generator's fuel, for that
	-- reason among others (CeroSecOS.devText).
	tv      = { on = "off", off = "on" },
	rx      = { on = "off", off = "on" },
}

-- The SET, whole or filtered by kind, in the order it is printed in. A device
-- the machine remembers the number of and cannot reach is not in it, exactly as
-- `ls /dev` has it. nil plus a reason about /dev where the directory itself is
-- the refusal; the caller signs that one, because it is the command's.
--
-- One function and not two, because `dev <kind>` and `dev <kind> <value>` have to
-- be the same set in the same order: a broadcast that worked a device the listing
-- above it did not show -- or worked them in another order -- would be a listing
-- nobody could read the broadcast against.
local function devSet(state, session, kind)
	local dir, reason = CeroSecOS.getNode(state, session, CeroSecOS.DEV_PATH)
	if dir == nil then return nil, reason end
	if dir.type ~= "dir" then return nil, "not a directory" end
	if not CeroSecOS.can(state, session, dir, "r") then return nil, "permission denied" end

	local names = CeroSecOS.childNames(dir)
	local found = {}
	for i = 1, #names do
		local node = dir.children[names[i]]
		-- The world's devices, which is what this command is about: /dev/null is a
		-- hole in the disk and has no description, no place in the building and no
		-- state to show, so it is not a row here. `ls /dev` lists it, because it
		-- really is a file in that directory.
		if CeroSecOS.isDev(node) and not node.dead and not CeroSecOS.isNull(node)
				and (kind == nil or node.kind == kind) then
			found[#found + 1] = node
		end
	end
	table.sort(found, devBefore)
	return found
end

local function devTable(state, session, kind)
	local found, reason = devSet(state, session, kind)
	if found == nil then return fail("dev", CeroSecOS.DEV_PATH, reason) end

	local out = {}
	for i = 1, #found do out[i] = devRow(found[i]) end
	return true, out
end

-- ONE DEVICE, ONE WORD: the whole of what `dev <id> <value>` does to the device
-- it names -- the write gate, the world action, the refusals in the device's own
-- name -- so that a kind's whole set goes down exactly this road and a broadcast
-- is never a second road to a light switch. Answers the one line the command
-- prints about it, or false and the refusal to print instead.
local function devOne(state, session, node, value, env)
	if value == "toggle" then
		-- Read first, for the permission and for every refusal a read makes: a
		-- device nobody may read is not a device anybody may toggle.
		local text, refusal = CeroSecOS.devRead(state, session, node)
		if text == nil then return false, refusal end
		-- And then the opposite of the STATE and not of what the read printed.
		-- They are the same string on every kind but one: a generator reads `on
		-- fuel 62 condition 80 connected`, and an opposite table keyed by that
		-- sentence would be a table with no entry for anything.
		local opposites = DEV_OPPOSITE[node.kind]
		value = nil
		if opposites ~= nil then value = opposites[node.state] end
		if value == nil then return false, node.id .. ": cannot toggle" end
	end

	local done, refusal = CeroSecOS.devWrite(state, session, node, value, env)
	if done == nil then return false, refusal end
	-- The state the world was re-read for, off the node devWrite put it on --
	-- not read again through devRead, because a machine that took the order and
	-- then refused to say what happened would be worse than one that never took
	-- it. The whole line, so that `dev gen0 on` answers the same sentence
	-- `cat /dev/gen0` would.
	return true, node.id .. ": " .. CeroSecOS.devText(node)
end

-- A WHOLE KIND, one word, one answer line per device, in the listing's order.
-- Every device goes through devOne, so each one is gated, worked and refused
-- exactly as the same word typed at its own id would have been -- and the answer
-- to `dev window close` is the answers to three `dev windowN close` lines, in
-- the order `dev window` printed them.
--
-- The status is a command's and not a device's: any refusal and the line failed,
-- which is `cat a nosuch b`'s rule and every other command's on this machine that
-- does one thing per operand. A failed command's output stays on the GLASS, so
-- `dev window close > log` writes nothing when one window was boarded; a script
-- that wants the answers device by device wants the loop the manual's page shows.
--
-- A kind the building has none of is no lines and a status of nought, which is
-- what the loop over an empty listing does too. There is nothing to refuse: the
-- kind is real (the caller checked it against the vocabulary) and every device of
-- it was worked.
--
-- What it COST the machine, past the one command the shell charged: a broadcast
-- does the work of as many commands as there are devices in the set, and a budget
-- that could not see thirty world writes behind one word would not be a budget
-- (the `cost` field of the shell's table, and CeroSecOSVM's debt).
local function devBroadcast(state, session, kind, value, env, sh)
	local found, reason = devSet(state, session, kind)
	if found == nil then return fail("dev", CeroSecOS.DEV_PATH, reason) end

	local out, ok = {}, true
	for i = 1, #found do
		local done, line = devOne(state, session, found[i], value, env)
		if not done then ok = false end
		out[#out + 1] = line
	end
	if type(sh) == "table" and #found > 1 then
		sh.cost = (#found - 1) * CeroSecOS.STEP_COST_COMMAND
	end
	return ok, out
end

-- Four words and not three, for one shape: a dial is a name and a NUMBER, so
-- `dev tv0 channel 203` is what `dev light0 off` is for everything else. Nothing
-- else here takes four, and a fifth is the usage line as it always was.
--
-- And the word in the second slot is a KIND or an id, which is the fork the usage
-- line has always drawn (`dev [kind|id [value|toggle]|find <id>]`): the value
-- belongs to the slot and not to the id, so `dev window close` shuts every window
-- the machine can reach and `dev window0 close` shuts the one. There is no kind
-- that means "everything", on purpose -- `off` means a different thing to a light
-- than to a generator, and `dev light off` then `dev stove off` is two lines,
-- which is how an administrator in 1993 would have written it.
commands.dev = function(state, session, args, env, stdin, sh)
	if #args > 4 then return usage("dev") end
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
	-- A KIND, with or without a word after it. The fork is the word itself and not
	-- how many words came after it: an id is a kind with a number on the end and a
	-- kind never has one, so `dev window` and `dev window close` are the same word
	-- in the same slot and are read the same way. A word that is neither -- no
	-- number on the end and nothing the core has a vocabulary for -- is an unknown
	-- kind whatever follows it, which is where `dev light0/x on` moved to: it was
	-- never an id, and the answer to it is now the answer `dev light0/x` alone has
	-- always given.
	if not looksLikeId(word) then
		-- A kind is one the core has words for, and no other.
		if CeroSecOS.DEV_VALUES[word] == nil then return fail("dev", word, "unknown kind") end
		if #args == 2 then return devTable(state, session, word) end
		-- `dev <kind> find` is not a thing. find points at ONE device -- that is the
		-- whole of what it is for, telling one of thirty-five lights from the others
		-- -- and thirty-five lights blinking at once points at nothing. So the third
		-- word here is a value and "find" is not one of any kind's, and the answer is
		-- the grammar rather than "invalid value": `dev find <id>` is the line that
		-- was meant, and the usage line is where it is written.
		if args[3] == "find" then return usage("dev") end
		local value = args[3]
		-- The dial, on every set of the kind at once. Judged against the KIND, which
		-- is the only thing a broadcast has to judge it against and the same table
		-- CeroSecOS.devArg reads for one device (DEV_ARGS is keyed by kind).
		if #args == 4 then
			value = args[3] .. " " .. args[4]
			if CeroSecOS.devArg(word, value) == nil then return usage("dev") end
		end
		return devBroadcast(state, session, word, value, env, sh)
	end

	local node = devNodeOf(state, session, word)
	if node == nil then return fail("dev", word, "no such device") end

	if #args == 2 then
		local text, refusal = CeroSecOS.devRead(state, session, node)
		if text == nil then return false, { refusal } end
		return true, { node.id .. ": " .. text }
	end

	local value = args[3]
	-- The two words of a dial, joined back into the one value a redirect would
	-- have carried: there is one gate and one world action, and neither of them
	-- knows how the shell split the line (CeroSecOS.devArg reads both).
	--
	-- And a fourth word that is NOT one is the usage line, exactly as it was
	-- before this rung: `dev light0 on now` is a line somebody typed wrong and the
	-- answer to that is the command's grammar, not a light switch being asked
	-- about the word "now". A redirect has no such fourth word to judge, so
	-- `echo on now > /dev/light0` is still the device's own "invalid value" --
	-- one is a command mistake and the other is a value, and each is answered by
	-- the layer it belongs to.
	if #args == 4 then
		value = args[3] .. " " .. args[4]
		if CeroSecOS.devArg(node.kind, value) == nil then return usage("dev") end
	end

	local done, line = devOne(state, session, node, value, env)
	return done, { line }
end

-- -f, 4.4BSD-Lite2's bin/rm/rm.c: a name that was never there is not an
-- error (`if (rval && (!fflag || errno != ENOENT))` -- only ENOENT is
-- forgiven, a permission refusal is still said), and it never prompts, which
-- this rm never did, having no -i. A missing OPERAND is asked before any of
-- it (`if (argc < 1) usage();`), so `rm -f` alone still gets the usage line.
commands.rm = function(state, session, args, env)
	local recursive, force, paths = false, false, {}
	for i = 2, #args do
		local a = args[i]
		if string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				local flag = string.sub(a, c, c)
				if flag == "r" then
					recursive = true
				elseif flag == "f" then
					force = true
				else
					return badOption("rm", flag)
				end
			end
		else
			paths[#paths + 1] = a
		end
	end
	if #paths == 0 then return usage("rm") end

	local out, ok = {}, true
	for i = 1, #paths do
		local done, reason =
			CeroSecOS.removeNode(state, session, paths[i], recursive, CeroSecOS.clockOf(env))
		if done == nil and not (force and reason == "no such file") then
			ok = false
			out[#out + 1] = "rm: " .. paths[i] .. ": " .. CeroSecOS.strerror(reason)
		end
	end
	return ok, out
end

-- rmdir DIR... -- 4.4BSD-Lite2's bin/rmdir/rmdir.c: getopt with no letters
-- at all, then rmdir(2) on each operand in turn, warn() for one that fails
-- and on to the next, exit 1 if any did. There is no -p in that file (usage:
-- "rmdir directory ..."); POSIX.2 added one and 4.4BSD had not taken it.
-- rmdir(2)'s own two refusals, ENOTDIR and ENOTEMPTY, are asked here before
-- removeNode is called, rather than let a directory with something in it be
-- answered with rm's "is a directory" instead.
commands.rmdir = function(state, session, args, env)
	local dirs = {}
	for i = 2, #args do
		local a = args[i]
		if string.sub(a, 1, 1) == "-" and a ~= "-" then
			return badOption("rmdir", string.sub(a, 2, 2))
		end
		dirs[#dirs + 1] = a
	end
	if #dirs == 0 then return usage("rmdir") end
	local out, ok = {}, true
	for i = 1, #dirs do
		local path = dirs[i]
		local node, reason = CeroSecOS.getNode(state, session, path, true)
		local why = nil
		if node == nil then why = reason
		elseif node.type ~= "dir" then why = "not a directory"
		-- A mount point is EBUSY whatever is on it, the words removeNode
		-- refuses one in; asked first, since the disk's files are not the
		-- directory's to be "not empty" with.
		elseif CeroSecOS.mountUnder(state, CeroSecOS.resolve(session, path)) ~= nil then
			why = "Device busy"
		elseif CeroSecOS.countEntries(node) > 0 then why = "directory not empty"
		else
			local done, rreason =
				CeroSecOS.removeNode(state, session, path, true, CeroSecOS.clockOf(env))
			if done == nil then why = rreason end
		end
		if why ~= nil then
			ok = false
			-- rmdir.c's warn(): the path and strerror(3)'s sentence.
			out[#out + 1] = "rmdir: " .. path .. ": " .. CeroSecOS.strerror(why)
		end
	end
	return ok, out
end

-- mv SRC DST, or mv SRC... DIR -- the second form only when DIR already is
-- one, exactly the rule cp below shares with it: a last operand that is not a
-- directory and more than one source is a line the machine will not guess at.
commands.mv = function(state, session, args, env)
	if #args < 3 then return usage("mv") end
	local dst = args[#args]
	local srcs = {}
	for i = 2, #args - 1 do srcs[#srcs + 1] = args[i] end
	local dstNode = CeroSecOS.getNode(state, session, dst)
	if #srcs > 1 and (dstNode == nil or dstNode.type ~= "dir") then
		return fail("mv", dst, "not a directory")
	end

	local out, ok = {}, true
	for si = 1, #srcs do
		local src = srcs[si]
		local node, reason = CeroSecOS.getNode(state, session, src)
		if node == nil then
			ok = false
			out[#out + 1] = "mv: " .. src .. ": " .. CeroSecOS.strerror(reason)
		-- Said about the SOURCE, before the destination is worked out: what is
		-- a device is the thing being moved, and mv's other refusals all name
		-- the target because it is the target they are about.
		elseif CeroSecOS.isDev(node) then
			ok = false
			out[#out + 1] = "mv: " .. src .. ": is a device"
		else
			local target = dst
			if dstNode ~= nil and dstNode.type == "dir" then
				local name = baseName(session, src)
				if name == nil then
					ok = false
					out[#out + 1] = "mv: " .. src .. ": Permission denied"
					target = nil
				else
					target = dst .. "/" .. name
				end
			end
			if target ~= nil then
				local done, mreason =
					CeroSecOS.moveNode(state, session, src, target, CeroSecOS.clockOf(env))
				if done == nil then
					ok = false
					out[#out + 1] = "mv: " .. target .. ": " .. CeroSecOS.strerror(mreason)
				end
			end
		end
	end
	return ok, out
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

-- One source into one target, or a directory. Split out of commands.cp so
-- the loop below reads as the loop it is and not as one long function with
-- the count of its operands folded into the middle of it.
local function cpOne(state, session, src, dst, dstIsDir, recursive, env)
	local node, reason, srcAbs = CeroSecOS.getNode(state, session, src)
	if node == nil then return "cp: " .. src .. ": " .. CeroSecOS.strerror(reason) end
	-- A device cannot be copied: what would come out is a file holding the word
	-- "on", which is a lie about a light switch.
	if CeroSecOS.isDev(node) then return "cp: " .. src .. ": is a device" end
	if node.type ~= "file" and not recursive then
		return "cp: " .. src .. ": Is a directory"
	end
	if not canCopyTree(state, session, node) then
		return "cp: " .. src .. ": Permission denied"
	end

	local target = dst
	if dstIsDir then
		local name = baseName(session, src)
		if name == nil then return "cp: " .. src .. ": Permission denied" end
		target = dst .. "/" .. name
	end

	-- A directory never goes inside itself: the copy would be a child of what
	-- is being copied. Judged on the paths the WALK takes and not on the ones that
	-- were typed -- so neither "." and ".." nor a symbolic link can spell a way
	-- around it. The same test mv makes, for the same reason and with the same
	-- two paths (see CeroSecOS.moveNode).
	if node.type == "dir" then
		local srcPhys = select(4, CeroSecOS.getNode(state, session, src)) or srcAbs
		local targetPhys = CeroSecOS.physicalOf(state, session, target)
			or CeroSecOS.resolve(session, target)
		if CeroSecOS.isInside(targetPhys, srcPhys) then
			return "cp: " .. target .. ": invalid destination"
		end
	end

	-- A target that is already there. 4.4BSD cp.c (copy_file): an existing file
	-- is opened O_WRONLY|O_TRUNC and written over, so its owner and its mode are
	-- the ones it had -- only -p would change them, and there is no -p here. The
	-- write is setData's, which asks for w on the FILE and holds the size, the
	-- printable rule and the disk to theirs. Asked of the paths the walk really
	-- takes, so a link or a ".." cannot hide that the two names are one file:
	-- cp.c refuses that ("%s and %s are identical (not copied)."), and so does
	-- this, in the one shape every refusal here has -- "cp: name: are
	-- identical", the declared "refusal" deviation (CeroSecOS.DEVIATIONS).
	-- A device is left to the create below and its "read-only", as it always
	-- was: a copy onto one would be a write that went round devWrite.
	local tnode, _, _, tphys = CeroSecOS.getNode(state, session, target)
	if tnode ~= nil and not CeroSecOS.isDev(tnode) then
		local sphys = select(4, CeroSecOS.getNode(state, session, src)) or srcAbs
		if tphys ~= nil and tphys == sphys then return "cp: " .. src .. ": are identical" end
		if tnode.type == "file" then
			-- cp.c again: a directory onto a file is `errno = ENOTDIR;
			-- err(1, "%s", to.p_path)` in 4.4BSD-Lite2's copy(), so the
			-- target's name and "not a directory".
			if node.type ~= "file" then return "cp: " .. target .. ": Not a directory" end
			local done, wreason =
				CeroSecOS.setData(state, session, target, node.data or "", CeroSecOS.clockOf(env))
			if done == nil then return "cp: " .. target .. ": " .. CeroSecOS.strerror(wreason) end
			return nil
		end
	end

	-- The copy is the caller's, and it is stamped with now: cp without -p makes
	-- a new file, and a new file is new.
	local copy = CeroSecOS.copyNode(node, CeroSecOS.userOf(session))
	local created, creason =
		CeroSecOS.createNode(state, session, target, copy, CeroSecOS.clockOf(env))
	if created == nil then return "cp: " .. target .. ": " .. CeroSecOS.strerror(creason) end
	return nil
end

-- cp [-r] SRC DST, or cp [-r] SRC... DIR -- the second form only when the
-- last operand already is one, which is what turns `cp -r /mnt/* dst` into
-- a line that can run at all: the shell hands cp as many sources as /mnt had
-- entries, and cp only knows what to do with more than one of them because
-- DST is a directory.
commands.cp = function(state, session, args, env)
	local recursive, paths = false, {}
	for i = 2, #args do
		local a = args[i]
		-- Only before the first path: "cp -r a -b" has no second flag in it,
		-- and a name that begins with "-" is refused by isValidName anyway.
		if #paths == 0 and string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				if string.sub(a, c, c) ~= "r" then return badOption("cp", string.sub(a, c, c)) end
			end
			recursive = true
		else
			paths[#paths + 1] = a
		end
	end
	if #paths < 2 then return usage("cp") end
	local dst = paths[#paths]
	local srcs = {}
	for i = 1, #paths - 1 do srcs[#srcs + 1] = paths[i] end

	local dstNode = CeroSecOS.getNode(state, session, dst)
	local dstIsDir = dstNode ~= nil and dstNode.type == "dir"
	if #srcs > 1 and not dstIsDir then return fail("cp", dst, "not a directory") end

	local out, ok = {}, true
	for i = 1, #srcs do
		local line = cpOne(state, session, srcs[i], dst, dstIsDir, recursive, env)
		if line ~= nil then
			ok = false
			out[#out + 1] = line
		end
	end
	return ok, out
end

--
-- ln, readlink
--
-- Symbolic links, and only those: see the note above CeroSecOS.newLink for why a
-- machine whose state is copied by recursion cannot carry a hard one.
--
--   admin@ksp-04-11:~$ ln -s /var/log/cron log
--   admin@ksp-04-11:~$ cat log
--   admin@ksp-04-11:~$ readlink log
--   /var/log/cron
--
-- The target is kept exactly as it was typed, and it is NOT checked: a link to a
-- file that does not exist yet is a link somebody meant to make -- the machine
-- says "no such file" the moment it is used, which is the honest answer and the
-- one every Unix gives. What is checked is what a link IS: a path this machine
-- could address at all, and printable like everything else it stores.
commands.ln = function(state, session, args, env)
	local symbolic, paths = false, {}
	for i = 2, #args do
		local a = args[i]
		if #paths == 0 and string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				if string.sub(a, c, c) ~= "s" then return badOption("ln", string.sub(a, c, c)) end
			end
			symbolic = true
		else
			paths[#paths + 1] = a
		end
	end
	-- Without -s there is nothing this machine could make, so the usage line is
	-- the whole answer: it names the flag that is missing.
	if not symbolic or #paths ~= 2 then return usage("ln") end
	local target, name = paths[1], paths[2]
	if target == "" then return fail("ln", name, "invalid name") end
	if #target > CeroSecOS.MAX_LINK_BYTES then return fail("ln", name, "file too large") end

	-- A directory named as the second argument takes the link INSIDE it, under the
	-- target's own last component, the way `ln -s /bin/ls .` has always worked.
	-- Judged on the name as typed, because that is what the link will hold.
	local dstNode = CeroSecOS.getNode(state, session, name)
	if dstNode ~= nil and dstNode.type == "dir" then
		local _, parts = CeroSecOS.resolve(nil, target)
		if #parts == 0 then return fail("ln", name, "invalid name") end
		name = name .. "/" .. parts[#parts]
	end

	if underDev(session, name) then return devReadOnly() end
	local link = CeroSecOS.newLink(CeroSecOS.userOf(session), target)
	local made, reason = CeroSecOS.createNode(state, session, name, link, CeroSecOS.clockOf(env))
	if made == nil then return fail("ln", name, reason) end
	return true, {}
end

-- What a link points at is `ls -l`'s arrow and nothing else here. readlink(1) is
-- a 1997 command -- GNU shellutils wrote it, four years after this machine --
-- and a 1993 survivor read the arrow: `ls -l notes` prints
-- "lrwxrwxrwx  admin  admin  notes -> /root/real.txt". So there is no command of
-- that name (see CeroSecOS.RETIRED_BIN), and linkLine above is where the answer is.

-- chmod. An octal mode, or a symbolic one applied to the mode the file already
-- wears. Which of the two it is is decided BEFORE the path is looked at, so
-- `chmod zzz nosuchfile` still answers about the mode: a typo in the mode is
-- the thing the player got wrong and is what he should be told about.
-- chmod MODE FILE..., a mode and one file or several, exactly as chmod has
-- taken them since a mode became a word of its own and not part of the name.
commands.chmod = function(state, session, args, env)
	if #args < 3 then return usage("chmod") end
	local mode = parseMode(args[2])
	-- Tried against 000 only to judge the grammar; the real mode is the file's
	-- and is not known until the node is in hand.
	local symbolic = mode == nil and CeroSecOS.applyModeSpec(0, args[2]) ~= nil
	if mode == nil and not symbolic then return fail("chmod", args[2], "invalid mode") end
	local now = CeroSecOS.clockOf(env)
	local out, ok = {}, true
	for i = 3, #args do
		local node, reason = CeroSecOS.getNode(state, session, args[i])
		if node == nil then
			ok = false
			out[#out + 1] = "chmod: " .. args[i] .. ": " .. CeroSecOS.strerror(reason)
		elseif not isOwnerOrRoot(session, node) then
			ok = false
			out[#out + 1] = "chmod: " .. args[i] .. ": Permission denied"
		else
			local m = mode
			if symbolic then m = CeroSecOS.applyModeSpec(node.mode, args[2]) end
			if m == nil then
				ok = false
				out[#out + 1] = "chmod: " .. args[2] .. ": invalid mode"
			else
				node.mode = m
				-- One timestamp for the two a real filesystem has: a chmod
				-- moves the ctime there and moves this one here.
				if now ~= nil then node.mtime = now end
			end
		end
	end
	return ok, out
end

-- chown OWNER FILE..., the same way.
commands.chown = function(state, session, args, env)
	if #args < 3 then return usage("chown") end
	local user = CeroSecOS.getUser(state, args[2])
	if user == nil then return fail("chown", args[2], "no such user") end
	local now = CeroSecOS.clockOf(env)
	local out, ok = {}, true
	for i = 3, #args do
		local node, reason = CeroSecOS.getNode(state, session, args[i])
		if node == nil then
			ok = false
			out[#out + 1] = "chown: " .. args[i] .. ": " .. CeroSecOS.strerror(reason)
		-- A device is root's, always. Only the MODE of one is remembered
		-- across a command (see CeroSecOS.mountDev), so an owner given away
		-- here would be back to root by the next line, and a change that
		-- does not last is a change not to accept.
		elseif CeroSecOS.isDev(node) then
			ok = false
			out[#out + 1] = "chown: " .. args[i] .. ": is a device"
		elseif not isOwnerOrRoot(session, node) then
			ok = false
			out[#out + 1] = "chown: " .. args[i] .. ": Permission denied"
		else
			node.owner = user.name
			if now ~= nil then node.mtime = now end
		end
	end
	return ok, out
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

-- Putting text in a file is `echo text > file`, which is a REDIRECTION and is the
-- shell's own half of a line -- see CeroSecOS.writeRedirect, which every ">" on
-- this machine goes through, the editor's save included (CeroSecOS.writeFile under
-- it). There was a `write <file> <text>` command here until SYSTEM_VERSION 16 and
-- it was a double mistake: nothing in Unix has ever written a file that way, and
-- write(1) is the command that puts a line on ANOTHER ACCOUNT's terminal. Keeping
-- the name for the wrong job would have been worse than not having it.

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

-- df. Two lines per filesystem, because a disk on this machine has two ceilings
-- and either of them is what a write dies on: the bytes on it and the nodes on
-- it. Both are counted off the tree at the moment it is asked -- there is no
-- counter kept beside the filesystem that could ever disagree with it.
--
-- The hard disk always, and the floppy under it while one is mounted -- which is
-- what df has always done: it reports what is MOUNTED, and a disk sitting in the
-- drive unmounted is a disk no filesystem is reading. The two are counted apart
-- and neither is ever counted against the other (see CeroSecOS.fsFor).
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
	local out = {
		CeroSecOS.padRight("Filesystem", D_NAME)
			.. "  " .. CeroSecOS.padLeft("Size", D_NUM)
			.. "  " .. CeroSecOS.padLeft("Used", D_NUM)
			.. "  " .. CeroSecOS.padLeft("Avail", D_NUM)
			.. "  " .. CeroSecOS.padLeft("Use%", D_PCT),
		dfLine(CeroSecOS.DISK_NAME, CeroSecOS.DISK_BYTES, bytes),
		dfLine("nodes", CeroSecOS.MAX_NODES, nodes),
	}
	-- The mounted floppy, named the way the drive is named: its own two rows, and
	-- the node row says which disk it is about, because the machine's own does not
	-- have to.
	local mount = CeroSecOS.fdMount(state)
	if mount ~= nil then
		local fs = CeroSecOS.fsFor(state, mount.dir)
		local fnodes, fbytes = CeroSecOS.fsUsage(state, fs)
		-- The sticker, after the columns and not in the Filesystem one: that column
		-- is ten characters wide and truncates, and a label cut in half is a label
		-- that lies about which disk this is. On the BYTES row alone -- the two rows
		-- are two ceilings of one disk, and saying it twice would read as two.
		local line = dfLine(CeroSecOS.FD_NAME, fs.bytes, fbytes)
		local label = CeroSecOS.labelOfDev(state, CeroSecOS.FD_NAME)
		if label ~= nil then line = line .. "  (" .. label .. ")" end
		out[#out + 1] = line
		out[#out + 1] = dfLine(CeroSecOS.FD_NAME .. " nodes", fs.nodes, fnodes)
	end
	return true, out
end

--
-- Text tools
--

-- The lines of one file, or nil plus the one-line refusal already worded. Three
-- commands read files this way, so the three of them refuse in the same words.
-- The node comes back too, because wc counts bytes and not lines.
local function fileLines(state, session, cmd, path)
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node == nil then return nil, cmd .. ": " .. path .. ": " .. CeroSecOS.strerror(reason) end
	if node.type ~= "file" then
		return nil, cmd .. ": " .. path .. ": " .. CeroSecOS.strerror(CeroSecOS.notAFile(node))
	end
	if not CeroSecOS.can(state, session, node, "r") then
		return nil, cmd .. ": " .. path .. ": Permission denied"
	end
	return CeroSecOS.splitLines(node.data or ""), nil, node
end

--
-- Basic regular expressions, for grep
--
-- POSIX.2's BRE, cut to the six pieces a survivor types: `^` and `$` where they
-- anchor, `.` for one character, `*` for any number of the thing in front of it,
-- `[...]` and `[^...]` for a set, and `\` to take the meaning off any of them.
-- What is NOT here is `\(...\)` and `\{m,n\}` -- the back-reference and the
-- interval -- and the manual's page says so: both want a matcher that remembers
-- where a group started, which is a different machine from the one below.
--
-- Read by hand, never turned into a Lua pattern. A pattern is a string a player
-- typed, and handing one to string.find would be handing him Lua's own matcher --
-- the rule this whole engine is built on (see docs/SECURITY.md), and the reason
-- globMatch is walked rather than translated too.
--
-- Simulated as an NFA and not by backtracking, which is the one design decision in
-- here that matters. A backtracking matcher on `a*a*a*a*b` against a line of a's is
-- exponential, and a player types the pattern -- so the walk below carries a SET of
-- positions through the line, one pass, and costs the length of the line times the
-- length of the pattern whatever the pattern says. Thompson's construction, 1968,
-- and the same reason grep(1) itself was written that way.
--

-- One piece of a pattern: a character, any character, or a set -- each of which may
-- carry a `*`. nil plus the refusal for a pattern that is not one.
--
-- head and tail are the two anchors, and both are only anchors WHERE POSIX says: a
-- `^` that is not the first character is a circumflex, and a `$` that is not the
-- last is a dollar sign. `*` is the same kind of rule the other way: at the front of
-- a pattern there is nothing for it to repeat, so it is a star.
--
-- plain is the pattern's LITERAL text when every piece of it is an unstarred
-- character. That is the pattern a survivor types nine times in ten -- `grep From`,
-- `grep '^From '` -- and it is matched by string.find and string.sub instead of by
-- the walk, which is the difference between a C call and a loop over every byte.
-- Pieces in one pattern. The walk below costs the length of the LINE times the
-- number of pieces, and a line may be a whole file -- four kilobytes with no
-- newline in it -- so this number is the other half of what that costs: measured at
-- a third of a microsecond a piece a character, thirty-two pieces over the widest
-- line a file can hold is forty-odd milliseconds, and two hundred pieces is a third
-- of a second. Thirty-two is longer than any pattern anybody types (the longest one
-- in this file's own benches is twenty) and short enough that the worst a crafted
-- one can cost is one dear command, which is what the step debt is for.
CeroSecOS.MAX_BRE_ITEMS = 32

function CeroSecOS.breCompile(pattern)
	if type(pattern) ~= "string" then return nil, "bad expression" end
	local re = { items = {}, head = false, tail = false }
	local items = re.items
	local i, n = 1, #pattern
	if string.sub(pattern, 1, 1) == "^" then
		re.head = true
		i = 2
	end
	local literal = true
	while i <= n do
		local c = string.sub(pattern, i, i)
		if c == "$" and i == n then
			re.tail = true
			i = i + 1
		elseif c == "\\" then
			local nx = string.sub(pattern, i + 1, i + 1)
			if nx == "" then return nil, "trailing backslash" end
			items[#items + 1] = { c = nx, b = string.byte(nx) }
			i = i + 2
		elseif c == "." then
			items[#items + 1] = { any = true }
			literal = false
			i = i + 1
		elseif c == "*" and #items > 0 then
			-- Onto the piece in front of it, and never onto another star: `a**` is
			-- `a*`, which is what every BRE does with it.
			items[#items].star = true
			literal = false
			i = i + 1
		elseif c == "[" then
			local j = i + 1
			local set, neg = {}, false
			if string.sub(pattern, j, j) == "^" then
				neg = true
				j = j + 1
			end
			-- A "]" as the FIRST character of a set is a "]" in the set, which is the
			-- only way of putting one there and is POSIX's rule.
			if string.sub(pattern, j, j) == "]" then
				set[string.byte("]")] = true
				j = j + 1
			end
			local closed = false
			while j <= n do
				local ch = string.sub(pattern, j, j)
				if ch == "]" then
					closed = true
					j = j + 1
					break
				end
				-- A range, unless the "-" is the last character before the "]", where it
				-- is a hyphen.
				if string.sub(pattern, j + 1, j + 1) == "-"
						and string.sub(pattern, j + 2, j + 2) ~= "]"
						and j + 2 <= n then
					local last = string.sub(pattern, j + 2, j + 2)
					local a, b = string.byte(ch), string.byte(last)
					if b < a then return nil, "bad range" end
					for k = a, b do set[k] = true end
					j = j + 3
				else
					set[string.byte(ch)] = true
					j = j + 1
				end
			end
			if not closed then return nil, "unmatched [" end
			items[#items + 1] = { set = set, neg = neg }
			literal = false
			i = j
		else
			items[#items + 1] = { c = c, b = string.byte(c) }
			i = i + 1
		end
	end
	if #items > CeroSecOS.MAX_BRE_ITEMS then return nil, "expression too long" end
	if literal then
		local text = {}
		for k = 1, #items do text[k] = items[k].c end
		re.plain = table.concat(text)
	end
	-- The piece a match must START on, when the pattern begins with one that cannot
	-- be skipped. A pattern is tried at every character of the line, and that is what
	-- the walk costs; where the first piece is not starred, a match beginning at a
	-- character REQUIRES that piece to match it, so every other character is a
	-- character the walk need not start at. `grep l.ghts` over a line with no "l" in
	-- it then costs one byte read a character and nothing else.
	if not re.head and items[1] ~= nil and not items[1].star then re.lead = items[1] end
	return re
end

-- Does this piece match this BYTE? Bytes and not one-character strings: the walk
-- below asks this once per character of every line, and string.sub(line, k, k)
-- allocates a string every time it is asked -- measured as more than half the cost
-- of matching a four-kilobyte line. string.byte allocates nothing.
local function breItemHit(item, b)
	if item.any then return true end
	if item.set ~= nil then
		if item.neg then return item.set[b] ~= true end
		return item.set[b] == true
	end
	return item.b == b
end

-- Every position the walk may be at, once the stars in front of it have been
-- allowed to swallow nothing. n + 1 is "the whole pattern has matched".
--
-- The set is a LIST of positions plus a stamp saying which pass put each one in it,
-- and not a fresh table a character: a table per character of a four-kilobyte line
-- is four thousand allocations for one grep, and the stamp is how a set is emptied
-- without walking it.
local function breAdd(set, items, i, n, gen)
	while i <= n do
		if set.mark[i] == gen then return end
		set.mark[i] = gen
		set.n = set.n + 1
		set[set.n] = i
		if not items[i].star then return end
		i = i + 1
	end
	if set.mark[n + 1] ~= gen then
		set.mark[n + 1] = gen
		set.accept = true
	end
end

local function breClear(set)
	set.n = 0
	set.accept = false
end

-- How many state-visits a STEP is worth, for charging the walk to the job's budget.
--
-- A command out of /bin is charged STEP_COST_COMMAND (32) steps, and a machine's pass
-- is a hundred steps meant to cost about four milliseconds of real time -- forty
-- microseconds a step. A state-visit below was measured at a third of a microsecond,
-- so a step at that exchange rate buys about a hundred and twenty of them.
--
-- Sixty-four, which is half of that, and the half is deliberate: charged at the exact
-- rate, a loop over the dearest pattern the ceiling allows averaged 3.97 ms a pass
-- against a ceiling of 4 -- correct by construction and with no margin at all. At
-- twice the rate the same loop averages two, and an honest pattern over a whole file
-- still costs about one command and a half.
--
-- Without this, grep was the one command that could cost far more than the budget
-- believes a command costs: a plain substring is a C call whatever the file, but a
-- pattern is a walk of every byte of it for every piece of the pattern -- five
-- milliseconds for an honest regular expression over the widest line a file can
-- hold, twenty-two for a crafted one. Charged, a loop of those runs slowly instead of
-- making a machine slow, which is the whole bargain the step budget is.
CeroSecOS.BRE_STEPS_PER = 64

-- Does this line hold a match? One pass over it, carrying the set of positions.
-- Answers the match and what the walk COST, in state-visits.
function CeroSecOS.breMatch(line, re)
	local items = re.items
	local n = #items
	if re.plain ~= nil then
		-- The literal paths, which are the patterns anybody actually types: nine
		-- greps in ten, and `^From ` among them. A C call instead of the walk, and one
		-- visit's worth of cost however long the line is.
		if re.head and re.tail then return line == re.plain, 1 end
		if re.head then return string.sub(line, 1, #re.plain) == re.plain, 1 end
		if re.tail then
			if #line < #re.plain then return false, 1 end
			return string.sub(line, #line - #re.plain + 1) == re.plain, 1
		end
		return string.find(line, re.plain, 1, true) ~= nil, 1
	end
	local len = #line
	local act = { n = 0, accept = false, mark = {} }
	local nxt = { n = 0, accept = false, mark = {} }
	local gen = 1
	local visits = 1
	if re.lead == nil or (len > 0 and breItemHit(re.lead, string.byte(line, 1))) then
		breAdd(act, items, 1, n, gen)
	end
	if act.accept and (not re.tail or len == 0) then return true, visits end
	for k = 1, len do
		local b = string.byte(line, k)
		gen = gen + 1
		breClear(nxt)
		visits = visits + act.n + 1
		for j = 1, act.n do
			local i = act[j]
			if i <= n and breItemHit(items[i], b) then
				-- A starred piece may swallow this character and stay where it is, or
				-- hand over to the piece after it.
				if items[i].star then breAdd(nxt, items, i, n, gen) end
				breAdd(nxt, items, i + 1, n, gen)
			end
		end
		act, nxt = nxt, act
		-- An unanchored pattern may start at any character, so the first position is
		-- put back at every one of them. This is what makes the walk linear instead of
		-- one pass per starting point -- and where the first piece cannot be skipped,
		-- only at the characters that piece could match (re.lead).
		if not re.head and k < len then
			if re.lead == nil then
				breAdd(act, items, 1, n, gen)
			elseif breItemHit(re.lead, string.byte(line, k + 1)) then
				breAdd(act, items, 1, n, gen)
			end
		end
		if act.accept and (not re.tail or k == len) then return true, visits end
	end
	return false, visits
end

-- Is this line one of the ones grep was asked for? -v is the whole of the
-- difference between "holds the pattern" and "is a line grep prints": the flag
-- does not change what a hit is, it changes which lines are wanted.
--
-- Several patterns is several -e, and a hit on any of them is a hit: that is what
-- POSIX.2 says of -e and what a list of them has always meant.
--
-- The line is lowered when -i is on, and the patterns were lowered before they were
-- compiled -- once for a file, not once for a line.
local function grepHit(line, res, ignore, invert, work)
	local hay = line
	if ignore then hay = string.lower(hay) end
	local held = false
	for i = 1, #res do
		local hit, cost = CeroSecOS.breMatch(hay, res[i])
		work.n = work.n + cost
		if hit then
			held = true
			break
		end
	end
	if invert then return not held end
	return held
end

-- grep, with a basic regular expression.
--
-- POSIX.2's BRE, as far as CeroSecOS.breCompile reads one, and `-e` to give the
-- pattern as an option-argument -- which is the only way of looking for a pattern
-- that starts with a dash, and is POSIX's own reason for the flag. Several -e is
-- several patterns and a hit on any of them is a hit.
--
-- The options are read here rather than through flagsOf, because -e takes a value
-- and may take it attached (`-eFrom`), which is getopt(3)'s rule and cut's.
--
-- It was a plain substring until this: `grep -c '^From '` on a mailbox -- the first
-- line anybody writes about mail -- counted nought, because the circumflex was a
-- character to look for.
local function grepOptions(args)
	local flags, pats, rest = {}, {}, {}
	local i = 2
	while i <= #args do
		local a = args[i]
		if #rest == 0 and string.sub(a, 1, 2) == "-e" then
			local text
			if #a > 2 then
				text = string.sub(a, 3)
				i = i + 1
			else
				text = args[i + 1]
				i = i + 2
			end
			if text == nil then return nil, nil, "-e" end
			pats[#pats + 1] = text
		elseif #rest == 0 and string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				local flag = string.sub(a, c, c)
				if string.find("cinv", flag, 1, true) == nil then return nil, nil, a end
				flags[flag] = true
			end
			i = i + 1
		else
			rest[#rest + 1] = a
			i = i + 1
		end
	end
	return flags, pats, rest
end

commands.grep = function(state, session, args, env, stdin, sh)
	local flags, pats, bad = grepOptions(args)
	if flags == nil then return badOption("grep", bad) end
	local ignore, numbered = flags.i == true, flags.n == true
	local counting, invert = flags.c == true, flags.v == true
	local rest = bad
	-- With no -e, the first operand is the pattern, which is grep's oldest shape.
	if #pats == 0 then
		if #rest < 1 then return usage("grep") end
		pats[1] = rest[1]
		local kept = {}
		for i = 2, #rest do kept[#kept + 1] = rest[i] end
		rest = kept
	else
		local kept = {}
		for i = 1, #rest do kept[#kept + 1] = rest[i] end
		rest = kept
	end

	-- Compiled once for the whole call, because a pattern is the same pattern on
	-- every line of every file. -i lowers it here, once, for the same reason.
	local res = {}
	for i = 1, #pats do
		local text = pats[i]
		if ignore then text = string.lower(text) end
		local re, reason = CeroSecOS.breCompile(text)
		if re == nil then return fail("grep", pats[i], reason) end
		res[i] = re
	end
	-- What the walk costs, gathered here and handed back to the shell so the budget
	-- pays for it (CeroSecOS.BRE_STEPS_PER, and the `cost` field of the shell's little
	-- table). A literal pattern is a C call and costs nothing worth charging; a
	-- pattern is every byte of every line, and that is real work.
	local work = { n = 0 }
	local function charge()
		if type(sh) == "table" then
			sh.cost = math.floor(work.n / CeroSecOS.BRE_STEPS_PER)
		end
	end

	-- With a string and no file, the pipe. The line numbers are the PIPE's --
	-- counted from the first line that came down it, not restarted every time
	-- grep is called -- and whether anything was found is carried the same way,
	-- so `... | grep x` answers 0 for a hit that came down in an earlier turn.
	local files = {}
	for i = 1, #rest do files[#files + 1] = rest[i] end
	local input = stdinOf(stdin, files)
	if input ~= nil then
		local carry = input.carry
		if carry.n == nil then carry.n = 0 end
		if carry.hits == nil then carry.hits = 0 end
		local out = {}
		for i = 1, #input.lines do
			carry.n = carry.n + 1
			if grepHit(input.lines[i], res, ignore, invert, work) then
				carry.found = true
				carry.hits = carry.hits + 1
				if not counting then
					local prefix = ""
					if numbered then prefix = tostring(carry.n) .. ":" end
					out[#out + 1] = prefix .. input.lines[i]
				end
			end
		end
		charge()
		-- -c has one line to say and cannot say it before the end of the pipe:
		-- a count of what has arrived so far is not a count of anything.
		if counting then
			if not input.eof then return true, {} end
			out[1] = tostring(carry.hits)
		end
		if not carry.found then
			-- Exit 1, and the count still on the standard OUTPUT: grep(1) writes
			-- "0" there under -c and says it found nothing by its status alone.
			-- Told to the shell (runSimple), which would take the lines of a command
			-- that failed for its errors otherwise, and `$(grep -c x f)` would be "".
			if type(sh) == "table" then sh.outOnFail = true end
			return false, out
		end
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
				if grepHit(lines[n], res, ignore, invert, work) then
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

	charge()
	-- grep answers "did you find anything". Nothing found is a refusal even
	-- when every file was read without trouble -- and a -c that counted nothing
	-- is nothing found, however many zeroes it printed.
	-- Only when every file was read: a missing one puts its refusal in the same
	-- list, and a list with both in it is the errors' (the "stderr" deviation).
	if not found then
		if okAll and type(sh) == "table" then sh.outOnFail = true end
		return false, out
	end
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
		local all = true
		for i = 1, #input.lines do
			if carry.n >= n then all = false break end
			carry.n = carry.n + 1
			out[#out + 1] = input.lines[i]
		end
		-- The input's own last line, and it had no newline: head copies
		-- bytes, so it has none on the way out either.
		if all and input.eof and input.open and #out > 0 then out.open = true end
		if carry.n >= n then input.done = true end
		return true, out
	end

	if #rest ~= 1 then return usage("head") end
	local lines, refusal, node = fileLines(state, session, "head", rest[1])
	if lines == nil then return false, { refusal } end
	local out = {}
	for i = 1, #lines do
		if i > n then break end
		out[#out + 1] = lines[i]
	end
	if #out > 0 and #out == #lines and not CeroSecOS.endsLine(node.data) then
		out.open = true
	end
	return true, out
end

-- +N, tail(1)'s older form, and the one head(1) never had: `tail +N` starts at
-- line N and runs to the end, where -N counts back from it. Only at the front
-- of the line and only tail's, per 4.4BSD's tail.c and the manual's deviations
-- page (which said this was missing). Since it names a STARTING point rather
-- than a count kept until the end, it can be answered as it goes -- like head,
-- and unlike -n N -- so a pipe under it costs nothing per line once past N.
local function tailPlus(args)
	local a = args[2]
	if a == nil or string.match(a, "^%+%d+$") == nil then return nil end
	local from = tonumber(string.sub(a, 2))
	if from < 1 then from = 1 end
	local rest = {}
	for i = 3, #args do rest[#rest + 1] = args[i] end
	return from, rest
end

commands.tail = function(state, session, args, env, stdin)
	local from, plusRest = tailPlus(args)
	if from ~= nil then
		local input = stdinOf(stdin, plusRest)
		if input ~= nil then
			local carry = input.carry
			if carry.seen == nil then carry.seen = 0 end
			local out = {}
			for i = 1, #input.lines do
				carry.seen = carry.seen + 1
				if carry.seen >= from then out[#out + 1] = input.lines[i] end
			end
			return true, out
		end
		if #plusRest ~= 1 then return usage("tail") end
		local lines, refusal = fileLines(state, session, "tail", plusRest[1])
		if lines == nil then return false, { refusal } end
		local out = {}
		for i = from, #lines do out[#out + 1] = lines[i] end
		return true, out
	end

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
		-- The kept lines end where the input did: open, if it was.
		local out = {}
		for i = 1, #carry.keep do out[i] = carry.keep[i] end
		if input.open and #out > 0 then out.open = true end
		return true, out
	end

	if #rest ~= 1 then return usage("tail") end
	local lines, refusal, node = fileLines(state, session, "tail", rest[1])
	if lines == nil then return false, { refusal } end
	local first = #lines - n + 1
	if first < 1 then first = 1 end
	local out = {}
	for i = first, #lines do out[#out + 1] = lines[i] end
	if #out > 0 and not CeroSecOS.endsLine(node.data) then out.open = true end
	return true, out
end

-- wc: lines, words, bytes, name -- or whichever of the three -l, -w and -c ask
-- for, always in that order however the flags were written, which is POSIX's
-- rule and not a choice. No flag at all is all three, which is the one place the
-- default is written down.
--
-- Each number is " %7ld", 4.4BSD-Lite2's usr.bin/wc/wc.c: a blank and seven
-- columns, the name after one more blank (" %s\n"), and a line counted off a
-- pipe is the numbers and nothing after them. Three numbers are 24 of the
-- screen's 60 and the name has the 35 left after its blank.
local W_NUM, W_ROW = 7, 60
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
			out = out .. " " .. CeroSecOS.padLeft(tostring(counts[key] or 0), W_NUM)
			shown = shown + 1
		end
	end
	return out, shown
end

local function wcLine(want, counts, name)
	local out, shown = wcCounts(want, counts)
	return out .. " " .. CeroSecOS.truncate(name, W_ROW - (W_NUM + 1) * shown - 1)
end

-- A word is a run of anything that is not a blank. Newlines count as blanks:
-- the data is one string with newlines in it, not a list of lines.
local function wordsIn(text)
	local n = 0
	for _ in string.gmatch(text, "[^ \t\n]+") do n = n + 1 end
	return n
end

-- wc -l counts the NEWLINE BYTE, not the line it starts (POSIX wc(1)): a file
-- whose last line has none is one short, which is what "a\nb" -- printf's,
-- or an old save's, since neither ever carried a final "\n" -- being TWO
-- lines but ONE count is. #splitLines(data) is the wrong number for exactly
-- that file; this counts the bytes themselves; no gsub count (kahlua-probe
-- has not proved that return of it).
local function countNewlines(text)
	local n, start = 0, 1
	while true do
		local p = string.find(text, "\n", start, true)
		if p == nil then return n end
		n = n + 1
		start = p + 1
	end
end

commands.wc = function(state, session, args, env, stdin)
	local want, paths = flagsOf(args, "clw")
	if want == nil then return badOption("wc", paths) end
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
			-- Every line down the pipe ends in a newline EXCEPT possibly the
			-- very last -- input.open says so, and only the final turn (eof)
			-- can be that one -- which is what makes `wc f` and `cat f | wc`
			-- agree.
			carry.l = (carry.l or 0) + 1
			carry.c = (carry.c or 0) + #line + 1
			carry.w = (carry.w or 0) + wordsIn(line)
		end
		if not input.eof then return true, {} end
		if input.open and (carry.l or 0) > 0 then
			carry.l = carry.l - 1
			carry.c = carry.c - 1
		end
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
			local counts = { l = countNewlines(data), w = wordsIn(data), c = #data }
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
	if flags == nil then return badOption("sort", paths) end
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
	-- 4.4BSD-Lite2's usr.bin/uniq/uniq.c, show(): "%4d %s".
	return CeroSecOS.padLeft(tostring(count), 4) .. " " .. line
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
	if flags == nil then return badOption("uniq", paths) end
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

--
-- cut, tr, tee: the three POSIX.2 filters this machine was missing
--

-- A list like "1,3-5" -> the positions it names, as a set plus the highest one.
-- POSIX.2's own grammar for -c and -f: numbers and ranges, separated by commas,
-- and a range with no number after the "-" runs to the end of the line ("3-").
-- nil for a list that is not one, which the caller words its own refusal about.
local function cutList(text)
	if type(text) ~= "string" or text == "" then return nil end
	local want, high, toEnd = {}, 0, nil
	local start = 1
	while true do
		local p = string.find(text, ",", start, true)
		local piece
		if p == nil then piece = string.sub(text, start) else piece = string.sub(text, start, p - 1) end
		if piece == "" then return nil end
		local lo, hi = string.match(piece, "^(%d+)%-(%d*)$")
		if lo == nil then
			local one = string.match(piece, "^(%d+)$")
			if one == nil then
				-- "-5" is "from the first to the fifth", which is the one shape
				-- with nothing in front of the hyphen.
				local upto = string.match(piece, "^%-(%d+)$")
				if upto == nil then return nil end
				lo, hi = "1", upto
			else
				lo, hi = one, one
			end
		end
		lo = tonumber(lo)
		if lo < 1 then return nil end
		if hi == "" then
			-- To the end of the line. Remembered as a floor rather than a set,
			-- because a line's length is not known here.
			if toEnd == nil or lo < toEnd then toEnd = lo end
		else
			hi = tonumber(hi)
			if hi < lo then return nil end
			for i = lo, hi do
				want[i] = true
				if i > high then high = i end
			end
		end
		if p == nil then break end
		start = p + 1
	end
	return want, high, toEnd
end

local function cutWanted(want, toEnd, i)
	if want[i] then return true end
	return toEnd ~= nil and i >= toEnd
end

-- One line through cut. Characters or fields, and the two are one function
-- because the selection is the same selection.
--
-- A line with no delimiter in it comes through WHOLE under -f, which is what
-- POSIX says and what cut has always done: the line is not a record, so there is
-- nothing to take a field out of. (There is no -s here to ask for the other
-- answer, and the manual names that.)
-- Built in a TABLE and joined once, not grown a character at a time. A line here
-- may be four kilobytes -- a whole file on one line -- and `out = out .. c` four
-- thousand times is four thousand new strings and eight megabytes copied: measured
-- at 4.2 ms for one `cut -c 1-4096`, which is the whole of a pass's wall-clock
-- budget spent by one command, and a loop around it would have been a way to make
-- a server slow. The join is linear and the same call costs a fraction of a
-- millisecond.
local function cutLine(line, want, toEnd, delim)
	if delim == nil then
		local out, n = {}, 0
		for i = 1, #line do
			if cutWanted(want, toEnd, i) then
				n = n + 1
				out[n] = string.sub(line, i, i)
			end
		end
		return table.concat(out)
	end
	if string.find(line, delim, 1, true) == nil then return line end
	local fields = {}
	local start = 1
	while true do
		local p = string.find(line, delim, start, true)
		if p == nil then
			fields[#fields + 1] = string.sub(line, start)
			break
		end
		fields[#fields + 1] = string.sub(line, start, p - 1)
		start = p + #delim
	end
	local out, shown = "", 0
	for i = 1, #fields do
		if cutWanted(want, toEnd, i) then
			if shown > 0 then out = out .. delim end
			out = out .. fields[i]
			shown = shown + 1
		end
	end
	return out
end

-- cut -c <list>, or cut -d <delim> -f <list>. The default delimiter is a TAB,
-- which is cut(1)'s own default and the reason -d exists at all.
--
-- ATTACHED OR APART, for all three. POSIX.2's utility syntax guidelines say an
-- option-argument may be written in the same word as its option, and cut(1) reads
-- its line with getopt(3), which is where that rule comes from -- so `cut -d: -f1`
-- and `cut -d : -f 1` are the same line, and `cut -d:` is the form every mbox and
-- /etc/passwd one-liner of the era is written in. Only the separated form was
-- taken here, so the line a survivor actually types answered a usage line.
--
-- The remainder of the word is the argument WHATEVER it looks like: `-f-3` is the
-- list "-3" (up to the third field) and not an option, because getopt stops
-- reading options at the letter it was given.
local function cutArg(args, i, a)
	if #a > 2 then return string.sub(a, 3), i + 1 end
	return args[i + 1], i + 2
end

commands.cut = function(state, session, args, env, stdin)
	local mode, list, delim = nil, nil, "\t"
	local paths = {}
	local i = 2
	while i <= #args do
		local a = args[i]
		local head = string.sub(a, 1, 2)
		if head == "-c" or head == "-f" then
			if #paths > 0 then return usage("cut") end
			mode = string.sub(a, 2, 2)
			list, i = cutArg(args, i, a)
			if list == nil then return usage("cut") end
		elseif head == "-d" then
			if #paths > 0 then return usage("cut") end
			local d
			d, i = cutArg(args, i, a)
			if d == nil or #d ~= 1 then return usage("cut") end
			delim = d
		elseif #paths == 0 and string.sub(a, 1, 1) == "-" and a ~= "-" then
			return badOption("cut", a)
		else
			paths[#paths + 1] = a
			i = i + 1
		end
	end
	if mode == nil then return usage("cut") end
	local want, _, toEnd = cutList(list)
	if want == nil then return fail("cut", list, "invalid list") end
	-- -c cuts CHARACTERS and has no delimiter to be given one for: a line with
	-- both flags on it is a line that cannot be carried out, and cut(1) says so
	-- rather than picking one.
	local d = nil
	if mode == "f" then d = delim end

	local input = stdinOf(stdin, paths)
	if input ~= nil then
		local out = {}
		for k = 1, #input.lines do out[#out + 1] = cutLine(input.lines[k], want, toEnd, d) end
		return true, out
	end
	if #paths == 0 then return usage("cut") end
	local out, okAll = {}, true
	for k = 1, #paths do
		local lines, why = fileLines(state, session, "cut", paths[k])
		if lines == nil then
			okAll = false
			out[#out + 1] = why
		else
			for j = 1, #lines do out[#out + 1] = cutLine(lines[j], want, toEnd, d) end
		end
	end
	return okAll, out
end

-- One of tr's two sets, expanded: "a-z" is the twenty-six letters, and every
-- other character stands for itself. No classes -- [:alpha:] is POSIX.2 and this
-- machine has the ranges, which is what a survivor types -- and the manual says
-- so. nil for a set that is not one.
local function trSet(text)
	if type(text) ~= "string" or text == "" then return nil end
	local out = {}
	local i = 1
	while i <= #text do
		local c = string.sub(text, i, i)
		if string.sub(text, i + 1, i + 1) == "-" and i + 2 <= #text then
			local last = string.sub(text, i + 2, i + 2)
			local a, b = string.byte(c), string.byte(last)
			if b < a then return nil end
			for n = a, b do out[#out + 1] = string.char(n) end
			i = i + 3
		else
			out[#out + 1] = c
			i = i + 1
		end
	end
	return out
end

-- The translation, as a table from one character to another. tr's own rule when
-- set2 is shorter: the LAST character of set2 stands in for the rest of set1,
-- which is what lets `tr a-z x` write a line of x's.
local function trMap(set1, set2)
	local map = {}
	for i = 1, #set1 do
		local to = set2[i]
		if to == nil then to = set2[#set2] end
		map[set1[i]] = to
	end
	return map
end

-- A table and one join, for the reason cutLine above has one: a four-kilobyte line
-- translated a character at a time is quadratic, and this is the other command that
-- walks every byte of one.
local function trLine(line, map, drop)
	local out, n = {}, 0
	for i = 1, #line do
		local c = string.sub(line, i, i)
		if drop then
			if map[c] == nil then
				n = n + 1
				out[n] = c
			end
		else
			n = n + 1
			out[n] = map[c] or c
		end
	end
	return table.concat(out)
end

-- tr [-d] <set1> [<set2>]. It reads its standard input and nothing else, which
-- is tr(1)'s own shape: there is no file operand on any tr, and on this machine
-- that means a pipe on its left.
commands.tr = function(state, session, args, env, stdin)
	local flags, rest = flagsOf(args, "d")
	if flags == nil then return badOption("tr", rest) end
	local drop = flags.d == true
	if drop then
		if #rest ~= 1 then return usage("tr") end
	elseif #rest ~= 2 then
		return usage("tr")
	end

	local set1 = trSet(rest[1])
	if set1 == nil then return fail("tr", rest[1], "invalid set") end
	local map = {}
	if drop then
		for i = 1, #set1 do map[set1[i]] = true end
	else
		local set2 = trSet(rest[2])
		if set2 == nil then return fail("tr", rest[2], "invalid set") end
		map = trMap(set1, set2)
	end

	-- No file, ever: what tr reads is its standard input. A tr with no pipe on
	-- its left is a tr with nothing to read, and the usage line is the honest
	-- answer -- the same one every other reader on this machine gives.
	if type(stdin) ~= "table" then return usage("tr") end
	stdin.want = true
	local out = {}
	for i = 1, #stdin.lines do out[#out + 1] = trLine(stdin.lines[i], map, drop) end
	return true, out
end

-- tee [-a] <file...>: the input, onto the screen AND into every file named. The
-- first call replaces what is in a file and every call after it appends, which is
-- what one open file looks like from here: tee is called once per turn of the
-- pipe and the file is not held open between them. -a appends from the first
-- call, which is what -a has always meant.
--
-- wall
--
-- A line to every terminal on the machine. 4.4BSD's wall(1), and ANYBODY may run
-- it: the program is setgid tty rather than setuid root, because a broadcast is not
-- a privilege -- a machine with four people on it is a machine where somebody has
-- to be able to say the lights are going off in five minutes -- and root is only
-- the account that usually has the reason. `shutdown` already broadcasts through
-- this same door (CeroSecJobs.wall); this is the door with a person behind it.
--
-- The banner is wall.c's own, and over TWO lines because wall.c writes it over two:
--
--   Broadcast Message from admin@ksp-front-01
--           (console) at 14:32 ...
--
-- One line of it would not fit sixty columns either, so the two are the same
-- decision twice. A blank line under it, then the text, which is what a real one
-- sends. No bell: the console strips control bytes off every line it takes
-- (CeroSecOS.fit), and a \007 nothing can carry is not worth writing.
--
-- The text comes from a FILE named on the line or from the standard input, which is
-- wall(1)'s own pair (`wall [file]`) and on this machine means a pipe -- there is
-- no keyboard behind a command, so `wall` with neither prints its usage line the way
-- every other reader does.
--
-- Bounded by the pipe's own ceiling, like `mail`: what goes on four screens at once
-- has to be something a screen can hold.
commands.wall = function(state, session, args, env, stdin, sh)
	local paths = operands(args)
	if #paths > 1 then return usage("wall") end
	local body = nil
	local input = stdinOf(stdin, paths)
	if input ~= nil then
		local carry = input.carry
		for i = 1, #input.lines do
			if not holdLine(carry, input.lines[i]) then carry.over = true end
		end
		if carry.over then
			input.done = true
			return fail("wall", nil, "input too large")
		end
		if not input.eof then return true, {} end
		input.done = true
		body = carry.lines or {}
	else
		if #paths == 0 then return usage("wall") end
		local read, refusal = fileLines(state, session, "wall", paths[1])
		if read == nil then return false, { refusal } end
		body = read
	end
	if #body == 0 then
		-- Nothing to say is nothing said, and no banner either: a wall of one blank
		-- banner on four screens is the one thing a broadcast must not be.
		return true, {}
	end
	local now = CeroSecOS.clockOf(env)
	local when = "??:??"
	if now ~= nil then when = CeroSecOS.formatTime(now, "%H:%M") end
	local out = {
		"Broadcast Message from " .. CeroSecOS.userOf(session) .. "@"
			.. CeroSecOS.hostname(state),
		"        (" .. (session.line or CeroSecOS.CONSOLE_LINE) .. ") at " .. when
			.. " ...",
		"",
	}
	for i = 1, #body do out[#out + 1] = body[i] end
	-- Only the MACHINE can put a line on a screen that is not this job's, so what
	-- comes back is an order and not output. Nothing is printed where it was typed:
	-- the console it was typed at is one of the screens it reaches.
	return true, {}, "wall", { lines = out }
end

commands.tee = function(state, session, args, env, stdin)
	local flags, paths = flagsOf(args, "a")
	if flags == nil then return badOption("tee", paths) end
	if #paths < 1 then return usage("tee") end
	-- tee is a filter and its input is the pipe: `tee f` with nothing on its left
	-- has nothing to copy.
	if type(stdin) ~= "table" then return usage("tee") end
	stdin.want = true

	local carry = stdin.carry
	if carry.wrote == nil then carry.wrote = {} end
	-- Every line of this turn's chunk gets its own "\n", including the last
	-- one -- writeFile's append is a raw concat now, so the terminator
	-- between one turn's text and the next has to be put here -- UNLESS this
	-- really is the pipe's last line and it had none of its own (input.open
	-- at eof), the one turn tee must leave open behind it too.
	local text = table.concat(stdin.lines, "\n")
	if text ~= "" and not (stdin.eof and stdin.open) then text = text .. "\n" end
	local out, okAll = {}, true
	for i = 1, #paths do
		local path = paths[i]
		-- The FIRST turn opens the file -- replaced, or added to with -a, exactly as
		-- ">" and ">>" do -- and every turn after it appends, because tee is called
		-- once per turn of the pipe and no file is held open between them. The
		-- separating newline is writeFile's and not this command's: it puts one in
		-- when what is already there is not empty, which is the only place that
		-- decision can be made correctly.
		local first = carry.wrote[path] ~= true
		-- The first turn of a pipe is very often an EMPTY one -- the rightmost
		-- stage runs before the one on its left has written anything -- and that
		-- turn is what OPENS the file: replaced and left empty, exactly as ">"
		-- leaves an empty file behind for a command that printed nothing.
		--
		-- With -a there is nothing to open: the file is added to, and adding
		-- nothing has to add nothing. (So `tee -a f` on a pipe that never carried
		-- a line leaves a missing f missing, where a real one would make it. One
		-- empty file, and the alternative was a stray newline in every -a.)
		local opening = first and flags.a ~= true
		if opening or text ~= "" then
			local done, reason = CeroSecOS.writeFile(state, session, path, text,
				not first or flags.a == true, CeroSecOS.clockOf(env))
			if done == nil then
				okAll = false
				out[#out + 1] = "tee: " .. path .. ": " .. CeroSecOS.strerror(reason)
			else
				carry.wrote[path] = true
			end
		end
	end
	if not okAll then
		-- A file it could not write is a refusal, and the copy still goes on: that
		-- is what tee does with one bad file out of three.
		stdin.done = true
		return false, out
	end
	for i = 1, #stdin.lines do out[#out + 1] = stdin.lines[i] end
	if stdin.eof and stdin.open then out.open = true end
	return true, out
end

--
-- find
--
-- Depth-first, one path a line, and the path printed is the one that was TYPED
-- with the names walked into it -- `find . -name "*.txt"` answers "./notes.txt",
-- exactly as it does on a real machine, because what find prints is the path it
-- arrived by and not a name it looked up afterwards.
--
-- -print is implied when no action is given, which is what POSIX says in so many
-- words. It is accepted anyway, because a survivor who has used find will type
-- it, and a find that refused it would be a find that argued.
--
-- The tests are AND-ed, which is the only way this one combines them: there is
-- no -o, no -a and no parentheses. What is here is the two tests, the action that
-- is implied when none is named, and -exec -- what a survivor needs to find a file
-- on a disk with five hundred nodes on it and then do something to it, and the
-- manual says exactly that.
--
-- One consequence worth knowing, and it is the MACHINE's rule rather than find's:
-- a walk that met a directory it may not read comes back UNSUCCESSFUL, and an
-- unsuccessful command's lines are a refusal here -- they go to the screen and
-- never down a pipe. So `find / | wc -l` as an ordinary account prints the paths
-- and counts nothing, exactly as `cat good bad | wc -l` does. A real find has a
-- second channel for that and this machine has never had one.
--

-- One name against a shell glob. "*" is any run, "?" is one character, "[...]"
-- is one of a set with ranges and a leading "!" or "^" to negate it. The same
-- three sh has had since the sixth edition -- and the only three this shell's
-- own pathname expansion uses too (see CeroSecOS.expandGlob below): a fourth
-- would be one the shell could not spell.
--
-- Walked rather than turned into a Lua pattern: a name carrying "%" or "-" would
-- have to be escaped into one, and an escaper is a second place for the grammar
-- to live.
function CeroSecOS.globMatch(name, pattern)
	if type(name) ~= "string" or type(pattern) ~= "string" then return false end
	-- ni, pi: where the walk stands. star, back: the last "*" met and what it had
	-- swallowed, so a mismatch after one goes back and lets it swallow one more.
	-- That is what makes this linear rather than a recursion, and it is bounded by
	-- the two lengths.
	local ni, pi = 1, 1
	local star, back = nil, nil
	while ni <= #name do
		local p = string.sub(pattern, pi, pi)
		if p == "*" then
			star = pi
			back = ni
			pi = pi + 1
		elseif p == "?" then
			ni = ni + 1
			pi = pi + 1
		elseif p == "[" then
			-- The set, up to the closing bracket. A "[" with no "]" behind it is
			-- not a set and stands for itself, which is what sh does with one.
			local close = string.find(pattern, "]", pi + 2, true)
			if close == nil then
				if p ~= string.sub(name, ni, ni) then
					if star == nil then return false end
					pi = star + 1
					back = back + 1
					ni = back
				else
					ni = ni + 1
					pi = pi + 1
				end
			else
				local body = string.sub(pattern, pi + 1, close - 1)
				local negate = false
				if string.sub(body, 1, 1) == "!" or string.sub(body, 1, 1) == "^" then
					negate = true
					body = string.sub(body, 2)
				end
				local c = string.sub(name, ni, ni)
				local held = false
				local k = 1
				while k <= #body do
					local from = string.sub(body, k, k)
					if string.sub(body, k + 1, k + 1) == "-" and k + 2 <= #body then
						local to = string.sub(body, k + 2, k + 2)
						if string.byte(c) >= string.byte(from)
								and string.byte(c) <= string.byte(to) then
							held = true
						end
						k = k + 3
					else
						if c == from then held = true end
						k = k + 1
					end
				end
				if held == negate then
					if star == nil then return false end
					pi = star + 1
					back = back + 1
					ni = back
				else
					ni = ni + 1
					pi = close + 1
				end
			end
		elseif p ~= "" and p == string.sub(name, ni, ni) then
			ni = ni + 1
			pi = pi + 1
		elseif star ~= nil then
			pi = star + 1
			back = back + 1
			ni = back
		else
			return false
		end
	end
	-- What is left of the pattern may only be stars.
	while string.sub(pattern, pi, pi) == "*" do pi = pi + 1 end
	return pi > #pattern
end

--
-- Pathname expansion (globbing)
--
-- A word's own text and a MASK of the same length, one character a byte:
-- "g" where that byte came from someplace unquoted and may still be read as
-- "*", "?" or "[", "l" everywhere else -- literal text, a quoted run, an
-- escaped character, the value of a quoted "$x", a right-hand side of "=", an
-- arithmetic expansion. CeroSecOSVM.lua's expandStep builds this mask beside
-- the field itself; nothing here re-derives quoting, it only reads the answer.
--
-- One path component is a pattern when ANY of its "*", "?" or "[" sits on a
-- "g" byte. A component that mixes a quoted metacharacter with an unquoted one
-- is rarer than the rest of this file worries about; it is read as plain text,
-- which is the same answer an escaper-free matcher gives a pattern it cannot
-- spell (see the comment on CeroSecOS.globMatch above).
--
-- nil when the word held no unquoted metacharacter at all -- the common case,
-- and the caller's sign to leave the word exactly as typed. Otherwise an array
-- of the paths that matched, sorted, which may be empty: an empty answer is
-- the caller's cue to fall back on the word AS WRITTEN (see CeroSecOS.jobStep's
-- caller), which is the one and only reason `cp -r /mnt/* x` on an empty /mnt
-- still says "/mnt/*: No such file or directory" -- a shell with nothing to glob to hands
-- the program the star.

-- What a glob's walk costs, past the flat command charge every field already
-- gets: a pattern is CeroSecOS.globMatch run once per entry of every
-- directory it opens, the same shape grep's BRE_STEPS_PER charges for a
-- pattern run over every byte of a line. CeroSecOS.expandGlob hands back how
-- many entries it visited and CeroSecOSVM's globFields turns that into debt,
-- the way it already turns a PATH walk's extra directories into debt.
--
-- Three, measured against `while true; do echo f*; done` over a directory
-- filled to CeroSecOS.MAX_DIR_ENTRIES (96): at 64 (grep's own rate) the
-- charge was too small to be seen against STEP_COST_COMMAND and the loop
-- ran the ceiling on real time instead of steps, 6-7 ms against a 4 ms
-- budget (tests/hostile_test.lua's "echo * over a wide directory"). At
-- three the same loop holds 0.76 ms.
CeroSecOS.GLOB_ENTRIES_PER = 3

local function joinPath(base, absolute, name)
	if base == "" then
		if absolute then return "/" .. name end
		return name
	end
	return base .. "/" .. name
end

-- Second return is true when text ends in "/" -- sh keeps that slash on
-- every match ("echo */" prints "onlydir/") and restricts the last
-- component to directories, the same restriction a non-glob last
-- component ending in "/" already gets by simply not being the last one.
local function splitPatternComponents(text, mask)
	local comps = {}
	local n = #text
	local start = 1
	local i = 1
	while i <= n + 1 do
		if i > n or string.sub(text, i, i) == "/" then
			if i > start then
				local ctext = string.sub(text, start, i - 1)
				local cmask = string.sub(mask, start, i - 1)
				local isGlob = false
				for k = 1, #ctext do
					local c = string.sub(ctext, k, k)
					if (c == "*" or c == "?" or c == "[")
							and string.sub(cmask, k, k) == "g" then
						isGlob = true
						break
					end
				end
				comps[#comps + 1] = { text = ctext, glob = isGlob }
			end
			start = i + 1
		end
		i = i + 1
	end
	local trailingSlash = n > 0 and string.sub(text, n, n) == "/"
	return comps, trailingSlash
end

function CeroSecOS.expandGlob(state, session, text, mask)
	if type(text) ~= "string" or text == "" then return nil end
	if type(mask) ~= "string" or #mask ~= #text then mask = string.rep("l", #text) end

	local comps, trailingSlash = splitPatternComponents(text, mask)
	local any = false
	for i = 1, #comps do
		if comps[i].glob then any = true end
	end
	if not any then return nil end

	local absolute = string.sub(text, 1, 1) == "/"
	local bases = { "" }
	local visited = 0
	for ci = 1, #comps do
		local comp = comps[ci]
		local isLast = ci == #comps
		local nextBases = {}
		for bi = 1, #bases do
			local base = bases[bi]
			if comp.glob then
				local dirPath = base
				if dirPath == "" then dirPath = absolute and "/" or "." end
				local node = CeroSecOS.getNode(state, session, dirPath)
				-- No entry, not a directory, or unreadable: no match down this
				-- branch, and silently -- the same answer "no such file" gives
				-- a literal component, and the same one a real glob gives a
				-- directory it may not read (see docs/SCRIPTING.md).
				if node ~= nil and node.type == "dir"
						and CeroSecOS.can(state, session, node, "r") then
					local names = CeroSecOS.childNames(node)
					visited = visited + #names
					for ni = 1, #names do
						local name = names[ni]
						local dotOk = string.sub(comp.text, 1, 1) == "."
							or string.sub(name, 1, 1) ~= "."
						if dotOk and CeroSecOS.globMatch(name, comp.text) then
							local candidate = joinPath(base, absolute, name)
							if isLast then
								-- "*/" only matches directories, and keeps the
								-- slash it was typed with (POSIX.2 2.13.3).
								if trailingSlash then
									local cn = CeroSecOS.getNode(state, session, candidate)
									if cn ~= nil and cn.type == "dir" then
										nextBases[#nextBases + 1] = candidate .. "/"
									end
								else
									nextBases[#nextBases + 1] = candidate
								end
							else
								local cn = CeroSecOS.getNode(state, session, candidate)
								if cn ~= nil and cn.type == "dir" then
									nextBases[#nextBases + 1] = candidate
								end
							end
						end
					end
				end
			else
				local candidate = joinPath(base, absolute, comp.text)
				local node = CeroSecOS.getNode(state, session, candidate)
				if node ~= nil and (isLast or node.type == "dir") then
					nextBases[#nextBases + 1] = candidate
				end
			end
		end
		bases = nextBases
		if #bases == 0 then break end
	end

	table.sort(bases)
	return bases, visited
end

-- The last component of a path as it was typed, for -name to judge. The path
-- itself for a path with no slash in it, which is what -name judges about ".".
local function lastComponent(path)
	local out = path
	while true do
		local p = string.find(out, "/", 1, true)
		if p == nil then break end
		out = string.sub(out, p + 1)
	end
	if out == "" then return path end
	return out
end

--
-- -exec, the one thing find does besides print
--
-- POSIX.2's two forms, and both of them are here:
--
--   find . -name "*.log" -exec rm {} \;      once per name found
--   find . -name "*.log" -exec grep x {} +   as few times as it can
--
-- An argument that is exactly "{}" is the name found; anything else is passed
-- through as it was written, which is POSIX's own rule -- so `-exec grep x {} \;`
-- works and `-exec grep x{} \;` hands grep a name with the braces still in it.
-- The `\;` a player types is the shell taking the meaning off the semicolon, so
-- what reaches here is a lone ";" -- and a `+` is a lone "+".
--
-- WHAT IT COSTS, which is why this command is written the way it is. Every exec
-- is a COMMAND: it walks PATH, reads files, writes them. So find runs
-- FIND_EXEC_TURN of them and hands the machine back, and the turn is charged the
-- one command the engine charges any command -- which is the honest price of it,
-- the exec being the work in the turn and the rest of it being find looking up
-- where it had got to.
--
-- A command that ran a hundred of them in one call would overspend a pass's
-- budget a hundred times over, which is the one thing the whole step machine
-- exists to prevent: a step is counted once it is taken, so the most a pass may
-- go over is ONE command's worth, and tests/hostile_test.lua holds every call to
-- that. So find keeps where it had got to in the frame's own carry and asks for
-- another turn, exactly as `sort` does when it is reading a pipe a line at a
-- time. A sweep of a hundred files takes a few seconds of game time and trickles,
-- like every other long thing on this machine; `+` is what turns it back into one
-- command, which is the very reason POSIX has that form.
CeroSecOS.FIND_EXEC_TURN = 1

-- How many names one gathered exec hands over at a time. A real `+` fills the
-- argument list (ARG_MAX); what bounds one here is the number of them, because a
-- name is up to MAX_NAME bytes and the line is a table -- so a disk full of
-- matches is eight commands and not one enormous one.
CeroSecOS.FIND_EXEC_BATCH = 64

-- What one exec runs in, which is not what find runs in: nobody is standing
-- behind a command find started, and what it writes is find's output and not a
-- screen. Same shape the shell hands any command (see the head of shPath).
local function execShell(sh)
	return { path = shPath(sh), tty = false, keys = false }
end

-- One command, with {} replaced by the names it is for. A fresh array every
-- time, because runArgs is allowed to change what it is handed (the tilde).
local function execArgs(argv, names)
	local out = {}
	for i = 1, #argv do
		if argv[i] == "{}" then
			for k = 1, #names do out[#out + 1] = names[k] end
		else
			out[#out + 1] = argv[i]
		end
	end
	return out
end

-- Run it and put what it printed into find's own output. Two answers, because
-- they are two different questions and find treats them differently:
--
--   what the PRIMARY evaluates to -- true when the command finished on nought,
--     which is what makes `-exec test -f {} \; -exec rm {} \;` read the way it
--     looks: the expression is AND-ed and the second does not run where the first
--     was false. A command that merely failed is not an error of find's.
--   whether find itself met an ERROR, which is a command it could not RUN at all.
--     That is what puts find's own exit status above nought, exactly as a tree it
--     could not read does.
--
-- A command that asks a QUESTION cannot be answered: there is nobody behind an
-- exec, and its out-of-band order must not travel out through find. It is refused
-- with the line the engine already gives a command in that position -- the same
-- one a cron line and a pipeline stage get -- and nothing of the order goes on.
local function execRun(state, session, env, sh, argv, names, out)
	local args = execArgs(argv, names)
	-- A word the SHELL is, which find cannot run for the reason sudo cannot: find
	-- execs a PROGRAM, and there is no /bin/cd for it to find. Same answer, in the
	-- name that was looked up (see sudoRun).
	if CeroSecOS.isShellWord(args[1]) or CeroSecOS.SHELL_BUILTINS[args[1]] then
		out[#out + 1] = args[1] .. ": not found"
		return false, true
	end
	local ok, lines, control = CeroSecOS.runArgs(state, session, args, nil, env, nil,
		execShell(sh))
	for i = 1, #(lines or {}) do out[#out + 1] = lines[i] end
	if control ~= nil then
		out[#out + 1] = args[1] .. ": not a terminal"
		return false, true
	end
	-- A name nothing answers to is a command find could not run, and the lookup's
	-- own line is what says so.
	if not ok and #(lines or {}) == 1
			and lines[1] == args[1] .. ": not found" then
		return false, true
	end
	return ok, false
end

-- The expression, read once: the two tests, and the actions in the order they
-- were written -- find evaluates left to right and `-print -exec` is not
-- `-exec -print`. nil for a line find cannot carry out, plus the flag it did not
-- know where that is what was wrong with it.
local function findParse(args)
	local name, kind = nil, nil
	local paths, actions = {}, {}
	local i = 2
	while i <= #args do
		local a = args[i]
		if a == "-name" then
			name = args[i + 1]
			if name == nil then return nil end
			i = i + 2
		elseif a == "-type" then
			kind = args[i + 1]
			if kind ~= "f" and kind ~= "d" then return nil end
			i = i + 2
		elseif a == "-print" then
			actions[#actions + 1] = { print = true }
			i = i + 1
		elseif a == "-exec" then
			local argv, term = {}, nil
			local k = i + 1
			while k <= #args do
				if args[k] == ";" or args[k] == "+" then
					term = args[k]
					break
				end
				argv[#argv + 1] = args[k]
				k = k + 1
			end
			-- A -exec with no terminator, or with nothing to run, is not a line
			-- this can carry out -- and neither is a `+` whose {} is not the last
			-- word of it: POSIX puts the names at the end of a gathered line,
			-- there being no room in one for a second place to put them.
			if term == nil or #argv == 0 then return nil end
			if term == "+" and argv[#argv] ~= "{}" then return nil end
			actions[#actions + 1] = { argv = argv, batch = term == "+" }
			i = k + 1
		elseif string.sub(a, 1, 1) == "-" and a ~= "-" then
			return nil, a
		else
			paths[#paths + 1] = a
			i = i + 1
		end
	end
	if #paths == 0 then return nil end
	return { name = name, kind = kind, paths = paths, actions = actions }
end

commands.find = function(state, session, args, env, stdin, sh)
	local plan, unknown = findParse(args)
	if plan == nil then
		-- find is not getopt(3): its primaries are words, and 4.4BSD-Lite2
		-- usr.bin/find/option.c refuses one it does not know with
		-- errx(1, "%s: unknown option", *argv) -- the word, and no usage.
		if unknown ~= nil then return fail("find", unknown, "unknown option") end
		return usage("find")
	end
	local name, kind, actions = plan.name, plan.kind, plan.actions

	-- Where the last turn had got to, or nothing at all on the first one.
	local carry = nil
	if type(sh) == "table" and type(sh.carry) == "table" then carry = sh.carry end

	if carry == nil then
		-- What the walk found, in walk order: a name, or a refusal about a tree it
		-- could not read. Kept as items rather than as lines because the actions
		-- turn a name into whatever they print, while a refusal is already a line.
		local items, okAll = {}, true

		-- Does this node answer the tests? Both are AND-ed and either may be absent.
		local function wanted(path, node)
			if kind == "f" and node.type ~= "file" then return false end
			if kind == "d" and node.type ~= "dir" then return false end
			if name ~= nil and not CeroSecOS.globMatch(lastComponent(path), name) then
				return false
			end
			return true
		end

		-- The walk. Depth-first and PRE-order -- the directory before what is in
		-- it, which is find's own order and the reason `find /etc` starts with
		-- "/etc".
		--
		-- A directory the account may not read is named and not entered, and find
		-- says so about it the way it always has: the tree it could not read is a
		-- refusal, and the rest of the walk goes on. Bounded by the disk: there are
		-- MAX_NODES nodes on a machine and each is visited once.
		local function walk(path, node)
			if wanted(path, node) then items[#items + 1] = { p = path } end
			if node.type ~= "dir" then return end
			if not CeroSecOS.can(state, session, node, "r") then
				okAll = false
				items[#items + 1] = { e = "find: " .. path .. ": Permission denied" }
				return
			end
			local names = CeroSecOS.listedNames(node, true)
			local prefix = path
			if string.sub(prefix, -1) ~= "/" then prefix = prefix .. "/" end
			for k = 1, #names do
				walk(prefix .. names[k], node.children[names[k]])
			end
		end

		for k = 1, #plan.paths do
			local path = plan.paths[k]
			-- A link NAMED on the line is not followed: find walks the tree it was
			-- given, and a link is a leaf of it -- which is find's own default (there
			-- is no -follow here) and what keeps a loop of links from being a walk
			-- with no end.
			local node, reason = CeroSecOS.getNode(state, session, path, true)
			if node == nil then
				okAll = false
				items[#items + 1] = { e = "find: " .. path .. ": " .. CeroSecOS.strerror(reason) }
			elseif node.dead then
				okAll = false
				items[#items + 1] = { e = "find: " .. path .. ": No such file or directory" }
			else
				walk(path, node)
			end
		end

		-- Nothing to do but print, which is what find does when no action is named
		-- -- POSIX's own wording -- and that answer is one command's worth of work
		-- and needs no second turn.
		local runs = 0
		for a = 1, #actions do
			if actions[a].argv ~= nil then runs = runs + 1 end
		end
		if runs == 0 then
			local out = {}
			for k = 1, #items do
				if items[k].p ~= nil then
					out[#out + 1] = items[k].p
				else
					out[#out + 1] = items[k].e
				end
			end
			return okAll, out
		end

		-- An action takes the implied -print away, and an explicit one puts it back
		-- where it was written.
		carry = { items = items, ok = okAll, i = 1, a = 1, gathered = {}, phase = "names" }
		for a = 1, #actions do carry.gathered[a] = {} end
	end

	-- One turn: FIND_EXEC_TURN commands and no more, then the machine gets its
	-- pass back. Everything else here -- the printing, the gathering -- is free
	-- and happens on whichever turn it is reached.
	local out = {}
	local ran = 0

	while carry.phase == "names" and ran < CeroSecOS.FIND_EXEC_TURN do
		local item = carry.items[carry.i]
		if item == nil then
			carry.phase = "batches"
			carry.i = 1
			carry.a = 1
			break
		end
		if item.e ~= nil then
			out[#out + 1] = item.e
			carry.i = carry.i + 1
			carry.a = 1
		else
			local action = actions[carry.a]
			if action == nil then
				carry.i = carry.i + 1
				carry.a = 1
			elseif action.print then
				out[#out + 1] = item.p
				carry.a = carry.a + 1
			elseif action.batch then
				local names = carry.gathered[carry.a]
				names[#names + 1] = item.p
				carry.a = carry.a + 1
			else
				local ok, problem =
					execRun(state, session, env, sh, action.argv, { item.p }, out)
				ran = ran + 1
				if problem then carry.ok = false end
				-- False stops the actions after it for this name, and that is all it
				-- does: a command that answered "no" is not an error.
				if ok then
					carry.a = carry.a + 1
				else
					carry.i = carry.i + 1
					carry.a = 1
				end
			end
		end
	end

	-- The gathered forms, once the walk's own actions are done with: the names
	-- FIND_EXEC_BATCH at a time, in the order the actions were written. A `+` is
	-- always true in find's expression, so a command that failed still leaves the
	-- rest of them to run -- but find itself has met an error and says so.
	while carry.phase == "batches" and ran < CeroSecOS.FIND_EXEC_TURN do
		local names = carry.gathered[carry.a]
		if names == nil then
			carry.phase = "done"
			break
		end
		if actions[carry.a].batch ~= true or carry.i > #names then
			carry.a = carry.a + 1
			carry.i = 1
		else
			local batch = {}
			while #batch < CeroSecOS.FIND_EXEC_BATCH and carry.i <= #names do
				batch[#batch + 1] = names[carry.i]
				carry.i = carry.i + 1
			end
			local _, problem = execRun(state, session, env, sh, actions[carry.a].argv,
				batch, out)
			ran = ran + 1
			if problem then carry.ok = false end
		end
	end

	-- What this turn cost, for the shell to charge: one command apiece.

	if carry.phase ~= "done" then
		-- Another turn. What it has printed so far goes out now, the way a stage of
		-- a pipeline writes as it goes: a sweep is not silent until it ends.
		if type(sh) == "table" then
			sh.again = true
			sh.carry = carry
		end
		return true, out
	end
	return carry.ok, out
end

--
-- at, atq, atrm: one thing, once, at a time you name
--
-- The three programs 1993 had, under the three names it had them under -- atq is
-- `at -l` and atrm is `at -r`, which is how the two of them were built on every
-- BSD, and POSIX.2 gives at those two flags as well. The queue, the file a job is
-- kept in and the reason a late job still runs are in CeroSecOSCron.lua, beside
-- cron's; what is here is the command.
--
-- WHERE THE COMMANDS COME FROM. From the standard input, which is at's own rule --
-- "at reads commands from standard input" -- and on this machine standard input is
-- a PIPE and nothing else: there is no keyboard behind a command here (see the
-- head of stdinOf). So it is
--
--   admin@ksp-04-11:~$ echo halt | at 04:00
--   job 1 at Fri Jul  9 04:00:00 1993
--   admin@ksp-04-11:~$ cat plan.sh | at 23:30
--
-- and `at 04:00` with nothing on its left prints its usage line, which is the
-- answer every other command that reads a pipe gives in that position. The manual
-- page says so in those words.
--
-- The FILE is written as root, on this account's behalf, exactly as `crontab -e`
-- writes a crontab and for the same reason: a queued job runs AS somebody, so the
-- queue is root's and this is the one program that reaches into it.
--

-- What at prints when it has queued one. at(1)'s own line, with the machine's own
-- date in it.
local function atQueued(n, when)
	return "job " .. tostring(n) .. " at " .. CeroSecOS.formatDate(when)
end

-- The listing `at -l` and `atq` print: the number and when it is due, one a line,
-- and only the account's own jobs unless it is root looking -- which is what atq
-- does everywhere.
local function atList(state, session)
	local me = CeroSecOS.userOf(session)
	local jobs = CeroSecOS.atJobs(state)
	local out = {}
	for i = 1, #jobs do
		if me == "root" or jobs[i].user == me then
			out[#out + 1] = tostring(jobs[i].n) .. "  " .. CeroSecOS.formatDate(jobs[i].when)
		end
	end
	return true, out
end

-- And `at -r` / `atrm`: the job goes. Somebody else's is not yours to remove, and
-- root's rule is root's everywhere -- the same rule `kill` runs on, in the same
-- words.
local function atRemove(state, session, args, from, who, env)
	if args[from] == nil then return usage(who) end
	local me = CeroSecOS.userOf(session)
	local jobs = CeroSecOS.atJobs(state)
	local out, okAll = {}, true
	for i = from, #args do
		local n = tonumber(args[i])
		local found = nil
		for k = 1, #jobs do
			if n ~= nil and jobs[k].n == n then found = jobs[k] end
		end
		if found == nil then
			okAll = false
			out[#out + 1] = who .. ": " .. args[i] .. ": no such job"
		elseif me ~= "root" and found.user ~= me then
			okAll = false
			out[#out + 1] = who .. ": " .. args[i] .. ": Operation not permitted"
		else
			local gone, reason = CeroSecOS.removeNode(state, CeroSecOS.rootSession(),
				CeroSecOS.atJobPath(found.n), false, CeroSecOS.clockOf(env))
			if gone == nil then
				okAll = false
				out[#out + 1] = who .. ": " .. args[i] .. ": " .. CeroSecOS.strerror(reason)
			end
		end
	end
	return okAll, out
end

commands.at = function(state, session, args, env, stdin)
	if args[2] == nil then return usage("at") end
	if args[2] == "-l" then
		if #args > 2 then return usage("at") end
		return atList(state, session)
	end
	if args[2] == "-r" then return atRemove(state, session, args, 3, "at", env) end
	if #args ~= 2 then return usage("at") end

	local now = CeroSecOS.clockOf(env)
	if now == nil then return fail("at", nil, "no clock") end
	local when = CeroSecOS.atWhen(args[2], now)
	if when == nil then return usage("at") end

	-- The commands, off the pipe. Nothing can be queued before the end of it: the
	-- last line may still be coming, so what has arrived is kept -- under the
	-- ceiling a pipe itself has -- until the pipe closes. Exactly `sort`'s shape,
	-- and for the same reason.
	if type(stdin) ~= "table" then return usage("at") end
	stdin.want = true
	local carry = stdin.carry
	for i = 1, #stdin.lines do
		if not holdLine(carry, stdin.lines[i]) then carry.over = true end
	end
	if carry.over then
		stdin.done = true
		return fail("at", nil, "input too large")
	end
	if not stdin.eof then return true, {} end

	local cmd = table.concat(carry.lines or {}, "\n")
	-- A job with nothing in it is not a job: at reads its commands and there were
	-- none. Real at queues an empty script and runs it to no effect; this says so
	-- instead, because a queue with an empty job in it is a line a survivor cannot
	-- read the point of.
	if cmd == "" then return fail("at", nil, "no commands") end

	local n = CeroSecOS.atFree(state)
	if n == nil then return fail("at", nil, "queue full") end
	local path = CeroSecOS.atJobPath(n)
	local file = CeroSecOS.newFile("root", CeroSecOS.AT_JOB_MODE,
		CeroSecOS.atText(CeroSecOS.userOf(session), when, cmd))
	local made, reason = CeroSecOS.createNode(state, CeroSecOS.rootSession(), path, file,
		CeroSecOS.clockOf(env))
	if made == nil then return fail("at", path, reason) end
	return true, { atQueued(n, when) }
end

-- The two other names, which are the same programs: atq(1) is `at -l` and atrm(1)
-- is `at -r`, and they are separate files in /bin because they were separate files
-- in /bin.
commands.atq = function(state, session, args, env)
	if #args > 1 then return usage("atq") end
	return atList(state, session)
end

commands.atrm = function(state, session, args, env)
	return atRemove(state, session, args, 2, "atrm", env)
end

--
-- tar: many files in one file
--
-- `tar cf <archive> <path>...` stores, `tar xf <archive>` puts back, and
-- `tar tf <archive>` lists; `v` names every member as it is handled. Three keys
-- and one modifier, which is what tar(1) had in 1993, called the way tar was
-- called then: one word of letters with no dash in front of it, tar being older
-- than getopt. There is no `z` -- compress(1) was a program of its own and this
-- machine has neither -- and no `-C`, no `-p`, no wildcards.
--
-- What it is FOR on a machine this size: a home on a floppy. A floppy holds one
-- maximal file (4096 bytes), and `tar cf /mnt/home.tar ~` is how a survivor
-- carries his notes to the machine next door.
--
-- WHAT IS OURS, and it is on the manual's deviations page: the container. A real
-- tar is 512-byte blocks with a 512-byte header in front of every member, so a
-- ten-byte note would cost a kilobyte of the floppy it was being carried on -- a
-- quarter of the disk for one note, on a machine whose whole drive is 64K. So the
-- container here is TEXT: a header line, and the bytes after it.
--
-- What it is NOT is dishonest about the price. The archive is an ordinary file,
-- written through the ordinary write path, and every byte of it counts against
-- the disk it lands on: `tar cf` of a home that does not fit answers
-- "disk full" exactly as `cp` would, and `df` moves by what the archive weighs.
-- And what a real tar and this one agree about is everything a member CARRIES --
-- the name, the mode, the owner, the group, the size, the time -- and about who
-- may put each of those back: root restores the owner, anybody else owns what he
-- extracts, which is tar's rule everywhere.
--

-- The first line of an archive, and the one thing that says it is one.
CeroSecOS.TAR_MAGIC = "CeroSec tar 1"

-- The three kinds of member. A device is none of them: there is nothing in a
-- /dev entry to carry and a real tar writes a header with no data for one, which
-- would be a promise this machine could not keep on the way back.
CeroSecOS.TAR_KINDS = { f = "file", d = "dir", l = "link" }

-- members -> the text of an archive. Pure: the members are plain tables
--   { kind = "f"|"d"|"l", mode = 644, owner = "admin", group = "users",
--     mtime = 0, name = "notes.txt", data = "..." }
-- and nothing here looks at a disk. A member with no data has no line for it,
-- which is what makes an empty file and a directory cost their header and
-- nothing more.
function CeroSecOS.tarText(members)
	local out = { CeroSecOS.TAR_MAGIC }
	for i = 1, #(members or {}) do
		local m = members[i]
		local data = m.data or ""
		out[#out + 1] = m.kind .. " " .. tostring(m.mode) .. " " .. tostring(m.owner)
			.. " " .. tostring(m.group) .. " " .. tostring(m.mtime or 0)
			.. " " .. tostring(#data) .. " " .. tostring(m.name)
		if #data > 0 then out[#out + 1] = data end
	end
	return table.concat(out, "\n") .. "\n"
end

-- And back: the text of an archive -> its members, or nil for a file that is not
-- one. The data is taken by its BYTE COUNT and never by looking for the next
-- line, because a file's contents may have newlines in it and the count is the
-- only thing that says where it ends -- which is the whole reason the header
-- carries a size, here as in a real tar.
function CeroSecOS.tarMembers(text)
	if type(text) ~= "string" then return nil end
	local head = CeroSecOS.TAR_MAGIC .. "\n"
	if string.sub(text, 1, #head) ~= head then return nil end
	local at = #head + 1
	local members = {}
	while at <= #text do
		local nl = string.find(text, "\n", at, true)
		if nl == nil then return nil end
		local line = string.sub(text, at, nl - 1)
		at = nl + 1
		if line ~= "" then
			local kind, mode, owner, group, mtime, bytes, name =
				string.match(line, "^(%a) (%d+) (%S+) (%S+) (%d+) (%d+) (%S+)$")
			if kind == nil or CeroSecOS.TAR_KINDS[kind] == nil then return nil end
			local n = tonumber(bytes)
			if n == nil or n > CeroSecOS.MAX_FILE_BYTES then return nil end
			local data = ""
			if n > 0 then
				data = string.sub(text, at, at + n - 1)
				if #data < n then return nil end
				-- Past the data AND past the newline that closes it.
				at = at + n + 1
			end
			members[#members + 1] = { kind = kind, mode = tonumber(mode),
				owner = owner, group = group, mtime = tonumber(mtime),
				name = name, data = data }
		end
	end
	return members
end

-- What `tar tv` prints for one member: the mode, who will own it, how big it is,
-- and the name -- in `ls -l`'s own columns and widths, so there is one long
-- listing on this machine and not two.
--
-- ONE cut from a real tar's tv line, and it is the sixty columns': tar(1) prints
-- the date as well, and a member's name here is a whole PATH rather than a name in
-- a directory -- the two together leave nothing for the path. The date is what
-- goes; the manual page says so, beside the command, the way `uptime`'s cut is
-- said beside uptime.
local function tarLine(m)
	local node = { type = CeroSecOS.TAR_KINDS[m.kind] or "file", owner = m.owner,
		group = m.group, mode = m.mode, mtime = m.mtime }
	if node.type == "dir" then node.children = {} end
	local head = CeroSecOS.permString(node)
		.. "  " .. CeroSecOS.padRight(CeroSecOS.truncate(m.owner or "?", L_OWNER), L_OWNER)
		.. "  " .. CeroSecOS.padLeft(tostring(#(m.data or "")), L_SIZE) .. "  "
	return head .. CeroSecOS.truncate(m.name, CeroSecOS.COLS - #head)
end

-- How many members tar handles before it hands the machine back. One, for the
-- reason `find -exec` does one exec: reading a file and building a header is a
-- command's worth of work, a tar of a full home is sixty of them, and a command
-- that did all sixty in one call would spend a pass's whole wall clock -- measured
-- at 0.9 ms for twenty files, against the 0.2 ms a command is charged. So a tar
-- trickles, a member a turn, and the pass it is in costs what any command costs.
CeroSecOS.TAR_TURN = 1

-- One member of the walk `c` makes, and the children of a directory pushed in
-- behind it so the order is pre-order: the directory before what is in it, exactly
-- as find walks and for the same reason -- a member whose directory came after it
-- could not be put back.
--
-- The NAME stored is the path as it was typed, which is what a 1993 tar stored:
-- `tar cf t.tar ~` stores /home/admin/... and puts it back there, `tar cf t.tar .`
-- stores ./... and puts it back wherever you are standing. The manual says which,
-- because the difference is the difference between restoring a home and restoring
-- it somewhere else.
local function tarGather(state, session, carry, verbose)
	local path = carry.queue[carry.i]
	carry.i = carry.i + 1
	local node, reason = CeroSecOS.getNode(state, session, path, true)
	if node == nil then
		carry.problems[#carry.problems + 1] = "tar: " .. path .. ": " .. CeroSecOS.strerror(reason)
		return
	end
	if node.dead then
		carry.problems[#carry.problems + 1] = "tar: " .. path .. ": No such file or directory"
		return
	end
	local kind = nil
	if node.type == "dir" then kind = "d"
	elseif node.type == "file" then kind = "f"
	elseif CeroSecOS.isLink(node) then kind = "l" end
	if kind == nil then
		carry.problems[#carry.problems + 1] =
			"tar: " .. path .. ": " .. CeroSecOS.strerror(CeroSecOS.notAFile(node))
		return
	end

	local data = ""
	if kind == "f" then
		if not CeroSecOS.can(state, session, node, "r") then
			carry.problems[#carry.problems + 1] = "tar: " .. path .. ": Permission denied"
			return
		end
		data = node.data or ""
	elseif kind == "l" then
		data = node.target or ""
	end
	carry.members[#carry.members + 1] = { kind = kind, mode = node.mode,
		owner = node.owner or "root", group = CeroSecOS.groupOf(node),
		mtime = CeroSecOS.mtimeOf(node), name = path, data = data }
	if verbose then carry.said[#carry.said + 1] = path end

	if kind ~= "d" then return end
	if not CeroSecOS.can(state, session, node, "r") then
		carry.problems[#carry.problems + 1] = "tar: " .. path .. ": Permission denied"
		return
	end
	local names = CeroSecOS.listedNames(node, true)
	local prefix = path
	if string.sub(prefix, -1) ~= "/" then prefix = prefix .. "/" end
	-- In behind this one, in order: the queue is the walk, so what is inserted here
	-- is what the next turns will do.
	for k = #names, 1, -1 do
		table.insert(carry.queue, carry.i, prefix .. names[k])
	end
end

-- One member, put back. nil when it went in, or the line that says why not.
--
-- The write is the ORDINARY one, on the account's own authority: an archive
-- cannot put a file where its owner could not have written one, which is the
-- whole of what keeps an archive off a floppy from being a way into a machine.
-- What is restored on top of it is the mode and the time always, and the owner
-- and the group only for root -- tar's rule on every Unix, and the reason a
-- survivor's own extraction leaves him owning what came out.
local function tarPut(state, session, m, now)
	local path = m.name
	local who = CeroSecOS.userOf(session)
	if m.kind == "d" then
		local node = CeroSecOS.getNode(state, session, path, true)
		if node == nil then
			local made, reason = CeroSecOS.createNode(state, session, path,
				CeroSecOS.newDir(who, m.mode, now), now)
			if made == nil then return "tar: " .. path .. ": " .. CeroSecOS.strerror(reason) end
		elseif node.type ~= "dir" then
			return "tar: " .. path .. ": File exists"
		end
	elseif m.kind == "l" then
		-- A link already at that name is REPLACED, which is what tar does with one:
		-- it unlinks and makes it again. Anything else at that name is not a link
		-- and is not something an archive may quietly write over.
		local node = CeroSecOS.getNode(state, session, path, true)
		if node ~= nil then
			if not CeroSecOS.isLink(node) then return "tar: " .. path .. ": File exists" end
			local gone, why = CeroSecOS.removeNode(state, session, path, false, now)
			if gone == nil then return "tar: " .. path .. ": " .. CeroSecOS.strerror(why) end
		end
		local made, reason = CeroSecOS.createNode(state, session, path,
			CeroSecOS.newLink(who, m.data, now), now)
		if made == nil then return "tar: " .. path .. ": " .. CeroSecOS.strerror(reason) end
	else
		local done, reason = CeroSecOS.writeFile(state, session, path, m.data, false, now)
		if done == nil then return "tar: " .. path .. ": " .. CeroSecOS.strerror(reason) end
	end
	-- And what the member carried about itself, onto the node that is there now.
	local node = CeroSecOS.getNode(state, session, path, true)
	if node == nil then return nil end
	if m.kind ~= "l" then node.mode = m.mode end
	node.mtime = m.mtime
	if who == "root" then
		node.owner = m.owner
		node.group = m.group
	end
	return nil
end

commands.tar = function(state, session, args, env, stdin, sh)
	local key = args[2]
	if key == nil or #args < 3 then return usage("tar") end
	local kind, verbose, wantFile = nil, false, false
	for i = 1, #key do
		local c = string.sub(key, i, i)
		if c == "c" or c == "x" or c == "t" then
			-- One key and not two: `tar cx` is two orders in one word and a real tar
			-- takes the first it meets, which is a line nobody meant to type.
			if kind ~= nil then return usage("tar") end
			kind = c
		elseif c == "v" then
			verbose = true
		elseif c == "f" then
			wantFile = true
		else
			-- Nor is tar: 4.4BSD-Lite2's is pax in tar mode, and
			-- bin/pax/options.c walks the key letters by hand and answers
			-- a letter it does not know with tar_usage() alone.
			return usage("tar")
		end
	end
	if kind == nil or not wantFile then return usage("tar") end

	local archive = args[3]
	local now = CeroSecOS.clockOf(env)

	-- Where the last turn had got to, or nothing at all on the first one. Both `c`
	-- and `x` take a member at a time (TAR_TURN) and hand the machine back, the way
	-- `find -exec` takes one exec: a member is a file read or a file written, which
	-- is a command's worth of work, and a tar of a home is sixty of them.
	local carry = nil
	if type(sh) == "table" and type(sh.carry) == "table" then carry = sh.carry end

	local function another(out, ok)
		if carry.phase ~= "done" and type(sh) == "table" then
			sh.again = true
			sh.carry = carry
			return true, out
		end
		return ok, out
	end

	if kind == "c" then
		if #args < 4 then return usage("tar") end
		if carry == nil then
			carry = { phase = "gather", queue = {}, i = 1, members = {}, said = {},
				problems = {} }
			for i = 4, #args do carry.queue[#carry.queue + 1] = args[i] end
		end
		local out = {}
		local did = 0
		while carry.phase == "gather" and did < CeroSecOS.TAR_TURN do
			if carry.queue[carry.i] == nil then
				carry.phase = "write"
				break
			end
			local before = #carry.said
			tarGather(state, session, carry, verbose)
			-- What this turn found out, said now rather than at the end: a tar of a
			-- home prints as it goes, the way `tar v` has always printed.
			for k = before + 1, #carry.said do out[#out + 1] = carry.said[k] end
			did = did + 1
		end
		if carry.phase ~= "write" then return another(out, true) end

		-- The archive itself, written through the ordinary write path on the
		-- account's own authority: one file, weighed against the disk like any other.
		carry.phase = "done"
		local text = CeroSecOS.tarText(carry.members)
		local done, reason = CeroSecOS.writeFile(state, session, archive, text, false, now)
		if done == nil then
			out[#out + 1] = "tar: " .. archive .. ": " .. CeroSecOS.strerror(reason)
			return false, out
		end
		for i = 1, #carry.problems do out[#out + 1] = carry.problems[i] end
		return #carry.problems == 0, out
	end

	-- Both of the others read the archive first, on the account's own authority.
	-- Read on the FIRST turn only: an archive somebody rewrote under an extraction
	-- would be two archives in one command.
	local members = carry ~= nil and carry.members or nil
	if members == nil then
		local node, reason = CeroSecOS.getNode(state, session, archive)
		if node == nil then return fail("tar", archive, reason) end
		if node.type ~= "file" then return fail("tar", archive, CeroSecOS.notAFile(node)) end
		if not CeroSecOS.can(state, session, node, "r") then
			return fail("tar", archive, "permission denied")
		end
		members = CeroSecOS.tarMembers(node.data or "")
		if members == nil then return fail("tar", archive, "not a tar archive") end
	end

	-- A listing is one command's worth whatever is in the archive: it reads the
	-- file it has already read and writes nothing.
	if kind == "t" then
		local out = {}
		for i = 1, #members do
			if verbose then
				out[#out + 1] = tarLine(members[i])
			else
				out[#out + 1] = members[i].name
			end
		end
		return true, out
	end

	if carry == nil then
		carry = { phase = "put", members = members, i = 1, ok = true }
	end
	local out = {}
	local did = 0
	while carry.phase == "put" and did < CeroSecOS.TAR_TURN do
		local m = carry.members[carry.i]
		if m == nil then
			carry.phase = "done"
			break
		end
		carry.i = carry.i + 1
		did = did + 1
		local refusal = tarPut(state, session, m, now)
		if refusal ~= nil then
			carry.ok = false
			out[#out + 1] = refusal
		elseif verbose then
			out[#out + 1] = m.name
		end
	end
	if carry.queue == nil and carry.phase == "put" and carry.members[carry.i] == nil then
		carry.phase = "done"
	end
	return another(out, carry.ok)
end

--
-- uptime and w
--
-- The two lines a survivor types to find out whether a machine is busy and who
-- is on it. Both are 4.4BSD's, and `w` is the one that opens with the other's
-- whole line, which is why they live together.
--
--   admin@ksp-04-11:~$ uptime
--    3:14PM  up 2 days,  4:03,  2 users,  load averages: 0.12, 0.08, 0.05
--
-- Every piece of that is uptime(1)'s: the leading space, the twelve-hour clock
-- with no space in front of the AM, the two spaces before "up", the plural on
-- "days" and not on "day", the two-column hour of the h:mm, the count of users,
-- and the three averages to two decimals.
--
-- ONE cut, and it is the sixty columns': BSD writes "load averages: 0.12, 0.08,
-- 0.05" and this writes "load 0.12 0.08 0.05". BSD's own words and commas are
-- nine columns of sixty, and the line would not fit the screen with them -- which
-- is the very cut `ruptime` already took here, and for the same reason (see
-- CeroSecOS.ruptimeLine, which cut three averages to one). The widest line this
-- can produce -- a machine up three-digit days with five sessions on it and every
-- job runnable -- is exactly sixty characters, and os_test pins that.
--

-- The clock as uptime and w print it: "3:14PM", twelve-hour, no leading zero on
-- the hour, and the hour of midnight is 12. Written here because two commands
-- print it and nothing else on this machine does -- `ls -l` and `last` print a
-- 24-hour stamp, which is the other format and stays where it is.
function CeroSecOS.clockText(now)
	local p = CeroSecOS.dateParts(now)
	local hour = p.hour
	local half = "AM"
	if hour >= 12 then half = "PM" end
	hour = math.fmod(hour, 12)
	if hour == 0 then hour = 12 end
	return tostring(hour) .. ":" .. CeroSecOS.twoDigits(p.min) .. half
end

-- How long the machine has been up, in uptime(1)'s own words: the days when
-- there are any, then the hours and minutes as "h:mm" -- or, under an hour,
-- "N mins", which is what BSD prints rather than "0:07".
function CeroSecOS.upText(seconds)
	if type(seconds) ~= "number" or seconds < 0 then seconds = 0 end
	seconds = math.floor(seconds)
	local mins = math.floor(seconds / 60)
	local days = math.floor(mins / 1440)
	mins = mins - days * 1440
	local hrs = math.floor(mins / 60)
	mins = mins - hrs * 60
	local out = ""
	if days > 0 then
		out = " " .. tostring(days) .. " day"
		if days > 1 then out = out .. "s" end
		out = out .. ","
	end
	-- uptime(1)'s own three shapes, in its own order: "h:mm" when there are both,
	-- "N hrs" when the minutes are nought, and "N mins" when there is no hour.
	if hrs > 0 and mins > 0 then
		return out .. " " .. CeroSecOS.padLeft(tostring(hrs), 2) .. ":"
			.. CeroSecOS.twoDigits(mins) .. ","
	end
	if hrs > 0 then
		if hrs == 1 then return out .. " 1 hr," end
		return out .. " " .. tostring(hrs) .. " hrs,"
	end
	if mins == 1 then return out .. " 1 min," end
	return out .. " " .. tostring(mins) .. " mins,"
end

--
-- The load average
--
-- What a load average has counted since the first one: how many jobs are able to
-- run. This machine's run queue is its job book, and CeroSecOS.liveJobs is what
-- counts it -- the same number `ruptime` broadcasts about a machine on the wire.
--
-- Three windows, because uptime(1) prints three: one minute, five and fifteen.
-- They are kept on the job BOOK -- runtime state like the jobs themselves, never
-- saved -- and moved by CeroSecOS.loadSample, which the scheduler calls once a
-- pass. A machine nobody has stepped yet has three zeros, which is the truth
-- about it.
--
-- The decay is NOT exp(): a first-order filter with the same time constant,
--
--     load <- load * W/(W+dt) + n * dt/(W+dt)
--
-- which needs one division and no library at all. Kahlua's math is a subset and
-- math.exp is not something to bet a number a player reads on; the shape is the
-- same -- a sample W seconds old has about a third of its weight left -- and it
-- is deterministic, which matters more here than the last decimal of a curve.
--
-- Sampled no oftener than every five seconds, which is the interval every Unix
-- has sampled its run queue at, so the cost is one division per window per five
-- seconds whatever the pass rate is.
CeroSecOS.LOAD_WINDOWS = { 60, 300, 900 }
CeroSecOS.LOAD_SAMPLE_MS = 5000

-- Move the three averages on, if it is time to. book is the machine's job book
-- (the table that holds `list`), nowMs the wall clock. true when it sampled.
function CeroSecOS.loadSample(book, nowMs)
	if type(book) ~= "table" or type(nowMs) ~= "number" then return false end
	if type(book.load) ~= "table" then book.load = { 0, 0, 0 } end
	local last = book.loadMs
	if type(last) ~= "number" then
		-- The first sample is the first sample: the averages start AT the run
		-- queue rather than climbing to it from zero, which is what a machine
		-- that has just been switched on with four jobs on it really looks like.
		book.loadMs = nowMs
		local n = CeroSecOS.liveJobs(book.list or {})
		book.load = { n, n, n }
		return true
	end
	local dt = nowMs - last
	if dt < CeroSecOS.LOAD_SAMPLE_MS then return false end
	-- A clock that went backwards -- a reload, a server restart -- is a sample
	-- interval nobody can use: start again rather than divide by a negative.
	if dt < 0 then
		book.loadMs = nowMs
		return false
	end
	book.loadMs = nowMs
	local secs = dt / 1000
	local n = CeroSecOS.liveJobs(book.list or {})
	for i = 1, #CeroSecOS.LOAD_WINDOWS do
		local w = CeroSecOS.LOAD_WINDOWS[i]
		local keep = w / (w + secs)
		book.load[i] = (book.load[i] or 0) * keep + n * (1 - keep)
	end
	return true
end

-- The three averages as the caller handed them over, each a number. A caller
-- with none is a machine nobody has stepped, which is three zeros.
local function loadOf(env)
	local out = { 0, 0, 0 }
	if type(env) ~= "table" or type(env.load) ~= "table" then return out end
	for i = 1, 3 do
		if type(env.load[i]) == "number" and env.load[i] >= 0 then out[i] = env.load[i] end
	end
	return out
end

-- A load average, to two decimals, without string.format's rounding: the number
-- is small and the arithmetic is the machine's own everywhere else.
local function loadText(n)
	local hundredths = math.floor(n * 100 + 0.5)
	local whole = math.floor(hundredths / 100)
	local rest = hundredths - whole * 100
	return tostring(whole) .. "." .. CeroSecOS.twoDigits(rest)
end

-- The sessions on this machine, as `who` reads them: the same door, so `w` and
-- `who` can never disagree about who is logged in.
local function liveSessions(env)
	if type(env) ~= "table" or type(env.net) ~= "table" then return {} end
	if type(env.net.sessions) ~= "function" then return {} end
	local list = env.net.sessions()
	if type(list) ~= "table" then return {} end
	local out = {}
	for i = 1, #list do
		local one = list[i]
		if type(one) == "table" and type(one.user) == "string" then out[#out + 1] = one end
	end
	table.sort(out, function(a, b) return tostring(a.line) < tostring(b.line) end)
	return out
end

-- The whole of uptime's line, which is also w's first line. One function,
-- because two copies of a format are two formats.
function CeroSecOS.uptimeLine(env)
	local now = CeroSecOS.clockOf(env)
	local clock = "??:??"
	if now ~= nil then clock = CeroSecOS.clockText(now) end
	local users = #liveSessions(env)
	local word = " user,"
	if users ~= 1 then word = " users," end
	local up = 0
	if type(env) == "table" and type(env.up) == "number" and env.up > 0 then up = env.up end
	local load = loadOf(env)
	return " " .. clock .. "  up" .. CeroSecOS.upText(up)
		.. "  " .. tostring(users) .. word
		.. "  load " .. loadText(load[1]) .. " " .. loadText(load[2])
		.. " " .. loadText(load[3])
end

commands.uptime = function(state, session, args, env)
	if #args > 1 then return usage("uptime") end
	return true, { CeroSecOS.uptimeLine(env) }
end

--
-- w
--
-- uptime's line, then a row for every session: who, on which line, where he came
-- from, when he logged in, how long he has been idle, and what he is running.
--
--    3:14PM  up 2 days,  4:03,  2 users,  load averages: 0.12, 0.08, 0.05
--   USER     TTY      FROM        LOGIN@ IDLE  WHAT
--   admin    console  -            2:32PM 00:03 ls -l /etc
--   kate     ttyp0    gate         3:01PM 00:00 -
--
-- Two cuts from BSD's own row, and both are the sixty columns':
--
--   * LOGIN@ is the CLOCK and never the weekday. BSD prints "Wed10AM" for a
--     session older than a day; seven columns of sixty spent on a weekday is a
--     column the WHAT cannot have, and the login day is what `last` is for.
--   * IDLE is hh:mm, the shape every other span on this screen wears
--     (CeroSecOS.spanText), rather than BSD's four different ones.
--
-- And one thing that is not a cut. A real w measures idle from the last
-- KEYSTROKE, off the tty's own mtime. This machine has no keystroke clock: what
-- it knows is when a session last handed the shell a line (env.net's `busy`), and
-- that is what the column says. A session the machine has no such stamp for --
-- one that came back from a save file, where activity is runtime like a job --
-- shows the time since it LOGGED IN, which is the honest floor: he has been idle
-- at least that long.
local W_USER, W_TTY, W_FROM, W_AT, W_IDLE = 8, 8, 10, 7, 5
local W_WHAT = CeroSecOS.COLS
	- (W_USER + 1 + W_TTY + 1 + W_FROM + 1 + W_AT + 1 + W_IDLE + 1)

-- What that session is running: the line the survivor typed, when the machine is
-- still busy with it, and "-" when it is standing at a prompt. Asked of the job
-- book, which is the only place the answer is.
local function whatOf(env, line)
	local jobs = CeroSecOS.jobsOf(env)
	for i = 1, #jobs do
		local job = jobs[i]
		-- The PROMPT's own job and nobody else's: a `&` in the background and a
		-- crontab line are the machine's work and not what this session is doing,
		-- which is the rule `jobs` and `ps` already tell apart.
		local mine = job.pty
		if mine == nil then mine = CeroSecOS.CONSOLE_LINE end
		if job.interactive and not job.bg and job.mailTo == nil and mine == line
				and not CeroSecOS.jobIsOver(job) then
			return job.promptLine or job.cmd or "-"
		end
	end
	return "-"
end

function CeroSecOS.wLine(row, now, what)
	local at = "     --"
	if now ~= nil and type(row.at) == "number" and row.at > 0 then
		at = CeroSecOS.padLeft(CeroSecOS.clockText(row.at), W_AT)
	end
	local since = row.busy
	if type(since) ~= "number" or since <= 0 then since = row.at end
	local idle = "  -  "
	if now ~= nil and type(since) == "number" and since > 0 and now >= since then
		idle = CeroSecOS.padRight(CeroSecOS.spanText(now - since), W_IDLE)
	end
	local from = row.host
	if type(from) ~= "string" or from == "" then from = "-" end
	return CeroSecOS.padRight(CeroSecOS.truncate(row.user, W_USER), W_USER) .. " "
		.. CeroSecOS.padRight(CeroSecOS.truncate(row.line or CeroSecOS.CONSOLE_LINE, W_TTY), W_TTY)
		.. " " .. CeroSecOS.padRight(CeroSecOS.truncate(from, W_FROM), W_FROM)
		.. " " .. at .. " " .. idle .. " " .. CeroSecOS.truncate(what, W_WHAT)
end

commands.w = function(state, session, args, env)
	if #args > 1 then return usage("w") end
	local now = CeroSecOS.clockOf(env)
	local out = { CeroSecOS.uptimeLine(env) }
	out[#out + 1] = CeroSecOS.padRight("USER", W_USER) .. " "
		.. CeroSecOS.padRight("TTY", W_TTY) .. " "
		.. CeroSecOS.padRight("FROM", W_FROM) .. " "
		.. CeroSecOS.padLeft("LOGIN@", W_AT) .. " "
		.. CeroSecOS.padRight("IDLE", W_IDLE) .. " WHAT"
	local rows = liveSessions(env)
	for i = 1, #rows do
		local row = rows[i]
		local line = row.line or CeroSecOS.CONSOLE_LINE
		out[#out + 1] = CeroSecOS.wLine(row, now, whatOf(env, line))
	end
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

-- shutdown [-h|-r] now|+N.
--
-- `-h` halts and `-r` reboots, exactly as they do on a real one; with neither,
-- the machine halts. `now` and no time at all are the same thing. `+N` puts
-- the order N minutes out, broadcasts it to every screen standing at the
-- machine, and broadcasts again a minute before -- and the timer is the
-- SCHEDULER's, because the core has no clock of its own and no machine to
-- switch off.
--
-- A PENDING ORDER IS A PROCESS, which is the one thing about this command that
-- 1993 settles and this machine got wrong until SYSTEM_VERSION 17. BSD's
-- shutdown(8) forks, prints its pid and sleeps until the minute; it is in `ps`
-- like anything else, and the way you call it off is the way you stop any other
-- process -- you kill it. There is no `-c`: that flag is sysvinit's, which is
-- Linux and is 1992 at the earliest on a machine nobody in Knox County had. So
-- `shutdown -c` is gone, the order shows up in `jobs` and in `ps` under the
-- account that gave it, and `kill` is how it is called off.
--
-- Which means a SECOND pending order is allowed, because on a real BSD it is: two
-- shutdowns are two processes, both sleeping, both broadcasting, and the first
-- minute to arrive takes the machine down. It used to be refused here, and there
-- is nothing in 4.4BSD to point at for the refusal. What bounds it now is the
-- job book -- four processes on this machine, shutdowns included.
commands.shutdown = function(state, session, args, env)
	local control, i = "shutdown", 2

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

	local nowMs = CeroSecOS.nowMsOf(env)
	if nowMs == nil then return fail("shutdown", nil, "no clock") end
	-- The room for it, asked the way `sh` and `wait` ask: a pending order is a
	-- process and the machine's ceiling is on processes. The job this command is
	-- running in is not one of the jobs in its way.
	if CeroSecOS.liveJobs(CeroSecOS.jobsOf(env), CeroSecOS.askingId(env))
			>= CeroSecOS.MAX_JOBS then
		return false, { "shutdown: too many jobs" }
	end

	return true, { CeroSecOS.shutdownLine(control, minutes) }, "schedule",
		{ at = nowMs + minutes * 60000, kind = control,
			-- Who ordered it, for the book: the account `kill` will let call it off
			-- besides root. It is the account the command RAN as, so a `sudo
			-- shutdown +5` is root's order and not the ordinary account's -- which is
			-- what sudo means and what the far end of every other authority check on
			-- this machine reads.
			user = CeroSecOS.userOf(session),
			-- And what `ps` shows in the command column.
			cmd = table.concat(args, " ") }
end

commands.reboot = powerCommand("reboot", "reboot")
-- halt, the other name shutdown has had since the seventies: `shutdown -h now`
-- with nothing to type in front of it.
commands.halt = powerCommand("halt", "shutdown")
-- And there is no `restart`. It was here until SYSTEM_VERSION 16 and it was
-- invented: no Unix has ever had one. The two spellings a 1993 machine had are
-- `reboot` and `shutdown -r now`, and both are above.

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
-- pw_error's last word on every failure after the lock (see "old", below).
local PASSWD_UNCHANGED = "passwd: /etc/passwd: unchanged"

commands.passwd = function(state, session, args, env)
	if #args > 2 then return usage("passwd") end
	local me = CeroSecOS.userOf(session)
	local name = args[2]
	if name == nil or name == "" then name = me end
	if CeroSecOS.getUser(state, name) == nil then return false, { "passwd: no such user" } end
	if name ~= me and me ~= "root" then return false, { "passwd: Permission denied" } end
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
	if name ~= me and me ~= "root" then return false, { "passwd: Permission denied" } end

	if cont.step == "old" then
		-- passwd is a real program with its own name, not su's bare prompt:
		-- 4.4BSD-Lite2 usr.bin/passwd/local_passwd.c sets errno to EACCES and
		-- calls pw_error(NULL, 1, 1), which warns under the PROGRAM's name
		-- (passwd, since no account name was given) with strerror(3)'s
		-- capitalised wording for EACCES -- "passwd: Permission denied", not
		-- su.c's bare "Sorry". pw_error (usr.sbin/vipw/pw_util.c) then says
		-- warnx("%s: unchanged", _PATH_MASTERPASSWD) before it exits: the
		-- second line. The file it names is the one this machine keeps the
		-- hash in, /etc/passwd (the "shadow" deviation), because naming a
		-- master.passwd `ls /etc` cannot find would be the worse lie.
		if not CeroSecOS.checkPassword(user, line) then
			return false, { "passwd: Permission denied", PASSWD_UNCHANGED }
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
		-- A write that failed is pw_error again, with its own reason first.
		if done == nil then
			return false, { "passwd: " .. CeroSecOS.strerror(reason), PASSWD_UNCHANGED }
		end
		return true, { "passwd: password updated" }
	end

	-- A token with a step nobody wrote: refuse the way a wrong answer is
	-- refused, and change nothing.
	return false, { "passwd: Permission denied" }
end

-- mkpasswd. The same function the passwords go through, on a string you choose,
-- so what a stored password looks like is something the machine can show you. A
-- salt of your own makes it reproducible; without one you get a fresh salt and
-- a line that is different every time, which is the point of a salt.
--
-- No Unix of 1993 had this command: crypt(3) was the library call and nothing in
-- /bin wrapped it. So it is CeroSec Systems' own, under the name the job would
-- have been given, and the manual's deviations page says so out loud. It was
-- called `hash` until this build, which was not a name any Unix would have used
-- for anything.
commands.mkpasswd = function(state, session, args, env)
	if #args < 2 or #args > 3 then return usage("mkpasswd") end
	local salt = args[3]
	if salt == nil or salt == "" then
		salt = CeroSecOS.newSalt(state, args[2] .. tostring(session.stamp))
	end
	if not CeroSecOS.isValidSalt(salt) then return fail("mkpasswd", salt, "invalid salt") end
	if CeroSecOS.hasControlBytes(args[2]) then
		return fail("mkpasswd", args[2], "invalid characters")
	end
	-- fit() breaks anything wider than the screen across lines, so a long salt
	-- wraps instead of being cut.
	return true, { CeroSecOS.hashPassword(args[2], salt) }
end

--
-- more
--
-- The pager. A screen twenty rows deep cannot show a file of forty lines, and
-- until this build the only answer was `head -20` and arithmetic. more(1) fills
-- the screen, puts up its own prompt, and waits:
--
--   admin@ksp-04-11:~$ more /etc/motd
--   ... nineteen lines ...
--   --More--(47%)
--
-- Space is the next screenful, Return is one more line, and q gives up. The
-- percentage is how far through the text the screenful just shown ends, which is
-- what more(1) prints and what makes the prompt worth reading.
--
-- ONE DEVIATION, and it is the console's rather than the pager's: this machine
-- reads a LINE and not a keystroke -- there is one input box and Enter is what
-- sends it -- so Space is a space and then Enter, and q is a q and then Enter. A
-- bare Enter is the next line, which is exactly right. It is the same shape
-- `read -n 1` already has here, and the manual says so for both.
--
-- WHERE IT PAGES AND WHERE IT DOES NOT
--
-- more(1) asks whether its output is a terminal and, when it is not, copies its
-- input through with no paging at all -- which is what makes `ls | more | wc -l`
-- answer a number instead of hanging. This one does the same, on the shell's own
-- answer to that question (the `tty` half of what a command is handed).
--
-- The other case is a screen with NOBODY in front of it: a `&` in the background,
-- a crontab line. There the output goes to a glass but no key will ever be
-- pressed, so the pager refuses in its own name -- `more: not a terminal`, which
-- is the very line su, passwd, sudo and edit already give for the same reason.
-- That refusal comes out of the prompt machinery and not out of this command; the
-- `keys` half of what the shell knows is what tells the two cases apart.
--

-- How many lines one screenful is: the screen, less the row the --More-- prompt
-- stands on. Exactly more(1)'s arithmetic.
CeroSecOS.MORE_ROWS = CeroSecOS.ROWS - 1

-- The prompt, with the percentage more(1) puts in it: how much of the text has
-- been shown, rounded the way more rounds it -- down, so a screenful that ends
-- one line short of the end never says 100%.
function CeroSecOS.moreLine(shown, total)
	if type(total) ~= "number" or total < 1 then return "--More--" end
	local pct = math.floor(shown * 100 / total)
	if pct > 99 then pct = 99 end
	return "--More--(" .. tostring(pct) .. "%)"
end

-- The screenful that starts at `from`, and the prompt under it. Or, at the end of
-- the text, the last lines and no prompt at all -- a pager that asked a question
-- after the last line would be a pager you had to dismiss.
local function moreStep(lines, from, count)
	local out = {}
	local last = from + count - 1
	if last > #lines then last = #lines end
	for i = from, last do out[#out + 1] = lines[i] end
	if last >= #lines then return out, nil end
	return out, CeroSecOS.moreLine(last, #lines)
end

-- What the token carries: where the pager stands, and the text it is standing in.
-- The text and not the file name, because the file may be gone -- or may never
-- have been a file at all: a pipe's contents exist nowhere else by the time the
-- question is up. Bounded by the pipe's own ceiling, which is what the reader
-- below pays.
local function moreAsk(lines, from)
	local shown, prompt = moreStep(lines, from, CeroSecOS.MORE_ROWS)
	if prompt == nil then return true, shown end
	local held = {}
	for i = from + #shown, #lines do held[#held + 1] = lines[i] end
	return true, shown, "prompt",
		{ text = prompt, mask = false,
		  cont = { cmd = "more", rest = held, total = #lines, seen = from + #shown - 1 } }
end

commands.more = function(state, session, args, env, stdin, sh)
	local paths = operands(args)

	-- The lines, from the files or from the pipe. A pipe is read to its END
	-- first: a pager cannot say what per cent of a text a screenful is until it
	-- knows how long the text is, and it cannot page what has not arrived. Which
	-- is what `sort` and `tail` already do, under the very same ceiling -- a
	-- hundred lines and four kilobytes -- and it is the ceiling the token has to
	-- meet too, because what is not shown yet is carried in it.
	local lines = nil
	local input = stdinOf(stdin, paths)
	if input ~= nil then
		local carry = input.carry
		for i = 1, #input.lines do
			if not holdLine(carry, input.lines[i]) then carry.over = true end
		end
		if carry.over then
			input.done = true
			return fail("more", nil, "input too large")
		end
		if not input.eof then return true, {} end
		-- It will read no more, and it says so: that is what lets the question it
		-- is about to ask be answered at all. A stage that still had its pipe open
		-- could not be resumed -- a continuation has no pipe behind it -- and the
		-- prompt machinery refuses one that has (see applyControl).
		input.done = true
		lines = carry.lines or {}
	else
		if #paths == 0 then return usage("more") end
		lines = {}
		local okAll = true
		local out = {}
		for i = 1, #paths do
			local got, why = fileLines(state, session, "more", paths[i])
			if got == nil then
				okAll = false
				out[#out + 1] = why
			else
				-- Every file named, one after another, which is what more(1) does
				-- with several -- minus the "::::::::" banner it puts between them,
				-- because that banner is two rows of twenty and the manual says so.
				for j = 1, #got do lines[#lines + 1] = got[j] end
			end
		end
		if not okAll then return false, out end
	end

	-- Not a screen: copy through, with no paging and no question. more(1)'s own
	-- answer, and what keeps `ls | more | wc -l` a number.
	if not shTty(sh) then return true, lines end
	-- A screen with nobody in front of it. Refused here rather than after the
	-- first screenful: the prompt machinery would refuse the question anyway (see
	-- applyControl), and a pager that printed nineteen lines onto the glass of a
	-- machine nobody is standing at before saying so would have paged nothing.
	if not shKeys(sh) then return fail("more", nil, "not a terminal") end
	return moreAsk(lines, 1)
end

-- The answer. One character decides, which is the key more(1) reads: a space is
-- the next screenful, an empty line is the next line, and q gives up. Anything
-- else is a screenful, because that is what more does with a key it has no
-- meaning for.
continuations.more = function(state, session, cont, line, env)
	local rest = cont.rest
	if type(rest) ~= "table" then return false, { "more: nothing to answer" } end
	for i = 1, #rest do
		if type(rest[i]) ~= "string" then return false, { "more: nothing to answer" } end
	end
	local total = tonumber(cont.total) or #rest
	local seen = tonumber(cont.seen) or 0

	local key = string.sub(tostring(line), 1, 1)
	-- q, and Q: the one key that is not "more, please".
	if key == "q" or key == "Q" then return true, {} end
	local count = CeroSecOS.MORE_ROWS
	if key == "" then count = 1 end

	local shown, prompt = moreStep(rest, 1, count)
	if prompt == nil then return true, shown end
	local held = {}
	for i = #shown + 1, #rest do held[#held + 1] = rest[i] end
	-- The percentage is of the WHOLE text and not of what is left, so it climbs
	-- once from nought to a hundred over the length of the file.
	return true, shown, "prompt",
		{ text = CeroSecOS.moreLine(seen + #shown, total), mask = false,
		  cont = { cmd = "more", rest = held, total = total, seen = seen + #shown } }
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
			text = CeroSecOS.bufferOf(node.data),
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

	-- A word the SHELL is, which is not a program and could not be one: `cd` moves
	-- the shell that ran it and `exit` ends the session, and there is no file in
	-- /bin for sudo to find for either. Real sudo RUNS A PROGRAM, so what it says
	-- is that it could not find the name it was given, in its own name -- and it
	-- says it about every one of them, which is why this asks the same question the
	-- shell asks (isShellWord, SHELL_BUILTINS) instead of naming `exit` alone.
	--
	-- `sudo cd /etc` was SILENT until SYSTEM_VERSION 18: the word fell through to
	-- commands.cd, which moved the borrowed session sudo had just made and which
	-- died with the command. A machine that says nothing and does nothing is the
	-- one answer a shell must never give, and the manual page already said sudo
	-- cannot run a word the shell is.
	if CeroSecOS.isShellWord(name) or CeroSecOS.SHELL_BUILTINS[name] then
		return false, { "sudo: " .. name .. ": command not found" }
	end

	-- A name with nothing behind it, signed the way the line above signs one:
	-- SUDO is the program that went looking, so sudo is what says it could not
	-- find it. Real sudo prints "sudo: <name>: command not found" for a word that
	-- is not on its PATH -- the shell's own refusal has no sudo in front of it
	-- because the shell is what looked. This said `nosuchthing: command not
	-- found`, which reads as a refusal from a program that was never run.
	local fn = commands[name]
	if fn == nil then return false, { "sudo: " .. name .. ": command not found" } end

	-- Looked up on the caller's own PATH, as root: the authority sudo lends is
	-- root's rights on the file, not a second PATH of its own -- real sudo of
	-- this era reset nothing about the environment either.
	if not CeroSecOS.BUILTINS[name] then
		local refusal = CeroSecOS.whyNotRun(state, sub, name, shPath(sh))
		if refusal ~= nil then return false, { name .. ": " .. CeroSecOS.execError(refusal) } end
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
-- he does everything else that is root's -- `sudo useradd bob` -- and there is
-- no second rule for who may.
--
-- The names are System V's -- useradd, userdel, usermod, 1989, and what Solaris
-- 2 shipped in 1992 -- and so are the flags: `-r` removes the home, `-G` SETS
-- the supplementary group list. There was never an `adduser` on a System V or a
-- BSD of 1993; Debian wrote that one, and it is a decade late here.
--
-- All three are ordinary writes to ordinary files: the account is a line in
-- /etc/passwd, the home is a directory made with createNode, the groups are
-- lines in /etc/group, and the ceilings, the permission bits and the printable
-- rule are the filesystem's exactly as they are for a player. A full disk
-- refuses a useradd the way it refuses a touch.
--
-- WHAT BECAME OF THE "admin" FLAG
--
-- `adduser -a` set a flag on the /etc/passwd line that no command consulted:
-- its one visible effect was the "#" on the prompt. There is no such flag on any
-- Unix, and the 1993 answer to "make this account an administrator" is a GROUP:
-- 4.4BSD gates `su` on membership of `wheel`, and sudo of the era takes a
-- `%group` line in /etc/sudoers. So `useradd -G wheel bob` is what `adduser -a
-- bob` was, and it means something now -- the shipped /etc/sudoers carries
-- `%wheel`, so the group really is what grants root.
--
-- The flag on the line stays, because the line's fourth field is the format and
-- a machine off an older save file still carries one. What changed is who writes
-- it: the two commands that can move an account in or out of `wheel` write it
-- from the membership, so the field and the group never say different things
-- about an account either of them has touched.
--

-- The -G list: the groups an account is to be in, in the order they were
-- written, each one once. nil plus the refusal already worded.
--
-- An EMPTY list is refused. SVR4's -G takes a list of groups, and "no groups at
-- all" is not one of them: a `usermod -G ""` that quietly emptied the list would
-- be the one spelling of this command that takes power away by accident.
local function groupList(cmd, text)
	if type(text) ~= "string" or text == "" then
		return nil, fail(cmd, nil, "empty group list")
	end
	local names, seen = {}, {}
	local start = 1
	while true do
		local p = string.find(text, ",", start, true)
		local piece
		if p == nil then piece = string.sub(text, start) else piece = string.sub(text, start, p - 1) end
		if piece == "" then return nil, fail(cmd, nil, "empty group list") end
		if not seen[piece] then
			seen[piece] = true
			names[#names + 1] = piece
		end
		if p == nil then break end
		start = p + 1
	end
	return names
end

-- Put the account in exactly these groups and in no others, and answer whether
-- `wheel` is one of them. Every group has to exist first -- the whole list is
-- checked before a byte is written, so a typo in the third name does not leave
-- an account half moved.
local function setGroups(state, cmd, name, groups, now)
	for i = 1, #groups do
		local group = groups[i]
		if not CeroSecOS.groupExists(state, group) then
			return nil, fail(cmd, group, "no such group")
		end
	end
	local wheel = false
	local want = {}
	for i = 1, #groups do
		want[groups[i]] = true
		if groups[i] == CeroSecOS.WHEEL_GROUP then wheel = true end
	end
	-- Out of the ones it is in and not on the list. The primary group is not a
	-- membership anybody granted, so it is not one -G takes away.
	local had = CeroSecOS.groupsOf(state, name)
	for i = 1, #had do
		local group = had[i]
		if group ~= name and not want[group] then
			local done, reason = CeroSecOS.setGroupMember(state, name, group, false, now)
			-- "not a member" is the mirrored sudo group answering: /etc/sudoers is
			-- what puts a name in that one and it is not this command's to edit.
			if done == nil and reason ~= "not a member" then
				return nil, fail(cmd, group, reason)
			end
		end
	end
	-- And into the ones on the list it is not in yet.
	for i = 1, #groups do
		local group = groups[i]
		if group ~= name and not CeroSecOS.inGroup(state, name, group) then
			local done, reason = CeroSecOS.setGroupMember(state, name, group, true, now)
			if done == nil then return nil, fail(cmd, group, reason) end
		end
	end
	return wheel
end

commands.useradd = function(state, session, args, env)
	if CeroSecOS.userOf(session) ~= "root" then return fail("useradd", nil, "permission denied") end

	local groups, name = nil, nil
	local i = 2
	while i <= #args do
		local a = args[i]
		if name == nil and a == "-G" then
			local list, okFlag, lines = groupList("useradd", args[i + 1])
			if list == nil then return okFlag, lines end
			groups = list
			i = i + 2
		elseif name == nil and string.sub(a, 1, 1) == "-" and a ~= "-" then
			return badOption("useradd", a)
		elseif name == nil then
			name = a
			i = i + 1
		else
			return usage("useradd")
		end
	end
	if name == nil or name == "" then return usage("useradd") end
	if not CeroSecOS.isValidUserName(name) then return fail("useradd", name, "invalid name") end
	if CeroSecOS.getUser(state, name) ~= nil then return fail("useradd", name, "already exists") end
	-- The groups are judged BEFORE the account exists: a line named on the
	-- command line that is not a group is a typo, and a typo must not leave an
	-- account behind it.
	if groups ~= nil then
		for k = 1, #groups do
			if not CeroSecOS.groupExists(state, groups[k]) then
				return fail("useradd", groups[k], "no such group")
			end
		end
	end

	local now = CeroSecOS.clockOf(env)
	local home = CeroSecOS.HOME_PATH .. "/" .. name
	local node, reason = CeroSecOS.getNode(state, session, home)
	if node == nil and reason ~= "no such file" then return fail("useradd", home, reason) end
	if node ~= nil and node.type ~= "dir" then return fail("useradd", home, "not a directory") end

	-- Is this account going to be in wheel? That is what the flag on its
	-- /etc/passwd line says, so it is settled before the line is written.
	local admin = false
	if groups ~= nil then
		for k = 1, #groups do
			if groups[k] == CeroSecOS.WHEEL_GROUP then admin = true end
		end
	end

	-- The account first and the home second, so that a refusal on the way --
	-- a full disk, a /home that is not there any more -- takes the account back
	-- out and leaves the machine exactly as it was. Half an account is worse
	-- than none: it is a name in the file with nowhere to stand.
	local done, wreason = CeroSecOS.addUser(state, name, home, admin, session.stamp, now)
	if done == nil then return fail("useradd", name, wreason) end

	if node == nil then
		local made, creason = CeroSecOS.createNode(state, session, home,
			CeroSecOS.newDir(name, CeroSecOS.HOME_MODE), now)
		if made == nil then
			CeroSecOS.removeUser(state, name, now)
			return fail("useradd", home, creason)
		end
	else
		-- A directory that is already there is ADOPTED, not remade: it changes
		-- hands and keeps its mode and everything in it. Somebody's files are
		-- not an obstacle to giving him an account.
		node.owner = name
		if now ~= nil then node.mtime = now end
	end

	if groups ~= nil then
		local _, gOk, gLines = setGroups(state, "useradd", name, groups, now)
		if gOk ~= nil then return gOk, gLines end
	end

	-- Nothing on the screen: SVR4's useradd(1M) printed no line for an
	-- account it made, and neither does this. The open, empty password is
	-- the manual's to warn about (Volume 2, useradd).
	return true, {}
end

commands.userdel = function(state, session, args, env)
	if CeroSecOS.userOf(session) ~= "root" then return fail("userdel", nil, "permission denied") end

	local removeHome, name = false, nil
	for i = 2, #args do
		local a = args[i]
		if name == nil and string.sub(a, 1, 1) == "-" and a ~= "-" then
			for c = 2, #a do
				if string.sub(a, c, c) ~= "r" then return badOption("userdel", string.sub(a, c, c)) end
			end
			removeHome = true
		elseif name == nil then
			name = a
		else
			return usage("userdel")
		end
	end
	if name == nil or name == "" then return usage("userdel") end

	-- Root is not one of the accounts: it is the way back into the machine, and
	-- a computer with no root on it is a computer whose BIOS is the only way in.
	-- Asked before the file is even looked at, so the answer is the same on a
	-- machine somebody has been editing by hand.
	if name == "root" then return fail("userdel", name, "cannot remove") end

	local user = CeroSecOS.getUser(state, name)
	if user == nil then return fail("userdel", name, "no such user") end
	-- Not the account at the glass, and not one the glass would come back to
	-- through `exit`: pulling either out from under a live session leaves
	-- somebody logged in as nobody.
	if CeroSecOS.isLoggedIn(session, name) then return fail("userdel", name, "user is logged in") end

	local now = CeroSecOS.clockOf(env)

	-- The home first, while the account still exists to own it. Without -r it
	-- stays exactly where it is, owned by a name the machine no longer knows --
	-- which is what `ls -l` will show, and it is the truth rather than a tidy
	-- lie about whose files those were.
	if removeHome then
		local home = user.home
		local node, reason = CeroSecOS.getNode(state, session, home)
		if node == nil then
			if reason ~= "no such file" then return fail("userdel", home, reason) end
		else
			local gone, greason = CeroSecOS.removeNode(state, session, home, true, now)
			if gone == nil then return fail("userdel", home, greason) end
		end
	end

	local done, reason = CeroSecOS.removeUser(state, name, now)
	if done == nil then return fail("userdel", name, reason) end
	-- And the right to become root with it: a name left in /etc/sudoers is a
	-- line waiting for whoever is given that name next, and so is a name left in
	-- a group that /etc/sudoers grants.
	local dropped, sreason = CeroSecOS.removeSudoer(state, name, now)
	if dropped == nil then return fail("userdel", CeroSecOS.SUDOERS_PATH, sreason) end
	local swept, greason = CeroSecOS.removeGroupMember(state, name, now)
	if swept == nil then return fail("userdel", CeroSecOS.GROUP_PATH, greason) end

	-- And nothing said for it, as SVR4's userdel(1M) said nothing.
	return true, {}
end

-- usermod -G crew,wheel bob. SVR4's -G, which SETS the list: bob is in crew and
-- wheel afterwards and in nothing else he was put in by hand. A primary group is
-- not a membership anybody granted, so it is not one this takes away -- and an
-- empty list is refused rather than read as "in nothing", because `usermod -G ""`
-- taking somebody's power away by accident is the one thing this command must
-- never do quietly.
commands.usermod = function(state, session, args, env)
	if #args ~= 4 or args[2] ~= "-G" then return usage("usermod") end
	if CeroSecOS.userOf(session) ~= "root" then return fail("usermod", nil, "permission denied") end
	local name = args[4]
	local user = CeroSecOS.getUser(state, name)
	if user == nil then return fail("usermod", name, "no such user") end

	local groups, okFlag, lines = groupList("usermod", args[3])
	if groups == nil then return okFlag, lines end

	local now = CeroSecOS.clockOf(env)
	local wheel, gOk, gLines = setGroups(state, "usermod", name, groups, now)
	if wheel == nil then return gOk, gLines end

	-- And the flag on the /etc/passwd line, which is what the prompt's "#" and
	-- `id` read: it says whether the account is in wheel, so it is written from
	-- the membership this command has just settled and never beside it.
	if wheel ~= (user.admin == true) then
		local done, reason = CeroSecOS.setAdmin(state, name, wheel, now)
		if done == nil then return fail("usermod", name, reason) end
	end
	return true, {}
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

-- Filling one is `usermod -G`, which lives with the two account commands above:
-- there was no gpasswd in 1993 either -- shadow-utils wrote it in 1996 -- and
-- SVR4's answer to "put bob in crew" was always a flag on usermod.
--
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
	if user == nil then return false, { "Sorry" } end
	if CeroSecOS.userOf(session) ~= "root" and not CeroSecOS.checkPassword(user, line) then
		-- One attempt, exactly as sudo gives one, and for the same reason: this
		-- machine has a physical lock on it.
		return false, { "Sorry" }
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
-- working directory and nothing else, so `PATH= ls` is "ls: not found".
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

-- And which of them are the ENVIRONMENT, which is the other half of the same
-- fact: a login exports what it sets, so a script started from that shell is
-- handed PATH and HOME and no `export` line is needed to make either work.
-- Anything typed afterwards is the shell's own until somebody exports it.
--
-- A set, and a fresh one every time, for the reason above. It goes with the
-- table from loginVars everywhere one is made -- the console at a login, a pty,
-- the BIOS repair -- and where it is missing the engine reads "everything it
-- holds" (see the variables section of CeroSecOSVM.lua), which is what a machine
-- saved before there was an environment on it has to mean.
function CeroSecOS.loginExported()
	return { PATH = true, HOME = true }
end

-- Where a name is found, walked left to right. absolute path, or nil plus the
-- bare reason -- the caller puts the name in front of it, so the two lines a
-- player ever sees are
--   ls: not found
--   ls: Permission denied
--
-- POSIX's rule and every sh's: the first candidate that is a file with x on it
-- for whoever typed it WINS, and a candidate that cannot be run does not stop the
-- search -- a copy of `ls` in ~/bin with no x on it is a file in the way, not a
-- command, and /bin/ls behind it still runs. What the walk carries is the best
-- REFUSAL it met on the way, so a name found everywhere and runnable nowhere
-- says "Permission denied", and a name nothing answers to at all says "not
-- found".
-- The third answer is how many directories were actually looked in, which is
-- what the walk COST: the shell charges it (see CeroSecOSVM.runSimple), because a
-- long PATH makes every command on the machine dearer and a budget that could not
-- see that would not be a budget. The fourth says whether what answered was a
-- symbolic LINK, which the caller needs because a link in /bin is not one of the
-- machine's own executables -- it is a name for somebody's file.
--
-- Each candidate is looked at without following the last component, so the link
-- can be told from what it points at; a link is then followed once, to judge x
-- and the type on the FILE, which is where a symbolic link's permissions have
-- always lived. A link that points nowhere is nothing there, and the walk goes on.
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
		local candidate = dirs[i] .. "/" .. name
		local node, reason, abs = CeroSecOS.getNode(state, session, candidate, true)
		local link = CeroSecOS.isLink(node)
		if link then node, reason = CeroSecOS.getNode(state, session, candidate) end
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
			return abs, nil, i, link
		else
			refusal = "permission denied"
		end
	end
	if refusal ~= nil then return nil, refusal, last end
	return nil, "not found", last
end

-- nil when the command may run, or the bare reason it may not. The path it was
-- found at comes back beside the nil, for the caller that needs to know WHICH
-- file answered.
function CeroSecOS.whyNotRun(state, session, name, path)
	local found, refusal, walked = CeroSecOS.lookupPath(state, session, name, path)
	if found == nil then return refusal, nil, walked end
	return nil, found, walked
end

-- Is what answered for this name one of the MACHINE's own executables? Only a
-- file that really lies in /bin is: a link there is a name somebody made for a
-- file of his own, and what runs is that file. Written once, because the walker
-- and the shell both ask it.
local function isSystemBin(found, link)
	if link then return false end
	local _, parts = CeroSecOS.resolve(nil, found)
	return CeroSecOS.parentOf(parts) == CeroSecOS.BIN_PATH
end

--
-- which: where a name would be found, and nothing else.
--
-- A name no PATH entry answers to is the csh script's own line, 4.3BSD's
-- ucb/which: `echo no $arg in $path`, where csh's $path is the directories
-- with blanks between -- so it is output, not an error, and `which thing >
-- /dev/null` says nothing on the screen -- and the status is 0, because the
-- script's last command was that echo and csh hands its status back. A
-- found name and a missing one are told apart by the words, as in 1993.
--
-- It answers about FILES, because that is all a PATH holds: `which cd` finds
-- nothing, exactly as it finds nothing on a real machine, and `type` is the word
-- that knows about the shell's own.
commands.which = function(state, session, args, env, stdin, sh)
	if #args ~= 2 then return usage("which") end
	local found = CeroSecOS.lookupPath(state, session, args[2], shPath(sh))
	if found == nil then
		-- A plain ":" to find, never a pattern built from what was typed.
		local dirs = string.gsub(shPath(sh), ":", " ")
		return true, { "no " .. args[2] .. " in " .. dirs }
	end
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
	-- A FUNCTION the shell holds, named after the words the shell IS and before PATH,
	-- which is the order the shell looks a name up in (CeroSecOSVM.runSimple). `type`
	-- says what WOULD run, so it has to ask the same questions in the same order.
	local job = CeroSecOS.jobOf(env)
	if job ~= nil and type(job.funcs) == "table" and type(job.funcs[name]) == "string" then
		return true, { name .. " is a function" }
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
-- who is kept for the caller's own bookkeeping but never signs this line: a
-- real sh opens ">" itself, before the command runs, and says so in its OWN
-- words whichever command was on the line -- "cannot create /etc/hosts:
-- permission denied" for `cat nosuch > /etc/hosts`, never "cat:" and never
-- capitalised (CeroSecOS.cannotCreate has the citation).
function CeroSecOS.writeRedirect(state, session, who, redirect, text, env)
	local devOk, devLines = redirectToDevice(state, session, redirect.path, text, env)
	if devOk ~= nil then return devOk, devLines end
	local done, reason = CeroSecOS.writeFile(state, session, redirect.path, text,
		redirect.append, CeroSecOS.clockOf(env))
	if done == nil then
		return false, CeroSecOS.fit({ CeroSecOS.cannotCreate(redirect.path, reason) })
	end
	return true, {}
end

-- OPENING what ">" named, with nothing to put in it yet. A shell opens the
-- target before the command runs -- that is why `cat nosuch > f` leaves an
-- empty f behind on a real machine -- and so does this one: CeroSecOSVM's
-- runSimple opens every ">" and "2>" here before it looks the command up, and
-- a target that cannot be opened is a command that never runs (`rm f >
-- /etc/hosts` leaves f alone). Every write after it appends.
--
-- A device is not opened. It has no contents to truncate, only a state to be
-- put into, and putting it into one is what the write itself does.
-- true plus the lines, or false plus the refusal, exactly like the write.
-- who is kept for the caller's own bookkeeping but never signs this line, for
-- the same reason writeRedirect's does not (see its comment above).
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
		return false, CeroSecOS.fit({ CeroSecOS.cannotCreate(redirect.path, reason) })
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
-- exported is the console's own set of exported names, by reference for the same
-- reason vars is: `export x` on one line holds on the next. A caller with none
-- is a shell that has not said which of its variables are the environment, and
-- the engine reads that as all of them (see the variables section of
-- CeroSecOSVM.lua) -- which is what a machine saved before this build means.
-- funcs is the console's own table of function SOURCES and travels by reference for
-- the same reason: `greet() { ...; }` on one line is still there on the next.
function CeroSecOS.promptJob(state, session, line, vars, status, name, exported, funcs, lastBg)
	if type(state) ~= "table" or state.fs == nil then return nil, "no filesystem" end
	if type(session) ~= "table" or type(session.user) ~= "string" then
		return nil, "not logged in"
	end
	if type(line) ~= "string" then return nil, "sh: syntax error" end

	local prog, reason, where = CeroSecOS.parseScript(line)
	-- No line number for a typed line, and no name either: 4.4BSD-Lite2
	-- sh's synerror() signs with commandname, which an interactive shell
	-- never set (bin/sh/options.c sets it only for a script file), so a
	-- typo at the prompt is the bare "Syntax error: ..." line. A file has
	-- lines and is named after itself, like any script.
	if prog == nil then
		if name ~= nil then return nil, CeroSecOS.scriptError(name, reason, where) end
		if CeroSecOS.isSyntaxError(reason) then return nil, reason end
		return nil, "sh: " .. reason
	end

	local cmd = line
	if name ~= nil then cmd = name end
	local job = CeroSecOS.newJob({
		prog = prog, name = name or "sh", cmd = cmd, session = session,
		vars = vars, status = status, exported = exported, funcs = funcs, lastBg = lastBg,
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

-- The status of a command that could not be run, by the reason it could not.
-- POSIX.2 (2.8.2, "Exit Status for Commands") and the ksh88 manual: a command
-- not found is 127, one found and not executable is 126 -- the numbers every
-- sh since has given, and what a script tests $? against to tell "it ran and
-- failed" from "there was nothing to run".
function CeroSecOS.notRunStatus(reason)
	if reason == "permission denied" then return 126 end
	return 127
end

function CeroSecOS.runArgs(state, session, args, redirect, env, stdin, sh)
	-- All THREE of them, because the table handed to the command below is built
	-- fresh here and anything not read out of the caller's is a fact the command
	-- never learns. `keys` was dropped here when it was added, which made `more`'s
	-- "not a terminal" dead code: the pager paged onto the glass of a machine
	-- nobody was standing at, and it took a mutation check to notice -- no bench
	-- could tell, because every bench reaches a command through this door.
	local path, tty, keys = shPath(sh), shTty(sh), shKeys(sh)
	CeroSecOS.expandTilde(state, session, args, redirect)

	-- A bare redirection still creates (or truncates) the file, and it is sh
	-- doing the creating -- the same "cannot create" as writeRedirect and
	-- openRedirect, because a line with nothing but a ">" on it is still sh
	-- opening a target before a command that never comes.
	if #args == 0 then
		if redirect == nil then return true, {} end
		local devOk, devLines = redirectToDevice(state, session, redirect.path, "", env)
		if devOk ~= nil then return devOk, devLines end
		local done, wreason = CeroSecOS.writeFile(state, session, redirect.path, "",
			redirect.append, CeroSecOS.clockOf(env))
		if done == nil then
			return false, CeroSecOS.fit({ CeroSecOS.cannotCreate(redirect.path, wreason) })
		end
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
		-- A path that is not there is 127 and one that is there and cannot be run
		-- -- no x, or a directory -- is 126, the same two numbers a bare name gets
		-- (CeroSecOS.notRunStatus). Told apart by the reason readScript ends its
		-- line with, compared as plain text: the line holds the typed path.
		if not ok and control == nil and type(sh) == "table" and type(lines) == "table"
				and #lines == 1 and type(lines[1]) == "string" then
			local said = lines[1]
			local function endsWith(tail)
				return #said >= #tail and string.sub(said, #said - #tail + 1) == tail
			end
			if endsWith(": not found") then
				sh.status = 127
			elseif endsWith(": permission denied") or endsWith(": is a directory") then
				sh.status = 126
			end
		end
		return ok, lines, control, data
	end

	local fn = commands[name]
	-- The shell's own words are never looked up. `cd` is not a file -- a program
	-- cannot move the shell that ran it -- so there is nothing on any PATH that
	-- could answer for one, and `help` is the word a machine with nothing left in
	-- /bin still answers.
	-- Every "could not run" below tells the caller its status through `sh`
	-- (CeroSecOS.notRunStatus); a caller that handed no table wants none.
	local function notRun(reason)
		if type(sh) == "table" then sh.status = CeroSecOS.notRunStatus(reason) end
		return false, CeroSecOS.fit({ name .. ": " .. CeroSecOS.execError(reason) })
	end
	if CeroSecOS.BUILTINS[name] then
		if fn == nil then return notRun("not found") end
	else
		local found, refusal, walked, link =
			CeroSecOS.lookupPath(state, session, name, path)
		-- What the walk cost, back into the table the shell handed down: the
		-- walker charges it, and a caller that gave no table is a caller that is
		-- not charging anything either.
		if type(sh) == "table" then sh.walked = walked end
		if found == nil then return notRun(refusal) end
		-- WHICH file answered decides what runs. One in /bin is the machine's own
		-- executable and the engine is what is behind it -- a file there with no
		-- command behind it is not a command, exactly as it never was. Anything
		-- else is a file, and a file that is run is a script: that is what makes
		-- ~/bin an account's own commands, what lets a name there shadow the one in
		-- /bin when PATH names it first, and what makes `ln -s` into /bin a way to
		-- give everybody a command of your own.
		if not isSystemBin(found, link) then
			local rest = {}
			for i = 2, #args do rest[#rest + 1] = args[i] end
			local ok, lines, control, data = CeroSecOS.startScript(state, session, found, found,
				rest, table.concat(args, " "), env, true)
			return ok, lines, control, data
		end
		if fn == nil then return notRun("not found") end
	end

	local inner = { path = path, tty = tty, keys = keys }
	-- What the command may keep between one turn and the next, where it has asked
	-- for another (see the head of the `again` block in CeroSecOSVM.runSimple):
	-- handed down, and handed back with the flag, because the table above is built
	-- fresh here and nothing left on it would reach the shell otherwise.
	if type(sh) == "table" then inner.carry = sh.carry end
	local ok, lines, control, data = fn(state, session, args, env, stdin, inner)
	if type(sh) == "table" and inner.again == true then
		sh.again = true
		sh.carry = inner.carry
	end
	-- And what the command says its own work COST, on top of what a command costs:
	-- the same road `walked` takes and for the same reason -- the budget has to see
	-- work a table lookup does not account for (see CeroSecOS.BRE_STEPS_PER).
	if type(sh) == "table" and type(inner.cost) == "number" then sh.cost = inner.cost end
	-- And a command that failed and says the lines it hands back are its OUTPUT all
	-- the same (grep, having found nothing): the shell routes them, the status is 1.
	if type(sh) == "table" and inner.outOnFail == true then sh.outOnFail = true end
	-- And a command that means to leave a status other than the plain 0/1 --
	-- expr(1)'s own 2, the one case besides "could not be run at all" where a
	-- status carries more than ok/fail (see CeroSecOSVM.runSimple's "sh.status
	-- or 1", which is what reads this back).
	if type(sh) == "table" and type(inner.status) == "number" then sh.status = inner.status end
	if lines == nil then lines = {} end

	-- Output goes to the file only when the command succeeded; errors stay on
	-- the screen, as they would on stderr. A command that has not finished --
	-- one that asks, or one that opens the editor -- has no output to redirect
	-- yet, so the redirection never applies to it.
	-- "job" joins them: a script that has just been handed to the machine has
	-- printed nothing yet, and its output goes to the screen as it is made. So
	-- does "rsh", which has gone to WAIT for another machine: the lines it will
	-- hand back are the far command's, and the file is opened and remembered by
	-- the shell that typed it and written when they land (CeroSecOSVM's
	-- job.dialRedirect).
	local redirectable = control ~= "prompt" and control ~= "edit" and control ~= "job"
		and control ~= "rsh"
	if ok and redirect ~= nil and redirectable then
		-- ">" and ">>" are the same order to a device: it has no contents to
		-- append to, only a state to be put into.
		local wroteOk, wroteLines =
			CeroSecOS.writeRedirect(state, session, name, redirect, CeroSecOS.linesToText(lines), env)
		-- data with it: an order this branch let through is still an order, and one
		-- handed on without its data is one the caller cannot carry out. `rcp
		-- notes gate:notes > out` gave a "sleep" with nothing to sleep on before
		-- this, and the job ended on it.
		return wroteOk, wroteLines, control, data
	end

	-- The lines as the command MADE them, not as a screen would show them. Folding
	-- at sixty columns here folded them for every destination at once, and only one
	-- of them is a screen: `grep root /etc/passwd | cut -d: -f1` answered "root"
	-- and then "n", because the sixty-fourth column of that line had become a
	-- second line before cut ever saw it. The fold belongs to the last step, and
	-- the last step already knows it -- CeroSecOSVM's outLine puts a line down a
	-- pipe, into a $( ) and into the file `>` named whole, and folds only what is
	-- going to the glass. A refusal above is folded because a refusal IS a screen
	-- line: it never travels to any of the three.
	return ok, lines, control, data
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
			redirect.who or cont.cmd, redirect, CeroSecOS.linesToText(lines), env)
		return wroteOk, wroteLines, control
	end

	-- Unfolded, for the reason runArgs hands its own back unfolded: the answer to
	-- a question is still a command's output and still has a pipe, a capture or a
	-- file in front of it -- `sudo cat /etc/passwd | cut -d: -f1` is the same line
	-- with a password in the middle of it.
	return ok, lines, control, data
end
