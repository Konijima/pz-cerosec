# CeroSec — Architecture

The engine (a pure-Lua OS with no game dependency), the server layer that gives it
a world to run in, and the client that draws it on a screen. Filesystem, accounts,
groups, the system files, the BIOS, the manual reader, and how a computer's state
is saved.

See also: [PROTOCOL.md](PROTOCOL.md) for the client/server wire messages,
[DEVICES.md](DEVICES.md) for `/dev` and the floppy's own filesystem,
[SCRIPTING.md](SCRIPTING.md) for the step machine and the scheduler,
[CONTRIBUTING.md](CONTRIBUTING.md) for the load-order trap and the coding rules.

## The engine door

`42/media/lua/shared/CeroSec/OS/` is a pure-Lua OS engine. It makes no game call,
touches no `os`/`io`/`require`, no coroutines and no metatables, so it runs the same
under a plain `lua5.1` and under the game's Kahlua.

There is **one** door in, and it is the script engine:

```
CeroSecOS.promptJob(state, session, line, vars, status, name) -> job, refusal
CeroSecOS.jobStep(state, job, env, budget)                    -> status, spent
```

A typed line is parsed by `CeroSecOS.parseScript` and becomes a job; the caller
steps it. There used to be a second, simpler path for one-command lines
(`CeroSecOS.exec` over `CeroSecOS.parseLine`, with `splitBackground` for a trailing
`&`) and all three are **gone** — that second parser is the bug this rung fixed, and
it must not come back. A command already split into words still has its own entry
point, `CeroSecOS.runArgs(state, session, args, redirect, env)`, which is the door
both a job and `sudo` reach a command through.


## The server and the client

On top of the engine sits a server-authoritative `SGlobalObject` system
(`SCeroSecObject`, `SCeroSecSystem`) that holds each computer's OS state and, while
it is on, a console:
`{ booted, user, cwd, pending, lines, prompt, edit, halted, shvars, status, job }`.
`shvars` is the shell's own variables and `status` its `$?` — the prompt is an
environment, not a series of unrelated commands, and both are machine state saved
with the console and sanitised by `CeroSec.repairConsole` on the way back in
(`MAX_VARS`, `MAX_VAR_BYTES`, exactly a job's ceilings). There is one console
per computer, not one per player — that is what makes walking away and coming back
find the same screen, and two players at one computer share it. The client mirror
(`CCeroSecObject`, `CCeroSecSystem`) never holds the filesystem or the screen; it
only shows the sprite and relays input.

The context menu, the reach checks and the terminal window are all client-side;
the wire between them and the server — the message list, the screen shape and
who a token addresses — is [PROTOCOL.md](PROTOCOL.md).

## The right-click that finds the computer

The whole of this is proved out of the jar in
[notes/picking.md](notes/picking.md), with the bytecode offsets; the shape of it is

**The game hands the menu one object.** `UIManager.update` calls
`IsoObjectPicker.ContextPick(mx, my)` on every mouse **move** and stores the one
`ClickObject` it answers; the right-button release fires
`OnObjectRightMouseButtonUp` with that object's `tile`.
`ISObjectClickHandler.doRClick` builds `worldobjects` out of it plus six `Pick*`
calls — a door, a window, a window frame, a thumpable, a hoppable, a tree — none
of which is ever a computer. So `worldobjects` is **one** object, and the
`Tile Report` / `Room Report` lines the game's debug menu prints are that object
and its own square.

**`ContextPick` is not a square walk.** It gathers every object that was rendered
near the point (`getObjectsAt`, `getObjectsOnSquare`), tests each against the box
the **renderer** recorded for it (`ObjectRenderInfo.renderX/renderY/renderWidth/renderHeight`)
and then against that object's own alpha mask (`IsoObject.isMaskClicked`), scores
every survivor with `ClickObject.calculateScore`, and returns the highest. A
sprite raised onto a table is handled exactly right, because `renderY` already
carries the raise. A lamp on a table is picked by its own pixels; so is a monitor.

**But the score is not distance.** A desk chair carries `IsoFlagType.bed`, worth
`+2`, where a plain computer gets nothing from that chain, and the chair stands on
the player's own square so it pays almost none of the Manhattan penalty. With the
cursor on the monitor of a computer on a desk and a chair pulled up in front of
it, the game considers both and — when the chair's back reaches up into the
monitor's band — hands the menu the **chair**, whose square is one step south of
the desk's.

So `CeroSecContextMenu.findComputer` asks in this order:

1. **is the object the game handed over a computer**, or is a computer on its
   square? A computer on the very desk the cursor found is answered here, and the
   square scan is the pattern vanilla's own one-device menus use
   (`ISRadioAndTvMenu.lua:16-26`, `ISBBQMenu.lua:20`). A joypad has no mouse and
   stops here.
2. **otherwise the mouse itself**, `CeroSecReach.pickComputer`: rebuild each nearby
   computer's drawn box and ask its own click mask — the same test the game settles
   on. A computer whose pixels are under the cursor wins; nothing refuses a hit
   because something else was picked first.

That order is a choice and it has one edge: two desks side by side, each with a
computer, and the cursor on the *left* monitor while the game resolves the click to
the *right* desk. Pass 1 would then answer with the right-hand computer where the
mask would have answered with the left-hand one. It is kept that way deliberately —
the game's own resolution is the engine's answer and our box arithmetic rests on one
assumption the engine alone can settle (that `getCameraOffX()` is
`IsoCamera.frameState.offX` when the menu is built), so deferring to the game first
fails safe. `docs/PARCOURS-TEST.md` step 12e is the click that checks it.

`CeroSecReach.drawnBox` is the renderer's three terms and not two:
`ISCoordConversion.ToScreen` for the square's anchor, less
`IsoObject.getOffsetX()` and `getOffsetY()` — which are `32 * tileScale` and
`96 * tileScale`, set in the constructor and never zero — less
`getRenderYOffset() * tileScale` for the raise. A box of `64 × 128` tile units,
because a 64×128 texture is drawn at `tileScale` and a 128×256 one at half of it,
and the mask index divides back down by whichever it was.

`CeroSecReach.pickSquares` takes its candidates from the **mouse's own iso tile**
and not from the square the game picked. That anchor is vanilla's own: the world
menu resolves the mouse the same way, in the same call chain and behind the same
joypad guard — `ISCoordConversion.ToWorld(_x * getCore():getZoom(n), _y * ..., z)`
then `getCell():getGridSquare(wx, wy, z)`, `ISMenuContextWorld.lua:76-79`. It is
also why the `media/lua/server` folder `ISCoordConversion` lives in is reachable
from the client at all — that square is itself somewhere inside the staircase the game
walked out of the mouse, so walking a forward-only staircase again out of it points
away from the start. The window is derived rather than guessed: with `s = x + y`
and `d = x - y`, a square's box contains the point only for
`s(mouse) - 2 + raise/16 <= s <= s(mouse) + 6 + raise/16` and
`|d - d(mouse)| <= 1`, and `raise` never exceeds `SURFACE_MAX` = 64 —
`PICK_BEHIND = 2`, `PICK_AHEAD = 6 + 64/16 + 2 = 12` (the last two steps are the
flooring of the two iso coordinates), `PICK_SIDE = 1`. `s` and `d` share a parity,
which is why the game's own candidates read as a staircase and why half the pairs
in that window name no square.

While `CeroSec.DEBUG` is on, every right-click leaves in the log ring the debug
window's **Log** tab reads: the sprite and the square of everything the game handed
over, then every candidate the mask pass weighed with its box, its raise and
whether the mask took it. A miss in game is a line to read.

## Standing at a computer

`CeroSecReach.lua` answers where the player has to be: the **front square** is the
neighbour the screen looks at (`CeroSec.frontOffset`), and every action of the mod
refuses to run anywhere else. Reaching is that square plus a height —
`CeroSecReach.height` reads the surface the computer stands on and calls it `low`
(the floor, a crouched animation), `mid` (a desk) or `high` (out of reach, the
option greyed out).

Inside that square the mod aims at a **point**, not at the tile, because a tile is
a metre wide and the game reads the character's float position for everything that
follows. Two points:

* the **seat point** when there is a chair in front of the screen — the place the
  game itself would stand him in to take that chair from the front
  (`SeatingManager:getAdjacentPosition`, the very call `ISRestAction` scores its
  twelve candidates with). The seat the character ends up in is chosen by nothing
  but where he stands, so a walk to the middle of the square used to end in a
  character sitting down sideways at a screen he had asked to read.
* the **stand point** when there is not: `CeroSec.standPoint`, which is
  `CeroSec.STAND_INSET` of a tile off the middle of the front square, toward the
  computer, and centred on the other axis. A computer facing south has its front
  square to the south and the player stands in the north part of it; the other
  three facings are derived from `FRONT_OFFSET` and cannot disagree with it. The
  middle of the square is a visible step short of the desk — the character typed
  at the air — and the inset is what closes it.

The walk is `ISPathFindAction:pathToLocationF`, which takes floats and is what
vanilla itself uses to put a character at a point inside a tile
(`ISCampingMenu.lua:476` and `:505`, 0.2 or 0.8 into the adjacent tile, toward the
campfire). It is never skipped for a player who is already on the square: paths to
a SQUARE are satisfied by a character standing anywhere in it, which is how
"already next to the computer" produced both bugs. `CeroSecTerminal:resettle` is
the same rule while the window is open — a click that hands the keyboard back also
puts the character back, on the chair if there is one and on the stand point if
there is not, and only when he is more than `CeroSec.STAND_NEAR` from it. The
turn itself is never walked: it is `ISCeroSecTypeAction:waitToStart`.

What the inset can promise is where the pathfinder aims, and therefore which seat
the game picks and where the character comes to rest. What it cannot promise is
contact with the desk sprite: a character is a 0.24-wide moving object
(`IsoMovingObject.width`, javap'd) and that width only ever separates him from
other characters, while a solid table blocks its own square and nothing inside
ours — so the number is a look, not a collision. It is **tuned by eye in game**,
and it is one constant.

## The chunk that goes away

A computer keeps the state it had while its chunk is not loaded. It stays on, it keeps
its jobs, its pending `shutdown` and its crontab, it goes on answering the wire, and
its disk goes on being written — none of the five is a thing in the world. Only what
the world owns goes with the chunk: `/dev`, the sensor heads, and the power question
itself.

The power question is the one that used to get this wrong. `SCeroSecObject:hasPower()`
asks the machine's **square** (`haveElectricity()`, or `hasGridPower()` in a room —
the same test `ISWorldObjectContextMenu.lua:460` makes), and a chunk the streamer has
taken away has no square at all, so `false` from it means *there was nobody to ask*
and not *the room has no wire*. The minute sweep read it as the second and switched
off every computer the survivor had walked away from — the bug behind "I go far, and I
come back and they are off". So the decision lives in one place,
`SCeroSecObject:checkPower()`, and it refuses to decide anything about a machine the
world has not got: `isLoaded()` (the `IsoObject`, which is the stricter of the two
handles) first, `hasPower()` second. `SCeroSecSystem:checkPower()` — the
`EveryOneMinute` sweep — calls exactly that, and so does `stateToIsoObject`, which is
the chunk arriving: **the power check happens on the next load**, at the first moment
there is a room to ask, so a machine whose generator ran dry while you were away is
lit until you walk back in and dark by the time you can see it. Coming back also
re-applies the sprite and announces the object to the client, which is what puts the
screen's glow back (`newLuaObjectOnClient` → `CCeroSecSystem:newLuaObjectAt` →
`CCeroSecObject:syncLight`).

