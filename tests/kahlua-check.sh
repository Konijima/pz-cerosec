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

CORE="42/media/lua/shared/CeroSec/OS"
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
forbid() {
	hits=$(grep -rnE "$1" "$CORE")
	if [ -n "$hits" ]; then
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
