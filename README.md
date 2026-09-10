# CeroSec

Project Zomboid Build 42 mod. From scratch, vanilla Lua only, no dependencies.

CeroSec OS runs on the vanilla computers of Knox County: turn them on, open a terminal, run a small OS, network machines together and automate doors, locks and lights.

## Layout

The repo root IS the mod folder, and it lives at `~/Zomboid/mods/CeroSec` (a real directory, not a symlink).

- `42/` — `mod.info`, `media/lua/{shared,client,server}/CeroSec/`, translations.
- `common/` — sounds and sound scripts.
- `tests/` — headless, no game needed: `sh tests/run.sh` runs `defs_test.lua`, `os_test.lua`, `terminal_test.lua`, the self-call check (every `self:method()` we write is defined somewhere — Lua resolves a method when it is *called*, so one that was never written, or one an edit took out with the block around it, is not a syntax error: it is a nil call once a frame in `prerender`, and the window is dead) and the Kahlua-compat check (`luac5.1 -p` on every file plus a grep for constructs the game's Lua cannot run).
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
one `ISTextEntryBox` parked **off the glass**. The box is there for the one thing
only it can do: taking the keyboard. `UITextBox2.focus` sets
`Core.currentTextEntryBox`, and from then on `GameKeyboard.isKeyDown` answers false
to every game key, so typing `w` types a `w` instead of walking.

Everything on the glass is drawn by the window: the prompt, what has been typed,
the block cursor, and the wrap. A terminal does not stop at the right edge, so the
input line is up to 240 characters and wraps onto the rows under it, the cursor
following — which is exactly what a one-line text box cannot draw. The box stays
outside the window's own stencil rect, where every pixel it paints is clipped away
(`ISCollapsableWindow:prerender` sets that rect and `:render` clears it, and
`UIElement.render` draws the children between the two; it only *skips* a child
outside its parent when `renderClippedChildren` is false, and that field is true
from the constructor). It has to keep being rendered, because `UITextBox2.render`
is what repaginates it and what recomputes the display line its Up and Down keys
walk, and it cannot be made to draw nothing: its caret colour is a hardcoded field
with no setter.

The prompt shortens the user's home to `~`, and only the home — `/home/adminx` is
not inside `/home/admin`. What is still too long is cut at the **front** and marked
`...`, never with a tilde: a tilde in the middle of a path is what made
`admin@ksp-4rw-44z:~ome/admin$` look like a broken home shortening, because it was
a tail cut wearing the wrong marker.

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
      open     {x,y,z}                  input    {x,y,z,text}
      exec     {x,y,z,line}             close    {x,y,z}
      editbuf  {x,y,z,text}             editsave {x,y,z,text}
      editexit {x,y,z}
    server -> client
      opened {x,y,z,hostname,booted,lines,prompt,mode,mask,edit,animate}
      screen {x,y,z,hostname,booted,lines,prompt,mode,mask,edit}
      closed {x,y,z,reason}

`input` carries one line: the answer to whatever the machine is asking. A user name,
a password, or the line a command asked for -- the console knows which, and the
window never has to. `mode` is `prompt`, `shell` or `edit`, `mask` says whether what
is typed shows as stars, and the prompt is derived from the console in one place, so
no two windows can disagree about it. The password is stored masked and the
cleartext never reaches a line. `animate` is set on the one `opened` that finds a
machine freshly switched on: that window watches the BIOS type itself out, once per
power-on, and every window opened afterwards finds those lines already on the screen.

## A command that has not finished

`exec` returns `ok, lines, control, data`, and `control` grew two values that carry a
payload. `prompt` means the command is asking something: `data` is the line to put
under the cursor, whether the answer is masked, and an opaque token. The console
stores the token, feeds the next line typed to `CeroSecOS.continue(state, session,
cont, line)`, and gets back the very same shape. That is how `passwd` asks three
questions without a coroutine, which Kahlua does not have. A token that is not one --
a forged console, a chain abandoned and answered later -- is refused and changes
nothing.

`passwd` asks its three questions this way, and nothing of a password reaches the
token: between "New password:" and "Retype new password:" what is carried is the
**hash** of the answer with its own salt, because the token lives in the machine's
console and the console is written to the save file. The authority to change an
account is re-checked at every step of the chain, not only in the command that
started it.

`edit` means the terminal is to become an editor: `data` is the path, the file's text
and whether it may be written back. The core says no more than that; the editor is
the window's, and its save is `CeroSecOS.writeFile`, the same call `write` and `>` go
through, so it has no permissions, no limits and no printable rule of its own.

## Passwords

Stored hashed, never in clear: `$cs1$<salt>$<32 hex digits>`, with a fresh six-digit
salt per account. `CeroSecOS.hashPassword` is the one place a password becomes what is
stored and `CeroSecOS.checkPassword` the one place one is judged, so swapping the
construction later is a two-function change; the `$cs1$` tag is in every stored
string so a later one can be told apart and migrated. `hash <text> [salt]` runs the
same function on any string, which is how you see what one looks like. A machine
saved before this rung carries its passwords in clear: `CeroSecOS.migrateUsers` hashes
them in place, and it runs **before** the validator, which refuses anything that is
not a `$cs1$` line — the alternative would be throwing away a working filesystem over
a password field.

Be honest about the strength. It is not bcrypt, not scrypt, not even SHA-2: it is
4000 rounds of 32-bit add / multiply / rotate over four lanes, written in the
arithmetic Kahlua has — no bit library, no packing, no integer division. Somebody
willing to write a cracker will get a password out of a save file. The point is
narrower and still worth having: reading the save file, or a future `/etc/passwd` on
the machine itself, does not simply hand the passwords over, and two accounts with
the same password do not look alike. One hash measures about 5 ms under `lua5.1`
(`tests/os_test.lua` fails above 50 ms), and a login costs exactly one.

The salt has no clock and no random number generator to draw on — the core is pure
Lua and runs the same under `lua5.1` and under Kahlua — so it is a counter, the
machine's own name, and whatever extra the caller passes. The server passes
`getTimestampMs()` through `session.stamp`; the engine never requires it, and without
it two machines with the same hostname, restarted, can produce the same salt. That is
a weaker salt, not a broken one: a salt has to be different, not secret.

## The editor

`edit <file>` turns the same 60 x 20 glass into nano's shape: an inverted bar naming
the file, seventeen rows of the buffer, an inverted bar of keys, and a message line.
Escape is `^X` and Tab is `^O`, because those are the only two keys the game hands a
text box that has the keyboard (`Core.updateKeyboardAux`) -- Ctrl+letter never
arrives, and neither do PageUp and PageDown.

The buffer is the machine's, like the screen: it lives in the console, is saved with
the object, and is pushed back to the machine on every save, on leaving, and every
five seconds while it differs. Walking away and coming back finds it, `[modified]`
and all. One window types in it and the others watch, because two people typing into
one buffer over a network is a merge. Who is holding it is worked out fresh on every
screen the server sends — the one who took it if he is still standing there, else the
first of the watchers — rather than remembered, so a buffer whose owner walked off
never leaves the player still standing at the machine watching a screen he can
neither type in nor leave.

The input surface is the vanilla `ISTextEntryBox`, in multiple-line mode, parked
**off the glass**. It has to keep being rendered -- `UITextBox2.render` is what
repaginates it and what recomputes the display line its Up and Down keys walk -- and
there is no way to make it draw nothing, because its caret colour is a hardcoded
field with no setter. So it is placed outside the window's own stencil rect
(`ISCollapsableWindow:prerender` sets it, `:render` clears it, and `UIElement.render`
draws the children between the two) where every pixel it paints is clipped away, and
the buffer is drawn in the green grid by the window, with its own block cursor at
`getCursorPos()` -- an absolute index into the text, which is what `putCharacter`,
`onKeyLeft`, `onKeyRight`, `onKeyBack` and `onKeyDelete` all treat it as.

Two ceilings are checked under the fingers: 60 characters to a line (the editor wraps
nothing) and 4096 bytes to a buffer (`CeroSecOS.MAX_FILE_BYTES`). A keystroke is
refused only when it does not make things **better**, which is not a nicety: the
shell can put a 70-character row in a file (`writeFile` has no width rule — the width
belongs to the glass, not to the disk), and an editor that undid every keystroke on
such a buffer would undo the backspaces too and could never repair the file it had
opened. The server holds the buffer under the filesystem's rules only — printable,
under the file ceiling — for the same reason. A third is the game's: `UITextBox2.textEntryMaxLength`
is 2000 in the constructor, has no setter and no constructor argument, and
`isTextLimit()` gates `putCharacter` with it, so **typing** stops at 2000 characters.
A bigger file still opens, still shows and still saves; Enter and paste are not gated
by it either. The message line says so when it happens.

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
