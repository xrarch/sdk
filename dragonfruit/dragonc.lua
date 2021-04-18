local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

dofile(sd.."misc.lua")

local lexer = dofile(sd.."lexer.lua")

local parser = dofile(sd.."parser.lua")

local eval = dofile(sd.."eval.lua")

local function explode(d,p)
	local t, ll
	t={}
	ll=0
	if(#p == 1) then return {p} end
		while true do
			l=string.find(p,d,ll,true) -- find the next d in the string
			if l~=nil then -- if "not not" found then..
				table.insert(t, string.sub(p,ll,l-1)) -- Save it in our array.
				ll=l+1 -- save just after where we found it for searching next time.
			else
				table.insert(t, string.sub(p,ll)) -- Save what's left in our array.
				break -- Break at end, as it should be, according to the lua manual.
			end
		end
	return t
end

-- dragonc.lua [source1 source2 ...] [dest1 dest2 ...]
-- tested under luaJIT 5.1

local function printhelp()
	print("== dragonc.lua ==")
	print("compiler for dragonfruit, targeting limn2k asm")
	print("usage: dragonc.lua [source1 source2 ...] [dest1 dest2 ...]")
end

local incdir = {}

local targets = {
	["limn2k"] = "cg-limn2k.lua",
	["riscv"] = "cg-riscv.lua",
}

local target = "limn2k"

local narg = {}

for k,v in ipairs(arg) do
	if v:sub(1,7) == "incdir=" then
		local incs = v:sub(8)

		incdir = explode(":", incs)
	elseif v:sub(1,7) == "target=" then
		target = v:sub(8)
	else
		narg[#narg + 1] = v
	end
end

arg = narg

if not targets[target] then
	print("dragonc: no such target "..target)
	os.exit(1)
end

local codegen = dofile(sd..targets[target])

if (#arg < 2) or (math.floor(#arg/2) ~= #arg/2) then
	print("dragonc: argument mismatch")
	printhelp()
	os.exit(1)
end

for i = 1, #arg/2 do
	local source = arg[i]
	local dest = arg[#arg/2 + i]

	local srcf = io.open(source, "r")

	if not srcf then
		print(string.format("dragonc: error opening source file %s", source))
		os.exit(1)
	end

	local o = codegen.gen(eval.eval(parser.parse(lexer, srcf:read("*a"), source, incdir, eval.immop, codegen)))

	if not o then
		print("dragonc: couldn't compile "..source.."!")
		os.exit(1)
	else
		destf = io.open(dest, "w")

		if not destf then
			print(string.format("dragonc: error opening destination file %s", dest))
			os.exit(1)
		end

		destf:write(o)
		return true
	end
end