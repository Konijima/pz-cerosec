# CeroSec — Devices

How `/dev` gets built every command from what a computer can actually reach:
discovery, the lock rule, sync calls proven against the shipped jar, motion
sensors, and the floppy drive's own second filesystem.

See also: [PLAYERS.md](PLAYERS.md) for the `dev` command and the device tables a
player sees, [PROTOCOL.md](PROTOCOL.md) for how `dev find` highlights one on a
single window, [ARCHITECTURE.md](ARCHITECTURE.md) for the engine `/dev` is mounted
into.

## /dev, and the world outside the machine

The engine knows nothing about Project Zomboid, devices included. A device node
lives under `/dev` and is not a file:

```lua
{ type = "dev", owner = "root", group = "sudo", mode = 660,
  id = "light0", kind = "light", desc = "office", side = "N",
  state = "on" }
```

It has no `data`, it costs nothing in `CeroSecOS.usage` (so `df` does not move
because somebody walked past a light switch), and **it is never persisted**.
`CeroSecOS.mountDev` builds `/dev`'s children from `env.devices.list()` at the
top of `exec` and `continue`, and `CeroSecOS.unmountDev` takes them away again
before the answer goes back — so the state the game saves has the same empty
`/dev` it has had since rung 1, and `validate` never sees a node type it does not
know. `SCeroSecObject:osState` sweeps once more before the gate, as the belt to
that pair of braces: a command that died in the middle must not turn a working
machine into a broken one.

`env.devices`, when the caller supplies one, is these functions:

| call | answers | who owns it |
| --- | --- | --- |
| `list()` | array of `{ id, kind, desc, side, state, mode, dead, ro }` | the caller |
| `write(id, value)` | `ok, reason, state` | the caller |
| `chmod(id, mode)` | — | the caller, optional |
| `find(id, seconds)` | `ok, reason, word` | the caller, optional |

The **ids are the caller's**, not the engine's: the engine renders what it is
handed and judges `value` against `CeroSecOS.DEV_VALUES[kind]`, so a word a kind
has no meaning for never reaches the world. An entry marked `dead` is mounted but
never listed, which is what makes `cat /dev/lock0` say `no such device` instead of
`no such file`. `chmod` is how a mode outlives the command it was typed in, since
the node itself is gone by the end of one.

Device I/O refusals read `<id>: <reason>`; filesystem refusals *about* a device
node keep the filesystem's grammar (`rm: /dev/light0: is a device`,
`mkdir` and `touch` under `/dev` answer `/dev: read-only`). The listing is
alphabetical, like every other listing on this machine.

**Discovery** is `SCeroSecDevices.find(x, y, z)`, run afresh at every command,
because the answer is only true for the moment it is asked:

- The square's `getBuilding()`, when it has one → `getDef():getRooms()`
  (an `ArrayList<RoomDef>`, read the way `shared/Util/BuildingHelper.lua` reads
  it) → `getIsoRoom()` per room — `nil` while its chunks are not loaded — →
  `getSquares()` → `getObjects()`.
- No building → `getCell():getGridSquare()` over ±`CeroSecDevices.RADIUS` (10) on
  the same z. A `nil` square is an unloaded chunk and is skipped.

