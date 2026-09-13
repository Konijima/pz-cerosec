if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/OS/CeroSecOS"

--
-- What the server knows about itself, as rows of text.
--
-- The debug window (client/CeroSec/CeroSecDebugUI.lua) draws these and works
-- nothing out: every row here is built by asking the function that OWNS the
-- answer -- CeroSecOS.hostname, CeroSecOS.address, CeroSecNet.lineOf,
-- CeroSecDevices.snapshot, CeroSecOS.usage, CeroSecOS.cronDue -- so a change that
-- moves one of those rules moves what this window shows with it and nobody has
-- to remember to come back here. A debug window that had a copy of a rule in it
-- would be a debug window that tells you what the code used to do.
--
-- It is READ-ONLY, with no exception. Nothing in this file writes a field, makes
-- a node, starts a job or touches the world; the three buttons the window has go
-- through the ordinary server commands like anything else (SCeroSecSystem).
--
-- EVERY LIST IS BOUNDED, because a snapshot goes on the wire and a county is not
-- a fixed size: a thousand-computer save must not put a thousand rows through
-- sendServerCommand ten times a minute. The caps are below and every one of them
-- is reported to the window, so a truncated list says so on the glass instead of
-- quietly being the whole truth.
--
-- HOW EXPENSIVE IT IS ALLOWED TO BE. The machine LIST reads each machine's state
-- raw -- CeroSecOS.hostname and friends on luaObject.os, never luaObject:osState()
-- -- for exactly the reason CeroSecNet.recordOf gives: osState migrates, tops up
-- and validates a whole filesystem, and a list that did it once per computer
-- would walk every disk in the county every two seconds. The three tabs that are
-- about ONE machine ask osState of that one machine, which is one disk.
--

CeroSecDebug = CeroSecDebug or {}

-- Machines in the list, rows in a file tree, entries in /dev, and jobs in the
-- scheduler's list. Four caps and not one, because the four lists are four
-- different sizes in the same save.
CeroSecDebug.MACHINE_MAX = 200
CeroSecDebug.FILE_MAX = 512
CeroSecDebug.DEV_MAX = 128
CeroSecDebug.JOB_MAX = 128

-- Rows in each section of the Network tab. One number for all of them: a
-- section of the wire that needs more than this to describe it is a section
-- nobody is reading on a list box anyway.
CeroSecDebug.NET_MAX = 64

-- Zones reported for the selected machine's square. Sixteen: a square in Louisville
-- can be inside a town zone, a district zone, a story zone and a handful of loot
-- zones at once, and sixteen is more than any square in the shipped map has.
CeroSecDebug.ZONE_MAX = 16

-- Characters in one cell. A hostname is validated and short; a path is not
-- (CeroSecOS.MAX_DEPTH components of CeroSecOS.MAX_NAME), and neither is a cron
-- line. Truncated with the same "~" the terminal truncates with, so a cell that
-- was cut says so.
CeroSecDebug.CELL_MAX = 64

-- Lines one `print` of a state dump may be. The dump goes to the game log, which
-- is a file somebody has to read: sixteen hundred lines of one computer's disk is
-- a dump, four hundred thousand is a denial of service against a text editor.
CeroSecDebug.DUMP_MAX = 400

-- The tabs this file answers for. The window's sixth tab (the log) is the
-- client's own ring buffer and is not a snapshot: see docs/DEBUG.md.
CeroSecDebug.TABS = { "machines", "files", "devices", "network", "scheduler" }

function CeroSecDebug.isTab(name)
	for i = 1, #CeroSecDebug.TABS do
		if CeroSecDebug.TABS[i] == name then return true end
	end
	return false
end

--
-- Cells
--

local function cell(value)
	if value == nil then return "-" end
	if value == true then return "yes" end
	if value == false then return "no" end
	return CeroSec.truncate(tostring(value), CeroSecDebug.CELL_MAX)
end

-- A row of cells, each one through cell() so nothing untruncated and nothing of
-- a type the wire does not carry can get onto it. The coordinates are optional
-- and are what makes a row selectable: the Machines tab puts them on so that
-- clicking a row names a machine, and no other tab has a machine to name.
local function row(cells, x, y, z)
	local out = {}
	for i = 1, #cells do out[i] = cell(cells[i]) end
	return { c = out, x = x, y = y, z = z }
end

local function pos(x, y, z)
	return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

--
-- One machine, the cheap way
--

-- How many windows are open on it.
function CeroSecDebug.watcherCount(luaObject)
	local n = 0
	if type(luaObject.watchers) == "table" then
		for _ in pairs(luaObject.watchers) do n = n + 1 end
	end
	return n
end

-- How many jobs it is running, through the engine's own count so that the
-- prompt's own job is not one of them here either.
function CeroSecDebug.jobCount(luaObject)
	if type(luaObject.jobs) ~= "table" or type(luaObject.jobs.list) ~= "table" then
		return 0, 0
	end
	return CeroSecOS.liveJobs(luaObject.jobs.list), #luaObject.jobs.list
