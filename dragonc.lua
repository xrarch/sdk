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
local libdir = ""
local target = "target=limn2600"
local format = "format=xloff"
local preprocargs = " "
local asmout = false

local narg = {}

for k,v in ipairs(arg) do
	if v == "-flat" then
		flat = true
	elseif v == "-S" then
		asmout = true
	elseif v:sub(1,7) == "incdir=" then
		incdir = v
	elseif v:sub(1,7) == "libdir=" then
		libdir = v
	elseif v:sub(1,7) == "target=" then
		target = v
	elseif v:sub(1,7) == "format=" then
		format = v
	elseif v:find("=") then
		preprocargs = preprocargs..v.." "
	else
		narg[#narg + 1] = v
	end
end

local function printhelp()
	print("== dragonc.lua ==")
	print("compiler for dragonfruit to loff/limn2600 object files")
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
local preproc = sd.."preproc/preproc.lua "..incdir.." "..libdir.." "..preprocargs
local dragonc = sd.."dragonfruit/dragonc.lua "..target.." "
local asm = sd.."asmfx/asmfx.lua "..format.." "..target.." "

if flat then
	asm = asm .. "format=flat "
end

local dx = 0

local function getfilename(p)
	local qp = 1

	for i = 1, #p do
		if p:sub(i,i) == "/" then
			qp = i + 1
		end
	end

	return p:sub(qp)
end

for k,v in ipairs(sourcef) do
	local ed = getdirectory(v)

	local pout = ed..".__out"..getfilename(v)..".pp "

	local eout

	if not asmout then
		eout = ed..".__out"..getfilename(v)..".s "
	else
		eout = destf[k]
	end

	local err

	-- is there a better way to do this? probably.
	err = os.execute(lua..preproc..v.." "..pout)

	if not err or (err > 0) then
		os.execute("rm -f "..pout)
		os.exit(1)
	end

	err = os.execute(lua..dragonc..pout.." "..eout)

	os.execute("rm -f "..pout)

	if not err or (err > 0) then os.exit(1) end

	if asmout then
		return
	end

	err = os.execute(lua..asm..eout..destf[k])

	if not err or (err > 0) then os.exit(1) end

	os.execute("rm -f "..eout)
end