# Changelog

Player-facing notes, one entry per Workshop release. Every change adds its lines
under **Unreleased** in the words a subscriber reads, not the words a commit
reads. At release, `python3 tools/changelog-steam.py` prints the newest section
in the shape Steam's Change Notes take, and the section gets its version and
date.

## Unreleased

- **The crafting recipes have names.** Every one of them used to show its internal
  name in the menu -- `DismantleCeroSecMotorCDPlayer` beside vanilla's tidy
  "Dismantle Electronic Item". They now read the way the rest of the game reads:
  "Make Curtain Motor", "Make Door Operator", "Dismantle Appliance for Motor",
  "Dismantle CD Player for Motor", in English and in French.

- **Sticky notes are real paper now: read them, write on them with a pen, burn
  them.** A note used to be an item whose only content was its name, which is why
  nobody could work out what it was for. It is a sheet of the game's own paper: the
  password is written on its page, so you open the note to read it, and the row in
  your bag says whose login it is -- `Sticky note (root)`, `Sticky note (jsmith)`.
  With a pen or a pencil on you it is a page you can erase and write over, and it
  feeds a campfire or a fireplace like any other paper. Notes already in your save
  stay as they were.

- **A new disk: `CeroSec HOME 1.0`.** Six programs that run the building instead of
  you, on a printed floppy with a README that tells you how to copy them and what
  to put in a crontab. It is a disk somebody paid for in 1993 and it turns up in
  the same drawers the others do, a little more often than the games.
- `autoclose.sh` is the one the disk is really for: **a door somebody left open,
  shut again five seconds later.** Start it with an `&` and it watches every door
  the computer can reach until you stop it by name. It needs a door operator on
  the door, so it shuts the doors you have wired and leaves the rest alone.
- `curtains.sh` draws **every curtain in the building**, or works out which way
  from the hour -- dawn at seven and dusk at eight in the evening unless you say
  otherwise. Two crontab lines, and they are the same line twice.
- `tvguide.sh` **switches the television on for the show and off when it ends.**
  One crontab line a minute, the Life and Living channel by default: it turns the
  set to the channel, waits for the schedule to say something is on, and switches
  it off again after. Somebody else's programme guide, done by the machine.
- `wake.sh` brings **the radio and every light on in the morning** -- a crontab
  line, or `wake.sh 06:30` and it puts itself in the at queue for you.
- `alarm.sh` watches **every door and window contact** and, when one opens, names
  it on every screen in the building and flashes the lights three times. Stop it
  by name when you want to walk through your own door.
- `genwatch.sh` watches **the generator's tank** and writes to root once when it
  gets low -- once, and not sixty times an hour, which is the difference between a
  warning and a nuisance. It never starts the generator: that is your decision and
  your noise.
- The company that wrote the disk and the computer shop that sold it already have
  some of it on their own machines, if you find either of them.

- A new part: the **Small Motor**. Knox County never sold one on its own, so you
  take a screwdriver to something that already has one -- a hair dryer, a pair
  of sheep shears, a CD player or a blower fan -- and you get the motor and the
  electronics scrap the game would have given you anyway. The CD player pays its
  usual two. Both recipes are in the Field Wiring Guide with the other four, and
  a motor turns up on the same shelves the modules do, rarer than any of them.
- **The electric strike and the door operator now cost a Small Motor and a
  Receiver each**, on top of everything they cost before. Nothing you have
  already built or already screwed to a door changes, and you still know every
  recipe you learned -- it is the price of the NEXT one that moved. The two
  modules that only watch a fixture, the magnetic contact and the relay, are
  untouched: a motor is for the ones that move something.
- **Four new modules, and five new things a computer can work.** A **curtain
  motor** on a curtain or on a door with a sheet over it (`curtain0`, open and
  close). A **window operator** on a window (`window0`) -- read the warning
  below. An **appliance switch** on an oven, a microwave, a coffee machine, a
  washer or a dryer (`stove0`, `washer0`, on and off). A **generator switch** on
  a generator (`gen0`), which reads `on fuel 62 condition 80 connected` and
  starts one without pulling a cord -- though not an empty, a wrecked or an
  unplugged one. All four are in the Field Wiring Guide and on the same shelves
  the first four are.
- **A window operator sets off a house alarm.** Opening a window is opening a
  window: the motor throws the catch on its way past, and in a house whose alarm
  was still armed when the power came back it rings, every time, exactly as a
  hand through the glass would. `0 6 * * * echo open > /dev/window0` in a house
  nobody has cleared is a horde at six in the morning. Closing one is silent.
  The book says all of this on the page before you fit one.
- A window is now two devices: `win0` is the magnetic contact and reads the
  latch, `window0` is the operator and moves the sash. Nothing about `win0`
  changed.
