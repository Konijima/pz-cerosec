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

-- TESTING AID. SET TO false BEFORE THE WORKSHOP RELEASE.
--
-- With this on, every computer -- on or off -- carries a last entry on its
-- right-click menu that opens the manual there and then, with no copy of the
-- book anywhere. It exists so the reader can be worked on without first going
-- shopping for the item, and it is a door into a piece of documentation that a
-- player is supposed to FIND. Off, nothing is added and the only way to the
-- book is the book.
--
-- It is deliberately a plain constant in the shared defs and not a sandbox
-- option: an option is something a server owner can turn on, and this is not
-- for them. It is read by CeroSecContextMenu and by nothing else.
CeroSec.DEV_MANUAL_MENU = true

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

-- The middle of a square, in the float coordinates a character stands on. A
-- square's integer coordinates are its north-west corner: the character walking
-- onto it can be anywhere inside the unit that follows, and where inside it he
-- stops decides which seat the game picks for him (see CeroSecReach). So a walk
-- that means "stand at this computer" aims here and not at the square.
function CeroSec.squareCentre(x, y)
	return x + 0.5, y + 0.5
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

-- The home directory shortened to "~", the way every shell since 1989 does it.
-- Only the whole directory or something under it: /home/adminx is not inside
-- /home/admin and is left alone.
function CeroSec.shortenPath(cwd, home)
	cwd = tostring(cwd)
	if type(home) ~= "string" or home == "" or home == "/" then return cwd end
	if cwd == home then return "~" end
	if string.sub(cwd, 1, #home + 1) == home .. "/" then
		return "~" .. string.sub(cwd, #home + 1)
	end
	return cwd
end

-- What is still too long after that is cut at the FRONT and marked with "...".
-- Not with "~": a tilde in the middle of a path is what made
-- "admin@ksp-4rw-44z:~ome/admin$" look like a broken home shortening, because
-- that is exactly what it looked like -- it was a tail cut wearing the wrong
-- marker.
function CeroSec.prompt(user, hostname, cwd, admin, home)
	local head = tostring(user) .. "@" .. tostring(hostname) .. ":"
	local tail = admin and "# " or "$ "
	-- A name and a host long enough to eat the whole line take the cut
	-- themselves, so PROMPT_MAX is a ceiling and not a suggestion. There is no
	-- useradd yet and a hostname is at most sixteen characters, so nothing
	-- reaches this today; it is here so that the day something does, the line
	-- does not quietly grow past the screen.
	if #head + #tail + 1 > CeroSec.PROMPT_MAX then
		head = CeroSec.truncate(head, CeroSec.PROMPT_MAX - #tail - 1)
	end
	local room = CeroSec.PROMPT_MAX - #head - #tail
	if room < 1 then room = 1 end
	local path = CeroSec.shortenPath(cwd, home)
	if #path > room then
		if room <= 3 then
			path = string.sub("...", 1, room)
		else
			path = "..." .. string.sub(path, #path - room + 4)
		end
	end
	return head .. path .. tail
end

--
-- Strings
--
-- The same two helpers the core has (CeroSecOS.truncate, CeroSecOS.padRight),
-- named again here because the terminal never loads the core. os_test pins the
-- two pairs against each other so they cannot drift.
--

function CeroSec.truncate(s, width)
	if #s <= width then return s end
	if width <= 1 then return string.sub("~", 1, width) end
	return string.sub(s, 1, width - 1) .. "~"
end

function CeroSec.padRight(s, width)
	if #s >= width then return s end
	return s .. string.rep(" ", width - #s)
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

--
-- The scheduler's numbers
--
-- What a running script may cost the server. They are here, beside the console
-- and away from the engine, because they are about THIS GAME and not about the
-- language: the engine is handed a budget and honours it, and these four
-- numbers are what a Project Zomboid server can afford to hand it.
--
-- One pass is worth STEP_BUDGET_PER_TICK steps, shared round-robin across every
-- machine with a job on it, and no one machine takes more than
-- STEP_BUDGET_PER_MACHINE of them. A builtin costs one step and a command in
-- /bin costs CeroSecOS.STEP_COST_COMMAND of them, so a step is worth about six
-- microseconds of Lua whatever a script is made of -- which is what makes these
-- two numbers milliseconds and not guesses.
--
-- At ten passes a second: a thousand builtins a second for any one computer,
-- two thousand for the whole county, and sixty commands out of /bin. A pass
-- costs about one and a quarter milliseconds of Lua at its very busiest --
-- every machine spinning on arithmetic -- against a sixty-frames-a-second
-- budget of sixteen. Measured headless under lua5.1 by tests/hostile_test.lua,
-- which prints the numbers every run and fails if a pass goes past its ceiling.
--
-- Nothing here was measured in the GAME, and the game's Lua is not this one:
-- Kahlua is an interpreter written in Java and is expected to be several times
-- slower than lua5.1, which is why the county's budget is a fifth of what the
-- measurement alone would allow. A number moved after a real server has been
-- watched is a number moved with a measurement beside it.
CeroSec.STEP_BUDGET_PER_TICK = 200
CeroSec.STEP_BUDGET_PER_MACHINE = 100

-- How often the scheduler runs, in milliseconds. Ten passes a second, on
-- Events.OnTick gated by getTimestampMs -- vanilla's own way of getting under a
-- minute on a server.
CeroSec.JOB_PASS_MS = 100

-- Lines one machine may put on its screen in a second. Beyond it a job is
-- paused until the window comes round, so `while true; do echo x; done` is a
-- slow trickle and never a flood -- neither of the network nor of the hundred
-- lines the screen keeps.
CeroSec.JOB_OUT_PER_SEC = 20

-- How long a job may hold the processor with no wait in it before the machine
-- takes it away, in seconds of wall clock. A sandbox option would be the
-- natural home for this one day; today it is a constant, on purpose -- a server
-- owner who wants a different number should be given a setting and not asked to
-- edit a file.
CeroSec.JOB_CPU_LIMIT_S = 300

-- How long a motion sensor holds its contact closed after the last movement it
-- saw, in seconds of wall clock. Five, and it is the mod's own number and not
-- the game's: a PIR head of 1993 is a relay with an RC network across it, and
-- what it sells is a contact that STAYS closed a few seconds after the room goes
-- still, so a machine polling it every five seconds cannot miss somebody walking
-- through. Two consequences, both in the manual: a body that stops moving reads
-- `clear` five seconds later, and a `cat` a minute after the fact reads `clear`
-- too -- a sensor says what is happening, never what happened.
--
-- Named here rather than in the server file because the manual quotes it and the
-- manual is shared.
CeroSec.SENSOR_HOLD_S = 5

-- How far a motion sensor sees, in tiles, measured the way the game measures it
-- (see the head of SCeroSecSensors.lua: squared euclidean from the centre of the
-- head's own tile, one floor).
--
-- Three, and it is the game's own number for this module rather than ours. The
-- device is the bare Base.MotionSensor (media/scripts/generated/items/normal.txt
-- :4539), which carries no SensorRange of its own -- it is a component. What the
-- game says the component is WORTH is in the recipes: one Base.MotionSensor plus
-- two Base.ElectronicsScrap makes a V1 sensor
-- (media/scripts/generated/recipes/recipes_traps.txt:153-181), and every V1 in
-- the game is SensorRange = 3 -- all five of them, without exception
-- (media/scripts/generated/items/weapon.txt:306, 487, 662, 838, 1027). The extra
-- scrap is what buys a V2 or a V3, so three is the reach the module brings by
-- itself and the smallest the game ever grants a motion sensor.
--
-- Named here rather than in the server file because the manual quotes it.
CeroSec.SENSOR_RANGE = 3

-- How deep the su stack a console carries may go. The same number the core
-- enforces (CeroSecOS.SU_MAX), named again here because the terminal never
-- loads the core -- os_test pins the two against each other so they cannot
-- drift, exactly as it does for truncate and padRight.
CeroSec.SU_MAX = 4

-- The firmware's own version, and the only place it is written down. The BIOS
-- is a separate component from the operating system, so it carries a separate
-- number: the two happen to be aligned today, and a new firmware moves this one
-- alone and never CeroSecOS.VERSION.
CeroSec.BIOS_VERSION = "1.0"

-- The BIOS. Written by the server into the console the first time somebody
-- opens a machine that has just been switched on, so that it is on the screen
-- exactly once per power-on -- and so that the second player to open the same
-- computer sees the same lines the first one saw, instead of a second boot.
CeroSec.BOOT_LINES = {
	"CeroSec BIOS " .. CeroSec.BIOS_VERSION .. " -- (c) 1993 CeroSec Systems",
	"Memory test: 640K OK",
	-- The capacity is NOT written here: it is the engine's ceiling and it is
	-- appended at power-on by bootLines(). A BIOS that announces a drive the
	-- machine does not have is a BIOS lying to the player about the one number
	-- he will run into -- `df` and a full disk say 32K, so this says 32K.
	"Detecting drives ... hda ",
	"Booting from hda ...",
	"",
}

-- Which of those lines carries the capacity.
CeroSec.BOOT_DISK_LINE = 3

-- And what the card is called when the firmware finds one. The address is NOT
-- written here and could not be: it is a fact about which building the computer
-- stands in, and the BIOS is handed it (see CeroSec.bootLines).
CeroSec.BOOT_ETHER = "Ethernet: " .. "eth0 "

-- The BIOS as it goes onto a screen: the lines above with the real disk on the
-- drive line, and the card under it when the machine has an address. A copy every
-- time, so nothing ever writes into the template.
--
-- A machine with no address prints no Ethernet line at all -- one in a
-- player-built base has no wire to be on -- rather than a line with nothing after
-- the colon, which would be a BIOS announcing hardware the machine has not got.
function CeroSec.bootLines(addr)
	local out = {}
	for i = 1, #CeroSec.BOOT_LINES do out[i] = CeroSec.BOOT_LINES[i] end
	out[CeroSec.BOOT_DISK_LINE] = out[CeroSec.BOOT_DISK_LINE] .. CeroSecOS.diskLabel()
	if type(addr) == "string" and addr ~= "" then
		table.insert(out, CeroSec.BOOT_DISK_LINE + 1, CeroSec.BOOT_ETHER .. addr)
	end
	return out
end

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
	-- The note of a foreground job. The job itself is the scheduler's and is
	-- killed with the machine, never by a logout -- this is only the console's
	-- memory of whose prompt it is.
	console.job = nil
	console.status = nil
	-- The shell's variables go with the session that set them. Somebody else
	-- walking up to a logged-out machine gets a shell, not the last one's.
	console.shvars = nil
	-- Who the glass would have come back to through su, with it: an account
	-- logs out of the machine and not out of its own last switch.
	console.stack = nil
	-- A half-answered prompt and an open buffer belong to the session that
	-- started them: neither survives the logout, and the unsaved buffer is lost
	-- exactly as it would be on a real machine.
	console.prompt = nil
	console.edit = nil
	console.halted = nil
	console.lines = {}
	return console
end

-- What the console is waiting for, in full: the four things the server has to
-- tell apart. "login" and "password" are the machine's own two built-in
-- prompts; "prompt" is one a command asked for (passwd), and they are answered
-- through one and the same client command.
function CeroSec.consoleWaiting(console)
	if type(console) ~= "table" then return "login" end
	-- A machine whose BIOS found nothing to boot and was told not to repair it.
	-- Nothing of the OS is reachable from there, so this comes first.
	if console.halted then return "halted" end
	if console.edit ~= nil then return "edit" end
	if console.prompt ~= nil then return "prompt" end
	-- A foreground job holds the prompt. It comes after "prompt" on purpose: a
	-- script that has asked something is a question first and a running job
	-- second, and the window has to draw the question.
	if console.job ~= nil then return "job" end
	if console.pending ~= nil then return "password" end
	if console.user == nil then return "login" end
	return "shell"
end

-- The same thing as the window has to be told it. A window types at a prompt or
-- it types a command or it is in the editor; which of the two prompts it is
-- typing at is the machine's business, and the mask flag is all that shows.
function CeroSec.consoleMode(console)
	local waiting = CeroSec.consoleWaiting(console)
	if waiting == "edit" then return "edit" end
	if waiting == "shell" then return "shell" end
	-- "job": the machine is busy with a script. The window draws no input line
	-- at all -- there is nothing to type at -- and Escape is a ^C.
	if waiting == "job" then return "job" end
	-- "halted" included: the window keeps the keyboard, because pressing a key
	-- at a halted machine is what brings the BIOS' question back.
	return "prompt"
end

-- Whether the machine is sitting on "No operating system found." with nothing
-- asked. The server's own flag, and the one thing the console holds that is not
-- about a session.
function CeroSec.consoleHalted(console)
	return type(console) == "table" and console.halted and true or false
end

-- Is the machine in the middle of something? This is what Escape asks before it
-- decides whether it is an interrupt or a close: a question a command put up
-- (passwd, sudo) and a login name half typed are things to give up on, and
-- everything else is a window to walk away from.
--
-- Three deliberate exclusions. The editor has its own Escape and always has.
-- The BIOS' question is not a session's and cannot be answered by giving up --
-- there is nothing behind it to come back to. A halted machine is asking
-- nothing at all.
function CeroSec.consoleActive(console)
	if type(console) ~= "table" then return false end
	if console.halted then return false end
	if console.edit ~= nil then return false end
	if console.prompt ~= nil then
		local cont = console.prompt.cont
		if type(cont) == "table" and cont.cmd == "bios" then return false end
		return true
	end
	-- A running script is the plainest thing there is to interrupt.
	if console.job ~= nil then return true end
	if console.pending ~= nil then return true end
	return false
end

-- The prompt that goes with it. Derived from the console and from nothing else,
-- so the server never has to remember what it last told a window.
function CeroSec.consolePrompt(console, hostname, admin, home)
	local waiting = CeroSec.consoleWaiting(console)
	if waiting == "edit" then return "" end
	if waiting == "halted" then return "" end
	-- Nothing under a running script: the line a player would type at is the
	-- job's, and the job is not listening.
	if waiting == "job" then return "" end
	if waiting == "prompt" then
		local text = console.prompt.text
		if type(text) ~= "string" then return "" end
		return text
	end
	if waiting == "password" then return "password: " end
	if waiting == "login" then return "login: " end
	return CeroSec.prompt(console.user, hostname, console.cwd or "/", admin, home)
end

-- Whether what is being typed at that prompt is to be shown as stars. The
-- window masks on this flag and on nothing it works out for itself, so a new
-- prompt that must not be echoed is one field and no client change.
function CeroSec.consoleMask(console)
	local waiting = CeroSec.consoleWaiting(console)
	if waiting == "password" then return true end
	if waiting == "prompt" then return console.prompt.mask and true or false end
	return false
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
	if console.halted then out.halted = true end
	if type(console.user) == "string" then out.user = console.user end
	if type(console.cwd) == "string" then out.cwd = console.cwd end
	if type(console.pending) == "string" then out.pending = console.pending end
	-- The shell's own variables, which are the machine's like everything else on
	-- the console: `x=5` typed at the glass is still set after a reload, because
	-- the prompt is an environment and not a series of unrelated commands. Kept
	-- entry by entry and bounded exactly as a job's are (CeroSecOS.MAX_VARS,
	-- MAX_VAR_BYTES), because a forged console must not be able to hand back a
	-- thousand of them.
	local shvars = console.shvars
	if type(shvars) == "table" then
		local kept, n = {}, 0
		for name, value in pairs(shvars) do
			if type(name) == "string" and type(value) == "string"
					and CeroSecOS.isVarName(name)
					and #value <= CeroSecOS.MAX_VAR_BYTES
					and not CeroSecOS.hasControlBytes(value)
					and n < CeroSecOS.MAX_VARS then
				kept[name] = value
				n = n + 1
			end
		end
		if n > 0 then out.shvars = kept end
	end
	-- $?, as the prompt last came back with it.
	if type(console.status) == "number" then out.status = math.floor(console.status) end
	-- When the account at the glass logged in, which is what `who` prints. Machine
	-- state like the account itself: a survivor who walked away and came back is
	-- still logged in since the minute he sat down.
	if type(console.loginAt) == "number" then out.loginAt = math.floor(console.loginAt) end
	-- The su stack: machine state like the user and the working directory, and
	-- saved with them. Kept entry by entry, only where an entry is still a name
	-- and a path, and never deeper than the ceiling -- a forged console must not
	-- be able to hand back a stack that takes ten exits to get out of.
	local stack = console.stack
	if type(stack) == "table" then
		local kept = {}
		for i = 1, #stack do
			local entry = stack[i]
			if type(entry) == "table" and type(entry.user) == "string"
					and #kept < CeroSec.SU_MAX then
				local cwd = "/"
				if type(entry.cwd) == "string" then cwd = entry.cwd end
				kept[#kept + 1] = { user = entry.user, cwd = cwd }
			end
		end
		if #kept > 0 then out.stack = kept end
	end
	-- A half-answered prompt is kept only when all three of its parts are still
	-- there. The token is the core's and is opaque here; a table is as far as
	-- this can check it, and CeroSecOS.continue refuses what is not one.
	--
	-- A question a JOB asked is the one exception, and it is dropped: jobs are
	-- runtime state and a reload has none, so a token naming one names nothing.
	-- This is also where console.job goes: it is not copied at all, so a
	-- machine that comes back from a save comes back at its prompt.
	local prompt = console.prompt
	if type(prompt) == "table" and type(prompt.text) == "string" and type(prompt.cont) == "table"
			and prompt.cont.cmd ~= "job" then
		out.prompt = { text = prompt.text, mask = prompt.mask and true or false, cont = prompt.cont }
	end
	-- An open buffer, likewise: a path and a text, or nothing at all.
	local edit = console.edit
	if type(edit) == "table" and type(edit.path) == "string" and type(edit.text) == "string" then
		out.edit = {
			path = edit.path,
			text = edit.text,
			readonly = edit.readonly and true or false,
		}
		if type(edit.by) == "string" then out.edit.by = edit.by end
		-- Who the buffer was opened as. A save runs under this and not under
		-- whoever is logged in, so `sudo edit` still writes as root -- and a
		-- console handed back without it falls back to the session, which is
		-- what every buffer opened before sudo existed was.
		if type(edit.user) == "string" then out.edit.user = edit.user end
		if type(edit.message) == "string" then out.edit.message = edit.message end
		if type(edit.saves) == "number" and edit.saves >= 0 then
			out.edit.saves = math.floor(edit.saves)
		end
	end
	if type(console.lines) == "table" then
		local lines = console.lines
		for i = 1, #lines do
			if type(lines[i]) == "string" then CeroSec.consolePush(out, lines[i]) end
		end
	end
	return out
end

--
-- The input line
--
-- A terminal does not stop taking characters at the right edge of the glass: it
-- wraps onto the next row and keeps going. So the line the player is typing is
-- laid out here -- prompt, text, and where the block cursor is -- and the window
-- draws the rows it is handed.
--
-- Like the editor's buffer, the visible line is drawn by the window and not by
-- the text box, which has no way to wrap one line across rows. The box is off
-- the glass, taking the keyboard and holding the characters, and getCursorPos
-- gives the absolute index the cursor sits at.
--

-- Four rows of sixty. Past that the machine stops taking characters, the way a
-- real one runs out of line buffer.
CeroSec.INPUT_ROWS = 4
CeroSec.INPUT_MAX = 240

-- rows, cursor row (1-based within rows), cursor column (0-based). The prompt
-- occupies the head of the first row and is never typed over.
function CeroSec.inputRows(prompt, text, offset)
	prompt = tostring(prompt or "")
	text = tostring(text or "")
	local cols = CeroSec.COLS
	-- A prompt wider than the screen would leave nowhere to type; it is cut so
	-- there is always at least one column left.
	local head = #prompt
	if head > cols - 1 then
		head = cols - 1
		prompt = string.sub(prompt, 1, head)
	end

	local first = cols - head
	local rows = { prompt .. string.sub(text, 1, first) }
	local i = first + 1
	while i <= #text do
		rows[#rows + 1] = string.sub(text, i, i + cols - 1)
		i = i + cols
	end

	if type(offset) ~= "number" then offset = #text end
	if offset < 0 then offset = 0 end
	if offset > #text then offset = #text end

	local row, col
	if offset < first then
		row, col = 1, head + offset
	else
		local rest = offset - first
		row = 2 + math.floor(rest / cols)
		col = rest % cols
	end
	-- The cursor can sit one past the last character, which is one row past the
	-- last row when the text ends exactly on a row boundary.
	while #rows < row do rows[#rows + 1] = "" end
	return rows, row, col
end

-- Where the block cursor is on a drawn row, and what character it covers.
--
-- The two halves of the blink have to agree on one column: the block that is
-- painted and the character repainted under it are the same cell, so both are
-- worked out here, once, and the window uses the one answer for both halves.
--
-- x is how far the pen has moved over everything in front of the cursor -- the
-- prompt and the text up to the cursor, over the very string that was painted
-- -- and not a count of cells, because a cell is one measurement taken at one
-- moment.
--
-- `measure` is the pen's ADVANCE over a string, which is not the same thing as
-- the font's answer for it: MeasureStringX counts the last glyph of a string by
-- its ink and not by its advance, so it is short by a character-dependent
-- pixel or three and is never handed in here directly. The window hands in a
-- helper built out of it (`advance` in CeroSecTerminal.lua, and the comment on
-- CELL_W there for the whole of it); the bench hands in a fixed width per
-- character, which is what a monospaced advance is.
--
-- The third answer is the WIDTH of the block: the advance of the character it
-- covers, or of a space where there is none to cover. It is asked for here so
-- that the block and the glyph repainted on it are the one cell -- a block
-- drawn at some cell width measured elsewhere overlaps the glyph beside it the
-- moment the two disagree. nil when there is no `measure` to ask.
--
-- cursorIndex is an index into `text`: 0 in front of the first character,
-- #text right after the last one, where the cursor covers nothing and the
-- glyph comes back nil. Out of range is clamped, never an error -- a box that
-- answers one past the end must not push the block a column past the line.
function CeroSec.cursorSpan(prompt, text, cursorIndex, measure)
	prompt = tostring(prompt or "")
	text = tostring(text or "")
	if type(cursorIndex) ~= "number" then cursorIndex = #text end
	if cursorIndex < 0 then cursorIndex = 0 end
	if cursorIndex > #text then cursorIndex = #text end

	local front = prompt .. string.sub(text, 1, cursorIndex)
	local x = 0
	if front ~= "" and measure then x = measure(front) or 0 end

	local under = string.sub(text, cursorIndex + 1, cursorIndex + 1)
	if under == "" then under = nil end

	local width = nil
	if measure then width = measure(under or " ") end
	return x, under, width
end

--
-- The editor
--
-- edit <file> puts the same 60 x 20 glass into a second shape: an inverted bar
-- naming the file, seventeen rows of the buffer, an inverted bar of keys, and
-- one line for what the machine has to say. Everything below is pure list and
-- string work -- the composition of that screen, where it scrolls to, and where
-- the cursor is -- so it lives here and is tested headless.
--
-- The keys are Escape and Tab and nothing else, because those are the only two
-- the game hands a text box that has the keyboard (Core.updateKeyboardAux):
-- Ctrl+O and Ctrl+X, which is what nano would use, never arrive.
--

-- Seventeen rows of text between the two bars, and one message line under them.
CeroSec.EDIT_ROWS = 17

-- A line is a screen line: the editor wraps nothing, so it refuses the 61st
-- character rather than fold it. The buffer ceiling is the file ceiling
-- (CeroSecOS.MAX_FILE_BYTES); os_test pins the two together.
CeroSec.EDIT_MAX_LINE = 60
CeroSec.EDIT_MAX_BYTES = 4096

-- What the vanilla text box lets a player *type* into it before it stops
-- taking characters: UITextBox2.textEntryMaxLength, 2000 in the constructor,
-- read by isTextLimit() which gates putCharacter, and with no setter and no
-- constructor argument. Enter, paste and a file loaded from disk are not gated
-- by it, so a bigger file still opens, still shows and still saves; it is only
-- the typing that stops. Named here so the message line can say so.
CeroSec.EDIT_TYPED_MAX = 2000

-- How often an unsaved buffer is pushed to the machine while it is being
-- typed, so that the screen stays the machine's and walking away keeps the
-- work. Only when it has changed, and never more often than this.
CeroSec.EDIT_SYNC_MS = 5000

-- The buffer as rows. Unlike the core's splitLines, an empty buffer is one
-- empty line and not none: a cursor has to sit somewhere.
function CeroSec.editLines(text)
	local out = {}
	if type(text) ~= "string" then text = "" end
	local start = 1
	while true do
		local p = string.find(text, "\n", start, true)
		if p == nil then
			out[#out + 1] = string.sub(text, start)
			return out
		end
		out[#out + 1] = string.sub(text, start, p - 1)
		start = p + 1
	end
end

-- Where an offset into the buffer is on that grid: the row, 1-based, and the
-- column, 0-based (0 is in front of the first character). The offset is what
-- UITextBox2.getCursorPos answers -- an absolute index into the text, which is
-- what putCharacter, onKeyLeft and onKeyRight all treat it as.
function CeroSec.editCursor(text, offset)
	if type(text) ~= "string" then text = "" end
	if type(offset) ~= "number" then offset = 0 end
	if offset < 0 then offset = 0 end
	if offset > #text then offset = #text end
	-- An offset is a gap, not a character: offset 0 is in front of the first
	-- character and offset p, where p is the index of a newline, is in front of
	-- the first character of the next row.
	local row, start = 1, 1
	while true do
		local p = string.find(text, "\n", start, true)
		if p == nil or offset < p then return row, offset - start + 1 end
		row = row + 1
		start = p + 1
	end
end

-- The first row shown, so the cursor row is always one of the seventeen. Given
-- the row it was on, so a screen that need not move does not move.
function CeroSec.editTop(top, row, count, rows)
	if type(top) ~= "number" or top < 1 then top = 1 end
	if count < 1 then count = 1 end
	local most = count - rows + 1
	if most < 1 then most = 1 end
	if top > most then top = most end
	if row < top then top = row end
	if row > top + rows - 1 then top = row - rows + 1 end
	if top > most then top = most end
	if top < 1 then top = 1 end
	return top
end

-- The top bar: what is being edited, and the one thing worth knowing about it.
-- The flag is "modified", "read-only" or nothing, and it is pinned to the right
-- so the eye finds it in the same place every time.
function CeroSec.editTitle(path, flag)
	local tail = ""
	if type(flag) == "string" and flag ~= "" then tail = "[" .. flag .. "] " end
	local room = CeroSec.COLS - #tail
	if room < 1 then room = 1 end
	local head = " EDIT  " .. tostring(path)
	return CeroSec.padRight(CeroSec.truncate(head, room), room) .. tail
end

-- The bottom bar. Two keys, because there are two keys.
function CeroSec.editKeys()
	return CeroSec.padRight(" Esc exit   Tab save ", CeroSec.COLS)
end

-- The message line: whatever the machine last had to say, cut to the screen and
-- stripped the way any other stored line is.
function CeroSec.editMessage(text)
	if type(text) ~= "string" then return "" end
	return CeroSec.consoleLine(text)
end

-- The whole screen, as twenty rows plus what the window has to draw
-- differently. rows 1 and 19 are the inverted bars, 2..18 the buffer, 20 the
-- message. A row of the buffer that is not there is drawn empty, the way a
-- terminal editor leaves the bottom of a short file blank.
function CeroSec.editScreen(text, top, path, flag, message)
	local lines = CeroSec.editLines(text)
	local out = { CeroSec.editTitle(path, flag) }
	for i = 0, CeroSec.EDIT_ROWS - 1 do
		local line = lines[top + i]
		if line == nil then line = "" end
		out[#out + 1] = CeroSec.truncate(line, CeroSec.COLS)
	end
	out[#out + 1] = CeroSec.editKeys()
	out[#out + 1] = CeroSec.editMessage(message)
	return out
end

-- How far this text is from being something the editor may hold: bytes over the
-- ceiling, plus characters over the width on every row that is too wide. Zero
-- means it is fine.
--
-- This exists because "refuse anything that breaks a rule" is a trap. The shell
-- can put a 70 character line in a file (writeFile has no width rule -- the
-- width is the screen's, not the filesystem's), and an editor that undoes every
-- keystroke on such a buffer undoes the BACKSPACES too: the file becomes
-- impossible to fix from the editor that opened it. So a keystroke is refused
-- only when it does not make things better, and deleting always does.
function CeroSec.editBadness(text)
	if type(text) ~= "string" then return CeroSec.EDIT_MAX_BYTES * 2 end
	local badness = 0
	if #text > CeroSec.EDIT_MAX_BYTES then badness = #text - CeroSec.EDIT_MAX_BYTES end
	local lines = CeroSec.editLines(text)
	for i = 1, #lines do
		if #lines[i] > CeroSec.EDIT_MAX_LINE then
			badness = badness + #lines[i] - CeroSec.EDIT_MAX_LINE
		end
	end
	for i = 1, #text do
		local b = string.byte(text, i)
		if b < 32 and b ~= 10 and b ~= 9 then badness = badness + 1 end
	end
	return badness
end

-- Is this text something the editor may hold? The two ceilings and the
-- printable rule, in the terminal's own words, so a refusal happens under the
-- fingers and not four seconds later at the save. Returns nil plus the line to
-- show when it is not.
function CeroSec.editRefusal(text)
	if type(text) ~= "string" then return "Cannot edit: not text" end
	if #text > CeroSec.EDIT_MAX_BYTES then
		return "Buffer full: " .. CeroSec.EDIT_MAX_BYTES .. " bytes"
	end
	local lines = CeroSec.editLines(text)
	for i = 1, #lines do
		if #lines[i] > CeroSec.EDIT_MAX_LINE then
			return "Line too long: " .. CeroSec.EDIT_MAX_LINE .. " characters"
		end
	end
	for i = 1, #text do
		local b = string.byte(text, i)
		if b < 32 and b ~= 10 and b ~= 9 then return "Cannot edit: invalid characters" end
	end
	return nil
end

-- What Escape and Tab do, and what answers the save question. One table, so
-- the window looks up a key instead of deciding, and the decisions are tested
-- without a game. state is "edit" or "ask".
function CeroSec.editKeyAction(state, key, modified, readonly)
	if state == "ask" then
		if key == "y" or key == "Y" then
			if readonly then return "leave" end
			return "saveleave"
		end
		if key == "n" or key == "N" then return "leave" end
		if key == "escape" then return "cancel" end
		return "again"
	end
	if key == "escape" then
		if modified and not readonly then return "ask" end
		return "leave"
	end
	if key == "tab" then
		if readonly then return "readonly" end
		return "save"
	end
	return nil
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

-- How much the terminal remembers. Nothing, in the end: the scrollback is the
-- machine's console (CONSOLE_MAX above) and the input history is the account's
-- own ~/.sh_history on the machine's disk, which the server hands over when a
-- window opens and whenever the account at the glass changes. This is the size
-- of the window's copy of that tail -- the same number the server sends
-- (CeroSecOS.HISTORY_TAIL), because the copy is the tail and not a second
-- history beside it.
CeroSec.HISTORY_MAX = 100

-- Module of the server -> client answers that go to one player, i.e. the module
-- of sendServerCommand(player, ...). Named here because both sides need the
-- same string and neither side owns it.
CeroSec.MODULE = "CeroSec"
