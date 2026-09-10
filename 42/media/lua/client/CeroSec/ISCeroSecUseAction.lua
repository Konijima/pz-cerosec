require "TimedActions/ISBaseTimedAction"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecReach"
require "CeroSec/CeroSecTerminal"

--
-- Sitting down at a computer that is already on. Same shape as the toggle
-- action (ISCeroSecToggleAction): the walk is queued before it, this only says
-- whether the player really made it, turns to the screen in waitToStart, and
-- does its one thing at the end.
--

ISCeroSecUseAction = ISBaseTimedAction:derive("ISCeroSecUseAction")

-- Only what is already true before the action starts. Which way the player
-- looks is not one of those things -- he is still facing the way he walked in.
function ISCeroSecUseAction:isValid()
	if not self.object or not self.object:getSquare() then return false end
	if not CeroSec.isOnSprite(self.object:getSpriteName()) then return false end
	local front = CeroSecReach.frontSquare(self.object)
	return front ~= nil and self.character:getCurrentSquare() == front
end

-- Turn to the screen first and hold the action back until the turn is done
-- (ISAddTakeDispenserBottle.lua:9-11).
function ISCeroSecUseAction:waitToStart()
	self.character:faceThisObject(self.object)
	return self.character:shouldBeTurning()
end

function ISCeroSecUseAction:update()
	self.character:faceThisObject(self.object)
end

function ISCeroSecUseAction:start()
	-- Same three calls the grab action makes (ISGrabItemAction.lua:50-52).
	self:setActionAnim("Loot")
	self:setAnimVariable("LootPosition", self.height == "low" and "Low" or "Mid")
	self:setOverrideHandModels(nil, nil)
end

function ISCeroSecUseAction:stop()
	ISBaseTimedAction.stop(self)
end

function ISCeroSecUseAction:perform()
	CeroSecTerminal.open(self.character, self.object)
	ISBaseTimedAction.perform(self)
end

function ISCeroSecUseAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return 30
end

function ISCeroSecUseAction:new(character, object, height)
	local o = ISBaseTimedAction.new(self, character)
	o.object = object
	o.height = height
	o.stopOnWalk = true
	o.stopOnRun = true
	o.maxTime = o:getDuration()
	o.useProgressBar = false
	return o
end
