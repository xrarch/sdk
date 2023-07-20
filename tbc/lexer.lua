local preproc = require("preproc")

-- this is a modified rewrite in lua of the MCL.DLL lexer from MINTIA.

local lexer = {}

local CHAR_NORMAL   = nil
local CHAR_COALESCE = 1
local CHAR_SPLIT    = 2

local chartreatment = {
	["^"] = CHAR_SPLIT,
	["("] = CHAR_SPLIT,
	[")"] = CHAR_SPLIT,
	["~"] = CHAR_SPLIT,
	[","] = CHAR_SPLIT,
	["["] = CHAR_SPLIT,
	["]"] = CHAR_SPLIT,
	[":"] = CHAR_SPLIT,
	["{"] = CHAR_SPLIT,
	["}"] = CHAR_SPLIT,

	["="] = CHAR_COALESCE,
	["&"] = CHAR_COALESCE,
	["|"] = CHAR_COALESCE,
	["!"] = CHAR_COALESCE,
	["<"] = CHAR_COALESCE,
	[">"] = CHAR_COALESCE,
	["+"] = CHAR_COALESCE,
	["-"] = CHAR_COALESCE,
	["*"] = CHAR_COALESCE,
	["/"] = CHAR_COALESCE,
	["%"] = CHAR_COALESCE,
	["."] = CHAR_COALESCE,
	["@"] = CHAR_COALESCE,
	["$"] = CHAR_COALESCE,
}

