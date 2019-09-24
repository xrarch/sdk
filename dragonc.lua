-- this program may seem redundant but it uses real dragonc and then the assembler
-- which are separate smaller programs instead of one big one
-- cuz KISS

local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local flat = false

for k,v in pairs(arg) do
	if v == "-flat" then
		flat = true
		table.remove(arg, k)
	end
end

local function printhelp()
	print("== dragonc.lua ==")
	print("compiler for dragonfruit to aixo/limn1k object files")
	print("usage: dragonc.lua [source1 source2 ...] [dest1 dest2 ...]")
end

local sourcef = {}
local destf = {}

if (#arg < 2) or (math.floor(#arg/2) ~= #arg/2) then
	print("argument mismatch")
	printhelp()
	return
end

for i = 1, #arg/2 do
	sourcef[#sourcef + 1] = arg[i]
	destf[#destf + 1] = arg[#arg/2 + i]
end

local lua = sd.."lua.sh "
local dragonc = sd.."dragonfruit/dragonc.lua "
local asm = sd.."asm/asm.lua "

for k,v in ipairs(sourcef) do
	local ed = getdirectory(v)

	local eout = ed..".__out.s "

	-- is there a better way to do this? probably.
	os.execute(lua..dragonc..v.." "..eout)
	if flat then
		os.execute(lua..asm.."-flat "..eout..destf[k])
	else
		os.execute(lua..asm..eout..destf[k])
	end
	os.execute("rm "..eout)
end