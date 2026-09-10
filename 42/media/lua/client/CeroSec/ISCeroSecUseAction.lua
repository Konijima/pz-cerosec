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
	return front ~= nil and CeroSecReach.standingSquare(self.character, self.object) == front
end

-- Seated on the chair that stands in front of this computer, the sit is already
-- the turn: the rest action faces the character the chair's way
-- (ISRestAction:setWhileSittingDirection, ISRestAction.lua:238-243) and a chair
-- only counts as the one in front when that way is the screen. Turning him
-- again would fight the pose vanilla has just set.
function ISCeroSecUseAction:seated()
	return CeroSecReach.isSeatedOn(self.character, CeroSecReach.chairInFront(self.object))
end

-- Turn to the screen first and hold the action back until the turn is done
-- (ISAddTakeDispenserBottle.lua:9-11).
function ISCeroSecUseAction:waitToStart()
	if self:seated() then return false end
	self.character:faceThisObject(self.object)
	return self.character:shouldBeTurning()
end

function ISCeroSecUseAction:update()
	if self:seated() then return end
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
	local window = CeroSecTerminal.open(self.character, self.object)
	-- The height is this action's, so it is handed over here rather than worked
	-- out again: the window then keeps a character typing at the keyboard for as
	-- long as it is open (ISCeroSecTypeAction, queued by the window itself once
	-- this action has left the queue).
	if window then window:startTyping(self.height) end
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
