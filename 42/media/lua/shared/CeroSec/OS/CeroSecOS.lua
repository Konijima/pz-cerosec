--
-- CeroSec OS core: the loader file.
--
-- The game loads every file under media/lua/shared in alphabetical order and
-- without require, so this file sorts first ("CeroSecOS." < "CeroSecOSF") and
-- every other OS file only extends the table it creates here. Nothing below
-- runs at load time in another file, so the order never matters beyond this.
--
-- The whole core is pure Lua: no game API, no os/io/require, no coroutines, no
-- metatables. It runs under lua5.1 and under the game's Kahlua alike. Every
-- state it produces is plain nested tables of strings, numbers and booleans,
-- because the game serializes it into an object's modData.
--

CeroSecOS = CeroSecOS or {}

CeroSecOS.STATE_VERSION = 1

-- What the machine's own system files are expected to hold, as opposed to what
-- shape the state is in. STATE_VERSION is the schema and moving it throws a save
-- away; this one is the CONTENTS -- which executables are standard, which files
-- /etc is expected to have -- and moving it tops an older machine up on the way
-- in, once, without touching anything a player put there.
--
-- 2: /bin/sudo, /bin/shutdown, /bin/reboot, /bin/restart and /etc/sudoers.
-- 3: /bin/date, /bin/df, /bin/grep, /bin/head, /bin/tail, /bin/wc, /bin/man.
-- 4: /bin/adduser, /bin/deluser, /bin/id, /bin/su.
CeroSecOS.SYSTEM_VERSION = 4

-- The screen the terminal will draw is 60 x 20 and wraps nothing, so every
-- output line the core emits is at most COLS characters.
CeroSecOS.COLS = 60

-- Limits, enforced in one place each (see CeroSecOSFS.lua).
CeroSecOS.MAX_NAME = 32          -- characters in a single path component
CeroSecOS.MAX_FILE_BYTES = 4096  -- bytes in one file
CeroSecOS.MAX_DIR_ENTRIES = 64   -- files + dirs directly inside one dir
CeroSecOS.MAX_NODES = 256        -- nodes on the whole computer, root included
-- The disk. One number, because the machine has one drive: it is what the
-- BIOS announces at power-on ("hda 32K"), what df divides by, and what the
-- write path refuses to go past. MAX_TOTAL_BYTES is the name the limits are
-- read under, DISK_BYTES the name the hardware is read under; they are the
-- same number by construction and never two numbers that can drift apart.
CeroSecOS.DISK_BYTES = 32768
CeroSecOS.MAX_TOTAL_BYTES = CeroSecOS.DISK_BYTES -- sum of every file's data
CeroSecOS.MAX_DEPTH = 16         -- path components below /

-- Control the terminal honours travels out of band, as exec's third return
-- value ("clear", "exit", "prompt", "edit", "shutdown" or "reboot"), never as a
-- line inside the output array: a line of text and an order to the terminal
-- must not be the same kind of thing, or a file's contents can be made to look
-- like an order.
CeroSecOS.DEFAULT_HOSTNAME = "cerosec"
CeroSecOS.MOTD = "CeroSec OS 1.0 -- unauthorized access is prohibited."

-- The system files. Every one of them is a real file on the machine's own
-- disk, and every one of them is the truth about what it holds: the parser is
-- what the OS believes, not a copy kept beside it in the state. So root editing
-- /etc/passwd with the editor changes who may log in, and rm -r /bin really
-- does take the commands away.
CeroSecOS.BIN_PATH = "/bin"
CeroSecOS.ETC_PATH = "/etc"
-- Where an account's home is made. A home is the account's own and nobody
-- else's: 750, so the owner reads, writes and enters it and everybody else
-- stays outside it.
CeroSecOS.HOME_PATH = "/home"
CeroSecOS.HOME_MODE = 750
CeroSecOS.PASSWD_PATH = "/etc/passwd"
CeroSecOS.SUDOERS_PATH = "/etc/sudoers"
CeroSecOS.MOTD_PATH = "/etc/motd"
CeroSecOS.HOSTNAME_PATH = "/etc/hostname"

