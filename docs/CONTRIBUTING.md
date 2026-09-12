# CeroSec — Contributing

How a wave of work happens, how the repo is laid out, and the coding and
security rules every wave is held to.

See also: [TESTING.md](TESTING.md) for what a wave has to pass before it merges,
[SECURITY.md](SECURITY.md) for the rules a reviewer checks first,
[ARCHITECTURE.md](ARCHITECTURE.md) for the persistence rules a version bump obeys.

## The wave process

Work happens in waves, each in its own git worktree branched from a named base
commit — never in the live mod folder directly, and never by resetting a shared
branch. A wave that touches the game itself never starts the game to prove
itself; `sh tests/run.sh` and the manual checklists in `docs/` are the proof.
A verifier reads the diff before it merges to main, and a wave ends with a
short report — what changed, what `tests/run.sh` printed, any stale claim found
along the way — and a `go` from Mathieu before the next wave starts on top of it.

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

- The manual is updated in the same wave as the command or file it documents:
  a page that describes a machine the code no longer builds is a stale page,
  and `tests/manual_test.lua` pins every usage line and every error string the
  engine can print somewhere in the union of the three volumes, so a change to
  the code is what breaks a page.
- `SYSTEM_VERSION` bumps whenever a wave adds a file to `/bin` or seeds a new
  system file, and `sysv` (the *contents* a machine was built with) is what
  `CeroSecOS.upgradeSystem` tops an older machine up against on load — see
  [ARCHITECTURE.md](ARCHITECTURE.md#persistence). It puts in what is missing and
  never replaces what root has already changed or removed.

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
