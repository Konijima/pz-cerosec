# CeroSec — Testing

`sh tests/run.sh` runs every headless suite, in order, and needs `lua5.1` on the
PATH. It exits non-zero the moment anything fails; treat that exit code as the
verdict, never the human-readable tail of the log.

See also: [PARCOURS-TEST.md](PARCOURS-TEST.md), [TEST-rung1.md](TEST-rung1.md),
[TEST-rung2.md](TEST-rung2.md) and [TEST-rung4.md](TEST-rung4.md) for what no
headless suite can reach — the sprite, the context menu, sitting down, the glow,
what is actually on screen. [CONTRIBUTING.md](CONTRIBUTING.md) for when a change is
done enough to run this and open a pull request.

The suites, in the order they run:

- `defs_test.lua` — the shared definitions (sprites, facings, state).
- `os_test.lua` — the OS core: filesystem, permissions, users, shell, passwords.
- `terminal_test.lua` — the pure parts of the terminal: hostname, console, history.
- `compat_computermod_test.lua` — living beside the Workshop mod *Computer Mod*:
  who owns a desktop, and which of the two fillers gets the right-click. Against
  a **double** of that mod, not the mod itself, so what it proves is the decision
  and the wire between our two client files -- never that the game behaves. The
  step that decides is in `docs/PARCOURS-TEST.md`, section AR.
- `window_test.lua` — the window wired to the machine end to end: type a line, get
  an answer on the glass, and a script's output, question and `^C` through it.
- `window_test.lua` also holds the network bench: three real machines on one real
  system, two in a building and one down the road, one of them with its square
  and its `IsoObject` taken away after it was switched on. The telephone section
  uses the same two buildings four hundred squares apart -- where not one
  r-command reaches and `cu` does -- with a fake `getSandboxOptions` and a world
  age, so the grid can be killed under a call that is up.
- `window_test.lua` also holds the **mall** bench (premises v2): one building with a
  music store, a dentist, a clothes shop, the dentist's stock room, a break room and
  a hall, laid out so that every branch of the premises rule has a square in it. It
  asserts three segments, three lines, three profiles and three passwords that do not
  open each other, that the stock room is the dentist's and the hall the building's,
  that a machine keyed under v1 re-keys on load and keeps its accounts, and that the
  phone book prints the three shops under the numbers their own machines answer on.
  Beside it: a gun shop with a back office that must stay ONE premises, a house, a gas
  station of one-tile pump islands, and a shop with a mezzanine. Eight mutations are
  recorded against it, and two of its rooms exist only because a mutation walked
  through the first draft -- see the commit and
  [notes/tenancies.md](notes/tenancies.md).
