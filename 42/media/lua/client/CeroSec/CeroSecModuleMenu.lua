require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecMenu"
require "CeroSec/CeroSecModules"
require "CeroSec/ISCeroSecModuleAction"

--
-- The right-click menu on a door, a window or a light switch
--
-- One submenu, "CeroSec hardware", with a line per module that could go on the
-- thing under the cursor: Install it, or Remove the one that is there. It is a
-- listener of its own on Events.OnFillWorldObjectContextMenu and not a branch of
-- the computer's menu (CeroSecContextMenu), because it is about a DIFFERENT
-- object: the computer's menu returns at once when there is no computer under
-- the cursor, and a door is never a computer.
--
-- Vanilla fires that event for exactly this -- "use the event (as you would
-- 'OnTick' etc) to add items to context menu without mod conflicts",
-- ISWorldObjectContextMenu.lua:213 -- and several of its own files listen to it
-- the same way (ISHutchMenu, ISVehicleMenu).
--
-- Nothing at all when the sandbox option is off: with CeroSec.HardwareRequired
-- false, a machine reaches every door in the building already and a module fitted
-- to one would buy nothing. A menu that offers a gesture with no effect is worse
-- than no menu.
--
-- What is GREYED and what is not there at all
--
-- A module the survivor is not carrying is not an entry: he has no business
-- reading about hardware he does not own, which is the same rule the floppy menu
-- runs on. Everything else -- the wrong fixture, a door with no lock worth
-- wiring, a leaf of a garage door, not enough Electricity, no screwdriver -- is
-- an entry with the reason on it, because each of those is a thing he can go and
-- fix.
--
-- Every one of them is asked again on the server (SCeroSecSystem's
-- Commands.installmodule), so what this decides is what a player SEES and never
-- what he may do.
--

CeroSecModuleMenu = {}

-- The first fixture the click landed on, or nil. Two passes like the computer's
-- menu: what the picker hands over is everything under the cursor, and a door and
-- the wall beside it come back together.
function CeroSecModuleMenu.findFixture(worldobjects)
	for _, object in ipairs(worldobjects) do
		if CeroSecModules.isFittable(object) then return object end
	end
	-- The square's own list, for a click that named the floor or a wall: a door
	-- is drawn over the square behind it and the picker does not always name it.
	local done = {}
	for _, object in ipairs(worldobjects) do
		local square = object:getSquare()
		if square and not done[square] then
			done[square] = true
			local objects = square:getObjects()
			for i = 0, objects:size() - 1 do
				local candidate = objects:get(i)
				if CeroSecModules.isFittable(candidate) then return candidate end
			end
		end
	end
	return nil
end

-- The walk vanilla makes to the same kinds of thing: a door or a window is
-- reached through the tile finder that knows which side of a doorway a survivor
-- has to stand on (luautils.walkAdjWindowOrDoor, ISWorldObjectContextMenu.lua's
-- onOpenCloseDoor and onUnbarricade), and anything else through the plain
-- adjacent walk (luautils.walkAdj, onFixGenerator).
function CeroSecModuleMenu.walkTo(playerObj, object)
	local square = object:getSquare()
	if square == nil then return false end
	if CeroSecModules.isDoor(object) or CeroSecModules.isWindow(object) then
		return luautils.walkAdjWindowOrDoor(playerObj, square, object)
	end
	return luautils.walkAdj(playerObj, square)
end

function CeroSecModuleMenu.onInstall(worldobjects, object, playerObj, module)
	if CeroSecModuleMenu.walkTo(playerObj, object) then
		ISTimedActionQueue.add(ISCeroSecModuleAction:new(playerObj, object, module, true))
	end
end

function CeroSecModuleMenu.onRemove(worldobjects, object, playerObj, module)
	if CeroSecModuleMenu.walkTo(playerObj, object) then
		ISTimedActionQueue.add(ISCeroSecModuleAction:new(playerObj, object, module, false))
	end
end

-- A reason word from CeroSecModules.fittingRefusal, as the key of the sentence a
-- player reads. DERIVED from the word and not looked up in a table beside it:
-- the words are decided over there, and a list here would be a second list to
-- keep in step -- which is how a reason nobody added a row for comes out on the
-- menu as its own key printed at a survivor.
function CeroSecModuleMenu.tooltipFor(why)
	return "Tooltip_CeroSec_Module" ..
		string.upper(string.sub(why, 1, 1)) .. string.sub(why, 2)
end

