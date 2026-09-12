require "Map/CGlobalObject"
require "CeroSec/CeroSecDefs"

CCeroSecObject = CGlobalObject:derive("CCeroSecObject")

-- Screen glow: dim and bluish-white, one square wide, so it reads as a monitor
-- and not as a lamp.
CeroSec.LIGHT_R = 0.55
CeroSec.LIGHT_G = 0.65
CeroSec.LIGHT_B = 0.85
CeroSec.LIGHT_RADIUS = 3

function CCeroSecObject:new(luaSystem, globalObject)
	return CGlobalObject.new(self, luaSystem, globalObject)
end

function CCeroSecObject:getObject()
	return self:getIsoObject()
end

--
-- The glow.
--
-- Lights are rendering-local: IsoObject has no public createLightSource in
-- 42.20.4 (that lives on IsoThumpable, and a vanilla computer tile is a plain
-- IsoObject), and the server of a dedicated game draws nothing. So the client
-- owns the light and registers it with the cell itself.
--

-- Has the CELL still got the light we asked for? The handle is not an answer.
-- The game drops a lamppost of its own accord and tells nobody:
-- LightingJNI.checkLights walks IsoCell.getLamppostPositions() and, for each
-- source, removes it from that stack when its life is 0 or isInBounds() is false
-- (javap -c LightingJNI.checkLights, offsets 104-123), and isInBounds() is
-- nothing but "inside some player's IsoChunkMap world tiles" (javap -c
-- IsoLightSource.isInBounds). It also zeroes the life of a source whose recorded
-- chunk is not the chunk now covering its square (offsets 78-101), which is what
-- a chunk streamed in again is. So a survivor who walks far enough for his chunks
-- to go loses the light, keeps the handle, and comes back to a lit sprite with no
-- glow -- for ever, because "self.light is set" was read as "the light is there".
-- The cell is the authority.
function CCeroSecObject:hasLight()
	if not self.light then return false end
	local cell = getCell()
	if not cell then return false end
	return cell:getLightSourceAt(self.x, self.y, self.z) == self.light
end

function CCeroSecObject:addLight()
	if self:hasLight() then return end
	-- The handle is stale: the cell dropped the light while the chunk was away.
	-- Let go of it, or nothing is ever asked for again.
	self.light = nil
	local cell = getCell()
	if not cell then return end
	-- Never stack a second light on a square that already has one.
	if cell:getLightSourceAt(self.x, self.y, self.z) then return end
	self.light = cell:addLamppost(self.x, self.y, self.z,
		CeroSec.LIGHT_R, CeroSec.LIGHT_G, CeroSec.LIGHT_B, CeroSec.LIGHT_RADIUS)
	CeroSec.log("light on at " .. self.x .. "," .. self.y .. "," .. self.z)
end

function CCeroSecObject:removeLight()
	if not self.light then return end
	-- Only ours to take out. A source the cell has already dropped is not in its
	-- stack any more, and removeLamppost would be aimed at nothing.
	if self:hasLight() then
		getCell():removeLamppost(self.light)
		CeroSec.log("light off at " .. self.x .. "," .. self.y .. "," .. self.z)
	else
		CeroSec.log("light dropped with the chunk at " .. self.x .. "," .. self.y .. "," .. self.z)
	end
	self.light = nil
end

-- What the WORLD says this machine is, or nil when its chunk is not in. The
-- sprite is the only answer that is right on the announce path: Java copies the
-- announced state into our table after newLuaObjectAt returns, while the server
-- sets the sprite before it announces (SCeroSecObject:stateToIsoObject calls
-- syncSprite, then newLuaObjectOnClient at :123). The mod's own server adopts a
-- machine's on/off off the sprite the same way (stateFromIsoObject).
function CCeroSecObject:onFromSprite()
	local isoObject = self:getIsoObject()
	if not isoObject then return nil end
	return CeroSec.isOnSprite(isoObject:getSpriteName())
end

-- Idempotent: bring the glow in line with the state. Safe to call repeatedly.
function CCeroSecObject:syncLight()
	if self.on then
		self:addLight()
	else
		self:removeLight()
	end
end
