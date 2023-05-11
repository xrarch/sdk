-- C generator for the TOWER Bootstrap Compiler

require("sb")

local gen = {}

function gen.generate(filename, ast)
	gen.output = newsb()

	tprint(ast)

	return gen.output.tostring()
end

return gen