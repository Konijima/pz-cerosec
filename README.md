# CeroSec

![CeroSec](workshop/banner.png)

**THE NETWORK NEVER DIED.**

A small 1993 Unix on the vanilla desktop computers of Knox County. Switch one on,
sit down at it, and a green 60x20 terminal opens on a BIOS line and a login
prompt. Behind it are files, permissions, accounts, an editor, shell scripts,
cron, three ways off the machine -- coax to the rest of the premises, a modem to
the county, a radio past both -- and the building itself under `/dev` once
somebody has screwed a module onto it: doors, lights, curtains, windows, the
oven, the washer, the generator, the television, worked by hand, on a schedule or
off a sensor.

And the county had computers in it already. A machine nobody has switched on yet
comes up as somebody's: his accounts, his files, a week of his log, and his
password written down on a paper in the building, because everybody wrote it
down. Ten kinds of premises, six labelled floppies, and vanilla's own Phonebook
turned into the Knox County directory.

Project Zomboid **Build 42** (42.20.0+). Written from scratch, vanilla Lua only,
no dependencies, server-authoritative. Made by Konijima.

## Install

**From the Steam Workshop.** Subscribe to *CeroSec* (item `3801094056`) and
enable **CeroSec** in the mod list when you start or load a game.

**From source, for playing or for working on it.** Clone the repository so that
the repository root *is* the mod folder:

```
git clone https://github.com/Konijima/pz-cerosec ~/Zomboid/mods/CeroSec
```

It must be a **real directory, never a symlink.** That is not a preference:
Build 42's `ScriptManager` resolves each `media/scripts` file against the mod's
canonical, symlink-resolved path while it is *found* through the link, so the
relative path degenerates into the full absolute path and every script fails with
`FileNotFoundException`. Lua and translations load fine through a link; scripts
do not, so the whole mod has to sit where the game loads it from.

Then enable **CeroSec** in the mod list.

## Quick start

1. Right-click a desktop computer and choose **Turn on computer** (needs power).
2. Right-click again for **Use computer** to sit down and open the terminal.
3. At `login:`: on a machine nobody ever set up, `admin` with an empty password.
   On somebody's machine (most of them), the accounts are the owner's: the root
   password is on a sticky note in a drawer of that place, a staff login
   sometimes on a paper in a zombie's pocket.
4. `dev` lists what the machine can reach; `help` lists the commands. A door,
   window, light, curtain, appliance, generator or set is only on that list once
   somebody has screwed a CeroSec module to it — right-click the fixture itself,
   **CeroSec hardware** — unless the sandbox option `CeroSec.HardwareRequired` is
   turned off.
5. Click the window's close button, or type `exit`, to walk away — the screen
   keeps running and is exactly as you left it next time.

## Automate the building

Nine screw-on modules turn a fixture into a device: a magnetic contact, a relay,
an electric strike, a door operator, a curtain motor, a window operator, an
appliance switch, a generator switch and a tuner control. A device is a file, so
anything that can write a file can work it: a word at the prompt, a script, a
crontab line.

```
echo close > /dev/door0
crontab -e
0 7 * * * sh /usr/local/bin/curtains.sh auto
0 20 * * * sh /usr/local/bin/curtains.sh auto
```

The six programs those lines call live on a printed floppy, `CeroSec HOME 1.0`,
found in the world like any other disk: `autoclose.sh` (a door that shuts itself
five seconds after somebody walked through), `curtains.sh` (dawn and dusk, both
crontab lines the same line), `tvguide.sh` (the set on for its programme and off
when it ends), `wake.sh` (the radio and every light in the morning), `alarm.sh`
(the window somebody opened, named on every screen in the building) and
`genwatch.sh` (the generator's tank, one letter to root and not sixty an hour).

A module goes on from inside the building, with the fixture at rest, and the four
that move something want a Small Motor. Knox County never sold one, so it comes
out of a hair dryer. A window operator throws the catch on its way past: in a
house whose alarm came back with the power, opening a window rings it. See
[docs/PLAYERS.md](docs/PLAYERS.md).

## Documentation

Start with [docs/PLAYERS.md](docs/PLAYERS.md) if you are playing, and with
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) if you are changing anything.

