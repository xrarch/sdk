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

function _G.tprint (tbl, indent)
	if not indent then indent = 0 end

	if indent > 20 then
		error("too deep")
	end

	for k, v in pairs(tbl) do
		if k ~= "parentblock" then
			formatting = string.rep("  ", indent) .. k .. ": "
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