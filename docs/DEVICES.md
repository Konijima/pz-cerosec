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

**Discovery** is `SCeroSecDevices.find(x, y, z)`, a walk of the world and not a
book kept up to date, because the answer is only true for the moment it is asked
— and it is not walked twice inside `CeroSecDevices.CACHE_MS` (see *The `/dev`
cache*, below):

- The square's `getBuilding()`, when it has one → `getDef():getRooms()`
  (an `ArrayList<RoomDef>`, read the way `shared/Util/BuildingHelper.lua` reads
  it) → `getIsoRoom()` per room — `nil` while its chunks are not loaded — →
  `getSquares()` → `getObjects()`, **plus the far edge of every one of those
  squares** (below).
- No building → `getCell():getGridSquare()` over ±`CeroSecDevices.RADIUS` (10) on
  the same z. A `nil` square is an unloaded chunk and is skipped. No far edge
  here: that walk visits every square of its block, room or not, so a base's south
  wall is already standing on a square it goes to.

Before either: the machine's **own** square. No square there is a chunk the streamer
has not brought in, and a machine that is not in the world reaches nothing — `find`
answers an empty list at once rather than walking four hundred tiles that cannot be
there, which is the same guard `CeroSecRadio.tncAt` wears one layer down. So a computer
you have walked away from lists no devices and answers `no such device` about the
numbers in its own book, and its sensors fall out of the sampling book on the usual two
scans of grace. It is not switched off for it and it keeps running: the rule is
[ARCHITECTURE.md](ARCHITECTURE.md#the-chunk-that-goes-away).

**A fixture on the far edge of a room belongs to the room.** A wall object belongs
to ONE square and sits on that square's NORTH or WEST edge:
`IsoDoor.getOppositeSquare` is `getNorth()` then `getGridSquare(x, y - 1, z)`, else
`getGridSquare(x - 1, y, z)` (`javap -c`, offsets 0—56); `IsoWindow`'s and
`IsoThumpable`'s are `getInsideSquare()` off the same `north` field (offsets 9—77 of
each); `IsoCurtain`'s reads its sprite type and answers all four — curtainN north,
curtainS south, curtainW west, curtainE east, `null` for a sprite that is none of
them (offsets 0—141). So a door in a room's north or west wall stands on the room's
own square and the walk above finds it, while a door in the room's **south or east**
wall stands on the neighbouring square — the pavement, in no room at all, and a
square the walk of the building's rooms never visited. Every south and east door,
window and sheet of every building was invisible to `/dev` until 0.4.1, while the
north and west ones were listed: a module fitted to a front door that never became
a device.

So each room square's **south and east neighbours** are looked at too, and what is
taken off one is:

- a **door, window or curtain** whose own `getOppositeSquare()` is that room square
  — the engine's answer to which boundary the object is on, which is why a curtain's
  four types need no reading of `north`;
- a **light switch or lamp** whose sprite carries the `attached` property pointing
  at that room square. A light is not the wall, it hangs on one, and the property is
  what says which: vanilla reads `attachedN`, `attachedS`, `attachedW`, `attachedE`
  in that order to work out where a survivor must stand to pull the chain
  (`ISWorldObjectContextMenu.lua:1348-1352`, `onToggleLight`). The *Round Outdoor
  Lamp* is `MoveType = WallObject` with `attachedN` (`newtiledefinitions.tiles.txt`,
  tileset `lighting_outdoor_01`, tile 24), so a porch lamp stands on the pavement
  and hangs on the house's wall — and a **lamppost** has no `attached` property at
  all and carries `streetlight` instead (tile 0 of the same tileset). That is how a
  lamp on the building is told from the county's street lighting, and it is the
  engine's own distinction rather than a guess about a sprite name.

Nothing else is taken off a neighbour: a generator on the sidewalk is not the
building's, and neither is a sensor dropped there (the far-edge walk does not read
`getWorldObjects()` at all). And **only where the neighbour is in no room**: a
neighbour that has a room is a square the walk visits in its own right, so an
interior door is found from the other side and must not be found twice — the ordinal
in an entry's key is handed out per square, so one object reached twice would be two
devices with two numbers. It is the lock's own rule — exactly one of a door's two
sides has a room — read from the room's end. The one fixture this does not reach is a
wall shared by two **buildings**: the neighbour is the other building's room, so it
is that building's machine that lists the door.

**The numbers a save already has do not move for it.** A number hangs on where the
device is (`os.devmap`, keyed `kind:x:y:z:side:n`) and is spent for the life of the
machine, so a door the walk could never reach before takes the next free number and
never anybody else's — even where it sorts ahead of them, which a south door does.
The alternative, renumbering so that the ids follow the `(kind, x, y, z, side)`
order, would move `door0` under a script that was written for it, and is not done.

Classification is `instanceof`, and it answers a **list**, because one object can
be two devices — or three: `IsoLightSwitch` → `light`, `IsoWindow` → `win` *and*
`window`, `IsoDoor` → `door`, `lock` when the lock bites, *and* `curtain` when a
sheet is on it, `IsoThumpable` with `isDoor()` → `door` and `lock` (`built`),
`IsoCurtain` → `curtain`, `IsoStove` → `stove`, `IsoGenerator` → `gen`,
`IsoClothingWasher` / `IsoClothingDryer` / `IsoCombinationWasherDryer` → `washer`,
and `IsoWaveSignal` → `tv` for an `IsoTelevision` and `rx` for an `IsoRadio`, each
only when `getDeviceData()` answers. A player-built window frame is not a device.

