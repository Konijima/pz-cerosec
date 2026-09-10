# CeroSec rung 2 — manual test checklist

Build 42.20.4. The terminal window is the one part of the mod no headless test can
reach: the pure logic under it (hostname, prompt, the console and its ring, the
history) is covered by `tests/terminal_test.lua`, everything below needs a pair of
eyes.

Do rung 1's checklist first, or at least step A1-A5 of it: nothing here works on a
computer that will not turn on. Turn `CeroSec.DEBUG = true` in
`42/media/lua/shared/CeroSec/CeroSecDefs.lua` for the console lines.

The default accounts ship open: `root` with an empty password, `admin` with an empty
password (`CeroSecOSState.lua`, `newUser("root", "", ...)`). Just press Enter at the
password prompt.

## A — Opening the window

1. **Off, no option.** Right-click a computer that is off. There is "Turn on computer"
   and **no** "Use computer": a dark screen has nothing to use.
2. **On, the option appears.** Turn it on. Right-click again: "Use computer" is there,
   below the turn-off entry.
3. **From anywhere in the room.** Click "Use computer" while standing across the room.
   The character walks to the square **in front of the screen**, turns to face it,
   plays the short loot animation, and the window opens then — not before.
4. **On a desk (mid).** The animation is the standing reach. On a computer standing on
   the floor (**low**) it is the crouched one. Same rule as the toggle.
5. **Too high.** Stack the computer on a crate on a table (surface > 64). "Use
   computer" is greyed out with "This computer is too high to reach." — same wording
   and same reason order as the toggle.
6. **No access.** Put a computer so its front square is a wall or is unreachable.
   "Use computer" is greyed out with "You cannot stand in front of this computer."
7. **Window shape.** Dark grey PZ frame, title `CeroSec OS · ksp-<x>-<y>` once the
   server has answered, close box top left. Inside: a beige monitor bezel, lighter on
   the top and left edges, darker on the bottom and right, a black-green screen of
   60 columns by 20 rows in `UIFont.Code`, a small green power light bottom right of
   the bezel, and the hint line under it.
8. **Scanlines and glow.** Dark lines every 3 pixels across the glass, and the text
   has a faint halo. Set `CeroSec.UI_SCANLINES = false` / `CeroSec.UI_GLOW = false`
   in the defs and reload: both must vanish and nothing else change.

## B — Boot and login

The screen belongs to the machine, not to you. The BIOS is played once per
power-on, for whoever opens the computer first; everything typed lands on the
machine's console and stays there until the machine goes dark.

9. **The BIOS.** The five boot lines type themselves out over about two seconds,
   then the machine's banner. They are the server's lines, revealed at the
   window's pace: on a laggy server they arrive a moment later, all at once, and
   then reveal normally.
10. **The banner.** After the BIOS, the machine's own line
    (`CeroSec OS 1.0 -- unauthorized access is prohibited.`) and then `login:`.
11. **The cursor.** A solid block, on half a second, off half a second, sitting where
    the next character will go. During the BIOS there is no prompt in front of it.
12. **Type as root.** `root`, Enter. The name is echoed by the machine, the prompt
    becomes `password:` and what you type shows as `*`. Press Enter on the empty
    password: the masked line, the banner again, then the shell prompt
    `root@ksp-<x>-<y>:/root# `.
13. **Wrong password.** Log out (`exit`), log in as `root` with `xyz`: `login
    incorrect`, and back to `login:`.
14. **No such user.** `nobody` / anything: the same `login incorrect`, never "no such
    user" — the machine does not say which half was wrong. It is answered only at
    the **password** prompt, so an unknown name looks exactly like a known one on
    the way in.
15. **Type as admin.** `admin`, empty password. Prompt is
    `admin@ksp-<x>-<y>:/home/admin$ ` — a `$`, not a `#`.
16. **Keys do not reach the game.** While the window is open, type `wwww`, `1`, `e`,
    `i`. The character must not walk, swap weapon, or open the inventory: the letters
    go to the screen and nowhere else.

## C — A session

17. `ls -l` in `/`: the standard skeleton, `bin dev etc home root`, one line each,
    never wider than the screen.