### What the minute sweep walks

`gos_cerosec.bin` holds **every** computer in the county — every one that has ever
been switched on, its chunk loaded or not — and the sweep does not walk it. The system
keeps two indexes, neither of them saved (`setModDataKeys` names the four fields that
are):

| | |
| --- | --- |
| `onMachines` | every machine that is **on**. The power question, the watcher eviction, `/dev`'s refresh, cron's minute and the `at` queue are about those and only those: a dark machine answers nothing to any of them. |
| `newMachines` | every machine whose square was made in this save and has not been settled yet (`born`). These may be **off** and still have to be visited — the automation's question is what switches one on. |

They are written by every place `on` and `born` are written, through one function that
reads the machine rather than being told what changed (`SCeroSecObject:reindex`); a
machine arriving is caught by `newLuaObject`, which the engine calls for every object
in the save file at load with the saved fields already in the table, and one leaving by
`aboutToRemoveFromSystem`. An entry that is neither `on` nor `born` when the sweep
reaches it is **dropped there and then**, so a transition nobody reported costs one
visit and never a machine that is swept for ever.

What it is worth, measured: at 300 machines with 40 on, the county walk was about 3 ms
of the 100 a game minute costs — a dark machine cost four field tests — and what the
index buys is that the number does not move as the file grows (40 of 1000 visited for
the same milliseconds; `tests/hostile_test.lua`, the county block). The 100 ms is the
state validator, once per running machine per read of its state, and that is the next
thing to look at rather than the walk.

**The glow is the cell's, not ours.** The light is one `IsoLightSource` on the cell's
lamppost stack (`getCell():addLamppost`), and the engine takes it off that stack
whenever the square leaves the loaded window: `LightingJNI.checkLights` walks
`IsoCell.getLamppostPositions()` and removes any source whose `isInBounds()` is false —
inside some player's `IsoChunkMap` world tiles — or whose recorded `chunk` is not the
chunk now covering its square (`javap -c`: `checkLights` offsets 78-123,
`IsoLightSource.isInBounds`). It tells nobody, and the handle `addLamppost` returned
goes on existing. So `CCeroSecObject:hasLight()` asks the CELL — `getLightSourceAt` at
our square, identical to our handle — and never `self.light` on its own: reading "I have
a handle" as "there is a light" is what left a teleport across the county with a lit
sprite and no glow, for ever, since `addLight` then refused to ask for another. There is
no sweep: `syncLight` is called from the four events that can change the answer — the
announce (a chunk arriving, and the first time a client hears of a machine at all), the
update, the removal packet, and `OnObjectAboutToBeRemoved` for a pickup — and on the
announce the state is read off the sprite the chunk brought (`onFromSprite`), because
Java copies the announced fields into our table only *after* `newLuaObjectAt` returns
and never calls `OnLuaObjectUpdated` on that path (`javap -c CGlobalObjectSystem`:
`OnLuaObjectUpdated` is named only inside `receiveUpdateLuaObjectAt`).

This is vanilla's own habit with a global object it cannot see:
`SCampfireSystem.lua:157-159` skips a campfire whose square is gone — *"if campfire is
burning (and still there, I mean not destroy because of streaming)"* — and so does
`lowerFirelvl` at `:100-101`, while `lowerFuelAmount:135-138` goes on burning its fuel
regardless, because the fuel is the fire's own state and not the world's.

**A chunk unloading is not a removal.** `Events.OnObjectAboutToBeRemoved` is triggered
in exactly two places in 42.20.4: `IsoGridSquare.RemoveTileObject(IsoObject, boolean)`
(`javap -c`: `LuaEventManager.triggerEvent` at offset 177) and
`RemoveItemFromSquarePacket` — a player or the network taking the object off its
square. `IsoChunk` never calls `RemoveTileObject`; what it fires when it lets its
squares go is `ReuseGridsquare` (`IsoChunk.doReuseGridsquares:3044`). So the vanilla
handler that removes the Lua object — and with it the disk, the jobs and every session
— runs when the computer is picked up or smashed, and never because somebody walked
away. Nothing here overrides it.

`tests/window_test.lua` has the whole rule: a machine with a session open on it and a
crontab due loses its square, its `IsoObject` and its room; ten minutes of the sweep
leave it on, the session alive and cron firing every minute; `dev light0 on` answers
`light0: no such device`; the chunk comes back with a wire and it is still on with its
sprite and its glow put back; the chunk comes back to a dark room and it goes off at
that first check, not a minute later; and the control — a machine the sweep **can**
see loses its power and goes off on the next minute. The glow has its own bench in the
same section, with the real `CCeroSecSystem` and `CCeroSecObject` on a fake cell that
keeps a lamppost stack and drops it with the chunk the way `checkLights` does: one light
while the machine is lit, none while the chunk is away, exactly one again when it comes
back however many times the square is announced, none for a machine switched off out of
view, and the light following the object through a pickup and a placement.

## The clock

The engine has no clock and asks for none. `env.now` is one number — seconds since
1970-01-01 00:00:00, counted on the *game's* calendar — and it is handed in at every
`exec` and `continue`. `env` is optional: without it the machine has no clock, `date`
answers `date: no clock`, and nothing is stamped. That is what lets a test pin every
timestamp to a fixed moment.

The server builds it in `SCeroSecSystem:clockEnv()` from `getGameTime()`:
`getYear()`, `getMonth() + 1`, `getDay() + 1`, `getHour()`, `getMinutes()` — the
month and the day are 0-based in `zombie.GameTime`, which is why vanilla adds one to
them everywhere it prints them and why `getDayPlusOne()` exists. There is no
`getSeconds()`: the game's finest hand is the minute, so the second is always `:00`.

## Owners, groups and the mode

A node is `{ type, owner, group, mode, ... }`. `group` is a plain string and it is
**optional**: every node of every machine saved before `SYSTEM_VERSION` 5 has none,
`validate` accepts that and refuses a `group` that is not a string, and
`CeroSecOS.groupOf(node)` reads a missing one as the node's `owner` — nothing
anywhere reads `node.group` off the field. `newFile` and `newDir` set it to the
owner's own name, which is that account's primary group, so a fresh file starts
shared with nobody. `chown` moves the owner and leaves the group; `chgrp` moves the
group and leaves the owner; `cp` gives the copy the caller's name for both.

`CeroSecOS.can(state, session, node, what)` is the only place a permission is
decided, and it reads exactly one digit:

1. `root` bypasses everything, before anything else is asked — except `what ==
   "x"` on a node that is not a directory, which needs at least one of the three
   `x` bits set (4.4BSD `vaccess()`: root may not execute what nobody may).
2. `node.owner == session.user` — the **first** digit, and the other two are never
   consulted for him even if he is also in the group.
