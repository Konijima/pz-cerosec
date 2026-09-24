#!/bin/sh
#
# This repository is public. Run from the repo root:
#   sh tests/public-check.sh
#
# The mod is written with long comments, and a long comment is where a detail
# about the machine it was written on gets in: an absolute path out of somebody's
# home directory, a hostname, the name of a private notes system, a session URL.
# None of that helps a contributor and it does not belong in a public tree, so it
# is a red here rather than something a reader has to notice.
#
# Every TRACKED text file is read (git ls-files, binaries skipped). Untracked
# files are not this check's business -- what ships is what is committed -- and
# .git itself is never read: the worktree pointer in it holds a real absolute
# path by design. Git HISTORY is not read either: the commit messages carry the
# session trailers of how this mod was written and they stay as they are, which
# docs/CONTRIBUTING.md says out loud.
#
# EVERY LINE BELOW IS ROT13, the allowed filenames included, and this file scans
# itself like any other -- so that the guard is not a plain list of the very
# things it forbids. To read one, or to write a new one:
#
#   echo znguvrh | tr 'A-Za-z' 'N-ZA-Mn-za-m'
#
# Decoded, each line is "<word>|<files allowed to contain it>". What they are and
# why, in order:
#
#   1  the maintainer's own first name
#   2  the hostname of the machine this was written on
#   3-4 two words naming a private notes system
#   5  a session URL of the assistant this was written with -- exempted NOWHERE,
#      so a pasted session link fails even in the files of line 6
#   6  the assistant's name, allowed only in the three files that are ABOUT
#      working on this mod with it
#   7  a scratch working directory
#   8  one particular way of installing a JDK, which the Kahlua harness must not
#      assume
#   9  a private network
#   10 the hosts on it
#
WORDS='znguvrh|
oynpxfgne|
preirnh|
pbsser|
pynhqr.nv/pbqr/frffvba|
pynhqr|PYNHQR.zq qbpf/PBAGEVOHGVAT.zq ERNQZR.zq
fpengpucnq|
fqxzna|
gnvyarg|
biu-|'

rot13() { printf '%s' "$1" | tr 'A-Za-z' 'N-ZA-Mn-za-m'; }

# /home/ is its own rule, because the in-game Unix has home directories of its
# own and they are content, not a leak: the manual, the benches and the world
# content are full of the admin's and bob's. What must never appear is such a
# path on a REAL machine, so the account names the simulated world uses are
# listed here and every other one is a failure. A new in-game account means one
# more name on this line, which is a decision somebody makes on purpose.
GAME_HOMES='admin adminx root bob sam carl kate dave eve other dispatch x alice carol u1'

files=0

# Every hit appends a line here. A file, not a variable: the word loop below runs
# in a subshell (it is the right-hand side of a pipe) and a variable set in there
# would not survive it -- which is exactly how a guard ends up always green.
FLAG=$(mktemp)
trap 'rm -f "$FLAG"' EXIT

echo "== no tracked file says anything about the machine it was written on"
for f in $(git ls-files | sort); do
	[ -f "$f" ] || continue
	# Text only: -I makes grep refuse a binary, so a file no pattern could be
	# searched in is skipped whole.
	grep -qI . "$f" 2> /dev/null || continue
	files=$((files + 1))

	printf '%s\n' "$WORDS" | while IFS= read -r line; do
		[ -z "$line" ] && continue
		plain=$(rot13 "$line")
		word=${plain%%|*}
		allow=${plain#*|}
		for ok in $allow; do
			[ "$f" = "$ok" ] && continue 2
		done
		n=$(grep -ciF -- "$word" "$f" 2> /dev/null || true)
		[ "$n" -eq 0 ] && continue
		echo "  FAIL $f: $n line(s) containing a word this tree must not contain"
		grep -niF -- "$word" "$f" | cut -c 1-100 | sed 's/^/         /'
		echo "!" >> "$FLAG"
	done

	# A home directory of somebody who is not in the simulated world.
	for name in $(grep -oiE '/[Hh][Oo][Mm][Ee]/[A-Za-z0-9_-]*' "$f" 2> /dev/null \
			| sed 's|^/[A-Za-z]*/||' | sort -u); do
		[ -z "$name" ] && continue
		found=0
		for ok in $GAME_HOMES; do
			[ "$name" = "$ok" ] && found=1 && break
		done
		[ "$found" -eq 1 ] && continue
		echo "  FAIL $f: the home directory of \"$name\" is nobody in the in-game"
		echo "         world, so it is a path on a real machine. Write ~ or \$HOME,"
		echo "         or add the account to GAME_HOMES here if it IS in-game."
		echo "!" >> "$FLAG"
	done
done

hits=$(wc -l < "$FLAG" | tr -d ' ')
if [ "$hits" -ne 0 ]; then
	echo "public-check: FAILED ($hits hit(s)) -- this tree is not fit to be public"
	exit 1
fi
echo "public-check: passed ($files text files, nothing about the machine in them)"
exit 0
