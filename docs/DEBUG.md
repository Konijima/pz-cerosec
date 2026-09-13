# CeroSec — The debug window

What the mod is actually doing, on one screen: every computer the server holds,
the selected machine's filesystem and its `/dev`, the wire, the scheduler, and
the mod's own log. A developer's tool and never a player's.

See also: [PROTOCOL.md](PROTOCOL.md) for the wire the terminal runs on, which
this window borrows; [ARCHITECTURE.md](ARCHITECTURE.md) for what the server
holds and why an unloaded chunk changes nothing about it;
[TESTING.md](TESTING.md) for the two suites that prove this, and
[PARCOURS-TEST.md](PARCOURS-TEST.md#x-la-fenêtre-de-débogage-palier-debug) for
the in-game walk.

## The two flags, and the one before release

`CeroSec.DEV_DEBUG_MENU` (`42/media/lua/shared/CeroSec/CeroSecDefs.lua`) is
`true` and **has to be set to `false` before the Workshop release**, exactly like
`CeroSec.DEV_MANUAL_MENU` beside it. It is a plain constant in the shared defs and
not a sandbox option, for the reason the manual flag is one: an option is
something a server owner turns on, and this is not for them.

What answers the question is `CeroSec.debugAllowed()`, and it is already written
the way the release needs it:

    the flag, OR the game's own debug mode

The second half is `isDebugEnabled()` — `zombie.Lua.LuaManager$GlobalObject`,
javap: `public static boolean isDebugEnabled();` — which is what vanilla's own
debug UIs are behind. So setting the flag to `false` is the whole of the release
change: the window stays, and is offered only to somebody who started the game
with `-debug`.

Both ends ask that question — the menu that offers the window and the two server
commands that answer it — because a client is not to be trusted about whether it
was allowed to ask.

**What the release gating still needs, and deliberately is not wired yet.** On a
dedicated server, debug mode is not an access level: a player who launched his own
client with `-debug` would pass `isDebugEnabled()` there. The check that belongs
beside it is the one vanilla puts in front of its own admin menu:

    AdminContextMenu.lua:23
    if not (isClient() and (isAdmin() or getAccessLevel() == "moderator")) then return true end

Both are globals on the same class (javap: `public static java.lang.String
getAccessLevel();`, `public static boolean isAccessLevel(java.lang.String);`).
Adding it is one line in `CeroSec.debugAllowed()`, and it is not in this wave
because nothing in this wave can be tested against a real server.

## The door

A **CeroSec (dev)** submenu, last on a computer's right-click menu, holding the
three manual volumes and then **Debug window**. One submenu for the mod's two
testing doors rather than one each, and it is there when EITHER flag is on, so
turning one off leaves the other's entries where they were.

The computer that was right-clicked is the machine the window opens **selected**,
because the survivor asking about a computer is standing at one.

## The window

`42/media/lua/client/CeroSec/CeroSecDebugUI.lua`. An `ISCollapsableWindow` with an
`ISTabPanel` in it, an `ISPanel` per tab as the tab's view, and an
`ISScrollingListBox` with columns inside each view — which is
`ISEntitiesDebugWindow`'s own shape
(`media/lua/client/DebugUIs/DebugMenu/Entity/ISEntitiesDebugWindow.lua:46-62`)
down to the ten pixels of border spacing. The list box's own palette and
`UIFont.Small`, and nothing of the mod's: it is a tool and it sits among vanilla's
tools, not among the phosphor screens.

### The layout, and why the list is not the view

A list box with columns draws its header row **above its own top edge**, at
`0 - self.itemheight` (`ISScrollingListBox.lua:553-562`), and `ISTabPanel:addView`
puts a view at `self.tabHeight` (`:493`). So a list that IS the view has nowhere to
draw its headers but on the tab strip — which is what shipped: `ess`, `tel`,
`call`, `jobs`, `eyes` showing through between the tab labels.

So each tab's view is an `ISPanel` at the top of the tab panel and the **list sits
one header row down inside it**, which is what vanilla's own column list does
(`ISItemsListTable.lua:76` puts the list at `BUTTON_HGT` and `:79` sets its
`itemheight` to the same number; the extra pixel here is the list's own top border,
`:486-491`).

Every number comes out of one `layout()`, and `applyLayout()` is what both
`createChildren` and `onResize` call — because two copies of this arithmetic that
disagreed is how it went wrong. The bands, top to bottom: title bar, tab strip,
header row, rows, button row, detail block. `tests/debug_ui_test.lua` asserts in
pixels that none of them reaches into the next, before and after a resize.

### The columns

Measured, never a table of constants. Each column is as wide as the **wider of its
own header and the widest cell of the rows on the glass**, plus the ten pixels the
list box itself draws header names at and a gap before the next rule; nothing is
narrower than four characters; and the last column absorbs what is left. When the
natural widths do not fit, every column gives up the same fraction of what it has
above the floor and the cells that no longer fit are cut with the mod's own `~` —
cut, and never drawn over the neighbour, which is what `call` on top of `jobs` was.

Widths are measured with the **advance** of a string and not with
`MeasureStringX` alone, through the same `"M"` sentinel the terminal uses
(`CeroSecTerminal.lua:1416-1419`, and the note at `:48-66` for why the subtraction
is exact): `MeasureStringX` answers the last glyph's ink where the pen moves by its
advance.

Resizable, one instance at a time (a second opening closes the first), and it
**remembers nothing** between sessions — not its position, not the tab that was in
front, not the machine that was selected. A debug window is opened to answer a
question and shut.

It refreshes itself every two seconds while it is open, on
`Events.OnTickEvenPaused` gated on `getTimestampMs()` — the gate vanilla's own
`forageServer` uses, and `OnTickEvenPaused` rather than `OnTick` because a debug
window is a thing somebody opens with the game paused. **The handler comes off on
close**; `tests/debug_ui_test.lua` fails if it stays.

It works nothing out. Every row on it is a row the server built, and the only two
things the window decides for itself are which tab is in front and which machine
is selected, because those are facts about a window.

## The tabs

1. **Machines** — every machine the server holds, loaded chunk or not. Columns:
   `x,y,z`, `facing`, `power`, `chunk`, `wire`, `host`, `address`, `tel`, `call`,
   `jobs`, `windows` — plain words, because a header nobody can read is a column
   nobody can read. A machine whose chunk is away reads `-` under **wire** and not
   `no`: `hasPower` is asked of a SQUARE, and no square means there was nobody to
   ask — the distinction a sweep once got wrong and switched off every computer
   behind a walking survivor.

   **The filter, and what "every machine the server holds" really means.** It is
   not "every computer that has ever been switched on": the engine makes a global
   object for every valid iso object of every square a chunk brings in
   (`SGlobalObjectSystem:loadIsoObject`,
   `media/lua/server/Map/SGlobalObjectSystem.lua:133-146`), so a save an hour old
   holds a machine for **every computer sprite the survivor has walked past** —
   forty-four of them, dark, with nothing in any column but their position. So the
   list shows the **used** ones by default: switched on, or carrying a disk of
   their own (`self.os` stays nil until a machine is first used). The server puts
   the flag on the row (`SCeroSecDebug.isUsed`), the button under the list toggles
   **Show all machines / Show used only**, and the line under the list says
   `showing N of M` and which way the filter is set. The toggle spends no round
   trip: the rows are already in hand.

   Clicking a row keeps the cursor on **that machine** across every refresh, by its
   coordinates and never by its row number.

   Clicking a row selects that machine, which is the machine the Files, Devices
   and Scheduler tabs are about. Under the list is that machine's own detail: its
   sprite, its own object version (`obj v`), the **shape its state is in** (`os v`,
   `CeroSecOS.STATE_VERSION` — what the migration chain walked it up to) beside its
   `sysv` (the contents `upgradeSystem` topped it up to), whether the system passes
   `CeroSecOS.systemOk`, and its console — who is logged in, where, what it is
   waiting for, how many lines are on it, and whether the glass is showing a
   session on another machine.

   And then **where it stands**, which is three facts about a PLACE and not about
   a computer:

   - the building's footprint off its `BuildingDef` — the corner, the far corner,
     the size, the area and the room count — or `outdoors` for a machine in no map
     building, which is what a player-built base is. The def's corners and not the
     `IsoBuilding`'s id, for the reason `CeroSecNet.buildingOf` gives: the id is
     handed out by a counter at load time and is a different number next session.
   - the room, by its `RoomDef`'s name (the name the map was drawn with; the
     `IsoRoom`'s own `getName` is asked only when there is no def), or `none`.
   - every zone the square is inside, one line each, capped at 16: type, name (or
     `-`), position, `w x h`, the bounding box `w*h`, and `getTotalArea()`.

   Both areas, deliberately. `w x h` is the bounding box; `getTotalArea()` is what
   the game actually computes, and for a polygon or a polyline zone the two are
   different numbers. Telling them apart is the whole point of standing in a mall
   and asking which named zone is smaller than the building around it — which is
   what the telephone wave's rules are going to be written against.

   All of it is asked of the WORLD, so a machine whose chunk is away answers
   `premises: no square (the chunk is away)` and claims nothing else — the same
   rule `/dev` and the power check wear, and for the same reason: there is nobody
   to ask.

   The calls, all javap'd on projectzomboid.jar (42.20.4) and used the way
   vanilla's own Lua uses them:

       zombie.iso.IsoGridSquare    getBuilding() -> IsoBuilding, getRoom() -> IsoRoom
       zombie.iso.areas.IsoBuilding getDef() -> BuildingDef
       zombie.iso.BuildingDef       getX() getY() getX2() getY2() getArea()
                                    getRoomsNumber()   (all int)
       zombie.iso.areas.IsoRoom     getName() -> String, getRoomDef() -> RoomDef
       zombie.iso.RoomDef           getName() -> String
       zombie.iso.IsoWorld          getMetaGrid() -> IsoMetaGrid
       zombie.iso.IsoMetaGrid       getZonesAt(int, int, int) -> ArrayList<Zone>
       zombie.iso.zones.Zone        getName() getType() -> String
                                    getX() getY() getZ() getWidth() getHeight() -> int
                                    getTotalArea() -> float

   `getZonesAt` answers an `ArrayList`, walked `0..size()-1` exactly as vanilla
   walks it in `media/lua/client/ISUI/AdminPanel/LootZed/SpawnRateChecker.lua:70-72`.
   `Zone` also carries the same seven as public fields (`name, type, x, y, z, w,
   h`); the getters are read because those are what vanilla's own Lua reads.

2. **Files** — the selected machine's tree, depth first, in the order `ls` prints
   each directory: path, type, mode as `ls -l` writes it, owner, size, mtime, and
   for a directory the nodes under it. Capped at 512 rows. Under it, the disk's own
   ceilings read off the functions that enforce them (`CeroSecOS.usage`,
   `exemptUsage`) — never counted here, because a debug window that added its own
   bytes up would be a second `df`.

   **Dump state** prints the whole state table to the game log through `print`, in
   bounded chunks (400 lines and one saying where it was cut). It is printed
   SERVER-side: in singleplayer that is the same console, and on a dedicated
   server it is the server's log, which is where something that size belongs.

3. **Devices** — `/dev` as the server sees it, through
   `CeroSecDevices.snapshot()`, which is the very call `envFor` makes to build
   what the engine is handed. Name, kind, room, side, mode, the offset the engine
   prints, the absolute square, the **handle** a highlight would carry, what the
   device reads, and whether its object is still there or the number is spent on
   something that has gone.

   The handle is `CeroSecDevices.handleOf()`: a sprite name for a fixture, the
   item's full type for a dropped head (a world item is drawn from a model and has
   no sprite name at all), and nothing for a light — a light answers "which one am
   I" by blinking, where everybody in the room can see it, so nothing about it is
   ever addressed to one screen. Under the list, the sampling book's record for
   each sensor in reach.

