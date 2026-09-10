# CeroSec

Project Zomboid Build 42 mod. From scratch, vanilla Lua only, no dependencies.

CeroSec OS runs on the vanilla computers of Knox County: turn them on, open a terminal, run a small OS, network machines together and automate doors, locks and lights.

## Layout

The repo root IS the mod folder, and it lives at `~/Zomboid/mods/CeroSec` (a real directory, not a symlink).

- `42/` — `mod.info`, `media/lua/{shared,client,server}/CeroSec/`, translations.
- `common/` — sounds and sound scripts.
- `tests/` — headless, no game needed: `sh tests/run.sh` runs `defs_test.lua`, `os_test.lua` and the Kahlua-compat check (`luac5.1 -p` on every file plus a grep for constructs the game's Lua cannot run).
- `docs/` — manual test checklists.
- `workshop/` — `workshop.txt` and `preview.png` for the Steam Workshop uploader; `~/Zomboid/Workshop/CeroSec/` links to them and to this folder.

## The OS core

`42/media/lua/shared/CeroSec/OS/` holds `CeroSecOS`, the engine the terminal will
drive: `state` in, `(state', output lines)` out, and nothing else. It makes no
game call, so it runs under a plain `lua5.1` as well as under the game's Kahlua,
and every state it produces is plain nested tables of strings, numbers and
booleans — the shape `modData` can serialize. Devices, the network and the clock
are later rungs; the seams are there, the code is not.

Why not a symlink in `~/Zomboid/mods`: Build 42's `ScriptManager` relativizes each `media/scripts` file against the mod's canonical (symlink-resolved) path while the files are found through the link; the relative path degenerates into the full absolute path and every script fails with `FileNotFoundException`. Lua and translations are unaffected, scripts are.
