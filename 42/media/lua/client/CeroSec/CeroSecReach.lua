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

--
-- The chair in front
--
-- Vanilla asks the question in two halves, and so do we.
--
-- Sittable at all: the sprite carries IsoFlagType.bed. That flag is what
-- IsoGridSquare.getBed collects, and IsoPlayer.doContextRestOnFurniture offers
-- the "Rest" contextual action on whatever it returns; the one Lua place that
-- reads it does the same (ISWorldObjectContextMenu.lua:2657). "bed" is the
-- flag's name, not its meaning -- every chair the game lets you rest on has it.
--
-- Sittable with an animation: the tile has seating data, which is exactly the
-- test the rest action makes before it plays the sitting animation
-- (ISRestAction:furnitureHasSittingData -> SeatingManager:getTilePositionCount(bed) > 0,
-- ISRestAction.lua:143-145). Without it vanilla falls back to sitting on the
-- ground, which is not what a desk chair is for.
--
-- Which way it looks: SeatingManager:getFacingDirection(object), the same call
-- the bed code uses (ISWorldObjectContextMenu.lua:2650, ISGetOnBedAction.lua:37),
-- returning "N", "S", "E" or "W" -- the id of the tile's seating position
-- (media/seating.txt, `position { id = S, ... }`). It is the direction the
-- seated character ends up looking: facing "N" on the "Front" seat ends in
-- faceDirection(IsoDirections.N) (ISRestAction.lua:156-169).
--

-- The chair standing on the computer's front square and looking at the screen,
-- or nil: no chair there, a chair with its back to the screen (that one belongs
-- to another desk), or a computer with no front square at all.
function CeroSecReach.chairInFront(computer)
	if not computer then return nil end
	local wanted = CeroSec.chairFacingFor(CeroSec.facingOf(computer:getSpriteName()))
	if not wanted then return nil end

	local front = CeroSecReach.frontSquare(computer)
	if not front then return nil end

	local seating = SeatingManager.getInstance()
	local objects = front:getObjects()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local sprite = object:getSprite()
		local props = sprite and sprite:getProperties()
		if props and props:has(IsoFlagType.bed)
			and seating:getTilePositionCount(object) > 0
			and seating:getFacingDirection(object) == wanted then
			return object
		end
	end
	return nil
end

-- Is the player sitting on that very chair? Asked the way vanilla asks it
-- (ISWorldObjectContextMenu.lua:1018: isSittingOnFurniture and the object
-- getSitOnFurnitureObject hands back).
function CeroSecReach.isSeatedOn(playerObj, chair)
	if not playerObj or not chair then return false end
	if not playerObj:isSittingOnFurniture() then return false end
	return playerObj:getSitOnFurnitureObject() == chair
end

-- The square the player counts as occupying for this computer. Normally his
-- own; but a seated character is placed by the seat's own translation inside
-- the tile (SeatingManager:getTilePositionTranslate), so a sit that pushes him
-- over a tile boundary would otherwise read as having left the front square and
-- would shut the terminal under him. Sitting on the chair that stands in front
-- of the computer therefore counts as standing on the chair's square.
function CeroSecReach.standingSquare(playerObj, computer)
	if playerObj and playerObj:isSittingOnFurniture() then
		local chair = CeroSecReach.chairInFront(computer)
		if chair and playerObj:getSitOnFurnitureObject() == chair then
			return chair:getSquare()
		end
	end
	return playerObj and playerObj:getCurrentSquare()
end

--
-- Getting there
--
-- Where a character STANDS decides how he sits. ISRestAction works the seat out
-- of his position and nothing else: waitToStart calls
-- calculateSitOnFurnitureDirection, which asks SeatingManager for the world
-- position of every (N,S,W,E) x (Front,Left,Right) place around the chair and
-- takes the NEAREST to the character's float position (ISRestAction.lua:215-233).
-- A player standing at the edge of the square, or on the wrong side of the
-- chair, is nearest to a side position and sits down sideways -- facing away
-- from the screen he asked to use.
--
-- So the approach is never skipped and never approximate. The target is a
-- point, not a square: the very place vanilla would have him stand to take that
-- chair from the front, or the stand point of the front square when there is no
-- chair. A character already standing in the square is walked to the point
-- inside it exactly like one coming from across the room.
--

