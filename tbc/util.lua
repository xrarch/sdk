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

	if not def.decltype then
		error("no decltype")
	end

	scopeblock.scope[def.name] = def
	def.scopeblock = scopeblock

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

primitivetypes._char = {}
primitivetypes._char.min = -128
primitivetypes._char.max = 127
primitivetypes._char.bits = 8
primitivetypes._char.ctype = "char"

primitivetypes._int = {}
primitivetypes._int.min = -2147483648
primitivetypes._int.max = 2147483647
primitivetypes._int.bits = 32
primitivetypes._int.ctype = "int"

primitivetypes.BYTE = {}
primitivetypes.BYTE.min = -128
primitivetypes.BYTE.max = 127
primitivetypes.BYTE.bits = 8
primitivetypes.BYTE.ctype = "int8_t"

primitivetypes.INT = {}
primitivetypes.INT.min = -32768
primitivetypes.INT.max = 32767
primitivetypes.INT.bits = 16
primitivetypes.INT.ctype = "int16_t"

primitivetypes.LONG = {}
primitivetypes.LONG.min = -2147483648
primitivetypes.LONG.max = 2147483647
primitivetypes.LONG.bits = 32
primitivetypes.LONG.ctype = "int32_t"

primitivetypes.UBYTE = {}
primitivetypes.UBYTE.min = 0
primitivetypes.UBYTE.max = 255
primitivetypes.UBYTE.bits = 8
primitivetypes.UBYTE.ctype = "uint8_t"

primitivetypes.UINT = {}
primitivetypes.UINT.min = 0
primitivetypes.UINT.max = 65535
primitivetypes.UINT.bits = 16
primitivetypes.UINT.ctype = "uint16_t"

primitivetypes.ULONG = {}
primitivetypes.ULONG.min = 0
primitivetypes.ULONG.max = 4294967295
primitivetypes.ULONG.bits = 32
primitivetypes.ULONG.ctype = "uint32_t"