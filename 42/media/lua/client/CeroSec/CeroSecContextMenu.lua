require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecReach"
require "CeroSec/ISCeroSecToggleAction"
require "CeroSec/ISCeroSecUseAction"
require "CeroSec/ISCeroSecDiskAction"
require "CeroSec/CeroSecManualUI"

CeroSecContextMenu = {}

local function hasPower(square)
	if not square then return false end
	-- Same test the car battery charger uses (ISWorldObjectContextMenu.lua:460).
	return square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil)
end

-- Walk to the middle of the square the screen looks at, then toggle from there.
-- The middle and not the square: a player already standing in it is walked to
-- the point inside it all the same, so the switch is thrown from where the
-- character can be seen to be standing at the machine (CeroSecReach.walkToFront).
-- The toggle action checks in its isValid that the player really made it, so a
-- walk that fails or gets interrupted changes nothing.
function CeroSecContextMenu.onToggle(worldobjects, computer, playerObj, height)
	CeroSecReach.walkToFront(playerObj, computer, function()
		ISTimedActionQueue.add(ISCeroSecToggleAction:new(playerObj, computer, height))
	end)
end

-- Same walk and same turn as the toggle, plus a chair. Sitting down at a
-- computer is what a chair pulled up to a desk is for, so when there is one on
-- the front square looking at the screen the player takes it on the way in:
-- vanilla's own rest action, with the arguments the vanilla menu passes it
-- (ISWorldObjectContextMenu.onRestPathFound, ISWorldObjectContextMenu.lua:948:
-- ISRestAction:new(playerObj, furniture, true)). It is a short action, not a
-- nap: with useAnimations it force-completes as soon as the sitting animation
-- reports itself started (ISRestAction.lua:47-53), leaving the character seated
-- and the queue free for the terminal behind it.
--
-- The walk is not vanilla's pathToSitOnFurniture, because that one picks its
-- own seat and its own square; ours is the front square or nothing, and the use
-- action checks in its isValid that the player made it. What it does borrow
-- from vanilla is the seat point itself: the walk aims at the place the game
-- would stand him in to take that chair from the front, because the rest action
-- picks the side of the chair from where he is standing and nothing else
-- (CeroSecReach, "Getting there"). That is the true parameter below.
function CeroSecContextMenu.onUse(worldobjects, computer, playerObj, height)
	CeroSecReach.walkToFront(playerObj, computer, function()
		local chair = CeroSecReach.chairInFront(computer)
		if chair and not CeroSecReach.isSeatedOn(playerObj, chair) then
			ISTimedActionQueue.add(ISRestAction:new(playerObj, chair, true))
		end
		ISTimedActionQueue.add(ISCeroSecUseAction:new(playerObj, computer, height))
	end, true)
end


--
-- The floppy drive
--
-- The slot is mechanical and the two options are offered whether the machine is
-- lit or not: a disk goes into a dark computer and comes out of one, which is how
-- a survivor carries his notes out of a building whose power went weeks ago.
--
-- What is IN the drive is the machine's to know, and the client is told exactly
-- one bit of it -- luaObject.disk, a boolean off the synced keys
-- (SCeroSecSystem:initSystem). Everything else about the disk stays on the
-- server, and every refusal these entries grey out is re-asked there.
--

-- The first disk the player is carrying, bag included, or nil. The four colours
-- in the order a box of them came in, so a survivor with one of each reaches for
-- the same one every time rather than for whichever the hash landed on.
function CeroSecContextMenu.floppyOn(playerObj)
	local inv = playerObj:getInventory()
	if not inv then return nil end
	for i = 1, #CeroSec.FLOPPY_TYPES do
		local item = inv:getFirstTypeRecurse(CeroSec.FLOPPY_TYPES[i])
		if item then return item end
	end
	return nil
end

function CeroSecContextMenu.onInsertFloppy(worldobjects, computer, playerObj, height, item)
	CeroSecReach.walkToFront(playerObj, computer, function()
		ISTimedActionQueue.add(ISCeroSecDiskAction:new(playerObj, computer, height, item))
	end)
end

function CeroSecContextMenu.onEjectFloppy(worldobjects, computer, playerObj, height)
	CeroSecReach.walkToFront(playerObj, computer, function()
		ISTimedActionQueue.add(ISCeroSecDiskAction:new(playerObj, computer, height, nil))
	end)
end

