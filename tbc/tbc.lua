-- tbc.lua [source] [dest]
-- tested under luaJIT 5.1

local function usage()
	print("== tbc.lua ==")
	print("bootstrap compiler for TOWER")
	print("usage: tbc.lua [source] [dest]")
	os.exit(1)
end

local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end

local tbcdir = getdirectory(arg[0])

local function explode(d,p)
	local t, ll
	t={}
	ll=0
	if(#p == 1) then return {p} end
		while true do
			while p:sub(1,1) == d do
				p = p:sub(2)
			end

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

local incdir = {}
local libdir = {}
local narg = {}
local symbols = {}

for k,v in ipairs(arg) do
	if v:sub(1,7) == "incdir=" then
		local incs = v:sub(8)

		incdir = explode(":", incs)
	elseif v:sub(1,7) == "libdir=" then
		local libs = v:sub(8)

		libdir = explode(":", libs)
	else
		local off = string.find(v, "=")

		if off and (off > 1) then
			local val = v:sub(off+1,-1)

			if val == "" then
				val = true
			elseif val == "0" then
				val = false
			end

			symbols[string.upper(v:sub(1,off-1))] = val
		else
			narg[#narg + 1] = v
		end
	end
end

arg = narg

if #arg ~= 2 then
	usage()
end

-- add the project directory to the package path so we can use require.

package.path = package.path .. ";" .. tbcdir .. "?.lua"

local parser = require("parser")
local gen = require("gen")

local inputfilename = arg[1]
local outputfilename = arg[2]

local inputfile = io.open(inputfilename, "r")

if not inputfile then
	print("tbc: couldn't open "..inputfilename)
	os.exit(1)
end

local outputfile = io.open(outputfilename, "w")

if not outputfile then
	print("tbc: couldn't open "..outputfilename)
	os.exit(1)
end

local ast = parser.parse(inputfilename, inputfile, incdir, libdir, symbols)

if not ast then
	print("tbc: couldn't parse "..inputfilename)
	os.exit(1)
end

local output = gen.generate(inputfilename, ast)

if not output then
	print("tbc: couldn't gen "..inputfilename)
	os.exit(1)
end

outputfile:write(output)