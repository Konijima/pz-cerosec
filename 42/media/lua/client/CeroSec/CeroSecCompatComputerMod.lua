require "CeroSec/CeroSecDefs"

--
-- Living beside Computer Mod (Workshop 3725497089, id ComputerModkum, v1.0.0).
--
-- That mod puts its machine on the SAME eight vanilla desktop tiles we do
-- (ComputerMod_ComputerTypes.lua:171-183, appliances_com_01_72..79 --
-- CeroSecDefs.lua:163-176 is the same list). Both of us fill
-- OnFillWorldObjectContextMenu, and theirs rewrites the world sprite on every
-- fill: ComputerMod_ContextMenu.lua:701 calls syncComputerWorldScreen(computer,
-- data.ComputerModPowerOn == true), which on a machine CeroSec lit -- their flag
-- nil, so false -- maps 76 back to 72, setSpriteFromName and
-- transmitUpdatedSpriteToClients (:672-682). Our menu reads the sprite for the
-- on/off label (CeroSecContextMenu.lua:320), so the screen goes dark on the
-- first right-click and the running session is no longer reachable.
--
-- The fix is ownership, not arbitration: whoever boots a desktop owns it until
-- it is switched off. On a machine that is OURS we do not call their filler at
-- all -- it is the call itself that darkens the screen. On a machine that is
-- THEIRS we add nothing (the guard in CeroSecContextMenu). On a dark machine
-- both menus are offered and the player's click decides.
--
-- WHY A RELAY AND NOT A WRAPPER. The event holds the VALUE of their function:
-- Events.OnFillWorldObjectContextMenu.Add(ComputerContextMenu.doMenu)
-- (ComputerMod_ContextMenu.lua:1029) and their table is aliased under two
-- global names onto one table (:16-18). Overwriting the .doMenu field after
-- the fact intercepts nothing -- the event goes on calling the old value. So
-- the value is REMOVED from the event and relayed by us. Events.<X>.Remove is
-- vanilla's own (ISWorldObjectContextMenu.lua:2795,
-- Tutorial/Steps.lua:914), and the removal happens before anything is written
-- so that the field still holds the value the event was given.
--
-- We call them, we never write for them: not one ComputerMod* key is assigned
-- anywhere in this file. Their flag is read, and only read.
--
-- If their mod is not active, or their table or doMenu is not what this file
-- expects, nothing at all happens: no removal, no relay, no guard. Both menus
-- coexist exactly as they do today and CeroSec alone is untouched.
--

CeroSecCompatComputerMod = {}

-- mod.info id=, which is what getActivatedMods() answers -- not the folder name
-- ComputerMod.
local MOD_ID = "ComputerModkum"

-- Their filler, as the event held it. nil until armed, and nil for good if any
-- check below fails.
local theirs = nil

-- Is that mod in this game? By id and once, at OnGameStart: a global can come
-- from anywhere, an id is a fact.
--
-- By the loop and not by :contains(id): vanilla only ever reads the list with
-- :size() and :get(i - 1) (ServerSettingsScreen.lua:2295-2297,
-- ISPauseModListUI.lua:19), and a call that was never proven is not a syntax
-- error -- it is a nil call, once a game.
local function modActive()
	if getActivatedMods == nil then return false end
	local mods = getActivatedMods()
	if mods == nil or mods.size == nil or mods.get == nil then return false end
	for i = 1, mods:size() do
		if mods:get(i - 1) == MOD_ID then return true end
	end
	return false
end

-- Their power flag on this machine, read only. For a desktop their data table
-- IS the object's modData, flat, under ComputerMod* keys
-- (ComputerMod_ComputerTypes.lua:42-50, registry.getRawData; dataOnItem is only
-- set by the laptop addon, ComputerModLaptop_Core.lua:101-105).
local function theyBootedIt(computer)
	if computer == nil or computer.hasModData == nil then return false end
	if not computer:hasModData() then return false end
	local data = computer:getModData()
	return type(data) == "table" and data.ComputerModPowerOn == true
end

