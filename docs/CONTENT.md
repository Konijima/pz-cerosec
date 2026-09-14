# CeroSec — World content

What is already on the machines, on the disks and on the papers of Knox County:
the mechanics of it, the catalogue format a change writes into, and how one number
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

**The hash is VM-independent now, and it was not before 2026-09-12.** Every value
documented in this file is what `lua5.1` computes, and that is the canonical one --
but the game computes on Kahlua, whose `%` operator is `a - (int)(a / b) * b` with a
32-bit `(int)` that clamps at 2147483647, and that made the mixer's `mul()` answer
different numbers in the game from the numbers in this document and in
`tests/fixtures/`. `CeroSecOS.mod` fixed it: nothing in here moved, the game moved
onto it. A save written by an older build therefore holds a different set of
generated values and passwords that no longer verify -- a one-time break, taken
before 0.1.0, written up in [RELEASE.md](RELEASE.md). The same day and the same
family: `tonumber(s, 16)` was nil on Kahlua above `0x7fffffff`, so
`CeroSecContent.number` returned nil for half of all keys and the first power-on of
a prefilled machine crashed; hex is parsed by `CeroSecOS.hexValue` now.

## What is keyed on what

| keyed on | what it decides | why |
| --- | --- | --- |
| **the premises** (its two bytes) | root's password, every account's login and password, **which telling of each file this company keeps** | so a paper found anywhere in that premises names something true of every machine in it, and two machines of one office read one office's readme |
| **the machine** (premises + square) | **whose desk it is**, which scripts are in `~/bin`, the hours in the log, **the shell history, the login records, the draft, whether somebody was left logged in** | the desk, not the company. Nothing a *paper* names may be keyed here. |
| **nothing** (a roll) | whether a floppy has content, whether a body carries a paper | the roll happens once and its *result* is saved on the item |

The three key builders are `CeroSecContent.rootKey`, `accountKey` and
`machineKey`, and the world-content work, part 3 added the fourth the first two only implied:
**`premisesKey`**, which is what a *telling* is chosen on. The rule that decides
which of the two a thing belongs to has not moved: **anything a premises IS must
be answered the same way from every square of it**, and anything about a desk is
the machine's.

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

`prefill` answers **five** things: the profile id, the root password, the logins by
slot, the session that was still open at the glass as `{ user =, at = }` or nil, and
what the machine turned out to **be** — `desk`, `floor` or `spare` (see *The shop
floor and the spare desk*). Two of its inputs are the world's and the catalogue may
not invent either: `opts.numbers`, telephone numbers of the machine's own region for
the `cu` line in somebody's history, and `opts.room` with `opts.desks` — the room
this machine stands in and the premises' page of the register.

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
that shipped in this change and was caught in review. The profile used to come from
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
  session  = false,      -- and never found with somebody still logged in
  accounts = { { name =, admin =, pass =, cron = { "0 2 * * * ..." },
                 files = { { path =, mode =, texts = { v1, v2, v3 } } } } },
  bin      = { { script = "lights.sh", chance = 60, to = "/usr/local/src" } },
  logs     = { "..." },  -- /var/log/messages, dated in the week before day one
  history  = { "cat ledger.txt", ... },   -- the owner's own ~/.sh_history lines
  lockup   = "sh bin/locks.sh lock lock0",-- the last thing he did before he left
  draft    = { v1, v2, v3 },              -- draft.txt, on about half the machines
  mail     = { { { to =, from =, subj =, back =, hour =, min =, body = } }, ... },
  cron     = { { to = "root", lines = { "0 * * * * ..." } } },
  files    = { { path =, mode =, owner =, texts = }, { path =, dir = true } },
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

And three fields the world-content work, part 2 added, each because a premises the county really has
could not be written without it:

- **`cron`** is a crontab, in Vixie's own five fields, written to
  `/var/spool/cron/<login>` exactly where `crontab(1)` writes one — root's, `600`,
  in root's `700` directory. It is a real crontab and the machine really runs it: a
  shop whose lights went off at ten every night is a shop whose lights still go off
  at ten. **Since the world-content work, part 3 there are two kinds of it.** A `cron` inside an *account*
  entry is that account's own and is written only on the machine he **owns**,
  because the line runs in his home with his `bin` on the path — the bookkeeper's
  nightly total reads *his* ledger, so on the desk beside his it would mail
  `no such file` once a night for ever. `profile.cron`, with a literal login in
  `to`, is the machine's own: the post's hourly door check out of `/usr/local/bin`,
  the vendor's weekly sweep of `/var`, neither of which names a home.
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
nothing about why. And a line naming a script of ours must name a file that is
**really on the machine the bench just built**, with `$HOME` resolved to the
crontab owner's own home.