function lexer.new(filename, file, incdir, libdir, symbols)
	local lex = {}

	lex.srctext = preproc.pp(filename, file, incdir, libdir, symbols, true)

	if not lex.srctext then return false end

	lex.ungetstack = {}

	lex.length = #lex.srctext

	lex.position = 0
	lex.linenumber = 1
	lex.filename = filename
	lex.newline = true

	lex.lastposition = 0
	lex.lastlinenumber = 1
	lex.lastfilename = filename

	function lex.nextCharRaw()
		-- return the next character at the current position in the input
		-- stream.

		local lastln = lex.linenumber
		local lastpos
		local char

		if lex.position >= lex.length then
			if lex.newline then
				return false
			end

			-- try to fix it up so we see a newline at the end of the file,
			-- even though there isn't one.

			lastpos = lex.position
			lex.position = lex.position + 1
			lex.linenumber = lex.linenumber + 1
			lex.newline = true

			char = "\n"

			return char, lastpos, lastln
		end

		lastpos = lex.position

		char = lex.srctext:sub(lex.position+1, lex.position+1)

		lex.position = lex.position + 1

		if char == "\n" then
			lex.linenumber = lex.linenumber + 1
			lex.newline = true
		else
			lex.newline = false
		end

		return char, lastpos, lastln
	end

	function lex.nextChar()
		-- return next character with processing for the # directives from the
		-- preprocessor, which tell us the boundaries between files and lets
		-- us update line numbers appropriately.

		local lastfn = lex.filename
		local nl = lex.newline

		local char, lastpos, lastln = lex.nextCharRaw()

		if not nl then
			return char, lastpos, lastln, lastfn
		end

		if char ~= "#" then
			return char, lastpos, lastln, lastfn
		end

		-- we have a directive, consume it.

		local directive = ""

		while char ~= "\n" do
			directive = directive .. char

			char = lex.nextCharRaw()
		end

		directive = directive:sub(2)

		local dirt = explode(" ", directive)

		if #dirt ~= 2 then
			return char, lastpos, lastln, lastfn
		end

		if not tonumber(dirt[2]) then
			return char, lastpos, lastln, lastfn
		end

		lastfn = lex.filename
		lex.filename = dirt[1]
		lex.linenumber = tonumber(dirt[2])

		return char, lastpos, lastln, lastfn
	end

	local LEXSTATE_NORMAL  = 1
	local LEXSTATE_STRING  = 2
	local LEXSTATE_CHARLIT = 3

	function lex.nextTokenRaw()
		-- return a table representing a token, or nil if no next token.
		-- NOTE: this is not done, but reserved keywords can be enforced more
		-- strictly here than they are by the parser, by tagging a token as a
		-- keyword. Do this in the actual self-hosted TOWER compiler. This can
		-- be done in linear time, inline with token scanning, with a trie.
		-- NOTE: double-quote string termination isn't checked either, the
		-- string token terminates when EOF is reached.
		-- NOTE: the lexer should probably cache a lookahead token instead of
		-- the general purpose mechanism which actually isn't necessary for
		-- Tower's grammar, this would be faster and should be done in the
		-- self-hosted compiler.

		if #lex.ungetstack > 0 then
			return table.remove(lex.ungetstack)
		end

		local firstpos = 0
		local firstln = 0
		local firstfn = false
		local nolastyet = true
		local ignorewhitespace = true
		local isbackslash = false
		local coalescechar = false
		local state = LEXSTATE_NORMAL

		local token = {}
		token.str = ""
		token.value = nil
		token.length = 0
		token.eof = false
		token.newline = false
		token.literal = false
		token.charliteral = false
		token.linenumber = lex.linenumber
		token.filename = lex.filename

		function add(char)
			token.str = token.str .. char
			token.length = token.length + 1
		end

		while true do
			::continue::

			local char, lastpos, lastln, lastfn = lex.nextChar()

			if not char then
				break
			end

			if nolastyet then
				token.linenumber = lex.linenumber
				token.filename = lex.filename

				firstpos = lastpos
				firstln = lastln
				firstfn = lastfn
				nolastyet = false
			end

			if isbackslash then
				isbackslash = false

				if char == "\n" then
					goto continue
				end

				local ch

				if char == "n" then
					ch = "\n"
				elseif char == "r" then
					ch = string.char(0xD)
				elseif char == "t" then
					ch = "\t"
				elseif char == "b" then
					ch = "\b"
				elseif char == "[" then
					ch = string.char(0x1B)
				else
					ch = char
				end

				add(ch)

				if state == LEXSTATE_CHARLIT then
					token.value = token.value * 256 + string.byte(ch)
				end

				goto continue
			elseif char == "\\" then
				isbackslash = true
				goto continue
			end

			if state == LEXSTATE_NORMAL then
				if char == "\n" then
					token.newline = true
					break
				end

				if (char == " ") or (char == "\t") then
					if ignorewhitespace then
						goto continue
					else
						break
					end
				end

				ignorewhitespace = false

				if char == "\"" then
					if token.length ~= 0 then
						lex.position = lastpos
						lex.linenumber = lastln
						lex.filename = lastfn

						break
					end

					token.literal = true
					state = LEXSTATE_STRING

					goto continue
				elseif char == "'" then
					if token.length ~= 0 then
						lex.position = lastpos
						lex.linenumber = lastln
						lex.filename = lastfn

						break
					end

					token.charliteral = true
					token.value = 0
					state = LEXSTATE_CHARLIT

					goto continue
				end

				local tmt = chartreatment[char]

				if tmt == CHAR_COALESCE then
					if coalescechar then
						add(char)
						goto continue
					end

					if token.length ~= 0 then
						lex.position = lastpos
						lex.linenumber = lastln
						lex.filename = lastfn

						break
					end

					coalescechar = true

					add(char)

					goto continue
				elseif coalescechar then
					lex.position = lastpos
					lex.linenumber = lastln
					lex.filename = lastfn

					break
				end

				if tmt == CHAR_SPLIT then
					if (token.length ~= 0) or token.literal then
						lex.position = lastpos
						lex.linenumber = lastln
						lex.filename = lastfn

						break
					end
				end

				add(char)

				if tmt == CHAR_SPLIT then
					char, lastpos, lastln, lastfn = lex.nextChar()

					if not char then
						break
					end

					if char == "\n" then
						token.newline = true
					elseif (char ~= " ") and (char ~= "\t") then
						lex.position = lastpos
						lex.linenumber = lastln
						lex.filename = lastfn
					end

					break
				end
			elseif state == LEXSTATE_STRING then
				if char == "\"" then
					break
				end

				add(char)
			elseif state == LEXSTATE_CHARLIT then
				if char == "'" then
					break
				end

				if char == "\\" then
					isbackslash = true
					goto continue
				end

				add(char)

				token.value = token.value * 256 + string.byte(char)
			end
		end

		if not nolastyet then
			lex.lastposition = firstpos
			lex.lastlinenumber = firstln
			lex.lastfilename = firstfn
		end

		if (token.length == 0) and not token.newline then
			token.eof = true
		elseif (not token.literal) and (not token.charliteral) then
			token.value = tonumber(token.str)
		end

		if token.value then
			token.str = nil
		end

		return token
	end

	function lex.nextToken()
		while true do
			local token = lex.nextTokenRaw()

			if token.eof then
				return token
			end

			if token.length ~= 0 then
				return token
			end

			if token.literal then
				return token
			end
		end
	end

	function lex.lastToken(token)
		-- un-consume the last token so that it will be returned again
		-- by nextToken in an identical fashion to the last time it was
		-- returned.

		lex.ungetstack[#lex.ungetstack + 1] = token
	end

	return lex
end

return lexer