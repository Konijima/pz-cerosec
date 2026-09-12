#!/bin/sh
#
# Every headless test, from the repo root:
#   sh tests/run.sh
#

set -e

lua5.1 tests/defs_test.lua
lua5.1 tests/os_test.lua
lua5.1 tests/manual_test.lua
lua5.1 tests/terminal_test.lua
lua5.1 tests/window_test.lua
lua5.1 tests/hostile_test.lua
lua5.1 tests/manual_ui_test.lua
lua5.1 tests/debug_ui_test.lua
# Not piped: a pipe would hide its exit status from set -e.
log=$(mktemp)
if sh tests/selfcalls-check.sh > "$log" 2>&1; then
	tail -1 "$log"
	rm -f "$log"
else
	cat "$log"
	rm -f "$log"
	exit 1
fi

log=$(mktemp)
if sh tests/kahlua-check.sh > "$log" 2>&1; then
	tail -1 "$log"
	rm -f "$log"
else
	cat "$log"
	rm -f "$log"
	exit 1
fi

log=$(mktemp)
if sh tests/kahlua-run.sh > "$log" 2>&1; then
	tail -1 "$log"
	rm -f "$log"
else
	cat "$log"
	rm -f "$log"
	exit 1
fi

echo "all tests passed"
