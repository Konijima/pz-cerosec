# CeroSec — Network

Three links, one command surface: coax inside a premises, the phone across the
county, and radio to whatever is in earshot. Identities and their derivations,
each link's own rules and rates, the pty a remote session lives on, and where
every result string a player reads actually comes from.

See also: [PLAYERS.md](PLAYERS.md) for `ifconfig`/`ping`/`rlogin`/`cu` as a
player uses them, [PROTOCOL.md](PROTOCOL.md) for whose screen a remote order
writes to and the terminal rule for `rlogin`/`rsh`, [SECURITY.md](SECURITY.md) for
the security angle on trust files.

## Ethernet, and the machines of a premises

Every computer on a **premises** is on one length of coax with the others, and it
has an address it did not choose: `10.<b1>.<b2>.<n>`, where the first two bytes
come from where the premises is and the last is which computer of it this is.

**A premises is not a building.** A house is one building and one premises; a
shopping mall is one building and thirty shops, and each shop is its own -- its own
segment and its own telephone line. Which it is comes out of the map data and is
decided in one place (`CeroSecNet.premisesOfSquare`), in this order:

> 1. the named `ZombiesType` zone containing the machine's square whose area
>    (`w*h`) is strictly smaller than the building's own footprint
>    (`(x2-x)*(y2-y)` of its `BuildingDef`) -- the **smallest** such zone when
>    several qualify;
> 2. else, if the building holds **two or more tenancies**, the square's own
>    tenancy;
> 3. else the building itself.

**Rule 1: the zone, which is the map's own word for a tenancy.** Map designers tag
some shops with small named `ZombiesType` zones -- `CoffeeShop`, 17 by 11, at
12858,1329 -- because that is how the spawner is told what kind of dead belongs in
a shop. The area test is the whole of what tells a tenancy from a region: the named
zones a *house* sits in are the other kind -- a suburb, a district, a whole town --
all of them bigger than the house. A zone exactly the building's size is the
building under another name and loses on the same test.

**Rule 2: the rooms, because the shipped malls have no zones.** This is what a
report from play said, in the words it came in: *they all share the same no matter
what the store is, because it's all one big building; the music store computer and
the dentist one have no specifics.* They did. So where no zone says otherwise, the
rooms are asked instead.

A `RoomDef`'s name is a **loot type** (`clothsstore`, `kitchen`) and says nothing
about tenancy, so which names mean a shop is a short and deliberate list
(`CeroSecContent.TENANCY_WORDS` and `TENANCY_TRADES`) rather than a guess:

> a **shopfront room** is one whose name carries `store`, `shop` or `market`, or is
> one of the trades the map spells out instead (`dentist`, `optometrist`,
> `pharmacy`, `bakery`, `butcher`, `cafe`, `diner`, `restaurant`, `bank`,
> `pawnshop`) -- never one whose name carries `storage` or `counter`, and never a
> room of a single tile.
>
> a **tenancy** is a maximal group of shopfront rooms with the **same name**, on
> **one floor**, that share a wall.

One shop is very often several `RoomDef`s -- a furniture shop in eight rooms, a gas
station's four pump islands -- while the seven rooms called `clothesstore` in seven
corners of one mall are seven shops, which is why the name alone will not do. And a
building with **one** tenancy is the building, deliberately: a gun shop with a back
office and a stock room is one business, and splitting its stock room off it would
be a worse bug than the one this fixes.

A square that is not in a shopfront room gets the tenancy it shares its **longest
wall** with -- the shop whose stock room, bathroom or break room it is -- except for
the common parts (`hall`, `corridor`, `lobby`, `elevator`, `stairwell`...), which
are nobody's: a mall corridor is not the shop it happens to share its longest wall
with, and every shop is off it.

**Every one of those rules was counted against the shipped county before it was
written**, and four earlier candidates were thrown out for what they did to it --
the numbers, the four rules and the `javap` behind `RoomDef` are
[docs/notes/tenancies.md](notes/tenancies.md). The one that ships calls 143 of the
county's 9546 buildings multi-tenant, and they are the malls and the strip malls.

