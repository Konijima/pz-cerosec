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

-- The SHAPE the state is in, and the number the migration chain counts against.
-- Every step from an older shape to this one is a function in
-- CeroSecOS.MIGRATIONS (see the head of the migration section in
-- CeroSecOSState.lua), so moving this number keeps a save instead of throwing it
-- away -- which is the whole reason it had never been moved before.
--
-- 2: the accounts file and the quota flags. Two repairs that were done on EVERY
--    read of the state, unversioned, because there was no number that could say
--    they had already been done: state.users -> /etc/passwd with hashed
--    passwords (CeroSecOS.migrateUsers), and the `nq` flag swept off every node
--    of the filesystem (the exemption is a PATH now, CeroSecOS.exemptPaths).
CeroSecOS.STATE_VERSION = 2

-- What the machine's own system files are expected to hold, as opposed to what
-- shape the state is in. STATE_VERSION is the schema, and a save written in an
-- older one is walked up to it by the chain; this one is the CONTENTS -- which
-- executables are standard, which files /etc is expected to have -- and moving
-- it tops an older machine up on the way in, once, without touching anything a
-- player put there.
--
-- Which of the two to move is the question every wave asks, and the answer is
-- what the change IS: a file the machine ships in /bin or /etc is CONTENTS and
-- moves sysv; a field of the state itself -- one renamed, one dropped, one whose
-- meaning changed -- is the SHAPE and moves STATE_VERSION with a migration
-- beside it. See docs/CONTRIBUTING.md.
--
-- 2: /bin/sudo, /bin/shutdown, /bin/reboot, /bin/restart and /etc/sudoers.
-- 3: /bin/date, /bin/df, /bin/grep, /bin/head, /bin/tail, /bin/wc, /bin/man.
-- 4: /bin/adduser, /bin/deluser, /bin/id, /bin/su.
-- 5: /bin/chgrp, /bin/gpasswd, /bin/groupadd, /bin/groupdel, /bin/groups and
--    /etc/group.
-- 6: /bin/dev.
-- 7: /bin/sh, /bin/ps, /bin/jobs, /bin/kill, /bin/wait.
-- 8: /bin/halt, and the six the shell runs itself but still looks up first --
--    /bin/echo was already there, /bin/sleep, /bin/printf, /bin/test, /bin/[,
--    /bin/true and /bin/false were not. And the one version that TAKES
--    something away: /bin/cd, /bin/exit, /bin/jobs and /bin/wait, which every
--    version up to 7 seeded and which never had anything behind them -- a
--    program cannot move the shell that ran it. They are deleted where they are
--    exactly what was shipped (root, 755, the seeded description) and left alone
--    anywhere else.
-- 9: /bin/sort and /bin/uniq, the two commands a pipeline is built to reach;
--    /bin/crontab and /bin/mail, and the /var tree the two of them live on --
--    /var/spool/cron, /var/log and /var/mail.
-- 10: the network. /bin/ifconfig, /bin/ping, /bin/rlogin, /bin/rsh, /bin/rcp,
--    /bin/ruptime, /bin/rwho, /bin/who, /bin/last, and the two files a name and
--    a trust are looked up in -- /etc/hosts and /etc/hosts.equiv. The machine's
--    own line in /etc/hosts is not seeded here: it needs an address, which is a
--    fact about the building and is only known once the server has looked (see
--    CeroSecOS.writeOwnHost).
-- 11: the shell that looks a name up. /bin/which, /bin/ln and /bin/readlink --
--    `type` is a word the shell IS and has no file, like cd -- plus the two
--    places the filesystem grew: /dev/null, the device that reads empty and
--    swallows what is written to it, and /var/tmp, the directory anybody may
--    write in and only the owner of a file may delete from.
-- 12: the floppy drive. /bin/mount, /bin/umount and /bin/newfs, and the one
--    directory a disk is mounted on: /mnt, root's at 755 and shipped empty. The
--    device it is mounted FROM is not seeded and never could be -- /dev/fd0
--    exists for the length of one command and only while there is a disk in the
--    slot (see CeroSecOSDisk.lua).
-- 13: the telephone. /bin/cu, and nothing else -- the line itself is a fact
--    about the building and is on no disk, so there is no file to seed for it and
--    no /etc/phone to read: the number is announced by the firmware and by cu,
--    the way an address is announced and never stored twice.
-- 14: the radio. /bin/call, and /etc/callsign -- the one file of the three links
--    that IS on the disk, because a callsign is a licence and root may change it
--    (see CeroSecOS.ensureCallsign).
-- 15: /bin/arp, which is how a survivor learns the ADDRESSES on his wire: ruptime
--    broadcasts names and /etc/hosts wants an address, and nothing on the disk
--    joined the two. No file behind it -- an Ethernet address is derived from the
--    network address and stored nowhere (CeroSecOS.etherOf).
-- 16: the names 1993 really used. /bin/useradd, /bin/userdel and /bin/usermod
--    (System V, 1989; Solaris 2, 1992) and /bin/mkpasswd seeded; /bin/adduser,
--    /bin/deluser, /bin/gpasswd and /bin/hash DELETED -- the first version since
--    8 to take a file away, on the very rule that one ran on (see
--    CeroSecOS.RETIRED_BIN and the deletion half of upgradeSystem). And the
--    `wheel` pair, which is what replaces the "admin flag" `adduser -a` set: the
--    group itself, empty, and the `%wheel` line in /etc/sudoers that grants it.
-- 17: the radio, the way 1993 reached one. /bin/call DELETED -- it was invented
--    here, and a TNC is a box on a serial line, so the box is reached with
--    `cu -l /dev/radio0` and driven with the TNC-2's own commands (see the head of
--    CeroSecOSRadio.lua). Nothing is seeded: cu is already on the disk.
CeroSecOS.SYSTEM_VERSION = 17

