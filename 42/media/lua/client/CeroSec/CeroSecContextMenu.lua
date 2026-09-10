require "CeroSec/CeroSecDefs"
require "CeroSec/ISCeroSecToggleAction"

CeroSecContextMenu = {}

local function hasPower(square)
	if not square then return false end
	-- Same test the car battery charger uses (ISWorldObjectContextMenu.lua:460).
	return square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil)
end

function CeroSecContextMenu.onToggle(worldobjects, computer, playerObj)
	if luautils.walkAdj(playerObj, computer:getSquare()) then
		ISTimedActionQueue.add(ISCeroSecToggleAction:new(playerObj, computer))
	end
end

-- The picker hands us what sits under the cursor: on a counter or a desk that
-- is the counter, not the table-top computer on it. Vanilla menus that target
-- one object scan the square of every picked object instead
-- (ISRadioAndTvMenu.lua:16-26, ISBBQMenu.lua:20), so do the same.
function CeroSecContextMenu.findComputer(worldobjects)
	local done = {}
	for _, object in ipairs(worldobjects) do
		local square = object:getSquare()
		if square and not done[square] then
			done[square] = true
			local objects = square:getObjects()
			for i = 0, objects:size() - 1 do
				local candidate = objects:get(i)
				if CeroSec.isComputerSprite(candidate:getSpriteName()) then
					return candidate
				end
			end
		end
	end
	return nil
end

function CeroSecContextMenu.OnFillWorldObjectContextMenu(player, context, worldobjects, test)
	if test and ISWorldObjectContextMenu.Test then return true end

	local playerObj = getSpecificPlayer(player)
	if not playerObj or playerObj:getVehicle() then return end

	local computer = CeroSecContextMenu.findComputer(worldobjects)
	if not computer then return end

	-- The sprite is the truth for the menu label: it is what the player sees.
	if CeroSec.isOnSprite(computer:getSpriteName()) then
		context:addOption(getText("ContextMenu_CeroSec_TurnOff"), worldobjects,
			CeroSecContextMenu.onToggle, computer, playerObj)
	else
		local option = context:addOption(getText("ContextMenu_CeroSec_TurnOn"), worldobjects,
			CeroSecContextMenu.onToggle, computer, playerObj)
		if not hasPower(computer:getSquare()) then
			option.notAvailable = true
			option.toolTip = ISWorldObjectContextMenu.addToolTip()
			option.toolTip:setVisible(false)
			option.toolTip.description = getText("Tooltip_CeroSec_NoPower")
		end
	end
end

Events.OnFillWorldObjectContextMenu.Add(CeroSecContextMenu.OnFillWorldObjectContextMenu)
