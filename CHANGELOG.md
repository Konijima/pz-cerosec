# Changelog

Player-facing notes, one entry per Workshop release. Every change adds its lines
under **Unreleased** in the words a subscriber reads, not the words a commit
reads. At release, `python3 tools/changelog-steam.py` prints the newest section
in the shape Steam's Change Notes take, and the section gets its version and
date.

## Unreleased

## 0.7.0 - 2026-09-23

A computer that opens with a left click, an editor that no longer stops at the
edge of the screen, three new cabling options for servers, and a shell that behaves
much more like the real one. Nothing here needs a new save: no state or system
version moves, and every new option is off, or set to the reach a cable always had,
until a server owner changes it. What a world you already have can notice is in the
shell: a script you saved that used `echo "a\nb"` now prints the two characters
`\n` (use `printf`), a `cp` onto a file that is already there now writes over it,
and a command whose redirect is refused no longer runs.

- A shell function can be defined without a space before the brace, as in
  `t(){ echo a; }`, like on any sh.
- The shell has `set` (`set -- a b` for new `$1 $2`, `set` alone to list the
  variables), `unset` and `unset -f`, `exec`, and `trap '...' EXIT` to clean
  up when a script ends. `${x:-default}`, `${x:=...}`, `${x:?...}`,
  `${x:+...}`, `${#x}` and the `${x#...}`, `${x%...}` trims work, `${1:-...}`
  and `${10}` too. A variable you did not `export` no longer leaks into the
  commands of a pipeline (`Q=1; env | cat`).
- A computer that's already on now opens with a left click, same as the
  menu's Use computer.
- The editor no longer refuses a line wider than the screen. It wraps onto the
  row below and scrolls to follow you, like a real terminal, instead of
  stopping your typing dead at the sixtieth character.
- The editor now shows a line number down the left of every row, like `vi
  -- :set number`. A wrapped row's number stays blank, so it can't be
  mistaken for a new line.
- Running a cable to a fixture in your own basement, or from the basement to
  the house above it, no longer costs any wire. Some basements are drawn on
  the map as their own building rather than part of the house's, and a
  computer down there could see only its own switches; the cable between them
  is still needed, but it's free now, the way running wire down to your own
  basement should be -- and it's offered however many floors apart the two
  are, whatever the cable range.
- Two new server options, both off by default. **Cabling required indoors
  too** (`CeroSec.RequireWiring`) turns off the free ride a computer's own
  building normally gives it: nothing is in `/dev`, inside or out, until a
  cable has actually been run to it. **Cabling costs nothing**
  (`CeroSec.FreeWiring`) leaves the wire in your bag wherever a cable is
  needed, without ever buying extra reach -- the cable range stays exactly
  what it was, and `dev find` still says such a device is linked. Under
  **Cabling required indoors too**, a shop that was automated before the
  outbreak comes with its cables already run, as far as the cable range
  reaches -- and a shop you first found dark gets them the moment you bring
  it power and switch its computer on. A shop already wired before the
  option was switched on doesn't: its fixtures wait for a cable like any
  you fitted yourself.
  Fixed: with **Hardware required** off, the "Link to
  computer" submenu could vanish entirely with no way to get a bare fixture
  onto `/dev` at all -- most completely under **Cabling required indoors
  too**, but also for a generator, an outdoor fixture, a fixture in another
  building, and a basement built as its own separate lot: none of those were
  ever covered by the free ride in the first place. Every one of them is
  cabled now, same as a fixture that carries a real module always was.
- New server option, **Cable range, in tiles** (`CeroSec.LinkRange`), thirty
  by default -- the same reach a cable has always had, and forty-eight at
  most. A server can raise it
  to cover more of a building off fewer machines, or lower it to spread
  computers out. Lowering it never strips a cable already run: only a new
  one feels the change.
- A command whose redirect is refused no longer runs. `rm notes > /etc/x`
  used to say "permission denied" and delete `notes` anyway; now the shell
  opens the file first, like a real one, and nothing happens. The other side
  of it: `cat nosuch > out` now leaves an empty `out` behind, as on any Unix.
- `2>` works: `cat nosuch 2>/dev/null` says nothing, `2>errors` keeps the
  errors in a file, `> log 2>&1` puts both in one, and `echo oops >&2` sends
  a line where errors go. `cat f 2>/dev/null` no longer looks for a file
  named `2`.
- A function or script with its own redirect in a pipeline now writes to
  its file and not down the pipe: `g > out | wc -l` fills `out` and counts
  0, as in a real shell. The redirect used to be ignored there, leaving
  `out` empty; `>>`, `2>`, `2>&1` and `>&2` on such a call now work too.
- `echo a > f | true` now leaves `a` in `f`. A command in a pipeline was
  stopped before it ran when the command after it finished first, so its
  file was never made; now every command in a pipeline gets to run, and one
  writing into its own file is not stopped at all.
- `x=$(g > f)` now puts what `g` prints in `f` and leaves `x` empty, as in
  a real shell. A function's or script's own `>` or `>>` used to lose to
  the `$( )`, leaving the file empty.
