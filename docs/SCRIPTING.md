# CeroSec — Scripting

The shell language, from typing at the prompt to writing a script file: grammar,
completion, history, pipes, cron, job control, and underneath, the step machine
that runs it all on a budget so no script can hurt the server.

See also: [PLAYERS.md](PLAYERS.md) for the commands themselves,
[ARCHITECTURE.md](ARCHITECTURE.md) for the engine it runs inside,
[CONTRIBUTING.md](CONTRIBUTING.md) for the no-eval rule this file is proof of.

## The prompt is the script language

**The prompt is the script language.** There is no second, simpler shell for typed
lines: every line goes through the same parser a file does and runs as a foreground
job on the console's own environment. So this works where you type it:

```
admin@ksp-04-11:~$ while true; do echo tick; sleep 1; done &
[1] 43
admin@ksp-04-11:~$ jobs
[1] sleeping while true; do echo tick; sleep 1; done &
admin@ksp-04-11:~$ kill %1
[1] killed
```

Multi-line constructs go on one line, all of it. There is no continuation prompt:
a line with an unfinished construct answers `sh: syntax error: missing 'done'` and
nothing runs. A refusal the shell itself makes carries no line number — a typed line
is line one of nothing — but past the first level it is inside a file again
(`sh backup.sh`) and that file's name and line come back.

Variables and `$?` belong to the machine: `x=5` on one line and `echo $x` on the
next are the same environment, and walking away and coming back finds it. Logging
out takes them, as it takes the rest of the session. `cd` at the prompt moves the
console; `cd` inside a script moves the script.

`ps` shows the shell you are typing into, the way every Unix `ps` does; `jobs` does
not, because a shell is not a background job. That is also why the first background
job is `[1] 43` and not `[1] 42` — the shell itself took 42 — and the four-job
ceiling is still four *scripts*.

**The jobs belong to the MACHINE, not to the shell.** This is the one place the
model differs from a real `sh` and it is deliberate: there is one job book per
computer (`luaObject.jobs`), four is a *computer's* ceiling rather than a session's,
and `jobs` lists every background job on the machine whoever started it. Walk away
and they keep running; the next survivor to sit down sees them, and may `fg` them.
On a real Unix a job is a process group the shell owns and `jobs` shows you only
your own. What is *not* deviated from is `kill(2)`'s rule: root, or the account the
job belongs to, and anybody else gets
`kill: <id>: Operation not permitted`. The deviation is about what you can SEE and
pick up, never about stopping somebody else's work -- which matters more since a
pending `shutdown +N` is itself a job of root's. `help`, `man jobs` and Volume 3 all say so in those words — the
description is *"list the background jobs on this machine"* — because a model that
differs has to be readable off the machine itself.

