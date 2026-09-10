-- Unit tests for CeroSecDefs.lua. Run from the repo root:
--   lua5.1 tests/defs_test.lua

-- Left over from before the repo root became the mod folder (commit 149ec89):
-- the path is relative to the repo root now.
local DEFS = "42/media/lua/shared/CeroSec/CeroSecDefs.lua"

local chunk, err = loadfile(DEFS)
if not chunk then error("cannot load " .. DEFS .. ": " .. tostring(err)) end
chunk()

local count = 0
local function check(what, cond)
	count = count + 1
	if not cond then error("FAIL: " .. what, 2) end
end
local function eq(what, got, want)
	count = count + 1
	if got ~= want then
		error("FAIL: " .. what .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
	end
end

-- Both sprite tables cover all four facings, and nothing else.
local facings = { S = true, E = true, N = true, W = true }
eq("FACINGS has 4 entries", #CeroSec.FACINGS, 4)
for _, table_ in ipairs({ CeroSec.SPRITES_OFF, CeroSec.SPRITES_ON }) do
	local n = 0
	for facing, sprite in pairs(table_) do
		check("facing " .. facing .. " is one of S/E/N/W", facings[facing])
		check("sprite for " .. facing .. " is a string", type(sprite) == "string")
		n = n + 1
	end
	eq("sprite table covers 4 facings", n, 4)
end

-- Exact tile names, per media/newtiledefinitions.tiles.txt (tileset appliances_com_01).
eq("OFF S", CeroSec.SPRITES_OFF.S, "appliances_com_01_72")
eq("OFF E", CeroSec.SPRITES_OFF.E, "appliances_com_01_73")
eq("OFF N", CeroSec.SPRITES_OFF.N, "appliances_com_01_74")
eq("OFF W", CeroSec.SPRITES_OFF.W, "appliances_com_01_75")
eq("ON S", CeroSec.SPRITES_ON.S, "appliances_com_01_76")
eq("ON E", CeroSec.SPRITES_ON.E, "appliances_com_01_77")
eq("ON N", CeroSec.SPRITES_ON.N, "appliances_com_01_78")
eq("ON W", CeroSec.SPRITES_ON.W, "appliances_com_01_79")

-- Mapping both ways, for every facing.
for _, facing in ipairs(CeroSec.FACINGS) do
	local off = CeroSec.SPRITES_OFF[facing]
	local on = CeroSec.SPRITES_ON[facing]

	check("isComputerSprite(off " .. facing .. ")", CeroSec.isComputerSprite(off))
	check("isComputerSprite(on " .. facing .. ")", CeroSec.isComputerSprite(on))

	check("isOnSprite(on " .. facing .. ")", CeroSec.isOnSprite(on))
	check("not isOnSprite(off " .. facing .. ")", not CeroSec.isOnSprite(off))
	check("isOffSprite(off " .. facing .. ")", CeroSec.isOffSprite(off))
	check("not isOffSprite(on " .. facing .. ")", not CeroSec.isOffSprite(on))

	eq("onSpriteFor(off " .. facing .. ")", CeroSec.onSpriteFor(off), on)
	eq("offSpriteFor(on " .. facing .. ")", CeroSec.offSpriteFor(on), off)
	-- Round trip.
	eq("off -> on -> off " .. facing, CeroSec.offSpriteFor(CeroSec.onSpriteFor(off)), off)
	eq("on -> off -> on " .. facing, CeroSec.onSpriteFor(CeroSec.offSpriteFor(on)), on)

	eq("facingOf(off " .. facing .. ")", CeroSec.facingOf(off), facing)
	eq("facingOf(on " .. facing .. ")", CeroSec.facingOf(on), facing)

	eq("spriteFor(" .. facing .. ", false)", CeroSec.spriteFor(facing, false), off)
	eq("spriteFor(" .. facing .. ", true)", CeroSec.spriteFor(facing, true), on)
end

-- Wrong way round: an ON sprite has no ON sprite, an OFF sprite has no OFF sprite.
eq("onSpriteFor(on) is nil", CeroSec.onSpriteFor("appliances_com_01_76"), nil)
eq("offSpriteFor(off) is nil", CeroSec.offSpriteFor("appliances_com_01_72"), nil)

-- Non-computer sprites are rejected. appliances_com_01_71 and _80 are the
-- immediate neighbours of our block in the same tileset: they must not match.
local strangers = {
	"appliances_com_01_71", "appliances_com_01_80", "appliances_com_01_7",
	"appliances_com_01_720", "appliances_com_02_72", "camping_01_6",
	"", "appliances_com_01_", "APPLIANCES_COM_01_72", nil,
}
for i = 1, 10 do
	local name = strangers[i]
	check("isComputerSprite rejects " .. tostring(name), not CeroSec.isComputerSprite(name))
	check("isOnSprite rejects " .. tostring(name), not CeroSec.isOnSprite(name))
	eq("facingOf is nil for " .. tostring(name), CeroSec.facingOf(name), nil)
	eq("onSpriteFor is nil for " .. tostring(name), CeroSec.onSpriteFor(name), nil)
	eq("offSpriteFor is nil for " .. tostring(name), CeroSec.offSpriteFor(name), nil)
end

-- Front square offsets. The facing of a tile is the direction it looks at, and
-- the names are IsoDirections constants: N (0,-1), S (0,1), E (1,0), W (-1,0).
local wantedOffset = {
	S = { 0, 1 },
	E = { 1, 0 },
	N = { 0, -1 },
	W = { -1, 0 },
}
for facing, wanted in pairs(wantedOffset) do
	local dx, dy = CeroSec.frontOffset(facing)
	eq("frontOffset(" .. facing .. ") dx", dx, wanted[1])
	eq("frontOffset(" .. facing .. ") dy", dy, wanted[2])
	-- Same answer whether the computer is lit or dark: the ON sprites carry no
	-- Facing property, so their facing comes through the OFF/ON mapping.
	for _, sprite in ipairs({ CeroSec.SPRITES_OFF[facing], CeroSec.SPRITES_ON[facing] }) do
		local sx, sy = CeroSec.frontOffset(CeroSec.facingOf(sprite))
		eq("frontOffset via " .. sprite .. " dx", sx, wanted[1])
		eq("frontOffset via " .. sprite .. " dy", sy, wanted[2])
	end
end

-- Exactly four offsets, each one square away and never diagonal.
local offsetCount = 0
for facing, offset in pairs(CeroSec.FRONT_OFFSET) do
	check("offset facing " .. facing .. " is one of S/E/N/W", facings[facing])
	eq("offset " .. facing .. " is one square away",
		math.abs(offset[1]) + math.abs(offset[2]), 1)
	offsetCount = offsetCount + 1
end
eq("FRONT_OFFSET covers 4 facings", offsetCount, 4)

-- Opposite facings must point opposite ways.
for _, pair in ipairs({ { "N", "S" }, { "E", "W" } }) do
	local ax, ay = CeroSec.frontOffset(pair[1])
	local bx, by = CeroSec.frontOffset(pair[2])
	eq("offsets " .. pair[1] .. "/" .. pair[2] .. " cancel on x", ax + bx, 0)
	eq("offsets " .. pair[1] .. "/" .. pair[2] .. " cancel on y", ay + by, 0)
end

-- Nothing else has a front square.
for i = 1, 10 do
	local dx, dy = CeroSec.frontOffset(CeroSec.facingOf(strangers[i]))
	eq("frontOffset dx is nil for " .. tostring(strangers[i]), dx, nil)
	eq("frontOffset dy is nil for " .. tostring(strangers[i]), dy, nil)
end
local dx, dy = CeroSec.frontOffset("NE")
eq("frontOffset(NE) dx is nil", dx, nil)
eq("frontOffset(NE) dy is nil", dy, nil)

-- facingForOffset is the inverse of frontOffset, and answers nil for anything
-- that is not one of the four steps.
for facing in pairs(wantedOffset) do
	local ox, oy = CeroSec.frontOffset(facing)
	eq("facingForOffset undoes frontOffset(" .. facing .. ")", CeroSec.facingForOffset(ox, oy), facing)
end
eq("facingForOffset of a standing step is nil", CeroSec.facingForOffset(0, 0), nil)
eq("facingForOffset of a diagonal is nil", CeroSec.facingForOffset(1, 1), nil)
eq("facingForOffset of a two square step is nil", CeroSec.facingForOffset(0, 2), nil)
eq("facingForOffset of nothing is nil", CeroSec.facingForOffset(nil, nil), nil)

-- A chair on the front square looks back at the screen, so its facing is the
-- computer's turned around: the two steps cancel.
local wantedChair = { S = "N", N = "S", E = "W", W = "E" }
for facing, wanted in pairs(wantedChair) do
	eq("chairFacingFor(" .. facing .. ")", CeroSec.chairFacingFor(facing), wanted)
	-- Said again as geometry rather than as a table: the chair's own front
	-- square is the computer's square.
	local cx, cy = CeroSec.frontOffset(facing)
	local kx, ky = CeroSec.frontOffset(CeroSec.chairFacingFor(facing))
	eq("chair looks back on x", cx + kx, 0)
	eq("chair looks back on y", cy + ky, 0)
	-- And it is never the computer's own facing: a chair with its back to the
	-- screen is a chair for another desk.
	check("chair facing differs from the computer's", CeroSec.chairFacingFor(facing) ~= facing)
end
eq("chairFacingFor of a diagonal is nil", CeroSec.chairFacingFor("NE"), nil)
eq("chairFacingFor of nothing is nil", CeroSec.chairFacingFor(nil), nil)

-- State schema v1.
local state = CeroSec.newState("E")
eq("state version", state.v, 1)
eq("state starts off", state.on, false)
eq("state facing", state.facing, "E")
eq("default facing", CeroSec.newState().facing, "S")
eq("movableData key", CeroSec.MOVABLE_DATA_KEY, "cerosec")
-- Two states must not share a table.
check("newState returns a fresh table", CeroSec.newState() ~= CeroSec.newState())

-- The log helper is silent unless DEBUG is on.
check("DEBUG off by default", CeroSec.DEBUG == false)
CeroSec.log("this must not print")

-- Screen geometry: the box test copies the picker's own comparison, left and
-- top edges exclusive, right and bottom inclusive.
check("point inside the box", CeroSec.pointInBox(50, 50, 0, 0, 128, 256))
check("point on the left edge is out", not CeroSec.pointInBox(0, 50, 0, 0, 128, 256))
check("point on the top edge is out", not CeroSec.pointInBox(50, 0, 0, 0, 128, 256))
check("point on the right edge is in", CeroSec.pointInBox(128, 50, 0, 0, 128, 256))
check("point on the bottom edge is in", CeroSec.pointInBox(50, 256, 0, 0, 128, 256))
check("point past the right edge is out", not CeroSec.pointInBox(129, 50, 0, 0, 128, 256))
check("point past the bottom edge is out", not CeroSec.pointInBox(50, 257, 0, 0, 128, 256))
check("point left of the box is out", not CeroSec.pointInBox(-1, 50, 0, 0, 128, 256))
check("point above the box is out", not CeroSec.pointInBox(50, -1, 0, 0, 128, 256))
-- A box that does not sit at the origin, the camera having moved.
check("offset box holds its own point", CeroSec.pointInBox(-70, -110, -100, -150, 128, 256))
check("offset box rejects a point behind it", not CeroSec.pointInBox(-200, -110, -100, -150, 128, 256))

-- Draw order: bigger x+y is nearer the viewer, so it comes first.
check("nearer square first", CeroSec.drawnBefore(11, 10, 0, 10, 10, 0))
check("farther square not first", not CeroSec.drawnBefore(10, 10, 0, 11, 10, 0))
check("the diagonal counts, not each axis", CeroSec.drawnBefore(9, 12, 0, 10, 10, 0))
check("equal diagonals fall through to the index", CeroSec.drawnBefore(9, 11, 5, 10, 10, 4))
check("same diagonal, lower index is behind", not CeroSec.drawnBefore(9, 11, 4, 10, 10, 5))
check("same square and index orders neither way", not CeroSec.drawnBefore(10, 10, 3, 10, 10, 3))
check("a missing index reads as zero", CeroSec.drawnBefore(10, 10, 1, 10, 10, nil))
check("two missing indexes order neither way", not CeroSec.drawnBefore(10, 10, nil, 10, 10, nil))

print("defs_test: " .. count .. " assertions passed")