- If your server has **Hardware modules required turned off**, the new fixtures
  answer with no module fitted like everything else does -- so a world that was
  every door and light is now every curtain, stove, washer and generator too.
- **The television, and the radio on the shelf.** A new module, the **Tuner
  Control**, goes on a television or a radio set and gives the computer its
  switch and its dial: `cat /dev/tv0` reads `on channel 203 airing 1080-1440`,
  `echo on > /dev/tv0` lights the screen, and `dev tv0 channel 210` changes the
  channel. It is the first order on this machine that is not a single word, so
  it is four words at `dev` where everything else takes three. The recipe is in
  the Field Wiring Guide with the rest, it takes a radio receiver and no motor --
  nothing in it turns -- and it turns up on the same shelves.
- **The set says what is on and when the next programme starts**, which is the
  whole reason the device is worth having: `airing 1080-1440` is a broadcast on
  the air and the hours it runs, `next 360-720` is when the following one
  begins, and `idle` is a channel with nothing left today. The numbers are
  minutes since midnight -- 360 is six in the morning, 720 is noon, 1080 is six
  in the evening -- so a crontab line can switch the set on for Life and Living
  and off again after it.
- **On a server, everybody in the room sees it.** The game itself has no way to
  tell the other players that a television was switched on by something other
  than a hand, so the mod now sends that message itself. A player who joins later
  or walks back into the room finds the set on and on the right channel. If you
  were expecting your machine to be able to do this before now, it could not: a
  set switched on by a script was only ever on for the server.
- A ham radio the machine uses as its TNC keeps its `/dev/radio0` exactly as it
  was -- the frequency it TRANSMITS on is still yours to turn by hand. A tuner
  control on the same set adds an `rx0` beside it, which is the receiver, and
  the two do not get in each other's way.
- Two refusals worth knowing: `tv0: out of range` is a dial asked for a frequency
  that set cannot reach, and `tv0: no power` is a dead grid or a flat battery.
  The volume stays the survivor's, at the set.
- A computer running a script no longer reads the whole building ten times a
  second. It reads it once a second and asks each door, light and window what it
  is doing every single time, so nothing you can see on the glass changed and a
  server in a shopping mall stops paying for the other nine. A module you fit or
  unscrew reaches every machine in the building at once, as before.

## 0.3.0 - 2026-09-15

The shell update. Nothing here needs a new save: machines you already switched
on keep everything. A server spends far less of its minute on the county.

- One terminal per computer per survivor: opening the same machine again closes
  the window you had on it. A computer holds eight windows and openings from one
  client are ignored past four a second. Nothing you can do at a keyboard
  reaches any of the three, and a server stops paying for windows nobody looks
  at.
- The server's minute goes on the computers actually running, so a county of
  dark machines costs nothing however many there are; and a running computer's
  filesystem is checked once, when it comes back from the save file, not on
  every reading. Forty running computers cost three milliseconds a game minute
  where they cost a hundred, and a filesystem that came back damaged is still
  refused.
- The shops already automated finish wiring themselves in big
  buildings, and the server stops re-reading the building every minute
  while they do. A mall's rooms arrive a few at a time as you walk it, so relays
  and contacts are fitted a few rooms a game minute and the shop is then marked
  done -- before this it never finished in a mall.
- A new command: `wall`. `echo "lights out in five" | wall` puts a line with a
  1993 machine's banner on every terminal of the machine -- the glass in
  front of you and every session that came in over the wire. Anybody may send
  one, and it reads a file too (`wall /etc/motd`); `shutdown` broadcasts through
  the same door.
- Reading your mail no longer destroys it. `mail` shows what has arrived and
  moves it to `mbox` in your home as it goes; `mail -f` reads that file and
  moves nothing, so last week's address is still there. `mbox` is an ordinary
  file of yours at mode 600 and costs your drive: with no room left the mail
  stays where it was and says so, after showing it to you. `You have mail.`
  still means something ARRIVED.
- `mail` sends as well as reads. `mail [-s subject] bob` posts to another
  account here: the body comes from a pipe (`echo hi | mail -s Hello bob`) or is
  typed a line at a time until a line holding a single `.`, and Escape gives up.
  Several names means a copy each. A name that is no account answers `bob...
  User unknown`, an address elsewhere `bob@gate... Cannot send mail: no mailer`
  -- there is no uucp yet. What you send costs your drive; a message cron
  mails you does not, so a job at four in the morning cannot fill it.
- Mail crosses the wire: `cat note | rsh gate mail -s Hi bob` leaves a note on
  another machine, because `rsh` now hands the far command what you piped into
  it -- so `rsh gate wc -l` counts what you feed it.
