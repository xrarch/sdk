local function tprint (tbl, indent)
	if not indent then indent = 0 end
	for k, v in pairs(tbl) do
		formatting = string.rep("  ", indent) .. k .. ": "
		if type(v) == "table" then
			print(formatting)
			tprint(v, indent+1)
		elseif type(v) == 'boolean' then
			print(formatting .. tostring(v))      
		else
			print(formatting .. tostring(v))
		end
	end
end

local function lerror(token, err)
	print(string.format("dragonc: cg-limn2500: %s:%d: %s", token[4], token[3], err))
end

local cg = {}

cg.ptrsize = 4
cg.wordsize = 4

local textsection

local datasection

local bsssection

local defs

local curfn

local SAVEMAX = 18

local TEMPMAX = 5

local wpushdown = {}

local wcpushdown = {}

local function text(str)
	textsection = textsection .. str .. "\n"
end

local function atext(str)
	textsection = textsection .. str
end

local function data(str)
	datasection = datasection .. str .. "\n"
end

local function adata(str)
	datasection = datasection .. str
end

local function bss(str)
	bsssection = bsssection .. str .. "\n"
end

local function abss(str)
	bsssection = bsssection .. str
end

local labln

local function label()
	local s = "_DF_CG_"..tostring(labln)

	labln = labln + 1

	return s
end

local function locallabel()
	local s = ".L"..tostring(curfn.labln)

	curfn.labln = curfn.labln + 1

	return s
end

local strings = {}

local function cstring(str, n)
	if (not n) and strings[str] then
		return strings[str]
	end

	local sno = n or label()

	data(sno..":")
	adata('\t.ds "')

	for i = 1, #str do
		local c = str:sub(i,i)
		if c == "\n" then
			adata("\\n")
		else
			adata(c)
		end
	end
	data('\\0"')

	strings[str] = sno

	return sno
end

local function reg_t(id, typ, errtok, auto, muted)
	local r = {}

	if typ == "temp" then
		r.n = "t"..tostring(id)
	elseif typ == "save" then
		r.n = "s"..tostring(id)
	elseif typ == "arg" then
		r.n = "a"..tostring(id)
	elseif typ == "ret" then
		r.n = "a"..tostring(id)
	elseif typ == "tf" then
		error("oop")
	elseif typ == "sp" then
		r.n = "sp"
	end

	r.id = id
	r.typ = typ
	r.errtok = errtok
	r.auto = auto
	r.muted = muted

	r.kind = "reg"

	return r
end

local function getsaved(errtok, auto, muted)
	for i = 0, SAVEMAX do
		if not curfn.usedsave[i] then
			curfn.usedsave[i] = true

			if not curfn.saved[i] then
				curfn.saved[i] = true
				curfn.savedn = curfn.savedn + 1
			end

			return reg_t(i, "save", errtok, auto, muted)
		end
	end

	return false
end

-- try to alloc temp registers first
-- if save is true, force the use of a saved register
local function ralloc(errtok, save, auto, muted)
	local out = false

	if save then
		out = getsaved(errtok, auto, muted)
	else
		for i = 0, TEMPMAX do
			if not curfn.usedtemp[i] then
				curfn.usedtemp[i] = true
				out = reg_t(i, "temp", errtok, false, muted)
				break
			end
		end

		-- worst case scenario, use a saved register if one is available
		if not out then
			out = getsaved(errtok, false, muted)
		end
	end

	if not out then
		lerror(errtok, "overflowing to stack frame not supported right now, sorry")
		return false
	end

	return out
end

local function rfree(reg)
	if reg.auto then
		reg.used = false

		return
	end

	if reg.refs then
		reg.refs = reg.refs - 1
		if reg.refs == 0 then
			reg.refs = nil
		else
			return
		end
	end

	if reg.incirco then
		reg.incirco = false
	end

	if reg.typ == "save" then
		curfn.usedsave[reg.id] = false
	elseif reg.typ == "temp" then
		curfn.usedtemp[reg.id] = false
	end
end

local function freeof(...)
	local regs = {...}

	for i = 1, #regs do
		local r = regs[i]

		if r.typ ~= "imm" then
			rfree(r)
		end
	end
end

local function rcmp(r1, r2)
	return (r1.typ == r2.typ) and (r1.id == r2.id)
