--
-- CeroSec OS core: packet radio.
--
-- The third link, and the last one. The coax reaches the other computers of one
-- building; the telephone reaches one building from another as long as the
-- county's exchange is alive; the RADIO reaches whatever is within earshot of an
-- aerial, with no exchange and no wire, which is why an amateur built one in the
-- first place.
--
-- WHAT THIS IS FAITHFUL TO. Packet radio in 1993 was a terminal node controller
-- -- a TNC, a box the size of a paperback -- with an RS-232 cable to the
-- computer and a microphone cable to the radio. The TNC held the station's
-- CALLSIGN and spoke AX.25 over the air at 1200 baud on two metres. A survivor
-- who had one typed a connect request at it and got a line back:
--
--     cmd: c KD4AXR
--     *** CONNECTED to KD4AXR
--
-- and from then on every character he typed went out over the air and arrived on
-- somebody else's screen. That is exactly what this rung is, and since
-- SYSTEM_VERSION 17 the `cmd:` above is the real one: the box is reached with
-- `cu -l /dev/radio0`, which is cu(1)'s own way of opening a serial line, and
-- driven with the TNC-2's own words. There was a `call CALLSIGN` command here
-- until then and it was invented -- no Unix shipped one, because a TNC was a
-- peripheral and not a kernel's business.
--
-- WHAT IS THE ENGINE'S HALF. The callsign and the file it lives in, the shape of
-- a callsign, the frequency as a reader of a radio dial writes it, the TNC's own
-- lines, its command dialog, and its heard list -- each up to the point where the
-- world has to be asked whether anybody can hear anything. Everything about
-- aerials, channels, distance and power is the world's and is in
-- SCeroSecRadio.lua, which is also where every game call it makes is proved.
--
-- WHAT IS DIFFERENT ABOUT THIS LINK, and it is the whole security lesson of the
-- rung: there is no wire and there is no number. An address is a fact about which
-- building a machine stands in and a telephone number is a fact about the wall;
-- neither can be typed. A CALLSIGN is a file, /etc/callsign, and root may write
-- it -- because on the air a callsign is what a station SAYS it is, and the only
-- thing behind it is an operator's licence and his word. So a call is never
-- trusted: the far machine asks for a password every time, exactly as it does
-- down the telephone, and for a stronger reason.
--

CeroSecOS = CeroSecOS or {}
CeroSecOS.commands = CeroSecOS.commands or {}

--
-- The callsign
--
-- /etc/callsign, root's and 644: everybody on the machine may read it -- it is
-- what the machine says about itself on the air and there is no secret in one --
-- and only root may change it.
--
-- ONE LINE, one word. There is no format to be faithful to because there was
-- never a Unix file for this: a TNC kept its callsign in its own battery-backed
-- memory under the name MYCALL, and what a machine wrote down beside it was a
-- line in somebody's notes. So the file is the plainest thing it could be, and
-- everything after the first word on the first line is ignored the way a comment
-- is -- a survivor who wrote "KD4AXR (Bob's set)" in it has a machine that still
-- knows its callsign.
CeroSecOS.CALLSIGN_PATH = "/etc/callsign"
CeroSecOS.CALLSIGN_MODE = 644

-- The shape of a United States amateur callsign in 1993, and the whole of it:
-- a prefix of K, N or W, then an optional second letter, then ONE digit -- the
-- call district -- then two or three letters. K4ABC, KD4AXR, N4AB and KD4AB are
-- all real shapes; KD44AXR and 4KDAXR are not, and neither is anything with a
-- lower-case letter in it, because a callsign is sent in capitals and written in
-- capitals.
--
-- What is deliberately NOT here is the SSID -- the "-1" an AX.25 station hangs
-- on the end of a call to tell two of its own boxes apart. This machine has one
-- TNC and therefore one station, which is SSID 0, and SSID 0 is written with
-- nothing after the call at all.
-- Written with explicit [A-Z] ranges and not with %u. The class is right in
-- ordinary Lua and this engine has never used one: everything else in it reads
-- %a, %d and %w, and a capital-letter class that a locale or Kahlua's own class
-- table might read differently is not something to put in the middle of the one
-- rule that decides whether a station may transmit.
function CeroSecOS.isCallsign(text)
	if type(text) ~= "string" then return false end
	return string.match(text,
		"^[KNW][A-Z]?%d[A-Z][A-Z][A-Z]?$") ~= nil
