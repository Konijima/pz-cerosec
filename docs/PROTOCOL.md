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
    server -> client: opened, screen, closed, history, drive

`closed` carries the reason the window is shutting: `off`, `power`, `reach`, `gone`,
`broken`, `exit` — and `reboot`, which is the only one that says the machine is
coming back. A reboot is a power cycle and the machine is physically off for
`CeroSec.REBOOT_DARK_MS` in the middle of it, so the window really does shut; what
makes it different from `off` is what happens at the other end of the dark.

`reopened` is that other end, and it is the one answer that is not addressed to a
window: it ASKS for one. The server remembers which players were at the glass when
the machine went dark, and when the machine comes back up it sends each of them who
is still standing there a whole screen — the same fields `opened` carries — under a
token the SERVER minted (every other token in the mod is the window's own) plus the
local player number, because there is no window yet to route it by. The client
builds the box around it through `CeroSecTerminal.sitDown`, which is the very call
the end of the walk makes (`ISCeroSecUseAction:perform`): the same window class, the
same character at the keyboard, no second walk and no second seat. A player who
wandered off in those seconds is sent nothing and uses the computer by hand. In
multiplayer each one is a `sendServerCommand(player, ...)` of its own, like every
other answer.

`drive` is the other answer with no window behind it, and the drive is why: a disk
goes into a machine that is switched off, with nothing open to draw a line on. It is
sent when an `insertfloppy` did **nothing** — the machine is not there (`gone`), the
slot is full (`occupied`), what was offered is not a disk in the sender's hands
(`nodisk`), the disk itself will not pass the engine's gate (`refused`, with the
machine's own reason in `detail`), or the machine's state will not (`broken`) — and
it carries the local player number, like `reopened`, because it lands over ONE
survivor's head. What travels is the code and never the sentence: the client owns the
words, and they are in `Translate/EN` and `Translate/FR` with the rest of what this
mod says to a player. The only refusal that stays silent is a packet with no item id
in it, which no client sends and no survivor is waiting on.

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

**That list is bounded, both ways, and it has to be:** the key is the online id and
the token the CLIENT picked, so one `open` per fresh random token used to add one
permanent entry apiece — and every entry is one `sendServerCommand` on every later
screen of that machine, paid by whoever types at it next. So a second `open` from the
same player replaces his first, which is told `closed` with the reason `replaced`, and
one machine holds at most `SCeroSecObject.WATCHERS_MAX` windows whatever the online
ids say, the oldest going first. Both rules live in `SCeroSecObject:addWatcher`, the
one place a watcher is ever inserted, and the same player is the same by online id
**and** player number, because split screen is two survivors on one connection. In
play neither rule ever fires: the client already shuts its own previous box (one
terminal per player, `CeroSecTerminal.open`). The debug window's machine tab prints
the count as `windows`.

## The `device` packet: the one sync the mod writes itself

    server -> every client: device { x, y, z, index, class, sprite, on, channel }

Every other actuator in the mod is broadcast by the engine. A television or a
radio set is not: `DeviceData.transmitDeviceDataState(short)` is a client branch
and nothing else, the server's own broadcaster is `private`, and the one public
wrapper spends its `short` on the battery — so a server-side `setIsTurnedOn(true)`
moves the field on the server and leaves every client's copy dark. The full
bytecode is in [DEVICES.md](DEVICES.md#the-sync-the-mod-writes-itself).

It is the only server→client message in the mod that is **not addressed to a
window**, and the only one sent with the three-argument
`sendServerCommand(module, command, args)` — the broadcast form, which walks
`GameServer.udpEngine.connections` and is what vanilla's own server Lua uses for a
world change nobody in particular asked for
(`server/BuildingObjects/ISWoodenFloor.lua:21`). A survivor's screen is his own
business; a television coming on in a room is everybody's. It carries no token for
the same reason: there is no window to route it to.

It lands on `Events.OnServerCommand` and not on the global object channel, and the
two doors are not interchangeable here. The global object channel is what
singleplayer answers on, and in singleplayer there is nothing to sync — one
process means the object the server wrote is the object the survivor is looking
at, and `sendServerCommand` is a no-op with no `GameServer` behind it anyway.

`x, y, z` is the square; `class` is what the far end asks `instanceof` for and
`sprite` is `getSpriteName()`, which is the same pair `dev find` travels on
(`CeroSecDevices.handleOf`, the one place either is worked out). `index` is which
of that square's objects it was, and it is there for the one case a class and a
sprite name cannot tell apart: two identical televisions on one tile. It is
believed only when the object at it is the right class and sprite, and a scan of
the square is what answers when it is not — the index agrees on both sides for as
long as nobody has added or taken away an object there, both lists being built
from the same chunk.

`on` and `channel` are **both** sent on every packet, whichever field the order
was about, and they are read off the object *after* the write rather than taken
from the order: `setIsTurnedOn` refuses an unpowerable set by turning it off
instead, so what was asked and what happened are two facts. Sending both also
means a client that missed one packet is put right by the next.

The far end applies them with `setTurnedOnRaw` and `setChannelRaw` and answers
nothing — the public setters would transmit, the server would relay that to
everybody, and one crontab line would cost a round trip per client. A packet about
a square the client has not got does nothing, and nothing is lost by that: the
chunk asks the server for its objects' state on the way in.

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
