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
local function run(state, session, line, env)
	env = env or { now = START }
	if session.shvars == nil then session.shvars = {} end
	local job, refusal =
		CeroSecOS.promptJob(state, session, line, session.shvars, session.status)
	if job == nil then return false, { refusal }, 0 end
	local out, turns = {}, 0
	while not CeroSecOS.jobIsOver(job) and turns < 2000 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, env, 1000)
		for k = 1, #job.out do out[#out + 1] = job.out[k] end
		job.out = {}
		if job.state == "waiting" or job.state == "sleeping" then break end
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
		e.state = value
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
						if type(profile.accounts[a].files) == "table" then
							for f = 1, #profile.accounts[a].files do
								local file = profile.accounts[a].files[f]
								local at = all["/home/" .. login .. "/" .. file.path]
								check(id .. " " .. login .. "'s " .. file.path .. " is there",
									at ~= nil and at.type == "file")
								eq(id .. " and it is his", at.owner, login)
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
				eq(id .. " one line per entry", #lines, #profile.logs)
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
		end
	end
	check("at least two profiles are written", built >= 2)
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

		-- And now run it.
		local state = CeroSecOS.newState("ksp-4-b")
		local session = CeroSecOS.login(state, "admin", "")
		check(name .. ": the bench can log in", session ~= nil)
		local path = "/home/admin/" .. name
		local done, why =
			CeroSecOS.writeFile(state, session, path, script.text, false, START)
		check(name .. " goes onto a machine: " .. tostring(why), done ~= nil)
		local env = { now = START, devices = devicesFor(script.needs) }

		local ok, out = run(state, session, "chmod 755 " .. name, env)
		check(name .. ": chmod works", ok)

		local line = "./" .. name
		for a = 1, #script.args do line = line .. " " .. script.args[a] end
		local ran, lines, turns = run(state, session, line, env)
		check(name .. " runs: " .. table.concat(lines, " / "), ran)
		check(name .. " printed something", #lines > 0)
		-- Under budget, which is the other half of "it runs": a script that only
		-- finishes because the bench gave it two thousand turns is a script that
		-- would be killed on a real machine (`killed: cpu limit`).
		check(name .. " finishes in a handful of turns (" .. turns .. ")", turns < 50)
		for l = 1, #lines do
			check(name .. ' output fits 60 columns: "' .. lines[l] .. '"',
				#lines[l] <= CeroSecOS.COLS)
		end

		-- And with NO arguments, which is the other way it will be run: by somebody
		-- who found it and typed its name. It must say how it is used and not fall
		-- over.
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
			eq(where .. " has one entry per file", #names, #entry.files)
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
			for n = 1, #names do
				local name = names[n]
				local node = root.children[name]
				check(where .. "/" .. name .. " is a name the machine will take",
					CeroSecOS.isValidFileName(name))
				check(where .. "/" .. name .. " carries no control byte",
					not CeroSecOS.hasControlBytes(node.data or ""))
				for line in ((node.data or "") .. "\n"):gmatch("([^\n]*)\n") do
					check(where .. "/" .. name .. ' line fits 60 columns: "' .. line
						.. '"', #line <= CeroSecOS.COLS)
				end
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
		check("catalogue entry " .. id .. " is either shipped or a named slot",
			slots[id] ~= nil or id == "UTILITIES" or id == "BLANK")
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