end

-- Has it got a wire in the wall? Asked of the SQUARE, so the only honest answer
-- for a machine whose chunk is away is "nobody to ask" -- which is the rule
-- SCeroSecObject:hasPower is written around, and nil is how it is said here.
function CeroSecDebug.powerOf(luaObject)
	if not luaObject:isLoaded() then return nil end
	return luaObject:hasPower() and true or false
end

-- Has this machine ever been anything but a sprite the streamer walked past?
--
-- The server holds a machine for EVERY computer sprite any chunk has ever brought
-- in: the engine hands each object of each loaded square to isValidIsoObject and
-- makes a global object for the ones that answer yes
-- (SGlobalObjectSystem:loadIsoObject, media/lua/server/Map/SGlobalObjectSystem.lua:133-146).
-- So a save an hour old holds every screen in every office the survivor has walked
-- through -- forty-four of them, dark, with nothing in any column but their
-- position -- and the handful the mod is actually doing something with are
-- somewhere in the middle of that list.
--
-- The ones worth showing by default are the ones with something ON them: switched
-- on, or carrying a disk of their own. self.os stays nil until a machine is first
-- used, which is the whole point of it being nil (SCeroSecObject:initNew), so it is
-- exactly the right question and costs no disk read at all.
function CeroSecDebug.isUsed(luaObject)
	if luaObject.on then return true end
	return type(luaObject.os) == "table"
end

--
-- What the selected machine can be asked to do
--
-- The window greys a button with these and prints the reason under the list, and
-- neither answer is its own. Both are decided HERE, by the same readings the act
-- itself goes through -- SCeroSecObject:turnOn refuses on hasPower, and hasPower is
-- asked of a SQUARE -- so a button greyed in the window is a button whose act the
-- server would refuse, and the day the rule moves the window moves with it.
--
-- This is the hole found in play: "Turn on" was enabled on a machine whose
-- chunk was away, the press went out on the wire, turnOn refused for want of a
-- square to ask about the wire, the boolean was dropped, and nothing at all
-- happened on the glass.
--
-- nil for no refusal, which is what "it can be turned on" is.
function CeroSecDebug.turnOnRefusal(luaObject)
	if luaObject == nil then return "nothing is selected" end
	if luaObject.on then return "it is already on" end
	-- The chunk before the wire, because the wire is asked of a square and a
	-- machine nobody has streamed in has none: hasPower answers false for want of
	-- anybody to ask, and that is not the same sentence as "the room has no power"
	-- (the note on SCeroSecObject:checkPower, and the sweep that once switched off
	-- every computer behind a walking survivor).
	if not luaObject:isLoaded() then
		return "its chunk is away, so there is nobody to ask about the wire" ..
			" -- teleport to it first"
	end
	if not luaObject:hasPower() then return "there is no wire at its square" end
	return nil
end

-- Turning OFF asks nothing of the world: the power is a fact the server holds, and
-- a machine on the far side of the map with its chunk away goes off when it is told
-- to (SCeroSecObject:turnOff, which checks nothing but self.on).
function CeroSecDebug.turnOffRefusal(luaObject)
	if luaObject == nil then return "nothing is selected" end
	if not luaObject.on then return "it is already off" end
	return nil
end

-- And the developer's reset, which asks the world nothing at all: it throws a
-- state away and puts a fresh machine in its place (SCeroSecObject:resetMachine),
-- and a machine on the far side of the county with its chunk away is reset exactly
-- like one in the room. The one thing it wants is a machine that has STOPPED: a
-- reset on a running computer would take its jobs and its screen away behind the
-- back of everybody standing at it.
function CeroSecDebug.resetRefusal(luaObject)
	if luaObject == nil then return "nothing is selected" end
	if luaObject.on then return "it is on -- switch it off first" end
	return nil
end

-- The fields every snapshot carries about the SELECTED machine, whatever tab was
-- asked for -- because the buttons under the list are the same seven on every tab.
function CeroSecDebug.selection(snap, luaObject)
	local why = CeroSecDebug.turnOnRefusal(luaObject)
	snap.canTurnOn = why == nil
	snap.reason = why
	snap.canTurnOff = CeroSecDebug.turnOffRefusal(luaObject) == nil
	-- Its own reason and not `reason`: that one is turnOn's, and a window that
	-- printed "it is already on" for a refused reset would be a window blaming the
	-- wrong rule.
	local noReset = CeroSecDebug.resetRefusal(luaObject)
	snap.canReset = noReset == nil
	snap.resetReason = noReset
	snap.on = luaObject ~= nil and luaObject.on and true or false
	snap.loaded = luaObject ~= nil and luaObject:isLoaded() and true or false
	return snap
end

