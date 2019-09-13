local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local lex = dofile(sd.."lex.lua")

local dimg = arg[1]

local function usage()
	print("== lextool.lua ==")
	print("utility to manipulate LIMN EXecutable (LEX) images")
	print("usage: lextool.lua [image] [command] [args] ...")
	print([[commands:
	i: dump info
	flatten [lex]: flatten a lex file (convert to raw binary)
	link [output] [lex1 lex2 ... ]: link 2 or more lex files
]])
end

if #arg < 2 then
	usage()
	return
end

local cmd = arg[2]