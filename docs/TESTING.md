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
- `content_test.lua` — the world content, and it is a bench about **loot that can
  break a save**. Every profile is built on a fresh machine, every one of them is
  handed to the engine's own boot gate afterwards, and one of them is built on a
  machine already filled to its node ceiling to prove a profile is *trimmed* rather
  than forced. Every script the mod ships is **run** — through the real step
  machine, under its budget, with its recorded arguments and again with none, and
  with exactly the devices it declared it needs stubbed and nothing else. Every
  README is held to naming every file beside it **and only** files that are on the
  disk, every generated login is pushed through a `passwd` line and read back, and
  two machines generated from one secret are compared byte for byte while a second
  secret must differ. See [CONTENT.md](CONTENT.md).
- `window_test.lua` holds the halves of that only the world can answer: that a
  machine is prefilled at its **first** power-on and never when it already had a
  state; that the papers in a drawer and in a pocket carry a password the machine
  then accepts — fired through the engine's own `Events.OnFillContainer` with the
  engine's own three arguments; that **a paper written from a drawer in one room
  opens the machine in another room of the same building**, which is the regression
  a review caught in this wave; that the event's third argument being *not* a
  container is never read (the bench hands over an object that raises on any field
  read); and that `setModDataKeys` really names both persisted fields while the
  client sync list names neither — the one line the whole wave rests on, and until
  it was written down there the suite stayed green with the save persisting nothing
  at all.
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
- `kahlua-run.sh` — every shipped file actually loaded on the real Kahlua, out of the
  game's own jar. See below.

What no headless test can reach — the sprite, the context menu, sitting down, the
glow, what is actually on screen — is covered by the manual checklists in `docs/`:
`TEST-rung1.md` (turning a computer on and off), `TEST-rung2.md` (the terminal,
login and the shell) and `TEST-rung4.md` (the manual: the item, the icon, the
reader, and finding one in the world). `PARCOURS-TEST.md` covers everything past
those three rungs and has not yet had a rung of its own; it is reported step by
step, OK or KO, with one line on what actually happened.

## The engine is loaded on the real Kahlua, not only on lua5.1

Every suite above runs on `lua5.1`. The game does not: it runs Lua on Kahlua
(`se.krka.kahlua`, bundled in `projectzomboid.jar`), a different parser and a
different VM. `kahlua-check.sh` greps for the constructs Kahlua is known to refuse,
which is a list of the mistakes we have already made — it cannot see a Kahlua parse
error it has no pattern for, and it cannot see anything that goes wrong when a file
*runs*. On 2026-09-12 the game said `Object tried to call nil` on an engine function
and nothing in `tests/` could even say whether the files loaded.

`tests/kahlua-run.sh` closes that. It compiles `tools/KahluaRun.java` into
`tools/out/` (gitignored, rebuilt when the source is newer) and loads every file we
ship on Kahlua itself, in three groups:

1. **`shared/`, in the game's load order.** The order is the game's, proven from the
   bytecode of `zombie.Lua.LuaManager`: `searchFolders()` adds each path lowercased
   and relative to the lua root, then `LoadDirBase()` does
   `Collections.sort(loadList, String.CASE_INSENSITIVE_ORDER)`. Each file is compiled
   with `LuaCompiler.loadis(InputStream, String, KahluaTable)` and run with
   `KahluaThread.pcall`. A compile error or a load-time error prints the file, the
   line and the message, and the run exits 1.
2. **The engine's surface.** Every `CeroSecOS.<name>(` and `CeroSec.<name>(` that any
   file under `server/` or `client/` calls has to be a function in the loaded
   environment — the same idea as `selfcalls-check.sh`, one step out. A missing name
   is reported with the file that calls it. That is the check that names what the
   game only calls "nil".
3. **`server/` and `client/`.** Parsed and their top level run, on a short list of
   named stubs for the game globals those top levels touch: `isClient`/`isServer`,
   `Events` (one auto-filled table with a no-op `Add`), `getText`, `MapObjects`, and
   six class roots (`ISBaseObject`, `ISCollapsableWindow`, `ISBaseTimedAction`,
   `SGlobalObject`, `SGlobalObjectSystem`, `CGlobalObject`, `CGlobalObjectSystem`)
   whose `derive()` makes a child that derives in turn. A file whose top level ever
   wants more than that goes on `PARSE_ONLY` in `KahluaRun.java` and is parsed only,
   and the report says so for that file — the list stays short on purpose, because a
   growing pile of stubs is a second game, not a test.

`require` is the game's semantics, not Lua's: a name resolves to one of our files
under `shared/`, `server/` or `client/` and loads it once; a second `require` of the
same name is a no-op. A `require` of one of the game's own files (`Map/SGlobalObject`,
`ISUI/ISCollapsableWindow`) is a no-op too, and the run prints the list of those
rather than hiding them.

Two bits of plumbing, both forced and both in the script's header: the game's classes
are Java 25 class files and the `javac` on this box is 21, so `KahluaRun` reaches
Kahlua by **reflection** and *runs* on the game's bundled `jre64`; and Kahlua's
`setupEnvironment()` reads `stdlib.lua` as a path relative to the working directory,
so the java process runs **in the game folder** and takes the repo root as its
argument.

**What it proves:** that Kahlua parses every file we ship, that the engine's top level
runs on Kahlua from a cold environment in the game's order, and that every engine
function the outer layers call by name exists once that load is done.

## The probe: the same functions RUN on both VMs, and the answers compared

