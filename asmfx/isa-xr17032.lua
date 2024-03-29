local isa = {}

isa.name = "xr17032"

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
	["t5"]   = 6,
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

	["s18"]  = 29,
	["tp"]   = 29,
	
	["sp"]   = 30,
	["lr"]   = 31,
}

isa.controlregisters = {
	["rs"]         = 0,
	["whami"]      = 1,
	["eb"]         = 5,
	["epc"]        = 6,
	["ebadaddr"]   = 7,
	["tbmissaddr"] = 9,
	["tbpc"]       = 10,

	["scratch0"]   = 11,
	["scratch1"]   = 12,
	["scratch2"]   = 13,
	["scratch3"]   = 14,
	["scratch4"]   = 15,

	["itbpte"]     = 16,
	["itbtag"]     = 17,
	["itbindex"]   = 18,
	["itbctrl"]    = 19,
	["icachectrl"] = 20,
	["itbaddr"]    = 21,

	["dtbpte"]     = 24,
	["dtbtag"]     = 25,
	["dtbindex"]   = 26,
	["dtbctrl"]    = 27,
	["dcachectrl"] = 28,
	["dtbaddr"]    = 29,
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
			elseif operand.bits == 29 then -- jal, j
				if operand.shift then
					nval = rshift(nval, operand.shift)
				end

				nval = bor(band(oval, 0x7), lshift(nval, 3))
			elseif operand.bits == 32 then -- la
				local nval2 = gv32(data, r.offset + 4)

				nval2 = bor(lshift(band(nval, 0xFFFF), 16), band(nval2, 0xFFFF))

				nval = bor(band(nval, 0xFFFF0000), band(oval, 0xFFFF))

				sv32(data, r.offset+4, nval2)
			elseif operand.bits == 31 then
				local old2 = gv32(data, r.offset + 4)
				local new2 = bor(lshift(rshift(band(nval, 0xFFFF), 1), 16), band(old2, 0xFFFF))

				new = bor(band(nval, 0xFFFF0000), band(oval, 0xFFFF))

				sv32(data, r.offset + 4, new2)
			elseif operand.bits == 30 then
				local old2 = gv32(data, r.offset + 4)
				local new2 = bor(lshift(rshift(band(nval, 0xFFFF), 2), 16), band(old2, 0xFFFF))

				new = bor(band(nval, 0xFFFF0000), band(oval, 0xFFFF))

				sv32(data, r.offset + 4, new2)
			else
				error("hm")
				return false
			end

			sv32(data, r.offset, nval)
		end
	end

	return true
end

local RELOC_XR17032_LONG = 1
local RELOC_XR17032_ABSJ = 2
local RELOC_XR17032_LA   = 3

local RELOC_XR17032_FAR_INT  = 4
local RELOC_XR17032_FAR_LONG = 5

function isa.reloctype(format, relocation)
	-- returns a relocation type number

	if (format.name == "loff") or (format.name == "xloff") then
		local operand

		if relocation.format then
			operand = relocation.format.operandinfo[relocation.field]
		end

		if relocation.long then
			return RELOC_XR17032_LONG
		elseif operand.bits == 29 then
			return RELOC_XR17032_ABSJ
		elseif operand.bits == 32 then
			return RELOC_XR17032_LA
		elseif operand.bits == 31 then
			return RELOC_XR17032_FAR_INT
		elseif operand.bits == 30 then
			return RELOC_XR17032_FAR_LONG
		else
			error("weird relocation")
		end
	else
		print("asm: isa-xr17032: I don't support "..format.name)
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

-- PSEUDOINSTRUCTIONS

addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjjjjjj00000111101", -- beq zero, j
	"b ^nj"
)

addFormat(
	{},
	"00000000000000001111100000111000", -- jalr zero, lr, 0
	"ret"
)

addFormat(
	{},
	"0000000000000000aaaaa00000111000", -- jalr zero, ra, 0
	"jr ^ra"
)

addFormat(
	{},
	"0111000000000000sssssddddd111001", -- add rd, rs, zero LSH 0
	"mov ^rd ^rs"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiii00000ddddd111100", -- addi rd, zero, i
	"li ^rd ^ni"
)

