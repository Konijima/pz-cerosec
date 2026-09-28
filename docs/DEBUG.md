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
`false` in every shipped build and is only ever set to `true` on a developer's
own tree, exactly like `CeroSec.DEV_MANUAL_MENU` beside it; the release checklist
checks both. It is a plain constant in the shared defs and
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

**And a third condition, which is what a dedicated server needed.** With only the
two above, the window was unreachable on a server for everybody: debug mode is a
thing a CLIENT is started with, the server has none, so `isDebugEnabled()` answered
false there for every admin there has ever been. Which also says why debug mode
alone could not be the rule the other way round -- on a server it is the *client's*
own flag, so a player who launched his own game with `-debug` would pass it.

So the rule is now:

    the flag, OR the game's own debug mode, OR the asking player is an ADMIN

`CeroSec.debugAllowed(playerObj)` takes a player, and the two server commands pass
the one **the engine handed `OnClientCommand`** -- never a field on `args`, which
would be a client answering a question about itself. What is asked of him is the
engine's own comparison:

    zombie.characters.IsoPlayer  public java.lang.String getAccessLevel();
                                 public boolean isAccessLevel(java.lang.String);

`getAccessLevel()` is `role.getName()`, or the string `none` for a character with no
role (javap: `getfield role`, `ifnonnull`, `Role.getName()`), and `isAccessLevel` is
that string through `String.equalsIgnoreCase` (offsets 0-8) -- so a role spelled
`Admin` answers the same as one spelled `admin`.

With **no** player named -- which is how the context menu asks, about this client's
own connection -- the answer is the one vanilla's world-editing tools use,
`isClient()` and the access level **by name** (`isAccessLevel("admin")`, the global
being `getRole().getName().equals(arg)`; `ISWorldMap.lua:36`, `:166`, `:911` ask
`getAccessLevel() == "admin"`). It used to be `isClient() and isAdmin()`, the pair
`client/DebugUIs/AdminContextMenu.lua:22` opens with; `isAdmin()` compares the
connection's role against `Roles.getDefaultForAdmin()` by identity (javap,
`if_acmpne` at 15), and on the author's own server, as admin, it answered no --
a role that arrived over the wire is not that object. `isAdmin()` is kept as a
second door behind the name test.

**Admin and not moderator**, and vanilla draws that line in both places. Its admin
context menu takes either (`isAdmin() or getAccessLevel() == "moderator"`), but the
tools that CHANGE the world take the narrower one: editing the world map is
`isClient() and (getAccessLevel() == "admin")`
(`client/ISUI/Maps/ISWorldMap.lua:36`, `:166`, `:911`). This window resets a machine,
clears a password and hands out root, so it wears the second rule.

**Singleplayer is unchanged.** A character there has no role, `getAccessLevel()`
answers `none`, `isClient()` is false, and the flag or debug mode is the whole
answer.

## The door

A **CeroSec (dev)** submenu, last on a computer's right-click menu, holding the
three manual volumes and then **Debug window**. One submenu for the mod's two
testing doors rather than one each, and it is there when EITHER flag is on, so
turning one off leaves the other's entries where they were. On a server the debug
entry is there for an **admin** without any flag, because that is what
`CeroSec.debugAllowed()` answers about this client's own connection (above).

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

**Two rows of buttons.** The row this window shipped with sets the window's minimum
width all by itself, and the admin's and the tester's eight would have made it
seventeen buttons and a row wider than a screen -- so they are on a SECOND row under
it, with the login box and the disk list on that row with them. `layout()` answers
`rowY`, one top per row, and a button asks for the row it was given; the window's
opening height and its floor both count every row, because a height that had not
heard of the second would open with nineteen list rows and then eighteen. The second
row is on the **Machines** tab and nowhere else: all eight are about the machine that
is SELECTED, and that is the tab a machine is selected on -- the same rule the filter
already wears.

