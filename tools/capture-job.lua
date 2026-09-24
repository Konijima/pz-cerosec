--
-- Capture a job fixture: two scripts stopped MID-COMMAND, as a build's own
-- scheduler would save them (CeroSecJobs.jobToData), with the machine they
-- were running on, serialized as a Lua table literal.
--
--   git archive v0.6.1 42/media/lua | tar -x -C <dir>
--   lua5.1 tools/capture-job.lua --root <dir> --out tests/fixtures/jobs-0.6.1.lua
--
-- The same reason as tools/capture-fixture.lua: a job an older build saved
-- can only be photographed by running that build, and tests/jobs_compat_test.lua
-- loads the photograph into this one. Not part of the mod; lua5.1 only.
--
-- The two, and what each is there to break:
--
--   loop.sh   a for loop writing with `>` and `>>` on every pass, saved
--             asleep on its second -- mid-loop, the files half written.
--             (0.6.1 had no redirect on a whole `done`, so the redirects
--             are on the commands inside it.)
--   pipe.sh   the same loop piped through tr into a file, saved while the
--             first stage sleeps -- a pipeline in flight, stages and pipes
--

local function argValue(name, fallback)
	for i = 1, #arg - 1 do
		if arg[i] == name then return arg[i + 1] end
	end
	return fallback
end
local ROOT = argValue("--root", ".")
local OUT = argValue("--out", nil)

-- What the server files need to load outside the game, and nothing more.
_G.require = function() end
_G.isClient = function() return false end
_G.isServer = function() return true end
_G.Events = setmetatable({}, { __index = function(t, k)
	local v = { Add = function() end, Remove = function() end }
	rawset(t, k, v)
	return v
end })