-- Why this survivor cannot do this job to this thing right now, as a tooltip
-- key, or nil when he can. The order is cheapest first and most damning first,
-- which is the same order the computer's own menu greys its entries in: what is
-- wrong with the FIXTURE beats what is wrong with him.
function CeroSecModuleMenu.refusal(object, playerObj, module)
	local fits, why = CeroSecModules.fitsOn(object, module.id)
	if not fits then
		if why == "nolock" then return "Tooltip_CeroSec_NoLock" end
		if why == "manydoors" then return "Tooltip_CeroSec_ManyDoors" end
		return "Tooltip_CeroSec_NoFixture"
	end
	-- Whose house it is, where he is standing and what the fixture is doing --
	-- one function, shared with the server, and the reason word IS the key
	-- (CeroSecModules.fittingRefusal). Above the skill and the tool for the
	-- reason the shape of the fixture is: the trade is the last thing wrong with
	-- a job that could not be done in that place at that moment anyway.
	local stop = CeroSecModules.fittingRefusal(object, module.id, playerObj)
	if stop ~= nil then return CeroSecModuleMenu.tooltipFor(stop) end
	if playerObj:getPerkLevel(Perks.Electricity) < module.skill then
		return "Tooltip_CeroSec_NeedSkill"
	end
	local inv = playerObj:getInventory()
	if inv == nil or not inv:getFirstTypeRecurse(CeroSecModules.TOOL) then
		return "Tooltip_CeroSec_NeedScrewdriver"
	end
	return nil
end

local function grey(option, key, module)
	if not key then return end
	option.notAvailable = true
	option.toolTip = ISWorldObjectContextMenu.addToolTip()
	option.toolTip:setVisible(false)
	-- The skill line is the only one with a number in it, and the number is the
	-- module's own rather than a word in the translation: four modules, four
	-- levels, one line of English.
	option.toolTip.description = getText(key, module.skill)
end

function CeroSecModuleMenu.OnFillWorldObjectContextMenu(player, context, worldobjects, test)
	if test and ISWorldObjectContextMenu.Test then return true end
	if not CeroSecModules.required() then return end

	local playerObj = getSpecificPlayer(player)
	if not playerObj or playerObj:getVehicle() then return end

	local object = CeroSecModuleMenu.findFixture(worldobjects)
	if not object then return end
	local fitted = CeroSecModules.installedOn(object)

	-- What is worth an entry: a module already on this thing (it can come off) or
	-- one in his bag (it can go on). Counted before anything is added, so a
	-- submenu is never built with nothing under it.
	local rows = {}
	local inv = playerObj:getInventory()
	for i = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[i]
		if fitted[module.id] then
			rows[#rows + 1] = { module = module, install = false }
		elseif inv ~= nil and inv:getFirstTypeRecurse(module.item) ~= nil then
			rows[#rows + 1] = { module = module, install = true }
		end
	end
	if #rows == 0 then return end

	-- getNew, addSubMenu, then fill it: the order every vanilla submenu is built
	-- in (ISWorldObjectContextMenu.lua:1167-1169). The parent goes at the TOP of the
	-- menu, which is where every entry of this mod goes and which is how vanilla's
	-- own top submenus are built too (ISHutchMenu.lua:20-22) -- see CeroSecMenu.
	-- A light switch's own Turn on is the game's and stays where the game puts it;
	-- what a survivor came to the switch with a screwdriver for is this.
	local parent = CeroSecMenu.addTop(context, getText("ContextMenu_CeroSec_Modules"))
	local sub = ISContextMenu:getNew(context)
	context:addSubMenu(parent, sub)

	for i = 1, #rows do
		local row = rows[i]
		local name = getItemNameFromFullType(row.module.item)
		local option
		if row.install then
			option = sub:addOption(getText("ContextMenu_CeroSec_Install", name), worldobjects,
				CeroSecModuleMenu.onInstall, object, playerObj, row.module)
			grey(option, CeroSecModuleMenu.refusal(object, playerObj, row.module), row.module)
		else
			-- Taking one off asks nothing about whether the module FITS -- it is
			-- already there -- and everything about the moment: whose house it
			-- is, where he is standing and what the fixture is doing. A man
			-- unscrewing a strike from a door that swings into him is the same
			-- hand in the same place as a man fitting one, and a module anybody
			-- could take off a door from the pavement is the whole reason this
			-- rung exists.
			option = sub:addOption(getText("ContextMenu_CeroSec_Remove", name), worldobjects,
				CeroSecModuleMenu.onRemove, object, playerObj, row.module)
			local why = nil
			local stop = CeroSecModules.fittingRefusal(object, row.module.id, playerObj)
			if stop ~= nil then
				why = CeroSecModuleMenu.tooltipFor(stop)
			elseif playerObj:getPerkLevel(Perks.Electricity) < row.module.skill then
				why = "Tooltip_CeroSec_NeedSkill"
			elseif inv == nil or not inv:getFirstTypeRecurse(CeroSecModules.TOOL) then
				why = "Tooltip_CeroSec_NeedScrewdriver"
			end
			grey(option, why, row.module)
		end
	end
end

Events.OnFillWorldObjectContextMenu.Add(CeroSecModuleMenu.OnFillWorldObjectContextMenu)
