# CeroSec rung 4 — manual test checklist

Build 42.20.4. Everything the headless benches cannot reach: the real world under
`/dev`. The engine's half is pinned character by character in `tests/os_test.lua`,
and the discovery is driven over a fake world in `tests/window_test.lua`, so what
is left here is the one thing neither can prove — that the Java calls do what
`javap` says they do, on a real map, with a second pair of eyes watching.

Do rung 2's checklist first, or at least its A and B sections: nothing here works
on a machine you cannot log into. Turn `CeroSec.DEBUG = true` in
`42/media/lua/shared/CeroSec/CeroSecDefs.lua` for the console lines.

Log in as `admin` (empty password) and `su root` (empty password) — the devices are
`660` and root's, so everything below is typed as root unless it says otherwise.

## Devices

### D — Solo, in a map building

Pick a house with a named kitchen and a lit room, put a computer in it, and power
it.

1. **The listing.** `ls -l /dev`. One line per light switch, lockable door and
   window in **any room of that building** — not just the room the computer is in.
   Columns: `c` and the mode, `root`, the id, what it stands between, the side,
   the state. Nothing is wider than the glass.
2. **The names are the map's.** The descriptions are raw room ids — `kitchen`,
   `livingroom`, `bathroom` — not prettified names. A door with the outdoors on
   one side reads `exterior`. A door between two rooms reads `<room>-<room>`, and
   the first half is the room the door's own square is in.
3. **Nothing from next door.** Stand outside and check the neighbouring house's
   lights are **not** in the listing. Only this building.
4. **A light.** `cat /dev/light0` → `on` or `off`. `echo off > /dev/light0`: the
   room goes dark **in the world**, and `cat` says `off`. `echo on` puts it back.
5. **A light with nothing behind it.** Find a switch with no bulb, or cut the
   power to the house (day 9+, or the sandbox switch). `echo on > /dev/light0`
   answers `light0: no power`, and `cat` still says `off`. The switch must not
   move.
6. **A keyed door.** Find a locked interior door — `cat /dev/lockN` says `locked`.
   `echo unlock > /dev/lockN`, then walk over and **open it by hand**: it opens,
   with no "the door is locked" message and no key. `echo lock > /dev/lockN` and
   try again: it refuses.
7. **A window.** `cat /dev/win0` → `locked` or `unlocked`. `echo unlock >
   /dev/win0`, walk over, and the window opens by hand. `echo lock` and it does
   not.
8. **A smashed window.** Break one with a hand. `ls -l /dev` now says `smashed`
   for it, and `echo lock > /dev/winN` answers `winN: smashed`. Board another one
   up: `barricaded`, and `echo lock > /dev/winN` answers `winN: barricaded`.
9. **The numbers hold.** Write the listing down. Save, quit to the main menu, load
   the save, `ls -l /dev`: every id is on the same device it was on.
10. **A gap stays a gap.** Sledgehammer one of the doors. `ls -l /dev` no longer
    lists its id, and `cat /dev/lockN` on it says `lockN: no such device` — not
    `no such file`. Every other id is unchanged. Build a new door: it takes the
    **next** number, never the gap.
11. **The mode.** As `admin` (`exit` out of the su), `cat /dev/light0` says
    `light0: permission denied`. `su root`, `chmod 666 /dev/light0`, `exit`, and
    now `admin` reads it and can write it. Save, reload, and the `666` is still
    there.
12. **Nothing else works on one.** `rm /dev/light0`, `mv /dev/light0 /root/x`,
    `cp /dev/light0 /root/x`, `edit /dev/light0` — all four say `is a device`.
    `mkdir /dev/mine` and `touch /dev/mine` say `/dev: read-only`.
13. **Nothing is on the disk.** `df` before and after a `ls -l /dev`: the same two
    lines, byte for byte. `ls -l /` shows `/dev` with its entry count, and the
    machine boots normally after a save and a reload — a state carrying a device
    node would come back as `No operating system found.`

### E — Solo, in a player base