--
-- 1. Machines
--
-- Every machine the server holds, loaded chunk or not -- which is every computer
-- in the county that has ever been switched on (see the head of SCeroSecNet.lua).
--
function CeroSecDebug.machines(system)
	local rows = {}
	local total = system:getLuaObjectCount() or 0
	for i = 1, total do
		if #rows >= CeroSecDebug.MACHINE_MAX then break end
		local luaObject = system:getLuaObjectByIndex(i)
		if luaObject ~= nil then
			local state = luaObject.os
			local live = CeroSecDebug.jobCount(luaObject)
			local made = row({
				pos(luaObject.x, luaObject.y, luaObject.z),
				luaObject.facing,
				luaObject.on and "on" or "off",
				luaObject:isLoaded() and "here" or "away",
				CeroSecDebug.powerOf(luaObject),
				CeroSecOS.hostname(state),
				CeroSecOS.address(state),
				CeroSecNet.lineOf(luaObject),
				CeroSecOS.callsignOf(state),
				live,
				CeroSecDebug.watcherCount(luaObject),
			}, luaObject.x, luaObject.y, luaObject.z)
			-- What the window's "used only" filter reads. On the ROW and not in the
			-- info block, because it is a fact about that machine and the filter is
			-- applied to one row at a time.
			made.used = CeroSecDebug.isUsed(luaObject)
			rows[#rows + 1] = made
		end
	end
	return {
		rows = rows,
		info = {
			"machines: " .. #rows .. " of " .. total ..
				" (cap " .. CeroSecDebug.MACHINE_MAX .. ")",
		},
	}
end

-- Everything about ONE machine, as the lines under the list. This is the one
-- place the selected machine's own disk is opened -- osState, with its migration
-- and its validation -- because it is one machine and not a county.
function CeroSecDebug.machineDetail(system, luaObject)
	if luaObject == nil then return { "no machine selected" } end
	local state, refusal = luaObject:osState()
	local console = luaObject.console
	local live, held = CeroSecDebug.jobCount(luaObject)

	local out = {}
	out[#out + 1] = "at " .. pos(luaObject.x, luaObject.y, luaObject.z) ..
		"  facing " .. cell(luaObject.facing) ..
		-- The OBJECT's own schema (CeroSec.STATE_VERSION), which is not the disk's: the
		-- shape the filesystem is in is CeroSecOS.STATE_VERSION and is printed beside
		-- sysv below, where the state it belongs to is.
		"  obj v" .. cell(luaObject.v) ..
		"  sprite " .. cell(CeroSec.spriteFor(luaObject.facing, luaObject.on))
	out[#out + 1] = "power " .. (luaObject.on and "on" or "off") ..
		"  chunk " .. (luaObject:isLoaded() and "loaded" or "away") ..
		"  wire " .. cell(CeroSecDebug.powerOf(luaObject)) ..
		"  disk " .. cell(luaObject:hasDisk())
	if state == nil then
		out[#out + 1] = "os: REFUSED (" .. cell(refusal) .. ")"
	else
		out[#out + 1] = "host " .. cell(CeroSecOS.hostname(state)) ..
			"  addr " .. cell(CeroSecOS.address(state)) ..
			"  tel " .. cell(CeroSecNet.lineOf(luaObject)) ..
			"  call " .. cell(CeroSecOS.callsignOf(state))
		local ok, why = CeroSecOS.systemOk(state)
		-- The two numbers a save carries, side by side, because they are the two
		-- questions an update raises and neither was readable anywhere in the game: `os
		-- v` is the SHAPE the migration chain walked this machine up to
		-- (CeroSecOS.STATE_VERSION), `sysv` is the CONTENTS upgradeSystem topped it up
		-- to (CeroSecOS.SYSTEM_VERSION). A machine off an older save shows both at this
		-- build's numbers, and that is how the in-game checklist constates a migration
		-- instead of asserting one (docs/PARCOURS-TEST.md, section Z).
		out[#out + 1] = "system " .. (ok and "ok" or ("NOT OK: " .. cell(why))) ..
			"  os v" .. cell(state.v) .. "  sysv " .. cell(state.sysv)
	end
	if type(console) ~= "table" then
		out[#out + 1] = "console: none (the machine is off)"
	else
		out[#out + 1] = "console booted=" .. cell(console.booted and true or false) ..
			" user=" .. cell(console.user) ..
			" cwd=" .. cell(console.cwd) ..
			" mode=" .. cell(CeroSec.consoleMode(console)) ..
			" lines=" .. cell(#(console.lines or {}))
		out[#out + 1] = "console waiting=" .. cell(CeroSec.consoleWaiting(console)) ..
			" active=" .. cell(CeroSec.consoleActive(console)) ..
			" halted=" .. cell(CeroSec.consoleHalted(console)) ..
			" job=" .. cell(console.job) ..
			" remote=" .. cell(console.remote ~= nil)
	end
	out[#out + 1] = "jobs " .. live .. " live of " .. held .. " held" ..
		"  ptys " .. cell(CeroSecOS.ptyCount(luaObject.ptys)) ..
		"  windows " .. cell(CeroSecDebug.watcherCount(luaObject)) ..
		"  shutdown " .. cell(CeroSecJobs.pendingShutdown(luaObject) ~= nil)

	local premises = CeroSecDebug.premises(luaObject)
	for i = 1, #premises do out[#out + 1] = premises[i] end
	return out
end

--
-- Where the machine STANDS
--
-- The building's footprint, the room, and every zone the square is inside. Three
-- facts about a place and not about a computer, and they are here because the
-- telephone work's rules are about to be written against them: a survivor standing
-- at a computer in a mall has to be able to see that the named zone he is in is
-- SMALLER than the building around it, and no command of the machine's says so.
--
-- All of it is asked of the WORLD, so a machine whose chunk is away has none of it
-- and says so -- the same rule /dev and the power check wear, and for the same
-- reason: there is nobody to ask.
--
-- The calls, verified with javap against projectzomboid.jar (42.20.4) and used the
-- way vanilla's own Lua uses them:
--
--   zombie.iso.IsoGridSquare
--     public zombie.iso.areas.IsoBuilding getBuilding();
--     public zombie.iso.areas.IsoRoom getRoom();
--   zombie.iso.areas.IsoBuilding
--     public zombie.iso.BuildingDef getDef();
--   zombie.iso.BuildingDef
--     public int getX();  getY();  getX2();  getY2();  getArea();
--     -- the corner and the far corner of the footprint, which is where the
--     -- building IS on the map and does not move (see CeroSecNet.buildingOf).
--     -- x2 is EXCLUSIVE: getW() is `getfield x2; getfield x; isub` with no
--     -- iconst_1, so the width is x2 - x and not x2 - x + 1. getArea() is not
--     -- the box at all -- it walks `rooms` and sums RoomDef.getArea() -- which
--     -- is why the size printed here is derived and the area is asked for.
--   zombie.iso.areas.IsoRoom
--     public java.lang.String getName();
--     public zombie.iso.RoomDef getRoomDef();
--   zombie.iso.RoomDef
--     public java.lang.String getName();
--   zombie.iso.IsoWorld
--     public zombie.iso.IsoMetaGrid getMetaGrid();
--   zombie.iso.IsoMetaGrid
--     public java.util.ArrayList<zombie.iso.zones.Zone> getZonesAt(int, int, int);
--     -- an ArrayList, walked 0..size()-1, exactly as vanilla walks it in
--     -- media/lua/client/ISUI/AdminPanel/LootZed/SpawnRateChecker.lua:70-72.
--   zombie.iso.zones.Zone
--     public java.lang.String getName();  getType();
--     public int getX();  getY();  getZ();  getWidth();  getHeight();
--     public float getTotalArea();
--     -- the same seven things the class also carries as public fields
--     -- (name, type, x, y, z, w, h), read through the getters because those are
--     -- what vanilla's own Lua reads.
--
-- Both areas are reported and that is deliberate: w x h is the BOUNDING BOX, and
-- getTotalArea is the area the game actually computes -- for a polygon or a
-- polyline zone they are different numbers, and telling them apart is the whole
-- point of looking at a mall.
function CeroSecDebug.premises(luaObject)
	local out = {}
	local square = luaObject:getSquare()
	if square == nil then
		out[#out + 1] = "premises: no square (the chunk is away)"
		return out
	end

	-- The building. Its footprint and not its IsoBuilding id: the id is handed out
	-- by a counter at load time and is a different number next session, while the
	-- def's corners are where the building stands (the note on
	-- CeroSecNet.buildingOf).
	local building = square:getBuilding()
	local def = nil
	if building ~= nil then def = building:getDef() end
	if def == nil then
		out[#out + 1] = "building: outdoors (no map building)"
	else
		local x1, y1, x2, y2 = def:getX(), def:getY(), def:getX2(), def:getY2()
		out[#out + 1] = "building: " .. cell(x1) .. "," .. cell(y1) ..
			" to " .. cell(x2) .. "," .. cell(y2) ..
			"  " .. cell(x2 - x1) .. "x" .. cell(y2 - y1) ..
			"  area " .. cell(def:getArea()) ..
			"  rooms " .. cell(def:getRoomsNumber())
	end

	-- The room. Its def's name, which is the name the map was drawn with; the
	-- IsoRoom's own getName answers the same string and is asked only when there is
	-- no def to ask.
	local room = square:getRoom()
	if room == nil then
		out[#out + 1] = "room: none"
	else
		local roomDef = room:getRoomDef()
		local name = nil
		if roomDef ~= nil then name = roomDef:getName() else name = room:getName() end
		out[#out + 1] = "room: " .. cell(name)
	end

	-- The zones. A square can be inside several at once -- a town, a district, a
	-- story, a loot zone -- and which of them is the SMALLEST is the question the
	-- telephone work is going to ask.
	if getWorld == nil then return out end
	local world = getWorld()
	if world == nil then return out end
	local grid = world:getMetaGrid()
	if grid == nil then return out end
	local zones = grid:getZonesAt(luaObject.x, luaObject.y, luaObject.z)
	if zones == nil then
		out[#out + 1] = "zones: none"
		return out
	end
	local total = zones:size()
	if total == 0 then
		out[#out + 1] = "zones: none"
		return out
	end
	out[#out + 1] = "zones: " .. cell(total) ..
		(total > CeroSecDebug.ZONE_MAX and
			(" (showing " .. CeroSecDebug.ZONE_MAX .. ")") or "")
	for i = 0, total - 1 do
		if i >= CeroSecDebug.ZONE_MAX then break end
		local zone = zones:get(i)
		if zone ~= nil then
			local w, h = zone:getWidth(), zone:getHeight()
			out[#out + 1] = "  zone " .. cell(zone:getType()) ..
				" name " .. cell(zone:getName()) ..
				"  " .. cell(zone:getX()) .. "," .. cell(zone:getY()) ..
				" " .. cell(w) .. "x" .. cell(h) ..
				"  box " .. cell(w * h) ..
				"  area " .. cell(zone:getTotalArea())
		end
	end
	return out
end

--
-- 2. Files
--

-- The tree, depth first, in the order `ls` would print each directory: the
-- engine's own sorted child names, so two runs of this cannot disagree.
local function walkTree(node, path, rows, depth)
	if #rows >= CeroSecDebug.FILE_MAX then return end
	local nodes, bytes = CeroSecOS.subtreeUsage(node)
	local size = bytes
	if node.type == "file" then
		size = #(node.data or "")
	elseif node.type == "link" then
		size = #(node.target or "")
	elseif node.type == "dev" then
		size = 0
	end
	rows[#rows + 1] = row({
		path == "" and "/" or path,
		node.type,
		CeroSecOS.permString(node),
		node.owner,
		size,
		CeroSecOS.formatStamp(CeroSecOS.mtimeOf(node)),
		node.type == "dir" and nodes or "",
	})
	if node.type ~= "dir" or node.children == nil then return end
	if depth > CeroSecOS.MAX_DEPTH then return end
	local names = CeroSecOS.childNames(node)
	for i = 1, #names do
		walkTree(node.children[names[i]], path .. "/" .. names[i], rows, depth + 1)
	end
end

function CeroSecDebug.files(system, luaObject)
	if luaObject == nil then return { rows = {}, info = { "no machine selected" } } end
	local state, refusal = luaObject:osState()
	if state == nil then
		return { rows = {}, info = { "os refused: " .. cell(refusal) } }
	end

	local rows = {}
	if type(state.fs) == "table" then walkTree(state.fs, "", rows, 1) end

	-- The ceilings, asked of the functions that enforce them rather than counted
	-- here: a debug window that added its own bytes up would be a second df.
	local nodes, bytes = CeroSecOS.usage(state)
	local exempt = CeroSecOS.exemptUsage(state)
	return {
		rows = rows,
		info = {
			"nodes " .. nodes .. " of " .. CeroSecOS.MAX_NODES ..
				"   bytes " .. bytes .. " of " .. CeroSecOS.MAX_TOTAL_BYTES ..
				"   exempt " .. exempt .. " of " .. CeroSecOS.MAX_EXEMPT_BYTES,
			"rows " .. #rows .. " (cap " .. CeroSecDebug.FILE_MAX .. ")",
		},
	}
end

-- The whole state table, to the game log, in bounded chunks.
--
-- print and not a reply: a state is tens of kilobytes and a log file is where
-- something that size belongs. On a dedicated server it lands in the server's
-- log, which is also where an operator would go looking for it.
--
-- Answers how many lines it wrote.
function CeroSecDebug.dump(luaObject)
	if luaObject == nil then return 0 end
	local written = 0
	local function say(text)
		if written >= CeroSecDebug.DUMP_MAX then return false end
		written = written + 1
		print("CeroSec dump: " .. text)
		return true
	end

	say("machine at " .. pos(luaObject.x, luaObject.y, luaObject.z))
	local state = luaObject:osState()
	if state == nil then
		say("  (no state)")
		return written
	end

	-- Depth first, one line per key, values as text. Never a key that is not a
	-- string or a number and never a value that is not one of the four the game's
	-- own serializer keeps, because a state that carried anything else is a state
	-- validate refused long before this.
	local function walk(value, prefix, depth)
		if depth > 12 then
			say(prefix .. " ...")
			return
		end
		if type(value) ~= "table" then
			return say(prefix .. " = " .. tostring(value))
		end
		local keys = {}
		for key in pairs(value) do keys[#keys + 1] = tostring(key) end
		table.sort(keys)
		for i = 1, #keys do
			local key = keys[i]
			local at = value[key]
			if at == nil then at = value[tonumber(key)] end
			if not say(prefix .. "." .. key ..
					(type(at) == "table" and "" or (" = " .. tostring(at)))) then
				return
			end
			if type(at) == "table" then walk(at, prefix .. "." .. key, depth + 1) end
		end
		return true
	end
	walk(state, "  os", 1)
	if written >= CeroSecDebug.DUMP_MAX then
		-- Counted like any other line, because what is returned is what was
		-- printed: a number that did not count its own last line would be a
		-- number nothing could be checked against.
		written = written + 1
		print("CeroSec dump: cut at " .. CeroSecDebug.DUMP_MAX .. " lines")
	end
	return written
end

--
-- 3. Devices
--

function CeroSecDebug.devices(system, luaObject)
	if luaObject == nil then return { rows = {}, info = { "no machine selected" } } end
	local state, refusal = luaObject:osState()
	if state == nil then
		return { rows = {}, info = { "os refused: " .. cell(refusal) } }
	end

	-- The device layer's own discovery and its own numbering. Never a walk of our
	-- own: the numbers are spent for the life of the machine and a second
	-- numbering would hand out different ones.
	local list, byId = CeroSecDevices.snapshot(luaObject, state)
	local rows = {}
	for i = 1, #list do
		if #rows >= CeroSecDebug.DEV_MAX then break end
		local entry = list[i]
		local found = byId[entry.id]
		local where, sprite, here = nil, nil, nil
		if found ~= nil then
			where = pos(found.x, found.y, found.z)
			here = found.object ~= nil and found.object:getSquare() ~= nil
			-- What a highlight would carry for it, through the device layer's own
			-- accessor: the sprite name of a fixture, the full type of a dropped
			-- head, and nothing at all for a light -- a light blinks rather than
			-- being pointed at, so there is no handle to show and getSpriteName is
			-- a call the mod does not make on a switch.
			local _, name, item = CeroSecDevices.handleOf(found)
			if name ~= nil and name ~= "" then
				sprite = name
			elseif item ~= nil and item ~= "" then
				sprite = item
			end
		end
		rows[#rows + 1] = row({
			entry.id, entry.kind, entry.desc, entry.side,
			CeroSecOS.permString({ type = "dev", mode = entry.mode }),
			entry.pos, where, sprite, entry.state,
			entry.dead and "gone" or (here and "here" or "away"),
		})
	end

	-- And the sensors this machine can reach, out of the sampling book -- the
	-- record itself, since what a sensor READS is stateAt's to say and is already
	-- in the rows above.
	local sensors = {}
	for i = 1, #list do
		local found = byId[list[i].id]
		if found ~= nil and found.kind == "sensor" then
			local record = CeroSecSensors.book[
				CeroSecSensors.keyAt(found.x, found.y, found.z, found.n or 0)]
			if record == nil then
				sensors[#sensors + 1] = list[i].id .. ": not in the book"
			else
				sensors[#sensors + 1] = list[i].id .. ": range " .. cell(record.range) ..
					"  field " .. cell(#(record.field or {})) .. " squares" ..
					"  hold " .. cell(record.holdUntil)
			end
		end
	end

	local info = {
		"/dev: " .. #rows .. " of " .. #list ..
			" (cap " .. CeroSecDebug.DEV_MAX .. ", engine cap " .. CeroSecOS.DEV_MAX .. ")",
		"book: " .. cell(CeroSecDebug.mapSize(state)) ..
			" numbers of " .. CeroSecDevices.MAP_MAX,
	}
	for i = 1, #sensors do info[#info + 1] = sensors[i] end
	return { rows = rows, info = info }
end

-- How many device numbers this machine has ever spent.
function CeroSecDebug.mapSize(state)
	if type(state) ~= "table" or type(state.devmap) ~= "table" then return 0 end
	local n = 0
	for _ in pairs(state.devmap) do n = n + 1 end
	return n
end

--
-- 4. Network
--
-- Five sections in one list, each row named by what it is in its first cell, so
-- one scrolling list box holds the whole of the wire.
--
function CeroSecDebug.network(system)
	local rows = {}
	local total = system:getLuaObjectCount() or 0

	-- The segments, which are buildings: every machine's own record says which
	-- building it is on, so the grouping is read off the records and never worked
	-- out from the world.
	local order, members = {}, {}
	for i = 1, total do
		local luaObject = system:getLuaObjectByIndex(i)
		if luaObject ~= nil then
			local key = CeroSecNet.keyOf(luaObject)
			if key ~= nil then
				if members[key] == nil then
					members[key] = {}
					order[#order + 1] = key
				end
				local list = members[key]
				list[#list + 1] = luaObject
			end
		end
	end
	table.sort(order)
	for i = 1, #order do
		if #rows >= CeroSecDebug.NET_MAX then break end
		local key = order[i]
		local list = members[key]
		local on = 0
		local names = ""
		for k = 1, #list do
			if list[k].on then on = on + 1 end
			local addr = CeroSecOS.address(list[k].os)
			if addr ~= nil then
				names = (names == "") and addr or (names .. " " .. addr)
			end
		end
		rows[#rows + 1] = row({ "eth", key, #list .. " on this wire",
			on .. " switched on", names })
	end

	-- The telephone: one line per building, and whether it is in use. Both
	-- answers through the functions that own them, because "busy" is derived from
	-- the ptys and must never be counted here (CeroSecNet.lineBusy says why).
	local seen = {}
	for i = 1, #order do
		if #rows >= CeroSecDebug.NET_MAX * 2 then break end
		local list = members[order[i]]
		local tel = CeroSecNet.lineOf(list[1])
		if tel ~= nil and not seen[tel] then
			seen[tel] = true
			rows[#rows + 1] = row({ "tel", tel, order[i],
				CeroSecNet.lineBusy(system, order[i]) and "busy" or "free", "" })
		end
	end
	rows[#rows + 1] = row({ "tel", "exchange",
		CeroSecNet.phoneService() and "service on" or "service off",
		CeroSecNet.gridAlive() and "grid alive" or "grid dead",
		CeroSecNet.exchangeAlive() and "exchange alive" or "exchange dead" })

	-- The radio: what each machine calls itself and what its set is doing. The
	-- set is a thing in the WORLD, so a machine whose chunk is away has none to
	-- report and says so rather than reporting a stale one.
	for i = 1, total do
		local luaObject = system:getLuaObjectByIndex(i)
		if luaObject ~= nil then
			local call = CeroSecOS.callsignOf(luaObject.os)
			if call ~= nil then
				local set = CeroSecRadio.tncOf(luaObject)
				if set == nil then
					rows[#rows + 1] = row({ "radio", call,
						pos(luaObject.x, luaObject.y, luaObject.z), "no set in reach", "" })
				else
					rows[#rows + 1] = row({ "radio", call,
						pos(luaObject.x, luaObject.y, luaObject.z),
						CeroSecOS.radioStateText(set.channel, set.on, set.powered),
						set.kind .. " range " .. cell(set.range) })
				end
			end
		end
	end

	-- The sessions that are up, everywhere. A pty is where a session IS, so this
	-- is the whole truth about who is connected to what.
	local nowMs = getTimestampMs()
	for i = 1, total do
		local luaObject = system:getLuaObjectByIndex(i)
		if luaObject ~= nil then
			local ptys = CeroSecOS.ptyList(luaObject.ptys)
			for k = 1, #ptys do
				local pty = ptys[k]
				local kind = "eth"
				if type(pty.phone) == "table" then kind = "tel" end
				if type(pty.radio) == "table" then kind = "radio" end
				local age = "-"
				local screen = pty.console
				if type(screen) == "table" and type(screen.loginAt) == "number" then
					age = tostring(math.floor((nowMs - screen.loginAt) / 1000)) .. "s"
				end
				rows[#rows + 1] = row({ "pty", pty.line,
					cell(pty.fromHost) .. " -> " .. pos(luaObject.x, luaObject.y, luaObject.z),
					kind .. (pty.noTty and " detached" or "") ..
						" hops " .. cell(pty.hops),
					"user " .. cell(type(screen) == "table" and screen.user or nil) ..
						"  age " .. age })
			end
		end
	end

	-- And the wire's own log, newest last so it reads down the way it happened.
	local events = CeroSecNet.events
	local from = #events - CeroSecDebug.NET_MAX + 1
	if from < 1 then from = 1 end
	for i = from, #events do
		local event = events[i]
		rows[#rows + 1] = row({ "evt", event.cmd, event.from, event.to, event.what })
	end

	return {
		rows = rows,
		info = {
			"segments " .. #order .. "   events " .. #events ..
				" of " .. CeroSecNet.EVENT_MAX,
		},
	}
end

--
-- 5. Scheduler
--

function CeroSecDebug.scheduler(system)
	local rows = {}
	local machines = CeroSecJobs.machines or {}
	for i = 1, #machines do
		local luaObject = machines[i]
		local book = luaObject ~= nil and luaObject.jobs or nil
		if type(book) == "table" and type(book.list) == "table" then
			for k = 1, #book.list do
				if #rows >= CeroSecDebug.JOB_MAX then break end
				local job = book.list[k]
				local cpu = "-"
				if type(job.cpuSince) == "number" then
					cpu = tostring(math.floor((getTimestampMs() - job.cpuSince) / 1000)) .. "s"
				end
				rows[#rows + 1] = row({
					pos(luaObject.x, luaObject.y, luaObject.z),
					job.id, job.n, job.name,
					-- The word the engine prints for it, which is not always the
					-- field: a job waiting on another machine reads "remote", and
					-- `jobs` shows the same word for the same job.
					CeroSecOS.jobWord(job),
					job.steps, cpu, job.debt or 0,
					job.bg and "bg" or (job.interactive and "prompt" or "fg"),
					job.pty or "console",
					job.mailTo ~= nil and "cron" or "",
				}, luaObject.x, luaObject.y, luaObject.z)
			end
		end
	end

	-- The pending crontab lines of the selected machine are not here: a crontab is
	-- one machine's file, and the cron section below is asked of the whole county
	-- the way the scheduler is.
	local info = {
		"machines with jobs " .. #machines .. "   jobs listed " .. #rows ..
			" (cap " .. CeroSecDebug.JOB_MAX .. ")",
		"budget per tick " .. CeroSec.STEP_BUDGET_PER_TICK ..
			"   per machine " .. CeroSec.STEP_BUDGET_PER_MACHINE ..
			"   pass every " .. CeroSec.JOB_PASS_MS .. "ms",
		"output per second " .. CeroSec.JOB_OUT_PER_SEC ..
			"   phone " .. CeroSec.PHONE_LINES_PER_S ..
			"   radio " .. CeroSec.RADIO_LINES_PER_S ..
			"   cpu limit " .. CeroSec.JOB_CPU_LIMIT_S .. "s",
		"cursor " .. tostring(CeroSecJobs.cursor) ..
			"   last pass " .. tostring(CeroSecJobs.lastMs) ..
			"   now " .. tostring(getTimestampMs()),
	}
	return { rows = rows, info = info }
end

-- The selected machine's crontab, as cron itself reads it: the entries
-- CeroSecOS.parseCrontab makes of the file and whether each is due at this very
-- minute, through CeroSecOS.cronDue.
--
-- Deliberately NOT "next run": nothing in the engine works one out, so a column
-- of them would be a rule this file had invented -- and the day the day-of-week
-- rule moved, this window would be the one thing that disagreed with cron.
function CeroSecDebug.cron(system, luaObject)
	local out = {}
	if luaObject == nil then return out end
	local state = luaObject:osState()
	if state == nil then return out end
	local now = CeroSecOS.clockOf(system:clockEnv())
	local parts = nil
	if now ~= nil then parts = CeroSecOS.dateParts(now) end

	local dir = CeroSecOS.systemNode(state, CeroSecOS.CRON_PATH)
	if type(dir) ~= "table" or dir.type ~= "dir" then return out end
	local names = CeroSecOS.childNames(dir)
	for i = 1, #names do
		local node = dir.children[names[i]]
		if type(node) == "table" and node.type == "file" then
			local entries, errors = CeroSecOS.parseCrontab(node.data or "")
			for k = 1, #entries do
				if #out >= CeroSecDebug.NET_MAX then return out end
				local when = "?"
				if entries[k].reboot then
					when = "@reboot"
				elseif parts ~= nil then
					when = CeroSecOS.cronDue(entries[k], parts) and "DUE NOW" or "waiting"
				end
				out[#out + 1] = "cron " .. names[i] .. " line " .. cell(entries[k].line) ..
					": " .. when .. "  " .. cell(entries[k].cmd)
			end
			for k = 1, #errors do
				if #out >= CeroSecDebug.NET_MAX then return out end
				out[#out + 1] = "cron " .. names[i] .. " line " ..
					cell(errors[k].line) .. ": BAD (" .. cell(errors[k].reason) .. ")"
			end
		end
	end
	return out
end

--
-- The one door
--

-- The snapshot for one tab, with the selected machine where a tab needs one.
-- nil for a tab nobody asked for, which is what an unknown word from a client
-- gets.
--
-- Every snapshot leaves here carrying what the selected machine can be asked to do
-- (CeroSecDebug.selection), whichever tab it is for: the buttons under the list are
-- the same on every tab, so the answer that greys them has to be on every answer.
function CeroSecDebug.snapshotOf(system, tab, luaObject)
	local snap = nil
	if tab == "machines" then
		snap = CeroSecDebug.machines(system)
		local detail = CeroSecDebug.machineDetail(system, luaObject)
		for i = 1, #detail do snap.info[#snap.info + 1] = detail[i] end
	elseif tab == "files" then
		snap = CeroSecDebug.files(system, luaObject)
	elseif tab == "devices" then
		snap = CeroSecDebug.devices(system, luaObject)
	elseif tab == "network" then
		snap = CeroSecDebug.network(system)
	elseif tab == "scheduler" then
		snap = CeroSecDebug.scheduler(system)
		local cron = CeroSecDebug.cron(system, luaObject)
		for i = 1, #cron do snap.info[#snap.info + 1] = cron[i] end
	end
	if snap == nil then return nil end
	return CeroSecDebug.selection(snap, luaObject)
end
