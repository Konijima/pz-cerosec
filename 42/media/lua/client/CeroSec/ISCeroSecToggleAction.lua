require "TimedActions/ISBaseTimedAction"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecReach"

ISCeroSecToggleAction = ISBaseTimedAction:derive("ISCeroSecToggleAction")

-- The engine re-runs isValid every tick, so this is also what stops the toggle
-- when the walk in front of the computer failed or the player wandered off.
-- It must only ask what can already be true before the action runs: valid() is
-- evaluated *before* waitToStart and start (IsoGameCharacter.StartAction:
-- `if (act.valid()) act.waitToStart()`, and the per-tick loop drops an invalid
-- action without ever starting it). Which way the player looks is not one of
-- those things -- he is still facing the way he walked in -- so the turn is a
-- precondition to wait for, below, not a test to fail here.
function ISCeroSecToggleAction:isValid()
	if not self.object or not self.object:getSquare() then return false end
	if not CeroSec.isComputerSprite(self.object:getSpriteName()) then return false end
	local front = CeroSecReach.frontSquare(self.object)
	return front ~= nil and self.character:getCurrentSquare() == front
end

-- Turn to the screen first and hold the action back until the turn is done.
-- Vanilla's own "face the object, then work on it" pattern
-- (ISAddTakeDispenserBottle.lua:9-11).
function ISCeroSecToggleAction:waitToStart()
	self.character:faceThisObject(self.object)
	return self.character:shouldBeTurning()
end

-- Keep him turned for the length of the animation, as the dispenser does
-- (ISAddTakeDispenserBottle.lua:14-17).
function ISCeroSecToggleAction:update()
	self.character:faceThisObject(self.object)
end

function ISCeroSecToggleAction:start()
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
