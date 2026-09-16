-- CeroSec OS, Volume 2: the System Administrator's Guide.
--
-- The second of the three books CeroSec Systems shipped with a machine in 1993.
-- Volume 1 taught the screen, the prompt, the disk and the small tools, for
-- somebody who had never sat at one. This one is for whoever is made responsible
-- for a machine OTHER PEOPLE use: root and sudo, the accounts, the groups, the
-- files that ARE the machine, the firmware's repair, the building on the other
-- end of /dev, the work the machine does with nobody standing at it, and the
-- other computers down the coax. Volume 3 is scripts, jobs and pipes.
--
-- The shape of a page is the reader's, not this file's: plain ASCII, "\n\n"
-- between paragraphs (a single "\n" is a soft break the reader reflows), a line
-- beginning with two spaces is a screen and is kept monospace and so must fit
-- the machine's own sixty columns, and no page runs past a thousand characters.
-- tests/manual_test.lua checks every one of those, and checks the transcripts
-- and the reference card against the engine itself.
--
-- Every transcript in here was taken off a running engine under lua5.1 -- the
-- prompt driven the way tests/os_test.lua drives it, with a fake world handed in
-- as env.devices and env.net where the engine alone could not answer. Where a
-- real line is wider than the glass the machine wraps it, and a wrapped line is
-- too wide to PRINT in a sixty-column book: those few are described in prose and
-- shown in their schematic form instead of being cut down and called a screen.
--
-- The cover is NOT written here. The reader stamps it from the engine's own
-- version number once the core is loaded; nothing in this file may name a
-- version, and nothing in this file may touch CeroSecOS at load time -- the
-- game loads shared/cerosec/ ahead of shared/cerosec/os/.

-- Both lines are written defensively so this file does not care which of the
-- three volume files the game loads first: none of them may assume it is the one
-- that creates the table. (CeroSecManual.lua, which used to be a book of its own,
-- is now the same two lines and nothing else.)
CeroSecManual = CeroSecManual or {}
CeroSecManual.volumes = CeroSecManual.volumes or {}

