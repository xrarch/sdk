function newsb()
	local sb = {}

	sb.stack = {}

	function sb.append(str)
		table.insert(sb.stack, str)
	end

	function sb.tostring()
		return table.concat(sb.stack)
	end

	return sb
end