# CeroSec — Protocol

The language the client and server speak: what a screen is, what a control marker
orders the terminal to do, how Tab and a device highlight get an answer addressed
to one window, and how a remote session's screen reaches the right glass.

See also: [ARCHITECTURE.md](ARCHITECTURE.md) for the server/client split this
protocol runs on, [NETWORK.md](NETWORK.md) for the sessions it carries,
[DEVICES.md](DEVICES.md) for the device highlight this is the wire for.

## Completion and control markers

`CeroSecOSComplete.lua` is the only other way in, and it is a read:
`CeroSecOS.complete(state, session, line, cursor)` answers
`{ replacement, candidates, start }` for the word at the cursor. It moves nothing,
creates nothing and stamps nothing — it is what Tab asks.

`lines` is text, one array entry per screen line, at most 60 characters. `control`
is `nil`, `"clear"`, `"exit"`, `"prompt"`, `"edit"`, `"job"`, `"shutdown"`,
`"reboot"`, `"schedule"` or `"cancel"` — an order to whoever runs the machine,
carried beside the output and never inside it, so a file's contents can never be
mistaken for one. `"prompt"`, `"edit"` and `"schedule"` carry a payload in `data`:
`"prompt"` is how a command like `passwd` or `sudo` asks a question without a
coroutine (`CeroSecOS.continue` answers it); `"edit"` hands the terminal a path, the
file's text, whether it may be written back, and the account it was opened as;
`"schedule"` is `shutdown +N` handing over the moment and the kind. The rest carry
nothing: the engine has no machine to switch off, so it says what should happen and
the server — which owns the sprite, the sound, the power and the windows — does it.

A control from inside a job **ends** the job, the way a real shell's `exec` does: a
line that has ordered the machine off has nothing left to say. All of it, script or
no script: a `shutdown` written two files deep is still the machine going dark.

`exit` is the one word with a foot on both sides of that. Typed at the top level of
an interactive shell it is the `"exit"` control — the logout, or the pop of an `su`.
Written in a file, in a `$(...)` or in a stage of a pipeline it is not a control at
all: it ends that script, that substitution, that stage, with the status it was
given, and the shell it was started from goes on with `$?` set — which is POSIX, and
which is what keeps a usage-and-exit script from throwing the player off the machine.
`~/.profile` is deliberately on the interactive side of the line, because it runs AS
the login shell: `exit` in a profile logs out, exactly as it does in bash.

A command that has to ask something answers `"prompt"` with an opaque continuation
token, and the console hands the next line typed to `CeroSecOS.continue`. Nothing of
a password ever goes into a token: between `New password:` and `Retype new
password:` what is carried is a hash of the answer with its own salt, and a `sudo`
token carries only the command that was typed and the account that typed it — the
answer is judged against `/etc/passwd` when it arrives. A token started under `sudo`
carries `as = "root"`, which is what makes `sudo passwd root` root's for the whole
chain while the console's own session stays `admin`'s.


## The wire messages, and a screen

The context menu (`CeroSecContextMenu.lua`), the reach checks (`CeroSecReach.lua`)
and the terminal window (`CeroSecTerminal.lua`, an `ISCollapsableWindow`) are all
client-side. The window talks to the server over the global object channel:

    client -> server: open, exec, close, input, interrupt,
                      editbuf, editsave, editexit, histtail
    server -> client: opened, screen, closed, history

A screen is sent whole: the lines, the prompt, the mode (`prompt`, `shell` or
`edit`), whether the answer is masked, whether the machine is in the middle of
something (`active`), the editor's own screen, and `user` — who is logged in, as one
short string. The window's Up/Down history is the account's own `~/.sh_history`, sent
in its own `history` reply when a window opens and whenever `user` changes under it
(a login, an `exit`, an `su`); a hundred lines on every screen would be a hundred
lines on the wire every time anybody typed. The window draws what it is
handed and works nothing out for itself — which is why Escape can be an interrupt
without the window ever having to tell `New password:` from any other question.
`interrupt` is that Escape: it clears the pending question on the machine and kills
the foreground job, so every window standing at it sees the same `^C` on the same
line.

`Commands.exec` echoes the line, appends it to the history, and then runs
`CeroSecJobs.runMachine` **in the player's own hand** — one scheduler pass, right
there — rather than leaving the line to the next tick. Two orders need a player:
`edit` has to know whose keyboard is on the buffer, and `dev find` answers on one
screen rather than on the machine's. So an ordinary `ls` still answers in the same
round trip it always did; a line that does not finish in that pass becomes a running
job like any other. `Commands.input` and `Commands.interrupt` serve a pass the same
way, which is what makes `sudo reboot` end on its password and the prompt come back
from a `^C` without waiting a tick. `SCeroSecSystem:runProfile` is the same call
again, on the text of `~/.profile`.

Every command carries the window's own token and every answer carries it back
(`sendServerCommand` reaches one connection, or the global object broadcast in
singleplayer where there is only one), because the server addresses a connection
and split screen puts several players on one. The server keeps a watcher list per
computer and answers every open window with the new screen under its own token.

## The device highlight, addressed to one window

`dev find` answers the question a listing cannot: **which** of the thirty-five it
is. A light blinks for six seconds and goes back exactly as it was found — a
server-side timer on `Events.OnTick`, gated on `getTimestampMs()` the way
vanilla's own `forageServer` gets under a minute — and a light with no power
answers `light0: no power`, the same as a write. A door or a window has nothing
to blink with, so the server tells the one window that asked where to look and
that player's client outlines the object with vanilla's `setHighlighted` /
`setOutlineHighlight`, which take the local player number first: in multiplayer
only the survivor who typed it sees the outline. It asks for the right it uses —
a light is switched, so blinking one needs write; a door is only drawn around, so
reading it is enough.

## Remote sessions: whose screen an order writes to
**Whether the job giving that order has a terminal is decided in the engine**, in
`jobHasTerminal` (`CeroSecOSVM.lua`): the prompt's own job, outside every pipe and
every `$(...)`, and deliberately at any DEPTH, so a foreground script inherits the
terminal it was started from. `exitLeavesTheMachine` is that rule plus the depth
rule, which is the one thing `exit` has and `rlogin` has not. An `"rlogin"` order
from a job with none is refused there; an `"rsh"` order is marked `noTty`
whoever gave it, and `SCeroSecNet.connect` then gives the session a console of
its own with no copy of the glass on it and never points the near console at it.
The order is carried out while the job that gave it is still on the book — it is
a WAIT and not an exit (`job.dial`, the same road `job.spawn` takes for an `&`,
because only the machine can reach another machine) — and the teardown hands what
the session printed, plus the far job's status, to `CeroSecOS.jobRemote`, which
writes it through that job's own door: the glass, the pipe, the capture, the mail.
A stage of a pipeline dials through its pipeline (`f.dialling` on the pipe frame),
since a stage is a shell the machine knows nothing about. The one
guard that closes every path at once is in `SCeroSecSystem:pushScreen`, which
sends nothing from a console marked `noTty` to any window: the FAR machine's own
scheduler pushes the screens its jobs wrote on and knows nothing about whose
session they are. `answerDial` asks the same question again at the door, for an
order that reached the server any other way.