18. `cd /etc`, `cat motd`, `cat hostname`. The hostname file holds the name in the
    title bar.
19. `cd`, then `mkdir notes`, `cd notes`, `echo "hello" > a.txt`, `cat a.txt`.
20. `echo "second" >> a.txt`, `cat a.txt`: two lines.
21. **Permission denied.** As `admin`: `cd /root` answers `cd: /root: permission
    denied`. As `root` it works.
22. **A command that does not exist.** `frobnicate` answers `frobnicate: command not
    found`.
23. **History.** Up walks back through the last lines, Down walks forward, Down past
    the newest leaves an empty line. Only the last 20 are kept.
24. **Scrolling.** Fill the screen (`ls -l /` a few times), then scroll with the mouse
    wheel over the window. `-- more --` shows on the top row while you are scrolled
    up, and any new output snaps back to the bottom. The wheel is the only way:
    a focused text box is handed exactly two keys by the game, Escape and Tab
    (`Core.updateKeyboardAux`), and key polling answers false while it has the
    keyboard, so PageUp and PageDown cannot reach us at all.
25. **clear.** `clear` empties the screen and leaves the prompt on the top row. The
    prompt always sits right under the last line printed, never at the bottom of an
    empty screen.
26. **exit.** `exit` clears the screen down to a bare `login:` — no `logout` line,
    nothing of the session left on the glass. Logging in again works, and lands in
    the user's home.

## D — Closing, and coming back

26b. **Click to type again.** With the terminal open and logged in, click somewhere
    else that takes the keyboard: on the ground (walk a step), then on the inventory
    or on the crafting search box. Typing no longer reaches the screen — that is the
    game handing the keyboard to whoever was clicked last, and it is not the bug.
    Now click **anywhere** on the terminal: the glass, the beige bezel, the title
    bar, the hint line under the screen. Typing resumes at once, and the **first**
    letter typed appears — no keystroke is eaten. Repeat for each of those four
    spots. Escape must still close the window afterwards, and dragging the window by
    its title bar must still work.

27. **Escape.** Closes the window. The keyboard goes back to the game (walk with WASD
    to be sure).
28. **The close box.** Same thing.
29. **Walk away.** Open the terminal, then walk off the front square (or get shoved by
    a zombie). The window closes by itself.
30. **Turn it off.** With the terminal open, have a second character — or the debug
    menu — turn the computer off. The window closes.
31. **Power loss.** Cut the power (debug menu, or wait for the grid to go). Within a
    minute the computer turns itself off and the window closes.
32. **Death.** Die with the terminal open. The window closes.

### The screen is still there when you come back

32a. **Walk away and come back, logged in.** Log in as `root`, run `ls -l /`, walk
    off the front square (the window closes), walk back and "Use computer" again.
    The window opens on **exactly** the screen you left: the same lines, still
    logged in as `root`, the same prompt. **No BIOS**, no `login:`, nothing typed
    again. This is the whole point of the rung — it is what was broken before.
32b. **And your directory too.** `cd /etc` before walking away. On the way back the
    prompt still says `/etc` and `pwd` answers `/etc`: the current directory is the
    machine's, not the session's.
32c. **Log out, walk away, come back.** `exit`: the screen clears to a bare `login:`
    and nothing of the session is left on it. Walk away, come back: still `login:`,
    still no BIOS. Somebody who finds the machine after you finds a locked screen.
32d. **Turn it off and on again.** Turn the computer off, turn it on, "Use computer".
    **Now** the BIOS plays, once, and the screen is empty behind it. Off is the only
    thing that wipes a screen.
32e. **The BIOS plays once, not once per window.** From the state of 32d, close the
    window (Escape) and open it again without touching the power switch: the boot
    lines are already on the screen, no second animation.
32f. **clear.** `clear` empties the console. Walk away and come back: still empty.

## E — Persistence

33. **Write, then reload.** Log in, `mkdir /root/notes`, `echo "kept" >
    /root/notes/a.txt`, `cat` it. Close the terminal, save and quit to the main menu,
    reload. Open the terminal: the file is still there — and so is the screen. You
    are **still logged in**, the `cat` output is still on the glass, and there is no
    BIOS. The console is saved beside the filesystem (`gos_cerosec.bin`).
