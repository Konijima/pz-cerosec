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
  shell (`[ adduser cat cd chgrp chmod chown clear cp date deluser dev df echo
  edit exit false gpasswd grep groupadd groupdel groups halt hash head help
  hostname id jobs kill ls man mkdir mv passwd printf ps pwd reboot restart rm sh
  shutdown sleep su sudo tail test touch true wait wc whoami write`), an editor,
  and salted-hashed passwords.
- One shell, at the prompt and in a file alike: every typed line is parsed by the
  script engine and runs as a job, so `&&`, `if`, `for`, `while`, `$(...)`, `$((...))`
  and a trailing `&` all work where you type them. Variables and `$?` persist with
  the console, `~/.sh_history` remembers what was typed, `~/.profile` runs at login,
  and `shutdown -r +5` warns everybody standing at the machine first.
- Accounts: `adduser` and `deluser` make and unmake them, `su` changes who the
  glass is logged in as without logging out, and `id` says what the machine knows
  about a name.
- Groups: `/etc/group`, a group on every file, and all three digits of a mode read
  — owner, group, everybody else — so two survivors can share a directory. The
  `sudo` group mirrors `/etc/sudoers`, which is what makes `crw-rw----  root  sudo`
  on every device mean "whoever may become root may throw that light switch".
- The clock: the machine reads the game's calendar, so `date` is the hour the
  survivor is living in and every file carries the minute it was written.
- The system files: the commands are files in `/bin`, the accounts are
  `/etc/passwd`, who may `sudo` is `/etc/sudoers`, the machine's name is
  `/etc/hostname` and its greeting is `/etc/motd`. Root can take any of them away,
  and the BIOS offers to put them back.
- The terminal window: the green screen, login, command history, the editor, `^C`
  on Escape, and a server-held console so the screen survives a save, a reload and
  a walk away.
- Devices: `/dev` holds the light switches, lockable doors and windows the machine
  can reach, and `dev` is the everyday way to see them all at once — with each
  one's offset from the computer, since room names repeat — read one, work one,
  `toggle` it, or `find` it and watch it blink or light up in the world.
- Scripts: a real shell language in a file -- variables, `if`, `for`, `while`,
  `until`, `test`, `&&`, `||`, `$(command)`, `$((arithmetic))`, `read`, `sleep`,
  background jobs -- run by a step machine on a budget, so an endless loop makes
  one machine slow at one thing and costs the server nothing. `ps`, `jobs`, `kill`
  and `wait` to see and stop them; Escape is `^C`.
- The manual: a printed book that spawns where computers do, read by the player in
  a two-page reader with a table of contents, and remembering the page it was left
  on.

Next: `cron`, `wait` on a device, pipes and `fg`; networking machines together to
automate doors, locks and lights.

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

**Sharing a file.** A mode is three digits — you, your group, everybody else — and
the machine reads exactly one of them: the first if you own the file, the second if
you are in its group, the third otherwise. Root walks through all three. Every
account is already in a group of its own name, so a fresh file is shared with
nobody until you say otherwise:

```
sudo groupadd crew
sudo gpasswd -a bob crew
chgrp crew notes.txt
chmod 660 notes.txt
```

Now you and `bob` both read and write `notes.txt` and nobody else can open it.
`groups` and `id` say what you are in; `ls -l` shows the group beside the owner.
A shipped machine already has `users`, which `admin` is in. Delete a group and
files still naming it keep the name — `ls -l` shows it dangling, nobody is in it,
and `chgrp` will not hand that name out again.

`/etc/sudoers` stays the authority on who may `sudo`; the `sudo` group mirrors it,
so a name in that file is in the group whether a line of `/etc/group` says so or
not. Joining the group by hand shares the group's files and nothing else — it does
not give out root.

Commands:

| command | does |
| --- | --- |
| `ls [-laAF] [path]` | list a directory in columns; `-l` adds owner, group, size and date, `-F` marks directories with `/`, `-a` shows hidden names plus `.` and `..`, `-A` shows hidden names without them |
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
| `chmod <mode> <path>` | set permissions: three octal digits, or letters applied to the mode it already wears — `u+x`, `go-w`, `a=r`, `ug+rw,o-rwx` |
| `chown <user> <path>` | change the owner |
| `chgrp <group> <path>` | change the group (owner or root; the group must exist) |
| `whoami` | print the logged-in user |
| `id [name]` | `uid=<name> flag=admin\|user groups=<its groups, comma-separated>` |
| `groups [name]` | the same list, blank-separated |
| `groupadd <name>` | make a group (root only) |
| `groupdel <name>` | remove one (root only); `root`, `sudo` and `users` cannot go |
| `gpasswd -a\|-d <user> <group>` | put a name in or out of a group (root only) |
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
| `dev [kind\|id [value\|toggle]\|find <id>]` | the devices as a table, one kind of them, one read, or one worked — `dev light0 off`, `dev lock2 toggle`; `dev find lock1` makes it show itself for six seconds |
| `man <command>` | what a command does, and how it is spelled |
| `sudo <command...>` | run one command as `root` |
| `shutdown [-h\|-r] [now\|+N]` | switch the machine off, or reboot it with `-r`; `+N` is N minutes from now and warns every screen at the machine (root only) |
| `shutdown -c` | call a pending one off |
| `halt` | `shutdown -h now` under its older name (root only) |
| `reboot` / `restart` | switch it off and straight back on (root only) |
| `history [-c]` | the last 60 lines of `~/.sh_history` with numbers; `-c` empties it |
| `!!` / `!<n>` | run the last line again, or line `<n>` |
| `sleep <seconds>` | wait, costing the machine nothing while it does |
| `printf <format> [arg...]` | `%s`, `%d`, `%%`, `\n` and `\t` |
| `test <expr>` / `[ <expr> ]` | the file and string tests, as in any `sh` |
| `true` / `false` | a status and nothing else |
| `echo <text>` | print text |
| `clear` | clear the screen |
| `exit` | log out |
| `> file` / `>> file` | redirect a command's output, write or append |

The commands are files: `/bin/<name>`, owner `root`, mode `755`, and the file's
contents are the one-line description `help` prints. `cat /bin/ls` prints
`list a directory`, `rm /bin/ls` really does take `ls` away, and `chmod 644 /bin/ls`
puts it out of everybody's reach but root's. That holds for the small ones the
engine runs without leaving the house too — `echo`, `printf`, `test`, `[`, `true`,
`false` and `sleep` are resolved through `/bin/<name>` first and then executed
inside the engine, so `rm /bin/sleep` gives `sleep: command not found` and
`chmod 600 /bin/echo` gives `echo: permission denied` to an ordinary account.
`/bin/sh` is the shell itself: delete it and every line typed answers
`sh: command not found`, and the BIOS repair brings it back.

