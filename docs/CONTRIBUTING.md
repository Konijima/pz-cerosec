# Contributing to CeroSec

Thank you for looking. CeroSec is a Project Zomboid Build 42 mod that simulates a
1993 Unix machine, and almost every rule below exists because breaking it either
cost somebody his save or put a behaviour in the game that no real machine ever
had. Read this page before your first change; it is short for what it covers.

Everyone taking part is held to the [Code of Conduct](../CODE_OF_CONDUCT.md).

See also: [TESTING.md](TESTING.md) (what each suite proves),
[SECURITY.md](SECURITY.md) (the rules a review looks at first),
[ARCHITECTURE.md](ARCHITECTURE.md) (the persistence rules a version bump obeys),
and [../CLAUDE.md](../CLAUDE.md) if you work with Claude Code.

**A note on the git history.** This mod was written with Claude Code, and commit
messages in the history carry session trailers that say so. That is the record of
how it was built and it is left exactly as it is. New commits do not need them,
and no *file* in the tree should mention anybody's tooling, machine or paths —
`tests/public-check.sh` fails the suite if one does.

## How to report a bug

Open an issue using the bug template. The four things that make a report
actionable:

1. **The build number** — the game's, exactly (`42.20.4`, not "latest").
2. **Your mod list.** CeroSec touches computers, doors, lights and the radio; a
   mod that also touches them is the first suspect.
3. **The `console.txt` lines around the failure**, not just the last one. It is
   at `~/Zomboid/console.txt`. Set `CeroSec.DEBUG = true` in
   `42/media/lua/shared/CeroSec/CeroSecDefs.lua` to get this mod's own lines.
4. **Where on the glass it happened**, as a step of
   [PARCOURS-TEST.md](PARCOURS-TEST.md) if you can find it there — that turns a
   report into a reproduction.

A save that shows the bug is worth more than a description of it.

## Translations

Very welcome, and they need no code. Copy
`42/media/lua/shared/Translate/EN/` to your language code
(`42/media/lua/shared/Translate/<CODE>/`) and translate the *values*, never the
keys. `FR/` is there as a worked example of a complete set.

Two cautions specific to this mod:

- The terminal is **60 columns** and does not wrap a line. Anything that reaches
  the glass has to fit, and a translation that is four characters longer than the
  English is a line cut off in play.
- The in-game manual (the three volumes) is Lua prose, not a translation file. It
  is not translated yet, and a change that starts translating it should say how it
  intends to keep the pages and the code in step — see "The manual" below.

## The project's rules

### Faithful to 1993 Unix; invent nothing

Where a real `/bin/sh`, `cron`, `rlogin`, `uucp` or a Hayes modem would answer a
certain way, this machine answers the same way — refusals and error wording
included. A behaviour with no real-world model is a behaviour to question, not to
design. The commands wear the names 1993 gave them: `useradd`, `userdel`,
`usermod -G` (System V, 1989), never Debian's `adduser` or shadow-utils'
`gpasswd`.

**A deviation is allowed, and it is declared.** The handful of things with no 1993
model that are kept anyway — `help`, `dev`, `mkpasswd`, `edit`, `sudo`, and jobs
that belong to the machine rather than to the shell — are listed in
`CeroSecOS.DEVIATIONS` *and* written on a page of the in-game Volume 1, *What is
not Unix here*. A bench checks the list against the page in **both** directions,
so a deviation that is not declared is a red, and a declaration with nothing
behind it is a red too. If your change deviates, add it to both.

A deviation that is **not a command** — the one machine in four found at somebody's
prompt after a power cut is the worked example — is marked `world = true` and carries
the `phrase` the page has to say, literally. Its name alone cannot be the check: a
word like `login` is already on that page for another reason, so the bench would be
green on a page that never mentioned the deviation at all.

### The sources of truth, in order

1. **The game's own Lua**, under
   `<steam>/steamapps/common/ProjectZomboid/projectzomboid/media/lua/`. If vanilla
   does a thing a certain way, that is the way.
