--
-- The self-test's third half: the SHELL, run on the VM the game has.
--
-- CeroSecSelfTest.run() weighs the engine's pure functions and runSave() the save
-- path of one machine. Neither of them types a line. The diagnostics floppy does
-- (`sh /mnt/selftest.sh`), and it holds twenty-six checks because a floppy holds
-- 4096 bytes -- a suite of every command and every rule of this release's shell
-- does not fit on one. So the suite is here, as a table the mod ships, and the
-- debug window's Self-test runs it after the other two halves.
--
-- WHAT A CASE IS. A line typed at a prompt, what the screen shows, what $? is
-- after it, and -- where the point of the line is a file -- what the file holds
-- afterwards:
--
--   { name = "...",            unique; what a failure is called in the log
--     files = { { path, text, mode }, ... },   written before anything runs
--     setup = { "line", ... }, typed first, their output thrown away
--     line = "...",            the line under test
--     input = { "...", ... },  answers, one per question the line asks
--     out = { "...", ... },    every line the screen shows, in order
--     status = n,              $? after it
--     want = { { path = p, text = t, mode = m, owner = o, absent = true } },
--     dev = "name" }           the entry of CeroSecOS.DEVIATIONS the answer
--                              leans on, when it is not what 1993 printed
--
-- Every expected answer is what a real 1993 sh or Unix command prints, or it is
-- a DECLARED deviation and says which one (tests/selftest_shell_test.lua holds
-- every `dev` to a name in CeroSecOS.DEVIATIONS). The screen has one stream (the
-- `stderr` deviation), so an error and an output line are both in `out`; which
-- stream a line was on is asked with a redirect, the way a real user asks it.
--
-- THE MACHINE IS A SCRATCH ONE. One state is made with CeroSecOS.newState -- the
-- very constructor a new computer's first power-on uses -- and every case runs on
-- a deep copy of it, so no case sees another's files and no case can be passed by
-- the one before it. Nothing here reaches the world: the env handed to jobStep
-- holds a fixed clock and an empty job book and nothing else -- no devices, no
-- network, no machine -- so a case can name no door, no modem and no other
-- computer, and there is no ModData, no save and no wire under any of it. What it
-- cannot run for that reason is listed at the bottom of the table, with why.
--
-- Kahlua-pure, like the rest of shared/: no metatable, no coroutine, no io, no os,
-- no loadstring, and nothing of CeroSecOS touched at the top level, because the
-- game loads shared/CeroSec/ ahead of shared/CeroSec/OS/.
--

CeroSecSelfTest = CeroSecSelfTest or {}

-- The clock the scratch machine sees. Fixed, so a case that prints a date prints
-- the same one on every run: 740000000 is 1993-06-13 19:33:20 UTC.
CeroSecSelfTest.SHELL_NOW = 740000000
-- How far the wall clock moves between two passes of a job, in ms. A `sleep 1`
-- is four passes.
CeroSecSelfTest.SHELL_STEP_MS = 250
-- The passes a line may take. A line that has not finished by then is a case
-- that was never evaluated, and it is counted as a failure.
CeroSecSelfTest.SHELL_PASSES = 400
-- The steps a pass may take, which is what the scheduler hands a job.
CeroSecSelfTest.SHELL_BUDGET = 1000

--
-- 1. The cases
--