Three kinds of word are **not** files, and could not be. The reserved words
(`if then elif else fi for while until do done`) are grammar. The state builtins
(`cd read shift break continue history`) change the shell itself, which no separate
program could do. And `exit` and `help` have no file on purpose, so that a player
who has just wiped the machine he is standing at can still ask what happened and
walk away from it. `help` prints the `/bin` table first and those words under it.

A name beginning with `.` is hidden from `ls` and `ls -l`; `ls -a` shows them with
`.` and `..`, `ls -A` shows them without. Nothing else treats a dotted name as
special — there is no globbing here for one to hide from.

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

`shutdown` also takes a time. `-h` halts, `-r` reboots, neither halts; `now` and no
time at all are the same thing. `+N` is N minutes away, and the machine broadcasts
to every screen in front of it when the order is given, again one minute before, and
once more as it goes:

```
root@ksp-04-11:~# shutdown -r +5
The system is going down for reboot in 5 minutes!
...
The system is going down for reboot in 1 minute!
...
The system is going down for reboot NOW!
```

`shutdown -c` prints `shutdown: cancelled`. One pending order per machine: a second
is `shutdown: already scheduled` rather than a quiet replacement, because nobody
should be told two different times. `halt` is `shutdown -h now`.

The timer is the scheduler's pass and lives on the machine, not in the window: close
the window, walk away, come back, and it is still counting. It is **not** persisted
— the power going out, the computer being picked up, or a reload all forget it, and
the machine stays up. That is deliberate and it is in the manual: this machine has
no process table on its disk.

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

The building the computer stands in is wired to it. `/dev` holds one file per
light switch, lockable door and window it can reach — its own building when its
square has one, every room of it; ten tiles of its own floor when it has not,
which is what a computer in a player-built base gets. `dev` is how you work them:

```
dev
light0  office                0 0            on
light1  hallway               3E 2N          off
lock0   exterior              0 5S        W  locked
lock1   kitchen-hallway       2W 1N       N  unlocked
lock2   built                 4E 9S +1    N  padlock
win0    office                1E 0        N  locked
```

The id you name it by, the rooms it stands between — the map's own raw names,
`exterior` where one side is the outdoors, `built` for something a player put up
— where it is from where the computer stands, which way it faces, and its state.
The offset is the column that tells two devices apart when the room names do
not: tiles east or west, tiles north or south, `0 0` for the computer's own
square, and `+1` / `-1` for a floor that is not this one. The table runs by kind
and then by number,
so `light2` comes before `light10`; in a big building `dev light`, `dev lock` and
`dev win` cut it down to one kind. One id reads that one back, an id and a word
works it and answers with the state read back afterwards, and `toggle` is
whichever of the pair it is not in now:

```
dev light0          -> light0: on
dev light0 off      -> light0: off
dev lock2 toggle    -> lock2: unlocked
dev find lock1      -> lock1: highlighted
```

`dev find` answers the question a listing cannot: **which** of the thirty-five it
is. A light blinks for six seconds and goes back exactly as it was found — a
server-side timer on `Events.OnTick`, gated on `getTimestampMs()` the way
vanilla's own `forageServer` gets under a minute — and a light with no power
answers `light0: no power`, the same as a write. A door or a window has nothing
to blink with, so the server tells the one window that asked where to look and
that player's client outlines the object with vanilla's `setHighlighted` /
`setOutlineHighlight`, which take the local player number first: in multiplayer
only the survivor who typed it sees the outline. It asks for the right it uses —
a light is switched, so blinking one needs write; a door is only drawn around, so
reading it is enough.

Underneath, `dev` is `cat` and a redirect on the node — the same permissions, the
same words, the same refusals — and `ls -l /dev` is the same devices with the
mode, the owner and the group in front of them and no room left for the offset:

```
crw-rw----  root  sudo  lock0   exterior       W  locked
crw-rw----  root  sudo  light0  office            on

cat /dev/light0
echo off > /dev/light0
```

`light` takes `on` and `off`; `lock` and `win` take `lock` and `unlock`. Anything
else is `light0: invalid value`. A device answers in its own name, not the
command's:

| line | what happened |
| --- | --- |
| `light0: no power` | the switch has no electricity, no bulb, or nothing to switch |
| `lock0: no such device` | it was taken away, or it is in a chunk nobody has loaded |
| `win0: smashed` | the glass is gone; there is no lock left to turn |
| `win0: barricaded` | it is boarded up |
| `lock2: no padlock` | a player-built door with neither padlock nor key on it |
| `light0: invalid value` | that word means nothing to that kind |
| `light0: permission denied` | the mode says no |
| `win0: cannot toggle` | smashed or barricaded: no opposite for `toggle` to turn it into |

`dev`'s own two are a command's and are signed like one: `dev: <word>: unknown
kind` (the kinds are `light`, `lock` and `win`) and `dev: <id>: no such device`
for a name no device of the machine's answers to at all.

A number belongs to a device for the life of the machine. `light0` is the same
switch tomorrow as it is today, and one that is torn out leaves a **gap** —
nothing moves up into it — so a line you wrote into a file still means what it
meant. A device that is out of reach is not listed at all; naming it says `no
such device`, which is the difference between a switch that is off the grid and a
path you mistyped.

Devices are owner `root`, group `sudo`, mode `660` — so root and anybody
`/etc/sudoers` names read and work them, with no `sudo` typed and no password
asked, and everybody else gets `light0: permission denied` from the device itself.
Root may open one up to everybody with `chmod 666 /dev/light0` — that lasts.
The group does not move: `chgrp` on a device answers `is a device`, because only
the mode of one outlives the command it was typed in. Nothing else works on one
either: `rm`, `mv`, `cp` and `edit` all answer `is a device`, and nothing can be
created in `/dev` at all.

Opening a door is not this. `unlock` takes the lock off; somebody still has to
walk over and open it.

Click the window's close button, or run `exit`, to leave. The screen itself keeps
running: log back in later and it is exactly as it was left.

### The prompt, and a script

**The prompt is the script language.** There is no second, simpler shell for typed
lines: every line goes through the same parser a file does and runs as a foreground
job on the console's own environment. So this works where you type it:

```
admin@ksp-04-11:~$ while true; do echo tick; sleep 1; done &
[1] 43
admin@ksp-04-11:~$ jobs
[1] sleeping while true; do echo tick; sleep 1; done &
admin@ksp-04-11:~$ kill %1
[1] killed
```

