-- The CeroSec OS User's Manual, as it sits on the shelf in Knox County.
--
-- A page of this book is a page for the in-world reader item: plain text,
-- ASCII only, no page over 900 characters, shell examples as their own
-- lines starting with two spaces. The only logic in this file is the one line
-- at the bottom that stamps the cover with CeroSecOS.VERSION; the text itself
-- is read by whatever item hands it to the player and by tests/manual_test.lua,
-- which checks it against the engine's own commands and error strings.

CeroSecManual = {
	-- The cover names the version of the OS this book is for, and that number
	-- has one home: CeroSecOS.VERSION. It cannot be read here at load time --
	-- the game sorts shared/cerosec/cerosecmanual.lua ahead of
	-- shared/cerosec/os/cerosecos.lua, so the core is not there yet -- so the
	-- title is stamped on by stampVersion() at the bottom of this file, which
	-- whoever opens the book calls first. There is no version literal here.
	title = nil,
	edition = "First Edition, 1993",
	chapters = {

		{ title = "1. Your machine", pages = {

[[CeroSec Systems, Louisville, Kentucky, has been putting small computers on
office desks since 1989 and this book since 1991. It is not a tutorial in
typing and it does not explain what a file is. It explains CeroSec OS: the
particular way this machine's shell, editor and accounts behave, including
the parts that surprise a visitor who has used a bigger system before.

Read it in order once, then keep it by the machine. The command MAN gives a
one-line reminder of what a command does; it does not go into the detail
this book does, and it was never meant to.]],

[[Notation. A line shown indented two spaces is something you type or
something the screen prints back, exactly as it appears:

  admin@ksp-04-11:~$ whoami
  admin

Square brackets mark an optional part of a command, never type the brackets
themselves. A dollar sign at the end of a prompt means an ordinary account is
logged in; a pound sign means an account with the admin flag set is logged
in. Anything this book states as fact was checked against a running
machine; where CeroSec Systems does not yet know the answer, the book says
so plainly rather than guess.]],

[[The machine is a beige box on a desk: a tower and a monitor, wired into the
building's own power and nothing else. It has no network cable, no modem
and no telephone line. Without power in the room it will not turn on, and
CeroSec Systems has had letters asking why -- the answer is that this is a
desk computer, not a portable one, and a dead building is a dead machine
until the power comes back.

The monitor glows a dim blue-green while the machine is on, day or night,
which is how you tell a working office from an abandoned one across a
street. It is a monitor's glow, not a lamp's: do not expect to read by it.]],

[[Turning it on and off is a menu choice at the machine itself, the same
way you would flip its switch. Turning it on takes a moment: you cannot
be turned away and have it happen behind you. If the option to turn it on
is missing entirely, or greyed out and unwilling to say why beyond "no
power", the building has none to give it -- check the wiring or the
generator before you check the machine.

Once it is lit, a second choice appears below the power switch to actually
sit down and use it. A dark screen has nothing to use, which is why that
choice is not there until the first one has been.]],

[[Reaching the machine. The screen looks one way out of its desk, and that
is the only side you may work it from -- CeroSec Systems built these for a
desk against a wall, not a shelf you walk around. If nothing can stand on
that one square, because it is a wall, a second piece of furniture or
nothing you can path to at all, the machine answers every attempt with the
same refusal and no amount of walking around the back will help.

Height matters too. A desk is fine and the floor is fine; stacked much
higher than a single crate and the machine answers that it is now too
high to reach, and stays that way until it comes back down.]],

[[Sitting down. Pull a chair to that one square, seat towards the screen,
and using the machine sits you in it on the way; turned away, or missing
outright, and you work standing, which the machine treats exactly the
same in every other respect. If you were already sitting there by hand,
it will not stand you up and sit you down again -- it only checks you are
on the square, not how you got comfortable.

A lit computer cannot be picked up. Turn it off first: the tiles that show
the glowing screen carry no weight and no way to lift them, which is
CeroSec Systems' way of saying a running machine stays where it is
plugged in.]],

		} },

		{ title = "2. Logging in", pages = {

[[Sitting down at a freshly powered machine plays its self-test once, the
moment anybody first looks at it -- not once per person who looks. Five
lines of it, typed out over a couple of seconds:

  CeroSec BIOS 1.0 -- (c) 1993 CeroSec Systems
  Memory test: 640K OK
  Detecting drives ... hda 32K
  Booting from hda ...

Then the machine's own greeting and a blank prompt waiting for a name. A
second person walking up after that finds the same lines already sitting
on the glass, never a second self-test -- the screen belongs to the
machine, not to whoever happens to be looking at it.]],

[[At login: type an account name and press Enter. Every fresh machine ships
two: root, which can do anything to it, and admin, which mostly cannot.
Both start with no password at all -- press Enter again at password: and
you are in.

  login: admin
  password:
  admin@ksp-04-11:/home/admin$

Get the name or the password wrong and the machine says only
"login incorrect" and starts over at login: again. It never says which
half was wrong, on purpose: a stranger typing names at your machine learns
nothing from the answer, not even whether the name he tried exists.]],

[[The prompt names who is logged in, the machine, and where you are
standing in its files, and ends in a dollar sign or a pound sign:

  admin@ksp-04-11:/home/admin$
  root@ksp-04-11:~#

A pound sign means the account's admin flag is set -- today that is
cosmetic, a mark on the glass and nothing more; what actually opens doors
is being root, or being named where sudo looks (chapter 8). A tilde in
the path means "your own home directory" there too, and, unlike many a
prompt, typing one works exactly the same way -- see chapter 4.]],

[[While the machine has your keyboard, nothing you type reaches anything
else: your character will not walk, will not swap a weapon, will not open
a bag, however many W's or E's you send it. Escape is how you take the
keyboard back. At an ordinary shell prompt it simply closes the window;
in the middle of a question -- half a name at login:, a password half
typed, anything passwd or sudo is asking -- it prints ^C on that line and
puts the question's start back up, rather than closing on you mid-answer.
Nothing you had typed toward that answer is kept.]],

		} },

		{ title = "3. Finding your way around", pages = {

[[A fresh machine's files look like this from the root:

  bin  dev  etc  home  root

bin holds the commands themselves (chapter 6), etc holds the files that
make the machine what it is (chapter 9), home holds one directory per
ordinary account, and root is the root account's own home -- an ordinary
account cannot so much as look inside it.

List a directory with ls, and add -l for a long listing: mode, owner,
size, the date it last changed, and the name, one file per line, in
exactly sixty columns. Add -F and a directory's name gets a slash after
it, so a list full of names does not make you guess which are folders.]],

[[cd changes where you are standing; alone, it takes you home. pwd prints
where that is. A path starting with a slash is measured from the very
top; anything else is measured from where you already are.

  admin@ksp-04-11:~$ cd /etc
  admin@ksp-04-11:/etc$ pwd
  /etc

A bare tilde, or a tilde in front of a slash, is your own home wherever
it appears -- as an argument or as a redirect target -- expanded once,
before the command ever sees it:

  admin@ksp-04-11:~$ cd ~
  admin@ksp-04-11:/home/admin$ cat ~/note.txt

Only a tilde with a name stuck straight onto it, like ~root, is left
exactly as typed, and since no file is named that, it answers
"no such file" like any other name nobody made.]],

[[cat prints a file straight to the glass, and echo prints back whatever
you hand it. Wrap text in double quotes when it has a space in it, or
the machine reads each word as its own separate argument:

  admin@ksp-04-11:~$ echo "two words"
  two words

Inside quotes, a backslash before n or t means a real newline or tab, and
a backslash before anything else just means that character -- there is no
other escaping and no single quote at all. There are no pipes and no
variables on this machine: one command, its own arguments, nothing piped
into anything else.]],

[[A greater-than sign sends a command's output into a file instead of the
glass, replacing whatever was there; two of them appends instead:

  admin@ksp-04-11:~$ echo "hello" > note.txt
  admin@ksp-04-11:~$ echo "again" >> note.txt
  admin@ksp-04-11:~$ cat note.txt
  hello
  again

The file is made if it was missing and it obeys every rule an ordinary
write does -- yours to write, room on the disk, printable text only.
Redirecting a command that only asks a question, or opens the editor, has
nothing to catch yet and is quietly ignored; see chapter 8 for the one
case, sudo, where that costs you something you likely wanted.]],

[[touch makes an empty file, or, on one that exists, moves its date to
right now without touching what is in it. mkdir makes a directory. mv
renames or moves either kind of thing, and cp copies a file -- add -r to
copy a whole directory, tree and all.

  admin@ksp-04-11:~$ mkdir notes
  admin@ksp-04-11:~$ touch notes/a.txt
  admin@ksp-04-11:~$ cp -r notes backup

None of the four will move or copy a directory into itself or one of its
own children -- the machine calls that "invalid destination" rather than
spin forever trying.]],

[[rm removes a file; add -r to take a whole directory down with everything
in it, and without -r a non-empty directory refuses outright rather than
guess you meant the tree. write puts one line of text into a file the way
the editor's own save does, useful when a whole editing session is more
than the moment calls for:

  admin@ksp-04-11:~$ write greeting.txt "hello there"

Every one of these answers "permission denied" on a file or directory
you may not touch, and "no such file" on a path that leads nowhere --
whichever it is, the machine names the exact path that failed, never a
general complaint.]],

[[A name that begins with a dot is hidden. ls walks straight past it and
so does ls -l; nothing else on the machine treats it as different in any
way -- cat .profile reads it, edit .sh_history opens it, rm takes it away.
It is the listing that is polite, not the file that is special.

Two flags show them. ls -a is everything, including the two entries every
directory has -- "." for itself and ".." for the one above it. ls -A is
everything except those two, which is usually what you wanted.

  admin@ksp-04-11:~$ ls
  notes.txt
  admin@ksp-04-11:~$ ls -A
  .profile  .sh_history  notes.txt
  admin@ksp-04-11:~$ ls -a
  .         ..           .profile
  .sh_history            notes.txt

They combine with the others: -la, -lA and -aF all read as you would
hope.]],

		} },

		{ title = "4. The editor", pages = {

[[edit opens a file full-screen for typing, in the same green glass the
shell uses. Nothing is written to disk the moment it opens -- edit on a
name that does not exist yet opens a blank page and creates nothing at
all until you save it. The screen becomes a title bar naming the file, a
writing area, a bar naming the two keys that work, and a message line at
the very bottom:

   EDIT /home/admin/notes.txt
  (seventeen lines to type in)
   Esc exit   Tab save

A block cursor sits where the next letter goes, blinking whether you are
typing or not.]],

[[Type as you would anywhere: Enter starts a new line, Backspace erases
across a line break same as within one, and the four arrows, Home and End
move the cursor without changing anything. The moment what is on the
screen differs at all from what is on disk, the title bar grows
"[modified]" pinned to its right edge, and it is gone again the instant
you save or the instant the two agree once more, such as undoing your own
last change by hand.

Those are the only keys that do anything here beyond typing a letter --
the game hands a text box exactly Escape and Tab and nothing else, which
is also why Tab, not any Ctrl combination, is the one that saves.]],

[[Tab saves and says so: "Saved N bytes" on the message line, with the
"[modified]" mark gone. Escape leaves; if nothing is unsaved it leaves at
once, and if something is it asks first, right on the message line:
"Save modified buffer? (y/n)". Escape again backs out of that question
with the buffer untouched, y saves and leaves, n leaves without saving --
and any other key just leaves the question sitting there rather than
guess what you meant.

A line is capped at sixty characters -- past it, typing stops and the
message reads "Line too long: 60 characters" until Backspace brings it
back under, or Enter starts a fresh one.]],

[[Two more ceilings, and they are not the same ceiling. The game's own
input box stops taking new letters at two thousand typed in one sitting
and says "Buffer full: 2000 typed characters" -- paste a great deal of
text in and you will meet this one first. The machine's own limit is four
thousand ninety-six bytes to a file; go past that while typing and the
message instead reads "Buffer full: 4096 bytes". A file already bigger
than either still opens and still edits; only new growth is stopped. A
save that will not fit what is left of the disk answers
"Cannot save: disk full" and writes nothing.]],

[[A file you may read but not write opens with "[read-only]" in the title
bar instead of "[modified]", stays that way however much you type, and
Tab answers "Cannot save: permission denied" without touching the disk.
Escape leaves at once, no question asked -- there is nothing unsaved that
belongs to you. A file you may not even read is refused before the editor
opens at all: "edit: <path>: permission denied" at the shell, same as any
other command that cannot see it.

Walk off the machine mid-edit and come back: the buffer, the text, the
"[modified]" mark and even an unanswered save question are exactly as you
left them -- only the cursor resets to the very start.]],

[[Two people at one machine may look at the same buffer, but only one may
type in it. The one who opened it edits; the other's screen shows the
same words updating live, with "Another user is editing" on his message
line, and his own keystrokes go nowhere at all -- his Escape closes only
his window, never the shared buffer. The moment the editor stands up and
walks away, the machine notices within about a minute and hands the
keyboard to whoever else is still watching, no reopening required.

There is no way to run a command while the editor is open, on purpose --
the shell simply is not there until you leave it with Escape.]],

		} },

		{ title = "5. Permissions and ownership", pages = {

[[Every file and directory carries an owner, a group and a mode. The mode
is three digits, written and shown the way a bigger Unix writes them: one
for the owner, one for the group, one for everybody else. Each digit is
read, write and execute added up the usual way: 4 to read, 2 to write, 1
to run it as a command or step into it as a directory.

  admin@ksp-04-11:~$ chmod 640 notes.txt
  admin@ksp-04-11:~$ chgrp users notes.txt
  admin@ksp-04-11:~$ ls -l notes.txt
  -rw-r-----  admin  users     412  Jul  8 14:32  notes.txt

chown hands a file to a different owner by name; chgrp hands it to a
different group. Both are the owner's to do and root's to do, and both
answer "permission denied" to anybody else, on the file itself, before
any digit is looked at.]],

[[All three digits are read, and exactly one of them decides. The machine
asks in order: do you own it? Then the first digit is yours and the other
two are none of your business. Are you in its group? Then the middle
digit is yours. Neither? Then the last one is, and that is the whole
answer.

So 640 on a file of admin's in group users means admin reads and writes
it, anybody in users reads it, and everybody else gets nothing at all --
not even the knowledge of what is inside it. Root walks through all three
and is never asked any of the questions.

Chapter 6 says what a group is and how you join one.]],

[[Directories obey the same three digits, but execute on a directory
means something different than on a file: it is permission to step inside
it at all, list it or not. An ordinary account's home ships at mode 750;
root's own, /root, ships tighter, at 700 -- its owner can do anything in
it, anybody else may not even see what is in it, which is why cd /root as
admin answers "cd: /root: permission denied" long before anything about
what is inside it comes up. A home at 750 is a home its owner's group can
walk into and read: chgrp on the home itself is how two survivors come to
share one.]],

[[Where /bin fits in. Every shell command is a real file inside /bin,
owned by root, mode 755, and its one-line description is the file's
entire contents -- cat /bin/ls really does print "list a directory".
Nothing about that is special-cased: chmod 644 /bin/ls takes ls away from
everybody but root just as surely as it would any file of yours, and
rm /bin/ls really does delete the command. The shell looks up exactly
/bin/<name> and nowhere else -- no search path, no "./thing" -- so a
missing, unreadable or unexecutable file there is command not found or
permission denied, and nothing else could ever run it instead.]],

[[Only exit and help are not files at all; they run even on a machine
whose /bin has been wiped clean, on purpose, so that a machine you just
broke can still tell you what happened and let you leave it standing.

The system files carry their own fixed modes, set by the BIOS and not
meant to be argued with: /etc/passwd is 600 (root reads and writes it,
nobody else so much as looks), /etc/sudoers is 440 (root and whoever it
names may read it, nobody writes it by hand), and /etc/group,
/etc/hostname and /etc/motd are 644, world-readable and root-writable,
the way a name on the door usually is. There is no secret in the group
file: it says who shares with whom, and anybody may read it.]],

[[chmod also takes the mode in letters, which is what you will actually
type. A clause is who -- u for the owner, g for the group, o for
everybody else, a for all three -- then + to add, - to take away, or = to
set exactly, then any of r, w and x. Commas separate clauses and they are
applied left to right, to the mode the file is wearing NOW, which is the
whole difference between chmod u+x and chmod 744.

  admin@ksp-04-11:~$ chmod u+x backup.sh
  admin@ksp-04-11:~$ chmod go-w notes.txt
  admin@ksp-04-11:~$ chmod a=r readme
  admin@ksp-04-11:~$ chmod ug+rw,o-rwx private

Leave the who out and it means all three, so +x is a=x. Saying the same
letter twice changes nothing -- they are a set, not a sum. a= with nothing
after it is how you say 000 in letters. u+ and u- are not clauses at all
and answer "invalid mode", as does anything that is neither three octal
digits nor this.]],

		} },

		{ title = "6. Accounts and passwords", pages = {

[[Only root may make or unmake an account. adduser writes it into
/etc/passwd, makes its home directory, and says so out loud -- and warns
you in the same breath that it has no password yet:

  root@ksp-04-11:~# adduser bob
  bob: created
  adduser: set a password with passwd bob

-a on the way in sets the account's admin flag, worn only as the pound
sign on its prompt today and read by nothing else in the machine. A name
must start with a lower-case letter and hold nothing but lower-case
letters, digits, dashes and underscores, sixteen characters at most --
narrower than an ordinary file name, so it always fits a prompt.]],

[[deluser takes an account away; -r takes its home directory with it, and
without -r the files stay on disk, owned by a name the machine no longer
knows. root cannot be removed at all, and nobody currently logged in
anywhere on the machine -- at the glass or four deep in an su chain --
can be removed either, until he logs out.

id prints what the machine knows about any name: its admin flag and
every group it is in. groups prints the same list on its own, and both
answer about anybody, to anybody.

  root@ksp-04-11:~# id bob
  uid=bob flag=user groups=bob
  root@ksp-04-11:~# groups admin
  admin sudo users]],

[[su becomes somebody else at the very same glass without logging out --
root by default, or a name of your choosing, asked for that account's own
password (root, asked to become anybody, is never asked for a password at
all). exit comes back to who you were, one step at a time, and the stack
this makes can run four accounts deep before the machine refuses a fifth
with "su: too many levels". Walk away mid-stack and come back: you are
still exactly as many accounts deep as you left it.

  admin@ksp-04-11:~$ su root
  password:
  root@ksp-04-11:~# exit
  admin@ksp-04-11:~$]],

[[passwd changes a password: your own old one first (skipped only for
root, which nobody's password can lock out of itself), then the new one
twice, to catch a mistyped one before it becomes the only key to the
account. Every answer is starred on the glass, never shown in the clear,
and none of it is ever written to disk unhashed even for the length of a
save -- walk away mid-question and reload, and the machine is still
mid-question, nothing lost and nothing exposed.

  admin@ksp-04-11:~$ passwd
  old password:
  new password:
  retype new password:
  passwd: password updated

root may change anyone's the same way, naming them: passwd bob.]],

[[hash shows what a password would be stored as, without changing
anything -- useful for putting an account straight into /etc/passwd by
hand with the editor, or simply for satisfying yourself nothing is kept
in the clear:

  admin@ksp-04-11:~$ hash hunter2 ab12cd
  $cs1$ab12cd$7e3c9a...(32 hex digits)

Give your own salt (letters and digits, sixteen characters at most) and
you get the same line every time; leave it off and a fresh one is picked
each time, which is the salt doing exactly its job -- two accounts with
the same password never look alike on the disk.]],

[[A group is how two survivors share a file. Every account is already in
one of its own name, needing no line; the rest live in /etc/group, one to
a line, the name and its members:

  root@ksp-04-11:~# cat /etc/group
  root:
  sudo:admin
  users:admin,bob

groupadd makes one, groupdel takes one away, gpasswd -a and -d put a name
in or out -- all three root's alone -- and root, sudo and users are the
three the machine keeps. Delete any other and files naming it keep the
name: ls -l shows it dangling, nobody is in it, and chgrp will not hand
it out again.

/etc/sudoers stays the authority on who may become root; the sudo group
mirrors it, so a name in that file is in the group with or without a line
here. Joining by hand shares files, never root. Every device under /dev
belongs to root and to sudo -- which is why an account that may sudo
throws a light switch with no sudo typed.]],

		} },

		{ title = "7. sudo and root", pages = {

[[sudo runs one command as root without logging you out of your own
account. Who may is /etc/sudoers, one name a line, and a fresh machine
lists admin. Typing it asks for your own password, once:

  admin@ksp-04-11:~$ sudo adduser carl
  [sudo] password for admin:
  carl: created

Get it wrong and the machine answers "sudo: authentication failure" and
stops there -- there is no second try, on the reasoning that a stranger
typing at your keyboard only gets one guess before he has to walk away
from it entirely, same as a real lock. A name /etc/sudoers does not
mention at all is told so outright: "<name> is not in the sudoers file."]],

[[A sudoers line ending in the single word NOPASSWD skips the question
for that name entirely -- convenient, and worth remembering it also skips
the one check that would have caught somebody else sitting at your
already-open session. Root itself is never looked up in the file at all:
an /etc/sudoers with nobody left in it can still be repaired by root,
because root's own power never depended on being named in it.

The command runs with root's own power, but not root's own place in the
files: sudo cd /root moves nobody anywhere, because cd only ever moves
the session that is actually logged in.]],

[[Two quirks worth carrying in your head. sudo su and sudo exit touch
nothing of your own login stack: the borrowed root session that sudo
builds gets its own copy of it, so pushing or popping inside a sudo'd
command dies with that command, and whoami still answers your own name
right after. And a redirection on a sudo'd line is only caught if the
command answers straight away -- ask sudo for a password first, and by
the time you have answered it the > or >> from the original line is gone
with it, so the command's output lands back on the glass instead of the
file you named. Where that matters, set NOPASSWD first.]],

		} },

		{ title = "8. The system files, and the BIOS", pages = {

[[Nothing about this machine is secret from root: every rule it lives by
is a file root can read and rewrite with the very same editor everything
else uses. /etc/passwd holds the accounts, one line each:

  name:$cs1$salt$32 hex digits:home:admin|user

A line that is not exactly those four fields, whose name will not parse,
whose hash is not one of ours, or whose last word is neither admin nor
user, is skipped rather than guessed at -- and skipped silently, so a
typo in this file does not announce itself, it simply is not there next
time somebody logs in. Two lines naming the same account keep the first
one only.]],

[[/etc/sudoers holds who may sudo, one name a line, optionally followed by
NOPASSWD; a blank line or one starting with # is a comment, and anything
else that will not parse the same way is skipped. /etc/hostname holds the
machine's own name, one to sixteen lower-case letters, digits and dashes,
never starting with a dash -- change it with hostname <name>, root only,
and every prompt and window title on the machine picks it up at once.
/etc/motd holds what greets a login, ten lines at most. Empty it, or
remove it, and the machine greets nobody: silence is a valid choice.]],

[[A machine can break: /bin emptied, or every last account gone from
/etc/passwd. The BIOS notices before it puts anything else on the glass,
and instead of a login prompt you get:

  No operating system found.
  Restore system? (y/n)

y writes every standard command back into /bin, owner root, mode 755,
its shipped description -- whether that file was missing, damaged, or
simply chmod'd away, so a repair really does undo a chmod 000 /bin/ls.
It never touches /home, /root, or a file of your own sitting in /bin
under a name none of the standard commands use.]],

[[y touches /etc/passwd and /etc/sudoers only when one of them is
missing, is not a file, or no longer parses to anybody at all; a file
that still names one account is left exactly as it lies, hashes and
all. n leaves it exactly as broken as it was, and anything typed at it,
right down to a stray key, only brings the same question back. exit or
Escape simply walks away from the question without answering it.]],

[[Running the repair twice changes nothing new the second time: /bin is
rewritten again to the very same owner, mode and text it already held,
and a passwd or sudoers that still parses is left alone both times. What
never comes back on its own is what the repair was never meant to touch
in the first place. If root's own account is the one thing gone, the
BIOS is the only door left; there is no back door around it and none was
ever built.

A machine gets new commands the same way, quietly, the moment it is next
turned on after CeroSec Systems ships them -- once, and only the ones it
was actually missing.]],

[[What is in /bin and what is not. Nearly every word you type is a file
there, and that is the machine's honesty about itself: rm /bin/sleep does
take sleep away, and chmod 600 /bin/echo does put echo out of an ordinary
account's reach. True even of the small ones the shell runs without
leaving the house -- echo, printf, test, [, true, false and sleep are
looked up in /bin first and then run inside the shell for speed.

/bin/sh is the shell itself. Delete it and every line you type answers
"sh: command not found" -- and the BIOS brings it back.]],

[[Two kinds of word are not files and could not be. The grammar itself --
if, then, elif, else, fi, for, while, until, do, done -- was never a
command. Nor are the shell's own words: cd, exit, jobs, wait, read,
shift, break, continue and history. No program can move the shell that
ran it, or be handed the jobs it started, so there is nothing an
executable of those names could ever have held. Look for /bin/cd and
there is none; man cd answers all the same, because a word of the shell
has its entry from the shell.

help is the one command that does have a file and is run without looking
for it, so that somebody in front of a machine he has just wiped can ask
what happened -- and exit, being a word of the shell, is how he walks
away.]],

		} },

		{ title = "9. The clock, and other small tools", pages = {

[[date prints the day and the hour, read off the very clock the world
outside keeps -- there is no separate clock inside the machine to drift
out of step with it. Give it a format and it prints only the pieces you
asked for:

  admin@ksp-04-11:~$ date
  Tue Sep 8 14:05 2026
  admin@ksp-04-11:~$ date +%Y-%m-%d
  2026-09-08
  admin@ksp-04-11:~$ date +%s
  1757339100

%s is the clock as a plain number, the same number every file's date is
stored as underneath -- useful for a script comparing two dates by
subtraction one day, not something to type for pleasure.]],

[[Every file remembers the moment it was last changed the same way, one
number for both content and mode -- a chmod moves it exactly as a rewrite
does. ls -l always shows a month, a day and an hour and minute, never a
year, no matter how old the file: "Jul  8 14:32". A file that predates
this rung of the machine, or was made without a clock handed to it, has
no stamp at all and shows the one date a missing stamp always reads as:
"Jan  1 00:00".

df says how much of the machine is used, out of a fixed thirty-two
kilobytes of disk and two hundred fifty-six files and directories total,
whichever runs out first, one line for each of the two:

  admin@ksp-04-11:~$ df
  Filesystem   Size   Used  Avail  Use%
  hda         32768   1482  31286    5%
  nodes         256     62    194   25%]],

[[grep looks for a plain string inside one or more files, one line per
match, the file's name in front of it when there is more than one file to
search: -i ignores upper and lower case, -n numbers the lines. There is
no pattern matching here at all, only an exact substring -- a period
means a period, not "any character".

  admin@ksp-04-11:~$ grep -n root /etc/passwd
  1:root:$cs1$...:/root:admin

head and tail print the first or last lines of a file, ten by default or
however many -n asks for; wc counts a file's lines, words and bytes, all
three, always in that order.]],

[[man <command> prints what the command does and how it is spelled, one
line each -- for depth beyond that, this book is the depth. help lists
every command currently in /bin with its one-line description, which
means help itself is a mirror of the machine's own bin directory: take a
command's file away and help stops mentioning it.

whoami prints who is logged in, and hostname alone prints the machine's
own name -- the same name in the window's title bar and in every prompt,
because all three read the very same file.]],

[[A worked example, tying several of the above together: was this file
touched today?

  admin@ksp-04-11:~$ ls -l notes.txt
  -rw-r--r--  admin  admin     12  Sep  8 14:05  notes.txt
  admin@ksp-04-11:~$ date +%Y-%m-%d
  2026-09-08

Nothing on this machine does that arithmetic for you yet -- there is no
scripting language here, only the shell you are typing at, one line at a
time. A later rung of this system is expected to add exactly that; see
chapter 10 for what is already decided about where this is going.]],

		} },

		{ title = "10. /dev: the building around you", pages = {

[[The machine is wired into the building it stands in, and dev is how
you work it. Type it alone and every door, light switch and window
it can reach is one line.

  admin@ksp-04-11:~$ dev
  door0   exterior              0 5S        W  locked
  door1   kitchen-hallway       2W 1N       N  closed
  light0  office                0 0            on
  lock0   exterior              0 5S        W  locked
  lock1   built                 4E 9S +1    N  padlock

The id you name it by; the two rooms it stands between, exterior
where one side is the outdoors, built for what a player raised;
where it is from where the computer stands -- tiles east or west,
tiles north or south, 0 0 for its own square, a floor that is not
this one written +1 or -1 after; the way it faces, N or W, and a
light has none; and what it is doing. Room names repeat in a big
house and an offset does not, so that column is what tells one
kitchen door from another.]],

[[door0 and lock0 up there are one door twice over: the thing that
opens, and the key that holds it shut.

doorN is every door the machine can reach, a map's or a player's,
inside the building or out. It reads open, closed or locked --
locked being shut and held -- and it takes open and close.

  admin@ksp-04-11:~$ dev door1 open
  door1: open

It swings with nobody's hand on it: no survivor walks over, nothing
is animated, the door is simply open and everybody on the server
sees it that way.

lockN is the one that is choosy, and the honest sentence about it is
this: a key stops a survivor who is outside a building and stops
nobody who is inside it. So a lock is fitted only where it bites --
a door with the outdoors on one side, and a door a player built --
and an interior door has no lockN at all. A key turned on one of
those by hand changes neither what doorN reads nor what it does.]],

[[A computer is not a key either. A locked door answers with the word
and stays shut; the way through is its lock, first.

  admin@ksp-04-11:~$ dev door0 open
  door0: locked
  admin@ksp-04-11:~$ dev lock0 unlock
  lock0: unlocked
  admin@ksp-04-11:~$ dev door0 open
  door0: open

barricaded is planks, and no machine takes those off. blocked is the
doorway itself -- a tree, a car across it, or somebody standing in
it.

A padlock is none of those. A padlock on a player's door holds what
is behind the door and not the door, so a padlocked door still opens
-- which is what a survivor clicking it finds too. And a garage door
or a double door is several pieces making one opening: the machine
will not move one piece and leave the rest, so those carry a lockN
and no doorN.]],

[[A big building is a long list and the screen simply scrolls. Name a
kind -- door, light, lock or win -- and only that kind is listed.

  admin@ksp-04-11:~$ dev win
  win0    office                1E 0        N  locked

The list runs by kind and then by number, so light2 comes before
light10 and each kind stands together.

One id, and dev reads that one back. An id and a word, and dev does
it and answers with the state it read afterwards, so you never have
to ask a second time.

  admin@ksp-04-11:~$ dev light0
  light0: on
  admin@ksp-04-11:~$ dev light0 off
  light0: off

light answers on and off. lock and win, map door and player-built
alike, answer lock and unlock. door answers open and close. Nothing
else is a word these kinds know, and no kind has heard of another's:
typing one is "light0: invalid value" -- the device's own name
first, the same grammar every refusal of its uses.]],

[[toggle stands in for the opposite of what the device reads now: a
lit switch goes off, a shut door opens and an open one shuts, a
locked lock unlocks, and a padlocked one has its padlock taken off.

  admin@ksp-04-11:~$ dev lock1 toggle
  lock1: unlocked

A locked door has an opposite too, so toggle asks for it and the
world answers "door0: locked" -- telling you which device to turn. A
window that is smashed or barricaded is in no state a word undoes,
and toggle answers "win0: cannot toggle" rather than guess; dev win0
lock still asks, and the window refuses in its own name. A number
never handed out is the command's own refusal:
"dev: light7: no such device".

dev find <id> answers what no list can: which of the thirty-five
this one is. A light blinks for six seconds and goes back exactly as
it was; a door or a window is outlined on the screen of whoever
asked, and on nobody else's.

  admin@ksp-04-11:~$ dev find door1
  door1: highlighted]],

[[Underneath, every device is a file under /dev, and dev is the short
way to type what you could type yourself. cat reads one, printing
its state and nothing more; a redirect writes one. dev light0 off
and echo off > /dev/light0 are one order, refusals included.

  admin@ksp-04-11:~$ cat /dev/light0
  on
  admin@ksp-04-11:~$ echo off > /dev/light0

ls -l /dev is the same devices with the plumbing's columns in front
and no room left for the offset:

  admin@ksp-04-11:~$ ls -l /dev
  crw-rw----  root  sudo  door0   exterior       W  locked
  crw-rw----  root  sudo  light0  office            on
  crw-rw----  root  sudo  lock0   exterior       W  locked

The mode wears a c where an ordinary file wears a dash: a device is
a character device. Then the owner, always root, and the group,
always sudo. Nothing under /dev is ever on the disk: it is built
fresh at every command and torn down before the prompt comes back,
so no save carries a byte of it.]],

[[660 and group sudo is not decoration: an account /etc/sudoers names
reads and works every device with no sudo typed at all, and anybody
else gets "permission denied" from the device itself -- chapter 6
says how that group is kept. chmod moves that mode and it survives:
the node itself is thrown away at the end of the command, so chmod
writes the new number into the machine's own book, not onto a node
that will not exist a moment later.

  admin@ksp-04-11:~$ su root
  password:
  root@ksp-04-11:~# chmod 666 /dev/light0

A device is not a file: rm, mv, cp and edit on one all answer
"is a device", filesystem grammar and all. /dev itself takes nothing
new -- mkdir, touch or edit a name under it and the answer names the
directory instead: "/dev: read-only".]],

[[What a machine can reach is the building it stands in, every room of
it, or, with no building around it -- a player's own base counts as
none -- ten tiles in every direction on its own floor, walls
included either way. Nothing outside the loaded world exists: a town
nobody is standing in is a town no script there can touch.

Every device works out its list fresh, each time a command runs, so a
switch that came within reach since the last command already has its
number by the time you type dev again. A number, once handed out,
belongs to that device for the life of the machine: light0 is the
same switch tomorrow as today, and one torn out or sledgehammered
leaves a gap nothing moves up into -- a line depending on light3
still means what it meant. A machine's book of numbers holds at most
128; past that, an unreachable device is simply not remembered.]],

		} },

		{ title = "11. Shutting down, and what is next", pages = {

[[shutdown switches the machine off from the keyboard instead of the
switch on its case -- root only, since turning off somebody else's work
is not a thing an ordinary account gets to decide. The sprite goes dark,
the glow goes with it, and every window open on the machine, yours and
anybody else's, closes there and then. What was on the disk survives
untouched; what was on the glass, and anything unsaved in the editor,
does not -- a screen is not a document, however it might feel like one
while you are looking at it.]],

[[reboot, or restart, its exact twin, switches the machine off and straight
back on again, root only, same as shutdown. Unlike shutdown it does not
close the windows watching it: everybody standing there watches the BIOS
count its memory out loud a second time and lands back at a bare login:,
same as any other power-on. This is a power cycle, not a repair -- a
machine broken enough for the BIOS to refuse it stays refused after a
reboot exactly as before one.

  root@ksp-04-11:~# reboot
  (the screen clears, the BIOS plays, login: returns)]],

[[shutdown takes a time, and with one it warns everybody standing at the
machine first. -h halts and -r reboots; with neither it halts. now, or no
time at all, is at once. +N is N minutes from now, and the machine says so
on every screen in front of it the moment you ask, again one minute
before, and once more as it goes.

  root@ksp-04-11:~# shutdown -r +5
  The system is going down for reboot in 5 minutes!
  (four minutes later)
  The system is going down for reboot in 1 minute!
  (and then)
  The system is going down for reboot NOW!

shutdown -c calls it off and prints "shutdown: cancelled". One pending
order per machine: a second answers "shutdown: already scheduled" rather
than quietly replacing the first, because nobody should be told two
different times. halt is shutdown -h now under the older name.]],

[[The timer is the machine's and not your window's: close the window, walk
away, come back, and it is still counting. It is not on the disk, though,
and that is worth knowing -- the building losing power, the computer being
picked up, or the world being saved and loaded again all forget it, and
the machine simply stays up. A shutdown you meant is one you may have to
ask for twice after a reload. CeroSec Systems would rather say so than
have you find out by the machine not going down.]],

[[Closing the window yourself, with Escape or its close box, costs the
machine nothing at all: the screen is the machine's, and it is exactly
as you left it the next time anybody opens it, logged in or not, mid
edit or not. Walking off the one square in front of it does the same
thing to your own window without you asking, and does not touch anybody
else still standing there watching the same glass.

Only clear, exit and power leaving the machine wipe the glass clean --
clear typed by hand, exit by logging out, and power by shutdown, a
reboot, or the building's own supply failing under it. Nothing else
does -- walking off the front square, closing the window, none of that
touches a single
line. Whether the screen you come back to is a locked login: or a dead,
dark one, either way it was one of those three that put it there, never
simply your having left.]],

		} },

		{ title = "12. Tricks and quirks", pages = {

[[A short list of everything this book has already said once, gathered in
one place for the day you need it fast rather than in order.

Escape only closes an idle window; mid-question it prints ^C and hands
the question back to its start instead. Tab saves in the editor and
completes a word at the prompt, and is the only key that does either. A lit computer cannot be picked up -- turn it off first. The
screen belongs to the machine, not to you: log out before you leave a
machine you do not want the next person walking in on. Walking away does
not clear it -- only clear, exit and power leaving the machine do (see
chapter 11) -- so the next person to sit down finds your session exactly
as you left it unless one of those three already ran.]],

[[sudo loses a redirection the moment it has to ask for your password
first -- give the account NOPASSWD in /etc/sudoers if a script depends on
sudo <cmd> > file working every time. ~ and ~/... expand to your own
home wherever they are typed, in an argument or a redirect target alike;
only a name stuck straight onto the tilde, like ~root, is left as typed
and answers "no such file". The BIOS repair keeps /home and /root exactly
as it found them, but it always rewrites every standard command in /bin
back to root, 755 and its shipped description, present or not -- a
chmod 600 /bin/ls does not survive a repair.]],

[[A machine already running when CeroSec Systems ships new commands
picks each one up once, quietly, the next time it is turned on -- you
will not be asked and it will not repeat. date +%s hands you the clock
as a plain number, the same number every file's date is stored as, which
is the one date arithmetic actually works on here. hash <text> <salt>
without a salt of your own is how you notice the salt doing its job: run
it twice and you get two different lines for the very same password.]],

[[chmod 666 works on a file exactly the way it works on anything else --
useful the day a device file (chapter 10) needs opening up to more than
its owner, since nothing about /dev makes the mode digits mean anything
different. ls -l never prints a year, however old a file is -- a stamp
of "Jan  1 00:00" is not New Year's Day, it is the machine's way of
saying this file was never handed a clock to begin with, likely because
it predates this rung of the machine. And ls cuts any name past
seventeen characters
short, with a trailing tilde standing in for what got dropped -- the file
is not renamed, only how it is shown to you.]],

[[Three more for /dev. sudo loses its redirect the moment it has to ask
for a password (chapter 7), and a device is no exception: sudo echo
off > /dev/light0 typed as an ordinary account stops at the password
prompt and the switch never hears about it -- do it as root, or give
the account NOPASSWD, if a script needs it to land. A window stays
lockable exactly as long as it has glass: the moment it is smashed,
echo lock or unlock both answer "winN: smashed", and cat only ever
reports smashed after that -- there is no locking a broken window
back into service. And a device torn out or sledgehammered keeps its
number for the life of the machine -- ls /dev stops listing it, but
the id is never handed to the next one that appears.]],

		} },

		{ title = "13. Scripts", pages = {

[[A script is a text file with commands in it, one to a line, and nothing
else. Write one with the editor, then hand it to the shell:

  admin@ksp-04-11:~$ edit backup.sh
  admin@ksp-04-11:~$ sh backup.sh

If the file carries x for you, you can run it by its path instead, which is
what ./ means -- this file, here:

  admin@ksp-04-11:~$ chmod 755 backup.sh
  admin@ksp-04-11:~$ ./backup.sh

A bare name is still a command in bin and only there, so a script in your
home is never found by typing its name alone. A first line of #!/bin/sh is
allowed and ignored; a # anywhere starts a comment that runs to the end of
the line. Blank lines do nothing. Two commands fit on one line with a
semicolon between them.]],

[[Words are split on blanks, and quoting works exactly as it does at the
prompt: double quotes hold a string together and still let a $ through,
single quotes let nothing through at all, and a backslash takes away the
meaning of the character after it.

A variable is set with NAME=value and no spaces around the equals sign, and
read back with $NAME or ${NAME}:

  count=3
  greeting="hello there"
  echo $count $greeting

Values are text. A variable that was never set reads as nothing at all, and
an unquoted one that is empty disappears from the line rather than becoming
an empty word -- which is why "$x" in quotes is the safer way to pass one to
a command that expects an argument.]],

[[Arithmetic lives inside $(( )) and works on whole numbers with + - * /
and %, and parentheses; division throws the remainder away and rounds
towards zero. Inside the double parentheses a bare name is already the
variable, so the $ in front of it is optional.

  i=$((i + 1))
  echo $((7 / 2)) $((-7 / 2)) $((7 % 3))

The output of a command becomes a word with $( ), every newline in it
folded to a space. One level only: a $( ) inside a $( ) is refused where it
is typed.

  today=$(date +%Y-%m-%d)

A script is handed the words typed after it. $1 to $9 are those words, $#
is how many there are, $@ is all of them, and shift throws the first away
and moves the rest down. Three more are the machine's own: $? is the status
the last command ended on -- 0 when it worked -- $$ is the number of the
job the script is running as, which is what ps prints and kill takes, and
$0 is the script's own name.]],

[[if runs one list of commands and looks at the status it ended on:

  if [ -f notes.txt ]; then
    echo found it
  else
    echo no notes
  fi

elif adds another question before the else, and both else and elif are
optional. The thing in brackets is the command test, spelled the way every
Unix spells it; the spaces inside the brackets are not decoration and it
will not parse without them. It answers on files -- -f a file, -d a
directory, -e either, -r -w -x what you may do with it -- on strings -- -z
empty, -n not empty, = and != -- and on numbers, with -eq -ne -lt -le -gt
-ge. Join two with -a or -o and turn one round with ! in front of it.]],

[[Loops come in three shapes. for walks a list of words, while runs as long
as its command keeps succeeding, and until is while turned round:

  for f in one two three; do
    echo $f
  done

  i=0
  while [ $i -lt 3 ]; do
    echo $i
    i=$((i + 1))
  done

break leaves the loop and continue jumps to its next turn; both take a
number to leave or skip that many loops at once, counted outwards. exit
ends the whole script, with the status you give it, and return does the
same thing. Loops and ifs nest sixteen deep and no further.]],

[[Six commands belong to the shell itself and work with no file in bin
behind them. echo prints its arguments, and echo -n leaves the cursor on
the same line. printf takes a format with %s, %d and %% in it. shift moves
the arguments along. read stops the script and asks:

  read -p "name? " who
  echo "hello $who"

The question appears at the prompt and the next line typed becomes the
value. read -s hides what is typed, for a password; read -n 1 takes the
first character and does not wait for Enter. sleep waits a number of
seconds of real time and costs the machine nothing while it does.

Pressing Escape while a script is running kills it, question and all.]],

[[A line ending in & runs in the background: the prompt comes straight back
and the script's output arrives on the same screen as it is made.

  admin@ksp-04-11:~$ sh watch.sh &
  [1] 42
  admin@ksp-04-11:~$ ps
    ID S     CPU COMMAND
    42 R      96 sh watch.sh
  admin@ksp-04-11:~$ kill %1

[1] is the job's slot and 42 is its number; kill takes either, the slot
with a % in front of it. jobs lists them by slot, ps by number with the
state -- R running, S sleeping, W waiting for an answer, O held back by the
screen -- and the steps it has spent. wait holds the prompt until the
background jobs are done. Four jobs at once is the ceiling.]],

[[What the machine does to a runaway script, since you will write one. It
is never allowed to run flat out: the computer gives every job a slice of
each tenth of a second and no more, so an endless loop makes the machine
slow at that one thing and nothing else -- the prompt still answers, other
people's screens still draw, and the server never waits for it.

Output is held to twenty lines a second, so a loop that prints floods
nothing; it trickles, and the screen keeps its last hundred lines as
always. A job that spins for five minutes without ever waiting for
anything is taken away with "killed: cpu limit". A string that doubles
every turn, or a script that runs itself, meets a ceiling and stops with a
line naming it.

Jobs are not written to disk. A machine switched off, rebooted, picked up
or reloaded comes back running nothing.]],

		} },

		{ title = "14. The shell you type at", pages = {

[[The prompt speaks the language of chapter 13. Every one of them: &&, ||,
and ; between commands, if, for, while and until, $(command), $((2+3)),
single quotes, double quotes, variables, and & to put the line in the
background. There is not a smaller shell at the prompt and a bigger one
inside files -- there is one shell, and a line is a one-line script.

  admin@ksp:~$ while true; do echo tick; sleep 1; done &
  [1] 43
  admin@ksp:~$ jobs
  [1] sleeping while true; do echo tick; sleep 1; done &
  admin@ksp:~$ kill %1
  [1] killed

Multi-line constructs go on one line, all of it. There is no continuation
prompt on this machine: a line with an unfinished if or loop in it answers
"sh: syntax error: missing 'done'" and nothing runs.]],

[[Because a line is a script, the ceilings of chapter 13 are the prompt's
too. A loop you type with no end to it does not lock the machine: it
trickles at twenty lines a second like any other job, and five minutes of
spinning with no wait in it and the machine takes it away. While it runs
there is no prompt under it -- the line belongs to the job -- and Escape is
the ^C that ends it.

ps shows the shell you are typing into, because it is a job like the rest;
jobs does not, because the shell is not one of the things the shell
started. That is also why the first thing you put in the background is
[1] 43 and not [1] 42: the shell itself took 42.

Variables you set stay set, across lines and across walking away: they
belong to the machine, like the screen and the working directory. Logging
out takes them, the way it takes everything else of the session.]],

[[Two small differences from what a smaller shell would have done, both
worth knowing once. Double quotes expand what is inside them, so "$x" is
the variable and '$x' is the two characters -- if you want a literal
dollar sign, use single quotes. And a word is at most 1024 bytes; the
typing line only takes 240 characters anyway, so the only thing that ever
fills a file to its own 4096 is the editor.

Output reaches the glass at twenty lines a second, whoever wrote it. A
long listing scrolls out rather than appearing whole. That is the same
rule that keeps a runaway script from drowning the screen, and CeroSec
Systems saw no reason to have two.]],

[[Tab completes what you are typing. In the first word of a line it offers
commands -- the files in /bin you may run, and the words the shell itself
is; anywhere else it offers names on the disk, relative to where you
stand, absolute, or under ~. One match is filled in whole, with a space
after a file and a slash after a directory so the next name can be typed
straight on. Several fill in as far as they agree and stop.

  admin@ksp-04-11:~$ cat note
  note2.txt  notes.txt
  admin@ksp-04-11:~$ cat note

Press Tab again on the same word and the names are listed in columns, the
way ls lists them, with your line drawn again underneath -- which is what
happened above. A name beginning with a dot stays hidden until you type
the dot, and a directory you may not read offers nothing: completion never
names a file ls would not show you. Devices in /dev complete like any
file. Nothing completes at a question, at a password, while a script holds
the prompt, or in the editor, where Tab is still save.]],

[[Everything you type is written down, in ~/.sh_history, one line per
line, oldest first. It is yours: mode 600, in your own home, and nobody
else can read it. Answers to questions are not in it -- a password you
typed at "New password:" was never a command.

  admin@ksp-04-11:~$ history
      1  ls -l
      2  cd /etc
      3  history

history prints the last sixty with their numbers; history -c empties the
file. !! runs the last line again and !5 runs line five, and what the
machine echoes back is the line it expanded to, not the !. Up and Down at
the prompt walk the same file, so a survivor who comes back tomorrow
presses Up and finds what he typed today.]],

[[The history holds a thousand lines and sixteen kilobytes, whichever
comes first, and the oldest go over the side. Those sixteen kilobytes do
not count against the machine's 32K disk -- a shell's memory of itself
should not be the thing that fills the drive -- so df will not move
because you typed. ls -l still tells you how big the file really is.

What is free is that file, at that name, in your own home. Rename it and
it is an ordinary file: df moves by every byte of it at once, and move it
back and it is free again. Four accounts' worth is all one machine keeps
free.

Two honest notes. The numbers history prints are positions in the file as
it stands, so they shift once the oldest lines start dropping off; a
bigger machine counts them from the start of the session and never reuses
one. And ! is only read as an event when it is the whole line: there is no
quoting rule for it here, so an exclamation mark in the middle of a line
is an exclamation mark.]],

[[~/.profile runs at login, after the greeting and before the first
prompt, if the file is there and you may read it. It runs as the shell's
own job, which is exactly the point: a variable it sets is set at the
prompt, and a cd it does is where you are standing.

  admin@ksp-04-11:~$ cat .profile
  greeting=hello
  cd /var/log

Its mistakes read like a script's -- ".profile: line 2: ..." -- and it
respects every ceiling a script does. Which brings the quirk: a .profile
with an endless loop in it leaves you at a busy prompt with nothing to
type at. It is not a locked machine. Press Escape, which is the ^C, and
then edit the file. CeroSec Systems mentions it because somebody will
write that loop, and would rather he knew the way out before he did.]],

		} },

		{ title = "15. Appendix: commands and limits", pages = {

-- The one page with a "]]" inside it -- dev's usage line ends in two closing
-- brackets -- so it is the one page written with a level-one long bracket.
[=[Quick reference. Every command the machine has and exactly how it is
spelled -- the files in /bin, and the handful of words that are the shell
itself and have no file (they are named again at the end of this list);
man <command> prints the very same line back at you at the machine
itself.

  adduser [-a] <name>
  cat <file>...
  cd [dir]
  chgrp <group> <path>
  chmod <mode> <path>
  chown <user> <path>
  clear
  cp [-r] <src> <dst>
  date [+FORMAT]
  deluser [-r] <name>
  dev [kind|id [value|toggle]|find <id>]
  df
  echo [text...]
  edit <file>
  exit
  gpasswd -a|-d <user> <group>
  grep [-i] [-n] <text> <file>...
  groupadd <name>
  groupdel <name>
  groups [name]
  hash <text> [salt]
]=],

[[  halt
  head [-n N] <file>
  help
  hostname [name]
  id [name]
  jobs
  kill <id>|%<n>
  ls [-laAF] [path]
  man <command>
  mkdir <dir>
  mv <src> <dst>
  passwd [user]
  printf <format> [arg...]
  ps
  pwd
  reboot
  restart
  rm [-r] <path>...
  sh <file> [args]
  shutdown [-h|-r] [now|+N] | shutdown -c
  sleep <seconds>
  su [name]
  sudo <command> [args]

(continued)]],

[[  tail [-n N] <file>
  test <expression>
  [ <expression> ]
  touch <file>
  true
  false
  wait [id]...
  wc <file>...
  whoami
  write <file> <text>

And the words that are not files in /bin at all, because they are the
shell itself (chapter 8). The grammar:

  if then elif else fi for while until do done

The ones that change the shell or own what it started, and so could never
be a separate program:

  cd exit jobs wait read shift break continue history

help prints those two lists under the table above. Those words and help
are what the machine keeps working when /bin is gone.]],

[[Limits, all of them fixed by the machine and none of them a setting:
the disk holds 32K across at most 256 files and directories, 64 entries
in any one directory, sixteen levels below the root. One file holds at
most 4096 bytes and one line inside it at most 60 characters -- the width
of the screen itself. A path component is at most 32 characters; an
account name at most 16, starting with a lower-case letter; a group name
by the very same rule, since every account already owns the group of its
own name; a machine's own hostname at most 16 as well. su and sudo's borrowed sessions run four
deep before either refuses a fifth. motd is read to ten lines and no
further. A salt is at most 16 characters of digits and lower-case
letters, six by default.]],

[[A script has ceilings of its own, and every one of them is a line it
stops on rather than a number it quietly rounds. Sixty-four variables at
once, and one word -- the whole of NAME=value, not just the value -- at
1024 bytes. Sixteen levels of if and loop nesting, and a script that runs
another with sh goes eight deep before it is refused. Four jobs at once on
one machine, and the shell you are typing into is not one of the four. Twenty lines a second
reach the screen, and a job that has written more waits until they have.
Five minutes of spinning with no wait in it and the machine takes the job
away. Jobs are never written to disk: switching off, rebooting, picking the
computer up or reloading the world leaves it running nothing.]],

[[The editor's own two ceilings are not the same ceiling: the game's
typing box stops itself at 2000 characters typed in one sitting, and the
machine's own file limit is the same 4096 bytes as any other file --
whichever is hit first is the one that answers. The screen itself is
sixty columns by twenty rows, and its history holds the last hundred
lines written to it, oldest dropped first, across a save and a reload.
Command history is not the window's at all any more: it is
~/.sh_history on the machine's own disk, a thousand lines and sixteen
kilobytes, exempt from the 32K and capped on its own (chapter 14).]],

[[Device words, for /dev (chapter 10): an id like light0 or door1 names
the file itself; light answers on and off; lock and win answer lock
and unlock; door answers open and close; toggle, which dev takes and
a redirect does not, is whichever of a pair the device is not in now.
dev alone is the whole table, dev door, dev light, dev lock and
dev win one kind of it, dev find <id>
six seconds of the device showing you where it is; its columns are
id, description, offset from the computer, facing and state.
ls -l /dev reads exactly like ls -l anywhere else, mode, owner,
group, id, description, facing and state in place of size and date,
and no offset -- the screen is sixty columns wide.
chmod and cat work on a device the way they work on a file; rm, mv,
cp and edit do not.]],

		} },

		{ title = "16. Appendix: what the machine says", pages = {

[[Every command signs its own errors with its own name first, then the
path or word that failed, then the reason -- always in that order, and
always one line: <command>: <what failed>: <reason>. Some reasons are
shared by nearly everything that touches the disk. Each is named below,
in two words or three, with what it means directly under it.

  no such file
  is a directory
      a file command was given a directory instead
  not a directory
      a directory was expected and something else was there
  permission denied
      you may not read, write or step into it
  file exists
      something is already at that name]],

[[  invalid name
      the last part of the path will not parse
  invalid destination
      a move or copy into itself, or into its own child
  path too deep
      past sixteen levels below the root
  directory full
      the parent already holds 64 entries
  disk full
      past 32K total, or past 256 files on the machine
  file too large
      past 4096 bytes for that one file
  invalid characters
      a control byte where only plain text belongs
  is a device
      a file command met a device where a file was wanted

<command>: command not found means no file answers that name in /bin.]],

[[A file that is there but not yours to run answers permission denied
instead, never command not found -- one tells you it is missing, the
other that it is locked and exactly where.

Making anything under /dev meets a refusal naming the directory
instead of what you typed: "/dev: read-only" -- mkdir, touch and
edit all answer this way; only the engine may add a node there.

Accounts and passwords speak for themselves, one line each:

  login incorrect
      a wrong name or a wrong password, never says which
  passwd: authentication failure
      the old password did not match
  passwd: passwords do not match
      the new one was typed two different ways
  passwd: password too long
  passwd: no such user

A command run with the wrong number of arguments answers with its own
usage line instead of guessing what you meant -- the very line chapter
14 lists for it.]],

[[  su: authentication failure
  su: too many levels
      a fifth su, past the four accounts allowed
  su: <name>: no such user
  sudo: authentication failure
      one wrong answer, there is no second try
  <name> is not in the sudoers file.
  adduser: <name>: already exists
  adduser: <name>: invalid name
  deluser: <name>: no such user
  deluser: <name>: user is logged in
  deluser: root: cannot remove
  id: <name>: no such user
  groups: <name>: no such user
  chown: <name>: no such user

Groups have five of their own, and the last three are gpasswd's:

  chgrp: <name>: no such group
      no line in /etc/group, and no account of that name
  groupadd: <name>: already exists
  groupdel: <name>: cannot remove
      root, sudo and users are the machine's own
  gpasswd: <name>: no such group
  gpasswd: <name>: already a member
  gpasswd: <name>: not a member
]],

[[A device names itself, never the command that reached it -- the last
one below is dev's own, and is signed the way a command signs:

  light0: no power
  lock0: no such device
  win0: smashed
  win0: barricaded
  lock1: no padlock
  door0: locked
  door0: barricaded
  door0: blocked
  light0: invalid value
  win0: cannot toggle
  dev: <word>: unknown kind
      no current or bulb; gone or unloaded; broken; boarded;
      neither padlock nor key; held by a key; planks on it;
      a tree, a car or a body in it; a word that
      kind does not know; no opposite; the kinds are door,
      light, lock and win

  hostname: <name>: invalid name
  hash: <salt>: invalid salt
      a salt is digits and lower-case letters only
  <cmd>: <flag>: unknown option
      ls, rm, cp, grep, adduser, deluser: a flag not theirs
  chmod: <mode>: invalid mode
      neither three octal digits nor a clause in letters
  man: <name>: no manual entry
      no file of that name in /bin, or not a plain file]],

[[shutdown's own four, three about the timer (chapter 11):

  shutdown: already scheduled
      one pending order per machine, never two times
  shutdown: no shutdown scheduled
      -c with nothing to call off
  shutdown: cancelled
      not an error: what -c prints when it worked
  shutdown: no clock
      a +N with no clock to count it from

A script signs its errors with its own name and its line: <script>: line
<n>: <reason>. The parser's come first, and a file that meets one never
runs:

  syntax error: unexpected 'fi'
      a closing word where a command should be; also
      'done', 'then', 'else', 'elif', 'do', '|', '<'
  syntax error: missing 'done'
      never closed; also 'fi', 'then' and 'do'
  syntax error: bad substitution
      a $( ) in a $( ), an unclosed ${ or $(( , or a
      name between braces that is not one
  syntax error: not a name
      for wants a variable name after it
  too deeply nested
      past sixteen levels of if and loop]],

[[And the reasons a script stops on while it is running, with the
machine's own lines about jobs after them -- those are not signed by a
script, because they are not a script's to say:

  too many variables
      a sixty-fifth name
  variable too large
  word too large
      past 1024 bytes: written, built, or caught
  ambiguous redirect
      the name after > became two words, or none
  divide by zero
  bad arithmetic
  edit: not a terminal
  sleep: invalid interval
  sleep: no clock
  read: not a name
  test: unknown operator
  test: integer expected
  test: missing ']'
  test: argument expected
  sh: too many jobs
  kill: <id>: no such job
  killed
  killed: cpu limit
      Escape or kill; then five minutes of spinning
  [1] 42 -- [1] done -- [1] exit 3 -- [1] killed
      a job starting, ending, failing, taken away

Running a path that is not yours answers in the file's own name:
"./backup.sh: permission denied".]],

[[  date: no clock
      no clock at all was handed to this machine, chapter 9

A line you TYPED has no line number -- it is line one of nothing -- so the
shell's refusals wear its name and no number. Past the first level it is
in a file again (sh backup.sh) and that file's name and line come back.

  sh: <reason>
      any reason above, on a line you typed
  sh: !<n>: event not found
      !5 or !! naming nothing in ~/.sh_history, chapter 14
  history: usage: history [-c]
  syntax error: bad redirect
      a second > or >> on one line
  syntax error: unterminated quote
      a closing double quote never came
  syntax error: missing redirect target
      a > or >> with no file named after it

Two only ever seen with an empty /bin behind them:

  help: no commands in /bin: the system is damaged.
  help: switch the computer off and on to repair it.

And one that names nothing, because it was never yours -- an answer for a
question the machine no longer asks:

  cerosec: nothing to answer]],

		} },

	},
}

-- The cover, stamped with the version the OS really reports. This file loads
-- before the core does, so the concatenation cannot sit in the table above; it
-- is done here, on demand, by whoever is about to hand the book to a reader.
-- Idempotent, and there is no second place the number is written.
function CeroSecManual.stampVersion()
	CeroSecManual.title = "CeroSec OS " .. CeroSecOS.VERSION .. " User's Manual"
	return CeroSecManual
end