-- The screen the terminal will draw is 60 x 20 and wraps nothing, so every
-- output line the core emits is at most COLS characters.
CeroSecOS.COLS = 60
-- And how many rows it has, which only the PAGER needs: `more` fills a screenful
-- and then asks. Named here beside the width, and named twice in the mod on
-- purpose -- CeroSec.ROWS is the terminal's, which never loads this file -- with
-- os_test pinning the two against each other, exactly as it pins the width.
CeroSecOS.ROWS = 20

-- Limits, enforced in one place each (see CeroSecOSFS.lua).
CeroSecOS.MAX_NAME = 32          -- characters in a single path component
CeroSecOS.MAX_FILE_BYTES = 4096  -- bytes in one file
-- Files and directories directly inside one directory.
--
-- 96, and the number that decides it is /bin's: the shipped commands were 64 of
-- them at the ceiling of 64, which is a /bin with no room in it -- a command put
-- back by hand after an `rm` was refused as "directory full", and the next wave
-- that adds one could not seed it at all. So the ceiling is the shipped set plus
-- room for a third as many again: yours in /bin, and a wave's worth of honest
-- growth. The DISK is what bounds a machine (MAX_NODES, 64K); this bounds one
-- LISTING, and a listing of 96 short names is six screens of columns.
CeroSecOS.MAX_DIR_ENTRIES = 96
CeroSecOS.MAX_NODES = 512        -- nodes on the whole computer, root included
-- The hard disk. One number, because the machine has one FIXED drive: it is what
-- the BIOS announces at power-on ("hda 64K"), what df divides by, and what the
-- write path refuses to go past. MAX_TOTAL_BYTES is the name the limits are
-- read under, DISK_BYTES the name the hardware is read under; they are the
-- same number by construction and never two numbers that can drift apart.
--
-- 64K and 512 nodes, twice what the machine shipped with, and the number that
-- decides it is the FLOPPY's. A 3.5-inch disk held 1.44 MB in 1993 and the hard
-- disk of a desk machine of that year held twenty-odd megabytes: a floppy was
-- about seven per cent of the drive it was carried to. That ratio is what makes
-- a disk worth carrying -- a floppy that held a third of the machine would be a
-- second hard disk, and one that held a thousandth would be a keepsake -- so the
-- floppy is 4096 bytes (one maximal file, or a dozen notes) and the drive is the
-- sixteen of them the ratio asks for. The nodes go with the bytes: 32 on the
-- floppy, 512 on the drive.
--
-- An older machine off a save file gains the room and loses nothing: the quota
-- is asked of the tree at every write and there is no stored total to move (see
-- CeroSecOS.upgradeSystem, which does not have to know about this at all).
CeroSecOS.DISK_BYTES = 65536
CeroSecOS.MAX_TOTAL_BYTES = CeroSecOS.DISK_BYTES -- sum of every file's data

