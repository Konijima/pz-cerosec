if isClient() then return end

require "CeroSec/CeroSecContent"
require "CeroSec/CeroSecDefs"
require "CeroSec/SCeroSecNet"

--
-- WHERE THE PASSWORDS ARE FOUND
--
-- A prefilled machine in an office has a root password on it, and the whole point
-- of that is that a survivor can get in. So the password is somewhere in the
-- world, and it is in the two places a password was in 1993:
--
-- AND ONLY WHERE THERE IS A MACHINE. Both papers are about a computer, so neither
-- is written for a premises no computer stands in -- see IS THERE A MACHINE IN HERE
-- AT ALL below, which is the report a house with no computer and a password in its
-- drawer produced.
--
--   * ON A PAPER IN THE DESK. One per premises, at most, in a desk, a counter, a
--     filing cabinet or a drawer of that same premises. It names ROOT, which is
--     the key to the whole machine: it is called `Sticky note (root)` and it reads
--     `Sticky note: root / falcon12`.
--   * IN A DEAD MAN'S POCKET. About one zombie in twenty, killed inside a
--     premises, carries his OWN login on a paper -- never root's, which he was
--     never given: `Sticky note (rmiller)`, reading `Note: rmiller / thunder07`.
--     A corpse gives a foothold; the office gives the keys.
--
-- NOTHING IS EVER DROPPED ON THE FLOOR. A note on the ground is a note under a
-- bookshelf that nobody will ever look at.
--
-- HOW THE NOTE AND THE MACHINE AGREE, and this is the whole design: they do not
-- talk to each other. Both DERIVE the password out of the save's own secret and
-- the premises, by the same two calls (CeroSecContent.rootKey and
-- CeroSecContent.accountPassword), so there is no moment where one has been
-- written and the other has not. The note can be found before anybody has ever
-- switched the machine on -- and when somebody does, it comes up with the very
-- password that is already in his pocket.
--
-- And it is the PREMISES and not the building, by the one rule there is
-- (CeroSecNet.premisesOfSquare): a shop in a mall is its own premises, with its own
-- machine, its own note and its own staff, exactly as it is its own telephone line.
--
-- THE HOOK, proved at the bytecode level on projectzomboid.jar 42.20.4. Every
-- claim here was re-read against the jar after a review found the first version of
-- this comment wrong in the one way that mattered -- see THE THIRD ARGUMENT below.
--
--   Events.OnFillContainer carries THREE arguments -- roomName, containerType,
--   and a container -- which is what vanilla's own handler takes
--   (media/lua/server/Items/LootLog.lua:7, registered at :34).
--
--   zombie.inventory.ItemPickerJava fires it from TEN places in FOUR methods, and
--   they do not all mean the same thing:
--
--     fillContainerInternal      the room's own containers (offsets 657, 704, 766)
--                                and a body's pockets (offset 430)
--     doRollItemInternal         a BAG that was rolled into a container, twice:
--     rollContainerItemInternal  room names "Zombie Bag" (261, 320) and
--                                "Container" (1207, 1373, 954, 1103)
--
--   THE THIRD ARGUMENT IS NOT ALWAYS AN ItemContainer. At offset 1207 it is
--   `ItemPickerContainer.bags` -- a zombie.inventory.ItemPickerJava$ItemPickerContainer,
--   which is a distribution table and not a container at all -- while at 1373 it is
--   a real one (InventoryContainer.getItemContainer). So this handler asks
--   `instanceof(container, "ItemContainer")` before it touches the thing, and that
--   is not belt and braces: reading a field off a Java object Kahlua has no class
--   metatable for is not guaranteed to answer nil quietly.
--
--   THE SQUARE. fillContainerInternal returns at once when the container has no
--   source grid (`getSourceGrid()` at offset 25, `ifnull` to the return at 42), so
--   a container IT tells us about always has one. The bag paths make no such
--   promise, which is the second reason the nil test below is a real test.
--
--   A ZOMBIE'S INVENTORY GOES DOWN THE SAME EVENT. When the container's type is
--   "inventorymale" or "inventoryfemale" (the two ldc_w at offsets 47 and 60), it
--   fires OnFillContainer with the room name "Zombie" (the ldc_w at 433) and
--   RETURNS at 442 -- so a body never sees the room distributions, and "Zombie" in
--   the FIRST argument is how this handler tells a pocket from a drawer. It is the
--   first argument and never the second on purpose: at offsets 106-133 a container
--   whose parent is an IsoDeadBody has its type replaced by the body's
--   getOutfitName(), so the second argument for a CORPSE is an outfit name and for
--   a walking zombie is "inventorymale" -- two different strings for one thing,
--   and neither of them is what this keys on. A skeleton is refused before the
--   event (IsoDeadBody.isSkeleton at 93-99), so a note is never on a pile of bones
--   nobody would search.
--
-- WHY NOT Events.OnZombieDead. It exists (IsoZombie.onKilled triggers it) and it
-- would have worked, but it is the wrong moment: a zombie's inventory is filled
-- once, when the zombie is made, and a hook on death would put a paper in a pocket
-- that had already been emptied by a survivor who searched the body a second time.
-- The fill event is the moment the game itself decides what is in a pocket.
--

