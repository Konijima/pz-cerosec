# CeroSec — Player's Guide

Everything a survivor needs to run a CeroSec computer from inside the game: logging
in, sharing files, the devices it can reach, the phone and the radio, floppy disks,
and where to find the in-game manual. For the engine and server internals behind
each of these, see [ARCHITECTURE.md](ARCHITECTURE.md), [DEVICES.md](DEVICES.md) and
[NETWORK.md](NETWORK.md). For the shell scripting language, see
[SCRIPTING.md](SCRIPTING.md).

See also: [../README.md](../README.md) for install and status.

Right-click a desktop computer (the beige `Desktop` tile) and choose **Turn on
computer**. It needs power in the room; if there is none, the option is greyed out.
Once it is on, right-click again for **Use computer**: the character walks to the
front of the machine, sits down if there is a chair pulled up to it, and the
terminal opens.

At the `login:` prompt, **it depends whose machine it is**. A machine **nobody ever
set up** — one you built, or any computer at all with **Prefilled machines and disks**
turned off — ships with two accounts, both with an empty password, so just press
Enter when asked:

| user | password |
| --- | --- |
| `admin` | (empty) |
| `root` | (empty) |

On **somebody's** machine there is no `admin` at all: the accounts are the people who
worked there, and the name and the password are on a paper in a desk drawer or in a
dead man's pocket. See *[What you may find](#what-you-may-find)*.

**What the machine says, and when.** Over the `login:` prompt it prints
`/etc/issue`, which names the system and the machine — a bank and an army post put
their "authorized use only" there, where somebody who is not in yet reads it. Once
the password is right, `login` prints three things in order: `Last login: Jul  8
14:32 on console` (or `from <machine>` for a session that came in over the wire, and
nothing at all the first time an account is used), then `/etc/motd`, then
`You have mail.` if there is anything in `/var/mail/<you>`. `touch ~/.hushlogin` and
a login says none of the three; delete the file and it all comes back. Either file
emptied is a machine that greets nobody there, which is a choice and not damage.

**Accounts.** A machine nobody set up ships with those two and root can make more:
`sudo useradd bob` writes the account, makes `/home/bob` for it and says out loud
that it has no password yet — set one with `passwd bob` before somebody else does.
`sudo useradd -G wheel bob` makes him an **administrator**, and that means one
thing: he is in the group `wheel`, which the shipped `/etc/sudoers` grants with a
`%wheel` line, so he may `sudo`. The `admin` flag on his `/etc/passwd` line is
written from that membership and grants nothing by itself — its one visible effect
is the `#` on the prompt instead of the `$`. `id bob` says what the machine knows
about a name, and
`sudo userdel bob` takes it away again (`-r` takes his home directory with it;
without it his files stay, still owned by a name the machine no longer knows).

