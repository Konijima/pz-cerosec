--
-- CeroSec shared definitions.
--
-- Pure Lua on purpose: no game API is touched here, so this file loads and can
-- be unit-tested under a plain lua5.1 interpreter (see tests/defs_test.lua).
--

CeroSec = CeroSec or {}

CeroSec.DEBUG = false

function CeroSec.log(message)
	if CeroSec.DEBUG then print("CeroSec: " .. tostring(message)) end
end

-- Vanilla desktop computer tiles, tileset appliances_com_01.
-- OFF tiles carry Facing/IsMoveAble/PickUpWeight; the ON tiles (76-79) do not,
-- which is why facing is kept in our own state and never read back from the
-- lit sprite.
CeroSec.FACINGS = { "S", "E", "N", "W" }

CeroSec.SPRITES_OFF = {
	S = "appliances_com_01_72",
	E = "appliances_com_01_73",
	N = "appliances_com_01_74",
	W = "appliances_com_01_75",
}

CeroSec.SPRITES_ON = {
	S = "appliances_com_01_76",
	E = "appliances_com_01_77",
	N = "appliances_com_01_78",
	W = "appliances_com_01_79",
}

-- Reverse lookups, built once.
local facingByName = {}
local onByOff = {}
local offByOn = {}
for i = 1, #CeroSec.FACINGS do
	local facing = CeroSec.FACINGS[i]
	local off = CeroSec.SPRITES_OFF[facing]
	local on = CeroSec.SPRITES_ON[facing]
	facingByName[off] = facing
	facingByName[on] = facing
	onByOff[off] = on
	offByOn[on] = off
end

-- Key our state lives under inside modData.movableData, so that vanilla
-- pickup/placement carries it in the item (ISMoveableSpriteProps.lua:1300, 2270).
CeroSec.MOVABLE_DATA_KEY = "cerosec"
CeroSec.STATE_VERSION = 1

-- Fresh state. Left open for later rungs (os, hostname).
function CeroSec.newState(facing)
	return { v = CeroSec.STATE_VERSION, on = false, facing = facing or "S" }
end

function CeroSec.isComputerSprite(name)
	return name ~= nil and facingByName[name] ~= nil
end

function CeroSec.isOnSprite(name)
	return name ~= nil and offByOn[name] ~= nil
end

function CeroSec.isOffSprite(name)
	return name ~= nil and onByOff[name] ~= nil
end

function CeroSec.onSpriteFor(offName)
	return onByOff[offName]
end

function CeroSec.offSpriteFor(onName)
	return offByOn[onName]
end

-- Facing of any computer sprite, lit or not. nil for anything else.
function CeroSec.facingOf(name)
	return facingByName[name]
end

-- Sprite a computer with this facing should show in the given state.
function CeroSec.spriteFor(facing, on)
	if on then return CeroSec.SPRITES_ON[facing] end
	return CeroSec.SPRITES_OFF[facing]
end
