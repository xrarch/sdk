local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

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

local loff = dofile(sd.."xloff.lua")

local dimg = arg[1]

local function usage()
	print("== xoftool.lua ==")
	print("utility to manipulate eXtended LIMN Object File Format (XLOFF) images")
	print("usage: xoftool.lua [command] [args] ...")
	print([[commands:
  info     [image]: show general info about the file
  sections [image]: dump section information
  symbols  [image]: dump symbols
  relocs   [image]: dump relocation tables
  externs  [image]: dump external symbols
  imports  [image]: dump imported DLLs
  fixups   [image]: dump fixup tables for imported DLLs
  move     [image] [move expression]: move an XLOFF file in memory
  rstrip   [image]: strip internal relocations and local symbols
  gstrip   [image]: strip global symbols
  fstrip   [image]: strip import fixups
  strip    [image]: perform actions of all of rstrip, gstrip, and fstrip
  binary   (-nobss) [image] [base address] (bss address): flatten an XLOFF file; will expand BSS section in file unless address is provided.
  link     (-f) [output] [xloff1 xloff2 ... ]: link 2 or more XLOFF files
  symtab   [output] [image] (text offset): generate a symbol table
]])
end

if #arg < 1 then
	usage()
	os.exit(1)
end

return true