4. **Network** — five sections in one list, each row named by what it is in its
   first cell. `eth`: one segment per building, its members and their addresses.
   `tel`: one line per building and whether it is busy, plus the exchange, the grid
   and the phone service. `radio`: each machine's callsign and what its set is
   doing. `pty`: every session that is up, where it came from, which link it came
   over, how many hops out it is and how old it is. `evt`: the last fifty things
   the wire was asked and what it answered.

   That last one is new state, in `SCeroSecNet`: a fifty-line ring, noted in the
   three `reachable*` doors where every refusal about the wire, the telephone and
   the air is actually decided, plus the pty each successful connect opened. A
   refusal used to leave no trace anywhere — the pty was never made, nothing was
   written to a disk, and the line the player read is on a screen that has
   scrolled. It is runtime state like the ptys beside it and is never saved.

   A name nothing resolves is NOT on it: that refusal is the resolver's and never
   reaches the wire.

5. **Scheduler** — every job on every machine the scheduler holds: machine, id,
   slot, name, the word the engine prints for its state (`CeroSecOS.jobWord`, so a
   job waiting on another machine reads `remote` here exactly as `jobs` prints it),
   steps, cpu seconds, debt, whether it is foreground, background or the prompt's
   own, which line it belongs to, and whether cron started it. Under it, the
   budget constants from `CeroSecDefs` beside the scheduler's live cursor and
   clock, and the selected machine's crontab.

   The crontab rows say **DUE NOW** or **waiting**, through `CeroSecOS.cronDue`
   with the game's own clock — and deliberately not "next run": nothing in the
   engine works one out, so a column of them would be a rule invented here, and
   the day the day-of-week rule moved this window would be the one thing that
   disagreed with cron.