addFormat(
	{
		["i"] = {
			intswap=true,
		},
		["d"] = {
			repeatbits=2,
			repeatbitsby=5,
		}
	},
	"iiiiiiiiiiiiiiiidddddddddd001100iiiiiiiiiiiiiiii00000ddddd000100", -- lui rd, zero, i; ori rd, rd, i
	"la ^rd ^ni"
)

addFormat(
	{},
	"00000000000000000000000000111100", -- addi zero, zero, 0
	"nop"
)

addFormat(
	{},
	"011100sssssbbbbb00000ddddd111001", -- add rd, zero, rb LSH s
	"lshi ^rd ^rb ^ns"
)
addFormat(
	{},
	"011101sssssbbbbb00000ddddd111001", -- add rd, zero, rb RSH s
	"rshi ^rd ^rb ^ns"
)
addFormat(
	{},
	"011110sssssbbbbb00000ddddd111001", -- add rd, zero, rb ASH s
	"ashi ^rd ^rb ^ns"
)
addFormat(
	{},
	"011111sssssbbbbb00000ddddd111001", -- add rd, zero, rb ROR s
	"rori ^rd ^rb ^ns"
)

addFormat(
	{
		["d"] = {
			repeatbits=2,
			repeatbitsby=5,
		}
	},
	"0000000000000001dddddddddd10110000100000000bbbbbaaaaaddddd111001", -- xor rd, ra, rb; slti rd, rd, 1
	"seq ^rd ^ra ^rb"
)
addFormat(
	{
		["d"] = {
			repeatbits=2,
			repeatbitsby=5,
		}
	},
	"0000000000000001dddddddddd101100iiiiiiiiiiiiiiiiaaaaaddddd010100", -- xori rd, ra, i; slti rd, rd, 1
	"seqi ^rd ^ra ^ni"
)


addFormat(
	{
		["d"] = {
			repeatbits=2,
			repeatbitsby=5,
		}
	},
	"01010000000ddddd00000ddddd11100100100000000bbbbbaaaaaddddd111001", -- xor rd, ra, rb; slt rd, zero, rd
	"sne ^rd ^ra ^rb"
)
addFormat(
	{
		["d"] = {
			repeatbits=2,
			repeatbitsby=5,
		}
	},
	"01010000000ddddd00000ddddd111001iiiiiiiiiiiiiiiiaaaaaddddd010100", -- xori rd, ra, i; slt rd, zero, rd
	"snei ^rd ^ra ^ni"
)

-- REAL INSTRUCTIONS

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		}
	},
	"iiiiiiiiiiiiiiiiiiiiiiiiiiiii111", -- jal i
	"jal ^ni"
)
addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		}
	},
	"iiiiiiiiiiiiiiiiiiiiiiiiiiiii110", -- j i
	"j ^ni"
)

addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjjjjjjaaaaa111101", -- beq ra, j
	"beq ^ra ^nj"
)
addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjjjjjjaaaaa110101", -- bne ra, j
	"bne ^ra ^nj"
)
addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjjjjjjaaaaa101101", -- blt ra, j
	"blt ^ra ^nj"
)
addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjjjjjjaaaaa100101", -- bgt ra, j
	"bgt ^ra ^nj"
)
addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjjjjjjaaaaa011101", -- ble ra, j
	"ble ^ra ^nj"
)
addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjjjjjjaaaaa010101", -- bge ra, j
	"bge ^ra ^nj"
)
addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjjjjjjaaaaa001101", -- bpe ra, j
	"bpe ^ra ^nj"
)
addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjjjjjjaaaaa000101", -- bpo ra, j
	"bpo ^ra ^nj"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiiisssssddddd111100", -- addi rd, rs, i
	"addi ^rd ^rs ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiisssssddddd110100", -- subi rd, rs, i
	"subi ^rd ^rs ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiisssssddddd101100", -- slti rd, rs, i
	"slti ^rd ^rs ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiisssssddddd100100", -- slti signed rd, rs, i
	"slti signed ^rd ^rs ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiisssssddddd011100", -- andi rd, rs, i
	"andi ^rd ^rs ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiisssssddddd010100", -- xori rd, rs, i
	"xori ^rd ^rs ^ni"
)
addFormat(
	{},
	"iiiiiiiiiiiiiiiisssssddddd001100", -- ori rd, rs, i
	"ori ^rd ^rs ^ni"
)
addFormat(
	{
		["i"] = {
			shift=16,
			mask=0x0000FFFF
		}
	},
	"iiiiiiiiiiiiiiiisssssddddd000100", -- lui rd, rs, i
	"lui ^rd ^rs ^ni"
)