| Document | What is in it |
| --- | --- |
| [docs/PLAYERS.md](docs/PLAYERS.md) | The whole thing from a player's chair: accounts, commands, the editor, devices, the network, floppies, the manual. |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | How to work on this mod: the project's rules, the three test layers, how to report a bug, how to send a change. |
| [CLAUDE.md](CLAUDE.md) | The same rules as operating instructions, for contributors working with Claude Code. |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | The engine, the server, the client, the system files, the BIOS, persistence, the manual reader. |
| [docs/PROTOCOL.md](docs/PROTOCOL.md) | The client/server wire: messages, the screen shape, control markers, completion, device highlighting, remote sessions. |
| [docs/DEVICES.md](docs/DEVICES.md) | How `/dev` is built, the sync calls proven against the jar, motion sensors, the floppy's own filesystem. |
| [docs/NETWORK.md](docs/NETWORK.md) | Coax, the telephone and the radio: their identities, their rules and rates, and the sessions they carry. |
| [docs/SCRIPTING.md](docs/SCRIPTING.md) | The shell language, pipes, cron, job control, and the step machine and scheduler underneath. |
| [docs/CONTENT.md](docs/CONTENT.md) | What is already on the machines, the disks and the papers: the per-save secret, the catalogues, where a password is found. |
| [docs/SECURITY.md](docs/SECURITY.md) | The password hash, what root can and cannot undo, what the server guarantees against a hostile script. |
| [docs/DEBUG.md](docs/DEBUG.md) | The debug window: the dev flags and the release gating, the six tabs, what it costs the server, the three things it can change. |
| [docs/TESTING.md](docs/TESTING.md) | `sh tests/run.sh`, what each suite proves, the calibrated millisecond ceilings, and what no headless test can reach. |
| [docs/RELEASE.md](docs/RELEASE.md) | The ordered Workshop release checklist: the images, the flags, the upload, the tag, the visibility. |
| [docs/PARCOURS-TEST.md](docs/PARCOURS-TEST.md) | The in-game checklist, in French, walked on the glass before a release. |
| [docs/TEST-rung1.md](docs/TEST-rung1.md), [rung2](docs/TEST-rung2.md), [rung4](docs/TEST-rung4.md) | Older in-game checklists, kept as they were read at the time. |
| [docs/notes/](docs/notes/README.md) | Engineering notes: the bytecode proofs out of the game's jar behind the rules, kept so a rule can be checked rather than believed. |
| [workshop/SHOTS.md](workshop/SHOTS.md) | The screenshots the Workshop page needs, with the in-game settings for each. |

The in-game manual's own text is three Lua files:
[`CeroSecManualUser.lua`](42/media/lua/shared/CeroSec/CeroSecManualUser.lua),
[`CeroSecManualAdmin.lua`](42/media/lua/shared/CeroSec/CeroSecManualAdmin.lua) and
[`CeroSecManualProgrammer.lua`](42/media/lua/shared/CeroSec/CeroSecManualProgrammer.lua).

## The tests

From the repository root, with `lua5.1` on the `PATH`:

```
sh tests/run.sh
echo $?
```

The exit code is the verdict, not the last line printed. It runs every headless
suite, then the guards: the Kahlua greps, every file loaded on the game's own
Kahlua VM out of the jar, the self-call resolver, the generated self-test
vectors, the Workshop page against Steam's ceilings, and
[`tests/public-check.sh`](tests/public-check.sh). Details, and what each suite
proves, in [docs/TESTING.md](docs/TESTING.md).

## Design rules (non-negotiable)

- **Vanilla only.** No dependencies, no bundled libraries.
- **Nothing is called on faith.** Every game API used is proven to exist first,
  against the shipped jar (`javap`) or against vanilla Lua.
- **No Lua is ever evaluated from a file.** The OS core reads and writes plain
  data; nothing a player types or a script contains is ever handed to `load` or
  `loadstring`. `tests/kahlua-check.sh` greps for the constructs that would
  smuggle one in.
- **Faithful to Unix; invent nothing.** Where a real `/bin/sh`, `cron`, `rlogin`
  or a Hayes modem would answer a certain way, this machine answers the same way
  — refusals included. A behaviour with no real-world model is a behaviour to
  question. The commands wear the names 1993 gave them: `useradd`, `userdel`,
  `usermod -G` (System V, 1989), and not Debian's `adduser` or shadow-utils'
  `gpasswd`. The handful of things that have no 1993 model and are kept anyway
  — `help`, `dev`, `mkpasswd`, `edit`, `sudo`, and jobs that belong to the
  machine rather than to the shell — are listed in `CeroSecOS.DEVIATIONS` and
  declared on a page of the in-game Volume 1, *What is not Unix here*, which a
  bench checks against that list in both directions.
- **A mod update never costs a player what he built.** Nothing is ever deleted:
  not a state key, not an item, not a recipe, not a sandbox option. The
  replacement is always *obsolete, and migrate*.
- **Never `eval`, in either direction.** Not Lua evaluated from a file, and not
  a player-supplied string reaching Lua's own pattern matching unescaped.

Three lessons this codebase paid for and does not intend to relearn:

- **The mod folder is a real directory, never a symlink** — a symlinked mod
  folder loads its Lua fine and fails every script with `FileNotFoundException`,
  because `ScriptManager` resolves through the link before it matters. See
  "Install" above.
- **`MeasureStringX` measures a glyph's ink, not its advance** — the manual
  reader sized its monospaced column on the *ink* of `"M"` until a change that
  measured the gap between two of them instead, because `"M"` in the game's own
  font is a pixel wider in ink than the cell it is drawn in. See
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#the-manual-reader).
- **`rlogin` needs a terminal to hand over** — a job with nobody in front of it
  (a cron line, a background job, a pipe stage, a `$(...)`) has nothing to give
  a remote shell and is refused, in `rlogin`'s own words, exactly as real
  `rlogin(1)` refuses one. See [docs/PROTOCOL.md](docs/PROTOCOL.md).

## How to help

Bug reports, in-game test passes, translations and code are all welcome.

- **A bug**: open an issue with the build number, your mod list and the
  `console.txt` lines around it — the template asks for exactly what is needed.
- **A translation**: copy `42/media/lua/shared/Translate/EN/` to your language
  code and translate the values. No code changes needed.
- **A change**: read [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) first. Every
  change comes with its benches, and `sh tests/run.sh` has to exit 0.
- Everyone taking part is held to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Licence

All rights reserved, see [LICENSE](LICENSE): read it, play it, send pull
requests from a fork; do not redistribute it or reupload it to the Workshop.
