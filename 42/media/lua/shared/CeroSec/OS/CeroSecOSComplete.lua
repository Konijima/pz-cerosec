--
-- CeroSec OS core: completion at the prompt.
--
-- One function, and it is pure like the rest of the engine: it reads the state
-- and the session and answers with strings. It moves nothing, creates nothing
-- and stamps nothing.
--
--   CeroSecOS.complete(state, session, line, cursor)
--     -> { replacement = string|nil, candidates = { ... }, start = index }
--
-- cursor is how many characters of the line are BEFORE the caret, 0..#line,
-- which is the number the window's text box answers. The word being completed
-- is the one the caret is standing in, counted to the left of it only: what is
-- to the right of the caret is not part of it and is not touched, exactly as it
-- is not in ksh. So the caller replaces line[start .. cursor] with replacement
-- and keeps the rest of the line as it was.
--
-- replacement is nil when there is nothing to put there -- no match, or a word
-- of a shape this machine does not complete. candidates is every name that
-- matched, sorted, for the listing a second Tab prints; it is one entry when
-- the completion was unique and empty when nothing matched.
--
-- What it completes, and it is ksh's answer to the same question:
--
--   * the first word of a command -> a COMMAND. The executables in /bin the
--     account may run, plus the words that are the shell itself and have no
--     file at all (the reserved words and the builtins). A unique one gets a
--     trailing space, because a command name is finished when it is found.
--   * anywhere else -> a PATH, relative to the session's cwd, absolute, or
--     under "~". A unique directory gets a trailing "/" so the next component
--     can be typed straight on; a unique file gets a trailing space.
--   * several matches -> the longest prefix they share, and nothing more. The
--     names come back for the caller to print, which is the second Tab.
--
-- What it refuses, and says so by answering nothing: a word inside single
-- quotes (text is text, and ksh does not complete in there either), a word
-- carrying a variable or a backslash escape (what it will expand to is the
-- job's business and not known here), and the inside of $(( )).
--
-- Permissions are the filesystem's, not a filter laid over the answer: a
-- directory is listed only if the account may read it and only if it could be
-- reached at all, so completion never says a name the account could not have
-- found with `ls`. A directory it may enter but not read answers nothing, the
-- way the real one does.
--

CeroSecOS = CeroSecOS or {}

local BLANK = { [" "] = true, ["\t"] = true, ["\r"] = true, ["\n"] = true }

-- The reserved words a COMMAND follows: `if`, `while` and `until` are followed
-- by the command they test, `then`, `elif`, `else` and `do` by the command they
-- run. `for`, `in`, `fi` and `done` are not followed by one, and are not here.
local OPENS_COMMAND = {
	["if"] = true, ["then"] = true, ["elif"] = true, ["else"] = true,
	["do"] = true, ["while"] = true, ["until"] = true,
}

-- The line, read left to right as far as the caret, the way the tokenizer in
-- CeroSecOSScript.lua reads it -- blanks and the operators end a word, and
-- ";", "&&", "||", "|", "&" and "$(" begin a command.
--
-- Answers: whether the word is one we complete at all, its text, where that
-- text starts in the line, the plain words of the command in front of it, and
-- whether the caret is inside double quotes the word opened.
local function scan(line, cursor)
	local words = {}      -- the words of this command before the current one
	local inWord = false
	local text = ""       -- the current word, as text
	local start = cursor + 1
	local bare = true     -- every character of it so far was bare
	local dq = false      -- inside the double quotes this word opened
	local ok = true       -- it is a shape completion understands

	local function endWord()
		if not inWord then return end
		if bare then words[#words + 1] = text else words[#words + 1] = false end
		inWord = false
		text = ""
		bare = true
		ok = true
	end

	local i = 1
	while i <= cursor do
		local c = string.sub(line, i, i)

		if dq then
			if c == "\"" then
				-- The run closed in front of the caret, so what follows is a
				-- second run in the same word. One run is what we complete.
				dq = false
				ok = false
				i = i + 1
			elseif c == "\\" then
				if i + 1 > cursor then
					ok = false
					i = i + 1
				else
					text = text .. string.sub(line, i + 1, i + 1)
					i = i + 2
				end
			elseif c == "$" then
				ok = false
				text = text .. c
				i = i + 1
			else
				text = text .. c
				i = i + 1
			end

		elseif BLANK[c] then
			endWord()
			start = i + 1
			i = i + 1

		elseif c == ";" or c == "&" or c == "|" then
			endWord()
			-- A command ends here whichever of the three it is, and whether it
			-- is doubled: ";", "&", "&&" and "||" all leave the caret at the
			-- first word of the next one.
			words = {}
			if string.sub(line, i + 1, i + 1) == c then i = i + 2 else i = i + 1 end
			start = i

		elseif c == ">" or c == "<" then
			endWord()
			-- The word after a redirection is a FILE and never a command, so
			-- the command is left with a word in it already.
			words = { false }
			if c == ">" and string.sub(line, i + 1, i + 1) == ">" then
				i = i + 2
			else
				i = i + 1
			end
			start = i

		elseif c == "$" and string.sub(line, i + 1, i + 1) == "(" then
			if string.sub(line, i + 2, i + 2) == "(" then
				-- $((expression)): arithmetic, where no name on this disk is.
				return false, "", cursor + 1, {}, false
			end
			endWord()
			words = {}
			i = i + 2
			start = i

		elseif c == "'" then
			-- A single-quoted run is text and only text.
			return false, "", cursor + 1, {}, false

		elseif c == "\"" then
			if text ~= "" then ok = false end
			if not inWord then start = i + 1 end
			inWord = true
			bare = false
			dq = true
			i = i + 1

		elseif c == "\\" then
			if not inWord then start = i end
			inWord = true
			bare = false
			ok = false
			i = i + 2

		elseif c == "$" then
			if not inWord then start = i end
			inWord = true
			bare = false
			ok = false
			text = text .. c
			i = i + 1

		else
			if not inWord then start = i end
			inWord = true
			text = text .. c
			i = i + 1
		end
	end

	return ok, text, start, words, dq
end

-- Is the word being typed the first word of its command? Word one is, and so is
-- the word after `sudo` -- sudo RUNS a command, so what follows it is a command
-- name and not a file, and `sudo sudo ls` is the same again. A reserved word
-- that opens a command counts the same way.
local function atCommand(words)
	for i = 1, #words do
		local w = words[i]
		if w ~= "sudo" and not OPENS_COMMAND[w] then return false end
	end
	return true
end

-- The longest prefix a set of names shares. Called only with at least one.
local function commonPrefix(names)
	local out = names[1]
	for i = 2, #names do
		local other = names[i]
		local k = 0
		while k < #out and k < #other
				and string.sub(out, k + 1, k + 1) == string.sub(other, k + 1, k + 1) do
			k = k + 1
		end
		out = string.sub(out, 1, k)
	end
	return out
end

-- The home of whoever is typing, or nil for an account with none on its
-- /etc/passwd line. The tilde is the shell's and is expanded here exactly as
-- CeroSecOS.expandTilde expands it before a command is handed its arguments.
local function homeOf(state, session)
	local user = CeroSecOS.getUser(state, session.user)
	if user == nil or type(user.home) ~= "string" or user.home == "" then return nil end
	return user.home
end

-- Every command name that starts with prefix: the files in /bin the account may
-- run, plus the words the shell itself is. Sorted, and each name once -- `help`
-- is both a file and a builtin.
local function commandNames(state, session, prefix)
	local hidden = string.sub(prefix, 1, 1) == "."
	local seen = {}
	local names = {}

	local function offer(name)
		if seen[name] then return end
		if string.sub(name, 1, #prefix) ~= prefix then return end
		seen[name] = true
		names[#names + 1] = name
	end

	local bin = CeroSecOS.getNode(state, session, CeroSecOS.BIN_PATH)
	if bin ~= nil and bin.type == "dir" and CeroSecOS.can(state, session, bin, "r") then
		local kids = CeroSecOS.listedNames(bin, hidden)
		for i = 1, #kids do
			local node = bin.children[kids[i]]
			if node.type == "file" and CeroSecOS.can(state, session, node, "x") then
				offer(kids[i])
			end
		end
	end

	-- The words with no file to find, and the two halves are the engine's own
	-- lists rather than a third copy: the grammar (CeroSecOS.RESERVED), the
	-- words that change the shell (CeroSecOS.BUILTINS, and the ones `help`
	-- prints under them).
	for name, _ in pairs(CeroSecOS.RESERVED or {}) do offer(name) end
	for name, _ in pairs(CeroSecOS.BUILTINS or {}) do offer(name) end
	for name in string.gmatch(CeroSecOS.HELP_BUILTINS or "", "%S+") do offer(name) end

	table.sort(names)
	return names
end

-- Every entry of the directory the word names that starts with the segment
-- being typed, and whether each is a directory. nil when there is nothing to
-- list: no such directory, not a directory, or one the account may not read.
local function pathNames(state, session, dirText, base)
	local lookup = dirText
	if lookup == "" then lookup = "." end
	local home = homeOf(state, session)
	if home ~= nil then lookup = CeroSecOS.expandHome(lookup, home) end

	local node = CeroSecOS.getNode(state, session, lookup)
	if node == nil or node.type ~= "dir" then return nil end
	if not CeroSecOS.can(state, session, node, "r") then return nil end

	local kids = CeroSecOS.listedNames(node, string.sub(base, 1, 1) == ".")
	local names, dirs = {}, {}
	for i = 1, #kids do
		local name = kids[i]
		if string.sub(name, 1, #base) == base then
			names[#names + 1] = name
			dirs[name] = node.children[name].type == "dir"
		end
	end
	return names, dirs
end

local function answer(replacement, candidates, start)
	return { replacement = replacement, candidates = candidates, start = start }
end

function CeroSecOS.complete(state, session, line, cursor)
	if type(state) ~= "table" or state.fs == nil then return answer(nil, {}, 1) end
	if type(session) ~= "table" or type(session.user) ~= "string" then
		return answer(nil, {}, 1)
	end
	if type(line) ~= "string" then return answer(nil, {}, 1) end
	if type(cursor) ~= "number" then cursor = #line end
	cursor = math.floor(cursor)
	if cursor < 0 then cursor = 0 end
	if cursor > #line then cursor = #line end

	local ok, word, start, words, dq = scan(line, cursor)
	if not ok then return answer(nil, {}, cursor + 1) end

	-- A command name is a name and never a path: there is no PATH on this
	-- machine, so nothing but /bin and the shell's own words is offered for it.
	if atCommand(words) then
		local names = commandNames(state, session, word)
		if #names == 0 then return answer(nil, {}, start) end
		local close = ""
		if dq then close = "\"" end
		if #names == 1 then return answer(names[1] .. close .. " ", names, start) end
		return answer(commonPrefix(names), names, start)
	end

	-- "~" on its own names the account's home, and a home is a directory.
	if word == "~" then
		if homeOf(state, session) == nil then return answer(nil, {}, start) end
		return answer("~/", { "~" }, start)
	end

	-- The word splits at its last "/": everything up to it names the directory
	-- to list, everything after it is the segment being typed. The directory
	-- half is put back in front of the answer exactly as it was typed, so a
	-- completion never rewrites "~/" as a home or "../x" as an absolute path.
	local cut = 0
	for p = #word, 1, -1 do
		if string.sub(word, p, p) == "/" then
			cut = p
			break
		end
	end
	local dirText = string.sub(word, 1, cut)
	local base = string.sub(word, cut + 1)

	local names, dirs = pathNames(state, session, dirText, base)
	if names == nil or #names == 0 then return answer(nil, {}, start) end
	if #names == 1 then
		local name = names[1]
		if dirs[name] then return answer(dirText .. name .. "/", names, start) end
		local close = ""
		if dq then close = "\"" end
		return answer(dirText .. name .. close .. " ", names, start)
	end
	return answer(dirText .. commonPrefix(names), names, start)
end