Before either: the machine's **own** square. No square there is a chunk the streamer
has not brought in, and a machine that is not in the world reaches nothing — `find`
answers an empty list at once rather than walking four hundred tiles that cannot be
there, which is the same guard `CeroSecRadio.tncAt` wears one layer down. So a computer
you have walked away from lists no devices and answers `no such device` about the
numbers in its own book, and its sensors fall out of the sampling book on the usual two
scans of grace. It is not switched off for it and it keeps running: the rule is
[ARCHITECTURE.md](ARCHITECTURE.md#the-chunk-that-goes-away).

Classification is `instanceof`, and it answers a **list**, because one object can
be two devices: `IsoLightSwitch` → `light`, `IsoWindow` → `win`, `IsoDoor` →
`door` *and* `lock` when the lock bites, `IsoThumpable` with `isDoor()` → `door`
and `lock` (`built`). A player-built window frame is not a device this rung.

And it answers **nothing at all** for a fixture nobody has wired, which is the
hardware-module gate below.

## The hardware modules

`SandboxVars.CeroSec.HardwareRequired`, declared in
`42/media/sandbox-options.txt` and **true by default**: a fixture is only a
device when a module is installed on it. Read through
`CeroSecModules.required()`, which **fails closed** — anything that is not the
literal `false`, a group nobody declared included, means the hardware is
required. A sandbox file that failed to load is then a world with an empty
`/dev`, which a player sees at once; the other way round is a world that quietly
went back to magic and looks exactly like a working one.

| module | item | fits | gives | skill |
| --- | --- | --- | --- | --- |
| `contact` | `CeroSec.MagneticContact` | door, window | that `door`/`win`, **read-only** | 1 |
| `relay` | `CeroSec.Relay` | light switch | `light` | 1 |
| `strike` | `CeroSec.ElectricStrike` | a door `doorLocks` says yes to | `lock` | 2 |
| `operator` | `CeroSec.DoorOperator` | door, not a garage or double leaf | `door`, read-write | 3 |

The table, the levels, the fit rules and the modData read/write are
`shared/CeroSec/CeroSecModules.lua` — **shared**, because the right-click menu
asks the same questions the discovery does and a client cannot load a server
file. `roomName`, `doorLocks` and `isManyDoors` moved there from
`SCeroSecDevices.lua` for that reason and are forwarded back under their old
names, so every call site there reads as it did.

**Where a module lives:** the object's own modData, under the mod's name —
`object:getModData().cerosec = { strike = true, contact = true }` — written
server-side and broadcast with `transmitModData()`, whose server branch is
`GameServer.sendObjectModData` and which calls `flagForHotSave()` on the way out.
`IsoObject` saves modData with the chunk under flag bit `0x4`, and `IsoThumpable`
keeps and saves a modData field of its **own**; both are quoted at the bytecode in
[notes/modules-proofs.md](notes/modules-proofs.md). The last module off takes the
table with it, because `IsoObject.save` only skips a modData table that is empty
altogether.

**Read-only without a kind.** A door with a contact and no operator is a `door`
like any other — same vocabulary — with nothing behind it to carry a write out.
That travels as `ro` on the entry, and it means two things: the node is born
`CeroSecOS.DEV_MODE_RO` (440), so everybody but root is refused by the mode; and
`CeroSecOS.devWrite` refuses `ro` **before the vocabulary**, because what word was
typed cannot matter to a device that can carry none of them out. The text is
`operation not supported` — `write(2)`'s `EOPNOTSUPP`, in the lower case every
other reason here is written in. `SCeroSecDevices.act` keeps the same refusal as a
belt for a caller that reaches the world layer directly.

A **window is always `ro`** when the option is on: the only call in the game that
moves a sash is `IsoWindow.ToggleWindow(IsoGameCharacter)`, which wants a
character, so there is no window actuator to build. With the option off the `win`
device locks and unlocks exactly as it always did. What a contact on a window
buys is the reading, and that is the point of a magnetic contact: it senses the
sash.

**Hardware changing under a live device** moves its mode and never its number:
the key a number hangs on is `kind:x:y:z:side:n` and neither the kind nor the
place moved. `CeroSecDevices.number` compares the record's `ro` with the entry's
as booleans — so a devmap written before this rung is not a change — and on a
real change puts the mode back to what a device of that shape is born at. A
`chmod` does not survive the hardware, deliberately: the alternative is a door
with an operator on it that nobody may write to.

**Install and uninstall** are `installmodule` and `uninstallmodule` in
`SCeroSecSystem.lua`, naming the fixture by its square plus its index in that
square's object list — the shape vanilla's own client commands use
(`ISWorldObjectContextMenu.lua:3076`). The server looks the object up itself and
re-asks the fit, the level, the module and the screwdriver, plus the one thing the
menu cannot ask: whether the player is standing there. The item leaves the bag
before the module goes on and is back in it before the module comes off, which is
the floppy drive's rule about duplication. The client half is
`CeroSecModuleMenu.lua` (a listener of its own on
`Events.OnFillWorldObjectContextMenu`, absent altogether when the option is off)
and `ISCeroSecModuleAction.lua` (vanilla's `ISFixGenerator` shape: the Loot
animation, `150 - perk * 3`-style duration, `addXp` at the end).

**`dev` and `ls -l` say nothing about which module gave a device**, and that is
deliberate: both listings are full-width already — `ls -l /dev` puts the widest
state on column 60 — and a survivor who wants to know goes and looks at the door.
What the listing does show is the consequence: `cr--r-----` on a door is a door
with a contact and no operator.

A **motion sensor** is not on that list at all, because a dropped item is not on
`getObjects()`: `scanWorldItems` walks `getWorldObjects()` beside it
(`ArrayList<IsoWorldInventoryObject>`, the list vanilla's own
`ISBuildUtil.lua:315` and `ISWorldObjectContextMenu.lua:2957` read) and asks each
item what it is. See **Motion sensors, underneath** below.

**Where a lock bites**, which is the rule that decides whether a door gets a
`lock` row at all:

- `IsoDoor` → yes when `isExterior()` is true, **or** when the door's two sides
  have a room on exactly one of them. `IsoDoor.couldBeOpen(chr)` reads, in order:
  animal → false, `isBarricaded()` → false, then `canBeOpenFromInside(chr)`
  → **true and returns**, before the `isLockedByKey` / `haveThisKeyId` branch is
  ever reached. `canBeOpenFromInside` is: `chr` is an `IsoPlayer`, `isOutside()`
  is false, `chr`'s room is the door's square's room or its opposite square's
  room, and the door has no `forceLocked` property. So from inside a building a
  locked map door always opens, and a lock on an interior door was a device that
  lied.
- `IsoThumpable` with `isDoor()` → always, unchanged. Its gate is different:
  `ToggleDoorActual` and `couldBeOpen` both test `isLockedByKey()` against
  `chr:getCurrentSquare():has(IsoFlagType.exterior)` — the square the survivor
  stands on, not which side of a building it is — and a base door is reachable
  from an exterior square by construction.
- **A padlock does not hold a door.** Neither `IsoThumpable.ToggleDoorActual` nor
  its `couldBeOpen` reads `lockedByPadlock` at all; the only reader is
  `isLockedToCharacter`, whose callers are the container ones
  (`server/ISObjectClickHandler.lua:283`, `client/ISUI/ISInventoryPage.lua`) plus
  the pick-up refusal in `shared/Moveables/ISMoveableSpriteProps.lua:1222`. So
  `padlock` is a `lock` state and never a `door` one, and a padlocked base door
  still opens from the computer — exactly as it does for a survivor clicking it.

**Which doors are not `door` devices.** A leaf of a double or a garage door:
`IsoDoor.getDoubleDoorIndex(object) ~= -1` or
`IsoDoor.getGarageDoorIndex(object) ~= -1`, both public statics and both vanilla
Lua's own way of asking (`server/BuildingObjects/ISBuildUtil.lua:556`,
`ISDoubleDoor.lua:315`). `ToggleDoorSilent` moves the one object it is called on
while vanilla's own toggle walks every leaf through `forEachDoorObject`, so a
machine that opened one would leave the rest shut. Those keep their `lock`.