end

local function freeofp(p, ...)
	local regs = {...}

	for i = 1, #regs do
		local r = regs[i]

		if (r.typ ~= "imm") and (not rcmp(p, r)) then
			rfree(r)
		end
	end
end

local function getmutreg(rootcanmut, ...)
	local regs = {...}

	if rootcanmut and curfn.mutreg then
		curfn.mutreg.muted = true
		return curfn.mutreg
	end

	for i = 1, #regs do
		local r = regs[i]

		if (not r.auto) and ((r.refs or 0) <= 1) and (r.typ ~= "imm") then
			return r
		end
	end

	return ralloc(nil, false, false, true)
end

local function shouldmut(r, butdontactually)
	if r.kind == "auto" then
		if not butdontactually then
			curfn.mutreg = r.ident.reg
		end

		return true
	else
		return false
	end
end

local function loadimm(r, imm)
	if tonumber(imm) then
		if band(imm, 0xFFFF0000) == 0 then
			text("\tli   "..r.n..", "..tostring(imm))
		elseif band(imm, 0xFFFF) == 0 then
			text("\tlui  "..r.n..", zero, "..tostring(imm))
		elseif (imm < 0) and (imm >= -65535) then
			text("\tsubi "..r.n..", zero, "..tostring(math.abs(imm)))
		else
			text("\tla   "..r.n..", "..tostring(imm))
		end
	else
		text("\tla   "..r.n..", "..imm)
	end
end

local function loadimmf(r, mask, min, max)
	if (r.typ == "imm") then
		if min and tonumber(r.id) and (r.id >= min) and (r.id <= max) then
			return r, false
		elseif (not tonumber(r.id)) or (band(r.id, bnot(mask)) ~= 0) or (mask == 0) then
			local e = ralloc(r.errtok)

			if not e then return false end

			loadimm(e, r.id)

			return e, true
		else
			return r, false
		end
	else
		return r, false
	end
end

local function canoffset(node)
	return (node.kind == "op") and (node.op == "+") and (not node.refs)
end

-- gets things in a nicer order for instructions that need it
local function r1r2i(r1, r2, mask, noncommutative, lomask)
	local reg1, reg2, imm, unaligned

	local ir

	lomask = lomask or 0

	if r1.typ == "imm" then
		if noncommutative then
			reg1 = ralloc(r1.errtok)

			if not reg1 then return false end

			loadimm(reg1, r1.id)

			reg2 = r2
		else
			reg1 = r2
			ir = r1
			imm = r1.id
		end
	elseif r2.typ == "imm" then
		reg1 = r1
		ir = r2
		imm = r2.id
	else
		reg1 = r1
		reg2 = r2
	end

	if imm and mask then
		local e, l = loadimmf(ir, mask)

		if l then
			if band(imm, lomask) ~= 0 then
				unaligned = true
			end

			reg2 = e
			imm = nil
		end
	end

	return reg1, reg2, imm, unaligned
end

local function retone(block, mutreg, allowinverse, lockref)
	local omutreg = curfn.mutreg
	curfn.mutreg = nil

	if not cg.block(block) then return false end

	local ns = block.stack.stack[1]

	if not ns then error("no top of stack") end

	curfn.mutreg = mutreg

	local ro = cg.expr(ns, false, false, false, mutreg, allowinverse, lockref)

	curfn.mutreg = omutreg

	return ro, (block.calls > 0)
end

local function op2(errtok, oper1, oper2, mask, noncommutative, lomask)
	local r1 = cg.expr(oper1)

	if not r1 then return false end

	local r2 = cg.expr(oper2)

	if not r2 then return false end

	local reg1, reg2, imm, unaligned = r1r2i(r1, r2, mask, noncommutative, lomask)

	return reg1, reg2, imm, unaligned
end

local function genarith(errtok, oper1, oper2, rootcanmut, mask, mnem, mnemi, noncommutative)
	local reg1, reg2, imm = op2(errtok, oper1, oper2, mask, noncommutative)

	if not reg1 then return false end

	local rd = getmutreg(rootcanmut, reg1, reg2)

	if not rd then return false end

	if imm then
		text("\t"..mnemi.." "..rd.n..", "..reg1.n..", "..tostring(imm))
	else
		text("\t"..mnem.." "..rd.n..", "..reg1.n..", "..reg2.n)
	end

	freeofp(rd, reg1, reg2)

	return rd
