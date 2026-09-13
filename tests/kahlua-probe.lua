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
-- THE BODY IS NOT HERE ANY MORE. It is CeroSecSelfTest.vectors, in
-- 42/media/lua/shared/CeroSec/CeroSecSelfTest.lua, and that is a file the mod
-- SHIPS -- so the same body has three readers: this script prints it on both VMs,
-- tools/make-selftest-vectors.lua writes down lua5.1's answers, and
-- CeroSecSelfTest.run() runs it inside the game off the debug window's
-- `selftest` button. One body, because a vector table written by hand beside a
-- probe written by hand is two lists that drift, and the day they drift the
-- vectors say what the engine used to answer.
--
-- HOW TO ADD TO IT: a say() line in CeroSecSelfTest.probe, then
-- `lua5.1 tools/make-selftest-vectors.lua`. The rules for what may go in one are
-- at the head of that file: a pure function of nothing, never a clock, a random
-- number, table ORDER or a path, and always through say().
--
-- Run by hand:
--   lua5.1 tests/kahlua-probe.lua
--

-- lua5.1 loads the files; under --eval KahluaRun has already loaded shared/ in
-- the game's own order, and loadfile does not exist there.
if CeroSecOS == nil then
	local SHARED = "42/media/lua/shared/CeroSec/"
	local DIR = SHARED .. "OS/"
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
	-- CeroSecDefs for the three key lists the vectors ask about, the catalogue for
	-- the derivation, and the self-test itself for the body. The game loads all
	-- three ahead of OS/ and so does every other bench; here they come after it
	-- only because the guard above is asked of CeroSecOS.
	local rest = { "CeroSecDefs", "CeroSecContent", "CeroSecSelfTest" }
	for i = 1, #rest do
		local path = SHARED .. rest[i] .. ".lua"
		local chunk, err = loadfile(path)
		if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
		chunk()
	end
end

local function say(name, value)
	print(name .. " = " .. tostring(value))
end

CeroSecSelfTest.vectors(say)