end

-- The call district, which is not a hash and must not be one: the digit in a
-- United States callsign says WHERE the station is licensed, and the fourth
-- district was the south-east -- Kentucky in it. Every station in Knox County
-- wears a 4, so the digit is the one character of the callsign that is a fact
-- about the map rather than about the machine.
CeroSecOS.CALL_DISTRICT = "4"

-- The three prefixes the fourth district handed out, in the order the sequence
-- ran: W first, then K, and N when those ran out.
CeroSecOS.CALL_PREFIXES = { "W", "K", "N" }

-- The alphabet as a string, indexed rather than computed: string.char is not used
-- anywhere else in this engine, and a table lookup cannot be wrong about which
-- byte a letter is.
CeroSecOS.CALL_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function letterAt(n)
	local i = math.fmod(math.floor(n), 26) + 1
	return string.sub(CeroSecOS.CALL_LETTERS, i, i)
end

-- The callsign a station is BORN with: derived from the building the computer
-- stands in and from which computer of that building it is -- the very three
-- numbers the address and the telephone number come off -- so that a machine
-- whose chunk nobody has loaded can still be named, and so that an older save
-- needs no new field to answer.
--
-- Two hashes and not one. Both are a multiply-add modulo 2^16, which is the
-- arithmetic a double holds exactly and the same shape CeroSecOS.buildingKey and
-- CeroSecOS.phoneKey are made of; the multipliers are different from theirs on
-- purpose, so that a building's callsign is not a rearrangement of its telephone
-- number. Five of the six characters come out of them and the sixth is the
-- district, which gives 3 * 26 * 26 * 26 * 26 = 1,370,928 callsigns for 65,536
-- buildings times 254 machines. Two stations can still collide -- the county is
-- bigger than that -- and a collision is two stations answering to one call,
-- which on the air is exactly what it is: the first one to answer is the one you
-- reached, and there is nothing in AX.25 that arbitrates it either.
function CeroSecOS.callsignFor(b1, b2, n)
	if type(b1) ~= "number" or type(b2) ~= "number" or type(n) ~= "number" then
		return nil
	end
	b1, b2, n = math.floor(b1), math.floor(b2), math.floor(n)
	if b1 < 0 or b1 > 255 or b2 < 0 or b2 > 255 then return nil end
	if n < 1 or n > 254 then return nil end
	local key = b1 * 256 + b2
	local a = math.fmod(key * 25173 + n * 4099 + 13849, 65536)
	local b = math.fmod(key * 40503 + n * 7919 + 12289, 65536)
	if a < 0 then a = a + 65536 end
	if b < 0 then b = b + 65536 end
	local prefix = CeroSecOS.CALL_PREFIXES[math.fmod(a, 3) + 1]
	return prefix .. letterAt(a / 3) .. CeroSecOS.CALL_DISTRICT
		.. letterAt(a / 78) .. letterAt(b) .. letterAt(b / 26)
end

-- The callsign this machine would be given, off its own record. nil for a
-- machine that has no record at all -- one standing in a base somebody built,
-- which has no address and no telephone line either, and for the same reason:
-- there is nothing to derive one from.
function CeroSecOS.defaultCallsign(state)
	local net = CeroSecOS.netRecord(state)
	if net == nil then return nil end
	return CeroSecOS.callsignFor(net.b1, net.b2, net.n)
end

-- What the machine calls itself on the air: the first word of /etc/callsign, if
-- that word is a callsign. nil for a file that is not there, is empty, or holds
-- something no station could be called -- and nil means the machine cannot get
-- on the air at all, which is the honest answer for a station with no licence to
-- announce.
--
-- Read off the FILE and never off the record, which is the difference between
-- this link and the other two: `ifconfig` tells you what the card is and nobody
-- can argue with it, and this tells you what somebody wrote down.
function CeroSecOS.callsignOf(state)
	local node = CeroSecOS.systemNode(state, CeroSecOS.CALLSIGN_PATH)
	if type(node) ~= "table" or node.type ~= "file" then return nil end
	local word = string.match(node.data or "", "^[ \t]*([^ \t\n]+)")
	if word == nil or not CeroSecOS.isCallsign(word) then return nil end
	return word
