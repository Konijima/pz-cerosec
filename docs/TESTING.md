# CeroSec — Testing

`sh tests/run.sh` runs every headless suite, in order, and needs `lua5.1` on the
PATH. It exits non-zero the moment anything fails; treat that exit code as the
verdict, never the human-readable tail of the log.

See also: [PARCOURS-TEST.md](PARCOURS-TEST.md), [TEST-rung1.md](TEST-rung1.md),
[TEST-rung2.md](TEST-rung2.md) and [TEST-rung4.md](TEST-rung4.md) for what no
headless suite can reach — the sprite, the context menu, sitting down, the glow,
what is actually on screen. [CONTRIBUTING.md](CONTRIBUTING.md) for when a wave is
done enough to run this and ask for `go`.

The suites, in the order they run:

- `defs_test.lua` — the shared definitions (sprites, facings, state).
- `os_test.lua` — the OS core: filesystem, permissions, users, shell, passwords.
- `terminal_test.lua` — the pure parts of the terminal: hostname, console, history.
- `window_test.lua` — the window wired to the machine end to end: type a line, get
  an answer on the glass, and a script's output, question and `^C` through it.
- `window_test.lua` also holds the network bench: three real machines on one real
  system, two in a building and one down the road, one of them with its square
  and its `IsoObject` taken away after it was switched on. The telephone section
  uses the same two buildings four hundred squares apart -- where not one
  r-command reaches and `cu` does -- with a fake `getSandboxOptions` and a world
  age, so the grid can be killed under a call that is up.