end

local function mkload(errtok, src, auto, mnem, mask, rootcanmut, lomask)
	if src.kind == "auto" then
		if not auto then
			lerror(errtok, "can't operate directly on an auto!")
			return false
		end

		return src.ident.reg
	end

	local rs, reg2, imm, unaligned

	local add = false

	if canoffset(src) then
		rs, reg2, imm, unaligned = op2(src.errtok, src.opers[1], src.opers[2], mask, false, lomask)

		add = true

		if unaligned then
			lerror(src.errtok, "load offset is unaligned!")
			return false
		end
	else
		rs = cg.expr(src, true, false, true)
	end

	if not rs then return false end

	local rd = getmutreg(rootcanmut, rs, reg2)

	if not rd then return false end

	if not add then
		text("\tmov  "..rd.n..", "..mnem.." ["..rs.n.."]")
	elseif reg2 then
		text("\tmov  "..rd.n..", "..mnem.." ["..rs.n.." + "..reg2.n.."]")
	elseif imm then
		text("\tmov  "..rd.n..", "..mnem.." ["..rs.n.." + "..tostring(imm).."]")
	end

	freeofp(rd, rs, reg2)

	return rd
end

local optable = {
	["@"] = function (errtok, op, rootcanmut)
		return mkload(errtok, op.opers[1], true, "long", 0x3FFFC, rootcanmut, 3)
	end,
	["gi"] = function (errtok, op, rootcanmut)
		return mkload(errtok, op.opers[1], false, "int", 0x1FFFE, rootcanmut, 1)
	end,
	["gb"] = function (errtok, op, rootcanmut)
		return mkload(errtok, op.opers[1], false, "byte", 0xFFFF, rootcanmut)
	end,

	["+"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "add ", "addi")
	end,
	["-"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "sub ", "subi", true)
	end,
	["*"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0, "mul ", nil)
	end,
	["/"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0, "div ", nil, true)
	end,
	["%"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0, "mod ", nil, true)
	end,

	[">>"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "rsh ", "rshi", true)
	end,
	["<<"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "lsh ", "lshi", true)
	end,

	["&"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "and ", "andi")
	end,
	["|"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "or  ", "ori ")
	end,
	["^"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "xor ", "xori")
	end,

	["~"] = function (errtok, op, rootcanmut)
		local src = op.opers[1]

		local rs = cg.expr(src, false, false, true, rootcanmut)

		if not rs then return false end

		local rd = getmutreg(rootcanmut, rs)

		if not rd then return false end

		text("\tnor  "..rd.n..", "..rs.n..", "..rs.n)

		freeofp(rd, rs)

		return rd
	end,

	["=="] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "seq ", "seqi")
	end,

	["~="] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "sne ", "snei")
	end,

	["<"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "slt ", "slti", true)
	end,
	[">"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[2], op.opers[1], rootcanmut, 0xFFFF, "slt ", "slti", true)
	end,

	["s<"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "slt  signed", "slti  signed", true)
	end,
	["s>"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[2], op.opers[1], rootcanmut, 0xFFFF, "slt  signed", "slti  signed", true)
	end,

	["<="] = function (errtok, op, rootcanmut) -- same thing as not-greater
		local e = genarith(errtok, op.opers[2], op.opers[1], rootcanmut, 0xFFFF, "slt ", "slti", true)

		if not e then return false end

		e.inverse = true

		return e
	end,
	[">="] = function (errtok, op, rootcanmut) -- same thing as not-less
		local e = genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "slt ", "slti", true)

		if not e then return false end

		e.inverse = true

		return e
	end,

	["s<="] = function (errtok, op, rootcanmut) -- same thing as not-greater
		local e = genarith(errtok, op.opers[2], op.opers[1], rootcanmut, 0xFFFF, "slt  signed", "slti  signed", true)

		if not e then return false end

		e.inverse = true

		return e
	end,
	["s>="] = function (errtok, op, rootcanmut) -- same thing as not-less
		local e = genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "slt  signed", "slti  signed", true)

		if not e then return false end

		e.inverse = true

		return e
	end,

	["~~"] = function (errtok, op, rootcanmut)
		local src = op.opers[1]

		local rs = cg.expr(src, false, false, true, rootcanmut, true)

		if not rs then return false end

		rs.inverse = (not rs.inverse)

		return rs
	end,

	["||"] = function (errtok, op, rootcanmut)
		local rd = genarith(errtok, op.opers[1], op.opers[2], rootcanmut, 0xFFFF, "or  ", "ori ")

		if not rd then return false end

		-- doing getmutreg isnt necessary because genarith already did that for us,
		-- so rd is guaranteed not to be directly an auto

		text("\tsne  "..rd.n..", "..rd.n..", zero")

		return rd
	end,

	["&&"] = function (errtok, op, rootcanmut)
		local reg1, reg2, imm = op2(errtok, op.opers[1], op.opers[2], 0xFF)

		if not reg1 then return false end

		-- on &&, eval.lua should convert any non-zero immediate into an equivalence test with 0
		if imm then error("internally inconsistent") end

		if reg1 == curfn.mutreg then
			rootcanmut = false
		end

		local rd = getmutreg(rootcanmut)

		if not rd then return false end

		text("\tli "..rd.n..", 0")

		local out = locallabel()

		text("\tbeq  "..reg1.n..", zero, "..out)

		text("\tsne  "..rd.n..", "..reg2.n..", zero")

		text(out..":")

		freeofp(rd, reg1, reg2)

		return rd
	end,

	["retvalue"] = function (errtok, op, rootcanmut)
		return op.reg
	end,

	["alloc"] = function (errtok, op, rootcanmut)
		local offset = op.opers[1]

		return genarith(errtok, curfn.allocoff, offset, rootcanmut, 0xFFFF, "add ", "addi")
	end,

	["index"] = function (errtok, op, rootcanmut)
		local exprb = op.opers[2]
		local tab = op.opers[1]

		local rs = retone(exprb)

		if not rs then return false end

		if (tab.kind ~= "table") and (tab.kind ~= "externconst") and (tab.kind ~= "buffer") then
			error("internally inconsistent")
		end

		local rd = getmutreg(rootcanmut)

		if not rd then return false end

		local ri

		if tab.ident ~= "argv" then
			loadimm(rd, tab.ident)

			ri = rd
		else
			ri = curfn.argvoff
		end

		rs, l = loadimmf(rs, 0x3FFF)

		if not rs then return false end

		local imm2

		if rs.typ == "imm" then
			imm2 = rs.id
		end

		if imm2 then
			if imm2 ~= 0 then
				text("\taddi "..rd.n..", "..ri.n..", "..tostring(rs.id * 4))
			else
				freeofp(ri, rd)
			end
		else
			text("\tadd  "..rd.n..", "..ri.n..", "..rs.n.." LSH 2")
		end

		freeofp(rd, rs)

		return rd
	end,
}

