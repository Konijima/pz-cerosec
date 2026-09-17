require "ISUI/ISContextMenu"

--
-- Where an option of this mod goes on a right-click menu: FIRST.
--
-- Every entry this mod adds -- the computer's own two, the drive's, the labels on
-- a disk, the volumes of the manual, the hardware submenu on a light switch --
-- goes above vanilla's Grab, Equip, Place and the rest of them. A survivor who
-- right-clicks a computer is right-clicking it to use the computer, and an entry
-- he has to read past four of the game's own to find is an entry he does not find
-- at all.
--
-- WHY A HELPER AND NOT addOptionOnTop AT EVERY CALL. The game's own
-- ISContextMenu:addOptionOnTop puts its option at index 1 (ISContextMenu.lua:914-930:
-- every id shifted up by one, then `self.options[1] = option`), so calling it N
-- times leaves the LAST call at the top and reverses the order they were written
-- in. Our entries have an order of their own -- the primary action, then the
-- drive, then the rest -- and a file that had to be read bottom to top to know
-- what the menu says is a file whose order nobody can check.
--
-- So each option is inserted just BEFORE the first option that is not ours, with
-- the engine's own ISContextMenu:insertOptionBefore (:965-1001): it finds that
-- option by name, shifts the tail down and renumbers every id, and for an option
-- that is already at index 1 it is addOptionOnTop itself (:982-984). An empty menu
-- -- and a menu that is nothing but ours -- falls through to plain addOption
-- (:967-969 does the same), which appends, and appending to the end of our own
-- block is the same place.
--
-- Vanilla does exactly this to put a submenu of its own at the top: ISHutchMenu
-- (client/ISUI/Hutch/ISHutchMenu.lua:20-22) and the foraging menu
-- (client/Foraging/ISSearchManager.lua:1672-1674) both call addOptionOnTop for the
-- parent and then getNew + addSubMenu, which is the shape addDrive, addDevMenu and
-- the hardware menu already build their submenus in. addSubMenu hangs the child off
-- the option itself (`option.subOption = menu.subOptionNums`, :1075-1077) and not
-- off its position, so an option that moves keeps its submenu.
--
-- WHICH OPTION IS "THE FIRST THAT IS NOT OURS" is answered off the options
-- themselves and never off a counter kept beside the menu: a context menu is
-- POOLED and `ISContextMenu:clear()` (:1088-1096) empties `self.options` without
-- touching anything a mod hung on the menu table, so a count of ours stored there
-- would survive into the next right-click. Each option we add is marked instead,
-- and `allocOption` does `table.wipe(option)` before it fills one in (:849-855), so
-- a recycled option cannot come back still wearing our mark.
--
-- TWO LISTENERS SHARE ONE MENU. This module fills a world menu from two files --
-- the computer's (CeroSecContextMenu) and the fixtures' (CeroSecModuleMenu) -- and
-- the inventory menu from two more. Each of them appends to the END of our block
-- rather than to the top of the menu, so whichever order the game fires the
-- listeners in, our entries stay together and in the order each file wrote them.
--
-- THE ONE EXCEPTION IS WRITTEN DOWN, and it is the dev submenu: see the note over
-- CeroSecContextMenu.addDevMenu. It is not part of the machine and it is not a
-- player's entry at all, so it keeps the plain addOption that leaves it last.
--

CeroSecMenu = {}

-- How many options at the top of this menu are already ours. The leading run and
-- not a count of them anywhere in the list: what is being asked is where our block
-- ENDS, and an entry of ours that somebody deliberately left at the bottom (the dev
-- submenu) is not part of it.
function CeroSecMenu.blockEnd(context)
	local options = context ~= nil and context.options or nil
	if type(options) ~= "table" then return 0 end
	local n = 0
	while true do
		local at = options[n + 1]
		if type(at) ~= "table" or at.cerosec ~= true then return n end
		n = n + 1
	end
end

-- addOption's own signature, param1..param10 written out and never "...": any of
-- them may be nil and select("#") is not worth betting on under Kahlua, which is
-- the reason vanilla writes its own pass-throughs out the same way
-- (ISContextMenu:addGetUpOption, :1038-1044).
function CeroSecMenu.addTop(context, name, target, onSelect,
		param1, param2, param3, param4, param5, param6, param7, param8, param9, param10)
	local option
	local anchor = nil
	if type(context.options) == "table" then
		anchor = context.options[CeroSecMenu.blockEnd(context) + 1]
	end
	-- Nothing under our block: appending IS putting it at the end of the block, and
	-- it is what insertOptionBefore would fall back to anyway (:967-969).
	if type(anchor) ~= "table" or type(anchor.name) ~= "string" then
		option = context:addOption(name, target, onSelect, param1, param2, param3,
			param4, param5, param6, param7, param8, param9, param10)
	else
		option = context:insertOptionBefore(anchor.name, name, target, onSelect,
			param1, param2, param3, param4, param5, param6, param7, param8, param9,
			param10)
	end
	-- The mark, which is what the next call of this function reads. Nothing else in
	-- the mod reads it and nothing in the game writes it.
	if type(option) == "table" then option.cerosec = true end
	return option
end

-- The menu icon, loaded once and reused: ISContextMenu draws
-- `option.iconTexture` with drawTextureScaledAspect at
-- `iconSize = itemHgt - 12` (ISUI/ISContextMenu.lua, the option-row branch),
-- the same field vanilla's own inventory menu sets
-- (ISInventoryPaneContextMenu.lua:4652). Fetched lazily, not at require time:
-- getTexture can run before every asset in media/ui is registered, and a
-- module-local cache means one file read for however many entries this
-- right-click adds.
local iconTexture, iconLoaded = nil, false

function CeroSecMenu.setIcon(option)
	if not iconLoaded then
		iconTexture = getTexture("media/ui/cerosec-menu.png")
		iconLoaded = true
	end
	if type(option) ~= "table" or iconTexture == nil then return end
	option.iconTexture = iconTexture
end

-- The tooltip a CeroSec entry wears, and the ONE place an entry of ours is marked
-- unavailable: the description, then the reason it is refused on its own line and
-- in red. Every greyed entry in the mod comes through here -- hardware, cable and
-- computer alike -- so the refusal always reads the same way.
--
-- The separator is the game's markup, not HTML. ISRichTextPanel:processCommand
-- knows LINE, BR, H1, RGB and a handful more, all upper case
-- (ISUI/ISRichTextPanel.lua:16-27), so a lower-case "<br>" is no command at all.
-- Worse, the parser tokenises on SPACES and re-cuts any token holding both '<'
-- and '>' up to the '>' before reading it as a command (:456-481) -- the text
-- that sat in front of the '<' is dropped, and the next chunk resumes at the same
-- x,y. "wire back.<br>Needs" therefore lost the word "back." and glued the rest.
-- " <LINE> <RGB:1,0,0> ", spaces included, is what vanilla writes for exactly
-- this (ISWorldObjectContextMenu.lua:383, ContextMenuCode.lua:95); with no
-- description in front of it, vanilla writes "<RGB:1,0,0> " (:377).
function CeroSecMenu.tooltip(option, desc, reason)
	if type(option) ~= "table" then return end
	if not desc and not reason then return end
	option.toolTip = ISWorldObjectContextMenu.addToolTip()
	option.toolTip:setVisible(false)
	local text = desc
	if reason then
		option.notAvailable = true
		if text then
			text = text .. " <LINE> <RGB:1,0,0> " .. reason
		else
			text = "<RGB:1,0,0> " .. reason
		end
	end
	option.toolTip.description = text
end