end

-- The file, made where it is missing and left exactly as it lies where it is
-- not: a callsign a survivor typed is his, and one he deleted stays deleted --
-- the same rule /etc/hosts runs on, and for the same reason.
--
-- Answers true when it wrote one. A machine with no record writes nothing,
-- because there is nothing to derive; it gets its file the moment it learns
-- which building it is standing in (CeroSecNet.identify).
function CeroSecOS.ensureCallsign(state)
	local call = CeroSecOS.defaultCallsign(state)
	if call == nil then return false end
	local etc = CeroSecOS.ensureSystemDir(state, "etc")
	if etc == nil then return false end
	if etc.children.callsign ~= nil then return false end
	etc.children.callsign =
		CeroSecOS.newFile("root", CeroSecOS.CALLSIGN_MODE, CeroSecOS.terminated(call))
	return true
end

--
-- The dial
--

-- The speed of the air, and what the trickle is derived from
-- (CeroSec.RADIO_LINES_PER_S). 1200 baud on two metres is what every TNC of the
-- period did and what the radios in this game are: a 1200-baud AFSK modem
-- keying an ordinary FM voice set.
CeroSecOS.RADIO_BAUD = 1200

-- The frequency as a station writes it: megahertz and three decimals, always
-- three, because a ham writes 144.390 and not 144.39 -- the last digit is the
-- kilohertz and an aerial is tuned in kilohertz.
--
-- The game keeps the channel in kilohertz (DeviceData.getChannel, and the radio
-- UI divides it by a thousand to print MHz: see the head of SCeroSecRadio.lua),
-- so the two halves of this are the whole and the remainder of that division and
-- there is no arithmetic on a fraction anywhere in it.
function CeroSecOS.radioFreqText(channel)
	if type(channel) ~= "number" then return nil end
	channel = math.floor(channel)
	if channel < 0 then return nil end
	local khz = tostring(math.fmod(channel, 1000))
	while #khz < 3 do khz = "0" .. khz end
	return tostring(math.floor(channel / 1000)) .. "." .. khz
end

-- What `cat /dev/radio0` reads: the frequency the knob is on, and what the set
-- is doing. Two facts on one line because they are one answer -- a survivor
-- asking about the radio is asking whether he can get on the air, and neither
-- half of that is any use without the other.
--
-- The three words are the set's own three states and there is no fourth: it is
-- switched on, it is switched off, or it is switched on with nothing behind it
-- -- a ham set off the mains with the county's power gone, or a walkie with a
-- flat battery. They are read off the game and not guessed (SCeroSecRadio.lua).
CeroSecOS.RADIO_OFF = "off"
CeroSecOS.RADIO_ON = "on"
CeroSecOS.RADIO_NO_POWER = "no power"

--
-- WHAT A TUNED SET SAYS BESIDE ITS SWITCH
--
-- `cat /dev/tv0` reads `on channel 203 airing 720-1080`: the switch, the dial,
-- and what the station is doing with the day. The switch is the `state` and
-- everything after it is the `detail`, for the generator's reason -- the listings
-- have a column for a word and not for a sentence, and `dev tv0 toggle` looks its
-- opposite up by the state, which a sentence would have no entry for.
--
-- THE THREE WORDS, AND WHY THERE IS NO FOURTH.
--
--   airing F-T   a broadcast is on that channel now, and that is its block
--   next F-T     nothing now; the next block of the day starts at F
--   idle         nothing now and nothing else today
--
-- and a dial on a frequency no station is on at all says neither: the line ends
-- at the number, because a set on static has nothing to say about a schedule.
--
-- F and T are MINUTES OF THE DAY, which is the unit the engine keeps them in and
-- not a unit of ours: a stamp in RadioData.xml is an integer and the parser reads
-- no date beside it. 1080-1440 is six in the evening to midnight. A program that
-- wants the set on for the show compares `next`'s first number with the clock,
-- which is the whole reason the numbers are here rather than a sentence.
--
-- The words are here, beside the radio's own three, because this is where a set's
-- sentence is built and there is one place for it (CeroSecOS.radioStateText). The
-- READING behind them is the server's and is in SCeroSecRadio.lua, which is the
-- only file that asks the game anything about a radio.
CeroSecOS.TUNER_AIRING = "airing"
CeroSecOS.TUNER_NEXT = "next"
CeroSecOS.TUNER_IDLE = "idle"

