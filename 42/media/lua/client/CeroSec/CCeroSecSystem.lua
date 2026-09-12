require "Map/CGlobalObjectSystem"
require "CeroSec/CeroSecDefs"
require "CeroSec/CCeroSecObject"
require "CeroSec/CeroSecTerminal"
require "CeroSec/CeroSecDebugUI"

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
--
-- And this is where the glow comes back. The announce is the only call the client
-- gets when a chunk returns, and Java's receiveNewLuaObjectAt calls this method
-- and nothing else -- it copies the announced state in afterwards and never calls
-- OnLuaObjectUpdated, which only receiveUpdateLuaObjectAt does (javap -c
-- CGlobalObjectSystem). So the state to match is read off the IsoObject the chunk
-- brought with it, not off our own table, which the copy has not reached yet.
function CCeroSecSystem:newLuaObjectAt(x, y, z)
	local existing = self.system:getObjectAt(x, y, z)
	local luaObject = existing and existing:getModData()
		or CGlobalObjectSystem.newLuaObjectAt(self, x, y, z)
	local on = luaObject:onFromSprite()
	if on ~= nil then luaObject.on = on end
	luaObject:syncLight()
	return luaObject
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
	CeroSecDebugUI.onServerAnswer(command, args)
end

-- Multiplayer: the server answers one connection. That is not one window --
-- split screen puts several players on a connection -- so the terminal still
-- checks the token before it believes a word of it.
Events.OnServerCommand.Add(function(module, command, args)
	if module ~= CeroSec.MODULE then return end
	CeroSecTerminal.onServerAnswer(command, args)
	CeroSecDebugUI.onServerAnswer(command, args)
end)

-- There is no sweep. This used to walk every object once a minute, because the
-- announce path did not sync the light and the object believed its own handle --
-- and a sweep could not mend that either, since addLight saw self.light set and
-- did nothing. Now the four events that can change the answer each make it match
-- (announce, update, removal, pickup) and the cell is asked whether the light is
-- really there, so there is nothing left for a minute hand to catch up on.
CGlobalObjectSystem.RegisterSystemClass(CCeroSecSystem)

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
