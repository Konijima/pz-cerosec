--
-- CeroSec OS core: users, passwords and login.
--
-- Passwords are stored as a salted, iterated hash and never in clear:
--
--     $cs1$<salt>$<32 hex digits>
--
-- Be honest about what that is. It is not bcrypt, not scrypt, not even SHA-2:
-- it is a few thousand rounds of 32-bit add / multiply / rotate over four
-- lanes, written in the arithmetic Kahlua has (no bit library, no packing,
-- no integer division). Somebody who wants a password out of a save file and is
-- willing to write a cracker will get it. The point is narrower and worth
-- having anyway: reading the save file, or a future /etc/passwd on the machine
-- itself, does not simply *hand over* the passwords, and two accounts with the
-- same password do not look the same.
--
-- checkPassword is still the single place a password is judged and
-- hashPassword the single place one is turned into what is stored, so swapping
-- the construction later is a two-function change.
--

CeroSecOS = CeroSecOS or {}

-- The name of this construction. It is in every stored string, so a later one
-- can be told apart and migrated instead of guessed at.
CeroSecOS.HASH_TAG = "cs1"

-- Rounds of mixing after the input has been absorbed. Chosen by measurement:
-- tests/os_test.lua fails if a hash takes longer than 50 ms under lua5.1, and
-- 4000 rounds measures about 5 ms on an idle machine. Kahlua is several times
-- slower than lua5.1, so that leaves a login well under the fifth of a second
-- that is the most one may cost. The budget is ten times the measurement on
-- purpose: a test that runs on a loaded machine must not go red for it.
CeroSecOS.HASH_ROUNDS = 4000

-- 2^32, and the powers of two the rotation needs. Built once: Kahlua has no
-- bit library, so a rotation is a division and a multiplication, and "^" in
-- the inner loop is not something to bet on.
local M = 4294967296
local POW = {}
for i = 0, 32 do POW[i] = 2 ^ i end

-- Odd 32-bit constants, one per lane. The first is Knuth's golden ratio; the
-- other three are the mixing constants of MurmurHash3. Odd on purpose:
-- multiplication by an odd number is a bijection modulo 2^32, so no round can
-- ever collapse a lane onto fewer values.
local MIX = { 2654435761, 2246822519, 3266489917, 668265263 }

-- Four distinct starting values, so the lanes do not walk in step.
local SEED = { 2166136261, 3323198485, 2654435769, 1103515245 }

local ROT = { 7, 11, 17, 23 }

-- a * b modulo 2^32, without ever asking a double to hold more than it can. A
-- Lua number carries 53 bits of mantissa and a 32-bit product needs 64, so the
-- left operand is split at 16 bits: the high half only matters modulo 2^16.
local function mul(a, b)
	local ah = math.floor(a / 65536)
	local al = a - ah * 65536
	return ((ah * b) % 65536 * 65536 + al * b) % M
end

local HEX = "0123456789abcdef"

local function hex8(n)
	local out = ""
	for _ = 1, 8 do
		local d = n % 16
		out = string.sub(HEX, d + 1, d + 1) .. out
		n = math.floor(n / 16)
	end
	return out
end

local BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"

local function base36(n, digits)
	local out = ""
	for _ = 1, digits do
		local d = n % 36
		out = string.sub(BASE36, d + 1, d + 1) .. out
		n = math.floor(n / 36)
	end
	return out
end

-- The four lanes, stirred by one byte.
local function absorb(l1, l2, l3, l4, b)
	l1 = mul((l1 + b + 1) % M, MIX[1])
	l1 = (l1 % POW[32 - ROT[1]] * POW[ROT[1]] + math.floor(l1 / POW[32 - ROT[1]])) % M
	l2 = mul((l2 + b + 2 + l1) % M, MIX[2])
	l2 = (l2 % POW[32 - ROT[2]] * POW[ROT[2]] + math.floor(l2 / POW[32 - ROT[2]])) % M
	l3 = mul((l3 + b + 3 + l2) % M, MIX[3])
	l3 = (l3 % POW[32 - ROT[3]] * POW[ROT[3]] + math.floor(l3 / POW[32 - ROT[3]])) % M
	l4 = mul((l4 + b + 4 + l3) % M, MIX[4])
	l4 = (l4 % POW[32 - ROT[4]] * POW[ROT[4]] + math.floor(l4 / POW[32 - ROT[4]])) % M
	l1 = (l1 + l4) % M
	return l1, l2, l3, l4
end