The cost of that is per OBJECT and not per device: a plain wall or table on a
square falls through every one of those tests, which is eleven `instanceof` calls
where it used to be four. **Eleven and not twelve**, because the television and
the radio set are asked as the one base they share: `instanceof(object,
"IsoWaveSignal")` gates the pair, and only inside it is the object asked which of
the two it is. That is the test vanilla's own Lua makes of a world object, on the
server included (`server/ISObjectClickHandler.lua:240`,
`client/ISUI/ISRadioAndTvMenu.lua:7`). It is paid once a second and not ten times,
which is the cache below — `hostile_test.lua`'s mall bench is where the number is
printed.

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
| `curtain` | `CeroSec.CurtainMotor` | an `IsoCurtain`, or a door whose `HasCurtains()` answers | `curtain` | 2 |
| `appliance` | `CeroSec.ApplianceSwitch` | `IsoStove`, washer, dryer, combination | `stove` / `washer` | 2 |
| `window` | `CeroSec.WindowOperator` | window | `window` | 3 |
| `genset` | `CeroSec.GeneratorSwitch` | `IsoGenerator` | `gen` | 3 |
| `tuner` | `CeroSec.TunerControl` | `IsoTelevision`, `IsoRadio`, each with a `DeviceData` | `tv` / `rx` | 2 |

The four the motor rung added are on the **end** of `CeroSecModules.LIST` and
not in level order, because that list is the order the right-click menu offers
them in and a menu that reshuffles itself under a player is worse than one whose
levels do not run downhill.

**Four of the eight are built round a `CeroSec.SmallMotor`** — the strike, the
door operator, the curtain motor and the window operator, which are the four that
move a piece of metal or of cloth — beside a `Base.Receiver`, which is the part
that tells the motor when to stop. The other four sense or close a circuit and
take neither; the relay has never had a receiver and still has not.

Build 42 ships **no motor item of any kind**: `grep -rni motor` over the whole of
`media/scripts` returns ten hits and every one is a motorcycle helmet, a pair of
motorcycle boots or the Louisville Motor Shop step van. So the part is declared
in `items_cerosec.txt` and comes out of the four things in the game that really
have one — `Base.HairDryer`, `Base.SheepElectricShears`, `Base.CDplayer` and
`Base.BlowerFan` — through two dismantle recipes cut from vanilla's own
`DismantleElectronics` (`recipes_electrical.txt:37-54`). Two and not one, because
vanilla already dismantles three of the four and a survivor must never be worse
off choosing ours: the hair dryer, the shears and the fan pay the one
`Base.ElectronicsScrap` `DismantleElectronics` pays, and the CD player pays the
**two** `DismantleMiscElectronics` pays it (its `itemMapper` maps a CD player back
to scrap). One recipe cannot pay one item for three inputs and two for the fourth,
and the mapper cannot either — it is keyed by the OUTPUT, so three inputs yielding
scrap would collide on one key. Both are `NeedToBeLearn` and both are in the
Field Wiring Guide's `LearnedRecipes` with the other six.

The table, the levels, the fit rules and the modData read/write are
`shared/CeroSec/CeroSecModules.lua` — **shared**, because the right-click menu
asks the same questions the discovery does and a client cannot load a server
file. `roomName`, `doorLocks` and `isManyDoors` moved there from
`SCeroSecDevices.lua` for that reason and are forwarded back under their old
names, so every call site there reads as it did.

**Where the recipes come from: a magazine, the vanilla way.** The four
`craftRecipe` blocks in `common/media/scripts/recipes_cerosec.txt` are
`NeedToBeLearn` and they are taught by `CeroSec.WiringGuide`, the *CeroSec Field
Wiring Guide* — a `base:literature` item whose `LearnedRecipes` names all four.
B42 has no `TeachedRecipes` left anywhere in `media/scripts`; `LearnedRecipes` is
the key (`items/literature.txt:5307-5320`, `Base.ElectronicsMag1`). Reading is
**entirely engine-side and the mod ships no Lua for it**:
`IsoGameCharacter.ReadLiterature(Literature)` walks `getLearnedRecipes()`, skips
what `getKnownRecipes()` already holds and calls `learnRecipe(String)` on the
rest (`javap -c`, offsets 24–81). The Lua side only *offers* the option
(`ISInventoryPaneContextMenu.lua:1081` spots the item, `:1107` adds Read) and
runs the timed action — `ISReadABook:perform()` at `:194` learns nothing, it
closes the book.

`SkillRequired` stays at the level that *fits* the module, and `AutoLearnAll`
sits **six levels above it** (7, 7, 8, 9). That is vanilla's shape for a
magazine-taught recipe and not a departure from it: vanilla does **not** drop the
auto-learn key when a magazine teaches a recipe, it spreads the two apart.
`MakeImprovisedFlashlight` is `SkillRequired 1` / `AutoLearnAny 3`
(`recipes/recipes_electrical.txt:101-109`, taught by `Base.ElectronicsMag5`) and
`MakeRemoteControllerV1` — the vanilla electrical recipe these four are nearest
to — is `2` / `8` (`recipes/recipes_traps.txt:3-11`, taught by
`Base.ElectronicsMag1`). Six is that recipe's own gap. So the skill still gates
the craft, the book is how a survivor actually comes by the recipe, and a master
electrician gets there alone in the end.

