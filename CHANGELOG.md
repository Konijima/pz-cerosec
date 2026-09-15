# Changelog

Player-facing notes, one entry per Workshop release. Every change adds its lines
under **Unreleased** in the words a subscriber reads, not the words a commit
reads. At release, `python3 tools/changelog-steam.py` prints the newest section
in the shape Steam's Change Notes take, and the section gets its version and
date.

## Unreleased

## 0.3.0 - 2026-09-15

The shell update. Nothing here needs a new save: machines you already switched
on keep everything. A server spends far less of its minute on the county.

- One terminal per computer per survivor. Opening the same machine again closes
  the window you had on it, a computer holds eight windows at once, and a flood
  of openings from one client is ignored past four a second. Nothing you can do
  at a keyboard reaches any of the three, and a server no longer pays for
  windows nobody looks at.
- The server's minute on the county goes on the computers that are actually
  running: a county of dark machines costs nothing, however many. And a running
  computer's filesystem is now checked once, when it comes back from the save
  file, instead of on every reading of it: forty running computers cost a game
  minute three milliseconds where they cost a hundred, and the check still
  refuses a filesystem that came back damaged.
- The shops that were already automated finish wiring themselves in big
  buildings, and the server stops re-reading the whole building every minute
  while they do. A mall's rooms arrive a few at a time as you walk it, so relays
  and contacts are fitted a few rooms a game minute and the shop is then written
  down as done: before this the wiring never called itself finished in a mall.
- A new command: `wall`. `echo "lights out in five" | wall` puts a line on every
  terminal of the machine, the glass in front of you and every session that came
  in over the wire, with a 1993 machine's banner on it. Anybody may send
  one, and it reads a file too (`wall /etc/motd`). What `shutdown` broadcasts
  goes out through the same door.
- Reading your mail no longer destroys it. `mail` shows what has arrived and
  moves it to `mbox` in your home as it goes; `mail -f` reads that file and
  moves nothing, so the address in last week's message is still there. `mbox` is
  an ordinary file of yours at mode 600 and costs your drive like any other: a
  drive with no room leaves the mail where it was and says so, having shown it
  to you. `You have mail.` at the login still means something has ARRIVED.
- `mail` sends as well as reads. `mail [-s subject] bob` posts a message to
  another account on the machine: the body comes from a pipe
  (`echo hi | mail -s Hello bob`) or is typed a line at a time until a line
  holding a single `.`, and Escape gives up without sending. Several names means
  a copy each. A name that is no account here answers `bob... User unknown`, and
  an address on another machine answers `bob@gate... Cannot send mail: no
  mailer`: there is no uucp on this disk yet. What you send costs your drive; a
  message cron mails you does not, so a job at four in the morning cannot fill
  it.
- Mail crosses the wire: `cat note | rsh gate mail -s Hi bob` leaves somebody a
  note on another machine. `rsh` now hands the far command what you piped into
  it, so `rsh gate wc -l` counts what you feed it instead of nothing.
- `grep` reads a pattern. `grep -c '^From ' mbox` counts the messages in a
  mailbox now, where the circumflex used to be a character to look for. It takes
  the old, plain kind of regular expression: `^` and `$` for the ends of a line,
  `.`, `*`, `[abc]`, `[a-z]` and `[^abc]` sets, and a backslash to take the
  meaning off any of them. `\( \)` and `\{2,5\}` are not here, and the manual
  says so. `-e` gives the pattern as a flag, the only way to look for one
  starting with a dash, and twice means either of two.
- Shell functions. `greet() { echo hello $1; }` and then `greet world`: the
  arguments inside are the call's, `return` hands a number back, `type greet`
  says what it is, and there is no `local` in a 1993 sh, so a variable a
  function sets is the shell's. A function belongs to the shell it was told
  about: `sh yours.sh` knows none of yours, `. yours.sh` reads them into this
  one (put that line in ~/.profile), and a logout takes them. Sixteen of them,
  a thousand bytes of text each.
- `case` is here. `case $1 in start) ... ;; stop|halt) ... ;; *) ... esac`, with
  a bar between patterns, the shell's own `*`, `?` and `[...]` in them, and `*)`
  as the catch-all; `help` and `type` know the two new words. One change: `;;`
  is an operator now, so a stray `echo a;;` is a syntax error instead of quietly
  running.
- What a script prints follows the redirect of the line that started it.
  `sh nightly.sh > log` left log empty and printed the script on the screen; now
  everything it prints goes in the file, `>>` adds to it, and a script that
  script runs writes there too. `./nightly.sh` and `. nightly.sh` are the same.
  A refusal still comes to the screen, and `ls` in such a script prints one name
  a line.
- The two kinds of brackets nest now. `stop=$(($(date +%s) + 300))` is a
  deadline in one line, and a catch round a sum works too; both answered a
  refusal before. Catches are still one level deep:
  `$(echo $(date))` is refused as it always was. And a `$( )` is a shell of its
  own: `y=$(x=2; echo $x)` leaves your own `x` alone, an `export` there marks
  nobody else's environment, and
  `echo $(cd /etc; pwd)` no longer leaves your prompt in /etc.
- `cut` takes its flags the way you type them. `cut -d: -f1 /etc/passwd`
  answered a usage line before; the value may now be stuck to the flag or stand
  apart, for `-d`, `-f` and `-c` alike.
- `sudo` owns up to a name it could not find. `sudo lights on` answered
  `lights: command not found`, as if it had run and refused; it now
  says `sudo: lights: command not found`.
