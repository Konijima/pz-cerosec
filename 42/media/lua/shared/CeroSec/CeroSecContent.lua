--
-- What is already on the machines, and on the disks beside them.
--
-- Knox County had computers in it before the outbreak and people were using
-- them. So a vanilla computer somebody switches on for the first time is not a
-- machine out of a box: it is somebody's machine, with his accounts on it, his
-- files in his home, a motd his employer put there and a log of the last week
-- anybody worked. And a floppy off a shelf is sometimes a floppy with something
-- written on it, with a README.TXT beside it in capitals the way a 1993 disk had.
--
-- THIS FILE IS THE CATALOGUE AND THE GENERATORS, AND NOTHING ELSE. It is pure:
-- data tables and functions over them. It does not look at the world, it does
-- not read the state of any machine by itself, and it holds no clock -- what
-- decides which profile a machine gets is the server (SCeroSecObject:turnOn, by
-- way of CeroSecNet.premisesOfSquare), and every date it writes is handed to it.
-- That
-- is what lets tests/content_test.lua build every profile and run every script
-- with no game under it.
--
-- Two rules it never breaks:
--
--   * EVERYTHING GOES THROUGH THE ENGINE'S OWN WRITE PATH. A file is made with
--     CeroSecOS.createNode and a password set with CeroSecOS.setPassword, so the
--     quota, the modes, the owners, the 96 entries to a directory and the 512
--     nodes to a machine hold for a prefilled computer exactly as they hold for
--     one a survivor typed on. A profile that would go over a ceiling is TRIMMED
--     -- the next file is simply not written -- and never crashes: the loot in
--     one office must not be able to take a machine down.
--   * NOTHING GENERATED IS STORED IN CLEAR. A root password is derived, hashed
--     through CeroSecOS.setPassword and forgotten; the only place the letters
--     themselves ever appear is on the sticky note in the drawer, and that note
--     derives them again from the same two inputs rather than being told them.
--
-- THE SEED. Everything is hash(secret, key): the per-save secret
-- (SCeroSecSystem.seed, made once and saved in gos_cerosec.bin) and a key that
-- says what is being asked for. So a password is the same password however many
-- times the world is reloaded -- there is nothing to save and therefore nothing
-- to get out of step -- and it is a different password in the next save. The
-- sticky note and the machine agree for that reason and for no other: they ask
-- the same question of the same secret, so there is no moment where one of them
-- has been written and the other has not.
--
-- BE HONEST ABOUT WHAT THE SECRET IS. It keeps a save CONSISTENT. It is not a
-- security boundary: the number is in the save file, and a single-player player
-- who reads his own save file can read /etc/passwd out of it just as easily. On
-- a server the save is on the server, which is the whole of the difference.
--
-- This file may NOT touch CeroSecOS at load time. The game loads
-- shared/CeroSec/ ahead of shared/CeroSec/OS/, so the core does not exist yet
-- when this top level runs -- the same rule the manual volumes follow.
--

CeroSecContent = CeroSecContent or {}

-- Which catalogue this is. Not a save-shape number and it must never become one:
-- nothing written by a profile is marked as having come from one, so a later
-- catalogue changes what the NEXT untouched machine gets and changes nothing
-- about a machine somebody has already switched on. Bumped when a wave adds or
-- rewrites entries, and read by nothing but the bench and docs/CONTENT.md.
CeroSecContent.VERSION = 1

--
-- Is there anything already on the machines at all?
--
-- The sandbox option, read the way vanilla reads its own grouped options --
-- `SandboxVars.Map and (SandboxVars.Map.AllowMiniMap == true)`,
-- client/ISUI/Maps/ISMiniMap.lua:687 -- because SandboxVars is a plain table and
-- a group nobody declared is simply not in it.
--
-- Anything that is not the literal false is "yes", which keeps the DECLARED
-- default (42/media/sandbox-options.txt says true) for a save from before the
-- option, a group that is not there and a sandbox file that failed to load. The
-- other direction would be a world that quietly went back to bare machines and
-- looked exactly like a working one.
--
-- One reader, two callers: the machines (SCeroSecObject:turnOn) and the notes
-- (CeroSecNotes). A second copy of this test is how a mod ends up with the option
-- off for the computers and on for the paper in the drawer.
CeroSecContent.SANDBOX = "PrefilledMachines"

function CeroSecContent.enabled()
	local group = SandboxVars and SandboxVars.CeroSec
	if group == nil then return true end
	return group[CeroSecContent.SANDBOX] ~= false
end

--
-- The derivation
--

-- Rounds of mixing for a content hash. Sixteen, which is CeroSecOS.newSalt's
-- number and not hashPassword's four thousand: this is not a password check and
-- must not cost like one -- prefilling one machine asks for a few dozen of these
-- and the bench asks for thousands.
CeroSecContent.HASH_ROUNDS = 16

-- The 64-bit secret, as sixteen lowercase hex digits. A string and not a number
-- on purpose: a Lua double carries 53 bits of mantissa, so a 64-bit integer kept
-- as a number is an integer whose bottom eleven bits are a lie, and it would ride
-- into the save file that way.
CeroSecContent.SECRET_DIGITS = 16

function CeroSecContent.isSecret(secret)
	if type(secret) ~= "string" then return false end
	if #secret ~= CeroSecContent.SECRET_DIGITS then return false end
	return string.find(secret, "[^0-9a-f]") == nil
end

-- hash(secret, key) -> 32 hex digits. The ONE place a content hash is taken, so
-- every generator below asks the same question the same way and the note and the
-- machine cannot drift.
--
-- The separator is "/" and the key is never allowed to contain one (below),
-- which is what stops two different questions from spelling the same string:
-- without it, secret .. "root" .. "01" and secret .. "root0" .. "1" are one
-- hash and the note for one premises would open the machine in another.
function CeroSecContent.derive(secret, key)
	if not CeroSecContent.isSecret(secret) then return nil end
	if type(key) ~= "string" or key == "" then return nil end
	if string.find(key, "/") ~= nil then return nil end
	return CeroSecOS.digest(secret .. "/" .. key, CeroSecContent.HASH_ROUNDS)
