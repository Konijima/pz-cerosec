require "TimedActions/ISBaseTimedAction"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecReach"

--
-- Pushing a disk into the slot, and taking it back out.
--
-- Same shape as the toggle (ISCeroSecToggleAction): the walk to the front square
-- is queued before it, this only says whether the player really made it, turns to
-- the machine in waitToStart, and does its one thing at the end.
--
-- Power is not asked about, here or on the server. A 3.5-inch drive's slot is a
-- spring and a lever: a disk goes into a dark machine and comes out of one, which
-- is the whole reason a survivor can carry a disk out of a building whose power
-- went weeks ago.
--
-- The action carries the item's ID and not the item: what goes over the wire is a
-- number the server looks up in the sender's OWN inventory, so nothing about the
-- disk is taken on the client's word (SCeroSecSystem's Commands.insertfloppy).
--

ISCeroSecDiskAction = ISBaseTimedAction:derive("ISCeroSecDiskAction")

-- Only what is already true before the action starts. Which way the player looks
-- is not one of those things -- he is still facing the way he walked in -- and
-- neither is whether the drive is empty: that is the server's to decide at the
-- moment the command lands, and a stale answer here would be a menu entry that
-- lies rather than one that is refused.
function ISCeroSecDiskAction:isValid()
	if not self.object or not self.object:getSquare() then return false end
	if not CeroSec.isComputerSprite(self.object:getSpriteName()) then return false end
	-- The disk has to still be in his hands when the action runs -- a container of
	-- nil is an item that has been dropped, eaten or handed to somebody. Nothing to
	-- ask on the way out: what is being taken out is the machine's.
	if self.item ~= nil and self.item:getContainer() == nil then return false end
	local front = CeroSecReach.frontSquare(self.object)
	return front ~= nil and CeroSecReach.standingSquare(self.character, self.object) == front
end

-- Turn to the machine first and hold the action back until the turn is done
-- (ISAddTakeDispenserBottle.lua:9-11).
function ISCeroSecDiskAction:waitToStart()
	self.character:faceThisObject(self.object)
	return self.character:shouldBeTurning()
end

function ISCeroSecDiskAction:update()
	self.character:faceThisObject(self.object)
end

function ISCeroSecDiskAction:start()
	-- Same three calls the toggle makes (ISGrabItemAction.lua:50-52). The slot is
	-- on the front of the case, at the same height as the switch, so it is the
	-- same reach.
	self:setActionAnim("Loot")
	self:setAnimVariable("LootPosition", self.height == "low" and "Low" or "Mid")
	self:setOverrideHandModels(nil, nil)
end

function ISCeroSecDiskAction:stop()
	ISBaseTimedAction.stop(self)
end

function ISCeroSecDiskAction:perform()
	local square = self.object:getSquare()
	local args = { x = square:getX(), y = square:getY(), z = square:getZ() }
	if self.item ~= nil then
		args.item = self.item:getID()
		CCeroSecSystem.instance:sendCommand(self.character, "insertfloppy", args)
	else
		CCeroSecSystem.instance:sendCommand(self.character, "ejectfloppy", args)
	end
	ISBaseTimedAction.perform(self)
end

-- Short: it is one push. The same thirty ticks the switch takes, because it is
-- the same reach to the same front panel.
function ISCeroSecDiskAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return 30
end

-- item is the disk going in, or nil for the one coming out.
function ISCeroSecDiskAction:new(character, object, height, item)
	local o = ISBaseTimedAction.new(self, character)
	o.object = object
	o.height = height
	o.item = item
	o.stopOnWalk = true
	o.stopOnRun = true
	o.maxTime = o:getDuration()
	o.useProgressBar = false
	return o
end
