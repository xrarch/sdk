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
	print(string.format("dragonc: cg-fox32: %s:%d: %s", token[4], token[3], err))
end

local cg = {}

cg.ptrsize = 4
cg.wordsize = 4

local textsections = {}
local textsectionsi = {}

local rodatasections = {}

local datasection

local bsssection

local defs

local curfn

local SAVEMAX = 17

local TEMPMAX = 6

local wpushdown = {}

local wcpushdown = {}

local function text(str)
	textsections[curfn.section] = textsections[curfn.section] .. str .. "\n"
end

local function atext(str)
	textsections[curfn.section] = textsections[curfn.section] .. str
end

local function data(str)
	datasection = datasection .. str .. "\n"
end

local function adata(str)
	datasection = datasection .. str
end

local function rodata(str)
	local section

	if curfn then
		section = curfn.section
	else
		section = "text"
	end

	rodatasections["text"] = rodatasections["text"] .. str .. "\n"
end

local function arodata(str)
	local section

	if curfn then
		section = curfn.section
	else
		section = "text"
	end

	rodatasections["text"] = rodatasections["text"] .. str
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

	rodata(sno..":")
	arodata('\t.ds "')

	for i = 1, #str do
		local c = str:sub(i,i)
		if c == "\n" then
			arodata("\\n")
		else
			arodata(c)
		end
	end
	rodata('\\0"')

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
		if imm < 0 then
			text("\tmov "..r.n..", "..tostring(imm))
		elseif imm <= 255 then
			text("\tmovz.8 "..r.n..", "..tostring(imm))
		elseif imm <= 65535 then
			text("\tmovz.16 "..r.n..", "..tostring(imm))
		else
			text("\tmov "..r.n..", "..tostring(imm))
		end
	else
		text("\tmov "..r.n..", "..imm)
	end
end

-- gets things in a nicer order for instructions that need it
local function r1r2i(r1, r2, noncommutative)
	local reg1, reg2, imm

	local ir

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

	return reg1, reg2, imm
end

local function op2(errtok, oper1, oper2, noncommutative)
	local r1 = cg.expr(oper1)

	if not r1 then return false end

	local r2 = cg.expr(oper2)

	if not r2 then return false end

	local reg1, reg2, imm = r1r2i(r1, r2, noncommutative)

	return reg1, reg2, imm
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

local function genarith(errtok, oper1, oper2, rootcanmut, mnem, noncommutative)
	local reg1, reg2, imm = op2(errtok, oper1, oper2, noncommutative)

	if not reg1 then return false end

	local rd = ralloc(nil, false, false, true)

	if not rd then return false end

	if rd.n ~= reg1.n then
		text("\tmov "..rd.n..", "..reg1.n)
	end

	if imm then
		text("\t"..mnem.." "..rd.n..", "..imm)
	else
		text("\t"..mnem.." "..rd.n..", "..reg2.n)
	end

	freeofp(rd, reg1, reg2)

	return rd
end

local function mkload(errtok, src, auto, mnem, rootcanmut)
	if src.kind == "auto" then
		if not auto then
			lerror(errtok, "can't operate directly on an auto!")
			return false
		end

		return src.ident.reg
	end

	local rs

	rs = cg.expr(src, true, false, true, nil, nil, nil, true)

	if not rs then return false end

	local rd = getmutreg(rootcanmut, rs)

	if not rd then return false end

	if rs.typ == "imm" then
		text("\tmovz."..mnem.." "..rd.n..", ["..rs.id.."]")
	else
		text("\tmovz."..mnem.." "..rd.n..", ["..rs.n.."]")
	end

	freeofp(rd, rs)

	return rd
end

