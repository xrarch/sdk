local format = {}

format.name = "loff"

local LOFF5MAGIC = 0x4C4F4635

local loffheader_s = struct {
	{4, "magic"},
	{4, "symbolTableOffset"},
	{4, "symbolCount"},
	{4, "stringTableOffset"},
	{4, "stringTableSize"},
	{4, "targetArchitecture"},
	{4, "entrySymbol"},
	{4, "stripped"},
	{4, "importTableOffset"},
	{4, "importCount"},
	{4, "timestamp"},
	{4, "fragment"},
	{12, "reserved2"},
	{4, "textHeaderOffset"},
	{4, "dataHeaderOffset"},
	{4, "bssHeaderOffset"},
}

local import_s = struct({
	{4, "name"},
	{4, "expectedText"},
	{4, "expectedData"},
	{4, "expectedBSS"},
	{4, "timestamp"},
})

local sectionheader_s = struct({
	{4, "fixupTableOffset"},
	{4, "fixupCount"},
	{4, "sectionOffset"},
	{4, "sectionSize"},
	{4, "linkedAddress"},
})

local symbol_s = struct({
	{4, "nameOffset"},
	{4, "section"},
	{4, "type"},
	{4, "value"},
	{4, "importIndex"}
})

local fixup_s = struct({
	{4, "symbolIndex"},
	{4, "offset"},
	{4, "type"},
})

local isas = {
	["limn2k"] = {
		archid = 2,
		align = 4,
	},
	["limn2500"] = {
		archid = 4,
		align = 4,
	},
}

local symbolnames = {
	["global"] = 1,
	["local"] = 2,
	["extern"] = 3,
	["special"] = 4,
}

local sectionnames = {
	["text"] = 1,
	["data"] = 2,
	["bss"] = 3,
}

local isectionnames = {
	[1] = "text",
	[2] = "data",
	[3] = "bss"
}

local function label_t(name, bc, ltype, section)
	local label = {}

	label.name = name
	label.bc = bc
	label.type = ltype
	label.locallabels = {}
	label.section = section

	return label
end

