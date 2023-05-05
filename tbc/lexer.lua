local preproc = require("preproc")

local lexer = {}

function lexer.new(filename, file, incdir, libdir, symbols)
	local srctext = preproc.pp(filename, file, incdir, libdir, symbols, true)

	print(srctext)

	local lex = {}

	function lex.nextToken()
		-- return a table representing a token, or nil if no next token.

	end

	function lex.lastToken()
		-- un-consume the last token so that it will be returned again
		-- by nextToken in an identical fashion to the last time it was
		-- returned. this can only be done one step backwards in time, as the
		-- state necessary to fetch any tokens before that has been lost by
		-- now.

	end

	return lex
end

return lexer