The guide's loot is the vanilla electronics-magazine family's own, shelf for
shelf and number for number (`CeroSecGuideLoot.lua`): `ElectronicStoreMagazines`
8; `BookstoreMisc`, `BookstoreBlueCollar`, `ToolStoreBooks` and `ElectricianTools`
2; `MagazineRackMixed`, `PostOfficeMagazines`, `CrateMagazines` and
`LibraryMagazines` 1.

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

**A window is two devices, and the reason `win` is read-only is not the one this
page used to give.**

It said: *the only call in the game that moves a sash is
`IsoWindow.ToggleWindow(IsoGameCharacter)`, which wants a character, so there is
no window actuator to build.* The call is right and the reason was wrong.
`ToggleWindow` **never dereferences the character**: the barricade test at offsets
37–49 is skipped when it is null, the `IsoZombie` test at 93–97 is false for null,
the music-intensity call at 166–197 is behind an `ifnull`, and the sync at offset
147 is unconditional. A Lua `nil` reaches a Java object parameter as `null` — see
*the nil argument*, below — so the call can be made, and it is: that is
`CeroSec.WindowOperator` and the `window` device.

What is true is three side effects, and with a motor on the sash all three are
what a motor really would do:

- **It throws the catch.** Offsets 50–54, `locked = false`, unconditionally,
  before the sash moves. So the latch stays `win`'s reading and never becomes the
  operator's word, and a `winN` that read `locked` reads `unlocked` after the
  machine opens the window.
- **It sets off the house alarm.** Offsets 86–118: when the sash ends up open the
  sandbox check (`lore.triggerHouseAlarm`) is consulted **only** for an
  `IsoZombie`, so a null character falls straight into `handleAlarm()`. Kept, and
  documented as a feature rather than argued away — a window opening in an alarmed
  house is a window opening in an alarmed house. It is on the page of Volume 2 a
  survivor reads before he fits one, and in the release notes.
- **It skips the barricade**, because the barricade test is the one thing it asks
  the character for. So a boarded window would move behind its boards, and the
  refusal is ours and comes before the call — exactly as a barricaded door's does.

And there are two more silent returns above all of that which the study did not
name: `permaLocked` at offsets 21–28 (`window0: sealed`) and `destroyed` at 29–36.
`isSmashed()` and `isDestroyed()` read the **same** field `#393`, both bodies three
instructions long, so `smashed` covers the second and there is no fourth word.

So `winN` is the magnetic contact and reads the latch, `windowN` is the operator
and moves the sash. Two vocabularies, so two kinds, exactly as `doorN` and `lockN`
are two kinds on one door: a node that took `lock`, `unlock`, `open` and `close`
would be a node whose mode could not say which of them it could carry out. `winN`
stays `ro` because a magnetic contact is a **sensor and senses**, which is the
true reason and the one it always should have given.

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

**What the right-click menu lists, and what it hides.** One line per module that
could ever go on a fixture of that **sort**, carried or not — and the only thing
hidden is `fitsOn` answering `fixture`, the module that could never fit. Its
other two answers (`nolock`, `manydoors`) are about *this* door and not about
doors, so they are lines and they say so. A survivor cannot go and look for a box
he has never been told exists, which is why the entry is now there before he owns
one; it is greyed with `Tooltip_CeroSec_ModuleItem` ("you are not carrying one")
or, when he does not know how one is made,
`Tooltip_CeroSec_ModuleRecipe` — `IsoGameCharacter.isRecipeKnown(String)`, which
is one call over the sandbox option `seeNotLearntRecipe`, `isKnowAllRecipes()`
and `getKnownRecipes().contains(name)` (`javap -c`, offsets 0—53), so a master
electrician who auto-learnt the recipe answers yes without a case of ours. The
recipe name per module is `recipe` on `CeroSecModules.LIST`.

**Every entry carries its description**, greyed or not:
`Tooltip_CeroSec_ModuleDesc_<id>` — what the box buys, which device it gives and
the level it wants, with the level passed as `%1` off `CeroSecModules.LIST` so
nine modules are one line of English. The reason, when there is one, goes on the
line **under** it: a refusal with no idea what it is refusing is a line a player
reads twice. If nothing is left after the hiding, there is no submenu and no
"CeroSec hardware" parent either.

**Where he has to be standing, what has to be open, and whose safehouse it is.**
Three more refusals, all of them about the MOMENT rather than about the shape of
the fixture, all of them decided in `CeroSecModules.fittingRefusal` — one
function, shared, which the server refuses on and the menu greys with, in the
`turnOnRefusal` shape (one rule, one place, one wording). The reason word IS the
tooltip key: `CeroSecModuleMenu.tooltipFor` builds
`Tooltip_CeroSec_Module<Reason>` from it rather than looking it up in a second
list. Every one is asked of a REMOVAL exactly as of a fitting — the hand is in
the same place either way, and a module anybody could unscrew from the pavement
is what the first rule exists to stop.

