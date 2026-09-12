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
# The rule: every call on one of OUR objects resolves. Two receivers are
# checked, because the deletion that prompted this took out methods reached
# both ways:
#
#   self:name(...)          -- defined in the same file, or inherited
#   <ours>:name(...)        -- defined in ANY of our files, or inherited,
#                              where <ours> is one of the locals below that
#                              holds an object of ours
#
# Anything else -- entry:, playerObj:, self.action:, object: -- is a vanilla or
# Java object and is not this check's business; those are verified with javap.
#
# A name that resolves nowhere is a call that will be nil. Lua looks a method up
# when it is called, so that is not a syntax error and luac5.1 -p says nothing.
#
# Locals that hold an object of ours. Deliberately a short, named list: a
# receiver nobody put here is simply not checked, and adding one is a decision.
OURS="window luaObject previous"
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
addToUIManager        ISUIElement
initialise            ISPanel
drawRect              ISUIElement
drawText              ISUIElement
removeFromUIManager   ISUIElement
setVisible            ISUIElement
getMouseX             ISUIElement
getMouseY             ISUIElement
setWantKeyEvents      ISUIElement
setResizable          ISCollapsableWindow
setTitle              ISCollapsableWindow
setActionAnim         ISBaseTimedAction
setAnimVariable       ISBaseTimedAction
setOverrideHandModels ISBaseTimedAction
instantiate           ISScrollingListBox
getWidth              ISUIElement
getHeight             ISUIElement
setWidth              ISUIElement
setHeight             ISUIElement
getYScroll            ISUIElement
isMouseOver           ISUIElement
titleBarHeight        ISCollapsableWindow
resizeWidgetHeight    ISCollapsableWindow
drawSelection         ISScrollingListBox
drawMouseOverHighlight ISScrollingListBox
isMouseOverScrollBar  ISScrollingListBox
"

allowed=$(echo "$INHERITED" | awk 'NF { print $1 }' | sort -u)

# Every method any of our files defines, for the <ours>: receivers -- those
# objects are made in one file and used in another.
ourdefs=$(find 42/media/lua -name '*.lua' -exec grep -hoE "^function [A-Za-z_]+[:.][a-zA-Z_]+" {} + \
	| sed 's/.*[:.]//' | sort -u)
ourknown=$(printf '%s\n%s\n' "$ourdefs" "$allowed" | sort -u)

status=0
checked=0

echo "== method calls on our own objects resolve"
for f in $(find 42/media/lua -name '*.lua' | sort); do
	defs=$(grep -oE "^function [A-Za-z_]+[:.][a-zA-Z_]+" "$f" | sed 's/.*[:.]//' | sort -u)
	calls=$(grep -oE "self:[a-zA-Z_]+\(" "$f" | sed 's/self://; s/(//' | sort -u)
	[ -z "$calls" ] && continue
	# No process substitution: this runs under /bin/sh, not bash.
	known=$(printf '%s\n%s\n' "$defs" "$allowed" | sort -u)
	missing=""
	for name in $calls; do
		if ! printf '%s\n' "$known" | grep -qx "$name"; then
			missing="${missing}self:$name
"
		fi
	done
	# The same, for a call on one of our objects held in a local.
	for recv in $OURS; do
		theirs=$(grep -oE "\b$recv:[a-zA-Z_]+\(" "$f" | sed "s/$recv://; s/(//" | sort -u)
		for name in $theirs; do
			checked=$((checked + 1))
			if ! printf '%s\n' "$ourknown" | grep -qx "$name"; then
				missing="$missing$recv:$name
"
			fi
		done
	done

	count=$(echo "$calls" | grep -c .)
	checked=$((checked + count))
	if [ -n "$missing" ]; then
		echo "  FAIL $f"
		printf '%s' "$missing" | sed 's/^/       /; s/$/() is defined nowhere and is not an inherited method/'
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
