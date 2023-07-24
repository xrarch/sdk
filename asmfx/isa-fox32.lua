local isa = {}

isa.name = "fox32"

isa.bits = 32

isa.alignmask = 0x0

local formats = {}

isa.formats = formats

isa.registers = {
	-- ryfox assembler names

	["r0"]   = 0,
	["r1"]   = 1,
	["r2"]   = 2,
	["r3"]   = 3,
	["r4"]   = 4,
	["r5"]   = 5,
	["r6"]   = 6,
	["r7"]   = 7,
	["r8"]   = 8,
	["r9"]   = 9,
	["r10"]  = 10,
	["r11"]  = 11,
	["r12"]  = 12,
	["r13"]  = 13,
	["r14"]  = 14,
	["r15"]  = 15,
	["r16"]  = 16,
	["r17"]  = 17,
	["r18"]  = 18,
	["r19"]  = 19,
	["r20"]  = 20,
	["r21"]  = 21,
	["r22"]  = 22,
	["r23"]  = 23,
	["r24"]  = 24,
	["r25"]  = 25,
	["r26"]  = 26,
	["r27"]  = 27,
	["r28"]  = 28,
	["r29"]  = 29,
	["r30"]  = 30,
	["r31"]  = 31,

	["rsp"]  = 32,
	["resp"] = 33,
	["rfp"]  = 34,

	-- dragonfruit ABI names

	["t0"]   = 0,
	["t1"]   = 1,
	["t2"]   = 2,
	["t3"]   = 3,
	["t4"]   = 4,
	["t5"]   = 5,
	["t6"]   = 6,
	["a0"]   = 7,
	["a1"]   = 8,
	["a2"]   = 9,
	["a3"]   = 10,
	["s0"]   = 11,
	["s1"]   = 12,
	["s2"]   = 13,
	["s3"]   = 14,
	["s4"]   = 15,
	["s5"]   = 16,
	["s6"]   = 17,
	["s7"]   = 18,
	["s8"]   = 19,
	["s9"]   = 20,
	["s10"]  = 21,
	["s11"]  = 22,
	["s12"]  = 23,
	["s13"]  = 24,
	["s14"]  = 25,
	["s15"]  = 26,
	["s16"]  = 27,
	["s17"]  = 28,

	["at"]   = 29,
	
	["tp"]   = 30,
	["r31"]  = 31,
	["sp"]   = 32,
	["esp"]  = 33,
	["fp"]   = 34,
}

isa.controlregisters = {

}

isa.conditions = {}

isa.conditions.ifz = 1
isa.conditions.ifnz = 2
isa.conditions.ifc = 3
isa.conditions.iflt = 3
isa.conditions.ifnc = 4
isa.conditions.ifgteq = 4
isa.conditions.ifgt = 5
isa.conditions.iflteq = 6

local RELOC_FOX32_LONG = 1
local RELOC_FOX32_SRC  = 2
local RELOC_FOX32_DEST = 3
local RELOC_FOX32_JMP  = 4
local RELOC_FOX32_MDST = 5
local RELOC_FOX32_LDST = 6

function isa.relocate(sections)
	for k,v in pairs(sections) do
		local data = v.data

		for i,r in ipairs(v.relocations) do
			local nval = r.symbol.bc + r.symbol.section.origin

			if r.long then
				sv32(data, r.offset, nval)
			elseif r.field == "s" then
				sv32(data, r.offset + 2, nval)
			elseif r.field == "d" then
				if r.format.operandinfo.TT == 8 then
					sv32(data, r.offset + 3, nval)
				elseif r.format.operandinfo.TT == 16 then
					sv32(data, r.offset + 4, nval)
				else
					sv32(data, r.offset + 6, nval)
				end
			else
				error("weird relocation")
			end
		end
	end

	return true
end

