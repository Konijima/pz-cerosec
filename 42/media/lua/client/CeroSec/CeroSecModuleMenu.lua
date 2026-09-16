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
-- ONE LINE IS NOT THERE AT ALL: a module that does not fit this SORT of fixture.
-- A curtain motor has no business on a light switch and never will have, and a
-- survivor right-clicking a door does not want to read six lines telling him
-- what a door is not. That is `fitsOn` answering "fixture", and it is the only
-- answer this menu hides.
--
-- EVERYTHING ELSE IS AN ENTRY, greyed, with the reason under the description:
-- the wrong door for a strike, a leaf of a garage door, the door shut, the oven
-- cooking, somebody else's safehouse, not enough Electricity, no screwdriver --
-- and, since this rung, a module he is not carrying at all. That last one used
-- to be no entry either, and the change is the whole point: a survivor cannot go
-- and find a box he has never been told exists. So the line is there, it says
-- what the module does, and it says which of the two things he needs -- one in
-- his bag, or the book that says how to make one.
--
-- AND EVERY ENTRY CARRIES ITS DESCRIPTION, greyed or not: what the box buys,
-- which device it gives and the level it wants
-- (Tooltip_CeroSec_ModuleDesc_<id>). The reason, when there is one, goes on the
-- line UNDER it -- a refusal with no idea what it is refusing is a line a player
-- reads twice.
--
-- If nothing is left after all that, there is no submenu and no parent entry
-- either: a right-click on a fridge says nothing about this mod at all.
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
-- wrong with the FIXTURE beats what is wrong with the moment, and both beat what
-- is wrong with HIM.
--
-- `install` false is a module coming off, which asks nothing about whether it
-- fits -- it is already on -- and nothing about his bag.
function CeroSecModuleMenu.refusal(object, playerObj, module, install)
	if install then
		local fits, why = CeroSecModules.fitsOn(object, module.id)
		if not fits then
			if why == "nolock" then return "Tooltip_CeroSec_NoLock" end
			if why == "manydoors" then return "Tooltip_CeroSec_ManyDoors" end
			-- The wrong sort of fixture altogether, which the caller has already
			-- decided not to show. Answered all the same, so this function is
			-- complete on its own and a caller that did show it is not silent.
			return "Tooltip_CeroSec_NoFixture"
		end
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
	if not install then return nil end

	-- And last, the box itself. Two answers and not one, because they send him
	-- to two different places: a survivor who knows the recipe needs to find or
	-- craft one, and a survivor who does not needs the CeroSec Field Wiring
	-- Guide, which is the only thing that teaches all nine.
	--
	-- isRecipeKnown(String) is vanilla's own question and it is ONE call over
	-- three: `ScriptManager.getRecipe(name)`, then -- for a name it does not know
	-- as an old-style Recipe, which is every craftRecipe of ours -- the sandbox
	-- option seeNotLearntRecipe, isKnowAllRecipes(), and finally
	-- getKnownRecipes().contains(name) (javap -c
	-- zombie.characters.IsoGameCharacter.isRecipeKnown(String,boolean), offsets
	-- 0-53). So a server that shows unlearnt recipes, a debug character and a
	-- master electrician who auto-learnt it all answer the same yes the book
	-- does, and none of them is a case written here.
	if inv:getFirstTypeRecurse(module.item) == nil then
		if not playerObj:isRecipeKnown(module.recipe) then
			return "Tooltip_CeroSec_ModuleRecipe"
		end
		return "Tooltip_CeroSec_ModuleItem"
	end
	return nil
end

-- What the box IS, in the survivor's own words: what it buys, which device it
-- gives and the level it wants. Every entry carries it, greyed or not, and the
-- level is the module's own rather than a word in the translation -- nine
-- modules, nine levels, one line of English (the same rule the skill line has
-- always run on).
function CeroSecModuleMenu.describe(module)
	return getText("Tooltip_CeroSec_ModuleDesc_" .. module.id, module.skill)
end

-- The tooltip every entry gets: the description, and the reason under it when
-- there is one. A greyed entry is also marked notAvailable, which is what stops
-- the click.
--
-- The skill line is the only reason with a number in it, and the number is the
-- module's own rather than a word in the translation: nine modules, nine levels,
-- one line of English.
local function describe(option, key, module)
	if type(option) ~= "table" then return end
	option.toolTip = ISWorldObjectContextMenu.addToolTip()
	option.toolTip:setVisible(false)
	local text = CeroSecModuleMenu.describe(module)
	if key then
		option.notAvailable = true
		text = text .. "<br>" .. getText(key, module.skill)
	end
	option.toolTip.description = text
end

function CeroSecModuleMenu.OnFillWorldObjectContextMenu(player, context, worldobjects, test)
	if test and ISWorldObjectContextMenu.Test then return true end
	if not CeroSecModules.required() then return end

	local playerObj = getSpecificPlayer(player)
	if not playerObj or playerObj:getVehicle() then return end

	local object = CeroSecModuleMenu.findFixture(worldobjects)
	if not object then return end
	local fitted = CeroSecModules.installedOn(object)

	-- What is worth an entry: a module already on this thing (it can come off),
	-- or one that could ever go on a fixture of this SORT -- whether he is
	-- carrying it or not, because a box he has never been told about is a box he
	-- will never go and look for.
	--
	-- The one thing left out is the module that does not fit this sort of fixture
	-- at all: `fitsOn` answering "fixture". Its other two answers -- a door no
	-- lock bites on, a leaf of a garage door -- are about THIS door and not about
	-- doors, so they stay and say so.
	--
	-- Counted before anything is added, so a submenu is never built with nothing
	-- under it and a right-click on something this mod has nothing to say about
	-- gets no parent entry either.
	local rows = {}
	for i = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[i]
		if fitted[module.id] then
			rows[#rows + 1] = { module = module, install = false }
		else
			local _, why = CeroSecModules.fitsOn(object, module.id)
			if why ~= "fixture" then
				rows[#rows + 1] = { module = module, install = true }
			end
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
			describe(option,
				CeroSecModuleMenu.refusal(object, playerObj, row.module, true),
				row.module)
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
			describe(option,
				CeroSecModuleMenu.refusal(object, playerObj, row.module, false),
				row.module)
		end
	end
end

Events.OnFillWorldObjectContextMenu.Add(CeroSecModuleMenu.OnFillWorldObjectContextMenu)
