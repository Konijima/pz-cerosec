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
