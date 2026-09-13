# CeroSec — Contributing

How a change of work happens, how the repo is laid out, and the coding and
security rules every change is held to.

See also: [TESTING.md](TESTING.md) for what a change has to pass before it merges,
[SECURITY.md](SECURITY.md) for the rules a reviewer checks first,
[ARCHITECTURE.md](ARCHITECTURE.md) for the persistence rules a version bump obeys.

## The change process

Work happens in changes, each in its own git worktree branched from a named base
commit — never in the live mod folder directly, and never by resetting a shared
branch. A change that touches the game itself never starts the game to prove
itself; `sh tests/run.sh` and the manual checklists in `docs/` are the proof.
A verifier reads the diff before it merges to main, and a change ends with a
short report — what changed, what `tests/run.sh` printed, any stale claim found
along the way — and a `go` from Mathieu before the next change starts on top of it.

## Repository layout

The repo root **is** the mod folder. It has to live at a real, non-symlinked path
under `~/Zomboid/mods/` — Build 42's `ScriptManager` resolves each `media/scripts`
file against the mod's canonical, symlink-resolved path while it is *found* through
the link, so the relative path degenerates into the full absolute path and every
script fails with `FileNotFoundException`. Lua and translations are unaffected;
scripts are not, so the whole mod has to sit where it is loaded from.

- `42/` — `mod.info`, `media/lua/{shared,client,server}/CeroSec/`, translations.
- `common/` — sounds, textures, models, and the script files: `sounds_cerosec.txt`,
  `items_cerosec.txt` and `models_cerosec.txt`.
- `tests/` — headless, no game needed: `sh tests/run.sh`.
- `docs/` — manual, in-game test checklists.
- `tools/` — the one build script there is: `make-volume-icons.py`, which derives
  the three volume icons from the shipped one.
- `workshop/` — `workshop.txt` and `preview.png` for the Steam Workshop uploader.

## Coding rules

- Vanilla only: no dependencies, no bundled libraries.
- Every game API used is proven to exist first, either against the shipped jar or
  against vanilla Lua (`javap`) — nothing is called on faith. See the sync-call
  table in [DEVICES.md](DEVICES.md) for a worked example.
- The Kahlua subset only: no bit library, no packing, no integer division, and
  nothing `tests/kahlua-check.sh` would flag. Keep example lines and shell output
  inside 60 columns — the terminal is 60x20 and does not wrap a code line.
- No Lua is ever evaluated from a file; the OS core reads and writes plain data
  and nothing a player types is ever handed to `load`/`loadstring`. This is the
  one rule `tests/kahlua-check.sh` enforces by grep, not by review.
- A timed action's validity is re-checked in `waitToStart`, not only in
  `isValid`, because the engine evaluates `isValid` before `waitToStart` and
  drops an action that stops being valid in between.
- A control marker (`clear`, `exit`, `prompt`, `edit`, ...) never travels in the
  same channel as text output — see [PROTOCOL.md](PROTOCOL.md).
- The mod folder is a real directory, never a symlink — see "Repository layout"
  above.
- **Three version numbers, three homes, and no in-world string carries a
  fourth.**
  fourth.** The operating system's is `CeroSecOS.VERSION` (`shared/CeroSec/OS/
  CeroSecOS.lua`) and everything a player reads that names it — the greeting the
  boot ends on and a login is met with (`CeroSecOS.MOTD`, the built-in
  `/etc/motd`), the manual's cover — is built from it. The firmware's is
  `CeroSec.BIOS_VERSION` (`shared/CeroSec/CeroSecDefs.lua`), a separate component
  with a separate number, printed by `CeroSec.BOOT_LINES[1]`. The mod's own
  release version is `modversion` in `42/mod.info` and never appears in the
  world at all. `tests/manual_test.lua` refuses a page that names an OS version
  of its own.

- The manual is updated in the same change as the command or file it documents:
  a page that describes a machine the code no longer builds is a stale page,
  and `tests/manual_test.lua` pins every usage line and every error string the
  engine can print somewhere in the union of the three volumes, so a change to
  the code is what breaks a page.
- `SYSTEM_VERSION` bumps whenever a change adds a file to `/bin` or seeds a new
  system file, and `sysv` (the *contents* a machine was built with) is what
  `CeroSecOS.upgradeSystem` tops an older machine up against on load — see
  [ARCHITECTURE.md](ARCHITECTURE.md#persistence). It puts in what is missing and
  never replaces what root has already changed or removed.

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
| a file the machine ships in `/bin` or `/etc` | `CeroSecOS.SYSTEM_VERSION` | `upgradeSystem` puts in what is **missing**, once, and never replaces what root changed or deleted |
| the **shape** of the state: a key renamed, dropped, or whose meaning changed | `CeroSecOS.STATE_VERSION` | a step in `CeroSecOS.MIGRATIONS`, walked on the way in |
| the shape of what is written on a **floppy** | `CeroSecOS.FLOPPY_VERSION` | a step in `CeroSecOS.DISK_MIGRATIONS` |
| the shape of a door's **modules** | `CeroSecModules.VERSION` | a step in `CeroSecModules.MIGRATIONS` |
| the shape of the **phone book** stamp | `CeroSecPhonebook.VERSION` | a step in `CeroSecPhonebook.MIGRATIONS` |

Seeding a file is *not* a shape change and must not move `STATE_VERSION`: the two
numbers exist precisely so that adding a command costs a machine nothing.

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

## Workshop copy

Never link `~/Zomboid/Workshop/CeroSec/Contents/mods/CeroSec` to the repo: the
game scans that folder as a mod too, and through a symlink `ScriptManager`
builds a doubled path and loses every script file (items, sounds). At
publication time run `sh tools/workshop-sync.sh sync`, upload from the game's
Workshop screen, then `sh tools/workshop-sync.sh clean` so the game loads the
real folder again.

## The changelog

Every change that changes what a player sees adds its lines to `CHANGELOG.md`
under **Unreleased**, in the words a subscriber reads. At release the section
takes its version and date, `python3 tools/changelog-steam.py` prints it as
Steam Change Notes, and Mathieu pastes that on the item. A change without a
changelog line is a change nobody will know shipped.