Loading proves a file parses and that its top level survives. It proves **nothing
about what the standard library answers.** On 2026-09-12 the first power-on of a
prefilled machine died with `__add not defined for operands in placeLog`, and the
cause was one line: `tonumber(s, 16)` goes through `Integer.parseInt(s, 16)` in
Kahlua (`javap -c se.krka.kahlua.vm.KahluaUtil`: base 10 is `Double.parseDouble`,
every other base is `Integer.parseInt`, and the `NumberFormatException` lands in a
catch that returns `null`). So it answered **nil** for every eight-digit hash from
`80000000` up -- half of them -- while every file loaded and every lua5.1 suite was
green. The fix is `CeroSecOS.hexValue`, which multiplies the digits out by hand and
is the only way the mod parses hex.

`tests/kahlua-probe.lua` is what would have caught it. It calls the engine's **pure**
functions with fixed inputs and prints one line per result, and `kahlua-run.sh` runs
it twice -- once with `lua5.1`, once on the game's Kahlua through
`KahluaRun --eval <file.lua> <root>` -- and **fails on any line that differs**, with
the diff. `--eval` loads `shared/` quietly, installs a `print` that renders its
arguments with the VM's own `tostring` (`KahluaUtil.tostring`, because Kahlua's
`BaseLib.print` hands its text to a callback the game installs and there is no game
here), and runs the file.

What it covers: `CeroSecOS.hexValue` at the edges (`7fffffff`, `80000000`,
`ffffffff`, upper case, empty, a non-digit, a non-string), `CeroSecOS.digest` at 0,
16 and `HASH_ROUNDS` rounds including bytes 0 and 255, `CeroSecContent.derive` /
`key` / `number` / `chance` on a fixed secret, `CeroSecOS.phoneKey` and `phoneText`
at both ends of the exchange, the `string.format` patterns the shell's columns are
built out of (`%5.2f`, `%-8s`, `%02d`, `%x`, `%%`), `math.fmod` and `%` on negatives,
`math.floor` of a negative, `tostring` of `1e15` and of `1/3`, `string.byte`/`char`
at 0 and 255, `string.rep`/`sub`/`gsub`/`find`, `table.concat`, and the clock-free
calendar the log placer steps in (`timeFromParts`, `dateParts`, `formatDate`,
`formatTime`, `formatStamp`).

Adding to it: print a **line**, named, for anything the engine gets out of the
standard library or out of arithmetic. Never print anything that depends on a clock,
a random number, `pairs` order or a path -- it has to be a pure function of nothing
or the diff cries wolf. The raw `tonumber(s, 16)` is deliberately **not** probed: it
answers nil on Kahlua and a number on lua5.1 and always will, so a line for it would
be a red that can never go green. The `hexValue` lines are the canary instead: point
`hexValue` back at `tonumber` and they differ, which is how the probe was proven to
catch the bug it was written for.

### The probe is RED on landing, and on purpose (2026-09-12)

It is not red for the bug above -- that one is fixed and its four lines agree. It is
red because it immediately found a **second and much larger** divergence, which is
written down here rather than hidden by trimming the probe:

- **`CeroSecOS.digest` answers differently on the two VMs.** `digest("", 16)` is
  `1c016990080ede755131cf2f9b0ecd65` under lua5.1 and
  `7eb118b8d258f3e9f18d63987b1a55aa` on Kahlua, so `CeroSecContent.derive` and every
  password hash differ *in the game* from every value in `tests/`, in
  `tests/fixtures/` and in `docs/CONTENT.md`.
- **The cause is Kahlua's `%` operator**, proven from
  `javap -c se.krka.kahlua.vm.KahluaThread`, `primitiveMath`, case `OP_MOD`:
  `a % b` is compiled as `a - (int)(a / b) * b`, and that `(int)` is Java's `d2i`,
  which **clamps at 2147483647**. So `%` is simply wrong whenever `a / b` reaches
  2^31. Measured at runtime on both VMs: with `big = 47564 * 3266489917`,
  `big % 65536` is `60828` under lua5.1 and `14629838122396` on Kahlua. That is
  exactly the shape of `mul()` in `CeroSecOSUsers.lua` -- `(ah * b) % 65536` -- which
  is the bottom of the mixer, so every hash the game has ever computed is a different
  number from every hash the bench has ever computed.
- Kahlua's `%` also **truncates toward zero** where Lua floors, so `-7 % 3` is `-1`
  on Kahlua and `2` under lua5.1, and `tostring` renders a non-integer double the
  Java way (`1.0E15`, `0.3333333333333333`). Those three lines of the probe are pure
  VM facts with no fix in the mod; they need a decision of their own (record the
  expected difference, or stop probing them).

Fixing the mixer is not a one-line change and it is **not reversible for a save**: a
password already stored on a machine was hashed the Kahlua way, so making the two VMs
agree invalidates it. That is a decision, not a fix, and it is open.

**What it does not prove.** It is a load, not a game.

- The environment is Kahlua's own (`J2SEPlatform.newEnvironment()` plus the game's
  `stdlib.lua`). The **game's own Lua** is not there: none of `media/lua/shared/**` of
  the base game, no `ISBaseObject`, no `luautils`, no `Translate` — the class roots
  above are stubs of the right shape, nothing more. A call into vanilla Lua that is
  wrong is still only caught by `javap` and by playing.
- The **event bus is a no-op**. `Events.OnFoo.Add(f)` is accepted and `f` is never
  called, so nothing past load time runs: no tick, no `prerender`, no packet, no
  timed action. Those are `selfcalls-check.sh`, the lua5.1 suites, and the manual
  checklists.
- No Java at all: no `IsoObject`, no `getSquare()`, no ModData round trip. What a
  stub returns is what the file sees.

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
status is the answer. Read that status, not the last line printed — `selfcalls-check.sh`,
`kahlua-check.sh` and `kahlua-run.sh` are deliberately not piped into anything for the
same reason, a pipe would hide their exit status from `set -e`.

