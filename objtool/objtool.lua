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

local loff = dofile(sd.."loff.lua")

local dimg = arg[1]

local function usage()
	print("== objtool.lua ==")
	print("utility to manipulate LIMN Object File Format (LOFF) images")
	print("usage: objtool.lua [command] [args] ...")
	print([[commands:
  info [loff]: show info about the file
  symbols [loff]: dump symbols
  fixups [loff]: dump fixup table
  externs [loff]: dump unresolved external symbols
  imports [loff]: dump imported DLLs
  move [loff] [move expression]: move a loff file in memory
  strip [loff]: strip all linking information from loff file
  lstrip [loff]: strip local symbol names
  binary (-nobss) [loff] [base address] (bss address): flatten a loff file, will expand BSS section in file unless address is provided
  link (-f) [output] [loff1 loff2 ... ]: link 2 or more loff files
  symtab [output] [loff] (text offset): generate a symbol table
]])
end

if #arg < 1 then
	usage()
	os.exit(1)
end

local symtypen = {"global","local","extern","special"}

local sectionn = {"text","data","bss"}

local archn = {"limn1k","limn2k","riscv32","limn2500"}

if arg[1] == "info" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	local image = loff.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	print(string.format("linked at: %s", os.date("%c", image.timestamp)))
	print(string.format("architecture: %s", archn[image.codeType] or "UNKNOWN"))
	if image.entrySymbol then
		print(string.format("entry point: %s @ $%X", image.entrySymbol.name, image.entrySymbol.value))
	end

	for i = 1, 3 do
		local s = image.sections[i]

		print(string.format("%s %d bytes @ $%X (off $%X)", s.name, s.size, s.linkedAddress, s.offset))
	end
elseif arg[1] == "symbols" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	local image = loff.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	local x = false

	for i = 0, #image.symbols do
		local v = image.symbols[i]

		if v then
			print(string.format("%s %s = %s: $%X", symtypen[v.symtype], (v.name or "_"), (image.sections[v.section] or {["name"]="extern"}).name, v.value))
			x = true
		end
	end

	if not x then
		print("objtool: no symbols exposed!")
	end
elseif arg[1] == "symtab" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	if not arg[3] then
		usage()
		os.exit(1)
	end

	local image = loff.new(arg[3])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	local textoff = tonumber(arg[4]) or 0

	local symtab = io.open(arg[2], "w")

	if not symtab then
		print("objtool: couldn't open "..tostring(arg[2]).." for writing")
		os.exit(1)
	end

	image:iSymSort()

	symtab:write(".section data\n\nSymbolTable:\n.global SymbolTable\n")

	local syms = 0

	local names = ""

	local donesym = {}

	for k,sym in ipairs(image.isym) do
		local s = image.sections[1]

		if (sym.symtype == 1) and (sym.section == 1) and (not donesym[sym.name]) then
			symtab:write("\t.dl __SYMNAM"..tostring(k).."\n")
			symtab:write("\t.dl "..tostring(sym.value + s.linkedAddress + textoff).."\n")

			names = names.."__SYMNAM"..tostring(k)..":\n\t.ds "..sym.name.."\n\t.db 0x0\n"

			syms = syms + 1

			symtab:write("\n")

			donesym[sym.name] = true
		end
	end

	symtab:write("SymbolCount:\n.global SymbolCount\n\t.dl "..tostring(syms).."\n\n")

	symtab:write(names)

	symtab:write("\n.align 4\n")

	symtab:close()
elseif arg[1] == "fixups" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	local image = loff.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	for i = 1, 2 do
		local s = image.sections[i]

		for k,v in ipairs(s.fixups) do
			local sym = v.symbol

			if sym then
				print(string.format("%s: %x ref %s: %s (@%x) (target type: %d)", s.name, v.offset, (image.sections[sym.section] or {["name"]="extern"}).name, (sym.name or "_"), sym.value, v.type))
			end
		end
	end
elseif arg[1] == "strip" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	local image = loff.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	image.linkable = false

	if not image:write() then
		os.exit(1)
	end
elseif arg[1] == "lstrip" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	local image = loff.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	image.localSymNames = false

	if not image:write() then
		os.exit(1)
	end
elseif arg[1] == "externs" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	local image = loff.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	for i = 0, #image.symbols do
		local v = image.symbols[i]

		if v and v.symtype == 3 then
			if v.import then
				print(string.format("%s -> %s", v.name, v.import.name))
			else
				print(string.format("%s", v.name))
			end
		end
	end
