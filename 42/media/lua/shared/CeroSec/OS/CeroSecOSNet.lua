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
	return { b1 = b1, b2 = b2, n = n, wrote = net.wrote and true or false }
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
-- wire, and it hands over three numbers it has worked out.
function CeroSecOS.setNetRecord(state, b1, b2, n)
	if type(state) ~= "table" then return nil end
	if CeroSecOS.addressText(b1, b2, n) == nil then return nil end
	state.net = { b1 = math.floor(b1), b2 = math.floor(b2), n = math.floor(n) }
	return CeroSecOS.netRecord(state)
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
	if not CeroSecOS.isValidHostname(words[1]) then return nil end
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

-- Does this list let `fromUser` on `fromHost` in as `asUser`? The two forms,
-- and no third.
local function equivAllows(entries, fromHost, fromUser, asUser)
	for i = 1, #entries do
		local entry = entries[i]
		if entry.host == fromHost then
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
function CeroSecOS.equivOk(state, fromHost, fromUser, asUser)
	if type(fromHost) ~= "string" or type(asUser) ~= "string" then return false end
	if type(fromUser) ~= "string" then return false end
	-- root is never trusted by /etc/hosts.equiv. That is ruserok's own rule and
	-- the most important line in it: a machine that let the root of any trusted
	-- host in as its own root would be a machine whose password is the weakest
	-- root password on the wire.
	if asUser == "root" then return false end
	local node = CeroSecOS.systemNode(state, CeroSecOS.EQUIV_PATH)
	if node == nil or node.type ~= "file" then return false end
	return equivAllows(CeroSecOS.parseEquiv(node.data or ""), fromHost, fromUser, asUser)
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
function CeroSecOS.rhostsOk(state, asUser, fromHost, fromUser)
	if type(asUser) ~= "string" or type(fromHost) ~= "string" then return false end
	if type(fromUser) ~= "string" then return false end
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
	return equivAllows(CeroSecOS.parseEquiv(node.data or ""), fromHost, fromUser, asUser)
end

-- Does one octal digit of a mode carry its write bit? The middle bit of three,
-- worked out with division because the core has no bit library.
function CeroSecOS.digitWritable(digit)
	if type(digit) ~= "number" then return false end
	return math.fmod(math.floor(math.floor(digit) / 2), 2) == 1
end

-- The question rlogind and rshd both ask, and the order they ask it in: the
-- machine's own list first, then the account's. Either is enough.
function CeroSecOS.trusts(state, asUser, fromHost, fromUser)
	if CeroSecOS.equivOk(state, fromHost, fromUser, asUser) then return true end
	return CeroSecOS.rhostsOk(state, asUser, fromHost, fromUser)
end

-- What a machine ships with: nothing trusted, and a line saying what a line
-- would look like. An office that wanted its machines to trust each other wrote
-- the names in; one that did not, did not.
function CeroSecOS.defaultEquiv()
	return "# host [user] -- one a line; a bare host trusts the same name on it\n"
		.. "# nothing is trusted until somebody writes a line here"
end

--
-- /var/log/wtmp
--

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
	if host ~= "-" and not CeroSecOS.isValidHostname(host) then return nil end
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
		fromHost = CeroSecOS.hostname(state),
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
