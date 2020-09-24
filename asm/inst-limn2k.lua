--[[

	{bytes, opcode, {operands (sizes in bytes)}, modifier func, divisor}

]]

local inst = {
	["nop"]   = {4, 0x0,  {}},

	["l.b"]   = {4, 0x1,  {1, 1, 1}},
	["l.i"]   = {4, 0x2,  {1, 1, 1}},
	["l.l"]   = {4, 0x3,  {1, 1, 1}},

	["lio.b"] = {4, 0x4,  {1, 1, 1}},
	["lio.i"] = {4, 0x5,  {1, 1, 1}, function (n,o)
		if n == 3 then o = o / 2 end
		return o
	end},
	["lio.l"] = {4, 0x6,  {1, 1, 1}, function (n,o)
		if n == 3 then o = o / 4 end
		return o
	end},

	["s.b"]   = {4, 0x7,  {1, 1, 1}},
	["s.i"]   = {4, 0x8,  {1, 1, 1}},
	["s.l"]   = {4, 0x9,  {1, 1, 1}},

	["si.b"]  = {4, 0xA,  {1, 1, 1}},
	["si.i"]  = {4, 0xB,  {1, 1, 1}},
	["si.l"]  = {4, 0xC,  {1, 1, 1}},

	["sio.b"] = {4, 0xD,  {1, 1, 1}},
	["sio.i"] = {4, 0xE,  {1, 1, 1}, function (n,o)
		if n == 2 then o = o / 2 end
		return o
	end, 2},
	["sio.l"] = {4, 0xF,  {1, 1, 1}, function (n,o)
		if n == 2 then o = o / 4 end
		return o
	end, 4},

	["siio.b"] = {4, 0x10, {1, 1, 1}},
	["siio.i"] = {4, 0x11, {1, 1, 1}, function (n,o)
		if n == 2 then o = o / 2 end
		return o
	end},
	["siio.l"] = {4, 0x12, {1, 1, 1}, function (n,o)
		if n == 2 then o = o / 4 end
		return o
	end},

	["li"]     = {4, 0x13, {1, 2}},

	["si16.i"] = {4, 0x14, {1, 2}},
	["si16.l"] = {4, 0x15, {1, 2}},

	["lui"]    = {4, 0x16, {1, 2}, function (n,o)
		if n == 2 then o = (band(rshift(o, 16), 0xFFFF)) end
		return o
	end, 65536},

	["swd.b"]  = {4, 0x17, {1, 1, 1}},
	["swd.i"]  = {4, 0x18, {1, 1, 1}},
	["swd.l"]  = {4, 0x19, {1, 1, 1}},

	["swdi.b"] = {4, 0x1A, {1, 1}},
	["swdi.i"] = {4, 0x1B, {1, 2}},
	["swdi.l"] = {4, 0x1C, {1, 2}},

	["lwi.b"]  = {4, 0x1D, {1, 1, 1}},
	["lwi.i"]  = {4, 0x1E, {1, 1, 1}},
	["lwi.l"]  = {4, 0x1F, {1, 1, 1}},

	["sgpr"]   = {4, 0x20, {1}},
	["lgpr"]   = {4, 0x21, {1}},


	["beq"]    = {4, 0x24, {1, 1, -1}, function (n,o)
		if n == 3 then o = o / 4 end
		return o
	end},
	["beqi"]   = {4, 0x25, {1, 1, -1}, function (n,o)
		if n == 3 then o = o / 4 end
		return o
	end},
	["bne"]    = {4, 0x26, {1, 1, -1}, function (n,o)
		if n == 3 then o = o / 4 end
		return o
	end},
	["bnei"]   = {4, 0x27, {1, 1, -1}, function (n,o)
		if n == 3 then o = o / 4 end
		return o
	end},
	["blt"]    = {4, 0x28, {1, 1, -1}, function (n,o)
		if n == 3 then o = o / 4 end
		return o
	end},
	["blt.s"]  = {4, 0x29, {1, 1, -1}, function (n,o)
		if n == 3 then o = o / 4 end
		return o
	end},

	["slt"]    = {4, 0x2A, {1, 1, 1}},
	["slti"]   = {4, 0x2B, {1, 1, 1}},

	["slt.s"]  = {4, 0x2C, {1, 1, 1}},
	["slti.s"] = {4, 0x2D, {1, 1, 1}},

	["sgti"]   = {4, 0x2F, {1, 1, 1}},
	["sgti.s"] = {4, 0x30, {1, 1, 1}},

	["seq"]    = {4, 0x32, {1, 1, 1}},
	["sne"]   = {4, 0x33, {1, 1, 1}},

	["seqi"]    = {4, 0x2E, {1, 1, 1}},
	["snei"]   = {4, 0x31, {1, 1, 1}},


	["b"]      = {4, 0x34, {-3}, function (n,o)
		if n == 1 then o = o / 4 end
		return o
	end},
	["j"]      = {4, 0x35, {3},  function (n,o)
		if n == 1 then o = o / 4 end
		return o
	end, 4},
	["jal"]    = {4, 0x36, {3},  function (n,o)
		if n == 1 then o = o / 4 end
		return o
	end, 4},
	["jalr"]   = {4, 0x37, {1}},

	["jr"]     = {4, 0x38, {1}},

	["brk"]    = {4, 0x39, {}},
	["sys"]    = {4, 0x3A, {}},


	["add"]    = {4, 0x3B, {1, 1, 1}},
	["addi"]   = {4, 0x3C, {1, 1, 1}},
	["addi.i"] = {4, 0x3D, {1, 2}},

	["sub"]    = {4, 0x3E, {1, 1, 1}},
	["subi"]   = {4, 0x3F, {1, 1, 1}},
	["subi.i"] = {4, 0x40, {1, 2}},

	["mul"]    = {4, 0x41, {1, 1, 1}},
	["muli"]   = {4, 0x42, {1, 1, 1}},
	["muli.i"] = {4, 0x43, {1, 2}},

	["div"]    = {4, 0x44, {1, 1, 1}},
	["divi"]   = {4, 0x45, {1, 1, 1}},
	["divi.i"] = {4, 0x46, {1, 2}},

	["mod"]    = {4, 0x47, {1, 1, 1}},
	["modi"]   = {4, 0x48, {1, 1, 1}},
	["modi.i"] = {4, 0x49, {1, 2}},


	["not"]    = {4, 0x4C, {1, 1}},

	["or"]     = {4, 0x4D, {1, 1, 1}},
	["ori"]    = {4, 0x4E, {1, 1, 1}},
	["ori.i"]  = {4, 0x4F, {1, 2}},

	["xor"]    = {4, 0x50, {1, 1, 1}},
	["xori"]   = {4, 0x51, {1, 1, 1}},
	["xori.i"] = {4, 0x52, {1, 2}},

	["and"]    = {4, 0x53, {1, 1, 1}},
	["andi"]   = {4, 0x54, {1, 1, 1}},
	["andi.i"] = {4, 0x55, {1, 2}},

	["lsh"]    = {4, 0x56, {1, 1, 1}},
	["lshi"]   = {4, 0x57, {1, 1, 1}},

	["rsh"]    = {4, 0x58, {1, 1, 1}},
	["rshi"]   = {4, 0x59, {1, 1, 1}},

	["bset"]   = {4, 0x5A, {1, 1, 1}},
	["bseti"]  = {4, 0x5B, {1, 1, 1}},

	["bclr"]   = {4, 0x5C, {1, 1, 1}},
	["bclri"]  = {4, 0x5D, {1, 1, 1}},

	["bget"]   = {4, 0x5E, {1, 1, 1}},
	["bgeti"]  = {4, 0x5F, {1, 1, 1}},

	["bswap"]  = {4, 0x60, {1, 1}},


	["rfe"]    = {4, 0x62, {}},
	["hlt"]    = {4, 0x63, {}},
	["wtlb"]   = {4, 0x64, {1, 1}},
	["ftlb"]   = {4, 0x65, {1, 1}},

	["bt"]      = {4, 0x67, {-3}, function (n,o)
		if n == 1 then o = o / 4 end
		return o
	end},
	["bf"]      = {4, 0x68, {-3}, function (n,o)
		if n == 1 then o = o / 4 end
		return o
	end},
}

