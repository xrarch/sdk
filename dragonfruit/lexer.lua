local lex = {}

function lex.extractAll(src, filename, stream, spot)
	local kc = {
		["!"] = true,
		["@"] = true,
		["#"] = true,
		["("] = true,
		[")"] = true,
		["["] = true,
		["]"] = true,
	}

	local whitespace = {
		[" "] = true,
		["\t"] = true,
		["\n"] = true,
	}

	local tokens = stream.tokens

	local line = 1

	local cpt = 1

	local srclen = #src

	local function extractChar(com)
		if cpt > srclen then
			return false
		end

		local o = src:sub(cpt,cpt)
		cpt = cpt + 1

		if o == string.char(0xD) then
			error("dragonc: lexer: Windows/DOS line endings aren't supported.")
		end

		while ((com) and (o == "(")) do
			if src:sub(cpt, cpt) == "*" then
				cpt = cpt + 1

				o = src:sub(cpt,cpt)

				while true do
					if o == "*" then
						if src:sub(cpt,cpt) == ")" then
							cpt = cpt + 1

							o = src:sub(cpt,cpt)
							cpt = cpt + 1

							break
						end
					elseif o == "\n" then
						line = line + 1
					end

					o = src:sub(cpt,cpt)
					cpt = cpt + 1

					if not o then
						break
					end
				end
			else
				break
			end
		end

		return o
	end

	while cpt <= srclen do
		local c = extractChar(true)

		while whitespace[c] do
			if c == "\n" then
				line = line + 1
			end

			c = extractChar(true)
		end

		if not c then break end

		if kc[c] then
			table.insert(tokens, spot, {c, "keyc", line, filename})
			spot = spot + 1
		else
			local t = ""

			if c == '"' then
				c = extractChar()

				while (c ~= '"') and c do
					if c == "\\" then
						c = extractChar()

						if not c then
							print(string.format("%s:%d: malformed string", filename, line))
							return false
						else
							if c == "\\" then
								t = t.."\\"
							elseif c == "n" then
								t = t.."\n"
							elseif c == "t" then
								t = t.."\t"
							elseif c == "r" then
								t = t..string.char(0xD)
							elseif c == "[" then
								t = t..string.char(0x1b)
							else
								t = t..c
							end
						end
					else
						t = t..c
					end

					c = extractChar()
				end

				if not c then
					print(string.format("%s:%d: malformed string", filename, line))
					return false
				end

				table.insert(tokens, spot, {t, "string", line, filename})
				spot = spot + 1
			elseif c == "'" then
				local rc = extractChar()

				if rc == "\\" then
					rc = extractChar()

					if rc == "n" then
						rc = "\n"
					elseif rc == "r" then
						rc = string.char(0xD)
					elseif rc == "t" then
						rc = "\t"
					elseif rc == "b" then
						rc = "\b"
					elseif rc == "[" then
						rc = string.char(0x1b)
					end
				end

				if extractChar() ~= "'" then
					print(string.format("%s:%d: malformed char", filename, line))
					return false
				end

				table.insert(tokens, spot, {string.byte(rc), "number", line, filename})
				spot = spot + 1
			else
				while (not whitespace[c]) and (not kc[c]) and (c) do
					t = t..c
					c = extractChar()
				end

				if kc[c] then
					cpt = cpt - 1

					if tonumber(t) then
						table.insert(tokens, spot, {tonumber(t), "number", line, filename})
						spot = spot + 1
					else
						table.insert(tokens, spot, {t, "tag", line, filename})
						spot = spot + 1
					end
				elseif tonumber(t) then
					table.insert(tokens, spot, {tonumber(t), "number", line, filename})
					spot = spot + 1
				else
					table.insert(tokens, spot, {t, "tag", line, filename})
					spot = spot + 1
				end

				if c == "\n" then
					line = line + 1
				end
			end
		end
	end

	return true
end

function lex.new(src, filename)
	local s = {}

	s.token = 1
	s.tokens = {}

	if not lex.extractAll(src, filename, s, 1) then return false end

	function s:insertCurrent(src, filename)
		lex.extractAll(src, filename, s, s.token)
	end

	function s:extract()
		if s.token > #s.tokens then
			return false
		end

		s.token = s.token + 1

		return s.tokens[s.token - 1]
	end

	function s:peek()
		return s.tokens[s.token]
	end

	function s:expect(kind)
		local t = self:extract()

		if not t then return {0, "EOF"}, false end

		if t[2] ~= kind then return t, false end

		return t, true
	end

	return s
end

return lex