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
  shape of every volume (8..13 chapters, 3..9 pages each, 50..76 pages, plain ASCII,
  nothing over a thousand characters, example lines inside sixty columns), every
  `COMMAND_INFO` usage line and every error string the machine can print carried
  somewhere in the **union** of the three, each volume's own rules (a card that is
  nothing but exact usage lines, every typed word a word the machine knows, every
  ceiling quoted as a phrase built from the engine's own constant), and eight facts
  pinned against the code so a change to the CODE is what breaks a page. There is no
  fourth book behind the set, and a shelf that is not three volumes fails here.
- `hostile_test.lua` — the one that matters to a server owner: an endless loop, a
  script that runs itself, a doubling string, an output flood, a hundred background
  jobs and a substitution bomb, each driven through the real scheduler for a
  thousand passes, asserting a flat cost per pass, a bounded console, bounded
  memory and the cpu ceiling firing where it should. It prints the numbers.
- `manual_ui_test.lua` — the manual: wrapping against a proportional font,
  pagination, the contents page, turning the leaves, opening each of three volumes
  off a fake shelf and opening blank paper for an id nothing answers to, a bookmark
  per copy and per volume, the dev submenu, the keys all four item blocks set and the
  icons they name, and the twelve loot lists times three volumes with the sandbox
  multiplier.
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