**A banner over the list, on the three tabs that are about ONE machine** (Files,
Devices, Scheduler — `CeroSecDebugUI.PER_MACHINE`). It says which machine their rows
belong to, in `selectedHost`'s own words and with the server's own `on` beside them:

    office at 10,10,0  (on)

and `no machine selected: pick one on the Machines tab` when nothing is. `(?)` is a
machine the server has not answered about yet, deliberately: a banner that printed
`off` before the server had spoken would be the greyed button that lied, one band
higher.

In it, two widgets. An **`ISComboBox` of every machine of the snapshot**, by hostname
and coordinates, which changes the selection **without leaving the tab** — through
`CeroSecDebugUI:selectMachine`, which is the one door a click on a row of the Machines
tab comes through too, so the two cannot drift and the refresh is the same refresh. It
is built off the machines snapshot and not off a list of the window's own (the server
is what knows what machines there are), it holds every machine whatever the county
filter says (this is how a reader REACHES one), and it is rebuilt only when the set of
machines really changed — a combo rebuilt twice a second is a list nobody can open.
And a **filter box**, which is the tab's own and is described under **Files** below.

The banner's room comes out of the **list** and not out of the panel: it is on three
tabs of six, and a panel that shrank would move the buttons under the other three.
The window's opening height and the floor it can be dragged to both count it, and the
floor is worked out from the SHORTEST list — a per-machine tab's — because a floor
taken off the county's own list is a floor at which those three have a list of a
negative height.

**A pane under the button rows.** Six rows of read-only text for the two things this
window had nowhere to put: what is IN a file the Files tab lists (`readfile`, below)
and the whole of what an act had to say when that is more than the one line under the
list — a sticky note is three lines. It is drawn with the same `drawText` and cut with
the same `fitText` as every cell of every list, and it is not an `ISRichTextPanel`
because that would have brought its own scrollbar, margins and font and left this
window with two answers to "how is text drawn here". What does not fit spends the last
of the six rows saying how much did not. It **clears** when the machine changes and
when the tab changes: a file's text under another machine's name, or under another
tab, is the one mistake the Files tab must not make, made one band lower.

Every number comes out of one `layout()`, and `applyLayout()` is what both
`createChildren` and `onResize` call — because two copies of this arithmetic that
disagreed is how it went wrong. The bands, top to bottom: title bar, tab strip,
banner (three tabs), header row, rows, button rows, pane, detail block.
`tests/debug_ui_test.lua` asserts in pixels that none of them reaches into the next,
before and after a resize.

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

The width it OPENS at comes off the widest tab's nominal columns, and the button
row's width comes off the words on the buttons, so the two are free to disagree —
a seventh button is what first made them and there are nine on the row now. So the
window is never opened narrower than its own button row (`createChildren`, after
the resize floors): a button hanging over the window's right edge is a button
somebody has to drag the corner to find.

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
   what the telephone work's rules are going to be written against.

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

   **Whose files.** The banner over the list names the machine (above), and its
   combo box changes which machine without going back to the Machines tab.

   **`/bin` is folded**, by default and until somebody clicks the row. Eighty-odd
   shipped commands are eighty-odd rows of a list whose cap is 512 and none of them
   is what a reader opened this tab for; the one `/bin` row stands for the lot and
   says how many it is standing for in its **last** cell — the one that already
   answered "how many nodes has this directory" — so the path cell still reads
   `/bin` and the row is still the row the cursor keeps. Clicking it opens it and
   clicking it again closes it, and neither spends a round trip: the rows are
   already in hand. It is a fact about the WINDOW, like the county filter, so it
   survives a change of machine.

   **The filter box** in the banner keeps the rows whose first cell holds what is
   typed — the path here, the device's name on Devices, the machine on Scheduler.
   Case-sensitive, `string.find` with `plain = true` and never a pattern, which is
   the rule every comparison against a typed string in this mod wears: a filter that
   took `.` for "any character" is a filter nobody can use on a filename. It is
   applied AFTER the fold, so what it sifts is what is on the glass — expand `/bin`
   to search it — and the `showing N of M` line still names the number the server
   sent.

   **Double-clicking a file row shows what is in it** in the pane under the buttons,
   read-only, through the `readfile` act (see **The protocol**). The path and the
   type are read off the row by the NAME of their column, so a column inserted
   before them cannot make the window ask for a file called `-rw-r--r--`; a row that
   is not a file says so on the reason line instead of going out on the wire, and the
   server asks the same question again anyway.

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