function CeroSecOS.tunerDetailText(channel, schedule)
	if type(channel) ~= "number" then return "" end
	local text = "channel " .. tostring(math.floor(channel))
	if type(schedule) ~= "table" then return text end
	local from, to = schedule.from, schedule.to
	if type(from) ~= "number" or type(to) ~= "number" then
		return text .. " " .. CeroSecOS.TUNER_IDLE
	end
	local word = CeroSecOS.TUNER_NEXT
	if schedule.airing then word = CeroSecOS.TUNER_AIRING end
	return text .. " " .. word .. " "
		.. tostring(math.floor(from)) .. "-" .. tostring(math.floor(to))
end

function CeroSecOS.radioStateText(channel, on, powered)
	local freq = CeroSecOS.radioFreqText(channel)
	if freq == nil then return "" end
	if not powered then return freq .. " " .. CeroSecOS.RADIO_NO_POWER end
	if not on then return freq .. " " .. CeroSecOS.RADIO_OFF end
	return freq .. " " .. CeroSecOS.RADIO_ON
end


-- What the TNC says, and it is a different voice again from the commands' and
-- from the modem's: a TNC-2 printed its own lines with three stars in front of
-- them, so that a station could tell the box talking from the man at the other
-- end talking.
--
--   *** CONNECTED to KD4AXR    the link is up: the far TNC answered the connect
--   *** DISCONNECTED           the link is down, whichever end let go
--   *** retry count exceeded   the connect was sent, and resent, and nobody
--                              ever answered
--   *** BUSY                   the far TNC has a link already and will take no
--                              second one
--
-- The fourth is the one string of the four that is not a TNC-2's own spelling: a
-- TNC-2 prints "*** <call> busy", naming the station. This machine prints the
-- bare word, so that the one-line refusal a survivor reads on a radio reads like
-- the one he already knows off the telephone (CeroSecOS.MODEM.busy) -- and
-- because the callsign is on the line above it, in the command he just typed.
--
-- And `eh`, which is the fifth and is the TNC's answer to a line it could not
-- make sense of: "?EH". A TNC-2 has other error lines of its own, and this
-- machine has ONE, deliberately -- a TNC-2's "?EH" is what a wrong word gets,
-- and the alternative to using it for a wrong VALUE as well would be inventing a
-- second string for a box whose second string nobody here can look up.
--
-- What is NOT here: "*** CONNECT REQUEST FROM", which is what the ANSWERING
-- TNC prints for its own operator. The machine at the far end is not a survivor
-- at a TNC, it is a login prompt, and a line announcing a caller to a screen
-- nobody is at would be a line for nobody. What the far machine records instead
-- is the callsign in wtmp, which is where `who` and `last` read it.
CeroSecOS.TNC = {
	connected = "*** CONNECTED to ",
	disconnected = "*** DISCONNECTED",
	retry = "*** retry count exceeded",
	busy = "*** BUSY",
	eh = "?EH",
	-- The same event as `connected`, said on the AIR rather than on the caller's
	-- own screen, and therefore without the station's name on the end of it: the
	-- line anybody listening reads already has both callsigns in front of it
	-- ("KD4AXR de KE4QWZ *** CONNECTED"), and "to KD4AXR" behind them would say
	-- the same thing twice. The disconnect needs no second spelling for the same
	-- reason it needed none on the screen: it never named anybody.
	onAir = "*** CONNECTED",
}

