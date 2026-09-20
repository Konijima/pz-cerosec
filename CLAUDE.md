# CLAUDE.md

Operating instructions for working on CeroSec with Claude Code. They are the
rules in [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md), written as things to do
rather than things to know. Read that page too; this one does not repeat the
reasoning behind every rule.

CeroSec is a Project Zomboid **Build 42** mod that simulates a 1993 Unix machine
on the game's vanilla desktop computers. Vanilla Lua only, no dependencies,
server-authoritative. The repository root **is** the mod folder.

## Before writing anything

1. Read the documentation index in [README.md](README.md) and open the page for
   the area you are touching: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the
   engine and persistence, [docs/PROTOCOL.md](docs/PROTOCOL.md) for the wire,
   [docs/DEVICES.md](docs/DEVICES.md) for `/dev`,
   [docs/NETWORK.md](docs/NETWORK.md) for coax, telephone and radio,
   [docs/SCRIPTING.md](docs/SCRIPTING.md) for the shell and the scheduler,
   [docs/CONTENT.md](docs/CONTENT.md) for what is already on the machines,
   [docs/SECURITY.md](docs/SECURITY.md) for the guarantees,
   [docs/TESTING.md](docs/TESTING.md) for what each suite proves.
2. Read the file you are about to change, whole, including its header comment.
   The comments in this codebase carry the proof beside the claim; the answer to
   "why is it like this" is usually already written above the line.
3. The design notes with the bytecode proofs behind the rules are in
   [docs/notes/](docs/notes/) — `modules-proofs.md` (what makes module modData
   persist), `picking.md` (what the right-click actually hands the menu, offset by
   offset), `workshop-study.md` (how Workshop pages are built). If a rule looks
   arbitrary, the proof is probably there.

## Sources of truth — never guess about the engine

In this order:

1. **The game's own vanilla Lua**, under
   `<steam library>/steamapps/common/ProjectZomboid/projectzomboid/media/lua/`.
   If vanilla does something a certain way, that is the way.
2. **`javap` on the jar that is installed right now:**

   ```
   javap -p -c -cp <path to>/projectzomboid.jar zombie.iso.IsoObject
   ```

   Quote the signature you relied on in the comment. For anything about *when* a
   field is written or read, quote the bytecode offsets too — `docs/notes/` shows
   the expected standard.
3. **A real Unix manual page**, for what the simulated machine should answer.

**Not** sources of truth: any decompiled dump (the one in circulation is months
older than the jar and has been wrong here), any other mod, and any answer that
starts "it probably". A call that was never proven to exist is not a syntax error
and `luac5.1 -p` says nothing about it — it is a nil call in `prerender`, once a
frame, and the window is dead. If you cannot prove a call exists, say so instead
of writing it.

## Never invent Unix behaviour

Every command, refusal and error string is what a real 1993 system would have
said. Cite the real tool — the manual page, the BSD or System V source, the RFC —
in the comment. Use the names 1993 used (`useradd`, `userdel`, `usermod -G`), not
Debian's (`adduser`, `gpasswd`).

If a behaviour genuinely has no 1993 model and is kept anyway, it is a **declared
deviation**: add it to `CeroSecOS.DEVIATIONS` *and* to the page of the in-game
Volume 1 called *What is not Unix here*. A bench checks the two against each other
in both directions, so declaring it in one place only goes red.

## Kahlua, not PUC Lua

The game's VM is Kahlua. The subset is smaller than `lua5.1`'s:

- No bit library, no `string.pack`, no integer division, no `goto`, no `%b`
  patterns. `tests/kahlua-check.sh` greps for what is known to break.
- The standard library **answers differently** in places: `tonumber(s, 16)` has
  `Integer.parseInt` behind it and once returned `nil` for half of all hashes
  while every `lua5.1` bench stayed green. Anything you newly rely on from the
  standard library goes into `tests/kahlua-probe.lua`, which runs on both VMs and
  compares the output line for line.