CeroSecNotes = {}

--
-- A NOTE IS A SHEET OF THE GAME'S OWN PAPER
--
-- It was CeroSec.StickyNote, a base:normal item whose only content was its name,
-- and a player asked what he was supposed to do with it: it could not be read, it
-- could not be written on, it would not burn. A paper that does none of the three
-- is not a paper. So a note is now Base.SheetPaper2, vanilla's writable sheet
-- (media/scripts/generated/items/literature.txt:1831-1843), and it does all three
-- because the game already does them for its own paper. Base.SheetPaper is not an
-- item: 1831 is the only SheetPaper block in the whole of scripts/.
--
--     item SheetPaper2 { ItemType = base:literature, Weight = 0.1,
--                        Icon = Paper, CanBeWrite = true, PageToWrite = 1,
--                        StaticModel = SheetOfPaper, ... ReadType = newspaper }
--
--   READ AND WRITE come from those two keys and from nothing else.
--   ISInventoryPaneContextMenu picks the item up at :245 -- getCategory() ==
--   "Literature" and canBeWrite() -- and puts the write/read modal on the menu at
--   :566-577, offering WRITE when the survivor is carrying a pen
--   (containsTagRecurse over WRITE/PEN/PENCIL/BLUE_PEN/RED_PEN/GREEN_PEN at :567)
--   and READ when he is not. getCategory() is the Literature class's own answer
--   (javap -c zombie.inventory.types.Literature, getCategory: the ldc "Literature"
--   at offset 12 when mainCategory is null), so the base:literature ItemType IS
--   the qualification. And a writable Literature is deliberately kept OUT of the
--   hours-long vanilla Read action -- :242 clears isAllLiterature for any item
--   whose canBeWrite() is true -- which is the very objection the old base:normal
--   block was written against, answered by the engine itself.
--
--   ERASING AND REWRITING need no eraser item and no rule of ours: the modal has
--   a trash button that blanks the page (ISUIWriteJournal.onClick, "DELETEPAGE")
--   and the survivor types over it. The one thing that could refuse him is a LOCK
--   -- getLockedBy() ~= his username at :568 -- and nothing here ever locks one,
--   so a found note is a note he can rewrite. That is the point.
--
--   FUEL comes free with the category too. ISCampingMenu.isValidFuel and
--   isValidTinder read campingFuelCategory / campingLightFireCategory by
--   item:getCategory(), and both tables carry Literature = 15/60 hours
--   (media/lua/server/Camping/camping_fuel.lua). SheetPaper2 is named in the type
--   tables besides. So a note lights a campfire and feeds a fireplace exactly as
--   any sheet of paper does.
--
-- AND NOTHING IS DELETED. The CeroSec.StickyNote block stays in
-- common/media/scripts/items_cerosec.txt exactly as it was, unobsoleted: notes
-- already lying in somebody's save are still that type and still carry their
-- password on their name, which is all they ever carried. Changing that block's
-- ItemType instead of leaving it would have been the one unrecoverable move --
-- javap -p -c zombie.inventory.InventoryItem, loadItem(ByteBuffer,int,boolean,
-- InventoryItem): the record is length-prefixed (getInt at 1, the reposition to
-- start+length at 197-206), so the stream would survive, but Literature.load
-- would read a BitHeader and a page count out of bytes a base:normal item never
-- wrote, and the load() call is wrapped in `catch (Exception)` at 64-82 which
-- nulls the item -- the saved note dropped, one line in the console. A player's
-- paper is not something to bet on a byte pattern.
CeroSecNotes.ITEM = "Base.SheetPaper2"

