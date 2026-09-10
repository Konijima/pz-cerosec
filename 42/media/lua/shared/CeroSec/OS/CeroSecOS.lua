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
CeroSecOS.SYSTEM_VERSION = 2

-- The screen the terminal will draw is 60 x 20 and wraps nothing, so every
-- output line the core emits is at most COLS characters.
CeroSecOS.COLS = 60

-- Limits, enforced in one place each (see CeroSecOSFS.lua).
CeroSecOS.MAX_NAME = 32          -- characters in a single path component
CeroSecOS.MAX_FILE_BYTES = 4096  -- bytes in one file
CeroSecOS.MAX_DIR_ENTRIES = 64   -- files + dirs directly inside one dir
CeroSecOS.MAX_NODES = 256        -- nodes on the whole computer, root included
CeroSecOS.MAX_TOTAL_BYTES = 32768 -- sum of every file's data
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