That second half used to ask the *catalogue* — "does `profile.bin` always write
this path" — and the catalogue always says yes, so it was an assertion that could
not fail. the world-content work, part 3 found what it had been hiding: the military post's
`/usr/local/bin/check.sh` **was never written on any machine in the county**,
because `placeScripts` was called only for a machine with an ordinary account to
hang a `~/bin` under and the post has none. Its hourly crontab had been mailing
`not found` since 7b shipped. Fixed, and the bench walks the built filesystem now.

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

Every one of the ten is written, each in **three or four files** plus the history
that comes with them, and each carries at least one script a survivor can copy onto a
building of his own. Every prose file below is **three tellings** (above), so the
column names the file and not the words in it.

| id | host | root | accounts | what is on a desk |
| --- | --- | --- | --- | --- |
| `residential` | `ksp` | no | 2, both open | `notes.txt`, `porch.txt` (what a timer really is), a child's `report.txt` |
| `office` | `acct` | yes | 3 | `handover.txt` + `ledger.txt` + the nightly crontab that really runs `total.sh` on it; `readme.txt`; `memo.txt` |
| `police` | `disp` | yes | 3, one named `dispatch` | `handover.txt` + `bolo.txt` + the cells crontab; `shifts.txt`; `keys.txt`; and `/var/log/dispatch`, which stops in the middle of a line on the morning of the 9th |
| `bank` | `vault` | yes | 3 | `accounts.dat` in four plain columns, `audit.txt` (the examiner's answers, as two commands), `vault.txt`, `counter.txt` |
| `store` | `till` | yes | 2 | `inventory.txt`, `prices.txt` in cents, `closing.txt`, `note.txt` |
| `showroom` | `sales` | yes | 2 | the electronics dealer's own machine: `stock.txt` by model, `tickets.txt` (what is on the bench), `floor.txt` (how a display model is set up, and why root on one is the shop's), `counter.txt`. Every **other** machine of such a premises is stock — see below |
| `school` | `bell` | yes | 3 | `grades.txt` by student number, `bells.txt`, a `detention.txt` that will not write the names down, `library.txt` |
| `clinic` | `ward` | yes | 3 | `patients.txt` (rooms and wards, nothing medical), `rounds.txt`, `supplies.txt`, `nights.txt` |
| `radio` | `studio` | yes | 2 | `sched.txt`, `notes.txt`, `readme.txt`, and `/var/log/heard` — what the county sounded like from the 4th to the 9th |
| `military` | `post` | yes | **none** | `/root/memo-01.txt` to `-03.txt`, on the exclusion zone. `session = false`. |
| `cerosec` | `cerosec` | yes | 3, one named `support` | `bench.txt`, `answers.txt`, `tickets.txt`, `/usr/local/src/CHANGES` |

**Which of those files a player finds depends on whose desk he is at** — see *One
machine is one person's desk*. The five profiles whose third slot used to carry
nothing gained a file in the world-content work, part 3 (`keys.txt`, `counter.txt`, `library.txt`,
`nights.txt`, `tickets.txt`), because a machine whose owner is a slot with no files
is a machine with an empty home, and one desk in five was coming up bare.

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

## One machine is one person's desk

**The complaint this answers, in the words it was made in:** several computers in
one building held the same things, and every office in the county told the same
story with other names. Both halves were true, and the first one was the worse of
the two — every account's `files` were written onto every machine, so an office
with three people in it was three desks carrying the same three homes. That is not
an office. It is one machine copied three times.

So a machine has an **owner**: one slot of `profile.accounts`, chosen by
`CeroSecContent.ownerSlot` out of the **machine's** key.

- **his** home is the populated one — his files, his `~/bin`, his `~/.sh_history`,
  his `draft.txt`, his crontab if his slot declares one;
- the **other accounts are all still there**, with their own passwords, because the
  people are the premises' and a paper in a dead man's pocket has to be able to name
  one of them (see *What is keyed on what*). Their homes hold their own
  `.sh_history` and nothing else: two or three lines, because they sat down at
  somebody else's desk, looked at one thing and went away;
