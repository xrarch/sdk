--[[

	Platform Environment Code
	supports platform-independent on-board drivers

	{bytes, opcode, {operands (sizes in bytes)}}

]]

local inst = {
	["nop"]   = {1, 0x0,  {}},

	["push"]  = {5, 0x1,  {4}},
	["add"]   = {1, 0x2,  {}},
	["sub"]   = {1, 0x3,  {}},
	["mul"]   = {1, 0x4,  {}},
	["div"]   = {1, 0x5,  {}},
	["mod"]   = {1, 0x6,  {}},
	["drop"]  = {1, 0x7,  {}},
	
	["eq"]    = {1, 0x8,  {}},
	["neq"]   = {1, 0x9,  {}},
	["gt"]    = {1, 0xA,  {}},
	["lt"]    = {1, 0xB,  {}},

	["b"]     = {1, 0xC,  {}},
	["bt"]    = {1, 0xD,  {}},
	["bf"]    = {1, 0xE,  {}},

	["load"]  = {1, 0xF,  {}},
	["store"] = {1, 0x10, {}},

	["swap"]  = {1, 0x11, {}},

	["call"]  = {1, 0x12, {}},
	["callt"] = {1, 0x13, {}},
	["callf"] = {1, 0x14, {}},

	["ret"]   = {1, 0x15, {}},
	["rett"]  = {1, 0x16, {}},
	["retf"]  = {1, 0x17, {}},

	["popd"]  = {1, 0x18, {}},
	["pushd"] = {1, 0x19, {}},

	["ncall"] = {5, 0x1A, {4}},

	["base"]  = {1, 0x1B, {}},

	["slot"]  = {1, 0x1C, {}},

	["xor"]   = {1, 0x1D, {}},
	["or"]    = {1, 0x1E, {}},
	["not"]   = {1, 0x1F, {}},
	["and"]   = {1, 0x20, {}},
}

local regs = {
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
}

return {inst, regs, consts}