if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecModules"

--
-- WHEN A FIXTURE LEAVES THE WORLD, ITS MODULES COME OFF
--
-- A survivor unplugs the television with a tuner control in it and carries it to
-- the next house; he takes a sledgehammer to the office door with a strike in it;
-- a zombie breaks that door down while he is out. The box was real hardware a
-- minute ago and it is real hardware now, so it is on the floor -- in the
-- doorway, beside the doorknob and the hinges the door itself drops
-- (IsoDoor.destroy, offsets 140-226).
--
-- It used to be nowhere at all. A module is written into the FIXTURE's own
-- modData (CeroSecModules, and modules-proofs.md, 1): the fixture went and the
-- table went with it, which made the one gesture a survivor cannot undo the one
-- that cost him the boxes he had climbed up to fit. `uninstallmodule` gave a
-- module back for the only way off anybody had thought about -- a screwdriver and
-- a survivor who meant it -- and there are eight other ways.
--
-- ONE RULE, ONE PLACE: when a fixture carrying CeroSec modules leaves the world,
-- every module on it becomes an item on the square it was standing on. Pre-fitted
-- ones included, for the reason `uninstallmodule` already includes them -- a
-- relay the 1991 walk screwed to a switch plate is a relay (DEVICES.md, "nothing
-- about such a module is special").
--
-- THE HOOK IS THE ENGINE'S OWN, AND IT IS ONE HOOK
--
-- Events.OnObjectAboutToBeRemoved, which fires with the object still ON its
-- square: IsoGridSquare.RemoveTileObject(IsoObject, boolean) triggers it at
-- offset 177 and then throws IllegalArgumentException at 195 if the listener has
-- taken the object away ("OnObjectAboutToBeRemoved not allowed to remove the
-- object"), so the square, the class and the modData are all still there to read
-- -- and taking the object off the square ourselves is a crash and not a
-- shortcut.
--
-- Every way a fixture can leave the world ends in one of exactly two Java calls,
-- and both of them trigger it on the side this file runs on:
--
--   IsoGridSquare.RemoveTileObject(IsoObject, boolean)      trigger at 177
--   RemoveItemFromSquarePacket.removeItemFromMap(...)       trigger at 336
--
-- and the dispatch between them is IsoGridSquare.transmitRemoveItemFromSquare(
-- IsoObject, boolean), which is what nearly every path above calls:
--
--   on a CLIENT   RemoveItemFromSquarePacket out (offsets 44-85) and then
--                 RemoveTileObject(obj, true) at 194 -- so a client fires it for
--                 its own screen, and the SERVER fires it when the packet lands
--                 (processServer -> removeItemFromMap, trigger at 336)
--   on a SERVER   GameServer.RemoveItemFromMap(obj) at 189, which broadcasts and
--                 then calls that same static itself (GameServer.RemoveItemFrom-
--                 Map, offsets 30-55) -- trigger at 336
--   on NEITHER    RemoveTileObject(obj, true) at 194, which is singleplayer
--
-- and RemoveTileObject(IsoObject), the one-argument one, hands a loaded chunk to
-- IsoObjectUtils.safelyRemoveTileObjectFromSquare (offsets 0-50), which comes
-- back to RemoveTileObject(obj, false) once per PART of a multi-tile object
-- (offsets 84-89 and 136-142). So the trigger is per object, always, on the side
-- that owns the world.
--
-- THE NINE PATHS, and what each one really does:
--
--   a television, a radio set, an oven, a washer, a lamp -- any movable
--     ISMoveableSpriteProps:pickUpMoveableInternal:1406-1407 -- triggerEvent
--     ITSELF ("Hack for RainCollectorBarrel, Trap, etc") and then
--     transmitRemoveItemFromSquare
--   a window picked up
--     the same function, :1384-1386: transmitRemoveItemFromSquare and NO Lua
--     trigger, so the Java one is the whole of it
--   a window SMASHED instead
--     :1289-1291 sets windowGotSmashed and the branch at :1385 is then skipped:
--     the object STAYS on the square. Nothing fires and nothing should -- a
--     smashed window is a window with a contact on it, and the contact reads
--     `smashed` (DEVICES.md)
--   a map door destroyed, by a zombie or a sledgehammer
--     IsoDoor.destroy(): `destroyed = true` and transmitRemoveItemFromSquare at
--     227-240 (the garage-door leaf takes the same pair at 23-36)
--   a player-built door or wall destroyed
--     IsoThumpable.destroy(): OnDestroyIsoThumpable at 120-125 and
--     transmitRemoveItemFromSquare at 146-154. OnObjectAboutToBeRemoved is the
--     EARLIER of the two hooks whenever ISBuildingObject.onDestroy removes the
--     object first, which is what vanilla's own trap system relies on
--     (STrapSystem.lua:106-110)
--   a sledgehammer, through the menu
--     ISDestroyStuffAction:complete:276-280 -- sledgeDestroy(obj) on a client,
--     transmitRemoveItemFromSquare otherwise
--   dismantled / "Disassemble"
--     ISMoveableSpriteProps:scrapObjectInternal:3517-3519 --
--     transmitRemoveItemFromSquare on a client, transmitRemoveItemFromSquare-
--     OnClients on the server, and square:RemoveTileObject(object) on BOTH
--   a curtain taken down
--     ISRemoveSheetAction -> IsoCurtain.removeSheet(IsoGameCharacter), offset 5.
--     A DOOR's sheet is not an object at all -- it is two fields on the door
--     (CeroSecModules.doorHasCurtain) -- so the door stays and keeps its motor
--   a generator picked up
--     ISTakeGenerator:complete:53 -> IsoGenerator.remove(), offsets 8-16
--
-- and the tenth is the one that must NOT fire: a chunk unloading. IsoChunk never
-- calls RemoveTileObject; what it fires when it lets its squares go is
-- "ReuseGridsquare" (IsoChunk.doReuseGridsquares:3044). A fixture the streamer
-- has taken away has not left the world and does not shed anything.
--
-- WHICH IS WHY IT IS PAID ONCE AND NOT ONCE PER EVENT
--
-- Singleplayer fires it TWICE for one pickup, and that is not a corner: the Lua
-- triggerEvent at :1406 and the Java one inside the transmitRemoveItemFromSquare
-- on the line after it are two firings of the same removal, and on a box that is
-- neither client nor server both of them happen. So "pay" has to mean something a
-- second firing can see, and it does: the keys are CLEARED as each module is paid
-- (CeroSecModules.setOn), so the second event reads an empty fixture and hands
-- nothing over. A pickup, a placement and a second pickup pay once each for the
-- same reason -- vanilla carries only `movableData` from an object's modData into
-- the moveable item (ISMoveableSpriteProps:1298-1299) and nothing of ours rides
-- along, so the fixture that goes back down is bare. See DEVICES.md.
--
-- THE ITEM FIRST AND THE KEY AFTER, in that order, which is the floppy drive's
-- rule and `installmodule`'s: a survivor must never be charged for a module that
-- was not made. IsoGridSquare.AddWorldInventoryItem(String, float, float, float)
-- answers null for a type InventoryItemFactory.CreateItem does not know (offsets
-- 0-12 of the six-argument one), and a null there leaves the box screwed on.
--
-- AND IT IS THE FLOOR, NEVER A BAG, which is a decision and not a shortcut. The
-- event carries the object and nothing else -- LuaEventManager.triggerEvent(
-- String, Object) is the two-argument one at both trigger sites -- so there is no
-- character to hand anything to, and there is no character on most of these paths
-- at all: a door a zombie broke down was nobody's gesture. One rule for the nine
-- of them is better than a bag for two and a floor for seven, and it is where
-- vanilla puts a destroyed door's own parts.
--

SCeroSecFixtures = SCeroSecFixtures or {}

-- Every module on this object, onto the square it is standing on. The number
-- paid, which is 0 for the object this handler is called with nearly every time.
--
-- The square is fetched once and only when there is something to drop: this runs
-- for every object the world takes away, which is every picked-up item and every
-- cleared tuft of grass as well as the nine paths above.
function SCeroSecFixtures.dropModules(object)
	if object == nil then return 0 end
	-- The one reader of what is screwed to a fixture, so an older save's table is
	-- walked up here and a table a LATER build wrote reads as empty -- which means
	-- a fixture whose ids this build cannot name sheds nothing and keeps them all,
	-- exactly as every other question about it answers (CeroSecModules.migrate).
	--
	-- ownedBy and setOwn, never installedOn and setOn: for one leaf of a double or a
	-- garage door those read and write the WHOLE gate, and a map double door has its
	-- leaves 2 and 3 removed and made again at every toggle -- which would refund the
	-- anchor's boxes each time the door opened.
	local fitted = CeroSecModules.ownedBy(object)
	local square = nil
	local paid = 0

	for i = 1, #CeroSecModules.LIST do
		local module = CeroSecModules.LIST[i]
		if fitted[module.id] then
			if square == nil then
				square = object:getSquare()
				-- Off its square already, which the trigger sites say cannot
				-- happen and which is not worth guessing at either way: there is
				-- no floor to put the box on, so nothing is taken from the
				-- fixture. The modData goes with the object, as it always did.
				if square == nil then return 0 end
			end
			-- At 0, 0, 0 on the tile, which is where a door drops its own doorknob,
			-- its planks, its hinges and its sheet (IsoDoor.destroy, offsets
			-- 120-226 -- fconst_0 three times, every time). The STRING overload, so
			-- the engine makes the item the way inv:AddItem does in
			-- uninstallmodule, and it transmits itself on a server: offsets 105-118
			-- of AddWorldInventoryItem(String, float, float, float, boolean,
			-- boolean) call IsoWorldInventoryObject.transmitCompleteItemToClients()
			-- under GameServer.server, which is why there is no send beside this
			-- line where uninstallmodule has a sendAddItemToContainer.
			local item = square:AddWorldInventoryItem(module.item, 0, 0, 0)
			if item == nil then
				-- Nothing was given, so nothing is taken: the box stays screwed to
				-- a fixture that is leaving, which is what used to happen to all
				-- of them and is better than eating it.
				CeroSec.log(CeroSec.LOG_WARN, "the floor would not take the " ..
					module.id .. " off the fixture at " .. square:getX() .. "," ..
					square:getY() .. "," .. square:getZ())
			else
				CeroSecModules.setOwn(object, module.id, false)
				paid = paid + 1
			end
		end
	end

	if paid > 0 then
		-- What every machine in that building can see just changed, and which
		-- machines those are is not a question this file can answer without the
		-- walk the cache exists to avoid -- so all of it goes, which is what
		-- installmodule and uninstallmodule do for the same reason. `alive` is
		-- what stops a device being WORKED after its fixture went; this is what
		-- stops it being LISTED for the rest of the second.
		CeroSecDevices.invalidate()
		CeroSec.log(paid .. " module(s) came off the fixture leaving the world at " ..
			square:getX() .. "," .. square:getY() .. "," .. square:getZ())
	end
	return paid
end

-- AND THE CABLE, for the reason the modules come off: it was thirty tiles of real
-- wire an hour ago and the fixture it was run to has just left the world. The
-- number of tiles paid back, which is 0 for nearly every object this is called with.
--
-- ONE END IS ALL THIS FILE WRITES. The machine at the other end keeps a square on
-- its list and finds nothing there on its next walk, which is the moment that entry
-- was always going to be dropped -- the cable is on the fixture and the fixture is
-- the thing that went (the link walk in SCeroSecDevices). Reaching for every machine
-- named in the list to correct it here would be the walk the pair of lists exists to
-- avoid, and it would be a walk done from inside an engine hook that is not allowed
-- to touch the world.
--
-- The tiles are paid ONE ITEM A TILE, on the square, exactly as the boxes are: the
-- refund for a cable is cable. A reel is not an item in this game -- Base.Electric-
-- Wire is one wire -- so twelve tiles is twelve of them, which is the same pile the
-- survivor would have dropped there taking it down himself.
function SCeroSecFixtures.dropLinks(object)
	if object == nil then return 0 end
	local links = CeroSecModules.ownLinksOn(object)
	if #links == 0 then return 0 end
	local square = object:getSquare()
	-- dropModules' own reason: no floor, no refund, and the modData goes with the
	-- object as it always did.
	if square == nil then return 0 end

	local paid = 0
	for i = 1, #links do
		local entry = links[i]
		local given = 0
		for _ = 1, entry.wire do
			if square:AddWorldInventoryItem(CeroSecModules.WIRE, 0, 0, 0) == nil then break end
			given = given + 1
		end
		if given < entry.wire then
			-- Part of it went onto the floor and the rest would not. The cable is cut
			-- anyway: what is on the floor is his, and a cable left on a fixture that
			-- is leaving the world is a cable nobody can ever cut.
			CeroSec.log(CeroSec.LOG_WARN, "the floor took " .. given .. " of " ..
				entry.wire .. " tiles of wire off the fixture at " .. square:getX() ..
				"," .. square:getY() .. "," .. square:getZ())
		end
		if CeroSecModules.unlinkOwn(object, entry.x, entry.y, entry.z) ~= nil then
			paid = paid + given
		end
	end

	if paid > 0 then
		-- dropModules' own reason, and the stronger half of it: what a cable reaches
		-- is a machine that is not in this building at all.
		CeroSecDevices.invalidate()
		CeroSec.log(paid .. " tile(s) of wire came off the fixture leaving the world at "
			.. square:getX() .. "," .. square:getY() .. "," .. square:getZ())
	end
	return paid
end

Events.OnObjectAboutToBeRemoved.Add(function(isoObject)
	-- Both, and in either order: whichever of the two writes last is the one that
	-- finds the table empty and takes it away (CeroSecModules.isBare). The boxes go
	-- first because they are what a survivor came for.
	SCeroSecFixtures.dropModules(isoObject)
	SCeroSecFixtures.dropLinks(isoObject)
end)