-- The mixer, over a string, with a given number of rounds afterwards. Every
-- lane feeds the next and the last feeds the first, so a change anywhere
-- reaches everywhere long before the rounds are up.
local function digest(text, rounds)
	local l1, l2, l3, l4 = SEED[1], SEED[2], SEED[3], SEED[4]
	-- The length goes in first: two strings of different lengths never start
	-- from the same place.
	l1, l2, l3, l4 = absorb(l1, l2, l3, l4, #text % 256)
	for i = 1, #text do
		l1, l2, l3, l4 = absorb(l1, l2, l3, l4, string.byte(text, i))
	end
	for r = 1, rounds do
		l1, l2, l3, l4 = absorb(l1, l2, l3, l4, r % 256)
	end
	return hex8(l1) .. hex8(l2) .. hex8(l3) .. hex8(l4)
end

-- The mixer, in public, under its own name. The same construction and the same
-- function -- not a second one: a mod that hashed its content with one mixer and
-- its passwords with another would be a mod with two answers to "what is a hash
-- here", and the note in the drawer agreeing with the machine on the desk rests
-- on there being one.
--
-- Everything above this line is the password construction and is NOT what this
-- is for: CeroSecContent asks for a few rounds to choose a surname with, and
-- hashPassword asks for four thousand to store a password with. The rounds are
-- the caller's to name, exactly as they already were inside this file.
function CeroSecOS.digest(text, rounds)
	if type(text) ~= "string" then return nil end
	if type(rounds) ~= "number" or rounds < 0 then return nil end
	return digest(text, math.floor(rounds))
end

-- A salt is six base 36 digits: printable, no "$", and short enough that the
-- whole stored string fits a screen line. Six because 36^6 is just under 2^32,
-- so every digit carries something and none is a wasted leading zero.
CeroSecOS.SALT_DIGITS = 6

function CeroSecOS.isValidSalt(salt)
	if type(salt) ~= "string" then return false end
	if #salt < 1 or #salt > 16 then return false end
	return string.find(salt, "[^0-9a-z]") == nil
end

-- A salt that has not been used before, as far as this machine can tell.
--
-- The core has no clock and no random number generator -- it is pure Lua and
-- runs the same under lua5.1 and under Kahlua -- so this is a counter, the
-- machine's own name, and whatever extra the caller passes. The game side
-- passes getTimestampMs(); the engine never requires it, and without it two
-- machines with the same hostname, restarted, can produce the same salt. That
-- is a weaker salt, not a broken one: a salt has to be different, not secret.
CeroSecOS.saltCounter = 0

function CeroSecOS.newSalt(state, extra)
	CeroSecOS.saltCounter = CeroSecOS.saltCounter + 1
	local seed = tostring(CeroSecOS.saltCounter)
	if type(state) == "table" and type(state.hostname) == "string" then
		seed = seed .. "@" .. state.hostname
	end
	if extra ~= nil then seed = seed .. "/" .. tostring(extra) end
	-- Sixteen rounds, not four thousand: this is not the slow part and must not
	-- be, or making a user would cost as much as checking one.
	local short = digest(seed, 16)
	-- hexValue and not tonumber(s, 16): Kahlua gives nil over 0x7fffffff, and
	-- the "or 0" here would have quietly made every second salt the same one.
	local n = CeroSecOS.hexValue(string.sub(short, 1, 8)) or 0
	return base36(n % 2176782336, CeroSecOS.SALT_DIGITS)
end

-- The single place a password becomes what is stored. Returns the whole
-- "$cs1$<salt>$<hash>" string, which is exactly what lands in the user record.
function CeroSecOS.hashPassword(password, salt)
	if type(password) ~= "string" then password = "" end
	if not CeroSecOS.isValidSalt(salt) then salt = "0" end
	return "$" .. CeroSecOS.HASH_TAG .. "$" .. salt .. "$"
		.. digest(salt .. "$" .. password, CeroSecOS.HASH_ROUNDS)
end

-- salt, hash. nil when the string is not one of ours -- a password saved before
-- this rung, or a forged state.
function CeroSecOS.splitHash(stored)
	if type(stored) ~= "string" then return nil end
	local salt, hash = string.match(stored, "^%$" .. CeroSecOS.HASH_TAG .. "%$([0-9a-z]+)%$([0-9a-f]+)$")
	if salt == nil then return nil end
	if not CeroSecOS.isValidSalt(salt) then return nil end
	if #hash ~= 32 then return nil end
	return salt, hash
end

--
-- /etc/passwd
--
-- One account per line, four fields, in the order a Unix passwd has them:
--
--     name:$cs1$<salt>$<hash>:home:admin|user
--
-- The file IS the accounts. There is no table of users beside it and nothing
-- caches a user record across a change to it, so root editing the file with the
-- editor adds, removes and re-homes accounts, and the parser is what the
-- machine believes.
--
-- Parsing is strict and silent: a line that is not exactly four fields, or
-- whose name is not a name, or whose second field is not one of our hashes, or
-- whose home is not an absolute path, or whose last field is neither "admin"
-- nor "user", is skipped. A file that parses to nothing is a machine nobody can
-- log in to -- which is what the BIOS restore is for, and not something to
-- paper over by inventing an account.
--

local function isValidHome(home)
	if type(home) ~= "string" then return false end
	if #home < 1 or #home > 128 then return false end
	if string.sub(home, 1, 1) ~= "/" then return false end
	return string.find(home, "[^A-Za-z0-9._/%-]") == nil
end

-- One line -> a user record, or nil. The four captures are all "no colon", so a
-- line with three fields or with five never matches at all.
function CeroSecOS.parsePasswdLine(line)
	if type(line) ~= "string" then return nil end
	local name, password, home, kind = string.match(line, "^([^:]*):([^:]*):([^:]*):([^:]*)$")
	if name == nil then return nil end
	if not CeroSecOS.isValidName(name) then return nil end
	if CeroSecOS.splitHash(password) == nil then return nil end
	if not isValidHome(home) then return nil end
	if kind ~= "admin" and kind ~= "user" then return nil end
	return { name = name, password = password, home = home, admin = kind == "admin" }
end

-- The record as it is written. The single place a line is built, so what
-- parsePasswdLine reads and what a rewrite produces cannot drift apart.
function CeroSecOS.passwdLine(user)
	local kind = "user"
	if user.admin then kind = "admin" end
	return user.name .. ":" .. user.password .. ":" .. user.home .. ":" .. kind
end

-- text -> users by name, names in the order the file has them. A name that
-- appears twice keeps its FIRST line, the way a lookup down a file does.
function CeroSecOS.parsePasswd(text)
	local users, order = {}, {}
	local lines = CeroSecOS.splitLines(text)
	for i = 1, #lines do
		local user = CeroSecOS.parsePasswdLine(lines[i])
		if user ~= nil and users[user.name] == nil then
			users[user.name] = user
			order[#order + 1] = user.name
		end
	end
	return users, order
end

-- The accounts of a machine, parsed on demand.
--
-- The cache is one slot, and what invalidates it is the file itself: a
-- different node table, or the same one carrying different text. Every write to
-- /etc/passwd goes through setData, which replaces node.data, so there is no
-- write this can miss -- including root saving the file out of the editor,
-- which nothing here is told about. Not in the state: the state is serialized
-- into the save file, and a parsed copy of the accounts sitting next to the
-- file would be a second truth.
CeroSecOS.passwdCache = { node = nil, text = nil, users = {}, order = {} }

function CeroSecOS.readUsers(state)
	local node = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	if node == nil or node.type ~= "file" then return {}, {} end
	local cache = CeroSecOS.passwdCache
	if cache.node ~= node or cache.text ~= node.data then
		local users, order = CeroSecOS.parsePasswd(node.data or "")
		cache.node = node
		cache.text = node.data
		cache.users = users
		cache.order = order
	end
	return cache.users, cache.order
end

function CeroSecOS.getUser(state, name)
	if type(name) ~= "string" then return nil end
	local users = CeroSecOS.readUsers(state)
	return users[name]
end

-- Whether the machine has anybody at all to log in as.
function CeroSecOS.hasUsers(state)
	local _, order = CeroSecOS.readUsers(state)
	return #order > 0
end

-- Longest password the machine will take, in clear. Nothing forces one this
-- long; it is a ceiling on what a client can push through setPassword.
CeroSecOS.MAX_PASSWORD = 32

function CeroSecOS.newUser(name, password, home, admin, salt)
	if salt == nil then salt = CeroSecOS.newSalt(nil, name) end
	return {
		name = name,
		password = CeroSecOS.hashPassword(password or "", salt),
		home = home or "/",
		admin = admin and true or false,
	}
end

-- The single place a password is judged. An empty password is hashed like any
-- other -- it is never a special case in storage -- and an account that ships
-- open is one whose stored hash happens to be the hash of "".
function CeroSecOS.checkPassword(user, password)
	if user == nil then return false end
	local salt = CeroSecOS.splitHash(user.password)
	if salt == nil then return false end
	if type(password) ~= "string" then password = "" end
	return CeroSecOS.hashPassword(password, salt) == user.password
end

-- The whole file, rewritten in one setData: a line is never patched where it
-- lies. So a refusal -- a full disk, a control byte -- leaves /etc/passwd
-- exactly as it was rather than half rewritten, and the write goes through the
-- ordinary filesystem gate like any other, ceilings and printable rule
-- included. The session is root's because the file is root's and mode 600.
function CeroSecOS.writePasswd(state, users, order, name, stored, now)
	local out = {}
	for i = 1, #order do
		local user = users[order[i]]
		if user.name == name then
			out[i] = CeroSecOS.passwdLine({
				name = user.name, password = stored, home = user.home, admin = user.admin,
			})
		else
			out[i] = CeroSecOS.passwdLine(user)
		end
	end
	local done, reason =
		CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.PASSWD_PATH,
			table.concat(out, "\n"), now)
	if done == nil then return nil, reason end
	return true, nil
end

-- The rule for a name the machine will MAKE: a lowercase Unix login, at most
-- MAX_USERNAME long. Deliberately narrower than the parser's, which takes any
-- valid file name: a machine that has been running a while may hold accounts
-- this rung would never have created, and refusing to parse them would be
-- taking somebody's machine away. So this gates useradd and nothing else.
--
-- Every name it accepts is also a valid file name, which is what lets
-- /home/<name> be created for it without a second rule.
CeroSecOS.MAX_USERNAME = 16

function CeroSecOS.isValidUserName(name)
	if type(name) ~= "string" then return false end
	if #name < 1 or #name > CeroSecOS.MAX_USERNAME then return false end
	if string.find(name, "^[a-z]") == nil then return false end
	return string.find(name, "[^a-z0-9_%-]") == nil
end

-- The file, replaced whole, through the ordinary filesystem gate: the ceilings
-- and the printable rule apply to the machine's own writes exactly as they
-- apply to a player's, and a refusal leaves /etc/passwd byte for byte as it was.
local function writePasswdText(state, text, now)
	local done, reason =
		CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.PASSWD_PATH, text, now)
	if done == nil then return nil, reason end
	return true, nil