33a. **A hundred lines and no more.** Fill the screen well past a hundred lines
    (`ls -l /` a dozen times), save and reload: the last hundred are there and the
    oldest are gone. That ceiling is what keeps the save file honest.
33b. **The screen does not travel.** After step 34 below (pick up and place), the
    machine comes back **blank**: the filesystem rides in the item, the screen does
    not, because picking a computer up unplugs it.
34. **Pick up and place.** Write a file, close the terminal, turn the computer off,
    pick it up, walk somewhere else, place it, turn it on, open the terminal, log in.
    The file is still there — the state travels in the item's `movableData`.
35. **The hostname does not move.** After 34, the title and `/etc/hostname` still show
    the name the machine got on its **first** boot, not one derived from the new
    square.
36. **A second computer is a second machine.** A file written on one is not on the
    other, and their hostnames differ.

## F — Two players (Host mode)

One computer, one screen. Two players standing at it read and type on the same
one, and that is intended: whoever can reach the keyboard can use the machine.

37. Host a game, join with a second client, both walk to the **same** computer.
38. The first to open it watches the BIOS. The second opens it and finds the boot
    lines **already there** — no second BIOS, and the same `login:`.
39. One logs in as `root`. The other's screen shows the login happening: the echoed
    `login: root`, the masked password line, the banner, and the **same** shell
    prompt. Neither has to log in twice.
40. One types `ls -l /`. Both screens show the command line and its output, live.
41. `cd /etc` on one moves the prompt on **both**: the current directory belongs to
    the machine, not to a session.
42. One types `exit`. Both screens clear to `login:` at once.
43. The password is never on either screen: only `password: ****`.
44. One writes a file, the other `cat`s it. One machine, one filesystem.
45. One turns the computer off from the context menu: **both** windows close. Turn
    it back on and open it: the BIOS plays once, and the screen is empty — what the
    two of them typed is gone with the power.
46. One walks away: only that window closes, and the screen he was on is untouched
    for the one still standing there. He comes back: same screen.
47. The second client quits the game with his window open. The first one keeps
    typing; within a minute the sweep has forgotten the window that left.
48. **Split screen.** Two local players on one connection, both with a terminal open
    on the same computer. Both must show the same screen, and each must keep its own
    half-typed input line while the other types: answers are matched on the window's
    token, and only a change of prompt empties a line being typed.

## G — Chair

"Use computer" takes the chair when there is one. The rule is one line: a chair
standing on the **front square** and **looking at the screen** — a computer facing
S wants a chair facing N — is sat on with vanilla's own rest action on the way in.
Anything else and the player works standing, exactly as before. Turning the
computer on and off never sits anybody down.

49. **Chair in front, facing the computer.** Push a desk chair onto the front square
    with its back to the screen (so the seat looks at the monitor). Right-click the
    computer from across the room, "Use computer": the character walks to the front
    square, **sits down**, and the terminal opens on the seated character. He does
    not turn once more after sitting — the sit is the turn.
50. **Chair facing away.** Turn the same chair around (or use one facing left or
    right). "Use computer": the character walks up and works **standing**, with the
    usual loot animation. No sit, and the chair is not disturbed.
51. **No chair.** Empty front square: unchanged from step A3, standing.
52. **Already seated.** Rest on the chair by hand first (vanilla "Rest"), then
    "Use computer" from the seat. He must **not** sit a second time, stand up, or
    shuffle: the window just opens.
53. **Stand up while the window is open.** Press the sit/stand key. The rule is the
    square, not the posture: if standing up leaves him on the front square the
    window **stays open** and typing still works; the moment he steps off it, it
    closes (step 29). Closing the window with Escape or the close box must never
    stand him up — he stays in the chair.
54. **Too high, with a chair.** Chair on the front square, computer stacked out of
    reach (surface > 64). "Use computer" is greyed out with "This computer is too
    high to reach.", nothing is queued, and the character does not sit.
55. **Bed, sofa, stool.** Anything the game lets you "Rest" on counts as a chair if
    it sits on the front square and faces the screen. A sofa across the front square
    seats him; that is intended, not a bug.

## H — The editor

