# CeroSec: Scripting

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
nothing runs. A refusal the shell itself makes carries no line number, a typed line
is line one of nothing, but past the first level it is inside a file again
(`sh backup.sh`) and that file's name and line come back.

Variables and `$?` belong to the machine: `x=5` on one line and `echo $x` on the
next are the same environment, and walking away and coming back finds it. Logging
out takes them, as it takes the rest of the session. `cd` at the prompt moves the
console; `cd` inside a script moves the script.

`ps` shows the shell you are typing into, the way every Unix `ps` does; `jobs` does
not, because a shell is not a background job. That is also why the first background
job is `[1] 43` and not `[1] 42`, the shell itself took 42, and the four-job
ceiling is still four *scripts*.

**The jobs belong to the MACHINE, not to the shell.** This is the one place the
model differs from a real `sh` and it is deliberate: there is one job book per
computer (`luaObject.jobs`), four is a *computer's* ceiling rather than a session's,
and `jobs` lists every background job on the machine whoever started it. Walk away
and they keep running; the next survivor to sit down sees them, and may `fg` them.
Leave the *game* and they keep running too, the machine was never switched off, so
the book goes into the save with it.
On a real Unix a job is a process group the shell owns and `jobs` shows you only
your own. What is *not* deviated from is `kill(2)`'s rule: root, or the account the
job belongs to, and anybody else gets
`kill: <id>: Operation not permitted`. The deviation is about what you can SEE and
pick up, never about stopping somebody else's work -- which matters more since a
pending `shutdown +N` is itself a job of root's. `help`, `man jobs` and Volume 3 all say so in those words, the
description is *"list the background jobs on this machine"*, because a model that
differs has to be readable off the machine itself.

Two costs worth knowing. Double quotes expand, so `"$x"` is the variable and `'$x'`
is two characters. And one word is 1024 bytes (the script engine's ceiling); the
typing line only takes 240 characters, so nothing typed reaches it and the editor is
what fills a file to its own 4096. What `$(...)` catches is that word too and meets
the same 1024 however many lines it caught, whole under it, `word too large` over
it, and never quietly shortened. (It had a hundred-line ceiling as well until a
later change, and that one cut a capture short *in silence*: `x=$(cat 150-lines)` came
back as a hundred of them with nothing said. One rule, and it refuses out loud.)
That refusal is now the **whole** of what reaches the glass. The ceiling is met at the
write, it has to be, because a capture whose program never ends never reaches the
substitution to be measured there, so the job dies in the middle of a command's
output, and the lines that command had already handed over used to arrive behind the
refusal with nothing catching them: a file's contents spilled across the middle of the
line being built. A job that has ended writes nowhere, which is one test in `outLine`
and what a dead process does.

**Shell functions.** `name() { list; }`. POSIX.2's shape, and `name ()` with a
blank is read too. Positional parameters inside the body are the **call's** (`$1`,
`$#`, `$@`), and the caller's come back when it returns; `$0` stays the script's, as
POSIX says. `return [n]` leaves the function and hands `n` up as `$?`; `exit` inside
one ends the **shell or the script**, which is the whole difference between the two
words. **There is no `local` in a 1993 sh**, a variable a function sets is the
shell's, and the manual says so out loud. A function is found *before* `/bin` and
before the builtins that are files there, and *after* the words the shell itself is,
so `ls() { … }` shadows `/bin/ls` and `cd() { … }` shadows nothing. `type name`
answers `name is a function`.

A function runs **in the shell that holds it**: no job, no new variables, no new
depth, one frame a call, so what bounds a recursion is `MAX_FRAMES` and a
`f() { f; }` reaches it and stops with `too deeply nested`. The call costs one step
and the body is charged line by line, like any other line. A redirect on the call is
the function's, the way it is a script's (`greet > log`).

**Where a function lives.** `job.funcs` is name → **the source text of the
definition**, and the body is parsed out of it once per job and cached in `job.fprog`.
The text and not the program, because the console *keeps* a function between one line
and the next and the console is written to the save file: a body is nested tables, and
a nested table handed back out of modData and then run is the one thing this machine
will not do. `CeroSec.repairConsole` bounds `console.shfuncs` the way it bounds a
variable's value, a real name, printable text under `MAX_FUNC_BYTES`, no more than
`MAX_FUNCS` of them, plus one check of its own: the text has to declare the very name
it is filed under, or a `greet` whose text defined `rm` would answer to the wrong word.

It travels the way `job.vars` travels: **by reference** for the prompt, a **copy** for
a subshell (a stage, an `&`, a `$( )`, a fork inherits its parent's functions and what
it defines afterwards is its own), and **none** for a script, which is a new `sh`.
`. file` is the one that brings them in, being the shell reading a file into itself,
which is the whole reason the dot exists. A logout takes them, as it takes the
variables.

The braces are **not** reserved words here. `{` and `}` are POSIX reserved words, and
making them so would mean a brace group (`{ list; }` as a command) this machine has not
got, plus a refusal for every `echo {` already written. What is needed is that `}`
*stops the body*, and that falls out of the stops table `parseProgram` already takes.

**`case` and the bracket.** `)` is **not** an operator on this machine, there is no
subshell grouping here, and making one of it now would turn every `echo (hi)` a
survivor has already written into a syntax error, so the `)` that closes a pattern is
taken off the *end* of the pattern word instead (`takeClose`). That is not a shortcut:
only an **unquoted** `)` closes a pattern on a real sh, and the test is whether the
last piece of the word was bare literal text, so `"a)"` is a pattern with a bracket in
it and `[)]` is a set holding one. `;;` **is** one operator now (it was two separators,
so `echo a;;` quietly ran as `echo a`), and `parseProgram` stops at it the way it stops
at a reserved word. POSIX's optional `(` in front of a pattern is taken off the front
the same way. `case` and `esac` joined the reserved words, so `help`, `type` and Tab
know them.