addFormat(
	{
		["j"] = {
			mask=0x3,
			shift=2,
			relative=true
		}
	},
	"jjjjjjjjjjjjjjjjbbbbbaaaaa111000", -- jalr ra, rb, j
	"jalr ^ra ^rb ^nj"
)

addFormat(
	{},
	"011100sssssbbbbbaaaaaddddd111001", -- add rd, ra, rb LSH s
	"add ^rd ^ra ^rb LSH ^ns"
)
addFormat(
	{},
	"011101sssssbbbbbaaaaaddddd111001", -- add rd, ra, rb RSH s
	"add ^rd ^ra ^rb RSH ^ns"
)
addFormat(
	{},
	"011110sssssbbbbbaaaaaddddd111001", -- add rd, ra, rb ASH s
	"add ^rd ^ra ^rb ASH ^ns"
)
addFormat(
	{},
	"011111sssssbbbbbaaaaaddddd111001", -- add rd, ra, rb ROR s
	"add ^rd ^ra ^rb ROR ^ns"
)
addFormat(
	{},
	"01110000000bbbbbaaaaaddddd111001", -- add rd, ra, rb LSH 0
	"add ^rd ^ra ^rb"
)

addFormat(
	{},
	"011000sssssbbbbbaaaaaddddd111001", -- sub rd, ra, rb LSH s
	"sub ^rd ^ra ^rb LSH ^ns"
)
addFormat(
	{},
	"011001sssssbbbbbaaaaaddddd111001", -- sub rd, ra, rb RSH s
	"sub ^rd ^ra ^rb RSH ^ns"
)
addFormat(
	{},
	"011010sssssbbbbbaaaaaddddd111001", -- sub rd, ra, rb ASH s
	"sub ^rd ^ra ^rb ASH ^ns"
)
addFormat(
	{},
	"011011sssssbbbbbaaaaaddddd111001", -- sub rd, ra, rb ROR s
	"sub ^rd ^ra ^rb ROR ^ns"
)
addFormat(
	{},
	"01100000000bbbbbaaaaaddddd111001", -- sub rd, ra, rb LSH 0
	"sub ^rd ^ra ^rb"
)

addFormat(
	{},
	"010100sssssbbbbbaaaaaddddd111001", -- slt rd, ra, rb LSH s
	"slt ^rd ^ra ^rb LSH ^ns"
)
addFormat(
	{},
	"010101sssssbbbbbaaaaaddddd111001", -- slt rd, ra, rb RSH s
	"slt ^rd ^ra ^rb RSH ^ns"
)
addFormat(
	{},
	"010110sssssbbbbbaaaaaddddd111001", -- slt rd, ra, rb ASH s
	"slt ^rd ^ra ^rb ASH ^ns"
)
addFormat(
	{},
	"010111sssssbbbbbaaaaaddddd111001", -- slt rd, ra, rb ROR s
	"slt ^rd ^ra ^rb ROR ^ns"
)
addFormat(
	{},
	"01010000000bbbbbaaaaaddddd111001", -- slt rd, ra, rb LSH 0
	"slt ^rd ^ra ^rb"
)

addFormat(
	{},
	"010000sssssbbbbbaaaaaddddd111001", -- slt signed rd, ra, rb LSH s
	"slt signed ^rd ^ra ^rb LSH ^ns"
)
addFormat(
	{},
	"010001sssssbbbbbaaaaaddddd111001", -- slt signed rd, ra, rb RSH s
	"slt signed ^rd ^ra ^rb RSH ^ns"
)
addFormat(
	{},
	"010010sssssbbbbbaaaaaddddd111001", -- slt signed rd, ra, rb ASH s
	"slt signed ^rd ^ra ^rb ASH ^ns"
)
addFormat(
	{},
	"010011sssssbbbbbaaaaaddddd111001", -- slt signed rd, ra, rb ROR s
	"slt signed ^rd ^ra ^rb ROR ^ns"
)
addFormat(
	{},
	"01000000000bbbbbaaaaaddddd111001", -- slt signed rd, ra, rb LSH 0
	"slt signed ^rd ^ra ^rb"
)

