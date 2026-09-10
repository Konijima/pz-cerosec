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

--
-- Geometry
--
-- A tile's Facing property is the direction the object looks at, and the tile
-- facings are the names of IsoDirections: N is (0,-1), S is (0,+1), E is (+1,0),
-- W is (-1,0) (zombie/iso/IsoDirections.java enum constants). So the square in
-- front of the screen is the neighbour in the facing direction: that is where
-- the player has to stand to look at the monitor.
CeroSec.FRONT_OFFSET = {
	N = { 0, -1 },
	S = { 0, 1 },
	E = { 1, 0 },
	W = { -1, 0 },
}

-- dx, dy of the square in front of a computer with this facing. nil, nil for
-- anything that is not one of the four facings.
function CeroSec.frontOffset(facing)
	local offset = CeroSec.FRONT_OFFSET[facing]
	if not offset then return nil, nil end
	return offset[1], offset[2]
end

-- The facing whose front offset is this step, or nil when the step is not one
-- of the four cardinal neighbours. The inverse of frontOffset.
function CeroSec.facingForOffset(dx, dy)
	for i = 1, #CeroSec.FACINGS do
		local facing = CeroSec.FACINGS[i]
		local offset = CeroSec.FRONT_OFFSET[facing]
		if offset[1] == dx and offset[2] == dy then return facing end
	end
	return nil
end

-- Which way a chair standing on the front square has to look for the player
-- sitting on it to be looking at the screen: back along the step that put the
-- square in front of the computer. Derived, not tabulated, so it can never
-- disagree with FRONT_OFFSET. A furniture tile's facing is the direction the
-- character seated on it looks (ISRestAction:setBeforeSitDirection, facing "N"
-- with the "Front" seat gives faceDirection(IsoDirections.N)), the same
-- convention the computer sprites use. So a computer facing S wants a chair
-- facing N, and so on for the other three.
function CeroSec.chairFacingFor(computerFacing)
	local dx, dy = CeroSec.frontOffset(computerFacing)
	if not dx then return nil end
	return CeroSec.facingForOffset(-dx, -dy)
end

--
-- Screen geometry
--
-- Isometric projection, from IsoUtils (zombie/iso/IsoUtils.java): screen X is
-- (x - y) * 32 * tileScale and screen Y is (x + y) * 16 * tileScale plus the
-- floor term. So a square with a bigger x+y is drawn LOWER on the screen and
-- LATER, over its neighbours: it is the one nearer the viewer.

-- Is a point inside a drawn box? Copied comparison for comparison from the
-- picker's own test (IsoObjectPicker.ContextPick: x > obj.x and y > obj.y and
-- x <= obj.x + obj.width and y <= obj.y + obj.height), left edge exclusive,
-- right edge inclusive, so that two boxes sharing an edge never both claim the
-- same pixel.
function CeroSec.pointInBox(px, py, x, y, width, height)
	return px > x and py > y and px <= x + width and py <= y + height
end

