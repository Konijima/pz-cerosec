# Changelog

Player-facing notes, one entry per Workshop release. Every change adds its lines
under **Unreleased** in the words a subscriber reads, not the words a commit
reads. At release, `python3 tools/changelog-steam.py` prints the newest section
in the shape Steam's Change Notes take, and the section gets its version and
date.

## Unreleased

- You can see which floppies hold a program. A disk that came with software
  wears its printed label and is named for the product on it -- CeroSec
  UTILITIES 1.0, SHAREWARE GAMES 2.1, NIGHTLINE DIALER 1.2 -- with a printed
  sticker on its icon and "Printed label" on its tooltip. A disk somebody kept
  his own things on is named in his own hand instead: books 93, do not read,
  home dir 8 july. Two copies of the same kind of disk found in two towns were
  two different men and do not say the same thing.
- A pen is a pen. Labelling a disk yourself is handwriting whatever you write,
  and relabelling a printed disk takes the printed sticker off it.
- `mail` sends as well as reads. `mail [-s subject] bob` posts a message to
  another account on the machine: the body comes from a pipe
  (`echo hi | mail -s Hello bob`) or is typed at the prompt a line at a time
  until a line holding a single `.`, and Escape gives up without sending
  anything. Several names means a copy each; the recipient reads it exactly as
  he reads what cron left him. A name that is no account here answers
  `bob... User unknown`, and an address on another machine answers
  `bob@gate... Cannot send mail: no mailer`: there is no uucp on this disk yet,
  and the manual's list of what is not Unix here says so.
- Mail crosses the wire: `cat note | rsh gate mail -s Hi bob` leaves somebody a
  note on another machine. `rsh` now hands the far command what you piped into
  it, which is what a real one has always done: so `rsh gate wc -l` counts
  what you feed it too, instead of counting nothing.
- What you send costs the drive. A message cron mails you does not, as before:
  a job at four in the morning must not fill your disk, but an account that
  could fill somebody else's mailbox for nothing could fill the machine.
- The greeting is where a 1993 machine put it. Over the login prompt the
  machine now names itself, out of a new file, /etc/issue; the message of the
  day is what you are met with once you are in, and it is printed once instead
  of twice. A bank and an army post warn you before you log in, not after.
- Logging in tells you what a real one told you: when this account was last
  used and at which terminal, or which machine it came in from over the wire,
  and whether there is mail waiting for you. The first time an account is used
  there is no last time, so nothing is said about one.
- touch ~/.hushlogin if you want a machine that says nothing at all when you
  log in. Delete the file and the greeting is back.
- Machines already in your save gain /etc/issue on load, unless you had put
  something at that name yourself. Nothing you wrote is overwritten.

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
