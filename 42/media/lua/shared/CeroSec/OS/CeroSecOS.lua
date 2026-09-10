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

-- Markers the terminal honours; they travel as ordinary strings in the output
-- array so nothing exotic ever reaches the game.
CeroSecOS.CLEAR = "\1CLEAR"
CeroSecOS.EXIT = "\1EXIT"

CeroSecOS.DEFAULT_HOSTNAME = "cerosec"
CeroSecOS.MOTD = "CeroSec OS 1.0 -- unauthorized access is prohibited."

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
-- is hard-wrapped. Markers pass through untouched.
function CeroSecOS.fit(lines)
	local out = {}
	for i = 1, #lines do
		local s = lines[i]
		if type(s) ~= "string" then s = tostring(s) end
		if s == CeroSecOS.CLEAR or s == CeroSecOS.EXIT then
			out[#out + 1] = s
		else
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
	end
	return out
end
