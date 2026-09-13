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
  bin      = { { script = "lights.sh", chance = 60 } },
  logs     = { "..." },  -- /var/log/messages, dated in the week before day one
  mail     = { { to =, from =, subj =, body = } },
  files    = { { path =, mode =, owner =, text = } },
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

A `logs` line is dated from the **save's own start date**
(`getGameTime():getStartYear()` and the two beside it, which carry the same
zero-based month and day `getMonth`/`getDay` do), spread over the week before it,
and cut to sixty columns with the hostname in front of it — a survivor reads
`/var/log/messages` with `cat` on a terminal that does not wrap.

Ten ids exist: `residential`, `office`, `police`, `bank`, `store`, `school`,
`clinic`, `radio`, `military`, `cerosec`. **Two are written; the other eight are
empty**, and a machine whose premises resolves to an empty one is prefilled with
nothing at all — which is exactly a bare machine. Filling one is writing a table.

## The disk catalogue

```lua
CeroSecContent.DISKS[i] = {
  id     = "UTILITIES",   -- what the entry is called here and in the bench
  label  = "UTILITIES",   -- what is written on the disk; capitals, labelOk
  weight = 4,             -- out of 100; the remainder is a blank disk
  files  = { { name = "lights.sh", script = "lights.sh" },
             { name = "README.TXT", mode = 644, text = "..." } },
}
```

Five things to know:

- a file entry carries **either** `script` (a name in `CeroSecContent.SCRIPTS`,
  which brings its own mode) **or** `text` and `mode`. Never both.
- `README.TXT` is in **capitals**, and so is every name on a disk that is not a
  script: a 1993 floppy came out of a DOS machine. The bench holds every README to
  naming every file beside it **and only** files that are on it.
- the ceilings are the floppy's and they are small — 4096 bytes, 32 nodes. An entry
  over either is trimmed at fill time, so the bench weighs every entry.
- the weights are out of a hundred and **the remainder is blank**. Most of a box of
  disks is blank, which is what the floppy loot has always said.
- `BLANK` is in the table with no files on purpose: naming the entry a roll lands
  on when nothing is written lets the bench say so out loud.

Slots wave 7b fills: `BBS LIST`, `WARDIALER`, `GAMES`, `BACKUP`,
`CEROSEC OS UPGRADE`.

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
  mode = 755, args = { "light0", "light1" },
  needs = { devices = { { id = "light0", kind = "light", state = "on" } } },
  text = "#!/bin/sh\n...",
}
```

`args` is what the bench runs it with and `needs` is what it declares it wants
standing around it — the bench stubs exactly that and nothing else, so a script
that quietly reached for a second device would find it missing.
`tests/content_test.lua` **runs every script**, under the engine's own budget, with
its arguments and again with none, and holds every line of every one of them to
sixty columns.

## Versions

`CeroSecContent.VERSION` is the catalogue's own number and **must never become a
save-shape number**: nothing a profile writes is marked as having come from one, so
a later catalogue changes what the next untouched machine gets and changes nothing
about a machine somebody has already switched on.

Neither `STATE_VERSION` nor `SYSTEM_VERSION` moves for content. Seeding a file is
not a shape change (see [CONTRIBUTING.md](CONTRIBUTING.md#which-number-moves-and-when)),
and nothing here is put in `/bin`: a profile's scripts go in an account's own
`~/bin`, which `upgradeSystem` never touches.