Multi-line constructs go on one line, all of it. There is no continuation prompt:
a line with an unfinished construct answers `sh: syntax error: missing 'done'` and
nothing runs. A refusal the shell itself makes carries no line number — a typed line
is line one of nothing — but past the first level it is inside a file again
(`sh backup.sh`) and that file's name and line come back.

Variables and `$?` belong to the machine: `x=5` on one line and `echo $x` on the
next are the same environment, and walking away and coming back finds it. Logging
out takes them, as it takes the rest of the session. `cd` at the prompt moves the
console; `cd` inside a script moves the script.

`ps` shows the shell you are typing into, the way every Unix `ps` does; `jobs` does
not, because the shell is not one of the things the shell started. That is also why
the first background job is `[1] 43` and not `[1] 42` — the shell itself took 42 —
and the four-job ceiling is still four *scripts*.

Two costs worth knowing. Double quotes expand, so `"$x"` is the variable and `'$x'`
is two characters. And one word is 1024 bytes (the script engine's ceiling); the
typing line only takes 240 characters, so nothing typed reaches it and the editor is
what fills a file to its own 4096.

**History.** Every typed line is appended to `~/.sh_history` — the POSIX/ksh name —
owner-only at mode 600, in the account's own home. `history` prints the last 60 with
numbers, `history -c` empties it, `!!` re-runs the last line and `!5` line five (the
expanded line is what is echoed, run and remembered). Up and Down in the window walk
that file, not a list the window kept, so a survivor who comes back tomorrow presses
Up and finds what he typed today. Answers to prompts are never in it.

The file holds 1000 entries and 16 KB, whichever comes first, oldest dropped. Those
16 KB are exempt from the 32 KB disk quota — a shell's memory of itself must not be
the thing that fills the drive — so `df` does not move because somebody typed, while
`ls -l` still tells the truth about the size. The exemption belongs to the **path**
and not to the file: `mv ~/.sh_history loot.txt` and every byte of it counts from
that moment on, `mv` it back and it is exempt again. Two honest deviations from a bigger shell:
the numbers `history` prints are positions in the file as it stands, so they shift
once the oldest drop off; and `!` is only an event when it is the whole line, there
being no quoting rule for it here.

**`~/.profile`** runs at login, after the motd and before the first prompt, if the
file exists and the account may read it. It runs as the shell's own job, which is
the point: a variable it sets is set at the prompt and a `cd` it does is where you
are standing. Its errors read like a script's (`.profile: line 2: ...`) and it
respects every budget. The quirk that comes with that, named in the manual: a
`.profile` with an endless loop in it leaves the account at a busy prompt with
nothing to type at. It is not a locked machine — Escape is the `^C` — and then edit
the file. The BIOS repair never touches homes, so restoring a machine never removes
one.

A script is a text file with commands in it. Write one with `edit`, run it with
`sh`, or give it `x` and run it by its path:

    admin@ksp-04-11:~$ edit lights.sh
    admin@ksp-04-11:~$ sh lights.sh
    admin@ksp-04-11:~$ chmod 755 lights.sh
    admin@ksp-04-11:~$ ./lights.sh

A bare name is still a command in `/bin` and only there, so a script in your home
is never found by typing its name alone.

The language is the one you already know from a 1993 `/bin/sh`, cut to what fits on
a desk machine: `NAME=value` and `$NAME`, `${NAME}`, `$1`..`$9`, `$#`, `$@`, `$?`,
`$$`; single and double quotes and backslash; `#` comments; `;`, `&&`, `||` and a
trailing `&`; `if`/`elif`/`else`/`fi`, `for`/`in`, `while`, `until`, `break`,
`continue`, `exit`, `return`; `test` and `[ ... ]` with `-f -d -e -r -w -x -z -n`,
`=`, `!=`, `-eq -ne -lt -le -gt -ge`, `!`, `-a`, `-o`; `$(command)` one level deep
and `$((1 + 2 * 3))` on whole numbers; and `echo [-n]`, `printf`, `read`, `sleep`
and `shift` as builtins that work even on a machine whose `/bin` has been emptied.

    #!/bin/sh
    for d in light0 light1 light2; do
      echo off > /dev/$d
    done
    read -p "and the office? (y/n) " a
    if [ "$a" = y ]; then echo off > /dev/light3; fi

Every one of those works at the prompt too, being the same shell.

`read` stops the script and asks at the prompt; the next line typed is the answer.
`sleep 5` waits five seconds of real time and costs the machine nothing while it
does. While a script has the prompt there is nothing to type at, and Escape is
`^C`: it kills what is running.

A line ending in `&` runs in the background and gives the prompt straight back:

    admin@ksp-04-11:~$ sh watch.sh &
    [1] 42
    admin@ksp-04-11:~$ ps
      ID S     CPU COMMAND
      42 R      96 sh watch.sh
    admin@ksp-04-11:~$ kill %1

`jobs` lists them by slot, `ps` by number with the state (`R` running, `S`
sleeping, `W` waiting for an answer, `O` held back by the screen) and the steps
spent, `kill` takes either a number or `%slot`, and `wait` holds the prompt until
the background jobs are done. Four jobs to a machine.

**A runaway script cannot hurt anybody.** Every job gets a slice of each tenth of a
second and no more, so `while true; do echo x; done` makes that one machine slow at
that one thing: the prompt still answers, other screens still draw, and the server
never waits. Output is held to twenty lines a second, so it trickles instead of
flooding — for a typed line as much as for a script's, which is why a long `help`
scrolls out rather than appearing whole. A job that spins for five minutes with no wait in it is taken away with
`killed: cpu limit`. A string that doubles every turn, or a script that runs itself,
meets a ceiling and stops with a line naming it. Jobs are not saved: switching off,
rebooting, picking the computer up or reloading the world leaves it running nothing.

### Finding the manual

**CeroSec OS User's Manual** is a printed book, and it is the documentation for
everything above — the commands, the files, the accounts, the BIOS — written for
somebody sitting at one of these machines in 1993.

It is loot. It is not in a crafting recipe and it is not given to you at the start:
it spawns where a book about a computer would have been sold, shelved or left
behind. The computer aisle of a **library**, a **bookshop** or a **university
library**; a **cyber cafe**'s desks and filing cabinets; the magazine rack of an
**electronics store**; a **university computing desk**; a **control room** counter.
More rarely, in an **office desk** or on an **office supply shelf**, where somebody
who bought one put it down. Rarest of all, on a **living room shelf** at home.

Rare, and findable: in the computer section of a library it is roughly the odds of
a particular computer paperback, so a shelf or two of looking. In a random office
desk it is the rarity of a business paperback, so it is a surprise. The exact
weights, and the vanilla items each one was measured against, are in
`42/media/lua/server/CeroSec/CeroSecManualLoot.lua`.

**Reading it.** Right-click the book in your inventory and choose **Read the
manual**. It opens as an open book: two pages side by side, a chapter title at the
head of each leaf, page numbers at the outer corners.

| | |
| --- | --- |
| **Next >** / Right arrow | turn the sheet forward |
| **< Back** / Left arrow | turn it back |
| **Contents** | the table of contents; click a chapter to jump to it |
| **Escape** | close the book |

The survivor does not read it — **you** do. There is no reading skill, no time
spent, no animation and nothing queued: the book is paper on your screen and the
character goes on doing whatever he was doing. Walk with it open, fight with it
open, drive with it open.

Where you left off is written on **that copy of the book**, so closing it and
opening it again puts you back on the same spread, across a save as well. Two
copies are two bookmarks.

## For modders and contributors

### Repository layout

The repo root **is** the mod folder. It has to live at a real, non-symlinked path
under `~/Zomboid/mods/` — Build 42's `ScriptManager` resolves each `media/scripts`
file against the mod's canonical, symlink-resolved path while it is *found* through
the link, so the relative path degenerates into the full absolute path and every
script fails with `FileNotFoundException`. Lua and translations are unaffected;
scripts are not, so the whole mod has to sit where it is loaded from.

- `42/` — `mod.info`, `media/lua/{shared,client,server}/CeroSec/`, translations.
- `common/` — sounds, textures, and the script files: `sounds_cerosec.txt` and
  `items_cerosec.txt`.
- `tests/` — headless, no game needed: `sh tests/run.sh`.
- `docs/` — manual, in-game test checklists.
- `workshop/` — `workshop.txt` and `preview.png` for the Steam Workshop uploader.

### Architecture

`42/media/lua/shared/CeroSec/OS/` is a pure-Lua OS engine. It makes no game call,
touches no `os`/`io`/`require`, no coroutines and no metatables, so it runs the same
under a plain `lua5.1` and under the game's Kahlua.

There is **one** door in, and it is the script engine:

```
CeroSecOS.promptJob(state, session, line, vars, status, name) -> job, refusal
CeroSecOS.jobStep(state, job, env, budget)                    -> status, spent
```

A typed line is parsed by `CeroSecOS.parseScript` and becomes a job; the caller
steps it. There used to be a second, simpler path for one-command lines
(`CeroSecOS.exec` over `CeroSecOS.parseLine`, with `splitBackground` for a trailing
`&`) and all three are **gone** — that second parser is the bug this rung fixed, and
it must not come back. A command already split into words still has its own entry
point, `CeroSecOS.runArgs(state, session, args, redirect, env)`, which is the door
both a job and `sudo` reach a command through.

`lines` is text, one array entry per screen line, at most 60 characters. `control`
is `nil`, `"clear"`, `"exit"`, `"prompt"`, `"edit"`, `"job"`, `"shutdown"`,
`"reboot"`, `"schedule"` or `"cancel"` — an order to whoever runs the machine,
carried beside the output and never inside it, so a file's contents can never be
mistaken for one. `"prompt"`, `"edit"` and `"schedule"` carry a payload in `data`:
`"prompt"` is how a command like `passwd` or `sudo` asks a question without a
coroutine (`CeroSecOS.continue` answers it); `"edit"` hands the terminal a path, the
file's text, whether it may be written back, and the account it was opened as;
`"schedule"` is `shutdown +N` handing over the moment and the kind. The rest carry
nothing: the engine has no machine to switch off, so it says what should happen and
the server — which owns the sprite, the sound, the power and the windows — does it.

A control from inside a job **ends** the job, the way a real shell's `exec` does: a
line that has ordered the machine off has nothing left to say.

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
`{ booted, user, cwd, pending, lines, prompt, edit, halted, shvars, status, job }`.
`shvars` is the shell's own variables and `status` its `$?` — the prompt is an
environment, not a series of unrelated commands, and both are machine state saved
with the console and sanitised by `CeroSec.repairConsole` on the way back in
(`MAX_VARS`, `MAX_VAR_BYTES`, exactly a job's ceilings). There is one console
per computer, not one per player — that is what makes walking away and coming back
find the same screen, and two players at one computer share it. The client mirror
(`CCeroSecObject`, `CCeroSecSystem`) never holds the filesystem or the screen; it
only shows the sprite and relays input.

The context menu (`CeroSecContextMenu.lua`), the reach checks (`CeroSecReach.lua`)
and the terminal window (`CeroSecTerminal.lua`, an `ISCollapsableWindow`) are all
client-side. The window talks to the server over the global object channel:

    client -> server: open, exec, close, input, interrupt,
                      editbuf, editsave, editexit, histtail
    server -> client: opened, screen, closed, history

A screen is sent whole: the lines, the prompt, the mode (`prompt`, `shell` or
`edit`), whether the answer is masked, whether the machine is in the middle of
something (`active`), the editor's own screen, and `user` — who is logged in, as one
short string. The window's Up/Down history is the account's own `~/.sh_history`, sent
in its own `history` reply when a window opens and whenever `user` changes under it
(a login, an `exit`, an `su`); a hundred lines on every screen would be a hundred
lines on the wire every time anybody typed. The window draws what it is
handed and works nothing out for itself — which is why Escape can be an interrupt
without the window ever having to tell `New password:` from any other question.
`interrupt` is that Escape: it clears the pending question on the machine and kills
the foreground job, so every window standing at it sees the same `^C` on the same
line.

`Commands.exec` echoes the line, appends it to the history, and then runs
`CeroSecJobs.runMachine` **in the player's own hand** — one scheduler pass, right
there — rather than leaving the line to the next tick. Two orders need a player:
`edit` has to know whose keyboard is on the buffer, and `dev find` answers on one
screen rather than on the machine's. So an ordinary `ls` still answers in the same
round trip it always did; a line that does not finish in that pass becomes a running
job like any other. `Commands.input` and `Commands.interrupt` serve a pass the same
way, which is what makes `sudo reboot` end on its password and the prompt come back
from a `^C` without waiting a tick. `SCeroSecSystem:runProfile` is the same call
again, on the text of `~/.profile`.

Every command carries the window's own token and every answer carries it back
(`sendServerCommand` reaches one connection, or the global object broadcast in
singleplayer where there is only one), because the server addresses a connection
and split screen puts several players on one. The server keeps a watcher list per
computer and answers every open window with the new screen under its own token.

#### Scripts: the step machine, the job, the scheduler

The language lives in two files and neither of them knows there is a game.

`CeroSecOSScript.lua` is the parser. `CeroSecOS.parseScript(text)` returns a
*program*: nested plain tables of strings, numbers and booleans, with no function
anywhere in it. Parsing happens **once**, before a job exists, so a script with a
missing `done` never costs a tick — and what comes out is inert. There is no `load`,
no `loadstring`, no `setfenv` and no metatable; the arithmetic in `$(( ))` is read
digit by digit by a recursive-descent reader in the VM. Nothing a player types is
ever evaluated as Lua, and `tests/kahlua-check.sh` greps for it.

`CeroSecOSVM.lua` is the stepper:

    CeroSecOS.jobStep(state, job, env, budget) -> status, stepsSpent

`status` is `"running"`, `"waiting"`, `"sleeping"`, `"done"`, `"killed"` or
`"error"`. It runs up to `budget` steps and returns; it never loops to the end and
never waits. A **job** is a plain serializable table — a program, a stack of frames,
its variables, its pending output, a session of its own — and holds no function at
all, which is what makes it inspectable by `ps` and impossible to hide anything
executable inside:

    { id = 42, n = 1, name = "backup.sh", cmd = "sh backup.sh", bg = false,
      prog = <program>, frames = { {k="block", prog=..., i=3}, ... },
      vars = { x = "1" }, nvars = 1, args = { "one", "two" },
      caps = { }, out = { "line" }, partial = "", status = 0, steps = 412,
      state = "running", blocked = nil, depth = 1, line = 7, debt = 0,
      cpuSince = 1723..., wakeMs = nil, ask = nil, cont = nil,
      session = { user = "admin", cwd = "/home/admin", ... } }

A step is a unit of **cost**, not of syntax: one for anything the shell answers
itself (an assignment, an `echo`, a `test`, a loop iteration boundary), and
`CeroSecOS.STEP_COST_COMMAND` (32) for a command that goes out to `/bin` — measured
between 20 and 500 microseconds a call against about 6 for a builtin, so a flat step
would have been a budget eighty times out on a loop of `ls`. The steps of what
`$(...)` runs are charged to the job that asked. A pass may overspend by at most one
command, since a command's price is only known once it has been paid; the overspend
is carried as a `debt` and taken off the next pass, so the average is exactly the
budget.

Every wait is a continuation. `read` and a command's own question (`sudo`,
`passwd`) both leave the job `"waiting"` — the console puts the question up with an
ordinary prompt token `{ cmd = "job", id = 42 }` and the answer comes back through
`CeroSecOS.jobInput`. `sleep` leaves it `"sleeping"` against `env.nowMs` and costs
nothing until it comes round.

`SCeroSecJobs.lua` is the scheduler and the only half that knows there is a server.
Ten passes a second on `Events.OnTick` gated by `getTimestampMs()` — vanilla's own
way of getting under a minute (`forageServer.lua:502`) — with
`CeroSec.STEP_BUDGET_PER_TICK` (200) steps to hand out across every machine that has
a job, no machine taking more than `CeroSec.STEP_BUDGET_PER_MACHINE` (100), and
machines served round-robin from one further along each pass. A starved job runs
slower; nothing is ever refused a turn. Output drains at `CeroSec.JOB_OUT_PER_SEC`
(20) lines a second **per machine**, and a job whose queue is full simply does not
run until the screen has taken what it wrote. A job that holds the processor with no
wait in it for `CeroSec.JOB_CPU_LIMIT_S` (300 s) is killed with `killed: cpu limit`
— a constant with a comment, not a sandbox option, because a server owner who wants
a different number should be given a setting rather than asked to edit a file.

`luaObject.jobs` is **runtime state and is deliberately not in the saved keys**: a
reload forgets jobs, `CeroSec.repairConsole` drops the console's note of a
foreground one, and a machine that comes back from a save comes back at its prompt.
Reboot, shutdown, a room that lost its power and a computer picked up all kill
everything.

The measured cost of a pass, headless under `lua5.1`, is printed by
`tests/hostile_test.lua` on every run: about 0.6 ms for one machine spinning on
arithmetic and 1.2 ms for six, against a 60-frames-a-second budget of 16.7. The
game's Lua is not this one — Kahlua is an interpreter written in Java and is
expected to be several times slower — which is why the county's budget is a fifth of
what the measurement alone would allow.

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

#### Owners, groups and the mode

A node is `{ type, owner, group, mode, ... }`. `group` is a plain string and it is
**optional**: every node of every machine saved before `SYSTEM_VERSION` 5 has none,
`validate` accepts that and refuses a `group` that is not a string, and
`CeroSecOS.groupOf(node)` reads a missing one as the node's `owner` — nothing
anywhere reads `node.group` off the field. `newFile` and `newDir` set it to the
owner's own name, which is that account's primary group, so a fresh file starts
shared with nobody. `chown` moves the owner and leaves the group; `chgrp` moves the
group and leaves the owner; `cp` gives the copy the caller's name for both.

`CeroSecOS.can(state, session, node, what)` is the only place a permission is
decided, and it reads exactly one digit:

1. `root` bypasses everything, before anything else is asked.
2. `node.owner == session.user` — the **first** digit, and the other two are never
   consulted for him even if he is also in the group.
3. `CeroSecOS.inGroup(state, user, CeroSecOS.groupOf(node))` — the **middle** digit.
4. Otherwise the **last** digit.

`inGroup` is true for three things and no others: the primary group (`user ==
group`), a line in `/etc/group` naming the user, and — for the group `sudo` alone —
a line in `/etc/sudoers`. It takes `state` because those two files are the answer,
and it tolerates a `nil` state (a machine with no files parses to no groups, which
leaves the primary groups working).

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

#### /dev, and the world outside the machine

The engine knows nothing about Project Zomboid, devices included. A device node
lives under `/dev` and is not a file:

```lua
{ type = "dev", owner = "root", group = "sudo", mode = 660,
  id = "light0", kind = "light", desc = "office", side = "N",
  state = "on" }
```

It has no `data`, it costs nothing in `CeroSecOS.usage` (so `df` does not move
because somebody walked past a light switch), and **it is never persisted**.
`CeroSecOS.mountDev` builds `/dev`'s children from `env.devices.list()` at the
top of `exec` and `continue`, and `CeroSecOS.unmountDev` takes them away again
before the answer goes back — so the state the game saves has the same empty
`/dev` it has had since rung 1, and `validate` never sees a node type it does not
know. `SCeroSecObject:osState` sweeps once more before the gate, as the belt to
that pair of braces: a command that died in the middle must not turn a working
machine into a broken one.

`env.devices`, when the caller supplies one, is three functions:

| call | answers | who owns it |
| --- | --- | --- |
| `list()` | array of `{ id, kind, desc, side, state, mode, dead }` | the caller |
| `write(id, value)` | `ok, reason, state` | the caller |
| `chmod(id, mode)` | — | the caller, optional |

The **ids are the caller's**, not the engine's: the engine renders what it is
handed and judges `value` against `CeroSecOS.DEV_VALUES[kind]`, so a word a kind
has no meaning for never reaches the world. An entry marked `dead` is mounted but
never listed, which is what makes `cat /dev/lock0` say `no such device` instead of
`no such file`. `chmod` is how a mode outlives the command it was typed in, since
the node itself is gone by the end of one.

Device I/O refusals read `<id>: <reason>`; filesystem refusals *about* a device
node keep the filesystem's grammar (`rm: /dev/light0: is a device`,
`mkdir` and `touch` under `/dev` answer `/dev: read-only`). The listing is
alphabetical, like every other listing on this machine.