-- What is WRITTEN on the page: the login and the password, in the two shapes that
-- say which kind of note it is in their first word -- one was stuck to a desk, the
-- other was folded in a pocket.
CeroSecNotes.ROOT_FORM = "Sticky note: %s / %s"
CeroSecNotes.USER_FORM = "Note: %s / %s"

-- What the INVENTORY ROW says, which is now a different thing from what the paper
-- says. The name names the login and stops there, so that finding out the password
-- is a gesture -- opening the note and reading it -- and not a line a survivor
-- skims past in a list. One shape for both papers: which of the two it is, the
-- page says, and "root" in the name already says the only part a player cares
-- about at a glance.
CeroSecNotes.NAME_FORM = "Sticky note (%s)"

-- And it still LOOKS like our sticky note although it is vanilla's sheet, per
-- item and through the engine's own path. javap -p -c
-- zombie.inventory.InventoryItem, getTexture(): hasModData at 1, getModData at 13,
-- ldc_w "customInventoryIcon" at 16, rawget at 19, and Texture.getSharedTexture on
-- it at 41 when it is a String -- anything else, and a name that resolves to
-- nothing, falls back to the script's own texture (the getfield at 33, 51). That
-- is on InventoryItem and Literature does not override it, so it is true of
-- vanilla's paper exactly as it is true of our floppies (see
-- CeroSecContent.markLabel). The key is the ENGINE's, on the engine's table,
-- beside the `customName` setCustomName writes there.
CeroSecNotes.ICON = "Item_CeroSecStickyNote"

-- The room name the engine uses for a body's pockets. Not a room.
CeroSecNotes.ZOMBIE_ROOM = "Zombie"

-- Where a note left on a desk may be. The names are vanilla's own container
-- types, which is what the second argument of the event carries: they are the
-- second-level keys of media/lua/server/Items/Distributions.lua, and these seven
-- are the ones somebody sat at or kept his papers in. NOT a fridge, not a crate,
-- not a bin: a password goes in the drawer you open every morning.
CeroSecNotes.DESK_TYPES = {
	desk = true,
	schooldesk = true,
	counter = true,
	filingcabinet = true,
	sidetable = true,
	locker = true,
	dresser = true,
}

-- One zombie in twenty. A number and not a feeling: a survivor who clears an
-- office of thirty dead should find one or two papers and not a handful, because a
-- paper that is on every body is a paper nobody reads.
CeroSecNotes.ZOMBIE_ODDS = 20

--
-- The bookkeeping
--
-- Which premises have already had their desk note. One per premises at most, or a
-- mall with forty desks in it is forty copies of one password.
--
-- It lives on the SYSTEM and is saved with the save (SCeroSecSystem:initSystem
-- names it in setModDataKeys), because the containers of one premises are filled
-- over many sessions -- a survivor opens the second drawer a week later -- and a
-- table that lived in memory would put a second note in it.
--
-- Keyed by the premises' own two bytes, which is the same key everything else
-- about a premises is keyed on.
--
function CeroSecNotes.premisesMark(system, b1, b2)
	if type(system.notes) ~= "table" then system.notes = {} end
	return system.notes, CeroSecContent.key(b1, b2)
end

function CeroSecNotes.hasNote(system, b1, b2)
	local notes, key = CeroSecNotes.premisesMark(system, b1, b2)
	return notes[key] == true
end

