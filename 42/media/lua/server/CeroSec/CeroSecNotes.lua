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
--   * ON A PAPER IN THE DESK. One per premises, at most, in a desk, a counter, a
--     filing cabinet or a drawer of that same premises. It names ROOT, which is
--     the key to the whole machine: `Sticky note: root / falcon12`.
--   * IN A DEAD MAN'S POCKET. About one zombie in twenty, killed inside a
--     premises, carries his OWN login on a paper -- never root's, which he was
--     never given: `Note: rmiller / thunder07`. A corpse gives a foothold; the
--     office gives the keys.
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

CeroSecNotes.ITEM = "CeroSec.StickyNote"

-- What a survivor reads in his inventory. Two shapes, and they say which kind of
-- note it is in their first word: one was stuck to a desk, the other was folded in
-- a pocket.
CeroSecNotes.ROOT_FORM = "Sticky note: %s / %s"
CeroSecNotes.USER_FORM = "Note: %s / %s"

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
-- Writing one
--

-- The item, into the container, with the words on its name. nil when the game
-- would not make one, which is a container that is full or a type the game has
-- never heard of -- and that is not an error: it is one note that did not land,
-- and the premises is left unmarked so the next drawer may carry it.
function CeroSecNotes.write(container, text)
	if container == nil or container.AddItem == nil then return nil end
	local item = container:AddItem(CeroSecNotes.ITEM)
	if item == nil then return nil end
	-- The same three calls the floppy label uses, and for the same reason (see the
	-- head of CeroSecFloppyMenu): setName is the one reading of a written-on item
	-- that is true on the server and on every client, the custom-name flag is what
	-- stops the translated name winning, and syncItemFields is what sends it.
	item:setName(text)
	item:setCustomName(true)
	if item.syncItemFields ~= nil then item:syncItemFields() end
	return item
end

-- ROOT'S PASSWORD, on a paper in a desk of this premises.
function CeroSecNotes.deskNote(system, container, containerType, profile, b1, b2)
	if not profile.root then return nil end
	if CeroSecNotes.DESK_TYPES[containerType] ~= true then return nil end
	if CeroSecNotes.hasNote(system, b1, b2) then return nil end

	local password =
		CeroSecContent.password(system:secret(), CeroSecContent.rootKey(b1, b2))
	if password == nil then return nil end
	local item =
		CeroSecNotes.write(container, string.format(CeroSecNotes.ROOT_FORM, "root", password))
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
function CeroSecNotes.zombieNote(system, container, profile, b1, b2)
	if ZombRand == nil then return nil end
	local slots = CeroSecContent.lockedSlots(profile)
	if #slots == 0 then return nil end
	if math.floor(ZombRand(CeroSecNotes.ZOMBIE_ODDS)) ~= 0 then return nil end

	local slot = slots[math.floor(ZombRand(#slots)) + 1]
	local secret = system:secret()
	local login = CeroSecContent.accountLogin(secret, b1, b2, slot)
	local password = CeroSecContent.accountPassword(secret, b1, b2, slot, login)
	if login == nil or password == nil then return nil end
	-- The one thing this must never write. A profile that named an account "root"
	-- would otherwise hand out the machine on a corpse, and the check is here
	-- rather than trusted to the catalogue because the catalogue is what wave 7b
	-- rewrites.
	if login == "root" then return nil end
	return CeroSecNotes.write(container,
		string.format(CeroSecNotes.USER_FORM, login, password))
end

--
-- The event
--
-- roomName, containerType, container -- LootLog.lua:7's own three.
--
-- Everything is asked in the order that costs least, because this runs for every
-- container the game fills in the county: the option, then the system, then the
-- square, then the premises, then the profile.
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
	local b1, b2, _, zone = CeroSecNet.premisesOfSquare(square)
	-- No building at all: the street, a car park, a player's own base. Nothing is
	-- written there, which is the same answer a machine standing there gets.
	if b1 == nil then return end

	-- The BUILDING's rooms and not this drawer's own room, which is the whole of
	-- what keeps the paper and the machine agreeing: see the head of
	-- CeroSecNet.premisesRooms. Asked of the drawer's own room, the desk in a study
	-- answered "office" and the computer in the living room of the same house
	-- answered "residential", and the paper named a password nothing had.
	local rooms = CeroSecNet.premisesRooms(square, zone)

	local profile = CeroSecContent.PROFILES[CeroSecContent.profileFor(zone, rooms)]
	-- A premises whose profile wave 7b has not written yet: no machine is prefilled
	-- there, so there is no password to find and nothing to write.
	if type(profile) ~= "table" then return end

	if roomName == CeroSecNotes.ZOMBIE_ROOM then
		CeroSecNotes.zombieNote(system, container, profile, b1, b2)
	else
		CeroSecNotes.deskNote(system, container, containerType, profile, b1, b2)
	end
end

Events.OnFillContainer.Add(CeroSecNotes.onFillContainer)
