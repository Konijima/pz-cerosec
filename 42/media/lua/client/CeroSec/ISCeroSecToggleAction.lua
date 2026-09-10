require "TimedActions/ISBaseTimedAction"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecReach"

ISCeroSecToggleAction = ISBaseTimedAction:derive("ISCeroSecToggleAction")

-- The engine re-runs isValid every tick, so this is also what stops the toggle
-- when the walk in front of the computer failed or the player wandered off.
function ISCeroSecToggleAction:isValid()
	if not self.object or not self.object:getSquare() then return false end
	if not CeroSec.isComputerSprite(self.object:getSpriteName()) then return false end
	local front = CeroSecReach.frontSquare(self.object)
	if not front or self.character:getCurrentSquare() ~= front then return false end
	return CeroSecReach.isFacing(self.character, self.object)
end

function ISCeroSecToggleAction:update()
end

function ISCeroSecToggleAction:start()
	self.character:faceThisObject(self.object)
	-- Same three calls the grab action makes (ISGrabItemAction.lua:50-52).
	-- LootPosition picks the animation: "Low" is the crouched reach
	-- (AnimSets/player/actions/LootLow.xml), and "Mid" -- the value vanilla uses
	-- for waist-height work (ISFeedingTrough.lua:45) -- has no node of its own,
	-- so it falls through to the plain Loot animation.
	self:setActionAnim("Loot")
	self:setAnimVariable("LootPosition", self.height == "low" and "Low" or "Mid")
	self:setOverrideHandModels(nil, nil)
end

function ISCeroSecToggleAction:stop()
	ISBaseTimedAction.stop(self)
end

function ISCeroSecToggleAction:perform()
	local square = self.object:getSquare()
	CCeroSecSystem.instance:sendCommand(self.character, "toggle",
		{ x = square:getX(), y = square:getY(), z = square:getZ() })
	ISBaseTimedAction.perform(self)
end

function ISCeroSecToggleAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return 30
end

function ISCeroSecToggleAction:new(character, object, height)
	local o = ISBaseTimedAction.new(self, character)
	o.object = object
	o.height = height
	o.stopOnWalk = true
	o.stopOnRun = true
	o.maxTime = o:getDuration()
	o.useProgressBar = false
	return o
end
