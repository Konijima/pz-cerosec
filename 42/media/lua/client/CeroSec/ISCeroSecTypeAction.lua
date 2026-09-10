require "TimedActions/ISBaseTimedAction"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecReach"

--
-- The character typing, for as long as the terminal is open.
--
-- An open-ended timed action: maxTime = -1, the way vanilla writes an action
-- that ends on something other than a clock (ISQueueActionsAction.lua:44,
-- ISGrabItemAction.lua:197). It never performs; it is stopped, by the window
-- closing, by the player stepping off the front square, or by the window asking
-- for it to go so that something else can have the queue.
--
-- It does two things and nothing else:
--
--   * the loot animation while keys are actually being pressed, and only then,
--     so a player who is reading his screen is a player sitting still;
--   * the facing, while the window has the keyboard. A player who clicked
--     somewhere else may look wherever he likes; taking the keyboard back puts
--     him on the screen again (CeroSecTerminal:focusEntry).
--
-- The queue is strictly sequential and this action sits at its head
-- (ISTimedActionQueue:addToQueue and :onCompleted), so nothing can be queued
-- behind it and expect to run: the character is busy at the computer for as
-- long as the window is up, which is what he is. Anything the window needs done
-- -- sitting back down on the chair -- is done by getting rid of this action
-- first and putting a fresh one in afterwards.
--

ISCeroSecTypeAction = ISBaseTimedAction:derive("ISCeroSecTypeAction")

-- How long after the last keystroke the hands come off the keyboard.
ISCeroSecTypeAction.QUIET_MS = 1500

-- Only what is already true before the action starts, the rung 1b rule: the
-- computer is there and lit, and the player is on the square in front of it.
-- Which way he is looking is not one of those things.
function ISCeroSecTypeAction:isValid()
	if self.cancelled then return false end
	if self.window == nil or self.window.closing then return false end
	if not self.object or not self.object:getSquare() then return false end
	if not CeroSec.isOnSprite(self.object:getSpriteName()) then return false end
	local front = CeroSecReach.frontSquare(self.object)
	return front ~= nil and CeroSecReach.standingSquare(self.character, self.object) == front
end

-- Seated on the chair in front of this computer, the sit is already the turn
-- and turning him again fights the pose vanilla has just set
-- (ISCeroSecUseAction:seated).
function ISCeroSecTypeAction:seated()
	return CeroSecReach.isSeatedOn(self.character, CeroSecReach.chairInFront(self.object))
end

function ISCeroSecTypeAction:waitToStart()
	if self:seated() then return false end
	self.character:faceThisObject(self.object)
	return self.character:shouldBeTurning()
end

function ISCeroSecTypeAction:start()
	self.typing = false
end

function ISCeroSecTypeAction:update()
	local window = self.window
	if window == nil or window.closing then return end

	if window:hasKeyboard() and not self:seated() then
		self.character:faceThisObject(self.object)
	end

	local typing = window:typingRecently(ISCeroSecTypeAction.QUIET_MS)
	if typing == self.typing then return end
	self.typing = typing
	if typing then
		-- Same three calls the grab action makes (ISGrabItemAction.lua:50-52)
		-- and the use action makes on the way in.
		self:setActionAnim("Loot")
		self:setAnimVariable("LootPosition", self.height == "low" and "Low" or "Mid")
		self:setOverrideHandModels(nil, nil)
	else
		self:clearAnim()
	end
end

-- setActionAnim writes the anim variable PerformingAction and sets
-- IsPerformingAnAction; stopTimedActionAnim clears every variable the action
-- set and puts IsPerformingAnAction back to false
-- (BaseAction.setActionAnim, LuaTimedActionNew.stopTimedActionAnim). They are
-- the pair, so the hands come off the keyboard the same way they went on.
function ISCeroSecTypeAction:clearAnim()
	self.typing = false
	if self.action then self.action:stopTimedActionAnim() end
end

function ISCeroSecTypeAction:stop()
	self:clearAnim()
	if self.window and self.window.typeAction == self then self.window.typeAction = nil end
	ISBaseTimedAction.stop(self)
end

function ISCeroSecTypeAction:forceCancel()
	if self.window and self.window.typeAction == self then self.window.typeAction = nil end
end

-- maxTime is -1, so nothing ever reaches here on a clock. It is kept honest
-- rather than left out.
function ISCeroSecTypeAction:perform()
	self:clearAnim()
	if self.window and self.window.typeAction == self then self.window.typeAction = nil end
	ISBaseTimedAction.perform(self)
end

function ISCeroSecTypeAction:new(character, object, height, window)
	local o = ISBaseTimedAction.new(self, character)
	o.object = object
	o.height = height
	o.window = window
	o.cancelled = false
	o.typing = false
	o.maxTime = -1
	o.stopOnWalk = true
	o.stopOnRun = true
	o.useProgressBar = false
	return o
end