end

-- A key built out of parts, with the separator put in by the one function that
-- is allowed to put it in. Every part is forced to the characters a key may
-- carry, so a premises called "Coffee Shop" and a login somebody chose cannot
-- smuggle a separator into a key.
function CeroSecContent.key(...)
	local parts = { ... }
	local out = {}
	for i = 1, #parts do
		local part = string.lower(tostring(parts[i]))
		part = string.gsub(part, "[^a-z0-9%-%.]", "")
		if part == "" then part = "-" end
		out[#out + 1] = part
	end
	return table.concat(out, ".")
end

-- A whole number in 1..n, out of the hash. The top eight hex digits, which is
-- 32 bits held exactly by a double, taken modulo n: the bias against the last
-- few values of n is one part in fifty million and this is choosing a surname.
-- CeroSecOS.hexValue and not tonumber(s, 16): Kahlua returns nil above
-- 0x7fffffff, which is half of all hashes, and the caller then adds to nil.
function CeroSecContent.number(secret, key, n)
	if type(n) ~= "number" or n < 1 then return nil end
	local hash = CeroSecContent.derive(secret, key)
	if hash == nil then return nil end
	local v = CeroSecOS.hexValue(string.sub(hash, 1, 8))
	if v == nil then return nil end
	return math.floor(math.fmod(v, math.floor(n))) + 1
end

-- One out of a list.
function CeroSecContent.pick(list, secret, key)
	if type(list) ~= "table" or #list == 0 then return nil end
	local i = CeroSecContent.number(secret, key, #list)
	if i == nil then return nil end
	return list[i]
end

-- Does this key's roll come in under `percent`? The gate every "a chance of"
-- in a profile goes through, so there is one of it.
function CeroSecContent.chance(secret, key, percent)
	if type(percent) ~= "number" or percent <= 0 then return false end
	if percent >= 100 then return true end
	local roll = CeroSecContent.number(secret, key, 100)
	if roll == nil then return false end
	return roll <= percent
end

--
-- The people
--
-- Names off the county's own mailboxes: ordinary American first and last names
-- of somebody who was of working age in 1993. A login is the first name, or the
-- first initial and the surname, or the surname alone -- the three shapes every
-- office in the world picked between -- cut to CeroSecOS.MAX_USERNAME and forced
-- through CeroSecOS.isValidUserName, because what this returns goes into
-- /etc/passwd and a line that will not parse is an account nobody can log in to.
--
-- Wave 7b lengthens both lists. Nothing derived from them is stored, so a longer
-- list changes the next untouched machine and no machine already switched on.
--

CeroSecContent.NAMES = {
	first = {
		"james", "robert", "john", "michael", "david", "william", "richard",
		"joseph", "thomas", "charles", "mary", "patricia", "linda", "barbara",
		"elizabeth", "jennifer", "susan", "margaret", "dorothy", "carol",
		"donald", "kenneth", "steven", "edward", "brian", "ronald", "anthony",
		"nancy", "karen", "betty", "helen", "sandra", "donna", "ruth",
	},
	last = {
		"smith", "johnson", "williams", "brown", "jones", "miller", "davis",
		"wilson", "moore", "taylor", "anderson", "thomas", "jackson", "white",
		"harris", "martin", "thompson", "garcia", "martinez", "robinson",
		"clark", "rodriguez", "lewis", "lee", "walker", "hall", "allen",
		"young", "king", "wright", "scott", "torres", "hill", "green",
	},
}

-- A login for one person. `key` is the whole of what decides it, so the same
-- account on the same machine is the same person for ever.
--
-- Three shapes, chosen by a roll of their own, and then the fallbacks: a shape
-- that comes out too long for MAX_USERNAME falls back to the first name, and a
-- first name that is somehow not a valid login falls back to "user". Neither
-- can happen with the lists above -- the bench proves every combination -- and
-- both are here because the lists are what wave 7b is going to lengthen.
function CeroSecContent.login(secret, key)
	local first = CeroSecContent.pick(CeroSecContent.NAMES.first, secret,
		CeroSecContent.key(key, "first"))
	local last = CeroSecContent.pick(CeroSecContent.NAMES.last, secret,
		CeroSecContent.key(key, "last"))
	if first == nil or last == nil then return "user" end
	local shape = CeroSecContent.number(secret, CeroSecContent.key(key, "shape"), 3)
	local name = first
	if shape == 2 then
		name = string.sub(first, 1, 1) .. last
	elseif shape == 3 then
		name = last
	end
	if not CeroSecOS.isValidUserName(name) then name = first end
	if not CeroSecOS.isValidUserName(name) then name = "user" end
	return name
end

-- A person's name as he writes it at the bottom of a note: "Bob Miller".
function CeroSecContent.realName(secret, key)
	local first = CeroSecContent.pick(CeroSecContent.NAMES.first, secret,
		CeroSecContent.key(key, "first")) or "the"
	local last = CeroSecContent.pick(CeroSecContent.NAMES.last, secret,
		CeroSecContent.key(key, "last")) or "operator"
	local function cap(s)
		return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
	end
	return cap(first) .. " " .. cap(last)
end

--
-- The passwords
--
-- What a password on an office machine looked like in 1993, which is the whole
-- of why this list is short and this shape is simple: a word and two digits. It
-- is not meant to be strong. It is meant to be the thing somebody wrote on a
-- sticky note and put in the top drawer, and it has to be typeable at a 60
-- column terminal by somebody reading it off that note.
--
-- Every one of them is inside CeroSecOS.MAX_PASSWORD with room to spare, carries
-- no control byte and is not empty, which are the three rules the machine's own
-- `passwd` has. The bench asserts all three of every password this can make.
--
CeroSecContent.WORDS = {
	"falcon", "sunset", "harvest", "granite", "meadow", "copper", "juniper",
	"lantern", "compass", "thunder", "maple", "ranger", "willow", "cardinal",
	"bourbon", "derby", "hickory", "walnut", "tobacco", "limestone",
}

function CeroSecContent.password(secret, key)
	local word = CeroSecContent.pick(CeroSecContent.WORDS, secret,
		CeroSecContent.key(key, "word"))
	if word == nil then return nil end
	local n = CeroSecContent.number(secret, CeroSecContent.key(key, "digits"), 100)
	if n == nil then return nil end
	n = n - 1
	local digits = tostring(n)
	if n < 10 then digits = "0" .. digits end
	return word .. digits
end

--
-- THE PROFILE FORMAT -- and this is the part wave 7b writes against.
--
--   PROFILES[id] = {
--     host     = "acct",     head of the hostname; the coordinate tail is kept
--     motd     = "...",      /etc/motd, at most MOTD_MAX_LINES lines of 60 cols
--     accounts = { { name=, admin=, pass=, files={ {path,mode,text} } }, ... },
--     root     = true,       a root password to derive, hash and never store
--     logs     = { "..." },  lines for /var/log/messages, dated before day one
--     mail     = { { to=, from=, subj=, body= } },
--     bin      = { { script="lights.sh", chance=60, to="home" } },
--     files    = { { path=, mode=, owner=, text= } },
--   }
--
-- Five things to know about it:
--
--   * an account's `name` is usually ABSENT, and then the login is generated
--     (CeroSecContent.login) out of the machine's own key, so two offices have
--     two different sets of people in them. A profile NAMES an account only when
--     the name is the point -- a shared "dispatch" login, say.
--   * `pass = true` means the account gets a password of its own, derived from
--     the machine's key and that account's index. `pass = false` (or absent) is
--     an open account, which is what most 1993 desk machines had, and is what
--     lets a survivor in without finding anything.
--   * `root = true` is what puts a sticky note in that PREMISES, because the
--     note's own derivation is the same one (CeroSecContent.rootKey). A profile
--     with no root password has no note anywhere.
--   * a `bin` entry names a script in CeroSecContent.SCRIPTS and never carries
--     its text: one script, one copy, so the disks and the homes cannot drift
--     into two versions of the same file, and the bench runs every script once.
--   * every text is written through the FS gate and therefore TRIMMED rather
--     than forced: the order of the table is the order things are written in, so
--     put what matters first.
--
-- The ten ids exist now and eight of them are deliberately EMPTY. A machine
-- whose premises resolves to an empty id is prefilled with nothing at all, which
-- is exactly a bare machine -- so wave 7b fills a table and changes no code.
--

CeroSecContent.PROFILE_IDS = {
	"residential", "office", "police", "bank", "store", "school", "clinic",
	"radio", "military", "cerosec",
}

-- The profile a machine in no building at all gets, and the one an unknown
-- premises falls back to: somebody's house.
CeroSecContent.DEFAULT_PROFILE = "residential"

--
-- Which premises is which profile
--
-- Two questions, in this order, and both are answered against LOWERCASED
-- substrings because that is the only thing the map data can be relied on for:
-- a premises zone is named by whoever drew the map ("CoffeeShop", "PoliceStorage")
-- and a RoomDef's name is a LOOT type ("clothsstore", "kitchen") and says nothing
-- about tenancy. So a word is looked for, and when no word is found the answer is
-- residential rather than a guess.
--
-- The list is ordered and the FIRST match wins, so a longer word goes above a
-- shorter one it contains.
--
CeroSecContent.PREMISES_WORDS = {
	{ "police", "police" }, { "prison", "police" },
	{ "bank", "bank" },
	{ "school", "school" }, { "classroom", "school" }, { "university", "school" },
	{ "clinic", "clinic" }, { "medical", "clinic" }, { "hospital", "clinic" },
	{ "radio", "radio" }, { "broadcast", "radio" },
	{ "military", "military" }, { "army", "military" },
	-- CeroSec Systems' own premises, which the shipped map has none of and a mod
	-- map may: it is in the list so that every declared id is REACHABLE, which the
	-- bench asserts. An id nothing resolves to is a profile wave 7b would write and
	-- nobody would ever see.
	{ "cerosec", "cerosec" },
	{ "office", "office" }, { "warehouse", "office" }, { "factory", "office" },
	{ "store", "store" }, { "shop", "store" }, { "market", "store" },
	{ "kitchen", "residential" }, { "bedroom", "residential" },
	{ "livingroom", "residential" }, { "house", "residential" },
}

-- premisesName, rooms -> profile id. Pure, and that is the seam the bench uses:
-- what a premises is CALLED is the server's business (CeroSecNet.premisesOfSquare
-- and CeroSecNet.premisesRooms); which profile a set of names means is decided
-- here, with no world in sight.
--
-- `rooms` is the whole building's list of room names, or one name, or nothing.
-- It is the BUILDING's and never the caller's own square's, and that is the fix to
-- a bug that shipped: see the head of CeroSecNet.premisesRooms. A house with a
-- study in it answered "office" to the desk in the study and "residential" to the
-- computer in the living room, so the note in the drawer named a password no
-- machine had.
--
-- THE SCAN IS BY WORD AND NOT BY NAME, and that is the other half of the same
-- fix. The outer loop walks PREMISES_WORDS in ITS order and asks every name about
-- each word in turn -- so the order the engine hands a building's rooms over in
-- cannot change the answer, and "which room wins" is a decision written down in
-- one ordered list rather than an accident of iteration.
function CeroSecContent.profileFor(premisesName, rooms)
	local words = CeroSecContent.PREMISES_WORDS
	local names = {}
	if type(premisesName) == "string" and premisesName ~= "" then
		names[#names + 1] = string.lower(premisesName)
	end
	if type(rooms) == "string" then
		if rooms ~= "" then names[#names + 1] = string.lower(rooms) end
	elseif type(rooms) == "table" then
		for i = 1, #rooms do
			if type(rooms[i]) == "string" and rooms[i] ~= "" then
				names[#names + 1] = string.lower(rooms[i])
			end
		end
	end
	for i = 1, #words do
		local word = words[i][1]
		for n = 1, #names do
			if string.find(names[n], word, 1, true) ~= nil then return words[i][2] end
		end
	end
	return CeroSecContent.DEFAULT_PROFILE
end

--
-- THE SEED LIBRARY
--
-- One table, one copy of every script the mod ships. A profile's `bin` and a
-- disk's `files` both name an entry here, so a script exists once and the bench
-- runs every one of them through the engine: `needs` is what it declares it
-- wants standing around it, and the bench stubs exactly that.
--
--   SCRIPTS[name] = { mode = 755, needs = { devices = { {id=,kind=} } },
--                     args = { "light0" }, text = "..." }
--
-- `args` is what the bench runs it WITH, and it is part of the library because a
-- script whose usage nobody recorded is a script nobody can prove runs.
--
CeroSecContent.SCRIPTS = {}

CeroSecContent.SCRIPTS["lights.sh"] = {
	mode = 755,
	args = { "light0", "light1" },
	needs = { devices = {
		{ id = "light0", kind = "light", state = "on" },
		{ id = "light1", kind = "light", state = "on" },
	} },
	text = table.concat({
		"#!/bin/sh",
		"# lights.sh -- switch the lights you name off, one by one.",
		"# usage: lights.sh <light> [<light> ...]",
		"if [ $# -eq 0 ]; then",
		'  echo "usage: lights.sh <light> [<light> ...]"',
		"  exit 1",
		"fi",
		"while [ $# -gt 0 ]; do",
		"  echo off > /dev/$1",
		'  echo "$1 off"',
		"  shift",
		"done",
	}, "\n"),
}

--
-- THE DISK CATALOGUE -- the other half of what wave 7b writes.
--
--   DISKS[i] = {
--     id     = "UTILITIES",  what the entry is called in here and in the bench
--     label  = "UTILITIES",  what is written on the disk, CeroSecOS.labelOk
--     weight = 4,            out of 100; what is left over is a blank disk
--     files  = { { name="lights.sh", script="lights.sh" },
--                { name="README.TXT", mode=644, text="..." } },
--   }
--
-- Five things to know:
--
--   * a file entry carries EITHER `script` (a name in CeroSecContent.SCRIPTS,
--     which brings its own mode) or `text` and `mode`. Never both.
--   * README.TXT is in CAPITALS and so is every name on a disk that is not a
--     script, because a 1993 floppy came out of a DOS machine and that is what
--     was on it. The bench holds every README to naming every file beside it.
--   * the ceilings are the FLOPPY's and they are small: FLOPPY_BYTES is 4096 and
--     FLOPPY_NODES is 32. An entry over either is trimmed at fill time, so the
--     bench weighs every entry instead of trusting it.
--   * the weights are out of a hundred and the REMAINDER is blank. Four vanilla
--     colours share one box of disks, and a disk with something on it is meant
--     to be a find: most of them are blank, which is also what the floppy loot
--     file has always said (see CeroSecFloppyLoot).
--   * BLANK is in the table with no files on purpose: it is the entry the roll
--     lands on when nothing is written, and naming it makes the bench able to say
--     so out loud.
--
CeroSecContent.DISKS = {
	{
		id = "UTILITIES",
		label = "UTILITIES",
		weight = 4,
		files = {
			{ name = "lights.sh", script = "lights.sh" },
			{ name = "README.TXT", mode = 644, text = table.concat({
				"UTILITIES DISK",
				"",
				"lights.sh   switch the lights you name off.",
				"            usage: sh lights.sh light0 light1",
				"",
				"Copy it to the machine before you run it:",
				"",
				"  cp /mnt/lights.sh ~/bin",
				"",
				"Ask the machine what lights it has with: ls /dev",
			}, "\n") },
		},
	},
	{
		id = "BLANK",
		label = nil,
		weight = 0,
		files = {},
	},
}

-- The ids wave 7b fills. Named here rather than left to be remembered, and the
-- bench walks the list: an id in it that has become a real entry is fine, an id
-- in it that is still missing is fine, and an entry whose id is in NEITHER list
-- is a catalogue nobody wrote down.
CeroSecContent.DISK_SLOTS = {
	"BBS LIST", "WARDIALER", "GAMES", "BACKUP", "CEROSEC OS UPGRADE",
}

-- The entry a roll lands on, or nil for a blank disk. `roll` is 1..100.
function CeroSecContent.diskForRoll(roll)
	if type(roll) ~= "number" then return nil end
	-- A roll below one is a blank disk and not the first entry in the table. The
	-- roll is 1..100 everywhere it is made; a zero reaching here would otherwise
	-- come out as "the first weighted entry", which is how a caller's off-by-one
	-- turns into every disk in the county carrying the same thing.
	if roll < 1 then return nil end
	local at = 0
	for i = 1, #CeroSecContent.DISKS do
		local entry = CeroSecContent.DISKS[i]
		local weight = tonumber(entry.weight) or 0
		if weight > 0 then
			at = at + weight
			if roll <= at then return entry end
		end
	end
	return nil
end

function CeroSecContent.diskById(id)
	for i = 1, #CeroSecContent.DISKS do
		if CeroSecContent.DISKS[i].id == id then return CeroSecContent.DISKS[i] end
	end
	return nil
end

-- One catalogue entry -> the table that goes in an item's modData: v, fs and
-- label, which is the whole of what a disk owns (CeroSecOS.DISK_KEYS). Built
-- through CeroSecOS.newFloppy and CeroSecOS.createNode, so the disk's own
-- ceilings are what decide how much of an entry fits, and a file that does not
-- fit is left out rather than making a disk no slot will take.
--
-- disk, written  -- `written` is how many of the entry's files landed.
function CeroSecContent.diskData(entry, now)
	if type(entry) ~= "table" then return nil, 0 end
	local disk = CeroSecOS.newFloppy(entry.label)
	if disk == nil then return nil, 0 end
	if type(entry.files) ~= "table" or #entry.files == 0 then return disk, 0 end
	-- A disk with files on it has a filesystem on it. newFloppy leaves a blank
	-- one blank -- which is what a disk out of the box is -- so the tree is made
	-- here, once, and only for an entry that has something to put on it.
	disk.fs = CeroSecOS.newFloppyRoot("root", now)

	-- The engine writes into a STATE, so the disk is put in the drive of a
	-- throwaway machine, written through the ordinary path and taken back out.
	-- That is not a detour: it is what makes the floppy's ceilings, its modes and
	-- its printable rule the same ones a survivor's own `cp` meets.
	local state = CeroSecOS.newState(nil)
	state.floppy = disk
	if CeroSecOS.addMount(state, CeroSecOS.FD_NAME, CeroSecOS.MNT_PATH) == nil then
		return disk, 0
	end
	local session = CeroSecOS.rootSession()
	local written = 0
	for i = 1, #entry.files do
		local file = entry.files[i]
		local text, mode = file.text, file.mode
		if type(file.script) == "string" then
			local script = CeroSecContent.SCRIPTS[file.script]
			if script ~= nil then
				text = script.text
				mode = script.mode
			end
		end
		if type(text) == "string" and CeroSecOS.isValidFileName(file.name) then
			local node = CeroSecOS.newFile("root", mode or 644, text)
			local path = CeroSecOS.MNT_PATH .. "/" .. file.name
			-- nil on a full disk, a name already there, a byte the machine will not
			-- carry. Trimmed, never argued with: see the head of this file.
			if CeroSecOS.createNode(state, session, path, node, now) ~= nil then
				written = written + 1
			end
		end
	end
	CeroSecOS.unmountAll(state)
	return disk, written
end

--
-- THE ITEM HOOK
--
-- `OnCreate = CeroSecContent.onCreateFloppy` on the four floppy items. Proved at
-- the bytecode level on projectzomboid.jar 42.20.4, because an item-script key
-- vanilla itself never uses is exactly the kind of thing that turns out not to
-- work:
--
--   zombie.scripting.objects.Item.DoParam reads the key "OnCreate" into the
--       private field luaCreate (ldc "OnCreate" at 11017, putfield luaCreate at
--       11031).
--   zombie.scripting.objects.Item.InstanceItem(String, boolean) -- which every
--       item creation goes through -- calls InventoryItem.initialiseItem() at
--       4059, guarded by isInitialised() and by the calling thread being one of
--       GameWindow.gameThread, GameLoadingState.loader or GameServer.mainThread
--       (4022-4055). Loot generation runs on the loader thread.
--   zombie.inventory.InventoryItem.initialiseItem() resolves the name through
--       LuaManager.getFunctionObject and calls it with the item as its ONE
--       argument (LuaCaller.protectedCallVoid at offset 32).
--   LuaManager.getFunctionObject splits a name on "." and walks the global env
--       (offsets 31-48), so a dotted name in a table of ours resolves.
--
-- WHAT IS ROLLED, AND WHY IT IS NOT A HASH. The design for this wave said to hash
-- the item's id. There is no id to hash: InventoryItem.id is only ever written by
-- InventoryItem.load and by createCloneItem -- the only two putfields on the
-- field in the whole class -- so a freshly instanced item is id 0 and every
-- floppy in the county would hash the same. So the roll is the engine's own RNG, ZombRand,
-- exactly as vanilla rolls loot -- and the determinism the design wanted is kept
-- by WHERE THE ANSWER LIVES: the roll happens once, at creation, and what is
-- saved is its RESULT in the item's own modData. A disk's contents never change
-- afterwards, through any number of reloads, because nothing rolls again.
--
-- This is a DEVIATION from the wave's design and it is declared in
-- docs/CONTENT.md as one.
--
-- The hook runs wherever an item is instanced, which includes a client. It is
-- therefore in a SHARED file and it asks the world for nothing but a random
-- number: nothing here reads the per-save secret, which is the server's and must
-- stay there.
function CeroSecContent.onCreateFloppy(item)
	if item == nil then return end
	if ZombRand == nil then return end
	-- A disk that somehow already has something written on it is left alone: this
	-- is a hook on creation and not a hook on every touch, but an item made by
	-- cloning a written one arrives here initialised in every way but the flag.
	local data = item:getModData()
	if data == nil then return end
	if data.v ~= nil or data.fs ~= nil or data.label ~= nil then return end

	local roll = math.floor(ZombRand(100)) + 1
	local entry = CeroSecContent.diskForRoll(roll)
	if entry == nil then return end

	local disk = CeroSecContent.diskData(entry, nil)
	if disk == nil then return end
	if not CeroSecOS.writeDiskTo(data, disk) then return end

	-- And the label, on the item's NAME, which is where a label lives and the
	-- only place it lives (see the head of CeroSecFloppyMenu). Written the way
	-- the menu writes it so a found disk and a labelled one are one thing.
	if type(entry.label) == "string" and CeroSecOS.labelOk(entry.label) then
		item:setName(entry.label)
		item:setCustomName(true)
		item:syncItemFields()
		data.label = entry.label
	end
end

--
-- PREFILLING A MACHINE
--

-- The two keys, and they are the whole of the agreement between a machine and a
-- note in its drawer: both are built out of the PREMISES and nothing else.
--
-- The root password's key is the premises' own two bytes, so the note in the
-- drawer of a shop and the machine on its counter derive the same letters -- and
-- a second machine carried into the same shop and switched on derives them too,
-- which is right: it is the premises' password.
function CeroSecContent.rootKey(b1, b2)
	return CeroSecContent.key("root", b1, b2)
end

-- AND SO ARE THE PEOPLE, and this is the decision the papers forced. An account's
-- login and an account's password are keyed on the PREMISES and its slot number,
-- not on the machine -- so two computers in one office have the same staff on
-- them, which is what an office is, and so a paper found on a body in the car park
-- can name one of them without knowing which desk the man sat at.
--
-- The alternative was machine-keyed people, which is what this was first. It gave
-- two desks in one office two disjoint sets of employees -- already a little
-- untrue -- and it made a note in a dead man's pocket impossible to write: the
-- corpse cannot say which machine its owner used, so a note keyed on a machine
-- would name an account that machine had and the machine beside it did not.
--
-- What stays MACHINE-keyed is everything that is about the desk and not about the
-- company: which scripts are in ~/bin, and the hours in the log.
function CeroSecContent.accountKey(b1, b2, slot)
	return CeroSecContent.key("a", b1, b2, slot)
end

-- One slot's login, which both the prefill and a paper derive for themselves.
function CeroSecContent.accountLogin(secret, b1, b2, slot)
	return CeroSecContent.login(secret, CeroSecContent.accountKey(b1, b2, slot))
end

-- And its password. The login goes INTO the key as well as the slot, so a wave
-- that reordered a profile's accounts would change the password of an account that
-- kept its name, rather than quietly handing one person another's password.
function CeroSecContent.accountPassword(secret, b1, b2, slot, login)
	return CeroSecContent.password(secret,
		CeroSecContent.key("ap", b1, b2, slot, login))
end

-- The slots of a profile that have a password on them, as an array of slot
-- numbers. What a paper in a pocket may name, and the one place that list is
-- worked out: an empty one is a profile whose people are all open accounts, and
-- there is nothing to write on a paper about those.
function CeroSecContent.lockedSlots(profile)
	local out = {}
	if type(profile) ~= "table" or type(profile.accounts) ~= "table" then return out end
	for i = 1, #profile.accounts do
		if profile.accounts[i].pass then out[#out + 1] = i end
	end
	return out
end

-- Everything else about a machine is keyed on the premises AND the machine's
-- own square, so two computers in one office are two people's computers.
function CeroSecContent.machineKey(b1, b2, x, y, z)
	return CeroSecContent.key("m", b1, b2, x, y, z)
end

-- How many days before day one the oldest log line is written. A week: the last
-- week anybody came to work, which is what a survivor reading /var/log is
-- looking at.
CeroSecContent.LOG_DAYS = 7

-- The one place a file is put on a prefilled machine. It answers nothing: a
-- refusal -- a full disk, a directory at 96 entries, a byte the machine will not
-- carry -- means this file is not on this machine, and the next one is tried.
-- That is the trimming rule, in one function, so no caller can forget it.
local function place(state, session, path, owner, mode, text, now)
	if type(text) ~= "string" then return false end
	local node = CeroSecOS.newFile(owner, mode or 644, text)
	return CeroSecOS.createNode(state, session, path, node, now) ~= nil
end

local function placeDir(state, session, path, owner, mode, now)
	local at = CeroSecOS.systemNode(state, path)
	if type(at) == "table" and at.type == "dir" then return true end
	local node = CeroSecOS.newDir(owner, mode or 755)
	return CeroSecOS.createNode(state, session, path, node, now) ~= nil
end


-- The accounts a profile asks for, made and (some of them) given a password.
-- Answers the array of logins it actually made, in order, because the files and
-- the mail are addressed to them by index.
--
-- A home is made BEFORE the account, because CeroSecOS.addUser writes the line
-- and nothing else -- a home is a directory somebody has to make, exactly as
-- `useradd` on this machine makes one. An account whose home would not fit gets
-- "/" for a home, which is what a machine with a full disk leaves somebody with,
-- and is still an account that can log in.
--
-- What comes back is indexed BY SLOT and not by how many accounts were made:
-- slots[3] is the third entry of profile.accounts or nil, so the files, the
-- scripts and the mail are addressed to the person the profile meant even when
-- an earlier slot was skipped. A dense list would have handed slot 2's files to
-- slot 3's login the moment one name collided with "admin".
local function makeAccounts(state, session, profile, secret, b1, b2, mkey, now)
	local made = {}
	if type(profile.accounts) ~= "table" then return made end
	for i = 1, #profile.accounts do
		local account = profile.accounts[i]
		local name = account.name
		if type(name) ~= "string" then
			name = CeroSecContent.accountLogin(secret, b1, b2, i)
		end
		if not CeroSecOS.isValidUserName(name) then name = nil end
		-- A login the machine already has -- "root", "admin", or the same name
		-- generated twice for two slots -- is not a second account. The slot keeps
		-- the name, so the files it asks for land in the home that is already
		-- there, and nothing is added to /etc/passwd.
		if name ~= nil and CeroSecOS.getUser(state, name) == nil then
			local home = "/home/" .. name
			if not placeDir(state, session, home, name, CeroSecOS.HOME_MODE, now) then
				home = "/"
			end
			if CeroSecOS.addUser(state, name, home, account.admin and true or false,
					mkey .. ":" .. i, now) == nil then
				name = nil
			end
		end
		if name ~= nil then
			if account.pass then
				local password =
					CeroSecContent.accountPassword(secret, b1, b2, i, name)
				-- A refusal here leaves the account OPEN, which is a machine somebody
				-- can still get into. The reverse -- a password set that the note does
				-- not know -- is the one outcome that locks a player out, and it cannot
				-- happen: the note derives the letters and never reads them.
				CeroSecOS.setPassword(state, name, password, mkey .. ":p" .. i, now)
			end
			made[i] = name
		end
	end
	return made
end

-- The files one account's slot asks for, under its own home. A path in a profile
-- is relative to the home and never absolute: an account's files belong to the
-- account, and a profile that could write anywhere would be a profile that could
-- rewrite /etc/passwd.
local function placeHomeFiles(state, session, account, login, now)
	if type(account.files) ~= "table" then return end
	local home = "/home/" .. login
	for i = 1, #account.files do
		local file = account.files[i]
		if type(file.path) == "string" and string.find(file.path, "/") == nil then
			place(state, session, home .. "/" .. file.path, login, file.mode or 644,
				file.text, now)
		end
	end
end

-- The scripts one profile puts in an account's ~/bin, each behind its own roll.
-- ~/bin and not /bin: /bin is the SYSTEM's and upgradeSystem tops it up, so a
-- script of ours in there would be a script the next version argues about. A
-- survivor's own ~/bin is already on his path (see the manual's chapter on where
-- commands come from).
local function placeScripts(state, session, profile, secret, mkey, login, now)
	if type(profile.bin) ~= "table" then return end
	local made = false
	for i = 1, #profile.bin do
		local entry = profile.bin[i]
		local script = CeroSecContent.SCRIPTS[entry.script]
		if script ~= nil
				and CeroSecContent.chance(secret,
					CeroSecContent.key(mkey, "bin", entry.script), entry.chance or 100) then
			if not made then
				made = placeDir(state, session, "/home/" .. login .. "/bin", login, 755, now)
			end
			if made then
				place(state, session, "/home/" .. login .. "/bin/" .. entry.script, login,
					script.mode, script.text, now)
			end
		end
	end
end

-- /var/log/messages: the last week anybody came to work, oldest line first.
--
-- The dates are the machine's OWN format (CeroSecOS.formatStamp -- "Jul  8
-- 14:32", twelve columns, what `ls -l` prints), because a log a survivor reads
-- with `cat` on a 60 column screen must look like the rest of the machine.
--
-- The clock is the SAVE's start date and not a number written here: the server
-- reads it off getGameTime() (getStartYear, getStartMonth + 1, getStartDay + 1 --
-- the same zero-based encoding SCeroSecSystem:clockEnv already uses for
-- getMonth/getDay, and the constructor sets both pairs from the same literals)
-- and hands over the second. So the default save's lines are dated in July 1993
-- because that is when the default save starts, and a save that starts elsewhere
-- gets a log dated there instead of a lie.
local function placeLog(state, session, profile, secret, mkey, startTime, now)
	if type(profile.logs) ~= "table" or #profile.logs == 0 then return end
	if type(startTime) ~= "number" then return end
	local lines = {}
	local days = CeroSecContent.LOG_DAYS
	-- MIDNIGHT of the start day and not the start moment: the save begins at nine
	-- in the morning, and an hour added to that put half the week's work after
	-- dark. A day is what the arithmetic below steps in, so a day is where it
	-- starts from.
	local midnight = math.floor(startTime / 86400) * 86400
	for i = 1, #profile.logs do
		-- Spread over the week, oldest first, with the hour rolled out of the line's
		-- own key so two machines do not have an identical morning.
		local back = days - math.floor((i - 1) * days / #profile.logs)
		local hour = CeroSecContent.number(secret,
			CeroSecContent.key(mkey, "logh", i), 10) + 7
		local minute = CeroSecContent.number(secret,
			CeroSecContent.key(mkey, "logm", i), 60) - 1
		local at = midnight - back * 86400 + hour * 3600 + minute * 60
		-- Cut to the width of the screen, HERE, by the one function that composes
		-- the line. A survivor reads this file with `cat` on a sixty column terminal
		-- that does not wrap, so a line longer than sixty is a line whose end nobody
		-- can ever read -- and the hostname in front of the message is up to sixteen
		-- characters of it. Cutting it here means wave 7b cannot write a message
		-- that disappears off the right of the glass.
		local line = CeroSecOS.formatStamp(at) .. " " .. state.hostname
			.. " " .. profile.logs[i]
		lines[#lines + 1] = string.sub(line, 1, CeroSecOS.COLS)
	end
	place(state, session, CeroSecOS.LOG_PATH .. "/messages", "root",
		CeroSecOS.CRON_LOG_MODE, table.concat(lines, "\n"), now)
end

-- /var/mail/<login>: the mail somebody had not read. The format is the one the
-- machine's own `mail` writes (CeroSecOS.mailAppend), which is the only format
-- the machine can read back.
local function placeMail(state, session, profile, logins, now)
	if type(profile.mail) ~= "table" then return end
	for i = 1, #profile.mail do
		local item = profile.mail[i]
		local to = item.to
		if type(to) == "number" then to = logins[to] end
		if type(to) == "string" and CeroSecOS.getUser(state, to) ~= nil then
			local body = item.body
			if type(item.subj) == "string" then
				body = "Subject: " .. item.subj .. "\n\n" .. tostring(body)
			end
			if type(item.from) == "string" then
				body = "From: " .. item.from .. "\n" .. body
			end
			place(state, session, CeroSecOS.mailPath(to), to, CeroSecOS.MAIL_MODE,
				body, now)
		end
	end
end

--
-- PREFILL ONE MACHINE. The one entry point the server calls, and it is called in
-- exactly one place: SCeroSecObject:turnOn, for a machine whose state was nil a
-- moment ago. Never for a state that already existed -- a machine somebody has
-- used is his.
--
--   state       a state CeroSecOS.newState has just made
--   opts        { secret=, b1=, b2=, x=, y=, z=, premises=, rooms=, start=, now= }
--
-- Answers the profile id it used and the root password it derived, or nil for a
-- machine it left alone. The password is answered for the BENCH and for the
-- sticky note's sake and is written nowhere: the caller may not keep it.
--
-- Order matters and this is the order: the hostname, then the accounts (because
-- everything else is addressed to them), then their files and scripts, then the
-- machine-wide files, then the motd, then the log and the mail. Everything after
-- a refusal still runs -- a full disk trims the tail of a profile and never its
-- head.
--
function CeroSecContent.prefill(state, opts)
	if type(state) ~= "table" or type(opts) ~= "table" then return nil end
	if not CeroSecContent.isSecret(opts.secret) then return nil end
	local id = CeroSecContent.profileFor(opts.premises, opts.rooms)
	local profile = CeroSecContent.PROFILES[id]
	-- An id wave 7b has not filled in yet. A bare machine, which is what one was
	-- before this file existed, and not an error.
	if type(profile) ~= "table" then return nil end

	local secret = opts.secret
	local mkey = CeroSecContent.machineKey(opts.b1, opts.b2, opts.x, opts.y, opts.z)
	local now = opts.now
	local session = CeroSecOS.rootSession()

	-- The name on the machine. The head is the profile's and the tail is the
	-- coordinates the engine already derived, so the name still says where the
	-- machine is and /etc/hosts, the prompt and ruptime all agree with each other.
	if type(profile.host) == "string" then
		local tail = string.match(state.hostname or "", "^[a-z0-9]+(%-.*)$")
		if tail ~= nil then
			local hostname = string.sub(profile.host .. tail, 1, CeroSecOS.HOSTNAME_MAX)
			if CeroSecOS.isValidHostname(hostname) then
				CeroSecOS.setHostname(state, hostname, now)
			end
		end
	end

	local logins =
		makeAccounts(state, session, profile, secret, opts.b1, opts.b2, mkey, now)
	local first = nil
	if type(profile.accounts) == "table" then
		for i = 1, #profile.accounts do
			local login = logins[i]
			if login ~= nil then
				if first == nil then first = login end
				placeHomeFiles(state, session, profile.accounts[i], login, now)
			end
		end
	end
	-- The scripts go in the FIRST account's ~/bin: a profile's first slot is the
	-- person whose machine it is, and a copy in every home would be the same file
	-- three times on a 64K disk.
	if first ~= nil then
		placeScripts(state, session, profile, secret, mkey, first, now)
	end

	if type(profile.files) == "table" then
		for i = 1, #profile.files do
			local file = profile.files[i]
			if type(file.path) == "string" then
				place(state, session, file.path, file.owner or "root", file.mode,
					file.text, now)
			end
		end
	end

	if type(profile.motd) == "string" then
		CeroSecOS.setData(state, session, CeroSecOS.MOTD_PATH, profile.motd, now)
	end

	placeLog(state, session, profile, secret, mkey, opts.start, now)
	placeMail(state, session, profile, logins, now)

	-- And root's own password, LAST, so that everything above it happened as root
	-- on a machine whose root account was still open -- and so that a refusal
	-- anywhere above cannot leave a machine locked with nothing on it.
	local password = nil
	if profile.root then
		password = CeroSecContent.password(secret,
			CeroSecContent.rootKey(opts.b1, opts.b2))
		if password ~= nil then
			CeroSecOS.setPassword(state, "root", password, mkey .. ":root", now)
		end
	end
	return id, password, logins
end

--
-- THE PROFILES
--
-- Two written, eight named and empty. The texts are SHORT PLACEHOLDERS in the
-- manual's voice: wave 7b writes the library and the lore, and it writes it into
-- these tables without touching a line of code above.
--
-- Every line of every text is inside 60 columns, because a survivor reads it with
-- `cat` on a 60 column screen and the terminal does not wrap. The bench holds
-- every one of them to it.
--

CeroSecContent.PROFILES = {}

CeroSecContent.PROFILES.residential = {
	host = "ksp",
	motd = table.concat({
		"This machine belongs to somebody who paid for it.",
		"Please do not change the wallpaper.",
	}, "\n"),
	accounts = {
		{ pass = false, files = {
			{ path = "notes.txt", text = table.concat({
				"Things to do before the weekend:",
				"",
				"- ring the bank about the cheque",
				"- the porch light is on a timer now, ask Dad",
				"- FIND THE MANUAL",
			}, "\n") },
		} },
	},
	bin = { { script = "lights.sh", chance = 35 } },
	logs = {
		"login: admin logged in on console",
		"login: admin logged in on console",
	},
}

CeroSecContent.PROFILES.office = {
	host = "acct",
	motd = table.concat({
		"CeroSec OS -- authorised users only.",
		"Log out when you leave your desk. This is not a",
		"suggestion from us, it is one from the insurer.",
	}, "\n"),
	root = true,
	accounts = {
		{ pass = true, admin = true, files = {
			{ path = "handover.txt", text = table.concat({
				"Whoever is covering for me:",
				"",
				"The nightly job mails the totals to root. If the",
				"mail stops, the job stopped -- look at crontab -l",
				"before you look at anything else.",
			}, "\n") },
		} },
		{ pass = false, files = {
			{ path = "readme.txt", text = table.concat({
				"My password is my own business. Ask me and I will",
				"type it for you.",
			}, "\n") },
		} },
	},
	bin = { { script = "lights.sh", chance = 60 } },
	logs = {
		"login: root logged in on console",
		"cron: ran the nightly totals",
		"login: failed login on console",
		"cron: ran the nightly totals",
	},
	mail = {
		{ to = "root", from = "head office", subj = "the new passwords",
			body = table.concat({
				"Nobody is to write a password down where it can be",
				"read. We will be checking the desks.",
			}, "\n") },
	},
}

-- Named, and empty until wave 7b. A machine whose premises resolves to one of
-- these is prefilled with nothing, which is exactly what a machine was before
-- this file existed.
CeroSecContent.PROFILES.police = nil
CeroSecContent.PROFILES.bank = nil
CeroSecContent.PROFILES.store = nil
CeroSecContent.PROFILES.school = nil
CeroSecContent.PROFILES.clinic = nil
CeroSecContent.PROFILES.radio = nil
CeroSecContent.PROFILES.military = nil
CeroSecContent.PROFILES.cerosec = nil
