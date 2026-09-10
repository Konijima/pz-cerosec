# CeroSec

CeroSec puts a small Unix on the vanilla desktop computers of Knox County. Right-click
one to turn it on: the sprite lights up, the screen glows, and a green 60x20 terminal
opens with a BIOS boot line, a login prompt and a real shell behind it — files,
permissions, an editor, `passwd`. The screen belongs to the machine, not to the
player: walk away and come back to the same session, still logged in, and two
survivors standing at one computer read and type on the same glass. Every bit of it
is server-authoritative and safe in multiplayer.

## Status

Build 42.20.4. From scratch, vanilla Lua only, no dependencies.

Done:
- Power: turn a desktop computer on and off from the context menu, with the right
  sprite per facing, power checked against the room, and a chair taken automatically
  when one is pulled up to the desk.
- The OS engine: a filesystem with owners and permissions, users, a shell
  (`cat cd chmod chown clear cp echo edit exit hash help hostname ls mkdir mv passwd
  pwd rm touch whoami write`), an editor, and salted-hashed passwords.
- The terminal window: the green screen, login, command history, the editor, and a
  server-held console so the screen survives a save, a reload and a walk away.

Next: `/bin`, `/etc/passwd` and a proper BIOS restore; `/dev` devices; scripts and
cron; networking machines together to automate doors, locks and lights.

## For players

### Install

Drop (or symlink-free clone) the mod into `~/Zomboid/mods/CeroSec` — see
"Repository layout" below for why it has to be a real directory — and enable
**CeroSec** in the mod list when starting or loading a game.

### Use

Right-click a desktop computer (the beige `Desktop` tile) and choose **Turn on
computer**. It needs power in the room; if there is none, the option is greyed out.
Once it is on, right-click again for **Use computer**: the character walks to the
front of the machine, sits down if there is a chair pulled up to it, and the
terminal opens.

At the `login:` prompt, use one of the two accounts that ship on every fresh
machine, both with an empty password — just press Enter when asked:

| user | password |
| --- | --- |
| `admin` | (empty) |
| `root` | (empty) |

Commands:

