require "ISUI/ISInventoryPane"
require "CeroSec/CeroSecMenu"
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

--
-- The book that shipped BEFORE the set, and what happens to a copy still in a save
--
-- CeroSec.Manual was one book, and the set of three replaced it. It is not in BOOKS
-- above, because BOOKS is the set on the SHELF -- the three volumes the loot tables
-- generate and the three the script pins itself against -- and this is not a volume
-- any more. Nothing makes another one.
--
-- It is still declared in items_cerosec.txt, and the whole reasoning for that is
-- written where the declaration is: dropping an item block deletes every copy of it
-- in every container in the world, and so does the engine's own `Obsolete` flag. The
-- only way to keep what a survivor is holding is to keep the type.
--
-- So it CONVERTS. `becomes` is the volume it was: the same book, under the name the
-- set gave it, so a survivor who had one ends up with the User's Guide and not with a
-- fourth item nobody else in the world has.
--
-- WHEN it converts is a choice, and this is the least invasive one there is: at the
-- moment he READS it. Not while the context menu is being built -- a handler that
-- took an item out of a container in the middle of the pane drawing that container is
-- a handler asking for trouble, and this event is fired once per right-click on
-- anything -- and not on a timer sweeping everybody's bags. The option and the
-- double-click both funnel through CeroSecManualMenu.onRead, so there is one place
-- where it happens and one gesture that causes it, and a copy nobody has touched sits
-- in its crate as the book it was printed as.
--
-- The label is the User's Guide's own, which is what it opens. There is deliberately
-- no ContextMenu_CeroSec_ReadManual key any more: a second label for one book would
-- be the menu offering the same volume twice.
CeroSecManualMenu.LEGACY = {
	item = "CeroSec.Manual",
	volume = "user",
	becomes = "CeroSec.ManualUser",
	label = "ContextMenu_CeroSec_ReadUser",
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
	-- And the retired single book, which opens the volume it became. Here rather than
	-- as a fourth row of BOOKS so that the double-click answers it too: this is the one
	-- function both doors ask.
	if fullType == CeroSecManualMenu.LEGACY.item then
		return CeroSecManualMenu.LEGACY.volume
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

-- The retired book, turned into the volume it became. The replacement, or nil when
-- nothing could be done -- in which case the old book is STILL IN HIS BAG, which is
-- the whole reason the order below is what it is.
--
-- Vanilla's own three-call shape for replacing an item a survivor is holding
-- (shared/TimedActions/ISPadlockAction.lua:33-45, shared/Items/OnBreak.lua:508-511):
-- AddItem plus sendAddItemToContainer, then Remove plus sendRemoveItemFromContainer.
-- The two send* calls are what a multiplayer client owes the server for a container it
-- has just changed, and ISPadlockAction makes them unguarded in a shared file, so they
-- are there in a single-player game too; the nil test is for the bench's fake game,
-- like every other engine global this mod reaches for (HaloTextHelper, JoypadState).
--
-- ADD FIRST, remove second. A full bag, an AddItem that answers nil, anything at all
-- going wrong the other way round leaves a survivor who asked to read a book holding
-- neither book -- and the item he lost was the one thing in the world nothing can make
-- another of.
--
-- And the bookmark goes with it: the two are the same volume, so the page he was on is
-- the page he is still on.
function CeroSecManualMenu.convertLegacy(item)
	local container = item:getContainer()
	if container == nil then return nil end
	local fresh = container:AddItem(CeroSecManualMenu.LEGACY.becomes)
	if fresh == nil then return nil end
	if sendAddItemToContainer ~= nil then sendAddItemToContainer(container, fresh) end

	local was = item.getModData and item:getModData() or nil
	local now = fresh.getModData and fresh:getModData() or nil
	if was ~= nil and now ~= nil and was[CeroSecManualUI.PAGE_KEY] ~= nil then
		now[CeroSecManualUI.PAGE_KEY] = was[CeroSecManualUI.PAGE_KEY]
	end

	container:Remove(item)
	if sendRemoveItemFromContainer ~= nil then sendRemoveItemFromContainer(container, item) end
	return fresh
end

-- Opening a volume, and the ONE place the retired book is converted: the menu option
-- and the double-click both come through here, so a survivor cannot reach the reader
-- by a road that leaves him holding the old item.
--
-- A conversion that could not be done is not a refusal to read: he opens the book he
-- has, exactly as he did before, and the next time he tries it will be converted.
function CeroSecManualMenu.onRead(item, playerObj, volumeId)
	if item:getFullType() == CeroSecManualMenu.LEGACY.item then
		item = CeroSecManualMenu.convertLegacy(item) or item
	end
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
			-- event (ISRemoveItemTool.lua:369) -- through CeroSecMenu.addTop, so it
			-- lands above vanilla's Equip and Drop: a book a survivor is holding is
			-- a book to read.
			CeroSecMenu.addTop(context, getText(book.label), copy,
				CeroSecManualMenu.onRead, playerObj, book.volume)
		end
	end

	-- And the retired single book, under the three: it is not one of the set any more,
	-- and a survivor holding both it and the User's Guide is offered the Guide first.
	-- One entry and not two, because it opens the same volume -- and reading it is what
	-- turns it into the Guide (CeroSecManualMenu.LEGACY).
	local legacy = CeroSecManualMenu.findManual(items, CeroSecManualMenu.LEGACY.item)
	if legacy then
		CeroSecMenu.addTop(context, getText(CeroSecManualMenu.LEGACY.label), legacy,
			CeroSecManualMenu.onRead, playerObj, CeroSecManualMenu.LEGACY.volume)
	end

	-- And the phone book, last: it is vanilla's item and not one of the set, so it
	-- goes under the volumes a survivor is carrying rather than in among them.
	local phonebook = CeroSecManualMenu.findManual(items, CeroSecManualMenu.PHONEBOOK.item)
	if phonebook then
		CeroSecMenu.addTop(context, getText(CeroSecManualMenu.PHONEBOOK.label),
			phonebook, CeroSecManualMenu.onLookUp, playerObj)
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
