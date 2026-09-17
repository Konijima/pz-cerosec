if isClient() then return end

require "CeroSec/CeroSecDefs"
require "CeroSec/CeroSecModules"
require "CeroSec/OS/CeroSecOS"
require "CeroSec/OS/CeroSecOSDev"
require "CeroSec/SCeroSecSensors"
require "CeroSec/SCeroSecRadio"

--
-- The world, as devices.
--
-- The engine knows nothing about Project Zomboid: it renders /dev and refuses
-- what may not be written, and everything that touches a light switch, a door
-- or a window happens HERE. What the two agree on is a list of entries and one
-- call (see the head of CeroSecOSDev.lua).
--
-- What a machine can reach
--
-- Nothing it is not WIRED to, which is rung 4f's whole change: a light switch is
-- in /dev because somebody screwed a relay to it, a door because somebody fitted
-- an operator, a strike or a magnetic contact, a window because somebody fitted
-- a contact. The four modules, what each one buys and where they are kept are in
-- CeroSecModules.lua (shared, because the right-click menu asks the same
-- questions); the gate itself is `fittedOn` and `has` in classify, below.
--
-- The sandbox option CeroSec.HardwareRequired turns it off, and off is the world
-- exactly as it was before this rung -- every door, window, lock and light of the
-- building, with the same numbers -- which is why `fitted == nil` reads as "yes"
-- everywhere rather than as a second code path.
--
-- And of what it is wired to: its own building when its square has one -- every
-- room of it -- and a radius of ten tiles on the same z when it has not, which
-- is what a computer standing in a player-built base gets: a base has no
-- building and no rooms.
--
-- THE RADIUS TAKES NOTHING THAT BELONGS TO A BUILDING. It is the fallback for a
-- place the map knows no room in, not a second reach into the house next door:
-- a machine set down on the pavement five tiles from a house used to list that
-- house's doors and lamps for free, which is a stranger's computer opening a
-- door he never wired (scanOutdoorSquare).
--
-- Nothing outside the loaded world exists. The game only keeps the chunks
-- around the players (13x13 of 8 tiles) and there is no unload event, so a
-- device is not "gone", it is simply not found this pass -- and a machine in a
-- town nobody is standing in cannot act on anything. That is why the discovery
-- is a walk of the world and not a book kept up to date: the answer is only true
-- for the moment it is asked.
--
-- It is not walked twice in the same tenth of a second, though, and that is the
-- one thing remembered about it: the list of what a machine can reach is held
-- for CeroSecDevices.CACHE_MS, while what each of those things is DOING is read
-- off the object every single time. The whole of the reasoning, and the cost it
-- is about -- which is not the cost docs/notes/actuators.md counted -- is at
-- "Not doing the walk again", below.
--
-- The numbers
--
-- light0 is the same light switch tomorrow as it is today. The numbering is
-- worked out once, from the candidates sorted by (kind, x, y, z, side), and
-- then written into the machine's own state at os.devmap, keyed by where the
-- device is. A device that goes away leaves its entry there -- the number is
-- spent for the life of that machine -- so nothing is ever renumbered under a
-- player who wrote "echo off > /dev/light3" into a script.
--
--   state.devmap["light:1024:998:0::0"] = { id = "light0", kind = "light",
--                                           n = 0, mode = 660 }
--
-- The mode rides along, because a chmod on a device has to outlive the command
-- it was typed in and the node itself is thrown away at the end of one.
--
-- The calls, and why these ones
--
-- Every one of them is verified with javap against
-- projectzomboid.jar (42.20.4) and used the way the game's own Lua uses it. The
-- point that matters is WHO BROADCASTS: our writes happen on the server, and
-- most of vanilla's happen on a client, so a setter that syncs for a player
-- does not necessarily sync for us.
--
--   light   IsoLightSwitch:setActive(on)
--           setActive(Z) -> setActive(Z,Z,Z), which ends on
--           syncIsoObject(false, activated, null); that method's server branch
--           walks GameServer.udpEngine.connections and sends SyncIsoObject to
--           each. So the light syncs ITSELF from the server and we add nothing.
--           It also answers with the state it settled on, which is why the
--           result is read back rather than assumed.
--
--   lock    IsoDoor:setLockedByKey(locked) then
--           syncIsoObject(false, 0, nil, nil)
--           setLockedByKey(Z,Z) explicitly SKIPS its own sync when
--           GameServer.server is true, so the sync is ours to make -- exactly
--           the pair vanilla makes in
--           media/lua/shared/TimedActions/ISLockDoor.lua:52-56.
--           IsoObject:syncIsoObject with bClient false is the server broadcast.
--
--   win     IsoWindow:setIsLocked(locked) then
--           syncIsoObject(false, 0, nil, nil)
--           setIsLocked is a bare field write with no sync of any kind, and
--           IsoWindow:syncIsoObjectSend writes `locked` into the packet.
--
--   find    IsoObject:setHighlighted(playerNum, on, false), plus
--   (client) setHighlightColor / setOutlineHighlight / setOutlineHighlightCol
--           on the same playerNum, which is exactly the four vanilla makes on
--           hover in media/lua/client/ISUI/ISWorldObjectContextMenu.lua:281-287
--           (onHighlightWorldItem). javap has all four on zombie.iso.IsoObject
--           with an int first argument: that int is the LOCAL player (split
--           screen), so a highlight is drawn for one pair of eyes and nobody
--           else's -- which is what we want, and why this half is the client's
--           and travels as a message.
--
--   lock    IsoThumpable:setLockedByPadlock(locked)
--   (built) which calls syncIsoThumpable() itself, and syncIsoThumpable's
--           server branch is INetworkPacket.sendToRelative(SyncThumpable, ...).
--           So a padlock syncs itself. A player door held by a key goes through
--           setLockedByKey, which skips its sync on the server like the map
--           door's, so syncIsoThumpable() is called by hand after it.
--
--   door    IsoDoor:ToggleDoorSilent() / IsoThumpable:ToggleDoorSilent(), then
--           syncIsoObject(false, 0, nil, nil)
--           Silent is the whole point: ToggleDoor(character) needs a character,
--           plays a sound at him and walks every leaf of a double door through
--           forEachDoorObject. A machine has no character, so the call that
--           moves one door and nothing else is the right one -- and it is the
--           call vanilla's own Lua makes when a script opens a door with nobody
--           holding it (media/lua/client/Tutorial/Steps.lua:1288 and :1795,
--           Tutorial1.lua:331).
--           Its bytecode is: isBarricaded -> return (so a barricaded door is
--           refused HERE, by us, or the order would be swallowed in silence),
--           InvalidateSpecialObjectPaths, the LOS caches, setRecalcLightTime,
--           then setOpen(!isOpen()) and the sprite swap. No sync of any kind,
--           so the broadcast is ours -- and it is syncIsoObject and not
--           syncIsoThumpable even for a player door: SyncThumpablePacket
--           carries lockedByCode, lockedByPadlock and keyId and NOTHING else,
--           while both classes' syncIsoObjectSend writes the open flag
--           (IsoDoor: isOpen(); IsoThumpable: the open field).
--
--   sensor  nothing at all. A motion sensor is a device that is only ever READ,
--           and what it reads is not a question asked of the item lying on the
--           floor -- there is nothing on a dropped item to ask -- but what the
--           sampling book says its contact is doing. The item, its range, the
--           field of view and the once-a-second sample are all in
--           SCeroSecSensors.lua, which is where the javap for them is too.
--           Here it is one more kind in the discovery, read through
--           IsoGridSquare:getWorldObjects() instead of getObjects() because a
--           dropped item is not on the square's object list.
--
-- The lock, and the one place it means anything
--
-- A keyed door only stops a survivor who is on the wrong side of it, which is
-- why `lock` devices are no longer made for every door:
--
--   IsoDoor.couldBeOpen(chr) reads, in order: an animal is false, isBarricaded
--   is false, and then canBeOpenFromInside(chr) returns TRUE AND RETURNS --
--   before the isLockedByKey / haveThisKeyId branch is ever reached.
--   canBeOpenFromInside is: chr is an IsoPlayer, chr.isOutside() is false, and
--   chr's room is the door's own square's room or its opposite square's room,
--   and the door has no "forceLocked" property.
--
-- So from inside, a locked map door always opens; the lock is a fact about the
-- OUTSIDE of a building. A door with a room on both sides has no outside, and a
-- lock on it is a device that lies.
--
-- A player-built door is the same shape with a different test: IsoThumpable's
-- ToggleDoorActual and couldBeOpen both gate isLockedByKey on
-- chr.getCurrentSquare().has(IsoFlagType.exterior) -- the square the survivor is
-- standing on, not which side of a building it is. A base door is reachable from
-- an exterior square by construction, so every player-built door stays a `lock`
-- device exactly as it was.
--
-- And the padlock, which was the open question: a padlock does NOT stop a door
-- from being opened, from either side. IsoThumpable.ToggleDoorActual has no
-- lockedByPadlock branch at all and neither has couldBeOpen; the only reader is
-- isLockedToCharacter, which answers true for a padlock with no key in the
-- inventory and no side test whatever -- and its callers are the CONTAINER ones
-- (media/lua/server/ISObjectClickHandler.lua:283, client/ISUI/ISInventoryPage.lua)
-- plus the pick-up refusal in shared/Moveables/ISMoveableSpriteProps.lua:1222.
-- A padlock locks what is inside the door, not the door. That is why `padlock`
-- is a `lock` state and never a `door` one.
--

CeroSecDevices = CeroSecDevices or {}

-- Tiles around the machine, on its own z, when it is not in a building.
CeroSecDevices.RADIUS = 10

-- Pointing at one
--
-- `dev find` has to answer the one question a listing cannot: WHICH of the
-- thirty-five it is. A light says so itself -- it blinks, and everybody in the
-- room sees it. A door and a window have nothing to do that with, so the
-- requesting player's own client draws an outline around it and nobody else's
-- does.
--
-- The blink is a server-side timer, and the timer is Events.OnTick gated on
-- getTimestampMs(), which is vanilla's own way of getting under a minute on a
-- server: media/lua/server/Foraging/forageServer.lua:455-460 keeps a
-- _nextRelevanceMs and returns early until the clock passes it, registered at
-- line 502 with Events.OnTick.Add. EveryOneMinute, which is what the rest of
-- this mod runs on, cannot blink anything.
-- How long a flip lasts. How long the whole blink lasts is NOT here: the engine
-- hands the seconds over with the request (CeroSecOS.DEV_FIND_SECONDS), so
-- there is one number for it and it is the one the manual quotes.
CeroSecDevices.BLINK_MS = 500

-- The lights blinking right now. Never saved: a blink is six seconds long and a
-- reload is the end of it, which is the right end for a thing whose whole
-- purpose is to answer a question somebody asked ten seconds ago.
CeroSecDevices.blinks = {}

-- How many entries os.devmap may hold. A number spent is spent for the life of
-- the machine, so this is what stops a computer carried across the map from
-- growing a book of dead devices in the save file.
--
-- 512, which is twice what /dev can mount at once (CeroSecOS.DEV_MAX). It was 128
-- against a /dev of 64, and the pair keep that proportion on purpose: the book has
-- to hold the devices of the building the machine is standing in AND the ones it
-- was standing in before, or a computer carried back into a mall it has already
-- numbered gives every light a second number.
CeroSecDevices.MAP_MAX = 512

-- The room a square is in, by its raw id ("kitchen", "office"), or nil.
--
-- Both of these moved to CeroSecModules (shared) at rung 4f and are forwarded
-- here so that every call site below reads as it always did. They moved because
-- the right-click menu asks the same two questions -- is this a door a lock
-- means anything on? -- and a client cannot load a server file, and a rule
-- written on both sides is a rule that drifts.
local function roomName(square)
	return CeroSecModules.roomName(square)
end

--
-- Classifying one object
--
-- nil when it is not a device, otherwise the LIST of devices it is -- one
-- object can be two, because an exterior door is both the thing that opens and
-- the thing that locks, and a survivor works those with different words. The
-- state strings are the machine's whole vocabulary and are written here, once.
--

local function doorDesc(door)
	local here = roomName(door:getSquare())
	local there = roomName(door:getOppositeSquare())
	-- A door with nothing but the outdoors on one side of it is the way in.
	if here == nil or there == nil then return "exterior" end
	if here == there then return here end
	return here .. "-" .. there
end

-- open, smashed, barricaded, locked or unlocked -- and the ORDER is the door's,
-- read the same way for the same reason (doorState, below).
--
-- Broken and boarded first: either of them is what a survivor needs to be told,
-- and neither is something a latch has anything to say about. A smashed window
-- has no sash left to be open and a boarded one cannot move, so neither of them
-- is ever the sash's business either.
--
-- Then OPEN, ahead of the latch, exactly as a door puts `open` ahead of
-- `locked`: a window a survivor has pushed up is open whatever its latch says,
-- and the word that matters is the one about the hole in the wall. So `locked`
-- and `unlocked` both mean shut, the way a door's `locked` means closed -- five
-- words and not eight, because nobody needs to be told "open and unlocked".
--
-- IsOpen() is the call, the same name a door answers to
-- (docs/notes/modules-proofs.md, 4), and it is what a magnetic contact on a
-- window is FOR: the contact senses the sash, and now the device says so.
local function windowState(win)
	if win:isSmashed() then return "smashed" end
	if win:isBarricaded() then return "barricaded" end
	if win:IsOpen() then return "open" end
	if win:isLocked() then return "locked" end
	return "unlocked"
end

local function thumpState(thump)
	if thump:isLockedByPadlock() then return "padlock" end
	if thump:isLockedByKey() then return "locked" end
	return "unlocked"
end

-- Does this map door's lock stop anybody? Its own isExterior() first -- the
-- square carries the exterior flag and the far side is a building with a def,
-- or the other way round -- and then the rooms, because a door whose two sides
-- have a room on exactly one of them is a way out of the building whatever the
-- tile flags say. The room test is the same reading doorDesc makes, so a device
-- whose description says "exterior" is always one the lock means something on.
local function doorLocks(door)
	return CeroSecModules.doorLocks(door)
end

-- One leaf of a double or a garage door. ToggleDoorSilent moves ONE object, and
-- vanilla's own toggle walks every leaf of the thing (forEachDoorObject, inside
-- ToggleDoorActual), so a machine that called Silent on one half would leave the
-- other half shut. Those are not `door` devices -- they are still `lock` ones,
-- because setLockedByKey is per-object in vanilla too.
--
-- `IsoDoor.getGarageDoorIndex(object) ~= -1` is vanilla's own way of asking
-- (media/lua/server/BuildingObjects/ISBuildUtil.lua:556, and :315 of
-- ISDoubleDoor.lua for the double-door one). Both are public statics and both
-- answer -1 for an object with no DOUBLE_DOOR / GARAGE_DOOR property on it.
-- Moved to CeroSecModules with the two above and for the same reason: an
-- operator is refused on a leaf of a garage door at the menu, by this test.
local function isManyDoors(object)
	return CeroSecModules.isManyDoors(object)
end