**The two bytes** come from `CeroSecOS.buildingKey(bx, by)` for a building,
unchanged, so **existing saves keep their addresses**; from
`CeroSecOS.premisesKey(zx, zy, zw, zh)` for a zone, which is the same arithmetic
over four numbers -- the corner hashed as a building corner is, the size hashed the
same way, and the two added; and from
`CeroSecOS.roomKey(bx, by, rx, ry, level)` for a tenancy, which is the same
arithmetic again over the building's corner, the tenancy's own corner and the
floor. The size has to be in the zone's key: a zone's corner is very often the
building's own, and a key made of the corner alone would *be* the building's. The
floor has to be in the room's, for the same reason one floor up: a shop with a
mezzanine is one name on one corner on two floors.

**Not `RoomDef.getID()`**, which is right there and looks made for this. The low 32
bits of that id are how many rooms were already registered in the map cell when the
lot header was read, so it moves if a map mod touches the cell -- and
`NewMapBinaryFile.SpawnBasement` advances the same counter *during play*. The
offsets are in the note. A save whose addresses moved because somebody installed a
map is exactly what this rung must not do.

Every engine call this needs is `javap`'d on `projectzomboid.jar` 42.20.4:
`IsoWorld.getMetaGrid()`, `IsoMetaGrid.getZonesAt(int,int,int)` (an
`ArrayList<zombie.iso.zones.Zone>`), `Zone.getName/getType/getX/getY/getWidth/getHeight`
(plain `getfield` on `name`, `type`, `x`, `y`, `w`, `h`),
`BuildingDef.getX/getY/getX2/getY2/getRooms`,
`RoomDef.getName/getX/getY/getX2/getY2/getZ/getArea` (all six ints plain field
reads, so `x2`/`y2` are exclusive and `getZ` is the floor) and
`IsoGridSquare.getRoomDef`. The getters and not the public fields, which is what
the game's own Lua does (`shared/Traps/TrapSystem.lua:12-17`).

**Migration, and there is no step for it.** A net record written before the line
belonged to the premises carries the *building* bytes and no exchange; one written
in a mall carries the building's bytes because that is what a mall was. Either way
it is rebuilt when the machine's square is loaded -- the two moments
`CeroSecNet.identify` is called, switching on and opening a window -- and the
machine is renumbered onto its shop's own segment and its shop's own line. That is
the same path a machine carried into another building has always taken, and it
cannot be a step in `CeroSecOS.MIGRATIONS`: a step is handed a table and no world,
and which shop a computer stands in is a question only the world can answer.

Until the square is answerable such a machine has an address and **no telephone at
all**: an empty BIOS phone line and `cu: no phone line`. What does *not* change is
anything already written on the disk -- the accounts, the passwords and the papers
in the drawers were derived at prefill and are stored hashed -- so **the root note
somebody found in that mall still opens the machine it was written for.** The
numbers in a mall change once, and the release notes say so.

The record carries which of the three the bytes came off (`pk`, one of `zone`,
`room`, or absent for the building) beside what the premises is called (`pz`). Both
are labels: no link reads either, and nothing is keyed by them.

The BIOS announces the address between the drive and the login, `ifconfig` prints
it any time, and nothing sets it -- the address is a fact about the card the way
the hostname is a fact about the machine. A computer in a base **you** built is on
no premises the map knows about, so it has no wire at all and says so:
`eth0: flags=2<BROADCAST>` with no address under it.

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
address no line of `/etc/hosts` names yet. The wire is the premises's, so the
shop next door is not on it: `ping bakery` from the coffee shop is
`100% packet loss` and `rlogin bakery` is `No route to host`, and the telephone is
what reaches it.

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
machine that trusted one would let anybody with root on any computer on the
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
house is one number and a mall is thirty -- which is the fix for the two things one
line per *building* got wrong: thirty businesses shared one number, and only the
lowest-numbered computer of the whole mall could ever be rung.

The number is seven digits, `NNN-NNNN`, which is what a call inside one area code
was dialled as in 1993:

