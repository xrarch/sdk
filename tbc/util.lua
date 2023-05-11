function _G.findSymbol(searchblock, name)
	while searchblock do
		local sym = searchblock.scope[name]

		if sym then
			return sym
		end

		searchblock = searchblock.parentblock
	end
end

function _G.defineSymbol(scopeblock, def)
	local sym = findSymbol(scopeblock, def.name)

	if sym then
		return false
	end

	scopeblock.scope[def.name] = def

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

function _G.comparetables(table1, table2)
	for k,v in pairs(table1) do
		local equ = table2[k]

		if v ~= equ then
			return false
		end
	end

	return true
end

_G.symboltypes = {
	SYM_VAR  = 1,
	SYM_TYPE = 2,
}