-- open, closed, or locked -- three words and not four, because locked implies
-- closed and a survivor reading "locked" has been told both things. `locks` is
-- whether this door is one the lock means anything on (doorLocks, above): an
-- interior door with a key in it still opens from either side, so it reads
-- "closed" and opens.
--
-- IsOpen() is the one name both classes answer to (IsoDoor's forwards to its
-- isOpen(), IsoThumpable's reads its open field).
local function doorState(object, locks)
	if object:IsOpen() then return "open" end
	if locks and object:isLockedByKey() then return "locked" end
	return "closed"
end

-- The hardware, when the sandbox option asks for any (CeroSecModules.required).
-- A table of four booleans, empty when nothing is fitted, and nil -- meaning "do
-- not ask" -- when the option is off, which is the whole of how the old world is
-- kept: every branch below reads `fitted == nil` as "yes, of course".
--
-- Asked INSIDE each branch and never at the top of classify, because classify is
-- asked about every object on every square of the building at every command --
-- the walls, the floors, the furniture -- and only one in fifty of them is a
-- thing a module goes on. Two Java calls apiece for the other forty-nine is a
-- cost paid over and over for nothing.
local function fittedOn(object)
	if not CeroSecModules.required() then return nil end
	return CeroSecModules.installedOn(object)
end

local function has(fitted, id)
	return fitted == nil or fitted[id] == true
end

--
-- What one device is DOING, right now
--
-- Written apart from classify because it is asked in two places and a rule
-- written twice is a rule that drifts: once when the walk first finds a device,
-- and again on every pass that is answered out of the cache below
-- (CeroSecDevices.findCached). What a device IS -- its kind, which way it faces,
-- the rooms it stands between, whether there is hardware behind it -- is a fact
-- about the building and holds for a second. What it is DOING is a fact about
-- this instant and is read off the object every single time.
--
--
-- The motor rung's kinds, read
--

-- A whole number, clamped, for a line a survivor reads. The engine answers a
-- float for the fuel and an int for the condition, and 62.399998 in a status
-- line is a machine showing its working.
local function pct(value)
	local n = tonumber(value) or 0
	n = math.floor(n + 0.5)
	if n < 0 then n = 0 end
	if n > 100 then n = 100 end
	return tostring(n)
end

-- A curtain has ONE fact and it is a boolean, and there are two kinds of curtain
-- behind this (CeroSecModules.isCurtain): an IsoCurtain of its own, which
-- answers IsOpen(), and a door with a sheet, whose fields live on the door and
-- answer isCurtainOpen(). `isCurtainOpen` on an IsoCurtain is `IsOpen` forwarded,
-- one instruction of it (offsets 0-4), so either name reads a curtain -- but a
-- DOOR has no IsOpen() that means the sheet, so the two are asked apart.
--
-- No `barricaded` word, and that is not an oversight: IsoCurtain has no
-- isBarricaded() at all -- `barricaded` is a public FIELD with no getter over it
-- -- so there is nothing to read and the refusal is found the only way it can be
-- (see `act`).
local function curtainState(object)
	if instanceof(object, "IsoCurtain") then
		return object:IsOpen() and "open" or "closed"
	end
	return object:isCurtainOpen() and "open" or "closed"
end

-- The SASH, which is a different reading from `win`'s: win0 is the magnetic
-- contact and reports the latch, window0 is the operator and reports the hole in
-- the wall. The three that come first are the three silent returns at the top of
-- ToggleWindow -- permaLocked (offsets 21-28), destroyed (29-36) and the
-- barricade the null character skips (37-49) -- in the order the engine tests
-- them, because a survivor told the first thing that stops the motor has been
-- told the thing to go and fix.
--
-- isSmashed() and isDestroyed() read the SAME field (#393 `destroyed`, both
-- bodies are three instructions), so `smashed` covers the second of those three
-- and there is no fourth word.
--
-- `sealed` is isPermaLocked(): a window the map says never opens. The trade word
-- for a light that does not open is a sealed one, and that is what it is.
local function sashState(win)
	if win:isSmashed() then return "smashed" end
	if win:isBarricaded() then return "barricaded" end
	if win:isPermaLocked() then return "sealed" end
	if win:IsOpen() then return "open" end
	return "closed"
end

-- An oven, a microwave or a coffee machine. `broken` first, because it is the
-- one thing the switch itself refuses on (setActivated returns at offsets 0-7)
-- and the one thing a survivor has to do something about. No `no power` word:
-- power is a fact about the wire and not about the stove, a light switch already
-- says it as a REFUSAL and not as a state, and a stove that is simply off reads
-- off whether the grid is up or not.
local function stoveState(stove)
	if stove:isBroken() then return "broken" end
	return stove:Activated() and "on" or "off"
end

-- Has this appliance got electricity? Vanilla's own question, asked vanilla's own
-- guarded way: `object:getContainer() and object:getContainer():isPowered()`
-- (client/ISUI/ISInventoryPage.lua:216, and the stove's own three call sites at
-- ISInventoryPaneContextMenu.lua:988, LootWindow/Handlers/StoveToggle.lua:8 and
-- StoveSettings.lua:8). A fixture with no container answers no, which is the
-- same answer a survivor clicking it would get.
--
-- A TELEVISION OR A RADIO SET, which are one class twice over
--
-- Everything a set has is on its zombie.radio.devices.DeviceData: the switch
-- (getIsTurnedOn), the dial (getChannel), the span the dial can reach
-- (getMinChannelRange / getMaxChannelRange) and the supply (canBePoweredHere,
-- getIsBatteryPowered, getPower). The whole list, javap'd, is at the head of
-- SCeroSecRadio.lua as proof 2, and this rung adds no call to it that is not
-- already written down there.
--
-- Asked through here and nowhere else, so that a set whose data went away between
-- the walk and the write is a device that simply is not there rather than a nil
-- call in the middle of an order.
local function waveData(object)
	if object == nil then return nil end
	if type(object.getDeviceData) ~= "function" then return nil end
	return object:getDeviceData()
end

-- ON or OFF, and there is no third word.
--
-- No `no power` STATE, which is the stove's rule and not the TNC's: power is a
-- fact about the wire and a set that is simply switched off reads off whether the
-- county has electricity or not. /dev/radio0 does say it, because that device is
-- read-only and its whole use is to be read before walking over to the set; a
-- device a survivor can WRITE says what a switch says, and says `no power` as the
-- refusal it is.
local function waveState(object)
	local data = waveData(object)
	if data == nil then return nil end
	return data:getIsTurnedOn() and "on" or "off"
end

local function appliancePowered(object)
	local container = object:getContainer()
	if container == nil then return false end
	return container:isPowered() == true
end

-- nil for a kind with no object to ask, and the caller keeps what it had: a
-- sensor's state is the sampling book's and is put on in build(), and a radio's
-- comes with the entry and never goes through the cache at all.
local function stateOf(kind, object, locks)
	if object == nil then return nil end
	if kind == "light" then return object:isActivated() and "on" or "off" end
	if kind == "door" then return doorState(object, locks) end
	if kind == "win" then return windowState(object) end
	if kind == "lock" then
		-- A map door's key and a built door's padlock are two different
		-- readings, and classify made the same split when it wrote the first one.
		if instanceof(object, "IsoDoor") then
			return object:isLockedByKey() and "locked" or "unlocked"
		end
		return thumpState(object)
	end
	if kind == "curtain" then return curtainState(object) end
	if kind == "window" then return sashState(object) end
	if kind == "stove" then return stoveState(object) end
	if kind == "washer" then return object:isActivated() and "on" or "off" end
	if kind == "gen" then return object:isActivated() and "on" or "off" end
	if kind == "tv" or kind == "rx" then return waveState(object) end
	return nil
end

-- The REST of the line, for a kind that has more to say than one word, or nil.
--
-- Three kinds have. A generator: what a survivor needs of one is not whether it
-- is running -- he can hear that -- but how long it will go on running, and that
-- is two numbers and a fact. And a television or a radio set, whose switch is one
-- word and whose DIAL is not a word at all.
--
-- None of them goes in the `state`, because the listings have a column for a word
-- and not for a sentence (`ls -l /dev` puts the widest state on column 60), so
-- `cat` gets the whole line and the tables get the word. CeroSecOS.devText is
-- where the two are put back together.
local function detailOf(kind, object)
	if object == nil then return nil end

	-- The dial, as the raw number the engine takes and answers with, and NOT as
	-- megahertz.
	--
	-- /dev/radio0 prints megahertz (CeroSecOS.radioFreqText) and can afford to: it
	-- is read-only, so its reading is the only spelling of that number a survivor
	-- ever meets. A dial he can WRITE cannot -- `echo channel 203` and a line
	-- reading `0.203` would be one number under two names -- and it would be the
	-- game's own inconsistency copied for nothing: vanilla's radio window prints
	-- megahertz for a radio and, for a television, prints no frequency at all,
	-- only the channel's NAME (client/RadioCom/RadioWindowModules/RWMGeneral.lua
	-- :66-81, the isTv branch against the one below it).
	--
	-- AND WHAT THE STATION IS DOING WITH THE DAY, which is the half a program
	-- needs and a survivor cannot get from the set: `airing 720-1080` is a
	-- broadcast that is on now and the block it belongs to, `next 1080-1440` is
	-- when the following one starts, and `idle` is a channel with nothing left
	-- today. The words and the units are CeroSecOS.tunerDetailText's and the
	-- reading is CeroSecRadio's, which is the only file that asks the game
	-- anything about a radio.
	--
	-- Why it rides in the DETAIL and not in a column of its own: `dev` prints a
	-- table on a terminal 60 wide that does not wrap, the state column is a word
	-- wide, and a TV-only column would be blank on every other row in the
	-- building. `cat /dev/tv0` and `dev tv0` read the whole line, exactly as a
	-- generator's has since the motor rung, and no listing grew a column.
	if kind == "tv" or kind == "rx" then
		local data = waveData(object)
		if data == nil then return nil end
		local channel = math.floor(data:getChannel())
		return CeroSecOS.tunerDetailText(channel,
			CeroSecRadio.scheduleOf(channel, kind == "tv"))
	end

	if kind ~= "gen" then return nil end
	-- Percentages, both of them, because a survivor reading `fuel 62` against a
	-- tank whose size he does not know has been told nothing. getFuelPercentage
	-- is the engine's own, and getCondition() is already 0 to 100.
	local text = "fuel " .. pct(object:getFuelPercentage())
		.. " condition " .. pct(object:getCondition())
	-- The third word is a fact and not a number, so it is there or it is not --
	-- which is how a real status line said a boolean.
	if object:isConnected() then text = text .. " connected" end
	return text
end

-- Which of the three the laundry is. Named rather than worked out on the far
-- side, because the client's outline asks the engine's own instanceof and a
-- guess between three classes is two wrong answers (see classOf).
local function washerClass(object)
	if instanceof(object, "IsoClothingWasher") then return "IsoClothingWasher" end
	if instanceof(object, "IsoClothingDryer") then return "IsoClothingDryer" end
	return "IsoCombinationWasherDryer"
end

function CeroSecDevices.classify(object)
	if object == nil then return nil end

	if instanceof(object, "IsoLightSwitch") then
		-- No relay, no light. Not a light switch that refuses: a light switch the
		-- machine has never heard of, which is what an unwired one is.
		local fitted = fittedOn(object)
		if not has(fitted, "relay") then return nil end
		return { {
			kind = "light", side = "",
			desc = roomName(object:getSquare()) or "exterior",
			state = stateOf("light", object),
		} }
	end

	if instanceof(object, "IsoDoor") then
		local fitted = fittedOn(object)
		local side = object:getNorth() and "N" or "W"
		local desc = doorDesc(object)
		local locks = doorLocks(object)
		local out = {}
		-- The operator is what MOVES a door and the contact is what sees it, so a
		-- door with only a contact on it is the same doorN with the same words
		-- and no way to carry them out (`ro`): it reads open, closed or locked,
		-- and every write to it is "operation not supported".
		local moves, sees = has(fitted, "operator"), has(fitted, "contact")
		if (moves or sees) and not isManyDoors(object) then
			out[#out + 1] = { kind = "door", side = side, desc = desc,
				locks = locks, state = stateOf("door", object, locks), ro = not moves }
		end
		if locks and has(fitted, "strike") then
			out[#out + 1] = { kind = "lock", side = side, desc = desc,
				state = stateOf("lock", object) }
		end
		-- A door's curtain is a pair of FIELDS on the door and not a second
		-- object, so a door with a sheet on it is a third device on one object
		-- (CeroSecModules.doorHasCurtain). `cls` is what the client is told to
		-- look for when `dev find` outlines it: a door, because that is what it
		-- is.
		if CeroSecModules.doorHasCurtain(object) and has(fitted, "curtain") then
			out[#out + 1] = { kind = "curtain", cls = "IsoDoor", side = side,
				desc = desc, state = stateOf("curtain", object) }
		end
		return out
	end

	-- A window's curtain and a built frame's are an object of their OWN, on the
	-- square's list like any other fixture -- IsoGridSquare.AddSpecialObject puts
	-- a curtain on `objects` as well as on `specialObjects` (offsets 25-65), so
	-- the walk that is already here finds it and nothing needs a second scan.
	if instanceof(object, "IsoCurtain") then
		local fitted = fittedOn(object)
		if not has(fitted, "curtain") then return nil end
		return { {
			kind = "curtain", cls = "IsoCurtain",
			side = object:getNorth() and "N" or "W",
			desc = roomName(object:getSquare()) or "exterior",
			state = stateOf("curtain", object),
		} }
	end

	-- The oven, the microwave and the coffee machine: one class, because
	-- isMicrowave() and isStove() read the CONTAINER's type and the map's
	-- GroupName = Coffee tiles carry IsoType = IsoStove with container = stove.
	if instanceof(object, "IsoStove") then
		local fitted = fittedOn(object)
		if not has(fitted, "appliance") then return nil end
		return { {
			kind = "stove", cls = "IsoStove", side = "",
			desc = roomName(object:getSquare()) or "exterior",
			state = stateOf("stove", object),
		} }
	end

	if instanceof(object, "IsoGenerator") then
		local fitted = fittedOn(object)
		if not has(fitted, "genset") then return nil end
		return { {
			kind = "gen", cls = "IsoGenerator", side = "",
			-- A generator stands outside more often than in, and a room name is
			-- the only thing that tells two of them apart on one machine.
			desc = roomName(object:getSquare()) or "exterior",
			state = stateOf("gen", object),
			detail = detailOf("gen", object),
		} }
	end

	-- The television and the radio SET, which are siblings and not one class:
	-- IsoTelevision and IsoRadio both extend IsoWaveSignal and neither is the
	-- other, so they are asked apart and they are two kinds. A survivor does not
	-- think of a television and a radio as one thing, and the schedule behind them
	-- is a different list on each (RadioChannel.IsTv).
	--
	-- A set with no DeviceData on it is not a device at all: the switch and the
	-- dial live on that object and there is nothing else to write. The test is
	-- CeroSecModules.isTuneable's, asked there so the install and the discovery
	-- cannot disagree about what a set is.
	-- ONE test for the pair, and the line is worth its own call: classify is asked
	-- about every object on every square of the building at every command -- the
	-- walls, the floors, the furniture -- and IsoWaveSignal is the base both
	-- classes extend, so a wall costs ONE instanceof here instead of two. What
	-- that is worth is the number hostile_test.lua's mall bench prints. It is the
	-- same reasoning fittedOn is written on, one branch up.
	--
	-- `IsoWaveSignal` is a base class and instanceof answers for a subclass: it is
	-- the test vanilla's own Lua makes of a world object, on the server included
	-- (server/ISObjectClickHandler.lua:240, client/ISUI/ISRadioAndTvMenu.lua:7,
	-- shared/Moveables/ISMoveableSpriteProps.lua:1389).
	if instanceof(object, "IsoWaveSignal") then
		local fitted = fittedOn(object)
		if not has(fitted, "tuner") then return nil end
		if CeroSecModules.isTelevision(object) then
			return { {
				kind = "tv", cls = "IsoTelevision", side = "",
				desc = roomName(object:getSquare()) or "exterior",
				state = stateOf("tv", object),
				detail = detailOf("tv", object),
			} }
		end
		-- And the receiver. It does NOT take the TNC's place: a ham set in the
		-- machine's own room is still /dev/radio0, read-only, because the frequency
		-- an aerial TRANSMITS on is the survivor's (SCeroSecRadio.lua, proof 7).
		-- What a tuner control buys is the set's own switch and its own dial as a
		-- RECEIVER, and the two hang on two keys -- `radio:x:y:z::0` and
		-- `rx:x:y:z::0` -- so neither number moves because the other exists.
		if CeroSecModules.isRadioSet(object) then
			return { {
				kind = "rx", cls = "IsoRadio", side = "",
				desc = roomName(object:getSquare()) or "exterior",
				state = stateOf("rx", object),
				detail = detailOf("rx", object),
			} }
		end
		-- An IsoWaveSignal that is neither, or one with no device data on it: a
		-- sprite with nothing to switch and nothing to tune.
		return nil
	end

	-- The laundry, and the class is carried because there are three of them and
	-- `dev find` has to tell the client which to look for.
	if CeroSecModules.isWasher(object) then
		local fitted = fittedOn(object)
		if not has(fitted, "appliance") then return nil end
		return { {
			kind = "washer", cls = washerClass(object), side = "",
			desc = roomName(object:getSquare()) or "exterior",
			state = stateOf("washer", object),
		} }
	end

	if instanceof(object, "IsoWindow") then
		local fitted = fittedOn(object)
		local side = object:getNorth() and "N" or "W"
		local desc = roomName(object:getSquare()) or "exterior"
		local out = {}
		-- TWO DEVICES ON ONE WINDOW, and it is the door's own shape: doorN is what
		-- opens and lockN is the key, and here winN is the catch a magnetic
		-- contact senses and windowN is the sash a motor moves. Two vocabularies,
		-- so two kinds -- a window that took `lock`, `unlock`, `open` and `close`
		-- on one node would be a node whose mode could not say which of them it
		-- could carry out.
		--
		-- winN stays READ-ONLY and the reason is not the one it used to give. It
		-- is not that no call moves a sash: the corrected version is at
		-- CeroSecModules.fitsOn, and the short of it is that a magnetic contact is
		-- a sensor and senses. The latch is the survivor's, or the operator's on
		-- its way past (ToggleWindow clears `locked` at offsets 50-54).
		if has(fitted, "contact") then
			out[#out + 1] = { kind = "win", cls = "IsoWindow", side = side, desc = desc,
				state = stateOf("win", object), ro = fitted ~= nil }
		end
		if has(fitted, "window") then
			out[#out + 1] = { kind = "window", cls = "IsoWindow", side = side,
				desc = desc, state = stateOf("window", object) }
		end
		return out
	end

	-- Player-built. A base has no building and no rooms, so there is no room id
	-- to name it with and "built" is the truth about it. Only doors: a
	-- player-built window frame has no lock this rung.
	if instanceof(object, "IsoThumpable") and object:isDoor() then
		local fitted = fittedOn(object)
		local side = object:getNorth() and "N" or "W"
		local out = {}
		local moves, sees = has(fitted, "operator"), has(fitted, "contact")
		if (moves or sees) and not isManyDoors(object) then
			out[#out + 1] = { kind = "door", side = side, desc = "built",
				locks = true, state = stateOf("door", object, true), ro = not moves }
		end
		if has(fitted, "strike") then
			out[#out + 1] = { kind = "lock", side = side, desc = "built",
				state = stateOf("lock", object) }
		end
		return out
	end

	return nil
