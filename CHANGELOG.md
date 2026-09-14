# Changelog

Player-facing notes, one entry per Workshop release. Every change adds its lines
under **Unreleased** in the words a subscriber reads, not the words a commit
reads. At release, `python3 tools/changelog-steam.py` prints the newest section
in the shape Steam's Change Notes take, and the section gets its version and
date.

## Unreleased

- **Some places were already automated, and they do not wait for you.** About one
  premises in three that had a nightly job to run was set up for it before the
  outbreak: the relays and the door contacts are on its fixtures, its computer was
  left running, and the crontab on it is still being read. Walk up to such a shop at
  five to nine and the lights go out in front of you at nine, with nobody near the
  switch. They come back on at seven. A bank bolts its vault at six on a weekday, a
  station reads its own schedule out on the hour, and a school puts its lights out at
  ten.
- Find the machine, log in, `crontab -l`, and the line is right there to change or
  take out. `dev` lists the fixtures it can reach. Unscrew the relay for the item and
  that light stops answering it -- and nothing puts the relay back: the building is
  yours to rewire.
- Whether a premises was automated is decided **once**, the first time you ever come
  near one of its computers, and never revisited. A place whose grid has gone stays
  dark and does nothing, which is what a 1993 timer with no power does. Houses are
  never automated, nor are the display models in an electronics shop's window. All of
  it follows **Prefilled machines and disks** in the sandbox options.
- The administrator's account on a prefilled machine can work the building it belongs
  to. It could not before: its own nightly job answered `permission denied` and
  mailed it to itself. It still cannot become `root` -- that is what the paper in the
  drawer is for.
- **A shop that sells computers is a shop that sells computers.** An electronics
  store used to come up as six copies of one back office. Now every machine on the
  sales floor is stock: it is switched on, logged in as `demo` with no password, and
  carries the three files a 1993 demonstration disk had -- a welcome, the pitch, and
  the whole model line with the prices. The shop's own machine is the one in the
  back room, and that one is somebody's desk like any other.
- **A spare desk is a spare desk.** Switch on more computers in one building than the
  place had people, and the ones left over no longer hand a second machine to
  somebody who already has one: they come up as the disk the dealer delivered, with
  the company's name and greeting on them, everybody's account and password present,
  and nobody's work anywhere. Which desk is whose is decided by the order you switch
  them on, once, and never changes afterwards.
- The sticky note in the drawer still opens **every** machine of the premises, the
  display models in the window included.

- **`at`**, for the thing you want done once: `echo halt | at 04:00` and the machine
  switches itself off at four. `atq` says what is waiting, `atrm` takes one out, and
  what the job prints goes to your mail like a nightly job's. It does not forget
  either: a job queued for four o'clock on a machine that was off at four runs when
  the machine comes back on.
- **`tar`**, so a home can go onto a floppy in one piece: `tar cf /mnt/home.tar ~`,
  `tar tf` to see what is on a disk you found, `tar xf` to put it back. Folders,
  modes and times come back with the files; root also puts the owner back. An
  archive is an ordinary file, so it counts against the disk and cannot be bigger
  than one file: 4096 bytes.
- `find` can do something to what it finds: `find . -name "*.log" -exec rm {} \;`
  runs a command for every name, and `-exec ... {} +` hands them all to one command.
  A long sweep takes its time and prints as it goes, so nothing on the machine
  stutters while it works.
- A script now gets the **environment**, the way it does on a real Unix, and not
  whatever you had typed at the prompt. `x=5` is yours; `export x` puts it where a
  script can see it; `env` prints the set as it will be handed over. What a script
  sets no longer leaks back out to your prompt either.
- New: `export NAME[=value]`, `env`, and `.`: the dot, which reads a file **in the
  shell you are standing in**, so a file of settings is worth keeping again. That is
  how `.profile` is read.
- The manual now says why `ln` here always wants `-s`: a 1993 `ln a b` made a second
  name for one and the same file, and this machine cannot hold one: a computer that
  can be picked up and carried is a disk copied name by name, so the second name
  would quietly become a second file. The page prints the answer you get without the
  flag.
- The manual's *What is not Unix here* page now also owns up to the one thing on
  it that is not a command: a machine nobody logged out of comes back at that
  person's prompt after the power returns, where a real Unix would ask again.
- A `$( )` that catches more than a word will hold now says `word too large` and
  nothing else. It used to say that and then spill the rest of the command's output
  across the screen, in the middle of the line you were typing.
- Tab now finishes a command of your own. It looks where the machine looks: every
  directory on `PATH`: so a program in `~/bin` is completed as soon as `PATH`
  names that directory, instead of only the ones in `/bin`.
- `sudo cd /root` used to do nothing and say nothing. It now answers
  `sudo: cd: command not found`, which is what sudo says about a word the shell
  itself is: it runs programs, and there is no program called `cd`.
- A sum may now count with what a script was handed: `$((5 % $1))`, `$(($# * 2))`
  and `$((${n} + 1))` all work inside the double brackets, where a dollar sign in
  front of a number used to answer `bad arithmetic`.
- Fixed: a disk with a label written on it could not be inserted. The drive took
  blank disks and refused every disk anybody had written on, the diagnostics disk
  included, and said nothing about it. It takes them now.
- A floppy gesture that does nothing now says why, over the survivor's head: the
  drive already has a disk in it, what you offered is not in your hands any more,
  or the disk itself is one this machine will not read, with the machine's own
  reason after it. A refusal nobody can read looks exactly like a broken mod.

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
