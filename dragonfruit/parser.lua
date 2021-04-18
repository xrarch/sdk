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

local function node_t(kind, errtok, ident)
	local node = {}
	node.ident = ident
	node.kind = kind
	node.errtok = errtok
	return node
end

local parser = {}

local def = {}

local public = {}

local extern = {}

local structs = {}

local lex

local basedir

local stack

local currentfn

local incdir

local res

local function defined(ident, kind)
	local id = currentfn.def[ident] or def[ident]

	if id then
		if kind then
			if id.kind == kind then
				return id
			else
				return false
			end
		else
			return id
		end
	end

	return false
end

local function define(ident, kind, errtok, scoped, value)
	if ((ident == "argv") and (not scoped)) or (res[ident]) then
		lerror(errtok, ident.." is a reserved name")
		return false
	end

	local id = defined(ident)

	if id then
		-- if anyone asks i did not tell you it is okay to code like this
		if (not id.scoped) and scoped then

		elseif (kind == "fn") and (id.kind == "extern") then

		elseif (id.kind == "externconst") and ((kind == "table") or (kind == "buffer") or (kind == "var")) then

		else
			lerror(errtok, "can't define "..tostring(ident).." twice")
			return false
		end
	end

	local d = {}
	d.ident = ident
	d.kind = kind
	d.errtok = errtok
	d.value = value
	d.scoped = scoped

	if scoped then
		currentfn.def[ident] = d
		currentfn.idef[#currentfn.idef + 1] = d
	else
		def[ident] = d
	end

	return id or true
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

		local qd = basedir

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
			f = io.open(basedir.."/"..incpath)
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

-- parses the form { ... in1 in2 in3 -- out1 out2 out3 }
-- { in1 ... -- } is not allowed, { ... in1 -- } is.
function parser.signature(extern, fnptr)
	local sig = {}

	sig.varin = false
	sig.varout = false

	sig.fin = {}
	sig.out = {}

	sig.public = true

	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	sig.errtok = t

	if t[1] == "private" then
		if extern or fnptr then
			lerror(t, "extern or fnptr can't be declared as private (they are inherently private)")
			return false
		end

		sig.public = false

		t, ok = lex:expect("tag")

		if not ok then
			lerror(t, "expected tag, got "..t[2])
			return false
		end
	end

	sig.name = t[1]

	sig.ident = t[1]

	t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	if t[1] ~= "{" then
		lerror(t, "malformed function declaration")
		return false
	end

	t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "malformed function declaration")
		return false
	end

	while t[1] ~= "--" do
		if t[1] == "..." then
			if (not sig.varin) and (#sig.fin == 0) then
				sig.varin = true
			else
				lerror(t, "malformed function declaration: '...' can only be the first argument")
				return false
			end
		else
			if (not extern) and (not fnptr) then
				if not define(t[1], "auto", t, true) then
					return false
				end

				currentfn.autos[#currentfn.autos + 1] = t[1]
			end

			sig.fin[#sig.fin + 1] = t[1]
		end

		t, ok = lex:expect("tag")

		if not ok then
			lerror(t, "malformed function declaration")
			return false
		end
	end

	t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "malformed function declaration")
		return false
	end

	while t[1] ~= "}" do
		if t[1] == "..." then
			lerror(t, "varout not allowed")
			return false
		else
			if (not extern) and (not fnptr) then
				if not define(t[1], "auto", t, true) then
					return false
				end

				currentfn.autos[#currentfn.autos + 1] = t[1]
			end

			sig.out[#sig.out + 1] = t[1]
		end

		t, ok = lex:expect("tag")

		if not ok then
			lerror(t, "malformed function declaration")
			return false
		end
	end

	function sig.compare(sig2, allowpubdiff)
		if (not allowpubdiff) and (sig.name ~= sig2.name) then
			return false
		end

		if (not allowpubdiff) and (sig.public ~= sig2.public) then
			return false
		end

		if sig.varin ~= sig2.varin then
			return false
		end

		for k,v in ipairs(sig.fin) do
			if sig2.fin[k] ~= v then
				return false
			end
		end

		for k,v in ipairs(sig.out) do
			if sig2.out[k] ~= v then
				return false
			end
		end

		return true
	end

	return sig
end

function parser.extern()
	local sig = parser.signature(true)

	if not sig then
		return false
	end

	if not define(sig.name, "extern", sig.errtok, false, sig) then
		return false
	end

	extern[sig.name] = true

	return true
end

function parser.fnptr()
	local sig = parser.signature(false, true)

	if not sig then
		return false
	end

	if not define(sig.name, "fnptr", sig.errtok, false, sig) then
		return false
	end

	return true
end

local function defauto(name, tok)
	if not define(name, "auto", tok, true) then
		return false
	end

	currentfn.autos[#currentfn.autos + 1] = name

	return true
end

function parser.auto()
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	if not defauto(t[1], t) then
		return false
	end

	return true
end

local function pconbody(name)
	local t, ok = lex:expect("keyc")

	if not ok then
		lerror(t, "malformed "..name.." statement")
		return false
	end

	if t[1] ~= "(" then
		lerror(t, "malformed conditional")
		return false
	end

	local ast = node_t(name.."_cb", lex:peek())

	ast.conditional = parser.block(")")

	if not ast.conditional then return false end

	if name == "while" then
		currentfn.wdepth = currentfn.wdepth + 1
	end

	ast.body = parser.block("end")

	if name == "while" then
		currentfn.wdepth = currentfn.wdepth - 1
	end

	if not ast.body then return false end

	return ast
end

function parser.pif()
	local ast = node_t("if", lex:peek())

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

	if peek and (peek[1] == "else") then
		lex:extract()

		ast.default = parser.block("end")

		if not ast.default then return ast end
	end

	return ast
end

function parser.pwhile()
	local ast = node_t("while", lex:peek())

	ast.w = pconbody("while")

	if not ast.w then return false end

	return ast
end

function parser.pointerof()
	local ast = node_t("pointerof", lex:peek())

	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	ast.value = t[1]

	return ast
end

function parser.index()
	local ast = node_t("index", lex:peek())

	ast.block = parser.block("]")

	if not ast.block then return false end

	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	ast.name = t[1]

	return ast
end


function parser.block(endtok, defines)
	local ast = node_t("block", lex:peek())

	ast.defines = defines

	ast.block = {}

	local b = ast.block

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

			b[#b + 1] = pq
		elseif ident == "while" then
			local pq = parser.pwhile()

			if not pq then return false end

			b[#b + 1] = pq
		elseif ident == "auto" then
			if not parser.auto() then return false end
		elseif ident == "pointerof" then
			local pq = parser.pointerof()

			if not pq then return false end

			b[#b + 1] = pq
		elseif ident == "[" then
			local pq = parser.index()

			if not pq then return false end

			b[#b + 1] = pq
		else
			if (t[1] == "break") or (t[1] == "continue") then
				if currentfn.wdepth == 0 then
					lerror(t, "can't "..t[1].." outside of a loop")
					return false
				end
			end

			b[#b + 1] = node_t("lazy", t, t)
		end

		t = lex:extract()

		if not t then
			lerror(t, "unfinished block")
			return false
		end
	end

	return ast
end

function parser.fn(defonly)
	local mydef = {}
	local myautos = {}
	local myidef = {}
	currentfn = {}
	currentfn.def = mydef
	currentfn.autos = myautos
	currentfn.idef = myidef

	local fnptr

	local t = lex:peek()

	if t then -- dont deal with the reverse case t=nil, let parser.signature() print its error message
		if t[1] == "(" then
			lex:extract()

			local t, ok = lex:expect("tag")

			if not ok then
				lerror(t, "expected fnptr name, got "..t[2])
				return false
			end

			fnptr = defined(t[1], "fnptr")

			if not fnptr then
				lerror(t, t[1].." isn't a declared fnptr")
				return false
			end

			t, ok = lex:expect("keyc")

			if (not ok) or (t[1] ~= ")") then
				lerror(t, "expected )")
				return false
			end
		end
	end

	local sig = parser.signature(false)

	if not sig then
		return false
	end

	local ast = node_t("fn", sig.errtok, sig.name)

	local extdef = defined(sig.name, "extern")

	if (extdef) and (not sig.compare(extdef.value)) then
		lerror(sig.errtok, "function declaration doesn't match previous extern declaration")
		return false
	end

	if (fnptr) and (not sig.compare(fnptr.value, true)) then
		lerror(sig.errtok, "function declaration doesn't match fnptr prototype")
		return false
	end

	if not define(sig.name, "fn", sig.errtok, false, ast) then
		return false
	end

	ast.fin = sig.fin
	ast.out = sig.out
	ast.public = sig.public
	ast.varin = sig.varin

	ast.def = mydef
	ast.autos = myautos
	ast.idef = myidef

	ast.wdepth = 0

	currentfn = ast

	if ast.varin then
		if not defauto("argc", sig.errtok) then
			return false
		end

		if not define("argv", "table", sig.errtok, true, {}) then
			return false
		end
	end

	ast.block = parser.block("end")

	if not ast.block then
		return false
	end

	return ast
end

function parser.constant(poa, str, noblock)
	local t = lex:extract()

	if not t then return false end

	if t[2] == "number" then
		return t[1], "num", t
	end

	if (t[2] == "string") and (str) then
		return t[1], "str", t
	end

	if t[2] == "tag" then
		if t[1] == "pointerof" then
			if not poa then
				lerror(t, "pointerof not allowed here")
				return false
			end

			local n, ok = lex:expect("tag")

			if not ok then
				lerror(t, "expected tag, got "..t[2])
				return false
			end

			return n[1], "ptr", t
		end

		local c = defined(t[1], "const")
		if not c then
			lerror(t, "not a constant")
			return false
		end

		return c.value, "const", t
	end

	if t[1] == "(" then
		if noblock then
			lerror(t, "can't use complex constants here")
			return false
		end

		local ast = parser.block(")")

		if not ast then
			return false
		end

		return ast, "block", t
	end
	
	lerror(t, "strange constant")
	return false
end

function parser.def(kind, hasinit, conste)
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	local name = t[1]

	local initv = true

	local k

	if hasinit then
		initv, k = parser.constant()
		if not initv then return false end

		if (k == "block") and (conste) then
			initv.defines = name
		end
	end

	if not define(name, kind, t, false, initv) then
		return false
	end

	if kind == "externconst" then
		extern[name] = true
	end

	return true
end

function parser.table()
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	local name = t[1]

	local dte = {}

	if not define(name, "table", t, false, dte) then
		return false
	end

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
		local n, q, t = parser.constant(true, true)
		if not n then return false end

		dte.words[#dte.words + 1] = {["typ"]=q, ["name"]=n, ["errtok"]=t}

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
	local snt, ok = lex:expect("tag")

	if not ok then
		lerror(snt, "expected tag, got "..snt[2])
		return false
	end

	local name = snt[1]

	local t = lex:peek()

	if not t then
		lerror(t, "unfinished struct")
		return false
	end

	local struc = {}

	struc.name = name

	local szofblock = {}
	szofblock.block = {}

	if not define(name.."_SIZEOF", "const", t, false, szofblock) then
		return false
	end

	while t[1] ~= "endstruct" do
		local const, consttype, tok = parser.constant(nil, nil)

		if not const then
			return false
		end

		local n, ok = lex:expect("tag")

		if not ok then
			lerror(n, "expected tag, got "..n[1])
			return false
		end

		local cn = name.."_"..n[1]

		local v = {}
		v.block = {}

		if not define(name.."_"..n[1], "const", tok, false, v) then
			return false
		end

		struc[#struc + 1] = {tok=tok, size=const, valblock=v, name=cn}

		t = lex:peek()

		if not t then
			lerror(t, "unfinished struct")
			return false
		end
	end

	lex:extract()

	struc[#struc + 1] = {tok=snt, size=0, valblock=szofblock, name=name.."_SIZEOF"}

	structs[#structs + 1] = struc

	if not define(name, "struct", snt, false, struc) then
		return false
	end

	return true
end

function parser.public()
	local t, ok = lex:expect("tag")

	if not ok then
		lerror(t, "expected tag, got "..t[2])
		return false
	end

	local name = t[1]

	public[name] = t

	return true
end

function parser.asm()
	local t, ok = lex:expect("string")

	if not ok then
		lerror(t, "expected string, got "..t[2])
		return false
	end

	return t[1]
end

function parser.parse(lexer, sourcetext, filename, incd, reserve, cg)
	lex = lexer.new(sourcetext, filename)

	res = reserve

	incdir = incd

	if not lex then return false end

	basedir = getdirectory(filename)

	currentfn = {}
	currentfn.def = {}

	define("WORD", "const", nil, false, cg.wordsize)
	define("PTR", "const", nil, false, cg.ptrsize)

	local asms = {}

	local token = lex:extract()

	while token do
		local ident = token[1]

		if ident == "" then
			-- why doesnt lua 5.1 have a continue keyword
		elseif ident == "#" then
			if not parser.directive() then return false end
		elseif (ident == "fn") then
			if not parser.fn(true) then return false end
		elseif ident == "extern" then
			if not parser.extern() then return false end
		elseif ident == "fnptr" then
			if not parser.fnptr() then return false end
		elseif ident == "const" then
			if not parser.def("const", true, true) then return false end
		elseif ident == "externptr" then
			if not parser.def("externconst", false) then return false end
		elseif ident == "public" then
			if not parser.public() then return false end
		elseif ident == "var" then
			if not parser.def("var", true) then return false end
		elseif ident == "table" then
			if not parser.table() then return false end
		elseif ident == "buffer" then
			if not parser.def("buffer", true) then return false end
		elseif ident == "struct" then
			if not parser.struct() then return false end
		elseif ident == "asm" then
			local pq = parser.asm()

			if not pq then return false end

			asms[#asms + 1] = pq
		else
			lerror(token, "unexpected token: "..ident)
			return false
		end

		token = lex:extract()
	end

	return def, public, extern, structs, asms
end

return parser