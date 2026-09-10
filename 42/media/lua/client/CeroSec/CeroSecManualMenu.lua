require "CeroSec/CeroSecManualUI"

--
-- "Read the manual", on the inventory menu.
--
-- The event is the one vanilla put there for exactly this
-- (ISInventoryPaneContextMenu.lua:933-935: "use the event (as you would
-- 'OnTick' etc) to add items to context menu without mod conflicts"), and it is
-- fired with (playerNum, context, items).
--
-- `items` is not a list of InventoryItems: a stack of identical items comes
-- through as one table with an `items` array inside it, which is why every
-- vanilla reader of this event unpacks both shapes
-- (ISRemoveItemTool.lua:347-357). One manual is enough -- they are all the same
-- book -- so the first one found is the one the option opens.
--

CeroSecManualMenu = {}

CeroSecManualMenu.ITEM = "CeroSec.Manual"

-- The one item out of a menu entry, whether it is an item or a stack of them.
local function itemOf(entry)
	if entry == nil then return nil end
	if instanceof(entry, "InventoryItem") then return entry end
	if entry.items and entry.items[1] then return entry.items[1] end
	return nil
end

function CeroSecManualMenu.findManual(items)
	for i = 1, #items do
		local item = itemOf(items[i])
		if item and item:getFullType() == CeroSecManualMenu.ITEM then return item end
	end
	return nil
end

function CeroSecManualMenu.onRead(item, playerObj)
	CeroSecManualUI.open(playerObj, item)
end

function CeroSecManualMenu.OnFillInventoryObjectContextMenu(playerNum, context, items)
	local playerObj = getSpecificPlayer(playerNum)
	if not playerObj then return end

	local manual = CeroSecManualMenu.findManual(items)
	if not manual then return end

	-- addOption(label, target, callback, ...) calls callback(target, ...), the
	-- way the vanilla debug menu adds its own option to this same event
	-- (ISRemoveItemTool.lua:369).
	context:addOption(getText("ContextMenu_CeroSec_ReadManual"), manual,
		CeroSecManualMenu.onRead, playerObj)
end

Events.OnFillInventoryObjectContextMenu.Add(CeroSecManualMenu.OnFillInventoryObjectContextMenu)