function CeroSecNotes.markNote(system, b1, b2)
	local notes, key = CeroSecNotes.premisesMark(system, b1, b2)
	notes[key] = true
end

--
-- IS THERE A MACHINE IN HERE AT ALL
--
-- A report off the glass: a sticky note with root's password was found in a house
-- that has no computer in it anywhere. The two notes above were written for any
-- premises whose PROFILE has a root password, and a house with a study in it is
-- such a premises (CeroSecContent.profileFor reads the building's rooms, and
-- `office` is 3977 rooms of the county) -- so a paper named the password of a
-- machine that does not exist, which is the one thing the shared derivation was
-- built to make impossible. A password is a thing about a MACHINE, so a note is
-- written only where a machine STANDS.
--
-- IT IS DECIDED AT FILL TIME FROM THE WORLD and cannot be decided anywhere else:
-- the profile is derived from the map every time it is needed and nothing about a
-- premises' machines is in the save. So the premises' rooms are walked, and their
-- live squares, and the objects on them.
--
-- BY THE SPRITE, and not by asking the GlobalObject system whether it holds a
-- machine here. Adoption is a chunk event -- MapObjects.OnLoadWithSprite ->
-- SCeroSecSystem:loadIsoObject, the registrations at the foot of
-- SCeroSecSystem.lua -- and within ONE chunk the order is in our favour: javap on
-- zombie.iso.IsoChunk.doLoadGridsquare has MapObjects.newGridSquare at offset 859
-- and loadGridSquare at 864, inside the loop over the chunk's squares, while the
-- loot fill is a LATER loop entirely (offsets 1350-1408, loadGridSquareIfNeeded ->
-- LoadGridsquarePerformanceWorkaround.LoadGridsquare, which is what fires
-- OnFillContainer). But a premises is not one chunk. The drawer's chunk comes in
-- while the room the computer stands in is still away, and then there is no
-- GlobalObject for that computer and never has been. The sprite is the very test
-- the registration itself keys on (CeroSec.isComputerSprite, over SPRITES_OFF and
-- SPRITES_ON), it is true of a machine nobody has ever switched on, and it needs
-- nothing adopted.
--
-- THREE ANSWERS AND NOT TWO: yes, no, and "the world cannot say" -- a room whose
-- chunks are away answers nothing about what stands in it, and neither does a walk
-- that hit its ceiling. Cannot-say writes no note AND LEAVES THE PREMISES
-- UNMARKED, so the next container filled in it asks the question again, which is
-- exactly what a full drawer already does.
--

-- How many squares one question may walk. A house is a few hundred and a mall
-- tenancy is one shop, but the whole-building branch of a school or a hospital is
-- thousands of squares -- and this is asked for containers of a chunk load, not
-- once. Past the ceiling the answer is cannot-say, which costs a re-ask on the
-- next container and never a paper for a machine that is not there.
CeroSecNotes.SQUARES_MAX = 4096

-- The premises a computer has already been SEEN in, for the session. Derived from
-- the map and nothing else, exactly as the tenancy cache is (CeroSecNet's, and
-- keyed the same way), so it is never saved and losing it costs one walk.
--
-- Only `true` is remembered. A premises with no computer in it today may have one
-- tomorrow -- a survivor puts one down, or the room it is in finally streams in --
-- and a remembered `no` would be a premises that can never carry a paper again.
local computerSeen = {}

-- Forget it. For a bench, and for a world being unloaded: a table keyed on
-- premises that survived into another save would be answering about a county that
-- is not there any more (CeroSecNet.forgetTenancies is the same rule).
function CeroSecNotes.forgetComputers()
	computerSeen = {}
end