`edit <file>` is nano in the same green screen. Two keys and only two: **Escape** is
nano's `^X` and **Tab** is nano's `^O`, because the game hands a focused text box
exactly those two and nothing else — Ctrl+letter never arrives. The input surface is
the vanilla text box parked off the glass; everything you see is drawn by the window.

56. **A new file.** Log in as `admin`, `cd`, then `edit notes.txt`. The screen
    becomes: an inverted bar (dark text on dim green) reading ` EDIT
    /home/admin/notes.txt`, seventeen empty rows, an inverted bar reading
    ` Esc exit   Tab save `, and an empty bottom row. The block cursor is on the
    first row, first column, blinking. **No file was created yet**: leave with
    Escape and `ls` shows nothing.
57. **Typing.** Type two lines with Enter between them. The cursor moves as you
    type, Backspace deletes across the line break, the left/right/up/down arrows
    move it, Home and End go to the start and the end of the **line**. The moment
    the buffer differs from the file, the top bar shows `[modified]`, pinned to
    the right edge.
58. **Tab saves.** Press Tab. The bottom row says `Saved N bytes` with N the byte
    count, and `[modified]` goes away. Escape now leaves without asking. `cat
    notes.txt` shows what you typed.
59. **Escape asks.** `edit notes.txt` again, type a character, press Escape. The
    bottom row asks `Save modified buffer? (y/n)`. Press **Escape**: the question
    goes away and the buffer is exactly as it was, cursor included. Press Escape
    again, then **n**: you are back at the shell and `cat` shows the *old* text.
    Once more, then **y**: `Saved N bytes` flashes and you land back at the shell
    with the new text on disk. Any other key while the question is up leaves the
    question up.
60. **An existing file.** `edit /etc/motd` as `root`: the banner is there, on one
    row, and the bar names `/etc/motd`.
61. **A read-only file, as the admin.** As `root`, `chmod 444 /etc/motd`. As
    `admin`, `edit /etc/motd`: it opens with `[read-only]` in the bar instead of
    `[modified]`, and it stays `[read-only]` however much you type. Tab answers
    `Cannot save: permission denied` on the message line and writes nothing.
    Escape leaves at once, without asking.
62. **A file the admin may not read.** As `root`, `chmod 000 /etc/motd`. As
    `admin`, `edit /etc/motd` answers `edit: /etc/motd: permission denied` at the
    shell and no editor opens. `edit /root/x.txt` answers `permission denied`;
    `edit /nope/x.txt` answers `no such file`; `edit /etc` answers `is a
    directory`. Put the mode back (`chmod 644`).
63. **/root as root.** As `root`, `edit /root/secret.txt`, type something, Tab.
    Saved, and `ls -l /root` shows it owned by `root`.
64. **The 60 character line.** Hold a key until the line is full. At the 61st
    character nothing more appears and the bottom row says `Line too long: 60
    characters`. Enter still works, so the next line starts empty and takes 60 of
    its own. Backspace still works.
