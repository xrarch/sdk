-- recursive descent parser for dragonfruit

local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local function lerror(token, err)
	print(string.format("dragonc: parser: %s:%d: %s", token[4], token[3], err))
end

local function asthelp(name, errtok, tag)
	local ast = {}
	ast.tag = tag
	ast.name = name
	ast.line = errtok[3]
	ast.file = errtok[4]
	return ast
end

local parser = {}

local ast

local const

local extern

local externconst

local defproc

local var

local deftable

local export

local cproc

local defined

local structs

local bd

local lex

local incdir

function parser.asm()
	local t, ok = lex:expect("string")

	if not ok then
		lerror(t, "expected string, got "..t[2])
		return false
	end

	return asthelp(t[1], t, "asm")
end

function parser.directive()
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	local directive = t[1]

	if directive == "include" then
		t, ok = lex:expect("string")

		if not ok then
			lerror(t, "expected string, got "..t[2])
			return false
		end

		local incpath = t[1]

		local qd = bd

		local f

		if incpath:sub(1,5) == "<df>/" then
			f = io.open(sd.."/../headers/dfrt/"..incpath:sub(6), "r")
		elseif incpath:sub(1,5) == "<ll>/" then
			f = io.open(sd.."/../headers/"..incpath:sub(6), "r")
		elseif incpath:sub(1,6) == "<inc>/" then
			local rpath = incpath:sub(7)

			for _,path in ipairs(incdir) do
				f = io.open(path.."/"..rpath)

				if f then break end
			end
		else
			f = io.open(bd.."/"..incpath)
		end

		if not f then
			lerror(t, "couldn't include "..incpath)
			return false
		end

		lex:insertCurrent(f:read("*a"), incpath)

		f:close()
	else
		lerror(t, "unknown directive "..directive)
		return false
	end

	return true
end

local function pconbody(name)
	local t, ok = lex:expect("keyc")

	if not ok then
		lerror(t, "malformed "..name)
		return false
	end

	if t[1] ~= "(" then
		lerror(t, "malformed conditional")
		return false
	end

	local ast = {}

	ast.conditional = parser.block(")")

	if not ast.conditional then return false end

	ast.body = parser.block("end")

	if not ast.body then return false end

	return ast
end

