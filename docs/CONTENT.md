# CeroSec — World content

What is already on the machines, on the disks and on the papers of Knox County:
the mechanics of it, the catalogue format a wave writes into, and how one number
per save makes a note in a drawer agree with a computer nobody has switched on.

See also: [PLAYERS.md](PLAYERS.md) for what a player meets,
[CONTRIBUTING.md](CONTRIBUTING.md#the-compatibility-contract) for the rules a
catalogue change is held to, [ARCHITECTURE.md](ARCHITECTURE.md) for the engine
underneath.

## The sandbox option

**`CeroSec.PrefilledMachines`**, boolean, default **on**.

- **On** — a vanilla computer switched on for the first time comes up as
  somebody's machine: his accounts, his files, a motd, a week of log, sometimes a
  password. A floppy off a shelf sometimes has a program and a `README.TXT` on it.
  Papers with passwords on them turn up in desks and in pockets.
- **Off** — the bare machine this mod shipped with: `root` and `admin`, both open,
  an empty disk, blank floppies.

It is **the one option of ours whose default changes a world**, and it changes it
in one direction only: **a machine somebody has already switched on is his and is
never touched.** What changes is the machines nobody has been to yet.

## The per-save secret

One 64-bit number, sixteen hex digits, made once for the life of a save and stored
as `SCeroSecSystem.seed`. Everything generated is `hash(secret, key)` — a name, a
password, which disk a floppy is — so:

- the same question asked twice gives the same answer, **for ever**, with nothing
  saved and therefore nothing that can get out of step;
- the next save answers differently, so a player who knows one save's passwords
  knows nothing about the next.

**Where it lives, and why there.** It is a field of the global object *system*,
named in `setModDataKeys`, so it is written into `gos_cerosec.bin` — the same save
file the machines are already in — and read back with it. Proved at the bytecode
level (offsets in `SCeroSecSystem:initSystem`): `save(ByteBuffer)` copies across
only the keys named in that list and writes them with `KahluaTable.save`; `load`
reads them straight back; and the Lua system object *is* that mod-data table.

It is deliberately **not** `ModData.getOrCreate` / `ModData.transmit`. That is the
global mod-data channel and its whole purpose is to be transmitted to clients — and
this number is what every password in the county derives from. It stays on the
server: it is in no sync-key list, in no initial state, and no client is ever told
a password.

**Be honest about what it is.** It keeps a save *consistent*. It is not a security
boundary: the number is in the save file, and a single-player player who reads his
own save can read `/etc/passwd` out of it just as easily. On a server the save is
on the server, which is the whole of the difference.

## What is keyed on what

| keyed on | what it decides | why |
| --- | --- | --- |
| **the premises** (its two bytes) | root's password, every account's login and password | so a paper found anywhere in that premises names something true of every machine in it |
| **the machine** (premises + square) | which scripts are in `~/bin`, the hours in the log | the desk, not the company. Nothing a *paper* names may be keyed here. |
| **nothing** (a roll) | whether a floppy has content, whether a body carries a paper | the roll happens once and its *result* is saved on the item |

The people are the premises' and not the machine's, and that was forced by the
papers: two desks in one office are two desks of one company, and a corpse cannot
say which desk its owner sat at — an account keyed on a machine is an account a
note in a pocket could not name.

## Prefilling a machine

`CeroSecContent.prefill(state, opts)`, called from `SCeroSecObject:turnOn` and
nowhere else, for a machine whose state was `nil` a moment before. Never for a
state that already existed.

It is **not** a migration step, for the reason the address is not one either: which
premises a machine stands in is a question about a *square*, and most machines in a
save have no chunk loaded. `turnOn` is the moment the chunk is certainly there,
because the power check has just proved it.

**Everything goes through the engine's own write path** — `CeroSecOS.createNode`,
`CeroSecOS.setPassword` — so the quota, the modes, the owners, the 96 entries to a
directory and the 512 nodes to a machine hold for a prefilled computer exactly as
they hold for one a survivor typed on. **A profile that would go over a ceiling is
trimmed**, file by file, and never forced: the loot in one office must not be able
to take a machine down. `tests/content_test.lua` fills a machine to its node limit
first and then prefills it.

**Nothing generated is stored in clear.** A root password is derived, hashed
through `setPassword` and forgotten; the only place the letters appear is on the
paper, and the paper derives them again for itself.

Which profile a machine gets: the **named zone** of its premises
(`CeroSecNet.premisesOfSquare`, the same rule the telephone line uses), else the
names of **all the rooms in its building** (`CeroSecNet.premisesRooms` →
`BuildingDef.getRooms()` → `RoomDef.getName()`), else **residential**. They are
matched against `CeroSecContent.PREMISES_WORDS` — because map data is all there is
to go on: a premises zone is named by whoever drew the map and a `RoomDef`'s name
is a *loot type* and says nothing about tenancy.

**The whole building, and never the caller's own square.** This is the fix to a bug
that shipped in this wave and was caught in review. The profile used to come from
the room the *caller* stood in, so in a house with a study in it the desk in the
study answered `office` — a profile with a root password, so a note was written —
while the computer in the living room of the same house answered `residential`,
which has none: the paper named a password no machine in the county had. Two squares
of one premises are one premises, and anything a premises *is* must be answered the
same way from every one of them.

The scan walks the **word list** in its order and asks every name about each word in
turn, so the order the engine hands a building's rooms over in cannot change the
answer, and "which room wins" is a decision written down in one ordered list rather
than an accident of iteration.

A machine in **no building at all** — a player-built base — is left bare, exactly
as it gets no address and no telephone line.

## The profile format

```lua
CeroSecContent.PROFILES.office = {
  host     = "acct",     -- head of the hostname; the coordinate tail is kept
  motd     = "...",      -- /etc/motd, at most MOTD_MAX_LINES lines of 60 columns
  root     = true,       -- a root password to derive, hash, and never store
  accounts = { { name =, admin =, pass =, files = { { path =, mode =, text = } } } },
  bin      = { { script = "lights.sh", chance = 60, to = "/usr/local/src" } },
  logs     = { "..." },  -- /var/log/messages, dated in the week before day one
  mail     = { { to =, from =, subj =, body = } },
  cron     = { { to = 1, lines = { "0 22 * * * ..." } } },
  files    = { { path =, mode =, owner =, text = }, { path =, dir = true } },
}
```

Five things to know:

- an account's `name` is usually **absent**, and then the login is generated from
  the premises and the slot number. A profile *names* an account only when the name
  is the point — a shared `dispatch` login, say.
- `pass = true` gives that account a password of its own; absent is an **open**
  account, which is what most 1993 desk machines had and is what lets a survivor in
  without finding anything.
- `root = true` is what puts a paper in that premises' drawers, because the note's
  derivation is the same one. A profile with no root password has no note anywhere.
- a `bin` entry names a script in `CeroSecContent.SCRIPTS` and never carries its
  text: one script, one copy, so the disks and the homes cannot drift into two
  versions of one file — and the bench runs every script once.
- **order matters**: everything is trimmed from the tail, so put what matters
  first. A `path` inside an account's `files` is relative to that account's home
  and may not contain a `/`.

And three fields wave 7b added, each because a premises the county really has
could not be written without it:

- **`cron`** is a crontab per account, in Vixie's own five fields, written to
  `/var/spool/cron/<login>` exactly where `crontab(1)` writes one — root's, `600`,
  in root's `700` directory. It is a real crontab and the machine really runs it: a
  shop whose lights went off at ten every night is a shop whose lights still go off
  at ten. `to` is a slot number or a literal login, the way `mail`'s is.
- a **`files` entry marked `dir`** is a directory and not a file, with its parents
  made above it. A profile that wanted a tree of its own — `/usr/local/src` on the
  vendor's bench machine — had no way to make one, and a path whose parent is
  missing is a file the gate refuses for a reason nothing in the catalogue could
  see.
- a **`bin` entry may name `to`**, an absolute directory, instead of the first
  account's `~/bin`; the directory and its parents are made if they are missing, and
  what lands there is root's. One script still has one copy — `to` moves where the
  copy goes and never what is in it — and it is how the vendor's machine can carry
  the whole library and the military post, which has no ordinary account at all, can
  carry one.

**What the bench holds a crontab to**, and both halves matter. Every line goes
through `CeroSecOS.checkCrontab`, the machine's own parser, in the writer *and* in
the bench: a line the parser refuses is a line that does nothing for ever and says
nothing about why. And a line naming a script of ours must name the path the profile
really writes it to — an entry behind a `chance` is on some machines and not others,
and one naming `to` is somewhere else entirely, so a crontab saying
`/usr/local/bin/check.sh` on a machine that put `check.sh` in a home is a line that
mails `not found` once an hour for ever. That check went red on the military post the
day it was written.

**And one crontab is TYPED**, as the account it belongs to, on a machine the profile
built, with the environment a login really hands a shell. A crontab that *parses* is
not a line that *works*: the command names a path with `$HOME` in it and an account
whose login was generated. The radio station's line is the one taken, because its
line is the one built to run from cron at all, and what it prints is the nine
o'clock entry off the station's own sheet.

A `logs` line is dated from the **save's own start date**
(`getGameTime():getStartYear()` and the two beside it, which carry the same
zero-based month and day `getMonth`/`getDay` do), spread over the week before it,
and cut to sixty columns with the hostname in front of it — a survivor reads
`/var/log/messages` with `cat` on a terminal that does not wrap.

### The ten as shipped

Every one of the ten is written. Each is a story in **three files**, and each carries
at least one script a survivor can copy onto a building of his own.

| id | host | root | accounts | the three files |
| --- | --- | --- | --- | --- |
| `residential` | `ksp` | no | 2, both open | `notes.txt`, `porch.txt` (what a timer really is), a child's `report.txt` |
| `office` | `acct` | yes | 3 | `handover.txt`, `ledger.txt`, `memo.txt`; the crontab the handover note talks about really runs `total.sh` on the ledger |
| `police` | `disp` | yes | 3, one named `dispatch` | `bolo.txt`, `handover.txt`, and `/var/log/dispatch` — which stops in the middle of a line at 5:05 on the morning of the 9th |
| `bank` | `vault` | yes | 3 | `accounts.dat` in four plain columns, `audit.txt` (the examiner's three answers, as two commands), `vault.txt` |
| `store` | `till` | yes | 2 | `inventory.txt` counted on the 6th, `prices.txt` in cents, `closing.txt` |
| `school` | `bell` | yes | 3 | `grades.txt` by student number, `bells.txt`, a `detention.txt` that will not write the two names down |
| `clinic` | `ward` | yes | 3 | `patients.txt` (rooms and wards, nothing medical), `rounds.txt`, `supplies.txt` |
| `radio` | `studio` | yes | 2 | `sched.txt`, `notes.txt`, and `/var/log/heard` — what the county sounded like from the 4th to the 9th |
| `military` | `post` | yes | **none** | `/root/memo-01.txt` to `-03.txt`, on the exclusion zone |
| `cerosec` | `cerosec` | yes | 3, one named `support` | `bench.txt`, `answers.txt`, `/usr/local/src/CHANGES` |

**The military post is the one with no ordinary account on it.** A post did not hand
out logins; a man sat down at it because he was allowed to be in the room. So there
is no open account to walk in through and no note in anybody's pocket — the only way
in is the paper in the drawer or the firmware's repair, which is the same cost every
locked machine has and which the manual states.

**The vendor's own machine carries the whole library** in `/usr/local/src`, by
reference, which is the one place in the county where all of it stands together — and
the distribution disk says so in as many words, which is true because this profile is
what makes it true.

A machine whose premises resolves to an id nobody had written was prefilled with
nothing at all, which is exactly a bare machine. That path is still there and is
still tested (`tests/window_test.lua` takes a profile out of the catalogue to provoke
it), because the next id somebody declares will go through it.

## The disk catalogue

```lua
CeroSecContent.DISKS[i] = {
  id     = "UTILITIES",   -- what the entry is called here and in the bench
  label  = "UTILITIES",   -- what is written on the disk; capitals, labelOk
  weight = 4,             -- out of 100; the remainder is a blank disk
  late   = "NUMBERS.TXT", -- one file is a stub until the disk is first inserted
  files  = { { name = "lights.sh", script = "lights.sh" },
             { name = "README.TXT", mode = 644, text = "..." },
             { name = "MAN", dir = true },
             { name = "MAN/CU.TXT", mode = 644, text = "..." } },
}
```

Five things to know:

- a file entry carries **either** `script` (a name in `CeroSecContent.SCRIPTS`,
  which brings its own mode) **or** `text` and `mode`. Never both. An entry marked
  `dir` is a **directory**, and a `name` may then be two components with a slash
  between them — `MAN`, then `MAN/CU.TXT`. Two is all the depth a floppy gets: a
  deeper tree on 4096 bytes read at sixty columns is a tree nobody would walk. The
  entry that makes a directory comes before the entries inside it.
- `README.TXT` is in **capitals**, and so is every name on a disk that is not a
  script: a 1993 floppy came out of a DOS machine. The bench holds every README to
  naming every file beside it **and only** files that are on it.
- the ceilings are the floppy's and they are small — 4096 bytes, 32 nodes. An entry
  over either is trimmed at fill time, so the bench weighs every entry.
- the weights are out of a hundred and **the remainder is blank**. Most of a box of
  disks is blank, which is what the floppy loot has always said.
- `BLANK` is in the table with no files on purpose: naming the entry a roll lands
  on when nothing is written lets the bench say so out loud.

### The six as shipped

| label | share | what is on it |
| --- | --- | --- |
| `UTILITIES` | 4 | `lights.sh`, `check.sh`, and a README saying why neither names a device of its own |
| `BBS LIST` | 3 | `NUMBERS.TXT` (**late**, see below), `CALLS.TXT` — packet stations somebody heard, by callsign — and how to reach either |
| `WARDIALER` | 2 | `RANGE.TXT`, `log.sh`, and a README whose first screen says there is no wardialer and why |
| `GAMES` | 3 | `guess.sh`, `hangman.sh`, `adventure.sh`, `WORDS.TXT` — 3651 of the floppy's 4096 bytes spent on the programs |
| `BACKUP` | 3 | somebody's home directory on 8 July: `DIARY.TXT` in four entries, `LETTERS.TXT`, `FAMILY.TXT` |
| `CEROSEC OS 1.0 DIST` | 2 | `INSTALL.TXT`, `MAN/` with six pages, three scripts |

Seventeen shares of a hundred; the other eighty-three are a blank disk, which is what
a box of disks is.

The slot 7a named `CEROSEC OS UPGRADE` shipped as **`CEROSEC OS 1.0 DIST`**: it is
distribution media, and nothing on it upgrades anything. `INSTALL.TXT` explains the
BIOS repair as reinstalling from this media and says in as many words that there is
nothing on the disk that can write to a system disk — a floppy that could rewrite the
system is a floppy that destroys a working machine by being left in the drive.

### `WARDIALER`: why there is no wardialer

Because `cu` cannot be driven by a script, and that is a fact about the engine and not
a decision taken here. `CeroSecOS.jobStep`'s `applyControl` treats a `cu` the way it
treats `edit` and `shutdown`: the order goes out to whoever is running the machine and
the job **ends**, whole, with `job.sig = { k = "exit", all = true }`. So the line after
a `cu` in a script never runs. And from a background job or a cron line it does not
dial at all — `jobHasTerminal` is false there, and the refusal is `cu: not a terminal`,
made *before* the ring so a crontab cannot hold a telephone line open for fifteen
seconds to be told what the door would have told it at once.

`cu` was **not changed**. Handing the glass to the far end is what `cu(1)` does, and a
scriptable dialler would mean a second way into a session — so the disk ships the
method instead and says so on its first screen: `RANGE.TXT` (how to turn a range, and
the four words a modem really answers with — `CONNECT 2400`, `NO CARRIER`, `BUSY`,
`NO DIALTONE`) and `log.sh`, which writes the date, a number and a word into a file you
name. Half the job is a thing the machine can do, and that half is on the disk.

### `late`: a disk printed where it is used

A floppy is created in **loot**, and loot has no location: the disk is in a drawer in a
town nobody has walked into, so there is no square, no premises, no region and
therefore no telephone exchange at the moment it is made. A BBS list printed with the
numbers of somewhere else is the one kind of lie this catalogue is not allowed to tell.

So one file of such an entry — the one `late` names — ships as a **stub**, and is
filled the first time somebody puts the disk in a machine:

1. `Commands.insertfloppy` has just read the disk off the item, validated it through
   the slot's own gate, and read the sticker off the item's name. That is the last
   moment before the disk goes in the drive and the first moment there is a square to
   ask, so the fill happens there, to **our** validated private copy — which is what
   the drive takes and what an eject writes back onto the item.
2. `CeroSecNet.fillLateDisk(disk, x, y, now)` asks which region the machine's tile is
   in (`CeroSecOS.phoneRegionOf`) and what that region's exchange is
   (`CeroSecOS.phoneExchangeOfRegion`) — the same two questions the phone book asks —
   and hands `CeroSecNet.directory`'s listings to the catalogue.
3. `CeroSecContent.fillLate` lays them out (`CeroSecContent.bbsText`) and writes the
   file through the **engine's own write path** on a throwaway drive, exactly as
   `diskData` wrote the disk in the first place. So the floppy's 4096 bytes decide how
   much fits and a list that would not fit leaves the stub where it was.

**The numbers are real and the names are invented**, which is the whole shape of the
disk: the four digits ring a real premises of the player's own region, because they
come out of the county's own directory, and the name beside each one is what the
disk's owner wrote on his list (`CeroSecContent.BBS_NAMES`). Eight of them at most —
a floppy is 4096 bytes and the other two files have to fit beside these.

**The list is sorted by number**, which does two things at once: it is the order a
hand-kept list of numbers to turn is really kept in — what `RANGE.TXT` on the wardialer
disk tells a survivor to do — and it is what keeps the order the map handed its zones
over from reaching the page. Which name goes with which number is decided by the
**number** and never by its position in the list. The first draft paired on the
position, and the bench caught it: two copies of one disk must be the same page, byte
for byte.

**Where the "has it been filled" mark lives: nowhere.** A disk owns three keys and only
three (`CeroSecOS.DISK_KEYS`) and the gate at the slot refuses a disk carrying a
fourth, which is what keeps a payload out of the save file — so there is nowhere on a
disk to write a flag and nothing that would survive being written there. The mark is
**the file**: `CeroSecContent.lateEntryFor` answers the entry only while the late file
still holds, byte for byte, the stub the catalogue shipped, and the stub it compares
against *is* the catalogue's own text, so a wave that edited the stub and forgot the
sentinel cannot happen.

That is not a trick. It is the rule `upgradeSystem` already uses to take a retired
command out of `/bin`: what is exactly what shipped is the system's to replace, and
anything else at that name is a survivor's own work and stays. So a player who wrote
his own notes over the stub keeps them, on every machine he ever puts the disk in, and
the disk never rewrites itself under him.

What it costs: a survivor who types the shipped stub onto a blank disk by hand, labels
it `BBS LIST` and inserts it gets the listings printed. He has to reproduce a text he
could only have read off another copy of the same disk, which is a curiosity and not a
way in — the numbers are the region's own telephone directory and the phone book in his
other pocket has all of them in it already.

The bench proves the whole of it without a world: a shipped disk is waiting, the fill
writes it, the filled disk is **not** waiting any more, a second machine in another
exchange changes nothing, a disk somebody wrote over is left alone, a region with no
listings leaves the stub, four hundred listings come out as one page inside the floppy,
and the filled disk mounts and reads on a machine. That the region really is the
inserting machine's is the world half, and it is step 293 of
[PARCOURS-TEST.md](PARCOURS-TEST.md).

**How a floppy gets its content.** `OnCreate = CeroSecContent.onCreateFloppy` on
the four item blocks — an item-script key vanilla ships itself
(`ItemCodeOnCreate.onCreatePaperwork` on `Base.Paperwork`) and which is traced
through the jar in the comment over those blocks.

**A declared deviation.** The design for this wave said to hash the item's id.
There is no id: `InventoryItem.id` is written only by `load` and by
`createCloneItem`, so a freshly instanced item is id 0 and every floppy in the
county would hash the same. The roll is `ZombRand`, the way vanilla rolls loot —
and the determinism the design wanted is kept by *where the answer lives*: the roll
happens once, at creation, and its **result** is what is saved in the item's
mod-data. A disk's contents never change again.

The four vanilla-shaped floppies and their loot shares are unchanged.

## The papers

One item, `CeroSec.StickyNote`, for the two places a password was in 1993. Which
one it is is in the name the item carries, and nothing else about it differs.

| | |
| --- | --- |
| **`Sticky note: root / falcon12`** | in a desk, counter, filing cabinet, locker, dresser, side table or school desk of a premises whose profile has a root password. **One per premises, at most.** |
| **`Note: rmiller / thunder07`** | in the pocket of about **one zombie in twenty** killed inside such a premises. His **own** login — never root's, which he was never given. |

Nothing is ever dropped on the floor: a note on the ground is a note under a
bookshelf nobody will look at.

**The hook is `Events.OnFillContainer`**, and it covers both. It carries three
arguments — roomName, containerType, and a container — vanilla's own `LootLog.lua:7`
signature. For a **zombie's pockets** the engine fires it with the room name
`"Zombie"` and returns, so a body never sees the room distributions; skeletons are
refused before the event, so no note is on a pile of bones.

**The third argument is not always an `ItemContainer`.** `ItemPickerJava` fires this
event from **ten** places in four methods — the room's containers, a body's pockets,
and bags rolled into a container under the room names `"Zombie Bag"` and
`"Container"` — and four of those hand over an `ItemPickerJava$ItemPickerContainer`,
a distribution table and not a container at all. So the handler asks the engine's own
`instanceof(container, "ItemContainer")` **before it touches the thing**, and that is
not belt and braces: reading a field off a Java object Kahlua has no class metatable
for is not guaranteed to answer nil quietly. `tests/window_test.lua` proves it with an
object that raises on any field read.

It also keys off the **first** argument and never the second: a container whose parent
is an `IsoDeadBody` has its type replaced by the body's `getOutfitName()`, so the
second argument is an outfit name for a corpse and `"inventorymale"` for a walking
zombie — two strings for one thing.

`fillContainerInternal` returns before the event when the container has no source
grid, so a container *it* reports always has a square; the bag paths make no such
promise, which is why the nil test is a real test.

Not `Events.OnZombieDead`, which exists and would be the wrong moment: pockets are
filled once, when the zombie is made, and a hook on death would drop a paper into a
pocket a survivor had already emptied.

**The note and the machine never talk to each other.** Both derive the password out
of the secret and the premises, so there is no moment where one has been written
and the other has not — the paper can be found a week before anybody switches the
computer on, and the computer comes up with the very password already in the
player's pocket.

The desk note's premises is marked **only once the paper is really in the drawer**,
and that mark is saved with the save: the drawers of one office are opened over
many sessions, and a full drawer must leave the next one free to carry it.

**If no container in a premises ever fills**, the root password is still findable
through play: `last` names the accounts that have logged in, an open account is
often enough to read `/var/log`, the passwords are a short word and two digits, and
the 1993 answer to a machine nobody can get into is the one the BIOS gives — repair
it, which reinstalls the system and keeps `/home`.

## The seed library

`CeroSecContent.SCRIPTS` — one table, one copy of every script the mod ships, in
the machine's own `sh`. A profile's `bin` and a disk's `files` both name an entry
here.

```lua
CeroSecContent.SCRIPTS["lights.sh"] = {
  mode = 755, args = { "light0", "light1" }, input = { "y" },
  needs = { devices = { { id = "light0", kind = "light", state = "on" } },
            files   = { { path = "prices.txt", text = "..." } } },
  text = "#!/bin/sh\n...",
}
```

`args` is what the bench runs it with and `needs` is what it declares it wants
standing around it — the bench stubs exactly that and nothing else, so a script
that quietly reached for a second device would find it missing.
`tests/content_test.lua` **runs every script**, under the engine's own budget, with
its arguments and again with none, and holds every line of every one of them to
sixty columns.

`needs.files` is the other half of `needs.devices`, and `input` is what somebody
**types** at it — the lines a `read` is answered with, in order, handed back through
`CeroSecOS.jobInput`, which is the one door an answer goes through on a real machine.
A program that asks questions cannot be proved by running it and reading what came
back, because nothing comes back until it has been answered; and the recorded lines
have to play it to the **end**, or a game left at its first prompt would pass for one
that runs.

**The usage rule.** A script somebody found and typed the name of must say how it is
used and must not claim success, so every one is run with no arguments as well. A
script that takes none — a game — is not held to it, there being no wrong way to run
one; and it cannot get out of the rule by declaring `args = {}`, because the bench
also reads the text for `$1`.

### The thirteen as shipped

| | |
| --- | --- |
| `lights.sh <light>...` | switch the lights you name off |
| `locks.sh lock` or `unlock`, then `<lock>...` | both directions of a row of locks |
| `lockup.sh <door> <lock>` | close the door, **read it back**, then bolt it |
| `check.sh <door>...` | which of them is standing open, and how many |
| `audit.sh <file> <word>` | the lines of a columns file that mention a word |
| `total.sh <file> <column>` | add a colon-separated column up |
| `rounds.sh <file>` | the first column, sorted: a list to work down |
| `announce.sh <file>` | the line of a table for the hour it is now |
| `sweep.sh <dir>` | every file under a tree, and how many |
| `log.sh <file> <number> <word>` | one line in a log: the date, a number, a word |
| `guess.sh <top>` | it picks one, you find it |
| `hangman.sh <file>` | a word out of a file, a letter at a time |
| `adventure.sh` | five rooms and one locked door |

Every one of them is a **template and not a tool**: each does one thing, takes its
devices and its files on the command line rather than naming any, and is short enough
to read on one screen. A script that hard-coded `light0` would work on exactly one
building in Knox County and teach nothing.

Two of them are worth reading for the trick. `lockup.sh` reads the door back before
it bolts it, because bolting a door that would not close bolts nothing and says it
did. `hangman.sh` masks the word with **three calls to `tr` and no loop over
characters**: the guessed letters become capitals, then every letter still in lower
case becomes a dot.

`CeroSecContent.DATA` holds the data files a script is *for*, named twice — once by
the script that reads it and once by the premises or the disk that carries it. So
`audit.sh` is proved against the very `accounts.dat` the bank's machine carries, and a
script proved against a file of the bench's own invention cannot happen. The bench
walks the table both ways.

**One engine quirk found while writing these and deliberately not fixed here**, this
being a content wave: `$(( ))` cannot read a positional parameter. `$((5 % $1))`
answers `bad arithmetic`, because the arithmetic reader takes a name to be
`[A-Za-z_]` (`arithUnit` in `CeroSecOSVM.lua`) and a real `sh` reads `$1` there.
Every script here assigns it to a name first.

## Versions

`CeroSecContent.VERSION` is **2** as of wave 7b, which filled the eight empty
profiles and the five empty disk slots. It is the catalogue's own number and **must
never become a save-shape number**: nothing a profile writes is marked as having come from one, so
a later catalogue changes what the next untouched machine gets and changes nothing
about a machine somebody has already switched on.

Neither `STATE_VERSION` nor `SYSTEM_VERSION` moves for content. Seeding a file is
not a shape change (see [CONTRIBUTING.md](CONTRIBUTING.md#which-number-moves-and-when)),
and nothing here is put in `/bin`: a profile's scripts go in an account's own
`~/bin`, which `upgradeSystem` never touches.