function cg.expr(node, allowdirectauto, allowdirectptr, immtoreg, rootcanmut, allowinverse, lockref)
	-- print(node)

	if node.kind == "reg" then
		return node
	end

	if node.evalr then
		if not node.evalr.refs then
			print(node.kind,node.op)
			error("internally inconsistent")
		end

		return node.evalr
	end

	if (node.kind == "num") or (node.kind == "ptr") or (node.kind == "table") then
		if node.ident == "argv" then
			return curfn.argvoff
		end

		if immtoreg or (((node.kind == "ptr") or (node.kind == "table")) and (not allowdirectptr)) then
			local r = getmutreg(rootcanmut)

			if not r then return false end

			loadimm(r, node.ident)

			return r
		end

		return reg_t(node.ident, "imm", node.errtok)
	elseif node.kind == "auto" then
		if not allowdirectauto then
			lerror(node.errtok, "can't operate directly on an auto!")
			return false
		end

		return node.ident.reg
	elseif node.kind == "str" then
		local r = getmutreg(rootcanmut)

		if not r then return false end

		local l = cstring(node.ident)

		loadimm(r, l)

		return r
	elseif node.kind == "op" then
		local cop = optable[node.op]

		if not cop then
			lerror(node.errtok, "I don't know how to generate code for "..node.op)
			return false
		end

		local rcm = rootcanmut and (not node.refs)

		local ro = cop(node.errtok, node, rcm)

		if not ro then return false end

		if ro.typ ~= "imm" then
			if (ro.inverse) and ((not allowinverse) or node.refs) then
				ro.inverse = nil

				local rd = getmutreg(rcm, ro)

				if not rd then return false end

				text("\tseq  "..rd.n..", "..ro.n..", zero")

				freeofp(rd, ro)

				ro = rd
			end

			if (not rcm) and (not ro.auto) and (node.refs) then
				ro.refs = node.refs

				node.evalr = ro
			end
		else
			error("op shouldn't return imm")
		end

		--print(ro.n)

		return ro
	else
		error(node.kind)
	end
