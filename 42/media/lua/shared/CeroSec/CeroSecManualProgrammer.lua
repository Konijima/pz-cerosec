-- CeroSec OS, Volume 3: the Programmer's Guide.
--
-- The third of the three books CeroSec Systems shipped with a machine in 1993.
-- Volume 1 taught the screen, the disk and the small tools; Volume 2 the
-- accounts, the system files and the devices. This one teaches the reader to
-- make the machine do something with nobody standing at it: a script, the words
-- and the quotes, the variables, if and the loops, $( ) and $(( )), the pipes,
-- the jobs, cron, and the building and the wire reached from a file.
--
-- It assumes the reader has never programmed anything. It does not assume he is
-- slow, and it never uses a word he has not been given.
--
-- The shape of a page is the reader's, not this file's: plain ASCII, "\n\n"
-- between paragraphs (a single "\n" is a soft break the reader reflows), a line
-- beginning with two spaces is a screen and is kept monospace and so must fit
-- the machine's own sixty columns, and no page runs past a thousand characters.
-- tests/manual_test.lua checks every one of those.
--
-- EVERY transcript in here was copied off a running engine: the pages were
-- written against CeroSecOS.promptJob / jobStep driven the way SCeroSecJobs.lua
-- drives them, with a fake world of devices and a fake wire where the page
-- needed one. Nothing below is what the author thought the machine would say.
--
-- The cover is NOT written here. The reader stamps it from the engine's own
-- version number once the core is loaded; nothing in this file may name a
-- version, and nothing in this file may touch CeroSecOS at load time -- the
-- game loads shared/cerosec/ ahead of shared/cerosec/os/.

CeroSecManual = CeroSecManual or {}
CeroSecManual.volumes = CeroSecManual.volumes or {}