--
-- The TNC as a 1993 operator met it
--
-- `call KD4AXR` was this machine's own command until SYSTEM_VERSION 17 and it
-- was invented: no Unix ever shipped a /bin/call, because packet radio was never
-- a thing the KERNEL did. A TNC was a box on the end of an RS-232 cable with its
-- own firmware, its own command language and its own prompt, and the way a
-- survivor of 1993 reached it was the way he reached any other serial device:
--
--     admin@ksp-04-11:~$ cu -l /dev/radio0
--     CeroSec Systems TNC-200 (TNC-2 compatible)
--     cmd: MYCALL
--     MYCALL KD4AXR
--     cmd: C KE4QWZ
--     *** CONNECTED to KE4QWZ
--     login:
--
-- cu(1) takes `-l line` to name the serial line instead of dialling a number,
-- and that is cu's own flag and not something added here. What is on the other
-- end of the line is then whatever is on it -- a modem, a plotter, another
-- computer, or a TNC -- and cu neither knows nor cares: it is a wire with a
-- keyboard at one end.
--
-- THE TWO THINGS DECLARED. A line under /dev that names a RADIO rather than a
-- tty is this machine's (a real cu is handed /dev/ttya and /etc/remote says what
-- is behind it, and this machine has no /etc/remote and no tty devices); and the
-- banner line is this machine's, because a real TNC-2 printed whatever its
-- vendor's firmware printed and CeroSec Systems is the vendor here. Both are in
-- CeroSecOS.DEVIATIONS and on the manual's "What is not Unix here" page.
--
-- Everything between those two is the TNC-2's own command set, cut to the six
-- commands a survivor needs and no further: MYCALL, CONNECT, DISCONNE, CONV,
-- MHEARD and MHCLEAR, each with the abbreviation the box itself took.
--

-- The line the TNC sits on. It is a device and not a tty, so it is whatever
-- /dev calls this machine's radio -- usually radio0, and `dev radio` says which.
-- The name is kept here so that the command, the manual and the parcours cannot
-- disagree about what a survivor types.
CeroSecOS.TNC_DEV = "/dev/radio0"

-- One line, and no version theatre: a box announced itself once when the cable
-- was opened and then got out of the way.
CeroSecOS.TNC_BANNER = "CeroSec Systems TNC-200 (TNC-2 compatible)"

-- The TNC's own prompt. Lower case with a colon, which is exactly how a TNC-2
-- printed it, and it is the one prompt on this machine that is not the shell's.
CeroSecOS.TNC_PROMPT = "cmd:"

-- What an unprogrammed TNC says its callsign is. The factory value of MYCALL,
-- and the honest answer here: the TNC's battery-backed memory IS /etc/callsign
-- on this machine, so a machine with no such file is a box nobody has programmed.
CeroSecOS.TNC_NOCALL = "NOCALL"

-- How many stations MHEARD remembers. Eighteen is the TNC-2's own depth, and it
-- is RAM in a box: it goes when the power does.
CeroSecOS.MHEARD_MAX = 18

-- The two things the machine says in its own name rather than the TNC's, because
-- neither is anything a TNC could ever have printed: a TNC with no radio on the
-- other end of its microphone cable says nothing at all, and a TNC with no
-- MYCALL set refuses to transmit and says so in its own way. So the program
-- holding the line says the plain thing in cu's own shape -- the command's name,
-- a colon, what is wrong -- exactly as cu does about a building with no
-- telephone (CeroSecOS.CU_NO_LINE).
CeroSecOS.TNC_NO_RADIO = "cu: no radio"
CeroSecOS.TNC_NO_CALLSIGN = "cu: no callsign"

-- And what cu says about a line it cannot open at all, which is the refusal a
-- machine with no set in its room gets before anything is transmitted: cu's own
-- shape again, with the device's own word for a device that is not there (the
-- word `dev` uses, and CeroSecOS.devRead's).
function CeroSecOS.tncNoDevice(line)
	return "cu: " .. tostring(line) .. ": no such device"
end

--
-- MHEARD
--
-- The stations this box has heard since the power came on, most recent first,
-- one line each. A TNC-2 prints the callsign and the time it was last heard when
-- DAYTIME is set, and DAYTIME on this machine is set at power-up off the
-- machine's own clock -- so there is always a time.
--
-- One line per STATION and not per transmission, which is what a TNC's heard
-- list is: a station heard again moves to the top and keeps one line. Eighteen
-- of them, and the nineteenth pushes the oldest off the bottom.
--
-- The list is the MACHINE's and is filled by whoever is running it -- only the
-- world knows which transmissions an aerial can hear -- and the rule for adding
-- one is here, so that the engine and the server cannot disagree about the depth
-- or the order.
--