2. **`javap` on the jar that is installed right now.**

   ```
   javap -p -c -cp <path to>/projectzomboid.jar zombie.iso.IsoObject
   ```

   Quote the signature, and for anything about *when* a field is written, the
   bytecode offsets. [docs/notes/](notes/) is what that looks like done properly.
3. **A real Unix manual page**, for what the simulated machine should answer.

What is **not** a source of truth: any decompiled dump (the one commonly passed
around is months older than the jar and has been wrong here), any other mod, and
any answer that begins "it probably". Nothing is called on faith — a call that
was never proven to exist is a nil call in `prerender`, once a frame, and the
window is dead.

### Kahlua purity

The game runs Lua on **Kahlua**, not on PUC Lua 5.1, and the subset is smaller
than it looks:

- No bit library, no `string.pack`, no integer division, no `goto`, no `%b`
  patterns. `tests/kahlua-check.sh` greps for the constructs that are known to
  break and it is the cheap half of the guard.
- `tonumber(s, 16)` is not PUC Lua's `tonumber(s, 16)`: Kahlua has
  `Integer.parseInt` behind it and returned `nil` for half of all hashes while
  every `lua5.1` bench stayed green and the game died on the first power-on of a
  prefilled machine. Anything you rely on from the standard library goes in
  `tests/kahlua-probe.lua`, which runs on **both** VMs and compares the output
  line for line.
- **No Lua is ever evaluated from a file**, in either direction. The OS core reads
  and writes plain data; nothing a player types or a script contains is ever
  handed to `load` or `loadstring`; and no player-supplied string reaches Lua's
  own pattern matching unescaped. This is the one rule a grep enforces rather than
  a reviewer.

`luac5.1 -p <file>` before you commit, always. It catches a syntax error; it
catches nothing else on this list.

### The three test layers, and how to run them

**Layer 1 — the headless suites.** Pure `lua5.1`, no game, no engine. This is
where almost all of the proof lives.

```
sh tests/run.sh ; echo $?
```

Needs `lua5.1` on the `PATH`. It is `set -e`, so it stops at the first failure,
and **its exit code is the verdict** — never the friendly last line. What each
suite covers is in [TESTING.md](TESTING.md).

**Layer 2 — the real Kahlua VM, out of the game's own jar.** Part of
`tests/run.sh`, and the layer that catches what `lua5.1` cannot: a Kahlua parse
error, a load-time nil call, a standard-library function that answers
differently. Prerequisites:

- The game installed. `tests/kahlua-run.sh` looks in the Steam default on Linux;
  set `GAME=` to the `projectzomboid` folder if yours is elsewhere.
- A `javac` on the `PATH` (`JAVAC=` overrides). Its version does not matter much:
  the jar's classes are Java 25, so `tools/KahluaRun.java` reaches Kahlua by
  reflection and *runs* under the game's own bundled `jre64`.
- `lua5.1`, to compare the probe against.

If the game is not installed, that layer cannot run and `tests/run.sh` will fail
on it. Say so in your pull request rather than deleting the block.

**Layer 3 — the glass.** Things no headless test can reach: the sprite, the
context menu, sitting down, the glow, what is actually drawn. The checklist is
[PARCOURS-TEST.md](PARCOURS-TEST.md) (French; an English version is welcome), with
[TEST-rung1.md](TEST-rung1.md), [TEST-rung2.md](TEST-rung2.md) and
[TEST-rung4.md](TEST-rung4.md) kept as they were read at the time. A change that
alters anything a player sees adds or updates a step there, and the maintainer
walks it before a release.

### Every change comes with benches, and the benches are checked by mutation

A new or changed assertion is not proven until it has been seen **red for the
reason it exists**. Before trusting one: break the thing it guards on purpose
(invert a condition, delete the line, comment out the write), watch the suite
fail *for that reason and no other*, put the code back, watch it pass. A suite
that has never gone red on the bug it claims to catch may be green because the
code is right or green because the assertion never runs, and there is no way to
tell the two apart by reading it.