- a premises with **one** account has that account everywhere;
- a slot whose generated login collided with a name the machine already had is not
  the owner: the desk falls to the first slot that really got made, so a machine is
  never nobody's.

What a player meets, and it is the point: two computers in one office, the same
staff in `/etc/passwd` with the same passwords, the same root password on the paper
in the drawer — and two different men's desks, two different weeks in
`~/.sh_history`, two different sets of logins in `last`, and only one of them
running the nightly job.

## The shop floor and the spare desk

Two things a hash cannot do, and they were one complaint each.

A shop that **sells** computers had six of them — five in a row on the floor and one
at the counter — and every one came up as the same back office, with the same two
people and the same ledger. And an office with **three** people in it and five
machines in the room gave the fourth and fifth desk an owner who already had one,
because `ownerSlot` is a hash of the machine into the number of accounts and a hash
of five things into three repeats.

Both need one fact: **what the other machines of this premises already are.**

### Why the computers are not counted

The obvious answer is to enumerate the premises' computers at prefill and rank this
one among them. It cannot be made to hold. A premises' computers can only be found
by walking its rooms' squares, and a room answers its squares only while its chunks
are loaded — `RoomDef.getIsoRoom()` is **nil** for a room the streamer has not
brought in, which is written down at `CeroSecDevices.find` and is why `/dev` is
rescanned once a minute instead of remembered. A prefill is written **once and for
ever**. So a count taken through a half-loaded building — a player switching a
machine on from the wrong doorway — would hand two desks one owner permanently, in
the save, with nothing able to notice afterwards.

### The register

So there is a register: `system.desks`, saved with the save
(`CeroSec.SYSTEM_SAVE_KEYS`), keyed by the premises' own two bytes exactly as the
note bookkeeping is, and holding one entry per machine — a **slot number** for a desk
somebody sat at, or the word `floor` or `spare`.

```lua
system.desks["d.120.12"] = { desks = { ["8130.9254.0"] = 2,
                                       ["8133.9259.0"] = "floor" } }
```

It is on the system and not in memory for the reason `notes` is: the machines of one
premises are switched on over many sessions.

`CeroSecContent.deskRole(entry, tag, secret, mkey, profile, showroom, floor)` is the
whole rule, and it writes its answer down:

- a **showroom's sales floor** is stock, whatever else is known;
- otherwise the owner slot is picked out of the slots **not already taken**, by the
  machine's own hash among the free ones — so two premises with the same people fill
  their desks in different orders;
- **no free slot** is a spare desk;
- asked **twice** about one machine it answers the same thing and does not take a
  second slot, which is what a developer's reset and a machine carried out and put
  back need;
- **no register at all** — a bench, any caller without a system — is a desk with
  `ownerSlot`'s own answer, which is what every machine was before this existed.

**What it costs, plainly: the order the player switches the machines on is what
decides which desk is whose.** It is decided once, written down, and never revisited.
What does *not* depend on the order is the thing that was wrong: no two machines of
one premises share an owner, and the men who get a desk are the premises' own.

### Which machine is the shop's, and which is stock

A showroom machine's own **room** decides, and the room is a fact about its own
corner of the floor rather than about the premises — so it is asked of the machine's
square (`IsoGridSquare.getRoom()` → `IsoRoom.getName()`, answerable because the power
check has just proved that chunk is in) and never of the building's room list.

`electronicsstore` and `electronicstore` are the **sales floor**
(`CeroSecContent.FLOOR_ROOMS`); any other room of the premises — `electronicsstorage`,
an office, a storage room — is the **shop's own**, and the first back-room machine
switched on is the one that gets the staff image. A room the map did not name reads as
the floor, which is the safe way round: the shop's ledger does not go on a machine the
public types at. A shop whose only computers stand on the floor is a shop of display
models and nothing else, which is a true thing about such a shop.

### What is on a machine that is nobody's

One image for both, `CeroSecContent.DEMO`, because it is one thing — the disk the
dealer put on it before it went out of the door:

| | |
| --- | --- |
| **`floor`** | a display model. The dealer's hostname and the dealer's card for a motd, an open `demo` account, `WELCOME.TXT`, `DEMO.TXT` (the 1993 pitch, three tellings) and `PRICES.TXT` (the model line) in its home, and two or three lines in `.sh_history` where somebody who was not buying it typed at it. **No staff accounts at all** — it is stock, and the shop's people are not on a machine the shop has not sold. |
| **`spare`** | the desk in the corner nobody was given. The same disk, with the **premises'** hostname and motd, and the staff **are** on it with their passwords, because the machine is the company's. What is not on it is anybody's work. |

Neither carries mail, a week of log, a crontab, a draft or a session somebody left
open: none of that happened to this machine, and a file saying it had would be the one
kind of lie this catalogue is not allowed to tell. The open `demo` account needs no
declared deviation — an account with no password is a thing a 1993 machine had, and
the store's second account is already one.

**Root is the premises' on every machine of a premises, display models included.**
That is deliberate and it is what keeps the paper honest: there is one sticky note per
premises and it names root's password for the *premises*, so a display model with a
factory password of its own would be a paper that opens one machine in six. The shop
says so itself in `floor.txt` — it set them all up the same, because it is the shop
that has to fix them.

## Three tellings of every file

Every prose file of every profile is written **three** times
(`CeroSecContent.VARIANTS`), and which telling a premises reads is the
**premises'** own: `number(secret, premisesKey .. "/v/" .. file, 3)`, spelt
`CeroSecContent.variantOf`. Forty-two prose files, a hundred and twenty-six
tellings: thirty-nine in the profiles and three on the dealer's disk.

An entry carries one of:

| | |
| --- | --- |
| **`texts`** | three tellings. Every prose file. |
| **`text`** | one telling, and it has to be a `CeroSecContent.DATA` table: those are the very files the scripts are proved against, and a table that came out different on every machine would be a bench proving one of three. The bench asserts that a one-telling entry *is* a data table. |
| **`extra`** | three tails appended under a `text`. How a data table varies without moving: the six rows the bench adds up are still the six rows the bench adds up, and this branch's own accounts are under them. |

All of it goes through **`CeroSecContent.textFor`**, the one place a text is
composed, and **one number per file is spent on both** `texts` and `extra` — a
premises has one telling of one file, not two.

**The names go in at fill time.** A file is written once and read in every office
in the county, so the people in it are placeholders: `{owner}` is whoever sat at
*this* machine, `{staff1}`..`{staff3}` are the premises' accounts by slot, `{host}`
is the machine. `CeroSecContent.fillNames` puts them in; a placeholder with nobody
behind it becomes `somebody` and never a brace on the glass, which the bench
asserts of every telling of every file.

**There is no `{town}`**, and the reason is worth stating: a town name would have to
be derived from the telephone exchange's region, and nothing in the county knows
one — the exchange is a hash of a map coordinate and the map's own region names are
not data this mod has. An invented town is a town that is not on the map the player
is standing on, which is the same lie the BBS disk refuses to tell. Muldraugh and
West Point are named in one file because they are real places on the real map, named
as landmarks and not as this premises' own town.

### Four rules the three tellings are written to

1. **A telling is picked per FILE**, so telling 2 of the handover note stands beside
   telling 1 of the ledger. Any three may therefore be read side by side — which
   means anything one file depends on another for (the column that is cents, the
   name of a script, the number of a device) is the **same** in all three tellings
   of both. What varies is the voice, the person writing, the detail and the
   complaint. Never the machine underneath.
2. **Nothing names a date the save might not have**, except the two hand-kept logs
   that always did and may: `/var/log/dispatch` and `/var/log/heard` are about
   particular nights in July, and the outbreak is in July.
3. **Nobody signs his own name as somebody else's.** A file in slot 1's home is
   written *by* slot 1, so it names `{staff2}` and `{staff3}` and never `{staff1}`.
4. **No town.** Above.

## The history: what the last week looked like

Four files per machine, all derived from the **machine** key, all dated before the
save's own start, and written to agree with each other.

### `~/.sh_history`

The owner's, **12 to 30 lines** (`HISTORY_MIN`, `HISTORY_SPAN`). The body alternates
the profile's own `history` lines with `CeroSecContent.HIST_COMMON` — `ls`, `who`,
`date`, `df` — because nine tenths of a real history is housekeeping and one that
was all story would read like a film. Two typos out of `HIST_TYPOS`, and they are
typos in an **argument** and never in a command name: a man mistyping a filename is
a man, and a line whose first word is nonsense is a line the bench cannot tell from
a mistake in the catalogue. Then the tail, which is the only part written to be
read: `mail`, `cat /var/log/messages`, `who`, `date`, a `cu` call if there was a
number to ring, the last thing the profile says he locked (`lockup`), and
`shutdown -h now`.