local LUA = ROOT .. "/42/media/lua/"
local FILES = { "shared/CeroSec/CeroSecDefs.lua" }
for _, name in ipairs({ "CeroSecOS", "CeroSecOSComplete", "CeroSecOSCron", "CeroSecOSDev",
		"CeroSecOSDisk", "CeroSecOSFS", "CeroSecOSNet", "CeroSecOSPath", "CeroSecOSRadio",
		"CeroSecOSScript", "CeroSecOSShell", "CeroSecOSState", "CeroSecOSSystem",
		"CeroSecOSUsers", "CeroSecOSVM" }) do
	FILES[#FILES + 1] = "shared/CeroSec/OS/" .. name .. ".lua"
end
FILES[#FILES + 1] = "server/CeroSec/SCeroSecJobs.lua"
for i = 1, #FILES do
	local chunk, err = loadfile(LUA .. FILES[i])
	if not chunk then error("cannot load " .. FILES[i] .. ": " .. tostring(err)) end
	chunk()
end

local SCRIPTS = {
	loop = "echo start > /home/admin/out.txt\nfor i in 1 2 3; do\n"
		.. "  echo line $i > /home/admin/last.txt\n  echo line $i >> /home/admin/out.txt\n"
		.. "  sleep 1\ndone\necho after $?\n",
	pipe = "for w in one two three; do\n  echo $w\n  sleep 1\ndone | tr a-z A-Z"
		.. " > /home/admin/up.txt\necho piped $?\n",
}

local state = CeroSecOS.newState("ksp-front-01")
local session = CeroSecOS.login(state, "admin", "")
if session == nil then error("cannot log in as admin") end
for name, text in pairs(SCRIPTS) do
	local done, why = CeroSecOS.writeFile(state, session, "/home/admin/" .. name .. ".sh",
		text, false, nil)
	if done == nil then error("cannot write " .. name .. ".sh: " .. tostring(why)) end
end

local env = { now = 725846400, nowMs = 1000, jobs = {} }
local saved, printed = {}, {}
local ids = { loop = 1, pipe = 2 }
for _, name in ipairs({ "loop", "pipe" }) do
	local path = "/home/admin/" .. name .. ".sh"
	local ok, lines, control, data = CeroSecOS.startScript(state, session, "sh", path, {},
		"sh " .. path, env, false)
	if control ~= "job" then error(name .. ": no job: " .. tostring(lines and lines[1])) end
	local job = CeroSecOS.newJob({ id = ids[name], prog = data.prog, args = data.args,
		name = data.name, cmd = data.cmd, session = session, bg = true })
	env.jobs[#env.jobs + 1] = job
	-- Fifteen passes of 100 ms: half way through the second `sleep 1`, which
	-- is mid-loop for both. (A job that wakes and sleeps again in one step is
	-- "sleeping" throughout, so the pass count is the clock to go by.)
	local out = {}
	for pass = 1, 15 do
		env.nowMs = env.nowMs + 100
		CeroSecOS.jobStep(state, job, env, 100)
		for i = 1, #job.out do out[#out + 1] = job.out[i] end
		job.out = {}
		if CeroSecOS.jobIsOver(job) then error(name .. " finished before it was saved") end
	end
	if job.state ~= "sleeping" then error(name .. " is not asleep: " .. tostring(job.state)) end
	local packed, why = CeroSecJobs.jobToData(job, env.nowMs, false)
	if packed == nil then error(name .. ": the build would not save it: " .. tostring(why)) end
	saved[name] = packed
	printed[name] = out
end

--
-- The serializer is tools/capture-fixture.lua's, byte for byte in behaviour.
--
local function quote(s)
	local out = string.gsub(s, "\\", "\\\\")
	out = string.gsub(out, '"', '\\"')
	out = string.gsub(out, "\n", "\\n")
	out = string.gsub(out, "\r", "\\r")
	out = string.gsub(out, "\t", "\\t")
	return '"' .. out .. '"'
end
local RESERVED = {}
for word in string.gmatch("and break do else elseif end false for function if in local "
		.. "nil not or repeat return then true until while", "%a+") do
	RESERVED[word] = true
end
local function keyText(k)
	if type(k) == "number" then return "[" .. tostring(k) .. "]" end
	if not RESERVED[k] and string.find(k, "^[A-Za-z_][A-Za-z0-9_]*$") then return k end
	return "[" .. quote(k) .. "]"
end
local function sortedKeys(t)
	local nums, strs = {}, {}
	for k in pairs(t) do
		if type(k) == "number" then nums[#nums + 1] = k
		elseif type(k) == "string" then strs[#strs + 1] = k
		else error("a key of type " .. type(k) .. " is not something a save can hold") end
	end
	table.sort(nums)
	table.sort(strs)
	local out = {}
	for i = 1, #nums do out[#out + 1] = nums[i] end
	for i = 1, #strs do out[#out + 1] = strs[i] end
	return out
end
local write
write = function(value, indent, parts)
	local t = type(value)
	if t == "string" then parts[#parts + 1] = quote(value) return end
	if t == "number" then
		if value == math.floor(value) then
			parts[#parts + 1] = string.format("%d", value)
		else
			parts[#parts + 1] = string.format("%.17g", value)
		end
		return
	end
	if t == "boolean" then parts[#parts + 1] = tostring(value) return end
	if t ~= "table" then error(t .. " is not something a save can hold") end
	local keys = sortedKeys(value)
	if #keys == 0 then parts[#parts + 1] = "{}" return end
	parts[#parts + 1] = "{\n"
	local inner = indent .. "\t"
	for i = 1, #keys do
		parts[#parts + 1] = inner .. keyText(keys[i]) .. " = "
		write(value[keys[i]], inner, parts)
		parts[#parts + 1] = ",\n"
	end
	parts[#parts + 1] = indent .. "}"
end

-- Into the state the way the build's own writeBook puts a book there:
-- { seq, list }, in the order the jobs were started. That is where a save
-- keeps them, so migrate and validate meet them before any job is read.
state.jobs = { seq = 2, list = { saved.loop, saved.pipe } }

local fixture = {
	v = state.v,
	sysv = state.sysv,
	nowMs = env.nowMs,
	scripts = SCRIPTS,
	printed = printed,
	order = { "loop", "pipe" },
	state = state,
}
local parts = {}
parts[#parts + 1] = "--\n"
parts[#parts + 1] = "-- Two jobs saved mid-command, photographed. STATE_VERSION " .. tostring(state.v)
parts[#parts + 1] = ", SYSTEM_VERSION " .. tostring(state.sysv) .. ".\n"
parts[#parts + 1] = "--\n"
parts[#parts + 1] = "-- Written by tools/capture-job.lua and never by hand: tests/jobs_compat_test.lua\n"
parts[#parts + 1] = "-- loads it into whatever the code is now. Do not edit it to make a bench pass.\n"
parts[#parts + 1] = "--\n"
parts[#parts + 1] = "return "
write(fixture, "", parts)
parts[#parts + 1] = "\n"
local text = table.concat(parts)
if OUT == nil then
	io.write(text)
else
	local f, err = io.open(OUT, "w")
	if f == nil then error("cannot write " .. OUT .. ": " .. tostring(err)) end
	f:write(text)
	f:close()
	print("captured two jobs at STATE_VERSION " .. tostring(state.v) .. " to " .. OUT)
end
