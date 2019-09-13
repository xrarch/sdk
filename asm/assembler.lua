local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

dofile(sd.."misc.lua")

local tinst = dofile(sd.."inst.lua")
local inst, regs = tinst[1], tinst[2]

local function lerror(line, err)
	print(string.format("%s:%d: %s", line.file, line.number, err))
end

local function dumpAllLines(block)
	local lines = block.lines

	print("== line dump ==")

	for k,v in ipairs(lines) do
		if v.text then
			print(string.format("%s:%d: %s", v.file, v.number, v.text))
		end
	end
end

local asm = {}

function asm.lines(block, source, filename)
	local lines = block.lines

	local llit = lineate(source)

	local lnum = 0

	for n,line in ipairs(llit) do
		lnum = lnum + 1

		while (line:sub(1,1) == " ") or (line:sub(1,1) == "\t") do
			line = line:sub(2)
		end

		local tt = tokenize(line)

		if tt[1] ~= ".ds" then
			for i = 1, #line do
				if line:sub(i,i) == ";" then
					line = line:sub(1, i-1)
					break
				end
			end

			while (line:sub(-1,-1) == " ") do
				line = line:sub(1,-2)
			end

			tt = tokenize(line)
		end

		if line ~= "" then
			if tt[1] ~= ".ds" then -- ds is immune
				line = ""

				for k,v in ipairs(tt) do
					if v:sub(-1,-1) == "," then
						v = v:sub(1,-2)
					end

					if k > 1 then
						line = line .. " " .. v
					else
						line = v
					end
				end
			end

			if tt[1] == ".include" then
				local srcf = io.open(block.basedir .. "/" .. tt[2], "r")
				if not srcf then
					print(string.format("%s:%d: file not found", filename, lnum))
					return false
				end

				if not asm.lines(block, srcf:read("*a"), tt[2]) then return false end

				srcf:close()
			else
				lines[#lines + 1] = {}

				local key = #lines

				lines[key].text = line
				lines[key].file = filename
				lines[key].number = lnum

				lines[key].destroy = function (self)
					self.text = nil
				end

				lines[key].replace = function (self, text)
					self.text = text
				end
			end
		end
	end

	return true
end

function asm.labels(block)
	block.labels = {}

	block.labels["__DATE"] = os.date()

	block.globals = {}
	block.extern = {}
	block.structs = {}
	block.localLabels = {}
	block.constants = {}
	local byteCount = 0
	local curStruct = false
	local strCount = 0
	local curLabel

	for k,v in ipairs(block.lines) do
		local tokens = tokenize(v.text)

		local word = tokens[1]

		if curStruct then
			if word == "end-struct" then
				block.labels[curStruct.."_sizeof"] = strCount
				curStruct = false
				strCount = 0
			elseif #tokens == 2 then
				block.labels[curStruct.."_"..word] = strCount

				local sz = tonumber(tokens[2])

				if not sz then
					lerror(v, "malformed struct entry")
					return false
				end

				strCount = strCount + sz
			else
				lerror(v, "malformed struct entry")
				return false
			end

			v:destroy()
		else
			if word:sub(-1,-1) == ":" then -- label
				if word:sub(1,1) == "." then -- local label
					if not curLabel then
						lerror(v, "can't define local label when no label has been defined yet")
						return false
					end

					local ll = block.localLabels[curLabel]

					if ll[word:sub(2,-2)] then
						lerror(v, "can't define local label '"..word:sub(2,-2).."' twice")
						return false
					end

					ll[word:sub(2,-2)] = byteCount

					v:destroy()
				else
					if block.labels[word:sub(1,-2)] then
						lerror(v, "can't define label '"..word:sub(1,-2).."' twice.")
						return false
					else
						curLabel = word:sub(1,-2)

						block.labels[curLabel] = byteCount

						block.localLabels[curLabel] = {}
					end
				end
			elseif tokens[2] == "===" then
				local value = tokens[3]

				if not value then
					lerror(v, "unfinished constant definition")
					return false
				end

				if block.labels[word] then
					lerror(v, "can't define constant; symbol '"..word.."' cannot be defined twice.")
					return false
				end

				if value:sub(1,1) == "#" then
					local file = io.open(block.basedir .. "/" .. value:sub(2), "r")

					if not file then
						lerror(v, "can't open file '"..value:sub(2).."'.")
						return false
					end

					block.labels[word] = file:read("*a")

					file:close()
				else
					block.labels[word] = value
				end

				block.constants[word] = true

				v:destroy()
			elseif word == ".struct" then
				curStruct = tokens[2]

				if not curStruct then
					lerror(v, "no name provided for struct")
					return false
				end

				v:destroy()
			elseif word == ".static" then
				local path = tokens[2]

				if not path then
					lerror(v, "no path for .static")
					return false
				end

				local file = io.open(block.basedir .. "/" .. path, "r")

				if not file then
					lerror(v, "can't open file '"..path.."'")
					return false
				end

				local sc = file:read("*a")

				local size = file:seek("end")

				file:close()

				v.static = sc
				v.staticsize = size

				byteCount = byteCount + size
			elseif word == ".db" then
				if #tokens == 1 then
					lerror(v, ".db needs 2+ arguments")
					return false
				end

				byteCount = byteCount + (#tokens - 1)
			elseif word == ".di" then
				if #tokens == 1 then
					lerror(v, ".di needs 2+ arguments")
					return false
				end

				byteCount = byteCount + ((#tokens - 1) * 2)
			elseif word == ".dl" then
				if #tokens == 1 then
					lerror(v, ".dl needs 2+ arguments")
					return false
				end

				byteCount = byteCount + ((#tokens - 1) * 4)
			elseif word == ".ds" then
				byteCount = byteCount + #v.text:sub(5)
			elseif word == ".ds$" then
				if #tokens == 1 then
					lerror(v, ".ds$ needs a symbol")
					return false
				end

				if not block.labels[tokens[2]] then
					lerror(v, "'"..tokens[2].."' is not a symbol")
					return false
				end

				byteCount = byteCount + #tostring(block.labels[tokens[2]])
			elseif word == ".bytes" then
				if tonumber(tokens[2]) then
					byteCount = byteCount + tonumber(tokens[2])
				else
					lerror(v, ".bytes: invalid number")
					return false
				end
			elseif word == ".fill" then
				if tonumber(tokens[2]) then
					byteCount = tonumber(tokens[2])
				else
					lerror(v, ".fill: invalid number")
					return false
				end
			elseif word == ".org" then
				if tokens[2] then
					if tonumber(tokens[2]) then
						byteCount = tonumber(tokens[2])
					else
						lerror(v, ".org: invalid number")
						return false
					end
				else
					lerror(v, ".org: unfinished org")
					return false
				end

				v:destroy()
			elseif word == ".bc" then
				if not tokens[2] then
					lerror(v, ".bc: needs symbol")
					return false
				end

				if tokens[2] == "@" then
					v:replace(".bc "..tostring(byteCount))
				end
			elseif word == ".global" then
				if not tokens[2] then
					lerror(v, ".global: needs symbol")
					return false
				end

				if not block.labels[tokens[2]] then
					lerror(v, ".global: '"..tokens[2].."' is not a symbol")
					return false
				end

				block.globals[tokens[2]] = block.labels[tokens[2]]

				v:destroy()
			elseif word == ".extern" then
				if not tokens[2] then
					lerror(v, ".extern: needs symbol name")
					return false
				end

				if block.labels[tokens[2]] then
					lerror(v, ".extern: '"..tokens[2].."' is already a symbol")
				end

				block.extern[tokens[2]] = true

				v:destroy()
			else
				local e = inst[word]

				if not e then
					lerror(v, "not an instruction: "..word)
					return false
				end

				v.offset = byteCount

				byteCount = byteCount + e[1]
			end
		end
	end

	return true
end

function asm.decode(block) -- decode labels, registers, strings
	block.reloc = {}

	local curLabel

	for k,v in ipairs(block.lines) do
		if v.text then
			local tokens = tokenize(v.text)

			local word = tokens[1]

			local lout = ""

			if word:sub(-1,-1) == ":" then
				curLabel = word:sub(1,-2)
				v:destroy()
			else
				if (word == ".ds") or (word == ".static") then
					lout = v.text
				elseif word == ".ds$" then
					lout = ".ds " .. tostring(block.labels[tokens[2]])
				else
					for n,t in ipairs(tokens) do
						if n == 1 then
							lout = t
						else
							if t:sub(1,1) == '"' then
								if #t == 3 then
									if t:sub(-1,-1) == '"' then
										lout = lout .. " " .. string.byte(t:sub(2,2))
									else
										lerror(v, "unclosed char")
										return false
									end
								else
									lerror(v, "cannot use a multi-byte char (fixme?)")
									return false
								end
							elseif tonumber(t) then
								lout = lout .. " " .. t
							elseif t:sub(1,1) == "." then -- local label
								if block.localLabels[curLabel][t:sub(2)] then
									lout = lout .. " " .. tostring(block.localLabels[curLabel][t:sub(2)])
								else
									lerror(v, "not a local label: '"..t:sub(2).."'")
									return false
								end

								if v.offset then
									block.reloc[#block.reloc + 1] = v.offset
								end
							elseif regs[t] then
								lout = lout .. " " .. tostring(regs[t])
							elseif block.labels[t] then
								lout = lout .. " " .. tostring(block.labels[t])

								if v.offset then
									if not block.constants[t] then
										block.reloc[#block.reloc + 1] = v.offset
									end
								end
							elseif block.extern[t] then
								lout = lout .. " " .. t
							else
								lerror(v, t .. " is not a symbol")
								return false
							end
						end
					end
				end

				v:replace(lout)
			end
		end
	end

	return true
end

function asm.binary(block, lex)
	local header = "TECUXELE"

	local code = ""
	local codesize = 0

	local function addByte(byte)
		code = code .. string.char(byte)

		codesize = codesize + 1
	end

	local function addInt(int)
		local u1, u2 = splitInt16(int)

		code = code .. string.char(u2) .. string.char(u1)

		codesize = codesize + 2
	end

	local function addLong(long)
		local u1, u2, u3, u4 = splitInt32(long)

		code = code .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		codesize = codesize + 4
	end

	local strtab = ""
	local strtabsize = 0

	local function addString(contents)
		local off = strtabsize

		strtab = strtab .. contents .. string.char(0)

		strtabsize = strtabsize + #contents + 1

		return off
	end

	local symtab = ""
	local symtabsize = 0

	local function addSymbol(name, value)
		local off = symtabsize

		local nameoff = addString(name)

		local u1, u2, u3, u4 = splitInt32(nameoff)
		symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		u1, u2, u3, u4 = splitInt32(value)
		symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		symtabsize = symtabsize + 8

		return off
	end

	local reloctab = ""
	local reloctabsize = 0
	
	local function addRelocation(addr)
		local off = reloctabsize

		local u1, u2, u3, u4 = splitInt32(addr)
		reloctab = reloctab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		reloctabsize = reloctabsize + 4

		return off
	end

	local fixuptab = ""
	local fixuptabsize = 0

	local function addFixup(name)
		local off = fixuptabsize

		local nameoff = addString(name)

		local u1, u2, u3, u4 = splitInt32(nameoff)
		fixuptab = fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		u1, u2, u3, u4 = splitInt32(codesize)
		fixuptab = fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		fixuptabsize = fixuptabsize + 8

		return off
	end

	if lex then
		for k,v in ipairs(block.reloc) do
			addRelocation(v)
		end

		for k,v in pairs(block.globals) do
			addSymbol(k, v)
		end
	end

	for k,v in ipairs(block.lines) do
		if v.text then
			local tokens = tokenize(v.text)

			local word = tokens[1]

			if word == ".static" then
				code = code .. v.static
				codesize = codesize + v.staticsize
			elseif word == ".db" then
				for i = 2, #tokens do
					local e = tokens[i]
					if tonumber(e) then
						addByte(tc(e))
					else
						lerror(v, "invalid bytelist")
						return false
					end
				end
			elseif word == ".di" then
				for i = 2, #tokens do
					local e = tokens[i]
					if tonumber(e) then
						addInt(tc(e))
					else
						lerror(v, "invalid intlist")
						return false
					end
				end
			elseif word == ".dl" then
				for i = 2, #tokens do
					local e = tokens[i]
					if tonumber(e) then
						addLong(tc(e))
					else
						lerror(v, "invalid longlist")
						return false
					end
				end
			elseif word == ".ds" then
				local contents = v.text:sub(5)
				code = code..contents
				codesize = codesize + #contents
			elseif word == ".bytes" then
				if (not tonumber(tokens[2])) or (not tonumber(tokens[3])) then
					lerror(v, "bad numbers on .bytes")
					return false
				end

				for i = 1, tonumber(tokens[2]) do
					addByte(tonumber(tokens[3]))
				end
			elseif word == ".fill" then
				if (not tonumber(tokens[2])) or (not tonumber(tokens[3])) then
					lerror(v, "bad numbers on .fill")
					return false
				end

				if codesize > tonumber(tokens[2]) then
					lerror(v, ".fill tried to go to "..tokens[2]..", bytecount already at "..string.format("%x",codesize))
					return false
				elseif codesize == tonumber(tokens[2]) then

				else
					repeat
						addByte(tonumber(tokens[3]))
					until codesize == tonumber(tokens[2])
				end
			elseif word == ".bc" then
				if #tokens == 1 then
					print("bytecount: "..string.format("%x",codesize))
				elseif #tokens == 2 then
					if not tonumber(tokens[2]) then
						lerror(v, "strange .bc")
						return false
					end

					print("bytecount: "..string.format("%x",tokens[2]))
				end
			else
				local e = inst[word]

				addByte(e[2])

				local rands = e[3] -- the names 'rand, operand

				if #tokens-1 ~= #rands then
					lerror(v, "operand count mismatch: "..word.." wants "..tostring(#rands).." operands, "..tostring(#tokens-1).." given.")
					return false
				end

				for n,s in ipairs(rands) do
					local operand = tokens[n+1]
					if not tonumber(operand) then
						if not ((s == 4) and block.extern[operand]) then
							lerror(v, "malformed number "..operand)
							return false
						end
					end

					if s == 1 then
						addByte(tc(operand))
					elseif s == 2 then
						addInt(tc(operand))
					elseif s == 4 then
						if not tonumber(operand) then -- already checked to make sure its an extern
							if not lex then
								lerror(v, "can't leave hanging symbols in a flat binary")
								return false
							end

							addFixup(operand)
							addLong(0)
						else
							addLong(tc(operand))
						end
					end
				end
			end
		end
	end

	if lex then
		-- make header
		local size = 40
		-- symtaboff
		local u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + symtabsize
		-- symcount
		u1, u2, u3, u4 = splitInt32(symtabsize / 8)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		-- strtaboff
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + strtabsize
		-- reloctaboff
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + reloctabsize
		-- reloccount
		u1, u2, u3, u4 = splitInt32(reloctabsize / 4)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		-- fixuptaboff
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + fixuptabsize
		-- fixupcount
		u1, u2, u3, u4 = splitInt32(fixuptabsize / 8)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		-- codeoff
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		block.binary = header .. symtab .. strtab .. reloctab .. fixuptab .. code
	else
		block.binary = code
	end

	return true
end

function asm.assembleBlock(source, filename, arg)
	local block = {}

	block.lines = {}

	block.statics = {}

	block.basedir = getdirectory(filename)

	if not asm.lines(block, source, filename) then return false end

	if not asm.labels(block) then return false end

	if not asm.decode(block) then return false end

	if not asm.binary(block, (arg[3] ~= "-flat")) then return false end

	return block
end

function asm.assemble(source, filename, arg)
	local block = asm.assembleBlock(source, filename, arg)

	if not block then return false end

	return block.binary
end

return asm