3. `CeroSecOS.inGroup(state, user, CeroSecOS.groupOf(node))` — the **middle** digit.
4. Otherwise the **last** digit.

`inGroup` is true for three things and no others: the primary group (`user ==
group`), a line in `/etc/group` naming the user, and — for the group `sudo` alone —
a line in `/etc/sudoers`. It takes `state` because those two files are the answer,
and it tolerates a `nil` state (a machine with no files parses to no groups, which
leaves the primary groups working).

Every node may carry an `mtime`, that same number. It is absent on every node saved
before this build and on everything a fresh machine ships with; absent means 0, read
through `CeroSecOS.mtimeOf` and never off the field, and `validate` accepts a node
without one. The four mutators (`createNode`, `removeNode`, `setData`, `moveNode`)
take the clock as a last argument and `nil` means "no clock": the mutation happens,
nothing is stamped. This machine has one timestamp where Unix has three, so it stands
for `mtime` and `ctime` both — a `chmod` and an `mv` move it. A create or a remove
also moves the *parent directory's* stamp, because a directory's date is when its
listing last changed.

`date +FORMAT` prints that number's pieces, `CeroSecOS.formatTime`'s way: `%Y %m
%d %H %M %S %j %a %b %e %s %%`, padded the way Unix pads them (`%d` is `08`, `%e`
is ` 8`), with anything else — an unknown code, a `%` at the end of the format —
copied out exactly as it was typed rather than silently swallowed. `%s` is
`env.now` itself, the very number a node's `mtime` carries, which is what a script
on the machine does arithmetic on. No clock stays no clock with a format: `date
+%s` on a machine with none answers `date: no clock` rather than handing out a
zero.

`CeroSecOS.DISK_BYTES` is the one number for the drive: the BIOS announces it
(`CeroSec.bootLines()` appends `hda 64K`), `df` divides by it, and the write path
refuses to go past it. There is no second copy of it anywhere to drift.

## System files, and their formats

*used* is what is in that filesystem, and each of these files is the truth about
what it holds — there is no table of users beside `/etc/passwd`, no list of commands
beside `/bin`, no list of sudoers beside `/etc/sudoers` and no table of groups
beside `/etc/group`. Root editing one of them
with the editor changes the machine, and `rm -r /bin` really does take the commands
away. The way back is the BIOS, not a guard rail on the command: root keeps full
power, and the protection is that root has a password.

**`/bin`** — one file per shell command, owner `root`, mode `755`, contents the
one-line description. It is the **first** directory a bare name is looked for in,
and `/usr/local/bin` — empty, root's at 755, seeded on every machine by
`CeroSecOS.ensureLocalBin` at `SYSTEM_VERSION` 21 — is the second and last unless
somebody widens `PATH`: nothing there, no `/bin` at all, `/bin` a
file, a directory called `/bin/ls`, or a file with no Lua command behind it are all
`<name>: command not found`; a file without `x` for this user, or a `/bin` he cannot
read, is `<name>: permission denied`. A **link** at a name in `/bin` is not one of
the machine's executables — what runs is the file it points at, as a script. The words with no file are the shell's own —
`cd`, `exit`, `fg`, `jobs`, `wait` (marked `shell` in `COMMAND_INFO`, so `binNames`
never seeds one) and the engine's `read`, `shift`, `break`, `continue`, `history` — plus
`help`, which has a file and is run without it; `CeroSecOS.BUILTINS` is that set and
is derived from the table, not listed beside it. `SYSTEM_VERSION` 8 **deletes** a
stale `/bin/cd`, `/bin/exit`, `/bin/jobs` or `/bin/wait` left by an earlier version,
and only where the file is exactly what was shipped (owner `root`, mode `755`, the
seeded description); anything else at that name is a player's own file and stays.
`restoreSystem` never recreates them.

**`/var`** — what the machine writes about itself. Four directories, made by
`CeroSecOS.ensureVar` for a fresh machine, for an older one being topped up and for
the BIOS repair alike, and never put back behind a root who deleted them:

- `/var/spool/cron` (`root`, **700**) holds one crontab per account, named after it,
  each `root` and `600`. Nobody reads or writes his own directly: `crontab` is the
  only way in, which is real Unix's setuid-root `crontab(1)` and the reason a line
  can be trusted to run as the account it belongs to. `crontab -e` opens the editor
  with `user = "root"` and `crontab = true` on the order, and that second flag is
  what makes `Commands.editsave` judge the buffer with `CeroSecOS.checkCrontab` and
  refuse it whole.
- `/var/log/cron` (`root`, `640`) is where a real one would call syslog. Bounded to
  `CRON_LOG_LINES` (100) and `CRON_LOG_BYTES` (4096), oldest dropped.
