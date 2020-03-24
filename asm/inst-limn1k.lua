--[[

	{bytes, opcode, {operands (sizes in bytes)}}

]]

local inst = {
	["nop"]   = {1, 0x0,  {}},

-- load/store primitives

	["li"]    = {6, 0x1,  {1, 4}},
	["mov"]   = {3, 0x2,  {1, 1}},
	["xch"]   = {3, 0x3,  {1, 1}},

	["lri.b"] = {6, 0x4,  {1, 4}},
	["lri.i"] = {6, 0x5,  {1, 4}},
	["lri.l"] = {6, 0x6,  {1, 4}},

	["sir.b"] = {6, 0x7,  {4, 1}},
	["sir.i"] = {6, 0x8,  {4, 1}},
	["sir.l"] = {6, 0x9,  {4, 1}},

	["lrr.b"] = {3, 0xA,  {1, 1}},
	["lrr.i"] = {3, 0xB,  {1, 1}},
	["lrr.l"] = {3, 0xC,  {1, 1}},

	["srr.b"] = {3, 0xD,  {1, 1}},
	["srr.i"] = {3, 0xE,  {1, 1}},
	["srr.l"] = {3, 0xF,  {1, 1}},

	["sii.b"] = {6, 0x10, {4, 1}},
	["sii.i"] = {7, 0x11, {4, 2}},
	["sii.l"] = {9, 0x12, {4, 4}},

	["sri.b"] = {3, 0x13, {1, 1}},
	["sri.i"] = {4, 0x14, {1, 2}},
	["sri.l"] = {6, 0x15, {1, 4}},

	["push"]  = {2, 0x16, {1}},
	["pushi"] = {5, 0x17, {4}},

	["pop"]   = {2, 0x18, {1}},

	["pusha"] = {1, 0x19, {}},
	["popa"]  = {1, 0x1A, {}},

-- control flow primitives

	["b"]     = {5, 0x1B, {4}},
	["br"]    = {2, 0x1C, {1}},
	["be"]    = {5, 0x1D, {4}},
	["bz"]    = {5, 0x1D, {4}},
	["bne"]   = {5, 0x1E, {4}},
	["bnz"]   = {5, 0x1E, {4}},
	["bg"]    = {5, 0x1F, {4}},
	["bl"]    = {5, 0x20, {4}},
	["bc"]    = {5, 0x1F, {4}},
	["bge"]   = {5, 0x21, {4}},
	["bnc"]   = {5, 0x21, {4}},
	["ble"]   = {5, 0x22, {4}},
	["call"]  = {5, 0x23, {4}},
	["ret"]   = {1, 0x24, {}},

-- comparison primitives

	["cmp"]   = {3, 0x25, {1, 1}},
	["cmpi"]  = {6, 0x26, {1, 4}},

-- arithmetic primitives

	["add"]   = {4, 0x27, {1, 1, 1}},
	["addi"]  = {7, 0x28, {1, 1, 4}},

	["sub"]   = {4, 0x29, {1, 1, 1}},
	["subi"]  = {7, 0x2A, {1, 1, 4}},

	["mul"]   = {4, 0x2B, {1, 1, 1}},
	["muli"]  = {7, 0x2C, {1, 1, 4}},

	["div"]   = {4, 0x2D, {1, 1, 1}},
	["divi"]  = {7, 0x2E, {1, 1, 4}},

	["mod"]   = {4, 0x2F, {1, 1, 1}},
	["modi"]  = {7, 0x30, {1, 1, 4}},

-- logical primitives

	["not"]   = {3, 0x31, {1, 1}},

	["ior"]   = {4, 0x32, {1, 1, 1}},
	["iori"]  = {7, 0x33, {1, 1, 4}},

	["nor"]   = {4, 0x34, {1, 1, 1}},
	["nori"]  = {7, 0x35, {1, 1, 4}},

	["eor"]   = {4, 0x36, {1, 1, 1}},
	["eori"]  = {7, 0x37, {1, 1, 4}},

	["and"]   = {4, 0x38, {1, 1, 1}},
	["andi"]  = {7, 0x39, {1, 1, 4}},

	["nand"]  = {4, 0x3A, {1, 1, 1}},
	["nandi"] = {7, 0x3B, {1, 1, 4}},

	["lsh"]   = {4, 0x3C, {1, 1, 1}},
	["lshi"]  = {4, 0x3D, {1, 1, 1}},

	["rsh"]   = {4, 0x3E, {1, 1, 1}},
	["rshi"]  = {4, 0x3F, {1, 1, 1}},

	["bset"]  = {4, 0x40, {1, 1, 1}},
	["bseti"] = {4, 0x41, {1, 1, 1}},

	["bclr"]  = {4, 0x42, {1, 1, 1}},
	["bclri"] = {4, 0x43, {1, 1, 1}},

-- special instructions

	["sys"]   = {2, 0x44, {1}},
	["cli"]   = {1, 0x45, {}},
	["brk"]   = {1, 0x46, {}},
	["hlt"]   = {1, 0x47, {}},
	["iret"]  = {1, 0x48, {}},

-- extensions

	["bswap"] = {3, 0x49, {1, 1}},
	["cpu"]   = {1, 0x4C, {}},
	["rsp"]   = {2, 0x4D, {1}},
	["ssp"]   = {2, 0x4E, {1}},
	["pushv"]  = {3, 0x4F, {1, 1}},
	["pushvi"] = {6, 0x50, {1, 4}},
	["popv"]   = {3, 0x51, {1, 1}},

	["cmps"]   = {3, 0x52, {1, 1}},
	["cmpsi"]  = {6, 0x53, {1, 4}},

	["imask"]   = {2, 0x54, {1}},
	["iunmask"]  = {2, 0x55, {1}},
}

local regs = {
	["r0"]  = 0,
	["r1"]  = 1,
	["r2"]  = 2,
	["r3"]  = 3,
	["r4"]  = 4,
	["r5"]  = 5,
	["r6"]  = 6,
	["r7"]  = 7,
	["r8"]  = 8,
	["r9"]  = 9,
	["r10"] = 10,
	["r11"] = 11,
	["r12"] = 12,
	["r13"] = 13,
	["r14"] = 14,
	["r15"] = 15,
	["r16"] = 16,
	["r17"] = 17,
	["r18"] = 18,
	["r19"] = 19,
	["r20"] = 20,
	["r21"] = 21,
	["r22"] = 22,
	["r23"] = 23,
	["r24"] = 24,
	["r25"] = 25,
	["r26"] = 26,
	["r27"] = 27,
	["r28"] = 28,
	["r29"] = 29,
	["r30"] = 30,
	["rf"]  = 31,

	["pc"]  = 32,
	["sp"]  = 33,
	["rs"]  = 34,
	["ivt"] = 35,
	["fa"] = 36,
	["usp"] = 37,

	["k0"] = 38,
	["k1"] = 39,
	["k2"] = 40,
	["k3"] = 41,
}

return {inst, regs, {}}

















