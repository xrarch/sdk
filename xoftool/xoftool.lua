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

    print(string.format("DateStamp     %s", os.date("%c", image.timestamp)))
    print(string.format("Architecture  %s", image.arch.name))
    print(string.format("Head Length   %d bytes", image.headlength))
    if image.entrysymbol then
        print(string.format("Entrypoint    %s @ $%X", image.entrysymbol.name, image.entrysymbol.value))
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

        print(string.format(
[[  %-8s %d bytes
  %-8s 0x%x
  %-8s 0x%x
  %-8s %s]],
"Size", s.size,
"Address", s.vaddr,
"Offset", s.filoffset,
"Flags", sectionflagstring))

        print("")
    end
elseif command == "symbols" then
    if not image:load() then os.exit(1) end

    for i = 0, image.symbolcount-1 do
        local symbol = image.symbolsbyid[i]

        local name = symbol.name or "UNNAMED"

        local section = symbol.section

        if section then
            section = section.name
        else
            section = "EXTERNAL"
        end

        print(string.format(
[[  %-8s %s
  %-8s %s
  %-8s %s
  %-8s 0x%x
  %-8s %d]],
"Name", name,
"Section", section,
"Type", xloff.symtypenames[symbol.type] or "UNKNOWN",
"Value", symbol.value,
"Flags", symbol.flags))

        print("")
    end
elseif command == "relocs" then
    if not image:load() then os.exit(1) end

    for i = 0, image.sectioncount-1 do
        local s = image.sectionsbyid[i]

        for j = 1, s.reloccount do
            local r = s.relocs[j]

            local sym = r.symbol

            if sym then
                print(string.format("%s: %x ref %s: %s (@%x) (%s)", s.name, r.offset, (sym.section or {["name"]="extern"}).name, (sym.name or "\b"), sym.value, xloff.relocnames[r.type]))
            end
        end
    end
elseif command == "externs" then
    if not image:load() then os.exit(1) end

    for k,v in pairs(image.externsbyname) do
        if v.import then
            print(string.format("%s -> %s", v.name, v.import.name))
        else
            print(string.format("%s", v.name))
        end
    end
elseif command == "imports" then
    if not image:load() then os.exit(1) end

    for i = 0, image.importcount-1 do
        local import = image.importsbyid[i]

        print(string.format("%d: %s [%s]", i, import.name, os.date("%c", import.timestamp)))
    end
elseif command == "fixups" then
    if not image:load() then os.exit(1) end

    for i = 0, image.importcount-1 do
        local s = image.importsbyid[i]

        for j = 1, s.fixupcount do
            local r = s.fixups[j]

            local sym = r.symbol

            if sym then
                print(string.format("%s: %x ref %s: %s (@%x) (%s)", r.section.name, r.offset, (sym.section or {["name"]="extern"}).name, (sym.name or "\b"), sym.value, xloff.relocnames[r.type]))
            end
        end
    end
end

return true