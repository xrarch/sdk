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
  lstrip   [image]: strip local symbols
  istrip   [image]: strip internal relocations
  gstrip   [image]: strip global symbols 
  fstrip   [image]: strip import fixups
  dystrip  [image]: perform actions of all of lstrip, istrip, and fstrip
  strip    [image]: perform actions of all of lstrip, istrip, gstrip, and fstrip
  binary   (-nobss) [image]: flatten an XLOFF file
  symtab   [image] [output] (text offset): generate a symbol table
  link     (-f) [output] [xloff1 xloff2 ... ]: link 2 or more XLOFF files
]])
end

local narg = {}

local switches = {}

local es = 0

for k,v in ipairs(arg) do
    if (es < 2) and (v:sub(1,1) == "-") then
        switches[#switches + 1] = v
    else
        es = es + 1
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

    local flagstring = ""

    local flags = image.flags

    for i = 31, 0, -1 do
        if band(rshift(flags, i), 1) == 1 then
            if xloff.flagnames[i] then
                if flagstring ~= "" then
                    flagstring = flagstring .. " | "
                end

                flagstring = flagstring .. xloff.flagnames[i]
            end
        end
    end

    print(string.format("Flags         %s", flagstring))

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
                print(string.format("%s: %x ref %s: %s (@%x) (%s)", s.name, r.offset, (sym.section or {["name"]="extern"}).name, (sym.name or "\b"), sym.value, image.arch.relocnames[r.type]))
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

        print(s.name..":")

        for j = 1, s.fixupcount do
            local r = s.fixups[j]

            local sym = r.symbol

            if sym then
                print(string.format("  %s: %x ref %s: %s (@%x) (%s)", r.section.name, r.offset, (sym.section or {["name"]="extern"}).name, (sym.name or "\b"), sym.value, image.arch.relocnames[r.type]))
            end
        end

        print("")
    end
elseif command == "lstrip" then
    if not image:load() then os.exit(1) end

    image.lstrip = true

    if not image:write() then os.exit(1) end
elseif command == "istrip" then
    if not image:load() then os.exit(1) end

    image.istrip = true
    image.lstrip = true

    if not image:write() then os.exit(1) end
elseif command == "gstrip" then
    if not image:load() then os.exit(1) end

    image.gstrip = true

    if not image:write() then os.exit(1) end
elseif command == "fstrip" then
    if not image:load() then os.exit(1) end

    image.fstrip = true

    if not image:write() then os.exit(1) end
elseif command == "dystrip" then
    if not image:load() then os.exit(1) end

    image.lstrip = true
    image.istrip = true
    image.fstrip = true

    if not image:write() then os.exit(1) end
elseif command == "strip" then
    if not image:load() then os.exit(1) end

    image.lstrip = true
    image.istrip = true
    image.fstrip = true
    image.gstrip = true

    if not image:write() then os.exit(1) end
elseif command == "binary" then
    local nobss = (switches[1] == "-nobss")
   
    if #arg ~= 2 then
        usage()
        os.exit(1)
    end

    if not image:load() then os.exit(1) end
    if not image:binary(nobss) then os.exit(1) end
elseif command == "move" then
    if not image:load() then os.exit(1) end

    if arg[3] == "aisix" then
        arg[3] = "text=0x1000,data=0x40000000,bss=data+data_size+align"
    elseif arg[3] == "mintiadll" then
        image.pagealignrequired = 4096
        arg[3] = arg[4]
    elseif arg[3] == "mintia" then
        image.pagealignrequired = 4096
        arg[3] = "text=0x100000,data=text+text_size+align,bss=data+data_size+align"
    end

    local expr = explode(",", arg[3])

    for k,v in ipairs(expr) do
        local exp = explode("=", v)

        local s = exp[1]

        if s == "base" then
            local base = tonumber(exp[2])

            for i = 0, image.sectioncount-1 do
                local section = image.sectionsbyid[i]

                section.vaddr = base
                base = base + band(section.size+4095, bnot(4095))
            end
        else
            local section = image.sectionsbyname[s]

            if not section then
                print("xoftool: not a section: '"..s.."'")
                os.exit(1)
            end

            local x = exp[2]

            local addends = explode("+", x)

            local r = 0

            for k,v in ipairs(addends) do
                if v:sub(-5,-1) == "_size" then
                    local asection = image.sectionsbyname[v:sub(1,-6)]

                    if not asection then
                        print("xoftool: not a section: '"..v:sub(1,-6).."'")
                        os.exit(1)
                    end

                    r = r + asection.size
                elseif v == "align" then
                    if (r % 4096) ~= 0 then
                        r = r + 4096
                        r = r - (r % 4096)
                    end
                elseif tonumber(v) then
                    r = r + tonumber(v)
                else
                    local asection = image.sectionsbyname[v]

                    if not asection then
                        print("xoftool: I don't know what "..v.." means")
                        os.exit(1)
                    end

                    r = r + asection.vaddr
                end
            end

            section.vaddr = r
        end
    end

    image.timestamp = os.time(os.date("!*t"))

    if not image:relocate() then os.exit(1) end

    image:sortsymbols()

    if not image:write() then os.exit(1) end
elseif command == "link" then
    local nostubs
    local fragment

    for k,v in ipairs(switches) do
        if v == "-f" then
            fragment = true
        elseif v == "-nostubs" then
            nostubs = true
        end
    end

    image.nostubs = nostubs
    image.fragment = fragment

    local linked = {}

    local dynamic = false

    for i = 3, #arg do
        local imgname = arg[i]

        if imgname == "-d" then
            dynamic = true
        elseif imgname == "-s" then
            dynamic = false
        elseif linked[imgname] then
            print("xoftool: warning: ignoring duplicate object "..arg[i])
        else
            linked[imgname] = true

            if imgname:sub(1,2) == "L/" then
                imgname = sd.."../lib/"..image.arch.name.."/"..imgname:sub(3)
            elseif imgname:sub(1,3) == "LX/" then
                imgname = sd.."../lib/"..imgname:sub(3)
            end

            local comp = explode(":", imgname)

            local libname

            if comp[2] then
                libname = comp[1]
                imgname = comp[2]
            end

            local lnkobj = xloff.new(imgname)

            if not lnkobj:load() then os.exit(1) end

            if libname then lnkobj.libname = libname end

            if not image:link(lnkobj, dynamic) then os.exit(1) end
        end
    end

    image:sortsymbols()

    if not fragment then
        if not image:checkunresolved() then os.exit(1) end
    end

    if not image:relocate() then os.exit(1) end

    if not image:write() then os.exit(1) end
elseif command == "symtab" then
    if not image:load() then os.exit(1) end

    if not arg[3] then
        usage()
        os.exit(1)
    end

    local textoff = tonumber(arg[4]) or 0

    local symtabfile = arg[3]

    if not image:gensymtab(symtabfile, textoff) then os.exit(1) end
else
    usage()
    os.exit(1)
end

return true