local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local asm = dofile(sd.."assembler.lua")

-- asm.lua [source] [dest]
-- tested under lua 5.1

local function printhelp()
	print("== asm.lua ==")
	print("assembler for aisav2 lemon")
	print("usage: asm.lua [source] [dest]")
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

destf:write(asm.as(srcf:read("*a"), false, source))