end

-- A new account, appended, with an EMPTY password -- which is not a special
-- case in storage: what is written is the hash of "", with a salt of its own,
-- exactly like the accounts a fresh machine ships with.
--
-- Appended and not rewritten: the lines already in the file are left as they
-- lie, comments and unparseable lines included. Only passwd rewrites the file
-- from what it parsed, and only because it has to touch a line in the middle.
function CeroSecOS.addUser(state, name, home, admin, extra, now)
	if CeroSecOS.getUser(state, name) ~= nil then return nil, "already exists" end
	local node = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	if node == nil or node.type ~= "file" then return nil, "no such file" end
	local user = CeroSecOS.newUser(name, "", home, admin,
		CeroSecOS.newSalt(state, name .. tostring(extra)))
	local text = node.data or ""
	if text ~= "" then text = text .. "\n" end
	return writePasswdText(state, text .. CeroSecOS.passwdLine(user), now)
end

-- Every line that names this account, taken out; every other line kept exactly
-- as it lies. A name that somehow has two lines loses both -- half an account
-- is worse than none.
function CeroSecOS.removeUser(state, name, now)
	local node = CeroSecOS.systemNode(state, CeroSecOS.PASSWD_PATH)
	if node == nil or node.type ~= "file" then return nil, "no such file" end
	local lines = CeroSecOS.splitLines(node.data or "")
	local out = {}
	for i = 1, #lines do
		local user = CeroSecOS.parsePasswdLine(lines[i])
		if user == nil or user.name ~= name then out[#out + 1] = lines[i] end
	end
	return writePasswdText(state, table.concat(out, "\n"), now)
end

-- The single place the fourth field is written after the line exists, and the
-- only thing that writes it is `usermod -G`: the field says whether the account
-- is in `wheel` (see the head of the account commands in CeroSecOSShell.lua), so
-- the command that moves an account in or out of that group is the command that
-- moves it. The file is rewritten from what was parsed, exactly as passwd does
-- it, because the line is in the middle.
function CeroSecOS.setAdmin(state, name, admin, now)
	local users, order = CeroSecOS.readUsers(state)
	local user = users[name]
	if user == nil then return nil, "no such user" end
	local out = {}
	for i = 1, #order do
		local one = users[order[i]]
		if one.name == name then
			out[i] = CeroSecOS.passwdLine({
				name = one.name, password = one.password, home = one.home,
				admin = admin and true or false,
			})
		else
			out[i] = CeroSecOS.passwdLine(one)
		end
	end
	local done, reason =
		CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.PASSWD_PATH,
			table.concat(out, "\n"), now)
	if done == nil then return nil, reason end
	return true, nil