Practical consequences that keep coming up:

- Assert the **state**, not the call. A bench that calls a function proves the
  function; the wire from the caller needs its own bench.
- Assert a **size or a count** where you can. An assertion of absence is green on
  an error, and a filtered list is not a lock.
- Print the numbers you assert on, the way `hostile_test.lua` does, so a reader
  can check the claim and not just the colour.

### The manual, the parcours and the changelog move in the same change

- **The manual.** A page describing a machine the code no longer builds is a
  stale page. `tests/manual_test.lua` pins every usage line and every error string
  the engine can print somewhere in the union of the three volumes, so changing
  the code is what breaks the page — fix the page in the same commit.
- **[PARCOURS-TEST.md](PARCOURS-TEST.md)** gets the step that walks your change on
  the glass.
- **`CHANGELOG.md`** gets its line under **Unreleased**, in the words a subscriber
  reads. At release the section takes its version and date and
  `python3 tools/changelog-steam.py` prints it as Steam Change Notes. A change
  without a changelog line is a change nobody will know shipped.

### Three version numbers, three homes, and no in-world string carries a fourth

The operating system's is `CeroSecOS.VERSION`
(`shared/CeroSec/OS/CeroSecOS.lua`), and everything a player reads that names it
— the greeting the boot ends on and a login is met with (`CeroSecOS.MOTD`, the
built-in `/etc/motd`), the manual's cover — is built from it. The firmware's is
`CeroSec.BIOS_VERSION` (`shared/CeroSec/CeroSecDefs.lua`), a separate component
with a separate number, printed by `CeroSec.BOOT_LINES[1]`. The mod's own release
version is `modversion` in `42/mod.info` and never appears in the world at all.
`tests/manual_test.lua` refuses a page that names an OS version of its own.

### Never work in the folder the game is loading

The game holds the mod folder open and reads from it. Work on a branch, or in a
`git worktree` off one, and merge only when `sh tests/run.sh` exits 0:

```
git worktree add -b my-change ../cerosec-my-change
```

Never reset a shared branch, and never prove a change by starting the game
instead of running the suite — starting the game proves that it loaded, which is
the one thing the suite already tells you.

## Repository layout

