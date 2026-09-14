# CeroSec -- the ten screenshots

What the Workshop page needs, in the order the description uses them. The
maintainer takes them; `workshop/workshop.txt` already carries a commented slot for each,
named with the filename below, and the slot becomes a `description=[img]...[/img]`
line once the shot is uploaded and has a URL ([RELEASE.md](../docs/RELEASE.md)).

Write them to `workshop/shots/NN-name.png`. That directory is not in git: the
files are big, they go to Steam and not into the mod, and the page references
them by URL.

## Settings for every shot

Set these once and do not touch them between shots, or the ten will not look
like ten pictures of one thing.

| | |
| --- | --- |
| resolution | **1920x1080**, borderless window. Steam scales a description image to 630 wide, so 1080p downsamples to it evenly. |
| UI scale | **1.0** for the world shots (3, 4, 5), **1.5** for the terminal and reader shots (1, 2, 6, 7, 8, 9, 10). The terminal is 60x20 characters and at 1.0 on a 1080p screen it is a stamp in the middle of the frame. |
| zoom | **one notch in from the default** for the world shots, so a door and the survivor at it are both in frame. Terminal shots: whatever, the window covers it. |
| time of day | **between 20:00 and 04:00** for every shot with a screen in it. The phosphor is the whole look and it does not read against daylight. Shot 5 is the exception: **dusk**, so the door and the module in hand are legible. |
| weather | **clear**. Rain puts a grey wash over the glass. |
| lighting | the room's own lights **on** where there is power, so the scene is not a black rectangle around a green one. |
| sandbox | a save with `CeroSec.PrefilledMachines` **on** (the default) and `CeroSec.HardwareRequired` **on** (the default). The page describes that world; the screenshots have to be of it. |
| before shooting | turn the two dev flags **off** first (`docs/RELEASE.md` step 3). A screenshot with **CeroSec (dev)** in a right-click menu is a screenshot of a build nobody is getting. |
| crop | none. Full frame, PNG. Steam does the scaling. |

## The ten

### 01 `01-boot-login.png` -- the hero shot

The terminal, just switched on, on the BIOS screen with the login prompt under
it. This is the first image in the description after the banner and it is the
one that has to say "this is a real machine" in one look.

- **Scene:** an office or a dispatch room, at night, lights on, the survivor
  seated at the computer.
- **Must be visible:** all five BIOS lines including **Ethernet: eth0** with a
  real address, **Phone line:** with a real number and the premises name in
  brackets, **Callsign:**, then the hostname and `login:` with the cursor.
- A machine in a building the map has named, or the phone line is missing and
  the best line on the screen is not there.

### 02 `02-shell-session.png` -- it is a real shell

A worked session. Not a wall of text: six or seven commands whose answers are
short and obviously real.

- **Type, in this order:** `whoami`, `ls -l`, `cat notes.txt`, `ps`,
  `ls -l /dev | head`, then leave the prompt sitting empty with the cursor on.
- **Must be visible:** an `ls -l` line with real modes, owner and group; at
  least one `c` device line in `/dev`; the `$` prompt with the hostname in it.
- Do it as an ordinary account, not `root`. A `#` prompt invites the wrong
  question. On a prefilled machine there is no `admin` to use — it is one of the
  premises' own staff logins, off the paper in the drawer — so either shoot it on a
  bare machine or log in as the shop's own man.

### 03 `03-computer-menu.png` -- how you get in

The right-click menu open on a desktop computer, so nobody has to ask how the
mod is used.

- **Must be visible:** **Turn on computer** / **Use computer**, and **Insert
  floppy** underneath with a labelled disk in the bag so the entry is live.
- Survivor standing beside the desk, the computer's own tile clearly the one
  under the cursor.

### 04 `04-dev-and-a-door.png` -- the building is under /dev

The one that explains what this mod is for. Split attention on purpose: the
terminal on one side, the door it is talking about on the other.

- **Type:** `dev`, then `dev find door1`, then `dev door1 open`.
- **Must be visible:** the `dev` table with a `door`, a `light` and a `lock` in
  it; the **outline the game draws on the real door** from `dev find`; and the
  door standing open in the same frame as the line that opened it.
- Move the terminal window to one side of the screen first so the door is not
  behind it.

### 05 `05-fitting-a-module.png` -- hardware, not magic

