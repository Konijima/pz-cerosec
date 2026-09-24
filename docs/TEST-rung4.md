# CeroSec rung 4 — manual test checklist

See also [TESTING.md](TESTING.md) for the headless suites and the other rungs.

Build 42.20.4. Everything the headless benches cannot reach: the real world under
`/dev`. The engine's half is pinned character by character in `tests/os_test.lua`,
and the discovery is driven over a fake world in `tests/window_test.lua`, so what
is left here is the one thing neither can prove — that the Java calls do what
`javap` says they do, on a real map, with a second pair of eyes watching.

Do rung 2's checklist first, or at least its A and B sections: nothing here works
on a machine you cannot log into. Turn `CeroSec.DEBUG = true` in
`42/media/lua/shared/CeroSec/CeroSecDefs.lua` for the console lines.

Log in as `admin` (empty password) and `su root` (empty password). The devices are
`660`, owner `root`, group `sudo` — `admin` is in that group on a shipped machine,
so most of it works as `admin` too, and the Groups section below is where that is
deliberately proved. Everything under "Devices" is typed as root unless it says
otherwise.

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
    `light0: Permission denied`. `su root`, `chmod 666 /dev/light0`, `exit`, and
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
navigation, the bookmark on each copy and each volume, the dev submenu, the four item
blocks and the twelve loot lists times three volumes. It covers all of that against a
**fake** font, a **fake** shelf of volumes and a **fake** distribution table.
Everything below is the part where the real game gets a say. Turn
`CeroSec.DEBUG = true` in `42/media/lua/shared/CeroSec/CeroSecDefs.lua` for the
console lines.

**The text is three separate files.** `CeroSecManualUser.lua`, `CeroSecManualAdmin.lua`
and `CeroSecManualProgrammer.lua` in `42/media/lua/shared/CeroSec/` hold the chapters
of the three volumes and are written apart from the reader; each assigns itself into
`CeroSecManual.volumes`. If one is missing the others still open, and if all three are
missing the reader falls back to the single book `CeroSecManual` was before the set. A
volume with no chapters still opens — a title leaf and an empty contents — which is
itself worth one look (step 9).

## Manual

### A — The item exists and the game parsed it

1. **No script errors on load.** Start a game with the mod on. The console
   (`~/Zomboid/console.txt`) has no `FileNotFoundException` and no script parse error
   naming `items_cerosec.txt`. A single bad key takes the **whole file** down, so a
   silent load is the whole of this check.
2. **All three are in the item list, and only three.** Open the debug menu (or the
   admin panel) → **Items list**. Filter on `CeroSec`. `CeroSec.ManualUser`,
   `CeroSec.ManualAdmin` and `CeroSec.ManualProgrammer` are there and
   `CeroSec.Manual` is **not** — the old single-volume book was a second copy of
   volume one and was removed. Every display category reads **Literature**, and the
   names read **CeroSec OS User's Guide**,
   **CeroSec OS System Administrator's Guide** and **CeroSec OS Programmer's Guide**
   — the names from `Translate/EN/ItemName.json`, not
   the `DisplayName` fallback and not the raw `ManualUser`.
3. **Spawn all three volumes.** Spawn one of each into the character's inventory.
   Weight 0.8 each, and three **different** icons: the same book with the little green
   screen on its cover, bound blue and marked 1, green and marked 2, red and marked 3
   — and **not** the white question mark. A question mark means the texture did not
   resolve: check that the file is `common/media/textures/Item_CeroSecManualUser.png`
   exactly, since the game builds the name as `"Item_" .. Icon` and looks it up as
   `media/textures/<that>.png`. Look at the three side by side in the inventory: the
   number on each spine is readable at the size the inventory actually draws it.
4. **Drop one.** Drop a volume on the floor. There is a closed book model on the
   ground, it can be picked up again, and nothing is logged. (`WorldStaticModel`.)
5. **No vanilla read option.** Right-click each volume in the inventory. There is
   **"Read the User's Guide"** / **"Read the System Administrator's Guide"** /
   **"Read the Programmer's Guide"**, one option and the right one, and there is
   **no** vanilla "Read", no "Write", and no "Look at pictures". That is what
   `ItemType = base:normal` buys: a Literature item would offer vanilla's own read,
   which sits the character down for hours.