The patterns are expanded and compared **one at a time, in order, and no further than
the match**. POSIX's rule, and the reason a `$( )` in a clause below the one that
matched never runs. Each comparison costs **one step**: a case of forty alternatives
really does forty expansions and forty string walks, the same thing written as forty
`[ "$x" = p ]` would cost forty steps, and with the comparison counted as free work a
loop over a forty-pattern case cost 7.6 ms a pass against a ceiling of 4
(`tests/hostile_test.lua`, "case of forty"). The subject is expanded *without* field
splitting, which is POSIX's rule for it: a value with a blank in it is one word, or a
name with a space could not be matched at all. Nothing matched is a status of nought,
and a clause that ran hands its own status up.

**Tab completes.** In the first word of a line it offers command names, every
executable the account may run in the directories `PATH` names, walked left to right
and bounded by the same `MAX_PATH_DIRS` the lookup is bounded by, plus the words the
shell itself is (the reserved words and the builtins, which have no file at all). It
is the shell's own `PATH` that is walked and not a fixed `/bin`, because a completion
that offered a name the lookup would not find would be a Tab that lies: a `hello` in
`~/bin` completes once `PATH=$PATH:$HOME/bin` has been typed, and not before. A link
is judged on what it points at, where `x` lives. Anywhere else it offers paths: relative
to the cwd, absolute, or under `~`. One match is filled in whole with a trailing
space, or a trailing `/` when it is a directory; several fill in the longest prefix
they share and stop, and a second Tab on the same word lists them in columns the way
`ls` does, with the prompt line drawn again underneath, ksh's answer, and the reason
the round trip carries the names back and not just the replacement.

Completion goes through the machine like everything else: the window sends
`complete { line, cursor }` and the server answers `completed { line, at, start,
replacement, cursor, candidates }`. It is the one client command that changes nothing,
no echo, no history, no job, and no screen pushed to anybody, and the one answer
addressed to a single window, because a half-typed word is on nobody else's glass.
Permissions are the filesystem's, not a filter over the answer: a directory is listed
only if the account may read it, so completion can never name a file `ls` would not
show. Hidden entries appear only once the dot is typed, devices under `/dev` complete
like any other file, and nothing completes at a question, at a password, while a job
holds the prompt, or in the editor, where Tab is still save.

**History.** Every typed line is appended to `~/.sh_history`, the POSIX/ksh name,
owner-only at mode 600, in the account's own home. `history` prints the last 60 with
numbers, `history -c` empties it, `!!` re-runs the last line and `!5` line five (the
expanded line is what is echoed, run and remembered). Up and Down in the window walk
that file, not a list the window kept, so a survivor who comes back tomorrow presses
Up and finds what he typed today. Answers to prompts are never in it.

The file holds 1000 entries and 16 KB, whichever comes first, oldest dropped. Those
16 KB are exempt from the 64 KB disk quota, a shell's memory of itself must not be
the thing that fills the drive, so `df` does not move because somebody typed, while
`ls -l` still tells the truth about the size. The exemption belongs to the **path**
and not to the file: `mv ~/.sh_history loot.txt` and every byte of it counts from
that moment on, `mv` it back and it is exempt again. Two honest deviations from a bigger shell:
the numbers `history` prints are positions in the file as it stands, so they shift
once the oldest drop off; and `!` is only an event when it is the whole line, there
being no quoting rule for it here.

**The environment, and what a script can see.** A shell holds variables; the
**environment** is the subset of them that has been exported, and that is what a
program it runs is handed, a copy of it, in a table of its own, so an assignment in
a script never comes back. `export NAME[=value]...` marks a name (POSIX.2's
`export`), `env` prints the set, and `. <file>`, the dot, sh's since the seventh
edition, reads a file in the shell standing there instead of running it as a
program, which is the one way a file's assignments land in the caller. `export` and
`.` are words the shell **is**: nothing in `/bin` could reach a shell's variables.
A login exports `PATH` and `HOME`, which is why a script has always been able to
find a command, and `cron` hands a line the same two and nothing else.

Two tables carry it: `job.vars` and `job.exported`, both by reference from the
console (`console.shvars`, `console.shexport`) so `export` holds from one line to
the next, and both copied for a subshell, a stage, an `&`. `job.exported` may be
**nil**, and nil is not the empty set: it means a caller that said nothing about the
environment, which reads as *all of them*. That is what a console saved before this
build means, because until then a foreground script ran on the prompt's own table and
saw everything on it; the next login writes the real set. `CeroSecOS.jobRun` is where
the swap happens, and the frame it pushes carries the caller's tables back, the dot
is the same call with `inPlace`, which keeps the caller's variables, arguments and
all, and is still a level deeper so a file that dots itself meets
`SCRIPT_DEPTH_MAX`.

**`~/.profile`** runs at login, after the motd and before the first prompt, if the
file exists and the account may read it. It runs as the shell's own job, which is
the point: a variable it sets is set at the prompt and a `cd` it does is where you
are standing (it is read the way the dot reads a file, not run the way `sh` runs
one). Its errors read like a script's (`.profile: line 2: ...`) and it
respects every budget. The quirk that comes with that, named in the manual: a
`.profile` with an endless loop in it leaves the account at a busy prompt with
nothing to type at. It is not a locked machine. Escape is the `^C`, and then edit
the file. The BIOS repair never touches homes, so restoring a machine never removes
one.

A script is a text file with commands in it. Write one with `edit`, run it with
`sh`, or give it `x` and run it by its path:

    admin@ksp-04-11:~$ edit lights.sh
    admin@ksp-04-11:~$ sh lights.sh
    admin@ksp-04-11:~$ chmod 755 lights.sh
    admin@ksp-04-11:~$ ./lights.sh

A bare name is looked for on `PATH`, which by default is `/bin` and then
`/usr/local/bin` (`CeroSecOS.DEFAULT_PATH`) -- the machine's own commands and then
what root installed for everybody -- so a script in your home is never found by
typing its name alone. `/bin` is first, so nothing installed can shadow a shipped
command.