function isa.reloctype(format, relocation)
	-- returns a relocation type number

	if (format.name == "loff") or (format.name == "xloff") then

		if relocation.long then
			return RELOC_FOX32_LONG
		elseif relocation.field == "s" then
			if relocation.format.jmp then
				return RELOC_FOX32_JMP
			else
				return RELOC_FOX32_SRC
			end
		elseif relocation.field == "d" then
			if relocation.format.operandinfo.TT == 8 then
				return RELOC_FOX32_DEST
			elseif relocation.format.operandinfo.TT == 16 then
				return RELOC_FOX32_MDST
			else
				return RELOC_FOX32_LDST
			end
		else
			error("weird relocation")
		end
	else
		print("asm: isa-fox32: I don't support "..format.name)
		return false
	end
end

local total = 0

local function addFormat(operandinfo, encodingstring, formatstring, jmp)
	total = total + 1
	local format = {}

	local tokens = {}

	format.operandinfo = operandinfo

	format.tokens = tokens

	local tok = ""

	for i = 1, #formatstring do
		local c = formatstring:sub(i,i)

		if c == " " then
			if #tok > 0 then
				tokens[#tokens + 1] = tok
			end

			tok = ""
		else
			tok = tok..c
		end
	end

	if #tok > 0 then
		tokens[#tokens + 1] = tok
	end

	format.bits = #encodingstring

	if band(format.bits, 7) ~= 0 then
		error("format bits isn't multiple of 8 " .. encodingstring)
	end

	format.bytes = format.bits/8

	format.encodingstring = encodingstring

	local encoding = {}

	format.encoding = encoding

	format.jmp = jmp

	local field = 0
	local fbits = 0

	local fn
	local fnbits = 0

	for i = 1, #encodingstring do
		local c = encodingstring:sub(i,i)

		if (c == "0") or (c == "1") then
			if fn then
				local et = {}
				et.bits = fnbits
				et.field = fn
				et.operand = operandinfo[fn]

				encoding[#encoding + 1] = et

				fn = nil
				fnbits = 0
			end

			fbits = fbits + 1

			field = field * 2 + tonumber(c)
		else
			if fbits > 0 then
				local et = {}
				et.bits = fbits
				et.field = field

				encoding[#encoding + 1] = et

				fbits = 0
				field = 0
			end

			if not fn then
				fn = c
				fnbits = 1
			elseif fn ~= c then
				local et = {}
				et.bits = fnbits
				et.field = fn
				et.operand = operandinfo[fn]

				encoding[#encoding + 1] = et

				fn = c
				fnbits = 1
			else
				fnbits = fnbits + 1
			end
		end
	end

	if fbits > 0 then
		local et = {}
		et.bits = fbits
		et.field = field

		encoding[#encoding + 1] = et
	elseif fnbits > 0 then
		local et = {}
		et.bits = fnbits
		et.field = fn
		et.operand = operandinfo[fn]

		encoding[#encoding + 1] = et
	end

	for i = 1, #encoding do
		local e = encoding[i]

		if type(e.field) ~= "number" then
			local q = e.operand

			if not q then
				q = {}
				operandinfo[e.field] = q
				e.operand = q
			end

			q.bits = (q.bits or 0) + e.bits

			local shift = q.shift or 0

			if operandinfo[e.field].intshift then
				q.max = 0xFFFFFFFF
			elseif q.bits == 32 then
				q.max = 0xFFFFFFFF
			else
				q.max = lshift(lshift(1, q.bits)-1, shift)
			end

			if q.max < 0 then
				q.max = 0xFFFFFFFF
			end
		end
	end

	local kt = formats[tokens[1]]

	if not kt then
		kt = {}
		formats[tokens[1]] = kt
	end

	table.insert(kt, format)
end

function numtobin(num, bits)
	local bitstr = ""

	for i = bits-1, 0, -1 do
		if band(rshift(num, i),1) == 1 then
			bitstr = bitstr .. "1"
		else
			bitstr = bitstr .. "0"
		end
	end

	return bitstr
end

function repeatbit(b, n)
	if n == 0 then return "" end

	local bitstr = ""

	for i = 1, n do
		bitstr = bitstr .. b
	end

	return bitstr
end

function makeFoxOpcode(opcode, size, condition, dest, src, hasoff)
	local bitstr = ""

	-- generate opcode byte

	bitstr = bitstr .. numtobin(size, 2)
	bitstr = bitstr .. numtobin(opcode, 6)

	-- generate condition byte

	if hasoff then
		bitstr = bitstr .. "1"
	else
		bitstr = bitstr .. "0"
	end

	bitstr = bitstr .. "ccc"
	bitstr = bitstr .. numtobin(dest, 2)
	bitstr = bitstr .. numtobin(src, 2)

	return bitstr
end

local sizes = {}

sizes["default"] = 2
sizes["8"] = 0
sizes["16"] = 1
sizes["32"] = 2

local instructions = {
	{
		"nop",
		0x00,
		0
	},
	{
		"add",
		0x01,
		2
	},
	{
		"mul",
		0x02,
		2
	},
	{
		"and",
		0x03,
		2
	},
	{
		"sla",
		0x04,
		2
	},
	{
		"sra",
		0x05,
		2
	},
	{
		"bse",
		0x06,
		2
	},
	{
		"cmp",
		0x07,
		2
	},
	{
		"jmp",
		0x08,
		1,
		true
	},
	{
		"rjmp",
		0x09,
		1,
		false,
		true
	},
	{
		"push",
		0x0A,
		1
	},
	{
		"in",
		0x0B,
		2
	},
	{
		"ise",
		0x0C,
		0
	},
	{
		"mse",
		0x0D,
		0
	},
	{
		"halt",
		0x10,
		0
	},
	{
		"inc",
		0x11,
		1
	},
	{
		"or",
		0x13,
		2
	},
	{
		"srl",
		0x15,
		2
	},
	{
		"bcl",
		0x16,
		2
	},
	{
		"mov",
		0x17,
		2
	},
	{
		"call",
		0x18,
		1,
		true
	},
	{
		"rcall",
		0x19,
		1,
		false,
		true
	},
	{
		"pop",
		0x1A,
		1
	},
	{
		"out",
		0x1B,
		2
	},
	{
		"icl",
		0x1C,
		0
	},
	{
		"mcl",
		0x1D,
		0
	},
	{
		"brk",
		0x20,
		0
	},
	{
		"sub",
		0x21,
		2
	},
	{
		"div",
		0x22,
		2
	},
	{
		"xor",
		0x23,
		2
	},
	{
		"rol",
		0x24,
		2
	},
	{
		"ror",
		0x25,
		2
	},
	{
		"bts",
		0x26,
		2
	},
	{
		"movz",
		0x27,
		2
	},
	{
		"loop",
		0x28,
		1,
		true
	},
	{
		"rloop",
		0x29,
		1,
		false,
		true
	},
	{
		"ret",
		0x2A,
		0
	},
	{
		"int",
		0x2C,
		1
	},
	{
		"tlb",
		0x2D,
		1
	},
	{
		"dec",
		0x31,
		2
	},
	{
		"rem",
		0x32,
		2
	},
	{
		"not",
		0x33,
		1
	},
	{
		"idiv",
		0x34,
		2
	},
	{
		"irem",
		0x35,
		2
	},
	{
		"rta",
		0x39,
		2,
		false,
		true
	},
	{
		"reti",
		0x3A,
		0
	},
	{
		"flp",
		0x3D,
		1
	},
}

local special8bitimm = {}

special8bitimm.sla = true
special8bitimm.srl = true
special8bitimm.sra = true
special8bitimm.rol = true
special8bitimm.ror = true
special8bitimm.bse = true
special8bitimm.bcl = true

-- type:
-- 0: register
-- 1: imm
-- 2: ptr

local optypesd = {
	{
		"[^rd]",
		1,
		0
	},
	{
		"[^rd + ^np]",
		1,
		0,
		true
	},
	{
		"[^nd]",
		3,
		2
	},
	{
		"^rd",
		0,
		0
	},
}

local optypess = {
	{
		"[^rs]",
		1,
		0
	},
	{
		"[^rs + ^no]",
		1,
		0,
		true
	},
	{
		"[^ns]",
		3,
		2
	},
	{
		"^rs",
		0,
		0
	},
	{
		"^ns",
		2,
		1
	}
}

function addFoxFormats(instr)
	local name = instr[1]
	local opcode = instr[2]
	local opcount = instr[3]

	local formatstr = name

	if opcount == 0 then
		local opinfo = {}

		addFormat(
			opinfo,
			makeFoxOpcode(opcode, 2, 0, 0, 0),
			formatstr,
			instr[4]
		)
	else
		for k2,v2 in pairs(sizes) do
			local bittage
			local f2

			if k2 ~= "default" then
				f2 = formatstr .. "." .. k2
				bittage = tonumber(k2)
			else
				f2 = formatstr
				bittage = 32
			end

			if opcount == 1 then
				for k3,v3 in ipairs(optypess) do
					local opfmt = v3[1]
					local opid = v3[2]
					local opreg = v3[3]

					local srcoffset = ""

					if hasoff then
						srcoffset = repeatbit("o", 8)
					end

					local opinf

					local fbittage

					if opreg == 0 then
						fbittage = 8
					elseif opreg == 1 then
						fbittage = bittage
					elseif opreg == 2 then
						fbittage = 32
					end

					local opinfo = {}

					if instr[5] then
						opinfo = {
							["s"] = {
								relative=true,
							}
						}
					end

					addFormat(
						opinfo,
						srcoffset..repeatbit("s", fbittage)..makeFoxOpcode(opcode, v2, 0, 0, opid, v3[4]),
						f2.." "..opfmt,
						instr[4]
					)
				end
			elseif opcount == 2 then
				for k3,v3 in ipairs(optypess) do
					local sfmt = v3[1]
					local sid = v3[2]
					local sreg = v3[3]

					local sbittage

					if sreg == 0 then
						sbittage = 8
					elseif sreg == 1 then
						if special8bitimm[name] then -- the shift instructions have special small imms
							sbittage = 8
						else
							sbittage = bittage
						end
					elseif sreg == 2 then
						sbittage = 32
					end

					for k4,v4 in ipairs(optypesd) do
						local dfmt = v4[1]
						local did = v4[2]
						local dreg = v4[3]

						local destoffset = ""
						local srcoffset = ""

						if v4[4] then
							if v3[2] == 1 then
								-- src is a reg

								if not v3[4] then
									-- put a dummy offset on the source
									srcoffset = "00000000"
								else
									srcoffset = repeatbit("o", 8)
								end
							end

							destoffset = repeatbit("p", 8)
						elseif v3[4] then
							if v4[2] == 1 then
								-- dest is a reg

								-- put a dummy offset on the dest
								destoffset = "00000000"
							end

							srcoffset = repeatbit("o", 8)
						else
							srcoffset = ""
						end

						local dbittage

						if dreg == 0 then
							dbittage = 8
						elseif dreg == 1 then
							dbittage = bittage
						elseif dreg == 2 then
							dbittage = 32
						end

						local opinfo = {}

						if instr[5] then
							opinfo = {
								["s"] = {
									relative=true,
								}
							}
						end

						opinfo.TT = sbittage

						addFormat(
							opinfo,
							destoffset..repeatbit("d", dbittage)..srcoffset..repeatbit("s", sbittage)..makeFoxOpcode(opcode, v2, 0, did, sid, v3[4] or v4[4]),
							f2.." "..dfmt.." "..sfmt,
							instr[4]
						)
					end
				end
			else
				error("weird opcount")
			end
		end
	end
end

for k,v in ipairs(instructions) do
	addFoxFormats(v)
end

return isa