6. **All three at once.** Select all three volumes together and right-click. Three
   options, one per volume, in the order 1, 2, 3 — not one option, and not the same
   option three times.
7. **The old book is gone.** `CeroSec.Manual` cannot be spawned: it is not a
   declared item any more. Nothing anywhere offers **"Read the manual"** — that
   option and its translation key were removed with the item.

### B — Opening the book

**While `CeroSec.DEV_MANUAL_MENU` is on** you do not need a copy of the book for any
of section B, C or D's first three steps: right-click any computer, take the last
entry, **Read the CeroSec manual (dev)**, and choose a volume from the submenu behind
it. Do steps 22-27 with a real item, though — they are about the bookmark on the
item, which the door does not have.

8. **The door is a submenu of three.** Hover the last entry. Behind it: **User's
   Guide**, **System Administrator's Guide**, **Programmer's Guide**, in that order,
   and each one opens its own volume — check the cover of each. The parent entry
   itself opens nothing when you pass over it.

9. **It opens.** Right-click → **Read the User's Guide**. A window appears in the
   middle of the screen, titled with that volume's own title. Two cream leaves side by
   side, a darker band down each inner edge where the paper curves into the gutter,
   page numbers at the outer foot of each leaf, and three buttons under the book:
   **< Back**, **Contents**, **Next >**.
10. **The character does nothing.** The survivor does not sit, does not play an
   animation, and the queue stays empty. Walk around with the book open — it stays
   open and the character walks. Open a door, chop a tree, get bitten: the book is
   still there. It is paper on the screen, not an action.
11. **Page 1 is the title leaf.** The volume's title centred -- `CeroSec OS 1.0
   User's Guide`, the same version the boot banner and `/etc/motd` say, and the
   volume's own name after it -- a rule under it, and `First Edition, 1993` under that
   in the dimmer ink. Page 2 is **Contents**. Open the other two and check their
   covers say `System Administrator's Guide` and `Programmer's Guide`, with the same
   version number.
12. **A volume's contents is its own.** Page 2 of each volume lists that volume's
   chapters and **no** chapter belonging to either of the others.
13. **Nothing is off the paper.** Look along the right margin of every leaf you turn.
   No line of prose runs past the edge of the cream, and no word is cut in half by
   the paper's edge.
14. **Example lines look like the terminal.** A line that starts with two spaces is
    drawn in the terminal's monospaced font, dark green, on a faint band, and it is
    **not** wrapped. Compare one against the same command typed at a real CeroSec
    screen: same face, same column spacing.
15. **Font size.** Options → the UI font size, up one notch and back. With the book
    open the leaves re-lay themselves, the reader stays on the page he was on, and
    still nothing runs past the margin.

### C — Turning the leaves

16. **Buttons.** **Next >** turns one sheet: both leaves change, and the page numbers
    go up by two. **< Back** turns one back.
17. **Keys.** Right arrow does what **Next >** does; Left does what **< Back** does.
    They work with the mouse anywhere, including outside the window.
18. **The ends.** At the front, **< Back** and Left do nothing at all — no flicker, no
    blank spread. At the back, **Next >** and Right do nothing. The last spread is
    never half a sheet: if the book ran out on a left leaf, the right one is blank
    paper.
19. **Chapters open a leaf.** Turn through the whole book. Every chapter starts at the
    **top** of a leaf, with its title as the running head, and no chapter begins
    halfway down the page before it.