- You can see which floppies hold a program. A disk that came with software
  wears its printed label and is named for the product on it, CeroSec
  UTILITIES 1.0 or SHAREWARE GAMES 2.1, with a sticker on its icon and
  "Printed label" on its tooltip. A disk somebody kept his own things on is
  named in his own hand instead, and two such disks found in two towns were two
  different men. Labelling a disk yourself is handwriting whatever you write,
  and relabelling a printed disk takes the sticker off it. Fixed: ejecting a
  disk with nothing written on it could hand it back named for a program it has
  not got a byte of, and that name stayed on it for good.
- The greeting is where a 1993 machine put it. Over the login prompt the machine
  names itself, out of a new file, /etc/issue; the message of the day greets you
  once you are in, printed once instead of twice. Logging in then tells you when
  this account was last used and at which
  terminal, or which machine it came in from over the wire, and whether there is
  mail waiting; the first time an account is used nothing is said about a last
  time. touch ~/.hushlogin for a machine that says nothing at all, and delete
  the file to have the greeting back.
- Machines already in your save gain /bin/wall and /etc/issue on load; a file of
  your own at either name is left alone.
- A new floppy to find: BBS, somebody's kit for running a board of his own. Put
  it in, read the README, and one command as root turns the machine into
  somewhere the people who ring it can leave each other messages: a menu at
  login with new mail, the mailbox a screenful at a time, a message to one
  caller or to everybody, a public board, who is on, the last callers, and the
  accounts there are. Five short programs you can read and change, because all
  of it is mail, who, last and a read loop. Its count of what you have read
  lives in .bbs_seen in your own home, so New means new. One share of the box of
  disks moved from UTILITIES to it; a written disk is still one in six.

## 0.2.0 - 2026-09-14

The world update. Nothing here needs a new save: computers you already
switched on keep everything; the new behaviour shows on machines nobody has
touched yet. Numbers of computers standing in a mall change once.

- Every shop in a mall is its own business: its own profile, staff,
  passwords, sticky note, phone line and network segment. The stock room
  belongs to its shop, the corridor to nobody. A building with one business
  stays one business.
- Some places were automated before the outbreak and do not wait for you:
  relays and contacts already on the fixtures, a computer already on, and a
  crontab that puts the lights out at nine and back at seven. Decided once per
  place, the first time you come near it. Log in and change the line.
- Somebody's machine no longer keeps the factory admin account open. The
  paper in the drawer, or in a pocket, is the way in.
- Electronics stores sell computers: the floor models come up as demo units;
  the shop's own machine is in the back. More computers than staff in a
  building, and the extra desks come up as unassigned.
- Two computers in one office belong to two different people: their own files,
  command history, mail and nightly job. Every memo, ledger and list is written
  three ways, so the office down the road tells another story.
- Every desk carries its owner's last week: `.sh_history` with the last lines
  of the morning it started, `last` with the fortnight's logins, `mail` with
  the outbreak week, `/var/log/messages` with the nights, a `draft.txt` that
  stops mid-sentence, and about one machine in four found still logged in.
- Three new floppies to find: LEDGER, a shop's books with `total.sh`; PERSONAL,
  letters never sent; RADIO LOG, a ham club's heard list. The disks that are
  somebody's own writing come in three tellings. Blank disks stay as common.
- The shell owes nothing to 1993 any more: `at`, `atq`, `atrm`; `tar cf`,
  `tf`, `xf`; `find -exec`; `export`, `env` and the dot; `$1` and `$#` inside
  `$(( ))`; Tab completes over `PATH`; `sudo cd` says what sudo says; a `$( )`
  that overflows says so and nothing else. The manual explains why `ln` here
  wants `-s`, and owns up to the machine found logged in.
- Restaurants, cafes, bakeries, butchers and diners are prefilled as the
  businesses they are, not as houses.
- Fixed: a floppy with a label written on it could not be inserted; any floppy
  gesture that does nothing now says why. Fixed: the military post's hourly
  door check called a program that was never installed.

## 0.1.0 - 2026-09-13

First release. Workshop item 3801094056, Build 42 only, no dependencies.

- The vanilla desktop computers switch on, light up and open a green 60x20
  terminal running CeroSec OS, a small 1993 Unix: files, permissions,
  accounts, sudo, a screen editor, a shell with pipes, jobs and cron.
- The disk belongs to the computer: walk away and come back to the same
  session; pick the computer up and carry it, the disk goes with it.
- Hardware modules: a magnetic contact, a relay, an electric strike and a
  door operator go on the fixture with a screwdriver and Electricity, and the
  door, light or window appears under /dev. A motion sensor is the vanilla
  one. The Field Wiring Guide teaches the four recipes. Sandbox option to
  make every fixture reachable without hardware.
- The network: Ethernet per premises (rlogin, rsh, rcp, ruptime, ping, arp),
  a telephone line per premises with seven-digit numbers, a Hayes modem (cu)
  that rings, a packet radio TNC behind cu -l /dev/radio0, and the vanilla
  phone book as the yellow pages of your region.
- Floppy disks in four colours: newfs, mount, a label written with a pen.
- The world: computers nobody switched on yet come up as somebody's machine,
  with staff, files, mail and logs of July 1993; the root password is on a
  sticky note in a drawer of the same premises, a staff login sometimes on a
  note in a zombie's pocket; disks found as loot carry utilities, games, a
  BBS list of your region, a backup, or the CeroSec OS distribution.
- A manual in three volumes found as loot; reboot switches the screen off
  and back on; your survivor stands at the keyboard.
- Saves migrate across updates; an update never breaks what you built.
