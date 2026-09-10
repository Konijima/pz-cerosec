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
- The OS engine: a filesystem with owners and permissions and modification times, a
  shell (`adduser cat cd chmod chown clear cp date deluser df echo edit exit grep
  hash head help hostname id ls man mkdir mv passwd pwd reboot restart rm shutdown
  su sudo tail touch wc whoami write`), an editor, and salted-hashed passwords.
- Accounts: `adduser` and `deluser` make and unmake them, `su` changes who the
  glass is logged in as without logging out, and `id` says what the machine knows
  about a name.
- The clock: the machine reads the game's calendar, so `date` is the hour the
  survivor is living in and every file carries the minute it was written.
- The system files: the commands are files in `/bin`, the accounts are
  `/etc/passwd`, who may `sudo` is `/etc/sudoers`, the machine's name is
  `/etc/hostname` and its greeting is `/etc/motd`. Root can take any of them away,
  and the BIOS offers to put them back.
- The terminal window: the green screen, login, command history, the editor, `^C`
  on Escape, and a server-held console so the screen survives a save, a reload and
  a walk away.

Next: `/dev` devices; scripts and cron; networking machines together to automate
doors, locks and lights.

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

**Accounts.** Every machine ships with those two and root can make more:
`sudo adduser bob` writes the account, makes `/home/bob` for it and says out loud
that it has no password yet — set one with `passwd bob` before somebody else does.
`sudo adduser -a bob` sets the account's `admin` flag; the flag is **informational
today** and grants nothing at all — what actually gives power is being `root` or
being named in `/etc/sudoers` — and its one visible effect is the `#` on the
prompt instead of the `$`. `id bob` says what the machine knows about a name, and
`sudo deluser bob` takes it away again (`-r` takes his home directory with it;
without it his files stay, still owned by a name the machine no longer knows).

