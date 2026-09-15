--
-- The self-test, and it is the only bench that runs where the mod does.
--
-- Every other bench in tests/ runs on lua5.1 on a developer's box. The game runs
-- Kahlua -- a Lua 5.1 interpreter written in Java, with its own standard library
-- -- and twice in one day that difference shipped a bug through a green suite:
-- `tonumber(s, 16)` answers nil there for every eight-digit hash from "80000000"
-- up (Integer.parseInt behind it), and the `%` OPERATOR is wrong once the
-- quotient reaches 2^31. Both were invisible to luac5.1, to a grep, and to ten
-- thousand green assertions.
--
-- So this file holds the ONE body of vectors, and three things run it:
--
--   tests/kahlua-probe.lua        prints it on lua5.1 and on the game's Kahlua
--                                and tests/kahlua-run.sh diffs the two outputs
--   tools/make-selftest-vectors.lua  runs it on lua5.1 -- the CANONICAL VM --
--                                and writes CeroSecSelfTestVectors.lua
--   CeroSecSelfTest.run()        runs it on whatever VM it finds itself on and
--                                compares every answer with those vectors
--
-- One body and not three copies, and that is the whole design: a vector table
-- written by hand beside a probe written by hand is two lists that drift, and the
-- day they drift the vectors say what the engine used to answer.
--
-- WHAT MAY GO IN HERE. A vector is a PURE function of nothing: fixed inputs, one
-- value out, through say(). Never a clock, never a random number, never table
-- ORDER (pairs is not ordered) and never a path -- those differ between two runs
-- of the same VM and would make every diff cry wolf. And always through say(),
-- which keeps one value to a line and tostring()s it in the VM under it, because
-- number formatting is one of the things being compared.
--
-- Kahlua-pure, like the OS core beside it: no metatable, no coroutine, no goto,
-- no io, no os, no loadstring. It is loaded by the game for both client and
-- server, by tests/kahlua-run.sh on the real Kahlua, and by the benches with
-- nothing under it at all.
--

CeroSecSelfTest = CeroSecSelfTest or {}

-- A secret of the shape CeroSecContent.isSecret wants, and fixed forever: the
-- values below are what they are because of this string, so changing it rewrites
-- every vector and proves nothing.
CeroSecSelfTest.SECRET = "0123456789abcdef"

-- The one string mkpasswd(1) is proved against, in the game, on the disk and
-- here. `selftest.sh` on the diagnostics floppy hashes exactly this text with
-- exactly this salt and compares the answer with a value baked into the script --
-- and tests/content_test.lua holds that baked value to CeroSecOS.hashPassword of
-- these two, so the number on the floppy cannot drift away from the engine.
--
-- It is the check that would have caught the "%" bug: hashPassword is
-- CeroSecOS.HASH_ROUNDS (4000) rounds of the mixer, and the mixer is nothing but
-- modulo.
CeroSecSelfTest.PASS_TEXT = "secret"
CeroSecSelfTest.PASS_SALT = "abcdef"

