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
-- about a machine somebody has already switched on. Bumped when a change adds or
-- rewrites entries, and read by nothing but the bench and docs/CONTENT.md.
CeroSecContent.VERSION = 3

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
	-- CeroSecOS.mod and not math.fmod: v reaches 2^32 and n is small, so the
	-- quotient passes 2^31. math.fmod happens to agree on both VMs at that size,
	-- but the rule the mod holds is one function for a modulo, and it is that one.
	-- Same value either way: v is never negative and n is at least 1.
	return math.floor(CeroSecOS.mod(v, math.floor(n))) + 1
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
-- the world-content work, part 2 lengthened both lists to forty-four apiece. Nothing derived from them
-- is stored, so a longer list changes the next untouched machine and no machine
-- already switched on -- a save in progress keeps every person it already had.
--
-- The ten added to each are the ones the shipped thirty-four were short of: the
-- names of somebody who was of working age in KENTUCKY in 1993 and not of
-- somebody the census counted nationally. Hensley, Mullins, Sizemore and
-- Whitaker are eastern-Kentucky surnames the way Smith is an American one -- a
-- county office with four Millers in it and nobody called Sizemore reads as a
-- county somewhere else.
--

CeroSecContent.NAMES = {
	first = {
		"james", "robert", "john", "michael", "david", "william", "richard",
		"joseph", "thomas", "charles", "mary", "patricia", "linda", "barbara",
		"elizabeth", "jennifer", "susan", "margaret", "dorothy", "carol",
		"donald", "kenneth", "steven", "edward", "brian", "ronald", "anthony",
		"nancy", "karen", "betty", "helen", "sandra", "donna", "ruth",
		"gary", "larry", "dennis", "wayne", "curtis", "earl", "sharon",
		"wanda", "darlene", "peggy",
	},
	last = {
		"smith", "johnson", "williams", "brown", "jones", "miller", "davis",
		"wilson", "moore", "taylor", "anderson", "thomas", "jackson", "white",
		"harris", "martin", "thompson", "garcia", "martinez", "robinson",
		"clark", "rodriguez", "lewis", "lee", "walker", "hall", "allen",
		"young", "king", "wright", "scott", "torres", "hill", "green",
		"adams", "baker", "campbell", "carter", "coleman", "hatfield",
		"hensley", "mullins", "sizemore", "whitaker",
	},
}

-- A login for one person. `key` is the whole of what decides it, so the same
-- account on the same machine is the same person for ever.
--
-- Three shapes, chosen by a roll of their own, and then the fallbacks: a shape
-- that comes out too long for MAX_USERNAME falls back to the first name, and a
-- first name that is somehow not a valid login falls back to "user". Neither
-- can happen with the lists above -- the bench proves every combination -- and
-- both are here because the lists are what the world-content work, part 2 is going to lengthen.
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
	"chestnut", "sycamore", "bluegrass", "trestle",
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
-- THE PROFILE FORMAT -- and this is the part the world-content work, part 2 writes against.
--
--   PROFILES[id] = {
--     host     = "acct",     head of the hostname; the coordinate tail is kept
--     motd     = "...",      /etc/motd, at most MOTD_MAX_LINES lines of 60 cols
--     accounts = { { name=, admin=, pass=, files={ {path,mode,texts} } }, ... },
--     root     = true,       a root password to derive, hash and never store
--     logs     = { "..." },  lines for /var/log/messages, dated before day one
--     mail     = { { to=, from=, subj=, body= } },
--     cron     = { { to=1, lines={ "0 22 * * * ..." } } },
--     bin      = { { script="lights.sh", chance=60, to="/usr/local/src" } },
--     files    = { { path=, mode=, owner=, texts= }, { path=, dir=true } },
--   }
--
-- ONE MACHINE IS ONE PERSON'S DESK (the world-content work, part 3). The accounts are the PREMISES' and
-- every machine in the building has all of them, with their passwords -- but only
-- ONE of them has files on this machine, chosen by the machine's own key
-- (CeroSecContent.ownerSlot). The others' homes hold their dot-files and nothing
-- else. That is what an office is, and it is what the complaint that started this
-- change was about: three accounts' homes written onto every desk in the room is one
-- machine copied three times.
--
-- AND EVERY PROSE FILE HAS THREE TELLINGS (the world-content work, part 3). An entry carries `texts`, an
-- array of CeroSecContent.VARIANTS of them, and which one a premises reads is the
-- premises' own (CeroSecContent.variantOf) -- so the office down the road tells the
-- same kind of story in other words, with its own people's names put in where the
-- text wrote {owner}, {staff1} and {host} (CeroSecContent.fillNames). A `text` is
-- still legal and still means one telling; `extra` is three tails under a `text`,
-- which is how a data table varies without moving the rows a script is proved on.
-- All of it goes through CeroSecContent.textFor, which is the one place a text is
-- composed.
--
-- THE RULE THE THREE TELLINGS ARE WRITTEN TO, and it is not obvious: a variant is
-- picked PER FILE, so telling 2 of the handover note stands beside telling 1 of the
-- ledger. Any three may therefore be read together -- which means a fact one file
-- depends on another for (the column that is cents, the name of a script, a device
-- id) must be the SAME in all three tellings of both. What varies is the voice, the
-- person writing, the detail and the complaint; never the machine underneath.
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
-- And three things the world-content work, part 2 added, each because a premises the county really has
-- could not be written without it:
--
--   * `cron` is a crontab per account, in Vixie's own five fields, written to
--     /var/spool/cron/<login> exactly where crontab(1) writes one. `to` is a slot
--     number or a literal login, the way `mail`'s is. It is a real crontab and the
--     machine really runs it, which is the point: a shop whose lights went off at
--     ten every night is a shop whose lights still go off at ten. The bench holds
--     every one of them to CeroSecOS.checkCrontab -- a crontab the machine's own
--     crontab(1) would refuse is a crontab that does nothing and says nothing.
--   * a `files` entry with `dir = true` is a DIRECTORY and not a file. A profile
--     that wanted a tree of its own -- /usr/local/src on the vendor's own machine
--     -- had no way to make one, and a path whose parent is missing is a file the
--     gate refuses for a reason nothing in the catalogue could see.
--   * a `bin` entry may name `to`, an absolute directory, instead of going into
--     the first account's ~/bin. The directory and its parents are made if they
--     are missing. One script still has one copy: `to` moves where the copy is
--     put and never what is in it.
--
-- The ten ids exist now and eight of them are deliberately EMPTY. A machine
-- whose premises resolves to an empty id is prefilled with nothing at all, which
-- is exactly a bare machine -- so the world-content work, part 2 fills a table and changes no code.
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
	-- bench asserts. An id nothing resolves to is a profile the world-content work, part 2 would write and
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
--   SCRIPTS[name] = { mode = 755, needs = { devices = { {id=,kind=} },
--                                          files = { {path=,text=} } },
--                     args = { "light0" }, input = { "y" }, text = "..." }
--
-- `args` is what the bench runs it WITH, and it is part of the library because a
-- script whose usage nobody recorded is a script nobody can prove runs.
--
-- `needs.files` is the other half of `needs.devices` and was added for the same
-- reason: a script that reads a file cannot be proved by running it on a machine
-- where the file is not there. The bench writes exactly what is declared, under the
-- account's own home, and nothing else -- so a script that quietly reached for a
-- second file finds it missing, which is the whole point of declaring.
--
-- `input` is what somebody TYPES at it: the lines a `read` is answered with, in
-- order. A program that asks questions -- a game -- cannot be proved by running it
-- and reading what came back, because nothing comes back until it has been
-- answered. The bench answers it through CeroSecOS.jobInput, which is the one door
-- an answer goes through on a real machine, and holds the recorded lines to playing
-- it to the END: a script still waiting when the list runs out is a script whose
-- usage nobody really recorded.
--
-- THE USAGE RULE, and what it is for. A script somebody found and typed the name of
-- must say how it is used and must not claim success -- so the bench runs every one
-- of them with NO arguments as well. A script that takes none (`args = {}`) is not
-- held to it, there being no wrong way to run it; and it cannot get out of the rule
-- by declaring so, because the bench also asks whether the text mentions `$1`.
--
-- WHAT IS IN HERE, and the rule the world-content work, part 2 wrote it to. Thirteen scripts: four that
-- work the building (lights, lockup, unlock, check), five that work a file
-- (audit, total, rounds, announce, sweep), one that keeps a log (log.sh), and
-- three that are games. Every one of them is a TEMPLATE and not a tool -- the
-- point is that a survivor reads it with `cat`, sees how the trick is done, and
-- writes his own. So each does ONE thing, takes its devices and its files on the
-- command line rather than naming any, and is short enough to read on one screen.
-- A script that hard-coded `light0` would work on exactly one building in Knox
-- County and teach nothing.
--
-- The data files a script is FOR, and they are up here rather than beside the
-- profile that ships them because a script and its file are one pair: audit.sh
-- is proved by the bench against the very accounts.dat the bank's own machine
-- carries, and total.sh against the shop's own prices. One copy, named twice --
-- once by the script that reads it and once by the premises that keeps it -- so
-- the two cannot drift into a script proved on a file nobody has.
CeroSecContent.DATA = {}

CeroSecContent.DATA["accounts.dat"] = table.concat({
	"1041:checking:1987:21400",
	"1042:savings:1991:138050",
	"1043:checking:1990:4712",
	"1044:checking:1984:0",
	"1045:savings:1993:62000",
	"1046:checking:1992:9980",
}, "\n")
CeroSecContent.DATA["prices.txt"] = table.concat({
	"nails 3in:189",
	"rope 50ft:1250",
	"lamp oil:399",
	"tarp 8x10:875",
	"batteries:249",
	"padlock:1195",
}, "\n")
CeroSecContent.DATA["patients.txt"] = table.concat({
	"101:a:for discharge",
	"104:b:two more days",
	"106:b:waiting on a bed",
	"108:a:transferred out",
	"112:b:for discharge",
}, "\n")
CeroSecContent.DATA["sched.txt"] = table.concat({
	"06 farm report and the weather",
	"09 the morning show",
	"12 news, then the swap shop",
	"15 records until the shift change",
	"18 news",
	"21 the county board, when it sits",
}, "\n")
CeroSecContent.DATA["WORDS.TXT"] = table.concat({
	"lantern",
	"bourbon",
	"trestle",
	"hickory",
	"tobacco",
	"derby",
	"limestone",
	"sycamore",
}, "\n")

CeroSecContent.SCRIPTS = {}

CeroSecContent.SCRIPTS["lights.sh"] = {
	-- The one everybody copies first: a row of light switches, off, in
	-- one line. It is the shape every other script here is a variation on.
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
		"  echo \"usage: lights.sh <light> [<light> ...]\"",
		"  exit 1",
		"fi",
		"while [ $# -gt 0 ]; do",
		"  echo off > /dev/$1",
		"  echo \"$1 off\"",
		"  shift",
		"done",
	}, "\n"),
}

CeroSecContent.SCRIPTS["lockup.sh"] = {
	-- Closing up. Two devices and the one habit worth teaching: it READS
	-- the door back before it locks anything, because locking a door that
	-- would not close locks nothing and says it did.
	mode = 755,
	args = { "door0", "lock0" },
	needs = { devices = {
		{ id = "door0", kind = "door", state = "open" },
		{ id = "lock0", kind = "lock", state = "unlocked" },
	} },
	text = table.concat({
		"#!/bin/sh",
		"# lockup.sh -- close a door, then lock it, in that order.",
		"# usage: lockup.sh <door> <lock>",
		"if [ $# -ne 2 ]; then",
		"  echo \"usage: lockup.sh <door> <lock>\"",
		"  exit 1",
		"fi",
		"echo close > /dev/$1",
		"# Read it back. A door with something in the way does not",
		"# close, and locking one that is open locks nothing.",
		"if [ \"$(cat /dev/$1)\" != closed ]; then",
		"  echo \"$1 will not close. Something is in the way.\"",
		"  exit 1",
		"fi",
		"echo \"$1 closed\"",
		"echo lock > /dev/$2",
		"echo \"$2 $(cat /dev/$2)\"",
	}, "\n"),
}

CeroSecContent.SCRIPTS["locks.sh"] = {
	-- Both directions of a row of locks, which is the shape a shift and a word
	-- argument are for: two scripts differing by one verb would have been two
	-- files to keep in step, and the interesting half of this one is that a
	-- survivor can read how the verb gets out of the way of the list.
	mode = 755,
	args = { "lock", "lock0", "lock1" },
	needs = { devices = {
		{ id = "lock0", kind = "lock", state = "unlocked" },
		{ id = "lock1", kind = "lock", state = "unlocked" },
	} },
	text = table.concat({
		"#!/bin/sh",
		"# locks.sh -- lock or unlock every lock you name.",
		"# usage: locks.sh lock|unlock <lock> [<lock> ...]",
		"if [ $# -lt 2 ]; then",
		"  echo \"usage: locks.sh lock|unlock <lock> [<lock> ...]\"",
		"  exit 1",
		"fi",
		"w=$1",
		"if [ \"$w\" != lock -a \"$w\" != unlock ]; then",
		"  echo \"usage: locks.sh lock|unlock <lock> [<lock> ...]\"",
		"  exit 1",
		"fi",
		"shift",
		"while [ $# -gt 0 ]; do",
		"  echo $w > /dev/$1",
		"  echo \"$1 $(cat /dev/$1)\"",
		"  shift",
		"done",
	}, "\n"),
}

CeroSecContent.SCRIPTS["check.sh"] = {
	-- Which door did they leave open. Counts as it goes, which is the little
	-- thing that turns a listing into an answer.
	mode = 755,
	args = { "door0", "door1" },
	needs = { devices = {
		{ id = "door0", kind = "door", state = "open" },
		{ id = "door1", kind = "door", state = "closed" },
	} },
	text = table.concat({
		"#!/bin/sh",
		"# check.sh -- which of the doors you name is standing open.",
		"# usage: check.sh <door> [<door> ...]",
		"if [ $# -eq 0 ]; then",
		"  echo \"usage: check.sh <door> [<door> ...]\"",
		"  exit 1",
		"fi",
		"n=0",
		"while [ $# -gt 0 ]; do",
		"  s=$(cat /dev/$1)",
		"  if [ \"$s\" = open ]; then",
		"    echo \"$1 OPEN\"",
		"    n=$((n + 1))",
		"  else",
		"    echo \"$1 $s\"",
		"  fi",
		"  shift",
		"done",
		"echo \"$n of them open\"",
	}, "\n"),
}

CeroSecContent.SCRIPTS["audit.sh"] = {
	-- The bank's. grep with a count in front of it, which is what an audit of
	-- a columns file was in 1993 and still is.
	--
	-- Proved against the very accounts.dat the bank ships (CeroSecContent.DATA):
	-- a script proved on a file of the bench's own invention is a script nobody
	-- has run on the thing it is for.
	mode = 755,
	args = { "accounts.dat", "checking" },
	needs = { files = {
		{ path = "accounts.dat", text = CeroSecContent.DATA["accounts.dat"] },
	} },
	text = table.concat({
		"#!/bin/sh",
		"# audit.sh -- the lines of a file that mention a word.",
		"# usage: audit.sh <file> <word>",
		"if [ $# -ne 2 ]; then",
		"  echo \"usage: audit.sh <file> <word>\"",
		"  exit 1",
		"fi",
		"if [ ! -f $1 ]; then",
		"  echo \"audit.sh: $1: no such file\"",
		"  exit 1",
		"fi",
		"n=$(grep -c $2 $1)",
		"echo \"$1: $n line(s) with $2 in them\"",
		"grep -n $2 $1",
	}, "\n"),
}

CeroSecContent.SCRIPTS["total.sh"] = {
	-- The shop's till. cut into a for loop into $(( )), which is the whole of
	-- how this machine adds a column up.
	mode = 755,
	args = { "prices.txt", "2" },
	needs = { files = {
		{ path = "prices.txt", text = CeroSecContent.DATA["prices.txt"] },
	} },
	text = table.concat({
		"#!/bin/sh",
		"# total.sh -- add up one colon-separated column of a file.",
		"# usage: total.sh <file> <column>",
		"if [ $# -ne 2 ]; then",
		"  echo \"usage: total.sh <file> <column>\"",
		"  exit 1",
		"fi",
		"if [ ! -f $1 ]; then",
		"  echo \"total.sh: $1: no such file\"",
		"  exit 1",
		"fi",
		"t=0",
		"for n in $(cut -d : -f $2 $1); do",
		"  t=$((t + n))",
		"done",
		"echo \"column $2 of $1 adds up to $t\"",
	}, "\n"),
}

CeroSecContent.SCRIPTS["rounds.sh"] = {
	-- The clinic's. A list to walk, in order, off a file somebody kept by
	-- hand: cut into sort, and the count underneath it.
	mode = 755,
	args = { "patients.txt" },
	needs = { files = {
		{ path = "patients.txt", text = CeroSecContent.DATA["patients.txt"] },
	} },
	text = table.concat({
		"#!/bin/sh",
		"# rounds.sh -- the first column of a colon file, sorted.",
		"# usage: rounds.sh <file>",
		"if [ $# -ne 1 ]; then",
		"  echo \"usage: rounds.sh <file>\"",
		"  exit 1",
		"fi",
		"if [ ! -f $1 ]; then",
		"  echo \"rounds.sh: $1: no such file\"",
		"  exit 1",
		"fi",
		"cut -d : -f 1 $1 | sort",
		"echo \"-- $(cat $1 | wc -l) of them, in order\"",
	}, "\n"),
}

CeroSecContent.SCRIPTS["announce.sh"] = {
	-- The station's, and the one built to run from cron: it asks the clock what
	-- hour it is and prints the line of the sheet for it. A cron line has no
	-- screen, so what it prints arrives in the mail, which is where a survivor
	-- finds out the machine was still doing its job while nobody was there.
	mode = 755,
	args = { "sched.txt" },
	needs = { files = {
		{ path = "sched.txt", text = CeroSecContent.DATA["sched.txt"] },
	} },
	text = table.concat({
		"#!/bin/sh",
		"# announce.sh -- print the line of a table for this hour.",
		"# usage: announce.sh <file>",
		"if [ $# -ne 1 ]; then",
		"  echo \"usage: announce.sh <file>\"",
		"  exit 1",
		"fi",
		"h=$(date +%H)",
		"line=$(grep \"$h \" $1)",
		"if [ -z \"$line\" ]; then",
		"  echo \"$h:00 nothing on the sheet\"",
		"  exit 0",
		"fi",
		"echo \"$h:00 $(echo $line | cut -d ' ' -f 2-9)\"",
	}, "\n"),
}

CeroSecContent.SCRIPTS["sweep.sh"] = {
	-- What is on this machine. The one that teaches `find`, and the one to run
	-- first on a computer nobody has ever sat at.
	mode = 755,
	args = { "/etc" },
	text = table.concat({
		"#!/bin/sh",
		"# sweep.sh -- every file under a directory, and how many.",
		"# usage: sweep.sh <dir>",
		"if [ $# -ne 1 ]; then",
		"  echo \"usage: sweep.sh <dir>\"",
		"  exit 1",
		"fi",
		"find $1 -type f | sort",
		"echo \"-- $(find $1 -type f | wc -l) file(s) under $1\"",
	}, "\n"),
}

CeroSecContent.SCRIPTS["log.sh"] = {
	-- The wardialer's book. It does not dial -- see the WARDIALER entry in the
	-- disk catalogue for why nothing can -- it writes down what happened when
	-- you did, with the date on it, which is the half a machine can do.
	mode = 755,
	args = { "418-2201", "answered" },
	text = table.concat({
		"#!/bin/sh",
		"# log.sh -- one line in calls.log: date, number, word.",
		"# usage: log.sh <number> <word>",
		"if [ $# -ne 2 ]; then",
		"  echo \"usage: log.sh <number> <word>\"",
		"  exit 1",
		"fi",
		"echo \"$(date) $1 $2\" >> calls.log",
		"tail -n 1 calls.log",
	}, "\n"),
}

CeroSecContent.SCRIPTS["guess.sh"] = {
	-- And three that are only games, because a 1993 desk machine had games on
	-- it and they are how somebody learned what `read` was.
	--
	-- The number comes off the SECOND HAND of the machine's own clock, which is
	-- what a shell script had instead of a random number in 1993. So the bench
	-- knows the answer -- its clock is nine in the morning exactly -- and the
	-- recorded goes are a binary search that finds it.
	mode = 755,
	args = { "20" },
	input = { "10", "15", "14" },
	text = table.concat({
		"#!/bin/sh",
		"# guess.sh -- the machine picks a number, you find it.",
		"# usage: guess.sh <top>",
		"if [ $# -ne 1 ]; then",
		"  echo \"usage: guess.sh <top>\"",
		"  exit 1",
		"fi",
		"top=$1",
		"s=$(date +%S)",
		"s=$((s * 7 + 13))",
		"n=$((s % top))",
		"n=$((n + 1))",
		"echo \"A number between 1 and $top. Eight goes.\"",
		"t=1",
		"while [ $t -le 8 ]; do",
		"  read -p \"$t: \" g",
		"  bad=$(echo $g | tr -d 0-9)",
		"  if [ -z \"$g\" ]; then",
		"    echo \"A number, please.\"",
		"  elif [ -n \"$bad\" ]; then",
		"    echo \"Digits only.\"",
		"  elif [ $g -lt $n ]; then",
		"    echo \"Higher.\"",
		"    t=$((t + 1))",
		"  elif [ $g -gt $n ]; then",
		"    echo \"Lower.\"",
		"    t=$((t + 1))",
		"  else",
		"    echo \"That is it. $n, in $t.\"",
		"    exit 0",
		"  fi",
		"done",
		"echo \"Out of goes. It was $n.\"",
	}, "\n"),
}

CeroSecContent.SCRIPTS["hangman.sh"] = {
	-- The masking is three calls to `tr` and no loop over characters: the
	-- guessed letters are turned into capitals, and then every letter still in
	-- lower case becomes a dot. It is the trick worth reading the file for.
	mode = 755,
	args = { "WORDS.TXT" },
	needs = { files = {
		{ path = "WORDS.TXT", text = CeroSecContent.DATA["WORDS.TXT"] },
	} },
	-- The word is the sixth line at nine in the morning, and the letters of it
	input = { "d", "e", "r", "b", "y" },
	text = table.concat({
		"#!/bin/sh",
		"# hangman.sh -- guess the word, a letter at a time.",
		"# usage: hangman.sh <word file>",
		"if [ $# -ne 1 ]; then",
		"  echo \"usage: hangman.sh <word file>\"",
		"  exit 1",
		"fi",
		"if [ ! -f $1 ]; then",
		"  echo \"hangman.sh: $1: no such file\"",
		"  exit 1",
		"fi",
		"c=$(cat $1 | wc -l)",
		"s=$(date +%S)",
		"s=$((s * 3 + 5))",
		"p=$((s % c))",
		"p=$((p + 1))",
		"w=$(head -n $p $1 | tail -n 1)",
		"got=\"\"",
		"left=6",
		"while [ $left -gt 0 ]; do",
		"  if [ -z \"$got\" ]; then",
		"    shown=$(echo $w | tr a-z .)",
		"  else",
		"    up=$(echo $got | tr a-z A-Z)",
		"    shown=$(echo $w | tr $got $up)",
		"    shown=$(echo $shown | tr a-z .)",
		"  fi",
		"  if [ $(echo $shown | grep -c .) -eq 0 ]; then",
		"    echo \"$w. You have it.\"",
		"    exit 0",
		"  fi",
		"  echo \"$shown    $left wrong left\"",
		"  read -p \"letter? \" l",
		"  if [ -z \"$l\" ]; then",
		"    echo \"A letter.\"",
		"  elif [ $(echo $w | grep -c $l) -gt 0 ]; then",
		"    got=$got$l",
		"    echo \"Yes.\"",
		"  else",
		"    left=$((left - 1))",
		"    echo \"No.\"",
		"  fi",
		"done",
		"echo \"Out of guesses. It was $w.\"",
	}, "\n"),
}

