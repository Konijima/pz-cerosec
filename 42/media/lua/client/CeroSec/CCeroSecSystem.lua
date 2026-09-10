require "Map/CGlobalObjectSystem"
require "CeroSec/CeroSecDefs"
require "CeroSec/CCeroSecObject"
require "CeroSec/CeroSecTerminal"

CCeroSecSystem = CGlobalObjectSystem:derive("CCeroSecSystem")

function CCeroSecSystem:new()
	return CGlobalObjectSystem.new(self, "cerosec")
end

function CCeroSecSystem:isValidIsoObject(isoObject)
	return instanceof(isoObject, "IsoObject") and CeroSec.isComputerSprite(isoObject:getSpriteName())
end

function CCeroSecSystem:newLuaObject(globalObject)
	return CCeroSecObject:new(self, globalObject)
end

-- The server announces an object whenever a chunk holding one is loaded, which
-- happens more than once for the same location. GlobalObjectSystem.newObject
-- throws on a duplicate, so hand back the existing object instead.
function CCeroSecSystem:newLuaObjectAt(x, y, z)
	local existing = self.system:getObjectAt(x, y, z)
	if existing then return existing:getModData() end
	return CGlobalObjectSystem.newLuaObjectAt(self, x, y, z)
end

function CCeroSecSystem:removeLuaObjectAt(x, y, z)
	local luaObject = self:getLuaObjectAt(x, y, z)
	if luaObject then luaObject:removeLight() end
	CGlobalObjectSystem.removeLuaObjectAt(self, x, y, z)
end

function CCeroSecSystem:OnLuaObjectUpdated(luaObject)
	luaObject:syncLight()
	-- A machine that just went dark has no terminal. The window watches the
	-- sprite on its own as well; this is the earlier of the two.
	if not luaObject.on then
		CeroSecTerminal.closeAt(luaObject.x, luaObject.y, luaObject.z)
	end
end

-- Singleplayer: the server answers by broadcast on the global object channel,
-- because sendServerCommand does nothing when there is no GameServer
-- (LuaManager.GlobalObject.sendServerCommand).
function CCeroSecSystem:OnServerCommand(command, args)
	CeroSecTerminal.onServerAnswer(command, args)
end

-- Multiplayer: the server answers one connection. That is not one window --
-- split screen puts several players on a connection -- so the terminal still
-- checks the token before it believes a word of it.
Events.OnServerCommand.Add(function(module, command, args)
	if module ~= CeroSec.MODULE then return end
	CeroSecTerminal.onServerAnswer(command, args)
end)

-- Idempotent sweep. Catches the cases no single event covers: objects announced
-- by receiveNewLuaObjectAt (which does not call OnLuaObjectUpdated), a cell that
-- dropped our light with its chunk, and a light left behind by anything else.
function CCeroSecSystem:syncLights()
	local count = self:getLuaObjectCount()
	if not count then return end
	for i = 1, count do
		self:getLuaObjectByIndex(i):syncLight()
	end
end

CGlobalObjectSystem.RegisterSystemClass(CCeroSecSystem)

Events.EveryOneMinute.Add(function()
	if CCeroSecSystem.instance then CCeroSecSystem.instance:syncLights() end
end)

-- Drop the glow the moment the computer goes, rather than waiting for the server
-- to tell us the GlobalObject is gone. Fires on pickup for plain objects
-- (ISMoveableSpriteProps.lua:1406) and on any removal packet.
Events.OnObjectAboutToBeRemoved.Add(function(isoObject)
	if not CCeroSecSystem.instance then return end
	if not CCeroSecSystem.instance:isValidIsoObject(isoObject) then return end
	local square = isoObject:getSquare()
	if not square then return end
	local luaObject = CCeroSecSystem.instance:getLuaObjectOnSquare(square)
	if luaObject then luaObject:removeLight() end
end)
