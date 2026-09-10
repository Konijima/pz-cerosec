-- Checks CeroSecManual.lua against the engine it describes. Run from the
-- repo root:
--   lua5.1 tests/manual_test.lua

local OS_DIR = "42/media/lua/shared/CeroSec/OS/"
local OS_FILES = {
	"CeroSecOS", "CeroSecOSFS", "CeroSecOSPath", "CeroSecOSShell",
	"CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers",
}
for i = 1, #OS_FILES do
	local path = OS_DIR .. OS_FILES[i] .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
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
check("has a title", type(CeroSecManual.title) == "string" and CeroSecManual.title ~= "")
check("has an edition", type(CeroSecManual.edition) == "string" and CeroSecManual.edition ~= "")
check("has chapters", type(CeroSecManual.chapters) == "table")

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

		wholeBook[#wholeBook + 1] = page
	end
end
wholeBook = table.concat(wholeBook, "\n")

check("total pages is 45..70 (" .. totalPages .. ")", totalPages >= 45 and totalPages <= 70)

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

-- Command-specific messages that are constant, full lines (no argument
-- baked into the literal), exactly as CeroSecOSShell.lua and
-- SCeroSecSystem.lua produce them.
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
}
for i = 1, #LITERAL_MESSAGES do
	check("error appendix carries \"" .. LITERAL_MESSAGES[i] .. "\"",
		string.find(errText, LITERAL_MESSAGES[i], 1, true) ~= nil)
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

print(count .. " manual checks passed")