end

local function mkstore(errtok, dest, src, auto, mnem, mask, lomask)
	local rd, reg2, imm, unaligned

	local add = false

	local muted

	if canoffset(dest) then
		rd, reg2, imm, unaligned = op2(dest.errtok, dest.opers[1], dest.opers[2], mask, false, lomask)

		add = true

		if unaligned then
			lerror(dest.errtok, "store offset is unaligned!")
			return false
		end
	elseif dest.kind ~= "reg" then
		rd = cg.expr(dest, auto, true)

		if not rd then return false end

		muted = shouldmut(dest)

		local e

		rd, e = loadimmf(rd, 0)
	end

	if not rd then return false end

	local rs = cg.expr(src, false, false, false, true)

	if not rs then return false end

	if dest.kind == "auto" then
		if not auto then error("internally inconsistent") end

		if rs.typ == "imm" then
			loadimm(rd, rs.id)
		elseif not rd.muted then
			if rd.n ~= rs.n then
				text("\tmov  "..rd.n..", "..rs.n)
			end
		end
	else
		local l

		if (rs.typ == "imm") and (reg2) then
			-- can't have a reg offset and imm src in limn2500.
			-- we have to load the imm here

			rs, l = loadimmf(rs, 0)

			if not rs then return false end
		else
			rs, l = loadimmf(rs, 0, -16, 15)
		end

		local imm2

		if rs.typ == "imm" then
			imm2 = rs.id
		end

		local rn = "0"

		if add then
			if reg2 then
				rn = reg2.n
			else
				rn = imm
			end
		end

		if imm2 then
			text("\tmov  "..mnem.." ["..rd.n.." + "..rn.."], "..tostring(imm2))
		else
			-- tprint(rd)

			text("\tmov  "..mnem.." ["..rd.n.." + "..rn.."], "..rs.n)
		end
	end

	freeof(rd, rs)

	return true
end

local function mkmod(errtok, dest, src, mask, mnem, mnemi, noncommutative)
	local rcm = shouldmut(dest)

	local rd = mkload(errtok, dest, true, "long", 0x3FFFC, true)

	if not rd then return false end

	rd = genarith(errtok, rd, src, true, mask, mnem, mnemi, noncommutative)

	if not rd then return false end

	if not mkstore(errtok, dest, rd, true, "long", 0x3FFFC) then return false end

	return true
end

local function conditional(cond, out, inv, lockref)
	-- TODO make this generate nicer branches

	local e = ralloc(cond.errtok)

	local rs = retone(cond, e, true, lockref)

	if not rs then return false end

	if (rs.typ ~= "imm") and (not e.muted) then
		text("\tmov  "..e.n..", "..rs.n)
	end

	if rs.typ ~= "imm" then
		if rs.inverse then
			rs.inverse = nil
			if inv then
				text("\tbeq  "..e.n..", zero, "..out)
			else
				text("\tbne  "..e.n..", zero, "..out)
			end
		else
			if inv then
				text("\tbne  "..e.n..", zero, "..out)
			else
				text("\tbeq  "..e.n..", zero, "..out)
			end
		end
	end

	freeof(e, rs)

	return true
end

local function flushincirco()
	for i = 1, #curfn.incirco do
		local r = curfn.incirco[i]

		if r.reg.incirco then
			local e = ralloc(r.reg.errtok, true)

			if not e then return false end

			text("\tmov  "..e.n..", "..r.reg.n)

			freeof(r.reg)

			r.reg = e

			if r.evalr then
				e.refs = r.evalr.refs
				r.evalr = e
			end
		end
	end

	curfn.incirco = {}

	return true