20. **Contents.** Press **Contents**. Each row is the chapter's title exactly as
    the chapter's own leaf is headed -- `1. Your machine`, not `1.  1. Your
    machine` -- with the page number right-aligned at the outer margin. The rows
    highlight under the cursor. Click the
    third one: the book opens at the third chapter's **first** leaf, and the running
    head on that leaf is that chapter's title. Do it for every chapter and check the
    printed page number on the row against the number printed at the foot of the leaf
    it lands on — those are two different pieces of arithmetic and they have to agree.
21. **Escape closes.** Press Escape. The book shuts, and the key does **not** also
    open the game's own menu behind it.

### D — Page memory

22. **It reopens where it was left.** Turn to some spread in the middle. Close the
    book with Escape. Right-click → Read the manual: the same two leaves.
23. **Across a save.** Same again, then save and quit to the main menu, and load. The
    book still opens on the same spread — the bookmark rides on the item's modData,
    which is saved with the item.
24. **One bookmark per copy.** Spawn a second User's Guide. Leave the first on chapter
    four and the second at the front. Each one opens where **it** was left.
25. **One bookmark per volume.** Turn the User's Guide to the middle and close it.
    Open the Programmer's Guide: it opens at **its** front, not at the User's Guide's
    spread. Turn it somewhere else, close it, and reopen the User's Guide — still
    where you left it. Do the same through the dev door, with no copies in the
    inventory at all: the door keeps a bookmark per volume too, for the session.
26. **Two windows, one player.** With a volume open, right-click **another** volume
    and read it. The first window closes; there is one book open at a time.
27. **The book leaves your hands.** With the book open, drop it on the floor. The
    window shuts by itself.

### E — Finding one in the world

The weights are in `42/media/lua/server/CeroSec/CeroSecManualLoot.lua`, with the
vanilla numbers each one was set against.

28. **The lists were found.** With `CeroSec.DEBUG = true`, the console says
    `the manual set added in 36 places` once, on load — twelve lists times three
    volumes. Anything less than 36 names a list vanilla has renamed — the missing one
    is logged by name right above it, once for the list and not once per volume.
29. **All three are really in the pool, and the old one is not.** Debug menu → **Spawn
    rate checker** (LootZed), pick `LibraryComputer`. `CeroSec.ManualUser` is in the
    list at weight 4, sitting beside `Book_Computer` at 20 and 10;
    `CeroSec.ManualAdmin` at 2 and `CeroSec.ManualProgrammer` at 1, in that order.
    `CeroSec.Manual` is **not in the list at all** — and not an item either, since
    it was removed.
30. **Volume three is raised where the programmers were.** Same checker, pick
    `UniversityDesk_Computer`: `CeroSec.ManualProgrammer` is at **2**, the same as
    `CeroSec.ManualAdmin`, not at 1. Same again for `UniversityLibraryComputer`,
    `BookstoreComputer` and `ElectronicStoreMagazines`.
31. **Find one in an office.** New game, walk into an office building, and loot every
    desk in it. This is the rarest placing on purpose (the User's Guide at weight 1
    against a pool of about seventy, four rolls a desk) so it will take a building or
    two — the point of the step is that it happens at all, and that the one you find
    reads and turns exactly like the one you spawned.
32. **Find one where it belongs.** Go to the library, the bookshop or a cyber cafe and
    loot the computer shelves. This should take a handful of containers, not a
    building. If it takes as long as the office desks did, the weight did not take.
    The one you turn up is most often the **User's Guide**: that is the set working as
    printed, not a bug.
33. **Not everywhere.** Loot a kitchen, a wardrobe and a garage. No manuals of any
    volume. It is a computer book; it belongs with the computers.

### F — Multiplayer

34. **It spawns on a server.** The distribution file is a server file. On a hosted
    game, loot a library computer shelf as a client and the manual turns up.
35. **Two players, two books.** Two clients each with a copy — different volumes, or
    two copies of one — each on a different spread. Neither one's turning moves the
    other's book: the window is a client window and the bookmark is on the item each
    of them is holding.
36. **The bookmark is local.** A bookmark written on a client is not sent to the
    server. Hand the book to another player: he gets a book, and where it opens for
    him is not promised to be where you left it. That is deliberate — it is a
    bookmark, not machine state — and it is the one place the manual behaves
    differently from the terminal.

## Groups

The engine's half is pinned in `tests/os_test.lua` (section 22) and the device half
is driven over a fake world in `tests/window_test.lua`. What is left here is what
only a real machine, a real save and a second player can show.

Do this on a computer in a base, with two accounts that are not `root`.

34. **What ships.** `cat /etc/group` on a fresh machine: the two comment lines, then
    `root:`, `sudo:admin`, `users:admin`. `ls -l /etc` shows it `-rw-r--r--  root
    root`, and `id` as `admin` says `uid=admin flag=user groups=admin,sudo,users`.
35. **A device needs no sudo.** Log in as `admin` and do **not** `su`. `echo on >
    /dev/light0` — the light comes on in the room, no password is asked, nothing is
    printed. That is `crw-rw----  root  sudo` doing its job.
36. **And an ordinary account gets nothing.** `sudo adduser bob`, `passwd bob`, then
    log out and log in as `bob`. `echo off > /dev/light0` answers
    `light0: Permission denied` and the light **stays on**. `ls -l /dev` still
    lists everything: the listing is the directory's business, not the device's.
37. **Sudoers is the way in.** As root, `edit /etc/sudoers`, add a line `bob`, save.
    As `bob`: `id` now says `groups=bob,sudo`, and `echo off > /dev/light0` works.
    Take the line out again and it stops working. No reboot in between.
38. **Sharing a directory, for real.** As `admin`: `sudo groupadd crew`,
    `sudo gpasswd -a bob crew`, `mkdir /home/admin/shared`,
    `chgrp crew /home/admin/shared`, `chmod 770 /home/admin/shared`,
    `chmod 755 /home/admin`. As `bob`: `cd /home/admin/shared`, `write note.txt hi`,
    `ls -l` — the file is there, owner `bob`, group `bob`. As `admin`: `cat
    /home/admin/shared/note.txt` prints `hi`.
39. **And a third account does not get in.** `sudo adduser kate`, log in as `kate`,
    `ls /home/admin/shared` → `permission denied`. `cd` into it, same.
40. **The middle digit is the one that moved.** As `admin`,
    `chmod 700 /home/admin/shared`. As `bob`, `ls` it → `permission denied`. Back to
    `770` and he is in again. Nothing else was touched.
41. **A dangling group.** As root, `groupdel crew`. `ls -l /home/admin` still shows
    `crew` in the group column; `bob` can no longer get in; `chgrp crew
    /home/admin/shared` answers `chgrp: crew: no such group`. `groupdel root`,
    `groupdel sudo` and `groupdel users` all answer `cannot remove`.
42. **It survives a save.** Quit to the main menu and load again. `cat /etc/group`
    is what you left it, `ls -l /home/admin` still shows the group you set, and
    `bob` still gets in or does not, exactly as before.
43. **An older machine is topped up, not rewritten.** Load a save made before this
    rung. `/etc/group` is there with the shipped three, `/bin` has `chgrp`,
    `gpasswd`, `groupadd`, `groupdel` and `groups` in it, and **every file that was
    already on the disk still lists its owner's own name in the group column** —
    nothing walked the disk to write a field into it.
    Then the other half of that rule: as root on a current machine,
    `rm /etc/group`, quit, load. It stays gone — the top-up runs once and root
    deleting a file is root's right, not damage. `groups admin` now says just
    `admin sudo` (the primary group, and `sudo` off `/etc/sudoers`), and the BIOS
    is what puts the file back (next step).
44. **The BIOS keeps a group file that still parses.** As root, `edit /etc/group`,
    leave one real line in it, save. `rm -r /bin`, then `reboot`. Answer `y` at
    `Restore system? (y/n)`: the commands come back and `/etc/group` is still the
    one line you left. Now `edit /etc/group` down to nothing but a comment and
    repeat: this time it comes back as the shipped three.
45. **Two players, one machine.** Player 1 as `admin` and player 2 as `bob`, both at
    the same computer. Player 1 runs `sudo gpasswd -a bob users`; player 2 types
    `groups` and sees `bob users` on his own screen without touching anything. One
    console, one filesystem, no cache anywhere to go stale.
46. **The listing still fits.** `ls -l /` , `ls -l /etc`, `ls -l /bin` and
    `ls -l /dev`: no line wraps, nothing is cut but a name, and a long name ends in
    `~`. `sudo adduser administrator` and `ls -l /home` — the owner column reads
    `admin~`.

## Before release

`CeroSec.DEV_MANUAL_MENU` in `42/media/lua/shared/CeroSec/CeroSecDefs.lua` is a
testing aid and **must be `false` before anything goes to the Workshop.** It is a
door straight into a piece of documentation the player is supposed to find, and it
is on every computer in Knox County.

37. **Turn it off.** Set `CeroSec.DEV_MANUAL_MENU = false`. Right-click a computer
    that is **on**: "Turn off computer" and "Use computer", and no third entry.
    Right-click one that is **off**: "Turn on computer" and nothing else. Not a
    greyed-out entry, not a submenu — nothing.
38. **The books still work.** With the flag off, spawn all three volumes and read
    each from the inventory. Everything in sections B, C and D still holds: the door
    was a way in, not the way it works.
39. **The flag is the only thing that changed.** `git diff` on the release commit
    touches `CeroSecDefs.lua` and nothing else.
