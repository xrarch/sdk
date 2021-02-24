local isa = {}

isa.name = "limn2k"

isa.bits = 32

isa.alignmask = 0x3

local formats = {}

isa.formats = formats

isa.registers = {
	["zero"] = 0,
	["t0"]   = 1,
	["t1"]   = 2,
	["t2"]   = 3,
	["t3"]   = 4,
	["t4"]   = 5,
	["a0"]   = 6,
	["a1"]   = 7,
	["a2"]   = 8,
	["a3"]   = 9,
	["v0"]   = 10,
	["v1"]   = 11,
	["s0"]   = 12,
	["s1"]   = 13,
	["s2"]   = 14,
	["s3"]   = 15,
	["s4"]   = 16,
	["s5"]   = 17,
	["s6"]   = 18,
	["s7"]   = 19,
	["s8"]   = 20,
	["s9"]   = 21,
	["s10"]  = 22,
	["s11"]  = 23,
	["s12"]  = 24,
	["s13"]  = 25,
	["s14"]  = 26,
	["at"]   = 27,
	["tf"]   = 28,
	["sp"]   = 29,
	["lr"]   = 30,
	["pc"]   = 31,

	["k0"]   = 32,
	["k1"]   = 33,
	["k2"]   = 34,
	["k3"]   = 35,
	["rs"]   = 36,
	["ev"]   = 37,
	["epc"]  = 38,
	["ecause"] = 39,
	["ers"]  = 40,
	["timer"] = 41,
	["cpuid"] = 42,
	["badaddr"] = 43,
	["tlbv"] = 44,
	["asid"] = 45,
}

function isa.relocate(sections)
	for k,v in pairs(sections) do
		local data = v.data

		for i,r in ipairs(v.relocations) do
			local operand

			if r.format then
				operand = r.format.operandinfo[r.field]
			end

			local oval = gv32(data, r.offset)

			local nval = r.symbol.bc + r.symbol.section.origin

			if r.long then
				-- nval already contains the proper 32 bit value
			elseif operand.bits == 16 then
				if operand.shift then
					nval = rshift(nval, operand.shift)
				end

				nval = bor(band(oval, 0xFFFF), lshift(nval, 16))
			elseif operand.bits == 24 then
				if operand.shift then
					nval = rshift(nval, operand.shift)
				end

				nval = bor(band(oval, 0xFF), lshift(nval, 8))
			elseif operand.bits == 32 then -- la
				local nval2 = gv32(data, r.offset + 4)

				nval2 = bor(lshift(band(nval, 0xFFFF), 16), band(nval2, 0xFFFF))

				nval = bor(band(nval, 0xFFFF0000), band(oval, 0xFFFF))

				sv32(data, r.offset+4, nval2)
			else
				error("hm")
				return false
			end

			sv32(data, r.offset, nval)
		end
	end

	return true
end

local RELOC_LIMN2K_16 = 2
local RELOC_LIMN2K_24 = 3
local RELOC_LIMN2K_32 = 4
local RELOC_LIMN2K_LA = 5

function isa.reloctype(format, relocation)
	-- returns a relocation type number

	if format.name == "loff" then
		local operand

		if relocation.format then
			operand = relocation.format.operandinfo[relocation.field]
		end

		if relocation.long then
			return RELOC_LIMN2K_32
		elseif operand.bits == 16 then
			return RELOC_LIMN2K_16
		elseif operand.bits == 24 then
			return RELOC_LIMN2K_24
		elseif operand.bits == 32 then
			return RELOC_LIMN2K_LA
		else
			error("weird relocation")
		end
	else
		print("asm: isa-limn2k: I don't support "..format.name)
		return false
	end
end

local function addFormat(operandinfo, encodingstring, formatstring)
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
		error("format bits isn't multiple of 8")
	end

	format.bytes = format.bits/8

	format.encodingstring = encodingstring

	local encoding = {}

	format.encoding = encoding

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

			if q.bits == 32 then
				q.max = 0xFFFFFFFF
			else
				q.max = lshift(lshift(1, q.bits)-1, shift)
			end

			if q.max < 0 then
				q.max = 0xFFFFFFFF
			end
		end
	end

	formats[#formats + 1] = format
end

addFormat(
	{},
	"00000000000000000000000000000000", -- nop
	"nop"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00000001", -- l.b rd, ra, rb
	"mov ^rd byte [^ra + ^rb]"
)
addFormat(
	{},
	"00000000aaaaaaaadddddddd00000001", -- l.b rd, ra, zero
	"mov ^rd byte [^ra]"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00000010", -- l.i rd, ra, rb
	"mov ^rd int [^ra + ^rb]"
)
addFormat(
	{},
	"00000000aaaaaaaadddddddd00000010", -- l.i rd, ra, zero
	"mov ^rd int [^ra]"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00000011", -- l.l rd, ra, rb
	"mov ^rd long [^ra + ^rb]"
)
addFormat(
	{},
	"00000000aaaaaaaadddddddd00000011", -- l.l rd, ra, zero
	"mov ^rd long [^ra]"
)

addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00000100", -- lio.b rd, ra, i
	"mov ^rd byte [^ra + ^ni]"
)

