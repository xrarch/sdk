function _G.findSymbol(searchblock, name)
	while searchblock do
		local sym = searchblock.scope[name]

		if sym then
			return sym
		end

		searchblock = searchblock.parentblock
	end
end

function _G.defineSymbol(scopeblock, name, def)
	local sym = findSymbol(scopeblock, name)

	if sym then
		return false
	end

	scopeblock.scope[name] = def

	return true
end

function _G.tprint (tbl, indent)
	if not indent then indent = 0 end
	for k, v in pairs(tbl) do
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