addFormat(
	{},
	"001100sssssbbbbbaaaaaddddd111001", -- and rd, ra, rb LSH s
	"and ^rd ^ra ^rb LSH ^ns"
)
addFormat(
	{},
	"001101sssssbbbbbaaaaaddddd111001", -- and rd, ra, rb RSH s
	"and ^rd ^ra ^rb RSH ^ns"
)
addFormat(
	{},
	"001110sssssbbbbbaaaaaddddd111001", -- and rd, ra, rb ASH s
	"and ^rd ^ra ^rb ASH ^ns"
)
addFormat(
	{},
	"001111sssssbbbbbaaaaaddddd111001", -- and rd, ra, rb ROR s
	"and ^rd ^ra ^rb ROR ^ns"
)
addFormat(
	{},
	"00110000000bbbbbaaaaaddddd111001", -- and rd, ra, rb LSH 0
	"and ^rd ^ra ^rb"
)

addFormat(
	{},
	"001000sssssbbbbbaaaaaddddd111001", -- xor rd, ra, rb LSH s
	"xor ^rd ^ra ^rb LSH ^ns"
)
addFormat(
	{},
	"001001sssssbbbbbaaaaaddddd111001", -- xor rd, ra, rb RSH s
	"xor ^rd ^ra ^rb RSH ^ns"
)
addFormat(
	{},
	"001010sssssbbbbbaaaaaddddd111001", -- xor rd, ra, rb ASH s
	"xor ^rd ^ra ^rb ASH ^ns"
)
addFormat(
	{},
	"001011sssssbbbbbaaaaaddddd111001", -- xor rd, ra, rb ROR s
	"xor ^rd ^ra ^rb ROR ^ns"
)
addFormat(
	{},
	"00100000000bbbbbaaaaaddddd111001", -- xor rd, ra, rb LSH 0
	"xor ^rd ^ra ^rb"
)

addFormat(
	{},
	"000100sssssbbbbbaaaaaddddd111001", -- or rd, ra, rb LSH s
	"or ^rd ^ra ^rb LSH ^ns"
)
addFormat(
	{},
	"000101sssssbbbbbaaaaaddddd111001", -- or rd, ra, rb RSH s
	"or ^rd ^ra ^rb RSH ^ns"
)
addFormat(
	{},
	"000110sssssbbbbbaaaaaddddd111001", -- or rd, ra, rb ASH s
	"or ^rd ^ra ^rb ASH ^ns"
)
addFormat(
	{},
	"000111sssssbbbbbaaaaaddddd111001", -- or rd, ra, rb ROR s
	"or ^rd ^ra ^rb ROR ^ns"
)
addFormat(
	{},
	"00010000000bbbbbaaaaaddddd111001", -- or rd, ra, rb LSH 0
	"or ^rd ^ra ^rb"
)

addFormat(
	{},
	"000000sssssbbbbbaaaaaddddd111001", -- nor rd, ra, rb LSH s
	"nor ^rd ^ra ^rb LSH ^ns"
)
addFormat(
	{},
	"000001sssssbbbbbaaaaaddddd111001", -- nor rd, ra, rb RSH s
	"nor ^rd ^ra ^rb RSH ^ns"
)
addFormat(
	{},
	"000010sssssbbbbbaaaaaddddd111001", -- nor rd, ra, rb ASH s
	"nor ^rd ^ra ^rb ASH ^ns"
)
addFormat(
	{},
	"000011sssssbbbbbaaaaaddddd111001", -- nor rd, ra, rb ROR s
	"nor ^rd ^ra ^rb ROR ^ns"
)
addFormat(
	{},
	"00000000000bbbbbaaaaaddddd111001", -- nor rd, ra, rb LSH 0
	"nor ^rd ^ra ^rb"
)