Two costs worth knowing. Double quotes expand, so `"$x"` is the variable and `'$x'`
is two characters. And one word is 1024 bytes (the script engine's ceiling); the
typing line only takes 240 characters, so nothing typed reaches it and the editor is
what fills a file to its own 4096. What `$(...)` catches is that word too and meets
the same 1024 however many lines it caught — whole under it, `word too large` over
it, and never quietly shortened. (It had a hundred-line ceiling as well until a
later change, and that one cut a capture short *in silence*: `x=$(cat 150-lines)` came
back as a hundred of them with nothing said. One rule, and it refuses out loud.)

**Tab completes.** In the first word of a line it offers command names — the files
in `/bin` the account may run, plus the words the shell itself is (the reserved words
and the builtins, which have no file at all). Anywhere else it offers paths: relative
to the cwd, absolute, or under `~`. One match is filled in whole with a trailing
space, or a trailing `/` when it is a directory; several fill in the longest prefix
they share and stop, and a second Tab on the same word lists them in columns the way
`ls` does, with the prompt line drawn again underneath — ksh's answer, and the reason
the round trip carries the names back and not just the replacement.

Completion goes through the machine like everything else: the window sends
`complete { line, cursor }` and the server answers `completed { line, at, start,
replacement, cursor, candidates }`. It is the one client command that changes nothing
— no echo, no history, no job, and no screen pushed to anybody — and the one answer
addressed to a single window, because a half-typed word is on nobody else's glass.
Permissions are the filesystem's, not a filter over the answer: a directory is listed
only if the account may read it, so completion can never name a file `ls` would not
show. Hidden entries appear only once the dot is typed, devices under `/dev` complete
like any other file, and nothing completes at a question, at a password, while a job
holds the prompt, or in the editor — where Tab is still save.

**History.** Every typed line is appended to `~/.sh_history` — the POSIX/ksh name —
owner-only at mode 600, in the account's own home. `history` prints the last 60 with
numbers, `history -c` empties it, `!!` re-runs the last line and `!5` line five (the
expanded line is what is echoed, run and remembered). Up and Down in the window walk
that file, not a list the window kept, so a survivor who comes back tomorrow presses
Up and finds what he typed today. Answers to prompts are never in it.

The file holds 1000 entries and 16 KB, whichever comes first, oldest dropped. Those
16 KB are exempt from the 64 KB disk quota — a shell's memory of itself must not be
the thing that fills the drive — so `df` does not move because somebody typed, while
`ls -l` still tells the truth about the size. The exemption belongs to the **path**
and not to the file: `mv ~/.sh_history loot.txt` and every byte of it counts from
that moment on, `mv` it back and it is exempt again. Two honest deviations from a bigger shell:
the numbers `history` prints are positions in the file as it stands, so they shift
once the oldest drop off; and `!` is only an event when it is the whole line, there
being no quoting rule for it here.

**`~/.profile`** runs at login, after the motd and before the first prompt, if the
file exists and the account may read it. It runs as the shell's own job, which is
the point: a variable it sets is set at the prompt and a `cd` it does is where you
are standing. Its errors read like a script's (`.profile: line 2: ...`) and it
respects every budget. The quirk that comes with that, named in the manual: a
`.profile` with an endless loop in it leaves the account at a busy prompt with
nothing to type at. It is not a locked machine — Escape is the `^C` — and then edit
the file. The BIOS repair never touches homes, so restoring a machine never removes
one.

A script is a text file with commands in it. Write one with `edit`, run it with
`sh`, or give it `x` and run it by its path:

    admin@ksp-04-11:~$ edit lights.sh
    admin@ksp-04-11:~$ sh lights.sh
    admin@ksp-04-11:~$ chmod 755 lights.sh
    admin@ksp-04-11:~$ ./lights.sh

A bare name is still a command in `/bin` and only there, so a script in your home
is never found by typing its name alone.

The language is the one you already know from a 1993 `/bin/sh`, cut to what fits on
a desk machine: `NAME=value` and `$NAME`, `${NAME}`, `$1`..`$9`, `$#`, `$@`, `$?`,
`$$`; single and double quotes and backslash; `#` comments; `;`, `&&`, `||` and a
trailing `&`; `if`/`elif`/`else`/`fi`, `for`/`in`, `while`, `until`, `break`,
`continue`, `exit`, `return`; `test` and `[ ... ]` with `-f -d -e -r -w -x -z -n`,
`=`, `!=`, `-eq -ne -lt -le -gt -ge`, `!`, `-a`, `-o`; `$(command)` one level deep
and `$((1 + 2 * 3))` on whole numbers; and `echo [-n]`, `printf`, `read`, `sleep`
and `shift` as builtins that work even on a machine whose `/bin` has been emptied.

    #!/bin/sh
    for d in light0 light1 light2; do
      echo off > /dev/$d
    done
    read -p "and the office? (y/n) " a
    if [ "$a" = y ]; then echo off > /dev/light3; fi

Every one of those works at the prompt too, being the same shell.

`read` stops the script and asks at the prompt; the next line typed is the answer.
`sleep 5` waits five seconds of real time and costs the machine nothing while it
does. While a script has the prompt there is nothing to type at, and Escape is
`^C`: it kills what is running.

A line ending in `&` runs in the background and gives the prompt straight back:

    admin@ksp-04-11:~$ sh watch.sh &
    [1] 42
    admin@ksp-04-11:~$ ps
      ID S     CPU COMMAND
      42 R      96 sh watch.sh
    admin@ksp-04-11:~$ kill %1

`jobs` lists them by slot, `ps` by number with the state (`R` running, `S`
sleeping, `W` waiting for an answer, `O` held back by the screen) and the steps
spent, `kill` takes either a number or `%slot`, and `wait` holds the prompt until
the background jobs are done. Four jobs to a machine — a *machine*, which is why
`jobs` is the machine's listing and not the shell's.

Two of the four are not scripts at all, and both are there because the thing they
stand for is a *process* on a real Unix. A pending `shutdown +N` is a job named
`shutdown`, waiting, owned by the account that gave the order, and `kill` is how it
is called off (there is no `shutdown -c`: that flag is sysvinit's). A
`cu -l /dev/radio0` sitting at the TNC's `cmd:` prompt is a job too, and it is the
program *holding* the radio link: `kill` it, or Escape at its prompt, and the link
goes with it.

**A runaway script cannot hurt anybody.** Every job gets a slice of each tenth of a
second and no more, so `while true; do echo x; done` makes that one machine slow at
that one thing: the prompt still answers, other screens still draw, and the server
never waits. Output is held to twenty lines a second, so it trickles instead of
flooding — for a typed line as much as for a script's, which is why a long `help`
scrolls out rather than appearing whole. A job that spins for five minutes with no wait in it is taken away with
`killed: cpu limit`. A string that doubles every turn, or a script that runs itself,
meets a ceiling and stops with a line naming it. Jobs are not saved: switching off,
rebooting, picking the computer up or reloading the world leaves it running nothing.

## Pipes, cron and job control

**A pipe joins two commands.** `a | b` runs both at once: what `a` prints is what
`b` reads.

    admin@ksp-04-11:~$ cat /etc/group | grep sudo
    sudo:admin
    admin@ksp-04-11:~$ ls /bin | wc
        55     55    323
    admin@ksp-04-11:~$ cat log | sort | uniq -c

Nine commands read the pipe, and only when they were given **no file**: `cat`,
`grep`, `head`, `tail`, `wc`, `sort [-r] [-n] [-u]`, `uniq [-c]`, and the two
fidelity A added — `cut` and `more`. A file named on the line always wins. There is
no standard input anywhere else on the machine: there is no keyboard behind a
command, so one of those nine with neither a file nor a pipe prints its usage line.

Two more read the pipe and **only** the pipe, because the real tools take no file
operand either: `tr [-d] <set1> [<set2>]` and `tee [-a] <file>...`. Both want
something on their left, and a `tr` typed on its own prints its usage line.

Every stage is a **subshell** — its own variables, its own working directory — so
what a stage changes is gone when the pipeline is over. That is the quirk everybody
meets once: `echo hi | read x` really does read the pipe, in the subshell whose `x`
died with it, so `echo $x` after it prints nothing. Every shell behaves this way;
`x=$(cat notes | head -n 1)` is how you keep it. `$?` after a pipeline is the last
stage's status, and `|` works inside `$(...)`.

A stage has no screen of its own, so `edit` in one is refused as it is in a
background job, and a `read` whose input is not a pipe reads end of file. A command
that has to *ask* something (`sudo`, `passwd`) is answered where an answer can reach
it: `sudo cat notes | grep -i knox` puts the password question up on the glass and
carries on with the answer, while a stage that *reads* a pipe answers
`not a terminal` — there, the answer would come back to a command with nothing on
its input.

**Unless it has finished reading.** `ls -l | more` is the case that needs the
exception and is why there is one: the pager reads its input to the end, says so
(the reader's own `done` flag, which closes the pipe behind it), and only then puts
its first `--More--` up. A continuation has no pipe behind it, and a stage that has
closed its input has no pipe left to miss — so the refusal above asks whether the
stage's pipe is still open, and not merely whether it had one.

A pipe holds **a hundred lines and four kilobytes**, and what happens when it is
full is back-pressure and not an error: the writer simply does not run again until
the reader has drained it, exactly as a job that has filled the screen does not.
A reader that stops reading kills the writer with **141** — `SIGPIPE`, as `sh`
reports it — so the flood in front of a `head` ends at once:

    admin@ksp-04-11:~$ while true; do echo y; done | head -n 1
    y

`sort -u` drops the repeats on its way out, which is the `uniq` after it saved, and
`grep -c` and `wc -l` answer a pipe with one number rather than with its lines.

`sort`, `tail` and `more` cannot answer before the end of their input, so they keep
what they have read; that too is bounded by a pipe's own hundred lines and four
kilobytes, and past it they stop with `input too large` and close the pipe. For
`more` the ceiling is paid twice over: what it has not shown yet is carried in the
token the console holds while the question is up. `wc` and
`uniq` keep nothing and will count a pipe that never ends for as long as it runs. A
pipeline may be eight commands long.

**cron** is the machine doing something with nobody standing at it. Each account has
a crontab — five fields and a command — and once a game minute the machine runs the
lines that are due.

    admin@ksp-04-11:~$ crontab -e
    0 4 * * * echo off > /dev/light0
    */15 * * * * cat /dev/door0 >> log
    @reboot echo the machine is up

It is Vixie's cron: `*`, lists, ranges and steps (`*/15`, `8-17`), minutes 0-59,
hours 0-23, days 1-31, months 1-12, weekdays 0-6 from Sunday (and 7), the
shorthands `@reboot @hourly @daily @midnight @weekly @monthly @yearly`, and his rule
for the two day fields: with both of them restricted, **either** matching is enough.
Names for months and weekdays are not accepted — write the numbers. 32 lines to a
crontab.

The file is `/var/spool/cron/<user>`, root's and `600`, in a directory that is
root's and `700`: `crontab -l`, `crontab -e` and `crontab -r` are the only way in,
which is what keeps one account from writing a line that runs as another. A file
that will not parse is refused whole when you save it, where Vixie refuses it and in
his words:

    Cannot save: "/var/spool/cron/admin":1: bad minute

**What cron will not do.** It does not catch up: a machine that was switched off at
four in the morning, or whose part of the world nobody was near, does not run four
o'clock's line when it comes back. A minute cron slept through is a minute that is
gone — real cron does not go back for one either, which is what `anacron` was
written for, and there is no `anacron` here. And it does not get more than its
share: a machine runs four jobs at once and no more, cron's included, so a line that
comes due with the machine full is **skipped** and the log says so in cron's own
words, `(CRON) error (can't fork)`.

**A cron line has no terminal**, and the machine holds it to that. Nothing it can
write reaches the glass a survivor might be standing at: `rlogin` is refused with
`rlogin: not a terminal`, and so are `su`, `passwd` and `sudo` — a password
question is only ever put up for the job holding the prompt, so from cron it would
wait for an answer that could never come, and four of those are every job slot the
machine has. `clear` runs and clears nothing, because the glass is not a cron
line's to wipe. `edit` has always answered `edit: not a terminal`, and an `exit`
ends the line and never the session. `rsh` is the one that does work without a
terminal, exactly as real `rsh` does: the cron job waits for it and what the far
command printed comes back in the mail, with everything else that line printed.

What a cron job **prints** never reaches the screen — there is nobody at the screen
at four in the morning. It is mailed to the account, with the `From` and `Subject`
lines a mailbox has always carried, and `mail` shows it and empties it:

    admin@ksp-04-11:~$ mail
    From cron  Thu Jul  8 04:00:00 1993
    Subject: Cron <admin@ksp-04-11> echo tick
    tick

`/var/log/cron` (root's, `640`) says what ran, and what could not. Both it and the
mailboxes are bounded by lines and by bytes and are exempt from the 64 KB by their
path, the same way `~/.sh_history` is — a machine must not fill its own disk with
what it said about itself while nobody was looking.

**Waiting on a device** is a loop, not a command. Unix has never had a "wait until
this happens", and this machine does not invent one:

    while [ "$(cat /dev/door0)" = closed ]; do
        sleep 5
    done
    echo on > /dev/light0

A sleeping job is off the processor entirely — it is not spending its five minutes
and it can wait for days — so that asks the machine for one turn every five seconds
and nothing in between. The same loop without the `sleep` is the one thing not to
write: it takes every step the machine will give it and gets nothing done any
sooner. `sleep` takes whole seconds, as it does everywhere.

**`fg`** brings a background job back to the front:

    admin@ksp-04-11:~$ sh watch.sh &
    [1] 43
    admin@ksp-04-11:~$ fg %1
    sh watch.sh &

`fg %1` names the slot `jobs` prints, `fg 43` the id `ps` prints, and `fg` on its
own is the job started last. What it changes is where the output goes and who
Escape belongs to. There is no `bg` and nothing to use it for: nothing on this
machine suspends a job, so the only direction one can be moved in is forwards. A
cron job is not one of these — nobody at a keyboard asked for it, `jobs` does not
list it and `fg` will not have it, though `ps` shows it.

## The shell that looks a name up, and the links it walks

Three pieces of plumbing came with `PATH`, links and `ls`, and each is in exactly
one place.

**What the shell knows.** A command is handed one thing more than its arguments: a
small table of what the *shell* knows about the line — `path`, the `PATH` to look a
bare name up on, and `tty`, whether what it writes is going to a screen at all.
Neither is a fact about the filesystem, so neither is looked up by whoever needs it;
`CeroSecOSVM.runSimple` builds it, `runArgs` passes it down, and `sudo` and a
continuation forward the one they were given. `tty` is false for the three doors
output already goes through other than the glass — a `$( )` capture, a pipe, `cron`'s
mailbox — plus a redirect, and the **last** stage of a pipeline inherits the answer
from whatever is running the pipeline (its pipe is drained onto that). `ls` is the
one command that reads it today, and it reads it exactly as every `ls` reads
`isatty`.

**What the walk costs.** `CeroSecOS.lookupPath` walks `PATH` left to right and
answers where it found the name, why it did not, **how many directories it looked
in**, and whether what answered was a link. The count is charged in steps by
`runSimple`, one per directory past the first, because a long `PATH` makes every
command on the machine dearer and a budget that could not see that would not be a
budget: measured, a kilobyte of `PATH` was a command twenty times dearer than
`STEP_COST_COMMAND` believes it is. Two ceilings follow — `MAX_PATH_DIRS` (8),
refused at the assignment with `too many PATH entries`, and the same number as a
belt on the walk itself, so a value off a save file nobody can explain is slow for
nobody. `tests/hostile_test.lua` drives the worst legal `PATH` and a forged
340-field one.

**Where a link is followed.** `CeroSecOS.getNode` and nowhere else, which is why no
command had to learn about links: a link in the middle of a path is the directory it
names, a link at the end of one is the file it names, and the absolute path that
comes back is still the **logical** one, so `cd` through a link prints where you
typed. A fourth argument leaves the last component alone — the difference between
`stat` and `lstat` — and the four commands that act on the link ask for it.
`MAX_LINK_HOPS` (8) is counted per resolution and `MAX_DEPTH` bounds what is left to
walk once a target is hung on the front, so no path through there fails to end.
`CeroSecOS.systemNode`, the kernel's own read, does **not** follow one: a link where
`/etc/passwd` should be reads as no passwd at all, which the boot check calls a
machine with no operating system and the BIOS repairs.


## Underneath: the step machine, the job, and the scheduler

The language lives in two files and neither of them knows there is a game.

`CeroSecOSScript.lua` is the parser. `CeroSecOS.parseScript(text)` returns a
*program*: nested plain tables of strings, numbers and booleans, with no function
anywhere in it. Parsing happens **once**, before a job exists, so a script with a
missing `done` never costs a tick — and what comes out is inert. There is no `load`,
no `loadstring`, no `setfenv` and no metatable; the arithmetic in `$(( ))` is read
digit by digit by a recursive-descent reader in the VM. Nothing a player types is
ever evaluated as Lua, and `tests/kahlua-check.sh` greps for it.

`CeroSecOSVM.lua` is the stepper:

    CeroSecOS.jobStep(state, job, env, budget) -> status, stepsSpent

`status` is `"running"`, `"waiting"`, `"sleeping"`, `"done"`, `"killed"` or
`"error"`. It runs up to `budget` steps and returns; it never loops to the end and
never waits. A **job** is a plain serializable table — a program, a stack of frames,
its variables, its pending output, a session of its own — and holds no function at
all, which is what makes it inspectable by `ps` and impossible to hide anything
executable inside:

    { id = 42, n = 1, name = "backup.sh", cmd = "sh backup.sh", bg = false,
      prog = <program>, frames = { {k="block", prog=..., i=3}, ... },
      vars = { x = "1" }, nvars = 1, args = { "one", "two" },
      caps = { }, out = { "line" }, partial = "", status = 0, steps = 412,
      state = "running", blocked = nil, depth = 1, line = 7, debt = 0,
      cpuSince = 1723..., wakeMs = nil, ask = nil, cont = nil,
      session = { user = "admin", cwd = "/home/admin", ... } }

A step is a unit of **cost**, not of syntax: one for anything the shell answers
itself (an assignment, an `echo`, a `test`, a loop iteration boundary), and
`CeroSecOS.STEP_COST_COMMAND` (32) for a command that goes out to `/bin` — measured
between 20 and 500 microseconds a call against about 6 for a builtin, so a flat step
would have been a budget eighty times out on a loop of `ls`. The steps of what
`$(...)` runs are charged to the job that asked. A pass may overspend by at most one
command, since a command's price is only known once it has been paid; the overspend
is carried as a `debt` and taken off the next pass, so the average is exactly the
budget.

Every wait is a continuation. `read` and a command's own question (`sudo`,
`passwd`) both leave the job `"waiting"` — the console puts the question up with an
ordinary prompt token `{ cmd = "job", id = 42 }` and the answer comes back through
`CeroSecOS.jobInput`. `sleep` leaves it `"sleeping"` against `env.nowMs` and costs
nothing until it comes round. A question with a **redirect** behind it keeps it:
`job.contRedirect` is what `>` named, opened when the question went up
(`CeroSecOS.openRedirect`) and handed to `CeroSecOS.continue` with the answer, so the
write happens beside every other command's — on the lines as the command made them,
before the screen's own sixty columns are applied to anything.

`SCeroSecJobs.lua` is the scheduler and the only half that knows there is a server.
Ten passes a second on `Events.OnTick` gated by `getTimestampMs()` — vanilla's own
way of getting under a minute (`forageServer.lua:502`) — with
`CeroSec.STEP_BUDGET_PER_TICK` (200) steps to hand out across every machine that has
a job, no machine taking more than `CeroSec.STEP_BUDGET_PER_MACHINE` (100), and
machines served round-robin from one further along each pass. A starved job runs
slower; nothing is ever refused a turn. Output drains at `CeroSec.JOB_OUT_PER_SEC`
(20) lines a second **per machine**, and a job whose queue is full simply does not
run until the screen has taken what it wrote. A job that holds the processor with no
wait in it for `CeroSec.JOB_CPU_LIMIT_S` (300 s) is killed with `killed: cpu limit`
— a constant with a comment, not a sandbox option, because a server owner who wants
a different number should be given a setting rather than asked to edit a file.

`luaObject.jobs` is **runtime state and is deliberately not in the saved keys**: a
reload forgets jobs, `CeroSec.repairConsole` drops the console's note of a
foreground one, and a machine that comes back from a save comes back at its prompt.
Reboot, shutdown, a room that lost its power and a computer picked up all kill
everything.

## Pipelines: a shell per stage

A pipeline is one job with several shells inside it. `pushNode` turns a `pipe` node
into a frame holding an array of **stages** — each one a job table of its own, built
by `newJob` with a copy of the pipeline's variables and session, which is exactly
what a subshell is — and an array of buffers, one per stage:

    { k = "pipe", stages = { <job>, <job> },
      pipes = { { lines = {}, bytes = 0, eof = false, closed = false }, ... } }

`pipeStep` is one turn of it. It drains the last stage's buffer into the job that
owns the pipeline (so a pipeline inside `$(...)` is caught by the capture like
anything else), marks `eof` behind a stage that has finished and `closed` in front of
one, and then steps the **rightmost stage that can run**. A stage that cannot is one
waiting for a line that is not there (`blocked = "input"`) or one whose buffer is
full — and reading right to left is where the back-pressure comes from: the reader
runs until it has taken everything there is, and only then does the writer get a
turn. A stage whose reader has gone is killed with `CeroSecOS.SIGPIPE_STATUS` (141).
When every stage is over the job's status becomes the **last** stage's.

A stage may **ask**. A command that has to put a question up (`sudo`, `passwd`) in a
stage with nothing on its input is answered: the question travels out of the stage
onto the pipeline's own job (`f.asking` remembers which stage asked), the console
puts it up with the pipeline's ordinary token, and `CeroSecOS.jobInput` hands the
answer back **down to the stage**, which is where the continuation, the redirect and
the pipe all belong. A stage that *reads* a pipe is still refused it with
`not a terminal`: a continuation carries a command's own arguments and no pipe behind
them, so the answer would run the command with nothing on its input.

`outLine` is the one door output goes through, and it now has three: a capture, a
pipe, or the screen. `errLine` is the other half — a stage's *refusals* go to the
screen and not down the pipe, which is the rule `>` already had ("output goes to the
file only when the command succeeded").

A command that reads a pipe is handed a reader as a fifth argument
(`fn(state, session, args, env, stdin)`), and is **run again** until its input is
exhausted: `stdin.want` says it is reading the pipe, `stdin.carry` is a scratch table
that survives between calls (what `sort` has sorted so far, what `wc` has counted),
and `stdin.done` closes the pipe behind it, which is how `head -n 1` ends a flood.
`job.again` is what keeps its frame on the stack for the next turn.

## cron: a pass on the minute hand

`CeroSecOSCron.lua` knows what a crontab *means* and nothing about the game:
`parseCronLine`, `parseCrontab`, `checkCrontab` (the refusal crontab(1) prints),
`cronDue(entry, parts)` against `CeroSecOS.dateParts`, and the two bounded writes —
`cronLog` and `mailAppend`. `commands.crontab` and `commands.mail` live there too.

`CeroSecJobs.cronPass(system, luaObject, now)` is the daemon, and there is no process
for it: `SCeroSecSystem:checkCron()` walks every machine that is **on** on
`Events.EveryOneMinute` — the same sweep the power check uses, because the two ask the
same question of the same list. On, and not "in view": a machine whose chunk the
streamer has taken away keeps its power, its jobs and its crontab, and cron goes on
firing for it, because none of the three is a thing in the world (see
[ARCHITECTURE.md](ARCHITECTURE.md#the-chunk-that-goes-away) — the pass used to stop for
such a machine, but only because the power sweep had switched it off first). A line
that reaches for `/dev` out there is told `no such device` like any other line about a
device out of reach. `luaObject.cron.minute` is the minute it last looked
at and is **runtime state**, dropped by `turnOff` and not by `killAll`: a machine
that has only just come into view runs nothing for the minute it arrived in, and a
minute nobody swept is a minute that is gone. `CeroSecJobs.atBoot` is `@reboot`,
called from `SCeroSecObject:turnOn`.

A due line becomes an ordinary background job with `job.mailTo` set, which is what
tells `enrol` this is not the shell's: no slot, nothing on the screen, nothing said
when it ends, and `jobs` does not list it (`ps` does). Its output is delivered by
`runMachine` to `/var/mail/<user>` instead of the console, with the `From` and
`Subject` header written once per job.

The measured cost of a pass, headless under `lua5.1`, is printed by
`tests/hostile_test.lua` on every run: about 0.6 ms for one machine spinning on
arithmetic and 1.2 ms for six, against a 60-frames-a-second budget of 16.7. The
game's Lua is not this one — Kahlua is an interpreter written in Java and is
expected to be several times slower — which is why the county's budget is a fifth of
what the measurement alone would allow.
