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
	{4, "ExpectedBase"},
	{4, "FixupTableOffset"},
	{4, "FixupCount"}
}

local reloc_s = struct {
	{4, "Offset"},
	{4, "SymbolIndex"},
	{2, "RelocType"},
	{2, "SectionIndex"}
}

local XLOFFRELOC_LIMN2500_LONG     = 1
local XLOFFRELOC_LIMN2500_ABSJ     = 2
local XLOFFRELOC_LIMN2500_LA       = 3
local XLOFFRELOC_LIMN2600_FAR_INT  = 4
local XLOFFRELOC_LIMN2600_FAR_LONG = 5

local archinfo = {}

archinfo[0] = {}
archinfo[0].name = "UNKNOWN"
archinfo[0].id = 0

archinfo[1] = {}
archinfo[1].name = "limn2600"
archinfo[1].align = 4
archinfo[1].id = 1

archinfo[1].dofixup = function (tab, off, nval, rtype)
	local old = gv32(tab, off)
	local new = old

	if rtype == XLOFFRELOC_LIMN2500_ABSJ then
		new = bor(band(old, 0x7), lshift(band(rshift(nval, 2), 0x1FFFFFFF), 3))
	elseif rtype == XLOFFRELOC_LIMN2500_LONG then
		new = nval
	elseif rtype == XLOFFRELOC_LIMN2500_LA then
		local old2 = gv32(tab, off + 4)
		local new2 = bor(lshift(band(nval, 0xFFFF), 16), band(old2, 0xFFFF))

		new = bor(band(nval, 0xFFFF0000), band(old, 0xFFFF))

		sv32(tab, off + 4, new2)
	elseif rtype == XLOFFRELOC_LIMN2600_FAR_INT then
		local old2 = gv32(tab, off + 4)
		local new2 = bor(lshift(rshift(band(nval, 0xFFFF), 1), 16), band(old2, 0xFFFF))

		new = bor(band(nval, 0xFFFF0000), band(old, 0xFFFF))

		sv32(tab, off + 4, new2)
	elseif rtype == XLOFFRELOC_LIMN2600_FAR_LONG then
		local old2 = gv32(tab, off + 4)
		local new2 = bor(lshift(rshift(band(nval, 0xFFFF), 2), 16), band(old2, 0xFFFF))

		new = bor(band(nval, 0xFFFF0000), band(old, 0xFFFF))

		sv32(tab, off + 4, new2)
	else
		error("unknown relocation type "..rtype)
	end

	sv32(tab, off, new)
end

archinfo[1].dostub = function (section, ptr)
	-- create a call stub template at the end of the given section.
	-- make sure to grow it.

	local stublocation = section.size
	section.size = section.size + 4

	sv32(section.data, stublocation, bor(lshift(rshift(ptr, 2), 3), 6))

	return stublocation, 4, XLOFFRELOC_LIMN2500_ABSJ
end

archinfo[1].shouldredirect = function (section, fixup)
	-- determine if a fixup should be redirected to a call stub.
	return fixup.type == XLOFFRELOC_LIMN2500_ABSJ
end

local XLOFFFLAG_ALIGN4K  = 1
local XLOFFFLAG_FRAGMENT = 2
local XLOFFFLAG_ISTRIP   = 4  -- can't be internally relocated
local XLOFFFLAG_GSTRIP   = 8  -- can't be dynamically linked against
local XLOFFFLAG_FSTRIP   = 16 -- can't be fixed up

local XLOFFSYMTYPE_GLOBAL  = 1
local XLOFFSYMTYPE_LOCAL   = 2
local XLOFFSYMTYPE_EXTERN  = 3
local XLOFFSYMTYPE_SPECIAL = 4
local XLOFFSYMTYPE_DEXTERN = 5

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
	["dextern"] = XLOFFSYMTYPE_DEXTERN,
}

