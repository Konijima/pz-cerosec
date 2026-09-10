# CeroSec

Project Zomboid Build 42 mod. From scratch, vanilla Lua only, no dependencies.

CeroSec OS runs on the vanilla computers of Knox County: turn them on, open a terminal, run a small OS, network machines together and automate doors, locks and lights.

## Layout

The repo root IS the mod folder, and it lives at `~/Zomboid/mods/CeroSec` (a real directory, not a symlink).

- `42/` — `mod.info`, `media/lua/{shared,client,server}/CeroSec/`, translations.
- `common/` — sounds and sound scripts.
- `tests/` — headless, no game needed: `sh tests/run.sh` runs `defs_test.lua`, `os_test.lua`, `terminal_test.lua` and the Kahlua-compat check (`luac5.1 -p` on every file plus a grep for constructs the game's Lua cannot run).
- `docs/` — manual test checklists.
- `workshop/` — `workshop.txt` and `preview.png` for the Steam Workshop uploader; `~/Zomboid/Workshop/CeroSec/` links to them and to this folder.

## The OS core

`42/media/lua/shared/CeroSec/OS/` holds `CeroSecOS`, the engine the terminal will
drive: `state` in, `(state', output lines)` out, and nothing else. It makes no
game call, so it runs under a plain `lua5.1` as well as under the game's Kahlua,
and every state it produces is plain nested tables of strings, numbers and
booleans — the shape `modData` can serialize. Devices, the network and the clock
are later rungs; the seams are there, the code is not.

The one entry point is `CeroSecOS.exec(state, session, line)`, which returns
`ok, lines, control`:

- `lines` is text and only text, one array entry per screen line, each at most 60
  characters.
- `control` is `nil`, `"clear"` or `"exit"` — an order to the terminal, beside
  the output and never inside it.

That split is deliberate. Control used to travel as sentinel strings in `lines`,
which meant a file whose contents happened to be those bytes produced a `cat`
line indistinguishable from a genuine `exit`. Text and orders are now different
kinds of thing, and on top of that the OS refuses to store any byte below `0x20`
other than newline and tab (`invalid characters`) — checked where the limits are
checked, and re-checked by `validate` so a forged `modData` cannot smuggle them
in either.

## The terminal

`client/CeroSec/CeroSecTerminal.lua` is the green screen: a `ISCollapsableWindow`
holding a 60 x 20 grid of `UIFont.Code`, a beige bezel, scanlines and a glow, and
one `ISTextEntryBox` flattened down to nothing visible. The box is there for the
one thing only it can do: taking the keyboard. `UITextBox2.focus` sets
`Core.currentTextEntryBox`, and from then on `GameKeyboard.isKeyDown` answers false
to every game key, so typing `w` types a `w` instead of walking. The line on screen
-- prompt, text, block cursor -- is drawn by the window itself, because the box has
no way to draw a block cursor or a halo.

The window knows nothing about the machine. Every command goes to the server, which
owns the state and the session, and the answer comes back addressed to one player:

    client -> server (global object channel, CGlobalObjectSystem:sendCommand)
      open   {x,y,z}                    login {x,y,z,name,password}
      exec   {x,y,z,line}               close {x,y,z}
    server -> client
      opened {x,y,z,hostname,lines}     login  {x,y,z,ok,lines,prompt}
      exec   {x,y,z,ok,lines,control,prompt}
      closed {x,y,z,reason}

Every one of them re-checks that the computer exists, is on, and has the player
standing next to it; `exec` also wants a live session, and the coordinates have to
be three numbers before they reach any arithmetic. The answer travels by
`sendServerCommand(player, ...)` on a server -- the only vanilla call that reaches
one client and not the room -- and, because that call does nothing without a
`GameServer`, by the global object broadcast in singleplayer, where the one
connection is the one player.

Neither of those is routing enough, so every command carries the terminal's own
token and every answer carries it back: a server addresses a *connection*, and
split screen puts several players on one, so without the token two local players
at the same computer would read each other's screens.

The OS state lives on the GlobalObject (`os`, saved to `gos_cerosec.bin` -- the
table serializer recurses into nested tables) and is mirrored into the IsoObject's
`movableData`, which is what vanilla pickup and placement copy, so a computer
carried across town keeps its files. The mirror is pushed to clients when a session
ends rather than after every command: a filesystem is up to 32 KB and the pickup
code reads the client's copy.

Why not a symlink in `~/Zomboid/mods`: Build 42's `ScriptManager` relativizes each `media/scripts` file against the mod's canonical (symlink-resolved) path while the files are found through the link; the relative path degenerates into the full absolute path and every script fails with `FileNotFoundException`. Lua and translations are unaffected, scripts are.