addFormat(
	{
		["i"] = {
			mask=0x1,
			shift=1
		}
	},
	"iiiiiiiiaaaaaaaadddddddd00000101", -- lio.i rd, ra, i
	"mov ^rd int [^ra + ^ni]"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		}
	},
	"iiiiiiiiaaaaaaaadddddddd00000110", -- lio.l rd, ra, i
	"mov ^rd long [^ra + ^ni]"
)

addFormat(
	{},
	"ssssssssaaaaaaaadddddddd00000111", -- s.b rd, ra, rs
	"mov byte [^rd + ^ra] ^rs"
)
addFormat(
	{},
	"ssssssss00000000dddddddd00000111", -- s.b rd, zero, rs
	"mov byte [^rd] ^rs"
)

addFormat(
	{},
	"ssssssssaaaaaaaadddddddd00001000", -- s.i rd, ra, rs
	"mov int [^rd + ^ra] ^rs"
)
addFormat(
	{},
	"ssssssss00000000dddddddd00001000", -- s.i rd, zero, rs
	"mov int [^rd] ^rs"
)

addFormat(
	{},
	"ssssssssaaaaaaaadddddddd00001001", -- s.l rd, ra, rs
	"mov long [^rd + ^ra] ^rs"
)
addFormat(
	{},
	"ssssssss00000000dddddddd00001001", -- s.l rd, zero, rs
	"mov long [^rd] ^rs"
)

addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00001010", -- si.b rd, ra, i
	"mov byte [^rd + ^ra] ^ni"
)
addFormat(
	{},
	"iiiiiiii00000000dddddddd00001010", -- si.b rd, zero, i
	"mov byte [^rd] ^ni"
)

addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00001011", -- si.i rd, ra, i
	"mov int [^rd + ^ra] ^ni"
)
addFormat(
	{},
	"iiiiiiii00000000dddddddd00001011", -- si.i rd, zero, i
	"mov int [^rd] ^ni"
)

addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00001100", -- si.l rd, ra, i
	"mov long [^rd + ^ra] ^ni"
)
addFormat(
	{},
	"iiiiiiii00000000dddddddd00001100", -- si.l rd, zero, i
	"mov long [^rd] ^ni"
)

addFormat(
	{},
	"aaaaaaaaiiiiiiiidddddddd00001101", -- sio.b rd, i, ra
	"mov byte [^rd + ^ni] ^ra"
)

addFormat(
	{
		["i"] = {
			mask=0x1,
			shift=1
		}
	},
	"aaaaaaaaiiiiiiiidddddddd00001110", -- sio.i rd, i, ra
	"mov int [^rd + ^ni] ^ra"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		}
	},
	"aaaaaaaaiiiiiiiidddddddd00001111", -- sio.l rd, i, ra
	"mov long [^rd + ^ni] ^ra"
)

addFormat(
	{},
	"aaaaaaaaiiiiiiiidddddddd00010000", -- siio.b rd, i, a
	"mov byte [^rd + ^ni] ^na"
)

addFormat(
	{
		["i"] = {
			mask=0x1,
			shift=1
		}
	},
	"aaaaaaaaiiiiiiiidddddddd00010001", -- siio.i rd, i, a
	"mov int [^rd + ^ni] ^na"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		}
	},
	"aaaaaaaaiiiiiiiidddddddd00010010", -- siio.l rd, i, a
	"mov long [^rd + ^ni] ^na"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd00010011", -- li rd, i
	"li ^rd ^ni"
)

addFormat(
	{
		["i"] = {
			intswap=true,
		},
		["d"] = {
			repeatbits=1,
			repeatbitsby=8,
		}
	},
	"iiiiiiiiiiiiiiiidddddddd00111101iiiiiiiiiiiiiiiidddddddd00010110", -- lui rd, i; addi.i rd, i
	"la ^rd ^ni"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd00010100", -- si16.i rd, i
	"mov int [^rd] ^ni"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd00010101", -- si16.l rd, i
	"mov long [^rd] ^ni"
)