- the **exchange** is the first three and it is a fact about the *town*: the
  `CeroSecOS.PHONE_REGION`-tile map region the premises corner falls in, hashed, so
  every subscriber around here shares it and the next town is on another switch.
  200 to 999, because a central-office code could not begin with 0 or 1 in the
  North American plan of 1993. A region and not the game's own 300-tile cell: a
  cell is smaller than Rosewood and every town would be three exchanges.
- the **four digits** are the premises, derived from the same two bytes the
  address's middle is made of, so nobody can type a new one.

The exchange is the one thing that cannot be derived from the record -- a region is
a coordinate and the record has none -- so the record carries it as a field
(`ex`), written when the machine learns where it is standing. The record also
carries what the premises is *called* (`pz`), and that is a label only: no link
reads it and nothing is keyed by it.

The firmware announces the number under the card, and that BIOS screen is the
**only** place it is written -- there is no `/etc/phone` -- with the premises name
behind it when the map gave it one and the line fits the screen:

```
Phone line: 555-0417 (CoffeeShop)
```

A computer in a base you built is on no premises the map knows, so it has no line:
`cu: no phone line`. Neither has a machine off an older save until its square is
loaded again.

**A party line**, which is what a rural exchange really sold in 1993, and there are
two ways onto one: several machines of one premises (a house has one line and one
modem set to answer), and two premises that hashed onto one number -- ten thousand
subscriber numbers to a region. Either way the **lowest address answers**, every
time, and the line is busy for all of them while it is up.

| command | does |
| --- | --- |
| `cu telno` | call another machine: a session on it, on this screen |

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

### The ring

A dial is a **wait**, and nothing is on the screen while it lasts: the modem goes
off-hook, dials, and the far end rings. Which of the three outcomes it will be is
asked of the link layer the moment the receiver is lifted (`env.net.phone`, which
is `CeroSecNet.ringAnswer`), and then the machine holds the line for as long as
that outcome takes (`CeroSecOS.ringMs`):

| outcome | wall clock | why that number |
| --- | --- | --- |
| `CONNECT 2400` | 4 s | what a 2400-baud handshake took: off-hook, the tones, the answer tone, agreeing a speed |
| `BUSY` | 2 s | the exchange returns busy tone as soon as it has looked the number up, and the modem needs two of them to know a tone from an answer |
| `NO CARRIER` | 15 s | the modem's **S7 register**, which is how long a Hayes-compatible modem waits for a carrier after dialling before it hangs up. The factory default was 30 or 50 depending on the model; this modem has `S7=15`, and that is a **setting**, declared here and in the manual so it is a fact about this modem and not a number invented here (`CeroSecOS.MODEM_S7`) |
| `NO DIALTONE` | none | what the receiver tells you the instant it is lifted |
| `cu: no phone line` | none | the machine never lifted one |