Written at `<home>/.sh_history`, mode 600, owned by that account — the path and the
mode are what make it the file `history`, Up and Down and
`CeroSecOS.historyLines` all read. The bench reads it back through that function,
as the account, and puts the **first word of every line** through the shell's own
lookup (`CeroSecOS.whyNotRun`) on the machine the profile built: a history cannot
name a program this Unix has not got.

### `/var/log/wtmp`, which is what `last` prints

Seeded through **`CeroSecOS.wtmpAppend`**, record by record, **oldest first** —
because `last` pairs a login with the logout that closed it in the order the *file*
has them, and a file written any other way is a file whose sessions pair up wrongly.
Six to fourteen sessions over the fortnight before the save (`WTMP_DAYS`), the
**owner three in five** because it is his desk, the other staff and root the rest,
and the last session an hour to three before the save begins — the morning of it, on
the default save.

Every moment is computed **before** any length is, so that no man leaves after the
next man sat down.

### Somebody who never logged out

**About one machine in four** (`CeroSecContent.LIVE_ONE_IN`), and **never** the
military post, which carries `session = false`: a post was a room a man was let
into, and he was relieved or he left. `CeroSecContent.liveSession` decides it,
`prefill` answers it as a fourth return value `{ user =, at = }`, and
`SCeroSecObject:prefill` is where it reaches the glass — the account, his home as
the working directory, the moment `wtmp` says he sat down, and the environment a
login hands a shell. A player who opens that machine gets his prompt and is asked
for nothing.

Two things about it. **`booted` is left alone on purpose**, so the BIOS lines and
the motd still print above the prompt: a screen that came up already at a prompt
with nothing over it reads as a machine that is broken. And **it is a declared
deviation**. A real Unix cannot restore a session across a power cut and neither can
this one — a survivor's own machine comes back to `login:` every time, and that is
right. What this does is choose the story: `wtmp` says a man logged in on the
morning of it and never logged out, and the console agrees with `wtmp` instead of
with the boot sequence. It happens once in the life of a machine and it is written
down where it is done rather than hidden.

**The two halves are one fact told twice.** A machine left logged in has a `wtmp`
record with no logout behind it *and* a history that does not end on
`shutdown -h now`. A history carrying both would be calling itself a liar on one
screen, and the bench holds both directions.

### `/var/mail/<owner>`

A **story**: three to six messages over the outbreak week, in three tellings, with
the last one unanswered. Work, family, a colleague who is not coming in, the county
or the radio station about the roads and the cordon, a CeroSec Systems support
reply. One message of each telling goes to **another** staff member, so a survivor
who logs in as the wrong man still finds something in his spool.

The format is the machine's own twice over: the separator is the
`From <sender>  <date>` line **`CeroSecOS.mailAppend`** writes, so a mailbox this
seeds and a mailbox `cron` appends to are one file `mail` reads from end to end —
and under it are the four headers a message really carries, `From:`, `To:`, `Date:`
and `Subject:`. The envelope line above repeating the sender and the date is not a
mistake: that is what an mbox is, and it is how `mail` tells one message from the
next.

Outside senders carry a **UUCP bang path** (`county!clerk`, `wknx!news`,
`cerosec!support`), which is how mail reached a 1993 desk machine nobody was logged
into; a local delivery carries a plain name or a role.

`back` is **days before the start day** and never a date, so a save that begins in
October gets a week dated in October. A message that would land at or after the
moment the save begins is **dropped** rather than moved — the trimming rule — and it
costs a save that starts at half past midnight its last message and nothing else.
Bounded by `MAIL_LINES` and `MAIL_BYTES` here, because a mailbox is exempt from the
disk quota by its path and nothing else would bound it.

### The outbreak week in `/var/log/messages`, and the draft

`placeLog` writes the premises' own `logs` and then **three** entries off
`CeroSecContent.LOG_EVENTS` — a machine that came back up on its own, a refused
login, a call that got `no carrier` — at the **hours nobody is at a desk**: the
premises' own lines are dated 07:00 to 16:00 and these are 00:00 to 05:00, which is
also how the bench tells them apart. Nothing in that list claims a halt, because
the dispatch desk's own log is a file people typed in until five in the morning on
the 9th and two files on one screen may not call each other liars.