-- The floppy. The same two ceilings the hard disk has, for the disk in the drive
-- on the front of the case: what `newfs` initialises, what `df` reports beside
-- hda while one is mounted, and what a write under /mnt dies on. A file's own
-- ceiling is NOT halved with it -- MAX_FILE_BYTES is the machine's and is 4096
-- everywhere -- so a floppy holds exactly one file as big as a file gets.
CeroSecOS.FLOPPY_BYTES = 4096
CeroSecOS.FLOPPY_NODES = 32
CeroSecOS.MAX_DEPTH = 16         -- path components below /

-- A symbolic link holds a PATH, so how long one may be is what a path may be on
-- this machine: every component at its own ceiling, sixteen of them, and a
-- separator in front of each. Derived and never eyeballed -- a link that could
-- hold more than the filesystem can address would be a link that cannot be
-- followed, and one that could hold less would refuse a path the machine allows.
CeroSecOS.MAX_LINK_BYTES = CeroSecOS.MAX_DEPTH * (CeroSecOS.MAX_NAME + 1)

-- How many symbolic links one path may go through before the machine gives up.
--
-- Eight, which is what the Unix these machines are from uses (MAXSYMLINKS), and
-- it is counted per RESOLUTION and not per component: a link to a link to a link
-- is three of them, and a link that points at itself is eight and then
-- "too many levels of symbolic links". That is what makes a loop cost a bounded
-- number of steps instead of hanging the machine.
CeroSecOS.MAX_LINK_HOPS = 8

-- What the disk quota does not count is bounded twice over -- once per file and
-- once for the whole machine -- and both of those numbers are sums of the three
-- ceilings involved (the history, a mailbox, the cron log). They are written
-- where all three are already written down, beside the history file's own, in
-- CeroSecOSShell.lua: CeroSecOS.MAX_EXEMPT_BYTES and
-- CeroSecOS.HISTORY_EXEMPT_BYTES. Nothing here, so there is no second copy of a
-- number this file cannot see.

-- Control the terminal honours travels out of band, as exec's third return
-- value ("clear", "exit", "prompt", "edit", "shutdown" or "reboot"), never as a
-- line inside the output array: a line of text and an order to the terminal
-- must not be the same kind of thing, or a file's contents can be made to look
-- like an order.
CeroSecOS.DEFAULT_HOSTNAME = "cerosec"

-- The operating system's own version, and the ONLY place it is written down.
-- Every string in the world that names it -- the greeting the boot ends on and
-- a login is met with, the manual's own cover -- is built from this one, so a
-- player never reads two different numbers for the same machine. The BIOS is a
-- separate component with its own number (CeroSec.BIOS_VERSION), and the mod's
-- release version in mod.info is a third thing again: neither is this.
CeroSecOS.VERSION = "1.0"

CeroSecOS.MOTD = "CeroSec OS " .. CeroSecOS.VERSION ..
	" -- unauthorized access is prohibited."

-- The system files. Every one of them is a real file on the machine's own
-- disk, and every one of them is the truth about what it holds: the parser is
-- what the OS believes, not a copy kept beside it in the state. So root editing
-- /etc/passwd with the editor changes who may log in, and rm -r /bin really
-- does take the commands away.
CeroSecOS.BIN_PATH = "/bin"
CeroSecOS.ETC_PATH = "/etc"
-- What PATH holds on a machine nobody has changed it on: the one directory the
-- commands ship in. A login puts it in the shell's environment
-- (CeroSecOS.loginVars), a script and a cron line start with it
-- (CeroSecOS.newJob), and a shell that has no PATH at all falls back on it --
-- see CeroSecOS.pathValue for why absent and empty are not the same thing.
CeroSecOS.DEFAULT_PATH = "/bin"

-- How many directories a lookup will walk.
--
-- Every command a shell runs is a walk along PATH, so the length of that string
-- is the price of every command on the machine -- and a kilobyte of it is three
-- hundred and forty directories, which is three hundred and forty walks of the
-- filesystem for one `ls`. Measured, that is a command twenty times dearer than
-- the budget believes it is, which is a budget that no longer protects anybody
-- (tests/hostile_test.lua carries the numbers).
--
-- So the ceiling is eight, which is the number this machine uses everywhere it
-- means "more than anybody writes" -- the stages of a pipeline, the depth of a
-- script inside a script. A PATH with more in it is refused where it is SET, with
-- a reason, the way every other ceiling here is refused; the walk stops at eight
-- as well, so a value that came off a save file nobody can explain is slow for
-- nobody.
CeroSecOS.MAX_PATH_DIRS = 8
-- Where an account's home is made. A home is the account's own and nobody
-- else's: 750, so the owner reads, writes and enters it and everybody else
-- stays outside it.
CeroSecOS.HOME_PATH = "/home"
CeroSecOS.HOME_MODE = 750
CeroSecOS.PASSWD_PATH = "/etc/passwd"
CeroSecOS.GROUP_PATH = "/etc/group"
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