It does two things with a line. It **prints** it, gated on `CeroSec.DEBUG` -- the
developer's constant -- or on the sandbox option `CeroSec.ServerLog`, which is the
server owner's way to the same lines (`CeroSec.serverLog()` reads it at each call
and never at load, because `SandboxVars` is not there yet when the file runs and
`tests/defs_test.lua` runs it with no game; only the value `true` turns it on). And
it **appends** it to a 200-line ring. The append is not
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
                                  canTurnOn, canTurnOff, canReset, on, loaded,
                                  reason, resetReason }
                      debug     { x, y, z, token, error }        -- a refusal
                      debug     { x, y, z, token, note }         -- it worked
                      debug     { x, y, z, token, path, text }   -- a file

`x, y, z` is the machine **selected in the window** and not a computer the player
is standing at — it may be on the far side of the map with its chunk unloaded.
`0,0,0` is the corner of the map and no computer is ever there, so it is what
"nothing selected" looks like on the wire; the server looks the triple up and
answers `nil` for one nothing is at.

Neither command asks for adjacency. That is the difference between these two and
every other command of this module, and it is deliberate: they are about the
COUNTY. What is asked instead is `CeroSec.debugAllowed()`.

`tab` is one of `machines`, `files`, `devices`, `network`, `scheduler` — anything
else is answered with nothing. `act` is `on`, `off`, `dump`, `reset`, `selftest`,
`readfile` or `givedisk`; the first two are the object's own `turnOn`/`turnOff`, which are the
very calls `SCeroSecObject:toggle` makes for the context menu, and `reset` is the
one act with no survivor's gesture behind it (see **Reset machine** below).

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

`canTurnOn`, `canTurnOff`, `canReset`, `on`, `loaded`, `reason` and `resetReason`
are about the **selected** machine and ride on every tab's snapshot, because the
buttons under the list are the same nine on every tab. So do the eight pairs the
SECOND row needs -- `canRootNote`/`rootNoteReason`, `canStaffNote`/`staffNoteReason`,
`canAccounts`/`accountsReason`, `canClearPass`/`clearPassReason`,
`canRootLogin`/`rootLoginReason`, `canCronNow`/`cronNowReason`,
`canForceWire`/`forceWireReason`. A pair each and never one shared reason, for the
reason the reset's own pair exists. The reset carries its own
reason and does not borrow `reason`: that one is `turnOn`'s, and a window printing
"it is already on" for a refused reset would be blaming the wrong rule. They are built by `CeroSecDebug.selection` off the very
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

An answer with **`path` and `text`** on it and no `tab` is one FILE, for the pane:
`text` is an array of lines and `path` is the file they came out of, because a reader
who double-clicked two rows has to be able to tell which answer he is looking at. Its
own field and not a note, since a note is one sentence and this is a file. It is kept
only when it names the machine that is selected NOW — the rule the selection fields
wear — and it goes when the machine or the tab changes.

### `readfile`

`debugact { act = "readfile", path }` answers the bytes of one file of the selected
machine, and it is the one act of this window that is a **read**: it writes nothing,
and it lives in `SCeroSecDebug.lua` with the snapshots for that reason.

It is root's read and does not pretend otherwise (`CeroSecOS.rootSession`, the session
the kernel reads `/etc/passwd` with). This window already prints every password on the
machine in clear for an admin, so a lock here would be a lock on the wrong door — and
it is behind `CeroSec.debugAllowed(playerObj)` like every other act, asked of the
player the ENGINE handed `OnClientCommand`.

