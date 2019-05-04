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

local df = {}

local lexer = require(sd.."lexer")

-- only one pass: parser and code gen rolled into one cannoli
-- possibly bad design as it fucks up retargetability
-- but whatever :D

local iwords = {
	["procedure"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			print("unexpected "..name[2].." at procedure")
		end

		out:a(name[1]..":")

		df.cblock(out, stream, "end")

		out:a("ret")

		out.auto = {}
		out.auto._LAU = 6
		out.rauto = {}
	end,
	["return"] = function (out, stream)
		out:a("ret")
	end,
	["var"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			print("unexpected "..name[2].." at var")
		end

		local initv = stream:extract()

		if initv[2] ~= "number" then
			print("unexpected "..name[2].." at var")
		end

		out:newvar(name[1], initv[1])
	end,
	["asm"] = function (out, stream)
		local con = stream:extract()

		if (con[2] == "tag") and (con[1] == "preamble") then
			local str = stream:extract()

			out:ap(str[1])

			return
		end

		out:a(con[1])
	end,
	["while"] = function (out, stream)
		if stream:extract()[1] ~= "(" then
			print("malformed while")
		end

		local expr = out:asym()
		local o = out:asym()

		out:a(out:syms(expr)..":")

		df.cblock(out, stream, ")")

		out:a("popv r5, r0")
		out:a("cmpi r0, 0")
		out:a("be "..out:syms(o))

		out:wenter(o)

		df.cblock(out, stream, "end")

		out:wexit()

		out:a("b "..out:syms(expr))
		out:a(out:syms(o)..":")
	end,
	["break"] = function (out, stream)
		out:a("b "..out:syms(out.wc[#out.wc]))
	end,
	["if"] = function (out, stream)
		if stream:extract()[1] ~= "(" then
			print("malformed if")
		end

		local t = out:asym() -- true
		local f = out:asym() -- false

		-- expression block

		df.cblock(out, stream, ")")

		out:a("popv r5, r0")
		out:a("cmpi r0, 0")
		out:a("be "..out:syms(f))
		out:a(out:syms(t)..":")

		-- true block

		df.cblock(out, stream, "end")

		if stream:peek()[1] == "else" then
			stream:extract()

			local o = out:asym()
			out:a("b "..out:syms(o))

			out:a(out:syms(f)..":")

			-- else block

			df.cblock(out, stream, "end")

			out:a(out:syms(o)..":")
		else
			out:a(out:syms(f)..":")
		end
	end,
	["const"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			print("unexpected "..name[2].." at const")
		end

		local initv = stream:extract()

		if initv[2] ~= "number" then
			if initv[2] ~= "string" then
				print("unexpected "..name[2].." at const")
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
	end,
	["struct"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			print("unexpected "..name[2].." at struct")
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
					print("unexpected "..t[2].." inside struct, wanted number or const")
					break
				end
			end

			local n = stream:extract()

			if n[2] ~= "tag" then
				print("unexpected "..n[2].." inside struct, wanted tag")
				break
			end

			out:newconst(name[1].."_"..n[1], off)

			off = off + t[1]

			t = stream:extract()
		end

		out:newconst(name[1].."_SIZEOF", off)
	end,
	["table"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			print("unexpected "..name[2].." at table")
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
						print("unexpected "..fname[2].." at pointerof")
					end

					p = fname[1]

					tcad("	.dl "..tostring(p))
				else
					tcad("	.dl "..tostring(out.const[t[1]]))
				end
			elseif t[2] == "string" then
				local string = t[1]

				local s = out:newsym()
				out.ds = out.ds .. "	.ds "
				for i = 1, #string do
					local c = string:sub(i,i)
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
				print("unexpected "..t[2].." in table")
			end

			t = stream:extract()
		end

		out:d(tca)
	end,
	["auto"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			print("unexpected "..name[2].." at auto")
		end

		out:newauto(name[1])
	end,
	["pointerof"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			print("unexpected "..name[2].." at pointerof")
		end

		local p = 0

		p = name[1]

		out:a("li r0, "..tostring(p))
		out:a("pushv r5, r0")
	end,
	["bswap"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("bswap r0, r0")
		out:a("pushv r5, r0")
	end,
	["=="] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("andi r0, rf, 0x1") -- isolate eq bit in flag register
		out:a("pushv r5, r0")
	end,
	["~="] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("not rf, rf")
		out:a("andi r0, rf, 0x1") -- isolate eq bit in flag register
		out:a("pushv r5, r0")
	end,
	[">"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("rshi r0, rf, 0x1") -- isolate gt bit in flag register
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
	end,
	["<"] = function (out, stream) -- NOT FLAG:1 and NOT FLAG:0
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("not r1, rf")
		out:a("rshi r0, r1, 0x1") -- isolate gt bit in flag register
		out:a("andi r0, r0, 1")
		out:a("not rf, rf")
		out:a("and r0, r0, rf")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
	end,
	[">="] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("mov r0, rf")
		out:a("rshi rf, rf, 1") -- bitwise magic
		out:a("ior r0, r0, rf")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
	end,
	["<="] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("cmp r0, r1")
		out:a("not rf, rf")
		out:a("rshi r0, rf, 0x1") -- isolate gt bit in flag register
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
	end,
	["~"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("not r0, r0")
		out:a("pushv r5, r0")
	end,
	["~~"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("not r0, r0")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
	end,
	["|"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("ior r0, r0, r1")
		out:a("pushv r5, r0")
	end,
	["||"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("ior r0, r0, r1")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
	end,
	["&"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("and r0, r0, r1")
		out:a("pushv r5, r0")
	end,
	["&&"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("and r0, r0, r1")
		out:a("andi r0, r0, 1")
		out:a("pushv r5, r0")
	end,
	[">>"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("rsh r0, r0, r1")
		out:a("pushv r5, r0")
	end,
	["<<"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("lsh r0, r0, r1")
		out:a("pushv r5, r0")
	end,
	["dup"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("pushv r5, r0")
		out:a("pushv r5, r0")
	end,
	["swap"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("xch r0, r1")
		out:a("pushv r5, r0")
		out:a("mov r0, r1")
		out:a("pushv r5, r0")
	end,
	["drop"] = function (out, stream)
		out:a("popv r5, r0")
	end,
	["+"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("add r0, r1, r0")
		out:a("pushv r5, r0")
	end,
	["-"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("sub r0, r0, r1")
		out:a("pushv r5, r0")
	end,
	["*"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("mul r0, r1, r0")
		out:a("pushv r5, r0")
	end,
	["/"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("div r0, r0, r1")
		out:a("pushv r5, r0")
	end,
	["%"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("mod r0, r0, r1")
		out:a("pushv r5, r0")
	end,
	["["] = function (out, stream)
		df.cblock(out, stream, "]")

		local tab = stream:extract()

		if tab[2] ~= "tag" then
			print("unexpected "..tab[2].." at [")
		end

		out:a("popv r5, r0")
		out:a("muli r0, r0, 4")
		out:a("addi r0, r0, "..tab[1])
		out:a("pushv r5, r0")
	end,
	["("] = function (out, stream)
		local t = stream:extract()

		while t and (t[1] ~= ")") do
			t = stream:extract()
		end
	end,
	["ix"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("muli r0, r0, 4")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("add r0, r1, r0")
		out:a("pushv r5, r0")
	end,
	["gb"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("lrr.b r0, r0")
		out:a("pushv r5, r0")
	end,
	["gi"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("lrr.i r0, r0")
		out:a("pushv r5, r0")
	end,
	["@"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("lrr.l r0, r0")
		out:a("pushv r5, r0")
	end,
	["sb"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("srr.b r1, r0")
	end,
	["si"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("srr.i r1, r0")
	end,
	["!"] = function (out, stream)
		out:a("popv r5, r0")
		out:a("mov r1, r0")
		out:a("popv r5, r0")
		out:a("srr.l r1, r0")
	end,
	["buffer"] = function (out, stream)
		local name = stream:extract()

		if name[2] ~= "tag" then
			print("unexpected "..name[2].." at table")
		end

		local sz = stream:extract()

		if sz[2] ~= "number" then
			print("unexpected "..sz[2].." at buffer")
		end

		out.var[name[1]] = name[1]

		out:d(name[1]..":")
		out:d("	.bytes "..tostring(sz[1].." 0x0"))
	end,
}

local directives = {
	["include"] = function (out, stream, bd)
		local e = stream:extract()

		if e[2] ~= "string" then
			print("include paths should be strings")
			return
		end

		local f = io.open(bd..e[1])

		if not f then
			print("error opening "..e[1])
			return
		end

		stream:insert(f:read("*a").."\n")

		f:close()
	end,
}

local function ckeyc(out, stream, c, bd)
	if c == "#" then
		local d = stream:extract()[1]

		if directives[d] then
			directives[d](out, stream, bd)
		else
			print("unknown directive "..d)
		end
	elseif iwords[c] then
		iwords[c](out, stream, bd)
	end
end

local function cauto(out, stream, reg)
	local t = stream:extract()

	if t[2] ~= "keyc" then
		print("unexpected "..t[1].." after auto reference")
		return
	end

	if t[1] == "!" then
		out:a("popv r5, r0")
		out:a("mov r"..tostring(reg)..", r0")
	elseif t[1] == "@" then
		out:a("mov r0, r"..tostring(reg))
		out:a("pushv r5, r0")
	else
		print("unexpected "..t[2].." operator on auto reference")
	end
end

local function cword(out, stream, word)
	if iwords[word] then
		iwords[word](out, stream)
	elseif out.var[word] then
		out:a("li r0, "..word)
		out:a("pushv r5, r0")
	elseif out.const[word] then
		out:a("li r0, "..tostring(out.const[word]))
		out:a("pushv r5, r0")
	elseif out.auto[word] then
		cauto(out, stream, out.auto[word])
	else
		out:contextEnter()
		out:a("call "..word)
		out:contextExit()
	end
end

local function cnumber(out, stream, number)
	out:a("li r0, "..tostring(number))
	out:a("pushv r5, r0")
end

local function cstring(out, stream, string)
	local s = out:newsym()
	out.ds = out.ds .. "	.ds "
	for i = 1, #string do
		local c = string:sub(i,i)
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

	out:a("li r0, "..out:syms(s))
	out:a("pushv r5, r0")

	out.oc = out.oc + 1
end

function df.cblock(out, stream, endt)
	local bd = getdirectory(out.path)

	local t = stream:extract()

	while t do
		if t[1] == endt then
			break
		elseif t[2] == "keyc" then
			ckeyc(out, stream, t[1], bd)
		elseif t[2] == "tag" then -- word
			cword(out, stream, t[1])
		elseif t[2] == "number" then -- number
			cnumber(out, stream, t[1])
		elseif t[2] == "string" then -- string
			cstring(out, stream, t[1])
		end

		t = stream:extract()
	end
end

function df.compile(stream, out)
	df.cblock(out, stream, nil)
end

function df.c(src, path)
	local out = {}
	out.ds = ""
	out.as = ""

	out.oc = 0

	out.var = {}
	out.const = {}
	out.auto = {}
	out.auto._LAU = 6

	out.wc = {}

	out.rauto = {}

	local automax = 25

	out.path = path

	function out:wenter(o)
		out.wc[#out.wc + 1] = o
	end

	function out.wexit(o)
		table.remove(out.wc,#out.wc)
	end

	function out:contextEnter()
		for k,v in ipairs(out.rauto) do
			out:a("push r"..tostring(v))
		end
	end

	function out:contextExit()
		local rauto = reverse(out.rauto)

		for k,v in ipairs(rauto) do
			out:a("pop r"..tostring(v))
		end
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
			print("can't create new auto var "..name..": ran out of registers")
			return
		end

		out.auto[name] = out.auto._LAU
		out.rauto[#out.rauto + 1] = out.auto._LAU
		out.auto._LAU = out.auto._LAU + 1
	end

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

	local s = lexer.new(src, kc, whitespace)

	df.compile(s, out)

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

		i = i + 1

		if v == "pushv r5, r0" then
			if la == "popv r5, r0" then
				i = i + 1
			else
				out = out .. v .. "\n"
			end
		elseif v == "popv r5, r0" then
			if la == "pushv r5, r0" then
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