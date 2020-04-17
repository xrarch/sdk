-- code gen for the R216 powder toy cpu
-- very broken, and also terribly optimized, don't use

-- requires luajit for bit ops

lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol = bit.lshift, bit.rshift, bit.tohex, bit.arshift, bit.band, bit.bxor, bit.bor, bit.bnot, bit.ror, bit.rol


local codegen = {}

local cg = {}

local cproc

local function cerror(t, err)
	print(string.format("dragonc: cg-r216: %s:%d: %s", (t.file or "not specified"), (t.line or "not specified"), err))
end

local e_extern

local e_defproc

local bpushdown = {}

local cpushdown = {}

function codegen.buffer(buffer)
	for name,value in pairs(buffer) do
		cg:data(name..":")

		for i = 1, value do
			cg:data("\tdw 0")
		end
	end
end

function codegen.var(var)
	for name,value in pairs(var) do
		cg:data(name..":")

		cg:data("\tdw "..tostring(value))
	end
end

local tsn = 0

function codegen.table(deftable)
	local strs = {}

	for name,detail in pairs(deftable) do
		cg:data(name..":")

		if detail.count then
			for i = 1, detail.count do
				cg:data("\tdw 0")
			end
		else
			for k,v in pairs(detail.words) do
				if (v.typ == "num") or (v.typ == "ptr") then
					cg:data("\tdw "..tostring(v.name))
				elseif v.typ == "str" then
					local n = "_df_sto_"..tostring(tsn)

					cg:data("\tdw "..tostring(n))

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
		cerror({}, "no externconsts or externs allowed in r216")
		--cg:code(".extern "..name)
	end

	for name,v in pairs(externconst) do
		cerror({}, "no externconsts or externs allowed in r216")
		--cg:code(".extern "..name)
	end
end

function codegen.export(export)
	--for name,v in pairs(export) do
	--	cg:data(".global "..name)
	--end
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

local ccn = 0