-- list is the machine's heard list or nil; the answer is the list to keep.
-- Stamped with the GAME's clock in seconds, which is the clock `who` and `last`
-- print: a time on the air is a time in Knox County.
function CeroSecOS.heardAdd(list, call, at)
	if type(call) ~= "string" or not CeroSecOS.isCallsign(call) then return list end
	if type(list) ~= "table" then list = {} end
	-- The same station again is the same line, moved to the top with a new time.
	local kept = {}
	for i = 1, #list do
		if type(list[i]) == "table" and list[i].call ~= call then
			kept[#kept + 1] = list[i]
		end
	end
	local out = { { call = call, at = math.floor(tonumber(at) or 0) } }
	for i = 1, #kept do
		if #out >= CeroSecOS.MHEARD_MAX then break end
		out[#out + 1] = kept[i]
	end
	return out
end

-- The machine's heard list, as the caller handed it over. One read of env, like
-- every other thing the engine is told about the world.
function CeroSecOS.heardOf(env)
	if type(env) ~= "table" or type(env.heard) ~= "table" then return nil end
	return env.heard
end

-- What MHEARD prints: "CALLSIGN  hh:mm", the callsign in the six columns a
-- callsign takes at most and the time behind it. Nothing at all for a box that
-- has heard nothing, which is what a TNC prints for an empty list.
function CeroSecOS.heardLines(list)
	local out = {}
	if type(list) ~= "table" then return out end
	for i = 1, #list do
		local one = list[i]
		if type(one) == "table" and type(one.call) == "string" then
			local p = CeroSecOS.dateParts(one.at or 0)
			local hh, mm = tostring(p.hour), tostring(p.min)
			if #hh < 2 then hh = "0" .. hh end
			if #mm < 2 then mm = "0" .. mm end
			out[#out + 1] = CeroSecOS.padRight(one.call, 6) .. "  " .. hh .. ":" .. mm
		end
	end
	return out
end

--
-- The dialog
--
-- Every line typed at `cmd:` comes back here. It is an ordinary continuation
-- chain -- the same mechanism sudo's password and more's pager run on -- so the
-- job holding the line is asleep between two lines and costs nothing, and the
-- console needs to know nothing about any of it.
--
-- What the engine can decide is everything about the WORDS: which command was
-- typed, whether a callsign is one, whether this box has a MYCALL, and whether
-- the chain is too deep already. Everything about the AIR -- an aerial in reach,
-- a set switched on, the same frequency, the distance, a chunk the server has in
-- memory -- is the world's, so those come back as a link ORDER for whoever is
-- running the machine, exactly as `rlogin` and `cu`'s own dial do.
--
-- THE TNC'S MEMORY IS THE CONTINUATION. A box at `cmd:` with a link up is a
-- different box from one at `cmd:` with none -- D and K mean something to the
-- first and nothing to the second -- and the one thing that knows which is which
-- is the token the prompt was put up with. So the station the link is to travels
-- in the cont, written there by the machine that made the link and by nothing
-- else: the engine cannot invent a link it has not been told about.
--

-- The cont a prompt is put back up with, carrying the link if there is one.
function CeroSecOS.tncCont(to)
	return { cmd = "tnc", to = to }
end

-- The cont the MACHINE hands back when it has done something to the link and the
-- box is to say one line about it and ask again. The line is the TNC's own and is
-- handed in as the answer, because the words for a link that went away are the
-- link layer's (CeroSecOS.TNC.retry and .disconnected are both its).
function CeroSecOS.tncSayCont(to)
	return { cmd = "tnc", say = true, to = to }
end

-- And the one that ends the program: `~.` has hung the line up, so cu says its
-- own last word and the shell comes back.
function CeroSecOS.tncByeCont()
	return { cmd = "tnc", bye = true }
end

-- The prompt, as the order an answer hands back.
local function atCmd(lines, to)
	return true, lines, "tnc",
		{ text = CeroSecOS.TNC_PROMPT, cont = CeroSecOS.tncCont(to) }
end

-- A link order for the machine, with whatever the box printed first.
local function link(lines, op, to, extra)
	local order = { op = op, to = to }
	if type(extra) == "table" then
		for k, v in pairs(extra) do order[k] = v end
	end
	return true, lines, "tnc", { link = order }
end

local function hopsOf(session)
	if type(session) ~= "table" then return 0 end
	local n = tonumber(session.hops)
	if n == nil or n < 0 then return 0 end
	return math.floor(n)
end

-- `cu -l /dev/radio0`: the TNC's command mode on the screen.
--
-- The device is checked HERE and not by the world, because it is a file: /dev is
-- mounted for the length of a command and a radio in the room is a node in it, so
-- a machine with no set has nothing at that name and cu says so without keying
-- anything. A node that is there but is not a radio -- /dev/null, a light switch
-- -- is not a serial line either and gets the same answer, which is the truth
-- about what cu could do with it.
function CeroSecOS.tncOpen(state, session, line, env)
	local node = CeroSecOS.getNode(state, session, line)
	-- "radio" is the kind, spelt as CeroSecOS.DEV_VALUES and CeroSecOS.DEV_MODES
	-- spell it and as the world hands it over (CeroSecRadio.KIND).
	if type(node) ~= "table" or node.type ~= "dev" or node.kind ~= "radio" then
		return false, { CeroSecOS.tncNoDevice(line) }
	end
	-- The banner travels in the ORDER and not as the command's own output: it is
	-- what the box on the end of the line says when the line opens, and a job with
	-- no terminal never opens one (CeroSecOSVM applyControl, which prints it once it
	-- has let the order through).
	return true, {}, "tnc", { lines = { CeroSecOS.TNC_BANNER },
		text = CeroSecOS.TNC_PROMPT, cont = CeroSecOS.tncCont(nil) }
end

-- MYCALL, shown and set.
--
-- Shown the way a TNC-2 shows any of its parameters: the name, a space, the
-- value. Set the way this machine sets anything -- the file, through the
-- filesystem, with the session's own authority -- so /etc/callsign being root's
-- and 644 is the whole of the rule and there is no second one written here. A
-- refusal is the one the write itself gave, signed by the program holding the
-- line, because a TNC has nothing to say about a Unix permission.
local function myCall(state, session, cont, word)
	if word == nil then
		local mine = CeroSecOS.callsignOf(state)
		if mine == nil then mine = CeroSecOS.TNC_NOCALL end
		return atCmd({ "MYCALL " .. mine }, cont.to)
	end
	-- Capitals, because a callsign is written and sent in capitals, and a TNC-2
	-- upper-cased what you typed at it.
	local call = string.upper(word)
	if not CeroSecOS.isCallsign(call) then return atCmd({ CeroSecOS.TNC.eh }, cont.to) end
	-- Through the filesystem, with the session's own authority: the file is
	-- root's and 644, so an ordinary account is refused by the same rule that
	-- refuses it the editor. A machine that has no such file at all gets one made,
	-- which is what programming a box's memory is -- and only root may, /etc
	-- being root's directory.
	local done, why = CeroSecOS.writeFile(state, session,
		CeroSecOS.CALLSIGN_PATH, CeroSecOS.terminated(call), false, nil)
	if done == nil then
		return atCmd({ "cu: " .. CeroSecOS.CALLSIGN_PATH .. ": " ..
			tostring(why) }, cont.to)
	end
	return atCmd({ "MYCALL " .. call }, cont.to)
end

-- CONNECT, up to the point where the world has to be asked.
local function connect(state, session, cont, word)
	if word == nil then return atCmd({ CeroSecOS.TNC.eh }, cont.to) end
	local call = string.upper(word)
	if not CeroSecOS.isCallsign(call) then return atCmd({ CeroSecOS.TNC.eh }, cont.to) end
	-- A box that has a link already. A TNC-2 will not open a second one and this
	-- is the one answer it has for a command it cannot carry out.
	if cont.to ~= nil then return atCmd({ CeroSecOS.TNC.eh }, cont.to) end
	-- A station with no callsign may not transmit. It is the first thing asked of
	-- the disk because it is the one refusal that is about this machine rather
	-- than about the air: a licence is not something the world can be asked about.
	local mine = CeroSecOS.callsignOf(state)
	if mine == nil then return atCmd({ CeroSecOS.TNC_NO_CALLSIGN }, nil) end
	-- Calling oneself. The TNC would key the transmitter and then hear its own
	-- connect request come back, which is not something AX.25 has an answer for;
	-- what a station actually gets is silence, and silence is the retry count
	-- running out. (There is no loopback on a radio. `rlogin localhost` is the
	-- command for a second session on this machine.)
	if call == mine then return atCmd({ CeroSecOS.TNC.retry }, nil) end
	-- The same ceiling rlogin and cu pay: every hop is a shell held open on a
	-- third machine's budget. What a chain at the ceiling gets is the TNC's word
	-- for a link it will not open, because on the air it is the TNC that talks.
	if hopsOf(session) >= CeroSecOS.HOP_MAX then
		return atCmd({ CeroSecOS.TNC.busy }, nil)
	end
	return link({}, "connect", call,
		{ call = call, user = CeroSecOS.userOf(session),
			from = CeroSecOS.userOf(session), hops = hopsOf(session) + 1 })
end

-- Which TNC command a line is. Case does not matter -- a TNC-2 took either --
-- and the abbreviations are the box's own: C, D, K, MH. A bare `MH` is MHEARD
-- and `MHC` is not: MHCLEAR is spelt out here, because a list a survivor cannot
-- get back is not something to lose to a typing slip.
local TNC_WORDS = {
	MYCALL = "mycall", MY = "mycall",
	CONNECT = "connect", C = "connect",
	DISCONNE = "disconnect", D = "disconnect",
	CONV = "converse", K = "converse",
	MHEARD = "mheard", MH = "mheard",
	MHCLEAR = "mhclear",
}

CeroSecOS.continuations.tnc = function(state, session, cont, line, env)
	if type(cont) ~= "table" then return false, { CeroSecOS.CU_DISCONNECTED } end
	-- cu's own last word, and the end of the program: the line has been hung up
	-- by the time this runs.
	if cont.bye then return true, { CeroSecOS.CU_DISCONNECTED } end
	-- Something the machine did to the link, said in the TNC's own words: they
	-- come in as the answer, because the link layer is what has them.
	if cont.say then
		local out = {}
		if type(line) == "string" and line ~= "" then out[1] = line end
		return atCmd(out, cont.to)
	end
	if type(line) ~= "string" then line = "" end
	-- An empty line at cmd: is a TNC printing its prompt again, and nothing else.
	local word, rest = string.match(line, "^[ \t]*(%S+)[ \t]*(.-)[ \t]*$")
	if word == nil then return atCmd({}, cont.to) end
	-- `~.` is cu's, not the TNC's: it is read by the program holding the line and
	-- never sent down it, which is what a tilde escape IS. A link still up is hung
	-- up first -- the machine does that -- and then cu says Disconnected.
	if CeroSecOS.isCuEscape(line) then
		if cont.to ~= nil then return link({}, "hangup", cont.to) end
		return true, { CeroSecOS.CU_DISCONNECTED }
	end
	local what = TNC_WORDS[string.upper(word)]
	if rest == "" then rest = nil end
	if what == nil then return atCmd({ CeroSecOS.TNC.eh }, cont.to) end
	if what == "mycall" then return myCall(state, session, cont, rest) end
	if what == "connect" then return connect(state, session, cont, rest) end
	if what == "disconnect" then
		-- A box with no link says the same line: DISCONNE is "let go of whatever
		-- you are holding", and a box holding nothing has let go.
		if cont.to == nil then return atCmd({ CeroSecOS.TNC.disconnected }, nil) end
		return link({ CeroSecOS.TNC.disconnected }, "drop", cont.to)
	end
	if what == "converse" then
		if cont.to == nil then return atCmd({ CeroSecOS.TNC.disconnected }, nil) end
		return link({}, "conv", cont.to)
	end
	if what == "mheard" then
		return atCmd(CeroSecOS.heardLines(CeroSecOS.heardOf(env)), cont.to)
	end
	-- MHCLEAR: the box's own RAM, emptied where it lies. The list belongs to the
	-- machine and is handed in by reference, which is how `kill` reaches a job it
	-- was handed the same way -- the engine holds no state of its own either way.
	local heard = CeroSecOS.heardOf(env)
	if heard ~= nil then
		for i = #heard, 1, -1 do heard[i] = nil end
	end
	return atCmd({}, cont.to)
end