6. **Log** — the mod's own lines, with All / Warnings / Errors buttons.

## The log

`CeroSec.log` now takes a level: `CeroSec.log(text)` is an info line and
`CeroSec.log(level, text)` names one of `CeroSec.LOG_INFO`, `LOG_WARN`,
`LOG_ERROR`. There is one log, so it is two arities and not two functions.

It does two things with a line. It **prints** it, gated on `CeroSec.DEBUG` exactly
as it always was, and it **appends** it to a 200-line ring. The append is not
gated: the print is console noise nobody asked for, and a Log tab that needed
`CeroSec.DEBUG` turned on first would be empty exactly when somebody opens it to
find out what went wrong.

The ring is per Lua **state**, and the Log tab reads the client's own with no
round trip at all. In singleplayer there is one state, so it holds the client's
lines and the server's together. On a dedicated server the tab shows the client's
own, and the server's are in the server log — fetching them over the wire is a
thing to add when there is a real server to test it against.

There is exactly one `print(` in the whole mod and it is inside `CeroSec.log`, so
there was nothing else to route.

### The one line the picking leaves behind

`CeroSecReach.pickComputer` is chatty behind `CeroSec.DEBUG` — the mouse, the zoom,
the candidate count, and one line per candidate with its square, its `raise`, the
box that was tested and whether the mask took it — and all of that is console
noise that stays behind the flag.