- `$( )` no longer catches error text. `x=$(cat nosuch)` shows the error on
  the screen and leaves `x` empty; write `x=$(cat nosuch 2>&1)` to catch it.
- A backslash inside double quotes now stays put unless it's in front of `$`,
  a backquote, `"` or another backslash, as on a real sh. `grep "a\.c"` now
  finds `a.c` and no longer `abc`, and `echo "C:\dos"` prints `C:\dos`. The
  shell no longer turns `\n` into a new line or `\t` into a tab: that is
  printf's job, and `printf "a\nb\n"` works as before. A script you already
  saved that used `echo "a\nb"` now prints the two characters `\n`; change
  it to `printf "a\nb\n"`.
- `read` takes several names: `read cmd rest` puts the first word in `cmd` and
  the rest of the line in `rest`. Plain `read` now takes a backslash away and
  keeps the character after it, as a real sh does (`a\ b` is one word, `a b`);
  `read -r` keeps backslashes as typed. `read -n 3` keeps three characters
  instead of only one, and reading from a pipe it leaves the rest of the line
  for the next `read`, as bash does.
- `cp` onto a file that's already there now writes over it, like a real cp,
  and the file keeps its owner and mode. `cp f f` says "are identical".
- `ls` takes several names at once, and `ls /etc/passwd` now prints
  `/etc/passwd` as typed.
- `cat -` reads the pipe among files (`echo top | cat - notes`), `cat -n`
  numbers the lines, and `--` ends the options.
- A `[` missing its `]`, or `sleep abc`, no longer stops a script: the error is
  printed, `$?` is 2 (or 1 for sleep), and the script carries on. Their
  errors go where errors go: `2>/dev/null` hides them, and they no longer
  land in a `> file`, a `$( )` or down a pipe.
- `$?` after "command not found" is now 127, and 126 for a file you may not
  run, so a script can tell "failed" from "wasn't there".
- `$*` and `$!` work, and a bare `$@` splits its words like `$*`. `x=$@` and
  `x="$@"` with two arguments or more no longer break the script: `x` gets
  them joined by a space. A new login starts with an empty `$!`.
- A file a function or script wrote through `>` or `2>` is complete for the
  very next command: `f > out; wc -l out` no longer counts short.
- A script left running by 0.6.x in the middle of a command writing to a file
  goes on adding to that file under 0.7.0 instead of emptying it again.
