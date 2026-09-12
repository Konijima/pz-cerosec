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
-- somebody else's screen. That is exactly what this rung is. The command here is
-- spelt `call` and not `c`, because `c` is a word inside the TNC's own command
-- mode and this machine has no TNC command mode to be in -- the TNC is a device
-- under /dev and the shell is the only prompt there is. The lines it prints back
-- are the TNC's own, unchanged (CeroSecOS.TNC).
--
-- WHAT IS THE ENGINE'S HALF. The callsign and the file it lives in, the shape of
-- a callsign, the frequency as a reader of a radio dial writes it, the TNC's four
-- lines, and the `call` command up to the point where it has to ask the world
-- whether anybody can hear it. Everything about aerials, channels, distance and
-- power is the world's and is in SCeroSecRadio.lua, which is also where every
-- game call it makes is proved.
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
function CeroSecOS.isCallsign(text)
	if type(text) ~= "string" then return false end
	return string.match(text, "^[KNW]%u?%d%u%u%u?$") ~= nil
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

local function letterAt(n)
	return string.char(65 + math.fmod(math.floor(n), 26))
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
		CeroSecOS.newFile("root", CeroSecOS.CALLSIGN_MODE, call)
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
	-- The same event as `connected`, said on the AIR rather than on the caller's
	-- own screen, and therefore without the station's name on the end of it: the
	-- line anybody listening reads already has both callsigns in front of it
	-- ("KD4AXR de KE4QWZ *** CONNECTED"), and "to KD4AXR" behind them would say
	-- the same thing twice. The disconnect needs no second spelling for the same
	-- reason it needed none on the screen: it never named anybody.
	onAir = "*** CONNECTED",
}

-- The two things the machine says in its own name rather than the TNC's, because
-- neither is anything a TNC could ever have printed: a TNC with no radio on the
-- other end of its microphone cable says nothing at all, and a TNC with no
-- MYCALL set refuses to transmit and says so in its own command mode. So the
-- machine says the plain thing in `call`'s own shape -- the command's name, a
-- colon, what is wrong -- exactly as cu does about a building with no telephone.
CeroSecOS.CALL_NO_RADIO = "call: no radio"
CeroSecOS.CALL_NO_CALLSIGN = "call: no callsign"

--
-- call
--
-- The fifth command that reaches another computer, and the same SHAPE as the
-- other four on purpose: a session on the far machine, on this glass, ending at
-- its own login prompt. A survivor who can use rlogin can use this, which is
-- what "a new link and not a new command to learn" has meant since the telephone.
--
-- It takes a CALLSIGN and not a host name and not a number, because on the air
-- there is nothing else to take: /etc/hosts maps names to addresses and an
-- address is a building, and a station on a mountain twenty miles away has
-- neither. The callsign IS the address, and it is the far machine's own file
-- that says what it is.
--
-- No trust file is asked, and this time it is not merely that the files name
-- machines: a callsign is a file root can write, so a machine that trusted one
-- would be a machine that trusted a string anybody with a radio can choose. The
-- password is asked every time.
--
-- What the engine can decide: whether the word is a callsign at all, whether
-- this machine has one, and how deep the chain already is. Whether anybody can
-- hear it -- an aerial in reach, a set switched on, the same frequency, the
-- distance, a chunk the server has in memory -- is the world's, and the TNC's
-- words for it come back from the link layer.
--

local commands = CeroSecOS.commands

local function usage(cmd)
	return false, { cmd .. ": usage: " .. (CeroSecOS.commandUsage(cmd) or cmd) }
end

local function hopsOf(session)
	if type(session) ~= "table" then return 0 end
	local n = tonumber(session.hops)
	if n == nil or n < 0 then return 0 end
	return math.floor(n)
end

commands.call = function(state, session, args, env)
	if #args ~= 2 then return usage("call") end
	if not CeroSecOS.isCallsign(args[2]) then return usage("call") end
	-- A station with no callsign may not transmit. It is the first thing asked
	-- because it is the plainest, and because it is the one refusal that is about
	-- this machine's disk rather than about the air: a licence is not something
	-- the world can be asked about.
	local mine = CeroSecOS.callsignOf(state)
	if mine == nil then return false, { CeroSecOS.CALL_NO_CALLSIGN } end
	-- Calling oneself. The TNC would key the transmitter and then hear its own
	-- connect request come back, which is not something AX.25 has an answer for;
	-- what a station actually gets is silence, and silence is the retry count
	-- running out. (There is no loopback on a radio. `rlogin localhost` is the
	-- command for a second session on this machine.)
	if args[2] == mine then return false, { CeroSecOS.TNC.retry } end
	-- The same ceiling rlogin and cu pay: every hop is a shell held open on a
	-- third machine's budget. What a chain at the ceiling gets is the TNC's word
	-- for a link it will not open, because on the air it is the TNC that talks.
	if hopsOf(session) >= CeroSecOS.HOP_MAX then
		return false, { CeroSecOS.TNC.busy }
	end
	return true, { }, "call", { call = args[2], user = CeroSecOS.userOf(session),
		from = CeroSecOS.userOf(session), hops = hopsOf(session) + 1 }
end
