# CeroSec

Project Zomboid Build 42 mod. From scratch, vanilla Lua only, no dependencies.

CeroSec OS runs on the vanilla computers of Knox County: turn them on, open a terminal, run a small OS, network machines together and automate doors, locks and lights.

## Layout

The repo root IS the mod folder, and it lives at `~/Zomboid/mods/CeroSec` (a real directory, not a symlink).

- `42/` — `mod.info`, `media/lua/{shared,client,server}/CeroSec/`, translations.
- `common/` — sounds and sound scripts.
- `tests/` — headless `lua5.1 tests/defs_test.lua`.
- `docs/` — manual test checklists.
- `workshop/` — `workshop.txt` and `preview.png` for the Steam Workshop uploader; `~/Zomboid/Workshop/CeroSec/` links to them and to this folder.

Why not a symlink in `~/Zomboid/mods`: Build 42's `ScriptManager` relativizes each `media/scripts` file against the mod's canonical (symlink-resolved) path while the files are found through the link; the relative path degenerates into the full absolute path and every script fails with `FileNotFoundException`. Lua and translations are unaffected, scripts are.