**Discovery** is `SCeroSecDevices.find(x, y, z)`, run afresh at every command,
because the answer is only true for the moment it is asked:

- The square's `getBuilding()`, when it has one → `getDef():getRooms()`
  (an `ArrayList<RoomDef>`, read the way `shared/Util/BuildingHelper.lua` reads
  it) → `getIsoRoom()` per room — `nil` while its chunks are not loaded — →
  `getSquares()` → `getObjects()`.
- No building → `getCell():getGridSquare()` over ±`CeroSecDevices.RADIUS` (10) on
  the same z. A `nil` square is an unloaded chunk and is skipped.

Classification is `instanceof`: `IsoLightSwitch` → `light`, `IsoDoor` → `lock`,
`IsoWindow` → `win`, `IsoThumpable` with `isDoor()` → `lock` (`built`). A
player-built window frame is not a device this rung.

**The numbering** is stable for the life of the machine. Candidates are sorted by
`(kind, x, y, z, side)` and each gets the smallest number its kind has never used;
the answer is written into the machine's own state at `os.devmap`, keyed by where
the device is:

```lua
state.devmap["light:1024:998:0::0"] = { id = "light0", kind = "light", n = 0, mode = 660 }
```

The trailing `0` is an ordinal that tells two devices of one kind facing the same
way on one square apart — the object index would have done it and is not stable
across a reload. An entry is **never removed**: the number is spent, so a device
that is torn out leaves a gap and nothing is renumbered under a script. The book
is capped at `CeroSecDevices.MAP_MAX` (128) so a computer carried across the map
does not grow one entry per light switch in the county.

