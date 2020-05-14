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
	print("assembler for aisav3 lemon")
	print("usage: asm.lua [source] [dest]")
end

local target = "limn2k"

for k,v in pairs(arg) do
	if v:sub(1,7) == "target=" then
		target = v:sub(8)
		table.remove(arg, k)
	end
end

local flat = false
if arg[1] == "-flat" then
	table.remove(arg, 1)
	flat = true
end

if (#arg < 2) or (math.floor(#arg/2) ~= #arg/2) then
	print("asm: argument mismatch")
	printhelp()
	os.exit(1)
end

for i = 1, #arg/2 do
	local source = arg[i]
	local dest = arg[#arg/2 + i]

	local srcf = io.open(source, "r")

	if not srcf then
		print(string.format("asm: error opening source file %s", source))
		os.exit(1)
	end

	local o = asm.assemble(target, srcf:read("*a"), source, flat)

	if not o then
		print("asm: couldn't assemble "..source.."!")
		os.exit(1)
	else
		destf = io.open(dest, "w")

		if not destf then
			print(string.format("asm: error opening destination file %s", dest))
			os.exit(1)
		end

		destf:write(o)
		return true
	end
end