-- THE PREMISES' ROOMS, as the plain tables that carry their RoomDef -- the same
-- list and the same two cached answers the WIRING walks (SCeroSecAuto's
-- premisesRoomsOf and CeroSecDevices.fixturesInRooms), so a mall costs here what
-- it costs there: the tenancy's own rooms for a premises that IS a tenancy, and
-- the building's rooms for everything else, out of the cache either way.
--
-- nil for a def that will not list its rooms, which is a building nothing can be
-- asked about.
local function premisesRoomsOf(square, kind)
	local building = square:getBuilding()
	if building == nil then return nil end
	local def = building:getDef()
	if def == nil then return nil end
	if kind == CeroSecOS.PREMISES_ROOM then
		local groups = CeroSecNet.tenanciesOf(def)
		if #groups < 2 then return nil end
		return CeroSecNet.tenantOfRoom(groups, CeroSecNet.roomDefAt(square))
	end
	return CeroSecNet.roomsOf(def)
end

-- Does a computer stand in this premises? true, false, or nil for cannot-say.
--
-- The live room is the one way to ask what is in a room right now
-- (RoomDef.getIsoRoom -> IsoMetaGrid.getRoomByID, null while its chunks are away),
-- and the walk stops at the FIRST computer: one is the whole question.
--
-- The rooms' own squares and NOT their far edges, which is the one place this walk
-- and the device walk differ (SCeroSecDevices, the far edge of a room). A computer
-- is a thing on a desk: it stands in the middle of a square, not on the boundary
-- between two, so it is never on the neighbouring square's list the way a south
-- wall's door is. There is nothing out there for this question to find.
function CeroSecNotes.computerStands(square, kind, b1, b2)
	local key = CeroSecContent.key(b1, b2)
	if computerSeen[key] == true then return true end
	if square == nil then return nil end
	local rooms = premisesRoomsOf(square, kind)
	if rooms == nil or #rooms == 0 then return nil end

	local walked, away = 0, false
	for i = 1, #rooms do
		local room = rooms[i]
		local live = nil
		if room.def ~= nil and room.def.getIsoRoom ~= nil then
			live = room.def:getIsoRoom()
		end
		local squares = live ~= nil and live:getSquares() or nil
		if squares == nil then
			-- Its chunks are away, and the machine may be standing in this very
			-- room: the answer is cannot-say and not "no".
			away = true
		else
			for j = 0, squares:size() - 1 do
				-- The ceiling is counted in SQUARES and checked before each one, so
				-- a building of a thousand rooms cannot walk past it by a roomful.
				if walked >= CeroSecNotes.SQUARES_MAX then return nil end
				walked = walked + 1
				local sq = squares:get(j)
				local objects = sq ~= nil and sq:getObjects() or nil
				if objects ~= nil then
					for k = 0, objects:size() - 1 do
						local object = objects:get(k)
						if object ~= nil and object.getSpriteName ~= nil
								and CeroSec.isComputerSprite(object:getSpriteName()) then
							computerSeen[key] = true
							return true
						end
					end
				end
			end
		end
	end
	if away then return nil end
	return false
end

--
-- Writing one
--

