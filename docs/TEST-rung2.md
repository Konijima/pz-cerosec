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

73b. **A file the shell made too wide.** As `admin`, `write wide.txt "` + 70
     `a`s + `"` (or `echo` a 70-character string into it). `edit wide.txt`: it
     opens, the row is on the glass cut to sixty, and the message line says
     `Line too long: 60 characters`. Now press **Backspace** ten times: each one
     **works** — the message stays until the row fits and then goes away, and
     Tab saves. Typing a character while it is still too long does nothing. An
     editor that refused the backspaces could never fix the file it opened.
73c. **The owner walks off while you watch.** Two players, one computer. A runs
     `edit notes.txt`; B opens his window and sees the editor with `Another user
     is editing`. A **walks away**. Within a minute (the sweep) B's screen stops
     saying it and B can type: the keyboard is his. He does not have to close
     and reopen the window.

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
83a. **Nothing in clear, mid-question.** As `admin`, run `passwd`, answer the old
     password, and at `New password: ` type one and press Enter. **Before**
     answering the retype, save and quit to the main menu, then reload and open
     the computer: the machine is still asking `Retype new password: `. Grep
     `gos_cerosec.bin` for the password you typed — it is not in there. Answer
     the retype and it completes.
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

## J — The keyboard you can hear, and the character typing

84. **A click per key.** Open the terminal and type a word slowly. There is one
    short click **per keystroke**, clearly audible, and the clicks are not all
    the same — four samples are picked from at random. Backspace and Delete
    click too. Hold a key down: a fast, even run, never a smear (nothing plays
    twice inside 40 ms).
85. **Enter is different.** Press Enter at the shell: a heavier, longer click
    than a letter. Same in the editor, where Enter opens a new row.
86. **Arrows.** Up and Down (history at the shell, the cursor in the editor)
    click. Left, Right, Home and End do not — the game gives a focused text box
    no callback for those, so there is nothing to hang a sound on.