-- The one refusal on this menu that is not the machine's and not Unix's: it is
-- the game's UI saying no to a gesture. "Eject the floppy first." -- because
-- there is one slot, and because a survivor who has just been told the drive is
-- occupied should be told what to do about it in the same breath.
function CeroSecContextMenu.addDrive(context, worldobjects, computer, playerObj, height)
	local luaObject = nil
	if CCeroSecSystem ~= nil and CCeroSecSystem.instance ~= nil then
		local square = computer:getSquare()
		if square then
			luaObject = CCeroSecSystem.instance:getLuaObjectAt(
				square:getX(), square:getY(), square:getZ())
		end
	end
	-- No mirror yet means a computer the client has not been told about. Saying
	-- nothing is the only honest answer: a menu built on a guess about what is in
	-- the drive is a menu that offers to eject nothing.
	if not luaObject then return end
	local inDrive = luaObject.disk == true

	-- Out of reach greys both entries for the same reason the two above are
	-- greyed, and in the same order: it is the same walk.
	local reason
	if height == "high" then
		reason = "Tooltip_CeroSec_TooHigh"
	elseif not CeroSecReach.canStandInFront(playerObj, computer) then
		reason = "Tooltip_CeroSec_NoAccess"
	end

	local function grey(option, key)
		if not key then return end
		option.notAvailable = true
		option.toolTip = ISWorldObjectContextMenu.addToolTip()
		option.toolTip:setVisible(false)
		option.toolTip.description = getText(key)
	end

	-- Nothing to insert is not an entry at all: a player with no disk on him has
	-- no business reading about a drive.
	local item = CeroSecContextMenu.floppyOn(playerObj)
	if item then
		local insert = context:addOption(getText("ContextMenu_CeroSec_InsertFloppy"),
			worldobjects, CeroSecContextMenu.onInsertFloppy, computer, playerObj, height, item)
		-- A full drive beats being out of reach, deliberately: it is the reason a
		-- player can act on standing where he is.
		if inDrive then
			grey(insert, "Tooltip_CeroSec_DriveFull")
		else
			grey(insert, reason)
		end
	end

	-- And nothing to eject is not an entry either.
	if inDrive then
		local eject = context:addOption(getText("ContextMenu_CeroSec_EjectFloppy"),
			worldobjects, CeroSecContextMenu.onEjectFloppy, computer, playerObj, height)
		grey(eject, reason)
	end
end

-- The picker hands us what sits under the cursor: on a counter or a desk that
-- is the counter, not the table-top computer on it. Vanilla menus that target
-- one object scan the square of every picked object instead
-- (ISRadioAndTvMenu.lua:16-26, ISBBQMenu.lua:20), so do the same.
--
-- Two passes, cheapest last. First the mouse itself, because a computer raised
-- on a crate is drawn over the square behind it and the picker never names its
-- square at all (see the picking notes in CeroSecReach). Then the plain scan of
-- the picked squares, which is what answers for a joypad, for a click the mouse
-- test does not settle, and for everything that worked before.
function CeroSecContextMenu.findComputer(worldobjects, playerIndex)
	if playerIndex and not JoypadState.players[playerIndex + 1] then
		local picked = CeroSecReach.pickComputer(playerIndex, getMouseX(), getMouseY(), worldobjects)
		if picked then return picked end
	end

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

	local computer = CeroSecContextMenu.findComputer(worldobjects, player)
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

	-- Nothing to use on a dark screen: the terminal option only exists once the
	-- machine is on. Out of reach and no access grey it out exactly as above --
	-- the same two reasons, in the same order -- because it is the same walk.
	if isOn then
		local use = context:addOption(getText("ContextMenu_CeroSec_Use"), worldobjects,
			CeroSecContextMenu.onUse, computer, playerObj, height)

		local useReason
		if height == "high" then
			useReason = "Tooltip_CeroSec_TooHigh"
		elseif not CeroSecReach.canStandInFront(playerObj, computer) then
			useReason = "Tooltip_CeroSec_NoAccess"
		end

		if useReason then
			use.notAvailable = true
			use.toolTip = ISWorldObjectContextMenu.addToolTip()
			use.toolTip:setVisible(false)
			use.toolTip.description = getText(useReason)
		end
	end

	CeroSecContextMenu.addDrive(context, worldobjects, computer, playerObj, height)

	CeroSecContextMenu.addDevManual(context, playerObj)
end

-- The testing door. While CeroSec.DEV_MANUAL_MENU is on, any computer -- lit or
-- dark, in reach or not -- offers the manual straight off its menu, with no
-- copy of the book anywhere and no walk to get to it, so the reader can be
-- worked on without first going shopping for the item.
--
-- A SUBMENU, because the manual is three volumes and a door onto one of them
-- is a door onto a third of the reader. One entry per volume on the shelf,
-- named the way the volume names itself. With no shelf at all there is nothing
-- to put a door onto: the three volumes are shipped files and an empty shelf is
-- one of them failing to load, which is said in the log and not answered with a
-- menu entry onto nothing.
--
-- LAST on the menu, deliberately: it is not part of the machine and it must
-- never sit between the two options that are. And it asks nothing of the
-- computer -- not its power, not its height, not whether anybody can stand in
-- front of it -- because it is not really about the computer at all. The
-- computer is only the nearest thing to right-click.
--
-- Off, this adds nothing and there is not an entry to be seen: the book is
-- found or it is not read.
function CeroSecContextMenu.addDevManual(context, playerObj)
	if not CeroSec.DEV_MANUAL_MENU then return end

	-- getNew, addSubMenu, then fill it: the order every vanilla submenu is
	-- built in (ISWorldObjectContextMenu.lua:1167-1169). addSubMenu copies the
	-- child's number onto the parent option, so the child has to exist first.
	local option = context:addOption(getText("ContextMenu_CeroSec_DevManual"))
	local sub = ISContextMenu:getNew(context)
	context:addSubMenu(option, sub)

	local shelf = CeroSecManualBook.shelf()
	if #shelf == 0 and CeroSec.log ~= nil then
		CeroSec.log("manual: the shelf is empty -- no volume file loaded")
	end
	for v = 1, #shelf do
		local volume = shelf[v]
		-- The volume's own name, not a translation key: this is a door into a
		-- piece of documentation and it is never seen by a player.
		sub:addOption(volume.name or volume.id, playerObj,
			CeroSecContextMenu.onDevManual, volume.id)
	end
end

function CeroSecContextMenu.onDevManual(playerObj, volumeId)
	CeroSecManualUI.open(playerObj, volumeId, nil)
end

Events.OnFillWorldObjectContextMenu.Add(CeroSecContextMenu.OnFillWorldObjectContextMenu)
