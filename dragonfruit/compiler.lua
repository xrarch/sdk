local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

function reverse(l)
  local m = {}
  for i = #l, 1, -1 do table.insert(m, l[i]) end
  return m
end

local function lerror(token, err)
	print(string.format("dragonc: %s:%d: %s", token[4], token[3], err))
end

local df = {}

local lexer = dofile(sd.."lexer.lua")

-- only one pass: parser and code gen rolled into one cannoli
-- possibly bad design as it messes up retargetability
-- but whatever :D

local function compileif(out, stream, outsm)
	if stream:peek()[1] ~= "(" then
		lerror(stream:peek(), "malformed if")
		return false
	end

	stream:extract()

	local f = out:asym() -- false

	local outsym = outsm or out:asym()

	-- expression block

	if not df.cblock(out, stream, ")") then return false end

	out:a("popv r5, r0")
	out:a("cmpi r0, 0")
	out:a("be "..out:syms(f))

	-- true block

	df.cblock(out, stream, "end")

	local etok = stream:peek()[1]

	if (etok == "else") or (etok == "elseif") then
		stream:extract()

		out:a("b "..out:syms(outsym))

		out:a(out:syms(f)..":")

		-- else block

		if etok == "elseif" then
			if not compileif(out, stream, outsym) then return false end
		elseif etok == "else" then
			if not df.cblock(out, stream, "end") then return false end
		else
			error("you messed something up, call 911")
		end
	else
		out:a(out:syms(f)..":")
	end

	if not outsm then
		out:a(out:syms(outsym)..":")
	end

	return true
end

