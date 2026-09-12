-- CeroSec OS, Volume 1: the User's Guide.
--
-- The first of the three books CeroSec Systems shipped with a machine in 1993.
-- This one is for somebody who has never sat in front of one of these: it
-- teaches the screen, the prompt, the disk, the editor, the modes and the small
-- tools, and it stops where the second volume starts (accounts, groups, sudo,
-- the system files, the devices) and the third one after that.
--
-- The shape of a page is the reader's, not this file's: plain ASCII, "\n\n"
-- between paragraphs (a single "\n" is a soft break the reader reflows), a line
-- beginning with two spaces is a screen and is kept monospace and so must fit
-- the machine's own sixty columns, and no page runs past a thousand characters.
-- tests/manual_test.lua checks every one of those, and checks the transcripts
-- and the reference card against the engine itself.
--
-- The cover is NOT written here. The reader stamps it from the engine's own
-- version number once the core is loaded; nothing in this file may name a
-- version, and nothing in this file may touch CeroSecOS at load time -- the
-- game loads shared/cerosec/ ahead of shared/cerosec/os/.

-- Both lines are written defensively so this file does not care whether the
-- legacy book has loaded yet. Note the one thing that WOULD break it: the legacy
-- CeroSecManual.lua assigns a fresh table to CeroSecManual rather than adding to
-- one, so a load order that put it after this file would wipe `volumes`. The game
-- sorts shared/cerosec/cerosecmanual.lua ahead of cerosecmanualuser.lua, so it
-- does not today; a file named between the two is the thing to watch for.
CeroSecManual = CeroSecManual or {}
CeroSecManual.volumes = CeroSecManual.volumes or {}