elseif arg[1] == "imports" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	local image = loff.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	for i = 1, #image.imports do
		local v = image.imports[i]

		print(string.format("%d: %s ($%x, $%x, $%x) [%s]", i, v.name, v.expectedText, v.expectedData, v.expectedBSS, os.date("%c", v.timestamp)))
	end
elseif arg[1] == "move" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	if not arg[3] then
		usage()
		os.exit(1)
	end

	local image = loff.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	local textaddress = image.sections[1].linkedAddress
	local dataaddress = image.sections[2].linkedAddress
	local bssaddress = image.sections[3].linkedAddress

	if arg[3] == "aisix" then
		arg[3] = "text=0x1000,data=0x40000000,bss=data+data_size+align"
	end

	local expr = explode(",", arg[3])

	local sectionnum = {
		["text"] = 1,
		["data"] = 2,
		["bss"] = 3,
	}

	local reloced = {}

	for k,v in ipairs(expr) do
		local exp = explode("=", v)

		local s = exp[1]

		local section = sectionnum[s]

		if not section then
			print("objtool: not a section: '"..s.."'")
			os.exit(1)
		end

		local x = exp[2]

		local addends = explode("+", x)

		local r = 0

		for k,v in ipairs(addends) do
			if v == "text" then
				r = r + image.sections[1].linkedAddress
			elseif v == "data" then
				r = r + image.sections[2].linkedAddress
			elseif v == "bss" then
				r = r + image.sections[3].linkedAddress
			elseif v == "text_size" then
				r = r + image.sections[1].size
			elseif v == "data_size" then
				r = r + image.sections[2].size
			elseif v == "bss_size" then
				r = r + image.sections[3].size
			elseif v == "text_offset" then
				r = r + image.sections[1].offset
			elseif v == "data_offset" then
				r = r + image.sections[2].offset
			elseif v == "bss_offset" then
				r = r + image.sections[3].offset
			elseif v == "align" then
				if (r % 4096) ~= 0 then
					r = r + 4096
					r = r - (r % 4096)
				end
			elseif tonumber(v) then
				r = r + tonumber(v)
			else
				print("objtool: I don't know what "..v.." is")
				os.exit(1)
			end
		end

		reloced[section] = true

		if not image:relocTo(section, r) then
			os.exit(1)
		end
	end

	image.timestamp = os.time(os.date("!*t"))

	if not image:write() then
		os.exit(1)
	end
elseif arg[1] == "binary" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	local nobss = arg[2] == "-nobss"

	local b = 2
	if nobss then b = 3 end

	local image = loff.new(arg[b])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	if not image:binary(nobss, tonumber(arg[b+1]), tonumber(arg[b+2])) then
		os.exit(1)
	end
elseif arg[1] == "link" then
	local fragment = false

	if arg[2] == "-f" then
		fragment = true
		table.remove(arg, 2)
	end

	if not (arg[2] and arg[3]) then
		usage()
		os.exit(1)
	end

	local linked = {}

	local out = loff.new(arg[2], nil, fragment)
	if not out then
		os.exit(1)
	end

	out.linkable = true

	local dy = false

	for i = 3, #arg do
		local imgname = arg[i]

		if imgname == "-d" then
			dy = true
		else
			if linked[arg[i]] then
				print("objtool: warning: ignoring duplicate object "..arg[i])
			else
				linked[arg[i]] = true

				local comp = explode(":", imgname)

				local libname

				if comp[2] then
					libname = comp[1]
					imgname = comp[2]
				end

				if imgname:sub(1,2) == "L/" then
					imgname = sd.."../lib/"..imgname:sub(3)
				end

				local image = loff.new(imgname, libname)
				if not image then
					os.exit(1)
				end

				if not image:load() then
					os.exit(1)
				end

				if not out:link(image, dy) then
					os.exit(1)
				end
			end
		end
	end

	out:relocate()

	if not fragment then
		local unr = {}

		for i = 0, #out.symbols do
			local sym = out.symbols[i]

			if sym and (not sym.resolved) and (not sym.import) then
				if sym.symtype == 3 then
					unr[#unr + 1] = sym
				end
			end
		end

		if #unr > 0 then
			print("objtool: error: unresolved symbols:")

			for k,v in ipairs(unr) do
				print(string.format("  %s: %s", v.file, v.name))
			end

			os.exit(1)
		end
	end

	if not out:write() then
		os.exit(1)
	end
else
	print("objtool: not a command: "..arg[1])
	usage()
	
	os.exit(1)
end

return true