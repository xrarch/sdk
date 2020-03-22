--[[

	a3x microcode
	supports platform-independent on-board drivers

	{bytes, opcode, {operands (sizes in bytes)}}
	though this is written a bit funky to make all instructions 32 bits

]]

local inst = {
	["nop"]   = {4, 0x0, {-3}},

	["li"]    = {4, 0x1, {1, 2}},
	["lui"]   = {4, 0x2, {1, 2}},

	["s.b"]   = {4, 0x3, {1, 1, -1}},
	["s.i"]   = {4, 0x4, {1, 1, -1}},
	["s.l"]   = {4, 0x5, {1, 1, -1}},

	["l.b"]   = {4, 0x6, {1, 1, -1}},
	["l.i"]   = {4, 0x7, {1, 1, -1}},
	["l.l"]   = {4, 0x8, {1, 1, -1}},

	["add"]   = {4, 0x9, {1, 1, 1}},
	["sub"]   = {4, 0xA, {1, 1, 1}},
	["mul"]   = {4, 0xB, {1, 1, 1}},
	["div"]   = {4, 0xC, {1, 1, 1}},

	["not"]   = {4, 0xD, {1, 1, -1}},
	["or"]    = {4, 0xE, {1, 1, 1}},
	["and"]   = {4, 0xF, {1, 1, 1}},
	["xor"]   = {4, 0x10, {1, 1, 1}},
	["lsh"]   = {4, 0x11, {1, 1, 1}},
	["rsh"]   = {4, 0x12, {1, 1, 1}},
	["bset"]  = {4, 0x13, {1, 1, 1}},
	["bclr"]  = {4, 0x14, {1, 1, 1}},

	["bt"]    = {4, 0x15, {3}},
	["bf"]    = {4, 0x16, {3}},

	["br"]    = {4, 0x17, {1, -2}},

	["call"]  = {4, 0x18, {3}},
	["callr"] = {4, 0x19, {1, -2}},

	["g"]     = {4, 0x1A, {1, 1, -1}},
	["l"]     = {4, 0x1B, {1, 1, -1}},
	["e"]     = {4, 0x1C, {1, 1, -1}},

	["ret"]   = {4, 0x1D, {-3}},

	["a3x"]   = {4, 0x1E, {3}},

	["push"]  = {4, 0x1F, {1, -2}},
	["pop"]   = {4, 0x20, {1, -2}},
	["drop"]  = {4, 0x21, {-3}},
	["swap"]  = {4, 0x22, {-3}},

	["gs"]    = {4, 0x23, {1, 1, -1}},
	["ls"]    = {4, 0x24, {1, 1, -1}},

	["mod"]   = {4, 0x25, {1, 1, 1}},

	["dup"]   = {4, 0x26, {1, 1, 1}},

	["b"]     = {4, 0x27, {3}},

	["ne"]    = {4, 0x28, {1, 1, -1}},

	["rpush"] = {4, 0x29, {1, -2}},
	["rpop"]  = {4, 0x2A, {1, -2}},

	["push24"]= {4, 0x2B, {3}},

	["mov"]   = {4, 0x2C, {1, 1, -1}},
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
	["rf"] = 28,
	["data"] = 29,
	["code"] = 30,
	["slot"]  = 31,
}

local consts = {
	["DevTreeWalk"] = 0,
	["DeviceParent"] = 1,
	["DeviceSelectNode"] = 2,
	["DeviceSelect"] = 3,
	["DeviceNew"] = 4,
	["DeviceClone"] = 5,
	["DeviceCloneWalk"] = 6,
	["DSetName"] = 7,
	["DAddMethod"] = 8,
	["DSetProperty"] = 9,
	["DGetProperty"] = 10,
	["DGetMethod"] = 11,
	["DCallMethod"] = 12,
	["DeviceExit"] = 13,
	["DGetName"] = 14,

	["Putc"] = 15,
	["Getc"] = 16,
	["Malloc"] = 17,
	["Calloc"] = 18,
	["Free"] = 19,
	["Puts"] = 20,
	["Gets"] = 21,
	["Printf"] = 22,

	["DevIteratorInit"] = 23,
	["DevIterate"] = 24,
}

return {inst, regs, consts}