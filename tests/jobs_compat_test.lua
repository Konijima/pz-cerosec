--
-- A job 0.6.1 saved mid-command, loaded into this build. Run from the repo
-- root:
--   lua5.1 tests/jobs_compat_test.lua
--
-- A machine's running jobs are saved with it (CeroSecJobs.writeBook), and a
-- job is its VM frames: the loop it is in, the command it stopped on, the
-- pipes of a pipeline in flight. This build rewrote most of the VM, so the
-- question a world saved with a script running asks on the first load after
-- the update is whether the frames 0.6.1 wrote are frames this build still
-- steps -- and steps to the same end.
--
-- The photograph is tests/fixtures/jobs-0.6.1.lua, written by 0.6.1's own
-- engine and scheduler (tools/capture-job.lua says how). Nothing below builds
-- an old job by hand: a hand-built one is this build's idea of 0.6.1.
--
-- The answer is held to the same scripts run uninterrupted on THIS build: the
-- lines they print, the files they leave and the status they end with.
--

_G.require = function() end
_G.isClient = function() return false end
_G.isServer = function() return true end
_G.Events = setmetatable({}, { __index = function(t, k)
	local v = { Add = function() end, Remove = function() end }
	rawset(t, k, v)
	return v
end })

local LUA = "42/media/lua/"
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

local count = 0
local function check(what, cond)
	count = count + 1
	if not cond then error("FAIL: " .. what, 2) end
end
local function eq(what, got, want)
	count = count + 1
	if got ~= want then
		error("FAIL: " .. what .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
	end
end

local PATH = "tests/fixtures/jobs-0.6.1.lua"
local function photo()
	local chunk, err = loadfile(PATH)
	if not chunk then error("cannot load " .. PATH .. ": " .. tostring(err)) end
	return chunk()
end

-- The scheduler's loop, short: step, drain, until the job is over. Answers
-- the lines it printed.
local function finish(state, job, env)
	local out = {}
	for pass = 1, 400 do
		if CeroSecOS.jobIsOver(job) then break end
		env.nowMs = env.nowMs + 100
		CeroSecOS.jobStep(state, job, env, 100)
		for i = 1, #job.out do out[#out + 1] = job.out[i] end
		job.out = {}
	end
	check("the job ends", CeroSecOS.jobIsOver(job))
	return out
end

local FILES_WRITTEN = { "/home/admin/out.txt", "/home/admin/last.txt", "/home/admin/up.txt" }
local function file(state, path)
	local node = CeroSecOS.systemNode(state, path)
	return node and node.data
end

-- The same scripts, start to end on this build: what "finishes correctly"
-- means.
local want = {}
do
	local fixture = photo()
	for _, name in ipairs({ "loop", "pipe" }) do
		local state = CeroSecOS.newState("ksp-front-01")
		local session = CeroSecOS.login(state, "admin", "")
		local path = "/home/admin/" .. name .. ".sh"
		CeroSecOS.writeFile(state, session, path, fixture.scripts[name], false, nil)
		local env = { now = 725846400, nowMs = 1000, jobs = {} }
		local _, lines, control, data = CeroSecOS.startScript(state, session, "sh", path, {},
			"sh " .. path, env, false)
		eq(name .. ": this build starts it", control, "job")
		local job = CeroSecOS.newJob({ id = 1, prog = data.prog, args = data.args,
			name = data.name, cmd = data.cmd, session = session, bg = true })
		env.jobs[1] = job
		local out = finish(state, job, env)
		local files = {}
		for i = 1, #FILES_WRITTEN do files[FILES_WRITTEN[i]] = file(state, FILES_WRITTEN[i]) end
		want[name] = { out = out, files = files, status = job.status }
	end
	eq("the loop, uninterrupted, prints", table.concat(want.loop.out, "|"), "after 0")
	eq("and writes", want.loop.files["/home/admin/out.txt"], "start\nline 1\nline 2\nline 3\n")
	eq("the pipe, uninterrupted, writes", want.pipe.files["/home/admin/up.txt"], "ONE\nTWO\nTHREE\n")
end

-- The photograph, walked up with its book inside it, and the book read the
-- way the server reads it at load (CeroSecJobs.readBook), on a stand-in for
-- the machine object: what it needs of one is its state, that it is on,
-- and where it is, for the log line.
local function loadBook(fixture)
	local state = fixture.state
	local walked, why = CeroSecOS.migrate(state, "ksp-front-01")
	check("the machine walks up (" .. tostring(why) .. ")", walked ~= nil)
	local ok, reason = CeroSecOS.validate(state)
	eq("and the gate takes it, book and all (" .. tostring(reason) .. ")", ok, true)
	check("the book rode through", type(state.jobs) == "table" and #state.jobs.list == 2)
	_G.getTimestampMs = function() return fixture.nowMs end
	local machine = { os = state, on = true, x = 1, y = 2, z = 0 }
	local back = CeroSecJobs.readBook(nil, machine)
	return state, CeroSecJobs.book(machine).list, back
end

do
	local fixture = photo()
	eq("the photograph is of the shape before STATE_VERSION 3", fixture.v, 2)
	local state, list, back = loadBook(fixture)
	eq("both jobs came back", back, 2)
	for k, name in ipairs(fixture.order) do
		local job = list[k]
		eq(name .. ": asleep, as it was saved", job.state, "sleeping")
		local env = { now = 725846400, nowMs = fixture.nowMs, jobs = { job } }
		local out = finish(state, job, env)
		local all = {}
		for i = 1, #fixture.printed[name] do all[#all + 1] = fixture.printed[name][i] end
		for i = 1, #out do all[#all + 1] = out[i] end
		eq(name .. ": prints what it prints uninterrupted", table.concat(all, "|"),
			table.concat(want[name].out, "|"))
		eq(name .. ": ends with the same status", job.status, want[name].status)
	end
	for i = 1, #FILES_WRITTEN do
		local path = FILES_WRITTEN[i]
		local w = want.loop.files[path] or want.pipe.files[path]
		eq(path .. " is what the uninterrupted run left", file(state, path), w)
	end
end

print("jobs_compat_test: " .. count .. " checks passed")
