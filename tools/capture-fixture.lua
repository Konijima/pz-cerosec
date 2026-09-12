--
-- Capture a save-shape fixture: a whole machine, as the CURRENT code writes it,
-- serialized as a Lua table literal.
--
--   lua5.1 tools/capture-fixture.lua [--engine <dir>] [--out <file>]
--
-- and tools/capture-fixture.sh is the wrapper that names both for the ordinary case.
--
-- WHY a file and not a bench that builds the machine itself. A bench that built its
-- fixture with today's code would be a bench that can only ever test today's shape:
-- the moment the builder is changed the "old" machine changes with it, and the chain
-- is then walking a state the previous release never wrote. A fixture is a
-- photograph -- bytes committed to git by the build that really produced them -- and
-- the only way to get one of an older shape is to run an older build, which is what
-- --engine is for (see docs/RELEASE.md).
--
-- It is NOT part of the mod and is never loaded by the game: it is a lua5.1 script
-- that uses io, os and print, none of which exist under Kahlua. It lives in tools/
-- for exactly that reason.
--
-- What goes in one, and why each piece is there: every one of them is a thing a
-- migration could plausibly break, so the bench that reads the fixture has something
-- to hold the chain to (tests/migrate_test.lua).
--
--   two accounts        /etc/passwd, hashed, one of them an admin
--   a home with work    files, and a script -- a script still RUNS afterwards
--   a cron line         /var/spool/cron/<user>, which is a file with a schedule in it
--   a net record        with an exchange, which is the field the phone wave added
--   a disk in the drive with a label and a file on it
--   two door modules    and a phone book stamp -- item and object modData, which are
--                       not the machine's state and have chains of their own
--

local function argValue(name, fallback)
	for i = 1, #arg do
		if arg[i] == name then return arg[i + 1] end
	end
	return fallback
end

local ENGINE = argValue("--engine", "42/media/lua/shared/CeroSec/OS")
local OUT = argValue("--out", nil)

-- The engine, in the order the game loads it: the loader file first, because it is
-- the one that makes the table (see the head of CeroSecOS.lua).
local FILES = {
	"CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSDev", "CeroSecOSDisk",
	"CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath", "CeroSecOSRadio", "CeroSecOSScript",
	"CeroSecOSShell", "CeroSecOSState", "CeroSecOSSystem", "CeroSecOSUsers", "CeroSecOSVM",
}
for i = 1, #FILES do
	local path = ENGINE .. "/" .. FILES[i] .. ".lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end

-- A fixed clock, so that two captures of one build are the same bytes: an mtime off
-- the wall would make every capture a diff.
local WHEN = 1993 * 0 + 725846400

--
-- The machine
--

local state = CeroSecOS.newState("ksp-front-01")

-- A second account beside the two a machine ships with, written into /etc/passwd the
-- way root would with the editor.
local function addUser(name, password, home, admin)
	local node = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	local text = node.data
	if text ~= "" then text = text .. "\n" end
	local user = CeroSecOS.newUser(name, password or "", home, admin)
	local done, reason = CeroSecOS.setData(state, CeroSecOS.rootSession(),
		CeroSecOS.PASSWD_PATH, text .. CeroSecOS.passwdLine(user), WHEN)
	if done == nil then error("cannot add " .. name .. ": " .. tostring(reason)) end
end
addUser("sam", "letmein", "/home/sam", false)

local function put(path, text)
	local done, reason =
		CeroSecOS.writeFile(state, CeroSecOS.rootSession(), path, text, false, WHEN)
	if done == nil then error("cannot write " .. path .. ": " .. tostring(reason)) end
end

-- sam's home, and something of his in it.
local home = CeroSecOS.systemNode(state, "/home")
home.children.sam = CeroSecOS.newDir("sam", CeroSecOS.HOME_MODE, WHEN)
put("/home/sam/notes.txt", "the generator needs fuel")
put("/home/admin/todo.txt", "check the back door")

-- And a script, which is the piece a migration is most able to break quietly: it is
-- a FILE, and what makes it a program is only that something runs it.
put("/home/admin/count.sh", "echo one\necho two\n")

-- A cron line. The crontab is a file under /var/spool/cron, one per account.
put(CeroSecOS.cronPath("admin"), "*/5 * * * * echo tick\n")

-- The wire, and the telephone exchange beside it -- the field the phone wave added
-- and topped up inline, which is why it is in here.
if CeroSecOS.setNetRecord(state, 10, 4, 17, 555, "Coffee Shop") == nil then
	error("cannot write the net record")
end
CeroSecOS.writeOwnHost(state, WHEN)
CeroSecOS.ensureCallsign(state)

-- A disk in the drive, with a label on the sticker and a file on it.
state.floppy = CeroSecOS.newFloppy("PAYROLL 93")
state.floppy.fs = CeroSecOS.newFloppyRoot("admin", WHEN)
state.floppy.fs.children["pay.txt"] = CeroSecOS.newFile("admin", 644, "sam 40h", WHEN)
state.fdtype = "CeroSec.FloppyBlue"