xloff.symtypenames = {}
xloff.symtypenames[XLOFFSYMTYPE_GLOBAL]  = "global"
xloff.symtypenames[XLOFFSYMTYPE_LOCAL]   = "local"
xloff.symtypenames[XLOFFSYMTYPE_EXTERN]  = "extern"
xloff.symtypenames[XLOFFSYMTYPE_SPECIAL] = "special"
xloff.symtypenames[XLOFFSYMTYPE_DEXTERN]  = "dextern"

xloff.sectionflagnames = {}

xloff.sectionflagnames[0] = "BSS"
xloff.sectionflagnames[1] = "DEBUG"
xloff.sectionflagnames[2] = "TEXT"
xloff.sectionflagnames[3] = "MAP"
xloff.sectionflagnames[4] = "READONLY"

local XLOFFSPECIALVALUE_START = 1
local XLOFFSPECIALVALUE_SIZE  = 2
local XLOFFSPECIALVALUE_END   = 3

xloff.relocnames = {}
xloff.relocnames[XLOFFRELOC_LIMN2500_LONG]     = "LONG"
xloff.relocnames[XLOFFRELOC_LIMN2500_ABSJ]     = "ABSJ"
xloff.relocnames[XLOFFRELOC_LIMN2500_LA]       = "LA"
xloff.relocnames[XLOFFRELOC_LIMN2600_FAR_LONG] = "FARLONG"
xloff.relocnames[XLOFFRELOC_LIMN2600_FAR_INT]  = "FARINT"

