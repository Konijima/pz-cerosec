require "ISUI/ISTextBox"
require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecMenu"

--
-- Writing on a floppy, from the inventory menu.
--
-- Four disks in a bag are four identical lines in a list, and that is the whole
-- problem: a survivor who keeps his passwords on one and the payroll on another
-- has no way to tell which is which, and neither has the menu that offers to
-- insert one. So he writes on the sticker, the way anybody with four disks and a
-- pen did in 1993.
--
-- The label is ONE string and it lives in ONE place: the item's own name.
--
--   * `item:setName(label)` + `setCustomName(true)` + `syncItemFields()` -- the
--     three calls vanilla's own Rename Bag makes, in that order
--     (ISInventoryPaneContextMenu.lua:2753-2755). The name is a field the engine
--     SAVES with the item (javap -c zombie.inventory.InventoryItem: save() writes
--     `name` through GameWindow.WriteString at 376-379 when it differs from the
--     private originalName, and the customName flag goes with it), so a label
--     written on a disk is still on it after a reload.
--
--   * The machine reads it at the slot, off the item and not off its modData:
--     see the note in SCeroSecSystem's Commands.insertfloppy. There is no
--     per-item modData transmit on InventoryItem in 42.20.4 and setName is
--     synced, so the name is the one reading of the label that is true on both
--     sides of a multiplayer game.
--
--   * `item:getModData().label` is written beside it, because that is the field
--     a disk RECORD owns for it (CeroSecOS.DISK_KEYS) and it is what an eject
--     writes back. It is not a second truth: the slot takes the name.
--
-- The item's modData top level is NOT ours and it is not a closed namespace: the
-- engine writes in it itself. `setCustomName(true)` -- the very call two lines up --
-- rawsets a `customName` key on that same table (javap -c
-- zombie.inventory.InventoryItem, setCustomName(boolean), offsets 5-24). That is
-- what the slot's closed-key rule met in a real save: every disk anybody had
-- written a label on, the diagnostics disk included, was refused at the slot for a
-- key the GAME had put there, the gesture did nothing and no screen said why.
-- The slot now takes the keys a disk owns off the item and judges those alone
-- (ownKeysOf in CeroSecOSDisk), so the label goes on the shell the way vanilla puts
-- one on a bag, and what the game keeps beside it is the game's business.
--
-- What has not changed is where the label is kept: one string, in the item's own
-- name, and a `cerosec` table of ours in that modData would still be a second
-- truth to go stale.
--

CeroSecFloppyMenu = {}

-- Something to write with. Six TAGS, asked of the whole inventory recursively --
-- which is exactly how vanilla decides whether a sheet of paper may be written on
-- (ISInventoryPaneContextMenu.lua:567: ItemTag.WRITE, BLUE_PEN, PEN, PENCIL,
-- RED_PEN and GREEN_PEN, each through containsTagRecurse).
--
-- Tags and not a list of item names, and that is the point of copying vanilla
-- here rather than typing Base.Pen and Base.Pencil: the day the game ships a
-- seventh thing that writes, it ships it with one of these tags on it, and a list
-- of names here would have gone stale without anybody touching this file.
--
-- Built at call time and not at load: ItemTag is the game's own enum
-- (zombie.scripting.objects.ItemTag -- javap confirms WRITE, PEN, PENCIL,
-- RED_PEN, BLUE_PEN and GREEN_PEN are all on it) and reading it into a table at
-- load time would be reading it before the game says it is there.
function CeroSecFloppyMenu.writeTags()
	if ItemTag == nil then return {} end
	return { ItemTag.WRITE, ItemTag.BLUE_PEN, ItemTag.PEN, ItemTag.PENCIL,
		ItemTag.RED_PEN, ItemTag.GREEN_PEN }
end

function CeroSecFloppyMenu.canWrite(playerObj)
	local inv = playerObj:getInventory()
	if inv == nil then return false end
	local tags = CeroSecFloppyMenu.writeTags()
	for i = 1, #tags do
		if tags[i] ~= nil and inv:containsTagRecurse(tags[i]) then return true end
	end
	return false
end

-- What is written on that disk, or nil. The custom name and only the custom name:
-- every unlabelled disk has a name too -- the translated one out of ItemName.json
-- -- and reading THAT as a label would put "3.5 inch Floppy Disk" in the mount
-- listing of every machine in Kentucky.
function CeroSecFloppyMenu.labelOn(item)
	if item == nil or not item:isCustomName() then return nil end
	local name = item:getName()
	if type(name) ~= "string" or name == "" then return nil end
	return name
end

-- Write it on. The label has already been through CeroSecOS.labelOk.
--
-- A label written HERE is handwritten, whatever it says. This is a survivor with a
-- pen, and a pen cannot print: a disk he has just relabelled says so on its tooltip
-- and goes back to the plain sticker in his bag, even if what he wrote on it is
-- word for word a product's own line (CeroSecContent.markLabel).
function CeroSecFloppyMenu.writeLabel(item, label)
	item:setName(label)
	item:setCustomName(true)
	item:syncItemFields()
	local data = item:getModData()
	if data ~= nil then data.label = label end
	CeroSecContent.markLabel(item, false)
end