addFormat(
	{},
	"111100sssssbbbbbaaaaaddddd111001", -- mov rd, byte [ra + rb LSH s]
	"mov ^rd byte [^ra + ^rb LSH ^ns]"
)
addFormat(
	{},
	"111101sssssbbbbbaaaaaddddd111001", -- mov rd, byte [ra + rb RSH s]
	"mov ^rd byte [^ra + ^rb RSH ^ns]"
)
addFormat(
	{},
	"111110sssssbbbbbaaaaaddddd111001", -- mov rd, byte [ra + rb ASH s]
	"mov ^rd byte [^ra + ^rb ASH ^ns]"
)
addFormat(
	{},
	"111111sssssbbbbbaaaaaddddd111001", -- mov rd, byte [ra + rb ROR s]
	"mov ^rd byte [^ra + ^rb ROR ^ns]"
)
addFormat(
	{},
	"11110000000bbbbbaaaaaddddd111001", -- mov rd, byte [ra + rb LSH 0]
	"mov ^rd byte [^ra + ^rb]"
)

addFormat(
	{},
	"111000sssssbbbbbaaaaaddddd111001", -- mov rd, int [ra + rb LSH s]
	"mov ^rd int [^ra + ^rb LSH ^ns]"
)
addFormat(
	{},
	"111001sssssbbbbbaaaaaddddd111001", -- mov rd, int [ra + rb RSH s]
	"mov ^rd int [^ra + ^rb RSH ^ns]"
)
addFormat(
	{},
	"111010sssssbbbbbaaaaaddddd111001", -- mov rd, int [ra + rb ASH s]
	"mov ^rd int [^ra + ^rb ASH ^ns]"
)
addFormat(
	{},
	"111011sssssbbbbbaaaaaddddd111001", -- mov rd, int [ra + rb ROR s]
	"mov ^rd int [^ra + ^rb ROR ^ns]"
)
addFormat(
	{},
	"11100000000bbbbbaaaaaddddd111001", -- mov rd, int [ra + rb LSH 0]
	"mov ^rd int [^ra + ^rb]"
)

addFormat(
	{},
	"110100sssssbbbbbaaaaaddddd111001", -- mov rd, long [ra + rb LSH s]
	"mov ^rd long [^ra + ^rb LSH ^ns]"
)
addFormat(
	{},
	"110101sssssbbbbbaaaaaddddd111001", -- mov rd, long [ra + rb RSH s]
	"mov ^rd long [^ra + ^rb RSH ^ns]"
)
addFormat(
	{},
	"110110sssssbbbbbaaaaaddddd111001", -- mov rd, long [ra + rb ASH s]
	"mov ^rd long [^ra + ^rb ASH ^ns]"
)
addFormat(
	{},
	"110111sssssbbbbbaaaaaddddd111001", -- mov rd, long [ra + rb ROR s]
	"mov ^rd long [^ra + ^rb ROR ^ns]"
)
addFormat(
	{},
	"11010000000bbbbbaaaaaddddd111001", -- mov rd, long [ra + rb LSH 0]
	"mov ^rd long [^ra + ^rb]"
)

addFormat(
	{},
	"101100sssssbbbbbaaaaaddddd111001", -- mov byte [ra + rb LSH s], rd
	"mov byte [^ra + ^rb LSH ^ns] ^rd"
)
addFormat(
	{},
	"101101sssssbbbbbaaaaaddddd111001", -- mov byte [ra + rb RSH s], rd
	"mov byte [^ra + ^rb RSH ^ns] ^rd"
)
addFormat(
	{},
	"101110sssssbbbbbaaaaaddddd111001", -- mov byte [ra + rb ASH s], rd
	"mov byte [^ra + ^rb ASH ^ns] ^rd"
)
addFormat(
	{},
	"101111sssssbbbbbaaaaaddddd111001", -- mov byte [ra + rb ROR s], rd
	"mov byte [^ra + ^rb ROR ^ns] ^rd"
)
addFormat(
	{},
	"10110000000bbbbbaaaaaddddd111001", -- mov byte [ra + rb LSH 0], rd
	"mov byte [^ra + ^rb] ^rd"
)

