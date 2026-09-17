# Changelog

Player-facing notes, one entry per Workshop release. Every change adds its lines
under **Unreleased** in the words a subscriber reads, not the words a commit
reads. At release, `python3 tools/changelog-steam.py` prints the newest section
in the shape Steam's Change Notes take, and the section gets its version and
date.

## Unreleased

## 0.5.0 - 2026-09-18

The fixes of the first day of 0.4.0, and what was built while they were being
made: every exterior door and window of a building on the machine at last, sound
on every fixture it moves, a program left running with `&` that is still running
when you come back, one word that works a whole kind of device at once, and a
cable you can run to anything the building does not reach. Enough
of the second sort for a release of its own rather than a repair. Nothing here
needs a new save: every machine you have switched on keeps its accounts, its files
and its modules, and the computers in your world gain `/usr/local/bin` the moment
they load. The one thing you will notice on a save you already have is that a
program you left running with `&` is still running when you come back to it --
there is nothing else for you to do.

- **A module comes off when its fixture is picked up, taken apart or broken: it is
  on the floor, or in your bag.** Before this, a television carried to the next
  house took its tuner control with it into nothing, and a door a zombie broke down
  took the contact and the strike you had climbed up to fit. Now the boxes are lying
  on the tile where the thing stood -- in the doorway, beside the doorknob and the
  hinges the door drops itself -- and you pick them up and screw them on somewhere
  else. It counts for every way a fixture can go: picked up, sledged, dismantled,
  broken down by a zombie, and the wall it was on coming down with it. Two things
  deliberately drop nothing: a window somebody **smashes** is still a window and
  keeps its contact (it reads `smashed`), and a neighbourhood unloading while you
  walk away takes nothing off anything.

- **Every machine has `/usr/local/bin` now, and it is on the PATH.** The `HOME
  AUTOMATION` floppy tells you to `sudo cp /mnt/curtains.sh /usr/local/bin`, and
  that directory was not on any machine -- the copy answered `no such file` and
  there was nothing on the disk's README saying to make three directories first.
  It is there on every machine from now on, and it is the second entry of the
  PATH a login hands you: copy a program there and call it by its name, at the
  prompt or in a crontab line, with no `sh /usr/local/bin/` in front of it. The
  whole path still works exactly as the README writes it. **Machines already in
  your save gain the directory on load**, and anything you had made at one of
  those three names is left exactly as it is.
- **You can hear the building work.** A door the machine opens or shuts, a window
  its motor works and a curtain it draws all make the sound a hand would have
  made -- the door's own sound, wood or metal, the sash, the cloth -- and every
  player in earshot hears it, on a server as well as in a solo game. Until now
  every one of them moved in complete silence, which made an order that worked
  look exactly like one that did nothing: `autoclose.sh` shut the door behind you
  without a sound, cron opened a window at dawn without a sound, and
  `curtains.sh close` drew every curtain in the house without a sound. A device
  that refuses -- a boarded door, a smashed window, a curtain nailed over -- stays
  silent, and so does an order for something that is already the way you asked:
  two `close` in a row are one shut door and one sound. Latches, ovens, washers,
  generators and sets are unchanged; they were never the silent ones.

- **A program you left running with `&` is still running when you come back to your
  save.** A computer you never switched off is a computer that never stopped: quit to
  the menu, come back tomorrow, and `jobs` shows the daemon you started, the door it
  watches still shuts, and a `sleep` still has its own seconds left to go instead of
  going off the moment you sit down. Three things still end a job and they are the
  three that always did: the switch on the case, a reboot, and somebody carrying the
  computer away. Four things do not come back, because each of them is waiting on
  something a reload has not got -- a question a script had put on your screen, a
  call or a radio link it was holding, a `shutdown +N` you had ordered for later, and
  a shell you had logged in from another machine. `man jobs` and Volume 3 say so.
- **A server admin gets the debug window again.** The entry `CeroSec (dev)` on a
  computer's menu asked the game whether this connection was THE admin role, which
  answered no to an admin on his own server; it now asks the access level by name,
  the way the game's own map editor does. What the server answers has not changed.
