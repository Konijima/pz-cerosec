#!/bin/sh
#
# Kahlua compatibility check. Run from the repo root:
#   sh tests/kahlua-check.sh
#
# The game runs Lua through Kahlua, a 5.1 subset: it takes 5.1 syntax but has
# neither the 5.2+ constructs nor a full standard library, and the OS core must
# on top of that stay free of anything the game cannot serialize. So: compile
# every Lua file we ship, then grep the core for what it must never contain.
#

# The files that must be Kahlua-pure AND loadable with nothing under them: the OS
# core, and the content catalogue beside it. CeroSecContent.lua is in here for the
# same reason the core is -- it is loaded before the core by the game (shared/
# CeroSec/ ahead of shared/CeroSec/OS/) and by loadfile in the benches, so a
# `require` or a setmetatable in it is a load-time failure nothing else catches.
CORE="42/media/lua/shared/CeroSec/OS 42/media/lua/shared/CeroSec/CeroSecContent.lua"
# And every file that ships, for the rules that are about KAHLUA rather than
# about the core: a construct the VM has not got is a load failure in a
# client file as surely as in the core.
ALL="42/media/lua"
# Which of the two the next forbid reads.
WHERE=$CORE
status=0

echo "== luac5.1 -p on every Lua file"
for f in $(find 42/media/lua tests -name '*.lua' | sort); do
	if luac5.1 -p "$f"; then
		echo "  ok   $f"
	else
		echo "  FAIL $f"
		status=1
	fi
done

# forbid <extended regex> <what it is>
#
# $CORE is a LIST of paths and is deliberately left unquoted, and grep's exit
# status is read rather than only its output: quoted, the whole list was one path
# name, grep said "No such file or directory" on stderr -- and this function
# printed "ok" for it, because an empty result read as "nothing forbidden found".
# That is an assertion going green for having looked at nothing. So a grep that
# ERRORS (status 2) is a failure of the check, not a pass.
forbid() {
	# shellcheck disable=SC2086
	hits=$(grep -rnE "$1" $WHERE 2>&1)
	rc=$?
	if [ "$rc" -gt 1 ]; then
		echo "  FAIL $2: the search itself failed"
		echo "$hits" | sed 's/^/       /'
		status=1
	elif [ -n "$hits" ]; then
		echo "  FAIL $2"
		echo "$hits" | sed 's/^/       /'
		status=1
	else
		echo "  ok   no $2"
	fi
}

# Same, with an escape hatch: the pattern finds the candidates and the second
# pattern is what makes one of them allowed. One grep cannot say "A but not B" on
# the same line without a lookahead, and grep -E has none.
forbid_unless() {
	# shellcheck disable=SC2086
	hits=$(grep -rnE "$1" $WHERE 2>&1)
	rc=$?
	if [ "$rc" -gt 1 ]; then
		echo "  FAIL $3: the search itself failed"
		echo "$hits" | sed 's/^/       /'
		status=1
		return
	fi
	hits=$(printf '%s' "$hits" | grep -vE "$2")
	if [ -n "$hits" ]; then
		echo "  FAIL $3"
		echo "$hits" | sed 's/^/       /'
		status=1
	else
		echo "  ok   no $3"
	fi
}

# A hit on a line that is nothing but a comment is prose, not code: the
# javap listings quoted beside a claim carry "//" and the word "load".
COMMENT='^[^:]+:[0-9]+:[[:space:]]*--'

WHERE=$ALL
echo "== what Kahlua has not got, in $ALL"
forbid '::[A-Za-z_]+::' 'goto label'
forbid '(^|[^A-Za-z_])goto[ 	]' 'goto'
forbid_unless '//' "$COMMENT" 'integer division'
forbid 'string\.(pack|unpack)' 'string.pack/unpack'
forbid 'table\.unpack' 'table.unpack'
forbid '\\z' 'the \z escape'
# The bit library: bit.band, bit32.bor, and a local taken off either.
forbid_unless '(^|[^A-Za-z_.])bit(32)?\.[a-z]' "$COMMENT" 'the bit library'
# %b, the balanced-match class. The one "%b" that is allowed is not a
# pattern at all: it is strftime's month in a format CeroSecOS.formatTime
# reads itself (the self-test's vector of it).
forbid_unless '%b' 'formatTime\(' 'the %b pattern class'
forbid_unless '(^|[^A-Za-z_.])(load|loadstring|dofile|loadfile)[ 	]*\(' "$COMMENT" 'runtime code loading'
forbid '(^|[^A-Za-z_.])(getfenv|setfenv)[ 	]*\(' 'environment juggling'

WHERE=$CORE
echo "== what the core must never contain, in $CORE"
forbid '(^|[^A-Za-z_.])coroutine\.' 'coroutine'
forbid '(^|[^A-Za-z_.])require[ 	]*[("'"'"']' 'require'
forbid '(^|[^A-Za-z_.])io\.' 'the io library'
forbid '(^|[^A-Za-z_.])os\.' 'the os library'
forbid '(^|[^A-Za-z_.])setmetatable[ 	]*\(' 'setmetatable'
forbid '(^|[^A-Za-z_.])newproxy' 'newproxy'
# Kahlua renders a non-integer double the Java way -- tostring(1e15) is "1.0E15"
# there and "1e+15" under lua5.1, tostring(1/3) is "0.3333333333333333" and
# "0.33333333333333" -- and there is no fixing that in the mod, so the engine
# never puts a non-integer through tostring. A division or a multiplication
# inside tostring() is the shape that does it; math.floor around it is the
# answer, and is why every one we have is allowed. (The other half of the same
# rule, the "%" operator, is not greppable: see docs/TESTING.md.)
forbid_unless 'tostring\([^)]*[*/]' 'math\.floor' 'unfloored arithmetic inside tostring()'

# No player string reaches a pattern: a lexer, not a grep (see its head).
echo "== pattern arguments in $ALL"
if ! lua5.1 tests/pattern-check.lua; then
	status=1
fi

if [ "$status" -ne 0 ]; then
	echo "kahlua-check: FAILED"
	exit 1
fi
echo "kahlua-check: passed"
