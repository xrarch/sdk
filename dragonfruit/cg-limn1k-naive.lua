local codegen = {}

local cg = {}

local cproc

local function cerror(t, err)
	print(string.format("dragonc: cg-limn1k: %s:%d: %s", (t.file or "not specified"), (t.line or "not specified"), err))
end

local e_extern

local e_defproc

local bpushdown = {}

local cpushdown = {}

function codegen.buffer(buffer)
	for name,value in pairs(buffer) do
		cg:bss(name..":")
		cg:bss("\t.bytes "..tostring(value).." 0")
	end
end

function codegen.var(var)
	for name,value in pairs(var) do
		if value == 0 then
			cg:bss(name..":")
			cg:bss("\t.dl 0")
		else
			cg:data(name..":")
			cg:data("\t.dl "..value)
		end
	end
end

local tsn = 0

function codegen.table(deftable)
	local strs = {}

	for name,detail in pairs(deftable) do
		if detail.count then
			cg:bss(name..":")
			cg:bss("\t.bytes "..tostring(detail.count * 4).." 0")
		else
			cg:data(name..":")
			for k,v in pairs(detail.words) do
				if (v.typ == "num") or (v.typ == "ptr") then
					cg:data("\t.dl "..tostring(v.name))
				elseif v.typ == "str" then
					local n = "_df_sto_"..tostring(tsn)

					cg:data("\t.dl "..n)

					strs[#strs + 1] = {v.name, n}

					tsn = tsn + 1
				end
			end
		end
	end

	for k,v in ipairs(strs) do
		codegen.string(v[1], v[2])
	end
end

function codegen.extern(extern, externconst)
	for name,v in pairs(extern) do
		cg:code(".extern "..name)
	end

	for name,v in pairs(externconst) do
		cg:code(".extern "..name)
	end
end

function codegen.export(export)
	for name,v in pairs(export) do
		cg:bss(".global "..name)
	end
end

function codegen.data(var, deftable, buffer)
	codegen.var(var)
	codegen.table(deftable)
	codegen.buffer(buffer)
end

function codegen.asm(t)
	cg:code("\n"..t.name)

	return true
end

local cdummy = 0

local prim_ops = {
	["return"] = function (rn)
		codegen.fret()
	end,
	["break"] = function (rn)
		if #bpushdown == 0 then
			cerror(rn, "can't use break outside of a block")
			return true -- this is an error here, though errors are usually falsey, this is to make this big table a bit more concise by removing all the return trues
		end

		cg:code("b "..bpushdown[#bpushdown])
	end,
	["continue"] = function (rn)
		if #cpushdown == 0 then
			cerror(rn, "can't use continue outside of a loop")
			return true
		end

		cg:code("b "..cpushdown[#cpushdown])
	end,
	["Call"] = function (rn)
		cg:code("popv r5, r0")
		cg:code("pushi ._df_cleave_"..tostring(cdummy))
		cg:code("br r0")
		cg:code("._df_cleave_"..tostring(cdummy)..":")
		cdummy = cdummy + 1
	end,
	["+="] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("lrr.l r2, r1")
		cg:code("add r0, r0, r2")
		cg:code("srr.l r1, r0")
	end,
	["-="] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("lrr.l r2, r1")
		cg:code("sub r0, r2, r0")
		cg:code("srr.l r1, r0")
	end,
	["*="] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("lrr.l r2, r1")
		cg:code("mul r0, r0, r2")
		cg:code("srr.l r1, r0")
	end,
	["/="] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("lrr.l r2, r1")
		cg:code("div r0, r2, r0")
		cg:code("srr.l r1, r0")
	end,
	["%="] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("lrr.l r2, r1")
		cg:code("mod r0, r2, r0")
		cg:code("srr.l r1, r0")
	end,
	["bswap"] = function (rn)
		cg:code("popv r5, r0")
		cg:code("bswap r0, r0")
		cg:code("pushv r5, r0")
	end,
	["=="] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmp r0, r1")
		cg:code("andi r0, rf, 0x1") -- isolate eq bit in flag register
		cg:code("pushv r5, r0")
	end,
	["~="] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmp r0, r1")
		cg:code("not r0, rf")
		cg:code("andi r0, r0, 0x1") -- isolate eq bit in flag register
		cg:code("pushv r5, r0")
	end,
	[">"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmp r0, r1")
		cg:code("rshi r0, rf, 0x1") -- isolate carry bit in flag register
		cg:code("not r0, r0")
		cg:code("not r1, rf")
		cg:code("and r0, r0, r1")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["<"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmp r0, r1")
		cg:code("rshi r0, rf, 0x1") -- isolate carry bit in flag register
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	[">="] = function (rn) -- not carry
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmp r0, r1")
		cg:code("rshi r0, rf, 1")
		cg:code("not r0, r0")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["<="] = function (rn) -- carry or zero
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmp r0, r1")
		cg:code("rshi r1, rf, 1")
		cg:code("ior r0, rf, r1")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["s>"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmps r0, r1")
		cg:code("rshi r0, rf, 0x1") -- isolate carry bit in flag register
		cg:code("not r0, r0")
		cg:code("not r1, rf")
		cg:code("and r0, r0, r1")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["s<"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmps r0, r1")
		cg:code("rshi r0, rf, 0x1") -- isolate carry bit in flag register
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["s>="] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmps r0, r1")
		cg:code("rshi r0, rf, 1")
		cg:code("not r0, r0")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["s<="] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("cmps r0, r1")
		cg:code("rshi r1, rf, 1")
		cg:code("ior r0, rf, r1")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["~"] = function (rn)
		cg:code("popv r5, r0")
		cg:code("not r0, r0")
		cg:code("pushv r5, r0")
	end,
	["~~"] = function (rn)
		cg:code("popv r5, r0")
		cg:code("not r0, r0")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["|"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("ior r0, r0, r1")
		cg:code("pushv r5, r0")
	end,
	["||"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("ior r0, r0, r1")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["&"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("and r0, r0, r1")
		cg:code("pushv r5, r0")
	end,
	["&&"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("and r0, r0, r1")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	[">>"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("rsh r0, r0, r1")
		cg:code("pushv r5, r0")
	end,
	["<<"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("lsh r0, r0, r1")
		cg:code("pushv r5, r0")
	end,
	["dup"] = function (rn)
		cg:code("popv r5, r0")
		cg:code("pushv r5, r0")
		cg:code("pushv r5, r0")
	end,
	["swap"] = function (rn)
		cg:code("popv r5, r0")
		cg:code("popv r5, r1")
		cg:code("pushv r5, r0")
		cg:code("pushv r5, r1")
	end,
	["drop"] = function (rn)
		cg:code("popv r5, r0")
	end,
	["+"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("add r0, r1, r0")
		cg:code("pushv r5, r0")
	end,
	["-"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("sub r0, r0, r1")
		cg:code("pushv r5, r0")
	end,
	["*"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("mul r0, r1, r0")
		cg:code("pushv r5, r0")
	end,
	["/"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("div r0, r0, r1")
		cg:code("pushv r5, r0")
	end,
	["%"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("mod r0, r0, r1")
		cg:code("pushv r5, r0")
	end,
	["gb"] = function (rn)
		cg:code("popv r5, r0")
		cg:code("lrr.b r0, r0")
		cg:code("pushv r5, r0")
	end,
	["gi"] = function (rn)
		cg:code("popv r5, r0")
		cg:code("lrr.i r0, r0")
		cg:code("pushv r5, r0")
	end,
	["@"] = function (rn)
		cg:code("popv r5, r0")
		cg:code("lrr.l r0, r0")
		cg:code("pushv r5, r0")
	end,
	["sb"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("srr.b r1, r0")
	end,
	["si"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("srr.i r1, r0")
	end,
	["!"] = function (rn)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("srr.l r1, r0")
	end,
	["bitget"] = function (rn) -- (v bit -- bit)
		cg:code("popv r5, r1")
		cg:code("popv r5, r0")
		cg:code("rsh r0, r0, r1")
		cg:code("andi r0, r0, 1")
		cg:code("pushv r5, r0")
	end,
	["bitset"] = function (rn) -- (v bit -- v)
		cg:code("popv r5, r0")
		cg:code("popv r5, r1")
		cg:code("bset r1, r1, r0")
		cg:code("pushv r5, r1")
	end,
	["bitclear"] = function (rn) -- (v bit -- v)
		cg:code("popv r5, r0")
		cg:code("popv r5, r1")
		cg:code("bclr r1, r1, r0")
		cg:code("pushv r5, r1")
	end,

	["_flush"] = function (rn) end,
	["_flush_all"] = function (rn) end,
}

local auto_ops = {
	["@"] = function (rn)
		cg:code("pushv r5, "..rn)
	end,
	["!"] = function (rn)
		cg:code("popv r5, "..rn)
	end,
	["+="] = function (rn)
		cg:code("popv r5, r0")
		cg:code("add "..rn..", "..rn..", r0")
	end,
	["-="] = function (rn)
		cg:code("popv r5, r0")
		cg:code("sub "..rn..", "..rn..", r0")
	end,
	["*="] = function (rn)
		cg:code("popv r5, r0")
		cg:code("mul "..rn..", "..rn..", r0")
	end,
	["/="] = function (rn)
		cg:code("popv r5, r0")
		cg:code("div "..rn..", "..rn..", r0")
	end,
	["%="] = function (rn)
		cg:code("popv r5, r0")
		cg:code("mod "..rn..", "..rn..", r0")
	end,
}

local inn = 0

function codegen.genif(ifn)
	local out = "._df_ifout_"..tostring(inn)

	inn = inn + 1

	for k,v in ipairs(ifn.ifs) do
		local nex = "._df_ifnex_"..tostring(inn)

		inn = inn + 1

		codegen.block(v.conditional)

		cg:code("popv r5, r0")
		cg:code("cmpi r0, 0")
		cg:code("be "..nex)

		codegen.block(v.body)

		cg:code("b "..out)
		cg:code(nex..":")
	end

	if ifn.default then
		codegen.block(ifn.default)
	end

	cg:code(out..":")

	return true
end

local wnn = 0

function codegen.genwhile(wn)
	local out = "._df_wout_"..tostring(wnn)

	bpushdown[#bpushdown + 1] = out

	wnn = wnn + 1

	local loop = "._df_wloop_"..tostring(wnn)

	cpushdown[#cpushdown + 1] = loop

	wnn = wnn + 1

	cg:code(loop..":")

	codegen.block(wn.w.conditional)

	cg:code("popv r5, r0")
	cg:code("cmpi r0, 0")
	cg:code("be "..out)

	codegen.block(wn.w.body)

	cg:code("b "..loop)

	cg:code(out..":")

	bpushdown[#bpushdown] = nil

	cpushdown[#cpushdown] = nil

	return true
end

local snn = 0

function codegen.string(str, n)
	local sno = n or "_df_so_"..tostring(snn)

	snn = snn + 1

	cg:data(sno..":")
	cg:dappend("\t.ds ")

	for i = 1, #str do
		local c = str:sub(i,i)
		if c == "\n" then
			cg:data("")
			cg:data("\t.db 0xA")
			cg:dappend("\t.ds ")
		else
			cg:dappend(c)
		end
	end
	cg:data("")
	cg:data("\t.db 0x0")

	return sno
end

function codegen.block(t)
	local skip = 0

	for k,v in ipairs(t) do
		if skip > 0 then
			skip = skip - 1
		else
			if (v.tag == "putnumber") or (v.tag == "putextptr") or (v.tag == "putptr") then
				cg:code("pushvi r5, "..tostring(v.name))
			elseif (v.tag == "pinput") or (v.tag == "poutput") or (v.tag == "pauto") then
				local r = cproc.autos[v.name]

				if not r then
					cerror(v, "attempt to reference undeclared auto "..(v.name or "NULL"))
					return false
				end

				skip = 1

				local op = t[k+1]

				if not op then
					cerror(v, "operation required on auto")
					return false
				end

				if not auto_ops[op.name] then
					cerror(v, "operation "..(op.name or "NULL").." can't be used for autos")
					return false
				end

				auto_ops[op.name](r)
			elseif v.tag == "call" then
				if prim_ops[v.name] then
					if prim_ops[v.name](v) then return false end
				elseif (e_extern[v.name] or e_defproc[v.name]) then
					cg:code("call "..v.name)
				else
					cerror(v, "attempt to call undeclared procedure "..(v.name or "NULL"))
					return false
				end
			elseif v.tag == "index" then
				if not codegen.block(v.block) then return false end

				cg:code("popv r5, r0")
				cg:code("muli r0, r0, 4")
				cg:code("addi r0, r0, "..v.tab.name)
				cg:code("pushv r5, r0")
			elseif v.tag == "if" then
				if not codegen.genif(v) then return false end
			elseif v.tag == "while" then
				if not codegen.genwhile(v) then return false end
			elseif v.tag == "asm" then
				if not codegen.asm(v) then return false end
			elseif v.tag == "putstring" then
				local sno = codegen.string(v.name)

				cg:code("pushvi r5, "..sno)
			else
				cerror(v, "weird AST node "..(v.tag or "NULL"))
				return false
			end
		end
	end

	return true
end

function codegen.save()
	for i = 1, #cproc.allocr do
		cg:code("push "..cproc.allocr[i])
	end
end

function codegen.restore()
	for i = #cproc.allocr, 1, -1 do
		cg:code("pop "..cproc.allocr[i])
	end
end

function codegen.fret()
	for i = 1, #cproc.outo do
		cg:code("pushv r5, "..cproc.outo[i])
	end

	codegen.restore()

	cg:code("ret")
end

function codegen.procedure(t)
	cg:code(t.name..":")

	if t.public then
		cg:code(".global "..t.name)
	end

	cproc = {}
	cproc.proc = t
	cproc.autos = {}

	cproc.allocr = {}

	cproc.outo = {}

	local ru = 6

	local inv = {}

	for _,name in ipairs(t.inputso) do
		if ru > 29 then
			cerror(t, "couldn't allocate input "..name)
			return false
		end

		local rn = "r"..tostring(ru)

		table.insert(inv, 1, rn)

		cproc.autos[name] = rn

		cproc.allocr[#cproc.allocr + 1] = rn

		ru = ru + 1
	end

	for _,name in pairs(t.outputso) do
		if ru > 29 then
			cerror(t, "couldn't allocate output "..name)
			return false
		end

		local rn = "r"..tostring(ru)

		cproc.autos[name] = rn

		cproc.allocr[#cproc.allocr + 1] = rn

		cproc.outo[#cproc.outo + 1] = rn

		ru = ru + 1
	end

	for name,_ in pairs(t.autos) do
		if ru > 29 then
			cerror(t, "couldn't allocate auto "..name)
			return false
		end

		local rn = "r"..tostring(ru)

		cproc.autos[name] = rn

		cproc.allocr[#cproc.allocr + 1] = rn

		ru = ru + 1
	end

	codegen.save()

	for i = 1, #inv do
		cg:code("popv r5, "..inv[i])
	end

	if not codegen.block(t.block) then return false end

	codegen.fret()

	return true
end

function codegen.code(ast)
	for e,t in pairs(ast) do
		if t.tag == "procedure" then
			if not codegen.procedure(t) then return false end
		elseif t.tag == "asm" then
			if not codegen.asm(t) then return false end
		else
			cerror(t, "unknown AST tag "..(t.tag or "NULL"))
			return false
		end
	end

	return true
end

function codegen.const(const)
	for k,v in pairs(const) do
		cg:code(k.." === "..tostring(v))
	end
end

function codegen.gen(ast, extern, externconst, var, deftable, export, defproc, buffer, const)
	if not ast then return false end

	e_extern = extern

	e_defproc = defproc

	cg.c = ".section text\n"
	cg.d = ".section data\n"
	cg.b = ".section bss\n"

	function cg:code(code)
		cg.c = cg.c .. code .. "\n"
	end

	function cg:append(code)
		cg.c = cg.c .. code
	end

	function cg:data(data)
		cg.d = cg.d .. data .. "\n"
	end

	function cg:dappend(data)
		cg.d = cg.d .. data
	end

	function cg:bss(bss)
		cg.b = cg.b .. bss .. "\n"
	end

	function cg:bappend(bss)
		cg.b = cg.b .. bss
	end

	codegen.const(const)

	codegen.extern(extern, externconst)

	if not codegen.code(ast) then return false end

	codegen.data(var, deftable, buffer)

	codegen.export(export)

	return codegen.opt(cg.c) .. "\n" .. cg.d .. "\n" .. cg.b
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

local function tokenize(str)
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
function codegen.opt(asm)
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

return codegen