**The path is a client's string, so it is validated** before it reaches anything:
absolute, at most `CeroSecOS.MAX_DEPTH` components, every component a name the
filesystem could really hold (`CeroSecOS.isValidFileName`), and the node it lands on a
`file` and not a directory. `..` cannot do anything here — `CeroSecOS.resolve` eats it
in pure string work and the tree is a table of ours with no way out of it — and it is
refused all the same, because a door that is only safe because of what is behind it
stops being safe when what is behind it moves. Nothing of the path ever reaches a Lua
pattern.

**Bounded twice.** `CeroSecDebug.FILE_BYTES_MAX` (4096) bytes, with a last line
`[... N more bytes]`, because the pane is for looking at what a script or a memo says
and not for reading a disk down a socket; and `CeroSecDebug.FILE_LINES_MAX` (64) lines
with a `[... N more lines]` of its own, because four kilobytes of newlines is four
thousand lines and the pane draws six.

**What cannot be printed is SHOWN and never dropped**, in two notations
(`CeroSecDebug.showBytes`):

- `^X` for a byte under 32 and `^?` for 127 — the caret notation every Unix has
  printed control characters in since `cat -v`, the byte plus 64, so a tab reads `^I`
  and a carriage return `^M`. A script written on a machine that thought it was DOS
  reads `line^M` here, which is the answer to "why does this not run".
- `\NNN`, three octal digits, for a byte of 128 and over — what `ls -b` and `od -b`
  print for a byte with no caret name. Deliberately **not** `cat -v`'s own `M-x` meta
  notation for the high half: this pane is a developer's tool and not a 1993 program,
  and `M-^I` reads as two escapes where `\211` reads as one byte. Nothing this mod
  writes can hold one (every write goes through the printable rule), so a high byte
  here is a byte something else put there — which is exactly when a reader needs its
  number.

A newline ends a line and is the one byte not shown; a file with no newline at the end
is still its last line, and an empty file is no lines at all.

**Everything is bounded and says so**: 200 machines, 512 file rows, 128 devices,
128 jobs, 64 rows a network section, 16 zones, 50 wire events, 64 characters a
cell, 4096 bytes and 64 lines of one file. A
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

Everything else is a read. There are fourteen: the two power buttons, the teleport,
the reset, the self-test, the diagnostics disk, and then the admin's and the tester's
eight on the second row. Thirteen go to the server and the teleport is the client's
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
- **Reset machine** is the one act in here that cannot be undone, and the only one
  behind two clicks: the selected machine's whole state thrown away so that its
  first power-on can happen a second time. It is refused on a machine that is not
  off, and everything about it — why it exists, what `resetMachine` does, and the
  five seconds the arming lasts — is under **Reset machine** below.

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

  And then the **shell half** (`CeroSecSelfTestShell.lua`): 356 typed lines, each
  run on a scratch machine the runner makes with `CeroSecOS.newState` and copies
  once per case, with a fixed clock and no world under it, and weighed against
  what the screen should show, what `$?` should be and what a file should hold.
  It is too long for one tick, so the press only starts it — the note says
  `shell half running, its verdict goes to the log` — and the server's
  `Events.OnTick` carries it, about 3 ms a tick. When the last case is done every
  failing case goes to the log at **warn** (name, the line typed, what it wanted,
  what it got), the summary `shell selftest: PASS n FAIL m` at **info** with a
  second line saying how long it took, and `CeroSec shell selftest: PASS n FAIL m`
  through `print`. It does not come back to the window: by then the player may have
  closed it. A second press while it runs starts nothing and says so.

  Why it exists at all: [TESTING.md](TESTING.md), "Three layers". It is a release
  gate, steps 6a and 6b of [RELEASE.md](RELEASE.md).
- **Give diagnostics disk** puts `CeroSec DIAGNOSTICS 1.0` in the survivor's inventory:
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