function parser.pif()
	local ast = asthelp(nil, lex:peek(), "if")

	ast.ifs = {}

	ast.ifs[1] = pconbody("if")

	if not ast.ifs[1] then return false end

	local peek = lex:peek()

	if not peek then
		return ast
	end

	while peek[1] == "elseif" do
		lex:extract()

		ast.ifs[#ast.ifs + 1] = pconbody("if")

		peek = lex:peek()

		if not peek then
			return ast
		end
	end

	peek = lex:peek()

	if peek then
		if peek[1] == "else" then
			lex:extract()

			ast.default = parser.block("end")

			if not ast.default then return ast end
		end
	end

	return ast
end

function parser.pwhile()
	local ast = asthelp(nil, lex:peek(), "while")

	ast.w = pconbody("while")

	if not ast.w then return false end

	return ast
end

function parser.string(t)
	return asthelp(t[1], t, "putstring")
end

function parser.number(t)
	return asthelp(t[1], t, "putnumber")
end

function parser.word(t)
	local wc = t[1]

	if wc == "pointerof" then
		local e, ok = lex:expect("tag")

		if not ok then
			lerror(t, "expected tag, got "..e[2])
			return false
		end

		return asthelp(e[1], e, "putptr")
	elseif wc == "asm" then
		return parser.asm()
	end

	if const[wc] then
		return asthelp(const[wc], t, "putnumber")
	elseif externconst[wc] then
		return asthelp(wc, t, "putextptr")
	elseif (deftable[wc] or var[wc] or buffer[wc]) then
		return asthelp(wc, t, "putptr")
	elseif cproc.inputs[wc] then
		return asthelp(wc, t, "pinput")
	elseif cproc.outputs[wc] then
		return asthelp(wc, t, "poutput")
	elseif cproc.autos[wc] then
		return asthelp(wc, t, "pauto")
	else
		cproc.calls[wc] = true
		return asthelp(wc, t, "call")
	end
end

function parser.auto()
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	if not cproc then
		error("internal parser error, should never happen and may god save you")
	end

	if cproc.autos[t[1]] then
		lerror(t, "can't declare auto "..t[1].." twice")
		return false
	end

	cproc.autos[t[1]] = true

	return true
end

function parser.index()
	local ast = asthelp(nil, lex:peek(), "index")

	ast.block = parser.block("]")

	if not ast.block then return false end

	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	if deftable[t[1]] then
		ast.tab = deftable[t[1]]
	else
		ast.tab = {}
		ast.tab.name = t[1]
	end

	return ast
end

function parser.block(endtok)
	local ast = {}

	local t = lex:extract()

	if not t then
		lerror(t, "no block")
		return false
	end

	while t[1] ~= endtok do
		local ident = t[1]

		if ident == "if" then
			local pq = parser.pif()

			if not pq then return false end

			ast[#ast + 1] = pq
		elseif ident == "while" then
			local pq = parser.pwhile()

			if not pq then return false end

			ast[#ast + 1] = pq
		elseif ident == "auto" then
			if not parser.auto() then return false end
		elseif ident == "[" then
			local pq = parser.index()

			if not pq then return false end

			ast[#ast + 1] = pq
		elseif t[2] == "string" then
			local pq = parser.string(t)

			if not pq then return false end

			ast[#ast + 1] = pq
		elseif t[2] == "number" then
			local pq = parser.number(t)

			if not pq then return false end

			ast[#ast + 1] = pq
		elseif (t[2] == "tag") or (t[2] == "keyc") then
			local pq = parser.word(t)

			if not pq then return false end

			ast[#ast + 1] = pq
		else
			lerror(t, "unexpected "..t[2])
			return false
		end

		t = lex:extract()

		if not t then
			lerror(t, "unfinished block")
			return false
		end
	end

	return ast
end

function parser.procedure()
	local public = true

	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	if t[1] == "private" then
		public = false

		t, ok = lex:expect("tag")

		if not ok then
			lerror(t, "expected tag, got "..t[2])
			return false
		end
	end

	local name = t[1]

	if defproc[name] then
		lerror(t, "attempt to define procedure "..name.." twice")
		return false
	end

	local ast = asthelp(name, t, "procedure")

	cproc = ast

	ast.calls = {}

	ast.public = public
	ast.inputs = {}
	ast.outputs = {}
	ast.autos = {}

	ast.inputso = {}
	ast.outputso = {}

	local d = {}

	local peek = lex:peek()
	if peek then
		if peek[1] == "{" then
			lex:extract()

			t = lex:extract()

			local switched, vec, veco = false, ast.inputs, ast.inputso

			while t do
				if t[1] == "}" then
					break
				elseif t[1] == "--" then
					if not switched then
						switched = true
						vec = ast.outputs
						veco = ast.outputso
					else
						lerror(t, "malformed procedure IO list")
						return false
					end
				else
					if d[t[1]] then
						lerror(t, "cannot define "..t[1].." twice")
						return false
					end

					vec[t[1]] = true
					veco[#veco + 1] = t[1]
					d[t[1]] = true
				end

				t = lex:extract()
			end
		end
	else
		lerror(t, "malformed procedure")
		return false
	end

	ast.block = parser.block("end")

	if not ast.block then return false end

	defproc[name] = ast

	return ast
end

function parser.constant(poa, str)
	local t = lex:extract()

	if not t then return false end

	if t[2] == "number" then
		return t[1], "num"
	end

	if (t[2] == "string") and (str) then
		return t[1], "str"
	end

	if t[2] ~= "tag" then
		lerror(t, "malformed constant")
		return false
	end

	local ok

	if (t[1] == "pointerof") and poa then
		t, ok = lex:expect("tag")

		if not ok then
			lerror(t, "expected tag, got "..t[2])
			return false
		end

		return t[1], "ptr"
	elseif const[t[1]] then
		return const[t[1]], "num"
	end
	
	lerror(t, "strange constant")
	return false
end

function parser.def(tab, init)
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	local name = t[1]

	local initv = true

	if init then
		initv = parser.constant()
		if not initv then return false end
	end

	if defined[name] then
		lerror(t, "cannot re-define "..name)
		return false
	end

	if (tab ~= extern) and (tab ~= externconst) then
		defined[name] = tab
	end

	tab[name] = initv

	return true
end

function parser.table()
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	local name = t[1]

	deftable[name] = {}

	local dte = deftable[name]

	dte.name = name

	local errtok = t

	local peek = lex:peek()
	if peek then
		if peek[1] == "[" then
			lex:extract()

			dte.count = parser.constant()
			if not dte.count then return false end

			local g = true

			t = lex:extract()
			if t then
				if t[1] ~= "]" then
					g = false
				end
			else
				g = false
			end

			if not g then
				lerror(peek, "malformed table size")
				return false
			end
		end
	end

	if dte.count then -- easy table?
		return true
	end

	-- nope, complicated table

	dte.words = {}

	peek = lex:peek()

	if not t then
		lerror(errtok, "EOF before table contents defined")
		return false
	end

	while peek[1] ~= "endtable" do
		local n, q = parser.constant(true, true)
		if not n then return false end

		dte.words[#dte.words + 1] = {["typ"]=q, ["name"]=n}

		peek = lex:peek()

		if not peek then
			lerror(errtok, "unfinished table")
			return false
		end
	end

	lex:extract()

	return true
end

function parser.struct()
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	local name = t[1]

	local t = lex:peek()

	if not t then
		lerror(t, "unfinished struct")
		return false
	end

	local off = 0

	while t[1] ~= "endstruct" do
		local num = parser.constant()
		if not num then return false end

		local n, ok = lex:expect("tag")

		if not ok then
			lerror(n, "expected tag, got "..n[1])
			return false
		end

		const[name.."_"..n[1]] = off

		off = off + num

		t = lex:peek()

		if not t then
			lerror(t, "unfinished struct")
			return false
		end
	end

	lex:extract()

	const[name.."_SIZEOF"] = off

	return true
end

function parser.public()
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	local name = t[1]

	export[name] = true

	return true
end

function parser.parse(lexer, sourcetext, filename, idt)
	ast = {}

	const = {}

	extern = {}

	externconst = {}

	defproc = {}

	var = {}

	deftable = {}

	export = {}

	defined = {}

	buffer = {}

	incdir = idt

	lex = lexer.new(sourcetext, filename)

	if not lex then return false end

	bd = getdirectory(filename)

	local token = lex:extract()

	while token do
		local ident = token[1]

		if ident == "" then
			-- why doesnt lua 5.1 have a continue keyword
		elseif ident == "#" then
			if not parser.directive() then return false end
		elseif ident == "procedure" then
			local pq = parser.procedure()

			if not pq then return false end

			ast[#ast + 1] = pq
		elseif ident == "const" then
			if not parser.def(const, true) then return false end
		elseif ident == "extern" then
			if not parser.def(extern, false) then return false end
		elseif ident == "externconst" then
			if not parser.def(externconst, false) then return false end
		elseif ident == "public" then
			if not parser.public() then return false end
		elseif ident == "var" then
			if not parser.def(var, true) then return false end
		elseif ident == "table" then
			if not parser.table() then return false end
		elseif ident == "buffer" then
			if not parser.def(buffer, true) then return false end
		elseif ident == "struct" then
			if not parser.struct() then return false end
		elseif ident == "asm" then
			local pq = parser.asm()

			if not pq then return false end

			ast[#ast + 1] = pq
		else
			lerror(token, "unexpected token: "..ident)
			return false
		end

		token = lex:extract()
	end

	return ast, extern, externconst, var, deftable, export, defproc, buffer, const
end

return parser