-- The book of device numbers, which is the machine's own and is NOT the world's: a
-- number is spent for the life of the computer, so nothing is ever renumbered under a
-- player who wrote "echo off > /dev/light3" into a script. Written as the literal
-- SCeroSecDevices.number writes (its head documents the shape), because that file is
-- the server's and does not load without the game.
state.devmap = {
	["light:1024:998:0::0"] = { id = "light0", kind = "light", n = 0, mode = 660 },
	["door:1024:999:0:N:0"] = { id = "door0", kind = "door", n = 0, mode = 660 },
	["lock:1024:999:0:N:0"] = { id = "lock0", kind = "lock", n = 0, mode = 660 },
}

local ok, reason = CeroSecOS.validate(state)
if not ok then error("the machine this built does not validate: " .. tostring(reason)) end

--
-- The item and object namespaces, which are not the machine's state
--
-- Written as the literals an older build wrote, and not built through
-- CeroSecModules/CeroSecPhonebook: those two files require the game's own `require`
-- and are not loadable here. The bench pins the key names against the real modules
-- (tests/migrate_test.lua), so a rename that left these behind goes red there.
--
local modules = {
	{ strike = true, contact = true },
	{ relay = true },
}
local phonebook = { cerosec = { region = { 7, 9 } } }
local diskInHand = { v = CeroSecOS.FLOPPY_VERSION, label = "BACKUP",
	fs = CeroSecOS.newFloppyRoot("sam", WHEN) }

--
-- Serializing
--
-- Deterministic: keys sorted, numbers before strings, so that two captures of one
-- build are one set of bytes and a fixture's diff is a real change.
--

local function quote(s)
	local out = string.gsub(s, "\\", "\\\\")
	out = string.gsub(out, '"', '\\"')
	out = string.gsub(out, "\n", "\\n")
	out = string.gsub(out, "\r", "\\r")
	out = string.gsub(out, "\t", "\\t")
	return '"' .. out .. '"'
end

-- Lua's own words, which are not names. /bin holds a file for every command and four
-- of them -- `false`, `true`, `not`... -- are spelled like keywords, so a bare `false
-- = {` is a syntax error and not a key. Found the hard way: the first capture would
-- not load.
local RESERVED = {}
for word in string.gmatch("and break do else elseif end false for function if in local "
		.. "nil not or repeat return then true until while", "%a+") do
	RESERVED[word] = true
end

local function keyText(k)
	if type(k) == "number" then return "[" .. tostring(k) .. "]" end
	if not RESERVED[k] and string.find(k, "^[A-Za-z_][A-Za-z0-9_]*$") then return k end
	return "[" .. quote(k) .. "]"
end

local function sortedKeys(t)
	local nums, strs = {}, {}
	for k in pairs(t) do
		if type(k) == "number" then nums[#nums + 1] = k
		elseif type(k) == "string" then strs[#strs + 1] = k
		else error("a key of type " .. type(k) .. " is not something a save can hold") end
	end
	table.sort(nums)
	table.sort(strs)
	local out = {}
	for i = 1, #nums do out[#out + 1] = nums[i] end
	for i = 1, #strs do out[#out + 1] = strs[i] end
	return out
end

local write
write = function(value, indent, parts)
	local t = type(value)
	if t == "string" then parts[#parts + 1] = quote(value) return end
	if t == "number" then
		-- Whole numbers as integers: "1" and not "1.0", because that is what the
		-- game's own serializer round-trips and what an older fixture holds.
		if value == math.floor(value) then
			parts[#parts + 1] = string.format("%d", value)
		else
			parts[#parts + 1] = string.format("%.17g", value)
		end
		return
	end
	if t == "boolean" then parts[#parts + 1] = tostring(value) return end
	if t ~= "table" then error(t .. " is not something a save can hold") end
	local keys = sortedKeys(value)
	if #keys == 0 then parts[#parts + 1] = "{}" return end
	parts[#parts + 1] = "{\n"
	local inner = indent .. "\t"
	for i = 1, #keys do
		parts[#parts + 1] = inner .. keyText(keys[i]) .. " = "
		write(value[keys[i]], inner, parts)
		parts[#parts + 1] = ",\n"
	end
	parts[#parts + 1] = indent .. "}"
end

local fixture = {
	v = state.v,
	sysv = state.sysv,
	state = state,
	disk = diskInHand,
	modules = modules,
	phonebook = phonebook,
}

local parts = {}
parts[#parts + 1] = "--\n"
parts[#parts + 1] = "-- A CeroSec save, photographed. STATE_VERSION " .. tostring(state.v)
parts[#parts + 1] = ", SYSTEM_VERSION " .. tostring(state.sysv) .. ".\n"
parts[#parts + 1] = "--\n"
parts[#parts + 1] = "-- Written by tools/capture-fixture.sh and never by hand: it is what a build\n"
parts[#parts + 1] = "-- really wrote, and tests/migrate_test.lua walks it up to whatever the code is\n"
parts[#parts + 1] = "-- now. Do not edit it to make a bench pass -- that is the one thing that would\n"
parts[#parts + 1] = "-- make it worthless.\n"
parts[#parts + 1] = "--\n"
parts[#parts + 1] = "return "
write(fixture, "", parts)
parts[#parts + 1] = "\n"
local text = table.concat(parts)

if OUT == nil then
	io.write(text)
else
	local f, err = io.open(OUT, "w")
	if f == nil then error("cannot write " .. OUT .. ": " .. tostring(err)) end
	f:write(text)
	f:close()
	print("captured STATE_VERSION " .. tostring(state.v) .. " to " .. OUT)
end