local optable = {
	["@"] = function (errtok, op, rootcanmut)
		return mkload(errtok, op.opers[1], true, "32", rootcanmut)
	end,
	["gi"] = function (errtok, op, rootcanmut)
		return mkload(errtok, op.opers[1], false, "16", rootcanmut)
	end,
	["gb"] = function (errtok, op, rootcanmut)
		return mkload(errtok, op.opers[1], false, "8", rootcanmut)
	end,

	["+"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "add ")
	end,
	["-"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "sub ", true)
	end,
	["*"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "mul ")
	end,
	["/"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "div ", true)
	end,
	["%"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "rem ", true)
	end,

	[">>"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "srl ", true)
	end,
	["<<"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "sla ", true)
	end,

	["&"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "and ")
	end,
	["|"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "or  ")
	end,
	["^"] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "xor ")
	end,

	["~"] = function (errtok, op, rootcanmut)
		local src = op.opers[1]

		local rs = cg.expr(src, false, false, true, rootcanmut)

		if not rs then return false end

		local rd = getmutreg(rootcanmut, rs)

		if not rd then return false end

		if rd.n ~= rs.n then
			text("\tmov "..rd.n..", "..rs.n)
		end

		text("\tnot "..rd.n)

		freeofp(rd, rs)

		return rd
	end,

	["=="] = function (errtok, op, rootcanmut)
		local rd = genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "sub ")

		rd.inverse = true

		return rd
	end,

	["~="] = function (errtok, op, rootcanmut)
		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "sub ")
	end,

	["<"] = function (errtok, op, rootcanmut)
		local reg1, reg2, imm = op2(errtok, op.opers[1], op.opers[2], true)

		if not reg1 then return false end

		local rd = getmutreg(rootcanmut, reg1, reg2)

		if not rd then return false end

		local out = locallabel()
		local out2 = locallabel()

		if imm then
			text("\tcmp "..reg1.n..", "..imm)
		else
			text("\tcmp "..reg1.n..", "..reg2.n)
		end

		text("\tiflt rjmp "..out)
		text("\tmov "..rd.n..", 0")
		text("\trjmp "..out2)
		text(out..":")
		text("\tmov "..rd.n..", 1")
		text(out2..":")

		freeofp(rd, reg1, reg2)

		return rd
	end,
	[">"] = function (errtok, op, rootcanmut)
		local reg1, reg2, imm = op2(errtok, op.opers[1], op.opers[2], true)

		if not reg1 then return false end

		local rd = getmutreg(rootcanmut, reg1, reg2)

		if not rd then return false end

		local out = locallabel()
		local out2 = locallabel()

		if imm then
			text("\tcmp "..reg1.n..", "..imm)
		else
			text("\tcmp "..reg1.n..", "..reg2.n)
		end

		text("\tifgt rjmp "..out)
		text("\tmov "..rd.n..", 0")
		text("\trjmp "..out2)
		text(out..":")
		text("\tmov "..rd.n..", 1")
		text(out2..":")

		freeofp(rd, reg1, reg2)

		return rd
	end,

	["z<"] = function (errtok, op, rootcanmut)
		local src = op.opers[1]

		local rs = cg.expr(src, false, false, true, rootcanmut)

		if not rs then return false end

		local rd = getmutreg(rootcanmut, rs)

		if not rd then return false end

		if rd.n ~= rs.n then
			text("\tmov "..rd.n..", "..rs.n)
		end

		text("\tand "..rd.n..", 0x80000000")

		freeofp(rd, rs)

		return rd
	end,
	["z>"] = function (errtok, op, rootcanmut)
		local src = op.opers[1]

		local rs = cg.expr(src, false, false, true, rootcanmut)

		if not rs then return false end

		local rd = getmutreg(rootcanmut, rs)

		if not rd then return false end

		if rd.n ~= rs.n then
			text("\tmov "..rd.n..", "..rs.n)
		end

		local badout = locallabel()
		local goodout = locallabel()

		text("\tcmp  "..rd.n..", 0")
		text("\tifz  jmp "..badout)
		text("\tand  "..rd.n..", 0x80000000")
		text("\tifnz jmp "..badout)
		text("\tmov  "..rd.n..", 1")
		text("\tjmp  "..goodout)
		text(badout..":")
		text("\tmov  "..rd.n..", 0")
		text(goodout..":")

		freeofp(rd, rs)

		return rd
	end,

	["s<"] = function (errtok, op, rootcanmut)
		lerror(errtok, "s< not supported by fox32 backend")
		return false
	end,
	["s>"] = function (errtok, op, rootcanmut)
		lerror(errtok, "s> not supported by fox32 backend")
		return false
	end,

	["<="] = function (errtok, op, rootcanmut) -- same thing as not-greater
		local reg1, reg2, imm = op2(errtok, op.opers[1], op.opers[2], true)

		if not reg1 then return false end

		local rd = getmutreg(rootcanmut, reg1, reg2)

		if not rd then return false end

		local out = locallabel()
		local out2 = locallabel()

		if imm then
			text("\tcmp "..reg1.n..", "..imm)
		else
			text("\tcmp "..reg1.n..", "..reg2.n)
		end

		text("\tiflteq rjmp "..out)
		text("\tmov "..rd.n..", 0")
		text("\trjmp "..out2)
		text(out..":")
		text("\tmov "..rd.n..", 1")
		text(out2..":")

		freeofp(rd, reg1, reg2)

		return rd
	end,
	[">="] = function (errtok, op, rootcanmut) -- same thing as not-less
		local reg1, reg2, imm = op2(errtok, op.opers[1], op.opers[2], true)

		if not reg1 then return false end

		local rd = getmutreg(rootcanmut, reg1, reg2)

		if not rd then return false end

		local out = locallabel()
		local out2 = locallabel()

		if imm then
			text("\tcmp "..reg1.n..", "..imm)
		else
			text("\tcmp "..reg1.n..", "..reg2.n)
		end

		text("\tifgteq rjmp "..out)
		text("\tmov "..rd.n..", 0")
		text("\trjmp "..out2)
		text(out..":")
		text("\tmov "..rd.n..", 1")
		text(out2..":")

		freeofp(rd, reg1, reg2)

		return rd
	end,

	["s<="] = function (errtok, op, rootcanmut) -- same thing as not-greater
		lerror(errtok, "s<= not supported by fox32 backend")
		return false
	end,
	["s>="] = function (errtok, op, rootcanmut) -- same thing as not-less
		lerror(errtok, "s>= not supported by fox32 backend")
		return false
	end,

	["~~"] = function (errtok, op, rootcanmut)
		local src = op.opers[1]

		local rs = cg.expr(src, false, false, true, rootcanmut, true)

		if not rs then return false end

		rs.inverse = (not rs.inverse)

		return rs
	end,

	["||"] = function (errtok, op, rootcanmut)
		-- TODO make it not evaluate the second thing if the first thing was true

		return genarith(errtok, op.opers[1], op.opers[2], rootcanmut, "or ")
	end,

	["&&"] = function (errtok, op, rootcanmut)
		local out = locallabel()

		local rd = getmutreg(rootcanmut)

		if not rd then return false end

		local reg1 = cg.expr(op.opers[2], false, false, false, rootcanmut, false)

		if not reg1 then return false end

		if reg1 == curfn.mutreg then
			rootcanmut = false
		end

		if reg1.n ~= rd.n then
			text("\tmov "..rd.n..", "..reg1.n)
		end

		text("\tcmp "..rd.n..", 0")
		text("\tifz rjmp "..out)

		local reg2 = cg.expr(op.opers[1], false, false, false, rootcanmut, false)

		if not reg2 then return false end

		if reg2.n ~= rd.n then
			text("\tmov "..rd.n..", "..reg2.n)
		end

		text(out..":")

		freeofp(rd, reg1, reg2)

		return rd
	end,

	["retvalue"] = function (errtok, op, rootcanmut)
		return op.reg
	end,

	["alloc"] = function (errtok, op, rootcanmut)
		local offset = op.opers[1]

		return genarith(errtok, reg_t("sp", "sp", errtok), offset, rootcanmut, "add ")
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

		if not rs then return false end

		local imm2

		if rs.typ == "imm" then
			imm2 = rs.id
		end

		if rd.n ~= ri.n then
			text("\tmov "..rd.n..", "..ri.n)
		end

		if imm2 then
			if (imm2 ~= 0) or (rd.n ~= ri.n) then
				text("\tadd "..rd.n..", "..tostring(rs.id*4))
			else
				freeofp(ri, rd)
			end
		else
			text("\tmov at, "..rs.n)
			text("\tsla at, 2")
			text("\tadd "..rd.n..", at")
		end

		freeofp(rd, rs)

		return rd
	end,
}

