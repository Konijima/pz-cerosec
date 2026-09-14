# Tenancies inside one building

Read against `projectzomboid.jar` **42.20.4**, the jar installed at the time.

Why this note exists: a premises was a named `ZombiesType` zone or else a whole
`BuildingDef`, and the shipped map's malls have no zones in them. So every shop in
a mall shared one profile, one staff, one telephone line and one length of coax —
the music store's computer and the dentist's computer were the same machine with
the same password. Splitting a building into tenancies means keying a premises on
a `RoomDef`, and everything below is what had to be proved before that was
possible: what geometry a `RoomDef` really exposes, whether its id can be a
persistence key, how a whole region's buildings are enumerated, and — because a
rule about the map has to be measured against the map — what any candidate rule
does to all 9546 buildings of the shipped county.

## What a `RoomDef` exposes

```
javap -p -cp projectzomboid.jar zombie.iso.RoomDef
```

```
public java.lang.String name;
public int level;
public zombie.iso.BuildingDef building;
public long id;
public final java.util.ArrayList<zombie.iso.RoomDef$RoomRect> rects;
public int x; public int y; public int x2; public int y2; public int area;
public long getID();
public boolean isAdjacent(zombie.iso.RoomDef);
public boolean isAdjacent(int, int, int, int);
public zombie.iso.BuildingDef getBuilding();
public java.lang.String getName();
public java.util.ArrayList<zombie.iso.RoomDef$RoomRect> getRects();
public int getY(); public int getX(); public int getX2(); public int getY2();
public int getW(); public int getH(); public int getZ();
public int getArea();
public boolean isEmptyOutside();
```

`getW`/`getH`/`getZ`/`getArea` are plain field reads, which settles what the four
corners mean:

```
public int getW();   0: getfield x2   4: getfield x   8: isub   9: ireturn
public int getH();   0: getfield y2   4: getfield y   8: isub   9: ireturn
public int getZ();   0: getfield level (an int, the floor)      4: ireturn
public int getArea();0: getfield area
```

So `x2`/`y2` are **exclusive**, exactly as `BuildingDef`'s are, and `getZ()` is the
level and not a world z. `CalculateBounds()` is what fills them, and it is the
bounding box of `rects` with `area` the **sum of the rects** rather than the box:

```
  0: x  = 10000000      12: x2 = -1000000     24: area = 0
  (per rect) x = min(x, r.x); y = min(y, r.y);
             x2 = max(x2, r.x + r.w); y2 = max(y2, r.y + r.h);
             area += r.w * r.h
```

`isEmptyOutside()` is `"emptyoutside".equalsIgnoreCase(name)`, and the map loader
puts such a room on `BuildingDef.emptyoutside` instead of `BuildingDef.rooms` — so
`getRooms()` never hands one over.

`isAdjacent(RoomDef other)` walks **the other room's rects**, grows each by one
tile on every side and asks `this.intersects(x-1, y-1, w+2, h+2)`:

```
25: this  26: rect  27: RoomRect.getX  30: iconst_1  31: isub
32: rect  33: RoomRect.getY  36: iconst_1  37: isub
38: rect  39: getW  42: iconst_2  43: iadd
44: rect  45: getH  48: iconst_2  49: iadd
50: invokevirtual intersects:(IIII)Z
```

It takes **no level**: two rooms one above the other are "adjacent" to it. Any
rule that uses it has to compare `getZ()` itself.

## `RoomDef.getID()` is NOT a persistence key

This is the one that changed the design. The id looks stable — it is a `long`, it
is in the map data, and `getRoomDefByID` reads it back — and it is not.

`getID()` returns the field verbatim, and the field is written only in the
constructor:

```
public long getID();  0: getfield id:J  4: lreturn

public RoomDef(long, String);
  ...  70: aload_0  71: lload_1  72: putfield id:J
       75: aload_0  76: aload_3  77: putfield name:Ljava/lang/String;
```

So the question is who constructs one, and with what. Three sites, and none of
them passes anything a save could rely on.

**1. The lot header, at world start** —
`IsoMetaGrid$MetaGridLoaderThread` reads each `.lotheader` and builds every room
with `id = 0` (offset 508-525, `lconst_0`), then **overwrites** the id when the
room joins the cell:

```
IsoMetaGrid$MetaGridLoaderThread, and NewMapBinaryFile
  .addRoomsAndBuildingsToMetaGrid at offsets 253-276:
    253: room
    255: cell  256: IsoMetaCell.getX
    259: cell  260: IsoMetaCell.getY
    263: cell  264: getfield IsoMetaCell.roomList
    267: ArrayList.size            <-- a RUNNING COUNTER
    270: iload 6  272: iadd        <-- plus this room's index in the file
    273: invokestatic zombie/iso/RoomID.makeID:(III)J
    276: putfield RoomDef.id:J
```