87. **Nobody else hears it, and no zombie comes.** In Host mode, the second
    player standing at the same computer hears **nothing** while the first types
    (it is a local sound, like the vanilla map screen's). Type next to a horde
    behind a wall: nothing turns towards you.
88. **Volume.** Loud enough to hear over room noise without being startling. It
    follows the game's own sound sliders.

89. **The typing animation.** Open the terminal standing. Type: the character
    plays the loot animation — hands out at the keyboard — and **stops** about a
    second and a half after the last key. Read your screen without typing and he
    stands still, facing the monitor. Start typing again and the hands come back.
90. **Low and mid.** On a computer on the floor the animation is the crouched
    one, on a desk the standing one — the same rule the "Use computer" walk-in
    uses.
91. **Seated.** With a chair in front, sit down and open the terminal. Typing
    plays the animation **from the chair**; if it does not coexist with the
    seated pose in your build, he simply stays seated facing the screen — say so
    rather than forcing it.
92. **He stays busy while the window is up.** With the terminal open, right-click
    something across the room and queue an action. It does **not** run: the
    character is at the keyboard, and the queue is sequential. Close the
    terminal and he is free again. That is intended, not a bug.
93. **Closing lets go.** Escape (or the close box) and the character drops out of
    the animation at once, facing the screen, still standing or still seated. He
    is never left with his hands out.
94. **Walking away.** Step off the front square: the window closes and the
    animation goes with it, in the same frame.

## K — Losing the keyboard and getting it back

95. **Refocus turns him back.** Terminal open, standing, no chair. Click on the
    ground far away (do not walk off the square) or mouse-look elsewhere so the
    character faces another way. Now click **anywhere on the terminal**: he turns
    back to the screen, and typing reaches the glass again with the first letter.
96. **Refocus sits him back down.** Same with a chair in front. Open the terminal
    seated, click elsewhere to lose the keyboard, press the sit/stand key so he
    **stands up but stays on the front square** (the window stays open — the rule
    is the square, not the posture). Click the terminal: he sits back down on the
    chair and faces the screen. No walking, no shuffling.
97. **He is not sat down twice.** Repeat 96 but click the terminal several times
    in a row while he is standing up: exactly one sit. Click it again while he is
    already seated: nothing happens at all.
98. **Free while unfocused.** With the terminal open but the keyboard elsewhere,
    mouse-look around: the character is **not** yanked back to the screen every
    frame. The facing is only held while the window has the keyboard.
99. **No chair, no sit.** 96 with the chair removed: clicking the terminal turns
    him to the screen and nothing else.

## L — The prompt, and a line longer than the screen

100. **The home is a tilde.** Log in as `admin`: the prompt is
     `admin@ksp-<x>-<y>:~$ `. Not `~ome/admin`, which is what it used to say —
     that was a tail cut wearing the wrong marker.
101. **Under the home.** `mkdir docs`, `cd docs`: `admin@ksp-<x>-<y>:~/docs$ `.
102. **Only the home.** As `root`, `mkdir /home/adminx` and `chmod 777` it. Log in
     as `admin` and `cd /home/adminx`: the prompt reads the whole
     `/home/adminx`, **not** `~x`. A name that merely starts the same is not
     inside it.
103. **root at home.** As `root`: `root@ksp-<x>-<y>:~# `. `cd /`:
     `root@ksp-<x>-<y>:/# `.
104. **A path too long even then.** Make a deep tree (`mkdir /a`, `/a/b`, …,
     six or seven levels) and `cd` into the bottom. The prompt is cut at the
     **front** and marked `...`, keeps the last directory readable, and never
     grows past thirty characters. No tilde anywhere in it.

105. **The line wraps.** At the shell, type 200 characters without pressing
     Enter (hold a key). The line **wraps** onto the rows under it — four rows of
     sixty, the prompt eating into the first — and the block cursor walks onto
     the second, third and fourth rows with it. The scrollback above shrinks by
     as many rows as the input takes, so nothing is ever pushed off the glass.
106. **The cursor follows.** With a wrapped line up, press Left and Right: the
     cursor walks back over the wrap onto the row above and forward again. Home
     goes to the very start of the typed text (right after the prompt), End to
     the very end. Backspace at the start of a wrapped row deletes the last
     character of the row above and the line re-flows.
107. **The ceiling.** Keep typing past 240 characters: nothing more appears. That
     is the machine's line buffer, and it is the same 240 whatever the prompt.
108. **Enter echoes it wrapped.** Press Enter on a 200-character line (make it a
     `echo` of a long string so it is a real command). The echoed line lands in
     the scrollback broken at sixty, exactly where it was broken while you typed
     it, and the input line goes back to one row.
109. **Nothing shows of the box.** At no point is there a lavender caret, a grey
     border, a second copy of the text, or anything at all outside the green
     glass — the input box lives off the screen and only the window paints.
110. **Click to type still works.** With a wrapped line half-typed, click on the
     inventory, then click anywhere on the terminal. The half-typed line is
     still there, the first letter typed after the click appears, and the cursor
     is where you left it.

## M — Standing at the machine before sitting down at it

Where the character **stands** is what decides how he sits: vanilla's rest action
works the side of the chair out of his float position and nothing else
(`ISRestAction:calculateSitOnFurnitureDirection`). So the approach is never
skipped and never approximate — a walk to a computer aims at a **point** (the
seat, or the middle of the front square) and not at a square, and a character
already standing in that square is walked to that point all the same.

111. **Already on the square, facing away, with a chair.** Walk onto the front
     square by hand, turn so the character has his back to the screen (walk into
     the wall behind it), and stand at the **edge** of the tile. Right-click the
     computer, "Use computer": he **re-centres onto the seat**, turns, and sits
     **facing the screen** — the same sit as if he had walked in from across the
     room (step 49). Not sideways, not with his back to it.
112. **Already on the square, no chair.** Same, with the front square empty: he
     walks to the **middle** of the square, turns to the screen and plays the
     loot animation there. The terminal opens.
113. **Already on the square, toggling.** Same again with "Turn computer off/on":
     he re-centres and throws the switch. A toggle never sits anybody down and
     never aims at the seat.
114. **Already seated.** From the chair, "Use computer" again: he must **not**
     stand up, shuffle or re-centre (step 52 still holds).
115. **Stand up and come back.** With the window open, press the sit/stand key,
     step to the edge of the square, then click the terminal to get the keyboard
     back. He goes back to the seat point, sits, and ends up **facing the
     screen** — not sideways.
116. **From across the room.** Steps 49 to 51 must still behave exactly as they
     did: the walk in, the sit, the standing case.

## N — System files

The machine is its filesystem and nothing else now: the commands are files in
`/bin`, the accounts are lines in `/etc/passwd`, the name is `/etc/hostname`.
Root can take any of them away, because that is what root is — the protection is
that root has a password — and the way back is underneath the operating system,
at the BIOS.

117. **The commands are files.** Log in as `admin` and type `ls -l /bin`: one
     `-rwxr-xr-x root` line per command, twenty-one of them, sized by the
     description inside. `cat /bin/ls` prints `list a directory`. `help` is that
     directory listed, one command a line with its description.
118. **The accounts are a file, and they are root's.** As `admin`,
     `cat /etc/passwd` → `cat: /etc/passwd: permission denied`. Log out (`exit`),
     log in as `root`, `cat /etc/passwd`: two lines,
     `root:$cs1$…:/root:admin` and `admin:$cs1$…:/home/admin:user`, each wrapped
     across two rows because a line is longer than sixty columns. No password in
     clear anywhere in it.
119. **Taking a command away takes the command away.** As `root`,
     `rm /bin/ls`, then `ls` → `ls: command not found`. `pwd` still works.
     `help` no longer lists `ls`.
120. **Putting it back.** `write /bin/ls "list a directory"` then
     `chmod 755 /bin/ls`: `ls` works again. An executable is an ordinary file.
121. **A command nobody may run.** `chmod 644 /bin/ls`, `exit`, log in as
     `admin`: `ls` → `ls: permission denied`. Log back in as `root`: `ls` works
     — root walks through the bits here as everywhere. `chmod 755 /bin/ls` to
     put it back.
122. **Wiping the machine.** As `root`, first `mkdir /home/admin/work` and
     `write /home/admin/work/notes.txt "keep me"`. Then `rm -r /bin`. Now `ls`,
     `cat`, `pwd` are all `command not found`, and `help` says
     `help: no commands in /bin: the system is damaged.` with
     `help: switch the computer off and on to repair it.` under it. `exit` still
     works: those two are the only builtins.
123. **The BIOS finds nothing.** Close the window and open it again (`exit` at
     the login prompt is not needed; the window closing is enough). The screen
     ends on `No operating system found.` and `Restore system? (y/n)`. There is
     no `login:` prompt: there is nothing to log in to.
124. **Refusing the repair.** Answer `n`. The screen stays on
     `No operating system found.` with nothing asked under it. Press Enter: the
     question comes back. Anything that is not `y` or `n` asks again too.
125. **`exit` at the BIOS.** Type `exit` at the question, or press Escape: the
     window closes. A machine that cannot be repaired can still be walked away
     from.
126. **Taking the repair.** Open the window again, answer `y`. The screen says
     `Restoring system ...`, then the motd, then `login:`. Log in as `root`:
     `ls` works, `help` lists all twenty-one commands again, and
     `cat /home/admin/work/notes.txt` still says `keep me`. **Nothing under
     `/home` was touched.**
127. **A password survives the repair.** Do it again, but before wiping `/bin`
     run `passwd` and give root a real password. After the restore, root's own
     password is the one you set — the empty one does **not** get in. A repair
     puts the commands back; it does not hand the machine to whoever walks up.
128. **Editing the accounts by hand.** As `root`, `edit /etc/passwd`. Change
     `admin`'s third field from `/home/admin` to `/` and save with Tab, Escape.
     `exit`, log in as `admin`, `pwd` → `/`. The prompt says `admin@…:/$`. The
     parser is the truth. Put it back the same way.
129. **A line that is not a line.** As `root`, `edit /etc/passwd`, break the
     `admin` line (delete a `:`), save, `exit`. `admin` can no longer log in at
     all — the line is skipped, and the machine does not say which half of the
     login was wrong. `root` still gets in. Repair the line with the editor.
130. **Losing them all.** As `root`, `write /etc/passwd "rubbish"`, then close
     and reopen the window: `No operating system found.` again — a machine with
     no accounts is a machine nobody can use. `y` puts `root` and `admin` back,
     both open, and leaves `/home` alone.
131. **The name is a file.** As `root`, `hostname` prints `ksp-<x>-<y>`.
     `hostname ksp-front` writes it: `hostname` says the new name, and so does
     `cat /etc/hostname`. As `admin`, `hostname other` →
     `hostname: permission denied`.
132. **The name rule.** As `root`, `hostname Upper` → `hostname: Upper: invalid
     name`, and the same for `hostname -x` and for anything over sixteen
     characters. One to sixteen of `a-z`, `0-9` and `-`, never starting with a
     dash.
133. **The title follows the name.** After a successful `hostname ksp-front`,
     close the window and open it again: the title bar reads
     `CeroSec OS · ksp-front`, and so does every prompt. (The title is set when
     the window opens, so a rename shows on the next open, not under your
     fingers.)
134. **The motd is a file too.** As `root`, `edit /etc/motd`, put your own line
     in it, save. `exit` and log in again: your line is what greets you.

## O — shutdown, reboot, sudo, and Escape

**Before you start.** The four new commands are files in `/bin` and the sudoers
list is a file in `/etc`. A computer placed fresh has them; so does one you have
taken through a BIOS restore (steps 122-126); and so does a computer from an
older save, which is topped up the first time it is opened on this build — the
state carries the contents it was built with (`sysv`), and a machine behind on
that number gets the standard executables it is missing and an `/etc/sudoers` if
it has none, once. **Worth a look on an existing save:** open an old computer,
`help` should list `sudo`, `shutdown`, `reboot` and `restart`, and
`cat /etc/sudoers` as `root` should print the shipped list. After that the
top-up is inert: `rm /bin/ls` as `root` still survives a save and a reload --
save, quit to the menu, load again, and `ls` is still `command not found` until
you repair the machine from the BIOS. That is what steps 121-122 are about, and
the top-up must not undo it.

135. **The new commands are there.** Log in as `admin`, `help`: the list has
     `reboot`, `restart`, `shutdown` and `sudo` in it, one line each. `ls -l /bin`
     shows them owner `root`, mode `755`. `cat /bin/sudo` prints
     `run a command as root`.
136. **shutdown is root's.** As `admin`: `shutdown` → `shutdown: permission
     denied`. `reboot` → `reboot: permission denied`. `restart` → `restart:
     permission denied` (the refusal wears the name you typed, not the name of
     the order behind it). The machine stays on and the window stays open.
137. **shutdown.** `exit`, log in as `root`, type `shutdown`. The screen shows
     the line you typed, the machine goes dark — the sprite goes back to the
     unlit tile, you hear the toggle sound — and the terminal window closes on
     its own. Right-click: "Use computer" is gone, "Turn on computer" is back.
138. **What shutdown did not do.** Turn it on again, open it, log in as `root`:
     `ls /home/admin` and `cat /etc/passwd` are exactly as they were. A shutdown
     is a power cut, not a repair.
139. **reboot.** As `root`, `reboot`. The window **stays open**: the screen goes
     back to `CeroSec BIOS v1.03`, counts the memory, detects the drive, prints
     the motd and stops at `login:`. You hear the toggle sound and then the boot
     sound, and the sprite blinks off and on. Nobody is logged in any more; log
     in again and `ls /home/admin` still lists what was there.
140. **restart is reboot.** `restart` does exactly the same thing.
141. **reboot with a second player watching (Host mode).** Both players stand at
     the same computer with the terminal open (see section F). One of them, as
     `root`, types `reboot`. **Both** windows stay open and **both** replay the
     BIOS from the top and land on `login:` — the screen belongs to the machine,
     so a reboot is something everybody standing there watches. Neither window
     closes and neither is left on the old screen.
142. **reboot with no power.** Cut the power to the room (turn the generator
     off, or do it in a house off the grid at night) while the machine is on,
     then `reboot` before the minute sweep notices. The machine goes down and
     stays down, and the window closes. Turning it on again is refused until
     there is power.
143. **sudo, the refusal.** Log in as `admin`. `cat /etc/passwd` →
     `cat: /etc/passwd: permission denied`. Now `sudo cat /etc/passwd`: the
     machine asks `[sudo] password for admin: ` and what you type shows as
     stars. Type something wrong: `sudo: authentication failure`, one line, and
     you are back at the shell — there is no second try.
144. **sudo, the right password.** `sudo cat /etc/passwd` again and press Enter
     on the empty password (the shipped `admin` is open). The file is printed,
     hashes and all.
145. **sudo leaves your session alone.** `sudo whoami` → `root`. `whoami` →
     `admin`. `sudo cd /root`, then `pwd` → still `/home/admin`, and the prompt
     still says `admin@…:~$`. Nothing of root sticks to the glass.
146. **Not in the sudoers file.** As `root`, `edit /etc/sudoers`, delete the
     `admin` line, save with Tab and leave with Escape. `exit`, log in as
     `admin`, `sudo ls` → `admin is not in the sudoers file.` (Note the wording:
     it is real sudo's line and it does not begin with `sudo:`.) Put the line
     back the same way.
147. **NOPASSWD.** As `root`, `edit /etc/sudoers` and make the line read
     `admin NOPASSWD`. `exit`, log in as `admin`: `sudo whoami` prints `root`
     with no question asked. Put it back to plain `admin` afterwards.
148. **The file is root's.** As `admin`, `cat /etc/sudoers` →
     `cat: /etc/sudoers: permission denied`. `ls -l /etc` shows it
     `-r--r-----  root      sudoers`.
149. **sudo with no command.** `sudo` alone → `sudo: usage: sudo <command>
     [args]`. `sudo nosuch` → `nosuch: command not found`. `sudo sudo whoami`
     asks once and prints `root`.
150. **sudo passwd.** As `admin`, `passwd root` → `passwd: permission denied`.
     Now `sudo passwd root`: it asks for **your** password first, then
     `New password:` and `Retype new password:` — root's chain, so it never asks
     for root's old one. Set it, `exit`, and log in as `root` with the new
     password; the empty one no longer gets in. The prompt at the glass was
     `admin@…$` the whole way through.
151. **sudo edit.** As `admin`, `edit /etc/motd`: the bar says `[read-only]` and
     Tab says `Cannot save: permission denied`. Escape out. Now
     `sudo edit /etc/motd`: it asks for your password, then the same file opens
     **without** `[read-only]`. Change the line, Tab → `Saved N bytes`, Escape.
     `cat /etc/motd` shows the new text and `ls -l /etc` still shows it owner
     `root`. The buffer was root's from the moment it opened to the moment it
     saved.
152. **sudo shutdown, sudo reboot.** As `admin`, `sudo reboot`: it asks for your
     password, and then the machine goes down and comes back with the window
     open, exactly as step 139. Then `sudo shutdown` closes it, exactly as step
     137.
153. **Escape interrupts.** Log in as `admin`, type `passwd` and press **Escape**
     at `Old password:`. The line on the screen reads `Old password: ^C`, the
     shell prompt is back under it, and **the window is still open**. `whoami`
     still works and still says `admin`: what was dropped was the question, not
     the session.
154. **Escape at a sudo question.** `sudo cat /etc/passwd`, then Escape at
     `[sudo] password for admin: `. Same thing: `^C`, the prompt back, the
     window open, and not a line of the accounts file on the screen.
155. **Escape half way through a login.** `exit`. At `login:` type `admin` and
     press Enter, then Escape at `password:`. The screen reads `password: ^C`
     and the machine is back at `login:` with the name forgotten.
156. **Escape when nothing is going on.** At an idle `login:` prompt, or at an
     idle shell prompt, Escape closes the window as it always has. Open it again:
     the session is exactly where you left it.
157. **Escape in the editor is still the editor's.** `edit notes.txt`, type
     something, Escape → `Save modified buffer? (y/n)`, not a closed window and
     not a `^C`.
158. **Escape at the BIOS still closes.** Wipe the machine (`rm -r /bin` as
     `root`), reopen the window to get `Restore system? (y/n) `, press Escape:
     the window closes, as in step 125. There is nothing behind that question to
     go back to.
159. **The interrupt is the machine's (Host mode).** Two players at one computer.
     One types `passwd` and presses Escape. **Both** screens show
     `Old password: ^C` and both are back at the shell prompt — the same screen,
     as everywhere else.

## What is not in this rung

- Devices, the network, the clock.
- Any sound beyond the typing click and the rung 1 toggle/boot sounds.