- `/var/mail/<user>` (the account's own, `600`) is a cron job's output. Bounded to
  `MAIL_LINES` (100) and `MAIL_BYTES` (4096), oldest dropped, with the mbox `From`
  line and cron's own `Subject` written once per job. `mail` prints it and empties it.

The log and the mailboxes are **exempt from the 64 KB disk quota**, by their path and
by nothing carried on the node, exactly as `~/.sh_history` is:
`CeroSecOS.exemptPaths` maps each exempt path to its owner, its own ceiling and its
*kind*, and the kind is what lets the history's four-file ceiling be asked about
histories alone. Rename one and it costs the disk from that moment on.
`CeroSecOS.MAX_EXEMPT_BYTES` is the machine-wide total and is written as the sum of
the three ceilings it is made of.

**`/etc/passwd`** — the accounts, owner `root`, mode `600`, one a line:

    name:$cs1$<salt>$<32 hex digits>:home:admin|user

Parsing is strict and silent: a line is skipped when it is not exactly four fields,
when the name is not a valid name, when the second field is not one of our `$cs1$`
strings, when the home is not an absolute path of `[A-Za-z0-9._/-]`, or when the
last field is neither `admin` nor `user`. A name that appears twice keeps its
**first** line, and a file that parses to nothing is a machine nobody can log in to
— which is the BIOS' business, not an error. The kernel reads it without going
through the permission bits (`CeroSecOS.systemNode`), because nobody is logged in
yet; that is the one read in the whole core that does not go through `getNode`. It
is parsed on demand and cached in one slot keyed on the node **and its text**, so
any write invalidates the cache by construction. `passwd` rewrites the whole file
through the ordinary `setData`, so the ceilings and the printable rule apply and a
refusal leaves it byte for byte as it was.

`useradd` **appends** its line and `userdel` drops every line that names the
account, keeping every other line exactly as it lies — comments and unparseable
lines included; only `passwd`, which has to touch a line in the middle, rewrites
the file from what it parsed. Both go through the ordinary `setData`, so a full
disk refuses a `useradd` the way it refuses a `touch`. The name a machine will
*make* is narrower than the name it will *parse*: `[a-z][a-z0-9_-]` up to sixteen
characters, so that it is always a name a prompt, a home directory and an `ls -l`
owner column can hold — while a machine that has been running a while keeps
whatever accounts are already in its file. The names are System V's since
`SYSTEM_VERSION` 16 — `useradd`, `userdel`, `usermod`, 1989, and what Solaris 2
shipped in 1992; `adduser`/`deluser` are Debian's and a decade late for a 1993
machine, so their `/bin` files are **deleted** at that top-up
(`CeroSecOS.RETIRED_BIN`).

The last field, `admin` or `user`, still grants nothing by itself: nothing in the
core reads it except the prompt, which wears `#` for an `admin` account and `$` for
a `user` one, and `id`, which prints it. What it *reports* since 16 is whether the
account is in `wheel` — `useradd -G` and `usermod -G` write it from that membership,
so the field and the group never disagree about an account either has touched. This
is what replaced the `adduser -a` "admin flag", which no command ever consulted:
4.4BSD gates `su` on `wheel`, sudo of the era takes a `%group` line, and the shipped
`/etc/sudoers` carries `%wheel` — so the group really is what grants root.
Deliberately **not** migrated: an account whose old line says `admin` is not put in
`wheel`, because the flag never granted anything and a top-up that handed it root
would be giving away a power the machine never had.

**`/etc/sudoers`** — who may `sudo`, owner `root`, mode `440`, one name a line with
an optional ` NOPASSWD` after it. A word beginning `%` is a **group**, which is
sudo's own syntax: every account in it may run a command as root, and the shipped
file carries `%wheel`. Blank lines and lines whose first non-blank character is `#`
are comments; anything else that is not a name or a `%group`, optionally followed by
the single word `NOPASSWD`, is skipped, and a name that appears twice keeps its
first line. `CeroSecOS.sudoer` walks the file in order and the **first** line that
matches the account wins, by name or by group — so `kate NOPASSWD` above `%wheel` is
kate not being asked. Group lines are resolved with `CeroSecOS.inGroupFile`, which
reads `/etc/passwd` and `/etc/group` only: `inGroup` mirrors *this* file for the
group called `sudo`, and a `%sudo` line read through it would ask itself who may
sudo. Same one-slot content-keyed cache as the accounts. Root is never looked up in
it: an `/etc/sudoers` with nobody in it must not be able to take `sudo` from the one
account that can put it back.

**`/etc/group`** — the groups, owner `root`, mode `644`, one a line:

    name:member,member,...

Parsing is as strict and as silent as the other two: a line is skipped when it is
not exactly one colon, a valid name in front of it, and behind it a possibly empty
list of valid names separated by commas — so `crew:admin,` and `crew:,admin` are
both dropped whole rather than half read. Blank lines and lines whose first
non-blank character is `#` are comments, a name that appears twice keeps its
**first** line, and the same one-slot cache keyed on the node and its text applies.
A machine ships with `root:`, `sudo:admin`, `users:admin` and `wheel:` — wheel
**empty**, so a shipped machine is exactly the machine it was: `admin` may `sudo`
because `/etc/sudoers` names him, and `wheel` is the door an administrator opens
for somebody else.

Every account is additionally in a **primary group of its own name**, with no line
anywhere: `bob` is in group `bob` whether `/etc/group` mentions him or not, and
`useradd` writes nothing here unless `-G` names a group. That is what
`chgrp bob <path>` takes, and it is also why `groupdel bob` answers `no such group`
and `usermod -G bob bob` moves nothing — there is no line to remove and none to put
anybody on.

`groupadd` appends, `groupdel` drops every line naming the group, `usermod -G`
**sets** the lines an account is on (SVR4's own semantics: the list is what it is in
afterwards, a group not on the list is one it has left, and an empty list is refused
— there is no SVR4 spelling for "in no groups at all"), and `userdel` sweeps a name
out of every line in one write (`CeroSecOS.removeGroupMember`), because with `%wheel`
in `/etc/sudoers` a name left in `wheel` is root waiting for whoever is given that
name next. Every other line is kept exactly as it lies, comments included. All go
through the ordinary `setData`. A group name obeys `CeroSecOS.isValidUserName` — the
two share a namespace, so a group nobody could ever have as a primary group would be
a trap. `root`, `wheel`, `sudo` and `users`
(`CeroSecOS.GROUP_KEEP`) cannot be deleted; anything else can, and files still
carrying the name keep it, dangling, which is what `ls -l` shows.

The `sudo` group is the one place two files meet. `/etc/sudoers` remains the
authority on who may run a command as root; `CeroSecOS.inGroup(state, user,
"sudo")` answers true for a name in *either* file, so `id` and `groups` show it and
the `660` on a device means what its comment always claimed. Membership of the
group grants no `sudo` by itself: only `/etc/sudoers` does that — which since
`SYSTEM_VERSION` 16 it does for `wheel`, by naming it.

**`/etc/hostname`** — the machine's name: 1 to 16 characters of `[a-z0-9-]`, never
starting with `-` (the name is written into `state.hostname` too, where `validate`
tests it with `isValidName`). `hostname <name>` is root only. A file that does not
hold a name falls back to `state.hostname` and then to `CeroSecOS.DEFAULT_HOSTNAME`.
The server reads the file for the window title and for every prompt.

**`/etc/motd`** — what `login` greets an account with once the password is right,
capped at 10 lines. A missing or empty file greets nobody: the built-in
`CeroSecOS.MOTD` seeds a fresh disk and never speaks for a file root emptied.

**`/etc/issue`** — what `getty` printed OVER the login prompt, capped at 10 lines
and read by the same rule (`CeroSecOS.issueLines`). Seeded 644 and root's with the
machine's own name written into the bytes -- nothing on this machine expands a token
on the way to the glass, so `CeroSecOS.setHostname` rewrites the line it seeded, and
only while the file still holds exactly that line. A profile may write one of its
own (`CeroSecContent.PROFILES.<id>.issue`), which is where the bank's and the post's
"authorized use only" goes.

**The BIOS.** On `open`, before a line is put on the screen, the machine has no
operating system when the state does not validate, or `/bin` is missing, not a
directory or empty, or `/etc/passwd` is missing, not a file, or parses to no
accounts. Then the boot ends on `No operating system found.` and
`Restore system? (y/n) ` — an ordinary console prompt with an ordinary continuation
token (`cont = { cmd = "bios" }`), answered on the server because there is no session
to run it under. The refusal (`n`) is the machine's and not the window's: a second
player opening a window on a halted machine finds the refusal, not a fresh question.

`CeroSecOS.restoreSystem` makes `/etc` if it is missing or is not a directory,
creates `/etc/hostname` and `/etc/motd` only if missing, replaces `/etc/passwd`,
`/etc/sudoers` and `/etc/group` only if missing, not a file, or parsing to nothing
at all, makes
`/bin` and rewrites every standard executable to owner `root`, mode `755` and its
description, and rebuilds the filesystem root if the state has no usable one. It
touches **nothing else** — `/home`, `/root`, `/dev` and anything a player made come
through untouched, a `/etc/passwd` that still parses keeps its hashes, and a file of
your own in `/bin` is left where it is. Running it twice changes not one byte. If
the validator refused the state for a reason the repair does not address, the
machine comes back to `No operating system found.` and asks again: the BIOS puts the
system files back, it is not a disk doctor.

**Migration.** A save from before `/etc/passwd` carries its accounts in a
`state.users` table (and, before that, in clear): `CeroSecOS.migrateUsers` hashes
what is still clear, writes the file, fills `/bin` and drops the table, so such a
machine boots straight to its login prompt with the same accounts, homes, admin
flags and passwords. A state that somehow has both a table and a parseable file
keeps the **file**. An unknown version, or junk, becomes a brand new machine. Damage
done in the game goes through the BIOS restore instead. `validate` knows nothing
about accounts any more: it checks that `/etc/passwd` is there, is a file and is
root's, and the rest is the parser's business. A machine saved before `/etc/sudoers`
existed simply has none, and the `sysv` top-up (see "Persistence") writes it on the
next load rather than making anyone go through the BIOS for it. The same is true of
`/etc/group`: `SYSTEM_VERSION` 5 seeds it, and the five group commands, into an
older machine. Nodes saved before that rung carry **no** `group` field at all and
are left exactly as they are — `CeroSecOS.groupOf` reads a missing one as the
node's owner, so nothing has to walk the disk. `validate` accepts a missing
`group` and refuses one that is not a string.

## Persistence

The GlobalObject saves `v`, `on`, `facing`, `os`, `console` and `born` to
`gos_cerosec.bin`.
`os` and `console` are nested tables the save serializer recurses into. `born` is one
bit — this computer's square was created for the first time in this save and nobody has
settled the automation question about its premises yet — and it is *saved* rather than
kept in memory so that a player who quits in the minute between the chunk arriving and
the sweep does not lose the question (see
[CONTENT.md](CONTENT.md#the-premises-that-were-already-automated)). Absent on every
machine saved before it, and absent reads as "nothing to settle". Only `v`,
`on`, `facing` and `os` are mirrored into the `IsoObject`'s `movableData`, which is
what vanilla pickup and placement copy — so a computer carried across town keeps its
files **and the disk in its drive**, and only `v`, `on`, `facing` are sent to clients on add or update. The console
is deliberately excluded from both: it is a screen, not a disk (a computer picked up
is a computer that lost its power), and the client never reads the stored screen,
only the lines the server answers it with. A filesystem is capped at 512 nodes, 96
entries per directory, 16 levels deep and 65536 bytes total, so the mirror stays
small. (96 and not 64 since rung 6b: the shipped `/bin` was 64 files at a ceiling of
64, which is a `/bin` with no room to put a deleted command back into. `/dev` keeps
its own 64 — how many commands ship is no reason to mount more of the world.)

The state also carries `sysv`, the *contents* it was built with (`CeroSecOS.SYSTEM_VERSION`
is 18 today) as opposed to `v`, the schema (`CeroSecOS.STATE_VERSION`, 2 today — see
[Migration](#migration) below). A change that adds a command adds a file to
`/bin`, so on load `CeroSecOS.upgradeSystem` tops a machine behind on that number up —
the standard executables that are missing, and `/etc/sudoers` when there is nothing at
that name — and then moves the number up. At the current number it does nothing at
all, which is what keeps root's `rm /bin/ls` a deletion and not a suggestion. As of
this change the top-up is generic: it walks `CeroSecOS.binNames()` against what is
actually in `/bin` rather than hand-listing what each numbered version added, which
is why versions 13, 14 and 15 (the telephone's and radio's own files,
`/etc/callsign` included, and `/bin/arp`) have no numbered entry below — they were seeded through `ensureNet` /
`ensureCallsign`, called unconditionally on every upgrade, the BIOS repair and a
fresh machine alike, on the same "only where the name is free" terms. The
version-by-version history below (8 through 12) is kept because each of those
changes really did add exactly what it says; read it as history, not as a claim that
12 is current.
`SYSTEM_VERSION` 19 seeds `/etc/issue`, the banner `getty` printed before the login
prompt, root's at 644 and naming the machine as it stands now rather than as it
shipped. Only where there is nothing at all at that name: an empty one is a silent
prompt somebody chose, and once the number has moved an `rm /etc/issue` stays done.
Nothing is deleted. What moved with it is where the greeting is printed -- `/etc/motd`
was being put on the screen over the login prompt AND after the password, and it is
now `login`'s alone (`CeroSecOS.loginLines`: the last login out of `/var/log/wtmp`,
the motd unless `~/.hushlogin` is there, and `You have mail.` off the spool).

`SYSTEM_VERSION` 18 seeds the things a 1993 sh and a 1993 desk had and this
machine had not: `/bin/env`, `/bin/tar`, `/bin/at`, `/bin/atq` and `/bin/atrm`, plus
`/var/spool/at` for at's queue (through `ensureVar`, on the same "only where the name
is free" terms as the rest of `/var`). `export` and `.` are words the shell **is** and
have no file, like `cd`; `find -exec` is a flag on a command that was already there.
Nothing is deleted. The one thing a save gains beside those is on the **console** and
not on the disk: `console.shexport`, the set of variables that are in the
environment, kept by `repairConsole` like `console.shvars` beside it and **absent on
every console saved before this build** — which reads as "all of them", because that
is what a script saw before there was an environment here (see the variables section
of `CeroSecOSVM.lua`).
`SYSTEM_VERSION` 12 seeds `/bin/mount`, `/bin/umount` and `/bin/newfs`, and the one
directory a disk is mounted on: `/mnt`, root's at 755 and shipped empty. The device
it is mounted *from* is not seeded and never could be — `/dev/fd0` exists for the
length of one command and only while there is a disk in the slot.
`SYSTEM_VERSION` 11 seeds `/bin/which`, `/bin/ln` and `/bin/readlink` (that last
one **deleted again** at 16: readlink(1) is 1997, and the arrow `ls -l` draws is
where a 1993 survivor reads a link) — `type` is a
word the shell *is* and has no file — plus the two places the filesystem grew:
`/dev/null`, which is the one device written to the disk and the one the `/dev` sweep
leaves alone, and `/var/tmp`. `validate` accepts a device on a saved disk only when
it is that hole, and counts it against no ceiling, because a device costs the quota
nothing everywhere else and a gate that counted it would refuse a machine the quota
had just let fill up.
`SYSTEM_VERSION` 10 seeds the nine the network added -- `/bin/ifconfig`,
`/bin/ping`, `/bin/rlogin`, `/bin/rsh`, `/bin/rcp`, `/bin/ruptime`, `/bin/rwho`,
`/bin/who` and `/bin/last` -- plus `/etc/hosts` and `/etc/hosts.equiv`, and
nothing else: the machine's own line in `/etc/hosts` needs an address, which is a
fact about the building and is only known once the server has looked.
`SYSTEM_VERSION` 9 seeds `/bin/sort`, `/bin/uniq`, `/bin/crontab` and `/bin/mail`,
and the `/var` tree the last two live on. `SYSTEM_VERSION` 8 seeds `/bin/halt` and the six the engine runs itself but still
looks up first — `/bin/sleep`, `/bin/printf`, `/bin/test`, `/bin/[`, `/bin/true`,
`/bin/false` (`/bin/echo` was already there) — and is the one version that takes
something away: `/bin/cd`, `/bin/exit`, `/bin/jobs` and `/bin/wait`, seeded by every
version up to 7 and never anything but a file with nothing behind it. `/bin/[` is the one filename on this
machine that is punctuation, which is why the disk has
`CeroSecOS.isValidFileName` beside `isValidName`: it allows exactly that one extra
name and nothing else, and an account or a group is still `isValidName`'s.

`~/.sh_history` is the one file exempt from the 64 KB disk quota, and the exemption
is decided by the **path** at the moment the disk is counted — never by anything
carried on the node. `CeroSecOS.exemptPaths` builds it from `/etc/passwd`: exactly
`<home>/.sh_history` for each account it names, plus `/root/.sh_history`, and owned by
that account. `CeroSecOS.usage` sums everything else; `CeroSecOS.exemptUsage` sums
only those paths, capped at `CeroSecOS.HISTORY_BYTES` (16 KB) per file and
`CeroSecOS.MAX_EXEMPT_BYTES` (four of those) per machine, with anything past either
counted against the disk like anybody's bytes. So `df` does not move because
somebody typed, and a **renamed** history is an ordinary file from the moment it is
renamed: it counts at once, and renaming it back makes it exempt again. There was a
flag (`nq`) before rung 5a.1 and it rode the rename, which let up to 64 KB hide from
`df`; `CeroSecOS.migrate` strips the field off every node on the way in. The
machine-wide ceiling is also paid at the **write**, in `historyAppend`, so a machine
with accounts enough cannot write history no `df` on it mentions. `cp` of a history
is an ordinary copy and meets the ordinary 4096-byte ceiling.

Being **over** the quota is a state a machine can be in: renaming a full history puts
it there, nothing is ever deleted to make room, and every further write answers `disk
full` until room is made (a shorter line written over a longer one still goes in —
that is room being made). `CeroSecOS.validate` says nothing about the 64 KB for that
reason: over quota is a runtime refusal, not a corrupt save to be thrown away. The
one ceiling it does hold a file to is `HISTORY_BYTES`, the biggest a file can *be* —
bigger than the 4096 a write may produce, because a renamed history is exactly that.
Homes are never touched by `restoreSystem`, so the BIOS repair never takes a history
or a `~/.profile` away.

`os.jobs` is what the machine was **running**, and it is a key inside the state
rather than a seventh saved key on the object: `os` is already saved and the
serializer recurses into it, so an added key inside it moves no number at all (a
field a change added, read with a default — the compatibility contract's own rule)
and a build that has never heard of it reads a machine with one and ignores it,
`CeroSecOS.validate` not being a closed namespace over the state's keys the way a
disk is. It is written at **`Events.OnSave`**, which `zombie.GameWindow.save(boolean)`
triggers at bytecode offset 302 and calls `zombie.globalObjects.SGlobalObjects.save()`
at offset 418 of the same method (`javap -p -c` on 42.20.4) — so the event is the one
moment there is, before `gos_cerosec.bin` is written. It is read at
`SCeroSecSystem:newLuaObject`, the road every machine in the save file comes in by,
and **taken off the state as it is read**: a book is a thing a machine is running and
not a thing that lies on its disk, so a second load cannot resurrect a job somebody
stopped and the gate never spends its table budget walking one. That it is read
*there and nowhere else* is what keeps a client out of it — a state also arrives from
an item's `movableData`, which on a server is a table a client wrote, and that road
ends in `resetForPlacement`, which switches the machine off and kills the book, and
the other, `stateFromIsoObject` — a machine adopted from its sprite, which *can* come
up on — strips the key before anything reads the state.

A book entry is `{ packed = graph }`, and the graph is what lets a pipeline in flight
cross a save. A job's parsed program is shared, by reference, between its frames and
every stage's frames, and a stage points back at the job that owns the pipeline and at
the pipes on either side of it; the state's own serializer has no notion of identity
and `validate` refuses a cycle, so a plain copy of such a job is both several times
too big and a cycle. `CeroSecJobs.intern` writes it once instead: `seen[table]` is set
before it descends, a table reached a second time gets a lazily assigned `$id` and is
replaced there by `{ ["$ref"] = id }`, and only a table reached twice carries an id.
The one cycle left (a stage's `errTo`) is broken the same way and put back by
`resolve`, which is two passes so that a marker may come before its target: the first
counts and validates and registers every id, the second replaces the markers. The
clocks are converted on the way, a stage's `wakeMs` to a `sleepLeft` exactly as the
job's is, and `jobFromData` rebuilds them from the moment of the load. What refuses a
stage is `jobRefused`, recursively, by name. The flat entry, the job itself, is still
read, and a build that predates the packed one drops the entry for want of an `id`.

`CeroSec.JOB_SAVE_BYTES` and `CeroSec.JOB_SAVE_TABLES` bound what may be written, and
the second is the one that binds: it is what is **left of `validate`'s own table
budget** once the biggest legal filesystem has been paid for. That budget is
`8 * (MAX_NODES + FLOPPY_NODES)` = 4352, and the worst legal state is the one where
every node is a **directory**, because a directory is two tables (the node and its
`children`) where a file is one — 1090 tables, measured, against the 576 a machine of
files costs. So 1090 spent, 2 for `os.jobs` and its list, and 2048 for the book leaves
1212 unspent (the shipped `autoclose.sh` is 371 tables at its heaviest, mid-pipeline,
and both home-kit daemons together 769, where the tree form was 1205 for one).
`tests/window_test.lua` builds that worst case and asserts the three
numbers add up, because a state past the budget is refused and `osState`'s refusal is
sticky: the failure this bounds is not a slow gate, it is a computer the player cannot
open again. [SCRIPTING.md](SCRIPTING.md#underneath-the-step-machine-the-job-and-the-scheduler)
has the table of what survives and what does not.

The pending `shutdown` is a job in the ordinary book and is **not** written with the
rest of it, which is deliberate and is about its clock: `at` is a moment on
`getTimestampMs` — the wall clock the scheduler counts passes on — and the world stood
still while the game was shut, so an order given against it cannot cross a save and
still mean what it said. It falls out of the save rule anyway, a pending order being
a job whose state is `"waiting"` and only a running or a sleeping job being written.
The machine stays up and the README, the manual and `docs/PARCOURS-TEST.md` all say so
rather than letting a player discover it by the machine not going down.

`console.stack` is the su stack: `{ { user = "admin", cwd = "/home/admin" }, ... }`,
innermost last, at most `CeroSec.SU_MAX` (4) deep — the same number the core
enforces as `CeroSecOS.SU_MAX`, named twice because the terminal never loads the
core and pinned against it by `os_test`. It is machine state like `console.user`
and `console.cwd`: `su` pushes onto it, `exit` pops, a logout, a `reboot` and a
`shutdown` drop it, and `repairConsole` keeps it entry by entry — only where an
entry is still a name and a path, and never deeper than the ceiling, so a forged
console cannot hand back a stack that takes ten exits to get out of. An empty
stack is stored as no stack at all. The core sees it on the session
(`session.stack`), beside `session.login` — the account really at the glass, as
opposed to the account a command is running as. A borrowed session (sudo's, and a
chain carrying its authority) is given `login` and a **copy** of the stack: it may
read who the glass would come back to (`userdel` refuses to remove one of them)
and anything it pushes or pops dies with the command — which is what keeps
`sudo cd /root` from moving anybody.

`su` is the exception, and deliberately: `sudo su bob` is a shell of bob's **at this
glass**, the way it is on a real machine, so it pushes on the console's own stack and
`exit` pops it. What makes that possible without giving a borrowed session the
console's is `session.real`, the link `sudoRun` hands to a command it runs *itself* —
not to a sudo'd script, whose `su` moves that script's shell and not the glass, and
not through `rootSessionFrom`, so nothing else can reach it. `su` is the only command
that reads it (`suTarget`), the ceiling is still the console's four, and root is
asked for nobody's password: `sudo su` is root, `sudo su bob` is bob.

`sudo exit`, on the other hand, is `sudo: exit: command not found`, and so is
`sudo cd`, `sudo jobs`, `sudo read` and every other word the shell **is**: there is
no file in `/bin` for sudo to look up and nothing for it to run, which is what real
sudo says about one, in its own name. The test is the shell's own
(`isShellWord`, `SHELL_BUILTINS`) rather than a list beside it. A name this
machine has no command for at all is signed the same way — `sudo: lights: command
not found` — because sudo is the program that went looking; what stays signed with
the command's own name is the **PATH lookup's** refusal (`whyNotRun`), so `sudo ls`
on a machine whose `/bin/ls` root deleted is still `ls: command not found`. Until
`SYSTEM_VERSION 18` only `exit` was named, so `sudo cd /root` fell through to
`commands.cd`, moved the borrowed session sudo had just made, and printed nothing
at all — a line that said nothing and did nothing, on a page of the manual that
already said sudo cannot run a word the shell is.

The editor's buffer lives in the console too (`console.edit`), with the account it
was opened as: `sudo edit /etc/motd` opens the buffer as `root` and saves as `root`,
four minutes later, while the session at the glass is still `admin`'s. A buffer with
no account on it — one opened before `sudo` existed — is the session's, as it always
was.


## Migration

**A mod update never costs a player what he built**, and until this change that was not
true of the one number that mattered. `CeroSecOS.STATE_VERSION` is the *shape* of the
state, and a version that was not the current one became a **fresh machine**:
`SCeroSecObject:osState` replaced `self.os` wholesale, and `CeroSecOS.migrate` handed
back a new state for anything that was not exactly v1 — the filesystem, the accounts,
the disk in the drive, gone. Which is why the number had never been moved in the mod's
life: the first bump would have wiped every computer in every save on the next load,
so nothing that lived in the shape could ever be changed at all.

### The chain

`CeroSecOS.MIGRATIONS[n]` takes a state at `n - 1` and leaves it at `n`.
`CeroSecOS.migrate` walks every step from the version on the disk up to this build's,
moving `state.v` **as each one lands** — so a state that dies half way through (a step
that errors, a server killed under it) comes back at the version it really reached and
walks the rest on the next load. Then `upgradeSystem` tops the *contents* up, which is
the other number and is not part of the chain.

It is called from **one place**: `SCeroSecObject:osState`. Everything that hands the
object a state writes it through `SCeroSecObject:setOS` and then asks there — a chunk
coming back (`stateToIsoObject`), a machine adopted from its sprite
(`stateFromIsoObject`), a computer put down out of somebody's hands
(`resetForPlacement`, both through `osFromIsoObject`), the developer's reset
(`resetMachine`) and the firmware repair (`restoreOS`) — so the chain runs on every road
in and on none of them twice: at the current version the loop has no steps to walk.

### The gate is asked once per state, not once per read

`CeroSecOS.validate` walks every node of the filesystem and every table of the disk in
the drive. It used to run on **every** read of the state, and the sweep reads the state
three times a game minute for every machine that is on, plus once per packet: measured
on the 300-machine rig at 0.887 of the 0.894 ms a read cost, and 104 of the 104 ms a
game minute cost with forty machines running (`tests/hostile_test.lua`, the county
block). It is now asked once per state table.

The memo is `self.osChecked`, and it holds the **table** and never a flag: a flag goes
stale the moment a state is replaced, and a stale flag here is a table nothing ever
validated being run on. `setOS` drops it with the state it replaces — which also stops
the memo holding a filesystem that was thrown away — and `restoreOS` drops it by hand,
because that is the one path that remakes `/etc`, `/bin` and the filesystem root of a
table it does **not** replace. `osChecked` is not in `CeroSec.OBJECT_SAVE_KEYS`, so
every machine in a save is validated once per session, on its first read.

What this is safe against is written out beside the code: `validate` is a gate on what
comes in from **outside** — a save file, an item's `movableData`, a client's packet — and
every other writer in the mod writes *inside* a table the gate has already passed,
under the write path's own rules (`setData` for the bytes and the printable characters,
`isValidFileName` for a name, `MAX_DIR_ENTRIES`, `MAX_NODES`). The one writer that puts
a whole subtree in at once is the disk going into the drive, and it arrives already
migrated and validated against the **slot's** stricter bound (`diskFromData` →
`insertDisk`), which is a superset of what the gate asks.

The two sweeps below it are **not** memoised, and the reason is the save file and not
the gate: `os` is a saved key, so a `/dev` node left behind by a pass that died
mid-command would go into `gos_cerosec.bin` and be refused on the next load, where the
memo starts empty. They cost 0.0044 and 0.0005 ms — half a percent of a read between
them — so they stay where they are. The three mount windows
(`CeroSecOS.jobStep`, `CeroSecOS.continue`, `Commands.complete`) each hold their pair of
calls in one block with no early return between them, so the only thing that leaves a
node behind is an error thrown inside one, which is exactly what no `end` can catch.

`migrate` deliberately does **not** validate. A state of a version it can *read* is
kept even when the gate then refuses it, because the way back from a filesystem the
core cannot run on is the BIOS (`restoreOS`), which keeps `/home`. Handing back a fresh
machine there was the function throwing away the very thing it exists to save, and it
was invisible because the only states that ever reached it were junk.

`STATE_VERSION` is **2**, and step 2 is the accounts file and the quota flags — two
repairs that ran on *every read of the state* because no number could say they had
already been done. `nq` was swept off every node of every machine for the rest of the
save's life.

A step is handed a table and nothing else. Most machines in a save have no chunk
loaded, so a step that asked the world could not run for them; the top-ups that
genuinely need it live where the square is answerable and are called from there — the
address, the telephone exchange and the premises name in `CeroSecNet.identify`, the
devices under `/dev` in the scheduler. The mount sweep (`checkMounts`) and the `/dev`
sweep (`unmountDev`) are **not** migrations and stay on the road in beside the chain:
what makes a mount stale is the disk coming out, which happens while the machine is
running.

### Newer than the code

A state a **later** build wrote is refused and **not touched**: `migrate` answers `nil`
plus `"newer"`, a runtime flag (`osNewer`, never written back) makes the refusal
sticky, and the firmware's own line goes on the screen —
`System newer than firmware: update the mod.` — instead of the BIOS' question. `y`
would mean this build writing its own shape over a save its own author could still
open, which is the one unrecoverable mistake there is. `restoreOS` refuses it too.
Nothing is reset, and the switch at the back of the case still works: `turnOff` has
never needed a state.

A state with **no** version, or one below the oldest step there is, becomes a fresh
machine. That is what a pre-release save is — nothing shipped that wrote one — and it
is the one case where something is lost.

### The other three shapes

The machine is not the only save file the mod writes, and each of the other three has a
number and a chain of its own:

| shape | number | chain | walked in |
| --- | --- | --- | --- |
| a floppy's `modData` (`v`, `fs`, `label`) | `CeroSecOS.FLOPPY_VERSION` | `CeroSecOS.DISK_MIGRATIONS` | `diskFromData` at the slot, and `migrate` for one riding inside the state |
| a door's modules (`modData.cerosec`) | `CeroSecModules.VERSION` | `CeroSecModules.MIGRATIONS` | `installedOn` |
| the phone book stamp (`modData.cerosec`) | `CeroSecPhonebook.VERSION` | `CeroSecPhonebook.MIGRATIONS` | `regionOn` |

A disk is walked on **both** roads in, because one that was in the drive when the game
was saved rides inside the state and never passes the slot again. A disk a later build
wrote makes the whole machine unreadable, with the same answer and for the same reason
— and it is asked *before* a single step writes anything, so "not touched" means it.
An unreadable disk is never handed back blank: a machine that formatted a floppy it
could not read would be a machine that wipes somebody's work to make it fit.

An absent number is the **oldest** shape and not version zero — the ids on a door
written before this change are the ids version 1 has — and the stamp is a thing the next
write adds. That matters for the modules in particular: a read happens on a client, and
a client writing into a door's `modData` writes into nothing anybody else will ever
see.

`CeroSecOS.DISK_LEGACY_KEYS` is what stops the closed namespace and the chain
contradicting each other. At the slot, only the keys in `DISK_KEYS` and that list are
taken off the item at all (`ownKeysOf`), and the pick happens *before a byte is
copied* — so a step that renamed a key could never have seen the old name. The old
name goes on that list and the step takes it off. A migration is the one thing allowed
to rename or drop a key.

What the slot does with a key that is **nobody's**, on the other hand, is leave it:
an item's modData is the game's table, not ours. `item:setCustomName(true)` rawsets a
`customName` key on it (javap `zombie.inventory.InventoryItem`, offsets 5-24), which is
how a label is written on a disk — and while the rule refused a fourth key, every
labelled disk in the world was refused at the slot with nothing on the glass to say so.
`diskFieldsOk` judges a disk **record**, a table this engine made; the item's own keys
never reach it.

### Proving it

`tests/fixtures/state-v<N>.lua` is a **photograph**: bytes a real build produced,
committed to git by `tools/capture-fixture.sh`. Every other bench in the suite builds
its machine with today's code, which is exactly what this one must not do — a fixture
built by the builder under test changes shape the moment the builder does, so the chain
would always be walking a state the previous release never wrote. With a commit
argument the tool checks that build's engine out into a temporary tree and captures
from there, which is the only honest way to get a fixture of a shape the current code
cannot write any more.

`tests/migrate_test.lua` walks every fixture and asks the invariants: the gate takes
the machine, the accounts still log in with the passwords they *had* (tried, not read —
what is stored is a hash), the files are byte for byte, the script still **runs**, the
cron line still parses, `light0` is still the same light switch, the hostname and the
callsign are the machine's own, and the disk still **mounts** and reads through the
mount. Twice is once, compared byte for byte with the version wound **back** first:
calling `migrate` again as it stands runs nothing, so that bench would prove the guard
and say nothing about the steps.

## The manual reader


The set is three pieces and three text files, and the text files are deliberately
the only ones of them anybody has to touch to write another edition.

**The text** is three volumes, one file each, each assigning itself into one table
they share:

| file | id | name |
| --- | --- | --- |
| `shared/CeroSec/CeroSecManualUser.lua` | `user` | User's Guide |
| `shared/CeroSec/CeroSecManualAdmin.lua` | `admin` | System Administrator's Guide |
| `shared/CeroSec/CeroSecManualProgrammer.lua` | `programmer` | Programmer's Guide |

    CeroSecManual.volumes = CeroSecManual.volumes or {}
    CeroSecManual.volumes[1] = {
      id = "user",             -- opened by this, never shown
      title = nil,             -- stamped, see below
      name = "User's Guide",   -- what the cover says
      edition = "First Edition, 1993",
      chapters = {
        { title = "...", pages = { "a page of plain text", ... } },
        ...
      },
    }

The `or {}` on the first line is the whole of why they can be three files and still
one shelf: the game loads them in whatever order it loads them in, and none of the
three may assume it is first.

The **title is not written here**. It names the version of the OS the set is for,
and that number has exactly one home — `CeroSecOS.VERSION` — so the cover is built
from it: `"CeroSec OS " .. CeroSecOS.VERSION .. " " .. name`. It cannot be a plain
concatenation in the table: the game sorts `shared/cerosec/cerosecmanualuser.lua`
ahead of `shared/cerosec/os/cerosecos.lua` (the load list is every relative path,
lowercased, sorted case-insensitively), so the core is not loaded yet when the table
is built. `CeroSecManualBook.stamp()` stamps it at the last moment before the layout
reads it, `CeroSecManualUI.text(volumeId)` is what calls it, and running the stamp
twice changes nothing. A volume that could not be stamped — the core genuinely not
there — shows its `name` on the cover rather than the word "Manual".

`CeroSecManualBook.shelf()` is the volumes as they stand and
`CeroSecManualBook.volume(id)` is one of them, stamped; a nil id is the first
volume. There is **nothing behind the shelf**: `CeroSecManual.lua` was itself a book
once — one volume, written for somebody who had used a bigger Unix before — and it
was retired when the third volume was written, because two books describing one
machine is one book too many. What is left of that file is the two lines above. So
an empty shelf is not a state this mod has: it is a volume file that failed to load,
and it is said in the log (`CeroSecManualUI.text`, `CeroSecContextMenu.addDevManual`)
rather than papered over. The reader still opens, as an empty book, because a reader
is the wrong place to take a client down from.

ASCII only. `\n` is a paragraph break. **An authored page is a page**: the writer
decides where a page ends and the layout honours it, so pages want to be about 900
characters. A line that starts with **two spaces** is an example: it is drawn in the
terminal's own `UIFont.Code`, on a faint band, and it is never wrapped and never
trimmed, because a shell line broken across two rows is a shell line the player will
mistype. Keep those under about 62 columns and they will always fit a leaf.

The manual is read through `CeroSecManualUI.text(volumeId)` and never cached, so a
reload of a text file is a reload of every open book. A missing or half-written
table is an empty book — a title leaf and a contents that lists nothing — and never
an error.

**The layout** is `shared/CeroSec/CeroSecManualBook.lua`, and it makes no game call
at all: `CeroSecManualBook.open(manual, { width, rows, measure })` hands back a flat
list of leaves, and `measure` is a function the caller supplies. That is what lets
`tests/manual_ui_test.lua` lay the same book out against a font of a known width. It
wraps by words, breaks a word wider than the leaf rather than draw it off the paper,
gives every chapter a leaf of its own, spills an authored page that does not fit onto
a continuation leaf rather than cut it off, and pads the book to an even number of
leaves so the reader is never shown half a spread.

**The window** is `client/CeroSec/CeroSecManualUI.lua`, an `ISCollapsableWindow`.
Vanilla ships no serif — `media/fonts/EN/fonts.txt` maps every readable face to
zomboidSmall/Medium/Large — so the body is `UIFont.NewMedium`, which is what
vanilla reads its *own* book in (`SurvivalGuide.lua:3-4,47`), and examples are
`UIFont.Code`. The leaf is **64 monospaced columns** wide and that cell is measured
the way the terminal measures its own — `MeasureStringX("MM") - MeasureStringX("M")`,
the advance and not the ink of a glyph, because `MeasureStringX` counts the last
character of a string as its ink `width` and `M` in `zomboidCode.fnt` is a pixel
wider in ink (9) than the cell it is drawn in (8). It was the ink until a later
change, which is 64 pixels of leaf per side that the text never filled. Everything
else the reader measures is *centring and wrapping* — a title, an edition, a page
number, whether a body line fits the leaf — and is left on `MeasureStringX`
deliberately: nothing there places a column, and the error is the side bearing of one
glyph against a leaf with a twenty-pixel margin. Left, Right and Escape reach it
through `setWantKeyEvents(true)` and
`isKeyConsumed`, the pattern `ISVehicleAnimalUI` uses. The bookmark is
`item:getModData().page`, always the **left** leaf of the sheet, and a number read
back off it goes through `CeroSecManualBook.clampPage` first — a manual rewritten
between two saves must not open an empty leaf. It is a client-side bookmark and is
not transmitted: it is where a reader left off, not machine state. One copy is one
volume, so a bookmark per copy is already a bookmark per volume.

A window is opened on one volume — `CeroSecManualUI.open(playerObj, volumeId, item)`
— and lays that volume out and nothing else: its cover, its contents, its chapters.
The player stays the first argument because the window belongs to him: it is his
instance a second opening closes, and it is his death that shuts it. `window.bookId`
is what the reader really ended up with, and it is what a bookmark with no copy
behind it is filed under — never nil, because a bookmark table cannot be keyed by
nothing.

**The menu** is `client/CeroSec/CeroSecManualMenu.lua`, on
`Events.OnFillInventoryObjectContextMenu` — the event vanilla put there for exactly
this (`ISInventoryPaneContextMenu.lua:933-935`). It unpacks both shapes the event
hands over: an `InventoryItem`, and a stack of identical ones which arrives as a
table with an `items` array inside it. `CeroSecManualMenu.BOOKS` maps each item to
its volume and its own label, and each volume in the selection gets its own option:
a menu offering "Read the manual" three times over would be a menu nobody could
use. It is an ordered list and not a map keyed by item, because `pairs()` would
shuffle the entries from one right-click to the next.

**A double-click** on a volume opens it too. Vanilla routes the gesture through
`ISInventoryPane:onMouseDoubleClick` (`ISInventoryPane.lua:1141`) into
`:doContextualDblClick(item)` (`:1199`), a ladder of elseifs over what the item is;
at `:1102-1103` a Literature item goes to `ISInventoryPaneContextMenu.readItem`,
which queues vanilla's hours-long `ISReadABook`. Our volumes are
`ItemType = base:normal` on purpose and never reach that rung, so
`CeroSecManualMenu.hookDoubleClick` **wraps** `doContextualDblClick`: our three books
go to `CeroSecManualMenu.onRead` — the context menu's own handler, so the two doors
cannot drift — and everything else is handed to the original untouched. The wrap is
idempotent, or a second one would make `vanillaDblClick` point at the wrapper and any
other item would recurse until the stack gave out.

**The floppies' own inventory menu** is `client/CeroSec/CeroSecFloppyMenu.lua`, on
the same event: *Label floppy*, and *change*/*erase* once there is writing on a disk.
See [DEVICES.md](DEVICES.md) for where the label lives and what prints it.

**The testing door.** `CeroSec.DEV_MANUAL_MENU` in `CeroSecDefs.lua` is a
**temporary testing aid and has to be set to `false` before the Workshop release.**
While it is on, every computer — lit or dark, in reach or not — carries a last entry
on its right-click menu, **Read the CeroSec manual (dev)**, and behind it a submenu
of one entry per volume, each opening the reader there and then with no copy of the
book anywhere. It exists so the reader can be worked on without first going shopping
for three items, and it is a door into a piece of documentation a player is supposed
to *find*. It is added by `CeroSecContextMenu.addDevManual`, always last, built the
way every vanilla submenu is (`getNew`, `addSubMenu`, then fill it —
`ISWorldObjectContextMenu.lua:1167-1169`), and it asks nothing of the computer — not
its power, not its height, not whether anybody can stand in front of it — because it
is not really about the computer at all. A book opened that way has no item to write
a bookmark on, so it keeps its own on the module, keyed by volume
(`CeroSecManualUI.devPages`): session-lived, never saved, and never the same
bookmark as a copy's. With no shelf standing up there is nothing to put a door onto and
the submenu is empty, with a line in the log saying which volume file did not load.
Off, nothing at all is added.

**The items** are `common/media/scripts/items_cerosec.txt`: `CeroSec.ManualUser`,
`CeroSec.ManualAdmin` and `CeroSec.ManualProgrammer`. All three are
`ItemType = base:normal` and
**not** `base:literature`, on purpose: a literature item that cannot be written on is
one the vanilla menu offers to *read*, and vanilla's read is a timed action that sits
the character down for hours. They keep `DisplayCategory = Literature`, which is a
free string the inventory prints through `getText("IGUI_ItemCat_" .. …)`, so they
still file themselves with the books. `Icon = CeroSecManualUser` resolves to
`common/media/textures/Item_CeroSecManualUser.png`: the game builds `"Item_" .. Icon`
and looks it up as `media/textures/<that>.png`.

`CeroSec.Manual`, the single book that shipped before the set, is **gone** —
removed on the inventory work. It was defined but not loot, and read it opened
volume one: two items with one content, which on an inventory menu is a fourth
"Read the manual" nobody can tell from the first. A save that still holds a copy
loses it, which is what dropping an item script entry costs and is acceptable
before release.

The three icons are made from the shipped one by `tools/make-volume-icons.py` —
same 32×32 book, three bindings. The navy is channel-swapped rather than picked again by
eye (blue as it was, G and B swapped for green, R and B swapped for red), which keeps
the three covers at the same value and the same contrast against the cream page block
and the green screen, neither of which is touched; the two title bars under the screen
come out and a 3×5 numeral in the bars' own cream takes their place.

**The loot** is `server/CeroSec/CeroSecManualLoot.lua`. Twelve vanilla lists times
three volumes, each weight set against what is already *in* that list, appended in
place on `Events.OnPreDistributionMerge`. The table below is **volume one's**, and
volumes two and three are a `share` of it — a half and a quarter — rather than two
more tables of twelve numbers: the share is the decision, and twelve numbers copied
and halved by hand is twelve chances to mistype one. Volume three is `raised` back to
a half in `UniversityLibraryComputer`, `UniversityDesk_Computer`, `BookstoreComputer`
and `ElectronicStoreMagazines`, because a programmer's manual is rare everywhere
except where the programmers were. The shares are halves and quarters on purpose and
not a taste: `0.1 * 0.25` is exactly `0.025` in a double, so none of the thirty-six
weights is a float that nearly is what it says it is.

| list | ours | measured against |
| --- | --- | --- |
| `LibraryComputer` | 4 | `Book_Computer` 20/10, `Paperback_Computer` 20/20/10/10 |
| `UniversityLibraryComputer` | 4 | `Book_Computer` 50/20/20/10/10 |
| `BookstoreComputer` | 4 | `Book_Computer` 20/10, `Magazine_Tech_New` 20/10 |
| `CyberCafeFilingCabinet` | 4 | `Book_Computer` 10, `Paperback_Computer` 20 |
| `CyberCafeDesk` | 3 | `Book_Computer` 4, `Paperback_Computer` 8 |
| `ControlRoomCounter` | 3 | `Book_Computer` 4, `Paperback_Computer` 8 |
| `UniversityDesk_Computer` | 4 | `Book_Computer` 50/20, `Magazine_Tech` 50/50/20/20 |
| `ElectronicStoreMagazines` | 4 | `BookElectrician4` 4, `ElectronicsMag1-5` 8 each |
| `OfficeDesk` | 1 | `Book_Business` 1, `Paperback_Fiction` 1 |
| `OfficeShelfSupplies` | 1 | `BusinessCard` 1, `PaperclipBox` 1 |
| `CrateBooks` | 1 | `Book_Computer` 1, `Paperback_Computer` 1 |
| `LivingRoomShelf` | 0.1 | `BookElectrician1` 0.1 |

Note the two distribution tables are not the same thing. `Distributions` is the room
and container map, and it is the one `mergeDistributions` merges
(`SuburbsDistributions.lua:136-149`); `ProceduralDistributions.list` is the item
pools, and nothing merges it — the Java side reads it as it stands. So a pool is
extended by appending to it, in place, which is what this does. Adding a list is a
line in `CeroSecManualLoot.WEIGHTS`; a list vanilla later renames is logged by name
— once for the list, not once per volume standing in front of it — and skipped
rather than taking the mod down.

`CeroSecManualLoot.abundance()` is the hook for a sandbox option: every weight
multiplied by `SandboxVars.CeroSec.LootAbundance` if a sandbox option file ever
declares one, so a server that wants the set common or all but absent moves one
number instead of thirty-six. Nothing declares it yet — the mod now HAS a sandbox
options file (`42/media/sandbox-options.txt`, which is where
`zombie.sandbox.CustomSandboxOptions.init()` looks for a mod's; see
[notes/modules-proofs.md](notes/modules-proofs.md)), and it deliberately declares
one option and not three: `CeroSec.HardwareRequired`, the hardware-module gate of
[DEVICES.md](DEVICES.md#the-hardware-modules). Declaring `LootAbundance` and
`PhoneService` would change what a running server does, and that is a decision of
its own rather than a side effect of this one. It is read the way vanilla
reads its own grouped options — `SandboxVars.Map and (SandboxVars.Map.AllowWorldMap
== true)`, `ISWorldMap.lua:1493` — because `SandboxVars` is a plain table and a group
nobody declared is simply not in it; and a value that is not a positive number is
ignored rather than argued with, since a nil, a string, a zero or a negative would
each quietly take every book out of the world.


`SYSTEM_VERSION` 17 takes one more away and seeds nothing at all: `/bin/call` is
**deleted**, on the same rule and for the same reason as `restart` before it -- it
was invented here. Packet radio was never something a kernel did: a TNC was a box
on an RS-232 cable, so the box is reached with `cu -l /dev/radio0` (cu(1)'s own
second form, and cu is already on the disk) and driven with the TNC-2's own
commands. See the radio section of [NETWORK.md](NETWORK.md).

`SYSTEM_VERSION` 16 is the second version to take something away, on the very rule
version 8 ran on: `/bin/adduser`, `/bin/deluser`, `/bin/gpasswd` and `/bin/hash` are
**deleted**, and only where the file is exactly what was shipped — owner `root`, mode
`755`, the seeded description — because anything else at that name is a player's own
work. It seeds `/bin/useradd`, `/bin/userdel`, `/bin/usermod` and `/bin/mkpasswd` in
their place, and the `wheel` pair: the group itself, empty, and the `%wheel` line in
`/etc/sudoers` (`CeroSecOS.ensureWheel`). It also deletes `/bin/readlink`,
`/bin/restart` and `/bin/write`: readlink(1) is 1997; `restart` was invented here
and the real spellings are `reboot` and `shutdown -r now`; and `write <file> <text>`
was a double mistake — nothing in Unix writes a file that way (it is `echo text >
file`, a redirection, and the shell has had one all along) and write(1) is the
command that puts a line on another account's terminal. Those two wheel lines are
the only **lines** any top-up
has ever added to a file a player may have edited, and each is added once, only where
its own line is missing, and never to a file that parses to nobody at all — that one
is the BIOS' business, and a line added there would make the repair keep it for ever.