**The sync calls**, and why these ones. Every one is verified with `javap` against
`projectzomboid.jar` (42.20.4). The point that matters is *who broadcasts*: our
writes happen on the server and most of vanilla's happen on a client, so a setter
that syncs for a player does not necessarily sync for us.

| kind | setter | sync | why |
| --- | --- | --- | --- |
| `light` | `IsoLightSwitch:setActive(on)` | none needed | `setActive(Z)` → `setActive(Z,Z,Z)`, which ends on `syncIsoObject(false, activated, null)`; that method's server branch walks `GameServer.udpEngine.connections` |
| `lock` (map) | `IsoDoor:setLockedByKey(locked)` | `syncIsoObject(false, 0, nil, nil)` | `setLockedByKey(Z,Z)` **skips** its own sync when `GameServer.server` is true; the pair is vanilla's own, `shared/TimedActions/ISLockDoor.lua:52-56` |
| `win` | `IsoWindow:setIsLocked(locked)` | `syncIsoObject(false, 0, nil, nil)` | `setIsLocked` is a bare field write with no sync at all; `IsoWindow:syncIsoObjectSend` writes `locked` into the packet |
| `lock` (built, padlock) | `IsoThumpable:setLockedByPadlock(locked)` | none needed | it calls `syncIsoThumpable()` itself, whose server branch is `INetworkPacket.sendToRelative(SyncThumpable, ...)` |
| `lock` (built, key) | `IsoThumpable:setLockedByKey(locked)` | `syncIsoThumpable()` | same server skip as the map door's |