CeroSecManual.volumes[2] = {
	id = "admin",
	title = nil,
	name = "System Administrator's Guide",
	edition = "First Edition, 1993",
	chapters = {

		{ title = "1. The administrator's chair", pages = {

[[This is the second of three books, and it is the one for whoever the
office has made responsible for the machine.

Volume 1 was written for a person with one account and his own files in
it. This one is written for the person who made that account. It assumes
you have read Volume 1, or have sat at one of these long enough not to
need it: the prompt, the editor, ls and cat and chmod are taken as known
from here on, and where this book needs one of them it uses it without
stopping to explain.

What is in it is everything a machine does for other people. The two
powers, root and sudo. The accounts and the groups. The handful of files
that ARE the machine, so that editing one changes it. The firmware, and
what it can put back. The building the machine is wired to. The work it
does at four in the morning. And the other computers down the wire.

Volume 3, the Programmer's Guide, is scripts, jobs and pipes. Where this
book needs a line of shell it writes one and points you there.]],

[[There are two accounts on a fresh machine, and not the same kind of
thing.

admin is an account. It owns its home, it reads what it is allowed to
read, and when it is refused the machine says so.

root is not an account so much as the absence of one. Every permission
check begins by asking whether the caller is root, and nearly always
stops there. Root reads a file at mode 600 it does not own. Root writes
/etc/passwd. Root deletes /bin. Root walks into any directory at all.

A mode says one thing to root, and it is the x bit: a file with no x bit
anywhere is one NOBODY may run, root included -- real Unix is the same.
So chmod 600 /bin/ls takes ls away from root too. Root can chmod it back,
and that is the difference.

The rest of this chapter is about not being root longer than you have to.
A machine cannot protect you from root; that is not what it is for.

  root@ksp-04-11:~# whoami
  root
  root@ksp-04-11:~# rm -r /bin

Two lines, and the second one is a machine that will not boot.]],

[[Do not work as root.

Log in as admin. Do the administrator's work with sudo, one command at a
time, and let the machine put the word root in front of every line where
it really matters. A root prompt left open on a desk is a machine anybody
walking past owns, and a typo typed at a root prompt is a typo with
nothing between it and the disk.

You can tell the two apart without reading the name, which is the point
of the last character of the prompt:

  admin@ksp-04-11:~$ su
  Password:
  root@ksp-04-11:~# whoami
  root
  root@ksp-04-11:~# exit
  admin@ksp-04-11:~$ whoami
  admin

A dollar sign is an ordinary account. A pound sign is an account whose
line in /etc/passwd carries the admin flag, and root's does. Chapter 2 is
where we are honest about what that flag does and does not grant.

Note what exit did there. It did not log anybody out.]],

[[su, and the stack behind it.

su becomes somebody else at this glass. With no name it means root. It
asks for the TARGET's password, which is what su has always asked for,
and root is asked for nobody's.

What makes it more than a convenience is that the machine remembers who
it was. Every su pushes the account you were, and where you were
standing, onto a stack; exit pops one off; only an exit with nothing left
on the stack logs the glass out. The stack belongs to the MACHINE and not
to the window, so walk away three deep and come back three deep, tomorrow
or next week.

  root@ksp-04-11:~# su bob
  bob@ksp-04-11:~$ su kate
  Password:
  kate@ksp-04-11:~$ exit
  bob@ksp-04-11:~$ exit
  root@ksp-04-11:~#

It stacks four deep, and a fifth is refused:

  root@ksp-04-11:~# su root
  su: too many levels

One wrong password is the end of it. There is no second try, because
somebody had to be standing at the keyboard to type the first.]],

[[sudo, and the file that says who may.

sudo runs ONE command as root and then it is over. It asks for YOUR OWN
password, not root's, which is the whole idea: you are proving you are you
and not that you know the machine's most valuable secret.

  admin@ksp-04-11:~$ sudo whoami
  [sudo] password for admin:
  root
  admin@ksp-04-11:~$ whoami
  admin

Who may is /etc/sudoers, one name a line, and a fresh machine has admin on
it. Anybody else gets one line and it names him:

  bob@ksp-04-11:~$ sudo whoami
  bob is not in the sudoers file.

One wrong answer is sudo: authentication failure, and there is no second
try. Put the single word NOPASSWD after a name in that file and the
account is never asked at all, which is convenient and is also a password
you have decided not to have. Chapter 10 has our advice.]],

[[Three things sudo does not do, each of which somebody writes to us
about.

It does not move you. The command runs as root in the directory you were
standing in; whoami afterwards still says admin.

It cannot run a word the shell itself is. sudo runs a PROGRAM, and cd,
exit, fg, jobs and wait have no file in /bin for it to find:

  admin@ksp-04-11:~$ sudo cd /root
  [sudo] password for admin:
  sudo: cd: command not found

sudo exit says the same, and so does a name the machine has not got:
sudo: lights: command not found. sudo went looking, so sudo signs it.

And it does not give out a root prompt -- except where you ask for one
on purpose. sudo su is a root shell at this glass, on the same stack exit
pops; sudo su bob is bob's shell without knowing bob's password.

Classic mistake. sudo su first thing in the morning and working there all
day: every hazard of being root, none of the protection sudo was bought
for. Type sudo in front of the six lines that need it.]],

		} },

		{ title = "2. Accounts", pages = {

[[An account is a line in a file, and the file is /etc/passwd.

There is no separate list of users anywhere on this machine. What is in
that file is what accounts exist. Root editing it with the editor changes
who may log in; root deleting it is a machine nobody can log in to at all,
which the firmware treats as a machine with no operating system.

It is root's, and it is mode 600, so admin cannot even read it. Look at it
with sudo:

  admin@ksp-04-11:~$ sudo cat /etc/passwd

Four fields, separated by colons, one account a line:

  name:$cs1$<salt>$<32 hex digits>:home:admin|user

A real line is wider than the sixty columns of the glass and the machine
wraps it across two rows. That is not damage and the file has one line per
account however it looks. Do not "tidy" a wrapped line in the editor.]],

[[The four fields, in order.

The name. Lower-case letter first, then lower-case letters, digits,
underscores and hyphens, up to sixteen characters. That is the name the
machine will MAKE; a machine that has been running a while may have been
given stranger ones by hand, and it keeps them.

The password, and it is not the password. $cs1$ names the scheme, then a
salt, then thirty-two hex digits which are what your password turns into.
It does not turn back. Nobody at CeroSec Systems and nothing on this
machine can tell you what a password was -- only whether one you typed is
the same. The salt is why two accounts with the same password do not look
alike on the disk. You can watch the machinery work:

  admin@ksp-04-11:~$ mkpasswd knox 42f7pl
  $cs1$42f7pl$b36c5193655e2d64e38523e242fb7fa8

Give mkpasswd no salt and it makes a fresh one, so the line is different
every time you ask. That is the salt doing its job, not the machine being
unreliable.]],

[[An EMPTY second field is an account with no password, and an account
with no password is a way in. Press Enter at password: and you are it.
Both shipped accounts start that way. Chapter 10 says what to do about it
and this is the page that says why.

The home. An absolute path, and it is where the account lands at login and
what a bare cd goes to. Nothing checks that it exists; an account whose
home has been deleted logs in and stands at the root of the disk.

The flag, admin or user, grants nothing by itself: no command consults it,
and its one visible effect is the pound sign on the prompt. What it REPORTS
is whether the account is in the group wheel -- and wheel is what grants,
because the shipped /etc/sudoers carries a %wheel line. usermod -G writes
this field from that membership, so the two never disagree.]],

[[Making one. useradd is root's, and it does three things: writes the
line, makes the home, and says out loud that the account is open.

Try it.

  root@ksp-04-11:~# useradd bob
  useradd: bob: created
  useradd: set a password with passwd bob

Do the second line now, not later. Between those two commands bob is an
account anybody in the office can log in to by pressing Enter.

  root@ksp-04-11:~# passwd bob
  New password:
  Retype new password:
  passwd: password updated

useradd -G wheel makes an administrator: wheel is the group /etc/sudoers
grants, so he may sudo. A name it will not make it says so about:

  root@ksp-04-11:~# useradd bob
  useradd: bob: already exists
  root@ksp-04-11:~# useradd Kate
  useradd: Kate: invalid name

A home directory that is already there is ADOPTED rather than remade: it
changes hands and keeps everything in it. Somebody's files are not an
obstacle to giving him an account.]],

[[Unmaking one, and this is where care is owed.

  root@ksp-04-11:~# userdel kate
  userdel: kate: removed

That takes the line out of /etc/passwd, and takes the name out of
/etc/sudoers with it -- a name left in that file is a line waiting for
whoever is given the name next. It does NOT touch the home directory. His
files stay exactly where they were, owned by a name the machine no longer
knows, and ls -l shows it. That is the truth rather than a tidy lie about
whose files those were.

  root@ksp-04-11:~# userdel -r kate

-r takes the home with it. There is no wastebasket.

Two refusals, and both are the machine looking after you:

  root@ksp-04-11:~# userdel root
  userdel: root: cannot remove
  root@ksp-04-11:~# userdel admin
  userdel: admin: user is logged in

Root is the way back into the machine, so it is not one of the accounts.
And no account is pulled out from under a live session, including one the
glass would come back to through exit.]],

[[Asking about an account, which anybody may do about anybody.

  admin@ksp-04-11:~$ id
  uid=admin flag=user groups=admin,sudo,users
  admin@ksp-04-11:~$ id bob
  uid=bob flag=user groups=bob
  admin@ksp-04-11:~$ groups bob
  bob

id is the whole of what the machine knows: the name, the flag from the
last field, and every group. groups is the same list with blanks instead
of commas. Neither is a secret: who may become root is a file the machine
reads out loud at every sudo, and there is nothing to be gained by making
it hard to look at.

passwd with no name changes your own and asks for the old one first. Root
is asked for nobody's old password -- its own included -- and root is the
only account that may change somebody else's.

Classic mistake. Running useradd, being interrupted, and coming back
tomorrow. The account has been sitting there with no password all night,
and the machine told you so at the time, in the second line it printed.
Read the second line.]],

		} },

		{ title = "3. Groups, and sharing a file", pages = {

[[A group is how two accounts come to share one file, and it is another
file: /etc/group, root's, mode 644, one group a line.

  admin@ksp-04-11:~$ cat /etc/group
  # name:member,member,... -- one group a line
  # every account is also in a group of its own name
  root:
  sudo:admin
  users:admin

A name, a colon, and the members separated by commas. Blank lines and
lines beginning with # are comments. Everybody may read it, which is why
it is 644 and why id can answer about anybody.

A machine ships with three. root: has nobody in it. sudo is the group the
devices in chapter 6 belong to. users is the ordinary one, and admin is in
it.

Both comment lines at the top are the machine's own, and the second is the
rule the rest of this chapter turns on.]],

[[Every account is in a group of its own name, and there is no line
anywhere that says so.

bob is in group bob whether /etc/group mentions him or not. That is his
PRIMARY group, useradd writes nothing for it, and it is what a fresh file
of his is shared with -- which is to say, nobody.

The consequence catches everybody once. A primary group is not a
membership somebody granted, so it is not one anybody can grant or take
away:

  root@ksp-04-11:~# groupdel bob
  groupdel: bob: no such group
  root@ksp-04-11:~# usermod -G bob bob
  root@ksp-04-11:~# groups bob
  bob

The refusal means "there is no LINE for that, and there never will be", and
the usermod moved nothing for the same reason.

It is also what makes chgrp bob something worth typing: handing a file to
bob's primary group hands it to bob and to nobody else.]],

[[Three commands, all root's.

Try it, and watch the file change under it.

  root@ksp-04-11:~# groupadd crew
  root@ksp-04-11:~# usermod -G crew bob
  root@ksp-04-11:~# usermod -G users,crew admin
  root@ksp-04-11:~# cat /etc/group
  # name:member,member,... -- one group a line
  # every account is also in a group of its own name
  root:
  sudo:admin
  users:admin
  wheel:
  crew:bob,admin
  root@ksp-04-11:~# groups bob
  bob crew

groupadd appends a line. usermod -G SETS the lines a name is on: the list
is what he is in afterwards, and a group he was in that is not on it is one
he has left. It will not take an empty list. Every other line of the file
is kept as it lies, comments and all.

  root@ksp-04-11:~# groupadd crew
  groupadd: crew: already exists
  root@ksp-04-11:~# groupdel users
  groupdel: users: cannot remove

root, wheel, sudo and users are the machine's own and cannot go.]],

[[The three digits, for real this time.

A mode is three octal digits and the machine reads exactly ONE of them:
the first if you own the file, the second if you are in its group, the
third otherwise. Root is judged by none of them. An owner is judged by the
first digit and the other two are never consulted for him, even when he is
in the group as well.

So a shared folder is two commands and a recipe worth copying:

  admin@ksp-04-11:~$ mkdir shared
  admin@ksp-04-11:~$ chgrp crew shared
  admin@ksp-04-11:~$ chmod 770 shared
  admin@ksp-04-11:~$ ls -l
  drwxrwx---  admin  crew        0  Jun 27 13:12  shared

770 is: I may read, write and step in; so may anybody in crew; and
everybody else may do nothing at all. The third digit matters most, since
7 there would have let the whole office in.

Files inside it want the same treatment -- 660, since a file needs no x --
and chgrp only takes a group that exists:

  admin@ksp-04-11:~$ chgrp nosuch shared
  chgrp: nosuch: no such group]],

[[Two loose ends.

A group can be deleted while files still name it. Nothing walks the disk
to tidy up, so the name stays on the file, dangling: nobody is in it, so
the middle digit now grants nothing, and the machine will not hand the
name out again.

  root@ksp-04-11:~# groupdel crew
  root@ksp-04-11:~# ls -l /home/admin
  drwxrwx---  admin  crew        1  Jun 27 13:12  shared
  root@ksp-04-11:~# chgrp crew /home/admin/shared
  chgrp: crew: no such group

That is recoverable -- groupadd crew and the line is back.

The other is the group called sudo, which is the one place two files meet.
/etc/sudoers stays the authority on who may run a command as root, and the
sudo group MIRRORS it: a name in that file is in the group whether
/etc/group says so or not. It is the group the devices belong to.

Classic mistake. Putting somebody in the sudo group by hand and believing
you have given him root. You have given him the devices and the group's
files. Only a line in /etc/sudoers gives out root.]],

		} },

		{ title = "4. The system files", pages = {

[[A machine is a filesystem and nothing else.

There is no table of accounts beside /etc/passwd, no list of commands
beside /bin, no list of groups beside /etc/group. Each of those files IS
the thing. Root editing one with the editor changes the machine, and root
deleting one breaks it as far as the file mattered.

  root@ksp-04-11:~# ls -l /
  drwxr-xr-x  root   root       66  Jan  1 00:00  bin
  drwxr-xr-x  root   root        1  Jan  1 00:00  dev
  drwxr-xr-x  root   root        7  Jan  1 00:00  etc
  drwxr-xr-x  root   root        1  Jan  1 00:00  home
  drwx------  root   root        0  Jan  1 00:00  root
  drwxr-xr-x  root   root        4  Jan  1 00:00  var

bin is the commands, etc is the machine's own answers about itself, var is
what it writes about itself, dev is the building, home is everybody's
files, and /root is root's own at mode 700.

There is no guard rail on any of it. The way back is the firmware, and the
protection is that root has a password.]],

[[/bin is not a list of commands. It is the commands.

One file per command, owner root, mode 755, whose contents are the one
line help prints about it:

  root@ksp-04-11:~# ls -l /bin/ls
  -rwxr-xr-x  root   root       16  Jan  1 00:00  ls
  root@ksp-04-11:~# cat /bin/ls
  list a directory

So this is not a demonstration. It is a machine losing a command:

  root@ksp-04-11:~# rm /bin/ls
  root@ksp-04-11:~# ls
  ls: command not found

And a mode is enough on its own. chmod 600 /bin/ls leaves the file there
and every account, root included, gets ls: permission denied instead: a
file with no x bit anywhere is one nobody may run, and the repair below
is the way back. One says the command is missing; the other that it is
locked.

An empty /bin is a machine with no operating system as far as the firmware
is concerned, and help knows it: asked on a machine with nothing in /bin
it says the system is damaged and to switch the computer off and on.
That is the repair, and it is the next chapter.]],

[[What the firmware's repair does to /bin, since it belongs here as much
as there: it rewrites every standard command, every time, without asking
-- back to owner root, mode 755 and its shipped description. Missing,
damaged and merely chmod'd out of reach all come back the same.

  root@ksp-04-11:~# chmod 600 /bin/ls
  root@ksp-04-11:~# ls -l /bin/ls
  -rwxr-xr-x  root   root       16  Jan  1 00:00  ls

That is after the repair, and it is a feature: a machine cannot be locked
shut by a mode.

A file of your own in /bin is left where it is. And there is a quieter
top-up that is not the repair at all. Every machine carries the number of
the system it was built with, and one loaded on a newer release has the
commands it is missing written in once and the number moved up. A machine
already at the current number gets nothing at all, which is what keeps
root's rm /bin/ls a deletion rather than a suggestion.]],

[[/etc, file by file.

  root@ksp-04-11:~# ls -1 /etc
  group
  hostname
  hosts
  hosts.equiv
  issue
  motd
  passwd
  sudoers

Eight files, and that is the whole machine's own account of itself. Add ls
-l to see the modes: every one of them is 644 except passwd, which is 600,
and sudoers, which is 440 -- root may not write that one without meaning
to, which is a small brake worth having on the file that hands out root.

passwd is chapter 2, group is chapter 3, hosts and hosts.equiv chapter 8.

/etc/hostname is the machine's name: one to sixteen characters of
lower-case letters, digits and hyphens.

  root@ksp-04-11:~# hostname gate-02
  root@gate-02:~# hostname
  gate-02

Root only, and the name is in the prompt of every screen at the machine
the moment it changes. Give it a name you can shout across an office.]],

[[/etc/issue is printed OVER the login prompt and /etc/motd under it, and
the difference is who reads them: the issue is read by a man who is not
in yet, the motd only by an account that got in. A bank and an army post
warn in the first for that reason.

The issue ships naming the system and the machine, and `hostname`
rewrites that line until you edit it yourself. /etc/motd is ten lines at
most. An empty one is a silent login, and so is an empty issue.

/var is what the machine writes about itself, and there are four
directories in it:

  root@ksp-04-11:~# ls -l /var
  drwxr-xr-x  root   root        0  Jan  1 00:00  log
  drwxr-xr-x  root   root        0  Jan  1 00:00  mail
  drwxr-xr-x  root   root        1  Jan  1 00:00  spool
  drwxrwxrwx  root   root        0  Jan  1 00:00  tmp

/var/log/cron and /var/log/wtmp are the two logs, chapters 7 and 8.
/var/mail holds one mailbox per account. /var/spool/cron holds the
crontabs, at mode 700 so that nobody reaches his own by hand.]],

[[/var/tmp is the one directory anybody may write in, and it wears a rule of
its own to make that safe. Everywhere else, a directory you may write in
is one you may delete from. Here, only the owner of a file -- or root --
may remove it or rename it out again.

  bob@ksp-04-11:~$ ls -l /var/tmp
  -rw-r--r--  admin  admin       4  Jun 27 13:12  mine.txt
  bob@ksp-04-11:~$ cat /var/tmp/mine.txt
  mine
  bob@ksp-04-11:~$ rm /var/tmp/mine.txt
  rm: /var/tmp/mine.txt: permission denied

Bob may read it, may write his own beside it, and may not take it away.
The rule belongs to the PLACE: a copy of it elsewhere is an ordinary file.

/dev is the building, and it is chapter 6. Nothing may be created there:
mkdir, touch and edit under it all answer /dev: read-only.

Classic mistake. Editing one of these files while logged in as root and
saving a line that will not parse. A line that will not parse is SKIPPED,
in silence, by every one of these files. Read your file back with cat
after you save it.]],

		} },

		{ title = "5. The firmware, and repairing a machine", pages = {

[[Before the operating system there is the firmware, and it has its own
version number that has nothing to do with the system's. It is what prints
the four lines Volume 1 chapter 1 describes, and it is what looks at the
disk before it hands over.

If what it finds is not a working system, it says so and offers to mend
it:

  No operating system found.
  Restore system? (y/n)

It means one of a very few things, and each takes root and some
determination. /bin is missing, or is not a directory, or is empty.
/etc/passwd is missing, or is not a file, or parses to no accounts at all.
Or the disk itself no longer makes sense.

y repairs it. n leaves it exactly as broken as it was, and the refusal
belongs to the MACHINE and not to your window: the next person to open a
screen on it finds the refusal and not a fresh question. Anything else
brings the question back. Escape walks away without answering and the
machine will ask again.

Say y. The next page is why there is nothing to weigh.]],

[[What a repair rewrites, without asking and every time: every standard
command in /bin, back to owner root, mode 755 and its shipped one-line
description.

What it puts back only when it is missing or names nobody at all:
/etc/passwd, /etc/sudoers and /etc/group. A passwd file that still names
one account is left as it lies, hashes and all -- no password is reset by a
repair. /etc/hostname, /etc/motd and /etc/issue are made if absent and
never touched.

What it never touches: /home and /root. Not the files, not a history, not
a .profile, not a thing.

Try it, on a machine you have just broken on purpose.

  root@ksp-04-11:~# rm -r /bin
  root@ksp-04-11:~# ls
  ls: command not found

Switch the machine off and on, answer y, and:

  root@ksp-04-11:~# cat /home/admin/notes.txt
  knox

Running it twice changes not one byte. It is not a disk doctor: if
something else is wrong the machine comes back to the same question,
because what it mends is the system files.]],

[[Switching a machine off, in words instead of by hand.

Both are root's: a second survivor standing at the same glass loses his
session, and that is not an ordinary account's to take. Nothing is lost
either way -- it is all on the disk.

  admin@ksp-04-11:~$ shutdown
  shutdown: permission denied
  root@ksp-04-11:~# shutdown

shutdown switches the machine off: the screen goes, the glow goes, every
window open on it closes. halt is its older name, and is shutdown -h now.

reboot is a power CYCLE, and shutdown -r now says it the long way: off the
same way, dark about three seconds, then on again by itself. Stay at the
keyboard and your window comes back where it was; step away while it is
dark and it comes up without you. A room that loses its power in those
seconds leaves the machine off, as an outage leaves any machine off.

Neither is a repair: the disk comes through untouched. What mends a
machine whose /bin is empty is the firmware's question on the way back up,
not the power.]],

[[shutdown also takes a time, which is how you clear a machine other people
are working at.

-h halts and -r reboots; with neither, it halts. now, and no time at all,
are the same thing. +N is N minutes from now, up to a day.

  root@ksp-04-11:~# shutdown -r +5
  [1] 44
  The system is going down for reboot in 5 minutes!

Every screen standing at the machine gets that line, gets it again one
minute before, and once more as the machine goes:

  The system is going down for reboot in 1 minute!
  The system is going down for reboot NOW!

A PENDING ORDER IS A PROCESS. That is the [1] 44: a job, with an id,
owned by the account that gave it. ps and jobs show it, and you call it
off the way you stop any process.

  root@ksp-04-11:~# jobs
  [1] waiting  shutdown -r +5
  root@ksp-04-11:~# kill 44

kill says nothing, which is kill. Root may, and so may the account that
ordered it; nobody else. There is no shutdown -c here: that flag is
another kind of Unix's, and this one had a process table.]],

[[Two honest limits on that timer, and one on the machine.

Two orders at once are allowed, because two processes are: both warn, and
the first minute to arrive wins. What bounds them is the job book.

The order lives on the MACHINE and not in your window: close the window,
walk away, come back, and it is still counting down. But it is not written
to the disk. The power going out, the computer being carried off, or the
world being loaded again all forget it and the machine stays up: this
computer keeps no list of running work on its disk.

The power going out is not gentle either: the screen clears, anything
unsaved in the editor is gone, and the disk is as it was. A computer that
is picked up keeps its disk and loses its screen.

Classic mistake. Typing shutdown at the end of the day on a machine
somebody else is logged into, having read this far and not chapter 8. Type
who first. It takes two seconds and it lists everybody.]],

		} },

		{ title = "6. The building, through /dev", pages = {

[[This is the chapter that makes the machine worth having.

The building it stands in is wired to it, and wired is the word: under
/dev there is one file for every fixture somebody has screwed a module
to, and writing a word into one of them works the thing itself. The
modules are the next page.

The reach is the BUILDING: every room of it, upstairs and down; ten tiles
of its own floor every way where the map knows none. 256 at the outside.

  root@ksp-04-11:~# dev
  curtain0 office               1E 0        N  closed
  door0   exterior              0 5S        W  locked
  door1   kitchen-hallway       2W 1N       N  closed
  gen0    exterior              6E 3S          off
  light0  office                0 0            on
  lock0   exterior              0 5S        W  locked
  stove0  kitchen               2W 2N          off
  tv0     office                2E 1N          on
  win0    office                1E 0        N  locked
  window0 office                1E 0        N  closed]],

[[The nine modules, and what each one buys.

Nothing in that table is there because it is a door, but because somebody
went up to it with a screwdriver and a box:

  magnetic contact  the machine can SEE a door or a window
  relay             it can throw a light switch
  electric strike   it can work a door's lock
  door operator     it can open and shut a door
  curtain motor     it can draw and open a curtain
  window operator   it can raise and shut a sash
  appliance switch  it can start a stove or a washer
  generator switch  it can start and stop a generator
  tuner control     it can work a television or a radio set

A door with only a contact on it is a doorN you can read and cannot move.
An operator opens it; a strike adds the lockN beside it.

If your server turned the option Hardware modules required OFF, forget all
this: every fixture in the building is under /dev, fitted or not.]],

[[Windows are two devices and they are not the same device.

winN is the magnetic contact. It is a SENSOR and it senses: smashed,
barricaded, open, locked or unlocked, in that order -- the glass, then the
sash, then the catch -- so open beats locked the way a door's does, and
unlocked means shut. Nothing is written to it.

windowN is the window operator, and it is the sash. It reads smashed,
barricaded, sealed, open or closed, and it takes open and close.

  root@ksp-04-11:~# dev window0
  window0: closed
  root@ksp-04-11:~# dev window0 open
  window0: open

sealed is a window the building was built never to open, and no motor
will change that. The operator will not move a boarded window either --
nothing on this machine takes planks off anything.

An earlier printing of this book said no machine could ever work a sash.
That was wrong, and the next page says what is true instead.]],

[[THE WINDOW OPERATOR SETS OFF A HOUSE ALARM. Read this before you fit
one.

A motor on a sash does three things and only one of them is opening the
window. It also throws the catch -- a window the machine opens comes open
whether it was latched or not, so a winN that read locked reads unlocked
afterwards. And in a house whose alarm was still armed when the power
came back, opening the window RINGS IT, every time, exactly as a hand
through the glass would.

That is not a fault and it is not something the machine can be told not
to do: it is what a window opening in an alarmed house does, and this
machine is a machine and not a burglar with a key.

So: `0 6 * * * echo open > /dev/window0` in a house nobody has cleared is
a horde at six in the morning. Open one by hand first and find out.

Closing a window never rings anything.]],

[[Curtains, stoves and the laundry.

curtainN is a sheet: open and closed, open and close. Both kinds are the
same device -- a curtain hanging in a window, and the sheet somebody
draped over a door, which the game keeps ON the door itself. Boarded over,
it answers curtain0: barricaded.

stoveN is an oven, a microwave OR a coffee machine, which are one thing as
far as this building is concerned. It reads on, off or broken and takes on
and off. No current at the socket is stove0: no power, the same words a
light switch uses, and a stove somebody has wrecked is broken and stays
broken.

  0 5 * * * echo on > /dev/stove0

washerN is a washer, a dryer or a machine that is both. on and off, and
no power when the grid is down.

The timer and the temperature on an oven are the survivor's, set at the
oven. The machine only throws the switch.]],

[[genN is a generator, and it is the one device that has more to say than
a word:

  root@ksp-04-11:~# cat /dev/gen0
  on fuel 62 condition 80 connected

Both numbers are percentages. connected is there when something is
plugged into it and absent when nothing is. The tables print the first
word only -- there is no room in them for a sentence -- so cat it, or
dev gen0, when you want the rest.

It takes on and off. Starting one is refused three ways and each is worth
knowing before you write the crontab line:

  gen0: not connected    nothing is wired to it
  gen0: no fuel          the tank is empty
  gen0: broken           its condition is nothing

Stopping one is never refused. And it will not pull a cord: a survivor
starting a worn generator fails about half the time, and an electric
starter does not, so a machine starts anything the three refusals let it.]],

[[tvN is a television and rxN is a radio set. A tuner control on either
gives you its switch and its dial.

  root@ksp-04-11:~# cat /dev/tv0
  off channel 203
  root@ksp-04-11:~# echo on > /dev/tv0
  root@ksp-04-11:~# dev tv0 channel 210
  tv0: on channel 210

on and off are the switch. channel and a NUMBER is the dial, and it is
the only order on this machine that is not one word: four words at dev,
where everything else takes three.

The number is the set's own, the one the game tunes by. 203 is Life and
Living TV; a kitchen radio reaches 88000 to 108000. /dev/radio0 prints
megahertz because nothing is ever written to it, and a dial you can
write has one spelling.

  tv0: no power      no grid, or the battery is flat
  tv0: out of range  that set's dial does not go there

A ham set your machine is wired to keeps its /dev/radio0 as well. The
aerial is yours to tune; the receiver is the machine's. So is the
switch, and the volume never is.]],

[[Where a box comes from.

Nobody works these out at the bench. The diagrams and the parts lists went
out with the fitters, in the CeroSec Field Wiring Guide: look on an
electronics shop's rack, in a bookshop, a tool shop, an electrician's van.
Find a copy and READ it, and all of it appears in the Electrical tab. A
lifetime electrician gets there in the end. Everybody else reads it.

Four of the eight are built round a SMALL MOTOR, and Knox County never
sold one on its own. The guide has the two recipes for that too: take a
screwdriver to a hair dryer, a pair of sheep shears, a CD player or a
blower fan and the motor comes out, with the electronics scrap you would
have got anyway.]],

[[Fitting a box, and taking it off.

Right-click the FIXTURE itself -- the door, the window, the switch, the
curtain, the oven, the washer, the generator -- and not the computer, and
take CeroSec hardware. You need the box, a screwdriver and the trade: a
contact or a relay at 1, a strike, a curtain motor, an appliance switch
or a tuner control at 2, the two operators and the generator switch at 3.

The list names every box that could go on that SORT of thing, whether you
have one or not, and each line says what it does and which device it
gives. One you have not got is greyed and says so, or says to go and read
the Field Wiring Guide. A box that could never fit is not listed.

Two are greyed for what the fixture IS:

  a strike on an interior door: a key stops nobody
  an operator on a garage door: one leaf would move

A boarded window and a broken stove are NOT greyed: that is what the
fixture does today, not what it is.

Remove gives the box back whole, and the NUMBER stays.]],

[[With the door open, and from inside.

A box goes on the building's SKIN -- a door, a window, a curtain -- only
from INSIDE, or anybody walking past strips the hardware off your front
door without coming in. On the pavement those entries are greyed. An
interior door has a room on both sides and is wired from either.

Nothing else asks where you stand: a porch lamp, a generator, an oven in
the yard are fitted from where they are.

And the thing has to be at rest:

  a door, a window          open
  a curtain, a door's sheet drawn back
  a stove, a washer, a set  switched off
  a generator               stopped

Taking a box off asks the same. A light switch asks nothing at all: the
plate comes off with the light burning.

If your server turned SAFEHOUSE MEMBERS ONLY on, a fixture inside a
safehouse takes a box, and gives one back, only for its owner, its
members or an admin. It is off unless somebody turned it on, and a
single-player game has no safehouses.]],

[[Reading that table.

The id is what you name the thing by. The kinds are curtain, door, gen,
light, lock, rx, sensor, stove, tv, washer, win and window, plus fd0 and
radio0, which are the machine's own. Then the rooms it stands between, in the
map's own raw words: exterior where one side is the outdoors, built for
something a player put up.

Then where it is from where the computer stands: tiles east or west, tiles
north or south, 0 0 for the computer's own square, and +1 or -1 for a
floor that is not this one. That column is how you tell two devices apart
when the room names do not.

Then which way it faces, and then its state.

The table runs by kind and then by number, so light2 comes before light10.
A mall is ONE building, so /dev is the one directory the 96-entry rule
does not hold for. In a big building one kind at a time is easier to read:

  root@ksp-04-11:~# dev light
  light0  office                0 0            on
  light1  hallway               3E 2N          off]],

[[Working one. An id on its own reads it back; an id and a word works it
and then reads back what it became.

Try it.

  root@ksp-04-11:~# dev light0
  light0: on
  root@ksp-04-11:~# dev light0 off
  light0: off
  root@ksp-04-11:~# dev light1 toggle
  light1: on
  root@ksp-04-11:~# dev door1 open
  door1: open

toggle is whichever of the pair it is not in now. Nearly every kind
knows two words: light, stove, washer, gen, tv and rx take on and off;
lock and win take lock and unlock; door, window and curtain take open
and close. tv and rx know channel as well, which carries a number. A
word from the wrong kind never reaches the building.

When you cannot tell which of thirty-five lights is the one in the
listing, ask it to show itself:

  root@ksp-04-11:~# dev find light0
  light0: blinking
  root@ksp-04-11:~# dev find door1
  door1: highlighted

A light blinks for six seconds and goes back exactly as it was found. A
door has nothing to blink with, so it is outlined on your screen instead.]],

[[Doors and keys, honestly.

door0 and lock0 in that first listing are one door twice over: the thing
that opens, and the key holding it shut. Only a door a lock can really
stop somebody at gets the second row, because a key stops somebody who is
OUTSIDE a building and nobody inside. So exterior doors and built doors
have a lockN and interior doors do not.

The computer is not a key. A locked door stays shut:

  root@ksp-04-11:~# dev door0 open
  door0: locked
  root@ksp-04-11:~# dev lock0 unlock
  lock0: unlocked
  root@ksp-04-11:~# dev door0 open
  door0: open

A padlock is the other way round. It does not hold a door against a hand;
it protects what is BEHIND the door from anybody without its key, which on
a player-built door is the whole point. Taking one off is dev lock1 unlock
and putting it back is dev lock1 lock.

And unlocking is not opening. unlock takes the key off; somebody still has
to walk over and open the door -- or the machine does, on the next line.]],

[[Motion sensors, the one device you supply yourself.

The part is a Motion Sensor: the module, out of a house alarm or off a
shelf. DROP one on the floor of a room this machine can reach and it
becomes a sensorN. Pick it up and the device is gone.

  root@ksp-04-11:~# dev sensor
  sensor0 office                1E 0           clear
  sensor1 store                 4E 2S          motion
  root@ksp-04-11:~# cat /dev/sensor0
  clear

It watches its own room out to THREE TILES, never through a wall, so a head
in the hall tells you nothing about the kitchen. Where there is no room at
all it watches three tiles every way and reads built.

Movement closes it for five seconds; then it opens. So a zombie that walks
in and STOPS reads clear five seconds later. It is movement it sees and not
bodies, which is why a script polls one.

Mode 440, cr--r-----, and nothing may be written to it.

A sensor taped to a BOMB is not one of these, whatever the shape of it.]],

[[Underneath, dev is cat and a redirect. Same permissions, same words,
same refusals:

  root@ksp-04-11:~# cat /dev/light0
  off
  root@ksp-04-11:~# echo on > /dev/light0

which is what makes a device something a crontab line or a script can
write to, and chapter 7 depends on it.

ls -l shows them as files, with no room left for the offset column:

  root@ksp-04-11:~# ls -l /dev
  crw-rw----  root  sudo  door0   exterior       W  locked
  crw-rw----  root  sudo  light0  office            on
  crw-rw-rw-  root  root  null

Owner root, group sudo, mode 660. So root and anybody /etc/sudoers names
read them and work them with no sudo typed and no password asked, and
everybody else is refused by the device itself. Root may open one to the
whole office, and that lasts:

  root@ksp-04-11:~# chmod 666 /dev/light0

Only the MODE of a device outlives the command it was typed in. chgrp on
one answers is a device, and so do rm, mv, cp and edit.]],

[[Every refusal a device makes, and each is a fact about the building and
not about your typing. A device answers in its OWN name.

  light0: no power
      no current, no bulb, or nothing to switch
  lock0: no such device
      taken away, or where nobody is standing
  win0: smashed
      the glass is gone, so there is no lock to turn
  win0: barricaded
      boarded up
  lock1: no padlock
      a built door with neither padlock nor key
  door0: locked
      held by a key: unlock its lockN first
  door0: barricaded
      planks on it, and no machine takes those off
  door0: blocked
      the doorway is not clear: a wall, a tree, a car
  light0: invalid value
      that word means nothing to that kind
  light0: permission denied
      the mode says no
  win0: cannot toggle
      smashed or barricaded: no opposite to turn into
  door1: operation not supported
      a contact and no operator: nothing to move it

dev's own two are signed the way a command signs, and the appendix has
both.]],

[[Two rules about numbers, and one about the world, and then we are done.

A number belongs to a device for the life of the machine. light0 is the
same switch tomorrow as today. One torn out leaves a GAP -- nothing moves
up into it -- so a line you wrote into a crontab last week still means
what it meant. A device out of reach is not listed at all, and naming it
answers no such device: the difference between a switch that is gone and a
path you mistyped.

And the one to design around: nobody near, nothing acts. The parts of the
world nobody stands in are not loaded, and a door in one of them is a door
the machine cannot find. A minute later, with somebody in the room, the
same line works. That is what a building is.

Classic mistake. Reading the table, seeing light0 at 0 0, and assuming 0 0
means "the first one". It means the computer's own square. The switch in
the room with the machine in it, which is the one you will want at four in
the morning, is the one whose offset is two zeroes.]],

		} },

		{ title = "7. Work the machine does alone", pages = {

[[cron is the machine doing something with nobody standing at it, and on
this computer that means the lights and the doors of chapter 6.

Each account has a crontab. Once a minute the machine looks at every one
of them and runs the lines that are due. There are exactly three ways in
and no fourth:

  admin@ksp-04-11:~$ crontab -l
  no crontab for admin
  admin@ksp-04-11:~$ crontab -e
  admin@ksp-04-11:~$ crontab -r

-l prints yours, -e opens it in the editor, -r throws it away. You cannot
reach the file itself, and that is deliberate:

  admin@ksp-04-11:~$ ls -l /var/spool/cron
  ls: /var/spool/cron: permission denied

The directory is root's at mode 700 and each crontab in it is root's at
600. crontab is the one command on the machine that reaches a file its
caller may not, and it spends that privilege on exactly one path -- which
is what makes a line in your crontab a line that runs as YOU and not as
somebody who wrote it into your file.]],

[[A line is five fields and then a command:

  0 4 * * * echo off > /dev/light0
  */15 * * * * cat /dev/door0 >> log
  @reboot echo the machine is up

The fields, in order: minute 0 to 59, hour 0 to 23, day of month 1 to 31,
month 1 to 12, and day of week 0 to 6 from Sunday, with 7 allowed for
Sunday as well. A star is every value. Lists, ranges and steps all work:
8-17 is office hours, */15 is every quarter of an hour, 1-5 is Monday to
Friday.

Write the NUMBERS. Names for months and weekdays are not accepted here.

The seven shorthands save the commonest lines: @reboot, @hourly, @daily,
@midnight, @weekly, @monthly and @yearly. @reboot is the only one that is
not a time at all -- it runs once, when the machine comes up.

And the rule nobody expects, which this machine keeps because every cron
has kept it: when BOTH day fields are restricted, EITHER matching is
enough. 0 0 1 * 1 is the first of the month and also every Monday.

Thirty-two lines to a crontab.]],

[[The whole crontab is judged when you save it, and refused whole. The
refusal names the file, the line and the field, in the words cron has
always used:

  Cannot save: "/var/spool/cron/admin":1: bad minute

Try getting each of them on purpose; it is five minutes well spent.

  "/var/spool/cron/admin":1: bad hour
  "/var/spool/cron/admin":1: bad day-of-month
  "/var/spool/cron/admin":1: bad month
  "/var/spool/cron/admin":1: bad day-of-week
  "/var/spool/cron/admin":1: bad command
      five fields and nothing after them
  "/var/spool/cron/admin":1: bad time specifier
      an @word that is not one of the seven
  "/var/spool/cron/admin":33: too many entries

Note the line number. It is the line in the FILE, so a good crontab with
one bad line in it is refused and nothing of it is installed -- the one
you had before is still there and still running. Fix the line and save
again.

Blank lines and lines beginning with # are neither entries nor errors.]],

[[Where the output goes, and it is not the screen. Nobody is at the screen
at four in the morning.

It is mailed to the account, with the two lines a mailbox carries:

  admin@ksp-04-11:~$ mail
  From cron  Sun Jun 27 13:12:00 1993
  Subject: Cron <admin@ksp-04-11> echo tick

  tick

Ask again and it says No mail for admin, which is not a fault: reading
MOVES the mail. /var/mail/<name> is what has ARRIVED, ~/mbox in your home
is what you have read, and mail puts it there as it shows it. mail -f
reads that one and moves nothing. ~/mbox is a file at 600 and costs the
drive what any file does; no room leaves the mail in the spool and says
so. You have mail. is about the spool.

mail with a NAME after it SENDS: Volume 3 has that half.

What ran, and what did not, is /var/log/cron, root's at 640:

  Jun 27 13:12 (admin) CMD (echo tick)
  Jun 27 13:12 (CRON) error (can't fork)

That second line is the machine full: four jobs is all it has, and a line
with no slot free is skipped and logged.]],

[[One thing, once: at.

cron is a line that comes round again. at is a job you want done ONCE, at a
time you name, and then forgotten. It reads the commands from its standard
input, which on this machine means a pipe:

  admin@ksp-04-11:~$ echo halt | at 04:00
  job 1 at Fri Jul  9 04:00:00 1993
  admin@ksp-04-11:~$ cat plan | at 23:30
  job 2 at Thu Jul  8 23:30:00 1993

A time is HH:MM and nothing else here -- no "now + 1 hour", no "4am" -- and
one that has gone by today means tomorrow. atq lists what waits and atrm
takes one out; at -l and at -r are the same two.

  admin@ksp-04-11:~$ atq
  1  Fri Jul  9 04:00:00 1993
  admin@ksp-04-11:~$ atrm 1

The output goes to your mail, as a crontab line's does and for the same
reason. Where the two differ is the clock: a minute cron slept through is
gone, while a job queued for four o'clock on a machine that was off at four
runs when the machine comes back. It waits in /var/spool/at until it is
done.]],

[[Three things cron will not do, and each of them has cost somebody a
night's work.

It does not catch up. A machine that was switched off at four in the
morning, or standing in a part of the world nobody was near, does not run
four o'clock's line when it comes back. A minute cron slept through is a
minute that is gone. No cron has ever gone back for one.

It has no terminal, and the machine holds it to that. A cron line cannot
put a question up on a glass a survivor might be standing at, so five
commands refuse from cron and each says why:

  rlogin: not a terminal
  su: not a terminal
  passwd: not a terminal
  sudo: not a terminal
  edit: not a terminal

clear runs and clears nothing. rsh is the one that works without a
terminal, which is why a crontab calls rsh and never rlogin.

And it does not inherit your PATH. Every cron line starts at /bin and only
/bin, whatever your shell has. It is the oldest trap in cron, and the fix
is to write the whole path to anything not in /bin.]],

[[The television, and the one line a set can tell you that a clock cannot.

cat a tvN or an rxN and the dial is followed by what that station is
doing with the day:

  root@ksp-04-11:~# cat /dev/tv0
  on channel 203 airing 1080-1440
  root@ksp-04-11:~# dev tv0 channel 210
  tv0: off channel 210 next 360-720

airing means a broadcast is on that channel now, and the two numbers are
the block it belongs to. next means nothing is on and those are the
hours of the one that follows. idle means nothing now and nothing else
today, and a set tuned where no station is says neither -- the line
stops at the dial.

THE NUMBERS ARE MINUTES OF THE DAY. 0 is midnight, 360 is six in the
morning, 720 is noon, 1080 is six in the evening and 1440 is midnight
again. Life and Living TV, on 203, is four blocks of six hours and a
different trade in each.

That is what the numbers are FOR: you read them once, and then you write
the crontab line.]],

[[Putting it together: locking up at night.

Write this with crontab -e, as admin, on a machine whose devices you have
read out of chapter 6:

  0 22 * * * echo lock > /dev/lock0
  0 22 * * * echo off > /dev/light0
  0 22 * * * echo off > /dev/light1
  0 6 * * 1-5 echo on > /dev/light0

Ten at night the front door locks and the lights go out; six in the
morning, weekdays only, the office light comes back on. Four lines, no
survivor walking anywhere, and everybody on the wire sees the door swing.

Then check it in the morning, because a crontab you have not read back is
a hope:

  admin@ksp-04-11:~$ crontab -l
  admin@ksp-04-11:~$ mail

The first says what is installed. The second says what happened.

Classic mistake. Writing a line that reads a device and expecting cron to
wait for something to change. Cron runs a line at a time; waiting for a
door is a loop, and loops are Volume 3.]],

		} },

		{ title = "8. The other machines in the building", pages = {

[[Every computer on a premises the map knows -- a house, or one shop of a
mall -- is on one length of coax with the others on it, and it has an
address it did not choose.

  admin@ksp-04-11:~$ ifconfig
  eth0: flags=63<UP,BROADCAST,NOTRAILERS,RUNNING>
        inet 10.4.17.3 netmask 0xffffff00
  lo0: flags=8<LOOPBACK>
        inet 127.0.0.1 netmask 0xff000000

Four numbers: ten, then two that come from where the premises is, then
which computer of it this is. Nothing sets it. The address is a
fact about the card the way the name is a fact about the machine, and
there is no argument to ifconfig that changes either. The firmware
announces it between the drive and the login, so you can read a machine's
address without logging in at all.

A computer in a base YOU built is on no premises the map knows, so it has
no wire and says so plainly -- eth0 with flags and no address under it.
Nothing on this chapter's list will do anything on such a machine, and
that is not a fault to hunt.]],

[[Names live in /etc/hosts, root's and 644, and the machine writes its own
line into it exactly once and never again. So the first job on a new
machine is to write the others down:

  admin@ksp-04-11:~$ cat /etc/hosts
  # address  host  [alias...]
  127.0.0.1 localhost
  10.4.17.4 office pump
  10.4.17.9 gate

An address, a name, and as many aliases as you like. A name not in that
file does not exist as far as this machine is concerned.

Then find out what is up, which is two commands:

  admin@ksp-04-11:~$ ruptime
  ksp-04-11 up  02:32,  1 user,  load 0.00
  office    up  2+22:35,  2 users,  load 1.25
  admin@ksp-04-11:~$ rwho
  admin    ksp-04-11:console Jun 27 13:12
  admin    office:ttyp0     Jun 27 13:10
  kate     office:console   Jun 27 12:12

ruptime is the machines that are switched on; rwho is who is on them. A
machine that is off is not listed at all -- there is no daemon here
keeping the last thing it said -- and that is where these two differ from
the ones you may know.]],

[[Naming your neighbours, and nothing does it for you.

ruptime lists the machines by the name each one calls itself; ping and
rlogin want a name /etc/hosts carries. So a machine you can SEE is a
machine you cannot reach yet:

  admin@ksp-04-11:~$ ping office
  ping: unknown host office

arp is the other half: the cards on the wire, and a ? for an address no
line of /etc/hosts names.

  admin@ksp-04-11:~$ arp -a
  gate (10.4.17.9) at 8:0:20:1e:2a:4b
  ? (10.4.17.4) at 8:0:20:3c:7f:11
  root@ksp-04-11:~# echo "10.4.17.4 office" >> /etc/hosts

Now ping office answers. An address works anywhere a name does, so
rlogin 10.4.17.4 needs no line at all. The card is derived from the
address: no arp -d and no arp -s, because nothing sets one.

Trust is a line about a MACHINE: a name in /etc/hosts.equiv or ~/.rhosts
is the one YOUR /etc/hosts gives the caller's address, never the one he
announced. ruptime's names are what a machine SAYS it is called, and root
over there may say anything.]],

[[ping is how you tell a machine that is off from a machine you cannot
reach at all. Three packets, a second apart, and then the summary:

  admin@ksp-04-11:~$ ping office
  PING office (10.4.17.4): 56 data bytes
  64 bytes from 10.4.17.4: icmp_seq=0 ttl=255 time=0.4 ms
  64 bytes from 10.4.17.4: icmp_seq=1 ttl=255 time=0.4 ms
  64 bytes from 10.4.17.4: icmp_seq=2 ttl=255 time=0.4 ms

  --- office ping statistics ---
  3 packets transmitted, 3 packets received, 0% packet loss

A machine that does not answer prints no line at all for the packet that
never came back, and the summary is where you read it:

  admin@ksp-04-11:~$ ping gate
  PING gate (10.4.17.9): 56 data bytes

  --- gate ping statistics ---

with 0 packets received and 100% packet loss under it. Whether a packet
arrives is asked fresh for each of the three, so a machine switched off
halfway through loses the rest and the percentage says so.

A name it cannot look up it refuses before it sends a packet at all.]],

[[Three commands reach the other machine, and an administrator should know
which of them wants what.

rlogin is a whole session over there, on this glass. It asks the far
machine's own login: and password:, and from then on every line you type
is that machine's -- its files, its /dev, its accounts, its crontabs. exit
ends it and Connection closed. comes back. It needs a terminal to hand
over, so nothing automatic can use it.

rsh runs ONE command over there, waits for it and hands back what it
printed. It never asks for a password: either the far machine trusts this
one or you get rsh: gate: Permission denied. No terminal needed, which is
why a crontab calls rsh.

rcp copies one file across, one end written host:path. It needs the same
trust, lands as the account you are, and is judged by the far machine's
permissions and its own disk. The wire runs at about a kilobyte a second.

  admin@ksp-04-11:~$ rcp log office:/home/admin/log

It prints nothing when it works, as a copy should.]],

[[Trust is what saves a password every time, and either of two files is
enough. This is the part to get right.

/etc/hosts.equiv is the MACHINE's, root's and 644, one line each. A bare
host name trusts the same account on that machine and nobody in as
anybody else. A host and an account names the account coming IN.

~/.rhosts is the ACCOUNT's own half, in his home, and it is checked the way
it always has been: it has to be HIS file and nobody but him may write it.
One owned by somebody else, or one at 664, is ignored without a word -- a
trust file somebody else can edit is one somebody else wrote. Mode 600.

Two rules for the wall. root is never trusted through /etc/hosts.equiv,
only through /root/.rhosts. And a bare + in either file, which elsewhere
means "everybody", does not parse here: it trusts nobody.

  root@ksp-04-11:~# chmod 600 /root/.rhosts
  root@ksp-04-11:~# ls -l /root/.rhosts

Check that mode after you edit it. A file the machine ignores looks exactly
like one it honours.]],

[[Who is here, and who has been. who is this machine only, and the command to
type before a shutdown:

  admin@ksp-04-11:~$ who
  admin    console  Jun 27 13:12
  kate     ttyp0    Jun 27 13:07  (office)

The console is the keyboard; ttyp0 to ttyp3 came in over the wire, with the
machine in brackets. who am i prints your line alone.

Then the one to type after it: wall puts a line on EVERY one of those
screens, kate's included.

  admin@ksp-04-11:~$ echo "lights out in 5" | wall
  Broadcast Message from admin@ksp-04-11
          (console) at 13:12 ...

  lights out in 5

Anybody may: the real wall is setgid tty, not setuid root -- telling people
is not a privilege. It reads a file or a pipe, and shutdown warns the same
way.

last reads /var/log/wtmp, newest first:

  admin@ksp-04-11:~$ last
  admin    console    Jun 27 13:12  still logged in
  admin    console    Jun 27 11:12 - 11:17  (00:05)

  wtmp begins Jun 27 11:12

Root's and 644, oldest dropped. That line is where memory runs out.]],

[[ONE LINE PER PREMISES: a shop, or a whole house. A house is one building and
one line; a mall is one building and one line per shop. Seven digits,
announced under the card.

  Detecting drives ... hda 64K
  Ethernet: eth0 10.4.17.3
  Phone line: 555-0417 (CoffeeShop)
  Booting from hda ...

The first three digits are the exchange, and that is the TOWN's: everything
around here shares them and the next town is on another switch. The last
four are the premises; the name in brackets is the shop. None of it is on
the disk: there is no /etc/phone.

Every computer of one premises is on that ONE line and the lowest address
answers. Two premises can land on one number too: a PARTY LINE either way.

The exchange is a building full of switches on the county's power, and when
that goes the telephone goes with it: everywhere, at once, for good.]],

[[AND WHAT COUNTS AS A SHOP, because the answer decides four things: your
number, your wire, the people on your machine and the password on the paper
in the drawer. A shop is one the map drew an outline round -- the name in
brackets above -- or one that is a room of a TRADE in a building holding two
or more of them.

A stock room or a back office goes with the shop it shares its longest wall
with. A mall's corridors, lifts and stairs belong to nobody, and go with the
building.

A building with ONE business in it is ONE premises, back office and stock
room included: a gun shop, a house with a study, a school, a filling station.

A machine with no line prints none and cu says so: a base you built, or a
save older than this firmware until it is switched on where it stands. One
that stood in a mall before the shops were told apart takes its own shop's
number the same moment -- once, and its disk is untouched.]],

[[cu dials, and then nothing happens for a while. That is the ring.

  admin@ksp-04-11:~$ cu 555-0102
  CONNECT 2400
  Connected.
  login:

Four seconds of silence before that carrier, which is what a 2400-baud
handshake took. A busy line answers in two. A number nobody answers costs
fifteen: this modem's S7 register is set to 15, and S7 is how long a modem
waits for a carrier. Escape gives up on a dial, in the same
word. Both numbers are busy while it rings.

From there it is rlogin's session, with two differences. It asks for a
password EVERY time -- the trust files name machines, and a call has only a
number in it. And 2400 baud is four lines a second.

Over there, who and last name the number that called.

  kate     ttyp0    555-0417   Jun 27 13:07

exit over there ends it; ~. alone on a line ends it from here. Either way
the line says Disconnected. Every other word a dial ends in is the modem's,
and chapter 12 carries them.

rsh and rcp do not dial: a call is not a route.]],

[[The third link is the radio, and it is the only one that outlives the
county's power. A two-way radio in the machine's own room -- a ham set
on a table, a walkie somebody put down -- becomes its TNC, the box that
turns a computer into a radio station. One per machine, and it is a
device:

  admin@ksp-04-11:~$ dev radio
  radio0    ham          2E 1N      144.390 on
  admin@ksp-04-11:~$ cat /dev/radio0
  144.390 on

The frequency in megahertz, and what the set is doing: on, off, or no
power -- a dead grid or a flat battery, and to a TNC those are the same
thing. Read-only: the knob is on the radio and you turn it by hand. Two
sets in the room, and dev find radio0 shows which is yours.

A station needs a callsign, and it is a file:

  admin@ksp-04-11:~$ cat /etc/callsign
  KD4AXR

Root's and 644. It is the box's MYCALL: a TNC kept its callsign in its own
memory, and here that memory is this file. The firmware prints it at
power-on, the way a TNC printed its own when you switched it on.]],

[[A TNC is a peripheral, so you reach it the way 1993 reached any
peripheral: cu on its line. cu -l names a LINE instead of a number, and
the box answers with one line about itself and then its own prompt.

  admin@ksp-04-11:~$ cu -l /dev/radio0
  CeroSec Systems TNC-200 (TNC-2 compatible)
  cmd: MYCALL
  MYCALL KD4AXR
  cmd: C KE4QWZ
  *** CONNECTED to KE4QWZ
  login:

Six commands at cmd:, each with the short form the box takes. MYCALL
shows the callsign; MYCALL W4ZZZ sets it, and it is a file, so root only.
C call connects, CONNECT the same. D disconnects, DISCONNE the same. K
goes back into a link you stepped out of, CONV the same. MH lists the
stations heard, MHEARD the same, and MHCLEAR empties it. Anything else
gets ?EH: the box did not understand you.

Both sets on, both with power, and BOTH ON THE SAME FREQUENCY. That last
one is the whole job: agree a frequency with whoever is at the other end,
walk to your set, turn the knob, and check it with cat /dev/radio0.]],

[[A link that is up is cu's session -- the far machine's files, one of its
four ttyp lines, a password EVERY time -- and slower again: 1200 baud is
two lines a second, half what a telephone call carries.

Over there, who and last name the CALLSIGN that called.

  kate     ttyp0    KE4QWZ     Jun 27 13:07

Three ways back, and they are three different things. Escape steps out of
the link to cmd:, WITHOUT dropping it -- the box is still connected, and K
goes back in. D at cmd: drops the link and leaves you at cmd:. And ~.
alone on a line hangs the whole line up, link and cu together, which is
how you get back to the shell:

  cmd: D
  *** DISCONNECTED
  cmd: ~.
  Disconnected.

exit on the far machine ends it from that end. The refusals -- retry count
exceeded, BUSY, no radio, no callsign -- are in chapter 12.]],

[[Now the part that matters, and it is why the chapter ends here.

EVERY CONNECT AND EVERY DISCONNECT GOES OUT OVER THE AIR. Not the session
-- the two announcements. Anybody in the county with a walkie tuned to
your frequency, in range, reads this in his radio window:

  KE4QWZ de KD4AXR *** CONNECTED

Two callsigns and the fact that two machines are talking. He now knows
there is a computer worth walking to, roughly where, and which frequency
to sit on and listen. A wire cannot be overheard and a telephone call
cannot either. A radio cannot be anything else, and every operator in
1993 knew it.

Change frequency, and agree the new one OFF the air. That is the defence,
and it is why the knob is on the set. Keep the set off between links: a
station nobody can raise is a station nobody hears.

And the callsign is not a lock. It is a FILE root may write to anything,
and MYCALL writes it -- which is why a link asks for a password every
time, whatever /etc/hosts.equiv says.]],

[[The limits, the refusals, and what is coming.

Four sessions may come in at once, on ttyp0 to ttyp3; the fifth is turned
away, and so is a third hop of a chain. A session costs the FAR machine.

  admin@ksp-04-11:~$ rlogin nowhere
  rlogin: nowhere: unknown host
  admin@ksp-04-11:~$ rlogin gate
  rlogin: gate: Host is down
  admin@ksp-04-11:~$ rcp log gate:/tmp/log
  rcp: gate: No route to host
  admin@ksp-04-11:~$ rlogin office
  rlogin: connect: Connection refused

A telephone call pays the same ceilings and so does a link. Range on the air:
7500 tiles for a ham set, 8000 for a walkie, the SMALLER of the two, and
floors do not count. A radio is also a thing standing on a tile: a station
in a town nobody is near cannot be raised at all, where the wire and the
telephone reach the county regardless.

Three links now, and every one of them is cu or rlogin.

Classic mistake. Trusting a machine in /etc/hosts.equiv and forgetting
that whoever gets root on THAT machine has yours too.]],

		} },

		{ title = "9. Keeping the machine healthy", pages = {

[[Four numbers tell you everything about a machine's health, and the first
of them is the disk.

  admin@ksp-04-11:~$ df
  Filesystem   Size   Used  Avail  Use%
  hda         65536   2075  63461    4%
  nodes         512     86    426   17%

Sixty-four kilobytes and five hundred and twelve files and directories,
whichever runs out first, and a fresh machine has already spent a sixth of
the second one on /bin. Type df before you let anybody start keeping notes
on a machine, and again once a week.

Full is a state a machine can sit in. Nothing is ever deleted to make
room; every write answers disk full until somebody makes room. Writing a
shorter line over a longer one IS making room, which is the cheapest fix
there is.

  admin@ksp-04-11:~$ wc -c .sh_history
      32 .sh_history

One file is capped at 4096 bytes, one directory at 96 entries, and no path
goes more than sixteen levels below the root.]],

[[What is running, which is the second number. ps is the machine's jobs
with the processor time each has spent:

  admin@ksp-04-11:~$ ps
    ID S     CPU COMMAND
    43 S      35 sh watch.sh
     1 R       0 ps

The state is one letter: R running, S sleeping, W waiting for an answer,
O held back by the screen. ps shows the shell you are typing into, the way
every ps has; jobs does not, because the shell is not one of the things
the shell started.

Four jobs to a machine, cron's included. A fifth is refused, and the job
that is refused might be the crontab line you were counting on -- which is
why chapter 7 has that (CRON) error (can't fork) line in it.

kill takes a number from ps or a slot from jobs. fg brings a background
job to the front. Neither is much use until you have read Volume 3, which
is the book for what a job IS; what an administrator needs from this page
is that four is the ceiling and ps is where you look.]],

[[A runaway cannot hurt anybody, and it is worth knowing why so that you
do not go hunting a fault that is not there.

Every job gets a slice of each tenth of a second and no more. A loop
someone left running makes that ONE machine slow at that ONE thing: the
prompt still answers, the other screens still draw, and the server never
waits. Output is held to twenty lines a second, which is why a long
listing trickles down the glass instead of appearing whole -- that is the
machine being polite, not the machine being ill.

A job that spins for five minutes with nothing to wait for is taken away:

  killed: cpu limit

And no job survives the power. Switching off, rebooting, picking the
computer up or the world being loaded again all leave the machine running
nothing at all. A machine you come back to is a machine at its prompt.

So the honest answer to "the machine is slow" is ps, and the honest fix is
kill. There is nothing else to tune.]],

[[What the machine remembers about a person, and what it costs.

Every line typed goes into that account's own ~/.sh_history, mode 600, in
his home. history prints the last sixty of them with numbers:

  admin@ksp-04-11:~$ history
      1  df
      2  dev light0 off
      3  crontab -l
      4  who

A thousand lines and sixteen kilobytes, oldest dropped. Those sixteen
kilobytes are EXEMPT from the thirty-two on the disk -- a shell's memory
of itself must not be the thing that fills the drive.

The exemption belongs to the PATH and not to the file, and you can watch
it move:

  admin@ksp-04-11:~$ mv .sh_history loot.txt
  admin@ksp-04-11:~$ df
  Filesystem   Size   Used  Avail  Use%
  hda         65536   2107  63429    4%

Thirty-two bytes appeared out of nowhere. Move it back and they go again.
/var/log/cron, /var/log/wtmp and the mailboxes are exempt the same way and
for the same reason.]],

[[One more file in a home, and it is the one that strands people.

~/.profile is a list of lines the machine types for the account at login,
after the greeting and before the first prompt. It is where PATH is widened
and where an office's habits live. It is not a file the login runs on the
side -- it IS the login session, which is what makes a cd in it the place
you are standing.

That is also the trap. A .profile with an endless loop in it leaves the
account at a busy prompt with nothing to type at, and one with exit in it
logs the account straight back out, for ever.

The machine is not broken and the account is not lost. Escape is the
interrupt, and root can edit anybody's .profile, which is the way back
from the second one. Note that the firmware's repair never touches a home,
so restoring a machine will not clear one of these.

Classic mistake. Fixing a stranded account by deleting it with userdel -r.
You have deleted his files to remove one line. sudo edit its .profile.]],

[[The second filesystem.

A disk in the drive on the front of the case is a filesystem of its own,
and the machine tells you what is mounted if you ask it with nothing:

  admin@ksp-04-11:~$ mount
  /dev/hda on / type ufs (rw)
  /dev/fd0 on /mnt type ufs (rw)

The first line is the root filesystem and is always there: a machine
whose root could be unmounted is a machine with no /bin. The second is a
floppy, and /mnt is the directory it is mounted on -- root's at 755 and
shipped empty, because anything kept in it vanishes from view the moment
somebody mounts a disk over it.

The disk's own 4096 bytes are never counted against the machine's 65536,
in df or anywhere else. Volume 1, chapter 11 is the rest of it.

Classic mistake. Keeping a file in /mnt. It is a place, not a drawer.]],

[[Who may mount one is the mode on the drive and nothing else.

  admin@ksp-04-11:~$ ls -l /dev
  crw-rw----  root  sudo  fd0     WORK         ready

/dev/fd0 is root's, group sudo, at 660, like every other device here --
and on this one both bits are read. mount reads the super block, so it
wants r; newfs writes one, so it wants w. Nobody outside the sudo group
has either, and there is no second list of names anywhere that could
disagree with the mode.

So chmod 666 /dev/fd0 really does hand the drive to the whole office, and
chmod 640 really does leave the group able to mount a disk and unable to
format one. The mode is the drive's and not the disk's: it outlives
whatever was in the slot when you typed it.

Classic mistake. Reaching for sudo to mount a disk. An account in the
sudo group already has the drive; the mode says so.]],

		} },

		{ title = "10. The security checklist", pages = {

[[Everything in this chapter is one page of doing and it should take
fifteen minutes on a machine you have just been handed. Do it in order.

One. Give both shipped accounts a password, root first.

  admin@ksp-04-11:~$ sudo passwd root
  [sudo] password for admin:
  New password:
  Retype new password:
  passwd: password updated
  admin@ksp-04-11:~$ passwd
  Old password:
  New password:
  Retype new password:
  passwd: password updated

Root first, because until root has a password every account on the machine
has root: su and Enter is all it takes.

Write both on paper and keep the paper where the computer is not. Nobody
can recover a password for you and nothing on the machine can tell you
what one was. That is by design and it is the same design that keeps a
stranger from reading them out of /etc/passwd.]],

[[Two. Read /etc/sudoers and make it as short as it can be.

  admin@ksp-04-11:~$ sudo cat /etc/sudoers
  [sudo] password for admin:
  admin

Past the comment line it ships with: one name, and it is the account the
office actually uses. Every extra name
is another password that is as good as root's. NOPASSWD is a name that
never has to prove it is itself, which means a screen left logged in is
root left logged in: keep it for a machine nobody walks past, and never on
the machine by the door.

Three. Read the trust files, and read the MODE of every one of them.

  admin@ksp-04-11:~$ cat /etc/hosts.equiv
  admin@ksp-04-11:~$ ls -l /root/.rhosts

Empty is the right answer for most machines. A .rhosts at mode 664 is
being ignored, which is safe but is not what its owner thinks; one at 600
naming a machine is a real door. Every machine you trust is a machine
whose root is now your root.]],

[[Four. Read who has been here, and get in the habit.

  admin@ksp-04-11:~$ who
  admin    console  Jun 27 13:12
  admin@ksp-04-11:~$ last

who is now. last is the machine's own memory, newest first, and it is the
one place a session somebody had at three in the morning shows up. Two
hundred lines of it and then wtmp begins.

Be clear about the limit of that, because it matters. /var/log/wtmp is
root's file. An ordinary account cannot change a line of it, cannot delete
it and cannot stop it being written -- so last is a real record against
anybody who is not root. Somebody who IS root on the machine can erase
it, and the same is true of /var/log/cron. Nothing on this computer
protects anything from root. That is not a gap in this machine; it is what
root means, and it is the reason the first page of this chapter is about
root's password rather than about a log.]],

[[Five. Set the modes on the building, and then close up.

  root@ksp-04-11:~# ls -l /dev

Devices ship at 660, owner root and group sudo: the names in /etc/sudoers
and nobody else. If you widened one to 666 for an afternoon, put it back.
A light is nothing; a lock is the front door.

Six. Log out, every time. exit at the end of a session, and a shutdown
when you leave for the night -- after who.

  admin@ksp-04-11:~$ who
  admin@ksp-04-11:~$ exit

What a stranger at your keyboard can then do: try names at login: and be
told only login incorrect, which never says which half was wrong; read
/etc/group and /etc/hosts, public on purpose; and read last, and see
himself in it.

What he cannot do: read /etc/passwd or /etc/sudoers, touch a device, or
take his own line out of the log.

Classic mistake. Doing all six and leaving the screen logged in as root
while you go to look at something. Every page here is undone by that one
habit, and it is the only one on the list that is free.]],

		} },

		{ title = "11. Quick reference card", pages = {

[==[Every command this volume uses, with its exact shape. Square brackets are
optional parts; never type the brackets. Angle brackets are something you
must supply. Volume 1 has the reading and writing commands; Volume 3 has
the shell's own.

Being somebody else.

  su [name]
  sudo <command> [args]
  exit

Accounts.

  useradd [-G group[,group...]] login
  userdel [-r] login
  passwd [user]
  id [name]
  groups [name]
  mkpasswd <text> [salt]

Groups, and who may read what.

  groupadd <name>
  groupdel <name>
  usermod -G group[,group...] login
  chmod <mode> <path>
  chown <user> <path>
  chgrp <group> <path>]==],

[==[The machine itself.

  hostname [name]
  df
  ps
  jobs
  kill <id>|%<n>
  fg [%<n>|<id>]
  shutdown [-h|-r] now|+N
  halt
  reboot

The building.

  dev [kind|id [value|toggle]|find <id>]

Work with nobody standing there.

  crontab -e|-l|-r
  at HH:MM | at -l | at -r <job>...
  atq
  atrm <job>...
  mail [-f] [-s subject] [user...]

The wire.

  ifconfig [-a|<interface>]
  arp -a | arp <host|address>
  ping <host|address>
  ruptime
  rwho
  who [am i]
  wall [file]
  last [name]
  rlogin <host|address> [-l user]
  rsh <host|address> [-l user] <command>...
  rcp <src> <dst>, one is <host|address>:<path>

The telephone, and the radio through the TNC on its line.

  cu telno | cu -l line

At cmd: on the TNC: MYCALL, C call, D, K, MH, MHCLEAR. Escape steps out
of a link to cmd:, and ~. alone on a line hangs the line up.]==],

[[The numbers an administrator runs into, all in one place.

Accounts: a name is 16 characters, and a password 32. The machine's own
name is 16 characters too. su stacks 4 deep.

The system files, and the modes they ship at: /etc/passwd is 600,
/etc/sudoers 440 and /etc/group 644. /etc/motd holds 10 lines. A crontab
holds 32 lines, and both it and the directory it sits in are root's.

The building: 256 devices at most, at mode 660, and dev find shows one
for 6 seconds.

Work: 4 jobs to a machine, cron's included, and a job that spins 5
minutes with nothing to wait for is taken away.

The wire: 4 sessions in at once, on ttyp0 to ttyp3, and a chain of
rlogins 2 machines deep.

The logs: /var/log/wtmp holds 200 lines, /var/log/cron 100, and a mailbox
100 -- oldest dropped in every case, and all three exempt from the disk's
65536 bytes by their path.

Classic mistake. Typing the square brackets. They mark a part you may
leave out; they are not part of the command.]],

		} },

		{ title = "12. Appendix: what the machine says", pages = {

[[Every refusal is one line and it is built the same way every time:
<command>: <what failed>: <why>. Volume 1's appendix has the ones a user
meets. Below are the ones that belong to this book.

Being somebody else, and the accounts.

  su: authentication failure
      one wrong answer; there is no second try
  su: too many levels
      a fifth su, past the four the machine allows
  sudo: authentication failure
      the same, and for the same reason
  <name> is not in the sudoers file.
      not in the file at all; sudo will not ask twice
  passwd: authentication failure
  passwd: passwords do not match
  passwd: password too long
  passwd: no such user
  useradd: <name>: already exists
  userdel: <name>: user is logged in
  userdel: root: cannot remove
  chown: <name>: no such user
  mkpasswd: <salt>: invalid salt
      a salt is digits and lower-case letters only]],

[[The groups, and the machine's name.

  chgrp: <name>: no such group
      no line in /etc/group, and no account of that name
  groupadd: <name>: already exists
  groupdel: <name>: cannot remove
      root, sudo and users are the machine's own
  usermod: <name>: no such group
  usermod: <name>: no such user
  usermod: empty group list
  hostname: <name>: invalid name

Switching it off. The first is a machine with no clock to count from and
the second is its job book full: a pending order is a process.

  shutdown: no clock
  shutdown: too many jobs
  kill: <id>: Operation not permitted
      not yours to stop, and you are not root

A machine that has lost its commands says two lines and they are the only
two help ever prints on its own behalf:

  help: no commands in /bin: the system is damaged.
  help: switch the computer off and on to repair it.]],

[[The devices, chapter 6. A device answers in its own name, never in the
command's, so none of these carries dev: in front of it.

  light0: no power
  lock0: no such device
  win0: smashed
  win0: barricaded
  lock1: no padlock
  door0: locked
  door0: barricaded
  door0: blocked
  light0: invalid value
  light0: permission denied
  win0: cannot toggle
  sensor0: invalid value
  door0: operation not supported

No current or bulb; gone, or nobody near it; the glass broken; boarded up;
neither padlock nor key; held by a key; planks on it; something in the
way; a word that kind does not know; the mode; no opposite to toggle
into; a sensor, which takes no word; and a device with no hardware behind
it to carry one out.]],

[[The motors and the switches, chapter 6 as well. Same rule: the device
answers in its own name.

  window0: smashed
  window0: barricaded
  window0: sealed
  curtain0: barricaded
  stove0: broken
  stove0: no power
  washer0: no power
  gen0: no fuel
  gen0: broken
  gen0: not connected
  tv0: no power
  tv0: out of range

The glass gone; boards on it; a window the building was built never to
open; a sheet somebody has boarded over; a ruined stove; no current at
the socket, which a washer says the same way; an empty tank; a wrecked
generator; one nothing is plugged into; a set with no supply, which rx0
says the same way; and a dial asked for a frequency it cannot reach.

A generator refuses those three only when it is asked to START. Stopping
one is always allowed.]],

[[dev's own two are signed the way a command signs, because they are a
command's:

  dev: <word>: unknown kind
  dev: <id>: no such device
  /dev: read-only
      nothing may be created under /dev at all

The kinds are curtain, door, floppy, gen, light, lock, radio, rx, sensor, stove, tv, washer, win and window.]],

[[cron and mail, chapter 7. A crontab is judged when it is saved and
refused whole, and the refusal names the file, the line and the field:

  "/var/spool/cron/admin":1: bad minute
      also bad hour, bad month, bad day-of-month and
      bad day-of-week
  "/var/spool/cron/admin":1: bad command
      five fields and nothing after them
  "/var/spool/cron/admin":1: bad time specifier
      an @word that is not one of the seven
  "/var/spool/cron/admin":33: too many entries

  no crontab for <name>
  No mail for <name>
      an empty mailbox, which is not an error
  mail: <path>: permission denied
  crontab: <path>: disk full

And sending:

  <name>... User unknown
  <name>@<host>... Cannot send mail: no mailer
      and <host>!<name> too: no mailer off this machine
  Null message body; hope that's ok
      an empty message, and it is SENT anyway
  mail: <path>: disk full

And the log, for a minute the machine had no room for:

  (CRON) error (can't fork)]],

[[at, chapter 7, which queues one job instead of a line that comes round.
Its refusals are its own and the queue's:

  at: usage: at HH:MM | at -l | at -r <job>...
      a time it could not read, or no pipe to read the
      commands from -- at reads them from its standard
      input and standard input here is a pipe
  at: no commands
      the pipe closed with nothing in it
  at: queue full
      ninety-six waiting jobs is a full directory
  at: <job>: no such job
  at: <job>: Operation not permitted
      somebody else's job. root's rule, as kill's is
  at: no clock
      the machine cannot tell the time, so it cannot be
      told when

atq and atrm sign their own the same way, in their own names.]],

[[The wire, chapter 8. rlogin, rsh and rcp sign their own, and the words
are the ones a real one prints for the same trouble.

  rlogin: gate: unknown host
      no line of /etc/hosts carries that name
  rlogin: gate: Host is down
      on the wire, and switched off
  rlogin: gate: No route to host
      no wire between here and there: another premises,
      or a base somebody built
  rlogin: connect: Connection refused
      no line free -- four are in -- or the chain of
      rlogins is already two machines deep
  rsh: gate: Permission denied
      it does not trust this machine: /etc/hosts.equiv
      and ~/.rhosts are the fix
  Connection closed.
      the session is over; you are at your own prompt
  ifconfig: interface eth9 does not exist
  ping: unknown host gate
      refused before a packet is sent, with the name
      behind the reason rather than in front of it

who, last, ruptime and rwho refuse nothing at all: an empty screen is
their answer when there is nothing to say.]],

[[arp, chapter 8. It signs the refusal that belongs to the RESOLVER and
does not sign the one that belongs to the cache, which is a real arp's own
shape and tells you at a glance which of the two you have.

  arp: office: unknown host
      no line of /etc/hosts carries that name, and it is
      no address either
  office (10.4.17.4) -- no entry
      the name resolved and nothing of that address is on
      the wire: a machine switched off, or one on another
      premises. No command in front of it -- what arp
      prints is the word you typed, the address behind it,
      and what is missing

arp -a refuses nothing: a wire with nothing else on it is an empty screen,
exactly as ruptime's is.]],

[[The telephone, chapter 8. Four of these five are the MODEM talking and
not a command, which is why they are in capitals: a modem reported what
happened to a call in one word and there was nobody else to report it.

  cu: no phone line
      this computer is in no building, so there is no
      telephone in it to lift
  BUSY
      the line is in use -- this building's or theirs.
      There is one line to a building and one call on it
  NO DIALTONE
      the county's power has gone and the exchange with
      it. Nothing dials again, ever
  NO CARRIER
      nobody answered -- a number no building has, or a
      building with every machine off -- or the line went
      away under a call that was up
  CONNECT 2400
      the far modem answered. Connected. is cu saying the
      same thing in its own voice
  Disconnected.
      one end hung up on purpose: ~. here, exit there]],

[[The radio, chapter 8. Five of these seven are the TNC talking and not a
command: the four with three stars, which is how a TNC printed its own
lines so an operator could tell the box from the man at the far end, and
the one with a question mark.

  cu: /dev/radio0: no such device
      no two-way radio in this machine's room, so there is
      no TNC on its line and no line to open
  cu: no callsign
      /etc/callsign is gone or holds something no station
      could be called, and a station with no callsign may
      not transmit
  ?EH
      the box did not understand that line. Its whole
      vocabulary for a word it does not know
  *** CONNECTED to KE4QWZ
      the far TNC answered and the link is up
  *** DISCONNECTED
      one end let go on purpose: D or exit there
  *** retry count exceeded
      nobody answered, and a radio never says why. It also
      ends a link that went away underneath you
  *** BUSY
      that station has a link already, or this one has]],

[[And the line the rest of the county reads, which is on nobody's screen
here and is not a refusal at all:

  KE4QWZ de KD4AXR *** CONNECTED

the station called, the station calling, and what happened. Every connect
and every disconnect, on the frequency they were made on. Chapter 8.]],

[[The six that want somebody at the glass, and the machine says so
wherever there is nobody -- cron, a background job, a pipeline stage:

  rlogin: not a terminal
  cu: not a terminal
  su: not a terminal
  passwd: not a terminal
  sudo: not a terminal
  edit: not a terminal

A password question is only ever put up for the job holding the prompt;
from cron it would wait for an answer that never comes.

And the machine's own lines about work, which no command signs:

  killed: cpu limit
      five minutes of spinning with nothing to wait for
  sh: too many jobs
  kill: <id>: no such job
  fg: no current job
  fg: %<n>: no such job
  cerosec: nothing to answer
      an answer, and no question waiting

Classic mistake. Reading the first word and the last word of a refusal and
skipping the middle one. The middle piece is the only part that tells you
WHICH file, account, group or device the machine is complaining about, and
it is the only part you can act on.]],

		} },

	},
}