end

--
-- Where it is
--
-- Room ids repeat -- a big house has three doors whose description is the same
-- word -- so the thing that tells two devices apart is where they are, and that
-- is what this column is: how far east or west of the machine, how far north or
-- south, and the floor when it is not the machine's own.
--
--   3E 2N      three tiles east and two north of the computer
--   0 2N       due north of it
--   0 0        its own square
--   3E 2N +1   one floor up
--
-- The axes are the game's own: x grows to the EAST and y grows to the SOUTH
-- (IsoGridSquare's getX/getY, the same pair every vanilla direction helper
-- reads), so a device with a smaller y than the machine's is north of it. Both
-- halves are always printed, a zero as a bare "0", so the column reads as one
-- shape and never as a sentence.
--
-- Pure arithmetic, and deliberately: it is the one part of a device's line that
-- can be proved without a world under it (tests/window_test.lua).
function CeroSecDevices.offset(dx, dy, dz)
	local east = "0"
	if dx > 0 then
		east = tostring(dx) .. "E"
	elseif dx < 0 then
		east = tostring(-dx) .. "W"
	end

	local north = "0"
	if dy > 0 then
		north = tostring(dy) .. "S"
	elseif dy < 0 then
		north = tostring(-dy) .. "N"
	end

	local out = east .. " " .. north
	if dz > 0 then
		out = out .. " +" .. tostring(dz)
	elseif dz < 0 then
		out = out .. " " .. tostring(dz)
	end
	return out
end

--
-- Finding them
--