local pseudo = {
	["ret"]    = {0, function (ops)
		return "jr lr"
	end},
	["la"]     = {2, function (ops)
		return string.format("lui %s, %s\naddi.i %s, %s", ops[2], ops[3], ops[2], ops[3])
	end},
	["push"]   = {1, function (ops)
		return string.format("swd.l sp, zero, %s", ops[2])
	end},
	["pushi"]  = {1, function (ops)
		return string.format("swdi.l sp, %s", ops[2])
	end},
	["pop"]    = {1, function (ops)
		return string.format("lwi.l %s, sp, zero", ops[2])
	end},
	["mov"]    = {2, function (ops)
		return string.format("add %s, %s, zero", ops[2], ops[3])
	end},
	["bge"]    = {3, function (ops)
		return string.format("slt at, %s, %s\nbeq at, zero, %s", ops[2], ops[3], ops[4])
	end},
	["ble"]    = {3, function (ops)
		return string.format("sgt at, %s, %s\nbeq at, zero, %s", ops[2], ops[3], ops[4])
	end},
}

local regs = {
	["zero"]  = 0,
	["at"]  = 27,
	["tf"]  = 28,
	["sp"]  = 29,
	["lr"]  = 30,
	["pc"]  = 31,

	-- privileged

	["k0"]  = 32,
	["k1"]  = 33,
	["k2"]  = 34,
	["k3"]  = 35,
	["rs"]  = 36,
	["ev"]  = 37,
	["epc"] = 38,
	["ecause"] = 39,
	["ers"] = 40,
	["timer"] = 41,
	["cpuid"] = 42,
	["badaddr"] = 43,
	["tlbv"] = 44,
	["asid"] = 45,

	-- helpful dragonfruit ABI names

	["t0"] = 1,
	["t1"] = 2,
	["t2"] = 3,
	["t3"] = 4,
	["t4"] = 5,
	["a0"] = 6,
	["a1"] = 7,
	["a2"] = 8,
	["a3"] = 9,
	["v0"] = 10,
	["v1"] = 11,
	["s0"] = 12,
	["s1"] = 13,
	["s2"] = 14,
	["s3"] = 15,
	["s4"] = 16,
	["s5"] = 17,
	["s6"] = 18,
	["s7"] = 19,
	["s8"] = 20,
	["s9"] = 21,
	["s10"] = 22,
	["s11"] = 23,
	["s12"] = 24,
	["s13"] = 25,
	["s14"] = 26,
}

return {inst, regs, {}, 4, false, pseudo}