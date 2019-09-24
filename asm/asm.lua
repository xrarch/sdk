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

local flat = false
if arg[1] == "-flat" then
	table.remove(arg, 1)
	flat = true
end

if (#arg < 2) or (math.floor(#arg/2) ~= #arg/2) then
	print("argument mismatch")
	printhelp()
	return
end

for i = 1, #arg/2 do
	local source = arg[i]
	local dest = arg[#arg/2 + i]

	local srcf = io.open(source, "r")

	if not srcf then
		print(string.format("asm: error opening source file %s", source))
		return
	end

	local destf = io.open(dest, "w")

	if not destf then
		print(string.format("asm: error opening destination file %s", dest))
		return
	end

	local o = asm.assemble(srcf:read("*a"), source, flat)

	if not o then
		print("asm: couldn't assemble "..source.."!")
		return
	else
		destf:write(o)
		return true
	end
end