end

-- The single place a password is written.
function CeroSecOS.setPassword(state, name, password, extra, now)
	local users, order = CeroSecOS.readUsers(state)
	local user = users[name]
	if user == nil then return nil, "no such user" end
	if type(password) ~= "string" then password = "" end
	if #password > CeroSecOS.MAX_PASSWORD then return nil, "password too long" end
	if CeroSecOS.hasControlBytes(password) then return nil, "invalid characters" end
	local stored = CeroSecOS.hashPassword(password, CeroSecOS.newSalt(state, name .. tostring(extra)))
	return CeroSecOS.writePasswd(state, users, order, name, stored, now)
end

-- The two accounts a machine ships with, as the file has them. Both open: an
-- account that ships open is one whose stored hash is the hash of "".
function CeroSecOS.defaultPasswd()
	return CeroSecOS.passwdLine(CeroSecOS.newUser("root", "", "/root", true))
		.. "\n" .. CeroSecOS.passwdLine(CeroSecOS.newUser("admin", "", "/home/admin", false))
end

-- A machine saved before /etc/passwd carries its accounts in a table on the
-- state, and one saved before that carries their passwords in clear. Both are
-- repaired here, once, and the table is then dropped: the file is the source of
-- accounts and two of them would be one too many.
--
-- The file wins. A state that somehow has both keeps the file untouched and
-- only loses the table -- what is on the disk is what the machine has been
-- running on.
function CeroSecOS.migrateUsers(state)
	if type(state) ~= "table" then return state end
	local users = state.users
	if type(users) ~= "table" then return state end

	-- Cleartext first: what goes into the file is only ever a hash.
	local names = {}
	for name, user in pairs(users) do
		if type(name) == "string" and type(user) == "table" then
			if type(user.password) ~= "string" or CeroSecOS.splitHash(user.password) == nil then
				local clear = user.password
				if type(clear) ~= "string" then clear = "" end
				user.password = CeroSecOS.hashPassword(clear, CeroSecOS.newSalt(state, name))
			end
			names[#names + 1] = name
		end
	end
	-- pairs() has no order and the file must come out the same every time.
	table.sort(names)

	if not CeroSecOS.hasUsers(state) then
		local lines = {}
		for i = 1, #names do
			local user = users[names[i]]
			local home = user.home
			if type(home) ~= "string" then home = "/" end
			if CeroSecOS.isValidName(names[i]) then
				lines[#lines + 1] = CeroSecOS.passwdLine({
					name = names[i], password = user.password, home = home,
					admin = user.admin and true or false,
				})
			end
		end
		CeroSecOS.ensureSystemDir(state, "etc")
		local etc = CeroSecOS.systemNode(state, CeroSecOS.ETC_PATH)
		etc.children.passwd =
			CeroSecOS.newFile("root", CeroSecOS.PASSWD_MODE, table.concat(lines, "\n"))
	end

	-- A machine converted from a users table has never had a /bin either: it was
	-- made before there were executables to put in one. Filling it here is what
	-- keeps such a save booting straight to its login prompt instead of meeting
	-- a BIOS that thinks its disk was wiped. Damage done in the game is a
	-- different thing and still goes through the restore.
	CeroSecOS.ensureSystemDir(state, "bin")
	CeroSecOS.fillBin(CeroSecOS.systemNode(state, CeroSecOS.BIN_PATH))

	state.users = nil
	return state
