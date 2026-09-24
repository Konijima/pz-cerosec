-- The self-test's shell half, headless. Run from the repo root:
--   lua5.1 tests/selftest_shell_test.lua
--
-- The table in CeroSecSelfTestShell.lua is what the debug window's Self-test
-- runs in the game, on Kahlua. This runs the SAME table through the SAME runner
-- on lua5.1 and demands FAIL 0, so a case that is wrong about the engine is red
-- here, on a developer's box, before anybody presses a button in a save. Then it
-- breaks things on purpose -- the engine once, the table four ways -- to prove
-- that FAIL 0 is an assertion and not a sentence the runner prints either way.

local DIR = "42/media/lua/shared/CeroSec/OS/"
local FILES = {
	"CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSDev", "CeroSecOSDisk",
	"CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath", "CeroSecOSScript", "CeroSecOSRadio",
	"CeroSecOSShell", "CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers", "CeroSecOSVM",
}
-- The game's order: shared/CeroSec/ first, so the case table must not touch
-- CeroSecOS at its top level. Loaded ahead of OS/ here to hold it to that.
local chunk, err = loadfile("42/media/lua/shared/CeroSec/CeroSecSelfTestShell.lua")
if not chunk then error(err) end
chunk()
for i = 1, #FILES do
	chunk, err = loadfile(DIR .. FILES[i] .. ".lua")
	if not chunk then error(err) end
	chunk()
end

local count, failures = 0, 0
local function check(what, cond)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL: " .. what)
	end
end
local function eq(what, got, want)
	check(what .. " (want " .. tostring(want) .. ", got " .. tostring(got) .. ")", got == want)
end
local function mentions(result, text)
	for i = 1, #result.lines do
		if string.find(result.lines[i], text, 1, true) ~= nil then return true end
	end
	return false
end

local CASES = CeroSecSelfTest.SHELL_CASES

-- 1. The table, whole, on lua5.1.
local result = CeroSecSelfTest.runShell()
for i = 1, #result.lines do print("  " .. result.lines[i]) end
eq("the shell selftest fails nothing", result.fail, 0)
eq("and passes every case it holds", result.pass, #CASES)
-- Pinned, so a case taken out is a red here and a line in the change, not a quiet
-- shrinking of what the button proves.
eq("the case count", #CASES, 235)
eq("the summary line", CeroSecSelfTest.shellSummary(result),
	"shell selftest: PASS 235 FAIL 0")

-- 2. Every answer that is not 1993's names the deviation that excuses it, and the
-- deviation exists: a `dev` that names nothing is an excuse nobody declared.
do
	local declared = {}
	for i = 1, #CeroSecOS.DEVIATIONS do declared[CeroSecOS.DEVIATIONS[i].name] = true end
	for i = 1, #CASES do
		if CASES[i].dev ~= nil then
			check("case '" .. CASES[i].name .. "' leans on a declared deviation: " ..
				CASES[i].dev, declared[CASES[i].dev] == true)
		end
	end
end

-- 3. The game runs it spread over ticks, a few cases each. Stepped one case at a
-- time it must come to exactly what the whole run came to -- and the first step is
-- the machine being made, on its own, with no case run.
do
	local run = CeroSecSelfTest.shellStart()
	local done = CeroSecSelfTest.shellStep(run, 1)
	check("the first step only makes the machine", not done and run.at == 0 and run.pristine ~= nil)
	local steps = 1
	while not CeroSecSelfTest.shellStep(run, 1) and steps < 10000 do steps = steps + 1 end
	eq("stepped, it passes as many", run.pass, #CASES)
	eq("and fails as few", run.fail, 0)
	eq("one step a case, plus the machine", steps, #CASES)
	eq("a finished run stays finished", CeroSecSelfTest.shellStep(run, 1), true)
	eq("and counts nothing twice", run.pass, #CASES)
end

-- 4. Break the ENGINE, once: whoami answers the wrong name. Exactly one case asks
-- whoami by name, so exactly one goes red and it is named in the line.
do
	local real = CeroSecOS.commands.whoami
	CeroSecOS.commands.whoami = function() return true, { "nobody" } end
	local hurt = CeroSecSelfTest.runShell()
	CeroSecOS.commands.whoami = real
	eq("a broken whoami is one failure", hurt.fail, 1)
	eq("and one pass fewer", hurt.pass, #CASES - 1)
	check("named in the log line: " .. tostring(hurt.lines[1]),
		mentions(hurt, "shell selftest: whoami:") and mentions(hurt, "nobody"))
	eq("put back, it passes again", CeroSecSelfTest.runShell().fail, 0)
end

-- 5. Break the TABLE, the ways a table goes quietly green.
do
	local none = CeroSecSelfTest.runShell({})
	eq("an empty table is a failure", none.fail, 1)
	eq("and passes nothing", none.pass, 0)
	check("and says so", mentions(none, "no cases"))

	-- The file shipped without its table: a run of nothing, and a failure.
	CeroSecSelfTest.SHELL_CASES = nil
	local missing = CeroSecSelfTest.runShell()
	CeroSecSelfTest.SHELL_CASES = CASES
	eq("a missing table is a failure", missing.fail, 1)
	eq("and passes nothing", missing.pass, 0)

	local twice = CeroSecSelfTest.runShell({ CASES[1], CASES[1] })
	eq("a name used twice is a failure", twice.fail, 1)
	check("and says so", mentions(twice, "used twice"))

	local noLine = CeroSecSelfTest.runShell({ { name = "no line here" } })
	eq("a case with no line is a failure, not a pass", noLine.fail, 1)
	eq("and passes nothing", noLine.pass, 0)

	local noName = CeroSecSelfTest.runShell({ { line = "true" } })
	eq("a case with no name is a failure", noName.fail, 1)

	local forever = CeroSecSelfTest.runShell({ { name = "forever", line = "sleep 100000" } })
	eq("a case that never finishes is a failure", forever.fail, 1)
	check("and says so", mentions(forever, "did not finish"))

	local raises = CeroSecSelfTest.runShell({ { name = "raises", line = "true", files = 5 } })
	eq("a case that raises is a failure", raises.fail, 1)
	check("and says so", mentions(raises, "raised"))
	eq("and the run went on past it", raises.pass, 0)

	local asks = CeroSecSelfTest.runShell({ { name = "asks", line = "read x" } })
	eq("a question nobody answers is a failure", asks.fail, 1)

	local wrong = CeroSecSelfTest.runShell({ { name = "wrong", line = "echo a", out = { "b" } } })
	eq("a wrong answer is a failure", wrong.fail, 1)
	check("naming what it wanted and what it got",
		mentions(wrong, "want [b] got [a]"))
end

-- 6. The scratch machine is a copy, every time: a case cannot see another's
-- files, and nothing it does reaches the machine it was copied from.
do
	local run = CeroSecSelfTest.shellStart({
		{ name = "writes", line = "echo x > /root/left" },
		{ name = "sees nothing", line = "[ -f /root/left ] || echo clean", out = { "clean" } },
	})
	while not CeroSecSelfTest.shellStep(run, 5) do end
	eq("two cases, two passes", run.pass, 2)
	check("and the pristine machine never had the file",
		CeroSecOS.getNode(run.pristine.state, CeroSecOS.rootSession(), "/root/left") == nil)
end

print(string.format("selftest_shell: %d checks, %d failed", count, failures))
if failures > 0 then os.exit(1) end
