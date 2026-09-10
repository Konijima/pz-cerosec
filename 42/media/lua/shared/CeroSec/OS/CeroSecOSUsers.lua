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
-- see tests/os_test.lua, which fails if a hash takes longer than the budget
-- under lua5.1. Kahlua is several times slower than lua5.1, so the budget is
-- set low enough (a few milliseconds) to stay well under a fifth of a second
-- there, which is the most a login may cost.
CeroSecOS.HASH_ROUNDS = 8000

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
	local n = tonumber(string.sub(short, 1, 8), 16) or 0
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

function CeroSecOS.getUser(state, name)
	if state == nil or state.users == nil or type(name) ~= "string" then return nil end
	return state.users[name]
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

-- The single place a password is written.
function CeroSecOS.setPassword(state, name, password, extra)
	local user = CeroSecOS.getUser(state, name)
	if user == nil then return nil, "no such user" end
	if type(password) ~= "string" then password = "" end
	if #password > CeroSecOS.MAX_PASSWORD then return nil, "password too long" end
	if CeroSecOS.hasControlBytes(password) then return nil, "invalid characters" end
	user.password = CeroSecOS.hashPassword(password, CeroSecOS.newSalt(state, name .. tostring(extra)))
	return true, nil
end

-- A machine saved before this rung carries its passwords in clear. They are
-- hashed in place, with a fresh salt each, so the account keeps working and the
-- cleartext is gone from the next save. Anything already hashed is left alone.
function CeroSecOS.migrateUsers(state)
	if type(state) ~= "table" or type(state.users) ~= "table" then return state end
	for name, user in pairs(state.users) do
		if type(user) == "table" and type(user.password) == "string"
				and CeroSecOS.splitHash(user.password) == nil then
			user.password = CeroSecOS.hashPassword(user.password, CeroSecOS.newSalt(state, name))
		end
	end
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
