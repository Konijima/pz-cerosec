#!/bin/sh
#
# Every self:method() we call has to exist. Run from the repo root:
#   sh tests/selfcalls-check.sh
#
# Lua resolves a method when it is called, so a method that was never written --
# or one that an edit quietly took out with the block around it -- is not a
# syntax error and luac5.1 -p says nothing about it. It is a nil call in
# prerender, once a frame, in the game, and the window is dead. That has
# happened once; this is the check that would have caught it.
#
# The rule: every "self:name(" in our own Lua is either defined in the same file
# as "function Class:name(" or is one of the inherited methods listed below,
# each of which was looked up in the shipped vanilla Lua and is named with the
# class it comes from. A name that is neither is a call that will be nil.
#
# Inherited on purpose. Adding to this list means having found the method in
# the game's own Lua first -- that is the point of it being a list and not a
# wildcard.
INHERITED="
getIsoObject          SGlobalObject
getSquare             SGlobalObject
updateOnClient        SGlobalObject
getLuaObjectAt        SGlobalObjectSystem
getLuaObjectByIndex   CGlobalObjectSystem
getLuaObjectCount     SGlobalObjectSystem
getLuaObjectOnSquare  SGlobalObjectSystem
getIsoObjectAt        SGlobalObjectSystem
loadIsoObject         SGlobalObjectSystem
newLuaObjectOnSquare  SGlobalObjectSystem
sendCommand           SGlobalObjectSystem
addChild              ISUIElement
drawRect              ISUIElement
drawText              ISUIElement
removeFromUIManager   ISUIElement
setVisible            ISUIElement
setResizable          ISCollapsableWindow
setTitle              ISCollapsableWindow
setActionAnim         ISBaseTimedAction
setAnimVariable       ISBaseTimedAction
setOverrideHandModels ISBaseTimedAction
"

allowed=$(echo "$INHERITED" | awk 'NF { print $1 }' | sort -u)
status=0
checked=0

echo "== self:method() calls resolve"
for f in $(find 42/media/lua -name '*.lua' | sort); do
	defs=$(grep -oE "^function [A-Za-z_]+[:.][a-zA-Z_]+" "$f" | sed 's/.*[:.]//' | sort -u)
	calls=$(grep -oE "self:[a-zA-Z_]+\(" "$f" | sed 's/self://; s/(//' | sort -u)
	[ -z "$calls" ] && continue
	# No process substitution: this runs under /bin/sh, not bash.
	known=$(printf '%s\n%s\n' "$defs" "$allowed" | sort -u)
	missing=""
	for name in $calls; do
		if ! printf '%s\n' "$known" | grep -qx "$name"; then
			missing="$missing$name
"
		fi
	done
	count=$(echo "$calls" | grep -c .)
	checked=$((checked + count))
	if [ -n "$missing" ]; then
		echo "  FAIL $f"
		printf '%s' "$missing" | sed 's/^/       self:/; s/$/() is defined nowhere and is not an inherited method/'
		status=1
	else
		echo "  ok   $f ($count)"
	fi
done

if [ "$status" -ne 0 ]; then
	echo "selfcalls-check: FAILED"
	exit 1
fi
echo "selfcalls-check: passed ($checked call sites)"
