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
