-- Unit tests for the pure parts of the terminal: the hostname a computer gives
-- itself, the prompt the server sends down, and the two rings the window keeps.
-- Run from the repo root:
--   lua5.1 tests/terminal_test.lua

local DEFS = "42/media/lua/shared/CeroSec/CeroSecDefs.lua"

local chunk, err = loadfile(DEFS)
if not chunk then error("cannot load " .. DEFS .. ": " .. tostring(err)) end
chunk()

local count = 0
local function check(what, cond)
	count = count + 1
	if not cond then error("FAIL: " .. what, 2) end
end
local function eq(what, got, want)
	count = count + 1
	if got ~= want then
		error("FAIL: " .. what .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
	end
end

--
-- Hostnames
--

eq("origin", CeroSec.hostnameFor(0, 0), "ksp-0-0")
eq("base 36 digits", CeroSec.hostnameFor(35, 36), "ksp-z-10")
-- 10723 = 8*1296 + 9*36 + 31 -> "89v"; 9432 = 7*1296 + 10*36 -> "7a0".
eq("a real map square", CeroSec.hostnameFor(10723, 9432), "ksp-89v-7a0")
eq("a negative coordinate", CeroSec.hostnameFor(-1, 2), "ksp-n1-2")

-- The same square always gives the same name, and two squares never share one.
local seen = {}
for x = 9000, 9040 do
	for y = 12000, 12040 do
		local name = CeroSec.hostnameFor(x, y)
		check("hostname is stable", name == CeroSec.hostnameFor(x, y))
		check("hostname fits in " .. CeroSec.HOSTNAME_MAX, #name <= CeroSec.HOSTNAME_MAX)
		check("hostname " .. name .. " is unique", seen[name] == nil)
		seen[name] = true
	end
end

-- Every name the derivation can produce is a name the OS accepts: 1..32 of
-- [A-Za-z0-9._-] and never a leading "-" (CeroSecOSPath.isValidName). That is
-- why a negative coordinate becomes an "n" and not a minus sign.
local function isValidOSName(name)
	if #name < 1 or #name > 32 then return false end
	if string.find(name, "^%-") ~= nil then return false end
	return string.find(name, "[^A-Za-z0-9._%-]") == nil
end

for _, pair in ipairs({ { 0, 0 }, { 1, -1 }, { -12345, 67890 }, { 15000, 15000 }, { -1, -1 } }) do
	local name = CeroSec.hostnameFor(pair[1], pair[2])
	check("valid OS name for " .. pair[1] .. "," .. pair[2] .. " (" .. name .. ")", isValidOSName(name))
	check("short enough (" .. name .. ")", #name <= CeroSec.HOSTNAME_MAX)
end

-- A fractional coordinate is floored, not rejected: the player's own position
-- is fractional and a caller could pass one by mistake.
eq("floored", CeroSec.hostnameFor(10.7, 4.2), CeroSec.hostnameFor(10, 4))

--
-- The prompt
--

eq("root prompt", CeroSec.prompt("root", "ksp-1-1", "/root", true), "root@ksp-1-1:/root# ")
eq("user prompt", CeroSec.prompt("admin", "ksp-1-1", "/home/admin", false), "admin@ksp-1-1:/home/admin$ ")

-- A path too long for the line is cut at the front, marked the way the OS marks
-- its own cuts, and the prompt never grows past PROMPT_MAX.
local long = CeroSec.prompt("admin", "ksp-abcd-ef", "/home/admin/a/b/c/d/e/f/g/h", false)
check("long prompt is capped", #long <= CeroSec.PROMPT_MAX)
check("long prompt marks the cut", string.find(long, "~", 1, true) ~= nil)
check("long prompt keeps the tail", string.find(long, "h%$ $") ~= nil)

-- Even a hostname that eats the whole line leaves a usable prompt.
local huge = CeroSec.prompt("administrator", "a-very-long-hostname", "/home", false)
check("huge prompt still ends in the sigil", string.sub(huge, -2) == "$ ")

--
-- The scrollback ring
--

local lines = {}
for i = 1, 10 do CeroSec.ringPush(lines, "line " .. i, 4) end
eq("ring keeps its size", #lines, 4)
eq("ring keeps the newest", lines[4], "line 10")
eq("ring dropped the oldest", lines[1], "line 7")

local one = {}
CeroSec.ringPush(one, "a", 1)
CeroSec.ringPush(one, "b", 1)
eq("ring of one", #one, 1)
eq("ring of one keeps the last", one[1], "b")

--
-- Scrolling
--

eq("nothing to scroll", CeroSec.clampScroll(5, 3, 20), 0)
eq("exactly a screenful", CeroSec.clampScroll(1, 20, 20), 0)
eq("one line above", CeroSec.clampScroll(1, 21, 20), 1)
eq("clamped at the top", CeroSec.clampScroll(99, 30, 20), 10)
eq("never below the bottom", CeroSec.clampScroll(-3, 30, 20), 0)

--
-- Input history
--

local history = { "ls", "cd /root", "cat motd" }
local index, text = CeroSec.historyPick(history, 0, 1)
eq("first up is the last line", text, "cat motd")
eq("index moves to 1", index, 1)

index, text = CeroSec.historyPick(history, index, 1)
eq("second up", text, "cd /root")
index, text = CeroSec.historyPick(history, index, 1)
eq("third up", text, "ls")
index, text = CeroSec.historyPick(history, index, 1)
eq("no fourth up", text, "ls")
eq("index stops at the oldest", index, 3)

index, text = CeroSec.historyPick(history, index, -1)
eq("down again", text, "cd /root")
index, text = CeroSec.historyPick(history, 1, -1)
eq("down past the newest is the empty line", text, "")
eq("index back to nothing", index, 0)

index, text = CeroSec.historyPick({}, 0, 1)
eq("no history, nothing to show", text, "")
eq("no history, index stays", index, 0)

--
-- The look: the constants the window draws with have to be there and be sane.
--

eq("60 columns", CeroSec.COLS, 60)
eq("20 rows", CeroSec.ROWS, 20)
for _, name in ipairs({ "screen", "text", "dim", "bright", "bezel", "bezelHi", "bezelLo",
		"barBack", "barText" }) do
	local color = CeroSec.COLORS[name]
	check("colour " .. name .. " exists", type(color) == "table")
	for _, channel in ipairs({ "r", "g", "b" }) do
		local value = color[channel]
		check("colour " .. name .. "." .. channel .. " is 0..1",
			type(value) == "number" and value >= 0 and value <= 1)
	end
end
eq("the inverted bar is the dim green", CeroSec.COLORS.barBack, CeroSec.COLORS.dim)
eq("the inverted bar writes in the screen colour", CeroSec.COLORS.barText, CeroSec.COLORS.screen)

print("terminal_test: " .. count .. " checks passed")