65. **The buffer ceiling.** Fill the buffer past 2000 characters (paste is the
    quick way: Ctrl+V pastes into the box). Typing stops at 2000 and the bottom
    row says `Buffer full: 2000 typed characters` — that is the game's own text
    box limit (`UITextBox2.textEntryMaxLength`, no setter), not the machine's.
    The machine's is 4096 bytes: a buffer that big says `Buffer full: 4096
    bytes`, and a save that would not fit the disk answers `Cannot save: disk
    full`.
66. **Walk away mid-edit.** With `[modified]` showing, walk off the front square.
    The window closes. Walk back, "Use computer": **the editor is still up**, on
    the same file, with the same text and `[modified]` still showing. No shell
    prompt in between, no BIOS. The cursor is back at the start of the buffer —
    the machine kept the text, not where your hands were.
67. **And the file was never touched.** From the state of 66, press Escape and
    **n**, then `cat` the file: the old contents. Only Tab and `y` write.
68. **Save and reload.** With an unsaved buffer up, save and quit to the main
    menu and reload. Open the computer: the editor is up with the buffer. The
    console is saved with the machine, and so is what is in the editor.
69. **Turning it off wipes it.** Turn the computer off with an unsaved buffer up
    and turn it on again: the BIOS plays and the screen is a bare `login:`. A
    machine that lost power lost the buffer, exactly like the screen.
70. **`exit` from the editor is not a thing.** There is no way to type a command
    while the editor is up: the shell is not there. Escape is how you leave.
    Logging out (`exit` at the shell afterwards) leaves nothing of the buffer.
71. **A second player watching (Host mode).** Two players at one computer. One
    types `edit notes.txt`. The **other's** screen becomes the same editor
    screen, and his bottom row says `Another user is editing`. He cannot type in
    it — his keystrokes do nothing — and his Escape closes his **window**, not
    the editor. The first one types; within five seconds the second one's screen
    shows the new text (and at once on every save and on every Escape).
72. **The keyboard changes hands.** The one editing walks away. The other one
    closes his window and opens it again: now **he** is the one editing, on the
    same buffer, and the bar and the cursor are his. An editor nobody could type
    in would be a dead machine.
73. **Two windows, one buffer, no fight.** From 71, while the second player is
    watching, the first one keeps typing: his own half-typed line is never
    replaced by anything the machine sends back.

## I — passwd

`passwd` asks its questions on the machine's own prompt line, and nothing typed at
one of them ever reaches the screen: the stored line is `Old password: ******`,
starred to the length of what was typed.

74. **Your own.** Log in as `admin` (empty password). `passwd`. The prompt becomes
    `Old password: ` and typing shows as `*`. Press Enter on the empty old
    password: `New password: `. Type `hunter2`, Enter: `Retype new password: `.
    Type `hunter2`, Enter: `passwd: password updated`, and the shell prompt is
    back. Three starred lines are on the screen, no cleartext anywhere.
75. **And it took.** `exit`, log in as `admin` with the empty password: `login
    incorrect`. Log in with `hunter2`: in.
76. **Wrong old password.** `passwd`, answer the old password wrong: `passwd:
    authentication failure`, straight back to the shell, nothing changed.
77. **Mismatch.** `passwd`, right old password, `abc` then `abd`: `passwd:
    passwords do not match`, back to the shell, nothing changed.
78. **Empty is a password.** `passwd`, right old password, Enter on both new
    prompts: `passwd: password updated`, and the account is open again. Log out
    and back in with Enter at the password prompt.
79. **root does not ask.** Log in as `root`. `passwd`: the **first** prompt is
    `New password: ` — root is asked for nobody's old password, its own included.
80. **root for somebody else.** As `root`, `passwd admin`: `New password: `,
    `Retype new password: `, `passwd: password updated`. Log out, log in as
    `admin` with it.
81. **The refusals.** As `root`, `passwd nobody` answers `passwd: no such user`.
    As `admin`, `passwd root` answers `passwd: permission denied`, and `passwd
    admin` (your own name) behaves exactly like a bare `passwd`.
82. **Walking away mid-question.** As `admin`, `passwd`, answer the old password,
    and at `New password: ` walk off the square. Come back: the machine is still
    asking `New password: `, because the question belongs to the machine. Answer
    it and it finishes.
83b. **`hash`, and what a stored password looks like.** `hash hunter2 abcdef`
    prints one line, `$cs1$abcdef$` followed by 32 hex digits, and prints the
    **same** line every time. `hash hunter2` (no salt) prints a different line
    every time — that is the salt doing its job. `hash hunter2 BAD` answers
    `hash: BAD: invalid salt` (a salt is lower-case letters and digits only).
    Nothing anywhere on the screen or in the save file holds a password in
    clear.
83c. **An old save still logs in.** Take a world saved before this rung (or hand-
    edit `password` in `gos_cerosec.bin` back to a plain word, if you are set up
    for that). Load it and log in with the password you had: it works, and from
    then on the field is a `$cs1$` line. The filesystem is untouched — a
    password field never costs a machine its disk.

83. **Logging out drops the question.** `passwd` again, and at `New password: `
    have the other player (or yourself, after answering) run `exit`: the screen
    clears to `login:` and nothing of the half-answered chain is left. Logging
    back in gives a shell prompt, not the question.

## What is not in this rung

- Devices, the network, the clock.
- Any sound beyond the typing click and the rung 1 toggle/boot sounds.
