# Hardware modules — the proofs

Every engine call the hardware modules make, proven against the shipped jar
(`projectzomboid.jar`, B42.20.4) with

```
javap -p -c -cp .../projectzomboid.jar <class>
```

and every vanilla Lua pattern they copy, quoted with its file and line.
`decompiled-src` is from January and is older than the jar: it is not cited here.

## 1. Where a module lives: `IsoObject` modData

```
public se.krka.kahlua.vm.KahluaTable getModData();
public void setModData(se.krka.kahlua.vm.KahluaTable);
public boolean hasModData();
public void transmitModData();
```

`getModData()` answers a `KahluaTable` — the Lua table itself, which is why
`object:getModData().cerosec = { ... }` is a plain table write and not a call.

**It is saved with the chunk.** The field behind those three methods is
`private se.krka.kahlua.vm.KahluaTable table;` (constant `#850`), and
`IsoObject.save(java.nio.ByteBuffer, boolean)` writes it:

```
893: getfield      #850   // Field table:Lse/krka/kahlua/vm/KahluaTable;
897: ifnull        930
904: invokeinterface #866, 1   // KahluaTable.isEmpty:()Z
909: ifne          930
915: invokeinterface #1162, 2  // BitHeaderWrite.addFlags:(I)V    <- bit 0x4
925: invokeinterface #1228, 2  // KahluaTable.save:(Ljava/nio/ByteBuffer;)V
```

and `IsoObject.load(java.nio.ByteBuffer, int, boolean)` reads it back under the
same flag bit, making the table if there is none yet:

```
1147: invokeinterface #925, 2   // BitHeaderRead.hasFlags:(I)Z    <- bit 0x4
1166: invokevirtual #860        // J2SEPlatform.newTable:()Lse/krka/kahlua/vm/KahluaTable;
1177: invokeinterface #1103, 3  // KahluaTable.load:(Ljava/nio/ByteBuffer;I)V
```

An empty table is not written at all (the `isEmpty` branch), which is why a door
nobody has touched costs a save nothing.

The four classes a module can sit on all reach that code, because all four begin
their own `save`/`load` with the superclass':

```
IsoDoor.save        3: invokespecial #701  // zombie/iso/IsoObject.save:(Ljava/nio/ByteBuffer;Z)V
IsoDoor.load        4: invokespecial #683  // zombie/iso/IsoObject.load:(Ljava/nio/ByteBuffer;IZ)V
IsoWindow.save      3: invokespecial #651  // IsoObject.save
IsoWindow.load      4: invokespecial #618  // IsoObject.load
IsoLightSwitch.save 3: invokespecial #414  // IsoObject.save
IsoLightSwitch.load 4: invokespecial #349  // IsoObject.load
IsoThumpable.save   3: invokespecial #550  // IsoObject.save
IsoThumpable.load   4: invokespecial #345  // IsoObject.load
```

**`IsoThumpable` is the one that does not use the inherited table.** It declares
`private se.krka.kahlua.vm.KahluaTable modData;` (constant `#3`) and its own
`getModData()` reads that field and not `IsoObject.table`:

```
getModData():  0: aload_0   1: getfield #3  // Field modData:Lse/krka/kahlua/vm/KahluaTable;
```

It is persisted all the same, by `IsoThumpable`'s own `save`/`load`, under a flag
bit of its own (`4194304`) beside the inherited one (`2097152`):

```
IsoThumpable.save  434: getfield #3   // modData
                   444: invokeinterface #86, 1    // KahluaTable.isEmpty:()Z
                   456: invokeinterface #558, 2   // BitHeaderWrite.addFlags:(I)V   <- 4194304
                   466: invokeinterface #574, 2   // KahluaTable.save:(Ljava/nio/ByteBuffer;)V
IsoThumpable.load  425: invokeinterface #369, 2   // BitHeaderRead.hasFlags:(I)Z    <- 4194304
                   444: invokevirtual #15         // J2SEPlatform.newTable()
                   456: invokeinterface #402, 3   // KahluaTable.load:(Ljava/nio/ByteBuffer;I)V
```

