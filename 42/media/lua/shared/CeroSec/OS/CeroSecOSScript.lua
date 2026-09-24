--
-- CeroSec OS core: the script language, as a parser.
--
-- A script is a text file on the machine's own disk and nothing else. This
-- file turns that text into a PROGRAM: nested plain tables of strings, numbers
-- and booleans, with no functions anywhere in it. CeroSecOSVM.lua walks that
-- program a step at a time.
--
-- The two halves are apart on purpose. Parsing is where a mistake in a script
-- is caught, and it happens ONCE, before a job exists: a script with a missing
-- `done` never becomes a job at all, and never costs the server a tick. What
-- the parser hands over is inert -- there is no code in it, only a shape -- so
-- nothing a player can type is ever evaluated as Lua. That is the whole
-- security model of this rung and it is enforced here, by never building
-- anything but tables.
--
-- The grammar, in one place:
--
--   program   := statement (( ";" | newline ) statement)*
--   statement := andor [ "&" ]
--   andor     := pipeline (( "&&" | "||" ) pipeline)*
--   pipeline  := piece ( "|" piece )*
--   piece     := if | for | while | until | case | group | func | simple
--   if        := "if" program "then" program
--                ("elif" program "then" program)* [ "else" program ] "fi"
--   for       := "for" NAME [ "in" word* ] (";"|newline) "do" program "done"
--   while     := "while" program "do" program "done"
--   until     := "until" program "do" program "done"
--   case      := "case" word "in" clause* "esac"
--   clause    := [ "(" ] word ( "|" word )* ")" program [ ";;" ]
--   group     := ( "{" program "}" | "(" program ")" ) redirect*
--   func      := NAME "(" ")" "{" program "}"
--   simple    := ( word | redirect )*
--   redirect  := [ "2" ] ( ">" | ">>" ) word | [ "1" | "2" ] ">&" ( "1" | "2" )
--
-- A word is an array of PARTS, because what a word means is only known when
-- the job runs it:
--
--   { t = "lit",    s = "notes",  q = true  }   plain text, never split
--   { t = "var",    name = "N",   q = false }   $N or ${N}
--   { t = "arg",    n = 1,        q = false }   $1..$9, $0
--   { t = "count"|"all"|"star"|"status"|"job"|"bang", q }   $# $@ $* $? $$ $!
--   { t = "sub",    prog = <program>,     q }   $(command)
--   { t = "arith",  expr = "1 + $x",      q }   $((expression))
--
-- An "arith" part also carries `parts` when the expression holds a $( ): the
-- command substitutions in it, lifted out so the walker can run them before the
-- sum is read, which is the order POSIX.2 puts the expansions in. It is nil for
-- every ordinary sum, and the text is then the whole of it.
--
-- q is "this part was quoted": a quoted part is one field whatever is in it,
-- an unquoted expansion is split on blanks the way a real shell splits it.
-- Literal text is q = true even when it was typed bare, because a literal
-- never had a chance to grow a space it did not have.
--
-- Comments run from an unquoted "#" at the start of a word to the end of the
-- line, so a leading "#!/bin/sh" is a comment like any other and needs no rule
-- of its own.
--
-- Kahlua: pure Lua 5.1, no metatables, no coroutines, no goto, and nothing out
-- of the standard library beyond string and table.
--

CeroSecOS = CeroSecOS or {}

-- How deep the constructs may nest inside one script. Sixteen is deeper than
-- anything a person writes at a terminal and shallow enough that the walker's
-- own frame stack cannot run away.
CeroSecOS.MAX_NEST = 16

-- The text of one function definition, and how many a shell may hold.
--
-- What a shell keeps between one line and the next is the SOURCE of a function, so
-- the ceiling is on a string and is the one a variable's value already meets -- a
-- kilobyte is a page of shell and more than anything anybody types at a glass sixty
-- columns wide. Sixteen of them, because they are kept on the console and the
-- console is written to the save file; a shell that could hold a thousand would be a
-- way to fill it.
CeroSecOS.MAX_FUNC_BYTES = 1024
CeroSecOS.MAX_FUNCS = 16

-- Stages in one pipeline. A pipeline runs every stage of it at once, so each one
-- is a shell of its own with its own frames and its own variables; eight is more
-- than any line anybody writes and few enough that the widest pipeline a 4096
-- byte file can hold cannot ask the machine for two thousand of them.
CeroSecOS.MAX_STAGES = 8

-- The words that are only words in command position. `echo done` prints
-- "done"; `done` on its own is the end of a loop, or a mistake. The braces
-- are among them (POSIX.2 XCU 2.4; 4.4BSD-Lite2 sh's TBEGIN and TEND in
-- bin/sh/mktokens): `echo {` prints it, `{echo a;}` is the word `{echo` and
-- then a `}` where a command starts, which is `"}" unexpected` on sh.
CeroSecOS.RESERVED = {
	["if"] = true, ["then"] = true, ["elif"] = true, ["else"] = true, ["fi"] = true,
	["for"] = true, ["in"] = true, ["while"] = true, ["until"] = true,
	["do"] = true, ["done"] = true,
	["case"] = true, ["esac"] = true,
	["{"] = true, ["}"] = true,
}

local function isNameStart(c)
	return c ~= "" and string.find(c, "^[A-Za-z_]") ~= nil
end

local function isNameChar(c)
	return c ~= "" and string.find(c, "^[A-Za-z0-9_]") ~= nil
end

-- The special parameters that may stand in braces, and the part each is.
local SPECIAL_IN_BRACES = {
	["@"] = "all", ["*"] = "star", ["#"] = "count",
	["?"] = "status", ["$"] = "job", ["!"] = "bang",
}

-- Digits and nothing else: ${1} and ${10}, a positional parameter inside
-- braces. Never a variable -- isVarName refuses a leading digit.
local function isPositional(name)
	return name ~= "" and string.find(name, "^[0-9]+$") ~= nil
end

-- A variable name: what may sit on the left of "=" and inside ${}.
function CeroSecOS.isVarName(name)
	if type(name) ~= "string" or name == "" then return false end
	if not isNameStart(string.sub(name, 1, 1)) then return false end
	return string.find(name, "[^A-Za-z0-9_]") == nil
end

--
-- The tokenizer
--

