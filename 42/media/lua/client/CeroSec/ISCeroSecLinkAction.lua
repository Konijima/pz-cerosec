require "TimedActions/ISBaseTimedAction"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecModules"

--
-- Running a cable from a fixture to a computer -- and cutting it, which is the
-- same walk with the reel going the other way and is therefore the same action
-- with a flag on it (ISCeroSecModuleAction's own shape).
--
-- WHAT THE TIME IS. Fitting a module is a man on a chair with a screwdriver, so
-- its duration is the box's own. A cable is a man PAYING OUT WIRE across a yard,
-- so its duration is the DISTANCE: CeroSecModules.LINK_TIME a tile, capped at
-- LINK_TIME_MAX, less the three ticks a level that vanilla's own electrical job
-- takes off (ISFixGenerator:getDuration, 150 - perk * 3). The cap is what makes
-- the longest run bearable: nobody stands still through thirty tiles of it, and
-- past the cap the honest answer is that he walked it while the bar filled.
--
-- The animation is vanilla's Loot at waist height, the same one the module
-- action uses, and for the same reason: there is no cable-laying animation in
-- this game and repairing a generator -- the electrical work vanilla ships --
-- uses Loot too.
--
-- What travels at the end is the fixture's square and index, and the MACHINE's
-- square: the shape vanilla's own client commands use to name a world object
-- (ISWorldObjectContextMenu.lua:3076), twice. Never the hostname -- that is a
-- thing a player types and changes, and a cable is a thing he laid. The server
-- looks both ends up itself, works the price out from the two squares and
-- re-asks every question this action asked; nothing here is believed over there
-- (SCeroSecSystem's Commands.linkmodule).
--

ISCeroSecLinkAction = ISBaseTimedAction:derive("ISCeroSecLinkAction")

-- Only what can already be true before the action starts, and only what the
-- SERVER will ask again: the fixture is still in the world, the rule still lets
-- him, he still has the tool -- and, for a run, the wire still in his bags.
function ISCeroSecLinkAction:isValid()
	if not self.object or not self.object:getSquare() then return false end
	-- Off its square is -1, vanilla's own way of asking whether a world object is
	-- still there (ISWorldObjectContextMenu.lua:1345).
	if self.object:getObjectIndex() == -1 then return false end

	local inv = self.character:getInventory()
	if not inv then return false end
	if not inv:getFirstTypeRecurse(CeroSecModules.TOOL) then return false end
	if self.character:getPerkLevel(Perks.Electricity)
			< CeroSecModules.linkSkill(self.object) then
		return false
	end

	if not self.link then
		return CeroSecModules.unlinkRefusal(self.object, self.mx, self.my, self.mz,
			self.character) == nil
	end
	if CeroSecModules.linkRefusal(self.object, self.mx, self.my, self.mz,
			self.character) ~= nil then
		return false
	end
	-- And the reel, which is the one thing about a cable run that can go away
	-- while he is walking it: he dropped it, or a second job spent it.
	return CeroSecModules.wireCount(inv) >= self.wire
end

-- Turn to the thing first and hold the action back until the turn is done
-- (ISAddTakeDispenserBottle.lua:9-11), the way the mod's other actions do.
function ISCeroSecLinkAction:waitToStart()
	self.character:faceThisObject(self.object)
	return self.character:shouldBeTurning()
end

function ISCeroSecLinkAction:update()
	self.character:faceThisObject(self.object)
end

function ISCeroSecLinkAction:start()
	self:setActionAnim("Loot")
	self:setAnimVariable("LootPosition", "Mid")
	self:setOverrideHandModels(nil, nil)
end

function ISCeroSecLinkAction:stop()
	ISBaseTimedAction.stop(self)
end

function ISCeroSecLinkAction:perform()
	local square = self.object:getSquare()
	local args = {
		x = square:getX(), y = square:getY(), z = square:getZ(),
		index = self.object:getObjectIndex(),
		mx = self.mx, my = self.my, mz = self.mz,
	}
	if self.link then
		CCeroSecSystem.instance:sendCommand(self.character, "linkmodule", args)
	else
		CCeroSecSystem.instance:sendCommand(self.character, "unlinkmodule", args)
	end
	ISBaseTimedAction.perform(self)
end

-- LINK_TIME a tile, capped, then vanilla's three ticks a level. The tiles are the
-- flat ones a survivor paces out and not the price: a cable to the floor above
-- costs four tiles of wire more and is not four tiles further to walk.
function ISCeroSecLinkAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	local tiles = CeroSecModules.linkTiles(self.object:getSquare():getX(),
		self.object:getSquare():getY(), self.mx, self.my)
	local time = tiles * CeroSecModules.LINK_TIME
	if time > CeroSecModules.LINK_TIME_MAX then time = CeroSecModules.LINK_TIME_MAX end
	if time < CeroSecModules.LINK_TIME then time = CeroSecModules.LINK_TIME end
	return time - (self.character:getPerkLevel(Perks.Electricity) * 3)
end

-- mx, my, mz is the machine's square; link is true to run one and false to cut
-- it. `wire` is what the menu worked the price out to be, carried only so that
-- isValid can ask whether he still has it -- the server works its own out.
function ISCeroSecLinkAction:new(character, object, mx, my, mz, link, wire)
	local o = ISBaseTimedAction.new(self, character)
	o.object = object
	o.mx, o.my, o.mz = mx, my, mz
	o.link = link == true
	o.wire = tonumber(wire) or 0
	o.stopOnWalk = true
	o.stopOnRun = true
	o.maxTime = o:getDuration()
	o.useProgressBar = true
	return o
end
