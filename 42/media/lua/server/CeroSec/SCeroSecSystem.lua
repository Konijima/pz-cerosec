if isClient() then return end

require "Map/SGlobalObjectSystem"
require "CeroSec/CeroSecDefs"
require "CeroSec/SCeroSecObject"

SCeroSecSystem = SGlobalObjectSystem:derive("SCeroSecSystem")

function SCeroSecSystem:new()
	return SGlobalObjectSystem.new(self, "cerosec")
end

function SCeroSecSystem:initSystem()
	SGlobalObjectSystem.initSystem(self)

	-- Fields of this system that are saved.
	self.system:setModDataKeys(nil)

	-- Fields of each GlobalObject that are saved to gos_cerosec.bin.
	self.system:setObjectModDataKeys({ 'v', 'on', 'facing' })

	-- Fields sent to clients on add/update. Without this the client mirror
	-- receives an empty table (SGlobalObjectNetwork saves only these keys).
	self.system:setObjectSyncKeys({ 'v', 'on', 'facing' })
end

function SCeroSecSystem:newLuaObject(globalObject)
	return SCeroSecObject:new(self, globalObject)
end

function SCeroSecSystem:isValidIsoObject(isoObject)
	return isoObject ~= nil and CeroSec.isComputerSprite(isoObject:getSpriteName())
end

-- Sent to a client when it connects, and to the local client in singleplayer.
function SCeroSecSystem:getInitialStateForClient()
	return nil
end

-- Events.OnObjectAdded only fires for objects a player or the network added
-- (AddItemToMapPacket, and ISMoveableSpriteProps.lua:2382 for placement) --
-- never for chunk loading. So reaching here means the computer was just placed:
-- it starts off, whatever it was before.
function SCeroSecSystem:OnObjectAdded(isoObject)
	if not self:isValidIsoObject(isoObject) then return end
	if not isoObject:getSquare() then return end

	local square = isoObject:getSquare()
	local luaObject = self:getLuaObjectOnSquare(square)
	if not luaObject then
		luaObject = self:newLuaObjectOnSquare(square)
		luaObject:initNew()
	end
	luaObject:resetForPlacement(isoObject)
end

-- The client walks the player to the square in front of the screen before it
-- sends anything, but the client is not to be trusted. Vanilla's own global
-- object commands do not check proximity at all (SCampfireSystemCommands.lua),
-- so the tolerance comes from the one place vanilla decides a player is close
-- enough to interact without walking: luautils.lua:138-140, half a square of
-- centre offset and 1.6 of slack on each axis. Adjacency only -- which of the
-- four sides he stands on is the client's business.
local function isAdjacent(playerObj, x, y, z)
	if not playerObj then return false end
	local square = playerObj:getCurrentSquare()
	if not square or square:getZ() ~= z then return false end
	return math.abs(x + 0.5 - playerObj:getX()) <= 1.6
		and math.abs(y + 0.5 - playerObj:getY()) <= 1.6
end

function SCeroSecSystem:OnClientCommand(command, playerObj, args)
	if command ~= "toggle" then return end
	if not args or not args.x then return end
	if not isAdjacent(playerObj, args.x, args.y, args.z) then return end

	local luaObject = self:getLuaObjectAt(args.x, args.y, args.z)
	if not luaObject then
		-- The client saw a computer we have no GlobalObject for; adopt it.
		local isoObject = self:getIsoObjectAt(args.x, args.y, args.z)
		if not isoObject then return end
		self:loadIsoObject(isoObject)
		luaObject = self:getLuaObjectAt(args.x, args.y, args.z)
		if not luaObject then return end
	end
	luaObject:toggle()
end

-- Computers on a square that lost power shut themselves off.
function SCeroSecSystem:checkPower()
	for i = 1, self:getLuaObjectCount() do
		local luaObject = self:getLuaObjectByIndex(i)
		if luaObject.on and not luaObject:hasPower() then
			luaObject:turnOff()
		end
	end
end

SGlobalObjectSystem.RegisterSystemClass(SCeroSecSystem)

Events.EveryOneMinute.Add(function()
	if SCeroSecSystem.instance then SCeroSecSystem.instance:checkPower() end
end)

-- Chunk loading does not fire OnObjectAdded, so register the computer sprites
-- with MapObjects the way the campfire does (MOCampfire.lua:42-44, 90-92).
local PRIORITY = 5

local function LoadComputer(isoObject)
	if not SCeroSecSystem.instance then return end
	SCeroSecSystem.instance:loadIsoObject(isoObject)
end

for _, facing in ipairs(CeroSec.FACINGS) do
	MapObjects.OnNewWithSprite(CeroSec.SPRITES_OFF[facing], LoadComputer, PRIORITY)
	MapObjects.OnLoadWithSprite(CeroSec.SPRITES_OFF[facing], LoadComputer, PRIORITY)
	MapObjects.OnNewWithSprite(CeroSec.SPRITES_ON[facing], LoadComputer, PRIORITY)
	MapObjects.OnLoadWithSprite(CeroSec.SPRITES_ON[facing], LoadComputer, PRIORITY)
end
