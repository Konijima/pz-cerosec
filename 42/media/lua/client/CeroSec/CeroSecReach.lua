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
-- What the game hands the menu, proved out of the jar (offsets are javap -c
-- offsets, B42 42.20.4, and the whole walk is written out in
-- docs/notes/picking.md):
--
--   UIManager.update, on every mouse MOVE, calls
--   IsoObjectPicker.ContextPick(mx, my) and stores the one ClickObject it gets
--   in UIManager.picked (@1078-1086). The right-click release fires
--   OnObjectRightMouseButtonUp with picked.tile -- ONE IsoObject (@783-802).
--   ISObjectClickHandler.doRClick then builds `objects` out of that single
--   object plus whatever PickDoor/PickWindow/PickWindowFrame/PickThumpable/
--   PickHoppable/PickTree add, and hands it to the world menu, which triggers
--   OnFillWorldObjectContextMenu with it. So `worldobjects` is ONE object, and
--   the other six are never a computer.
--
--   ContextPick itself (FBORenderObjectPicker.ContextPick, @43-620) is not a
--   square walk at all: it asks getClickObjects for every object drawn near the
--   point, tests each against the box the RENDERER recorded for it
--   (ObjectRenderInfo.renderX/renderY/renderWidth/renderHeight, @167-224) and
--   then against that object's own alpha mask (IsoObject.isMaskClicked,
--   @333/@429). Every survivor is scored (ClickObject.calculateScore) and the
--   HIGHEST score wins (@601-620, the comparator sorts ascending and the last
--   is taken). So the game picks by per-object mask over every rendered object,
--   and a raised sprite is handled exactly right: renderY already carries the
--   raise (IsoObject.updateRenderInfoForObjectPicker, @297-315:
--   sy -= offsetY + renderYOffset * Core.tileScale).
--
-- Which kills the story this code used to be written on. The old comment here
-- said the picker "budgets three tiles" and never looks at a raised sprite's
-- square. The staircase is real (getObjectsAt, @246-288, walks
-- leftSideXy/rightSideXy = {0,0} {0,1} {1,1} {1,2} {2,2} {2,3} {3,3} out of the
-- mouse's own iso tile) but three diagonal steps is SIX steps of x+y, and six is
-- exactly the height of a sprite box measured in steps -- see PICK_AHEAD below.
-- A monitor's own pixels sit low in its texture, so a monitor on a desk lands
-- one or two steps out, nowhere near the edge of the budget. The game sees it.
--
-- What actually happened in the screenshot, then, is the score: the chair on the
-- front square carries IsoFlagType.bed, which is +2 on calculateScore (@417-435)
-- where a plain computer gets nothing, and it stands on the square the player is
-- on, which costs it less of the Manhattan penalty (@656-693). When the two
-- masks overlap the chair wins, the menu is built for the chair, and
-- `worldobjects` is {chair} -- one square SOUTH of the desk.
--
-- Hence the two things this section now does differently.
--
--   The candidate squares are taken from the MOUSE's own iso tile, the way
--   getObjectsAt takes them, and not from the square of the object the game
--   picked. The picked object is itself somewhere inside that staircase, so
--   walking the staircase again out of IT lands nowhere near the start: from the
--   chair at 2089,5833 the old scan of (+0..2, +0..2) covered 2089..2091 x
--   5833..5835 and the desk at 2089,5832 -- dy = -1 -- was never looked at once.
--   That is the "something invisible in front": nothing was in front, the search
--   was simply pointed the wrong way.
--
--   The box is the one the renderer drew, offsets and all. drawnBox used to take
--   ISCoordConversion.ToScreen as the box's top-left, but IsoObject carries
--   offsetX = 32 * tileScale and offsetY = 96 * tileScale (IsoObject.<init>,
--   @38-57) and the renderer SUBTRACTS both. At tileScale 2 the old box sat 64
--   pixels right and 192 pixels low -- three quarters of a sprite height -- so
--   the mask was read three quarters of a sprite below the pixels it was meant
--   to read, and the only way to hit a monitor was to click most of a tile below
--   it. Which is the other half of the report: "sometimes I almost have to click
--   the ground".
--

-- How far the candidate squares run, in steps of x + y. Derived, not measured:
--
-- A square's screen anchor is YToScreen = 16 * tileScale * (x + y) plus the
-- level term, so one step of x + y is 16 * tileScale pixels down. The object's
-- box starts offsetY + renderYOffset * tileScale ABOVE that anchor and is
-- 128 * tileScale tall, so with s = x + y and raise = renderYOffset:
--
--   anchor(s) - 96*ts - raise*ts  <=  mouse  <=  anchor(s) + 32*ts - raise*ts
--   s - 6 - raise/16              <=  s(mouse)  <=  s + 2 - raise/16
--   s(mouse) - 2 + raise/16       <=  s         <=  s(mouse) + 6 + raise/16
--
-- raise is a render offset and never exceeds SURFACE_MAX, so raise/16 runs 0..4
-- and s - s(mouse) runs -2..10. Six of those ten are the game's own staircase;
-- the other four are the raise, which is the part a table-top computer needs and
-- the part the game itself would miss on a tall enough stack.
--
-- Then two more, because the tile is not the point. The window is measured from
-- the mouse's FRACTIONAL iso position, but a square is named by integers, so the
-- two coordinates are each floored and each loses up to one whole step of its
-- own -- up to two off the sum, always in the same direction. Behind is
-- unaffected (flooring can only move the anchor back, never forward), ahead
-- takes both.
CeroSecReach.PICK_BEHIND = 2
CeroSecReach.PICK_AHEAD = 6 + CeroSecReach.SURFACE_MAX / 16 + 2

-- And how far sideways. Screen X is 32 * tileScale * (x - y), the box is
-- 64 * tileScale wide and centred on the anchor, so x - y can differ from the
-- mouse's own by one either way; the flooring moves the difference by strictly
-- less than one more, so one step each way still covers it.
CeroSecReach.PICK_SIDE = 1

-- The box the renderer drew this object into, in the picker's own space -- world
-- screen units, which is screen pixels multiplied by the zoom (ContextPick
-- multiplies the mouse by getZoom to enter it, @11-23).
--
-- The same three terms the renderer uses (IsoObject.updateRenderInfoForObjectPicker):
-- the square's screen position less the camera offset (ISCoordConversion.ToScreen),
-- less the object's own draw offsets, less the raise that lifts a table-top
-- sprite. The size is 64 x 128 tile units: a 64x128 texture is drawn at
-- tileScale and a 128x256 one at half of it (@35-126), so both come to
-- 64 * tileScale by 128 * tileScale and the scale below divides back to whichever
-- it was.
-- Returns x, y, width, height, texture; nil when the object has no sprite yet.
function CeroSecReach.drawnBox(object)
	local square = object and object:getSquare()
	if not square then return nil end
	local sprite = object:getSprite()
	local texture = sprite and sprite:getTextureForCurrentFrame(object:getDir())
	if not texture then return nil end

	local tileScale = Core.getTileScale()
	local x, y = ISCoordConversion.ToScreen(square:getX(), square:getY(), square:getZ())
	x = x - object:getOffsetX()
	y = y - object:getOffsetY() - object:getRenderYOffset() * tileScale
	return x, y, 64 * tileScale, 128 * tileScale, texture
end

-- Is the mouse on this object's drawn pixels? The box first, then the sprite's
-- click mask, which is the very test the picker settles on
-- (FBORenderObjectPicker.ContextPick -> IsoObject.isMaskClicked). The mask is
-- indexed in texture pixels, so a box drawn bigger than its texture is divided
-- back down the way ContextPick divides by scaleX/scaleY.
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

-- Every square whose sprite can be drawn over the mouse point, on one level.
-- The mouse's own iso tile, the way getObjectsAt takes it
-- (IsoUtils.XToIso/YToIso on the mouse multiplied by the zoom), and then the
-- (x + y, x - y) window PICK_BEHIND/PICK_AHEAD/PICK_SIDE derive above. x + y and
-- x - y always have the same parity, so a sideways step only exists for half the
-- forward steps -- which is precisely why the game's own candidates read as a
-- staircase.
function CeroSecReach.pickSquares(mouseX, mouseY, z, zoom)
	local out = {}
	local wx, wy = ISCoordConversion.ToWorld(mouseX * zoom, mouseY * zoom, z)
	if wx == nil or wy == nil then return out end
	local tx, ty = math.floor(wx), math.floor(wy)

	for sum = -CeroSecReach.PICK_BEHIND, CeroSecReach.PICK_AHEAD do
		for diff = -CeroSecReach.PICK_SIDE, CeroSecReach.PICK_SIDE do
			if (sum + diff) % 2 == 0 then
				local square = getCell():getGridSquare(
					tx + (sum + diff) / 2, ty + (sum - diff) / 2, z)
				if square then out[#out + 1] = square end
			end
		end
	end
	return out
end

-- Every computer that could be drawn under the cursor, nearest to the viewer
-- first. The levels looked at are the ones the game itself resolved the click
-- to -- the z of the objects it handed over -- because the mouse's iso tile
-- depends on the level and a computer on another floor is out of reach anyway.
local function pickCandidates(worldobjects, mouseX, mouseY, zoom)
	local levels, seen, candidates = {}, {}, {}
	for _, object in ipairs(worldobjects) do
		local square = object:getSquare()
		if square then levels[square:getZ()] = true end
	end

	for z in pairs(levels) do
		for _, square in ipairs(CeroSecReach.pickSquares(mouseX, mouseY, z, zoom)) do
			if not seen[square] then
				seen[square] = true
				local objects = square:getObjects()
				for i = 0, objects:size() - 1 do
					local candidate = objects:get(i)
					if CeroSec.isComputerSprite(candidate:getSpriteName()) then
						table.insert(candidates, candidate)
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

-- The computer the mouse is really on, or nil. Purely a screen test: whether the
-- player may touch it is still the caller's business, and NOTHING here refuses a
-- hit on account of what else is under the cursor. A computer whose own pixels
-- are under the mouse wins, chair or no chair -- which is what the game does for
-- every other object on a table, and what it would have done for this one if a
-- desk chair did not outscore a computer.
function CeroSecReach.pickComputer(playerIndex, mouseX, mouseY, worldobjects)
	if not mouseX or not mouseY then return nil end

	local zoom = getCore():getZoom(playerIndex or 0)
	local candidates = pickCandidates(worldobjects, mouseX, mouseY, zoom)
	if CeroSec.DEBUG then
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
				" -> " .. (hit and "HIT" or "no mask"))
		end
		if hit then return candidate end
	end
	return nil
end
