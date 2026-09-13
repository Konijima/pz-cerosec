# Changelog

Player-facing notes, one entry per Workshop release. Every change adds its lines
under **Unreleased** in the words a subscriber reads, not the words a commit
reads. At release, `python3 tools/changelog-steam.py` prints the newest section
in the shape Steam's Change Notes take, and the section gets its version and
date.

## Unreleased

- Two computers in one office now belong to two different people. Each machine
  has one person's files, their own command history, their own mail and their own nightly job; the other staff still have accounts on it, with the same
  passwords, and empty homes. A building with two computers is worth walking
  twice.
- Every note, handover, ledger, memo and list is written three ways now, and
  which one an office keeps is that office's own for the life of the save, with
  its own people's names in it. The office down the road tells the same kind of
  story in another voice.
- Every desk carries the last week of whoever sat at it. `cat .sh_history` is
  every line they typed, and Up at the prompt walks the same list; the last few
  are the morning it started.
- `last` now tells you who logged in at that keyboard over the fortnight before
  the outbreak, the owner most, with how long each session lasted.
- `mail` holds three to six messages from the outbreak week: work, family,
  somebody who is not coming in, the county or the radio station about the roads
  and the cordon, a reply from CeroSec Systems support. The last one was never
  answered.
- `/var/log/messages` has the nights in it as well as the working days: a
  machine that came back up at four in the morning, a login that was refused, a
  call that got no carrier.
- About half the machines have a page somebody was writing, `draft.txt`, that
  stops in the middle of a sentence.
- About one machine in four is found still logged in. It comes up at that person's prompt and asks you for nothing, because they never typed `exit`. Never at a
  military post.
- Five kinds of premises gained a file for the member of staff who had none, so
  no desk comes up empty.
- Three new floppy labels to find. **LEDGER** is a small shop's books, kept in
  whole cents: a line a day, who the shop buys from, and the program that adds a
  column up. **PERSONAL** is somebody's own disk and none of it is any use to you:
  letters he never sent, a list of things he was going to do, his mother's recipe,
  a poem he asks you not to laugh at. **RADIO LOG** is a ham club's packet log,
  every station the machine heard over the week before the outbreak, the schedule
  of the nets, and the station's own callsign.
- The disks that are somebody's own writing are written three ways now, with three
  different sets of people in them. The BACKUP diary you find across town is
  another person's week, not the same one again. Which telling a disk carries is
  decided when the disk is made and never changes afterwards, through any number
  of reloads.
- A box of floppies is as blank as it always was: the three new labels were paid
  for out of the shares the six already had, not out of the blank ones.
- Fixed: the military post's hourly door check named a program that was never
  put on the machine, so it mailed `not found` once an hour instead of checking
  the door.

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
