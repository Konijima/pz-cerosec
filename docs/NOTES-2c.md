# Rung 2c — system files, for folding into the README

Written here rather than into `README.md` because the README is being
restructured in parallel. Everything below is the state of the code on branch
`wave-2c`.

## The shape of a machine

A machine is a filesystem and nothing else. What makes it usable is what is *in*
the filesystem:

- `/bin` — one executable per shell command.
- `/etc/passwd` — the accounts.
- `/etc/hostname` — the machine's name.
- `/etc/motd` — what greets whoever logs in.

There is no table of users on the state any more and no list of commands beside
the Lua. Root can take any of these away — that is what root is, and the
protection is that root has a password — and the way back is the BIOS.

## `/bin`: a command is a file

At `newState`, and again after a BIOS restore, `/bin/<name>` exists for every
shell command: **owner `root`, mode `755`, and the file's contents are the
one-line description `help` prints**. `cat /bin/ls` prints `list a directory`.

The shell resolves `args[1]` by looking up `/bin/<name>` for the session that
typed it:

| what is at `/bin/<name>` | what the shell says |
| --- | --- |
| nothing, or no `/bin` at all, or `/bin` is a file | `<name>: command not found` |
| a directory | `<name>: command not found` |
| a file without `x` for this user | `<name>: permission denied` |
| `/bin` itself unreadable for this user (`chmod 700 /bin`) | `<name>: permission denied` |
| a file with `x`, and a Lua command behind it | it runs |
| a file with `x`, and **no** Lua command behind it | `<name>: command not found` |

Root bypasses the mode bits here as everywhere else, so `chmod 644 /bin/ls`
stops `admin` and not `root`.

**Builtins.** `exit` and `help` run whether or not `/bin` has anything in it.
That is the whole list, and the reason is that a player who has just wiped the
machine he is standing at must still be able to ask what happened and to walk
away from it. With no `/bin`, `help` says:

```
help: no commands in /bin: the system is damaged.
help: switch the computer off and on to repair it.
```

**Not supported yet:** copying `/bin/ls` into a home directory and running it.
Commands are found in `/bin` and nowhere else — there is no `PATH` and no
`./thing`. The copy is an ordinary file and the shell will not look at it.

## `/etc/passwd`: the accounts

One account a line, four colon-separated fields:

```
name:$cs1$<salt>$<32 hex digits>:home:admin|user
```

`root:$cs1$mdhyft$b24d…:/root:admin`

Owner `root`, mode `600` by default — so `cat /etc/passwd` as `admin` is
`cat: /etc/passwd: permission denied`. The kernel reads it without going through
the permission bits (`CeroSecOS.systemNode`), because there is no session that
could read it and none to read it with: nobody is logged in yet. That is the one
read in the whole core that does not go through `getNode`.

**Parsing is strict and silent.** A line is skipped when it is not exactly four
fields, when the name is not a valid name, when the second field is not one of
our `$cs1$` strings, when the home is not an absolute path of
`[A-Za-z0-9._/-]`, or when the last field is neither `admin` nor `user`. A name
that appears twice keeps its **first** line. A file that parses to nothing is a
machine nobody can log in to — which is the BIOS' business, not an error.

`login`, `passwd`, `cd` with no argument, `chown`'s "no such user" and the
`#`/`$` in the prompt all read this file. It is parsed on demand and cached in
one slot keyed on the node **and its text**, so any write — `passwd`, a
redirect, root saving it out of the editor — invalidates the cache by
construction. `whoami` still prints the session's own user: the session was
built from the file at login, and deleting somebody's line does not log him out.

`passwd` rewrites the **whole file** through the ordinary `setData` path, so the
ceilings and the printable-byte rule apply to it, and a refusal leaves
`/etc/passwd` byte for byte as it was rather than half rewritten.

## `/etc/hostname` and `/etc/motd`

`hostname` with no argument prints the file. `hostname <name>` writes it and is
**root only** (`hostname: permission denied` for anybody else). The rule: 1 to
16 characters of `[a-z0-9-]`, not starting with `-`; anything else is
`hostname: <name>: invalid name`. (The no-leading-dash part is not decoration:
the name is also written into `state.hostname`, where `validate` tests it with
`isValidName`, which refuses a leading dash. A hostname that was not a name
would make the machine unbootable the moment it was set.)