One line does not. When the cursor was **inside a computer's own rectangle and its
mask still said no**, that is written as a `LOG_WARN` whatever the flag says. It is
the shape every miss the picking was rewritten for had
([notes/picking.md](notes/picking.md)), and a player who right-clicks a monitor and
gets no entry must be able to read why off the **Log** tab's Warnings filter
without first editing a file and doing it again. A click has to land inside a
128 × 256 box to earn the line, so it does not fire on ordinary play — and a click
that merely weighed a computer's square and dropped it on the box says nothing,
because a warning that fires while the mod is behaving is a warning nobody reads.

## The protocol

Two commands, both on the existing global-object channel, both carrying the
window's own token and getting it back — a reply reaches a connection and a
connection is not a window (see [PROTOCOL.md](PROTOCOL.md)).

    client -> server: debug     { x, y, z, token, tab }
                      debugact  { x, y, z, token, act }
    server -> client: debug     { x, y, z, token, tab, rows, info,
                                  canTurnOn, canTurnOff, on, loaded, reason }
                      debug     { x, y, z, token, error }        -- a refusal
                      debug     { x, y, z, token, note }         -- it worked

`x, y, z` is the machine **selected in the window** and not a computer the player
is standing at — it may be on the far side of the map with its chunk unloaded.
`0,0,0` is the corner of the map and no computer is ever there, so it is what
"nothing selected" looks like on the wire; the server looks the triple up and
answers `nil` for one nothing is at.

Neither command asks for adjacency. That is the difference between these two and
every other command of this module, and it is deliberate: they are about the
COUNTY. What is asked instead is `CeroSec.debugAllowed()`.

`tab` is one of `machines`, `files`, `devices`, `network`, `scheduler` — anything
else is answered with nothing. `act` is `on`, `off`, `dump`, `selftest` or `givedisk`; the first two are
the object's own `turnOn`/`turnOff`, which are the very calls
`SCeroSecObject:toggle` makes for the context menu.

`givedisk` is the one act that does not name a machine, and it is answered **before**
the lookup every other act needs: it is about the survivor's inventory, nothing is
selected when a window is first opened, and a button that refused until a row had
been clicked would be a button nobody finds the use of. It still carries the
selection, because every command of this module does, and the server ignores it.

