require "CeroSec/CeroSecDefs"
require "Util/AdjacentFreeTileFinder"

--
-- Where the player has to stand to use a computer, and how high the computer is.
--
-- Kept apart from the toggle so the terminal of the later rungs asks the same
-- questions and gets the same answers.
--

CeroSecReach = {}

-- Vanilla refuses to place a table-top object on a stack of tables taller than
-- this (ISMoveableSpriteProps.lua:1620-1622: canPlace = not IsTableTop and
-- (currentSurface <= 64)). We take the same line for reaching one: anything the
-- game would not let you put there is out of arm's reach.
CeroSecReach.SURFACE_MAX = 64

-- The square the screen looks at, or nil when the computer has no square, an
-- unknown sprite, or the neighbour is off the loaded map.
function CeroSecReach.frontSquare(computer)
	if not computer then return nil end
	local square = computer:getSquare()
	if not square then return nil end
	local dx, dy = CeroSec.frontOffset(CeroSec.facingOf(computer:getSpriteName()))
	if not dx then return nil end
	return getCell():getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
end

-- Can the player stand in front of this computer and reach it from there?
-- Returns true, or false plus a reason key.
function CeroSecReach.canStandInFront(playerObj, computer)
	local square = computer and computer:getSquare()
	if not square then return false, "noObject" end

	local front = CeroSecReach.frontSquare(computer)
	if not front then return false, "noSquare" end

	-- Standing there already settles it, the way luautils.walkAdj short-circuits
	-- when the player is close enough (luautils.lua:136-142).
	if playerObj and playerObj:getCurrentSquare() == front then return true end

	-- Vanilla's own "is this a valid adjacent tile" test: same level, no wall
	-- between the two squares, and a floor you can stand on
	-- (AdjacentFreeTileFinder.lua:181-213, the filter AdjacentFreeTileFinder.Find
	-- runs on every candidate).
	if not AdjacentFreeTileFinder.privTrySquare(square, front) then return false, "blocked" end

	-- And the reach test Find applies to the square it picks
	-- (AdjacentFreeTileFinder.lua:175). canReachTo rejects a wall, a blocked
	-- window, a blocked door and a stair top between the two squares.
	if not front:canReachTo(square) then return false, "blocked" end

	return true
end

-- The player stands in front of the screen, so he looks the other way round.
local OPPOSITE = { N = "S", S = "N", E = "W", W = "E" }

-- IsoDirections is a Java enum: build the lookup on first use rather than at
-- file load, so nothing here depends on when the engine exposes it.
local isoDirections
local function isoDirection(name)
	if not isoDirections then
		isoDirections = { N = IsoDirections.N, S = IsoDirections.S, E = IsoDirections.E, W = IsoDirections.W }
	end
	return isoDirections[name]
end

-- Is the player looking at the screen? faceThisObject turns him with
-- IsoDirections.fromAngle on the vector to the object (IsoGameCharacter.java
-- DirectionFromVector), which lands on a diagonal whenever he stopped a little
-- off the centre of his square, so the two neighbouring 45 degree steps count as
-- facing too (IsoDirections.RotLeft/RotRight).
function CeroSecReach.isFacing(playerObj, computer)
	if not playerObj or not computer then return false end
	local facing = CeroSec.facingOf(computer:getSpriteName())
	if not facing then return false end
	local wanted = isoDirection(OPPOSITE[facing])
	if not wanted then return false end
	local dir = playerObj:getDir()
	return dir == wanted or dir == wanted:RotLeft() or dir == wanted:RotRight()
end

-- Height of the surface the computer sits on, in the pixel units vanilla uses
-- for stacking. Copied from ISMoveableSpriteProps:getTopTable and
-- :getTotalTableHeight (ISMoveableSpriteProps.lua:1421-1443): the topmost object
-- of the square carrying both IsTable and Surface, its render offset plus its
-- own surface. 0 when nothing on the square is a table, i.e. the floor.
local function surfaceHeight(square)
	local objects = square:getObjects()
	for i = objects:size(), 1, -1 do
		local object = objects:get(i - 1)
		local sprite = object:getSprite()
		local props = sprite and sprite:getProperties()
		if props and props:has("IsTable") and props:has("Surface") and tonumber(props:get("Surface")) then
			return object:getRenderYOffset() + tonumber(props:get("Surface"))
		end
	end
	return 0
end

-- "low" on the floor, "mid" on a table, counter or desk, "high" out of reach.
-- nil when the computer has no square.
function CeroSecReach.height(computer)
	local square = computer and computer:getSquare()
	if not square then return nil end
	local height = surfaceHeight(square)
	if height <= 0 then return "low" end
	if height <= CeroSecReach.SURFACE_MAX then return "mid" end
	return "high"
end

-- Walk to the front square -- that one, not any free neighbour -- and then call
-- onArrived. The callback runs right away because it only queues the follow-up
-- action behind the walk; the action itself checks in its isValid that the
-- player really ended up on the front square, so a path that fails or a walk the
-- player interrupts leaves the computer alone.
function CeroSecReach.walkToFront(playerObj, computer, onArrived)
	local front = CeroSecReach.frontSquare(computer)
	if not front then return false end
	if not CeroSecReach.canStandInFront(playerObj, computer) then return false end

	-- Same three calls luautils.walkAdj makes: drop what the player was doing,
	-- then walk, unless he is already standing where he needs to be
	-- (luautils.lua:120-123 and 145-147).
	ISTimedActionQueue.clear(playerObj)
	if playerObj:getCurrentSquare() ~= front then
		ISTimedActionQueue.add(ISWalkToTimedAction:new(playerObj, front))
	end
	onArrived()
	return true
end