- `window_test.lua` also holds the unload bench: one machine of that same system with
  everything the world owns behind a single switch -- its square, its `IsoObject`, the
  room its devices are in and the cell that answers for its tiles -- so the streamer
  can be made to take a chunk away with a session open on the machine and a crontab
  due, and to bring it back with or without a wire in the wall. It is the bench for
  the rule in
  [ARCHITECTURE.md](ARCHITECTURE.md#the-chunk-that-goes-away), and it carries its own
  control: a machine the sweep CAN see still goes off when its room does.
- `window_test.lua` also holds the hardware-module benches: the mockup's own
  building with `SandboxVars.CeroSec.HardwareRequired` turned on, so that a bare
  door, window and light switch are absent from `/dev` until a module is written
  into the object's modData; a contact alone giving a device that reads and
  refuses every write in two different voices (the mode's for anybody, the
  device's for root); the mode following the hardware while the number does not;
  the control with the option off, which is what every device bench written
  before rung 4f now stands as; a world with no sandbox group at all, which fails
  closed; and the two install commands end to end against a fake inventory, a
  perk level and a screwdriver — every refusal proved by what did NOT happen,
  since those commands answer nothing.
- `os_test.lua` section 21r is the engine's own half of that: a `ro` entry from a
  fake caller that would happily have carried the write out, so the refusal is
  proved to be the engine's and not the server's.
- `manual_test.lua` — the documentation set against the engine it describes: the
  shape of every volume (8..13 chapters, 3..14 pages each, 50..84 pages, plain ASCII,
  nothing over a thousand characters, example lines inside sixty columns), every
  `COMMAND_INFO` usage line and every error string the machine can print carried
  somewhere in the **union** of the three, each volume's own rules (a card that is
  nothing but exact usage lines, every typed word a word the machine knows, every
  ceiling quoted as a phrase built from the engine's own constant), and eight facts
  pinned against the code so a change to the CODE is what breaks a page. There is no
  fourth book behind the set, and a shelf that is not three volumes fails here.
  Since fidelity A it also holds the **deviations** rule, which is the project's own
  "invent nothing" written as a bench: `CeroSecOS.DEVIATIONS` is the list of things
  on this machine that no 1993 Unix had and that are kept anyway, and Volume 1's
  *What is not Unix here* page has to name every one of them — plus every name
  `CeroSecOS.RETIRED_BIN` deletes whose replacement is not itself a command the book
  teaches by name. It is checked in both directions: an entry that is not marked
  `gone` has to be a command the engine really has, and one that is marked `gone`
  has to be a command it really has not.
- `hostile_test.lua` — the one that matters to a server owner: an endless loop, a
  script that runs itself, a doubling string, an output flood, a hundred background
  jobs and a substitution bomb, each driven through the real scheduler for a
  thousand passes, asserting a flat cost per pass, a bounded console, bounded
  memory and the cpu ceiling firing where it should. It prints the numbers. Since
  fidelity A it also holds the two new commands a hostile player would reach for: a
  `more` standing at its `--More--` prompt for a thousand passes, which must cost
  **nought** steps (a pager that spun would be one), and a `find` over a disk filled
  to its node ceiling, which must be one command and not two.
- `manual_ui_test.lua` — the manual: wrapping against a proportional font,
  pagination, the contents page, turning the leaves, opening each of three volumes
  off a fake shelf and opening blank paper for an id nothing answers to, a bookmark
  per copy and per volume, the dev submenu, the keys all four item blocks set and the
  icons they name, and the twelve loot lists times three volumes with the sandbox
  multiplier.
- `debug_ui_test.lua` — the debug window: six tabs with their own columns, every
  cell of every column drawn at its own column and not all at the left, a
  snapshot that carries another window's token drawn nowhere, selecting a machine
  asking the server again under this window's token while the county list keeps
  its rows, the six buttons (three through the server, the teleport through
  vanilla's own debug call, the terminal only where the chunk is in), the Log
  tab's three filters, the two-second clock, and the one that matters: closing
  takes the tick handler OFF the event, counted on the event itself rather than
  taken on the window's word. And the rework of 2026-09-12: the bands of the
  layout in PIXELS before and after a resize (no header row on the tab strip, no
  buttons over the list), the measured columns (none overlapping, every cell inside
  its own, a cell too long cut with a `~` instead of drawn over its neighbour), the
  used-only filter with its `showing N of M`, a cursor that follows its machine
  through a reordered county, and every button greyed with the reason under the list
  — a refusal from the server included, which is the one that used to be swallowed.
- `selfcalls-check.sh` — every `self:method()` called is defined somewhere, since
  Lua only resolves a method when it is called and a missing one is a silent nil
  call, not a syntax error.
- `kahlua-check.sh` — `luac5.1 -p` on every shipped file, plus a grep of the OS core
  for constructs the game's Kahlua cannot run.

What no headless test can reach — the sprite, the context menu, sitting down, the
glow, what is actually on screen — is covered by the manual checklists in `docs/`:
`TEST-rung1.md` (turning a computer on and off), `TEST-rung2.md` (the terminal,
login and the shell) and `TEST-rung4.md` (the manual: the item, the icon, the
reader, and finding one in the world). `PARCOURS-TEST.md` covers everything past
those three rungs and has not yet had a rung of its own; it is reported step by
step, OK or KO, with one line on what actually happened.

## The millisecond ceilings are calibrated, not fixed

`hostile_test.lua` is the only suite that asserts on real time, and a bare
millisecond number says as much about who else is on the box as it does about the
engine. On a bench machine that is also running the game and a few coding agents
(load average 5 to 9) the 4 ms ceiling went red two runs in three at 4.1 to 5.5 ms
— on the untouched base as much as on a branch that touched no engine file. A red
that says nothing about the code is noise, and noise trains a reader to ignore the
colour.

So the ceilings stay and the yardstick moves. Right before the first timed section,
in the same process, the bench times a fixed pure-Lua workload (arithmetic and table
writes, nothing of the engine in it, a few tens of milliseconds), three times, and
keeps the cheapest run — the cheapest is the one that got the most of the processor.
That over `CALIB_REF_MS`, the value the same workload costs on an idle box, is a
scale factor, and every millisecond ceiling in the file becomes `limit * max(1,
scale)`:

- an idle box scales by 1 and is held to exactly the strict number it always was,
- a box that is half taken gets an allowance in proportion to how slow **it** is,
- past **3×** there is no allowance at all: the bench refuses with `box too loaded
  to measure: rerun idle` rather than pretend it measured something.

The scale and the raw milliseconds are printed on the bench's `calibration` report
line, so any figure below it can be read back against the box that produced it.
`CALIB_REF_MS` is a measurement of one machine and belongs to it: its comment in
the file says when, how and on what it was taken, and it is re-measured — on a box
with nothing else on it — not guessed at.

What is **not** scaled: every step-count assertion. Steps are the real budget proof
and a step costs the same on a loaded box as on a quiet one; a loaded box is no
reason to let a program spend more of them. Only the wall-clock ceilings move.

## The mutation habit

A suite that has never gone red on the bug it claims to catch is not proven —
it may be green because the code is right, or green because the assertion never
runs. Before trusting a new or changed assertion, break the thing it guards on
purpose (comment out the check, invert a condition, remove a line) and watch the
suite fail for that reason and no other; then put the code back and watch it pass
again. This is why `hostile_test.lua` prints the numbers it asserts on rather than
only pass/fail — a flat cost per pass is a claim a reader can check against the
printed figures, not just against a green line.

## Verify by exit code

`tests/run.sh` is `set -e`: it stops at the first failing suite and its own exit
status is the answer. Read that status, not the last line printed — `selfcalls-check.sh`
and `kahlua-check.sh` are deliberately not piped into anything for the same reason,
a pipe would hide their exit status from `set -e`.

