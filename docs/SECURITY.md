# CeroSec — Security

What the password hash protects and does not, what root can and cannot undo,
what the scheduler guarantees against a hostile script, and why a remote link
never lets a password be skipped by accident.

See also: [ARCHITECTURE.md](ARCHITECTURE.md) for the BIOS and the system files
root can rewrite, [SCRIPTING.md](SCRIPTING.md) for the budgets that bound a
script, [NETWORK.md](NETWORK.md) for the trust files in full.

## Passwords

Passwords are stored as `$cs1$<salt>$<32 hex digits>`, never in clear: a fresh
six-digit salt per account, run through 4000 rounds of 32-bit add/multiply/rotate
mixing written in the arithmetic Kahlua has (no bit library, no packing, no integer
division). Be honest about what that is: it is not bcrypt, not scrypt, not even
SHA-2. Somebody willing to write a cracker will get a password out of a save file.
What it protects against is narrower and still worth having: reading the save file,
or a future `/etc/passwd` on the machine itself, does not simply hand the passwords
over, and two accounts with the same password do not look alike. A machine saved
before hashing existed has its passwords hashed in place on load, with a fresh salt
each.

## What root can and cannot undo

Root bypasses every permission check before anything else is asked
(`CeroSecOS.can`), with the one exception a real machine keeps: execute on a
non-directory needs at least one of the three `x` bits set, so `chmod 600
/bin/ls` locks `ls` for root too (4.4BSD `vaccess()`, POSIX "appropriate
privileges"). Root may rewrite any system file including its own way in —
`/etc/passwd`, `/etc/sudoers`, `/etc/group`, `/bin` itself. The one way back from
a machine broken this way is the BIOS repair (`CeroSecOS.restoreSystem`), and it
is deliberately narrow: it remakes `/etc`, `/bin` and the filesystem root only
when they are missing or will not parse, and it never touches `/home`, `/root`,
`/dev` or anything a player made — so restoring a machine never hands back a
password, a history, or a file root chose to delete. See
[ARCHITECTURE.md](ARCHITECTURE.md#system-files-and-their-formats) for the file
formats and the BIOS gate itself.

`/etc/sudoers` is the sole authority on who may `sudo`. A line is an account name
or a `%group`, and the shipped file carries both: `admin` by name, and `%wheel`.
Being in the `sudo` group gives out the group's own files and nothing else — it is
that file's mirror and never its authority — while being in `wheel` really does
grant root, because `/etc/sudoers` says so. `useradd -G wheel <login>` and
`usermod -G wheel <login>` are therefore **power grants** and are root's alone, the
way editing the file is; the `admin` flag on an `/etc/passwd` line reports that
membership and grants nothing on its own. Root is never looked up in `/etc/sudoers`
— an empty sudoers file must not be able to take `sudo` away from the one account
that could put it back.

`userdel` sweeps the name out of `/etc/sudoers` **and out of every group**, in one
write each: a name left in `wheel` is root waiting for whoever is given that name
next.

## What the server guarantees against a script

No Lua is ever evaluated from a file the OS core reads: the parser
(`CeroSecOS.parseScript`) builds inert plain tables, never `load`, `loadstring`,
`setfenv` or a metatable, and `tests/kahlua-check.sh` greps the shipped files for
the constructs that would smuggle one in. A runaway script cannot take the server
down or slow any other machine: every job runs on a step budget under a
per-machine and per-tick ceiling, output is throttled per machine, and a job that
holds the processor with no wait in it for longer than the CPU ceiling is killed
outright. See [SCRIPTING.md](SCRIPTING.md#underneath-the-step-machine-the-job-and-the-scheduler)
for the constants and the scheduler that enforces them.

## What the server guarantees against a flood of packets

A script is bounded by the scheduler; a **client** is bounded at the door. `open` is the
dearest packet this mod has and the only one that is dear on the way back out too: it
identifies the machine, decides the boot, builds the screen and then ships the console's
history lines to the sender, so a flood of them is a network amplifier as well as server
time. Two bounds, and they are different things:

- **The watcher table is bounded** (`SCeroSecObject:addWatcher`): one live window per
  player per machine, eight per machine whatever the online ids say. The key is the
  token the *client* picked, so without this an `open` with a fresh token each time
  bought one permanent entry apiece — and every entry is a `sendServerCommand` on every
  later screen of that machine, paid by whoever types at it next.
- **And the packet itself is rate-limited** (`SCeroSecSystem:mayOpen`): at most
  `SCeroSecSystem.OPEN_PER_SECOND` = 4 openings per player per real second, counted on
  `getTimestampMs()` — the same clock and the same shape vanilla throttles a client
  command with server-side (`forageServer.onRequestZone`). Past the cap the packet is
  dropped with **no reply at all**, because a refusal is a confirmation that the packet
  arrived and a second thing for the server to send; the drop goes in `CeroSec.log`
  once per second per player instead, which is what a server owner reads. The book of
  timestamps is keyed on the online id, which is not ours, so entries older than a few
  seconds are dropped on the way in — there is no vanilla event for a player leaving
  (`OnPlayerDisconnect` does not exist, and `OnDisconnect` is the client's own
  connection failing), so age is the whole of the bound.

Four is far above anything a survivor does: the client shuts its own previous terminal
before it sends one (`CeroSecTerminal.open`), and the reopen after a reboot is the
server's own doing and comes through no packet. Both bounds are walked on the wire in
`tests/hostile_test.lua` (26c and 26d) and in `tests/window_test.lua`, against five
thousand packets from one client.

### The typing sound is the one packet this mod cannot bound

Keystrokes are audible to the players near a terminal. That is the vanilla
`PlaySound` packet (`character:playSound`), not one of ours, so there is no door of
the mod's own to rate-limit it at: the server relays it in Java, checks only that
the name is not empty (`PlaySoundPacket.isConsistent`), and does not check that the
sender owns the character it names. The only bound is the honest client's own: at
most one such packet per `CeroSecTerminal.KEY_NET_MS` (200 ms), five a second. A
modified client can send that same packet for any sound in the game whether this
mod is installed or not, so this adds no capability; but it is the one place where
"a client is bounded at the door" is not true, and a server owner should know it.

## Remote sessions: a password every time

Neither the telephone nor the radio consults a trust file, ever: `/etc/hosts.equiv`
and `~/.rhosts` are lists of *machines*, and a call or a transmission carries no
machine, only a number or a callsign — so a session that skips a password on the
coax always asks for one over the wire and over the air. On the coax itself, a
trust file is checked exactly as `rlogind`/`ruserok(3)` check it: a `.rhosts` not
owned by the account, or writable by anyone else, is ignored without a word,
because a login that could be redirected by editing someone else's trust file
would not be trust at all. See [NETWORK.md](NETWORK.md) for the full rule and
for `rsh`'s own no-terminal, no-trust-prompt behaviour.

**A machine cannot name itself into trust.** A trust line may carry a name or an
address, and the name is resolved through the TRUSTING machine's own
`/etc/hosts`, against the address the session arrived from
(`CeroSecOS.trustWords`). It is never matched against the name the caller
announces: `/etc/hostname` is a `644` file its own root may write to anything and
`ruptime` prints whatever it says, so a machine that matched on the announced
name would let anybody with root on any computer in the building type
`hostname gate` and walk in through a line somebody wrote about `gate`. The same
rule is what makes a caller with no address — a call, a radio link — trusted by
neither file, and what `who`, `last` and `/var/log/wtmp` record: the name the
receiving machine's own `/etc/hosts` gives the caller's address, else the bare
address.

## Standing outside reaches nothing inside

Three rungs used to give a survivor on the pavement something that belongs to the
house beside him, and all three now read the same test -- a square whose
`getRoom()` is not `nil` is not his:

- **the `/dev` walk.** A machine in no building falls back to a ten-tile radius,
  and the radius takes nothing of a building: not the light switch inside, not the
  front door or the porch lamp, whose objects stand on the pavement square itself
  (`scanOutdoorSquare`, `facesARoom`). See [DEVICES.md](DEVICES.md).
- **the coax.** A machine carried out of a house keeps its address -- somebody
  wrote it in `/etc/hosts` -- and loses the wire: to be on a premises' segment a
  machine must be standing in that premises (`oneWire`). Two machines *outdoors*
  with one pair of bytes are on a wire within `CeroSecDevices.RADIUS` of each
  other, which is the base somebody built and nothing else. See
  [NETWORK.md](NETWORK.md).
- **the TNC.** The one-tile fallback skips a neighbouring square that has a room,
  so a computer on a pavement is not wired to the household's set through the wall
  (`CeroSecRadio.tncAt`).
- **the motion sensor.** A room-less sensor's box drops every candidate tile that
  turns out to have a room of its own, so one set against a house wall reads the
  pavement round it and never the room behind it (`CeroSecSensors.fieldOf`). It is
  another rung on this same ladder, not a special case.

`getRoom()` and not `isInARoom()`, in all three: the second answers true for a
player-built base off `getIsoWorldRegion().isPlayerRoom()`, and a base is what
every one of these fallbacks exists for. Anything of a building, from outside,
costs a cable.

## The debug window is not a player's door

The debug window can reset a machine, clear an account's password, hand out root at
the glass and print every derived password on a computer in clear (see
[DEBUG.md](DEBUG.md), *The things it can change*). None of that is a thing a player
may do, so both ends of every one of its commands ask the same question and the
server's answer is the only one that counts.

`CeroSec.debugAllowed(playerObj)` is the whole door: the release flag
(`CeroSec.DEV_DEBUG_MENU`, `false` in a shipped build), OR the game's own debug mode,
OR the asking player's access level being **admin**.

Three rules keep it a door rather than a suggestion:

- **The level is read off the player the ENGINE handed `OnClientCommand`.** Never a
  field on the command's `args`, which would be a client answering a question about
  itself. `tests/window_test.lua` sends `admin = true`, `accessLevel = "admin"` and
  three more spellings of it from a player at `none` and the machine does not move.
- **Admin, not moderator.** Vanilla's admin context menu takes either; the vanilla
  tools that CHANGE the world take admin alone (`ISWorldMap.lua:36`), and this window
  changes more than the map does.
- **A refused command is silence and not a refusal.** With the door shut, nothing is
  answered and nothing is acted on -- a released build does not tell a client what it
  would have said, because a refusal that names an act is a list of acts.

**What the window can read is not a security boundary, and never was.** The save's
own secret is in the save file, so a single-player player who reads his own save can
derive every password in the county with or without this window (see
[CONTENT.md](CONTENT.md), *The per-save secret*). On a server the save is on the
server, which is the whole of the difference -- and the secret itself is never put in
any reply, any log line or any packet.
