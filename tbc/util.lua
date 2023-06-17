function _G.findSymbol(searchblock, name)
	while searchblock do
		local sym = searchblock.scope[name]

		if sym then
			return sym
		end

		searchblock = searchblock.parentblock
	end
end

function _G.defineSymbol(scopeblock, def, nocheck)
	if not nocheck then
		local sym = findSymbol(scopeblock, def.name)

		if sym then
			return false
		end
	end

	scopeblock.scope[def.name] = def

	-- add to an ordered list of definitions as well for things that would
	-- like to iterate that, so that the output can be deterministic.

	table.insert(scopeblock.iscope, def)

	return true
end

local gencount = 0

function _G.tprint (tbl, indent)
	if not indent then
		gencount = gencount + 1
		indent = 0
	end

	if tbl._tprint_gen_count == gencount then
		local formatting = string.rep("  ", indent)

		print(formatting .. "already printed!")

		return
	end

	tbl._tprint_gen_count = gencount

	for k, v in pairs(tbl) do
		if k ~= "_tprint_gen_count" then
			local formatting = string.rep("  ", indent) .. k .. ": "

			if type(v) == "table" then
				print(formatting)
				tprint(v, indent+1)
			elseif type(v) == 'boolean' then
				print(formatting .. tostring(v))      
			else
				print(formatting .. tostring(v))
			end
		end
	end
end

function _G.compareTypes(type1, type2)
	if type1.pointer ~= type2.pointer then
		return false
	end

	if type1.array ~= type2.array then
		return false
	end

	if type(type1.base) == "string" then
		return type1.base == type2.base
	end

	return compareTypes(type1.base, type2.base)
end

_G.symboltypes = {
	SYM_VAR   = 1,
	SYM_TYPE  = 2,
	SYM_LABEL = 3,
}

_G.primitivetypes = {}

primitivetypes.byte = {}
primitivetypes.byte.min = -128
primitivetypes.byte.max = 127
primitivetypes.byte.bits = 8
primitivetypes.byte.ctype = "int8_t"

primitivetypes.int = {}
primitivetypes.int.min = -32768
primitivetypes.int.max = 32767
primitivetypes.int.bits = 16
primitivetypes.int.ctype = "int16_t"

primitivetypes.long = {}
primitivetypes.long.min = -2147483648
primitivetypes.long.max = 2147483647
primitivetypes.long.bits = 32
primitivetypes.long.ctype = "int32_t"

primitivetypes.ubyte = {}
primitivetypes.ubyte.min = 0
primitivetypes.ubyte.max = 255
primitivetypes.ubyte.bits = 8
primitivetypes.ubyte.ctype = "uint8_t"

primitivetypes.uint = {}
primitivetypes.uint.min = 0
primitivetypes.uint.max = 65535
primitivetypes.uint.bits = 16
primitivetypes.uint.ctype = "uint16_t"

primitivetypes.ulong = {}
primitivetypes.ulong.min = 0
primitivetypes.ulong.max = 4294967295
primitivetypes.ulong.bits = 32
primitivetypes.ulong.ctype = "uint32_t"