Wall-clock seconds, like every other delay on either link (`PHONE_LINES_PER_S` is
a wall-clock rate and `rcp`'s wait is wall-clock milliseconds): a call is a thing
happening in a room and not in game hours.

**The wait costs nothing.** It is the VM's ordinary sleep -- `applyControl`'s
`"sleep"` with a `cont` on it -- so `jobStep` answers `sleeping` and spends no step
before it ever reaches the walker. `hostile_test` drives four machines ringing at
once for a hundred and forty passes and asserts not one step spent by anybody, and
that the ring still ends.

**Both ends are busy for the length of the ring.** There is no pty yet, so that
half is read off the **job** that is dialling (`CeroSecNet.ringOf`, walked by
`lineBusy`) -- which is the same doctrine the busy rule already ran on one step
along: the thing that is waiting *is* the record of the ring, and a job that has
gone -- Escape, `kill`, the cpu ceiling, the machine going dark -- has hung up by
the same act. Nothing is counted anywhere, so nothing can leak.

**Escape aborts a dial**, and the word is the modem's own: `NO CARRIER`, which is
what a Hayes modem prints when the DTE puts the receiver down before a carrier
came up. The word is written into the ring record by `cu` itself, so `killJob` says
the line it was handed and the VM never learns what a modem is.

The world is asked **again at the door** when the ring is over: four seconds is
time enough for the far machine to be switched off, and what a caller gets then is
`NO CARRIER` rather than a session on a computer that has gone.

A dial with no terminal behind it is refused **before** the ring and not after it
(`applyControl`, on the `dial` field of the wait): a crontab line must not hold a
telephone line open for fifteen seconds to be told `cu: not a terminal`.

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
socket, a route -- and a call is not a route: `rsh shed date` on a machine on
another premises is `No route to host` whether or not you could have called it.
Copying a file by telephone was `uucp`'s job, and `uucp` is not on this disk.

**The exchange is the county's grid.** A telephone exchange is a building full of
switches on the mains, so the day the sandbox's power cutoff arrives there is no
dial tone anywhere, for good -- and a call that was up when it happened comes
back as `NO CARRIER`. That is the real difference between the two links: the coax
is two machines and a wire and goes on working with a generator at each end,
while a call needs a third building that is still working. A grid that dies under
a ring takes the ring with it: the door asks again when the wait is over. Whether the grid is
alive is asked the way the game's own Lua asks it (`ISButtonPrompt.lua:520`).
A server that wants it otherwise sets one option:

| `SandboxVars.CeroSec.PhoneService` | the exchange |
| --- | --- |
| `grid` (default, and what anything unset means) | lives as long as the county's power |
| `never` | there is no telephone service at all, from day one |
| `always` | on its own generator; it outlives the grid |

### The phone book

A number is only useful if you have somebody else's, so `Base.Phonebook` --
vanilla's own item, in 22 loot spots, which until now only relieved boredom -- is
the **Knox County telephone directory**. Right-click a copy in the inventory:
*Look up numbers* opens the manual reader on a generated volume, the yellow pages
of one exchange, `NAME ..... NNN-NNNN` a line.

**One book is one exchange, and the copy remembers which.** The first time a given
copy is opened it is stamped with the `PHONE_REGION` cell of the reader's square
-- `cerosec.region = {rx, ry}` in the item's modData -- and its name gets the
exchange (`InventoryItem.setName`, the vanilla display name kept in front:
"Phonebook (exchange 732)"). After that the stamp never moves, so a book picked up
in Rosewood and read in Muldraugh is still Rosewood's book. That is what carrying
a phone book across a county does, and it is the whole reason the edition is on
the item and not worked out again at every opening.

**Who is in it.** The client asks the server (`sendClientCommand("CeroSec",
"phonebook", { rx, ry })` -- the one command in `SCeroSecSystem` that names no
square, which is why it lives in its own `PlayerCommands` table) and the server
sweeps that region with
`getWorld():getMetaGrid():getZonesIntersecting(x, y, 0, w, h)`. It keeps the zones
`CeroSecNet.isPremisesZone` calls a premises -- which is `premisesOf`'s own
predicate, extracted so there is one of it -- applies `premisesOf`'s own area test
against the building, and derives each number with `CeroSecOS.phoneOfZone`, which
is the exchange-of-the-corner and four-digits-of-the-premises-key composition
`lineOf` makes off the record. So a computer standing in `CoffeeShop` reads the
book's own line off its BIOS. Sorted by name and then by number, capped at 400
with the cap printed on the last line, and answered to the asking player only.

The **corner** decides which book a premises is in, because the corner is what the
exchange is derived from: a shop in a building straddling two regions is listed
once, in the book its number belongs to.

The area test is where it differs from `premisesOf` by one probe, and it has to.
`premisesOf` asks the building the MACHINE stands in; a book printed before
anybody put a computer anywhere has no machine, so the building is probed at the
zone's **middle tile** (`getBuildingAt(int, int)`) instead. The corner is very
often a wall or the pavement, and probing there would drop real shops. Without the
test the spawner's region-sized named zones would be listed as businesses --
`Farm` is 262 by 226, `StreetPoor` covers a suburb -- and neither has a telephone.

**And a second sweep, for the tenants.** The zones are one of the two kinds of
business premises and the malls that ship are the other, so a book that carried only
zones is a book a survivor dials a shop out of and gets nothing. Every building of
the region is asked for its tenancies by the same rule one building down, and each
one is a listing named from its room name in words -- `musicstore` becomes
`Music Store`, `dentist` becomes `Dentist` -- with the number
`CeroSecOS.phoneOfRoom` composes out of the same three facts the machine's own key
comes off. A building with **one** tenancy is listed by neither sweep, exactly as it
is one premises.

The buildings come from `IsoMetaGrid.getBuildingsIntersecting(x, y, w, h, out)`,
which walks only the **cells** the rectangle touches (`javap`: `x / 256` and
`y / 256` clamped to `minX`/`maxX`/`minY`/`maxY`, then `getCell`) -- the same shape
as `getZonesIntersecting`. A `PHONE_REGION` of 1024 tiles is four cells by four, so
a book costs sixteen cell visits, paid once when a copy is opened. `getBuildings()`
is the other accessor on that class and is every building in Knox County; it is
deliberately not used.

**No residences, and no coordinates.** A house is a premises and has a line; the
map gives it no name to print, and a white-pages line needs a family name Knox
County does not have anywhere in its data. Inventing one is not on the table, so a
residence is simply unlisted, the way an unlisted number was. Where a shop stands
is not printed either: a directory prints names and numbers.

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

### The TNC, and how one was driven

There is **no `call` command**, and there was one until `SYSTEM_VERSION` 17. It was
invented here: no Unix ever shipped a `/bin/call`, because packet radio was never
something the kernel did. A TNC was a box on the end of an RS-232 cable with its
own firmware and its own prompt, and a 1993 operator reached it the way he reached
any other serial device -- `cu(1)` on its line:

```
admin@ksp-04-11:~$ cu -l /dev/radio0
CeroSec Systems TNC-200 (TNC-2 compatible)
cmd: MYCALL
MYCALL KD4AXR
cmd: C KE4QWZ
*** CONNECTED to KE4QWZ
login:
```

`cu -l line` is cu(1)'s own second form -- a line to open instead of a number to
dial -- so `cu`'s usage line is now `cu telno | cu -l line`. **Two things here are
ours and are declared** (`CeroSecOS.DEVIATIONS`, and Volume 1's "What is not Unix
here"): the line is a *character device naming a radio* (`/dev/radio0`) where a
real `cu` is handed a tty and reads `/etc/remote`, neither of which this machine
has; and the banner line, a real TNC-2 having printed whatever its vendor chose.

The command set at `cmd:` is the TNC-2's, cut to six with the box's own
abbreviations, case-insensitive as a TNC was:

| at `cmd:` | does |
| --- | --- |
| `MYCALL` / `MY` | print the callsign; an unprogrammed box says `MYCALL NOCALL` |
| `MYCALL <call>` | set it -- it is `/etc/callsign`, so root only |
| `CONNECT <call>` / `C` | connect, then converse: keys go to the far station |
| `DISCONNE` / `D` | drop the link, staying at `cmd:` |
| `CONV` / `K` | back into converse on a link you stepped out of |
| `MHEARD` / `MH` | the stations heard since power-up, newest first |
| `MHCLEAR` | empty that list |
| anything else | `?EH`, which is the box's own answer to a line it did not understand |

Three ways out of a link, and they are three different things. **Escape** is the
TNC-2's interrupt key: back to `cmd:` with the link still up (`K` goes back in).
**`D`** drops the link and leaves the box at `cmd:`. **`~.`** alone on a line is
`cu`'s own escape and hangs the whole line up -- link and `cu` together -- which
prints `*** DISCONNECTED` from the link layer and then `Disconnected.` from `cu`,
and gives the shell back. `exit` on the far machine ends it from that end.

That is why `cu` is a *program that stays*: it holds the near end of the link, so
^C at its prompt takes the link with it, the machine going dark takes it, and a
link that goes away underneath puts the box back at `cmd:` rather than dumping the
survivor at a shell prompt he did not ask for.

`MHEARD` is the real thing and not a log of this machine's own work: the link layer
writes a station down on **every** machine whose aerial can hear it. Hearing is not
connecting -- one transmission, so the only range in it is the *transmitter's*,
where a link holds out to the smaller of the two -- so a station can sit in `MHEARD`
and still answer a connect with silence, which is the first thing anybody with a
handheld learns. One line per station (heard again moves it to the top with a new
time), eighteen deep, which is a TNC-2's depth, and the list is RAM in a box on a
desk: `turnOff` empties it. The time is printed because a TNC-2 prints one when
`DAYTIME` is set, and `DAYTIME` here is set at power-up off the machine's clock.

Lines with three stars are the **TNC** talking and not a command, and they are a
TNC-2's own: `*** CONNECTED to <call>`, `*** DISCONNECTED`,
`*** retry count exceeded` and `*** BUSY`. (A TNC-2 spells the last one
`*** <call> busy`; the bare word was chosen so the one-line refusal reads like the
modem's `BUSY` on the link before this one, and the callsign is on the line above
it anyway.) Two more the machine says in its own name, because it can see them
without transmitting: `cu: no radio` and `cu: no callsign` -- and a machine with no
set in its room has no line to open at all: `cu: /dev/radio0: no such device`.

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


## Underneath: identities, links and sessions

The engine's half is `shared/CeroSec/OS/CeroSecOSNet.lua` and it knows nothing
about the game: the four files (`/etc/hosts`, `/etc/hosts.equiv`, `~/.rhosts`,
`/var/log/wtmp`), the arithmetic that turns a premises's corner into two bytes of
an address, the shape of every line the five listing commands print, the trust
rules, and the pty table a session lives in. Two functions carry the whole of the
name question and nothing else calls the resolver behind their backs:
`CeroSecOS.originOf(state, addr)` is `gethostbyaddr(3)` -- the name that machine's
own `/etc/hosts` gives an address, else the address -- and is what a session's
origin is recorded as, while `CeroSecOS.trustWords(state, addr)` is the list a
trust line may match (the address, plus every name on its `/etc/hosts` line) and
answers `nil` for a caller with no address, so a machine reached by telephone or
radio is trusted by nobody. `CeroSecOS.etherOf(addr)` derives the card `arp`
prints. `rlogin`, `rsh` and `rcp` decide
everything that can be decided from here -- the name, whether the wire reaches,
how deep the chain already is -- and then end in an order to the server
(`"rlogin"`, `"rsh"`), exactly as `shutdown` does.


`env.net` is the link layer, handed in beside `env.devices` and built fresh for
every line typed, because both are answers about a moment:

| call | answers |
| --- | --- |
| `reach(addr)` | `ok`, and which of strerror's words to wear when not |
| `peers()` | every machine of this wire that is up: host, addr, up, users, load, who |
| `sessions()` | who is logged in on *this* machine, console and ptys |
| `copy(spec)` | `rcp`'s own copy, judged by both disks |

`server/CeroSec/SCeroSecNet.lua` is the other half and the only one that knows
there is a world, and it now holds **two link kinds**, which is what the promise
about "a new kind of link and not a new command" came to:

| kind | the answer | the rule |
| --- | --- | --- |
| Ethernet | `reachable(system, from, addr)` | the same premises, both machines on |
| telephone | `reachablePhone(system, from, tel)` | both have a line, both on, the exchange alive, the line free at each end |
| radio | `reachableRadio(system, from, call)` | both machines on, a two-way set in reach of each and both switched on and powered, the same channel, inside the smaller transmit range, both sets free, and both chunks loaded |

Three answers, no new command learnt and no engine file touched by the second and
third except to add one of their own. What a new kind owes, and the telephone and
the radio are the two worked examples:

- **an identity**, derived and not stored twice. The four subscriber digits come
  off the premises key already on the machine's disk (`CeroSecOS.phoneKey` of
  `netRecord`'s `b1`/`b2`, one more multiply-add modulo 2^16 so that adjacent
  premises are not adjacent numbers), so they are answerable for a machine whose
  chunk nobody has loaded and cannot disagree with the address about whether the
  computer is on a premises at all. The exchange is the one half that could not be
  derived -- a region is a coordinate and the record has none -- so it is a field
  (`ex`), which is what makes this the one identity on the rung that needed a
  migration. Collisions are documented rather than fixed: two premises on one
  number are two premises on one line, which is a party line, and nothing here
  routes.
- **its own refusals**, in the voice of the hardware that would have said them:
  strerror's words for a socket, a Hayes modem's result codes for a call.
- **a marked pty**. `pty.phone` is the whole of what makes a session a call --
  the busy rule, the trickle and the two endings are all read off it -- so
  everything that already knows what a pty is goes on working unchanged.
- **busy derived, never counted.** `CeroSecNet.lineBusy` walks the county's pty
  tables, because a call's two ends are both on the pty; a counter beside them is
  a second truth that leaks the first time a machine is picked up mid-call.
- **a teardown reason.** `tearDown(system, object, line, why)`: `"carrier"` when
  the link went (power at either end, a machine picked up, the exchange dying
  mid-call, noticed in `farOf`, where every keystroke on a session already goes)
  and nothing when somebody hung up. A wire says one line whatever ended it.
- **its own rate, if it is slower than the machine.** `CeroSecNet.callRoom` keeps
  a one-second window on the pty and `SCeroSecJobs` drains under both ceilings;
  what the line cannot carry is kept, never dropped.
- **a sandbox option, read the guarded way.** `SandboxVars.CeroSec.PhoneService`,
  and `CeroSecNet.gridAlive()` asks the game the way the game's own Lua does --
  `getSandboxOptions():getElecShutModifier()` against
  `getGameTime():getWorldAgeHours()` (`ISButtonPrompt.lua:520`), where `-1` is
  the power already gone and `2147483647` is the power that never goes
  (`zombie.SandboxOptions.randomElectricityShut`, javap'd). A game it cannot ask
  at all answers "alive": a mod that could not read the option must not take the
  telephone out of every server it cannot interrogate.

The radio pays every one of those and adds three of its own, all three because it
is the first link that is a THING STANDING ON A TILE:

- **a proof section before a design.** `server/CeroSec/SCeroSecRadio.lua` opens
  with seven numbered facts about the game's radio model, each cited to `javap` on
  the jar or to the game's own Lua, because the design bent to three of them: the
  channel is kilohertz (`DeviceData.getChannel`, and the radio UI divides by a
  thousand), range is applied on x and y with no z and with no hard cutoff
  (`ZomboidRadio.DistributeTransmission` scrambles past `0.9 * range`), and a
  radio whose chunk is unloaded is not in the list a transmission is distributed
  over at all (`IsoWaveSignal.addToWorld` -> `RegisterDevice`).
- **a device, not a second discovery.** The TNC is one entry appended to
  `CeroSecDevices.find`, with its own reach (`CeroSecRadio.REACH`) because a TNC
  has a foot of cable and the ordinary walk covers a whole premises. Its
  vocabulary is empty and its mode is therefore `440`, not `660`: the sensor's
  rule -- a `w` bit must not promise a write that cannot happen -- applied twice.
- **a failure the other links do not have.** No aerial, an unloaded chunk, a
  retuned knob: all silence, and `farOf` re-asks `CeroSecNet.radioHolds` on every
  keystroke so a link that has gone is found the moment anybody touches it.

`cu` is the engine-side worked example of the same split: it decides the shape of
a number, whether this machine has a line at all and the hop ceiling, and ends in
a `"cu"` order. It is refused where `rlogin` is when no job has a terminal, in its
own name (`CeroSecOSVM`), and `~.` is a shape the engine recognises
(`CeroSecOS.isCuEscape`) and the server acts on in `Commands.exec` -- a tilde
escape is read by the near end and never sent down the line, so the far shell
never sees it and neither history has it.

**Why a machine answers with its chunk unloaded.** The rung rests on it, so it is
written down beside the code that uses it. `zombie.globalObjects.SGlobalObjects`
reads `gos_cerosec.bin` whole at server start and `SGlobalObjectSystem:
initLuaObjects` builds one Lua object per global object, so
`getLuaObjectCount()` is every computer in Knox County that has ever been
switched on and not every computer in memory; `SGlobalObject:getIsoObject()`
answers `nil` for one whose chunk is not loaded, which is why every call on it in
`SCeroSecObject` is guarded. So a machine's disk, its power flag and the record
of its address are readable whatever the streamer is doing. Three things need
the chunk -- the power check, `/dev`, and working out which building a computer
stands in -- and the third is done once, when the machine is switched on, with
the answer written into the machine's own state (`CeroSecOS.netRecord`, three
numbers, saved). The first of the three is not merely skipped but *postponed*: a
machine out of the world keeps the state it had, and the power question is asked again
the moment its chunk comes back
([ARCHITECTURE.md](ARCHITECTURE.md#the-chunk-that-goes-away)). `tests/window_test.lua` has a machine whose `getSquare()` and
`getIsoObject()` both answer `nil` and which still answers `ruptime`, a `ping`,
an `rlogin` and a write to its disk.

And the two halves of that, which is where the wire and the streamer meet: trust is
a question about the caller's **address** (`CeroSecOS.trustWords`), and an address is
a record on the disk -- so a machine that has been numbered goes on trusting and
being trusted with no square, no tile and no room left around it, while a machine
nothing has numbered yet is on nobody's wire and there is nothing for a trust file
to be about. Numbering is the only one of the two that waits: it needs a building,
a building needs a square, and the square arrives with the chunk -- so a computer
switched on in a base somebody built and then carried into a building joins the wire
at the first minute the chunk is in, and not before. Both are benched in
`tests/window_test.lua` (section 42, the foot of it).

**The address** is assigned once and never moved: the lowest number nobody in the
same building has, exactly as a device number is the lowest its kind has never
used. A computer carried into another building is renumbered the next time it is
switched on or a window opens on it -- the two bytes it carries no longer match
where it stands -- and one carried out of every building keeps what it had,
because a machine with no address at all is not something to invent. The
machine's own line in `/etc/hosts` is written the first time it learns an
address and never again.

**A session is a pty on the far machine carrying a `console`** -- the same table a
machine's own screen is, so the login prompt, the shell, the editor, Escape, `$?`
and the `su` stack all work on it unchanged. It carries three fields a machine's
own console has not got: `watchAt` (which machine's windows are looking at it),
`line` (the pty's name, what `who` prints and what tags every job it starts) and
`hops`. The console that dialled carries `remote`, naming the machine and the
line. Neither is saved: a pty is runtime state like a job, so a machine that
comes back from a reload comes back at its own prompt with nothing open.

The lines are **one glass**. A pty's console starts with a copy of what was on
the dialling screen and hands it back when the session ends, which is why a
survivor sees one unbroken stream and why the local scrollback is still there
afterwards.

So the scheduler stopped being a machine with one console. A job is tagged with
the line it was started from (`job.pty`), writes to that screen, and is killed
when the session ends; one pass can finish four lines at once and each order goes
to the screen its job was writing to. Output is drained **round-robin across the
jobs, one further along every draining pass** -- a machine gets its twenty lines
in the first pass of each second and nothing in the nine after it, so draining
from the front of the list handed all twenty to the same job for ever, and a job
whose output cannot drain is a job that never runs again. A job whose screen has
gone has its output thrown away, or it would never be reaped and its slot would
never come back.

Every command that types at the machine resolves the chain through one door,
`SCeroSecSystem:targetFor`, which is also where a session whose far end has gone
is torn down and the glass handed back.

`ping` and `rcp` wait, so the VM grew the one thing it could not say: a command
that wants to be **woken later** rather than answered. `control = "sleep"` with
`{ ms, cont }` leaves the job `"sleeping"` against `env.nowMs` exactly as `sleep
1` does, and the continuation is called with an empty line when it comes round.
The waiting costs the machine nothing.