-- Order two drawn objects front to back: the one nearer the viewer first.
-- Bigger x+y is nearer; on the same square the object drawn last (higher index
-- in the square's object list) is on top. Returns true when a comes first.
function CeroSec.drawnBefore(ax, ay, aIndex, bx, by, bIndex)
	local a, b = ax + ay, bx + by
	if a ~= b then return a > b end
	return (aIndex or 0) > (bIndex or 0)
end

--
-- Hostnames
--
-- A computer names itself the first time it boots, from the square it stands
-- on: two machines can never share a square, so two machines can never share a
-- name. The name is then written into the OS state and travels with it, so
-- moving the computer does not rename it -- the derivation only ever runs once.
-- Base 36 keeps a five-digit map coordinate down to four characters, which is
-- what keeps the whole thing inside HOSTNAME_MAX.
--

CeroSec.HOSTNAME_MAX = 16

local BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"

-- Non-negative integers become digits; a negative coordinate gets an "n" in
-- front rather than a "-", because a leading "-" is not a valid OS name
-- (CeroSecOSPath.isValidName).
local function base36(n)
	n = math.floor(tonumber(n) or 0)
	local sign = ""
	if n < 0 then
		sign = "n"
		n = -n
	end
	if n == 0 then return sign .. "0" end
	local out = ""
	while n > 0 do
		local digit = n % 36
		out = string.sub(BASE36, digit + 1, digit + 1) .. out
		n = math.floor(n / 36)
	end
	return sign .. out
end

function CeroSec.hostnameFor(x, y)
	return string.sub("ksp-" .. base36(x) .. "-" .. base36(y), 1, CeroSec.HOSTNAME_MAX)
end

--
-- The prompt
--
-- Built where the session is, i.e. on the server, and sent down with every
-- answer, so the terminal never has to guess who it is logged in as or where.
-- Kept short so that a long path still leaves room to type on a 60 column line.
--

CeroSec.PROMPT_MAX = 30

function CeroSec.prompt(user, hostname, cwd, admin)
	local head = tostring(user) .. "@" .. tostring(hostname) .. ":"
	local tail = admin and "# " or "$ "
	local room = CeroSec.PROMPT_MAX - #head - #tail
	if room < 1 then room = 1 end
	cwd = tostring(cwd)
	-- Too long: keep the tail of the path and mark the cut, as the OS does.
	if #cwd > room then cwd = "~" .. string.sub(cwd, #cwd - room + 2) end
	return head .. cwd .. tail
end

--
-- Rings
--
-- The scrollback and the input history are both "keep the last N", and both are
-- pure list work, so they live here and are tested headless.
--

-- Append, dropping from the front once the list is longer than max.
function CeroSec.ringPush(list, value, max)
	list[#list + 1] = value
	while #list > max do table.remove(list, 1) end
	return list
end

-- Where a scrollback view starts: 0 is the bottom (the newest rows). Clamped to
-- what there is to scroll, so a window taller than the scrollback never scrolls.
function CeroSec.clampScroll(offset, count, rows)
	local most = count - rows
	if most < 0 then most = 0 end
	if offset < 0 then return 0 end
	if offset > most then return most end
	return offset
end

-- Walk the input history. index 0 is the line being typed, 1 the last line
-- entered, #history the oldest. delta is +1 for "older" (up) and -1 for
-- "newer" (down). Returns the new index and the text to show.
function CeroSec.historyPick(history, index, delta)
	local wanted = index + delta
	if wanted < 0 then wanted = 0 end
	if wanted > #history then wanted = #history end
	if wanted == 0 then return 0, "" end
	return wanted, history[#history - wanted + 1]
end

--
-- The console
--
-- The screen belongs to the machine, not to the player. One console per
-- computer, living on the server's GlobalObject and saved with it: what is on
-- it, who is logged in, and where he is. A player who walks away and comes back
-- is handed the very same screen, and two players standing at the same computer
-- read the same one -- physical access is the only access there is.
--
-- Everything here is pure list and string work, so it lives in the defs and is
-- tested headless (tests/terminal_test.lua). Nothing below knows the game.
--

-- Lines kept on a screen. Smaller than the client's own scrollback on purpose:
-- this one is written to gos_cerosec.bin for every computer in Knox County.
CeroSec.CONSOLE_MAX = 100

-- The BIOS. Written by the server into the console the first time somebody
-- opens a machine that has just been switched on, so that it is on the screen
-- exactly once per power-on -- and so that the second player to open the same
-- computer sees the same lines the first one saw, instead of a second boot.
CeroSec.BOOT_LINES = {
	"CeroSec BIOS v1.03 -- (c) 1993 CeroSec Systems",
	"Memory test: 640K OK",
	"Detecting drives ... hda 20MB",
	"Booting from hda ...",
	"",
}

-- A console at power-on: nothing on the screen, nobody logged in, and the BIOS
-- still to come.
function CeroSec.newConsole()
	return { booted = false, lines = {} }
end

-- One stored screen line. A line is text and only text: every byte below 0x20
-- is dropped (a tab becomes a space, the way a terminal prints it in a fixed
-- grid), and nothing is ever wider than the screen. The line a player typed
-- comes from the client, so this is where it is made safe.
function CeroSec.consoleLine(text)
	if type(text) ~= "string" then text = tostring(text) end
	local out = ""
	for i = 1, #text do
		local b = string.byte(text, i)
		if b == 9 then
			out = out .. " "
		elseif b >= 32 then
			out = out .. string.sub(text, i, i)
		end
	end
	if #out > CeroSec.COLS then out = string.sub(out, 1, CeroSec.COLS) end
	return out
end

function CeroSec.consolePush(console, text)
	CeroSec.ringPush(console.lines, CeroSec.consoleLine(text), CeroSec.CONSOLE_MAX)
	return console
end

function CeroSec.consolePushAll(console, lines)
	if type(lines) ~= "table" then return console end
	for i = 1, #lines do CeroSec.consolePush(console, lines[i]) end
	return console
end

function CeroSec.consoleClear(console)
	console.lines = {}
	return console
end

-- Logged out: the screen goes back to a bare login prompt. Nothing of the
-- session survives, which is the whole point of typing exit on a machine
-- anybody else can walk up to.
function CeroSec.consoleLogout(console)
	console.user = nil
	console.cwd = nil
	console.pending = nil
	console.lines = {}
	return console
end

-- What the console is waiting for: a user name, a password, or a command.
function CeroSec.consoleMode(console)
	if type(console) ~= "table" then return "login" end
	if console.pending ~= nil then return "password" end
	if console.user == nil then return "login" end
	return "shell"
end

-- The prompt that goes with it. Derived from the console and from nothing else,
-- so the server never has to remember what it last told a window.
function CeroSec.consolePrompt(console, hostname, admin)
	local mode = CeroSec.consoleMode(console)
	if mode == "password" then return "password: " end
	if mode == "login" then return "login: " end
	return CeroSec.prompt(console.user, hostname, console.cwd or "/", admin)
end

-- What a password looks like once it is on the screen. The cleartext never
-- reaches a stored line.
function CeroSec.maskedLine(prompt, text)
	if type(text) ~= "string" then text = "" end
	return prompt .. string.rep("*", #text)
end

-- A console handed back by the game, or by a forged modData: keep what is still
-- shaped like a console and drop the rest. Always returns a console.
function CeroSec.repairConsole(console)
	if type(console) ~= "table" then return CeroSec.newConsole() end
	local out = CeroSec.newConsole()
	out.booted = console.booted and true or false
	if type(console.user) == "string" then out.user = console.user end
	if type(console.cwd) == "string" then out.cwd = console.cwd end
	if type(console.pending) == "string" then out.pending = console.pending end
	if type(console.lines) == "table" then
		local lines = console.lines
		for i = 1, #lines do
			if type(lines[i]) == "string" then CeroSec.consolePush(out, lines[i]) end
		end
	end
	return out
end

--
-- The look: "Phosphore vert"
--
-- Every colour the terminal draws is named here and nowhere else, as r, g, b in
-- 0..1 the way every ISUIElement draw call wants them. The hex beside each one
-- is the value that was approved on the mockups; nothing computes a colour from
-- another one, so a change here is a change on screen and nothing else.
--

CeroSec.COLS = 60
CeroSec.ROWS = 20

CeroSec.COLORS = {
	screen  = { r = 0.024, g = 0.102, b = 0.047 }, -- #061a0c
	text    = { r = 0.361, g = 1.000, b = 0.478 }, -- #5cff7a
	dim     = { r = 0.184, g = 0.604, b = 0.278 }, -- #2f9a47
	bright  = { r = 0.831, g = 1.000, b = 0.851 }, -- #d4ffd9
	bezel   = { r = 0.788, g = 0.749, b = 0.655 }, -- #c9bfa7
	bezelHi = { r = 0.890, g = 0.859, b = 0.776 }, -- #e3dbc6
	bezelLo = { r = 0.612, g = 0.569, b = 0.475 }, -- #9c9179
}

-- The inverted bar of the editor (rung 2b): the dim green becomes the
-- background and the screen colour becomes the text. Named here so that rung
-- does not invent a second palette.
CeroSec.COLORS.barBack = CeroSec.COLORS.dim
CeroSec.COLORS.barText = CeroSec.COLORS.screen

-- Scanlines: a one pixel line every SCANLINE_STEP pixels, so a 20 row screen
-- costs about a hundred rects and not one per pixel.
CeroSec.UI_SCANLINES = true
CeroSec.SCANLINE_STEP = 3
CeroSec.SCANLINE_ALPHA = 0.22

-- Glow: each line of text is drawn twice, once faint and one pixel off.
CeroSec.UI_GLOW = true
CeroSec.GLOW_ALPHA = 0.35
CeroSec.GLOW_OFFSET = 1

-- The block cursor blinks on this period, in milliseconds of real time.
CeroSec.CURSOR_BLINK_MS = 500

-- How much the terminal remembers. The scrollback is not one of these any
-- more: it is the machine's console (CONSOLE_MAX above), which the window only
-- renders. The input history is the one thing that stays in the window, because
-- it is what this player typed and not what the screen shows.
CeroSec.HISTORY_MAX = 20

-- Module of the server -> client answers that go to one player, i.e. the module
-- of sendServerCommand(player, ...). Named here because both sides need the
-- same string and neither side owns it.
CeroSec.MODULE = "CeroSec"
