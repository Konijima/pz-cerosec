--
-- The engine's pure functions, RUN, with fixed inputs, one line per result.
--
-- This file is run twice -- on lua5.1 and on the game's own Kahlua, through
-- tools/KahluaRun.java --eval -- and tests/kahlua-run.sh fails if the two
-- outputs are not byte for byte the same. That is the whole point: every other
-- bench in tests/ runs on lua5.1 only, and kahlua-run.sh LOADS the files
-- without running anything, so a standard-library function that answers
-- differently under Kahlua is invisible to all of them.
--
-- The day this was written that was not a hypothetical. tonumber(s, 16) goes
-- through Integer.parseInt(s, 16) in Kahlua (javap on
-- se.krka.kahlua.vm.KahluaUtil), so it returned NIL for every eight-digit hash
-- from "80000000" up -- half of them -- and the first power-on of a prefilled
-- machine died on "__add not defined for operands in placeLog". Every file
-- loaded. Every bench was green.
--
-- HOW TO ADD TO IT: print a LINE, with a name in front of it, for anything the
-- engine gets out of the standard library or out of arithmetic -- a format
-- pattern, a negative modulo, a byte at the ends of the range, a number turned
-- into a string. Never print anything that depends on a clock, a random number,
-- table ORDER (pairs is not ordered) or a path: this has to be a pure function
-- of nothing, or the diff cries wolf. And print through say() below, which
-- keeps one value to a line and tostring()s it in the VM under it -- number
-- formatting is one of the things being compared.
--
-- Run by hand:
--   lua5.1 tests/kahlua-probe.lua
--

-- lua5.1 loads the files; under --eval KahluaRun has already loaded shared/ in
-- the game's own order, and loadfile does not exist there.
if CeroSecOS == nil then
	local DIR = "42/media/lua/shared/CeroSec/OS/"
	local FILES = {
		"CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSDev",
		"CeroSecOSDisk", "CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath",
		"CeroSecOSScript", "CeroSecOSRadio", "CeroSecOSShell", "CeroSecOSState",
		"CeroSecOSSystem", "CeroSecOSUsers", "CeroSecOSVM",
	}
	for i = 1, #FILES do
		local path = DIR .. FILES[i] .. ".lua"
		local chunk, err = loadfile(path)
		if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
		chunk()
	end
	local path = "42/media/lua/shared/CeroSec/CeroSecContent.lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end

local function say(name, value)
	print(name .. " = " .. tostring(value))
end

-- A secret of the shape CeroSecContent.isSecret wants, and fixed forever: the
-- values below are what they are because of this string, so changing it
-- rewrites every line and proves nothing.
local SECRET = "0123456789abcdef"

--
-- tonumber's replacement, at the edges. The first three lines are the bug.
--
say("hexValue 7fffffff", CeroSecOS.hexValue("7fffffff"))
say("hexValue 80000000", CeroSecOS.hexValue("80000000"))
say("hexValue ffffffff", CeroSecOS.hexValue("ffffffff"))
say("hexValue 00000000", CeroSecOS.hexValue("00000000"))
say("hexValue 0", CeroSecOS.hexValue("0"))
say("hexValue f", CeroSecOS.hexValue("f"))
say("hexValue deadbeef", CeroSecOS.hexValue("deadbeef"))
say("hexValue DEADBEEF", CeroSecOS.hexValue("DEADBEEF"))
say("hexValue empty", CeroSecOS.hexValue(""))
say("hexValue g", CeroSecOS.hexValue("g"))
say("hexValue nil", CeroSecOS.hexValue(nil))
say("hexValue number", CeroSecOS.hexValue(255))
-- The raw tonumber(s, 16) is deliberately NOT probed here: it answers nil on
-- Kahlua and a number on lua5.1 and always will, so a line for it would be a
-- red that never goes green. The four lines above are the canary instead --
-- point hexValue back at tonumber and they differ, which is how this probe was
-- proven to catch the bug it was written for.

--
-- The mixer, at the rounds the mod actually uses.
--
say("digest empty 16", CeroSecOS.digest("", 16))
say("digest cerosec 16", CeroSecOS.digest("cerosec", 16))
say("digest long 16", CeroSecOS.digest(string.rep("ab", 40), 16))
say("digest hi 0", CeroSecOS.digest("hi", 0))
say("digest hi 4000", CeroSecOS.digest("hi", CeroSecOS.HASH_ROUNDS))
say("digest 255 bytes", CeroSecOS.digest(string.char(0, 1, 127, 128, 255), 16))

--
-- The content derivation: the two functions the first power-on runs.
--
say("derive root", CeroSecContent.derive(SECRET, "root"))
say("derive logh", CeroSecContent.derive(SECRET, "office.logh.1"))
say("derive bad", CeroSecContent.derive(SECRET, "has/slash"))
say("key parts", CeroSecContent.key("Coffee Shop", "logh", 3))
for i = 1, 6 do
	say("number logh " .. i, CeroSecContent.number(SECRET,
		CeroSecContent.key("office", "logh", i), 10))
	say("number logm " .. i, CeroSecContent.number(SECRET,
		CeroSecContent.key("office", "logm", i), 60))
