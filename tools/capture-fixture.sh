#!/bin/sh
#
# Photograph the save shape this build writes, into tests/fixtures/.
#
#   sh tools/capture-fixture.sh                 # the current code's shape
#   sh tools/capture-fixture.sh <commit>        # the shape that commit wrote
#
# Run from the repo root. Every release captures one BEFORE its STATE_VERSION is
# bumped, so that the next release's chain has a real older machine to walk -- see
# docs/RELEASE.md. The file is committed; tests/migrate_test.lua reads every one of
# them and holds the chain to the invariants.
#
# With a commit argument it checks that build's engine out into a temporary tree and
# captures from THERE, which is the only honest way to get a fixture of a shape the
# current code cannot write any more. Nothing is checked out over the working tree.
#

set -e

ENGINE_REL="42/media/lua/shared/CeroSec/OS"
FIXTURES="tests/fixtures"

if [ ! -f "$ENGINE_REL/CeroSecOS.lua" ]; then
	echo "run this from the repo root" >&2
	exit 1
fi

mkdir -p "$FIXTURES"

engine="$ENGINE_REL"
tmp=""
if [ -n "$1" ]; then
	tmp=$(mktemp -d)
	git archive "$1" "$ENGINE_REL" | tar -x -C "$tmp"
	engine="$tmp/$ENGINE_REL"
	if [ ! -f "$engine/CeroSecOS.lua" ]; then
		echo "no engine at $1" >&2
		rm -rf "$tmp"
		exit 1
	fi
fi

# Which number that engine calls its shape. Read out of the file rather than passed
# in, so the name of the fixture cannot disagree with what is inside it.
version=$(sed -n 's/^CeroSecOS\.STATE_VERSION = \([0-9]*\)$/\1/p' "$engine/CeroSecOS.lua")
if [ -z "$version" ]; then
	echo "cannot read STATE_VERSION out of $engine/CeroSecOS.lua" >&2
	[ -n "$tmp" ] && rm -rf "$tmp"
	exit 1
fi

out="$FIXTURES/state-v$version.lua"
lua5.1 tools/capture-fixture.lua --engine "$engine" --out "$out"

[ -n "$tmp" ] && rm -rf "$tmp"

echo "now run: sh tests/run.sh"