- **A door or window on the south or east wall of a building was invisible to
  `/dev`. Every exterior door is found now.** A module fitted to the front door of
  a house that faces south did nothing at all: the machine listed the doors of the
  north and west walls and never saw the others, because a south wall stands on the
  tile *outside* the room and the computer only ever walked the rooms. Doors,
  windows and the sheets on them are all found from either side now, on every wall
  of the building, and so are the shop's back door in the alley and the window over
  the yard. Numbers you already have do not move: a door that turns up for the first
  time takes the next free number, so `door0` in a script you wrote last week is
  still the door you wrote it for, and the newly found ones are on the end of the
  list.
- **An outdoor lamp on the wall of the building is a `light` like any other.** The
  porch lamp, the lamp over the back door, the neon sign on a shop front: fitted
  with a relay, they are on the machine and on a timer with the rest. A lamppost on
  the street is not the building's and is not listed -- unless you run a cable to
  it, which is the next line.
- **Run a cable and the machine reaches a fixture that is not in its building at
  all.** The lamppost on the street, the gate at the end of the drive, the shop
  across the car park: fit the box as usual, then right-click the thing and take
  **Link to computer**. Every machine near enough is a line with its name, how far
  it is and what the run costs -- `ksp-front-01, 12 tiles, 12 wire` -- and it costs
  exactly that, one electric wire a tile across the ground and four more for every
  floor between the two, up to thirty tiles of cable. After that the fixture is in
  that computer's `/dev` like anything in the house, and `dev find` tells you what
  the run cost: `light1: blinking, linked, 12 tiles of wire`. The computer does not
  have to be switched on, you do not have to be inside, and the door does not have
  to be open -- a cable is the answer to not being able to reach the thing. You do
  need the screwdriver, the wire in your bag and the same Electricity the box
  itself wanted, and the walk takes as long as the cable is long.
- **And cutting one gives the wire back.** *Unlink from ksp-front-01* is on the
  same menu, one line per cable, and every tile comes back into your bag -- as it
  does if the fixture itself is picked up or broken, when the wire drops on the
  floor beside the boxes. One fixture answers up to four computers at once and is
  in all four of their `/dev`s; one computer holds thirty-two cables. A line the
  menu will not let you click says why: *Needs 14 electric wire*, *This fixture
  already answers 4 computers*, *This computer already has 32 cables*. Renaming a
  computer with `hostname` changes what the menu calls it and cuts nothing: the
  cable is run to where the machine stands, not to what it is called. **Nothing in
  your save changes for any of this**: a machine with no cables is a machine
  exactly as it was.
- **The menu no longer offers a cable to a computer that already sees the
  fixture for free.** A door, window or curtain the machine's own building
  already lists in `/dev` is greyed on **Link to computer**, with the reason
  in red -- a cable there would have bought you a second entry for the same
  door, not a new one. A machine with no building of its own reads the same
  way: anything already inside its ten-tile radius outdoors is greyed too, not
  just the pavement version of a wall fixture.
- **The inside rule was refusing a relay on a porch lamp.** Fitting a module from
  the pavement is refused for the building's skin -- a door, a window, a curtain --
  and for nothing else: an outdoor lamp, a generator, an oven somebody dragged into
  the yard or a radio on the step are fitted where they stand, because the pavement
  is the only place there is to stand in front of one. Nothing about the door, the
  window and the curtain has changed.
- **The device tables line up again.** A name exactly eight characters wide ran
  straight into the room beside it -- `curtain0office` in `dev` and in
  `ls -l /dev`, and `curtain0` is the first curtain of the first house you wire.
  The name column is one wider now, which the manual's page always showed; in
  `ls -l` the room column paid for it, so a long pair of rooms reads
  `kitchen-hal~` there. Nothing else moved, and both tables still end inside the
  screen's 60 columns.
- **`dev window close` shuts every window at once; the same for any kind and any
  word, one answer line per device.** The word in front of the value can be a kind
  instead of one device's name, so `dev light off` is the whole building's lights,
  `dev curtain toggle` turns each sheet the way it is not, and
  `dev tv channel 203` tunes every set. You get one line per device, in the order
  `dev window` lists them, and each is exactly what that device would have said on
  its own -- a boarded window still answers `window1: barricaded`, and a line with
  a refusal in it counts as failed, so a script can test it. There is no word for
  *everything*: `off` means one thing to a light and another to a generator, so two
  kinds is still two lines. `man dev` and the administrator's manual have the page.
