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
--   piece     := if | for | while | until | case | func | simple
--   if        := "if" program "then" program
--                ("elif" program "then" program)* [ "else" program ] "fi"
--   for       := "for" NAME [ "in" word* ] (";"|newline) "do" program "done"
--   while     := "while" program "do" program "done"
--   until     := "until" program "do" program "done"
--   case      := "case" word "in" clause* "esac"
--   clause    := [ "(" ] word ( "|" word )* ")" program [ ";;" ]
--   func      := NAME "()" "{" program "}"
--   simple    := word* [ (">"|">>") word ]
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
-- "done"; `done` on its own is the end of a loop, or a mistake.
CeroSecOS.RESERVED = {
	["if"] = true, ["then"] = true, ["elif"] = true, ["else"] = true, ["fi"] = true,
	["for"] = true, ["in"] = true, ["while"] = true, ["until"] = true,
	["do"] = true, ["done"] = true,
	["case"] = true, ["esac"] = true,
}

local function isNameStart(c)
	return c ~= "" and string.find(c, "^[A-Za-z_]") ~= nil
end

local function isNameChar(c)
	return c ~= "" and string.find(c, "^[A-Za-z0-9_]") ~= nil
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
	if depth > 0 then return nil, "syntax error: bad substitution" end
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
			return nil, "syntax error: bad substitution"
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
	return nil, "syntax error: bad substitution"
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
	if depth > 0 then return nil, "syntax error: bad substitution" end
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
	return nil, "syntax error: bad substitution"
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
							return nil, "syntax error: bad substitution"
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
			return nil, "syntax error: bad substitution"
		end

		local prog, second = readCommandSub(text, i, depth)
		if prog == nil then return nil, second end
		return { t = "sub", prog = prog, q = quoted }, second
	end

	if c == "{" then
		local j = i + 2
		local name = ""
		while j <= n and string.sub(text, j, j) ~= "}" do
			name = name .. string.sub(text, j, j)
			j = j + 1
		end
		if j > n then return nil, "syntax error: bad substitution" end
		if not CeroSecOS.isVarName(name) then return nil, "syntax error: bad substitution" end
		return { t = "var", name = name, q = quoted }, j + 1
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
					or after == ">" or after == "<"
				if (d ~= "1" and d ~= "2") or not ends then
					return nil, "syntax error: bad redirect", line
				end
				dup = 1
				if d == "2" then dup = 2 end
				i = i + 2
			end
			tokens[#tokens + 1] = { t = "redir", append = append, fd = fd, dup = dup, line = line }
		elseif c == "<" then
			return nil, "syntax error: unexpected '<'", line
		else
			-- One word: bare text, quoted runs and expansions, until a blank or
			-- an operator ends it.
			local parts = {}
			local startLine = line
			while i <= n do
				local ch = string.sub(text, i, i)
				if ch == " " or ch == "\t" or ch == "\r" or ch == "\n" or ch == ";"
						or ch == "&" or ch == "|" or ch == ">" or ch == "<" then
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
						return nil, "syntax error: unterminated quote", startLine
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
								return nil, "syntax error: unterminated quote", startLine
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
						return nil, "syntax error: unterminated quote", startLine
					end
				elseif ch == "\\" then
					local nx = string.sub(text, i + 1, i + 1)
					if nx == "" then return nil, "syntax error: unterminated quote", startLine end
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

-- How a token is named in an error, the way a shell names it.
local function describe(t)
	if t.t == "eof" then return "end of file" end
	if t.t == "op" then
		if t.v == "\n" then return "end of line" end
		return "'" .. t.v .. "'"
	end
	if t.t == "redir" then
		if t.append then return "'>>'" end
		return "'>'"
	end
	if t.plain ~= nil then return "'" .. t.plain .. "'" end
	return "word"
end

-- Is this token one the caller asked to be left alone? A reserved word in `stops`,
-- or the ";;" that ends a case clause -- which is an OPERATOR and not a word, and
-- is the one operator any caller has ever needed to stop at.
local function stopsHere(t, stops)
	if t.t == "word" and t.plain ~= nil and stops[t.plain] then return true end
	if t.t == "op" and t.v == ";;" and stops[";;"] then return true end
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

-- A word token, or nil when what is next is not one.
local function wordAt(P)
	local t = peek(P)
	if t.t ~= "word" then return nil end
	return t
end

local function parseSimple(P)
	local words, redirect, errRedirect = {}, nil, nil
	-- Where each descriptor ends up, worked out in the order the line names them,
	-- which is sh(1)'s rule and the whole difference between `> f 2>&1` (both
	-- into f) and `2>&1 > f` (errors where the output WAS, the output into f).
	-- "1" and "2" are the ones the command was started with, "w" the file ">"
	-- names and "e" the file "2>" names.
	local fds = { "1", "2" }
	local seen = {}
	local line = peek(P).line
	while true do
		local t = peek(P)
		if t.t == "word" then
			-- Reserved words are only reserved where a command starts; every
			-- other position is an ordinary argument, so `echo done` prints it.
			if #words == 0 and t.plain ~= nil and CeroSecOS.RESERVED[t.plain] then
				return nil, "syntax error: unexpected '" .. t.plain .. "'", t.line
			end
			words[#words + 1] = t.parts
			P.i = P.i + 1
		elseif t.t == "redir" then
			-- One redirect per descriptor: a second one is a line that says two
			-- things about the same place, and this machine does not guess which.
			local fd = t.fd or 1
			if seen[fd] then
				return nil, "syntax error: bad redirect", t.line
			end
			seen[fd] = true
			P.i = P.i + 1
			if t.dup ~= nil then
				fds[fd] = fds[t.dup]
			else
				local target = wordAt(P)
				if target == nil then
					return nil, "syntax error: missing redirect target", t.line
				end
				P.i = P.i + 1
				if fd == 2 then
					errRedirect = { word = target.parts, append = t.append }
					fds[2] = "e"
				else
					redirect = { word = target.parts, append = t.append }
					fds[1] = "w"
				end
			end
		else
			break
		end
	end
	if #words == 0 and not seen[1] and not seen[2] then
		local t = peek(P)
		return nil, "syntax error: unexpected " .. describe(t), t.line
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
-- words this shell already says it with. Only a list that stopped on a WORD is
-- refused here: one that ran into the end of the file is missing its closing word,
-- which the caller goes on to say.
local function emptyList(P, prog)
	if #prog > 0 then return nil end
	local t = peek(P)
	if t.t == "eof" then return nil end
	return "syntax error: unexpected " .. describe(t), t.line
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
			return nil, "syntax error: missing 'then'", peek(P).line
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
				return nil, "syntax error: missing 'fi'", peek(P).line
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
		return nil, "syntax error: missing 'do'", peek(P).line
	end
	P.i = P.i + 1
	local body, reason, where = parseProgram(P, { ["done"] = true }, depth + 1)
	if body == nil then return nil, reason, where end
	local empty, eline = emptyList(P, body)
	if empty ~= nil then return nil, empty, eline end
	local nx = wordAt(P)
	if nx == nil or nx.plain ~= "done" then
		return nil, "syntax error: missing 'done'", peek(P).line
	end
	P.i = P.i + 1
	return body
end

local function parseFor(P, depth)
	local line = take(P).line
	local name = wordAt(P)
	if name == nil or name.plain == nil or not CeroSecOS.isVarName(name.plain) then
		return nil, "syntax error: not a name", peek(P).line
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
-- `case word in pattern) ... ;; esac`, POSIX.2's own shape, and the one construct
-- whose grammar needs a bracket. ")" is NOT an operator on this machine -- it never
-- was, there being no subshell grouping here, and making one of it now would turn
-- every `echo (hi)` a survivor has already written into a syntax error -- so the
-- ")" that closes a pattern is taken off the END of the pattern word instead.
--
-- That reading is not a shortcut, it is the right one: only an UNQUOTED ")" closes a
-- pattern, so `"a)"` is a pattern with a bracket in it and `[)]` is a set holding
-- one, and both come out right because the strip asks whether the last piece of the
-- word was bare literal text (`bare`, which the tokenizer already records for
-- exactly this kind of question).
--
-- The leading "(" POSIX allows before a pattern is taken off the front the same way.

-- The ")" at the end of a pattern word, removed. false when the word does not end
-- in one, which is how the caller knows to go on looking.
local function takeClose(parts)
	local last = parts[#parts]
	if last == nil or last.t ~= "lit" or not last.bare then return false end
	if string.sub(last.s, #last.s) ~= ")" then return false end
	last.s = string.sub(last.s, 1, #last.s - 1)
	-- A part that is nothing but the bracket goes with it, unless it is the whole
	-- word: `)` on its own is the pattern that matches an empty word.
	if last.s == "" and #parts > 1 then parts[#parts] = nil end
	return true
end

-- And the "(" POSIX allows in front of one.
local function takeOpen(parts)
	local first = parts[1]
	if first == nil or first.t ~= "lit" or not first.bare then return end
	if string.sub(first.s, 1, 1) ~= "(" then return end
	first.s = string.sub(first.s, 2)
	if first.s == "" and #parts > 1 then table.remove(parts, 1) end
end

local function parseCase(P, depth)
	local line = take(P).line
	local subject = wordAt(P)
	if subject == nil then
		return nil, "syntax error: unexpected " .. describe(peek(P)), peek(P).line
	end
	P.i = P.i + 1
	local inWord = wordAt(P)
	if inWord == nil or inWord.plain ~= "in" then
		return nil, "syntax error: missing 'in'", peek(P).line
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
			return nil, "syntax error: missing 'esac'", peek(P).line
		end

		-- The patterns of one clause: words with "|" between them, the last of them
		-- carrying the ")" that closes the list.
		local pats = {}
		local closed = false
		while true do
			local w = wordAt(P)
			if w == nil then
				return nil, "syntax error: missing ')'", peek(P).line
			end
			P.i = P.i + 1
			if #pats == 0 then takeOpen(w.parts) end
			closed = takeClose(w.parts)
			pats[#pats + 1] = w.parts
			if closed then break end
			local sep = peek(P)
			if not (sep.t == "op" and sep.v == "|") then
				return nil, "syntax error: missing ')'", sep.line
			end
			P.i = P.i + 1
			skipNewlines(P)
		end

		local body, reason, where =
			parseProgram(P, { [";;"] = true, ["esac"] = true }, depth + 1)
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
				return nil, "syntax error: missing 'esac'", nx.line
			end
			return nil, "syntax error: missing ';;'", nx.line
		end
	end
end

--
-- A function definition
--
-- `name() { list; }`, POSIX.2's shape and the one every sh has taken since the
-- seventh edition. In sh `(` and `)` are operators and end a word (XCU 2.3 rule 6,
-- 2.9.5 `fname ( ) compound-command`), so the blanks around them are free:
-- `t(){`, `t() {`, `t (){`, `t ( ) {` and a `{` on the next line are all the same
-- definition on dash. This tokenizer does not split on them -- `(` means nothing
-- anywhere else on this machine and `echo (a)` is kept -- so funcAhead glues the
-- words back together where a definition begins instead.
--
-- `{` is a reserved word, not an operator: it needs a blank after it, and
-- `t(){echo a;}` is a syntax error on dash ("}" unexpected) and here.
--
-- The braces are NOT made reserved words. `{` and `}` are POSIX reserved words, and
-- making them so here would mean a brace group (`{ list; }` as a command) this
-- machine has not got and a refusal for every `echo {` already written. What is
-- needed instead is that `}` stops the body, and that falls out of the stops table
-- parseProgram already takes: a reserved word is only one where a command starts, so
-- `echo done }` prints the brace exactly as a real sh does and the body ends at the
-- `}` that begins a statement.
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
		local open = wordAt(P)
		if open == nil or open.plain ~= "{" then
			return nil, "syntax error: missing '{'", peek(P).line
		end
		P.i = P.i + 1
	end
	local body, reason, where = parseProgram(P, { ["}"] = true }, depth + 1)
	if body == nil then return nil, reason, where end
	local empty, eline = emptyList(P, body)
	if empty ~= nil then return nil, empty, eline end
	local close = wordAt(P)
	if close == nil or close.plain ~= "}" then
		return nil, "syntax error: missing '}'", peek(P).line
	end
	P.i = P.i + 1
	local src = string.sub(P.text or "", at, close.stop or at)
	if #src > CeroSecOS.MAX_FUNC_BYTES then
		return nil, "function too large", line
	end
	return { k = "func", line = line, name = name, body = body, src = src }
end

-- Is what is next a function definition, and what is its name? nil when it is not
-- one, so the caller goes on to read an ordinary command. Else the name, how many
-- words spell `name ( )`, and whether the last of them already carried the `{`.
--
-- The bare words on the line are read one after another and joined, blanks
-- dropped, for as long as the join is still the start of `name(){`. `name()` is a
-- definition; `name(){` is one with its brace; `name()` and anything else glued on
-- (`t(){echo`) is one whose brace is missing, the syntax error it is on a real sh.
-- A quoted word has no plain text and ends the join: `t "()"` is a command.
--
-- A reserved word is not a name: `if() { :; }` is a syntax error on a real sh and is
-- one here, because `if` is grammar and cannot be a command.
local function funcAhead(P)
	local t = wordAt(P)
	if t == nil or t.plain == nil then return nil end
	local name = string.match(t.plain, "^([A-Za-z_][A-Za-z0-9_]*)")
	if name == nil or CeroSecOS.RESERVED[name] then return nil end
	local joined = ""
	local n = 0
	while true do
		local w = P.tokens[P.i + n]
		if w == nil or w.t ~= "word" or w.plain == nil then return nil end
		joined = joined .. w.plain
		n = n + 1
		local rest = string.sub(joined, #name + 1)
		if string.sub(joined, 1, #name) ~= name then return nil end
		if rest == "()" then return name, n, false end
		if rest == "(){" then return name, n, true end
		if string.sub(rest, 1, 2) == "()" then return name, n, "bad" end
		if rest ~= "" and rest ~= "(" then return nil end
	end
end

local function parsePiece(P, depth)
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
	local fname, fwords, braced = funcAhead(P)
	if braced == "bad" then
		return nil, "syntax error: missing '{'", P.tokens[P.i].line
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
			return nil, "syntax error: unexpected " .. describe(nx), nx.line
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
	if type(text) ~= "string" then return nil, "syntax error", 1 end
	depth = depth or 0

	local tokens, reason, line = tokenize(text, depth)
	if tokens == nil then return nil, reason, line end

	local P = { tokens = tokens, i = 1, text = text }
	local prog, preason, pline = parseProgram(P, {}, 1)
	if prog == nil then return nil, preason, pline end

	local last = peek(P)
	if last.t ~= "eof" then
		return nil, "syntax error: unexpected " .. describe(last), last.line
	end
	return prog
end

-- What the shell prints when a script will not parse: the file, the line and
-- the reason, in the order every Unix has printed them.
function CeroSecOS.scriptError(name, reason, line)
	return tostring(name) .. ": line " .. tostring(line or 1) .. ": " .. tostring(reason)
end