`rows` is an array of `{ c = { "cell", ... }, x, y, z, used }` — plain strings,
every cell truncated to 64 characters with the same `~` the terminal truncates
with, and the coordinates only on the Machines tab, where they are what makes a row
selectable; `used` only there too, for the filter. `info` is an array of strings for
the block under the list.

`canTurnOn`, `canTurnOff`, `on`, `loaded` and `reason` are about the **selected**
machine and ride on every tab's snapshot, because the buttons under the list are the
same six on every tab. They are built by `CeroSecDebug.selection` off the very
readings the act itself goes through, so a button greyed in the window is a button
whose act the server would refuse — and the day the rule moves, the window moves
with it.

An answer with an **`error`** on it and no `tab` is a refusal: the window puts it on
the first line of the block under the list and leaves its lists alone.

An answer with a **`note`** on it and no `tab` is the other half of that: something
that worked and has a sentence to show for it — the self-test's verdict, the receipt
for a disk handed over. Kept apart from a refusal on purpose, because a reader has to
be able to tell `PASS 138 FAIL 0` from `cannot turn on`; a refusal outranks a note on
the one line there is, a note after a refusal replaces it, and both go when another
machine is selected — half of what the self-test reports is about the machine that
WAS selected.

**Everything is bounded and says so**: 200 machines, 512 file rows, 128 devices,
128 jobs, 64 rows a network section, 16 zones, 50 wire events, 64 characters a
cell. A
truncated list reports its own cap in `info`, so a list that was cut says so on
the glass instead of quietly being the whole truth.

## What it costs the server

The machine LIST reads each machine's state **raw** —
`CeroSecOS.hostname`/`address`/`phoneOf`/`callsignOf` on `luaObject.os`, never
`luaObject:osState()` — for exactly the reason `CeroSecNet.recordOf` gives:
`osState` migrates a state, tops up its system files and validates a whole
filesystem, and a list that did that once per computer would walk every disk in
the county every two seconds. All four of those accessors are tolerant readers
that answer `nil` for anything that is not what they are looking for.

The three tabs that are about ONE machine ask `osState` of that one machine, which
is one disk. The Devices tab additionally walks the selected machine's building,
which is what `ls /dev` costs and is paid once per refresh. The premises block is
one square, one `BuildingDef` and one `getZonesAt` — all three for the selected
machine only, and none of them for the two hundred rows above it.

## The things it can change

Everything else is a read. Four of them go to the server and one is the client's
own:

- **Turn on** / **Turn off** go through `Commands.debugact`, which calls the
  object's own `turnOn`/`turnOff`. Same path, same sprite, same sound, same
  eviction of any window standing at it.

  **Every refusal comes back.** `turnOn` refuses a machine whose chunk is away —
  the wire is asked of a SQUARE and there is nobody to ask — and `debugact` used to
  drop that boolean and answer nothing at all, so the window drew the same `off` two
  seconds later: a button that could not work looked exactly like a button that had.
  Now the refusal goes back on the `debug` answer with an `error` on it, and the
  window prints it. A refusal a player cannot read is a refusal that looks like a bug
  in the mod.

  A press the window already knows cannot work is not sent at all — it prints the
  same sentence itself — and nothing is greyed on an answer that has not arrived
  yet: an unknown is asked, and the reason comes back with the refusal.
- **Teleport to it** is the client's own and is vanilla's own debug pair, copied
  from the one place vanilla teleports off a list row
  (`ISSpawnPointsEditor:onPointDoubleClick`,
  `media/lua/client/DebugUIs/ISSpawnPointsEditor.lua:130-140`): the middle of the
  square, `playerObj:teleportTo(x, y, z)` in singleplayer
  (`zombie.characters.IsoGameCharacter`, javap: `public void teleportTo(float,
  float, int)`) and `SendCommandToServer("/teleportto x,y,z")` on a client
  (javap: `public static void SendCommandToServer(java.lang.String);`), because a
  client has no business moving itself.
