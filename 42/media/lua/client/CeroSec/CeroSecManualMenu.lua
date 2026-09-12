require "ISUI/ISInventoryPane"
require "CeroSec/CeroSecManualUI"
require "CeroSec/CeroSecPhonebookUI"

--
-- "Read the User's Guide", on the inventory menu.
--
-- The event is the one vanilla put there for exactly this
-- (ISInventoryPaneContextMenu.lua:933-935: "use the event (as you would
-- 'OnTick' etc) to add items to context menu without mod conflicts"), and it is
-- fired with (playerNum, context, items).
--
-- `items` is not a list of InventoryItems: a stack of identical items comes
-- through as one table with an `items` array inside it, which is why every
-- vanilla reader of this event unpacks both shapes
-- (ISRemoveItemTool.lua:347-357). One copy of a given book is enough -- they
-- are all the same book -- so the first one found is the one its option opens.
--
-- There are three books, so there may be three options: each volume in the
-- selection gets its own, named after itself. A menu offering "Read the manual"
-- three times over would be a menu that cannot be used.
--

CeroSecManualMenu = {}

-- The set, in the order it is printed on the shelf, and the order the menu
-- lists it in: an ordered list and not a map keyed by item, because pairs()
-- would shuffle the entries from one right-click to the next.
CeroSecManualMenu.BOOKS = {
	{ item = "CeroSec.ManualUser", volume = "user",
		label = "ContextMenu_CeroSec_ReadUser" },
	{ item = "CeroSec.ManualAdmin", volume = "admin",
		label = "ContextMenu_CeroSec_ReadAdmin" },
	{ item = "CeroSec.ManualProgrammer", volume = "programmer",
		label = "ContextMenu_CeroSec_ReadProgrammer" },
}

-- The one item out of a menu entry, whether it is an item or a stack of them.
local function itemOf(entry)
	if entry == nil then return nil end
	if instanceof(entry, "InventoryItem") then return entry end
	if entry.items and entry.items[1] then return entry.items[1] end
	return nil
end

-- Which volume one of our items opens, or nil for anything that is not one of
-- them. The BOOKS table above is the only list of that anywhere: the menu, the
-- double-click and the benches all read it, so an item added to the set is on
-- both doors at once or on neither.
function CeroSecManualMenu.volumeOf(fullType)
	for b = 1, #CeroSecManualMenu.BOOKS do
		if CeroSecManualMenu.BOOKS[b].item == fullType then
			return CeroSecManualMenu.BOOKS[b].volume
		end
	end
	return nil
end

-- The first copy of one named book in a selection.
function CeroSecManualMenu.findManual(items, fullType)
	for i = 1, #items do
		local item = itemOf(items[i])
		if item and item:getFullType() == fullType then return item end
	end
	return nil
end

function CeroSecManualMenu.onRead(item, playerObj, volumeId)
	CeroSecManualUI.open(playerObj, volumeId, item)
end

-- The PHONE BOOK, which is not one of ours and is not on the shelf.
--
-- Base.Phonebook is vanilla's own item, and vanilla's Read stays exactly where it
-- was: relieving boredom by leafing through it is a thing a survivor does with a
-- phone book and this mod does not take it away. What is added beside it is the
-- other thing a phone book is for -- looking a number up -- and the entry is its
-- own because it opens a different window on a different book
-- (CeroSecPhonebookUI, CeroSecPhonebook).
--
-- Deliberately NOT an entry in BOOKS above: that list is the mod's own volumes,
-- every one of them an item this mod declares and a volume on the shelf, and the
-- bench holds it to both.
CeroSecManualMenu.PHONEBOOK = {
	item = CeroSecPhonebook.ITEM,
	label = "ContextMenu_CeroSec_LookUpNumbers",
}

function CeroSecManualMenu.onLookUp(item, playerObj)
	CeroSecPhonebookUI.look(item, playerObj)
end

