# Actuators -- what the server can work, and what it cannot

An inventory of every vanilla object a CeroSec machine could
read or drive from the **server**, with the sync each one
needs, proven against the shipped jar -- **B42.20.4**, read
with

```
javap -p -c -cp .../projectzomboid/projectzomboid.jar <class>
```

-- and against the game's own Lua under
`.../projectzomboid/media/`. The January `decompiled-src` is
older than the jar and is not cited.

The question every row answers is the one
[DEVICES.md](../DEVICES.md#the-sync-calls) already asks of a
setter: **who broadcasts.** Our writes happen on the server
and most of vanilla's happen on a client, so a setter that
syncs for a player does not necessarily sync for us. A write
the other players never see is worse than a refusal.

This note writes down what is buildable. It changes no code,
adds no device and decides no design.

**CORRECTED BY THE RUNGS IT WAS WRITTEN FOR.** Nothing below
is rewritten -- it is the record of what was read, and it
stays as it was read -- but some of its findings were wrong
and one of its open questions is now closed, and all of that
is here at the top where a reader meets it before he acts on
the note:

1. **The window is buildable, and it is built.** Section 7's
   three reasons all stand at the bytecode. What does not
   stand is the note's own aside that the marshalling
   question "does not matter for the verdict": it is the
   whole of the verdict, it is proven now (see "What is not
   proven", last item), and the three side effects that were
   the argument against a window actuator turned out to be
   exactly what a motor on a sash does -- so they became the
   device's rules instead of its refusal.
2. **THE TELEVISION IS WRITTEN, AND THE SYNC IS OURS.**
   Section 2's reading is right in every line and its verdict
   -- READ YES, WRITE NOT *without a sync of our own* -- was
   the conditional it looks like. The condition is met: the
   mod carries the sync, and what "what is not proven" called
   "designed nowhere and measured nowhere" is designed in
   [DEVICES.md](../DEVICES.md#the-sync-the-mod-writes-itself),
   on the wire in [PROTOCOL.md](../PROTOCOL.md) and benched in
   `tests/window_test.lua` section 44c. Three things this note
   did not have:

   - the far end's calls. A client must NOT use the public
     setters -- they transmit, and the server relays it -- so
     it uses `setTurnedOnRaw` and `setChannelRaw`, which are
     the public names of what `receiveDeviceDataStatePacket`
     does on a client (`setIsTurnedOnInternal` at 124-129, a
     bare `putfield channel` at 179-182) and what
     `IsoWaveSignal.loadState` does at 116-154.
   - **LATE JOINERS ARE THE ENGINE'S, not ours.** Every chunk a
     client loads queues a request for that chunk's object
     state (`IsoChunk.doLoadGridsquare`, 1650-1675), and the
     server answers out of the live object
     (`ChunkObjectStateRequestPacket.parse` ->
     `saveObjectState` at 99 -> `IsoObject.saveState` at
     124-127), where `IsoWaveSignal.saveState` writes
     `getIsTurnedOn()` at 73-93 and `getChannel()` at 94-105.
     No chunk hook of ours is needed.
   - **both setters swallow**, which the note read and did not
     draw the conclusion from: `setIsTurnedOn` turns an
     unpowerable set OFF whatever was asked (0-4, 44-58) and
     `setChannel` returns at 105 outside the span (0-13), so
     both refusals are the device's own and come before the
     call, exactly as the barricaded door's does.

   So the table's `tv0` row reads 660 now, its `values` column
   is `on`, `off` and `channel <n>`, and `radio0` stays what it
   is -- the receiver a tuner control buys is a SECOND device
   (`rx0`) beside the TNC and does not touch it.

3. **A polling daemon walks the building ten times a second
   and not once every five.** "The shell: what a daemon
   costs" reasons from jobStep returning above mountDev for a
   sleeping job, which it does -- and the walk is not in
   mountDev. It is one layer higher, and it happens before
   any job is looked at. The note's closing sentence ("that
   number is the first thing the next rung should put on the
   glass") is answered: a sixty-room mall, a hundred passes,
   7,109,900 engine calls and 100 walks with no cache;
   845,990 and 10 with one (hostile_test.lua, section 27).
4. **THE SILENT CALL IS THE RIGHT CALL AND IT IS HALF THE
   GESTURE.** Section 1 is right that `ToggleDoor(chr)` "plays
   a sound at the character" and that `ToggleDoorSilent` is
   therefore the call; section 5 says the same of a door. What
   neither drew is the conclusion a player drew for us on
   0.4.0: a fixture worked in silence is a fixture nobody can
   tell was worked. So the mod plays the hand's own sound
   beside the silent toggle, and the three names are the
   engine's:

   - a door, both classes: `getSoundPrefix()` plus `Open` or
     `Close`. `playDoorSound(BaseCharacterSoundEmitter, String)`
     concatenates the two (offsets 0-16, the `\1\1` recipe in
     the class's BootstrapMethods) and the prefix is the
     `closedSprite`'s `DoorSound` property or `WoodDoor`
     (offsets 0-40 of each `getSoundPrefix`). Which word is
     read off `isOpen()` AFTER the flip (`IsoDoor`
     `ToggleDoorActual` 701-722, `IsoThumpable` 477-514).
   - a curtain of its own: `getSoundPrefix()` plus the same two
     words (`IsoCurtain.ToggleDoor`, 83-129), where the prefix
     is `"Curtain"` plus the `CurtainSound` property, or
     `CurtainShort` (offsets 0-45, recipe `Curtain\1`). Every
     name it can make -- `CurtainShort`, `CurtainLong`,
     `CurtainShade`, `CurtainSheet`, times `Open` and `Close`
     -- is declared in
     `media/scripts/generated/sounds/objects/sounds_object_curtain.txt`.
   - a sash: **nothing in the class**. Section 7 javap'd
     `ToggleWindow` whole and there is no sound in it; the
     noise a survivor makes at a window is an event on his own
     animation, `PlaySound` with `OpenWindow` in
     `media/AnimSets/player/openwindow/success.xml` and
     `CloseWindow` in `closewindow/`, both declared in
     `sounds_object_window.txt`.
   - a door's own sheet: nothing anywhere. `toggleCurtain()`
     has no sound in it and the menu hands it the door, so the
     mod plays `CurtainShort…` -- which is what
     `IsoCurtain.getSoundPrefix()` answers when there is no
     sprite to ask (offsets 0-10) and is a CHOICE, recorded in
     [DEVICES.md](../DEVICES.md#the-sound-the-machine-makes).

   And who hears it is a second question this note never
   asked, with vanilla's own answer in a server file
   (`server/Traps/STrapGlobalObject.lua:118-124`):
   `playServerSound(name, square)` on a server --
   `GameServer.PlayWorldSound`, `if (!server) return` at 0-10,
   then the `udpEngine.connections` walk at 69-171 -- and
   `square:playSound(name, true)` anywhere else, which is the
   solo game.
5. **`IsoCurtain.IsOpen()` IS NOT INVERTED**, which is worth a
   line because it was suspected of being. `open` true is the
   cloth drawn BACK: the engine's own menu offers
   `ContextMenu_Close_curtains` for it
   (`ISWorldObjectContextMenuLogic`, 1415-1433, and 123-142 for
   a door's sheet), `IsoDoor.initCurtainSprites` binds
   `curtainN` to `fixtures_windows_curtains_01_18` and
   `curtainNopen` to `..._22` -- so 0-3 of each eight is the
   closed cloth and 4-7 the open one, which is the `% 8 <= 3`
   `CellLoader` chooses the sprite pair with (678-707) --
   `ISZoneDisplay.canSeeThroughObject` reads `IsOpen()` as
   see-through, and every curtain in the world is BORN open
   (`CellLoader` 709-740, `IsoWindow.addSheet` 192-253 building
   from the open tile, `IsoDoor.addSheet` setting
   `curtainOpen = true` at offset 18). Section 1's vocabulary
   -- `open` and `closed`, `open` and `close` -- reads the
   field the right way round.

## The table

| object | read | actuate | needs a character? | sync | verdict |
| --- | --- | --- | --- | --- | --- |
| `IsoCurtain` (window, built) | `IsOpen()` / `isCurtainOpen()` | `ToggleDoorSilent()` | no | **none needed**, the toggle ends on `syncIsoObject(false, open, null)` at offset 100 | **BUILDABLE** |
| `IsoDoor` curtain (a door's own sheet) | `isCurtainOpen()`, `HasCurtains()` | `toggleCurtain()`, or `setCurtainOpen(b)` | no | **none needed**, `toggleCurtain` calls `transmitSetCurtainOpen` on the server branch at offset 55 | **BUILDABLE** |
| `IsoStove` (oven, microwave, **coffee machine**) | `Activated()`, `getTimer()`, `getCurrentTemperature()`, `isBroken()` | `Toggle()`, `setActivated(b)`, `setTimer(n)`, `setMaxTemperature(t)` | no | **none needed**, `setActivated` server branch at offset 207 calls `sync()` and `syncSpriteGridObjects(true,true)` | **BUILDABLE** |
| `IsoGenerator` | `isActivated()`, `getFuel()`, `getCondition()`, `isConnected()` | `setActivated(b)` | no | **none needed**, server branch at offset 119 calls `sync()`; vanilla calls `sync()` again after it | **BUILDABLE** |
| lamps (`IsoLightSwitch` with `getCanBeModified()`) | `isActivated()`, `canSwitchLight()` | `setActive(b)` | no | none needed, as `light` already | **ALREADY BUILT** |
| `IsoDoor` / `IsoThumpable` door | `IsOpen()`, `isLockedByKey()` | `ToggleDoorSilent()` | no | ours: `syncIsoObject(false, 0, nil, nil)` | **ALREADY BUILT**, path unchanged in 42.20.4 |
| `IsoBarbecue` | `isLit()`, `getFuelAmount()`, `hasPropaneTank()`, `isSmouldering()` | `setLit(b)` / `turnOn()` / `extinguish()` | no | ours: `sendObjectChange(IsoObjectChange.STATE)`, which is server-only by construction | **BUILDABLE**, with a warning |
| `IsoFireplace` | `isLit()`, `getFuelAmount()` | `turnOn()` / `extinguish()` | no | ours: `sendObjectChange(IsoObjectChange.STATE)` | **BUILDABLE**, with the same warning |
| `IsoClothingWasher` / `IsoClothingDryer` / `IsoCombinationWasherDryer` | `isActivated()` | `setActivated(b)` | no | ours: `sendObjectChange(IsoObjectChange.WASHER_STATE)` | **BUILDABLE** |
| `IsoStackedWasherDryer` | `isWasherActivated()`, `isDryerActivated()` | `setWasherActivated(b)`, `setDryerActivated(b)` | no | ours: `sendObjectChange(IsoObjectChange.WASHER_STATE)` | **BUILDABLE**, but no map tile carries it |
| `IsoCompost` | `getCompost()`, `getHealth()` | nothing to actuate | none | `syncCompost()` has a server branch | **BUILDABLE, read only** |
| `IsoTelevision` / `IsoRadio` (`IsoWaveSignal`) | `getDeviceData()` -> `getIsTurnedOn()`, `getChannel()`, `getPower()`, `getDeviceVolume()` | `setIsTurnedOn(b)`, `setChannel(n)` | no | **NONE THAT WORKS.** `transmitDeviceDataState(short)` has a **client branch only**; the server one is `private` | **READ YES, WRITE NOT** without a sync of our own |
| `IsoWindow` sash | `IsOpen()`, `isSmashed()`, `isBarricaded()` | `ToggleWindow(chr)` only | see section 7 | `sync(open)` inside it, so the sync is not the problem | **NOT** -- and the reason needs correcting (**and the verdict was corrected too: see the top of this file**) |
| `IsoTrap` | `getSensorRange()` etc. | detonation | none | none | **NEVER**, and that is already the rule |
| `IsoJukebox` | `isPlaying` is private | `SetPlaying(b)` | no | **none at all**, and no `save`/`load` | **NOT** |
| alarm clock | `isAlarmSet()`, `getHour()`, `isRinging()` | `setAlarmSet(b)`, `setHour(n)` | no | `syncAlarmClock_World()` | **UNCERTAIN**, it is an item and not a fixture |
| house alarm | none | none | none | none | **NOT**, `zombie.iso.Alarm` is a sound and nothing else |

Everything with a verdict of BUILDABLE was checked for the
two things a device needs beside the call: that the state
**persists** (the class's own `save`/`load`) and that
modData on it persists, so a module can sit on it. Both are
noted in their sections.

## 1. Curtains, and there are two of them

A curtain is not one thing in Build 42. It is two, and the
difference decides everything else.

**A window's curtain, and a player-built frame's, is its own
object.**

```
zombie.iso.objects.IsoCurtain
  public boolean IsOpen();          public boolean isCurtainOpen();
  public void ToggleDoor(zombie.characters.IsoGameCharacter);
  public void ToggleDoorSilent();
  public boolean getNorth();
  public static boolean isSheet(zombie.iso.IsoObject);
  public void syncIsoObject(boolean, byte, UdpConnection);
```

`isCurtainOpen()` is `IsOpen()` forwarded, one instruction
of it (offsets 0-4), so either name reads the sash-cloth.

**`ToggleDoorSilent()` takes no character and broadcasts
itself.** Whole, at the bytecode:

```
  0: getfield  #268  // Field barricaded:Z
  4: ifeq      8
  7: return                       <- a boarded curtain is refused
  8: invokevirtual #129           // DirtySlice()
 12-30: LosUtil.cachecleared[i] = true, per player
 33-45: GameTime.lightSourceUpdate = 100f
        IsoGridSquare.setRecalcLightTime(-1f)
 46-59: putfield #120  // open = !open
 62-84: sprite := open ? openSprite : closedSprite
 85-100: invokevirtual #304
         // syncIsoObject:(ZBLzombie/core/raknet/UdpConnection;)V
         //   (false, open ? 1 : 0, null)
103: return
```

That last call is the whole answer to the sync question, and
it is the one place a curtain differs from a door:
`IsoDoor`'s own `ToggleDoorSilent` syncs **nothing** and the
broadcast is ours (DEVICES.md), while `IsoCurtain`'s does it
itself. `IsoCurtain` overrides
`syncIsoObject(boolean, byte, UdpConnection)` and its server
branch is the familiar walk:

```
 156: getstatic #27   // GameServer.server:Z
 159: ifeq      229
 162: getstatic #566  // GameServer.udpEngine
 165: getfield  #570  // UdpEngine.connections:Ljava/util/List;
 168-226: for each UdpConnection:
          startPacket, PacketType.SyncIsoObject.doPacket,
          syncIsoObjectSend(writer), send(connection)
 229-320: RecalcProperties, RecalcAllWithNeighbours(true),
          LosUtil caches, light time, dirtyGlobalLightsCount,
          LuaEventManager.triggerEvent("OnContainerUpdate")
 321: invokevirtual #607  // flagForHotSave()
```

and `syncIsoObjectSend` writes x, y, z, the object's index
in `square.getObjects()`, a `true`, and then the `open`
field (offsets 54-62). So the flag a client needs is in the
packet, the chunk is marked to be written out, and **a
curtain toggled on the server needs nothing added to it.**

One condition on that: `syncIsoObject` returns at offset 31
without sending anything when `getObjectIndex() == -1`.
`getObjectIndex()` is `square.getObjects().indexOf(this)`
(`IsoObject`, offsets 9-20), and
`IsoGridSquare.AddSpecialObject(IsoObject, int)` adds a
curtain to **both** lists -- `objects` at offsets 25-56 and
`specialObjects` at 57-65 -- so a curtain that is in the
world has an index. It also means the discovery needs no
second walk: `CeroSecDevices.scanSquare` already reads
`getObjects()` and a curtain is on it.

**How vanilla does it.**
`media/lua/shared/TimedActions/ISOpenCloseCurtain.lua`,
`complete()` whole:

```lua
	if instanceof(self.item, "IsoDoor") then
    	self.item:toggleCurtain()
    elseif instanceof(self.item, "IsoWindow") then
        self.item:openCloseCurtain(self.character)
    else
    	self.item:ToggleDoor(self.character);
   	end
```

Three paths, and the middle one is a trap for us.
`IsoWindow.openCloseCurtain(IsoGameCharacter)` begins

```
  0: aload_1
  1: invokestatic #666  // IsoPlayer.getInstance()
  4: if_acmpne    132   // not the local player -> return
```

so it does nothing at all except for the character sitting
at the keyboard. What it does when it does run is walk
`getSpecialObjects()` of the square on the far side and call
`IsoCurtain.ToggleDoorSilent()` on the first curtain it
finds (offsets 84-125). So the server's road is the object
and not the window: `window:HasCurtains()` answers the
`IsoCurtain` (`IsoWindow.HasCurtains()`,
`getOppositeSquare():getCurtain(curtainS|curtainE)` then its
own square), and then `ToggleDoorSilent()` on it.

**That is vanilla's own server-safe line, written by
vanilla.**
`media/lua/client/DebugUIs/Scenarios/Trailer2Scenario.lua:134`

```lua
		window1:HasCurtains():ToggleDoorSilent();
```

and `Tutorial1.lua:251` does the same on a curtain it
fetched the same way. A curtain toggled with nobody holding
it is a thing the game already does.

`ToggleDoor(chr)` is the one to leave alone: it plays a
sound at the character, and when `locked` is set it refuses
to **open** for anybody standing outside a room (offsets
12-40). `ToggleDoorSilent` reads neither, which is right for
a motor and is why it is the call.

**A door's curtain is a field on the door.** There is no
`IsoCurtain` for it at all:

```
zombie.iso.objects.IsoDoor
  private boolean hasCurtain;   private boolean curtainOpen;
  public boolean canAddCurtain();
  public zombie.iso.objects.IsoDoor HasCurtains();
  public boolean isCurtainOpen();
  public void setCurtainOpen(boolean);
  public void transmitSetCurtainOpen(boolean);
  public void toggleCurtain();
```

`HasCurtains()` answers **the door itself** when
`hasCurtain` is set and null otherwise (offsets 0-12), which
is why `IsoCurtain.isSheet` has three `instanceof` branches
and why `ISWorldObjectContextMenu.lua:2238` re-fetches
before it reads a sprite.

`toggleCurtain()` is server-clean and self-syncing:

```
  0: getfield  #40   // hasCurtain:Z
  4: ifne      8
  7: return                    <- a door with no sheet does nothing
  8: getstatic #798  // GameClient.client:Z
 11: ifeq      33
 14-27: transmitSetCurtainOpen(!isCurtainOpen())   <- client asks
 33-46: setCurtainOpen(!isCurtainOpen())
 49: getstatic #909  // GameServer.server:Z
 52: ifeq      63
 55-60: transmitSetCurtainOpen(isCurtainOpen())    <- server tells
 63: return
```

and `transmitSetCurtainOpen(boolean)`'s server branch is a
`sendObjectChange` and not a `syncIsoObject`:

```
  8: getstatic #909  // GameServer.server:Z
 11: ifeq      38
 14-35: sendObjectChange(IsoObjectChange.SET_CURTAIN_OPEN,
                         new Object[]{ "open", Boolean.valueOf(arg) })
```

So on the server, one call -- `door:toggleCurtain()` -- sets
the field and broadcasts it. `setCurtainOpen(b)` alone is
the half that does not broadcast; it is also the half that
**skips the light and LOS recalculation when
`GameServer.server` is true** (offset 13, `ifne 77`), which
is correct on a dedicated server and is vanilla's own
arithmetic, not ours to second-guess. For an absolute set
rather than a toggle the pair is `setCurtainOpen(b)` then
`transmitSetCurtainOpen(b)`, which is exactly what
`toggleCurtain` does on the server.

**It persists.** `IsoDoor.save` writes `hasCurtain` at
offset 128 and `curtainOpen` at 140; `IsoDoor.load` reads
them back at 155 and 171. `IsoCurtain.save` writes `open` at
offsets 7-19 and `IsoCurtain.load` reads it at 7-20, and
both begin with `invokespecial IsoObject.save` and
`invokespecial IsoObject.load` at offset 3, so a module's
modData on a curtain is saved with the chunk under the same
flag bit as a door's (modules-proofs.md, 1).

**Reading the state, and what the words are.** A curtain has
one fact and it is a boolean: `IsOpen()`. There is no lock
and no barricade of its own worth reporting except the
`barricaded` field the toggle itself refuses on, which is
the same refusal a door already makes and in the same place
(ours, before the call, because the engine's is a silent
`return`). So the vocabulary is `open` and `close`, and the
states are `open` and `closed` -- a door's words without its
`locked`.

**Where a curtain can be at all.** `IsoDoor.canAddCurtain()`
is false for a garage door (`IsoPropertyType.GARAGE_DOOR`),
false for a `SlidingGlassDoor` by sound prefix, and
otherwise the sprite property `doorTrans` (offsets 11-45). A
survivor's bedsheet and a map curtain are both `IsoCurtain`;
`IsoCurtain.isSheet(object)` is the static that tells them
apart, on the sprite property `CurtainSound == "Sheet"`
(offsets 69-98). Nothing here needs the difference, but a
listing that wanted to say "sheet" has the call.

## 2. Television and radio: read yes, write no

The device data is one class for a TV, a radio, a walkie and
a car stereo, and it is where everything lives:

```
zombie.radio.devices.DeviceData
  public boolean getIsTurnedOn();  public void setIsTurnedOn(boolean);
  public int getChannel();         public void setChannel(int);
  public void setChannel(int, boolean);   public void setChannelRaw(int);
  public float getPower();         public boolean canBePoweredHere();
  public float getDeviceVolume();  public void setDeviceVolume(float);
  public boolean getIsTelevision();public boolean getIsTwoWay();
  public void transmitBatteryChangeServer();
  private void transmitDeviceDataState(short);
  private void transmitDeviceDataStateServer(short, UdpConnection);
  private void sendDeviceDataStatePacket(UdpConnection, short);
```

`SCeroSecRadio.lua` already proves the reading side of this
whole list and reads it the way vanilla's own radio UI does
(`getIsTurnedOn()` and `getPower() > 0`, after
`ISRadioAction:isValidSetChannel`). A television is the same
class with `getIsTelevision()` true, and `IsoTelevision`
extends `IsoWaveSignal`, which carries
`protected DeviceData deviceData` and answers
`getDeviceData()`. So **reading a TV costs nothing new** and
is proven already.

**Writing it does not reach the other players.** Both public
setters do call the transmitter:

```
setIsTurnedOn(boolean)
   0: invokevirtual #437  // canBePoweredHere()
   4: ifeq 44
  23-28: setIsTurnedOnInternal(arg)      (or (false) with a flat battery)
  36-38: invokevirtual #364  // transmitDeviceDataState:(S)V   <- state 0
  44-58: (unpowerable) turn off, transmit state 0
 118-127: IsoGenerator.updateGenerator(getParent().getSquare())
setChannel(int) -> setChannel(int, true)
  16-18: channel = arg, inside min/max
  21-64: playSoundSend("TelevisionZap" | "VehicleRadioZap" | "RadioZap")
  91-93: invokevirtual #364  // transmitDeviceDataState:(S)V   <- state 1
 100-102: TriggerPlayerListening(true)
```

and `transmitDeviceDataState(short)` is a **client branch
and nothing else**:

```
private void transmitDeviceDataState(short);
   0: getstatic #276  // GameClient.client:Z
   3: ifeq      37                       <- not a client: return
   6-12: VoiceManager.getInstance().UpdateChannelsRoaming(...)
  15-20: sendDeviceDataStatePacket(GameClient.connection, arg)
  37: return
```

The server's broadcaster exists and is **`private`**:
`transmitDeviceDataStateServer(short, UdpConnection)`, whose
body is the `GameServer.udpEngine.connections` walk (offsets
0-63). Every one of its callers is inside the class:
`receiveDeviceDataStatePacket` (the server relaying what a
client did, eight times over), `addBattery`, `getBattery`,
`addMediaItem`, `removeMediaItem`, `StartPlayMedia`,
`StopPlayMedia`, `updateMediaPlaying`,
`update(boolean, boolean)` and the one public wrapper,
`transmitBatteryChangeServer()`.

That wrapper cannot be borrowed. The `short` picks a field
out of a `tableswitch 0..10` in `sendDeviceDataStatePacket`
(offset 345), and the numbers are: **0** `isTurnedOn`, **1**
`channel`, **2** `hasBattery` + `powerDelta`, **3**
`powerDelta`, **4** `deviceVolume`, **5** presets, **6**
headphones, **7**-**10** recorded media.
`transmitBatteryChangeServer()` passes `2`. It carries the
battery and it cannot carry the switch.

The only server-side state-0 broadcast in the class is in
`DeviceData.update(boolean, boolean)`, and it fires **only
when the engine is turning the device off** because the
power ran out:

```
 238: getfield #434  // isTurnedOn:Z
 242: ifeq 307
 245-265: battery flat, or not canBePoweredHere()
 268-270: setIsTurnedOnInternal(false)
 277-286: if GameServer.server:
          transmitDeviceDataStateServer(0, null)
```

So the honest statement is: **a server-side
`setIsTurnedOn(true)` moves the field on the server and
leaves every client's copy dark and silent.** Vanilla never
makes that call from the server either -- every
`setIsTurnedOn` in `media/lua/` is a client UI path
(`RadioCom/ISRadioAction.lua:51`, `ISRadioWindow.lua:153`)
or turns something **off** while it is being picked up
(`Moveables/ISMoveablesAction.lua:133` and `:191`,
`ISVehicleDashboard.lua:544`). And `setChannel` is called
from exactly two places, one of them the same client timed
action -- which is the proof `SCeroSecRadio.lua` already
writes down as proof 7 and the reason `/dev/radio0` is
read-only.

A `/dev/tv0` that can be written is therefore buildable
**only if the mod carries the sync itself**: server writes
the field, then
`sendServerCommand(player, CeroSec.MODULE, ...)` to every
client that has the chunk, and the client calls
`setIsTurnedOn` on its own copy. The mod already has that
channel (`CeroSec.MODULE`, `Events.OnServerCommand` in
`CCeroSecSystem.lua:69`). It would be the first device whose
sync is ours rather than the engine's, and that is a
decision and a cost, not a proof, so it is left here as one.

**The Life and Living schedule is live and the engine will
answer it.** The mod does not have to carry a copy of
`RadioData.xml`.

`getZomboidRadio()` is reachable from where this mod runs --
vanilla's own **server** Lua calls it
(`media/lua/server/radio/ISDynamicRadio.lua:32` and `:145`)
-- and the chain under it is read by vanilla's own debugger,
`media/lua/client/DebugUIs/DebugMenu/radio/ZomboidRadioDebug.lua`:

```lua
    self.scriptManager = self.radio:getScriptManager();      -- :30
    local channels = self.scriptManager:getChannelsList();   -- :103
        local channel = channels:get(i);
        local name = channel:GetName();
    ... tostring(_radioChannel:GetFrequency())               -- :146
    ... tostring(_radioChannel:IsTv())                       -- :147
    local bc = _radioChannel:getAiringBroadcast();           -- :172
        local lines = bc:getLines();
```

which is `RadioScriptManager.getChannelsList()` ->
`ArrayList<RadioChannel>`, and on a channel:

```
zombie.radio.scripting.RadioChannel
  public int GetFrequency();   public java.lang.String GetName();
  public boolean IsTv();       public ChannelCategory GetCategory();
  public RadioScript getCurrentScript();
  public RadioBroadCast getAiringBroadcast();
zombie.radio.scripting.RadioScript
  public ArrayList<RadioBroadCast> getBroadcastList();
  public RadioBroadCast getValidAirBroadcastDebug();
zombie.radio.scripting.RadioBroadCast
  public java.lang.String getID();
  public int getStartStamp();  public int getEndStamp();
```

so "what is airing now on channel X" is
`getAiringBroadcast()`, and "what is on today" is
`getCurrentScript():getBroadcastList()` with each entry's
`getStartStamp()` and `getEndStamp()`.

**The stamps are minutes of the day.** `Life and Living TV`
in `media/radio/RadioData.xml:6799` is

```xml
    <ChannelEntry ID="9f7e..." name="Life and Living TV"
                  cat="Television" freq="203" startscript="main">
      <ScriptEntry ID="6dbd..." name="main" startdelay="0"
                   timestampmode="Static" loopmin="1" loopmax="1">
        <BroadcastEntry ID="465e..." timestamp="0" endstamp="360"
                        type="ActivateBroadcast" day="0" ... >
          <LineEntry ID="1ccb..." r="255" g="192" b="0" />
          ... codes="FIS+1" ... codes="RCP=Make Fishing Rod"
        </BroadcastEntry>
        <BroadcastEntry timestamp="360"  endstamp="720"  ...  COO+1
        <BroadcastEntry timestamp="720"  endstamp="1080" ...  CRP+1
```

Four six-hour blocks -- 0, 360, 720, 1080 -- which is
midnight, six, noon and six in the evening, and each block
is one subject (the `codes` on the lines are the skill it
teaches). So a program that wants the TV on for the show
reads the block the clock is in and the block's `endstamp`.

**Two things about the parser, both proofs of absence.**
`RadioData.loadBroadcast` builds each broadcast out of three
attributes and no more --

```
   2: ldc_w #478  // String ID
  11: ldc_w #541  // String timestamp
  21: ldc_w #543  // String endstamp
  44,51: Integer.parseInt
  90-99: new RadioBroadCast(id, timestamp, endstamp)
```

-- so the `day` attribute on a `BroadcastEntry` is **not
read at all** in this build, and neither are `startdelay` or
`timestampmode`. A stamp is a time of day and carries no
date.

And `getValidAirBroadcast()` **writes**: offsets 42-44 set
`currentHasAired = true` on the way out. Asking it would
take a broadcast away from the radio's own simulation. The
pure readers are `getAiringBroadcast()` and
`getValidAirBroadcastDebug()`, which is the one vanilla's
debugger falls back on, and they are the two to use.

**And it runs where we run.**
`ZomboidRadio.UpdateScripts(int,int)` drives the script
manager in `GameMode.Server` **and**
`GameMode.SinglePlayer`:

```
   5: getstatic #432  // GameMode.Server
   9: if_acmpeq 19
  12: getstatic #435  // GameMode.SinglePlayer
  16: if_acmpne 85
  45-62: scriptManager.UpdateScripts(daysSinceStart, hour, minute)
```

and `getGameMode()` is `SinglePlayer` when neither
`GameClient.client` nor `GameServer.server` is set (offsets
0-15), `Server` when the server flag is (16-25). That is the
same pair `ZomboidRadio.SendTransmission` covers, which is
why `SCeroSecRadio.lua` uses it.

**One call worth looking for does not exist.** There is no
`ZomboidRadio.getFullChannelName`. What there is:
`getChannelName(int)`, `GetChannelList(String)` and
`getFullChannelList()`. Nothing in this note needs any of
them.

## 3. The stove, the microwave, and the coffee machine

```
zombie.iso.objects.IsoStove
  public boolean Activated();      public void Toggle();
  public void setActivated(boolean);
  public void setTimer(int);       public int getTimer();
  public float getMaxTemperature();public void setMaxTemperature(float);
  public float getCurrentTemperature();
  public boolean isTemperatureChanging();
  public int isRunningFor();       public boolean isMicrowave();
  public boolean isBroken();       public void setBroken(boolean);
  public void PlayToggleSound();   public void sync();
```

**`setActivated` syncs itself from the server.** Its tail:

```
 170: invokevirtual #481  // doSound()
 174-198: HasLightOnSprite -> invalidateRenderChunkLevel(256L)
 201: getstatic #65   // GameServer.server:Z
 204: ifeq 220
 207: invokevirtual #508  // sync()
 211-214: syncSpriteGridObjects(true, true)
 220: getstatic #70   // GameClient.client:Z
 223: ifne 232
 226-229: syncSpriteGridObjects(true, false)
 232: return
```

`sync()` on `IsoStove` is its own override -- `sync()` ->
`sync(activated? 1: 0)` -> `IsoObject.sync(int)` ->
`syncIsoObject(false, byte, null, null)` -- and `IsoStove`
overrides that too, with the connections walk at offsets
172-262 and a `syncIsoObjectSend` that writes `activated`
(54-62), `secondsTimer` (63-68) and `maxTemperature`
(71-76). So the state a client needs is all in the packet.

It also refuses on the one condition that matters:
`isBroken()` -> `return` at offsets 0-7, before anything is
written.

**`Toggle()` is the whole vanilla gesture** and it is three
calls:

```
  0-13: setActivated(!activated)
 16-20: getContainer().addItemsToProcessItems()
 23-27: IsoGenerator.updateGenerator(square)
```

and it is what the **server** calls.
`media/lua/server/ClientCommands.lua:1049-1062`, whole:

```lua
Commands.stove.setOvenParamsAndToggle = function(player, args)
	local sq = getSquare(args.x, args.y, args.z);
	if sq then
		for i=0, sq:getObjects():size()-1 do
			local obj = sq:getObjects():get(i);
			if instanceof(obj, "IsoStove") then
				obj:setTimer(args.timer);
				obj:setMaxTemperature(args.maxTemperature);
				obj:Toggle();
			end
		end
	end
end
```

That is the pattern, written by vanilla, on the server, with
no character anywhere in it.
`ISToggleStoveAction:complete()` is one line,
`self.object:Toggle()`, and `PlayToggleSound()` is separate
and belongs to the survivor's hands -- so a machine that
works a stove is silent, which is right.

**The power test is the container's and not ours.** Vanilla
asks `object:getContainer():isPowered()` and it asks it in
three places (`ISInventoryPaneContextMenu.lua:988`,
`LootWindow/Handlers/StoveToggle.lua:8`,
`StoveSettings.lua:8`). A `no power` refusal reads off that,
the way `light`'s reads off `canSwitchLight()`.

**The timer and the temperature are one field each and both
go out in the packet.** `setTimer(int)` is seconds;
`setActivated` uses it to compute `startTime` and `stopTime`
in world-age hours (offsets 116-152) and, when nothing has
been set yet, defaults the temperature to 100 for a
microwave and 200 for a stove (offsets 20-76).
`getCurrentTemperature()` answers the field plus 100
(offsets 0-7), so it is degrees and not a fraction.

**And the coffee machine is an `IsoStove`.** This is the
answer to "is the coffee machine an object class at all",
and it is better than the question expected.
`media/newtiledefinitions.tiles.txt`, the
`GroupName = Coffee` tiles (`appliances_cooking_01_56` and
`_57`, lines 4339-4370):

```
    tile
    {
        xy = 0,7
        CustomName = X-press
        Facing = S
        GroupName = Coffee
        IsMoveAble =
        IsoType = IsoStove
        Material = Electric
        ...
        container = stove
    }
```

`isMicrowave()` and `isStove()` both read the
**container's** type and not the sprite
(`ItemContainer.isMicrowave()` / `.isStove()`, offsets 0-22
each), so a coffee machine with `container = stove` is a
stove as far as the class is concerned: it takes the
200-degree default and the `ToggleStove` sound. One device
kind covers the oven, the microwave and the coffee machine,
and a coffee machine needs nothing of its own.

The full list of what carries an `IsoType` in any of the
game's five `.tiles.txt` files, counted:

| IsoType | tiles |
| --- | --- |
| `IsoStove` | 54 |
| `IsoRadio` | 48 |
| `IsoBarbecue` | 33 |
| `IsoFireplace` | 24 |
| `IsoFeedingTrough` | 16 |
| `IsoMannequin` | 13 |
| `IsoTelevision` | 12 |
| `IsoCompost` | 4 |
| `IsoCombinationWasherDryer` | 4 |
| `IsoClothingWasher` | 4 |
| `IsoClothingDryer` | 4 |
| `IsoBrokenGlass` | 4 |

`IsoStackedWasherDryer` is in none of them, so no map tile
makes one and a player would have to place it; and doors,
windows, curtains and light switches are in none of them
either because they come from sprite flags and not from
`IsoType`.

## 4. Lamps, and the generator

**A table lamp is an `IsoLightSwitch`, so the relay already
covers it.** There is **no `IsoLightSwitch.isLamp`** in this
jar. What there is, is

```
zombie.iso.objects.IsoLightSwitch
  private boolean canBeModified;
  public boolean getCanBeModified();  public void setCanBeModified(boolean);
  public boolean hasLightBulb();      public java.lang.String getBulbItem();
  public boolean getUseBattery();     public boolean getHasBattery();
  public boolean canSwitchLight();
  public boolean setActive(boolean);  public boolean toggle();
  public boolean isActivated();
```

and the constructor decides `canBeModified` from one sprite
property:

```
  94: invokevirtual #59  // IsoSprite.getProperties()
  97: ldc  #77           // String IsMoveAble
  99: invokevirtual #79  // PropertyContainer.has(String)
 107: putfield #82       // canBeModified:Z
```

which is what vanilla's own comment says in as many words,
at
`media/lua/client/ISUI/ISWorldObjectContextMenu.lua:1301`:

> lightbulbs can be changed regardless, as long as the lamp can be
> modified (which are all isolightswitches that are movable, see
> IsoLightSwitch constructor)

So a lamp on a table, a wall switch and a streetlight are
one class. `light` is already the kind, `setActive(on)` is
already the call, `canSwitchLight()` is already the power
rule (a bulb, and electricity or a charged battery), and a
relay fits a lamp today with no change at all. The only
thing the next rung could add here is a **description** that
says "lamp" where `getCanBeModified()` is true, and the
colour a lamp has: `getPrimaryR/G/B()`.

**The generator reads and drives, and syncs itself.**

```
zombie.iso.objects.IsoGenerator
  public boolean isActivated();   public void setActivated(boolean);
  public float getFuel();         public void setFuel(float);
  public float getFuelPercentage();public float getMaxFuel();
  public int getCondition();      public void setCondition(int);
  public boolean isConnected();   public void setConnected(boolean);
  public void failToStart();
  public ArrayList<String> getItemsPowered();
  public float getTotalPowerUsing();
  public double getBasePowerConsumption();
```

`setActivated(boolean)`:

```
  0-8: arg == activated -> return       <- idempotent by construction
  9-45: square not exterior and in a building -> building.setToxic(arg)
 50-79: lastHour := worldAgeHours; playGeneratorSound("Starting"|"Stopping")
 82-94: updateFridgeFreezerItems()
 94-99: activated := arg; setSurroundingElectricity()
103-112: if GameClient.client: sync()
113-122: if GameServer.server: sync()    <- ours, for free
```

`sync()` here is `IsoObject.sync()` ->
`syncIsoObject(false, 0, null, null)`, the same call the
door already makes, and `IsoGenerator.syncIsoObjectSend` is
its own. `setConnected` and `setCondition` carry the
identical pair of branches (offsets 5-25 and 14-34).

**It checks nothing before it starts.** No fuel test, no
condition test. Vanilla's own gate is in the timed action
and is worth copying exactly --
`media/lua/shared/TimedActions/ISActivateGenerator.lua`,
`isValid` and `complete`:

```lua
	if self.activate == self.generator:isActivated() then return false end
	if self.activate and not self.generator:isConnected() or
			self.generator:getFuel() <= 0 or
			self.generator:getCondition() <= 0 then
		return false
	end
	return self.generator:getObjectIndex() ~= -1
...
	if self.activate and self.generator:getCondition() <= 50 and ZombRand(2) == 0 then
		self.generator:failToStart()
	else
		self.generator:setActivated(self.activate)
	end
	self.generator:sync()
```

Four refusals a machine should make in its own words --
`not connected`, `no fuel`, `broken`, and the state it is
already in -- and a fifth thing that is a **survivor's** and
not a machine's: `failToStart()` on a coin flip below half
condition. A machine that pull-started a generator would be
a machine doing what a shoulder does. Whether `/dev/gen0`
may start one at all is a design question for the next rung;
what is proven is that it can, and that reading it -- fuel,
condition, connected, what it is powering -- is free and has
no side effect.

## 5. Doors, re-confirmed on 42.20.4

Unchanged. `IsoDoor.ToggleDoorSilent()` and
`IsoThumpable.ToggleDoorSilent()` are still there, still
take no character, still sync nothing of their own, and
`syncIsoObject(false, 0, nil, nil)` is still the broadcast,
whose server branch is still the
`GameServer.udpEngine.connections` walk. The two statics the
operator's fit rule uses are still public:
`IsoDoor.getDoubleDoorIndex(IsoObject)` and
`IsoDoor.getGarageDoorIndex(IsoObject)`, and vanilla still
asks them that way
(`server/BuildingObjects/ISBuildUtil.lua:556`,
`ISDoubleDoor.lua:315`).

**The double door and the garage door are still out, for the
reason they were out.** `ToggleDoorSilent` moves the one
object it is called on; vanilla's own `ToggleDoor` walks
every leaf through `forEachDoorObject`. A machine that
opened one leaf would leave the rest shut. Nothing in this
jar adds a silent toggle that walks the leaves, so
`CeroSecModules.fitsOn`'s `manydoors` refusal stands as
written.

One thing a later rung could look at and this one did not:
whether calling `ToggleDoorSilent` on **each** leaf in turn,
found through the same two statics, is a faithful garage
door or a door that moves in pieces. That is a behaviour
question and needs a screen, not a `javap`.

## 6. The rest, one paragraph each

**`IsoBarbecue` and `IsoFireplace` light and go out with no
character, and the sync is ours.** Both carry `isLit()`,
`setLit(boolean)`, `turnOn()`, `extinguish()`, `hasFuel()`,
`getFuelAmount()`, `addFuel(int)`, `useFuel(int)`,
`getTemperature()`; the barbecue adds `toggle()`,
`turnOff()`, `isPropaneBBQ()`, `hasPropaneTank()`. Every one
of those writers is a **bare field write**:
`setLit(boolean)` is three instructions, `turnOn()` is
`setLit(true)` plus
`getContainer().addItemsToProcessItems()`, `extinguish()` is
`setLit(false)` plus a reset of `minutesSinceExtinguished`.
Not one of them syncs.

The broadcast is `sendObjectChange(IsoObjectChange.STATE)`,
and that is **server-only by construction**:

```
public void sendObjectChange(zombie.core.properties.IsoObjectChange);
   0: getstatic #83   // GameServer.server:Z
   3: ifeq      18
   6-12: GameServer.sendObjectChange(this, change, null)
  18: getstatic #489  // GameClient.client:Z
  21: ifeq      33
  24-27: DebugLog.log("sendObjectChange() can only be called on the server")
  33-39: SinglePlayerServer.sendObjectChange(this, change, null)
```

so it covers a dedicated server and a solo game and refuses
a client in its own words -- which is the shape this mod
wants. What goes on the wire is `saveChange(STATE, ...)`:
for the barbecue `getFuelAmount()`, `isLit()`,
`hasPropaneTank()` (offsets 7-32); for the fireplace
`getFuelAmount()` and `isLit()` (7-23). And vanilla makes
exactly this pair on the server, twice:
`media/lua/server/ClientCommands.lua:401-402` (fireplace)
and `:425-426` (barbecue), `setFuelAmount(n)` then
`sendObjectChange(IsoObjectChange.STATE)`.

**The warning.** A computer that lights a fire is a computer
that starts a fire. `setLit(true)` with no fuel, and the
sprite, the heat source and the smoke that `update()` builds
off it, are a kitchen that burns down while nobody is in the
room -- and a survivor cannot put it out from the same
machine, because `ISPutOutFire.lua` is a pair of hands. That
is a design refusal to make deliberately, not a proof, and
it belongs in the same drawer as "never an operator" in
[DEVICES.md](../DEVICES.md#hardware-that-was-already-fitted):
a building that opened its own doors would open them for the
dead, and a building that lit its own fires would light them
for nobody. Reading `isLit()` and `getFuelAmount()` has no
such cost.

**Washers and dryers actuate cleanly.** `IsoClothingWasher`,
`IsoClothingDryer` and `IsoCombinationWasherDryer` each
answer `isActivated()` / `setActivated(boolean)` and forward
both to a `ClothingWasherLogic` or `ClothingDryerLogic`;
`IsoStackedWasherDryer` splits them into
`isWasherActivated()` / `setWasherActivated(boolean)` and
the dryer pair. `ClothingWasherLogic.setActivated(boolean)`
is a field write plus
`IsoGenerator.updateGenerator(getObject().getSquare())`
guarded on being on the game or server main thread (offsets
28-53), and no sync. `saveChange` writes `isActivated()`
under `IsoObjectChange.WASHER_STATE` (offsets 0-16), and
vanilla's
`media/lua/shared/TimedActions/ISToggleClothingWasher.lua`,
`complete()`, is the exact pair:

```lua
	self.object:setActivated(not self.object:isActivated())
	self.object:sendObjectChange(IsoObjectChange.WASHER_STATE)
```

The combination machine also has `setModeWasher()` /
`setModeDryer()` / `isModeWasher()` / `isModeDryer()`, so
its mode is a second word a device would need. None of the
four is dangerous and all four are dull, which is the best
thing that can be said about an appliance.

**`IsoCompost` is a reading and nothing else.**
`getCompost()` answers 0 to 100 and `setCompost(float)`
clamps to the same (offsets 0-11); `getHealth()` /
`getMaxHealth()` are the bin's condition. `syncCompost()`
has a proper server branch
(`GameServer.sendCompost(this, null)`, offsets 13-24) and
`sync()` forwards to it. But a compost bin has no on and no
off, so there is nothing to write and the only honest device
is read-only -- which is a `sensor`-shaped thing with an
empty vocabulary, like `/dev/sensor0` and `/dev/fd0`.

**`IsoTrap` is never a device and that is already the
rule.** `SCeroSecSensors.lua` excludes trap heads *before*
the item is named, deliberately so the refusal cannot be
argued around, and the reason is written there: a security
system a survivor wires to five pipe bombs is a security
system that kills him. Nothing in this jar changes that, and
a trap has no state a machine wants except the one it must
not touch.

**`IsoJukebox` is not a device.** `SetPlaying(boolean)` sets
a private `isPlaying` and calls
`SoundManager.instance.PlaySound("paws1".."paws4")` on
whichever machine ran it (offsets 30-95). No sync, no
`save`, no `load`. On a dedicated server that call plays a
sound nobody hears and forgets it at the next reload.

**Alarms: there is no `IsoAlarmClock` and no alarmed
`IsoObject`.** The jar has
`zombie.inventory.types.AlarmClock` (an `InventoryItem`),
`AlarmClockClothing`, and `zombie.iso.Alarm` -- and
`zombie.iso.Alarm` is a sound emitter with `update()`,
`save`, `load` and nothing else public: no on, no off, no
state to read. `IsoObject` has no `alarmed` member of any
kind. The item is a different story and a real possibility:
`isAlarmSet()`, `setAlarmSet(boolean)`, `getHour()`,
`setHour(int)`, `getMinute()`, `setMinute(int)`,
`isRinging()`, `stopRinging()`, `getSoundRadius()` and a
`syncAlarmClock_World()` beside
`syncAlarmClock_Player(IsoPlayer)`. It would be found the
way the motion sensor is found -- on `getWorldObjects()`,
not `getObjects()` -- and it is the one thing in this note
that is an item pretending to be a fixture. Left UNCERTAIN:
nothing here proved which of the three sync calls a world
clock needs, and the 1993 question ("is a computer that sets
an alarm clock a computer or a hand?") has not been asked
yet.

## 7. Windows: the decision stands, the reason does not

**(The decision did not stand. This section's three reasons
are right and its verdict was overturned by the rung that
read it: each of the three is what a motor on a sash really
does, so all three became the device's rules. See the top of
this file, and docs/DEVICES.md.)**

Re-confirmed on 42.20.4, and the framing needs a correction.

**The `open` field of `IsoWindow` has exactly three
writers**, and `javap` names them:
`load(ByteBuffer, int, boolean)` (offset 20, from the save),
`ToggleWindow(IsoGameCharacter)` (offset 68) and
`syncIsoObjectReceive(ByteBufferReader)` (offset 5, from a
packet). There is no `ToggleWindowSilent`, no `setOpen`, and
no fourth road.

**But `ToggleWindow`'s body does not dereference the
character**, and that is the part the old proof stated too
strongly. Every use of the argument is guarded -- the
barricade test at offsets 37-49 is skipped when it is null,
the `IsoZombie` test at 93-97 is false for null, the
music-intensity call at 166-197 is behind `ifnull` -- and
the sync at offset 147 is unconditional: `sync(open? 1: 0)`,
which is the server broadcast. So `window:ToggleWindow(nil)`
would move a sash and tell the clients.

It is still not an actuator, for three reasons in the
bytecode rather than one:

- **It throws the catch.** Offsets 50-52, `locked = false`,
  unconditionally, before the toggle. A `win` device whose
  words are `lock` and `unlock` cannot have an `open` that
  silently unlocks; that is two gestures wearing one word.
- **It always trips the house alarm.** Offsets 86-116: when
  the sash ends up open, the sandbox check
  (`lore.triggerHouseAlarm`) is only consulted for an
  `IsoZombie`, so for a null character the branch falls
  straight into `handleAlarm()`. A machine that opened a
  window would call the dead to it every time.
- **It skips the barricade test**, because that test is the
  one thing it asks the character for. A boarded window
  would move behind its boards.

Add that nothing in `media/lua/` ever passes null -- the
only live caller is a test
(`client/Tests/TimedActionsTests.lua:470`, with a real
player), and vanilla's own timed action has it **commented
out** (`shared/TimedActions/ISOpenCloseWindow.lua:36`) in
favour of `character:openWindow(object)` /
`character:closeWindow(object)`, which are methods on a
character and take one by construction. So whether Kahlua
marshals a Lua `nil` into that parameter at all is unproven,
and there is no vanilla line to copy.

**Verdict unchanged: no window actuator.** A window's module
is the magnetic contact and the reading is the point of it.
What should change is the sentence in
[DEVICES.md](../DEVICES.md) and in `CeroSecModules.fitsOn`
-- "the only call that moves a sash wants a character
standing at it" is nearly true and not exactly true, and the
exact version is better: *the only call that moves a sash
also throws the catch, trips the alarm and skips the
barricade, and nothing in the game ever calls it without a
survivor.*

## The motor, from vanilla data alone

**Build 42 has no motor item.** A `grep -rni motor` over the
whole of `media/scripts` returns ten hits and every one of
them is a motorcycle helmet, a pair of motorcycle boots or
the Louisville Motor Shop step van. There is no `Motor`,
no `SmallMotor`, no `ElectricMotor`, and no `item` block
anywhere whose name contains the word.

**And there is no `Base.Electronics` either**, which
modules-proofs.md, 8 already records. The electronics family
in this build is exactly:

| item | where |
| --- | --- |
| `Base.ElectronicsScrap` | `generated/items/normal.txt:4529` |
| `Base.Amplifier` | `normal.txt:4496` |
| `Base.ElectricWire` | `normal.txt:4518` |
| `Base.MotionSensor` | `normal.txt:4539` |
| `Base.RadioReceiver` | `normal.txt:4550` |
| `Base.RadioTransmitter` | `normal.txt:4562` |
| `Base.Receiver` | `normal.txt:4574` |
| `Base.ElectronicsMag1`..`5` | `generated/items/literature.txt:5307`, `5322`, `5337`, `5352`, `5367` |

**What dismantles into electronics**, all four recipes, by
name:

- `DismantleElectronics` --
  `generated/recipes/recipes_electrical.txt:37-54`. Input
  `tags[base:camera;base:digital;base:miscelectronic;base:flashlight]`
  plus a kept screwdriver, output one
  `Base.ElectronicsScrap`,
  `timedAction = DismantleElectrical`,
  `xpAward = Electricity:2`.
- `DismantleMiscElectronics` --
  `recipes_electrical.txt:56-81`. Input one of
  `[Base.CDplayer;Base.HomeAlarm;Base.Remote;Base.Speaker]`,
  output `Base.ElectronicsScrap` **plus** a second item
  chosen by an `itemMapper`: `Base.Amplifier` from a
  speaker, `Base.ElectronicsScrap` from a CD player,
  `Base.MotionSensor` from a home alarm, `Base.Receiver`
  from a remote. This is the recipe the motion sensor
  already comes out of.
- `DismantleElectronicsDevice` --
  `generated/recipes/recipes_radio.txt:3-20`. Input one of
  sixteen named sets -- `TvAntique`, `TvWideScreen`,
  `TvBlack`, `RadioRed`, `RadioBlack`, the five walkies,
  `ManPackRadio`, `HamRadio1`, `HamRadio2` and the three
  makeshifts -- output one `Base.ElectronicsScrap`,
  `xpAward = Electricity:10`.
- `DismantlePowerBar` -- `recipes_electrical.txt:83-104`.
  Input `Base.PowerBar`, output `Base.ElectricWire`.

**Which vanilla items actually have a motor in them.** The
`base:miscelectronic` tag family is eleven items and it is
the door `DismantleElectronics` comes in by:

| item | where | has a motor? |
| --- | --- | --- |
| `Base.HairDryer` | `normal.txt:2787` | **yes**, a fan |
| `Base.SheepElectricShears` | `drainable.txt:246` | **yes**, clippers |
| `Base.CordlessPhone` | `normal.txt:4412` | no |
| `Base.Earbuds` | `normal.txt:4422` | no |
| `Base.Headphones` | `normal.txt:4432` | no |
| `Base.Pager` | `normal.txt:4452` | no |
| `Base.VideoGame` | `normal.txt:4485` | no |
| `Base.Microphone` | `normal.txt:4861` | no |
| `Base.HairIron` | `normal.txt:9053` | no |
| `Base.Calculator` | `normal.txt:9197` | no |
| `Base.Bullhorn` | `drainable.txt:2322` | no |

Two more outside that tag are obvious and are already named
in a dismantle recipe or carry a tag of their own:

- `Base.CDplayer` (`generated/items/radio.txt:280`), in
  `DismantleMiscElectronics` -- a spindle motor and a sled
  motor.
- `Base.BlowerFan` (`normal.txt:1924`), whose whole tag list
  is `base:blowerfan;base:hasmetal` and whose tag is used
  **nowhere else in `media/scripts`** -- a fan with nothing
  to do.

**The toys are a dead end, and it is worth writing down
why.** Build 42's toys are `DisplayCategory = Memento`
keepsakes with no electronics and no motor: `ToyBear`,
`ToyBear_Crafted_Cotton`, `ToyBear_Crafted_Burlap`,
`Bricktoys`, `ToyBadge`, `Doll`, `Plushabug`, `CatToy`,
`Rubberducky`, `Yoyo` (`normal.txt:9444`, `11472`,
`11516-11549`, `11580`, `11614`), and the two that carry
`base:hasmetal` -- `ToyCar` (`normal.txt:11624`) and
`ToyPlane` (`:11636`) -- are diecast and wind-up, 0.1
weight, with no `Electric` material and no electronics tag.
A recipe that got a motor out of a teddy bear would be this
mod inventing a Build 42 that does not exist. The hair
dryer, the shears, the CD player and the blower fan are the
four things in this game that really do have one, and they
are enough.

**Where a `CeroSec.SmallMotor` hooks in.** The mod already
has the answer to "where does a motor come from" for the one
module that needs one: `MakeCeroSecDoorOperator` takes
`item 1 [Base.EngineParts]`, with the comment that the game
already calls that a box of motor and gearing. A small motor
is not a duplicate of it and not a duplicate of
`Base.ElectronicsScrap` either -- `EngineParts` is a car
part and `ElectronicsScrap` is a board -- so the hook is:

- one `item SmallMotor` in
  `common/media/scripts/items_cerosec.txt`, shaped on
  `Base.MotionSensor` and `Base.Receiver`, which are the two
  vanilla part items nearest to it:
  `DisplayCategory = Electronics`, `ItemType = base:normal`,
  `Weight = 0.3`, a `MetalValue`, a `Tooltip` and a
  `WorldStaticModel` so it can be dropped and set down;
- one **dismantle** recipe beside the four make recipes,
  `timedAction = DismantleElectrical`,
  `Tags = InHandCraft;Electrical`, `category = Electrical`,
  `xpAward = Electricity:2`, a kept screwdriver with
  `flags[NoBrokenItems]`, and an input list of the four
  items that have one -- which is `DismantleElectronics`'s
  shape, verbatim, including its `mode:destroy` and its
  flags;
- and it is an **input** to whatever new module a later rung
  writes, beside `Base.EngineParts` on the door operator
  rather than instead of it. Nothing already on a player's
  shelf changes.

Two things to know before writing it. `Base.CDplayer` is
already an input to `DismantleMiscElectronics`, so a second
recipe on the same item is a second **choice** for the
player and not a conflict -- but it is a choice, and the two
outputs should be worth about the same or one of them is a
trap. And the recipe has to be `NeedToBeLearn` and named in
`CeroSec.WiringGuide`'s `LearnedRecipes` like the other
four, or a survivor with the book will find he can fit a
module he cannot make a part for.

## The shell: what a daemon costs

**A sleeping job spends neither budget nor cpu, and a
`while true; ... sleep 5; done` daemon may run for ever.**
Not by a rule but by two lines.

`CeroSecOS.jobStep` returns before it does anything at all
for a job whose clock has not come round
(`CeroSecOSVM.lua:3414-3430`):

```lua
	if job.state == "sleeping" then
		if now == nil or now >= (job.wakeMs or 0) then
			...
		else
			return "sleeping", 0
		end
	end
```

Zero steps, and -- this is the part that decides the
question -- the return is **above** `CeroSecOS.mountDev`, so
a sleeping machine does not even build `/dev`.

And the cpu clock is *reset*, not paused, every time the job
lies down (`CeroSecOSVM.lua:3546`):

```lua
	if job.state == "waiting" or job.state == "sleeping" then job.cpuSince = nil end
```

`CeroSecOS.jobOverCpu(job, nowMs, limitS)` answers false the
moment `job.cpuSince` is nil, and the five-minute ceiling
(`CeroSec.JOB_CPU_LIMIT_S`, 300) is
`nowMs - job.cpuSince > limitS * 1000`. So the ceiling
measures *one unbroken run on the processor* and a loop that
sleeps starts from zero every five seconds. It can never
reach it. SCRIPTING.md already says this in the player's
words and the code is where it comes from:

> A sleeping job is off the processor entirely -- it is not spending
> its five minutes and it can wait for days

The same loop **without** the `sleep` is the one thing not
to write, and that one dies at 300 s with
`killed: cpu limit`.

**What a five-second poll costs, per machine, in steps.**
The canonical loop from SCRIPTING.md:

```sh
while [ "$(cat /dev/door0)" = closed ]; do
    sleep 5
done
```

is, per turn of it:

| piece | steps |
| --- | --- |
| the wake | 0 |
| `cat` in `$(...)`, a command out of `/bin` | `CeroSecOS.STEP_COST_COMMAND` = 32, plus one per PATH directory past the first |
| `[ ... = closed ]`, a builtin | 1 |
| `sleep 5`, a builtin | 1 |
| the loop frame, the word expansion | free, and bounded by the program |

about **34 steps every five seconds**, which is under 7 a
second. Against it: `CeroSec.STEP_BUDGET_PER_MACHINE` is 100
steps a pass and `CeroSec.JOB_PASS_MS` is 100, so one
machine is offered up to 1000 steps a second and the poll
takes 0.7 % of them. The pass the wake lands in spends 34 of
its 100 and the four and a half seconds either side spend
nothing.

**The cost that is not in steps, and is the real one.**
Every pass that actually runs calls `CeroSecOS.mountDev`,
which calls `env.devices.list()`, which is
`SCeroSecDevices.find(x, y, z)` -- and that is a walk of
every room of the building the machine stands in, or a 21x21
box when it stands in none. A five-second poll makes that
walk **twelve times a game minute** for that machine, where
the standing sweep (`CeroSecDevices.refresh`) makes it once.

**AND IT IS WORSE THAN TWELVE A MINUTE, corrected by the
motor rung.** The walk does not happen in `mountDev`.
`CeroSecDevices.envFor` does it, `SCeroSecSystem:execEnv`
calls that, and `CeroSecJobs.runMachine` calls THAT once a
pass -- before it looks at a single job, so the
`return "sleeping", 0` quoted above never gets the chance to
save it. A machine with any job at all in its book gets a
pass every `CeroSec.JOB_PASS_MS`, which is ten a second, so
the loop above cost fifty building walks per turn of it.

That walk is Java-side -- `getRooms()`, `getIsoRoom()`,
`getSquares()`, `getObjects()`, an `instanceof` per object
-- so `tests/hostile_test.lua` cannot measure it and does
not: the county numbers it prints are the scheduler's, and
the sensor number in DEVICES.md is the sampling book's. **So
the honest figure for what a five-second poll costs the
server is: 34 steps, which is nothing, plus one building
walk per five seconds per polling machine, which has never
been measured on Kahlua.** (Corrected by the motor rung:
fifty walks per five seconds, and measured -- see the note at
the top of this file.) A mall is one `BuildingDef` and
its several hundred rooms are one walk. That number is the
first thing the next rung should put on the glass, and it is
the argument for giving `/dev` a short-lived cache, or an
event, before a room full of machines is told to poll.

## Proposed devices for the next rung

Cut to what is proven above, in the shape `/dev` already has
(`CeroSecOS.DEV_VALUES`, `DEV_MODES`, `DEV_OPPOSITE`).
Nothing here is decided; this is the list the proofs
support.

| node | on | states | values | opposite | mode |
| --- | --- | --- | --- | --- | --- |
| `curtain0` | `IsoCurtain`, or an `IsoDoor` with `hasCurtain` | `open`, `closed`, `barricaded` | `open`, `close` | `open`<->`close` | 660 |
| `stove0` | `IsoStove` (oven, microwave, coffee machine) | `on`, `off`, `broken`, `no power` | `on`, `off` | `on`<->`off` | 660 |
| `gen0` | `IsoGenerator` | `on`, `off`, `no fuel`, `broken`, `not connected` | `on`, `off`, or nothing at all | `on`<->`off` | 660, or 440 |
| `wash0` | washer, dryer, combination, stacked | `on`, `off` | `on`, `off` | `on`<->`off` | 660 |
| `fire0` | `IsoBarbecue`, `IsoFireplace` | `lit`, `out`, `smouldering`, `no fuel` | **empty**, unless lighting fires is decided | none | 440 |
| `compost0` | `IsoCompost` | a percentage | **empty** | none | 440 |
| `tv0` | `IsoTelevision` | `on`, `off`, `no power`, and the channel | `on`, `off` **only with a sync of our own** | `on`<->`off` | 440 today, 660 the day the sync is written |

- `radio0` stays what it is: read-only, empty vocabulary,
  the knob is the survivor's.
- `win0` stays read-only, for the three reasons in section 7
  and not for the one it used to give.
- No `lamp0`: a lamp is a `light` and the relay already fits
  it.
- No `jukebox0`, no `trap0`, no `alarm0`.
- Each of these wants a **module** to exist at all, the way
  every fixture does. A curtain operator is the obvious one
  and a small motor is what it would be built from; the
  appliances want a contactor, which is a relay by another
  name and might be the relay itself. That is the next
  rung's design and this note deliberately does not pick it.
- Every one of them is discovered by the walk that already
  exists: all seven classes are on `square:getObjects()`,
  including `IsoCurtain` (`AddSpecialObject` adds to both
  lists). Nothing here needs a second scan, which is the one
  thing the motion sensor did need.

## What is not proven

Written down so that nobody reads a silence as a yes.

- **The TV's write path.** Reading is proven; writing is
  proven *not* to sync, and the mod's own sync for it is
  designed nowhere and measured nowhere.
- **The cost of a building walk on Kahlua.** Named above. It
  is the number that decides whether a five-second poll is
  cheap or is the most expensive thing this mod does.
- **`IsoCurtain` on a player-built frame.**
  `IsoThumpable.HasCurtains()` answers an `IsoCurtain` and
  the toggle is the same call, but no line of this note was
  checked against a built window with a sheet on it. The
  modData question is settled either way (`IsoThumpable`
  keeps and saves its own table, modules-proofs.md, 1); the
  fetch is not.
- **A garage door in leaves.** Whether calling
  `ToggleDoorSilent` on each leaf is a door or a shudder.
  Needs a screen.
- **The alarm clock.** Which of `syncAlarmClock()`,
  `syncAlarmClock_World()` and
  `syncAlarmClock_Player(IsoPlayer)` a clock on the ground
  needs, and whether it belongs in a mod about premises at
  all.
- **`IsoStackedWasherDryer` in the world.** No tile in any
  of the game's five `.tiles.txt` files carries that
  `IsoType`, so where one comes from was not established.
- **Kahlua and a null Java argument.** Section 7 rests
  partly on what `window:ToggleWindow(nil)` would marshal
  to, and no vanilla Lua passes null to that parameter. It
  does not matter for the verdict, which the three side
  effects settle on their own, and it would matter to
  anybody who tried to argue the verdict away.

  **PROVEN, and somebody did argue the verdict away.**
  `LuaJavaInvoker.prepareCall` pulls each argument off the
  frame (offsets 295-304) and converts anything the parameter
  type is not already an instance of (325-347) -- which a
  null never is, `Class.isInstance` answering false for it.
  `convert(Object, Class)` answers null for a null before the
  converter manager is asked anything:

  ```
  private java.lang.Object convert(java.lang.Object, java.lang.Class<?>);
     0: aload_1
     1: ifnonnull     6
     4: aconst_null
     5: areturn
  ```

  And the type check at 349-392 is
  `if (arg != null && converted == null) fail(...)` -- the
  failure is GUARDED ON `arg != null` -- so a null argument
  goes straight into the parameter array at 393-405. The
  argument COUNT is not exempt (126-137 refuse a short call),
  so the nil has to be written and cannot be left out.

  **And the preamble is inert too**, which the rung's verifier
  asked for and which this note never named: `ToggleWindow`'s
  first eleven instructions are
  `Type.tryCastTo(arg, IsoPlayer.class)`, `checkcast IsoPlayer`,
  `astore_2` -- before `DirtySlice()` and before any of the
  returns. `Type.tryCastTo` is three tests long and answers
  null for a null at its first branch
  (`arg1.isInstance(arg0)` is false for null, so offsets 14-15
  `aconst_null; areturn`), a `checkcast` on null succeeds by
  the JVM spec, and the local it is stored in is read nowhere
  but behind the ifnull guards this note already counted. So
  the cast at the top of the method is not a fourth thing a
  null argument has to survive.

  And the vanilla call site this note looked for and did not
  find is there for a different method:
  `media/lua/shared/TimedActions/ISLockDoor.lua:56`, `:62`
  and `:69` are `door:syncIsoObject(false, 0, nil, nil)` --
  `IsoObject.syncIsoObject(boolean, byte, UdpConnection,
  ByteBufferReader)`, two Java OBJECT parameters handed a Lua
  nil -- and this mod has made that call on every door write
  since rung 1.

  **Two silent returns this note did not name**, both above
  the ones it did, and both refused by the device for the
  barricaded door's reason -- a `return` that does nothing is
  an order swallowed: `permaLocked` at offsets 21-28
  (`window0: sealed`) and `destroyed` at 29-36.
  `isSmashed()` and `isDestroyed()` read the SAME field #393,
  three instructions each, so `smashed` covers the second and
  there is no fourth word.