-- The paper, into the container, with `text` written on its page and `login` on
-- its name. nil when the game would not make one, which is a container that is
-- full or a type the game has never heard of -- and that is not an error: it is
-- one note that did not land, and the premises is left unmarked so the next drawer
-- may carry it.
--
-- THE INK AND THE LABEL ARE TWO DIFFERENT THINGS, and this is the one place both
-- are put on. The page is what a player opens the note to read; the name is what
-- the row in his bag says. They are set here together because a paper that had one
-- without the other is either a note that says nothing or a note whose password is
-- readable without ever picking it up.
--
-- PAGE 1, because PageToWrite = 1 on the sheet: addPage(Integer, String) is the
-- call vanilla's own write modal makes on OK (ISInventoryPaneContextMenu:2716,
-- `notebook:addPage(i,v)`), and seePage(1) is what it hands the modal to show
-- (:2702). Both are public on zombie.inventory.types.Literature -- javap -p:
-- `public void addPage(java.lang.Integer, java.lang.String)`,
-- `public java.lang.String seePage(java.lang.Integer)`.
--
-- AND IT PERSISTS AND IT TRAVELS, which had to be true or the note would be blank
-- the moment the drawer's chunk went away again:
--
--   SAVE. Literature.save(ByteBuffer, boolean) writes the pages into the item's own
--   record -- customPages non-null and non-empty sets bit 32 of the header (offsets
--   208-228), then HashMap.size() as an int (241) and every value through
--   GameWindow.WriteString (284). load reads the count back (getInt at 217) and
--   re-keys them 1..n (the Integer.valueOf(i+1) at 257 against ReadString at 261).
--   One page in, one page out.
--
--   AND MULTIPLAYER. A note is written on the SERVER, at loot fill, and the client
--   who opens the drawer has to get the page with it. syncItemFields() is what
--   sends it and it was already the call this function ended on for the name:
--   zombie.network.packets.SyncItemFieldsPacket carries `customPages`,
--   `customName`/`isCustomName` and `moddata` as fields of the one packet, it fills
--   customPages from Literature.getCustomPages() at offset 310 of setData, and it
--   puts them back with Literature.setCustomPages on both the client and the server
--   side (offsets 267-270 and 133-136). So the page, the name and the icon key all
--   ride the same call, and there is nothing else to send.
function CeroSecNotes.write(container, text, login)
	if container == nil or container.AddItem == nil then return nil end
	local item = container:AddItem(CeroSecNotes.ITEM)
	if item == nil then return nil end
	-- THE WORDS, on the page. Guarded for the same reason every engine call in this
	-- mod is: a container that handed back something that is not a Literature would
	-- otherwise be a nil call, and a note with no ink is still a note that names its
	-- login.
	if item.addPage ~= nil then item:addPage(1, text) end
	-- The same three calls the floppy label uses, and for the same reason (see the
	-- head of CeroSecFloppyMenu): setName is the one reading of a written-on item
	-- that is true on the server and on every client, the custom-name flag is what
	-- stops the translated name winning, and syncItemFields is what sends it.
	-- setCustomName AFTER setName and never before -- it rawsets `customName` on the
	-- modData with whatever the name is AT THAT MOMENT.
	item:setName(string.format(CeroSecNotes.NAME_FORM, tostring(login)))
	item:setCustomName(true)
	-- And our own sticker on vanilla's sheet (CeroSecNotes.ICON).
	local data = item.getModData ~= nil and item:getModData() or nil
	if data ~= nil then data[CeroSecContent.ICON_KEY] = CeroSecNotes.ICON end
	if item.syncItemFields ~= nil then item:syncItemFields() end
	return item
end

-- ROOT'S PASSWORD, on a paper in a desk of this premises.
function CeroSecNotes.deskNote(system, container, containerType, profile, b1, b2,
		square, kind)
	if not profile.root then return nil end
	if CeroSecNotes.DESK_TYPES[containerType] ~= true then return nil end
	if CeroSecNotes.hasNote(system, b1, b2) then return nil end
	-- AND A MACHINE TO OPEN. Asked last of the four: it is the only one of them
	-- that walks the world, and three cheap noes cost nothing.
	if CeroSecNotes.computerStands(square, kind, b1, b2) ~= true then return nil end

	local password =
		CeroSecContent.password(system:secret(), CeroSecContent.rootKey(b1, b2))
	if password == nil then return nil end
	local item = CeroSecNotes.write(container,
		string.format(CeroSecNotes.ROOT_FORM, "root", password), "root")
	if item == nil then return nil end
	-- Marked only once the paper is really in the drawer.
	CeroSecNotes.markNote(system, b1, b2)
	CeroSec.log("a note for the premises " .. b1 .. "." .. b2 .. " went into a "
		.. tostring(containerType))
	return item
end