| command | does |
| --- | --- |
| `ls [-l] [path]` | list a directory, or one file |
| `cd [dir]` | change directory (home if no argument) |
| `pwd` | print the working directory |
| `cat <file>` | print a file |
| `edit <file>` | open the file in the editor |
| `write <file> <text>` | write text to a file (used by the editor's save) |
| `touch <file>` | create an empty file |
| `mkdir <dir>` | create a directory |
| `rm [-r] <path>` | remove a file, or a directory tree with `-r` |
| `mv <src> <dst>` | move or rename |
| `cp <src> <dst>` | copy a file |
| `chmod <mode> <path>` | set permissions (three octal digits) |
| `chown <user> <path>` | change the owner |
| `whoami` | print the logged-in user |
| `hostname` | print the machine's name |
| `passwd [user]` | change a password (root may change anyone's) |
| `hash <text> [salt]` | show what a password would hash to |
| `echo <text>` | print text |
| `clear` | clear the screen |
| `exit` | log out |
| `> file` / `>> file` | redirect a command's output, write or append |

`edit` turns the screen into a small editor: Esc saves and leaves, Tab shows the key
bar. A file is capped at 4096 bytes and a line at 60 characters; the game's own text
box stops accepting new keystrokes at 2000 characters typed in one sitting, though a
bigger file still opens and still saves.

`passwd` asks for the old password (skipped for root), the new one, and a retype.
`hash` runs the same hashing the passwords use on any text you give it, so you can
see what a password would look like stored.

Click the window's close button, or run `exit`, to leave. The screen itself keeps
running: log back in later and it is exactly as it was left.

## For modders and contributors

### Repository layout

The repo root **is** the mod folder. It has to live at a real, non-symlinked path
under `~/Zomboid/mods/` — Build 42's `ScriptManager` resolves each `media/scripts`
file against the mod's canonical, symlink-resolved path while it is *found* through
the link, so the relative path degenerates into the full absolute path and every
script fails with `FileNotFoundException`. Lua and translations are unaffected;
scripts are not, so the whole mod has to sit where it is loaded from.

- `42/` — `mod.info`, `media/lua/{shared,client,server}/CeroSec/`, translations.
- `common/` — sounds and the sound script (`sounds_cerosec.txt`).
- `tests/` — headless, no game needed: `sh tests/run.sh`.
- `docs/` — manual, in-game test checklists.
- `workshop/` — `workshop.txt` and `preview.png` for the Steam Workshop uploader.

### Architecture

`42/media/lua/shared/CeroSec/OS/` is a pure-Lua OS engine: `CeroSecOS.exec(state,
session, line)` takes a state and a command line and returns `ok, lines, control,
data`, and nothing else. It makes no game call, touches no `os`/`io`/`require`, no
coroutines and no metatables, so it runs the same under a plain `lua5.1` and under
the game's Kahlua. `lines` is text, one array entry per screen line, at most 60
characters. `control` is `nil`, `"clear"`, `"exit"`, `"prompt"` or `"edit"` — an
order to the terminal, carried beside the output and never inside it, so a file's
contents can never be mistaken for one. `"prompt"` and `"edit"` carry a payload in
`data`: `"prompt"` is how a command like `passwd` asks a question without a
coroutine (`CeroSecOS.continue` answers it the same way `exec` answers a command
line); `"edit"` hands the terminal a path, the file's text and whether it may be
written back.

On top of the engine sits a server-authoritative `SGlobalObject` system
(`SCeroSecObject`, `SCeroSecSystem`) that holds each computer's OS state and, while
it is on, a console: `{ booted, user, cwd, pending, lines }`. There is one console
per computer, not one per player — that is what makes walking away and coming back
find the same screen, and two players at one computer share it. The client mirror
(`CCeroSecObject`, `CCeroSecSystem`) never holds the filesystem or the screen; it
only shows the sprite and relays input.

The context menu (`CeroSecContextMenu.lua`), the reach checks (`CeroSecReach.lua`)
and the terminal window (`CeroSecTerminal.lua`, an `ISCollapsableWindow`) are all
client-side. The window talks to the server over the global object channel:

    client -> server: open, exec, close, input, editbuf, editsave, editexit
    server -> client: opened, screen, closed

Every command carries the window's own token and every answer carries it back
(`sendServerCommand` reaches one connection, or the global object broadcast in
singleplayer where there is only one), because the server addresses a connection
and split screen puts several players on one. The server keeps a watcher list per
computer and answers every open window with the new screen under its own token.

### Persistence

The GlobalObject saves `v`, `on`, `facing`, `os` and `console` to `gos_cerosec.bin`.
`os` and `console` are nested tables the save serializer recurses into. Only `v`,
`on`, `facing` and `os` are mirrored into the `IsoObject`'s `movableData`, which is
what vanilla pickup and placement copy — so a computer carried across town keeps its
files, and only `v`, `on`, `facing` are sent to clients on add or update. The console
is deliberately excluded from both: it is a screen, not a disk (a computer picked up
is a computer that lost its power), and the client never reads the stored screen,
only the lines the server answers it with. A filesystem is capped at 256 nodes, 64
entries per directory, 16 levels deep and 32768 bytes total, so the mirror stays
small.

### Design rules

- Vanilla only: no dependencies, no bundled libraries.
- Every game API used is proven to exist first, either against the shipped jar or
  against vanilla Lua — nothing is called on faith.
- No Lua is ever evaluated from a file; the OS core reads and writes plain data.
- A timed action's validity is re-checked in `waitToStart`, not only in `isValid`,
  because the engine evaluates `isValid` before `waitToStart` and drops an action
  that stops being valid in between.
- A control marker (`clear`, `exit`, `prompt`, `edit`) never travels in the same
  channel as text output.
- The mod folder is a real directory, never a symlink.

## Testing

`sh tests/run.sh` runs every headless suite in order and needs `lua5.1`:

- `defs_test.lua` — the shared definitions (sprites, facings, state).
- `os_test.lua` — the OS core: filesystem, permissions, users, shell, passwords.
- `terminal_test.lua` — the pure parts of the terminal: hostname, console, history.
- `window_test.lua` — the window wired to the machine end to end: type a line, get
  an answer on the glass.
- `selfcalls-check.sh` — every `self:method()` called is defined somewhere, since
  Lua only resolves a method when it is called and a missing one is a silent nil
  call, not a syntax error.
- `kahlua-check.sh` — `luac5.1 -p` on every shipped file, plus a grep of the OS core
  for constructs the game's Kahlua cannot run.

What no headless test can reach — the sprite, the context menu, sitting down, the
glow, what is actually on screen — is covered by the manual checklists in `docs/`:
`TEST-rung1.md` (turning a computer on and off) and `TEST-rung2.md` (the terminal,
login and the shell).

## Security note

Passwords are stored as `$cs1$<salt>$<32 hex digits>`, never in clear: a fresh
six-digit salt per account, run through 4000 rounds of 32-bit add/multiply/rotate
mixing written in the arithmetic Kahlua has (no bit library, no packing, no integer
division). Be honest about what that is: it is not bcrypt, not scrypt, not even
SHA-2. Somebody willing to write a cracker will get a password out of a save file.
What it protects against is narrower and still worth having: reading the save file,
or a future `/etc/passwd` on the machine itself, does not simply hand the passwords
over, and two accounts with the same password do not look alike. A machine saved
before hashing existed has its passwords hashed in place on load, with a fresh salt
each.