- `window_test.lua` also holds the unload bench: one machine of that same system with
  everything the world owns behind a single switch -- its square, its `IsoObject`, the
  room its devices are in and the cell that answers for its tiles -- so the streamer
  can be made to take a chunk away with a session open on the machine and a crontab
  due, and to bring it back with or without a wire in the wall. It is the bench for
  the rule in
  [ARCHITECTURE.md](ARCHITECTURE.md#the-chunk-that-goes-away), and it carries its own
  control: a machine the sweep CAN see still goes off when its room does.
- `window_test.lua` also holds the **reload** bench: `bench.save()` fires
  `Events.OnSave` and then walks the object's saved keys the way the game's
  serializer walks them -- strings, numbers, booleans and nested tables, anything
  else dropped on the floor -- and `bench.reload()` builds a WHOLE NEW server out of
  nothing but those bytes, through `SCeroSecSystem:newLuaObject`, which is the road
  every machine in a save file comes in by. So a daemon started with `&` is asserted
  to come back and shut a door that was not even open when the save was taken; a
  foreground job to come back still holding the glass with the console's own
  variables under it; a killed job, a machine switched off, a computer picked up and
  a pending `shutdown` to bring nothing back at all; and a book spoiled eight
  different ways to load as no jobs, a line in the log and a machine that still
  answers a command. The cycle a pipeline's stage makes is proved against
  `CeroSecOS.validate` itself rather than asserted, and so is the arithmetic behind
  `CeroSec.JOB_SAVE_TABLES`: the bench BUILDS the worst legal state there is -- every
  one of 512 nodes a directory, with a 32-node floppy the same -- checks the gate
  takes it, counts the tables the gate would spend on it, and asserts that number
  plus the book's ceiling still leaves a tenth of the budget unspent. A comment
  carrying that arithmetic was wrong by a factor of two before the bench existed.
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
- `window_test.lua` also holds the **television** bench, and it is the one bench
  in the mod with **two fake worlds in it**. Every other actuator's sync is the
  engine's, so a bench can assert it by counting calls on one object; a
  television's is the mod's own packet, and a bench where the server's write and
  the client's apply land on the same table cannot tell a sync that happened from
  one that did not — it would be green on a mod that sent nothing. So a second
  world with a second television on the same square receives the packet through
  the client's real `Events.OnServerCommand` door, and what is asserted is that
  the far set moved, that it moved through the **raw** setters, and that the
  public ones — which would transmit and bounce — were never called. Beside it:
  both swallowed orders refused before the engine is asked (a dead grid, a flat
  battery, a dial outside the set's span), a refused write sending no packet at
  all, a stale object index falling through to the scan behind it, and the
  schedule read against a faked channel list whose blocks are deliberately **out
  of order**, because nothing in the engine sorts them. That fake's
  `getValidAirBroadcast` raises rather than answering: it is not a reader, and a
  fake that simply lacked it would make the mistake a crash instead of a
  sentence.
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
  secret must differ. Section 4h switches a whole premises on one machine at a time
  with the desk register in its hand -- a shop of six comes out one desk and five
  display models, an office of five comes out three desks and two spares, and the
  three men with a desk are the same three in every order the machines are switched
  on in. Section 4b2 owns the pure half of the automation: that "has a nightly job"
  is derived from the crontabs a profile really writes (walked by hand from the same
  table `placeCron` writes from, so a `hasJob` that grew a list of its own would
  disagree with it), that the roll can never say yes to a profile with nothing to run,
  that about one premises in three comes out yes over four hundred of them, and that
  the still-logged-in odds really move when the better ones are handed over. Two of its
  assertions are made on a profile invented in the bench, because no profile the
  catalogue ships has two accounts with a crontab and the rule about which of them wins
  would otherwise be green either way. See [CONTENT.md](CONTENT.md).
- `window_test.lua` holds the halves of that only the world can answer: that a
  machine is prefilled at its **first** power-on and never when it already had a
  state; that the papers in a drawer and in a pocket carry a password the machine
  then accepts — fired through the engine's own `Events.OnFillContainer` with the
  engine's own three arguments; that **a paper written from a drawer in one room
  opens the machine in another room of the same building**, which is the regression
  a review caught in this change; that the event's third argument being *not* a
  container is never read (the bench hands over an object that raises on any field
  read); and that `setModDataKeys` really names both persisted fields while the
  client sync list names neither — the one line the whole change rests on, and until
  it was written down there the suite stayed green with the save persisting nothing
  at all. It also holds the wire the desk register hangs on: that the room a machine
  stands in really reaches the catalogue, so a computer on a shop's sales floor comes
  up as stock and the one in its back room comes up as the shop's own. That one is
  worth its own line because a square answering no room at all would have left every
  bench in `content_test.lua` green while putting the shop's ledger on a machine the
  public types at.
- `window_test.lua` also holds the **mall-scale** automation bench: a fake mall of
  thirty shops of sixteen rooms each and twenty halls, five hundred rooms, whose
  chunks arrive twenty rooms at a time and never all at once, so the premises has to
  finish wiring itself without ever seeing its building whole. It counts the squares
  and objects the fake handed over -- not milliseconds -- and asserts that no minute
  walks more than `CeroSecAuto.ROOMS_PER_MINUTE` rooms' worth, that no room is walked
  twice over forty minutes, that the record converges to `wired` and drops its room
  set, and that not one of the other twenty-nine shops grows a relay.
- `window_test.lua` also holds the **automation** benches, and they run over a whole
  building: the two `MapObjects` maps told apart (the fake keeps both and fires each
  through the engine's own per-object walk, so what each path does and does not do is
  asserted, counts included); the decision written once on the system and then
  asserted not to move when a second computer of the same premises turns up; the
  fixtures fitted through the real module writer and found by the real discovery;
  **nine o'clock and seven o'clock asserted on the light switch object itself**,
  through the real cron pass, the real shell and the real `/dev`; the display model
  that never carries it; no power; the option off; a house, which has no nightly job
  to leave running; a room whose chunks are away and then arrive; and a survivor who
  unscrews a pre-fitted relay, gets the item, and does not find it back on the plate.
  Three of these were green for the wrong reason when first written, and the note at
  the head of the section says which and why — the worst was a desk searched for with
  the wrong hash, so the machine stood on a square the bench had no reason to believe
  anything about. It also names the one rule here carried three times over, because
  breaking any single carrier of it leaves the suite green.
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
  has to be a command it really has not. An entry marked `world` is not a command at
  all — the machine found still logged in — and is held to the literal `phrase` it
  carries rather than to its name, because its name is a word the page already uses
  for something else and would be green on a page that never mentioned it.
- `hostile_test.lua` — the one that matters to a server owner: an endless loop, a
  script that runs itself, a doubling string, an output flood, a hundred background
  jobs and a substitution bomb, each driven through the real scheduler for a
  thousand passes, asserting a flat cost per pass, a bounded console, bounded
  memory and the cpu ceiling firing where it should. It prints the numbers. Since
  fidelity A it also holds the two new commands a hostile player would reach for: a
  `more` standing at its `--More--` prompt for a thousand passes, which must cost
  **nought** steps (a pager that spun would be one), and a `find` over a disk filled
  to its node ceiling, which must be one command and not two. And since the debts
  wave, the three things that do more work than a command's worth: a loop of
  `find -exec` over a hundred matches and a loop of `tar cf` over a full home, both
  of which must stay inside the budget by taking a turn at a time (turn them into
  one call and the ms a pass climbs tenfold), and six machines with a queue of at
  jobs as full as a directory gets, waiting for a hundred minutes, which must cost
  **nought** steps a pass -- a waiting job is not a running one. And the **county**
  block, which is the other axis -- not one player's script on one machine but three
  hundred machines in one save, forty of them on, ten with crontabs. It is the only
  suite that loads the server's own files (the object, the system, the devices, the
  automation) and it asserts COUNTS before clocks: that the minute sweep never asks
  the system for a machine by index (the county walk's one door), that it decides
  about the forty that are on and no others, that the same is true with a thousand
  machines in the file, that every path a machine comes on by puts it in the sweep's
  index and every path it goes off by takes it out, and that five thousand `open`
  packets with a fresh token each leave ONE window open and a screen costing one
  answer. Those five thousand are **paced a second apart** on the fake clock (26c):
  the server drops an `open` past the fourth in a real second, so a flood sent in one
  instant would make every one of those assertions green for the rate limit's reason
  instead of the watcher table's. The rate limit has its own block on its own clock
  (26d), and what it asserts is a COUNT too -- four full opens of five thousand,
  counted at `sendHistory`, one line in the log and one entry in the book. The
  milliseconds are printed beside them and the ceiling on them is deliberately
  generous: what it has to catch is the county coming back into the walk or the state
  validator coming back onto the read path, not a box that is also running a game.
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
- `debug_ui_test.lua` also holds the two buttons of the self-test work and the
  `note` they answer with: a verdict on the line under the list, a refusal
  outranking it, a verdict after a refusal replacing it, and both going when
  another machine is selected.
- `selfcalls-check.sh` — every `self:method()` called is defined somewhere, since
  Lua only resolves a method when it is called and a missing one is a silent nil
  call, not a syntax error.
- the **stale-vector guard** — `tools/make-selftest-vectors.lua` regenerated into a
  temporary file and diffed against the committed
  `CeroSecSelfTestVectors.lua`. Not a suite: a two-line check that the numbers the
  in-game self-test weighs the game against are this build's and not last week's.
  The fix for a red is to run the generator, never to edit the table.
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
are Java 25 class files and a `javac` older than 25 cannot read them, so `KahluaRun` reaches
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
the diff.

The body of it is **not in `tests/`**. It is `CeroSecSelfTest.vectors`, in
`42/media/lua/shared/CeroSec/CeroSecSelfTest.lua`, which is a file the mod ships --
so one body has three readers and there is nothing to drift: the probe prints it on
both VMs, `tools/make-selftest-vectors.lua` writes lua5.1's answers down, and
`CeroSecSelfTest.run()` runs it **inside the game**. See the third layer below. `--eval` loads `shared/` quietly, installs a `print` that renders its
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

Adding to it: a `say()` line, named, in `CeroSecSelfTest.probe`, for anything the
engine gets out of the standard library or out of arithmetic -- and then
`lua5.1 tools/make-selftest-vectors.lua`, or `tests/run.sh` goes red on the stale
table. Never print anything that depends on a clock,
a random number, `pairs` order or a path -- it has to be a pure function of nothing
or the diff cries wolf. The raw `tonumber(s, 16)` is deliberately **not** probed: it
answers nil on Kahlua and a number on lua5.1 and always will, so a line for it would
be a red that can never go green. The `hexValue` lines are the canary instead: point
`hexValue` back at `tonumber` and they differ, which is how the probe was proven to
catch the bug it was written for.

### The three rules the probe cannot carry, and one grep that can (2026-09-12)

The probe found a second and much larger divergence the day it was written, and
that one is fixed too: **`CeroSecOS.digest` answered differently on the two VMs.**
`digest("", 16)` was `1c016990080ede755131cf2f9b0ecd65` under lua5.1 and
`7eb118b8d258f3e9f18d63987b1a55aa` on Kahlua, so `CeroSecContent.derive` and every
stored password differed *in the game* from every value in `tests/`,
`tests/fixtures/` and `docs/CONTENT.md`.

The cause, from `javap -c se.krka.kahlua.vm.KahluaThread`, `primitiveMath`, case
`OP_MOD`: Kahlua compiles `a % b` as `a - (int)(a / b) * b`, and that `(int)` is
Java's `d2i`, which **clamps at 2147483647**. So the `%` operator is wrong the
moment the quotient reaches 2^31. Measured at runtime on both VMs, with
`big = 47564 * 3266489917`: `big % 65536` is `60828` under lua5.1 and
`14629838122396` on Kahlua -- and `(ah * b) % 65536` is exactly the line at the
bottom of `mul()` in the mixer. `CeroSecOS.mod(a, b)` = `a - math.floor(a / b) * b`
replaces it, and the whole mixer goes through that expression -- written out by hand
inside `mul()`, `rotl()` and `absorb()` rather than called, because the mixer is the
one hot loop in the mod and a call per modulo took a 4000-round hash from 4.3 ms to
18.4 ms under lua5.1 (7.7 ms as it stands, against the 50 ms `os_test` allows, and
Kahlua is several times slower again). Everything outside that loop calls
`CeroSecOS.mod`. lua5.1's answer is the canonical
one and did not move, so no fixture and no documented value changed; the game now
agrees with them. `math.fmod` is **not** affected -- it is `MathLib` and agrees on
both VMs at every size and both signs, which the probe pins.

Three rules come out of it, and they are rules rather than probe lines because a
line for any of them could never go green:

1. **Never `tostring` a non-integer.** Kahlua renders a double the Java way
   (`1.0E15`, `0.3333333333333333`); lua5.1 uses `%.14g` (`1e+15`,
   `0.33333333333333`). `math.floor` first. This one IS greppable and is now
   checked: `kahlua-check.sh` fails on a `/` or `*` inside `tostring()` without a
   `math.floor` in the same call (`forbid_unless`, proven by mutation).
2. **Never `%` a negative.** Kahlua truncates toward zero where Lua floors, so
   `-7 % 3` is `-1` there and `2` here. Normalise the left operand first, the way
   `scatter()` in `CeroSecOSNet.lua` already does (`if h < 0 then h = h + 65536`).
3. **Never `%` when the quotient can reach 2^31.** Use `CeroSecOS.mod`. Not
   greppable -- it is a fact about operand ranges, not about text -- so it is
   reviewed: the audit of every modulo in `42/media/lua/shared/CeroSec/**` is in
   the commit that introduced `CeroSecOS.mod`.

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

## Three layers, and what each one actually proves (2026-09-13)

Two Kahlua-only bugs shipped past a green suite in one day. Neither was a missing
assertion: the suite was asking the right questions of the **wrong VM**. So there
are three layers now, and it is worth being precise about where each one stops,
because a reader who thinks the first one covers the third will keep shipping the
same class of bug.

**1. The lua5.1 suites (`sh tests/run.sh`).** Every rule of the engine, every
refusal, every ceiling, every screen — twelve thousand assertions in
`content_test.lua` alone. What they prove: the mod is **correct**, on the VM it was
written to. What they cannot see: anything the standard library answers differently
somewhere else, and anything that needs a game.

**2. The offline Kahlua probe (`sh tests/kahlua-run.sh`, inside `run.sh`).** Every
shipped Lua file loaded on the game's own Kahlua out of `projectzomboid.jar`, and
then `CeroSecSelfTest.vectors` **run** on both VMs with the outputs diffed byte for
byte. What it proves: every file parses and its top level survives there, and the
engine's pure functions — the hex parser, the mixer, the hash, the derivation, the
date arithmetic, the shell's `$(( ))` reader — give the **same answers** on both.
What it cannot see: the game's own Lua (none of vanilla's `media/lua/**` is
present), the event bus (`Events.OnFoo.Add` is accepted and never fires), Java of
any kind, and therefore the world, the save file, the wire and the sync.

**3. The in-game self-test (the debug window's `Self-test` button, and
`sh /mnt/selftest.sh` off the diagnostics floppy).** Two halves:

- `CeroSecSelfTest.run()` evaluates the very same vectors **in the save**, on the
  Kahlua the game is actually running, with the game's own `stdlib.lua` and every
  vanilla file loaded, and weighs each answer against
  `CeroSecSelfTestVectors.lua` — lua5.1's answers, generated by
  `tools/make-selftest-vectors.lua` and committed, because there is no `lua5.1` in
  the game to ask. Every failing line goes to `CeroSec.log` at **warn** (the Log
  tab's own filter) and the summary to info and to `print`, so `console.txt` holds
  it. It also asks the three key lists the save and the wire are made of, which is
  where `seed` is held to being saved and never synced.
- `CeroSecSelfTest.runSave(luaObject)` walks the save path of the selected machine:
  `stateToIsoObject` writes the mirror, `osFromIsoObject` reads it back, the whole
  mirror entry goes through a copy keeping only what `KahluaTable.save` keeps, and
  the state in it is handed to the boot gate. It is the one thing no offline bench
  can be asked, and what it can catch is a **mirror field**: `os` is validated on
  every read, while `v`, `on` and `facing` ride into the save file weighed by
  nothing — drop `facing` and a computer picked up and put down faces the wrong
  way, with a green suite behind it.

And `sh /mnt/selftest.sh`, which is the other half again: twenty-six checks of the
**shell** — `echo`, a pipe, `cut`, `sort`, `wc`, `grep -c`, `more`, `tee`,
`$(( ))` at a quotient over 2^31, `for`, `while`, `read` off a pipe, `mkdir`/`rm`,
`test` on files, `chmod`, `find`, the clock, `df`, `mount`'s label, `ls -l /dev`,
`dev`, `hostname`, `id`, `uptime`, `mkpasswd` against a baked canonical hash, and
`sleep`. None of that is a pure function of nothing: it is commands, redirects and
a filesystem, driven by the step machine, on the VM the game has.

### Where each layer's numbers come from, and the two guards that keep them honest

The vectors are **generated** and committed, which is two ways to go stale, so
there are two guards and they work from opposite ends:

- `tests/run.sh` regenerates the table into a temporary file and **diffs** it. A
  `say()` line added to the body, or an engine answer that has legitimately moved,
  is a red suite with the diff printed and one instruction: run
  `lua5.1 tools/make-selftest-vectors.lua`. Never edit the table.
- `CeroSecSelfTest.run()` counts three kinds of failure, and only the first is the
  obvious one: an answer that differs, **a vector nothing evaluated** (a line taken
  out of the body), and **an answer with no vector** (a line added). The middle two
  are how a generated table goes quietly green, and an empty table is a failure
  rather than a pass of nothing — which is how the whole button would have passed
  on a build that shipped without the generated file.

The floppy's one baked number gets the same treatment from the other side.
`selftest.sh` has `$cs1$abcdef$74a6...` written into it, because there is no
`lua5.1` in the game to ask for it — and `content_test.lua` section 7c holds that
string to `CeroSecOS.hashPassword(CeroSecSelfTest.PASS_TEXT, PASS_SALT)`. So the day
`HASH_ROUNDS` or the mixer moves, the headless suite is red and the floppy is
rewritten, instead of the in-game run going red for a reason nobody can place.

Section 7c also **runs** the floppy under the engine and holds it to `FAIL 0`,
asserts the pass count against the number of verdict lines the script declares — a
check added without the count following is that line — and then breaks one check to
prove `FAIL 0` is an assertion and not a sentence the script prints either way.

### What the shell suite could not be asked, and why

Two things on the wish list are not on the floppy, and both for the same kind of
reason:

- **A crontab round trip.** A crontab is writable only through `crontab -e`, which
  opens the editor and wants a terminal; a script has none, and `crontab` takes no
  file operand (real `crontab file` does; ours is `-e|-l|-r`, which is what keeps
  one account from writing a line that runs as another). So the script asks
  `which crontab` and the round trip is a step in
  [PARCOURS-TEST.md](PARCOURS-TEST.md) section X instead.
- **A permission REFUSAL.** `chmod 600` is checked by reading the mode back, but
  "and now another account cannot read it" needs a second account, and `su` and
  `sudo` both put a password question on the glass — which a script cannot answer.
  One account can only test what one account can. The refusal is `os_test.lua`'s,
  many times over, and section X's on the glass.

## The millisecond ceilings are calibrated, not fixed

`hostile_test.lua` is the only suite that asserts on real time, and a bare
millisecond number says as much about who else is on the machine as it does about
the engine. On a machine that is also running the game and other heavy work
(load average 5 to 9) the 4 ms ceiling went red two runs in three at 4.1 to 5.5 ms
— on the untouched base as much as on a branch that touched no engine file. A red
that says nothing about the code is noise, and noise trains a reader to ignore the
colour.

So the ceilings stay and the yardstick moves. Right before the first timed section,
in the same process, the bench times a fixed pure-Lua workload (arithmetic and table
writes, nothing of the engine in it, a few tens of milliseconds), three times, and
keeps the cheapest run — the cheapest is the one that got the most of the processor.
That over `CALIB_REF_MS`, the value the same workload costs on an idle machine, is a
scale factor, and every millisecond ceiling in the file becomes `limit * max(1,
scale)`:

- an idle machine scales by 1 and is held to exactly the strict number it always was,
- a machine that is half taken gets an allowance in proportion to how slow **it** is,
- past **3×** there is no allowance at all: the bench refuses with `machine too loaded
  to measure: rerun idle` rather than pretend it measured something.

The scale and the raw milliseconds are printed on the bench's `calibration` report
line, so any figure below it can be read back against the machine that produced it.
`CALIB_REF_MS` is a measurement of one machine and belongs to it: its comment in
the file says when, how and on what it was taken, and it is re-measured — on a
machine with nothing else on it — not guessed at. If the ceilings read wrong on
yours, re-measure and say so in the change; do not raise a ceiling to make a red
go away.

What is **not** scaled: every step-count assertion. Steps are the real budget proof
and a step costs the same on a loaded machine as on a quiet one; a loaded machine is no
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

