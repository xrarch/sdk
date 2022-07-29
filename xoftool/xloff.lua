local xloff = {}

local XLOFFMAGIC = 0x99584F46

local xloffheader_s = struct {
	{4, "Magic"},
	{4, "SymbolTableOffset"},
	{4, "SymbolCount"},
	{4, "StringTableOffset"},
	{4, "StringTableSize"},
	{4, "TargetArchitecture"},
	{4, "EntrySymbol"},
	{4, "Flags"},
	{4, "Timestamp"},
	{4, "SectionTableOffset"},
	{4, "SectionCount"},
	{4, "ImportTableOffset"},
	{4, "ImportCount"},
	{4, "HeadLength"},
}

local sectionheader_s = struct {
	{4, "NameOffset"},
	{4, "DataOffset"},
	{4, "DataSize"},
	{4, "VirtualAddress"},
	{4, "RelocTableOffset"},
	{4, "RelocCount"},
	{4, "Flags"}
}

local symbol_s = struct {
	{4, "NameOffset"},
	{4, "Value"},
	{2, "SectionIndex"},
	{1, "Type"},
	{1, "Flags"}
}

local import_s = struct {
	{4, "NameOffset"},
	{4, "ExpectedTimestamp"},
	{4, "FixupTableOffset"},
	{4, "FixupCount"}
}

local reloc_s = struct {
	{4, "Offset"},
	{4, "SymbolIndex"},
	{2, "RelocType"},
	{2, "SectionIndex"}
}

local archinfo = {}

archinfo[1] = {}
archinfo[1].name = "limn2600"
archinfo[1].align = 4

local XLOFFFLAG_ALIGN4K = 1

local XLOFFSYMTYPE_GLOBAL  = 1
local XLOFFSYMTYPE_LOCAL   = 2
local XLOFFSYMTYPE_EXTERN  = 3
local XLOFFSYMTYPE_SPECIAL = 4

local XLOFFSECTIONFLAG_BSS   = 1
local XLOFFSECTIONFLAG_DEBUG = 2
local XLOFFSECTIONFLAG_TEXT  = 4
local XLOFFSECTIONFLAG_MAP   = 8
local XLOFFSECTIONFLAG_READONLY = 16

local symbolnames = {
	["global"]  = XLOFFSYMTYPE_GLOBAL,
	["local"]   = XLOFFSYMTYPE_LOCAL,
	["extern"]  = XLOFFSYMTYPE_EXTERN,
	["special"] = XLOFFSYMTYPE_SPECIAL,
}

xloff.symtypenames = {}
xloff.symtypenames[XLOFFSYMTYPE_GLOBAL]  = "global"
xloff.symtypenames[XLOFFSYMTYPE_LOCAL]   = "local"
xloff.symtypenames[XLOFFSYMTYPE_EXTERN]  = "extern"
xloff.symtypenames[XLOFFSYMTYPE_SPECIAL] = "special"

xloff.sectionflagnames = {}

xloff.sectionflagnames[0] = "BSS"
xloff.sectionflagnames[1] = "DEBUG"
xloff.sectionflagnames[2] = "TEXT"
xloff.sectionflagnames[3] = "MAP"
xloff.sectionflagnames[4] = "READONLY"

local XLOFFSPECIALVALUE_START = 1
local XLOFFSPECIALVALUE_SIZE  = 2
local XLOFFSPECIALVALUE_END   = 3

local XLOFFRELOC_LIMN2500_LONG = 1
local XLOFFRELOC_LIMN2500_ABSJ = 2
local XLOFFRELOC_LIMN2500_LA   = 3

local XLOFFRELOC_LIMN2600_FAR_INT  = 4
local XLOFFRELOC_LIMN2600_FAR_LONG = 5

xloff.relocnames = {}
xloff.relocnames[XLOFFRELOC_LIMN2500_LONG]     = "LONG"
xloff.relocnames[XLOFFRELOC_LIMN2500_ABSJ]     = "ABSJ"
xloff.relocnames[XLOFFRELOC_LIMN2500_LA]       = "LA"
xloff.relocnames[XLOFFRELOC_LIMN2600_FAR_LONG] = "FARLONG"
xloff.relocnames[XLOFFRELOC_LIMN2600_FAR_INT]  = "FARINT"

