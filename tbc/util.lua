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