So the same Lua line works on a player-built door as on a map door, and both
survive a save — through two different fields.

## 2. Telling the other players: `transmitModData()`

```
public void transmitModData();
   1: getfield      #127   // Field square:Lzombie/iso/IsoGridSquare;
   4: ifnonnull     8
   7: return                                    <- an object off its square does nothing
   8: getstatic     #489   // GameClient.client:Z
  25: invokestatic  #3501  // INetworkPacket.send(PacketType.ObjectModData, object)
  31: getstatic     #83    // GameServer.server:Z
  38: invokestatic  #3504  // GameServer.sendObjectModData:(Lzombie/iso/IsoObject;)V
  42: invokevirtual #736   // flagForHotSave:()V
  45: return
```

It has a server branch of its own — `GameServer.sendObjectModData` — so a write
made on the server reaches every client without anything else being called, which
is the point that matters for this mod (our writes happen on the server and most
of vanilla's happen on a client). `flagForHotSave()` at the end is what marks the
chunk to be written out.

## 3. Where Build 42 loads a mod's sandbox options

Not on `zombie.SandboxOptions`: a full `javap -p` of it has no mod-file loader at
all. It is `zombie.sandbox.CustomSandboxOptions.init()`, which walks every
installed mod (`ZomboidFileSystem.getModIDs()` ->
`ChooseGameInfo.getAvailableModDetails(String)` -> `ChooseGameInfo$Mod`) and tries
two paths per mod, taking whichever exists:

```
new File(mod.getVersionDir() + File.separator + File.separator + "media" + File.separator + "sandbox-options.txt")
new File(mod.getCommonDir()  + File.separator + File.separator + "media" + File.separator + "sandbox-options.txt")
```

(the `BootstrapMethods` recipe string is literally
`mediasandbox-options.txt`). What it reads is parsed
(`readFile`, `parse`) and each option handed to the real options object through
`SandboxOptions.newCustomOption(zombie.sandbox.CustomSandboxOption)` in
`initInstance(SandboxOptions)`.

`mod.getVersionDir()` is the versioned folder `ZomboidFileSystem` picked:
`getModVersionDirName(Path)` lists the mod root's subdirectories and takes the
highest one that parses as a game version and is not above the running one, which
for this mod is `42`. `getAllModFoldersAux` then registers both
`<mod>/common/media` and `<mod>/42/media` as content roots.

**So the file goes at `42/media/sandbox-options.txt`** — beside `42/media/lua`,
not at the mod root and not under `common/media` (either would work, and the
versioned one is where the two B42 mods on this machine put theirs:
`.../workshop/content/108600/3780639614/mods/PushVehicle/42/media/sandbox-options.txt`
and `.../3794455791/mods/TienCoolers/42/media/sandbox-options.txt`).

The shape is theirs, verbatim:

```
VERSION = 1,

option PushVehicle.AllowSidePushing
{
    type = boolean,
    default = true,
    page = PushVehicle,
    translation = PushVehicle_AllowSidePushing,
}
```

and the names a player reads are JSON now, not `Sandbox_EN.txt` — this install
has no `Sandbox_EN.txt` anywhere. Vanilla ships
`media/lua/shared/Translate/EN/Sandbox.json`, the two mods above ship one inside
their own `42/media/lua/shared/Translate/EN/`, and the keys are the old ones:
`Sandbox_<Page>`, `Sandbox_<Page>_<Option>`, `Sandbox_<Page>_<Option>_tooltip` —
the `translation =` value with `Sandbox_` in front of it.

Read back the way vanilla reads a grouped option
(`SandboxVars.Map and (SandboxVars.Map.AllowMiniMap == true)`,
`client/ISUI/Maps/ISMiniMap.lua:687`), because `SandboxVars` is a plain table and
a group nobody declared is simply not in it. It is the same guarded read this mod
already makes for `PhoneService` and `LootAbundance`.

## 4. The classes a module sits on

```
zombie.iso.objects.IsoDoor
  public boolean isLocked();          public boolean isLockedByKey();
  public void setLockedByKey(boolean);public boolean isExterior();
  public boolean IsOpen();            public void ToggleDoorSilent();
  public int getKeyId();
zombie.iso.objects.IsoWindow
  public boolean IsOpen();            public boolean isSmashed();
  public void ToggleWindow(zombie.characters.IsoGameCharacter);
zombie.iso.objects.IsoThumpable
  public boolean isDoor();            public boolean isLockedByPadlock();
  public boolean IsOpen();            public void ToggleDoorSilent();
zombie.iso.objects.IsoLightSwitch
  public boolean toggle();            public boolean isActivated();
  public boolean setActive(boolean);
```

`IsoWindow` has `IsOpen()` and `ToggleWindow(IsoGameCharacter)` and **no silent
toggle**: the only call that moves a sash needs a character standing at it. That
is the engine's own reason there is no window actuator in this mod, and why a
magnetic contact is all a window can carry (see DEVICES.md).

`IsoLightSwitch` does not override `getModData` — it inherits `IsoObject`'s, the
persisted one of proof 1.

## 5. The perk, and the experience

```
zombie.characters.IsoGameCharacter
  public int getPerkLevel(zombie.characters.skills.PerkFactory$Perk);
  public zombie.characters.IsoGameCharacter$XP getXp();
zombie.Lua.LuaManager$GlobalObject
  public void addXp(zombie.characters.IsoPlayer, zombie.characters.skills.PerkFactory$Perk, float);
```

`addXp(character, Perks.Electricity, n)` is a Java global exposed to Lua, and it
is the call vanilla's own electrical work makes:
`media/lua/shared/TimedActions/ISFixGenerator.lua:71`
`addXp(self.character, Perks.Electricity, 5)`. The other road,
`character:getXp():AddXP(Perks.Electricity, n)`, resolves to
`IsoGameCharacter$XP.AddXP(PerkFactory$Perk, float)` and is not what a generator
repair uses, so it is not what this uses either.

There is no `zombie.characters.skills.XPSystem` and no `zombie.characters.XP` in
this jar; `IsoGameCharacter$XP` is the class.

## 6. The vanilla action this one is cut from

`media/lua/shared/TimedActions/ISFixGenerator.lua` — electrical work on a world
object, whole:

```lua
function ISFixGenerator:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Low")
	self.character:reportEvent("EventLootItem")
	self.sound = self.character:playSound("GeneratorRepair")
end

function ISFixGenerator:complete()
	...
	addXp(self.character, Perks.Electricity, 5)
end

function ISFixGenerator:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return 150 - (self.character:getPerkLevel(Perks.Electricity) * 3)
end
```

So: `setActionAnim("Loot")` and the `LootPosition` variable, a duration that
comes down with the perk, and the experience awarded in `complete` and not in
`perform`. There is no screwdriver-specific animation in vanilla — generator
repair, the game's own electrical job, uses the generic Loot pose, which is also
the one this mod's other actions already use (`ISCeroSecToggleAction:start`).

## 7. Getting the survivor to the thing

`luautils.walkAdjWindowOrDoor(playerObj, square, item)` for a door or a window —
`media/lua/shared/luautils.lua:227`, and it is what the vanilla menu calls before
it opens a door (`client/ISUI/ISWorldObjectContextMenu.lua:2417-2422`,
`onOpenCloseDoor`) and before it unbarricades a window (`:2151-2158`). It answers
true when the walk was queued or the survivor is already there.

`luautils.walkAdj(playerObj, square)` — `luautils.lua:119` — for anything that is
not a door or a window, which is what a light switch is
(`onFixGenerator`, `ISWorldObjectContextMenu.lua:554-556`).

Vanilla's own classifier for the first case is
`ISWorldObjectContextMenu.isThumpDoor` (`:2176-2189`): `IsoThumpable` with
`isDoor()` or `isWindow()`, or `IsoWindow`, or `IsoDoor`, or `IsoWindowFrame`.

A greyed-out entry with its reason is `option.notAvailable = true` plus
`ISWorldObjectContextMenu.addToolTip()` with a `description`
(`ISWorldObjectContextMenu.lua:1303-1309`, the bulb that will not fit in the
bag) — the same three lines this mod's computer menu already writes.

`Events.OnFillWorldObjectContextMenu` is the door mods are meant to come in by:
`ISWorldObjectContextMenu.lua:213` fires it with the comment *"use the event (as
you would 'OnTick' etc) to add items to context menu without mod conflicts"*, and
several vanilla files listen to it themselves (`ISHutchMenu.lua:3` and `:115`,
`ISVehicleMenu.lua:21` and `:1741`).