`su bob` becomes somebody else at the same glass: it asks for **his** password
(root is asked for nobody's), the prompt changes, and `exit` comes back to who you
were instead of logging out — up to four deep. Walk away and come back and the
machine is still where you left it, four users deep if that is where you left it.

Commands:

| command | does |
| --- | --- |
| `ls [-lF] [path]` | list a directory in columns; `-l` adds owner, size and date, `-F` marks directories with `/` |
| `cd [dir]` | change directory (home if no argument) |
| `pwd` | print the working directory |
| `cat <file>...` | print a file |
| `edit <file>` | open the file in the editor |
| `write <file> <text>` | write text to a file (used by the editor's save) |
| `touch <file>` | create an empty file, or move an existing one's date to now |
| `mkdir <dir>` | create a directory |
| `rm [-r] <path>` | remove a file, or a directory tree with `-r` |
| `mv <src> <dst>` | move or rename |
| `cp [-r] <src> <dst>` | copy a file, or a whole tree with `-r` |
| `chmod <mode> <path>` | set permissions (three octal digits) |
| `chown <user> <path>` | change the owner |
| `whoami` | print the logged-in user |
| `id [name]` | `uid=<name> flag=admin\|user groups=sudo\|-` |
| `su [name]` | become another user (`root` by default); `exit` comes back |
| `adduser [-a] <name>` | make an account with an empty password (root only); `-a` sets its `admin` flag |
| `deluser [-r] <name>` | remove an account (root only); `-r` removes its home directory too |
| `hostname` | print the machine's name |
| `passwd [user]` | change a password (root may change anyone's) |
| `hash <text> [salt]` | show what a password would hash to |
| `grep [-i] [-n] <text> <file>...` | find a plain string in files (`-i` ignores case, `-n` numbers the lines); there is no regex on this machine |
| `head [-n N] <file>` | the first N lines, 10 by default |
| `tail [-n N] <file>` | the last N lines, 10 by default |
| `wc <file>...` | lines, words and bytes |
| `date [+FORMAT]` | the date and time, from the game's calendar; with a format, the pieces — `date +%s` is the clock as a plain number |
| `df` | how much of the 32K disk and the 256 nodes are used |
| `man <command>` | what a command does, and how it is spelled |
| `sudo <command...>` | run one command as `root` |
| `shutdown` | switch the machine off (root only) |
| `reboot` / `restart` | switch it off and straight back on (root only) |
| `echo <text>` | print text |
| `clear` | clear the screen |
| `exit` | log out |
| `> file` / `>> file` | redirect a command's output, write or append |

The commands are files: `/bin/<name>`, owner `root`, mode `755`, and the file's
contents are the one-line description `help` prints. `cat /bin/ls` prints
`list a directory`, `rm /bin/ls` really does take `ls` away, and `chmod 644 /bin/ls`
puts it out of everybody's reach but root's. Only `exit` and `help` run without a
file behind them, so that a player who has just wiped the machine he is standing at
can still ask what happened and walk away from it.

`edit` turns the screen into a small editor: Tab saves, Esc leaves — and asks
`Save modified buffer? (y/n)` first when there is something unsaved. Those two are
the only keys the game hands a focused text box, which is why they are the two the
key bar names. A file is capped at 4096 bytes and a line at 60 characters; the game's own text
box stops accepting new keystrokes at 2000 characters typed in one sitting, though a
bigger file still opens and still saves.

`passwd` asks for the old password (skipped for root), the new one, and a retype.
`hash` runs the same hashing the passwords use on any text you give it, so you can
see what a password would look like stored.

`sudo` runs one command as `root`. Who may is `/etc/sudoers`, one name a line, and
a fresh machine has `admin` on it. It asks for **your own** password first
(`[sudo] password for admin: `), and one wrong answer is
`sudo: authentication failure` — there is no second try, because somebody had to be
standing at the keyboard to type the first. A name that is not in the file gets
`<user> is not in the sudoers file.` The command runs with root's powers and the
working directory you were in; the session at the glass is untouched, so
`sudo cd /root` moves nobody and `whoami` still says `admin` afterwards. Put
`NOPASSWD` after a name in `/etc/sudoers` and that account is never asked.

`shutdown` and `reboot` are the power button typed instead of pressed, and they are
root's alone. `shutdown` turns the machine off: the sprite goes dark, the screen is
gone, and every terminal open on it closes. `reboot` turns it off and straight back
on, and the windows stay: everybody standing there watches the BIOS count the
memory again and lands back at `login:`. What is on the disk survives both — this
is a power cycle, not a repair.

**Escape** interrupts what the machine is in the middle of, and closes the window
when it is not in the middle of anything. At a `passwd` or `sudo` question, or with
a login name half typed, it prints `^C` on the line and puts the shell prompt back
(or `login:`); at an idle shell it shuts the window. In the editor it is still the
editor's Escape, and at the BIOS' question — which has nothing behind it to give up
on — it still closes.

If the machine will not boot — no `/bin`, or no account left in `/etc/passwd` — the
screen ends on `No operating system found.` and `Restore system? (y/n)`. `y` puts
the commands, the accounts and the system files back and touches nothing under
`/home` or `/root`; `n` leaves it sitting there, and anything typed at it brings the
question back; `exit` or Escape walks away from it.

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
session, line, env)` takes a state, a command line and the world outside the machine,
and returns `ok, lines, control, data`, and nothing else. It makes no game call, touches no `os`/`io`/`require`, no
coroutines and no metatables, so it runs the same under a plain `lua5.1` and under
the game's Kahlua. `lines` is text, one array entry per screen line, at most 60
characters. `control` is `nil`, `"clear"`, `"exit"`, `"prompt"`, `"edit"`,
`"shutdown"` or `"reboot"` — an order to the terminal, carried beside the output and
never inside it, so a file's contents can never be mistaken for one. `"prompt"` and
`"edit"` carry a payload in `data`: `"prompt"` is how a command like `passwd` or
`sudo` asks a question without a coroutine (`CeroSecOS.continue` answers it the same
way `exec` answers a command line); `"edit"` hands the terminal a path, the file's
text, whether it may be written back, and the account it was opened as.
`"shutdown"` and `"reboot"` carry nothing: the engine has no machine to switch off,
so it says what should happen and the server — which owns the sprite, the sound, the
power and the windows — is what does it.

A command that has to ask something answers `"prompt"` with an opaque continuation
token, and the console hands the next line typed to `CeroSecOS.continue`. Nothing of
a password ever goes into a token: between `New password:` and `Retype new
password:` what is carried is a hash of the answer with its own salt, and a `sudo`
token carries only the command that was typed and the account that typed it — the
answer is judged against `/etc/passwd` when it arrives. A token started under `sudo`
carries `as = "root"`, which is what makes `sudo passwd root` root's for the whole
chain while the console's own session stays `admin`'s.

On top of the engine sits a server-authoritative `SGlobalObject` system
(`SCeroSecObject`, `SCeroSecSystem`) that holds each computer's OS state and, while
it is on, a console:
`{ booted, user, cwd, pending, lines, prompt, edit, halted }`. There is one console
per computer, not one per player — that is what makes walking away and coming back
find the same screen, and two players at one computer share it. The client mirror
(`CCeroSecObject`, `CCeroSecSystem`) never holds the filesystem or the screen; it
only shows the sprite and relays input.

The context menu (`CeroSecContextMenu.lua`), the reach checks (`CeroSecReach.lua`)
and the terminal window (`CeroSecTerminal.lua`, an `ISCollapsableWindow`) are all
client-side. The window talks to the server over the global object channel:

    client -> server: open, exec, close, input, interrupt,
                      editbuf, editsave, editexit
    server -> client: opened, screen, closed

A screen is sent whole: the lines, the prompt, the mode (`prompt`, `shell` or
`edit`), whether the answer is masked, whether the machine is in the middle of
something (`active`), and the editor's own screen. The window draws what it is
handed and works nothing out for itself — which is why Escape can be an interrupt
without the window ever having to tell `New password:` from any other question.
`interrupt` is that Escape: it clears the pending question on the machine, so every
window standing at it sees the same `^C` on the same line.

Every command carries the window's own token and every answer carries it back
(`sendServerCommand` reaches one connection, or the global object broadcast in
singleplayer where there is only one), because the server addresses a connection
and split screen puts several players on one. The server keeps a watcher list per
computer and answers every open window with the new screen under its own token.

#### The clock

The engine has no clock and asks for none. `env.now` is one number — seconds since
1970-01-01 00:00:00, counted on the *game's* calendar — and it is handed in at every
`exec` and `continue`. `env` is optional: without it the machine has no clock, `date`
answers `date: no clock`, and nothing is stamped. That is what lets a test pin every
timestamp to a fixed moment.

The server builds it in `SCeroSecSystem:clockEnv()` from `getGameTime()`:
`getYear()`, `getMonth() + 1`, `getDay() + 1`, `getHour()`, `getMinutes()` — the
month and the day are 0-based in `zombie.GameTime`, which is why vanilla adds one to
them everywhere it prints them and why `getDayPlusOne()` exists. There is no
`getSeconds()`: the game's finest hand is the minute, so the second is always `:00`.

Every node may carry an `mtime`, that same number. It is absent on every node saved
before this build and on everything a fresh machine ships with; absent means 0, read
through `CeroSecOS.mtimeOf` and never off the field, and `validate` accepts a node
without one. The four mutators (`createNode`, `removeNode`, `setData`, `moveNode`)
take the clock as a last argument and `nil` means "no clock": the mutation happens,
nothing is stamped. This machine has one timestamp where Unix has three, so it stands
for `mtime` and `ctime` both — a `chmod` and an `mv` move it. A create or a remove
also moves the *parent directory's* stamp, because a directory's date is when its
listing last changed.

`date +FORMAT` prints that number's pieces, `CeroSecOS.formatTime`'s way: `%Y %m
%d %H %M %S %j %a %b %e %s %%`, padded the way Unix pads them (`%d` is `08`, `%e`
is ` 8`), with anything else — an unknown code, a `%` at the end of the format —
copied out exactly as it was typed rather than silently swallowed. `%s` is
`env.now` itself, the very number a node's `mtime` carries, which is what a script
on the machine does arithmetic on. No clock stays no clock with a format: `date
+%s` on a machine with none answers `date: no clock` rather than handing out a
zero.

`CeroSecOS.DISK_BYTES` is the one number for the drive: the BIOS announces it
(`CeroSec.bootLines()` appends `hda 32K`), `df` divides by it, and the write path
refuses to go past it. There is no second copy of it anywhere to drift.

### System files, and their formats

A machine is a filesystem and nothing else. What makes it a machine that can be
*used* is what is in that filesystem, and each of these files is the truth about
what it holds — there is no table of users beside `/etc/passwd`, no list of commands
beside `/bin` and no list of sudoers beside `/etc/sudoers`. Root editing one of them
with the editor changes the machine, and `rm -r /bin` really does take the commands
away. The way back is the BIOS, not a guard rail on the command: root keeps full
power, and the protection is that root has a password.

**`/bin`** — one file per shell command, owner `root`, mode `755`, contents the
one-line description. The shell resolves `args[1]` as `/bin/<name>` and nothing else
(no `PATH`, no `./thing`): nothing there, no `/bin` at all, `/bin` a file, a
directory called `/bin/ls`, or a file with no Lua command behind it are all
`<name>: command not found`; a file without `x` for this user, or a `/bin` he cannot
read, is `<name>: permission denied`. `exit` and `help` are the only builtins.

**`/etc/passwd`** — the accounts, owner `root`, mode `600`, one a line:

    name:$cs1$<salt>$<32 hex digits>:home:admin|user

Parsing is strict and silent: a line is skipped when it is not exactly four fields,
when the name is not a valid name, when the second field is not one of our `$cs1$`
strings, when the home is not an absolute path of `[A-Za-z0-9._/-]`, or when the
last field is neither `admin` nor `user`. A name that appears twice keeps its
**first** line, and a file that parses to nothing is a machine nobody can log in to
— which is the BIOS' business, not an error. The kernel reads it without going
through the permission bits (`CeroSecOS.systemNode`), because nobody is logged in
yet; that is the one read in the whole core that does not go through `getNode`. It
is parsed on demand and cached in one slot keyed on the node **and its text**, so
any write invalidates the cache by construction. `passwd` rewrites the whole file
through the ordinary `setData`, so the ceilings and the printable rule apply and a
refusal leaves it byte for byte as it was.

`adduser` **appends** its line and `deluser` drops every line that names the
account, keeping every other line exactly as it lies — comments and unparseable
lines included; only `passwd`, which has to touch a line in the middle, rewrites
the file from what it parsed. Both go through the ordinary `setData`, so a full
disk refuses an `adduser` the way it refuses a `touch`. The name a machine will
*make* is narrower than the name it will *parse*: `[a-z][a-z0-9_-]` up to sixteen
characters, so that it is always a name a prompt, a home directory and an `ls -l`
owner column can hold — while a machine that has been running a while keeps
whatever accounts are already in its file. The last field, `admin` or `user`, is
**informational**: nothing in the core reads it except the prompt, which wears
`#` for an `admin` account and `$` for a `user` one, and `id`, which prints it.
Power is being `root` or being in `/etc/sudoers`, and a later rung is what will
give the flag a meaning.

**`/etc/sudoers`** — who may `sudo`, owner `root`, mode `440`, one name a line with
an optional ` NOPASSWD` after it. Blank lines and lines whose first non-blank
character is `#` are comments; anything else that is not a name, or a name and the
single word `NOPASSWD`, is skipped, and a name that appears twice keeps its first
line. Same one-slot content-keyed cache as the accounts. Root is never looked up in
it: an `/etc/sudoers` with nobody in it must not be able to take `sudo` from the one
account that can put it back.

**`/etc/hostname`** — the machine's name: 1 to 16 characters of `[a-z0-9-]`, never
starting with `-` (the name is written into `state.hostname` too, where `validate`
tests it with `isValidName`). `hostname <name>` is root only. A file that does not
hold a name falls back to `state.hostname` and then to `CeroSecOS.DEFAULT_HOSTNAME`.
The server reads the file for the window title and for every prompt.

**`/etc/motd`** — what greets a login and ends the boot, capped at 10 lines; a
missing or empty file falls back to the built-in `CeroSecOS.MOTD`.

**The BIOS.** On `open`, before a line is put on the screen, the machine has no
operating system when the state does not validate, or `/bin` is missing, not a
directory or empty, or `/etc/passwd` is missing, not a file, or parses to no
accounts. Then the boot ends on `No operating system found.` and
`Restore system? (y/n) ` — an ordinary console prompt with an ordinary continuation
token (`cont = { cmd = "bios" }`), answered on the server because there is no session
to run it under. The refusal (`n`) is the machine's and not the window's: a second
player opening a window on a halted machine finds the refusal, not a fresh question.

`CeroSecOS.restoreSystem` makes `/etc` if it is missing or is not a directory,
creates `/etc/hostname` and `/etc/motd` only if missing, replaces `/etc/passwd` and
`/etc/sudoers` only if missing, not a file, or parsing to nothing at all, makes
`/bin` and rewrites every standard executable to owner `root`, mode `755` and its
description, and rebuilds the filesystem root if the state has no usable one. It
touches **nothing else** — `/home`, `/root`, `/dev` and anything a player made come
through untouched, a `/etc/passwd` that still parses keeps its hashes, and a file of
your own in `/bin` is left where it is. Running it twice changes not one byte. If
the validator refused the state for a reason the repair does not address, the
machine comes back to `No operating system found.` and asks again: the BIOS puts the
system files back, it is not a disk doctor.

**Migration.** A save from before `/etc/passwd` carries its accounts in a
`state.users` table (and, before that, in clear): `CeroSecOS.migrateUsers` hashes
what is still clear, writes the file, fills `/bin` and drops the table, so such a
machine boots straight to its login prompt with the same accounts, homes, admin
flags and passwords. A state that somehow has both a table and a parseable file
keeps the **file**. An unknown version, or junk, becomes a brand new machine. Damage
done in the game goes through the BIOS restore instead. `validate` knows nothing
about accounts any more: it checks that `/etc/passwd` is there, is a file and is
root's, and the rest is the parser's business. A machine saved before `/etc/sudoers`
existed simply has none, and the `sysv` top-up (see "Persistence") writes it on the
next load rather than making anyone go through the BIOS for it.

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

The state also carries `sysv`, the *contents* it was built with (4 today) as
opposed to `v`, the schema. A wave that adds a command adds a file to `/bin`, so
on load `CeroSecOS.upgradeSystem` tops a machine behind on that number up — the
standard executables that are missing, and `/etc/sudoers` when there is nothing at
that name — and then moves the number up. At the current number it does nothing at
all, which is what keeps root's `rm /bin/ls` a deletion and not a suggestion.

`console.stack` is the su stack: `{ { user = "admin", cwd = "/home/admin" }, ... }`,
innermost last, at most `CeroSec.SU_MAX` (4) deep — the same number the core
enforces as `CeroSecOS.SU_MAX`, named twice because the terminal never loads the
core and pinned against it by `os_test`. It is machine state like `console.user`
and `console.cwd`: `su` pushes onto it, `exit` pops, a logout, a `reboot` and a
`shutdown` drop it, and `repairConsole` keeps it entry by entry — only where an
entry is still a name and a path, and never deeper than the ceiling, so a forged
console cannot hand back a stack that takes ten exits to get out of. An empty
stack is stored as no stack at all. The core sees it on the session
(`session.stack`), beside `session.login` — the account really at the glass, as
opposed to the account a command is running as. A borrowed session (sudo's, and a
chain carrying its authority) is given `login` and a **copy** of the stack: it may
read who the glass would come back to (`deluser` refuses to remove one of them)
and anything it pushes or pops dies with the command, which is why `sudo su` moves
nobody and `sudo exit` is still a logout.

The editor's buffer lives in the console too (`console.edit`), with the account it
was opened as: `sudo edit /etc/motd` opens the buffer as `root` and saves as `root`,
four minutes later, while the session at the glass is still `admin`'s. A buffer with
no account on it — one opened before `sudo` existed — is the session's, as it always
was.

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
