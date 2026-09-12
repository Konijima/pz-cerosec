--
-- CeroSec OS core: the network.
--
-- A machine on this rung has one wire in it and it is Ethernet: a length of
-- coax between the computers of ONE building, which is the network a 1993
-- office had. There is no router, no gateway and no name server -- names are
-- resolved out of /etc/hosts, exactly as they were before BIND was on every
-- desk, and a machine in the building across the street is not reachable at
-- all. Later rungs add the phone line and the radio; they add LINKS and not
-- commands, which is the promise the manual makes.
--
-- What is in this file is everything about the network that does not know there
-- is a game: the four files (/etc/hosts, /etc/hosts.equiv, ~/.rhosts and
-- /var/log/wtmp), the arithmetic that turns a building and a machine number
-- into an address, the shape of every line ping, ruptime, rwho, who and last
-- print, and the pty table a remote session lives in.
--
-- What is NOT here is the link itself. Whether two machines can hear each other
-- is a question about the world -- which building a computer stands in, whether
-- it has power -- and it is answered by the server (SCeroSecNet.lua) and handed
-- in as env.net, the same way the devices under /dev are handed in as
-- env.devices. The engine renders what it is told and judges what it is asked;
-- it never reaches out.
--
-- The addresses are 10.<b1>.<b2>.<n>: the ten-dot network is the one RFC 1597
-- set aside for a site with no business on the Internet, which is what a Knox
-- County office is. b1 and b2 come from where the building stands on the map
-- and n is which computer of that building this is, so the address is a fact
-- about the hardware and nobody can type a new one -- there is no ifconfig that
-- sets anything here, and the manual says why.
--

CeroSecOS = CeroSecOS or {}
CeroSecOS.commands = CeroSecOS.commands or {}

--
-- Where it all lives
--

-- hosts(5): "internet-address official-host-name aliases". Readable by
-- everybody -- it is how a name becomes an address and there is no secret in
-- one -- and writable by root, which is the mode a real one wears.
CeroSecOS.HOSTS_PATH = "/etc/hosts"
CeroSecOS.HOSTS_MODE = 644

-- hosts.equiv(5): the machines and accounts this one trusts, one a line. Same
-- mode, and for the same reason: everybody may read who is trusted, and only
-- root may change it.
CeroSecOS.EQUIV_PATH = "/etc/hosts.equiv"
CeroSecOS.EQUIV_MODE = 644

-- The account's own half of the same list, in its own home. 600, and rlogind
-- IGNORES it when it is not the account's own file or when anybody but the
-- owner may write it -- a trust file somebody else can edit is a trust file
-- somebody else wrote (see CeroSecOS.rhostsOk).
CeroSecOS.RHOSTS_NAME = ".rhosts"
CeroSecOS.RHOSTS_MODE = 600