- **Open terminal** is the front door and nothing quieter: `CeroSecTerminal.open`
  needs the computer's `IsoObject`, so a machine whose chunk is away has nothing to
  open a window on — and the server would refuse the window anyway, every command a
  terminal sends being checked for adjacency. So it is a shortcut past the walk and
  the chair and past nothing else.

  Its three conditions are the client's own, because all three are facts about this
  client: the screen is in the world, the machine is **on** (the server's `on`), and
  the player is **standing at it** — the server's own arithmetic, copied from the
  adjacency every terminal command goes through (`SCeroSecSystem`'s `isAdjacent`,
  which is vanilla's `luautils.lua:138-140`). Whichever of the three is missing is
  what the reason line says, and the button is greyed until none is.

- **Self-test** runs `CeroSecSelfTest.runAll` on the selected machine: every vector
  of `CeroSecSelfTest.vectors` evaluated on **the Kahlua the game is running**, in
  this save, weighed against the answers `lua5.1` gives (generated and committed as
  `CeroSecSelfTestVectors.lua`); plus the save path of that machine —
  `stateToIsoObject`, the mirror read back out of the `IsoObject`'s own modData, a
  copy keeping only what `KahluaTable.save` keeps, and the boot gate.

  Every failing line goes through `CeroSec.log` at **warn**, which is the level the
  Log tab's own filter button reads, and names the vector, what `lua5.1` answers and
  what the game answered. The summary goes at **info** whether it passed or not — a
  run that said nothing when it passed would be a run nobody can tell from a button
  that did not work — and through `print`, so `console.txt` holds it and a release
  note can be pasted from it. And it comes back to the window as a `note`.

  It wants a machine whose chunk is **in**: the mirror is written into a thing in the
  world. A machine whose chunk is away is reported as a **failed vector** naming the
  chunk, in the same words the Turn on button greys with, and not skipped — a
  self-test that quietly ran half of itself would be a pass that proved less than the
  one before it.

  Why it exists at all: [TESTING.md](TESTING.md), "Three layers". It is a release
  gate, steps 6a and 6b of [RELEASE.md](RELEASE.md).
- **Give diagnostics disk** puts `CEROSEC DIAGNOSTICS` in the survivor's inventory:
  a floppy built from `CeroSecContent.DISKS` at the moment it is asked for, through
  the same `CeroSecContent.diskData` loot builds one with, so what he is handed is
  the disk the bench weighed. The item grant is `Commands.ejectfloppy`'s own path and
  not a shorter one — `AddItem`, the modData written **before** the item is announced
  to the clients, the sticker put on with vanilla's own three rename calls, and
  `sendAddItemToContainer` last — because a disk handed over any other way is a disk
  a multiplayer client never sees.

  The entry has **weight 0**, so `CeroSecContent.diskForRoll` can never land on it
  and no drawer in the county has one: this button is the only way to it. On it,
  `selftest.sh` — twenty-six checks of the shell, the text tools, the filesystem and
  the clock, which is the half of the mod no pure-function vector can reach. See
  [CONTENT.md](CONTENT.md).

**Dump state** writes nothing: it prints. The self-test writes only through the
save path it is testing, which is the write a chunk load does anyway.

## What is proven, and where

`tests/window_test.lua` holds the server half — the snapshots built against three
real machines on one real system, one of them with its chunk away, the caps held
against a disk that is over them, the devices snapshot equal to what
`CeroSecDevices.find` answers, the wire's ring, and the log ring's two hundred
lines. Section 52 adds the rework's half of it: the three refusals of
`turnOnRefusal` in the server's own words, the `used` flag on a computer nobody has
ever touched, the selection fields on every tab's snapshot, and a refusal driven
through the real `OnClientCommand` door and read off the reply.

`tests/debug_ui_test.lua` holds the window, against a fake tab panel, panel, list
box and button, and an `Events` register whose `Remove` really removes. Its blocks
10 to 13 are the rework's: the bands of the layout in pixels before and after a
resize, the columns (no two overlapping, every cell inside its own, a long cell cut
rather than drawn over its neighbour), the filter and the `showing N of M` line, the
cursor staying on its machine through a reordered county, and the greying and the
reason line for every button.

The whole of it is mutation-checked: a view put at `y = 0`, a list with no headroom
for its header row, cells drawn at their natural width, the filter off by default,
a selection kept by index, `debugact` swallowing the refusal the way it used to, and
a `turnOnRefusal` that blames the wiring for a chunk nobody can ask — each one turns
a bench red.

The in-game half — what is actually on the glass, whether the columns line up,
whether the buttons do what they say — is
[PARCOURS-TEST.md](PARCOURS-TEST.md#x-la-fenêtre-de-débogage-palier-debug).
