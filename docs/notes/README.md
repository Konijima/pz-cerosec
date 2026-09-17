# Engineering notes

These are **proofs**, not design documents. Each one exists because a rule in the
code would otherwise have to be taken on faith, and a rule taken on faith in this
codebase has already cost a wrong behaviour once. They are written so that a
reader can check the claim instead of believing it: the class, the method, the
`javap` line, the bytecode offset, and the vanilla Lua file and line beside it.

They are kept as history as much as as reference. A note says what was true of the
jar it was read against, with the build number at the top; if the game changes
under it, the fix is to re-read the jar and add what is now true, never to quietly
edit the note into agreement.

| Note | What it proves |
| --- | --- |
| [actuators.md](actuators.md) | Which vanilla objects the **server** can read and drive without a character, and which setter broadcasts and which does not: curtains toggle and sync themselves, a coffee machine is an `IsoStove`, a television's `DeviceData` transmitter has a client branch only. Plus what a five-second `sleep` daemon costs, and the three side effects that keep a window sash out. |
| [modules-proofs.md](modules-proofs.md) | Every engine call the hardware modules make, and, offset by offset in `IsoObject.save`/`load`, that a module written into an object's modData is really saved with the chunk, and that the cable's list of tables goes the same way, on disk and down the wire. |
| [picking.md](picking.md) | What the game's right-click actually hands a context menu: the whole pick pipeline through `UIManager.update`, `IsoObjectPicker` and `FBORenderObjectPicker`, and the two real defects a guess about it was hiding. |
| [tenancies.md](tenancies.md) | What geometry a `RoomDef` really exposes, why `RoomDef.getID()` cannot be a persistence key (the low 32 bits are a per-cell load counter, and a basement spawned in play advances it), how a region's buildings are enumerated for the cost of sixteen cells, and what five candidate "which rooms are separate shops" rules each did to all 9546 buildings of the shipped county. |
| [workshop-study.md](workshop-study.md) | How the most subscribed Project Zomboid Workshop pages are built, counted from the raw HTML of their descriptions, and Steam's own rules for images in one. |

The command, for a note of your own:

```
javap -p -c -cp <path to>/projectzomboid.jar zombie.iso.IsoObject
```

Read it against the jar that is **installed right now**. Any decompiled dump in
circulation is older than the jar and has been wrong here; it is not cited in
these notes and should not be cited in a new one.