A file that does not hold a name — nonsense, two words, deleted — falls back to
`state.hostname`, and then to `CeroSecOS.DEFAULT_HOSTNAME`. The server reads the
file for the window title and for every prompt, so a rename by hand in the
editor takes effect too; the title bar is set when a window opens, so a rename
shows on the next open.

`/etc/motd` is what is printed after a login (and at the end of the boot),
capped at 10 lines. A missing or empty file falls back to the built-in
`CeroSecOS.MOTD` line.

## The BIOS

On `open`, before anything is put on the screen, the console looks at the disk.
The machine has no operating system when any of these is true:

- the state does not validate (`SCeroSecObject:osState()` returns nil), or
- `/bin` is missing, is not a directory, or is empty, or
- `/etc/passwd` is missing, is not a file, or parses to no accounts at all.

Then the boot ends on:

```
No operating system found.
Restore system? (y/n)
```

That is an ordinary console prompt with an ordinary continuation token
(`cont = { cmd = "bios" }`), so the terminal window needed no change at all: it
draws the prompt it is handed and sends the line back. The token is answered on
the server and never by `CeroSecOS.continue`, because there is no session to run
it under.

- **`y`** → `CeroSecOS.restoreSystem(state)`, then `Restoring system ...`, the
  motd, and `login:`.
- **`n`** → the screen stays on `No operating system found.` with nothing asked.
  Anything typed at it (any line, Enter included) brings the question back.
- **`exit`**, or Escape → the window closes.
- anything else → the question is asked again.

The refusal is the machine's, not the window's: a second player opening a window
on a halted machine finds the refusal, not a fresh question.

### What `restoreSystem` touches

- `/etc` — made if missing or if it is not a directory.
- `/etc/hostname`, `/etc/motd` — created **only if missing**.
- `/etc/passwd` — replaced with the two shipped accounts (`root` and `admin`,
  both open, mode 600) **only if it is missing, is not a file, or parses to no
  accounts**. A file that still parses is kept, hashes and all: losing the
  accounts is not part of repairing the commands, and a root password somebody
  set is not something a repair may quietly drop.
- `/bin` — made if missing or not a directory, then every standard executable is
  written with owner `root`, mode `755` and its description. It is authoritative
  for those, so `chmod 000 /bin/ls` is repaired too. Any **other** file in `/bin`
  is left exactly where it is.
- The filesystem root itself, if the state has no usable one.

It touches **nothing else**: `/home`, `/root`, `/dev` and anything a player made
come through a repair untouched. Running it twice changes not one node and not
one byte.

If the state was refused by the validator for a reason the repair does not
address (a control byte in a file under `/home`, a tree over the node ceiling),
the machine comes back to `No operating system found.` and asks again. That is
honest: the BIOS puts the system files back, it is not a disk doctor.

## Migration of existing saves

- A save from **rung 2b** (accounts in a `state.users` table, `/bin` empty):
  `CeroSecOS.migrateUsers` hashes anything still in clear, writes
  `/etc/passwd` from the table, fills `/bin`, and drops the table. Such a save
  boots straight to its login prompt, with the same accounts, homes, admin flags
  and passwords it had. `/bin` is filled here on purpose: that machine was made
  before there were executables, so it is not damage and should not meet a BIOS.
- A save that somehow has **both** a table and a parseable `/etc/passwd`: the
  **file wins** and the table is dropped. What the machine has been running on is
  not something a migration may replace.
- A save of an unknown version, or junk: a brand new machine, as before.
- Damage done **in the game** (`rm -r /bin`, `write /etc/passwd "rubbish"`) is a
  different thing and goes through the BIOS restore.

`validate` no longer knows anything about users. It checks that `/etc/passwd`
exists, is a file, and is owned by `root` — the rest is the parser's business.

## API verification

No new game API is called in this wave. Everything added is pure Lua in the OS
core plus server-side logic on top of calls rung 2 already verified
(`sendServerCommand`, `getTimestampMs`, `SGlobalObject*`). `tests/kahlua-check.sh`
covers the new engine file, and `tests/selfcalls-check.sh` covers the new
methods on `SCeroSecSystem` and `SCeroSecObject`.