-- Who is running this desktop: "computermod", "cerosec", or nil for a dark one
-- nobody has booted. Always nil while we are not armed, so a game without their
-- mod never takes a different branch anywhere.
--
-- THEIR FLAG IS ASKED FIRST, and that order is the whole point. Our own state
-- for a machine is the lit sprite -- it is what our menu reads
-- (CeroSecContextMenu.lua:320) and it is what our server ADOPTS a machine from
-- when the save has no GlobalObject for it (SCeroSecObject:stateFromIsoObject,
-- `self.on = CeroSec.isOnSprite(spriteName)`). So a machine THEY lit answers
-- "on" to us as well, and asking the sprite first would offer "Use computer" on
-- a session CeroSec never started. Their flag is the only thing that tells the
-- two apart.
function CeroSecCompatComputerMod.ownerOf(computer)
	if theirs == nil or computer == nil then return nil end
	if theyBootedIt(computer) then return "computermod" end
	if CeroSec.isOnSprite(computer:getSpriteName()) then return "cerosec" end
	return nil
end

-- Two computers on one square: we keep the click.
--
-- Their filler stamps whatever it finds with a ComputerModMachineID
-- (ensureIdentity, ComputerMod_ContextMenu.lua:699), and for a placed desktop
-- the id is built from the SQUARE's coordinates
-- (ComputerMod_ComputerTypes.lua:91-98). Two stamped machines on one square
-- therefore carry the same id, and their server sweep removes one of them from
-- the square on the next chunk load -- transmitRemoveItemFromSquare /
-- RemoveTileObject, ComputerMod_MoveablePersistence.lua:196-203. The object it
-- takes away carries our movableData.cerosec with it, which is the machine's
-- filesystem. Machines on different squares get different ids and cannot
-- collide, so this one square is the whole of the hole.
--
-- The price, said plainly: on a stacked square their menu does not appear.
local function sharesItsSquare(computer)
	local square = computer:getSquare()
	if square == nil then return false end
	local objects = square:getObjects()
	if objects == nil then return false end
	local seen = 0
	for i = 0, objects:size() - 1 do
		if CeroSec.isComputerSprite(objects:get(i):getSpriteName()) then
			seen = seen + 1
			if seen > 1 then return true end
		end
	end
	return false
end

-- Their filler, called with the arguments it was registered to receive. Under
-- pcall: an error in another mod's menu must not take the game's whole
-- right-click down with it. Their answer is passed back untouched, because on
-- the test pass the event wants the boolean they return (:688).
local function relay(player, context, worldobjects, test)
	local ok, answer = pcall(theirs, player, context, worldobjects, test)
	if not ok then
		CeroSec.log(CeroSec.LOG_ERROR,
			"compat: Computer Mod's menu raised: " .. tostring(answer))
		return
	end
	return answer
end

-- The relay, registered in their place.
--
-- One case and one case only keeps the click from them: a desktop CeroSec is
-- running. Everything else -- no computer of ours under the cursor, a dark
-- machine, a machine they booted -- goes to them with the arguments the event
-- gave us, so their laptop on the floor, their network terminals and everything
-- else of theirs goes on living.
--
-- The test pass is handed straight over, the way their own first line handles it
-- (ComputerMod_ContextMenu.lua:688): it asks whether anything would be added,
-- and the answer to that is theirs to give.
function CeroSecCompatComputerMod.fill(player, context, worldobjects, test)
	if theirs == nil then return end
	if test and ISWorldObjectContextMenu ~= nil and ISWorldObjectContextMenu.Test then
		return relay(player, context, worldobjects, test)
	end

	local computer = CeroSecContextMenu.findComputer(worldobjects, player)
	if computer ~= nil then
		if CeroSecCompatComputerMod.ownerOf(computer) == "cerosec" then return end
		if sharesItsSquare(computer) then return end
	end

	return relay(player, context, worldobjects, test)
end

-- At OnGameStart, once. Their Add runs when their file loads, which is long
-- before this, so the value is on the event by now; and nothing has written to
-- their table, so the field still holds the value the event was given.
local function arm()
	if not modActive() then return end

	if type(ComputerModContextMenu) ~= "table"
			or type(ComputerModContextMenu.doMenu) ~= "function" then
		-- Their update renamed or moved it. We take nothing off the event and add
		-- no relay: the two menus coexist the way they did before this file
		-- existed. Said once, so a player who wonders has a line to find.
		CeroSec.log(CeroSec.LOG_WARN,
			"compat: Computer Mod is active but its context menu is not the one " ..
			"this build knows -- the two menus are left as they are")
		return
	end

	theirs = ComputerModContextMenu.doMenu
	Events.OnFillWorldObjectContextMenu.Remove(theirs)
	Events.OnFillWorldObjectContextMenu.Add(CeroSecCompatComputerMod.fill)
	CeroSec.log("compat: Computer Mod is active -- a desktop belongs to the mod " ..
		"that booted it until it is switched off")
end

Events.OnGameStart.Add(arm)