- **A line longer than the screen is no longer cut in two when it goes down a
  pipe, into a file or into a `$( )`.** Sixty columns is what the screen can show,
  and the machine was applying it to everything a command printed before anything
  else got to read it. So `grep root /etc/passwd | cut -d: -f1` answered `root` and
  then `n`, `wc -l` counted two lines where there was one, and a `$(...)` around a
  long line came back with a break in the middle of it. Now the width is applied
  where it belongs, on the glass and nowhere else: what a pipe, a redirect, a
  `tee` and a command substitution carry is the line exactly as the command wrote
  it, however long. What you see on the screen has not changed.

- Every hardware module (Magnetic Contact, Relay, Electric Strike, Door
  Operator, Curtain Motor, Window Operator, Appliance Switch, Generator
  Switch, Tuner Control) now looks the same small circuit board when
  dropped on the ground, instead of some of them looking like scrap metal.
- Right-clicking a fixture with CeroSec hardware on it now shows one entry,
  "CeroSec: Door" (or Window, Stove, Microwave, and so on), instead of two
  separate menus fighting for the same spot. Hovering it, or a row inside it,
  highlights the fixture; opening "Link to computer" and hovering a line to a
  named machine highlights that computer instead, never the fixture.
- Every CeroSec entry at the top of a menu now carries a small green terminal
  icon, so the mod's own lines ("Turn on/off/use computer", a fixture's
  "CeroSec: Door", "CeroSec (dev)") are told apart from vanilla's at a glance.
  Nothing inside a submenu grows one.
- CeroSec and the Workshop mod *Computer Mod* can be subscribed together now.
  Both put a machine on the same eight desktop computers, and their menu turned
  the screen off again on the first right-click after you had switched a machine
  on, with your session still running behind a dark screen. A desktop now belongs
  to the mod that booted it, until it is switched off: switch one on with CeroSec
  and it stays a CeroSec machine, boot it with theirs and it stays theirs, and
  the two menus are both offered on a computer nobody has started. The limit,
  said plainly: while a computer is running under one of the two mods, the other
  mod's entries are not on its menu, so their CD games and their 486 parts want a
  machine you have not booted with CeroSec. Choosing between the two systems on
  one machine, at boot, is meant for a later release. When two computers share
  one tile, only CeroSec's menu shows on that tile. Nothing changes in a game
  without that mod.

- A machine set down outside a house is no longer on that house's network
  either. A computer you carry out of a building keeps the address it was given
  there, because somebody may have written it in /etc/hosts, and it used to keep
  the WIRE with it: parked on the pavement, arp showed it the machines still
  inside, and rlogin, rcp and ping all worked. Drop a looted computer in the
  street and you were on the household's Ethernet. To be on a building's cable a
  machine now has to be standing in that building. Two computers carried out of
  the same one and set down together, in a base you built or on the same verge,
  are on a wire again within ten tiles of each other and on nobody else's, so a
  camp made of looted machines still works. Nothing is renumbered: no address and
  no netmask changes. The radio went the same way, a computer on a pavement is no
  longer wired to the set on the other side of the wall.
- A machine set down outside a house no longer sees that house. A computer
  standing on the ground with no building around it reaches ten tiles, which is
  what a base you built yourself is made of; those ten tiles were taking the
  doors, the windows and the porch lamps of any map house that happened to be
  inside them, for free and with nothing wired. Somebody could drop a computer
  on your pavement and open your front door. From outside, a building's fixtures
  now cost a cable, exactly as the manual always said. A machine INSIDE a
  building still reaches the whole of it, and a base with no building still
  reaches everything in its ten tiles.
- With **Modules in safehouses** on, a stranger can no longer cable the front
  door or the windows of a house somebody has claimed. A door is part of the
  wall and stands on the tile OUTSIDE the room, which is a tile no safehouse
  claim covers, so the refusal was never being asked about it. The porch lamp of
  a claimed house is still open to anybody: it hangs on the outside wall and
  there is nothing on it to say which house it belongs to.
- A motion sensor set down outside, against a house wall, no longer sees
  through that wall. A sensor with no room of its own already watched its
  three tiles in every direction; it was also picking up a room next door for
  free. It still watches its own three tiles outdoors, just never the tiles a
  wall is standing between it and.