**A window's states** are `smashed`, `barricaded`, `open`, `locked` and
`unlocked`, read in that order — the glass, then the sash
(`IsoWindow.IsOpen()`), then the catch. `open` comes ahead of the latch for the
reason a door's does, and `unlocked` therefore means shut; a smashed or boarded
window has no sash worth reporting, so those two still come first. `open` has no
opposite in `DEV_OPPOSITE.win` (the kind's words are `lock` and `unlock`), so
`dev win0 toggle` on an open window answers `win0: cannot toggle` rather than
guessing a direction for a sash no machine can move.

**A door's states** are `open`, `closed` and `locked`, and `locked` implies
closed — three words, not four, because a survivor who reads `locked` has been
told both things. Its values are `open` and `close`. Its refusals are
`doorN: locked` (the computer is not a key; `unlock` the lock beside it first),
`doorN: barricaded`, `doorN: blocked` and `doorN: no such device`.

**The numbering** is stable for the life of the machine. Candidates are sorted by
`(kind, x, y, z, side)` and each gets the smallest number its kind has never used;
the answer is written into the machine's own state at `os.devmap`, keyed by where
the device is:

```lua
state.devmap["light:1024:998:0::0"] = { id = "light0", kind = "light", n = 0, mode = 660 }
```

A new kind's starting mode is `CeroSecOS.DEV_MODES[kind]` through
`CeroSecOS.devModeFor(kind, ro)`, which is `CeroSecOS.DEV_MODE` (660) for
everything except `sensor` (440) — and `CeroSecOS.DEV_MODE_RO` (440) for any
entry marked `ro`, whatever its kind, which is the hardware-module gate above. It is only where a mode *starts*: a `chmod` moves it and the book
above is what makes that outlive the command.

The trailing `0` is an ordinal that tells two devices of one kind facing the same
way on one square apart — the object index would have done it and is not stable
across a reload. An entry is **never removed**: the number is spent, so a device
that is torn out leaves a gap and nothing is renumbered under a script. The book
is capped at `CeroSecDevices.MAP_MAX` (128) so a computer carried across the map
does not grow one entry per light switch in the county.

**The sync calls**, and why these ones. Every one is verified with `javap` against
`projectzomboid.jar` (42.20.4). The point that matters is *who broadcasts*: our
writes happen on the server and most of vanilla's happen on a client, so a setter
that syncs for a player does not necessarily sync for us.

| kind | setter | sync | why |
| --- | --- | --- | --- |
| `light` | `IsoLightSwitch:setActive(on)` | none needed | `setActive(Z)` → `setActive(Z,Z,Z)`, which ends on `syncIsoObject(false, activated, null)`; that method's server branch walks `GameServer.udpEngine.connections` |
| `lock` (map) | `IsoDoor:setLockedByKey(locked)` | `syncIsoObject(false, 0, nil, nil)` | `setLockedByKey(Z,Z)` **skips** its own sync when `GameServer.server` is true; the pair is vanilla's own, `shared/TimedActions/ISLockDoor.lua:52-56` |
| `win` | `IsoWindow:setIsLocked(locked)` | `syncIsoObject(false, 0, nil, nil)` | `setIsLocked` is a bare field write with no sync at all; `IsoWindow:syncIsoObjectSend` writes `locked` into the packet |
| `lock` (built, padlock) | `IsoThumpable:setLockedByPadlock(locked)` | none needed | it calls `syncIsoThumpable()` itself, whose server branch is `INetworkPacket.sendToRelative(SyncThumpable, ...)` |
| `lock` (built, key) | `IsoThumpable:setLockedByKey(locked)` | `syncIsoThumpable()` | same server skip as the map door's |
| `door` (both classes) | `ToggleDoorSilent()` | `syncIsoObject(false, 0, nil, nil)` | Silent needs no character, plays no sound and moves one object; it is what vanilla's own scripts call (`client/Tutorial/Steps.lua:1288`, `:1795`, `Tutorial1.lua:331`). Its bytecode is `isBarricaded → return`, path/LOS/light invalidation, `setOpen(!isOpen())`, sprite swap — **and no sync of any kind**. `syncIsoObject` and *not* `syncIsoThumpable` even for a player door: `SyncThumpablePacket` writes `lockedByCode`, `lockedByPadlock` and `keyId` and nothing else, while both classes' `syncIsoObjectSend` writes the open flag (`IsoDoor`: `isOpen()`; `IsoThumpable`: the `open` field) |

Because `ToggleDoorSilent` **toggles**, a door already in the state it was asked
for is left alone and nothing is broadcast: two `dev door0 open` in a row are one
open door. And because it returns doing nothing on a barricaded door, the
`barricaded` refusal is ours and comes *before* the call — otherwise the order
would be swallowed and the machine would report the state it already had.

`doorN: blocked` is the game's own test and nothing of ours: `isObstructed()` →
the static `IsoDoor.isDoorObstructed(IsoObject)`, true when the door's square
`isSolid()` or `isSolidTrans()`, has an `IsoObjectType.tree`, or a vehicle in the
chunk `isIntersectingSquareWithShadow` of it. It is exactly the test
`couldBeOpen` makes at offset 108 before it will let a survivor through, so a door
the machine refuses is a door nobody could open by hand either.

A survivor **standing** in the doorway is not one of these. Vanilla lets a door
swing through him — `ISOpenCloseDoor:complete` calls `ToggleDoor` and checks
nothing first — so the machine does too. A refusal the game does not make is a
refusal we would have invented.

**Migration.** A `devmap` entry made for an interior map door's `lock` device
before this rung is keyed `lock:x:y:z:side:n` and nothing classifies to that key
any more. It therefore behaves exactly as a device torn out of the world does:
the number stays spent for the life of the machine, the entry stays mounted so
`cat /dev/lock4` answers `lock4: no such device` rather than `no such file`, and
it is **not listed**. Nothing is renumbered and no gap is ever reused.

The power rule for a light is the switch's own: `canSwitchLight()` — a bulb, and
electricity or a charged battery. A switch with no bulb reads as `no power` too,
which is what a survivor flicking it would find. `setActive` also *answers* with
the state it settled on, so the state is read back rather than assumed; the same
goes for every kind, because "the order went out" and "the world moved" are not
the same fact.

The one-minute sweep (`CeroSecDevices.refresh`) renumbers for a machine somebody
is standing at. Nothing already on the glass changes — a printed line stays
printed, here as on any terminal — but a device that appeared since already has
its number by the time `ls /dev` is typed.

**Motion sensors, underneath** (`SCeroSecSensors.lua`). Nothing of ours goes into
the world: the device *is* the item lying on the floor.

- **Which item.** Exactly one: `Base.MotionSensor`
  (`media/scripts/generated/items/normal.txt:4539-4548`), an Electronics-category
  module with a `WorldStaticModel` so it can be dropped and set down. It is named
  in one place, `CeroSecSensors.ITEM`, because the module carries no field that
  tells it apart from a fuse — a component has no `SensorRange`. The path is
  `getWorldObjects()` → `IsoWorldInventoryObject:getItem()` →
  `InventoryItem:getFullType()`, all `javap`'d. It is a findable part, not a boss
  drop: it is in the loot tables (`server/Items/ProceduralDistributions.lua:20424`,
  `:20535`, `:43661`; `Distributions.lua:20956`) and a screwdriver on a `HomeAlarm`
  yields one (`recipes/recipes_electrical.txt:60-81`, `DismantleMiscElectronics`).
- **Its reach is `CeroSec.SENSOR_RANGE` (3), and that number is the game's.** One
  `Base.MotionSensor` plus two `ElectronicsScrap` is what the game itself calls a
  V1 sensor (`recipes/recipes_traps.txt:153-181`), and every V1 in the game is
  `SensorRange = 3` — all five of them, without exception
  (`items/weapon.txt:306, 487, 662, 838, 1027`). The extra scrap is what buys a V2
  or a V3, so three is the reach the module brings by itself and the smallest the
  game ever grants a motion sensor.
- **Trap heads are never devices**, and they are excluded *before* the item is
  named so the refusal cannot be argued around — not by a vanilla trap, not by a
  modded one, and not by one somebody named `Base.MotionSensor`. The test is the
  game's own field and not a list of the fifteen names:
  `instanceof(item, "HandWeapon") and item:getSensorRange() > 0`. `sensorRange`
  lives on `HandWeapon` and on no other `InventoryItem`, and is copied there from
  the script by `zombie.scripting.objects.Item.InstanceItem(String, boolean)`
  (bytecode offsets 2016–2019), so a positive one means a weapon that senses —
  which is a mine. The fifteen are
  `{PipeBomb,Aerosolbomb,NoiseTrap,SmokeBomb,FlameTrap}SensorV{1,2,3}` (V1 = 3,
  V2 = 4, V3 = 5 or 6). *Why:* the whole point of one is that it goes off when a
  body comes near, and a security system a survivor wires to five pipe bombs is a
  security system that kills him.
- **Dropped and placed are two different objects**, which is the difference the
  exclusion is about. A dropped item is an inert `IsoWorldInventoryObject` on
  `getWorldObjects()`; a **placed** trap is an armed `IsoTrap` on `getObjects()`,
  made through `server/Traps/BuildingObjects/TrapBO.lua` and
  `IsoTrap.new(item, cell, square)`. So a dropped pipe bomb is not live — and it is
  one right-click from being, which is exactly why the machine will not call it a
  sensor.
- **The field of view and the cadence are `IsoTrap.updateVictimsInSensorRange`'s**,
  arithmetic included: `SENSOR_TIMER` is `new OnceEvery(1.0f)` so the sample is
  once a second; `mo:getZi() == square:getZ()` so one floor only;
  `DistanceToSquared(mo:getX(), mo:getY(), getX() + 0.5, getY() + 0.5) <= range *
  range` — **squared euclidean from the centre of the head's own tile**, not a
  Chebyshev box, so a body two tiles east and three south of a head is 3.6 tiles
  away and is not seen where a tile count would have said 3 and fired; and an
  `IsoGameCharacter` that `isInvisible()` is skipped while a
  `BaseVehicle`, which extends `IsoMovingObject` and is not a character, is not.
  A car is warm.
- **The one test not mirrored** is `LosUtil.lineClear`. No vanilla Lua touches
  `LosUtil` anywhere, so whether its nested `TestResults` enum is reachable from
  Lua at all is unproven, and a LOS trace per body per second per sensor is the
  dearest thing this file could do. The **room** stands in its place — the game's
  own partition of the inside of a building by its walls — so the field is
  `room:getSquares()` intersected with the range box, and a head with no room
  under it gets the range alone. That is the honest statement and it is the one
  the manual prints: *in a room, the part of that room within range; outside one,
  the range.*
- **What movement is, and this half is ours.** The game's trap is a proximity fuse
  that fires on a body standing still; a PIR is not. A sample is a **signature** —
  every body in the field, quantized to `CeroSecSensors.STEP` (10, tenths of a
  tile), sorted, joined — and a signature differing from the one before it closes
  the contact for `CeroSec.SENSOR_HOLD_S` (5) seconds. One comparison covers
  moved, entered *and* left, with no identity followed, because a PIR has no
  identities either. The first sample of a newly discovered head sets the baseline
  and fires nothing: a one-second warm-up, which every PIR ever fitted has had.
- **Whose state it is.** The sensor's, keyed by where the head is plus its ordinal
  on that tile — one head, one contact, however many machines watch it, and it is
  sampled once however many are watching. Never saved: a contact is five seconds
  long and a reload is the end of it.
- **When it runs.** `CeroSecSensors.tick` is one `Events.OnTick` handler with two
  gates on `getTimestampMs`: `SCAN_MS` (60000) walks every machine that is **on**
  and registers the sensors it can reach, and `SAMPLE_MS` (1000) samples the book.
  A machine that is off is not walked, so no machine on means no pass and no cost.
  A command typed at the glass registers too (`build`), so a head dropped ten
  seconds ago is warm before the next `cat` rather than at the top of the minute.
  A head no live machine has asked about for two scans is forgotten. Ceilings:
  `FIELD_MAX` (49, the 7×7 box of a reach of three — a ceiling, so a reach somebody
  widens cannot make a pass cost four thousand squares without this moving too) and
  `SENSOR_MAX` (100).
- **What it costs.** `hostile_test` section 20 drives the worst county there is —
  six machines, eight heads each, forty squares a field, nine hundred and sixty
  bodies, every one of them moving every second, each body on one of the twenty
  squares nearest its head so that every one of them counts — for a thousand
  seconds: **1920 squares and about 5 ms per second**, flat, with every contact
  closed. Half a
  percent of one second. An empty county costs under a hundredth of a
  millisecond, because the pass over an empty book does nothing at all.


## The floppy drive, and the second filesystem

The disk is an **item**, and what is written on it lives in the item's modData and
not in the computer: `{ v = 1, fs = <directory node>, label = "WORK" }`, the same
shape `state.floppy` has while the disk is in the drive, because it *is*
`state.floppy` while the disk is in the drive. Three pieces, and they are
deliberately three (`CeroSecOSDisk.lua`):

- **The disk.** `state.floppy`, or nothing at all when the slot is empty. A missing
  `fs` is an unformatted disk, which is what a new one out of a box is.
- **The device.** `/dev/fd0` is mounted on `/dev` for the length of one command,
  exactly as a light switch is, and only while there is a disk in the slot — so a
  saved machine never carries one. Its kind has an **empty** vocabulary, like a
  motion sensor's: there is no word to write to a raw disk, and every one tried is
  `fd0: invalid value`. Its `660` is still read twice over — `newfs` wants `w`,
  `mount` wants `r` — so the mode on that node is the whole of who may format and
  who may mount, and there is no second list of names anywhere. A `chmod` on it is
  the **drive's** and outlives the disk (`state.fdmode`).
- **The mount.** `state.mounts` is what `mount` with no arguments prints and what
  `CeroSecOS.getNode` crosses: a directory that is a mount point resolves to the
  root of the mounted disk and not to the directory on the hard drive underneath
  it. The crossing is done in `getNode` and nowhere else — the same place a
  symbolic link is followed, and for the same reason: not one command in the engine
  had to learn there is a floppy. A mount does not survive the power going off,
  which is what a reboot does anywhere; the disk stays in the slot, because that is
  a thing in the world.

The two filesystems never share a ceiling, and that falls out of the **shape**
rather than out of a rule: the disk lives beside `state.fs` and not inside it, so
the quota walk (`CeroSecOS.usage`) physically cannot see it. What picks the ceiling
for a write is the path — `CeroSecOS.fsFor` answers which filesystem an absolute
path is on, and `checkAttach` and `setData` ask it — which is why a full floppy is a
`df` that has not moved on `hda`.

Across the boundary, a disk is **copied** and never handed over
(`CeroSecOS.diskFromData` / `diskToData`). An item's modData is a `KahluaTable` the
game owns, and the engine's own gate runs on whatever goes into the machine's state
on every command from then on — so what goes in has to be a plain Lua table this
engine made. `CeroSecOS.validateDisk` runs at the **slot**, so a forged or damaged
disk is refused there rather than three commands later by a gate that then calls the
whole machine broken. An item always *has* a modData table, so nothing written in it
means a blank disk and not a refusal.

That gate is asked two questions. The **boot gate** asks the *shape* — whether the
core can run on the disk at all — and deliberately not the ceilings, for the reason
the machine's own drive is not asked either: being over a quota is a state a
filesystem can be *in*, and the answer is that the next write says `disk full` until
room is made. A boot gate that refused would cost the player his whole computer for
a disk he could have fixed with one `rm`, because `osState`'s refusal is sticky and
the firmware repair deliberately does not reach into the drive. The **slot** asks the
ceilings as well, because what arrives there is a table off a save file — or, on a
server, off a client — and it is walked on every command from then on: a 4 KB disk
costs the boot gate nothing, and a forged 8 MB one is that same walk on every
keystroke.

Which leaves the obvious trap — a machine that runs on a disk must be able to hand
it out, or the player ends up holding one nobody will accept with nothing on any
screen to say why — and that is closed at the **other end**: a disk the slot would
not take never leaves the drive. It is still in the machine, `df` still says what is
wrong with it, and one `rm` is the way out. Nothing the write path can do makes such
a disk; that is the belt under it, not the rule.

The ceilings a disk is held to are the disk's, per file included: `MAX_FILE_BYTES`
and not the `HISTORY_BYTES` a node on the hard drive may reach, because that larger
number belongs to the history exemption and the exemption belongs to the hard drive
alone. Nothing on a disk is ever exempt from anything — which is also why a disk may
carry no **device**: a device costs the quota nothing by design, and that is right
for the machine's own `/dev`, built afresh every command and swept again, and is a
hole on a disk where nothing sweeps and the nodes are saved.

Before any ceiling, though, comes what a disk is allowed to be **made of**
(`CeroSecOS.diskFieldsOk`), because a ceiling is asked of a filesystem and a *field*
is a place to hide things. `CeroSecOS.DISK_KEYS` is everything a disk owns and
`CeroSecOS.NODE_FIELDS` everything a node is, so junk hung on the disk, on its root,
on any node, or a whole subtree hung under a *file* node — which the quota walk never
descends into and the node count never sees — is refused rather than carried
unweighed, saved and published. It is asked of the table the game handed over and
before a byte of it is copied: the copy is what a payload is paid for in, and four
hundred thousand keys under a name nobody here has ever written cost half a second
to walk and one comparison to refuse.

Two things stay on the hard drive whatever is mounted. A `~/.sh_history` is exempt
from the quota because the exemption is the *drive's* — it exists so `df` on `hda`
does not move because somebody typed — so a history on a mounted disk is an ordinary
file there, written through `setData` and bounded by the disk. And the machine's own
records — the cron log, a mailbox, `/var/log/wtmp` — are found by a walk that does
not cross a mount and written straight onto the node, so under a mount over `/var`
the machine stops keeping them until the disk is out rather than leaving them
somewhere it can never read them again (`CeroSecOS.onOwnDrive`).

**Logical and physical paths.** `getNode` crosses a mount on the path it really
took, with every symbolic link already followed, and hands back the path that was
*typed*, because that is what `cd` keeps and what every shell prints. Those are not
the same string, and every rule about where a node lives — which disk it is on,
whether it is a mount point, whether it is under `/dev` — is a fact about the place
and not about the name, so it is asked with the fourth value `getNode` returns and
never with the third. Asked with the name, as they were when this was first written,
a symbolic link carried a write past the ceilings of the disk it landed on, a rename
past the cross-device refusal, a removal past the mount-point guard, and a mount
onto a name no walk would ever cross. `CeroSecOS.physicalOf` answers the same
question for a path that does not exist yet, which is what a create needs.

`mv` does not cross the two disks. `rename(2)` answers `EXDEV` and so does this,
in that error's own words; real `mv` falls back on a copy and this one deliberately
does not, because a half-finished copy behind the word "mv" is a lost file. The
manual sends the player to `cp` and `rm`.