## 8. What the recipes are cut from

`media/scripts/generated/recipes/recipes_traps.txt:3-26` — the electrical recipe
that makes a sensor part, whole:

```
    craftRecipe MakeRemoteControllerV1
    {
        timedAction = MakingElectrical,
        time = 50,
        NeedToBeLearn = true,
        SkillRequired = Electricity:2,
        Tags = AnySurfaceCraft,
        category = Electrical,
        AutoLearnAny = Electricity:8,
        xpAward = Electricity:6,
        inputs
        {
            item 1 [Base.Remote;Base.CordlessPhone;Base.Pager],
            item 1 tags[base:screwdriver] mode:keep,
            item 1 tags[base:pliers] mode:keep flags[MayDegradeLight],
            item 2 [Base.ElectronicsScrap],
            item 2 [Base.Glue],
        }
        outputs
        {
            item 1 Base.RemoteCraftedV1,
        }
    }
```

`AutoLearnAll` is the same key with every skill required instead of any one of
them (`recipes_tailoring_leatherAndHide.txt:1061`, `recipes_bone.txt:12`); with a
single skill named they are the same thing, and `All` is the one written here so
that a second skill added later tightens the gate rather than widening it.

The vanilla items used as inputs, each with the line its `item` block starts on
in `media/scripts/generated/items/`:

| item | where |
| --- | --- |
| `Base.ElectronicsScrap` | `normal.txt:4529` |
| `Base.ElectricWire` | `normal.txt:4518` |
| `Base.Wire` | `drainable.txt:531` |
| `Base.ScrapMetal` | `normal.txt:8451` |
| `Base.SmallSheetMetal` | `normal.txt:8475` |
| `Base.Aluminum` | `normal.txt:8487` |
| `Base.LightBulb` | `normal.txt:4654` |
| `Base.MotionSensor` | `normal.txt:4539` |
| `Base.Screwdriver` | `weapon.txt:18169` |

`Base.Electronics`, `Base.Magnet` and `Base.CopperWire` do **not** exist in B42
and are in none of these recipes.

### 8a. The name a player reads

A `craftRecipe` carries no display name of its own. The menu asks
`Translator.getRecipeName(name)`
(`media/lua/client/ISUI/ISInventoryPaneContextMenu.lua:1236-1238`), and that is a
lookup in one map with the **raw recipe name** as the key — no `Recipe_` prefix,
no module prefix:

```
zombie.core.Translator.getRecipeName(java.lang.String)
   0: getstatic  #101  // Field recipe:Ljava/util/Map;
   4: Map.get
  14: ifnull 24
  18: String.isEmpty
  21: ifeq 63
  61: aload_0       <- the KEY it was handed
  62: areturn
  63: aload_1       <- the translation
  64: areturn
```

Offsets 61-62 are the whole reason this matters: a miss, **or an empty string**,
returns the key itself and logs nothing, so the right-click menu prints
`DismantleCeroSecMotorCDPlayer` at the player and the game looks like it is
working. That is what shipped before the names were written.

The map is the one the file called `Recipes` fills. `Translator$1` is the
`BY_NAME` map and its body puts them together:

```
  24: aload_0
  25: ldc  #26   // String Recipes
  27: getstatic  #28  // Field zombie/core/Translator.recipe:Ljava/util/Map;
  30: put
  35: ldc  #31   // String RecipeGroups
  37: getstatic  #33  // Field zombie/core/Translator.recipeGroups:Ljava/util/Map;
```

and `Translator.lambda$loadFiles$1` calls `tryFillMapFromFile` and then
`tryFillMapFromMods` for every `BY_NAME` entry (offsets 20 and 26), which is how
a mod's own `Translate/<LANG>/Recipes.json` lands in the same map as vanilla's.
So the file is `42/media/lua/shared/Translate/<LANG>/Recipes.json` and the key is
the bare name, exactly as vanilla writes it:

```
    "CraftMakeshiftRadio": "Make Makeshift Radio",
    "DismantleElectronics": "Dismantle Simple Electronic Item",
    "DismantleMiscElectronics": "Dismantle Electronic Item",
```

`RecipeGroups.json` is a different map (`getRecipeGroupName`, the same
return-the-key shape) and vanilla's whole English file is one line,
`"RecipeGroup_OpenBox"`. Nothing this mod writes is a recipe group: `category =
Electrical` is the crafting tab, not a group, so there is no file to add.

Forty-seven of vanilla's recipe names begin `Dismantle` and not one contains
`Salvage`, so the two motor recipes are `Dismantle …` too.

### 8b. Why the motor is its own recipe and not an output of vanilla's

The question that keeps coming back: why not simply make `CeroSec.SmallMotor` a
second output of vanilla's own `DismantleMiscElectronics`, so that taking a CD
player apart the usual way pays the motor and this mod adds no menu entry at all?
Three things were looked at in the jar. None of them works.

**A second block with the same name is additive, and that is the problem.** It is
worth saying exactly, because "the mod replaces vanilla's block" is the usual
assumption and it is wrong here. `ScriptBucket.CreateFromTokenPP` at offsets
88-146: when `loadData` already holds the name, the existing script object is
kept and the new body is **appended** to `LoadData.scriptBodies`.
`ScriptBucket.LoadScripts` at offsets 157-218 then walks the bodies in order and
calls `Load` on the one object for each. Between bodies it calls `reset()` only
if the type carries `ScriptType$Flags.ResetExisting` (offsets 183-205) — and
`CraftRecipe` does carry it, by the default flag set every `ScriptType` with a
null `flags` field is given in the enum's static block (offsets 818-832, the set
built at 644-681). It costs nothing all the same:
`zombie.scripting.objects.BaseScriptObject.reset()` is `0: return`, and
`zombie.scripting.entity.components.crafting.CraftRecipe` does not override it.
So bodies blend. `CraftRecipe.LoadIO` only ever calls `outputs.add` and
`inputs.add` (offsets 474-479 and 332-337) — there is no `clear` anywhere in it.

A mod could therefore declare `module Base { craftRecipe DismantleMiscElectronics
{ outputs { item 1 CeroSec.SmallMotor, } } }` and the motor would be added to
vanilla's list. It would also be added for **every** input of that recipe: a TV
remote, a speaker and a home alarm all pay a motor. `DismantleElectronics` is
worse, because its input is a tag query (`tags[base:camera;base:digital;
base:miscelectronic;base:flashlight]`) and a digital watch would pay one too.

**The mapper can say "nothing", but it cannot be attached.** An `itemMapper` is
keyed by the OUTPUT and matched against the consumed inputs, and
`OutputMapper.getOutputItem` returns **null** when no entree matched and
`defaultOutputEntree` is null (offsets 209-213 falling to 272: `aconst_null;
areturn`) — so a mapper with no `default` really does yield no item for the
inputs it does not name. Every `default` vanilla writes is an item type; there is
no "nothing" token, and none is needed. But a mapper only sees the inputs that
were **registered** with it, and registration comes from the `mappers[...]` list
written on the input line itself — `InputScript`, offsets 1590-1602:
`CraftRecipe.getOrCreateOutputMapper(name)` then
`OutputMapper.registerInputScript(input)`. Inputs are add-only, so a second body
cannot put `mappers[ceroMotor]` on vanilla's existing input line; it can only add
a new input line, and that means the recipe demands a second item out of the
player's bag. There is no way to express it.