CeroSecContent.SCRIPTS["adventure.sh"] = {
	-- Five rooms, and the only script here that takes no arguments at all:
	-- there is no wrong way to run a game, so the usage rule does not apply to
	-- it and the bench says so in those words. The recorded moves walk it to
	-- THE END, which is the only proof a text adventure can be given.
	mode = 755,
	args = {},
	input = { "n", "e", "n", "take", "s", "s" },
	text = table.concat({
		"#!/bin/sh",
		"# adventure.sh -- five rooms, a locked stair and one key.",
		"r=gate",
		"k=0",
		"over=0",
		"echo \"THE OLD WATERWORKS\"",
		"echo \"n s e w to walk, take, look, quit. Five rooms.\"",
		"while [ $over -eq 0 ]; do",
		"  if [ $r = gate ]; then",
		"    echo \"A chain gate, hanging open. The yard is north.\"",
		"  elif [ $r = yard ]; then",
		"    echo \"Drums and a flatbed with no wheels. A door east,\"",
		"    echo \"the gate back south.\"",
		"  elif [ $r = hall ]; then",
		"    echo \"A corridor smelling of chlorine. Office north,\"",
		"    echo \"the yard west, a stair down to the south.\"",
		"  elif [ $r = office ]; then",
		"    echo \"A desk under a fallen ceiling tile. Hall south.\"",
		"  else",
		"    echo \"The pump room. Two feet of water, and a grate\"",
		"    echo \"overhead with daylight through it. You climb out.\"",
		"    echo \"THE END.\"",
		"    over=1",
		"  fi",
		"  if [ $over -eq 0 ]; then",
		"    read -p \"> \" c",
		"    if [ \"$c\" = quit ]; then",
		"      echo \"You walk back out to the road.\"",
		"      over=1",
		"    elif [ \"$c\" = take ]; then",
		"      if [ $r = office ]; then",
		"        k=1",
		"        echo \"A brass key, taped under the drawer. Yours.\"",
		"      else",
		"        echo \"Nothing here worth carrying.\"",
		"      fi",
		"    elif [ \"$c\" = look ]; then",
		"      echo \"You look again. It is the same.\"",
		"    elif [ \"$c\" = n ]; then",
		"      if [ $r = gate ]; then r=yard",
		"      elif [ $r = hall ]; then r=office",
		"      elif [ $r = pump ]; then r=hall",
		"      else echo \"There is nothing north of here.\"",
		"      fi",
		"    elif [ \"$c\" = s ]; then",
		"      if [ $r = yard ]; then r=gate",
		"      elif [ $r = office ]; then r=hall",
		"      elif [ $r = hall ]; then",
		"        if [ $k -eq 1 ]; then r=pump",
		"        else echo \"The stair door is locked. A brass lock.\"",
		"        fi",
		"      else echo \"There is nothing south of here.\"",
		"      fi",
		"    elif [ \"$c\" = e ]; then",
		"      if [ $r = yard ]; then r=hall",
		"      else echo \"There is nothing east of here.\"",
		"      fi",
		"    elif [ \"$c\" = w ]; then",
		"      if [ $r = hall ]; then r=yard",
		"      else echo \"There is nothing west of here.\"",
		"      fi",
		"    else",
		"      echo \"I do not know how to $c.\"",
		"    fi",
		"  fi",
		"done",
	}, "\n"),
}

