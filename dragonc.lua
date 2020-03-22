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
local incdir = ""
local target = "target=limn1k"

local narg = {}

for k,v in ipairs(arg) do
	if v == "-flat" then
		flat = true
	elseif v:sub(1,7) == "incdir=" then
		incdir = v
	elseif v:sub(1,7) == "target=" then
		target = v
	else
		narg[#narg + 1] = v
	end
end

local function printhelp()
	print("== dragonc.lua ==")
	print("compiler for dragonfruit to aixo/limn1k object files")
	print("(or flat binaries with the -flat argument)")
	print("usage: dragonc.lua [source1 source2 ...] [dest1 dest2 ...]")
end

local sourcef = {}
local destf = {}

if (#narg < 2) or (math.floor(#narg/2) ~= #narg/2) then
	print("argument mismatch")
	printhelp()
	return
end

for i = 1, #narg/2 do
	sourcef[#sourcef + 1] = narg[i]
	destf[#destf + 1] = narg[#narg/2 + i]
end

local lua = sd.."lua.sh "
local dragonc = sd.."dragonfruit/dragonc.lua "..target.." "..incdir.." "
local asm = sd.."asm/asm.lua "..target.." "

if flat then
	asm = asm .. "-flat "
end

for k,v in ipairs(sourcef) do
	local ed = getdirectory(v)

	local eout = ed..".__out.s "

	local err

	-- is there a better way to do this? probably.
	err = os.execute(lua..dragonc..v.." "..eout)

	if err > 0 then os.exit(1) end

	err = os.execute(lua..asm..eout..destf[k])

	if err > 0 then os.exit(1) end

	err = os.execute("rm "..eout)

	if err > 0 then os.exit(1) end
end