--
-- 1. The engine's pure functions, RUN
--
-- Moved here out of tests/kahlua-probe.lua, unchanged: the probe is now the
-- thing that PRINTS this, and this is the thing the game can run.
--
function CeroSecSelfTest.probe(say)
	local SECRET = CeroSecSelfTest.SECRET

	--
	-- tonumber's replacement, at the edges. The first three lines are the bug.
	--
	say("hexValue 7fffffff", CeroSecOS.hexValue("7fffffff"))
	say("hexValue 80000000", CeroSecOS.hexValue("80000000"))
	say("hexValue ffffffff", CeroSecOS.hexValue("ffffffff"))
	say("hexValue 00000000", CeroSecOS.hexValue("00000000"))
	say("hexValue 0", CeroSecOS.hexValue("0"))
	say("hexValue f", CeroSecOS.hexValue("f"))
	say("hexValue deadbeef", CeroSecOS.hexValue("deadbeef"))
	say("hexValue DEADBEEF", CeroSecOS.hexValue("DEADBEEF"))
	say("hexValue empty", CeroSecOS.hexValue(""))
	say("hexValue g", CeroSecOS.hexValue("g"))
	say("hexValue nil", CeroSecOS.hexValue(nil))
	say("hexValue number", CeroSecOS.hexValue(255))
	-- The raw tonumber(s, 16) is deliberately NOT probed here: it answers nil on
	-- Kahlua and a number on lua5.1 and always will, so a line for it would be a
	-- red that never goes green. The four lines above are the canary instead --
	-- point hexValue back at tonumber and they differ, which is how this probe was
	-- proven to catch the bug it was written for.

	--
	-- The mixer, at the rounds the mod actually uses.
	--
	say("digest empty 16", CeroSecOS.digest("", 16))
	say("digest cerosec 16", CeroSecOS.digest("cerosec", 16))
	say("digest long 16", CeroSecOS.digest(string.rep("ab", 40), 16))
	say("digest hi 0", CeroSecOS.digest("hi", 0))
	say("digest hi 4000", CeroSecOS.digest("hi", CeroSecOS.HASH_ROUNDS))
	say("digest 255 bytes", CeroSecOS.digest(string.char(0, 1, 127, 128, 255), 16))

	-- And the password hash whole, which is the value `mkpasswd` prints on the
	-- glass and the one the diagnostics floppy checks itself against.
	say("hashPassword canonical",
		CeroSecOS.hashPassword(CeroSecSelfTest.PASS_TEXT, CeroSecSelfTest.PASS_SALT))
	say("hashPassword empty", CeroSecOS.hashPassword("", CeroSecSelfTest.PASS_SALT))
	say("hashPassword bad salt", CeroSecOS.hashPassword("x", "NOT A SALT"))

	--
	-- The content derivation: the two functions the first power-on runs.
	--
	say("derive root", CeroSecContent.derive(SECRET, "root"))
	say("derive logh", CeroSecContent.derive(SECRET, "office.logh.1"))
	say("derive bad", CeroSecContent.derive(SECRET, "has/slash"))
	say("key parts", CeroSecContent.key("Coffee Shop", "logh", 3))
	for i = 1, 6 do
		say("number logh " .. i, CeroSecContent.number(SECRET,
			CeroSecContent.key("office", "logh", i), 10))
		say("number logm " .. i, CeroSecContent.number(SECRET,
			CeroSecContent.key("office", "logm", i), 60))
	end
	say("number n1", CeroSecContent.number(SECRET, "root", 1))
	say("number n100", CeroSecContent.number(SECRET, "root", 100))
	say("chance 50 root", CeroSecContent.chance(SECRET, "root", 50))

	--
	-- The phone line: the number a machine prints on its BIOS line.
	--
	say("phoneKey 0 0", CeroSecOS.phoneKey(0, 0))
	say("phoneKey 12 34", CeroSecOS.phoneKey(12, 34))
	say("phoneKey 255 255", CeroSecOS.phoneKey(255, 255))
	say("phoneKey bad", CeroSecOS.phoneKey(-1, 0))
	say("phoneText min 0", CeroSecOS.phoneText(CeroSecOS.PHONE_EXCHANGE_MIN, 0))
	say("phoneText min 7", CeroSecOS.phoneText(CeroSecOS.PHONE_EXCHANGE_MIN, 7))
	say("phoneText max last", CeroSecOS.phoneText(CeroSecOS.PHONE_EXCHANGE_MAX,
		CeroSecOS.PHONE_NUMBERS - 1))
	say("phoneText out", CeroSecOS.phoneText(CeroSecOS.PHONE_EXCHANGE_MAX,
		CeroSecOS.PHONE_NUMBERS))

	--
	-- string.format, in the patterns the shell's columns are built out of.
	--
	say("format f", string.format("%5.2f", 3.14159))
	say("format f neg", string.format("%5.2f", -0.5))
	say("format s left", "[" .. string.format("%-8s", "ab") .. "]")
	say("format s right", "[" .. string.format("%8s", "ab") .. "]")
	say("format 02d", string.format("%02d", 7))
	say("format 02d big", string.format("%02d", 123))
	say("format d zero", string.format("%d", 0))
	say("format x", string.format("%x", 255))
	say("format percent", string.format("%d%%", 50))
	say("format two", string.format("%s:%d", "a", 12))

	--
	-- Arithmetic that the placer and the columns depend on, at the signs and the
	-- sizes where VMs differ.
	--
	say("fmod 7 3", math.fmod(7, 3))
	say("fmod -7 3", math.fmod(-7, 3))
	say("fmod 7 -3", math.fmod(7, -3))
	say("fmod big", math.fmod(4294967295, 60))
	-- The "%" OPERATOR is probed only where the mod is allowed to use it: both
	-- operands non-negative and the quotient under 2^31. Kahlua's "%" truncates
	-- toward zero where Lua floors (-7 % 3 is -1 there and 2 here) and is outright
	-- wrong once the quotient reaches 2^31, and neither is fixable in the mod -- so
	-- they are a RULE in docs/TESTING.md and a grep in kahlua-check.sh, not a line
	-- here that could never go green. CeroSecOS.mod is what the engine uses.
	say("mod 7 3", 7 % 3)
	say("CeroSecOS.mod 7 3", CeroSecOS.mod(7, 3))
	say("CeroSecOS.mod big", CeroSecOS.mod(47564 * 3266489917, 65536))
	say("CeroSecOS.mod exact 32", CeroSecOS.mod(4294967295, 65536))
	say("CeroSecOS.mod b zero", CeroSecOS.mod(1, 0))
	say("CeroSecOS.mod a neg", CeroSecOS.mod(-7, 3))
	say("CeroSecOS.mod not number", CeroSecOS.mod("7", 3))
	say("floor -0.5", math.floor(-0.5))
	say("floor div", math.floor(-7 / 3))
	-- tostring of a NON-INTEGER is not probed: Kahlua renders a double the Java way
	-- ("1.0E15", "0.3333333333333333") and lua5.1 uses "%.14g" ("1e+15",
	-- "0.33333333333333"). Unfixable, so it is the other half of the rule in
	-- docs/TESTING.md: the engine never puts a non-integer through tostring.
	say("tostring int", tostring(42))
	say("tostring div", tostring(10 / 2))
	say("tostring neg zero", tostring(0 - 0))

	--
	-- Bytes and strings at the ends of the range.
	--
	say("byte of 0", string.byte(string.char(0)))
	say("byte of 255", string.byte(string.char(255)))
	say("len char 0", #string.char(0, 65, 0))
	say("byte middle", string.byte(string.char(0, 65, 0), 2))
	say("rep 0", "[" .. string.rep("ab", 0) .. "]")
	say("rep 3", string.rep("ab", 3))
	say("sub past end", "[" .. string.sub("abc", 2, 99) .. "]")
	say("sub negative", string.sub("abcdef", -3))
	say("upper", string.upper("aBc1"))
	say("gsub count", select(2, string.gsub("a.b.c", "%.", "-")))
	say("find plain", tostring(string.find("a.b", ".", 1, true)))
	say("concat", table.concat({ "a", "b", "c" }, ","))
	say("concat numbers", table.concat({ 1, 2, 3 }, "-"))
	say("concat empty", "[" .. table.concat({}, ",") .. "]")

	--
	-- The calendar the log placer steps in: no os.time anywhere, the engine's own
	-- civil arithmetic over a fixed stamp.
	--
	local START = CeroSecOS.timeFromParts(1993, 7, 9, 9, 0, 0)
	say("timeFromParts start", START)
	local midnight = math.floor(START / 86400) * 86400
	say("midnight", midnight)
	for i = 1, 3 do
		local at = midnight - (8 - i) * 86400 + 11 * 3600 + 42 * 60
		say("formatStamp " .. i, CeroSecOS.formatStamp(at))
	end
	say("formatStamp zero", CeroSecOS.formatStamp(0))
	say("formatDate start", CeroSecOS.formatDate(START))
	say("formatTime start",
		CeroSecOS.formatTime(START, "%Y-%m-%d %H:%M:%S j=%j %a %b s=%s %% %q"))
	local p = CeroSecOS.dateParts(START)
	say("dateParts", p.year .. "-" .. p.month .. "-" .. p.day
		.. " " .. p.hour .. ":" .. p.min .. ":" .. p.sec)
	local z = CeroSecOS.dateParts(0)
	say("dateParts of zero", z.year .. "-" .. z.month .. "-" .. z.day)

	--
	-- The small string helpers every column in the shell goes through.
	--
	say("truncate long", CeroSecOS.truncate("abcdefgh", 4))
	say("truncate exact", CeroSecOS.truncate("abcd", 4))
	say("padRight", "[" .. CeroSecOS.padRight("ab", 5) .. "]")
	say("padLeft", "[" .. CeroSecOS.padLeft("ab", 5) .. "]")
	say("hasControlBytes no", CeroSecOS.hasControlBytes("ab\tc\nd"))
	say("hasControlBytes yes", CeroSecOS.hasControlBytes("ab" .. string.char(7)))

	--
	-- The script engine, parsed and STEPPED. The bit of the mod a player's own
	-- typing goes through, and the one whose answers nothing else on this list
	-- would notice going wrong on the other VM.
	--
	say("parse ok", CeroSecOS.parseScript("echo hi; echo there") ~= nil)
	local bad, why = CeroSecOS.parseScript("for i in 1 2; do echo $i")
	say("parse missing done", bad == nil and tostring(why) or "PARSED")
	say("arith mod small", CeroSecSelfTest.arith("7 % 3"))
	-- The quotient is over 2^31 here, which is where Kahlua's own "%" is wrong: the
	-- shell's $(( )) reader must not be written with it (CeroSecOSVM.arithProduct
	-- divides and floors instead), and this is the line that says so.
	say("arith mod big", CeroSecSelfTest.arith("2147483648 % 7"))
	say("arith mod 32", CeroSecSelfTest.arith("4294967295 % 65536"))
	say("arith neg div", CeroSecSelfTest.arith("-7 / 2"))
	say("arith neg mod", CeroSecSelfTest.arith("-7 % 3"))
	say("arith precedence", CeroSecSelfTest.arith("1 + 2 * 3 - 4 / 2"))
	-- The expansions inside $(( )), which POSIX.2 does before the sum is read.
	-- Here because they go through tonumber on a word a script was handed, and a
	-- VM whose tonumber answered differently for "3" would take `$((5 % $1))` --
	-- the commonest line there is in a script that walks its arguments -- from
	-- right to nought without a single bench noticing.
	say("arith argument", CeroSecSelfTest.arith("5 % $1", { "3" }))
	say("arith argument count", CeroSecSelfTest.arith("$# * 10", { "a", "b" }))
	say("arith argument missing", CeroSecSelfTest.arith("$2 + 1", { "3" }))
	say("arith braces", CeroSecSelfTest.arith("${nothing} + 1", { "3" }))
	-- And the two NESTINGS, which are parser work on both sides of the same two
	-- characters: a $( ) inside a sum has to be run before the sum is read, a
	-- $(( )) inside a catch must not be mistaken for a second catch, and a second
	-- catch is still refused. Here because all three are decided by scanning text
	-- for brackets with string.sub and string.find, and a VM that answered
	-- differently about either would turn a line a survivor types into a refusal.
	say("arith holds a catch", CeroSecSelfTest.arith("$(echo 5) + 1"))
	say("arith holds two catches", CeroSecSelfTest.arith("$(echo 6) * $(echo 7)"))
	say("catch holds a sum", CeroSecSelfTest.sh("echo $( echo $(( 2 + 3 )) )"))
	local twice, twiceWhy = CeroSecOS.parseScript("echo $(echo $(echo deep))")
	say("catch in catch", twice == nil and tostring(twiceWhy) or "PARSED")
	say("catch inside quotes", CeroSecSelfTest.sh("echo \"[$(echo \"a b\")]\""))
	-- case, which is parser work and MATCHER work: the bracket that closes a pattern
	-- is found with string.sub on the last piece of a word, and a `[a-c]` set is
	-- walked with string.byte -- a VM that answered differently about either would
	-- turn a working script into a refusal or, worse, into a clause that never runs.
	say("case match", CeroSecSelfTest.sh("case abc in a*) echo star;; esac"))
	say("case alternatives", CeroSecSelfTest.sh("case abc in x|abc) echo alt;; esac"))
	say("case default",
		CeroSecSelfTest.sh("case abc in z*) echo no;; *) echo other;; esac"))
	say("case set", CeroSecSelfTest.sh("case b in [a-c]) echo set;; esac"))
	say("case negated set",
		CeroSecSelfTest.sh("case 7 in [!0-9]) echo no;; *) echo digit;; esac"))
	say("case no match", CeroSecSelfTest.sh("case abc in q) echo no;; esac"))
	local noParen, noParenWhy = CeroSecOS.parseScript("case abc in abc echo x;; esac")
	say("case missing bracket", noParen == nil and tostring(noParenWhy) or "PARSED")
	local loose, looseWhy = CeroSecOS.parseScript("echo a;;")
	say("two semicolons alone", loose == nil and tostring(looseWhy) or "PARSED")
	-- Shell functions, which are parser work of a shape nothing else here has: the
	-- brackets after the name are found with string.match on the word, and the SOURCE
	-- of the definition is cut out of the text with string.sub on offsets the
	-- tokenizer recorded -- so a VM that counted a byte differently would hand the
	-- console a function it could not read back.
	say("function call", CeroSecSelfTest.sh("greet() { echo hi $1; }; greet bob"))
	say("function spaced", CeroSecSelfTest.sh("g () { echo spaced; }; g"))
	say("function return", CeroSecSelfTest.sh("r() { return 3; }; r; echo $?"))
	say("function args", CeroSecSelfTest.sh("c() { echo \"$# $@\"; }; c a b"))
	local fnSrc = CeroSecOS.parseScript("pair() { echo one; echo two; }")
	say("function source kept",
		type(fnSrc) == "table" and type(fnSrc[1]) == "table" and tostring(fnSrc[1].src)
			or "NO NODE")
	local noBrace, noBraceWhy = CeroSecOS.parseScript("bad() echo x; }")
	say("function missing brace", noBrace == nil and tostring(noBraceWhy) or "PARSED")

	--
	-- grep's basic regular expressions, which are walked byte by byte with
	-- string.byte and a table keyed by byte value. Here for the reason globMatch's
	-- ranges are: a VM that answered differently about string.byte or about a range
	-- would turn a pattern into a silence, and a silence is the one answer a search
	-- must never give.
	--
	local function bre(pattern, line)
		local re, why = CeroSecOS.breCompile(pattern)
		if re == nil then return "refused: " .. tostring(why) end
		local hit = CeroSecOS.breMatch(line, re)
		return tostring(hit)
	end
	say("bre literal", bre("From", "From bob"))
	say("bre anchored", bre("^From ", "From bob"))
	say("bre anchored miss", bre("^From ", "  From bob"))
	say("bre end", bre("bob$", "From bob"))
	say("bre any", bre("F.om", "From bob"))
	say("bre star", bre("Fr*om", "Fom"))
	say("bre star none", bre("Fx*om", "Fom"))
	say("bre set", bre("[Ff]rom", "from bob"))
	say("bre range", bre("^[a-z][a-z]*$", "frombob"))
	say("bre negated", bre("^[^0-9]", "From bob"))
	say("bre negated miss", bre("^[^0-9]", "7 bob"))
	say("bre escape", bre("a\\.b", "axb"))
	say("bre escape hit", bre("a\\.b", "a.b"))
	say("bre bracket in set", bre("a[]]b", "a]b"))
	say("bre empty", bre("", "anything"))
	say("bre blank line", bre("^$", ""))
	say("bre unmatched", bre("[abc", "abc"))
	say("bre bad range", bre("[z-a]", "abc"))
	say("bre trailing backslash", bre("a\\", "a"))
	say("bre too long", bre(string.rep(".", CeroSecOS.MAX_BRE_ITEMS + 1), "x"))

	--
	-- The tar container, which is what a floppy carries between two machines.
	--
	-- Here because it is written and read as TEXT with a byte count in it: a VM
	-- whose string.sub or # answered differently at an edge would write archives
	-- one machine could make and another could not read, and the disk would be
	-- carried across town before anybody found out. The round trip is asserted as
	-- well as the bytes, so a reader that lost a member is not green for having
	-- written one.
	local members = {
		{ kind = "d", mode = 755, owner = "admin", group = "users", mtime = 7, name = "work" },
		{ kind = "f", mode = 600, owner = "admin", group = "users", mtime = 8,
			name = "work/two.txt", data = "first\nsecond" },
		{ kind = "f", mode = 644, owner = "root", group = "root", mtime = 0,
			name = "empty", data = "" },
		{ kind = "l", mode = 777, owner = "admin", group = "users", mtime = 9,
			name = "short", data = "work/two.txt" },
	}
	local archive = CeroSecSelfTest.tar(members)
	say("tar container bytes", #archive)
	say("tar container", (string.gsub(archive, "\n", "|")))
	say("tar round trip", CeroSecSelfTest.tarBack(archive))
	say("tar not an archive", CeroSecOS.tarMembers("hello\n") == nil)
	say("tar cut short", CeroSecOS.tarMembers(
		CeroSecOS.TAR_MAGIC .. "\nf 644 a b 0 20 x\nshort\n") == nil)
end

-- The archive of a fixed member list, as text. A function of nothing, like every
-- vector: the members are written above and no disk is looked at.
function CeroSecSelfTest.tar(members)
	return CeroSecOS.tarText(members)
end

-- And what reading it back says about every field, as ONE line: a vector is one
-- value, and what has to agree between two VMs is the whole of what came out.
function CeroSecSelfTest.tarBack(text)
	local members = CeroSecOS.tarMembers(text)
	if members == nil then return "NOT AN ARCHIVE" end
	local out = {}
	for i = 1, #members do
		local m = members[i]
		out[#out + 1] = m.kind .. ":" .. tostring(m.mode) .. ":" .. m.owner .. ":"
			.. m.group .. ":" .. tostring(m.mtime) .. ":" .. m.name .. ":"
			.. tostring(#m.data) .. ":" .. (string.gsub(m.data, "\n", "|"))
	end
	return table.concat(out, " ")
end

-- One LINE, run the way the prompt runs one, and the first line it printed.
--
-- The general form of CeroSecSelfTest.arith below, and it is here for the same
-- reason: the parser and the walker are what a player's own typing goes through,
-- and nothing else on this list would notice either of them answering differently
-- on the other VM. A line that printed nothing answers "no output" and a line
-- that would not parse answers its own refusal, so a broken shell is a LINE here
-- and not an error out of the middle of the probe.
--
-- Pure, as every vector has to be: no clock is handed in (env.now is 0), no path
-- is named and nothing is read back out of the filesystem, so two runs of one VM
-- answer the same thing.
function CeroSecSelfTest.sh(line)
	local state = CeroSecOS.newState("selftest")
	local session = CeroSecOS.login(state, "root", "")
	if session == nil then return "no session" end
	local job, refusal = CeroSecOS.promptJob(state, session, line, {}, 0)
	if job == nil then return tostring(refusal) end
	local env = { now = 0 }
	local turns = 0
	while not CeroSecOS.jobIsOver(job) and turns < 64 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, env, 1000)
		if job.state == "waiting" or job.state == "sleeping" then break end
	end
	if #job.out == 0 then return "no output" end
	return job.out[1]
end

-- One `$(( ))` expression, evaluated the way the shell evaluates one: through a
-- real job, because the reader is the VM's and takes a job for its variables.
-- The answer as a string, or the refusal, so a broken arithmetic reader is a
-- LINE and not an error out of the middle of the probe.
--
-- args, when given, makes it a SCRIPT's job instead of a prompt's, because $1 is
-- a script's and a prompt has no arguments to answer with.
function CeroSecSelfTest.arith(expr, args)
	local state = CeroSecOS.newState("selftest")
	local session = CeroSecOS.login(state, "root", "")
	if session == nil then return "no session" end
	local job
	if args == nil then
		job = CeroSecOS.promptJob(state, session, "echo $(( " .. expr .. " ))", {}, 0)
	else
		local prog = CeroSecOS.parseScript("echo $(( " .. expr .. " ))")
		if prog == nil then return "no parse" end
		job = CeroSecOS.newJob({ prog = prog, args = args, name = "probe.sh",
			session = session })
	end
	if job == nil then return "no job" end
	local env = { now = 0 }
	local turns = 0
	while not CeroSecOS.jobIsOver(job) and turns < 64 do
		turns = turns + 1
		CeroSecOS.jobStep(state, job, env, 1000)
		if job.state == "waiting" or job.state == "sleeping" then break end
	end
	if #job.out == 0 then return "no output" end
	return job.out[1]
end

--
-- 2. The lists the save file and the wire are made of
--
-- Three literal lists decide what a machine keeps across a reload and what a
-- client is ever told (SCeroSecSystem:initModData hands them to the engine's own
-- setters). They are CONSTANTS in CeroSecDefs so that this can read the very
-- list the server passes, rather than a copy of it written down twice.
--
-- The one that matters is `seed`: it is the per-save secret every password in the
-- county is derived from, it is SAVED on the server and it must never be on the
-- wire. Asserted from both ends -- present in the system's saved keys, absent
-- from the object's synced ones -- because "seed is not in this list" is a green
-- assertion on a list that has become empty, and the other half is what stops
-- that.
--
function CeroSecSelfTest.keys(say)
	say("sync has disk", CeroSecSelfTest.holds(CeroSec.OBJECT_SYNC_KEYS, "disk"))
	say("sync has on", CeroSecSelfTest.holds(CeroSec.OBJECT_SYNC_KEYS, "on"))
	say("sync has facing", CeroSecSelfTest.holds(CeroSec.OBJECT_SYNC_KEYS, "facing"))
	say("sync has v", CeroSecSelfTest.holds(CeroSec.OBJECT_SYNC_KEYS, "v"))
	say("sync count", #CeroSec.OBJECT_SYNC_KEYS)
	say("sync has no seed", CeroSecSelfTest.holds(CeroSec.OBJECT_SYNC_KEYS, "seed"))
	say("sync has no os", CeroSecSelfTest.holds(CeroSec.OBJECT_SYNC_KEYS, "os"))
	say("sync has no console",
		CeroSecSelfTest.holds(CeroSec.OBJECT_SYNC_KEYS, "console"))
	say("saved has os", CeroSecSelfTest.holds(CeroSec.OBJECT_SAVE_KEYS, "os"))
	say("saved has console", CeroSecSelfTest.holds(CeroSec.OBJECT_SAVE_KEYS, "console"))
	say("saved has no disk", CeroSecSelfTest.holds(CeroSec.OBJECT_SAVE_KEYS, "disk"))
	say("saved has no seed", CeroSecSelfTest.holds(CeroSec.OBJECT_SAVE_KEYS, "seed"))
	say("saved count", #CeroSec.OBJECT_SAVE_KEYS)
	-- And the other end of it: the seed IS kept, on the server, in the system's
	-- own modData. Without this line the three above are satisfied by a build that
	-- has stopped saving the secret at all.
	say("system saves seed", CeroSecSelfTest.holds(CeroSec.SYSTEM_SAVE_KEYS, "seed"))
	say("system saves notes", CeroSecSelfTest.holds(CeroSec.SYSTEM_SAVE_KEYS, "notes"))
	-- And the register of what each premises' machines already are. Without it a
	-- reload gives the second desk of an office the owner the first one has, and a
	-- display model on a shop floor comes up as the shop's own back office.
	say("system saves desks", CeroSecSelfTest.holds(CeroSec.SYSTEM_SAVE_KEYS, "desks"))
	-- And which premises were automated before the outbreak, which is a decision
	-- made once in the life of a premises: without it a reload rolls again, and a
	-- shop's fixtures are wired a second time over the survivor who stripped them.
	say("system saves auto", CeroSecSelfTest.holds(CeroSec.SYSTEM_SAVE_KEYS, "auto"))
	say("system count", #CeroSec.SYSTEM_SAVE_KEYS)
	-- The one bit on a machine that says its square was created in this save and
	-- nobody has settled the question yet. Saved, so a quit in the minute between
	-- the chunk arriving and the sweep does not lose it.
	say("saved has born", CeroSecSelfTest.holds(CeroSec.OBJECT_SAVE_KEYS, "born"))
end

-- Is that name on that list? A walk and not a set, because the lists are three
-- and five names long and a set built here would be a second copy of them.
function CeroSecSelfTest.holds(list, name)
	if type(list) ~= "table" then return "NO LIST" end
	for i = 1, #list do
		if list[i] == name then return true end
	end
	return false
end

-- Everything a vector table is made of, in one call: the engine's answers, then
-- the lists. This is what the generator runs and what run() runs, so a vector
-- that exists is a vector both of them see.
function CeroSecSelfTest.vectors(say)
	CeroSecSelfTest.probe(say)
	CeroSecSelfTest.keys(say)
end

--
-- 3. Running them
--

-- The vectors, evaluated on THIS VM and weighed against the canonical answers in
-- CeroSecSelfTestVectors.lua.
--
--   { pass = n, fail = m, lines = { "..." } }
--
-- Three ways to fail and all three are counted, because two of them are how a
-- bench goes quietly green:
--
--   * an answer that differs from the vector -- the one everybody expects;
--   * a vector nothing evaluated, which is a body somebody took a line out of
--     without regenerating -- reported as a MISSING vector rather than skipped;
--   * an answer with no vector for it, which is a body somebody added a line to
--     without regenerating -- reported as a STALE table.
--
-- So the count of lines evaluated and the count of vectors held are asserted
-- against each other, and a run of nothing at all is a failure and not a pass.
function CeroSecSelfTest.run()
	local lines = {}
	local list = CeroSecSelfTest.VECTORS
	if type(list) ~= "table" or #list == 0 then
		lines[1] = "selftest: CeroSecSelfTestVectors.lua is missing or empty" ..
			" -- run tools/make-selftest-vectors.lua"
		return { pass = 0, fail = 1, lines = lines }
	end

	local want, seen = {}, {}
	for i = 1, #list do
		local vector = list[i]
		if type(vector) == "table" and type(vector.name) == "string" then
			want[vector.name] = vector.want
		end
	end

	local pass, fail = 0, 0
	local order = {}
	CeroSecSelfTest.vectors(function(name, value)
		local got = tostring(value)
		order[#order + 1] = name
		if seen[name] then
			fail = fail + 1
			lines[#lines + 1] = "selftest: " .. name .. ": said twice"
			return
		end
		seen[name] = true
		local expected = want[name]
		if expected == nil then
			fail = fail + 1
			lines[#lines + 1] = "selftest: " .. name ..
				": no vector for it -- the table is stale"
		elseif expected ~= got then
			fail = fail + 1
			lines[#lines + 1] = "selftest: " .. name .. ": want [" ..
				tostring(expected) .. "] got [" .. got .. "]"
		else
			pass = pass + 1
		end
	end)

	-- And the vectors nothing answered. Walked over the TABLE and not over what
	-- ran, which is the only order in which a missing line can be noticed at all.
	for i = 1, #list do
		local vector = list[i]
		local name = type(vector) == "table" and vector.name or nil
		if type(name) ~= "string" then
			fail = fail + 1
			lines[#lines + 1] = "selftest: vector " .. i .. " has no name"
		elseif not seen[name] then
			fail = fail + 1
			lines[#lines + 1] = "selftest: " .. name ..
				": a vector nothing evaluated -- the body is stale"
		end
	end

	if #order == 0 then
		fail = fail + 1
		lines[#lines + 1] = "selftest: the body evaluated nothing at all"
	end
	return { pass = pass, fail = fail, lines = lines }
end

--
-- 4. The one thing only the game can be asked
--
-- The save path, on a real machine, there and back: the state the server holds is
-- mirrored into the IsoObject (SCeroSecObject:stateToIsoObject, which is what
-- runs on every chunk load), read back out of that object's own modData, put
-- through a copy that keeps ONLY what the game's serializer keeps, and handed to
-- the boot gate. Every key that went in comes out.
--
-- WHAT CAN ACTUALLY DIFFER, because a round trip written without asking that is a
-- row of vectors that can never go red. The mirror holds `os = self.os` -- the
-- same table, by reference -- so "what came back equals what went in" is a table
-- equal to itself and would pass on a build that had stopped saving anything. It
-- is here, said out loud, as the statement of the design; the vectors that can
-- FAIL are the other four:
--
--   * the mirror is THERE at all, under the key vanilla's pickup reads
--     (CeroSec.MOVABLE_DATA_KEY). A change that renames it or drops the write
--     leaves every computer carried across town blank, and nothing else notices.
--   * the mirror carries every field toModData writes -- v, on, facing, os. Drop
--     `facing` and a computer picked up and put down faces the wrong way; drop
--     `on` and it comes back dark. Neither is validated by anything.
--   * a copy of the WHOLE mirror entry keeping only what KahluaTable.save keeps
--     drops nothing. This is not a second validate: validate is asked of the OS
--     state alone, and the three fields beside it go into the save file with
--     nothing weighing them at all.
--   * and the copy of the state still passes the boot gate, which is the
--     assertion that validate's rule and the serializer's rule are the SAME rule.
--     (They are, today -- which is why a function planted in the state is refused
--     by osState long before it reaches here, and why the mutation that proves
--     these vectors is a dropped mirror field and not a planted function.)
--
-- Answers { pass, fail, lines } like run() does, so the two add up.
function CeroSecSelfTest.runSave(luaObject)
	local pass, fail, lines = 0, 0, {}
	local function vector(name, got, wanted)
		if got == wanted then
			pass = pass + 1
		else
			fail = fail + 1
			lines[#lines + 1] = "selftest: save." .. name .. ": want [" ..
				tostring(wanted) .. "] got [" .. tostring(got) .. "]"
		end
	end

	if type(luaObject) ~= "table" then
		vector("machine", "nothing is selected", "a machine")
		return { pass = pass, fail = fail, lines = lines }
	end
	-- Asked before anything is written, and in the same words the window greys the
	-- Turn on button with: the mirror is written into a thing in the WORLD, and a
	-- machine whose chunk is away has no thing in the world to write it into.
	--
	-- ONE question and not two. A draft asked isLoaded() and then asked for the
	-- IsoObject, which reads like belt and braces and is not: SCeroSecObject:isLoaded
	-- IS `getIsoObject() ~= nil`, so the second refusal sat on a path nothing could
	-- ever reach and would have been a vector that could never go red.
	local isoObject = nil
	if luaObject.getIsoObject ~= nil then isoObject = luaObject:getIsoObject() end
	if isoObject == nil then
		vector("chunk", "its chunk is away -- teleport to it first", "loaded")
		return { pass = pass, fail = fail, lines = lines }
	end

	local state, refusal = luaObject:osState()
	vector("state", state ~= nil and "a state" or ("REFUSED: " .. tostring(refusal)),
		"a state")
	if state == nil then return { pass = pass, fail = fail, lines = lines } end

	-- The write the chunk load does, then the read the placement code does.
	luaObject:stateToIsoObject(isoObject)
	local back = luaObject:osFromIsoObject(isoObject)
	vector("mirror", type(back), "table")
	if type(back) ~= "table" then return { pass = pass, fail = fail, lines = lines } end
	-- The design, said out loud rather than left to be discovered.
	vector("mirror is the state", back == state, true)

	-- The whole mirror ENTRY and not just the OS state: v, on and facing ride into
	-- the save beside it and nothing validates those three.
	local entry = CeroSecSelfTest.mirrorEntry(isoObject)
	vector("entry", type(entry), "table")
	if type(entry) ~= "table" then return { pass = pass, fail = fail, lines = lines } end
	vector("entry keys", CeroSecSelfTest.topKeys(entry), "facing on os v")

	local copy, dropped, deep = CeroSecSelfTest.serializable(entry, 1)
	vector("serializable", dropped, 0)
	vector("depth", deep, false)

	local ok, why = CeroSecOS.validate(copy.os)
	vector("validate", ok and "ok" or ("NOT OK: " .. tostring(why)), "ok")

	local a = CeroSecSelfTest.keyPaths(back)
	local b = CeroSecSelfTest.keyPaths(copy.os)
	vector("keys", #a == #b and a == b, true)
	vector("keys count", #a > 0, true)
	return { pass = pass, fail = fail, lines = lines }
end

-- The top-level key names of a table, sorted, as one string. Sorted because pairs
-- is not ordered; top level only, because what is being asked is which FIELDS
-- toModData wrote and not what is inside them.
function CeroSecSelfTest.topKeys(value)
	if type(value) ~= "table" then return "NOT A TABLE" end
	local names = {}
	for key in pairs(value) do names[#names + 1] = tostring(key) end
	table.sort(names)
	return table.concat(names, " ")
end

-- What SCeroSecObject:toModData wrote, read back the way vanilla's own pickup
-- reads it (ISMoveableSpriteProps.lua:1300): modData.movableData under our key.
-- osFromIsoObject answers only the `os` inside it, and the three fields beside
-- that one are exactly the ones nothing else weighs.
function CeroSecSelfTest.mirrorEntry(isoObject)
	if isoObject == nil then return nil end
	if isoObject.hasModData ~= nil and not isoObject:hasModData() then return nil end
	local modData = isoObject:getModData()
	if type(modData) ~= "table" then return nil end
	if type(modData.movableData) ~= "table" then return nil end
	return modData.movableData[CeroSec.MOVABLE_DATA_KEY]
end

-- A copy of a state keeping only what KahluaTable.save keeps: strings, numbers,
-- booleans and tables of those, under string or number keys. Answers the copy,
-- how many values it had to DROP, and whether it hit the depth ceiling -- the two
-- numbers being the whole point, because a copy that silently left something
-- behind is what a save file is.
CeroSecSelfTest.MAX_DEEP = 16

function CeroSecSelfTest.serializable(value, depth)
	local out, dropped, deep = {}, 0, false
	if depth > CeroSecSelfTest.MAX_DEEP then return out, 0, true end
	for key, at in pairs(value) do
		local keyOk = type(key) == "string" or type(key) == "number"
		local kind = type(at)
		if not keyOk then
			dropped = dropped + 1
		elseif kind == "table" then
			local sub, subDropped, subDeep = CeroSecSelfTest.serializable(at, depth + 1)
			out[key] = sub
			dropped = dropped + subDropped
			if subDeep then deep = true end
		elseif kind == "string" or kind == "number" or kind == "boolean" then
			out[key] = at
		else
			dropped = dropped + 1
		end
	end
	return out, dropped, deep
end

-- Every key of a table, at every depth, as one sorted string. Sorted because
-- pairs is not ordered and two walks of the same table would otherwise disagree
-- with each other -- which would make this the bench that cries wolf.
function CeroSecSelfTest.keyPaths(value, prefix, out, depth)
	prefix = prefix or ""
	out = out or {}
	depth = depth or 1
	if depth > CeroSecSelfTest.MAX_DEEP then return table.concat(out, " ") end
	local names = {}
	for key in pairs(value) do names[#names + 1] = tostring(key) end
	table.sort(names)
	for i = 1, #names do
		local name = names[i]
		local at = value[name]
		if at == nil then at = value[tonumber(name)] end
		out[#out + 1] = prefix .. "." .. name
		if type(at) == "table" then
			CeroSecSelfTest.keyPaths(at, prefix .. "." .. name, out, depth + 1)
		end
	end
	return table.concat(out, " ")
end

-- Both halves, added up, which is what the debug window asks for.
function CeroSecSelfTest.runAll(luaObject)
	local vm = CeroSecSelfTest.run()
	local save = CeroSecSelfTest.runSave(luaObject)
	local lines = {}
	for i = 1, #vm.lines do lines[#lines + 1] = vm.lines[i] end
	for i = 1, #save.lines do lines[#lines + 1] = save.lines[i] end
	return { pass = vm.pass + save.pass, fail = vm.fail + save.fail, lines = lines }
end

-- The one line that goes on the glass and into the log, and the one thing a
-- reader is looking for. Built here so the window, the server log and the game
-- console all say it in the same words.
function CeroSecSelfTest.summary(result)
	if type(result) ~= "table" then return "selftest: nothing ran" end
	return "selftest: PASS " .. tostring(result.pass) ..
		" FAIL " .. tostring(result.fail)
end
