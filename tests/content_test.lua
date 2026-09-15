-- Unit tests for the world content: the derivation, the profiles, the disk
-- catalogue and every script the mod ships. Run from the repo root:
--   lua5.1 tests/content_test.lua
--
-- WHAT THIS BENCH IS FOR, in one sentence: a profile is loot, and loot that can
-- crash a machine or fill a disk is loot that breaks a save. So every profile is
-- built on a fresh machine, every shipped script is RUN on it, and the machine is
-- handed to the engine's own boot gate afterwards.
--
-- No game under it and no fake world either. What decides which profile a machine
-- gets is two strings -- the premises' name and the room's -- and
-- CeroSecContent.profileFor is a pure function of them, which is the seam that
-- lets this bench ask every question without a square anywhere. The world half --
-- that the two strings come off the right square, and that turnOn is the one
-- moment prefill runs -- is tests/window_test.lua's and docs/PARCOURS-TEST.md's.

local DIR = "42/media/lua/shared/CeroSec/OS/"
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
do
	local path = "42/media/lua/shared/CeroSec/CeroSecContent.lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end
-- The self-test, for the one string section 7c needs out of it: the text and the
-- salt the diagnostics floppy hashes. Asking it rather than writing them down
-- again is the whole point -- the number baked into the script has to be the
-- engine's answer to THESE two, and a bench with its own copy of them would be a
-- bench that proved a different question.
do
	local path = "42/media/lua/shared/CeroSec/CeroSecSelfTest.lua"
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end

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

-- Two secrets, and they are written down rather than rolled: a bench whose
-- inputs are random is a bench that is red on somebody else's machine and green
-- on this one.
local SECRET_A = "0123456789abcdef"
local SECRET_B = "fedcba9876543210"

-- The default save's first morning: 1993-07-09 09:00. Passed in exactly as the
-- server passes it (SCeroSecObject:startTime), so every date this bench reads is
-- a date a real machine would carry.
local START = CeroSecOS.timeFromParts(1993, 7, 9, 9, 0, 0)

local function opts(secret, overrides)
	local o = {
		secret = secret, b1 = 12, b2 = 34, x = 8130, y = 9254, z = 0,
		premises = nil, room = nil, start = START, now = START,
	}
	if overrides ~= nil then
		for k, v in pairs(overrides) do o[k] = v end
	end
	return o
end

-- Every node of a filesystem, as path -> node, so a bench can ask "is it there"
-- and "how big is it" without walking the tree four times.
local function walk(node, at, out)
	out = out or {}
	at = at or ""
	out[at == "" and "/" or at] = node
	if node.type ~= "dir" or type(node.children) ~= "table" then return out end
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do
		walk(node.children[names[i]], at .. "/" .. names[i], out)
	end
	return out
end

--
-- 1. The derivation
--

