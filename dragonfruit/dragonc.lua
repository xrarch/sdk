local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local df = dofile(sd.."compiler.lua")

-- dragonc.lua [source1 source2 ...] [dest1 dest2 ...]
-- tested under lua 5.1

local function printhelp()
	print("== dragonc.lua ==")
	print("compiler for dragonfruit, targeting limn1k asm")
	print("usage: dragonc.lua [source1 source2 ...] [dest1 dest2 ...]")
end

if (#arg < 2) or (math.floor(#arg/2) ~= #arg/2) then
	print("argument mismatch")
	printhelp()
	return false
end

for i = 1, #arg/2 do
	local source = arg[i]
	local dest = arg[#arg/2 + i]

	local srcf = io.open(source, "r")

	if not srcf then
		print(string.format("dragonc: error opening source file %s", source))
		return false
	end

	local destf = io.open(dest, "w")

	if not destf then
		print(string.format("dragonc: error opening destination file %s", dest))
		return false
	end

	local o = df.c(srcf:read("*a"), source)

	if not o then
		print("dragonc: couldn't compile "..source.."!")
		return false
	else
		destf:write(o)
		return true
	end
end