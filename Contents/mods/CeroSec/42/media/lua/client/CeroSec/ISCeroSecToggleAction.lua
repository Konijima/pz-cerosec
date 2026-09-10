require "TimedActions/ISBaseTimedAction"
require "CeroSec/CeroSecDefs"

ISCeroSecToggleAction = ISBaseTimedAction:derive("ISCeroSecToggleAction")

function ISCeroSecToggleAction:isValid()
	return self.object ~= nil
		and self.object:getSquare() ~= nil
		and CeroSec.isComputerSprite(self.object:getSpriteName())
end

function ISCeroSecToggleAction:update()
end

function ISCeroSecToggleAction:start()
	self.character:faceThisObject(self.object)
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

function ISCeroSecToggleAction:new(character, object)
	local o = ISBaseTimedAction.new(self, character)
	o.object = object
	o.stopOnWalk = true
	o.stopOnRun = true
	o.maxTime = o:getDuration()
	o.useProgressBar = false
	return o
end