**There is no Lua seam at craft time either.** `OnCreate` is real and it is a
Lua-resolved call — `CraftRecipeData.initLuaFunctions` hands the script's string
to `LuaManager.getFunctionObject` (offset 46-53) and
`CraftRecipeData.luaCallOnCreate` calls it with the recipe data and the
character, which knows `getAllConsumedItems()`. But the string it resolves is
written in the script block (`OnCreate = RecipeCodeOnCreate.dismantleMiscElectronics`),
so pointing it somewhere else means overwriting a scalar key of vanilla's block —
the thing this section exists to refuse — and the target it names is a Java class
(`zombie/scripting/logic/RecipeCodeOnCreate.class`), not mod Lua. Nor is there an
event to listen for: `ISHandcraftAction:performRecipe`
(`media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua:221-249`) calls
`luaCallOnCreate` and nothing else — the file contains no `triggerEvent` at all,
and there is no `OnCraft` in any `LuaEventManager.AddEvent` in `media/lua`.

So: two recipes of our own, named, and vanilla's blocks untouched. What it costs
a player is one extra line in the Electrical tab beside vanilla's; what it buys
is that a hair dryer pays a motor and a TV remote does not, that any other mod
touching `DismantleMiscElectronics` does not collide with us, and that a patch to
that recipe from the game's own authors arrives intact instead of being blended
with a copy we took months earlier.

## 9. The loot lists

Checked by name against `media/lua/server/Items/ProceduralDistributions.lua`:

| list | line |
| --- | --- |
| `ElectronicStoreMisc` | 20306 |
| `ElectronicStoreLights` | 20241 |
| `ElectronicStoreComputers` | 20213 |
| `ElectricianTools` | 20505 |
| `CrateElectronics` | 14464 |
| `CrateTools` | 17718 |
| `GarageTools` | 23325 |
| `GarageMechanics` | 23173 |
| `ToolStoreTools` | 49335 |
| `MechanicTools` | 33912 |
| `ToolCabinetMechanics` | 48633 |
| `ToolFactoryTools` | 48759 |

There is **no** `HardwareStore*` and **no** `Shed*` list in Build 42 at all — the
hardware store's shelves are the `ToolStore*` and `Electrician*` ones, and a tool
shed's are `Crate*` and `Garage*`. A list named for a place that does not exist in
the game is a distribution nothing would ever be found in.

## 10. When the fixture leaves the world: the removal paths

A module lives in the fixture's modData (section 1), so the day the fixture leaves
the world the module leaves with it. `SCeroSecFixtures` hands it back as an item on
the square instead, off **one** hook — and this is the proof that one hook is
enough.

**The event fires from exactly two places in 42.20.4**, both of them Java, both of
them *before* the object comes off its square:

```
zombie.iso.IsoGridSquare.RemoveTileObject(zombie.iso.IsoObject, boolean)
     177: ldc_w  #2857   // String OnObjectAboutToBeRemoved
     180: aload_1
     181: invokestatic #1851  // LuaEventManager.triggerEvent:(Ljava/lang/String;Ljava/lang/Object;)V
     184: getfield #71 / 189: contains / 192: ifne 206
     195: new    #2859   // class java/lang/IllegalArgumentException
     199: ldc_w  #2861   // String OnObjectAboutToBeRemoved not allowed to remove the object
     239: invokevirtual #2869  // IsoObject.removeFromWorld:()V
     243: invokevirtual #2870  // IsoObject.removeFromSquare:()V

zombie.network.packets.RemoveItemFromSquarePacket.removeItemFromMap(UdpConnection,
                                                                   int, int, int, int)
     328: instanceof #131  // class IsoWorldInventoryObject   <- skipped for a dropped item
     336: ldc_w  #297    // String OnObjectAboutToBeRemoved
     341: invokestatic #149  // LuaEventManager.triggerEvent
     361: ldc_w  #305    // String OnObjectAboutToBeRemoved not allowed to remove the object
     401: invokevirtual #309  // IsoObject.removeFromWorld:()V
```

