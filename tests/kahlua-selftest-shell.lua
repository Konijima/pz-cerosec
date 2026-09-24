-- The self-test's shell half (CeroSecSelfTestShell.lua), RUN on the game's own
-- Kahlua through tools/KahluaRun.java --eval, and on lua5.1 by hand:
--   lua5.1 tests/kahlua-selftest-shell.lua
--
-- tests/selftest_shell_test.lua already demands FAIL 0 of the table on lua5.1.
-- This is the same table on the VM the player has, offline: every failing case
-- on a line of its own, then the summary, and tests/kahlua-run.sh fails unless
-- the summary says FAIL 0. It is not a diff against lua5.1 like the probe --
-- each case already carries its own expected answer.
--
-- What it cannot be is the game: no vanilla Lua, no event bus, so the ticks the
-- server spreads the run over are not here, only the cases.

-- lua5.1 loads the files; under --eval KahluaRun has already loaded shared/ in
-- the game's own order, and loadfile does not exist there.
if CeroSecOS == nil then
	local SHARED = "42/media/lua/shared/CeroSec/"
	local FILES = {
		"CeroSecSelfTestShell",
		"OS/CeroSecOS", "OS/CeroSecOSComplete", "OS/CeroSecOSCron", "OS/CeroSecOSDev",
		"OS/CeroSecOSDisk", "OS/CeroSecOSFS", "OS/CeroSecOSNet", "OS/CeroSecOSPath",
		"OS/CeroSecOSScript", "OS/CeroSecOSRadio", "OS/CeroSecOSShell",
		"OS/CeroSecOSState", "OS/CeroSecOSSystem", "OS/CeroSecOSUsers", "OS/CeroSecOSVM",
	}
	for i = 1, #FILES do
		local path = SHARED .. FILES[i] .. ".lua"
		local chunk, err = loadfile(path)
		if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
		chunk()
	end
end

local result = CeroSecSelfTest.runShell()
for i = 1, #result.lines do print(result.lines[i]) end
print(CeroSecSelfTest.shellSummary(result))
