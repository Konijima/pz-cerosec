require "TimedActions/ISBaseTimedAction"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecModules"

--
-- Screwing a hardware module to a door, a window or a light switch -- and
-- taking it off again, which is the same job with the screwdriver turned the
-- other way and is therefore the same action with a flag on it.
--
-- Cut from vanilla's own electrical job, shared/TimedActions/ISFixGenerator.lua:
-- the generic Loot animation (there is no screwdriver animation in this game --
-- repairing a generator, which is the electrical work vanilla ships, uses the
-- same one), a duration that comes down with the perk, and the experience
-- awarded through the global `addXp` at the end of it. The numbers per module
-- are in CeroSecModules.LIST.
--
-- The walk in front of the thing is queued before this by the menu
-- (luautils.walkAdjWindowOrDoor for a door or a window, luautils.walkAdj for a
-- light switch -- vanilla's own two), and isValid is what stops the job when the
-- walk failed or the survivor wandered off, exactly as the mod's other actions
-- do.
--
-- What travels at the end is the square, the object's index on it and the
-- module's id -- the shape vanilla's own client commands use to name a world
-- object (ISWorldObjectContextMenu.lua:3076). The server looks the object up
-- itself and re-asks every question this action asked; nothing here is believed
-- over there.
--

ISCeroSecModuleAction = ISBaseTimedAction:derive("ISCeroSecModuleAction")

-- Only what can already be true before the action starts, and only what the
-- SERVER will ask again: the fixture is still in the world, the module still
-- fits it, and he still has the tool -- and the module itself, when he is
-- fitting one.
function ISCeroSecModuleAction:isValid()
	if not self.object or not self.object:getSquare() then return false end
	-- Off its square is -1, which is vanilla's own way of asking whether a world
	-- object is still there (ISWorldObjectContextMenu.lua:1345, the light switch).
	if self.object:getObjectIndex() == -1 then return false end
	if not CeroSecModules.fitsOn(self.object, self.module.id) then return false end

	local inv = self.character:getInventory()
	if not inv then return false end
	if not inv:getFirstTypeRecurse(CeroSecModules.TOOL) then return false end

	local fitted = CeroSecModules.installedOn(self.object)
	if self.install then
		if fitted[self.module.id] then return false end
		return inv:getFirstTypeRecurse(self.module.item) ~= nil
	end
	return fitted[self.module.id] == true
end

-- Turn to the thing first and hold the action back until the turn is done
-- (ISAddTakeDispenserBottle.lua:9-11), the way the mod's other actions do.
function ISCeroSecModuleAction:waitToStart()
	self.character:faceThisObject(self.object)
	return self.character:shouldBeTurning()
end

function ISCeroSecModuleAction:update()
	self.character:faceThisObject(self.object)
end

function ISCeroSecModuleAction:start()
	-- The same three calls the mod's other actions make (ISGrabItemAction.lua:50-52).
	-- "Mid" is the waist-height reach (ISFeedingTrough.lua:45), which is where a
	-- lock, a light switch and a window catch are; a generator is on the floor and
	-- that is why vanilla's electrical action asks for "Low" instead.
	self:setActionAnim("Loot")
	self:setAnimVariable("LootPosition", "Mid")
	self:setOverrideHandModels(nil, nil)
end

function ISCeroSecModuleAction:stop()
	ISBaseTimedAction.stop(self)
end

function ISCeroSecModuleAction:perform()
	local square = self.object:getSquare()
	local args = {
		x = square:getX(), y = square:getY(), z = square:getZ(),
		index = self.object:getObjectIndex(),
		module = self.module.id,
	}
	if self.install then
		CCeroSecSystem.instance:sendCommand(self.character, "installmodule", args)
		-- Vanilla awards the experience for electrical work at the end of the job
		-- and on the machine the character is on (ISFixGenerator:complete,
		-- addXp(self.character, Perks.Electricity, 5)). Fitting one is a job;
		-- taking one off teaches nobody anything and pays nothing.
		addXp(self.character, Perks.Electricity, self.module.xp)
	else
		CCeroSecSystem.instance:sendCommand(self.character, "uninstallmodule", args)
	end
	ISBaseTimedAction.perform(self)
end

-- Vanilla's own shape for electrical work: a base the job is worth, less three
-- ticks a level (ISFixGenerator:getDuration, 150 - perk * 3). The base is the
-- module's own, because fitting a contact is not fitting an operator.
function ISCeroSecModuleAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return self.module.time - (self.character:getPerkLevel(Perks.Electricity) * 3)
end

-- module is a row of CeroSecModules.LIST; install is true to fit one and false
-- to take it off.
function ISCeroSecModuleAction:new(character, object, module, install)
	local o = ISBaseTimedAction.new(self, character)
	o.object = object
	o.module = module
	o.install = install == true
	o.stopOnWalk = true
	o.stopOnRun = true
	o.maxTime = o:getDuration()
	o.useProgressBar = true
	return o
end
