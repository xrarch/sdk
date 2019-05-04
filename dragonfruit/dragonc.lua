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

-- dragonc.lua [source] [dest]
-- tested under lua 5.1

local function printhelp()
	print("== dragonc.lua ==")
	print("compiler for dragonfruit, targeting aisav2 asm")
	print("usage: dragonc.lua [source] [dest]")
end

local source = arg[1]
local dest = arg[2]

if (not source) or (not dest) then
	print("argument mismatch")
	printhelp()
	return
end

local srcf = io.open(source, "r")

if not srcf then
	print(string.format("error opening source file %s", source))
	return
end

local destf = io.open(dest, "w")

if not destf then
	print(string.format("error opening destination file %s", dest))
	return
end

destf:write(df.c(srcf:read("*a"), source, arg[3] == "-noprim"))