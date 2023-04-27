require("sb")

local gen = {}

function gen.generate(filename, ast)
	gen.output = newsb()



	return gen.output.tostring()
end

return gen