-- The point vanilla puts a character at to sit on this chair facing the way the
-- chair faces -- which, for the chair chairInFront hands back, is the screen.
-- The same call the rest action scores its candidates with
-- (SeatingManager:getAdjacentPosition, ISRestAction.lua:221), asked for one
-- candidate instead of twelve: the chair's own direction, from the front. nil
-- when the game says that place is not usable.
function CeroSecReach.seatSpot(playerObj, chair)
	if not playerObj or not chair then return nil end
	local seating = SeatingManager.getInstance()
	local facing = seating:getFacingDirection(chair)
	if not facing then return nil end
	local position = Vector3f.new()
	local valid = seating:getAdjacentPosition(playerObj, chair, facing, "Front",
		"sitonfurniture", "SitOnFurnitureFront", position)
	if not valid then return nil end
	return position:x(), position:y(), position:z()
end

-- The stand point of this computer, in the float coordinates a character stands
-- on: the place on the front square from which a player on his feet has the
-- keyboard under his hands rather than a step of floor in front of him
-- (CeroSec.standPoint, and CeroSec.STAND_INSET is the distance). nil when the
-- computer has no front square. The facing cannot be missing here: frontSquare
-- is itself nil without one.
function CeroSecReach.standPoint(computer)
	local front = CeroSecReach.frontSquare(computer)
	if not front then return nil end
	local x, y = CeroSec.standPoint(front:getX(), front:getY(),
		CeroSec.facingOf(computer:getSpriteName()))
	if x == nil then return nil end
	return x, y, front:getZ()
end

-- Is the player already standing at the keyboard -- that is, within
-- CeroSec.STAND_NEAR of the stand point? False when there is no stand point to
-- be at.
function CeroSecReach.atStandPoint(playerObj, computer)
	if not playerObj then return false end
	local x, y = CeroSecReach.standPoint(computer)
	if x == nil then return false end
	return CeroSec.atPoint(playerObj:getX(), playerObj:getY(), x, y, CeroSec.STAND_NEAR)
end

-- Where the player is to end up: the chair's seat point when he is on his way
-- to sit in it, else the stand point of the front square. Never the corner of it
-- he happened to be standing in, and not the middle either -- the middle is a
-- step away from the desk, which is what a player using a computer standing up
-- was seen to be.
--
-- wantSeat is what tells the two apart. Using the computer takes the chair;
-- switching it on and off does not, and would be refused by its own action for
-- standing anywhere but the front square -- so the seat point is only ever
-- aimed at when it is inside that square, and the stand point answers for
-- everything else. That guard is deliberate: the seat point is the game's, and
-- where the game puts it for a chair against a desk is not something this can
-- prove without the game. A chair that is there is therefore never traded for
-- the stand point: the seat is the pose, and the sit places the character
-- itself.
function CeroSecReach.approachPoint(playerObj, computer, wantSeat)
	local front = CeroSecReach.frontSquare(computer)
	if not front then return nil end

	if wantSeat then
		local chair = CeroSecReach.chairInFront(computer)
		if chair ~= nil and not CeroSecReach.isSeatedOn(playerObj, chair) then
			local x, y, z = CeroSecReach.seatSpot(playerObj, chair)
			if x ~= nil and math.floor(x) == front:getX() and math.floor(y) == front:getY() then
				return x, y, z
			end
		end
	end

	return CeroSecReach.standPoint(computer)
end