Right-click on a **door**, not on the computer, with the **CeroSec hardware**
submenu open.

- **In the bag:** a Magnetic Contact, a Relay Module, an Electric Strike, a
  Door Operator, and a Screwdriver.
- **Must be visible:** at least one live **Install** entry and at least one
  **greyed** one with its reason on it. An interior door gets the strike greyed;
  a garage or double door gets the operator greyed. Stand at one of those.
- **Dusk**, so the door and the survivor read.

### 06 `06-the-manual.png` -- a manual you have to find

The reader open on Volume 1, on a page with a command table on it.

- **Must be visible:** the **Contents** / **< Back** / **Next >** controls, the
  volume's title, and the survivor still standing behind the panel doing
  whatever they were doing. That last part is the point of it.
- Open **Volume 1, the User's Guide**, not the Programmer's. A page of prose
  with a short table beats a page of syntax.

### 07 `07-somebody-elses-machine.png` -- the county had computers

A prefilled office or dispatch machine, plus the paper that opens it.

- **Type:** `cat /etc/motd` (or let the motd stand from the login), then
  `tail /var/log/messages`, then `crontab -l`.
- **Must be visible:** a motd that is clearly somebody's; log lines dated the
  week before the outbreak; a real crontab line. **And the inventory panel open
  beside it with `Sticky note: root / falcon12` in it** -- the name of the item
  is the password, and one frame showing both is the whole mechanic.
- Use an **office** or **police** machine. A residential one has nothing locked
  and nothing to show.

### 08 `08-floppy-disk.png` -- carry it across town

A disk with something on it, mounted and read.

- **Type:** `mount /dev/fd0 /mnt`, `ls /mnt`, `cat /mnt/README.TXT`.
- **Must be visible:** the disk's own **label** in the inventory panel (a real
  one: `UTILITIES`, `BBS LIST`, `GAMES`, `BACKUP`), the capitals of the DOS-era
  filenames, and the first screen of the README.
- If the drawer rolls blank disks all evening, the labelled ones are seventeen
  in a hundred. Keep looking or use a `BACKUP`.

### 09 `09-the-building-network.png` -- the machine next door

Two computers of one premises, one session reaching the other.

- **Type:** `arp`, `ruptime`, then `rlogin` to the other machine and `hostname`
  on the far side.
- **Must be visible:** two different `10.x.x.x` addresses; the prompt **changing
  hostname** after the `rlogin`, which is the proof that the second machine is
  really running it; and if the room allows, **the second computer in shot**
  behind the window.
- A shop in a mall, an office with two desks, or a dispatch room. Not a house.

### 10 `10-telephone-and-radio.png` -- past the building

The two links that leave the premises, in one frame.

- **Type:** `cu 555-0417` and let it answer, then `~.` out, then
  `cu -l /dev/radio0`, `MYCALL`, `C KE4QWZ`.
- **Must be visible:** the modem's own **CONNECT 2400**, the **TNC-200** banner,
  and `*** CONNECTED to` with a callsign. A two-way radio has to be in the room
  and switched on or there is no `/dev/radio0`.
- **If it will not fit in one screen**, this is the shot to split: take the
  phone half, then open a **Phonebook** from the inventory (*Look up numbers*)
  and shoot the yellow pages beside the terminal instead of the radio. The
  directory is the better picture of the two.

## Two short GIFs

Under 4 MB each, 8 to 10 frames a second, no longer than eight seconds, and
they loop. Both are cut from OBS at 1920x1080 and scaled to 630 wide, which is
the ceiling Steam shows them at anyway.

### G1 `g1-power-on.gif` -- six seconds, the whole loop of using one

Right-click, **Turn on computer**, right-click, **Use computer**, the survivor
walks over and sits, the BIOS counts down, the login prompt arrives, the login
typed (`admin` on a bare machine, the premises' own man on a prefilled one),
Enter, the motd. Nothing typed after that. It answers "what do I actually do
with this" before anybody asks it in the comments.

### G2 `g2-the-lights.gif` -- five seconds, the mod's whole argument

A dark shop floor with its lights on, the terminal open to one side. Type
`dev light0 off`, press Enter, **and the room goes dark in the same frame**.
Then `sh lights.sh` and let the script walk both of them. One take, no cut: the
cut is what would make it look faked.
