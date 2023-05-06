local lexer = require("lexer")

local parser = {}

function parser.parse(filename, file, incdir, libdir, symbols)
	local lex = lexer.new(filename, file, incdir, libdir, symbols)

	while true do
		local token = lex.nextToken()

		if token.eof then
			break
		end

		print(token.str, token.length, token.fileName, token.lineNumber)
	end

	local ast = {}



	return ast
end

return parser