The power rule for a light is the switch's own: `canSwitchLight()` — a bulb, and
electricity or a charged battery. A switch with no bulb reads as `no power` too,
which is what a survivor flicking it would find. `setActive` also *answers* with
the state it settled on, so the state is read back rather than assumed; the same
goes for every kind, because "the order went out" and "the world moved" are not
the same fact.

The one-minute sweep (`CeroSecDevices.refresh`) renumbers for a machine somebody
is standing at. Nothing already on the glass changes — a printed line stays
printed, here as on any terminal — but a device that appeared since already has
its number by the time `ls /dev` is typed.

### System files, and their formats

A machine is a filesystem and nothing else. What makes it a machine that can be
*used* is what is in that filesystem, and each of these files is the truth about
what it holds — there is no table of users beside `/etc/passwd`, no list of commands
beside `/bin`, no list of sudoers beside `/etc/sudoers` and no table of groups
beside `/etc/group`. Root editing one of them
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

**`/etc/group`** — the groups, owner `root`, mode `644`, one a line:

    name:member,member,...

Parsing is as strict and as silent as the other two: a line is skipped when it is
not exactly one colon, a valid name in front of it, and behind it a possibly empty
list of valid names separated by commas — so `crew:admin,` and `crew:,admin` are
both dropped whole rather than half read. Blank lines and lines whose first
non-blank character is `#` are comments, a name that appears twice keeps its
**first** line, and the same one-slot cache keyed on the node and its text applies.
A machine ships with `root:`, `sudo:admin` and `users:admin`.

Every account is additionally in a **primary group of its own name**, with no line
anywhere: `bob` is in group `bob` whether `/etc/group` mentions him or not, and
`adduser` writes nothing here. That is what `chgrp bob <path>` takes, and it is
also why `groupdel bob` and `gpasswd -a bob bob` both answer `no such group` —
there is no line to remove and none to add anybody to.

`groupadd` appends, `groupdel` drops every line naming the group, and `gpasswd`
rewrites the first line naming it; every other line is kept exactly as it lies,
comments included. All three go through the ordinary `setData`. A group name obeys
`CeroSecOS.isValidUserName` — the two share a namespace, so a group nobody could
ever have as a primary group would be a trap. `root`, `sudo` and `users`
(`CeroSecOS.GROUP_KEEP`) cannot be deleted; anything else can, and files still
carrying the name keep it, dangling, which is what `ls -l` shows.