-- The sensors lying on one square. Not classify's business: a dropped item is not
-- on the square's object list at all -- it is an IsoWorldInventoryObject on
-- getWorldObjects() -- so it is walked here, beside the other list and not inside
-- it. Everything about what makes one a sensor is in SCeroSecSensors.lua.
local function scanWorldItems(square, found, seen, x, y, z)
	local sensors = CeroSecSensors.onSquare(square)
	for i = 1, #sensors do
		local sensor = sensors[i]
		local entry = {
			kind = "sensor", side = "",
			-- A dropped head is the player's own doing wherever it lies, so the
			-- room names it where there is one and "built" does where there is
			-- not -- the same word a player-built door wears.
			desc = roomName(square) or "built",
			x = x, y = y, z = z, object = sensor.object,
			range = sensor.range,
			-- Which of the heads on this tile it is. Carried because the sampling
			-- book is keyed by it too, and both have to mean the same thing.
			n = i - 1,
		}
		local base = "sensor:" .. x .. ":" .. y .. ":" .. z .. ":"
		local n = 0
		while seen[base .. ":" .. n] do n = n + 1 end
		entry.key = base .. ":" .. n
		seen[entry.key] = true
		found[#found + 1] = entry
	end
end

-- Where one OBJECT was put on the list, as a key of `seen`, so that a walk which
-- reaches the same object twice adds it once.
--
-- It cannot collide with a device key, which is `kind:x:y:z:side:n`: no kind is
-- called "at", and the kinds are a closed list in CeroSecOS.DEV_VALUES. What is
-- filed under it is the LIST of entries that came off the object, because the
-- second reader is the link walk and what it needs is not "was this done" but the
-- entries themselves -- a fixture in the building AND on the end of a cable is one
-- device that has a wire, not two devices.
local function placeKey(x, y, z, index)
	return "at:" .. x .. ":" .. y .. ":" .. z .. ":" .. index
end

-- One object, as the devices it is, onto the walk's own list. Its place is the
-- square it STANDS on and not the square it was reached from: that is what the
-- key hangs on and what `alive` re-asks the engine for.
local function addDevices(object, index, x, y, z, found, seen)
	-- A list, because one object can be two devices: an exterior door is
	-- what opens AND what locks.
	local entries = CeroSecDevices.classify(object) or {}
	for k = 1, #entries do
		local entry = entries[k]
		entry.x, entry.y, entry.z = x, y, z
		entry.object = object
		-- WHICH of the square's objects it is, kept for one kind of device and
		-- one only: a television or a radio set whose state this mod has to
		-- broadcast itself, because the far end has to find the same object
		-- again and two identical televisions on one tile are the one case a
		-- class and a sprite name cannot tell apart (CCeroSecDevices.objectAt).
		-- It is not a key and cannot be one -- the object index is not stable
		-- across a reload, which is why `seen` counts ordinals instead -- and it
		-- is not asked of anything else.
		entry.index = index
		-- Where it is, as a string, and that is the key its number hangs
		-- on. Two devices of one kind facing the same way on one square are
		-- told apart by an ordinal -- the object index would have done it
		-- too, and it is not stable across a reload. The kind is in the key,
		-- so door3 and lock1 on the same door hang on two keys and neither
		-- number moves when the other kind's numbering changes.
		local base = entry.kind .. ":" .. x .. ":" .. y .. ":" .. z .. ":" .. entry.side
		local n = 0
		while seen[base .. ":" .. n] do n = n + 1 end
		entry.key = base .. ":" .. n
		seen[entry.key] = true
		found[#found + 1] = entry
	end
	-- And the object itself, under where it stands (placeKey), for the walk that
	-- comes after this one: the link walk visits squares the building walk may
	-- already have covered, and a fixture found twice would be two devices with two
	-- numbers -- the ordinal in a key is handed out per square.
	if #entries > 0 then seen[placeKey(x, y, z, index)] = entries end
	return entries
end

-- Everything on one square, and the square's own place answered back: the
-- far-edge walk below needs those three numbers to find the two neighbours, and
-- there is no reason to ask the square twice. nil for a square that is not there.
local function scanSquare(square, found, seen)
	if square == nil then return end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	scanWorldItems(square, found, seen, x, y, z)
	local objects = square:getObjects()
	if objects == nil then return x, y, z end
	for i = 0, objects:size() - 1 do
		addDevices(objects:get(i), i, x, y, z, found, seen)
	end
	return x, y, z
end

--
-- The far edge of a room, which is a fixture standing on somebody else's square
--
-- A WALL OBJECT BELONGS TO ONE SQUARE AND SITS ON THAT SQUARE'S NORTH OR WEST
-- EDGE. `IsoDoor.getOppositeSquare` is the whole of it: `getNorth()` then
-- getGridSquare(x, y - 1, z), else getGridSquare(x - 1, y, z) (javap -c, offsets
-- 0-56). `IsoWindow`'s and `IsoThumpable`'s are `getInsideSquare()`, the same
-- pair off the `north` field (offsets 9-77 of each), and `IsoCurtain`'s reads its
-- sprite TYPE and answers all four -- curtainN north, curtainS south, curtainW
-- west, curtainE east, nil for a sprite that is none of them (offsets 0-141).
--
-- So a door in a room's north or west wall stands on the room's OWN square and
-- the walk above finds it, while a door in the room's south or east wall stands
-- on the NEIGHBOURING square -- which for an exterior wall is the pavement, in no
-- room at all, and a square the walk of the building's rooms never visits. That
-- was every south and east door, window and sheet of every building on the map,
-- invisible to /dev while the north and west ones were listed: a machine that saw
-- the back door and not the front one.
--
-- WHAT IS TAKEN OFF A NEIGHBOUR is a fixture that is ON THAT WALL: a door, a
-- window or a curtain, which IS the wall, and a light switch or lamp, which hangs
-- on it. A generator on the sidewalk is not the building's and neither is a sensor
-- dropped there, so the class gate and the boundary test below are what keep the
-- pavement out; and the far side of the next wall along is kept out by the second
-- of the two, which is the engine's own answer to which wall a thing is on.
--
-- AND ONLY WHERE THE NEIGHBOUR IS IN NO ROOM. A neighbour that is in a room is a
-- square the walk visits in its own right, so an INTERIOR door is found from the
-- other side and must not be found here as well: the ordinal in a key is handed
-- out per square, so one object reached twice would be two devices with two
-- numbers. It is the same rule the lock reads -- exactly one of a door's two sides
-- has a room -- read from the room's end.
--
-- That is also why this belongs to the building branch and not to scanSquare: the
-- no-building branch walks every square of its block, room or not, so a base's
-- south wall already stands on a square that walk visits.
--
-- The one fixture it does not reach is a wall shared by two BUILDINGS -- the
-- neighbour is the other building's room, so it is that building's machine that
-- lists the door. See docs/DEVICES.md.
local function isWallFixture(object)
	return CeroSecModules.isDoor(object) or CeroSecModules.isWindow(object)
		or CeroSecModules.isCurtain(object) or CeroSecModules.isLightSwitch(object)
end

-- Which of the four `attached` properties of a HUNG fixture would point at
-- `square`, given the square it stands on. nil for anything that is not one of the
-- four neighbours.
--
-- A light does not have an opposite square: it is not the wall, it is screwed to
-- one, and the sprite is what says which. Vanilla reads exactly these four
-- properties in exactly this order to work out where a survivor has to stand to
-- reach a light (`ISWorldObjectContextMenu.lua:1348-1352`, `onToggleLight`:
-- attachedN -> IsoDirections.N and so on, then AdjacentFreeTileFinder.FindEdge).
--
-- AND IT IS WHAT TELLS A PORCH LAMP FROM A LAMPPOST. The Round Outdoor Lamp of the
-- screenshot is `MoveType = WallObject` with `attachedN` and `Facing = S` --
-- newtiledefinitions.tiles.txt, tileset lighting_outdoor_01, tile 24 -- so it
-- stands on the pavement square and hangs on that square's north edge, which is
-- the house's south wall. The county's street lighting has no `attached` property
-- of any kind and carries `streetlight` instead (tile 0 of the same tileset), and
-- the flood lights have neither. So a lamp on the building is found and a lamp on
-- a post two tiles away is not, and neither answer is a guess about a sprite name.
--
-- `props:has("attachedN")` is the STRING overload and it really answers: PropertyContainer
-- has five `has` overloads, Kahlua's MultiLuaJavaInvoker picks the one whose
-- argument types match (matchesArgumentTypes, offsets 42-49), and `has(String)`
-- puts the name through TilePropertyAliasMap.getIDFromPropertyName -- which
-- registers every name the tile definitions use under
-- IsoPropertyType.lookupOrDefaultStr, and ATTACHED_N's own name is the literal
-- "attachedN" (javap -c zombie.core.properties.IsoPropertyType, offset 1281). An
-- unknown name answers -1 and `containsKey((short) -1)`, which is false.
local function attachedFlag(x, y, z, square)
	if square:getZ() ~= z then return nil end
	local dx, dy = square:getX() - x, square:getY() - y
	if dx == 0 and dy == -1 then return "attachedN" end
	if dx == 0 and dy == 1 then return "attachedS" end
	if dx == -1 and dy == 0 then return "attachedW" end
	if dx == 1 and dy == 0 then return "attachedE" end
	return nil
end

-- AND THE OTHER HALF OF THE SAME QUESTION, because eight of the county's twenty
-- outdoor wall lamps do not answer the first one.
--
-- The `attached` property is what vanilla reads and it is read first, above. But
-- the tile definitions are not consistent with it: of the twenty
-- `CustomName = Outdoor Lamp` tiles in lighting_outdoor_01, twelve carry the
-- attached flag OPPOSITE their `Facing` -- a lamp facing south hangs on the wall to
-- its north -- and eight do not. Every Round and every Antique lamp drawn facing
-- NORTH carries `attachedW` (tiles 28 and 30), and every one drawn facing WEST
-- carries `attachedN` (29 and 31); the Oval pair is crossed the same way (44, 45).
-- So a Round Outdoor Lamp on the north wall of a house hangs on a wall the property
-- says is to its west, and the rule above looks for it on the wrong side.
--
-- `Facing` does not have that problem, and the reason is what a lamp IS: it faces
-- away from the thing it is screwed to. So the second reading is the first one
-- turned round -- the wall is on the OPPOSITE side of `Facing` -- and it is asked
-- only of a sprite the engine itself calls a wall object:
--
--   MoveType = WallObject   every one of the twenty lamps, and no lamppost
--   Facing = N|S|W|E        every one of the twenty, and the four flood lights
--   streetlight             every lamppost, and none of the twenty
--
-- which is what keeps the two things that are NOT on the building out. A lamppost
-- carries neither `Facing` nor `MoveType` and is refused by both readings, as it
-- was before. A FLOOD LIGHT carries `Facing` and no `MoveType` -- it is a movable
-- light on a tripod, `LightRadius = 24`, `IsMoveAble`, tiles 48-51 -- so it is
-- refused by the MoveType half: a floodlight standing against a wall is not screwed
-- to it, and the day somebody carries it away the building has not lost a fixture.
--
-- `props:get(name)` is the value and `null` for a property the sprite has not
-- (PropertyContainer.get(String), offsets 0-32, through the same alias map
-- `has` uses).
-- Where the WALL is, per Facing: the square on the other side of the lamp from
-- the way it points. A lamp facing south has its back to the square north of it.
local FACING_BACK = { N = { 0, 1 }, S = { 0, -1 }, W = { 1, 0 }, E = { -1, 0 } }

-- Is this hung fixture's BACK to `square`? props is the sprite's, already read by
-- the caller.
--
-- `has` before `propertyEquals`, and not for tidiness: propertyEquals is
-- get(name) into StringUtils.equalsIgnoreCase (offsets 0-9) and get answers null
-- for a property the sprite has not got, so the guard is what makes the null
-- impossible rather than a thing to hope about.
local function backsOnto(x, y, z, square, props)
	if not props:has("MoveType") then return false end
	if not props:propertyEquals("MoveType", "WallObject") then return false end
	local facing = props:get("Facing")
	if type(facing) ~= "string" then return false end
	local back = FACING_BACK[facing]
	if back == nil then return false end
	if square:getZ() ~= z then return false end
	return square:getX() - x == back[1] and square:getY() - y == back[2]
end

-- Is this fixture on the boundary between the square it stands on (x, y, z) and
-- `square`? Two questions, because the engine keeps the answer in two places.
--
-- A door, a window and a curtain ARE the wall, and their own getOppositeSquare
-- says which boundary that is -- the engine deciding rather than a reading of
-- `north` of ours, which is what a curtain's four types are about. Compared by
-- PLACE and not by handle: two Lua values for one Java square need not be one
-- value, and x, y and z are what every key in this file is made of.
--
-- A light HANGS on the wall, has no opposite square at all -- there is no
-- getOppositeSquare on IsoObject, and IsoLightSwitch has no `north` either -- and
-- carries one of the four properties above instead.
local function faces(object, x, y, z, square)
	if CeroSecModules.isLightSwitch(object) then
		local sprite = object:getSprite()
		local props = nil
		if sprite ~= nil then props = sprite:getProperties() end
		if props == nil then return false end
		-- Vanilla's own reading first, and then the one the tile definitions make
		-- necessary (backsOnto): eight of the county's twenty outdoor lamps point
		-- their `attached` property at a wall that is not the one they hang on.
		local flag = attachedFlag(x, y, z, square)
		if flag ~= nil and props:has(flag) == true then return true end
		return backsOnto(x, y, z, square, props)
	end
	local opposite = object:getOppositeSquare()
	if opposite == nil then return false end
	return opposite:getX() == square:getX()
		and opposite:getY() == square:getY()
		and opposite:getZ() == square:getZ()
end

-- `hungOnly` is the two neighbours added by the porch-lamp report: see scanFarEdges.
local function scanFarEdge(square, neighbour, found, seen, hungOnly)
	if neighbour == nil then return end
	if neighbour:getRoom() ~= nil then return end
	local objects = neighbour:getObjects()
	if objects == nil then return end
	local x, y, z = neighbour:getX(), neighbour:getY(), neighbour:getZ()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local mine
		if hungOnly then
			mine = CeroSecModules.isLightSwitch(object)
		else
			mine = isWallFixture(object)
		end
		if mine and faces(object, x, y, z, square) then
			addDevices(object, i, x, y, z, found, seen)
		end
	end
end

-- The four squares a room square's walls can be reached from, and they are not
-- symmetrical.
--
-- TWO OF THEM CARRY A WALL. A door, a window and a curtain ARE the wall and the
-- wall is on its own square's north or west edge, so the wall between a room
-- square and its SOUTH neighbour stands on that neighbour, and so does the wall
-- between it and its EAST neighbour. The north and west walls stand on the room's
-- own square and scanSquare has them already.
--
-- AND ALL FOUR CARRY A LAMP, which is what the porch-lamp report turned out to be
-- about. A light does not stand on a wall, it HANGS on one, and it hangs on the
-- outside: a lamp on the house's south wall is on the pavement south of the room
-- (found by the first of the two above), and a lamp on the house's NORTH wall is on
-- the pavement NORTH of it -- a square no walk of this mod ever visited. Every
-- north-wall and west-wall porch lamp in the county was therefore invisible to
-- /dev, with a relay on it and everything else on the building listed: exactly the
-- report, and the far-edge rule of 0.4.1 fixed the doors and only half the lamps.
--
-- So the north and the west neighbour are walked for HUNG fixtures only. It is a
-- narrower gate than the other two on purpose and not to save the walk: a door on
-- one of those squares is that NEIGHBOUR's wall and not this room's, and taking it
-- would be a machine listing the house next door's front door.
local function scanFarEdges(cell, square, x, y, z, found, seen)
	scanFarEdge(square, cell:getGridSquare(x, y + 1, z), found, seen, false)
	scanFarEdge(square, cell:getGridSquare(x + 1, y, z), found, seen, false)
	scanFarEdge(square, cell:getGridSquare(x, y - 1, z), found, seen, true)
	scanFarEdge(square, cell:getGridSquare(x - 1, y, z), found, seen, true)
end

-- The machine's TNC, added to whatever the walk found. It is not discovered by
-- the walk and must not be: the radio's reach is its OWN -- the machine's room,
-- or a tile around it in a base -- and it is narrower than either branch below,
-- because a TNC is a box with a foot of cable to the set and not a thing that
-- works across a building. The rule and every game call behind it are in
-- SCeroSecRadio.lua.
--
-- One entry at the most, because a machine has one serial port. A radio already
-- found at that key -- which cannot happen, radios not being on the walk -- is
-- left alone, so the belt is the same one scanSquare wears.
local function withTnc(found, seen, x, y, z)
	local entry = CeroSecRadio.entryAt(x, y, z)
	if entry == nil then return found end
	if seen[entry.key] then return found end
	seen[entry.key] = true
	found[#found + 1] = entry
	return found
end

-- Every square of a building, handed over one at a time, and whether the walk saw
-- ALL OF IT.
--
-- Every room of the building, through its definition: BuildingDef getRooms() is an
-- ArrayList of RoomDef (the way media/lua/shared/Util/BuildingHelper.lua reads it),
-- and a RoomDef answers getIsoRoom() with the live room -- nil while its chunks are
-- not loaded, which is a room the machine cannot act on.
--
-- The second answer is what a room like that costs, and its caller is the device
-- walk below: /dev is what the machine can reach RIGHT NOW, so a room that was
-- away is a room whose doors are not on the machine. `false` therefore means "a
-- room of this building was not in the world", which is a different thing from
-- "the building has no rooms".
local function eachBuildingSquare(building, fn)
	local def = building:getDef()
	local rooms = nil
	if def ~= nil then rooms = def:getRooms() end
	if rooms == nil then return false end
	local whole = true
	for i = 0, rooms:size() - 1 do
		local room = rooms:get(i):getIsoRoom()
		if room == nil then
			whole = false
		else
			local squares = room:getSquares()
			if squares == nil then
				whole = false
			else
				for j = 0, squares:size() - 1 do
					fn(squares:get(j))
				end
			end
		end
	end
	return whole
end

--
-- The far edge again, for the pre-fitting walk
--
-- The same rule the device walk reads (scanFarEdges, above) and the same reason
-- read one rung earlier: a pre-apocalypse premises' front door stands on the
-- pavement south of the hall as often as on the hall's own square, and one of the
-- two was never wired at all.
--
-- The square handed back is the ROOM's and not the one the door stands on,
-- because what the caller does with it is ask which PREMISES the fixture belongs
-- to (SCeroSecAuto's sift, through CeroSecNet.premisesOfSquare): a front door
-- belongs to the premises it opens into, and its own square is the street.
--
-- `isWallFixture` is a narrower gate than the walk's `isFittable` and lies inside
-- it: every door, window, curtain and light switch is fittable, and the stove, the
-- laundry, the generator and the sets are on nobody's wall -- a fridge a survivor
-- dragged onto the pavement is not part of the premises.
local function fittableFarEdge(square, neighbour, out, hungOnly)
	if neighbour == nil then return end
	if neighbour:getRoom() ~= nil then return end
	local objects = neighbour:getObjects()
	if objects == nil then return end
	local x, y, z = neighbour:getX(), neighbour:getY(), neighbour:getZ()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local mine
		if hungOnly then
			mine = CeroSecModules.isLightSwitch(object)
		else
			mine = isWallFixture(object)
		end
		if mine and faces(object, x, y, z, square) then
			out[#out + 1] = { object = object, square = square }
		end
	end
end

-- Every FIXTURE a module of ours could go on in at most `max` of these rooms, and
-- the tags of the rooms it actually walked.
--
-- Here rather than in the automation that wants it because the walk is this file's
-- rule: a fixture is a thing on a square of a room, and there is one place that
-- says how to find one. WHICH rooms is the caller's, and it is the premises' own
-- (CeroSecAuto) -- a shop in a mall is one tenancy of thirty and the other
-- twenty-nine are somebody else's rooms.
--
-- `done` is the set of room tags already walked in an earlier minute and `max` is
-- how many may be walked in this one. A room whose chunks are away answers no live
-- room and is simply left for a later minute: it costs nothing and does NOT count
-- against `max`, because nothing was walked. That is the whole of what makes the
-- pre-fitting converge -- a five-hundred-room mall is never in the world at once,
-- so "every room answered in one pass" never happened and the mall was re-walked
-- every game minute for ever (see the head of CeroSecAuto.wire).
function CeroSecDevices.fixturesInRooms(rooms, done, max)
	local out, walked = {}, {}
	if rooms == nil or done == nil then return out, walked end
	-- No cell is a world that cannot be asked about a neighbouring square at all,
	-- which is a bench and never a game: the rooms' own squares are still walked.
	local cell = nil
	if getCell ~= nil then cell = getCell() end
	for i = 1, #rooms do
		if #walked >= max then return out, walked end
		local room = rooms[i]
		local tag = room.tag
		if tag ~= nil and not done[tag] and room.def ~= nil and room.def.getIsoRoom ~= nil then
			local live = room.def:getIsoRoom()
			local squares = live ~= nil and live:getSquares() or nil
			if squares ~= nil then
				for j = 0, squares:size() - 1 do
					local sq = squares:get(j)
					if sq ~= nil then
						local objects = sq:getObjects()
						if objects ~= nil then
							for k = 0, objects:size() - 1 do
								local object = objects:get(k)
								if CeroSecModules.isFittable(object) then
									out[#out + 1] = { object = object, square = sq }
								end
							end
						end
						if cell ~= nil then
							local sx, sy, sz = sq:getX(), sq:getY(), sq:getZ()
							fittableFarEdge(sq, cell:getGridSquare(sx, sy + 1, sz), out, false)
							fittableFarEdge(sq, cell:getGridSquare(sx + 1, sy, sz), out, false)
							-- And the two that carry a LAMP and no wall of this room: a
							-- premises' own porch light was wired in 1991 exactly as its
							-- front door was (scanFarEdges).
							fittableFarEdge(sq, cell:getGridSquare(sx, sy - 1, sz), out, true)
							fittableFarEdge(sq, cell:getGridSquare(sx - 1, sy, sz), out, true)
						end
					end
				end
				-- Walked, and never walked again: the tag goes into the premises'
				-- own record and the caller writes it there.
				walked[#walked + 1] = tag
			end
		end
	end
	return out, walked
end

--
-- THE OTHER WAY A FIXTURE IS ON A MACHINE: somebody ran a cable to it
--
-- The building is free and it is also the whole of what the two walks above can
-- reach. A lamppost on the street, a gate at the end of the drive, a lamp on a wall
-- the room walk does not touch, a fixture in the shop across the car park: none of
-- those is in any room of the machine's building, and a survivor who wants one on
-- /dev does what an electrician would do -- he runs a cable
-- (CeroSecModules.LINK_KEY, and Commands.linkmodule).
--
-- WHY THE MACHINE KEEPS A LIST. The cable is written on the fixture, because that
-- is where the modules live and where the refund is owed. But `find` cannot start
-- from the fixture: asking "which fixture in Knox County names this machine" is a
-- walk of the county, once a second, for ever. So the link is written on BOTH sides
-- and the machine's side is a list of SQUARES (state.links): the walk visits
-- exactly those, which is at most CeroSecOS.LINKS_PER_MACHINE of them.
--
-- WHAT KEEPS THE TWO IN STEP is this walk, and nothing else has to. An entry whose
-- square is loaded and carries no cable to this machine is DROPPED -- the fixture
-- was unlinked from the other side, or replaced, or a later build wrote a modData
-- table this one will not read -- and the answer goes back to the caller to be
-- written into the state. An entry whose square is NOT loaded is kept exactly as it
-- is: a cable in a street nobody is standing in is still a cable, and a machine
-- that forgot one because the chunk was away would be a machine that charged for a
-- cable and then took it away.
--
-- A FIXTURE THAT IS BOTH IN THE BUILDING AND ON A CABLE is one device and not two.
-- The building walk got there first, so the entries are already on the list under
-- their own numbers; what this adds to them is the `wire`, which is the one thing
-- only the cable knows (see placeKey).
local function scanLinked(cell, links, found, seen, mx, my, mz)
	local kept = {}
	if type(links) ~= "table" then return kept end
	for i = 1, #links do
		local at = links[i]
		if type(at) == "table" and type(at.x) == "number" and type(at.y) == "number"
				and type(at.z) == "number" and #kept < CeroSecOS.LINKS_PER_MACHINE then
			local square = cell:getGridSquare(at.x, at.y, at.z)
			if square == nil then
				kept[#kept + 1] = { x = at.x, y = at.y, z = at.z }
			else
				local objects = square:getObjects()
				local cabled = false
				if objects ~= nil then
					for k = 0, objects:size() - 1 do
						local object = objects:get(k)
						-- The fixture's own end of the cable, which is what makes this
						-- self-healing in both directions: the square is asked, not
						-- believed.
						local wire = CeroSecModules.wireOf(object, mx, my, mz)
						if wire ~= nil then
							cabled = true
							local already = seen[placeKey(at.x, at.y, at.z, k)]
							if already == nil then
								already = addDevices(object, k, at.x, at.y, at.z, found, seen)
							end
							for e = 1, #already do already[e].wire = wire end
						end
					end
				end
				-- Nothing on that square names this machine any more: the cable is gone
				-- and so is the entry. A fixture whose MODULE came off keeps its cable
				-- and stays on the list -- the wire is still run, and what it reaches is
				-- a fixture with no device on it.
				if cabled then kept[#kept + 1] = { x = at.x, y = at.y, z = at.z } end
			end
		end
	end
	return kept
end

--
-- The radius walk, which is not the building walk
--

-- The four neighbours of a square, in the order scanFarEdges reads them.
local AROUND = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }

-- Is this wall fixture on the boundary of a square the map gives a ROOM to?
--
-- The question the radius walk has to ask and the building walk never had to. A
-- door, a window and a curtain ARE the wall and stand on one of the two squares
-- they divide -- their own getOppositeSquare says which (scanFarEdges above) --
-- so a house's front door stands on the PAVEMENT and the pavement is in no room
-- at all. A lamp hangs on the wall from the outside and stands there too. Room
-- test on the square, therefore, is not enough: the fixture is the house's while
-- the square under it is nobody's.
--
-- Asked through `faces`, which is the same reading the building walk uses from
-- the room's end -- the engine's opposite square for the three that are the wall
-- and the `attached`/`Facing` pair for a hung light -- so the two ends agree on
-- which wall a thing is on. A lamppost or a dropped generator faces nothing and
-- is kept.
local function facesARoom(cell, object, x, y, z)
	for i = 1, #AROUND do
		local at = AROUND[i]
		local neighbour = cell:getGridSquare(x + at[1], y + at[2], z)
		if neighbour ~= nil and neighbour:getRoom() ~= nil
				and faces(object, x, y, z, neighbour) then
			return true
		end
	end
	return false
end

-- One square of the ten-tile fallback, and what it is NOT allowed to take.
--
-- The report this is from: a computer set down outside a house, five squares
-- away, wired to nothing, listing every device of that house. The radius is the
-- answer for a place with no building -- a player base -- and a building
-- belongs to its own machine or to a cable, never to whoever stands near it.
--
-- `getRoom() ~= nil` is the ownership test and it is the wider of the two the
-- engine has: getBuilding() is getRoom() and then IsoRoom.getBuilding (javap -c
-- zombie.iso.IsoGridSquare.getBuilding, offsets 0-15), so a square with a
-- building is always a square with a room while a mapped room whose building the
-- metagrid never set is caught here too.
--
-- AND NOT isInARoom(), which is the trap: that one is
-- `getRoom() != null || getIsoWorldRegion().isPlayerRoom()` (offsets 0-31), and
-- a player-built base answers true on the second half. Reading it here would
-- take a base's own radius away from it -- the very machine the radius exists
-- for -- while closing nothing the room test does not close already.
local function scanOutdoorSquare(cell, square, found, seen)
	if square == nil then return end
	if square:getRoom() ~= nil then return end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	scanWorldItems(square, found, seen, x, y, z)
	local objects = square:getObjects()
	if objects == nil then return end
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		if not (isWallFixture(object) and facesARoom(cell, object, x, y, z)) then
			addDevices(object, i, x, y, z, found, seen)
		end
	end
end

-- Every device the machine at x, y, z can reach right now, unnumbered. THE
-- WALK ITSELF, with no cache in front of it: the minute sweep and the cache's
-- own miss are what call it now (CeroSecDevices.findCached).
--
-- `links` is the machine's own list of cable ends (state.links) and the second
-- answer is what that list should be AFTER this walk -- nil when the walk could not
-- ask the world at all, which is not the same as an empty list and must not read as
-- one (scanLinked).
function CeroSecDevices.find(x, y, z, links)
	local found, seen = {}, {}
	if getCell == nil then return found end
	local cell = getCell()
	if cell == nil then return found end

	local square = cell:getGridSquare(x, y, z)
	-- No square at all is a chunk the streamer has not brought in, and a machine
	-- that is not in the world reaches nothing: no /dev, and nothing for the
	-- sensor scan to sample (CeroSecSensors.scan). The same rule and the same
	-- guard the radio wears one layer down (CeroSecRadio.tncAt), and it is here
	-- rather than inside the two branches below because the no-building branch
	-- would otherwise walk four hundred squares that cannot be there -- once a
	-- minute, for every machine in the county the player has walked away from.
	if square == nil then return found end

	local building = square:getBuilding()

	if building ~= nil then
		-- Every room of the building, and a room whose chunks are away is a room the
		-- machine cannot act on: eachBuildingSquare above is the whole of that rule.
		--
		-- And the far edge of every one of those squares, which is where a south or
		-- east door stands: scanFarEdges above is the whole of THAT rule.
		eachBuildingSquare(building, function(sq)
			local sx, sy, sz = scanSquare(sq, found, seen)
			if sx ~= nil then scanFarEdges(cell, sq, sx, sy, sz, found, seen) end
		end)
		-- And the squares somebody ran a cable to, which are in no room of this
		-- building and are on the machine all the same (scanLinked).
		local kept = scanLinked(cell, links, found, seen, x, y, z)
		return withTnc(found, seen, x, y, z), kept
	end

	-- No building: a square of ten tiles around the machine, on its own floor.
	-- A square the game has not loaded is simply nil and is skipped, and
	-- anything that belongs to a building is left to that building's machine
	-- and to the cable (scanOutdoorSquare).
	local r = CeroSecDevices.RADIUS
	for dx = -r, r do
		for dy = -r, r do
			scanOutdoorSquare(cell, cell:getGridSquare(x + dx, y + dy, z),
				found, seen)
		end
	end
	local kept = scanLinked(cell, links, found, seen, x, y, z)
	return withTnc(found, seen, x, y, z), kept
end

--
-- Not doing the walk again, a tenth of a second later
--
-- THE COST THIS IS ABOUT, and it is not the one the study wrote down.
--
-- docs/notes/actuators.md, "The shell: what a daemon costs", counted a
-- five-second polling loop as one building walk every five seconds, on the
-- reasoning that CeroSecOS.jobStep returns above CeroSecOS.mountDev for a
-- sleeping job -- which it does. But the walk does not happen in mountDev. It
-- happens one layer higher, in CeroSecDevices.envFor, which is called from
-- SCeroSecSystem:execEnv, which CeroSecJobs.runMachine calls ONCE A PASS,
-- before it looks at a single job. A machine with any job at all in its book --
-- asleep, waiting, anything -- gets a pass every CeroSec.JOB_PASS_MS, and every
-- one of those passes walked the whole building.
--
-- So a `while true; do ...; sleep 5; done` daemon cost ten building walks a
-- second, not one every five. On a machine standing in a shopping mall -- ONE
-- BuildingDef, several hundred rooms -- that is the most expensive thing this
-- mod does, and nothing about it is visible from the step counts the scheduler
-- prints, because it costs no steps at all.
--
-- WHAT IS REMEMBERED, AND WHAT IS NOT. What a device IS -- that there is a door
-- at that square, which way it faces, the rooms it stands between, whether
-- somebody has screwed an operator to it -- is a fact about the BUILDING. It is
-- what the walk is for and it is what is kept. What a device is DOING is a fact
-- about this instant and is read off the object on every single answer
-- (stateOf, and CeroSecRadio.restate for the TNC): a door that opened between
-- two passes reads open on the second one, cache or no cache.
--
-- WHAT THROWS IT AWAY, and there are four:
--
--   the clock          an entry older than CACHE_MS is not used
--   the minute sweep   CeroSecDevices.refresh walks anyway, so it drops the
--                      entry first and fills it with what the walk just found
--   a module           installmodule and uninstallmodule, and the pre-fitting
--                      walk, all call CeroSecDevices.invalidate -- a box
--                      screwed to a door changes what EVERY machine in that
--                      building can see, and which machines those are is not a
--                      question this file can answer, so all of it goes
--   the machine moving an entry hangs on where the machine STANDS, so a
--                      computer picked up and put down on another desk misses
--                      and walks afresh
--
-- THE ONE THING A CACHE COSTS, and it is a second, in both directions. A device
-- that APPEARS -- a chunk streaming in, a door a survivor builds -- is not on
-- /dev until the next walk; a device that LEAVES reads its last state until the
-- next walk too. That is the same second the discovery has always been honest
-- about, "a device is not gone, it is simply not found this pass", read forwards
-- and then backwards.
--
-- What is NOT allowed to be a second late is a device being WORKED, and it is
-- not: envFor's write and find ask `alive` of the one device they are about to
-- touch, exactly as they did before this cache existed, so an order to a door
-- somebody has knocked down answers "no such device" and moves nothing. Asking
-- it of the whole LIST instead would be four engine calls per device per pass --
-- on a mall that is sixty thousand a second for one machine -- to buy a listing
-- that is right a second sooner, and the listing was never the thing that had to
-- be right.

-- One second of the player's own life, which is ten scheduler passes
-- (CeroSec.JOB_PASS_MS is 100). Long enough that a daemon polling every five
-- seconds pays for one walk a second instead of ten, short enough that nothing a
-- survivor does in a room is stale by the time he walks back to the keyboard --
-- and the two things that really would be stale, a module and the minute sweep,
-- do not wait for it.
--
-- REAL milliseconds and not the game's, because what it is bounding is real
-- server time: the pass it saves is scheduled on getTimestampMs and so is this.
CeroSecDevices.CACHE_MS = 1000

-- One entry per machine, by where the machine stands. Never saved: it is an
-- answer about a moment, and a reload is the end of it.
CeroSecDevices.cache = {}

local function cacheKey(x, y, z)
	return x .. ":" .. y .. ":" .. z
end

-- Everything, forgotten. What a module install calls: which machines can see the
-- fixture somebody just wired is not a question this file can answer without the
-- walk it is trying to avoid, so the honest answer is all of them.
function CeroSecDevices.invalidate()
	CeroSecDevices.cache = {}
end

-- One machine's, forgotten.
function CeroSecDevices.forget(x, y, z)
	CeroSecDevices.cache[cacheKey(x, y, z)] = nil
end

-- Old entries out. Nothing else takes one away, so a computer carried across the
-- county would otherwise leave one behind for every desk it ever stood on.
-- Walked on a MISS only, which is at most once a second per machine.
local function prune(now)
	for key, held in pairs(CeroSecDevices.cache) do
		if now < held.at or now - held.at >= CeroSecDevices.CACHE_MS then
			CeroSecDevices.cache[key] = nil
		end
	end
end

-- The same list find() answers, out of the last walk when there was one recently
-- enough, with every state read afresh and everything that has left the world
-- dropped.
--
-- `now` is the real clock (getTimestampMs). Without one there is no cache at
-- all and every call is a walk: a caller with no clock cannot be told how old an
-- answer is, and an answer of unknown age is one to throw away.
--
-- `links` and the second answer are the machine's cable list and what it should be
-- (CeroSecDevices.find). The held answer carries the one the walk gave, because
-- every hand that writes a cable calls invalidate(): a hit cannot be looking at a
-- list the walk has not seen.
function CeroSecDevices.findCached(x, y, z, now, links)
	if type(now) ~= "number" then return CeroSecDevices.find(x, y, z, links) end

	local held = CeroSecDevices.cache[cacheKey(x, y, z)]
	-- `now < held.at` is a clock that went backwards, which is a miss: the one
	-- thing worse than walking again is trusting an answer whose age is negative.
	if held ~= nil and now >= held.at and now - held.at < CeroSecDevices.CACHE_MS then
		local out = {}
		for i = 1, #held.found do
			local entry = held.found[i]
			if entry.kind == CeroSecRadio.KIND then
				-- The radio's state is built by the file that owns every call a
				-- radio answers, so there is one sentence and not two.
				local text = CeroSecRadio.restate(entry)
				if text ~= nil then entry.state = text end
			else
				-- A sensor gets nil here and keeps what it has: its state is the
				-- sampling book's and build() puts it on after the numbering.
				local fresh = stateOf(entry.kind, entry.object, entry.locks)
				if fresh ~= nil then entry.state = fresh end
				-- And the rest of the line, which is a reading like any other: a
				-- generator's tank going down between two passes is the whole
				-- reason anybody cats one.
				local more = detailOf(entry.kind, entry.object)
				if more ~= nil then entry.detail = more end
			end
			out[i] = entry
		end
		return out, held.kept
	end

	local found, kept = CeroSecDevices.find(x, y, z, links)
	CeroSecDevices.cache[cacheKey(x, y, z)] = { at = now, found = found, kept = kept }
	prune(now)
	return found, kept
end

--
-- Numbering them
--

-- The order the numbers are handed out in, and it must not depend on the order
-- the world was walked in: kind, then x, then y, then z, then the side, then
-- the ordinal that tells two devices on one square apart.
local function before(a, b)
	if a.kind ~= b.kind then return a.kind < b.kind end
	if a.x ~= b.x then return a.x < b.x end
	if a.y ~= b.y then return a.y < b.y end
	if a.z ~= b.z then return a.z < b.z end
	if a.side ~= b.side then return a.side < b.side end
	return a.key < b.key
end

-- The book of numbers, made when it is first needed.
local function devmapOf(state)
	if type(state.devmap) ~= "table" then state.devmap = {} end
	return state.devmap
end

-- Give every found device its id, out of the book or freshly out of the
-- smallest number that kind has never used. Answers the entries, plus the ones
-- the book knows and the world did not hand back.
function CeroSecDevices.number(state, found)
	local map = devmapOf(state)

	local used, entries = {}, 0
	for _, record in pairs(map) do
		if type(record) == "table" and type(record.kind) == "string"
				and type(record.n) == "number" then
			used[record.kind .. ":" .. record.n] = true
		end
		entries = entries + 1
	end

	table.sort(found, before)

	local live = {}
	for i = 1, #found do
		local entry = found[i]
		local record = map[entry.key]
		if type(record) ~= "table" or type(record.id) ~= "string" then
			-- A number is spent for the life of the machine, so the book is
			-- capped: a computer carried across the map must not grow one entry
			-- per light switch in the county.
			if entries < CeroSecDevices.MAP_MAX then
				local n = 0
				while used[entry.kind .. ":" .. n] do n = n + 1 end
				used[entry.kind .. ":" .. n] = true
				-- The mode a kind is born at, which is not the same for every kind:
				-- a sensor cannot be written to and wears 440 for saying so
				-- (CeroSecOS.DEV_MODES) -- and neither can a device with nothing
				-- behind it to write with, which is what `ro` is.
				record = { id = entry.kind .. tostring(n), kind = entry.kind, n = n,
					ro = entry.ro == true,
					mode = CeroSecOS.devModeFor(entry.kind, entry.ro) }
				map[entry.key] = record
				entries = entries + 1
			else
				record = nil
			end
		end
		if record ~= nil then
			-- The hardware behind a device can change under it: somebody fits an
			-- operator to a door that had only a contact on it, or takes one off.
			-- The NUMBER does not move for that -- it hangs on where the device is
			-- and which kind it is, and neither of those moved -- but the mode goes
			-- back to what a device of that shape is born at. A chmod does not
			-- survive the hardware, and must not: the other way round is a door
			-- with an operator on it that nobody may write to, because it was
			-- read-only the first time it was seen.
			--
			-- Both sides are read as booleans, so a record written before this rung
			-- -- which carries no `ro` at all -- is a read-write one and not a
			-- changed one, and no chmod is thrown away by a reload.
			if (record.ro == true) ~= (entry.ro == true) then
				record.ro = entry.ro == true
				record.mode = CeroSecOS.devModeFor(entry.kind, entry.ro)
			end
			entry.id = record.id
			if type(record.mode) == "number" then entry.mode = record.mode end
			live[#live + 1] = entry
		end
	end

	return live
end

--
-- What the engine is handed
--

-- The cable list a walk came back with, put on the machine -- and only when the
-- walk changed it.
--
-- The list lives beside the book of numbers in the machine's own state and is
-- written the same way (CeroSecDevices.number): the state table IS the saved one, so
-- an assignment here is the save. Which is exactly why an unchanged list is left
-- alone: a walk that rewrites a table every pass makes the machine's state new every
-- pass, and everything downstream that asks "did this change" would answer yes for
-- ever.
--
-- A nil answer is a walk that could not ask the world -- no cell, or the machine's
-- own square away -- and it is NOT an empty list: a cable is not lost because the
-- chunk was (scanLinked).
local function writeKept(state, kept)
	if state == nil or type(kept) ~= "table" then return false end
	local links = state.links
	if links == nil and #kept == 0 then return false end
	if type(links) == "table" and #links == #kept then
		local same = true
		for i = 1, #kept do
			local was, is = links[i], kept[i]
			if type(was) ~= "table" or was.x ~= is.x or was.y ~= is.y or was.z ~= is.z then
				same = false
				break
			end
		end
		if same then return false end
	end
	-- An empty list is the key gone, not a key holding nothing: a machine with no
	-- cables reads in a save exactly like every machine written before this build
	-- (CeroSecOS.linksOk).
	if #kept == 0 then state.links = nil else state.links = kept end
	return true
end

-- One machine's devices, discovered now. Everything below closes over this one
-- table, so list() and write() cannot disagree about what is there.
local function build(luaObject, state)
	-- One clock for the whole pass, read before the discovery because the
	-- discovery needs it: this is where /dev is answered out of the last walk
	-- when there was one this second (CeroSecDevices.findCached).
	local now = getTimestampMs()
	local found, kept = CeroSecDevices.findCached(luaObject.x, luaObject.y, luaObject.z,
		now, state ~= nil and state.links or nil)
	writeKept(state, kept)

	-- A sensor's state is not read off the object: there is nothing on a dropped
	-- item to read. It is what the sampling book says the contact is doing right
	-- now, and asking for it is also what puts a head just dropped on the floor
	-- into that book (see the head of SCeroSecSensors.lua).
	CeroSecSensors.registerFound(found, now)

	local live = CeroSecDevices.number(state, found)
	for i = 1, #live do
		local entry = live[i]
		if entry.kind == "sensor" then
			entry.state = CeroSecSensors.stateAt(entry.x, entry.y, entry.z, entry.n, now)
		end
	end

	local byId, seen = {}, {}
	local list = {}
	for i = 1, #live do
		local entry = live[i]
		byId[entry.id] = entry
		seen[entry.id] = true
		list[#list + 1] = {
			id = entry.id, kind = entry.kind, desc = entry.desc,
			side = entry.side, state = entry.state,
			-- The rest of a line a kind has more than one word for. Absent on
			-- every kind but the generator, and absent reads as "nothing more to
			-- say" (CeroSecOS.devText).
			detail = entry.detail,
			-- Whether anything is wired behind it. The engine mounts a node that
			-- says so and refuses every write to it in its own name.
			ro = entry.ro,
			-- Where it is, from where the machine is standing. Worked out here
			-- and not by the engine: the engine has no idea there are tiles.
			pos = CeroSecDevices.offset(entry.x - luaObject.x, entry.y - luaObject.y,
				entry.z - luaObject.z),
			mode = entry.mode or CeroSecOS.devModeFor(entry.kind, entry.ro),
		}
	end

	-- And the numbers the machine remembers and cannot reach. They are mounted
	-- but never listed, so that a player who wrote one down is told "no such
	-- device" instead of "no such file" -- the difference between a device that
	-- is out of reach and a path he mistyped.
	local map = devmapOf(state)
	for _, record in pairs(map) do
		if type(record) == "table" and type(record.id) == "string" and not seen[record.id] then
			if #list >= CeroSecOS.DEV_MAX then break end
			seen[record.id] = true
			list[#list + 1] = {
				id = record.id, kind = record.kind, dead = true, ro = record.ro,
				mode = record.mode or CeroSecOS.devModeFor(record.kind, record.ro),
			}
		end
	end

	return list, byId, map
end

-- The same discovery, for a reader that is not the engine: the list /dev would
-- be built from, and the entries behind it with their world objects on them.
--
-- It exists so the debug window can show what the SERVER sees -- the sprite a
-- device is, the square it is on, whether its object is still there -- without
-- working any of it out again: a debug window that numbered devices itself would
-- be a second numbering, and the day the real one changed it would quietly
-- disagree. Nothing here writes anything; build() is the same call envFor makes.
function CeroSecDevices.snapshot(luaObject, state)
	return build(luaObject, state)
end

-- Is the object we found still where we found it? Belt and braces: list() and
-- write() happen inside one command, so nothing should have moved -- but a
-- Java handle to an object that has been taken off its square is exactly the
-- kind of thing that answers questions and changes nothing.
--
-- It is asked of the device being WORKED and never of the whole list, and the
-- cache did not change that: see "the one thing a cache costs", above. Four
-- engine calls per device per pass is what asking it of a mall's worth of them
-- would be, and the answer it bought -- a device that reads its last state for
-- up to a second after somebody knocked it down -- is the same second the
-- discovery has always been honest about in the other direction.
local function alive(entry)
	local object = entry.object
	if object == nil then return false end
	local square = object:getSquare()
	if square == nil then return false end
	return square:getX() == entry.x and square:getY() == entry.y and square:getZ() == entry.z
end

-- Is the doorway itself in the way? The game's own test and nothing of ours:
-- IsoDoor.isObstructed() -> the static isDoorObstructed(IsoObject), which
-- answers true when the door's square is isSolid() or isSolidTrans(), when it
-- has an IsoObjectType.tree on it, or when a vehicle in the chunk
-- isIntersectingSquareWithShadow of it. IsoThumpable has the same method,
-- forwarding to the same static.
--
-- It is exactly the test couldBeOpen makes at offset 108 before it will let a
-- survivor through, so a door the machine refuses is a door nobody could open by
-- hand either -- which is the whole rule here. A survivor STANDING in the
-- doorway is not one of these: vanilla lets a door swing through him
-- (ISOpenCloseDoor:complete calls ToggleDoor and checks nothing first), so the
-- machine does too. A refusal the game does not make is a refusal we would have
-- invented.
local function blocked(object)
	return object:isObstructed()
end

--
-- THE SOUND A HAND WOULD HAVE MADE
--
-- Every actuator here works its fixture with the SILENT call, because the loud
-- ones play at a SURVIVOR and a machine has none: IsoDoor and IsoThumpable play
-- through playDoorSound(BaseCharacterSoundEmitter, String), which is the
-- character's own emitter (IsoDoor.playDoorSound, offsets 0-16), IsoCurtain's
-- ToggleDoor plays at `chr` too and only when `chr` is not null (offsets 79-129),
-- and a window's sound is not in the class at all. So the toggle stays silent and
-- the sound is made HERE, beside it.
--
-- It is not decoration. A survivor who cannot hear his building work cannot tell
-- a door that swung from an order that was swallowed, which is exactly what was
-- reported of 0.4.0: a door shut by autoclose.sh, a window opened by cron and a
-- curtain drawn by curtains.sh all happened in silence.
--
-- THE NAME IS THE HAND'S NAME, never one of ours, and it is read AFTER the toggle
-- so that it names the state the world settled in rather than the word that was
-- typed.
--
-- WHO HEARS IT is vanilla's own server-side pair, out of a server file --
-- media/lua/server/Traps/STrapGlobalObject.lua:118-124:
--
--   if isServer() then playServerSound(soundName, square) return end
--   square:playSound(soundName, true)
--
-- and each half is the only one that works where it stands.
-- playServerSound(String, IsoGridSquare) is GameServer.PlayWorldSoundServer(name,
-- false, square, 0.2f, 5f, 1.1f, true) -> GameServer.PlayWorldSound, whose first
-- instructions are `if (!GameServer.server) return` (offsets 0-10) and whose body
-- walks udpEngine.connections and sends a PlayWorldSoundPacket to every
-- connection the square is RelevantTo (offsets 69-171). So it is a broadcast on a
-- dedicated server and nothing at all anywhere else.
-- IsoGridSquare.playSound(String, boolean) takes a free emitter at the square and
-- plays there (offsets 0-36), which is what a solo game needs: one process, so
-- the machine the server wrote is the machine the survivor is listening to.
local function playAt(object, name)
	if type(name) ~= "string" or name == "" then return end
	local square = object:getSquare()
	-- A fixture the world has taken away makes no sound, and asking a nil square
	-- where to play would be a nil call in the middle of an order.
	if square == nil then return end
	if isServer() then
		playServerSound(name, square)
		return
	end
	square:playSound(name, true)
end

-- A DOOR, map or built. Both classes carry a public getSoundPrefix() and both
-- build the name the same way: playDoorSound(emitter, "Open") / ("Close")
-- concatenates the prefix and the word (IsoDoor.playDoorSound offsets 0-16, the
-- recipe "\1\1" in the class's BootstrapMethods), and the prefix is the
-- closedSprite's DoorSound property or "WoodDoor" when the sprite has none
-- (offsets 0-40 of each getSoundPrefix). So a map door says WoodDoorOpen and a
-- prison door says PrisonMetalDoorOpen without this file knowing there is such a
-- thing.
--
-- Which word, at the bytecode: ToggleDoorActual reads isOpen() AFTER the flip and
-- plays "Open" when it is open (IsoDoor offsets 701-722, IsoThumpable 477-514).
local function doorSound(object)
	return object:getSoundPrefix() .. (object:IsOpen() and "Open" or "Close")
end

-- A CURTAIN of its own. IsoCurtain.ToggleDoor plays getSoundPrefix() .. "Open" /
-- "Close" at the character (offsets 83-129, the same "\1\1" recipe), and
-- IsoCurtain.getSoundPrefix() is "Curtain" .. the closedSprite's CurtainSound
-- property, or "CurtainShort" when there is no sprite or no property (offsets
-- 0-45, recipe "Curtain\1"). So a map curtain is CurtainShortOpen and a
-- survivor's bedsheet is CurtainSheetOpen -- both declared, with CurtainLong and
-- CurtainShade, in media/scripts/generated/sounds/objects/sounds_object_curtain.txt.
local function curtainSound(object)
	return object:getSoundPrefix() .. (object:IsOpen() and "Open" or "Close")
end

-- A DOOR'S OWN SHEET has no IsoCurtain to ask a prefix of, and vanilla plays
-- NOTHING for it: the menu hands the DOOR to ISOpenCloseCurtain, whose complete()
-- calls toggleCurtain() for an IsoDoor, and that method is a field write and a
-- broadcast with no sound anywhere in it (offsets 0-63).
--
-- The mod plays the curtain's own default rather than nothing, and that is a
-- CHOICE written down rather than a guess: the engine is silent there because it
-- has no object to read a prefix off, which is the very case
-- IsoCurtain.getSoundPrefix() answers "CurtainShort" for (offsets 0-10, no
-- closedSprite). The door's own prefix would have been wrong -- a bedsheet on a
-- door is not a door, and WoodDoorOpen is the sound of the door swinging.
local function sheetSound(object)
	return "CurtainShort" .. (object:isCurtainOpen() and "Open" or "Close")
end

-- A WINDOW. IsoWindow.ToggleWindow plays no sound of any kind: the whole method
-- is a sprite swap, handleAlarm, sync and triggerMusicIntensityEvent for the
-- local player (offsets 166-197), and that last one is music and not a sash. The
-- sash's sound is on the SURVIVOR'S ANIMATION --
-- media/AnimSets/player/openwindow/success.xml carries a `PlaySound` event whose
-- parameter is `OpenWindow`, and closewindow's carries `CloseWindow`, both
-- declared in sounds_object_window.txt. A motor has no animation, so the mod
-- plays those two names itself.
local function windowSound(object)
	return object:IsOpen() and "OpenWindow" or "CloseWindow"
end

--
-- THE ONE SYNC IN THIS MOD THAT IS OURS
--
-- Every other actuator either broadcasts itself or is broadcast by one engine
-- call beside it, and the whole table of them is in docs/DEVICES.md. A
-- television and a radio set are the pair that cannot be, and the proof --
-- transmitDeviceDataState(short) being a client branch and nothing else, the
-- server's broadcaster being private, and the one public wrapper spending its
-- short on the battery -- is at the head of
-- 42/media/lua/client/CeroSec/CCeroSecDevices.lua, beside the code that answers
-- this packet. It is written there rather than here because that is the end that
-- has to be believed.
--
-- WHAT TRAVELS is where the object is, what class it is, what it looks like,
-- which of the square's objects it was, and the two fields as they READ AFTER the
-- write. Not what was asked for: setIsTurnedOn refuses an unpowerable device by
-- turning it off instead (offsets 0-4 and 44-58), so the order and the state are
-- two different facts and it is the state that is anybody's business.
--
-- NOTHING AT ALL IN SINGLE PLAYER, and that is the engine's doing rather than a
-- branch of ours:
--
--   LuaManager$GlobalObject.sendServerCommand(String, String, KahluaTable)
--      0: getstatic  #349   // GameServer.server:Z
--      3: ifeq       12                     <- no server: return
--      6-9: GameServer.sendServerCommand(arg0, arg1, arg2)
--     12: return
--
-- so the call is a no-op in a solo game -- where it has nothing to do anyway, one
-- process meaning the object the server wrote is the object the survivor is
-- looking at. One code path, two games.
--
-- AND IT IS A BROADCAST and not an answer to one player, which is the other half
-- of why it is this call and not SCeroSecSystem:reply. A survivor's screen is his
-- own business; a television coming on in a room is everybody's:
--
--   GameServer.sendServerCommand(String, String, KahluaTable) walks
--   udpEngine.connections from 0 to size() and sends to each (offsets 0-48).
--
-- Vanilla's own server Lua makes the same three-argument call --
-- `sendServerCommand('erosion', 'disableForSquare', args)`,
-- media/lua/server/BuildingObjects/ISWoodenFloor.lua:21 -- so it is the shape the
-- game uses for a world change nobody in particular asked for.
CeroSecDevices.SYNC = "device"

-- The same pair `dev find` travels on, out of the same one place: a class for the
-- far end's instanceof and a sprite name for what it looks like. nil when there is
-- none, and a set this mod cannot describe to the other clients is a set it must
-- not move -- which is why this is asked BEFORE the field is written and not after
-- (see `act`). A write nobody is told about is worse than a refusal.
local function waveHandle(entry)
	local class, sprite = CeroSecDevices.handleOf(entry)
	if type(class) ~= "string" or type(sprite) ~= "string" or sprite == "" then
		return nil
	end
	return class, sprite
end

local function syncWave(entry, data, class, sprite)
	sendServerCommand(CeroSec.MODULE, CeroSecDevices.SYNC, {
		x = entry.x, y = entry.y, z = entry.z,
		index = entry.index,
		class = class, sprite = sprite,
		-- Read off the object, never assumed from the word that was typed.
		on = data:getIsTurnedOn() and true or false,
		channel = math.floor(data:getChannel()),
	})
end

-- THROW A LIGHT SWITCH, INCLUDING ONE THE SURVIVOR'S HAND COULD NOT REACH.
--
-- IsoLightSwitch.setActive(boolean, boolean, boolean) has a gate of its own
-- BEFORE it ever asks canSwitchLight -- offsets 22-43, and canSwitchLight is
-- not invoked until offset 49:
--
--   22: getfield  square        26: invokevirtual IsoGridSquare.getRoom
--   29: ifnonnull 44            33: getfield      canBeModified
--   36: ifne      44            39: getfield      activated
--   43: ireturn
--
-- which is
--   if (this.square.getRoom() == null && !this.canBeModified) {
--       return this.activated;
--   }
--
-- No room and not player-built is a STREET LAMPPOST, and the engine hands the
-- write straight back, unchanged and silent. Nothing on the read side passes
-- there -- a light reads through isActivated(), and the constructor's `else`
-- branch sets a roomless switch activated = true -- which is why a cabled
-- lamppost reads `on` while a write to it looked like missing current. It is
-- not missing: canSwitchLight said the grid is there one line up.
--
-- canBeModified is the engine's word for "this switch can be worked at all",
-- and a relay screwed onto the post is exactly that. Lifted for the one call
-- and put straight back, so setActive does all of its own work -- the light
-- sources, the global relight, the sync to every client -- rather than this
-- file doing three quarters of it by hand. Nothing can save the object between
-- the two lines: it is one Lua call, and save() writes the flag it finds after.
local function throwLight(object, want)
	local square = object:getSquare()
	if square ~= nil and square:getRoom() == nil and not object:getCanBeModified() then
		object:setCanBeModified(true)
		-- pcall: canBeModified is what save() writes (proof above), and a raise
		-- out of setActive with the flag left up would save a street lamppost as
		-- player-built forever. Rabaissé in every case, error included; the
		-- message itself is dropped -- act()'s isActivated() read right after
		-- this call already turns "nothing happened" into "no power", the one
		-- word this file uses for an engine call that did not do what it was
		-- told.
		pcall(object.setActive, object, want)
		object:setCanBeModified(false)
		return
	end
	object:setActive(want)
end

-- The world action, per kind. ok, reason, state.
local function act(entry, value)
	local object = entry.object

	-- Nothing is ever written to a sensor: the engine has no word for the kind
	-- (CeroSecOS.DEV_VALUES.sensor is empty) so a write is refused a layer up and
	-- never arrives here. This is the belt: a device that reached the world with
	-- no action for it must refuse in its own name and not fall through to the
	-- lock branch below, which would ask a dropped pipe bomb about its padlock.
	if entry.kind == "sensor" then return false, "invalid value" end

	-- And the radio, the same belt for the same reason: its vocabulary is empty
	-- too (the knob is the survivor's -- proof 7 in SCeroSecRadio.lua), so a write
	-- is refused a layer up and never arrives. If one ever did, it refuses in its
	-- own name rather than falling through to the lock branch below and asking an
	-- aerial about its padlock.
	if entry.kind == CeroSecRadio.KIND then return false, "invalid value" end

	-- And the third belt, for the devices this rung made: a door with a magnetic
	-- contact on it and no operator, or a window, which has no actuator in the
	-- game at all. The engine refuses these a layer up -- by the mode, and then by
	-- the node's own `ro` -- so nothing should arrive here. If one ever does, it
	-- says the same thing the engine says rather than quietly working the door
	-- with hardware nobody fitted.
	if entry.ro then return false, "operation not supported" end

	if entry.kind == "light" then
		local want = value == "on"
		-- The switch's own rule for whether it can be thrown at all: a bulb,
		-- and electricity or a charged battery (IsoLightSwitch.canSwitchLight).
		-- A switch with no bulb in it reads the same way, which is what a
		-- survivor flicking it would find too.
		if not object:canSwitchLight() then return false, "no power" end
		throwLight(object, want)
		-- setActive syncs itself from the server and answers with what it
		-- settled on; the state is read back rather than assumed.
		local now = object:isActivated() and "on" or "off"
		if (now == "on") ~= want then return false, "no power" end
		return true, nil, now
	end

	if entry.kind == "door" then
		local want = value == "open"
		-- Barricaded first, and by us: ToggleDoorSilent's first two
		-- instructions are isBarricaded and return, so a machine that did not
		-- check would swallow the order and report the state it already had.
		if object:isBarricaded() then return false, "barricaded" end
		-- The computer is not a key. A locked door is only locked at all when
		-- the lock means something on it (entry.locks), and the way past it is
		-- `unlock` on the lock device beside it.
		if want and entry.locks and object:isLockedByKey() then
			return false, "locked"
		end
		if blocked(object) then return false, "blocked" end
		-- Silent TOGGLES, so a door already where it is asked to be is left
		-- alone and nothing is broadcast: two `dev door0 open` in a row are one
		-- open door, not an open one and a shut one.
		if object:IsOpen() ~= want then
			object:ToggleDoorSilent()
			-- ToggleDoorSilent syncs nothing. syncIsoObject's server branch
			-- walks GameServer.udpEngine.connections, and both classes'
			-- syncIsoObjectSend writes the open flag.
			object:syncIsoObject(false, 0, nil, nil)
			-- And it is HEARD, which the silent toggle is named for not doing:
			-- the same name the hand plays, read off the door after it moved
			-- (see "the sound a hand would have made"). Inside this branch and
			-- not below it, so a door already where it was asked to be is one
			-- open door and one sound, not two.
			playAt(object, doorSound(object))
		end
		return true, nil, doorState(object, entry.locks)
	end

	if entry.kind == "win" then
		if object:isSmashed() then return false, "smashed" end
		if object:isBarricaded() then return false, "barricaded" end
		object:setIsLocked(value == "lock")
		object:syncIsoObject(false, 0, nil, nil)
		return true, nil, windowState(object)
	end

	--
	-- THE SASH, which is the window operator's and not the contact's
	--
	-- IsoWindow.ToggleWindow(IsoGameCharacter) is the only call in the game that
	-- moves one -- javap names the three writers of the `open` field and they are
	-- load(), this, and syncIsoObjectReceive() -- and it takes a character it
	-- never dereferences. Every use of the argument is behind a null guard and the
	-- sync at offset 147 is unconditional, which is why this works at all.
	--
	-- A LUA nil REACHES A JAVA OBJECT PARAMETER AS null, and both halves of that
	-- are proven rather than assumed:
	--
	--   the marshalling. LuaJavaInvoker.prepareCall pulls each argument off the
	--   frame (offsets 295-304), and at 325-347 it converts anything the parameter
	--   type is not already an instance of -- which a null never is, Class.isInstance
	--   answering false for it. convert(Object, Class) returns null at its first two
	--   instructions for a null input (offsets 0-5), before the converter manager is
	--   asked anything. And the type check at 349-392 is `if (arg != null &&
	--   converted == null) fail(...)`: the failure is GUARDED ON arg != null, so a
	--   null argument is stored straight into the parameter array at 393-405. The
	--   argument COUNT is not exempt (offsets 126-137 refuse a short call), so the
	--   nil has to be written and cannot be left out.
	--
	--   and vanilla's own Lua does it. media/lua/shared/TimedActions/ISLockDoor.lua
	--   :56, :62 and :69 -- `door:syncIsoObject(false, 0, nil, nil)` -- passes nil
	--   into a UdpConnection and a ByteBufferReader, and this mod has made that same
	--   call on every door write since rung 1.
	--
	-- WHAT THE MOTOR DOES BESIDES MOVE THE SASH, which is the whole design of this
	-- device and is written in the bytecode rather than chosen by us:
	--
	--   it throws the catch. Offsets 50-54 set `locked = false` unconditionally.
	--   That is what an operator does -- a motor that stopped at a latch would be a
	--   motor with a hand -- and it is why the latch stays win0's reading and never
	--   becomes this device's word.
	--
	--   it sets the house alarm off. Offsets 86-118: when the sash ends up open the
	--   sandbox check (lore.triggerHouseAlarm) is consulted ONLY for an IsoZombie,
	--   so a null character falls straight into handleAlarm(). It is kept, because
	--   a window opened in an alarmed house is a window opened in an alarmed house
	--   and the machine is not a burglar with a key. It is in the manual, in the
	--   changelog and in the parcours in those words.
	--
	-- AND THE THREE SILENT RETURNS ARE REFUSED HERE, before the call, for the
	-- barricaded door's reason: a `return` that does nothing is an order swallowed
	-- and a machine reporting the state it already had.
	if entry.kind == "window" then
		local want = value == "open"
		if object:isSmashed() then return false, "smashed" end
		if object:isBarricaded() then return false, "barricaded" end
		if object:isPermaLocked() then return false, "sealed" end
		-- ToggleWindow TOGGLES, so a sash already where it is asked to be is left
		-- alone: two `dev window0 open` in a row are one open window, and the
		-- second one does not ring the alarm again.
		if object:IsOpen() ~= want then
			object:ToggleWindow(nil)
			-- The sash is heard. ToggleWindow plays nothing at all -- the sound a
			-- survivor makes at a window is an event on his own animation -- so
			-- this is where the motor gets one.
			playAt(object, windowSound(object))
		end
		return true, nil, sashState(object)
	end

	--
	-- THE CURTAIN, and there are two of them
	--
	if entry.kind == "curtain" then
		local want = value == "open"
		if instanceof(object, "IsoCurtain") then
			-- IsoCurtain.ToggleDoorSilent() takes no character and BROADCASTS
			-- ITSELF: its last act is syncIsoObject(false, open ? 1 : 0, null) at
			-- offset 85-100, and that override's server branch walks
			-- GameServer.udpEngine.connections. This is the one actuator in the mod
			-- whose sync is the engine's and not ours -- IsoDoor's own
			-- ToggleDoorSilent syncs nothing -- so nothing is added after it.
			-- Vanilla makes the same bare call itself, on a curtain nobody is
			-- holding: client/DebugUIs/Scenarios/Trailer2Scenario.lua:134,
			-- `window1:HasCurtains():ToggleDoorSilent()`.
			if object:IsOpen() ~= want then
				object:ToggleDoorSilent()
				-- AND THE BARRICADE, found the only way it can be. The toggle's
				-- first two instructions are `barricaded -> return` (offsets 0-7)
				-- and IsoCurtain has no isBarricaded(): `barricaded` is a public
				-- field with no getter over it, so there is nothing to ask before
				-- the call. What there is, is the fact that those two instructions
				-- are the ONLY way out of that method without moving the sheet --
				-- so a curtain that did not move is a curtain that is boarded, and
				-- the machine says so instead of swallowing the order.
				if object:IsOpen() ~= want then return false, "barricaded" end
				-- It moved, so it is heard -- and AFTER the barricade test, so a
				-- boarded curtain that did not move is silent as well as refused.
				playAt(object, curtainSound(object))
			end
			return true, nil, curtainState(object)
		end
		-- A door's own sheet. toggleCurtain() sets the field and broadcasts on the
		-- server in one call -- `transmitSetCurtainOpen(isCurtainOpen())` at
		-- offsets 55-60, whose server branch is a sendObjectChange of
		-- SET_CURTAIN_OPEN -- so this is the pair vanilla makes and nothing is
		-- added after it either. setCurtainOpen(b) alone is the half that does not
		-- broadcast.
		--
		-- It has one silent return and classify has already answered it: no sheet,
		-- no device (offsets 0-7, `hasCurtain`).
		if object:isCurtainOpen() ~= want then
			object:toggleCurtain()
			playAt(object, sheetSound(object))
		end
		return true, nil, curtainState(object)
	end

	--
	-- THE STOVE, THE MICROWAVE AND THE COFFEE MACHINE
	--
	-- Toggle() and not setActivated(), because Toggle() is the whole gesture and
	-- the other two thirds of it matter: offsets 0-27 are setActivated(!activated),
	-- getContainer().addItemsToProcessItems() and
	-- IsoGenerator.updateGenerator(square). A machine that called the setter alone
	-- would switch an oven on that never cooked anything and never drew a watt off
	-- the generator.
	--
	-- It is vanilla's own server-side line, written by vanilla with no character
	-- anywhere in it: media/lua/server/ClientCommands.lua:1049-1062,
	-- `Commands.stove.setOvenParamsAndToggle`, which finds the IsoStove on a square
	-- and calls obj:Toggle(). The timer and the temperature that command also sets
	-- are a survivor's settings and are left alone.
	--
	-- setActivated syncs itself from the server -- offsets 201-214, sync() and
	-- syncSpriteGridObjects(true, true) -- so nothing is broadcast by us.
	-- PlayToggleSound() is separate and belongs to a survivor's hands, so a machine
	-- that works a stove is silent, which is right.
	if entry.kind == "stove" then
		local want = value == "on"
		-- Broken first, and by us: setActivated's own first instructions are
		-- isBroken -> return (offsets 0-7), so a machine that did not check would
		-- swallow the order.
		if object:isBroken() then return false, "broken" end
		if not appliancePowered(object) then return false, "no power" end
		if object:Activated() ~= want then object:Toggle() end
		return true, nil, stoveState(object)
	end

	--
	-- THE LAUNDRY
	--
	-- setActivated is a field write plus IsoGenerator.updateGenerator and no sync
	-- at all, and the broadcast is ours: sendObjectChange(WASHER_STATE), which is
	-- server-only by construction (its first instructions test GameServer.server
	-- and its client branch logs "sendObjectChange() can only be called on the
	-- server"). saveChange writes isActivated() under that change.
	--
	-- It is exactly the pair vanilla's own timed action makes,
	-- media/lua/shared/TimedActions/ISToggleClothingWasher.lua:
	--   self.object:setActivated(not self.object:isActivated())
	--   self.object:sendObjectChange(IsoObjectChange.WASHER_STATE)
	if entry.kind == "washer" then
		local want = value == "on"
		if not appliancePowered(object) then return false, "no power" end
		if object:isActivated() ~= want then
			object:setActivated(want)
			object:sendObjectChange(IsoObjectChange.WASHER_STATE)
		end
		return true, nil, object:isActivated() and "on" or "off"
	end

	--
	-- THE GENERATOR
	--
	-- setActivated(boolean) is idempotent by construction (offsets 0-8 return when
	-- the argument is the state it is already in) and its server branch calls
	-- sync() at offsets 113-122, which is IsoObject.sync() ->
	-- syncIsoObject(false, 0, null, null) -- the same broadcast the door already
	-- makes. Vanilla calls sync() again after it and so does this, because
	-- ISActivateGenerator:complete does.
	--
	-- IT CHECKS NOTHING ITSELF: no fuel test, no condition test, no connection
	-- test. The gate is vanilla's own timed action's (ISActivateGenerator:isValid)
	-- and it is copied: not connected, no fuel, no condition. All three are asked
	-- only of STARTING it -- stopping a generator that is out of fuel is stopping
	-- a generator, and refusing that would be a machine arguing.
	--
	-- AND THE COIN FLIP IS NOT OURS. That same complete() calls failToStart() on a
	-- generator below half condition, one time in two. A shoulder fails to pull a
	-- cord; an electric starter does not, and a starter is what this module IS.
	-- Leaving it out is a decision and it is written here rather than left as a
	-- line somebody deleted.
	if entry.kind == "gen" then
		local want = value == "on"
		if want then
			if not object:isConnected() then return false, "not connected" end
			if object:getFuel() <= 0 then return false, "no fuel" end
			if object:getCondition() <= 0 then return false, "broken" end
		end
		if object:isActivated() ~= want then
			object:setActivated(want)
			object:sync()
		end
		return true, nil, object:isActivated() and "on" or "off",
			detailOf("gen", object)
	end

	--
	-- THE TELEVISION AND THE RADIO SET, and the sync that is ours
	--
	-- THE SWITCH. setIsTurnedOn(boolean) is the whole gesture and the other third
	-- of it matters: offsets 118-130 are
	-- IsoGenerator.updateGenerator(getParent().getSquare()), which is what makes a
	-- generator feel the load -- the same third of Toggle() that is the reason the
	-- stove calls Toggle and not setActivated.
	--
	-- AND IT SWALLOWS AN ORDER IT CANNOT CARRY OUT, twice over, so both gates are
	-- asked HERE, before the call, for the barricaded door's reason:
	--
	--    0-4    canBePoweredHere() false -> the 44-58 branch, which turns the set
	--           OFF and transmits, whatever was asked. So `on` on a dead grid is
	--           an order that reads back as off.
	--    7-20   battery-powered with powerDelta <= 0 -> setIsTurnedOnInternal(
	--           FALSE) at 31-33, again whatever was asked.
	--
	-- canBePoweredHere() is the engine's own supply question and it answers for
	-- both kinds of set: true at once for anything battery-powered (offsets 0-8),
	-- and otherwise the SQUARE's -- hasGridPower, haveElectricity, and a room to be
	-- in at all (40-121). It is the call vanilla's own radio UI leans on
	-- (getPower() > 0 after it, ISRadioAction:isValidSetChannel), and the mod
	-- already reads the pair that way for the TNC.
	--
	-- One word for both gates, and it is the light switch's and the stove's: a
	-- survivor told `tv0: no power` has been told the thing to go and fix.
	--
	-- THE DIAL. setChannel(int) is setChannel(int, true), and its first four
	-- instructions are the other swallowed order:
	--
	--    0-13   below minChannelRange or above maxChannelRange -> return 105,
	--           having done nothing at all.
	--
	-- so a frequency outside the set's own span is refused here too. A frequency
	-- nobody BROADCASTS on is not refused and must not be: vanilla's own window
	-- tunes anywhere in the span and prints "Unknown channel" for it, a television
	-- on a dead frequency shows the test card (IsoTelevision.updateTvScreen,
	-- offsets 79-83), and a refusal the game does not make is a refusal we would
	-- have invented.
	--
	-- What setChannel does BESIDE moving the field is kept, like the stove's
	-- Toggle: the zap (playSoundSend at 21-64, which returns at once on a dedicated
	-- server -- playSound's first three instructions are `if GameServer.server
	-- return` -- so the set clicks in a solo game and is silent on a server), the
	-- loop sound stopped at 65-91, and TriggerPlayerListening(true) at 100-102.
	--
	-- AND THEN THE SYNC, which is ours and is the whole reason this device took a
	-- rung of its own: see CeroSecDevices.SYNC above, and the proof at the head of
	-- client/CeroSec/CCeroSecDevices.lua.
	if entry.kind == "tv" or entry.kind == "rx" then
		local data = waveData(object)
		-- A set whose data went away between the walk and the write. classify asked
		-- the same question through CeroSecModules.isTuneable; this is the belt.
		if data == nil then return false, "no such device" end
		-- Before anything is written, because the write cannot be taken back and a
		-- write nobody can be told about must not happen.
		local class, sprite = waveHandle(entry)
		if class == nil then return false, "no such device" end

		local name, number = CeroSecOS.devArg(entry.kind, value)
		if name == "channel" then
			if number < data:getMinChannelRange() or number > data:getMaxChannelRange() then
				return false, "out of range"
			end
			-- Already there is already done: two `dev tv0 channel 203` in a row are
			-- one television on channel 203, with one zap and one packet.
			if data:getChannel() ~= number then
				data:setChannel(number)
				syncWave(entry, data, class, sprite)
			end
			return true, nil, waveState(object), detailOf(entry.kind, object)
		end

		local want = value == "on"
		if want then
			if not data:canBePoweredHere() then return false, "no power" end
			if data:getIsBatteryPowered()
					and (tonumber(data:getPower()) or 0) <= 0 then
				return false, "no power"
			end
		end
		if data:getIsTurnedOn() ~= want then
			data:setIsTurnedOn(want)
			-- Read back and not assumed: the two gates above are ours and the engine
			-- has a third of its own inside the setter, so a set that did not come on
			-- says the same thing a light switch that did not throw says.
			if data:getIsTurnedOn() ~= want then return false, "no power" end
			syncWave(entry, data, class, sprite)
		end
		return true, nil, waveState(object), detailOf(entry.kind, object)
	end

	-- lock: a map door, or a player-built one.
	if instanceof(object, "IsoDoor") then
		object:setLockedByKey(value == "lock")
		object:syncIsoObject(false, 0, nil, nil)
		return true, nil, object:isLockedByKey() and "locked" or "unlocked"
	end

	local want = value == "lock"
	if object:isLockedByPadlock() or object:canBeLockByPadlock() then
		-- setLockedByPadlock syncs itself, on the server included.
		object:setLockedByPadlock(want)
		return true, nil, thumpState(object)
	end
	-- A padlock is set to keyId -1 when it is taken off
	-- (media/lua/shared/TimedActions/ISPadlockAction.lua:46), and a door built
	-- with no lock at all carries 0, so a real key is a positive one.
	if object:getKeyId() > 0 then
		object:setLockedByKey(want)
		object:syncIsoThumpable()
		return true, nil, thumpState(object)
	end
	return false, "no padlock"
end

--
-- The blink
--

-- Is the object we found still where we found it? Named apart from `alive`
-- above because a blink outlives the command that started it: the square is
-- looked at again on every tick, and a light carried away mid-blink is a light
-- the sweep drops rather than one it keeps calling setActive on.
local function stillThere(blink)
	local object = blink.object
	if object == nil then return false end
	local square = object:getSquare()
	if square == nil then return false end
	return square:getX() == blink.x and square:getY() == blink.y
		and square:getZ() == blink.z
end

local function throw(blink, on)
	if not stillThere(blink) then return false end
	-- The same throw a write takes, so a lamppost blinks for `dev find` too.
	throwLight(blink.object, on)
	return true
end

-- Put the switch back where it was found. A blink that ends is a blink that
-- leaves nothing behind: a survivor who asked which light this was does not
-- want the room's lighting changed for having asked.
local function restore(blink)
	throw(blink, blink.was)
end

-- Drop a light's blink without restoring it. What a WRITE does: somebody who
-- has just typed `dev light0 off` means it, and a blink that ended a second
-- later by putting the light back on would be the machine arguing.
function CeroSecDevices.dropBlink(id)
	local kept = {}
	local blinks = CeroSecDevices.blinks
	for i = 1, #blinks do
		if blinks[i].id ~= id then kept[#kept + 1] = blinks[i] end
	end
	CeroSecDevices.blinks = kept
end

-- One tick of every blink there is. Nothing at all when there are none, which
-- is every tick of every game that is not answering `dev find` right now.
function CeroSecDevices.tick()
	local blinks = CeroSecDevices.blinks
	if #blinks == 0 then return end
	local now = getTimestampMs()

	local kept = {}
	for i = 1, #blinks do
		local blink = blinks[i]
		if now >= blink.endMs or not stillThere(blink) then
			restore(blink)
		else
			if now >= blink.nextMs then
				-- now + BLINK_MS and not nextMs + BLINK_MS: a server that was
				-- busy for two seconds owes nobody four catch-up flips.
				blink.nextMs = now + CeroSecDevices.BLINK_MS
				blink.on = not blink.on
				throw(blink, blink.on)
			end
			kept[#kept + 1] = blink
		end
	end
	CeroSecDevices.blinks = kept
end

-- Start one, or push the end of the one already running out. ok, reason.
local function blink(entry, seconds)
	local object = entry.object
	-- The switch's own rule, the same one a write asks (act, above): a light
	-- that cannot be thrown cannot be blinked either, and says the same thing
	-- about it.
	if not object:canSwitchLight() then return false, "no power" end

	local now = getTimestampMs()
	local endMs = now + seconds * 1000
	local blinks = CeroSecDevices.blinks
	for i = 1, #blinks do
		if blinks[i].id == entry.id then
			blinks[i].endMs = endMs
			return true
		end
	end

	blinks[#blinks + 1] = {
		id = entry.id, object = object,
		x = entry.x, y = entry.y, z = entry.z,
		-- What to put back, read now and not assumed from the state string.
		was = object:isActivated(),
		on = object:isActivated(),
		nextMs = now, endMs = endMs,
	}
	return true
end

-- The class the client is to look for on that square. The server already knows
-- which it is -- it classified the object to make a device of it -- so the
-- client is told rather than left to guess between a map door and a built one.
local function classOf(entry)
	-- A dropped sensor is not on the square's object list at all, so the client
	-- is told to look at the OTHER list -- and the thing that tells one head from
	-- another there is the item's full type and not a sprite name (a world item is
	-- drawn from a model). See CeroSecTerminal:objectAt.
	if entry.kind == "sensor" then return "IsoWorldInventoryObject" end
	-- The kinds the motor rung added carry their own class, written down when
	-- classify made them. It has to be carried and cannot be worked out again
	-- here: a curtain is an IsoCurtain or a DOOR depending on whose sheet it is,
	-- and the laundry is one of three classes with nothing in common but
	-- IsoObject. Guessing between three is two wrong answers, and a wrong class
	-- is an outline the client draws round nothing (CeroSecTerminal:objectAt asks
	-- the engine's own instanceof for it).
	if type(entry.cls) == "string" and entry.cls ~= "" then return entry.cls end
	if entry.kind == "win" then return "IsoWindow" end
	-- A radio is a fixture with a sprite like a light switch, so the outline finds
	-- it the ordinary way: `dev find radio0` is how a survivor with two sets in the
	-- room learns which one his machine is wired to.
	if entry.kind == CeroSecRadio.KIND then return "IsoRadio" end
	if instanceof(entry.object, "IsoDoor") then return "IsoDoor" end
	return "IsoThumpable"
end

-- How that object is found again on the far side: the class above, and ONE of two
-- handles -- a sprite name for a fixture, the item's full type for a dropped head,
-- because getSpriteName on a world item answers a model's name or nothing at all.
--
-- nil for a device that never travels to one screen, which is a LIGHT: a light
-- answers "which one am I" by blinking, where everybody in the room can see it,
-- so nothing about it is ever addressed to a window and getSpriteName is a call
-- this file does not make on a switch.
--
-- One place, because find() sends it and the debug snapshot (SCeroSecDebug) shows
-- it: two answers to "how is this object found again" would be one too many, and
-- the second one would be the one that went stale.
function CeroSecDevices.handleOf(entry)
	if type(entry) ~= "table" or entry.object == nil then return nil end
	if entry.kind == "light" then return nil end
	if entry.kind == "sensor" then
		return classOf(entry), "", CeroSecSensors.typeOf(entry.object)
	end
	return classOf(entry), entry.object:getSpriteName(), ""
end

-- The env.devices table for one machine. Built once per command: the discovery
-- is the expensive half and nothing may ask the world twice inside one line and
-- get two answers.
--
-- system and playerObj are the road back to ONE pair of eyes, and they are
-- optional: a call without them is a machine whose doors cannot be highlighted
-- (the light still blinks, being a thing the world does and not a thing a
-- screen does). They are handed down from the command being run, because a
-- highlight belongs to whoever typed the line and to nobody else standing at
-- the same computer.
function CeroSecDevices.envFor(luaObject, state, system, playerObj, token)
	local list, byId, map = build(luaObject, state)

	return {
		list = function()
			return list
		end,

		write = function(id, value)
			local entry = byId[id]
			if entry == nil or not alive(entry) then return false, "no such device" end
			-- A write ends any blink that light was in the middle of, and does
			-- NOT put the old state back: the word just typed is the newer of
			-- the two intentions.
			CeroSecDevices.dropBlink(id)
			local ok, reason, after, detail = act(entry, value)
			if not ok then return false, reason end
			-- The list the engine is holding is updated too, so a `cat` in the
			-- same breath agrees with what was just done -- and so is the rest of
			-- the line for a kind that has one, because a generator that has just
			-- been started has a tank that is going down from now on.
			if type(after) == "string" then
				entry.state = after
				if type(detail) == "string" then entry.detail = detail end
				for i = 1, #list do
					if list[i].id == id then
						list[i].state = after
						if type(detail) == "string" then list[i].detail = detail end
					end
				end
			end
			return true, nil, after, detail
		end,

		-- Point at one for `seconds`. A light blinks where everybody can see it;
		-- a door or a window is outlined on the requesting player's screen and
		-- on no other, which is what the int first argument of vanilla's
		-- setHighlighted is for (see the head of this file).
		find = function(id, seconds)
			local entry = byId[id]
			if entry == nil or not alive(entry) then return false, "no such device" end

			if entry.kind == "light" then
				local ok, reason = blink(entry, seconds)
				if not ok then return false, reason end
				-- And how it is on this machine, for the one device kind that can be
				-- half a street away: a survivor who is told a light is blinking wants
				-- to know whether to look out of the window (CeroSecOS.linkedText).
				return true, nil, CeroSecOS.linkedText("blinking", entry.wire)
			end

			if system == nil or playerObj == nil then return false, "no such device" end
			-- The device's own square, not the computer's: what travels with a
			-- highlight is where to look, and the token of the window that
			-- asked, which is the only thing a terminal believes.
			-- A fixture is found again on the far side by what it LOOKS like and a
			-- dropped item by what it IS: getSpriteName on a world item answers a
			-- model's name or nothing at all, so a sensor travels on the item's
			-- full type instead and the client uses whichever its class calls for.
			-- Only one of the two is ever asked of an object, because getItem is a
			-- question a light switch has no answer to.
			local class, sprite, item = CeroSecDevices.handleOf(entry)
			if class == nil then return false, "no such device" end
			system:reply(playerObj, "highlight", {
				x = entry.x, y = entry.y, z = entry.z, token = token,
				class = class, sprite = sprite, item = item,
				seconds = seconds,
			})
			return true, nil, CeroSecOS.linkedText("highlighted", entry.wire)
		end,

		-- A chmod on a device node. The node itself is thrown away at the end of
		-- the command, so this is where the new mode survives.
		chmod = function(id, mode)
			for key, record in pairs(map) do
				if type(record) == "table" and record.id == id then
					record.mode = mode
					return
				end
			end
		end,
	}
end

-- The blink clock. Vanilla's own way of getting under a minute on a server
-- (forageServer.lua:502, and the gate inside CeroSecDevices.tick).
Events.OnTick.Add(function()
	CeroSecDevices.tick()
end)

-- The one-minute sweep. Nothing on a screen changes -- a line already printed
-- is a line already printed -- but the book of numbers is brought up to date,
-- so a device that appeared since the machine was last used already has its
-- number by the time somebody types `ls /dev`.
--
-- AND IT IS THE STANDING INVALIDATION of the /dev cache. The sweep walks the
-- building anyway, so the machine's entry is dropped first and then filled with
-- what this very walk found: one walk, and the freshest answer there is. Leaving
-- it to age out under the sweep would have been a second walk a minute for
-- nothing.
function CeroSecDevices.refresh(luaObject, state)
	if state == nil then return end
	CeroSecDevices.forget(luaObject.x, luaObject.y, luaObject.z)
	local found, kept = CeroSecDevices.findCached(
		luaObject.x, luaObject.y, luaObject.z, getTimestampMs(), state.links)
	writeKept(state, kept)
	CeroSecDevices.number(state, found)
end