Build an enclosure with no map building under it — four walls and a door of your
own — and put a computer inside it.

14. **The radius rule.** `ls -l /dev` lists what is within **ten tiles on the same
    floor** and nothing beyond. Put a light switch (or use a nearby house's) at
    eleven tiles and confirm it is not there; at ten, it is.
15. **One floor only.** Build a second storey with a light switch on it. It is not
    in the listing.
16. **`built`.** Your own door reads `built` in the description column, with the
    side it faces.
17. **A padlock.** Padlock your door. `cat /dev/lockN` → `padlock`. `echo unlock >
    /dev/lockN` and walk through it. `echo lock` and it refuses you again.
18. **No padlock, no key.** A player-built door with neither answers `lockN: no
    padlock` to both `lock` and `unlock`.

### F — Out of reach

19. **A distant building.** Put a computer in a house across town, log in, and
    leave a terminal open — then walk far enough that its chunks unload (the game
    keeps 13×13 chunks of 8 tiles around a player). `ls -l /dev` lists nothing, and
    `echo on > /dev/light0` answers `light0: no such device`. Walk back: the same
    ids come back on the same devices.
20. **Nothing acted while you were away.** The light you tried to switch is still
    where you left it.

### G — Host mode, two players

Start a **Host** game and have a second player at the same computer, or at the
same house.

21. **A light, seen by both.** Player 1 types `echo on > /dev/light0`. Player 2,
    standing in that room, sees it come on — without relogging, without walking
    away and back.
22. **And off again.** `echo off` and player 2 sees it go dark.
23. **A door, seen by both.** Player 1 unlocks a keyed door from the computer.
    Player 2 walks over and opens it by hand. Then player 1 locks it and player 2
    is refused. This is the one that proves the hand-made
    `syncIsoObject(false, 0, nil, nil)` — a client that never heard about the
    change would still think the door was locked.
24. **A window, seen by both.** Same, with `echo unlock > /dev/win0` and player 2
    climbing through.
25. **A padlock, seen by both.** Same, on a player-built door.
26. **Both screens agree.** Both players open a terminal on the same computer.
    Player 1 types `ls -l /dev`; the listing appears on **both** screens, since
    every screen change goes to every watcher. Player 2 then types `cat
    /dev/light0` and both see the answer.
27. **What one changes, the other reads.** Player 1 `echo off > /dev/light0`;
    player 2 types `cat /dev/light0` on his own window and gets `off`.
28. **Somebody smashes a window.** With a terminal open, player 2 breaks a window
    of the building. Player 1 types `ls -l /dev` again: it now reads `smashed`. The
    listing already on the screen does **not** rewrite itself — a printed line
    stays printed — the new one is the fresh one.

### H — The machine itself

29. **A computer with no world around it.** Pick a computer up and put it down in
    the middle of a field. `ls -l /dev` lists nothing, and everything else on the
    machine still works.
30. **Carried across town.** Pick a computer up in one house and put it down in
    another. Its `/dev` is the new building's. The old building's ids are gone from
    the listing and answer `no such device` — the machine remembers the numbers, it
    does not remember the devices.
31. **Off and on.** `reboot` from the shell: the machine comes back and `ls -l
    /dev` is the same listing.
32. **The BIOS.** `rm -r /bin` as root, `reboot`, answer `y` at `Restore system?`.
    The machine comes back and `/dev` still works — the repair does not touch it.

Build 42.20.4. What the headless benches cannot reach: the item as the game parses
it, the icon as the game draws it, the window as the eye sees it, and the book as it
actually turns up in the world.

`tests/manual_ui_test.lua` already covers the wrapping, the pagination, the
navigation, the bookmark on the item and the twelve loot lists. It covers all of that
against a **fake** font and a **fake** distribution table. Everything below is the
part where the real game gets a say. Turn `CeroSec.DEBUG = true` in
`42/media/lua/shared/CeroSec/CeroSecDefs.lua` for the console lines.

**The text is a separate file.** `42/media/lua/shared/CeroSec/CeroSecManual.lua`
holds the chapters and is written apart from the reader. If it is missing the book
still opens — a title leaf and an empty contents — which is itself worth one look
(step 6).

## Manual

### A — The item exists and the game parsed it

1. **No script errors on load.** Start a game with the mod on. The console
   (`~/Zomboid/console.txt`) has no `FileNotFoundException` and no script parse error
   naming `items_cerosec.txt`. A single bad key takes the **whole file** down, so a
   silent load is the whole of this check.
2. **It is in the item list.** Open the debug menu (or the admin panel) → **Items
   list**. Filter on `CeroSec`. `CeroSec.Manual` is there, its display category reads
   **Literature**, and its name reads **CeroSec OS User's Manual** — the name from
   `Translate/EN/ItemName.json`, not the `DisplayName` fallback and not the raw
   `Manual`.
3. **Spawn one.** Spawn it into the character's inventory. Weight 0.8, and the icon is
   the navy book with the little green screen on its cover — **not** the white
   question mark. A question mark means the texture did not resolve: check that the
   file is `common/media/textures/Item_CeroSecManual.png` exactly, since the game
   builds the name as `"Item_" .. Icon` and looks it up as
   `media/textures/<that>.png`.
4. **Drop it.** Drop the manual on the floor. There is a closed book model on the
   ground, it can be picked up again, and nothing is logged. (`WorldStaticModel`.)
5. **No vanilla read option.** Right-click the manual in the inventory. There is
   **"Read the manual"** and there is **no** vanilla "Read", no "Write", and no
   "Look at pictures". That is what `ItemType = base:normal` buys: a Literature item
   would offer vanilla's own read, which sits the character down for hours.

### B — Opening the book

**While `CeroSec.DEV_MANUAL_MENU` is on** you do not need a copy of the book for any
of section B, C or D's first three steps: right-click any computer and take the last
entry, **Read the CeroSec manual (dev)**. Do steps 18-22 with a real item, though —
they are about the bookmark on the item, which the door does not have.

6. **It opens.** Right-click → **Read the manual**. A window appears in the middle of
   the screen, titled with the book's own title. Two cream leaves side by side, a
   darker band down each inner edge where the paper curves into the gutter, page
   numbers at the outer foot of each leaf, and three buttons under the book: **< Back**,
   **Contents**, **Next >**.
7. **The character does nothing.** The survivor does not sit, does not play an
   animation, and the queue stays empty. Walk around with the book open — it stays
   open and the character walks. Open a door, chop a tree, get bitten: the book is
   still there. It is paper on the screen, not an action.
8. **Page 1 is the title leaf.** The book's title centred, a rule under it, the
   edition line under that in the dimmer ink. Page 2 is **Contents**.
9. **Nothing is off the paper.** Look along the right margin of every leaf you turn.
   No line of prose runs past the edge of the cream, and no word is cut in half by
   the paper's edge.
10. **Example lines look like the terminal.** A line that starts with two spaces is
    drawn in the terminal's monospaced font, dark green, on a faint band, and it is
    **not** wrapped. Compare one against the same command typed at a real CeroSec
    screen: same face, same column spacing.
11. **Font size.** Options → the UI font size, up one notch and back. With the book
    open the leaves re-lay themselves, the reader stays on the page he was on, and
    still nothing runs past the margin.

### C — Turning the leaves

12. **Buttons.** **Next >** turns one sheet: both leaves change, and the page numbers
    go up by two. **< Back** turns one back.
13. **Keys.** Right arrow does what **Next >** does; Left does what **< Back** does.
    They work with the mouse anywhere, including outside the window.
14. **The ends.** At the front, **< Back** and Left do nothing at all — no flicker, no
    blank spread. At the back, **Next >** and Right do nothing. The last spread is
    never half a sheet: if the book ran out on a left leaf, the right one is blank
    paper.
15. **Chapters open a leaf.** Turn through the whole book. Every chapter starts at the
    **top** of a leaf, with its title as the running head, and no chapter begins
    halfway down the page before it.
16. **Contents.** Press **Contents**. The rows highlight under the cursor. Click the
    third one: the book opens at the third chapter's **first** leaf, and the running
    head on that leaf is that chapter's title. Do it for every chapter and check the
    printed page number on the row against the number printed at the foot of the leaf
    it lands on — those are two different pieces of arithmetic and they have to agree.
17. **Escape closes.** Press Escape. The book shuts, and the key does **not** also
    open the game's own menu behind it.

### D — Page memory

18. **It reopens where it was left.** Turn to some spread in the middle. Close the
    book with Escape. Right-click → Read the manual: the same two leaves.
19. **Across a save.** Same again, then save and quit to the main menu, and load. The
    book still opens on the same spread — the bookmark rides on the item's modData,
    which is saved with the item.
20. **One bookmark per copy.** Spawn a second manual. Leave the first on chapter four
    and the second at the front. Each one opens where **it** was left.
21. **Two windows, one player.** With the book open, right-click the **other** copy
    and read it. The first window closes; there is one book open at a time.
22. **The book leaves your hands.** With the book open, drop it on the floor. The
    window shuts by itself.

### E — Finding one in the world

The weights are in `42/media/lua/server/CeroSec/CeroSecManualLoot.lua`, with the
vanilla numbers each one was set against.

23. **The lists were found.** With `CeroSec.DEBUG = true`, the console says
    `manual added to 12 distribution lists` once, on load. Anything less than 12 names
    a list vanilla has renamed — the missing one is logged by name right above it.
24. **It is really in the pool.** Debug menu → **Spawn rate checker** (LootZed), pick
    `LibraryComputer`. `CeroSec.Manual` is in the list at weight 4, sitting beside
    `Book_Computer` at 20 and 10.
25. **Find one in an office.** New game, walk into an office building, and loot every
    desk in it. This is the rarest placing on purpose (weight 1 against a pool of
    about seventy, four rolls a desk) so it will take a building or two — the point of
    the step is that it happens at all, and that the one you find reads and turns
    exactly like the one you spawned.
26. **Find one where it belongs.** Go to the library, the bookshop or a cyber cafe and
    loot the computer shelves. This should take a handful of containers, not a
    building. If it takes as long as the office desks did, the weight did not take.
27. **Not everywhere.** Loot a kitchen, a wardrobe and a garage. No manuals. It is a
    computer book; it belongs with the computers.

### F — Multiplayer

28. **It spawns on a server.** The distribution file is a server file. On a hosted
    game, loot a library computer shelf as a client and the manual turns up.
29. **Two players, two books.** Two clients each with a copy, each on a different
    spread. Neither one's turning moves the other's book — the window is a client
    window and the bookmark is on the item each of them is holding.
30. **The bookmark is local.** A bookmark written on a client is not sent to the
    server. Hand the book to another player: he gets a book, and where it opens for
    him is not promised to be where you left it. That is deliberate — it is a
    bookmark, not machine state — and it is the one place the manual behaves
    differently from the terminal.

## Before release

`CeroSec.DEV_MANUAL_MENU` in `42/media/lua/shared/CeroSec/CeroSecDefs.lua` is a
testing aid and **must be `false` before anything goes to the Workshop.** It is a
door straight into a piece of documentation the player is supposed to find, and it
is on every computer in Knox County.

31. **Turn it off.** Set `CeroSec.DEV_MANUAL_MENU = false`. Right-click a computer
    that is **on**: "Turn off computer" and "Use computer", and no third entry.
    Right-click one that is **off**: "Turn on computer" and nothing else. Not a
    greyed-out entry, not a submenu — nothing.
32. **The book still works.** With the flag off, spawn a manual and read it from the
    inventory. Everything in sections B, C and D still holds: the door was a way in,
    not the way it works.
33. **The flag is the only thing that changed.** `git diff` on the release commit
    touches `CeroSecDefs.lua` and nothing else.