end

local muttable = {
	["!"] = function (errtok, op)
		return mkstore(errtok, op.opers[1], op.opers[2], true, "long", 0x3FFFC, 3)
	end,
	["si"] = function (errtok, op)
		return mkstore(errtok, op.opers[1], op.opers[2], false, "int", 0x1FFFE, 1)
	end,
	["sb"] = function (errtok, op)
		return mkstore(errtok, op.opers[1], op.opers[2], false, "byte", 0xFFFF)
	end,

	["+="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], 0xFFFF, "add ", "addi")
	end,
	["-="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], 0xFFFF, "sub ", "subi", true)
	end,

	["*="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], 0, "mul ", nil)
	end,
	["/="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], 0, "div ", nil, true)
	end,

	["%="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], 0, "mod ", nil, true)
	end,

	[">>="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], 0x1F, "rsh ", "rshi", true)
	end,
	["<<="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], 0x1F, "lsh ", "lshi", true)
	end,

	["&="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], 0xFFFF, "and ", "andi")
	end,

	["|="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], 0xFFFF, "or  ", "ori ")
	end,

	["return"] = function (errtok, op)
		text("\tb    .epilogue")

		return true
	end,

	["break"] = function (errtok, op)
		text("\tb    "..wpushdown[#wpushdown])

		return true
	end,

	["continue"] = function (errtok, op)
		text("\tb "..wcpushdown[#wcpushdown])

		return true
	end,

	["call"] = function (errtok, op)
		if not flushincirco() then return false end

		local an

		if op.fn.varin then
			text("\tli  a0, "..op.argvs)
			an = 1
		else
			an = 0
		end

		local reached = 8

		for i = 1, #op.fin do
			local fa = op.fin[i]

			if an then
				local e = reg_t(an, "arg", errtok)
				curfn.mutreg = e

				local r = cg.expr(fa.node, false, false, false, true)

				if not r then return false end

				if r.typ == "imm" then
					loadimm(e, r.id)
				elseif not e.muted then
					text("\tmov  "..e.n..", "..r.n)
				end

				curfn.mutreg = nil
				freeofp(e, r)

				an = an + 1

				if an == 4 then
					an = nil
				end
			else
				local r = cg.expr(fa.node, false, false, false)

				if not r then return false end

				r, l = loadimmf(r, 0, -16, 15)

				local imm2

				if r.typ == "imm" then
					imm2 = r.id
				end

				if imm2 then
					text("\tmov  long [sp + "..tostring(reached).."], "..tostring(imm2))
				else
					text("\tmov  long [sp + "..tostring(reached).."], "..r.n)
				end

				freeof(r)

				reached = reached + 4
			end
		end

		for i = 1, #op.argv do
			local fa = op.argv[i]

			local r = cg.expr(fa.node, false, false, false)

			if not r then return false end

			r, l = loadimmf(r, 0, -16, 15)

			local imm2

			if r.typ == "imm" then
				imm2 = r.id
			end

			if imm2 then
				text("\tmov  long [sp + "..tostring(reached).."], "..tostring(imm2))
			else
				text("\tmov  long [sp + "..tostring(reached).."], "..r.n)
			end

			freeof(r)

			reached = reached + 4
		end

		if op.ptr then
			local r = cg.expr(op.ptr, false, false, true)

			if not r then return false end

			text("\tjalr lr, "..r.n..", 0")

			freeof(r)
		else
			text("\tjal  "..op.fn.ident)
		end

		local vn = 0

		reached = 8

		for i = 1, #op.rets do
			local fa = op.rets[i]

			if not fa.dropped then
				if vn then
					fa.reg = reg_t(vn, "ret", errtok)

					vn = vn + 1

					if vn > 3 then
						vn = nil
					end
				else
					fa.reg = ralloc(errtok)

					if not fa.reg then return false end

					text("\tmov  "..fa.reg.n..", long [sp + "..tostring(reached).."]")

					reached = reached + 4
				end

				fa.reg.incirco = true

				curfn.incirco[#curfn.incirco + 1] = fa
			elseif vn then
				vn = vn + 1

				if vn > 3 then
					vn = nil
				end
			else
				reached = reached + 4
			end
		end

		return true
	end,

	["while"] = function (errtok, op)
		local loop = locallabel()

		local out = locallabel()

		if (op.body.calls > 0) or (op.conditional.calls > 0) then -- needs to be done before the conditional runs
			flushincirco()
		end

		local simp = op.conditional.simple

		local cont

		if simp then
			if not conditional(op.conditional, out) then return false end
			cont = locallabel()
		end

		text(loop..":")

		if not simp then
			if not conditional(op.conditional, out) then return false end
		end

		wcpushdown[#wcpushdown + 1] = cont or loop

		wpushdown[#wpushdown + 1] = out

		if not cg.block(op.body) then return false end

		wcpushdown[#wcpushdown] = nil

		wpushdown[#wpushdown] = nil

		if simp then
			text(cont..":")
			if not conditional(op.conditional, loop, true) then return false end
		else
			text("\tb    "..loop)
		end

		text(out..":")

		return true
	end,

	["if"] = function (errtok, op)
		-- needs to be done before any code is generated
		for i = 1, #op.ifs do
			local ifn = op.ifs[i]

			if (ifn.conditional.calls > 0) or (ifn.body.calls > 0) then
				flushincirco()
				break
			end
		end

		local satisfied = locallabel()

		local nex

		for i = 1, #op.ifs do
			local ifn = op.ifs[i]

			local dn = (i ~= #op.ifs) or op.default

			if dn then
				nex = locallabel()
			else
				nex = satisfied
			end

			if not conditional(ifn.conditional, nex) then return false end

			if not cg.block(ifn.body) then return false end

			if dn then
				text("\tb    "..satisfied)

				text(nex..":")
			end
		end

		if op.default then
			if not cg.block(op.default) then return false end
		end

		text(satisfied..":")

		return true
	end,
}

function cg.block(block)
	if block.calls > 0 then
		--print(block.calls)
		flushincirco()
	end

	if curfn.mutreg then
		error("mutreg before block")
	end

	for i = 1, #block.ops do
		local op = block.ops[i]

		local cop = muttable[op.kind]

		if not cop then
			lerror(op.errtok, "I don't know how to generate code for "..op.kind)
			return false
		end

		if not cop(op.errtok, op) then return false end

		if curfn.mutreg then
			curfn.mutreg.muted = false
			curfn.mutreg = false
		end
	end

	return true
end

function cg.func(func)
	curfn = func

	func.usedtemp = {}

	func.usedsave = {}

	func.saved = {}

	func.incirco = {}

	func.savedn = 0

	func.labln = 0

	local exret = 0

	local exarg = 0

	-- analyze stuff to determine stack frame parameters.
	-- these need to be known ahead of time, I guess

	local savelink = false

	for i = 1, #func.calls do
		local cgc = func.calls[i]

		exarg = math.max(exarg, cgc.argvs)

		if cgc.args > 4 then -- the limn2500 ABI gives us 4 registers to use for arguments
			exarg = math.max(exarg, cgc.args - 4)
		end

		if cgc.os > 4 then -- the limn2500 ABI gives us 4 registers to use for outputs
			exret = math.max(exret, cgc.os - 4)
		end

		savelink = true
	end

	local savareaoff = math.max(exret, exarg) * 4 + 8

	if func.varin then
		func.argvoff = ralloc(func.errtok, true, true)

		if not func.argvoff then
			return false
		end
	end

	if func.allocated > 0 then
		func.allocoff = ralloc(func.errtok, true, true)

		if not func.allocoff then
			return false
		end
	end

	for i = 1, #func.isymb do
		local s = func.isymb[i]

		if s.kind == "auto" then
			s.reg = ralloc(s.errtok, true, true)

			if not s.reg then return false end
		end
	end

	local otext = textsection

	textsection = ""

	-- compile root block
	if not cg.block(func.block) then return false end

	-- switch text
	local fntext = textsection
	textsection = otext

	if func.allocated > 0xFFFF then
		lerror(func.errtok, "stack alloc exceeded 64KB")

		return false
	end

	-- generate prologue
	local frametop = savareaoff + (func.savedn * 4)

	if frametop > 0x40000 then
		lerror(func.errtok, "frame size exceeded 256KB")
		return false
	end

	func.allocstart = frametop

	frametop = frametop + func.allocated

	text(func.name..":")
	if func.public then
		text(".global "..func.name)
	end
	text("\tmov  t0, sp")
	text("\tsubi sp, sp, "..tostring(frametop))
	text("\tmov  long [sp], t0")
	if savelink then
		text("\tmov  long [sp + 4], lr")
	end
	for i = 0, SAVEMAX do
		if func.saved[i] then
			text("\tmov  long [sp + "..tostring(savareaoff + (i * 4)).."], s"..tostring(i))
		end
	end

	local reached = false

	local ac = 0

	if func.varin then
		local argcs = func.symb["argc"]

		text("\tmov  "..argcs.reg.n..", a0")

		ac = 1
	end

	for i = #func.fin, 1, -1 do
		local s = func.symb[func.fin[i]]

		--print(func.fin[i], s.reg.n)

		if not reached then
			text("\tmov  "..s.reg.n..", a"..tostring(ac))
			ac = ac + 1

			if ac == 4 then
				reached = 8
			end
		else
			text("\tmov  "..s.reg.n..", long [sp + "..tostring(frametop + reached).."]")

			reached = reached + 4
		end
	end

	if func.varin then
		text("\taddi "..func.argvoff.n..", t0, "..(reached or 8))
	end

	if func.allocated > 0 then
		text("\taddi "..func.allocoff.n..", sp, "..func.allocstart)
	end

	-- append fn text
	textsection = textsection .. fntext

	-- generate epilogue

	text(".epilogue:")

	local vc = 0

	reached = false

	for i = 1, #func.out do
		local s = func.symb[func.out[i]]

		if not reached then
			text("\tmov  a"..tostring(vc)..", "..s.reg.n)
			vc = vc + 1

			if vc == 4 then
				reached = 8
			end
		else
			text("\tmov  long [sp + "..tostring(frametop + reached).."], "..s.reg.n)

			reached = reached + 4
		end
	end

	for i = 0, SAVEMAX do
		if func.saved[i] then
			text("\tmov  s"..tostring(i)..", long [sp + "..tostring(savareaoff + (i * 4)).."]")
		end
	end
	if savelink then
		text("\tmov  lr, long [sp + 4]")
	end
	text("\taddi sp, sp, "..tostring(frametop))
	text("\tret")

	return true
end

function cg.gen(edefs, public, extern, asms, const)
	if not edefs then return false end

	defs = edefs

	textsection = ".section text\n"

	datasection = ".section data\n"

	bsssection = ".section bss\n"

	labln = 0

	--tprint(defs)

	for k,v in pairs(extern) do
		text(".extern "..k)
	end

	for k,v in pairs(const) do
		if not extern[k] then
			text(".define "..k.." "..tostring(v))
		end
	end

	for k,v in pairs(defs) do
		if v.kind == "var" then
			if v.value == 0 then
				bss(".align 4")
				bss(v.name..":")
				bss("\t.dl 0")
			else
				data(".align 4")
				data(v.name..":")
				data("\t.dl "..v.value)
			end
		elseif v.kind == "buffer" then
			bss(".align 4")
			bss(v.name..":")
			bss("\t.bytes "..v.value.." 0")
			bss(".align 4")
		elseif v.kind == "table" then
			if v.value then
				bss(".align 4")
				bss(v.name..":")
				bss("\t.bytes "..(v.value * 4).." 0")
				bss(".align 4")
			else
				local strs = {}

				data(".align 4")
				data(v.name..":")
				for k2,word in ipairs(v.words) do
					if (word.typ == "num") or (word.typ == "ptr") then
						data("\t.dl "..word.name)
					elseif word.typ == "str" then
						local l = label()

						strs[#strs + 1] = {l, word.name}

						data("\t.dl "..l)
					else
						error(word.typ)
					end
				end

				for k2,s in ipairs(strs) do
					cstring(s[2], s[1])
				end
			end
		elseif v.kind == "fn" then
			--tprint(v)

			if not cg.func(v) then return false end
		else
			error(v.kind)
		end
	end

	for i = 1, #asms do
		text(asms[i])
	end

	for k,v in pairs(public) do
		bss(".global "..k)
	end

	return textsection .. datasection .. bsssection
end

return cg