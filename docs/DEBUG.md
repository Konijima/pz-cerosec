# CeroSec — The debug window

What the mod is actually doing, on one screen: every computer the server holds,
the selected machine's filesystem and its `/dev`, the wire, the scheduler, and
the mod's own log. A developer's tool and never a player's.

See also: [PROTOCOL.md](PROTOCOL.md) for the wire the terminal runs on, which
this window borrows; [ARCHITECTURE.md](ARCHITECTURE.md) for what the server
holds and why an unloaded chunk changes nothing about it;
[TESTING.md](TESTING.md) for the two suites that prove this, and
[PARCOURS-TEST.md](PARCOURS-TEST.md#w-la-fenêtre-de-débogage-palier-debug) for
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
`ISTabPanel` in it and an `ISScrollingListBox` per tab with columns on it — which
is `ISEntitiesDebugWindow`'s own shape
(`media/lua/client/DebugUIs/DebugMenu/Entity/ISEntitiesDebugWindow.lua:46-62`)
down to the ten pixels of border spacing. The list box's own palette and
`UIFont.Small`, and nothing of the mod's: it is a tool and it sits among vanilla's
tools, not among the phosphor screens.

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

1. **Machines** — every machine the server holds, loaded chunk or not, which is
   every computer in Knox County that has ever been switched on (see the head of
   `SCeroSecNet.lua`). Position, facing, on/off, whether its chunk is in, whether
   it has a wire, hostname, address, telephone number, callsign, live jobs and
   open windows. A machine whose chunk is away reads `-` under **wire** and not
   `no`: `hasPower` is asked of a SQUARE, and no square means there was nobody to
   ask — the distinction a sweep once got wrong and switched off every computer
   behind a walking survivor.

   Clicking a row selects that machine, which is the machine the Files, Devices
   and Scheduler tabs are about. Under the list is that machine's own detail: its
   sprite, its state version, its `sysv`, whether the system passes
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

## The protocol

Two commands, both on the existing global-object channel, both carrying the
window's own token and getting it back — a reply reaches a connection and a
connection is not a window (see [PROTOCOL.md](PROTOCOL.md)).

    client -> server: debug     { x, y, z, token, tab }
                      debugact  { x, y, z, token, act }
    server -> client: debug     { x, y, z, token, tab, rows, info }

`x, y, z` is the machine **selected in the window** and not a computer the player
is standing at — it may be on the far side of the map with its chunk unloaded.
`0,0,0` is the corner of the map and no computer is ever there, so it is what
"nothing selected" looks like on the wire; the server looks the triple up and
answers `nil` for one nothing is at.

Neither command asks for adjacency. That is the difference between these two and
every other command of this module, and it is deliberate: they are about the
COUNTY. What is asked instead is `CeroSec.debugAllowed()`.

`tab` is one of `machines`, `files`, `devices`, `network`, `scheduler` — anything
else is answered with nothing. `act` is `on`, `off` or `dump`; the first two are
the object's own `turnOn`/`turnOff`, which are the very calls
`SCeroSecObject:toggle` makes for the context menu.

`rows` is an array of `{ c = { "cell", ... }, x, y, z }` — plain strings, every
cell truncated to 64 characters with the same `~` the terminal truncates with,
and the coordinates only on the Machines tab, where they are what makes a row
selectable. `info` is an array of strings for the block under the list.

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

## The three things it can change

Everything else is a read. The three are the two power buttons and the teleport:

- **Turn on** / **Turn off** go through `Commands.debugact`, which calls the
  object's own `turnOn`/`turnOff`. Same path, same sprite, same sound, same
  eviction of any window standing at it.
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
  the chair and past nothing else; a machine out of reach says so in the log rather
  than opening a window that would shut itself.

**Dump state** writes nothing: it prints.

## What is proven, and where

`tests/window_test.lua` holds the server half — the snapshots built against three
real machines on one real system, one of them with its chunk away, the caps held
against a disk that is over them, the devices snapshot equal to what
`CeroSecDevices.find` answers, the wire's ring, and the log ring's two hundred
lines. `tests/debug_ui_test.lua` holds the window, against a fake tab panel, list
box and button, and an `Events` register whose `Remove` really removes.

The in-game half — what is actually on the glass, whether the columns line up,
whether the buttons do what they say — is
[PARCOURS-TEST.md](PARCOURS-TEST.md#w-la-fenêtre-de-débogage-palier-debug).