local prim_ops = {
	["return"] = function (rn)
		codegen.fret()
	end,
	["break"] = function (rn)
		if #bpushdown == 0 then
			cerror(rn, "can't use break outside of a block")
			return true -- this is an error here, though errors are usually falsey, this is to make this big table a bit more concise by removing all the return trues
		end

		cg:code("jmp "..bpushdown[#bpushdown])
	end,
	["continue"] = function (rn)
		if #cpushdown == 0 then
			cerror(rn, "can't use continue outside of a loop")
			return true
		end

		cg:code("jmp "..cpushdown[#cpushdown])
	end,
	["Call"] = function (rn)
		codegen.pop("r1")

		cg:code("call r1")
	end,
	["+="] = function (rn)
		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("add [r1], r2")
	end,
	["-="] = function (rn)
		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("sub [r1], r2")
	end,
	["*="] = function (rn)
		error("todo")

		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l.l r2, r1")
		cg:code("mul r0, r0, r2")
		cg:code("s.l r1, r0")
	end,
	["/="] = function (rn)
		error("todo")

		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l.l r2, r1")
		cg:code("div r0, r2, r0")
		cg:code("s.l r1, r0")
	end,
	["%="] = function (rn)
		error("todo")

		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l.l r2, r1")
		cg:code("mod r0, r2, r0")
		cg:code("s.l r1, r0")
	end,
	["=="] = function (rn)
		local lbl = "._df_ccl_"..tostring(ccn)

		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("mov r3, 0")
		cg:code("cmp r1, r2")
		cg:code("jne "..lbl)
		cg:code("mov r3, 1")
		cg:code(lbl..":")

		codegen.push("r3")

		ccn = ccn + 1
	end,
	["~="] = function (rn)
		local lbl = "._df_ccl_"..tostring(ccn)

		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("mov r3, 0")
		cg:code("cmp r1, r2")
		cg:code("je "..lbl)
		cg:code("mov r3, 1")
		cg:code(lbl..":")

		codegen.push("r3")

		ccn = ccn + 1
	end,
	[">"] = function (rn)
		local lbl = "._df_ccl_"..tostring(ccn)

		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("mov r3, 0")
		cg:code("cmp r1, r2")
		cg:code("jng "..lbl)
		cg:code("mov r3, 1")
		cg:code(lbl..":")

		codegen.push("r3")

		ccn = ccn + 1
	end,
	["<"] = function (rn) -- NOT FLAG:1 and NOT FLAG:0
		local lbl = "._df_ccl_"..tostring(ccn)

		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("mov r3, 0")
		cg:code("cmp r1, r2")
		cg:code("jnl "..lbl)
		cg:code("mov r3, 1")
		cg:code(lbl..":")

		codegen.push("r3")

		ccn = ccn + 1
	end,
	[">="] = function (rn)
		local lbl = "._df_ccl_"..tostring(ccn)

		codegen.pop("r2")
		codegen.pop("r1")

		cg:code("mov r3, 0")
		cg:code("cmp r1, r2")
		cg:code("jnge "..lbl)
		cg:code("mov r3, 1")
		cg:code(lbl..":")

		codegen.push("r3")

		ccn = ccn + 1
	end,
	["<="] = function (rn)
		local lbl = "._df_ccl_"..tostring(ccn)

		codegen.pop("r2")
		codegen.pop("r1")

		cg:code("mov r3, 0")
		cg:code("cmp r1, r2")
		cg:code("jnle "..lbl)
		cg:code("mov r3, 1")
		cg:code(lbl..":")

		codegen.push("r3")

		ccn = ccn + 1
	end,
	["~"] = function (rn)
		codegen.pop("r1")

		cg:code("mov r2, 0xFFFF")
		cg:code("sub r2, r1")
		
		codegen.push("r2")
	end,
	["~~"] = function (rn)
		codegen.pop("r1")

		cg:code("mov r2, 0xFFFF")
		cg:code("sub r2, r1")
		cg:code("and r2, 1")
		
		codegen.push("r2")
	end,
	["|"] = function (rn)
		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("or r1, r2")
		
		codegen.push("r1")
	end,
	["||"] = function (rn)
		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("or r1, r2")
		cg:code("and r1, 1")

		codegen.push("r1")
	end,
	["&"] = function (rn)
		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("and r1, r2")
		
		codegen.push("r1")
	end,
	["&&"] = function (rn)
		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("and r1, r2")
		cg:code("and r1, 1")
		
		codegen.push("r1")
	end,
	[">>"] = function (rn)
		codegen.pop("r2")
		codegen.pop("r1")

		cg:code("shr r1, r2")
		
		codegen.push("r1")
	end,
	["<<"] = function (rn)
		codegen.pop("r2")
		codegen.pop("r1")

		cg:code("shl r1, r2")
		
		codegen.push("r1")
	end,
	["dup"] = function (rn)
		cg:code("mov r1, [r0]")
		codegen.push("r1")
	end,
	["swap"] = function (rn)
		cg:code("mov r1, [r0]")
		cg:code("mov r2, [r0+1]")
		cg:code("mov [r0], r2")
		cg:code("mov [r0+1], r1")
	end,
	["drop"] = function (rn)
		cg:code("add r0, 1")
	end,
	["+"] = function (rn)
		codegen.pop("r2")
		codegen.pop("r1")

		cg:code("add r1, r2")
		
		codegen.push("r1")
	end,
	["-"] = function (rn)
		codegen.pop("r2")
		codegen.pop("r1")

		cg:code("sub r1, r2")
		
		codegen.push("r1")
	end,
	["*"] = function (rn)
		error("todo")

		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("mul r0, r0, r1")
		cg:code("push r0")
	end,
	["/"] = function (rn)
		error("todo")

		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("div r0, r0, r1")
		cg:code("push r0")
	end,
	["%"] = function (rn)
		error("todo")

		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("mod r0, r0, r1")
		cg:code("push r0")
	end,
	["@"] = function (rn)
		codegen.pop("r1")

		cg:code("mov r1, [r1]")

		codegen.push("r1")
	end,
	["!"] = function (rn)
		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("mov [r1], r2")
	end,
	--[[
	["bitget"] = function (rn) -- (v bit -- bit)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("rsh r0, r0, r1")
		cg:code("li r1, 1")
		cg:code("and r0, r0, r1")
		cg:code("push r0")
	end,
	["bitset"] = function (rn) -- (v bit -- v)
		cg:code("pop r0")
		cg:code("pop r1")
		cg:code("bset r1, r1, r0")
		cg:code("push r1")
	end,
	["bitclear"] = function (rn) -- (v bit -- v)
		cg:code("pop r0")
		cg:code("pop r1")
		cg:code("bclr r1, r1, r0")
		cg:code("push r1")
	end,
	]]


	["R216bump"] = function (rn)
		codegen.pop("r1")

		cg:code("bump r1")
	end,
	["R216send"] = function (rn)
		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("send r1, r2")
	end,
	["R216recv"] = function (rn)
		codegen.pop("r1")
		codegen.pop("r2")

		cg:code("recv r1, r2")
	end,
	["R216wait"] = function (rn)
		cg:code("wait r1")

		codegen.push("r1")
	end,
}

local auto_ops = {
	["@"] = function (rn)
		codegen.push(rn)
	end,
	["!"] = function (rn)
		codegen.pop(rn)
	end,
	["+="] = function (rn)
		codegen.pop("r1")
		cg:code("add "..rn..", r1")
	end,
	["-="] = function (rn)
		codegen.pop("r1")
		cg:code("sub "..rn..", r1")
	end,
	["*="] = function (rn)
		error("todo")

		codegen.pop("r1")
		cg:code("mul "..rn..", r1")
	end,
	["/="] = function (rn)
		error("todo")

		codegen.pop("r1")
		cg:code("div "..rn..", r1")
	end,
	["%="] = function (rn)
		error("todo")

		codegen.pop("r1")
		cg:code("mod "..rn..", r1")
	end
}

local inn = 0

function codegen.genif(ifn)
	local out = "_df_ifout_"..tostring(inn)

	inn = inn + 1

	for k,v in ipairs(ifn.ifs) do
		local nex = "_df_ifnex_"..tostring(inn)

		inn = inn + 1

		codegen.block(v.conditional)

		codegen.pop("r1")

		cg:code("cmp r1, 0")
		cg:code("je "..nex)

		codegen.block(v.body)

		cg:code("jmp "..out)
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
	local out = "_df_wout_"..tostring(wnn)

	bpushdown[#bpushdown + 1] = out

	wnn = wnn + 1

	local loop = "_df_wloop_"..tostring(wnn)

	cpushdown[#cpushdown + 1] = loop

	wnn = wnn + 1

	cg:code(loop..":")

	codegen.block(wn.w.conditional)

	codegen.pop("r1")

	cg:code("cmp r1, 0")
	cg:code("je "..out)

	codegen.block(wn.w.body)

	cg:code("jmp "..loop)

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
	cg:dappend('\tdw "')

	for i = 1, #str do
		local c = str:sub(i,i)
		if c == "\n" then
			cg:data('"')
			cg:data("\tdw 0xA")
			cg:dappend('\t.dw "')
		else
			cg:dappend(c)
		end
	end
	cg:data('"')
	cg:data("\tdw 0x0")

	return sno
end

function codegen.block(t)
	local skip = 0

	for k,v in ipairs(t) do
		if skip > 0 then
			skip = skip - 1
		else
			if v.tag == "putnumber" then
				codegen.push(tostring(v.name))
			elseif v.tag == "putextptr" then
				cerror(v, "R216 backend can't make object files, externs aren't allowed")
				return false
			elseif v.tag == "putptr" then
				codegen.push(v.name)
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

				codegen.pop("r1")

				cg:code("add r1, "..v.tab.name)

				codegen.push("r1")
			elseif v.tag == "if" then
				if not codegen.genif(v) then return false end
			elseif v.tag == "while" then
				if not codegen.genwhile(v) then return false end
			elseif v.tag == "asm" then
				if not codegen.asm(v) then return false end
			elseif v.tag == "putstring" then
				local sno = codegen.string(v.name)

				codegen.push(sno)
			else
				cerror(v, "weird AST node "..(v.tag or "NULL"))
				return false
			end
		end
	end

	return true
end

function codegen.push(thing)
	cg:code("sub r0, 1")
	cg:code("mov [r0], "..thing)
end

function codegen.pop(into)
	cg:code("mov "..into..", [r0]")
	cg:code("add r0, 1")
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
		codegen.push(cproc.outo[i])
	end

	codegen.restore()

	cg:code("ret")
end

function codegen.procedure(t)
	cg:code(t.name..":")

	--if t.public then
	--	cg:code(".global "..t.name)
	--end

	cproc = {}
	cproc.proc = t
	cproc.autos = {}

	cproc.allocr = {}

	cproc.outo = {}

	local ru = 4

	local inv = {}

	for _,name in ipairs(t.inputso) do
		if ru > 11 then
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
		if ru > 11 then
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
		if ru > 11 then
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
		codegen.pop(inv[i])
	end

	if not codegen.block(t.block) then return false end

	codegen.fret()

	return true
end

function codegen.r2init()
	cg:code("mov sp, 0")
	cg:code("mov r0, 0x1FC0")
	cg:code("jmp Main")
end

function codegen.code(ast)
	codegen.r2init()

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
		--cg:code("%define "..k.." "..tostring(v))
	end
end

function codegen.gen(ast, extern, externconst, var, deftable, export, defproc, buffer, const)
	if not ast then return false end

	e_extern = extern

	e_defproc = defproc

	cg.c = ""
	cg.d = ""

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

	codegen.const(const)

	codegen.extern(extern, externconst)

	codegen.data(var, deftable, buffer)

	if not codegen.code(ast) then return false end

	codegen.export(export)

	-- TODO: optimization
	return cg.c .. "\n" .. cg.d
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
	return s:sub(1,5) == "push "
end

local function ispopv(s)
	return s:sub(1,4) == "pop " 
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

		local vr = vt[2] or "HMM"
		local ar = at[2] or "HMMM"

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
		else
			out = out .. v .. "\n"
		end
	end

	return out
end

return codegen