addFormat(
	{},
	"101000sssssbbbbbaaaaaddddd111001", -- mov int [ra + rb LSH s], rd
	"mov int [^ra + ^rb LSH ^ns] ^rd"
)
addFormat(
	{},
	"101001sssssbbbbbaaaaaddddd111001", -- mov int [ra + rb RSH s], rd
	"mov int [^ra + ^rb RSH ^ns] ^rd"
)
addFormat(
	{},
	"101010sssssbbbbbaaaaaddddd111001", -- mov int [ra + rb ASH s], rd
	"mov int [^ra + ^rb ASH ^ns] ^rd"
)
addFormat(
	{},
	"101011sssssbbbbbaaaaaddddd111001", -- mov int [ra + rb ROR s], rd
	"mov int [^ra + ^rb ROR ^ns] ^rd"
)
addFormat(
	{},
	"10100000000bbbbbaaaaaddddd111001", -- mov int [ra + rb LSH 0], rd
	"mov int [^ra + ^rb] ^rd"
)

addFormat(
	{},
	"100100sssssbbbbbaaaaaddddd111001", -- mov long [ra + rb LSH s], rd
	"mov long [^ra + ^rb LSH ^ns] ^rd"
)
addFormat(
	{},
	"100101sssssbbbbbaaaaaddddd111001", -- mov long [ra + rb RSH s], rd
	"mov long [^ra + ^rb RSH ^ns] ^rd"
)
addFormat(
	{},
	"100110sssssbbbbbaaaaaddddd111001", -- mov long [ra + rb ASH s], rd
	"mov long [^ra + ^rb ASH ^ns] ^rd"
)
addFormat(
	{},
	"100111sssssbbbbbaaaaaddddd111001", -- mov long [ra + rb ROR s], rd
	"mov long [^ra + ^rb ROR ^ns] ^rd"
)
addFormat(
	{},
	"10010000000bbbbbaaaaaddddd111001", -- mov long [ra + rb LSH 0], rd
	"mov long [^ra + ^rb] ^rd"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiiisssssddddd111011", -- mov rd, byte [rs + i]
	"mov ^rd byte [^rs + ^ni]"
)
addFormat(
	{},
	"0000000000000000sssssddddd111011", -- mov rd, byte [rs + 0]
	"mov ^rd byte [^rs]"
)

addFormat(
	{
		["i"] = {
			mask=0x1,
			shift=1
		}
	},
	"iiiiiiiiiiiiiiiisssssddddd110011", -- mov rd, int [rs + i]
	"mov ^rd int [^rs + ^ni]"
)
addFormat(
	{},
	"0000000000000000sssssddddd110011", -- mov rd, int [rs + 0]
	"mov ^rd int [^rs]"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		}
	},
	"iiiiiiiiiiiiiiiisssssddddd101011", -- mov rd, long [rs + i]
	"mov ^rd long [^rs + ^ni]"
)
addFormat(
	{},
	"0000000000000000sssssddddd101011", -- mov rd, long [rs + 0]
	"mov ^rd long [^rs]"
)

addFormat(
	{},
	"iiiiiiiiiiiiiiiibbbbbaaaaa111010", -- mov byte [ra + i], rb
	"mov byte [^ra + ^ni] ^rb"
)
addFormat(
	{},
	"0000000000000000bbbbbaaaaa111010", -- mov byte [ra + 0], rb
	"mov byte [^ra] ^rb"
)

addFormat(
	{
		["i"] = {
			mask=0x1,
			shift=1
		}
	},
	"iiiiiiiiiiiiiiiibbbbbaaaaa110010", -- mov int [ra + i], rb
	"mov int [^ra + ^ni] ^rb"
)
addFormat(
	{},
	"0000000000000000bbbbbaaaaa110010", -- mov int [ra + 0], rb
	"mov int [^ra] ^rb"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		}
	},
	"iiiiiiiiiiiiiiiibbbbbaaaaa101010", -- mov long [ra + i], rb
	"mov long [^ra + ^ni] ^rb"
)
addFormat(
	{},
	"0000000000000000bbbbbaaaaa101010", -- mov long [ra + 0], rb
	"mov long [^ra] ^rb"
)