The language is the one you already know from a 1993 `/bin/sh`, cut to what fits on
a desk machine: `NAME=value` and `$NAME`, `${NAME}`, `$1`..`$9`, `$#`, `$@`, `$?`,
`$$`; single and double quotes and backslash; `#` comments; `;`, `&&`, `||` and a
trailing `&`; `if`/`elif`/`else`/`fi`, `for`/`in`, `while`, `until`, `break`,
`continue`, `exit`, `return`; `name() { list; }`; `case word in pattern) … ;; esac` with `|` between
alternatives, the shell's own globs (`*`, `?`, `[…]`) in the patterns and `*)` as the
default; `test` and `[ ... ]` with `-f -d -e -r -w -x -z -n`,
`=`, `!=`, `-eq -ne -lt -le -gt -ge`, `!`, `-a`, `-o`; `$(command)` one level deep
and `` `command` `` -- the ORIGINAL sh(1) form, before ksh and POSIX.2 (1992)
added `$( )`, one level deep the same way, escaped or not:
``echo \`echo hi\` `` is `bad substitution` just like `$(echo $(echo hi))`,
and both spellings parse into the same substitution so what follows treats
them alike; and
`$((1 + 2 * 3))` on whole numbers, with `$1`, `$#`, `$?`, `$$` and `${NAME}`
read inside the double brackets as POSIX.2 reads them, the expansion first and the
sum afterwards, so `$((5 % $1))` is a sum on the first argument. **The two kinds
of bracket nest**, in POSIX.2's own order: every command substitution is run first
and the sum is read on what came back, so `stop=$(($(date +%s) + 300))` is a
deadline and `echo $(echo $((2 + 3)))` is a catch round a sum. What is one level
deep is *command substitutions*, and a `$(( ))` between two of them does not buy a
second one, `$(( $(echo $(date)) ))` is still `bad substitution`. A catch inside a
sum meets the **word's** ceiling, at the write, exactly as one inside a word does;
what comes back and is not a number is nought, the rule an empty variable already
follows. A `$(( ))` inside a `$(( ))` is not read (write the brackets plainly
instead); and `echo [-n]`,
`printf`, `read`, `sleep`
and `shift` as builtins that work even on a machine whose `/bin` has been emptied.

    #!/bin/sh
    for d in light0 light1 light2; do
      echo off > /dev/$d
    done
    read -p "and the office? (y/n) " a
    if [ "$a" = y ]; then echo off > /dev/light3; fi

Every one of those works at the prompt too, being the same shell.

A loop over a whole kind of device has a command of its own:
`dev window close` is every window the machine can reach, one answer line each in
`dev window`'s order, and the line fails if any one of them refused (the
[`dev` page](PLAYERS.md) has the grammar). The loop is still what a script wants
when it needs the answers device by device, because a command that half failed
keeps its output on the screen and out of a redirect, the way every other command
on this machine does:

    for d in $(ls /dev | grep ^window); do
      echo close > /dev/$d
    done

`ls` prints one name a line when there is no screen behind it, inside a `$( )`
there is not, which is what makes that catch and that grep work. Its own status
is the LAST iteration's, so a refusal in the middle of the set is a loop that ends
in nought; `dev window close` is the one that reports it.

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
the background jobs are done. Four jobs to a machine, a *machine*, which is why
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
flooding, for a typed line as much as for a script's, which is why a long `help`
scrolls out rather than appearing whole. A job that spins for five minutes with no wait in it is taken away with
`killed: cpu limit`. A string that doubles every turn, or a script that runs itself,
meets a ceiling and stops with a line naming it. Switching off, rebooting or picking
the computer up leaves it running nothing, but **leaving the game and coming back
does not**: a computer the world saved was never switched off, so what you left
running with `&` is still running when you sit down again.

## Pipes, cron and job control

**A pipe joins two commands.** `a | b` runs both at once: what `a` prints is what
`b` reads.

    admin@ksp-04-11:~$ cat /etc/group | grep sudo
    sudo:admin
    admin@ksp-04-11:~$ ls /bin | wc
        55     55    323
    admin@ksp-04-11:~$ cat log | sort | uniq -c

**grep reads a pattern, and the walk is charged.** `grep` takes POSIX.2's basic
regular expression (`^ $ . * [...] [^...]` and the backslash; not `\( \)` and not
`\{m,n\}`), see [PLAYERS.md](PLAYERS.md) for the grammar. The matcher is an NFA
simulation and not a backtracker: a backtracking matcher on `a*a*a*a*b` against a
line of a's is exponential and the pattern is a string a *player* typed, so the walk
carries a set of positions through the line in one pass and costs the length of the
line times the number of pieces whatever the pattern says. Two ceilings go with that:
32 pieces (`MAX_BRE_ITEMS`), and a pattern whose first piece cannot be skipped starts
the walk only at the characters that piece could match.

It is also the first command whose real cost is far from `STEP_COST_COMMAND`: a
literal pattern is one C call whatever the file, a pattern with a piece in it was
measured at five milliseconds over the widest line a file can hold and twenty-two for
the dearest one the ceiling allows, against a per-pass wall budget of four. So grep
reports what its walk cost on the shell's little table (`sh.cost`) and `runSimple`
adds it to the job's **debt**, not to the steps spent on that pass, because the
pass's invariant is that it may overspend by at most one command and a command
reporting five hundred steps would break it. The debt is exactly the machinery for
this: the work is paid for on the passes after it, and the average is the budget
again. `CeroSecOS.BRE_STEPS_PER` carries the arithmetic and the measurements.

Nine commands read the pipe, and only when they were given **no file**: `cat`,
`grep`, `head`, `tail`, `wc`, `sort [-r] [-n] [-u]`, `uniq [-c]`, and the two
fidelity A added, `cut` and `more`. A file named on the line always wins. There is
no standard input anywhere else on the machine: there is no keyboard behind a
command, so one of those nine with neither a file nor a pipe prints its usage line.

