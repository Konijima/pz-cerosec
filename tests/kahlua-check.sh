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
	hits=$(grep -rnE "$1" $CORE 2>&1)
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

echo "== forbidden constructs in $CORE"
forbid '::[A-Za-z_]+::' 'goto label'
forbid '(^|[^A-Za-z_])goto[ 	]' 'goto'
forbid '//' 'integer division'
forbid 'string\.(pack|unpack)' 'string.pack/unpack'
forbid 'table\.unpack' 'table.unpack'
forbid '(^|[^A-Za-z_.])coroutine\.' 'coroutine'
forbid '(^|[^A-Za-z_.])require[ 	]*[("'"'"']' 'require'
forbid '(^|[^A-Za-z_.])io\.' 'the io library'
forbid '(^|[^A-Za-z_.])os\.' 'the os library'
forbid '(^|[^A-Za-z_.])setmetatable[ 	]*\(' 'setmetatable'
forbid '(^|[^A-Za-z_.])newproxy' 'newproxy'
forbid '(^|[^A-Za-z_.])(load|loadstring|dofile|loadfile)[ 	]*\(' 'runtime code loading'
forbid '\\z' 'the \z escape'
forbid '(^|[^A-Za-z_.])(getfenv|setfenv)[ 	]*\(' 'environment juggling'

if [ "$status" -ne 0 ]; then
	echo "kahlua-check: FAILED"
	exit 1
fi
echo "kahlua-check: passed"
