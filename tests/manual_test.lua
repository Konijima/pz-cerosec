-- Checks CeroSecManual.lua against the engine it describes. Run from the
-- repo root:
--   lua5.1 tests/manual_test.lua

local OS_DIR = "42/media/lua/shared/CeroSec/OS/"
local OS_FILES = {
	"CeroSecOS", "CeroSecOSFS", "CeroSecOSPath", "CeroSecOSShell",
	"CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers", "CeroSecOSDev",
}
-- Kept as text too (not just loaded), so the error-message sweep below can
-- scan the engine's own source for the literal reasons it hands to fail(),
-- rather than trust a hand-typed list to have kept up with it.
local osSource = {}
for i = 1, #OS_FILES do
	local path = OS_DIR .. OS_FILES[i] .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()

	local f = io.open(path, "r")
	if f == nil then error("cannot read " .. path .. " as text") end
	osSource[#osSource + 1] = f:read("*a")
	f:close()
end
osSource = table.concat(osSource, "\n")

-- CeroSecDefs.lua too, text and all: it is where consoleLogout, consoleClear
-- and the boot lines live, and the error-string sweep and the defect-5
-- regression check both want it.
local defsPath = "42/media/lua/shared/CeroSec/CeroSecDefs.lua"
do
	local dchunk, derr = loadfile(defsPath)
	if not dchunk then error("cannot load " .. defsPath .. ": " .. tostring(derr)) end
	dchunk()
end

local chunk, err = loadfile("42/media/lua/shared/CeroSec/CeroSecManual.lua")
if not chunk then error("cannot load CeroSecManual.lua: " .. tostring(err)) end
chunk()

local count = 0
local function check(what, cond)
	count = count + 1
	if not cond then error("FAIL: " .. what, 2) end
end

check("CeroSecManual is a table", type(CeroSecManual) == "table")

-- The cover is stamped, not written: the version on it is the engine's own and
-- there is no second copy of the number anywhere in the book.
check("the cover is stamped, not typed", type(CeroSecManual.stampVersion) == "function")
CeroSecManual.stampVersion()

check("has a title", type(CeroSecManual.title) == "string" and CeroSecManual.title ~= "")
check("has an edition", type(CeroSecManual.edition) == "string" and CeroSecManual.edition ~= "")
check("has chapters", type(CeroSecManual.chapters) == "table")

check("the version is one string in one place", type(CeroSecOS.VERSION) == "string"
	and CeroSecOS.VERSION ~= "")
check("the title names the OS version the engine reports",
	CeroSecManual.title == "CeroSec OS " .. CeroSecOS.VERSION .. " User's Manual")

local chapters = CeroSecManual.chapters

--
-- Whole-book shape: chapter count, page counts, unique titles, no empty
-- page, everything ASCII, nothing over the page cap, example lines fit.
--
check("chapter count is 10..14", #chapters >= 10 and #chapters <= 14)

local totalPages = 0
local seenTitles = {}
-- The whole text, concatenated, so the command/error sweeps below can just
-- look for a substring rather than walk chapters and pages themselves.
local wholeBook = {}

for ci = 1, #chapters do
	local ch = chapters[ci]
	check("chapter " .. ci .. " has a title", type(ch.title) == "string" and ch.title ~= "")
	check("chapter " .. ci .. " title is unique",
		seenTitles[ch.title] == nil)
	seenTitles[ch.title] = true

	check("chapter " .. ci .. " has pages", type(ch.pages) == "table")
	local n = #ch.pages
	check("chapter " .. ci .. " (" .. ch.title .. ") has 2..6 pages",
		n >= 2 and n <= 6)
	totalPages = totalPages + n

	for pi = 1, n do
		local page = ch.pages[pi]
		local where = ch.title .. " page " .. pi
		check(where .. " is a string", type(page) == "string")
		check(where .. " is not empty", page ~= "" and string.find(page, "%S") ~= nil)
		check(where .. " is at most 900 characters (" .. #page .. ")", #page <= 900)

		-- ASCII only: every byte in 0x09..0x7E (tab, and printable range;
		-- \n is 0x0A, allowed as the paragraph break the spec calls for).
		for i = 1, #page do
			local b = string.byte(page, i)
			check(where .. " byte " .. i .. " is ASCII (" .. b .. ")",
				b == 9 or b == 10 or (b >= 32 and b <= 126))
		end

		-- Example lines: anything starting with two literal spaces is kept
		-- monospaced by the reader, so it must fit the 60-column screen.
		for line in (page .. "\n"):gmatch("([^\n]*)\n") do
			if string.sub(line, 1, 2) == "  " then
				check(where .. ' example line fits 60 columns: "' .. line .. '" (' .. #line .. ")",
					#line <= 60)
			end
		end

		-- No page names an OS version of its own. The cover is the only place
		-- the number appears at all, and it is stamped from CeroSecOS.VERSION;
		-- a "CeroSec OS 3.2" left in the prose is a second number the player
		-- reads on the same machine. The letter test in front of "OS" is what
		-- lets "CeroSec BIOS 1.0" through: the firmware has its own version.
		for pos in string.gmatch(page, "()OS %d+%.%d+") do
			local before = pos > 1 and string.sub(page, pos - 1, pos - 1) or ""
			check(where .. " names no OS version of its own: " ..
				string.sub(page, pos - 8 < 1 and 1 or pos - 8, pos + 8),
				string.find(before, "%a") ~= nil)
		end

		wholeBook[#wholeBook + 1] = page
	end
end
wholeBook = table.concat(wholeBook, "\n")

-- The BIOS line the book prints is the BIOS line the machine prints.
check("the book quotes the real BIOS line",
	string.find(wholeBook, CeroSec.BOOT_LINES[1], 1, true) ~= nil)
check("and the firmware version is one string in one place",
	type(CeroSec.BIOS_VERSION) == "string" and CeroSec.BIOS_VERSION ~= "")

-- The upper bound is a ceiling on the BOOK, not on any one chapter -- a
-- chapter is still 2..6 pages, and there are still at most 14 of them, so 84
-- is the most the shape above can hold at all. Raised from 70 to 80 when the
-- /dev chapter grew a page for the dev command: the number is there to catch a
-- book that has quietly doubled, and it must leave room for a rung's worth of
-- honest growth or it is only a chore to move.
check("total pages is 45..80 (" .. totalPages .. ")", totalPages >= 45 and totalPages <= 80)

--
-- Every command in COMMAND_INFO appears in the quick-reference chapter,
-- with its exact usage line.
--
local refChapter = nil
for ci = 1, #chapters do
	if string.find(chapters[ci].title, "commands and limits", 1, true) ~= nil then
		refChapter = chapters[ci]
	end
end
check("there is a quick-reference chapter", refChapter ~= nil)

local refText = {}
for pi = 1, #refChapter.pages do refText[#refText + 1] = refChapter.pages[pi] end
refText = table.concat(refText, "\n")

local commandNames = {}
for name, info in pairs(CeroSecOS.COMMAND_INFO) do
	commandNames[#commandNames + 1] = name
	check("quick reference names " .. name, string.find(refText, name, 1, true) ~= nil)
	check("quick reference carries " .. name .. "'s exact usage line",
		string.find(refText, info.usage, 1, true) ~= nil)
end
table.sort(commandNames)
check("collected every COMMAND_INFO entry", #commandNames > 0)

-- The two builtins that run with no file in /bin: not in COMMAND_INFO's
-- usage form, but the manual still owes the player a mention of both.
check("exit is mentioned somewhere in the book", string.find(wholeBook, "exit", 1, true) ~= nil)
check("help is mentioned somewhere in the book", string.find(wholeBook, "help", 1, true) ~= nil)

--
-- Every exact error string the engine can print appears in the error
-- appendix -- collected here as the literal reason strings CeroSecOSFS.lua
-- and CeroSecOSShell.lua actually return (the constant halves; the
-- <path>/<name> halves are the caller's argument and are not literal
-- strings the manual could quote).
--
local errChapter = nil
for ci = 1, #chapters do
	if string.find(chapters[ci].title, "what the machine says", 1, true) ~= nil then
		errChapter = chapters[ci]
	end
end
check("there is an error-message appendix", errChapter ~= nil)

local errText = {}
for pi = 1, #errChapter.pages do errText[#errText + 1] = errChapter.pages[pi] end
errText = table.concat(errText, "\n")

-- The shared filesystem reasons (CeroSecOSFS.lua), bare, before the shell
-- prefixes them with "<command>: <path>: ".
local FS_REASONS = {
	"no such file", "is a directory", "not a directory", "permission denied",
	"file exists", "invalid name", "path too deep", "directory full",
	"disk full", "file too large", "invalid characters", "invalid destination",
}
for i = 1, #FS_REASONS do
	check("error appendix carries the reason \"" .. FS_REASONS[i] .. "\"",
		string.find(errText, FS_REASONS[i], 1, true) ~= nil)
end

-- The bare reasons the shell itself hands to fail(cmd, arg, reason) as a
-- literal third argument, scanned straight out of the source rather than
-- hand-copied -- fail() always prefixes these with "<command>: " or
-- "<command>: <arg>: ", so the bare reason is what the appendix carries.
-- This is what CeroSecOSFS.lua's own bare reasons (FS_REASONS above) are
-- NOT: those are returned deeper, as a variable, and reach fail() already
-- carried in "reason", not as a literal at the call site -- so they still
-- need the hand list; a command-level literal like "unknown option" or
-- "invalid mode" does not, and is caught here even if a later change adds
-- another command that answers it.
local scannedReasons = {}
local seenReason = {}
for reason in osSource:gmatch('fail%(%s*"[%w_]+"%s*,%s*[^,]+,%s*"([^"]*)"%s*%)') do
	if not seenReason[reason] then
		seenReason[reason] = true
		scannedReasons[#scannedReasons + 1] = reason
	end
end
check("scanned at least a dozen fail() reasons out of the engine source",
	#scannedReasons >= 12)
for i = 1, #scannedReasons do
	check("error appendix carries the scanned reason \"" .. scannedReasons[i] .. "\"",
		string.find(errText, scannedReasons[i], 1, true) ~= nil)
end

-- Everything else worth listing is built at runtime -- string concatenation
-- (a command's own name, ".. reason", a user's own name in the sudoers
-- refusal) or assembled a piece at a time (the parser's three syntax
-- errors, none of which go through fail() at all) -- so there is no bare
-- literal in the source for a scan to lift. Hand-kept, and exactly as
-- CeroSecOSShell.lua and SCeroSecSystem.lua produce them.
local LITERAL_MESSAGES = {
	"command not found",
	"is not in the sudoers file.",
	"login incorrect",
	"passwd: authentication failure",
	"passwd: passwords do not match",
	"passwd: password too long",
	"passwd: no such user",
	"su: authentication failure",
	"su: too many levels",
	"sudo: authentication failure",
	"adduser: <name>: already exists",
	"deluser: <name>: user is logged in",
	"deluser: root: cannot remove",
	"chown: <name>: no such user",
	"hash: <salt>: invalid salt",
	"help: no commands in " .. CeroSecOS.BIN_PATH .. ": the system is damaged.",
	"help: switch the computer off and on to repair it.",
	"cerosec: nothing to answer",
	"syntax error: bad redirect",
	"syntax error: unterminated quote",
	"syntax error: missing redirect target",
}
for i = 1, #LITERAL_MESSAGES do
	check("error appendix carries \"" .. LITERAL_MESSAGES[i] .. "\"",
		string.find(errText, LITERAL_MESSAGES[i], 1, true) ~= nil)
end

-- The device errors SCeroSecDevices.lua and CeroSecOSDev.lua produce, which
-- the scan above cannot see: SCeroSecDevices.lua opens with `if isClient()
-- then return end` and calls straight into the game engine, so it is never
-- loaded here at all, and CeroSecOSDev.lua builds its own refusals through
-- refuse(node, reason) rather than fail(cmd, arg, reason), which the regex
-- above does not match. Hand-kept, and exactly as those two files produce
-- them (tests/os_test.lua section 21 and SCeroSecDevices.lua's `act`).
local DEVICE_MESSAGES = {
	"no power",
	"no such device",
	"smashed",
	"barricaded",
	"no padlock",
	"invalid value",
	CeroSecOS.DEV_PATH .. ": read-only",
}
for i = 1, #DEVICE_MESSAGES do
	check("error appendix carries the device reason \"" .. DEVICE_MESSAGES[i] .. "\"",
		string.find(errText, DEVICE_MESSAGES[i], 1, true) ~= nil)
end

-- Confirm the three syntax errors really are in the engine source, spelled
-- exactly as the appendix quotes them -- caught by the scan above only if
-- they went through fail(), and they do not.
local SYNTAX_ERRORS = {
	"syntax error: bad redirect",
	"syntax error: unterminated quote",
	"syntax error: missing redirect target",
}
for i = 1, #SYNTAX_ERRORS do
	check("engine source really contains \"" .. SYNTAX_ERRORS[i] .. "\"",
		string.find(osSource, SYNTAX_ERRORS[i], 1, true) ~= nil)
end

--
-- Sanity checks tying the book to a couple of live engine numbers, so a
-- future change to a limit fails this test instead of only going stale in
-- the reader's hands.
--
check("book states the disk size", string.find(wholeBook, "32K", 1, true) ~= nil)
check("book states the node ceiling (" .. CeroSecOS.MAX_NODES .. ")",
	string.find(wholeBook, tostring(CeroSecOS.MAX_NODES), 1, true) ~= nil)
check("book states the file size ceiling (" .. CeroSecOS.MAX_FILE_BYTES .. ")",
	string.find(wholeBook, tostring(CeroSecOS.MAX_FILE_BYTES), 1, true) ~= nil)
check("book states the su stack ceiling (" .. CeroSecOS.SU_MAX .. ")",
	string.find(wholeBook, "four", 1, true) ~= nil or
	string.find(wholeBook, tostring(CeroSecOS.SU_MAX), 1, true) ~= nil)

--
-- Eight fact-checked defects, each pinned against the engine so a future
-- change to the code, not just to the book, is what breaks these.
--

-- 1. ~ and ~/... expand to the reader's own home everywhere they are typed;
-- only ~name (no slash) stays literal. The book must say so, and must not
-- still carry the old, wrong claim that a typed tilde is never expanded.
do
	local home = "/home/admin"
	check("expandHome('~', home) is the home",
		CeroSecOS.expandHome("~", home) == home)
	check("expandHome('~/x', home) is inside the home",
		CeroSecOS.expandHome("~/x", home) == home .. "/x")
	check("expandHome('~root', home) is untouched",
		CeroSecOS.expandHome("~root", home) == "~root")
	check("book shows a tilde expanding (cat ~/)",
		string.find(wholeBook, "cat ~/", 1, true) ~= nil)
	check("book no longer claims a typed tilde is never expanded",
		string.find(wholeBook, "does not go home", 1, true) == nil and
		string.find(wholeBook, "never expanded", 1, true) == nil)
end

-- 2. formatStamp always prints month/day/hour/minute, never a year; a node
-- with no mtime reads as 0 and prints "Jan  1 00:00".
do
	check("formatStamp(0) is \"Jan  1 00:00\"",
		CeroSecOS.formatStamp(0) == "Jan  1 00:00")
	check("book carries the no-stamp stamp \"Jan  1 00:00\"",
		string.find(wholeBook, "Jan  1 00:00", 1, true) ~= nil)
	check("book no longer claims an old file prints its year",
		string.find(wholeBook, "prints its\nyear", 1, true) == nil and
		string.find(wholeBook, "prints its year", 1, true) == nil)
end

-- 3. All three digits of a mode are read, and exactly one of them decides:
-- the owner's if the account owns the node, the group's if it is in the
-- node's group, everybody else's otherwise. The book used to say the middle
-- digit decided nothing; it decides now, and must not still say otherwise.
do
	local state = CeroSecOS.newState("ksp-04-11")
	CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.GROUP_PATH, "crew:bob")
	local file = CeroSecOS.newFile("admin", 640)
	file.group = "crew"
	local ownerSession = { user = "admin" }
	local memberSession = { user = "bob" }
	local otherSession = { user = "kate" }

	check("the owner is judged by the first digit",
		CeroSecOS.can(state, ownerSession, file, "w"))
	check("a member of the group by the middle one",
		CeroSecOS.can(state, memberSession, file, "r")
			and not CeroSecOS.can(state, memberSession, file, "w"))
	check("and everybody else by the last",
		not CeroSecOS.can(state, otherSession, file, "r"))
	-- Move only the middle digit: only the member's access moves with it.
	file.mode = 600
	check("the middle digit is what the member gets",
		not CeroSecOS.can(state, memberSession, file, "r"))
	check("and the owner is unmoved", CeroSecOS.can(state, ownerSession, file, "w"))
	-- A primary group needs no line in the file at all.
	file.group = "bob"
	file.mode = 040
	check("a primary group is a membership",
		CeroSecOS.can(state, memberSession, file, "r"))
	-- A node with no group of its own reads as its owner's name.
	local old = CeroSecOS.newFile("admin", 640)
	old.group = nil
	check("a node with no group reads as its owner", CeroSecOS.groupOf(old) == "admin")

	check("book explains the middle digit is the group's",
		string.find(wholeBook, "one for the group, one for everybody else", 1, true) ~= nil)
	check("book says all three digits are read",
		string.find(wholeBook, "All three digits are read", 1, true) ~= nil)
	check("book no longer claims the middle digit decides nothing",
		string.find(wholeBook, "decides nothing", 1, true) == nil and
		string.find(wholeBook, "kept for a later release", 1, true) == nil)
	check("book shows the group column of ls -l",
		string.find(wholeBook, "-rw-r-----  admin  users     412", 1, true) ~= nil)
	check("book quotes /etc/group's format",
		string.find(wholeBook, "sudo:admin", 1, true) ~= nil)
end

-- 4. The BIOS repair rewrites every standard command in /bin unconditionally
-- (owner, mode and description), even one already present and chmod'd
-- away; it does not touch /home or /root, and leaves a still-parseable
-- /etc/passwd or /etc/sudoers alone.
do
	local state = CeroSecOS.newState("ksp-test")
	state.fs.children.bin.children.ls.mode = 600
	local marker = CeroSecOS.newFile("admin", 644, "mine")
	state.fs.children.home.children.admin.children["mine.txt"] = marker
	CeroSecOS.restoreSystem(state)
	check("restoreSystem resets a chmod'd standard command back to 755",
		state.fs.children.bin.children.ls.mode == 755)
	check("restoreSystem does not touch a player's own file under /home",
		state.fs.children.home.children.admin.children["mine.txt"] ~= nil)
	check("book says the repair always rewrites the standard commands",
		string.find(wholeBook, "always rewrites every standard command", 1, true) ~= nil)
end

-- 5. clear, exit (logout) and power loss/shutdown all wipe the console;
-- walking away does not. Both chapters that mention this must agree.
do
	local console = { lines = { "one", "two" } }
	CeroSec.consoleLogout(console)
	check("consoleLogout empties the console's lines",
		#console.lines == 0)
	local n = 0
	for _ in wholeBook:gmatch("clear, exit and power leaving the machine") do n = n + 1 end
	check("both chapters name the same three things that wipe the glass (" .. n .. ")",
		n >= 2)
end

-- 6. df's real header and two data lines, exactly as the engine prints
-- them for a fresh machine at env.now = 0.
do
	local state = CeroSecOS.newState("ksp-04-11")
	local session = { user = "admin", cwd = "/home/admin" }
	local ok, lines = CeroSecOS.exec(state, session, "df", { now = 0 })
	check("df ran", ok == true)
	for i = 1, #lines do
		check("book's df transcript carries the real line \"" .. lines[i] .. "\"",
			string.find(wholeBook, lines[i], 1, true) ~= nil)
	end
end

-- 7. The seven previously-missing error strings are all in the appendix
-- (also covered above by the scan and the hand list; named again here so
-- a regression in any one of them fails with its own message).
do
	local MISSING_BEFORE = {
		"unknown option", "invalid mode", "no manual entry", "no clock",
		"syntax error: bad redirect", "syntax error: unterminated quote",
		"syntax error: missing redirect target",
	}
	for i = 1, #MISSING_BEFORE do
		check("previously-missing error string now in the appendix: \""
			.. MISSING_BEFORE[i] .. "\"",
			string.find(errText, MISSING_BEFORE[i], 1, true) ~= nil)
	end
end

-- 8. /root ships at mode 700, not 750.
do
	local state = CeroSecOS.newState("ksp-04-11")
	check("/root ships at mode 700", state.fs.children.root.mode == 700)
	check("book states /root ships at 700",
		string.find(wholeBook, "/root, ships tighter, at 700", 1, true) ~= nil)
end

print(count .. " manual checks passed")
