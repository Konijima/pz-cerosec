--
-- CeroSec OS core: cron.
--
-- A machine that does something at four in the morning, with nobody standing at
-- it. The whole of it is Vixie's model, because that is the cron these machines
-- would have had:
--
--   * a file per account under /var/spool/cron, named after the account. The
--     directory is root's and 700, the files are root's and 600, and the only
--     way in is crontab(1) -- which is why `crontab` is the one command on this
--     machine that reaches a file its caller may not read.
--   * five fields and a command: minute, hour, day of the month, month, day of
--     the week. "*", lists, ranges and steps, and the shorthands @reboot,
--     @hourly, @daily and the rest.
--   * a minute is either due or it is gone. Nothing is run late and nothing is
--     run twice: a machine whose chunk was not loaded at 04:00, or that was
--     switched off, does not run 04:00's line when it comes back. Real cron does
--     not either -- that is what anacron was invented for, and there is no
--     anacron here.
--   * what a job prints goes to the account's mail and never to the screen.
--     There is nobody at the screen at four in the morning, and a line that
--     appeared on it out of nowhere would be a machine talking to itself.
--
-- What is NOT here, and is said out loud rather than half-built: no -u (a root
-- who wants somebody else's crontab edits the file), no environment lines
-- (SHELL=, MAILTO=), no names for months or weekdays, and no @reboot catching up
-- on a machine that was off. Each of those is a thing to add, not a thing to
-- pretend about.
--
-- The daemon is not here. This file knows what a crontab MEANS; the server's
-- scheduler (SCeroSecJobs.lua) is what asks it, once a game minute, and what
-- makes the jobs -- because only the machine knows how many jobs it already has.
--

CeroSecOS = CeroSecOS or {}
CeroSecOS.commands = CeroSecOS.commands or {}

local commands = CeroSecOS.commands

--
-- Where it all lives
--

CeroSecOS.VAR_PATH = "/var"
CeroSecOS.SPOOL_PATH = "/var/spool"
CeroSecOS.CRON_PATH = "/var/spool/cron"
CeroSecOS.LOG_PATH = "/var/log"
CeroSecOS.CRON_LOG_PATH = "/var/log/cron"
CeroSecOS.MAIL_PATH = "/var/mail"
-- The one directory on the machine anybody may write in, and the reason it can be
-- one: only the account that owns a file there may take it away (see
-- CeroSecOS.isSticky). Real ones wear a fourth mode digit for that -- 1777 -- and
-- the modes here are three digits everywhere, on the disk and in `ls -l` and in
-- chmod's grammar alike, so the RULE is the path's and not the node's. That is
-- how the quota exemptions already work, and the manual says so where it says
-- 777.
CeroSecOS.TMP_PATH = "/var/tmp"
CeroSecOS.TMP_MODE = 777

-- The spool is 700 and root's: a crontab is a list of things that will run as
-- somebody, so nobody reads anybody else's and nobody writes his own except
-- through crontab(1). The two others are ordinary 755 directories, because what
-- is in them is a file per account with a mode of its own.
CeroSecOS.CRON_DIR_MODE = 700
CeroSecOS.CRONTAB_MODE = 600
-- The log is root's to read: syslog's files are, and a line in it says what
-- somebody's machine did at four in the morning.
CeroSecOS.CRON_LOG_MODE = 640
CeroSecOS.MAIL_MODE = 600

-- Lines in one crontab. Vixie has no such number; this machine does, because a
-- file here is 4096 bytes and a minute on it is 32 lines of work that all come
-- due at once.
CeroSecOS.CRON_MAX_LINES = 32

-- The log and the mailboxes are bounded and are exempt from the disk quota by
-- their PATH, exactly as ~/.sh_history is (see the exemption section of
-- CeroSecOSFS.lua): a machine must not fill its own disk with what it said
-- about itself while nobody was looking.
CeroSecOS.CRON_LOG_LINES = 100
CeroSecOS.CRON_LOG_BYTES = 4096
CeroSecOS.MAIL_LINES = 100
CeroSecOS.MAIL_BYTES = 4096

function CeroSecOS.cronPath(user)
	return CeroSecOS.CRON_PATH .. "/" .. tostring(user)
end

function CeroSecOS.mailPath(user)
	return CeroSecOS.MAIL_PATH .. "/" .. tostring(user)
end

-- /var and the three directories under it, made where they are missing and left
-- exactly as they are where they are not. Used by a fresh machine, by the
-- migration that tops an older one up, and by the BIOS repair -- and by nothing
-- a player can reach: root deleting /var is root's right and stays done.
function CeroSecOS.ensureVar(state)
	if type(state) ~= "table" then return nil end
	local var = CeroSecOS.ensureSystemDir(state, "var")
	if var == nil then return nil end
	local function under(name, mode)
		local node = var.children[name]
		if type(node) ~= "table" or node.type ~= "dir" or type(node.children) ~= "table" then
			node = CeroSecOS.newDir("root", mode)
			var.children[name] = node
		end
		return node
	end
	local spool = under("spool", 755)
	if type(spool.children.cron) ~= "table" or spool.children.cron.type ~= "dir" then
		spool.children.cron = CeroSecOS.newDir("root", CeroSecOS.CRON_DIR_MODE)
	end
	-- And at's queue beside cron's, on the same terms and for the same reason: a
	-- job that will run AS somebody is not a file anybody else may read or write.
	if type(spool.children.at) ~= "table" or spool.children.at.type ~= "dir" then
		spool.children.at = CeroSecOS.newDir("root", CeroSecOS.AT_DIR_MODE)
	end
	under("log", 755)
	under("mail", 755)
	-- The scratch directory. Written to by everybody, emptied by nobody but the
	-- owner of what is in it.
	under("tmp", CeroSecOS.TMP_MODE)
	return var
end

--
-- The crontab format
--
-- Vixie's, field for field, and his refusals word for word: what crontab(1)
-- prints when a line will not parse is the file it was in, the line it was on,
-- and which field went wrong.
--
--   "/var/spool/cron/admin":1: bad minute
--
-- The eight reasons are his eight, spelled as the ecodes table in his crontab.c
-- spells them.
--

CeroSecOS.CRON_FIELDS = {
	{ name = "minute", lo = 0, hi = 59 },
	{ name = "hour", lo = 0, hi = 23 },
	{ name = "day-of-month", lo = 1, hi = 31 },
	{ name = "month", lo = 1, hi = 12 },
	-- Seven is Sunday as well as zero, the way every cron has taken it.
	{ name = "day-of-week", lo = 0, hi = 7 },
}

-- The shorthands, and what each of them is the long way round. @reboot is the
-- one that is not a time at all and is marked rather than expanded.
CeroSecOS.CRON_SPECIALS = {
	reboot = "reboot",
	yearly = "0 0 1 1 *",
	annually = "0 0 1 1 *",
	monthly = "0 0 1 * *",
	weekly = "0 0 * * 0",
	daily = "0 0 * * *",
	midnight = "0 0 * * *",
	hourly = "0 * * * *",
}

-- How a refusal about a crontab reads: the file in quotes, the line, the reason.
-- Vixie's shape exactly, including the colon with no space in front of it.
function CeroSecOS.cronError(path, line, reason)
	return "\"" .. tostring(path) .. "\":" .. tostring(line) .. ": " .. tostring(reason)
end

-- One number, within the field. nil when it is not one.
local function cronNumber(text, lo, hi)
	if string.find(text, "^%d+$") == nil then return nil end
	local n = tonumber(text)
	if n == nil or n < lo or n > hi then return nil end
	return n
end

-- One piece of a list: "*", "5", "1-5", "*/5" or "1-5/2". Fills the set, or
-- answers false.
local function cronPiece(set, text, lo, hi)
	local body, step = text, 1
	local slash = string.find(text, "/", 1, true)
	if slash ~= nil then
		body = string.sub(text, 1, slash - 1)
		local n = cronNumber(string.sub(text, slash + 1), 1, hi - lo + 1)
		if n == nil then return false end
		step = n
	end

	local first, last
	if body == "*" then
		first, last = lo, hi
	else
		local dash = string.find(body, "-", 1, true)
		if dash == nil then
			-- A single number, and a step behind one is not a range: Vixie reads
			-- a step only after "*" or after a range, so `5/10` is not a field.
			if slash ~= nil then return false end
			first = cronNumber(body, lo, hi)
			if first == nil then return false end
			last = first
		else
			first = cronNumber(string.sub(body, 1, dash - 1), lo, hi)
			last = cronNumber(string.sub(body, dash + 1), lo, hi)
			if first == nil or last == nil then return false end
			-- A range that runs backwards is not a range. Vixie refuses it too.
			if last < first then return false end
		end
	end

	local v = first
	while v <= last do
		set[v] = true
		v = v + step
	end
	return true
end

-- One field -> the set of values it matches, plus whether it was nothing but a
-- "*" (which is what decides the day-of-month against day-of-week rule below).
-- nil when the field is not one.
function CeroSecOS.parseCronField(text, lo, hi)
	if type(text) ~= "string" or text == "" then return nil end
	local set, star = {}, text == "*"
	local from = 1
	while true do
		local comma = string.find(text, ",", from, true)
		local piece
		if comma == nil then
			piece = string.sub(text, from)
		else
			piece = string.sub(text, from, comma - 1)
		end
		if not cronPiece(set, piece, lo, hi) then return nil end
		if comma == nil then break end
		from = comma + 1
	end
	return set, star
end

local function blankSplit(text)
	local words = {}
	for word in string.gmatch(text, "[^ \t]+") do words[#words + 1] = word end
	return words
end

-- One line of a crontab -> an entry, or nil plus the reason. A comment or a
-- blank line is neither: it comes back as nil with no reason at all, which is
-- what "there is nothing on this line" means.
--
-- An entry is plain tables:
--   { min = {set}, hour = {set}, dom = {set}, month = {set}, dow = {set},
--     domStar = true, dowStar = true, cmd = "echo hi" }
-- or, for the one shorthand that is not a time:
--   { reboot = true, cmd = "echo hi" }
function CeroSecOS.parseCronLine(text)
	if type(text) ~= "string" then return nil, "bad minute" end
	local body = string.match(text, "^[ \t]*(.-)[ \t]*$") or ""
	if body == "" then return nil end
	if string.sub(body, 1, 1) == "#" then return nil end

	if string.sub(body, 1, 1) == "@" then
		local word = string.match(body, "^@([%a]*)")
		local rest = string.match(body, "^@[%a]*[ \t]+(.*)$")
		-- Case for case, the way Vixie compares them: @Daily is not a shorthand.
		local long = CeroSecOS.CRON_SPECIALS[word or ""]
		if long == nil then return nil, "bad time specifier" end
		if rest == nil or rest == "" then return nil, "bad command" end
		if long == "reboot" then return { reboot = true, cmd = rest } end
		return CeroSecOS.parseCronLine(long .. " " .. rest)
	end

	local words = blankSplit(body)
	local fields = CeroSecOS.CRON_FIELDS
	local sets, stars = {}, {}
	for i = 1, #fields do
		local field = fields[i]
		if words[i] == nil then return nil, "bad " .. field.name end
		local set, star = CeroSecOS.parseCronField(words[i], field.lo, field.hi)
		if set == nil then return nil, "bad " .. field.name end
		sets[i], stars[i] = set, star
	end

	-- Seven is Sunday and so is zero: one set holds both, so a line that says
	-- either matches the same day.
	if sets[5][7] then sets[5][0] = true end

	-- Everything after the five fields is the command, whole, blanks and all:
	-- it is a line of shell and not a list of words.
	local cmd = body
	for i = 1, #fields do
		local from = string.find(cmd, words[i], 1, true)
		cmd = string.sub(cmd, from + #words[i])
	end
	cmd = string.match(cmd, "^[ \t]*(.-)[ \t]*$") or ""
	if cmd == "" then return nil, "bad command" end

	return { min = sets[1], hour = sets[2], dom = sets[3], month = sets[4], dow = sets[5],
		domStar = stars[3], dowStar = stars[5], cmd = cmd }
end

-- A whole crontab -> the entries it holds and the refusals it carries, each with
-- the line it is on. Both are answered: a file with one bad line in it is a file
-- crontab(1) refuses whole, and one already on the disk is a file the daemon
-- runs the good lines of and complains about the rest -- which is exactly what
-- Vixie's does with a crontab that was put there behind its back.
function CeroSecOS.parseCrontab(text)
	local entries, errors = {}, {}
	local lines = CeroSecOS.splitLines(text or "")
	for i = 1, #lines do
		local entry, reason = CeroSecOS.parseCronLine(lines[i])
		if entry ~= nil then
			if #entries >= CeroSecOS.CRON_MAX_LINES then
				errors[#errors + 1] = { line = i, reason = "too many entries" }
				return entries, errors
			end
			entry.line = i
			entries[#entries + 1] = entry
		elseif reason ~= nil then
			errors[#errors + 1] = { line = i, reason = reason }
		end
	end
	return entries, errors
end

-- What crontab(1) says about a file it will not install: the first refusal in
-- it, worded and located Vixie's way. nil when the file is one.
function CeroSecOS.checkCrontab(path, text)
	local _, errors = CeroSecOS.parseCrontab(text)
	if #errors == 0 then return nil end
	return CeroSecOS.cronError(path, errors[1].line, errors[1].reason)
end

-- Is this entry due at this minute? parts is CeroSecOS.dateParts's table.
--
-- The day rule is the one every cron has and nobody expects: when BOTH the day
-- of the month and the day of the week are restricted, either of them matching
-- is enough -- `0 0 1 * 1` is the first of the month AND every Monday. When one
-- of them is "*" it is the other that decides. Vixie wrote it that way because
-- the crontab(5) of the day did.
function CeroSecOS.cronDue(entry, parts)
	if type(entry) ~= "table" or entry.reboot then return false end
	if type(parts) ~= "table" then return false end
	if not entry.min[parts.min] then return false end
	if not entry.hour[parts.hour] then return false end
	if not entry.month[parts.month] then return false end

	local dom = entry.dom[parts.day] == true
	local dow = entry.dow[parts.wday - 1] == true
	if entry.domStar and entry.dowStar then return true end
	if entry.domStar then return dow end
	if entry.dowStar then return dom end
	return dom or dow
end

--
-- The two bounded files
--
-- The log and a mailbox are written by the MACHINE, not by anybody's command, so
-- they are written the way /etc/passwd is: by absolute path, with no session and
-- no permission check, through a node the kernel made itself. Both are capped by
-- lines and by bytes and both drop the OLDEST first, which is the rule the
-- history file already runs on -- a machine that stopped writing its log because
-- the log was full would be a machine that goes quiet exactly when something is
-- wrong.
--

-- The node at path, made root's with that mode when it is not there yet. nil
-- when it cannot be made -- a /var somebody deleted, a full disk -- and the
-- caller says nothing about it: a line of log that cannot be written is not a
-- reason to break what was being logged.
local function ownFile(state, path, mode, owner)
	-- Not onto a mounted disk: see CeroSecOS.onOwnDrive.
	if not CeroSecOS.onOwnDrive(state, path) then return nil end
	local node = CeroSecOS.systemNode(state, path)
	if type(node) == "table" then
		if node.type ~= "file" then return nil end
		return node
	end
	local file = CeroSecOS.newFile(owner or "root", mode, "")
	local made = CeroSecOS.createNode(state, CeroSecOS.rootSession(), path, file)
	if made == nil then return nil end
	return CeroSecOS.systemNode(state, path)
end

-- Lines onto the end of one of them, trimmed to both ceilings. Not through
-- setData: these two files are exempt from the disk quota by their path and are
-- capped here instead, exactly as historyPut caps the history.
local function appendBounded(state, node, lines, maxLines, maxBytes, now)
	local kept = CeroSecOS.splitLines(node.data or "")
	for i = 1, #lines do
		local line = lines[i]
		if type(line) == "string" and not CeroSecOS.hasControlBytes(line) then
			kept[#kept + 1] = line
		end
	end
	while #kept > maxLines do table.remove(kept, 1) end
	local text = table.concat(kept, "\n")
	while #text > maxBytes and #kept > 1 do
		table.remove(kept, 1)
		text = table.concat(kept, "\n")
	end
	if #text > maxBytes then text = string.sub(text, #text - maxBytes + 1) end
	node.data = text
	if now ~= nil then node.mtime = now end
	return true
end

-- One line into /var/log/cron. Where a real one would call syslog: there is no
-- syslog on this machine, so the file IS the log, and it is bounded because
-- nothing else bounds it.
function CeroSecOS.cronLog(state, text, now)
	local node = ownFile(state, CeroSecOS.CRON_LOG_PATH, CeroSecOS.CRON_LOG_MODE)
	if node == nil then return false end
	local stamp = ""
	if now ~= nil then stamp = CeroSecOS.formatStamp(now) .. " " end
	return appendBounded(state, node, { stamp .. tostring(text) },
		CeroSecOS.CRON_LOG_LINES, CeroSecOS.CRON_LOG_BYTES, now)
end

-- What a cron job printed, into the account's mailbox, with the two lines a
-- mailbox has always carried in front of it: the "From " line that separates one
-- message from the next, and the Subject cron itself writes.
function CeroSecOS.mailAppend(state, user, host, cmd, lines, now)
	if type(lines) ~= "table" or #lines == 0 then return false end
	local node = ownFile(state, CeroSecOS.mailPath(user), CeroSecOS.MAIL_MODE, user)
	if node == nil then return false end
	local out = {}
	if cmd ~= nil then
		local when = ""
		if now ~= nil then when = "  " .. CeroSecOS.formatDate(now) end
		out[#out + 1] = "From cron" .. when
		out[#out + 1] = "Subject: Cron <" .. tostring(user) .. "@" .. tostring(host)
			.. "> " .. tostring(cmd)
		out[#out + 1] = ""
	end
	for i = 1, #lines do out[#out + 1] = lines[i] end
	return appendBounded(state, node, out, CeroSecOS.MAIL_LINES,
		CeroSecOS.MAIL_BYTES, now)
end

--
-- crontab
--
-- The one command that reaches a file its caller may not: /var/spool/cron is
-- 700 and root's, and this is the program real Unix makes setuid root so that an
-- account can have a crontab without being able to write one for anybody else.
-- -e opens the editor on it AS ROOT, which is the whole of the privilege and is
-- spent on exactly one path.
--

local function noCrontab(user)
	return false, { "no crontab for " .. tostring(user) }
end

commands.crontab = function(state, session, args, env)
	if #args ~= 2 then
		return false, { "crontab: usage: " .. CeroSecOS.commandUsage("crontab") }
	end
	local user = CeroSecOS.userOf(session)
	local path = CeroSecOS.cronPath(user)
	-- Read with no session, the way the kernel reads /etc/passwd: the file is
	-- root's and 600, and this command is the reason it can be.
	local node = CeroSecOS.systemNode(state, path)
	local text = ""
	if type(node) == "table" and node.type == "file" then text = node.data or "" end

	if args[2] == "-l" then
		if text == "" then return noCrontab(user) end
		return true, CeroSecOS.splitLines(text)
	end

	if args[2] == "-r" then
		if type(node) ~= "table" or node.type ~= "file" then return noCrontab(user) end
		local done, reason = CeroSecOS.removeNode(state, CeroSecOS.rootSession(), path, false,
			CeroSecOS.clockOf(env))
		if done == nil then return false, { "crontab: " .. path .. ": " .. reason } end
		return true, {}
	end

	if args[2] == "-e" then
		-- The file has to exist before the editor opens on it, so that it is
		-- root's and 600 from the start rather than whatever a save would have
		-- made it. An empty one is no crontab at all, so quitting the editor
		-- without typing anything leaves the account exactly as it was.
		if type(node) ~= "table" or node.type ~= "file" then
			local file = CeroSecOS.newFile("root", CeroSecOS.CRONTAB_MODE, "")
			local made, reason = CeroSecOS.createNode(state, CeroSecOS.rootSession(), path,
				file, CeroSecOS.clockOf(env))
			if made == nil then return false, { "crontab: " .. path .. ": " .. reason } end
		end
		return true, {}, "edit", {
			path = path, text = text, readonly = false,
			-- The privilege, and the only place it is spent: the save is root's
			-- write, on this path, because crontab is what opened it.
			user = "root",
			-- What the save is judged against before it is installed.
			crontab = true,
		}
	end

	return false, { "crontab: usage: " .. CeroSecOS.commandUsage("crontab") }
end

--
-- at: the one job, at the one time
--
-- cron is a line that comes round again; at is a thing to do ONCE, at a time you
-- name, and then forget. Both are 1993's, both run through the same machinery
-- here -- the queue is read once a game minute by the same sweep that reads the
-- crontabs, a job becomes an ordinary background job of the account's, and what it
-- prints goes to that account's mail because nobody is standing at the screen.
--
-- ONE difference from cron, and it is at's own: a job whose time has PASSED still
-- runs. cron's minute is either due or it is gone -- there is no anacron here and a
-- machine that was off at four in the morning did not run four o'clock's line --
-- but an at job is a thing somebody asked for, it sits in the spool until it has
-- been done, and atrun on a real machine catches up on it the same way when the
-- machine comes back.
--
-- The queue is /var/spool/at, one FILE per job, named by the job number: root's at
-- 600 like a crontab, in a directory that is root's at 700, and `at` is the
-- program that reaches them on an account's behalf -- the same setuid-root shape
-- crontab(1) has here and for the same reason. So the queue survives a save
-- because the filesystem does, and `sudo cat /var/spool/at/1` is how an
-- administrator reads what somebody queued.
--
-- The FILE's shape is this machine's own, like the tar container: a header line
-- and the commands after it.
--
--   at admin 742122960
--   echo the lights are off > /home/admin/night.log
--
-- A real at wrote a shell script with the whole environment in it, which on a
-- machine with a 4096-byte file would be a header longer than anything anybody
-- queues. What is not ours is anything a player sees: the times, the numbers, the
-- listing and the refusals are at(1)'s, atq(1)'s and atrm(1)'s.
--

CeroSecOS.AT_PATH = "/var/spool/at"
-- The directory is root's and 700 for the crontab's reason: a queued job is a
-- thing that will run AS somebody, so nobody reads anybody else's and nobody
-- writes his own except through at(1).
CeroSecOS.AT_DIR_MODE = 700
CeroSecOS.AT_JOB_MODE = 600
-- The first word of a job file, so a file that is not one is not read as one.
CeroSecOS.AT_MAGIC = "at"

function CeroSecOS.atJobPath(n)
	return CeroSecOS.AT_PATH .. "/" .. tostring(n)
end

-- The text of a job file. Pure, like the tar container's two halves.
function CeroSecOS.atText(user, when, cmd)
	return CeroSecOS.AT_MAGIC .. " " .. tostring(user) .. " " .. tostring(math.floor(when))
		.. "\n" .. tostring(cmd)
end

-- And back: the account, the second it is due, and the commands. nil for a file
-- that is not a job file at all -- one root wrote by hand, or something else that
-- ended up at that name.
function CeroSecOS.atParse(text)
	if type(text) ~= "string" then return nil end
	local nl = string.find(text, "\n", 1, true)
	if nl == nil then return nil end
	local user, when = string.match(string.sub(text, 1, nl - 1),
		"^" .. CeroSecOS.AT_MAGIC .. " (%S+) (%d+)$")
	if user == nil then return nil end
	local cmd = string.sub(text, nl + 1)
	if cmd == "" then return nil end
	return user, tonumber(when), cmd
end

-- Every job in the queue, by number: { n =, user =, when =, cmd = }. Read with no
-- session, the way the kernel reads /etc/passwd -- the directory is root's and this
-- is what makes `at -l` able to answer at all.
function CeroSecOS.atJobs(state)
	local out = {}
	local dir = CeroSecOS.systemNode(state, CeroSecOS.AT_PATH)
	if type(dir) ~= "table" or dir.type ~= "dir" then return out end
	local names = CeroSecOS.childNames(dir)
	for i = 1, #names do
		local n = tonumber(names[i])
		local node = dir.children[names[i]]
		-- A name that is not a number is not a job of ours, and neither is anything
		-- that is not a file: both are left exactly where they are.
		if n ~= nil and string.find(names[i], "^%d+$") ~= nil
				and type(node) == "table" and node.type == "file" then
			local user, when, cmd = CeroSecOS.atParse(node.data or "")
			if user ~= nil then
				out[#out + 1] = { n = n, user = user, when = when, cmd = cmd }
			end
		end
	end
	-- By number, which is by the order they were queued in: the numbers are handed
	-- out lowest-free-first, so this is not the order they will RUN in and `at -l`
	-- says the time beside each one for that reason.
	for i = 2, #out do
		local hold = out[i]
		local k = i - 1
		while k >= 1 and out[k].n > hold.n do
			out[k + 1] = out[k]
			k = k - 1
		end
		out[k + 1] = hold
	end
	return out
end

-- The number the next job gets: the lowest that is free. A real at counts up for
-- ever; this one reuses a number the moment its job has run, because the number is
-- the file's NAME here and a name is 32 characters -- and because a survivor who
-- queues one job a day for a year should not be typing `atrm 365`.
function CeroSecOS.atFree(state)
	local taken = {}
	local jobs = CeroSecOS.atJobs(state)
	for i = 1, #jobs do taken[jobs[i].n] = true end
	local dir = CeroSecOS.systemNode(state, CeroSecOS.AT_PATH)
	local n = 1
	while taken[n] do n = n + 1 end
	-- The spool is a directory and a directory holds MAX_DIR_ENTRIES: a queue that
	-- is full is a queue at said so, not a job quietly lost.
	if type(dir) == "table" and dir.type == "dir"
			and CeroSecOS.countEntries(dir) >= CeroSecOS.MAX_DIR_ENTRIES then
		return nil
	end
	return n
end

-- "at HH:MM" -> the second that time next comes round, counting from `now`. Today
-- if it has not happened yet, tomorrow if it has, which is what at(1) does with a
-- time and no date: `at 04:00` at nine in the morning means four tomorrow.
-- nil for anything that is not a time.
function CeroSecOS.atWhen(text, now)
	if type(text) ~= "string" or type(now) ~= "number" then return nil end
	local hh, mm = string.match(text, "^(%d%d?):(%d%d)$")
	if hh == nil then return nil end
	local hour, min = tonumber(hh), tonumber(mm)
	if hour > 23 or min > 59 then return nil end
	local parts = CeroSecOS.dateParts(now)
	local midnight = now - (parts.hour * 3600 + parts.min * 60 + parts.sec)
	local when = midnight + hour * 3600 + min * 60
	if when <= now then when = when + 86400 end
	return when
end

--
-- mail
--
-- What the machine has to say to an account that was not standing there. It
-- shows the mailbox and empties it, which is what mail does when you read your
-- mail and quit: the spool is the account's own, 600, so reading it needs no
-- privilege at all.
--

commands.mail = function(state, session, args, env)
	if #args ~= 1 then
		return false, { "mail: usage: " .. CeroSecOS.commandUsage("mail") }
	end
	local user = CeroSecOS.userOf(session)
	local path = CeroSecOS.mailPath(user)
	local node, reason = CeroSecOS.getNode(state, session, path)
	if node == nil then
		if reason == "no such file" then return true, { "No mail for " .. tostring(user) } end
		return false, { "mail: " .. path .. ": " .. reason }
	end
	if node.type ~= "file" then return false, { "mail: " .. path .. ": " .. CeroSecOS.notAFile(node) } end
	if not CeroSecOS.can(state, session, node, "r") then
		return false, { "mail: " .. path .. ": permission denied" }
	end
	local text = node.data or ""
	if text == "" then return true, { "No mail for " .. tostring(user) } end
	if not CeroSecOS.can(state, session, node, "w") then
		return false, { "mail: " .. path .. ": permission denied" }
	end
	local lines = CeroSecOS.splitLines(text)
	-- Read is read: the mailbox is emptied through the ordinary write path, on
	-- the account's own authority, so a mailbox that cannot be emptied is a
	-- mailbox that is not shown as read.
	local done, why = CeroSecOS.setData(state, session, path, "", CeroSecOS.clockOf(env))
	if done == nil then return false, { "mail: " .. path .. ": " .. why } end
	return true, lines
end
