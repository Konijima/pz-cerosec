--
-- Write the self-test's vector table, from the CANONICAL VM.
--
--   lua5.1 tools/make-selftest-vectors.lua [output path]
--
-- The vectors are what CeroSecSelfTest.run() weighs the game's own Kahlua
-- against, so they have to come from somewhere that is right by definition:
-- lua5.1, which is what every bench in tests/ runs on and what the engine is
-- written to. This runs CeroSecSelfTest.vectors under it and writes down every
-- answer.
--
-- IT IS GENERATED AND IS NOT TO BE EDITED. tests/run.sh regenerates it into a
-- temporary file and fails on a diff, so a hand-edited table -- or a body somebody
-- added a line to without coming back here -- is a red suite and not a silent
-- drift. The file is committed rather than built at load time because the game
-- has no lua5.1 in it: what ships has to be the answers, not the means of getting
-- them.
--
-- Run from the repo root.
--

local LUA = "42/media/lua/"
local FILES = {
	"shared/CeroSec/CeroSecDefs.lua",
	"shared/CeroSec/CeroSecContent.lua",
	"shared/CeroSec/CeroSecSelfTest.lua",
	"shared/CeroSec/OS/CeroSecOS.lua",
	"shared/CeroSec/OS/CeroSecOSComplete.lua",
	"shared/CeroSec/OS/CeroSecOSCron.lua",
	"shared/CeroSec/OS/CeroSecOSDev.lua",
	"shared/CeroSec/OS/CeroSecOSDisk.lua",
	"shared/CeroSec/OS/CeroSecOSFS.lua",
	"shared/CeroSec/OS/CeroSecOSNet.lua",
	"shared/CeroSec/OS/CeroSecOSPath.lua",
	"shared/CeroSec/OS/CeroSecOSRadio.lua",
	"shared/CeroSec/OS/CeroSecOSScript.lua",
	"shared/CeroSec/OS/CeroSecOSShell.lua",
	"shared/CeroSec/OS/CeroSecOSState.lua",
	"shared/CeroSec/OS/CeroSecOSSystem.lua",
	"shared/CeroSec/OS/CeroSecOSUsers.lua",
	"shared/CeroSec/OS/CeroSecOSVM.lua",
}
for i = 1, #FILES do
	local path = LUA .. FILES[i]
	local chunk, err = loadfile(path)
	if not chunk then error("cannot load " .. path .. ": " .. tostring(err)) end
	chunk()
end

local OUT = arg[1] or (LUA .. "shared/CeroSec/CeroSecSelfTestVectors.lua")

-- A Lua string literal for a value that is already text. Every vector is a
-- string, because say() tostring()s in the VM under it -- number formatting being
-- one of the things compared -- so this quotes and never guesses at a type.
local function quote(s)
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, '"', '\\"')
	s = string.gsub(s, "\n", "\\n")
	s = string.gsub(s, "\r", "\\r")
	s = string.gsub(s, "\t", "\\t")
	-- Anything else outside printable ASCII goes out as a decimal escape: a
	-- generated file with a raw byte 7 in it is a file nothing can diff.
	s = string.gsub(s, "[^ -~]", function(c)
		return "\\" .. string.format("%03d", string.byte(c))
	end)
	return '"' .. s .. '"'
end

local rows, names = {}, {}
CeroSecSelfTest.vectors(function(name, value)
	if type(name) ~= "string" or name == "" then
		error("a vector with no name: " .. tostring(name))
	end
	if names[name] then error("two vectors called " .. name) end
	names[name] = true
	rows[#rows + 1] = { name = name, want = tostring(value) }
end)
if #rows == 0 then error("the body evaluated nothing at all") end

local out = {}
local function line(text) out[#out + 1] = text end

line("--")
line("-- GENERATED -- do not edit.")
line("--")
line("--   lua5.1 tools/make-selftest-vectors.lua")
line("--")
line("-- Every answer CeroSecSelfTest.vectors gives on lua5.1, which is the")
line("-- canonical VM: what the engine is written to and what every bench in")
line("-- tests/ runs on. CeroSecSelfTest.run() evaluates the same body on")
line("-- whatever VM it finds itself on -- the game's Kahlua, in a real save --")
line("-- and every line that differs is a line the game gets wrong.")
line("--")
line("-- tests/run.sh regenerates this into a temporary file and fails on a")
line("-- diff, so a body with a line added or taken out is a red suite.")
line("--")
line("")
line("CeroSecSelfTest = CeroSecSelfTest or {}")
line("")
line("CeroSecSelfTest.VECTORS = {")
for i = 1, #rows do
	line("\t{ name = " .. quote(rows[i].name) .. ", want = " .. quote(rows[i].want) .. " },")
end
line("}")
line("")

local file, err = io.open(OUT, "wb")
if file == nil then error("cannot write " .. OUT .. ": " .. tostring(err)) end
file:write(table.concat(out, "\n"))
file:close()
print("make-selftest-vectors: " .. #rows .. " vectors -> " .. OUT)