CeroSecSelfTest.SHELL_CASES = {
	--
	-- 1a. The grammar: words, quotes, variables, $( ), $(( )), status
	--
	{ name = "echo", line = "echo hello   world", out = { "hello world" } },
	{ name = "echo -n", line = "echo -n a; echo b", out = { "ab" } },
	{ name = "quotes keep blanks", line = "echo 'a  b' \"c  d\"", out = { "a  b c  d" } },
	-- sh(1): inside double quotes a backslash quotes only $ ` " \ and newline, and
	-- stays a backslash before anything else.
	{ name = "double-quote backslash",
		line = "printf '%s %s %s\\n' \"a\\$b\" \"c\\\\d\" \"e\\q\"",
		out = { "a$b c\\d e\\q" } },
	{ name = "single quotes keep backslash", line = "printf '%s\\n' 'a\\b'",
		out = { "a\\b" } },
	{ name = "variable", line = "x=5; echo $x${x}", out = { "55" } },
	{ name = "unset variable is empty", line = "echo \"[$nosuch]\"", out = { "[]" } },
	{ name = "arithmetic", line = "echo $((2 + 3 * 4)) $(( (7 + 3) / 2 )) $((7 / 2))",
		out = { "14 5 3" } },
	{ name = "arithmetic remainder sign", line = "echo $((-7 % 3)) $((7 % -3))",
		out = { "-1 1" } },
	{ name = "arithmetic on a variable", line = "i=4; i=$((i * 2 + 1)); echo $i",
		out = { "9" } },
	{ name = "command substitution", line = "x=$(echo hi); echo \"[$x]\"", out = { "[hi]" } },
	{ name = "substitution unquoted splits", line = "echo $(printf 'a\\nb\\n')",
		out = { "a b" } },
	{ name = "true and false", line = "true; echo $?; false; echo $?", out = { "0", "1" } },
	{ name = "not found is 127", line = "nosuch; echo $?",
		out = { "nosuch: command not found", "127" }, dev = "sh" },
	{ name = "and or", line = "false && echo a || echo b; true && echo c",
		out = { "b", "c" } },
	{ name = "status of a pipeline is its last stage",
		line = "false | true; echo $?; true | false; echo $?", out = { "0", "1" } },
	{ name = "semicolons", line = "echo a; echo b;echo c", out = { "a", "b", "c" } },
	{ name = "comment", line = "echo a # not this", out = { "a" } },
	{ name = "glob", setup = { "touch b.c; touch a.c; touch d.h" }, line = "echo *.c",
		out = { "a.c b.c" } },
	{ name = "glob with no match stays", line = "echo *.zz", out = { "*.zz" } },

	--
	-- 1b. Control flow
	--
	{ name = "if", line = "if [ 1 -lt 2 ]; then echo y; else echo n; fi", out = { "y" } },
	{ name = "elif", line = "x=2; if [ $x = 1 ]; then echo 1; elif [ $x = 2 ]; then echo 2; fi",
		out = { "2" } },
	{ name = "for", line = "for i in a b c; do echo $i; done", out = { "a", "b", "c" } },
	{ name = "while", line = "i=0; while [ $i -lt 3 ]; do i=$((i + 1)); done; echo $i",
		out = { "3" } },
	{ name = "until", line = "i=0; until [ $i -ge 2 ]; do echo $i; i=$((i + 1)); done",
		out = { "0", "1" } },
	{ name = "break and continue",
		line = "for i in 1 2 3 4; do [ $i = 2 ] && continue; [ $i = 4 ] && break; echo $i; done",
		out = { "1", "3" } },
	{ name = "case", line = "case abc in x*) echo X;; a*) echo A;; *) echo O;; esac",
		out = { "A" } },
	{ name = "case default", line = "case zz in a) echo A;; *) echo O;; esac", out = { "O" } },
	{ name = "function", line = "f() { echo \"f:$1:$2\"; }; f x y", out = { "f:x:y" } },
	{ name = "for over a pipe", line = "for w in a b; do echo $w; done | sort -r",
		out = { "b", "a" } },

	--
	-- 1c. Scripts: arguments, $#, $*, $@, shift, exit, `.`
	--
	{ name = "script arguments",
		files = { { "/root/s.sh", "echo $#\necho \"$*\"\nfor a in $@; do echo \"<$a>\"; done" } },
		line = "sh s.sh 'a b' c", out = { "2", "a b c", "<a>", "<b>", "<c>" } },
	{ name = "x=$@ with two arguments", files = { { "/root/s.sh", "x=$@\necho \"[$x]\"" } },
		line = "sh s.sh a b", out = { "[a b]" } },
	{ name = "shift", files = { { "/root/s.sh", "shift\necho $1 $#" } },
		line = "sh s.sh a b c", out = { "b 2" } },
	{ name = "exit status of a script", files = { { "/root/s.sh", "echo in\nexit 3\necho no" } },
		line = "sh s.sh; echo $?", out = { "in", "3" } },
	{ name = "dot runs in this shell", files = { { "/root/inc", "y=7" } },
		line = ". /root/inc; echo $y", out = { "7" } },
	{ name = "export", line = "export Z=1; env | grep '^Z='", out = { "Z=1" } },
	{ name = "plain variable is not exported", line = "Q=1; env > f; grep -c '^Q=' f",
		out = { "0" }, status = 1 },

	--
	-- 1d. read
	--
	{ name = "read multi-name",
		line = "echo a b c | while read x y; do echo \"$x|$y\"; done", out = { "a|b c" } },
	{ name = "read without -r eats backslash",
		line = "printf '%s\\n' 'a\\b' | while read x; do echo \"$x\"; done", out = { "ab" } },
	{ name = "read -r keeps backslash",
		line = "printf '%s\\n' 'a\\b' | while read -r x; do echo \"$x\"; done",
		out = { "a\\b" } },
	-- bash's read -n: n characters, or up to a newline, whichever comes first.
	{ name = "read -n on a pipe",
		line = "printf 'abcdef\\nxy\\n' | while read -n 2 x; do printf '[%s]' \"$x\"; done",
		out = { "[ab][cd][ef][][xy][]" }, dev = "read" },
	{ name = "read at the end of input fails",
		line = "printf 'a\\n' | while read x; do echo $x; done; echo $?", out = { "a", "0" } },
	{ name = "read from the terminal", line = "read a b; echo \"$b,$a\"",
		input = { "one two three" }, out = { "two three,one" } },

	--
	-- 1e. Redirects, and this release's rules for them
	--
	{ name = "redirect writes a file", line = "echo hi > f; cat f", out = { "hi" },
		want = { { path = "/root/f", text = "hi\n" } } },
	{ name = "append", line = "echo a > f; echo b >> f; cat f", out = { "a", "b" } },
	-- sh opens the file BEFORE it runs the command: a redirect that cannot be
	-- opened means the command never runs.
	{ name = "redirect opened before the command",
		files = { { "/root/f", "x" }, { "/root/s.sh", "rm f > /nosuchdir/x\necho $?" } },
		line = "sh s.sh 2>/dev/null", out = { "1" },
		want = { { path = "/root/f", text = "x" } } },
	{ name = "a failed command still made its file", line = "cat nosuch > out; echo $?",
		out = { "cat: nosuch: no such file", "1" },
		want = { { path = "/root/out", text = "" } }, dev = "refusal" },
	{ name = "2> to a file", line = "cat nosuch 2> e; echo $?; cat e",
		out = { "1", "cat: nosuch: no such file" }, dev = "refusal" },
	{ name = "2>/dev/null", line = "cat nosuch 2>/dev/null; echo $?", out = { "1" } },
	{ name = "error does not go down the pipe", line = "cat nosuch | tr a-z A-Z",
		out = { "cat: nosuch: no such file" }, dev = "refusal" },
	{ name = "2>&1 goes down the pipe", line = "cat nosuch 2>&1 | tr a-z A-Z",
		out = { "CAT: NOSUCH: NO SUCH FILE" }, dev = "refusal" },
	{ name = "> f 2>&1 puts both in f", line = "cat nosuch > f 2>&1; echo \"[$(cat f)]\"",
		out = { "[cat: nosuch: no such file]" }, dev = "refusal" },
	-- Left to right: 2>&1 copies the output as it is THEN, the screen.
	{ name = "2>&1 > f leaves the error on the screen",
		line = "cat nosuch 2>&1 > f; echo \"[$(cat f)]\"",
		out = { "cat: nosuch: no such file", "[]" }, dev = "refusal" },
	{ name = ">&2 is the error", line = "f() { echo e >&2; echo o; }; f 2>/dev/null",
		out = { "o" } },
	{ name = "$( ) does not catch the error", line = "x=$(cat nosuch); echo \"[$x]\"",
		out = { "cat: nosuch: no such file", "[]" }, dev = "refusal" },
	{ name = "$( ) catches it with 2>&1", line = "x=$(cat nosuch 2>&1); echo \"[$x]\"",
		out = { "[cat: nosuch: no such file]" }, dev = "refusal" },
	-- The pipe is set up before the stage's own redirects, so they win.
	{ name = "a stage's own redirect wins over the pipe",
		line = "g() { echo a; echo b; }; echo $(g > f | wc -l); cat f",
		out = { "0", "a", "b" } },
	{ name = "a redirect wins over $( )",
		line = "g() { echo hi; }; x=$(g > f); echo \"[$x]\"; cat f", out = { "[]", "hi" } },
	{ name = "echo a > f | true", line = "echo a > f | true; cat f", out = { "a" } },
	{ name = "the file is complete for the next command",
		line = "printf '1\\n2\\n3\\n' > f; tail -1 f; echo $(cat f | wc -l)",
		out = { "3", "3" } },
	{ name = "redirect into /dev/null", line = "echo gone > /dev/null; echo $?", out = { "0" } },

	--
	-- 1f. printf
	--
	{ name = "printf conversions", line = "printf '%s-%d-%s\\n' x 42 'y z'",
		out = { "x-42-y z" } },
	{ name = "printf escapes", line = "printf 'a\\tb\\\\%%\\n' > f",
		want = { { path = "/root/f", text = "a\tb\\%\n" } } },
	{ name = "printf no newline", line = "printf abc; echo", out = { "abc" } },

	--
	-- 1g. test and [
	--
	{ name = "test on files", files = { { "/root/f", "x" } }, setup = { "mkdir d; touch e" },
		line = "[ -f f ] && [ -d d ] && [ -e e ] && [ ! -d f ] && [ ! -e g ] && echo ok",
		out = { "ok" } },
	{ name = "test on strings", line = "[ -z '' ] && [ -n a ] && [ a = a ] && [ a != b ] && echo ok",
		out = { "ok" } },
	{ name = "test on numbers",
		line = "[ 2 -eq 2 ] && [ 2 -ne 3 ] && [ 3 -gt 2 ] && [ 2 -le 2 ] && echo ok",
		out = { "ok" } },
	{ name = "test -a -o and !", line = "test 1 -eq 1 -a ! 1 -eq 2 && test 1 = 2 -o a = a; echo $?",
		out = { "0" } },
	{ name = "test false is 1", line = "test a = b; echo $?", out = { "1" } },
	{ name = "test error is 2 and not fatal", files = { { "/root/s.sh", "[ a -lt 1 ]\necho $?" } },
		line = "sh s.sh 2>/dev/null", out = { "2" } },
	{ name = "test error goes to stderr", line = "x=$([ a -lt 1 ] 2>/dev/null); echo \"[$x]\"",
		out = { "[]" } },
	{ name = "sleep error is not fatal", files = { { "/root/s.sh", "sleep x\necho $?" } },
		line = "sh s.sh 2>/dev/null", out = { "1" } },
	{ name = "sleep", line = "sleep 1; echo slept", out = { "slept" } },
	{ name = "$! before any &", line = "echo \"[$!]\"", out = { "[]" } },
	{ name = "$! after an &", line = "sleep 1 & [ -n \"$!\" ] && echo set", out = { "set" } },
	{ name = "126 for a file that is not executable",
		files = { { "/root/s", "echo hi", 644 } }, line = "./s 2>/dev/null; echo $?",
		out = { "126" } },
	{ name = "a script with x runs by its path",
		files = { { "/root/s", "echo ran $1", 755 } }, line = "./s a; echo $?",
		out = { "ran a", "0" } },
	{ name = "$? of a failed command", line = "ls /nosuch 2>/dev/null; echo $?", out = { "1" } },

	--
	-- 2. The commands, one or more cases each. Numbers that a real command pads
	-- into a column are read through `echo $(...)`, which is what a script does
	-- with them anyway.
	--

	-- The directory the shell is in.
	{ name = "pwd", line = "pwd", out = { "/root" } },
	{ name = "cd", line = "cd /etc; pwd", out = { "/etc" } },
	{ name = "cd with no operand goes home", line = "cd /etc; cd; pwd", out = { "/root" } },
	{ name = "cd ..", line = "cd /etc; cd ..; pwd", out = { "/" } },
	{ name = "cd to nothing fails", line = "cd /nosuch 2>/dev/null; echo $?; pwd",
		out = { "1", "/root" } },

	-- ls. Down a pipe it is one name a line, as ls has always been when its output
	-- is not a terminal.
	{ name = "ls down a pipe", setup = { "mkdir d; touch d/b; touch d/a" },
		line = "ls d | cat", out = { "a", "b" } },
	{ name = "ls -1", setup = { "mkdir d; touch d/b; touch d/a" }, line = "ls -1 d",
		out = { "a", "b" } },
	{ name = "ls hides dot files", setup = { "mkdir d; touch d/.h; touch d/a" },
		line = "ls -1 d", out = { "a" } },
	{ name = "ls -a", setup = { "mkdir d; touch d/.h" }, line = "ls -1a d",
		out = { ".", "..", ".h" } },
	{ name = "ls -A", setup = { "mkdir d; touch d/.h" }, line = "ls -1A d", out = { ".h" } },
	{ name = "ls -F", setup = { "mkdir d; touch f" }, line = "ls -1F", out = { "d/", "f" } },
	{ name = "ls several operands", setup = { "touch b; touch a; mkdir d; touch d/c" },
		line = "ls -1 b a d", out = { "a", "b", "", "d:", "c" } },
	{ name = "ls of nothing", line = "ls nosuch 2>/dev/null; echo $?", out = { "1" } },

	-- cat
	{ name = "cat", files = { { "/root/f", "1\n2" } }, line = "cat f", out = { "1", "2" } },
	-- cat copies bytes: a file whose last line has no newline runs into the
	-- next one, as it does on a real terminal.
	{ name = "cat several", files = { { "/root/a", "1" }, { "/root/b", "2" } },
		line = "cat a b", out = { "12" } },
	{ name = "cat - is the input", files = { { "/root/a", "1" }, { "/root/b", "3" } },
		line = "echo 2 | cat a - b", out = { "12", "3" } },
	{ name = "cat -n", line = "printf 'a\\nb\\n' | cat -n > f",
		want = { { path = "/root/f", text = "     1\ta\n     2\tb\n" } } },
	{ name = "cat -- ends the options", files = { { "/root/a", "1" } },
		line = "cat -- a", out = { "1" } },
	-- cat goes on past a file it cannot open, and says 1 -- but the half that
	-- worked goes with the error, into /dev/null (the `stderr` deviation).
	{ name = "cat of nothing goes on", files = { { "/root/a", "1" } },
		line = "cat nosuch a 2>/dev/null; echo $?", out = { "1" }, dev = "stderr" },

	-- head, tail
	{ name = "head -n", files = { { "/root/f", "1\n2\n3\n4" } }, line = "head -n 2 f",
		out = { "1", "2" } },
	{ name = "head -N", files = { { "/root/f", "1\n2\n3\n4" } }, line = "head -1 f",
		out = { "1" } },
	{ name = "head of a pipe", line = "printf '1\\n2\\n3\\n' | head -n 2", out = { "1", "2" } },
	{ name = "tail -n", files = { { "/root/f", "1\n2\n3\n4" } }, line = "tail -n 2 f",
		out = { "3", "4" } },
	{ name = "tail -N", files = { { "/root/f", "1\n2\n3\n4" } }, line = "tail -1 f",
		out = { "4" } },
	{ name = "tail +N is not here", files = { { "/root/f", "1" } },
		line = "tail +1 f 2>/dev/null; echo $?", out = { "1" }, dev = "tail" },

	-- sort, uniq
	{ name = "sort", line = "printf 'b\\na\\nc\\n' | sort", out = { "a", "b", "c" } },
	{ name = "sort -r", line = "printf 'a\\nb\\n' | sort -r", out = { "b", "a" } },
	{ name = "sort is by character", line = "printf '10\\n9\\n' | sort", out = { "10", "9" } },
	{ name = "sort -n", line = "printf '10\\n9\\n' | sort -n", out = { "9", "10" } },
	{ name = "sort -u", line = "printf 'b\\na\\nb\\n' | sort -u", out = { "a", "b" } },
	{ name = "sort a file", files = { { "/root/f", "z\ny" } }, line = "sort f", out = { "y", "z" } },
	{ name = "uniq", line = "printf 'a\\na\\nb\\na\\n' | uniq", out = { "a", "b", "a" } },
	{ name = "uniq -c", line = "echo $(printf 'a\\na\\nb\\n' | uniq -c)", out = { "2 a 1 b" } },

	-- cut, tr
	{ name = "cut -c", line = "echo abcdef | cut -c 2-3", out = { "bc" } },
	{ name = "cut -d -f", line = "echo a:b:c | cut -d : -f 2", out = { "b" } },
	{ name = "cut -f list", line = "echo a:b:c | cut -d : -f 1,3", out = { "a:c" } },
	{ name = "tr", line = "echo hello | tr a-z A-Z", out = { "HELLO" } },
	{ name = "tr -d", line = "echo hello | tr -d l", out = { "heo" } },

	-- wc: a pipe's text is its lines, and nothing follows the last one.
	{ name = "wc -l", line = "echo $(printf 'a\\nb\\nc\\n' | wc -l)", out = { "3" } },
	{ name = "wc -w", line = "echo $(echo one two three | wc -w)", out = { "3" } },
	{ name = "wc -c", line = "echo $(echo abc | wc -c)", out = { "4" } },
	-- wc -l counts newlines: a last line without one is not counted.
	{ name = "wc of a file names it", files = { { "/root/f", "a b\nc" } },
		line = "echo $(wc -l -w f)", out = { "1 3 f" } },

	-- grep
	{ name = "grep", files = { { "/root/f", "apple\nBanana\ncherry" } }, line = "grep an f",
		out = { "Banana" } },
	{ name = "grep -i", files = { { "/root/f", "apple\nBanana\ncherry" } },
		line = "grep -i b f", out = { "Banana" } },
	{ name = "grep -c", files = { { "/root/f", "apple\nBanana\ncherry" } },
		line = "grep -c a f", out = { "2" } },
	{ name = "grep -v", files = { { "/root/f", "apple\nBanana\ncherry" } },
		line = "grep -v a f", out = { "cherry" } },
	{ name = "grep -n", files = { { "/root/f", "apple\nBanana\ncherry" } },
		line = "grep -n e f", out = { "1:apple", "3:cherry" } },
	{ name = "grep -e", files = { { "/root/f", "-x\ny" } }, line = "grep -e -x f",
		out = { "-x" } },
	{ name = "grep anchors", files = { { "/root/f", "ab\nba" } }, line = "grep '^a' f",
		out = { "ab" } },
	{ name = "grep with no match is 1", files = { { "/root/f", "a" } },
		line = "grep zz f; echo $?", out = { "1" } },
	{ name = "grep of a pipe", line = "printf 'a\\nb\\n' | grep b", out = { "b" } },
	{ name = "grep several files names them", files = { { "/root/a", "x" }, { "/root/b", "x" } },
		line = "grep x a b", out = { "a:x", "b:x" } },

	-- tee, more
	{ name = "tee", line = "echo hi | tee f; cat f", out = { "hi", "hi" } },
	{ name = "tee -a", files = { { "/root/f", "a" } },
		line = "echo b | tee -a f > /dev/null; cat f", out = { "ab" } },
	{ name = "more on a pipe is cat", line = "printf 'a\\nb\\n' | more", out = { "a", "b" } },

	-- mkdir, rm, mv, cp, touch, ln
	{ name = "mkdir", line = "mkdir d; [ -d d ] && echo y", out = { "y" } },
	{ name = "mkdir of one that is there", line = "mkdir d; mkdir d 2>/dev/null; echo $?",
		out = { "1" } },
	{ name = "rm", files = { { "/root/f", "x" } }, line = "rm f; echo $?", out = { "0" },
		want = { { path = "/root/f", absent = true } } },
	{ name = "rm of a directory needs -r", setup = { "mkdir d" },
		line = "rm d 2>/dev/null; echo $?", out = { "1" }, want = { { path = "/root/d" } } },
	{ name = "rm -r", setup = { "mkdir d; touch d/a" }, line = "rm -r d",
		want = { { path = "/root/d", absent = true } } },
	{ name = "rm has no -f", line = "rm -f nosuch 2>/dev/null; echo $?", out = { "1" },
		dev = "rm" },
	{ name = "mv renames", files = { { "/root/a", "x" } }, line = "mv a b",
		want = { { path = "/root/a", absent = true }, { path = "/root/b", text = "x" } } },
	{ name = "mv into a directory", files = { { "/root/a", "x" } }, setup = { "mkdir d" },
		line = "mv a d", want = { { path = "/root/d/a", text = "x" } } },
	{ name = "cp", files = { { "/root/a", "x" } }, line = "cp a b",
		want = { { path = "/root/a", text = "x" }, { path = "/root/b", text = "x" } } },
	-- An existing file is opened and truncated, not replaced: its mode stays.
	{ name = "cp over a file keeps its mode",
		files = { { "/root/s", "new", 644 }, { "/root/d", "old", 600 } }, line = "cp s d",
		want = { { path = "/root/d", text = "new", mode = 600 } } },
	{ name = "cp into a directory", files = { { "/root/a", "x" } }, setup = { "mkdir d" },
		line = "cp a d", want = { { path = "/root/d/a", text = "x" } } },
	{ name = "cp -r", setup = { "mkdir d; echo x > d/a" }, line = "cp -r d e",
		want = { { path = "/root/e/a", text = "x\n" } } },
	{ name = "cp of nothing", line = "cp nosuch b 2>/dev/null; echo $?", out = { "1" },
		want = { { path = "/root/b", absent = true } } },
	{ name = "touch", line = "touch f; [ -f f ] && echo y", out = { "y" },
		want = { { path = "/root/f", text = "" } } },
	{ name = "touch keeps what is in it", files = { { "/root/f", "x" } }, line = "touch f",
		want = { { path = "/root/f", text = "x" } } },
	{ name = "ln -s", files = { { "/root/a", "x" } }, line = "ln -s a l; cat l",
		out = { "x" } },
	{ name = "ln without -s", files = { { "/root/a", "x" } },
		line = "ln a l 2>/dev/null; echo $?", out = { "1" }, dev = "ln" },

	-- chmod, chown, chgrp
	{ name = "chmod", files = { { "/root/f", "x" } }, line = "chmod 600 f",
		want = { { path = "/root/f", mode = 600 } } },
	{ name = "chmod makes it runnable", files = { { "/root/s", "echo ran", 644 } },
		line = "chmod 755 s; ./s", out = { "ran" } },
	{ name = "chmod of a bad mode", files = { { "/root/f", "x" } },
		line = "chmod 999 f 2>/dev/null; echo $?", out = { "1" } },
	{ name = "chown", files = { { "/root/f", "x" } }, line = "chown admin f",
		want = { { path = "/root/f", owner = "admin" } } },
	{ name = "chgrp", files = { { "/root/f", "x" } }, line = "chgrp wheel f",
		want = { { path = "/root/f", group = "wheel" } } },

	-- find, tar
	{ name = "find", setup = { "mkdir d; touch d/a" }, line = "find d", out = { "d", "d/a" } },
	{ name = "find -name", setup = { "mkdir d; touch d/a; touch d/b" },
		line = "find d -name a", out = { "d/a" } },
	{ name = "find -type d", setup = { "mkdir d; touch d/a" }, line = "find d -type d",
		out = { "d" } },
	{ name = "tar there and back", setup = { "mkdir d; echo x > d/a" },
		line = "tar cf t d; rm -r d; tar xf t; cat d/a", out = { "x" } },

	-- The machine and the account.
	{ name = "date +FORMAT", line = "date +%Y-%m-%d", out = { "1993-06-13" } },
	{ name = "date +%H:%M", line = "date +%H:%M", out = { "19:33" } },
	{ name = "hostname", line = "hostname", out = { "selftest" } },
	{ name = "hostname sets it", line = "hostname kx; hostname", out = { "kx" } },
	{ name = "whoami", line = "whoami", out = { "root" } },
	{ name = "id", line = "id", out = { "uid=root flag=admin groups=root" }, dev = "id" },
	{ name = "groups", line = "groups", out = { "root" } },
	{ name = "which", line = "which ls", out = { "/bin/ls" } },
	{ name = "type of a builtin", line = "type cd", out = { "cd is a shell builtin" } },
	{ name = "type of a file", line = "type ls", out = { "ls is /bin/ls" } },
	{ name = "env", line = "env", out = { "HOME=/root", "PATH=/bin:/usr/local/bin" } },
	{ name = "mkpasswd", line = "mkpasswd secret abcdef",
		out = { "$cs1$abcdef$74a662fe0a5af94dd93513930da000aa" }, dev = "mkpasswd" },
	{ name = "help", line = "help | head -1", out = { "CeroSec OS commands:" }, dev = "help" },
	{ name = "man", line = "man ls > /dev/null; echo $?", out = { "0" } },
	{ name = "man of nothing", line = "man nosuch 2>/dev/null; echo $?", out = { "1" } },

	-- Accounts and groups, as root.
	{ name = "groupadd", line = "groupadd g1; grep '^g1:' /etc/group", out = { "g1:" } },
	{ name = "groupdel", line = "groupadd g1; groupdel g1; grep -c '^g1:' /etc/group",
		out = { "0" }, status = 1 },
	{ name = "useradd", line = "useradd u1 > /dev/null; grep -c '^u1:' /etc/passwd; [ -d /home/u1 ] && echo home",
		out = { "1", "home" } },
	{ name = "useradd -G", line = "groupadd g1; useradd -G g1 u1 > /dev/null; groups u1",
		out = { "u1 g1" } },
	{ name = "usermod -G", line = "groupadd g1; useradd u1 > /dev/null; usermod -G g1 u1; groups u1",
		out = { "u1 g1" } },
	{ name = "userdel", line = "useradd u1 > /dev/null; userdel u1 > /dev/null; grep -c '^u1:' /etc/passwd",
		out = { "0" }, status = 1 },

	-- The queues, all empty on a machine nobody has used.
	{ name = "mail with none", line = "mail", out = { "No mail for root" } },
	{ name = "crontab -l with none", line = "crontab -l; echo $?",
		out = { "no crontab for root", "1" } },
	{ name = "crontab -r with none", line = "crontab -r 2>/dev/null; echo $?", out = { "1" } },
	{ name = "atq", line = "atq; echo $?", out = { "0" } },
	{ name = "at -l", line = "at -l; echo $?", out = { "0" } },
	{ name = "atrm of nothing", line = "atrm 5 2>/dev/null; echo $?", out = { "1" } },
	{ name = "jobs", line = "jobs; echo $?", out = { "0" } },
	{ name = "wait", line = "wait; echo $?", out = { "0" } },
	{ name = "kill of nothing", line = "kill 99 2>/dev/null; echo $?", out = { "1" } },
	{ name = "last", line = "last; echo $?", out = { "0" } },
	{ name = "who", line = "who; echo $?", out = { "0" } },
	{ name = "df", line = "df > /dev/null; echo $?", out = { "0" } },
	{ name = "clear gives the screen an order", line = "clear; echo $?", out = { "0" } },
}

-- WHAT IS NOT HERE, and why. Every command in /bin and every word of the shell is
-- above except these, and each of them needs something a scratch machine with no
-- world under it does not have -- which is the point of it having none. They are
-- os_test.lua's, headless, and PARCOURS-TEST.md's, on the glass. The same list is
-- in docs/TESTING.md.
--
--   passwd su sudo           put a password question on the glass; nobody here
--                            can answer one without the password being written in
--                            a shipped file
--   edit, crontab -e         open the screen editor, which wants a terminal
--   at HH:MM                 reads the commands to run from the terminal until ^D
--   fg, history, exit        the console's own: a job to bring back, the lines
--                            typed at it, the session to log out of (`exit` in a
--                            SCRIPT is above)
--   ps, uptime, w            read the machine's job book, its power-on time and
--                            its consoles; the scratch machine has none of them
--   wall                     writes on every console of the machine
--   halt reboot shutdown     stop the machine
--   mount umount newfs       need a drive with a floppy in it
--   dev                      the premises' devices, which are in the world
--   arp ifconfig ping rlogin rsh rcp ruptime rwho cu
--                            the coax, the telephone line and the radio: another
--                            machine, or a modem, in the world

--
-- 2. Running them
--

-- A copy of a plain table, all the way down. The state is what KahluaTable.save
-- keeps -- strings, numbers, booleans and tables of them, no cycles -- so a
-- plain walk copies all of it.
function CeroSecSelfTest.shellCopy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, at in pairs(value) do out[key] = CeroSecSelfTest.shellCopy(at) end
	return out
end

-- The shell a case types into: its variables, its environment, its functions and
-- its $? and $!, the four things a console keeps between two lines
-- (SCeroSecJobs's prompt reads the same five off the console).
function CeroSecSelfTest.shellNew(state, session)
	local account = CeroSecOS.getUser(state, session.user)
	return {
		vars = CeroSecOS.loginVars(account ~= nil and account.home or nil),
		exported = CeroSecOS.loginExported(),
		funcs = {},
		status = 0,
		lastBg = nil,
		nextBg = 1,
	}
end

-- One LINE, typed, and run to its end the way the scheduler runs it: a prompt
-- job, stepped pass by pass with the clock moving, its lines taken off it every
-- pass. Two things the scheduler does are done here in its place, and only the
-- bookkeeping of them: an `&` is handed a job number for $! (the job itself is
-- not run -- there is no book to run it in), and an order for the machine (a
-- `clear`, a `wall`) is taken off the job and dropped, because a job with an
-- order on it does not step again.
--
-- Answers the lines, the status and true -- or nil and why, for a line that
-- would not start or would not finish.
function CeroSecSelfTest.shellLine(state, session, sh, line, input)
	local job, refusal = CeroSecOS.promptJob(state, session, line, sh.vars,
		sh.status, nil, sh.exported, sh.funcs, sh.lastBg)
	if job == nil then
		-- What the console prints for a line that does not parse, and $? after it.
		sh.status = 2
		return { tostring(refusal) }, 2, true
	end
	local env = { now = CeroSecSelfTest.SHELL_NOW, nowMs = 1000, jobs = {} }
	local out = {}
	local answer = 1
	local passes = 0
	while not CeroSecOS.jobIsOver(job) do
		passes = passes + 1
		if passes > CeroSecSelfTest.SHELL_PASSES then
			return nil, "did not finish in " .. CeroSecSelfTest.SHELL_PASSES .. " passes"
		end
		env.nowMs = env.nowMs + CeroSecSelfTest.SHELL_STEP_MS
		CeroSecOS.jobStep(state, job, env, CeroSecSelfTest.SHELL_BUDGET)
		for i = 1, #job.out do out[#out + 1] = job.out[i] end
		job.out = {}
		job.orders = nil
		if job.spawn ~= nil then
			job.spawn = nil
			job.spawnLine = nil
			job.lastBg = sh.nextBg
			sh.nextBg = sh.nextBg + 1
		end
		if job.state == "waiting" then
			if job.ask == nil or input == nil or input[answer] == nil then
				return nil, "stopped waiting for something nobody gives it"
			end
			CeroSecOS.jobInput(state, job, input[answer], env)
			answer = answer + 1
		end
	end
	for i = 1, #job.out do out[#out + 1] = job.out[i] end
	job.out = {}
	session.user = job.session.user
	session.cwd = job.session.cwd
	sh.status = job.status
	sh.lastBg = job.lastBg
	return out, job.status, true
end

-- A case's lines, joined for a log line: one string, the breaks shown.
function CeroSecSelfTest.shellShow(lines)
	if type(lines) ~= "table" then return tostring(lines) end
	local parts = {}
	for i = 1, #lines do parts[i] = tostring(lines[i]) end
	return "[" .. table.concat(parts, "|") .. "]"
end

-- One case, on a copy of the pristine machine. Answers nil when it passed, or
-- the one line saying what it got instead.
function CeroSecSelfTest.shellCase(pristine, case)
	local state = CeroSecSelfTest.shellCopy(pristine.state)
	local session = { user = pristine.session.user, cwd = pristine.session.cwd }
	local root = CeroSecOS.rootSession()
	local sh = CeroSecSelfTest.shellNew(state, session)

	local files = case.files or {}
	for i = 1, #files do
		local file = files[i]
		local done, why = CeroSecOS.writeFile(state, root, file[1], file[2], false,
			CeroSecSelfTest.SHELL_NOW)
		if done == nil then return "cannot write " .. tostring(file[1]) .. ": " .. tostring(why) end
		if file[3] ~= nil then CeroSecOS.getNode(state, root, file[1]).mode = file[3] end
	end
	local setup = case.setup or {}
	for i = 1, #setup do
		local lines, why = CeroSecSelfTest.shellLine(state, session, sh, setup[i])
		if lines == nil then return "setup `" .. setup[i] .. "` " .. why end
	end

	local out, status = CeroSecSelfTest.shellLine(state, session, sh, case.line, case.input)
	if out == nil then return status end
	local wanted = case.out or {}
	if CeroSecSelfTest.shellShow(out) ~= CeroSecSelfTest.shellShow(wanted) then
		return "want " .. CeroSecSelfTest.shellShow(wanted) .. " got " ..
			CeroSecSelfTest.shellShow(out)
	end
	if status ~= (case.status or 0) then
		return "want $? " .. tostring(case.status or 0) .. " got " .. tostring(status)
	end
	local want = case.want or {}
	for i = 1, #want do
		local w = want[i]
		local node = CeroSecOS.getNode(state, root, w.path, true)
		if w.absent then
			if node ~= nil then return w.path .. ": want absent, it is there" end
		elseif node == nil then
			return w.path .. ": want it there, it is not"
		else
			if w.text ~= nil and node.data ~= w.text then
				return w.path .. ": want text [" .. w.text .. "] got [" ..
					tostring(node.data) .. "]"
			end
			if w.mode ~= nil and node.mode ~= w.mode then
				return w.path .. ": want mode " .. w.mode .. " got " .. tostring(node.mode)
			end
			if w.group ~= nil and node.group ~= w.group then
				return w.path .. ": want group " .. w.group .. " got " .. tostring(node.group)
			end
			if w.owner ~= nil and node.owner ~= w.owner then
				return w.path .. ": want owner " .. w.owner .. " got " .. tostring(node.owner)
			end
		end
	end
	return nil
end

-- A run, not yet started. Stepped by shellStep, a few cases at a time, so the
-- game can spread it over ticks (SCeroSecSystem does, on Events.OnTick).
--
--   { pass, fail, lines, done }
--
-- The same three ways to fail as CeroSecSelfTest.run(), for the same reason --
-- two of them are how a bench goes quietly green:
--
--   * a case whose answer differs -- the one everybody expects;
--   * a case that was never evaluated: malformed (no name, no line, a name
--     twice), stopped before its end, or an error out of the middle of it;
--   * an empty or missing table, which is a run of nothing and not a pass.
--
-- And at the end the cases evaluated are counted against the cases held.
function CeroSecSelfTest.shellStart(cases)
	return { cases = cases or CeroSecSelfTest.SHELL_CASES, at = 0, evaluated = 0,
		pass = 0, fail = 0, lines = {}, seen = {}, done = false }
end

local function failed(run, text)
	run.fail = run.fail + 1
	run.lines[#run.lines + 1] = "shell selftest: " .. text
end

-- The machine every case is a copy of. Its own step, because newState and the
-- login hash passwords and are the one slow thing here.
function CeroSecSelfTest.shellPrepare(run)
	local state = CeroSecOS.newState("selftest")
	local session = CeroSecOS.login(state, "root", "")
	if session == nil then
		failed(run, "the scratch machine does not let root in")
		run.done = true
		return
	end
	run.pristine = { state = state, session = session }
end

-- Up to `count` cases more. Answers true once the run is over.
function CeroSecSelfTest.shellStep(run, count)
	if run.done then return true end
	local cases = run.cases
	if type(cases) ~= "table" or #cases == 0 then
		failed(run, "CeroSecSelfTestShell.lua holds no cases")
		run.done = true
		return true
	end
	if run.pristine == nil then
		CeroSecSelfTest.shellPrepare(run)
		return run.done
	end
	local n = 0
	while n < count and run.at < #cases do
		n = n + 1
		-- Moved on BEFORE the case runs, so a case that raises is behind the run
		-- and not in front of it every tick for ever.
		run.at = run.at + 1
		local case = cases[run.at]
		local name = type(case) == "table" and case.name or nil
		if type(name) ~= "string" then
			failed(run, "case " .. run.at .. " has no name")
		elseif run.seen[name] then
			failed(run, name .. ": the name is used twice")
		elseif type(case.line) ~= "string" then
			run.seen[name] = true
			failed(run, name .. ": no line to type")
		else
			run.seen[name] = true
			local ok, why = pcall(CeroSecSelfTest.shellCase, run.pristine, case)
			if not ok then
				failed(run, name .. ": `" .. case.line .. "` raised " .. tostring(why))
			elseif why ~= nil then
				failed(run, name .. ": `" .. case.line .. "` " .. why)
			else
				run.evaluated = run.evaluated + 1
				run.pass = run.pass + 1
			end
		end
	end
	if run.at >= #cases then run.done = true end
	return run.done
end

-- The whole run at once, for a bench and for the offline Kahlua probe: the game
-- itself spreads it over ticks instead.
function CeroSecSelfTest.runShell(cases)
	local run = CeroSecSelfTest.shellStart(cases)
	local guard = 0
	while not CeroSecSelfTest.shellStep(run, 1000000) and guard < 10 do
		guard = guard + 1
	end
	return { pass = run.pass, fail = run.fail, lines = run.lines }
end

function CeroSecSelfTest.shellSummary(result)
	if type(result) ~= "table" then return "shell selftest: nothing ran" end
	return "shell selftest: PASS " .. tostring(result.pass) ..
		" FAIL " .. tostring(result.fail)
end