addFormat(
	{
		["i"] = {
			shift=16,
			mask=0x0000FFFF
		}
	},
	"iiiiiiiiiiiiiiiidddddddd00010110", -- lui rd, i
	"lui ^rd ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00010111", -- swd.b rd, ra, rb
	"mov byte [--^rd + ^ra] ^rb"
)
addFormat(
	{},
	"aaaaaaaa00000000dddddddd00010111", -- swd.b rd, zero, ra
	"mov byte [--^rd] ^ra"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00011000", -- swd.i rd, ra, rb
	"mov int [--^rd + ^ra] ^rb"
)
addFormat(
	{},
	"aaaaaaaa00000000dddddddd00011000", -- swd.i rd, zero, ra
	"mov int [--^rd] ^ra"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00011001", -- swd.l rd, ra, rb
	"mov long [--^rd + ^ra] ^rb"
)
addFormat(
	{},
	"aaaaaaaa00000000dddddddd00011001", -- swd.l rd, zero, ra
	"mov long [--^rd] ^ra"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd00011010", -- swdi.b rd, i
	"mov byte [--^rd] ^ni"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd00011011", -- swdi.i rd, i
	"mov int [--^rd] ^ni"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd00011100", -- swdi.l rd, i
	"mov long [--^rd] ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00011101", -- lwi.b rd, ra, rb
	"mov ^rd byte [^ra++ + ^rb]"
)
addFormat(
	{},
	"00000000aaaaaaaadddddddd00011101", -- lwi.b rd, ra, zero
	"mov ^rd byte [^ra++]"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00011110", -- lwi.i rd, ra, rb
	"mov ^rd int [^ra++ + ^rb]"
)
addFormat(
	{},
	"00000000aaaaaaaadddddddd00011110", -- lwi.i rd, ra, zero
	"mov ^rd int [^ra++]"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00011111", -- lwi.l rd, ra, rb
	"mov ^rd long [^ra++ + ^rb]"
)
addFormat(
	{},
	"00000000aaaaaaaadddddddd00011111", -- lwi.l rd, ra, zero
	"mov ^rd long [^ra++]"
)

addFormat(
	{},
	"ssssssss000000000001110100011001", -- swd.l sp, zero, rs
	"push ^rs"
)

addFormat(
	{},
	"0000000000011101dddddddd00011111", -- lwi.l rd, sp, zero
	"pop ^rd"
)

addFormat(
	{},
	"0000000000000000dddddddd00100000", -- sgpr rd
	"sgpr ^rd"
)

addFormat(
	{},
	"0000000000000000ssssssss00100001", -- lgpr rs
	"lgpr ^rs"
)

addFormat(
	{},
	"00000000ssssssssdddddddd00111011", -- add rd, rs, zero
	"mov ^rd ^rs"
)

-- SHORT CONDITIONAL BRANCHES

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"iiiiiiiibbbbbbbbaaaaaaaa00100100", -- beq ra, rb, i
	"beq ^ra ^rb ^ni"
)
addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjiiiiiiiiaaaaaaaa00100101", -- beqi ra, i, j
	"beq ^ra ^ni ^nj"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"iiiiiiiibbbbbbbbaaaaaaaa00100110", -- bne ra, rb, i
	"bne ^ra ^rb ^ni"
)
addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjiiiiiiiiaaaaaaaa00100111", -- bnei ra, i, j
	"bne ^ra ^ni ^nj"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"iiiiiiiibbbbbbbbaaaaaaaa00101000", -- blt ra, rb, i
	"blt ^ra ^rb ^ni"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"iiiiiiiibbbbbbbbaaaaaaaa00101001", -- blt.s ra, rb, i
	"blt signed ^ra ^rb ^ni"
)

-- CONDITIONAL SETS

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00101010", -- slt rd, ra, rb
	"slt ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00101011", -- slti rd, ra, i
	"slt ^rd ^ra ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00101100", -- slt.s rd, ra, rb
	"slt signed ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00101101", -- slti.s rd, ra, i
	"slt signed ^rd ^ra ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00110010", -- seq rd, ra, rb
	"seq ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00101110", -- seqi rd, ra, i
	"seq ^rd ^ra ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00110011", -- sne rd, ra, rb
	"sne ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00110001", -- snei rd, ra, i
	"sne ^rd ^ra ^ni"
)

addFormat(
	{},
	"aaaaaaaabbbbbbbbdddddddd00101010", -- slt rd, rb, ra
	"sgt ^rd ^ra ^rb"
)

addFormat(
	{},
	"aaaaaaaabbbbbbbbdddddddd00101100", -- slt.s rd, rb, ra
	"sgt signed ^rd ^ra ^rb"
)

addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00101111", -- sgti rd, ra, i
	"sgt ^rd ^ra ^ni"
)

addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00110000", -- sgti.s rd, ra, i
	"sgt signed ^rd ^ra ^ni"
)

-- UNCONDITIONAL BRANCHES

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"iiiiiiiiiiiiiiiiiiiiiiii00110100", -- b i
	"b ^ni"
)