-- /etc/passwd holds the hashes, so it is root's and nobody else reads it. The
-- kernel does not go through the permission bits to parse it (systemNode), the
-- way a real one does not either.
CeroSecOS.PASSWD_MODE = 600

-- /etc/sudoers says who may become root, so it is root's and it is read-only
-- even to him: 440, the mode a real one wears, so that a stray redirect cannot
-- rewrite the list of people who may run as root. Root may still edit it -- root
-- walks through the bits everywhere -- but he has to mean it.
CeroSecOS.SUDOERS_MODE = 440

-- A machine name is 1..16 characters of [a-z0-9-] and never starts with "-".
-- The leading digit rule is isValidName's: the name is also written into the
-- state, where validate tests it as a name, so a hostname that is not one would
-- make the machine unbootable the moment it was set.
CeroSecOS.HOSTNAME_MAX = 16

-- Lines of /etc/motd that are put on the screen after a login. A file is up to
-- 4096 bytes and the console keeps a hundred lines; a motd is a greeting, not a
-- book.
CeroSecOS.MOTD_MAX_LINES = 10

-- Every command table lives here; the shell looks up args[1] in it.
CeroSecOS.commands = CeroSecOS.commands or {}

--
-- Small string helpers, shared by the shell.
--

-- Cut a string down to width, marking the cut with a trailing "~".
function CeroSecOS.truncate(s, width)
	if #s <= width then return s end
	if width <= 1 then return string.sub("~", 1, width) end
	return string.sub(s, 1, width - 1) .. "~"
end

