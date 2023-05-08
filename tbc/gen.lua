local function tprint (tbl, indent)
	if not indent then indent = 0 end
	for k, v in pairs(tbl) do
		formatting = string.rep("  ", indent) .. k .. ": "
		if type(v) == "table" then
			print(formatting)
			tprint(v, indent+1)
		elseif type(v) == 'boolean' then
			print(formatting .. tostring(v))      
		else
			print(formatting .. tostring(v))
		end
	end
end

require("sb")

local gen = {}

function gen.generate(filename, ast)
	gen.output = newsb()

	tprint(ast)

	return gen.output.tostring()
end

return gen