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
-- There are three books now, so there may be three options: each volume in the
-- selection gets its own, named after itself. A menu offering "Read the manual"
-- three times over would be a menu that cannot be used.
--

CeroSecManualMenu = {}

-- The set, in the order it is printed on the shelf, and the order the menu
-- lists it in: an ordered list and not a map keyed by item, because pairs()
-- would shuffle the entries from one right-click to the next.
--
-- CeroSec.Manual is the book that shipped BEFORE the set did. It is still
-- defined, because it is in saves, and it opens volume one -- the volume it
-- became. It is last here so that a survivor holding both the old book and the
-- new User's Guide is offered the new one first.
CeroSecManualMenu.BOOKS = {
	{ item = "CeroSec.ManualUser", volume = "user",
		label = "ContextMenu_CeroSec_ReadUser" },
	{ item = "CeroSec.ManualAdmin", volume = "admin",
		label = "ContextMenu_CeroSec_ReadAdmin" },
	{ item = "CeroSec.ManualProgrammer", volume = "programmer",
		label = "ContextMenu_CeroSec_ReadProgrammer" },
	{ item = "CeroSec.Manual", volume = "user",
		label = "ContextMenu_CeroSec_ReadManual" },
}

-- The one item out of a menu entry, whether it is an item or a stack of them.
local function itemOf(entry)
	if entry == nil then return nil end
	if instanceof(entry, "InventoryItem") then return entry end
	if entry.items and entry.items[1] then return entry.items[1] end
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

Events.OnFillInventoryObjectContextMenu.Add(CeroSecManualMenu.OnFillInventoryObjectContextMenu)