function cg.expr(node, allowdirectauto, allowdirectptr, immtoreg, rootcanmut, allowinverse, lockref, superallowdirectptr)
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

		if superallowdirectptr then
			return reg_t(node.ident, "imm", node.errtok)
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

				local out = locallabel()
				local out2 = locallabel()

				text("\tcmp "..ro.n..", 0")
				text("\tifz rjmp "..out)
				text("\tmov "..rd.n..", 0")
				text("\trjmp "..out2)
				text(out..":")
				text("\tmov "..rd.n..", 1")
				text(out2..":")

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

local function mkstore(errtok, dest, src, auto, mnem)
	local rd

	local muted

	rd = cg.expr(dest, auto, false, nil, nil, nil, nil, true)

	if not rd then return false end

	if rd.typ ~= "imm" then
		muted = shouldmut(dest)
	end

	local rtmp

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
		local imm2

		if rs.typ == "imm" then
			imm2 = rs.id
		end

		if rd.typ == "imm" then
			if imm2 then
				text("\tmov."..mnem.." ["..rd.id.."], "..tostring(imm2))
			else
				text("\tmov."..mnem.." ["..rd.id.."], "..rs.n)
			end
		else
			if imm2 then
				text("\tmov."..mnem.." ["..rd.n.."], "..tostring(imm2))
			else
				text("\tmov."..mnem.." ["..rd.n.."], "..rs.n)
			end
		end
	end

	freeof(rd, rs)

	return true