-- Pad on the right to width (never cuts; callers truncate first).
function CeroSecOS.padRight(s, width)
	if #s >= width then return s end
	return s .. string.rep(" ", width - #s)
end

-- Pad on the left to width.
function CeroSecOS.padLeft(s, width)
	if #s >= width then return s end
	return string.rep(" ", width - #s) .. s
end

-- Text the OS stores must be printable: every byte below 0x20 is refused except
-- newline and tab. This is what keeps a file's contents from ever being taken
-- for anything but text on the way to the screen.
-- Scanned byte by byte on purpose: matching the zero byte in a Lua 5.1 pattern
-- needs %z, and that is the kind of corner not worth betting on under Kahlua.
function CeroSecOS.hasControlBytes(text)
	if type(text) ~= "string" then return false end
	for i = 1, #text do
		local b = string.byte(text, i)
		if b < 32 and b ~= 10 and b ~= 9 then return true end
	end
	return false
end

-- Split a blob of text into display lines. An empty file has no lines at all,
-- which is what cat on an empty file should print.
function CeroSecOS.splitLines(text)
	local out = {}
	if text == nil or text == "" then return out end
	local start = 1
	while true do
		local p = string.find(text, "\n", start, true)
		if p == nil then
			out[#out + 1] = string.sub(text, start)
			return out
		end
		out[#out + 1] = string.sub(text, start, p - 1)
		start = p + 1
	end
end

-- Last gate before output leaves the core: one array entry is one screen line.
-- Embedded newlines become separate entries and anything wider than the screen
-- is hard-wrapped. Every entry is text and only text; nothing here is ever
-- inspected for a special value.
function CeroSecOS.fit(lines)
	local out = {}
	for i = 1, #lines do
		local s = lines[i]
		if type(s) ~= "string" then s = tostring(s) end
		local pieces = CeroSecOS.splitLines(s)
		if #pieces == 0 then pieces = { "" } end
		for p = 1, #pieces do
			local piece = pieces[p]
			if #piece <= CeroSecOS.COLS then
				out[#out + 1] = piece
			else
				local j = 1
				while j <= #piece do
					out[#out + 1] = string.sub(piece, j, j + CeroSecOS.COLS - 1)
					j = j + CeroSecOS.COLS
				end
			end
		end
	end
	return out
end

--
-- The disk, as a label.
--

-- What the BIOS says it found and what df calls the drive. Whole kilobytes
-- while the disk is one -- 32768 bytes is "32K" and not "32.0K" -- and whole
-- megabytes past that, so a bigger drive at a later rung does not print a
-- five-digit K.
function CeroSecOS.diskLabel()
	local bytes = CeroSecOS.DISK_BYTES
	if bytes >= 1048576 then return tostring(math.floor(bytes / 1048576)) .. "MB" end
	if bytes >= 1024 then return tostring(math.floor(bytes / 1024)) .. "K" end
	return tostring(bytes) .. "B"
end

CeroSecOS.DISK_NAME = "hda"

--
-- The clock
--
-- The engine has no clock of its own and never asks for one: a time is HANDED
-- to exec, in env.now, by whoever is running the machine. The server passes the
-- game's calendar (see SCeroSecSystem:clockEnv); a test passes a fixed number;
-- nobody passing anything at all means the machine has no clock, which `date`
-- says out loud and which leaves every timestamp at 0.
--
-- env.now is ONE number: seconds since 1970-01-01 00:00:00, counted on the
-- calendar the game is showing. A number is what a node can carry into the save
-- file, what two mtimes can be compared as, and what a formatted table could
-- never be without the engine trusting whoever built it.
--
-- Everything below is arithmetic on that number. The standard library's own
-- date and time functions are not used and could not be: the core is pure, and
-- the whole os library is out of reach under Kahlua.
--

CeroSecOS.MONTH_NAMES = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}
-- Indexed 1..7 from Sunday, the way the day-of-week arithmetic below lands.
CeroSecOS.DAY_NAMES = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

-- Days from 1970-01-01 to y-m-d (proleptic Gregorian, month 1..12, day 1..31).
-- Hinnant's days_from_civil, with math.floor around every division: the 5.3
-- integer-division operator is forbidden in the core, and rounding toward zero
-- is not something to bet on under Kahlua.
local function daysFromCivil(y, m, d)
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = math.fmod(m + 9, 12)
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- The way back.
local function civilFromDays(z)
	z = z + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524)
		- math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = mp + 3
	if mp >= 10 then m = mp - 9 end
	if m <= 2 then y = y + 1 end
	return y, m, d
end

-- A calendar the game hands over -> the one number the engine carries.
function CeroSecOS.timeFromParts(year, month, day, hour, min, sec)
	if type(year) ~= "number" or type(month) ~= "number" or type(day) ~= "number" then
		return nil
	end
	hour = tonumber(hour) or 0
	min = tonumber(min) or 0
	sec = tonumber(sec) or 0
	return daysFromCivil(math.floor(year), math.floor(month), math.floor(day)) * 86400
		+ math.floor(hour) * 3600 + math.floor(min) * 60 + math.floor(sec)
end

-- The number -> a calendar. Always a table, never nil: a timestamp of 0 is a
-- real date (1970-01-01) and is what an unstamped node prints as.
function CeroSecOS.dateParts(t)
	if type(t) ~= "number" then t = 0 end
	t = math.floor(t)
	local days = math.floor(t / 86400)
	local rest = t - days * 86400
	local y, m, d = civilFromDays(days)
	-- Day of the year, counted the way strftime's %j counts it: 1 on January
	-- the first. Worked out here because this is where the civil arithmetic
	-- lives, and it is one subtraction from the days the year began on.
	local yday = days - daysFromCivil(y, 1, 1) + 1
	-- 1970-01-01 was a Thursday, which is index 5 of DAY_NAMES.
	local wday = math.fmod(math.fmod(days + 4, 7) + 7, 7) + 1
	return {
		year = y, month = m, day = d,
		hour = math.floor(rest / 3600),
		min = math.floor(math.fmod(math.floor(rest / 60), 60)),
		sec = math.floor(math.fmod(rest, 60)),
		wday = wday,
		yday = yday,
	}
end

local function two(n)
	if n < 10 then return "0" .. tostring(n) end
	return tostring(n)
end

-- What `date` prints: "Thu Jul  8 14:32:00 1993". The day of the month is
-- blank-padded to two, the way every Unix date since the seventies has done it.
function CeroSecOS.formatDate(t)
	local p = CeroSecOS.dateParts(t)
	return CeroSecOS.DAY_NAMES[p.wday] .. " " .. CeroSecOS.MONTH_NAMES[p.month]
		.. " " .. CeroSecOS.padLeft(tostring(p.day), 2)
		.. " " .. two(p.hour) .. ":" .. two(p.min) .. ":" .. two(p.sec)
		.. " " .. tostring(p.year)
end

local function zeros(n, width)
	local s = tostring(n)
	while #s < width do s = "0" .. s end
	return s
end

-- What `date +FORMAT` prints: as much of strftime as this machine has.
--
-- The codes are the ones somebody writing a script on it will reach for, and
-- they pad the way Unix pads -- %d is "08" and %e is " 8", which is the whole
-- difference between them. %s is the number itself, the very number that goes
-- into a node's mtime, so `date +%s` is how a script gets at the clock the
-- filesystem is stamped with.
--
-- Anything else is copied out exactly as it was typed, "%" and all: a machine
-- that swallowed the codes it does not have would be a machine whose output
-- silently lost a column. A "%" at the very end of the format is one of those.
function CeroSecOS.formatTime(t, format)
	if type(format) ~= "string" then format = "" end
	if type(t) ~= "number" then t = 0 end
	t = math.floor(t)
	local p = CeroSecOS.dateParts(t)
	local out, i = "", 1
	while i <= #format do
		local c = string.sub(format, i, i)
		if c ~= "%" then
			out = out .. c
			i = i + 1
		else
			local code = string.sub(format, i + 1, i + 1)
			local piece = nil
			if code == "Y" then piece = tostring(p.year)
			elseif code == "m" then piece = two(p.month)
			elseif code == "d" then piece = two(p.day)
			elseif code == "e" then piece = CeroSecOS.padLeft(tostring(p.day), 2)
			elseif code == "H" then piece = two(p.hour)
			elseif code == "M" then piece = two(p.min)
			elseif code == "S" then piece = two(p.sec)
			elseif code == "j" then piece = zeros(p.yday, 3)
			elseif code == "a" then piece = CeroSecOS.DAY_NAMES[p.wday]
			elseif code == "b" then piece = CeroSecOS.MONTH_NAMES[p.month]
			elseif code == "s" then piece = tostring(t)
			elseif code == "%" then piece = "%"
			end
			if piece == nil then piece = c .. code end
			out = out .. piece
			i = i + 2
		end
	end
	return out
end

-- What `ls -l` prints: "Jul  8 14:32", exactly 12 characters wide whatever the
-- date, because it sits in a fixed column.
function CeroSecOS.formatStamp(t)
	local p = CeroSecOS.dateParts(t)
	return CeroSecOS.MONTH_NAMES[p.month] .. " " .. CeroSecOS.padLeft(tostring(p.day), 2)
		.. " " .. two(p.hour) .. ":" .. two(p.min)
end

-- The clock exec was handed, or nil when it was handed none. The ONE place the
-- engine reads env, so a caller that passes junk is a machine without a clock
-- and never a machine with a wrong one.
function CeroSecOS.clockOf(env)
	if type(env) ~= "table" then return nil end
	if type(env.now) ~= "number" then return nil end
	return math.floor(env.now)
end

-- A node's timestamp. Absent is 0: every node made before this build has none,
-- and validate accepts them, so nothing anywhere may read node.mtime raw.
function CeroSecOS.mtimeOf(node)
	if type(node) ~= "table" or type(node.mtime) ~= "number" then return 0 end
	return node.mtime
end

-- Stamp a node and everything under it. What a create costs: a fresh file, a
-- fresh directory and every node of a `cp -r` all carry the moment the copy was
-- made, the way cp without -p does.
function CeroSecOS.stampTree(node, now)
	if now == nil or type(node) ~= "table" then return end
	node.mtime = now
	if node.children == nil then return end
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do CeroSecOS.stampTree(node.children[names[i]], now) end
end
