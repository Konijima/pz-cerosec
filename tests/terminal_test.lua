-- Unit tests for the pure parts of the terminal: the hostname a computer gives
-- itself, the console the machine keeps (its lines, its prompt, what it is
-- waiting for), and the input history the window keeps.
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

-- The home directory is "~", and only the home directory. This is where
-- "admin@ksp-4rw-44z:~ome/admin$" came from: a tail cut wearing a tilde.
eq("the home itself", CeroSec.shortenPath("/home/admin", "/home/admin"), "~")
eq("under the home", CeroSec.shortenPath("/home/admin/docs", "/home/admin"), "~/docs")
eq("deeper under the home",
	CeroSec.shortenPath("/home/admin/a/b", "/home/admin"), "~/a/b")
eq("a name that merely starts the same",
	CeroSec.shortenPath("/home/adminx", "/home/admin"), "/home/adminx")
eq("a sibling", CeroSec.shortenPath("/home/other", "/home/admin"), "/home/other")
eq("root's home", CeroSec.shortenPath("/root", "/root"), "~")
eq("the root of the disk", CeroSec.shortenPath("/", "/root"), "/")
eq("no home, no shortening", CeroSec.shortenPath("/home/admin", nil), "/home/admin")
eq("a home of / shortens nothing", CeroSec.shortenPath("/home/admin", "/"), "/home/admin")
eq("an empty home shortens nothing", CeroSec.shortenPath("/home/admin", ""), "/home/admin")

-- And the same, through the prompt. These are the exact lines on the glass.
eq("prompt: the home is a tilde",
	CeroSec.prompt("admin", "ksp-4rw-44z", "/home/admin", false, "/home/admin"),
	"admin@ksp-4rw-44z:~$ ")
eq("prompt: under the home",
	CeroSec.prompt("admin", "ksp-4rw-44z", "/home/admin/docs", false, "/home/admin"),
	"admin@ksp-4rw-44z:~/docs$ ")
eq("prompt: a name that merely starts the same",
	CeroSec.prompt("admin", "ksp-1-1", "/home/adminx", false, "/home/admin"),
	"admin@ksp-1-1:/home/adminx$ ")
eq("prompt: root at home",
	CeroSec.prompt("root", "ksp-1-1", "/root", true, "/root"), "root@ksp-1-1:~# ")
eq("prompt: the root of the disk",
	CeroSec.prompt("root", "ksp-1-1", "/", true, "/root"), "root@ksp-1-1:/# ")