-- /etc/group holds no secret -- it is who shares files with whom -- so it is
-- readable by everybody and writable by root: 644, the mode a real one wears.
-- `groups` and `id` read it for any account, so a mode that hid it would only
-- make two commands lie.
CeroSecOS.GROUP_MODE = 644

-- The group 4.4BSD gates `su` on, and the one the shipped /etc/sudoers grants
-- with a `%wheel` line: putting an account in it is what "make this account an
-- administrator" means on this machine, and it is what `useradd -G wheel` does.
-- The name lives here, above both files that mean the same group by it.
CeroSecOS.WHEEL_GROUP = "wheel"

-- The four groups a machine ships with, and the only ones groupdel refuses to
-- take away: root's own, wheel, the one the devices belong to, and the one an
-- account joins to share files. wheel is here for the reason the others are --
-- /etc/sudoers names it, and a `groupdel wheel` would be a line in that file
-- pointing at nothing.
CeroSecOS.GROUP_KEEP = { root = true, sudo = true, users = true,
	[CeroSecOS.WHEEL_GROUP] = true }

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

-- a modulo b, by hand, because the "%" OPERATOR is not the same function under
-- the two VMs either. Kahlua compiles `a % b` as `a - (int)(a / b) * b`
-- (javap -c se.krka.kahlua.vm.KahluaThread, primitiveMath, case OP_MOD), and
-- that (int) is Java's d2i, which CLAMPS at 2147483647. So Kahlua's "%" is
-- simply wrong the moment the quotient reaches 2^31 -- measured on both VMs,
-- with big = 47564 * 3266489917: big % 65536 is 60828 under lua5.1 and
-- 14629838122396 on Kahlua. That is the shape of the mixer's mul(), so every
-- hash the game computed was a different number from every hash the bench
-- computed, silently, from the first line of the mod.
--
-- math.fmod is NOT affected (it is MathLib, and it agrees on both VMs at every
-- size and both signs -- tests/kahlua-probe.lua pins that), so this exists for
-- the "%" operator only.
--
-- Non-negative operands only, and that is the whole contract: floor division
-- makes this Lua 5.1's "%" exactly, and every caller in the mod is working in
-- 32-bit lanes. nil for b <= 0 and for a negative a -- a caller that has a
-- negative left operand normalises it first (CeroSecOS.phoneKey's scatter does)
-- rather than betting on a sign convention two VMs disagree about. Exact while
-- a stays under 2^53, which is nine orders of magnitude above the 2^48 the
-- mixer reaches.
function CeroSecOS.mod(a, b)
	if type(a) ~= "number" or type(b) ~= "number" then return nil end
	if b <= 0 or a < 0 then return nil end
	return a - math.floor(a / b) * b
end

-- The value of a string of hex digits, by hand, because tonumber(s, 16) is not
-- the same function under the two VMs. Kahlua's base-16 path is
-- Integer.parseInt(s, 16) (proven with javap on se.krka.kahlua.vm.KahluaUtil),
-- so anything from "80000000" up throws NumberFormatException and comes back
-- NIL -- half of every eight-digit hash -- while lua5.1 hands back the 32-bit
-- value. Digits multiplied out one at a time give lua5.1's answer on both, so
-- the numbers a save already holds stay the numbers they were.
--
-- nil for anything that is not one or more hex digits, which is what
-- tonumber(s, 16) does too. Up to thirteen digits stay exact in a double; the
-- mod never asks for more than eight.
local HEX_DIGITS = {}
for i = 0, 9 do HEX_DIGITS[string.sub("0123456789", i + 1, i + 1)] = i end
for i = 0, 5 do
	HEX_DIGITS[string.sub("abcdef", i + 1, i + 1)] = 10 + i
	HEX_DIGITS[string.sub("ABCDEF", i + 1, i + 1)] = 10 + i
end

function CeroSecOS.hexValue(s)
	if type(s) ~= "string" or #s == 0 then return nil end
	local v = 0
	for i = 1, #s do
		local d = HEX_DIGITS[string.sub(s, i, i)]
		if d == nil then return nil end
		v = v * 16 + d
	end
	return v
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
-- while the disk is one -- 65536 bytes is "64K" and not "64.0K" -- and whole
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