addFormat(
	{},
	"0000000000000000aaaaaaaa00111000", -- jr ra
	"j ^ra"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		}
	},
	"iiiiiiiiiiiiiiiiiiiiiiii00110101", -- j i
	"j ^ni"
)

addFormat(
	{},
	"0000000000000000aaaaaaaa00110111", -- jalr ra
	"jal ^ra"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		}
	},
	"iiiiiiiiiiiiiiiiiiiiiiii00110110", -- jal i
	"jal ^ni"
)

addFormat(
	{},
	"00000000000000000000000000111001", -- brk
	"brk"
)

addFormat(
	{},
	"00000000000000000000000000111010", -- sys
	"sys"
)

addFormat(
	{},
	"00000000000000000001111000111000", -- jr lr
	"ret"
)

-- MATH OPERATIONS

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00111011", -- add rd, ra, rb
	"add ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00111100", -- addi rd, ra, i
	"add ^rd ^ra ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd00111101", -- addi.i rd, i
	"add ^rd ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd00111110", -- sub rd, ra, rb
	"sub ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd00111111", -- subi rd, ra, i
	"sub ^rd ^ra ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd01000000", -- subi.i rd, i
	"sub ^rd ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01000001", -- mul rd, ra, rb
	"mul ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01000010", -- muli rd, ra, i
	"mul ^rd ^ra ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd01000011", -- muli.i rd, i
	"mul ^rd ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01000100", -- div rd, ra, rb
	"div ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01000101", -- divi rd, ra, i
	"div ^rd ^ra ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd01000110", -- divi.i rd, i
	"div ^rd ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01000111", -- mod rd, ra, rb
	"mod ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01001000", -- modi rd, ra, i
	"mod ^rd ^ra ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd01001001", -- modi.i rd, i
	"mod ^rd ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01000111", -- mod rd, ra, rb
	"mod ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01001000", -- modi rd, ra, i
	"mod ^rd ^ra ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd01001001", -- modi.i rd, i
	"mod ^rd ^ni"
)

-- LOGICAL OPERATIONS

addFormat(
	{},
	"00000000ssssssssdddddddd01001100", -- not rd, rs
	"not ^rd ^rs"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01001101", -- or rd, ra, rb
	"or ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01001110", -- ori rd, ra, i
	"or ^rd ^ra ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd01001111", -- ori.i rd, i
	"or ^rd ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01010000", -- xor rd, ra, rb
	"xor ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01010001", -- xori rd, ra, i
	"xor ^rd ^ra ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd01010010", -- xori.i rd, i
	"xor ^rd ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01010011", -- and rd, ra, rb
	"and ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01010100", -- andi rd, ra, i
	"and ^rd ^ra ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiidddddddd01010101", -- andi.i rd, i
	"and ^rd ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01010110", -- lsh rd, ra, rb
	"lsh ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01010111", -- lshi rd, ra, i
	"lsh ^rd ^ra ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01011000", -- rsh rd, ra, rb
	"rsh ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01011001", -- rshi rd, ra, i
	"rsh ^rd ^ra ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01011010", -- bset rd, ra, rb
	"bset ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01011011", -- bseti rd, ra, i
	"bset ^rd ^ra ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01011100", -- bclr rd, ra, rb
	"bclr ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01011101", -- bclri rd, ra, i
	"bclr ^rd ^ra ^ni"
)

addFormat(
	{},
	"bbbbbbbbaaaaaaaadddddddd01011110", -- bget rd, ra, rb
	"bget ^rd ^ra ^rb"
)
addFormat(
	{},
	"iiiiiiiiaaaaaaaadddddddd01011111", -- bgeti rd, ra, i
	"bget ^rd ^ra ^ni"
)

addFormat(
	{},
	"00000000ssssssssdddddddd01100000", -- bswap rd, rs
	"bswap ^rd ^rs"
)

-- PRIVILEGED STUFF

addFormat(
	{},
	"00000000000000000000000001100010", -- rfe
	"rfe"
)

addFormat(
	{},
	"00000000000000000000000001100011", -- hlt
	"hlt"
)

addFormat(
	{},
	"00000000ppppppppvvvvvvvv01100100", -- wtlb
	"wtlb ^rv ^rp"
)

addFormat(
	{},
	"00000000vvvvvvvvaaaaaaaa01100101", -- ftlb
	"ftlb ^ra ^rv"
)

-- FAR CONDITIONAL BRANCHES

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"iiiiiiiiiiiiiiiiiiiiiiii01100111", -- bt i
	"bt ^ni"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"iiiiiiiiiiiiiiiiiiiiiiii01101000", -- bf i
	"bf ^ni"
)

return isa