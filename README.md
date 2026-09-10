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

## The screen belongs to the machine

There is **one console per computer**, on the server, saved with the object:

    console = { booted = bool, user = string|nil, cwd = string|nil,
                pending = string|nil, lines = { ... } }

`lines` is what is on the glass: at most 100 entries of at most 60 printable
characters, oldest dropped. `user` and `cwd` are the session -- the one the OS core
is handed before each command and which is written back after it, so `cd` moves the
machine's cursor and not anybody's. `pending` is a user name typed at `login:` and
not yet answered for. Nobody has a session of his own any more: walking away and
coming back hands you the same screen, still logged in, with no second BIOS, and two
players standing at one computer read and type on the same screen. Physical access
is the only access there is.

It is created when the machine is switched on and destroyed when it goes dark --
off, power loss, pickup -- and `exit` empties it back to a bare `login:`. It is
saved in `gos_cerosec.bin` beside `os`, and deliberately **not** mirrored into
`movableData` (a computer that is picked up is a computer that lost its power) and
**not** in the sync keys (the client never reads the stored screen, only the lines
the server answers it with).

The window knows nothing about the machine and nothing about the screen: it draws
the lines it is handed, under the prompt it is handed.

    client -> server (global object channel, CGlobalObjectSystem:sendCommand)
      open   {x,y,z}                    login {x,y,z,text}
      exec   {x,y,z,line}               close {x,y,z}
    server -> client
      opened {x,y,z,hostname,booted,lines,prompt,mode,animate}
      screen {x,y,z,hostname,booted,lines,prompt,mode}
      closed {x,y,z,reason}

`login` carries one line, and the console says whether that line is a user name or a
password -- the password is stored masked and the cleartext never reaches a line.
`mode` is `login`, `password` or `shell`, and the prompt is derived from the console
in one place, so no two windows can disagree about it. `animate` is set on the one
`opened` that finds a machine freshly switched on: that window watches the BIOS type
itself out, once per power-on, and every window opened afterwards finds those lines
already on the screen.

Every one of them re-checks that the computer exists, is on, and has the player
standing next to it, and the coordinates have to be three numbers before they reach
any arithmetic. The answer travels by `sendServerCommand(player, ...)` on a server --
the only vanilla call that reaches one client and not the room -- and, because that
call does nothing without a `GameServer`, by the global object broadcast in
singleplayer, where the one connection is the one player.

Neither of those is routing enough, so every command carries the terminal's own
token and every answer carries it back: a server addresses a *connection*, and split
screen puts several players on one. The server keeps the open windows in a watcher
list per computer (keyed by online id and token, pruned on `close`, on eviction and
by the every-minute sweep) and sends each one the new screen under **its own** token,
so one change to a console reaches every window looking at it.

The OS state lives on the GlobalObject (`os`, saved to `gos_cerosec.bin` -- the
table serializer recurses into nested tables) and is mirrored into the IsoObject's
`movableData`, which is what vanilla pickup and placement copy, so a computer
carried across town keeps its files. The mirror is pushed to clients when a window
closes rather than after every command: a filesystem is up to 32 KB and the pickup
code reads the client's copy.

Why not a symlink in `~/Zomboid/mods`: Build 42's `ScriptManager` relativizes each `media/scripts` file against the mod's canonical (symlink-resolved) path while the files are found through the link; the relative path degenerates into the full absolute path and every script fails with `FileNotFoundException`. Lua and translations are unaffected, scripts are.
