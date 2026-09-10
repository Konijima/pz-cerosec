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

function CCeroSecObject:addLight()
	if self.light then return end
	-- Never stack a second light on a square that already has one.
	if getCell():getLightSourceAt(self.x, self.y, self.z) then return end
	self.light = getCell():addLamppost(self.x, self.y, self.z,
		CeroSec.LIGHT_R, CeroSec.LIGHT_G, CeroSec.LIGHT_B, CeroSec.LIGHT_RADIUS)
	CeroSec.log("light on at " .. self.x .. "," .. self.y .. "," .. self.z)
end

function CCeroSecObject:removeLight()
	if not self.light then return end
	getCell():removeLamppost(self.light)
	self.light = nil
	CeroSec.log("light off at " .. self.x .. "," .. self.y .. "," .. self.z)
end

-- Idempotent: bring the glow in line with the state. Safe to call repeatedly.
function CCeroSecObject:syncLight()
	if self.on then
		self:addLight()
	else
		self:removeLight()
	end
end