function xloff.new(filename)
	local img = {}

	img.filename = filename
	img.libname = getfilename(filename)

	img.bin = {}

	img.sectionsbyid = {}
	img.sectionsbyname = {}
	img.symbolsbyid = {}
	img.symbolsbyname = {}
	img.importsbyid = {}
	img.importsbyname = {}
	img.symbolcount = 0
	img.sectioncount = 0
	img.importcount = 0
	img.flags = 0
	img.timestamp = 0

	img.sortablesymbols = {}

	img.arch = archinfo[0]

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

		if band(self.flags, XLOFFFLAG_FRAGMENT) ~= 0 then
			self.fragment = true
		end

		if band(self.flags, XLOFFFLAG_ISTRIP) ~= 0 then
			self.istrip = true
		end

		if band(self.flags, XLOFFFLAG_GSTRIP) ~= 0 then
			self.gstrip = true
		end

		if band(self.flags, XLOFFFLAG_FSTRIP) ~= 0 then
			self.fstrip = true
		end

		self.sectionsbyname = {}
		self.sectionsbyid = {}

		self.sectiontable = hdr.gv("SectionTableOffset")
		self.sectioncount = hdr.gv("SectionCount")

		local sectionheader = self.sectiontable

		for i = 0, self.sectioncount-1 do
			local shdr = cast(sectionheader_s, self.bin, sectionheader)

			local section = {}

			section.file = self.filename

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
			import.expectedbase = importc.gv("ExpectedBase")
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

			symbol.file = self.filename

			symbol.value = symbolc.gv("Value")
			symbol.type = symbolc.gv("Type")
			symbol.flags = symbolc.gv("Flags")

			if (symbol.type ~= XLOFFSYMTYPE_EXTERN) and (symbol.type ~= XLOFFSYMTYPE_DEXTERN) then
				symbol.sectionindex = symbolc.gv("SectionIndex")
			elseif symbol.type == XLOFFSYMTYPE_DEXTERN then
				symbol.importindex = symbolc.gv("SectionIndex")
				symbol.import = self.importsbyid[symbol.importindex]
			end

			if symbol.sectionindex then
				symbol.section = self.sectionsbyid[symbol.sectionindex]
			end

			self.symbolsbyid[i] = symbol

			if symbol.name then
				self.symbolsbyname[symbol.name] = symbol
			end

			self.sortablesymbols[#self.sortablesymbols+1] = symbol

			symbolstr = symbolstr + symbol_s.size()
		end

		if self.entrysymbolindex ~= 0xFFFFFFFF then
			self.entrysymbol = self.symbolsbyid[self.entrysymbolindex]
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

	function img:binary(nobss)
		local file = io.open(self.filename, "wb")

		if not file then
			print("xoftool: can't open " .. self.filename .. " for writing")
			return false
		end

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			if band(section.flags, XLOFFSECTIONFLAG_BSS) == 0 then
				for j = 0, section.size-1 do
					file:write(string.char(section.data[j]))
				end
			elseif not nobss then
				for j = 0, section.size-1 do
					file:write(string.char(0))
				end
			end
		end

		file:close()

		return true
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
			if size == 0 then return "" end

			local nstr = ""

			for i = 0, size-1 do
				nstr = nstr .. string.char(tab[i])
			end

			return nstr
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
			import.importc.sv("ExpectedBase", import.expectedbase)
			import.importc.sv("FixupTableOffset", 0)
			import.importc.sv("FixupCount", 0)
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

			if (symbol.type ~= XLOFFSYMTYPE_EXTERN) and (symbol.type ~= XLOFFSYMTYPE_DEXTERN) then
				sid = symbol.section.id
			elseif (symbol.type == XLOFFSYMTYPE_DEXTERN) then
				sid = symbol.import.id
			else
				sid = 0xFFFF
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
				if (sym.type ~= XLOFFSYMTYPE_GLOBAL) or (not self.gstrip) or (sym == self.entrysymbol) then
					if ((sym.type ~= XLOFFSYMTYPE_EXTERN) and (sym.type ~= XLOFFSYMTYPE_DEXTERN)) or (not self.fstrip) then
						if not addSymbol(img.symbolsbyid[i]) then return false end
					end
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
					if (not r.dyresolved) and ((not r.symbol) or (r.symbol.added)) then
						if not addRelocation(section, r.symbol, r.offset, r.type, r.section.id) then return false end
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

		header.sv("TargetArchitecture", self.arch.id)

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

		if self.fragment then
			self.flags = bor(self.flags, XLOFFFLAG_FRAGMENT)
		else
			self.flags = band(self.flags, bnot(XLOFFFLAG_FRAGMENT))
		end

		if self.istrip or self.lstrip then
			self.flags = bor(self.flags, XLOFFFLAG_ISTRIP)
		end

		if self.gstrip then
			self.flags = bor(self.flags, XLOFFFLAG_GSTRIP)
		end

		if self.fstrip then
			self.flags = bor(self.flags, XLOFFFLAG_FSTRIP)
		end

		header.sv("Flags", self.flags)

		header.sv("Timestamp", self.timestamp)

		header.sv("SectionTableOffset", sectionhdrfiloff)
		header.sv("SectionCount", self.sectioncount)

		header.sv("ImportTableOffset", importfiloff)
		header.sv("ImportCount", self.importcount)

		header.sv("HeadLength", headlength)

		-- write everything out

		binary = binary .. addTab(headertab, xloffheader_s.size())
		binary = binary .. addTab(symtab, symtaboff)
		binary = binary .. addTab(stringtab, stringtaboff)

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			binary = binary .. addTab(section.reloctable, section.reloctableoff)
		end

		for i = 0, self.importcount-1 do
			local import = self.importsbyid[i]

			binary = binary .. addTab(import.reloctable, import.reloctableoff)
		end

		binary = binary .. addTab(importtab, importtaboff)
		binary = binary .. addTab(secheadertab, secheadertaboff)

		-- align the header up to a page

		for i = 1, alignamt do
			binary = binary..string.char(0)
		end

		local file = io.open(self.filename, "wb")

		if not file then
			print("xoftool: can't open " .. self.filename .. " for writing")
			return false
		end

		file:write(binary)

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			if band(section.flags, XLOFFSECTIONFLAG_BSS) == 0 then
				for j = 0, section.size-1 do
					file:write(string.char(section.data[j]))
				end
			end
		end

		file:close()

		return true
	end

	function img:mergesection(section)
		-- merge a foreign section into this image.
		-- first we have to match it with a section we already have, meaning
		-- the name and the flags are identical. then we can merge those.
		-- if we don't have a matching section, just copy it over directly.

		local oursection
		local found = false

		for i = 0, self.sectioncount-1 do
			oursection = self.sectionsbyid[i]

			if oursection.name == section.name then
				if oursection.flags ~= section.flags then
					print("xoftool: "..section.file..": flag mismatch in section '"..section.name.."'")
					return false
				end

				found = true

				break
			end
		end

		if not found then
			-- create a new empty section

			oursection = {}

			oursection.name = section.name
			oursection.flags = section.flags
			oursection.vaddr = section.vaddr
			oursection.size = 0
			oursection.data = {}
			oursection.relocs = {}

			self.sectionsbyname[section.name] = oursection
			self.sectionsbyid[self.sectioncount] = oursection

			self.sectioncount = self.sectioncount + 1
		end

		section.forward = oursection
		section.offsetinfile = oursection.size

		-- merge relocation list

		for k,v in ipairs(section.relocs) do
			local reloc = {}

			oursection.relocs[#oursection.relocs+1] = reloc

			reloc.symbol = v.symbol
			reloc.type = v.type
			reloc.section = oursection
			reloc.offset = v.offset + oursection.size
		end

		-- merge data

		local osz = oursection.size

		if band(section.flags, XLOFFSECTIONFLAG_BSS) == 0 then
			for i = 0, section.size-1 do
				oursection.data[osz+i] = section.data[i]
			end
		end

		oursection.size = oursection.size + section.size

		return true
	end

	function img:reloc(section, movefixups)
		-- relocate a section to its base virtual address

		for k,v in ipairs(section.relocs) do
			local sym = v.symbol

			if v.symbol.forward then
				sym = v.symbol.forward
				v.symbol = v.symbol.forward
			end

			if (sym.stubsym) and (self.arch.shouldredirect(section, v)) then
				sym = sym.stubsym

				v.symbol = sym
			end

			if sym then
				if sym.import and (not v.dyresolved) and movefixups then
					-- this is a DLL fixup and hasn't already been moved,
					-- so move it to the fixup table for that import.

					local fixup = {}

					fixup.symbol = v.symbol
					fixup.offset = v.offset
					fixup.type = v.type
					fixup.section = v.section

					sym.import.fixups[#sym.import.fixups+1] = fixup

					v.dyresolved = true
				else
					local nval

					local wsection = sym.section

					if wsection and wsection.forward then
						wsection = wsection.forward
					end

					if sym.type == XLOFFSYMTYPE_SPECIAL then
						if sym.value == XLOFFSPECIALVALUE_START then
							nval = wsection.vaddr
						elseif sym.value == XLOFFSPECIALVALUE_SIZE then
							nval = wsection.size
						elseif sym.value == XLOFFSPECIALVALUE_END then
							nval = wsection.vaddr + wsection.size
						end
					elseif wsection then
						nval = sym.value + wsection.vaddr
					else
						nval = sym.value
					end

					-- print(string.format("%s %s $%x %d", v.symbol.name, v.file, v.offset, v.type))

					self.arch.dofixup(section.data, v.offset, nval, v.type)
				end
			end
		end

		return true
	end

	function img:relocate()
		-- should be run after img:link() has been used to link all of the
		-- object files together.

		-- for each section, iterate its internal relocations and perform them.

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			if not self:reloc(section, true) then return false end
		end

		-- finally, perform all external fixups.

		for i = 0, self.importcount-1 do
			local import = self.importsbyid[i]

			for k,v in ipairs(import.fixups) do
				self.arch.dofixup(v.section.data, v.offset, v.symbol.value, v.type)
			end
		end

		return true
	end

	function img:gettextsection()
		-- return first section with TEXT flag

		for i = 0, self.sectioncount-1 do
			local section = self.sectionsbyid[i]

			if band(section.flags, XLOFFSECTIONFLAG_TEXT) ~= 0 then
				return section
			end
		end

		return false
	end

	function img:import(withimg)
		-- check to see if this DLL has already been imported

		if self.importsbyname[withimg.libname] then
			return true
		end

		local text = self:gettextsection()

		-- create an import table entry. then go through all our externs and
		-- try to associate them with a global symbol found in the DLL.
		-- then go through all of our internal relocations and lift any that
		-- refer to this DLL into its table of fixups. if stubbing is enabled,
		-- create jump stubs for each of the imported symbols.

		local import = {}

		import.name = withimg.libname
		import.timestamp = withimg.timestamp
		import.expectedbase = withimg.sectionsbyid[0].vaddr
		import.fixups = {}
		import.fixupcount = 0

		self.importsbyname[withimg.libname] = import
		self.importsbyid[self.importcount] = import
		self.importcount = self.importcount + 1

		for k,sym in pairs(self.symbolsbyname) do
			if sym.type == XLOFFSYMTYPE_EXTERN then
				local lookup = withimg.symbolsbyname[sym.name]

				if lookup and (lookup.type == XLOFFSYMTYPE_GLOBAL) then
					sym.type = XLOFFSYMTYPE_DEXTERN
					sym.import = import
					sym.value = lookup.value + lookup.section.vaddr
					sym.flags = lookup.flags

					lookup.forward = sym

					if not self.nostubs then
						-- create a call stub at the end of our text section.
						-- this is a tactic to reduce COWs when performing
						-- fixups for a DLL that wasn't loaded at its
						-- preferred location.

						local stublocation, stubsize, reloctype = self.arch.dostub(text, 0)

						-- create a local symbol for the call stub.

						local stubsym = {}

						stubsym.file = self.filename

						stubsym.type = XLOFFSYMTYPE_LOCAL
						stubsym.section = text
						stubsym.value = stublocation
						stubsym.flags = 0

						self.sortablesymbols[#self.sortablesymbols+1] = stubsym
						self.symbolcount = self.symbolcount + 1

						sym.stubsym = stubsym

						-- create a fixup for the call stub.

						local reloc = {}

						reloc.symbol = sym
						reloc.offset = stublocation
						reloc.type = reloctype
						reloc.file = self.filename
						reloc.section = text

						import.fixups[#import.fixups+1] = reloc
					end
				end
			end
		end

		return true
	end

	function img:link(withimg, dynamic)
		if self.arch == archinfo[0] then
			self.arch = withimg.arch
		end

		self.timestamp = os.time(os.date("!*t"))

		if not dynamic then
			-- merge the sections and their relocation tables.
			-- then merge the symbol tables, making sure to discard extraneous externs and resolve those who find a match.
			-- doesn't relocate, that's done by img:relocate(), which also snaps foreign relocations into place to refer to
			-- our symbols.

			for i = 0, withimg.sectioncount-1 do
				local section = withimg.sectionsbyid[i]

				if not img:mergesection(section) then return false end
			end

			for i = 0, withimg.symbolcount-1 do
				local sym = withimg.symbolsbyid[i]

				local lookup

				if sym.name then
					lookup = self.symbolsbyname[sym.name]
				end

				if lookup then
					if (sym.type == XLOFFSYMTYPE_GLOBAL) and (lookup.type == XLOFFSYMTYPE_EXTERN) then
						-- overwrite our extern symbol with their global symbol

						lookup.file = sym.filename

						lookup.type = XLOFFSYMTYPE_GLOBAL
						lookup.section = sym.section.forward
						lookup.value = sym.value + sym.section.offsetinfile
						lookup.flags = sym.flags
						lookup.name = sym.name
					elseif (sym.type == XLOFFSYMTYPE_GLOBAL) and (lookup.type == XLOFFSYMTYPE_GLOBAL) then
						-- collision! error
						print(string.format("xoftool: symbol conflict: '%s' is defined in both:\n %s\n %s", sym.name, sym.file, lookup.file))
						return false
					elseif (sym.type == XLOFFSYMTYPE_EXTERN) and (lookup.type == XLOFFSYMTYPE_GLOBAL) then
						-- resolved, forward theirs to ours
					elseif (sym.type == XLOFFSYMTYPE_EXTERN) and (lookup.type == XLOFFSYMTYPE_EXTERN) then
						-- resolved, forward theirs to ours
					elseif (sym.type == XLOFFSYMTYPE_SPECIAL) and (lookup.type == XLOFFSYMTYPE_SPECIAL) then
						-- resolved, forward theirs to ours
					else
						-- weird situation! error
						error(string.format("weird situation: %d %d", sym.type, lookup.type))
					end
				else
					-- copy, make sure to capture the filename for error messages.

					lookup = {}

					lookup.file = sym.filename
					lookup.type = sym.type
					lookup.name = sym.name

					if sym.section then
						lookup.section = sym.section.forward
					end

					lookup.flags = sym.flags

					if sym.type == XLOFFSYMTYPE_SPECIAL then
						lookup.value = sym.value
					elseif sym.section then
						lookup.value = sym.value + sym.section.offsetinfile
					else
						lookup.value = sym.value
					end

					if sym.name then
						self.symbolsbyname[sym.name] = lookup
					end

					self.sortablesymbols[#self.sortablesymbols+1] = lookup
					self.symbolcount = self.symbolcount + 1
				end

				sym.forward = lookup
			end

			if self.entrysymbol and withimg.entrysymbol then
				print(string.format("xoftool: conflicting entry symbols: '%s' and '%s'", self.entrysymbol.name, withimg.entrysymbol.name))
				return false
			elseif (not self.entrysymbol) and (withimg.entrysymbol) then
				self.entrysymbol = withimg.entrysymbol.forward
			end
		else
			return self:import(withimg)
		end

		return true
	end

	function img:sortsymbols()
		-- should be called after a link is complete.

		table.sort(self.sortablesymbols, function (s1,s2)
			local s1t = s1.section
			local s2t = s2.section

			if not s1t then return false end
			if not s2t then return true end

			return (s1.value + s1t.vaddr) < (s2.value + s2t.vaddr)
		end)

		for i = 1, #self.sortablesymbols do
			self.symbolsbyid[i-1] = self.sortablesymbols[i]
		end
	end

	function img:checkunresolved()
		local unr = {}

		for i = 0, self.symbolcount-1 do
			local sym = self.symbolsbyid[i]

			if sym.type == XLOFFSYMTYPE_EXTERN then
				unr[#unr + 1] = sym
			end
		end

		if #unr > 0 then
			print("xoftool: error: unresolved symbols:")

			for k,v in ipairs(unr) do
				print(string.format("  %s: %s", v.file, v.name))
			end

			return false
		end

		return true
	end

	function img:gensymtab(symtabfile, textoff)
		local symtab = io.open(symtabfile, "w")

		if not symtab then
			print("xoftool: couldn't open "..tostring(arg[2]).." for writing")
			return false
		end

		symtab:write(".section data\n\nSymbolTable:\n.global SymbolTable\n")

		local syms = 0

		local names = ""

		local donesym = {}

		for i = 0, self.symbolcount-1 do
			local sym = self.symbolsbyid[i]

			local section = sym.section

			if (sym.type == XLOFFSYMTYPE_GLOBAL) and (band(section.flags, XLOFFSECTIONFLAG_TEXT) ~= 0) and (not donesym[sym.name]) then
				symtab:write("\t.dl __SYMNAM"..tostring(i).."\n")
				symtab:write("\t.dl "..tostring(sym.value + section.vaddr + textoff).."\n")

				names = names.."__SYMNAM"..tostring(i)..":\n\t.ds "..sym.name.."\n\t.db 0x0\n"

				syms = syms + 1

				symtab:write("\n")

				donesym[sym.name] = true
			end
		end

		symtab:write("SymbolCount:\n.global SymbolCount\n\t.dl "..tostring(syms).."\n\n")

		symtab:write(names)

		symtab:write("\n.align 4\n")

		symtab:close()

		return true
	end

	return img
end

return xloff