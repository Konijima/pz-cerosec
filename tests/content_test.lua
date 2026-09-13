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

	-- Every name in the lists, on its own, because the lists are what wave 7b
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
		-- is asserted rather than skipped, because "wave 7b will fill it" must not
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
						-- exactly what this wave took out.
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
-- tree for a wave and turns up on a player's screen in the one office in three
-- that got it.
--
-- So this walks the CATALOGUE and not a machine: every entry, every telling, with
-- names put in, held to the same rules section 4 holds the one it built to. And it
-- asserts the shape of the format as well as the text -- three tellings and not
-- two, never `text` and `texts` together, and PROSE MUST HAVE THREE. That last one
-- is the requirement of this wave, and it is the only assertion here that a
-- forgetful next wave could fail.
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
			-- this wave in one assertion: prose varies, and the tables the scripts are
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
			for i = 1, #text do
				local b = string.byte(text, i)
				check(w .. " byte " .. i .. " is printable ASCII (" .. b .. ")",
					b == 10 or (b >= 32 and b <= 126))
			end
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
		if officeText(12, b2) ~= base then differs = true end
	end
	check("two offices in the county do not read the same", differs)
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

	-- The slots wave 7b fills. An id in neither list is a catalogue entry nobody
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
	-- with none -- so without this line, a wave that dropped `late` off the BBS list
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
		item.setCustomName = function(_, flag) item.custom = flag end
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
	-- nodes. A catalogue entry far over both -- which is what wave 7b will write by
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
