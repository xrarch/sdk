local lexer = require("lexer")

local parser = {}

function parser.parse(filename, file, incdir, libdir, symbols)
	local lex = lexer.new(filename, file, incdir, libdir, symbols)

	local ast = {}



	return ast
end

return parser