And then the eight of the second row, for a **server admin** or somebody walking the
in-game checklist. Every one of them is behind `CeroSec.debugAllowed()` on the
server, every one of them refuses through a rule in `SCeroSecDebug.lua` that also
greys its button, and every one of them answers the window -- a `note` when it worked
and an `error` when it did not -- because the old silent **Turn on** is the defect
this window has already paid for once. **What each one WRITES is the column that
matters**:

| act | what it writes | refused when |
| --- | --- | --- |
| **Give root note** | nothing on any disk: one sheet of the game's own paper (`Base.SheetPaper2`), named `Sticky note (root)` with the password on its page, into the survivor's own inventory | the chunk is away (the premises cannot be asked), the machine is in no building, no profile is written for its premises, or that profile has no root password |
| **Give staff note** | the same, one paper into his inventory | the same three, plus a profile whose accounts are all open |
| **Show accounts** | nothing at all: lines to the server's log and one line back to the asking window | the machine has never been switched on, so it has no disk to read |
| **Clear password** | `/etc/passwd` on the selected machine, through `CeroSecOS.setPassword` | the same, plus a `login` that is not a name or an account the machine has not got |
| **Give disk** | nothing on any disk: one floppy item into his inventory | a `disk` id the catalogue has not got, a bag that will not take it |
| **Login as root** | the machine's **console**, and `/var/log/wtmp` on its disk (the login's own record) | the machine is off, it has no screen, it is at the BIOS, somebody is already logged in, or it has no root account |
| **Run cron now** | whatever the crontab lines that are due write -- which is the point | the machine is off |
| **Force wire** | the premises' automation record (`system.auto`) and the fixtures' own modules | the machine has no address yet, its premises has not been asked, it rolled no, or it is already wired |

Four of them are worth a sentence more than the table gives:

- **Give root note** and **Give staff note** derive the letters exactly as the world
  derives them -- the save's own secret and the premises' two bytes, through
  `CeroSecContent.rootKey` and `accountPassword` -- so the paper opens the machine in
  front of it. And `CeroSecNotes.premisesMark` is **left alone**: that mark says a
  premises' one paper has really been placed in a container, and setting it here would
  take the note out of the next drawer a player opens. The staff note is the FIRST
  locked slot every time and never a roll, so the button can be used twice, and it can
  never name root.
