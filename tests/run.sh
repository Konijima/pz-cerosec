#!/bin/sh
#
# Every headless test, from the repo root:
#   sh tests/run.sh
#

set -e

lua5.1 tests/defs_test.lua
lua5.1 tests/os_test.lua
lua5.1 tests/commands_test.lua
# The photographed saves under tests/fixtures/, walked up to whatever the code is now:
# the one bench that reads bytes a real build wrote instead of building its own.
lua5.1 tests/migrate_test.lua
lua5.1 tests/content_test.lua
lua5.1 tests/manual_test.lua
lua5.1 tests/terminal_test.lua
lua5.1 tests/window_test.lua
lua5.1 tests/compat_computermod_test.lua
lua5.1 tests/leftclick_test.lua
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

# The self-test's vectors are GENERATED from lua5.1, the canonical VM, and are
# committed because the game has no lua5.1 in it. So they can go stale two ways --
# a say() line added to CeroSecSelfTest.vectors, or an engine answer that has
# legitimately changed -- and either way the table in the tree would be what the
# engine USED to answer. Regenerated here into a temporary file and diffed: the
# fix for a red is `lua5.1 tools/make-selftest-vectors.lua`, never an edit of the
# table. (CeroSecSelfTest.run() catches the same drift from the other side, by
# counting the vectors nothing evaluated -- two guards, because this one is only
# run by a developer and that one is only run in a game.)
VECTORS=42/media/lua/shared/CeroSec/CeroSecSelfTestVectors.lua
fresh=$(mktemp)
if ! lua5.1 tools/make-selftest-vectors.lua "$fresh" > /dev/null; then
	echo "run: the vector generator does not run"
	rm -f "$fresh"
	exit 1
fi
if ! diff -u "$VECTORS" "$fresh" > /dev/null; then
	echo "run: FAILED -- $VECTORS is stale"
	echo "  (-- committed, ++ freshly generated; fix with"
	echo "   lua5.1 tools/make-selftest-vectors.lua)"
	diff -u --label committed "$VECTORS" --label generated "$fresh"
	rm -f "$fresh"
	exit 1
fi
rm -f "$fresh"
echo "selftest vectors: up to date"

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

# The repository is public, so nothing in it says anything about the machine it
# was written on. Not piped, for the same reason as the blocks above.
log=$(mktemp)
if sh tests/public-check.sh > "$log" 2>&1; then
	tail -1 "$log"
	rm -f "$log"
else
	cat "$log"
	rm -f "$log"
	exit 1
fi

# The Workshop item against Steam's own ceilings and the jar's own preview
# rules. Here rather than in tools/ because it is the one failure in this
# project that is completely silent: on 2026-09-13 an update to item
# 3801094056 was accepted by the submit screen and the published page came
# back 0 bytes, no preview, no description, with no error anywhere. The
# description was 9502 bytes against a ceiling of 8000.
#
# Not piped, for the reason the two blocks above say: a pipe would hide its
# exit status from set -e, which is how a guard becomes decoration.
log=$(mktemp)
if python3 tools/check-workshop.py > "$log" 2>&1; then
	tail -1 "$log"
	rm -f "$log"
else
	cat "$log"
	rm -f "$log"
	exit 1
fi

echo "all tests passed"