- The manual's "What is not Unix here" pages are now the complete list, and
  checked both ways against the machine: every difference from a 1993 Unix
  that is kept is on them, and nothing on them is untrue. New are the file
  that ends without a newline (`echo a > p` is one byte), `IFS` not being
  read, `read -p/-s/-n` and `!!` being later shells' words, the passwd file,
  the `#` prompt, the error wording, a pipe stopping its left side as soon as
  the right side is done (`sleep 5 | true` ends at once), and the commands and
  flags that are not here (`set`, `rmdir`, `rm -f`, `kill -9`, `tail +N`,
  printf widths, `sh -c`). The
  error appendix also gained grep's pattern errors, `passwd: permission
  denied`, `export: not a name` and `wait: too many jobs`.

## 0.6.1 - 2026-09-21

Doors that close on cars and a keyboard nobody else could hear. A garage door, a
double door or a gate worked from a computer now refuses on a car in its way the
way the hand's own switch does, including a car somebody is driving, and the
keyboard at a terminal is heard by the players standing near it. Nothing here
needs a new save: no state or system version moves and no sandbox option is
added.

- A garage door no longer closes on a car somebody is sitting in. On a server the
  game does not know where a car it is driving really is (it remembers the place
  where the driver got in), so a script such as `autoclose.sh` could shut the door
  on the car -- and send it underground -- while the same script refused to close
  it with the car standing several tiles away. The machine now works the car's
  outline out from where the car is, so it refuses exactly when the car is in the
  doorway and only then. Two parked cars on either side of a door, neither across
  it, no longer keep it open either.
- A double door or a gate opened or closed from a computer now refuses on a car
  standing where its leaves stand or swing -- parked, or with somebody driving it --
  the way the hand's own toggle does, instead of moving through it. A car
  driven away from a gate no longer keeps it refused.
- The keyboard at a terminal is now heard by the players standing near it, as it
  was always meant to be: the clicks were played only on the machine of the
  player at the keyboard, so nobody else ever heard somebody type. The clicks are
  quiet, so somebody more than six tiles away still hears nothing. On a server,
  at most one click in every fifth of a second is sent to the others -- a fast
  typist is heard typing, not click for click -- and the typist always hears
  every key at once. Nothing new is sent in a single-player game, and the
  keyboard still makes no noise a zombie can follow.

## 0.6.0 - 2026-09-20

Doors that were out of reach and a restart that no longer costs a server its
scripts. Double doors, garage doors and yard gates now take a module like any
other door, and a dedicated server that is started and stopped with nobody on it
keeps every running script. Nothing here needs a new save: no state or system
version moves, and the new sandbox option is off unless a server owner turns it
on. A server owner whose world lost its `autoclose.sh` in an empty restart still
needs one `reboot` on that machine to start it again.

- Double doors and garage doors can now take a door operator and be opened and
  closed from `/dev` (`dev door0 open`), and locked and unlocked from `lock`
  with a strike. Each one is a single `door` and a single `lock` however many
  leaves it has, all the leaves move together, and the number does not change
  when the door is worked. A door still says `barricaded`, `locked` or
  `blocked` the way a hand would meet them. Before, a computer refused to work
  either kind.
- A server that was restarted while nobody was connected no longer forgets its
  running scripts. With the "pause when empty" server option on, a server that
  came up and was stopped again with nobody on it wrote every machine down with
  nothing running, so `autoclose.sh` and every `@reboot` daemon were gone the
  next time a player joined. The scripts are now kept until the server next
  writes them down. A script somebody stopped still does not come back.
- A door, window or curtain with open air on both sides, such as a yard gate,
  now takes a module (a door operator, a strike, a contact). It used to say
  "This has to be done from inside" on a door that has no inside. One with a
  room on either side still has to be fitted from inside, so a front door cannot
  be stripped from the pavement.
- A new sandbox option, **Log the mod to the server console**
  (`CeroSec.ServerLog`, off by default), for a server owner who has to find out
  why something went wrong and cannot edit the mod. On, everything the mod says
  about itself is also written to the server console as `CeroSec:` lines: every
  saved job that was dropped or refused when the world loaded, how many of a
  machine's saved jobs came back, a saved book ignored because its machine was
  off, and every machine switched off for lack of power. It is safe to leave on
  while you hunt a bug, and turning it off changes nothing else.

## 0.5.1 - 2026-09-19

- A dedicated server now keeps its running scripts across a restart. The game's
  server saves the world without telling the mod, so the scripts were never
  written down and every daemon (`autoclose.sh`, `autolock.sh`) was gone after
  the server came back. The server now writes them down every five seconds; a
  script resumes at the step it had reached at most five seconds before the
  server stopped. Singleplayer and a hosted game were not affected.
- A script that is in the middle of a pipeline when the game saves now comes
  back at the very step it was on. `autoclose.sh` running `ls /dev | grep
  ^door` at the moment you quit used to be left out of the save and gone on
  the next load; it is kept now, and a pipeline's sleeping stage keeps what
  is left of its sleep. Running scripts also weigh a third of what they did
  in the save, so several daemons fit together comfortably.
- The printed manual no longer says that loading the world again leaves a
  machine running nothing. A program left running with `&` is kept across a
  save and a load; the manual now says so, and lists what is not kept.
- The shell expands `*`, `?` and `[...]` in an unquoted word against the
  files that are actually there, sorted, the way a real sh always has --
  `cp -r /mnt/* /usr/local/bin` now copies what the floppy holds instead of
  failing on the literal word. `cp` and `mv` also take more than one source
  when the last argument is a directory.
- The shell reads `` `command` `` as a command substitution again, the same
  as `$(command)` -- `for f in `ls /mnt`; do cp -r /mnt/$f /usr/local; done`
  used to copy nothing at all, the backquotes read as two stray characters.
- The printed manual (Volume 3, chapter 10) now carries a table of every
  /dev kind and the words it takes, and says plainly that a lock is its own
  node beside its door's, not a second word the door answers to.

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
- **Link to computer no longer lists a computer this fixture already answers
  to.** A cable already run there would only have bought a second entry for
  the same machine, so the line is gone rather than greyed; its **Unlink from
  ...** line at the bottom of the menu already says the fixture is wired to it.
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
- **One CeroSec entry per fixture now comes after that fixture's own options,
  not before them.** Right-click a door, a window, a light switch or anything
  else with a module on it and Open, Turn on and the rest of the game's own
  lines lead the menu the way they always did on everything else; **CeroSec:
  Door** and its **Link to computer** read after them. The computer itself is
  unchanged: **Use computer**, **Turn on** and the drive still lead its own
  menu, and so does everything on a floppy or a manual in your inventory.
- **Interface: the CeroSec entry only shows when you can do something: a
  module you carry and have the skill for, or one already fitted.** A door,
  switch or other fixture you have never put a module on, and have no module
  in your bag for, no longer grows a "CeroSec:" entry at all; a module you do
  carry but have not yet got the skill for still shows, greyed, once that
  entry is open for another reason. A cable left running with no module on
  the fixture any more still opens the entry, so "Unlink loose cable" is
  never out of reach.
- **Generators are no longer found by proximity: fit a Generator Switch and
  run a cable.** A generator used to show up on a computer's `/dev` just for
  standing in the building or within its outdoor radius, the same as a light
  switch or a door -- which meant a computer could start or stop a generator
  it had no wire to at all. Now it takes a **Link to computer**, exactly like
  a lamppost. **If a save already had a generator on `/dev`, it drops off the
  list until you cable it** -- your `crontab` lines and scripts for it are
  untouched and pick up again the moment the cable is run.
- **A note's login and password always match the machine it names; two
  accounts could share a name and the second overwrote the first's
  password.**

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