So the object is still on the square at the trigger, and a listener that removed
it would raise — which is why the drop writes modData and never touches the
square's object list.

**Both trigger sites are reachable on the server, and the dispatch between them is
`transmitRemoveItemFromSquare(IsoObject, boolean)`** — the call nearly every
vanilla removal path makes:

```
  17: getstatic #1775  // GameClient.client:Z
  44..85                // RemoveItemFromSquarePacket out, then falls through
  88: getstatic #157   // GameServer.server:Z
 189: invokestatic #2933  // GameServer.RemoveItemFromMap:(Lzombie/iso/IsoObject;)I
 194: invokevirtual #2825  // RemoveTileObject:(Lzombie/iso/IsoObject;Z)I
```

- on a **client**: the packet goes out *and* offset 194 removes it locally, so the
  client fires the event for its own screen;
- on a **server**: offset 189, and `GameServer.RemoveItemFromMap` broadcasts and
  then calls the static above itself (offsets 30-55: `INetworkPacket.sendToRelative`
  then `RemoveItemFromSquarePacket.removeItemFromMap(null, x, y, z, index)`);
- on **neither** — singleplayer — offset 194.

And the one-argument `RemoveTileObject(IsoObject)` sends a loaded chunk through
`IsoObjectUtils.safelyRemoveTileObjectFromSquare` (offsets 0-50 pick the boolean
from `square == null || !chunk.loaded || chunk.preventHotSave`), which comes back
to `RemoveTileObject(obj, false)` once per part of a multi-tile object (offsets
84-89 and 136-142). Either way the trigger happens once per object.

**A client's packet reaches the server's handler**: `processServer` calls the same
static (offsets 0-17) and then `sendToRelativeClients`, so a survivor picking a
television up on a dedicated server fires the event **on the server**, which is the
side this mod writes modData on.

### The paths, and what each one really calls

| what happens | what removes the object | fires on the server |
| --- | --- | --- |
| a movable picked up (television, radio set, oven, washer, lamp) | `ISMoveableSpriteProps:pickUpMoveableInternal:1406-1407` — `triggerEvent("OnObjectAboutToBeRemoved", _object)` *itself* ("Hack for RainCollectorBarrel, Trap, etc") and then `transmitRemoveItemFromSquare` | yes |
| a window picked up | the same function, `:1384-1386` — `transmitRemoveItemFromSquare` and **no** Lua trigger | yes, the Java one |
| the same pickup **smashing** the window | `:1352-1354` sets `windowGotSmashed`, and the branch at `:1385` is then skipped: the object **stays** | **no, and it must not** |
| a map door destroyed (zombie, sledgehammer) | `IsoDoor.destroy()` — `destroyed = true` and `transmitRemoveItemFromSquare` at offsets 227-240; the garage-door leaf takes the same pair at 23-36 | yes |
| a player-built door or wall destroyed | `IsoThumpable.destroy()` — `OnDestroyIsoThumpable` at 120-125, `transmitRemoveItemFromSquare` at 146-154 | yes |
| sledgehammer, from the menu | `ISDestroyStuffAction:complete:276-280` — `sledgeDestroy(obj)` on a client, `transmitRemoveItemFromSquare` otherwise | yes |
| dismantled / "Disassemble" | `ISMoveableSpriteProps:scrapObjectInternal:3517-3519` — transmit on a client, `transmitRemoveItemFromSquareOnClients` on a server, and `square:RemoveTileObject(object)` on **both** | yes |
| a curtain taken down | `ISRemoveSheetAction` → `IsoCurtain.removeSheet(IsoGameCharacter)`, offset 5 | yes |
| a generator picked up | `ISTakeGenerator:complete:53` → `IsoGenerator.remove()`, offsets 8-16 | yes |
| a chunk unloading | nothing: `IsoChunk` never calls `RemoveTileObject`, it fires `ReuseGridsquare` (`IsoChunk.doReuseGridsquares:3044`) | **no, and it must not** |