function CeroSecManualMenu.OnFillInventoryObjectContextMenu(playerNum, context, items)
	local playerObj = getSpecificPlayer(playerNum)
	if not playerObj then return end

	for b = 1, #CeroSecManualMenu.BOOKS do
		local book = CeroSecManualMenu.BOOKS[b]
		local copy = CeroSecManualMenu.findManual(items, book.item)
		if copy then
			-- addOption(label, target, callback, ...) calls callback(target, ...),
			-- the way the vanilla debug menu adds its own option to this same
			-- event (ISRemoveItemTool.lua:369).
			context:addOption(getText(book.label), copy,
				CeroSecManualMenu.onRead, playerObj, book.volume)
		end
	end

	-- And the phone book, last: it is vanilla's item and not one of the set, so it
	-- goes under the volumes a survivor is carrying rather than in among them.
	local phonebook = CeroSecManualMenu.findManual(items, CeroSecManualMenu.PHONEBOOK.item)
	if phonebook then
		context:addOption(getText(CeroSecManualMenu.PHONEBOOK.label), phonebook,
			CeroSecManualMenu.onLookUp, playerObj)
	end
end

--
-- Double-clicking a volume opens it
--
-- A book you double-click opens: that is what the gesture means everywhere else
-- in this inventory, and vanilla already routes it. The chain is
-- ISInventoryPane:onMouseDoubleClick (ISInventoryPane.lua:1141) calling
-- ISInventoryPane:doContextualDblClick(item) (:1199) for an item in the player's
-- own inventory, and that one is a ladder of elseifs over what the item IS --
-- a weapon is equipped, a map is checked, and at :1102-1103 a Literature item
-- that is not uninteresting and is readable in this light goes to
-- ISInventoryPaneContextMenu.readItem, which queues vanilla's own ISReadABook.
--
-- Our volumes never reach that rung: they are ItemType = base:normal on purpose
-- (items_cerosec.txt), so vanilla's Literature test is false for them and its
-- read -- the timed action that sits the character down for hours -- is exactly
-- what we do not want. So the gesture is ours to answer, and the place to answer
-- it is doContextualDblClick itself: it is the ONE function the double-click
-- funnels through, it is called with the item, and it is where every other
-- "double-click does the obvious thing" in the game is written.
--
-- A WRAPPER and not a replacement. The original is kept and called for
-- everything that is not one of our three books, so a double-click on a
-- screwdriver, a bag or a vanilla book does precisely what it did before this
-- mod was installed. Our books return before it and the original never sees
-- them, which is the only reason nothing needs to be known about its ladder.
--
-- Idempotent, and it has to be: wrapping twice would make CeroSecManualMenu.vanillaDblClick
-- point at our own wrapper and a double-click on a screwdriver would recurse
-- until the stack gave out. The guard is the wrapper's own presence and not a
-- flag beside it, so a reload that dropped the flag could not lose the wrap.
--
-- ISInventoryPane is REQUIRED at the top of this file rather than hooked on an
-- event: a wrap written against a class that is not loaded yet is a wrap on nil,
-- and require is how this mod already reaches a vanilla class it derives from
-- (ISCeroSecDiskAction.lua requires TimedActions/ISBaseTimedAction).
--

CeroSecManualMenu.vanillaDblClick = nil

-- true when this was one of ours and the reader is open, false when the gesture
-- is somebody else's business. A pane whose player has gone -- the window
-- outliving the character by a frame -- is nobody's book: false, so the original
-- answers it and not a reader opened on nil.
function CeroSecManualMenu.doubleClick(pane, item)
	if item == nil or not instanceof(item, "InventoryItem") then return false end
	local volume = CeroSecManualMenu.volumeOf(item:getFullType())
	if volume == nil then return false end
	local playerObj = getSpecificPlayer(pane.player)
	if playerObj == nil then return false end
	-- Through the menu's own handler, so the two doors cannot drift: the option
	-- "Read the User's Guide" and a double-click on the same book are one path.
	CeroSecManualMenu.onRead(item, playerObj, volume)
	return true
end

function CeroSecManualMenu.hookDoubleClick()
	if ISInventoryPane == nil then return false end
	if CeroSecManualMenu.vanillaDblClick ~= nil then return false end
	local original = ISInventoryPane.doContextualDblClick
	if original == nil then return false end
	CeroSecManualMenu.vanillaDblClick = original
	ISInventoryPane.doContextualDblClick = function(pane, item)
		if CeroSecManualMenu.doubleClick(pane, item) then return end
		return original(pane, item)
	end
	return true
end

Events.OnFillInventoryObjectContextMenu.Add(CeroSecManualMenu.OnFillInventoryObjectContextMenu)
CeroSecManualMenu.hookDoubleClick()