-- Add a literal character to the word being built, merging with the literal
-- part in front of it so a word of plain text is one part and not forty.
local function addLit(parts, c, quoted, bare)
	local last = parts[#parts]
	if last ~= nil and last.t == "lit" and last.bare == bare then
		last.s = last.s .. c
		return
	end
	parts[#parts + 1] = { t = "lit", s = c, q = true, bare = bare }
end

-- $(command), from the "$" to the ")" that closes it: the program inside, and
-- the index just past the bracket. nil plus a reason for a line that is not one.
--
-- Its own function because it is read from TWO places now -- a word, and the
-- inside of a $(( )) -- and a second scanner would be a second answer to "where
-- does this bracket close".
--
-- One level deep and no further: a substitution inside a substitution is the
-- shape that lets a short line ask for an unbounded amount of work, and there is
-- no script worth writing on a 1993 desk machine that needs two.
local function readCommandSub(text, i, depth)
	if depth > 0 then return nil, "Syntax error: Bad substitution" end
	local n = #text
	local j, level, quote = i + 2, 0, nil
	while j <= n do
		local ch = string.sub(text, j, j)
		if quote ~= nil then
			if ch == quote then quote = nil
			elseif ch == "\\" and quote == "\"" then j = j + 1 end
		elseif ch == "'" or ch == "\"" then
			quote = ch
		elseif ch == "\\" then
			j = j + 1
		-- A $(( )) is NOT a second command substitution and must not be refused as
		-- one. POSIX.2 puts arithmetic expansion inside a command substitution --
		-- `x=$(echo $((2 + 3)))` is an ordinary line -- and the two wear the same
		-- first two characters, which is why this used to answer "bad substitution"
		-- for a sum. Its brackets are balanced, so the level count below carries it.
		elseif ch == "$" and string.sub(text, j + 1, j + 1) == "("
				and string.sub(text, j + 2, j + 2) ~= "(" then
			return nil, "Syntax error: Bad substitution"
		elseif ch == "(" then
			level = level + 1
		elseif ch == ")" then
			if level == 0 then
				local inner = string.sub(text, i + 2, j - 1)
				local prog, reason = CeroSecOS.parseScript(inner, depth + 1)
				if prog == nil then return nil, reason end
				return prog, j + 1
			end
			level = level - 1
		end
		j = j + 1
	end
	return nil, "Syntax error: Bad substitution"
end

-- `command`, from the opening backquote to the matching closing one: the
-- program inside, and the index just past the closer. nil plus a reason for
-- a line that is not one.
--
-- sh(1) "Command Substitution": backquotes are the ORIGINAL form, from the
-- Bourne shell; $( ) is the later ksh and POSIX.2 (1992) spelling of the
-- same thing, and this machine is 1993, so both are on it. A backquote pair
-- does not balance the way `(` and `)` count, so its closer is the first
-- UNESCAPED backquote found. Inside the pair a backslash is literal except
-- before `$`, `` ` `` or `\`, where it escapes that character (same page),
-- letting a literal backquote or dollar sign sit inside the span without
-- ending it early.
--
-- One level, and no further: the same rule as readCommandSub below, and it
-- holds however the nesting is spelled. `` `echo \`echo hi\` `` `` is
-- refused just like `$(echo $(echo hi))`, escaped or not; the depth
-- argument catches it, not a scan for the surface shape. Reuses
-- CeroSecOS.parseScript, so the result is the identical
-- { t = "sub", prog = ... } node, and every step after parsing, expansion,
-- budget charging, field splitting, globbing, has one path.
local function readBackquoteSub(text, i, depth)
	if depth > 0 then return nil, "Syntax error: Bad substitution" end
	local n = #text
	local j, buf = i + 1, ""
	while j <= n do
		local ch = string.sub(text, j, j)
		if ch == "`" then
			local prog, reason = CeroSecOS.parseScript(buf, depth + 1)
			if prog == nil then return nil, reason end
			return prog, j + 1
		elseif ch == "\\" then
			local nx = string.sub(text, j + 1, j + 1)
			if nx == "$" or nx == "`" or nx == "\\" then
				buf = buf .. nx
				j = j + 2
			else
				buf = buf .. ch
				j = j + 1
			end
		else
			buf = buf .. ch
			j = j + 1
		end
	end
	return nil, "Syntax error: Bad substitution"
end

-- The inside of a $(( )) as an array of PARTS, when it holds a command
-- substitution; nil when it is plain text and the arithmetic reader can have it
-- whole.
--
-- POSIX.2 orders the expansions: parameter expansion and command substitution
-- happen first, arithmetic expansion afterwards -- so `stop=$(($(date +%s) + 300))`
-- is a sum on what date printed, and it is the line a survivor writes when he
-- wants a deadline. It answered "bad arithmetic" here, because the expression
-- reached the reader with the brackets still in it and the reader knows variables
-- and arguments, not programs.
--
-- Only the command substitutions are lifted out. Everything else the reader
-- already does for itself -- `$1`, `$#`, `$?`, `$$`, `${NAME}` and a bare name --
-- and moving those here would be two readers for one grammar.
--
-- parts, or nil, or nil plus a reason.
local function arithParts(text, depth)
	if string.find(text, "$(", 1, true) == nil then return nil end
	local parts, lit, i, n = {}, "", 1, #text
	local function keepLit()
		if lit ~= "" then
			parts[#parts + 1] = { t = "lit", s = lit }
			lit = ""
		end
	end
	while i <= n do
		local c = string.sub(text, i, i)
		if c == "$" and string.sub(text, i + 1, i + 1) == "("
				and string.sub(text, i + 2, i + 2) ~= "(" then
			local prog, second = readCommandSub(text, i, depth)
			if prog == nil then return nil, second end
			keepLit()
			parts[#parts + 1] = { t = "sub", prog = prog }
			i = second
		else
			lit = lit .. c
			i = i + 1
		end
	end
	keepLit()
	if #parts == 0 then return nil end
	return parts
end

-- The word after :- := :? :+ # ## % %%, defined below readDollar because the
-- two call each other: a name inside the braces may itself hold a bare $x or
-- ${x}, and readDollar's own "{" arm reads that word once it has the operator.
-- Forward-declared so the mutual recursion compiles.
local readBraceWord

-- Everything from "$" onwards. Returns the part and the index just past it,
-- or nil plus a reason.
local function readDollar(text, i, quoted, depth)
	local n = #text
	local c = string.sub(text, i + 1, i + 1)

	if c == "(" then
		if string.sub(text, i + 2, i + 2) == "(" then
			-- $((expression)). The expression is kept as text and worked out
			-- when the job runs it, by the arithmetic reader in the VM -- never
			-- by Lua.
			local j, level = i + 3, 0
			while j <= n do
				local ch = string.sub(text, j, j)
				if ch == "(" then
					level = level + 1
				elseif ch == ")" then
					if level == 0 then
						if string.sub(text, j + 1, j + 1) ~= ")" then
							return nil, "Syntax error: Bad substitution"
						end
						local expr = string.sub(text, i + 3, j - 1)
						-- The command substitutions in it, lifted out to be run
						-- BEFORE the sum is read (arithParts above). nil is the
						-- ordinary case and keeps the text alone.
						local pieces, reason = arithParts(expr, depth)
						if pieces == nil and reason ~= nil then return nil, reason end
						return { t = "arith", expr = expr, parts = pieces, q = quoted },
							j + 2
					end
					level = level - 1
				end
				j = j + 1
			end
			return nil, "Syntax error: Bad substitution"
		end

		local prog, second = readCommandSub(text, i, depth)
		if prog == nil then return nil, second end
		return { t = "sub", prog = prog, q = quoted }, second
	end

	if c == "{" then
		-- ${@} ${*} ${#} ${?} ${$} ${!}: the special parameters in braces,
		-- the same parts their bare forms are (below). Before ${#name},
		-- because ${#} is $# and not the length of nothing.
		local sp = string.sub(text, i + 2, i + 2)
		if string.sub(text, i + 3, i + 3) == "}" then
			local kind = SPECIAL_IN_BRACES[sp]
			if kind ~= nil then return { t = kind, q = quoted }, i + 4 end
		end

		-- ${#name}: the length, ksh88's own form and POSIX.2's. Read first
		-- because "#" cannot start a name (isVarName says so), so it can
		-- never be mistaken for one.
		if string.sub(text, i + 2, i + 2) == "#" then
			local k = i + 3
			local name = ""
			while k <= n and isNameChar(string.sub(text, k, k)) do
				name = name .. string.sub(text, k, k)
				k = k + 1
			end
			if string.sub(text, k, k) == "}" and CeroSecOS.isVarName(name) then
				return { t = "vare", kind = "len", name = name, q = quoted }, k + 1
			end
			if string.sub(text, k, k) == "}" and isPositional(name) then
				return { t = "vare", kind = "len", pos = tonumber(name), q = quoted }, k + 1
			end
			return nil, "Syntax error: Bad substitution"
		end

		local j = i + 2
		local name = ""
		while j <= n and isNameChar(string.sub(text, j, j)) do
			name = name .. string.sub(text, j, j)
			j = j + 1
		end
		-- ${1}, ${10}: a positional parameter, the only way past $9 (POSIX.2
		-- 2.5.1, "a positional parameter with more than one digit shall be
		-- enclosed in braces"), and the name ${1:-default} carries.
		local pos = nil
		if isPositional(name) then
			pos = tonumber(name)
		elseif name == "" or not CeroSecOS.isVarName(name) then
			return nil, "Syntax error: Bad substitution"
		end
		local nc = string.sub(text, j, j)
		if nc == "}" then
			if pos ~= nil then return { t = "arg", n = pos, q = quoted }, j + 1 end
			return { t = "var", name = name, q = quoted }, j + 1
		end

		-- System V sh's :- := :? :+, and ksh88's # ## % %% -- the same set
		-- CeroSecOS.globMatch already gives `case` and the shell's own
		-- pathname expansion, so # and % read a PATTERN and never a Lua one.
		local colon = false
		if nc == ":" then
			colon = true
			j = j + 1
			nc = string.sub(text, j, j)
		end
		local kind = nil
		if nc == "-" then kind = "default"
		elseif nc == "=" then kind = "assign"
		elseif nc == "?" then kind = "error"
		elseif nc == "+" then kind = "alt"
		elseif not colon and nc == "#" then
			if string.sub(text, j + 1, j + 1) == "#" then
				kind = "trimPreLong"
				j = j + 1
			else
				kind = "trimPre"
			end
		elseif not colon and nc == "%" then
			if string.sub(text, j + 1, j + 1) == "%" then
				kind = "trimSufLong"
				j = j + 1
			else
				kind = "trimSuf"
			end
		end
		if kind == nil then return nil, "Syntax error: Bad substitution" end
		j = j + 1
		local word, j2 = readBraceWord(text, j, depth)
		if word == nil then return nil, j2 end
		if pos ~= nil then name = nil end
		return { t = "vare", kind = kind, name = name, pos = pos, word = word,
			colon = colon, q = quoted }, j2
	end

	if isNameStart(c) then
		local j, name = i + 1, ""
		while j <= n and isNameChar(string.sub(text, j, j)) do
			name = name .. string.sub(text, j, j)
			j = j + 1
		end
		return { t = "var", name = name, q = quoted }, j
	end

	if string.find(c, "^[0-9]") ~= nil then
		return { t = "arg", n = tonumber(c), q = quoted }, i + 2
	end
	if c == "#" then return { t = "count", q = quoted }, i + 2 end
	if c == "@" then return { t = "all", q = quoted }, i + 2 end
	-- $* is every argument as one string, joined by a blank; $! is the process
	-- number of the last job an `&` started. Both are in the Bourne shell's
	-- sh(1) of Version 7 and in POSIX.2's list of special parameters.
	if c == "*" then return { t = "star", q = quoted }, i + 2 end
	if c == "!" then return { t = "bang", q = quoted }, i + 2 end
	if c == "?" then return { t = "status", q = quoted }, i + 2 end
	if c == "$" then return { t = "job", q = quoted }, i + 2 end

	-- A dollar in front of anything else is a dollar.
	return nil, nil, true
end

-- The word that follows :- := :? :+ # ## % %%, up to the "}" that closes it.
-- Read like an ordinary word -- quotes, a bare $name and a bare ${name} all
-- work -- but ONE level: $( ), `` `` and a second ${x:-y} inside it are each
-- refused as a bad substitution, the same ceiling readCommandSub already
-- holds $( ) inside $( ) to (one catch is bounded work; two is unbounded
-- behind a single dollar sign). That is what lets this word be read straight
-- through, with no capture to wait for and nothing that can recurse.
readBraceWord = function(text, i, depth)
	local n = #text
	local parts = {}
	-- A "$" met anywhere in this word: readDollar reads it, and only a
	-- plain parameter (var, arg, count, star, bang, status, job, all) may
	-- come back -- "sub", "arith" and a nested "vare" are refused here.
	local function dollar(quoted)
		local part, second, literal = readDollar(text, i, quoted, depth)
		if literal then
			addLit(parts, "$", true, false)
			i = i + 1
			return true
		end
		if part == nil then return nil, second end
		if part.t == "sub" or part.t == "arith" or part.t == "vare" then
			return nil, "Syntax error: Bad substitution"
		end
		parts[#parts + 1] = part
		i = second
		return true
	end
	while i <= n do
		local c = string.sub(text, i, i)
		if c == "}" then
			return parts, i + 1
		elseif c == "'" then
			i = i + 1
			local buf, closed = "", false
			while i <= n do
				local q = string.sub(text, i, i)
				if q == "'" then
					closed = true
					i = i + 1
					break
				end
				buf = buf .. q
				i = i + 1
			end
			if not closed then return nil, "Syntax error: Unterminated quoted string" end
			parts[#parts + 1] = { t = "lit", s = buf, q = true, bare = false }
		elseif c == "\"" then
			i = i + 1
			local closed = false
			parts[#parts + 1] = { t = "lit", s = "", q = true, bare = false }
			while i <= n do
				local q = string.sub(text, i, i)
				if q == "\"" then
					closed = true
					i = i + 1
					break
				elseif q == "\\" then
					local nx = string.sub(text, i + 1, i + 1)
					if nx == "" then return nil, "Syntax error: Unterminated quoted string" end
					if nx == "$" or nx == "`" or nx == "\"" or nx == "\\" then
						addLit(parts, nx, true, false)
					else
						addLit(parts, "\\" .. nx, true, false)
					end
					i = i + 2
				elseif q == "$" then
					local ok, reason = dollar(true)
					if ok == nil then return nil, reason end
				elseif q == "`" then
					return nil, "Syntax error: Bad substitution"
				else
					addLit(parts, q, true, false)
					i = i + 1
				end
			end
			if not closed then return nil, "Syntax error: Unterminated quoted string" end
		elseif c == "$" then
			local ok, reason = dollar(false)
			if ok == nil then return nil, reason end
		elseif c == "`" then
			return nil, "Syntax error: Bad substitution"
		elseif c == "\\" then
			-- A backslash quotes the character after it, as it does outside
			-- the braces: ${x#\*} cuts a literal star, never "anything".
			local nx = string.sub(text, i + 1, i + 1)
			if nx == "" then return nil, "Syntax error: Bad substitution" end
			addLit(parts, nx, true, false)
			i = i + 2
		else
			-- BARE, and marked so: in the pattern of # ## % %% an unquoted
			-- * ? [ is a glob character and a quoted one is itself (POSIX.2
			-- 3.6.2, "quoting ... shall cause the pattern character to be
			-- matched literally"), so the matcher has to know which it was.
			addLit(parts, c, true, true)
			i = i + 1
		end
	end
	return nil, "Syntax error: Bad substitution"
end

-- text -> array of tokens, or nil plus a reason and the line it is on.
--
-- Token shapes:
--   { t = "word", parts = {...}, plain = "done" or nil, line = 3 }
--   { t = "op",   v = ";" | "&&" | "||" | "&" | "\n", line = 3 }
--   { t = "redir", append = false, line = 3 }
--   { t = "eof",  line = 9 }
--
-- plain is set only when the whole word is one run of bare literal text, which
-- is the only shape a reserved word can wear.
local function tokenize(text, depth)
	local tokens = {}
	local i, n, line = 1, #text, 1

	while i <= n do
		local at = i
		local c = string.sub(text, i, i)
		if c == "\n" then
			tokens[#tokens + 1] = { t = "op", v = "\n", line = line }
			line = line + 1
			i = i + 1
		elseif c == " " or c == "\t" or c == "\r" then
			i = i + 1
		elseif c == "#" then
			while i <= n and string.sub(text, i, i) ~= "\n" do i = i + 1 end
		elseif c == ";" then
			-- ";;" is one operator and not two separators: it is what ends a case
			-- clause, and sh has read it as a single token since the Bourne shell.
			-- Two of them where a case is not being parsed is a syntax error, exactly
			-- as it is on a real one -- `echo a;;` used to run as `echo a` here,
			-- because skipSeparators swallowed the empty statement between them.
			if string.sub(text, i + 1, i + 1) == ";" then
				tokens[#tokens + 1] = { t = "op", v = ";;", line = line }
				i = i + 2
			else
				tokens[#tokens + 1] = { t = "op", v = ";", line = line }
				i = i + 1
			end
		elseif c == "&" then
			if string.sub(text, i + 1, i + 1) == "&" then
				tokens[#tokens + 1] = { t = "op", v = "&&", line = line }
				i = i + 2
			else
				tokens[#tokens + 1] = { t = "op", v = "&", line = line }
				i = i + 1
			end
		elseif c == "|" then
			if string.sub(text, i + 1, i + 1) == "|" then
				tokens[#tokens + 1] = { t = "op", v = "||", line = line }
				i = i + 2
			else
				tokens[#tokens + 1] = { t = "op", v = "|", line = line }
				i = i + 1
			end
		elseif c == ">" or ((c == "1" or c == "2") and string.sub(text, i + 1, i + 1) == ">") then
			-- A digit is a file descriptor only where a word would START and only
			-- when ">" follows it at once: `2>err` is the standard error, `a2>f` is
			-- the word a2 and `echo 2 > f` prints a 2. sh(1) of 4.4BSD and ksh(1)
			-- both read it that way. Only 1 and 2: this machine has no other
			-- descriptor to name, so `3>f` stays the word 3, as it was.
			local fd = 1
			if c == "2" then fd = 2 end
			if c ~= ">" then i = i + 1 end
			local append = false
			local dup = nil
			i = i + 1
			if string.sub(text, i, i) == ">" then
				append = true
				i = i + 1
			elseif string.sub(text, i, i) == "&" then
				-- ">&1" and ">&2": the descriptor made a copy of the other one, sh(1)'s
				-- "<&digit / >&digit" duplication. Any other word after ">&" names a
				-- descriptor this machine does not have.
				local d = string.sub(text, i + 1, i + 1)
				local after = string.sub(text, i + 2, i + 2)
				local ends = after == "" or after == " " or after == "\t" or after == "\r"
					or after == "\n" or after == ";" or after == "&" or after == "|"
					or after == ">" or after == "<" or after == "(" or after == ")"
				if (d ~= "1" and d ~= "2") or not ends then
					return nil, "Syntax error: Bad fd number", line
				end
				dup = 1
				if d == "2" then dup = 2 end
				i = i + 2
			end
			-- stop, as a word has: a function body may end on a `2>&1`.
			tokens[#tokens + 1] = { t = "redir", append = append, fd = fd, dup = dup, line = line,
				stop = i - 1 }
		elseif c == "<" then
			return nil, "Syntax error: redirection unexpected", line
		elseif c == "(" or c == ")" then
			-- Operators, and they end a word: POSIX.2 XCU 2.3 rule 6, and
			-- 4.4BSD-Lite2 sh's TLP and TRP (bin/sh/mktokens, parser.c's
			-- xxreadtoken). What they build is a subshell, a function's
			-- `name ( )` and a case pattern's brackets; anywhere else one is
			-- `"(" unexpected`, as `echo (a)` is on sh. Inside quotes, $( ),
			-- ${ } and backquotes they are text, read by those readers.
			-- stop, as a word has: a function whose body is a subshell ends
			-- on its ")" and keeps its source up to it (parseFunc).
			tokens[#tokens + 1] = { t = "op", v = c, line = line, stop = i }
			i = i + 1
		else
			-- One word: bare text, quoted runs and expansions, until a blank or
			-- an operator ends it.
			local parts = {}
			local startLine = line
			while i <= n do
				local ch = string.sub(text, i, i)
				if ch == " " or ch == "\t" or ch == "\r" or ch == "\n" or ch == ";"
						or ch == "&" or ch == "|" or ch == ">" or ch == "<"
						or ch == "(" or ch == ")" then
					break
				elseif ch == "'" then
					i = i + 1
					local closed = false
					local buf = ""
					while i <= n do
						local q = string.sub(text, i, i)
						if q == "'" then
							closed = true
							i = i + 1
							break
						end
						if q == "\n" then line = line + 1 end
						buf = buf .. q
						i = i + 1
					end
					if not closed then
						return nil, "Syntax error: Unterminated quoted string", startLine
					end
					-- A single-quoted run is text and only text, empty run
					-- included: `x=''` is a variable set to nothing, not a word
					-- that vanishes.
					parts[#parts + 1] = { t = "lit", s = buf, q = true, bare = false }
				elseif ch == "\"" then
					i = i + 1
					local closed = false
					parts[#parts + 1] = { t = "lit", s = "", q = true, bare = false }
					while i <= n do
						local q = string.sub(text, i, i)
						if q == "\"" then
							closed = true
							i = i + 1
							break
						elseif q == "\\" then
							local nx = string.sub(text, i + 1, i + 1)
							if nx == "" then
								return nil, "Syntax error: Unterminated quoted string", startLine
							end
							-- sh(1) of 4.4BSD and ksh88, and POSIX.2 2.2.3:
							-- within double quotes the backslash keeps its
							-- meaning only before $ ` " \ and newline. A
							-- backslash-newline is removed, both characters;
							-- before anything else the backslash stays, so
							-- "a\.c" is a\.c and "C:\dos" is C:\dos. The
							-- shell makes no \n or \t: printf(1) does that
							-- to its own format, echo here does not.
							if nx == "\n" then
								line = line + 1
							elseif nx == "$" or nx == "`" or nx == "\"" or nx == "\\" then
								addLit(parts, nx, true, false)
							else
								addLit(parts, "\\" .. nx, true, false)
							end
							i = i + 2
						elseif q == "$" then
							-- readDollar answers part + the index past it, or
							-- nil + a reason, or nil + nil + "it was only a
							-- dollar sign".
							local part, second, literal = readDollar(text, i, true, depth)
							if literal then
								addLit(parts, "$", true, false)
								i = i + 1
							elseif part == nil then
								return nil, second, line
							else
								parts[#parts + 1] = part
								i = second
							end
						elseif q == "`" then
							-- ``cmd`` inside double quotes: substituted, one
							-- word, no splitting -- same as `$(cmd)` here.
							local prog, second = readBackquoteSub(text, i, depth)
							if prog == nil then return nil, second, line end
							parts[#parts + 1] = { t = "sub", prog = prog, q = true }
							i = second
						else
							if q == "\n" then line = line + 1 end
							addLit(parts, q, true, false)
							i = i + 1
						end
					end
					if not closed then
						return nil, "Syntax error: Unterminated quoted string", startLine
					end
				elseif ch == "\\" then
					local nx = string.sub(text, i + 1, i + 1)
					if nx == "" then return nil, "Syntax error: Unterminated quoted string", startLine end
					if nx == "\n" then
						-- A backslash at the end of a line joins it to the next.
						line = line + 1
					else
						addLit(parts, nx, true, false)
					end
					i = i + 2
				elseif ch == "$" then
					local part, second, literal = readDollar(text, i, false, depth)
					if literal then
						addLit(parts, "$", true, true)
						i = i + 1
					elseif part == nil then
						return nil, second, line
					else
						parts[#parts + 1] = part
						i = second
					end
				elseif ch == "`" then
					-- Unquoted ``cmd`` -- output, trailing newlines stripped,
					-- split into fields, same as unquoted `$(cmd)`.
					local prog, second = readBackquoteSub(text, i, depth)
					if prog == nil then return nil, second, line end
					parts[#parts + 1] = { t = "sub", prog = prog, q = false }
					i = second
				else
					addLit(parts, ch, true, true)
					i = i + 1
				end
			end

			local plain = nil
			if #parts == 1 and parts[1].t == "lit" and parts[1].bare then plain = parts[1].s end
			if #parts == 0 then parts[1] = { t = "lit", s = "", q = true, bare = false } end
			-- Where the word sits in the text. Only a WORD carries it, and only one
			-- thing asks: a function definition has to be able to hand back its own
			-- SOURCE, because that is what the console keeps (a body is a program --
			-- nested tables -- and nothing player-controlled is handed back out of a
			-- save file as one; the text is re-read by this very parser instead).
			tokens[#tokens + 1] = { t = "word", parts = parts, plain = plain,
				line = startLine, at = at, stop = i - 1 }
		end
	end

	tokens[#tokens + 1] = { t = "eof", line = line }
	return tokens
end

--
-- The parser
--

local function peek(P) return P.tokens[P.i] end
local function take(P)
	local t = P.tokens[P.i]
	P.i = P.i + 1
	return t
end

-- How a token is named in an error: the names 4.4BSD-Lite2's sh gives its
-- tokens (bin/sh/mktokens, the table synexpect() prints from, parser.c).
-- An operator and a reserved word in double quotes -- "fi", "|", ";;" --
-- and the rest by their KIND, not their text: end of file, newline,
-- redirection, word. So `echo a | | b` is `"|" unexpected` and a stray
-- `foo` where `then` was wanted is `word unexpected`, as sh said it.
local QUOTED = { ["{"] = true, ["}"] = true, ["!"] = true }
local function describe(t)
	if t == nil or t.t == "eof" then return "end of file" end
	if t.t == "op" then
		if t.v == "\n" then return "newline" end
		return "\"" .. t.v .. "\""
	end
	if t.t == "redir" then return "redirection" end
	-- "in" is not one of sh's tokens (mktokens has no TIN): a word.
	if t.plain ~= nil and t.plain ~= "in"
			and (CeroSecOS.RESERVED[t.plain] or QUOTED[t.plain]) then
		return "\"" .. t.plain .. "\""
	end
	return "word"
end

-- synexpect(), parser.c: the token that was there, "unexpected", and the
-- one that was wanted in brackets when the grammar knew which.
local function unexpected(t, want)
	local said = "Syntax error: " .. describe(t) .. " unexpected"
	if want ~= nil then said = said .. " (expecting \"" .. want .. "\")" end
	return said
end

-- Is this token one the caller asked to be left alone? A reserved word in `stops`,
-- or the ";;" that ends a case clause -- which is an OPERATOR and not a word, and
-- is the one operator any caller has ever needed to stop at.
local function stopsHere(t, stops)
	if t.t == "word" and t.plain ~= nil and stops[t.plain] then return true end
	if t.t == "op" and (t.v == ";;" or t.v == ")") and stops[t.v] then return true end
	return false
end

local function skipSeparators(P)
	while true do
		local t = peek(P)
		if t.t == "op" and (t.v == ";" or t.v == "\n") then
			P.i = P.i + 1
		else
			return
		end
	end
end

local function skipNewlines(P)
	while true do
		local t = peek(P)
		if t.t == "op" and t.v == "\n" then
			P.i = P.i + 1
		else
			return
		end
	end
end

local parseProgram
local parseGroup
local parsePiece

-- A word token, or nil when what is next is not one.
local function wordAt(P)
	local t = peek(P)
	if t.t ~= "word" then return nil end
	return t
end

-- One redirect off the token stream into st, or a reason and a line. A simple
-- command reads its redirects with it, and so do the compound commands that may
-- carry them -- `{ ...; } > f 2>&1`, `( ... ) 2>/dev/null` -- the same
-- descriptors, in the same left-to-right order.
--
-- Where each descriptor ends up, worked out in the order the line names them,
-- which is sh(1)'s rule and the whole difference between `> f 2>&1` (both into
-- f) and `2>&1 > f` (errors where the output WAS, the output into f). In st.fds,
-- "1" and "2" are the ones the command was started with, "w" the file ">" names
-- and "e" the file "2>" names.
local function takeRedirect(P, st)
	local t = peek(P)
	-- One redirect per descriptor: a second one is a line that says two
	-- things about the same place, and this machine does not guess which.
	local fd = t.fd or 1
	if st.seen[fd] then
		return "Syntax error: redirection unexpected", t.line
	end
	st.seen[fd] = true
	P.i = P.i + 1
	if t.dup ~= nil then
		st.fds[fd] = st.fds[t.dup]
	else
		local target = wordAt(P)
		if target == nil then
			return unexpected(peek(P)), t.line
		end
		P.i = P.i + 1
		if fd == 2 then
			st.errRedirect = { word = target.parts, append = t.append }
			st.fds[2] = "e"
		else
			st.redirect = { word = target.parts, append = t.append }
			st.fds[1] = "w"
		end
	end
	return nil
end

local function parseSimple(P)
	local words = {}
	local st = { fds = { "1", "2" }, seen = {} }
	local line = peek(P).line
	while true do
		local t = peek(P)
		if t.t == "word" then
			-- Reserved words are only reserved where a command starts; every
			-- other position is an ordinary argument, so `echo done` prints it.
			if #words == 0 and t.plain ~= nil and CeroSecOS.RESERVED[t.plain] then
				return nil, unexpected(t), t.line
			end
			words[#words + 1] = t.parts
			P.i = P.i + 1
		elseif t.t == "redir" then
			local reason, rline = takeRedirect(P, st)
			if reason ~= nil then return nil, reason, rline end
		else
			break
		end
	end
	local redirect, errRedirect, fds, seen = st.redirect, st.errRedirect, st.fds, st.seen
	if #words == 0 and not seen[1] and not seen[2] then
		local t = peek(P)
		return nil, unexpected(t), t.line
	end

	-- The leading NAME=value words are assignments and are told apart HERE,
	-- once, rather than guessed at again every time the line runs. A shell
	-- never splits an assignment's value into fields, and keeping the two
	-- kinds of word in two arrays is what lets the walker honour that.
	local assigns = nil
	local first = 1
	while first <= #words do
		local parts = words[first]
		local head = parts[1]
		if head == nil or head.t ~= "lit" or not head.bare then break end
		if string.find(head.s, "^[A-Za-z_][A-Za-z0-9_]*=") == nil then break end
		if assigns == nil then assigns = {} end
		assigns[#assigns + 1] = parts
		first = first + 1
	end
	if assigns ~= nil then
		local rest = {}
		for i = first, #words do rest[#rest + 1] = words[i] end
		words = rest
	end

	local node = { k = "cmd", line = line, words = words, assigns = assigns, redirect = redirect }
	-- Only a line that named a descriptor carries these, so every node a plain
	-- `>` makes is the node it always was.
	if seen[2] or fds[1] ~= (redirect ~= nil and "w" or "1") then
		node.errRedirect = errRedirect
		node.out = fds[1]
		node.err = fds[2]
	end
	return node
end

-- A list with nothing in it where the grammar wants one. Every part of if, while,
-- until, for and a function's braces is a compound_list (POSIX XCU 2.10.2), and a
-- compound_list is at least one command: a comment or a blank line is not one.
-- dash refuses `if true; then fi` with `"fi" unexpected`, and so does this, in the
-- words synexpect() says it with. Only a list that stopped on a WORD is
-- refused here: one that ran into the end of the file is missing its closing word,
-- which the caller goes on to say.
local function emptyList(P, prog)
	if #prog > 0 then return nil end
	local t = peek(P)
	if t.t == "eof" then return nil end
	return unexpected(t), t.line
end

local function parseIf(P, depth)
	local line = take(P).line
	local clauses = {}
	local otherwise = nil

	while true do
		local cond, reason, where = parseProgram(P, { ["then"] = true }, depth + 1)
		if cond == nil then return nil, reason, where end
		local empty, eline = emptyList(P, cond)
		if empty ~= nil then return nil, empty, eline end
		local t = wordAt(P)
		if t == nil or t.plain ~= "then" then
			return nil, unexpected(peek(P), "then"), peek(P).line
		end
		P.i = P.i + 1
		local body, breason, bwhere =
			parseProgram(P, { ["elif"] = true, ["else"] = true, ["fi"] = true }, depth + 1)
		if body == nil then return nil, breason, bwhere end
		empty, eline = emptyList(P, body)
		if empty ~= nil then return nil, empty, eline end
		clauses[#clauses + 1] = { cond = cond, body = body }

		local nx = wordAt(P)
		if nx ~= nil and nx.plain == "elif" then
			P.i = P.i + 1
		else
			if nx ~= nil and nx.plain == "else" then
				P.i = P.i + 1
				local ebody, ereason, ewhere = parseProgram(P, { ["fi"] = true }, depth + 1)
				if ebody == nil then return nil, ereason, ewhere end
				empty, eline = emptyList(P, ebody)
				if empty ~= nil then return nil, empty, eline end
				otherwise = ebody
				nx = wordAt(P)
			end
			if nx == nil or nx.plain ~= "fi" then
				return nil, unexpected(peek(P), "fi"), peek(P).line
			end
			P.i = P.i + 1
			return { k = "if", line = line, clauses = clauses, otherwise = otherwise }
		end
	end
end

-- The tail every loop shares: "do" ... "done".
local function parseDoDone(P, depth)
	skipSeparators(P)
	local t = wordAt(P)
	if t == nil or t.plain ~= "do" then
		return nil, unexpected(peek(P), "do"), peek(P).line
	end
	P.i = P.i + 1
	local body, reason, where = parseProgram(P, { ["done"] = true }, depth + 1)
	if body == nil then return nil, reason, where end
	local empty, eline = emptyList(P, body)
	if empty ~= nil then return nil, empty, eline end
	local nx = wordAt(P)
	if nx == nil or nx.plain ~= "done" then
		return nil, unexpected(peek(P), "done"), peek(P).line
	end
	P.i = P.i + 1
	return body
end

local function parseFor(P, depth)
	local line = take(P).line
	local name = wordAt(P)
	if name == nil or name.plain == nil or not CeroSecOS.isVarName(name.plain) then
		return nil, "Syntax error: Bad for loop variable", peek(P).line
	end
	P.i = P.i + 1

	local words = nil
	local nx = wordAt(P)
	if nx ~= nil and nx.plain == "in" then
		P.i = P.i + 1
		words = {}
		while true do
			local t = peek(P)
			if t.t ~= "word" then break end
			if t.plain == "do" then break end
			words[#words + 1] = t.parts
			P.i = P.i + 1
		end
	end

	local body, reason, where = parseDoDone(P, depth)
	if body == nil then return nil, reason, where end
	return { k = "for", line = line, var = name.plain, words = words, body = body }
end

local function parseLoop(P, depth)
	local head = take(P)
	local cond, reason, where = parseProgram(P, { ["do"] = true }, depth + 1)
	if cond == nil then return nil, reason, where end
	local empty, eline = emptyList(P, cond)
	if empty ~= nil then return nil, empty, eline end
	local body, breason, bwhere = parseDoDone(P, depth)
	if body == nil then return nil, breason, bwhere end
	return { k = "loop", line = head.line, negate = head.plain == "until",
		cond = cond, body = body }
end

--
-- case
--
-- `case word in pattern) ... ;; esac`, POSIX.2's own shape. "(" and ")" are
-- operators since the subshell came (the tokenizer), so the brackets round a
-- pattern are tokens of their own and a pattern is an ordinary word: `"a)"` is a
-- pattern with a bracket in it, and a bare `[)]` is the syntax error it is on sh
-- (write `[\)]`). Until 0.7.0 ")" was not an operator here and was taken off the
-- end of the pattern word, which is how `echo (hi)` used to print its brackets.

local function parseCase(P, depth)
	local line = take(P).line
	local subject = wordAt(P)
	if subject == nil then
		return nil, unexpected(peek(P)), peek(P).line
	end
	P.i = P.i + 1
	local inWord = wordAt(P)
	if inWord == nil or inWord.plain ~= "in" then
		return nil, unexpected(peek(P), "in"), peek(P).line
	end
	P.i = P.i + 1

	local clauses = {}
	while true do
		skipSeparators(P)
		local t = wordAt(P)
		if t ~= nil and t.plain == "esac" then
			P.i = P.i + 1
			return { k = "case", line = line, word = subject.parts, clauses = clauses }
		end
		-- The file ran out where a pattern or the esac should be, and what is missing
		-- is the esac -- not the bracket the pattern loop below would name.
		if peek(P).t == "eof" then
			return nil, unexpected(peek(P), "esac"), peek(P).line
		end

		-- The patterns of one clause: the "(" POSIX allows in front, then words
		-- with "|" between them, then the ")" that closes the list -- all three
		-- operators (parser.c: `if (lasttoken == TLP) readtoken()`, then TPIPE
		-- between the words and TRP after them).
		local pats = {}
		local open = peek(P)
		if open.t == "op" and open.v == "(" then P.i = P.i + 1 end
		while true do
			local w = wordAt(P)
			if w == nil then
				return nil, unexpected(peek(P), ")"), peek(P).line
			end
			P.i = P.i + 1
			pats[#pats + 1] = w.parts
			local sep = peek(P)
			if sep.t == "op" and sep.v == ")" then
				P.i = P.i + 1
				break
			end
			if not (sep.t == "op" and sep.v == "|") then
				return nil, unexpected(sep, ")"), sep.line
			end
			P.i = P.i + 1
			skipNewlines(P)
		end

		-- A ")" stops the body too, so that a stray one is a clause that never
		-- ended, as parser.c has it (list(), then synexpect(TENDCASE)): dash
		-- says `")" unexpected (expecting ";;")` for `case ) in [)]) ...`.
		local body, reason, where =
			parseProgram(P, { [";;"] = true, ["esac"] = true, [")"] = true }, depth + 1)
		if body == nil then return nil, reason, where end
		clauses[#clauses + 1] = { pats = pats, body = body }

		local nx = peek(P)
		if nx.t == "op" and nx.v == ";;" then
			P.i = P.i + 1
		elseif not (nx.t == "word" and nx.plain == "esac") then
			-- POSIX lets the LAST clause drop its ";;" before the esac, and only the
			-- last one: anything else here is a clause that never ended. The end of the
			-- file is the other way of getting here and it is a different mistake --
			-- what is missing there is the esac.
			if nx.t == "eof" then
				return nil, unexpected(nx, "esac"), nx.line
			end
			return nil, unexpected(nx, ";;"), nx.line
		end
	end
end

--
-- A function definition
--
-- `name() { list; }`, POSIX.2's shape and the one every sh has taken since the
-- seventh edition. `(` and `)` are operators and end a word (XCU 2.3 rule 6,
-- 2.9.5 `fname ( ) compound-command`), so the blanks around them are free:
-- `t(){`, `t() {`, `t (){`, `t ( ) {` and a `{` on the next line are all the same
-- definition on dash, and here.
--
-- `{` is a reserved word, not an operator: it needs a blank after it, and
-- `t(){echo a;}` is a syntax error on dash ("}" unexpected) and here. The body is
-- any compound command, as POSIX.2 XCU 2.9.5 and 4.4BSD sh's parser.c
-- (`n->nfunc.body = command()`) have it: a brace group most of the time, and
-- `f() ( list )`, `f() if ...; fi` or a loop. A simple command is not one:
-- XCU 2.9.5's grammar is `function_body : compound_command`, so `f() echo x`
-- is `word unexpected (expecting "{")` here, though parser.c and dash take it.
--
-- The SOURCE of the definition travels with it (`src`). The console keeps a
-- function between one line and the next, and what it keeps has to survive being
-- written to a save file and handed back -- so what it keeps is the text, bounded
-- and checked like a variable's value, and the body is read out of it by this
-- parser. A parsed program handed back out of modData is the one thing this machine
-- will not do.
local function parseFunc(P, depth, name, tokens, braced)
	local line = P.tokens[P.i].line
	local at = P.tokens[P.i].at
	P.i = P.i + tokens
	if not braced then
		skipNewlines(P)
		-- Any other compound command: `f() ( list )` runs in a copy of the
		-- shell at every call, and a redirect after its ")" is the call's.
		-- The body is a program of that one command, and the source ends
		-- on its last token, a ")" or the done, fi or esac that closed it.
		local lp = peek(P)
		local w = wordAt(P)
		if (lp.t == "op" and lp.v == "(") or (w ~= nil and (w.plain == "if"
				or w.plain == "for" or w.plain == "while" or w.plain == "until"
				or w.plain == "case")) then
			local node, reason, where = parsePiece(P, depth)
			if node == nil then return nil, reason, where end
			local last = P.tokens[P.i - 1]
			local src = string.sub(P.text or "", at, last.stop or at)
			if #src > CeroSecOS.MAX_FUNC_BYTES then
				return nil, "function too large", line
			end
			return { k = "func", line = line, name = name, body = { node }, src = src }
		end
		local open = wordAt(P)
		if open == nil or open.plain ~= "{" then
			return nil, unexpected(peek(P), "{"), peek(P).line
		end
		P.i = P.i + 1
	end
	local brace = P.i - 1
	local body, reason, where = parseProgram(P, { ["}"] = true }, depth + 1)
	if body == nil then return nil, reason, where end
	local empty, eline = emptyList(P, body)
	if empty ~= nil then return nil, empty, eline end
	local close = wordAt(P)
	if close == nil or close.plain ~= "}" then
		return nil, unexpected(peek(P), "}"), peek(P).line
	end
	P.i = P.i + 1
	-- `f() { list; } > o`: XCU 2.9.5 `function_body : compound_command
	-- redirect_list`, and 4.4BSD-Lite2 parser.c's command() reads the
	-- redirects after the TEND and wraps the brace list in an NREDIR, so
	-- they are the body's and are opened at every call, inside any the
	-- call itself names (`f > p` still writes o, as on dash). Here the
	-- body is read again as the brace group it is, which takes them; the
	-- source ends on the last one, so a save hands them back.
	if peek(P).t == "redir" then
		P.i = brace
		local node, reason, where = parseGroup(P, depth)
		if node == nil then return nil, reason, where end
		body = { node }
		close = P.tokens[P.i - 1]
	end
	local src = string.sub(P.text or "", at, close.stop or at)
	if #src > CeroSecOS.MAX_FUNC_BYTES then
		return nil, "function too large", line
	end
	return { k = "func", line = line, name = name, body = body, src = src }
end

-- Is what is next a function definition, and what is its name? nil when it is not
-- one, so the caller goes on to read an ordinary command. Else the name and the
-- three tokens that spell `name ( )`. A NAME followed by "(" and anything but ")"
-- is "bad": parser.c reads TLP after a word as a definition and asks for TRP
-- (`if (readtoken() != TRP) synexpect(TRP)`).
--
-- A reserved word is not a name: `if() { :; }` is a syntax error on a real sh and is
-- one here, because `if` is grammar and cannot be a command. A quoted word has no
-- plain text: `"t" ()` is a command followed by a stray bracket.
local function funcAhead(P)
	local t = wordAt(P)
	if t == nil or t.plain == nil then return nil end
	local lp = P.tokens[P.i + 1]
	if lp == nil or lp.t ~= "op" or lp.v ~= "(" then return nil end
	local name = string.match(t.plain, "^[A-Za-z_][A-Za-z0-9_]*$")
	if name == nil or CeroSecOS.RESERVED[name] then return nil end
	local rp = P.tokens[P.i + 2]
	if rp == nil or rp.t ~= "op" or rp.v ~= ")" then return name, 2, "bad" end
	return name, 3, false
end

-- `{ list; }` and `( list )`: a brace group, run in this shell, and a subshell, run
-- in a copy of it (POSIX.2 XCU 2.9.4; 4.4BSD-Lite2 sh's NBRACE and NSUBSHELL,
-- parser.c's command()). `{` and `}` are reserved words -- only where a command
-- starts, so `echo {` and `echo a }` print their braces -- and `(` `)` operators.
-- A list is at least one command in either (the "}" or ")" unexpected dash gives
-- `{ }` and `( )`), and what follows the closer is a redirect or the end of the
-- command: `{ echo; } foo` is `word unexpected`, as on sh.
parseGroup = function(P, depth)
	local open = take(P)
	local sub = open.t == "op"
	local closer = "}"
	if sub then closer = ")" end
	local body, reason, where
	if sub then
		body, reason, where = parseProgram(P, { [")"] = true }, depth + 1)
	else
		body, reason, where = parseProgram(P, { ["}"] = true }, depth + 1)
	end
	if body == nil then return nil, reason, where end
	local empty, eline = emptyList(P, body)
	if empty ~= nil then return nil, empty, eline end
	local close = peek(P)
	local closed
	if sub then
		closed = close.t == "op" and close.v == ")"
	else
		closed = close.t == "word" and close.plain == "}"
	end
	if not closed then return nil, unexpected(close, closer), close.line end
	P.i = P.i + 1
	local node = { k = "group", line = open.line, body = body, sub = sub, words = {} }
	local st = { fds = { "1", "2" }, seen = {} }
	while peek(P).t == "redir" do
		local r, rline = takeRedirect(P, st)
		if r ~= nil then return nil, r, rline end
	end
	node.redirect = st.redirect
	if st.seen[2] or st.fds[1] ~= (st.redirect ~= nil and "w" or "1") then
		node.errRedirect = st.errRedirect
		node.out = st.fds[1]
		node.err = st.fds[2]
	end
	return node
end

parsePiece = function(P, depth)
	if depth > CeroSecOS.MAX_NEST then
		return nil, "too deeply nested", peek(P).line
	end
	local t = wordAt(P)
	if t ~= nil and t.plain ~= nil then
		if t.plain == "if" then return parseIf(P, depth) end
		if t.plain == "for" then return parseFor(P, depth) end
		if t.plain == "while" or t.plain == "until" then return parseLoop(P, depth) end
		if t.plain == "case" then return parseCase(P, depth) end
	end
	if (t ~= nil and t.plain == "{") or (peek(P).t == "op" and peek(P).v == "(") then
		return parseGroup(P, depth)
	end
	local fname, fwords, braced = funcAhead(P)
	if braced == "bad" then
		local at = P.tokens[P.i + fwords]
		return nil, unexpected(at, ")"), at.line
	end
	if fname ~= nil then return parseFunc(P, depth, fname, fwords, braced) end
	return parseSimple(P)
end

-- A pipeline: one or more pieces with "|" between them. It binds tighter than
-- "&&" and "||", the way every shell binds it, so `a | b && c` is the pipeline
-- and then c.
local function parsePipeline(P, depth)
	local first, reason, where = parsePiece(P, depth)
	if first == nil then return nil, reason, where end

	local stages = { first }
	while true do
		local t = peek(P)
		if not (t.t == "op" and t.v == "|") then break end
		P.i = P.i + 1
		-- A newline after "|" is a line that is not finished, exactly as it is
		-- after "&&": the pipeline goes on.
		skipNewlines(P)
		local next_, nreason, nwhere = parsePiece(P, depth)
		if next_ == nil then return nil, nreason, nwhere end
		if #stages >= CeroSecOS.MAX_STAGES then
			return nil, "too many stages", t.line
		end
		stages[#stages + 1] = next_
	end

	if #stages == 1 then return first end
	return { k = "pipe", line = first.line, stages = stages }
end

local function parseAndOr(P, depth)
	local first, reason, where = parsePipeline(P, depth)
	if first == nil then return nil, reason, where end

	local items, ops = { first }, {}
	while true do
		local t = peek(P)
		if t.t == "op" and (t.v == "&&" or t.v == "||") then
			P.i = P.i + 1
			skipNewlines(P)
			local next_, nreason, nwhere = parsePipeline(P, depth)
			if next_ == nil then return nil, nreason, nwhere end
			ops[#items] = t.v
			items[#items + 1] = next_
		else
			break
		end
	end

	local bg = false
	local t = peek(P)
	if t.t == "op" and t.v == "&" then
		P.i = P.i + 1
		bg = true
		-- An ampersand ends the statement as surely as a semicolon does, so
		-- `sh a & sh b` is two statements and not a syntax error.
		P.terminated = true
	end

	if #items == 1 and not bg then return first end
	return { k = "list", line = first.line, items = items, ops = ops, bg = bg }
end

-- prog, or nil plus a reason and a line. Stops on any reserved word in stops,
-- leaving it for the caller to consume.
parseProgram = function(P, stops, depth)
	local prog = {}
	while true do
		skipSeparators(P)
		local t = peek(P)
		if t.t == "eof" then break end
		if stopsHere(t, stops) then break end

		P.terminated = false
		local st, reason, where = parseAndOr(P, depth)
		if st == nil then return nil, reason, where end
		prog[#prog + 1] = st

		local nx = peek(P)
		if nx.t == "eof" then break end
		if stopsHere(nx, stops) then break end
		if P.terminated then
			-- nothing: "&" already closed the statement
		elseif not (nx.t == "op" and (nx.v == ";" or nx.v == "\n")) then
			return nil, unexpected(nx), nx.line
		end
	end
	return prog
end

--
-- The one entry point.
--
-- text -> program, or nil plus the reason and the line it is on. depth is the
-- command-substitution level and is the parser's own business: a caller passes
-- nothing.
--
function CeroSecOS.parseScript(text, depth)
	if type(text) ~= "string" then return nil, "Syntax error: end of file unexpected", 1 end
	depth = depth or 0

	local tokens, reason, line = tokenize(text, depth)
	if tokens == nil then return nil, reason, line end

	local P = { tokens = tokens, i = 1, text = text }
	local prog, preason, pline = parseProgram(P, {}, 1)
	if prog == nil then return nil, preason, pline end

	local last = peek(P)
	if last.t ~= "eof" then
		return nil, unexpected(last), last.line
	end
	return prog
end

-- What the shell prints when a script will not parse: the file, the line and
-- the reason, in the order every Unix has printed them. A syntax error is
-- 4.4BSD-Lite2 sh's synerror() to the letter (parser.c: "%s: %d: " and then
-- "Syntax error: %s"), the line a bare number. Every OTHER error in a file
-- keeps this machine's "line N:" -- sh's error() printed no line at all,
-- and a script's author has nothing else to find the line by (the
-- "sh" entry of CeroSecOS.DEVIATIONS).
function CeroSecOS.isSyntaxError(reason)
	return type(reason) == "string" and string.sub(reason, 1, 13) == "Syntax error:"
end

function CeroSecOS.scriptError(name, reason, line)
	if CeroSecOS.isSyntaxError(reason) then
		return tostring(name) .. ": " .. tostring(line or 1) .. ": " .. reason
	end
	return tostring(name) .. ": line " .. tostring(line or 1) .. ": " .. tostring(reason)
end