`RoomID.makeID(cellX, cellY, index)` is `((cellY << 16 | cellX) << 32) | index`
(`javap zombie.iso.RoomID`), so the low 32 bits **are** that counter. The counter
is how many rooms are already registered in that cell, which is a fact about
**which lot headers were loaded into the cell first** — the base map plus whatever
map mods touch it, in mod-load order. Change the mod list and the same room gets
another id.

**2. A basement, during play.** `NewMapBinaryFile.SpawnBasement(String,int,int)`
is a runtime call — it reads `IsoPlayer.getInstance()` at offset 25 — and
`addBasementRoomsToMetaGrid` builds the basement's rooms with

```
131: new RoomDef
150: cell  153: getfield IsoMetaCell.rooms  156: HashMap.size   <-- at THIS instant
156: invokestatic zombie/iso/RoomID.makeID:(III)J
164: invokespecial RoomDef."<init>":(JLjava/lang/String;)V
```

and then **adds them to the building**:

```
272: building  274: getfield BuildingDef.rooms  279: ArrayList.add
```

So the counter advances as the game is played, and `BuildingDef.getRooms()` grows
at runtime. Two things follow, and both are written into the rule: a room id can
differ between sessions, and a building's room list is not fixed for the life of a
save.

**The key is therefore `(building corner, room corner, level)`** — three facts
about where the room is drawn on the map, which no load order can move. Written as
`CeroSecOS.roomKey`, in `buildingKey`'s own arithmetic, beside it.

## Enumerating a region's buildings, bounded

The telephone book lists the tenants of a region, so it needs the buildings of a
region and not one building at a tile. `IsoMetaGrid` has both:

```
public final java.util.ArrayList<zombie.iso.BuildingDef> buildings;
public java.util.ArrayList<zombie.iso.BuildingDef> getBuildings();
public void getBuildingsIntersecting(int, int, int, int,
        java.util.ArrayList<zombie.iso.BuildingDef>);
```

`getBuildings()` is every building in Knox County and is not what a book wants.
`getBuildingsIntersecting` walks only the **cells the rectangle touches** and asks
each one:

```
  0: iload_2  1: sipush 256  4: idiv  5: istore 6      <-- y / 256
 22: iload_1  23: sipush 256  26: idiv  27: istore 7   <-- x / 256
 44..77: clamped to minX/maxX/minY/maxY
 95: invokevirtual getCell:(II)Lzombie/iso/IsoMetaCell;
109: (delegates to the cell)
```

which is the same shape as `getZonesIntersecting`, already used by the book. A
`CeroSecOS.PHONE_REGION` of 1024 tiles is 4 by 4 cells, so one book costs sixteen
cell visits and nothing more.

`BuildingDef.getRooms()` and `RoomDef.getName()` were already proved for the
profile rule (see the head of `CeroSecNet.premisesRooms`).
`IsoGridSquare.getRoomDef()` is `getRoom()` and then `IsoRoom.getRoomDef()`, and
answers null without a room:

```
public zombie.iso.RoomDef getRoomDef();
  0: invokevirtual getRoom:()Lzombie/iso/areas/IsoRoom;
  5: ifnonnull 13   9: aconst_null  10: goto 17
 13: invokevirtual zombie/iso/areas/IsoRoom.getRoomDef
```

## What the map says, counted

A rule about the map is worth exactly what it does to the map, so the shipped
county was parsed and every candidate was measured on all of it. The `.lotheader`
format is the loader's own, read off the bytecode above: `LOTH`, an int version,
an int count and that many newline-terminated tile names, a byte for version 0,
int width and height (8 by 8), the levels, then `nRooms` records of
`name / level / nRects / (x, y, w, h)... / nObjects / (id, x, y)...`, then
`nBuildings` records of `nRooms` and that many room indices. Every int is
little-endian (`IsoLot.readInt` is four `read()`s shifted 0, 8, 16, 24) and every
string is a line (`BufferedRandomAccessFile.getNextLine`, terminated by byte 10).

**9546 buildings**, and this is what each rule did to them.

| rule | buildings it calls multi-tenant | why it is wrong |
| --- | --- | --- |
| two or more rooms whose name maps to a business word | 362 | `office, officestorage` (24 buildings), `office, warehouse` (16), `gunstore, gunstorestorage` (6), `bank, bankstorage, office` (5) — a single business with a back office and a stock room, split into two or three premises. A regression for hundreds of ordinary buildings. |
| ... grouped by *profile* instead of name | — | merges the mall: `musicstore`, `clothesstore` and `toolstore` are all the `store` profile, so the whole mall is one tenant again. The very thing being fixed. |
| ... every business room its own tenancy | 240 | one shop is often several `RoomDef`s: a furniture shop in 8 rooms, a gas station's 4 `gasstore` kiosks, a farm tool shed of 2 `toolstore` rooms. |
| **shopfront rooms, same name and touching, grouped** | 159 | the gas stations are still 4 or 8 premises: their `gasstore` rooms are the 1-tile pump islands and no two touch. |
| **... and a room of one tile is not a shop** | **143** | shipped |

