-- No player-controlled string reaches Lua's pattern matching unescaped.
-- Run from the repo root (tests/kahlua-check.sh runs it):
--   lua5.1 tests/pattern-check.lua
--
-- A pattern is code: "%b", "[", a lone "%" and a capture reference are all
-- things a player could type, and handed to string.find as a pattern they are
-- an error in the middle of a command or a match nobody meant. So every call
-- that matches -- string.find, match, gmatch and gsub, and the same four as
-- methods -- is read here, in every Lua file that ships, and its PATTERN must
-- be one of:
--
--   * a string literal, which is the author's and not the player's;
--   * any argument of a find whose fourth argument is `true` (a plain find:
--     no pattern at all);
--   * an entry of ALLOWED below, by file and by the argument's exact text,
--     each with the reason it is not a player's.
--
-- gsub's REPLACEMENT is held to the same rule, because "%1" and a lone "%" in
-- it are read too: a literal, a function or table built in place, or ALLOWED.
--
-- This is a lexer and not a grep because a grep cannot tell a call split over
-- two lines, a comma inside a nested call, or a "string.find(" inside a
-- comment from the real thing. It does not follow values: a local that holds
-- a literal is still a name here, which is why a name must be allowed by hand
-- and say why.

local ROOT = "42/media/lua"

local ALLOWED = {
	-- A constant of the engine's own, a literal one line above it.
	["CeroSecOSDisk.lua|CeroSecOS.LABEL_PATTERN"] = true,
	-- "^" .. CeroSecOS.AT_MAGIC .. " (%S+) (%d+)$": AT_MAGIC is a constant
	-- of letters and a "#".
	["CeroSecOSCron.lua|\"^\" .. CeroSecOS.AT_MAGIC .. \" (%S+) (%d+)$\""] = true,
	-- The content catalogue's placeholders: the names are keys of its own
	-- list, braces and letters, and the value is a login, [a-z0-9] -- no "%"
	-- on either side (the comment above the call says the same).
	["CeroSecContent.lua|\"{\" .. list[i] .. \"}\""] = true,
	["CeroSecContent.lua|value"] = true,
	-- CeroSecOS.HASH_TAG is a constant, "cs1".
	["CeroSecOSUsers.lua|\"^%$\" .. CeroSecOS.HASH_TAG .. \"%$([0-9a-z]+)%$([0-9a-f]+)$\""] = true,
	-- A player's function NAME, but only after CeroSecOS.isVarName passed it on
	-- the line above: letters, digits and "_", nothing a pattern reads.
	["CeroSecDefs.lua|\"^\" .. name .. \"[ \\t]*%([ \\t]*%)\""] = true,
}

local function listFiles()
	local files = {}
	local p = io.popen("find " .. ROOT .. " -name '*.lua' | sort")
	for line in p:lines() do files[#files + 1] = line end
	p:close()
	return files
end

-- Past a string or comment starting at i, or nil if none starts there.
local function skipLong(src, i)
	local eq = string.match(src, "^%[(=*)%[", i)
	if eq == nil then return nil end
	local close = "]" .. eq .. "]"
	local e = string.find(src, close, i, true)
	return (e or #src) + #close
end
local function skip(src, i)
	local c = string.sub(src, i, i)
	if string.sub(src, i, i + 1) == "--" then
		local long = skipLong(src, i + 2)
		if long ~= nil then return long end
		local e = string.find(src, "\n", i, true)
		return (e or #src) + 1
	end
	if c == "[" then return skipLong(src, i) end
	if c == "\"" or c == "'" then
		local j = i + 1
		while j <= #src do
			local d = string.sub(src, j, j)
			if d == "\\" then j = j + 2
			elseif d == c then return j + 1
			else j = j + 1 end
		end
		return j
	end
	return nil
end

-- The arguments of the call whose "(" is at i: their texts, and the line.
local function args(src, i)
	local out, depth, start, j = {}, 0, i + 1, i + 1
	while j <= #src do
		local past = skip(src, j)
		if past ~= nil then
			j = past
		else
			local c = string.sub(src, j, j)
			if c == "(" or c == "{" or c == "[" then depth = depth + 1
			elseif (c == ")" or c == "}" or c == "]") and depth > 0 then depth = depth - 1
			elseif c == ")" then
				out[#out + 1] = string.sub(src, start, j - 1)
				break
			elseif c == "," and depth == 0 then
				out[#out + 1] = string.sub(src, start, j - 1)
				start = j + 1
			end
			j = j + 1
		end
	end
	for k = 1, #out do
		out[k] = string.gsub(string.gsub(out[k], "^%s+", ""), "%s+$", "")
		out[k] = string.gsub(out[k], "%s+", " ")
	end
	return out
end

-- One string literal and nothing else.
local function literal(text)
	if text == nil then return true end
	local past = skip(text, 1)
	local c = string.sub(text, 1, 1)
	return (c == "\"" or c == "'" or c == "[") and past == #text + 1
end

local failures, calls = 0, 0
for _, path in ipairs(listFiles()) do
	local f = assert(io.open(path, "r"))
	local src = f:read("*a")
	f:close()
	local base = string.match(path, "([^/]+)$")
	local i = 1
	while i <= #src do
		local past = skip(src, i)
		if past ~= nil then
			i = past
		else
			local fn, open = nil, nil
			local s1, e1, name1 = string.find(src, "^string%.([%a]+)%s*%(", i)
			local s2, e2, name2 = string.find(src, "^:([%a]+)%s*%(", i)
			local method = false
			if s1 ~= nil and string.find(string.sub(src, i - 1, i - 1), "[%w_%.]") == nil then
				fn, open = name1, e1
			elseif s2 ~= nil then
				fn, open, method = name2, e2, true
			end
			if fn == "find" or fn == "match" or fn == "gmatch" or fn == "gsub" then
				calls = calls + 1
				local a = args(src, open)
				local off = method and 0 or 1
				local pat, repl = a[off + 1], a[off + 2]
				local plain = fn == "find" and a[off + 3] == "true"
				local line = select(2, string.gsub(string.sub(src, 1, i), "\n", "")) + 1
				local function judge(what, text)
					if literal(text) or ALLOWED[base .. "|" .. tostring(text)] then return end
					failures = failures + 1
					print("  FAIL " .. path .. ":" .. line .. ": " .. fn .. "'s " .. what ..
						" is not a literal: " .. tostring(text))
				end
				if not plain then judge("pattern", pat) end
				if fn == "gsub" and repl ~= nil
						and string.find(repl, "^function") == nil
						and string.find(repl, "^{") == nil then
					judge("replacement", repl)
				end
				i = open + 1
			else
				i = i + 1
			end
		end
	end
end

if calls < 100 then
	print("  FAIL pattern-check read only " .. calls .. " matching calls: it is not looking")
	failures = failures + 1
end
if failures > 0 then
	print("pattern-check: FAILED")
	os.exit(1)
end
print("  ok   no player string reaches a pattern (" .. calls .. " calls read)")