function format.encode(sections, symbols, isa)
	local arch = isas[isa.name]

	if not arch then
		print("asm: format-loff: LOFF encoding doesn't support '"..isa.name.."' yet")
		return false
	end

	local isection = {}

	isection[1] = sections.text
	isection[2] = sections.data
	isection[3] = sections.bss

	for i = 1, 3 do
		local v = isection[i]

		if not v then
			v = {}
			isection[i] = v
			v.data = {}
			v.bc = 0
			v.relocations = {}
			v.origin = 0

			local sname = isectionnames[i]

			symbols["_"..sname] = label_t("_"..sname, 1, "special", v)
			symbols["_"..sname.."_size"] = label_t("_"..sname.."_size", 2, "special", v)
			symbols["_"..sname.."_end"] = label_t("_"..sname.."_end", 3, "special", v)
		end

		v.id = i

		v.reloctable = {}
		v.reloctableoff = 0
		v.reloctableindex = 0

		while band(v.bc, 3) ~= 0 do
			if not v.bss then
				v.data[v.bc] = 0
			end

			v.bc = v.bc + 1
		end

		v.head = {}
	end

	local stringtab = {}
	local stringtaboff = 0

	local function addString(str)
		local off = stringtaboff

		for i = 1, #str do
			stringtab[stringtaboff] = string.byte(str:sub(i,i))
			stringtaboff = stringtaboff + 1
		end

		stringtab[stringtaboff] = 0
		stringtaboff = stringtaboff + 1

		return off
	end

	local symtab = {}
	local symtaboff = 0
	local symtabindex = 0

	local function addSymbol(name, section, symtype, value)
		local off = symtabindex

		local nameoff = 0xFFFFFFFF

		if name then
			if symtype ~= "local" then
				nameoff = addString(name)
			end
		end

		local typid = symbolnames[symtype]

		if not typid then
			print("asm: format-loff: LOFF encoding doesn't support symbols of type '"..symtype.."'")
			return false
		end

		local sym = cast(symbol_s, symtab, symtaboff)

		local sid

		if section then
			sid = section.id
		else
			sid = 0
		end

		sym.sv("nameOffset", nameoff)
		sym.sv("section", sid)
		sym.sv("type", typid)
		sym.sv("value", value)
		sym.sv("importIndex", 0)

		symtabindex = symtabindex + 1
		symtaboff = symtaboff + symbol_s.size()

		return off
	end

	local entrySymbol = 0xFFFFFFFF

	for k,v in pairs(symbols) do
		if (v.type ~= "extern") or (v.erefs > 0) then
			v.index = addSymbol(v.name, v.section, v.type, v.bc)

			if v.entry then
				entrySymbol = v.index
			end
		end
	end

	while band(stringtaboff, 3) ~= 0 do
		stringtab[stringtaboff] = 0
		stringtaboff = stringtaboff + 1
	end

	local function addRelocation(section, symbol, offset, rtype)
		local off = section.reloctableindex

		local fixup = cast(fixup_s, section.reloctable, section.reloctableoff)

		if not symbol.index then
			print("asm: format-loff: LOFF encoding doesn't support local fixups")
			return false
		end

		fixup.sv("symbolIndex", symbol.index)
		fixup.sv("offset", offset)
		fixup.sv("type", rtype)

		section.reloctableindex = section.reloctableindex + 1
		section.reloctableoff = section.reloctableoff + fixup_s.size()

		return off
	end

	local stringtabfiloff = loffheader_s.size() + symtaboff

	local off = loffheader_s.size() + symtaboff + stringtaboff

	for i = 1, 3 do
		local v = isection[i]

		local shdr = cast(sectionheader_s, v.head)

		for i,r in ipairs(v.relocations) do
			local rt = isa.reloctype(format, r)

			if not rt then return false end

			if not addRelocation(v, r.symbol, r.offset, rt) then return false end
		end

		shdr.sv("fixupTableOffset", off)
		shdr.sv("fixupCount", v.reloctableindex)
		shdr.sv("linkedAddress", v.origin)

		off = off + v.reloctableoff

	end

	-- off is now the file offset after the header, symbol table, string table, and after the fixup tables

	local hdroff = off

	off = off + sectionheader_s.size()*3

	-- off is now the file offset after the header, symbol table, string table, fixup tables, and section headers

	for i = 1, 3 do
		local v = isection[i]

		local shdr = cast(sectionheader_s, v.head)

		shdr.sv("sectionOffset", off)
		shdr.sv("sectionSize", v.bc)

		v.headeroffset = hdroff

		hdroff = hdroff + sectionheader_s.size()
		off = off + v.bc
	end

	local loffhead = {}

	for i = 0, loffheader_s.size()-1 do
		loffhead[i] = 0
	end

	local header = cast(loffheader_s, loffhead)

	header.sv("magic", LOFF5MAGIC)

	header.sv("symbolTableOffset", loffheader_s.size())
	header.sv("symbolCount", symtabindex)

	header.sv("stringTableOffset", stringtabfiloff)
	header.sv("stringTableSize", stringtaboff)

	header.sv("targetArchitecture", arch.archid)

	header.sv("entrySymbol", entrySymbol)

	header.sv("stripped", 0)

	header.sv("importTableOffset", 0)
	header.sv("importCount", 0)

	-- header.sv("timestamp", os.time(os.date("!*t")))

	header.sv("fragment", 0)

	header.sv("textHeaderOffset", isection[1].headeroffset)
	header.sv("dataHeaderOffset", isection[2].headeroffset)
	header.sv("bssHeaderOffset", isection[3].headeroffset)

	local binary = ""

	local function addTab(tab, size)
		if size == 0 then return end

		for i = 0, size-1 do
			binary = binary .. string.char(tab[i])
		end
	end

	addTab(loffhead, loffheader_s.size())
	addTab(symtab, symtaboff)
	addTab(stringtab, stringtaboff)

	addTab(isection[1].reloctable, isection[1].reloctableoff)
	addTab(isection[2].reloctable, isection[2].reloctableoff)
	addTab(isection[3].reloctable, isection[3].reloctableoff)

	addTab(isection[1].head, sectionheader_s.size())
	addTab(isection[2].head, sectionheader_s.size())
	addTab(isection[3].head, sectionheader_s.size())

	addTab(isection[1].data, isection[1].bc)
	addTab(isection[2].data, isection[2].bc)
	-- addTab(isection[3].data, isection[3].bc)

	return binary
end

return format