- **Show accounts** says the PLAINTEXT of every password the catalogue put on the
  machine. It is allowed to: an admin who may empty a machine may read its passwords,
  and this is the half of "remove a password" a tester actually wants, which is to get
  in. Nothing derived is stored in clear anywhere, so the letters are worked out again
  here the way the paper works them out; an account the catalogue did not make says
  `derived -`, because there is nothing to read off a salted hash. The lines go to the
  game's own log by `print`, unconditionally, the way the dump and the self-test do
  (`CeroSec.log` prints only under `CeroSec.DEBUG` or the `CeroSec.ServerLog` option, and its ring is one Lua state's,
  so on a dedicated server an admin's Log tab shows his client's ring: the letters
  are read in `console.txt` on a client, or in the server's log); the ASKING window's
  note, through `reply`, carries the count and says where the lines are; nothing goes
  to any other client -- the save's own secret is on none of them.
- **Clear password** is `passwd -d`, and on this machine there is nothing to invent:
  an open account is one whose stored hash is the hash of the empty string
  (`CeroSecOS.newUser`), and `login` lets an empty answer straight through. So the act
  is `setPassword(state, login, "")` and the paper in the drawer stops opening it.
- **Login as root** skips the PASSWORD CHECK and nothing else. The session is the very
  table `CeroSecOS.login` answers with, built off the account record, and every gesture
  after it is the login's own: `SCeroSecSystem:beginSession`, which the `input` command
  now calls too -- the shell's variables, the greeting, the `wtmp` line. So `who`,
  `last` and the prompt read exactly as they read for somebody who typed the letters.
  The window then opens the terminal through its own **Open terminal** path, so the
  three conditions a window has to meet are the ones it already checks.
- **Run cron now** winds the minute hand back one and calls the daemon's own
  `cronPass` and `atPass`. It has to: `cronPass` runs a line only on a minute it has
  not already looked at, which is right for the daemon and is exactly what a tester
  needs to get past. Nothing else about the pass changes -- the lines that fire are the
  ones `cronDue` says are due at the clock the world has.
- **Force wire** calls `CeroSecAuto.wire` over and over. It has to: the walk covers
  `ROOMS_PER_MINUTE` rooms a game minute, so a mall takes many minutes. It stops on
  the first of three things -- the record says `wired`, a pass fitted nothing and
  walked no new room, or `CeroSecDebug.WIRE_PASS_MAX` passes have gone by -- and the
  ceiling is there for the case the walk cannot finish at all because half the
  building's chunks are away.

**Dump state** writes nothing: it prints. And the self-test writes only through the
save path it is testing: `CeroSecSelfTest.runSave` calls `stateToIsoObject`, which
asks `checkPower` about the room before it mirrors the state into the object's
modData — so the only thing the self-test can change is what a chunk load changes
anyway, a machine whose wire has gone going dark. That is the write, and there is
no other.

## Reset machine

**A machine nobody has ever used, made out of one that has.** Prefill runs at the
FIRST power-on and at no other moment (`SCeroSecObject:prefill`), so a machine
whose first power-on went wrong halfway through — a crash mid-prefill — is a
machine there is no second try on: it is half filled for ever and the bug that
half filled it cannot be provoked again. This button is what makes the second try
possible, and it exists for testing and for nothing else.

**It is refused on a machine that is not OFF**, in the server's own words
(`CeroSecDebug.resetRefusal`: `it is on -- switch it off first`), which is what
greys the button and what the reason line prints. It asks the world nothing at
all, so a machine on the far side of the county with its chunk away is reset
exactly like one in the room — the difference from **Turn on**, which needs a
square to ask about the wire.

What `SCeroSecObject:resetMachine` does, and it is everything `turnOff` does plus
the disk: every job killed and the pending `shutdown` order with them, the dark
interval of a reboot dropped, the machine taken off the scheduler's book
(`CeroSecJobs.killAll`), every window standing at it **told** and not merely
forgotten, then `os`, `console`, `heard`, `cron` and the two sticky refusals
(`osBroken`, `osNewer`) gone, and the state pushed out to the IsoObject and to
the clients the way `turnOff` pushes one.

**The disk stays in the drive.** What is in the slot is a thing in the WORLD — a
player carried it here — and it lives inside the machine's state only because that
is where the serializer can keep it. So it is lifted out, the state is thrown
away, and it goes back into the fresh one. There is deliberately no "eject it to
the floor first": a disk in a drive is in the drive, which is the same rule the
pickup path wears. A machine with an empty drive comes back with no state at all;
one with a disk comes back with a fresh state whose only content is the drive.

**The accounts come back the same, and the paper in the drawer still opens them.**
Everything prefill derives comes out of the save's own secret and the premises,
and a reset touches neither — so the same profile, the same logins and the same
root password come back. The note bookkeeping (`CeroSecNotes.premisesMark`, on the
system and saved with the save) is **not** cleared either: it is about a PREMISES
and not about a machine, the paper already in a desk is still valid, and clearing
it would put a second copy of one password in the next drawer somebody opens.

**How the next power-on knows.** `self.osFresh`, set here and consumed by
`turnOn`, where it is read beside the `bare` test. It has to be a flag and not the
absence of a state, because the absence does not survive being LOOKED at:
`osState` makes a fresh machine out of nothing, and this very window asks `osState`
of the selected machine every two seconds for its detail block — so a reset
remembered as "`self.os` is nil" would be undone by the refresh that followed it.
It is runtime state and not among the object's saved keys: reset, then reload
without switching the machine on, and it simply comes up as the fresh machine it
now is with no prefill. The gesture is reset and then switch on.

**Two clicks on the glass, and no dialog.** The first click arms and turns the
reason line into `Click again to reset <host> at x,y,z`; the second sends; the
arming expires after `CeroSecDebugUI.ARM_MS` (five seconds) and is dropped by a
click on another row or by the machine coming on in between. A vanilla modal would
be one more window over a window that is already a tool, and what a reader needs
is not a box to click through but to be told which machine he is about to empty.

**The row does not vanish under the cursor.** A reset machine has no `os`, so the
server's `used` flag goes false and the `used only` filter would take its row away
at the very moment its reader needs it — a computer that looked deleted. So
`CeroSecDebugUI:passes` keeps the SELECTED machine's row whatever the filter says,
on this refresh and on every one after it, while the machines nobody is looking at
stay filtered away.

## What is proven, and where

`tests/window_test.lua` holds the server half — the snapshots built against three
real machines on one real system, one of them with its chunk away, the caps held
against a disk that is over them, the devices snapshot equal to what
`CeroSecDevices.find` answers, the wire's ring, and the log ring's two hundred
lines. Section 52 adds the rework's half of it: the three refusals of
`turnOnRefusal` in the server's own words, the `used` flag on a computer nobody has
ever touched, the selection fields on every tab's snapshot, and a refusal driven
through the real `OnClientCommand` door and read off the reply.

Section 53 is the reset's: a real machine prefilled off a real premises, a file of
the player's own on it, a disk in its drive and a paper already marked for the
premises — reset, and then switched on again — plus the refusal on a running
machine, the refusal through the real `OnClientCommand` door, and the same door
with `CeroSec.debugAllowed` shut, which answers nothing and acts on nothing. The
jobs, the windows, the reboot interval and the heard stations it clears are
PROVOKED onto a machine that is off, because `turnOff` has already taken them and a
bench that merely switched the machine off would assert zero against zero.

`tests/debug_ui_test.lua` holds the window, against a fake tab panel, panel, list
box and button, and an `Events` register whose `Remove` really removes. Its blocks
10 to 13 are the rework's: the bands of the layout in pixels before and after a
resize, the columns (no two overlapping, every cell inside its own, a long cell cut
rather than drawn over its neighbour), the filter and the `showing N of M` line, the
cursor staying on its machine through a reordered county, and the greying and the
reason line for every button.

Its block 14 is the reset's half: the button greyed and usable, the first click
that sends nothing and names the machine, the second that sends, the five seconds
running out, an arming that does not cross a change of row or a machine coming on,
and the selected row surviving the filter.

The whole of it is mutation-checked: a view put at `y = 0`, a list with no headroom
for its header row, cells drawn at their natural width, the filter off by default,
a selection kept by index, `debugact` swallowing the refusal the way it used to, and
a `turnOnRefusal` that blames the wiring for a chunk nobody can ask — each one turns
a bench red. And for the reset: one click that resets, a reset allowed on a running
machine, the note bookkeeping cleared, the jobs left alive, the disk dropped with
the state, `osFresh` never set (so the next power-on does not prefill), the selected
row filtered away, and the shut door ignored — eight more, each one red. And a
ninth on the layout: the window opened at its nominal width with the button row
wider than it, which puts the last button over the edge.

**Section 54 is the admin's and the tester's eight**, every one of them driven through
the real `OnClientCommand` door and asserted on the STATE it leaves: the paper in the
bag with the words the drawer would have carried and the premises still unmarked, the
staff paper's login really on the machine with really that password, one log line per
account with root's letters in clear and the save's own secret on none of them, a
digest really replaced by the digest of nothing so that `login` takes an empty answer,
a floppy wearing a sticker the catalogue can prove is that entry's with a disk the
slot would take on it, root at the glass with a login shell's variables and a `wtmp`
line naming him, a crontab line's own output in `/var/mail/root` after the scheduler
has stepped the job it made, and a premises of twenty rooms walked to `wired` in
several passes where one pass of the walk leaves it unfinished. Then every refusal in
the server's own words, and then the door shut over all eight, which answers nothing
and does nothing.

It also writes down one seam: the disk acts are refused on a machine nobody has ever
used, and the WINDOW'S OWN REFRESH stops that being true, because the Machines tab
asks `osState` of the selected machine and `osState` makes a state out of nothing --
the same fact the reset's `osFresh` flag exists for. What must never happen is the act
inventing one itself, which is why the refusal reads `luaObject.os` raw.

**Its last block is the door an admin comes through**: a fake player at `admin` is
allowed with the flag off and no debug mode and his press really switches a machine
off, a player at `none` is answered nothing and changes nothing, a moderator is
refused (the narrower of vanilla's two rules), `Admin` with a capital is still the
admin role, and a client sending `admin = true`, `accessLevel = "admin"` and three
more spellings of it is still not one.

`tests/debug_ui_test.lua`'s block 16 is the second row's: the eight buttons are there
on the Machines tab and gone on every other, each sends its own act on the selected
machine under this window's token and asks for no snapshot, the login box opens on
`root` and travels as it is typed and falls back to `root` when it is emptied, the
disk list is built off `CeroSecContent.DISKS` and sends the entry's ID and not the
words on it, each of the seven is greyed by ITS OWN field while the other six stay
usable, a press the window knows cannot work sends nothing and prints the server's own
sentence, and **Login as root** opens the terminal when it worked and opens nothing
when it was refused. Its block 10 now asserts TWO button rows in pixels: every button
on the row it was given, no row reaching into the one above it, the login box and the
disk list on the second, and the detail block under the LAST row.

**Section 55 of `tests/window_test.lua` is `readfile`'s**, driven through the real
`OnClientCommand` door and read off the reply: the lines of a file the machine really
holds, a last line with no newline after it still a line and an empty file no lines at
all, every one of the two notations on the bytes themselves (`a^Ib^M^@^?\310`), the
byte cap provoked with a file OVER it and the line cap with one of newlines, and then
every refusal the path can earn — a file that is not there, a directory, `/`, a
relative path, no path at all, a component the machine could not hold, a path deeper
than it allows, and a `..` that resolves and is answered. Then the door shut, which
answers nothing.

`tests/debug_ui_test.lua`'s blocks 17 to 20 are the banner's, the machine list's, the
fold's, the filter's and the pane's: the banner's text for a machine that is on, one
that is off, one nothing has been said about and none at all, and painted on a
per-machine tab and not on the county's; the list built off the snapshot with the
coordinates as its data, a choice out of it selecting that machine and asking the
server again, a row click moving the list, a choice of the machine already selected
asking nothing, and the list rebuilt only when the county changed; `/bin` folded to one
row whose last cell counts what it stands for, folded from a COPY so that a second fill
folds the same three, opened and closed by a click and spending no round trip;
the filter keeping what is typed and nothing else, case-sensitive, a dot a dot, and not
touching the county's list; and the pane with a file in it, the path over it, a run
longer than the band saying how much is not on the glass, a file about another machine
dropped, a note whole in it and still on the reason line, and cleared by a change of
tab and by a change of machine. Block 10 asserts the two new bands in pixels: the pane
under the last button row and clear of the detail block, the banner out of the LIST on
exactly three tabs with its two widgets inside the panel and clear of the header row,
and the floor taken off the SHORTEST list.

Mutation-checked, each one red on its own line: no fold, a fold that writes into the
snapshot, the filter switched off, the filter as a Lua pattern, a combo that selects
nothing, the pane's room never taken out of the panel, the banner taking no room off
the list, a pane that survives a change of tab, a file for another machine shown, a
directory asked for; and on the server, no byte cap, a control byte dropped instead of
shown, a relative path let in, and `readfile` outside the door.

The in-game half — what is actually on the glass, whether the columns line up,
whether the buttons do what they say — is
[PARCOURS-TEST.md](PARCOURS-TEST.md#x-la-fenêtre-de-débogage-palier-debug).
