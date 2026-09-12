-- Checks the manual against the engine it describes. Run from the repo root:
--   lua5.1 tests/manual_test.lua
--
-- There is ONE book on the shelf: the 1993 documentation SET, three volumes,
-- one file each -- CeroSecManualUser.lua (Volume 1, the User's Guide),
-- CeroSecManualAdmin.lua (Volume 2, the System Administrator's Guide) and
-- CeroSecManualProgrammer.lua (Volume 3, the Programmer's Guide). Each puts
-- itself into CeroSecManual.volumes at load time; CeroSecManual.lua is the table
-- they hang on and holds no text at all any more.
--
-- A volume has its own shape rules (8..13 chapters, 3..13 pages each, 50..80
-- pages, plain ASCII, nothing over a thousand characters, example lines inside
-- sixty columns) and its cover is stamped by the reader and never typed in the
-- file.
--
-- The two bounds moved at rung 4e, when the floppy drive gave Volume 1 a chapter
-- it did not have: twelve chapters and seventy pages were both exactly where the
-- three volumes already stood, so the next honest chapter could not be written at
-- all. Thirteen and seventy-six is the same book -- a 1993 user's guide was a
-- seventy-page paperback either way -- and the bounds are here to catch a volume
-- that has quietly lost half of itself, which they still do.
--
-- The COVERAGE rule is about the UNION of the three: the union of their
-- reference chapters must carry every COMMAND_INFO usage line, character for
-- character, and the union of their error appendices must carry every error
-- string the engine can print. WHICH volume carries a thing is the volume's own
-- business -- an administrator's refusal belongs in Volume 2 and a programmer's
-- in Volume 3 -- and what may never happen is a command or a refusal that no
-- volume carries at all.
--
-- The single book this mod shipped before the set (CeroSecManual.lua's own
-- chapters) was retired once all three volumes existed. Nothing falls back to
-- it, and an empty shelf is a volume file that failed to load.

local OS_DIR = "42/media/lua/shared/CeroSec/OS/"
local OS_FILES = {
	"CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath",
	"CeroSecOSRadio",
	"CeroSecOSScript", "CeroSecOSShell",
	"CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers", "CeroSecOSDev",
	"CeroSecOSDisk",
	"CeroSecOSVM",
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

-- The hardware modules, for the one thing the manual quotes out of them: what
-- each asks of an electrician. A level changed in the code has to break a PAGE.
local modulesPath = "42/media/lua/shared/CeroSec/CeroSecModules.lua"
do
	-- It is the first file this suite loads that requires another, and the game
	-- is what answers a require. Everything it asks for is already loaded above,
	-- so the stub is the honest one: nothing to do.
	local realRequire = require
	require = function() end
	local mchunk, merr = loadfile(modulesPath)
	if not mchunk then error("cannot load " .. modulesPath .. ": " .. tostring(merr)) end
	mchunk()
	require = realRequire
end

local MANUAL_DIR = "42/media/lua/shared/CeroSec/"

local chunk, err = loadfile(MANUAL_DIR .. "CeroSecManual.lua")
if not chunk then error("cannot load CeroSecManual.lua: " .. tostring(err)) end
chunk()

--
-- The volumes.
--
-- Every CeroSecManual*.lua beside the legacy book is loaded, and a file counts
-- as a volume only if loading it put something in CeroSecManual.volumes. That is
-- what lets a new volume file be dropped in and checked with no change here, and
-- what lets CeroSecManualBook.lua -- the LAYOUT engine, which is not text --
-- sit in the same directory without being mistaken for a book.
local volumeFiles = {}
do
	local ls = io.popen("ls -1 " .. MANUAL_DIR)
	if ls == nil then error("cannot list " .. MANUAL_DIR) end
	for name in ls:lines() do
		if string.find(name, "^CeroSecManual.+%.lua$") ~= nil then
			volumeFiles[#volumeFiles + 1] = name
		end
	end
	ls:close()
	table.sort(volumeFiles)
end

local volumes = {}
do
	CeroSecManual.volumes = CeroSecManual.volumes or {}
	for i = 1, #volumeFiles do
		local path = MANUAL_DIR .. volumeFiles[i]
		local vchunk, verr = loadfile(path)
		if not vchunk then error("cannot load " .. path .. ": " .. tostring(verr)) end
		vchunk()
	end
	-- In the order they are read, not the order the files happened to be listed.
	for n = 1, 16 do
		local vol = CeroSecManual.volumes[n]
		if type(vol) == "table" then
			vol.number = n
			volumes[#volumes + 1] = vol
		end
	end
end

local count = 0
local function check(what, cond)
	count = count + 1
	if not cond then error("FAIL: " .. what, 2) end
end

check("CeroSecManual is a table", type(CeroSecManual) == "table")
check("the version is one string in one place", type(CeroSecOS.VERSION) == "string"
	and CeroSecOS.VERSION ~= "")

--
-- The shelf, and the whole of what is on it.
--
-- There is no legacy book any more. CeroSecManual.lua held one volume for
-- somebody who had used a bigger Unix before, and it carried the machine on its
-- own until all three volumes of the 1993 set existed; now it holds the table
-- they hang themselves on and nothing else. So an empty shelf is not a state
-- this mod has -- it is a volume file that failed to load -- and it fails here.
--
check("the shelf holds the three volumes of the set (" .. #volumes .. ")",
	#volumes == 3)
check("and nothing is left of the single book: no chapters",
	CeroSecManual.chapters == nil)
check("no cover", CeroSecManual.title == nil)
check("and nothing to stamp one with", CeroSecManual.stampVersion == nil)

-- Every page of every volume, concatenated: what the sweeps below look for a
-- substring in. The union and not any one book, which is the rule this file has
-- been written to since the second volume arrived -- what matters is that the
-- SET says a thing, not which of the three says it.
local wholeBook = {}
for vi = 1, #volumes do
	local vchapters = volumes[vi].chapters
	for ci = 1, #vchapters do
		local pages = vchapters[ci].pages
		for pi = 1, #pages do wholeBook[#wholeBook + 1] = pages[pi] end
	end
end
wholeBook = table.concat(wholeBook, "\n")

-- The BIOS line the book prints is the BIOS line the machine prints.
check("the set quotes the real BIOS line",
	string.find(wholeBook, CeroSec.BOOT_LINES[1], 1, true) ~= nil)
check("and the firmware version is one string in one place",
	type(CeroSec.BIOS_VERSION) == "string" and CeroSec.BIOS_VERSION ~= "")

--
-- The chapters that are LISTS, gathered across the three volumes: a reference
-- chapter (the usage lines) and an error appendix (the strings the machine
-- prints). The coverage rules below are about the UNION of them and not about
-- any one volume -- an administrator's refusal belongs in Volume 2 and a
-- programmer's in Volume 3, and what must never happen is a command or a
-- refusal that NO volume carries.
--
local function chapterTextMatching(chapterList, ...)
	local wanted = { ... }
	local out = {}
	for ci = 1, #chapterList do
		local title = chapterList[ci].title
		for wi = 1, #wanted do
			if string.find(title, wanted[wi], 1, true) ~= nil then
				local pages = chapterList[ci].pages
				for pi = 1, #pages do out[#out + 1] = pages[pi] end
				break
			end
		end
	end
	if #out == 0 then return nil end
	return table.concat(out, "\n")
end

-- Volume 3's reference chapter is its GRAMMAR appendix: there was no room on
-- its shelf for a card of its own when it was written (twelve chapters, seventy
-- pages, both at what the ceilings then were) and the shapes of the words it
-- leans on -- sh, test, wait, printf --
-- are written there, beside the grammar they belong to.
local REF_TITLES = { "commands and limits", "Quick reference", "the grammar" }
local ERR_TITLES = { "what the machine says" }

-- The union, one string each. Every volume carries one of each, and the checks
-- below are what says so: a volume that lost its card or its appendix takes a
-- command or a refusal off the union with it.
local refUnion = {}
local errUnion = {}
for vi = 1, #volumes do
	local vol = volumes[vi]
	local r = chapterTextMatching(vol.chapters, unpack(REF_TITLES))
	if r ~= nil then refUnion[#refUnion + 1] = r end
	local e = chapterTextMatching(vol.chapters, unpack(ERR_TITLES))
	if e ~= nil then errUnion[#errUnion + 1] = e end
end
refUnion = table.concat(refUnion, "\n")
errUnion = table.concat(errUnion, "\n")

--
-- Every command in COMMAND_INFO appears in a quick-reference chapter, with its
-- exact usage line.
--
local commandNames = {}
for name, info in pairs(CeroSecOS.COMMAND_INFO) do
	commandNames[#commandNames + 1] = name
	check("a quick reference names " .. name, string.find(refUnion, name, 1, true) ~= nil)
	check("a quick reference carries " .. name .. "'s exact usage line",
		string.find(refUnion, info.usage, 1, true) ~= nil)
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
local errText = errUnion

-- The shared filesystem reasons (CeroSecOSFS.lua), bare, before the shell
-- prefixes them with "<command>: <path>: ".
local FS_REASONS = {
	"no such file", "is a directory", "not a directory", "permission denied",
	"file exists", "invalid name", "path too deep", "directory full",
	"disk full", "file too large", "invalid characters", "invalid destination",
	-- What a move answers when it is asked to write a directory over one that
	-- has something in it: rename(2)'s ENOTEMPTY, in this machine's own words.
	"directory not empty",
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
	"useradd: <name>: already exists",
	"userdel: <name>: user is logged in",
	"userdel: root: cannot remove",
	"chown: <name>: no such user",
	"mkpasswd: <salt>: invalid salt",
	-- SYSTEM_VERSION 16's own: the one list `usermod -G` will not take.
	"usermod: empty group list",
	"help: no commands in " .. CeroSecOS.BIN_PATH .. ": the system is damaged.",
	"help: switch the computer off and on to repair it.",
	"cerosec: nothing to answer",
	"syntax error: bad redirect",
	"syntax error: unterminated quote",
	"syntax error: missing redirect target",
	-- rung 5b: the pipeline's own two, neither of which goes through fail()
	"too many stages",
	"input too large",
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
	"blocked",
	"invalid value",
	-- What a device with nothing behind it to write with answers: write(2)'s own
	-- EOPNOTSUPP text, in this machine's lower case (CeroSecOSDev's devWrite,
	-- and SCeroSecDevices' act for the belt behind it).
	"operation not supported",
	CeroSecOS.DEV_PATH .. ": read-only",
}
for i = 1, #DEVICE_MESSAGES do
	check("error appendix carries the device reason \"" .. DEVICE_MESSAGES[i] .. "\"",
		string.find(errText, DEVICE_MESSAGES[i], 1, true) ~= nil)
end

-- A door's three refusals, whole lines: "locked" and "barricaded" are words
-- other kinds use too, so the bare sweep above cannot tell whether the appendix
-- says them about a DOOR.
local DOOR_LINES = { "door0: locked", "door0: barricaded", "door0: blocked" }
for i = 1, #DOOR_LINES do
	check("error appendix carries \"" .. DOOR_LINES[i] .. "\"",
		string.find(errText, DOOR_LINES[i], 1, true) ~= nil)
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
-- The disk as the BIOS and df spell it, off CeroSecOS.diskLabel rather than typed:
-- the drive grew when the floppy arrived (rung 4e) and a hand-typed "32K" here
-- would have passed on a book that still said the old number.
check("the set states the disk size (" .. CeroSecOS.diskLabel() .. ")",
	string.find(wholeBook, CeroSecOS.diskLabel(), 1, true) ~= nil)
check("the set states the node ceiling (" .. CeroSecOS.MAX_NODES .. ")",
	string.find(wholeBook, tostring(CeroSecOS.MAX_NODES), 1, true) ~= nil)
check("the set states the file size ceiling (" .. CeroSecOS.MAX_FILE_BYTES .. ")",
	string.find(wholeBook, tostring(CeroSecOS.MAX_FILE_BYTES), 1, true) ~= nil)
check("the set states the su stack ceiling (" .. CeroSecOS.SU_MAX .. ")",
	string.find(wholeBook, "four", 1, true) ~= nil or
	string.find(wholeBook, tostring(CeroSecOS.SU_MAX), 1, true) ~= nil)

--
-- Eight fact-checked defects, each pinned against the engine so a future
-- change to the code, not just to the book, is what breaks these.
--
-- They were written against the single book that used to be on the shelf, whose
-- wording they quoted. That book is gone and the three volumes say the same
-- things in their own words, so what is quoted here is THEIR wording -- the
-- engine half of every one of them is untouched, because the engine half is the
-- part that is worth having.
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
	check("the set shows a tilde expanding",
		string.find(wholeBook, "cd ~ goes home", 1, true) ~= nil
		and string.find(wholeBook, "~/notes is your own", 1, true) ~= nil)
	check("and never claims a typed tilde is not expanded",
		string.find(wholeBook, "does not go home", 1, true) == nil and
		string.find(wholeBook, "never expanded", 1, true) == nil)
end

-- 2. formatStamp always prints month/day/hour/minute, never a year; a node
-- with no mtime reads as 0 and prints "Jan  1 00:00".
do
	check("formatStamp(0) is \"Jan  1 00:00\"",
		CeroSecOS.formatStamp(0) == "Jan  1 00:00")
	check("the set carries the no-stamp stamp \"Jan  1 00:00\"",
		string.find(wholeBook, "Jan  1 00:00", 1, true) ~= nil)
	check("and never claims an old file prints its year",
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

	check("the set explains the middle digit is the group's",
		string.find(wholeBook, "The next three are the group's", 1, true) ~= nil
		and string.find(wholeBook, "The last three are everybody else's", 1, true) ~= nil)
	check("and says all three digits are read",
		string.find(wholeBook, "All three digits are read", 1, true) ~= nil)
	check("and never claims the middle digit decides nothing",
		string.find(wholeBook, "middle digit decides nothing", 1, true) == nil and
		string.find(wholeBook, "kept for a later release", 1, true) == nil)
	check("the set shows the group column of ls -l",
		string.find(wholeBook, "-rw-r-----  admin  users      11", 1, true) ~= nil)
	check("and quotes /etc/group's format",
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
	check("the set says the repair always rewrites the standard commands",
		string.find(wholeBook, "it rewrites every standard command, every time",
			1, true) ~= nil)
end

-- 5. clear, exit (logout) and power loss/shutdown all wipe the console;
-- walking away does not. Both chapters that mention this must agree.
do
	local console = { lines = { "one", "two" } }
	CeroSec.consoleLogout(console)
	check("consoleLogout empties the console's lines",
		#console.lines == 0)
	-- One place now, and one is enough: the legacy book said it in two chapters and
	-- this was the check that they agreed. Volume 1 is the book the glass belongs
	-- to and it says it once, in the chapter about reading the screen.
	check("the set names the three things that wipe the glass",
		string.find(wholeBook,
			"clear typed by hand, exit logging\nout, and power leaving the machine",
			1, true) ~= nil)
end

-- 6. df's real header and two data lines, exactly as the engine prints
-- them for a fresh machine at env.now = 0.
do
	local state = CeroSecOS.newState("ksp-04-11")
	local session = { user = "admin", cwd = "/home/admin" }
	-- Straight at the command rather than through the prompt: there is no
	-- single-line entry point any more (the prompt is the script engine, rung
	-- 5a.1) and what this bench wants is df's own lines.
	local ok, lines = CeroSecOS.runArgs(state, session, { "df" }, nil, { now = 0 })
	check("df ran", ok == true)
	for i = 1, #lines do
		check("the set's df transcript carries the real line \"" .. lines[i] .. "\"",
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
	check("the set states /root ships at 700",
		string.find(wholeBook, "/root is root's own at mode 700", 1, true) ~= nil)
end

--
-- The volumes.
--
-- Same form rules as the legacy book, with a volume's own bounds, plus the two
-- things only a volume has: a cover that is NOT written in the file (the reader
-- stamps it from CeroSecOS.VERSION, so a `title` typed here would be a second
-- copy of the number) and a `name` for the reader to stamp it with.
--
check("at least one volume exists", #volumes >= 1)

local volumeById = {}

for vi = 1, #volumes do
	local vol = volumes[vi]
	local where = "volume " .. vol.number

	check(where .. " has an id", type(vol.id) == "string" and vol.id ~= "")
	check(where .. " has a name", type(vol.name) == "string" and vol.name ~= "")
	check(where .. " has an edition", type(vol.edition) == "string" and vol.edition ~= "")
	-- Not a mistake and not an omission: the cover is stamped, and a volume that
	-- typed its own title would name an OS version the engine did not hand it.
	check(where .. " leaves its title to the reader", vol.title == nil)
	check(where .. " has chapters", type(vol.chapters) == "table")
	volumeById[vol.id] = vol

	local vchapters = vol.chapters
	check(where .. " has 8..13 chapters (" .. #vchapters .. ")",
		#vchapters >= 8 and #vchapters <= 13)

	local vpages, vseen, vwhole = 0, {}, {}
	for ci = 1, #vchapters do
		local ch = vchapters[ci]
		local cwhere = where .. " chapter " .. ci
		check(cwhere .. " has a title", type(ch.title) == "string" and ch.title ~= "")
		check(cwhere .. " title is unique", vseen[ch.title] == nil)
		vseen[ch.title] = true
		check(cwhere .. " has pages", type(ch.pages) == "table")
		local n = #ch.pages
		-- Nine and not eight since rung 6b, and the volume that moved it is the one
		-- that earned it: the telephone is a second kind of link and it went into the
		-- chapter the first one is in, because a reader looking for "how do I reach
		-- that machine" must not have to know which wire the answer is about. Eight
		-- was the width of the widest chapter there was and never a rule about
		-- reading; the page ceiling and the volume's fifty-to-seventy-six are what
		-- keep a chapter a chapter.
		--
		-- Thirteen since rung 6c, and the same volume earned it a second time for the
		-- same reason: the RADIO is the third kind of link and it went into that one
		-- chapter too, because "how do I reach that machine" has three answers now
		-- and a reader who had to pick the chapter by the wire would have to know
		-- the answer before he could look it up. Chapter 8 of Volume 2 is therefore
		-- the widest chapter in the set on purpose -- it is three chapters' worth of
		-- one subject -- and nothing else in the book is allowed near this number:
		-- the 1000-character page and the volume's own page total are what keep a
		-- chapter a chapter, and neither of those moved.
		--
		-- Fourteen since rung 6d, and the same volume earned it a third time for the
		-- reason the first two were earned: `arp` is what joins the names ruptime
		-- broadcasts to the addresses /etc/hosts wants, and a reader looking for "how
		-- do I reach that machine" would have to know he was missing a NAME before he
		-- could find the page that says so. It is one page, and the chapter it belongs
		-- in is the one the other three answers are in. Thirteen was exactly where
		-- this chapter already stood, which is a bound forbidding the next honest page
		-- rather than catching a chapter that has swallowed a book.
		check(cwhere .. " (" .. ch.title .. ") has 3..14 pages (" .. n .. ")",
			n >= 3 and n <= 14)
		vpages = vpages + n

		for pi = 1, n do
			local page = ch.pages[pi]
			local pwhere = where .. " " .. ch.title .. " page " .. pi
			check(pwhere .. " is a string", type(page) == "string")
			check(pwhere .. " is not empty",
				page ~= "" and string.find(page, "%S") ~= nil)
			check(pwhere .. " is at most 1000 characters (" .. #page .. ")", #page <= 1000)

			for i = 1, #page do
				local b = string.byte(page, i)
				check(pwhere .. " byte " .. i .. " is ASCII (" .. b .. ")",
					b == 9 or b == 10 or (b >= 32 and b <= 126))
			end

			for line in (page .. "\n"):gmatch("([^\n]*)\n") do
				if string.sub(line, 1, 2) == "  " then
					check(pwhere .. ' example line fits 60 columns: "' .. line ..
						'" (' .. #line .. ")", #line <= 60)
				end
			end

			-- No page names an OS version of its own, exactly as in the legacy
			-- book: the cover is the only place the number appears at all. The
			-- letter test in front of "OS" lets "CeroSec BIOS 1.0" through.
			for pos in string.gmatch(page, "()OS %d+%.%d+") do
				local before = pos > 1 and string.sub(page, pos - 1, pos - 1) or ""
				check(pwhere .. " names no OS version of its own",
					string.find(before, "%a") ~= nil)
			end

			vwhole[#vwhole + 1] = page
		end
	end

	-- Eighty and not seventy-six since rung 6c, and it is the same kind of move
	-- the last one was: the radio is five pages of chapter 8 plus two of the
	-- appendix, and seventy-six was exactly where Volume 2 already stood -- a bound
	-- sitting on the current number is a bound that forbids the next honest
	-- chapter rather than catching a volume that has lost half of itself, which is
	-- what it is for. An eighty-page administrator's guide is still a 1993
	-- paperback.
	-- Eighty-four since rung 6d, and it moved for the third time for the reason it
	-- moved the first two: arp is a page of chapter 8 and a page of the appendix,
	-- and eighty was exactly where Volume 2 then stood. A bound resting on the
	-- current number forbids the next honest page instead of catching a volume that
	-- has lost half of itself.
	check(where .. " has 50..84 pages (" .. vpages .. ")",
		vpages >= 50 and vpages <= 84)
	vol.wholeText = table.concat(vwhole, "\n")
end

--
-- Volume 1, the User's Guide, has two rules of its own.
--
do
	local vol = volumeById["user"]
	check("Volume 1 is the User's Guide", vol ~= nil and vol.name == "User's Guide")

	--
	-- 1. The reference card is nothing but exact usage lines.
	--
	-- Every line of it that is a screen line is one COMMAND_INFO usage line,
	-- character for character. So a card entry cannot drift from the shell's own
	-- grammar, and a command the card names with the wrong shape fails here
	-- rather than sending a player to type something the machine refuses.
	--
	local card = nil
	for ci = 1, #vol.chapters do
		if string.find(vol.chapters[ci].title, "Quick reference", 1, true) ~= nil then
			card = vol.chapters[ci]
		end
	end
	check("Volume 1 has a quick-reference card", card ~= nil)

	local carded, entries = {}, 0
	for pi = 1, #card.pages do
		for line in (card.pages[pi] .. "\n"):gmatch("([^\n]*)\n") do
			if string.sub(line, 1, 2) == "  " then
				local body = string.sub(line, 3)
				local name = string.match(body, "^(%S+)")
				check('card line names a command: "' .. body .. '"',
					name ~= nil and CeroSecOS.COMMAND_INFO[name] ~= nil)
				check('card line is ' .. name .. "'s exact usage line: \"" .. body .. '"',
					body == CeroSecOS.commandUsage(name))
				carded[name] = true
				entries = entries + 1
			end
		end
	end
	-- A card that has quietly lost half its entries is a card that still passes
	-- every check above.
	check("the card carries at least 30 commands (" .. entries .. ")", entries >= 30)

	-- And the commands a first volume has no business naming are not on it: the
	-- accounts, the groups, sudo, the devices, cron and the network are Volumes
	-- 2 and 3, and a card that hands a beginner `deluser` is a card that lies
	-- about which book he is holding.
	local NOT_VOLUME_ONE = {
		"useradd", "userdel", "usermod", "groupadd", "groupdel", "sudo",
		"dev", "crontab", "mail", "ifconfig", "ping", "rcp", "rlogin",
		"rsh", "ruptime", "rwho", "hostname", "sh",
	}
	for i = 1, #NOT_VOLUME_ONE do
		check("the card leaves " .. NOT_VOLUME_ONE[i] .. " to a later volume",
			carded[NOT_VOLUME_ONE[i]] == nil)
	end

	--
	-- 2. Every screen line that shows somebody typing shows a real word.
	--
	-- A "Try it" box that tells a beginner to type something the machine has
	-- never heard of is the one kind of error that costs him his trust in the
	-- whole book. Running all of them here is not possible -- most want a disk
	-- in a particular state -- so what is checked is the first word of every
	-- line that carries a prompt: it has to be a command the machine has, a word
	-- the shell itself is, a reserved word, a variable being set, or a history
	-- event.
	--
	-- The one exception is a short, declared list of words the book introduces on
	-- purpose. Anything else is a typo or an invention, and fails.
	local DELIBERATE = {
		-- chapter 8 has the reader make this one himself, in ~/bin
		hello = true,
		-- chapter 2 types this on purpose, to show "command not found"
		sl = true,
	}

	local shown = 0
	for ci = 1, #vol.chapters do
		local ch = vol.chapters[ci]
		for pi = 1, #ch.pages do
			for line in (ch.pages[pi] .. "\n"):gmatch("([^\n]*)\n") do
				if string.sub(line, 1, 2) == "  " then
					local word = string.match(line, "^  %S+@%S-[%$#] (%S+)")
					if word ~= nil then
						shown = shown + 1
						local known = CeroSecOS.COMMAND_INFO[word] ~= nil
							or CeroSecOS.SHELL_BUILTINS[word] == true
							or CeroSecOS.RESERVED[word] == true
							or DELIBERATE[word] == true
							-- x=... , a variable being set
							or string.find(word, "^[%a_][%w_]*=") ~= nil
							-- !! and !5 , a line from the history
							or string.find(word, "^!") ~= nil
						check(ch.title .. ' page ' .. pi ..
							' types a word the machine knows: "' .. word .. '"', known)
					end
				end
			end
		end
	end
	check("Volume 1 shows at least 30 typed lines (" .. shown .. ")", shown >= 30)

	--
	-- 3. The numbers a beginner will actually run into are the engine's.
	--
	-- Each of these is a whole PHRASE built from the constant, not the bare
	-- number: "96" on its own is a substring of "4096" and "32" of "32768", so a
	-- bare-number search passes on a book that has gone stale. What is searched
	-- is the volume's own text with every run of whitespace flattened to one
	-- space, because the reader reflows prose and a sentence may wrap anywhere.
	--
	local flat = string.gsub(vol.wholeText, "%s+", " ")
	local function states(what, phrase)
		check("Volume 1 states " .. what .. ': "' .. phrase .. '"',
			string.find(flat, phrase, 1, true) ~= nil)
	end

	states("the screen", "Screen: " .. CeroSecOS.COLS .. " columns wide, "
		.. CeroSec.ROWS .. " rows tall")
	states("the editor's rows", "gets " .. CeroSec.EDIT_ROWS .. " of those rows")
	states("the editor's line width",
		"a line stops at " .. CeroSec.EDIT_MAX_LINE .. " characters")
	states("the typing line", "typing line takes " .. CeroSec.INPUT_MAX .. " characters")
	states("one file's ceiling", "One file: " .. CeroSecOS.MAX_FILE_BYTES .. " bytes.")
	states("the drive", "The drive: " .. CeroSecOS.DISK_BYTES .. " bytes and "
		.. CeroSecOS.MAX_NODES .. " files")
	states("one directory's ceiling",
		"One directory: " .. CeroSecOS.MAX_DIR_ENTRIES .. " entries.")
	states("how deep a path may go",
		CeroSecOS.MAX_DEPTH .. " levels of directory below the root, and "
		.. CeroSecOS.MAX_NAME .. " characters in any one name")
	states("the history kept", "the last " .. CeroSecOS.HISTORY_MAX .. " lines and "
		.. (CeroSecOS.HISTORY_BYTES / 1024) .. " kilobytes")
	states("what history prints",
		"prints the last " .. CeroSecOS.HISTORY_SHOW .. " of them")
	states("how many directories PATH may name",
		"PATH may name " .. CeroSecOS.MAX_PATH_DIRS .. " directories")
	states("how deep su stacks", "su stacks " .. CeroSecOS.SU_MAX .. " deep")

	-- The name column of ls -l, which the legacy book gets wrong: it says
	-- seventeen and the engine cuts at twelve. Measured off the engine rather
	-- than typed, by listing a name too long for it and counting what came back.
	do
		local state = CeroSecOS.newState("ksp-04-11")
		local session = CeroSecOS.login(state, "admin", "")
		local ok, lines = CeroSecOS.runArgs(state, session,
			{ "touch", string.rep("a", CeroSecOS.MAX_NAME) }, nil, { now = 0 })
		check("the bench could make a long-named file", ok == true)
		ok, lines = CeroSecOS.runArgs(state, session, { "ls", "-l" }, nil, { now = 0 })
		check("the bench could list it", ok == true and #lines == 1)
		local shown = string.match(lines[1], "(%S+)$")
		check("and the engine really did cut the name", string.find(shown, "~", 1, true) ~= nil)
		states("the ls -l name column", "a name up to " .. #shown .. " characters")
		check("Volume 1 says the width in words too, in chapter 3",
			string.find(flat, "twelve characters wide", 1, true) ~= nil)
		check("and twelve really is the number the engine cut to", #shown == 12)
	end

	-- The two lines it quotes off a real screen, which are the two a player is
	-- most likely to compare against the glass in front of him.
	check("Volume 1 quotes the real BIOS line",
		string.find(vol.wholeText, CeroSec.BOOT_LINES[1], 1, true) ~= nil)
	-- editKeys() is padded out to the width of the bar it draws; what the book
	-- shows is the bar with its trailing blank taken off, which a page may not
	-- carry (a run of spaces at the end of a line is not something to print).
	check("Volume 1 quotes the editor's key bar",
		string.find(vol.wholeText, (string.gsub(CeroSec.editKeys(), "%s+$", "")), 1, true) ~= nil)

	-- Every chapter carries its "Classic mistake" box. It is the shape Mathieu
	-- asked for, and a chapter that quietly loses one loses the part a beginner
	-- reads first.
	for ci = 1, #vol.chapters do
		local ch = vol.chapters[ci]
		local has = false
		for pi = 1, #ch.pages do
			if string.find(ch.pages[pi], "Classic mistake", 1, true) ~= nil then has = true end
		end
		check(ch.title .. " has a Classic mistake box", has)
	end
end

--
-- Volume 2, the System Administrator's Guide, has the same three rules as
-- Volume 1 -- a card that is nothing but usage lines, typed words the machine
-- knows, numbers taken off the engine -- plus the two a book about running a
-- machine for other people owes: the DEVICE and NETWORK refusals as whole
-- lines, and cron's refusal in the shape cron locates it with.
--
do
	local vol = volumeById["admin"]
	check("Volume 2 is the System Administrator's Guide",
		vol ~= nil and vol.name == "System Administrator's Guide")

	--
	-- 1. The reference card is nothing but exact usage lines.
	--
	local card = nil
	for ci = 1, #vol.chapters do
		if string.find(vol.chapters[ci].title, "Quick reference", 1, true) ~= nil then
			card = vol.chapters[ci]
		end
	end
	check("Volume 2 has a quick-reference card", card ~= nil)

	local carded, entries = {}, 0
	for pi = 1, #card.pages do
		for line in (card.pages[pi] .. "\n"):gmatch("([^\n]*)\n") do
			if string.sub(line, 1, 2) == "  " then
				local body = string.sub(line, 3)
				local name = string.match(body, "^(%S+)")
				check('Volume 2 card line names a command: "' .. body .. '"',
					name ~= nil and CeroSecOS.COMMAND_INFO[name] ~= nil)
				check('Volume 2 card line is ' .. name .. "'s exact usage line: \""
					.. body .. '"', body == CeroSecOS.commandUsage(name))
				carded[name] = true
				entries = entries + 1
			end
		end
	end
	check("Volume 2's card carries at least 30 commands (" .. entries .. ")", entries >= 30)

	-- Everything this volume is FOR is on it. A card that has quietly lost the
	-- devices, or cron, or the wire, still passes every check above.
	local IS_VOLUME_TWO = {
		"su", "sudo", "exit", "useradd", "userdel", "passwd", "id", "groups", "mkpasswd",
		"groupadd", "groupdel", "usermod", "chmod", "chown", "chgrp",
		"hostname", "df", "ps", "jobs", "kill", "fg",
		"shutdown", "halt", "reboot", "restart",
		"dev", "crontab", "mail",
		"ifconfig", "ping", "ruptime", "rwho", "who", "last", "rlogin", "rsh", "rcp",
	}
	for i = 1, #IS_VOLUME_TWO do
		check("Volume 2's card carries " .. IS_VOLUME_TWO[i],
			carded[IS_VOLUME_TWO[i]] == true)
	end

	-- And the commands that are somebody else's book are not on it. Reading,
	-- writing and moving files is Volume 1's chapter 3; the shell's own words and
	-- the script tools are Volume 3. A card that hands an administrator `grep`
	-- again is a card that has stopped being a second volume.
	local NOT_VOLUME_TWO = {
		"ls", "cat", "cd", "pwd", "mkdir", "touch", "cp", "mv", "rm", "echo",
		"edit", "write", "head", "tail", "wc", "grep", "sort", "uniq",
		"date", "sleep", "ln", "readlink", "which", "type", "man", "whoami",
		"printf", "test", "true", "false", "wait", "sh", "clear", "help",
	}
	for i = 1, #NOT_VOLUME_TWO do
		check("Volume 2's card leaves " .. NOT_VOLUME_TWO[i] .. " to another volume",
			carded[NOT_VOLUME_TWO[i]] == nil)
	end

	--
	-- 2. Every screen line that shows somebody typing shows a real word.
	--
	-- Volume 2 needs no list of words it introduces on purpose: every line it
	-- shows being typed is a command the machine has.
	local shown = 0
	for ci = 1, #vol.chapters do
		local ch = vol.chapters[ci]
		for pi = 1, #ch.pages do
			for line in (ch.pages[pi] .. "\n"):gmatch("([^\n]*)\n") do
				if string.sub(line, 1, 2) == "  " then
					local word = string.match(line, "^  %S+@%S-[%$#] (%S+)")
					if word ~= nil then
						shown = shown + 1
						local known = CeroSecOS.COMMAND_INFO[word] ~= nil
							or CeroSecOS.SHELL_BUILTINS[word] == true
							or CeroSecOS.RESERVED[word] == true
							or string.find(word, "^[%a_][%w_]*=") ~= nil
							or string.find(word, "^!") ~= nil
						check(ch.title .. ' page ' .. pi ..
							' types a word the machine knows: "' .. word .. '"', known)
					end
				end
			end
		end
	end
	check("Volume 2 shows at least 40 typed lines (" .. shown .. ")", shown >= 40)

	--
	-- 3. The ceilings an administrator runs into are the engine's, each as a
	-- PHRASE built from the constant rather than as a bare number: "4" on its own
	-- is a substring of half the numbers on the machine.
	--
	local flat = string.gsub(vol.wholeText, "%s+", " ")
	local function states(what, phrase)
		check("Volume 2 states " .. what .. ': "' .. phrase .. '"',
			string.find(flat, phrase, 1, true) ~= nil)
	end

	states("a name's and a password's length",
		"a name is " .. CeroSecOS.MAX_USERNAME .. " characters, and a password "
		.. CeroSecOS.MAX_PASSWORD)
	states("the hostname's length",
		"name is " .. CeroSecOS.HOSTNAME_MAX .. " characters too")
	states("how deep su stacks", "su stacks " .. CeroSecOS.SU_MAX .. " deep")
	states("the modes the system files ship at",
		"/etc/passwd is " .. CeroSecOS.PASSWD_MODE .. ", /etc/sudoers "
		.. CeroSecOS.SUDOERS_MODE .. " and /etc/group " .. CeroSecOS.GROUP_MODE)
	states("the motd's ceiling",
		"/etc/motd holds " .. CeroSecOS.MOTD_MAX_LINES .. " lines")
	states("a crontab's ceiling",
		"A crontab holds " .. CeroSecOS.CRON_MAX_LINES .. " lines")
	-- The hardware modules' levels, read off the list the install and the recipes
	-- both run on rather than typed here: a module that moved a level has to
	-- break this page.
	do
		local byId = {}
		for i = 1, #CeroSecModules.LIST do
			byId[CeroSecModules.LIST[i].id] = CeroSecModules.LIST[i]
		end
		check("a contact and a relay are the same level",
			byId.contact.skill == byId.relay.skill)
		states("what each module asks of an electrician",
			"a contact or a relay at Electricity " .. byId.contact.skill
			.. ", a strike at " .. byId.strike.skill
			.. ", an operator at " .. byId.operator.skill)
	end

	states("the devices", CeroSecOS.DEV_MAX .. " devices at most, at mode "
		.. CeroSecOS.DEV_MODE .. ", and dev find shows one for "
		.. CeroSecOS.DEV_FIND_SECONDS .. " seconds")
	states("the job ceiling", CeroSecOS.MAX_JOBS .. " jobs to a machine")
	states("the cpu limit",
		(CeroSec.JOB_CPU_LIMIT_S / 60) .. " minutes with nothing to wait for")
	states("how many sessions may come in",
		CeroSecOS.PTY_MAX .. " sessions in at once, on "
		.. CeroSecOS.ptyLine(0) .. " to " .. CeroSecOS.ptyLine(CeroSecOS.PTY_MAX - 1))
	states("how deep a chain of rlogins goes",
		"rlogins " .. CeroSecOS.HOP_MAX .. " machines deep")
	states("the logs' ceilings",
		"/var/log/wtmp holds " .. CeroSecOS.WTMP_LINES .. " lines, /var/log/cron "
		.. CeroSecOS.CRON_LOG_LINES .. ", and a mailbox " .. CeroSecOS.MAIL_LINES)
	states("what the exempt logs are exempt from",
		"disk's " .. CeroSecOS.DISK_BYTES .. " bytes")

	--
	-- 4. Volume 2's own error appendix carries the device and the network
	-- refusals as WHOLE LINES.
	--
	-- The bare-word sweep at the top of this file cannot tell whether an appendix
	-- says "barricaded" about a window or about a door, or whether "Host is down"
	-- was signed by rlogin at all. This volume is the book those lines belong to,
	-- so it is held to the whole line.
	--
	local vErr = chapterTextMatching(vol.chapters, unpack(ERR_TITLES))
	check("Volume 2 has an error appendix", vErr ~= nil)

	local DEVICE_LINES = {
		"light0: no power", "lock0: no such device", "win0: smashed",
		"win0: barricaded", "lock1: no padlock", "door0: locked",
		"door0: barricaded", "door0: blocked", "light0: invalid value",
		"light0: permission denied", "win0: cannot toggle",
		"door0: operation not supported",
		"dev: <word>: unknown kind", "dev: <id>: no such device",
		CeroSecOS.DEV_PATH .. ": read-only",
	}
	for i = 1, #DEVICE_LINES do
		check("Volume 2's appendix carries the whole line \"" .. DEVICE_LINES[i] .. "\"",
			string.find(vErr, DEVICE_LINES[i], 1, true) ~= nil)
	end

	-- The kinds, derived from the table the engine judges a value against rather
	-- than hand-listed: a fifth kind is a book that has gone stale.
	do
		local kinds = {}
		for kind in pairs(CeroSecOS.DEV_VALUES) do kinds[#kinds + 1] = kind end
		table.sort(kinds)
		check("more than two kinds of device to list", #kinds >= 3)
		local sentence = table.concat(kinds, ", ", 1, #kinds - 1)
			.. " and " .. kinds[#kinds]
		check("Volume 2 names every kind of device: \"" .. sentence .. "\"",
			string.find(vErr, sentence, 1, true) ~= nil)
	end

	-- The network's five, each composed by the engine's own netRefusal so that a
	-- change to a word fails here rather than going stale on the page.
	local NET_LINES = {
		CeroSecOS.netRefusal("rlogin", "gate", "unknown"),
		CeroSecOS.netRefusal("rlogin", "gate", "down"),
		CeroSecOS.netRefusal("rlogin", "gate", "unreach"),
		CeroSecOS.netRefusal("rlogin", "gate", "refused"),
		CeroSecOS.netRefusal("rsh", "gate", "denied"),
	}
	for i = 1, #NET_LINES do
		check("Volume 2's appendix carries the whole line \"" .. NET_LINES[i] .. "\"",
			string.find(vErr, NET_LINES[i], 1, true) ~= nil)
	end
	local NET_OTHER = {
		"Connection closed.",
		"ifconfig: interface eth9 does not exist",
		"ping: unknown host gate",
	}
	for i = 1, #NET_OTHER do
		check("Volume 2's appendix carries \"" .. NET_OTHER[i] .. "\"",
			string.find(vErr, NET_OTHER[i], 1, true) ~= nil)
	end

	-- The five that want somebody at the glass, whole lines and all: a crontab
	-- line, a background job and a pipeline stage all meet them, and an
	-- administrator who does not know the list writes a crontab that cannot run.
	local NO_TTY = { "rlogin", "su", "passwd", "sudo", "edit" }
	for i = 1, #NO_TTY do
		check("Volume 2's appendix carries \"" .. NO_TTY[i] .. ": not a terminal\"",
			string.find(vErr, NO_TTY[i] .. ": not a terminal", 1, true) ~= nil)
	end

	--
	-- 5. cron's refusal is located the way cron locates it: the file in quotes,
	-- the line, and the field. Composed by the engine's own cronError, and the
	-- field names read off CRON_FIELDS rather than typed.
	--
	do
		local path = CeroSecOS.cronPath("admin")
		check("Volume 2's appendix carries cron's locator format",
			string.find(vErr, CeroSecOS.cronError(path, 1, "bad minute"), 1, true) ~= nil)
		for i = 1, #CeroSecOS.CRON_FIELDS do
			local reason = "bad " .. CeroSecOS.CRON_FIELDS[i].name
			check("Volume 2's appendix names cron's reason \"" .. reason .. "\"",
				string.find(vErr, reason, 1, true) ~= nil)
		end
		check("Volume 2's appendix carries cron's two other refusals",
			string.find(vErr, CeroSecOS.cronError(path, 1, "bad command"), 1, true) ~= nil
			and string.find(vErr,
				CeroSecOS.cronError(path, 1, "bad time specifier"), 1, true) ~= nil)
		-- The line a crontab one entry too long is refused on.
		check("Volume 2's appendix carries the too-many-entries line",
			string.find(vErr, CeroSecOS.cronError(path,
				CeroSecOS.CRON_MAX_LINES + 1, "too many entries"), 1, true) ~= nil)
		check("Volume 2's appendix carries cron's and mail's empty answers",
			string.find(vErr, "no crontab for <name>", 1, true) ~= nil
			and string.find(vErr, "No mail for <name>", 1, true) ~= nil)
		check("Volume 2's appendix carries the log's own line about a full machine",
			string.find(vErr, "(CRON) error (can't fork)", 1, true) ~= nil)
	end

	--
	-- 6. Every chapter carries its "Classic mistake" box, as Volume 1's do.
	--
	for ci = 1, #vol.chapters do
		local ch = vol.chapters[ci]
		local has = false
		for pi = 1, #ch.pages do
			if string.find(ch.pages[pi], "Classic mistake", 1, true) ~= nil then has = true end
		end
		check("Volume 2: " .. ch.title .. " has a Classic mistake box", has)
	end

	--
	-- 7. Three facts this volume is the only book that states, each pinned to the
	-- engine so that a change to the CODE is what breaks the page.
	--
	do
		-- The su stack really is four deep and exit really pops it.
		local state = CeroSecOS.newState("ksp-04-11")
		local root = CeroSecOS.login(state, "root", "")
		check("the bench got a root session", root ~= nil)
		check("Volume 2 says exit pops the stack rather than logging out",
			string.find(flat, "It did not log anybody out", 1, true) ~= nil)

		-- /etc/sudoers really ships naming admin, which is what chapter 10's
		-- checklist tells the reader to read.
		local sudoers = CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH)
		check("/etc/sudoers ships naming admin",
			sudoers ~= nil and string.find(sudoers.data or "", "\nadmin", 1, true) ~= nil)
		check("and ships at the mode the book states",
			sudoers.mode == CeroSecOS.SUDOERS_MODE)

		-- /var/spool/cron really is root's at 700, which is the whole reason
		-- chapter 7 says crontab is the only way in.
		local spool = CeroSecOS.getNode(state, root, CeroSecOS.CRON_PATH)
		check("/var/spool/cron is root's", spool ~= nil and spool.owner == "root")
		check("and ships at the mode the book states", spool.mode == CeroSecOS.CRON_DIR_MODE)
		check("Volume 2 says so", string.find(flat,
			"The directory is root's at mode " .. CeroSecOS.CRON_DIR_MODE, 1, true) ~= nil)
	end
end

--
-- Volume 3, the Programmer's Guide, has rules of its own too -- fewer, because
-- the two volumes above it carry the card and the ceilings, and one that is
-- ONLY this volume's: it is the book with no quick-reference chapter, so the
-- shapes of the words nobody else's card carries are written in its appendix and
-- the union's coverage leans on them being there.
--
do
	local vol = volumeById["programmer"]
	check("Volume 3 is the Programmer's Guide",
		vol ~= nil and vol.name == "Programmer's Guide")

	-- 1. The words no other card carries, in their exact shape. Derived from the
	-- other two cards rather than hand-listed: a command Volume 1 or 2 takes onto
	-- its card stops being this volume's to spell, and one they drop becomes it.
	local others = {}
	for vi = 1, #volumes do
		if volumes[vi].id ~= "programmer" then
			local card = chapterTextMatching(volumes[vi].chapters, unpack(REF_TITLES))
			if card ~= nil then others[#others + 1] = card end
		end
	end
	others = table.concat(others, "\n")
	local mine = chapterTextMatching(vol.chapters, unpack(REF_TITLES))
	check("Volume 3 has the chapter its shapes are written in", mine ~= nil)
	local carried = 0
	for name, info in pairs(CeroSecOS.COMMAND_INFO) do
		if string.find(others, info.usage, 1, true) == nil then
			check("Volume 3 spells " .. name .. " exactly, since no other card does: \""
				.. info.usage .. "\"", string.find(mine, info.usage, 1, true) ~= nil)
			carried = carried + 1
		end
	end
	check("and there really are some of those (" .. carried .. ")", carried >= 5)

	-- 2. Every chapter carries its "Classic mistake" box, as Volumes 1 and 2 do.
	for ci = 1, #vol.chapters do
		local ch = vol.chapters[ci]
		local has = false
		for pi = 1, #ch.pages do
			if string.find(ch.pages[pi], "Classic mistake", 1, true) ~= nil then has = true end
		end
		check("Volume 3: " .. ch.title .. " has a Classic mistake box", has)
	end

	-- 3. The two numbers a programmer runs into that are this volume's to state.
	local flat = string.gsub(vol.wholeText, "%s+", " ")
	check("Volume 3 states the job ceiling",
		string.find(flat, "Four jobs is the ceiling", 1, true) ~= nil)
	-- The two parser ceilings, as a PHRASE and not as a bare number: "8" on its
	-- own is a substring of half the numbers on the machine, and this file has been
	-- caught by that before.
	local NUMBER = { [8] = "eight", [16] = "Sixteen" }
	check("Volume 3 states how deep the loops nest and how long a pipeline may be",
		string.find(flat, NUMBER[CeroSecOS.MAX_NEST] ..
			" deep is as far as these nest, and " .. NUMBER[CeroSecOS.MAX_STAGES] ..
			" is as long as a pipeline may be", 1, true) ~= nil)
end

print(count .. " manual checks passed")