| fixture | must be | reason word | the getter, proven |
| --- | --- | --- | --- |
| door (map or built) | open | `closed` | `IsoDoor.IsOpen()`, `IsoThumpable.IsOpen()` (proofs, 4) |
| window | open | `closed` | `IsoWindow.IsOpen()` (proofs, 4) — which already excludes smashed, sealed and barricaded: none of those opens |
| curtain (`IsoCurtain`) | open | `drawn` | `IsoCurtain.IsOpen()` |
| a door's own sheet | open | `drawn` | `IsoDoor.isCurtainOpen()` — the fields are on the door and there is no second object |
| stove, microwave, coffee | off | `running` | `IsoStove.Activated()` (capital A; the laundry's is not) |
| washer, dryer, combination | off | `running` | `IsoClothingWasher.isActivated()` and its two siblings |
| television, radio set | off | `running` | `IsoWaveSignal.getDeviceData()` then `DeviceData.getIsTurnedOn()` |
| generator | off | `running` | `IsoGenerator.isActivated()` |
| light switch | — | — | a relay goes behind a plate whose only state is the light it works |
| door, window, curtain (map or built) | a survivor standing in a room | `outside` | `IsoGridSquare.isInARoom()` |
| in a safehouse, with the option on | a player the safehouse allows | `safehouse` | `SafeHouse.getSafeHouse(square)`, then `SafeHouse.playerAllowed(IsoPlayer)` |

The state asked for is the state of what the MODULE is screwed to and not of the
object it sits on, which is the same door twice: a curtain motor on a door asks
about the sheet, a strike on that same door asks about the door. A rule written
per fixture could not tell the two apart and one of them would be asked the
wrong question.

**`isInARoom()` and not `getRoom() ~= nil`**, and the difference is a base: the
call is `getRoom() != null || getIsoWorldRegion().isPlayerRoom()` (`javap -c
zombie.iso.IsoGridSquare.isInARoom`, offsets 0—31), so four walls a PLAYER put up
— which the map has no `RoomDef` for — read as inside, and `getRoom()` alone would
refuse a man standing in the middle of his own base. Vanilla asks it that way
itself (`server/BuildingObjects/ISEmptyGraves.lua:169`,
`server/Vehicles/Vehicles.lua:667`). It is asked of **his** square and never of
the fixture's: a door stands on the room's own square — which is why `doorLocks`
reads `getSquare()` against `getOppositeSquare()` and calls the pair *exactly one
of them has a room* — and he stands on one side of it or the other. The inside
side is in a room; the pavement is not. An interior door has a room on both
sides, so both sides are allowed.

**The inside rule is the ENVELOPE's, and the envelope is three classes** — the
door, the window and the curtain, which are what a stranger would strip to get in
or to blind the alarm. That is what the rule was written for, and a module anybody
could unscrew from the pavement is what it exists to stop.

Nothing else is asked about a room. A **porch lamp** is the case a relay is FOR —
an outdoor light on a timer, screwed to the outside of the house, reached from the
pavement because there is nowhere else to stand — and a rule that wanted a room
round it was a `relay` greyed out on the one fixture it was made for (reported in
game on 0.4.0, a *Round Outdoor Lamp*). The same goes for an appliance, a set or a
generator a survivor has dragged outside: they are fitted where they stand. The
generator used to be the one exemption and is now one of five, for its own reason
read wider — it is an outdoor machine by construction, and so is a porch lamp.

**The safehouse gate is a sandbox option and it is OFF by default** —
`SandboxVars.CeroSec.SafehouseModules`, read the way vanilla reads a grouped
option and failing **open**, which is the opposite direction to
`CeroSecModules.required()`. That is the compatibility contract and not a
preference: a new option defaults to the old behaviour, and a sandbox file that
failed to load must not be a world where nobody may touch his own hardware —
where the hardware gate failing closed gives a player an empty `/dev`, which he
can read off the screen. `SafeHouse.getSafeHouse(square)` is asked of the
**fixture's** square, because what is being protected is somebody's door and a
man on the pavement outside a safehouse is the case it exists for; it is
`isSafeHouse(square, null, false)` down to `findSafeHouse`, a walk of
`safehouseList` comparing the square's x and y against each box (`javap -c`,
offsets 28—69), so nil for every square in a single-player game.
`playerAllowed(IsoPlayer)` is vanilla's own membership question and **admins pass
it without a branch of ours**: `players.contains(getUsername()) ||
owner.equals(getUsername()) || role.hasCapability(CanGoInsideSafehouses)`
(offsets 0—46), and that capability is what vanilla's own
`isSafehouseAllowInteract` reads for the same purpose (offsets 23—44). A
safehouse's own rule against **looting** is not consulted either way: fitting is
not looting — nothing leaves the building — so this option is the only gate.

**Pre-fitted hardware is not affected.** The 1991 walk writes the modData itself
(`CeroSecModules.setOn`, `markPreFitted`) and performs no player action at all,
so it never comes past any of this: a fixture shut, in a stranger's safehouse,
with the option on, still gets the hardware the building was built with.

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

**The motor rung's five kinds**, each with what `cat` reads, what a redirect
accepts and what it refuses. Every state is read off the object on every answer
(`stateOf` in `SCeroSecDevices.lua`); the refusals are `act`'s.

| kind | module | reads | accepts | refuses |
| --- | --- | --- | --- | --- |
| `curtain` | `curtain` | `open`, `closed` | `open`, `close` | `barricaded` |
| `window` | `window` | `smashed`, `barricaded`, `sealed`, `open`, `closed` | `open`, `close` | `smashed`, `barricaded`, `sealed` |
| `stove` | `appliance` | `broken`, `on`, `off` | `on`, `off` | `broken`, `no power` |
| `washer` | `appliance` | `on`, `off` | `on`, `off` | `no power` |
| `gen` | `genset` | `on`, `off` + the line below | `on`, `off` | `no fuel`, `broken`, `not connected` |
| `tv` / `rx` | `tuner` | `on`, `off` + the dial and the schedule | `on`, `off`, `channel <n>` | `no power`, `out of range` |