iwords = {
	["procedure"] = function (out, stream)
		local public = true

		if stream:peek()[1] == "private" then
			public = false
			stream:extract()
		end
	
		local name = stream:extract()

		if name[2] ~= "tag" then
			lerror(name, "unexpected "..name[2].." at procedure")
			return false
		end

		out:a(name[1]..":")

		if public then
			out:a(".global "..name[1])
		end

		out.outv = false

		if stream:peek()[1] == "{" then
			stream:extract()

			local outp = true
			local inv = {}

			out.outv = {}

			local t = stream:extract()

			while t do
				if t[1] == "}" then
					break
				end

				if outp then
					if t[1] == "--" then
						outp = false
					else
						if not out:newauto(t[1]) then
							lerror(t, "couldn't create input variable")
							return false
						end

						table.insert(inv, 1, out.auto[t[1]])
					end
				else
					if not out:newauto(t[1]) then
						lerror(t, "couldn't create output variable")
						return false
					end

					out.outv[#out.outv + 1] = out.auto[t[1]]
				end

				t = stream:extract()
			end

			for k,v in ipairs(inv) do
				out:a("popv r5, r"..tostring(v))
			end
		end

		df.cblock(out, stream, "end")

		out:exitF()

		out.pushed = false
		out.auto = {}
		out.auto._LAU = 6
		out.rauto = {}

		return true
	end,
	["return"] = function (out, stream)
		out:exitF()
		return true
	end,
	["var"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			lerror(name, "unexpected "..name[2].." at var")
			return false
		end

		local initv = stream:extract()

		if initv[2] ~= "number" then
			lerror(initv, "unexpected "..name[2].." at var")
			return false
		end

		out:newvar(name[1], initv[1])

		return true
	end,
	["asm"] = function (out, stream)
		local con = stream:extract()

		if (con[2] == "tag") and (con[1] == "preamble") then
			local str = stream:extract()

			out:ap(str[1])

			return true
		end

		out:a(con[1])

		return true
	end,
	["while"] = function (out, stream)
		out:autoMod()
	
		if stream:peek()[1] ~= "(" then
			lerror(stream:peek(), "malformed while")
			return false
		end

		stream:extract()

		local expr = out:asym()
		local o = out:asym()

		out:a(out:syms(expr)..":")

		if not df.cblock(out, stream, ")") then return false end

		out:a("popv r5, r0")
		out:a("cmpi r0, 0")
		out:a("be "..out:syms(o))

		out:wenter(o)

		if not df.cblock(out, stream, "end") then return false end

		out:wexit()

		out:a("b "..out:syms(expr))
		out:a(out:syms(o)..":")

		return true
	end,
	["break"] = function (out, stream)
		out:autoMod()
		out:a("b "..out:syms(out.wc[#out.wc]))
		return true
	end,
	["if"] = function (out, stream)
		out:autoMod()
		return compileif(out, stream)
	end,
	["const"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			lerror(name, "unexpected "..name[2].." at const")
			return false
		end

		local initv = stream:extract()

		if initv[2] ~= "number" then
			if initv[2] ~= "string" then
				lerror(initv, "unexpected "..name[2].." at const")
				return false
			else
				local s = out:newsym()
				out.ds = out.ds .. "	.ds "
				for i = 1, #initv[1] do
					local c = initv[1]:sub(i,i)
					if c == "\n" then
						out.ds = out.ds .. "\n"
						out:d("	.db 0xA")
						out.ds = out.ds .. "	.ds "
					else
						out.ds = out.ds .. c
					end
				end
				out:d("")
				out:d("	.db 0x0")

				initv[1] = out:syms(s)
			end
		end

		out:newconst(name[1], initv[1])

		return true
	end,
	["struct"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			lerror(name, "unexpected "..name[2].." at struct")
			return false
		end

		local t = stream:extract()
		local off = 0

		while t do
			if t[1] == "endstruct" then
				break
			end

			if t[2] ~= "number" then
				if (t[2] == "tag") and out.const[t[1]] then
					t[1] = out.const[t[1]]
				else
					lerror(t, "unexpected "..t[2].." inside struct, wanted number or const")
					return false
				end
			end

			local n = stream:extract()

			if n[2] ~= "tag" then
				lerror(n, "unexpected "..n[2].." inside struct, wanted tag")
				return false
			end

			out:newconst(name[1].."_"..n[1], off)

			off = off + t[1]

			t = stream:extract()
		end

		out:newconst(name[1].."_SIZEOF", off)

		return true
	end,
	["table"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			lerror(name, "unexpected "..name[2].." at table")
			return false
		end

		out.var[name[1]] = name[1]

		local t = stream:extract()

		local tca = ""

		local function tcad(e)
			tca = tca .. e .. "\n"
		end

		tcad(name[1]..":")

		while t do
			if t[1] == "endtable" then
				break
			end

			if t[2] == "number" then
				tcad("	.dl "..tostring(t[1]))
			elseif t[2] == "tag" then
				if t[1] == "pointerof" then
					local fname = stream:extract()

					if fname[2] ~= "tag" then
						lerror(fname, "unexpected "..fname[2].." at pointerof")
						return false
					end

					p = fname[1]

					tcad("	.dl "..tostring(p))
				else
					tcad("	.dl "..tostring(out.const[t[1]]))
				end
			elseif t[2] == "string" then
				local str = t[1]

				local s = out:newsym()
				out.ds = out.ds .. "	.ds "
				for i = 1, #str do
					local c = str:sub(i,i)
					if c == "\n" then
						out.ds = out.ds .. "\n"
						out:d("	.db 0xA")
						out.ds = out.ds .. "	.ds "
					else
						out.ds = out.ds .. c
					end
				end
				out:d("")
				out:d("	.db 0x0")

				tcad("	.dl "..out:syms(s))

				out.oc = out.oc + 1
			else
				lerror(t, "unexpected "..t[2].." in table")
				return false
			end

			t = stream:extract()
		end

		out:d(tca)

		return true
	end,
	["auto"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			lerror(name, "unexpected "..name[2].." at auto")
			return false
		end

		if iwords[name[1]] then
			lerror(name, "autos can't share a name with a iword: "..name[1])
			return false
		end

		if not out:newauto(name[1]) then
			lerror(name, "couldn't create auto " ..name[1])
			return false
		end

		return true
	end,
	["extern"] = function (out, stream)
		local symbol = stream:extract()

		if symbol[2] ~= "tag" then
			lerror(symbol, "unexpected "..symbol[2].." at extern")
			return false
		end

		out:a(".extern "..symbol[1])

		return true
	end,
	["externconst"] = function (out, stream)
		local symbol = stream:extract()

		if symbol[2] ~= "tag" then
			lerror(symbol, "unexpected "..symbol[2].." at extern")
			return false
		end

		out:a(".extern "..symbol[1])

		out.var[symbol[1]] = symbol[1]

		return true
	end,
	["public"] = function (out, stream)
		local symbol = stream:extract()

		if symbol[2] ~= "tag" then
			lerror(symbol, "unexpected "..symbol[2].." at public")
			return false
		end

		out:d(".global "..symbol[1])

		return true
	end,
	["pointerof"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			lerror(name, "unexpected "..name[2].." at pointerof")
			return false
		end

		local p = 0

		p = name[1]

		out:a("pushvi r5, "..tostring(p))

		return true
	end,
	["+="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("lrr.l r2, r1")
		out:a("add r0, r0, r2")
		out:a("srr.l r1, r0")
		return true
	end,
	["-="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("lrr.l r2, r1")
		out:a("sub r0, r0, r2")
		out:a("srr.l r1, r0")
		return true
	end,
	["*="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("lrr.l r2, r1")
		out:a("mul r0, r0, r2")
		out:a("srr.l r1, r0")
		return true
	end,
	["/="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("lrr.l r2, r1")
		out:a("div r0, r0, r2")
		out:a("srr.l r1, r0")
		return true
	end,
	["%="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("lrr.l r2, r1")
		out:a("mod r0, r0, r2")
		out:a("srr.l r1, r0")
		return true
	end,
	["bswap"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("bswap r0, r0")
		out:a("pushv r5, r0")
		return true
	end,
	["=="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("andi r0, rf, 0x1") -- isolate eq bit in flag register
		out:a("pushv r5, r0")
		return true
	end,
	["~="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("not rf, rf")
		out:a("andi r0, rf, 0x1") -- isolate eq bit in flag register
		out:a("pushv r5, r0")
		return true
	end,
	[">"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("rshi r0, rf, 0x1") -- isolate gt bit in flag register
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["<"] = function (out, stream) -- NOT FLAG:1 and NOT FLAG:0
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("not r1, rf")
		out:a("rshi r0, r1, 0x1") -- isolate gt bit in flag register
		out:a("andi r0, r0, 1")
		out:a("not rf, rf")
		out:a("and r0, r0, rf")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	[">="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("mov r0, rf")
		out:a("rshi rf, rf, 1") -- bitwise magic
		out:a("ior r0, r0, rf")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["<="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("not rf, rf")
		out:a("rshi r0, rf, 0x1") -- isolate gt bit in flag register
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["s>"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmps r0, r1")
		out:a("rshi r0, rf, 0x1") -- isolate gt bit in flag register
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["s<"] = function (out, stream) -- NOT FLAG:1 and NOT FLAG:0
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmps r0, r1")
		out:a("not r1, rf")
		out:a("rshi r0, r1, 0x1") -- isolate gt bit in flag register
		out:a("andi r0, r0, 1")
		out:a("not rf, rf")
		out:a("and r0, r0, rf")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["s>="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmps r0, r1")
		out:a("mov r0, rf")
		out:a("rshi rf, rf, 1") -- bitwise magic
		out:a("ior r0, r0, rf")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["s<="] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("cmps r0, r1")
		out:a("not rf, rf")
		out:a("rshi r0, rf, 0x1") -- isolate gt bit in flag register
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["~"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("not r0, r0")
		out:a("pushv r5, r0")
		return true
	end,
	["~~"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("not r0, r0")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["|"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("ior r0, r0, r1")
		out:a("pushv r5, r0")
		return true
	end,
	["||"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("ior r0, r0, r1")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["&"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("and r0, r0, r1")
		out:a("pushv r5, r0")
		return true
	end,
	["&&"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("and r0, r0, r1")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	[">>"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("rsh r0, r0, r1")
		out:a("pushv r5, r0")
		return true
	end,
	["<<"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("lsh r0, r0, r1")
		out:a("pushv r5, r0")
		return true
	end,
	["dup"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("pushv r5, r0")
		out:a("pushv r5, r0")
		return true
	end,
	["swap"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("popv r5, r1")
		out:a("pushv r5, r0")
		out:a("pushv r5, r1")
		return true
	end,
	["drop"] = function (out, stream)
		out:a("popv r5, r0")
		return true
	end,
	["+"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("add r0, r1, r0")
		out:a("pushv r5, r0")
		return true
	end,
	["-"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("sub r0, r0, r1")
		out:a("pushv r5, r0")
		return true
	end,
	["*"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("mul r0, r1, r0")
		out:a("pushv r5, r0")
		return true
	end,
	["/"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("div r0, r0, r1")
		out:a("pushv r5, r0")
		return true
	end,
	["%"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("mod r0, r0, r1")
		out:a("pushv r5, r0")
		return true
	end,
	["["] = function (out, stream)
		df.cblock(out, stream, "]")

		local tab = stream:extract()

		if tab[2] ~= "tag" then
			lerror(tab, "unexpected "..tab[2].." at [")
			return false
		end

		out:a("popv r5, r0")
		out:a("muli r0, r0, 4")
		out:a("addi r0, r0, "..tab[1])
		out:a("pushv r5, r0")
		return true
	end,
	["gb"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("lrr.b r0, r0")
		out:a("pushv r5, r0")
		return true
	end,
	["gi"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("lrr.i r0, r0")
		out:a("pushv r5, r0")
		return true
	end,
	["@"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("lrr.l r0, r0")
		out:a("pushv r5, r0")
		return true
	end,
	["sb"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("srr.b r1, r0")
		return true
	end,
	["si"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("srr.i r1, r0")
		return true
	end,
	["!"] = function (out, stream)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("srr.l r1, r0")
		return true
	end,
	["bitget"] = function (out, stream) -- (v bit -- bit)
		out:a("popv r5, r1")
		out:a("popv r5, r0")
		out:a("rsh r0, r0, r1")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
		return true
	end,
	["bitset"] = function (out, stream) -- (v bit -- v)
		out:a("popv r5, r0")
		out:a("popv r5, r1")
		out:a("bset r1, r1, r0")
		out:a("pushv r5, r1")
		return true
	end,
	["bitclear"] = function (out, stream) -- (v bit -- v)
		out:a("popv r5, r0")
		out:a("popv r5, r1")
		out:a("bclr r1, r1, r0")
		out:a("pushv r5, r1")
		return true
	end,
	["buffer"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			lerror(name, "unexpected "..name[2].." at buffer")
			return false
		end

		local sz = stream:extract()

		local rsz = sz[1]

		if sz[2] ~= "number" then
			if (sz[2] == "tag") and out.const[sz[1]] then
				rsz = out.const[sz[1]]
			else
				lerror(sz, "unexpected "..sz[2].." at buffer")
				return false
			end
		end

		out.var[name[1]] = name[1]

		out:d(name[1]..":")
		out:d("	.bytes "..tostring(rsz.." 0x0"))

		return true
	end,
}

local directives = {
	["include"] = function (out, stream, bd)
		local e = stream:extract()

		if e[2] ~= "string" then
			lerror(e, "include paths should be strings")
			return false
		end

		if e[1]:sub(1,5) == "<df>/" then
			bd = sd.."/runtime/include/"
			e[1] = e[1]:sub(6)
		elseif e[1]:sub(1,6) == "<inc>/" then
			if not out.incdir then
				lerror(e, "can't include relative to <inc>/ when no 'incdir=' option was given")
				return false
			end

			bd = out.incdir
			e[1] = e[1]:sub(7)
		end

		local f = io.open(bd..e[1])

		if not f then
			lerror(e, "error opening "..e[1])
			return false
		end

		stream:insertCurrent(f:read("*a"), e[1])

		f:close()

		return true
	end,
}

local function ckeyc(out, stream, c, bd)
	if c == "#" then
		local d = stream:extract()[1]

		if directives[d] then
			directives[d](out, stream, bd)
		else
			lerror(d, "unknown directive "..d)
			return false
		end
	elseif iwords[c] then
		if not iwords[c](out, stream, bd) then return false end
	end

	return true
end

local function cauto(out, stream, reg)
	local t = stream:extract()

	out:autoMod()

	if t[1] == "!" then
		out:a("popv r5, r"..tostring(reg))
	elseif t[1] == "@" then
		out:a("pushv r5, r"..tostring(reg))
	elseif t[1] == "+=" then
		out:a("popv r5, r0")
		out:a("add r"..tostring(reg)..", r"..tostring(reg)..", r0")
	elseif t[1] == "-=" then
		out:a("popv r5, r0")
		out:a("sub r"..tostring(reg)..", r"..tostring(reg)..", r0")
	elseif t[1] == "*=" then
		out:a("popv r5, r0")
		out:a("mul r"..tostring(reg)..", r"..tostring(reg)..", r0")
	elseif t[1] == "/=" then
		out:a("popv r5, r0")
		out:a("div r"..tostring(reg)..", r"..tostring(reg)..", r0")
	elseif t[1] == "%=" then
		out:a("popv r5, r0")
		out:a("mod r"..tostring(reg)..", r"..tostring(reg)..", r0")
	else
		lerror(t, "unexpected "..t[2].." operator on auto reference")
		return false
	end

	return true
end

local function cword(out, stream, word)
	if iwords[word] then
		if not iwords[word](out, stream) then return false end
	elseif out.var[word] then
		out:a("pushvi r5, "..word)
	elseif out.const[word] then
		out:a("pushvi r5, "..tostring(out.const[word]))
	elseif out.auto[word] then
		if not cauto(out, stream, out.auto[word]) then return false end
	else
		out:contextEnter()
		out:a("call "..word)
	end

	return true
end

local function cnumber(out, stream, number)
	out:a("pushvi r5, "..tostring(number))

	return true
end

local function cstring(out, stream, str)
	local s = out:newsym()
	out.ds = out.ds .. "	.ds "
	for i = 1, #str do
		local c = str:sub(i,i)
		if c == "\n" then
			out.ds = out.ds .. "\n"
			out:d("	.db 0xA")
			out.ds = out.ds .. "	.ds "
		else
			out.ds = out.ds .. c
		end
	end
	out:d("")
	out:d("	.db 0x0")

	out:a("pushvi r5, "..out:syms(s))

	return true
end

function df.cblock(out, stream, endt)
	local bd = getdirectory(out.path)

	local t = stream:extract()

	while t do
		if t[1] == endt then
			break
		elseif t[2] == "keyc" then
			if not ckeyc(out, stream, t[1], bd) then return false end
		elseif t[2] == "tag" then -- word
			if not cword(out, stream, t[1]) then return false end
		elseif t[2] == "number" then -- number
			if not cnumber(out, stream, t[1]) then return false end
		elseif t[2] == "string" then -- string
			if not cstring(out, stream, t[1]) then return false end
		end

		t = stream:extract()

		if (not t) and endt then
			lerror(t, "no matching "..endt)
			return false
		end
	end

	if endt then
		out:autoMod()
	end

	return true
end

function df.compile(stream, out)
	return df.cblock(out, stream, nil)
end

function df.c(src, path, incdir)
	local out = {}
	out.ds = ""
	out.as = ""

	out.oc = 0

	out.var = {}
	out.const = {}
	out.auto = {}
	out.auto._LAU = 6

	out.wc = {}

	out.outv = {}

	out.pushed = false

	out.rauto = {}

	out.incdir = incdir

	local automax = 25

	out.path = path

	function out:wenter(o)
		out.wc[#out.wc + 1] = o
	end

	function out.wexit(o)
		table.remove(out.wc,#out.wc)
	end

	out.rrauto = {}

	function out:contextEnter()
		if not out.pushed then
			for k,v in ipairs(out.rauto) do
				out:a("push r"..tostring(v))
			end
			out.pushed = true

			out.rrauto = reverse(out.rauto)
		end
	end

	function out:autoMod()
		if out.pushed then
			local rauto = out.rrauto

			for k,v in ipairs(rauto) do
				out:a("pop r"..tostring(v))
			end
			out.pushed = false
		end
	end

	function out:exitF()
		out:autoMod()

		if out.outv then
			for k,v in ipairs(out.outv) do
				out:a("pushv r5, r"..tostring(v))
			end
		end

		out:a("ret")
	end

	function out:d(str)
		self.ds = self.ds .. str .. "\n"
	end

	function out:a(str)
		self.as = self.as .. str .. "\n"
	end

	function out:ap(str)
		self.as = str .. "\n" .. self.as
	end

	function out:asym()
		local o = self.oc
		
		self.oc = o + 1

		return o
	end

	function out:newsym()
		self:d("_dc_o_"..tostring(self.oc)..":")

		return self:asym()
	end

	function out:syms(n)
		return "_dc_o_"..tostring(n)
	end

	function out:newvar(name, initv)
		self:d(name..":")
		self:d("	.dl "..tostring(initv))

		self.var[name] = name
	end

	function out:newconst(name, val)
		out:d(name.." === "..tostring(val))
		out.const[name] = val
	end

	function out:newauto(name)
		if out.auto._LAU >= automax then
			print("dragonc: can't create new auto var "..name..": ran out of registers")
			return false
		end

		if (out.auto[name]) then
			print("dragonc: can't create new auto var "..name..": already exists")
			return false
		end

		out.auto[name] = out.auto._LAU
		out.rauto[#out.rauto + 1] = out.auto._LAU
		out.auto._LAU = out.auto._LAU + 1

		return true
	end

	local s = lexer.new(src, path)

	if not s then return false end

	if not df.compile(s, out) then return false end

	return df.opt(out.as .. "\n" .. out.ds)
end

local function explode(d,p)
	local t, ll
	t={}
	ll=0
	if(#p == 1) then return {p} end
		while true do
			l=string.find(p,d,ll,true) -- find the next d in the string
			if l~=nil then -- if "not not" found then..
				table.insert(t, string.sub(p,ll,l-1)) -- Save it in our array.
				ll=l+1 -- save just after where we found it for searching next time.
			else
				table.insert(t, string.sub(p,ll)) -- Save what's left in our array.
				break -- Break at end, as it should be, according to the lua manual.
			end
		end
	return t
end

function tokenize(str)
	return explode(" ",str)
end

local function lineate(str)
	return explode("\n",str)
end

local function ispushv(s)
	return s:sub(1,10) == "pushv r5, "
end

local function ispopv(s)
	return s:sub(1,9) == "popv r5, " 
end

local function ispushvi(s)
	return s:sub(1,11) == "pushvi r5, "
end

-- extremely naive simple optimizer to straighten stack kinks
function df.opt(asm)
	local out = ""

	local lines = lineate(asm)

	local i = 1
	while true do
		local v = lines[i]

		if not v then
			break
		end

		local la = lines[i+1] or ""

		local vt = tokenize(v)
		local at = tokenize(la)

		local vr = vt[3] or "HMM"
		local ar = at[3] or "HMMM"

		i = i + 1

		if ispushv(v) then
			if ispopv(la) then
				if vr == ar then
					i = i + 1
				else
					out = out .. "mov " .. ar .. ", " .. vr .. "\n"
					i = i + 1
				end
			else
				out = out .. v .. "\n"
			end
		elseif ispopv(v) then
			if ispushv(la) then
				if vr == ar then
					out = out .. "lrr.l " .. vr .. ", r5\n"
					i = i + 1
				else
					out = out .. v .. "\n"
				end
			else
				out = out .. v .. "\n"
			end
		elseif ispushvi(v) then
			if ispopv(la) then
				out = out .. "li " .. ar .. ", " .. vr .. "\n"
				i = i + 1
			else
				out = out .. v .. "\n"
			end
		else
			out = out .. v .. "\n"
		end
	end

	return out
end

return df