addFormat(
	{
		["o"] = {
			signmask=0xFFFFFFF0,
		},
	},
	"iiiiiiiiiiiiiiiioooooaaaaa011010", -- mov byte [ra + i], o
	"mov byte [^ra + ^ni] ^no"
)
addFormat(
	{
		["o"] = {
			signmask=0xFFFFFFF0,
		},
	},
	"0000000000000000oooooaaaaa011010", -- mov byte [ra + 0], o
	"mov byte [^ra] ^no"
)

addFormat(
	{
		["i"] = {
			mask=0x1,
			shift=1
		},
		["o"] = {
			signmask=0xFFFFFFF0,
		},
	},
	"iiiiiiiiiiiiiiiioooooaaaaa010010", -- mov int [ra + i], o
	"mov int [^ra + ^ni] ^no"
)
addFormat(
	{
		["o"] = {
			signmask=0xFFFFFFF0,
		},
	},
	"0000000000000000oooooaaaaa010010", -- mov int [ra + 0], o
	"mov int [^ra] ^no"
)

addFormat(
	{
		["i"] = {
			mask=0x3,
			shift=2
		},
		["o"] = {
			signmask=0xFFFFFFF0,
		},
	},
	"iiiiiiiiiiiiiiiioooooaaaaa001010", -- mov long [ra + i], o
	"mov long [^ra + ^ni] ^no"
)
addFormat(
	{
		["o"] = {
			signmask=0xFFFFFFF0,
		},
	},
	"0000000000000000oooooaaaaa001010", -- mov long [ra + 0], o
	"mov long [^ra] ^no"
)

addFormat(
	{},
	"10000000000bbbbbaaaaaddddd111001", -- lsh rd, rb, ra
	"lsh ^rd ^rb ^ra"
)
addFormat(
	{},
	"10000100000bbbbbaaaaaddddd111001", -- rsh rd, rb, ra
	"rsh ^rd ^rb ^ra"
)
addFormat(
	{},
	"10001000000bbbbbaaaaaddddd111001", -- ash rd, rb, ra
	"ash ^rd ^rb ^ra"
)
addFormat(
	{},
	"10001100000bbbbbaaaaaddddd111001", -- ror rd, rb, ra
	"ror ^rd ^rb ^ra"
)

addFormat(
	{},
	"11110000000bbbbbaaaaaddddd110001", -- mul rd, ra, rb
	"mul ^rd ^ra ^rb"
)

addFormat(
	{},
	"11010000000bbbbbaaaaaddddd110001", -- div rd, ra, rb
	"div ^rd ^ra ^rb"
)

addFormat(
	{},
	"11000000000bbbbbaaaaaddddd110001", -- div signed rd, ra, rb
	"div signed ^rd ^ra ^rb"
)

addFormat(
	{},
	"10110000000bbbbbaaaaaddddd110001", -- mod rd, ra, rb
	"mod ^rd ^ra ^rb"
)

addFormat(
	{},
	"1001000000000000aaaaaddddd110001", -- mov rd, locked [ra]
	"mov ^rd locked [^ra]"
)

addFormat(
	{},
	"10000000000bbbbbaaaaaddddd110001", -- sc rd, ra, rb
	"sc ^rd [^ra] ^rb"
)

addFormat(
	{},
	"00110000000000000000000000110001", -- mb
	"mb"
)

addFormat(
	{},
	"00100000000000000000000000110001", -- wmb
	"wmb"
)

addFormat(
	{},
	"00010000000000000000000000110001", -- brk
	"brk" 
)

addFormat(
	{},
	"00000000000000000000000000110001", -- sys
	"sys"
)

addFormat(
	{},
	"11110000000sssss00000ddddd101001", -- mfcr rd, cs
	"mfcr ^rd ^cs"
)

addFormat(
	{},
	"11100000000sssssaaaaa00000101001", -- mtcr cs, ra
	"mtcr ^cs ^ra"
)

addFormat(
	{},
	"11000000000000000000000000101001", -- hlt
	"hlt"
)