- A street lamppost you have cabled can be switched now. It read `on` and then
  answered `no power` to every order, with the grid up and the lamp burning:
  the game refuses to let a hand flip a light that stands outside on no floor
  of any building, and the machine was passing that refusal on as if the
  current had gone. A relay on the post is what your hand is not. With the grid
  down and no generator, the lamp still answers `no power`, because then it
  really has none.
- A computer's power switch is mechanical now, the way an old AT machine's was.
  One left switched on when the power dies comes back on its own the moment the
  wire is live again, no hand needed: BIOS, any `@reboot` job, all the way to a
  bare `login:` prompt. One you turned off on purpose, at the machine or with
  `halt` or `shutdown`, stays off no matter how many times the power returns.
  A `reboot` that loses the room's power in its three dark seconds is the first
  case: the machine comes up when the wire does, though nobody's window comes
  back with it.
- The tooltips on CeroSec's own menu entries read properly again. They were
  losing a word wherever a line was meant to break, and running the next
  sentence straight into the one before it without a space. A greyed entry now
  says why it is greyed on a line of its own, in red.
- A cable can be cut again after the computer at the other end of it has been
  carried off its tile. A run is to the spot the machine stood on, not to the
  machine, so putting a computer back on that spot reconnects it; before this,
  "Unlink" on a cable going nowhere did nothing at all and the wire was lost.
- That same cable, with no computer standing on the spot it runs to, now reads
  "Unlink loose cable" and says how far off the machine used to be. It used to
  print a made-up hostname for the empty tile, which read like the machine had
  been renamed.
- A door, window or curtain can only be cabled to a computer, or cut from one,
  the way a module is fitted to it or taken off it: open, drawn or from the
  right side. A closed front door can no longer be wired, or unwired, from the
  street.

## 0.4.0 - 2026-09-16

The automation update. Nothing here needs a new save: machines you already
switched on keep everything, and the notes and modules already in your bags are
left exactly as they are. The one thing you will notice on a save you already
have is the price of the next electric strike and door operator -- both cost a
Small Motor and a Receiver now, and what you have already built is untouched.

- **The hardware menu tells you what a box is, and what you are missing.** Every
  line now says what the module does, which `/dev` it gives and the Electricity it
  wants -- and the list shows **every** box that could go on that sort of fixture,
  whether you are carrying one or not, so you can find out a curtain motor exists
  before you own one. A box you have not got is greyed with *You are not carrying
  one*, or with the line that sends you to the **CeroSec Field Wiring Guide** if
  you have not read it. What is gone from the list is the noise: a module that
  could never fit that sort of fixture -- a curtain motor on a light switch -- is
  not a greyed line any more, it is no line at all, and a fixture with nothing to
  offer has no **CeroSec hardware** entry over it.

- **Modules go on from inside, with the door open.** A magnetic contact, a strike,
  an operator, a curtain motor or a window operator is fitted -- and taken off --
  only from **inside** the building: stand on the pavement and the entry is greyed
  with *This has to be done from inside*. Otherwise anybody walking past could
  strip the hardware off your front door without ever coming in, which is what
  this is really about. An interior door has rooms on both sides and is wired from
  either. A **generator** is the one exception and takes its switch outdoors,
  where a generator belongs.
- **And the thing has to be at rest.** A door or a window has to be **open**, a
  curtain or a door's sheet **drawn back**, and a stove, a washer, a dryer, a
  television, a radio set or a generator **switched off** -- each with the line
  that says what to do about it. A light switch asks for nothing: the plate comes
  off with the light burning. Removing a box asks exactly the same as fitting one.
- **A new sandbox option: Safehouse members only**, and it is **off**, which is
  the way it was before. Turn it on and a door, window, light, appliance or set
  standing inside a safehouse takes a module -- and gives one back -- only for
  somebody that safehouse allows: its owner, its members, and an admin. It is for
  a server where stripping a rival's hardware out of his own hallway was the
  sabotage nobody wanted. Looting rules are not consulted either way: fitting a
  module is not looting. Single player has no safehouses, so it does nothing
  there.
- A building **already wired** before the outbreak is untouched by all of this:
  its relays and contacts are written with the world and were never anybody's
  gesture.
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