Two more read the pipe and **only** the pipe, because the real tools take no file
operand either: `tr [-d] <set1> [<set2>]` and `tee [-a] <file>...`. Both want
something on their left, and a `tr` typed on its own prints its usage line.

`wall [file]` joins the nine: a file named on the line, or the pipe. The real one
reads its *terminal* when given neither, and this machine has no keyboard behind a
command, so `wall` alone prints its usage line, which is the same answer `cat` gives.
What it hands back is an **order** and not output, because only the machine can put a
line on a screen that is not this job's: `CeroSecJobs.wall` walks the machine's own
console and every `pty.console`, and `shutdown`'s minute-out warning has always gone
out through that same door.

**An order is a program, and a program is not a full stop.** Every control name a
command can hand back is in `CeroSecOS.KNOWN_ORDERS`, against one of three words.
`"vm"` is one the engine deals with itself and the job goes on, a wait, a question,
a script one level deeper, a link on the radio. `"machine"` is one only the server
can carry out with the job going **on past it**, the way a caller goes on past any
other program: it is queued on the job (`job.orders`), the job does not step again
until the pass has taken it (`CeroSecJobs.runMachine`), and the next statement runs
after the machine has done the deed, `wall` and `clear` are the two.
`"exit"` ends the whole job, because there is nothing left for it to do: the machine
is going dark (`shutdown`, `reboot`, a pending order), the account is being logged
out (`exit`), or a buffer or a session has taken the glass (`edit`, `fg`, `rlogin`,
`cu`). A name that is in none of the three is **refused out loud**:
`sh: <name>: unknown order`, and the job runs on. That refusal is there because
`wall` arrived without a case of its own and fell to the `"exit"` end of
`applyControl`: `echo before; wall f; echo after` printed `before` and stopped, a
crontab line died at its own broadcast, and every bench stayed green because the
only shape they wrote was `echo hi | wall`, where the order is the job's last word
anyway. `tests/os_test.lua` walks the table in both directions.

Every stage is a **subshell**, its own variables, its own working directory, so
what a stage changes is gone when the pipeline is over. That is the quirk everybody
meets once: `echo hi | read x` really does read the pipe, in the subshell whose `x`
died with it, so `echo $x` after it prints nothing. Every shell behaves this way;
`x=$(cat notes | head -n 1)` is how you keep it. `$?` after a pipeline is the last
stage's status, and `|` works inside `$(...)`.

**And so is a `$( )`.** POSIX.2 runs a command substitution in a subshell
environment, so what it sets dies with it: `x=1; y=$(x=2; echo $x); echo $x` prints
`1`, and an `export` inside one marks the subshell's environment and not the
shell's. A capture is a *frame on the job that asked for it* and not a job of its
own, that is what makes its steps the asker's and its output the asker's word, so
the copy is taken at the frame and put back when the frame pops (`expandStep`,
`popFrame`), which is the same pair `newStage` gives a pipeline's stage written the
other way round. The working directory goes with them, so `echo $(cd /etc; pwd)`
prints `/etc` and leaves the prompt where it was standing. What a capture still
shares is the `su` **stack**: that one belongs to the console, and popping it is the
console's.

A stage has no screen of its own, so `edit` in one is refused as it is in a
background job, and a `read` whose input is not a pipe reads end of file. A command
that has to *ask* something (`sudo`, `passwd`) is answered where an answer can reach
it: `sudo cat notes | grep -i knox` puts the password question up on the glass and
carries on with the answer, while a stage that *reads* a pipe answers
`not a terminal`, there, the answer would come back to a command with nothing on
its input.

