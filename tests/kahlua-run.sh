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
#   - The compiler is the JDK on the box (javac), but the game's classes are
#     Java 25 class files and that javac is 21, so KahluaRun reaches Kahlua by
#     reflection and RUNS on the game's bundled jre64.
#   - Kahlua's setupEnvironment() reads stdlib.lua as a path relative to the
#     working directory, so the java process runs in the game folder and gets
#     the repo root as its argument.
#

GAME="$HOME/.local/share/Steam/steamapps/common/ProjectZomboid/projectzomboid"
JAR="$GAME/projectzomboid.jar"
JAVA="$GAME/jre64/bin/java"
JAVAC="$HOME/.sdkman/candidates/java/current/bin/javac"

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

cd "$GAME" || exit 1
"$JAVA" -cp "$JAR:$OUT" KahluaRun "$ROOT"
exit $?