A `windowN` is read in the order the engine tests it: the glass, the boards, the
permanent lock, then the sash. `sealed` is `isPermaLocked()`, a window the map
was built with that never opens. A `stoveN` puts `broken` first for the reason a
door puts `locked` first: it is the thing a survivor has to do something about,
and a broken stove is off by construction. No kind has a `no power` **state** —
power is a fact about the wire and not about the appliance, and a light switch
has always said it as a refusal.

**A generator says more than a word**, and it is the only kind that does:

```
root@ksp-04-11:~# cat /dev/gen0
on fuel 62 condition 80 connected
```

Both numbers are percentages (`getFuelPercentage()`, `getCondition()`), rounded
to a whole one and clamped to 0..100; `connected` is a fact and is there or is
not. It travels as `detail` beside `state` on the entry and on the node, and
`CeroSecOS.devText` is the one place the two are put back together: `cat` and
`dev <id>` read the whole line, `ls -l /dev` and the `dev` table read the word,
because those two have a column for a word and the terminal is 60 wide and does
not wrap. `dev <id> toggle` therefore looks its opposite up by `node.state` and
not by what the read printed — a table keyed by that sentence would have no
entry for anything.

Its three refusals are asked **only of starting one**, and they are vanilla's own
timed action's (`ISActivateGenerator:isValid`): `not connected`, `no fuel`,
`broken`. Stopping one is never refused. And `failToStart()` — the coin flip
that same action makes below half condition — is deliberately **not** copied: a
shoulder fumbles a cord and an electric starter does not, and a starter is what
the module is.

**A curtain's barricade is found the only way it can be.** `IsoCurtain` has no
`isBarricaded()`: `barricaded` is a public field with no getter over it, so there
is nothing to ask before the call. What there is, is that
`ToggleDoorSilent`'s first two instructions are `barricaded -> return` (offsets
0—7) and that is the **only** way out of the method without moving the sheet. So
the device toggles, reads back, and answers `curtain0: barricaded` when the sheet
did not move.

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
is capped at `CeroSecDevices.MAP_MAX` (512) so a computer carried across the map
does not grow one entry per light switch in the county. Twice `CeroSecOS.DEV_MAX`
on purpose: the book has to hold the building the machine stands in *and* the one
it stood in before, or a computer carried back into a mall it has already numbered
gives every light a second number.

