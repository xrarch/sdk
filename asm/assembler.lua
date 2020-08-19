
-- got rewritten to be 100x better but is still sort of iffy, don't poke it too much

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

local targets = {
	["limn2k"] = 0x2,
}

local function lerror(line, err)
	print(string.format("asm: %s:%d: %s", line.file, line.number, err))
end

local function dumpAllLines(block)
	local lines = block.lines

	print("== line dump ==")

	for k,v in ipairs(lines) do
		if v.text then
			print(string.format("%s:%d: %s", v.file, v.number, v.text))
		end
	end
end

local function ttokenize(str)
	local tokens = {}

	if #str == 0 then return tokens end

	local ctok = ""

	local raw = false

	for i = 1, #str do
		local c = str:sub(i,i)

		if not raw then
			if c == "\\" then
				ctok = ctok .. (str:sub(i+1,i+1) or "")

				i = i + 1
			elseif c == ";" then
				break
			elseif (c == " ") or (c == "\t") then
				if #ctok > 0 then
					if ctok:sub(-1,-1) == "," then
						ctok = ctok:sub(1,-2)
					elseif (ctok == ".ds") and (#tokens == 0) then
						raw = true
						i = i + 1
					end

					tokens[#tokens + 1] = ctok
					ctok = ""
				end
			else
				ctok = ctok .. c
			end
		else
			ctok = ctok .. c
		end

		i = i + 1
	end

	if (#ctok > 0) or raw then
		tokens[#tokens + 1] = ctok
	end

	return tokens
end

local asm = {}

function asm.lines(block, source, filename, lnum)
	local lines = block.lines

	local llit = lineate(source)

	local lnum = lnum or 0

	local pseudo = block.pseudo

	for n,line in ipairs(llit) do
		lnum = lnum + 1

		local tt = ttokenize(line)

		if #tt > 0 then
			if tt[1] == ".include" then
				local srcf = io.open(block.basedir .. "/" .. tt[2], "r")
				if not srcf then
					print(string.format("asm: %s:%d: file not found", filename, lnum))
					return false
				end

				if not asm.lines(block, srcf:read("*a"), tt[2]) then return false end

				srcf:close()
			elseif pseudo[tt[1]] then
				local pi = pseudo[tt[1]]

				if (#tt - 1) < pi[1] then
					print(string.format("asm: %s:%d: not enough arguments", filename, lnum))
					return false
				end

				if not asm.lines(block, pi[2](tt), filename, lnum-1) then return false end
			else
				lines[#lines + 1] = {}

				local key = #lines

				lines[key].text = line
				lines[key].file = filename
				lines[key].number = lnum
				lines[key].tokens = tt

				lines[key].destroy = function (self)
					self.text = nil
				end

				lines[key].replace = function (self, text)
					self.text = text
					self.tokens = ttokenize(text)
				end
			end
		end
	end

	return true
end

local function section(block, id, bss)
	local me = {}

	local symtab = block.symtab

	me.bss = bss

	me.contents = ""

	me.size = 0

	me.tbc = 0

	me.id = id

	me.fixups = {}

	function me:addByte(byte)
		if not self.bss then
			self.contents = self.contents .. string.char(band(byte, 0xFF))
		end

		self.size = self.size + 1
	end

	function me:addInt(int)
		if not self.bss then
			local u1, u2 = splitInt16(int)

			self.contents = self.contents .. string.char(u2) .. string.char(u1)
		end

		self.size = self.size + 2
	end

	function me:addTriplet(three)
		if not self.bss then
			local u1, u2, u3 = splitInt24(three)

			self.contents = self.contents .. string.char(u3) .. string.char(u2) .. string.char(u1)
		end

		self.size = self.size + 3
	end

	function me:addLong(long)
		if not self.bss then
			local u1, u2, u3, u4 = splitInt32(long)

			self.contents = self.contents .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		end

		self.size = self.size + 4
	end

	function me:setGlobal(name)
		symtab:getSymbol(name).symtype = "global"
	end

	function me:addLocal(name, off)
		return symtab:addSymbol(name, self, "local", off)
	end

	function me:addFixup(sym, off, size, divisor)
		if size < 0 then return end

		self.fixups[#self.fixups + 1] = {}
		self.fixups[#self.fixups].sym = sym
		self.fixups[#self.fixups].value = off
		self.fixups[#self.fixups].size = size
		self.fixups[#self.fixups].divisor = (divisor or 1)
	end

	me.fixuptab = ""
	me.fixupcount = 0

	function me:addBinaryFixup(symindex, offset, size, divisor)
		local u1, u2, u3, u4 = splitInt32(symindex)
		self.fixuptab = self.fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		u1, u2, u3, u4 = splitInt32(offset)
		self.fixuptab = self.fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		u1, u2, u3, u4 = splitInt32(size)
		self.fixuptab = self.fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		u1, u2, u3, u4 = splitInt32(divisor)
		self.fixuptab = self.fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		self.fixupcount = self.fixupcount + 1
	end

	return me
end

function asm.labels(block)
	block.sections = {}
	block.sections["text"] = section(block, 1)
	block.sections["data"] = section(block, 2)
	block.sections["bss"] = section(block, 3, true)

	block.localLabels = {}
	block.localLabelsSym = {}

	local curStruct = false
	local strCount = 0
	local curLabel

	local inst = block.inst
	local regs = block.regs

	local section = block.sections["text"]

	local symtab = block.symtab

	symtab:addSymbol("_text", block.sections["text"], "special", 1)
	symtab:addSymbol("_text_size", block.sections["text"], "special", 2)
	symtab:addSymbol("_text_end", block.sections["text"], "special", 3)

	symtab:addSymbol("_data", block.sections["data"], "special", 1)
	symtab:addSymbol("_data_size", block.sections["data"], "special", 2)
	symtab:addSymbol("_data_end", block.sections["data"], "special", 3)

	symtab:addSymbol("_bss", block.sections["bss"], "special", 1)
	symtab:addSymbol("_bss_size", block.sections["bss"], "special", 2)
	symtab:addSymbol("_bss_end", block.sections["bss"], "special", 3)

	for k,v in ipairs(block.lines) do
		local tokens = v.tokens

		local word = tokens[1]

		if curStruct then
			if word == ".end-struct" then
				symtab:addConstant(curStruct.."_sizeof", strCount)
				curStruct = false
				strCount = 0
			elseif #tokens == 2 then
				symtab:addConstant(curStruct.."_"..tokens[2], strCount)

				local sz = tonumber(word)

				if not sz then
					lerror(v, "malformed struct entry")
					return false
				end

				strCount = strCount + sz
			else
				lerror(v, "malformed struct entry")
				return false
			end

			v:destroy()
		else
			v.section = section
			v.offset = {section.tbc}

			if word:sub(-1,-1) == ":" then -- label
				if word:sub(1,1) == "." then -- local label
					if not curLabel then
						lerror(v, "can't define local label when no label has been defined yet")
						return false
					end

					local ll = block.localLabels[curLabel]

					if ll[word:sub(2,-2)] then
						lerror(v, "can't define local label '"..word:sub(2,-2).."' twice")
						return false
					end

					ll[word:sub(2,-2)] = section.tbc

					block.localLabelsSym[curLabel][word:sub(2,-2)] = section:addLocal("_"..curLabel.."."..word:sub(2,-2), section.tbc)

					v:destroy()
				else
					local sy = symtab:getSymbol(word:sub(1,-2))

					if sy and sy.symtype ~= "extern" then
						lerror(v, "can't define symbol '"..word:sub(1,-2).."' twice.")
						return false
					else
						curLabel = word:sub(1,-2)

						section:addLocal(curLabel, section.tbc)

						block.localLabels[curLabel] = {}
						block.localLabelsSym[curLabel] = {}
					end
				end
			elseif tokens[2] == "===" then
				local value = tokens[3]

				if not value then
					lerror(v, "unfinished constant definition")
					return false
				end

				if symtab:getSymbol(word) then
					lerror(v, "can't define constant; symbol '"..word.."' cannot be defined twice.")
					return false
				end

				symtab:addConstant(word, tonumber(tokens[3]))

				v:destroy()
			elseif word == ".section" then
				if tokens[2] then
					if not block.sections[tokens[2]] then
						lerror(v, "not a section")
						return false
					else
						section = block.sections[tokens[2]]
					end
				else
					lerror(v, "no name provided for section")
					return false
				end
			elseif word == ".struct" then
				curStruct = tokens[2]

				if not curStruct then
					lerror(v, "no name provided for struct")
					return false
				end

				v:destroy()
			elseif word == ".static" then
				local path = tokens[2]

				if not path then
					lerror(v, "no path for .static")
					return false
				end

				local file = io.open(block.basedir .. "/" .. path, "r")

				if not file then
					lerror(v, "can't open file '"..path.."'")
					return false
				end

				local sc = file:read("*a")

				local size = file:seek("end")

				file:close()

				v.static = sc
				v.staticsize = size

				section.tbc = section.tbc + size
				v.offset[2] = size
			elseif word == ".db" then
				if #tokens == 1 then
					lerror(v, ".db needs 2+ arguments")
					return false
				end

				v.offsets = {}

				for i = 2, #tokens do
					v.offsets[#v.offsets + 1] = {section.tbc, 1}
					section.tbc = section.tbc + 1
				end
			elseif word == ".di" then
				if #tokens == 1 then
					lerror(v, ".di needs 2+ arguments")
					return false
				end

				v.offsets = {}

				for i = 2, #tokens do
					v.offsets[#v.offsets + 1] = {section.tbc, 2}
					section.tbc = section.tbc + 2
				end
			elseif word == ".dl" then
				if #tokens == 1 then
					lerror(v, ".dl needs 2+ arguments")
					return false
				end

				v.offsets = {}

				for i = 2, #tokens do
					v.offsets[#v.offsets + 1] = {section.tbc, 4}
					section.tbc = section.tbc + 4
				end
			elseif word == ".ds" then
				section.tbc = section.tbc + #tokens[2]
				v.offset[2] = #tokens[2]
			elseif word == ".ds$" then
				if #tokens == 1 then
					lerror(v, ".ds$ needs a symbol")
					return false
				end

				if not block.constants[tokens[2]] then
					lerror(v, "'"..tokens[2].."' is not a symbol")
					return false
				end

				section.tbc = section.tbc + #tostring(block.constants[tokens[2]])
				v.offset[2] = #tostring(block.constants[tokens[2]])
			elseif word == ".bytes" then
				if tonumber(tokens[2]) then
					section.tbc = section.tbc + tonumber(tokens[2])
					v.offset[2] = tonumber(tokens[2])
				else
					lerror(v, ".bytes: invalid number")
					return false
				end
			elseif word == ".bc" then
				if not tokens[2] then
					lerror(v, ".bc: needs symbol")
					return false
				end

				if tokens[2] == "@" then
					v:replace(".bc "..tostring(byteCount))
				end
			elseif word == ".align" then
				if tokens[2] then
					if tonumber(tokens[2]) then
						section.tbc = math.ceil(section.tbc / tonumber(tokens[2])) * tonumber(tokens[2])
					else
						lerror(v, ".align: invalid number")
						return false
					end
				else
					lerror(v, ".align: unfinished align")
					return false
				end
			elseif word == ".global" then
				if not tokens[2] then
					lerror(v, ".global: needs symbol")
					return false
				end

				if not symtab:getSymbol(tokens[2]) then
					lerror(v, ".global: '"..tokens[2].."' is not a symbol")
					return false
				end

				section:setGlobal(tokens[2])

				v:destroy()
			elseif word == ".extern" then
				if not tokens[2] then
					lerror(v, ".extern: needs symbol name")
					return false
				end

				if symtab:getSymbol(tokens[2]) then
					lerror(v, ".extern: '"..tokens[2].."' is already a symbol")
					return false
				end

				symtab:addExtern(tokens[2])

				v:destroy()
			elseif word == ".entry" then
				local sym = symtab:getSymbol(tokens[2])

				if not sym then
					lerror(v, ".entry: '"..tokens[2].."' is not a symbol")
					return false
				end

				if sym.symtype ~= "global" then
					lerror(v, ".entry: '"..tokens[2].."' must be a global to be set as the entry point")
					return false
				end

				symtab:setEntry(tokens[2])

				v:destroy()
			else
				local e = inst[word]

				if not e then
					lerror(v, "not an instruction: "..word)
					return false
				end

				v.offsets = {}

				local off = section.tbc + 1

				for i = 1, #e[3] do
					v.offsets[#v.offsets + 1] = {off, e[3][i], e[5]}

					off = off + e[3][i]
				end

				section.tbc = section.tbc + e[1]

				v.offset[2] = e[1]
				v.offset[3] = e[5]
			end

		end
	end

	return true
end

local QSY = 0

function asm.decode(block) -- decode labels, registers, strings
	local curLabel

	local inst = block.inst
	local regs = block.regs

	local symtab = block.symtab

	for k,v in ipairs(block.lines) do
		if v.text then
			local tokens = v.tokens

			local word = tokens[1]

			local lout = ""

			if word:sub(-1,-1) == ":" then
				curLabel = word:sub(1,-2)
				v:destroy()
			else
				if (word == ".ds") or (word == ".static") or (word == ".section") then
					lout = v.text
				elseif word == ".ds$" then
					lout = ".ds " .. tostring(block.constants[tokens[2]])
				else
					local e = inst[word]

					for n,t in ipairs(tokens) do
						if n == 1 then
							lout = t
						else
							if t:sub(1,1) == '"' then
								if #t == 3 then
									if t:sub(-1,-1) == '"' then
										lout = lout .. " " .. string.byte(t:sub(2,2))
									else
										lerror(v, "unclosed char")
										return false
									end
								else
									lerror(v, "cannot use a multi-byte char (fixme?)")
									return false
								end
							elseif tonumber(t) then
								lout = lout .. " " .. t
							elseif t:sub(1,1) == "." then -- local label
								local ll = block.localLabels[curLabel][t:sub(2)]

								local llsym = block.localLabelsSym[curLabel][t:sub(2)]

								local nofix = false

								if ll then
									if e and e[3][n-1] < 0 then
										nofix = true

										lout = lout .. " " .. tostring(ll - v.offset[1])
									else
										lout = lout .. " " .. tostring(ll)
									end
								else
									lerror(v, "not a local label: '"..t:sub(2).."'")
									return false
								end

								if (word ~= ".bc") and (not nofix) then
									if v.offsets then
										if v.offsets[n-1] then
											v.section:addFixup(llsym, v.offsets[n-1][1], v.offsets[n-1][2], v.offsets[n-1][3])
										else
											lerror(v, "unrecoverable condition")
											return false
										end
									elseif v.offset then
										v.section:addFixup(llsym, v.offset[1], v.offset[2], v.offset[3])
									else
										lerror(v, "unrecoverable condition")
										return false
									end
								end
							elseif regs[t] then
								lout = lout .. " " .. tostring(regs[t])
							elseif symtab:getSymbol(t) then
								local sym = symtab:getSymbol(t)

								if sym.symtype == "constant" then
									lout = lout .. " " .. tostring(sym.value)
								else
									local psym = sym

									if (sym.symtype == "local") or (sym.symtype == "global") then
										if sym.section == v.section then
											if e and e[3][n-1] < 0 then
												psym = -1

												lout = lout .. " " .. tostring(sym.value - v.offset[1])
											else
												lout = lout .. " " .. tostring(sym.value)
											end
										else
											lout = lout .. " 0"
										end
									elseif (sym.symtype == "extern") or (sym.symtype == "special") then
										sym.count = sym.count + 1
										lout = lout .. " 0"
									else
										error("huh")
									end

									if (word ~= ".bc") and (psym ~= -1) then
										if v.offsets then
											if v.offsets[n-1] then
												v.section:addFixup(psym, v.offsets[n-1][1], v.offsets[n-1][2], v.offsets[n-1][3])
											else
												error("huh")
											end
										elseif v.offset then
											v.section:addFixup(psym, v.offset[1], v.offset[2], v.offset[3])
										else
											error("huh")
										end
									end
								end
							else
								lerror(v, t .. " is not a symbol")
								return false
							end
						end
					end
				end

				v:replace(lout)
			end
		end
	end

	return true
end

local loffheader_s = struct({
	{4, "magic"},
	{4, "symbolTableOffset"},
	{4, "symbolCount"},
	{4, "stringTableOffset"},
	{4, "stringTableSize"},
	{4, "targetArchitecture"},
	{4, "entrySymbol"},
	{4, "stripped"},
	{28, "reserved"},
	{4, "textHeaderOffset"},
	{4, "dataHeaderOffset"},
	{4, "bssHeaderOffset"},
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
})

local fixup_s = struct({
	{4, "symbolIndex"},
	{4, "offset"},
	{4, "size"},
	{4, "divisor"},
})

function asm.binary(block, lex)
	local inst = block.inst
	local regs = block.regs

	local strtab = ""
	local strtabsize = 0

	local function addString(contents)
		local off = strtabsize

		strtab = strtab .. contents .. string.char(0)

		strtabsize = strtabsize + #contents + 1

		return off
	end

	local symtab = ""
	local symtabindex = 0

	local function addSymbol(name, section, symtype, value)
		local off = symtabindex

		local nameoff = addString(name)

		local u1, u2, u3, u4 = splitInt32(nameoff)
		symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		u1, u2, u3, u4 = splitInt32(section)
		symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		u1, u2, u3, u4 = splitInt32(symtype)
		symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		u1, u2, u3, u4 = splitInt32(value)
		symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		symtabindex = symtabindex + 1

		return off
	end

	local symindex = {}

	local symtypid = {
		["global"] = 1,
		["local"] = 2,
		["extern"] = 3,
		["special"] = 4,
		["weak"] = 5,
	}

	for k,v in pairs(block.symtab.symtab) do
		if (v.symtype ~= "constant") and (v.count > 0) then
			local ix = addSymbol(k, v.section.id, symtypid[v.symtype] or 0xFFFFFFFF, v.value)

			v.index = ix

			symindex[ix] = v
		end
	end

	local section = block.sections["data"]

	for k,v in ipairs(section.fixups) do
		section:addBinaryFixup(v.sym.index, v.value, v.size, v.divisor)
	end

	section = block.sections["text"]

	for k,v in ipairs(section.fixups) do
		section:addBinaryFixup(v.sym.index, v.value, v.size, v.divisor)
	end

	while strtabsize % 4 ~= 0 do
		strtab = strtab..string.char(0)
		strtabsize = strtabsize + 1
	end

	for k,v in ipairs(block.lines) do
		if v.text then
			local tokens = v.tokens

			local word = tokens[1]

			if word == ".static" then
				section.contents = section.contents .. v.static
				section.size = section.size + v.staticsize
			elseif word == ".section" then
				section = block.sections[tokens[2]]
			elseif word == ".db" then
				for i = 2, #tokens do
					local e = tokens[i]
					if tonumber(e) then
						section:addByte(tc(e))
					else
						lerror(v, "invalid bytelist")
						return false
					end
				end
			elseif word == ".di" then
				for i = 2, #tokens do
					local e = tokens[i]
					if tonumber(e) then
						section:addInt(tc(e))
					else
						lerror(v, "invalid intlist")
						return false
					end
				end
			elseif word == ".dl" then
				for i = 2, #tokens do
					local e = tokens[i]
					if tonumber(e) then
						section:addLong(tc(e))
					else
						lerror(v, "invalid longlist")
						return false
					end
				end
			elseif word == ".ds" then
				local contents = tokens[2]
				section.contents = section.contents..contents
				section.size = section.size + #contents
			elseif word == ".bytes" then
				if (not tonumber(tokens[2])) or (not tonumber(tokens[3])) then
					lerror(v, "bad numbers on .bytes")
					return false
				end

				for i = 1, tonumber(tokens[2]) do
					section:addByte(tonumber(tokens[3]))
				end
			elseif word == ".bc" then
				if #tokens == 1 then
					print("bytecount: "..string.format("%x",codesize))
				elseif #tokens == 2 then
					if not tonumber(tokens[2]) then
						lerror(v, "strange .bc")
						return false
					end

					print("bytecount: "..string.format("%x",tokens[2]))
				end
			elseif word == ".align" then
				if not tonumber(tokens[2]) then
					lerror(v, "bad number on .align")
					return false
				end

				while section.size % tonumber(tokens[2]) ~= 0 do
					section:addByte(0)
				end
			else
				if section.size % block.ialign ~= 0 then
					lerror(v, "instruction not aligned to "..tostring(block.ialign).." bytes")
					return false
				end

				local cs = section.size

				local e = inst[word]

				section:addByte(e[2])

				local rands = e[3] -- the names 'rand, operand

				if #tokens-1 ~= #rands then
					lerror(v, "operand count mismatch: "..word.." wants "..tostring(#rands).." operands, "..tostring(#tokens-1).." given.")
					return false
				end

				for n,s in ipairs(rands) do
					s = math.abs(s)

					local operand = tonumber(tokens[n+1])
					if not operand then
						lerror(v, "malformed number "..tokens[n+1])
						return false
					end

					if e[4] then
						operand = e[4](n, operand)
					end

					if math.floor(operand) ~= operand then
						lerror(v, "unaligned operand on "..word)
						return false
					end

					if s == 1 then
						section:addByte(tc(operand))
					elseif s == 2 then
						section:addInt(tc(operand))
					elseif s == 3 then
						section:addTriplet(tc(operand))
					elseif s == 4 then
						section:addLong(tc(operand))
					end
				end

				while (section.size-cs) < e[1] do
					section:addByte(0)
				end
			end
		end
	end

	for k,v in pairs(block.sections) do
		if not v.bss then
			while v.size % 4 ~= 0 do
				v.contents = v.contents..string.char(0)
				v.size = v.size + 1
			end
		end
	end

	if lex then
		-- make header
		local size = 72

		local header = "2FOL"

		-- symbolTableOffset
		local u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + (symtabindex * symbol_s.size())

		-- symbolCount
		u1, u2, u3, u4 = splitInt32(symtabindex)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- stringTableOffset
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + strtabsize

		-- stringTableSize
		u1, u2, u3, u4 = splitInt32(strtabsize)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- targetArchitecture
		u1, u2, u3, u4 = splitInt32(targets[block.target])
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- entrySymbol
		local entryidx = 0xFFFFFFFF
		if block.symtab.entry then
			entryidx = block.symtab.entry.index
		end
		u1, u2, u3, u4 = splitInt32(entryidx)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- reserved
		for i = 0, 31 do
			header = header .. string.char(0)
		end

		local ts = block.sections["text"]
		local ds = block.sections["data"]
		local bs = block.sections["bss"]

		-- textHeaderOffset
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + sectionheader_s.size()

		-- dataHeaderOffset
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + sectionheader_s.size()

		-- bssHeaderOffset
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + sectionheader_s.size()

		local textHeader = ""

		-- fixupTableOffset
		u1, u2, u3, u4 = splitInt32(size)
		textHeader = textHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + (ts.fixupcount * fixup_s.size())

		-- fixupCount
		u1, u2, u3, u4 = splitInt32(ts.fixupcount)
		textHeader = textHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- sectionOffset
		u1, u2, u3, u4 = splitInt32(size)
		textHeader = textHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + ts.size

		-- sectionSize
		u1, u2, u3, u4 = splitInt32(ts.size)
		textHeader = textHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- linkedAddress
		textHeader = textHeader .. string.char(0) .. string.char(0) .. string.char(0) .. string.char(0)

		local dataHeader = ""

		-- fixupTableOffset
		u1, u2, u3, u4 = splitInt32(size)
		dataHeader = dataHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + (ds.fixupcount * fixup_s.size())

		-- fixupCount
		u1, u2, u3, u4 = splitInt32(ds.fixupcount)
		dataHeader = dataHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- sectionOffset
		u1, u2, u3, u4 = splitInt32(size)
		dataHeader = dataHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + ds.size

		-- sectionSize
		u1, u2, u3, u4 = splitInt32(ds.size)
		dataHeader = dataHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- linkedAddress
		dataHeader = dataHeader .. string.char(0) .. string.char(0) .. string.char(0) .. string.char(0)

		local bssHeader = ""

		-- fixupTableOffset
		bssHeader = bssHeader .. string.char(0) .. string.char(0) .. string.char(0) .. string.char(0)

		-- fixupCount
		bssHeader = bssHeader .. string.char(0) .. string.char(0) .. string.char(0) .. string.char(0)

		-- sectionOffset
		bssHeader = bssHeader .. string.char(0) .. string.char(0) .. string.char(0) .. string.char(0)

		-- sectionSize
		u1, u2, u3, u4 = splitInt32(bs.size)
		bssHeader = bssHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- linkedAddress
		bssHeader = bssHeader .. string.char(0) .. string.char(0) .. string.char(0) .. string.char(0)

		block.binary = header .. symtab .. strtab .. textHeader .. dataHeader .. bssHeader .. ts.fixuptab .. ts.contents .. ds.fixuptab .. ds.contents
	else
		block.binary = block.sections["text"].contents
	end

	return true
end

local function symtab(block)
	local sym = {}

	sym.symtab = {}

	local sytab = sym.symtab

	sym.entry = nil



	function sym:addSymbol(name, section, symtype, value, count)
		sytab[name] = {}
		sytab[name].section = section
		sytab[name].symtype = symtype
		sytab[name].value = value
		sytab[name].count = count or 1

		return sytab[name]
	end

	function sym:addConstant(name, value)
		block.constants[name] = value

		sym:addSymbol(name, nil, "constant", value)
	end

	function sym:addExtern(name)
		self:addSymbol(name, {["id"]=0}, "extern", 0, 0)
	end

	function sym:getSymbol(name)
		return sytab[name]
	end

	function sym:setEntry(name)
		self.entry = self:getSymbol(name)
	end

	return sym
end

function asm.assembleBlock(target, source, filename, flat)
	local block = {}

	block.target = target

	if not targets[target] then
		print("asm: no such target "..target)
		return false
	end

	local tinst = dofile(sd.."inst-"..target..".lua")
	block.inst, block.regs, block.ialign, block.pseudo = tinst[1], tinst[2], tinst[4], tinst[6]

	block.constants = {}

	block.symtab = symtab(block)

	block.symtab:addConstant("__DATE", os.date())

	for k,v in pairs(tinst[3]) do
		block.symtab:addConstant(k, v)
	end

	block.lines = {}

	block.statics = {}

	block.symtab = symtab(block)

	block.basedir = getdirectory(filename)

	if not asm.lines(block, source, filename) then return false end

	if not asm.labels(block) then return false end

	if not asm.decode(block) then return false end

	if not asm.binary(block, not flat) then return false end

	return block
end

function asm.assemble(target, source, filename, flat)
	local block = asm.assembleBlock(target, source, filename, flat)

	if not block then return false end

	return block.binary
end

return asm