addFormat(
	{},
	"10110000000000000000000000101001", -- rfe
	"rfe"
)

-- more pseudoinstructions

addFormat(
	{
		["i"] = {
			intswap=true,
		},
		["d"] = {
			repeatbits=2,
			repeatbitsby=5,
		}
	},
	"iiiiiiiiiiiiiiiidddddddddd111011iiiiiiiiiiiiiiii00000ddddd000100", -- lui rd, zero, i; mov rd, byte [rd + i]
	"mov ^rd byte [^ni]"
)

addFormat(
	{
		["i"] = {
			intswap=true,
			intshift=1,
		},
		["d"] = {
			repeatbits=2,
			repeatbitsby=5,
		}
	},
	"0iiiiiiiiiiiiiiidddddddddd110011iiiiiiiiiiiiiiii00000ddddd000100", -- lui rd, zero, i; mov rd, int [rd + i]
	"mov ^rd int [^ni]"
)

addFormat(
	{
		["i"] = {
			intswap=true,
			intshift=2,
		},
		["d"] = {
			repeatbits=2,
			repeatbitsby=5,
		}
	},
	"00iiiiiiiiiiiiiidddddddddd101011iiiiiiiiiiiiiiii00000ddddd000100", -- lui rd, zero, i; mov rd, long [rd + i]
	"mov ^rd long [^ni]"
)



addFormat(
	{
		["i"] = {
			intswap=true,
		},
		["b"] = {
			repeatbits=1,
			repeatbitsby=5,
		}
	},
	"iiiiiiiiiiiiiiiiaaaaabbbbb111010iiiiiiiiiiiiiiii00000bbbbb000100", -- lui rb, zero, i; mov byte [rb + i], ra
	"mov byte [^ni] ^ra tmp=^rb"
)

addFormat(
	{
		["i"] = {
			intswap=true,
			intshift=1,
		},
		["b"] = {
			repeatbits=1,
			repeatbitsby=5,
		}
	},
	"0iiiiiiiiiiiiiiiaaaaabbbbb110010iiiiiiiiiiiiiiii00000bbbbb000100", -- lui rb, zero, i; mov int [rb + i], ra
	"mov int [^ni] ^ra tmp=^rb"
)

addFormat(
	{
		["i"] = {
			intswap=true,
			intshift=2,
		},
		["b"] = {
			repeatbits=1,
			repeatbitsby=5,
		}
	},
	"00iiiiiiiiiiiiiiaaaaabbbbb101010iiiiiiiiiiiiiiii00000bbbbb000100", -- lui rb, zero, i; mov int [rb + i], ra
	"mov long [^ni] ^ra tmp=^rb"
)

addFormat(
	{
		["i"] = {
			intswap=true,
		},
		["b"] = {
			repeatbits=1,
			repeatbitsby=5,
		},
		["s"] = {
			signmask=0xFFFFFFF0,
		},
	},
	"iiiiiiiiiiiiiiiisssssbbbbb011010iiiiiiiiiiiiiiii00000bbbbb000100", -- lui rb, zero, i; mov byte [rb + i], ns
	"mov byte [^ni] ^ns tmp=^rb"
)

addFormat(
	{
		["i"] = {
			intswap=true,
			intshift=1,
		},
		["b"] = {
			repeatbits=1,
			repeatbitsby=5,
		},
		["s"] = {
			signmask=0xFFFFFFF0,
		},
	},
	"0iiiiiiiiiiiiiiisssssbbbbb010010iiiiiiiiiiiiiiii00000bbbbb000100", -- lui rb, zero, i; mov int [rb + i], ns
	"mov int [^ni] ^ns tmp=^rb"
)

addFormat(
	{
		["i"] = {
			intswap=true,
			intshift=2,
		},
		["b"] = {
			repeatbits=1,
			repeatbitsby=5,
		},
		["s"] = {
			signmask=0xFFFFFFF0,
		},
	},
	"00iiiiiiiiiiiiiisssssbbbbb001010iiiiiiiiiiiiiiii00000bbbbb000100", -- lui rb, zero, i; mov int [rb + i], ns
	"mov long [^ni] ^ns tmp=^rb"
)

return isa