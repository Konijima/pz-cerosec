#!/bin/sh
#
# Load every Lua file we ship on the real Kahlua. Run from the repo root:
#   sh tests/kahlua-run.sh
#
# tests/kahlua-check.sh greps for constructs Kahlua cannot take; this one
# actually hands the files to Kahlua -- the VM out of the game's own jar -- in
# the game's load order, and runs their top level. A Kahlua parse error and a
# load-time nil call are both invisible to a grep and to luac5.1; the day this
# was written the game said "Object tried to call nil" on an engine function and
# nothing in tests/ could say whether the files even loaded.
#
# Two details of the setup, both forced:
#   - The compiler is whatever JDK is on your PATH (javac; override with
#     JAVAC=...), but the game's classes are Java 25 class files and a javac
#     older than that cannot read them, so KahluaRun reaches Kahlua by
#     reflection and RUNS on the game's bundled jre64.
#   - Kahlua's setupEnvironment() reads stdlib.lua as a path relative to the
#     working directory, so the java process runs in the game folder and gets
#     the repo root as its argument.
#

# The Steam install on Linux. Override GAME if the game lives elsewhere, and
# JAVAC if the javac to use is not the one on your PATH.
GAME="${GAME:-$HOME/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid}"
JAR="$GAME/projectzomboid.jar"
JAVA="$GAME/jre64/bin/java"
JAVAC="${JAVAC:-$(command -v javac 2> /dev/null || echo javac)}"

ROOT=$(pwd)
SRC="$ROOT/tools/KahluaRun.java"
OUT="$ROOT/tools/out"
CLASS="$OUT/KahluaRun.class"

for f in "$JAR" "$JAVA" "$JAVAC" "$SRC"; do
	if [ ! -f "$f" ]; then
		echo "kahlua-run: missing $f"
		exit 1
	fi
done

if [ ! -f "$CLASS" ] || [ "$SRC" -nt "$CLASS" ]; then
	mkdir -p "$OUT"
	if ! "$JAVAC" -d "$OUT" "$SRC"; then
		echo "kahlua-run: KahluaRun.java does not compile"
		exit 1
	fi
fi

# Second half: tests/kahlua-probe.lua, RUN on both VMs, outputs compared.
#
# Loading proves a file parses and that its top level survives; it proves
# nothing about what the standard library ANSWERS. tonumber(s, 16) returned nil
# on Kahlua for half of all hashes (Integer.parseInt behind it) while every file
# loaded and every lua5.1 bench was green, and the game died on the first
# power-on of a prefilled machine. So the probe calls the engine's pure
# functions with fixed inputs and prints a line each, and a single differing
# line fails this script.
PROBE="$ROOT/tests/kahlua-probe.lua"
if [ ! -f "$PROBE" ]; then
	echo "kahlua-run: missing $PROBE"
	exit 1
fi
if ! command -v lua5.1 > /dev/null 2>&1; then
	echo "kahlua-run: no lua5.1 to compare against"
	exit 1
fi

WANT=$(mktemp)
GOT=$(mktemp)
trap 'rm -f "$WANT" "$GOT"' EXIT

if ! lua5.1 "$PROBE" > "$WANT" 2>&1; then
	echo "kahlua-run: the probe does not run on lua5.1"
	cat "$WANT"
	exit 1
fi

cd "$GAME" || exit 1
"$JAVA" -cp "$JAR:$OUT" KahluaRun "$ROOT" || exit 1

if ! "$JAVA" -cp "$JAR:$OUT" KahluaRun --eval "$PROBE" "$ROOT" > "$GOT"; then
	echo "kahlua-run: the probe does not run on Kahlua"
	cat "$GOT"
	exit 1
fi

if ! diff -u "$WANT" "$GOT" > /dev/null; then
	echo "kahlua-run: FAILED -- the probe answers differently on the two VMs"
	echo "  (-- lua5.1, ++ the game's Kahlua)"
	diff -u --label lua5.1 "$WANT" --label kahlua "$GOT"
	exit 1
fi

# Third half: the self-test's SHELL cases (CeroSecSelfTestShell.lua), run on
# Kahlua. Not a diff: every case carries its own answer, and lua5.1 is already
# held to FAIL 0 by tests/selftest_shell_test.lua. What this adds is the same
# table on the VM the game has. The summary is the last line, and nothing but
# FAIL 0 passes -- a run that printed nothing is not a pass either.
SHELL="$ROOT/tests/kahlua-selftest-shell.lua"
if ! "$JAVA" -cp "$JAR:$OUT" KahluaRun --eval "$SHELL" "$ROOT" > "$GOT"; then
	echo "kahlua-run: the shell selftest does not run on Kahlua"
	cat "$GOT"
	exit 1
fi
LAST=$(tail -1 "$GOT")
case "$LAST" in
"shell selftest: PASS "*" FAIL 0") ;;
*)
	echo "kahlua-run: FAILED -- the shell selftest on Kahlua:"
	cat "$GOT"
	exit 1
	;;
esac

echo "kahlua-run: passed, the probe agrees on both VMs ($(wc -l < "$WANT") lines), $LAST on Kahlua"
exit 0
