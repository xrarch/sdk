-- requires luajit for bit ops

lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol = bit.lshift, bit.rshift, bit.tohex, bit.arshift, bit.band, bit.bxor, bit.bor, bit.bnot, bit.ror, bit.rol


local codegen = {}

local cg = {}

local cproc

local function cerror(t, err)
	print(string.format("dragonc: cg-auc: %s:%d: %s", (t.file or "not specified"), (t.line or "not specified"), err))
end

local e_extern

local e_defproc

local bpushdown = {}

local cpushdown = {}

local dataoff = 0

local datainits = {}

local dsection = {}

function codegen.buffer(buffer)
	for name,value in pairs(buffer) do
		cg:data(name.." === "..tostring(dataoff))
		dataoff = dataoff + value

		dsection[name] = true
	end
end

function codegen.var(var)
	for name,value in pairs(var) do
		cg:data(name.." === "..tostring(dataoff))
		datainits[#datainits + 1] = {dataoff, value}
		dataoff = dataoff + 4

		dsection[name] = true
	end
end

local tsn = 0

function codegen.table(deftable)
	local strs = {}

	for name,detail in pairs(deftable) do
		cg:data(name.." === "..tostring(dataoff))

		if detail.count then
			dataoff = dataoff + (detail.count * 4)
		else
			for k,v in pairs(detail.words) do
				if (v.typ == "num") or (v.typ == "ptr") then
					datainits[#datainits + 1] = {dataoff, v.name}
					dataoff = dataoff + 4
				elseif v.typ == "str" then
					local n = "_df_sto_"..tostring(tsn)

					datainits[#datainits + 1] = {dataoff, n, true}

					dataoff = dataoff + 4

					strs[#strs + 1] = {v.name, n}

					tsn = tsn + 1
				end
			end
		end

		dsection[name] = true
	end

	for k,v in ipairs(strs) do
		codegen.string(v[1], v[2])
	end
end

function codegen.extern(extern, externconst)
	for name,v in pairs(extern) do
		cerror({}, "no externconsts or externs allowed in ucode")
		--cg:code(".extern "..name)
	end

	for name,v in pairs(externconst) do
		cerror({}, "no externconsts or externs allowed in ucode")
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
		cg:code("pop r0")
		cg:code("callr r0")
	end,
	["+="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l.l r2, r1")
		cg:code("add r0, r0, r2")
		cg:code("s.l r1, r0")
	end,
	["-="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l.l r2, r1")
		cg:code("sub r0, r2, r0")
		cg:code("s.l r1, r0")
	end,
	["*="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l.l r2, r1")
		cg:code("mul r0, r0, r2")
		cg:code("s.l r1, r0")
	end,
	["/="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l.l r2, r1")
		cg:code("div r0, r2, r0")
		cg:code("s.l r1, r0")
	end,
	["%="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l.l r2, r1")
		cg:code("mod r0, r2, r0")
		cg:code("s.l r1, r0")
	end,
	--["bswap"] = function (rn)
	--	cg:code("pop r0")
	--	cg:code("bswap r0, r0")
	--	cg:code("push r0")
	--end,
	["=="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("e r0, r1")
		cg:code("push rf")
	end,
	["~="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("ne r0, r1")
		cg:code("push rf")
	end,
	[">"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("g r0, r1")
		cg:code("push rf")
	end,
	["<"] = function (rn) -- NOT FLAG:1 and NOT FLAG:0
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l r0, r1")
		cg:code("push rf")
	end,
	[">="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("g r0, r1")
		cg:code("mov r2, rf")
		cg:code("e r0, r1")
		cg:code("or r2, r2, rf")
		cg:code("push r2")
	end,
	["<="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("l r0, r1")
		cg:code("mov r2, rf")
		cg:code("e r0, r1")
		cg:code("or r2, r2, rf")
		cg:code("push r2")
	end,
	["s>"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("gs r0, r1")
		cg:code("push rf")
	end,
	["s<"] = function (rn) -- NOT FLAG:1 and NOT FLAG:0
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("ls r0, r1")
		cg:code("push rf")
	end,
	["s>="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("gs r0, r1")
		cg:code("mov r2, rf")
		cg:code("e r0, r1")
		cg:code("or r2, r2, rf")
		cg:code("push r2")
	end,
	["s<="] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("ls r0, r1")
		cg:code("mov r2, rf")
		cg:code("e r0, r1")
		cg:code("or r2, r2, rf")
		cg:code("push r2")
	end,
	["~"] = function (rn)
		cg:code("pop r0")
		cg:code("not r0, r0")
		cg:code("push r0")
	end,
	["~~"] = function (rn)
		cg:code("pop r0")
		cg:code("not r0, r0")
		cg:code("li r1, 1")
		cg:code("and r0, r0, r1")
		cg:code("push r0")
	end,
	["|"] = function (rn)
		cg:code("pop r0")
		cg:code("pop r1")
		cg:code("or r0, r0, r1")
		cg:code("push r0")
	end,
	["||"] = function (rn)
		cg:code("pop r0")
		cg:code("pop r1")
		cg:code("or r0, r0, r1")
		cg:code("li r1, 1")
		cg:code("and r0, r0, r1")
		cg:code("push r0")
	end,
	["&"] = function (rn)
		cg:code("pop r0")
		cg:code("pop r1")
		cg:code("and r0, r0, r1")
		cg:code("push r0")
	end,
	["&&"] = function (rn)
		cg:code("pop r0")
		cg:code("pop r1")
		cg:code("and r0, r0, r1")
		cg:code("li r1, 1")
		cg:code("and r0, r0, r1")
		cg:code("push r0")
	end,
	[">>"] = function (rn)
		cg:code("pop r0")
		cg:code("pop r1")
		cg:code("rsh r0, r0, r1")
		cg:code("push r0")
	end,
	["<<"] = function (rn)
		cg:code("pop r0")
		cg:code("pop r1")
		cg:code("lsh r0, r0, r1")
		cg:code("push r0")
	end,
	["dup"] = function (rn)
		cg:code("dup")
	end,
	["swap"] = function (rn)
		cg:code("swap")
	end,
	["drop"] = function (rn)
		cg:code("drop")
	end,
	["+"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("add r0, r1, r0")
		cg:code("push r0")
	end,
	["-"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("sub r0, r0, r1")
		cg:code("push r0")
	end,
	["*"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("mul r0, r0, r1")
		cg:code("push r0")
	end,
	["/"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("div r0, r0, r1")
		cg:code("push r0")
	end,
	["%"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("mod r0, r0, r1")
		cg:code("push r0")
	end,
	["gb"] = function (rn)
		cg:code("pop r0")
		cg:code("l.b r0, r0")
		cg:code("push r0")
	end,
	["gi"] = function (rn)
		cg:code("pop r0")
		cg:code("l.i r0, r0")
		cg:code("push r0")
	end,
	["@"] = function (rn)
		cg:code("pop r0")
		cg:code("l.l r0, r0")
		cg:code("push r0")
	end,
	["sb"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("s.b r1, r0")
	end,
	["si"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("s.i r1, r0")
	end,
	["!"] = function (rn)
		cg:code("pop r1")
		cg:code("pop r0")
		cg:code("s.l r1, r0")
	end,
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

	-- a3x NCALLS

	["DevTreeWalk"] = function (rn)
		cg:code("a3x DevTreeWalk")
	end,
	["DeviceParent"] = function (rn)
		cg:code("a3x DeviceParent")
	end,
	["DeviceSelectNode"] = function (rn)
		cg:code("a3x DeviceSelectNode")
	end,
	["DeviceSelect"] = function (rn)
		cg:code("a3x DeviceSelect")
	end,
	["DeviceNew"] = function (rn)
		cg:code("a3x DeviceNew")
	end,
	["DeviceClone"] = function (rn)
		cg:code("a3x DeviceClone")
	end,
	["DeviceCloneWalk"] = function (rn)
		cg:code("a3x DeviceCloneWalk")
	end,
	["DSetName"] = function (rn)
		cg:code("a3x DSetName")
	end,
	["DAddMethod"] = function (rn)
		cg:code("a3x DAddMethod")
	end,
	["DSetProperty"] = function (rn)
		cg:code("a3x DSetProperty")
	end,
	["DGetProperty"] = function (rn)
		cg:code("a3x DGetProperty")
	end,
	["DGetMethod"] = function (rn)
		cg:code("a3x GetMethod")
	end,
	["DCallMethod"] = function (rn)
		cg:code("a3x DCallMethod")
	end,
	["DeviceExit"] = function (rn)
		cg:code("a3x DeviceExit")
	end,
	["DGetName"] = function (rn)
		cg:code("a3x DGetName")
	end,
	["Putc"] = function (rn)
		cg:code("a3x Putc")
	end,
	["Getc"] = function (rn)
		cg:code("a3x Getc")
	end,
	["Malloc"] = function (rn)
		cg:code("a3x Malloc")
	end,
	["Calloc"] = function (rn)
		cg:code("a3x Calloc")
	end,
	["Free"] = function (rn)
		cg:code("a3x Free")
	end,
	["Puts"] = function (rn)
		cg:code("a3x Puts")
	end,
	["Gets"] = function (rn)
		cg:code("a3x Gets")
	end,
	["Printf"] = function (rn)
		cg:code("a3x Printf")
	end,
	["DevIteratorInit"] = function (rn)
		cg:code("a3x DevIteratorInit")
	end,
	["DevIterate"] = function (rn)
		cg:code("a3x DevIterate")
	end,

	["code"] = function (rn)
		cg:code("push code")
	end,
	["data"] = function (rn)
		cg:code("push data")
	end,
	["slot"] = function (rn)
		cg:code("push slot")
	end,
}

local auto_ops = {
	["@"] = function (rn)
		cg:code("push "..rn)
	end,
	["!"] = function (rn)
		cg:code("pop "..rn)
	end,
	["+="] = function (rn)
		cg:code("pop r0")
		cg:code("add "..rn..", "..rn..", r0")
	end,
	["-="] = function (rn)
		cg:code("pop r0")
		cg:code("sub "..rn..", "..rn..", r0")
	end,
	["*="] = function (rn)
		cg:code("pop r0")
		cg:code("mul "..rn..", "..rn..", r0")
	end,
	["/="] = function (rn)
		cg:code("pop r0")
		cg:code("div "..rn..", "..rn..", r0")
	end,
	["%="] = function (rn)
		cg:code("pop r0")
		cg:code("mod "..rn..", "..rn..", r0")
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

		cg:code("pop r0")
		cg:code("li r1, 0")
		cg:code("e r0, r1")
		cg:code("bt "..nex)

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
	local out = "_df_wout_"..tostring(wnn)

	bpushdown[#bpushdown + 1] = out

	wnn = wnn + 1

	local loop = "_df_wloop_"..tostring(wnn)

	cpushdown[#cpushdown + 1] = loop

	wnn = wnn + 1

	cg:code(loop..":")

	codegen.block(wn.w.conditional)

	cg:code("pop r0")
	cg:code("li r1, 0")
	cg:code("e r0, r1")
	cg:code("bt "..out)

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
			if v.tag == "putnumber" then
				local i0 = band(v.name, 0xFFFF)
				local i1 = rshift(v.name, 16)

				cg:code("li r0, "..tostring(i0))

				if v.name > 0xFFFF then
					cg:code("lui r0, "..tostring(i1))
				end

				cg:code("push r0")
			elseif v.tag == "putextptr" then
				cerror(v, "a3x microcode doesn't support extern pointers (FIXME)")
				return false
			elseif v.tag == "putptr" then
				if dsection[v.name] then
					cg:code("push24 "..v.name)
					cg:code("pop r0")
					cg:code("add r0, r0, data")
					cg:code("push r0")
				else -- assume code
					cg:code("push24 "..v.name)
					cg:code("pop r0")
					cg:code("add r0, r0, code")
					cg:code("push r0")
				end
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

				cg:code("pop r0")
				cg:code("li r1, 4")
				cg:code("mul r0, r0, r1")
				cg:code("push24 "..v.tab.name)
				cg:code("pop r1")
				cg:code("add r0, r0, r1")
				cg:code("add r0, r0, data")
				cg:code("push r0")
			elseif v.tag == "if" then
				if not codegen.genif(v) then return false end
			elseif v.tag == "while" then
				if not codegen.genwhile(v) then return false end
			elseif v.tag == "asm" then
				if not codegen.asm(v) then return false end
			elseif v.tag == "putstring" then
				local sno = codegen.string(v.name)

				cg:code("push24 "..sno)
				cg:code("pop r0")
				cg:code("add r0, r0, code")
				cg:code("push r0")
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
		cg:code("rpush "..cproc.allocr[i])
	end
end

function codegen.restore()
	for i = #cproc.allocr, 1, -1 do
		cg:code("rpop "..cproc.allocr[i])
	end
end

function codegen.fret()
	for i = 1, #cproc.outo do
		cg:code("push "..cproc.outo[i])
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

	local ru = 6

	local inv = {}

	for _,name in ipairs(t.inputso) do
		if ru > 27 then
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
		if ru > 27 then
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
		if ru > 27 then
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
		cg:code("pop "..inv[i])
	end

	if not codegen.block(t.block) then return false end

	codegen.fret()

	return true
end

function codegen.aucinit()
	for k,v in ipairs(datainits) do
		cg:code("push24 "..tostring(v[2]))
		cg:code("push24 "..tostring(v[1]))
		cg:code("pop r0")
		cg:code("pop r1")
		if v[3] then
			cg:code("add r1, r1, code")
		end
		cg:code("add r0, r0, data")
		cg:code("s.l r0, r1")
	end

	cg:code("b UcodeStart")
end

function codegen.code(ast)
	codegen.aucinit()

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

	return codegen.opt(cg.c) .. "\n" .. cg.d
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