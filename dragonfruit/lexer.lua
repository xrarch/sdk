local lex = {}

function lex.new(src, ekc, ewhitespace)
	local s = {}

	s.src = src
	s.ptr = 1

	s.kc = ekc
	s.whitespace = ewhitespace

	s.line = 1

	local kc = s.kc
	local whitespace = s.whitespace

	function s:insert(str)
		self.src = self.src:sub(1,self.ptr) .. str .. self.src:sub(self.ptr + 1, -1)
	end

	function s:extractChar()
		if self.ptr > #self.src then
			return false
		end

		local o = self.src:sub(self.ptr,self.ptr)
		self.ptr = self.ptr + 1

		if o == "\n" then
			self.line = self.line + 1
		end

		return o
	end

	function s:extract()
		local c = self:extractChar()

		while whitespace[c] do
			c = self:extractChar()
		end

		if not c then return false end

		if kc[c] then
			return {c, "keyc"}
		end

		local t = ""

		if c == '"' then
			c = self:extractChar()
			while (c ~= '"') and c do
				if c == "\\" then
					c = self:extractChar()

					if not c then
						return {"malformed string: escape", "error"}
					else
						if c == "\\" then
							t = t.."\\"
						elseif c == "n" then
							t = t.."\n"
						elseif c == "t" then
							t = t.."\t"
						elseif c == "[" then
							t = t..string.char(0x1b)
						else
							t = t..c
						end
					end
				else
					t = t..c
				end

				c = self:extractChar()
			end

			if not c then
				return {"malformed string", "error"}
			end

			return {t, "string"}
		end

		if c == "'" then
			local rc = self:extractChar()

			if rc == "\\" then
				rc = self:extractChar()

				if rc == "n" then
					rc = "\n"
				elseif rc == "t" then
					rc = "\t"
				elseif rc == "b" then
					rc = "\b"
				elseif rc == "[" then
					rc = string.char(0x1b)
				end
			end

			if self:extractChar() ~= "'" then
				return {"malformed char", "error"}
			end

			return {string.byte(rc), "number"}
		end

		while (not whitespace[c]) and (not kc[c]) and (c ~= false) do
			t = t..c
			c = self:extractChar()
		end

		if kc[c] then
			self.ptr = self.ptr - 1

			if tonumber(t) then
				return {tonumber(t), "number"}
			end

			return {t, "tag"}
		end

		if tonumber(t) then
			return {tonumber(t), "number"}
		end

		return {t, "tag"}
	end

	function s:peek()
		local optr = self.ptr
		local oline = self.line

		local o = self:extract()

		self.ptr = optr
		self.line = oline

		return o
	end

	return s
end

return lex