-- And take it off. Back to the name the disk came with -- which cannot be ASKED
-- of the item: the engine keeps originalName private and getDisplayName() is one
-- getfield on the same field setName writes (javap -c
-- zombie.inventory.InventoryItem), so once a custom name is on there the old one
-- is gone. It is looked up from the full type instead, the way vanilla prints an
-- item's name inside a sentence (getItemNameFromFullType,
-- ISInventoryPaneContextMenu.lua:906). That is the TRANSLATED name out of
-- ItemName.json and not the DisplayName fallback in the script, so a French
-- client gets its own words back and not ours.
function CeroSecFloppyMenu.eraseLabel(item)
	item:setName(getItemNameFromFullType(item:getFullType()))
	item:setCustomName(false)
	item:syncItemFields()
	local data = item:getModData()
	if data ~= nil then data.label = nil end
	-- Nothing written on it is nothing to say about the writing: the tooltip line
	-- and the printed look come off with the label.
	CeroSecContent.markLabel(item, nil)
end

-- The one item out of a menu entry, whether it is an item or a stack of them
-- (CeroSecManualMenu has the same unpacking, and for the same reason: a stack of
-- identical items arrives as one table with an `items` array inside it).
--
-- A stack is a pile of disks the game thinks are interchangeable, and the first of
-- them is the one the pen lands on. Writing on it is what makes it stop being one
-- of a pile.
local function itemOf(entry)
	if entry == nil then return nil end
	if instanceof(entry, "InventoryItem") then return entry end
	if entry.items and entry.items[1] then return entry.items[1] end
	return nil
end

-- The first of our disks in a selection, or nil.
function CeroSecFloppyMenu.floppyIn(items)
	for i = 1, #items do
		local item = itemOf(items[i])
		if item and CeroSec.isFloppyType(item:getFullType()) then return item end
	end
	return nil
end

--
-- The box
--
-- ISTextBox, opened and dispatched exactly the way Rename Bag opens and
-- dispatches it (ISInventoryPaneContextMenu.lua:2643-2650 and :2746): new with
-- the title, the text already in the box, a nil target and the handler, then
-- initialise, then addToUIManager, then the joypad focus. ISTextBox calls
-- `onclick(target, button, param1, param2, ...)` (ISTextBox.lua:134), so with a
-- nil target the handler's first argument is that nil and the two after the
-- button are ours.
--
-- The ceiling is checked in the OK handler and not through
-- ISTextBox:setValidateFunction, because that is where vanilla checks it
-- (:2748-2762, MAXIMUM_RENAME_LENGTH, with a HaloTextHelper line when it is too
-- long) -- and because two gates on one rule is two places for the rule to drift.
--

function CeroSecFloppyMenu.onLabel(item, playerObj)
	local playerNum = playerObj:getPlayerNum()
	local modal = ISTextBox:new(0, 0, 280, 180,
		getText("IGUI_CeroSec_LabelFloppy", CeroSecOS.LABEL_MAX),
		CeroSecFloppyMenu.labelOn(item) or "", nil,
		CeroSecFloppyMenu.onLabelClick, playerNum, playerObj, item)
	modal:initialise()
	modal:addToUIManager()
	if JoypadState ~= nil and JoypadState.players[playerNum + 1] then
		setJoypadFocus(playerNum, modal)
	end
	return modal
end

function CeroSecFloppyMenu.onLabelClick(_, button, playerObj, item)
	if button.internal ~= "OK" then return end
	local typed = button.parent.entry:getText()
	-- Nothing typed is a survivor who changed his mind, and it is not an erase:
	-- taking a label off has its own entry on the menu, and a box that erased on an
	-- empty OK would be a box that erases a label somebody opened to READ.
	if typed == nil or typed == "" then return end
	if not CeroSecOS.labelOk(typed) then
		-- One refusal and one sentence for both of its reasons -- too long, or a
		-- character a label may not carry -- because the sentence has to say what IS
		-- allowed either way, and a survivor who has just been refused needs that and
		-- not a diagnosis.
		if HaloTextHelper ~= nil then
			HaloTextHelper.addBadText(playerObj,
				getText("IGUI_CeroSec_LabelBad", CeroSecOS.LABEL_MAX))
		end
		return
	end
	CeroSecFloppyMenu.writeLabel(item, typed)
end

function CeroSecFloppyMenu.onErase(item, playerObj)
	CeroSecFloppyMenu.eraseLabel(item)
end

--
-- The menu
--
-- The event vanilla put there for mods to add to this menu with, fired with
-- (playerNum, context, items) -- the same one the manual's Read entries come
-- through (ISInventoryPaneContextMenu.lua:935).
--
-- Nothing to write with is not an entry at all, rather than a greyed one: a
-- survivor with no pen on him has no business reading about labelling, which is
-- the same rule the drive's menu keeps for a player carrying no disk
-- (CeroSecContextMenu.addDrive).
--
-- A labelled disk gets TWO entries, and the first of them is named for what it
-- does to a disk that already has writing on it: you are not labelling it, you are
-- changing what it says.
--
function CeroSecFloppyMenu.OnFillInventoryObjectContextMenu(playerNum, context, items)
	local playerObj = getSpecificPlayer(playerNum)
	if not playerObj then return end

	local disk = CeroSecFloppyMenu.floppyIn(items)
	if disk == nil then return end
	if not CeroSecFloppyMenu.canWrite(playerObj) then return end

	if CeroSecFloppyMenu.labelOn(disk) == nil then
		CeroSecMenu.addTop(context, getText("ContextMenu_CeroSec_LabelFloppy"), disk,
			CeroSecFloppyMenu.onLabel, playerObj)
	else
		CeroSecMenu.addTop(context, getText("ContextMenu_CeroSec_RelabelFloppy"), disk,
			CeroSecFloppyMenu.onLabel, playerObj)
		CeroSecMenu.addTop(context, getText("ContextMenu_CeroSec_EraseLabel"), disk,
			CeroSecFloppyMenu.onErase, playerObj)
	end
end

Events.OnFillInventoryObjectContextMenu.Add(CeroSecFloppyMenu.OnFillInventoryObjectContextMenu)
