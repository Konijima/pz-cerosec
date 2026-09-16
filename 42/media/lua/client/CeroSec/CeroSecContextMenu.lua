require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecMenu"
require "CeroSec/CeroSecReach"
require "CeroSec/ISCeroSecToggleAction"
require "CeroSec/ISCeroSecUseAction"
require "CeroSec/ISCeroSecDiskAction"
require "CeroSec/CeroSecManualUI"
require "CeroSec/CeroSecDebugUI"

CeroSecContextMenu = {}

local function hasPower(square)
	if not square then return false end
	-- Same test the car battery charger uses (ISWorldObjectContextMenu.lua:460).
	return square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil)
end

-- Walk to the stand point of the square the screen looks at, then toggle from
-- there. The point and not the square: a player already standing in it is walked
-- to the point inside it all the same, so the switch is thrown from where the
-- character can be seen to be standing at the machine, against the desk and not
-- a step from it (CeroSecReach.walkToFront).
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

-- EVERY disk he is carrying, bag included, in the same order: the four colours as
-- a box of them came in, and within one colour whatever order the container hands
-- them over in. A stable order matters more than which order it is -- a list that
-- reshuffled between two right-clicks would be a menu where the disk under the
-- cursor is not the disk that goes in.
--
-- getAllTypeRecurse and not getFirstTypeRecurse, because a survivor keeps three
-- blue disks as readily as one of each colour (javap zombie.inventory.ItemContainer:
-- getAllTypeRecurse(String) returns the ArrayList of them).
function CeroSecContextMenu.floppiesOn(playerObj)
	local out = {}
	local inv = playerObj:getInventory()
	if not inv then return out end
	for i = 1, #CeroSec.FLOPPY_TYPES do
		local found = inv:getAllTypeRecurse(CeroSec.FLOPPY_TYPES[i])
		if found ~= nil then
			for j = 0, found:size() - 1 do
				out[#out + 1] = found:get(j)
			end
		end
	end
	return out
end

-- What one disk reads as on the menu. The label FIRST, because that is the thing
-- the survivor wrote in order to be able to pick this disk out of four, and the
-- shell's colour after it in brackets.
--
-- item:getName() is the label when there is one written on it and the translated
-- item name otherwise (CeroSecFloppyMenu), so an unlabelled disk reads
-- `3.5" Floppy Disk (blue)` and a labelled one `BACKUP (blue)`. The colour is
-- always there: without it four unlabelled disks would be four identical lines,
-- which is the menu this submenu exists to replace.
function CeroSecContextMenu.diskEntry(item)
	local name = item:getName()
	if type(name) ~= "string" then name = "" end
	local colour = CeroSec.floppyColourKey(item:getFullType())
	if colour == nil then return name end
	return name .. " (" .. getText(colour) .. ")"
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
	local inDrive = CeroSec.diskInDrive(luaObject)

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
	--
	-- ONE disk is the direct entry it has always been. More than one and it becomes
	-- a submenu with a line per disk, because a drive with one slot and a survivor
	-- with four disks is a choice, and an entry that silently took the first blue
	-- one was the whole of the complaint this answers.
	--
	-- A full drive beats being out of reach, deliberately: it is the reason a
	-- player can act on standing where he is.
	local disks = CeroSecContextMenu.floppiesOn(playerObj)
	local insertReason = reason
	if inDrive then insertReason = "Tooltip_CeroSec_DriveFull" end

	if #disks == 1 then
		local insert = CeroSecMenu.addTop(context,
			getText("ContextMenu_CeroSec_InsertFloppy"),
			worldobjects, CeroSecContextMenu.onInsertFloppy, computer, playerObj, height,
			disks[1])
		grey(insert, insertReason)
	elseif #disks > 1 and insertReason ~= nil then
		-- Refused, so there is nothing to choose BETWEEN: one greyed line carrying the
		-- reason, and no submenu behind it. A greyed parent over a list of disks would
		-- be a menu that invites a survivor to pick one and then refuses the pick, and
		-- the line he needs to read is the reason and not the four names.
		--
		-- No callback on it either -- label only, the way the dev submenu's own parent
		-- is added -- so there is nothing there to fire even if a greyed entry were
		-- ever clickable.
		local insert = CeroSecMenu.addTop(context,
			getText("ContextMenu_CeroSec_InsertFloppy"))
		grey(insert, insertReason)
	elseif #disks > 1 then
		-- getNew, addSubMenu, then fill it: the order every vanilla submenu is built
		-- in (ISWorldObjectContextMenu.lua:1167-1169), and the order addDevMenu below
		-- builds its own in. addSubMenu copies the child's number onto the parent
		-- option, so the child has to exist first.
		local parent = CeroSecMenu.addTop(context,
			getText("ContextMenu_CeroSec_InsertFloppy"))
		local sub = ISContextMenu:getNew(context)
		context:addSubMenu(parent, sub)
		for d = 1, #disks do
			sub:addOption(CeroSecContextMenu.diskEntry(disks[d]), worldobjects,
				CeroSecContextMenu.onInsertFloppy, computer, playerObj, height, disks[d])
		end
	end

	-- And nothing to eject is not an entry either.
	if inDrive then
		local eject = CeroSecMenu.addTop(context,
			getText("ContextMenu_CeroSec_EjectFloppy"),
			worldobjects, CeroSecContextMenu.onEjectFloppy, computer, playerObj, height)
		grey(eject, reason)
	end
end

-- What the game handed the event, written out: the sprite and the square of
-- every object in worldobjects. One line, only while CeroSec.DEBUG is on, and it
-- goes through CeroSec.log so the debug window's Log tab shows it -- a right-click
-- that finds nothing in game is then a line to read rather than a thing to
-- reproduce.
local function logHanded(worldobjects)
	local parts = {}
	for _, object in ipairs(worldobjects) do
		local square = object:getSquare()
		parts[#parts + 1] = tostring(object:getSpriteName()) .. "@" ..
			(square and (square:getX() .. "," .. square:getY() .. "," .. square:getZ()) or "nowhere")
	end
	CeroSec.log("menu: game handed " .. #worldobjects .. " object(s): " ..
		(#parts > 0 and table.concat(parts, " ") or "none"))
end

-- The computer the right-click is about, in the order vanilla answers this kind
-- of question in.
--
-- FIRST what the game handed over. ContextPick gives the menu exactly ONE object
-- (see the picking notes in CeroSecReach), so if a computer stands on that object's
-- square -- which covers both the computer being handed over itself and a computer
-- on the very desk the cursor found, since a computer is always on its own square --
-- that is the answer and there is nothing to search for. Vanilla menus that target
-- one device do the same square scan (ISRadioAndTvMenu.lua:16-26, ISBBQMenu.lua:20).
--
-- One pass and not two: a separate "is the handed object itself a computer" branch
-- read well and could not be made to fail, because the square scan answers every
-- case it did. A branch no bench can redden is a branch nobody has checked.
--
-- THEN the mouse, because the one object the game hands over is the one that
-- scored highest and not the one nearest the cursor: a desk chair carries
-- IsoFlagType.bed and outscores a computer by 2, so a computer on a desk with a
-- chair pulled up to it loses its own menu to the chair's. That pass rebuilds
-- each nearby computer's drawn box and asks its own click mask -- the same test
-- the game settles on -- and nothing in it refuses a hit because something else
-- was picked first.
--
-- A joypad has no mouse, so it gets the first pass and stops there.
--
-- The order has one edge, kept on purpose: two desks side by side, each with a
-- computer, the cursor on the left monitor and the game resolving the click to the
-- right desk. The first pass answers with the right-hand computer where the mask
-- would have answered with the left-hand one. The game's resolution is the engine's
-- own answer, and the box arithmetic of the second pass rests on one thing only the
-- engine can settle -- that getCameraOffX() is IsoCamera.frameState.offX at the
-- moment the menu is built -- so deferring to the game first fails safe.
-- docs/PARCOURS-TEST.md step 12e is the click that checks it.
function CeroSecContextMenu.findComputer(worldobjects, playerIndex)
	if CeroSec.DEBUG then logHanded(worldobjects) end

	local done = {}
	for _, object in ipairs(worldobjects) do
		local square = object:getSquare()
		if square and not done[square] then
			done[square] = true
			local objects = square:getObjects()
			for i = 0, objects:size() - 1 do
				local candidate = objects:get(i)
				if CeroSec.isComputerSprite(candidate:getSpriteName()) then
					if CeroSec.DEBUG then
						CeroSec.log("menu: a computer on the picked square " ..
							square:getX() .. "," .. square:getY() .. "," .. square:getZ())
					end
					return candidate
				end
			end
		end
	end

	if playerIndex and not JoypadState.players[playerIndex + 1] then
		local picked = CeroSecReach.pickComputer(playerIndex, getMouseX(), getMouseY(), worldobjects)
		if picked then return picked end
	end

	if CeroSec.DEBUG then CeroSec.log("menu: no computer under the cursor") end
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

	-- THE PRIMARY ACTION LEADS, and which one that is depends on the screen: a lit
	-- machine is there to be used and a dark one to be switched on. So "Use
	-- computer" goes above "Turn off computer" on a machine that is running --
	-- using it is what a survivor came to the desk for and switching it off is the
	-- rarer gesture -- and on a dark one there is nothing to use and "Turn on
	-- computer" is the first entry there is. Every entry below is under it, and all
	-- of them are above the game's own (CeroSecMenu.addTop).
	--
	-- Nothing to use on a dark screen: the terminal option only exists once the
	-- machine is on. Out of reach and no access grey it out exactly as the toggle
	-- below is greyed -- the same two reasons, in the same order -- because it is
	-- the same walk.
	if isOn then
		local use = CeroSecMenu.addTop(context, getText("ContextMenu_CeroSec_Use"),
			worldobjects, CeroSecContextMenu.onUse, computer, playerObj, height)

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

	local label = isOn and "ContextMenu_CeroSec_TurnOff" or "ContextMenu_CeroSec_TurnOn"
	local option = CeroSecMenu.addTop(context, getText(label), worldobjects,
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

	CeroSecContextMenu.addDrive(context, worldobjects, computer, playerObj, height)

	CeroSecContextMenu.addDevMenu(context, playerObj, computer)
end

-- The testing doors. While either dev flag is on, any computer -- lit or dark, in
-- reach or not -- carries a last entry on its menu with the mod's own tools behind
-- it: the manual reader with no copy of the book anywhere
-- (CeroSec.DEV_MANUAL_MENU), and the debug window (CeroSec.DEV_DEBUG_MENU, or the
-- game's own debug mode -- CeroSec.debugAllowed). So either can be worked on
-- without first going shopping for an item or restarting the game with -debug.
--
-- A SUBMENU, because there is more than one door: the manual is three volumes and
-- a door onto one of them is a door onto a third of the reader, and the debug
-- window is a fourth entry beside them. With no shelf at all there is nothing to
-- put a manual door onto: the three volumes are shipped files and an empty shelf
-- is one of them failing to load, which is said in the log and not answered with
-- a menu entry onto nothing.
--
-- LAST on the menu, deliberately: none of it is part of the machine and it must
-- never sit between the options that are. The manual entries ask nothing of the
-- computer -- not its power, not its height, not whether anybody can stand in
-- front of it -- because they are not about the computer at all. The debug entry
-- does take the computer, but only as the machine it opens SELECTED: it is the one
-- the survivor right-clicked, which is the one he is asking about.
--
-- SO IT IS THE ONE ENTRY OF THIS MOD THAT DOES NOT GO TO THE TOP, and it is the
-- only declared exception to CeroSecMenu.addTop. Plain addOption, which appends: it
-- goes under the game's own Grab and Equip as well as under ours. Nobody who is
-- not a developer ever sees it -- both flags are false in a shipped build and the
-- third condition is an admin's connection (docs/DEBUG.md) -- so the one reader it
-- has is somebody who knows it is at the bottom, and a testing door above "Use
-- computer" would push the machine's own entries down the menu for the sake of a
-- tool.
--
-- With both flags off this adds nothing and there is not an entry to be seen.
function CeroSecContextMenu.addDevMenu(context, playerObj, computer)
	local manual = CeroSec.DEV_MANUAL_MENU
	local debug = CeroSec.debugAllowed()
	if not manual and not debug then return end

	-- getNew, addSubMenu, then fill it: the order every vanilla submenu is
	-- built in (ISWorldObjectContextMenu.lua:1167-1169). addSubMenu copies the
	-- child's number onto the parent option, so the child has to exist first.
	local option = context:addOption(getText("ContextMenu_CeroSec_Dev"))
	local sub = ISContextMenu:getNew(context)
	context:addSubMenu(option, sub)

	if manual then
		local shelf = CeroSecManualBook.shelf()
		if #shelf == 0 and CeroSec.log ~= nil then
			CeroSec.log(CeroSec.LOG_ERROR,
				"manual: the shelf is empty -- no volume file loaded")
		end
		for v = 1, #shelf do
			local volume = shelf[v]
			-- The volume's own name, not a translation key: this is a door into a
			-- piece of documentation and it is never seen by a player.
			sub:addOption(volume.name or volume.id, playerObj,
				CeroSecContextMenu.onDevManual, volume.id)
		end
	end

	-- LAST inside the submenu, for the reason the submenu is last on the menu: the
	-- three above it are one tool and this is another.
	if debug then
		sub:addOption(getText("ContextMenu_CeroSec_DevDebug"), playerObj,
			CeroSecContextMenu.onDevDebug, computer)
	end
end

function CeroSecContextMenu.onDevManual(playerObj, volumeId)
	CeroSecManualUI.open(playerObj, volumeId, nil)
end

-- The computer under the cursor is the machine the window opens selected. Its
-- SQUARE and not the object: the window carries three numbers, because the
-- machine it is looking at may be one whose chunk went away while the window was
-- open.
function CeroSecContextMenu.onDevDebug(playerObj, computer)
	local square = computer ~= nil and computer:getSquare() or nil
	if square == nil then
		CeroSecDebugUI.open(playerObj)
		return
	end
	CeroSecDebugUI.open(playerObj, square:getX(), square:getY(), square:getZ())
end

Events.OnFillWorldObjectContextMenu.Add(CeroSecContextMenu.OnFillWorldObjectContextMenu)