**The two ceilings.** `CeroSecOS.DEV_MAX` (256) is how many nodes `/dev` may hold
at once, and it is the only ceiling `/dev` answers to: the 96-entry directory rule
(`CeroSecOS.MAX_DIR_ENTRIES`) guards the *write* path, and the write path refuses
`/dev` as read-only one gate earlier — nothing but the mount can put an entry
there, and the mount is held to `DEV_MAX`. It was 64, and 64 was a computer in one
store of a shopping mall that could not see half the mall: a mall is **one**
building as far as `BuildingDef` is concerned, so every store's lights, doors and
windows are on that one machine's `/dev`, and the map ships buildings with several
hundred. A device a survivor cannot see through `dev` is a device he cannot reach
at all. The cost is paid per command (the mount is built afresh at the top of each
one and swept off before the answer) and never in the save file: a device node
costs the disk quota nothing (`CeroSecOS.subtreeUsage`) and the state gate refuses
any device of the world on a saved disk.

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
| `curtain` (`IsoCurtain`) | `ToggleDoorSilent()` | **none needed** | the toggle's own last act is `syncIsoObject(false, open, null)` at offsets 85—100, and that override's server branch walks `GameServer.udpEngine.connections`. The one actuator here whose broadcast is the engine's. Vanilla makes the bare call itself on a curtain nobody is holding: `client/DebugUIs/Scenarios/Trailer2Scenario.lua:134` |
| `curtain` (a door's sheet) | `toggleCurtain()` | **none needed** | on the server it is the whole gesture: `setCurtainOpen` then `transmitSetCurtainOpen(isCurtainOpen())` at offsets 55—60, whose server branch is `sendObjectChange(SET_CURTAIN_OPEN)`. `setCurtainOpen(b)` alone is the half that does not broadcast |
| `window` | `ToggleWindow(nil)` | **none needed** | `sync(open ? 1 : 0)` at offset 147, unconditional. The character is never dereferenced; see *A window is two devices* and *The nil argument* |
| `stove` | `Toggle()` | **none needed** | `Toggle()` is `setActivated(!activated)` plus `getContainer().addItemsToProcessItems()` plus `IsoGenerator.updateGenerator(square)` (offsets 0—27), and `setActivated`'s server branch calls `sync()` and `syncSpriteGridObjects(true, true)` at 201—214. The setter alone would switch on an oven that cooked nothing and drew nothing. It is vanilla's own server line: `server/ClientCommands.lua:1049-1062` |
| `washer` | `setActivated(b)` | `sendObjectChange(IsoObjectChange.WASHER_STATE)` | the setter is a field write plus `updateGenerator` and no sync at all; `saveChange` writes `isActivated()` under that change, and `sendObjectChange` is server-only by construction. The pair is `shared/TimedActions/ISToggleClothingWasher.lua`'s own |
| `gen` | `setActivated(b)` | `sync()` | idempotent by construction (offsets 0—8 return when the argument is the state it is in) and its server branch calls `sync()` at 113—122; vanilla calls `sync()` again after it (`ISActivateGenerator:complete`) and so does this |
| `tv` / `rx` | `DeviceData:setIsTurnedOn(b)`, `DeviceData:setChannel(n)` | **ours, and the mod's own packet** | there is no engine call that broadcasts either field from the server; see *The sync the mod writes itself*, below |

### The sync the mod writes itself

Every row above is the engine's packet. The television and the radio set are the
one pair where there is none, and this is the only place in the mod where a
server-side write is followed by a message of our own.

**Why there is none.** Everything a set has lives on `zombie.radio.devices.DeviceData`,
and the only method that puts a change of `isTurnedOn` or `channel` on the wire is

```
private void transmitDeviceDataState(short);
   0: getstatic  #276   // GameClient.client:Z
   3: ifeq       37                       <- not a client: return
  15-20: sendDeviceDataStatePacket(GameClient.connection, arg)
```

a **client branch and nothing else**. The server's own broadcaster exists and is
`private` — `transmitDeviceDataStateServer(short, UdpConnection)` — and every
caller of it is inside the class. The one public wrapper,
`transmitBatteryChangeServer()`, passes the short `2`, and the `tableswitch 0..10`
in `sendDeviceDataStatePacket` (offset 345) spends `2` on `hasBattery` and
`powerDelta`: `0` is `isTurnedOn`, `1` is the channel, and nothing public reaches
either. So a server-side `setIsTurnedOn(true)` moves the field on the server and
leaves every client's copy dark and silent.

**What the mod sends.** One `device` command on `CeroSec.MODULE`, broadcast to
every connection (`PROTOCOL.md` has the fields). It carries the square, the class,
the sprite name and the object's index on that square, plus **both** fields as
they read *after* the write — not what was asked for, because `setIsTurnedOn`
refuses an unpowerable set by turning it off instead.

**What the far end does with it** (`client/CeroSec/CCeroSecDevices.lua`):
`setTurnedOnRaw(b)` and `setChannelRaw(n)`, and nothing else. Those are the public
names of exactly what the engine itself does on this path — a client receiving
vanilla's own state-0 packet calls the private `setIsTurnedOnInternal` (offsets
124—129) and writes `channel` with a bare `putfield` (179—182), and
`IsoWaveSignal.loadState` uses `setTurnedOnRaw` / `setChannelRaw` /
`setDeviceVolumeRaw` (116—154). Using the **public** setters on a client would
transmit, the server would relay that to everybody, and one crontab line would
cost a round trip per client.

The screen, the glow and the sound all follow that field with nothing else called:
`IsoTelevision.update()` ends on `updateTvScreen()` (offsets 57—58), whose first
test is `getIsTurnedOn()`; `IsoWaveSignal.update()`'s not-a-server branch
(48—105) picks `updateLightSource()` or `removeLightSourceFromWorld()` by the same
field; and the same method sends a client to `DeviceData.updateSimple()`, which
calls `updateEmitter()` (118—125), which reads `isTurnedOn` at 45—49 to decide
whether the loop sound plays.

**Single player sends nothing and needs nothing**, and that is the engine's doing
rather than a branch of ours: `LuaManager$GlobalObject.sendServerCommand(String,
String, KahluaTable)` opens on `getstatic GameServer.server; ifeq return`. One
process means the object the server wrote is the object the survivor is looking
at. One code path, two games.

**Late joiners are correct by the engine, and no chunk hook is needed.** Every
chunk a client loads asks the server for that chunk's object state —
`IsoChunk.doLoadGridsquare`, offsets 1650—1675, `if (GameClient.client)
connection.addChunkObjectState(wx)` and the same for `wy` — and the server answers
out of the **live** object: `ChunkObjectStateRequestPacket.parse` →
`IsoChunk.saveObjectState` (offset 99) → `IsoObject.saveState` per object
(124—127), where `IsoWaveSignal.saveState` writes `getIsTurnedOn()` at 73—93,
`getChannel()` at 94—105 and `getDeviceVolume()` at 106—117. The client applies
them through `loadState`'s three raw setters. So a player who connects an hour
after cron switched the television on sees it on, and a player who walks back into
a chunk that was unloaded sees what it is doing now.

**The refusals are ours and come before the call**, because both setters swallow
an order they cannot carry out instead of refusing it:

- `setIsTurnedOn(Z)` — `canBePoweredHere()` false takes the 44—58 branch, which
  turns the set **off** whatever was asked (offsets 0—4); battery-powered with
  `powerDelta <= 0` calls `setIsTurnedOnInternal(false)` at 31—33 (7—20). Both are
  `no power`, the word the light switch and the stove already use. It also ends on
  `IsoGenerator.updateGenerator` (118—130), which is the third of the gesture that
  makes a generator feel the load.
- `setChannel(I)` → `setChannel(I, true)` returns at offset 105 outside
  `minChannelRange..maxChannelRange`, having done nothing at all (0—13). That is
  `out of range`. A frequency nobody **broadcasts** on is *not* refused: vanilla's
  own window tunes anywhere in the span and prints "Unknown channel", a television
  on a dead frequency shows the test card (`updateTvScreen`, 79—83), and a refusal
  the game does not make is a refusal we would have invented.