do
	check("a 16 hex digit string is a secret", CeroSecContent.isSecret(SECRET_A))
	check("15 digits is not", not CeroSecContent.isSecret("0123456789abcde"))
	check("17 digits is not", not CeroSecContent.isSecret("0123456789abcdef0"))
	check("upper case is not", not CeroSecContent.isSecret("0123456789ABCDEF"))
	check("a number is not", not CeroSecContent.isSecret(1234))

	local one = CeroSecContent.derive(SECRET_A, "root.12.34")
	eq("a hash is 32 hex digits", #one, 32)
	check("and nothing else", string.find(one, "[^0-9a-f]") == nil)
	eq("the same question twice is the same answer", one,
		CeroSecContent.derive(SECRET_A, "root.12.34"))
	check("another secret is another answer",
		CeroSecContent.derive(SECRET_B, "root.12.34") ~= one)
	check("another key is another answer",
		CeroSecContent.derive(SECRET_A, "root.12.35") ~= one)

	-- The separator rule, which is what stops two questions spelling one string.
	eq("a key with a separator in it is refused",
		CeroSecContent.derive(SECRET_A, "root/12"), nil)
	eq("an empty key is refused", CeroSecContent.derive(SECRET_A, ""), nil)
	eq("junk for a secret is refused", CeroSecContent.derive("x", "root.1"), nil)

	-- And the key builder is what makes sure nothing can smuggle one in.
	eq("a key is joined with dots", CeroSecContent.key("m", 1, 2), "m.1.2")
	eq("a name with a slash in it loses the slash",
		CeroSecContent.key("Coffee/Shop"), "coffeeshop")
	eq("a name of nothing but punctuation becomes a dash",
		CeroSecContent.key("///"), "-")
	check("and the key it makes is always usable",
		CeroSecContent.derive(SECRET_A, CeroSecContent.key("Coffee/Shop", 1)) ~= nil)

	-- A number in range, every time, over a long walk: a modulo that came out as
	-- 0 or as n + 1 would be an index off the end of a list of names.
	local lo, hi = 99, 0
	for i = 1, 2000 do
		local n = CeroSecContent.number(SECRET_A, CeroSecContent.key("n", i), 34)
		check("number " .. i .. " is in 1..34", n >= 1 and n <= 34)
		if n < lo then lo = n end
		if n > hi then hi = n end
	end
	eq("and the bottom of the range is reached", lo, 1)
	eq("and the top of it is reached", hi, 34)
	eq("a list of one always answers one",
		CeroSecContent.number(SECRET_A, "k", 1), 1)
	eq("a range of nothing is refused", CeroSecContent.number(SECRET_A, "k", 0), nil)

	-- chance, at both ends and in the middle.
	check("a chance of 100 always comes in",
		CeroSecContent.chance(SECRET_A, "c", 100))
	check("a chance of 0 never does",
		not CeroSecContent.chance(SECRET_A, "c", 0))
	local hits = 0
	for i = 1, 1000 do
		if CeroSecContent.chance(SECRET_A, CeroSecContent.key("c", i), 50) then
			hits = hits + 1
		end
	end
	check("a chance of 50 comes in about half the time (" .. hits .. ")",
		hits > 400 and hits < 600)
end

--
-- 2. The names and the passwords
--
-- Everything generated has to be something the machine itself will take: a login
-- goes into /etc/passwd and a line that will not parse is an account nobody can
-- log in to, and a password goes through `passwd`'s own two rules.
--

do
	for i = 1, 500 do
		local key = CeroSecContent.key("u", i)
		local login = CeroSecContent.login(SECRET_A, key)
		check("login " .. i .. ' ("' .. login .. '") is a valid user name',
			CeroSecOS.isValidUserName(login))
		-- And it parses back off a passwd line, which is the real test: a name the
		-- validator likes but the parser drops is an account that vanishes on load.
		local user = CeroSecOS.newUser(login, "x", "/home/" .. login, false)
		local parsed = CeroSecOS.parsePasswdLine(CeroSecOS.passwdLine(user))
		check("login " .. i .. " survives a passwd line", parsed ~= nil)
		eq("login " .. i .. " comes back", parsed.name, login)

		local password = CeroSecContent.password(SECRET_A, key)
		check("password " .. i .. " is a string", type(password) == "string")
		check("password " .. i .. " is not empty", #password > 0)
		check("password " .. i .. " is inside MAX_PASSWORD (" .. #password .. ")",
			#password <= CeroSecOS.MAX_PASSWORD)
		check("password " .. i .. " carries no control byte",
			not CeroSecOS.hasControlBytes(password))
		-- Typeable at the machine's own keyboard, which is the rule nobody writes
		-- down: a password with a character the terminal cannot send is a password
		-- nobody can get in with.
		check("password " .. i .. ' ("' .. password .. '") is typeable',
			string.find(password, "^[a-z0-9]+$") ~= nil)

		local real = CeroSecContent.realName(SECRET_A, key)
		check("real name " .. i .. ' ("' .. real .. '") is two capitalised words',
			string.find(real, "^%u%l+ %u%l+$") ~= nil)
	end

	-- Every name in the lists, on its own, because the lists are what the world-content work, part 2
	-- lengthens and a name with a space or a capital in it would be a silent
	-- fallback to "user" for one machine in thirty-four.
	for _, which in ipairs({ "first", "last" }) do
		local list = CeroSecContent.NAMES[which]
		check(which .. " names are a list", type(list) == "table" and #list > 0)
		for i = 1, #list do
			check(which .. ' name "' .. list[i] .. '" is a valid user name on its own',
				CeroSecOS.isValidUserName(list[i]))
		end
	end
	for i = 1, #CeroSecContent.WORDS do
		local word = CeroSecContent.WORDS[i]
		check('password word "' .. word .. '" is lower case letters',
			string.find(word, "^[a-z]+$") ~= nil)
		check('password word "' .. word .. '" leaves room for its digits',
			#word + 2 <= CeroSecOS.MAX_PASSWORD)
	end
end

--
-- 3. Which premises is which profile
--

do
	eq("no names at all is a house", CeroSecContent.profileFor(nil, nil),
		CeroSecContent.DEFAULT_PROFILE)
	eq("empty names are a house", CeroSecContent.profileFor("", ""),
		CeroSecContent.DEFAULT_PROFILE)
	eq("a zone the map called an office", CeroSecContent.profileFor("Office", nil),
		"office")
	eq("and the case does not matter",
		CeroSecContent.profileFor("ACCOUNTING OFFICE", nil), "office")
	eq("a police zone", CeroSecContent.profileFor("PoliceStorage", nil), "police")
	eq("the ZONE wins over the rooms",
		CeroSecContent.profileFor("Office", { "kitchen" }), "office")
	eq("and the rooms are asked when there is no zone",
		CeroSecContent.profileFor(nil, { "kitchen" }), "residential")
	eq("one room may be given as a bare string",
		CeroSecContent.profileFor(nil, "kitchen"), "residential")
	eq("a room nobody has a word for is a house",
		CeroSecContent.profileFor(nil, { "zzzz" }), CeroSecContent.DEFAULT_PROFILE)
	eq("no rooms at all is a house", CeroSecContent.profileFor(nil, {}),
		CeroSecContent.DEFAULT_PROFILE)

	--
	-- THE BUG THIS SHAPE EXISTS FOR, and it shipped once.
	--
	-- A profile used to be decided from the ROOM THE CALLER STOOD IN. In a house
	-- with a study in it the desk in the study answered "office" -- a profile with a
	-- root password, so a note was written into the drawer -- and the computer in
	-- the living room of the SAME HOUSE answered "residential", which has none. The
	-- paper named a password no machine in the county had, which is the one thing
	-- the whole design promises cannot happen.
	--
	-- The answer is a list of the BUILDING's rooms, the same list from every square
	-- of it, and the assertion is that ONE question has ONE answer.
	--
	local house = { "kitchen", "livingroom", "bedroom", "office" }
	local fromStudy = CeroSecContent.profileFor(nil, house)
	local fromLivingRoom = CeroSecContent.profileFor(nil, house)
	eq("every square of one house gets one profile", fromStudy, fromLivingRoom)

	-- And the order the engine hands the rooms over in cannot change it. The scan
	-- walks the WORD list and asks every name about each word, so "which room wins"
	-- is a decision in an ordered list and not an accident of iteration.
	local shuffled = { "office", "bedroom", "kitchen", "livingroom" }
	eq("and the order the rooms arrive in does not change it",
		CeroSecContent.profileFor(nil, shuffled), fromStudy)
	local reversed = {}
	for i = #house, 1, -1 do reversed[#reversed + 1] = house[i] end
	eq("nor does reading them backwards",
		CeroSecContent.profileFor(nil, reversed), fromStudy)

	-- A building with an office room in it IS an office by that list, which is the
	-- decision: the word list is ordered and `office` sits above the household
	-- words. What matters is not which way it goes -- it is that it goes the same
	-- way for the drawer and for the desk.
	eq("a house with a study in it is an office to everybody in it", fromStudy,
		"office")
	eq("and a house with no study in it is a house to everybody in it",
		CeroSecContent.profileFor(nil, { "kitchen", "livingroom", "bedroom" }),
		"residential")

	-- Junk in the list is skipped and does not stop the scan.
	eq("a list with holes and junk in it still answers",
		CeroSecContent.profileFor(nil, { "", 7, false, "office" }), "office")

	-- Every word in the table resolves to an id that is in PROFILE_IDS. A word
	-- pointing at an id nobody declared would be a machine prefilled with nothing
	-- for a reason nothing could say.
	local known = {}
	for i = 1, #CeroSecContent.PROFILE_IDS do
		known[CeroSecContent.PROFILE_IDS[i]] = true
	end
	for i = 1, #CeroSecContent.PREMISES_WORDS do
		local pair = CeroSecContent.PREMISES_WORDS[i]
		check('the word "' .. pair[1] .. '" points at a declared profile id',
			known[pair[2]] == true)
		eq('and the word "' .. pair[1] .. '" resolves to it',
			CeroSecContent.profileFor(pair[1], nil), pair[2])
		-- And the same word found in a ROOM name resolves to the same profile: the
		-- two halves of the question are answered by one list, so a word that meant
		-- one thing to a zone and another to a room is impossible.
		eq('and the same word in a room name resolves to it too',
			CeroSecContent.profileFor(nil, { pair[1] }), pair[2])
	end
	check("the default is a declared id", known[CeroSecContent.DEFAULT_PROFILE] == true)

	-- And every profile TABLE there is answers to one of the declared ids, so a
	-- profile somebody wrote under a name nothing resolves to cannot sit there
	-- unreachable.
	for id in pairs(CeroSecContent.PROFILES) do
		check('the profile "' .. id .. '" has a declared id', known[id] == true)
	end

	--
	-- WHICH ROOMS ARE SEPARATE SHOPS (premises v2)
	--
	-- The pure half of the tenancy rule. Where the rooms are is the server's and has
	-- its own bench (tests/window_test.lua); what a NAME means is here, with no world
	-- in sight, and every case below is a room name the shipped county really has --
	-- the counts are in docs/notes/tenancies.md.
	--

	-- THE SHOPFRONTS. A word, and a trade the map spells out instead of a word.
	for _, name in ipairs({ "musicstore", "clothesstore", "gunstore", "toolstore",
			"bookstore", "conveniencestore", "cornerstore", "pawnshop", "metalshop",
			"dentist", "optometrist", "pharmacy", "bakery", "cafe", "bank" }) do
		check('"' .. name .. '" is a shop', CeroSecContent.isTenancyName(name, 100))
	end

	-- AND WHAT IS NOT, which is the half that keeps this from splitting the county.
	-- `office` is 3977 rooms and nearly every business has one; `classroom` is 89 and
	-- `prisoncells` 540, so a tenancy word there would break every school and every
	-- prison into premises with a telephone line each.
	for _, name in ipairs({ "office", "officestorage", "classroom",
			"elementaryclassroom", "prisoncells", "policeoffice", "hospitalroom",
			"motelroom", "medical", "medicaloffice", "warehouse", "factory",
			"kitchen", "bedroom", "livingroom", "bathroom", "hall", "hallway",
			"breakroom", "janitor", "garagestorage", "laundry" }) do
		check('"' .. name .. '" is not a shop',
			not CeroSecContent.isTenancyName(name, 100))
	end

	-- A STORAGE IS THE BACK OF THE SHOP IN FRONT OF IT and never a second shop, and a
	-- COUNTER is its till. Both carry a shopfront word, which is why they need saying.
	for _, name in ipairs({ "gunstorestorage", "clothesstorage", "bookstorage",
			"pharmacystorage", "toolstorestorage", "cornerstorestorage",
			"cornerstorecounter" }) do
		check('"' .. name .. '" is the back of a shop and not one',
			not CeroSecContent.isTenancyName(name, 100))
	end

	-- A ROOM OF ONE TILE is a gas station's pump island. Thirteen stations in the
	-- county are four of these and no two of them touch, so every one of them was four
	-- premises with four telephone lines until the area was in the question.
	check("a one-tile shopfront is not a shop",
		not CeroSecContent.isTenancyName("gasstore", 1))
	check("two tiles is", CeroSecContent.isTenancyName("gasstore", 2))
	check("and an area nobody measured is not",
		not CeroSecContent.isTenancyName("gasstore", nil))
	check("nor is a name that is not one", not CeroSecContent.isTenancyName(7, 100))
	check("nor an empty one", not CeroSecContent.isTenancyName("", 100))

	-- EVERY TRADE ON THE LIST IS A ROOM NAME THE SHIPPED MAP HAS. A word nothing on
	-- the map wears is a tenancy nobody could ever stand in, and the list is short
	-- enough to hold to that. The map's own spellings, read off the lot headers.
	local MAP_ROOMS = {}
	for _, name in ipairs({ "dentist", "optometrist", "pharmacy", "bakery",
			"butcher", "knoxbutcher", "cafe", "diner", "restaurant", "bank",
			"pawnshop" }) do
		MAP_ROOMS[name] = true
	end
	for i = 1, #CeroSecContent.TENANCY_TRADES do
		local trade = CeroSecContent.TENANCY_TRADES[i]
		check('the trade "' .. trade .. '" is a room name the shipped map has',
			MAP_ROOMS[trade] == true)
		check('and it is read as a shop', CeroSecContent.isTenancyName(trade, 100))
		-- And it resolves to a profile that is not the default, or a shop would be
		-- prefilled as somebody's house -- which is the report's "no specifics".
		check('and to a profile of its own',
			CeroSecContent.profileFor(CeroSecContent.tenancyLabel(trade), { trade })
				~= CeroSecContent.DEFAULT_PROFILE)
	end

	-- THE COMMON PARTS, which belong to nobody: a mall corridor is not the shop it
	-- happens to share its longest wall with, and every shop is off it.
	for _, name in ipairs({ "hall", "hallway", "corridor", "lobby", "foyer",
			"elevator", "stairwell", "empty", "emptyoutside", "secondaryhall" }) do
		check('"' .. name .. '" is nobody\'s', CeroSecContent.isCommonName(name))
	end
	for _, name in ipairs({ "musicstore", "dentist", "clothesstorage", "office",
			"bathroom", "breakroom" }) do
		check('"' .. name .. '" is not a common part',
			not CeroSecContent.isCommonName(name))
	end

	-- THE WORDS ON THE FIRMWARE, which is what a survivor in a mall reads to know
	-- which of eleven lines he is sitting at. A room name is one lower-case word
	-- because it is a loot key, so it is split in front of the trade word it ends on
	-- and nothing cleverer is attempted.
	eq("a shop name is split at the trade word",
		CeroSecContent.tenancyLabel("musicstore"), "Music Store")
	eq("and so is a longer one",
		CeroSecContent.tenancyLabel("conveniencestore"), "Convenience Store")
	eq("a trade with no word in it is just capitalised",
		CeroSecContent.tenancyLabel("dentist"), "Dentist")
	eq("and so is a one-word shop", CeroSecContent.tenancyLabel("pharmacy"),
		"Pharmacy")
	-- A name the map wrote as one word that a second break would have to GUESS at is
	-- left as the map wrote it: guessing is inventing a shop name.
	eq("a name with two words run together keeps them",
		CeroSecContent.tenancyLabel("leatherclothesstore"), "Leatherclothes Store")
	eq("a name that IS the word is the word",
		CeroSecContent.tenancyLabel("store"), "Store")
	eq("and junk is nothing", CeroSecContent.tenancyLabel(7), nil)
	-- The label reaches a profile, which is the line the whole thing hangs from: the
	-- dentist's machine is the clinic's and the music store's is the shop's.
	eq("the dentist's label resolves to the clinic",
		CeroSecContent.profileFor(CeroSecContent.tenancyLabel("dentist"),
			{ "dentist" }), "clinic")
	eq("and the music store's to the shop",
		CeroSecContent.profileFor(CeroSecContent.tenancyLabel("musicstore"),
			{ "musicstore" }), "store")
end

--
-- 4. Every profile, built on a fresh machine
--

-- The script engine, driven the way the server drives it -- os_test.lua's own
-- loop, cut to what a bench that only runs scripts needs. The parse, the
-- expansion, the commands and every ceiling are the engine's.
-- `answers` is what somebody types at it, in order, and it is what lets a bench
-- run a program that ASKS -- a game. Every answer goes back through
-- CeroSecOS.jobInput, which is the one door an answer goes through on a real
-- machine; a question past the end of the list is not answered at all, so the job
-- comes back still waiting and the caller can say so instead of the bench looping
-- on an empty line for ever.
local function run(state, session, line, env, answers)
	env = env or { now = START }
	if session.shvars == nil then session.shvars = {} end
	local job, refusal =
		CeroSecOS.promptJob(state, session, line, session.shvars, session.status)
	if job == nil then return false, { refusal }, 0 end
	local out, turns, at = {}, 0, 1
	while not CeroSecOS.jobIsOver(job) and turns < 2000 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, env, 1000)
		for k = 1, #job.out do out[#out + 1] = job.out[k] end
		job.out = {}
		if job.state == "waiting" and job.ask ~= nil and answers ~= nil
				and at <= #answers then
			CeroSecOS.jobInput(state, job, answers[at], env)
			at = at + 1
		elseif job.state == "waiting" or job.state == "sleeping" then
			break
		end
		if job.spawn ~= nil then break end
	end
	for k = 1, #job.out do out[#out + 1] = job.out[k] end
	session.status = job.status
	return job.status == 0, out, turns, job, at - 1
end

-- The same loop, for a script that SLEEPS. `run` above stops at a sleeping job on
-- purpose -- a bench that waited would be a bench nobody could read -- but the
-- diagnostics suite has a `sleep 1` in it, and a runner that gave up there would
-- report the rest of the suite as "never ran".
--
-- The millisecond clock is wound FORWARD to the job's own wake time rather than
-- ticked: a bench that advanced the clock a second at a time would be a bench
-- whose turn count is the sleep's length, and the turn ceiling is what says a
-- script finishes at all.
local function runSleeping(state, session, line, env, answers)
	env = env or { now = START }
	if env.nowMs == nil then env.nowMs = 0 end
	if session.shvars == nil then session.shvars = {} end
	local job, refusal =
		CeroSecOS.promptJob(state, session, line, session.shvars, session.status)
	if job == nil then return false, { refusal }, 0 end
	local out, turns, at = {}, 0, 1
	while not CeroSecOS.jobIsOver(job) and turns < 2000 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, env, 1000)
		for k = 1, #job.out do out[#out + 1] = job.out[k] end
		job.out = {}
		if job.state == "waiting" and job.ask ~= nil and answers ~= nil
				and at <= #answers then
			CeroSecOS.jobInput(state, job, answers[at], env)
			at = at + 1
		elseif job.state == "waiting" then
			break
		elseif job.state == "sleeping" then
			if type(job.wakeMs) == "number" and job.wakeMs > env.nowMs then
				env.nowMs = job.wakeMs
			else
				env.nowMs = env.nowMs + 1000
			end
		end
		if job.spawn ~= nil then break end
	end
	for k = 1, #job.out do out[#out + 1] = job.out[k] end
	session.status = job.status
	return job.status == 0, out, turns, job
end

-- A fake env.devices, os_test.lua's shape, built out of what a script DECLARED it
-- needs. That is the point of `needs` being in the library: the bench stubs
-- exactly what the script says it wants and nothing else, so a script that
-- quietly reached for a second device would find it missing.
--
-- What the WORLD answers after a write, which is not the word that was written.
-- `echo close > /dev/door0` and then `cat /dev/door0` reads "closed", and a lock
-- written "lock" reads "locked": the state words are the ones the world composes
-- out of the object itself (SCeroSecDevices.doorState and the two beside it --
-- "open"/"closed"/"locked" for a door, "locked"/"unlocked" for a lock), while the
-- vocabulary a write uses is the imperative (CeroSecOS.DEV_VALUES).
--
-- Written down here because a stub that echoed the written word back would be a
-- machine that does not exist, and a script that reads a device back to check its
-- own work -- which is what a lockup script is FOR -- would be proved against it.
local STATE_AFTER = {
	open = "open", close = "closed",
	lock = "locked", unlock = "unlocked",
	on = "on", off = "off",
}

local function devicesFor(needs)
	local entries = {}
	if type(needs) == "table" and type(needs.devices) == "table" then
		for i = 1, #needs.devices do
			local e = needs.devices[i]
			entries[#entries + 1] = { id = e.id, kind = e.kind, desc = e.desc or "",
				side = "", pos = "0 0", state = e.state or "off" }
		end
	end
	local byId = {}
	for i = 1, #entries do byId[entries[i].id] = entries[i] end
	local devices = { writes = {} }
	devices.list = function()
		local out = {}
		for i = 1, #entries do
			local e = entries[i]
			out[i] = { id = e.id, kind = e.kind, desc = e.desc, side = e.side,
				pos = e.pos, state = e.state }
		end
		return out
	end
	devices.write = function(id, value)
		devices.writes[#devices.writes + 1] = id .. "=" .. value
		local e = byId[id]
		if e == nil then return false, "no such device" end
		e.state = STATE_AFTER[value] or value
		return true, nil, e.state
	end
	devices.chmod = function() end
	return devices
end

-- The word that reaches one profile id, so the bench asks for a profile the way
-- the world does -- by the name of a premises -- and not by naming the id
-- directly. An id no word reaches is an id nothing in the world can ever select,
-- which is asserted below rather than worked around.
local WORD_FOR = {}
for i = #CeroSecContent.PREMISES_WORDS, 1, -1 do
	local pair = CeroSecContent.PREMISES_WORDS[i]
	WORD_FOR[pair[2]] = pair[1]
end

do
	local ids = CeroSecContent.PROFILE_IDS
	local built = 0
	for i = 1, #ids do
		local id = ids[i]
		check("every declared profile id is reachable from a premises name (" .. id
			.. ")", WORD_FOR[id] ~= nil)
		local premises = WORD_FOR[id]
		eq("and that name resolves to it (" .. id .. ")",
			CeroSecContent.profileFor(premises, nil), id)
		local profile = CeroSecContent.PROFILES[id]
		-- The eight empty slots. A machine on such a premises is prefilled with
		-- nothing, which is what a machine was before this file existed -- and that
		-- is asserted rather than skipped, because "the world-content work, part 2 will fill it" must not
		-- be able to become "and until then it half fills it".
		if profile == nil then
			local state = CeroSecOS.newState("ksp-4-b")
			local before = CeroSecOS.systemNode(state, "/etc/passwd").data
			local got =
				CeroSecContent.prefill(state, opts(SECRET_A, { premises = premises }))
			eq("an empty profile (" .. id .. ") prefills nothing", got, nil)
			eq("and leaves the accounts alone (" .. id .. ")",
				CeroSecOS.systemNode(state, "/etc/passwd").data, before)
		else
			built = built + 1
			local state = CeroSecOS.newState("ksp-4-b")
			-- What the machine already had, so the checks below are asked of what the
			-- PROFILE wrote and not of the machine's own shipped files: /etc/sudoers
			-- has a comment in it wider than the screen and always has, and a bench
			-- that held a profile's texts to sixty columns by holding the whole
			-- machine to it would be a bench about the wrong thing.
			local shipped = walk(state.fs)
			local got, password, logins =
				CeroSecContent.prefill(state, opts(SECRET_A, { premises = premises }))
			eq("profile " .. id .. " is the one asked for", got, id)

			-- WHOSE DESK THIS MACHINE IS. Asked of the catalogue with the very key the
			-- prefill used, so the bench and the writer cannot pick two owners.
			local mkey = CeroSecContent.machineKey(12, 34, 8130, 9254, 0)
			local ownerSlot = CeroSecContent.ownerSlot(SECRET_A, mkey, profile)
			local ownerName = nil
			if ownerSlot ~= nil then ownerName = logins[ownerSlot] end

			-- THE BOOT GATE. Everything else in here is detail; this is the one that
			-- says the machine still works. A prefilled state the validator refuses
			-- is a computer the player switches on and finds broken, for ever, with
			-- no way back but the BIOS.
			local ok, why = CeroSecOS.validate(state)
			check("a prefilled " .. id .. " machine passes the boot gate: "
				.. tostring(why), ok)
			check("and it has an operating system on it", CeroSecOS.systemOk(state))

			-- The ceilings, measured and not assumed.
			local nodes, bytes = CeroSecOS.usage(state)
			check(id .. " is inside MAX_NODES (" .. nodes .. ")",
				nodes <= CeroSecOS.MAX_NODES)
			check(id .. " is inside the disk (" .. bytes .. ")",
				bytes <= CeroSecOS.MAX_TOTAL_BYTES)
			-- And far enough inside it that a survivor can still use the machine: a
			-- profile that filled the disk would be a computer nobody can write a
			-- script on, which is the whole of what this mod is for. Half.
			check(id .. " leaves half the disk free (" .. bytes .. ")",
				bytes * 2 <= CeroSecOS.MAX_TOTAL_BYTES)

			local all = walk(state.fs)
			local wrote = 0
			for path, node in pairs(all) do
				local isOurs = shipped[path] == nil
					or path == CeroSecOS.MOTD_PATH or path == CeroSecOS.HOSTNAME_PATH
					or path == CeroSecOS.ISSUE_PATH
				-- Counted only for a path the machine did NOT already have. /etc/motd
				-- and /etc/hostname are on every fresh machine, so counting those made
				-- the "wrote something" check below true whatever a profile did -- an
				-- assertion that could not fail, which is worse than no assertion.
				if shipped[path] == nil then wrote = wrote + 1 end
				if node.type == "file" then
					check(id .. " " .. path .. " is inside MAX_FILE_BYTES ("
						.. #(node.data or "") .. ")",
						#(node.data or "") <= CeroSecOS.MAX_FILE_BYTES)
					-- Every line of a file the PROFILE wrote fits the screen. A survivor
					-- reads these with `cat` on a sixty column terminal that does not
					-- wrap.
					if isOurs then
						for line in ((node.data or "") .. "\n"):gmatch("([^\n]*)\n") do
							check(id .. " " .. path .. ' line fits 60 columns: "' .. line
								.. '" (' .. #line .. ")", #line <= CeroSecOS.COLS)
						end
					end
				end
				if node.type == "dir" then
					check(id .. " " .. path .. " is inside MAX_DIR_ENTRIES",
						CeroSecOS.countEntries(node) <= CeroSecOS.MAX_DIR_ENTRIES)
				end
			end

			check(id .. " put files on the machine that were not already there ("
				.. wrote .. ")", wrote > 0)

			-- The hostname. The head is the profile's and the TAIL is still the
			-- machine's coordinates, so /etc/hosts, the prompt and ruptime all agree.
			check(id .. " has a valid hostname (" .. state.hostname .. ")",
				CeroSecOS.isValidHostname(state.hostname))
			eq(id .. " keeps the coordinate tail",
				string.match(state.hostname, "(%-.*)$"), "-4-b")
			eq(id .. " writes it to /etc/hostname",
				CeroSecOS.systemNode(state, CeroSecOS.HOSTNAME_PATH).data, state.hostname)

			-- The accounts, read back out of the file the way the machine reads them.
			if type(profile.accounts) == "table" then
				for a = 1, #profile.accounts do
					local login = logins[a]
					if login ~= nil then
						local user = CeroSecOS.getUser(state, login)
						check(id .. " account " .. a .. " (" .. login .. ") is in the file",
							user ~= nil)
						if profile.accounts[a].pass then
							-- The password is DERIVED and never stored, so the only way to ask
							-- whether it is the right one is to try it, which is what a
							-- survivor does -- and the derivation is the PREMISES', which is
							-- what lets a paper in a dead man's pocket name it.
							local want =
								CeroSecContent.accountPassword(SECRET_A, 12, 34, a, login)
							check(id .. " account " .. a .. " holds its derived password",
								CeroSecOS.checkPassword(user, want))
							check(id .. " account " .. a .. " is not open",
								not CeroSecOS.checkPassword(user, ""))
						else
							check(id .. " account " .. a .. " is open",
								CeroSecOS.checkPassword(user, ""))
						end
						-- ONE MACHINE IS ONE PERSON'S DESK. The owner's files are on it and
						-- nobody else's are, and both halves are asserted: "the owner's are
						-- there" alone would pass a prefill that wrote everybody's, which is
						-- exactly what this change took out.
						if type(profile.accounts[a].files) == "table" then
							for f = 1, #profile.accounts[a].files do
								local file = profile.accounts[a].files[f]
								local at = all["/home/" .. login .. "/" .. file.path]
								if a == ownerSlot then
									check(id .. " the owner " .. login .. "'s " .. file.path
										.. " is there", at ~= nil and at.type == "file")
									eq(id .. " and it is his", at.owner, login)
								else
									eq(id .. " " .. login .. " is not the owner, so his "
										.. file.path .. " is not on this machine", at, nil)
								end
							end
						end
						-- And his home is EMPTY of anything but dot-files, however the
						-- catalogue is written: a file nobody declared is a file this check
						-- would miss if it only walked the declarations.
						if a ~= ownerSlot then
							local home = all["/home/" .. login]
							if home ~= nil and home.type == "dir" then
								local kids = CeroSecOS.childNames(home)
								for k = 1, #kids do
									check(id .. " " .. login .. "'s home holds only dot-files ("
										.. kids[k] .. ")", string.sub(kids[k], 1, 1) == ".")
								end
							end
						end
					end
				end
			end

			-- Root. A profile that asks for a password gets one that WORKS and that
			-- is nowhere on the disk in clear, which is the pair of facts the sticky
			-- note rests on.
			local root = CeroSecOS.getUser(state, "root")
			if profile.root then
				eq(id .. " answers root's password to its caller", password,
					CeroSecContent.password(SECRET_A, CeroSecContent.rootKey(12, 34)))
				check(id .. " root holds it", CeroSecOS.checkPassword(root, password))
				check(id .. " root is not open", not CeroSecOS.checkPassword(root, ""))
				-- And the letters are nowhere on the machine. Every file, and the
				-- hostname too.
				for path, node in pairs(all) do
					if node.type == "file" then
						check(id .. " " .. path .. " does not carry the password in clear",
							string.find(node.data or "", password, 1, true) == nil)
					end
				end
			else
				eq(id .. " asks for no root password", password, nil)
				check(id .. " leaves root open", CeroSecOS.checkPassword(root, ""))
			end

			-- The banner, which is what getty prints over the login prompt. A profile
			-- that names one wrote it; a profile that does not keeps the seeded line,
			-- and that line names THIS machine -- the hostname went in before the
			-- content did, so a banner naming "cerosec" would be a banner nobody
			-- rewrote.
			local banner = CeroSecOS.systemNode(state, CeroSecOS.ISSUE_PATH)
			check(id .. " has a banner over its login prompt",
				banner ~= nil and banner.type == "file")
			if type(profile.issue) == "string" then
				eq(id .. " writes the banner", banner.data, profile.issue)
			else
				eq(id .. " keeps the seeded banner, naming itself",
					banner.data, CeroSecOS.issueText(state.hostname))
			end
			eq(id .. " and a login prompt has exactly one line over it",
				#CeroSecOS.issueLines(state), 1)

			-- The motd, inside what a login will print.
			if type(profile.motd) == "string" then
				eq(id .. " writes the motd",
					CeroSecOS.systemNode(state, CeroSecOS.MOTD_PATH).data, profile.motd)
				local lines = CeroSecOS.motdLines(state)
				eq(id .. " and every line of it is printed", #lines,
					select(2, string.gsub(profile.motd, "\n", "")) + 1)
			end

			-- The log. Dated BEFORE day one -- a machine nobody has switched on has
			-- not written a line since the outbreak -- and inside the week.
			if type(profile.logs) == "table" and #profile.logs > 0 then
				local log = CeroSecOS.systemNode(state, CeroSecOS.LOG_PATH .. "/messages")
				check(id .. " has a log", log ~= nil and log.type == "file")
				eq(id .. " and the log is root's", log.owner, "root")
				local lines = CeroSecOS.splitLines(log.data)
				-- The premises' own week, and the county's on the end of it: three
				-- outbreak entries off CeroSecContent.LOG_EVENTS, which is what says a
				-- machine that had been standing there through July looks like it.
				eq(id .. " one line per entry", #lines,
					#profile.logs + CeroSecContent.LOG_EVENT_COUNT)
				for l = 1, #lines do
					check(id .. " log line " .. l .. " fits the screen", #lines[l] <= CeroSecOS.COLS)
					local month, day = string.match(lines[l], "^(%a%a%a)%s+(%d+) ")
					check(id .. " log line " .. l .. " starts with a date the machine writes",
						month ~= nil)
					eq(id .. " log line " .. l .. " is dated in the start month", month, "Jul")
					check(id .. " log line " .. l .. " is dated before day one ("
						.. tostring(day) .. ")", tonumber(day) < 9)
					check(id .. " log line " .. l .. " is inside the week",
						tonumber(day) >= 9 - CeroSecContent.LOG_DAYS)
				end
			end

			-- The mail, in the format the machine's own `mail` can read back.
			if type(profile.mail) == "table" then
				for m = 1, #profile.mail do
					local to = profile.mail[m].to
					if type(to) == "number" then to = logins[to] end
					if to ~= nil then
						local box = all[CeroSecOS.mailPath(to)]
						check(id .. " " .. tostring(to) .. " has mail", box ~= nil)
						eq(id .. " and the mailbox is his", box.owner, to)
						eq(id .. " at the mail mode", box.mode, CeroSecOS.MAIL_MODE)
						check(id .. " and it is inside the mailbox ceiling",
							#(box.data or "") <= CeroSecOS.MAIL_BYTES)
					end
				end
			end

			-- THE CRONTABS, and this is the one thing about a profile that has to be
			-- true of the file's CONTENTS and not only of where it landed: cron reads
			-- it with the machine's own parser, so a line the parser refuses is a line
			-- that does nothing for ever and says nothing about why.
			if type(profile.cron) == "table" then
				for c = 1, #profile.cron do
					local to = profile.cron[c].to
					if type(to) == "number" then to = logins[to] end
					if to ~= nil then
						local tab = all[CeroSecOS.cronPath(to)]
						check(id .. " " .. tostring(to) .. " has a crontab", tab ~= nil)
						eq(id .. " and the crontab is root's", tab.owner, "root")
						eq(id .. " at the crontab mode", tab.mode, CeroSecOS.CRONTAB_MODE)
						eq(id .. " and crontab(1) itself accepts it",
							CeroSecOS.checkCrontab(CeroSecOS.cronPath(to), tab.data), nil)
						local entries = CeroSecOS.parseCrontab(tab.data)
						check(id .. " and it has lines in it (" .. #entries .. ")",
							#entries > 0 and #entries <= CeroSecOS.CRON_MAX_LINES)
						-- And a line that calls a script of ours calls a file that is
						-- REALLY ON THIS MACHINE, at the very path the line names.
						--
						-- ASKED OF THE FILESYSTEM AND NOT OF THE CATALOGUE, and that is
						-- the fix for a bench that went green over a broken machine. It
						-- used to derive the set of paths the profile "always writes" out
						-- of profile.bin and compare against that -- so it asked the
						-- catalogue whether the catalogue meant to write the file, and
						-- the catalogue always means to. The military post's
						-- /usr/local/bin/check.sh was never written at all, because
						-- placeScripts was called only for a machine with an ordinary
						-- account on it and the post has none, and its crontab mailed
						-- "not found" once an hour for ever. Walking the built machine is
						-- the only question that could have caught it.
						--
						-- $HOME is what cron hands the shell, so it is resolved to the
						-- crontab owner's own home before the path is looked up.
						local ownHome = (CeroSecOS.getUser(state, to) or {}).home or "/"
						for named in string.gmatch(tab.data, "([%$%w%-%./]+%.sh)") do
							local at = string.gsub(named, "%$HOME", ownHome)
							check(id .. " its crontab calls " .. named
								.. ", and " .. at .. " is really on the machine",
								all[at] ~= nil and all[at].type == "file")
						end
					end
				end
			end

			-- A `files` entry marked `dir` is a directory and is there as one: a
			-- profile whose tree was not made is a profile whose files were all
			-- refused for a reason nothing in the catalogue could see.
			if type(profile.files) == "table" then
				for f = 1, #profile.files do
					local file = profile.files[f]
					if file.dir then
						local at = all[file.path]
						check(id .. " made the directory " .. tostring(file.path),
							at ~= nil and at.type == "dir")
					end
				end
			end
		end
	end
	check("at least two profiles are written", built >= 2)
end

--
-- 4b. THE CRONTAB'S OWN LINE, RUN AS THE ACCOUNT IT BELONGS TO
--
-- Everything above proves a crontab is a file cron will PARSE. That is not the
-- same thing as a line that works: the command in it names a path with $HOME in
-- it, an account whose login was generated, and a script placed behind a roll --
-- three ways to write a line that parses perfectly and mails "not found" once an
-- hour for ever.
--
-- So one is taken off a prefilled machine and TYPED, as the account it belongs to,
-- on the machine the profile built. The radio station's, because its line is the
-- one built to run from cron at all.
--

-- WHERE THE DESK IS. A crontab inside an account entry is written only on the
-- machine that account OWNS (see CeroSecContent.ownerSlot), so a bench that wants
-- to type the station engineer's own line has to stand at the station engineer's
-- own desk. It walks the square until the machine key picks the slot it wants,
-- which is what a survivor walking a building does, and answers the overrides for
-- `opts`. nil for a slot no square in the walk reaches, which is a red rather than
-- a silent skip.
local function deskFor(id, secret, want, b1, b2)
	local profile = CeroSecContent.PROFILES[id]
	for i = 0, 200 do
		local x, y = 8130 + i, 9254 + i * 3
		local mkey = CeroSecContent.machineKey(b1 or 12, b2 or 34, x, y, 0)
		if CeroSecContent.ownerSlot(secret, mkey, profile) == want then
			return { x = x, y = y, b1 = b1 or 12, b2 = b2 or 34 }, mkey
		end
	end
	return nil
end

do
	local state = CeroSecOS.newState("ksp-4-b")
	local slot = 1
	local where = deskFor("radio", SECRET_A, slot)
	check("a square exists where the station engineer's own desk is", where ~= nil)
	where.premises = "radio"
	local id, _, logins = CeroSecContent.prefill(state, opts(SECRET_A, where))
	eq("the station is the profile asked for", id, "radio")
	local login = logins[slot]
	check("and it has the engineer's account on it", login ~= nil)
	local password =
		CeroSecContent.accountPassword(SECRET_A, 12, 34, slot, login)
	local session = CeroSecOS.login(state, login, password)
	check("who can log in with the password a paper would name", session ~= nil)
	-- The environment a LOGIN hands a shell, which is where $HOME comes from --
	-- and cron hands its jobs the same one (CeroSecOS.loginVars, called by
	-- CeroSecJobs for a cron job and by the console for a prompt). A bench that
	-- left it empty would be a bench in which $HOME is the empty string and every
	-- path in the crontab is wrong in exactly the way this is here to catch.
	session.shvars = CeroSecOS.loginVars("/home/" .. login)

	local tab = CeroSecOS.systemNode(state, CeroSecOS.cronPath(login))
	check("the station has a crontab", tab ~= nil)
	local entries = CeroSecOS.parseCrontab(tab.data)
	check("with a line in it", #entries > 0)
	local env = { now = START, devices = devicesFor(nil) }
	for e = 1, #entries do
		local ran, lines = run(state, session, entries[e].cmd, env)
		check("its crontab line runs: " .. entries[e].cmd .. " -> "
			.. table.concat(lines, " / "), ran)
		check("and printed something worth mailing", #lines > 0)
		for l = 1, #lines do
			check('and it fits the screen: "' .. lines[l] .. '"',
				#lines[l] <= CeroSecOS.COLS)
		end
		-- And what it printed is the line of the sheet for the hour the bench's
		-- clock says it is, which is nine in the morning.
		check("and it is the nine o'clock line (" .. table.concat(lines, " ") .. ")",
			string.find(table.concat(lines, " "), "morning show", 1, true) ~= nil)
	end

	-- The same line, the way a machine nobody is standing at really runs it: with
	-- no terminal. A cron line is refused nothing here -- announce.sh reads a file
	-- and prints, which is all cron ever wanted -- and this is what says so.
	local vok, vwhy = CeroSecOS.validate(state)
	check("and the station still boots afterwards: " .. tostring(vwhy), vok)
end

--
-- 4b2. WHICH PREMISES COULD HAVE BEEN AUTOMATED, and whose crontab would drive it
--
-- The pure half of wave 7e; the world half -- the roll being made once, the fixtures
-- wired, the machine switched on and the lights really going out at nine -- is
-- tests/window_test.lua's, because only a world can answer it.
--
-- What is asserted here is the catalogue's own three facts, and each is asked of
-- EVERY profile rather than of the ones the change had in mind: a candidate is a
-- profile that really writes a crontab, so the day one gains or loses one it joins
-- or leaves the list on its own and nothing here has to be edited.
--
do
	local ids = CeroSecContent.PROFILE_IDS
	local candidates = 0
	for i = 1, #ids do
		local id = ids[i]
		local profile = CeroSecContent.PROFILES[id]
		-- Derived from the SAME table placeCron writes from, walked here by hand, so a
		-- hasJob that started answering out of a list of its own would disagree with it.
		local machineJob = type(profile.cron) == "table" and #profile.cron > 0
		local slot = nil
		if type(profile.accounts) == "table" then
			for a = 1, #profile.accounts do
				local cron = profile.accounts[a].cron
				if slot == nil and type(cron) == "table" and #cron > 0 then slot = a end
			end
		end
		eq(id .. ": hasJob agrees with the crontabs the profile really writes",
			CeroSecContent.hasJob(id), machineJob or slot ~= nil)
		eq(id .. ": jobSlot is the first account with a crontab",
			CeroSecContent.jobSlot(profile), slot)
		-- A job of the MACHINE's is root's and needs no desk; a job of a PERSON's has to
		-- have one, or the automation could stand its machine at somebody else's desk
		-- and the line would be in the catalogue and on no machine in the county.
		if CeroSecContent.hasJob(id) then
			candidates = candidates + 1
			check(id .. ": its nightly job is either root's or somebody's desk",
				machineJob or slot ~= nil)
		end
		-- And the roll can never say yes to a profile with nothing to run. Over a spread
		-- of premises, because one pair of bytes proves nothing about a hash.
		for n = 0, 60 do
			local b1, b2 = CeroSecOS.buildingKey(4000 + n * 23, 7000 + n * 37)
			if CeroSecContent.automated(SECRET_A, b1, b2, id) then
				check(id .. ": only a profile with a nightly job is ever automated",
					CeroSecContent.hasJob(id))
			end
		end
	end
	-- AND THE RULE ITSELF, on a profile made up here, because no profile the catalogue
	-- ships has TWO accounts with a crontab -- so "the first" and "the last" are the
	-- same answer on all eleven of them and the loop above is green either way. A pure
	-- function with no world behind it may be asked a question the world has not posed
	-- yet, and this is the one worth asking: the rule is a decision and not an accident
	-- of iteration.
	eq("jobSlot answers the FIRST account with a crontab, not the last",
		CeroSecContent.jobSlot({ accounts = {
			{ pass = true },
			{ pass = true, cron = { "0 21 * * * true" } },
			{ pass = true, cron = { "0 22 * * * true" } },
		} }), 2)
	eq("and nothing at all when no account has one",
		CeroSecContent.jobSlot({ accounts = { { pass = true }, { pass = true } } }), nil)
	eq("nor when there are no accounts", CeroSecContent.jobSlot({}), nil)

	eq("a house is the one profile with nothing to run",
		#ids - candidates, 1)
	eq("and it is residential", CeroSecContent.hasJob("residential"), false)

	-- THE ODDS. Asserted as a count over the county and not as the constant, because a
	-- roll that always said yes and a roll that always said no would both satisfy every
	-- assertion above -- one of them by automating Knox County entirely.
	local yes, total = 0, 0
	for n = 0, 399 do
		local b1, b2 = CeroSecOS.buildingKey(3000 + n * 19, 9000 + n * 13)
		total = total + 1
		if CeroSecContent.automated(SECRET_A, b1, b2, "store") then yes = yes + 1 end
	end
	check("about one premises in three is automated (" .. yes .. " of " .. total .. ")",
		yes > total / 6 and yes < total / 2)
	eq("and the declared share is what that is", CeroSecContent.AUTO_ONE_IN, 3)

	-- SOMEBODY STILL LOGGED IN, at the better odds. Both readings of one function, over
	-- the same machines: the automated machine's roll is its own and is more often a
	-- yes. A bench that only asked for one number could not see an `oneIn` that was
	-- being ignored.
	local plain, auto = 0, 0
	local profile = CeroSecContent.PROFILES.store
	for n = 0, 299 do
		local mkey = CeroSecContent.machineKey(12, 34, 2000 + n * 7, 5000 + n * 11, 0)
		if CeroSecContent.liveSession(SECRET_A, mkey, profile) then plain = plain + 1 end
		if CeroSecContent.liveSession(SECRET_A, mkey, profile,
				CeroSecContent.LIVE_AUTO_ONE_IN) then auto = auto + 1 end
	end
	check("about one ordinary desk in four was left logged in (" .. plain .. " of 300)",
		plain > 40 and plain < 120)
	check("and about one automated machine in two (" .. auto .. " of 300)",
		auto > 100 and auto < 200)
	check("which is more of them", auto > plain)
	-- And the military post is never one, whatever the odds asked for: session = false.
	local post = CeroSecContent.PROFILES.military
	local everLive = false
	for n = 0, 60 do
		local mkey = CeroSecContent.machineKey(12, 34, 900 + n, 900 + n * 3, 0)
		if CeroSecContent.liveSession(SECRET_A, mkey, post, 1) then everLive = true end
	end
	eq("a military post is never found at somebody's prompt, at any odds", everLive,
		false)
end

--
-- 4b3. THE FACTORY ACCOUNT IS OFF A MACHINE SOMEBODY SET UP
--
-- The reason this section exists, in the words the hole was found in: a prefilled
-- machine had root hashed and a paper in a drawer naming the letters -- and it also
-- still had `admin`, open, with a line of its own in /etc/sudoers. So `admin` at the
-- login prompt and then `sudo su` was root on any machine in the county without
-- reading anything, and the drawer, the pocket and the corpse were all decoration.
--
-- What is asserted is the whole of the way in, from four directions, because "the
-- account is gone" on its own is an assertion that a passwd file which failed to be
-- written at all would satisfy:
--
--   * the account, its home and every line that names it are off the machine;
--   * the STAFF administrator is not a way to root either -- he is in the device
--     group and not in /etc/sudoers, which is the line this change is drawn on;
--   * root's password is the one the paper in the drawer derives;
--   * and a BARE machine still has `admin`, open, because that is the one machine
--     the account describes: one nobody ever set up.
--
do
	local ids = CeroSecContent.PROFILE_IDS
	for i = 1, #ids do
		local id = ids[i]
		local word = WORD_FOR[id]
		if word ~= nil then
			local state = CeroSecOS.newState("ksp-4-b")
			-- The account IS there on the machine the prefill is handed, which is what
			-- makes the assertions below about its absence mean anything: a bench that
			-- never saw it there is a bench that cannot tell removal from never-was.
			check(id .. ": the machine starts with the factory account on it",
				CeroSecOS.getUser(state, CeroSecOS.FACTORY_USER) ~= nil)
			check(id .. ": and its home",
				CeroSecOS.systemNode(state, CeroSecOS.FACTORY_HOME) ~= nil)
			local _, _, logins = CeroSecContent.prefill(state, opts(SECRET_A,
				{ premises = word }))

			eq(id .. ": the factory account is off /etc/passwd",
				CeroSecOS.getUser(state, CeroSecOS.FACTORY_USER), nil)
			eq(id .. ": its home is gone",
				CeroSecOS.systemNode(state, CeroSecOS.FACTORY_HOME), nil)
			eq(id .. ": and it may not sudo, there being nothing left to ask about",
				CeroSecOS.sudoer(state, CeroSecOS.FACTORY_USER), nil)
			eq(id .. ": nor is it in the device group",
				CeroSecOS.inGroup(state, CeroSecOS.FACTORY_USER, CeroSecOS.DEV_GROUP),
				false)
			-- Read off the FILE as well, by line, because sudoer() answering nil is also
			-- what a missing /etc/sudoers answers -- and a machine with no sudoers file
			-- would satisfy the line above while being a different bug.
			local sudoers = CeroSecOS.systemNode(state, CeroSecOS.SUDOERS_PATH)
			check(id .. ": /etc/sudoers is still there", sudoers ~= nil)
			local lines = CeroSecOS.splitLines((sudoers or {}).data or "")
			local named = 0
			for l = 1, #lines do
				local entry = CeroSecOS.parseSudoersLine(lines[l])
				if entry ~= nil and entry.name == CeroSecOS.FACTORY_USER then
					named = named + 1
				end
			end
			eq(id .. ": and no line in it names the factory account", named, 0)
			-- The wheel line is untouched: it grants nothing (the group ships empty) and
			-- it is what `useradd -G wheel bob` means. Taking it out would cost root a
			-- door he never opened.
			check(id .. ": while %wheel is still the line it was",
				string.find((sudoers or {}).data or "",
					"%%" .. CeroSecOS.WHEEL_GROUP) ~= nil)
			-- And no group line anywhere still names it.
			local groups, order = CeroSecOS.readGroups(state)
			for g = 1, #order do
				eq(id .. ": no group still names it (" .. order[g] .. ")",
					groups[order[g]].set[CeroSecOS.FACTORY_USER], nil)
			end

			-- THE STAFF ADMINISTRATOR: the building, yes; root, no.
			local profile = CeroSecContent.PROFILES[id]
			if type(profile.accounts) == "table" then
				for a = 1, #profile.accounts do
					local login = logins[a]
					if login ~= nil and profile.accounts[a].admin then
						check(id .. ": the staff administrator may throw a relay (" .. login
							.. ")", CeroSecOS.inGroup(state, login, CeroSecOS.DEV_GROUP))
						eq(id .. ": and may not become root", CeroSecOS.sudoer(state, login),
							nil)
						-- The passwd flag is a mirror of wheel, and he is not in wheel:
						-- his prompt ends in $, as the parcours says.
						eq(id .. ": and carries no admin flag (" .. login .. ")",
							CeroSecOS.getUser(state, login).admin and true or false, false)
						eq(id .. ": and is not in wheel",
							CeroSecOS.inGroup(state, login, CeroSecOS.WHEEL_GROUP), false)
						-- Through the command a player would type, not only through the
						-- function behind it: sudo is the wire, and the refusal is what he
						-- reads.
						local password =
							CeroSecContent.accountPassword(SECRET_A, 12, 34, a, login)
						local session = CeroSecOS.login(state, login, password)
						check(id .. ": he can log in with the password a paper names",
							session ~= nil)
						if session ~= nil then
							session.shvars = CeroSecOS.loginVars("/home/" .. login)
							local ok, out = run(state, session, "sudo whoami")
							eq(id .. ": and sudo refuses him", ok, false)
							check(id .. ": in sudo's own words (" ..
								tostring((out or {})[1]) .. ")",
								string.find(tostring((out or {})[1]),
									"not in the sudoers file", 1, true) ~= nil)
						end
					end
				end
			end

			-- AND ROOT IS WHAT THE PAPER SAYS, which is the way in that is left.
			if profile.root then
				local note = CeroSecContent.password(SECRET_A,
					CeroSecContent.rootKey(12, 34))
				check(id .. ": the drawer's paper opens root",
					CeroSecOS.checkPassword(CeroSecOS.getUser(state, "root"), note))
				check(id .. ": and root is not open", not CeroSecOS.checkPassword(
					CeroSecOS.getUser(state, "root"), ""))
			end
			local vok, vwhy = CeroSecOS.validate(state)
			check(id .. ": and the machine still boots: " .. tostring(vwhy), vok)
		end
	end

	-- A BARE MACHINE, which is the control and is the one machine the factory account
	-- describes: nobody ever set it up. Nothing is prefilled here at all, which is
	-- what the option being off and a premises with no profile both come to.
	do
		local bare = CeroSecOS.newState("ksp-4-b")
		local factory = CeroSecOS.getUser(bare, CeroSecOS.FACTORY_USER)
		check("a bare machine keeps the factory account", factory ~= nil)
		check("and it is open", CeroSecOS.checkPassword(factory, ""))
		check("and may sudo, exactly as it always could",
			CeroSecOS.sudoer(bare, CeroSecOS.FACTORY_USER) ~= nil)
		check("and its home is there",
			CeroSecOS.systemNode(bare, CeroSecOS.FACTORY_HOME) ~= nil)
		check("and root is open on it too",
			CeroSecOS.checkPassword(CeroSecOS.getUser(bare, "root"), ""))
		-- A premises with no profile at all is the other way to be bare: prefill leaves
		-- the machine exactly as it found it and answers nothing.
		local unknown = CeroSecOS.newState("ksp-4-b")
		eq("a premises with no profile prefills nothing",
			CeroSecContent.prefill(unknown, opts(SECRET_A, { premises = "nosuchword",
				rooms = { "nosuchroom" } })), CeroSecContent.DEFAULT_PROFILE)
		-- ...and residential IS a profile, so that one is prefilled and gives the
		-- account up like the rest. The case that is really bare is an id the catalogue
		-- has no table for, which is what a future profile id looks like from here.
		local none = CeroSecOS.newState("ksp-4-b")
		local had = CeroSecContent.PROFILES.residential
		CeroSecContent.PROFILES.residential = nil
		eq("an id the catalogue has no table for prefills nothing",
			CeroSecContent.prefill(none, opts(SECRET_A, { premises = "nosuchword" })), nil)
		CeroSecContent.PROFILES.residential = had
		check("and such a machine keeps the factory account",
			CeroSecOS.getUser(none, CeroSecOS.FACTORY_USER) ~= nil)
	end
end

--
-- 4c. Every data file a script was proved on is a file some premises really keeps
--
-- CeroSecContent.DATA is named twice on purpose: once by the script that reads it
-- and once by the machine or the disk that carries it. If only the script named
-- one, the bench would be running audit.sh on a file of its own invention and
-- calling that proof.
--

do
	local names = {}
	for name in pairs(CeroSecContent.DATA) do names[#names + 1] = name end
	table.sort(names)
	check("there are data files", #names > 0)
	for i = 1, #names do
		local name, text = names[i], CeroSecContent.DATA[names[i]]
		local found = nil
		for id in pairs(CeroSecContent.PROFILES) do
			local profile = CeroSecContent.PROFILES[id]
			if type(profile.accounts) == "table" then
				for a = 1, #profile.accounts do
					local files = profile.accounts[a].files
					if type(files) == "table" then
						for f = 1, #files do
							if files[f].path == name and files[f].text == text then
								found = id
							end
						end
					end
				end
			end
			if type(profile.files) == "table" then
				for f = 1, #profile.files do
					if profile.files[f].path == name and profile.files[f].text == text then
						found = id
					end
				end
			end
		end
		for d = 1, #CeroSecContent.DISKS do
			local files = CeroSecContent.DISKS[d].files
			for f = 1, #files do
				if files[f].name == name and files[f].text == text then
					found = CeroSecContent.DISKS[d].id
				end
			end
		end
		check("the data file " .. name .. " is carried by something in the county",
			found ~= nil)
	end
end

--
-- 4d. THE THREE TELLINGS: every one of them, read
--
-- Section 4 builds ONE machine of each profile, so it reads one telling of each
-- file and the other two are never looked at. That is exactly the shape in which a
-- text with a line eighty columns wide, or a {staff4} nothing fills, sits in the
-- tree for a change and turns up on a player's screen in the one office in three
-- that got it.
--
-- So this walks the CATALOGUE and not a machine: every entry, every telling, with
-- names put in, held to the same rules section 4 holds the one it built to. And it
-- asserts the shape of the format as well as the text -- three tellings and not
-- two, never `text` and `texts` together, and PROSE MUST HAVE THREE. That last one
-- is the requirement of this change, and it is the only assertion here that a
-- forgetful next change could fail.
--

-- What a file may be, read at sixty columns. A thousand two hundred bytes is
-- twenty lines of sixty, which is the screen -- a file longer than that is a file
-- a survivor scrolls, and nothing here needs scrolling.
local FILE_CHARS = 1200

-- The DATA tables, by their own text, so an entry carrying one can be told from a
-- prose file that happens to have one telling.
local IS_DATA = {}
for _, text in pairs(CeroSecContent.DATA) do IS_DATA[text] = true end

do
	local names = {
		owner = "pcoleman", staff1 = "torres", staff2 = "walker",
		staff3 = "dhensley", host = "acct-04-11",
	}
	local entries, prose, told = 0, 0, 0
	local function judge(where, entry)
		entries = entries + 1
		check(where .. " does not carry both text and texts",
			entry.text == nil or entry.texts == nil)
		if entry.texts ~= nil then
			prose = prose + 1
			eq(where .. " has CeroSecContent.VARIANTS tellings", #entry.texts,
				CeroSecContent.VARIANTS)
		else
			-- A file with one telling is a DATA table and nothing else. The rule of
			-- this change in one assertion: prose varies, and the tables the scripts are
			-- proved against do not.
			check(where .. " has one telling only because it is a data table the "
				.. "scripts are proved against", IS_DATA[entry.text] == true)
			if entry.extra ~= nil then
				eq(where .. " has CeroSecContent.VARIANTS tails", #entry.extra,
					CeroSecContent.VARIANTS)
			end
		end
		local tellings = entry.texts or { entry.text }
		for v = 1, #tellings do
			told = told + 1
			local w = where .. " telling " .. v
			local text = CeroSecContent.fillNames(tellings[v], names)
			check(w .. " is a string", type(text) == "string" and text ~= "")
			check(w .. " is inside " .. FILE_CHARS .. " characters (" .. #text .. ")",
				#text <= FILE_CHARS)
			check(w .. " is inside MAX_FILE_BYTES", #text <= CeroSecOS.MAX_FILE_BYTES)
			-- Not one brace left. A placeholder nothing fills is a bug on a screen.
			check(w .. " has no placeholder left in it",
				string.find(text, "[{}]") == nil)
			-- ONE CHECK AND NOT ONE PER BYTE. A pattern says the same thing about the
			-- whole text and names the offender when there is one; a check per byte over
			-- ninety-three tellings was forty thousand assertions and eighteen seconds of
			-- the suite, which is a bench measuring the same fact forty thousand times.
			local bad = string.find(text, "[^\010\032-\126]")
			check(w .. " is printable ASCII (byte " .. tostring(bad) .. ": "
				.. tostring(bad and string.byte(text, bad)) .. ")", bad == nil)
			for line in (text .. "\n"):gmatch("([^\n]*)\n") do
				check(w .. ' line fits 60 columns: "' .. line .. '" (' .. #line .. ")",
					#line <= CeroSecOS.COLS)
			end
			-- And the names really went in: a telling that names a placeholder names
			-- one of the five, and every one of the five is a login the bench chose.
			for who in string.gmatch(tellings[v], "{(%a+%d*)}") do
				local known = false
				for p = 1, #CeroSecContent.PLACEHOLDERS do
					if CeroSecContent.PLACEHOLDERS[p] == who then known = true end
				end
				check(w .. " names a placeholder the filler knows ({" .. who .. "})",
					known)
			end
		end
	end

	for i = 1, #CeroSecContent.PROFILE_IDS do
		local id = CeroSecContent.PROFILE_IDS[i]
		local profile = CeroSecContent.PROFILES[id]
		if profile ~= nil then
			if type(profile.accounts) == "table" then
				for a = 1, #profile.accounts do
					local files = profile.accounts[a].files
					if type(files) == "table" then
						for f = 1, #files do
							judge(id .. " slot " .. a .. " " .. tostring(files[f].path), files[f])
						end
					end
				end
			end
			if type(profile.files) == "table" then
				for f = 1, #profile.files do
					local file = profile.files[f]
					if not file.dir then
						judge(id .. " " .. tostring(file.path), file)
					end
				end
			end
		end
	end
	-- AND THE DEALER'S DISK, which is not a profile and is read by every display
	-- model and every spare desk in the county -- so a telling of it that nobody
	-- walked would be the widest-read unread file there is.
	for f = 1, #CeroSecContent.DEMO.files do
		judge("demo " .. tostring(CeroSecContent.DEMO.files[f].path),
			CeroSecContent.DEMO.files[f])
	end

	check("there are prose files with three tellings each (" .. prose .. ")",
		prose >= 25)
	check("and every entry was read (" .. entries .. " entries, " .. told
		.. " tellings)", told >= entries * 2)

	-- EVERY TELLING IS REACHABLE, which is the other half of writing three of them:
	-- a chooser that answered 1 and 2 and never 3 would leave a third of the county's
	-- prose unread for ever and nothing above would notice.
	local seen = {}
	for b1 = 0, 15 do
		for b2 = 0, 15 do
			seen[CeroSecContent.variantOf(SECRET_A, b1, b2, "memo.txt")] = true
		end
	end
	for v = 1, CeroSecContent.VARIANTS do
		check("telling " .. v .. " is reached by some premises", seen[v] == true)
	end
	eq("and the same premises asks for the same telling for ever",
		CeroSecContent.variantOf(SECRET_A, 12, 34, "memo.txt"),
		CeroSecContent.variantOf(SECRET_A, 12, 34, "memo.txt"))
	check("while another save tells it differently somewhere",
		CeroSecContent.variantOf(SECRET_B, 12, 34, "memo.txt")
			~= CeroSecContent.variantOf(SECRET_A, 12, 34, "memo.txt")
		or CeroSecContent.variantOf(SECRET_B, 12, 35, "memo.txt")
			~= CeroSecContent.variantOf(SECRET_A, 12, 35, "memo.txt"))

	-- TWO OFFICES ARE TWO STORIES. Asked of built machines and not of the chooser,
	-- because what a player meets is a file on a disk: the same profile in two
	-- premises, and somewhere in the county the files differ. Walked until it is
	-- found, and the walk is bounded so that "never found" is a red.
	local function officeText(b1, b2)
		local state = CeroSecOS.newState("ksp-4-b")
		local _, _, logins = CeroSecContent.prefill(state,
			opts(SECRET_A, { premises = "Office", b1 = b1, b2 = b2 }))
		local out = {}
		for slot = 1, 3 do
			local login = logins[slot]
			if login ~= nil then
				local home = CeroSecOS.systemNode(state, "/home/" .. login)
				if home ~= nil and home.type == "dir" then
					local kids = CeroSecOS.childNames(home)
					for k = 1, #kids do
						local node = home.children[kids[k]]
						if node.type == "file" then out[#out + 1] = node.data or "" end
					end
				end
			end
		end
		table.sort(out)
		return table.concat(out, "\n@@\n")
	end
	local base = officeText(12, 34)
	local differs = false
	for b2 = 35, 60 do
		if officeText(12, b2) ~= base then
			differs = true
			-- The first one that differs answers the question. Walking the rest would
			-- prefill twenty-five more machines to learn nothing.
			break
		end
	end
	check("two offices in the county do not read the same", differs)

	-- AND NEITHER DOES THEIR MAIL, which is a separate assertion because the mail
	-- has a chooser of its own (mailStory) and the walk above reads only the homes.
	-- Pinning that chooser to telling 1 left everything above green, which is a
	-- mutation that passed and is the reason this block exists.
	-- THE SUBJECTS AND NOTHING ELSE, and that is the point of this reading. Compared
	-- whole, two offices' mailboxes differ because the LOGINS differ -- every To:
	-- line carries a different man's name -- so the assertion was satisfied by the
	-- people and went green with the telling pinned to 1. A subject line comes out
	-- of the catalogue and out of nothing else, so it is the one part of a mailbox
	-- that can only differ if the telling did.
	local function mailOf(b1, b2)
		local state = CeroSecOS.newState("ksp-4-b")
		local _, _, logins = CeroSecContent.prefill(state,
			opts(SECRET_A, { premises = "Office", b1 = b1, b2 = b2 }))
		local out, read = {}, {}
		for slot = 1, 3 do
			local login = logins[slot]
			-- ONE MAILBOX READ ONCE. Two slots can generate one login -- the name
			-- collided and the second slot kept it, which makes them one account -- and
			-- reading that box twice put a duplicate subject in the list. The telling
			-- was pinned to 1 and this walk still found a "difference": the collision,
			-- not the story. A witness satisfied by the wrong thing.
			if login ~= nil and not read[login] then
				read[login] = true
				local box = CeroSecOS.systemNode(state, CeroSecOS.mailPath(login))
				if box ~= nil then
					local lines = CeroSecOS.splitLines(box.data or "")
					for l = 1, #lines do
						if string.sub(lines[l], 1, 9) == "Subject: " then
							out[#out + 1] = lines[l]
						end
					end
				end
			end
		end
		table.sort(out)
		return table.concat(out, " | ")
	end
	local mailBase = mailOf(12, 34)
	check("and the office in the next town had other mail in it", mailBase ~= "")
	local mailDiffers = false
	for b2 = 35, 60 do
		if mailOf(12, b2) ~= mailBase then
			mailDiffers = true
			break
		end
	end
	check("two offices in the county do not hold the same mail", mailDiffers)
end

--
-- 4e. THE HISTORY: what he typed, who logged in, and what was in the mail
--
-- Three files that have to agree with each other and with the save's own clock,
-- and every one of them is read back through the COMMAND a survivor would use --
-- `last` out of CeroSecOSNet, `mail` out of CeroSecOSCron, CeroSecOS.historyLines
-- for what Up and Down walk -- rather than off the node. A bench that read the
-- bytes it had just written would prove the writer and nothing else; what has to
-- be true is that the machine's own programs can read them.
--
-- What is NOT here is the one thing this bench cannot hold: that a machine left
-- logged in really comes up at that man's prompt. That is the console's, the
-- console is the server's, and it is tests/window_test.lua's section on prefilling.
--

-- Every minute of the week before the save begins, as the machine would PRINT it.
-- Built once: a message's Date: header is proved by finding it in here, which is
-- the same question as "is this a moment before the save" asked in the one shape a
-- header carries -- and asking it by walking ten thousand formatDate calls per
-- header was thirty seconds of the suite.
local BEFORE_START = {}
for second = START - CeroSecContent.LOG_DAYS * 86400, START - 60, 60 do
	BEFORE_START[CeroSecOS.formatDate(second)] = true
end

-- A session for one slot of a built machine, by the credential a paper would name:
-- the derived password for a locked account and the empty one for an open account,
-- which is exactly what a survivor types.
local function sessionFor(state, profile, slot, login, b1, b2)
	local password = ""
	if profile.accounts[slot].pass then
		password = CeroSecContent.accountPassword(SECRET_A, b1 or 12, b2 or 34, slot,
			login)
	end
	return CeroSecOS.login(state, login, password)
end

-- Build one machine of a profile at a named square, and answer everything the
-- sections below ask of it.
local function build(id, secret, where)
	local state = CeroSecOS.newState("ksp-4-b")
	local o = opts(secret, where)
	o.premises = WORD_FOR[id]
	o.numbers = { "418-0100", "418-4477", "555-9012" }
	local got, password, logins, live = CeroSecContent.prefill(state, o)
	local mkey = CeroSecContent.machineKey(o.b1, o.b2, o.x, o.y, o.z)
	local slot = CeroSecContent.ownerSlot(secret, mkey, CeroSecContent.PROFILES[id])
	local owner = nil
	if slot ~= nil then owner = logins[slot] end
	return { state = state, id = got, password = password, logins = logins,
		live = live, mkey = mkey, slot = slot, owner = owner, opts = o }
end

do
	local liveSeen, deadSeen, dialled = 0, 0, 0
	for i = 1, #CeroSecContent.PROFILE_IDS do
		local id = CeroSecContent.PROFILE_IDS[i]
		local profile = CeroSecContent.PROFILES[id]
		if profile ~= nil then
			-- WHICH SQUARES, and it is a search and not a handful of numbers. The first
			-- draft walked four squares of an arithmetic progression and every one of
			-- them came back halted -- the roll is one in four and eight samples in a
			-- row missed it, which is a thing that happens one time in two hundred and
			-- fifty-six and had happened. A bench that then says "some machines were
			-- left logged in" is a bench that is red for no fault.
			--
			-- So the squares are chosen by what they ARE: one machine that was left
			-- logged in, two that were shut down, found by walking until they turn up.
			-- A profile that forbids an open session (the post) contributes none of the
			-- first, which is asserted below rather than worked around.
			local machines = {}
			local live, dead = 0, 0
			-- The post forbids an open session, so the walk must not go on looking for
			-- one: without this it walked all two hundred squares for that one profile
			-- and prefilled two hundred machines to find nothing, which is most of a
			-- minute of the suite spent proving a field is false.
			local wantLive = 1
			if profile.session == false then wantLive = 0 end
			for n = 0, 199 do
				if live >= wantLive and dead >= 2 then break end
				local m = build(id, SECRET_A, { x = 8130 + n, y = 9254 + n * 3 })
				if m.live ~= nil and live < 1 then
					live = live + 1
					machines[#machines + 1] = m
				elseif m.live == nil and dead < 2 then
					dead = dead + 1
					machines[#machines + 1] = m
				end
			end
			eq(id .. " is found logged in as often as its profile allows", live,
				wantLive)
			eq(id .. " is found shut down too", dead, 2)

			for n = 1, #machines do
				local m = machines[n]
				local where = id .. " machine " .. n
				local env = { now = START, devices = devicesFor(nil) }

				-- THE HISTORIES. Read through CeroSecOS.historyLines, as the account, which
				-- is what the window is handed when it opens: a history at the wrong mode or
				-- under the wrong owner reads as no history at all and this is what says so.
				if type(profile.accounts) == "table" then
					for a = 1, #profile.accounts do
						local login = m.logins[a]
						if login ~= nil then
							local session = sessionFor(m.state, profile, a, login)
							check(where .. " slot " .. a .. " (" .. login .. ") can log in",
								session ~= nil)
							local lines = CeroSecOS.historyLines(m.state, session)
							local path = "/home/" .. login .. "/" .. CeroSecOS.HISTORY_NAME
							local node = CeroSecOS.systemNode(m.state, path)
							check(where .. " " .. login .. " has a history", node ~= nil)
							eq(where .. " and it is his", node.owner, login)
							eq(where .. " at the history mode", node.mode,
								CeroSecOS.HISTORY_MODE)
							if login == m.owner then
								check(where .. " the owner's history is "
									.. CeroSecContent.HISTORY_MIN .. " to "
									.. (CeroSecContent.HISTORY_MIN + CeroSecContent.HISTORY_SPAN)
									.. " lines (" .. #lines .. ")",
									#lines >= CeroSecContent.HISTORY_MIN
										and #lines <= CeroSecContent.HISTORY_MIN
											+ CeroSecContent.HISTORY_SPAN)
								-- The tail, and the one place the two halves of "he never logged
								-- out" are held against each other.
								local last = lines[#lines]
								if m.live ~= nil then
									check(where .. " a machine left logged in did not halt itself ("
										.. tostring(last) .. ")", last ~= CeroSecContent.HIST_HALT)
								else
									eq(where .. " and a machine nobody was at was halted", last,
										CeroSecContent.HIST_HALT)
								end
							else
								check(where .. " a visitor's history is short (" .. #lines .. ")",
									#lines >= 1 and #lines <= 4)
							end
							-- EVERY LINE IS A COMMAND THIS MACHINE HAS. The shell's own lookup,
							-- on this machine, as this account: a word the shell has no file for
							-- and no word of its own is a line that prints "command not found"
							-- on the day a player presses Up.
							for l = 1, #lines do
								local line = lines[l]
								check(where .. ' history line fits 60 columns: "' .. line .. '"',
									#line <= CeroSecOS.COLS)
								check(where .. " history line is printable",
									not CeroSecOS.hasControlBytes(line))
								local word = string.match(line, "^([^%s]+)")
								check(where .. " history line " .. l .. " has a first word",
									word ~= nil)
								if word ~= nil and not CeroSecOS.isShellWord(word) then
									local why = CeroSecOS.whyNotRun(m.state, session, word,
										CeroSecOS.DEFAULT_PATH)
									eq(where .. ' history line ' .. l .. ' runs "' .. word
										.. '" (' .. line .. ")", why, nil)
								end
								-- A `cu` with a NUMBER after it is the telephone call, and the
								-- number has to be one this county really has: `cu -l /dev/radio0`
								-- is the radio station reaching its own TNC and is not a call at
								-- all, which is why the test is on the shape of the argument.
								local number = string.match(line, "^cu (%d%d%d%-%d%d%d%d)$")
								if number ~= nil then
									dialled = dialled + 1
									check(where .. " and the number it rang is a real one ("
										.. number .. ")", CeroSecOS.isPhoneNumber(number))
								end
								if string.sub(line, 1, 3) == "cu " and number == nil then
									check(where .. " and a cu with no number is a device (" .. line
										.. ")", string.find(line, "^cu %-l /dev/") ~= nil)
								end
							end
						end
					end
				end

				-- `last`, THE COMMAND. Root's, because /var/log/wtmp is 644 and root's and
				-- an ordinary account may read it -- but root is the account that certainly
				-- can, and what is under test here is the file and not the mode.
				local root = CeroSecOS.rootSession()
				local ok, out = run(m.state, root, "last", env)
				check(where .. " last runs", ok)
				check(where .. " and prints sessions (" .. #out .. ")", #out >= 4)
				eq(where .. " and its last line is where wtmp begins",
					string.sub(out[#out], 1, 12), "wtmp begins ")
				-- The records, read back through the machine's own parser, in the order
				-- the file has them: every one before the save begins, and at most one
				-- login with no logout behind it.
				local wtmp = CeroSecOS.systemNode(m.state, CeroSecOS.WTMP_PATH)
				check(where .. " has a wtmp", wtmp ~= nil)
				local recs = CeroSecOS.parseWtmp(wtmp.data or "")
				check(where .. " every wtmp line parses (" .. #recs .. ")",
					#recs == #CeroSecOS.splitLines(wtmp.data or ""))
				local open, opened, previous = 0, nil, 0
				for r = 1, #recs do
					check(where .. " wtmp record " .. r .. " is before the save begins",
						recs[r].at < START)
					check(where .. " wtmp record " .. r .. " is in order",
						recs[r].at >= previous)
					previous = recs[r].at
					eq(where .. " and it is on the console", recs[r].line,
						CeroSecOS.CONSOLE_LINE)
					if recs[r].kind == "in" then
						open = open + 1
						opened = recs[r].user
					else
						open = open - 1
					end
					check(where .. " and no two sessions are open at once on one console",
						open <= 1)
				end
				-- STILL LOGGED IN, and `last` is what a survivor reads it with. Exactly one
				-- such line on a machine somebody left, and none at all on one that was
				-- shut down.
				local still = 0
				for r = 1, #out do
					if string.find(out[r], "still logged in", 1, true) ~= nil then
						still = still + 1
					end
				end
				if m.live ~= nil then
					liveSeen = liveSeen + 1
					eq(where .. " last prints one open session", still, 1)
					eq(where .. " and it is the owner's", m.live.user, m.owner)
					eq(where .. " and wtmp's open record is his", opened, m.owner)
					eq(where .. " and the moment is the one wtmp holds", m.live.at,
						recs[#recs].at)
					check(where .. " and it is before the save begins", m.live.at < START)
					check(where .. " and the profile allows one at all",
						profile.session ~= false)
				else
					deadSeen = deadSeen + 1
					eq(where .. " last prints no open session", still, 0)
				end

				-- `mail`, THE COMMAND, as the owner. It is his mailbox at mode 600, so a
				-- mailbox written with the wrong owner is "permission denied" and a mailbox
				-- written in some other shape is a screenful of nothing.
				if m.owner ~= nil then
					local session = sessionFor(m.state, profile, m.slot, m.owner)
					local box = CeroSecOS.systemNode(m.state, CeroSecOS.mailPath(m.owner))
					check(where .. " the owner has mail", box ~= nil)
					if box ~= nil then
						eq(where .. " and the mailbox is his", box.owner, m.owner)
						eq(where .. " at the mail mode", box.mode, CeroSecOS.MAIL_MODE)
						check(where .. " and inside the mailbox ceiling ("
							.. #(box.data or "") .. ")",
							#(box.data or "") <= CeroSecOS.MAIL_BYTES)
						local mok, mout = run(m.state, session, "mail", env)
						check(where .. " mail runs", mok)
						local messages, subjects, dates = 0, 0, 0
						for l = 1, #mout do
							local line = mout[l]
							check(where .. ' mail line fits 60 columns: "' .. line .. '"',
								#line <= CeroSecOS.COLS)
							if string.sub(line, 1, 5) == "From " then messages = messages + 1 end
							if string.sub(line, 1, 4) == "To: " then
								eq(where .. " and every message is addressed to him",
									string.sub(line, 5), m.owner)
							end
							if string.sub(line, 1, 9) == "Subject: " then
								subjects = subjects + 1
							end
							if string.sub(line, 1, 6) == "Date: " then
								dates = dates + 1
								-- The date, in the shape `date` writes and the machine reads --
								-- and it has to be one of the days BEFORE the save begins, which
								-- is proved by finding it among them rather than by parsing it
								-- back: a message from after the outbreak started is the one
								-- thing in this file that could not have arrived.
								local when = string.sub(line, 7)
								check(where .. " message " .. dates
									.. " is dated in the week before the save (" .. when .. ")",
									BEFORE_START[when] == true)
							end
						end
						check(where .. " the owner's mailbox holds 3 to 6 messages ("
							.. messages .. ")", messages >= 3 and messages <= 6)
						-- One envelope line, one From:, one To:, one Date: and one Subject:
						-- per message, which is what makes `mail` readable at all.
						eq(where .. " every message has a subject", subjects, messages)
						eq(where .. " every message has a date", dates, messages)
						-- And the mailbox is emptied by reading it, which is what `mail` does.
						eq(where .. " and reading it empties the spool",
							CeroSecOS.systemNode(m.state, CeroSecOS.mailPath(m.owner)).data, "")
					end
				end
			end
		end
	end
	-- THE OUTBREAK WEEK IS REALLY IN THE LOG, and it is asked by the HOUR and not by
	-- counting lines against CeroSecContent.LOG_EVENT_COUNT: a count derived from the
	-- constant under test cannot fail when the constant goes to zero, which is a
	-- mutation that passed. The premises' own lines are written between seven in the
	-- morning and four in the afternoon and the outbreak's between midnight and five,
	-- so a line before six is a line only this change can have put there.
	do
		local nights = 0
		for i = 1, #CeroSecContent.PROFILE_IDS do
			local id = CeroSecContent.PROFILE_IDS[i]
			if CeroSecContent.PROFILES[id] ~= nil then
				local m = build(id, SECRET_A, { x = 8130, y = 9254 })
				local log = CeroSecOS.systemNode(m.state,
					CeroSecOS.LOG_PATH .. "/messages")
				if log ~= nil then
					local lines = CeroSecOS.splitLines(log.data or "")
					local night = 0
					for l = 1, #lines do
						local hour = tonumber(string.match(lines[l], "^%a%a%a%s+%d+ (%d%d):"))
						if hour ~= nil and hour < 6 then night = night + 1 end
					end
					check(id .. " has something in its log from the hours nobody was there ("
						.. night .. ")", night > 0)
					nights = nights + night
				end
			end
		end
		check("the county's own week is in every log (" .. nights .. ")", nights >= 10)
	end

	-- AND THE DRAFT IS ON SOME MACHINES AND NOT OTHERS, which is the whole of what
	-- "about half" means and is a roll rather than a rule. Nothing above could catch
	-- the roll being pinned to 100.
	do
		local with, without = 0, 0
		for n = 0, 19 do
			local m = build("office", SECRET_A, { x = 8130 + n, y = 9254 + n * 3 })
			if m.owner ~= nil then
				if CeroSecOS.systemNode(m.state, "/home/" .. m.owner .. "/draft.txt") ~= nil
					then with = with + 1
				else without = without + 1 end
			end
		end
		check("some desks have a half written page on them (" .. with .. ")", with > 0)
		check("and some do not (" .. without .. ")", without > 0)
	end

	check("some machines in the walk were left logged in (" .. liveSeen .. ")",
		liveSeen > 0)
	check("and most were not (" .. deadSeen .. ")", deadSeen > liveSeen)
	check("and somebody rang a number of his own region (" .. dialled .. ")",
		dialled > 0)
end

--
-- 4f. EVERY DATE IN THE MAIL IS BEFORE THE SAVE BEGINS, in every telling
--
-- Section 4e reads one telling of each profile's mail per machine. The `back`,
-- `hour` and `min` of every message of every telling are what decide whether it
-- could have arrived at all, so they are walked here off the catalogue -- and
-- against the same arithmetic the writer uses, which is the start DAY's midnight
-- and not the start moment.
--
do
	local messages, tellings = 0, 0
	local midnight = math.floor(START / 86400) * 86400
	for i = 1, #CeroSecContent.PROFILE_IDS do
		local id = CeroSecContent.PROFILE_IDS[i]
		local profile = CeroSecContent.PROFILES[id]
		if profile ~= nil and type(profile.mail) == "table" then
			eq(id .. " has CeroSecContent.VARIANTS tellings of its mail", #profile.mail,
				CeroSecContent.VARIANTS)
			for v = 1, #profile.mail do
				tellings = tellings + 1
				local story = profile.mail[v]
				local where = id .. " mail telling " .. v
				check(where .. " has 3 to 6 messages (" .. #story .. ")",
					#story >= 3 and #story <= 6)
				local previous = nil
				for n = 1, #story do
					messages = messages + 1
					local item = story[n]
					local at = midnight - (item.back or 0) * 86400
						+ (item.hour or 9) * 3600 + (item.min or 0) * 60
					check(where .. " message " .. n .. " is dated before the save begins ("
						.. CeroSecOS.formatDate(at) .. ")", at < START)
					check(where .. " message " .. n .. " is inside the outbreak week",
						(item.back or 0) <= CeroSecContent.LOG_DAYS)
					-- IN ORDER, because a mailbox is read from the top and a story whose
					-- third message came before its second is not a story.
					if previous ~= nil then
						check(where .. " message " .. n .. " is after the one before it",
							at > previous)
					end
					previous = at
					-- Every line of it, with names in, at sixty columns -- the headers are
					-- composed around it and add nothing to a body line's width.
					check(where .. " message " .. n .. " has a sender",
						type(item.from) == "string" and item.from ~= "")
					check(where .. " message " .. n .. " has a subject",
						type(item.subj) == "string" and item.subj ~= "")
					check(where .. " message " .. n .. " has a body",
						type(item.body) == "table" and #item.body > 0)
					local names = { owner = "pcoleman", staff1 = "torres",
						staff2 = "walker", staff3 = "dhensley", host = "acct-04-11" }
					local parts = { item.from, item.subj }
					for b = 1, #(item.body or {}) do parts[#parts + 1] = item.body[b] end
					for p = 1, #parts do
						local text = CeroSecContent.fillNames(parts[p], names)
						check(where .. ' message ' .. n .. ' line fits 60 columns: "'
							.. text .. '"', #text <= CeroSecOS.COLS)
						check(where .. " message " .. n .. " has no placeholder left",
							string.find(text, "[{}]") == nil)
						local bad = string.find(text, "[^\032-\126]")
						check(where .. " message " .. n .. " is printable ASCII (byte "
							.. tostring(bad) .. ")", bad == nil)
					end
					-- NOBODY WRITES TO HIMSELF. A sender that is a placeholder and a
					-- recipient that is a slot can be one man twice over, which is how the
					-- first draft of these stories read on one machine in three.
					if type(item.to) == "number" then
						check(where .. " message " .. n
							.. " is not from a placeholder to a slot",
							string.find(item.from, "{", 1, true) == nil)
					end
				end
			end
		end
	end
	check("every profile's mail is a story in three tellings (" .. tellings .. ")",
		tellings >= 30)
	check("and there are messages in them (" .. messages .. ")", messages >= 90)

	-- THE DRAFT, the same way: three tellings, and it stops in the middle of
	-- something. Held to ending without a full stop, because a draft that reads as a
	-- finished page is not a draft.
	local drafts = 0
	for i = 1, #CeroSecContent.PROFILE_IDS do
		local id = CeroSecContent.PROFILE_IDS[i]
		local profile = CeroSecContent.PROFILES[id]
		if profile ~= nil and type(profile.draft) == "table" then
			drafts = drafts + 1
			eq(id .. " has CeroSecContent.VARIANTS drafts", #profile.draft,
				CeroSecContent.VARIANTS)
			for v = 1, #profile.draft do
				local text = CeroSecContent.fillNames(profile.draft[v],
					{ owner = "pcoleman", staff1 = "torres", staff2 = "walker",
						staff3 = "dhensley", host = "acct-04-11" })
				check(id .. " draft " .. v .. " is inside the screen and the file",
					#text <= 1200)
				check(id .. " draft " .. v .. " has no placeholder left",
					string.find(text, "[{}]") == nil)
				for line in (text .. "\n"):gmatch("([^\n]*)\n") do
					check(id .. ' draft ' .. v .. ' line fits 60 columns: "' .. line .. '"',
						#line <= CeroSecOS.COLS)
				end
				check(id .. " draft " .. v .. " stops in the middle of something ("
					.. string.sub(text, -20) .. ")",
					string.find(text, "[%.%?!]$") == nil)
			end
		end
	end
	eq("every profile carries a draft", drafts, 11)
end

--
-- 4g. TWO MACHINES OF ONE OFFICE
--
-- The whole change in one section, and it is asked of built machines because what a
-- player meets is two computers in one room: the same company, the same people,
-- the same passwords, and two different men's desks with two different weeks on
-- them.
--
do
	local profile = CeroSecContent.PROFILES.office
	local first = deskFor("office", SECRET_A, 1)
	local second = deskFor("office", SECRET_A, 3)
	check("a square exists for the bookkeeper's desk", first ~= nil)
	check("and one for the third man's", second ~= nil)
	local a = build("office", SECRET_A, first)
	local b = build("office", SECRET_A, second)

	check("two machines of one office have two different owners ("
		.. tostring(a.owner) .. ", " .. tostring(b.owner) .. ")",
		a.owner ~= nil and b.owner ~= nil and a.owner ~= b.owner)

	-- THE SAME PEOPLE AND THE SAME PASSWORDS, which is what makes a paper in a
	-- dead man's pocket mean anything in either room.
	for slot = 1, #profile.accounts do
		eq("and the same person in slot " .. slot, a.logins[slot], b.logins[slot])
		local login = a.logins[slot]
		if login ~= nil and profile.accounts[slot].pass then
			local password =
				CeroSecContent.accountPassword(SECRET_A, 12, 34, slot, login)
			check("and his password opens both (" .. login .. ")",
				CeroSecOS.checkPassword(CeroSecOS.getUser(a.state, login), password)
					and CeroSecOS.checkPassword(CeroSecOS.getUser(b.state, login),
						password))
		end
	end
	eq("and the same root password", a.password, b.password)

	-- AND TWO DIFFERENT WEEKS.
	local function historyOf(m)
		local node = CeroSecOS.systemNode(m.state,
			"/home/" .. m.owner .. "/" .. CeroSecOS.HISTORY_NAME)
		if node == nil then return "" end
		return node.data or ""
	end
	check("two desks of one office hold two different histories",
		historyOf(a) ~= historyOf(b) and historyOf(a) ~= "")
	local function wtmpOf(m)
		local node = CeroSecOS.systemNode(m.state, CeroSecOS.WTMP_PATH)
		if node == nil then return "" end
		return node.data or ""
	end
	check("and two different sets of logins", wtmpOf(a) ~= wtmpOf(b))
	-- The files, which is where a player notices first.
	local function homeOf(m)
		local home = CeroSecOS.systemNode(m.state, "/home/" .. m.owner)
		local out = {}
		if home ~= nil and home.type == "dir" then
			local kids = CeroSecOS.childNames(home)
			for k = 1, #kids do out[#out + 1] = kids[k] end
		end
		return table.concat(out, " ")
	end
	check("and two different desks (" .. homeOf(a) .. " / " .. homeOf(b) .. ")",
		homeOf(a) ~= homeOf(b))

	-- THE MILITARY POST IS NEVER FOUND LOGGED IN, over a long walk of squares and
	-- both secrets: the rule is `session = false` and this is what says the rule
	-- holds rather than that it is written down.
	local posts = 0
	for _, secret in ipairs({ SECRET_A, SECRET_B }) do
		for n = 0, 59 do
			local mkey = CeroSecContent.machineKey(12, 34, 8130 + n, 9254 + n * 7, 0)
			check("the post at square " .. n .. " is not left logged in",
				not CeroSecContent.liveSession(secret, mkey,
					CeroSecContent.PROFILES.military))
			if CeroSecContent.liveSession(secret, mkey,
					CeroSecContent.PROFILES.office) then
				posts = posts + 1
			end
		end
	end
	-- And the rule is a ROLL and not "never": an office somewhere in that walk was.
	check("while offices in the same walk were (" .. posts .. ")", posts > 0)
end

--
-- 4h. MORE MACHINES THAN PEOPLE: the shop floor and the spare desk
--
-- The two complaints this answers were made of one save: a shop that sells
-- computers had six of them in a row and every one came up as the same back office
-- with the same two people, and an office with three people in it gave the fourth
-- and fifth desk an owner who already had one.
--
-- What decides is the REGISTER (CeroSecContent.deskRole) -- a table of what the
-- other machines of this premises already turned out to be -- and it is a table the
-- server keeps and saves. This bench is the register's own, so it hands it over
-- itself: a fresh one per premises, machine after machine, exactly as a player
-- switching them on one at a time hands it over.
--
-- THE HONEST COST, asserted rather than hidden: the ORDER decides which desk is
-- whose. What must not depend on the order is that no two machines share an owner
-- and that the people who do get a desk are the premises' own, and that is what the
-- two orders below are compared on.
--

-- One machine of a premises, switched on with the register in its hand. `room` is
-- the room the machine stands in, which is what tells a shop's sales floor from its
-- back room.
local function switchOn(id, secret, entry, n, room, b1, b2)
	local state = CeroSecOS.newState("ksp-4-b")
	local o = opts(secret, { premises = WORD_FOR[id], b1 = b1 or 12, b2 = b2 or 34,
		x = 8130 + n * 3, y = 9254 + n * 5, z = 0, desks = entry, room = room })
	local got, password, logins, live, role = CeroSecContent.prefill(state, o)
	local owner = nil
	if type(logins) == "table" then
		for slot = 1, 9 do
			-- WHOSE machine it is, read off the disk and not off the answer: the owner
			-- is the account whose home has work in it, which is what a player sees.
			local login = logins[slot]
			if login ~= nil then
				local home = CeroSecOS.systemNode(state, "/home/" .. login)
				if home ~= nil and home.type == "dir" then
					local kids = CeroSecOS.childNames(home)
					for k = 1, #kids do
						if string.sub(kids[k], 1, 1) ~= "." then owner = login end
					end
				end
			end
		end
	end
	return { state = state, id = got, password = password, logins = logins,
		live = live, role = role, owner = owner, opts = o }
end

do
	local DEMO = CeroSecContent.DEMO

	-- THE SHOP. Six machines: five on the sales floor, the sixth in the back room,
	-- and the back one is switched on LAST so that "the shop's own" cannot be an
	-- accident of being first.
	local entry = { desks = {} }
	local floors, staff = {}, nil
	for n = 1, 5 do
		floors[n] = switchOn("showroom", SECRET_A, entry, n, "electronicsstore")
	end
	staff = switchOn("showroom", SECRET_A, entry, 6, "electronicsstorage")

	eq("the shop's own machine is a desk", staff.role, "desk")
	check("and somebody's work is on it", staff.owner ~= nil)
	for n = 1, 5 do
		local m = floors[n]
		eq("display model " .. n .. " is a floor model", m.role, "floor")
		-- THE DEMO ACCOUNT, open, which is what a customer finds waiting.
		local demo = CeroSecOS.getUser(m.state, DEMO.login)
		check("display model " .. n .. " has the demo account", demo ~= nil)
		check("and it is open", CeroSecOS.checkPassword(demo, ""))
		-- AND THE SHOP'S PEOPLE ARE NOT ON IT. It is stock: the shop has not sold it,
		-- and a machine the public types at is not a machine with the staff on it.
		local _, ord = CeroSecOS.readUsers(m.state)
		eq("and the only accounts on it are root and demo (" ..
			table.concat(ord, " ") .. ")", #ord, 2)
		-- And not the factory account: a prefilled machine gives that one up, display
		-- models included, or root's hashed password has a way round it.
		eq("the factory account is off it too",
			CeroSecOS.getUser(m.state, CeroSecOS.FACTORY_USER), nil)
		for slot = 1, #CeroSecContent.PROFILES.showroom.accounts do
			local login = CeroSecContent.accountLogin(SECRET_A, 12, 34, slot)
			eq("and the shop's slot " .. slot .. " is not on it (" .. login .. ")",
				CeroSecOS.getUser(m.state, login), nil)
		end
		-- The three files in capitals, and nothing of anybody's work.
		for f = 1, #DEMO.files do
			local at = CeroSecOS.systemNode(m.state,
				"/home/" .. DEMO.login .. "/" .. DEMO.files[f].path)
			check("display model " .. n .. " carries " .. DEMO.files[f].path,
				at ~= nil and at.type == "file")
		end
		-- WHAT A CUSTOMER TYPED: two or three lines, and no week of anybody's work.
		local hist = CeroSecOS.systemNode(m.state,
			"/home/" .. DEMO.login .. "/" .. CeroSecOS.HISTORY_NAME)
		check("and a history somebody typed at it", hist ~= nil)
		local lines = CeroSecOS.splitLines(hist.data or "")
		check("of two or three lines (" .. #lines .. ")", #lines >= 2 and #lines <= 3)
		check("and nothing of the outbreak in it (" .. #lines .. ")",
			#lines < CeroSecContent.HISTORY_MIN)
		-- NO MAIL AND NOBODY LEFT LOGGED IN: none of that happened to this machine.
		eq("no mail box on a display model",
			CeroSecOS.systemNode(m.state, CeroSecOS.mailPath(DEMO.login)), nil)
		eq("and nobody was left logged in at it", m.live, nil)
		-- The dealer's card, and the dealer's name on the machine.
		eq("it carries the dealer's motd",
			CeroSecOS.systemNode(m.state, CeroSecOS.MOTD_PATH).data, DEMO.motd)
		eq("and the dealer's name on it", string.match(m.state.hostname, "^[a-z0-9]+"),
			DEMO.host)
		-- THE BOOT GATE, on a machine built by the other branch of the prefill.
		local ok, why = CeroSecOS.validate(m.state)
		check("and a display model passes the boot gate: " .. tostring(why), ok)
		-- AND THE PAPER IN THE DRAWER OPENS IT. Root is the PREMISES' on every
		-- machine of the shop, which is the whole reason a display model may be
		-- stock and still be openable by the note in the back-room drawer.
		local note = CeroSecContent.password(SECRET_A, CeroSecContent.rootKey(12, 34))
		check("and the drawer's paper opens root on it",
			CeroSecOS.checkPassword(CeroSecOS.getUser(m.state, "root"), note))
		eq("which is the same password the shop's own machine has", m.password,
			staff.password)
	end
	-- ONE STAFF MACHINE AND FIVE MODELS, counted, because a count is the assertion
	-- that cannot be satisfied by the wrong machine.
	local desks, models = 0, 0
	for _, v in pairs(entry.desks) do
		if type(v) == "number" then desks = desks + 1 end
		if v == CeroSecContent.DESK_FLOOR then models = models + 1 end
	end
	eq("six machines in the shop are one desk", desks, 1)
	eq("and five display models", models, 5)

	-- THE SAME SHOP, SWITCHED ON THE OTHER WAY ROUND: the back room first. The
	-- register cannot change what a room IS, so the answer is the same.
	local other = { desks = {} }
	local first = switchOn("showroom", SECRET_A, other, 6, "electronicsstorage")
	eq("the back room is the shop's own however early it is switched on", first.role,
		"desk")
	for n = 1, 5 do
		eq("and the floor is still the floor (" .. n .. ")",
			switchOn("showroom", SECRET_A, other, n, "electronicsstore").role, "floor")
	end

	-- A SHOP WHOSE ONLY COMPUTERS STAND ON THE FLOOR is a shop of display models,
	-- and the paper in its drawer still opens every one of them.
	local allFloor = { desks = {} }
	local only = switchOn("showroom", SECRET_A, allFloor, 1, "electronicsstore")
	eq("a shop with nothing in the back has display models only", only.role, "floor")
	check("and the drawer's paper still opens root on it",
		CeroSecOS.checkPassword(CeroSecOS.getUser(only.state, "root"),
			CeroSecContent.password(SECRET_A, CeroSecContent.rootKey(12, 34))))

	-- AND A MACHINE IN A ROOM THE MAP DID NOT NAME is stock too, which is the safe
	-- way round: the shop's ledger does not go on a machine the public types at.
	local unnamed = { desks = {} }
	eq("a machine in an unnamed room of a shop is stock",
		switchOn("showroom", SECRET_A, unnamed, 1, nil).role, "floor")
end

do
	-- THE SPARE DESK. An office has three people in it; this one has five machines,
	-- and they are switched on one at a time the way a player walks a building.
	local id = "office"
	local profile = CeroSecContent.PROFILES[id]
	eq("the office has three people in it", #profile.accounts, 3)

	local function walkOffice(order, secret)
		local entry = { desks = {} }
		local out, owners = {}, {}
		for i = 1, #order do
			local n = order[i]
			local m = switchOn(id, secret or SECRET_A, entry, n, "office")
			out[n] = m
			if m.role == "desk" then owners[#owners + 1] = m.owner end
		end
		table.sort(owners)
		return out, owners, entry
	end

	local machines, owners, entry = walkOffice({ 1, 2, 3, 4, 5 })
	local desks, spares = 0, 0
	for _, v in pairs(entry.desks) do
		if type(v) == "number" then desks = desks + 1 end
		if v == CeroSecContent.DESK_SPARE then spares = spares + 1 end
	end
	eq("five machines in a three-person office are three desks", desks, 3)
	eq("and two spare desks", spares, 2)
	eq("and three men with a desk each (" .. table.concat(owners, " ") .. ")",
		#owners, 3)
	-- NO TWO DESKS SHARE A MAN, which is the complaint in one assertion.
	for i = 2, #owners do
		check("and no two desks are the same man's (" .. owners[i] .. ")",
			owners[i] ~= owners[i - 1])
	end
	-- And they are the premises' own three people and not three of anything else.
	local staff = {}
	for slot = 1, 3 do
		staff[#staff + 1] = CeroSecContent.accountLogin(SECRET_A, 12, 34, slot)
	end
	table.sort(staff)
	eq("and they are the office's own three", table.concat(owners, " "),
		table.concat(staff, " "))

	-- WHATEVER THE ORDER. Four more orders, and what is compared is the SET of men
	-- with a desk -- which is the promise -- and not which machine each got, which
	-- is what the order really decides and is written down as costing that.
	local orders = {
		{ 5, 4, 3, 2, 1 }, { 3, 1, 5, 2, 4 }, { 2, 5, 1, 4, 3 }, { 4, 3, 1, 5, 2 },
	}
	for o = 1, #orders do
		local _, got, reg = walkOffice(orders[o])
		eq("the same three men have a desk in order " .. o .. " ("
			.. table.concat(got, " ") .. ")", table.concat(got, " "),
			table.concat(owners, " "))
		local d, s = 0, 0
		for _, v in pairs(reg.desks) do
			if type(v) == "number" then d = d + 1 end
			if v == CeroSecContent.DESK_SPARE then s = s + 1 end
		end
		eq("and still three desks in order " .. o, d, 3)
		eq("and still two spares in order " .. o, s, 2)
	end

	-- WHAT A SPARE DESK IS: the company's machine with nobody's work on it. The
	-- staff are on it, with their passwords -- it is the company's machine and a
	-- paper in a pocket has to open it -- and nobody's home has anything in it.
	local spare = nil
	for n = 1, 5 do
		if machines[n].role == CeroSecContent.DESK_SPARE then spare = machines[n] end
	end
	check("some machine of the office is a spare desk", spare ~= nil)
	eq("the company's name is still on it",
		string.match(spare.state.hostname, "^[a-z0-9]+"), profile.host)
	eq("and the company's own motd",
		CeroSecOS.systemNode(spare.state, CeroSecOS.MOTD_PATH).data, profile.motd)
	eq("and nobody's work is on it", spare.owner, nil)
	local demo = CeroSecOS.getUser(spare.state, CeroSecContent.DEMO.login)
	check("it came up on the dealer's disk", demo ~= nil)
	check("with the demo account open", CeroSecOS.checkPassword(demo, ""))
	for slot = 1, #profile.accounts do
		local login = spare.logins[slot]
		check("the office's slot " .. slot .. " is on the spare desk", login ~= nil)
		if login ~= nil and profile.accounts[slot].pass then
			local want = CeroSecContent.accountPassword(SECRET_A, 12, 34, slot, login)
			check("and his own password opens it (" .. login .. ")",
				CeroSecOS.checkPassword(CeroSecOS.getUser(spare.state, login), want))
		end
		if login ~= nil then
			local home = CeroSecOS.systemNode(spare.state, "/home/" .. login)
			if home ~= nil and home.type == "dir" then
				local kids = CeroSecOS.childNames(home)
				for k = 1, #kids do
					check("and his home on it holds only dot-files (" .. kids[k] .. ")",
						string.sub(kids[k], 1, 1) == ".")
				end
			end
		end
	end
	local ok, why = CeroSecOS.validate(spare.state)
	check("and a spare desk passes the boot gate: " .. tostring(why), ok)

	-- ASKED TWICE, ANSWERED THE SAME. A machine prefilled a second time -- the
	-- developer's reset, a machine carried out of the room and put back -- must not
	-- take a second slot, or the office runs out of people for the desks it has.
	local again = { desks = {} }
	local one = switchOn(id, SECRET_A, again, 1, "office")
	local twice = switchOn(id, SECRET_A, again, 1, "office")
	eq("a machine prefilled twice keeps its role", twice.role, one.role)
	eq("and its man", twice.owner, one.owner)
	local n = 0
	for _ in pairs(again.desks) do n = n + 1 end
	eq("and the register holds one machine, not two", n, 1)
end

do
	-- THE DEALER'S DISK IS A DIFFERENT DISK IN THE NEXT SAVE. Which telling of the
	-- three a premises reads is hashed on the secret, so a player who has read the
	-- pitch in one save has not read the one in the next.
	local function pitch(secret, b2)
		local entry = { desks = {} }
		local m = switchOn("showroom", secret, entry, 1, "electronicsstore", 12, b2)
		local at = CeroSecOS.systemNode(m.state, "/home/"
			.. CeroSecContent.DEMO.login .. "/DEMO.TXT")
		if at == nil then return "" end
		return at.data or ""
	end
	local base = pitch(SECRET_A, 34)
	check("a display model carries a sales pitch", base ~= "")
	local differs = false
	for b2 = 34, 60 do
		if pitch(SECRET_B, b2) ~= pitch(SECRET_A, b2) then differs = true break end
	end
	check("and the next save's shops sell it in other words", differs)

	-- AND TWO MODELS IN ONE WINDOW DO NOT CARRY ONE CUSTOMER'S HISTORY, which is
	-- the machine's own roll and not the premises'.
	local entry = { desks = {} }
	local seen, same = {}, 0
	for n = 1, 12 do
		local m = switchOn("showroom", SECRET_A, entry, n, "electronicsstore")
		local at = CeroSecOS.systemNode(m.state, "/home/"
			.. CeroSecContent.DEMO.login .. "/" .. CeroSecOS.HISTORY_NAME)
		local text = ""
		if at ~= nil then text = at.data or "" end
		if seen[text] then same = same + 1 end
		seen[text] = true
	end
	local kinds = 0
	for _ in pairs(seen) do kinds = kinds + 1 end
	check("twelve display models carry more than one history (" .. kinds .. ")",
		kinds > 1)
end

--
-- 5. The same secret twice is the same machine, and another secret is another one
--

do
	-- Byte for byte, which is what "deterministic" has to mean: a machine built
	-- twice from one secret is one machine, whatever order anything happened in.
	local function dump(node, at, out)
		out = out or {}
		at = at or ""
		out[#out + 1] = at .. "|" .. node.type .. "|" .. node.owner .. "|"
			.. tostring(node.mode) .. "|" .. tostring(node.data)
		if node.type == "dir" then
			local names = CeroSecOS.childNames(node)
			for i = 1, #names do dump(node.children[names[i]], at .. "/" .. names[i], out) end
		end
		return table.concat(out, "\n")
	end

	local first, second, other
	do
		local state = CeroSecOS.newState("ksp-4-b")
		CeroSecContent.prefill(state, opts(SECRET_A, { premises = "Office" }))
		first = dump(state.fs) .. "\nhost=" .. state.hostname
	end
	do
		local state = CeroSecOS.newState("ksp-4-b")
		CeroSecContent.prefill(state, opts(SECRET_A, { premises = "Office" }))
		second = dump(state.fs) .. "\nhost=" .. state.hostname
	end
	do
		local state = CeroSecOS.newState("ksp-4-b")
		CeroSecContent.prefill(state, opts(SECRET_B, { premises = "Office" }))
		other = dump(state.fs) .. "\nhost=" .. state.hostname
	end
	-- The salts are the one thing that is NOT derived -- CeroSecOS.newSalt is a
	-- counter, on purpose, so that two accounts with one password do not look the
	-- same -- so the stored hashes differ between two runs and the comparison is
	-- made with the passwd file's second field taken out.
	local function withoutHashes(text)
		return string.gsub(text, "%$cs1%$[0-9a-z]+%$[0-9a-f]+", "$cs1$")
	end
	eq("the same secret builds the same machine twice",
		withoutHashes(first), withoutHashes(second))
	check("another secret builds another machine",
		withoutHashes(other) ~= withoutHashes(first))

	-- And the passwords themselves, which is what a player notices.
	local a = CeroSecContent.password(SECRET_A, CeroSecContent.rootKey(12, 34))
	local b = CeroSecContent.password(SECRET_B, CeroSecContent.rootKey(12, 34))
	check("and another save's root password is another password", a ~= b)
	eq("while this save's is the same every time it is asked", a,
		CeroSecContent.password(SECRET_A, CeroSecContent.rootKey(12, 34)))

	-- The note and the machine, which is the pair that must never disagree. Asked
	-- the way the two sides ask it: the machine through prefill, the note through
	-- the derivation on its own.
	local state = CeroSecOS.newState("ksp-4-b")
	local _, machine = CeroSecContent.prefill(state,
		opts(SECRET_A, { premises = "Office" }))
	local note = CeroSecContent.password(SECRET_A, CeroSecContent.rootKey(12, 34))
	eq("the note in the drawer opens the machine on the desk", note, machine)
	check("and it really does log root in",
		CeroSecOS.checkPassword(CeroSecOS.getUser(state, "root"), note))

	-- A machine in another PREMISES has another root password, so one note is not
	-- a master key to the county.
	local elsewhere = CeroSecOS.newState("ksp-4-b")
	local _, other2 = CeroSecContent.prefill(elsewhere,
		opts(SECRET_A, { premises = "Office", b1 = 12, b2 = 35 }))
	check("another premises is another root password", other2 ~= machine)
	check("and this note does not open that machine",
		not CeroSecOS.checkPassword(CeroSecOS.getUser(elsewhere, "root"), note))

	-- Two machines in ONE premises are two desks of one company: the same root
	-- password, and the SAME PEOPLE on them. That is what makes a paper found on a
	-- body in the car park mean anything -- a corpse cannot say which desk its owner
	-- sat at, so an account keyed on the machine would be an account the note could
	-- not name.
	local second2 = CeroSecOS.newState("ksp-9-c")
	local _, samePremises, logins2 = CeroSecContent.prefill(second2,
		opts(SECRET_A, { premises = "Office", x = 9000, y = 1 }))
	eq("a second machine in the same premises takes the same root password",
		samePremises, machine)
	local _, _, logins1 = CeroSecContent.prefill(CeroSecOS.newState("ksp-4-b"),
		opts(SECRET_A, { premises = "Office" }))
	eq("and the same people", logins2[1], logins1[1])
	-- And a machine in ANOTHER premises has other people on it.
	local _, _, logins3 = CeroSecContent.prefill(CeroSecOS.newState("ksp-4-b"),
		opts(SECRET_A, { premises = "Office", b1 = 12, b2 = 35 }))
	check("while another premises has its own", logins3[1] ~= logins1[1])

	-- THE PAPER IN A POCKET. An ordinary account's login and password, derived from
	-- the premises alone, by the two calls a note makes -- and it logs in.
	do
		local slots = CeroSecContent.lockedSlots(CeroSecContent.PROFILES.office)
		check("the office has an account with a password on it", #slots > 0)
		local slot = slots[1]
		local login = CeroSecContent.accountLogin(SECRET_A, 12, 34, slot)
		local password = CeroSecContent.accountPassword(SECRET_A, 12, 34, slot, login)
		local who = CeroSecOS.getUser(state, login)
		check("the login a paper names is on the machine (" .. login .. ")", who ~= nil)
		check("and the password beside it logs him in",
			CeroSecOS.checkPassword(who, password))
		check("and it is not root's", password ~= note)
		check("and root is not what the paper names", login ~= "root")
	end
end

--
-- 6. The seed library: every script RUNS
--
-- A script nobody ran is a script that does not work. Each one is written onto a
-- fresh machine through the ordinary write path, made executable, and run with
-- the arguments the library recorded for it, with exactly the devices it declared
-- standing around it.
--

do
	local names = {}
	for name in pairs(CeroSecContent.SCRIPTS) do names[#names + 1] = name end
	table.sort(names)
	check("the library has scripts in it", #names > 0)

	for i = 1, #names do
		local name = names[i]
		local script = CeroSecContent.SCRIPTS[name]
		check(name .. " is a file name the machine will take",
			CeroSecOS.isValidFileName(name))
		check(name .. " is a script name", string.find(name, "%.sh$") ~= nil)
		check(name .. " has text", type(script.text) == "string" and script.text ~= "")
		check(name .. " opens with the hash-bang",
			string.sub(script.text, 1, 9) == "#!/bin/sh")
		check(name .. " is executable (" .. tostring(script.mode) .. ")",
			script.mode == 755)
		check(name .. " is inside MAX_FILE_BYTES (" .. #script.text .. ")",
			#script.text <= CeroSecOS.MAX_FILE_BYTES)
		for line in (script.text .. "\n"):gmatch("([^\n]*)\n") do
			check(name .. ' line fits 60 columns: "' .. line .. '" (' .. #line .. ")",
				#line <= CeroSecOS.COLS)
		end
		check(name .. " says how it is run", type(script.args) == "table")
		-- A script that reads $1 and records no arguments is a script that has got
		-- out of the usage rule below by declaring itself argument-free. Asked of the
		-- TEXT, because the text is the only honest witness to what it wants.
		check(name .. " that reads $1 records an argument",
			string.find(script.text, "$1", 1, true) == nil or #script.args > 0)
		check(name .. " records the lines typed at it if it asks anything",
			string.find(script.text, "read ", 1, true) == nil
				or type(script.input) == "table")

		-- And now run it.
		local state = CeroSecOS.newState("ksp-4-b")
		local session = CeroSecOS.login(state, "admin", "")
		check(name .. ": the bench can log in", session ~= nil)
		local path = "/home/admin/" .. name
		local done, why =
			CeroSecOS.writeFile(state, session, path, script.text, false, START)
		check(name .. " goes onto a machine: " .. tostring(why), done ~= nil)
		-- The files it declared it wants standing beside it, and nothing else: the
		-- other half of `needs`, written under the account's own home the way the
		-- devices are stubbed one to one (see the head of devicesFor).
		if type(script.needs) == "table" and type(script.needs.files) == "table" then
			for f = 1, #script.needs.files do
				local file = script.needs.files[f]
				local put, fwhy = CeroSecOS.writeFile(state, session,
					"/home/admin/" .. file.path, file.text, false, START)
				check(name .. " gets " .. tostring(file.path) .. ": " .. tostring(fwhy),
					put ~= nil)
			end
		end
		local env = { now = START, devices = devicesFor(script.needs) }

		local ok, out = run(state, session, "chmod 755 " .. name, env)
		check(name .. ": chmod works", ok)

		local line = "./" .. name
		for a = 1, #script.args do line = line .. " " .. script.args[a] end
		local ran, lines, turns, job, used = run(state, session, line, env, script.input)
		check(name .. " runs: " .. table.concat(lines, " / "), ran)
		check(name .. " printed something", #lines > 0)
		-- Under budget, which is the other half of "it runs": a script that only
		-- finishes because the bench gave it two thousand turns is a script that
		-- would be killed on a real machine (`killed: cpu limit`).
		check(name .. " finishes in a handful of turns (" .. turns .. ")", turns < 50)
		-- And the lines recorded for it really play it to the end. A game left at a
		-- question is a game whose `input` nobody finished writing, and it would
		-- otherwise pass as "it ran" on the strength of its first prompt.
		check(name .. " is over and not still asking (" .. tostring(job.state) .. ")",
			CeroSecOS.jobIsOver(job))
		if type(script.input) == "table" then
			check(name .. " uses the lines recorded for it (" .. used .. " of "
				.. #script.input .. ")", used == #script.input)
		end
		for l = 1, #lines do
			check(name .. ' output fits 60 columns: "' .. lines[l] .. '"',
				#lines[l] <= CeroSecOS.COLS)
		end

		-- And with NO arguments, which is the other way it will be run: by somebody
		-- who found it and typed its name. It must say how it is used and not fall
		-- over.
		--
		-- Asked of a script that TAKES an argument, and of no other: a program with
		-- no arguments at all -- a game -- has no wrong way to be run, and the run
		-- above already was the bare one. What stops a script from getting out of
		-- this by declaring `args = {}` is the $1 check at the top of the loop.
		if #script.args > 0 then
			local bare, bareLines = run(state, session, "./" .. name, env)
			check(name .. " with no arguments says something", #bareLines > 0)
			check(name .. " with no arguments does not say sh had an error",
				string.find(table.concat(bareLines, " "), "syntax error", 1, true) == nil)
			check(name .. " with no arguments is not a nil call",
				string.find(table.concat(bareLines, " "), "attempt to", 1, true) == nil)
			-- A script run with no arguments must SAY SO and must not claim success:
			-- unconditional, because written as "if it failed, it must print usage" the
			-- requirement quietly stops being checked the day a script starts exiting 0
			-- with nothing to do.
			check(name .. " with no arguments does not claim success", not bare)
			check(name .. " with no arguments prints a usage line",
				string.find(bareLines[1] or "", "usage", 1, true) ~= nil)
		end

		-- The machine is still a machine afterwards.
		local vok, vwhy = CeroSecOS.validate(state)
		check(name .. " leaves a machine that still boots: " .. tostring(vwhy), vok)
	end

	-- lights.sh, by name, because what it is FOR is the one thing the loop above
	-- cannot ask: that it actually reached the devices it was given.
	do
		local script = CeroSecContent.SCRIPTS["lights.sh"]
		check("lights.sh is in the library", script ~= nil)
		local state = CeroSecOS.newState("ksp-4-b")
		local session = CeroSecOS.login(state, "admin", "")
		CeroSecOS.writeFile(state, session, "/home/admin/lights.sh", script.text,
			false, START)
		local devices = devicesFor(script.needs)
		local env = { now = START, devices = devices }
		run(state, session, "chmod 755 lights.sh", env)
		local ok = run(state, session, "./lights.sh light0 light1", env)
		check("lights.sh runs on its own devices", ok)
		eq("and it wrote to both of them", table.concat(devices.writes, ","),
			"light0=off,light1=off")
	end
end

--
-- 6b. THE SYSOP'S KIT: the board, set up as root and then CALLED
--
-- Section 6 runs every script once, alone, on a bare machine. That is not a
-- board. A board is five programs in /usr/local/bin, two accounts with homes, a
-- file in /usr/local/lib that both of them may write, and a caller working the
-- menu -- and every one of those is a thing the five programs do to EACH OTHER.
-- So this section builds the whole of it the way the README says to, out of the
-- floppy, and then types at it.
--
-- What it is really for, in one line: the menu is the only program in this mod
-- that RUNS OTHER PROGRAMS, and nothing in section 6 can see a nested `sh` at
-- all.
--

do
	local entry = CeroSecContent.diskById("BBS")
	check("the BBS disk is in the catalogue", entry ~= nil)

	-- The README names the five programs, by name. Section 7 already holds every
	-- README to naming everything beside it and only what is beside it; this says
	-- the same thing the other way round for the one disk whose files are a KIT --
	-- a program a caller is never told about is a program nobody will run.
	local readme = nil
	for i = 1, #entry.files do
		if entry.files[i].name == "README.TXT" then readme = entry.files[i].text end
	end
	check("the disk carries a README", type(readme) == "string")
	local PROGRAMS = { "bbs.sh", "read.sh", "post.sh", "board.sh", "setup.sh" }
	for i = 1, #PROGRAMS do
		check("the README names " .. PROGRAMS[i],
			string.find(readme, PROGRAMS[i], 1, true) ~= nil)
		check(PROGRAMS[i] .. " is in the seed library",
			CeroSecContent.SCRIPTS[PROGRAMS[i]] ~= nil)
		check(PROGRAMS[i] .. " is under 1200 bytes ("
			.. #CeroSecContent.SCRIPTS[PROGRAMS[i]].text .. ")",
			#CeroSecContent.SCRIPTS[PROGRAMS[i]].text <= 1200)
	end
	-- The line the sysop is told to put in a .profile has to be the path the
	-- programs really end up at, which is setup.sh's own P and nothing else.
	check("the README gives the .profile line",
		string.find(readme, "sh /usr/local/bin/bbs.sh", 1, true) ~= nil)
	check("and the one command that sets the machine up",
		string.find(readme, "sh /mnt/setup.sh /usr/local/lib/bbs", 1, true) ~= nil)
	check("and the nightly tar of the mail",
		string.find(readme, "tar cf /mnt/backup /var/mail", 1, true) ~= nil)

	-- A driver that remembers the QUESTIONS as well as the answers. `run` above
	-- hands back what was printed, and a pager's whole existence is a question --
	-- "-- more -- " is not output, it is the prompt on a waiting job -- so a bench
	-- that only read the lines could not tell a paged screen from an unpaged one.
	-- Everything every program in this section ever printed, in one place. A
	-- script is a list of commands and a line that is not one of them is not a
	-- syntax error: the shell says `command not found`, the line does nothing, and
	-- the script runs on to its last `echo` and exits 0. So a bench that reads only
	-- the status of these five would be green with a dead line in the middle of the
	-- menu. This is what catches that, and it is asked of every line of output the
	-- section produced rather than of any one run.
	local said = {}
	local function drive(state, session, line, env, answers)
		if session.shvars == nil then session.shvars = {} end
		local job = CeroSecOS.promptJob(state, session, line, session.shvars,
			session.status)
		if job == nil then return false, {}, {} end
		-- `marks` is how many lines had been printed when each question went up,
		-- which is the only way to say "the first screenful was a screenful": the
		-- prompt is not a line of output and never appears among them.
		local out, asks, marks, turns, at = {}, {}, {}, 0, 1
		while not CeroSecOS.jobIsOver(job) and turns < 4000 do
			turns = turns + 1
			CeroSecOS.jobStep(state, job, env, 1000)
			for k = 1, #job.out do out[#out + 1] = job.out[k] end
			job.out = {}
			if job.state == "waiting" and job.ask ~= nil then
				asks[#asks + 1] = tostring(job.ask.text)
				marks[#marks + 1] = #out
				if answers == nil or at > #answers then break end
				CeroSecOS.jobInput(state, job, answers[at], env)
				at = at + 1
			elseif job.state == "sleeping" then
				break
			end
		end
		for k = 1, #job.out do out[#out + 1] = job.out[k] end
		session.status = job.status
		for k = 1, #out do said[#said + 1] = out[k] end
		return job.status == 0, out, asks, job, at - 1, marks
	end

	local function found(lines, want)
		return string.find(table.concat(lines, "\n"), want, 1, true) ~= nil
	end
	local function countOf(list, want)
		local n = 0
		for i = 1, #list do if list[i] == want then n = n + 1 end end
		return n
	end

	local state = CeroSecOS.newState("bbs-4-b")
	local env = { now = START, nowMs = 0, devices = devicesFor(nil) }
	local rootSession = CeroSecOS.login(state, "root", "")
	check("the bench can be root", rootSession ~= nil)

	-- THE SYSOP'S OWN THREE STEPS, in his order and through the shell, because
	-- the point of a kit is that the steps in the README are the steps that work.
	state.floppy = CeroSecContent.diskData(entry, START)
	local ok, lines = drive(state, rootSession, "mount /dev/fd0 /mnt", env)
	check("the disk mounts: " .. table.concat(lines, " / "), ok)
	for _, who in ipairs({ "alice", "bob" }) do
		local made, why = drive(state, rootSession, "useradd " .. who, env)
		check("useradd " .. who .. ": " .. table.concat(why, " / "), made)
	end

	local ranSetup, setupOut = drive(state, rootSession,
		"sh /mnt/setup.sh /usr/local/lib/bbs", env)
	check("setup.sh runs as root: " .. table.concat(setupOut, " / "), ranSetup)
	local dir = CeroSecOS.getNode(state, rootSession, "/usr/local/lib/bbs")
	check("setup.sh made the board's directory", dir ~= nil and dir.type == "dir")
	eq("and left it open to everybody", dir.mode, 777)
	local board = CeroSecOS.getNode(state, rootSession, "/usr/local/lib/bbs/board")
	check("setup.sh made the board file", board ~= nil and board.type == "file")
	eq("and left it writable by everybody", board.mode, 666)
	eq("and it is root's", board.owner, "root")
	for i = 1, #PROGRAMS do
		local name = PROGRAMS[i]
		local node = CeroSecOS.getNode(state, rootSession, "/usr/local/bin/" .. name)
		-- setup.sh copies the four a caller runs and not itself: an installer that
		-- installed itself would be a fifth program in everybody's PATH that only
		-- root can do anything with.
		if name == "setup.sh" then
			eq("setup.sh does not copy itself into the path", node, nil)
		else
			check("setup.sh copied " .. name .. " into /usr/local/bin", node ~= nil)
			eq(name .. " is executable there", node.mode, 755)
		end
	end
	check("the machine still boots after setup.sh",
		(CeroSecOS.validate(state)))

	-- AND NOW A CALLER. Everything below is alice at the menu, with the answers
	-- she types, which is the only way any of this is ever used.
	local alice = CeroSecOS.login(state, "alice", "")
	check("alice can log in", alice ~= nil)
	local MENU = "sh /usr/local/bin/bbs.sh"

	-- P, to `all`: one copy in every mailbox and one posting on the board.
	local ranP, outP, asksP = drive(state, alice, MENU, env,
		{ "P", "all", "the water", "It is back on at my end.", ".", "q" })
	check("the menu runs: " .. table.concat(outP, " / "), ranP)
	check("it asked who to post to", countOf(asksP, "to (a name, or all): ") == 1)
	check("and for a subject", countOf(asksP, "subject: ") == 1)
	check("and took the body a line at a time", countOf(asksP, "> ") >= 3)
	check("and said where it went: " .. table.concat(outP, " / "),
		found(outP, "Posted to all.") and found(outP, "On the board too."))
	-- EVERY account with a home, which is what `all` means and what the README
	-- says: a caller left out is a caller who never hears from the board again.
	-- The rule the script really uses is `ls /home`, because /etc/passwd is 600
	-- and root's on this machine and a caller cannot read it -- so the list is
	-- every account whose home is UNDER /home, which is admin and the two callers.
	for _, who in ipairs({ "admin", "alice", "bob" }) do
		local box = CeroSecOS.systemNode(state, CeroSecOS.mailPath(who))
		check("all put a copy in " .. who .. "'s mailbox",
			box ~= nil and string.find(box.data or "", "It is back on at my end.",
				1, true) ~= nil)
		check("and it is from alice, with her subject",
			box ~= nil and string.find(box.data or "", "Subject: the water", 1, true) ~= nil)
	end
	-- And root is NOT on that list, root's home being /root. Asserted rather than
	-- left to be noticed: the board is the callers', the sysop reads his own mail,
	-- and the day somebody writes that line another way this says which it was.
	eq("and none in root's, root's home not being under /home",
		CeroSecOS.systemNode(state, CeroSecOS.mailPath("root")), nil)
	-- The board itself: the three headers the script writes, then the body.
	board = CeroSecOS.getNode(state, rootSession, "/usr/local/lib/bbs/board")
	local text = board.data or ""
	check("the board carries the poster's name",
		string.find(text, "From: alice", 1, true) ~= nil)
	check("and a date", string.find(text, "Date: ", 1, true) ~= nil)
	check("and the subject", string.find(text, "Subject: the water", 1, true) ~= nil)
	check("and the body under them",
		string.find(text, "It is back on at my end.", 1, true) ~= nil)

	-- B: the board, read back through the menu by somebody who is not alice.
	local bobSession = CeroSecOS.login(state, "bob", "")
	local ranB, outB = drive(state, bobSession, MENU, env, { "b", "q" })
	check("bob can read the board: " .. table.concat(outB, " / "), ranB)
	check("and it is alice's posting on it", found(outB, "From: alice"))

	-- N, twice: the new messages, and then none, which is the whole of what the
	-- lastread pointer is for.
	local ranN, outN = drive(state, bobSession, MENU, env, { "n", "q" })
	check("bob's new mail: " .. table.concat(outN, " / "), ranN)
	check("the board's own posting is in it", found(outN, "It is back on at my end."))
	local seen = CeroSecOS.getNode(state, bobSession, "/home/bob/.bbs_seen")
	check("and .bbs_seen was written", seen ~= nil and seen.type == "file")
	eq("with the number of messages read", (string.gsub(seen.data or "", "%s", "")), "1")
	local again = select(2, drive(state, bobSession, MENU, env, { "n", "q" }))
	check("and a second look says there is nothing new: "
		.. table.concat(again, " / "), found(again, "No new mail. 1 read."))

	-- One more message, and the pointer moves by one and not to the top.
	drive(state, rootSession, "echo the bridge | mail -s roads bob", env)
	local third = select(2, drive(state, bobSession, MENU, env, { "n", "q" }))
	check("the next message shows: " .. table.concat(third, " / "),
		found(third, "the bridge"))
	check("and the first one does not come round again",
		not found(third, "It is back on at my end."))
	seen = CeroSecOS.getNode(state, bobSession, "/home/bob/.bbs_seen")
	eq("the pointer is two now", (string.gsub(seen.data or "", "%s", "")), "2")

	-- R, W, L, U and a key that is none of them. Every one of those is a branch
	-- of the ladder, and a menu whose keys have been proved one at a time is a
	-- menu: `ps`, `who` and `last` all answer through the same nested `sh`.
	local ranR, outR = drive(state, bobSession, MENU, env, { "r", "q" })
	check("R reads the whole box: " .. table.concat(outR, " / "), ranR)
	check("which is both messages", found(outR, "the bridge")
		and found(outR, "It is back on at my end."))
	local ranU, outU = drive(state, bobSession, MENU, env, { "u", "q" })
	check("U lists the accounts with homes: " .. table.concat(outU, " / "), ranU)
	check("alice among them", found(outU, "alice"))
	check("and bob", found(outU, "bob"))
	local ranL = drive(state, bobSession, MENU, env, { "l", "q" })
	check("L asks last and comes back", ranL)
	local ranW = drive(state, bobSession, MENU, env, { "w", "q" })
	check("W asks who and comes back", ranW)
	local ranZ, outZ = drive(state, bobSession, MENU, env, { "z", "q" })
	check("a key that is not one of them is answered: "
		.. table.concat(outZ, " / "), ranZ and found(outZ, "N R P B W L U Q?"))
	-- Quitting, which is what the loop is held by: a menu that could not be left
	-- is a caller who has to be cut off at the exchange.
	local ranQ, outQ, asksQ, job = drive(state, bobSession, MENU, env, { "Q" })
	check("Q leaves the menu", ranQ and found(outQ, "Goodbye."))
	check("and the job is over", CeroSecOS.jobIsOver(job))
	eq("with nothing left asking", #asksQ, 1)

	-- THE PAGER, and it is asserted on the PROMPT and not on the lines: a screen
	-- that was not paged prints exactly the same text, all at once, and a bench
	-- reading the text could not tell the difference. Nineteen messages of seven
	-- lines is a hundred and thirty-three lines, so the prompt comes up seven
	-- times over -- and eighteen of them at a time is what says the page is the
	-- page the terminal has (CeroSecOS.ROWS is 20, two of them the prompt's).
	do
		for i = 1, 19 do
			drive(state, rootSession,
				"echo line " .. i .. " | mail -s n" .. i .. " alice", env)
		end
		local answers = {}
		for i = 1, 30 do answers[i] = "" end
		answers[#answers + 1] = "q"
		local ranPage, outPage, asksPage, _, _, marks =
			drive(state, alice, "sh /usr/local/bin/read.sh /var/mail/alice", env,
				answers)
		check("a long mailbox reads: " .. tostring(ranPage), ranPage)
		local pages = countOf(asksPage, "-- more -- ")
		-- Not "more than a few": the number of prompts is the number of pages the
		-- file really has, less the last one, and the file is whatever is left of
		-- the box after the spool's own trimming (MAIL_LINES) has had it. Written
		-- as the arithmetic so that a pager that showed the wrong number of lines
		-- per page is red here rather than merely different.
		local box = CeroSecOS.systemNode(state, CeroSecOS.mailPath("alice"))
		local held = #CeroSecOS.splitLines(box.data or "")
		local want = math.ceil(held / 18) - 1
		check("the box is longer than a screen (" .. held .. " lines)", held > 18)
		eq("and it stopped once for every page but the last", pages, want)
		-- The first page is a page and not the whole file: the last message cannot
		-- be on the glass before the first prompt. Nineteen lines and not eighteen,
		-- because read.sh says how many are new above the first page of them.
		check("the first screenful is one screenful (" .. tostring(marks[1]) .. ")",
			marks[1] ~= nil and marks[1] <= 20)
		check("and the whole box was not printed before the first question",
			marks[1] < #outPage)
	end

	-- AND A MAILBOX WITH NOTHING IN IT, which is the machine a board starts on:
	-- read.sh must not divide by the absence of a file.
	do
		local fresh = CeroSecOS.newState("bbs-4-c")
		local fenv = { now = START, nowMs = 0, devices = devicesFor(nil) }
		local froot = CeroSecOS.login(fresh, "root", "")
		fresh.floppy = CeroSecContent.diskData(entry, START)
		drive(fresh, froot, "mount /dev/fd0 /mnt", fenv)
		drive(fresh, froot, "useradd carol", fenv)
		drive(fresh, froot, "sh /mnt/setup.sh /usr/local/lib/bbs", fenv)
		local carol = CeroSecOS.login(fresh, "carol", "")
		local ranC, outC = drive(fresh, carol, MENU, fenv, { "n", "r", "b", "q" })
		check("a caller with no mail is answered: " .. table.concat(outC, " / "),
			ranC)
		check("and told so in the words read.sh uses",
			found(outC, "usage: read.sh") or found(outC, "No new mail")
				or found(outC, "message"))
		check("the machine still boots after all of it", (CeroSecOS.validate(fresh)))
	end

	-- AND NOTHING IN ANY OF IT WENT WRONG QUIETLY. The four refusals a script can
	-- carry for ever without failing: a word that is not a command, a file it may
	-- not touch, a line the parser would not take, and a nil call in the engine.
	local whole = table.concat(said, "\n")
	for _, bad in ipairs({ "command not found", "permission denied",
			"syntax error", "attempt to", "no such file" }) do
		check("nothing the board printed says \"" .. bad .. "\"",
			string.find(whole, bad, 1, true) == nil)
	end
end

--
-- 7. The disk catalogue
--

do
	local total, ids, labels = 0, {}, {}
	for i = 1, #CeroSecContent.DISKS do
		local entry = CeroSecContent.DISKS[i]
		local where = "disk " .. tostring(entry.id)
		check(where .. " has an id", type(entry.id) == "string" and entry.id ~= "")
		check(where .. " has a unique id", ids[entry.id] == nil)
		ids[entry.id] = true
		local weight = tonumber(entry.weight) or 0
		check(where .. " has a weight of nothing or more", weight >= 0)
		total = total + weight

		if entry.label ~= nil then
			check(where .. " has a label the machine will take",
				CeroSecOS.labelOk(entry.label))
			check(where .. " has a unique label", labels[entry.label] == nil)
			labels[entry.label] = true
			-- Upper case, because a 1993 disk came out of a DOS machine.
			eq(where .. " is labelled in capitals", entry.label,
				string.upper(entry.label))
		end

		local disk, written = CeroSecContent.diskData(entry, START)
		check(where .. " makes a disk", type(disk) == "table")
		eq(where .. " is at this build's floppy version", disk.v,
			CeroSecOS.FLOPPY_VERSION)
		eq(where .. " carries its label onto the disk", disk.label, entry.label)
		-- THE SLOT'S OWN GATE, ceilings included, which is the one that says the
		-- disk can be put in a machine at all.
		local ok, why = CeroSecOS.validateDisk(disk, true)
		check(where .. " passes the slot's gate: " .. tostring(why), ok)

		if #entry.files == 0 then
			eq(where .. " is blank", disk.fs, nil)
			eq(where .. " wrote nothing", written, 0)
		else
			eq(where .. " wrote every one of its files", written, #entry.files)
			local root = disk.fs
			check(where .. " has a filesystem on it", type(root) == "table")
			local names = CeroSecOS.childNames(root)
			-- One node per entry, counted over the whole TREE and not over the root:
			-- a distribution disk has a MAN directory on it, and the six pages in it
			-- are six entries the root has never heard of. The root's own children
			-- are the entries with no slash in their name.
			local flat = 0
			for f = 1, #entry.files do
				if string.find(entry.files[f].name, "/", 1, true) == nil then
					flat = flat + 1
				end
			end
			eq(where .. " has one root entry per flat file", #names, flat)
			local deep = walk(root)
			local made = 0
			for _ in pairs(deep) do made = made + 1 end
			eq(where .. " has one node per entry, the root itself aside", made - 1,
				#entry.files)
			local _, bytes = CeroSecOS.subtreeUsage(root)
			check(where .. " is inside FLOPPY_BYTES (" .. bytes .. ")",
				bytes <= CeroSecOS.FLOPPY_BYTES)
			local nodes = CeroSecOS.subtreeUsage(root)
			check(where .. " is inside FLOPPY_NODES (" .. nodes .. ")",
				nodes <= CeroSecOS.FLOPPY_NODES)

			-- Every README names every file beside it. A disk whose README describes
			-- a program that is not on it is a disk that lies to the player, and it
			-- is exactly the mistake a catalogue written by hand makes.
			local readme = nil
			for n = 1, #names do
				if string.find(names[n], "^README") ~= nil then
					readme = root.children[names[n]]
				end
			end
			check(where .. " has a README.TXT", readme ~= nil)
			-- Every node on the disk, at whatever depth: the name is one the machine
			-- will take, what is in it carries no control byte, and every line of it
			-- fits the glass. A page in MAN is read with `cat` like anything else.
			for path, node in pairs(deep) do
				if path ~= "/" then
					local leaf = string.match(path, "([^/]+)$")
					check(where .. path .. " is a name the machine will take",
						CeroSecOS.isValidFileName(leaf))
					check(where .. path .. " carries no control byte",
						not CeroSecOS.hasControlBytes(node.data or ""))
					for line in ((node.data or "") .. "\n"):gmatch("([^\n]*)\n") do
						check(where .. path .. ' line fits 60 columns: "' .. line
							.. '" (' .. #line .. ")", #line <= CeroSecOS.COLS)
					end
				end
			end
			-- And the README names every entry BESIDE it, which is the root's own
			-- children and not the tree: a directory is named and what is in it is
			-- listed by `ls`, exactly as a distribution disk's own README did it.
			for n = 1, #names do
				local name = names[n]
				local node = root.children[name]
				if node ~= readme then
					check(where .. "'s README names " .. name,
						string.find(readme.data or "", name, 1, true) ~= nil)
				end
			end
			-- And every name the README names is on the disk. The other direction,
			-- because a README that mentions a file nobody shipped is the same lie
			-- read the other way round.
			for named in string.gmatch(readme.data or "", "[A-Za-z0-9_%-]+%.[A-Za-z]+") do
				check(where .. "'s README names only files that are on it: " .. named,
					root.children[named] ~= nil)
			end
		end
	end
	check("the weights are a share of a hundred (" .. total .. ")",
		total > 0 and total <= 100)

	-- The roll, at both ends and over the whole range. What is left over is blank,
	-- and that is asserted rather than assumed: a weighting error that made every
	-- disk in the county a UTILITIES disk would otherwise be invisible.
	local blanks, filled = 0, 0
	for roll = 1, 100 do
		local entry = CeroSecContent.diskForRoll(roll)
		if entry == nil then blanks = blanks + 1 else filled = filled + 1 end
	end
	eq("every weighted roll lands on an entry", filled, total)
	eq("and the rest of the box is blank", blanks, 100 - total)
	check("most of a box is blank", blanks > filled)
	eq("a roll of nothing is blank", CeroSecContent.diskForRoll(0), nil)
	eq("junk for a roll is blank", CeroSecContent.diskForRoll("x"), nil)

	-- The slots the world-content work, part 2 fills. An id in neither list is a catalogue entry nobody
	-- wrote down.
	for i = 1, #CeroSecContent.DISK_SLOTS do
		local id = CeroSecContent.DISK_SLOTS[i]
		local entry = CeroSecContent.diskById(id)
		if entry ~= nil then
			check("a filled slot has a weight (" .. id .. ")",
				(tonumber(entry.weight) or 0) > 0)
		end
	end
	local slots = {}
	for i = 1, #CeroSecContent.DISK_SLOTS do slots[CeroSecContent.DISK_SLOTS[i]] = true end
	for i = 1, #CeroSecContent.DISKS do
		local id = CeroSecContent.DISKS[i].id
		-- The diagnostics disk is the fourth case and is named by a constant, not
		-- by a string typed here: it is not loot, so it is not a weighted slot, and
		-- it is not UTILITIES or BLANK either. Section 7c is what holds it to being
		-- unreachable from the box.
		check("catalogue entry " .. id .. " is either shipped or a named slot",
			slots[id] ~= nil or id == "UTILITIES" or id == "BLANK"
				or id == CeroSecContent.DIAG_DISK)
	end

	-- And a disk out of the catalogue MOUNTS on a machine and its files can be
	-- read, which is the thing a player actually does with it.
	do
		local state = CeroSecOS.newState("ksp-4-b")
		local session = CeroSecOS.login(state, "admin", "")
		local disk = CeroSecContent.diskData(CeroSecContent.diskById("UTILITIES"), START)
		state.floppy = disk
		local env = { now = START, devices = devicesFor(nil) }
		local ok, lines = run(state, session, "mount /dev/fd0 /mnt", env)
		check("a catalogue disk mounts: " .. table.concat(lines, " / "), ok)
		local listed = select(2, run(state, session, "ls /mnt", env))
		local text = table.concat(listed, " ")
		check("and README.TXT is on it (" .. text .. ")",
			string.find(text, "README.TXT", 1, true) ~= nil)
		local read = select(2, run(state, session, "cat /mnt/README.TXT", env))
		check("and it can be read", #read > 0)
		local vok, vwhy = CeroSecOS.validate(state)
		check("and the machine still boots with it in the drive: " .. tostring(vwhy), vok)
	end
end

--
-- 7b. THE LATE FILE: the one disk whose story needs a place
--
-- A floppy is created in loot and loot has no location, so a BBS list cannot be
-- printed with the numbers of the region it is found in at the moment it is made.
-- One file of such an entry ships as a STUB and is filled the first time the disk
-- goes into a machine, out of that machine's own exchange.
--
-- The pure half is here: what a stub is, what fills it, and that it is filled ONCE.
-- That the numbers really come off the inserting machine's square is
-- CeroSecNet.fillLateDisk's, and it is walked in docs/PARCOURS-TEST.md.
--

do
	-- Every entry that declares a late file really has one, with text. `late`
	-- naming a file nobody shipped would be an entry that can never be filled and
	-- nothing else would ever say so.
	local lateCount = 0
	for i = 1, #CeroSecContent.DISKS do
		local entry = CeroSecContent.DISKS[i]
		if entry.late ~= nil then
			lateCount = lateCount + 1
			local name, stub = CeroSecContent.lateFile(entry)
			eq("disk " .. entry.id .. " has the late file it names", name, entry.late)
			check("and the stub is text", type(stub) == "string" and stub ~= "")
		end
	end
	eq("nothing declares a late file it has not got",
		CeroSecContent.lateFile({ late = "NOPE.TXT", files = {} }), nil)
	-- AND THERE IS ONE. Everything below this is inside `if lateCount > 0`, because
	-- the mechanism is for a catalogue that has such an entry and there was a build
	-- with none -- so without this line, a change that dropped `late` off the BBS list
	-- would take the whole of section 7b out of the suite in silence and the bench
	-- would still say it passed.
	check("the shipped catalogue has a late entry in it (" .. lateCount .. ")",
		lateCount > 0)

	-- The numbers a region hands over, in the shape CeroSecNet.directory answers
	-- them in. Written down rather than taken off a world: there is no world here,
	-- which is the whole reason the layout half is a pure function.
	local HERE = { "418-2201", "418-0347", "418-7719", "418-4488" }
	local THERE = { "233-1010", "233-9002" }

	if lateCount > 0 then
		local entry = nil
		for i = 1, #CeroSecContent.DISKS do
			if CeroSecContent.DISKS[i].late ~= nil then entry = CeroSecContent.DISKS[i] end
		end
		local name, stub = CeroSecContent.lateFile(entry)

		local disk = CeroSecContent.diskData(entry, START)
		local got, gotName = CeroSecContent.lateEntryFor(disk)
		eq("a disk off a shelf is the entry it came from", got, entry)
		eq("and the file waiting to be filled is the one named", gotName, name)
		eq("which still holds the stub", disk.fs.children[name].data, stub)

		check("the fill writes it", CeroSecContent.fillLate(disk, 418, HERE, START))
		local filled = disk.fs.children[name].data
		check("with the exchange on it", string.find(filled, "418", 1, true) ~= nil)
		for i = 1, #HERE do
			check("and with " .. HERE[i] .. " on it",
				string.find(filled, HERE[i], 1, true) ~= nil)
		end
		check("and a name beside the number",
			string.find(filled, CeroSecContent.BBS_NAMES[1], 1, true) ~= nil
				or string.find(filled, CeroSecContent.BBS_NAMES[2], 1, true) ~= nil
				or string.find(filled, CeroSecContent.BBS_NAMES[3], 1, true) ~= nil)
		for line in (filled .. "\n"):gmatch("([^\n]*)\n") do
			check('a filled line fits 60 columns: "' .. line .. '" (' .. #line .. ")",
				#line <= CeroSecOS.COLS)
		end
		-- And the disk is still a disk a machine will take, ceilings included: the
		-- list is bigger than the stub it replaced.
		local ok, why = CeroSecOS.validateDisk(disk, true)
		check("and the slot still takes it: " .. tostring(why), ok)
		local nodes, bytes = CeroSecOS.subtreeUsage(disk.fs)
		check("inside FLOPPY_BYTES (" .. bytes .. ")", bytes <= CeroSecOS.FLOPPY_BYTES)
		check("inside FLOPPY_NODES (" .. nodes .. ")", nodes <= CeroSecOS.FLOPPY_NODES)

		-- ONCE. The disk is not a late one any more, and the second machine it goes
		-- into does not print its own county over the first one's.
		eq("a filled disk is no longer waiting", CeroSecContent.lateEntryFor(disk), nil)
		check("so the next machine fills nothing",
			not CeroSecContent.fillLate(disk, 233, THERE, START))
		eq("and the list is still the one it was printed with", disk.fs.children[name].data,
			filled)
		check("with none of the other county's numbers on it",
			string.find(disk.fs.children[name].data, THERE[1], 1, true) == nil)

		-- A survivor's own work at that name is his. This is the rule upgradeSystem
		-- uses on /bin and it is the rule here: what is exactly what shipped is the
		-- system's to replace, and anything else is somebody's.
		do
			local his = CeroSecContent.diskData(entry, START)
			his.fs.children[name].data = "the ones that still answer:"
			eq("a disk somebody wrote over is not waiting to be filled",
				CeroSecContent.lateEntryFor(his), nil)
			check("and nothing overwrites him",
				not CeroSecContent.fillLate(his, 418, HERE, START))
			eq("his line is still there", his.fs.children[name].data,
				"the ones that still answer:")
		end

		-- A region with nothing named in it prints nothing, and the stub says so
		-- rather than the disk carrying an empty heading.
		do
			local empty = CeroSecContent.diskData(entry, START)
			check("a county with no listings fills nothing",
				not CeroSecContent.fillLate(empty, 418, {}, START))
			eq("and the stub is untouched", empty.fs.children[name].data, stub)
		end

		-- Every other disk in the county, and every kind of junk, answers nothing.
		eq("a blank disk is not waiting",
			CeroSecContent.lateEntryFor(CeroSecOS.newFloppy()), nil)
		eq("nor is a disk with somebody's own sticker on it",
			CeroSecContent.lateEntryFor(CeroSecOS.newFloppy("PAYROLL")), nil)
		eq("nor is the utilities disk",
			CeroSecContent.lateEntryFor(
				CeroSecContent.diskData(CeroSecContent.diskById("UTILITIES"), START)), nil)
		eq("nor is nothing at all", CeroSecContent.lateEntryFor(nil), nil)
		check("and filling nothing is refused",
			not CeroSecContent.fillLate(nil, 418, HERE, START))
		check("and so is filling with junk for numbers",
			not CeroSecContent.fillLate(CeroSecContent.diskData(entry, START), 418, nil,
				START))

		-- The list is a fact about the REGION and not about the order the map handed
		-- its zones over. Byte for byte, and that is the strong form: two survivors
		-- reading two copies of the disk read the SAME PAGE, and not merely the same
		-- numbers in some order. It is what the sort inside bbsText is for, and the
		-- weaker version of this assertion -- "a number keeps its board" -- is what
		-- caught the first draft, which paired a name to a number's POSITION.
		do
			local a = CeroSecContent.bbsText(418, HERE)
			local shuffled = {}
			for i = #HERE, 1, -1 do shuffled[#shuffled + 1] = HERE[i] end
			local b = CeroSecContent.bbsText(418, shuffled)
			eq("the page is the same page however the county was enumerated", a, b)
			local function nameFor(text, number)
				for line in (text .. "\n"):gmatch("([^\n]*)\n") do
					if string.find(line, number, 1, true) ~= nil then
						return string.match(line, "^  (.-) %.")
					end
				end
				return nil
			end
			eq("and a number keeps its board", nameFor(a, HERE[1]),
				nameFor(b, HERE[1]))
			-- And a number keeps it when the rest of the county changes around it,
			-- which is what "decided by the number" has to mean.
			local alone = CeroSecContent.bbsText(418, { HERE[1] })
			eq("even on a list of one", nameFor(alone, HERE[1]), nameFor(a, HERE[1]))
		end

		-- More listings than a page holds: cut to BBS_MAX and not printed past the
		-- disk. A region with four hundred premises in it is a region whose book is
		-- four hundred lines and whose FLOPPY is four thousand bytes.
		do
			local many = {}
			for i = 1, 400 do many[i] = "418-" .. string.format("%04d", i) end
			local big = CeroSecContent.diskData(entry, START)
			check("a county of four hundred still fills",
				CeroSecContent.fillLate(big, 418, many, START))
			local lines = CeroSecOS.splitLines(big.fs.children[name].data)
			check("with a page of them and no more (" .. #lines .. ")",
				#lines <= CeroSecContent.BBS_MAX + 6)
			local _, bytes2 = CeroSecOS.subtreeUsage(big.fs)
			check("and inside the floppy (" .. bytes2 .. ")",
				bytes2 <= CeroSecOS.FLOPPY_BYTES)
			local dok, dwhy = CeroSecOS.validateDisk(big, true)
			check("and the slot takes it: " .. tostring(dwhy), dok)
		end

		-- And the filled disk really READS on a machine, through the drive, which is
		-- the thing a player actually does with it.
		do
			local state = CeroSecOS.newState("ksp-4-b")
			local session = CeroSecOS.login(state, "admin", "")
			local mine = CeroSecContent.diskData(entry, START)
			CeroSecContent.fillLate(mine, 418, HERE, START)
			state.floppy = mine
			local env = { now = START, devices = devicesFor(nil) }
			local mok, mlines = run(state, session, "mount /dev/fd0 /mnt", env)
			check("a filled disk mounts: " .. table.concat(mlines, " / "), mok)
			local read = select(2, run(state, session, "cat /mnt/" .. name, env))
			local text = table.concat(read, " ")
			check("and the numbers are on the screen (" .. text .. ")",
				string.find(text, HERE[1], 1, true) ~= nil)
			local vok, vwhy = CeroSecOS.validate(state)
			check("and the machine still boots: " .. tostring(vwhy), vok)
		end
	end
end

--
-- 7c. THE DIAGNOSTICS DISK: the machine's own test suite, RUN
--
-- Every other bench in here runs on lua5.1. The game runs Kahlua, and the shell
-- is the half of the mod no pure-function probe can reach: the commands, the
-- pipes, the redirects, the arithmetic reader and the filesystem. So the mod
-- ships a floppy with a test suite on it, and this section runs that suite under
-- the engine and holds it to FAIL 0.
--
-- Which is not the same as running it in the game, and is not meant to be. This
-- says the suite is RIGHT -- twenty-six checks that pass on the canonical VM.
-- docs/RELEASE.md is what says somebody ran it on the other one.
--
do
	local entry = CeroSecContent.diskById(CeroSecContent.DIAG_DISK)
	check("the diagnostics disk is in the catalogue", entry ~= nil)
	eq("it is labelled for the drive", entry.label, "CEROSEC DIAGNOSTICS")
	-- NEVER IN LOOT, asserted over the whole box and not off the field: weight 0
	-- is the mechanism, "no roll lands on it" is the requirement, and it is the
	-- requirement that is checked.
	eq("it has no weight", tonumber(entry.weight) or 0, 0)
	for roll = 1, 100 do
		check("no roll of the box lands on it (" .. roll .. ")",
			CeroSecContent.diskForRoll(roll) ~= entry)
	end

	-- THE HASH THE SCRIPT CHECKS ITSELF AGAINST, held to the engine's own answer.
	-- The script has that string baked into it -- it has to, there being no lua5.1
	-- in the game to ask -- and a baked number with nothing holding it is a number
	-- that goes on being green after the thing it measures has moved. This is what
	-- holds it: the day HASH_ROUNDS or the mixer changes, this line is red and the
	-- floppy is rewritten, instead of the in-game run going red for a reason
	-- nobody can place.
	local script = nil
	for i = 1, #entry.files do
		if entry.files[i].name == "selftest.sh" then script = entry.files[i].text end
	end
	check("the disk carries selftest.sh", type(script) == "string")
	local hash = CeroSecOS.hashPassword(CeroSecSelfTest.PASS_TEXT,
		CeroSecSelfTest.PASS_SALT)
	check("and the hash baked into it is the engine's own (" .. hash .. ")",
		string.find(script, hash, 1, true) ~= nil)
	check("and it is the text and salt the engine was asked about",
		string.find(script, "mkpasswd " .. CeroSecSelfTest.PASS_TEXT .. " "
			.. CeroSecSelfTest.PASS_SALT, 1, true) ~= nil)

	-- And now RUN it, on a fresh machine, as an ordinary account, with the disk in
	-- the drive and mounted the way a survivor mounts one.
	local state = CeroSecOS.newState("ksp-4-b")
	local session = CeroSecOS.login(state, "admin", "")
	check("the bench can log in", session ~= nil)
	local disk, written = CeroSecContent.diskData(entry, START)
	eq("the disk took all of its files", written, #entry.files)
	state.floppy = disk
	-- The shell's own clock and its own millisecond clock, because the suite has a
	-- `sleep 1` in it: a job that sleeps is off the processor until env.nowMs comes
	-- round, so a bench with no millisecond clock would hang at that line for two
	-- thousand turns and then call it a failure.
	local env = { now = START, nowMs = 0, up = 12345,
		devices = devicesFor(nil) }
	local ok, lines = run(state, session, "mount /dev/fd0 /mnt", env)
	check("the disk mounts: " .. table.concat(lines, " / "), ok)

	local ran, out = runSleeping(state, session, "sh /mnt/selftest.sh", env)
	local said = table.concat(out, " / ")
	-- The verdict line, and it is read off the LAST line rather than searched for
	-- anywhere in the output: a failure line has the check's name in it and could
	-- otherwise be mistaken for the summary.
	--
	-- Both halves, because either alone is weak. "The last line is a verdict" is what
	-- caught the disk shipped without a world-writable RESULTS.TXT -- the write
	-- refused, `permission denied` came out after the summary, and the last line was
	-- not a verdict any more -- and "a verdict was printed at all" is what stops the
	-- first half from being satisfied by a suite that printed nothing but a verdict.
	local verdict = out[#out]
	check("the suite printed a verdict (" .. said .. ")", verdict ~= nil)
	check("the last thing it said IS the verdict and nothing came after it: " .. said,
		string.match(verdict or "", "^PASS %d+ FAIL %d+$") ~= nil)
	-- FAIL 0 first and by itself, because that is the requirement; the pass count
	-- is asserted beside it so that a suite whose checks have quietly stopped
	-- running cannot be green for having run none.
	check("and nothing failed: " .. said,
		string.find(verdict or "", "FAIL 0", 1, true) ~= nil)
	local passed = tonumber(string.match(verdict or "", "PASS (%d+)") or "0")
	check("and it ran every check it has (" .. passed .. ")", passed >= 26)
	-- The script's own verdict lines are what a check IS, so the number of them is
	-- what the pass count has to agree with. A check somebody adds without the
	-- count following is this line.
	local declared = 0
	for _ in string.gmatch(script, "p=%$%(%(p%+1%)%)") do declared = declared + 1 end
	eq("as many checks as the script declares", passed, declared)
	check("and it said so on its own exit status", ran)
	for i = 1, #out do
		check('a line of it fits 60 columns: "' .. out[i] .. '"',
			#out[i] <= CeroSecOS.COLS)
	end

	-- The file it leaves on the disk, which is what somebody who ran it while
	-- nobody was watching reads afterwards.
	local results = CeroSecOS.getNode(state, session, "/mnt/RESULTS.TXT")
	check("it wrote RESULTS.TXT on the disk", results ~= nil)
	check("with the verdict in it (" .. tostring(results and results.data) .. ")",
		results ~= nil and string.find(results.data or "", "FAIL 0", 1, true) ~= nil)
	-- Which it could only do because the stub ships world-writable: /mnt is root's
	-- and the account running the suite is not.
	eq("because the stub ships world-writable", results.mode, 666)

	-- It took its scratch files away with it, both because a suite that fills a
	-- survivor's home is a suite nobody runs twice and because the disk quota is
	-- the one thing a script can break on a real machine.
	local home = CeroSecOS.getNode(state, session, "/home/admin")
	local left = {}
	local names = CeroSecOS.childNames(home)
	for i = 1, #names do
		if string.find(names[i], "^st%.") ~= nil then left[#left + 1] = names[i] end
	end
	eq("and left no scratch files behind (" .. table.concat(left, " ") .. ")",
		#left, 0)

	-- And the machine is still a machine. The suite makes directories, changes
	-- modes and removes files, which is the whole of what a script can do to one.
	local vok, vwhy = CeroSecOS.validate(state)
	check("the machine still boots afterwards: " .. tostring(vwhy), vok)
	local sok, swhy = CeroSecOS.systemOk(state)
	check("and its system is still whole: " .. tostring(swhy), sok)

	-- A MUTATION, so that "FAIL 0" is known to be an assertion and not a sentence
	-- the script prints either way. One check is turned into a lie and the suite
	-- has to notice, name it, and come back non-zero.
	do
		local broken = string.gsub(script, "n=echo; e=hi;", "n=echo; e=HI;", 1)
		check("the mutation changed the script", broken ~= script)
		-- The same sticker, because one of the checks reads the label out of
		-- `mount`: a mutant labelled anything else fails TWO checks and the one
		-- being proved would be hidden among them.
		local hurt = { id = "MUTANT", label = entry.label, weight = 0, files = {} }
		for i = 1, #entry.files do
			local file = entry.files[i]
			local text = file.text
			if file.name == "selftest.sh" then text = broken end
			hurt.files[i] = { name = file.name, mode = file.mode, text = text }
		end
		local s2 = CeroSecOS.newState("ksp-4-c")
		local ses2 = CeroSecOS.login(s2, "admin", "")
		s2.floppy = CeroSecContent.diskData(hurt, START)
		local env2 = { now = START, nowMs = 0, up = 12345, devices = devicesFor(nil) }
		run(s2, ses2, "mount /dev/fd0 /mnt", env2)
		local ran2, out2 = runSleeping(s2, ses2, "sh /mnt/selftest.sh", env2)
		local said2 = table.concat(out2, " / ")
		check("a broken check is NOT reported as a pass: " .. said2,
			string.find(out2[#out2] or "", "FAIL 1", 1, true) ~= nil)
		check("and the failing check is named: " .. said2,
			string.find(said2, "echo: HI vs hi", 1, true) ~= nil)
		check("and the suite comes back non-zero", not ran2)
	end
end

--
-- 7d. THREE TELLINGS OF A DISK
--
-- Section 7 weighs and reads every entry in the telling it gets by default, which
-- is the first. This one reads ALL THREE of every entry, because a telling nobody
-- built is a telling that ships broken: a line four characters longer than the
-- glass, a README naming a file that is only on one of them, a disk that fits in
-- 4096 bytes in one voice and not in another.
--
-- And it proves the two things the mechanism rests on. The tellings really DIFFER
-- -- three copies of one text is one text with extra work in front of it -- and the
-- choice is STABLE once the disk is written: what persists is the bytes in disk.fs,
-- so nothing rolls again at read time and a disk read twice is the same disk. That
-- is asserted through the item hook, which is where the roll is really made.
--

do
	-- Every path on a disk and what is in it, as one string, so two disks can be
	-- compared byte for byte in one assertion and a difference can be printed.
	local function dump(root)
		local nodes = walk(root)
		local paths = {}
		for path in pairs(nodes) do paths[#paths + 1] = path end
		table.sort(paths)
		local out = {}
		for i = 1, #paths do
			out[#out + 1] = paths[i] .. "\1" .. tostring(nodes[paths[i]].data)
		end
		return table.concat(out, "\2")
	end

	local told = 0
	for i = 1, #CeroSecContent.DISKS do
		local entry = CeroSecContent.DISKS[i]
		local where = "disk " .. tostring(entry.id)
		local varies = false
		for f = 1, #entry.files do
			local file = entry.files[f]
			if type(file.texts) == "table" then
				varies = true
				-- Exactly three, and the same number for every file there is: a file
				-- somebody wrote two tellings of is a file two disks in three share,
				-- which is the whole of what this was for.
				eq(where .. "/" .. file.name .. " has every telling", #file.texts,
					CeroSecContent.VARIANTS)
				check(where .. "/" .. file.name .. " carries no second shape",
					file.text == nil)
				for v = 1, #file.texts do
					for w = v + 1, #file.texts do
						check(where .. "/" .. file.name .. " telling " .. v .. " is not "
							.. "telling " .. w, file.texts[v] ~= file.texts[w])
					end
				end
			end
			-- A LATE file is one shape and can only be one shape: the fill decides
			-- whether a disk is still waiting by comparing the file byte for byte
			-- against the catalogue's own stub (CeroSecContent.lateFile), and three
			-- stubs would be two disks in three that never get their listings.
			if entry.late ~= nil and file.name == entry.late then
				check(where .. "'s late file is one shape", type(file.text) == "string"
					and file.texts == nil)
			end
		end

		-- All three, built, weighed and read. The disk the catalogue makes for a
		-- telling is the disk a player finds, so every question section 7 asks of
		-- the first is asked of the other two as well.
		local seen = {}
		for v = 1, CeroSecContent.VARIANTS do
			local at = where .. " telling " .. v
			local disk, written = CeroSecContent.diskData(entry, START, v)
			check(at .. " makes a disk", type(disk) == "table")
			eq(at .. " wrote every one of its files", written, #entry.files)
			local ok, why = CeroSecOS.validateDisk(disk, true)
			check(at .. " passes the slot's gate: " .. tostring(why), ok)
			if #entry.files > 0 then
				local root = disk.fs
				local nodes, bytes = CeroSecOS.subtreeUsage(root)
				check(at .. " is inside FLOPPY_BYTES (" .. bytes .. ")",
					bytes <= CeroSecOS.FLOPPY_BYTES)
				check(at .. " is inside FLOPPY_NODES (" .. nodes .. ")",
					nodes <= CeroSecOS.FLOPPY_NODES)
				-- NO PLACEHOLDER SURVIVES, in any telling of any file. A survivor
				-- reading "ask {staff3} about it" is reading a bug; the names are put
				-- in at build time (CeroSecContent.diskNames) and a brace on the glass
				-- means one was spelt wrong in the catalogue.
				for path, node in pairs(walk(root)) do
					if path ~= "/" then
						local data = node.data or ""
						check(at .. path .. " has no brace left in it",
							string.find(data, "{", 1, true) == nil
								and string.find(data, "}", 1, true) == nil)
						for line in (data .. "\n"):gmatch("([^\n]*)\n") do
							check(at .. path .. ' line fits 60 columns: "' .. line .. '" ('
								.. #line .. ")", #line <= CeroSecOS.COLS)
						end
					end
				end
				-- And the README of THIS telling names exactly what is beside it in
				-- THIS telling. Both directions, as section 7 asks it of the first:
				-- a README that names a file nobody shipped and a file no README names
				-- are the same lie read from the two ends.
				local names = CeroSecOS.childNames(root)
				local readme = nil
				for n = 1, #names do
					if string.find(names[n], "^README") ~= nil then
						readme = root.children[names[n]]
					end
				end
				check(at .. " has a README.TXT", readme ~= nil)
				for n = 1, #names do
					if root.children[names[n]] ~= readme then
						check(at .. "'s README names " .. names[n],
							string.find(readme.data or "", names[n], 1, true) ~= nil)
					end
				end
				for named in string.gmatch(readme.data or "", "[A-Za-z0-9_%-]+%.[A-Za-z]+") do
					check(at .. "'s README names only files that are on it: " .. named,
						root.children[named] ~= nil)
				end
				-- The tellings are not the same disk. Held over the WHOLE tree rather
				-- than over one file, because what a player meets is the disk.
				local text = dump(root)
				for w = 1, #seen do
					if varies then
						check(at .. " is not telling " .. w, text ~= seen[w])
					else
						-- And an entry with no `texts` on it is the SAME disk in every
						-- telling, which is the other half of the rule: a program and a
						-- data file do not vary, and an entry that quietly started
						-- varying would be a bench proving one disk in three.
						eq(at .. " is telling " .. w .. " over again", text, seen[w])
					end
				end
				seen[#seen + 1] = text
			end
		end
		if varies then told = told + 1 end

		-- EVERY SCRIPT ON THE DISK RUNS, OFF THE DISK. Section 6 runs every script in
		-- the library out of a home directory, which proves the script; this runs the
		-- copy the disk carries, through the mount, with the files and the lines the
		-- library says it wants. A name on a disk that is not in SCRIPTS writes
		-- nothing at all (diskData leaves the entry out), so a script that fell out
		-- of the library would be a file the README names and the disk has not got --
		-- and the README walk above is what catches that.
		for f = 1, #entry.files do
			local file = entry.files[f]
			local script = CeroSecContent.SCRIPTS[file.script or ""]
			if script ~= nil then
				local at = where .. "/" .. file.name .. " off the disk"
				local state = CeroSecOS.newState("ksp-4-b")
				local session = CeroSecOS.login(state, "admin", "")
				state.floppy = CeroSecContent.diskData(entry, START, 1)
				local env = { now = START, devices = devicesFor(script.needs) }
				local mounted = run(state, session, "mount /dev/fd0 /mnt", env)
				check(at .. ": the disk mounts", mounted)
				if type(script.needs) == "table" and type(script.needs.files) == "table" then
					for n = 1, #script.needs.files do
						local put = CeroSecOS.writeFile(state, session,
							"/home/admin/" .. script.needs.files[n].path,
							script.needs.files[n].text, false, START)
						check(at .. " gets " .. script.needs.files[n].path, put ~= nil)
					end
				end
				local line = "sh " .. CeroSecOS.MNT_PATH .. "/" .. file.name
				for a = 1, #script.args do line = line .. " " .. script.args[a] end
				local ran, lines, turns, job =
					run(state, session, line, env, script.input)
				check(at .. " runs: " .. table.concat(lines, " / "), ran)
				check(at .. " printed something", #lines > 0)
				check(at .. " is over and not still asking", CeroSecOS.jobIsOver(job))
				check(at .. " finishes in a handful of turns (" .. turns .. ")",
					turns < 50)
				local vok, vwhy = CeroSecOS.validate(state)
				check(at .. " leaves a machine that still boots: " .. tostring(vwhy),
					vok)
			end
		end
	end
	check("four disks are written three ways (" .. told .. ")", told == 4)

	-- THE SHOP'S BOOKS ADD UP, and the number is the point of the disk. total.sh is
	-- run off the LEDGER disk against the LEDGER disk's own SALES.TXT, from inside
	-- /mnt, which is the line the README prints and the step the parcours walks --
	-- and the total is written down here rather than computed, because a bench that
	-- adds the column up itself proves that two additions agree and not that the
	-- shop's week is 1582 dollars and 44 cents.
	do
		local entry = CeroSecContent.diskById("LEDGER")
		check("the LEDGER disk is in the catalogue", entry ~= nil)
		local state = CeroSecOS.newState("ksp-4-b")
		local session = CeroSecOS.login(state, "admin", "")
		state.floppy = CeroSecContent.diskData(entry, START, 1)
		local env = { now = START, devices = devicesFor(nil) }
		check("the LEDGER disk mounts", run(state, session, "mount /dev/fd0 /mnt", env))
		-- Stood in /mnt by writing the session's own cwd, which is the field `cd`
		-- writes (commands.cd) and the field every relative path is resolved against
		-- (CeroSecOS.absPath). Not by running `cd`: this bench's loop steps one job
		-- and drops it, and what carries a cwd out of a finished job back onto the
		-- session is the server's own turn -- so a `cd` here would come back true and
		-- leave the bench standing in the home directory, which is exactly how the
		-- first draft of this block passed while proving the wrong path.
		session.cwd = CeroSecOS.MNT_PATH
		eq("and the bench is standing in it",
			(select(2, run(state, session, "pwd", env)))[1], CeroSecOS.MNT_PATH)
		local ran, lines = run(state, session, "sh /mnt/total.sh SALES.TXT 3", env)
		check("total.sh runs off the disk: " .. table.concat(lines, " / "), ran)
		eq("and the week in cents is the week in cents", lines[1],
			"column 3 of SALES.TXT adds up to 158244")
		-- The other column, because one number agreeing could be one number agreeing
		-- with a script that ignores its second argument.
		local tran, tlines = run(state, session, "sh /mnt/total.sh SALES.TXT 2", env)
		check("and the tickets too: " .. table.concat(tlines, " / "), tran)
		eq("and they add up to their own number", tlines[1],
			"column 2 of SALES.TXT adds up to 346")
		-- SALES.TXT is ONE shape, which is what lets the two numbers above be numbers
		-- rather than one of three possible numbers.
		for v = 2, CeroSecContent.VARIANTS do
			local other = CeroSecContent.diskData(entry, START, v)
			eq("SALES.TXT is the same file in telling " .. v,
				other.fs.children["SALES.TXT"].data,
				state.floppy.fs.children["SALES.TXT"].data)
		end
	end

	-- THE CALLSIGNS ARE THE SHAPE A SET WILL TAKE. They are invented -- there is no
	-- station on the air to ask -- so the one thing that can be held is the rule the
	-- engine itself applies to a callsign before it lets a station transmit
	-- (CeroSecOS.isCallsign). A made-up call the player's own set would refuse is a
	-- disk teaching him something that is not true of this machine.
	do
		local entry = CeroSecContent.diskById("RADIO LOG")
		check("the RADIO LOG disk is in the catalogue", entry ~= nil)
		local calls = {}
		local found = 0
		for v = 1, CeroSecContent.VARIANTS do
			local disk = CeroSecContent.diskData(entry, START, v)
			for path, node in pairs(walk(disk.fs)) do
				if path ~= "/" then
					-- A capitals-and-digits word that opens with one of the three
					-- prefixes the fourth district handed out and has a digit in it. The
					-- times and the numbers on those pages are digits alone and the
					-- other words have no digit in them, so what is left is the calls.
					for word in string.gmatch(node.data or "", "[A-Z0-9]+") do
						if string.find(word, "^[KNW]") ~= nil
							and string.find(word, "%d") ~= nil then
							found = found + 1
							check("RADIO LOG telling " .. v .. path .. ": " .. word
								.. " is a callsign this machine would take",
								CeroSecOS.isCallsign(word))
							calls[word] = true
						end
					end
				end
			end
		end
		check("there are callsigns on the disk (" .. found .. ")", found > 20)
		local distinct = 0
		for _ in pairs(calls) do distinct = distinct + 1 end
		check("and more than one station was on the air (" .. distinct .. ")",
			distinct >= 6)
	end

	-- THE ROLL IS MADE ONCE AND THE ANSWER IS THE BYTES.
	--
	-- A disk owns three keys and only three, so there is nowhere to write which
	-- telling this copy is -- and there is no need to, because the telling is spent
	-- at creation and what it produces is a filesystem. So: the hook is called with
	-- a roll that picks BACKUP and telling three, and then called again on the same
	-- item with a generator that would answer telling one. Nothing moves. A disk
	-- read out of its own modData twice is the same disk, which is what a save
	-- reload is.
	do
		local item = { data = {}, name = "3.5\" Floppy Disk", custom = false }
		item.getModData = function() return item.data end
		item.setName = function(_, text) item.name = text end
		item.getName = function() return item.name end
		-- The engine does not only move a flag: setCustomName rawsets `customName` on
		-- the item's own modData with its name (javap -c
		-- zombie.inventory.InventoryItem, setCustomName(boolean), offsets 5-24). The
		-- slot reads the keys a disk owns off that table and leaves the rest, so this
		-- is here to prove the leaving and not only the writing.
		item.setCustomName = function(_, flag)
			item.custom = flag
			item.data.customName = tostring(item.name)
		end
		item.isCustomName = function() return item.custom end
		item.syncItemFields = function() end

		local entry = CeroSecContent.diskById("BACKUP")
		local at = 0
		for i = 1, #CeroSecContent.DISKS do
			if CeroSecContent.DISKS[i] == entry then break end
			at = at + (tonumber(CeroSecContent.DISKS[i].weight) or 0)
		end
		-- ZombRand(n) answers 0..n-1, and the hook adds one to both of its rolls.
		-- Which roll this is is told by the bound the hook asked for, which is the
		-- only thing the engine's own generator is told either.
		local telling = 3
		local hadRand = _G.ZombRand
		_G.ZombRand = function(n)
			if n == 100 then return at end
			return telling - 1
		end
		CeroSecContent.onCreateFloppy(item)
		eq("a rolled disk carries the label it rolled", item.data.label, "BACKUP")
		local first = CeroSecOS.diskFromData(item.data)
		check("and the slot takes it", (CeroSecOS.validateDisk(first, true)))
		-- The telling really is the one the roll asked for: the disk the item carries
		-- is byte for byte the catalogue's third telling and not its first.
		eq("and it is the telling the roll asked for", dump(first.fs),
			dump(CeroSecContent.diskData(entry, nil, 3).fs))
		check("and not another one", dump(first.fs)
			~= dump(CeroSecContent.diskData(entry, nil, 1).fs))
		-- Nothing on it says which telling it is, which is the reason the telling is
		-- kept as bytes: the DISK owns three keys and a fourth of ours would be refused
		-- at the slot. Counted on the disk the slot read back and not on the item's
		-- table, because that table is the game's: the engine's own `customName` is on
		-- it too (setCustomName, javap), and what the slot does with a name that is not
		-- ours is leave it there.
		local keys = 0
		for _ in pairs(first) do keys = keys + 1 end
		eq("and the disk owns three keys and no more", keys, 3)
		check("the game's own key is on the item", item.data.customName ~= nil)
		eq("and did not come in on the disk", first.customName, nil)

		-- Now the second creation, with a generator that would answer differently.
		telling = 1
		CeroSecContent.onCreateFloppy(item)
		eq("a disk already written is not rolled again", dump(
			CeroSecOS.diskFromData(item.data).fs), dump(first.fs))
		-- And read back twice out of the same modData, which is what a reload is.
		eq("and reading a disk does not roll it", dump(
			CeroSecOS.diskFromData(item.data).fs),
			dump(CeroSecOS.diskFromData(item.data).fs))
		_G.ZombRand = hadRand
	end
end

--
-- 8. The item hook: a floppy off a shelf
--
-- What `OnCreate = CeroSecContent.onCreateFloppy` does when the game calls it with
-- an item. The fake item answers the five calls the hook makes and nothing else,
-- which is the point: a hook that quietly reached for a sixth would find it
-- missing here.
--

do
	local function newFloppy(data)
		local item = { data = data or {}, name = "3.5\" Floppy Disk", custom = false,
			synced = 0 }
		item.getModData = function() return item.data end
		item.setName = function(_, text) item.name = text end
		item.getName = function() return item.name end
		-- The engine does not only move a flag: setCustomName rawsets `customName` on
		-- the item's own modData with its name (javap -c
		-- zombie.inventory.InventoryItem, setCustomName(boolean), offsets 5-24). The
		-- slot reads the keys a disk owns off that table and leaves the rest, so this
		-- is here to prove the leaving and not only the writing.
		item.setCustomName = function(_, flag)
			item.custom = flag
			item.data.customName = tostring(item.name)
		end
		item.isCustomName = function() return item.custom end
		item.syncItemFields = function() item.synced = item.synced + 1 end
		return item
	end

	-- A roll this bench decides, in place of the engine's. Every assertion below is
	-- about what the hook does WITH a roll, so the roll itself is not left to a
	-- generator: a bench whose result depends on one is a bench that is red on
	-- somebody else's machine.
	local roll = 0
	local hadRand = _G.ZombRand
	_G.ZombRand = function() return roll end

	-- A roll that lands on the UTILITIES entry.
	local entry = CeroSecContent.diskById("UTILITIES")
	local at = 0
	for i = 1, #CeroSecContent.DISKS do
		if CeroSecContent.DISKS[i] == entry then break end
		at = at + (tonumber(CeroSecContent.DISKS[i].weight) or 0)
	end
	roll = at  -- ZombRand(100) answers 0..99, and the hook adds one

	local item = newFloppy()
	CeroSecContent.onCreateFloppy(item)
	eq("a disk that rolled a catalogue entry is at this floppy version",
		item.data.v, CeroSecOS.FLOPPY_VERSION)
	check("and has a filesystem on it", type(item.data.fs) == "table")
	eq("and carries the label", item.data.label, entry.label)
	eq("which is written on the item's name", item:getName(), entry.label)
	check("as a custom name, or the translated name would win", item:isCustomName())
	eq("and it was sent", item.synced, 1)
	local ok, why = CeroSecOS.validateDisk(CeroSecOS.diskFromData(item.data), true)
	check("and the slot takes it: " .. tostring(why), ok)
	-- README.TXT really is on the disk the ITEM carries, which is the one thing the
	-- catalogue checks above cannot say: they weighed the disk diskData made, and
	-- this weighs the copy that went through the item's modData.
	local root = CeroSecOS.diskFromData(item.data).fs
	check("with the README on it", root.children["README.TXT"] ~= nil)

	-- A roll past every weight is a blank disk: no filesystem, no label, and the
	-- name it came with.
	roll = 99
	local blank = newFloppy()
	CeroSecContent.onCreateFloppy(blank)
	eq("a disk that rolled nothing carries nothing", blank.data.v, nil)
	eq("and no label", blank.data.label, nil)
	eq("and keeps the name it came with", blank:getName(), "3.5\" Floppy Disk")
	check("and is not a custom name", not blank:isCustomName())

	-- A disk that ALREADY has something written on it is left alone. An item made
	-- by cloning a written one arrives here with its modData filled in, and a hook
	-- that rolled again would wipe somebody's work.
	roll = at
	local written = newFloppy({ v = CeroSecOS.FLOPPY_VERSION, label = "PAYROLL" })
	CeroSecContent.onCreateFloppy(written)
	eq("a disk that already carries something keeps its label",
		written.data.label, "PAYROLL")
	eq("and nothing was written on its name", written:getName(), "3.5\" Floppy Disk")

	-- And junk, because this runs for every floppy the game ever makes.
	CeroSecContent.onCreateFloppy(nil)
	do
		local noData = { getModData = function() return nil end }
		CeroSecContent.onCreateFloppy(noData)
	end
	_G.ZombRand = nil
	do
		local noRand = newFloppy()
		CeroSecContent.onCreateFloppy(noRand)
		eq("a box with no generator in it makes a blank disk", noRand.data.v, nil)
	end
	_G.ZombRand = hadRand
	check("nothing threw", true)
end

--
-- 9. What a refusal does: TRIMMED, never a crash
--
-- The rule the whole file rests on. A profile is loot, and loot that can take a
-- machine down is loot that breaks a save -- so a machine with no room left on it
-- is prefilled with as much as fits and is still a machine that boots.
--

do
	-- A machine filled to within a few nodes of MAX_NODES, and then prefilled.
	local state = CeroSecOS.newState("ksp-4-b")
	local session = CeroSecOS.rootSession()
	local made = 0
	while true do
		local node = CeroSecOS.newFile("root", 644, "x")
		if CeroSecOS.createNode(state, session, "/var/tmp/f" .. made, node, START) == nil then
			break
		end
		made = made + 1
		if made > CeroSecOS.MAX_NODES then break end
	end
	check("the bench filled the machine up (" .. made .. " files)", made > 0)
	local before = select(1, CeroSecOS.usage(state))

	local got = CeroSecContent.prefill(state, opts(SECRET_A, { premises = "Office" }))
	eq("a full machine is still given its profile", got, "office")
	local ok, why = CeroSecOS.validate(state)
	check("and it still boots: " .. tostring(why), ok)
	local after, bytes = CeroSecOS.usage(state)
	check("and it is still inside MAX_NODES (" .. after .. ")",
		after <= CeroSecOS.MAX_NODES)
	check("and still inside the disk (" .. bytes .. ")",
		bytes <= CeroSecOS.MAX_TOTAL_BYTES)
	check("and the fill was trimmed rather than forced",
		after - before < 20)

	-- AND THE DISK'S OWN CEILINGS, which are the small ones: 4096 bytes and 32
	-- nodes. A catalogue entry far over both -- which is what the world-content work, part 2 will write by
	-- accident one day -- must come out as a disk the SLOT still takes, with as many
	-- files on it as fit, and never as a disk no machine in the county will accept.
	do
		local big = { id = "BIG", label = "BIG", weight = 0, files = {} }
		for i = 1, 40 do
			big.files[i] = { name = "F" .. i .. ".TXT", mode = 644,
				text = string.rep("x", 300) }
		end
		local disk, written = CeroSecContent.diskData(big, START)
		check("a catalogue entry over the floppy ceilings writes some of its files ("
			.. written .. " of " .. #big.files .. ")",
			written > 0 and written < #big.files)
		local ok, why = CeroSecOS.validateDisk(disk, true)
		check("and the slot still takes the disk: " .. tostring(why), ok)
		local nodes, bytes = CeroSecOS.subtreeUsage(disk.fs)
		check("inside FLOPPY_NODES (" .. nodes .. ")", nodes <= CeroSecOS.FLOPPY_NODES)
		check("inside FLOPPY_BYTES (" .. bytes .. ")", bytes <= CeroSecOS.FLOPPY_BYTES)
	end

	-- And junk for every input. Nothing here may throw: prefill is called from
	-- turnOn, and an error there is a computer that cannot be switched on.
	eq("no state at all", CeroSecContent.prefill(nil, opts(SECRET_A)), nil)
	eq("no options at all", CeroSecContent.prefill(CeroSecOS.newState("ksp-1-1"), nil), nil)
	eq("no secret", CeroSecContent.prefill(CeroSecOS.newState("ksp-1-1"),
		{ premises = "Office" }), nil)
	eq("a secret that is not one", CeroSecContent.prefill(CeroSecOS.newState("ksp-1-1"),
		opts("nonsense", { premises = "Office" })), nil)
	-- A premises name with everything wrong with it in one string.
	do
		local s = CeroSecOS.newState("ksp-1-1")
		local id = CeroSecContent.prefill(s, opts(SECRET_A,
			{ premises = "Office/../../etc\1\2", room = "\255" }))
		eq("a premises name full of junk still resolves", id, "office")
		check("and the machine it built boots", CeroSecOS.validate(s))
	end
	-- No clock, which is what a bench and a server mid-load are. The options are
	-- written out rather than overridden: `pairs` does not carry a nil, so
	-- `{ start = nil }` handed to the helper above would quietly leave the clock in.
	do
		local s = CeroSecOS.newState("ksp-1-1")
		local id = CeroSecContent.prefill(s, { secret = SECRET_A, b1 = 12, b2 = 34,
			x = 1, y = 1, z = 0, premises = "Office" })
		eq("a machine with no clock is still prefilled", id, "office")
		check("and it boots", CeroSecOS.validate(s))
		eq("and it has no log, because a log with no date is not a log",
			CeroSecOS.systemNode(s, CeroSecOS.LOG_PATH .. "/messages"), nil)
	end
end

print("content_test: " .. count .. " checks passed")