-- Walk to that point -- the front square, not any free neighbour -- and then
-- call onArrived. The callback runs right away because it only queues the
-- follow-up action behind the walk; the action itself checks in its isValid
-- that the player really ended up on the front square, so a path that fails or
-- a walk the player interrupts leaves the computer alone.
--
-- The walk is ISPathFindAction:pathToLocationF and not ISWalkToTimedAction: the
-- second one paths to a SQUARE (pathToLocation with three integers,
-- WalkToTimedAction.lua:39) and a character already standing in that square has
-- arrived by definition -- which is how "already next to the computer" ended in
-- an off-centre character sitting down sideways.
function CeroSecReach.walkToFront(playerObj, computer, onArrived, wantSeat)
	local front = CeroSecReach.frontSquare(computer)
	if not front then return false end
	if not CeroSecReach.canStandInFront(playerObj, computer) then return false end

	-- Dropping what the player was doing first, like luautils.walkAdj
	-- (luautils.lua:120-123).
	ISTimedActionQueue.clear(playerObj)

	-- A player already sitting in the chair is where he belongs; walking him to
	-- the seat point would stand him up to sit down again.
	local chair = CeroSecReach.chairInFront(computer)
	if not (chair ~= nil and CeroSecReach.isSeatedOn(playerObj, chair)) then
		local x, y, z = CeroSecReach.approachPoint(playerObj, computer, wantSeat)
		if x ~= nil then
			ISTimedActionQueue.add(ISPathFindAction:pathToLocationF(playerObj, x, y, z))
		end
	end
	onArrived()
	return true
end

--
-- Picking a computer under the mouse
--
-- The game's picker only ever hands the menu ONE object, and it never even
-- considers ours when the click lands high on the monitor. Its candidate
-- squares come from a fixed diagonal walk out of the clicked point
-- (FBORenderObjectPicker.getObjectsAt: for each z it steps through
-- leftSideXy/rightSideXy, {0,0} {0,1} {1,1} {1,2} {2,2} {2,3} {3,3}), which
-- budgets three tiles -- 192 screen pixels at zoom 1 -- for a sprite that
-- overhangs the square it belongs to. A table-top computer is drawn a further
-- renderYOffset * tileScale pixels up (IsoObject.setRenderInfo:
-- sy -= offsetY + renderYOffset * Core.tileScale), so on a crate its top pixels
-- climb out of that budget and its square is never even looked at. Below the
-- cut-off the option appears, above it the square behind wins: exactly what the
-- screenshots show.
--
-- So we redo the picking ourselves, for computers only: gather the computers of
-- the squares near the ones the picker did attribute the click to, rebuild each
-- one's drawn box the way vanilla does, and ask the sprite's own click mask.
--

-- How many squares toward the viewer to look. A raised sprite moves straight up
-- the screen by renderYOffset * tileScale pixels, and renderYOffset never
-- exceeds SURFACE_MAX (64), so the shift is at most 64 * tileScale = 128 pixels
-- at zoom 1. One step of (+1,+1) is 32 * tileScale = 64 pixels down
-- (IsoUtils.YToScreen), so two steps cover the whole raise. We scan the square
-- block (0..2, 0..2) rather than just the diagonal because the sprite is a full
-- tile wide, so the half-overlapping neighbours (+1,0) and (0,+1) can be the
-- square the picker names too.
CeroSecReach.PICK_REACH = 2

-- The drawn box of an object in the picker's screen space -- that is, screen
-- pixels multiplied by the zoom. Same construction vanilla uses for the water
-- shader's own click box (FBORenderObjectPicker.handleWaterShader): the
-- square's screen position less the camera offset, a box of 64 x 128 tile
-- units, and the render offset that raises a table-top sprite.
-- Returns x, y, width, height, texture; nil when the object has no sprite yet.
function CeroSecReach.drawnBox(object)
	local square = object and object:getSquare()
	if not square then return nil end
	local sprite = object:getSprite()
	local texture = sprite and sprite:getTextureForCurrentFrame(object:getDir())
	if not texture then return nil end

	local tileScale = Core.getTileScale()
	local x, y = ISCoordConversion.ToScreen(square:getX(), square:getY(), square:getZ())
	y = y - object:getRenderYOffset() * tileScale
	return x, y, 64 * tileScale, 128 * tileScale, texture