`OnDestroyIsoThumpable` is **not** needed beside it. Vanilla's own trap system says
why in a comment: *"This is called \*before\* self:OnDestroyIsoThumpable() due to
ISBuildingObject.onDestroy() removing the object"* (`STrapSystem.lua:106-110`) — so
`OnObjectAboutToBeRemoved` is the earlier of the two on that path, and
`IsoThumpable.destroy` fires it after its own event anyway (offsets 120-154).

### Fired twice for one gesture, in singleplayer

`pickUpMoveableInternal` triggers the event in Lua at `:1406` and then calls
`transmitRemoveItemFromSquare` at `:1407`, whose singleplayer branch (offset 194)
triggers it again in Java. So a survivor picking a television up on his own box
fires it **twice** for one pickup, which is why the drop is paid per *key* and not
per event: `CeroSecModules.setOn(object, id, false)` clears the key as each module
is handed over, and the second firing reads a bare fixture.

### Nothing of ours rides along in the item

A pickup that keeps identity does **not** carry our modData into the moveable item.
`pickUpMoveableInternal` copies exactly one key out of an object's modData —

```
1298:  if _object:hasModData() and _object:getModData().movableData then
1299:      item:getModData().movableData = copyTable(_object:getModData().movableData)
```

— plus `<containerType>_customContainerName` and `itemCondition` (`:1300-1312`), and
`IsoThumpable` goes through `saveThumpableParameters` instead (`:1204`). Placement
copies the item's whole modData back onto the object, but only when there is **no**
`movableData` on it (`:2273-2275`). `GameEntityFactory.TransferComponents(_object,
item)` at `:1280` moves components, not modData.

So a ride-along was possible only by writing our key into somebody else's
`movableData` table, which is the second truth this mod refuses to keep
(`CeroSecModules`, head). The module comes off instead — which is also the honest
answer: a television carried out of the building did not take the building's wiring
with it.

### Putting the item on the floor

`IsoGridSquare.AddWorldInventoryItem(String, float, float, float)` is the one call,
and it does the two things `uninstallmodule` needs two for:

```
AddWorldInventoryItem(String, float, float, float)      -> (String,F,F,F,true)
AddWorldInventoryItem(String, float, float, float, boolean) -> (...,true,false)
AddWorldInventoryItem(String, float, float, float, boolean, boolean)
       1: invokestatic  #2968  // InventoryItemFactory.CreateItem:(Ljava/lang/String;)
       6: ifnonnull 13 / 11: aconst_null / 12: areturn   <- null for a type it cannot make
      13: new #1981             // class IsoWorldInventoryObject
      66..85                    // onto square.objects AND square.worldObjects
     105: getstatic #157        // GameServer.server:Z
     118: invokevirtual #2998   // IsoWorldInventoryObject.transmitCompleteItemToClients:()V
```

It makes the item and, **on a server, transmits it by itself** — so there is no
`sendAddItemToContainer` beside it the way there is in `uninstallmodule`. The
`null` at offset 12 is why the item is made *before* the key is cleared: a type the
game cannot make must not cost a survivor the box.

The coordinates are `0, 0, 0`, which is where a door drops its own parts:
`IsoDoor.destroy` calls `AddWorldInventoryItem` with `fconst_0` three times for the
planks (offsets 120-133), the doorknob (157-169), the hinges (186-199) and the
sheet (213-226). Vanilla's server Lua uses the same call the same way
(`ISBuildingObject.lua:58`, `SCampfireGlobalObject.lua:143`,
`STrapGlobalObject.lua:603`).