- **Never evaluate Lua from a file or from input**, in either direction: nothing a
  player types or a script contains reaches `load`/`loadstring`, and no
  player-controlled string reaches Lua's pattern matching unescaped. A grep
  enforces this, not a reviewer.
- Run `luac5.1 -p <file>` on every Lua file you touch, every time. It catches a
  syntax error and nothing else on this list.

## Prove it, by exit code

```
sh tests/run.sh ; echo $?
```

**Read the exit code.** Never report success from the friendly last line: the
script is `set -e` and stops at the first failure, and several of its guards are
deliberately not piped into anything so that a pipe cannot hide a status.

- Run it in the **foreground** and let it finish. It is not fast, and a suite you
  did not wait for proves nothing.
- If the game is not installed, the Kahlua harness cannot run and the suite will
  fail on that block. Say so plainly; do not delete or skip the block.
- Every new or changed assertion must be seen **red for the reason it exists**:
  break the thing it guards on purpose, watch the suite fail for that reason and
  no other, restore it, watch it pass. Report what you mutated and what went red.
- Never raise a millisecond ceiling to make a red go away. The ceilings in
  `hostile_test.lua` are scaled by a calibration measured in the same process; a
  red there means measure again on a quiet machine, not edit the number.
- Assert the state, not the call. A bench that calls a function proves the
  function; the wire from the caller needs its own bench.

## Keep the manual, the parcours and the changelog in step

In the **same** change as the code:

- **The manual** (`CeroSecManualUser.lua`, `CeroSecManualAdmin.lua`,
  `CeroSecManualProgrammer.lua`). `tests/manual_test.lua` pins every usage line
  and every error string the engine can print somewhere in the three volumes, so
  changing the code is what breaks a page.
- **[docs/PARCOURS-TEST.md](docs/PARCOURS-TEST.md)** — the in-game checklist, in
  French. Add or update the step that walks your change on the glass. Keep it
  French; an English version is welcome as its own change.
- **`CHANGELOG.md`** — a line under **Unreleased**, in the words a subscriber
  reads.

## Compatibility is not negotiable

A mod update never costs a player what he built. Nothing is deleted: no state key,
no item block, no recipe, no sandbox option. Retiring something means obsoleting
it and migrating. Which version number moves, and the rules a migration step
obeys, are in
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md#the-compatibility-contract) — read
that section before touching anything persisted.

## Where to work

- **Never edit the folder the game is loading while the game is running.** Work on
  a branch, or in a `git worktree` off one:

  ```
  git worktree add -b my-change ../cerosec-my-change
  ```

  Merge when `sh tests/run.sh` exits 0. Never reset a shared branch.
- **Never prove a change by starting the game** instead of running the suite.
  Starting the game proves that it loaded, which is the one thing the suite
  already tells you.
- The mod folder must be a **real directory, never a symlink** — Build 42's
  `ScriptManager` resolves `media/scripts` against the canonical path while
  finding it through the link, and every script fails with
  `FileNotFoundException` while the Lua loads fine.

## When the author says "prepare the release"

Do not ask how. Open the section **"Prepare the release": who does what, in what
order** in [docs/RELEASE.md](docs/RELEASE.md) and run it: propose the version
number from what is under **Unreleased**, close the changelog, set the version in
the five places that mean "now", run the suite, make the upload copy, write the
Steam note and the item comment. Say at the end of each stage which step is the
author's and what it is. The steps marked Claude are not waited-for: nothing on
that list should ever need the author to remind you of it.

Until then, features and fixes each keep their own manual page, parcours step and
**Unreleased** line, and the version number is left alone.

## Commits

- Small, each one a thing that works. A message that says **why**, not what the
  diff already shows.
- 60 columns is the terminal's width and a good width for a comment too. Match the
  prose around you: explain the reason, put the proof beside the claim, and do not
  restate the line below.
- Nothing in a tracked file about your machine, your paths, your tooling or your
  name — absolute paths out of a home directory, hostnames, session URLs.
  `tests/public-check.sh` fails the suite if one gets in, and it runs as part of
  `sh tests/run.sh`.