-- wtmp. In Unix this is a file of binary utmp records and there is therefore no
-- text format to be faithful to, so this one is five fields and a word:
--
--     in admin ttyp0 gate 741186720
--     out admin ttyp0 gate 741187020
--
-- the kind, the account, the line it was on, where it came from ("-" for one
-- that came from nowhere, which is the machine's own console) and the moment,
-- as the one number the whole engine keeps time in. `last` reads it and nothing
-- else does. Bounded by lines and by bytes and exempt from the disk quota by
-- its path, exactly as /var/log/cron is: a machine must not fill its own disk
-- with what it said about itself while nobody was looking.
CeroSecOS.WTMP_PATH = "/var/log/wtmp"
CeroSecOS.WTMP_MODE = 644
CeroSecOS.WTMP_LINES = 200
CeroSecOS.WTMP_BYTES = 8192

-- The name of the line a survivor standing at the machine is logged in on. Not
-- a pty: he is at the keyboard, and `who` has called that the console since
-- there were consoles.
CeroSecOS.CONSOLE_LINE = "console"

-- The pseudo-terminals a remote session lands on, and how many there are.
-- ttyp0..ttyp3 is BSD's own spelling, and four is what this machine has: a
-- number, because every inbound session is a shell on somebody else's budget
-- and a machine with no ceiling on them is a machine anybody can fill.
CeroSecOS.PTY_PREFIX = "ttyp"
CeroSecOS.PTY_MAX = 4

-- How many rlogins deep a chain may go. Two, so that a survivor can reach the
-- machine behind the machine and no further: every hop is a shell held open on
-- a third machine's budget, and a chain nobody bounded is a loop somebody can
-- build out of two computers.
CeroSecOS.HOP_MAX = 2

--
-- The address
--

-- The network the addresses live on. Ten, which is the one RFC 1597 (March
-- 1994, and the practice long before it) set aside for a site that is not on
-- the Internet.
CeroSecOS.NET_PREFIX = 10

-- The loopback, and the name every hosts file has had on its first line since
-- there were hosts files.
CeroSecOS.LOOPBACK_ADDR = "127.0.0.1"
CeroSecOS.LOOPBACK_NAME = "localhost"

-- One round of the linear congruential generator every key and every number on
-- this rung is scattered with: a multiply-add modulo 2^16, which a double holds
-- exactly, with the multiplier 25173 and the increment 13849 -- a generator that
-- has been in print since the eighties. One place, because a second copy of it is
-- a second answer waiting to happen.
local function scatter(x)
	local h = math.fmod(x * 25173 + 13849, 65536)
	if h < 0 then h = h + 65536 end
	return h
end

-- Two bytes out of where the building stands, so that every computer in one
-- building agrees about the first three numbers of its address and two
-- buildings almost never do.
--
-- It is a hash and not the coordinates themselves: a map coordinate is five
-- digits and the low byte of one would put the office next door on the same
-- network as this one every time the map's own grid lined up. Knuth's golden
-- ratio on one axis and an odd prime on the other, taken modulo 2^16 -- which
-- is arithmetic a double holds exactly, the way the password hash's mul() has
-- to split a product and this does not.
--
-- Deterministic and nothing else: the same building answers the same two bytes
-- on every machine, on every load, for ever. That is the whole requirement --
-- two buildings that collide are two buildings with no wire between them, and
-- nothing on this rung routes.
function CeroSecOS.buildingKey(bx, by)
	if type(bx) ~= "number" or type(by) ~= "number" then return nil end
	bx = math.floor(bx)
	by = math.floor(by)
	local h = math.fmod(bx * 40503 + by * 12289, 65536)
	if h < 0 then h = h + 65536 end
	return math.floor(h / 256), math.fmod(h, 256)
end

-- And the same two bytes for a premises INSIDE a building, which is what a shop in
-- a mall is: the corner hashed exactly as a building corner is, then the SIZE
-- folded in and the whole thing put through one more round.
--
-- The extra round is what keeps a shop apart from the building it is in: a zone
-- often starts at the building's own corner, and without it the coffee shop in the
-- corner of the mall would share the mall's key -- which is the very thing this is
-- here to stop. The size is in the hash because two zones can start on one tile
-- (a shop and the mall-wide zone above it) and only their outlines differ.
--
-- Deterministic and nothing else, exactly as buildingKey is: the same zone answers
-- the same two bytes on every load, for ever. Two premises that collide are two
-- premises with no wire between them and one telephone line between them, which is
-- a party line and is documented as one.
function CeroSecOS.premisesKey(zx, zy, zw, zh)
	if type(zx) ~= "number" or type(zy) ~= "number" then return nil end
	if type(zw) ~= "number" or type(zh) ~= "number" then return nil end
	local corner = math.fmod(math.floor(zx) * 40503 + math.floor(zy) * 12289, 65536)
	local size = math.fmod(math.floor(zw) * 40503 + math.floor(zh) * 12289, 65536)
	local h = math.fmod(corner + size, 65536)
	if h < 0 then h = h + 65536 end
	h = scatter(h)
	return math.floor(h / 256), math.fmod(h, 256)
end

-- The address as it is written and as it is read. One place, so that ifconfig,
-- the BIOS line, /etc/hosts and ping cannot drift into four spellings.
function CeroSecOS.addressText(b1, b2, n)
	if type(b1) ~= "number" or type(b2) ~= "number" or type(n) ~= "number" then
		return nil
	end
	return CeroSecOS.NET_PREFIX .. "." .. math.floor(b1) .. "." .. math.floor(b2)
		.. "." .. math.floor(n)
end

-- Is this a dotted quad? Four numbers under 256, which is what a hosts file may
-- carry and what a player may type at ping.
function CeroSecOS.isAddress(text)
	if type(text) ~= "string" then return false end
	local a, b, c, d = string.match(text, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if a == nil then return false end
	local parts = { a, b, c, d }
	for i = 1, 4 do
		-- A leading zero is not a quad: 010 is octal in every resolver ever
		-- written, and a machine that read it as ten would be a machine that
		-- disagreed with the file it was reading.
		if #parts[i] > 1 and string.sub(parts[i], 1, 1) == "0" then return false end
		local v = tonumber(parts[i])
		if v == nil or v > 255 then return false end
	end
	return true
end

-- The machine's own record: which building it is on and which computer of it
-- this is. Kept in the state and therefore saved, because an address has to
-- outlive a reload AND has to be answerable for a machine whose part of the
-- world nobody has loaded -- the whole point of this rung is that the server
-- holds every computer's disk whether its chunk is in memory or not.
--
-- Read through here and never off the field, exactly as a node's group and its
-- mtime are: a forged save must be a machine with no address and never a
-- machine with half of one.
function CeroSecOS.netRecord(state)
	if type(state) ~= "table" then return nil end
	local net = state.net
	if type(net) ~= "table" then return nil end
	local b1, b2, n = net.b1, net.b2, net.n
	if type(b1) ~= "number" or type(b2) ~= "number" or type(n) ~= "number" then
		return nil
	end
	if b1 ~= math.floor(b1) or b1 < 0 or b1 > 255 then return nil end
	if b2 ~= math.floor(b2) or b2 < 0 or b2 > 255 then return nil end
	-- 0 is the network itself and 255 is the broadcast: neither is a machine.
	if n ~= math.floor(n) or n < 1 or n > 254 then return nil end
	-- And the fourth number, which is the telephone exchange and is OPTIONAL: every
	-- machine of every save written before the line became the modem's own carries
	-- three numbers and not four, and such a machine has no telephone at all until
	-- the record is made again where it stands (CeroSecNet.identify). One that is
	-- THERE has to be an exchange -- a value in the field that is not one is a
	-- forged save and not a machine with half a record, which is the rule the three
	-- above already run on.
	local ex = net.ex
	if ex ~= nil then
		if type(ex) ~= "number" or ex ~= math.floor(ex) then return nil end
		if ex < CeroSecOS.PHONE_EXCHANGE_MIN or ex > CeroSecOS.PHONE_EXCHANGE_MAX then
			return nil
		end
	end
	-- And what the PREMISES is called, which is optional twice over: a machine whose
	-- premises is the building it stands in has no name to carry, and so has every
	-- machine saved before the line belonged to the premises. A value that is there
	-- has to be a name a screen can carry -- a string, inside one line, with no
	-- control bytes in it -- because it is printed by the firmware and by nothing
	-- that could sanitise it later.
	local pz = net.pz
	if pz ~= nil then
		if type(pz) ~= "string" or pz == "" then return nil end
		if #pz > CeroSecOS.COLS then return nil end
		if CeroSecOS.hasControlBytes(pz) then return nil end
	end
	return { b1 = b1, b2 = b2, n = n, ex = ex, pz = pz,
		wrote = net.wrote and true or false }
end

-- The machine's own address, or nil for a machine with no wire in it -- one in a
-- player-built base, which is no map building and has no Ethernet on this rung.
function CeroSecOS.address(state)
	local net = CeroSecOS.netRecord(state)
	if net == nil then return nil end
	return CeroSecOS.addressText(net.b1, net.b2, net.n)
end

-- The record, written. The server is the only caller: it is the half that knows
-- which building a computer stands in and which machines are already on the
-- wire, and it hands over the numbers it has worked out.
--
-- ex is the telephone exchange, and it may be left out: a machine that gets a
-- record with no exchange in it is a machine with an address and no telephone,
-- which is what every save written before the line became the modem's own has
-- until the server sees the building again.
-- pz is what the premises is called, and may be left out: a machine whose premises
-- is the building it stands in has nothing to be called.
function CeroSecOS.setNetRecord(state, b1, b2, n, ex, pz)
	if type(state) ~= "table" then return nil end
	if CeroSecOS.addressText(b1, b2, n) == nil then return nil end
	local record = { b1 = math.floor(b1), b2 = math.floor(b2), n = math.floor(n) }
	if ex ~= nil then
		if type(ex) ~= "number" then return nil end
		ex = math.floor(ex)
		if ex < CeroSecOS.PHONE_EXCHANGE_MIN or ex > CeroSecOS.PHONE_EXCHANGE_MAX then
			return nil
		end
		record.ex = ex
	end
	-- A name that will not do is DROPPED and the record is still written: the
	-- premises is the two bytes and the name is a label, so a zone somebody called
	-- something unprintable is a premises with no name and never a machine with no
	-- line. Refusing the record here would take the telephone away over a word.
	if type(pz) == "string" and pz ~= "" and #pz <= CeroSecOS.COLS
			and not CeroSecOS.hasControlBytes(pz) then
		record.pz = pz
	end
	state.net = record
	return CeroSecOS.netRecord(state)
end

--
-- The phone line
--
-- ONE LINE PER PREMISES, which is the one fact everything below follows from. It
-- was one line per BUILDING, and a building is the wrong unit: a shopping mall is
-- ONE BuildingDef with thirty shops in it, so thirty businesses shared one number
-- and one modem -- and only the lowest-numbered computer of the whole mall could
-- ever be rung, the rest being unreachable by telephone for as long as they stood
-- there. A house is a building and is one premises; a mall is a building and is
-- thirty.
--
-- WHAT A PREMISES IS, and the map really does say. Map designers tag the shops
-- inside a mall with named zones of type ZombiesType -- "CoffeeShop", 17 by 11, at
-- 12858,1329 -- so a shop has an outline in the map data even though no RoomDef
-- says whose shop it is (a RoomDef's name is a LOOT TYPE, "clothsstore", and not a
-- tenancy). The rule is therefore:
--
--   the premises is the named ZombiesType zone containing the machine's square
--   whose area is strictly SMALLER than the building's own footprint; the
--   smallest such zone when several qualify; and otherwise the building.
--
-- The area test is what keeps a house one line: the named zones a house sits in
-- are the town-sized ones -- a suburb, a district -- and a zone bigger than the
-- building it covers is not a tenancy inside it. A zone exactly the building's
-- size is the building by another name and loses on the same test. So on the map
-- that ships, almost every machine is where it was and only a mall changes.
--
-- The premises decides BOTH links: the telephone number and the Ethernet segment
-- come off the same two bytes, so two shops in a mall are two lines and two
-- lengths of coax -- which is what two businesses in one building had.
--
-- The engine does not do any of that looking: which zones lie on a square is a
-- question about the world, so it is the server's (CeroSecNet.premisesOf) and what
-- arrives here is the two bytes it decided on. What IS here is the arithmetic.
--
-- The number is NNN-NNNN, seven digits, which is what a call inside one area code
-- was dialled as in 1993.
--
-- THE EXCHANGE is the first three, and it is a fact about the TOWN. A central
-- office served a place -- one switch in one building, and every subscriber wired
-- back to it -- so the numbers of one town share their first three digits and a
-- town down the road does not. Here the "town" is the map region the premises
-- stands in: the PHONE_REGION-tile square its corner falls in, hashed. A region
-- and not the game's own 300-tile cell, deliberately -- a cell is smaller than
-- Rosewood and every town would be three exchanges -- and not a real-world
-- office-code table either, because Knox County is not a real place. 200 to 999:
-- a central-office code could not begin with 0 or 1 in the North American plan of
-- 1993, those being the operator and the long-distance prefix.
--
-- THE FOUR DIGITS are the subscriber, and they come off the premises key -- the two
-- bytes b1 and b2 the address's middle is made of -- and off nothing else. Which is
-- the whole reason they are derived from the RECORD and not from the coordinates: a
-- number has to be answerable for a machine whose chunk nobody has loaded, and what
-- such a machine has on its disk is its record.
--
-- The exchange is the one thing that cannot be: a region is a coordinate, and the
-- record does not carry one. So the record carries the EXCHANGE instead -- one
-- field, written when the machine learns where it is standing, at the one moment
-- its chunk is certainly loaded. A machine saved before this carries the building
-- bytes and no exchange, and has no telephone at all until the server sees its
-- square again, which is the next time it is switched on or a window is opened on
-- it. The BIOS line is empty until then, and the manual says so.
--
-- THE SCATTER. Both halves go through the same generator: a multiply-add modulo
-- 2^16 with the multiplier 25173 and the increment 13849, which is a linear
-- congruential generator that has been in print since the eighties and is exact in
-- a double. It matters: without it two premises a street apart, whose keys are near
-- each other, would have consecutive telephone numbers, and a county where
-- 555-0416 is next door to 555-0417 is a county whose numbers look invented. The
-- 16-bit result is SCALED onto the range rather than taken modulo it: a modulo
-- would make everything under 5536 a seventh likelier than everything above it,
-- and the multiplication is exact (65535 * 10000 is well under 2^53).
--
-- COLLISIONS, and they are a PARTY LINE. Ten thousand subscriber numbers to a
-- region, so two premises of one region can land on one number -- and when they do,
-- the lowest n answers, every time, exactly as it does for the several machines of
-- ONE premises. That is not a fault to fix here: two subscribers on one line is a
-- party line, which is what a rural exchange sold in 1993, and there is nothing on
-- this rung that routes. A call is placed to a number and the machine that answers
-- is the machine that answers. The manual says so in those words.
--

-- How long a number is, and what an exchange may be.
CeroSecOS.PHONE_DIGITS = 4
CeroSecOS.PHONE_NUMBERS = 10000
CeroSecOS.PHONE_EXCHANGE_MIN = 200
CeroSecOS.PHONE_EXCHANGE_MAX = 999

-- How big a region one central office serves, in tiles.
CeroSecOS.PHONE_REGION = 1024

-- The speed of the line, which is what the modem reports when it has one and
-- what the trickle is derived from (CeroSec.PHONE_LINES_PER_S).
CeroSecOS.PHONE_BAUD = 2400

-- Where the building stands -> which central office it is wired to, as the three
-- digits themselves. nil for anything that is not a pair of map coordinates.
--
-- Asked of the CORNER of the BuildingDef, which is the very coordinate the address
-- is hashed out of, so that every computer of one building agrees about its
-- exchange even when the building straddles two regions.
function CeroSecOS.phoneExchange(bx, by)
	if type(bx) ~= "number" or type(by) ~= "number" then return nil end
	local cx = math.floor(math.floor(bx) / CeroSecOS.PHONE_REGION)
	local cy = math.floor(math.floor(by) / CeroSecOS.PHONE_REGION)
	-- Folded into one number the way a building key is -- 256 and not 65536, because
	-- the generator is modulo 2^16 and a multiplier of 65536 would leave the whole
	-- of cx out of the answer -- and scattered twice for the reason the subscriber
	-- digits are: two towns side by side must not be 418 and 419. 256 is room for a
	-- map 262144 tiles across, which is eighteen times the one that ships.
	local h = scatter(scatter(math.fmod(cx, 256) * 256 + math.fmod(cy, 256)))
	local span = CeroSecOS.PHONE_EXCHANGE_MAX - CeroSecOS.PHONE_EXCHANGE_MIN + 1
	return CeroSecOS.PHONE_EXCHANGE_MIN + math.floor(h * span / 65536)
end

-- The premises key -> the four subscriber digits, as a number 0..9999. nil for
-- anything that is not a key.
--
-- The key is b1 * 256 + b2, which is the very 16-bit number the premises key was
-- worked out as; one round of the scatter above puts adjacent keys nowhere near
-- each other.
function CeroSecOS.phoneKey(b1, b2)
	if type(b1) ~= "number" or type(b2) ~= "number" then return nil end
	b1 = math.floor(b1)
	b2 = math.floor(b2)
	if b1 < 0 or b1 > 255 or b2 < 0 or b2 > 255 then return nil end
	local h = scatter(b1 * 256 + b2)
	return math.floor(h * CeroSecOS.PHONE_NUMBERS / 65536)
end

-- The number as it is written, and the one place it is written: the BIOS line,
-- cu, who and last all read it out of here.
function CeroSecOS.phoneText(ex, n)
	if type(ex) ~= "number" or type(n) ~= "number" then return nil end
	ex = math.floor(ex)
	n = math.floor(n)
	if ex < CeroSecOS.PHONE_EXCHANGE_MIN or ex > CeroSecOS.PHONE_EXCHANGE_MAX then
		return nil
	end
	if n < 0 or n >= CeroSecOS.PHONE_NUMBERS then return nil end
	local digits = tostring(n)
	while #digits < CeroSecOS.PHONE_DIGITS do digits = "0" .. digits end
	return tostring(ex) .. "-" .. digits
end

-- This machine's line, or nil for a machine that has none: one in no building at
-- all, and one whose record was written before the line belonged to the modem. The
-- same record the address is read out of, so the two answers can never disagree
-- about whether the computer is in a building.
function CeroSecOS.phoneOf(state)
	local net = CeroSecOS.netRecord(state)
	if net == nil or net.ex == nil then return nil end
	return CeroSecOS.phoneText(net.ex, CeroSecOS.phoneKey(net.b1, net.b2))
end

-- What the PREMISES is called, when the map named it and the name is one a screen
-- can carry: the zone a shop in a mall is tagged with. nil for a machine whose
-- premises is the building it stands in, which is every machine in a house.
--
-- It is a label and nothing else -- no link reads it, nothing is keyed by it, and
-- two shops with one name are still two premises because the KEY is the outline and
-- not the word. Announced by the firmware beside the number, because a survivor in
-- a mall with thirty lines in it needs to know which one he is sitting at.
function CeroSecOS.premisesOf(state)
	local net = CeroSecOS.netRecord(state)
	if net == nil then return nil end
	return net.pz
end

-- The BIOS's telephone line, which is the number and the premises behind it when
-- there is one. One place, so the firmware cannot drift from what `cu` reads.
--
-- The name is dropped rather than truncated when the whole line will not fit the
-- screen: a BIOS line cut off in the middle is worse than one that says only the
-- number, and the number is the half a survivor has to write down.
function CeroSecOS.phoneLine(state)
	local tel = CeroSecOS.phoneOf(state)
	if tel == nil then return nil end
	local name = CeroSecOS.premisesOf(state)
	if name == nil then return tel end
	local long = tel .. " (" .. name .. ")"
	if #CeroSec.BOOT_PHONE + #long > CeroSecOS.COLS then return tel end
	return long
end

-- Is that a number somebody could dial? Three digits, a hyphen and four digits and
-- nothing else -- and the first of them is 2 to 9, because a central-office code
-- could not begin with 0 or 1. There is no long distance in Knox County and no
-- operator to ask, so a word that is not this shape is not a telephone number.
function CeroSecOS.isPhoneNumber(text)
	if type(text) ~= "string" then return false end
	local ex, digits = string.match(text, "^([2-9]%d%d)%-(%d%d%d%d)$")
	if ex == nil or digits == nil then return false end
	local n = tonumber(ex)
	return n >= CeroSecOS.PHONE_EXCHANGE_MIN and n <= CeroSecOS.PHONE_EXCHANGE_MAX
end

--
-- /etc/hosts
--
-- hosts(5), and it is the PLAYER's file. The machine writes its own line into
-- it exactly once -- the first time it learns its address -- and never touches
-- it again: a name a survivor put in it is a name he can keep, and a line he
-- deleted stays deleted. Every name on this machine is resolved through it and
-- through nothing else, which is what makes `rlogin gate` a thing somebody had
-- to write down first.
--

-- One line -> { addr, names }, or nil. A "#" anywhere begins a comment, which
-- is what every resolver's parser does with one.
function CeroSecOS.parseHostsLine(line)
	if type(line) ~= "string" then return nil end
	local hash = string.find(line, "#", 1, true)
	if hash ~= nil then line = string.sub(line, 1, hash - 1) end
	local words = {}
	for word in string.gmatch(line, "[^ \t]+") do words[#words + 1] = word end
	if #words < 2 then return nil end
	if not CeroSecOS.isAddress(words[1]) then return nil end
	local names = {}
	for i = 2, #words do
		-- A host name obeys the machine's own name rule, which is the rule a
		-- hostname on it has to obey anyway: a line naming something no
		-- /etc/hostname could ever hold would be a name nothing answers to.
		if not CeroSecOS.isValidHostname(words[i]) then return nil end
		names[#names + 1] = words[i]
	end
	return { addr = words[1], names = names }
end

-- text -> the entries in the order the file has them, plus a name index. A name
-- that appears twice keeps its FIRST line, the way a lookup down a file does;
-- so does an address.
function CeroSecOS.parseHosts(text)
	local order, byName, byAddr = {}, {}, {}
	local lines = CeroSecOS.splitLines(text)
	for i = 1, #lines do
		local entry = CeroSecOS.parseHostsLine(lines[i])
		if entry ~= nil then
			order[#order + 1] = entry
			if byAddr[entry.addr] == nil then byAddr[entry.addr] = entry end
			for k = 1, #entry.names do
				if byName[entry.names[k]] == nil then byName[entry.names[k]] = entry end
			end
		end
	end
	return order, byName, byAddr
end

-- The same one-slot, content-keyed cache the accounts, the groups and the
-- sudoers have: the file is the truth, and what makes the answer stale is the
-- file changing.
CeroSecOS.hostsCache = { node = nil, text = nil, order = {}, byName = {}, byAddr = {} }

function CeroSecOS.readHosts(state)
	local node = CeroSecOS.systemNode(state, CeroSecOS.HOSTS_PATH)
	if node == nil or node.type ~= "file" then return {}, {}, {} end
	local cache = CeroSecOS.hostsCache
	if cache.node ~= node or cache.text ~= node.data then
		local order, byName, byAddr = CeroSecOS.parseHosts(node.data or "")
		cache.node = node
		cache.text = node.data
		cache.order = order
		cache.byName = byName
		cache.byAddr = byAddr
	end
	return cache.order, cache.byName, cache.byAddr
end

-- A name or an address a player typed -> addr, name. nil when the file has
-- never heard of it, which is the one refusal a resolver makes: "unknown host".
--
-- An address typed straight out answers itself, with whatever name the file
-- gives it -- a dotted quad needs no resolving, which is why ping can be used
-- on a machine whose /etc/hosts somebody emptied.
function CeroSecOS.resolveHost(state, word)
	if type(word) ~= "string" or word == "" then return nil end
	local _, byName, byAddr = CeroSecOS.readHosts(state)
	if CeroSecOS.isAddress(word) then
		local entry = byAddr[word]
		local name = word
		if entry ~= nil and #entry.names > 0 then name = entry.names[1] end
		return word, name
	end
	local entry = byName[word]
	if entry == nil then return nil end
	-- The name the player typed, not the official one: he asked about "gate"
	-- and every line ping prints is about the name he asked about, which is
	-- what a real one does with an alias too.
	return entry.addr, word
end

-- The OTHER direction, which is the one a machine asks about a caller it did not
-- choose: an address -> the names THIS machine's /etc/hosts gives it, in the
-- order the line has them, or an empty list for an address no line carries.
--
-- gethostbyaddr(3) and nothing more. The first line for the address wins, the way
-- a lookup down a file does and the way readHosts already indexes it: a second
-- line naming the same address is a line the resolver never reaches.
--
-- It is what `who`, `last` and arp all print, and it is the ONLY thing the trust
-- files are allowed to match a name against -- see CeroSecOS.trustWords.
function CeroSecOS.hostsNames(state, addr)
	local out = {}
	if not CeroSecOS.isAddress(addr) then return out end
	local _, _, byAddr = CeroSecOS.readHosts(state)
	local entry = byAddr[addr]
	if entry == nil then return out end
	for i = 1, #entry.names do out[#out + 1] = entry.names[i] end
	return out
end

-- What this machine calls the far end of a session: the name its own /etc/hosts
-- gives the address, and the ADDRESS itself when no line carries it.
--
-- That is rlogind's own answer and the reason it is worth spelling out. A real
-- one takes the peer's address off the socket and asks the resolver what it is
-- called; with no DNS on the rung the resolver is /etc/hosts, and a caller no
-- line names has no name -- so what goes in the host column of wtmp, and into
-- who's brackets, is the dotted quad. It is never the name the caller announces:
-- a machine's own /etc/hostname is a file its own root may write to anything, and
-- a far machine that believed one would be printing whatever it was told.
function CeroSecOS.originOf(state, addr)
	if not CeroSecOS.isAddress(addr) then return nil end
	local names = CeroSecOS.hostsNames(state, addr)
	if #names > 0 then return names[1] end
	return addr
end

-- What a fresh machine's /etc/hosts holds before it knows its own address: the
-- loopback, and nothing else there is to say.
function CeroSecOS.defaultHosts()
	return "# address  host  [alias...]\n"
		.. CeroSecOS.LOOPBACK_ADDR .. " " .. CeroSecOS.LOOPBACK_NAME
end

-- The machine's own line, appended once. Answers true when it wrote one.
--
-- Only ever a line that is not there yet: an /etc/hosts that already names this
-- address, or already names this host, is a file somebody has been keeping and
-- is left exactly as it lies. Through the ordinary setData, so the ceilings and
-- the printable rule apply and a full disk simply means the line is not written
-- -- which costs the machine a name for itself and nothing else.
function CeroSecOS.writeOwnHost(state, now)
	local addr = CeroSecOS.address(state)
	if addr == nil then return false end
	local node = CeroSecOS.systemNode(state, CeroSecOS.HOSTS_PATH)
	if node == nil or node.type ~= "file" then return false end
	local host = CeroSecOS.hostname(state)
	local _, byName, byAddr = CeroSecOS.readHosts(state)
	if byAddr[addr] ~= nil or byName[host] ~= nil then return false end
	local text = node.data or ""
	if text ~= "" then text = text .. "\n" end
	local done = CeroSecOS.setData(state, CeroSecOS.rootSession(), CeroSecOS.HOSTS_PATH,
		text .. addr .. " " .. host, now)
	if done == nil then return false end
	return true
end

-- /etc/hosts and /etc/hosts.equiv, made where they are missing. Called for a
-- fresh machine, for an older one being topped up and for the BIOS repair
-- alike, and never put back behind a root who deleted them: the two are the
-- player's files and a missing one is a machine that trusts nobody and resolves
-- nothing, which is a choice.
function CeroSecOS.ensureNet(state)
	if type(state) ~= "table" then return nil end
	local etc = CeroSecOS.ensureSystemDir(state, "etc")
	if etc == nil then return nil end
	if etc.children.hosts == nil then
		etc.children.hosts =
			CeroSecOS.newFile("root", CeroSecOS.HOSTS_MODE, CeroSecOS.defaultHosts())
	end
	if etc.children["hosts.equiv"] == nil then
		etc.children["hosts.equiv"] =
			CeroSecOS.newFile("root", CeroSecOS.EQUIV_MODE, CeroSecOS.defaultEquiv())
	end
	-- And the station's callsign, which is the third link's half of the same job
	-- and is seeded on the same terms: only where the name is free, and only for a
	-- machine that has a record to derive one from -- a computer in a base
	-- somebody built has no address, no telephone number and no callsign, all
	-- three for the one reason. See CeroSecOSRadio.lua.
	CeroSecOS.ensureCallsign(state)
	return etc
end

--
-- Trust
--
-- hosts.equiv(5) and ruserok(3), which is the pair of files rlogind and rshd
-- ask before they decide whether to want a password. A line is a host and
-- optionally an account:
--
--     gate
--     gate admin
--
-- The bare host trusts THE SAME NAME on it: a line "gate" in /etc/hosts.equiv
-- lets gate's admin in as admin and nobody in as anybody else.
--
-- WHICH MACHINE A LINE IS ABOUT, which is the whole of the security in these two
-- files. What rlogind and rshd are handed is the caller's ADDRESS off the socket,
-- and the name in a trust line is turned into an address the only way this rung
-- has: through THIS machine's /etc/hosts. So a line may be written either way --
--
--     gate
--     10.4.17.3
--     10.4.17.3 admin
--
-- and a NAME matches only when a line of the local /etc/hosts gives that name to
-- the address the session came from. It is never matched against the name the
-- caller announces. That name is the caller's own /etc/hostname, a 644 file its
-- own root may write to anything, and it is what ruptime and rwho print because
-- those are reports a machine broadcasts about itself -- believing one here would
-- let anybody with root on any computer in the building type `hostname gate` and
-- walk in through a line somebody wrote about gate. So trust is a question about
-- an address, and a machine whose caller has none (a telephone call, a radio
-- link) trusts nobody: see CeroSecOS.trustWords.
--
-- A host and an account names the account COMING IN, not the one being come in
-- as, which is ruserok(3)'s own reading of the second field: a line
-- "gate admin" in bob's ~/.rhosts lets gate's admin become bob, because the file
-- is bob's and saying so is bob's to say. That is the one direction of trust the
-- two-word form has ever meant, and reading it the other way round would make
-- every .rhosts a line about somebody who is already the owner.
--
-- What is deliberately NOT here: "+" and "-", and netgroups. A bare plus in
-- hosts.equiv trusts every machine in the world, which was a hole in 1993 and
-- is a hole now, and a game that shipped one would be teaching it. A line with
-- one in it does not parse, so it trusts nobody rather than everybody -- and
-- that is the safe direction for a parser to fail in.
--

-- One line -> { host, user }, or nil. Blank lines and comments are skipped.
function CeroSecOS.parseEquivLine(line)
	if type(line) ~= "string" then return nil end
	local hash = string.find(line, "#", 1, true)
	if hash ~= nil then line = string.sub(line, 1, hash - 1) end
	local words = {}
	for word in string.gmatch(line, "[^ \t]+") do words[#words + 1] = word end
	if #words == 0 or #words > 2 then return nil end
	-- A host or an address: the two spellings of the same machine, and a name can
	-- never be mistaken for an address because isValidHostname carries no dot.
	if not CeroSecOS.isValidHostname(words[1]) and not CeroSecOS.isAddress(words[1]) then
		return nil
	end
	if #words == 1 then return { host = words[1] } end
	if not CeroSecOS.isValidName(words[2]) then return nil end
	return { host = words[1], user = words[2] }
end

-- text -> the entries, in the order the file has them.
function CeroSecOS.parseEquiv(text)
	local out = {}
	local lines = CeroSecOS.splitLines(text)
	for i = 1, #lines do
		local entry = CeroSecOS.parseEquivLine(lines[i])
		if entry ~= nil then out[#out + 1] = entry end
	end
	return out
end

-- Every word a trust line may use for the machine at `fromAddr`: the address
-- itself, and every name the local /etc/hosts gives it. nil when the caller has
-- no address at all, which is a caller these two files have nothing to say about.
--
-- The names come from the machine being ASKED, not from the machine asking. That
-- is the whole rule, and it is one function so that no caller can arrive at a
-- trust decision with a name somebody else chose.
function CeroSecOS.trustWords(state, fromAddr)
	if not CeroSecOS.isAddress(fromAddr) then return nil end
	local out = { fromAddr }
	local names = CeroSecOS.hostsNames(state, fromAddr)
	for i = 1, #names do out[#out + 1] = names[i] end
	return out
end

-- Does this list let `fromUser` on one of `words` in as `asUser`? The two forms,
-- and no third.
local function equivAllows(entries, words, fromUser, asUser)
	local function names(host)
		for i = 1, #words do
			if words[i] == host then return true end
		end
		return false
	end
	for i = 1, #entries do
		local entry = entries[i]
		if names(entry.host) then
			if entry.user == nil then
				if fromUser == asUser then return true end
			elseif entry.user == fromUser then
				return true
			end
		end
	end
	return false
end

-- The machine-wide half: /etc/hosts.equiv, read the way the kernel reads
-- /etc/passwd -- by path, with no session. It is root's file and 644, so there
-- is no permission question to ask about it; what matters is that a rlogind
-- reads it whoever is coming in, and a rlogind does not have a session yet.
function CeroSecOS.equivOk(state, fromAddr, fromUser, asUser)
	if type(asUser) ~= "string" or type(fromUser) ~= "string" then return false end
	local words = CeroSecOS.trustWords(state, fromAddr)
	if words == nil then return false end
	-- root is never trusted by /etc/hosts.equiv. That is ruserok's own rule and
	-- the most important line in it: a machine that let the root of any trusted
	-- host in as its own root would be a machine whose password is the weakest
	-- root password on the wire.
	if asUser == "root" then return false end
	local node = CeroSecOS.systemNode(state, CeroSecOS.EQUIV_PATH)
	if node == nil or node.type ~= "file" then return false end
	return equivAllows(CeroSecOS.parseEquiv(node.data or ""), words, fromUser, asUser)
end

-- The account's own half: ~/.rhosts, and the two facts rlogind checks about the
-- FILE before it reads a byte of it.
--
--   * it is the account's own, or root's. A .rhosts in bob's home owned by
--     somebody else is a list somebody else wrote.
--   * nobody but its owner may write it. ruserok tests st_mode & 022; a group
--     or a world writable .rhosts is one any member of that group could add a
--     line to, and rlogind ignores it rather than trusting it.
--
-- Ignored and not refused: a .rhosts that fails either test is a file that is
-- not there as far as the trust question goes, and the account is asked for its
-- password exactly as it would be with no file at all. That is what rlogind
-- does, and saying so out loud would be telling a caller which of the two tests
-- it failed.
function CeroSecOS.rhostsOk(state, asUser, fromAddr, fromUser)
	if type(asUser) ~= "string" or type(fromUser) ~= "string" then return false end
	local words = CeroSecOS.trustWords(state, fromAddr)
	if words == nil then return false end
	local user = CeroSecOS.getUser(state, asUser)
	if user == nil or type(user.home) ~= "string" then return false end
	local path = user.home .. "/" .. CeroSecOS.RHOSTS_NAME
	local node = CeroSecOS.systemNode(state, path)
	if node == nil or node.type ~= "file" then return false end
	if node.owner ~= asUser and node.owner ~= "root" then return false end
	-- ruserok's st_mode & 022: the write bit of the group digit or of the world
	-- digit, either of which is somebody who is not the owner.
	local mode = node.mode or 0
	if CeroSecOS.digitWritable(math.fmod(math.floor(mode / 10), 10)) then return false end
	if CeroSecOS.digitWritable(math.fmod(mode, 10)) then return false end
	return equivAllows(CeroSecOS.parseEquiv(node.data or ""), words, fromUser, asUser)
end

-- Does one octal digit of a mode carry its write bit? The middle bit of three,
-- worked out with division because the core has no bit library.
function CeroSecOS.digitWritable(digit)
	if type(digit) ~= "number" then return false end
	return math.fmod(math.floor(math.floor(digit) / 2), 2) == 1
end

-- The question rlogind and rshd both ask, and the order they ask it in: the
-- machine's own list first, then the account's. Either is enough.
--
-- `fromAddr` is the caller's ADDRESS and never a name: a caller with no address
-- is trusted by neither file. See the head of this section.
function CeroSecOS.trusts(state, asUser, fromAddr, fromUser)
	if CeroSecOS.equivOk(state, fromAddr, fromUser, asUser) then return true end
	return CeroSecOS.rhostsOk(state, asUser, fromAddr, fromUser)
end

-- What a machine ships with: nothing trusted, and a line saying what a line
-- would look like. An office that wanted its machines to trust each other wrote
-- the names in; one that did not, did not.
function CeroSecOS.defaultEquiv()
	return "# host [user] -- one a line; a bare host trusts the same name on it\n"
		.. "# a name has to be in /etc/hosts here; an address needs no line\n"
		.. "# nothing is trusted until somebody writes a line here"
end

--
-- /var/log/wtmp
--

-- Is that word something a session could have come FROM? One of the three
-- origins this machine has, and no fourth: a machine off the coax -- named by a
-- line of the local /etc/hosts, or by its bare ADDRESS when no line carries it,
-- which is what CeroSecOS.originOf hands over -- a telephone number, or a
-- callsign off the air. Written as one function because it is one
-- question, asked in one place, and because the day a fourth link is built the
-- thing that has to change is here and not inside a parser.
--
-- isCallsign lives in CeroSecOSRadio.lua, which the game loads after this file;
-- it is called at run time and never at load time, so the order does not matter
-- -- but a machine with the radio half missing must still read its own wtmp, so
-- the call is guarded rather than assumed.
function CeroSecOS.isWtmpOrigin(word)
	if type(word) ~= "string" then return false end
	if CeroSecOS.isValidHostname(word) then return true end
	if CeroSecOS.isAddress(word) then return true end
	if CeroSecOS.isPhoneNumber(word) then return true end
	if type(CeroSecOS.isCallsign) == "function" and CeroSecOS.isCallsign(word) then
		return true
	end
	return false
end

-- One line -> { kind, user, line, host, at }, or nil. Strict and silent, like
-- every other parser on this machine.
function CeroSecOS.parseWtmpLine(text)
	if type(text) ~= "string" then return nil end
	local kind, user, line, host, at =
		string.match(text, "^(%a+) ([^ ]+) ([^ ]+) ([^ ]+) (%d+)$")
	if kind == nil then return nil end
	if kind ~= "in" and kind ~= "out" then return nil end
	if not CeroSecOS.isValidName(user) then return nil end
	if not CeroSecOS.isValidName(line) then return nil end
	-- The host column is the ORIGIN, and there are three kinds of it now: a
	-- machine on the coax is named by its hostname, a caller down the telephone by
	-- the number he can be rung back on, and a station on the air by its callsign.
	-- All three go through here, so all three have to be spelt out -- a callsign is
	-- CAPITALS and isValidHostname is lower case only, so the rule that used to be
	-- "a hostname or a dash" silently refused every radio session's record and left
	-- `last` with nothing to read. Found by tests/window_test.lua and not by
	-- reading: wtmpAppend answers false and nobody was listening.
	if host ~= "-" and not CeroSecOS.isWtmpOrigin(host) then return nil end
	local when = tonumber(at)
	if when == nil then return nil end
	if host == "-" then host = nil end
	return { kind = kind, user = user, line = line, host = host, at = math.floor(when) }
end

function CeroSecOS.parseWtmp(text)
	local out = {}
	local lines = CeroSecOS.splitLines(text)
	for i = 1, #lines do
		local rec = CeroSecOS.parseWtmpLine(lines[i])
		if rec ~= nil then out[#out + 1] = rec end
	end
	return out
end

-- A record onto the end of it, trimmed to both ceilings. Not through setData:
-- the file is exempt from the disk quota by its path and is capped here
-- instead, exactly as the cron log and the mailboxes are.
--
-- Quiet on every refusal. A login that could not be logged is still a login,
-- and a machine that refused one because its own bookkeeping file would not
-- take a line would be a machine nobody can use.
function CeroSecOS.wtmpAppend(state, kind, user, line, host, now)
	if kind ~= "in" and kind ~= "out" then return false end
	if type(user) ~= "string" or type(line) ~= "string" then return false end
	if type(now) ~= "number" then return false end
	-- Not onto a mounted disk: see CeroSecOS.onOwnDrive.
	if not CeroSecOS.onOwnDrive(state, CeroSecOS.WTMP_PATH) then return false end
	local node = CeroSecOS.systemNode(state, CeroSecOS.WTMP_PATH)
	if node == nil then
		local made = CeroSecOS.createNode(state, CeroSecOS.rootSession(),
			CeroSecOS.WTMP_PATH, CeroSecOS.newFile("root", CeroSecOS.WTMP_MODE, ""))
		if made == nil then return false end
		node = CeroSecOS.systemNode(state, CeroSecOS.WTMP_PATH)
	end
	if node == nil or node.type ~= "file" then return false end

	local where = "-"
	if type(host) == "string" and host ~= "" then where = host end
	local text = kind .. " " .. user .. " " .. line .. " " .. where
		.. " " .. math.floor(now)
	if CeroSecOS.parseWtmpLine(text) == nil then return false end

	local kept = CeroSecOS.splitLines(node.data or "")
	kept[#kept + 1] = text
	while #kept > CeroSecOS.WTMP_LINES do table.remove(kept, 1) end
	local out = table.concat(kept, "\n")
	while #out > CeroSecOS.WTMP_BYTES and #kept > 1 do
		table.remove(kept, 1)
		out = table.concat(kept, "\n")
	end
	node.data = out
	node.mtime = math.floor(now)
	return true
end

--
-- The shape of a line
--
-- Every format the five listing commands print is written here, once, so that
-- what a test pins and what a player reads cannot drift apart. They are BSD's
-- own, cut where sixty columns forced a cut and nowhere else -- and each cut is
-- named beside the number it cost.
--

-- who(1) and last(1) pad the account and the line to eight, because that is how
-- many characters a utmp record holds. This machine's accounts go to sixteen
-- (CeroSecOS.MAX_USERNAME), so eight is a minimum here and never a truncation:
-- a `last` that shortened a name would be a `last` that named the wrong
-- survivor.
CeroSecOS.L_WHO_USER = 8
CeroSecOS.L_WHO_LINE = 8
-- BSD's UT_HOSTSIZE is sixteen. Ten here, because a hostname on this machine is
-- "ksp-" and two base-36 coordinates and a longer one is a name a player chose.
CeroSecOS.L_WHO_HOST = 10

-- who(1): the account, the line, when it started, and where it came from. The
-- host in parentheses is BSD's, and so is leaving it off a session that came
-- from nowhere -- which here is the survivor standing at the keyboard.
--
-- BSD puts a TAB in front of the parenthesis. This machine has none to put:
-- CeroSec.consoleLine turns a tab into one space on the way to the glass,
-- because a screen with a fixed grid has no tab stops.
function CeroSecOS.whoLine(user, line, at, host)
	local out = CeroSecOS.padRight(user, CeroSecOS.L_WHO_USER) .. " "
		.. CeroSecOS.padRight(line, CeroSecOS.L_WHO_LINE) .. " "
		.. CeroSecOS.formatStamp(at)
	if type(host) == "string" and host ~= "" then out = out .. "  (" .. host .. ")" end
	return out
end

-- last(1). BSD prints ctime's first ten characters and then the clock --
-- "Thu Jul  8 14:35" -- and this prints the machine's own twelve-character
-- stamp, the one `ls -l` uses, because the weekday is four columns of sixty and
-- the line already carries an account, a line, a host and two times.
--
--     admin    ttyp0    gate       Jul  8 14:35 - 14:40  (00:05)
--     admin    console             Jul  8 14:32  still logged in
--
-- "still logged in" is BSD's own line, and so are the two spaces in front of it.
function CeroSecOS.lastLine(rec, out)
	local line = CeroSecOS.padRight(rec.user, CeroSecOS.L_WHO_USER) .. " "
		.. CeroSecOS.padRight(rec.line, CeroSecOS.L_WHO_LINE) .. " "
		.. CeroSecOS.padRight(rec.host or "", CeroSecOS.L_WHO_HOST) .. " "
		.. CeroSecOS.formatStamp(rec.at)
	if out == nil then return line .. "  still logged in" end
	local p = CeroSecOS.dateParts(out)
	return line .. " - " .. CeroSecOS.twoDigits(p.hour) .. ":"
		.. CeroSecOS.twoDigits(p.min) .. "  ("
		.. CeroSecOS.spanText(out - rec.at) .. ")"
end

-- A number as two digits, zero-padded. The clock halves of every line below use
-- it, and so does the span; there is no second spelling of "02" in this file.
function CeroSecOS.twoDigits(n)
	if type(n) ~= "number" then n = 0 end
	n = math.floor(n)
	if n < 10 and n >= 0 then return "0" .. tostring(n) end
	return tostring(n)
end

-- How long something lasted, the way last(1) and ruptime(1) both print it:
-- "3+02:15" past a day and "02:15" under one. BSD pads both into a column; the
-- callers here pad what they print, so this is the number and nothing else.
function CeroSecOS.spanText(seconds)
	if type(seconds) ~= "number" or seconds < 0 then seconds = 0 end
	seconds = math.floor(seconds)
	local days = math.floor(seconds / 86400)
	local rest = seconds - days * 86400
	local hh = CeroSecOS.twoDigits(math.floor(rest / 3600))
	local mm = CeroSecOS.twoDigits(math.fmod(math.floor(rest / 60), 60))
	if days > 0 then return tostring(days) .. "+" .. hh .. ":" .. mm end
	return hh .. ":" .. mm
end

-- ruptime(1): the machine, how long it has been up, how many survivors are
-- logged in on it, and its load.
--
--     gate     up  3+02:15,  1 user,  load 0.02
--
-- Two cuts from BSD's line, and both are the screen's. It prints three load
-- averages -- one, five and fifteen minutes -- and this prints one, because
-- three would be twelve more columns of sixty. And it can print "down" for a
-- machine it has not heard from, because a real ruptime reads the reports rwhod
-- left in /var/spool/rwho and the newest of them may be an hour old; there is
-- no spool here, so a machine that is off is a machine nothing on the wire has
-- ever heard of and it is simply not listed. The manual says both.
--
-- The load is the number of jobs the machine has that are able to run, which is
-- what a load average has counted since the first one: what it is NOT is an
-- average, because nothing on this machine smooths anything over a minute.
function CeroSecOS.ruptimeLine(host, up, users, load)
	local word = " user,"
	if users ~= 1 then word = " users," end
	local n = tostring(math.floor((load or 0) * 100))
	while #n < 3 do n = "0" .. n end
	local whole = string.sub(n, 1, #n - 2)
	local cents = string.sub(n, #n - 1)
	return CeroSecOS.padRight(host, CeroSecOS.L_WHO_HOST) .. "up  "
		.. CeroSecOS.spanText(up) .. ",  " .. tostring(math.floor(users or 0))
		.. word .. "  load " .. whole .. "." .. cents
end

-- rwho(1): who is logged in, on which machine, and since when. BSD's own line,
-- ctime's twelfth character onward and all -- which is exactly the stamp `ls -l`
-- prints, so this one needed no cutting.
--
--     admin    gate:console  Jul  8 14:32
function CeroSecOS.rwhoLine(user, host, line, at)
	return CeroSecOS.padRight(user, CeroSecOS.L_WHO_USER) .. " "
		.. CeroSecOS.padRight(host .. ":" .. line, CeroSecOS.L_WHO_HOST + 6) .. " "
		.. CeroSecOS.formatStamp(at)
end

--
-- The commands
--

local commands = CeroSecOS.commands

local function fail(cmd, arg, reason)
	if arg == nil then return false, { cmd .. ": " .. reason } end
	return false, { cmd .. ": " .. arg .. ": " .. reason }
end

local function usage(cmd)
	return false, { cmd .. ": usage: " .. (CeroSecOS.commandUsage(cmd) or cmd) }
end

-- The link layer, or nil. A machine whose caller handed it none has no network
-- at all: nothing is reachable, nothing is listed, and no command says anything
-- about it -- which is the same thing a machine with the wire pulled out of it
-- would say, and is what every test that is not about the network runs on.
local function linkOf(env)
	if type(env) ~= "table" then return nil end
	if type(env.net) ~= "table" then return nil end
	return env.net
end

-- Is that address something this machine can hear right now? The question is
-- entirely the world's -- which building, and whose power is on -- so it is the
-- link layer's and the engine only ever asks it.
local function reachable(env, addr)
	if addr == CeroSecOS.LOOPBACK_ADDR then return true end
	local net = linkOf(env)
	if net == nil or type(net.reach) ~= "function" then return false end
	return net.reach(addr) and true or false
end

-- Every machine on the wire, this one included, in the order the commands print
-- them: by name, because that is how ruptime and rwho sort with no flag on them.
local function peersOf(env)
	local net = linkOf(env)
	if net == nil or type(net.peers) ~= "function" then return {} end
	local list = net.peers()
	if type(list) ~= "table" then return {} end
	local out = {}
	for i = 1, #list do
		local peer = list[i]
		if type(peer) == "table" and type(peer.host) == "string" then out[#out + 1] = peer end
	end
	table.sort(out, function(a, b) return a.host < b.host end)
	return out
end

--
-- ifconfig
--
-- Two interfaces, and neither of them can be configured: the address is derived
-- from the building the computer stands in and from which computer of it this
-- is, so there is nothing an argument could set. 4.4BSD's own `ifconfig` with no
-- arguments prints a usage line; this one lists, because there are exactly two
-- and no way to change either -- and `-a`, which is what a real one wants for
-- the same answer, does the same thing.
--
-- The broadcast address is not printed. A real one prints it beside the netmask;
-- this screen is sixty columns and the netmask already says what the network is.
--

CeroSecOS.ETHER_NAME = "eth0"
CeroSecOS.LOOPBACK_NAME_IF = "lo0"

local function ifaceLines(state, want)
	local out = {}
	if want == nil or want == CeroSecOS.ETHER_NAME then
		local addr = CeroSecOS.address(state)
		if addr == nil then
			-- A computer in a player-built base is in no map building, so there
			-- is no wire for it to be on. The card is there and it is not up.
			out[#out + 1] = CeroSecOS.ETHER_NAME .. ": flags=2<BROADCAST>"
		else
			out[#out + 1] = CeroSecOS.ETHER_NAME
				.. ": flags=63<UP,BROADCAST,NOTRAILERS,RUNNING>"
			out[#out + 1] = "      inet " .. addr .. " netmask 0xffffff00"
		end
	end
	if want == nil or want == CeroSecOS.LOOPBACK_NAME_IF then
		out[#out + 1] = CeroSecOS.LOOPBACK_NAME_IF .. ": flags=8<LOOPBACK>"
		out[#out + 1] = "      inet " .. CeroSecOS.LOOPBACK_ADDR .. " netmask 0xff000000"
	end
	return out
end

commands.ifconfig = function(state, session, args, env)
	if #args > 2 then return usage("ifconfig") end
	local want = args[2]
	if want == nil or want == "-a" then return true, ifaceLines(state, nil) end
	if want ~= CeroSecOS.ETHER_NAME and want ~= CeroSecOS.LOOPBACK_NAME_IF then
		-- ifconfig(8)'s own refusal for a name the kernel has never heard of.
		return false, { "ifconfig: interface " .. want .. " does not exist" }
	end
	return true, ifaceLines(state, want)
end

--
-- arp
--
-- arp(8), and it is the command that closes the gap between the two halves of a
-- network with no name server in it: ruptime says what the machines CALL
-- themselves and /etc/hosts wants an ADDRESS, and until there was an arp there
-- was nothing on the disk that told a survivor the addresses he was surrounded
-- by. A real arp is exactly that command -- what the kernel has learnt about the
-- wire, address by address -- and a 1993 administrator read one for this reason.
--
-- Two of its five forms, and the three that are missing are missing for one
-- reason: -d deletes an entry, -s sets one and -f reads a file of them, and every
-- Ethernet address on this rung is DERIVED from the network address (see
-- CeroSecOS.etherOf) and is stored nowhere at all. There is nothing to delete,
-- nothing to set and no file to read, so the flags that would say so are not
-- there rather than there and lying.
--
-- What the cache holds. A real one holds the machines this one has spoken to
-- lately; this one holds every OTHER switched-on machine of the building, which
-- is the set ruptime reports and the set `ping` can reach. Not itself: a machine
-- does not ARP for its own address, and BSD's cache has no line for it either.
-- A machine that is off is not in it, exactly as it is not in ruptime -- and that
-- is the same single deviation the manual already names for ruptime, there being
-- no daemon here keeping what the wire said an hour ago.
--

-- The first three bytes of every card on the wire: Sun Microsystems' own OUI,
-- which is what "8:0:20" was in 1993 and what the arp(8) manual page of the day
-- printed in its own example. A building full of Sun boxes is what a county
-- office had.
CeroSecOS.ETHER_OUI = "8:0:20"

-- The lower three bytes, derived from the three numbers of the address that vary:
-- b1 and b2, which are the building, and n, which is the machine. Two rounds of
-- the same 16-bit multiply-add the building key and the telephone number are made
-- of -- exact in a double, deterministic for ever, and scattering neighbours so
-- that two machines of one building do not read as two cards off one reel.
--
-- It is DERIVED and it is not a field: there is no state to save, nothing to
-- migrate, no ifconfig and no arp -s that writes one, and a machine off an older
-- save answers the same card the first time anybody asks. The manual says so
-- where it prints one.
function CeroSecOS.etherKey(b1, b2, n)
	if type(b1) ~= "number" or type(b2) ~= "number" or type(n) ~= "number" then
		return nil
	end
	b1, b2, n = math.floor(b1), math.floor(b2), math.floor(n)
	if b1 < 0 or b1 > 255 or b2 < 0 or b2 > 255 or n < 0 or n > 255 then return nil end
	local k = (b1 * 256 + b2) * 256 + n
	local h = math.fmod(k * 25173 + 13849, 65536)
	local g = math.fmod(h * 40503 + 12289, 65536)
	return math.floor(h / 256), math.fmod(h, 256), math.floor(g / 256)
end

-- One byte as arp prints one: lower-case hex with no leading zero, which is
-- printf's "%x" and is why a real one reads "8:0:20:1e:2a:4b" and not
-- "08:00:20:1e:2a:4b". Written out by hand because the engine has no
-- string.format on it.
CeroSecOS.ETHER_HEX = "0123456789abcdef"

function CeroSecOS.etherByte(n)
	if type(n) ~= "number" then return nil end
	n = math.floor(n)
	if n < 0 or n > 255 then return nil end
	local lo = math.fmod(n, 16)
	local hi = math.floor(n / 16)
	local out = string.sub(CeroSecOS.ETHER_HEX, lo + 1, lo + 1)
	if hi > 0 then out = string.sub(CeroSecOS.ETHER_HEX, hi + 1, hi + 1) .. out end
	return out
end

-- An address -> the card that answers for it. nil for anything that is not an
-- address. The first number is not in it: every address on this rung is on the
-- ten network, so it carries nothing to derive from.
function CeroSecOS.etherOf(addr)
	if not CeroSecOS.isAddress(addr) then return nil end
	local _, b1, b2, n = string.match(addr, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	local x, y, z = CeroSecOS.etherKey(tonumber(b1), tonumber(b2), tonumber(n))
	if x == nil then return nil end
	return CeroSecOS.ETHER_OUI .. ":" .. CeroSecOS.etherByte(x) .. ":"
		.. CeroSecOS.etherByte(y) .. ":" .. CeroSecOS.etherByte(z)
end

-- One line of arp -a, and arp's own shape for it:
--
--     gate (10.4.17.3) at 8:0:20:1e:2a:4b
--     ? (10.4.17.4) at 8:0:20:3c:7f:11
--
-- The "?" is arp's own and it is the point of the command: it is what a machine
-- prints for an address gethostbyaddr could not name, which here means no line of
-- /etc/hosts carries it yet. A real one prints the interface it was learnt on
-- after the card ("on eth0"); this screen is sixty columns and there is one
-- Ethernet on the machine.
CeroSecOS.ARP_NO_NAME = "?"

function CeroSecOS.arpLine(name, addr)
	local mac = CeroSecOS.etherOf(addr)
	if mac == nil then return nil end
	return tostring(name) .. " (" .. addr .. ") at " .. mac
end

-- What arp calls an address: the name the local /etc/hosts gives it, or "?".
local function arpName(state, addr)
	local names = CeroSecOS.hostsNames(state, addr)
	if #names > 0 then return names[1] end
	return CeroSecOS.ARP_NO_NAME
end

-- Is this address in the cache? Every other machine of the building that is
-- switched on -- so not this one, and not the loopback, neither of which any
-- kernel has an Ethernet entry for.
local function inCache(state, env, addr)
	if not CeroSecOS.isAddress(addr) then return false end
	if addr == CeroSecOS.LOOPBACK_ADDR then return false end
	if addr == CeroSecOS.address(state) then return false end
	return reachable(env, addr)
end

commands.arp = function(state, session, args, env)
	if #args ~= 2 then return usage("arp") end

	if args[2] == "-a" then
		local peers = peersOf(env)
		local rows = {}
		for i = 1, #peers do
			local addr = peers[i].addr
			if inCache(state, env, addr) then rows[#rows + 1] = addr end
		end
		-- By address, and by its four numbers rather than by its letters: 10.4.17.9
		-- comes before 10.4.17.10 on a wire and after it in a string sort. The
		-- broadcast names the peers arrived under are not sorted on and not printed
		-- -- arp is a command about addresses.
		table.sort(rows, function(a, b)
			local aq = { string.match(a, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$") }
			local bq = { string.match(b, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$") }
			for i = 1, 4 do
				local x, y = tonumber(aq[i]), tonumber(bq[i])
				if x ~= y then return x < y end
			end
			return false
		end)
		local out = {}
		for i = 1, #rows do
			out[#out + 1] = CeroSecOS.arpLine(arpName(state, rows[i]), rows[i])
		end
		return true, out
	end

	local addr = CeroSecOS.resolveHost(state, args[2])
	if addr == nil then
		-- arp's own refusal for a word the resolver cannot place, in this machine's
		-- spelling of it: a real one hands the job to herror(3), which says "Unknown
		-- host" in capitals, and every refusal on this disk is lower case.
		return fail("arp", args[2], CeroSecOS.NET_REASON.unknown)
	end
	if not inCache(state, env, addr) then
		-- arp(8)'s own line for a host it resolved and has no entry for, and it
		-- carries neither the command's name nor a colon: the word the player typed,
		-- the address it resolved to, and what is missing. It is still a refusal, so
		-- a script can tell "not on the wire" from "here is the card".
		return false, { args[2] .. " (" .. addr .. ") -- no entry" }
	end
	return true, { CeroSecOS.arpLine(arpName(state, addr), addr) }
end

--
-- ping
--
-- Three packets, a second apart, and the statistics ping has printed since
-- 1983. The second between them is a real second: the command hands the job back
-- to the machine with a moment to be woken at (the "sleep" control), so a ping
-- costs the machine one turn a second and nothing in between -- exactly what a
-- script's own `sleep` costs.
--
-- Whether a packet arrives is asked FRESH for each of the three, which is what
-- makes a ping honest: a machine switched off halfway through loses the packets
-- that were still to come, and the loss percentage says so.
--

CeroSecOS.PING_COUNT = 3
CeroSecOS.PING_WAIT_MS = 1000
-- What ping sends and what comes back: 56 bytes of data, which with the eight
-- of an ICMP header is the 64 the reply line reports. Both are ping's own
-- defaults and neither is a number this machine chose.
CeroSecOS.PING_DATA = 56
CeroSecOS.PING_REPLY = 64
CeroSecOS.PING_TTL = 255
-- How long a packet takes on the wire. One number for the Ethernet link,
-- printed as it stands: there is nothing on this machine to measure, and a
-- round trip that varied would be a random number dressed up as a measurement.
CeroSecOS.PING_TIME = "0.4"

local function pingReply(addr, seq)
	return CeroSecOS.PING_REPLY .. " bytes from " .. addr .. ": icmp_seq="
		.. seq .. " ttl=" .. CeroSecOS.PING_TTL .. " time="
		.. CeroSecOS.PING_TIME .. " ms"
end

local function pingStats(name, got)
	local sent = CeroSecOS.PING_COUNT
	-- The blank line is ping's own: it separates the replies from the summary.
	local out = { "", "--- " .. name .. " ping statistics ---" }
	local lost = math.floor((sent - got) * 100 / sent)
	out[#out + 1] = sent .. " packets transmitted, " .. got
		.. " packets received, " .. lost .. "% packet loss"
	-- And no round-trip line at all when nothing came back, which is where
	-- ping's own `if (nreceived)` puts it: there is no minimum of nothing.
	if got > 0 then
		local t = CeroSecOS.PING_TIME
		out[#out + 1] = "round-trip min/avg/max = " .. t .. "/" .. t .. "/" .. t .. " ms"
	end
	return out
end

-- One packet, and either the next one or the summary. Shared by the command and
-- by the continuation the clock wakes, so the first packet and the third are the
-- same code.
local function pingStep(env, addr, name, seq, got, out)
	if reachable(env, addr) then
		out[#out + 1] = pingReply(addr, seq)
		got = got + 1
	end
	if seq + 1 >= CeroSecOS.PING_COUNT then
		local tail = pingStats(name, got)
		for i = 1, #tail do out[#out + 1] = tail[i] end
		return true, out
	end
	return true, out, "sleep", {
		ms = CeroSecOS.PING_WAIT_MS,
		cont = { cmd = "ping", addr = addr, name = name, seq = seq + 1, got = got },
	}
end

commands.ping = function(state, session, args, env)
	if #args ~= 2 then return usage("ping") end
	local addr, name = CeroSecOS.resolveHost(state, args[2])
	if addr == nil then
		-- ping(8)'s own words, and its own shape: the name goes after the
		-- reason, not in front of it.
		return false, { "ping: unknown host " .. args[2] }
	end
	local out = { "PING " .. name .. " (" .. addr .. "): "
		.. CeroSecOS.PING_DATA .. " data bytes" }
	return pingStep(env, addr, name, 0, 0, out)
end

-- The token the clock answers, a second after the last packet. It carries the
-- address and not the name: a machine taken out of /etc/hosts between two
-- packets is still the machine those packets were going to.
CeroSecOS.continuations = CeroSecOS.continuations or {}

CeroSecOS.continuations.ping = function(state, session, cont, line, env)
	local addr, name = cont.addr, cont.name
	if type(addr) ~= "string" or type(name) ~= "string" then
		return false, { "ping: nothing to answer" }
	end
	local seq = tonumber(cont.seq) or 0
	local got = tonumber(cont.got) or 0
	if seq < 1 or seq >= CeroSecOS.PING_COUNT then
		return false, { "ping: nothing to answer" }
	end
	return pingStep(env, addr, name, math.floor(seq), math.floor(got), {})
end

--
-- ruptime, rwho
--
-- The two commands the rwho package gave a small network, and they are the
-- answer to the only two questions a survivor has about one: which machines are
-- there, and who is on them.
--
-- A real ruptime reads the reports rwhod left under /var/spool/rwho, so it can
-- print "down" for a machine it has not heard from in a while. There is no spool
-- here and no daemon writing one: a machine that is off is a machine nothing on
-- the wire has ever heard of, and it is simply not listed. That is the one
-- deviation and the manual names it.
--

commands.ruptime = function(state, session, args, env)
	if #args ~= 1 then return usage("ruptime") end
	local peers = peersOf(env)
	local out = {}
	for i = 1, #peers do
		local peer = peers[i]
		out[#out + 1] = CeroSecOS.ruptimeLine(peer.host, peer.up or 0,
			peer.users or 0, peer.load or 0)
	end
	return true, out
end

commands.rwho = function(state, session, args, env)
	if #args ~= 1 then return usage("rwho") end
	local peers = peersOf(env)
	local rows = {}
	for i = 1, #peers do
		local peer = peers[i]
		local who = peer.who
		if type(who) == "table" then
			for k = 1, #who do
				local one = who[k]
				if type(one) == "table" and type(one.user) == "string" then
					rows[#rows + 1] = { user = one.user, host = peer.host,
						line = one.line or CeroSecOS.CONSOLE_LINE, at = one.at or 0 }
				end
			end
		end
	end
	-- rwho sorts by account and then by where he is sitting, which is what
	-- makes two survivors on one machine read as two lines of one block.
	table.sort(rows, function(a, b)
		if a.user ~= b.user then return a.user < b.user end
		if a.host ~= b.host then return a.host < b.host end
		return a.line < b.line
	end)
	local out = {}
	for i = 1, #rows do
		out[#out + 1] = CeroSecOS.rwhoLine(rows[i].user, rows[i].host,
			rows[i].line, rows[i].at)
	end
	return true, out
end

--
-- who
--
-- This machine only, and every line on it: the survivor at the keyboard, on the
-- console, and every session that came in over the wire, on its pty with the
-- machine it came from in parentheses. That last column is what makes `who` the
-- command to type when something is happening on a computer and nobody is
-- standing at it.
--
-- `who am i` is BSD's own second form and prints the one line the question was
-- asked on -- which is not always the console: asked down an rlogin it names the
-- pty and the machine at the far end.
--

local function sessionsOf(env)
	local net = linkOf(env)
	if net == nil or type(net.sessions) ~= "function" then return {} end
	local list = net.sessions()
	if type(list) ~= "table" then return {} end
	local out = {}
	for i = 1, #list do
		local one = list[i]
		if type(one) == "table" and type(one.user) == "string" then out[#out + 1] = one end
	end
	-- The console first and then the ptys in their own order, which is what
	-- sorting by the line's name gives: "console" is before "ttyp0".
	table.sort(out, function(a, b)
		return tostring(a.line) < tostring(b.line)
	end)
	return out
end

commands.who = function(state, session, args, env)
	local mine = false
	if #args == 3 and args[2] == "am" and (args[3] == "i" or args[3] == "I") then
		mine = true
	elseif #args ~= 1 then
		return usage("who")
	end
	local rows = sessionsOf(env)
	local out = {}
	for i = 1, #rows do
		local row = rows[i]
		if not mine or row.line == session.line then
			out[#out + 1] = CeroSecOS.whoLine(row.user,
				row.line or CeroSecOS.CONSOLE_LINE, row.at or 0, row.host)
		end
	end
	return true, out
end

--
-- last
--
-- /var/log/wtmp, newest first, which is the order last has printed since it was
-- written. A login with no logout behind it is still logged in and says so; one
-- with a logout carries how long it lasted, in the brackets last puts it in.
--
-- The file is two hundred lines deep and the oldest go: "wtmp begins" is
-- therefore a real answer on this machine rather than the formality it is on a
-- real one, and it is printed for exactly that reason.
--

commands.last = function(state, session, args, env)
	if #args > 2 then return usage("last") end
	-- last takes an account or a line, and anything that is neither simply
	-- matches nothing: there is no refusal to make about a name, because a name
	-- that has never logged in is not an error either.
	local who = args[2]
	local node, reason = CeroSecOS.getNode(state, session, CeroSecOS.WTMP_PATH)
	if node == nil then
		-- A machine nobody has logged into yet has no wtmp, and that is not a
		-- fault: it is an empty answer.
		if reason == "no such file" then return true, {} end
		return fail("last", CeroSecOS.WTMP_PATH, reason)
	end
	if node.type ~= "file" then
		return fail("last", CeroSecOS.WTMP_PATH, CeroSecOS.notAFile(node))
	end
	if not CeroSecOS.can(state, session, node, "r") then
		return fail("last", CeroSecOS.WTMP_PATH, "permission denied")
	end

	local recs = CeroSecOS.parseWtmp(node.data or "")
	-- Pair each login with the logout that closed it. A line that has been used
	-- twice over -- a session that closed and another that opened on the same
	-- pty -- pairs in the order the file has them, which is the order they
	-- happened in.
	local open, rows = {}, {}
	for i = 1, #recs do
		local rec = recs[i]
		if rec.kind == "in" then
			local row = { user = rec.user, line = rec.line, host = rec.host, at = rec.at }
			rows[#rows + 1] = row
			open[rec.line .. "/" .. rec.user] = row
		else
			local row = open[rec.line .. "/" .. rec.user]
			if row ~= nil then
				row.out = rec.at
				open[rec.line .. "/" .. rec.user] = nil
			end
		end
	end

	local out = {}
	for i = #rows, 1, -1 do
		local row = rows[i]
		if who == nil or row.user == who or row.line == who then
			out[#out + 1] = CeroSecOS.lastLine(row, row.out)
		end
	end
	if #recs > 0 then
		out[#out + 1] = ""
		out[#out + 1] = "wtmp begins " .. CeroSecOS.formatStamp(recs[1].at)
	end
	return true, out
end

--
-- The ptys
--
-- A session that came in over the wire lands on a pseudo-terminal, exactly as it
-- does on any Unix: ttyp0 to ttyp3, four of them, and the fifth caller is
-- refused. Every one of them is a shell running on the machine it landed on --
-- its files, its accounts, its four job slots, its twenty lines a second -- with
-- its screen on somebody else's glass.
--
-- The table is RUNTIME state and lives beside the machine's jobs, not in the
-- state that is saved: a reload has no jobs, so it can have no sessions either,
-- and what a survivor finds after a server restart is a machine at its own
-- prompt. It is the server that holds it and the server that hands it in here.
--
-- What the engine owns is the bookkeeping: which lines are taken, what a pty
-- remembers about where it came from, and the two records it writes into wtmp.
-- What the SERVER owns is the screen on it (pty.console) and the jobs it starts,
-- because both of those are things the engine has never heard of.
--

function CeroSecOS.ptyLine(n)
	return CeroSecOS.PTY_PREFIX .. tostring(math.floor(n))
end

-- Every pty in the order who(1) prints them, which is by the name of the line.
function CeroSecOS.ptyList(ptys)
	local out = {}
	if type(ptys) ~= "table" then return out end
	for n = 0, CeroSecOS.PTY_MAX - 1 do
		local pty = ptys[CeroSecOS.ptyLine(n)]
		if type(pty) == "table" then out[#out + 1] = pty end
	end
	return out
end

function CeroSecOS.ptyCount(ptys)
	return #CeroSecOS.ptyList(ptys)
end

-- A line for an inbound session, or nil plus the reason there is none.
--
-- The lowest free number, which is what a pty allocator has always handed out:
-- a session that closed frees its line and the next caller gets it, so a machine
-- nobody has rlogged into twice at once only ever shows ttyp0.
--
-- The refusal is "refused" and the caller wears it as BSD wears it --
-- "rlogin: connect: Connection refused" -- because a machine with every pty
-- taken is a machine whose listener has nothing left to accept with, and
-- ECONNREFUSED is exactly what a full backlog answers.
function CeroSecOS.remoteOpen(state, ptys, opts)
	if type(ptys) ~= "table" or type(opts) ~= "table" then return nil, "refused" end
	if type(opts.fromHost) ~= "string" then return nil, "refused" end
	for n = 0, CeroSecOS.PTY_MAX - 1 do
		local line = CeroSecOS.ptyLine(n)
		if ptys[line] == nil then
			local pty = {
				line = line,
				fromHost = opts.fromHost,
				fromAddr = opts.fromAddr,
				-- Which account the far end asked to come in as, and how many
				-- rlogins deep this one is. The hop count travels so that the
				-- session started FROM here knows it is one further out.
				want = opts.want,
				hops = math.floor(tonumber(opts.hops) or 1),
				at = opts.at,
				home = opts.home,
			}
			ptys[line] = pty
			return pty, nil
		end
	end
	return nil, "refused"
end

-- The pty a line belongs to, or nil for one that has gone: the machine was
-- switched off, the session was closed at the other end, somebody picked the
-- computer up. Every call that routes a keystroke goes through here, so a
-- keystroke can never reach a session that is over.
function CeroSecOS.remoteLine(ptys, line)
	if type(ptys) ~= "table" or type(line) ~= "string" then return nil end
	local pty = ptys[line]
	if type(pty) ~= "table" then return nil end
	return pty
end

-- The end of a session. The pty comes off the table and the logout goes into
-- wtmp -- but only when somebody actually got in: a caller who gave up at the
-- password prompt was never logged in and has no logout to record.
--
-- `user` is who was on it, which the server reads off the pty's own screen; the
-- engine is handed it rather than guessing, because who is logged in on a screen
-- is the console's business and the console is not the engine's.
function CeroSecOS.remoteClose(state, ptys, line, user, now)
	local pty = CeroSecOS.remoteLine(ptys, line)
	if pty == nil then return nil end
	ptys[line] = nil
	if type(user) == "string" and type(now) == "number" then
		CeroSecOS.wtmpAppend(state, "out", user, line, pty.fromHost, now)
	end
	return pty
end

--
-- rlogin, rsh, rcp
--
-- The three commands the BSD r-package gave a small network, and the three this
-- machine has. Every one of them ends in an order to whoever is running the
-- machine (the "rlogin", "rsh" and "rcp" controls), because everything that
-- happens afterwards happens on ANOTHER computer -- and the engine has never
-- heard of a second computer.
--
-- What the engine does before it hands over is everything that can be decided
-- from here: the name, whether the wire reaches, and how deep the chain already
-- is. What is left for the server is what only the far end knows: whether it has
-- a line free, and whether its /etc/hosts.equiv or the account's own ~/.rhosts
-- trusts this machine.
--

-- The refusals, in one place. They are strerror's own words for the errno a real
-- rlogin would have got, and which of them a caller is handed is the one thing
-- the link layer decides:
--
--   down    the machine is on the wire and is switched off      EHOSTDOWN
--   unreach there is no wire between here and there             EHOSTUNREACH
--   refused it answered and had nothing to accept with          ECONNREFUSED
--   denied  it answered and does not trust this machine         rshd's own word
CeroSecOS.NET_REASON = {
	down = "Host is down",
	unreach = "No route to host",
	refused = "Connection refused",
	denied = "Permission denied",
	unknown = "unknown host",
}

-- What the MODEM says, which is a different voice from the commands' and is
-- printed in capitals because that is how it came out of a Hayes-compatible
-- modem in 1993: the four result codes a dial can end in, and they are the
-- modem's words and not this machine's.
--
--   CONNECT 2400  the far modem answered and the carrier is up
--   BUSY          the line is in use -- this end's or the other end's
--   NO DIALTONE   the exchange is dead: the county has no power
--   NO CARRIER    nobody answered, or the carrier went away mid-call
--
-- There is no RING and no ATDT echo: the machine dials, it does not let a player
-- talk to the modem, and an AT command set would be a second language to learn
-- for a call that has exactly one thing to say.
CeroSecOS.MODEM = {
	connect = "CONNECT " .. CeroSecOS.PHONE_BAUD,
	busy = "BUSY",
	noDialtone = "NO DIALTONE",
	noCarrier = "NO CARRIER",
}

--
-- HOW LONG A DIAL TAKES, which is the other half of what a modem was: the result
-- code is the END of something a survivor sat through. Wall-clock seconds, like
-- every other delay on either link (CeroSec.PHONE_LINES_PER_S is a wall-clock
-- rate, and rcp's wait is wall-clock milliseconds) -- a call is a thing happening
-- in a room and not a thing happening in game hours.
--
--   4 seconds to CONNECT 2400. Off-hook, the tones, the far modem's answer tone
--     and the two of them agreeing on a speed: a 2400-baud handshake really did
--     take about that, and it is the one delay a player is glad to hear.
--   2 seconds to BUSY. The exchange returns busy tone as soon as it has looked the
--     number up, and the modem needs two of them to know a tone from an answer.
--   15 seconds to NO CARRIER, and that is the modem's S7 REGISTER: S7 is how long
--     a Hayes-compatible modem waits for a carrier after dialling before it gives
--     up and hangs up. The factory default was 30 or 50 depending on the model;
--     this machine's modem has S7=15, which is a SETTING and not a rule, and the
--     manual says so in those words so that it is a fact about this modem and not
--     a number somebody here invented.
CeroSecOS.MODEM_S7 = 15
CeroSecOS.RING_ANSWER_MS = 4000
CeroSecOS.RING_BUSY_MS = 2000
CeroSecOS.RING_TIMEOUT_MS = CeroSecOS.MODEM_S7 * 1000

-- How long the modem holds the line for an outcome. 0 for the two that are not a
-- ring at all: NO DIALTONE is what the receiver says the instant it is lifted, and
-- a machine with no line never lifted one.
function CeroSecOS.ringMs(word)
	if word == nil then return CeroSecOS.RING_ANSWER_MS end
	if word == CeroSecOS.MODEM.busy then return CeroSecOS.RING_BUSY_MS end
	if word == CeroSecOS.MODEM.noCarrier then return CeroSecOS.RING_TIMEOUT_MS end
	return 0
end

-- And what cu(1) itself says, which is BSD's own two lines: one when the
-- connection is made and one when it is over.
CeroSecOS.CU_CONNECTED = "Connected."
CeroSecOS.CU_DISCONNECTED = "Disconnected."

-- The one string on this rung that is nobody's but this game's, and it is here
-- because there is nothing in 4.4BSD to be faithful TO: a real cu is told which
-- line to use by /etc/remote and says "cu: unknown host" or "link down" about
-- one it cannot find, and neither of those is true of a computer standing in a
-- shed with no telephone in it. So the machine says the plain thing instead, in
-- cu's own shape -- the command's name, a colon, and what is wrong.
CeroSecOS.CU_NO_LINE = "cu: no phone line"

-- cu's escape, and the whole of what this machine implements of it. BSD's cu
-- reads a "~" at the start of a line as a word to ITSELF rather than to the far
-- machine, and "~." is the one that hangs up. The others -- "~!", "~%put",
-- "~$" -- are not here: they are a second shell and a file transfer, and this
-- rung has neither.
--
-- It is read by whatever is holding the near end of the line and never reaches
-- the far shell, which is why the server answers it (SCeroSecSystem Commands.exec)
-- and the engine only says what it looks like.
CeroSecOS.CU_ESCAPE = "~."

function CeroSecOS.isCuEscape(line)
	if type(line) ~= "string" then return false end
	return string.match(line, "^[ \t]*~%.[ \t]*$") ~= nil
end

-- How a refusal about a machine is signed. rcmd(3) prints some of these itself,
-- without the name of the program that called it; this machine signs every
-- refusal with the command that made it, exactly as the other sixty do.
--
-- "connect:" rather than the host name is BSD's own shape for a socket that
-- would not open at all, as against a name that would not resolve.
function CeroSecOS.netRefusal(cmd, host, kind)
	local reason = CeroSecOS.NET_REASON[kind] or CeroSecOS.NET_REASON.refused
	if kind == "refused" then return cmd .. ": connect: " .. reason end
	return cmd .. ": " .. tostring(host) .. ": " .. reason
end

-- host, addr, or nil plus the one line to print. The three commands share it, so
-- "unknown host" and "Host is down" read the same whichever was typed.
local function reach(state, session, env, cmd, word)
	local addr, name = CeroSecOS.resolveHost(state, word)
	if addr == nil then
		return nil, { cmd .. ": " .. word .. ": " .. CeroSecOS.NET_REASON.unknown }
	end
	local net = linkOf(env)
	local ok, why = false, "unreach"
	if addr == CeroSecOS.LOOPBACK_ADDR then
		ok = true
	elseif net ~= nil and type(net.reach) == "function" then
		ok, why = net.reach(addr)
	end
	if not ok then
		return nil, { CeroSecOS.netRefusal(cmd, name, why or "unreach") }
	end
	return name, addr
end

-- `-l user`, wherever it sits on the line: rlogin(1) takes it before the host
-- and behind it, and so does rsh.
-- words with the flag taken out, the account it named, and the refusal when it
-- named nothing at all.
local function takeLoginFlag(args, from)
	local words, want = {}, nil
	local i = from
	while i <= #args do
		if args[i] == "-l" then
			want = args[i + 1]
			if want == nil then return nil, nil, true end
			i = i + 2
		else
			words[#words + 1] = args[i]
			i = i + 1
		end
	end
	return words, want, false
end

-- How deep the chain this session is already part of. A session at the glass is
-- zero hops out; one that arrived over the wire carries the count on it.
local function hopsOf(session)
	if type(session) ~= "table" then return 0 end
	local n = tonumber(session.hops)
	if n == nil or n < 0 then return 0 end
	return math.floor(n)
end

commands.rlogin = function(state, session, args, env)
	local words, want, bad = takeLoginFlag(args, 2)
	if bad or words == nil or #words ~= 1 then return usage("rlogin") end
	if want == nil then want = CeroSecOS.userOf(session) end
	if not CeroSecOS.isValidName(want) then return usage("rlogin") end

	-- The hop ceiling, before anything is resolved: a chain that may not grow is
	-- a chain that may not look up a name either. A real rlogin has no such
	-- ceiling and no such message, so what this answers is the plainest true
	-- thing there is -- the connection was refused.
	if hopsOf(session) >= CeroSecOS.HOP_MAX then
		return false, { CeroSecOS.netRefusal("rlogin", nil, "refused") }
	end

	local host, addr = reach(state, session, env, "rlogin", words[1])
	if host == nil then return false, addr end
	-- Who is asking, as against who is being asked for: the trust files name the
	-- account COMING IN, and that is the account that typed the line and not the
	-- one -l asked to become.
	return true, { }, "rlogin", { host = host, addr = addr, user = want,
		from = CeroSecOS.userOf(session), hops = hopsOf(session) + 1 }
end

commands.rsh = function(state, session, args, env)
	local words, want, bad = takeLoginFlag(args, 2)
	if bad or words == nil or #words < 2 then return usage("rsh") end
	if want == nil then want = CeroSecOS.userOf(session) end
	if not CeroSecOS.isValidName(want) then return usage("rsh") end

	if hopsOf(session) >= CeroSecOS.HOP_MAX then
		return false, { CeroSecOS.netRefusal("rsh", nil, "refused") }
	end

	local host, addr = reach(state, session, env, "rsh", words[1])
	if host == nil then return false, addr end
	local line = {}
	for i = 2, #words do line[#line + 1] = words[i] end
	return true, { }, "rsh", { host = host, addr = addr, user = want,
		from = CeroSecOS.userOf(session), cmd = table.concat(line, " "),
		hops = hopsOf(session) + 1 }
end

--
-- cu
--
-- cu(1): call up another machine. It is the fourth command that reaches another
-- computer and the only one that does not go down the coax -- it dials the
-- telephone -- and it is deliberately the same SHAPE as rlogin, because that is
-- what a survivor already knows: a session on the far machine, on this glass,
-- ending at its own login prompt.
--
-- What it does NOT share with rlogin is trust. rlogin and rsh ask
-- /etc/hosts.equiv and ~/.rhosts because the machine at the other end of a wire
-- in the same building is a machine an office vouched for; a telephone call comes
-- from anywhere there is a telephone, and ruserok has never had anything to say
-- about one. So cu asks for a password every time, whatever either file says.
--
-- rsh and rcp do not dial at all, and that is BSD's own division: they are
-- NETWORK commands -- rcmd(3), a socket, a route -- and a dial is not a route.
-- A file over the telephone was uucp's job and uucp is not on this disk yet.
--
-- What the engine can decide is: the shape of the line, whether this machine has
-- a telephone line at all, and how deep the chain already is. Everything else --
-- a dial tone, a free line at either end, somebody to answer -- is the world's,
-- and the modem's words for it come back from the link layer.
--

commands.cu = function(state, session, args, env)
	if #args ~= 2 then return usage("cu") end
	if not CeroSecOS.isPhoneNumber(args[2]) then return usage("cu") end
	-- No telephone at all: the machine says so itself and never lifts the receiver.
	-- It is asked before the hop ceiling because it is the plainer fact of the two.
	local mine = CeroSecOS.phoneOf(state)
	if mine == nil then
		return false, { CeroSecOS.CU_NO_LINE }
	end
	-- The same ceiling rlogin pays, and for the same reason: every hop is a shell
	-- held open on a third machine's budget. What a chain at the ceiling gets is
	-- the modem's word for a call that cannot be put through, because on the
	-- telephone it is the modem that does the talking.
	if hopsOf(session) >= CeroSecOS.HOP_MAX then
		return false, { CeroSecOS.MODEM.busy }
	end
	local data = { tel = args[2], user = CeroSecOS.userOf(session),
		from = CeroSecOS.userOf(session), hops = hopsOf(session) + 1 }

	-- THE RING. What a dial really is: the modem goes off-hook, dials, and then
	-- there is nothing on the screen at all until the far end answers or the modem
	-- gives up. Which of the three it will be is the WORLD's to say, so it is asked
	-- of the link layer now -- and then the machine waits the time that outcome
	-- takes before it prints a word or opens a session (CeroSecOS.ringMs).
	--
	-- A machine with no link layer under it cannot be asked, and dials straight
	-- through: there is no world to ring in, which is what a bench is.
	local link = linkOf(env)
	if link == nil or type(link.phone) ~= "function" then
		return true, { }, "cu", data
	end
	local word = link.phone(args[2])
	local ms = CeroSecOS.ringMs(word)
	-- Nothing to wait for: no dial tone is what the receiver tells you the instant
	-- it is lifted, and a machine with no line never lifted one.
	if ms <= 0 then
		if word == nil then return true, { }, "cu", data end
		return false, { word }
	end
	-- The line is HELD for the length of the ring, at both ends, and the record of
	-- it is the waiting job itself (CeroSecNet.lineBusy reads it off there). `dial`
	-- is what makes the wait a dial rather than a pause: it is the name the refusal
	-- wears if there is no terminal to hand a session to, and it is checked before
	-- the wait and not after it.
	return true, { }, "sleep", { ms = ms, dial = "cu",
		ring = { tel = mine, to = args[2], abort = CeroSecOS.MODEM.noCarrier },
		cont = { cmd = "cu", word = word, data = data } }
end

-- The far end has answered, or has not. Whichever it was, it was decided before
-- the ring began and the ring is what the survivor paid for it: a call that went
-- through opens the session here, and one that did not prints the modem's word.
--
-- Asked of the world AGAIN at the door (CeroSecNet.dialPhone), and deliberately:
-- four seconds is time for the far machine to be switched off, and what a caller
-- gets then is NO CARRIER rather than a session on a computer that has gone.
CeroSecOS.continuations.cu = function(state, session, cont, line, env)
	if type(cont) ~= "table" then return false, { CeroSecOS.MODEM.noCarrier } end
	if cont.word ~= nil then return false, { cont.word } end
	if type(cont.data) ~= "table" then return false, { CeroSecOS.MODEM.noCarrier } end
	return true, { }, "cu", cont.data
end

--
-- rcp
--

-- How fast the wire is, in bytes a second, and the least a transfer can take.
-- Both are this machine's own numbers: there is nothing to measure and a copy
-- that came back instantly would be a copy the player had no reason to believe
-- had crossed anything. A file is 4096 bytes at the most, so the slowest
-- transfer there is takes under four seconds.
CeroSecOS.RCP_BYTES_PER_SEC = 1200
CeroSecOS.RCP_MIN_MS = 200

-- "host:path" -> host, path. nil when the word is a plain local path, which is
-- rcp's own rule: a colon makes it remote only when there is no "/" in front of
-- it, so ./a:b is a file and gate:/tmp/a is a machine.
function CeroSecOS.splitRemote(word)
	if type(word) ~= "string" then return nil end
	local colon = string.find(word, ":", 1, true)
	if colon == nil then return nil end
	local head = string.sub(word, 1, colon - 1)
	if string.find(head, "/", 1, true) ~= nil then return nil end
	if not CeroSecOS.isValidHostname(head) and not CeroSecOS.isAddress(head) then
		return nil
	end
	return head, string.sub(word, colon + 1)
end

commands.rcp = function(state, session, args, env)
	if #args ~= 3 then return usage("rcp") end
	local fromHost, fromPath = CeroSecOS.splitRemote(args[2])
	local toHost, toPath = CeroSecOS.splitRemote(args[3])
	-- Exactly one end is somewhere else. rcp itself will copy between two
	-- remote machines and between two local paths; this one will not -- the
	-- first needs a third connection and the second is `cp`, which is already
	-- on the disk. Neither is a refusal to invent: it is the usage line, which
	-- is what this machine answers every wrong invocation with.
	if (fromHost == nil) == (toHost == nil) then return usage("rcp") end

	local word = fromHost or toHost
	local host, addr = reach(state, session, env, "rcp", word)
	if host == nil then return false, addr end

	local net = linkOf(env)
	if net == nil or type(net.copy) ~= "function" then
		return false, { CeroSecOS.netRefusal("rcp", host, "unreach") }
	end
	local spec = {
		addr = addr, host = host, user = CeroSecOS.userOf(session),
		-- Where the caller is standing, so the local half of the copy resolves a
		-- relative path the way every other command on the line does. The tilde is
		-- already gone: the shell expanded it before this command saw a thing.
		cwd = session.cwd or "/",
		-- Who is copying, for the far machine's trust files: the ADDRESS, which is
		-- the only thing about a caller the caller did not choose. fromHost travels
		-- beside it because rcp's own refusal names the machine, and is nothing the
		-- far end decides anything by.
		fromHost = CeroSecOS.hostname(state),
		fromAddr = CeroSecOS.address(state),
		push = toHost ~= nil,
		remote = toPath or fromPath,
		["local"] = args[3],
	}
	if spec.push then spec["local"] = args[2] end
	local done, reason, bytes = net.copy(spec)
	if not done then
		-- rcp signs its refusals with the file they were about, whichever end of
		-- the wire that file was on.
		local about = spec.remote
		if reason == CeroSecOS.NET_REASON.denied then about = host end
		return false, { "rcp: " .. tostring(about) .. ": " .. tostring(reason) }
	end

	-- The bytes have landed; what is left is the time the wire would have taken.
	-- Waiting after the write rather than before it is a difference nobody can
	-- see: nothing of this command answers until the wait is over, and there is
	-- no second command on the machine that could look in between -- a pipeline
	-- stage behind it is waiting on the same job.
	local ms = math.floor((tonumber(bytes) or 0) * 1000 / CeroSecOS.RCP_BYTES_PER_SEC)
	if ms < CeroSecOS.RCP_MIN_MS then ms = CeroSecOS.RCP_MIN_MS end
	return true, {}, "sleep", { ms = ms, cont = { cmd = "rcp" } }
end

-- rcp says nothing at all when it worked, which is what every copy on this
-- machine says: the token the clock answers is there to end the wait and not to
-- print anything.
CeroSecOS.continuations.rcp = function(state, session, cont, line, env)
	return true, {}
end