The repository root **is** the mod folder, at a real non-symlinked path under
`~/Zomboid/mods/` (the reason is in the [README](../README.md#install)).

- `42/` — `mod.info`, `media/lua/{shared,client,server}/CeroSec/`, translations,
  `sandbox-options.txt`.
- `common/` — sounds, textures, models, and the script files:
  `items_cerosec.txt`, `models_cerosec.txt`, `recipes_cerosec.txt`,
  `sounds_cerosec.txt`.
- `tests/` — headless, no game needed: `sh tests/run.sh`.
- `docs/` — this documentation, and the in-game checklists.
- `tools/` — the generators and checks: the icon and image scripts, the
  self-test vector generator, the fixture capture, `KahluaRun.java`, the
  Workshop helpers.
- `workshop/` — `workshop.txt`, the preview and the page art for the Steam
  Workshop uploader.

## Coding rules

- Vanilla only: no dependencies, no bundled libraries.
- Every game API used is proven first (see "sources of truth"). The sync-call
  table in [DEVICES.md](DEVICES.md) is the worked example.
- Keep example lines and shell output inside **60 columns** — the terminal is
  60x20 and does not wrap a code line.
- A timed action's validity is re-checked in `waitToStart`, not only in
  `isValid`, because the engine evaluates `isValid` before `waitToStart` and
  drops an action that stops being valid in between.
- A control marker (`clear`, `exit`, `prompt`, `edit`, ...) never travels in the
  same channel as text output — see [PROTOCOL.md](PROTOCOL.md).
- `SYSTEM_VERSION` bumps whenever a change adds a file to `/bin` or seeds a new
  system file or directory, and `sysv` (the *contents* a machine was built with) is what
  `CeroSecOS.upgradeSystem` tops an older machine up against on load — see
  [ARCHITECTURE.md](ARCHITECTURE.md#persistence). It puts in what is missing and
  never replaces what root has already changed or removed.
- Match the prose around you. The comments in this codebase explain *why*, with
  the proof beside the claim; a comment that only restates the line under it is
  not worth the space.

## Security rules

- No `eval`: nothing typed or read from a file is ever Lua. See
  [SECURITY.md](SECURITY.md#what-the-server-guarantees-against-a-script).
- No user-supplied pattern reaches Lua's own pattern matching unescaped —
  a string a player controls is a literal, not a pattern, wherever it is
  compared against one.
- Limits are asked of the **path**, never carried as a flag on the node: the
  history exemption, the exempt logs and mailboxes, and the floppy's own
  ceilings are all decided by where a write lands, so a rename or a mount
  cannot carry an exemption to where it does not belong. See
  [ARCHITECTURE.md](ARCHITECTURE.md#persistence) and
  [DEVICES.md](DEVICES.md#the-floppy-drive-and-the-second-filesystem).
- The server decides. A client asks; it never rules.

## The compatibility contract

**A mod update never costs a player what he built.** Everything below follows from
that one sentence, and it is not a preference: a computer in a save holds hours of
somebody's work — accounts, a filesystem, a script he wrote — and there is no
"restore from backup" in this game.

**Nothing is ever deleted. Not a state key, not an item, not a recipe, not a
sandbox option.** The replacement is always the same pair: *obsolete, and migrate*.

### Which number moves, and when

| what changed | number | what it does |
| --- | --- | --- |
| a file or directory the machine ships — `/bin`, `/etc`, `/var`, `/usr/local/bin` | `CeroSecOS.SYSTEM_VERSION` | `upgradeSystem` puts in what is **missing**, once, and never replaces what root changed or deleted |
| the **shape** of the state: a key renamed, dropped, or whose meaning changed | `CeroSecOS.STATE_VERSION` | a step in `CeroSecOS.MIGRATIONS`, walked on the way in |
| the shape of what is written on a **floppy** | `CeroSecOS.FLOPPY_VERSION` | a step in `CeroSecOS.DISK_MIGRATIONS` |
| the shape of a door's **modules** | `CeroSecModules.VERSION` | a step in `CeroSecModules.MIGRATIONS` |
| the shape of the **phone book** stamp | `CeroSecPhonebook.VERSION` | a step in `CeroSecPhonebook.MIGRATIONS` |

Seeding a file is *not* a shape change and must not move `STATE_VERSION`: the two
numbers exist precisely so that adding a command costs a machine nothing. Seeding a
**directory** is the same kind of thing and obeys the same rule as a file does: what
is already at that name is the player's, whatever it is. A *file* where the seeding
wants a directory stops the seeding there and is left alone (`/usr/local/bin` at
version 21 is the worked example, as `/bin/wall` is for a file).

### The rules for a step

- **`MIGRATIONS[n]` takes a state at `n - 1` and leaves it at `n`.** One step per
  number, no gaps — `tests/migrate_test.lua` walks the whole chain and goes red on a
  hole, and on a step that sits above the current number because somebody wrote the
  migration and forgot to move it.
- **Idempotent.** Run twice on one table it leaves it as the first run did. The bench
  winds the version back and walks again, comparing the whole machine byte for byte.
- **It is handed a table and nothing else.** No square, no player, no `SandboxVars`,
  no time of day: most machines in a save have no chunk loaded, so a step that asked
  the world could not run for them. A top-up that genuinely needs the world lives
  where the world is answerable and is called from there — the address and the
  telephone exchange in `CeroSecNet.identify`, the devices under `/dev` in the
  scheduler.
- **Read with a default, never with an assumption.** A field a change added is absent
  on every machine saved before it, and absent must read as the old behaviour — not
  as `false`, unless `false` *is* the old behaviour. `node.group` and `node.mtime` are
  the worked examples (see [ARCHITECTURE.md](ARCHITECTURE.md#persistence)).
- **A migration is the one thing allowed to rename or drop a key.** Where a namespace
  is closed — `CeroSecOS.diskFieldsOk` refuses any key a disk does not own — the old
  name goes on `CeroSecOS.DISK_LEGACY_KEYS` so the gate lets it past, and the step
  takes it off.
- **No meaning changes.** A key that meant one thing and now means another is a key
  renamed, with a step that converts it. Reusing the name is how a save comes back
  subtly wrong instead of loudly broken.
- **Newer than the code is refused, never repaired.** A player who rolls the mod back
  under a save a later build wrote gets his machine left exactly as it is and a line
  saying so. Writing this build's shape over a save its own author could still open is
  the one unrecoverable mistake in the whole file.

### Items, recipes and sandbox options

- **Never remove an `item` block.** A saved item is a registry id, not a name: a type
  no script declares any more resolves to nothing, `InventoryItemFactory.CreateItem`
  answers null, and the copy is dropped from the container with one line in the
  console. The reasoning is traced through the jar, offset by offset, in the comment
  over `item Manual` in `common/media/scripts/items_cerosec.txt`.
- **And the engine's `Obsolete = true` does *not* save it either.** It is a real
  script key and it does stop a type spawning, but it also makes
  `DictionaryInfo.isValid()` answer false, which is the very test that deletes the
  saved copy. It is the flag for *"this type is finished and so is everything made of
  it"*. Retiring an item means: keep the block, take it out of every loot table, and
  convert a copy into its replacement when somebody touches it
  (`CeroSecManualMenu.LEGACY` is the worked example — at READ time, which is the least
  invasive moment there is).
- **Never remove a recipe** a player may have learned, for the same reason: what he
  learned is a string in his character file.
- **A new sandbox option defaults to the OLD behaviour**, or the release notes say
  plainly that worlds change. `CeroSecModules.required` is the pattern: read the way
  vanilla reads a grouped option, and fail *closed* — a group nobody declared, a
  sandbox file that did not load and a save from before the option all answer the same
  thing, and that thing is a world the player can see and fix from the sandbox screen.

### Every release captures a fixture

`sh tools/capture-fixture.sh` photographs the save shape the current build writes into
`tests/fixtures/state-v<N>.lua`, and it is committed. Do it **before** bumping
`STATE_VERSION`, so the next release's chain has a real older machine to walk — see
[RELEASE.md](RELEASE.md). `tests/migrate_test.lua` refuses to pass without a fixture
for the shape one behind the current one, which is the save an update actually meets.

## Sending a change

1. A branch (or a worktree) off `main`. Small commits, each one a thing that
   works; a message that says *why*, not what the diff already shows.
2. `sh tests/run.sh` exits 0, and `luac5.1 -p` is clean on every Lua file you
   touched.
3. The benches for your change have been seen red for the right reason.
4. The manual, [PARCOURS-TEST.md](PARCOURS-TEST.md) and `CHANGELOG.md` are in step
   with the code.
5. Open a pull request; the template is the checklist. Say plainly what you could
   *not* verify — an unverified claim costs more to unpick than an honest gap.

## Workshop copy (maintainer)

Never link `~/Zomboid/Workshop/CeroSec/Contents/mods/CeroSec` to the repository:
the game scans that folder as a mod too, and through a symlink `ScriptManager`
builds a doubled path and loses every script file (items, sounds). At publication
time run `sh tools/workshop-sync.sh sync`, upload from the game's Workshop screen,
then `sh tools/workshop-sync.sh clean` so the game loads the real folder again.
The ordered checklist is [RELEASE.md](RELEASE.md).

## Licence and contributions

The mod is all rights reserved (see `LICENSE`). Contributions are welcome
the GitHub way: fork the repository, work on a branch, send a pull request.
By sending one you grant the author the right to ship your change as part of
the mod; you keep the copyright on what you wrote. Do not redistribute the mod
or a fork of it as a playable mod anywhere.
