require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecMenu"
require "CeroSec/CeroSecModules"
require "CeroSec/CeroSecModuleMenu"
require "CeroSec/ISCeroSecLinkAction"

--
-- The right-click menu on a fixture, second submenu: the cable
--
-- "Link to computer", with a line per machine a cable could reach from this
-- fixture -- the hostname, how far it is and what the run costs:
--
--   ksp-front-01, 12 tiles, 12 wire
--   ksp-front-01, 3 tiles, 7 wire        (a machine one floor up)
--
-- and, under them, a line per cable already run: "Unlink from ksp-front-01",
-- which gives the wire back.
--
-- A listener of its own on Events.OnFillWorldObjectContextMenu, beside the
-- module menu's and for the same reason: it is about the fixture under the
-- cursor and not about a computer. It shares that file's helpers -- which
-- fixture the click landed on, the walk to it, and the parent named after the
-- fixture (CeroSecModuleMenu.fixtureParent) -- because they are the same
-- question about the same object. "Link to computer" nests inside that shared
-- parent rather than sitting on its own at the top of the menu.
--
-- THE MENU SHOWS THE HOSTNAME AND THE CABLE IS WRITTEN AGAINST THE SQUARE. That
-- is the whole of the naming rule: a hostname is what a survivor knows his
-- machines by and is a thing he can change with one line in /etc/hostname, so
-- what travels and what is stored is where the machine STANDS (CeroSecModules.
-- LINK_KEY, and Commands.linkmodule). A machine renamed in the morning is the
-- same machine in the afternoon and keeps every cable run to it.
--
-- WHERE THE HOSTNAME COMES FROM, given that the client is not told the OS state:
-- the server mirrors the whole state into the IsoObject's own modData so that
-- vanilla's pickup carries a machine's filesystem with it (SCeroSecObject:
-- toModData, published by publishOS), and /etc/hostname is read out of that
-- mirror exactly as the server reads it out of the state -- one function, shared
-- (CeroSecOS.hostname). A machine whose mirror has not arrived is named the way
-- a machine with no /etc/hostname is named anyway: ksp- and its square
-- (CeroSec.hostnameFor). No new sync key, because a hostname on a menu is not
-- worth a packet per machine per right-click.
--
-- ON OR OFF, both. A cable is run to a terminal block and not to a login: a
-- survivor who had to boot the machine first to wire his porch light would be
-- wiring it in the dark. The server does not ask either (SCeroSecSystem:linkJob).
--
-- What is GREYED and what is not there at all
--
-- NOT THERE AT ALL: a machine further away than a cable goes, and a fixture with
-- no hardware on it -- which is the one refusal this menu hides, because a
-- survivor with nothing screwed to the door is a survivor who has not got to
-- this feature yet and the module submenu above is already telling him so.
--
-- EVERYTHING ELSE IS A LINE, greyed, with the reason under the description:
-- somebody else's safehouse, the fixture full, the machine full, not enough
-- Electricity, no screwdriver, and -- the one a survivor actually meets -- not
-- enough wire, which says how much (Tooltip_CeroSec_LinkWire, "needs 14
-- electric wire"). A line that is not there is a feature he cannot find; a line
-- that is greyed with a number is a shopping list.
--
-- Every one of them is asked again on the server, so what this decides is what a
-- player SEES and never what he may do.
--

CeroSecLinkMenu = {}

-- The OS state the server mirrored into this machine's IsoObject, or nil. Read
-- for two things only -- the hostname, and how many cables the machine already
-- has -- and never written: the mirror is a copy and the machine's own table is
-- the truth (SCeroSecObject:toModData).
function CeroSecLinkMenu.mirrorOf(luaObject)
	if type(luaObject) ~= "table" then return nil end
	if type(luaObject.getIsoObject) ~= "function" then return nil end
	local isoObject = luaObject:getIsoObject()
	if isoObject == nil or not isoObject:hasModData() then return nil end
	local data = isoObject:getModData()
	if data == nil then return nil end
	local movable = data.movableData
	if type(movable) ~= "table" then return nil end
	local mine = movable[CeroSec.MOVABLE_DATA_KEY]
	if type(mine) ~= "table" or type(mine.os) ~= "table" then return nil end
	return mine.os
end

-- What a survivor calls that machine. /etc/hostname out of the mirror when there
-- is one, and otherwise the name a machine with no /etc/hostname wears anyway --
-- which is the same pair the server answers (SCeroSecSystem:hostnameOf).
function CeroSecLinkMenu.hostOf(luaObject)
	local state = CeroSecLinkMenu.mirrorOf(luaObject)
	if state ~= nil then return CeroSecOS.hostname(state) end
	return CeroSec.hostnameFor(luaObject.x, luaObject.y)
end

-- Every machine a cable from this fixture could reach, nearest first, as rows of
-- { x, y, z, host, tiles, wire, full }. `full` is the machine's own end of the
-- cap and is the one refusal the fixture cannot see (CeroSecOS.addLink).
--
-- The machines are the client's own list of them -- the same global objects the
-- server keeps, announced as their chunks come in -- so a machine whose chunk is
-- away is not offered. That is the rule /dev has always run on read from the
-- other end: a cable to a machine nobody has been near is a cable to a machine
-- the discovery could not visit either.
-- The live IsoObject a mirrored computer stands for, or nil when its chunk is
-- away -- the same call mirrorOf itself makes before it ever reaches modData,
-- guarded the same way, so a machine nobody is near never gets an object handed
-- to the highlight below.
function CeroSecLinkMenu.isoOf(luaObject)
	if type(luaObject) ~= "table" or type(luaObject.getIsoObject) ~= "function" then
		return nil
	end
	return luaObject:getIsoObject()
end

function CeroSecLinkMenu.machines(object)
	local out = {}
	local square = object ~= nil and object:getSquare() or nil
	if square == nil then return out end
	local system = CCeroSecSystem ~= nil and CCeroSecSystem.instance or nil
	if system == nil then return out end
	local total = system:getLuaObjectCount()
	if type(total) ~= "number" then return out end

	local fx, fy, fz = square:getX(), square:getY(), square:getZ()
	for i = 1, total do
		local luaObject = system:getLuaObjectByIndex(i)
		if type(luaObject) == "table" and type(luaObject.x) == "number" then
			local wire = CeroSecModules.linkWire(fx, fy, fz,
				luaObject.x, luaObject.y, luaObject.z)
			-- Out of range is not a line. It is the one thing about a cable a
			-- survivor cannot do anything about from where he is standing, and a
			-- county's worth of machines he cannot reach is a menu he cannot read.
			if wire <= CeroSecModules.LINK_RANGE then
				local state = CeroSecLinkMenu.mirrorOf(luaObject)
				local book = CeroSecOS.linkSquares(state)
				out[#out + 1] = {
					x = luaObject.x, y = luaObject.y, z = luaObject.z,
					host = CeroSecLinkMenu.hostOf(luaObject),
					tiles = CeroSecModules.linkTiles(fx, fy, luaObject.x, luaObject.y),
					wire = wire,
					full = CeroSecOS.linkAt(book, fx, fy, fz) == nil
						and #book >= CeroSecOS.LINKS_PER_MACHINE,
					iso = CeroSecLinkMenu.isoOf(luaObject),
				}
			end
		end
	end

	-- Nearest first, and the hostname breaks a tie: two machines the same distance
	-- away must not swap places between two right-clicks, which is what a walk of a
	-- hash table would do to them.
	table.sort(out, function(a, b)
		if a.wire ~= b.wire then return a.wire < b.wire end
		if a.host ~= b.host then return a.host < b.host end
		if a.x ~= b.x then return a.x < b.x end
		if a.y ~= b.y then return a.y < b.y end
		return a.z < b.z
	end)
	return out
end

-- A reason word from CeroSecModules.linkRefusal or unlinkRefusal, as the key of
-- the sentence a player reads. DERIVED from the word, for the reason the module
-- menu's is: the words are decided in the shared rule and a table here would be a
-- second list to keep in step.
function CeroSecLinkMenu.tooltipFor(why)
	return "Tooltip_CeroSec_Link" ..
		string.upper(string.sub(why, 1, 1)) .. string.sub(why, 2)
end

-- The number a refusal's own sentence has in it, which is a CAP and never a word
-- in a translation: "a cable runs 30 tiles" and "already answers 4 computers" are
-- CeroSecModules.LINK_RANGE and LINKS_MAX, so the day one of them moves the menu
-- moves with it. A word with no number in its line gets 0 and prints a sentence
-- that does not ask for one.
function CeroSecLinkMenu.numberFor(why)
	if why == "far" then return CeroSecModules.LINK_RANGE end
	if why == "links" then return CeroSecModules.LINKS_MAX end
	return 0
end

-- Why he cannot run THIS cable right now, as a tooltip key and the number that
-- goes in it, or nil when he can. Cheapest and most damning first, the order
-- every menu in this mod greys in: what is wrong with the fixture and the place,
-- then what is wrong with the MACHINE, then what is wrong with him.
function CeroSecLinkMenu.refusal(object, playerObj, row)
	local stop = CeroSecModules.linkRefusal(object, row.x, row.y, row.z, playerObj)
	if stop ~= nil then
		return CeroSecLinkMenu.tooltipFor(stop), CeroSecLinkMenu.numberFor(stop)
	end
	if row.full then return "Tooltip_CeroSec_LinkFull", CeroSecOS.LINKS_PER_MACHINE end

	local want = CeroSecModules.linkSkill(object)
	if playerObj:getPerkLevel(Perks.Electricity) < want then
		return "Tooltip_CeroSec_NeedSkill", want
	end
	local inv = playerObj:getInventory()
	if inv == nil or not inv:getFirstTypeRecurse(CeroSecModules.TOOL) then
		return "Tooltip_CeroSec_NeedScrewdriver", 0
	end
	-- And the reel. Last, and with the number in it: this is the one refusal on
	-- this menu a survivor meets every time he tries something ambitious, and the
	-- only useful thing to tell him is how much cable to go and find.
	if CeroSecModules.wireCount(inv) < row.wire then
		return "Tooltip_CeroSec_LinkWire", row.wire
	end
	return nil
end

-- The same for cutting one, which asks less: whose house it is, whether there is
-- a cable there at all, and the tool.
function CeroSecLinkMenu.unlinkRefusal(object, playerObj, row)
	local stop = CeroSecModules.unlinkRefusal(object, row.x, row.y, row.z, playerObj)
	if stop ~= nil then
		return CeroSecLinkMenu.tooltipFor(stop), CeroSecLinkMenu.numberFor(stop)
	end
	local want = CeroSecModules.linkSkill(object)
	if playerObj:getPerkLevel(Perks.Electricity) < want then
		return "Tooltip_CeroSec_NeedSkill", want
	end
	local inv = playerObj:getInventory()
	if inv == nil or not inv:getFirstTypeRecurse(CeroSecModules.TOOL) then
		return "Tooltip_CeroSec_NeedScrewdriver", 0
	end
	return nil
end

function CeroSecLinkMenu.onLink(worldobjects, object, playerObj, row)
	if CeroSecModuleMenu.walkTo(playerObj, object) then
		ISTimedActionQueue.add(ISCeroSecLinkAction:new(playerObj, object,
			row.x, row.y, row.z, true, row.wire))
	end
end

function CeroSecLinkMenu.onUnlink(worldobjects, object, playerObj, row)
	if CeroSecModuleMenu.walkTo(playerObj, object) then
		ISTimedActionQueue.add(ISCeroSecLinkAction:new(playerObj, object,
			row.x, row.y, row.z, false, row.wire))
	end
end

-- The tooltip an entry gets: what the cable is, and the reason under it when
-- there is one. CeroSecMenu.tooltip is what greys it and what puts the reason on
-- its own line, in red, the way vanilla writes a refusal.
local function describe(option, key, desc, number)
	CeroSecMenu.tooltip(option, desc, key and getText(key, number) or nil)
end

function CeroSecLinkMenu.OnFillWorldObjectContextMenu(player, context, worldobjects, test)
	if test and ISWorldObjectContextMenu.Test then return true end
	-- The same gate the module menu wears: with the hardware option off every
	-- machine reaches every door in its building already, nothing is ever fitted,
	-- and a cable would be a gesture with no effect.
	if not CeroSecModules.required() then return end

	local playerObj = getSpecificPlayer(player)
	if not playerObj or playerObj:getVehicle() then return end

	local object = CeroSecModuleMenu.findFixture(worldobjects)
	if not object then return end
	-- Nothing screwed to it is no submenu at all: the cable is what carries a
	-- MODULE's device to a machine, and a survivor with a bare door has not got to
	-- this feature yet (CeroSecModules.anyFitted, the first thing linkRefusal asks).
	if not CeroSecModules.anyFitted(object) then return end

	local rows = CeroSecLinkMenu.machines(object)
	local links = CeroSecModules.linksOn(object)
	if #rows == 0 and #links == 0 then return end

	-- The fixture's own parent, shared with the module menu (CeroSecModuleMenu.
	-- fixtureParent): "Link to computer" nests inside it rather than sitting at
	-- the top of the menu on its own, so a survivor reads one entry named after
	-- the door and not two unnamed ones.
	local fixtureSub = CeroSecModuleMenu.fixtureParent(context, object)
	local parent = fixtureSub:addOption(getText("ContextMenu_CeroSec_Link"))
	-- getNew's argument is the PARENT MENU, not the root: vanilla hangs a third
	-- level off the second one the same way (ISWorldObjectContextMenu.lua:1216
	-- getNew(lightSwitchSubmenu), ISInventoryPaneContextMenu.lua:1590
	-- getNew(subMenuPatch)). It is the line that sets `parent`
	-- (ISContextMenu.lua:1244), and `parent` is the chain closeAll walks up to put
	-- every ancestor away after a click (:278-292). Handed the root instead, the
	-- walk skipped this fixture's own menu, which stayed visible -- and a visible
	-- menu with the mouse on a submenu option re-shows that submenu every frame
	-- (:441-452), so the third level came straight back too.
	local sub = ISContextMenu:getNew(fixtureSub)
	fixtureSub:addSubMenu(parent, sub)

	for i = 1, #rows do
		local row = rows[i]
		local option = sub:addOption(
			getText("ContextMenu_CeroSec_LinkTo", row.host, row.tiles, row.wire),
			worldobjects, CeroSecLinkMenu.onLink, object, playerObj, row)
		local key, number = CeroSecLinkMenu.refusal(object, playerObj, row)
		describe(option, key,
			getText("Tooltip_CeroSec_LinkDesc", row.wire, row.host), number)
		-- The COMPUTER lights up here, not the fixture: this line names a
		-- machine and the survivor is choosing which one to wire. Nothing at
		-- all when its chunk is away (row.iso is nil then).
		if row.iso then CeroSecModuleMenu.highlightOn(option, row.iso) end
	end

	-- And the cables that are already run, under them. Off the FIXTURE, which is
	-- the end that carries them, so a cable to a machine whose chunk is away is
	-- still here to be cut -- and the wire it gives back is the wire that was paid,
	-- never the price worked out again (Commands.unlinkmodule).
	local square = object:getSquare()
	for i = 1, #links do
		local at = links[i]
		local row = { x = at.x, y = at.y, z = at.z, wire = at.wire }
		local luaObject = nil
		local system = CCeroSecSystem ~= nil and CCeroSecSystem.instance or nil
		if system ~= nil then luaObject = system:getLuaObjectAt(at.x, at.y, at.z) end
		local option, tooltipDesc
		if luaObject ~= nil then
			-- A machine still stands there: the name it answers to today, same
			-- as the "Link to computer" rows above.
			local host = CeroSecLinkMenu.hostOf(luaObject)
			option = sub:addOption(getText("ContextMenu_CeroSec_Unlink", host),
				worldobjects, CeroSecLinkMenu.onUnlink, object, playerObj, row)
			tooltipDesc = getText("Tooltip_CeroSec_UnlinkDesc", at.wire, host)
		else
			-- No machine on that square: the link is indexed by where a
			-- computer STOOD (CeroSecModules.LINK_KEY), so a survivor never
			-- reads a hostname CeroSec.hostnameFor made up for an empty tile.
			local tiles = CeroSecModules.linkTiles(square:getX(), square:getY(),
				at.x, at.y)
			option = sub:addOption(getText("ContextMenu_CeroSec_UnlinkLoose"),
				worldobjects, CeroSecLinkMenu.onUnlink, object, playerObj, row)
			tooltipDesc = getText("Tooltip_CeroSec_UnlinkLooseDesc", tiles, at.wire)
		end
		local key, number = CeroSecLinkMenu.unlinkRefusal(object, playerObj, row)
		describe(option, key, tooltipDesc, number)
		local iso = CeroSecLinkMenu.isoOf(luaObject)
		if iso then CeroSecModuleMenu.highlightOn(option, iso) end
	end
end

Events.OnFillWorldObjectContextMenu.Add(CeroSecLinkMenu.OnFillWorldObjectContextMenu)