-- A path too long even shortened is cut at the FRONT and marked "...", never
-- with a tilde: a tilde in the middle of a path is what the bug looked like.
local long = CeroSec.prompt("admin", "ksp-abcd-ef", "/a/b/c/d/e/f/g/h/i/j/k", false, "/home/admin")
check("long prompt is capped", #long <= CeroSec.PROMPT_MAX)
check("long prompt marks the cut", string.find(long, "...", 1, true) ~= nil)
check("long prompt does not fake a home", string.find(long, "~", 1, true) == nil)
check("long prompt keeps the tail", string.find(long, "k%$ $") ~= nil)

-- Even a name and a host that eat the whole line leave a usable prompt, and
-- PROMPT_MAX is a ceiling rather than a suggestion: the head takes the cut.
local huge = CeroSec.prompt("administrator", "a-very-long-hostname", "/home", false)
check("huge prompt still ends in the sigil", string.sub(huge, -2) == "$ ")
check("huge prompt is capped like any other", #huge <= CeroSec.PROMPT_MAX)
for _, pair in ipairs({ { "a", "b" }, { string.rep("u", 40), string.rep("h", 40) },
		{ string.rep("u", 16), string.rep("h", 16) }, { "admin", "ksp-abcd-ef" } }) do
	for _, admin in ipairs({ true, false }) do
		local line = CeroSec.prompt(pair[1], pair[2], "/home/admin/deep/deeper", admin, "/root")
		check("prompt for " .. #pair[1] .. "/" .. #pair[2] .. " is capped",
			#line <= CeroSec.PROMPT_MAX)
		check("and still ends in its sigil",
			string.sub(line, -2) == (admin and "# " or "$ "))
	end
end

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
-- The console
--
-- The screen belongs to the machine. Everything below is what the server does
-- to it between two commands, and it is all pure list and string work.
--

local console = CeroSec.newConsole()
eq("a fresh console has not booted", console.booted, false)
eq("a fresh console is empty", #console.lines, 0)
eq("a fresh console has nobody on it", console.user, nil)
eq("a fresh console waits for a name", CeroSec.consoleWaiting(console), "login")
eq("which the window is told is a prompt", CeroSec.consoleMode(console), "prompt")
eq("and shows the login prompt", CeroSec.consolePrompt(console, "ksp-1-1", false), "login: ")
eq("a name is not masked", CeroSec.consoleMask(console), false)

-- A stored line is text and only text, and never wider than the screen.
eq("a plain line is kept", CeroSec.consoleLine("ls -l"), "ls -l")
eq("a control byte is dropped", CeroSec.consoleLine("a\1b\4c"), "abc")
eq("a newline is dropped", CeroSec.consoleLine("a\nb"), "ab")
eq("a tab becomes a space", CeroSec.consoleLine("a\tb"), "a b")
eq("a zero byte is dropped", CeroSec.consoleLine("a\0b"), "ab")
eq("a line is cut to the screen", #CeroSec.consoleLine(string.rep("x", 200)), CeroSec.COLS)
eq("something that is not a string still becomes one", CeroSec.consoleLine(42), "42")

-- The ring: the oldest line falls off the top, and only CONSOLE_MAX are kept.
local ring = CeroSec.newConsole()
for i = 1, CeroSec.CONSOLE_MAX + 25 do CeroSec.consolePush(ring, "line " .. i) end
eq("the console keeps its size", #ring.lines, CeroSec.CONSOLE_MAX)
eq("the console keeps the newest", ring.lines[CeroSec.CONSOLE_MAX],
	"line " .. (CeroSec.CONSOLE_MAX + 25))
eq("the console dropped the oldest", ring.lines[1], "line 26")

CeroSec.consolePushAll(ring, { "one", "two" })
eq("pushAll appends in order", ring.lines[CeroSec.CONSOLE_MAX - 1], "one")
eq("pushAll appends the last", ring.lines[CeroSec.CONSOLE_MAX], "two")
CeroSec.consolePushAll(ring, "not a list")
eq("pushAll ignores what is not a list", ring.lines[CeroSec.CONSOLE_MAX], "two")

CeroSec.consoleClear(ring)
eq("clear empties the screen", #ring.lines, 0)

-- Logging in and out. The prompt is derived from the console and from nothing
-- the server has to remember.
local live = CeroSec.newConsole()
live.booted = true
CeroSec.consolePush(live, "login: root")
live.pending = "root"
eq("a name pending means a password is wanted", CeroSec.consoleWaiting(live), "password")
eq("still one prompt as far as the window knows", CeroSec.consoleMode(live), "prompt")
eq("and the password prompt", CeroSec.consolePrompt(live, "ksp-1-1", true), "password: ")
eq("a password is masked", CeroSec.consoleMask(live), true)
eq("the password never reaches a line",
	CeroSec.maskedLine("password: ", "hunter2"), "password: *******")
eq("an empty password masks to nothing", CeroSec.maskedLine("password: ", ""), "password: ")

live.pending = nil
live.user = "root"
live.cwd = "/root"
eq("logged in is the shell", CeroSec.consoleMode(live), "shell")
eq("and the shell is nobody's secret", CeroSec.consoleMask(live), false)
eq("the shell prompt is the OS one",
	CeroSec.consolePrompt(live, "ksp-1-1", true), "root@ksp-1-1:/root# ")
eq("a plain user gets a dollar",
	CeroSec.consolePrompt(live, "ksp-1-1", false), "root@ksp-1-1:/root$ ")

CeroSec.consoleLogout(live)
eq("exit forgets the user", live.user, nil)
eq("exit forgets the directory", live.cwd, nil)
eq("exit forgets a pending name", live.pending, nil)
eq("exit clears the screen", #live.lines, 0)
eq("exit goes back to the login prompt", CeroSec.consoleWaiting(live), "login")
eq("and it is still a booted machine", live.booted, true)

-- A console with no cwd is still a console: the prompt falls back to the root.
local rooted = CeroSec.newConsole()
rooted.user = "admin"
eq("no cwd means /", CeroSec.consolePrompt(rooted, "ksp-1-1", false), "admin@ksp-1-1:/$ ")

-- Whatever it is waiting for, what comes back is a string, and the name in it
-- is the one that was handed over. The shell prompt is echoed into the
-- machine's own lines as well as drawn under the cursor, and a caller that
-- passed no name once put "root@nil:~#" on a real screen -- so the server works
-- the name out for itself now (SCeroSecSystem:promptFor) and this pins the
-- contract it works to.
do
	local asking = CeroSec.newConsole()
	asking.user = "admin"
	asking.prompt = { text = "New password: ", mask = true, cont = { cmd = "passwd" } }
	local shapes = { CeroSec.newConsole(), rooted, live, asking }
	for i = 1, #shapes do
		local text = CeroSec.consolePrompt(shapes[i], "ksp-1-1", false)
		eq("every prompt is a string", type(text), "string")
		check("and never carries a nil", string.find(text, "nil", 1, true) == nil)
	end
	check("the shell prompt carries the name it was given",
		string.find(CeroSec.consolePrompt(rooted, "office", false), "@office:", 1, true) ~= nil)
end

--
-- Repairing what the game hands back
--

eq("nil is a fresh console", CeroSec.repairConsole(nil).booted, false)
eq("a string is a fresh console", #CeroSec.repairConsole("junk").lines, 0)

local dirty = {
	booted = 1,
	user = 12,
	cwd = "/root",
	pending = {},
	lines = { "kept", 7, {}, "also kept", "a\1b", string.rep("y", 90) },
}
local clean = CeroSec.repairConsole(dirty)
eq("a truthy booted becomes true", clean.booted, true)
eq("a user that is not a string is nobody", clean.user, nil)
eq("a cwd that is a string is kept", clean.cwd, "/root")
eq("a pending that is not a string is nothing", clean.pending, nil)
eq("only the string lines survive", #clean.lines, 4)
eq("the first survivor", clean.lines[1], "kept")
eq("the second survivor", clean.lines[2], "also kept")
eq("survivors are scrubbed", clean.lines[3], "ab")
eq("survivors are cut to the screen", #clean.lines[4], CeroSec.COLS)

local overflowing = { lines = {} }
for i = 1, CeroSec.CONSOLE_MAX * 2 do overflowing.lines[i] = "line " .. i end
eq("a forged console cannot grow the screen",
	#CeroSec.repairConsole(overflowing).lines, CeroSec.CONSOLE_MAX)

--
-- The BIOS is the server's, and it fits the screen.
--

check("there are boot lines", #CeroSec.BOOT_LINES > 0)
-- The firmware announces its own version and nothing else's: the BIOS is not
-- the operating system, and the two numbers are never the same string.
check("the BIOS names its own version",
	string.find(CeroSec.BOOT_LINES[1], CeroSec.BIOS_VERSION, 1, true) ~= nil)
eq("and it is the whole of the first line",
	CeroSec.BOOT_LINES[1], "CeroSec BIOS " .. CeroSec.BIOS_VERSION ..
	" -- (c) 1993 CeroSec Systems")
for i = 1, #CeroSec.BOOT_LINES do
	local line = CeroSec.BOOT_LINES[i]
	check("boot line " .. i .. " is a string", type(line) == "string")
	eq("boot line " .. i .. " needs no scrubbing", CeroSec.consoleLine(line), line)
end

--
-- Prompts a command asked for
--
-- login, password and passwd's three questions are one path: the console says
-- what it is waiting for, the window is told "prompt" plus a mask flag, and the
-- answer comes back through the one client command.
--

local asked = CeroSec.newConsole()
asked.booted = true
asked.user = "admin"
asked.cwd = "/home/admin"
asked.prompt = { text = "Old password: ", mask = true, cont = { cmd = "passwd", step = "old" } }
eq("a command's prompt is a prompt", CeroSec.consoleWaiting(asked), "prompt")
eq("and the window is told so", CeroSec.consoleMode(asked), "prompt")
eq("with the command's own line", CeroSec.consolePrompt(asked, "ksp-1-1", false), "Old password: ")
eq("masked because the command said so", CeroSec.consoleMask(asked), true)

asked.prompt = { text = "Name: ", mask = false, cont = { cmd = "passwd" } }
eq("an unmasked prompt is not masked", CeroSec.consoleMask(asked), false)
eq("and shows its line", CeroSec.consolePrompt(asked, "ksp-1-1", false), "Name: ")

-- A prompt outranks a half-typed login, and the editor outranks everything:
-- there is one thing a machine is waiting for at a time.
asked.pending = "root"
eq("a prompt comes first", CeroSec.consoleWaiting(asked), "prompt")
asked.edit = { path = "/home/admin/a.txt", text = "", readonly = false }
eq("the editor comes first of all", CeroSec.consoleWaiting(asked), "edit")
eq("and the window is told edit", CeroSec.consoleMode(asked), "edit")
eq("an editor has no prompt line", CeroSec.consolePrompt(asked, "ksp-1-1", false), "")
eq("and nothing to mask", CeroSec.consoleMask(asked), false)

CeroSec.consoleLogout(asked)
eq("exit forgets the question", asked.prompt, nil)
eq("exit forgets the buffer", asked.edit, nil)
eq("exit goes back to the login prompt", CeroSec.consoleWaiting(asked), "login")

-- What the game hands back: a prompt or a buffer survives only whole.
local kept = CeroSec.repairConsole({
	lines = {},
	prompt = { text = "Old password: ", mask = 1, cont = { cmd = "passwd" } },
	edit = { path = "/a.txt", text = "hi", readonly = 1, by = "42", message = "Saved 2 bytes" },
})
eq("a whole prompt is kept", kept.prompt.text, "Old password: ")
eq("its mask becomes a boolean", kept.prompt.mask, true)
eq("its token is kept", kept.prompt.cont.cmd, "passwd")
eq("a whole buffer is kept", kept.edit.path, "/a.txt")
eq("with its text", kept.edit.text, "hi")
eq("its read-only flag becomes a boolean", kept.edit.readonly, true)
eq("its owner is kept", kept.edit.by, "42")
eq("its message is kept", kept.edit.message, "Saved 2 bytes")

for _, junk in ipairs({
	{ text = "x", mask = true },                       -- no token
	{ mask = true, cont = {} },                        -- no text
	{ text = "x", mask = true, cont = "no" },          -- a token that is not one
	"a string", 7,
}) do
	eq("half a prompt is no prompt", CeroSec.repairConsole({ lines = {}, prompt = junk }).prompt, nil)
end
for _, junk in ipairs({ { path = "/a" }, { text = "hi" }, { path = 1, text = "hi" }, "x", 7 }) do
	eq("half a buffer is no buffer", CeroSec.repairConsole({ lines = {}, edit = junk }).edit, nil)
end

-- The su stack, likewise: it is saved with the machine, so what comes back has
-- to be a stack and not merely a table -- and never deeper than the ceiling,
-- because every entry on it is an `exit` somebody has to type to get out.
do
	local stacked = CeroSec.repairConsole({
		lines = {}, user = "bob", cwd = "/home/bob",
		stack = { { user = "admin", cwd = "/home/admin" }, { user = "root" },
			{ cwd = "/nobody" }, "x", 7 },
	})
	eq("only the entries that are entries survive", #stacked.stack, 2)
	eq("the first is kept whole", stacked.stack[1].user, "admin")
	eq("with its directory", stacked.stack[1].cwd, "/home/admin")
	eq("an entry with no directory stands at the root", stacked.stack[2].cwd, "/")
	eq("an empty stack is no stack",
		CeroSec.repairConsole({ lines = {}, stack = {} }).stack, nil)
	eq("and neither is one that is not a table",
		CeroSec.repairConsole({ lines = {}, stack = "deep" }).stack, nil)

	local deep = { lines = {}, stack = {} }
	for i = 1, CeroSec.SU_MAX * 3 do deep.stack[i] = { user = "u" .. i, cwd = "/" } end
	eq("a forged console cannot make a stack nobody gets out of",
		#CeroSec.repairConsole(deep).stack, CeroSec.SU_MAX)

	-- And a logout drops it: an account logs out of the machine, not out of its
	-- own last switch.
	local live2 = CeroSec.newConsole()
	live2.user = "bob"
	live2.stack = { { user = "admin", cwd = "/home/admin" } }
	CeroSec.consoleLogout(live2)
	eq("exit forgets who it would have come back to", live2.stack, nil)
end

--
-- The input line, wrapped
--
-- A terminal does not stop at the right edge of the glass: it wraps and keeps
-- going. Four rows of sixty, prompt included on the first.
--

eq("four rows", CeroSec.INPUT_ROWS, 4)
eq("and that is 240 characters", CeroSec.INPUT_MAX, CeroSec.INPUT_ROWS * CeroSec.COLS)

do
	local P = "admin@ksp-1-1:~$ "        -- 17 characters
	local head = #P
	local first = CeroSec.COLS - head    -- 43 characters of text on row 1

	-- Nothing typed: one row, the prompt, cursor right after it.
	local rows, row, col = CeroSec.inputRows(P, "", 0)
	eq("empty: one row", #rows, 1)
	eq("empty: the row is the prompt", rows[1], P)
	eq("empty: cursor row", row, 1)
	eq("empty: cursor column", col, head)

	-- The same in the words of the screenshot: the prompt that was on the glass,
	-- nothing typed, and the block on the column right after the "$ ". Column
	-- here is counted from zero, so that is #prompt.
	local screenshot = "admin@ksp-4rw-44z:~$ " -- 21 characters
	local _, sr, sc = CeroSec.inputRows(screenshot, "", 0)
	eq("the screenshot's prompt: cursor row", sr, 1)
	eq("the screenshot's prompt: cursor at column #prompt + 1", sc + 1, #screenshot + 1)

	-- A short line stays on one row.
	rows, row, col = CeroSec.inputRows(P, "ls -l", 5)
	eq("short: one row", #rows, 1)
	eq("short: the row", rows[1], P .. "ls -l")
	eq("short: cursor row", row, 1)
	eq("short: cursor column", col, head + 5)

	-- Exactly the first row's worth: still one row of text, but the cursor at
	-- the end has nowhere to sit on it, so it is the start of the next.
	local exact = string.rep("x", first)
	rows, row, col = CeroSec.inputRows(P, exact, first)
	eq("exact: the first row is full", #rows[1], CeroSec.COLS)
	eq("exact: a second row was made for the cursor", #rows, 2)
	eq("exact: and it is empty", rows[2], "")
	eq("exact: cursor row", row, 2)
	eq("exact: cursor column", col, 0)
	-- One character back, and the cursor is on the last column of row 1.
	local _, r1, c1 = CeroSec.inputRows(P, exact, first - 1)
	eq("one back: cursor row", r1, 1)
	eq("one back: cursor column", c1, CeroSec.COLS - 1)

	-- One character more: two rows.
	rows, row, col = CeroSec.inputRows(P, exact .. "y", first + 1)
	eq("wrapped: two rows", #rows, 2)
	eq("wrapped: the first is full", #rows[1], CeroSec.COLS)
	eq("wrapped: the second holds the overflow", rows[2], "y")
	eq("wrapped: cursor row", row, 2)
	eq("wrapped: cursor column", col, 1)

	-- The full 240, which is four rows and no more.
	local full = ""
	for i = 1, CeroSec.INPUT_MAX do full = full .. string.sub("0123456789", (i % 10) + 1, (i % 10) + 1) end
	rows = CeroSec.inputRows(P, full, 0)
	check("240 characters fit in four rows or fewer", #rows <= CeroSec.INPUT_ROWS + 1)
	for i = 1, #rows do
		check("row " .. i .. " never exceeds the screen", #rows[i] <= CeroSec.COLS)
	end
	-- Put back together, the rows are the prompt and the text and nothing else.
	eq("nothing is lost and nothing is invented", table.concat(rows, ""), P .. full)

	-- Every offset lands on a row that exists, at a column on the screen, and
	-- walking the offsets never goes backwards.
	local text = string.rep("abcdefghij", 12)
	local lastRow, lastCol = 0, -1
	for offset = 0, #text do
		local r, rr, cc = CeroSec.inputRows(P, text, offset)
		check("offset " .. offset .. " lands on a row that exists", r[rr] ~= nil)
		check("offset " .. offset .. " lands on the screen", cc >= 0 and cc < CeroSec.COLS)
		check("offset " .. offset .. " never goes backwards",
			rr > lastRow or (rr == lastRow and cc > lastCol))
		lastRow, lastCol = rr, cc
	end

	-- A nonsense offset is clamped, never an error.
	local _, r2, c2 = CeroSec.inputRows(P, "abc", -5)
	eq("a negative offset is the start", r2 .. "," .. c2, "1," .. head)
	local _, r3, c3 = CeroSec.inputRows(P, "abc", 999)
	eq("an offset past the end is the end", r3 .. "," .. c3, "1," .. (head + 3))
	local _, r4, c4 = CeroSec.inputRows(P, "abc", nil)
	eq("no offset is the end", r4 .. "," .. c4, "1," .. (head + 3))

	-- No prompt at all, and a prompt wider than the glass.
	rows = CeroSec.inputRows("", "abc", 0)
	eq("no prompt", rows[1], "abc")
	rows, row, col = CeroSec.inputRows(string.rep("P", 200), "ab", 0)
	eq("an absurd prompt is cut", #rows[1], CeroSec.COLS)
	check("and still leaves a column to type in", col <= CeroSec.COLS - 1)
	-- What is not a string is still laid out.
	eq("nil text", CeroSec.inputRows("x> ", nil, 0)[1], "x> ")
	eq("nil prompt", CeroSec.inputRows(nil, "y", 0)[1], "y")
end

--
-- Where the block cursor is, and what is under it
--
-- The block was a column right of the end of what was typed in one half of the
-- blink and a column left of it in the other, with the last character drawn
-- inverted under it: two halves of one cursor working out two different
-- columns. There is one answer now and both halves take it.
--

do
	local P = "root@blacknet:~# "          -- 17 characters
	-- A proportional font would answer differently for "i" and "M"; the glass
	-- is monospaced, and the measurement is of the string that was painted.
	local W = 8
	local function measure(s) return W * #s end

	-- Nothing typed: the block sits right after the prompt, on nothing.
	local x, under = CeroSec.cursorSpan(P, "", 0, measure)
	eq("empty: the block is at the end of the prompt", x, W * #P)
	eq("empty: and covers nothing", under, nil)

	-- One character, cursor after it: no gap, and still nothing under it.
	x, under = CeroSec.cursorSpan(P, "a", 1, measure)
	eq("one char: the block is right after it, no gap", x, W * (#P + 1))
	eq("one char: and covers nothing", under, nil)

	-- Two, and the same at the end.
	x, under = CeroSec.cursorSpan(P, "ab", 2, measure)
	eq("ab: the block is right after the b", x, W * (#P + 2))
	eq("ab: and covers nothing", under, nil)

	-- In the middle of what was typed, the block covers the character AT that
	-- index -- the one the next typed character would push right.
	x, under = CeroSec.cursorSpan(P, "ab", 1, measure)
	eq("mid: the block is on the b", x, W * (#P + 1))
	eq("mid: and covers the b", under, "b")
	x, under = CeroSec.cursorSpan(P, "ab", 0, measure)
	eq("start: the block is on the a", x, W * #P)
	eq("start: and covers the a", under, "a")

	-- No prompt is a prompt of nothing, and a space under the cursor is a
	-- character like any other.
	x, under = CeroSec.cursorSpan("", "a b", 1, measure)
	eq("no prompt: the block is one character in", x, W)
	eq("no prompt: and covers the space", under, " ")

	-- What is out of range is clamped: a box that answers one past the end of
	-- the text must not put the block a column past the end of the line, which
	-- is the gap that was on the glass.
	x, under = CeroSec.cursorSpan(P, "a", 2, measure)
	eq("past the end: still right after the a", x, W * (#P + 1))
	eq("past the end: and covers nothing", under, nil)
	x, under = CeroSec.cursorSpan(P, "a", 999, measure)
	eq("far past the end: still right after the a", x, W * (#P + 1))
	x, under = CeroSec.cursorSpan(P, "a", -3, measure)
	eq("before the start: at the end of the prompt", x, W * #P)
	eq("before the start: covering the a", under, "a")
	x, under = CeroSec.cursorSpan(P, "abc", nil, measure)
	eq("no index at all is the end", x, W * (#P + 3))
	eq("no index at all covers nothing", under, nil)

	-- What is not a string is still placed, and nothing is measured when there
	-- is nothing in front of the cursor.
	eq("nil prompt and nil text", CeroSec.cursorSpan(nil, nil, 0, measure), 0)
	eq("nothing in front is measured as nothing", CeroSec.cursorSpan("", "ab", 0, nil), 0)

	-- The measurement is of the whole string in front of the cursor, in one
	-- call, and not a count of cells: a font that answers 1 for "M" and 100 for
	-- "MM" is still placed on what it answers.
	local seen = nil
	local bent = function(s) seen = s; return #s * #s end
	x = CeroSec.cursorSpan("ab", "cd", 1, bent)
	eq("the font is asked about the text in front of the cursor", seen, "abc")
	eq("and its answer is the x", x, 9)
end

-- Getting closer counts, even while it is still refused. A file the shell wrote
-- can hold a row wider than the screen (writeFile has no width rule -- the
-- width belongs to the glass, not to the disk), and an editor that undid every
-- keystroke on such a buffer would undo the backspaces too and could never fix
-- what it had opened.
do
	local wide = string.rep("a", 70)
	eq("a 70 character row is refused", CeroSec.editRefusal(wide),
		"Line too long: 60 characters")
	check("and it is over the line by ten", CeroSec.editBadness(wide) == 10)
	check("legal text has no badness at all", CeroSec.editBadness("ok\nfine") == 0)
	check("an empty buffer has none", CeroSec.editBadness("") == 0)
	check("what is not a string is as bad as it gets",
		CeroSec.editBadness(nil) > CeroSec.EDIT_MAX_BYTES)

	-- Every backspace strictly helps, all the way down to legal.
	local text, steps = wide, 0
	while CeroSec.editRefusal(text) ~= nil do
		local shorter = string.sub(text, 1, #text - 1)
		check("a backspace at " .. #text .. " gets closer",
			CeroSec.editBadness(shorter) < CeroSec.editBadness(text))
		text, steps = shorter, steps + 1
		check("and never runs away", steps <= 70)
	end
	eq("ten backspaces make it legal", steps, 10)
	eq("and what is left is a full row", #text, CeroSec.EDIT_MAX_LINE)

	-- Typing more never does.
	check("the 71st character gets no closer",
		CeroSec.editBadness(wide .. "b") >= CeroSec.editBadness(wide))
	-- Two long rows: fixing one of them helps even though the other is still bad.
	local two = string.rep("a", 70) .. "\n" .. string.rep("b", 70)
	check("two long rows are worth twenty", CeroSec.editBadness(two) == 20)
	check("shortening one of them helps",
		CeroSec.editBadness(string.sub(two, 2)) < CeroSec.editBadness(two))

	-- The byte ceiling behaves the same way.
	local big = string.rep("x\n", CeroSec.EDIT_MAX_BYTES)
	check("well over the ceiling", CeroSec.editBadness(big) > 0)
	check("and deleting still helps",
		CeroSec.editBadness(string.sub(big, 1, #big - 1)) < CeroSec.editBadness(big))

	-- A control byte is badness of its own, and losing it helps.
	check("a control byte is bad", CeroSec.editBadness("a\1b") == 1)
	check("and dropping it fixes it", CeroSec.editBadness("ab") == 0)
end

--
-- The editor screen
--

-- The buffer as rows. An empty buffer is one empty row: a cursor has to sit
-- somewhere, which is what makes this different from the core's splitLines.
eq("an empty buffer is one row", #CeroSec.editLines(""), 1)
eq("and that row is empty", CeroSec.editLines("")[1], "")
eq("one row", #CeroSec.editLines("abc"), 1)
eq("two rows", #CeroSec.editLines("a\nb"), 2)
eq("a trailing newline makes an empty last row", #CeroSec.editLines("a\n"), 2)
eq("and it is empty", CeroSec.editLines("a\n")[2], "")
eq("a lone newline is two empty rows", #CeroSec.editLines("\n"), 2)
eq("what is not a string is one empty row", CeroSec.editLines(nil)[1], "")

-- Where an offset is on that grid. The offset is a gap between characters, so
-- the end of a row and the start of the next are two different offsets.
local function at(text, offset, wantRow, wantCol)
	local row, col = CeroSec.editCursor(text, offset)
	local where = "offset " .. tostring(offset) .. " in " .. string.format("%q", text)
	eq("row of " .. where, row, wantRow)
	eq("column of " .. where, col, wantCol)
end

at("", 0, 1, 0)
at("abc", 0, 1, 0)
at("abc", 1, 1, 1)
at("abc", 3, 1, 3)
at("ab\ncd", 2, 1, 2)   -- in front of the newline: the end of the first row
at("ab\ncd", 3, 2, 0)   -- past it: the start of the second
at("ab\ncd", 5, 2, 2)
at("a\n\nb", 2, 2, 0)
at("a\n\nb", 3, 3, 0)
at("abc", -4, 1, 0)     -- a nonsense offset is clamped, never an error
at("abc", 99, 1, 3)
at("abc", nil, 1, 0)

-- The row of every offset in a buffer is the row that offset's character is on.
do
	local text = "one\ntwo\n\nfour"
	local lines = CeroSec.editLines(text)
	for offset = 0, #text do
		local row, col = CeroSec.editCursor(text, offset)
		check("offset " .. offset .. " lands on a row that exists", lines[row] ~= nil)
		check("offset " .. offset .. " lands inside it", col >= 0 and col <= #lines[row])
	end
end

-- Scrolling: the cursor row is always one of the seventeen, and a screen that
-- need not move does not move.
local ROWS = CeroSec.EDIT_ROWS
eq("seventeen rows", ROWS, 17)
eq("a short file never scrolls", CeroSec.editTop(1, 1, 3, ROWS), 1)
eq("a short file cannot be scrolled either", CeroSec.editTop(9, 2, 3, ROWS), 1)
eq("the cursor on the last visible row stays", CeroSec.editTop(1, ROWS, 40, ROWS), 1)
eq("one row further pushes the screen down", CeroSec.editTop(1, ROWS + 1, 40, ROWS), 2)
eq("and the cursor is then on the last row",
	CeroSec.editTop(1, ROWS + 1, 40, ROWS) + ROWS - 1, ROWS + 1)
eq("walking back up pulls it back", CeroSec.editTop(10, 4, 40, ROWS), 4)
eq("a top past the end is pulled back", CeroSec.editTop(99, 40, 40, ROWS), 40 - ROWS + 1)
eq("the last screenful of a 40 row file", CeroSec.editTop(1, 40, 40, ROWS), 40 - ROWS + 1)
eq("a nonsense top is the first row", CeroSec.editTop(-3, 1, 40, ROWS), 1)
eq("a nonsense top is the first row", CeroSec.editTop("x", 1, 40, ROWS), 1)
eq("an empty file has one row", CeroSec.editTop(1, 1, 0, ROWS), 1)

-- The cursor row is visible for every row of a long file, from any starting top.
do
	local count = 60
	for _, start in ipairs({ 1, 5, 20, 44, 99 }) do
		local top = start
		for row = 1, count do
			top = CeroSec.editTop(top, row, count, ROWS)
			check("row " .. row .. " is at or below the top", row >= top)
			check("row " .. row .. " is at or above the bottom", row <= top + ROWS - 1)
			check("the top is a row of the file", top >= 1 and top <= count - ROWS + 1)
		end
	end
end

-- The two bars and the message line.
local bar = CeroSec.editTitle("/home/admin/notes.txt", "modified")
eq("the title bar is a full row", #bar, CeroSec.COLS)
eq("it names the file", string.sub(bar, 1, 28), " EDIT  /home/admin/notes.txt")
eq("and pins the flag to the right", string.sub(bar, CeroSec.COLS - 10), "[modified] ")
eq("read-only is pinned the same way",
	string.sub(CeroSec.editTitle("/a.txt", "read-only"), CeroSec.COLS - 11), "[read-only] ")
eq("no flag is a bar of the same width", #CeroSec.editTitle("/a.txt", nil), CeroSec.COLS)
eq("an empty flag is no flag", #CeroSec.editTitle("/a.txt", ""), CeroSec.COLS)
eq("a very long path is cut, not folded",
	#CeroSec.editTitle(string.rep("/aaaaaaaa", 20), "modified"), CeroSec.COLS)
check("and the cut is marked",
	string.find(CeroSec.editTitle(string.rep("/aaaaaaaa", 20), "modified"), "~", 1, true) ~= nil)

eq("the key bar is a full row", #CeroSec.editKeys(), CeroSec.COLS)
check("it names Escape", string.find(CeroSec.editKeys(), "Esc exit", 1, true) ~= nil)
check("it names Tab", string.find(CeroSec.editKeys(), "Tab save", 1, true) ~= nil)

eq("a message is a line", CeroSec.editMessage("Saved 412 bytes"), "Saved 412 bytes")
eq("no message is an empty line", CeroSec.editMessage(nil), "")
eq("a message is scrubbed like any other line", CeroSec.editMessage("a\1b"), "ab")
eq("and cut to the screen", #CeroSec.editMessage(string.rep("x", 90)), CeroSec.COLS)

-- The whole screen: twenty rows, always, whatever the buffer is.
do
	local text = ""
	for i = 1, 40 do text = text .. "line " .. i .. "\n" end
	local screen = CeroSec.editScreen(text, 1, "/a.txt", "modified", "Saved 412 bytes")
	eq("twenty rows", #screen, CeroSec.ROWS)
	eq("row 1 is the title bar", screen[1], CeroSec.editTitle("/a.txt", "modified"))
	eq("row 2 is the first line of the buffer", screen[2], "line 1")
	eq("row 18 is the seventeenth", screen[1 + ROWS], "line 17")
	eq("row 19 is the key bar", screen[19], CeroSec.editKeys())
	eq("row 20 is the message", screen[20], "Saved 412 bytes")

	local scrolled = CeroSec.editScreen(text, 24, "/a.txt", nil, nil)
	eq("scrolled: still twenty rows", #scrolled, CeroSec.ROWS)
	eq("scrolled: the top row of the view", scrolled[2], "line 24")
	eq("scrolled: the last line of the file", scrolled[2 + 40 - 24], "line 40")
	eq("scrolled: past the end is an empty row", scrolled[2 + 40 - 24 + 2], "")
	eq("scrolled: the message row is empty", scrolled[20], "")

	local empty = CeroSec.editScreen("", 1, "/a.txt", nil, nil)
	eq("an empty buffer is still twenty rows", #empty, CeroSec.ROWS)
	for i = 2, 18 do eq("and row " .. i .. " is empty", empty[i], "") end

	-- No row of the screen is ever wider than the screen.
	local wide = CeroSec.editScreen(string.rep("x", 400), 1, string.rep("p", 400), "modified", string.rep("m", 400))
	for i = 1, #wide do
		eq("row " .. i .. " fits the screen", #wide[i] <= CeroSec.COLS, true)
	end
end

-- What the editor will hold, and what it refuses under the fingers.
eq("the buffer ceiling is the file ceiling", CeroSec.EDIT_MAX_BYTES, 4096)
eq("a line is a screen line", CeroSec.EDIT_MAX_LINE, CeroSec.COLS)
eq("plain text is fine", CeroSec.editRefusal("hello\nworld"), nil)
eq("an empty buffer is fine", CeroSec.editRefusal(""), nil)
eq("a tab is text", CeroSec.editRefusal("a\tb"), nil)
eq("exactly sixty characters fit",
	CeroSec.editRefusal(string.rep("x", CeroSec.EDIT_MAX_LINE)), nil)
eq("sixty-one do not",
	CeroSec.editRefusal(string.rep("x", CeroSec.EDIT_MAX_LINE + 1)),
	"Line too long: 60 characters")
eq("and it is the long row that counts, not the first",
	CeroSec.editRefusal("ok\n" .. string.rep("x", 61)), "Line too long: 60 characters")
eq("exactly the buffer ceiling fits",
	CeroSec.editRefusal(string.rep("x\n", CeroSec.EDIT_MAX_BYTES / 2)), nil)
eq("one byte over does not",
	CeroSec.editRefusal(string.rep("x\n", CeroSec.EDIT_MAX_BYTES / 2) .. "y"),
	"Buffer full: 4096 bytes")
eq("a control byte is not text", CeroSec.editRefusal("a\1b"), "Cannot edit: invalid characters")
eq("a zero byte is not text", CeroSec.editRefusal("a\0b"), "Cannot edit: invalid characters")
eq("what is not a string is not text", CeroSec.editRefusal(nil), "Cannot edit: not text")

-- The two keys, and the question one of them asks.
eq("Escape on a clean buffer leaves", CeroSec.editKeyAction("edit", "escape", false, false), "leave")
eq("Escape on a modified one asks", CeroSec.editKeyAction("edit", "escape", true, false), "ask")
eq("Escape on a read-only one leaves, modified or not",
	CeroSec.editKeyAction("edit", "escape", true, true), "leave")
eq("Tab saves", CeroSec.editKeyAction("edit", "tab", true, false), "save")
eq("Tab on a read-only file says so", CeroSec.editKeyAction("edit", "tab", true, true), "readonly")
eq("nothing else does anything", CeroSec.editKeyAction("edit", "y", true, false), nil)

eq("y saves and leaves", CeroSec.editKeyAction("ask", "y", true, false), "saveleave")
eq("Y too", CeroSec.editKeyAction("ask", "Y", true, false), "saveleave")
eq("n leaves", CeroSec.editKeyAction("ask", "n", true, false), "leave")
eq("N too", CeroSec.editKeyAction("ask", "N", true, false), "leave")
eq("Escape takes the question back", CeroSec.editKeyAction("ask", "escape", true, false), "cancel")
eq("anything else asks again", CeroSec.editKeyAction("ask", "q", true, false), "again")
eq("Tab asks again", CeroSec.editKeyAction("ask", "tab", true, false), "again")

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