**Unless it has finished reading.** `ls -l | more` is the case that needs the
exception and is why there is one: the pager reads its input to the end, says so
(the reader's own `done` flag, which closes the pipe behind it), and only then puts
its first `--More--` up. A continuation has no pipe behind it, and a stage that has
closed its input has no pipe left to miss, so the refusal above asks whether the
stage's pipe is still open, and not merely whether it had one.

A pipe holds **a hundred lines and four kilobytes**, and what happens when it is
full is back-pressure and not an error: the writer simply does not run again until
the reader has drained it, exactly as a job that has filled the screen does not.
A reader that stops reading kills the writer with **141**, `SIGPIPE`, as `sh`
reports it, so the flood in front of a `head` ends at once:

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
a crontab, five fields and a command, and once a game minute the machine runs the
lines that are due.

    admin@ksp-04-11:~$ crontab -e
    0 4 * * * echo off > /dev/light0
    */15 * * * * cat /dev/door0 >> log
    @reboot echo the machine is up

It is Vixie's cron: `*`, lists, ranges and steps (`*/15`, `8-17`), minutes 0-59,
hours 0-23, days 1-31, months 1-12, weekdays 0-6 from Sunday (and 7), the
shorthands `@reboot @hourly @daily @midnight @weekly @monthly @yearly`, and his rule
for the two day fields: with both of them restricted, **either** matching is enough.
Names for months and weekdays are not accepted, write the numbers. 32 lines to a
crontab.

The file is `/var/spool/cron/<user>`, root's and `600`, in a directory that is
root's and `700`: `crontab -l`, `crontab -e` and `crontab -r` are the only way in,
which is what keeps one account from writing a line that runs as another. A file
that will not parse is refused whole when you save it, where Vixie refuses it and in
his words:

    Cannot save: "/var/spool/cron/admin":1: bad minute

**at** is the other half of the same machinery: one job, at one time, and then
forgotten. It reads its commands from standard input, which on this machine is a
**pipe** and nothing else, so `echo halt | at 04:00` is the shape, and `at 04:00`
with nothing on its left answers its usage line like every other command that reads
a pipe. `atq` lists what is waiting and `atrm` takes one out; `at -l` and `at -r`
are the same two, as they are on a real BSD. A time is `HH:MM` (no `now + 1 hour`,
no `4am`) and one that has gone by today means tomorrow.

The queue is `/var/spool/at`, one **file** per job named by its number, root's and
`600` in a directory that is root's and `700`, and `at` is the program that reaches
it on an account's behalf, the shape `crontab` has here and for the same reason. So
the queue survives a save because the filesystem does, and the file's header line
(`at <user> <second>`) is what says whose job it is and when. The number handed out
is the lowest that is free, so `atrm 1` is a line a survivor can type.

**Where at differs from cron, and it is the clock.** A minute cron slept through is
gone; an at job is a thing somebody asked for and it sits in the queue until it has
been **done**, so a job queued for four o'clock on a machine that was off at four
runs when the machine comes back, which is what `atrun` does on a real one. The
file goes when the job **starts**, and only then: a job the machine had no room for
(four is the ceiling) is still in the queue next minute, where a cron line is skipped
because it will come round again. `CeroSecJobs.atPass` fires them, through the very
`cronFire` a crontab line goes through, so the output goes to the account's mail for
the same reason.

**What cron will not do.** It does not catch up: a machine that was switched off at
four in the morning, or whose part of the world nobody was near, does not run four
o'clock's line when it comes back. A minute cron slept through is a minute that is
gone, real cron does not go back for one either, which is what `anacron` was
written for, and there is no `anacron` here. And it does not get more than its
share: a machine runs four jobs at once and no more, cron's included, so a line that
comes due with the machine full is **skipped** and the log says so in cron's own
words, `(CRON) error (can't fork)`.

**A cron line has no terminal**, and the machine holds it to that. Nothing it can
write reaches the glass a survivor might be standing at: `rlogin` is refused with
`rlogin: not a terminal`, and so are `su`, `passwd` and `sudo`, a password
question is only ever put up for the job holding the prompt, so from cron it would
wait for an answer that could never come, and four of those are every job slot the
machine has. `clear` runs and clears nothing, because the glass is not a cron
line's to wipe. `edit` has always answered `edit: not a terminal`, and an `exit`
ends the line and never the session. `rsh` is the one that does work without a
terminal, exactly as real `rsh` does: the cron job waits for it and what the far
command printed comes back in the mail, with everything else that line printed.

What a cron job **prints** never reaches the screen, there is nobody at the screen
at four in the morning. It is mailed to the account, with the `From` and `Subject`
lines a mailbox has always carried, and `mail` shows it and empties it:

    admin@ksp-04-11:~$ mail
    From cron  Thu Jul  8 04:00:00 1993
    Subject: Cron <admin@ksp-04-11> echo tick
    tick

`/var/log/cron` (root's, `640`) says what ran, and what could not. Both it and the
mailboxes are bounded by lines and by bytes and are exempt from the 64 KB by their
path, the same way `~/.sh_history` is, a machine must not fill its own disk with
what it said about itself while nobody was looking.

Reading mail does not destroy it. `mail` shows what is in the spool and **moves** it
to `~/mbox` as it goes -- 4.4BSD Mail's own pair, where the spool is what has arrived
and `~/mbox` is what has been read -- and `mail -f` reads `~/mbox` and moves nothing.
The move is an ordinary write in an ordinary home, so it pays the disk; a drive with
no room leaves the spool exactly as it was and says so, having shown the messages
anyway, because they have been read and what failed is the keeping. `You have mail.`
at the login is still about the spool alone.

A script can **post** mail as well as read it: `mail [-s subject] user...` takes
its body from the standard input, which is a pipe (`echo copied | mail -s Backup
bob`) or, with a pair of hands behind it, the terminal a line at a time until a
line holding a single `.`. A line with nobody behind it, a crontab line, a `&`,
has no input at all, so the body is empty and `mail` says `Null message body;
hope that's ok` and posts it anyway. Delivery goes through the same `mailAppend`,
so the spool keeps its modes: the box stays the recipient's own at `600` in
root's directory, and the privilege is the engine's writer rather than a mode
somebody loosened (which is the `setgid mail` of a real spool, done the way this
machine can do it). What it does **not** inherit is the quota exemption above:
that exemption is for the machine writing about *itself*, so the bytes a message
somebody typed really adds are charged to the drive and put back when they do not
fit, `mail: /var/mail/bob: disk full`, and nothing written.

Across the wire it is `cat note | rsh gate mail -s Hi bob`: `rsh` drains its own
standard input before it dials and hands it to the far command as an ordinary
pipe buffer, and a far command with no pipe behind it is handed one already at
end of file, which is why `rsh gate mail bob` posts the empty message instead of
waiting for a body nobody can type. An address off the machine (`bob@gate`,
`gate!bob`) is refused where it is typed: `bob@gate... Cannot send mail: no
mailer`, a declared deviation, because 4.4BSD would have tried and there is no
uucp on this disk.

**Waiting on a device** is a loop, not a command. Unix has never had a "wait until
this happens", and this machine does not invent one:

    while [ "$(cat /dev/door0)" = closed ]; do
        sleep 5
    done
    echo on > /dev/light0

A sleeping job is off the processor entirely, it is not spending its five minutes
and it can wait for days, so that asks the machine for one turn every five seconds
and nothing in between. The same loop without the `sleep` is the one thing not to
write: it takes every step the machine will give it and gets nothing done any
sooner. `sleep` takes whole seconds, as it does everywhere.

**A daemon, and where it keeps what it knows.** "Wait until this happens" is a loop,
and a loop that has to remember something between two turns has one place to put it:
a file. There is no `local`, there are no associative arrays, and a variable belongs
to the job, so the shape a 1993 script used is a **flag file**, and these machines
have `/var/tmp` for it (root's `/tmp` does not exist here; `/var/tmp` is the one
directory anybody may write in and only the owner of a file may delete from).

Two uses, and the home kit's programs are both of them (`CeroSecContent.SCRIPTS`,
docs/CONTENT.md):

    F=/var/tmp/autoclose.on
    echo run > $F
    while [ -f $F ]; do ... ; sleep 1; done

That is the **switch**: `start` writes it and loops while it is there, and a second
run with `stop` removes it and the loop ends at its own next turn. It is not better
than `kill %1` and it is not instead of it, it is a thing a survivor can see with
`ls /var/tmp`, a thing a crontab line can touch, and a way to stop a daemon that
`jobs` on a machine full of other people's work would make awkward.

    t=/var/tmp/autoclose.$d
    c=0
    if [ -f $t ]; then c=$(cat $t); fi
    c=$((c + 1))
    echo $c > $t

That is **state per thing**, which is the associative array this shell has not got:
one file per device, named after it. Three rules come with it and every one of them
was paid for:

- **`rm` has no `-f`**, so a removal is `if [ -f $t ]; then rm $t; fi`. A daemon that
  removed a file that was not there would print a refusal every second it ran.
- **Count rounds, not seconds.** `date +%s` is the *world's* clock and moves a minute
  at a time (`SCeroSecSystem:clockEnv` builds it out of the hour and the minute with
  the seconds at nought), so two stamps taken inside one game minute are the same
  number and nothing finer than a minute can be measured against it. What a `sleep 1`
  loop can count is its own turns.
- **A round is a second and a little more.** The sleep is a second; the work of the
  round, a `$( )` per listing, a `cat` per device, the counter file, is charged in
  steps against `CeroSec.STEP_BUDGET_PER_MACHINE`, so a round costs the sleep plus
  however many passes that work took. A bench that pinned five rounds to five seconds
  exactly would be a bench that goes red on a busier machine.

**`fg`** brings a background job back to the front:

    admin@ksp-04-11:~$ sh watch.sh &
    [1] 43
    admin@ksp-04-11:~$ fg %1
    sh watch.sh &

`fg %1` names the slot `jobs` prints, `fg 43` the id `ps` prints, and `fg` on its
own is the job started last. What it changes is where the output goes and who
Escape belongs to. There is no `bg` and nothing to use it for: nothing on this
machine suspends a job, so the only direction one can be moved in is forwards. A
cron job is not one of these, nobody at a keyboard asked for it, `jobs` does not
list it and `fg` will not have it, though `ps` shows it.

## The shell that looks a name up, and the links it walks

Three pieces of plumbing came with `PATH`, links and `ls`, and each is in exactly
one place.

**What the shell knows.** A command is handed one thing more than its arguments: a
small table of what the *shell* knows about the line, `path`, the `PATH` to look a
bare name up on, and `tty`, whether what it writes is going to a screen at all.
Neither is a fact about the filesystem, so neither is looked up by whoever needs it;
`CeroSecOSVM.runSimple` builds it, `runArgs` passes it down, and `sudo` and a
continuation forward the one they were given. `tty` is false for the three doors
output already goes through other than the glass, a `$( )` capture, a pipe, `cron`'s
mailbox, plus a redirect, and the **last** stage of a pipeline inherits the answer
from whatever is running the pipeline (its pipe is drained onto that). `ls` is the
one command that reads it today, and it reads it exactly as every `ls` reads
`isatty`.

**A script inherits the redirect of the command that started it.** A process's
standard output is the process's, so `sh a.sh > out` opens `out` and everything the
script prints goes in it, nested scripts and all, because nothing closed the file.
Until this the redirect belonged to the *word* `sh`, which prints nothing: `out` came
back empty and the script's own lines went on the glass. The pipe and the capture
were never wrong, because those are doors on the **job** and a script runs in the job
that asked for it (`CeroSecOS.jobRun`), which is why `./a.sh | wc -l` and
`x=$(sh a.sh)` always worked. `./thing`, a name on `PATH` that turns out to be a
script, and the dot all go the same way.

It is a fourth door in `outLine` (`job.rdto`), and everything else about it follows
the three that were already there: `tty` is false through it, so `ls` inside the
script prints one name a line; a **refusal** is not output and goes to the screen, as
`ls /nope > f` already does; the line goes over whole, unwrapped, because a file is
not sixty columns; and the lines wait in a buffer the **pass** writes, because
`outLine` is handed a job and a write needs a filesystem and a clock. The buffer
meets the screen's own forty-line limiter, a redirected script puts nothing in
`job.out`, so without that the limiter that bounds every other flood would never
fire, but the runaway clock is *not* stopped while it waits: nothing is holding the
job back except the end of the pass, and a target with no contents to fill (a device)
would otherwise run for ever. A write that cannot be made, the file at its 4096
bytes, is the end of the output and so the end of the job, with the refusal on the
screen; 4.4BSD sends `SIGXFSZ` for that and the default action is to terminate.

**What the walk costs.** `CeroSecOS.lookupPath` walks `PATH` left to right and
answers where it found the name, why it did not, **how many directories it looked
in**, and whether what answered was a link. The count is charged in steps by
`runSimple`, one per directory past the first, because a long `PATH` makes every
command on the machine dearer and a budget that could not see that would not be a
budget: measured, a kilobyte of `PATH` was a command twenty times dearer than
`STEP_COST_COMMAND` believes it is. Two ceilings follow, `MAX_PATH_DIRS` (8),
refused at the assignment with `too many PATH entries`, and the same number as a
belt on the walk itself, so a value off a save file nobody can explain is slow for
nobody. `tests/hostile_test.lua` drives the worst legal `PATH` and a forged
340-field one.

**A command that runs other commands, and one that needs another turn.**
`find -exec` is the only command on this machine that runs commands of its own, and
it is the reason the shell's little table carries two more fields. Every exec goes
through `CeroSecOS.runArgs` like any other command, the `PATH` walk, the
permission, a script in `~/bin`, all of it, with `tty` and `keys` false, because
nobody is standing behind one; an out-of-band order (`edit`) is refused there with
the line the engine gives a command in that position, since a marker must never
travel out through find. A word the *shell* is gets sudo's answer,
`cd: command not found`: find execs a program.

An exec is a **command's** worth of work, and find runs `FIND_EXEC_TURN` of them
before handing the machine back, so the turn is charged the one command every
command is charged, which is the honest price of it: the exec is the work in the
turn and the rest is find looking up where it had got to. Two fields carry that:
`sh.again` asks for another turn and `sh.carry` is what it wants handed back,
kept on the frame (`f.rd.carry`) exactly as a pipe reader's carry is. That is what
keeps the invariant every `jobStep` call is held to, *a pass may go over its budget
by at most one command*, with a sweep of five hundred files behind it: it trickles
at a command a turn, printing as it goes, and `-exec … +` (64 names to a command) is
the form POSIX gives you for doing it in one. A resumed command's redirect appends
from the second turn on, through the same door a stage's does, so `find … -exec cat
{} \; > all.txt` does not truncate the file it is filling.

`tar` takes another turn the same way, and for the same reason measured: a member
is a file read or a file written, twenty of them in one call cost 0.9 ms against
the 0.2 ms a command is charged, and a loop of `tar cf` was a machine spending most
of a pass's wall clock on one command. It does one member a turn, `c` gathers,
then writes the archive on a turn of its own; `x` puts one member back a turn;
`t` reads the file it has already read and is one command.

**Where a link is followed.** `CeroSecOS.getNode` and nowhere else, which is why no
command had to learn about links: a link in the middle of a path is the directory it
names, a link at the end of one is the file it names, and the absolute path that
comes back is still the **logical** one, so `cd` through a link prints where you
typed. A fourth argument leaves the last component alone, the difference between
`stat` and `lstat`, and the four commands that act on the link ask for it.
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
missing `done` never costs a tick, and what comes out is inert. There is no `load`,
no `loadstring`, no `setfenv` and no metatable; the arithmetic in `$(( ))` is read
digit by digit by a recursive-descent reader in the VM. Nothing a player types is
ever evaluated as Lua, and `tests/kahlua-check.sh` greps for it.

`CeroSecOSVM.lua` is the stepper:

    CeroSecOS.jobStep(state, job, env, budget) -> status, stepsSpent

`status` is `"running"`, `"waiting"`, `"sleeping"`, `"done"`, `"killed"` or
`"error"`. It runs up to `budget` steps and returns; it never loops to the end and
never waits. A **job** is a plain serializable table, a program, a stack of frames,
its variables, its pending output, a session of its own, and holds no function at
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
`CeroSecOS.STEP_COST_COMMAND` (32) for a command that goes out to `/bin`, measured
between 20 and 500 microseconds a call against about 6 for a builtin, so a flat step
would have been a budget eighty times out on a loop of `ls`. The steps of what
`$(...)` runs are charged to the job that asked. A pass may overspend by at most one
command, since a command's price is only known once it has been paid; the overspend
is carried as a `debt` and taken off the next pass, so the average is exactly the
budget.

Every wait is a continuation. `read` and a command's own question (`sudo`,
`passwd`) both leave the job `"waiting"`, the console puts the question up with an
ordinary prompt token `{ cmd = "job", id = 42 }` and the answer comes back through
`CeroSecOS.jobInput`. `sleep` leaves it `"sleeping"` against `env.nowMs` and costs
nothing until it comes round. A question with a **redirect** behind it keeps it:
`job.contRedirect` is what `>` named, opened when the question went up
(`CeroSecOS.openRedirect`) and handed to `CeroSecOS.continue` with the answer, so the
write happens beside every other command's, on the lines as the command made them,
before the screen's own sixty columns are applied to anything.

`SCeroSecJobs.lua` is the scheduler and the only half that knows there is a server.
Ten passes a second on `Events.OnTick` gated by `getTimestampMs()`, vanilla's own
way of getting under a minute (`forageServer.lua:502`), with
`CeroSec.STEP_BUDGET_PER_TICK` (200) steps to hand out across every machine that has
a job, no machine taking more than `CeroSec.STEP_BUDGET_PER_MACHINE` (100), and
machines served round-robin from one further along each pass. A starved job runs
slower; nothing is ever refused a turn. Output drains at `CeroSec.JOB_OUT_PER_SEC`
(20) lines a second **per machine**, and a job whose queue is full simply does not
run until the screen has taken what it wrote. A job that holds the processor with no
wait in it for `CeroSec.JOB_CPU_LIMIT_S` (300 s) is killed with `killed: cpu limit`,
a constant with a comment, not a sandbox option, because a server owner who wants
a different number should be given a setting rather than asked to edit a file.

`luaObject.jobs` is the live book and is **not one of the object's saved keys**. It
is written into the machine's own state, at `os.jobs`, when the world is saved and
read back out of it when the world is loaded, see "The book across a save" at the
foot of `SCeroSecJobs.lua`, which carries the whole of it. Reboot, shutdown, a room
that lost its power and a computer picked up all still kill everything; a save and a
load do not, because a computer the world saved was never switched off.

What survives, and what does not. Every "no" below is one test in
`CeroSecJobs.jobRefused`, and the word in brackets is the one it answers with, the
table is the function's rows and not a summary of them, and `jobFromData` asks the
very same function again on the way in, so a forged book cannot hand back what the
save would not have written:

| | |
| --- | --- |
| a background `&` job | **survives** |
| a cron or `at` child | **survives**, its output goes to a mailbox on the disk |
| the foreground job of the machine's own glass | **survives**; the console is saved and the note of which job it was is put back by `SCeroSecObject:consoleState` |
| a job that has ended | no (`over`), it is about to be reaped |
| a job that is **waiting** | no (`waiting`): a pending `shutdown`, a `read` with its question up, a `cu` at the TNC's `cmd:`, a `wait`. Each waits on something a reload has not got |
| a job whose terminal came in over the wire (`job.pty`) | no (`a session`): `luaObject.ptys` is not saved, so its screen is gone |
| a job holding something the world owns (`job.remote`, `job.dial`, `job.ring`) | no (`the wire`): a session at the far end, a dial in flight, a radio link |
| a job caught between asking the machine for something and being given it (`job.orders`, `job.spawn`, `job.killReq`) | no (`mid-order`): a `wall` or a `clear` the pass has not carried out, an `&` it has asked for and not been given, a `kill` it has been asked for. Each is half of a handshake the scheduler finishes inside one pass, so there is nothing on the far side of a save for the other half to reach |
| a job with no program or no frames | no (`no program`) |
| a job table that is not one, or a frame that is not a table | no (`not a job`, `bad frame`), neither is a state a running job can be in; both are the shape refusals under everything above |
| a pipeline in flight | **survives**, at the step it was on: the job is written as a graph, each table once and a one-key marker wherever it is reached again, so the pipes, the stages' links back to their pipeline and the parsed program the frames and the stages share all come back as the *same* tables and not as copies of them (`CeroSecJobs.intern` and `resolve`). A stage is asked the same questions the job is, recursively, and refuses by name: a stage that is **waiting** (`a stage is waiting`: a `read` with its question up, a `wait`, a timer), one **on the wire** (`a stage on the wire`) or **mid-order** (`a stage mid-order`), and a pipeline nested deeper than a job may be (`too deep`). A stage's sleep keeps what is left of it, as the job's does. It costs a third of what the same job cost as a tree (the shipped `autoclose.sh` is 371 tables in the middle of `ls /dev \| grep ^door`, where the tree was 1205), which is what lets a pipeline through the book's ceiling |
| a book entry off an older build | still read: the entry used to be the job itself, and that flat form loads as it did. It never carried a pipeline, and one that claims to is refused (`a pipeline`). The other way round, an older build reading a `{ packed = ... }` entry finds no `id` in it and drops that one job with a line in the log, never the machine |
| the prompt's own job when it is **not** the one holding the glass (`job.interactive` without the console naming it) | no (`an orphan prompt`), and this one is `jobToData`'s rather than `jobRefused`'s, because whether a job holds the glass is the console's answer and not the job's: only the job the glass names can be given its shell back, so any other interactive job is a shell nobody would be typing at. The console always hands its prompt to the interactive job it makes, so there is no way to build one of these from the glass, it is a belt under a state the wire cannot reach |
| a job whose saved shape is bigger than `CeroSec.JOB_SAVE_BYTES`, or that does not fit what is left of `CeroSec.JOB_SAVE_TABLES` | no, and it is **not killed for it**: it goes on running, it is left out of the save, and the log says so |
| a job **too deep** for the state gate, or holding something the graph form cannot say (`not plain data`: a table that already means a marker, a key that is a table), or a pipeline that has more stages than the shell makes or a pipe too few (`bad frame`) | no, and it is **not killed for it** either: it goes on running, it is left out of the save, and the log says which of them it was (`left a job out of the save: <why>`). Depth is counted from the root of the *state* and not of the job: the book's entry is three levels down, the job one more, so a job has sixty-one levels of its own. The refusals that are only what a job is doing (waiting, a session, the wire, mid-order) are not in the log, they are not news |

A **sleep keeps what is left of it**, not the moment it was due: a `sleep 3600`
started a minute before you quit still has fifty-nine minutes on it when you come
back. A job's cpu accounting starts again, the runaway ceiling counts continuous
processor time, and a job just rebuilt has spent none.

A sleep's clock in a save file is a finite number of milliseconds, at most a thousand
million seconds (a `sleep inf` is written as that): NaN and infinity compare false with
every clock there is, so a job carrying one would be asleep for ever, and a job that
does is refused as forged (`bad clock`). The same gate holds a pipe to being what a
pipe is: one table of its own per stage, and a byte count that is a whole number, no
more than a save may carry and no more than the lines in it add up to. (Not
`PIPE_LINES` and `PIPE_BYTES`, which are the back-pressure asked before a stage is
stepped: one `cat` puts a whole file into the pipe, so a legal pipe is past both.)

A book off the save file goes through a gate of its own before a single job is put
back (`CeroSecJobs.jobFromData`): every field is asked its type, and a program is
asked the one shape the walker could be made to trip over, every value at an
integer key is a table, `k` and `t` are strings, a list node's `ops` are strings. A
job that fails it is dropped with a line in the log, never a crash, and the machine
comes up with the rest.

## Pipelines: a shell per stage

A pipeline is one job with several shells inside it. `pushNode` turns a `pipe` node
into a frame holding an array of **stages**, each one a job table of its own, built
by `newJob` with a copy of the pipeline's variables and session, which is exactly
what a subshell is, and an array of buffers, one per stage:

    { k = "pipe", stages = { <job>, <job> },
      pipes = { { lines = {}, bytes = 0, eof = false, closed = false }, ... } }

`pipeStep` is one turn of it. It drains the last stage's buffer into the job that
owns the pipeline (so a pipeline inside `$(...)` is caught by the capture like
anything else), marks `eof` behind a stage that has finished and `closed` in front of
one, and then steps the **rightmost stage that can run**. A stage that cannot is one
waiting for a line that is not there (`blocked = "input"`) or one whose buffer is
full, and reading right to left is where the back-pressure comes from: the reader
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
pipe, or the screen. `errLine` is the other half, a stage's *refusals* go to the
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
`cronDue(entry, parts)` against `CeroSecOS.dateParts`, and the two bounded writes:
`cronLog` and `mailAppend`. `commands.crontab` and `commands.mail` live there too,
and so does the sending half, `CeroSecOS.mailSend` and `continuations.mail`.

`CeroSecJobs.cronPass(system, luaObject, now)` is the daemon, and there is no process
for it: `SCeroSecSystem:checkCron()` walks every machine that is **on** on
`Events.EveryOneMinute`, the same sweep the power check uses, because the two ask the
same question of the same list. On, and not "in view": a machine whose chunk the
streamer has taken away keeps its power, its jobs and its crontab, and cron goes on
firing for it, because none of the three is a thing in the world (see
[ARCHITECTURE.md](ARCHITECTURE.md#the-chunk-that-goes-away), the pass used to stop for
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
game's Lua is not this one. Kahlua is an interpreter written in Java and is
expected to be several times slower, which is why the county's budget is a fifth of
what the measurement alone would allow.
