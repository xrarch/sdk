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

dofile(sd.."misc.lua")

local xloff = dofile(sd.."xloff.lua")

local function usage()
	print("== xoftool.lua ==")
	print("utility to manipulate eXtended LIMN Object File Format (XLOFF) images")
	print("usage: xoftool.lua [command] [args] ...")
	print([[commands:
  info     [image]: dump general info about the file
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

local narg = {}

local switches = {}

for k,v in ipairs(arg) do
    if v:sub(1,1) == "-" then
        switches[#switches + 1] = v
    else
        narg[#narg + 1] = v
    end
end

arg = narg

if #arg < 2 then
	usage()
	os.exit(1)
end

local command = arg[1]
local imagename = arg[2]

local image = xloff.new(imagename)

if command == "info" then
    if not image:load() then os.exit(1) end

    print(string.format("linked at: %s", os.date("%c", image.timestamp)))
    print(string.format("architecture: %s", image.arch.name))
    if image.entrysymbol then
        print(string.format("entry point: %s @ $%X", image.entrysymbol.name, image.entrysymbol.value))
    end

    print("\nSections:")

    for i = 0, image.sectioncount-1 do
        local s = image.sectionsbyid[i]

        local sectionflags = s.flags

        local sectionflagstring = ""

        for j = 31, 0, -1 do
            if band(rshift(sectionflags, j), 1) == 1 then
                if xloff.sectionflagnames[j] then
                    if sectionflagstring ~= "" then
                        sectionflagstring = sectionflagstring .. " | "
                    end

                    sectionflagstring = sectionflagstring .. xloff.sectionflagnames[j]
                end
            end
        end

        print(s.name..":")

        print(string.format([[  %-8s %d bytes
  %-8s 0x%x
  %-8s 0x%x
  %-8s %s]],
"Size", s.size,
"Address", s.vaddr,
"Offset", s.filoffset,
"Flags", sectionflagstring))

        print("")
    end
end

return true