CeroSecManual.volumes[1] = {
	id = "user",
	title = nil,
	name = "User's Guide",
	edition = "First Edition, 1993",
	chapters = {

		{ title = "1. Your first day", pages = {

[[Welcome, and thank you for reading the book instead of guessing.

CeroSec Systems of Louisville, Kentucky has been putting these small
computers on office desks since 1989. This volume assumes you have never
touched one. It does not assume you are slow. There is a difference, and
we have tried to keep it in mind on every page.

A computer like this one does not have pictures on its screen and it does
not have a mouse to point with. It has a keyboard, and it has a green
screen with words on it, and everything you will ever ask it you will ask
by typing a short word and pressing Enter. That is the whole trick. Once
you believe it, the rest of this book is just vocabulary.

Read it in order once, with the machine in front of you, and do the "Try
it" boxes as you go. Then leave the book on the desk. That is where it
lives.]],

[[How to read this book.

A line indented two spaces is the screen. It is either something you
type or something the machine typed back:

  admin@ksp-04-11:~$ whoami
  admin

The first of those two lines you typed; only the part after the dollar
sign. The second one the machine printed. We will always show both, so
you can tell whether you got it right.

Square brackets in a command's description mean "this part is optional".
Never type the brackets themselves. Capital letters matter: LS is not ls,
and the machine only knows the small one.

Everything stated here as a fact was checked against a running machine.
Where CeroSec Systems does not know something, the book says so, plainly.
We would rather look ignorant on one page than have you trust us on the
next.]],

[[What the thing actually is.

A beige tower, a monitor on top of it, and a cable into the wall. That is
all. There is no battery in it and there is nowhere to put a floppy disk:
everything you save lives on the small drive inside, and the drive holds
thirty-two kilobytes. That is not a lot, and you will meet the number;
chapter 3 is where we deal with it properly.

It runs on the building's electricity and nothing else. No power in the
room means no computer, and no amount of patience will change that. The
screen glows a dim blue-green whenever the machine is on, day or night,
which is how you spot a live office from across the street. It is a
monitor's glow, not a lamp: you cannot read a newspaper by it.

Turning it on and off is a choice at the machine itself, the same way you
would reach round and flip its switch.]],

[[Getting to it.

The screen faces one way out of the desk, and that one square in front of
it is the only place you can work from. These were built for a desk
against a wall, not an island you walk around. If nothing can stand on
that square, because it is a wall, another piece of furniture, or simply
nowhere you can walk to, the machine will refuse you and walking round
the back will not help.

Height matters as well. On the floor is fine. On a desk, a counter or a
table is fine. Stacked much higher than that and the machine says it is
too high to reach, and stays that way until somebody brings it down.

A chair helps but is not required. Put one on that square with its seat
towards the screen and you will sit down on your way in. Turned the wrong
way, or missing, and you work standing up. The machine does not care
either way.]],

[[Turning it on, and the four lines that follow.

The first person to look at a freshly powered machine watches it test
itself, once. Not once per person: once per power-on. Four lines, typed
out over a couple of seconds.

  CeroSec BIOS 1.0 -- (c) 1993 CeroSec Systems
  Memory test: 640K OK
  Detecting drives ... hda 32K
  Booting from hda ...

Line one is the firmware, the small permanent program that wakes the
machine up. It has its own version number and it is not the operating
system. Line two says the memory answered. Line three says it found the
drive, which it calls hda, and that the drive holds 32K. Line four says
it is loading the operating system off that drive.

Then a greeting line naming this system, and then the machine asks who
you are. If your machine is on a wire it prints one line more, about the
wire; Volume 3 is the book for that.]],

[[Saying who you are.

  login: admin
  password:
  admin@ksp-04-11:~$

Type a name, press Enter, and the machine asks for a password. Every
machine ships with two accounts. admin is the ordinary one and is the one
you want. root can do absolutely anything to the machine, including break
it, and Volume 2 is where we hand you that key. Neither has a password to
begin with, so at password: you simply press Enter again.

Get either half wrong and the machine says only "login incorrect" and
starts over. It never tells you which half was wrong. That is deliberate:
a stranger typing names at your keyboard should learn nothing, not even
whether the name he tried exists.

Try it. Type admin, Enter, then Enter again at password:. You are in when
you see a line ending in a dollar sign.]],

[[The screen belongs to the machine, not to you.

This is the single most important sentence in the book, so here it is
again with the reason attached. When you walk away from this computer,
everything on the glass stays on the glass, and you stay logged in. The
next person to sit down does not get a login: prompt. He gets your
session, your files, your account. Closing the window changes nothing.
Walking off the square changes nothing.

One word fixes it:

  admin@ksp-04-11:~$ exit
  login:

Type exit before you leave. It wipes the screen and hands the machine
back to the login: prompt. Get in the habit now, on the first day, while
there is nothing on the machine worth stealing.

Classic mistake. You walk away, come back an hour later, and the screen
is blank and dark. You did not break it. The building lost power, which
turns the machine off and clears the glass. Check the power first, always,
before you suspect the computer.]],

		} },

		{ title = "2. Talking to the machine", pages = {

[[The prompt, read like a sentence.

  admin@ksp-04-11:~$

That short line is the machine telling you four things before you have
typed anything at all.

admin is who is logged in. The at-sign means "at", the way it does in an
address. ksp-04-11 is this machine's own name, printed so that you know
which computer you are talking to when you have sat at three of them
today. After the colon is where you are standing in the machine's files:
the squiggle stands for your own private folder, and chapter 3 is all
about that. The dollar sign at the end means "your turn, I am listening".

A pound sign instead of a dollar sign means the account logged in is
marked as an administrator. Today that mark is cosmetic. Volume 2 explains
what actually opens locked doors.]],

[[Typing, and Enter.

You type after the dollar sign. Nothing happens while you type: the
machine is not reading over your shoulder. It only reads the line when
you press Enter, and then it does the whole line at once. So if you see a
typo before you press Enter, Backspace over it and nobody will ever know.

Two words to start with. whoami says who is logged in, which is useful
when you sat down at a machine somebody else was using. clear wipes the
screen and gives you a clean one, which is useful surprisingly often.

Try it.

  admin@ksp-04-11:~$ whoami
  admin
  admin@ksp-04-11:~$ clear

clear prints nothing. That is the point of it. The screen simply goes
empty with the prompt at the top, and nothing on the disk was touched.]],

[[Asking the machine what it knows.

You will not remember the commands in this book, and you are not supposed
to. The machine carries its own index.

help lists every command it has, one line each, with a few words about
what it does. It is a long list and it scrolls.

man, followed by a command's name, prints that one command's line plus
the exact shape of the command: which parts it wants, which are optional.

Try it.

  admin@ksp-04-11:~$ man ls
  ls - list a directory
  usage: ls [-1laACF] [path]

That "usage:" line is worth learning to read. ls is the word you type.
Square brackets mean optional. So ls on its own is legal, ls -l is legal,
and ls -l /etc is legal. Chapter 11 of this volume is nothing but a page
of those lines, for the day you need one fast.]],

[[Three keys that save your fingers.

Up and Down walk through the lines you have already typed. Press Up and
your last command comes back, ready to run again or to edit. Press it
twice for the one before that. This is not a small convenience: a long
command typed once is a long command you never need to type again.

Tab finishes a word for you. Type the first few letters of a command or a
file and press Tab. If exactly one thing matches, the machine fills the
rest in. If several match, it fills in as far as they all agree and stops.
Press Tab a second time on the same word and it lists them in columns.

  admin@ksp-04-11:~$ cat note
  note2.txt  notes.txt
  admin@ksp-04-11:~$ cat note

The mouse wheel scrolls the screen back up, three lines a notch, so you
can read something that has already scrolled away. The wheel is the only
way up: this terminal has no page keys.]],

[[Escape, and how to stop something.

Escape does one of two things, and the machine decides which.

If the machine is sitting idle at a dollar-sign prompt, Escape simply
closes the window and lets go of your keyboard. Nothing is lost, nothing
is logged out, and the screen is exactly as you left it when you come
back.

If the machine is in the middle of asking you something, or in the middle
of running something, Escape is the old typewriter "cancel". It prints ^C
on the line and puts the question back at its beginning, or stops what was
running. It does not close the window, because you were in the middle of
something and closing on you would be rude.

Worth knowing while the window is open: your keystrokes go to the
computer and nowhere else. Your hands are on its keyboard. You will not
walk, open a bag or swing anything until Escape hands them back.]],

[[When the machine says "command not found".

  admin@ksp-04-11:~$ sl
  sl: command not found

That line is not an insult and it is not a fault. It means exactly one
thing: no command by that name exists on this machine. The machine looked,
found nothing, and said so.

Three typos cause nearly all of them.

A misspelling. sl for ls, whoiam for whoami. Press Up, fix the letters,
press Enter.

A capital letter. LS, Ls and lS are three names the machine has never
heard of. Everything here is lower case.

A command from somebody else's computer. This machine has its own list,
and help is that list. If help does not print it, it is not here, and no
amount of spelling it correctly will conjure it.

Classic mistake. You type a command, nothing happens, no error appears,
and you conclude the machine is stuck. Look again: you almost certainly
forgot Enter. The machine has not read your line yet.]],

		} },

		{ title = "3. Files and folders", pages = {

[[A drawer inside a drawer inside a drawer.

Everything the machine keeps is a file, and files live in folders, which
this machine calls directories. Directories live inside other directories,
and at the very top is one that holds all of them. It has no name: it is
written as a single slash, and everyone calls it the root.

Six drawers there, on every machine.

  admin@ksp-04-11:~$ ls /
  bin   dev   etc   home  root  var

bin holds the commands, every one of them a real file. dev, etc, root and
var belong to the machine and its administrator; Volume 2 opens them. home
holds one directory per ordinary account, and yours is /home/admin.

pwd prints where you are standing. ls lists what is there. Try both.

  admin@ksp-04-11:~$ pwd
  /home/admin
  admin@ksp-04-11:~$ ls
  admin@ksp-04-11:~$

ls printed nothing, the right answer on a fresh machine: your directory is
empty. The squiggle in the prompt stands for that directory, written there
instead of /home/admin to keep the line short.]],

[[Moving about.

cd changes which directory you are standing in. Give it a name to go
there, give it two dots to go up one, and give it nothing at all to go
straight home from anywhere. Try the whole round trip.

  admin@ksp-04-11:~$ cd /etc
  admin@ksp-04-11:/etc$ pwd
  /etc
  admin@ksp-04-11:/etc$ cd ..
  admin@ksp-04-11:/$ cd
  admin@ksp-04-11:~$

Watch the prompt as you go: it changes with you, which is why it tells
you where you are.

A name starting with a slash is measured from the very top, and works from
anywhere: /etc is /etc wherever you happen to be standing. A name without
one is measured from where you are now. So if you are in /home/admin, then
notes and /home/admin/notes are the same place. The long form always
works; the short form is less typing.

The squiggle works as a name too. cd ~ goes home, and ~/notes is your own
notes directory however far away you have wandered.]],

[[Making things, and reading them.

Four commands, and then you have a working office.

mkdir makes a directory. touch makes an empty file, or, on a file that
already exists, just moves its date to now. cat prints a file's contents
on the screen. And a greater-than sign after a command sends what the
command would have printed into a file instead.

Try it.

  admin@ksp-04-11:~$ mkdir notes
  admin@ksp-04-11:~$ echo hello > note.txt
  admin@ksp-04-11:~$ cat note.txt
  hello

echo just prints back whatever you give it, which makes it the simplest
way to put one line into a file. One greater-than sign replaces the whole
file. Two of them add to the end instead:

  admin@ksp-04-11:~$ echo again >> note.txt
  admin@ksp-04-11:~$ cat note.txt
  hello
  again

Wrap words in double quotes when your text has a space in it.]],

[[Copying, moving, and throwing away.

cp copies a file, mv renames or moves one, and rm destroys one. All three
take the thing first and where it is going second.

Try it, with ls after every line so you can see what changed.

  admin@ksp-04-11:~$ cp note.txt spare.txt
  admin@ksp-04-11:~$ mv spare.txt old.txt
  admin@ksp-04-11:~$ rm old.txt

A directory is not a file, and none of the three will take a whole
directory without being told twice. cp wants -r for "and everything
inside it". rm wants -r for the same reason, and refuses outright without
it:

  admin@ksp-04-11:~$ rm notes
  rm: notes: is a directory
  admin@ksp-04-11:~$ rm -r notes

Read that second line twice before you press Enter. rm -r does not ask,
it does not confirm, and there is no way to get any of it back. There is
no wastebasket on this machine. CeroSec Systems has lost more customer
data to a hurried rm -r than to every power cut in Kentucky.]],

[[Looking at a file properly: ls -l.

A letter after a command, with a dash in front of it, changes how the
command behaves. Those are called flags. ls -l is the one you will use
daily: one file per line, with everything the machine knows about it. Try
it now.

  admin@ksp-04-11:~$ ls -l
  -rw-r--r--  admin  admin      11  Sep  8 13:45  note.txt

Six columns, left to right.

The first is the kind and the permissions: a dash to start means an
ordinary file, a d means a directory, and the nine letters after it are
chapter 5's whole subject.

The second is the owner. The third is the group. The fourth is the size in
bytes, or, for a directory, how many things are inside it. The fifth is
when it last changed. The last is the name.

Two more flags. ls -F puts a slash after every directory name so you can
tell them apart at a glance. ls -1 puts one plain name per line.]],

[[Two honest warnings about that listing.

The date column never prints a year. It prints a month, a day, and a time,
and nothing else, however old the file is. A file showing

  Jan  1 00:00

is not from New Year's Day. That is what the machine prints when a file
has no date recorded at all, which is normal for the commands in /bin.

And the name column is twelve characters wide. A longer name is shown cut
short there, with a squiggle standing in for the part that did not fit. A
file called averyveryverylongname.txt appears at the end of its ls -l line
as

  averyveryve~

(A whole ls -l line is exactly sixty characters, which is the screen, so
this book cannot show you one with the two-space indent it uses for a
screen. That is the book's problem, not the machine's.)

The file is not renamed and nothing is wrong. Only the listing was trimmed
to fit. Plain ls, with no -l, prints the full name. Keep your names short
and you will never meet this at all.]],

[[Files that hide.

A name beginning with a dot is hidden from ls. That is the whole rule, and
the machine invented it so that its own housekeeping files would not
clutter up your listings. Nothing else about such a file is special: cat
reads it, the editor opens it, rm deletes it.

Two flags show them. ls -a shows everything, including two entries every
single directory has: a single dot, meaning "this directory", and two
dots, meaning "the one above". ls -A shows everything except those two,
which is usually what you actually wanted.

  admin@ksp-04-11:~$ ls
  note.txt
  admin@ksp-04-11:~$ ls -a
  .         ..        .profile  note.txt

Flags combine. ls -la, ls -lA and ls -aF all read as you would hope, and
so does ls -al: the order does not matter.

Classic mistake. "My file is gone." Try ls -a first. A file you named
.budget is not gone; it is hiding, exactly as instructed.]],

[[The two ceilings, and what they sound like.

This is a small machine and it is honest about it.

One file may hold 4096 bytes. That is about a page and a half of typing.
Past it, the machine says "file too large" and writes nothing.

The whole drive holds 32768 bytes and 256 files and directories, whichever
runs out first. Past either, every command that writes says "disk full".

And one directory may hold 96 entries. Past that, "directory full".

df shows you where you stand, as two lines:

  admin@ksp-04-11:~$ df
  Filesystem   Size   Used  Avail  Use%
  hda         32768   2075  30693    7%
  nodes         256     86    170   34%

The first line is bytes, the second is the count of files and directories.
When either Avail column reaches nothing, you delete something or you stop
writing. Type df before a long editing session, not after.]],

		} },

		{ title = "4. Writing with the editor", pages = {

[[Opening the editor.

echo and a greater-than sign are fine for one line. For a real note you
want the editor, which is a command called edit with a file name after it.

  admin@ksp-04-11:~$ edit notes.txt

The whole screen changes. The shell is gone; you are in the editor now,
and nothing you type is a command any more. You get four things:

A bar across the top naming the file you are in.

Seventeen lines of space to write in, with a blinking block where the next
letter will land.

A bar across the bottom naming the only two keys that do anything:

   Esc exit   Tab save

And, under that, a message line, which is blank until the machine has
something to tell you.

Nothing is written to the disk when you open it. edit on a name that does
not exist yet gives you a blank page and creates no file at all until you
save.]],

[[Typing in it.

Type. Try a couple of lines. Enter starts a new one, and Backspace rubs
out, rubbing back over a line break as happily as within a line. The four
arrow keys, Home and End move the block about without changing anything.

That is genuinely all of it. There are no other keys, and there is no
menu. If you have used a bigger machine and your fingers want a Control
key combination, they will be disappointed: this terminal is handed
exactly two keys beyond ordinary letters, and those two are Escape and
Tab. Which is why Tab, of all things, is the one that saves.

The moment what is on the screen differs from what is on the disk, the top
bar grows a mark, pinned to its right-hand edge:

   EDIT  /home/admin/notes.txt        [modified]

The real bar is sixty characters wide and this book's indent is not, so the
gap above is shorter than the one on your screen. The mark is your warning
light. While it is lit, your work exists only on the glass.]],

[[Saving, and leaving.

Tab saves. The message line says so and the [modified] mark goes out:

  Saved 34 bytes

Escape leaves. If there is nothing unsaved it leaves at once. If there is,
it asks first, on the message line:

  Save modified buffer? (y/n)

y saves and leaves. n leaves and throws your changes away. Escape again
backs out of the question entirely and puts you back in the editor with
your text untouched. Any other key does nothing at all, rather than guess
which of three things you meant.

Try it. Open a file, type one word, press Escape, and read the question.
Then press Escape again to come back. Knowing you can back out of that
question is worth more than knowing either answer.]],

[[Three ceilings the message line will tell you about.

A line stops at sixty characters, because the screen is sixty characters
wide. Keep typing and the machine simply stops taking letters and says

  Line too long: 60 characters

Backspace until it is shorter, or press Enter and carry on below. Nothing
was lost; the keystrokes were refused, not eaten.

The file stops at 4096 bytes, the ceiling from chapter 3, and says

  Buffer full: 4096 bytes

And the typing box itself stops at two thousand characters in one sitting.
A save that will not fit in what is left of the drive answers "Cannot save:
disk full" and writes nothing at all, so nothing is half-written.

A file already bigger than a ceiling still opens and still edits. Only new
growth is refused.]],

[[Two situations worth meeting on purpose.

A file you may read but not change opens with [read-only] in the top bar
instead of [modified]. You can move around it and read it all day. Tab
answers "Cannot save: permission denied" and touches nothing. Escape
leaves at once with no question, because nothing unsaved is yours. A file
you may not even read never opens: the shell refuses it before the editor
starts.

And walking away mid-edit costs you nothing. The buffer, your text, the
[modified] mark, even an unanswered save question are all exactly as you
left them when you come back. Only the cursor goes back to the start. The
editor is the machine's, not your window's.

Classic mistake. You type a page, press Escape, press n out of habit
because you press n at every question, and the page is gone. Read the
question. It is the one place on this machine where the wrong single
keystroke destroys work.]],

		} },

		{ title = "5. Who may do what", pages = {

[[Three kinds of person, for every single file.

The machine does not really know about people. For any one file, it knows
about three roles, and it decides which one you are.

The owner. One account, usually whoever made the file.

The group. A named list of accounts, for sharing between a few people.

Everybody else. Everyone who is neither of the above.

For each of those three, the file separately records whether they may read
it, write it, and run it. Nine facts in all, and ls -l prints the lot. Try
it, on a file of your own.

  admin@ksp-04-11:~$ ls -l note.txt
  -rw-r-----  admin  users      11  Sep  8 13:45  note.txt

admin owns it, and its group is called users. Now we read the letters.]],

[[Reading -rw-r----- out loud.

Ten characters. Chop the first one off, then read the rest in threes.

The first character is the kind: a dash for an ordinary file, a d for a
directory, an l for a link.

  -  rw-  r--  ---

The first three are the owner's: r means may read, w means may write, and
a dash in a slot means may not. So the owner reads and writes.

The next three are the group's. r and two dashes: anyone in group users
may read it and may not change it.

The last three are everybody else's. Three dashes: nothing at all. They
cannot read it and cannot even learn what is inside it.

The third letter in a set is x, for may run this as a command. On a
directory it means something different and more important: may step inside
it at all.]],

[[The same nine facts as three digits.

You will see modes written as three numbers, because that is how you set
them. Within a set, read is worth 4, write is worth 2, and x is worth 1,
and you add up the ones you want.

So rw- is 4 plus 2, which is 6. r-- is 4. --- is 0. Our file is 640.

chmod sets it. The number first, then the file. Try it, and watch the
letters change to match.

  admin@ksp-04-11:~$ chmod 640 note.txt
  admin@ksp-04-11:~$ ls -l note.txt
  -rw-r-----  admin  users      11  Sep  8 13:45  note.txt

Four worth memorising. 600 is private: only you, and nobody else at all.
644 is the usual note: you write it, anybody reads it. 755 is a command or
a directory: you change it, anybody uses it. 700 is a private directory.

All three digits are read, and exactly one of them decides. Do you own it?
Then the first digit is yours and the other two are none of your business.
Are you in its group? The middle one. Neither? The last one.]],

[[chmod in letters, which is what you will actually type.

Doing arithmetic on a file you only want to change slightly is silly, so
chmod also takes letters. A clause is who, then what to do, then which.

Who: u for the owner (u for user), g for the group, o for everybody else
(o for other), a for all three. Leave it out and it means all three.

What: + to add, - to take away, = to set exactly this and nothing more.

Which: any of r, w and x. Try it, reading ls -l after each one.

  admin@ksp-04-11:~$ chmod u+x backup.sh
  admin@ksp-04-11:~$ chmod go-r note.txt
  admin@ksp-04-11:~$ chmod a=r readme
  admin@ksp-04-11:~$ chmod ug+rw,o-rwx private

Commas separate clauses, applied left to right to the mode the file wears
right now. That is the whole difference: chmod u+x adds one thing and
leaves the rest, chmod 744 declares all nine at once.

u+ and u- with no letters after them are not clauses and answer "invalid
mode", as does anything that is neither three digits nor this.]],

[[Owner and group, in one paragraph.

chown hands a file to a different account by name, and chgrp hands it to a
different group. Both are the owner's to do and root's to do, and both
answer "permission denied" to anybody else, on the file itself, before any
digit is looked at.

Try it. There is a group called users on every machine, so this one works
on a fresh one:

  admin@ksp-04-11:~$ chgrp users note.txt
  admin@ksp-04-11:~$ ls -l note.txt
  -rw-r-----  admin  users      11  Sep  8 13:45  note.txt

The third column moved and nothing else did. Groups themselves, and who is
in them, are Volume 2's business; all you need here is that a file has one
and that the middle digit belongs to it.]],

[["permission denied", explained kindly.

You will see this line a great deal, and it does not mean you did anything
wrong.

  admin@ksp-04-11:~$ cd /root
  cd: /root: permission denied

Read it in three pieces, which is how every refusal on this machine is
built. cd is the command that refused. /root is exactly what it refused
about. permission denied is why.

It means the account you are logged in as is not allowed to do that to
that thing. That is all. The file is there, the command works, you are
simply not the right person for it. Nothing broke and nothing needs
repairing.

Three ordinary reasons. It belongs to root, like /root. It belongs to
another survivor, in his own home. Or it is yours and you took the
permission away yourself, in which case chmod gives it back.

Classic mistake. Assuming denied means broken and reaching for root to
force it. Ask first whether you needed that file at all. Most of the time
the answer is no, and Volume 2 is a shorter book than it looks.]],

		} },

		{ title = "6. Your account", pages = {

[[Who the machine thinks you are.

Three commands, no flags, nothing to remember.

whoami prints the account logged in right now. id prints that plus the
groups it belongs to. groups prints just the groups.

Try it.

  admin@ksp-04-11:~$ whoami
  admin
  admin@ksp-04-11:~$ id
  uid=admin flag=user groups=admin,sudo,users
  admin@ksp-04-11:~$ groups
  admin sudo users

Every account is automatically in a group of its own name, which is why
admin appears in its own list. The others are lists somebody put it on.

flag=user is the cosmetic administrator mark from chapter 2: user means
the prompt ends in a dollar sign, admin means it ends in a pound sign. It
decides nothing else.

Try id on a machine somebody else has been using. It is the quickest way
to find out whose session you just sat down in.]],

[[Giving yourself a password.

Your account ships with no password, which means anybody who sits down
can be you. Fix that on your first day.

passwd asks three questions, in this order, and every answer you type
appears as stars and never as letters. Try it now.

  admin@ksp-04-11:~$ passwd
  Old password:
  New password:
  Retype new password:
  passwd: password updated

Old password: proves you are you. On a fresh account there is none, so
press Enter. New password: is the new one. Retype new password: is the
same one again, to catch a typo before it becomes the only key to your own
account.

Get the old one wrong and it says "passwd: authentication failure". Type
the new one two different ways and it says "passwd: passwords do not
match". Either way nothing changed and you simply start again.]],

[[Two facts about that password worth trusting.

It is never written down anywhere in readable form, not even for the
moment between the second and third question. The machine keeps a
scrambled version and compares scrambles. Nobody, including root, can read
your password back out of this computer.

Which is the bad news as well. Nobody can recover it for you either. If
you forget it, the account is shut to you, and the only way back is root
setting a new one.

So write it on paper and put the paper somewhere the machine is not. In
1993 that is not an embarrassing suggestion; it is the suggestion. A
password you cannot remember protects your notes from you.

Classic mistake. Changing a password, walking away without testing it, and
discovering the typo tomorrow. Type exit, log back in with the new
password, and then walk away.]],

[[Becoming somebody else for a minute.

su switches the account at this same screen without logging anybody out.
Name who you want to become, and answer their password. Try it, and then
come straight back out again.

  admin@ksp-04-11:~$ su root
  Password:
  root@ksp-04-11:~#

Look at the end of that prompt. The pound sign is your reminder that you
are root now and that nothing will stop you doing anything, including
deleting the machine's own commands. Do what you came for, and get out.

exit comes back to who you were, one step at a time:

  root@ksp-04-11:~# exit
  admin@ksp-04-11:~$

You can stack four accounts deep. A fifth answers "su: too many levels".
And note that exit at the bottom of the stack is the exit from chapter 1,
which logs the machine out entirely. That is the correct thing to type
when you leave, so type it twice if you have to.]],

		} },

		{ title = "7. The clock and the small tools", pages = {

[[What time is it.

date prints the day and the hour, read off the same clock as the world
outside the window. There is no separate clock inside the machine to drift
out of step.

  admin@ksp-04-11:~$ date
  Mon Sep  8 13:45:00 2025

Try it. Then give it a plus sign and a format, and it prints only the
pieces you asked for. A piece is a percent sign and a letter: %Y is the
year, %m the month, %d the day.

  admin@ksp-04-11:~$ date +%Y-%m-%d
  2025-09-08

And %s is the whole clock as one plain number, counting seconds:

  admin@ksp-04-11:~$ date +%s
  1757339100

That number looks useless and is not: it is the only form of the time you
can do arithmetic on, and it is the same number every file's date is kept
as underneath. Volume 3 uses it. You can forget it until then.]],

[[Waiting on purpose.

sleep does nothing, for as many seconds as you tell it, and then finishes.
Try it.

  admin@ksp-04-11:~$ sleep 5

Five seconds of nothing, and then your prompt comes back. On its own that
is a curiosity. Written into a longer instruction it is how you space
things out in time, which is Volume 3's subject.

While it waits, the machine is busy and the prompt is not yours. That is
the moment to try Escape from chapter 2: it prints ^C and takes the sleep
away, rather than closing the window. Worth doing once, deliberately, so
that the first time you meet a command that will not finish you already
know the key.]],

[[Reading tools: a file is often too long to just cat.

Four small commands do nothing but look at a file for you.

head prints the first ten lines, or however many -n asks for. tail prints
the last ones the same way. wc counts: lines, then words, then bytes, in
that order, with the name after. grep prints only the lines that hold the
text you name.

Try it on the note from chapter 3.

  admin@ksp-04-11:~$ wc note.txt
       2      2     11 note.txt
  admin@ksp-04-11:~$ head -n 1 note.txt
  hello
  admin@ksp-04-11:~$ grep hello note.txt
  hello

grep looks for plain text and nothing cleverer: a period means a period
here. Its useful flags are -i to ignore capitals, -n to number the lines
it prints, -c to print how many it found instead of printing them, and -v
to print the lines that do NOT hold the text.]],

[[Putting lines in order.

sort prints its input in order. uniq drops a line that is identical to the
one immediately before it, which is why it is nearly always the command
right after sort.

Try it on a file with a few names in it.

  admin@ksp-04-11:~$ sort names
  admin@ksp-04-11:~$ sort -n sizes
  admin@ksp-04-11:~$ sort -r names

Plain sort compares characters, which puts 100 before 20 and every capital
letter before every small one. That surprises everybody once. -n reads the
number at the front of each line and compares that instead, which is what
you meant. -r turns either of them round. -u prints each line only once.

uniq takes -c to put a count in front of each line it keeps. Remember that
it only ever compares neighbours: on an unsorted file it will find almost
nothing, and will not be wrong to.]],

[[Plumbing: joining two commands with a pipe.

Here is the idea the whole system is built on. The upright bar takes what
the command on its left printed and hands it straight to the command on
its right, instead of to the screen. Nothing is saved, nothing is named.
It is a length of pipe between two taps.

Three friendly examples. Try all three.

How many commands does this machine have?

  admin@ksp-04-11:~$ ls /bin | wc -l
      66

Which of them have "ls" in the name?

  admin@ksp-04-11:~$ ls /bin | grep ls
  false
  ls

And how many times does each name appear in a list?

  admin@ksp-04-11:~$ sort names | uniq -c
        1 bob
        3 kate

Join as many as you like, left to right, up to eight. Only the last one's
output reaches the glass.]],

[[The wastebasket, and one honest note about pipes.

/dev/null is a hole in the machine. Anything written to it is gone, and
reading it gives you nothing at all. It is not a file and it costs no
space on the drive.

  admin@ksp-04-11:~$ echo junk > /dev/null
  admin@ksp-04-11:~$ cat /dev/null
  admin@ksp-04-11:~$

That is what you use when you want a command to do its work and say
nothing about it.

The honest note. The commands that can read a pipe are the ones that read
files: cat, grep, head, tail, wc, sort and uniq. A file named on the line
always wins, so cat note.txt | sort sorts note.txt and cat note.txt |
grep -n e searches it. Give one of those seven no file and no pipe, and it
prints its usage line instead, because there is no keyboard behind a
command on this machine.

Classic mistake. Expecting a pipe to save something. It does not. Use a
greater-than sign for that.]],

		} },

		{ title = "8. Second names, and where commands come from", pages = {

[[A second name for a file somewhere else.

A link is a signpost. It is a tiny file whose whole contents are the name
of another file, and everything that opens it follows the sign.

Try it.

  admin@ksp-04-11:~$ ln -s note.txt shortcut
  admin@ksp-04-11:~$ readlink shortcut
  note.txt
  admin@ksp-04-11:~$ cat shortcut
  hello

ln -s makes one: the real file first, the new short name second. Always
include the -s. readlink says what a link points at without following it.

Two flags ask about the link itself rather than the file. ls -l draws the
arrow and starts the line with an l; ls -F marks it with an at-sign:

  admin@ksp-04-11:~$ ls -F
  note.txt   notes/     shortcut@

What a link lets you do is whatever the real file allows. A signpost to a
locked room is still a locked room. And rm on a link removes the signpost
and leaves the file standing, which is usually what you want.]],

[[Where the machine looks for a command.

Now for the sentence that explains chapter 2's "command not found". Every
command you type is a real file. ls is a file called /bin/ls. You can list
it and you can read it.

  admin@ksp-04-11:~$ cat /bin/ls
  list a directory

When you type a word, the machine walks a list of directories looking for
a file by that name, in order, and runs the first one it can. That list is
called PATH, and on a fresh machine it has exactly one entry. Try it.

  admin@ksp-04-11:~$ echo $PATH
  /bin

So "command not found" really means "I walked PATH and there was no such
file anywhere on it". Nothing more sinister than that.

Two commands report on the search. which prints where a name would be
found, and prints nothing at all when it would not. type does the same and
also knows the words that the shell itself is.]],

[[Your own bin, and how to add it.

A file found on PATH is run, so you can put your own small commands
somewhere and add that somewhere to the list. By tradition it is a
directory called bin inside your own home.

  admin@ksp-04-11:~$ mkdir bin
  admin@ksp-04-11:~$ PATH=$PATH:$HOME/bin
  admin@ksp-04-11:~$ echo $PATH
  /bin:/home/admin/bin

Read that middle line carefully, because it is the whole recipe. $PATH
means "whatever PATH is now". $HOME means your own directory. The colon
separates entries. So the line says: keep everything I had, and add my own
bin after it.

Order matters. Entries are tried left to right, so /bin still wins for any
name that exists in both. PATH may name eight directories at most, and a
ninth is refused where you set it.]],

[[Making the change stick, and proving it.

A file needs x on it before anything will run it. Give it the same way you
gave anything else x in chapter 5.

  admin@ksp-04-11:~$ echo "echo hi" > bin/hello
  admin@ksp-04-11:~$ chmod +x bin/hello
  admin@ksp-04-11:~$ hello
  hi
  admin@ksp-04-11:~$ which hello
  /home/admin/bin/hello
  admin@ksp-04-11:~$ type hello
  hello is /home/admin/bin/hello

The catch: that PATH line is forgotten the moment you log out. To have it
every time, put it in a file called .profile in your own home, which the
next chapter is about.

Classic mistake. A file on PATH with no x on it. It is a file in the way,
not a command, and the machine walks straight past it to the next entry
without complaining. If a command of your own is ignored, check ls -l for
the x before anything else.]],

		} },

		{ title = "9. What the machine remembers about you", pages = {

[[It writes down everything you type.

Every line you enter at the prompt is appended to a file in your own home
called .sh_history. One line per line, oldest first. It begins with a dot,
so ls will not show it to you until you ask with ls -a.

It is yours: mode 600, which from chapter 5 you can now read as "the owner
reads and writes, nobody else anything". Answers to questions are not in
it: a password you typed at New password: was never a command and was
never written down. Try ls -l on it and check both.

That file is what Up and Down at the prompt are walking through. Which
means it survives: come back tomorrow, press Up, and there is what you
typed today, still in order.

  admin@ksp-04-11:~$ ls -a
  .         ..        .profile  note.txt]],

[[Reading it back, and running a line again.

history prints the last sixty lines with their numbers. Try it.

  admin@ksp-04-11:~$ history
      1  ls -l
      2  cd /etc
      3  history

Two shorthands go with it. Two exclamation marks run the last line again.
An exclamation mark and a number run that numbered line. Either way the
machine echoes the line it worked out, so you can see what it is about to
do.

  admin@ksp-04-11:~$ !!
  admin@ksp-04-11:~$ !2

history -c empties the file, which is how you clean up after typing
something you would rather nobody read.

Two honest notes. Those numbers are positions in the file as it stands
right now, so they shift once the oldest lines start dropping off the top.
And an exclamation mark only means this when it is the whole line; in the
middle of a line it is just an exclamation mark.]],

[[How much of it is kept.

A thousand lines and sixteen kilobytes, whichever fills first, and the
oldest go over the side to make room.

Those sixteen kilobytes do not count against the machine's 32768 bytes of
drive. A shell's memory of itself should not be the thing that fills up
your disk, so df will not move because you typed a lot. ls -l still tells
you honestly how big the file is.

That exemption belongs to that file, at that name, in your own home.
Rename it and it becomes an ordinary file: df jumps by every byte of it at
once. Move it back and it is free again. Worth knowing before you get
clever with it.]],

[[.profile: things you want done every time.

There is one more dotted file in your home, and it is the useful one.
.profile is a list of lines the machine types for you, at login, after the
greeting and before your first prompt. If it is there and you may read it,
it runs.

One safe example, and it is the one from chapter 8:

  admin@ksp-04-11:~$ edit .profile
  (type one line: PATH=$PATH:$HOME/bin)
  admin@ksp-04-11:~$ exit

Log back in and echo $PATH has your own bin on it, and will every time.

The trap, and we would rather you heard it here. .profile IS your login
session, not a file it runs. So a line in it saying exit logs you straight
back out, instantly, every time you log in, and the login: prompt is all
you will ever see.

Classic mistake. Exactly that. The way out is root, which can edit your
.profile for you. Read what you put in that file twice.]],

		} },

		{ title = "10. When things go wrong", pages = {

[[The screen is empty. Now what.

Work down this list in order. It is the order of likelihood, not the order
of drama.

Is anything glowing? A dark, dead screen with no glow at all means the
machine is off, and almost always means the building has no power. Nothing
you type will help. Check the power.

Is there a login: prompt? Then the machine is fine and somebody logged
out, which is the polite thing they were supposed to do. Log in.

Is there a prompt and nothing above it? Somebody typed clear, or logged in
just now. Nothing is wrong and nothing is lost: clear touches the screen
and never the disk. Type ls and carry on.

Only three things ever wipe that glass: clear typed by hand, exit logging
out, and power leaving the machine. Walking away does not. Closing the
window does not. If the screen changed, one of those three did it.]],

[[No operating system found.

Rare, alarming, and repairable. Instead of a login: prompt you get two
lines:

  No operating system found.
  Restore system? (y/n)

The firmware from chapter 1 looked at the drive before handing over, and
what it found was not a working system any more. Usually that means the
commands in /bin were deleted, or every account was removed from the
machine's own list. It takes root and some determination to do either.

y repairs it. n leaves it exactly as broken as it was, and any other key
just brings the question back. Escape walks away from the question without
answering, and the machine will ask again.

Say y. There is no downside worth weighing, and the next page explains
exactly what it does and does not touch.]],

[[What a repair keeps, and what it rewrites.

It rewrites, without asking and every time: every standard command in
/bin, back to owner root, mode 755, and its shipped one-line description.
Missing, damaged, or merely chmod'd out of reach, all three come back the
same. So a chmod 600 /bin/ls does not survive a repair, and that is a
feature.

It touches the machine's account list and its list of who may become root
only when one of them is missing or no longer names anybody at all. A list
that still names one account is left exactly as it lies, passwords and all.

It never touches /home or /root. Your files, your notes, your .profile and
your history are not what broke and are not what gets rebuilt. Nothing you
wrote is at risk from a repair.

Running it twice changes nothing the second time.]],

[[Turning it off properly.

Two commands, and you need root for both, because switching off a machine
somebody else is working at is not an ordinary account's decision.

  root@ksp-04-11:~# shutdown
  root@ksp-04-11:~# reboot

shutdown switches the machine off. The screen goes dark, the glow goes
with it, and every window open on the machine closes. What was on the
drive survives untouched. What was on the glass, and anything unsaved in
the editor, does not.

reboot, and its exact twin restart, switch it off and straight back on:
everybody watching sees the firmware count its memory out loud again and
lands at a fresh login:.

As admin you get "shutdown: permission denied", which is not a fault. The
switch on the case works for everybody, and is what you should use.]],

[[The golden rules, on one page.

Type exit before you walk away. The screen belongs to the machine. This is
first because it is first.

Never type rm -r on anything you did not make yourself. There is no
wastebasket and no undo. Read the line twice before Enter.

Keep your password on paper, somewhere the computer is not. Nobody can
recover it for you, by design.

Save with Tab, often. The [modified] mark means your work exists only on
the glass, and the glass is the least durable thing here.

Type df before a long session. Thirty-two kilobytes goes faster than you
think.

Read the error line. Command, then what failed, then why. Three pieces, and
never trying to trick you.

When something looks broken, check the power, then the prompt, then ls -a,
in that order. It is almost always one of those three.

Classic mistake. Breaking one of these rules once, getting away with it,
and concluding the rule was fussy. Every rule here is on this page because
a customer wrote us a letter about it.]],

		} },

		{ title = "11. Quick reference card", pages = {

[==[Every command in this volume, with its exact shape. Square brackets are
optional parts; never type the brackets. Angle brackets are something you
must supply.

Getting about, and looking.

  pwd
  cd [dir]
  ls [-1laACF] [path]
  cat [file]...
  df

Making, copying, destroying.

  mkdir <dir>
  touch <file>
  cp [-r] <src> <dst>
  mv <src> <dst>
  rm [-r] <path>...
  echo [text...]
  edit <file>

Reading a file without opening it.

  head [-n N|-N] [file]
  tail [-n N|-N] [file]
  wc [-clw] [file]...
  grep [-c] [-i] [-n] [-v] <text> [file]...
  sort [-r] [-n] [-u] [file]...
  uniq [-c] [file]]==],

[[Permissions and ownership.

  chmod <mode> <path>
  chown <user> <path>
  chgrp <group> <path>

Your account.

  whoami
  id [name]
  groups [name]
  passwd [user]
  su [name]
  exit

The screen, and asking the machine.

  clear
  help
  man <command>

The clock, and waiting.

  date [+FORMAT]
  sleep <seconds>

Second names, and where commands come from.

  ln -s <target> <name>
  readlink <name>
  which <name>
  type <name>]],

[[Switching the machine off. Both want root.

  shutdown [-h|-r] [now|+N] | shutdown -c
  reboot
  restart

The numbers, all in one place.

Screen: 60 columns wide, 20 rows tall. The editor gets 17 of those rows to
write in, and a line stops at 60 characters. The typing line takes 240
characters.

One file: 4096 bytes.

The drive: 32768 bytes and 256 files and directories, whichever runs out
first. One directory: 96 entries. 16 levels of directory below the root,
and 32 characters in any one name.

ls -l shows a name up to 12 characters and cuts the rest with a squiggle.

History: the last 1000 lines and 16 kilobytes, and history prints the last
60 of them. PATH may name 8 directories. su stacks 4 deep.

Classic mistake. Typing the square brackets. They mark a part you may
leave out; they are not part of the command.]],

		} },

		{ title = "12. Appendix: what the machine says", pages = {

[[Every refusal on this machine is one line, and it is built the same way
every time:

  <command>: <what failed>: <why>

The command that refused, then exactly which file or word it refused
about, then the reason in two or three words. Read it in that order and it
will tell you what to do next. Below is every reason a user meets, with
what it actually means.

  no such file
      nothing is at that name; check ls and your spelling
  is a directory
      a file command was handed a directory; try -r
  not a directory
      a directory was expected and a file was there
  permission denied
      you may not read, write or step into it
  file exists
      something is already at that name

Classic mistake. Reading the first word and the last word and skipping the
middle one. The middle piece is the only part that tells you which file the
machine is actually complaining about.]],

[[Names and paths.

  invalid name
      the last part of the path will not parse
  invalid characters
      a control byte where only plain text belongs
  invalid destination
      a move or copy into itself, or into its own child
  path too deep
      past sixteen levels below the root
  is a device
      a file command met a device, not a file

Running out of room. Chapter 3 has the numbers.

  file too large
      past 4096 bytes for that one file
  disk full
      past 32768 bytes, or past 256 files, on the machine
  directory full
      the parent already holds 96 entries

  /dev: read-only
      nothing may be created under /dev; only the machine
      puts things there]],

[[Commands the machine could not run.

  command not found
      nothing on PATH answers that name; check spelling,
      check capitals, and check help

A command that is there but not yours to run says permission denied
instead, never command not found. One tells you it is missing, the other
that it is locked and exactly where.

  <cmd>: usage: <the shape of it>
      the right command with the wrong number of parts;
      the line it prints is the answer
  <cmd>: <flag>: unknown option
      a flag that command does not have
  chmod: <mode>: invalid mode
      neither three digits nor a clause in letters
  man: <name>: no manual entry
      no command of that name
  sh: sleep: no clock
      the machine has no clock to count from]],

[[Typing that the shell could not make sense of. Nothing runs at all.

  syntax error: bad redirect
      two redirects on one command; a command sends its
      output to one file, not to two
  syntax error: missing redirect target
      a greater-than sign with no file name after it
  syntax error: unterminated quote
      a double quote opened and never closed, or a line
      that ends in a backslash

Pipes, from chapter 7.

  too many stages
      more than eight commands in one pipeline
  input too large
      sort and uniq must see all of their input before
      they can answer, and it went past a hundred lines
      or four kilobytes]],

[[Logging in, and your account.

  login incorrect
      a wrong name or a wrong password, and it will never
      say which
  passwd: authentication failure
      the old password did not match
  passwd: passwords do not match
      the new one was typed two different ways
  passwd: password too long
  passwd: no such user
  su: authentication failure
      one wrong answer; there is no second try
  su: too many levels
      a fifth su, past the four the machine allows

  <name> is not in the sudoers file.
      that account may not become root at all; Volume 2]],

[[The editor, whose messages sit on its own bottom line rather than at a
prompt.

  Saved 34 bytes
      not an error: what Tab prints when it worked
  Save modified buffer? (y/n)
      Escape with unsaved work; Escape again backs out
  Line too long: 60 characters
      the screen is 60 wide; Backspace or press Enter
  Buffer full: 4096 bytes
      the file's own ceiling
  Buffer full: 2000 typed characters
      the typing box's ceiling for one sitting
  Cannot save: permission denied
      the file is [read-only] to you; nothing was written
  Cannot save: disk full
      no room left; nothing was written, so nothing is
      half-written
  Another user is editing
      somebody else opened this buffer first and has the
      keyboard; your Escape closes only your own window]],

		} },

	},
}