--
-- THE DISK CATALOGUE -- the other half of what the world-content work, part 2 writes.
--
--   DISKS[i] = {
--     id     = "UTILITIES",  what the entry is called in here and in the bench
--     label  = "UTILITIES",  what is written on the disk, CeroSecOS.labelOk
--     weight = 4,            out of 100; what is left over is a blank disk
--     late   = "NUMBERS.TXT" one file is a stub until the disk is first inserted
--     files  = { { name="lights.sh", script="lights.sh" },
--                { name="README.TXT", mode=644, text="..." } },
--   }
--
-- Five things to know:
--
--   * a file entry carries EITHER `script` (a name in CeroSecContent.SCRIPTS,
--     which brings its own mode) or `text` and `mode`. Never both. An entry marked
--     `dir` is a directory, and a `name` may then be two components with a slash
--     between them ("MAN", then "MAN/CU.TXT") -- two is all the depth a floppy
--     gets, and the entry that makes a directory has to come before the entries
--     inside it.
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
-- AND A SIXTH, which the world-content work, part 2 needed and which is the one piece of mechanics it
-- added: `late`.
--
-- A floppy is created in LOOT and loot has no location. The disk is in a drawer in
-- a town nobody has walked into yet; there is no square to ask, no premises, no
-- region and therefore no telephone exchange -- and a BBS list printed with the
-- numbers of somewhere else is a disk that lies to the player in the one way this
-- catalogue is not allowed to.
--
-- So one file of such an entry is a STUB when the disk is made, and it is filled
-- in the first time somebody puts the disk in a machine: the server knows which
-- square that machine is on, and therefore which exchange's book the numbers come
-- out of (CeroSecNet.fillLateDisk).
--
-- HOW "HAS IT BEEN FILLED YET" IS ANSWERED, and it is answered without a field of
-- its own. A disk owns three keys and only three (CeroSecOS.DISK_KEYS), and the
-- gate at the slot refuses a disk carrying a fourth -- which is what keeps a
-- payload out of the save file -- so there is nowhere on a disk to write a flag
-- and nothing that would survive being written there. The mark is the FILE: the
-- late file is filled only while it still holds, byte for byte, the stub the
-- catalogue shipped.
--
-- That is not a trick, it is the rule upgradeSystem already uses to take a retired
-- command out of /bin: a file that is exactly what was shipped is the system's to
-- replace, and anything else at that name is a survivor's own work and stays. So a
-- player who wrote his own notes over the stub keeps them, on every machine he ever
-- puts the disk in, and the disk never rewrites itself under him.
--
-- What it costs: a survivor who types the shipped stub onto a blank disk by hand,
-- labels it, and inserts it gets the listings printed. He has to reproduce a text
-- he could only have read off another copy of the same disk, which is a curiosity
-- and not a way in -- the numbers are the region's own telephone directory and the
-- phone book in his other pocket has all of them in it already.
--
-- The one entry that is neither loot nor a slot: the developer's diagnostics
-- disk, weight 0, handed out by the debug window and by nothing else. Named here
-- so that the bench's "every entry is either shipped or a named slot" walk can
-- say which one it is, and so the server can ask for it by something other than a
-- string typed twice (SCeroSecSystem's `givedisk`).
CeroSecContent.DIAG_DISK = "CEROSEC DIAGNOSTICS"

CeroSecContent.DISKS = {
	{
		id = "UTILITIES",
		label = "UTILITIES",
		weight = 4,
		files = {
			{ name = "lights.sh", script = "lights.sh" },
			{ name = "check.sh", script = "check.sh" },
			{ name = "README.TXT", mode = 644, text = table.concat({
				"UTILITIES DISK",
				"",
				"lights.sh   switch the lights you name off.",
				"            sh lights.sh light0 light1",
				"check.sh    say which of the doors you name is open.",
				"            sh check.sh door0 door1",
				"",
				"Copy them onto the machine before you run them:",
				"",
				"  cp /mnt/lights.sh ~/bin",
				"",
				"Ask the machine what it can reach with: ls /dev",
				"Neither of them names a device of its own, so they",
				"work on any building with the modules fitted.",
			}, "\n") },
		},
	},
	--
	-- THE FIVE the world-content work, part 2 wrote.
	--
	{
		id = "BBS LIST",
		label = "BBS LIST",
		weight = 3,
		-- THE ONE LATE ENTRY, and the sixth note over this table is the whole of
		-- why: the numbers on it are the numbers of the exchange the disk is first
		-- put into a machine in, because a disk in a drawer in a town nobody has
		-- walked into has no exchange to be printed from.
		late = "NUMBERS.TXT",
		files = {
			{ name = "README.TXT", mode = 644, text = table.concat({
				"BBS LIST",
				"",
				"NUMBERS.TXT  the boards, with their numbers.",
				"CALLS.TXT    the packet stations I have heard, by",
				"             callsign. Nothing on that list is a",
				"             thing you dial.",
				"",
				"Dial a board with cu and the seven digits:",
				"",
				"  cu 418-2201",
				"",
				"That one is mine and it is not yours. Use the ones",
				"in NUMBERS.TXT. What comes back is CONNECT 2400 if",
				"there is a machine on the end, and NO CARRIER after",
				"fifteen seconds if there is not.",
			}, "\n") },
			-- THE STUB. Short, and it reads as what it is: a side of a disk its
			-- owner had not written up. The fill replaces it byte for byte at the
			-- first insertion (CeroSecContent.fillLate), so a player only ever sees
			-- this on a disk used in a region with no listed premises in it at all
			-- -- and on such a disk it is the truth.
			{ name = "NUMBERS.TXT", mode = 644, text = table.concat({
				"BOARDS I CALL",
				"",
				"(nothing written on this side yet)",
			}, "\n") },
			{ name = "CALLS.TXT", mode = 644, text = table.concat({
				"PACKET STATIONS I HAVE HEARD",
				"",
				"  K4QDL   most nights, on 144.390",
				"  WB4NRT  the repeater crowd. Loud and never quiet.",
				"  N4FKX   once, very weak, asking for a relay",
				"  KD4AXR  a machine and not a man. It took a connect",
				"          and then said nothing at all.",
				"",
				"A callsign is not a number and there is no dialling",
				"it. You open the line to your own radio and raise",
				"the station from there:",
				"",
				"  cu -l /dev/radio0",
			}, "\n") },
		},
	},
	{
		id = "WARDIALER",
		label = "WARDIALER",
		weight = 2,
		files = {
			-- THE DECISION, said on the disk itself in the plainest words there
			-- are. See the WARDIALER paragraph in docs/CONTENT.md for the proof.
			{ name = "README.TXT", mode = 644, text = table.concat({
				"WARDIALER",
				"",
				"There is no wardialer on this disk and there cannot",
				"be one. cu hands the screen over to whatever answers",
				"and the script that called it ENDS there -- the line",
				"after a cu never runs -- and from cron or from a",
				"background job cu will not dial at all. So what is",
				"on here is the method and the book, not a program.",
				"",
				"RANGE.TXT  the numbers to turn, in what order, and",
				"           how to read what comes back.",
				"log.sh     write down what happened: the date, the",
				"           number, and one word.",
				"",
				"  cp /mnt/log.sh ~/bin",
				"  sh ~/bin/log.sh ~/dialled 418-2201 answered",
			}, "\n") },
			{ name = "RANGE.TXT", mode = 644, text = table.concat({
				"HOW TO WORK A RANGE",
				"",
				"The first three digits are the exchange and every",
				"telephone in one town shares them. So the only part",
				"worth turning is the last four.",
				"",
				"Start at 0100 and go up in hundreds. Anything that",
				"answers at all, write it down and come back to it",
				"when you have the whole hundred done.",
				"",
				"  cu 418-0100",
				"  cu 418-0200",
				"",
				"What comes back, and what it means:",
				"",
				"  CONNECT 2400  a machine, and you are now on it.",
				"  NO CARRIER    nothing answered. Fifteen seconds.",
				"  BUSY          somebody is on that line already.",
				"  NO DIALTONE   your own line is dead. Stop.",
				"",
				"Escape hangs up, the same key that stops everything",
				"else on this machine.",
			}, "\n") },
			{ name = "log.sh", script = "log.sh" },
		},
	},
	{
		id = "GAMES",
		label = "GAMES",
		weight = 3,
		files = {
			{ name = "README.TXT", mode = 644, text = table.concat({
				"GAMES",
				"",
				"  sh /mnt/guess.sh 100",
				"  sh /mnt/hangman.sh /mnt/WORDS.TXT",
				"  sh /mnt/adventure.sh",
				"",
				"guess.sh      it picks one, you find it. Eight goes.",
				"hangman.sh    a word out of WORDS.TXT, a letter at a",
				"              time. Six wrong and it is over.",
				"adventure.sh  five rooms and one locked door.",
				"",
				"All three are short enough to read, which is most of",
				"what they are for.",
			}, "\n") },
			{ name = "guess.sh", script = "guess.sh" },
			{ name = "hangman.sh", script = "hangman.sh" },
			{ name = "adventure.sh", script = "adventure.sh" },
			{ name = "WORDS.TXT", mode = 644, text = CeroSecContent.DATA["WORDS.TXT"] },
		},
	},
	{
		id = "BACKUP",
		label = "BACKUP",
		weight = 3,
		files = {
			{ name = "README.TXT", mode = 644, text = table.concat({
				"BACKUP",
				"",
				"Everything out of my home directory, 8 July.",
				"",
				"DIARY.TXT    what I have been writing since the 4th.",
				"LETTERS.TXT  the two I wrote and did not send.",
				"FAMILY.TXT   everybody's numbers.",
				"",
				"If you have found this and you can still telephone",
				"anybody, ring them and tell them where you got it.",
			}, "\n") },
			{ name = "DIARY.TXT", mode = 644, text = table.concat({
				"4 July",
				"The plant shut at noon and nobody said why. Half of",
				"them went straight to the bar from the gate. I came",
				"home and put the radio on and there was nothing on",
				"the radio either.",
				"",
				"5 July",
				"Drove in for bread. The road at the trestle is shut",
				"and there is a soldier standing on it, a young one,",
				"who would not look at me while he turned me round.",
				"",
				"6 July",
				"Earl came by. He says the hospital is not taking",
				"anybody at all and that the line on the map moved",
				"north in the night. We put the shutters up. It felt",
				"stupid doing it in the daylight.",
				"",
				"8 July",
				"The telephone has been ringing all morning and it is",
				"not ringing here. It is ringing next door and nobody",
				"has picked it up. I am putting this on a disk",
				"because the machine is the only thing in this house",
				"still doing what it did last week.",
			}, "\n") },
			{ name = "LETTERS.TXT", mode = 644, text = table.concat({
				"To Mother, not sent:",
				"",
				"We are all right and the house is all right. Do not",
				"try to drive down. If the road is open they will",
				"tell you it is shut, and if it is shut they will",
				"tell you nothing at all.",
				"",
				"To the county, not sent:",
				"",
				"I have telephoned four times about the water and",
				"been told four times that somebody will come out.",
				"Nobody has come out. I am writing it down so that",
				"when this is over there is a piece of paper with a",
				"date on it.",
			}, "\n") },
			{ name = "FAMILY.TXT", mode = 644, text = table.concat({
				"EVERYBODY'S NUMBERS",
				"",
				"  Mother          418-0233",
				"  Earl and Wanda  418-1147",
				"  the plant       418-4400",
				"  the doctor      418-0180",
				"  next door       418-1162",
				"",
				"The first three are this exchange. If you are",
				"reading this somewhere else in the county then they",
				"are somebody else's numbers now, and I am sorry.",
			}, "\n") },
		},
	},
	{
		id = "CEROSEC OS 1.0 DIST",
		label = "CEROSEC OS 1.0 DIST",
		weight = 2,
		files = {
			{ name = "README.TXT", mode = 644, text = table.concat({
				"CEROSEC OS 1.0 -- DISTRIBUTION MEDIA",
				"CeroSec Systems, Louisville, Kentucky",
				"",
				"INSTALL.TXT  how the system is put back onto a",
				"             machine. Read it first.",
				"MAN          six pages out of the manual: the six",
				"             commands people telephone us about.",
				"lights.sh    switch the lights you name off.",
				"locks.sh     lock or unlock a row of locks.",
				"sweep.sh     list every file under a directory.",
				"",
				"The three programs are the beginning of the local",
				"library. The whole of it stands in /usr/local/src on",
				"the bench machine of any of our service departments.",
			}, "\n") },
			{ name = "INSTALL.TXT", mode = 644, text = table.concat({
				"INSTALLING FROM THIS DISK",
				"",
				"You do not install from this disk by running",
				"anything on it. There is nothing on here that can",
				"write to a system disk, and that is deliberate: a",
				"floppy that could rewrite the system is a floppy",
				"that can destroy a working machine by being left in",
				"the drive.",
				"",
				"What installs the system is the machine itself. Hold",
				"the power switch until the firmware comes up and",
				"choose repair. It writes a fresh system onto the",
				"disk out of its own read-only copy, which is the",
				"same version as this media -- and it KEEPS /home.",
				"Every account survives. Every password survives.",
				"What goes back to how we shipped it is /bin, /etc",
				"and the rest of the system.",
				"",
				"So the answer to a machine that will not boot has",
				"always been: repair it, and then put your own files",
				"back from a disk like this one.",
			}, "\n") },
			{ name = "MAN", dir = true, mode = 755 },
			{ name = "MAN/MOUNT.TXT", mode = 644, text = table.concat({
				"MOUNT(8)",
				"",
				"  mount [<device> <dir>]",
				"",
				"Reach the filesystem on a disk. This machine has one",
				"place to put one and it is /mnt.",
				"",
				"  mount /dev/fd0 /mnt",
				"",
				"With nothing after it, mount lists what is mounted.",
				"Say umount /mnt when you are done, and cd out of it",
				"first or it will tell you it is busy.",
			}, "\n") },
			{ name = "MAN/NEWFS.TXT", mode = 644, text = table.concat({
				"NEWFS(8)",
				"",
				"  newfs <device>",
				"",
				"Put a filesystem on a disk. A disk out of the box",
				"has none and nothing can be written to it until it",
				"has one.",
				"",
				"  newfs /dev/fd0",
				"",
				"It empties the disk. That is what formatting a disk",
				"has always meant and we are not going to ask twice.",
			}, "\n") },
			{ name = "MAN/CU.TXT", mode = 644, text = table.concat({
				"CU(1)",
				"",
				"  cu telno",
				"  cu -l line",
				"",
				"Call another machine on the telephone, or open the",
				"line to whatever is wired to the machine.",
				"",
				"  cu 418-2201",
				"  cu -l /dev/radio0",
				"",
				"The screen belongs to the far end until you hang up",
				"with Escape. Nothing can drive it for you: a script",
				"that calls cu ends where the cu is.",
			}, "\n") },
			{ name = "MAN/CRONTAB.TXT", mode = 644, text = table.concat({
				"CRONTAB(1)",
				"",
				"  crontab -e|-l|-r",
				"",
				"The machine doing something with nobody standing at",
				"it. Five fields and a command: minute, hour, day of",
				"the month, month, day of the week.",
				"",
				"  0 22 * * * echo off > /dev/light0",
				"",
				"What a line prints goes in your mail and never on",
				"the screen, there being nobody at the screen. Read",
				"it with mail.",
			}, "\n") },
			{ name = "MAN/DEV.TXT", mode = 644, text = table.concat({
				"DEV(8)",
				"",
				"  dev [kind|id [value|toggle]|find <id>]",
				"",
				"The building, as the machine sees it. Everything dev",
				"does you can do with two commands you already know:",
				"",
				"  cat /dev/light0",
				"  echo off > /dev/light0",
				"",
				"A fixture with no module wired to it is not a device",
				"and will not be in the list. That is an electrician.",
			}, "\n") },
			{ name = "MAN/MKPASSWD.TXT", mode = 644, text = table.concat({
				"MKPASSWD(1)",
				"",
				"  mkpasswd <text> [salt]",
				"",
				"Hash a string the way a password is hashed. Ours,",
				"and no other Unix has it: the library call is what",
				"everybody else was given.",
				"",
				"It does not set a password and it does not read one.",
				"It is for seeing that two strings hash the same, and",
				"it was called hash until we renamed it.",
			}, "\n") },
			{ name = "lights.sh", script = "lights.sh" },
			{ name = "locks.sh", script = "locks.sh" },
			{ name = "sweep.sh", script = "sweep.sh" },
		},
	},
	--
	-- THE DEVELOPER'S DISK, and it is the only entry in here that is not loot.
	--
	-- Weight 0, so CeroSecContent.diskForRoll can never land on it and no drawer
	-- in the county has one: the way to it is the debug window's own "Give
	-- diagnostics disk", behind CeroSec.debugAllowed like everything else on that
	-- glass (Commands.debugact "givedisk" in SCeroSecSystem.lua).
	--
	-- WHAT IT IS FOR. Every bench in tests/ runs on lua5.1 on a developer's box.
	-- The game runs Kahlua, and twice in one day that difference shipped a bug
	-- through a green suite. tests/kahlua-probe.lua closed the half of that which
	-- is pure functions; this disk closes the other half, which is the SHELL: the
	-- commands, the pipes, the redirects, the arithmetic reader and the
	-- filesystem, run by the engine, in a save, on the VM the game has.
	--
	-- ONE SCRIPT AND NOT FOUR. A floppy is 4096 bytes and 32 nodes, and the
	-- twenty-six checks fit in one file with about three hundred bytes to spare --
	-- so there is no t1.sh/t2.sh split, which is just as well: a script is a job
	-- of its own and its variables go with it, so parts would have had to pass
	-- their tally through a file. The pass count is a variable and the failures are
	-- lines in a scratch file, which is deliberately two places: a miscount cannot
	-- make itself agree.
	--
	-- The bench weighs this entry like every other (tests/content_test.lua section
	-- 7c), RUNS it under the engine and holds it to FAIL 0 -- and holds the hash on
	-- the last check to CeroSecOS.hashPassword's own answer, so the number on the
	-- floppy cannot drift off the engine it is there to check.
	--
	{
		id = CeroSecContent.DIAG_DISK,
		label = "CEROSEC DIAGNOSTICS",
		-- Never in loot. The gate is diskForRoll's `weight > 0`, and the bench
		-- walks all hundred rolls to say so out loud.
		weight = 0,
		files = {
			{ name = "selftest.sh", mode = 755, text = table.concat({
				"#!/bin/sh",
				"# CEROSEC DIAGNOSTICS -- the machine testing itself.",
				"# Twenty-six checks. See README.TXT.",
				"F=~/st.f",
				"p=0",
				"echo -n \"\" >$F",
				"n=echo; e=hi; g=$(echo hi)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=pipe; e=HI; g=$(echo hi | tr a-z A-Z)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=cut; e=b; g=$(echo a:b:c | cut -d : -f 2)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=sort; e=a; g=$(printf \"c\\na\\nb\\n\" | sort | head -n 1)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=sort-u; e=2; g=$(printf \"b\\na\\nb\\n\" | sort -u | wc -l)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=wc; e=3; g=$(printf \"a\\nb\\nc\\n\" | wc -l)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"printf \"a\\nba\\nc\\n\" >~/st.t",
				"n=grep; e=2; g=$(grep -c a ~/st.t)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=more; e=3; g=$(cat ~/st.t | more | wc -l)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=tee; e=\"z z\"; g=\"$(echo z | tee ~/st.u) $(cat ~/st.u)\"",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=arith; e=22; g=$(( 3 * 7 + 1 ))",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=modulo; e=\"2 65535\"",
				"g=\"$(( 2147483648 % 7 )) $(( 4294967295 % 65536 ))\"",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"s=0",
				"for i in 1 2 3; do s=$(( s + i )); done",
				"n=for; e=6; g=$s",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"c=0",
				"while [ $c -lt 3 ]; do c=$(( c + 1 )); done",
				"n=while; e=3; g=$c",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=read; e=abc",
				"g=$(printf \"a\\nb\\nc\\n\" | while read v; do echo -n $v; done)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"mkdir ~/st.d",
				"touch ~/st.d/f",
				"chmod 700 ~/st.d",
				"chmod 600 ~/st.u",
				"n=mkdir; e=y; g=$([ -d ~/st.d -a -f ~/st.d/f ] && echo y)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=perms; e=rwx",
				"g=$([ -r ~/st.d -a -w ~/st.d -a -x ~/st.d ] && echo rwx)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=chmod; e=-rw-------; g=$(ls -l ~/st.u | cut -c 1-10)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"rm ~/st.d/f",
				"n=rm; e=gone; g=$([ -e ~/st.d/f ] || echo gone)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=paths; e=\"/etc/passwd /bin/crontab\"",
				"g=\"$(find /etc -name passwd) $(which crontab)\"",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=date; e=$(date +%Y); g=$(date \"+%Y-%m-%d\" | cut -d - -f 1)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=drive; e=\"2 1\"",
				"g=\"$(df | grep -c fd0) $(mount | grep -c DIAGNOSTICS)\"",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=dev; e=\"1 1\"",
				"g=\"$(ls -l /dev | grep -c null) $(dev | grep -c fd0)\"",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=who; e=\"$(hostname) uid=$(whoami)\"",
				"g=\"$(cat /etc/hostname) $(id | cut -d \" \" -f 1)\"",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=uptime; e=1; g=$(uptime | grep -c load)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"n=mkpasswd",
				"e='$cs1$abcdef$74a662fe0a5af94dd93513930da000aa'",
				"g=$(mkpasswd secret abcdef)",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"sleep 1",
				"n=sleep; e=0; g=$?",
				"[ \"$g\" = \"$e\" ] && p=$((p+1)) || echo \"$n: $e vs $g\" >>$F",
				"f=$(cat $F | wc -l)",
				"s=\"PASS $p FAIL $f\"",
				"cat $F",
				"echo \"$s\"",
				"echo \"CEROSEC SELFTEST $s\" >/mnt/RESULTS.TXT",
				"cat $F >>/mnt/RESULTS.TXT",
				"rm $F",
				"rm ~/st.t",
				"rm ~/st.u",
				"rm -r ~/st.d",
				"if [ $f -gt 0 ]; then exit 1; fi",
			}, "\n") },
			-- Shipped as a STUB at mode 666, and the mode is the whole point: /mnt is
			-- root's, so an ordinary account cannot make a file on a floppy -- but it
			-- may write one that is already there and says anybody may. Without this
			-- entry the last four lines of the script would be `permission denied` on
			-- every machine a survivor is not root on.
			{ name = "RESULTS.TXT", mode = 666, text = "(nothing run yet)" },
			{ name = "README.TXT", mode = 644, text = table.concat({
				"CEROSEC DIAGNOSTICS",
				"",
				"The machine testing itself.",
				"",
				"  mount /dev/fd0 /mnt",
				"  sh /mnt/selftest.sh",
				"",
				"A line for every check that failed, then PASS n FAIL m. The",
				"verdict goes into RESULTS.TXT beside it, with the failures",
				"under it while there is room on the disk for them. Its",
				"scratch files go in your home and are taken away again.",
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

-- The ids the world-content work, part 2 fills. Named here rather than left to be remembered, and the
-- bench walks the list: an id in it that has become a real entry is fine, an id
-- in it that is still missing is fine, and an entry whose id is in NEITHER list
-- is a catalogue nobody wrote down.
CeroSecContent.DISK_SLOTS = {
	"BBS LIST", "WARDIALER", "GAMES", "BACKUP", "CEROSEC OS 1.0 DIST",
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

-- And by the STICKER, which is the only thing a disk in somebody's pocket carries
-- of the entry it came from. Written as its own walk rather than as diskById of the
-- label: the two are the same string for every entry there is, and a lookup that
-- leaned on that would be a lookup that broke the day an entry is labelled in words
-- and identified by a word.
function CeroSecContent.diskByLabel(label)
	if type(label) ~= "string" then return nil end
	for i = 1, #CeroSecContent.DISKS do
		if CeroSecContent.DISKS[i].label == label then return CeroSecContent.DISKS[i] end
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
		-- A name may be one component or two -- "MAN" and "MAN/CU.TXT" -- and two is
		-- the whole of the depth a floppy gets. A distribution disk really did have a
		-- MAN directory on it; a tree deeper than that on a 4096-byte disk read at
		-- sixty columns is a tree nobody would walk.
		local node = nil
		if file.dir then
			node = CeroSecOS.newDir("root", mode or 755)
		elseif type(text) == "string" then
			node = CeroSecOS.newFile("root", mode or 644, text)
		end
		if node ~= nil and CeroSecContent.diskNameOk(file.name) then
			local path = CeroSecOS.MNT_PATH .. "/" .. file.name
			-- nil on a full disk, a name already there, a byte the machine will not
			-- carry, a directory above it that is not there -- an entry naming one
			-- must come after the entry that makes it, which is the order rule this
			-- table already has. Trimmed, never argued with: see the head of this
			-- file.
			if CeroSecOS.createNode(state, session, path, node, now) ~= nil then
				written = written + 1
			end
		end
	end
	CeroSecOS.unmountAll(state)
	return disk, written
end

-- A name a disk entry may carry: one component, or two with a slash between them.
-- Every component is held to the machine's own rule, so a name the filesystem
-- would refuse is refused here and the entry is simply not written.
function CeroSecContent.diskNameOk(name)
	if type(name) ~= "string" or name == "" then return false end
	local at = string.find(name, "/", 1, true)
	if at == nil then return CeroSecOS.isValidFileName(name) end
	local head = string.sub(name, 1, at - 1)
	local tail = string.sub(name, at + 1)
	if not CeroSecOS.isValidFileName(head) then return false end
	return CeroSecOS.isValidFileName(tail)
end

--
-- THE LATE FILE: a disk whose story needs a place, and a place loot has not got
--
-- See the sixth note over CeroSecContent.DISKS for why this exists at all.
--

-- How many listings go on a late BBS list, and why not more: a floppy is 4096
-- bytes and the other two files on that disk have to fit beside these. Eight is a
-- page of a hand-kept list, which is what somebody who called around actually had.
CeroSecContent.BBS_MAX = 8

-- The names somebody wrote beside the numbers. A board was named by whoever ran it
-- out of his spare room, and these are named the way those were: a place, a shift,
-- or a joke about the telephone bill.
--
-- They are INVENTED and the numbers are not, which is the whole shape of the disk:
-- the four digits ring a real premises of the player's own region, because they
-- come out of the county's own directory, and the name beside them is what the
-- disk's owner wrote on his list.
CeroSecContent.BBS_NAMES = {
	"The Back Porch", "Night Shift", "Knox Exchange", "The Tool Shed",
	"Coal Town", "Static Line", "The Waiting Room", "Bluegrass Board",
	"Dead Letter Office", "The Annex", "Third Shift", "Riverbend",
}

-- Which file of an entry is the late one, and the text it shipped with. Both come
-- off the entry itself so there is ONE copy of the stub: the sentinel the fill
-- compares against IS the catalogue's own text, and a change that edited the stub
-- and forgot the sentinel is a change that cannot happen.
--
-- name, stub -- or nil for an entry with no late file.
function CeroSecContent.lateFile(entry)
	if type(entry) ~= "table" then return nil end
	if type(entry.late) ~= "string" then return nil end
	if type(entry.files) ~= "table" then return nil end
	for i = 1, #entry.files do
		local file = entry.files[i]
		if file.name == entry.late and type(file.text) == "string" then
			return file.name, file.text
		end
	end
	return nil
end

-- Is this disk a copy of a late entry that has not been filled in yet?
--
-- Three questions, and all three have to answer yes: the sticker names a late
-- entry, the file is on the disk, and it still holds the stub. entry, name -- or
-- nil, which is every other disk in the county and is the answer taken on every
-- single insertion, so it is three table reads and a string compare.
function CeroSecContent.lateEntryFor(disk)
	if type(disk) ~= "table" or type(disk.label) ~= "string" then return nil end
	local entry = CeroSecContent.diskByLabel(disk.label)
	if entry == nil then return nil end
	local name, stub = CeroSecContent.lateFile(entry)
	if name == nil then return nil end
	local root = disk.fs
	if type(root) ~= "table" or type(root.children) ~= "table" then return nil end
	local node = root.children[name]
	if type(node) ~= "table" or node.type ~= "file" then return nil end
	if node.data ~= stub then return nil end
	return entry, name
end

-- The list itself: the exchange, then a name and a number a line at a time.
--
-- PURE, and that is what keeps this file a catalogue: what premises are in the
-- region and what they are called is the server's question (CeroSecNet.directory),
-- and turning a list of numbers into a page is this one's.
--
-- SORTED HERE, and by the number, which does two things at once. It is the order a
-- hand list of numbers to turn is kept in -- lowest first, the way RANGE.TXT on the
-- wardialer disk tells a survivor to work a range -- and it is what keeps the order
-- the map handed its zones over from reaching the page: the same county gives the
-- same list, byte for byte, however it was enumerated. CeroSecPhonebook.sorted
-- sorts for the same reason one level up.
--
-- Which name goes with which number is decided by THE NUMBER and never by its
-- position, so a board keeps its name whatever else is on the list; two numbers
-- landing on one name take the next one along, which the sort makes a decision and
-- not an accident. Nothing here is hashed against the save's secret -- a printed
-- disk is not a password.
function CeroSecContent.bbsText(exchange, numbers)
	if type(numbers) ~= "table" then return nil end
	local names = CeroSecContent.BBS_NAMES
	local list = {}
	for i = 1, #numbers do
		if type(numbers[i]) == "string" then list[#list + 1] = numbers[i] end
	end
	if #list == 0 then return nil end
	table.sort(list)
	local out = {
		"BOARDS I CALL -- exchange " .. tostring(exchange),
		"",
	}
	local put, taken = 0, {}
	for i = 1, #list do
		local number = list[i]
		if put < CeroSecContent.BBS_MAX then
			local digits = tonumber(string.match(number, "(%d+)$") or "0") or 0
			local at = math.floor(math.fmod(digits, #names)) + 1
			local hops = 0
			while taken[at] and hops < #names do
				at = at + 1
				if at > #names then at = 1 end
				hops = hops + 1
			end
			taken[at] = true
			local name = names[at]
			-- Name, dot leaders, number -- a hand-kept list laid out the way the
			-- telephone book it was copied out of lays one out, and inside the sixty
			-- columns the screen has.
			local room = 52 - #number
			local dots = string.rep(".", room - #name)
			out[#out + 1] = "  " .. name .. " " .. dots .. " " .. number
			put = put + 1
		end
	end
	out[#out + 1] = ""
	out[#out + 1] = "Dial one with: cu " .. tostring(list[1])
	out[#out + 1] = "Most of them stopped answering in July."
	return table.concat(out, "\n"), put
end

-- Fill the late file in, once. `numbers` is the region's own numbers, in the order
-- the book prints them.
--
-- Written through the ENGINE's own write path onto the disk in a throwaway drive,
-- exactly as diskData writes the disk in the first place, so the floppy's 4096
-- bytes decide how much of the list fits and a list that would not fit leaves the
-- stub exactly where it was. Answers true when the file really changed.
function CeroSecContent.fillLate(disk, exchange, numbers, now)
	local entry, name = CeroSecContent.lateEntryFor(disk)
	if entry == nil then return false end
	local text = CeroSecContent.bbsText(exchange, numbers)
	if text == nil then return false end
	local state = CeroSecOS.newState(nil)
	state.floppy = disk
	if CeroSecOS.addMount(state, CeroSecOS.FD_NAME, CeroSecOS.MNT_PATH) == nil then
		return false
	end
	local session = CeroSecOS.rootSession()
	local done = CeroSecOS.writeFile(state, session,
		CeroSecOS.MNT_PATH .. "/" .. name, text, false, now)
	CeroSecOS.unmountAll(state)
	return done ~= nil
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
-- WHAT IS ROLLED, AND WHY IT IS NOT A HASH. The design for this change said to hash
-- the item's id. There is no id to hash: InventoryItem.id is only ever written by
-- InventoryItem.load and by createCloneItem -- the only two putfields on the
-- field in the whole class -- so a freshly instanced item is id 0 and every
-- floppy in the county would hash the same. So the roll is the engine's own RNG, ZombRand,
-- exactly as vanilla rolls loot -- and the determinism the design wanted is kept
-- by WHERE THE ANSWER LIVES: the roll happens once, at creation, and what is
-- saved is its RESULT in the item's own modData. A disk's contents never change
-- afterwards, through any number of reloads, because nothing rolls again.
--
-- This is a DEVIATION from that work's design and it is declared in
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

-- And its password. The login goes INTO the key as well as the slot, so a change
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
-- own square, so two computers in one office are two people's computers. It is
-- what says WHOSE desk this one is (CeroSecContent.ownerSlot), what is in his
-- history, who logged in on it and when, and which scripts are in his bin.
function CeroSecContent.machineKey(b1, b2, x, y, z)
	return CeroSecContent.key("m", b1, b2, x, y, z)
end

-- And the premises' own key, which the world-content work, part 3 needed and the two above only implied:
-- rootKey and accountKey are both built out of the premises' two bytes, and now
-- so is WHICH TELLING of a story this company's files carry.
--
-- It is the premises' and not the machine's on purpose, and it is the same
-- decision the people were: a readme is the COMPANY's readme, so the two machines
-- of one office carry the same one, exactly as they carry the same staff. What
-- differs between two desks of one office is whose desk it is -- the owner, his
-- history, his mail, the login records -- and every one of those is keyed on the
-- machine.
function CeroSecContent.premisesKey(b1, b2)
	return CeroSecContent.key("p", b1, b2)
end

-- How many tellings of one file the catalogue carries. Three, and it is a number
-- rather than "however many are in the table" because the bench holds every entry
-- to having exactly this many: a file somebody wrote two variants of is a file two
-- premises in three share, and the whole point of this is that they do not.
CeroSecContent.VARIANTS = 3

-- Which telling this premises got of the file called `name`. The PREMISES and the
-- file's own name and nothing else, so:
--
--   * two machines of one office read the same readme, because it is one office's
--     readme;
--   * two offices read different ones, which is what a county of offices is;
--   * two files of one office are not forced onto one number, so an office is not
--     "the office that got telling two" all the way down.
--
-- Never nil: a secret it cannot hash falls back on the first telling, which is a
-- file that is there rather than a file that is not.
function CeroSecContent.variantOf(secret, b1, b2, name)
	local n = CeroSecContent.number(secret,
		CeroSecContent.key(CeroSecContent.premisesKey(b1, b2), "v", name),
		CeroSecContent.VARIANTS)
	if n == nil then return 1 end
	return n
end

-- WHOSE MACHINE THIS ONE IS, as a slot number of profile.accounts.
--
-- The complaint this answers, in the words it was made in: several computers in
-- one building held the same things. They did, because every account's files were
-- written onto every machine -- so an office with three people in it was three
-- desks with the same three homes on them, which is not an office, it is one
-- machine copied three times.
--
-- So one machine is one person's desk. The owner's home is the one that is
-- populated; the others exist, with their passwords, and their homes hold their
-- own dot-files and nothing else. Which is what walking into an office is: the
-- accounts are the company's, the files on this keyboard are the man who sat here.
--
-- Keyed on the MACHINE, which is the whole point of it, and never on the premises:
-- the second desk in the room has to be somebody else's for this to have been
-- worth doing. A premises with one account has that account everywhere.
function CeroSecContent.ownerSlot(secret, mkey, profile)
	if type(profile) ~= "table" or type(profile.accounts) ~= "table" then return nil end
	local n = #profile.accounts
	if n == 0 then return nil end
	if n == 1 then return 1 end
	local slot = CeroSecContent.number(secret, CeroSecContent.key(mkey, "owner"), n)
	if slot == nil then return 1 end
	return slot
end

--
-- The names in the text
--
-- A file of a profile is written once and read in every office in the county, so
-- the people in it are placeholders and the premises' own staff are put in at fill
-- time. {owner} is whoever sat at THIS machine, {staff1}..{staff3} are the
-- premises' accounts by slot -- the same three people on every machine in the
-- building -- and {host} is the machine's own name.
--
-- There is no {town}. A town name would have to be derived from the telephone
-- exchange's region, and nothing in the county knows one: the exchange is a hash
-- of a map coordinate and the map's own region names are not data this mod has.
-- Inventing one would put a town in Knox County that is not in Knox County, which
-- is the one kind of lie this catalogue is not allowed to tell -- so the texts are
-- written without a town in them. (Muldraugh and West Point are named in one file
-- because those are real places on the real map and are named as landmarks, not
-- as this premises' own town.)
CeroSecContent.PLACEHOLDERS = { "owner", "staff1", "staff2", "staff3", "host" }

-- What goes in when a placeholder has nobody behind it -- a slot whose login
-- collided, a profile with fewer people than a text names. A word and never the
-- braces: a survivor reading "ask {staff3} about it" is reading a bug, and a
-- survivor reading "ask somebody about it" is reading a shrug. The bench asserts
-- no braces survive in any file of any profile in any telling.
CeroSecContent.NO_NAME = "somebody"

function CeroSecContent.fillNames(text, names)
	if type(text) ~= "string" then return nil end
	local list = CeroSecContent.PLACEHOLDERS
	local out = text
	for i = 1, #list do
		local value = nil
		if type(names) == "table" then value = names[list[i]] end
		if type(value) ~= "string" or value == "" then value = CeroSecContent.NO_NAME end
		-- Braces are not pattern characters and a login is [a-z0-9], so neither
		-- side of this carries a "%" and there is nothing to escape.
		out = string.gsub(out, "{" .. list[i] .. "}", value)
	end
	return out
end

-- The text of one catalogue entry, in this premises' telling, with its people in
-- it. The ONE place a text is composed, so a file of a profile and a file of a
-- machine-wide `files` entry cannot end up with two different rules.
--
-- An entry carries `text` or `texts`, never both:
--
--   text    one telling. A DATA file and little else: CeroSecContent.DATA's
--           tables are the very files the scripts are proved against, and a table
--           that came out different on every machine would be a bench proving one
--           of three.
--   texts   three tellings, chosen by the premises. Every prose file is one.
--   extra   three tails, appended under `text`. It is how a data table varies
--           without moving: the six rows the bench adds up are still the six rows
--           the bench adds up, and the rows under them are this premises' own.
--
-- ONE NUMBER PER FILE, spent on both: the telling that picks the prose picks the
-- tail, because a premises has one telling of one file and not two.
function CeroSecContent.textFor(entry, secret, b1, b2, name, names)
	if type(entry) ~= "table" then return nil end
	local pick = CeroSecContent.variantOf(secret, b1, b2, name)
	local text = entry.text
	if type(entry.texts) == "table" and #entry.texts > 0 then
		local v = pick
		if v > #entry.texts then v = #entry.texts end
		text = entry.texts[v]
	end
	if type(text) ~= "string" then return nil end
	if type(entry.extra) == "table" and #entry.extra > 0 then
		local v = pick
		if v > #entry.extra then v = #entry.extra end
		local tail = entry.extra[v]
		if type(tail) == "table" and #tail > 0 then
			text = text .. "\n" .. table.concat(tail, "\n")
		elseif type(tail) == "string" and tail ~= "" then
			text = text .. "\n" .. tail
		end
	end
	return CeroSecContent.fillNames(text, names)
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

-- The same, plus every parent above it. createNode makes ONE node and refuses a
-- path whose parent is not there -- which is right, and is why /usr/local/src
-- needed three calls and a caller that remembered to make them in order. The
-- walk is bounded by CeroSecOS.MAX_DEPTH, and a parent that could not be made
-- stops it: the deeper directory would be refused anyway and the refusal is the
-- trimming rule doing its job.
local function placeDirTree(state, session, path, owner, mode, now)
	if type(path) ~= "string" or string.sub(path, 1, 1) ~= "/" then return false end
	local at, made = "", 0
	for part in string.gmatch(path, "[^/]+") do
		made = made + 1
		if made > CeroSecOS.MAX_DEPTH then return false end
		at = at .. "/" .. part
		if not placeDir(state, session, at, owner, mode, now) then return false end
	end
	return made > 0
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
--
-- Called for the OWNER's slot and for no other (see CeroSecContent.ownerSlot):
-- the other people on the machine have accounts and no files, which is what an
-- office is.
local function placeHomeFiles(state, session, account, login, secret, b1, b2, names, now)
	if type(account.files) ~= "table" then return end
	local home = "/home/" .. login
	for i = 1, #account.files do
		local file = account.files[i]
		if type(file.path) == "string" and string.find(file.path, "/") == nil then
			place(state, session, home .. "/" .. file.path, login, file.mode or 644,
				CeroSecContent.textFor(file, secret, b1, b2, file.path, names), now)
		end
	end
end

-- The scripts one profile puts in an account's ~/bin, each behind its own roll.
-- ~/bin and not /bin: /bin is the SYSTEM's and upgradeSystem tops it up, so a
-- script of ours in there would be a script the next version argues about. A
-- survivor's own ~/bin is already on his path (see the manual's chapter on where
-- commands come from).
-- An entry naming `to` goes into that directory instead, owned by root: it is not
-- one man's copy of a tool but a copy the machine keeps -- the vendor's own
-- /usr/local/src, which is where a 1993 machine's local software really lived.
local function placeScripts(state, session, profile, secret, mkey, login, now)
	if type(profile.bin) ~= "table" then return end
	local made = {}
	for i = 1, #profile.bin do
		local entry = profile.bin[i]
		local script = CeroSecContent.SCRIPTS[entry.script]
		local dir, owner = nil, nil
		if type(entry.to) == "string" and string.sub(entry.to, 1, 1) == "/" then
			dir, owner = entry.to, "root"
		elseif type(login) == "string" then
			dir, owner = "/home/" .. login .. "/bin", login
		end
		-- An entry with no `to` on a machine with no ordinary account has nowhere to
		-- go, and /home/root/bin is not a place: the profile that has no people on it
		-- names `to` on every entry, and this is what says so out loud.
		if script ~= nil and dir ~= nil
				and CeroSecContent.chance(secret,
					CeroSecContent.key(mkey, "bin", entry.script), entry.chance or 100) then
			if made[dir] == nil then
				made[dir] = placeDirTree(state, session, dir, owner, 755, now)
			end
			if made[dir] then
				place(state, session, dir .. "/" .. entry.script, owner, script.mode,
					script.text, now)
			end
		end
	end
end

-- Who a `to` field means, and the one place it is read: a slot number is the
-- premises' account in that slot, the word "owner" is whoever sat at THIS machine,
-- and anything else is a literal login ("root", "support").
--
-- "owner" is the world-content work, part 3's and it is not a convenience. A crontab line saying
-- $HOME/bin/total.sh runs in the home of the account the crontab belongs to, and
-- the scripts are the OWNER's now -- so a crontab pinned to slot 1 on a machine
-- whose desk is slot 2's is a line that mails "not found" once a night for ever.
-- Written as one function because cron and mail both ask it and a second copy is a
-- second answer waiting to happen.
local function whoFor(to, logins, owner)
	if type(to) == "number" then return logins[to] end
	if to == "owner" then return owner end
	if type(to) == "string" then return to end
	return nil
end

-- /var/spool/cron/<login>: what the machine was doing while nobody stood at it.
--
-- Root's and 600 in a directory that is root's and 700, which is exactly where
-- crontab(1) puts one and the whole of why one account cannot write a line that
-- runs as another. A survivor who wants to read it says `sudo crontab -l -u` --
-- there is no such flag, so he says `sudo cat` -- and one who owns the account
-- says `crontab -l`, which is the everyday way in.
-- One crontab, held to the machine's own crontab(1) first. Quiet on a refusal,
-- like every other write here.
local function placeOneCron(state, session, to, lines, now)
	if type(to) ~= "string" or CeroSecOS.getUser(state, to) == nil then return end
	if type(lines) ~= "table" or #lines == 0 then return end
	local text = table.concat(lines, "\n")
	-- Held to the machine's own crontab(1) HERE, by the one function that
	-- writes one: a file that will not parse is a file the survivor's own
	-- `crontab -l` prints and `cron` silently does nothing with, and the
	-- catalogue must not be able to ship one. The bench asserts it too, of
	-- every line of every profile; this is the belt, so a profile written
	-- after the bench was last read cannot get one past.
	if CeroSecOS.checkCrontab(CeroSecOS.cronPath(to), text) == nil then
		place(state, session, CeroSecOS.cronPath(to), "root",
			CeroSecOS.CRONTAB_MODE, text, now)
	end
end

-- The crontabs, and there are two kinds of them since the world-content work, part 3.
--
-- AN ACCOUNT'S OWN (`cron` inside an account entry) is written only when that
-- account is the OWNER of this machine, because a crontab is a list of things that
-- run in that account's home and with that account's bin on the path. The
-- bookkeeper's nightly total reads HIS ledger out of HIS home and calls the copy
-- of total.sh in HIS bin, so on the desk next to his -- another man, another home,
-- no ledger in it -- that line would mail "no such file" once a night for ever.
-- One machine is one desk, so one machine runs the job of the person whose desk it
-- is. Two computers in one office now do different things at two in the morning,
-- which is the whole of what this change is for.
--
-- THE MACHINE'S OWN (`profile.cron`, with a literal login in `to`) is root's, and
-- is what a job that belongs to no desk is: the military post's hourly door check
-- out of /usr/local/bin, the vendor's weekly sweep of /var. It is written whoever
-- owns the machine, because nothing in it names a home.
local function placeCron(state, session, profile, logins, owner, ownerSlot, now)
	if type(profile.cron) == "table" then
		for i = 1, #profile.cron do
			local item = profile.cron[i]
			placeOneCron(state, session, whoFor(item.to, logins, owner), item.lines, now)
		end
	end
	if ownerSlot ~= nil and type(profile.accounts) == "table" then
		local account = profile.accounts[ownerSlot]
		if type(account) == "table" then
			placeOneCron(state, session, owner, account.cron, now)
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
-- And what the OUTBREAK WEEK put in it, on top of whatever the premises' own
-- work was: three of these, picked by the machine's key and written at the end of
-- the week, at the hours nobody is at a desk. A machine that rebooted at four in
-- the morning, a login that was refused, a call that got no carrier.
--
-- They are here and not in a profile because every machine in the county had the
-- same week: what differs between a dispatch desk and a shop is what the OTHER
-- lines say, and the shop's machine rebooting at 03:12 on the 7th is not the
-- shop's story, it is July's.
--
-- Nothing in this list claims a halt. The dispatch desk's own log is a file people
-- typed in until five in the morning on the 9th, so a /var/log/messages saying the
-- machine went down on the 7th would be two files on one screen calling each other
-- liars -- which is why the police profile's own logs end on a disk error and not
-- on a shutdown, and why nothing that lands after them may end the machine either.
CeroSecContent.LOG_EVENTS = {
	"login: failed login on console",
	"kernel: unexpected restart",
	"cu: no carrier",
	"kernel: hda read error, retried",
	"syslogd: restarted",
	"login: failed login on console",
	"kernel: fd0 no disk in drive",
	"cron: no such device",
}
CeroSecContent.LOG_EVENT_COUNT = 3

local function placeLog(state, session, profile, secret, mkey, startTime, now)
	if type(profile.logs) ~= "table" or #profile.logs == 0 then return end
	if type(startTime) ~= "number" then return end
	-- The premises' own week, and then the county's. Built into a list of its own
	-- rather than added to the profile: the catalogue is a constant and a change that
	-- appended to profile.logs would be a change whose second machine had six extra
	-- lines on it.
	local messages, own = {}, #profile.logs
	for i = 1, own do messages[i] = profile.logs[i] end
	for i = 1, CeroSecContent.LOG_EVENT_COUNT do
		local pick = CeroSecContent.pick(CeroSecContent.LOG_EVENTS, secret,
			CeroSecContent.key(mkey, "logev", i))
		if pick ~= nil then messages[#messages + 1] = pick end
	end
	local lines = {}
	local days = CeroSecContent.LOG_DAYS
	-- MIDNIGHT of the start day and not the start moment: the save begins at nine
	-- in the morning, and an hour added to that put half the week's work after
	-- dark. A day is what the arithmetic below steps in, so a day is where it
	-- starts from.
	local midnight = math.floor(startTime / 86400) * 86400
	for i = 1, #messages do
		-- Spread over the week, oldest first, with the hour rolled out of the line's
		-- own key so two machines do not have an identical morning.
		local back = days - math.floor((i - 1) * days / #messages)
		-- Seven in the morning to four in the afternoon for the premises' own lines,
		-- which is when somebody was there -- and midnight to five for the outbreak
		-- week's, which is the whole point of them: a machine that came back up on
		-- its own at four in the morning is a machine nobody restarted.
		local hour
		if i <= own then
			hour = CeroSecContent.number(secret,
				CeroSecContent.key(mkey, "logh", i), 10) + 7
		else
			hour = CeroSecContent.number(secret,
				CeroSecContent.key(mkey, "logn", i), 6) - 1
		end
		local minute = CeroSecContent.number(secret,
			CeroSecContent.key(mkey, "logm", i), 60) - 1
		local at = midnight - back * 86400 + hour * 3600 + minute * 60
		-- Cut to the width of the screen, HERE, by the one function that composes
		-- the line. A survivor reads this file with `cat` on a sixty column terminal
		-- that does not wrap, so a line longer than sixty is a line whose end nobody
		-- can ever read -- and the hostname in front of the message is up to sixteen
		-- characters of it. Cutting it here means the world-content work, part 2 cannot write a message
		-- that disappears off the right of the glass.
		local line = CeroSecOS.formatStamp(at) .. " " .. state.hostname
			.. " " .. messages[i]
		lines[#lines + 1] = string.sub(line, 1, CeroSecOS.COLS)
	end
	place(state, session, CeroSecOS.LOG_PATH .. "/messages", "root",
		CeroSecOS.CRON_LOG_MODE, table.concat(lines, "\n"), now)
end

--
-- /var/mail/<login>: THE MAIL NOBODY HAD READ
--
-- the world-content work, part 3 rewrote this, and it is the part of the change a player is most likely to
-- read: people were doing things before they died, and mail is the one file on a
-- 1993 desk machine that is dated, addressed and written by somebody who is not in
-- the room. So a mailbox is now a STORY -- three to six messages over the outbreak
-- week, in three tellings like everything else, with the last one unanswered.
--
--   mail = {
--     {  -- telling 1
--       { to = "owner", from = "head office", subj = "...",
--         back = 5, hour = 9, min = 12, body = { "...", "..." } },
--       { to = 2, from = "...", ... },
--     },
--     { ... }, { ... },
--   }
--
-- `to` is whoFor's: "owner" is whoever's desk this is, a number is the premises'
-- account in that slot -- which is how one message lands in a mailbox whose home
-- is otherwise empty, and a survivor who logs in as the wrong man still finds
-- something -- and a string is a literal login.
--
-- `back` is DAYS BEFORE THE START DAY and never a date: the save's own start is
-- what the whole catalogue is dated from (see placeLog), so `back = 5` on the
-- default save is the 4th of July and on another save is five days before whatever
-- day that one begins. A message that would land at or after the moment the save
-- begins is DROPPED rather than moved -- the trimming rule, and it costs a save
-- that starts at half past midnight its last message and nothing else.
--
-- THE FORMAT is the machine's own, and it is the machine's own twice over. The
-- separator is the "From <sender>  <date>" line CeroSecOS.mailAppend writes, so a
-- mailbox this seeds and a mailbox cron appends to are one file that `mail` reads
-- from end to end. Under it are the four headers a message really carries -- From:,
-- To:, Date:, Subject: -- and the envelope line above repeating the sender and the
-- date is not a mistake: that is what an mbox is, and it is why `mail` can tell one
-- message from the next at all.
--
-- BOUNDED HERE, by lines and by bytes, because a mailbox is exempt from the disk
-- quota by its path and nothing else would bound it: messages are added while they
-- fit and the rest are not written. A story whose fourth message is missing is a
-- mailbox; a machine whose disk the loot filled is a bug.
local function mailStory(profile, secret, b1, b2)
	if type(profile.mail) ~= "table" or #profile.mail == 0 then return nil end
	local v = CeroSecContent.variantOf(secret, b1, b2, "var.mail")
	if v > #profile.mail then v = #profile.mail end
	local story = profile.mail[v]
	if type(story) ~= "table" then return nil end
	return story
end

local function mailLines(item, to, at, names)
	local out = {}
	local stamp = CeroSecOS.formatDate(at)
	local from = CeroSecContent.fillNames(item.from or "somebody", names)
	out[#out + 1] = "From " .. from .. "  " .. stamp
	out[#out + 1] = "From: " .. from
	out[#out + 1] = "To: " .. to
	out[#out + 1] = "Date: " .. stamp
	out[#out + 1] = "Subject: "
		.. CeroSecContent.fillNames(item.subj or "(no subject)", names)
	out[#out + 1] = ""
	if type(item.body) == "table" then
		for i = 1, #item.body do
			out[#out + 1] = CeroSecContent.fillNames(item.body[i], names)
		end
	end
	return out
end

local function placeMail(state, session, profile, secret, b1, b2, logins, owner,
		names, startTime, now)
	local story = mailStory(profile, secret, b1, b2)
	if story == nil or type(startTime) ~= "number" then return end
	local midnight = math.floor(startTime / 86400) * 86400
	-- One list of lines per mailbox, in the order the messages were written, so a
	-- mailbox that two of them land in reads as one mailbox.
	local boxes, order = {}, {}
	for i = 1, #story do
		local item = story[i]
		local to = whoFor(item.to, logins, owner)
		local at = midnight - (item.back or 0) * 86400
			+ (item.hour or 9) * 3600 + (item.min or 0) * 60
		if type(to) == "string" and CeroSecOS.getUser(state, to) ~= nil
				and at < startTime then
			if boxes[to] == nil then
				boxes[to] = {}
				order[#order + 1] = to
			end
			local box = boxes[to]
			if #box > 0 then box[#box + 1] = "" end
			local message = mailLines(item, to, at, names)
			for m = 1, #message do box[#box + 1] = message[m] end
		end
	end
	for i = 1, #order do
		local to = order[i]
		local kept = boxes[to]
		-- Bounded by the mailbox's own two ceilings, oldest kept and newest dropped:
		-- a mailbox is read from the top and the first message is the one that sets
		-- the scene.
		while #kept > CeroSecOS.MAIL_LINES do table.remove(kept) end
		local text = table.concat(kept, "\n")
		while #text > CeroSecOS.MAIL_BYTES and #kept > 1 do
			table.remove(kept)
			text = table.concat(kept, "\n")
		end
		place(state, session, CeroSecOS.mailPath(to), to, CeroSecOS.MAIL_MODE,
			text, now)
	end
end

--
-- ~/.sh_history: WHAT HE TYPED
--
-- The other half of "people were doing things before they died", and the half that
-- is in the man's own hand: a shell writes down every line entered at it
-- (CeroSecOS.historyAppend), so the history of the account whose desk this was is a
-- transcript of his last week with the boring parts left in.
--
-- Twelve to thirty lines. A shell keeps a thousand and a week of real work would
-- be a few hundred, but a survivor reads this with `cat` on a sixty column screen
-- and presses Up at the prompt: thirty lines is what a man can take in, and the
-- last six are the only ones that are about anything.
--
-- THE SHAPE. The body alternates the profile's own work lines with the lines
-- anybody types at any machine -- ls, who, date, df -- because nine tenths of a
-- real history is housekeeping and a history that was all story would read like a
-- film. A line repeats, which is also what a real one does. Then the TAIL, which is
-- the only part written to be read: he read his mail, he looked at the log, he rang
-- a number if there was one to ring, he locked what could be locked from a
-- keyboard, and then either he halted the machine and left or he did not.
--
-- AND A MACHINE THAT WAS LEFT LOGGED IN DOES NOT END ON A SHUTDOWN. The two are
-- one fact told twice: `shutdown -h now` is a man who closed the office, and a
-- session still open at the glass (CeroSecContent.liveSession) is a man who did
-- not. A history carrying both would be calling itself a liar on one screen.
--
-- EVERY LINE IS A COMMAND THE MACHINE HAS. The bench takes the first word of every
-- line of every history it can build and puts it through the shell's own lookup
-- (CeroSecOS.whyNotRun) on the machine the profile built -- so a history cannot
-- name a program this Unix does not have, and cannot name one that is only in /bin
-- on some other machine. Which is why the TYPOS below are typos in an ARGUMENT and
-- never in the command: a man mistyping a filename is a man, and a line whose first
-- word is nonsense is a line the bench cannot tell from a mistake in this table.
CeroSecContent.HISTORY_MIN = 12
CeroSecContent.HISTORY_SPAN = 19

CeroSecContent.HIST_COMMON = {
	"ls", "ls -a", "ls -l", "pwd", "who", "date", "df", "ps",
	"cat /etc/motd", "id", "whoami", "uptime", "ls /bin", "ls bin",
	"cat /var/log/messages", "man ls", "help", "echo $PATH", "w",
	"last", "df -h", "cd", "cat /etc/passwd", "which sh",
}

CeroSecContent.HIST_TYPOS = {
	"cat /var/log/messsages",
	"ls -l /hom",
	"cd /ect",
	"cat /etc/passwd.",
	"ls -la ~/bni",
	"more /etc/motd.txt",
}

-- The tail, for a man who shut the machine down and went home, and for one who
-- did not. Both end on the morning it started; the difference is the last line.
CeroSecContent.HIST_TAIL = {
	"mail", "cat /var/log/messages", "who", "date",
}
CeroSecContent.HIST_HALT = "shutdown -h now"

-- A history for one account. `work` is the profile's own lines for the man whose
-- desk it is, `tail` is whether this is the owner's history or a visitor's, and
-- `number` is a telephone number of the machine's own region or nil.
--
-- A NON-OWNER GETS TWO OR THREE LINES AND NO TAIL, and that is the other half of
-- the owner rule: `last` says three people logged in at this keyboard over the
-- fortnight, so three people have a history here -- and two of them sat down at
-- somebody else's desk, looked at one thing and went away, which is exactly two
-- lines long.
local function historyText(profile, secret, mkey, who, work, live, number)
	local lines = {}
	local common = CeroSecContent.HIST_COMMON
	if not who then
		local n = CeroSecContent.number(secret, CeroSecContent.key(mkey, "hv", "n"), 2) + 1
		for i = 1, n do
			lines[#lines + 1] = CeroSecContent.pick(common, secret,
				CeroSecContent.key(mkey, "hv", i))
		end
		return table.concat(lines, "\n")
	end
	local want = CeroSecContent.HISTORY_MIN
		+ CeroSecContent.number(secret, CeroSecContent.key(mkey, "hn"),
			CeroSecContent.HISTORY_SPAN) - 1
	local tail = CeroSecContent.HIST_TAIL
	-- THE WHOLE FILE IS `want` LINES, and the body is what is left after everything
	-- that is not negotiable: the two typos, the tail, the call, the last thing he
	-- locked and the halt. Counted here rather than added afterwards, because a body
	-- of `want` with nine lines appended to it is a history of `want` plus nine --
	-- which is what the first draft of this was, and the bench found it at 33 lines
	-- against a ceiling of 31.
	local fixed = 2 + #tail
	if type(number) == "string" and number ~= "" then fixed = fixed + 1 end
	if type(profile.lockup) == "string" then fixed = fixed + 1 end
	if not live then fixed = fixed + 1 end
	local body = want - fixed
	if body < 2 then body = 2 end
	for i = 1, body do
		local from = common
		-- Two in five from the premises' own work, which is about how much of a real
		-- history is the job and not the machine.
		if work ~= nil and #work > 0
				and CeroSecContent.number(secret, CeroSecContent.key(mkey, "hw", i), 5) <= 2 then
			from = work
		end
		local at = CeroSecContent.number(secret, CeroSecContent.key(mkey, "hb", i), #from)
		local line = from[at]
		-- NOT THE LINE HE JUST TYPED. A real history repeats itself, and this one
		-- does -- but a hash that lands twice running puts the same line under itself,
		-- and two identical lines in a row do not read as a man working, they read as
		-- a program filling a file. The next entry of the same list, which is still
		-- the same man and the same list.
		if line ~= nil and line == lines[#lines] then
			line = from[math.floor(CeroSecOS.mod(at, #from)) + 1]
		end
		if line ~= nil then lines[#lines + 1] = line end
	end
	-- A typo or two, in the middle of the week where one really happens.
	for i = 1, 2 do
		local at = CeroSecContent.number(secret, CeroSecContent.key(mkey, "hti", i),
			#lines)
		local typo = CeroSecContent.pick(CeroSecContent.HIST_TYPOS, secret,
			CeroSecContent.key(mkey, "ht", i))
		if typo ~= nil and at ~= nil then table.insert(lines, at, typo) end
	end
	for i = 1, #tail do lines[#lines + 1] = tail[i] end
	-- The telephone call, when the server could tell us a number of this machine's
	-- own region. No number, no line: a history naming an exchange that is not the
	-- one under the survivor's feet is the one lie the BBS disk is not allowed to
	-- tell either, and it is not allowed here.
	if type(number) == "string" and number ~= "" then
		lines[#lines + 1] = "cu " .. number
	end
	if type(profile.lockup) == "string" then lines[#lines + 1] = profile.lockup end
	if not live then lines[#lines + 1] = CeroSecContent.HIST_HALT end
	return table.concat(lines, "\n")
end

-- How many of the region's numbers the server need hand over. Eight, the BBS
-- disk's own number, and for the same reason: one is chosen out of them and a walk
-- of four hundred listings to choose it from is a walk nobody needs.
CeroSecContent.DIAL_MAX = 8

-- Whose number he rang. One of the region's own, off the machine's key, and never
-- the premises' own line -- a man does not ring the telephone on his own desk.
local function dialled(secret, mkey, numbers)
	if type(numbers) ~= "table" or #numbers == 0 then return nil end
	local pick = CeroSecContent.pick(numbers, secret, CeroSecContent.key(mkey, "dial"))
	if type(pick) ~= "string" or not CeroSecOS.isPhoneNumber(pick) then return nil end
	return pick
end

--
-- /var/log/wtmp: WHO LOGGED IN, AND WHO NEVER LOGGED OUT
--
-- What `last` reads, and the one file on the machine that says how many people
-- really used it. Seeded through CeroSecOS.wtmpAppend -- the engine's own writer,
-- record by record, oldest first -- because `last` pairs a login with the logout
-- that closed it in the ORDER THE FILE HAS THEM, and a file written any other way
-- is a file whose sessions pair up wrongly.
--
-- The fortnight before the save, the owner most often, the other staff now and
-- then, root when somebody had to be root. The last session is a couple of hours
-- before the save begins -- the morning of it, on the default save -- and it is the
-- one that may have no logout.
--
-- EVERY RECORD IS BEFORE THE SAVE BEGINS, counted backwards from the start itself
-- and not forwards from anything, so it is true of a save that starts in October
-- as well as of one that starts on the 9th of July.
CeroSecContent.WTMP_DAYS = 14
CeroSecContent.WTMP_MIN = 6
CeroSecContent.WTMP_SPAN = 9

-- One machine in four is found with somebody still logged in at it, and it is
-- never the military post: a post was a room a man was let into and he was relieved
-- or he left, and a terminal left at somebody's prompt inside a cordon is a story
-- about the wrong thing.
--
-- What it means on the glass is in SCeroSecObject:prefill, and what it costs in
-- fidelity is written there too.
CeroSecContent.LIVE_ONE_IN = 4

function CeroSecContent.liveSession(secret, mkey, profile)
	if type(profile) ~= "table" then return false end
	if profile.session == false then return false end
	return CeroSecContent.number(secret, CeroSecContent.key(mkey, "live"),
		CeroSecContent.LIVE_ONE_IN) == 1
end

-- Answers the moment of the last login, for the console that is going to be left
-- at that man's prompt.
local function placeWtmp(state, profile, secret, mkey, logins, owner, live, startTime)
	if type(startTime) ~= "number" then return nil end
	-- Who could have logged in here at all: the owner, the other staff, and root.
	-- A machine with no ordinary account on it has root and nobody else, which is
	-- what the military post is.
	local people = {}
	if type(owner) == "string" then people[#people + 1] = owner end
	if type(profile.accounts) == "table" then
		for i = 1, #profile.accounts do
			if logins[i] ~= nil and logins[i] ~= owner then
				people[#people + 1] = logins[i]
			end
		end
	end
	people[#people + 1] = "root"

	local n = CeroSecContent.WTMP_MIN
		+ CeroSecContent.number(secret, CeroSecContent.key(mkey, "wn"),
			CeroSecContent.WTMP_SPAN) - 1
	local midnight = math.floor(startTime / 86400) * 86400

	-- EVERY MOMENT FIRST, AND THE LENGTHS AFTERWARDS, and that is not tidiness: a
	-- session's logout has to fall before the next session's login or `last` prints
	-- a man leaving after the next man sat down. Only the whole list knows that, so
	-- the whole list is built before any of it is written.
	local who, at = {}, {}
	for i = 1, n do
		-- THE OWNER MOST: three sessions in five are his, and the rest are shared out
		-- among whoever else the premises has. It is his desk, and a `last` in which
		-- everybody used it equally is a `last` that says nothing.
		local name = owner
		if name == nil
				or CeroSecContent.number(secret, CeroSecContent.key(mkey, "ww", i), 5) > 3 then
			name = CeroSecContent.pick(people, secret, CeroSecContent.key(mkey, "wp", i))
		end
		if i == n then
			-- The last one: an hour to three before the save begins, and the owner's,
			-- whoever else came and went in the fortnight. It is his desk and he was
			-- the last man at it.
			if owner ~= nil then name = owner end
			at[i] = startTime - 3600
				- CeroSecContent.number(secret, CeroSecContent.key(mkey, "wl"), 120) * 60
		else
			-- The fortnight, oldest first, and the walk ends on YESTERDAY rather than
			-- wherever the arithmetic happened to stop: a desk whose last login before
			-- the morning of it was four days ago is a desk nobody worked at, which is
			-- not the story any of these premises tell.
			local span = CeroSecContent.WTMP_DAYS - 1
			local steps = n - 2
			if steps < 1 then steps = 1 end
			local back = CeroSecContent.WTMP_DAYS - math.floor((i - 1) * span / steps)
			if back < 1 then back = 1 end
			local hour = CeroSecContent.number(secret,
				CeroSecContent.key(mkey, "wh", i), 12) + 6
			local minute = CeroSecContent.number(secret,
				CeroSecContent.key(mkey, "wm", i), 60) - 1
			at[i] = midnight - back * 86400 + hour * 3600 + minute * 60
		end
		who[i] = name
	end

	local lastAt = nil
	for i = 1, n do
		local ends = startTime
		if i < n then ends = at[i + 1] end
		local out = at[i] + 1800
			+ CeroSecContent.number(secret, CeroSecContent.key(mkey, "wo", i), 300) * 60
		if out >= ends then out = ends - 600 end
		-- A session the arithmetic made shorter than a minute is a man who did not
		-- sit down: half an hour, which still ends before the next login because the
		-- moments above are never that close together.
		if out <= at[i] then out = at[i] + 1800 end
		-- THE ONE SESSION WITH NO LOGOUT, and only ever the last: a second open
		-- session would make `last` print two men still logged in on one console.
		if i == n and live then out = nil end
		if type(who[i]) == "string" and at[i] < startTime then
			CeroSecOS.wtmpAppend(state, "in", who[i], CeroSecOS.CONSOLE_LINE, nil, at[i])
			if out ~= nil and out < startTime then
				CeroSecOS.wtmpAppend(state, "out", who[i], CeroSecOS.CONSOLE_LINE, nil, out)
			end
			if i == n then lastAt = at[i] end
		end
	end
	if not live then return nil end
	return lastAt
end

--
-- PREFILL ONE MACHINE. The one entry point the server calls, and it is called in
-- exactly one place: SCeroSecObject:turnOn, for a machine whose state was nil a
-- moment ago. Never for a state that already existed -- a machine somebody has
-- used is his.
--
--   state       a state CeroSecOS.newState has just made
--   opts        { secret=, b1=, b2=, x=, y=, z=, premises=, rooms=, start=, now=,
--                 numbers= }
--
-- Answers FOUR things now: the profile id it used, the root password it derived,
-- the logins by slot, and -- the world-content work, part 3 -- the session that was still open at the
-- glass, as { user =, at = }, or nil. The password is answered for the BENCH and
-- for the sticky note's sake and is written nowhere: the caller may not keep it.
-- Answers nil for a machine it left alone.
--
-- `numbers` is a list of telephone numbers of the machine's own region, or nil.
-- The catalogue cannot ask for one -- it has no world and does not want one -- so
-- the server hands them in the way CeroSecNet.fillLateDisk hands the BBS disk its
-- listings, and a machine with none simply has no `cu` line in its history. A
-- history naming an exchange that is not the one under the survivor's feet is the
-- same lie the BBS disk refuses to tell.
--
-- Order matters and this is the order: the hostname, then the accounts (because
-- everything else is addressed to them), then their files and scripts, then the
-- machine-wide files, then the motd, then the log, the mail and the crontabs, and
-- last the three files that say what the last week looked like -- the histories,
-- the draft, and the login records. Everything after a refusal still runs -- a full
-- disk trims the tail of a profile and never its head.
--
function CeroSecContent.prefill(state, opts)
	if type(state) ~= "table" or type(opts) ~= "table" then return nil end
	if not CeroSecContent.isSecret(opts.secret) then return nil end
	local id = CeroSecContent.profileFor(opts.premises, opts.rooms)
	local profile = CeroSecContent.PROFILES[id]
	-- An id the world-content work, part 2 has not filled in yet. A bare machine, which is what one was
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

	-- WHOSE DESK THIS IS. One slot, off the machine's key, and the only home this
	-- machine has anything in.
	local slot = CeroSecContent.ownerSlot(secret, mkey, profile)
	local owner = nil
	if slot ~= nil then owner = logins[slot] end
	-- A slot whose login collided with one the machine already had: the desk is
	-- the first account that really got made, so a machine is never nobody's.
	if owner == nil and type(profile.accounts) == "table" then
		for i = 1, #profile.accounts do
			if logins[i] ~= nil then
				slot, owner = i, logins[i]
				break
			end
		end
	end

	-- The people, as the texts name them: the premises' staff by slot, the man at
	-- this keyboard, and the machine itself. Built once and handed to every write,
	-- so a name cannot be composed two ways.
	local names = {
		owner = owner,
		staff1 = logins[1], staff2 = logins[2], staff3 = logins[3],
		host = state.hostname,
	}

	if owner ~= nil then
		placeHomeFiles(state, session, profile.accounts[slot], owner, secret,
			opts.b1, opts.b2, names, now)
		-- The scripts go in the OWNER's ~/bin, which is the same rule his files
		-- follow: they are the tools on this desk. A copy in every home would be the
		-- same file three times on a 64K disk.
		placeScripts(state, session, profile, secret, mkey, owner, now)
	else
		-- A PROFILE WITH NO ORDINARY ACCOUNT AT ALL -- the military post -- and this
		-- branch is a bug fix and not a tidy-up. placeScripts used to be called only
		-- when there was an account to put a ~/bin under, so the post's one entry,
		-- which names /usr/local/bin and needs no home at all, was never written:
		-- /usr/local/bin/check.sh was missing on every military machine in the county
		-- and its crontab mailed "not found" once an hour for ever. The bench read
		-- the crontab against the PROFILE TABLE -- "does the catalogue always write
		-- this path" -- and the catalogue said yes, so it went green. Section 4 now
		-- asks the filesystem instead.
		placeScripts(state, session, profile, secret, mkey, nil, now)
	end

	if type(profile.files) == "table" then
		for i = 1, #profile.files do
			local file = profile.files[i]
			if type(file.path) == "string" then
				if file.dir then
					placeDirTree(state, session, file.path, file.owner or "root",
						file.mode or 755, now)
				else
					place(state, session, file.path, file.owner or "root", file.mode,
						CeroSecContent.textFor(file, secret, opts.b1, opts.b2, file.path,
							names), now)
				end
			end
		end
	end

	if type(profile.motd) == "string" then
		CeroSecOS.setData(state, session, CeroSecOS.MOTD_PATH, profile.motd, now)
	end

	placeLog(state, session, profile, secret, mkey, opts.start, now)
	placeMail(state, session, profile, secret, opts.b1, opts.b2, logins, owner,
		names, opts.start, now)

	--
	-- THE HISTORY, and it is the whole of what the world-content work, part 3 is for: people were doing
	-- things before they died. Three files say so and they have to agree.
	--
	-- WHO WAS STILL LOGGED IN, decided first because both of the other two depend on
	-- it: a man who never logged out did not type `shutdown -h now`, and his session
	-- in wtmp has no logout behind it.
	local live = owner ~= nil and CeroSecContent.liveSession(secret, mkey, profile)
	local number = dialled(secret, mkey, opts.numbers)

	-- ~/.sh_history, the owner's in full and a couple of lines for everybody else
	-- who sat down here, so that `last` naming three people is three people with a
	-- history on this machine.
	if type(profile.accounts) == "table" then
		for i = 1, #profile.accounts do
			local login = logins[i]
			if login ~= nil then
				local mine = login == owner
				local work = nil
				if mine then work = profile.history end
				local text = historyText(profile, secret,
					CeroSecContent.key(mkey, "h", i), mine, work, live, number)
				if text ~= nil and text ~= "" then
					place(state, session, "/home/" .. login .. "/"
						.. CeroSecOS.HISTORY_NAME, login, CeroSecOS.HISTORY_MODE, text, now)
				end
			end
		end
	end

	-- THE DRAFT HE WAS WRITING, on about half the machines, and it stops in the
	-- middle of a sentence because that is what happened to it.
	if owner ~= nil and type(profile.draft) == "table"
			and CeroSecContent.chance(secret, CeroSecContent.key(mkey, "draft"), 50) then
		place(state, session, "/home/" .. owner .. "/draft.txt", owner, 644,
			CeroSecContent.textFor({ texts = profile.draft }, secret, opts.b1, opts.b2,
				"draft.txt", names), now)
	end

	-- And the login records, last of the three, because the file they go in is the
	-- one `last` reads and the survivor reads it after everything else.
	local liveAt = placeWtmp(state, profile, secret, mkey, logins, owner, live,
		opts.start)
	placeCron(state, session, profile, logins, owner, slot, now)

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
	local session4 = nil
	if live and liveAt ~= nil then session4 = { user = owner, at = liveAt } end
	return id, password, logins, session4
end

--
-- THE PROFILES
--
-- Ten places in Knox County, each a story in three or four files, each carrying
-- at least one script a survivor can copy and use on a building of his own.
--
-- Every line of every text is inside 60 columns, because a survivor reads it with
-- `cat` on a 60 column screen and the terminal does not wrap. The bench holds
-- every one of them to it.
--
-- AND EVERY PROSE FILE HAS THREE TELLINGS (the world-content work, part 3). Which one a premises reads
-- is the premises' own (CeroSecContent.variantOf), so the office in the next town
-- tells the same kind of story in another voice, with its own people's names in it
-- where the text writes {owner}, {staff1}, {staff2}, {staff3} or {host}.
--
-- FOUR RULES THE THREE ARE WRITTEN TO, and none of them is obvious:
--
--   1. A TELLING IS PICKED PER FILE. Telling 2 of the handover note stands beside
--      telling 1 of the ledger, so any three may be read together -- which means
--      anything one file depends on another for (the column that is cents, the
--      name of a script, the number of a device) is the SAME in all three
--      tellings of both. What varies is the voice, the person writing, the detail
--      and the complaint. Never the machine underneath.
--   2. NOTHING NAMES A DATE THE SAVE MIGHT NOT HAVE, unless the file is a log
--      somebody typed in by hand -- those carry July because the outbreak is
--      July, and they are the same two files that already did.
--   3. NOBODY SIGNS HIS OWN NAME AS SOMEBODY ELSE'S. A file in slot 1's home is
--      written BY slot 1, so it names {staff2} and {staff3} and never {staff1};
--      {owner} is for a file that is about whoever's desk it is rather than about
--      the man who wrote it.
--   4. NO TOWN. See the head of CeroSecContent.PLACEHOLDERS: a town name would
--      have to be invented, and an invented town is a town that is not on the
--      map a player is standing on.
--

-- Three tellings, each a list of lines. A shorthand and nothing more: without it
-- every file in this table would be three calls to table.concat side by side and
-- the shape of a file would be lost in them.
local function three(a, b, c)
	return { table.concat(a, "\n"), table.concat(b, "\n"), table.concat(c, "\n") }
end

CeroSecContent.PROFILES = {}

CeroSecContent.PROFILES.residential = {
	host = "ksp",
	motd = table.concat({
		"This machine belongs to somebody who paid for it.",
		"Please do not change the wallpaper.",
	}, "\n"),
	accounts = {
		{ pass = false, files = {
			{ path = "notes.txt", texts = three({
				"Things to do before the weekend:",
				"",
				"- ring the bank about the cheque",
				"- the porch light is on a timer now, ask Dad",
				"- FIND THE MANUAL",
			}, {
				"List, because otherwise I will forget all of it.",
				"",
				"- the gutter, before it rains again",
				"- two more tins of lamp oil",
				"- ask {staff2} about the trailer on Saturday",
				"- the porch light. Read porch.txt. Stop asking me.",
			}, {
				"Nobody is answering at the office and the radio has",
				"said the same four sentences since Tuesday.",
				"",
				"- fill everything in the house that holds water",
				"- the good padlock, on the shed",
				"- if {staff2} gets back, the keys are where they were",
				"- we are not driving north. They have that road.",
			}) },
			{ path = "porch.txt", texts = three({
				"How the porch light works, since nobody believes me.",
				"",
				"There is a little box wired to the switch and the",
				"computer can see it. It is light0. Two commands:",
				"",
				"  cat /dev/light0",
				"  echo off > /dev/light0",
				"",
				"That is all a timer is. If there is a script in my",
				"bin, it does the same thing and saves the typing.",
			}, {
				"The porch light. Read this before you touch the",
				"switch on the wall.",
				"",
				"The switch has a box on it and the box is on the",
				"computer. The computer calls it light0 and calls",
				"nothing else light0.",
				"",
				"  cat /dev/light0        what it is doing now",
				"  echo on > /dev/light0",
				"  echo off > /dev/light0",
				"",
				"It is not a timer. A timer is somebody writing the",
				"third line down and the machine typing it at ten.",
			}, {
				"{owner}'s porch light, written down because I am",
				"tired of explaining it at the table.",
				"",
				"  cat /dev/light0",
				"  echo off > /dev/light0",
				"",
				"light0 is the porch and that is the whole of it.",
				"The kitchen was never wired. The man was paid for",
				"both and came back for neither.",
			}) },
		} },
		{ pass = false, files = {
			{ path = "report.txt", texts = three({
				"THE COUNTY IN 1830 -- by me, for Tuesday",
				"",
				"In 1830 there was nothing here but the river and",
				"the salt works. My grandmother says the trestle came",
				"later and that is where the town went.",
				"",
				"I have three pages and it has to be four. Dad says",
				"do not pad it. I am going to pad it.",
			}, {
				"THE RIVER -- {staff2}, fourth period",
				"",
				"The river is the only reason anybody is here. Coal",
				"went down it before there was a rail bed, and the",
				"rail bed only went in because the river freezes.",
				"",
				"Miss wants four pages. I have two and a map, and I",
				"am counting the map.",
			}, {
				"WHAT A COMPUTER IS -- for Thursday, and it is not",
				"due until Thursday",
				"",
				"It is a box with a disk in it. You type a word and",
				"press the key and it does the word. There are about",
				"sixty words. I have found forty of them and written",
				"them on the back of this page.",
				"",
				"Dad says put in what it cost. I am not putting in",
				"what it cost.",
			}) },
		} },
	},
	bin = { { script = "lights.sh", chance = 35 } },
	logs = {
		"login: admin logged in on console",
		"login: admin logged in on console",
	},

	-- WHAT HE TYPED, and the lines are the premises' own: a house machine is a
	-- porch light and a list of things to do.
	history = {
		"cat notes.txt",
		"edit notes.txt",
		"cat porch.txt",
		"cat /dev/light0",
		"echo off > /dev/light0",
		"echo on > /dev/light0",
		"dev light",
		"sh bin/lights.sh light0",
	},
	lockup = "echo off > /dev/light0",
	draft = three({
		"Dear Ruth",
		"",
		"I have started this three times. The roads are shut",
		"and the man on the radio says it is a precaution, and",
		"nobody I have spoken to believes him.",
		"",
		"If you get this at all, we are going to the",
	}, {
		"To whoever is in this house after us.",
		"",
		"The water is off at the valve under the stairs and",
		"the heater is off at the breaker. Neither of them is",
		"broken. There is food in the",
	}, {
		"Tuesday",
		"",
		"I am writing it down because I keep forgetting what",
		"day things happened on. Monday the school shut.",
		"Tuesday the telephone stopped ringing out and started",
		"just ringing. Today",
	}),
	mail = {
		{
			{ to = "owner", from = "knox!rholland", subj = "Saturday",
				back = 5, hour = 8, min = 40, body = {
					"We have the trailer free Saturday and Sunday both.",
					"Ring the house, not the yard. Nobody is at the yard.",
				} },
			{ to = 2, from = "root", subj = "your account",
				back = 4, hour = 19, min = 5, body = {
					"I have made you your own login so that you stop",
					"using mine. It is open. Do not change the wallpaper.",
				} },
			{ to = "owner", from = "wknx!news", subj = "the roads",
				back = 1, hour = 6, min = 30, body = {
					"Nothing north and nothing east. The county says it is",
					"a precaution and the county has said that for three",
					"days now.",
				} },
			{ to = "owner", from = "knox!rholland", subj = "are you there",
				back = 0, hour = 5, min = 55, body = {
					"Anything. One line. I have tried the telephone eleven",
					"times.",
				} },
		},
		{
			{ to = "owner", from = "knox!jbarrett", subj = "the gutter",
				back = 5, hour = 11, min = 20, body = {
					"I can do it Thursday if it is dry. Leave the ladder",
					"round the side.",
				} },
			{ to = "owner", from = "cerosec!support", subj = "your enquiry",
				back = 3, hour = 14, min = 10, body = {
					"There is no module on your kitchen switch, which is",
					"why the computer cannot see it. That is an",
					"electrician and not us. The porch one is fine.",
				} },
			{ to = 2, from = "the house", subj = "school",
				back = 2, hour = 7, min = 15, body = {
					"No school today and none tomorrow. Stay in the house",
					"and do not answer the door to anybody at all.",
				} },
			{ to = "owner", from = "knox!jbarrett", subj = "Thursday",
				back = 0, hour = 6, min = 40, body = {
					"I am not coming Thursday. Nobody is coming Thursday.",
					"Get out if you have anywhere to go.",
				} },
		},
		{
			{ to = "owner", from = "wknx!news", subj = "the swap shop",
				back = 5, hour = 9, min = 5, body = {
					"Your notice went out at twelve. Two people rang about",
					"the bicycle and neither left a number, which is the",
					"usual.",
				} },
			{ to = "owner", from = "knox!ehatfield", subj = "the lamp oil",
				back = 3, hour = 16, min = 45, body = {
					"The shop has none and the shop is not getting any.",
					"I have three tins. Come and take one.",
				} },
			{ to = "owner", from = "county!clerk", subj = "notice",
				back = 1, hour = 8, min = 0, body = {
					"Residents are asked to remain at their addresses.",
					"This notice will be repeated on the hour.",
				} },
			{ to = "owner", from = "knox!ehatfield", subj = "(no subject)",
				back = 0, hour = 4, min = 20, body = {
					"There is somebody in the road outside my house and he",
					"has been there since two in the morning. I am not",
					"going out to him. Are you awake",
				} },
		},
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
			{ path = "handover.txt", texts = three({
				"Whoever is covering for me:",
				"",
				"The nightly job mails the totals to me at two in",
				"the morning. If the mail stops, the job stopped --",
				"look at crontab -l before you look at anything else.",
				"",
				"The ledger is ledger.txt and the second column is",
				"cents. Never dollars. It has never been dollars.",
			}, {
				"Covering this desk, in the order it matters.",
				"",
				"1. crontab -l. One line, at two in the morning. It",
				"   adds up the second column of ledger.txt and mails",
				"   the number to me.",
				"2. That column is CENTS. Every argument this office",
				"   has ever had began by forgetting it.",
				"3. No mail at two means the job did not run. Read the",
				"   line before you read the figures.",
				"",
				"{staff2} has a key to the cabinet. I have not.",
			}, {
				"Notes for {staff3}, since you asked and I am out on",
				"Friday and Monday both.",
				"",
				"The machine adds the ledger up by itself at two in",
				"the morning and mails me the number. crontab -l shows",
				"you the line. It is one line and I would rather you",
				"did not edit it while I am not here.",
				"",
				"ledger.txt is a name and then cents. Yes, the coffee",
				"fund is a real line of the ledger.",
			}) },
			{ path = "ledger.txt", texts = three({
				"freight:41200",
				"paper and toner:8875",
				"telephone:12340",
				"the coffee fund:1500",
			}, {
				"freight:38650",
				"telephone:11980",
				"paper and toner:6240",
				"postage:2075",
				"the coffee fund:1500",
			}, {
				"freight:44100",
				"telephone:12610",
				"paper and toner:9330",
				"the machine, monthly:22500",
				"the coffee fund:1500",
			}) },
		}, cron = { "0 2 * * * sh $HOME/bin/total.sh $HOME/ledger.txt 2" } },
		{ pass = false, files = {
			{ path = "readme.txt", texts = three({
				"My password is my own business. Ask me and I will",
				"type it for you.",
			}, {
				"This account is open on purpose.",
				"",
				"There is nothing in here worth locking, and I would",
				"rather you used it than sat down at {staff1}'s desk",
				"and made a mess of his.",
			}, {
				"Left open. If you need the machine, use the machine.",
				"",
				"What I will not do is write my own password on a",
				"square of yellow paper and put it in the top drawer",
				"like everybody else on this floor.",
			}) },
		} },
		{ pass = true, files = {
			{ path = "memo.txt", texts = three({
				"To the three of you, and I am not saying it again:",
				"",
				"The machine is not a filing cabinet. Anything that",
				"has to survive this office goes on a disk and the",
				"disk goes in the cabinet. Sixty-four thousand bytes",
				"is a week of work, not a career.",
			}, {
				"{staff1}, {staff2}: the disk.",
				"",
				"Sixty-four thousand bytes. That is the whole machine",
				"and not the whole of your share of it. When it fills,",
				"the next thing anybody types is refused, and it will",
				"be refused at the worst hour of the worst day.",
				"",
				"Anything that has to survive goes on a floppy and the",
				"floppy goes in the cabinet. df says where we are.",
			}, {
				"Read this before the audit and not during it.",
				"",
				"Nothing on this machine is a record. The record is",
				"the paper in the cabinet and it always has been. What",
				"is on the disk is a convenience, and a convenience",
				"somebody has to type back in is not one.",
				"",
				"In writing, so that nobody can say afterwards that",
				"he was not told.",
			}) },
		} },
	},
	bin = {
		{ script = "lights.sh", chance = 60 },
		{ script = "total.sh" },
	},
	logs = {
		"login: root logged in on console",
		"cron: ran the nightly totals",
		"login: failed login on console",
		"cron: ran the nightly totals",
	},

	history = {
		"cat handover.txt",
		"cat ledger.txt",
		"edit ledger.txt",
		"sh bin/total.sh ledger.txt 2",
		"crontab -l",
		"cat memo.txt",
		"df",
		"sudo cat /var/log/messages",
	},
	draft = three({
		"To the board, and I will put this properly when I have",
		"the figures in front of me.",
		"",
		"Freight is up a third on the quarter and it is not the",
		"rate, it is the number of runs. Two of our three",
		"carriers have stopped answering the telephone and the",
		"third has put his",
	}, {
		"Memorandum: closing the office",
		"",
		"Nobody has told us to close and nobody is going to.",
		"So I am writing down what closing would mean, because",
		"somebody is going to have to decide it on a Friday",
		"afternoon with half the",
	}, {
		"{staff3} --",
		"",
		"I have thought about what you said and I think you are",
		"right about the disk. Sixty-four thousand bytes is not",
		"a filing cabinet and I have been treating it like one",
		"for two years. What I would do instead is",
	}),
	mail = {
		{
			{ to = "root", from = "head office", subj = "the new passwords",
				back = 5, hour = 9, min = 25, body = {
					"Nobody is to write a password down where it can be",
					"read. We will be checking the desks.",
				} },
			{ to = "owner", from = "head office", subj = "the quarter",
				back = 4, hour = 10, min = 40, body = {
					"Freight, telephone and paper, in cents, by Friday.",
					"The machine can add the column up. Do not send me a",
					"column and call it a total.",
				} },
			{ to = 2, from = "knox!ltorres", subj = "not in today",
				back = 2, hour = 7, min = 5, body = {
					"I am not coming in. It is not me, it is the road --",
					"they have it shut at the bridge and there is no way",
					"round that does not add an hour.",
				} },
			{ to = "owner", from = "county!clerk", subj = "the affected area",
				back = 1, hour = 9, min = 55, body = {
					"The area is the county south of the river. Businesses",
					"inside it are asked to secure and close. There is no",
					"timetable and there will not be one today.",
				} },
			{ to = "owner", from = "head office", subj = "Friday",
				back = 0, hour = 6, min = 50, body = {
					"Ignore the last one. Nobody wants the quarter.",
					"Is there anybody in the building. Anybody at all.",
				} },
		},
		{
			{ to = "owner", from = "cerosec!support", subj = "ticket 418",
				back = 5, hour = 13, min = 15, body = {
					"Your drive belt is on order and we are told two",
					"weeks. The machine will run on the hard disk in the",
					"meantime, which is what it has been doing.",
				} },
			{ to = "owner", from = "head office", subj = "the coffee fund",
				back = 4, hour = 15, min = 50, body = {
					"It is a line of the ledger and it is going to stay a",
					"line of the ledger. I have had three letters about",
					"this and I am not having a fourth.",
				} },
			{ to = 3, from = "knox!dmullins", subj = "the cabinet key",
				back = 2, hour = 8, min = 30, body = {
					"Mine is in my desk, top drawer, at the back. Take it",
					"if you need it. I do not know when I am next in.",
				} },
			{ to = "owner", from = "county!clerk", subj = "businesses",
				back = 1, hour = 11, min = 0, body = {
					"Premises within the affected area are asked to",
					"secure and close. There is no compensation scheme",
					"and there is no timetable.",
				} },
			{ to = "owner", from = "head office", subj = "(no subject)",
				back = 0, hour = 7, min = 20, body = {
					"Close it. Lock what you can and go home to your",
					"family. Somebody tell me you got this.",
				} },
		},
		{
			{ to = "owner", from = "knox!wsizemore", subj = "the invoice",
				back = 5, hour = 8, min = 55, body = {
					"Your figure and my figure differ by a hundred times",
					"exactly, which means one of us is reading cents as",
					"dollars, and it is not me.",
				} },
			{ to = 2, from = "the office manager", subj = "the machine",
				back = 4, hour = 17, min = 30, body = {
					"Leave it switched on. The job at two in the morning",
					"is the only thing in this office that has not",
					"failed this month.",
				} },
			{ to = "owner", from = "wknx!news", subj = "your notice",
				back = 2, hour = 12, min = 10, body = {
					"We read it at noon and again at six. If you want it",
					"changed, ring before nine. Nobody is here after",
					"nine any more.",
				} },
			{ to = "owner", from = "knox!wsizemore", subj = "forget the invoice",
				back = 0, hour = 6, min = 5, body = {
					"Forget it. I am taking the family south this morning",
					"and I am telling everybody I can reach to do the",
					"same. Go.",
				} },
		},
	},
}

CeroSecContent.PROFILES.police = {
	host = "disp",
	motd = table.concat({
		"KNOX COUNTY SHERIFF -- DISPATCH",
		"Official use only. Every login is written down, and",
		"so is every line typed at this keyboard.",
	}, "\n"),
	root = true,
	accounts = {
		-- NAMED, and the one profile that names an account: a dispatch desk was
		-- worked in shifts by whoever was on, and a login per deputy is a login
		-- nobody remembers at four in the morning. It carries a password because
		-- the desk did.
		{ name = "dispatch", pass = true, admin = true, files = {
			{ path = "handover.txt", texts = three({
				"Whoever sits down next:",
				"",
				"The cell doors are on the computer now. locks.sh in",
				"my bin does the pair of them at once:",
				"",
				"  sh ~/bin/locks.sh lock lock0 lock1",
				"",
				"Check with dev lock before you walk away. The strike",
				"on the back cell sticks and reads locked when it is",
				"not. The log is /var/log/dispatch. Write in it. It",
				"is the only thing anybody upstairs ever reads.",
			}, {
				"Handover. Four things and then you are on your own.",
				"",
				"  sh ~/bin/locks.sh lock lock0 lock1",
				"  dev lock",
				"",
				"The first line bolts both cells. The second reads",
				"them back, and you read them back because the strike",
				"on the back one sticks and says locked when it is",
				"standing open.",
				"",
				"Everything that happens goes in /var/log/dispatch,",
				"in your own hand. Nobody upstairs reads anything",
				"else and nobody upstairs ever will.",
			}, {
				"{staff2}, {staff3}: read this once.",
				"",
				"This login is all of ours. Do not make yourself one",
				"of your own -- the county wants one name on the desk",
				"and this is the name.",
				"",
				"  sh ~/bin/locks.sh lock lock0 lock1",
				"",
				"That is both cells. dev lock afterwards, every time,",
				"because the back strike lies. /var/log/dispatch is",
				"the log and it is the only thing that leaves here.",
			}) },
			{ path = "bolo.txt", texts = three({
				"BE ON THE LOOKOUT -- standing list, 8 July",
				"",
				"Grey pickup, no plate, on the Muldraugh road three",
				"nights running. Do not stop it on your own.",
				"",
				"Two men on foot out of West Point, walking north on",
				"the rail bed. Wanted for the co-op break-in.",
				"",
				"Anybody in a hospital gown outside the fence. The",
				"state people want to be told. We do not go in.",
			}, {
				"BE ON THE LOOKOUT -- standing, read at every shift",
				"",
				"A flatbed with the tailgate wired shut, seen at the",
				"co-op twice after dark. Two men in it. Do not stop",
				"it without somebody behind you.",
				"",
				"A woman, forties, walking the rail bed both ways for",
				"three days. Not wanted. Somebody talk to her.",
				"",
				"Anybody coming out of the hospital grounds on foot.",
				"The state people want to hear about every one and",
				"they have told us twice not to go in after them.",
			}, {
				"BE ON THE LOOKOUT -- and the list is shorter than it",
				"was, which is not good news.",
				"",
				"The grey pickup is off the list. We found it.",
				"",
				"Two men out of West Point, north on the rail bed,",
				"still wanted for the break-in and by now probably",
				"for worse. On foot.",
				"",
				"And this is the standing order as of the 8th: nobody",
				"goes inside the hospital fence for any reason. Not",
				"for a call, not for one of ours. It is in writing",
				"because somebody is going to want to argue with it.",
			}) },
		}, cron = { "0 22 * * * sh $HOME/bin/locks.sh lock lock0 lock1" } },
		{ pass = false, files = {
			{ path = "shifts.txt", texts = three({
				"Nights, this week and next. Nobody has swapped and",
				"nobody is going to, so stop asking me.",
				"",
				"There are four of us for seven nights. Work it out.",
			}, {
				"The board, since somebody keeps rubbing out the real",
				"one.",
				"",
				"Four of us. Seven nights. Two of those four are on",
				"the road for the county on Thursday and Friday.",
				"",
				"I have stopped writing names on it. Ask {staff1}",
				"who is on and believe what he says.",
			}, {
				"Nights.",
				"",
				"There is no schedule any more. There are four of us",
				"and there is the telephone, and whoever answers it",
				"is on.",
				"",
				"That is not a complaint. It is what to expect when",
				"you come in.",
			}) },
		} },
		{ pass = true, files = {
			{ path = "keys.txt", texts = three({
				"What is on the ring, because the tags fell off and",
				"nobody has replaced them since I have been here.",
				"",
				"  long brass       the back door",
				"  short brass      the cabinet in the hall",
				"  the flat one     the gate, and it sticks",
				"",
				"The cells are not on the ring. The cells are on the",
				"computer, which is the whole argument this office",
				"had last spring.",
			}, {
				"The ring, from the fob outwards:",
				"",
				"  1  back door",
				"  2  hall cabinet",
				"  3  the gate. Lift, then turn.",
				"  4  nothing. It has opened nothing in two years and",
				"     I am keeping it anyway.",
				"",
				"Cell doors are not keys any more, they are the",
				"computer. Ask {staff1} to show you once.",
			}, {
				"Keys. Read it and put the ring back on the hook.",
				"",
				"  long brass   back door",
				"  short brass  hall cabinet",
				"  flat         gate",
				"",
				"The gate one is bent and it will go in wrong way up",
				"and feel right. If it will not turn, take it out and",
				"look at it before you force it.",
				"",
				"The cells are the computer's. Not this ring's.",
			}) },
		} },
	},
	bin = {
		{ script = "locks.sh" },
		{ script = "check.sh", chance = 60 },
		{ script = "lights.sh", chance = 40 },
	},
	files = {
		-- THE SPINE OF THE STORY, and it is in /var/log because that is where a
		-- log lives: root's, at the mode the machine's own logs wear, so an
		-- account in the sudo group reads it and a stranger does not.
		--
		-- One of the two files in the catalogue that carries July in as many words,
		-- and it may: a hand-kept log of what happened is about the days it is
		-- about. All three tellings end in the middle of a line on the morning of
		-- the 9th, because whatever a deputy was writing then, he did not finish it.
		{ path = "/var/log/dispatch", owner = "root", mode = 640,
			texts = three({
				"Jul 05 0710 traffic, 31 at the line, cleared",
				"Jul 06 2240 alarm at the co-op, nobody there",
				"Jul 07 0155 fight outside the tavern, two in",
				"Jul 07 1400 hospital wants two units, sent two",
				"Jul 08 0620 hospital again, sent everybody",
				"Jul 08 1910 lost contact with unit 4",
				"Jul 08 2335 lost contact with unit 2",
				"Jul 09 0402 nobody answering the desk telephone",
				"Jul 09 0505",
			}, {
				"Jul 04 1130 fireworks call, Elm, spoke to them",
				"Jul 05 1620 co-op, shoplift, released",
				"Jul 06 0840 two vehicles at the line, both turned",
				"Jul 06 2115 domestic, one in, released 0200",
				"Jul 07 1105 hospital asks for a unit at the doors",
				"Jul 07 2340 hospital asks again. Sent 3 and 4.",
				"Jul 08 0515 unit 3 not answering",
				"Jul 08 0640 unit 4 not answering",
				"Jul 08 2050 the state people took the telephone",
				"Jul 09 0447 whoever is reading this, the keys are in",
			}, {
				"Jul 05 0925 traffic, cleared",
				"Jul 05 2200 cells locked, both, checked by hand",
				"Jul 06 1315 assist the fire service, the mill road",
				"Jul 07 0340 fight, tavern, two in, one to hospital",
				"Jul 07 1750 hospital will not take him",
				"Jul 08 0800 nine calls in an hour and four of us",
				"Jul 08 1240 told to hold at the county line",
				"Jul 08 2317 unit 2 off the air, last at the bridge",
				"Jul 09 0510 I am going to look for him. If nobody",
			}) },
	},
	-- NO HALT ON THE END OF THIS ONE, and that is not a detail: the dispatch log
	-- above is a file people TYPED in, and its last line is at five in the morning
	-- on the 9th. A machine whose /var/log/messages said it went down on the 7th
	-- would be a machine that cannot have been typed at on the 8th, and the two
	-- files would be calling each other liars on the same screen.
	logs = {
		"login: dispatch logged in",
		"su: dispatch to root",
		"login: dispatch logged in",
		"login: failed login on console",
		"login: dispatch logged in",
		"kernel: fd0 no disk in drive",
	},

	history = {
		"sh bin/locks.sh lock lock0 lock1",
		"sh bin/locks.sh unlock lock0",
		"dev lock",
		"dev",
		"sudo cat /var/log/dispatch",
		"cat handover.txt",
		"cat bolo.txt",
		"edit bolo.txt",
		"crontab -l",
	},
	lockup = "sh bin/locks.sh lock lock0 lock1",
	draft = three({
		"REPORT -- and I will type it properly when somebody",
		"is here to take it.",
		"",
		"At about six this morning I was asked to send a unit",
		"to the hospital doors for the third time in two days.",
		"I sent everybody. What I want on the record is that I",
		"was told not to",
	}, {
		"To the county, from this desk.",
		"",
		"Four men. Seven nights. Nine calls in the hour before",
		"I started writing this. I have been asked twice today",
		"to hold at the line and both times the call I was",
		"holding away from was",
	}, {
		"For whoever reads the log after me.",
		"",
		"Unit 2 went off the air at the bridge and I am not",
		"going to be the man who wrote that down and then sat",
		"here. The cells are locked, the front is bolted and",
		"the keys are",
	}),
	mail = {
		{
			{ to = "owner", from = "the desk sergeant", subj = "the cells",
				back = 5, hour = 10, min = 5, body = {
					"Both of them stay locked from ten at night whoever",
					"is in them. That is not mine, it came down from the",
					"county. Put it on the computer and stop arguing.",
				} },
			{ to = "owner", from = "county!clerk", subj = "the roads",
				back = 3, hour = 14, min = 20, body = {
					"The bridge is closed to everybody including you. The",
					"rail bed is not a road and nobody is to use it as",
					"one.",
				} },
			{ to = 2, from = "knox!ewhitaker", subj = "tonight",
				back = 2, hour = 16, min = 45, body = {
					"I cannot get in tonight and I am not going to",
					"pretend I can. My road has three cars across it and",
					"nobody in any of them.",
				} },
			{ to = "owner", from = "the desk sergeant", subj = "(no subject)",
				back = 0, hour = 4, min = 35, body = {
					"Forget the cells. Forget the log. If you are still",
					"at that desk when you read this, go home.",
				} },
		},
		{
			{ to = "owner", from = "the desk sergeant", subj = "the strike",
				back = 5, hour = 9, min = 15, body = {
					"The back cell reads locked when it is standing open",
					"and it has done for a month. Read it back with dev",
					"lock, every time, until somebody comes to fix it.",
				} },
			{ to = "owner", from = "the hospital", subj = "the doors",
				back = 3, hour = 6, min = 50, body = {
					"We need somebody at the doors and we have needed",
					"somebody since last night. I am not going to keep",
					"asking politely.",
				} },
			{ to = "owner", from = "county!clerk", subj = "the line",
				back = 1, hour = 13, min = 5, body = {
					"Hold at the county line. Do not cross it for a call",
					"and do not cross it for one of your own. This is not",
					"a request from this office.",
				} },
			{ to = 3, from = "knox!ewhitaker", subj = "my keys",
				back = 0, hour = 5, min = 40, body = {
					"The ring is in the hall cabinet. I am not going to",
					"be needing it. Whoever is left, the gate one is",
					"bent and goes in the other way up.",
				} },
		},
		{
			{ to = "owner", from = "wknx!news", subj = "what do we say",
				back = 5, hour = 11, min = 40, body = {
					"We will read anything the sheriff's office gives us",
					"and we will read nothing it does not. Somebody",
					"telephone us before six.",
				} },
			{ to = "owner", from = "the desk sergeant", subj = "unit 4",
				back = 2, hour = 20, min = 15, body = {
					"He is not answering and his car is at the co-op with",
					"the door open. Nobody goes on his own. Nobody.",
				} },
			{ to = 2, from = "the desk sergeant", subj = "the bolo",
				back = 1, hour = 7, min = 30, body = {
					"Take the pickup off the standing list. We found it.",
					"Leave the two men on foot on it.",
				} },
			{ to = "owner", from = "the hospital", subj = "please",
				back = 0, hour = 5, min = 10, body = {
					"There is nobody outside our doors now and that is",
					"worse. Is there anybody at that desk.",
				} },
		},
	},
}

CeroSecContent.PROFILES.bank = {
	host = "vault",
	motd = table.concat({
		"This terminal records every login and every figure",
		"typed at it. Do not leave it logged in and do not",
		"write your password anywhere near it.",
	}, "\n"),
	root = true,
	accounts = {
		{ pass = true, admin = true, files = {
			-- The table itself is ONE telling, and it has to be: it is the very file
			-- audit.sh and total.sh are proved against (CeroSecContent.DATA), and a
			-- table that came out different on every machine would be a bench proving
			-- one of three. What varies is the ROWS UNDER IT -- this branch's own
			-- accounts -- which is `extra`, and the six the bench adds up are still
			-- the six the bench adds up.
			{ path = "accounts.dat", text = CeroSecContent.DATA["accounts.dat"],
				extra = {
					{ "1047:checking:1989:3300", "1048:savings:1986:24175" },
					{ "1051:checking:1993:118", "1052:checking:1988:7640",
						"1053:savings:1990:41200" },
					{ "1062:savings:1985:9015" },
				} },
			{ path = "audit.txt", texts = three({
				"The examiner comes on the second Tuesday and wants",
				"the same three answers every time.",
				"",
				"How many of them are checking accounts:",
				"",
				"  sh ~/bin/audit.sh accounts.dat checking",
				"",
				"What the balances add up to, in cents:",
				"",
				"  sh ~/bin/total.sh accounts.dat 4",
				"",
				"The fourth column has been cents since 1987 and he",
				"knows it. Do not convert it for him.",
			}, {
				"For the examiner. Second Tuesday, every month, and",
				"he has asked the same two questions for six years.",
				"",
				"  sh ~/bin/audit.sh accounts.dat checking",
				"  sh ~/bin/total.sh accounts.dat 4",
				"",
				"The first prints the checking accounts. The second",
				"adds the fourth column up, which is CENTS and has",
				"been cents since 1987.",
				"",
				"He will ask you to read it to him in dollars. Read",
				"him the number that is on the screen.",
			}, {
				"{staff2}: this is the whole of the audit and I am",
				"writing it down because I am due to retire.",
				"",
				"Two commands. Nothing else on this machine is part",
				"of it.",
				"",
				"  sh ~/bin/audit.sh accounts.dat checking",
				"  sh ~/bin/total.sh accounts.dat 4",
				"",
				"Column four is cents. If a figure looks a hundred",
				"times too big, it is not, and you are the hundredth",
				"person to think so.",
			}) },
		}, cron = { "0 18 * * 1-5 sh $HOME/bin/lockup.sh door0 lock0" } },
		{ pass = true, files = {
			{ path = "vault.txt", texts = three({
				"The vault door is on the computer now and it is not",
				"a lock anybody picks. It is also not a lock the",
				"computer can force: lockup.sh pulls the door to and",
				"then turns the bolt, and if the door will not close",
				"it says so and stops rather than bolting air.",
				"",
				"Read it before you trust it:",
				"",
				"  cat ~/bin/lockup.sh",
			}, {
				"The door, and why the script is written the way it",
				"is written.",
				"",
				"  sh ~/bin/lockup.sh door0 lock0",
				"",
				"It closes door0. Then it READS door0 back. Only",
				"then does it turn lock0. A bolt thrown at a door",
				"that did not close is a bolt across a gap, and the",
				"screen would have said it worked.",
				"",
				"  cat ~/bin/lockup.sh",
				"",
				"Nine lines. Read them once and you will never trust",
				"a program that does not read its own work back.",
			}, {
				"Closing the vault.",
				"",
				"  sh ~/bin/lockup.sh door0 lock0",
				"",
				"door0 is the door and lock0 is the bolt, and they",
				"are two separate pieces of iron whatever the panel",
				"upstairs looks like.",
				"",
				"The script stops and says so if the door did not",
				"come to. When it says so, go and look at the door",
				"with your own eyes. Every time. {owner} has had to",
				"do it twice this year.",
			}) },
		} },
		{ pass = false, files = {
			{ path = "counter.txt", texts = three({
				"The counter, opening and closing.",
				"",
				"The drawer count goes in the book and not in here.",
				"The book is the record. This machine is where the",
				"month's figures get added up and nowhere else.",
				"",
				"Two of the three lamps over the counter are on the",
				"same switch and it is not the switch you expect.",
			}, {
				"Notes for a new teller, in the order you will need",
				"them.",
				"",
				"1. Count into the book. Always the book.",
				"2. The machine is for adding a column up, and there",
				"   is a program for that in {staff1}'s bin.",
				"3. The examiner is nobody's problem but {staff1}'s.",
				"4. If the front door will not lock, do not force it.",
				"   Tell somebody and go home the back way.",
			}, {
				"Counter.",
				"",
				"Nothing about a customer goes on this machine. Not",
				"a name, not a number, not a note about either. The",
				"book is the record and the book stays behind the",
				"counter.",
				"",
				"Everything anybody has ever got in trouble for here",
				"began with somebody thinking a computer was a quiet",
				"place to write something down.",
			}) },
		} },
	},
	bin = {
		{ script = "audit.sh" },
		{ script = "total.sh" },
		{ script = "lockup.sh" },
	},
	logs = {
		"login: failed login on console",
		"login: failed login on console",
		"su: authentication failure",
		"login: root logged in on console",
		"kernel: fd0 write protected",
		"shutdown: halt by root",
	},

	history = {
		"cat audit.txt",
		"sh bin/audit.sh accounts.dat checking",
		"sh bin/total.sh accounts.dat 4",
		"cat accounts.dat",
		"sh bin/lockup.sh door0 lock0",
		"dev door",
		"crontab -l",
		"df",
	},
	lockup = "sh bin/lockup.sh door0 lock0",
	draft = three({
		"To the district office.",
		"",
		"I am asking, in writing, what this branch is supposed",
		"to do with a vault that cannot be opened by anybody",
		"who is still coming to work. There are two of us who",
		"know the procedure and neither of us",
	}, {
		"Note for the examiner, whenever he next gets here.",
		"",
		"The figures are right and they are in cents. What is",
		"not right is the number of accounts that have been",
		"emptied to the last penny in four days. I have",
		"listed them below and the pattern is",
	}, {
		"{staff2} --",
		"",
		"If I am not here on Monday the procedure is in",
		"audit.txt and the door is in vault.txt and neither of",
		"them is difficult. What is difficult is the part",
		"nobody wrote down, which is",
	}),
	mail = {
		{
			{ to = "owner", from = "the district office", subj = "the examiner",
				back = 5, hour = 9, min = 10, body = {
					"He wants the figures read out to him a line at a",
					"time, the way he always does. Have the machine up",
					"and the disk in the drive before he sits down.",
				} },
			{ to = "owner", from = "the district office", subj = "cash",
				back = 3, hour = 11, min = 35, body = {
					"There is no delivery this week and there may not be",
					"one next week. Do not say so at the counter.",
				} },
			{ to = 2, from = "knox!bcampbell", subj = "not in",
				back = 2, hour = 7, min = 50, body = {
					"I am at my mother's and I cannot get back. I am",
					"sorry to do this to you on a Thursday.",
				} },
			{ to = "owner", from = "the district office", subj = "(no subject)",
				back = 0, hour = 6, min = 15, body = {
					"Secure the vault and leave. Nobody from this office",
					"is coming and nobody is being sent.",
				} },
		},
		{
			{ to = "owner", from = "cerosec!support", subj = "ticket 502",
				back = 5, hour = 14, min = 5, body = {
					"Your machine will not boot because the system on the",
					"disk is gone, not because the disk is. The firmware",
					"repair puts it back and leaves /home alone.",
				} },
			{ to = "owner", from = "the district office", subj = "the audit",
				back = 4, hour = 10, min = 20, body = {
					"Postponed. Not cancelled, postponed, and I want the",
					"two commands in audit.txt to still work when he does",
					"come.",
				} },
			{ to = "owner", from = "county!clerk", subj = "businesses",
				back = 1, hour = 12, min = 40, body = {
					"Premises within the affected area are to be secured",
					"and closed. Cash handling businesses are asked to",
					"telephone this office first. Nobody answers it.",
				} },
			{ to = 3, from = "knox!bcampbell", subj = "the counter",
				back = 0, hour = 5, min = 30, body = {
					"Do not open the front. There were four people on the",
					"step when I drove past at five and they were not",
					"queuing.",
				} },
		},
		{
			{ to = "owner", from = "the district office", subj = "1044",
				back = 5, hour = 8, min = 45, body = {
					"The account at nought has been at nought since",
					"March. Leave it open. He comes in on the first of",
					"the month and he is somebody's father.",
				} },
			{ to = 2, from = "the branch manager", subj = "the door",
				back = 3, hour = 17, min = 55, body = {
					"Read vault.txt before Friday. The script stops and",
					"tells you when the door did not come to, and last",
					"month it told me twice and I did not read it.",
				} },
			{ to = "owner", from = "wknx!news", subj = "a statement",
				back = 1, hour = 15, min = 25, body = {
					"We are asking every business on the square for one",
					"line about opening hours. One line, before six.",
				} },
			{ to = "owner", from = "the district office", subj = "are you open",
				back = 0, hour = 7, min = 0, body = {
					"Is the branch open. Is anybody in it. This is the",
					"third time I have asked this morning.",
				} },
		},
	},
}

CeroSecContent.PROFILES.store = {
	host = "till",
	motd = table.concat({
		"Back office. If you are not on the schedule then you",
		"are not supposed to be back here.",
	}, "\n"),
	root = true,
	accounts = {
		{ pass = true, admin = true, files = {
			{ path = "inventory.txt", texts = three({
				"What is on the floor, counted the day before the",
				"road shut. Anything not on this list went out the",
				"door in the first three days and is not coming back.",
				"",
				"  nails 3in      4 boxes",
				"  rope 50ft      2",
				"  lamp oil       11 tins",
				"  tarp 8x10      none",
				"  batteries      none",
				"  padlock        1, the good one",
				"",
				"Prices are in prices.txt and they are in cents.",
				"The machine adds the column up:",
				"",
				"  sh ~/bin/total.sh prices.txt 2",
			}, {
				"Counted by hand, twice, because the first count was",
				"wrong and I am not signing a wrong one.",
				"",
				"  nails 3in      1 box, opened",
				"  rope 50ft      none",
				"  lamp oil       3 tins",
				"  tarp 8x10      6",
				"  batteries      none, and none coming",
				"  padlock        none. Somebody took the good one.",
				"",
				"prices.txt is in cents. To add the column:",
				"",
				"  sh ~/bin/total.sh prices.txt 2",
			}, {
				"The floor, as of this morning.",
				"",
				"  nails 3in      7 boxes",
				"  rope 50ft      1",
				"  lamp oil       none",
				"  tarp 8x10      2, both torn",
				"  batteries      none",
				"  padlock        3",
				"",
				"Lamp oil and batteries went in one afternoon and",
				"there is no point writing them on the order sheet",
				"again. Nobody is filling an order sheet.",
				"",
				"  sh ~/bin/total.sh prices.txt 2",
			}) },
			{ path = "prices.txt", text = CeroSecContent.DATA["prices.txt"],
				extra = {
					{ "work gloves:550", "kerosene lamp:1875" },
					{ "hose 25ft:990", "duct tape:325", "wheelbarrow:4250" },
					{ "shovel:1450" },
				} },
			{ path = "closing.txt", texts = three({
				"Closing up, in this order, every night:",
				"",
				"  sh ~/bin/lights.sh light0 light1",
				"  sh ~/bin/lockup.sh door0 lock0",
				"",
				"light0 is the floor and light1 is the sign. The",
				"front door is door0. The back door is not on the",
				"computer at all -- do that one by hand and pull it",
				"to you until it clicks.",
			}, {
				"Closing. Lights first, then the door, and never the",
				"other way round: you cannot see the door in the dark",
				"and you will bolt it on the catch.",
				"",
				"  sh ~/bin/lights.sh light0 light1",
				"  sh ~/bin/lockup.sh door0 lock0",
				"",
				"light0 floor. light1 sign. door0 front.",
				"",
				"The back door is iron and is nobody's computer. Pull",
				"it until it clicks and then pull it again.",
			}, {
				"{owner}: closing up.",
				"",
				"  sh ~/bin/lights.sh light0 light1",
				"  sh ~/bin/lockup.sh door0 lock0",
				"",
				"The machine does the nine o'clock lights on its own",
				"whether anybody is here or not, so do not be",
				"surprised in the back room. The bolt it does not do",
				"on its own, which is why the second line is here.",
				"",
				"Back door by hand. It has never been on anything.",
			}) },
		}, cron = { "0 21 * * * sh $HOME/bin/lights.sh light0 light1" } },
		{ pass = false, files = {
			{ path = "note.txt", texts = three({
				"The number for the padlock on the gate is not",
				"written down anywhere and it is not going to be.",
				"Ask me, or ask whoever is on after me.",
			}, {
				"Three things and then I am going home.",
				"",
				"The gate padlock number is not on this machine and",
				"will not be. Ask {staff1}.",
				"",
				"The till tape is behind the register, not in here.",
				"",
				"Whoever keeps switching the sign on at six in the",
				"morning: it is on the computer now. Stop.",
			}, {
				"Left open so that anybody on shift can use it.",
				"",
				"Nothing on this account is worth a password. The",
				"gate number is in my head, the orders are on paper",
				"and the money is not here at night.",
			}) },
		} },
	},
	bin = {
		{ script = "total.sh" },
		{ script = "lights.sh" },
		{ script = "lockup.sh" },
	},
	logs = {
		"login: root logged in on console",
		"cron: lights out",
		"login: root logged in on console",
		"cron: lights out",
		"login: failed login on console",
		"cron: no such device: light1",
	},

	history = {
		"cat inventory.txt",
		"edit inventory.txt",
		"cat prices.txt",
		"sh bin/total.sh prices.txt 2",
		"sh bin/lights.sh light0 light1",
		"sh bin/lockup.sh door0 lock0",
		"dev light",
		"cat closing.txt",
		"crontab -l",
	},
	lockup = "sh bin/lockup.sh door0 lock0",
	draft = three({
		"Sign for the front window, and I will write it out",
		"properly on card.",
		"",
		"NO LAMP OIL. NO BATTERIES. NO TARPS. PLEASE DO NOT",
		"ASK WHEN, BECAUSE I DO NOT",
	}, {
		"Order sheet, and I know there is nobody to send it to.",
		"",
		"  lamp oil        as much as there is",
		"  batteries       every size, any make",
		"  rope            50ft, ten of them",
		"  padlocks        all of them",
		"",
		"I have telephoned the depot nine times. The last",
		"time it",
	}, {
		"To whoever opens up after me.",
		"",
		"The float is not in the till and it is not in the",
		"safe. It is in the third tin on the shelf above the",
		"sink, and I am writing that here because I may not",
		"be the one who",
	}),
	mail = {
		{
			{ to = "owner", from = "the depot", subj = "your order",
				back = 5, hour = 9, min = 30, body = {
					"Lamp oil is on the truck for Thursday. Batteries are",
					"not and will not be. Do not ask about tarps.",
				} },
			{ to = "owner", from = "knox!cdavis", subj = "Saturday",
				back = 3, hour = 18, min = 10, body = {
					"I can do Saturday but not Sunday. My brother has the",
					"car and my brother has gone to Louisville.",
				} },
			{ to = 2, from = "the manager", subj = "the sign",
				back = 2, hour = 6, min = 45, body = {
					"The sign is on the computer at nine at night. If you",
					"find it off in the morning, that is the computer and",
					"not you.",
				} },
			{ to = "owner", from = "the depot", subj = "(no subject)",
				back = 0, hour = 5, min = 20, body = {
					"There is no truck Thursday. There is no truck. The",
					"yard is shut and I am telephoning from my house.",
				} },
		},
		{
			{ to = "owner", from = "county!clerk", subj = "prices",
				back = 5, hour = 11, min = 15, body = {
					"Retailers within the affected area are reminded that",
					"prices posted before the notice are the prices that",
					"apply. Complaints have been received.",
				} },
			{ to = "owner", from = "the depot", subj = "credit",
				back = 4, hour = 13, min = 40, body = {
					"Your account is clear and I have put you first on",
					"the list for whatever comes in. That is not a",
					"promise, it is an order of names.",
				} },
			{ to = "owner", from = "knox!cdavis", subj = "the padlock",
				back = 2, hour = 8, min = 25, body = {
					"Somebody has had the good one off the gate. I did",
					"not write the number down anywhere, so it is not",
					"that.",
				} },
			{ to = "owner", from = "knox!cdavis", subj = "not coming in",
				back = 0, hour = 6, min = 30, body = {
					"I am not coming in and I would not open if I were",
					"you. There were people at the window at four this",
					"morning and they were not looking at the window.",
				} },
		},
		{
			{ to = "owner", from = "cerosec!support", subj = "your enquiry",
				back = 5, hour = 10, min = 50, body = {
					"The disk is 65536 bytes and always was. df will show",
					"you. A floppy holds 4096 and there is no charge for",
					"a box of them if you buy the drive belt from us.",
				} },
			{ to = "owner", from = "the depot", subj = "counted?",
				back = 3, hour = 15, min = 5, body = {
					"Send me a count of what is on the floor, not what is",
					"on the shelf card. There is a difference and we both",
					"know there is a difference.",
				} },
			{ to = 2, from = "wknx!news", subj = "opening hours",
				back = 1, hour = 12, min = 20, body = {
					"One line about your hours, before six, and we will",
					"read it at noon tomorrow.",
				} },
			{ to = "owner", from = "the depot", subj = "are you there",
				back = 0, hour = 4, min = 50, body = {
					"Answer if you are there. I have nine shops on this",
					"list and you are the seventh I have written to this",
					"morning.",
				} },
		},
	},
}

CeroSecContent.PROFILES.school = {
	host = "bell",
	motd = table.concat({
		"KNOX COUNTY SCHOOLS -- office terminal",
		"The grades are on this machine. Any student found at",
		"this keyboard goes home for the week.",
	}, "\n"),
	root = true,
	accounts = {
		{ pass = true, admin = true, files = {
			{ path = "grades.txt", texts = three({
				"Fourth period, term ending. Numbers only -- the",
				"names are in the paper file in the cabinet, which",
				"is where they are staying.",
				"",
				"  1104  B",
				"  1109  C",
				"  1112  A",
				"  1118  incomplete",
				"  1121  B",
				"  1127  incomplete",
				"",
				"Two incompletes. Both were absent all week and",
				"neither house answers the telephone.",
			}, {
				"Second period. Student numbers, and only student",
				"numbers: the names live in the cabinet and a machine",
				"anybody can sit down at is not a cabinet.",
				"",
				"  2201  A",
				"  2204  B",
				"  2208  B",
				"  2213  D, and he knows why",
				"  2216  A",
				"  2219  withdrawn",
				"  2224  incomplete",
				"",
				"2219 moved in May. 2224 has not been in since the",
				"4th and the office has stopped ringing the house.",
			}, {
				"Sixth period, final, and this is the last one I am",
				"putting on the computer.",
				"",
				"  3302  C",
				"  3305  B",
				"  3311  A",
				"  3314  C",
				"  3318  incomplete",
				"  3320  incomplete",
				"  3321  incomplete",
				"",
				"Three incompletes out of seven. I am not going to",
				"write down why. Everybody in this building knows why.",
			}) },
			{ path = "bells.txt", texts = three({
				"The bells are on a clockwork timer in the boiler",
				"room. The lights are on this machine. They are not",
				"the same thing and the timer does not care what the",
				"computer thinks.",
				"",
				"  sh ~/bin/lights.sh light0 light1",
				"",
				"That is the corridor and the gymnasium. Every",
				"classroom is a switch on the wall, as it always was.",
			}, {
				"Bells: boiler room, clockwork, a key on a nail.",
				"Lights: this machine. Nobody has ever managed to",
				"keep those two facts apart for a whole term.",
				"",
				"  sh ~/bin/lights.sh light0 light1",
				"",
				"light0 corridor, light1 gymnasium. The machine does",
				"them at ten at night by itself.",
				"",
				"If the bells are wrong, it is the timer, and the",
				"timer is a man with a screwdriver and not a command.",
			}, {
				"For {staff2}, who asked why the computer will not fix",
				"the bells.",
				"",
				"Because the bells are a clock with gears in it in the",
				"boiler room, and there is no wire between that room",
				"and this one. The computer has the corridor and the",
				"gymnasium lights and nothing else in the building.",
				"",
				"  sh ~/bin/lights.sh light0 light1",
				"",
				"Classroom switches are switches. They are fine.",
			}) },
		}, cron = { "0 22 * * * sh $HOME/bin/lights.sh light0 light1" } },
		{ pass = true, files = {
			{ path = "detention.txt", texts = three({
				"Detention, Friday, two of them.",
				"",
				"I am not writing the names in here. The last time I",
				"did, one of the two read it off this screen over my",
				"shoulder while I was typing it.",
				"",
				"Ask me. I remember.",
			}, {
				"Friday. Three.",
				"",
				"No names on this machine. The office is a corridor",
				"with a door that does not shut and a screen that",
				"faces it, and I have learned that twice.",
				"",
				"The list is in my drawer, in pencil, and it is short.",
			}, {
				"Nobody is in detention this week and nobody is going",
				"to be.",
				"",
				"Half the register is empty, two of the staff are not",
				"coming in, and I am not keeping a boy behind for",
				"being late to a school that is barely open.",
				"",
				"{staff1} disagrees. {staff1} can write his own file.",
			}) },
		} },
		{ pass = false, files = {
			{ path = "library.txt", texts = three({
				"Books out and not back, by number. The names are in",
				"the card tray where they belong.",
				"",
				"  0411  since March",
				"  0455  since March",
				"  0502  since April, and it is the atlas",
				"",
				"Three in a term is not bad. The atlas is the one I",
				"would like back.",
			}, {
				"The tray is the record. This is only my list of what",
				"has been out longest.",
				"",
				"  1120  the county history, since February",
				"  1204  since April",
				"  1233  since May",
				"",
				"Nobody is fined anything. They are books.",
			}, {
				"Out and not back. I have stopped counting the days.",
				"",
				"  0388",
				"  0412",
				"  0455",
				"  0501",
				"  0502",
				"",
				"If somebody comes in with an armful of them, take",
				"them and say thank you and do not ask anything.",
			}) },
		} },
	},
	bin = {
		{ script = "lights.sh" },
		{ script = "check.sh", chance = 70 },
	},
	logs = {
		"login: failed login on console",
		"login: failed login on console",
		"login: failed login on console",
		"useradd: account added",
		"login: root logged in on console",
		"shutdown: halt by root",
	},

	history = {
		"cat grades.txt",
		"edit grades.txt",
		"cat bells.txt",
		"sh bin/lights.sh light0 light1",
		"dev light",
		"sh bin/check.sh door0",
		"crontab -l",
		"sudo cat /var/log/messages",
	},
	lockup = "sh bin/lights.sh light0 light1",
	draft = three({
		"To the parents of the fourth period.",
		"",
		"Term ends on Friday whatever else happens, and the",
		"marks will go out on Friday. What I cannot tell you is",
		"whether there is going to be a",
	}, {
		"Notice for the door.",
		"",
		"THE SCHOOL IS CLOSED UNTIL FURTHER NOTICE. THIS IS THE",
		"COUNTY'S DECISION AND NOT THIS OFFICE'S. IF YOUR CHILD",
		"IS INSIDE THE BUILDING",
	}, {
		"Register, and I am keeping it here because the paper",
		"one is in the hall and the hall is",
		"",
		"Monday   19 of 31",
		"Tuesday  14",
		"Wednesday 9",
		"Thursday  4, and two of those were",
	}),
	mail = {
		{
			{ to = "owner", from = "county!schools", subj = "term marks",
				back = 5, hour = 9, min = 20, body = {
					"By student number and not by name, the way it has",
					"been since the year before last. Nothing with a name",
					"in it comes off that machine.",
				} },
			{ to = 2, from = "knox!mgreen", subj = "Friday",
				back = 3, hour = 16, min = 30, body = {
					"I cannot take the detention on Friday. I am not",
					"going to be in the building on Friday and I think",
					"you know why.",
				} },
			{ to = "owner", from = "county!schools", subj = "closure",
				back = 1, hour = 7, min = 40, body = {
					"All county schools are closed from today. Staff are",
					"not required to attend. Nobody is to be left in a",
					"building alone.",
				} },
			{ to = "owner", from = "knox!mgreen", subj = "1118 and 1127",
				back = 0, hour = 6, min = 10, body = {
					"I went to both houses. Nobody at either. The doors",
					"were open at the second one. What do I do with that.",
				} },
		},
		{
			{ to = "owner", from = "county!schools", subj = "the boiler",
				back = 5, hour = 11, min = 5, body = {
					"The bell timer is on the same key as the boiler and",
					"the key is on a nail. That is the whole maintenance",
					"arrangement for this building and it always was.",
				} },
			{ to = "owner", from = "cerosec!support", subj = "your enquiry",
				back = 4, hour = 14, min = 50, body = {
					"The computer cannot reach the bells. There is no wire",
					"between that room and this one, and no program can",
					"make one. Corridor and gymnasium lights only.",
				} },
			{ to = 3, from = "knox!agarcia", subj = "the atlas",
				back = 2, hour = 13, min = 15, body = {
					"0502 is out with a boy who has not been in since the",
					"4th. Leave it on the list. It is a book.",
				} },
			{ to = "owner", from = "county!schools", subj = "(no subject)",
				back = 0, hour = 5, min = 45, body = {
					"Do not open the building today. Do not go in to lock",
					"it. Is there anybody reading this who is inside a",
					"school right now.",
				} },
		},
		{
			{ to = "owner", from = "wknx!news", subj = "closures",
				back = 5, hour = 8, min = 30, body = {
					"We read the school closures at seven and at noon. If",
					"yours is shutting, tell us before six or we will",
					"read yesterday's list again.",
				} },
			{ to = "owner", from = "county!schools", subj = "attendance",
				back = 3, hour = 10, min = 25, body = {
					"Send the week's numbers and not the week's excuses.",
					"We are counting children and not reasons.",
				} },
			{ to = 2, from = "the head teacher", subj = "no names",
				back = 2, hour = 7, min = 55, body = {
					"I read your detention file over your shoulder from",
					"the corridor. So can a boy. Take the names out.",
				} },
			{ to = "owner", from = "knox!agarcia", subj = "the gymnasium",
				back = 0, hour = 4, min = 40, body = {
					"There are people in the gymnasium. The doors were",
					"locked last night and they are not locked now and I",
					"am not going in there on my",
				} },
		},
	},
}

CeroSecContent.PROFILES.clinic = {
	host = "ward",
	motd = table.concat({
		"Nurses station.",
		"Everything on this machine is about a person. Log",
		"out when you stand up.",
	}, "\n"),
	root = true,
	accounts = {
		{ pass = true, admin = true, files = {
			{ path = "patients.txt", text = CeroSecContent.DATA["patients.txt"],
				extra = {
					{ "115:a:waiting on a bed" },
					{ "103:b:for discharge", "117:a:two more days" },
					{ "109:a:transferred out", "110:a:waiting on a bed",
						"118:b:for discharge" },
				} },
			{ path = "rounds.txt", texts = three({
				"Rounds, in room order. The machine sorts them so",
				"nobody has to read my handwriting:",
				"",
				"  sh ~/bin/rounds.sh patients.txt",
				"",
				"Column one is the room, column two is the ward and",
				"column three is what has to happen next.",
				"",
				"NOTHING MEDICAL GOES IN THIS FILE. That is the",
				"chart, and the chart stays on the trolley.",
			}, {
				"How the round list is made, for whoever is on nights.",
				"",
				"  sh ~/bin/rounds.sh patients.txt",
				"",
				"That prints the rooms in order and nothing else. It",
				"is the order to walk in, not a list of people.",
				"",
				"Room, ward, what happens next. Three columns and no",
				"fourth. Anything clinical is on the chart on the",
				"trolley and it has never been in here.",
				"",
				"The machine mails me the list at seven every day.",
			}, {
				"{staff2}, {staff3}: the round list.",
				"",
				"  sh ~/bin/rounds.sh patients.txt",
				"",
				"Rooms in order. Walk it in that order and you will",
				"not cross the corridor nine times.",
				"",
				"Three columns: room, ward, next thing. If you find",
				"yourself wanting a fourth, you want the chart, and",
				"the chart is on the trolley where it lives.",
			}) },
		}, cron = { "0 7 * * * sh $HOME/bin/rounds.sh $HOME/patients.txt" } },
		{ pass = false, files = {
			{ path = "supplies.txt", texts = three({
				"What we are out of:",
				"",
				"  saline, everything above 500ml",
				"  gloves, small",
				"  the good tape",
				"",
				"Ordered a week ago. Nobody has telephoned back and",
				"the switchboard rings out now.",
			}, {
				"Out, short, and not coming.",
				"",
				"  saline          none of any size",
				"  gloves          large only",
				"  tape            none",
				"  the blue trays  two, and one is cracked",
				"",
				"Two orders in, no answer to either. The number for",
				"the depot rings and rings.",
			}, {
				"Supplies. I am writing it down so that the next",
				"person does not spend an hour looking.",
				"",
				"There is nothing in the store room. Not low. Nothing.",
				"",
				"What is left is in the two cupboards by the sluice",
				"and on the second trolley, and {staff1} has the key",
				"to the second cupboard.",
			}) },
		} },
		{ pass = true, files = {
			{ path = "nights.txt", texts = three({
				"Nights, and the two things nobody tells you.",
				"",
				"The corridor lights are on this machine and the ward",
				"lights are not. Do not switch anything off looking",
				"for the corridor.",
				"",
				"And the telephone at this desk rings for the whole",
				"floor. Answer it even if you are in the middle of",
				"something, because nobody else will.",
			}, {
				"For whoever is on tonight.",
				"",
				"Two of us. That is not a mistake on the board, it is",
				"two of us.",
				"",
				"The list the machine mails at seven is the round",
				"list and it is right. Walk it in the order it is in.",
				"",
				"If somebody comes to the doors, do not open them on",
				"your own. Find {staff1} first. That is not my rule.",
			}, {
				"Nights. Read once, then put it back.",
				"",
				"  the corridor lights are the computer's",
				"  the ward lights are the switch by the door",
				"  the telephone is the whole floor's",
				"",
				"And this, which is new: nobody goes out to the car",
				"park after dark, for any reason, alone. In writing",
				"because two people have argued with me about it.",
			}) },
		} },
	},
	bin = {
		{ script = "rounds.sh" },
		{ script = "locks.sh", chance = 60 },
		{ script = "check.sh", chance = 60 },
	},
	logs = {
		"login: root logged in on console",
		"cron: rounds mailed",
		"login: failed login on console",
		"cron: rounds mailed",
		"kernel: hda 82 percent full",
		"cron: rounds mailed",
	},

	history = {
		"sh bin/rounds.sh patients.txt",
		"cat patients.txt",
		"edit patients.txt",
		"cat rounds.txt",
		"sh bin/locks.sh lock lock0",
		"dev lock",
		"crontab -l",
		"cat supplies.txt",
	},
	lockup = "sh bin/locks.sh lock lock0",
	draft = three({
		"To the second floor, and I will bring it up myself if",
		"the telephone is still doing what it is doing.",
		"",
		"I have four beds and eleven people who need one. I am",
		"not asking you to find seven beds. I am asking you to",
		"tell me, in one sentence, who",
	}, {
		"Handover, nights.",
		"",
		"Two of us. The round list is in the mail at seven and",
		"it is right. Rooms in order. What is not on the list",
		"is that 106 is not waiting on a bed any more and",
		"nobody has",
	}, {
		"Order, urgent, and I know that word has stopped",
		"meaning anything.",
		"",
		"  saline, every size",
		"  gloves, small and medium",
		"  tape",
		"",
		"Nine days. Two orders. No answer to either. If this",
		"one is also not",
	}),
	mail = {
		{
			{ to = "owner", from = "the second floor", subj = "beds",
				back = 5, hour = 9, min = 40, body = {
					"We have none. If the sheriff telephones again tell",
					"them exactly what I told them at six this morning.",
				} },
			{ to = "owner", from = "the depot", subj = "your order",
				back = 4, hour = 11, min = 10, body = {
					"Saline is allocated and you are not on the",
					"allocation. I did not write that list and I cannot",
					"change it.",
				} },
			{ to = 2, from = "knox!sallen", subj = "tonight",
				back = 2, hour = 17, min = 20, body = {
					"I will be there but I will be late. The road past",
					"the church has something across it and I am going",
					"round by the mill.",
				} },
			{ to = "owner", from = "the second floor", subj = "(no subject)",
				back = 0, hour = 5, min = 25, body = {
					"Lock the ward doors. Both of them. I am not going to",
					"explain that in writing and you would not want me",
					"to.",
				} },
		},
		{
			{ to = "owner", from = "county!health", subj = "reporting",
				back = 5, hour = 8, min = 50, body = {
					"Numbers only, twice a day, to this address. Nothing",
					"clinical on a terminal and nothing clinical on a",
					"telephone. The chart stays on the trolley.",
				} },
			{ to = "owner", from = "the second floor", subj = "the round list",
				back = 3, hour = 7, min = 5, body = {
					"The seven o'clock list is the only thing arriving on",
					"time in this building. Whoever set that up, thank",
					"you.",
				} },
			{ to = 3, from = "knox!sallen", subj = "the sluice cupboard",
				back = 1, hour = 15, min = 35, body = {
					"The second one has the last of the tape in it and",
					"the key is with whoever is senior. That is you",
					"tonight.",
				} },
			{ to = "owner", from = "county!health", subj = "do not transfer",
				back = 0, hour = 6, min = 0, body = {
					"No transfers out of the affected area. None. Every",
					"receiving hospital has been told the same thing and",
					"none of them is answering either.",
				} },
		},
		{
			{ to = "owner", from = "the second floor", subj = "112",
				back = 5, hour = 10, min = 15, body = {
					"For discharge, and there is nobody to discharge him",
					"to. His daughter is in Louisville and the road is",
					"shut. Leave him where he is.",
				} },
			{ to = "owner", from = "wknx!news", subj = "advice",
				back = 3, hour = 12, min = 45, body = {
					"We are asked to read out what the public should do.",
					"We would rather read out what you actually say than",
					"what the county sent us.",
				} },
			{ to = 2, from = "the day sister", subj = "the car park",
				back = 1, hour = 21, min = 30, body = {
					"Nobody goes out there alone after dark. That is not",
					"the county's rule and it is not the hospital's, it",
					"is mine, and I will not be argued with about it.",
				} },
			{ to = "owner", from = "the second floor", subj = "are you still there",
				back = 0, hour = 4, min = 55, body = {
					"Two of my staff have gone and I do not mean gone",
					"home. Is there anybody at that station.",
				} },
		},
	},
}

CeroSecContent.PROFILES.radio = {
	host = "studio",
	motd = table.concat({
		"Studio B.",
		"Nothing goes out on the air off this machine. It",
		"keeps the log and the sheet and that is all it has",
		"ever done.",
	}, "\n"),
	root = true,
	accounts = {
		{ pass = true, admin = true, files = {
			{ path = "sched.txt", text = CeroSecContent.DATA["sched.txt"],
				extra = {
					{ "23 the network feed, nobody in the building" },
					{ "03 records, unattended", "23 the network feed" },
					{ "00 the state frequency, relayed", "05 the farm report again" },
				} },
			{ path = "notes.txt", texts = three({
				"The sheet is sched.txt: the hour, then what goes out",
				"in it. The machine reads the clock and mails me the",
				"line for the hour it is:",
				"",
				"  sh ~/bin/announce.sh sched.txt",
				"",
				"It is on cron at five past every hour. If the mail",
				"stops then either the clock is wrong or somebody has",
				"edited the sheet into something it cannot read.",
				"",
				"Keep the hours two digits. 06, never 6.",
			}, {
				"How the sheet works, and the one way to break it.",
				"",
				"sched.txt is an hour and then what is on in it. The",
				"machine looks at its own clock and prints the line",
				"for the hour it is now:",
				"",
				"  sh ~/bin/announce.sh sched.txt",
				"",
				"Five past the hour, every hour, on cron, into my",
				"mail. No mail means the sheet will not read, and the",
				"sheet will not read the moment somebody types 6 for",
				"six. It is 06. It has always been 06.",
			}, {
				"{staff2}: the sheet, since you are on Saturday.",
				"",
				"  sh ~/bin/announce.sh sched.txt",
				"",
				"That prints what is meant to be on the air right now",
				"according to the sheet. It is not the transmitter and",
				"it cannot put anything on the air -- nothing on this",
				"machine can, which is worth knowing.",
				"",
				"Two digits on every hour or the whole thing stops.",
			}) },
		}, cron = { "5 * * * * sh $HOME/bin/announce.sh $HOME/sched.txt" } },
		{ pass = false, files = {
			{ path = "readme.txt", texts = three({
				"If you are on at midnight and the tone is still on",
				"the state frequency, do not say so on the air. Say",
				"the time and the weather and put a record on.",
			}, {
				"For whoever is in the chair at midnight.",
				"",
				"If the state frequency is still a tone, that is not",
				"news and you are not to make it news. Time, weather,",
				"a record, and again in an hour.",
				"",
				"If somebody telephones the studio asking about the",
				"roads, tell them what the county told us and not one",
				"word past it.",
			}, {
				"Read before you open the microphone.",
				"",
				"We have three things to say and we say only those",
				"three: the time, the weather, and what the county",
				"has told us in the county's own words.",
				"",
				"Everything else is a rumour with a transmitter",
				"behind it. {staff1} put that on the wall in Studio A",
				"nine years ago and it has never been wrong.",
			}) },
		} },
	},
	bin = {
		{ script = "announce.sh" },
		{ script = "lights.sh", chance = 50 },
	},
	files = {
		-- What the station HEARD, which is the one file in the county that says
		-- what the rest of it sounded like. 644 and root's: a log of the air is
		-- not a secret, and somebody who gets onto this machine at all should be
		-- able to read it.
		--
		-- The other file that carries July in as many words, and for the reason the
		-- dispatch log does: it is a hand-kept log of particular nights. All three
		-- tellings end the same way, on nothing at all.
		{ path = "/var/log/heard", owner = "root", mode = 644,
			texts = three({
				"Jul 04 1150 the fire service, asking for help",
				"Jul 05 0940 a man reading a list of names, on 40m",
				"Jul 06 1815 the state frequency, a tone and nothing",
				"Jul 07 0300 somebody counting. Got to 60 and stopped",
				"Jul 08 1420 a woman west of here, asking for a doctor",
				"Jul 08 2200 the tone again",
				"Jul 09 0000 nothing on any of them",
			}, {
				"Jul 04 2015 two stations talking about the bridge",
				"Jul 05 1130 a net on 40m, eleven callsigns, then six",
				"Jul 06 0450 the same net, three callsigns",
				"Jul 06 1900 the state frequency went to a tone",
				"Jul 07 1240 somebody reading road numbers, twice",
				"Jul 08 0730 a man asking anybody to answer. Nobody",
				"Jul 08 2340 the tone",
				"Jul 09 0130 the tone stopped. Nothing since.",
			}, {
				"Jul 04 0900 the county board, live, as usual",
				"Jul 05 1615 a woman north of the river, clear as day",
				"Jul 06 1100 her again, weaker",
				"Jul 07 0215 a carrier with nobody on it, four hours",
				"Jul 07 2100 the state frequency, a tone",
				"Jul 08 1005 three stations at once, all of them fast",
				"Jul 08 2250 one station, counting, in a whisper",
				"Jul 09 0300 I have listened to all of it twice",
			}) },
	},
	logs = {
		"login: root logged in on console",
		"cron: announce mailed",
		"cron: announce mailed",
		"login: failed login on console",
		"cron: announce mailed",
		"kernel: radio0 present",
	},

	history = {
		"sh bin/announce.sh sched.txt",
		"cat sched.txt",
		"edit sched.txt",
		"cat notes.txt",
		"cat /var/log/heard",
		"cu -l /dev/radio0",
		"crontab -l",
		"dev",
	},
	draft = three({
		"Copy for the top of the hour, and I am not reading",
		"this until somebody senior has seen it.",
		"",
		"The county has asked us to say that the roads are",
		"closed as a precaution. We have been saying that for",
		"three days. What I would like to say instead is",
	}, {
		"Log note, for whoever comes in.",
		"",
		"The state frequency has been a tone since Tuesday",
		"evening. Not silence, a tone. I have written down",
		"every hour I have checked it and the list is in",
		"/var/log/heard. What I have not written down is",
	}, {
		"Sheet for tomorrow, if there is a tomorrow on the air.",
		"",
		"  06 the weather, read twice",
		"  09 nothing. Records.",
		"  12 the county notice, word for word",
		"  15 records",
		"  18 the county notice again",
		"",
		"I have taken the swap shop off because",
	}),
	mail = {
		{
			{ to = "owner", from = "county!clerk", subj = "read at noon",
				back = 5, hour = 9, min = 0, body = {
					"The following is to be read at noon and at six, in",
					"these words: the closures are a precaution and there",
					"is no cause for alarm.",
				} },
			{ to = "owner", from = "the transmitter shack", subj = "the tone",
				back = 3, hour = 19, min = 25, body = {
					"It is not us. I have been up to the mast and it is",
					"not us. Whatever is on the state frequency is on the",
					"state frequency.",
				} },
			{ to = 2, from = "knox!rking", subj = "midnight",
				back = 2, hour = 22, min = 40, body = {
					"I can do midnight to six but I cannot do it twice.",
					"Somebody has to be in that chair on Friday and it",
					"cannot be me.",
				} },
			{ to = "owner", from = "county!clerk", subj = "(no subject)",
				back = 0, hour = 5, min = 50, body = {
					"Stop reading the noon notice. Do not read anything",
					"we sent you this week. Is there anybody still at",
					"the station.",
				} },
		},
		{
			{ to = "owner", from = "cerosec!support", subj = "the sheet",
				back = 5, hour = 13, min = 30, body = {
					"The program stops because an hour in your file is one",
					"digit. It has to be 06 and not 6. That is the whole",
					"fault and there is no charge for it.",
				} },
			{ to = "owner", from = "the transmitter shack", subj = "power",
				back = 4, hour = 6, min = 40, body = {
					"We have the generator and about two days of fuel for",
					"it. After that we are off the air and no amount of",
					"telephoning this shack will change it.",
				} },
			{ to = "owner", from = "knox!rking", subj = "the woman on 40m",
				back = 2, hour = 15, min = 15, body = {
					"She came up again at eleven and she is west of here,",
					"not north. Somebody should write that down properly",
					"and it should not be me at two in the morning.",
				} },
			{ to = "owner", from = "wknx!news", subj = "what do we say at six",
				back = 0, hour = 4, min = 30, body = {
					"Nobody has sent us anything since yesterday morning.",
					"I am going on at six with the time and the weather",
					"and a record unless somebody tells me otherwise.",
				} },
		},
		{
			{ to = "owner", from = "county!clerk", subj = "the board meeting",
				back = 5, hour = 10, min = 35, body = {
					"It sits at nine on Thursday and you may carry it",
					"live, as usual. Two of the members have said they",
					"will not be attending.",
				} },
			{ to = 2, from = "the station manager", subj = "the sheet",
				back = 3, hour = 18, min = 5, body = {
					"Two digits on every hour. If you edit it, read it",
					"back with the program before you go home, because",
					"the mail stopping is how I find out and I find out",
					"at five past.",
				} },
			{ to = "owner", from = "the transmitter shack", subj = "somebody counting",
				back = 1, hour = 3, min = 20, body = {
					"Third night. He gets to sixty and stops. It is on a",
					"frequency nobody licensed and I have stopped",
					"listening to it on purpose.",
				} },
			{ to = "owner", from = "knox!rking", subj = "I am not coming in",
				back = 0, hour = 5, min = 5, body = {
					"I am not coming in and I am telling you rather than",
					"just not arriving. Put a record on and lock the",
					"studio door behind you.",
				} },
		},
	},
}

CeroSecContent.PROFILES.military = {
	host = "post",
	motd = table.concat({
		"RESTRICTED. Authorised personnel only.",
		"Everything on this terminal is classified at the",
		"level of the operation it names.",
		"KEEP OUT.",
	}, "\n"),
	-- ROOT AND NOTHING ELSE, and it is the one profile with no ordinary account on
	-- it at all. A post did not hand out logins; a man sat down at it because he
	-- was allowed to be in the room. So there is no open account to walk in
	-- through and no note in anybody's pocket -- the only way in is the paper in
	-- the drawer, or the BIOS. What that costs is said in the manual, and it is
	-- the same cost every locked machine has.
	root = true,
	bin = {
		-- Nobody's ~/bin to put it in, so it goes where a machine's own local
		-- software went in 1993.
		{ script = "check.sh", to = "/usr/local/bin" },
	},
	cron = {
		{ to = "root", lines = { "0 * * * * sh /usr/local/bin/check.sh door0" } },
	},
	files = {
		{ path = "/root/memo-01.txt", owner = "root", mode = 600,
			texts = three({
				"MEMORANDUM 1 -- 4 July",
				"",
				"The line is the river to the west, the county road",
				"to the north and the rail bed to the east. Nothing",
				"on foot crosses it in either direction. Nothing.",
				"",
				"Vehicles are turned at the first checkpoint and are",
				"not to be searched at the second.",
			}, {
				"MEMORANDUM 1 -- 4 July",
				"",
				"The cordon as of this morning: the river west, the",
				"county road north, the rail bed east. It is not a",
				"fence and it is not going to be one. It is us.",
				"",
				"Nobody on foot crosses in either direction, and that",
				"includes people with papers. Turn vehicles at the",
				"first point and do not open them at the second.",
			}, {
				"MEMORANDUM 1 -- 4 July",
				"",
				"Boundaries: river, county road, rail bed. West,",
				"north, east.",
				"",
				"No foot traffic through, either way, no exceptions,",
				"and the word exceptions is in this memorandum",
				"because somebody asked. Vehicles turned at the first",
				"point, not searched at the second.",
				"",
				"Anybody who argues with a checkpoint is somebody",
				"else's problem and not the checkpoint's.",
			}) },
		{ path = "/root/memo-02.txt", owner = "root", mode = 600,
			texts = three({
				"MEMORANDUM 2 -- 6 July",
				"",
				"The line has moved twice in two days and both times",
				"we were told after the fact.",
				"",
				"Until somebody tells us otherwise, the line is where",
				"we are standing. The road south is open for us and",
				"for nobody else.",
			}, {
				"MEMORANDUM 2 -- 6 July",
				"",
				"Twice in two days the boundary has been redrawn and",
				"twice we have read about it afterwards.",
				"",
				"So: the boundary is where this post is standing. It",
				"will go on being where this post is standing until",
				"somebody with a name on it says otherwise in writing.",
				"",
				"The road south is ours. It is nobody else's.",
			}, {
				"MEMORANDUM 2 -- 6 July",
				"",
				"Two changes to the line in two days, both of them",
				"announced after they happened.",
				"",
				"I am done redrawing it. The line is here. The road",
				"south is open for us and closed to everybody, and",
				"the men are to be told that in those words so that",
				"nobody has to decide anything at three in the",
				"morning.",
			}) },
		{ path = "/root/memo-03.txt", owner = "root", mode = 600,
			texts = three({
				"MEMORANDUM 3 -- 8 July",
				"",
				"Two of the checkpoints did not report this morning.",
				"We are not to go and look. That order is in writing",
				"and this is the writing.",
				"",
				"If you are reading this and you are not one of us:",
				"the road south was open on the 8th of July. It will",
				"not be open now.",
			}, {
				"MEMORANDUM 3 -- 8 July",
				"",
				"Two points silent since before first light. We are",
				"not to send anybody to either of them. I have asked",
				"twice and the answer was the same twice, so it is",
				"written down here where it cannot be denied.",
				"",
				"To whoever finds this and is not one of us: on the",
				"8th of July the road south was open. Take that for",
				"what it is worth now, which may be nothing.",
			}, {
				"MEMORANDUM 3 -- 8 July",
				"",
				"Two checkpoints have not reported since last night",
				"and we are ordered not to go and find out why.",
				"",
				"I have put that order in this file rather than only",
				"in my own head, because a man is going to want to",
				"go, and he is going to be right, and the order will",
				"still be the order.",
				"",
				"Anybody reading this later: the road south was open",
				"on the 8th. Nothing here says it stayed open.",
			}) },
	},
	logs = {
		"login: root logged in on console",
		"login: root logged in on console",
		"login: failed login on console",
		"login: root logged in on console",
		"halt: system going down",
	},

	-- NEVER FOUND LOGGED IN, and it is the one profile that says so. A post was a
	-- room a man was let into, and he was relieved or he left; a terminal standing
	-- at somebody's prompt inside a cordon is a story about the wrong thing.
	session = false,
	history = {
		"cat /root/memo-01.txt",
		"cat /root/memo-02.txt",
		"cat /root/memo-03.txt",
		"edit /root/memo-03.txt",
		"sh /usr/local/bin/check.sh door0",
		"dev door",
		"crontab -l",
		"ls /root",
		"cat /var/log/messages",
	},
	draft = three({
		"MEMORANDUM 4 -- not issued",
		"",
		"Two checkpoints have been silent for a day and a half",
		"and the order not to go to them stands. I have put my",
		"objection in writing twice and this is the third. If",
		"anybody reads this after",
	}, {
		"SITUATION -- 0500",
		"",
		"Line held. Two points silent. No contact with",
		"battalion since the evening. Fuel for the generator",
		"about thirty hours at this rate. Ammunition is not the",
		"problem and I want that on the",
	}, {
		"To whoever holds this post next.",
		"",
		"The memoranda in /root are the orders as I received",
		"them and I have not edited one of them. What is not in",
		"them is what the men actually did, which was",
	}),
	mail = {
		{
			{ to = "root", from = "battalion", subj = "the ninth",
				back = 5, hour = 8, min = 15, body = {
					"Hold where you are. Do not withdraw and do not",
					"advance. Further orders follow.",
				} },
			{ to = "root", from = "battalion", subj = "the line",
				back = 3, hour = 14, min = 40, body = {
					"The boundary has been redrawn. You will be sent the",
					"new one when it is confirmed. Until then your",
					"boundary is the one you are standing on.",
				} },
			{ to = "root", from = "battalion", subj = "checkpoints",
				back = 1, hour = 6, min = 20, body = {
					"You will not send men to a point that has stopped",
					"reporting. This is not discretionary and it is not",
					"to be discussed with them.",
				} },
			{ to = "root", from = "battalion", subj = "(no subject)",
				back = 0, hour = 4, min = 45, body = {
					"Report strength. Report strength. Report strength.",
				} },
		},
		{
			{ to = "root", from = "battalion", subj = "vehicles",
				back = 5, hour = 10, min = 50, body = {
					"Turned at the first point. Not searched at the",
					"second. Nothing on foot in either direction and the",
					"word nothing is the word.",
				} },
			{ to = "root", from = "battalion", subj = "the road south",
				back = 4, hour = 17, min = 5, body = {
					"Open for you and for nobody else. You will not be",
					"told twice and you will not be told again.",
				} },
			{ to = "root", from = "the sheriff", subj = "our units",
				back = 2, hour = 11, min = 35, body = {
					"We have two vehicles that have not come back and",
					"both were last heard from inside your boundary. We",
					"are asking, not demanding.",
				} },
			{ to = "root", from = "battalion", subj = "hold",
				back = 0, hour = 5, min = 30, body = {
					"Hold. Nothing else in this message.",
				} },
		},
		{
			{ to = "root", from = "battalion", subj = "orders, 4 July",
				back = 5, hour = 7, min = 30, body = {
					"River west, county road north, rail bed east. The",
					"cordon is men and not wire. Do not improve it",
					"without authority.",
				} },
			{ to = "root", from = "county!clerk", subj = "civilians",
				back = 3, hour = 9, min = 55, body = {
					"This office has been asked eleven times today by",
					"people who want to reach relatives inside. We are",
					"telling them to stay where they are. Confirm that",
					"is still correct.",
				} },
			{ to = "root", from = "battalion", subj = "no relief",
				back = 1, hour = 20, min = 10, body = {
					"There is no relief coming tonight. Rest half your",
					"strength and hold with the other half.",
				} },
			{ to = "root", from = "the sheriff", subj = "anybody",
				back = 0, hour = 5, min = 0, body = {
					"Is there anybody at that post. We have nothing on",
					"the radio and nothing on the telephone and we are",
					"four men.",
				} },
		},
	},
}

CeroSecContent.PROFILES.cerosec = {
	host = "cerosec",
	motd = table.concat({
		"CeroSec Systems -- service department",
		"This is a customer machine on the bench. Whatever is",
		"on it belongs to whoever brought it in. Read the",
		"ticket before you touch the disk.",
	}, "\n"),
	root = true,
	accounts = {
		{ pass = true, admin = true, files = {
			{ path = "bench.txt", texts = three({
				"Whatever comes in, the same four things and in this",
				"order:",
				"",
				"  1. sh /usr/local/src/sweep.sh /   what is on it",
				"  2. last                           who used it",
				"  3. df                             room left",
				"  4. the BIOS, if it will not boot at all",
				"",
				"The library is /usr/local/src and every one of them",
				"is commented. Copy what you want into your own bin.",
				"Leave the originals where they are.",
			}, {
				"Bench procedure. Four commands before you open the",
				"case, every time, no exceptions for a machine you",
				"think you remember.",
				"",
				"  sh /usr/local/src/sweep.sh /",
				"  last",
				"  df",
				"  cat /var/log/messages",
				"",
				"What is on it, who used it, how full it is, what it",
				"says about itself. The BIOS repair is the fifth and",
				"only when the first four say the disk is the fault.",
				"",
				"/usr/local/src is the library. Copy, never edit.",
			}, {
				"For {staff2} and {staff3}, taped to the bench in",
				"Studio order because {owner} keeps moving it.",
				"",
				"  sh /usr/local/src/sweep.sh /",
				"  last",
				"  df",
				"",
				"Those three, written on the ticket, before anything.",
				"Half the machines that come in here are somebody's",
				"full disk and the customer has been told it is",
				"broken.",
				"",
				"The library in /usr/local/src is read-only by habit",
				"and not by mode. Keep the habit.",
			}) },
		} },
		-- NAMED, and for the reason the dispatch desk's is: a support line was
		-- answered by whoever picked it up, and the mailbox has to be findable by
		-- somebody who has never seen this machine. Open, deliberately: what is
		-- in it is a shelf of answers and not anybody's business.
		{ name = "support", pass = false, files = {
			{ path = "answers.txt", texts = three({
				"What people telephone about, and what to tell them.",
				"",
				"It will not take the disk. It is not formatted:",
				"  newfs /dev/fd0",
				"",
				"I have forgotten the password. Nobody here can tell",
				"them. Repair from the BIOS keeps /home.",
				"",
				"The lights will not come on. There is no module on",
				"the switch. That is an electrician, not us.",
				"",
				"It is slow. Something is running. ps, then kill.",
			}, {
				"The five calls, in the order we get them.",
				"",
				"1. The drive will not read the disk. It is a blank",
				"   disk. newfs /dev/fd0 and then mount it.",
				"2. Nobody knows the password. We cannot help and we",
				"   do not pretend to. The BIOS repair puts the system",
				"   back and leaves /home alone.",
				"3. The lights do nothing. There is no module on the",
				"   fitting. Electrician.",
				"4. It has got slow. ps. Something is running.",
				"5. The disk is full. It is 65536 bytes and it always",
				"   was. df, then a floppy.",
			}, {
				"Answers. Read this before you pick the telephone up",
				"and you will not have to put anybody on hold.",
				"",
				"  disk will not read     newfs /dev/fd0",
				"  lost the password      BIOS repair, /home is kept",
				"  lights do nothing      no module. Electrician.",
				"  gone slow              ps, then kill",
				"  disk full              df. It is 65536 bytes.",
				"",
				"Nobody at this company can read anybody's password",
				"off anything. Say so plainly. They always ask.",
			}) },
		} },
		{ pass = true, files = {
			{ path = "tickets.txt", texts = three({
				"On the bench, oldest first.",
				"",
				"  411  full disk. Customer says broken.",
				"  418  drive belt. Parts, two weeks, no chance.",
				"  423  works. Brought in twice. Works.",
				"",
				"423 goes back with a note this time and the note",
				"says what I tested and in what order.",
			}, {
				"Bench queue.",
				"",
				"  502  no boot. Disk. Repaired, /home kept.",
				"  505  modem. No dial tone at the customer and a",
				"       dial tone here. It is the line and not us.",
				"  509  keyboard, liquid. Not a repair.",
				"  512  full disk.",
				"",
				"Two full disks this month and both customers were",
				"told the machine was failing by somebody else.",
			}, {
				"What is on the bench and what I have stopped doing",
				"about it.",
				"",
				"  601  no boot, no spare disk in the building",
				"  604  full disk",
				"  607  full disk",
				"  611  came in on Monday, nobody has been back",
				"",
				"There are no parts coming. I have written that on",
				"every ticket so that it is on the ticket and not",
				"only in this file.",
			}) },
		} },
	},
	-- THE LIBRARY ITSELF, by reference, in the one place on any machine in the
	-- county where the whole of it stands together. Every entry is the same file
	-- the disks and the homes carry: one script, one copy (see the head of
	-- CeroSecContent.SCRIPTS).
	bin = {
		{ script = "lights.sh", to = "/usr/local/src" },
		{ script = "locks.sh", to = "/usr/local/src" },
		{ script = "lockup.sh", to = "/usr/local/src" },
		{ script = "check.sh", to = "/usr/local/src" },
		{ script = "audit.sh", to = "/usr/local/src" },
		{ script = "total.sh", to = "/usr/local/src" },
		{ script = "rounds.sh", to = "/usr/local/src" },
		{ script = "announce.sh", to = "/usr/local/src" },
		{ script = "sweep.sh", to = "/usr/local/src" },
		{ script = "log.sh", to = "/usr/local/src" },
		{ script = "guess.sh", to = "/usr/local/src" },
		{ script = "hangman.sh", to = "/usr/local/src" },
		{ script = "adventure.sh", to = "/usr/local/src" },
	},
	-- ROOT'S AND NOT THE OWNER'S, because nothing in the line names a home: the
	-- weekly sweep of /var is the machine's own housekeeping and runs whoever's
	-- desk the bench machine is this week.
	cron = {
		{ to = "root", lines = { "0 4 * * 0 sh /usr/local/src/sweep.sh /var" } },
	},
	files = {
		{ path = "/usr/local/src/CHANGES", owner = "root", mode = 644,
			texts = three({
				"CeroSec OS -- what changed, newest first.",
				"",
				"1.0  The shell learned pipes, cron and job control.",
				"     The floppy drive became a filesystem and not a",
				"     place to keep one file in.",
				"     hash became mkpasswd, because no Unix ever had",
				"     a command called hash.",
				"     call became cu -l /dev/radio0, because a TNC is",
				"     a box on a serial line and cu is how you reach",
				"     one.",
				"     write went away. Putting text in a file has",
				"     always been a redirection.",
				"",
				"0.9  /dev, and the building on the end of it.",
				"0.8  Accounts, groups and sudo, in that order.",
				"0.7  The first shell. There were no pipes in it.",
			}, {
				"CeroSec OS -- what changed, newest first. The",
				"bench copy, with the four names customers still type",
				"marked up the side.",
				"",
				"1.0  Pipes, cron, job control. The drive became a",
				"     filesystem.",
				"     hash      -> mkpasswd",
				"     call      -> cu -l /dev/radio0",
				"     readlink  -> ls -l, and read the arrow",
				"     write     -> echo text > file",
				"     restart   -> reboot",
				"",
				"0.9  /dev, and the building behind it.",
				"0.8  Accounts, groups, sudo.",
				"0.7  The first shell, with no pipes in it.",
				"0.6  The editor. Before that there was cat.",
			}, {
				"CeroSec OS -- what changed, newest first.",
				"",
				"1.0  The shell learned pipes, cron and job control,",
				"     and the floppy drive stopped being a place to",
				"     keep one file in.",
				"     Four commands were taken away and the four that",
				"     replace them are the ones Unix always had:",
				"     mkpasswd, cu, echo into a file, reboot.",
				"",
				"0.9  /dev.",
				"0.8  Accounts and sudo.",
				"0.7  A shell.",
				"",
				"Anybody who wants to know why a command went away",
				"can read the manual page for the one that replaced",
				"it. That is the whole of the answer and it is a",
				"better answer than this file is.",
			}) },
	},
	logs = {
		"login: root logged in on console",
		"cron: sweep ran",
		"login: root logged in on console",
		"newfs: fd0 relabelled",
		"login: support logged in",
		"cron: sweep ran",
	},

	history = {
		"sh /usr/local/src/sweep.sh /",
		"last",
		"df",
		"cat bench.txt",
		"ls /usr/local/src",
		"cat /usr/local/src/CHANGES",
		"newfs /dev/fd0",
		"mount /dev/fd0 /mnt",
		"ls /mnt",
		"umount /mnt",
		"mkpasswd",
	},
	draft = three({
		"To every customer with an open ticket.",
		"",
		"There are no parts coming. I am writing one letter and",
		"sending it to all of you rather than telling each of",
		"you a different story on the telephone. What we can",
		"still do is",
	}, {
		"Service note, for the file.",
		"",
		"Four machines in a fortnight with the same fault, and",
		"the fault is that the disk is 65536 bytes and the",
		"customer has been told by somebody else that it is",
		"broken. I want a one page sheet we can post out that",
		"says",
	}, {
		"Notice for the counter.",
		"",
		"THE SERVICE DEPARTMENT IS CLOSED. MACHINES ON THE",
		"BENCH MAY BE COLLECTED BY THE PERSON WHO BROUGHT THEM",
		"IN. WE CANNOT TELL YOU ANYBODY'S PASSWORD AND WE",
		"NEVER COULD. IF YOUR MACHINE",
	}),
	mail = {
		{
			{ to = "support", from = "a customer", subj = "no dial tone",
				back = 5, hour = 9, min = 45, body = {
					"Third week of this. The modem says NO DIAL TONE and",
					"the telephone on the same desk works perfectly.",
					"Somebody has to come out here.",
				} },
			{ to = "owner", from = "the parts desk", subj = "back order",
				back = 4, hour = 13, min = 20, body = {
					"Drive belts are four weeks and I would not believe",
					"four weeks. Nothing else on your list has a date",
					"against it at all.",
				} },
			{ to = "owner", from = "a customer", subj = "my password",
				back = 2, hour = 10, min = 5, body = {
					"I have been told by three people that you can read",
					"it off the disk. Please just tell me what it is.",
				} },
			{ to = "owner", from = "the parts desk", subj = "(no subject)",
				back = 0, hour = 6, min = 25, body = {
					"The warehouse is inside the line. Nothing is coming",
					"out of it and nobody is going into it. I am sorry.",
				} },
		},
		{
			{ to = "owner", from = "the parts desk", subj = "the quarter",
				back = 5, hour = 11, min = 30, body = {
					"Eleven machines on your bench and nine of them are",
					"waiting on us. Tell the customers whatever you have",
					"to tell them.",
				} },
			{ to = "support", from = "a customer", subj = "it will not take the disk",
				back = 4, hour = 15, min = 55, body = {
					"I have put four different floppies in it and it says",
					"the same thing about every one of them. They are",
					"brand new out of the box.",
				} },
			{ to = "owner", from = "the counter", subj = "ticket 611",
				back = 2, hour = 8, min = 10, body = {
					"Nobody has been back for it since Monday. Put it",
					"behind the counter with the ticket on it and do not",
					"take the disk out.",
				} },
			{ to = "owner", from = "the parts desk", subj = "the van",
				back = 1, hour = 16, min = 40, body = {
					"There is no van this week. If a customer needs his",
					"machine back he collects it, and he collects it",
					"before Friday.",
				} },
			{ to = "owner", from = "a customer", subj = "are you open",
				back = 0, hour = 5, min = 40, body = {
					"I drove to the square and the shutter is down. Is",
					"anybody reading this. My machine has my whole",
					"business on it.",
				} },
		},
		{
			{ to = "owner", from = "the parts desk", subj = "the library",
				back = 5, hour = 8, min = 20, body = {
					"Yes, put the whole of /usr/local/src on every bench",
					"machine. If a customer reads one of them and writes",
					"his own, that is the machine sold and not lost.",
				} },
			{ to = "support", from = "a customer", subj = "it is slow",
				back = 3, hour = 12, min = 0, body = {
					"It has been slow since Friday and it was not slow",
					"before Friday. I have not changed anything, which",
					"is what everybody says and is true.",
				} },
			{ to = "owner", from = "county!clerk", subj = "businesses",
				back = 1, hour = 14, min = 15, body = {
					"Premises within the affected area are to be secured",
					"and closed. Repair trades are not exempt and there",
					"is no permit scheme.",
				} },
			{ to = "owner", from = "a customer", subj = "my machine",
				back = 0, hour = 4, min = 35, body = {
					"Keep it. I am not coming back for it. If anybody at",
					"your company gets out of the county, take the disk",
					"out and",
				} },
		},
	},
}
