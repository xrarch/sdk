local format = {}

format.name = "xloff"

local XLOFFMAGIC = 0x99584F46

local xloffheader_s = struct {
	{4, "Magic"},
	{4, "SizeOfRecord"},
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
	{4, "SizeOfRecord"},
	{4, "NameOffset"},
	{4, "DataOffset"},
	{4, "DataSize"},
	{4, "VirtualAddress"},
	{4, "RelocOffset"},
	{4, "RelocCount"}
}

local symbol_s = struct {
	{4, "NameOffset"},
	{4, "Value"},
	{2, "SectionIndex"},
	{1, "Type"},
	{1, "Flags"}
}

local import_s = struct {
	{4, "SizeOfRecord"},
	{4, "NameOffset"},
	{4, "ExpectedTimestamp"},
	{4, "FixupOffset"},
	{4, "FixupCount"}
}

local reloc_s = struct {
	{4, "Offset"},
	{4, "SymbolIndex"},
	{2, "RelocType"},
	{2, "SectionIndex"}
}

return format