And `draft.txt`, in the owner's home, on **about half** the machines: a page he was
writing that stops in the middle of a sentence. Three tellings, and the bench holds
every one of them to not ending on a full stop.

### The `cu` line, and why the server has to help

A telephone number in a history has to be a number **this** county really has, and
the catalogue has no world and may not guess — the same rule that keeps the BBS
disk's numbers a stub until somebody puts the disk in a machine. So the server hands
`prefill` a list: **`CeroSecNet.regionNumbers(x, y, b1, b2, max)`** asks the
machine's own region for its listings the way `fillLateDisk` does, takes the
premises' own line out of them (a man does not ring the telephone on his own desk),
and hands over at most `CeroSecContent.DIAL_MAX` of them. A machine with no listings
in its region simply has **no `cu` line**.

The cost is one zone sweep of one region, once in the life of a machine, at the
power-on where the chunk is already known to be loaded — the same sweep the
telephone book does when a player opens it.

## The disk catalogue

```lua
CeroSecContent.DISKS[i] = {
  id     = "UTILITIES",   -- what the entry is called here and in the bench
  label  = "UTILITIES",   -- what is written on the disk; capitals, labelOk
  weight = 3,             -- out of 100; the remainder is a blank disk
  late   = "NUMBERS.TXT", -- one file is a stub until the disk is first inserted
  files  = { { name = "lights.sh", script = "lights.sh" },
             { name = "README.TXT", mode = 644, text = "..." },
             { name = "DIARY.TXT", mode = 644,
               texts = { "...", "...", "..." } },   -- three tellings
             { name = "MAN", dir = true },
             { name = "MAN/CU.TXT", mode = 644, text = "..." } },
}
```

Five things to know:

- a file entry carries **either** `script` (a name in `CeroSecContent.SCRIPTS`,
  which brings its own mode) **or** `text` and `mode`, **or** `texts` and `mode`
  for a file written three ways (see *Three tellings of a disk* below). An entry
  marked
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

### The nine as shipped

| label | share | tellings | what is on it |
| --- | --- | --- | --- |
| `UTILITIES` | 3 | one | `lights.sh`, `check.sh`, and a README saying why neither names a device of its own |
| `BBS LIST` | 2 | one | `NUMBERS.TXT` (**late**, see below), `CALLS.TXT` — packet stations somebody heard, by callsign — and how to reach either |
| `WARDIALER` | 1 | one | `RANGE.TXT`, `log.sh`, and a README whose first screen says there is no wardialer and why |
| `GAMES` | 2 | one | `guess.sh`, `hangman.sh`, `adventure.sh`, `WORDS.TXT` — 3651 of the floppy's 4096 bytes spent on the programs |
| `BACKUP` | 2 | **three** | somebody's home directory on 8 July: `DIARY.TXT`, `LETTERS.TXT`, `FAMILY.TXT` |
| `CEROSEC OS 1.0 DIST` | 2 | one | `INSTALL.TXT`, `MAN/` with six pages, three scripts |
| `LEDGER` | 2 | **three** | a shop's books: `SALES.TXT` (a line a day, in cents), `SUPPLIERS.TXT`, `total.sh` |
| `PERSONAL` | 2 | **three** | `LETTERS.TXT` (never sent, the last one dated the 8th or 9th of July), `TODO.TXT`, `RECIPE.TXT`, `POEM.TXT`, `NUMBERS.TXT` |
| `RADIO LOG` | 1 | **three** | a ham club's `HEARD.LOG` of the week before, `NETS.TXT`, `MYCALL.TXT`, and a README on `cu -l /dev/radio0` and `MHEARD` |

**Still seventeen shares of a hundred.** `LEDGER`, `PERSONAL` and `RADIO LOG` were
paid for out of the six that were already there and not out of the blank remainder:
`UTILITIES` went from 4 to 3, `BBS LIST` from 3 to 2, `WARDIALER` from 2 to 1,
`GAMES` from 3 to 2 and `BACKUP` from 3 to 2, which is five shares for three new
disks at 2, 2 and 1. So the other eighty-three are still a blank disk, which is what
a box of disks is, and what changed is only what a written one says.

