require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecReach"
require "CeroSec/ISCeroSecToggleAction"

CeroSecContextMenu = {}

local function hasPower(square)
	if not square then return false end
	-- Same test the car battery charger uses (ISWorldObjectContextMenu.lua:460).
	return square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil)
end

-- Walk to the square the screen looks at, then toggle from there. The toggle
-- action checks in its isValid that the player really made it, so a walk that
-- fails or gets interrupted changes nothing.
function CeroSecContextMenu.onToggle(worldobjects, computer, playerObj, height)
	CeroSecReach.walkToFront(playerObj, computer, function()
		ISTimedActionQueue.add(ISCeroSecToggleAction:new(playerObj, computer, height))
	end)
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

	local height = CeroSecReach.height(computer)

	-- The sprite is the truth for the menu label: it is what the player sees.
	local isOn = CeroSec.isOnSprite(computer:getSpriteName())
	local label = isOn and "ContextMenu_CeroSec_TurnOff" or "ContextMenu_CeroSec_TurnOn"
	local option = context:addOption(getText(label), worldobjects,
		CeroSecContextMenu.onToggle, computer, playerObj, height)

	-- One reason at a time, cheapest first: out of reach beats no access beats no
	-- power, because a computer nobody can touch never gets as far as its wiring.
	local reason
	if height == "high" then
		reason = "Tooltip_CeroSec_TooHigh"
	elseif not CeroSecReach.canStandInFront(playerObj, computer) then
		reason = "Tooltip_CeroSec_NoAccess"
	elseif not isOn and not hasPower(computer:getSquare()) then
		reason = "Tooltip_CeroSec_NoPower"
	end

	if reason then
		option.notAvailable = true
		option.toolTip = ISWorldObjectContextMenu.addToolTip()
		option.toolTip:setVisible(false)
		option.toolTip.description = getText(reason)
	end
end

Events.OnFillWorldObjectContextMenu.Add(CeroSecContextMenu.OnFillWorldObjectContextMenu)
