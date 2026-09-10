-- Unit tests for CeroSecDefs.lua. Run from the repo root:
--   lua5.1 tests/defs_test.lua

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

print("defs_test: " .. count .. " assertions passed")
