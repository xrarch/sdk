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
	[":"] = CHAR_COALESCE,
	["."] = CHAR_COALESCE,
}

function lexer.new(filename, file, incdir, libdir, symbols)
	local lex = {}

	lex.srctext = preproc.pp(filename, file, incdir, libdir, symbols, true)

	if not lex.srctext then return false end

	lex.length = #lex.srctext

	lex.position = 0
	lex.lineNumber = 1
	lex.fileName = filename
	lex.newline = true

	lex.lastPosition = 0
	lex.lastLineNumber = 1
	lex.lastFileName = filename

	function lex.nextCharRaw()
		-- return the next character at the current position in the input
		-- stream.

		local lastln = lex.lineNumber
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
			lex.lineNumber = lex.lineNumber + 1
			lex.newline = true

			char = "\n"

			return char, lastpos, lastln
		end

		lastpos = lex.position

		char = lex.srctext:sub(lex.position+1, lex.position+1)

		lex.position = lex.position + 1

		if char == "\n" then
			lex.lineNumber = lex.lineNumber + 1
			lex.newline = true
		else
			lex.newline = false
		end

		return char, lastpos, lastln
	end

	function lex.nextChar()
		-- return next character with processing for the @ directives from the
		-- preprocessor.

		local lastfn = lex.fileName

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

		lastfn = lex.fileName
		lex.fileName = dirt[1]
		lex.lineNumber = tonumber(dirt[2])

		return char, lastpos, lastln, lastfn
	end

	local LEXSTATE_NORMAL = 1
	local LEXSTATE_STRING = 2

	function lex.nextToken()
		-- return a table representing a token, or nil if no next token.

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
		token.length = 0
		token.eof = false
		token.newline = false
		token.literal = false
		token.lineNumber = lex.lineNumber
		token.fileName = lex.fileName

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
				token.lineNumber = lex.lineNumber
				token.fileName = lex.fileName

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

				add(char)

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

				if char == "\\" then
					isbackslash = true
					goto continue
				end

				ignorewhitespace = false

				if char == "\"" then
					token.literal = true
					state = LEXSTATE_STRING
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
						lex.lineNumber = lastln
						lex.fileName = lastfn

						break
					end

					coalescechar = true

					add(char)

					goto continue
				elseif coalescechar then
					lex.position = lastpos
					lex.lineNumber = lastln
					lex.fileName = lastfn

					break
				end

				if tmt == CHAR_SPLIT then
					if (token.length ~= 0) or token.literal then
						lex.position = lastpos
						lex.lineNumber = lastln
						lex.fileName = lastfn

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
						lex.lineNumber = lastln
						lex.fileName = lastfn
					end

					break
				end
			elseif state == LEXSTATE_STRING then
				if char == "\"" then
					break
				end

				add(char)
			end
		end

		if not nolastyet then
			lex.lastPosition = firstpos
			lex.lastLineNumber = firstln
			lex.lastFileName = firstfn
		end

		if (token.length == 0) and not token.newline then
			token.eof = true
		end

		return token
	end

	function lex.nextNonemptyToken(stopnl)
		while true do
			local token = lex.nextToken()

			if token.eof then
				return token
			end

			if token.length ~= 0 then
				return token
			end

			if token.literal then
				return token
			end

			if stopnl and token.newline then
				return token
			end
		end
	end

	function lex.lastToken()
		-- un-consume the last token so that it will be returned again
		-- by nextToken in an identical fashion to the last time it was
		-- returned. this can only be done one step backwards in time, as the
		-- state necessary to fetch any tokens before that has been lost by
		-- now.

		lex.position = lex.lastPosition
		lex.lineNumber = lex.lastLineNumber
		lex.fileName = lex.lastFileName
		lex.newline = false
	end

	return lex
end

return lexer