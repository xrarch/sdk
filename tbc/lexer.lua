local preproc = require("preproc")

local lexer = {}

function lexer.new(filename, file, incdir, libdir, symbols)
	local srctext = preproc.pp(filename, file, incdir, libdir, symbols, true)

	print(srctext)

	local lex = {}



	return lex
end

return lexer