`su bob` becomes somebody else at the same glass: it asks for **his** password
(root is asked for nobody's), the prompt changes, and `exit` comes back to who you
were instead of logging out — up to four deep. Walk away and come back and the
machine is still where you left it, four users deep if that is where you left it.
`sudo su bob` is the same switch without knowing his password (`sudo su` is root's),
because root is asked for nobody's.

**Sharing a file.** A mode is three digits — you, your group, everybody else — and
the machine reads exactly one of them: the first if you own the file, the second if
you are in its group, the third otherwise. Root walks through all three, except
for running something: a file with no `x` bit at all is one root may not execute
either, which is why `chmod 600 /bin/ls` takes `ls` away from root as well. Every
account is already in a group of its own name, so a fresh file is shared with
nobody until you say otherwise:

```
sudo groupadd crew
sudo usermod -G crew bob
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
| `ls [-1laACF] [path]` | list a directory; columns when a person is reading, one name per line when anything else is (a pipe, a `$( )`, a file), `-1` and `-C` force either; `-l` adds owner, group, size and date, `-F` marks directories with `/` and links with `@`, `-a` shows hidden names plus `.` and `..`, `-A` shows hidden names without them |
| `cd [dir]` | change directory (home if no argument) |
| `pwd` | print the working directory |
| `cat <file>...` | print a file |
| `edit <file>` | open the file in the editor |
| `touch <file>` | create an empty file, or move an existing one's date to now |
| `mkdir <dir>` | create a directory |
| `rm [-r] <path>` | remove a file, or a directory tree with `-r` |
| `mv <src> <dst>` | move or rename; a destination that exists is replaced (the directory's `w`, not the destination's mode, is what decides), an existing directory is moved *into*, and one that is not empty answers `directory not empty` |
| `ln -s <target> <name>` | make a symbolic link; there are no hard links here, so the `-s` is not optional — `ln a b` answers `ln: usage: ln -s <target> <name>` and makes nothing. It is a **declared deviation**: a 1993 `ln` with no flag made a second name for one file |
| `cp [-r] <src> <dst>` | copy a file, or a whole tree with `-r` |
| `chmod <mode> <path>` | set permissions: three octal digits, or letters applied to the mode it already wears — `u+x`, `go-w`, `a=r`, `ug+rw,o-rwx` |
| `chown <user> <path>` | change the owner |
| `chgrp <group> <path>` | change the group (owner or root; the group must exist) |
| `whoami` | print the logged-in user |
| `id [name]` | `uid=<name> flag=admin\|user groups=<its groups, comma-separated>` |
| `groups [name]` | the same list, blank-separated |
| `groupadd <name>` | make a group (root only) |
| `groupdel <name>` | remove one (root only); `root`, `wheel`, `sudo` and `users` cannot go |
| `usermod -G group[,group...] login` | **set** an account's supplementary groups, replacing the list (root only); it will not take an empty one |
| `su [name]` | become another user (`root` by default); `exit` comes back |
| `useradd [-G group[,group...]] login` | make an account with an empty password (root only); `-G wheel` makes it an administrator |
| `userdel [-r] login` | remove an account (root only); `-r` removes its home directory too, and either way its name is swept out of `/etc/sudoers` and every group |
| `hostname` | print the machine's name |
| `passwd [user]` | change a password (root may change anyone's) |
| `mkpasswd <text> [salt]` | show what a password would hash to (CeroSec Systems' own — no 1993 Unix had this) |
| `grep [-cinv] [-e pattern] [pattern] <file>...` | find a **basic regular expression** in files (`-i` ignores case, `-n` numbers the lines, `-v` keeps the lines that do *not* match, `-c` prints how many instead of which, `-e` gives the pattern as an option-argument — the only spelling for one starting with a dash — and twice means either of two). POSIX.2's BRE cut to six pieces: `^` and `$` where they anchor (first and last), `.` for one character, `*` for any number of the piece in front of it, `[abc]`/`[a-z]` and `[^abc]` for a set, and `\` to take the meaning off any of them. **Not** here: `\( \)` and `\{m,n\}`. A pattern of more than 32 pieces is `expression too long`, an unclosed set is `unmatched [`, a reversed range is `bad range`. A literal pattern is a C call whatever the file; a pattern with a piece in it is a walk of every byte for every piece, and grep charges the job for that walk in steps (see "Design rules") |
| `head [-n N\|-N] <file>` | the first N lines, 10 by default; `head -1` is the older spelling and works |
| `tail [-n N\|-N] <file>` | the last N lines, 10 by default; `tail -5` likewise |
| `wc [-clw] <file>...` | lines, words and bytes — or whichever of the three `-l`, `-w` and `-c` ask for, always printed in that order, with a `total` row for several files |
| `more [file]...` | a pager: one screenful, then `--More--(NN%)`; **Space** is the next screenful, **Return** one more line, **q** quits. Works as the *last* stage of a pipe (`ls -l \| more`). Where its output is not a screen — a redirect, a `$( )`, a stage that is not the last — it copies through and pages nothing, which is what `more(1)` itself does; where the output *is* a screen but nobody is there (a `&` job, a crontab line) it answers `more: not a terminal`. One deviation, and it is the console's: this machine reads a *line*, so Space is a space and then Enter |
| `find <path>... [expression]` | walk a tree depth-first, one path a line, the directory before what is in it. The expression is `-name <glob>` (matches the **last component**, with `*`, `?` and `[…]`; a leading `!` or `^` negates a set), `-type f\|d`, `-print` (implied when no action is named, as POSIX says, and accepted anyway) and `-exec`. Both tests together must both be true. A link is a leaf: find does not follow one. A directory it may not read is named and not entered, and the walk goes on **unsuccessfully** — so `find / \| wc -l` as an ordinary account prints the paths instead of counting them, exactly as `cat good bad \| wc -l` does |
| `find … -exec <cmd> {} \;` | run the command once for every name found, in find's own order, with `{}` replaced by the name — POSIX's rule: only an argument that is *exactly* `{}`. The `\;` is the shell being told to leave the semicolon alone. Naming an action takes the implied `-print` away; an explicit `-print` prints where you wrote it. The expression is AND-ed, so `-exec test -f {} \; -exec rm {} \;` runs the second only where the first was true. find does **one exec per turn** and hands the machine back, so a sweep of a hundred names takes a few seconds of game time and prints as it goes — no command on this machine may spend a whole pass |
| `find … -exec <cmd> {} +` | the same, with the names gathered into as few commands as it can (64 at a time) — the `{}` must be the last word before the `+`. This is the form for a big sweep: one command instead of a hundred |
| `tee [-a] <file>...` | copy the pipe to the screen **and** into every file named; `-a` adds instead of replacing. It is a filter: it needs a pipe on its left, and it passes the lines on |
| `cut -c <list>` | keep those character positions of every line |
| `cut -d <delim> -f <list>` | keep those fields, split on a one-character delimiter (a TAB by default). A list is `1`, `1,4`, `3-5`, `2-` (to the end) or `-3` (from the first). A line with no delimiter in it comes through **whole**, which is what POSIX says. All three flags take their value **attached** as well as apart, the way `getopt(3)` reads a line: `cut -d: -f1 /etc/passwd` is `cut -d : -f 1 /etc/passwd`, and the rest of the word is the value whatever it looks like (`-f-2` is the list `-2`) |
| `tr [-d] <set1> [<set2>]` | translate characters one for one, or delete them with `-d`. Ranges (`a-z`) only — the `[:alpha:]` classes a bigger Unix has are not here. It reads its standard input and nothing else, like every `tr`, so it wants a pipe |
| `uptime` | ` 3:14PM  up 2 days,  4:03,  2 users,  load 0.12 0.08 0.05` — the clock, how long since power-on, who is logged in, and the run queue averaged over one, five and fifteen minutes. One cut from 4.4BSD's line and it is the 60 columns': BSD writes `load averages: 0.12, 0.08, 0.05`, which does not fit |
| `w` | that line, then `USER TTY FROM LOGIN@ IDLE WHAT` — a row a session, with the line it is running in `WHAT`. `LOGIN@` is the clock and not the weekday, and `IDLE` is `hh:mm` since that session last typed (since it **logged in** for one that came back from a save file, which is the honest floor: there is no keystroke clock here) |
| `date [+FORMAT]` | the date and time, from the game's calendar; with a format, the pieces — `date +%s` is the clock as a plain number |
| `df` | how much of the 64K disk and the 512 nodes are used — and a `fd0` row of its own while a floppy is mounted |
| `tar c\|x\|t[v]f <archive> [path]...` | many files in one file, which is how a home goes onto a floppy: `tar cf /mnt/home.tar ~`. `c` makes an archive, `t` lists what is in one, `x` puts it back, `f` says the next word is the archive, and `v` names every member as it goes — one word of letters with no dash in front, the way tar was called in 1993. No `z`. The names are stored **as you typed them**, so an archive of `/home/admin` puts it back there; a member carries its mode, owner, group, size and time, and **root** is the only account that puts an owner back — anybody else owns what he extracts. The container is **this machine's own** and is declared on the deviations page: a real tar is 512-byte blocks with a header in front of every member, which on a 4096-byte floppy would cost one note a quarter of the disk. It is honest about the price — the archive is an ordinary file, it counts against the disk, and a home bigger than 4096 bytes answers `file too large`. tar takes **one member a turn**, so a big archive takes a few seconds and prints as it goes |
| `newfs <device>` | put a filesystem on the disk in the drive, emptying it: `newfs /dev/fd0` prints `/dev/fd0: 4096 bytes, 32 inodes` |
| `mount` | what is mounted, one line each: `/dev/hda on / type ufs (rw)` |
| `mount <device> <dir>` | graft the disk onto a directory; from then on that directory **is** the disk, and what was under it is covered |
| `umount <dir>` | take it off again — refused with `Device busy` while any session's working directory is inside it |
| `dev [kind\|id [value\|toggle]\|find <id>]` | the devices as a table, one kind of them, one read, one worked, or a whole kind worked — `dev door1 open`, `dev light0 off`, `dev lock1 toggle`, and `dev window close` for every window the machine can reach, one answer line each in the table's order, the line failing if any of them refused (no kind means *everything*: `off` means one thing to a light and another to a generator); `dev find door1` makes it show itself for six seconds; `dev sensor0` reads a motion sensor and no word may be written to one |
| `which <name>` | where a bare name would be found on `PATH`, and nothing at all when it would not |
| `type <name>` | which of the three kinds of word it is: `ls is /bin/ls`, `cd is a shell builtin`, `if is a shell keyword` |
| `man <command>` | what a command does, and how it is spelled |
| `sudo <command...>` | run one command as `root` |
| `shutdown [-h\|-r] now\|+N` | switch the machine off, or reboot it with `-r`; `+N` is N minutes from now and warns every screen at the machine (root only) |
| `kill <id>` | call a pending `+N` off: it is a process, and that is how you stop one |
| `halt` | `shutdown -h now` under its older name (root only) |
| `reboot` | switch it off, wait three seconds, and switch it back on (root only); `shutdown -r now` is the long way |
| `export NAME[=value]...` | put a name in the **environment**, which is the set of variables a program you run is handed. `x=5` is a variable of the shell's own and a script does not see it; `export x` puts it in, and the value follows the name afterwards. With no name at all it lists what is in the environment, one `export NAME=value` a line |
| `env` | the environment as it will be handed over, `NAME=value` a line, sorted. Not the shell's variables: `env` shows what a script of yours can actually see |
| `. <file>` | read the file **in this shell**, so what it sets is still set afterwards — the one way in, because `sh <file>` and `./<file>` run it as a program and a program is handed a copy. It wants `r` on the file and not `x`. This is how `.profile` is read. `source` is csh's and bash's word for it and is not here |
| `at HH:MM` | queue one job for a time you name, reading the commands from a **pipe**: `echo halt \| at 04:00`, `cat plan \| at 23:30`. It answers `job 1 at Fri Jul  9 04:00:00 1993`. A time that has gone by today means tomorrow; `HH:MM` and nothing else (no `now + 1 hour`). The output goes to your **mail**, as a crontab line's does. Unlike cron it does **not** forget: a job queued for four o'clock on a machine that was off at four runs when the machine comes back |
| `mail` | with no name after it, your own mailbox: what cron and `at` left you and what anybody on the machine sent you, shown once and emptied — reading your mail **is** emptying the box, as it always was |
| `wall [file]` | put a line on **every** terminal of this machine -- the glass and every session that came in over the wire -- as `Broadcast Message from <user>@<host>` and, under it, `        (<line>) at hh:mm ...`, a blank line, then the text. 4.4BSD's wording, over two lines because `wall.c` writes it over two (and because one line of it would not fit sixty columns). **Anybody may**: the real one is setgid `tty` and not setuid root, because telling people is not a privilege. The text is a file named on the line or the standard input (a pipe): `echo "lights out in 5" \| wall`. Nothing to say broadcasts nothing, and more than a pipe may hold is `wall: input too large`. `shutdown`'s own warning goes out through the same door |
| `mail` | read what has arrived, and **move** it to `~/mbox` as it shows it -- the spool (`/var/mail/<name>`) is what has arrived and `~/mbox` in your home is what you have read, which is what 4.4BSD Mail does on `q`. `~/mbox` is an ordinary file at mode 600 and costs your drive what any file costs; a drive with no room for it leaves the mail in the spool and says `mail: ~/mbox: file too large`, having shown it to you anyway. `You have mail.` at the login is about the **spool**: it means something has arrived, and a full `~/mbox` says nothing |
| `mail -f` | read `~/mbox` and move nothing, so what you read last week is still readable. Mail's own flag for "a mailbox that is not the spool" |
| `mail [-s subject] user...` | send a message to an account on **this** machine. The body is the standard input: `echo hi \| mail -s Hello bob` from a pipe, or typed at the prompt a line at a time until a line holding a single `.` (Escape gives up and sends nothing). Several names means a copy each. A body with nothing in it is sent anyway, with `Null message body; hope that's ok` — which is what a crontab line's `mail bob` posts, having no keyboard behind it. A name that is no account here answers `bob... User unknown`; an address on another machine (`bob@gate`, `gate!bob`) answers `bob@gate... Cannot send mail: no mailer`, because there is no uucp on this disk. The wire is `cat note \| rsh gate mail -s Hi bob`, which hands the far `mail` what you piped in. What you send costs the **drive**; what cron mails you does not |
| `at -l` / `atq` | what is waiting: the job number and when it is due, yours only (root sees every account's) |
| `at -r <job>...` / `atrm <job>...` | take a waiting job out of the queue. Somebody else's is not yours to remove — root's rule, as `kill`'s is |
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

Which directories a bare name is looked for in is `PATH`, an ordinary shell
variable. A login sets it to `/bin`, sets `HOME` beside it and **exports** both; a
`.profile` widens it (`PATH=$PATH:$HOME/bin`); a script is handed a **copy of the
environment** — the exported names and nothing else the shell was holding — in the
foreground and behind an `&` alike, while every line `cron` runs starts at `/bin`
with `HOME` and nothing else, which is the oldest trap in `cron` and is why a
crontab line spells the whole path. The walk is POSIX's: left to right, the first
file with `x` on it for whoever typed it wins, and something in the way without `x`
does not stop the search — found everywhere and runnable nowhere is
`permission denied`, found nowhere at all is `command not found`. A file found in
`/bin` is the machine's own executable and the engine is behind it; a file found
anywhere else is run as a **script**, so `~/bin` is where an account's own commands
go and a name there shadows one in `/bin` when `PATH` says so. A symlink in `/bin`
is a name for somebody's file, not one of the machine's, so
`ln -s ~/tools/hello /bin/hello` hands everybody with `r+x` on the target a command
called `hello`. A word with a `/` in it is a path and is never looked up.
`PATH` may name eight directories and a ninth is refused where it is set: every
command on the machine walks that string, so its length is a price everybody pays
(see "Design rules"). **Tab** walks the same string, bounded the same way: a name
of your own in `~/bin` is completed once `PATH` names that directory, and not
before — a completion that offered a name the shell would not then find would be a
Tab that lies about what the machine can do.

Two kinds of word are **not** files, and could not be. The reserved words
(`if then elif else fi for while until do done case esac`) are grammar. A **function**
you define (`greet() { echo hi $1; }`) is found before either of the lists below and
before `/bin`, and `type greet` says `greet is a function`; it lasts as long as the
login. The shell's own words
(`. cd export exit fg jobs wait read shift break continue history`) change the shell
itself or own what it started, which no separate program could do — `cd` cannot be a
file in Unix and is not one here, `export` marks the shell's own variables and `.`
reads a file into it. The seven of them that carry a description and a usage line
(`.`, `cd`, `export`, `exit`, `fg`, `jobs`, `wait`) keep both, so `help` lists them
and `man export` answers;
what they do not have is an executable to find, to delete or to `chmod`. `help` is
the one command with a file that is run without it, so that a player who has just
wiped the machine he is standing at can still ask what happened — and `exit`, being a
shell word, is how he walks away. `help` prints the `/bin` table first and those
words under it. Real Unix ships `/bin/pwd`, `/bin/su`, `/bin/kill` and `/bin/echo`,
and so does this machine.

A name beginning with `.` is hidden from `ls` and `ls -l`; `ls -a` shows them with
`.` and `..`, `ls -A` shows them without. Nothing else treats a dotted name as
special — there is no globbing here for one to hide from.

**Links.** `ln -s target name` makes a symbolic link: a node holding the path as it
was typed. Everything that acts on a *file* follows it — `cat`, `cp`, `chmod`, a
redirect — and the permissions are the target's, so a link to something you may not
read buys you nothing. The three that act on the *link* do not — `-l` and `-F` are the two flags that ask
`ls` about the link itself, which is POSIX's rule for both: `ls -l` draws it
(`lrwxrwxrwx  admin  admin   log -> /var/log/cron`) and that arrow is **where you
read what a link points at**, `ls -F` marks it `@`, `rm` takes the link away and
leaves the file, and `mv` moves the link. A link to a name that is not there is allowed and answers
`no such file` on use; a loop of them answers
`too many levels of symbolic links` after eight hops. There are **no hard links**:
two names for one node would be one table under two keys, and the game copies the
state by recursion (`copyTable` on pickup, and the save file), so the second name
would become a second file the first time somebody picked the computer up.

**`/dev/null`** reads as nothing at all and swallows anything written to it, so
`sh nightly.sh > /dev/null` throws output away. It is a device — `rm`, `mv`, `cp`
and `edit` all answer `is a device` — it is mode `666`, and it costs the disk
nothing however much goes into it. Only *output* goes there: this machine has no
`2>`, and errors always reach the glass.

**`/var/tmp`** is the one directory anybody may write in (`drwxrwxrwx`) and the one
where only the owner of a file, or root, may delete it or rename it out again.
Everywhere else a directory you may write is a directory you may delete from; real
machines carry that exception as a fourth mode digit (`1777`) and every mode here is
three digits, so the rule is the **place's** — decided by the path, exactly as the
quota exemptions are.

`edit` turns the screen into a small editor: Tab saves, Esc leaves — and asks
`Save modified buffer? (y/n)` first when there is something unsaved. Those two are
the only keys the game hands a focused text box, which is why they are the two the
key bar names. A file is capped at 4096 bytes and a line at 60 characters; the game's own text
box stops accepting new keystrokes at 2000 characters typed in one sitting, though a
bigger file still opens and still saves.

`passwd` asks for the old password (skipped for root), the new one, and a retype.
Putting text in a file is `echo text > file` — a redirection, the way it has
always been; there is no command that writes a file for you, and `write(1)` on a
real Unix is what puts a line on somebody else's terminal.

`mkpasswd` runs the same hashing the passwords use on any text you give it, so you
can see what a password would look like stored. It is not a Unix command: no 1993
system shipped one, and the manual's *What is not Unix here* page says so.

`sudo` runs one command as `root`. Who may is `/etc/sudoers`, one name a line — or
`%group`, which grants every account in that group — and a fresh machine has
`admin` and `%wheel` on it. It asks for **your own** password first
(`[sudo] password for admin: `), and one wrong answer is
`sudo: authentication failure` — there is no second try, because somebody had to be
standing at the keyboard to type the first. A name that is not in the file gets
`<user> is not in the sudoers file.` The command runs with root's powers and the
working directory you were in; the session at the glass is untouched, so
`whoami` still says `admin` afterwards. A word the shell **is** cannot be run by
it at all — sudo runs a program, and `cd`, `exit`, `jobs`, `read` and the rest have
no file in `/bin` for it to find, so `sudo cd /root` is
`sudo: cd: command not found`, which is sudo's own line about one. Put
`NOPASSWD` after a name in `/etc/sudoers` and that account is never asked.

A redirect on a line that asks waits for the answer with the command:
`sudo cat /etc/passwd > copie.txt` puts the file in the file and nothing on the
glass. What `>` names is **opened** where a shell opens it — before the command
runs — so a password answered wrongly leaves the empty file behind, exactly as a
real one does, and `>>` adds to what is there.

A redirect on a line that runs a **script** belongs to the script, the way a
process's standard output belongs to the process: `sh nightly.sh > log` puts
everything the script prints in `log` and nothing on the glass, `>>` adds to it, and
a script the script runs writes there too. `./nightly.sh`, a script of your own on
`PATH`, and `. nightly.sh` all do the same. What still comes to the screen is a
**refusal** — `ls: /nope: no such file` is not output, here as on any Unix — and a
script whose output fills the file to its 4096 bytes is stopped there with
`sh: log: file too large`.

`shutdown` and `reboot` are the power button typed instead of pressed, and they are
root's alone. `shutdown` turns the machine off: the sprite goes dark, the screen is
gone, and every terminal open on it closes.

`reboot` is a power CYCLE and looks like one. The machine goes off the same way —
the tile goes dark, the glow on the wall goes with it, and every terminal open on it
closes — and about three seconds later it comes back on by itself: the BIOS counts
the memory again and lands at `login:`. If you are still standing at the keyboard
when it comes up, your terminal opens again by itself, in the same place, with no
walk back to the machine; if you wandered off in those three seconds it comes up
without you and you use it by hand like any other lit screen. Two survivors at one
machine both get their window back.

A machine whose room lost its power while it was dark stays dark, exactly as a real
one does after an outage: it does not come back by itself, and somebody switches it
on at the case. What is on the disk survives all of it — a reboot is a power cycle,
not a repair.

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

**A pending order is a process**, which is what BSD's `shutdown(8)` is: it forks,
prints its pid and sleeps until the minute. So it is a job in the ordinary book --
`[1] 44` when it is given, named `shutdown` in `ps`, listed by `jobs`, owned by the
account that gave it -- and you call it off the way you stop any process:

```
root@ksp-04-11:~# jobs
[1] waiting  shutdown -r +5
root@ksp-04-11:~# kill 44
```

`kill` says nothing when it worked, which is `kill`. Root may, and so may the
account that ordered it; anybody else gets
`kill: 44: Operation not permitted`. There is **no `shutdown -c`**: that flag is
sysvinit's, which is Linux and later than this machine. Two orders at once are
allowed, because two processes are -- both warn, and the first minute to arrive
takes the machine down -- and what bounds them is the job book, four to a machine.
`halt` is `shutdown -h now`.

The timer is the scheduler's pass and lives on the machine, not in the window: close
the window, walk away, come back, and it is still counting. It is **not** persisted
— the power going out, the computer being picked up, or leaving the game all forget
it, and the machine stays up. That is deliberate and it is in the manual, and it is
the one job that does not come back from a save: the minute it was waiting for is a
moment on the real clock, and the world stood still while the game was shut. A
program you left running with `&` does come back, because it was waiting on nothing
but its own next turn.

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

The building the computer stands in is wired to it — literally, with a
screwdriver. `/dev` holds one file per door, light switch and window it can reach
**that somebody has fitted a hardware module to** (see below): its own building
when its square has one, every room of it; ten tiles of its own floor when it has
not, which is what a computer in a player-built base gets. `dev` is how you work
them:

```
dev
door0    exterior              0 5S        W  locked
door1    kitchen-hallway       2W 1N       N  closed
door2    built                 4E 9S +1    N  closed
light0   office                0 0            on
light1   hallway               3E 2N          off
lock0    exterior              0 5S        W  locked
lock1    built                 4E 9S +1    N  padlock
win0     office                1E 0        N  locked
```

`door0` and `lock0` are one door twice over: the thing that opens, and the key
that holds it shut. Only a door the lock can actually stop somebody at gets that
second row — in this game a key stops a survivor who is *outside* a building and
nobody who is inside, so exterior doors and player-built doors have a `lockN` and
interior doors do not.

The id you name it by, the rooms it stands between — the map's own raw names,
`exterior` where one side is the outdoors, `built` for something a player put up
— where it is from where the computer stands, which way it faces, and its state.
The offset is the column that tells two devices apart when the room names do
not: tiles east or west, tiles north or south, `0 0` for the computer's own
square, and `+1` / `-1` for a floor that is not this one. The table runs by kind
and then by number,
so `light2` comes before `light10`; in a big building a kind's own name --
`dev door`, `dev light`, `dev curtain` -- cuts it down to that kind. One id reads
that one back, an id and a word
works it and answers with the state read back afterwards, and `toggle` is
whichever of the pair it is not in now:

```
dev light0          -> light0: on
dev light0 off      -> light0: off
dev door1 open      -> door1: open
dev door0 open      -> door0: locked
dev lock1 toggle    -> lock1: unlocked
dev find door1      -> door1: highlighted
```

A door opens with nobody's hand on it: no survivor walks over, nothing is
animated, and everybody on the server sees it swing. The computer is not a key,
though — a locked door answers `door0: locked` and stays shut until its `lockN`
is unlocked.

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
crw-rw----  root  sudo  door0    exterior      W  locked
crw-rw----  root  sudo  light0   office           on
crw-rw----  root  sudo  lock0    exterior      W  locked

cat /dev/light0
echo off > /dev/light0
```

`light`, `stove`, `washer`, `gen`, `tv` and `rx` take `on` and `off`; `lock` and
`win` take `lock` and `unlock`; `door`, `window` and `curtain` take `open` and
`close`; a `tv` or an `rx` takes one thing more, `channel <number>`, which is the
only value on this machine that carries a number. No kind has heard of another's
words, so anything else is `light0: invalid value`. A device answers in its own
name, not the
command's:

| line | what happened |
| --- | --- |
| `light0: no power` | the switch has no electricity, no bulb, or nothing to switch |
| `lock0: no such device` | it was taken away, or it is in a chunk nobody has loaded |
| `win0: smashed` | the glass is gone; there is no lock left to turn |
| `win0: barricaded` | it is boarded up |
| `lock1: no padlock` | a player-built door with neither padlock nor key on it |
| `door0: locked` | held by a key the machine has not got: `unlock` its `lockN` first |
| `door0: barricaded` | planks on it, and no machine takes those off |
| `door0: blocked` | the doorway is not clear: a solid tile, a tree, or a vehicle across it — the game's own test, so a survivor could not open it by hand either |
| `light0: invalid value` | that word means nothing to that kind |
| `light0: permission denied` | the mode says no |
| `win0: cannot toggle` | smashed or barricaded: no opposite for `toggle` to turn it into |
| `sensor0: invalid value` | a sensor takes no word at all: every write to one says this |

`dev`'s own two are a command's and are signed like one: `dev: <word>: unknown
kind` (the kinds are `curtain`, `door`, `floppy`, `gen`, `light`, `lock`,
`radio`, `rx`, `sensor`, `stove`, `tv`, `washer`, `win` and `window`) and
`dev: <id>: no such device`
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
A sensor is born `440` instead, `cr--r-----`, because it is read-only by nature
and the mode says so before anybody tries.
Root may open one up to everybody with `chmod 666 /dev/light0` — that lasts.
The group does not move: `chgrp` on a device answers `is a device`, because only
the mode of one outlives the command it was typed in. Nothing else works on one
either: `rm`, `mv`, `cp` and `edit` all answer `is a device`, and nothing can be
created in `/dev` at all.

Opening a door is not this. `unlock` takes the lock off; somebody still has to
walk over and open it.

### The hardware modules

Nothing is a device because of what it is. It is a device because somebody went
up to it with a screwdriver and a box, and the sandbox option
`CeroSec.HardwareRequired` — **on** by default — is what says so. Nine boxes,
each bought with a level of Electricity and one gesture:

| module | goes on | what the machine gets | level |
| --- | --- | --- | --- |
| `CeroSec.MagneticContact` | a door **or** a window | that `doorN` or `winN`, **read-only** | 1 |
| `CeroSec.Relay` | a light switch | `lightN`, on and off | 1 |
| `CeroSec.ElectricStrike` | a door a lock bites on | `lockN`, lock and unlock | 2 |
| `CeroSec.DoorOperator` | a door, not a garage or a double leaf | `doorN`, open and close | 3 |
| `CeroSec.CurtainMotor` | a curtain, or a door with a sheet over it | `curtainN`, open and close | 2 |
| `CeroSec.WindowOperator` | a window | `windowN`, open and close | 3 |
| `CeroSec.ApplianceSwitch` | an oven, a microwave, a coffee machine, a washer, a dryer | `stoveN` or `washerN`, on and off | 2 |
| `CeroSec.GeneratorSwitch` | a generator | `genN`, on and off, and it reads the tank | 3 |
| `CeroSec.TunerControl` | a television or a radio set | `tvN` or `rxN`, on, off and the channel | 2 |

So a door with only a contact on it is a `doorN` you can `cat` and cannot write:
its mode is `cr--r-----`, everybody but root is stopped by the mode, and root is
stopped by the device — `door1: operation not supported`, which is `write(2)`'s
own `EOPNOTSUPP` in this machine's lower case. Put an operator on that same door
and the same `doorN` opens; add a strike and the `lockN` appears beside it.

**A window is two devices, and they are two boxes.** `winN` is the magnetic
contact and it reads the latch: `smashed`, `barricaded`, `open`, `locked` or
`unlocked`, in that order -- the glass, then the sash, then the catch -- so `open`
beats the latch the way a door's does and `unlocked` means shut. A contact senses
and only senses, so `winN` is read-only, and `dev win0 toggle` answers `win0:
cannot toggle`. `windowN` is the **window operator**, and it moves the sash with a
door's two words, `open` and `close`.

**And a window operator sets off a house alarm.** Opening a window is opening a
window: the motor throws the catch on its way past, and in a house whose alarm was
still armed when the power came back it rings, every time, exactly as a hand
through the glass would. `0 6 * * * echo open > /dev/window0` in a house nobody has
cleared is a horde at six in the morning. Closing one is silent. A boarded window
is refused before the motor turns (`window0: barricaded`), and a sealed one
answers `window0: sealed`.

**Fitting one.** Right-click the fixture itself -- the door, window, light switch,
curtain, oven, washer, generator or set, not the computer -- and take **CeroSec
hardware**. It asks for the module in your bag, a `Base.Screwdriver`, and
Electricity at the module's level, which is the column in the table above: **1**
for a contact or a relay, **2** for a strike, a curtain motor, an appliance switch
or a tuner control, **3** for a door operator, a window operator or a generator
switch. The job is a few seconds,
shorter the better an electrician you are, and pays a little Electricity. Remove
gives the box back whole.

**The menu lists every box that could go on that sort of fixture**, whether you
are carrying one or not, and each line tells you what the box does, which device
it gives and the Electricity it wants. A box you have not got is greyed with *You
are not carrying one* — or, if you have not read the **CeroSec Field Wiring
Guide**, with the line that sends you to it, because a box you have never heard
of is a box you would never go and look for. The only thing left off the list is
a module that could never fit that sort of fixture at all: no curtain motor on a
light switch. Right-click something this mod has nothing to say about and there
is no **CeroSec hardware** entry at all.

Two entries come up greyed with the reason on them, and both are about the
fixture rather than about you: a **strike on an interior door** (a key there
stops nobody, so the lock would be a device that lies) and an **operator on a
garage or double door** (a machine moves one leaf and would leave the rest shut).

**With the door open, and from inside.** A box goes on — and comes off — only
from **inside** the building. Stand on the pavement and every entry is greyed
with *This has to be done from inside*, because otherwise anybody walking past
strips the hardware off your front door without ever coming in. An interior door
has rooms on both sides and is wired from either. A **generator** is the one
exception: it takes its switch outdoors, where a generator belongs.

And the thing has to be at rest — open for what opens, off for what switches on:

| fixture | must be | what the greyed entry says |
| --- | --- | --- |
| a door, a window | open | *Open it first.* |
| a curtain, or a door's own sheet | drawn back | *Draw the curtain back first.* |
| a stove, a washer, a dryer | switched off | *Switch it off first.* |
| a television, a radio set | switched off | *Switch it off first.* |
| a generator | stopped | *Switch it off first.* |
| a light switch | nothing at all | — |

**Remove asks exactly the same**, which is the half the first rule is really
about. A light switch is the one that asks nothing: the plate comes off with the
light burning.

**Somebody else's safehouse.** There is a sandbox option,
**Safehouse members only** (`CeroSec.SafehouseModules`), **off** by default. With
it on, a fixture standing inside a safehouse takes a module — and gives one back
— only for somebody that safehouse allows: its owner, its members, and an admin.
It is there for a server where stripping a rival's hardware out of his own
hallway was the sabotage nobody wanted. A safehouse's own looting rules are not
consulted either way: fitting a module is not looting, and nothing leaves the
building. In single player there are no safehouses, so the option does nothing.

None of this touches a building that was **already wired** before the outbreak:
that hardware is written on at world generation and is not a gesture anybody
made, so a shut door in a safehouse still has its relays on it.

The **number does not move** for any of this. It hangs on where the device is and
which kind it is, so a contact taken off and put back a week later is the same
`doorN` a script wrote down. Only the mode moves — back to what a device of that
shape is born at — because a door that has just grown an operator must not be one
nobody may write to.

**Where they come from.** Found ready-made in an electrician's van, on the shelves
of an electronics shop, in a warehouse crate, a tool shop, a garage and a crate of
tools: a contact is the common one and an operator is eight times rarer, in every
list.

Or **built**, once you have read the book. The recipes are not something an
electrician works out at the bench: they are printed in the **CeroSec Field
Wiring Guide** (`CeroSec.WiringGuide`), a trade magazine with the diagrams and the
parts lists for all nine in it, and the two that take a **Small Motor** out of
something that already has one -- a hair dryer, a pair of sheep shears, a CD player
or a blower fan -- because Knox County never sold a motor on its own. It turns up
where the game's own electronics
magazines turn up, and at the same rates — likeliest on an **electronics shop's
magazine rack**, then a bookshop, a tool shop and an electrician's van, then a
mixed rack, a post office's mail, a warehouse crate of magazines and a library.
Right-click it, **Read**, and the eleven appear in the **Electrical** tab.

After that the *skill* still gates the craft, exactly as it gates the fitting, and
at the same level: out of electronics scrap, wire, screws and sheet metal, plus a
**Small Motor** and a receiver for the four that move a piece of metal or of cloth
-- the strike, the door operator, the curtain motor and the window operator -- and
a radio receiver for the tuner control, which has nothing in it that turns. A very experienced electrician does eventually work
them out unaided, six levels above the level that fits them, which is what the game
does with every magazine recipe it ships: the magazine is the way you get there
early, not the only way.

**Some buildings are already wired.** About one shop, bank, school, clinic, station
or office in three had all this done before the outbreak, and you will find its relays
and contacts already on its fixtures with nobody to thank for them. They are ordinary
modules: `dev` lists them, the right-click menu offers **Remove**, and taking one off
puts the box in your bag. Nothing puts it back afterwards — the building is yours to
rewire from there. See *[A place that is still running itself](#a-place-that-is-still-running-itself)*.

**With the option off**, none of this exists: every door, window, lock and light
of the building is in `/dev` the way it was before the modules, the right-click
menu is not there at all, and a module already fitted is simply not consulted.

**Motion sensors** are the one device you supply yourself. The part is a vanilla
**Motion Sensor** (`Base.MotionSensor`) — the electronics module, out of a house
alarm or off an electronics shelf, the same one the game's own sensor recipes eat.
*Drop* one on the floor of a room the machine can reach and it becomes a
`sensorN`. Pick it up and the device is gone, and the number it had stays
reserved, so a name you wrote into a script answers `sensor0: no such device`
rather than pretending.

```
dev sensor
sensor0  office                1E 0           clear
sensor1  store                 4E 2S          motion

cat /dev/sensor0     -> clear
echo motion > /dev/sensor0
sensor0: invalid value
```

What it watches is **its own room, out to three tiles**. It never sees through a
wall, so a head in the hall tells you nothing about the kitchen; where there is no
room at all — a base, a yard — it watches three tiles in every direction and its
description reads `built`. A survivor, a zombie, an animal and a **car** all set it
off, which is what the game's own sensors trigger on; an invisible character does
not.

One thing the machine will **not** do: wire up a bomb. The fifteen
`*SensorV1/V2/V3` items — pipe bomb, aerosol bomb, flame trap, smoke bomb, noise
trap, each with a motion sensor taped to it — are never devices, whatever they are
called. A mine that goes off when it detects movement is not a motion sensor, and
a security system built out of five of them is a security system that kills you.

And it is a **movement** detector, not a proximity fuse. The contact closes the
moment the picture in front of it changes — somebody moved, walked in, or walked
out — and it stays closed for five seconds after the last movement. So a zombie
that wanders into the field and **stops** reads `clear` five seconds later, with
the zombie still standing there. That is what a real one does, and it is why a
script polls a sensor instead of reading it once.

Click the window's close button, or run `exit`, to leave. The screen itself keeps
running: log back in later and it is exactly as it was left.

## A place that is still running itself

Walk up to a shop at five to nine and watch the lights go out at nine, with nobody
near the switch. About one premises in three that had a nightly job to run was set up
for it before the outbreak: the relays and the contacts are on its fixtures, its
computer was **left running**, and the crontab on it is still being read. A bank bolts
its vault at six on a weekday. A station reads its own schedule out on the hour. A
school puts its lights out at ten, a shop at nine, and both put them back on at seven
in the morning.

It is not a script waiting for you to arrive. `cron` on those machines runs on the
county's clock whether anybody is there or not — but a computer can only reach the
building around it while that part of the map is loaded, so what actually happens is
that the lights go out **while you are standing there** and nothing happens at all
while nobody is. Which is what a timer nobody is watching does.

**What to do with one.** The machine is on, so there is a screen already. Find it, log
in, and:

```
crontab -l                     the line, exactly as it was left
dev                            the fixtures it can reach
crontab -r                     take the job out
echo "0 22 * * * sh $HOME/bin/lights.sh light0" | crontab
```

The crontab belongs to whoever's job it was — often the machine is still sitting at
his prompt — so `crontab -l` as him shows it, and as `root` you can read and write
anybody's. Unscrew the relay out of a light switch and that light stops answering: it
is not a device any more, and `dev light0` says `no such device` until you put a relay
back.

**And where there is no power there is nothing.** A premises whose grid has gone has a
dark computer and does nothing at all on a schedule, exactly like a 1993 timer with no
mains. The hardware is still on the walls, so a generator is all it wants.

A house is never one of these — a house had nothing to run — and neither is a display
model in an electronics shop's window. Whether a premises was set up this way is
decided **once**, the first time you ever come near one of its computers, and it never
changes afterwards. It follows **Prefilled machines and disks** in the sandbox options like
everything else already on the machines.

## The other computers on the premises

Every computer on a **premises** is on one length of coax with the others,
and it has an address it did not choose: `10.<b1>.<b2>.<n>`, where the first two
bytes come from where the premises is and the last is which computer of it
this is.

**A premises is not a building.** A house is one building and one premises; a
shopping mall is one building and a dozen shops, and each shop is its own -- its own
wire, its own telephone number, its own staff and its own password on the paper in
its drawer. Two things tell them apart, and the second one is new: a named map zone
smaller than the building it sits in is a shop, and a *room* whose name is a trade is
a shop where no zone says otherwise -- so the mall's music store and the dentist two
doors down are two businesses now instead of one. The zones a house sits in are
suburbs and districts, all bigger than the house, so a house is still a house; and a
shop with a back office and a stock room is still one business, because it takes two
trades in a building to make it a mall.

The parts of a mall that belong to nobody -- the corridors, the lifts, the stairs --
are the building's, and a stock room or a break room belongs to the shop it shares
its longest wall with. The BIOS announces it between the drive and the login, `ifconfig`
prints it any time, and nothing sets it -- the address is a fact about the card
the way the hostname is a fact about the machine. A computer in a base **you**
built is on no premises the map knows about, so it has no wire at all and says
so: `eth0: flags=2<BROADCAST>` with no address under it.

Names live in `/etc/hosts`, root's and `644`. It ships with the loopback and the
machine's own line and the machine never writes in it again, so the first thing
to do with a new one is write the others down:

```
10.4.17.3 gate
10.4.17.4 office pump
```

**`arp` is what tells you the addresses to write in it.** There is no name
server on this rung, so the two halves of the wire do not meet on their own:
`ruptime` lists the machines by the name each one *broadcasts* about itself,
`ping` and `rlogin` want a name `/etc/hosts` carries, and until there was an
`arp` nothing on the disk joined the two -- `ruptime` showed `office` and
`ping office` said `unknown host`. `arp -a` is the cache: every other machine of
the premises that is switched on, in `arp(8)`'s own shape, with a `?` for an
address no line of `/etc/hosts` names yet.

```
admin@ksp-04-11:~$ arp -a
gate (10.4.17.9) at 8:0:20:1e:2a:4b
? (10.4.17.4) at 8:0:20:3c:7f:11
root@ksp-04-11:~# echo "10.4.17.4 office" >> /etc/hosts
```

`arp <host>` is one entry, by name or by address, and
`<host> (<addr>) -- no entry` -- arp's own line, unsigned -- for a machine it
resolved and has no card for: switched off, or on another premises. A name
nothing resolves is `arp: <host>: unknown host`. The machine itself is in no
cache of its own, exactly as no kernel ARPs for its own address.

The Ethernet address is **derived** from the network address (`8:0:20` is Sun's
OUI, which is what a county office's boxes were, and the three low bytes come
from `b1`, `b2` and `n` through the same multiply-add modulo 2^16 the premises
key uses). It is stored nowhere, so the same machine answers the same card for
ever, and the three forms of `arp(8)` that CHANGE a line -- `-d`, `-s`, `-f` --
are not here rather than here and lying.

**An address is accepted anywhere a name is**, and resolved with no lookup at
all: `ping 10.4.17.4`, `rlogin 10.4.17.4`, `rsh 10.4.17.4 date`,
`rcp log 10.4.17.4:/tmp/log` and `arp 10.4.17.4` all work on a machine whose
`/etc/hosts` somebody emptied. `ruptime` and `rwho` are the exception and stay
names: they are reports the machines broadcast about themselves.

| command | does |
| --- | --- |
| `ifconfig [-a\|<iface>]` | the two interfaces, `eth0` and `lo0` |
| `arp -a \| arp <host\|address>` | the cards on the wire, address by address |
| `ping <host\|address>` | three packets a second apart, and the statistics |
| `ruptime` | the machines of this premises that are switched on |
| `rwho` | who is logged in on them |
| `who [am i]` | who is logged in *here*, with where each came from |
| `last [name]` | the logins in `/var/log/wtmp`, newest first |
| `rlogin <host\|address> [-l user]` | a shell on another machine, on this screen |
| `rsh <host\|address> [-l user] <command>...` | one command over there |
| `rcp <src> <dst>` | one file across, one end of it `<host>:<path>` |

`ruptime` and `rwho` are the rwho package's, cut where sixty columns forced a
cut: one load average instead of three, and no `down` row for a machine that is
off -- a real one keeps the last report it heard in `/var/spool/rwho` and there
is no spool here, so a dark machine is a machine nothing on the wire has ever
heard of. The load is how many jobs the machine has that can run, which is what
a load average has counted since the first one; nothing here averages anything,
so it is this instant's.

**`rlogin` is a shell over there on this glass.** It asks `login:` and
`password:` through the far machine's own accounts, and from then on every line
typed is that machine's: its files, its `/dev`, its accounts, its jobs, its
budget. The screen is one unbroken stream -- your own prompt, the `rlogin` you
typed, the far machine's work, and then your own prompt again with all of it
still above -- because a real terminal never had a second screen to put anything
on. Your history keeps the `rlogin` line and nothing you typed over there; the
far machine's history keeps that, in its own home. The editor travels: `edit`
down an `rlogin` opens the far machine's file and Tab saves it over there.

**`rlogin` needs a terminal to hand over**, the way `rlogin(1)` does: it puts
your own terminal into raw mode and gives the far end everything typed on it, so
a job with nobody in front of it has nothing to give and gets
`rlogin: not a terminal` -- a crontab line, an `&`, a `$(...)` and a stage of a
pipeline. A script run from the prompt in the **foreground** keeps the terminal it
was started from, exactly as it does on real Unix, so a `./nightly.sh` with an
`rlogin` in it opens its session. Without that rule a crontab was a way to land a
logged-in session on the glass of a machine nobody was standing at.

`exit` ends it, and so does Escape at an idle prompt; either way the line
`Connection closed.` comes back. Escape while something is running over there is
that job's `^C` and not the end of the session. Switching either machine off,
the power going out and either computer being picked up all end it too, and so
does a `shutdown` typed inside it.

**A password every time is what the trust files are for**, and either of the two
is enough. A line names a machine either way -- `gate` or `10.4.17.3` -- and a
NAME is matched the only way this rung can match one: through the trusting
machine's own `/etc/hosts`, against the address the session arrived from. It is
never matched against the name the caller announces. That name is the caller's
own `/etc/hostname`, a `644` file its own root may write to anything, so a
machine that trusted one would let anybody with root on any computer in the
premises type `hostname gate` and walk in through a line somebody wrote about
gate -- which is why `ruptime`'s names are reports and not credentials, and why
a caller with no address at all (a telephone call, a radio link) is trusted by
neither file. `/etc/hosts.equiv` is the machine's own, root's and `644`, one line
each: a bare host name trusts **the same account** on it and nobody in as
anybody else, and a host and an account names the account *coming in* --
`here admin` in bob's own `~/.rhosts` lets `here`'s admin be bob, which is
`ruserok(3)`'s reading of that second field and is what `rlogin gate -l bob` is
for. `~/.rhosts` is the
account's own half, and it is checked the way `rlogind` checks it -- it has to be
**your** file and nobody but you may write it, so one owned by somebody else or
one at mode `664` is ignored without a word. `root` is never trusted by
`/etc/hosts.equiv`, only by `/root/.rhosts`.

`rsh` never asks for a password, because `rshd` does not: trust or
`rsh: gate: Permission denied`. It needs **no** terminal, which is the whole
reason a crontab calls `rsh` and not `rlogin`, and it never takes the screen over:
the session it opens is for the command's output and not for a pair of hands.

**`rsh` blocks.** The job that gave the order is parked — `ps` shows a `W`, `jobs`
says `remote`, and it spends nothing at all while it waits — the far machine runs
the command on its own budget, and then what that command printed is delivered
into the waiting job's own output stream, with the far command's status in `$?`.
So it goes wherever that job was already writing: the glass for a line typed at
the prompt, the pipe for `rsh gate ls | wc -l`, the word for `$(rsh gate date)`,
the file for `rsh gate date > file`, `/var/mail/<you>` for a cron line. Then the
job runs on, which is why an `rsh` is no longer the last thing a script ever does.
A remote command that never ends keeps the local job waiting until Escape or
`kill` (either tears the far session down) or until the far machine's own cpu
ceiling kills it, which comes back as a status of 130. No greeting is printed on
an `rsh` session — `rshd` prints none, `login` does — so what comes back is the
command's output and nothing else. `rcp` needs the same trust, lands the file as the account you are,
and is judged by the far machine's own permissions, its 4096-byte file ceiling
and its own 64K disk. It is not quick: the wire runs at about a kilobyte a
second.

The limits, because each is something a player meets. Four sessions may come in
at once and the fifth is `rlogin: connect: Connection refused`. A chain of
`rlogin`s goes two machines deep and the third is refused in the same words. And
a session costs the **far** machine: a loop left running on `gate` slows `gate`
down and leaves your own machine at an idle prompt.

**Where a session came from** is the receiving machine's own answer, not the
caller's: `rlogind` takes the address off the wire and asks its own `/etc/hosts`
what it is called, so `who`'s brackets, `last`'s host column and
`/var/log/wtmp` carry the name when a line of that file gives one and the bare
address when none does.

`/var/log/wtmp` is what `last` reads: root's, `644`, two hundred lines deep with
the oldest dropped, and exempt from the 64 KB disk quota by its path exactly as
`/var/log/cron` is. That is why `wtmp begins` is a real answer on this machine
rather than the formality it is on a real one.

## The telephone

The coax reaches one premises. The telephone reaches the county.

A premises has **one line**, and the number belongs to the line and not to a
machine: every computer on that premises answers on it, one call at a time. So a
house is one number and a mall is one for every shop in it.

The number is seven digits, `NNN-NNNN`, which is how a call inside one area code
was dialled in 1993. The first three are the **exchange** and they belong to the
*town*: every machine around here shares them, and the next town is on another
switch. The last four are the premises. Both are derived from where the machine
stands, exactly as the address is, so nobody can type a new one.

The firmware announces it under the card, and that BIOS screen is the **only**
place it is written -- there is no `/etc/phone` -- with the shop's name behind it
where there is one, from the map's zone or from the room the shop is:

```
Phone line: 555-0417 (CoffeeShop)
Phone line: 555-2260 (Music Store)
```

A computer in a base you built is on no premises, so it has no line:
`cu: no phone line`. Neither has a machine off a save older than this firmware,
until somebody switches it on or opens a window on it where it stands -- and a
machine that has been sitting in a mall since before the shops were told apart is
given its shop's own number at that same moment, so the number on its BIOS changes
once. Whatever is on its disk does not: the password on the paper in its drawer still
opens it.

**A party line.** Several machines of one premises are all on that one line and
the lowest address is the one that picks up -- a house has one line and one modem
set to answer. Two premises can land on one number too, and then it is the same
answer: the lowest address answers, and the line is busy for both.

| command | does |
| --- | --- |
| `cu telno` | call another machine: a session on it, on this screen |
| `cu -l line` | open a serial line instead of dialling: the radio's is `/dev/radio0` |

```
admin@ksp-04-11:~$ cu 555-0102
CONNECT 2400
Connected.
login:
```

Four words in capitals are the **modem** talking and not a command, and they are
a Hayes-compatible modem's own result codes: `CONNECT 2400` when the far end
answered, `BUSY` when the line is in use at either end, `NO DIALTONE` when there
is no exchange, and `NO CARRIER` when nobody answered or the line went away
under a call that was up. `Connected.` and `Disconnected.` are `cu(1)`'s own two
lines.

**And then there is the waiting.** Nothing at all is on the screen while the modem
dials and the far end rings:

| what you get | how long it takes |
| --- | --- |
| `CONNECT 2400` | about 4 seconds, which is what a 2400-baud handshake took |
| `BUSY` | about 2 |
| `NO CARRIER` | **15**, which is this modem's `S7` register -- how long it waits for a carrier before it hangs up |
| `NO DIALTONE` | at once: that is what you hear the moment the receiver goes up |

Both numbers are busy for the whole of that, so a fifteen-second ring is fifteen
seconds in which neither telephone can take another call. Escape gives up on the
dial, and the modem says `NO CARRIER` about that too -- a receiver put down is a
carrier that never came.

From `login:` on it is `rlogin`'s session -- the far machine's files, its
accounts, one of its same four `ttyp` lines, its jobs, and it counts as a hop of
the same two-deep chain -- with two differences:

- **A password every time.** `/etc/hosts.equiv` and `~/.rhosts` are lists of
  *machines*, and a call carries no machine, only a number: `ruserok(3)` has
  never had an answer for one. So no trust file is asked, however trusted your
  computer is on its own coax.
- **It is slow.** The line is 2400 baud, which on a sixty-column screen is four
  lines a second (`CeroSec.PHONE_LINES_PER_S`) underneath the machine's own
  twenty. Nothing is dropped: a `cat` down a call arrives in handfuls.

Over there, `who` and `last` name the **number** the call came from -- `(555-0417)`
in the host column -- and that is what goes into `/var/log/wtmp`. It is the honest
thing to record: a number is what a stranger has instead of a name.

`exit` over there ends it, and `~.` typed alone on a line at the far machine's
prompt ends it from this end -- `cu`'s own tilde escape, read by the near end and
never sent down the line, so it is a command on neither machine and in neither
history. (The other tilde escapes are not here: `~!` is a second shell and
`~%put` is a file transfer.) Escape still works the way it does down an `rlogin`:
`^C` for whatever is running over there, and the end of an idle session.

`rsh` and `rcp` do **not** dial. They are network commands -- `rcmd(3)`, a
socket, a route -- and a call is not a route: `rsh shed date` on a machine in
another premises is `No route to host` whether or not you could have called it.
Copying a file by telephone was `uucp`'s job, and `uucp` is not on this disk.

**The exchange is the county's grid.** A telephone exchange is a building full of
switches on the mains, so the day the sandbox's power cutoff arrives there is no
dial tone anywhere, for good -- and a call that was up when it happened comes
back as `NO CARRIER`. That is the real difference between the two links: the coax
is two machines and a wire and goes on working with a generator at each end,
while a call needs a third building that is still working. Whether the grid is
alive is asked the way the game's own Lua asks it (`ISButtonPrompt.lua:520`).
A server that wants it otherwise sets one option:

| `SandboxVars.CeroSec.PhoneService` | the exchange |
| --- | --- |
| `grid` (default, and what anything unset means) | lives as long as the county's power |
| `never` | there is no telephone service at all, from day one |
| `always` | on its own generator; it outlives the grid |

**The phone book.** Your own number is on the BIOS screen. Everybody else's is in
the telephone directory, and the county is full of them -- `Phonebook` is a vanilla
item that turns up on hall tables and behind shop counters. Right-click a copy in
your bag: **Look up numbers** opens it as a book with leaves, the businesses of one
exchange, a name and a number a line:

```
  Coffee Shop ................................ 555-0416
  Dentist .................................... 555-3841
  Music Store ................................ 555-2260
```

The shops of a mall are in it now, each under its own trade, which is how you find
the number of the one two floors up without walking the whole building.

Dial it with `cu` from any machine in the county -- it is the same seven digits
everywhere, and `NO CARRIER` after fifteen seconds is a shop with no computer
switched on in it rather than a wrong number.

A directory covers **one exchange**: the part of the county its copy was printed
in, which is where you first opened it. The exchange goes on the item's name the
moment you do, so three books in a bag are three books you can tell apart, and a
book carried across the county is still the book of where it came from. Turn the
leaves the way you turn the manual's.

**Houses are not listed.** A house has a line like anything else, and nobody wrote
the family names down: an unlisted number is an unlisted number. Neither is where a
shop stands -- a directory prints names and numbers, and the rest is walking. A shop
that is the only business in its building is not listed either: it is one premises,
and as far as the yellow pages go it keeps to itself.

## The radio

The coax reaches one premises, the telephone reaches the county, and the radio
reaches whatever is in earshot of an aerial -- with no wire and no exchange, which
makes it the **only link that outlives the county's power**.

A **two-way** radio (a ham set, a walkie, a man-pack: `TwoWay = true` in the
game's own item scripts) that the machine can reach becomes its **TNC** -- the box
that turned a computer into a radio station in 1993. Its reach is the machine's own
room in a building the map knows, or one tile in a base you built, and there is one
per machine, on the serial port:

```
admin@ksp-04-11:~$ dev radio
radio0    ham          2E 1N      144.390 on
admin@ksp-04-11:~$ cat /dev/radio0
144.390 on
```

The frequency in megahertz and one of three words: `on`, `off`, `no power` (a dead
grid or a flat battery, and to a TNC those are the same thing). **Read-only**, at
mode `440` like the motion sensor: the game has exactly one path that moves a
radio's channel and it is the radio window's own timed action, so the knob is on
the set and a survivor turns it by hand. `dev find radio0` outlines it when there
are two in the room.

A station needs a **callsign**, and unlike the address and the number it is a
FILE:

```
admin@ksp-04-11:~$ cat /etc/callsign
KD4AXR
```

Root's and `644`, seeded with one derived from the premises key and the machine's
own number -- `K`/`N`/`W`, an optional second letter, the fourth call district's
digit (Kentucky), and three letters, which is what a United States amateur held in
1993 -- and announced by the firmware under the modem, the way a TNC printed its
own `MYCALL` at power-up. Root may write it to anything, which is the whole
security lesson below.

The box is a **peripheral on a serial line**, so it is reached the way 1993 reached
one -- there is no `call` command, and the one that was here until
`SYSTEM_VERSION` 17 was invented:

| command | does |
| --- | --- |
| `cu -l line` | open a serial line: `/dev/radio0` is the TNC's |

```
admin@ksp-04-11:~$ cu -l /dev/radio0
CeroSec Systems TNC-200 (TNC-2 compatible)
cmd: MYCALL
MYCALL KD4AXR
cmd: C KE4QWZ
*** CONNECTED to KE4QWZ
login:
```

At `cmd:` the box takes the TNC-2's own commands, in either case, with the box's
own abbreviations: `MYCALL` (and `MYCALL W4ZZZ` to set it, which is
`/etc/callsign`, so root only), `CONNECT`/`C`, `DISCONNE`/`D`, `CONV`/`K`,
`MHEARD`/`MH`, `MHCLEAR`. Anything else gets `?EH`, which is what a TNC-2 answers
a line it did not understand. **Escape** steps out of a link back to `cmd:` with
the link still up, `K` goes back in, `D` drops it, and `~.` alone on a line hangs
the whole line up and gives the shell back.

Lines with three stars are the **TNC** talking and not a command, and they are a
TNC-2's own: `*** CONNECTED to <call>`, `*** DISCONNECTED`,
`*** retry count exceeded` and `*** BUSY`. (A TNC-2 spells the last one
`*** <call> busy`; the bare word was chosen so the one-line refusal reads like the
modem's `BUSY` on the link before this one, and the callsign is on the line above
it anyway.) Two more the machine says in its own name, because it can see them
without transmitting: `cu: no radio` and `cu: no callsign` -- and a machine with no
set in its room has no line to open: `cu: /dev/radio0: no such device`.

Both sets must be on, both powered, and **both on the same frequency** -- agree
one off the air, walk to the set, turn the knob, and check with
`cat /dev/radio0`. The link holds out to the **smaller** of the two transmit
ranges (7500 tiles for a ham set, 8000 for a walkie) measured on x and y with no
z in it, which is the game's own arithmetic. A password is asked **every time**:
no trust file is consulted, because a callsign is a file anybody with a radio and
an editor can choose. Over there `who` and `last` name the **callsign**, and that
is what goes into `/var/log/wtmp`.

`*** retry count exceeded` is the single answer to every way a connect goes
unanswered -- no such station, a machine or a set switched off, a flat battery, the
wrong frequency, out of range, or a chunk the server has not loaded -- because a
station that hears nothing learns nothing about why. And one of those is worse
than anything the telephone had: **a radio is a tile.** The server holds every
machine's disk whether its chunk is in memory or not, which is why `ruptime`,
`ping`, `rlogin` and `cu` all answer for a computer at the far end of the county;
a radio is registered with the game's radio subsystem in `addToWorld` and
unregistered in `removeFromWorld`, so a station in a town nobody is standing in
cannot be raised at all.

**Everybody hears it.** Every connect and every disconnect goes out as a real
transmission on the real frequency, from the caller's own set, with the game's own
distance distortion applied:

```
KE4QWZ de KD4AXR *** CONNECTED
```

Anybody in the county with a walkie tuned to that frequency and inside range reads
it in their radio window. That is not decoration and it is not a fault: a wire
cannot be overheard and a telephone call cannot either, and a radio cannot be
anything else. The defence is to change frequency and agree the new one off the
air -- which is why the knob is on the set and not in the machine.

There is **no sandbox option** for the radio. A range multiplier was considered and
rejected: the ranges are the game's own numbers for the game's own sets, and a
server that doubled them would be a server where the manual's arithmetic is wrong.


## The floppy drive

There is a slot on the front of the case, and a 3.5-inch disk goes into it. That is
how anything gets off one machine and onto another: write your notes, put them on a
disk, walk the disk across town.

Right-click the computer and the menu offers **Insert floppy** while you are
carrying one and **Eject floppy** once one is in. Both work on a dark machine as
well as a lit one — a drive is a spring and a lever, not a circuit — and one disk
fits at a time, which is what *Eject the floppy first* on a greyed-out Insert
means.

Carrying **more than one disk**, Insert floppy becomes a submenu with a line per
disk, so you pick the one that goes in rather than finding out afterwards. Each line
reads the disk's label if it has one and its shell colour in brackets — *PAYROLL 93
(green)*, or *3.5" Floppy Disk (blue)* for one nobody has written on. While the
drive is full or you cannot reach the machine there is nothing to choose between, so
the entry goes back to a single greyed line with the reason on it.

### Printed, or somebody's handwriting

A disk you find is one of two things, and you can see which without reading it.

A disk that came with **software** has a label printed at the factory and is named
for the product on it: *CeroSec UTILITIES 1.0*, *SHAREWARE GAMES 2.1*,
*NIGHTLINE DIALER 1.2*, *CeroSec OS 1.0 DIST*. Its sticker is white with two lines
of print on it, which is what the icon in your bag shows, and its tooltip says
**Printed label**.

A disk somebody kept his own things on is named in **his** words, in his own
hand — *books 93*, *do not read*, *home dir 8 july*, *heard log jul*. Plain
sticker, and the tooltip says **Handwritten label**. Two copies of the same kind of
disk found in different towns were two different men, so they do not say the same
thing.

Most of the box is blank, and a blank disk is neither: it reads *3.5" Floppy Disk*
and has nothing written on it at all.

### Writing on the label

Four disks in a bag look identical, so do what anybody with four disks did: write on
the sticker. Right-click a disk in your inventory, with **something to write with**
somewhere on you — a pen, a pencil, a red, blue or green pen, or anything else the
game counts as a writing implement — and choose **Label floppy**. Up to 24
characters: letters, digits, spaces, dashes and dots. Nothing else, because the
label is printed on the machine's own screen.

The label becomes the disk's name in your inventory, so you can tell your disks apart
without inserting them, and it stays on the disk through the drive and out the other
side. **What you write is handwriting** — a pen is a pen, so a disk you label says
*Handwritten label*, and labelling a printed disk over the top of its own line takes
the printed sticker off it. **Change the floppy's label** rewrites it and **Erase the floppy's label**
takes it off; both need the same pen in hand. A label is written on the disk and not
on the machine, so it travels across town with it.

And the machine reads it. `mount` and `df` name the disk in the drive by what is
written on it:

```
admin@ksp-04-11:~$ mount
/dev/hda on / type ufs (rw)
/dev/fd0 on /mnt type ufs (rw) (PAYROLL 93)
```

A disk out of a box is **blank**: there is no filesystem on it and nothing can be
written to it until you put one there.

```
admin@ksp-04-11:~$ cat /dev/fd0
blank
admin@ksp-04-11:~$ newfs /dev/fd0
/dev/fd0: 4096 bytes, 32 inodes
admin@ksp-04-11:~$ mount /dev/fd0 /mnt
admin@ksp-04-11:~$ cp notes.txt /mnt
admin@ksp-04-11:~$ ls /mnt
notes.txt
admin@ksp-04-11:~$ umount /mnt
```

`/dev/fd0` is the drive and exists only while there is a disk in it. `newfs`
formats — which empties, every time, on every machine there has ever been — and
`mount` grafts the disk onto `/mnt`, an empty directory the machine ships for
exactly this. From then on `/mnt` **is** the disk and every command you know works
through it; whatever was in `/mnt` before is covered, not deleted, and comes back
when you `umount`.

A disk holds **4096 bytes and 32 files**, which is one file as big as a file here
gets or a dozen short notes, and those are its own ceilings: fill the disk and `df`
has not moved on `hda`, fill the machine and the disk is still yours to write to.

```
admin@ksp-04-11:~$ df
Filesystem   Size   Used  Avail  Use%
hda         65536   2155  63381    4%
nodes         512     90    422   18%
fd0          4096      5   4091    1%  (PAYROLL 93)
fd0 nodes      32      2     30    7%
```

What travels with the disk is everything on it — the names, the contents, who owns
each file and what its mode is — so a file that was yours on one machine is yours
on the next, because an account is a name and the name goes with the file.

Three things to know. `umount` refuses while anybody's working directory is inside
the mount (`umount: /mnt: Device busy`) — including somebody who got there through
a symbolic link, since where he is standing is a place and not a spelling; `cd` out
and try again. So does `rm -r` or `mv` on the mount point itself, or on any directory with a mount under it —
unhooking the place a mount is written against would leave the disk in the drive
and no path to it. Ejecting a mounted
disk unmounts it first and loses nothing, because every write here is finished by
the time the command that made it came back. And `mv` will not carry a file between
the two disks (`cross-device link`) — use `cp` and then `rm`, which are two commands
because they are two things that can go wrong separately.

Who may format and who may mount is the mode on `/dev/fd0` and nothing else: it is
`root`'s, group `sudo`, at `660`, so `newfs` (which writes a super block) wants the
`w` bit and `mount` (which reads one) wants the `r` bit. `chmod 666 /dev/fd0` really
does hand the drive to the whole office.

## Finding the manual

CeroSec Systems shipped a **documentation set**, three volumes of it, and it is the
documentation for everything above — the commands, the files, the accounts, the
BIOS — written for somebody sitting at one of these machines in 1993.

| | |
| --- | --- |
| **CeroSec OS User's Guide** | the blue one, marked 1. Turning the machine on, logging in, the shell, the editor, your own files. What came in the box. |
| **CeroSec OS System Administrator's Guide** | the green one, marked 2. Accounts, groups, permissions, the system files, the devices, the network. What the office's own machine-minder got. |
| **CeroSec OS Programmer's Guide** | the red one, marked 3. Scripts, cron, jobs and pipes. What the one person writing anything for the machine got. |

They are loot. They are not in a crafting recipe and they are not given to you at
the start: they spawn where a book about a computer would have been sold, shelved or
left behind. The computer aisle of a **library**, a **bookshop** or a **university
library**; a **cyber cafe**'s desks and filing cabinets; the magazine rack of an
**electronics store**; a **university computing desk**; a **control room** counter.
More rarely, in an **office desk** or on an **office supply shelf**, where somebody
who bought one put it down. Rarest of all, on a **living room shelf** at home.

CeroSec Systems printed far fewer of the later volumes than of the first, and that
is what you will feel looking for them: the **User's Guide** at the rate above, the
**System Administrator's Guide** at half of it, and the **Programmer's Guide** at a
quarter — except at a university, a bookshop's computer aisle or an electronics
store, where it comes back up to a half, because that is where the people writing
anything for these machines were buying their books.

Rare, and findable: in the computer section of a library the User's Guide is roughly
the odds of a particular computer paperback, so a shelf or two of looking. In a
random office desk it is the rarity of a business paperback, so it is a surprise. The
exact weights, and the vanilla items each one was measured against, are in
`42/media/lua/server/CeroSec/CeroSecManualLoot.lua`.

**Reading one.** Right-click the book in your inventory and choose **Read the User's
Guide** — or the Administrator's, or the Programmer's, whichever you are holding. Or
just **double-click it**, which opens the same volume the same way. It
opens as an open book: its own cover, its own contents, two pages side by side, a
chapter title at the head of each leaf, page numbers at the outer corners.

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
copies are two bookmarks, and so are two volumes: your place in the Programmer's
Guide is not your place in the User's Guide.


## What you may find

Knox County had computers in it before the outbreak, and people were using them.
So a vanilla computer you switch on for **the first time** is usually not a machine
out of a box — it is somebody's machine, and what is on it depends on whose it was.

This is the sandbox option **Prefilled machines and disks**, and it is **on** by
default. Turn it off and every computer is a bare one: `root` and `admin`, both
open, an empty disk. Either way, **a computer somebody has already switched on is
never touched** — whatever you built on a machine stays exactly as you left it.

**Somebody's machine.** A computer in an office comes up with the office's own
greeting on the screen, a handful of staff accounts in `/etc/passwd`, a week of
`/var/log/messages` from the last days anybody came to work, and unread mail in
`/var/mail`. Some of those accounts are open and you can simply log in; some have
passwords. A computer in a house is a quieter thing and usually has nothing locked at
all. The name on the machine changes with it: the front-office machine is not `ksp-`
anything.

**And the factory `admin` is not on it.** A machine somebody set up gave that account
up the way any office would have: the dealer's own login is off `/etc/passwd`, its
home is gone and it is out of `/etc/sudoers`. So `admin` with no password is not a way
into somebody's machine, and **root's password really is the paper in the drawer**.
What such a machine has instead is the company's own administrator, who has a password
like the rest of the staff and can work the building he was responsible for — the
lights, the doors, the locks — and who **cannot** `sudo` his way to root either.

**But it is one person's desk, not the whole office's.** The accounts are the
company's and every machine in the building has all of them — but only **one** of
them has files on the computer you are standing at. Two computers in one office are
two different men's desks: the bookkeeper's has the ledger and the nightly job that
adds it up, the man at the next desk has his own memo and no job at all, and both
know the same three people and the same passwords. So a building with two computers
in it is worth walking twice.

**And the office down the road tells the story in other words.** Every note, every
handover, every list is written three ways, and which one a premises keeps is that
premises' own for the life of the save — with its own people's names in it. Reading
one office does not mean you have read them all.

**Whose machine it was depends on the building**, and there are eleven kinds:

| | |
| --- | --- |
| **a house** | somebody's notes, a page on how the porch light got put on a timer, a child's history homework. Nothing locked. |
| **an office** | a handover note, a ledger in cents, and the nightly job that mails the totals — which is a real line in a real crontab and really runs |
| **a sheriff's dispatch** | a shared `dispatch` login, a standing lookout list, and `/var/log/dispatch`, which stops in the middle of a line on the morning of the 9th |
| **a bank** | `accounts.dat` in four plain columns and the audit the examiner asks for, written down as two commands you can type |
| **a shop** | what was on the floor when somebody last counted it, the prices in cents, and the order to close up in |
| **a shop that sells computers** | the dealer's own machine in the back: the stock by model, what is on the repair bench, and how a machine was set up before it went out on the floor. Every machine **on the floor** is stock — see below |
| **a school** | grades by student number, because the names are in the cabinet; the bells on a clockwork timer the computer cannot reach |
| **a clinic** | rooms and wards and what has to happen next. Nothing medical: that is the chart, and the chart stays on the trolley |
| **a radio station** | the hour-by-hour sheet the machine reads off its own clock, and `/var/log/heard` — what the county sounded like from the 4th to the 9th |
| **a military post** | `root` and **nothing else**. No open account, and nothing in anybody's pocket. Three memoranda on the exclusion zone, and the last one tells whoever is reading it that the road south was open on the 8th of July |
| **CeroSec Systems** | the vendor's own bench: the whole script library standing together in `/usr/local/src`, a `CHANGES` that says why `hash` became `mkpasswd`, and the support mailbox |

**A machine nobody worked at.** Two of them, and both are worth recognising because
there is nothing to find on either and you can stop looking:

- **a display model.** In an electronics shop, every computer on the sales floor is
  stock. It comes up on an open `demo` account with nobody's files on it — a
  `WELCOME.TXT` telling you to try it, a `DEMO.TXT` selling it to you and a
  `PRICES.TXT` with the whole model line and the prices — and two or three lines in
  the history where a customer looked at one file and walked away. No staff, no mail,
  no log. The shop's **own** machine is the one in the back room, and that one is
  somebody's desk like any other.
- **a spare desk.** A premises has as many people as it has people: switch on more
  machines than that and the ones left over come up as the disk the dealer delivered
  — the company's name and greeting on it, the staff accounts and their passwords all
  present, and not one populated home.

**Root is still the premises' on both of them**, so the sticky note out of the back
drawer opens every machine in the building, the display models included.

**What they were doing before it happened.** Every desk carries the last week of
whoever sat at it, and none of it is decoration:

| | |
| --- | --- |
| `cat .sh_history` | every line he typed, oldest first, twelve to thirty of them. Press Up at the prompt and you are walking the same list. The last few are the morning it started: he read his mail, he looked at the log, he rang somebody, he locked what the computer could lock, and then `shutdown -h now`. Or not. |
| `last` | who logged in at that keyboard over the fortnight, newest first, with how long each session lasted. The owner most, the others now and then. |
| `mail` | three to six messages from the outbreak week: work, family, somebody who is not coming in, the county or the radio station about the roads, a reply from CeroSec Systems. The last one is unanswered. Reading it empties the spool, so read it once and read it properly. |
| `cat /var/log/messages` | the premises' own week, and then the nights at the end of it: a machine that came back up at four in the morning, a login that was refused, a call that got no carrier. |
| `cat draft.txt` | on about half of them: a page he was writing. It stops in the middle of a sentence. |

**And about one machine in four you will find still logged in** — better odds still on
a machine its premises left running, which is a machine nobody shut down. Nobody ever typed
`exit`, so it comes up at that man's prompt and asks you for nothing — his home, his
shell, his history under your fingers. `last` on such a machine says `still logged
in` against the last name on it. That never happens at a military post. It is a
**declared deviation** — no Unix can restore a session across a power cut, and the
manual's *What is not Unix here* page says so in the machine's own words; what is
deviated from is the story those machines tell, where the screen agrees with `wtmp`
instead of with the boot sequence.

**Some of them do things while you are not there.** A shop's lights go off at nine,
a bank's vault door pulls itself to at six on weekdays, the cells in a dispatch
office lock at ten, a clinic mails the morning round list at seven. Those are
ordinary crontab lines and `crontab -l` shows them to you — and nothing happens at
all unless somebody has wired a module onto the fixture, which is the same rule
every device follows.

A job like that belongs to **the man whose desk it was**, because it runs in his home
with his programs: it is on the computer he sat at and not on the one beside it. If
the cells in an office of two computers do not lock at ten, try the other machine.

    login: root
    Password:
    Login incorrect.

**The password is in the building.** For a machine with a locked `root`, somebody
wrote the password down, because everybody did:

| | |
| --- | --- |
| **in a drawer** | a yellow sticky note in a desk, a counter, a filing cabinet, a locker, a dresser or a side table **of that same premises**. Your bag calls it `Sticky note (root)`; **read it** and the page says `Sticky note: root / falcon12`. One per premises, at most. |
| **in a pocket** | about one dead employee in twenty, killed **inside** that premises, has his own login folded in his pocket — `Sticky note (rmiller)`, reading `Note: rmiller / thunder07`. Never root's — he was never given it. |

**A note is a sheet of paper and the game treats it as one.** Right-click it and
read it; with a pen or a pencil in your bag the same entry lets you write over it,
and the little bin empties the page first. Nothing you find is locked, so a note is
yours to reuse. And it burns: it feeds a campfire, a fireplace or a barbecue, and
it will light one, exactly as any sheet of paper does. Notes already lying in a save
from before this are the older item and are left exactly as they were — their name
still carries their password.

A shop in a mall is its own premises, with its own machine, its own staff and its
own note — the same rule the telephone line uses. A body in the street carries
nothing: he worked somewhere, but not there.

The two always agree, and they agree **before you ever touch the machine**: find
the note on Monday, switch the computer on a week later, and the password on the
paper is the one it wants. They are different in another save.

**If you never find a paper**, the machine is not lost. `last` tells you which
accounts have been used. An open account is often enough to read `/var/log` and see
who was here. The passwords are a plain word and two digits, so guessing is not
hopeless. And the 1993 answer to a machine nobody can get into is the one the
firmware gives: hold the switch through the BIOS and let it **repair** the system,
which reinstalls it and keeps `/home`.

**Disks with something on them.** Most floppies you find are blank, exactly as
before — seventeen disks in a hundred are not. Those come already labelled, and the
label is on the item in your inventory. Put one in the drive, mount it, and read the
`README.TXT` — a 1993 disk had one, in capitals, and it tells you what the other
files on the disk are and how to run them.

    admin@acct-04-11:~$ mount /dev/fd0 /mnt
    admin@acct-04-11:~$ cat /mnt/README.TXT

There are eleven labels:

| | |
| --- | --- |
| **UTILITIES** | two programs for the building: lights off, and which door is open |
| **BBS LIST** | telephone numbers of boards somebody used to call, and callsigns he used to hear. See below |
| **WARDIALER** | no wardialer. `cu` hands the screen to whatever answers and the script that called it stops there, so the disk carries the *method* instead: how to turn a range, what each modem word means, and a program to write down what happened |
| **GAMES** | guess the number, hangman, and a five-room adventure. All three short enough to read |
| **BACKUP** | somebody's home directory, saved on the 8th of July: a diary, the letters that were never sent, and the family's telephone numbers |
| **CEROSEC OS 1.0 DIST** | the distribution media the machine was sold with. How the firmware puts the system back, six manual pages in `MAN/`, and three programs |
| **LEDGER** | a small shop's books, kept in whole cents because the machine adds whole numbers: a line a day, who the shop buys from, and `total.sh` to add a column up. `sh /mnt/total.sh /mnt/SALES.TXT 3` is the week |
| **PERSONAL** | somebody's own disk, and none of it is any use to you: letters never sent, a list of things he was going to do, his mother's recipe, a poem he asks you not to laugh at, and four telephone numbers |
| **BBS** | somebody's kit for running a board of his own: five programs and a README. See *Running a board of your own*, below |
| **HOME AUTOMATION** | the home kit, labelled `CeroSec HOME 1.0`: six programs that run the building for you, and a README saying how to copy them and what to put in a crontab. See *Letting the machine run the building*, below |
| **RADIO LOG** | a ham club's packet log — every station the machine heard over the week before, when the nets are, and the station's own callsign — with a README on `cu -l /dev/radio0` and why `MHEARD` inside the box says less than the file does |

**The four disks that are somebody's own writing are written three ways.** `BACKUP`,
`LEDGER`, `PERSONAL` and `RADIO LOG` each have three tellings with three casts of
people in them, decided when the disk was made and fixed from then on, so the one in
the drawer across town is another person's week. The vendor's disks and the programs
are the same on every copy, which is what a manual page and a program are.

**The BBS list is printed where you first use it.** The numbers on that disk are the
numbers of *your* exchange — they come out of the same county directory the phone
book does, so they ring real premises, and a computer in one of those premises
answers `CONNECT 2400`. What is written beside each one is the board's name, in the
handwriting of whoever owned the disk. It is printed the first time you put the disk
in any machine and it never changes after that, so the list is the list of wherever
you were standing. Write over it and it is yours: nothing will overwrite what you
typed.

    admin@acct-04-11:~$ cat /mnt/NUMBERS.TXT
    admin@acct-04-11:~$ cu 418-2201

### Running a board of your own

If there are several of you and one machine with a telephone line on it, the `BBS`
floppy is the whole of what you need to turn it into somewhere you can leave each
other messages. It is five shell programs and a README, and it was written by
somebody who ran a board out of his own front room in 1993.

The sysop — whoever the machine belongs to — does it once:

    root@disp-04-11:~$ mount /dev/fd0 /mnt
    root@disp-04-11:~$ sh /mnt/setup.sh /usr/local/lib/bbs
    root@disp-04-11:~$ useradd alice
    root@disp-04-11:~$ passwd alice

and then puts one line at the end of each caller's `.profile`:

    sh /usr/local/bin/bbs.sh

After that, somebody who rings the number with `cu`, logs in as `alice` and gets a
menu instead of a prompt: **N** for what has come in since she last looked, **R** for
her whole mailbox eighteen lines at a time, **P** to write one — to a name, or the
word `all`, which mails everybody with an account and puts a copy on the board —
**B** for the board, **W** for who is on right now, **L** for the last callers,
**U** for the accounts there are, and **Q** to hang up.

Nothing about it is magic and that is the point: it is `mail`, `who`, `last` and a
`read` loop, in files you can read on one screen and change. The board itself is one
file in `/usr/local/lib/bbs` that everybody may write, with the newest posting at the
bottom — there is nothing on this machine that turns a file back to front, and the
README says so rather than pretending otherwise. Keep the mail with a line in root's
crontab and a floppy left in the drive:

    0 3 * * * tar cf /mnt/backup /var/mail

### Letting the machine run the building

The `HOME AUTOMATION` floppy -- its printed label reads `CeroSec HOME 1.0` -- is six
programs and a README, and it is the disk for a base you have wired. Copy them
where you keep your own, and either start one in the background or give it a
crontab line:

    admin@house-04-11:~$ mount /dev/fd0 /mnt
    admin@house-04-11:~$ sudo cp /mnt/curtains.sh /usr/local/bin
    admin@house-04-11:~$ crontab -e
    0 7 * * * sh /usr/local/bin/curtains.sh auto
    0 20 * * * sh /usr/local/bin/curtains.sh auto

| program | what it does |
| --- | --- |
| `autoclose.sh start [<secs>] \| stop` | a daemon: every `doorN` the machine can reach, once a second, and one that has read `open` for five rounds is pulled to through its operator. Start it with an `&` and stop it by name |
| `curtains.sh open\|close\|auto [dawn dusk]` | every `curtainN`. `auto` reads the hour and works out which way, dawn at 7 and dusk at 20 unless you say otherwise, so both crontab lines are the **same line** |
| `tvguide.sh [<channel>]` | one crontab line a minute: it tunes the set, switches it on while the schedule says something is airing, and off when it is not. 203 is Life and Living |
| `wake.sh now \| HH:MM` | `rx0` and every `lightN` on. With a time it puts itself in the `at` queue |
| `alarm.sh start \| stop` | a daemon: every door and window contact, and one that reads `open` is named on every screen in the building with `wall`, and answered by flashing the lights three times |
| `genwatch.sh [<percent>]` | one crontab line a minute: `gen0`'s fuel against a threshold, and under it one `wall` and one letter to root. Once, not sixty times an hour -- it never starts the generator, which is your decision and your noise |

None of the six names a device or a file of its own, so a copy off somebody else's
machine works on your base once it is wired. Without the hardware they say so and
stop: `curtains.sh: no curtain in /dev`, `tvguide.sh: no tv0 in /dev`.

**Programs somebody wrote.** Some machines have a script or two in their owner's
`~/bin`, which is already on your path once you are logged in as him. They are
written in the same `sh` you write in, so `cat` one and read it — that is how you
learn what this machine can do. Copy one off a disk with `cp /mnt/thing.sh ~/bin`
and it is yours.

There are nineteen of them in the county and **every one is a template**: none names
a device or a file of its own, so a script off a shop's machine works on your own
base once you have wired it. Lights off and lights on, locks either way, close a door and bolt it
(reading the door back first, because bolting a door that would not close bolts
nothing), which door is open, grep a columns file, add a column up, sort a list to
work down, print the line of a table for the hour it is, list everything under a
tree, write a line in a log — and three games.

The one place the **fourteen building tools** stand together is `/usr/local/src` on
the bench machine of a CeroSec Systems service department. The distribution disk says
so, and it is true. The five programs of the `BBS` disk are not there and never were:
they are a caller's own work, off his own disk, and a dealer did not stock them.

**And the phone book.** A vanilla phone book picked up in Knox County lists the
premises of that region with the number a computer standing in one would answer on
— which is how you find a machine to dial without walking into the shop. See
[the telephone](#the-telephone).