The `sudo` group is the one place two files meet. `/etc/sudoers` remains the
authority on who may run a command as root; `CeroSecOS.inGroup(state, user,
"sudo")` answers true for a name in *either* file, so `id` and `groups` show it and
the `660` on a device means what its comment always claimed. Membership of the
group grants no `sudo`: only `/etc/sudoers` does that.

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
creates `/etc/hostname` and `/etc/motd` only if missing, replaces `/etc/passwd`,
`/etc/sudoers` and `/etc/group` only if missing, not a file, or parsing to nothing
at all, makes
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
next load rather than making anyone go through the BIOS for it. The same is true of
`/etc/group`: `SYSTEM_VERSION` 5 seeds it, and the five group commands, into an
older machine. Nodes saved before that rung carry **no** `group` field at all and
are left exactly as they are — `CeroSecOS.groupOf` reads a missing one as the
node's owner, so nothing has to walk the disk. `validate` accepts a missing
`group` and refuses one that is not a string.

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

The state also carries `sysv`, the *contents* it was built with (8 today) as
opposed to `v`, the schema. A wave that adds a command adds a file to `/bin`, so
on load `CeroSecOS.upgradeSystem` tops a machine behind on that number up — the
standard executables that are missing, and `/etc/sudoers` when there is nothing at
that name — and then moves the number up. At the current number it does nothing at
all, which is what keeps root's `rm /bin/ls` a deletion and not a suggestion.
`SYSTEM_VERSION` 8 seeds `/bin/halt` and the six the engine runs itself but still
looks up first — `/bin/sleep`, `/bin/printf`, `/bin/test`, `/bin/[`, `/bin/true`,
`/bin/false` (`/bin/echo` was already there). `/bin/[` is the one filename on this
machine that is punctuation, which is why the disk has
`CeroSecOS.isValidFileName` beside `isValidName`: it allows exactly that one extra
name and nothing else, and an account or a group is still `isValidName`'s.

`~/.sh_history` is the one file exempt from the 32 KB disk quota, and the exemption
is decided by the **path** at the moment the disk is counted — never by anything
carried on the node. `CeroSecOS.exemptPaths` builds it from `/etc/passwd`: exactly
`<home>/.sh_history` for each account it names, plus `/root/.sh_history`, and owned by
that account. `CeroSecOS.usage` sums everything else; `CeroSecOS.exemptUsage` sums
only those paths, capped at `CeroSecOS.HISTORY_BYTES` (16 KB) per file and
`CeroSecOS.MAX_EXEMPT_BYTES` (four of those) per machine, with anything past either
counted against the disk like anybody's bytes. So `df` does not move because
somebody typed, and a **renamed** history is an ordinary file from the moment it is
renamed: it counts at once, and renaming it back makes it exempt again. There was a
flag (`nq`) before rung 5a.1 and it rode the rename, which let up to 64 KB hide from
`df`; `CeroSecOS.migrate` strips the field off every node on the way in. The
machine-wide ceiling is also paid at the **write**, in `historyAppend`, so a machine
with accounts enough cannot write history no `df` on it mentions. `cp` of a history
is an ordinary copy and meets the ordinary 4096-byte ceiling.

Being **over** the quota is a state a machine can be in: renaming a full history puts
it there, nothing is ever deleted to make room, and every further write answers `disk
full` until room is made (a shorter line written over a longer one still goes in —
that is room being made). `CeroSecOS.validate` says nothing about the 32 KB for that
reason: over quota is a runtime refusal, not a corrupt save to be thrown away. The
one ceiling it does hold a file to is `HISTORY_BYTES`, the biggest a file can *be* —
bigger than the 4096 a write may produce, because a renamed history is exactly that.
Homes are never touched by `restoreSystem`, so the BIOS repair never takes a history
or a `~/.profile` away.

The pending `shutdown` (`luaObject.shutdown`) is **not** among the saved keys and is
not meant to be: it is an order given to a running machine, driven by
`CeroSecJobs.checkShutdown` on each scheduler pass, and a reload forgets it. The
machine stays up and the README, the manual and `docs/PARCOURS-TEST.md` all say so
rather than letting a player discover it by the machine not going down.

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

### The manual

The book is three pieces and a text file, and the text file is deliberately the
only one of them anybody has to touch to write another edition.

**The text** is `42/media/lua/shared/CeroSec/CeroSecManual.lua`, one global table:

    CeroSecManual = {
      title = nil,             -- stamped, see below
      edition = "...",
      chapters = {
        { title = "...", pages = { "plain text\nwith paragraphs", ... } },
        ...
      },
    }

The **title is not written here**. It names the version of the OS the book is
for, and that number has exactly one home — `CeroSecOS.VERSION` — so the cover is
built from it by `CeroSecManual.stampVersion()` at the bottom of the same file.
It cannot be a plain concatenation in the table: the game sorts
`shared/cerosec/cerosecmanual.lua` ahead of `shared/cerosec/os/cerosecos.lua`
(the load list is every relative path, lowercased, sorted case-insensitively),
so the core is not loaded yet when the table is built. `CeroSecManualUI.text()`
stamps it at the last moment before the layout reads it, and running the stamp
twice changes nothing.

ASCII only. `\n` is a paragraph break. **An authored page is a page**: the writer
decides where a page ends and the layout honours it, so pages want to be about 900
characters. A line that starts with **two spaces** is an example: it is drawn in the
terminal's own `UIFont.Code`, on a faint band, and it is never wrapped and never
trimmed, because a shell line broken across two rows is a shell line the player will
mistype. Keep those under about 62 columns and they will always fit a leaf.

The manual is read through `CeroSecManualUI.text()` and never cached, so a reload of
the text file is a reload of every open book. A missing or half-written table is an
empty book — a title leaf and a contents that lists nothing — and never an error.

**The layout** is `shared/CeroSec/CeroSecManualBook.lua`, and it makes no game call
at all: `CeroSecManualBook.open(manual, { width, rows, measure })` hands back a flat
list of leaves, and `measure` is a function the caller supplies. That is what lets
`tests/manual_ui_test.lua` lay the same book out against a font of a known width. It
wraps by words, breaks a word wider than the leaf rather than draw it off the paper,
gives every chapter a leaf of its own, spills an authored page that does not fit onto
a continuation leaf rather than cut it off, and pads the book to an even number of
leaves so the reader is never shown half a spread.

**The window** is `client/CeroSec/CeroSecManualUI.lua`, an `ISCollapsableWindow`.
Vanilla ships no serif — `media/fonts/EN/fonts.txt` maps every readable face to
zomboidSmall/Medium/Large — so the body is `UIFont.NewMedium`, which is what
vanilla reads its *own* book in (`SurvivalGuide.lua:3-4,47`), and examples are
`UIFont.Code`. Left, Right and Escape reach it through `setWantKeyEvents(true)` and
`isKeyConsumed`, the pattern `ISVehicleAnimalUI` uses. The bookmark is
`item:getModData().page`, always the **left** leaf of the sheet, and a number read
back off it goes through `CeroSecManualBook.clampPage` first — a manual rewritten
between two saves must not open an empty leaf. It is a client-side bookmark and is
not transmitted: it is where a reader left off, not machine state.