**The dial is raw and not megahertz.** `/dev/radio0` prints megahertz and can
afford to — it is read-only, so its reading is the only spelling of that number
anybody meets. A dial a survivor can *write* cannot: `echo channel 203` beside a
line reading `0.203` would be one number under two names. It is also the game's
own split — `RWMGeneral:setInfoLines` prints megahertz for a radio and, for a
television, prints no frequency at all, only the channel's name (`:66-81`).

**What is airing, and when the next block starts**, rides in the same `detail` the
generator's fuel does: `on channel 203 airing 1080-1440`. The reading is
`CeroSecRadio.scheduleOf` — `getZomboidRadio():getScriptManager():getChannelsList()`,
then `RadioChannel.GetFrequency()` / `IsTv()` to pick the station, then
`getAiringBroadcast()` for what is on and `getCurrentScript():getBroadcastList()`
for the nearest block still to come. The channel list is memoised and rebuilt when
its **size** changes, which is vanilla's own staleness test for that list
(`ZomboidRadioDebug:populateList`, `:103-105`). `getValidAirBroadcast()` is
**never** called: offsets 42—44 set `currentHasAired = true` on the way out, so
asking it would take a broadcast away from the radio's own simulation. The stamps
are minutes of the day and are printed as minutes of the day, because a program
compares the first of them with the clock; `RadioData.loadBroadcast` reads only
`ID`, `timestamp` and `endstamp`, so a stamp carries no date and there is no wrap
to tomorrow.

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

## The `/dev` cache

**The walk is the most expensive thing this mod does and nothing measured it
until the motor rung.** `notes/actuators.md` put a five-second polling daemon at
one building walk every five seconds, reasoning from `CeroSecOS.jobStep`
returning above `CeroSecOS.mountDev` for a sleeping job. It does return there —
and the walk is not in `mountDev`. It is in `CeroSecDevices.envFor`, reached
through `SCeroSecSystem:execEnv` from `CeroSecJobs.runMachine`, which runs **once
a pass** for any machine with a job in its book at all, before a single job is
looked at. A machine gets a pass every `CeroSec.JOB_PASS_MS` (100 ms), so the
daemon walked the whole building **ten times a second** — and none of it showed
in a step count, because a walk costs no steps.

So `CeroSecDevices.findCached(x, y, z, now)` sits in front of it, keyed by where
the machine **stands**, with a lifetime of `CeroSecDevices.CACHE_MS` (1000 ms,
which is ten passes).

- **What is remembered** is what a device IS: that there is a door at that square,
  which way it faces, the rooms it stands between, what is screwed to it. That is
  a fact about the building.
- **What is never remembered** is what a device is DOING. Every answer re-reads
  the state off the object (`stateOf`, and `CeroSecRadio.restate` for the TNC), and
  the rest of a generator's line with it (`detailOf`) — a door opened by a hand
  between two passes reads `open` on the second one.
- **What throws it away**: the clock; the minute sweep, which walks anyway and so
  drops the entry first and refills it with what its own walk found; a module
  going on or coming off **any** fixture (`installmodule`, `uninstallmodule` and
  the pre-fitting walk all call `CeroSecDevices.invalidate`, which empties the
  whole book — which machines can see a fixture is the question the walk exists
  to answer); and the machine standing somewhere else, which is a different key.
- **What it costs is one second, in both directions.** A device that appears — a
  chunk streaming in, a door somebody builds — is not on `/dev` until the next
  walk, and a device that is knocked down reads its last state until then too.
  That is the same second the discovery has always been honest about. What is
  **not** a second late is a device being *worked*: `envFor`'s `write` and `find`
  ask `alive` of the one object they are about to touch, so an order to a door
  somebody has knocked down answers `no such device` and moves nothing. Asking it
  of the whole list instead would be four engine calls per device per pass — on
  a mall, sixty thousand a second for one machine — to buy a listing that is
  right a second sooner, and the listing was never the thing that had to be right.

**Measured**, in engine calls rather than in milliseconds, because the walk is
Java on the far side of a Kahlua call and a timing says more about the box than
about the code (`hostile_test.lua` section 27): a sixty-room mall, a hundred
passes at the scheduler's own cadence. **7,109,900 calls and 100 walks without the
cache; 845,990 and 10 with it.**

## The nil argument

`IsoWindow.ToggleWindow(IsoGameCharacter)` is called with `nil`, and that a Lua
`nil` reaches a Java object parameter as `null` is proven twice over.

**At the bytecode.** `LuaJavaInvoker.prepareCall` pulls each argument off the call
frame (offsets 295—304) and converts anything the parameter type is not already
an instance of (325—347) — which a null never is, `Class.isInstance` answering
false for it. `convert(Object, Class)` returns `null` at its first two
instructions for a null input (offsets 0—5), before the converter manager is
asked anything. And the type check at 349—392 is
`if (arg != null && converted == null) fail(...)`: **the failure is guarded on
`arg != null`**, so a null argument is stored straight into the parameter array at
393—405. The argument *count* is not exempt — offsets 126—137 refuse a call
with too few — so the `nil` has to be written and cannot be left out.