- `grep` reads a pattern: `grep -c '^From ' mbox` counts a mailbox's messages
  now, where the circumflex was a character to look for. The old, plain
  kind of regular expression -- `^` and `$` for the ends of a line, `.`, `*`,
  `[abc]`, `[a-z]`, `[^abc]`, and a backslash to take the meaning off any of
  them. `\( \)` and `\{2,5\}` are not here, and the manual says so. `-e` gives
  the pattern as a flag, the only way to look for one starting with a dash;
  twice means either of two.
- Shell functions. `greet() { echo hello $1; }`, then `greet world`: the
  arguments inside are the call's, `return` hands a number back, `type greet`
  says what it is, and there is no `local` in a 1993 sh, so a variable a function
  sets is the shell's. A function belongs to the shell it was told about -- `sh
  yours.sh` knows none of yours, `. yours.sh` reads them into this one (put that
  in ~/.profile), a logout takes them. Sixteen, a thousand bytes each.
- `case` is here: `case $1 in start) ... ;; stop|halt) ... ;; *) ... esac`, with
  a bar between patterns, the shell's own `*`, `?` and `[...]` in them, and `*)`
  as the catch-all; `help` and `type` know the two new words. One change: `;;`
  is an operator now, so a stray `echo a;;` is a syntax error instead of quietly
  running.
- What a script prints follows the redirect of the line that started it. `sh
  nightly.sh > log` left log empty and printed the script on the screen; now all
  it prints goes in the file, `>>` adds to it, and a script that
  script runs writes there too. `./nightly.sh` and `. nightly.sh` are the same.
  A refusal still comes to the screen, and `ls` in such a script prints one name
  a line.
- The two kinds of brackets nest now: `stop=$(($(date +%s) + 300))` is a
  deadline in one line and a catch round a sum works too, where both were
  refused. Catches are still one level deep -- `$(echo $(date))` is refused as
  ever -- and a `$( )` is a shell of its own: `y=$(x=2; echo $x)`
  leaves your own `x` alone, an `export` there marks nobody else's environment,
  `echo $(cd /etc; pwd)` no longer leaves your prompt in /etc.
- `cut` takes its flags the way you type them: `cut -d: -f1 /etc/passwd`
  answered a usage line before; the value may now be stuck to the flag or
  stand apart, for `-d`, `-f` and `-c` alike.
- `sudo` owns up to a name it could not find: `sudo lights on` answered `lights:
  command not found`, as if it had run and refused; now it says `sudo: lights:
  command not found`.
- You can see which floppies hold a program: a software disk is named for the
  product on it, CeroSec UTILITIES 1.0 or SHAREWARE
  GAMES 2.1, with a sticker on its icon and "Printed label" on its tooltip. A
  disk somebody kept his own things on is in his own hand, and two such disks in
  two towns were two different men. Labelling one yourself is handwriting;
  relabelling a printed disk takes the sticker off. Fixed: ejecting a blank disk
  could name it, for good, for a program it has not got a byte of.
- The greeting is where a 1993 machine put it: over the login prompt the machine
  names itself out of a new file, /etc/issue, and the message of the day greets
  you once you are in, printed once instead of twice. Logging in says when this
  account was last used and at which terminal, or which machine it came in from
  over the wire, and whether mail is waiting; a first use says nothing of a last
  time. touch ~/.hushlogin for a machine that says nothing, delete it to have
  the greeting back. Machines already in your save gain /bin/wall and
  /etc/issue; a file of your own at either name is left alone.
- A new floppy to find: BBS, somebody's kit for running a board. Put
  it in, read the README, and one command as root turns the machine into
  somewhere callers leave each other messages: a menu at login with new mail,
  the mailbox a screenful at a time, a message to one or to everybody, a public
  board, who is on, the last callers, the accounts. Five short programs you can
  read and change, all of it mail, who, last and a read loop; what you have read
  is counted in .bbs_seen, so New means new. One share of the box
  of disks moved from UTILITIES to it; a written disk is still one in six.
- Everything this mod puts on a right-click menu is now at the top: Use
  computer, Turn on, Insert floppy, Eject, the hardware submenu on a light
  switch, Read the User's Guide, Look up numbers -- all above the game's own
  Grab and Equip, and Use computer leads on a running machine. The
  developer's CeroSec (dev) submenu stays last.
- A password on a paper always belongs to a computer that stands in that place:
  a house with no computer has no note in its drawers and no login in anybody's
  pocket. Before this a house with a study could hand you the password of a
  machine that is not there.
- For server owners and testers, the debug window gains a row of tools: the
  sticky note a drawer would hold and one of its staff papers, every account
  with its password, a password taken off, any disk of the catalogue, a root
  session at the screen, cron run without waiting, and a shop's wiring finished
  on the spot. A server admin has it in multiplayer now, where nobody could
  reach it. Its Files tab names the machine whose files they are, switches
  machine in place, shows a file on a double-click, folds /bin into one row, and
  filters paths.

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