end

local function mkmod(errtok, dest, src, mnem, noncommutative)
	local rcm = shouldmut(dest)

	local rd = mkload(errtok, dest, true, "32", true)

	if not rd then return false end

	rd = genarith(errtok, rd, src, true, mnem, noncommutative)

	if not rd then return false end

	if not mkstore(errtok, dest, rd, true, "32") then return false end

	return true
end

local function conditional(cond, out, inv, lockref)
	-- TODO make this generate nicer branches

	local e = ralloc(cond.errtok)

	if not e then return false end

	local rs = retone(cond, e, true, lockref)

	if not rs then return false end

	if (rs.typ ~= "imm") then
		if not e.muted then
			text("\tmov "..e.n..", "..rs.n)
		end

		text("\tcmp "..e.n..", 0")
	end

	if rs.typ ~= "imm" then
		if rs.inverse then
			rs.inverse = nil
			if inv then
				text("\nifz rjmp "..out)
			else
				text("\tifnz rjmp "..out)
			end
		else
			if inv then
				text("\tifnz rjmp "..out)
			else
				text("\tifz rjmp "..out)
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

			text("\tmov "..e.n..", "..r.reg.n)

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
		return mkstore(errtok, op.opers[1], op.opers[2], true, "32")
	end,
	["si"] = function (errtok, op)
		return mkstore(errtok, op.opers[1], op.opers[2], false, "16")
	end,
	["sb"] = function (errtok, op)
		return mkstore(errtok, op.opers[1], op.opers[2], false, "8")
	end,

	["+="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], "add ")
	end,
	["-="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], "sub ", true)
	end,

	["*="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], "mul ")
	end,
	["/="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], "div ", true)
	end,

	["%="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], "rem ", true)
	end,

	[">>="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], "srl ", true)
	end,
	["<<="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], "sla ", true)
	end,

	["&="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], "and ")
	end,

	["|="] = function (errtok, op)
		return mkmod(errtok, op.opers[1], op.opers[2], "or ")
	end,

	["return"] = function (errtok, op)
		text("\trjmp .epilogue")

		return true
	end,

	["break"] = function (errtok, op)
		text("\trjmp "..wpushdown[#wpushdown])

		return true
	end,

	["continue"] = function (errtok, op)
		text("\trjmp "..wcpushdown[#wcpushdown])

		return true
	end,

	["call"] = function (errtok, op)
		if not flushincirco() then return false end

		local extraargs = 0

		local extraret = 0

		if #op.rets > 4 then
			extraret = #op.rets - 4
		end

		local an

		if op.fn.varin then
			text("\tmov a0, "..op.argvs)
			an = 1
		else
			an = 0
		end

		if #op.fin > 4 then
			extraargs = #op.fin - 4 + an
		end

		local savareasize = math.max(extraargs+#op.argv, extraret)*4

		if savareasize-((extraargs+#op.argv)*4) > 0 then
			text("\tsub sp, "..savareasize-((extraargs+#op.argv)*4))
		end

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
					text("\tmov "..e.n..", "..r.n)
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

				local imm2

				if r.typ == "imm" then
					imm2 = r.id
				end

				if imm2 then
					text("\tpush "..tostring(imm2))
				else
					text("\tpush "..r.n)
				end

				freeof(r)
			end
		end

		for i = #op.argv, 1, -1 do
			local fa = op.argv[i]

			local r = cg.expr(fa.node, false, false, false)

			if not r then return false end

			local imm2

			if r.typ == "imm" then
				imm2 = r.id
			end

			if imm2 then
				text("\tpush "..tostring(imm2))
			else
				text("\tpush "..r.n)
			end

			freeof(r)
		end

		if op.ptr then
			local r = cg.expr(op.ptr, false, false, true)

			if not r then return false end

			text("\tcall "..r.n)

			freeof(r)
		else
			text("\tcall "..op.fn.ident)
		end

		local vn = 0

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

					text("\tpop "..fa.reg.n)
				end

				fa.reg.incirco = true

				curfn.incirco[#curfn.incirco + 1] = fa
			elseif vn then
				vn = vn + 1

				if vn > 3 then
					vn = nil
				end
			else
				text("\tpop at")
			end
		end

		if savareasize-(extraret*4) > 0 then
			text("\tadd sp, "..savareasize-(extraret*4))
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
			text("\trjmp "..loop)
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
				text("\trjmp "..satisfied)

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

	if not textsections[curfn.section] then
		textsections[curfn.section] = ".section "..curfn.section.."\n"
		rodatasections[curfn.section] = ""
		textsectionsi[#textsectionsi+1] = curfn.section
	end

	if func.varin then
		func.argvoff = ralloc(func.errtok, true, true)

		if not func.argvoff then
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

	local otext = textsections[curfn.section]

	textsections[curfn.section] = ""

	-- compile root block
	if not cg.block(func.block) then return false end

	-- switch text
	local fntext = textsections[curfn.section]
	textsections[curfn.section] = otext

	text(func.name..":")
	if func.public then
		text(".global "..func.name)
	end

	local saved = 0

	for i = 0, SAVEMAX do
		if func.saved[i] then
			text("\tpush s"..tostring(i))
			saved = saved + 1
		end
	end

	local ac = 0

	if func.varin then
		ac = 1
	end

	local popped = 0
	local savedsz = 0

	for i = #func.fin, 1, -1 do
		local s = func.symb[func.fin[i]]

		--print(func.fin[i], s.reg.n)

		text("\tmov "..s.reg.n..", a"..tostring(ac))
		ac = ac + 1

		if (ac == 4) and (i ~= 1) then
			savedsz = saved*4+4

			text("\tadd sp, "..savedsz)
			popped = 0

			for j = 1, i-1 do
				s = func.symb[func.fin[j]]

				text("\tpop "..s.reg.n)
				popped = popped + 1
			end

			savedsz = savedsz + popped*4

			break
		end
	end

	local ac = 0

	if func.varin then
		local argcs = func.symb["argc"]

		text("\tmov "..argcs.reg.n..", a0")
		text("\tmov "..func.argvoff.n..", sp")

		if savedsz == 0 then
			text("\tadd "..func.argvoff.n..", "..saved*4+4)
		end
	end

	if savedsz + func.allocated > 0 then
		text("\tsub sp, " .. savedsz + func.allocated)
	end

	-- append fn text
	textsections[curfn.section] = textsections[curfn.section] .. fntext

	-- generate epilogue

	text(".epilogue:")

	local vc = 0

	local reached = false

	for i = 1, #func.out do
		local s = func.symb[func.out[i]]

		if not reached then
			text("\tmov a"..tostring(vc)..", "..s.reg.n)
			vc = vc + 1

			if (vc == 4) and (#func.out > 4) then
				print((#func.out-4)*4, func.name)
				text("\tadd sp, ".. savedsz + func.allocated + (#func.out-4)*4 + 4)

				reached = true
			end
		else
			s = func.symb[func.out[#func.out-i+4+1]]

			text("\tpush "..s.reg.n)
		end
	end

	if reached then
		text("\tsub sp, ".. savedsz+4)
	end

	if func.allocated > 0 then
		text("\tadd sp, "..func.allocated)
	end

	for i = SAVEMAX, 0, -1 do
		if func.saved[i] then
			text("\tpop s"..tostring(i))
		end
	end

	text("\tret")

	curfn = nil

	return true
end

function cg.gen(edefs, public, extern, asms, const)
	if not edefs then return false end

	defs = edefs

	textsections["text"] = ".section text\n"
	rodatasections["text"] = ""
	textsectionsi[1] = "text"

	datasection = ".section data\n"

	bsssection = ".section bss\n"

	local defsection = ""

	labln = 0

	--tprint(defs)

	for k,v in pairs(extern) do
		defsection = defsection .. ".extern "..k.."\n"
	end

	for k,v in pairs(const) do
		if not extern[k] then
			defsection = defsection .. ".define "..k.." "..tostring(v).."\n"
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
		textsections["text"] = textsections["text"] .. asms[i] .. "\n"
	end

	for k,v in pairs(public) do
		bss(".global "..k)
	end

	local texts = ""

	for k,v in ipairs(textsectionsi) do
		texts = texts .. textsections[v] .. rodatasections[v] .. ".align 4\n"
	end

	return defsection .. texts .. datasection .. bsssection
end

return cg