end

-- session, reason. A session is a runtime object: the terminal window owns it
-- and it is never written into the state.
function CeroSecOS.login(state, name, password)
	local user = CeroSecOS.getUser(state, name)
	if user == nil then return nil, "no such user" end
	if not CeroSecOS.checkPassword(user, password) then return nil, "wrong password" end
	return { user = user.name, cwd = user.home or "/" }, nil
end

--
-- Who is at the glass
--
-- A session says who a command RUNS as. That is not always who is logged in:
-- sudo runs on a session of root's while the account at the keyboard is still
-- the one that typed the line, and a command that has to know which of the two
-- it is asking about must not have to guess. So a session carries `login`, the
-- console's own user, and it travels into every borrowed session -- sudo's, and
-- a chain that carries sudo's authority.
--
-- A session without one is its own login, which is what every session the core
-- makes for itself is.
function CeroSecOS.loginOf(session)
	if type(session) ~= "table" then return nil end
	if type(session.login) == "string" then return session.login end
	return CeroSecOS.userOf(session)
end

-- How deep su may go. The console keeps a stack of who it was before each
-- switch and `exit` pops it, so this is a ceiling on a thing that is saved with
-- the machine and on the number of exits it takes to get out of it.
CeroSecOS.SU_MAX = 4

-- A copy of that stack, entry by entry. What a borrowed session is given: it may
-- READ who the glass would come back to -- userdel refuses to take one of them
-- away -- and anything it pushes or pops dies with the command.
function CeroSecOS.copyStack(stack)
	if type(stack) ~= "table" then return nil end
	local out = {}
	for i = 1, #stack do
		local entry = stack[i]
		if type(entry) == "table" and type(entry.user) == "string" then
			local cwd = "/"
			if type(entry.cwd) == "string" then cwd = entry.cwd end
			out[#out + 1] = { user = entry.user, cwd = cwd }
		end
	end
	return out
end

-- Is this account the one at the glass, or one the glass would come back to?
-- Both count: `exit` pops back to the users under the stack, and popping back
-- to an account that is no longer in /etc/passwd is a session nobody is in.
function CeroSecOS.isLoggedIn(session, name)
	if type(session) ~= "table" or type(name) ~= "string" then return false end
	if CeroSecOS.loginOf(session) == name then return true end
	local stack = session.stack
	if type(stack) ~= "table" then return false end
	for i = 1, #stack do
		local entry = stack[i]
		if type(entry) == "table" and entry.user == name then return true end
	end
	return false
end

--
-- /etc/sudoers
--
-- Who may run a command as root without being root. One name a line:
--
--     admin
--     kate NOPASSWD
--     %wheel
--
-- A name with a "%" in front of it is a GROUP, which is sudo's own syntax and
-- has been since the tool was published: every account in that group may run a
-- command as root. The shipped file carries `%wheel`, so putting somebody in
-- wheel is what makes him an administrator on this machine -- which is 4.4BSD's
-- rule for `su` and the 1993 answer to the question `adduser -a` used to pretend
-- to answer.
--
-- The file IS the list, exactly as /etc/passwd is the accounts: there is no
-- table beside it, nothing caches across a change to it, and root editing it
-- with the editor changes who may sudo. Owner root, mode 440.
--
-- Parsing is strict and silent, like the passwd parser. A blank line and a line
-- whose first non-blank character is "#" are comments. Anything else is a name
-- or a %group, optionally followed by the single word NOPASSWD, and a line that
-- is not that is skipped -- so a typo takes one name off the list and never puts
-- a wrong one on it.
--

local function trim(s)
	local i, j = 1, #s
	while i <= j do
		local c = string.sub(s, i, i)
		if c ~= " " and c ~= "\t" then break end
		i = i + 1
	end
	while j >= i do
		local c = string.sub(s, j, j)
		if c ~= " " and c ~= "\t" then break end
		j = j - 1
	end
	return string.sub(s, i, j)
end

-- One line -> { name, group, nopasswd }, or nil. `name` is the word exactly as
-- the file has it, "%" and all, because that is what a rewrite has to put back;
-- `group` is the name behind the "%" and is nil on a line that names an account.
local function sudoersWord(word)
	if type(word) ~= "string" or word == "" then return nil end
	if string.sub(word, 1, 1) ~= "%" then
		if not CeroSecOS.isValidName(word) then return nil end
		return word, nil
	end
	local group = string.sub(word, 2)
	if not CeroSecOS.isValidName(group) then return nil end
	return word, group
end

function CeroSecOS.parseSudoersLine(line)
	if type(line) ~= "string" then return nil end
	local body = trim(line)
	if body == "" then return nil end
	if string.sub(body, 1, 1) == "#" then return nil end

	local one = string.match(body, "^([^ \t]+)$")
	if one ~= nil then
		local name, group = sudoersWord(one)
		if name == nil then return nil end
		return { name = name, group = group, nopasswd = false }
	end

	local word, flag = string.match(body, "^([^ \t]+)[ \t]+([^ \t]+)$")
	if word == nil then return nil end
	local name, group = sudoersWord(word)
	if name == nil then return nil end
	if flag ~= "NOPASSWD" then return nil end
	return { name = name, group = group, nopasswd = true }
end

-- text -> entries by name, names in the order the file has them. A name that
-- appears twice keeps its FIRST line, the way a lookup down a file does.
function CeroSecOS.parseSudoers(text)
	local entries, order = {}, {}
	local lines = CeroSecOS.splitLines(text)
	for i = 1, #lines do
		local entry = CeroSecOS.parseSudoersLine(lines[i])
		if entry ~= nil and entries[entry.name] == nil then
			entries[entry.name] = entry
			order[#order + 1] = entry.name
		end
	end
	return entries, order
end

-- The same one-slot, content-keyed cache the passwd parser has: the file is the
-- truth, and what makes the answer stale is the file changing.
CeroSecOS.sudoersCache = { node = nil, text = nil, entries = {}, order = {} }

function CeroSecOS.readSudoers(state)
	local node = CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH)
	if node == nil or node.type ~= "file" then return {}, {} end
	local cache = CeroSecOS.sudoersCache
	if cache.node ~= node or cache.text ~= node.data then
		local entries, order = CeroSecOS.parseSudoers(node.data or "")
		cache.node = node
		cache.text = node.data
		cache.entries = entries
		cache.order = order
	end
	return cache.entries, cache.order
end

-- The entry for one account, or nil when it is not in the file. A machine with
-- no /etc/sudoers at all is a machine where nobody may sudo, which is the
-- honest answer for a file that says who may.
--
-- Two ways to be in it and the FIRST line that matches wins, which is the rule
-- this file already runs on and the rule a lookup down a file has: a line with
-- the account's own name, or a `%group` line naming a group it is in. So a
-- `kate NOPASSWD` above `%wheel` is kate not being asked, and the same two lines
-- the other way round are kate being asked like the rest of the group.
--
-- The group test is the FILE's -- a primary group or a line in /etc/group -- and
-- deliberately not CeroSecOS.inGroup, which mirrors this very file for the group
-- called "sudo": a `%sudo` line read through that one would ask itself who may
-- sudo and never come back.
function CeroSecOS.sudoer(state, name)
	if type(name) ~= "string" then return nil end
	local entries, order = CeroSecOS.readSudoers(state)
	for i = 1, #order do
		local entry = entries[order[i]]
		if entry.group == nil then
			if entry.name == name then return entry end
		elseif CeroSecOS.inGroupFile(state, name, entry.group) then
			return entry
		end
	end
	return nil
end

-- Every line that names this account, taken out; every other line kept exactly
-- as it lies, comments included. A machine with no /etc/sudoers at all has
-- nothing to take out and says so by succeeding: it is a file that says who
-- may, and a missing one says nobody.
function CeroSecOS.removeSudoer(state, name, now)
	local node = CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH)
	if node == nil or node.type ~= "file" then return true, nil end
	local lines = CeroSecOS.splitLines(node.data or "")
	local out, dropped = {}, false
	for i = 1, #lines do
		local entry = CeroSecOS.parseSudoersLine(lines[i])
		if entry ~= nil and entry.name == name then
			dropped = true
		else
			out[#out + 1] = lines[i]
		end
	end
	-- Nothing to do is not a write: the file keeps its timestamp.
	if not dropped then return true, nil end
	local done, reason = CeroSecOS.setData(state, CeroSecOS.rootSession(),
		CeroSecOS.SUDOERS_PATH, table.concat(out, "\n"), now)
	if done == nil then return nil, reason end
	return true, nil
end

-- What a machine ships with: the one non-root account by name, the wheel group
-- by group, and both are asked for a password. An open account plus a
-- passwordless sudo would make root free for whoever walks up, and the accounts
-- ship open.
--
-- `%wheel` is what makes `useradd -G wheel bob` mean something: the group ships
-- EMPTY, so the shipped machine is exactly the machine it was -- admin may sudo
-- because his name is here -- and an administrator who puts somebody in wheel has
-- given him root without editing this file at all.
function CeroSecOS.defaultSudoers()
	return "# who may run a command as root, and whether he is asked for his password\n"
		.. "# a bare word is an account; %word is a group -- 4.4BSD gates su on wheel\n"
		.. "%" .. CeroSecOS.WHEEL_GROUP .. "\n"
		.. "admin"
end

--
-- /etc/group
--
-- Who shares files with whom. One group a line, the name and its members:
--
--     root:
--     sudo:admin
--     users:admin,bob
--
-- The file IS the groups, exactly as /etc/passwd is the accounts: nothing
-- caches across a change to it, and root editing it with the editor changes who
-- may read whose files. Owner root, mode 644 -- there is no secret in it, and
-- `groups` answers about anybody.
--
-- Parsing is strict and silent, like the other two parsers. A blank line and a
-- line whose first non-blank character is "#" are comments. Anything else is
-- exactly one colon, a valid name in front of it, and behind it a possibly
-- empty list of valid names separated by commas -- a line that is not that is
-- skipped, so a typo takes one group off the list and never puts a wrong one
-- on it. A name that appears twice keeps its FIRST line, the way a lookup down
-- a file does.
--
-- Every account is a member of a group of its OWN NAME whether the file says so
-- or not: that is its primary group, the one a file it makes belongs to, and it
-- needs no line. useradd writes none.
--

-- One line -> { name, members, set }, or nil. `set` is the members again, by
-- name, because membership is asked far more often than it is listed.
function CeroSecOS.parseGroupLine(line)
	if type(line) ~= "string" then return nil end
	local body = trim(line)
	if body == "" then return nil end
	if string.sub(body, 1, 1) == "#" then return nil end

	local name, rest = string.match(body, "^([^:]*):([^:]*)$")
	if name == nil then return nil end
	if not CeroSecOS.isValidName(name) then return nil end

	local members, set = {}, {}
	if rest ~= "" then
		-- Split by hand rather than by gmatch: an empty field between two
		-- commas has to be seen, and a pattern that matches runs of non-commas
		-- would silently skip it.
		local start = 1
		while true do
			local p = string.find(rest, ",", start, true)
			local piece
			if p == nil then
				piece = string.sub(rest, start)
			else
				piece = string.sub(rest, start, p - 1)
			end
			if not CeroSecOS.isValidName(piece) then return nil end
			if set[piece] == nil then
				set[piece] = true
				members[#members + 1] = piece
			end
			if p == nil then break end
			start = p + 1
		end
	end
	return { name = name, members = members, set = set }
end

-- The record as it is written. The single place a line is built, so what
-- parseGroupLine reads and what a rewrite produces cannot drift apart.
function CeroSecOS.groupLine(group)
	return group.name .. ":" .. table.concat(group.members or {}, ",")
end

-- text -> groups by name, names in the order the file has them.
function CeroSecOS.parseGroup(text)
	local groups, order = {}, {}
	local lines = CeroSecOS.splitLines(text)
	for i = 1, #lines do
		local group = CeroSecOS.parseGroupLine(lines[i])
		if group ~= nil and groups[group.name] == nil then
			groups[group.name] = group
			order[#order + 1] = group.name
		end
	end
	return groups, order
end

-- The same one-slot, content-keyed cache the other two parsers have: the file
-- is the truth, and what makes the answer stale is the file changing.
CeroSecOS.groupCache = { node = nil, text = nil, groups = {}, order = {} }

function CeroSecOS.readGroups(state)
	local node = CeroSecOS.systemNode(state, CeroSecOS.GROUP_PATH)
	if node == nil or node.type ~= "file" then return {}, {} end
	local cache = CeroSecOS.groupCache
	if cache.node ~= node or cache.text ~= node.data then
		local groups, order = CeroSecOS.parseGroup(node.data or "")
		cache.node = node
		cache.text = node.data
		cache.groups = groups
		cache.order = order
	end
	return cache.groups, cache.order
end

-- Is there such a group? A line in the file is one, and so is an account: every
-- account carries a primary group of its own name that no line has to declare,
-- and chgrp takes it.
function CeroSecOS.groupExists(state, name)
	if type(name) ~= "string" then return false end
	local groups = CeroSecOS.readGroups(state)
	if groups[name] ~= nil then return true end
	return CeroSecOS.getUser(state, name) ~= nil
end

-- Is this account in this group? Three ways, and root is not one of them: root
-- walks through the bits in CeroSecOS.can before this is ever asked.
--
--   the primary group -- bob is in group bob, always;
--   a line in /etc/group that names him;
--   /etc/sudoers, for the group "sudo" alone. That file is the authority on
--   who may become root, and the sudo GROUP mirrors it rather than competing
--   with it -- which is what makes crw-rw----  root  sudo on a light switch
--   mean "whoever may sudo may throw it", with no sudo typed.
function CeroSecOS.inGroup(state, user, group)
	if CeroSecOS.inGroupFile(state, user, group) then return true end
	if group == "sudo" and CeroSecOS.sudoer(state, user) ~= nil then return true end
	return false
end

-- The first two ways on their own: what /etc/passwd and /etc/group say, with no
-- glance at /etc/sudoers. This is the half CeroSecOS.sudoer asks, because that
-- one is what the third way reads -- a `%sudo` line answered through inGroup
-- above would be the sudoers file asking itself who may sudo.
function CeroSecOS.inGroupFile(state, user, group)
	if type(user) ~= "string" or type(group) ~= "string" then return false end
	if user == group then return true end
	local groups = CeroSecOS.readGroups(state)
	local entry = groups[group]
	return entry ~= nil and entry.set[user] == true
end

-- Every group an account is in, in the order `groups` and `id` print them: the
-- primary first, then the file's own order, then sudo when /etc/sudoers is what
-- puts him there.
function CeroSecOS.groupsOf(state, name)
	local out, seen = {}, {}
	if type(name) ~= "string" then return out end
	out[1] = name
	seen[name] = true
	local groups, order = CeroSecOS.readGroups(state)
	for i = 1, #order do
		local entry = groups[order[i]]
		if entry.set[name] and not seen[entry.name] then
			seen[entry.name] = true
			out[#out + 1] = entry.name
		end
	end
	if not seen.sudo and CeroSecOS.sudoer(state, name) ~= nil then
		out[#out + 1] = "sudo"
	end
	return out
end

-- The group a node belongs to. Absent is the owner's own name: every node of
-- every machine saved before this build has none, and validate accepts them, so
-- nothing anywhere may read node.group raw.
function CeroSecOS.groupOf(node)
	if type(node) ~= "table" then return "" end
	if type(node.group) == "string" then return node.group end
	if type(node.owner) == "string" then return node.owner end
	return ""
end

-- The rule for a group name the machine will MAKE, and it is the rule for an
-- account name: the two share a namespace -- every account has a group of its
-- own name -- so a group nobody could ever have as a primary would be a trap.
function CeroSecOS.isValidGroupName(name)
	return CeroSecOS.isValidUserName(name)
end

-- The file, replaced whole, through the ordinary filesystem gate.
local function writeGroupText(state, text, now)
	local done, reason =
		CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.GROUP_PATH, text, now)
	if done == nil then return nil, reason end
	return true, nil
end

-- A new group, appended with no members. The lines already in the file are left
-- exactly as they lie, comments and unparseable lines included.
function CeroSecOS.addGroup(state, name, now)
	if CeroSecOS.groupExists(state, name) then return nil, "already exists" end
	local node = CeroSecOS.systemNode(state, CeroSecOS.GROUP_PATH)
	if node == nil or node.type ~= "file" then return nil, "no such file" end
	local text = node.data or ""
	if text ~= "" then text = text .. "\n" end
	return writeGroupText(state, text .. CeroSecOS.groupLine({ name = name, members = {} }), now)
end

-- Every line that names this group, taken out; every other line kept exactly as
-- it lies. Files still carrying the name are LEFT carrying it: a dangling group
-- is the truth about them, and `ls -l` says so.
function CeroSecOS.removeGroup(state, name, now)
	local node = CeroSecOS.systemNode(state, CeroSecOS.GROUP_PATH)
	if node == nil or node.type ~= "file" then return nil, "no such file" end
	local lines = CeroSecOS.splitLines(node.data or "")
	local out = {}
	for i = 1, #lines do
		local group = CeroSecOS.parseGroupLine(lines[i])
		if group == nil or group.name ~= name then out[#out + 1] = lines[i] end
	end
	return writeGroupText(state, table.concat(out, "\n"), now)
end

-- Add or drop one member of one group. The line is rewritten where it lies and
-- every other line is kept as it is; a change that would leave the line exactly
-- as it was is not a write at all, so the file keeps its timestamp.
-- true, reason -- and "not a member" / "already a member" are refusals, not
-- silences: gpasswd is typed by hand and a no-op that says nothing reads as a
-- change that happened.
function CeroSecOS.setGroupMember(state, name, group, member, now)
	local node = CeroSecOS.systemNode(state, CeroSecOS.GROUP_PATH)
	if node == nil or node.type ~= "file" then return nil, "no such file" end
	local lines = CeroSecOS.splitLines(node.data or "")
	local out, found = {}, false
	for i = 1, #lines do
		local entry = CeroSecOS.parseGroupLine(lines[i])
		-- Only the FIRST line with this name, which is the only one a lookup
		-- down the file ever sees.
		if entry ~= nil and entry.name == group and not found then
			found = true
			local members = {}
			for j = 1, #entry.members do
				if entry.members[j] ~= name then members[#members + 1] = entry.members[j] end
			end
			if member then
				if entry.set[name] then return nil, "already a member" end
				members[#members + 1] = name
			elseif not entry.set[name] then
				return nil, "not a member"
			end
			out[#out + 1] = CeroSecOS.groupLine({ name = group, members = members })
		else
			out[#out + 1] = lines[i]
		end
	end
	if not found then return nil, "no such group" end
	return writeGroupText(state, table.concat(out, "\n"), now)
end

-- Every line naming this account as a member, rewritten without it; every other
-- line kept exactly as it lies. What `userdel` sweeps: a name left in a group is
-- a share waiting for whoever is given that name next, and with `%wheel` in
-- /etc/sudoers a name left in wheel is root waiting for him.
--
-- One write for the whole file rather than one per group, because the ceilings
-- are paid per write and an account in four groups must not be four chances of a
-- full disk.
function CeroSecOS.removeGroupMember(state, name, now)
	local node = CeroSecOS.systemNode(state, CeroSecOS.GROUP_PATH)
	if node == nil or node.type ~= "file" then return true, nil end
	local lines = CeroSecOS.splitLines(node.data or "")
	local out, dropped = {}, false
	for i = 1, #lines do
		local entry = CeroSecOS.parseGroupLine(lines[i])
		if entry ~= nil and entry.set[name] then
			dropped = true
			local members = {}
			for j = 1, #entry.members do
				if entry.members[j] ~= name then members[#members + 1] = entry.members[j] end
			end
			out[#out + 1] = CeroSecOS.groupLine({ name = entry.name, members = members })
		else
			out[#out + 1] = lines[i]
		end
	end
	-- Nothing to do is not a write: the file keeps its timestamp.
	if not dropped then return true, nil end
	return writeGroupText(state, table.concat(out, "\n"), now)
end

-- What a machine ships with. root's own group, empty; wheel, empty, which is
-- what /etc/sudoers grants and what an account is put in to be made an
-- administrator; the group the devices belong to, mirroring the shipped
-- /etc/sudoers; and the one an account joins to share a file with the next
-- survivor who sits down.
--
-- wheel ships with nobody in it on purpose. The shipped `admin` account may sudo
-- because /etc/sudoers names it, exactly as it always did, and a shipped machine
-- is therefore the machine it was; wheel is the door an administrator opens for
-- somebody else.
function CeroSecOS.defaultGroup()
	return "# name:member,member,... -- one group a line\n"
		.. "# every account is also in a group of its own name\n"
		.. "root:\n"
		.. "sudo:admin\n"
		.. "users:admin\n"
		.. CeroSecOS.WHEEL_GROUP .. ":"
end