The shipped rule's own numbers, which is the claim a reader can check:

| building | size | tenancies |
| --- | --- | --- |
| 13515,1261 | 159x145 | 45 — 25 trades, including 7 separate `clothesstore` |
| 13868,5745 | 133x174 | 40 — 21 trades, 9 separate `clothesstore` |
| 12696,1511 | 46x71 | 12 |
| 12809,1294 | 83x46 | 11 — `bookstore`, `cafe`x2, `clothesstore`x2, `conveniencestore`x2, **`dentist`**x2, `giftstore`, `pharmacy`, with three floors of `office` above it |
| 12612,1893 | 12x10 | 2 — a `cafe` and a `giftstore`, which is two shops in one strip |
| 10860,10032 | 12x16 | 2 — a `dentist` and an `optometrist` |
| a house, a school, a police station, a hospital, a gas station | — | 0 or 1, so the building, exactly as before |

The author's own two examples are in the shipped data: `musicstore` (11 rooms in
the county) and `dentist` (15). They are not in one building — the report's mall is
whichever one he was standing in — and both come out as tenancies.

Three things the counting settled that no amount of reading would have:

* **`office` cannot be a tenancy word.** 3977 rooms in the county are called
  `office`, and nearly every business has one. An office is somebody's back room
  unless it is the whole premises, which is what the building fallback already
  says.
* **`classroom`, `prisoncells`, `hospitalroom`, `motelroom` cannot be either.** A
  school has 20 classrooms and a prison has 540 cells in the county; a tenancy
  word there would shatter every school and every prison into premises with a
  telephone line each.
* **A `storage` is never a second shop.** `gunstorestorage`, `clothesstorage`,
  `bookstorage`, `pharmacystorage` all carry a shopfront word and all of them are
  the back of the shop next door.

Which is why the tenancy words are a short, ordered, *deliberate* list read off
this map (`CeroSecContent.TENANCY_WORDS` and `TENANCY_TRADES`) and not
"`PREMISES_WORDS` minus the residential ones". The bench holds every word on the
list to being a room name the shipped map really has.

## The cost, measured

The rule walks a building's rooms, and a mall has a lot of them. Measured on the
biggest one the county has -- 13515,1261, 498 rooms, 70 of them shopfronts --
`CeroSecNet.premisesOfSquare` cost **2.5 ms a call** under `lua5.1`, and Kahlua is
slower than that.

That is nothing for switching a machine on, which happens once. It is a great deal
for the caller nobody thinks of: `Events.OnFillContainer` fires for **every
container** as loot is generated, and the papers in the drawers ask the rule on each
one -- so a mall's chunk load would have spent most of a second in here, twice over,
because the profile asks again for the tenancy's own room names.

So the answer is cached per building for the session (`CeroSecNet.tenanciesOf`), which
takes it to **0.010 ms a call** -- a chunk load of three hundred containers goes from
about 750 ms to 3 ms. It is derived from the map and never saved.

**What invalidates it**, and it is not "nothing": `BuildingDef.rooms` grows during
play, by the `SpawnBasement` path above. So the entry carries the room count it was
built from and is thrown away when the building's own count has moved.
`BuildingDef.getRoomsNumber()` is one `ArrayList.size()`, which is what makes that
check cheap enough to do on every call:

```
public int getRoomsNumber();
  0: getfield rooms:Ljava/util/ArrayList;
  4: invokevirtual java/util/ArrayList.size:()I
```

Keyed on the building's **corner**. The def object would in fact do --
`IsoBuilding.getDef()` is `getfield def` and `IsoMetaGrid.getBuildingAt` returns the
instance out of its own `buildings` list, so one building really is one object -- and
the corner is used anyway because it is the identity this whole rung already runs on,
and because a table key that is a Java object across the Kahlua boundary is an
identity nobody here has proved.

## What is still approximate, said out loud

* **A tenancy is grouped on the bounding box, not the rects.** Two rooms are one
  shop when their boxes share a wall of a tile or more on the same level. Measured
  against the county it groups identically to `RoomDef.isAdjacent`'s rect walk
  (159 multi-tenant buildings either way, 45 and 40 tenancies in the two big
  malls against 45 and 41), and it costs four getters instead of a walk of two
  rect lists.
* **A wall two tiles thick splits a suite.** The mall at 12809,1294 has four
  `dentist` rooms in two groups, because a wall at y=1300 leaves a one-tile gap
  the touch test does not cross. That is one dentist on two telephone lines rather
  than thirty shops on one, and both halves answer `clinic`.
* **A shop with a mezzanine is two tenancies**, because the grouping is per level
  (`cafe` at 12858,1329 on levels 0 and 1).
* **A basement added during play can add a tenancy** to a building, by the
  `SpawnBasement` path above. It cannot move an existing one: the key is the
  room's own corner, so what is already keyed stays keyed.