### Three tellings of a disk

**The complaint, in the words it was made in:** the loot floppies have one content
per kind, so the `BACKUP` diary is the same all over the county. A profile already
answers that — three tellings of every prose file, chosen by the premises — and a
disk cannot borrow that answer: **a disk has no premises.** It is in a drawer in a
town nobody has walked into, which is the same hole `late` was dug for.

So a disk's telling is **a second roll at creation**, `ZombRand(VARIANTS)` beside
the roll that chose the kind, in `CeroSecContent.onCreateFloppy`.

**Not derived from the kind's roll**, and that is the part worth stating: the kind's
roll is 1..100 spent against a weight, so an entry with a share of one is reached by
exactly one roll and would carry exactly one telling for ever. Every entry has all
three whatever its share of the box is.

**Where the choice persists: in `disk.fs`, as the bytes themselves.** A disk owns
three keys and only three (`CeroSecOS.DISK_KEYS`) and the slot takes those three off
the item and no others, so there is nowhere of ours to write a variant number — and nothing to write, because
what a telling produces is a filesystem, and the filesystem is what goes into the
item's modData and comes back out of the save with it. **Nothing rolls at read
time.** A disk read twice is the same disk and a disk read in the next save is still
the disk it was written as, which is exactly the shape the hook already had for which
*kind* of disk this is: roll once, keep the answer, never ask again. The bench asserts
it through the hook, called a second time on the same item with a generator that
would answer a different telling.

**Which files vary.** The four disks that are somebody's **own writing** —
`BACKUP`, `LEDGER`, `PERSONAL`, `RADIO LOG` — carry `texts` on every file including
the README, because a shopkeeper's note to himself is his and the shop in the next
town had another shopkeeper in it. The other five are a vendor's or a program's
documentation and keep **one shape**: three voices of one manual page would be three
manual pages. And two kinds of file keep one shape wherever they are:

- **data a script is proved against.** `SALES.TXT` is the column the bench adds up
  (158244 cents, and 346 tickets), so it is the column every copy carries — the same
  rule a profile's `CeroSecContent.DATA` table obeys. `RANGE.TXT` and `WORDS.TXT` are
  the same case.
- **a `late` stub.** The fill decides whether a disk is still waiting by comparing
  the file byte for byte against the catalogue's own stub, so three stubs would be
  two disks in three that never get their listings. `CeroSecContent.lateFile` only
  ever answers a `text`, so this one is refused by construction and asserted anyway.

**The names go in at build time**, out of `CeroSecContent.NAMES`, and they are the
**telling's**: `CeroSecContent.diskNames` walks the first-name list at a stride per
placeholder and a stride per telling, so telling one is always the same four people.
It cannot be a hash of the save's secret the way a profile's staff are — the hook
runs wherever an item is instanced, a client included, and the secret is the
server's. There is no `{host}` on a disk: a disk that named a machine would name the
wrong one on every machine but the first. A placeholder with nobody behind it becomes
`somebody`, and the bench asserts no brace survives in any telling of any file.

`LEDGER` carries `total.sh` out of the shared library rather than a copy of its own,
which is the same one-copy-named-twice rule the profiles follow: the script the shop
runs on its own books is the script the bench runs.

### And a seventh that is not loot: `CEROSEC DIAGNOSTICS`

**Weight 0.** `CeroSecContent.diskForRoll` skips any entry whose weight is not above
zero, so no drawer in the county has one and no roll can reach it — which
`content_test.lua` section 7c asserts over all hundred rolls rather than off the
field, because "weight 0" is the mechanism and "no roll lands on it" is the
requirement. The only way to one is the debug window's **Give diagnostics disk**,
behind `CeroSec.debugAllowed` like everything else on that glass
([DEBUG.md](DEBUG.md)).

On it: `selftest.sh`, `RESULTS.TXT` and a `README.TXT`. The script is **twenty-six
checks of the shell** — the commands, the pipes, the redirects, the `$(( ))` reader
and the filesystem — and it is there because the mod's whole headless suite runs on
`lua5.1` while the game runs Kahlua, and the shell is the half of the mod no
pure-function vector can reach. What each of the three testing layers proves is in
[TESTING.md](TESTING.md); it is a release gate ([RELEASE.md](RELEASE.md) step 6b).