function xloff.new(filename)
	local img = {}

	img.filename = filename
	img.libname = filename

	img.bin = {}

	function img:getString(offset)
		local off = self.stringtable + offset

		local out = ""

		while self.bin[off] ~= 0 do
			out = out .. string.char(self.bin[off])

			off = off + 1
		end

		return out
	end

	function img:load()
		local file = io.open(self.filename, "rb")

		if not file then
			print("xoftool: can't open " .. self.filename)
			return false
		end

		local raw = file:read("*a")

		self.bin = {}

		for i = 1, #raw do
			self.bin[i-1] = string.byte(raw:sub(i,i))
		end

		file:close()

		self.header = cast(xloffheader_s, self.bin)
		local hdr = self.header

		local magic = hdr.gv("Magic")

		if magic ~= XLOFFMAGIC then
			print(string.format("xoftool: '%s' isn't an XLOFF format image", self.filename))
			return false
		end

		self.archid = hdr.gv("TargetArchitecture")

		self.arch = archinfo[self.archid]

		if not self.arch then
			print(string.format("xoftool: '%s' is for an unknown architecture", self.filename))
			return false
		end

		self.entrysymbolindex = hdr.gv("EntrySymbol")

		self.flags = hdr.gv("Flags")

		self.timestamp = hdr.gv("Timestamp")

		self.headlength = hdr.gv("HeadLength")

		self.stringtable = hdr.gv("StringTableOffset")

		if band(self.flags, XLOFFFLAG_ALIGN4K) ~= 0 then
			self.pagealignrequired = 4096
		end

		self.externsbyname = {}
		self.globalsbyname = {}

		self.sectionsbyname = {}
		self.sectionsbyid = {}

		self.sectiontable = hdr.gv("SectionTableOffset")
		self.sectioncount = hdr.gv("SectionCount")

		local sectionheader = self.sectiontable

		for i = 0, self.sectioncount-1 do
			local shdr = cast(sectionheader_s, self.bin, sectionheader)

			local section = {}

			section.name = self:getString(shdr.gv("NameOffset"))
			section.filoffset = shdr.gv("DataOffset")
			section.size = shdr.gv("DataSize")
			section.vaddr = shdr.gv("VirtualAddress")
			section.relocfiloff = shdr.gv("RelocTableOffset")
			section.reloccount = shdr.gv("RelocCount")
			section.flags = shdr.gv("Flags")

			section.id = i

			self.sectionsbyid[i] = section
			self.sectionsbyname[section.name] = section

			if band(section.flags, XLOFFSECTIONFLAG_BSS) == 0 then
				section.data = {}

				for i = 0, section.size-1 do
					section.data[i] = self.bin[section.filoffset+i]
				end
			end

			sectionheader = sectionheader + sectionheader_s.size()
		end

		self.importsbyname = {}
		self.importsbyid = {}

		self.importtable = hdr.gv("ImportTableOffset")
		self.importcount = hdr.gv("ImportCount")

		local importstr = self.importtable

		for i = 0, self.importcount-1 do
			local importc = cast(import_s, self.bin, importstr)

			local import = {}

			import.name = self:getString(importc.gv("NameOffset"))
			import.timestamp = importc.gv("ExpectedTimestamp")
			import.fixuptable = importc.gv("FixupTableOffset")
			import.fixupcount = importc.gv("FixupCount")

			self.importsbyid[i] = import
			self.importsbyname[import.name] = import

			importstr = importstr + import_s.size()
		end

		self.symbolsbyname = {}
		self.symbolsbyid = {}

		self.symboltable = hdr.gv("SymbolTableOffset")
		self.symbolcount = hdr.gv("SymbolCount")

		local symbolstr = self.symboltable

		for i = 0, self.symbolcount-1 do
			local symbolc = cast(symbol_s, self.bin, symbolstr)

			local symbol = {}

			if symbolc.gv("NameOffset") ~= 0xFFFFFFFF then
				symbol.name = self:getString(symbolc.gv("NameOffset"))
			end

			symbol.value = symbolc.gv("Value")
			symbol.type = symbolc.gv("Type")
			symbol.flags = symbolc.gv("Flags")

			if symbol.type ~= XLOFFSYMTYPE_EXTERN then
				symbol.sectionindex = symbolc.gv("SectionIndex")
			else
				symbol.importindex = symbolc.gv("SectionIndex")

				if symbol.importindex ~= 0xFFFF then
					symbol.import = self.importsbyid[symbol.importindex]
				end
			end

			if symbol.sectionindex then
				symbol.section = self.sectionsbyid[symbol.sectionindex]
			end

			self.symbolsbyid[i] = symbol

			if symbol.name then
				self.symbolsbyname[symbol.name] = symbol
			end

			if symbol.type == XLOFFSYMTYPE_EXTERN then
				self.externsbyname[symbol.name] = symbol
			elseif symbol.type == XLOFFSYMTYPE_GLOBAL then
				self.globalsbyname[symbol.name] = symbol
			end

			symbolstr = symbolstr + symbol_s.size()
		end

		if self.entrysymbolindex ~= 0xFFFFFFFF then
			self.entrysymbol = self.sectionsbyid[self.entrysymbolindex]
		end

		-- load relocations

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			section.relocs = {}

			local relocstr = section.relocfiloff

			for j = 0, section.reloccount-1 do
				local relocc = cast(reloc_s, self.bin, relocstr)

				local reloc = {}

				reloc.offset = relocc.gv("Offset")
				reloc.symbolindex = relocc.gv("SymbolIndex")
				reloc.type = relocc.gv("RelocType")
				reloc.sectionindex = i

				reloc.section = section

				section.relocs[#section.relocs+1] = reloc

				if reloc.symbolindex ~= 0xFFFFFFFF then
					reloc.symbol = self.symbolsbyid[reloc.symbolindex]
				end

				relocstr = relocstr + reloc_s.size()
			end
		end

		-- load import fixups

		for i = 0, self.importcount-1 do
			local import = self.importsbyid[i]

			import.fixups = {}

			local fixupstr = import.fixuptable

			for j = 0, import.fixupcount-1 do
				local fixupc = cast(reloc_s, self.bin, fixupstr)

				local fixup = {}

				fixup.offset = fixupc.gv("Offset")
				fixup.symbolindex = fixupc.gv("SymbolIndex")
				fixup.type = fixupc.gv("RelocType")
				fixup.sectionindex = fixupc.gv("SectionIndex")

				fixup.section = self.sectionsbyid[fixup.sectionindex]

				fixup.import = import

				import.fixups[#import.fixups+1] = fixup

				if fixup.symbolindex ~= 0xFFFFFFFF then
					fixup.symbol = self.symbolsbyid[fixup.symbolindex]
				end

				fixupstr = fixupstr + reloc_s.size()
			end
		end

		return true
	end

	function img:needsalignment(sid)
		for i = sid+1, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			if (band(section.flags, XLOFFSECTIONFLAG_BSS) == 0) and (section.size > 0) then
				return true
			end
		end

		return false
	end

	function img:write()
		-- trashes the structures. should be re-load()-ed if you wanna keep
		-- using it.

		-- encoding an executable in lua: believe it or not this used to be even more gross.
	
		-- basically what's going on here is that we iterate through all the relevant structures,
		-- sometimes multiple times, and update their IDs and whatnot to reflect where they'll
		-- end up in the on-file tables. Then we do a final pass to actually manufacture and
		-- write the binary.

		local binary = ""

		local headertab = {}

		local header = cast(xloffheader_s, headertab)

		local function addTab(tab, size)
			if size == 0 then return end

			for i = 0, size-1 do
				binary = binary .. string.char(tab[i])
			end
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

		local secheadertab = {}
		local secheadertaboff = 0
		local secheadertabindex = 0

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]
			section.id = i

			section.headerc = cast(sectionheader_s, secheadertab, secheadertaboff)

			if self:needsalignment(i) then
				if img.pagealignrequired then
					while band(section.size, img.pagealignrequired-1) ~= 0 do
						if band(section.flags, XLOFFSECTIONFLAG_BSS) == 0 then
							section.data[section.size] = 0
						end

						section.size = section.size + 1
					end
				else
					while band(section.size, 3) ~= 0 do
						if band(section.flags, XLOFFSECTIONFLAG_BSS) == 0 then
							section.data[section.size] = 0
						end

						section.size = section.size + 1
					end
				end
			end

			section.reloctable = {}
			section.reloctableoff = 0
			section.reloctableindex = 0

			section.nameoff = addString(section.name)

			section.headerc.sv("RelocTableOffset", 0)
			section.headerc.sv("RelocCount", 0)
			section.headerc.sv("VirtualAddress", section.vaddr)
			section.headerc.sv("NameOffset", section.nameoff)
			section.headerc.sv("Flags", section.flags)

			secheadertaboff = secheadertaboff + sectionheader_s.size()
			secheadertabindex = secheadertabindex + 1
		end

		local importtab = {}
		local importtaboff = 0
		local importtabindex = 0

		for i = 0, self.importcount-1 do
			local off = importtabindex

			local import = self.importsbyid[i]
			import.id = i

			import.importc = cast(import_s, importtab, importtaboff)

			import.nameoff = addString(import.name)

			importtabindex = importtabindex + 1
			importtaboff = importtaboff + import_s.size()

			import.reloctable = {}
			import.reloctableoff = 0
			import.reloctableindex = 0

			import.importc.sv("NameOffset", import.nameoff)
			import.importc.sv("ExpectedTimestamp", import.timestamp)
			import.importc.sv("FixupTableOffset", 0)
			import.importc.sv("FixupCount", 0)

			return off
		end

		local symtab = {}
		local symtaboff = 0
		local symtabindex = 0

		local function addSymbol(symbol)
			local off = symtabindex

			symbol.id = symtabindex
			symbol.added = true

			local nameoff = 0xFFFFFFFF

			if symbol.name then
				if (symbol.type ~= "local") and (symbol.type ~= "special") then
					nameoff = addString(symbol.name)
				end
			end

			local sym = cast(symbol_s, symtab, symtaboff)

			local sid

			if symbol.type ~= XLOFFSYMTYPE_EXTERN then
				sid = symbol.section.id
			else
				if symbol.import then
					sid = symbol.import.id
				else
					sid = 0xFFFF
				end
			end

			sym.sv("NameOffset", nameoff)
			sym.sv("Value", symbol.value)
			sym.sv("SectionIndex", sid)
			sym.sv("Type", symbol.type)
			sym.sv("Flags", 0)

			symtabindex = symtabindex + 1
			symtaboff = symtaboff + symbol_s.size()

			return off
		end

		for i = 0, img.symbolcount-1 do
			local sym = img.symbolsbyid[i]

			if (sym.type ~= XLOFFSYMTYPE_LOCAL) or (not self.lstrip) then
				if (sym.type ~= XLOFFSYMTYPE_GLOBAL) or (not self.gstrip) then
					if not addSymbol(img.symbolsbyid[i]) then return false end
				end
			end
		end

		-- we won't be adding anymore strings so make sure to align the string table to 32 bits.

		while band(stringtaboff, 3) ~= 0 do
			stringtab[stringtaboff] = 0
			stringtaboff = stringtaboff + 1
		end

		local filoff = xloffheader_s.size()
		local symtabfiloff = filoff

		filoff = filoff + symtaboff
		local stringtabfiloff = filoff

		filoff = filoff + stringtaboff

		local function addRelocation(section, symbol, offset, rtype, sectionindex)
			local off = section.reloctableindex

			local reloc = cast(reloc_s, section.reloctable, section.reloctableoff)

			reloc.sv("Offset", offset)

			if symbol then
				reloc.sv("SymbolIndex", symbol.id)
				symbol.rrefs = symbol.rrefs + 1
			else
				reloc.sv("SymbolIndex", -1)
			end

			reloc.sv("RelocType", rtype)
			reloc.sv("SectionIndex", sectionindex)

			section.reloctableindex = section.reloctableindex + 1
			section.reloctableoff = section.reloctableoff + reloc_s.size()

			return off
		end

		-- add all the internal relocations

		if not self.istrip then
			for i = 0, self.sectioncount-1 do
				local section = self.sectionsbyid[i]

				for i,r in ipairs(section.relocs) do
					if (not r.symbol) or (r.symbol.added) then
						if not addRelocation(section, r.symbol, r.offset, r.type, 0xFFFF) then return false end
					end
				end

				local shdr = section.headerc

				shdr.sv("RelocTableOffset", filoff)
				shdr.sv("RelocCount", section.reloctableindex)

				filoff = filoff + section.reloctableoff
			end
		end

		-- add all the import fixups and finalize import table entries

		if not self.fstrip then
			for i = 0, self.importcount-1 do
				local import = self.importsbyid[i]

				for i,r in ipairs(import.fixups) do
					if not addRelocation(import, r.symbol, r.offset, r.type, r.section.id) then return false end
				end

				local shdr = import.importc

				shdr.sv("FixupTableOffset", filoff)
				shdr.sv("FixupCount", import.reloctableindex)

				filoff = filoff + import.reloctableoff
			end
		end

		-- finalize the section headers

		local importfiloff = filoff
		filoff = filoff + import_s.size()*self.importcount

		local sectionhdrfiloff = filoff
		filoff = filoff + sectionheader_s.size()*self.sectioncount

		local headlength = filoff

		local alignamt = 0

		if self.pagealignrequired then
			alignamt = self.pagealignrequired-band(headlength, (self.pagealignrequired-1))
			headlength = headlength + alignamt
			filoff = filoff + alignamt
		end

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			local shdr = section.headerc

			if band(section.flags, XLOFFSECTIONFLAG_BSS) ~= 0 then
				shdr.sv("DataOffset", 0)
			else
				shdr.sv("DataOffset", filoff)
			end

			shdr.sv("DataSize", section.size)

			if band(section.flags, XLOFFSECTIONFLAG_BSS) == 0 then
				filoff = filoff + section.size
			end
		end

		-- construct header

		for i = 0, xloffheader_s.size()-1 do
			headertab[i] = 0
		end

		header.sv("Magic", XLOFFMAGIC)

		header.sv("SymbolTableOffset", symtabfiloff)
		header.sv("SymbolCount", symtabindex)

		header.sv("StringTableOffset", stringtabfiloff)
		header.sv("StringTableSize", stringtaboff)

		header.sv("TargetArchitecture", self.archid)

		if self.entrysymbol then
			header.sv("EntrySymbol", self.entrysymbol.id)
		else
			header.sv("EntrySymbol", 0xFFFFFFFF)
		end

		if self.pagealignrequired == 4096 then
			self.flags = bor(self.flags, XLOFFFLAG_ALIGN4K)
		else
			self.flags = band(self.flags, bnot(XLOFFFLAG_ALIGN4K))
		end

		header.sv("Flags", self.flags)

		header.sv("Timestamp", self.timestamp)

		header.sv("SectionTableOffset", sectionhdrfiloff)
		header.sv("SectionCount", self.sectioncount)

		header.sv("ImportTableOffset", importfiloff)
		header.sv("ImportCount", self.importcount)

		header.sv("HeadLength", headlength)

		-- write everything out

		addTab(headertab, xloffheader_s.size())
		addTab(symtab, symtaboff)
		addTab(stringtab, stringtaboff)

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			addTab(section.reloctable, section.reloctableoff)
		end

		for i = 0, self.importcount-1 do
			local import = self.importsbyid[i]

			addTab(import.reloctable, import.reloctableoff)
		end

		addTab(importtab, importtaboff)
		addTab(secheadertab, secheadertaboff)

		-- align the header up to a page

		for i = 1, alignamt do
			binary = binary..string.char(0)
		end

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			if band(section.flags, XLOFFSECTIONFLAG_BSS) == 0 then
				addTab(section.data, section.size)
			end
		end

		local file = io.open(self.filename, "wb")

		if not file then
			print("xoftool: can't open " .. self.filename .. " for writing")
			return false
		end

		file:write(binary)

		file:close()
	end

	return img
end

return xloff