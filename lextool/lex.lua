local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

dofile(sd.."misc.lua")

local lex = {}

local header_s = struct {
	{4, "magic"},
	{4, "symbolTableOffset"},
	{4, "symbolCount"},
	{4, "stringTableOffset"},
	{4, "stringTableSize"},
	{4, "relocTableOffset"},
	{4, "relocCount"},
	{4, "fixupTableOffset"},
	{4, "fixupCount"},
	{4, "codeOffset"},
	{4, "codeSize"}
}

local symbol_s = struct {
	{4, "name"},
	{4, "value"}
}

local fixup_s = struct {
	{4, "name"},
	{4, "addr"}
}

local uint32_s = struct {
	{4, "value"}
}

function lex.new(filename)
	local ilex = {}

	ilex.path = filename

	ilex.bin = {}

	ilex.fixups = {}

	ilex.symbols = {}

	ilex.relocs = {}

	ilex.code = {}

	function ilex:load()
		local file = io.open(self.path, "rb")

		if not file then
			print("lextool: can't open " .. self.path)
			return false
		end

		self.raw = file:read("*a")
		local craw = self.raw

		for i = 1, #craw do
			self.bin[i-1] = string.byte(craw:sub(i,i))
		end

		file:close()

		self.header = cast(header_s, self.bin)
		local hdr = self.header

		if hdr.gv("magic") ~= 0x4C455830 then
			print(string.format("lextool: '%s' has bad magic %X", self.path, hdr.gv("magic")))
			return false
		end

		local codeoff = self.header.gv("codeOffset")
		local codesize = self.header.gv("codeSize")

		self.code = {}

		for i = 0, codesize - 1 do
			self.code[i] = self.bin[i + codeoff]
		end

		local function getString(offset)
			local off = self.header.gv("stringTableOffset") + offset

			local out = ""

			while self.bin[off] ~= 0 do
				out = out .. string.char(self.bin[off])

				off = off + 1
			end

			return out
		end

		local ptr

		self.symbols = {}
		local symcount = hdr.gv("symbolCount")
		ptr = hdr.gv("symbolTableOffset")

		for i = 1, symcount do
			local sym = cast(symbol_s, self.bin, ptr)

			local name = getString(sym.gv("name"))
			local value = sym.gv("value")

			self.symbols[name] = value

			ptr = ptr + 8
		end

		self.fixups = {}
		local fixcount = hdr.gv("fixupCount")
		ptr = hdr.gv("fixupTableOffset")

		for i = 1, fixcount do
			local f = cast(fixup_s, self.bin, ptr)

			local name = getString(f.gv("name"))
			local addr = f.gv("addr")

			self.fixups[#self.fixups + 1] = {name, addr}

			ptr = ptr + 8
		end

		self.relocs = {}
		local reloccount = hdr.gv("relocCount")
		ptr = hdr.gv("relocTableOffset")

		for i = 1, reloccount do
			local r = cast(uint32_s, self.bin, ptr)

			self.relocs[#self.relocs + 1] = r.gv("value")

			ptr = ptr + 4
		end

		function self:relocBy(offset)
			if #self.relocs > 0 then
				if offset > 0 then
					for k,v in ipairs(self.relocs) do
						local addrs = cast(uint32_s, self.code, v)

						local addr = addrs.gv("value")

						addrs.sv("value", addr + offset)
					end
				end
			end
		end

		function self:relocInFile(offset)
			self:relocBy(offset)

			for k,v in ipairs(self.relocs) do
				self.relocs[k] = v + offset
			end

			for k,v in pairs(self.symbols) do
				self.symbols[k] = v + offset
			end

			for k,v in ipairs(self.fixups) do
				self.fixups[k] = {v[1], v[2] + offset}
			end
		end

		function self:flatten(base) -- saves to the object file implicitly
			base = base or 0

			if #self.fixups > 0 then
				print(string.format("lextool: I refuse to flatten a LEX file '%s' with hanging symbols", self.path))
				return false
			end

			local file = io.open(self.path, "wb")

			if not file then
				print("lextool: can't open " .. self.path .. " for writing")
				return false
			end

			if #self.relocs > 0 then
				print("lextool: relocation table available: relocating to $"..string.format("%X", base))

				self:relocBy(base)
			end

			for i = 0, #self.code do
				file:write(string.char(self.code[i]))
			end

			file:close()

			return true
		end

		return true
	end

	function ilex:write()
		local file = io.open(self.path, "wb")

		if not file then
			print("lextool: can't open " .. self.path .. " for writing")
			return false
		end

		local header = "0XEL"

		local strtab = ""
		local strtabsize = 0

		local function addString(contents)
			local off = strtabsize

			strtab = strtab .. contents .. string.char(0)

			strtabsize = strtabsize + #contents + 1

			return off
		end

		local symtab = ""
		local symtabsize = 0

		local function addSymbol(name, value)
			local off = symtabsize

			local nameoff = addString(name)

			local u1, u2, u3, u4 = splitInt32(nameoff)
			symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			u1, u2, u3, u4 = splitInt32(value)
			symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			symtabsize = symtabsize + 8

			return off
		end

		local reloctab = ""
		local reloctabsize = 0
		
		local function addRelocation(addr)
			local off = reloctabsize

			local u1, u2, u3, u4 = splitInt32(addr)
			reloctab = reloctab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			reloctabsize = reloctabsize + 4

			return off
		end

		local fixuptab = ""
		local fixuptabsize = 0

		local function addFixup(name, offset)
			local off = fixuptabsize

			local nameoff = addString(name)

			local u1, u2, u3, u4 = splitInt32(nameoff)
			fixuptab = fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			u1, u2, u3, u4 = splitInt32(offset)
			fixuptab = fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			fixuptabsize = fixuptabsize + 8

			return off
		end

		for k,v in ipairs(self.relocs) do
			addRelocation(v)
		end

		for k,v in pairs(self.symbols) do
			addSymbol(k, v)
		end

		for k,v in ipairs(self.fixups) do
			if v[1] then
				addFixup(v[1], v[2])
			end
		end

		-- make header
		local size = 44
		-- symtaboff
		local u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + symtabsize
		-- symcount
		u1, u2, u3, u4 = splitInt32(symtabsize / 8)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		-- strtaboff
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + strtabsize
		-- strtabsize
		u1, u2, u3, u4 = splitInt32(strtabsize)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		-- reloctaboff
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + reloctabsize
		-- reloccount
		u1, u2, u3, u4 = splitInt32(reloctabsize / 4)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		-- fixuptaboff
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + fixuptabsize
		-- fixupcount
		u1, u2, u3, u4 = splitInt32(fixuptabsize / 8)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		-- codeoff
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		-- codesize
		u1, u2, u3, u4 = splitInt32(#self.code + 1)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		file:write(header .. symtab .. strtab .. reloctab .. fixuptab)

		for i = 0, #self.code do
			file:write(string.char(self.code[i]))
		end

		file:close()

		return true
	end

	function ilex:link(with)
		--print(with.path)

		-- relocate by width of my own code

		with:relocInFile(#self.code)

		-- merge code

		local sc = #self.code -- weirdness because one-indexing, thanks lua

		for i = 0, #with.code do
			self.code[sc + i] = with.code[i]
		end

		-- merge symbols
		--print("merge symbols")

		for k,v in pairs(with.symbols) do
			--print(k)
			if self.symbols[k] then
				print(string.format("lextool: symbol conflict: '%s' is already defined! conflict caused by: '%s'", k, with.path))
				return false
			else
				self.symbols[k] = v
			end
		end

		-- merge fixups
		--print("merge fixups")

		for k,v in ipairs(with.fixups) do
			--print(v[1])
			self.fixups[#self.fixups + 1] = {v[1], v[2]}
		end

		-- merge relocs
		for k,v in ipairs(with.relocs) do
			self.relocs[#self.relocs + 1] = v
		end

		-- try to resolve fixups
		for k,v in ipairs(self.fixups) do
			if v[1] then
				if self.symbols[v[1]] then
					--print(string.format("resolving %s @ %X", v[1], v[2]))
					local addrs = cast(uint32_s, self.code, v[2])
					addrs.sv("value", self.symbols[v[1]])
					v[1] = nil -- can't take element out of array entirely because lua is weird, this marks it as dead

					-- convert fixup to a reloc
					self.relocs[#self.relocs + 1] = v[2]
				end
			end
		end

		return true
	end

	return ilex
end

return lex