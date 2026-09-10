require "CeroSec/CeroSecDefs"

--
-- Who is typing.
--
-- Shared, not duplicated on each side: in singleplayer the server answers by
-- broadcast and the terminal decides for itself whether an answer is addressed
-- to it, so the two sides must spell the key the same way or nothing arrives.
--
-- getOnlineID is what vanilla keys per-player server state on
-- (Fishing.ServerBobberManager, Bobber.lua:26). It is not enough on its own
-- here: in singleplayer, and in split screen, every character shares the one
-- connection. So the local player number and the username go into the key as
-- well. Stable for as long as the connection lives, which is exactly as long as
-- a session may live.
--
-- This file touches the game API, which is why it is not in CeroSecDefs: that
-- one stays pure Lua so it can be tested headless.
--

function CeroSec.playerKey(playerObj)
	if not playerObj then return nil end
	return tostring(playerObj:getOnlineID()) .. "/" ..
		tostring(playerObj:getPlayerNum()) .. "/" ..
		tostring(playerObj:getUsername())
end