-- AN EMPLOYEE'S OWN LOGIN, on a paper in his pocket. Never root's: he was never
-- given it, and a mod that put the keys to the building on every third corpse
-- would be a mod where nobody ever opens a drawer.
--
-- WHICH employee, and the honest answer about determinism. The account is chosen
-- by a roll and so is whether there is a paper at all -- ZombRand, the way vanilla
-- rolls everything -- and not by a hash of the zombie: a zombie has no id at the
-- moment its pockets are filled that is worth hashing (getPersistentOutfitID is an
-- outfit and thousands of them share one). The determinism that matters is kept by
-- WHERE THE ANSWER LIVES: the roll happens once, the paper is then an item in the
-- world with the words already on it, and nothing rolls again. What is DERIVED --
-- the login and the password on it -- is derived from the save's secret and the
-- premises, so the paper and every machine in that office agree for ever.
function CeroSecNotes.zombieNote(system, container, profile, b1, b2, square, kind)
	if ZombRand == nil then return nil end
	local slots = CeroSecContent.lockedSlots(profile)
	if #slots == 0 then return nil end
	if math.floor(ZombRand(CeroSecNotes.ZOMBIE_ODDS)) ~= 0 then return nil end
	-- And the same rule the drawer obeys, for the same reason and asked in the same
	-- place -- last, after the roll: a dead employee of a shop with no computer in
	-- it carries the login of a machine nobody can walk up to.
	if CeroSecNotes.computerStands(square, kind, b1, b2) ~= true then return nil end

	local slot = slots[math.floor(ZombRand(#slots)) + 1]
	local secret = system:secret()
	local login = CeroSecContent.accountLogin(secret, b1, b2, slot)
	local password = CeroSecContent.accountPassword(secret, b1, b2, slot, login)
	if login == nil or password == nil then return nil end
	-- The one thing this must never write. A profile that named an account "root"
	-- would otherwise hand out the machine on a corpse, and the check is here
	-- rather than trusted to the catalogue because the catalogue is what the world-content work
	-- rewrites.
	if login == "root" then return nil end
	return CeroSecNotes.write(container,
		string.format(CeroSecNotes.USER_FORM, login, password), login)
end

--
-- The event
--
-- roomName, containerType, container -- LootLog.lua:7's own three.
--
-- Everything is asked in the order that costs least, because this runs for every
-- container the game fills in the county: the option, then the system, then the
-- square, then the premises, then the profile -- and, inside the two writers and
-- after every cheap no, the one question that walks the world.
--
function CeroSecNotes.onFillContainer(roomName, containerType, container)
	if not CeroSecContent.enabled() then return end
	local system = SCeroSecSystem and SCeroSecSystem.instance
	if system == nil or system.secret == nil then return end
	-- What arrived is not always a container (see THE THIRD ARGUMENT above). The
	-- class is asked of the ENGINE, which is the one thing that can answer it, and
	-- asked before anything is read off the object.
	if container == nil or instanceof == nil then return end
	if not instanceof(container, "ItemContainer") then return end

	local square = container:getSourceGrid()
	if square == nil then return end
	local b1, b2, _, pz, pk = CeroSecNet.premisesOfSquare(square)
	-- No building at all: the street, a car park, a player's own base. Nothing is
	-- written there, which is the same answer a machine standing there gets.
	if b1 == nil then return end

	-- The BUILDING's rooms and not this drawer's own room, which is the whole of
	-- what keeps the paper and the machine agreeing: see the head of
	-- CeroSecNet.premisesRooms. Asked of the drawer's own room, the desk in a study
	-- answered "office" and the computer in the living room of the same house
	-- answered "residential", and the paper named a password nothing had.
	local rooms = CeroSecNet.premisesRooms(square, pz, pk)

	local profile = CeroSecContent.PROFILES[CeroSecContent.profileFor(pz, rooms)]
	-- A premises whose profile the world-content work has not written yet: no machine is prefilled
	-- there, so there is no password to find and nothing to write.
	if type(profile) ~= "table" then return end

	-- The square and the KIND travel on, because the last question either writer
	-- asks is about the world and the kind is what says which rooms are this
	-- premises' (CeroSecNotes.computerStands). Passed and never worked out again,
	-- for the reason the head of CeroSecNet.premisesRooms gives: two answers to one
	-- question is how a note comes to name a password no machine has.
	if roomName == CeroSecNotes.ZOMBIE_ROOM then
		CeroSecNotes.zombieNote(system, container, profile, b1, b2, square, pk)
	else
		CeroSecNotes.deskNote(system, container, containerType, profile, b1, b2,
			square, pk)
	end
end

Events.OnFillContainer.Add(CeroSecNotes.onFillContainer)