end
say("number n1", CeroSecContent.number(SECRET, "root", 1))
say("number n100", CeroSecContent.number(SECRET, "root", 100))
say("chance 50 root", CeroSecContent.chance(SECRET, "root", 50))

--
-- The phone line: the number a machine prints on its BIOS line.
--
say("phoneKey 0 0", CeroSecOS.phoneKey(0, 0))
say("phoneKey 12 34", CeroSecOS.phoneKey(12, 34))
say("phoneKey 255 255", CeroSecOS.phoneKey(255, 255))
say("phoneKey bad", CeroSecOS.phoneKey(-1, 0))
say("phoneText min 0", CeroSecOS.phoneText(CeroSecOS.PHONE_EXCHANGE_MIN, 0))
say("phoneText min 7", CeroSecOS.phoneText(CeroSecOS.PHONE_EXCHANGE_MIN, 7))
say("phoneText max last", CeroSecOS.phoneText(CeroSecOS.PHONE_EXCHANGE_MAX,
	CeroSecOS.PHONE_NUMBERS - 1))
say("phoneText out", CeroSecOS.phoneText(CeroSecOS.PHONE_EXCHANGE_MAX,
	CeroSecOS.PHONE_NUMBERS))

--
-- string.format, in the patterns the shell's columns are built out of.
--
say("format f", string.format("%5.2f", 3.14159))
say("format f neg", string.format("%5.2f", -0.5))
say("format s left", "[" .. string.format("%-8s", "ab") .. "]")
say("format s right", "[" .. string.format("%8s", "ab") .. "]")
say("format 02d", string.format("%02d", 7))
say("format 02d big", string.format("%02d", 123))
say("format d zero", string.format("%d", 0))
say("format x", string.format("%x", 255))
say("format percent", string.format("%d%%", 50))
say("format two", string.format("%s:%d", "a", 12))

--
-- Arithmetic that the placer and the columns depend on, at the signs and the
-- sizes where VMs differ.
--
say("fmod 7 3", math.fmod(7, 3))
say("fmod -7 3", math.fmod(-7, 3))
say("fmod 7 -3", math.fmod(7, -3))
say("fmod big", math.fmod(4294967295, 60))
say("mod 7 3", 7 % 3)
say("mod -7 3", -7 % 3)
say("mod 7 -3", 7 % -3)
say("floor -0.5", math.floor(-0.5))
say("floor div", math.floor(-7 / 3))
say("tostring 1e15", tostring(1e15))
say("tostring int", tostring(42))
say("tostring div", tostring(10 / 2))
say("tostring third", tostring(1 / 3))
say("tostring neg zero", tostring(0 - 0))

--
-- Bytes and strings at the ends of the range.
--
say("byte of 0", string.byte(string.char(0)))
say("byte of 255", string.byte(string.char(255)))
say("len char 0", #string.char(0, 65, 0))
say("byte middle", string.byte(string.char(0, 65, 0), 2))
say("rep 0", "[" .. string.rep("ab", 0) .. "]")
say("rep 3", string.rep("ab", 3))
say("sub past end", "[" .. string.sub("abc", 2, 99) .. "]")
say("sub negative", string.sub("abcdef", -3))
say("upper", string.upper("aBc1"))
say("gsub count", select(2, string.gsub("a.b.c", "%.", "-")))
say("find plain", tostring(string.find("a.b", ".", 1, true)))
say("concat", table.concat({ "a", "b", "c" }, ","))
say("concat numbers", table.concat({ 1, 2, 3 }, "-"))
say("concat empty", "[" .. table.concat({}, ",") .. "]")

--
-- The calendar the log placer steps in: no os.time anywhere, the engine's own
-- civil arithmetic over a fixed stamp.
--
local START = CeroSecOS.timeFromParts(1993, 7, 9, 9, 0, 0)
say("timeFromParts start", START)
local midnight = math.floor(START / 86400) * 86400
say("midnight", midnight)
for i = 1, 3 do
	local at = midnight - (8 - i) * 86400 + 11 * 3600 + 42 * 60
	say("formatStamp " .. i, CeroSecOS.formatStamp(at))
end
say("formatStamp zero", CeroSecOS.formatStamp(0))
say("formatDate start", CeroSecOS.formatDate(START))
say("formatTime start", CeroSecOS.formatTime(START, "%Y-%m-%d %H:%M:%S j=%j %a %b s=%s %% %q"))
local p = CeroSecOS.dateParts(START)
say("dateParts", p.year .. "-" .. p.month .. "-" .. p.day
	.. " " .. p.hour .. ":" .. p.min .. ":" .. p.sec)
say("dateParts of zero", (function()
	local z = CeroSecOS.dateParts(0)
	return z.year .. "-" .. z.month .. "-" .. z.day
end)())

--
-- The small string helpers every column in the shell goes through.
--
say("truncate long", CeroSecOS.truncate("abcdefgh", 4))
say("truncate exact", CeroSecOS.truncate("abcd", 4))
say("padRight", "[" .. CeroSecOS.padRight("ab", 5) .. "]")
say("padLeft", "[" .. CeroSecOS.padLeft("ab", 5) .. "]")
say("hasControlBytes no", CeroSecOS.hasControlBytes("ab\tc\nd"))
say("hasControlBytes yes", CeroSecOS.hasControlBytes("ab" .. string.char(7)))