Four things about it are worth knowing before touching it:

- **One script and not a `t1.sh`/`t2.sh` split.** Twenty-six checks fit in 3754 of
  the floppy's 4096 bytes, which leaves about three hundred and forty. That matters:
  `RESULTS.TXT` grows when it is run, and the room left is what bounds how many
  failure lines can be written under the verdict. The verdict is written **first** for
  that reason, so a disk that fills still carries it. A check added to the script
  comes out of the same three hundred and forty bytes, and section 7c's byte
  assertions are what say so.
- **No counters between scripts, had it been split.** A script is a job of its own
  and its variables go with it, so two parts would have had to pass their tally
  through a file. As one script the pass count is a variable `p`, and the failures are
  lines in a scratch file — deliberately two different places, so a miscount cannot
  make itself agree.
- **`RESULTS.TXT` ships as a stub at mode 666,** and the mode is the whole point.
  `/mnt` is root's, so an ordinary account cannot *make* a file on a floppy, but it
  may write one that is already there and says anybody may. Without that entry the
  last lines of the script are `permission denied` on every machine a survivor is not
  root on.
- **The hash in it is baked and is held to the engine.** The `mkpasswd` check compares
  against `$cs1$abcdef$74a6...` written into the script, because there is no `lua5.1`
  in the game to ask for it — and section 7c holds that string to
  `CeroSecOS.hashPassword(CeroSecSelfTest.PASS_TEXT, PASS_SALT)`. So the day
  `HASH_ROUNDS` or the mixer moves, the headless suite goes red and the floppy is
  rewritten, rather than the in-game run going red for a reason nobody can place. It
  is the check that would have caught the `%` bug: four thousand rounds of a mixer
  that is nothing but modulo.

Two things the script cannot ask, and both are steps in
[PARCOURS-TEST.md](PARCOURS-TEST.md) section X instead: a **crontab round trip**
(a crontab is writable only through `crontab -e`, which wants a terminal) and a
**permission refusal** (that needs a second account, and `su` and `sudo` both put a
question on the glass a script cannot answer).

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
three (`CeroSecOS.DISK_KEYS`) and the slot takes those three off the item and copies
nothing else, which is what keeps a payload out of the save file — so there is nowhere
on a disk to write a flag and nothing that would survive being written there. The mark is
**the file**: `CeroSecContent.lateEntryFor` answers the entry only while the late file
still holds, byte for byte, the stub the catalogue shipped, and the stub it compares
against *is* the catalogue's own text, so a change that edited the stub and forgot the
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

**A declared deviation.** The design for this change said to hash the item's id.
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

### The fourteen as shipped

| | |
| --- | --- |
| `lights.sh <light>...` | switch the lights you name off |
| `lamps.sh <light>...` | and the other direction: switch them on |
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
being a world-content work: `$(( ))` cannot read a positional parameter. `$((5 % $1))`
answers `bad arithmetic`, because the arithmetic reader takes a name to be
`[A-Za-z_]` (`arithUnit` in `CeroSecOSVM.lua`) and a real `sh` reads `$1` there.
Every script here assigns it to a name first.

## Versions

`CeroSecContent.VERSION` is **6** as of the change that made about one premises in
three automated before the outbreak: `lamps.sh`, a morning line in the three
crontabs that put lights out, and the roll in `CeroSecContent.automated`.
(**5** gave the electronics shop a
profile of its own and put the dealer's demonstration disk on every machine that is
nobody's desk; **4** gave every loot disk that is
somebody's own writing three tellings and added `LEDGER`, `PERSONAL` and `RADIO LOG`
out of the same seventeen shares; **3** gave every machine an owner,
every prose file three tellings, and every desk a week of history behind it; **2**
was the world-content work, part 2, which filled the eight empty profiles and the five empty disk slots.) It
is the catalogue's own number and **must
never become a save-shape number**: nothing a profile writes is marked as having come from one, so
a later catalogue changes what the next untouched machine gets and changes nothing
about a machine somebody has already switched on.

Neither `STATE_VERSION` nor `SYSTEM_VERSION` moves for content. Seeding a file is
not a shape change (see [CONTRIBUTING.md](CONTRIBUTING.md#which-number-moves-and-when)),
and nothing here is put in `/bin`: a profile's scripts go in an account's own
`~/bin`, which `upgradeSystem` never touches.