CeroSecManual.volumes[3] = {
	id = "programmer",
	title = nil,
	name = "Programmer's Guide",
	edition = "First Edition, 1993",
	chapters = {

		{ title = "1. Your first program", pages = {

[[This is the book about making the machine do something while you are not
there.

Everything in the first two volumes you did by hand: you typed a word, the
machine answered, you typed the next one. That works, and for an afternoon
it is the right way to work. It stops working the moment the job is long,
or dull, or has to happen at four in the morning while you are asleep in
another building.

So you write the words down in a file instead, and hand the file to the
machine. That file is called a script, and a script is the whole of the
programming this computer can be asked to do. There is no other language
in it and nothing to install: the words are the ones you have been typing
all along.

CeroSec Systems of Louisville, Kentucky has been selling these to offices
across Knox County since 1989, and this is the volume our customers write
to us about.

You need Volumes 1 and 2 in your head for this one, or at least on the
desk. We will not explain ls again.]],

[[What a script actually is.

A script is a text file with commands in it, one to a line. That is the
entire definition, and it is worth being suspicious of how small it is.
There is no compiling, no building and no magic: the machine reads your
lines and does them, top to bottom, exactly as if you had typed each one
and pressed Enter.

Write one with the editor from Volume 1, and put a first line on it that
does nothing:

  admin@ksp-04-11:~$ edit hello.sh
  (type two lines, then Tab to save and Escape to leave)
  admin@ksp-04-11:~$ cat hello.sh
  #!/bin/sh
  echo hello, world

The .sh on the name is a habit, not a rule; it tells a human what the file
is. The first line is a comment. A pound sign starts a comment anywhere in
a script and runs to the end of that line, so that line does nothing at
all. Write it anyway: every machine of this family expects it, and the
habit costs you nine characters.]],

[[Running it, the plain way.

sh is the command that reads a script and does it. Give it the file.

  admin@ksp-04-11:~$ sh hello.sh
  hello, world

That is your first program, and it worked. Read the line again and notice
what is not there: no wait, no output but yours, and your prompt back
immediately.

sh needs only to READ the file. So a script you may read is a script you
may run this way, which is worth remembering when you borrow somebody
else's.

Try it. Put a second line in hello.sh, save, and run it again. Then put a
deliberate mistake in it -- a command that does not exist -- and run it
once more, to see what the machine does with a bad line. It says the same
thing it says at the prompt, carries on to the next line, and does not
throw the rest of your file away.]],

[[Reading a file into the shell you are standing in.

sh hello.sh runs the file as a program, and a program cannot change the
shell that ran it: it is handed a copy of the environment, and everything
it sets dies with it. Most of the time that is what you want.

When it is not, there is one word for it, and the word is a full stop:

  admin@ksp-04-11:~$ echo "x=5" > set.sh
  admin@ksp-04-11:~$ sh set.sh
  admin@ksp-04-11:~$ echo [$x]
  []
  admin@ksp-04-11:~$ . set.sh
  admin@ksp-04-11:~$ echo [$x]
  [5]

Read it as "read this file here". The file is not run as a program at all;
its lines are read by the shell in front of you, as though you had typed
them, so what it sets is still set afterwards. It needs no x on it, only
r, for the same reason.

That is how .profile is read, and it is the reason a file of settings is
worth keeping. The word in bash and in csh is source; there is no source
on this machine, and there was none in 1993 either.]],

[[Running it as a command of its own.

Typing sh in front of a file forever is tiresome, and there is a better
way. A file with x on it -- the execute permission from Volume 1 -- can be
run by naming its path. The path for "this file, right here" is written
./name, and that dot-slash is not decoration: a bare name is looked for on
PATH and nowhere else, so a script in your own directory is never found by
typing its name alone.

  admin@ksp-04-11:~$ chmod +x hello.sh
  admin@ksp-04-11:~$ ./hello.sh
  hello, world

Forget the chmod and the machine tells you plainly, in the file's own name
rather than sh's, because it was the file you typed:

  admin@ksp-04-11:~$ ./noexec.sh
  ./noexec.sh: permission denied

Note the difference from the last page. sh wants r. ./ wants x as well.]],

[[Your own bin, in two paragraphs.

Volume 1 has this properly; here is the short form. When you type a word,
the machine walks the directories named in PATH, left to right, looking
for a file by that name with x on it, and runs the first it finds. Fresh
out of the crate PATH holds one directory, /bin, which is why a word you
made up is "command not found".

Make a directory of your own, add it to PATH, and your scripts become
commands with no dot-slash and no sh in front of them:

  admin@ksp-04-11:~$ mkdir bin
  admin@ksp-04-11:~$ lights on
  lights: command not found
  admin@ksp-04-11:~$ PATH=$PATH:$HOME/bin
  admin@ksp-04-11:~$ lights on
  lights on
  admin@ksp-04-11:~$ which lights
  /home/admin/bin/lights

That PATH line is forgotten when you log out. Chapter 9 is where we make
it stick. PATH may name eight directories and no more.]],

[[Handing a script some words.

Words typed after the script's name are handed to it, and inside the file
they wear numbers. $1 is the first, $2 the second, up to $9. $# is how
many arrived. $@ is all of them at once. $0 is the script's own name.

  admin@ksp-04-11:~$ cat say.sh
  #!/bin/sh
  echo $0 got $# words
  echo first is $1
  echo all of them: $@
  admin@ksp-04-11:~$ ./say.sh one two three
  say.sh got 3 words
  first is one
  all of them: one two three

Run it with nothing after it and nothing breaks. A word that was never
handed over is simply empty:

  admin@ksp-04-11:~$ sh say.sh
  say.sh got 0 words
  first is
  all of them:

Try both. Then try ./say.sh "one two" and watch $# come back as 1: the
quotes made one word of two, which is chapter 2's whole subject.]],

[[Saying how it went, and reading the answer.

Every command on this machine finishes with a number nobody prints:
nought when it worked, and something else when it did not. It is written
$?, and it is how one command in a script judges the one before it.

exit ends a script, with the number you give it. Here is the shape every
useful script starts with -- check what you were handed, complain, stop:

  admin@ksp-04-11:~$ cat check.sh
  #!/bin/sh
  if [ $# -lt 1 ]; then
      echo usage: check.sh NAME
      exit 2
  fi
  echo checking $1
  admin@ksp-04-11:~$ ./check.sh
  usage: check.sh NAME
  admin@ksp-04-11:~$ echo $?
  2
  admin@ksp-04-11:~$ ./check.sh notes.txt
  checking notes.txt
  admin@ksp-04-11:~$ echo $?
  0

Chapter 4 explains the if. Read it as English for now.]],

[[The one thing exit does differently in two places.

exit written IN A FILE ends that file and nothing else. The prompt comes
back, your session is untouched, and $? holds the number. A script that
ran another script is not ended by the inner one's exit either:

  admin@ksp-04-11:~$ ./outer.sh
  inner starting
  inner gave 3
  outer still here

exit TYPED AT THE PROMPT is the other exit, the one from Volume 1: it logs
the machine out and wipes the glass. There is no third meaning. The word
is the same word; where you wrote it decides.

Classic mistake. Putting exit at the end of a script "to be tidy". It is
harmless in a file, so nothing teaches you not to -- and then one day you
put the same tidy line at the end of ~/.profile, which IS your login
session and not a file it runs, and the machine logs you out the instant
you log in, every time, for ever. Chapter 9 has the way back. Do not
write exit unless you mean "stop here, early".]],

		} },

		{ title = "2. Words, quotes and the line", pages = {

[[How the machine reads your line.

Before anything runs, the shell chops your line into words, and it chops
on blanks. One space or forty, it makes no difference: the words are what
is left.

That is why the spaces in your line are not decoration. echo hello world
is the command echo and two words, and echo prints them back with one
space between them whatever you typed:

  admin@ksp-04-11:~$ echo hello     world
  hello world

And that is why quotes exist. A pair of quotes says "all of this is one
word", and the blanks inside are yours to keep:

  admin@ksp-04-11:~$ echo 'a  b' "c  d"
  a  b c  d

Two words went in and two came out, each with its own two spaces. Try it
with the quotes taken off and watch the spaces collapse.]],

[[The two kinds of quote, and when it matters.

Double quotes hold a word together and still let a dollar sign do its
work. Single quotes hold a word together and let nothing through at all:
inside them a dollar sign is a dollar sign.

  admin@ksp-04-11:~$ x=5
  admin@ksp-04-11:~$ echo "$x" and '$x'
  5 and $x

That is the whole difference and it is worth learning by heart. When you
want the value, double. When you want the characters, single.

A backslash does the same thing for exactly one character after it, which
is how you get a space into a word without quoting the lot:

  admin@ksp-04-11:~$ echo a\ b
  a b

Leave a quote open and nothing runs at all -- not the good half of the
line, nothing:

  admin@ksp-04-11:~$ echo "unfinished
  sh: syntax error: unterminated quote]],

[[Comments, and two commands on one line.

A pound sign starts a comment. Everything from it to the end of the line
is ignored, and the machine does not mind where on the line it sits:

  admin@ksp-04-11:~$ echo hi # this is a comment
  hi

Comment your scripts. Not every line -- a comment saying "print the name"
above a line that prints the name is noise -- but say at the top of the
file what the file is FOR, and say above anything clever why it is there.
You will read it in six months and you will not remember.

A semicolon ends a command in the middle of a line, so two commands fit on
one. This is the trap the whole page exists for:

  admin@ksp-04-11:~$ echo a;b
  a
  b: command not found
  admin@ksp-04-11:~$ echo "a;b"
  a;b

The first is two commands. The second is one word with a semicolon in it,
because the quotes took the semicolon's meaning away.]],

[[Joining two commands by their answer.

Two signs join commands by whether the first one worked, and both of them
read like English if you say them out loud.

Two ampersands mean "and then, if that worked".

  admin@ksp-04-11:~$ echo one && echo two
  one
  two

Two upright bars mean "or else, if that failed".

  admin@ksp-04-11:~$ false || echo fallback
  fallback

false is a real command whose only job is to fail, and true is its
opposite. They exist for exactly this sort of test.

Chain them and they are read left to right, with no cleverness:

  admin@ksp-04-11:~$ true && echo yes || echo no
  yes

Try it. This pair does most of what a short if would, in a third of the
room, and you will see it all over other people's scripts.]],

[[What the shell will not do, and one honest warning.

Two things you may be expecting are not here, and it is better to know
now than to debug it later.

There is no star. On a bigger machine a star in a word becomes every name
that matches it; on this one it is a star, and stays one:

  admin@ksp-04-11:~$ for f in *; do echo $f; done
  *

The way to walk a directory here is ls inside a $( ), which is chapter 6.

And there is no keyboard behind a command. Nothing on this machine reads
what you would have typed at it except read, which chapter 3 covers.

Classic mistake. Writing a line with a space around an equals sign. x = 5
is not an assignment: it is the command x with two words after it, and the
machine answers "x: command not found", which reads like nonsense until
you know this. An assignment is NAME=value with no blanks anywhere near
the equals sign. It is the single most common line in a broken script.]],

		} },

		{ title = "3. Variables, and asking a question", pages = {

[[Somewhere to put a thing.

A variable is a name with a value kept under it, and you make one by
writing the name, an equals sign, and the value. No spaces. Nothing is
declared first and nothing has a type: every value is text.

Read it back with a dollar sign in front of the name.

  admin@ksp-04-11:~$ x=5
  admin@ksp-04-11:~$ echo $x ${x}th
  5 5th

The braces in the second one are how you say where the name stops. $xth
would be a variable called xth, which you never set, so it reads as
nothing. ${x}th is the value of x with th stuck on the end. Use the braces
whenever a letter or a digit follows the name and never mind otherwise.

A variable you never set is not an error and is not a warning. It is
empty, silently, which is convenient and is also the thing that will cost
you an afternoon one day.

  admin@ksp-04-11:~$ echo ${nosuch}here
  here]],

[[Two names the machine sets for you.

HOME is your own directory, and PATH is the list of places a command is
looked for in. Both are ordinary variables that happen to be set before
you arrive.

  admin@ksp-04-11:~$ echo $HOME
  /home/admin
  admin@ksp-04-11:~$ echo $PATH
  /bin

Writing $HOME/notes instead of /home/admin/notes is the difference between
a script that works for whoever runs it and one that works for you. Get
into the habit.

Now the fact that catches everybody, and this book would rather tell you
on page one of the chapter. A script is not you. It is handed a COPY of
your ENVIRONMENT -- PATH, HOME, and whatever you have exported -- and
nothing else you have set, and what it sets never comes back to your
prompt. The next page is about that word, export, and it is the whole of
the difference between a variable of yours and a variable your scripts can
see. Set what you need at the top of your own scripts and you will never
meet the trouble.]],

[[The environment: what a script of yours can see.

Two different things live at your prompt. There are your VARIABLES, which
are yours; and there is the ENVIRONMENT, which is the small set of them
that is handed to every program you run. export is the word that moves a
name from the first into the second.

  admin@ksp-04-11:~$ x=5
  admin@ksp-04-11:~$ echo 'echo [$x]' > show.sh
  admin@ksp-04-11:~$ sh show.sh
  []
  admin@ksp-04-11:~$ export x
  admin@ksp-04-11:~$ sh show.sh
  [5]

export NAME=value does both in one line. env prints the environment as it
will be handed over, and export with nothing after it prints the same
thing in the shape you would type back:

  admin@ksp-04-11:~$ env
  HOME=/home/admin
  PATH=/bin
  x=5

A login exports PATH and HOME for you, which is why a script has always
been able to find a command.]],

[[Two ceilings on them.

A script may hold sixty-four variables at once, and one value may be a
thousand and twenty-four bytes long. Both are numbers you can only reach
on purpose, and both stop the script where it stands rather than letting
it grow until the machine suffers:

  admin@ksp-04-11:~$ ./lots.sh
  lots.sh: line 64: too many variables
  admin@ksp-04-11:~$ ./grow.sh
  grow.sh: line 4: word too large

The second of those is a loop with x="$x$x" in it, which doubles a value
every time round: ten turns take one letter past a thousand bytes. The
machine names the file and the line, so you do not go hunting.

These are not restrictions on what you meant to write. Sixty-four names is
more than any script on this desk has ever needed. They are there so that
one careless loop cannot take the machine down, which is a promise made
everywhere in this volume.]],

[[Asking the person at the keyboard.

read stops the script, puts a question up, and puts what is typed into a
variable. -p is the question to print.

  admin@ksp-04-11:~$ cat ask.sh
  #!/bin/sh
  read -p "your name? " who
  echo hello, $who
  admin@ksp-04-11:~$ ./ask.sh
  your name? Kate
  hello, Kate

Two more flags. read -s hides what is typed, which is what you want for a
password: the letters do not appear and they do not go into the history
either. read -n 1 takes the first character after Enter and does not wait
for a whole line, which is what you want for a yes-or-no:

  admin@ksp-04-11:~$ ./k.sh
  sure? (y/n) y

  going ahead

Try it. And note the blank line: that script prints an empty echo after
the answer, because a one-character answer leaves the cursor where it is.

While a script is waiting like this, the prompt is not yours. Escape is
the ^C that takes the question away and the script with it.]],

[[printf, for when echo is not tidy enough.

echo prints its words with a space between them and a new line at the end,
and nine times out of ten that is all you want. echo -n leaves the cursor
on the same line instead.

printf takes a shape first and the things to put in it after. A percent
sign and a letter is a hole: %s for a word, %d for a whole number, %% for
a real percent sign. A backslash and a letter is a key you cannot type in
the middle of a word: \n a new line, \t a tab.

  admin@ksp-04-11:~$ printf "%s is %d years old\n" hda 4
  hda is 4 years old
  admin@ksp-04-11:~$ printf "%s\t%s\n" a b
  a	b

printf prints NO new line unless you ask for one, which is the whole
reason it exists: you decide where the lines end.

Classic mistake. Reading a name with read and then using it unquoted:
[ $who = kate ] with nothing typed at the question becomes [ = kate ],
which is not a sentence the machine can judge. Quote what a person typed,
every time: [ "$who" = kate ].]],

		} },

		{ title = "4. Deciding", pages = {

[[Asking a question about the world.

Up to now your scripts have done the same thing every time. This chapter
is where they start to look around first.

The shape is four words, and you will type it for the rest of your life:

  if SOMETHING; then
      what to do when it worked
  fi

fi is if backwards, and it is how the machine knows the block has ended.
The semicolon after the question is a real semicolon: then is a new
command, and it needs the last one finished. A new line does instead, if
you would rather write it that way.

What sits where SOMETHING is, is a COMMAND -- any command -- and what the
if looks at is the number it finished on. Nought means yes. Anything else
means no. That is all an if is: it runs something and reads the answer.

  admin@ksp-04-11:~$ true; echo $?
  0
  admin@ksp-04-11:~$ false; echo $?
  1]],

[[The command whose whole job is answering questions.

You rarely want to test whether ls worked. You want to ask whether a file
is there, or whether two words are the same. The command for that is
called test, and it has a second name that is a single square bracket,
which is the one everybody writes:

  admin@ksp-04-11:~$ [ -f note.txt ]; echo $?
  0
  admin@ksp-04-11:~$ [ -d note.txt ]; echo $?
  1

Read it as "is note.txt a file?" -- yes, nought -- and "is it a
directory?" -- no, one.

The spaces inside those brackets are not optional and they are not style.
The bracket is a command, exactly like ls, and a command has to be a word
of its own. The closing bracket is an argument it insists on:

  admin@ksp-04-11:~$ [ 3 -lt 4
  sh: test: missing ']'

Try both. Then try man [ and read its usage line, which is real.]],

[[Everything test can be asked.

About a file, with the name after the flag:

  -f  is it a plain file
  -d  is it a directory
  -e  is it there at all, either kind
  -r  may I read it
  -w  may I write it
  -x  may I run it

About text:

  -z  is it empty
  -n  is it not empty
  =   are these two the same
  !=  are they different

About whole numbers, because = compares text, where 10 sorts before 9:

  -eq -ne -lt -le -gt -ge

Equal, not equal, less than, less or equal, greater, greater or equal.

  admin@ksp-04-11:~$ [ 3 -lt 10 ]; echo $?
  0
  admin@ksp-04-11:~$ [ 3 = 10 ]; echo $?
  1

Join two questions with -a for and, -o for or, and turn one round by
putting an exclamation mark in front of it:

  admin@ksp-04-11:~$ [ ! -f nothing ]; echo $?
  0]],

[[Two answers, and more than two.

else is the other half: what to do when the answer was no.

  if [ -f $log ]; then
      echo the log is there
  else
      echo no log yet
  fi

elif is "or else, if this instead", and you may write as many as you like
before the else. Here is the whole shape, with every part in it:

  admin@ksp-04-11:~$ cat menu.sh
  #!/bin/sh
  read -p "choice? " n
  if [ "$n" = 1 ]; then
      echo turning them on
  elif [ "$n" = 2 ]; then
      echo turning them off
  else
      echo nothing done
  fi
  admin@ksp-04-11:~$ ./menu.sh
  choice? 2
  turning them off

Both else and elif are optional. An if with neither simply does nothing
when the answer is no, which is often exactly right.]],

[[When the question itself is wrong.

test signs its refusals with its own name, and each one says what it could
not do rather than guessing:

  admin@ksp-04-11:~$ [ a -eq 3 ]
  test: integer expected
  admin@ksp-04-11:~$ [ 3 -foo 4 ]
  test: unknown operator

The first is the important one. -eq and its five friends read numbers, and
"a" is not one. Use = for text and -eq for numbers, and remember that a
variable holding a number is still text until something reads it as one.

The last thing to know is that any command works in an if, not only test.
This is a real line and a useful one, from chapter 10:

  if echo $1 > /dev/$l; then
      echo $l is now $1
  else
      echo $l would not answer
  fi

Classic mistake. Writing if [ $x = 5 ] where x might be empty. With
nothing in x the line the machine sees is [ = 5 ], which is not a question
and answers with a refusal instead of a no. Put the quotes on:
[ "$x" = 5 ]. It costs two characters and removes a whole family of
afternoons.]],

		} },

		{ title = "5. Repeating", pages = {

[[Doing the same thing to a list of things.

for takes a name and a list of words, and runs its block once for each
word with the name set to it.

  admin@ksp-04-11:~$ for f in a b c; do echo $f; done
  a
  b
  c

do opens the block and done closes it. Written out in a file, where there
is room, the same loop reads better:

  for f in a b c; do
      echo $f
  done

The list is words, split on blanks like any other line, so quotes work in
it the way they work everywhere. And the list can come from a command,
which is what makes for useful rather than merely tidy -- that is chapter
6, and it is the one thing in this book worth reading twice.

Try it. Then take the semicolon out from in front of do and read what the
machine says; it will tell you exactly which word it wanted.]],

[[Doing something until a question changes its answer.

while takes a question, exactly the kind chapter 4 built, and runs its
block over and over for as long as the answer stays yes.

  admin@ksp-04-11:~$ cat count.sh
  #!/bin/sh
  i=0
  while [ $i -lt 3 ]; do
      echo $i
      i=$((i + 1))
  done
  admin@ksp-04-11:~$ ./count.sh
  0
  1
  2

The $(( )) is arithmetic and is chapter 6; read it as "one more than i".
Notice that something inside the block has to move, or the answer never
changes. That is a fact about loops and not a rule of this machine.

until is while with the question turned round: it runs for as long as the
answer is NO, and stops when it becomes yes. Put i=5 at the top, until
where the while was, and one less each turn, and it counts down:

  admin@ksp-04-11:~$ ./down.sh
  5
  4
  3

Use whichever makes the sentence in your head shorter. They are the same
loop and neither is faster.]],

[[Leaving early, and skipping one turn.

break leaves the loop it is in, at once, whatever the question would have
said next. This file walks a b c d and stops at c:

  admin@ksp-04-11:~$ cat stop.sh
  #!/bin/sh
  for f in a b c d; do
      if [ $f = c ]; then
          break
      fi
      echo $f
  done
  admin@ksp-04-11:~$ ./stop.sh
  a
  b

continue goes straight to the loop's next turn and skips the rest of the
block. The same file with continue where the break was prints a and c.

Both take a number, if you want to leave or skip more than one loop at a
time, counted outwards from where you stand: break 2 leaves this loop and
the one around it.

Loops go inside loops, which is how you walk two lists at once:

  admin@ksp-04-11:~$ cat pairs.sh
  #!/bin/sh
  for a in 1 2; do
      for b in x y; do
          echo $a$b
      done
  done
  admin@ksp-04-11:~$ ./pairs.sh
  1x
  1y
  2x
  2y

Sixteen deep is the limit on ifs and loops together.]],

[[The one loop this machine was built for.

Unix has never had a "wait until something happens". What it has always
had is a loop that asks, waits a bit, and asks again, and that is how you
watch a door:

  while [ "$(cat /dev/door0)" = closed ]; do
      sleep 5
  done
  echo on > /dev/light0
  echo "the front door opened"

Read it as a sentence: while the door is still shut, do nothing for five
seconds. When it stops being shut, the loop ends and the lines under it
run.

Put an ampersand on the end of the line that starts it and it watches
while you do something else:

  admin@ksp-04-11:~$ ./watch.sh &
  [1] 43
  the front door opened

That is the whole of a burglar alarm. Chapter 8 explains the ampersand and
the number, and chapter 10 explains /dev; this page is here so you see
where the book is going.]],

[[Why the sleep in that loop is the point.

The same loop with the sleep taken out does the same job and is the one
thing in this book not to write.

A sleeping script costs the machine nothing at all. It is off the
processor entirely and can wait for days. What the loop above asks of the
computer is one glance every five seconds and nothing in between.

Without the sleep it asks for every scrap of processor the machine will
give it, for as long as it runs, and finds out the door opened no sooner.
A script that spins with no wait in it for five minutes is taken away:

  admin@ksp-04-11:~$ ./spin.sh &
  [1] 43
  [1] killed: cpu limit

sleep takes whole seconds, as it does everywhere. sleep 5, not sleep 0.5.

Classic mistake. A while loop whose question can never change -- reading a
file the loop never writes, or comparing a variable nothing moves. It runs
for five minutes and dies of the ceiling above. Before you write a while,
say out loud what makes it stop.]],

		} },

		{ title = "6. Capturing and computing", pages = {

[[Putting a command's answer into a word.

This is the idea that turns a list of commands into a program. Wrap a
command in a dollar sign and round brackets, and what it would have
printed becomes a word in the line you are writing.

  admin@ksp-04-11:~$ today=$(date +%Y-%m-%d); echo $today
  1993-07-08

Nothing was saved and no file was made. date ran, its output was caught,
and the catch was handed to the assignment.

Every newline in the catch is folded into a space, so a command that
printed three lines becomes one word-list of three:

  admin@ksp-04-11:~$ echo $(cat log)
  one two three

That folding is what makes the for loop from chapter 5 work on things the
machine found rather than things you typed:

  for l in $(ls /dev | grep light); do
      echo off > /dev/$l
  done

Try that on your own machine after chapter 10 and watch the lights go
out.]],

[[Two rules about catching, and one refusal.

One level, and no further. A $( ) inside a $( ) is refused where it is
typed, before anything runs:

  admin@ksp-04-11:~$ x=$(echo $(date))
  sh: syntax error: bad substitution

There is no script worth writing on this desk that needs two, and the
machine would rather say so than let a short line ask for an unbounded
amount of work.

And a catch is a WORD, so it meets the word's own ceiling of a thousand
and twenty-four bytes:

  admin@ksp-04-11:~$ x=$(cat big)
  sh: word too large

That line is the whole answer: nothing of what the command had already
printed arrives behind it.

Catch the number of lines, not the lines. That is almost always what you
wanted anyway:

  admin@ksp-04-11:~$ n=$(cat log | wc -l); echo "$n lines"
  3 lines

Note the quotes round $n there. Without them the value is split on blanks
like anything else, which matters the day a catch comes back with a space
in it.]],

[[Arithmetic, in double round brackets.

Dollar sign and two round brackets is a sum. It works on whole numbers
with plus, minus, star for times, slash for divide and a percent sign for
the remainder, and ordinary brackets group as you would expect.

  admin@ksp-04-11:~$ echo $((2 + 3)) $((7 / 2)) $((7 % 3))
  5 3 1
  admin@ksp-04-11:~$ echo $((3 * 4)) $((10 - 20))
  12 -10
  admin@ksp-04-11:~$ echo $(( (2 + 3) * 4 ))
  20

There are no fractions anywhere on this machine. 7 / 2 is 3, with the
remainder thrown away, and a divide rounds towards nothing rather than
downwards: minus seven over two is minus three.

Inside the double brackets a bare name is already the variable, so the
dollar sign in front of it is optional. These two lines are the same line,
and you will see both written:

  admin@ksp-04-11:~$ i=4; echo $((i + 1))
  5
  admin@ksp-04-11:~$ i=4; echo $(($i + 1))
  5

Counting up is the commonest line in this book:

  i=$((i + 1))]],

[[Arithmetic on the words a script was handed.

A dollar sign inside the double brackets means what it means outside them.
The shell puts the word in first and reads the sum afterwards, so the
numbers a script was given are numbers it can count with.

  admin@ksp-04-11:~$ cat share.sh
  #!/bin/sh
  echo $(($1 / $2)) each, $(($1 % $2)) left over
  echo that was $# numbers
  admin@ksp-04-11:~$ ./share.sh 17 5
  3 each, 2 left over
  that was 2 numbers

$1 to $9, $0, $#, $? and ${NAME} are all read in there, and so is $$. A
word that is not a number counts as nought -- the same rule an empty
variable follows -- so a script handed nothing divides by nothing:

  admin@ksp-04-11:~$ ./share.sh
  share.sh: line 1: divide by zero

Count what you were given before you compute with it:

  if [ $# -lt 2 ]; then echo usage: share.sh a b; exit 2; fi]],

[[Doing arithmetic on the clock.

date +%s prints the time as one plain number, counting seconds, and that
is the only shape of the time you can do sums on. It is also the shape
every file's date is kept in underneath.

  admin@ksp-04-11:~$ start=$(date +%s); echo $((start + 60))
  742122960

So "a minute from now" is a number you can compare against, which is how
you write a loop that gives up:

  stop=$(($(date +%s) + 300))

-- except that you cannot, because that is a $( ) inside a $(( )) and this
machine allows one level. Write it in two lines, which is clearer anyway:

  now=$(date +%s)
  stop=$((now + 300))

Then a loop that waits and gives up. This one was run with 30 instead of
300, so as not to sit there, and it gave up thirty-four seconds later:

  admin@ksp-04-11:~$ cat give.sh
  #!/bin/sh
  now=$(date +%s)
  stop=$((now + 30))
  while [ $(date +%s) -lt $stop ]; do
      sleep 10
  done
  echo gave up
  admin@ksp-04-11:~$ ./give.sh
  gave up]],

[[Two refusals, and a habit worth having.

Dividing by nothing, and a sum that is not one:

  admin@ksp-04-11:~$ echo $((1 / 0))
  sh: divide by zero
  admin@ksp-04-11:~$ echo $((2 +))
  sh: bad arithmetic

Both stop the script where they stand, naming the file and the line. The
first is nearly always a divide by a variable that turned out empty, which
reads as nought; worth knowing before it happens.

The habit: when a script is not doing what you meant, put an echo in front
of the line you doubt and print the pieces.

  admin@ksp-04-11:~$ n=$(wc -l log); echo $n
  3 log

There is the whole bug on one line: wc prints the file's name as well as
the count, so n is two words and not a number. Pipe it instead and the
name is gone, as page two of this chapter had it.

Classic mistake. Expecting $( ) to hand back what a command changed rather
than what it printed. A catch only ever catches PRINTING. A command that
worked in silence hands back an empty word, and that is not a fault.]],

		} },

		{ title = "7. Plumbing", pages = {

[[The pipe, in one line.

An upright bar between two commands takes what the left one printed and
hands it to the right one instead of to the screen. Volume 1 introduced
it; here is what it is for in a script.

  admin@ksp-04-11:~$ ls /bin | wc -l
      66
  admin@ksp-04-11:~$ cat log | sort | uniq -c
        2 bob
        3 kate

Join as many as you like, left to right, up to eight. A ninth stops the
line before anything runs:

  admin@ksp-04-11:~$ cat log|cat|cat|cat|cat|cat|cat|cat|cat
  sh: too many stages

Only the last stage's output reaches the glass, and only the last stage's
number reaches $?. The ones in the middle are plumbing:

  admin@ksp-04-11:~$ true | false; echo $?
  1
  admin@ksp-04-11:~$ false | true; echo $?
  0]],

[[Which commands can read a pipe.

Seven, and they are the seven that read files: cat, grep, head, tail, wc,
sort and uniq. Anything else on the right of a bar simply ignores what
came down it.

A file named on the line always wins. cat notes | sort sorts notes;
cat notes | grep -n e searches it. And one of the seven with no file and
no pipe prints its usage line rather than waiting, because there is no
keyboard behind a command on this machine.

Two of the seven have to see all of their input before they can answer a
word of it -- sort cannot know the first line until it has the last -- so
what they will hold is bounded, at a hundred lines and four kilobytes:

  admin@ksp-04-11:~$ cat big | sort | tail -n 1
  sort: input too large

The five that answer as they go have no such ceiling:

  admin@ksp-04-11:~$ cat big | wc -l
     150

So put head or grep in FRONT of a sort when the input is long, and sort
what is left.]],

[[The reader that stops reading.

head takes what it wants and then stops, and a writer whose reader has
gone away is ended rather than left shouting into a wall. This is what
makes an endless loop safe to pipe:

  admin@ksp-04-11:~$ while true; do echo y; done | head -n 2
  y
  y

The loop is over the moment head has its two lines. What it ended with is
a number worth recognising, because it is the one status on this machine
that is not a small integer:

  141

A hundred and forty-one means "the pipe I was writing to closed". It is
not a fault and it is not yours: it is the normal end of anything in front
of a head. $? after that pipeline is head's own, which is nought, so a
script never sees the 141 unless it goes looking.

Try it. Then try it with head -n 1 and count the lines.]],

[[The subshell rule, which catches everybody once.

Every stage of a pipeline is a shell of its own, with its own copy of the
variables. So anything a stage changes is gone when the pipeline ends, and
the one that bites is read:

  admin@ksp-04-11:~$ echo hello | read x
  admin@ksp-04-11:~$ echo [$x]
  []

That is not a bug and it is not this machine being small. read really did
read the pipe, in the shell that was the last stage, and that shell and
its x ended with the pipeline. Every Unix behaves this way.

The way to keep what came down a pipe is a catch, which is not a separate
shell:

  admin@ksp-04-11:~$ x=$(cat log | head -n 1); echo $x
  kate

Remember the rule as a sentence: a pipe carries text out, never variables
back. If you need the value, catch it.]],

[[Sending output to a file, and to nowhere.

One greater-than sign puts a command's output in a file, replacing what
was there. Two add to the end. Both work in a script exactly as they work
at the prompt, and both are how a script leaves a record of itself:

  admin@ksp-04-11:~$ cat note.sh
  #!/bin/sh
  echo first line > report
  echo second line >> report
  date >> report
  wc -l report
  admin@ksp-04-11:~$ ./note.sh
       3 report

/dev/null is the hole in the machine. Send output there when you want a
command's work and not its noise:

  admin@ksp-04-11:~$ cat log | grep kate > /dev/null
  admin@ksp-04-11:~$ echo $?
  0

That line asks "is kate in the log?" and says nothing at all while
asking. The answer is in $?, which is what an if wants.

One command sends its output to one file. Two redirects on a line, or none
after the sign, and nothing runs:

  admin@ksp-04-11:~$ echo x > a > b
  sh: syntax error: bad redirect]],

[[Two more on redirects, and one on the wire.

The name after the sign has to come out as exactly one word. A catch that
folds to two words is refused, because the machine will not guess which
file you meant:

  admin@ksp-04-11:~$ echo x > $(cat two)
  sh: ambiguous redirect

A redirect onto a device is how you work the building. That is chapter 10,
and the sign means the same thing there: what would have been printed goes
into the thing on the right.

One on the wire, since you will try it. rsh runs one command on another
machine and hands back what it printed, and that goes wherever anything
else on the line would have gone -- a pipe, a catch, a file:

  admin@ksp-04-11:~$ rsh gate ls /bin | wc -l
      66

Chapter 10 has the rest of it.

Classic mistake. Writing cmd > file inside a loop and wondering why the
file holds one line. Each turn replaces the lot. Inside a loop you almost
always want two signs.]],

		} },

		{ title = "8. Jobs", pages = {

[[Putting a script behind the prompt.

An ampersand at the end of a line means "start this and give me my prompt
back". The machine answers with two numbers and gets on with it.

  admin@ksp-04-11:~$ ./tick.sh &
  [1] 43
  tick

The number in brackets is the slot -- the machine holds four at once and
this is the first -- and 43 is the job's own number, which is what $$
holds inside it. The line under it is the script printing, as it prints.

Two commands list what is running. jobs lists the background jobs, by slot:

  admin@ksp-04-11:~$ jobs
  [1] sleeping ./tick.sh &

Read that carefully: the jobs belong to the MACHINE and not to your shell.
Four is a computer's ceiling, not a session's. Walk away and they keep
running, and whoever sits down next sees them in his own jobs and may fg or
kill them. A bigger Unix shows you only what your own shell started.]],

[[ps lists everything the MACHINE is running, by number, with what state it
is in and how much it has spent:

  admin@ksp-04-11:~$ ps
    ID S     CPU COMMAND
    43 S      36 ./tick.sh &
    45 R       0 ps

R is running, S sleeping, W waiting for an answer from somebody or from
another machine, O held back by the screen, and Z finished and not yet
reaped. The CPU column is the steps the job has spent, and it is the one
number a runaway script is recognised by: it climbs, fast, and nothing else
on the listing does.

ps shows the shell you typed into, because that is a job too, and it shows
the cron lines. jobs shows neither: one is not a background job and the
other is nobody's to bring forward.]],

[[Stopping one, and waiting for one.

kill takes a slot with a percent sign in front of it, or a bare job
number, and asks the machine to take the job away.

  admin@ksp-04-11:~$ kill %1
  [1] killed
  admin@ksp-04-11:~$ jobs

The empty answer from jobs is the proof. Nothing is left.

wait holds your prompt until the background jobs are finished, which is
how a script starts three things and then waits for all three:

  admin@ksp-04-11:~$ ./short.sh &
  [1] 43
  admin@ksp-04-11:~$ wait
  done working
  [1] done

fg brings a job to the front. What that changes is two things and no more:
its output arrives on the glass as it is written, and Escape becomes its
^C. It prints the line it brought forward.

  admin@ksp-04-11:~$ fg %1
  ./tick.sh &

There is no bg, and nothing to want it for: nothing on this machine
suspends a job, so the only direction one moves in is forwards.]],

[[Four at once, and what the fourth one says.

Four jobs is the ceiling. A fifth is refused where you asked for it, and
nothing else is disturbed:

  admin@ksp-04-11:~$ while true; do sleep 9; done &
  [1] 43
  admin@ksp-04-11:~$ while true; do sleep 9; done &
  [2] 45
  admin@ksp-04-11:~$ while true; do sleep 9; done &
  [3] 47
  admin@ksp-04-11:~$ while true; do sleep 9; done &
  [4] 49
  admin@ksp-04-11:~$ while true; do sleep 9; done &
  sh: too many jobs

Four is four whichever way the job started: a typed loop, a file behind an
ampersand, a cron line. A script behind an ampersand runs INSIDE the job
the machine made for it and asks for no second one, so it needs no slot of
its own.

Four background jobs and a prompt is the shape to plan for. It is more
than a 1993 desk has needed, and if you want a fifth thing watched, watch
two of them from one script with one loop.]],

[[How the machine shares itself out.

The promise this whole volume rests on: nothing you can write will stop
this machine.

The computer hands out work in STEPS and not in seconds. Ten times a
second it gives every job a small allowance and takes it back mid-word. So
an endless loop makes the machine slow at that one thing and at nothing
else: your prompt still answers and nobody waits for your mistake.

A step is a unit of cost, not of syntax. A variable set, an echo, a test
is worth one. A command that leaves the shell -- ls, grep, date, anything
with a file in /bin behind it -- is worth thirty-two, because it does about
thirty times the work. A loop of arithmetic is cheap, a loop of ls is not,
and ps shows it:

  admin@ksp-04-11:~$ ps
    ID S     CPU COMMAND
    43 R     400 ./spin.sh &
  admin@ksp-04-11:~$ ps
    ID S     CPU COMMAND
    43 R     750 ./spin.sh &

That column climbing fast, with nothing to show for it, is what a runaway
loop looks like from outside.]],

[[What a runaway does, from beginning to end.

Write one on purpose. It is the best hour you will spend with this book.

  admin@ksp-04-11:~$ cat spin.sh
  #!/bin/sh
  while true; do
      x=$((x + 1))
  done
  admin@ksp-04-11:~$ ./spin.sh &
  [1] 43

First: nothing happens. The prompt comes straight back and the machine
feels normal, because the loop is only getting its allowance.

Second: ps shows the CPU column climbing, and nothing else on the machine
changes.

Third, if you leave it: five minutes of that, with no wait anywhere in it,
and the machine takes it away and says why.

  [1] killed: cpu limit

A loop that PRINTS is gentler still. Output reaches the glass at twenty
lines a second whoever wrote it, so a loop full of echoes trickles instead
of flooding, and a job with forty lines waiting simply does not run again
until the screen has taken some. ps writes that job's state as O.]],

[[Getting it back under control.

Three ways to end something you regret, in the order to reach for them.

Escape, when the thing is in front of you. It is the ^C from Volume 1: it
prints ^C and ends the job that holds the prompt, question and all.

kill %1, when it is behind the prompt. jobs tells you the slot.

And the switch on the case, which ends every job at once. Jobs are never
written to the disk: a computer switched off, rebooted or carried away
comes back running nothing at all.

One thing more. A script asleep or waiting for an answer stops its own
clock, which is why the door-watching loop in chapter 5 can wait a week and
a spinning one cannot last five minutes: the ceiling counts time ON the
processor, not time alive.

Classic mistake. Starting a background job, walking away, and coming back
to a machine that seems to have lost your script. It very likely finished.
Read the screen from the top: [1] done, [1] exit 3 and [1] killed are all
in the scrollback.]],

		} },

		{ title = "9. Programs that run without you", pages = {

[[cron: the machine's own alarm clock.

Every account may keep a list of times and commands, and once a minute the
machine looks at every line of every list and runs whatever is due. Nobody
has to be standing at the computer. Nobody has to be in the building.

A line is five fields and then the command: minute, hour, day of the
month, month, day of the week. A field is a star for "every", a number, a
list, a range, or a range with a step.

  0 4 * * *      four in the morning, every day
  */15 * * * *   every fifteen minutes
  0 8-17 * * 1-5 hourly, eight to five, Monday to Friday
  30 2 1 * *     half past two, the first of the month

Minutes are 0-59, hours 0-23, days 1-31, months 1-12, weekdays 0-6 from
Sunday. Write the numbers; names are not accepted. A line beginning with a
pound sign is a comment.

There are shorthands: @hourly, @daily, @midnight, @weekly, @monthly,
@yearly, and @reboot, which runs when the machine is switched on and never
otherwise.]],

[[Getting your lines in, and what refuses them.

crontab is the way in and the only way in. The file itself lives under
/var/spool/cron where nobody can reach it, which is what stops one account
writing a line that runs as another.

crontab -e opens yours in the editor. crontab -l prints it. crontab -r
throws it away.

  admin@ksp-04-11:~$ crontab -l
  # every night at four
  0 4 * * * /home/admin/bin/backup
  @reboot /home/admin/bin/watch &

A list that will not parse is refused whole, when you save it, naming the
file, the line and the field:

  "/var/spool/cron/admin":1: bad minute

The others read the same way: bad hour, bad day-of-month, bad month, bad
day-of-week, bad command for five fields with nothing after them, and bad
time specifier for an at-word that is not one of the seven. A list holds
thirty-two lines.

Try crontab -l on a machine with nothing in it. "no crontab for admin" is
not an error; it is an empty shelf.]],

[[The environment a cron line gets, which is not yours.

This is the oldest trap in Unix and it catches every programmer once.

A cron line starts with PATH set to /bin and nothing more on it. Your
own bin is not there, however carefully you added it at your prompt. So:

  30 4 * * * nightly.sh
  30 4 * * * /home/admin/bin/nightly.sh

The first one is not found at four in the morning and the second one is.
Write the whole path in a crontab line, always.

It does get HOME, and starts in your own directory. What it does not get
is your environment: cron builds one of its own with those two names in it
and nothing else, so a name you exported at a prompt this morning is not
there at four tomorrow.

  admin@ksp-04-11:~$ export x=hi
  admin@ksp-04-11:~$ ./where.sh
  x is [hi]
  admin@ksp-04-11:~$ ./where.sh &
  [1] 44
  x is [hi]

An ampersand is a subshell and carries your environment with it. A crontab
line is not a subshell of anything: set what a script needs inside it.]],

[[Where a cron job's words go.

Nobody is at the screen at four in the morning, so nothing a cron line
prints goes on it. It is posted to the account instead, and mail shows it
and empties the box.

  admin@ksp-04-11:~$ mail
  From cron  Thu Jul  8 09:15:00 1993
  Subject: Cron <admin@ksp-04-11> /home/admin/bin/backup

  backup: 3 files copied
  admin@ksp-04-11:~$ mail
  No mail for admin

A cron line has nobody in front of it and the machine holds it to that.
Five commands want a pair of hands and refuse:

  edit: not a terminal

and the same line signed su:, passwd:, sudo: and rlogin:. clear runs and
clears nothing. exit ends the line and never a session.

The same is true of a job you started with an ampersand, and of a stage of
a pipeline: neither has anybody in front of it either.

  admin@ksp-04-11:~$ echo hi | su root
  su: not a terminal]],

[[Two things cron will not do.

It does not catch up. A machine that was switched off at four does not run
four o'clock's line when it comes back. A minute cron slept through is
gone. @reboot is the one that runs on the way up, and it runs then and not
for the minutes that went by while the machine was dark.

And it does not get more than its share. Four jobs at once is the whole
machine's ceiling, cron's lines included, and a line that comes due with
the machine full is SKIPPED and not queued. The log says so, in cron's own
words:

  (CRON) error (can't fork)

What ran is written to /var/log/cron, which is root's to read. Both the
log and the mailbox are bounded and neither costs you disk.

So: keep cron lines short and let them finish. A line that starts a loop
which never ends is a slot gone until somebody kills it, and three of
those is a machine that can no longer run anything at four.]],

[[Being far away is not being switched off.

A machine standing in a part of the county nobody has been near for a week
is still running, and cron is still running on it. It keeps its own clock,
its lines come due on time, and what they write is on the disk when you
get there. Walking off does not stop a machine; only the power going, the
switch, or somebody carrying it away does.

What it cannot do out there is touch the building. A line that writes a
file, adds up a log or posts you a report works exactly as it does under
your nose. A line that reaches for a door, a light or a sensor is answered

  light0: no such device

until you are back in the neighbourhood, because the wires to those things
are the room itself and the room is not there while nobody is.]],

[[.profile, which is a script too.

One more file runs without being asked, and it runs at login: ~/.profile.
If it is there and you may read it, every line of it is done after the
greeting and before your first prompt.

It is where the PATH line from chapter 1 goes to become permanent:

  admin@ksp-04-11:~$ cat .profile
  PATH=$PATH:$HOME/bin
  greeting=hello
  admin@ksp-04-11:~$ echo $PATH
  /bin:/home/admin/bin

It is READ, the way a dot reads a file, and not run as a program: that is
why a variable it sets is set at your prompt and a cd it does is where you
are standing. Its mistakes read like any script's.

And a script is the right place for a machine to keep a diary. One line
does it, and date makes every entry findable:

  echo "$(date) lights out" >> /home/admin/night.log

Classic mistake. exit in ~/.profile. It is not a file your session runs,
it IS your session, so exit logs you out the instant you log in, for ever.
The way back is root, which can edit the file for you.]],

		} },

		{ title = "10. The building, and the wire", pages = {

[[The building is a directory.

Volume 2 showed you /dev: the lights, the doors, the window latches and
the padlocks of the place this computer is standing in, each one a name
under /dev. Reading one tells you how it is. Writing one works it.

From a script that is all you need, because reading and writing are things
you already know how to do.

  admin@ksp-04-11:~$ cat /dev/light0
  off
  admin@ksp-04-11:~$ echo on > /dev/light0
  admin@ksp-04-11:~$ cat /dev/light0
  on

The words are few and each kind has its own. A light takes on and off. A
door takes open and close. A lock and a window latch take lock and
unlock. Anything else is refused before it reaches the world:

  admin@ksp-04-11:~$ echo blue > /dev/light0
  light0: invalid value

dev is the friendlier face of the same things and prints a table. dev with
one name is a question, and a name and a word is an order.

  admin@ksp-04-11:~$ dev door0
  door0: closed]],

[[Working a list of them.

ls prints one name per line when anything but a person is reading, which
is exactly what a catch wants. So the building comes apart into lists you
can loop over:

  admin@ksp-04-11:~$ cat off.sh
  #!/bin/sh
  for l in $(ls /dev | grep light); do
      echo off > /dev/$l
  done
  admin@ksp-04-11:~$ ./off.sh
  light2: no power
  admin@ksp-04-11:~$ dev light
  light0  office                2E 1N          off
  light1  hall                  5E 0N          off
  light2  yard                  9E 4N          on

Two lights went off and the third answered for itself. The loop did not
stop, and it never needed to know how many lights the building has.

The columns are the name, what it is near, where it is from this machine,
which side it is on, and how it is. Two lights both called "office" are
told apart by that third column and by nothing else.

Try the same loop with grep door and the word close in it.]],

[[Every refusal is a number as well as a line.

A device says its own name and its own reason, and it also finishes on a
number, so a script can act on it without reading English:

  admin@ksp-04-11:~$ echo on > /dev/light2
  light2: no power
  admin@ksp-04-11:~$ echo $?
  1

Which means an if around it is the whole of the error handling:

  admin@ksp-04-11:~$ cat lights.sh
  #!/bin/sh
  if [ $# -lt 1 ]; then
      echo "usage: lights.sh on|off"
      exit 2
  fi
  for l in $(ls /dev | grep light); do
      if echo $1 > /dev/$l; then
          echo $l is now $1
      else
          echo $l would not answer
      fi
  done
  admin@ksp-04-11:~$ ./lights.sh on
  light0 is now on
  light1 is now on
  light2: no power
  light2 would not answer

The reasons you will meet: no power, no such device, smashed, barricaded,
blocked, locked, no padlock and invalid value.]],

[[Watching, which is the loop from chapter 5.

Here is the door alarm, whole, and it is nine lines.

  admin@ksp-04-11:~$ cat watch.sh
  #!/bin/sh
  # Watch one door. Light the office when it opens.
  log=/home/admin/watch.log
  while [ "$(cat /dev/door0)" = closed ]; do
      sleep 5
  done
  echo on > /dev/light0
  echo "$(date +%H:%M) front door opened" >> $log
  echo "the front door opened"
  admin@ksp-04-11:~$ ./watch.sh &
  [1] 43
  the front door opened
  [1] done
  admin@ksp-04-11:~$ cat watch.log
  09:15 front door opened

That ran. Somebody opened that door while the loop was asleep between two
glances, and the loop noticed on the next one.

Note the absolute path in log. $HOME/watch.log works as well -- a job
behind the prompt starts with a copy of your own variables, and a cron line
gets HOME -- but a path written out in full is one less thing to be wrong
about a script that runs while nobody is watching.]],

[[Reaching another machine from a script.

Volume 2 has the wire in full: /etc/hosts, the trust files, rlogin. Three
things from it matter here.

rsh runs ONE command on another machine and needs nobody at either
keyboard, which is why a crontab calls rsh and never rlogin. It needs the
other machine to trust this one -- /etc/hosts.equiv there, or a ~/.rhosts
in the account's own home, 600 and its own -- or it says so:

  admin@ksp-04-11:~$ rsh gate ls
  rsh: gate: Permission denied

rcp copies a file to or from another machine. One end carries the machine's
name and a colon:

  admin@ksp-04-11:~$ rcp notes.txt gate:/home/admin/note
  admin@ksp-04-11:~$ echo $?
  0

It says nothing when it worked, and it takes a moment: the wire is not
instant.

The refusals are worth knowing by their words: unknown host means no line
of /etc/hosts carries that name; Host is down means it is on the wire and
switched off; No route to host means there is no wire between here and
there at all.]],

[[What an rsh in a file does while it waits.

rsh waits for the far machine and then goes on. Your job is parked while
the other computer runs the command -- it spends nothing at all doing that,
and ps shows it with a W -- and what the far command printed arrives where
anything else on the line would have gone.

  admin@ksp-04-11:~$ cat night.sh
  #!/bin/sh
  echo before
  rsh gate dev light0
  echo "after, $?"
  admin@ksp-04-11:~$ ./night.sh
  before
  light0: on
  after, 0

So $? after an rsh is the FAR command's status, a catch holds what it
printed, and a pipe is fed by it. What you cannot do is type at it: an rsh
is one command and not a session, and the keyboard stays here.

A remote command that never ends leaves your job waiting for ever, and
jobs says which wait it is:

  admin@ksp-04-11:~$ jobs
  [1] remote   rsh gate sleep 300 &

Escape, or kill, and the session over there goes with it.]],

[[rcp waits the same way, and always has.

  admin@ksp-04-11:~$ cat backup.sh
  #!/bin/sh
  host=gate
  for f in notes.txt log; do
      if rcp $f $host:/home/admin/$f; then
          echo $f copied to $host
      else
          echo $f did not go
      fi
  done
  admin@ksp-04-11:~$ ./backup.sh
  notes.txt copied to gate
  log copied to gate

Classic mistake. A device number written into a script for ever. A light
that is light1 today is not promised to be light1 next week. Find the thing
by what it is.]],

		} },

		{ title = "11. Five programs that work", pages = {

[[Five whole programs, each one run on a real machine before it was
printed. Type them, run them, then change them: a program you have altered
once is a program you understand.

Number one. The lights, with the argument checked.

  #!/bin/sh
  # lights.sh on|off -- every light in the building.
  if [ $# -lt 1 ]; then
      echo "usage: lights.sh on|off"
      exit 2
  fi
  if [ "$1" != on -a "$1" != off ]; then
      echo "lights.sh: $1: not on or off"
      exit 2
  fi
  for l in $(ls /dev | grep light); do
      if echo $1 > /dev/$l; then
          echo $l is now $1
      else
          echo $l would not answer
      fi
  done

Three things to notice. It checks before it acts. It refuses with a number
as well as a line, so something else can test it. And it says what it did,
one light at a time, so a light that would not answer is not a silence.]],

[[Number two. Shutting the place, once a night, with nobody there.

  #!/bin/sh
  # lockup.sh -- run by cron at ten every night.
  log=/home/admin/lockup.log
  echo "$(date) locking up" >> $log
  for d in $(ls /dev | grep door); do
      echo close > /dev/$d
  done
  for l in $(ls /dev | grep lock); do
      echo lock > /dev/$l || echo "$l refused" >> $log
  done
  for w in $(ls /dev | grep win); do
      echo lock > /dev/$w || echo "$w refused" >> $log
  done
  for b in $(ls /dev | grep light); do
      echo off > /dev/$b
  done
  echo "$(date +%H:%M) done" >> $log

And the line that runs it. The whole path, because cron's PATH is /bin:

  0 22 * * * /home/admin/bin/lockup.sh

Run once on a real building, it left this in the log. One window had been
broken during the day:

  Thu Jul  8 09:15:00 1993 locking up
  win1 refused
  09:15 done]],

[[Number three. The night watch, with a log and a lamp.

  #!/bin/sh
  # watch.sh -- shout when sensor0 sees anything move.
  log=/home/admin/watch.log
  while [ "$(cat /dev/sensor0)" = clear ]; do
      sleep 4
  done
  echo on > /dev/light0
  echo "$(date +%H:%M) movement in the office" >> $log
  echo "something is moving in the office"

  admin@ksp-04-11:~$ ./watch.sh &
  [1] 43
  something is moving in the office
  [1] done

Start it from the crontab at the other end of the day, and it watches
while nobody watches it:

  0 22 * * * /home/admin/bin/watch.sh

Three honest limits. Four seconds is not a guess: a contact is held five,
so a sleep of four cannot step over one and a sleep of ten can. It watches
ONE sensor; watch several with a for inside a while true and the sleep at
the bottom. And it ends on the first contact, so it says so once -- a loop
round the lot says so every night.]],

[[Number four. Keeping a log from eating the disk.

Thirty-two kilobytes is the whole drive, so anything that writes every
night has to be cut back. tail keeps the end of a file and wc counts it.

  #!/bin/sh
  # rotate.sh -- keep the last ten lines of the log.
  log=$HOME/watch.log
  keep=10
  n=$(cat $log | wc -l)
  echo "$log holds $n lines"
  if [ $n -gt $keep ]; then
      cat $log | tail -n $keep > $log.new
      mv $log.new $log
      echo "cut back to $keep"
  fi

  admin@ksp-04-11:~$ ./rotate.sh
  /home/admin/watch.log holds 30 lines
  cut back to 10
  admin@ksp-04-11:~$ head -n 1 watch.log
  entry 21

There is no rm before the mv, and there must not be one. mv writes over
the file already there -- a rename points a name somewhere else, and what
it pointed at is gone -- so the new log takes the old name in one step,
with no moment in which the log is missing. An earlier draft of this page
had the rm, and with it a gap where a cron job would have found no log.]],

[[Number five. A menu, for somebody who does not want to learn any of this.

  #!/bin/sh
  # office.sh -- the four things anybody needs.
  echo "1  lights on"
  echo "2  lights off"
  echo "3  lock up"
  echo "4  quit"
  read -p "choice? " n
  if [ "$n" = 1 ]; then
      lights.sh on
  elif [ "$n" = 2 ]; then
      lights.sh off
  elif [ "$n" = 3 ]; then
      lockup.sh
  elif [ "$n" = 4 ]; then
      echo nothing done
  else
      echo "office.sh: $n: not a choice"
      exit 2
  fi

Put it in ~/bin with x on it and the person at the desk types one word.
Quote the answer every time it is read, because somebody will press Enter
at that question and you want a "not a choice", not a refusal.

Classic mistake. Writing a menu that keeps asking in a while true loop and
forgetting to give it a way out. Number four is that way out, and it is in
every menu in this book for a reason.]],

		} },

		{ title = "12. Appendix: the grammar, and what the machine says", pages = {

[[The whole language, on this page and the next.

A program is a list of commands, separated by a semicolon or a new line.
A command may be followed by an ampersand to run it behind the prompt.

  cmd ; cmd        one after the other
  cmd && cmd       the second only if the first worked
  cmd || cmd       the second only if the first failed
  cmd | cmd        the first's output into the second
  cmd > file       output into a file, replacing it
  cmd >> file      output onto the end of a file
  cmd &            run it behind the prompt

The eleven reserved words. They mean this only where a command starts, so
echo done prints "done":

  if then elif else fi
  for in while until do done

The shapes they build:

  if LIST; then LIST; elif LIST; then LIST; else LIST; fi
  for NAME in WORDS; do LIST; done
  while LIST; do LIST; done
  until LIST; do LIST; done

Sixteen deep is as far as these nest, and eight is as long as a pipeline
may be.]],

[[The dollar signs, all of them.

  $NAME ${NAME}   a variable
  $1 .. $9        the words handed to this script
  $0              the script's own name
  $#              how many words were handed over
  $@              all of them
  $?              the number the last command finished on
  $$              this job's number
  $(command)      what the command printed, as a word
  $((2 + 3))      arithmetic: + - * / % and brackets

Assignment is NAME=value with no blanks near the equals sign.

Quoting: double quotes hold a word together and let a dollar sign work;
single quotes let nothing through; a backslash takes the meaning off one
character. A pound sign starts a comment.

Thirteen words the shell runs itself, with no file in /bin needed:

  . break cd continue export exit fg
  history jobs read shift type wait

Everything else you type is a FILE, found by walking PATH: echo, printf
and test are files in /bin, which is why ls /bin is the honest list of
what this machine can do.]],

[[The three shapes about the environment, and the dot.

  export NAME[=value]...
      put one or more names in the environment, with a
      value or with the one they already have. With no
      name at all it lists what is in it, one a line,
      in the shape you would type back
  env
      the environment as it will be handed over,
      NAME=value, one a line, sorted
  . <file>
      read the file in THIS shell, so what it sets is
      still set afterwards. It wants r on the file and
      not x, because nothing runs it

sh <file> is the other half of the last one: that runs the file as a
program, which is handed a copy of the environment and can change nothing
of yours. Chapter 1 has the pair side by side and chapter 3 has export.]],

[[What the shell says before anything runs. A script that meets one never
becomes a job: not one line of it happens.

A script signs these with its own name and line -- broken.sh: line 3: --
and a typed line is signed sh:, with no number.

  syntax error: unexpected 'fi'
      a closing word where a command should be; also
      'done', 'then', 'else', 'elif', 'do' and '<'
  syntax error: missing 'done'
      a loop never closed; also 'fi', 'then' and 'do'
  syntax error: not a name
      for wants a variable name straight after it
  syntax error: unterminated quote
      a quote opened and never closed
  syntax error: bad substitution
      a $( ) in a $( ), an unclosed ${ or $(( , or a
      name in braces that is not a name
  syntax error: bad redirect
      two redirects on one command
  syntax error: missing redirect target
      a > or >> with no file named after it
  too deeply nested
      past sixteen levels
  too many stages
      more than eight stages in one pipeline]],

[[What stops a script while it is running. These happen on a line, so the
line is named, and the script ends there.

  too many variables
      a sixty-fifth name
  variable too large
  word too large
      past 1024 bytes: written, built, or caught
  bad arithmetic
      the thing in $(( )) is not a sum
  divide by zero
  ambiguous redirect
      the name after > came out as two words, or none
  sort: input too large
      sort and uniq must see all their input before they
      answer, so they hold a hundred lines and four
      kilobytes of it and no more
  test: integer expected
      -eq and its five friends were handed something
      that is not a number
  test: unknown operator
  test: missing ']'
  test: argument expected
  read: not a name
  sleep: invalid interval
  sleep: no clock
  edit: not a terminal
      also signed su:, passwd:, sudo: and rlogin:; all
      five want a pair of hands, and a cron line, an
      ampersand and a pipeline stage have none]],

[[What the machine says about jobs. No script signs these, because they
are not a script's to say.

  sh: too many jobs
      a fifth job; four is the ceiling
  kill: <id>: no such job
  fg: no current job
      nothing is running behind the prompt
  fg: %<n>: no such job
  killed
  killed: cpu limit
      Escape or kill; then five minutes of spinning
  [1] 42
  [1] done
  [1] exit 3
  [1] killed
      a job starting, ending, failing, taken away

And the ones about finding a program at all:

  <name>: command not found
      nothing on PATH answers to it
  ./thing: permission denied
      it is there and it has no x on it for you
  too many PATH entries
      PATH may name eight directories
  type: <name>: not found
  sh: usage: sh <file> [args]
  sh: !<n>: event not found

The shapes of the words this volume leans on, which no card in Volumes 1
and 2 carries:

  sh <file> [args]        test <expression>
  [ <expression> ]        wait [id]...
  printf <format> [arg...]    true    false]],

[[The reasons off the disk, each wearing the command's name and the path
first: cat: notes: no such file.

  no such file          is a directory
  not a directory       permission denied
  invalid characters    invalid destination
  path too deep         directory not empty
  file too large        directory full
  file exists   invalid name   is a device
  disk full     /dev: read-only

A device answers in its OWN name and no command's:

  light0: no power       lock0: no such device
  win0: smashed          win0: barricaded
  lock1: no padlock      light0: invalid value
  win0: cannot toggle    door0: locked
  door0: barricaded      door0: blocked

And cron's own, and the wire's:

  "/var/spool/cron/admin":1: bad minute
      also bad hour, bad day-of-month, bad month,
      bad day-of-week, bad command, bad time specifier
      and, past thirty-two lines, too many entries
  (CRON) error (can't fork)
  no crontab for <name>    No mail for <name>
  rsh: gate: Permission denied]],

[[The last page, and the one to keep.

Six things, in the order they will save you.

A script is only the words you already type. If you can do it at the
prompt you can write it down; if you cannot, no file will help.

Quote what came from outside: "$1", "$x", "$(cat /dev/door0)". Every ugly
bug here was an unquoted empty word.

Put a sleep in every loop that watches. A sleeping script costs nothing
and can wait a week; a spinning one gets five minutes.

Say what went wrong and finish on a number. exit 2 and one honest line is
what makes it a program and not a pile of commands.

Never write a device number into a file that has to work next month.

And run it before you trust it. Every screen here was copied off a machine
that had done the thing, and three came out different from what the author
expected. Yours will too.

Classic mistake. Reading this page and not the chapters. It is the answers
with no reasons attached, and a reason is the only part of any use at two
in the morning.]],

		} },

	},
}