end

-- Is the mouse on this object's drawn pixels? The box first, then the sprite's
-- click mask, which is the very test the picker settles on
-- (IsoObjectPicker.ContextPick -> IsoObject.isMaskClicked). The mask is indexed
-- in texture pixels, so a box drawn bigger than its texture is divided back
-- down the way ContextPick divides by scaleX/scaleY.
-- Returns hit, x, y, width, height so the caller can log the box it tested.
function CeroSecReach.isMouseOn(object, mouseX, mouseY, playerIndex)
	local x, y, width, height, texture = CeroSecReach.drawnBox(object)
	if not x then return false end

	local zoom = getCore():getZoom(playerIndex or 0)
	local px, py = mouseX * zoom, mouseY * zoom
	if not CeroSec.pointInBox(px, py, x, y, width, height) then
		return false, x, y, width, height
	end

	local scaleX = width / texture:getWidthOrig()
	local scaleY = height / texture:getHeightOrig()
	local hit = object:isMaskClicked(math.floor((px - x) / scaleX), math.floor((py - y) / scaleY), false)
	return hit == true, x, y, width, height
end

-- Every computer on the squares that could be drawn under the cursor, nearest
-- to the viewer first.
local function pickCandidates(worldobjects)
	local seen, candidates = {}, {}
	for _, object in ipairs(worldobjects) do
		local square = object:getSquare()
		if square then
			local x0, y0, z0 = square:getX(), square:getY(), square:getZ()
			for dy = 0, CeroSecReach.PICK_REACH do
				for dx = 0, CeroSecReach.PICK_REACH do
					local near = getCell():getGridSquare(x0 + dx, y0 + dy, z0)
					if near and not seen[near] then
						seen[near] = true
						local objects = near:getObjects()
						for i = 0, objects:size() - 1 do
							local candidate = objects:get(i)
							if CeroSec.isComputerSprite(candidate:getSpriteName()) then
								table.insert(candidates, candidate)
							end
						end
					end
				end
			end
		end
	end

	table.sort(candidates, function(a, b)
		local sa, sb = a:getSquare(), b:getSquare()
		return CeroSec.drawnBefore(sa:getX(), sa:getY(), a:getObjectIndex(),
			sb:getX(), sb:getY(), b:getObjectIndex())
	end)
	return candidates
end

-- The computer the mouse is really on, or nil. Purely a screen test: whether
-- the player may touch it is still the caller's business.
function CeroSecReach.pickComputer(playerIndex, mouseX, mouseY, worldobjects)
	if not mouseX or not mouseY then return nil end

	local candidates = pickCandidates(worldobjects)
	if CeroSec.DEBUG then
		local zoom = getCore():getZoom(playerIndex or 0)
		CeroSec.log("pick: mouse " .. tostring(mouseX) .. "," .. tostring(mouseY) ..
			" zoom " .. tostring(zoom) .. " -> " .. tostring(mouseX * zoom) .. "," .. tostring(mouseY * zoom) ..
			" (" .. tostring(#candidates) .. " candidates)")
	end

	for _, candidate in ipairs(candidates) do
		local hit, x, y, width, height = CeroSecReach.isMouseOn(candidate, mouseX, mouseY, playerIndex)
		if CeroSec.DEBUG then
			local square = candidate:getSquare()
			CeroSec.log("pick:   " .. tostring(candidate:getSpriteName()) ..
				" at " .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ()) ..
				" raise " .. tostring(candidate:getRenderYOffset()) ..
				" box " .. tostring(x) .. "," .. tostring(y) .. " " .. tostring(width) .. "x" .. tostring(height) ..
				" -> " .. tostring(hit))
		end
		if hit then return candidate end
	end
	return nil
end