**And vanilla's own Lua does it.** `media/lua/shared/TimedActions/ISLockDoor.lua`
:56, :62 and :69 — `door:syncIsoObject(false, 0, nil, nil)` — passes `nil` into
a `UdpConnection` and a `ByteBufferReader`, and this mod has made that same call
on every door write since rung 1.

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


### Hardware that was already fitted

Some premises were wired before the outbreak, and about one in three that had a
nightly job to run really was: relays on the light switches, contacts on the doors and
windows, a strike where the lock stops somebody. The decision, the roll and where it is
written down are in
[CONTENT.md](CONTENT.md#the-premises-that-were-already-automated); what matters here is
that **nothing about such a module is special**.

- **The same writer.** `CeroSecAuto.fit` goes through `CeroSecModules.setOn`, the one
  function that writes a fixture's modData, so the discovery, `/dev`, `dev`, the
  right-click menu and the Devices tab of the debug window see exactly what they see
  for a module a survivor screwed on. There is no second table and no flag that says
  "the mod put this here".
- **It comes off into his hands.** `Commands.uninstallmodule` asks nothing about where
  a module came from, so a pre-fitted relay is a relay in his bag — it is real
  hardware, and pretending otherwise would be a box he can see and cannot have.
- **And it stays off.** This is the one thing the shape had to gain.
  `CeroSecModules.PRE_KEY` (`pre`) is written beside the ids, it **outlives every
  module coming off** (`setOn` keeps the table alive for it, where it would otherwise
  take the last empty one away), and the pre-fitting walk skips any fixture that
  carries it. Without that, a survivor who unscrews a relay for the item finds it back
  on the plate at the top of the next minute, which is a mod undoing a player's own
  work. A table this build cannot read — one a *later* build wrote — answers "already
  done" for the same reason: the last thing to write into is somebody else's shape.
- **`CeroSecModules.VERSION` moves to 2 for it**, with a step that converts nothing.
  Strictly it did not have to: an absent mark reads as "not pre-fitted", which is the
  old behaviour on every fixture in every save. It moves for the reader — a table that
  has grown a key which is not one of the four ids and does not behave like one is a
  shape nothing can be held to afterwards — and the step is *written* rather than
  absent, because a gap in the chain is what `migrate` refuses to walk. One consequence
  is worth knowing and is written down at the constant: the walk has always ended each
  step with `fitted[v] = n`, so the moment the number moved past 1, the first **read**
  of an older table became the thing that stamps it, on a client as well as on the
  server. Harmless in both places — on a client it lands in a table nobody else sees,
  on the server it lands in the chunk, which is where the answer belongs — and it is
  the stamp that stops a step which does real work from running twice.
- **Never an operator.** A relay, a contact and a strike; no motors. A 1993 shop had a
  magnetic contact on the stockroom frame to know the door was shut and an electric
  strike to bolt it, and a building that opened its own doors would open them for the
  dead.
- **Fitted whether or not the option needs it.** With `HardwareRequired` off nothing
  needs fitting, and the walk fits anyway: the modules are then items a survivor can
  take off a wall, and a world where they are there is truer than one where the shop
  was automated by magic.

Which fixtures: the ones the machine can act on, sifted back down to its own premises.
`CeroSecDevices.fixturesInRooms` is handed the rooms of the **premises** — its
tenancy's in a mall, the building's anywhere else — and walks at most
`CeroSecAuto.ROOMS_PER_MINUTE` of the ones whose chunks are in. A room it walked is
written into the premises' record and **never walked again**, which is how the
pre-fitting comes back for a room whose chunks were away, finishes in any chunk order,
and stops coming back: a five-hundred-room mall is never in the world all at once, so a
walk that waited for every room to answer together waited for ever and re-walked the
mall every game minute while it did. Each fixture is then asked
`CeroSecNet.premisesOfSquare` for itself, so a shop inside a mall wires its own tenancy
and not the other twenty-nine.


## The floppy drive, and the second filesystem

The disk is an **item**, and what is written on it lives in the item's modData and
not in the computer: `{ v = 1, fs = <directory node>, label = "WORK" }`, the same
shape `state.floppy` has while the disk is in the drive, because it *is*
`state.floppy` while the disk is in the drive. Three pieces, and they are
deliberately three (`CeroSecOSDisk.lua`):

- **The disk.** `state.floppy`, or nothing at all when the slot is empty. A missing
  `fs` is an unformatted disk, which is what a new one out of a box is. `label` is
  the sticker a survivor writes on it with a pen, and it is the one field of the
  record a player puts there himself: it lives on the ITEM as its custom name
  (`CeroSecFloppyMenu`, on the inventory menu), the slot reads it off the item and
  writes it here, `mount` and `df` print it after the device, and the eject puts it
  back on the shell — which has to be done deliberately, because an insert destroys
  the item and an eject makes a new one. `CeroSecOS.labelOk` is the whole of what may
  be written: up to `CeroSecOS.LABEL_MAX` (24) letters, digits, spaces, dashes and
  dots, never empty and never all spaces. It is held to that at the slot as well as
  in the box, because a forged name with a newline in it would put a second line in
  the mount listing.
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
unweighed, saved and published. It is asked of a disk **record**, before a byte of it
is copied, and the record is built out of the keys a disk owns and nothing else
(`ownKeysOf`): a name nobody here declared is left on the item, where the game and
other mods write their own (`customName` among them). The copy is what a payload is
paid for in, and four
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

