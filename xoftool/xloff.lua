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
	{2, "SectionIndexOrExternOrdinal"},
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

xloff.sectionflagnames = {}

xloff.sectionflagnames[0] = "BSS"
xloff.sectionflagnames[1] = "DEBUG"
xloff.sectionflagnames[2] = "TEXT"
xloff.sectionflagnames[3] = "MAP"
xloff.sectionflagnames[4] = "READONLY"

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

			sectionheader = sectionheader + sectionheader_s.size()
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

			if symbol.type == XLOFFSYMTYPE_EXTERN then
				symbol.ordinal = symbolc.gv("SectionIndexOrExternOrdinal")
			else
				symbol.sectionindex = symbolc.gv("SectionIndexOrExternOrdinal")
			end

			if symbol.sectionindex then
				symbol.section = self.sectionsbyid[symbol.sectionindex]
			end

			self.symbolsbyid[i] = symbol

			if symbol.name then
				self.symbolsbyname[symbol.name] = symbol
			end

			symbolstr = symbolstr + symbol_s.size()
		end

		if self.entrysymbolindex ~= 0xFFFFFFFF then
			self.entrysymbol = self.sectionsbyid[self.entrysymbolindex]
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

	return img
end

return xloff