**The menu** is `client/CeroSec/CeroSecManualMenu.lua`, on
`Events.OnFillInventoryObjectContextMenu` — the event vanilla put there for exactly
this (`ISInventoryPaneContextMenu.lua:933-935`). It unpacks both shapes the event
hands over: an `InventoryItem`, and a stack of identical ones which arrives as a
table with an `items` array inside it.

**The testing door.** `CeroSec.DEV_MANUAL_MENU` in `CeroSecDefs.lua` is a
**temporary testing aid and has to be set to `false` before the Workshop release.**
While it is on, every computer — lit or dark, in reach or not — carries a last entry
on its right-click menu, **Read the CeroSec manual (dev)**, that opens the reader
there and then with no copy of the book anywhere. It exists so the reader can be
worked on without first going shopping for the item, and it is a door into a piece
of documentation a player is supposed to *find*. It is added by
`CeroSecContextMenu.addDevManual`, always last, and it asks nothing of the computer
— not its power, not its height, not whether anybody can stand in front of it —
because it is not really about the computer at all. A book opened that way has no
item to write a bookmark on, so it keeps its own on the module
(`CeroSecManualUI.devPage`): session-lived, never saved, and never the same
bookmark as a copy's. Off, nothing at all is added.

**The item** is `common/media/scripts/items_cerosec.txt`, `CeroSec.Manual`. It is
`ItemType = base:normal` and **not** `base:literature`, on purpose: a literature item
that cannot be written on is one the vanilla menu offers to *read*, and vanilla's
read is a timed action that sits the character down for hours. It keeps
`DisplayCategory = Literature`, which is a free string the inventory prints through
`getText("IGUI_ItemCat_" .. …)`, so it still files itself with the books. `Icon =
CeroSecManual` resolves to `common/media/textures/Item_CeroSecManual.png`: the game
builds `"Item_" .. Icon` and looks it up as `media/textures/<that>.png`.

**The loot** is `server/CeroSec/CeroSecManualLoot.lua`. Twelve vanilla lists, each
weight set against what is already *in* that list, appended in place on
`Events.OnPreDistributionMerge`:

| list | ours | measured against |
| --- | --- | --- |
| `LibraryComputer` | 4 | `Book_Computer` 20/10, `Paperback_Computer` 20/20/10/10 |
| `UniversityLibraryComputer` | 4 | `Book_Computer` 50/20/20/10/10 |
| `BookstoreComputer` | 4 | `Book_Computer` 20/10, `Magazine_Tech_New` 20/10 |
| `CyberCafeFilingCabinet` | 4 | `Book_Computer` 10, `Paperback_Computer` 20 |
| `CyberCafeDesk` | 3 | `Book_Computer` 4, `Paperback_Computer` 8 |
| `ControlRoomCounter` | 3 | `Book_Computer` 4, `Paperback_Computer` 8 |
| `UniversityDesk_Computer` | 4 | `Book_Computer` 50/20, `Magazine_Tech` 50/50/20/20 |
| `ElectronicStoreMagazines` | 4 | `BookElectrician4` 4, `ElectronicsMag1-5` 8 each |
| `OfficeDesk` | 1 | `Book_Business` 1, `Paperback_Fiction` 1 |
| `OfficeShelfSupplies` | 1 | `BusinessCard` 1, `PaperclipBox` 1 |
| `CrateBooks` | 1 | `Book_Computer` 1, `Paperback_Computer` 1 |
| `LivingRoomShelf` | 0.1 | `BookElectrician1` 0.1 |

Note the two distribution tables are not the same thing. `Distributions` is the room
and container map, and it is the one `mergeDistributions` merges
(`SuburbsDistributions.lua:136-149`); `ProceduralDistributions.list` is the item
pools, and nothing merges it — the Java side reads it as it stands. So a pool is
extended by appending to it, in place, which is what this does. Adding a list is a
line in `CeroSecManualLoot.WEIGHTS`; a list vanilla later renames is logged by name
and skipped rather than taking the mod down.

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
- **Three version numbers, three homes, and no in-world string carries a
  fourth.** The operating system's is `CeroSecOS.VERSION` (`shared/CeroSec/OS/
  CeroSecOS.lua`) and everything a player reads that names it — the greeting the
  boot ends on and a login is met with (`CeroSecOS.MOTD`, the built-in
  `/etc/motd`), the manual's cover — is built from it. The firmware's is
  `CeroSec.BIOS_VERSION` (`shared/CeroSec/CeroSecDefs.lua`), a separate component
  with a separate number, printed by `CeroSec.BOOT_LINES[1]`. The mod's own
  release version is `modversion` in `42/mod.info` and never appears in the
  world at all. `tests/manual_test.lua` refuses a page that names an OS version
  of its own.

## Testing

`sh tests/run.sh` runs every headless suite in order and needs `lua5.1`:

- `defs_test.lua` — the shared definitions (sprites, facings, state).
- `os_test.lua` — the OS core: filesystem, permissions, users, shell, passwords.
- `terminal_test.lua` — the pure parts of the terminal: hostname, console, history.
- `window_test.lua` — the window wired to the machine end to end: type a line, get
  an answer on the glass, and a script's output, question and `^C` through it.
- `hostile_test.lua` — the one that matters to a server owner: an endless loop, a
  script that runs itself, a doubling string, an output flood, a hundred background
  jobs and a substitution bomb, each driven through the real scheduler for a
  thousand passes, asserting a flat cost per pass, a bounded console, bounded
  memory and the cpu ceiling firing where it should. It prints the numbers.
- `manual_ui_test.lua` — the manual: wrapping against a proportional font,
  pagination, the contents page, turning the leaves, the bookmark on the item, the
  keys the item script sets, and the twelve loot lists.
- `selfcalls-check.sh` — every `self:method()` called is defined somewhere, since
  Lua only resolves a method when it is called and a missing one is a silent nil
  call, not a syntax error.
- `kahlua-check.sh` — `luac5.1 -p` on every shipped file, plus a grep of the OS core
  for constructs the game's Kahlua cannot run.

What no headless test can reach — the sprite, the context menu, sitting down, the
glow, what is actually on screen — is covered by the manual checklists in `docs/`:
`TEST-rung1.md` (turning a computer on and off), `TEST-rung2.md` (the terminal,
login and the shell) and `TEST-rung4.md` (the manual: the item, the icon, the
reader, and finding one in the world).

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
