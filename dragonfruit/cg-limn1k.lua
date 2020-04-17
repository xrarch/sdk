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

local framepushdown = {}

local regcount = 30

local topframe = {}
topframe.regs = {}

local thisframe

local cblock

local function rs(r)
	if not r then error("code gen bug") end

	return "r"..tostring(r)
end

local DIRECT,REGISTER,LABEL = 1,2,3

function codegen.frame(parent, clone)
	local f = {}

	f.regs = {}

	f.stack = {}

	f.used = {}

	f.scratch = {}

	for i = 0, regcount do
		f.regs[i] = parent.regs[i]
	end

	if clone then
		f.cloned = true

		for k,v in pairs(parent.stack) do
			local e = {}

			e.method = v.method
			e.value = v.value
			e.rvalue = v.rvalue
			e.auto = v.auto
			e.mutable = v.mutable

			f.stack[k] = e
		end

		for k,v in pairs(parent.used) do
			f.used[k] = v
		end

		for k,v in pairs(parent.scratch) do
			f.scratch[k] = v
		end
	end

	function f.alloc(start, last)
		start = start or 0
		last = last or regcount

		for i = start, last do
			if f.regs[i] then
				f.regs[i] = false

				return i
			end
		end
	end

	function f.allocscratch()
		local r = f.alloc()

		if r > 5 then
			if not f.used[r] then
				f.scratch[#f.scratch + 1] = r

				cg:code("push "..rs(r))

				f.used[r] = true
			end
		end

		if not r then error("code generator flaw") end

		return r
	end

	function f.release(r)
		if (not cproc.ralloc[r])  then
			f.regs[r] = true
		end
	end

	function f.mutate(o)
		if o.mutable then
			o.rvalue = o.value

			o.auto = false
		end
	end

	function f.push(thing)
		f.stack[#f.stack + 1] = thing
	end

	function f.makeconst(c)
		local e = {}

		e.method = DIRECT

		e.value = c

		return e
	end

	function f.makereg(r, auto)
		local e = {}

		e.method = REGISTER

		e.value = r

		e.rvalue = r

		e.auto = auto

		return e
	end

	local function pull()
		if #f.stack > 0 then
			return table.remove(f.stack, #f.stack)
		end

		local r = f.allocscratch()

		local e = {}

		if r then
			e = f.makereg(r)

			cg:code("popv r5, "..rs(r))
		end

		return e
	end

	function f.pop(reglabels, mutable)
		if #f.stack > 0 then
			local top = table.remove(f.stack, #f.stack)

			if (not reglabels) and (top.method == DIRECT) and (type(top.value) ~= "number") then
				top.method = REGISTER

				local c = top.value

				top.value = f.allocscratch()

				top.rvalue = top.value

				cg:code("li "..rs(top.value)..", "..c)
			elseif (top.method == REGISTER) and (top.auto) and (mutable) then
				top.rvalue = top.value

				top.value = f.allocscratch()

				top.mutable = true
			end

			return top
		end

		local r = f.allocscratch()

		local e = {}

		if r then
			e = f.makereg(r)

			cg:code("popv r5, "..rs(r))
		end

		return e
	end

	function f.flush(drr)
		for k,v in ipairs(f.stack) do
			if v.method == DIRECT then
				cg:code("pushvi r5, "..tostring(v.value))
			elseif v.method == REGISTER then
				cg:code("pushv r5, r"..tostring(v.value))
				f.release(v.value)
			end
		end

		f.stack = {}

		if not drr then
			for i = #f.scratch, 1, -1 do
				f.release(f.scratch[i])

				cg:code("pop "..rs(f.scratch[i]))
			end

			f.scratch = {}

			f.used = {}
		end
	end

	function f.result(...)
		local e = {}

		e.method = DIRECT

		for k,v in ipairs({...}) do
			if v.method ~= DIRECT then
				e.method = REGISTER

				break
			end
		end

		if (e.method == REGISTER) then
			e.value = f.allocscratch()

			e.rvalue = e.value
		end

		return e
	end

	function f.dup()
		local top = pull()

		local e = {}

		e.method = top.method

		if top.method == DIRECT then
			e.value = top.value
		elseif top.method == REGISTER then
			e.value = f.allocscratch()

			e.rvalue = e.value

			cg:code("mov "..rs(e.value)..", "..rs(top.value))
		end

		f.stack[#f.stack + 1] = top
		f.stack[#f.stack + 1] = e
	end

	function f.swap()
		local w = f.stack[#f.stack - 1]
		f.stack[#f.stack - 1] = f.stack[#f.stack]
		f.stack[#f.stack] = w
	end

	function f.drop()
		local top = f.pop(true, false)

		if top.method == REGISTER then
			f.release(top.value)
		end
	end

	return f
end

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

local cmptable = {
	[REGISTER] = {
		[REGISTER] = function (op1, op2, c)
			cg:code("cmp "..rs(op1.value)..", "..rs(op2.value))

			thisframe.release(op1.value)
			thisframe.release(op2.value)
		end,
		[DIRECT] = function (op1, op2, c)
			cg:code("cmpi "..rs(op1.value)..", "..tostring(op2.value))

			thisframe.release(op1.value)
		end,
	},
	[DIRECT] = {
		[REGISTER] = function (op1, op2, c)
			if not c then
				local r = thisframe.allocscratch()

				cg:code("li "..rs(r)..", "..tostring(op1.value))
				cg:code("cmp "..rs(r)..", "..rs(op2.value))

				thisframe.release(r)
				thisframe.release(op2.value)
			else
				cg:code("cmpi "..rs(op2.value)..", "..tostring(op1.value))
				thisframe.release(op2.value)
			end
		end,
		[DIRECT] = function (op1, op2, c)
			error("should be case-by-case, code generator bug")
		end,
	}
}

local cmpstable = {
	[REGISTER] = {
		[REGISTER] = function (op1, op2, c)
			cg:code("cmps "..rs(op1.value)..", "..rs(op2.value))

			thisframe.release(op1.value)
			thisframe.release(op2.value)
		end,
		[DIRECT] = function (op1, op2, c)
			cg:code("cmpsi "..rs(op1.value)..", "..tostring(op2.value))

			thisframe.release(op1.value)
		end,
	},
	[DIRECT] = {
		[REGISTER] = function (op1, op2, c)
			if not c then
				local r = thisframe.allocscratch()

				cg:code("li "..rs(r)..", "..tostring(op1.value))
				cg:code("cmps "..rs(r)..", "..rs(op2.value))

				thisframe.release(r)
				thisframe.release(op2.value)
			else
				cg:code("cmpsi "..rs(op2.value)..", "..tostring(op1.value))
				thisframe.release(op2.value)
			end
		end,
		[DIRECT] = function (op1, op2, c)
			error("should be case-by-case, code generator bug")
		end,
	}
}

local opstable = {
	[REGISTER] = {
		[REGISTER] = function (rr, rd, d, op1, op2, c)
			cg:code(rr.." "..rs(d)..", "..rs(op1.value)..", "..rs(op2.value))

			thisframe.release(op1.value)
			thisframe.release(op2.value)
		end,
		[DIRECT] = function (rr, rd, d, op1, op2, c)
			cg:code(rd.." "..rs(d)..", "..rs(op1.value)..", "..tostring(op2.value))

			thisframe.release(op1.value)
		end,
	},
	[DIRECT] = {
		[REGISTER] = function (rr, rd, d, op1, op2, c)
			if not c then
				cg:code("li "..rs(d)..", "..tostring(op1.value))
				cg:code(rr.." "..rs(d)..", "..rs(d)..", "..rs(op2.value))
			else
				cg:code(rd.." "..rs(d)..", "..rs(op2.value)..", "..tostring(op1.value))
				thisframe.release(op2.value)
			end
		end,
		[DIRECT] = function (rr, rd, d, op1, op2, c)
			error("should be case-by-case, code generator bug")
		end,
	}
}

local cdummy = 0

local prim_ops = {
	["return"] = function (rn)
		local e = thisframe

		codegen.fret()

		codegen.setframe(e)
	end,
	["break"] = function (rn)
		if #bpushdown == 0 then
			cerror(rn, "can't use break outside of a block")
			return true -- this is an error here, though errors are usually falsey, this is to make this big table a bit more concise by removing all the return trues
		end

		thisframe.flush()

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
		local c = thisframe.pop(true)

		thisframe.flush(true)

		if c.method == DIRECT then
			cg:code("call "..tostring(c.value))
		elseif c.method == REGISTER then
			cg:code("pushi ._df_cleave_"..tostring(cdummy))

			cg:code("br "..rs(c.value))

			-- thisframe.release(c.value)
			-- got released when we flush()ed

			cg:code("._df_cleave_"..tostring(cdummy)..":")

			cdummy = cdummy + 1
		end
	end,
	["+="] = function (rn)
		local dest = thisframe.pop(true)
		local src = thisframe.pop(true)

		local dc = thisframe.allocscratch()

		if dest.method == DIRECT then
			cg:code("lri.l "..rs(dc)..", "..tostring(dest.value))
		elseif dest.method == REGISTER then
			cg:code("lrr.l "..rs(dc)..", "..rs(dest.value))
		end

		if src.method == DIRECT then
			cg:code("addi "..rs(dc)..", "..rs(dc)..", "..tostring(src.value))
		elseif src.method == REGISTER then
			cg:code("add "..rs(dc)..", "..rs(dc)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		if dest.method == DIRECT then
			cg:code("sir.l "..tostring(dest.value)..", "..rs(dc))
		elseif dest.method == REGISTER then
			cg:code("srr.l "..rs(dest.value)..", "..rs(dc))

			thisframe.release(dest.value)
		end

		thisframe.release(dc)
	end,
	["-="] = function (rn)
		local dest = thisframe.pop(true)
		local src = thisframe.pop(true)

		local dc = thisframe.allocscratch()

		if dest.method == DIRECT then
			cg:code("lri.l "..rs(dc)..", "..tostring(dest.value))
		elseif dest.method == REGISTER then
			cg:code("lrr.l "..rs(dc)..", "..rs(dest.value))
		end

		if src.method == DIRECT then
			cg:code("subi "..rs(dc)..", "..rs(dc)..", "..tostring(src.value))
		elseif src.method == REGISTER then
			cg:code("sub "..rs(dc)..", "..rs(dc)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		if dest.method == DIRECT then
			cg:code("sir.l "..tostring(dest.value)..", "..rs(dc))
		elseif dest.method == REGISTER then
			cg:code("srr.l "..rs(dest.value)..", "..rs(dc))

			thisframe.release(dest.value)
		end

		thisframe.release(dc)
	end,
	["*="] = function (rn)
		local dest = thisframe.pop(true)
		local src = thisframe.pop(true)

		local dc = thisframe.allocscratch()

		if dest.method == DIRECT then
			cg:code("lri.l "..rs(dc)..", "..tostring(dest.value))
		elseif dest.method == REGISTER then
			cg:code("lrr.l "..rs(dc)..", "..rs(dest.value))
		end

		if src.method == DIRECT then
			cg:code("muli "..rs(dc)..", "..rs(dc)..", "..tostring(src.value))
		elseif src.method == REGISTER then
			cg:code("mul "..rs(dc)..", "..rs(dc)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		if dest.method == DIRECT then
			cg:code("sir.l "..tostring(dest.value)..", "..rs(dc))
		elseif dest.method == REGISTER then
			cg:code("srr.l "..rs(dest.value)..", "..rs(dc))

			thisframe.release(dest.value)
		end

		thisframe.release(dc)
	end,
	["/="] = function (rn)
		local dest = thisframe.pop(true)
		local src = thisframe.pop(true)

		local dc = thisframe.allocscratch()

		if dest.method == DIRECT then
			cg:code("lri.l "..rs(dc)..", "..tostring(dest.value))
		elseif dest.method == REGISTER then
			cg:code("lrr.l "..rs(dc)..", "..rs(dest.value))
		end

		if src.method == DIRECT then
			cg:code("divi "..rs(dc)..", "..rs(dc)..", "..tostring(src.value))
		elseif src.method == REGISTER then
			cg:code("div "..rs(dc)..", "..rs(dc)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		if dest.method == DIRECT then
			cg:code("sir.l "..tostring(dest.value)..", "..rs(dc))
		elseif dest.method == REGISTER then
			cg:code("srr.l "..rs(dest.value)..", "..rs(dc))

			thisframe.release(dest.value)
		end

		thisframe.release(dc)
	end,
	["%="] = function (rn)
		local dest = thisframe.pop(true)
		local src = thisframe.pop(true)

		local dc = thisframe.allocscratch()

		if dest.method == DIRECT then
			cg:code("lri.l "..rs(dc)..", "..tostring(dest.value))
		elseif dest.method == REGISTER then
			cg:code("lrr.l "..rs(dc)..", "..rs(dest.value))
		end

		if src.method == DIRECT then
			cg:code("modi "..rs(dc)..", "..rs(dc)..", "..tostring(src.value))
		elseif src.method == REGISTER then
			cg:code("mod "..rs(dc)..", "..rs(dc)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		if dest.method == DIRECT then
			cg:code("sir.l "..tostring(dest.value)..", "..rs(dc))
		elseif dest.method == REGISTER then
			cg:code("srr.l "..rs(dest.value)..", "..rs(dc))

			thisframe.release(dest.value)
		end

		thisframe.release(dc)
	end,
	["bswap"] = function (rn)
		local n = thisframe.pop(false, true)

		if n.method == DIRECT then
			n.value = 
				bor(rshift(n.value, 24),
					bor(band(lshift(n.value, 8), 0xFF0000),
						bor(band(rshift(n.value, 8), 0xFF00),
							band(lshift(n.value, 24), 0xFF000000))))
		elseif n.method == REGISTER then
			cg:code("bswap "..rs(n.value)..", "..rs(n.rvalue))

			n.mutate()
		end

		thisframe.push(n)
	end,
	["=="] = function (rn)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value == src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmptable[src1.method][src2.method](src1, src2, true)

			cg:code("andi "..rs(r.value)..", rf, 0x1")
		end

		thisframe.push(r)
	end,
	["~="] = function (rn)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value ~= src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmptable[src1.method][src2.method](src1, src2, true)

			cg:code("not "..rs(r.value)..", rf")
			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")
		end

		thisframe.push(r)
	end,
	[">"] = function (rn)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value > src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmptable[src1.method][src2.method](src1, src2)

			cg:code("rshi "..rs(r.value)..", rf, 0x1")
			cg:code("not "..rs(r.value)..", "..rs(r.value))

			local sr = thisframe.allocscratch()

			cg:code("not "..rs(sr)..", rf")
			cg:code("and "..rs(r.value)..", "..rs(r.value)..", "..rs(sr))
			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")

			thisframe.release(sr)
		end

		thisframe.push(r)
	end,
	["<"] = function (rn)
		local src2 = thisframe.pop(true)
		local src1 = thisframe.pop(true)

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value < src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmptable[src1.method][src2.method](src1, src2)

			cg:code("rshi "..rs(r.value)..", rf, 0x1")
			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")
		end

		thisframe.push(r)
	end,
	[">="] = function (rn) -- not carry
		local src2 = thisframe.pop(true)
		local src1 = thisframe.pop(true)

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value >= src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmptable[src1.method][src2.method](src1, src2)

			cg:code("rshi "..rs(r.value)..", rf, 0x1")
			cg:code("not "..rs(r.value)..", "..rs(r.value))
			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")
		end

		thisframe.push(r)
	end,
	["<="] = function (rn) -- carry or zero
		local src2 = thisframe.pop(true)
		local src1 = thisframe.pop(true)

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value <= src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmptable[src1.method][src2.method](src1, src2)

			cg:code("rshi "..rs(r.value)..", rf, 0x1")
			cg:code("ior "..rs(r.value)..", rf, "..rs(r.value))
			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")
		end

		thisframe.push(r)
	end,
	["s>"] = function (rn)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value > src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmpstable[src1.method][src2.method](src1, src2)

			cg:code("rshi "..rs(r.value)..", rf, 0x1")
			cg:code("not "..rs(r.value)..", "..rs(r.value))

			local sr = thisframe.allocscratch()

			cg:code("not "..rs(sr)..", rf")
			cg:code("and "..rs(r.value)..", "..rs(r.value)..", "..rs(sr))
			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")

			thisframe.release(sr)
		end

		thisframe.push(r)
	end,
	["s<"] = function (rn)
		local src2 = thisframe.pop(true)
		local src1 = thisframe.pop(true)

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value < src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmpstable[src1.method][src2.method](src1, src2)

			cg:code("rshi "..rs(r.value)..", rf, 0x1")
			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")
		end

		thisframe.push(r)
	end,
	["s>="] = function (rn) -- not carry
		local src2 = thisframe.pop(true)
		local src1 = thisframe.pop(true)

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value >= src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmpstable[src1.method][src2.method](src1, src2)

			cg:code("rshi "..rs(r.value)..", rf, 0x1")
			cg:code("not "..rs(r.value)..", "..rs(r.value))
			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")
		end

		thisframe.push(r)
	end,
	["s<="] = function (rn) -- carry or zero
		local src2 = thisframe.pop(true)
		local src1 = thisframe.pop(true)

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			if src1.value <= src2.value then
				r.value = 1
			else
				r.value = 0
			end
		elseif r.method == REGISTER then
			cmpstable[src1.method][src2.method](src1, src2)

			cg:code("rshi "..rs(r.value)..", rf, 0x1")
			cg:code("ior "..rs(r.value)..", rf, "..rs(r.value))
			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")
		end

		thisframe.push(r)
	end,
	["~"] = function (rn)
		local o = thisframe.pop(true, true)

		if o.method == DIRECT then
			o.value = bnot(o.value)
		elseif o.method == REGISTER then
			cg:code("not "..rs(o.value)..", "..rs(o.rvalue))

			thisframe.mutate(o)
		end

		thisframe.push(o)
	end,
	["~~"] = function (rn)
		local o = thisframe.pop(true, true)

		if o.method == DIRECT then
			o.value = band(bnot(o.value), 1)
		elseif o.method == REGISTER then
			cg:code("not "..rs(o.value)..", "..rs(o.rvalue))
			cg:code("andi "..rs(o.value)..", "..rs(o.value)..", 1")

			thisframe.mutate(o)
		end

		thisframe.push(o)
	end,
	["|"] = function (rn)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = bor(src1.value, src2.value)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("ior", "iori", r.value, src1, src2, true)
		end

		thisframe.push(r)
	end,
	["||"] = function (rn)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = band(bor(src1.value, src2.value), 1)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("ior", "iori", r.value, src1, src2, true)

			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")
		end

		thisframe.push(r)
	end,
	["&"] = function (rn)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = band(src1.value, src2.value)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("and", "andi", r.value, src1, src2, true)
		end

		thisframe.push(r)
	end,
	["&&"] = function (rn)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = band(band(src1.value, src2.value), 1)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("and", "andi", r.value, src1, src2, true)

			cg:code("andi "..rs(r.value)..", "..rs(r.value)..", 0x1")
		end

		thisframe.push(r)
	end,
	[">>"] = function (rn)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = rshift(src1.value, src2.value)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("rsh", "rshi", r.value, src1, src2)
		end

		thisframe.push(r)
	end,
	["<<"] = function (rn)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = lshift(src1.value, src2.value)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("lsh", "lshi", r.value, src1, src2)
		end

		thisframe.push(r)
	end,
	["dup"] = function (rn)
		thisframe.dup()
	end,
	["swap"] = function (rn)
		thisframe.swap()
	end,
	["drop"] = function (rn)
		thisframe.drop()
	end,
	["+"] = function (rn)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = src1.value + src2.value
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("add", "addi", r.value, src1, src2, true)
		end

		thisframe.push(r)
	end,
	["-"] = function (rn)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = src1.value - src2.value
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("sub", "subi", r.value, src1, src2)
		end

		thisframe.push(r)
	end,
	["*"] = function (rn)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = src1.value * src2.value
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("mul", "muli", r.value, src1, src2, true)
		end

		thisframe.push(r)
	end,
	["/"] = function (rn)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = math.floor(src1.value / src2.value)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("div", "divi", r.value, src1, src2)
		end

		thisframe.push(r)
	end,
	["%"] = function (rn)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = src1.value % src2.value
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("mod", "modi", r.value, src1, src2)
		end

		thisframe.push(r)
	end,
	["gb"] = function (rn)
		local o = thisframe.pop(true, true)

		if o.method == DIRECT then
			local r0 = thisframe.allocscratch()

			cg:code("lri.b "..rs(r0)..", "..tostring(o.value))

			o = thisframe.makereg(r0)
		elseif o.method == REGISTER then
			cg:code("lrr.b "..rs(o.value)..", "..rs(o.rvalue))

			thisframe.mutate(o)
		end

		thisframe.push(o)
	end,
	["gi"] = function (rn)
		local o = thisframe.pop(true, true)

		if o.method == DIRECT then
			local r0 = thisframe.allocscratch()

			local rs0 = rs(r0)

			cg:code("lri.i "..rs0..", "..tostring(o.value))

			o = thisframe.makereg(r0)
		elseif o.method == REGISTER then
			cg:code("lrr.i "..rs(o.value)..", "..rs(o.rvalue))

			thisframe.mutate(o)
		end

		thisframe.push(o)
	end,
	["@"] = function (rn)
		local o = thisframe.pop(true, true)

		if o.method == DIRECT then
			local r0 = thisframe.allocscratch()

			local rs0 = rs(r0)

			cg:code("lri.l "..rs0..", "..tostring(o.value))

			o = thisframe.makereg(r0)
		elseif o.method == REGISTER then
			cg:code("lrr.l "..rs(o.value)..", "..rs(o.rvalue))

			thisframe.mutate(o)
		end

		thisframe.push(o)
	end,
	["sb"] = function (rn)
		local op1 = thisframe.pop(true)
		local op2 = thisframe.pop(true)

		if op1.method == DIRECT then
			if op2.method == DIRECT then
				cg:code("sii.b "..tostring(op1.value)..", "..tostring(op2.value))
			elseif op2.method == REGISTER then
				cg:code("sir.b "..tostring(op1.value)..", "..rs(op2.value))

				thisframe.release(op2.value)
			end
		elseif op1.method == REGISTER then
			if op2.method == DIRECT then
				cg:code("sri.b "..rs(op1.value)..", "..tostring(op2.value))
			elseif op2.method == REGISTER then
				cg:code("srr.b "..rs(op1.value)..", "..rs(op2.value))

				thisframe.release(op2.value)
			end

			thisframe.release(op1.value)
		end
	end,
	["si"] = function (rn)
		local op1 = thisframe.pop(true)
		local op2 = thisframe.pop(true)

		if op1.method == DIRECT then
			if op2.method == DIRECT then
				cg:code("sii.i "..tostring(op1.value)..", "..tostring(op2.value))
			elseif op2.method == REGISTER then
				cg:code("sir.i "..tostring(op1.value)..", "..rs(op2.value))

				thisframe.release(op2.value)
			end
		elseif op1.method == REGISTER then
			if op2.method == DIRECT then
				cg:code("sri.i "..rs(op1.value)..", "..tostring(op2.value))
			elseif op2.method == REGISTER then
				cg:code("srr.i "..rs(op1.value)..", "..rs(op2.value))

				thisframe.release(op2.value)
			end

			thisframe.release(op1.value)
		end
	end,
	["!"] = function (rn)
		local op1 = thisframe.pop(true)
		local op2 = thisframe.pop(true)

		if op1.method == DIRECT then
			if op2.method == DIRECT then
				cg:code("sii.l "..tostring(op1.value)..", "..tostring(op2.value))
			elseif op2.method == REGISTER then
				cg:code("sir.l "..tostring(op1.value)..", "..rs(op2.value))

				thisframe.release(op2.value)
			end
		elseif op1.method == REGISTER then
			if op2.method == DIRECT then
				cg:code("sri.l "..rs(op1.value)..", "..tostring(op2.value))
			elseif op2.method == REGISTER then
				cg:code("srr.l "..rs(op1.value)..", "..rs(op2.value))

				thisframe.release(op2.value)
			end

			thisframe.release(op1.value)
		end
	end,
	["bitget"] = function (rn) -- (v bit -- bit)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = band(band(src1.value, src2.value), 1)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("rsh", "rshi", r.value, src1, src2)

			cg:code("andi "..rs(r.value)..", rf, 0x1")
		end

		thisframe.push(r)
	end,
	["bitset"] = function (rn) -- (v bit -- v)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = band(band(src1.value, src2.value), 1)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("bset", "bseti", r.value, src1, src2)
		end

		thisframe.push(r)
	end,
	["bitclear"] = function (rn) -- (v bit -- v)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = band(band(src1.value, src2.value), 1)
		elseif r.method == REGISTER then
			opstable[src1.method][src2.method]("bclr", "bclri", r.value, src1, src2)
		end

		thisframe.push(r)
	end,

	["_flush_all"] = function (rn)
		thisframe.flush()
	end,
	["_flush"] = function (rn)
		thisframe.flush(true)
	end,
}

local auto_ops = {
	["@"] = function (rn)
		thisframe.push(thisframe.makereg(rn, true), true)
	end,
	["!"] = function (rn)
		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("mov "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			cg:code("li "..rs(rn)..", "..tostring(c.value))
		end
	end,
	["+="] = function (rn)
		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("add "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			cg:code("addi "..rs(rn)..", "..rs(rn)..", "..tostring(c.value))
		end
	end,
	["-="] = function (rn)
		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("sub "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			cg:code("subi "..rs(rn)..", "..rs(rn)..", "..tostring(c.value))
		end
	end,
	["*="] = function (rn)
		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("mul "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			cg:code("muli "..rs(rn)..", "..rs(rn)..", "..tostring(c.value))
		end
	end,
	["/="] = function (rn)
		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("div "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			cg:code("divi "..rs(rn)..", "..rs(rn)..", "..tostring(c.value))
		end
	end,
	["%="] = function (rn)
		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("mod "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			cg:code("modi "..rs(rn)..", "..rs(rn)..", "..tostring(c.value))
		end
	end
}

local inn = 0

function codegen.genif(ifn)
	local out = "._df_ifout_"..tostring(inn)

	inn = inn + 1

	local nopedone = false

	for k,v in ipairs(ifn.ifs) do
		local nex = "._df_ifnex_"..tostring(inn)

		inn = inn + 1

		local cframe = codegen.frame(thisframe)

		codegen.setframe(cframe)

		codegen.block(v.conditional)

		local c = thisframe.pop()

		if c.method == DIRECT then
			if c.value ~= 0 then
				codegen.block(v.body)

				codegen.restoreframe()

				nopedone = true
				break
			end
		elseif c.method == REGISTER then
			cg:code("cmpi "..rs(c.value)..", 0")

			local nf = codegen.frame(thisframe, true)

			cg:code("be "..nex)

			codegen.block(v.body)

			codegen.restoreframe()

			if (k < #ifn.ifs) or (ifn.default) then
				cg:code("b "..out)
			end

			cg:code(nex..":")

			nf.flush()
		end
	end

	if (ifn.default) and (not nopedone) then
		local bframe = codegen.frame(thisframe)

		codegen.setframe(bframe)

		codegen.block(ifn.default)

		codegen.restoreframe()
	end

	if not nopedone then
		cg:code(out..":")
	end

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

	local cframe = codegen.frame(thisframe)

	codegen.setframe(cframe)

	codegen.block(wn.w.conditional)

	local r = cframe.pop()

	if r.method == DIRECT then
		if r.value ~= 0 then
			codegen.block(wn.w.body)

			cg:code("b "..loop)

			cg:code(out..":")

			codegen.restoreframe()
		end
	elseif r.method == REGISTER then
		cg:code("cmpi "..rs(r.value)..", 0")

		cg:code("be "..out)

		codegen.block(wn.w.body)

		cg:code("b "..loop)

		cg:code(out..":")

		codegen.restoreframe()
	end

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
				thisframe.push(thisframe.makeconst(v.name))
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
					thisframe.flush(true)
					cg:code("call "..v.name)
				else
					cerror(v, "attempt to call undeclared procedure "..(v.name or "NULL"))
					return false
				end
			elseif v.tag == "index" then
				if not codegen.block(v.block) then return false end

				local r = thisframe.pop(false, true)

				if r.method == DIRECT then
					local r0 = thisframe.allocscratch()

					local rs0 = rs(r0)

					cg:code("li "..rs0..", "..v.tab.name)
					cg:code("addi "..rs0..", "..rs0..", "..tostring(r.value * 4))

					r = thisframe.makereg(r0)
				elseif r.method == REGISTER then
					cg:code("muli "..rs(r.value)..", "..rs(r.rvalue)..", 4")
					cg:code("addi "..rs(r.value)..", "..rs(r.value)..", "..v.tab.name)

					thisframe.mutate(r)
				end

				thisframe.push(r)
			elseif v.tag == "if" then
				if not codegen.genif(v) then return false end
			elseif v.tag == "while" then
				if not codegen.genwhile(v) then return false end
			elseif v.tag == "asm" then
				if not codegen.asm(v) then return false end
			elseif v.tag == "putstring" then
				local sno = codegen.string(v.name)

				thisframe.push(thisframe.makeconst(sno))
			else
				cerror(v, "weird AST node "..(v.tag or "NULL"))
				return false
			end
		end
	end



	return true
end

function codegen.setframe(frame)
	if (thisframe) and (not frame.cloned) then
		thisframe.flush()
	end

	framepushdown[#framepushdown + 1] = thisframe

	thisframe = frame
end

function codegen.restoreframe()
	thisframe.flush()

	thisframe = framepushdown[#framepushdown]

	framepushdown[#framepushdown] = nil
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

	codegen.restoreframe()

	codegen.restore()

	cg:code("ret")
end

function codegen.procedure(t)
	cg:code(t.name..":")

	if t.public then
		cg:code(".global "..t.name)
	end

	local f = codegen.frame(topframe)

	thisframe = f

	cproc = {}
	cproc.proc = t
	cproc.autos = {}

	cproc.allocr = {}

	cproc.ralloc = {}

	cproc.outo = {}

	local inv = {}

	local ru

	for _,name in ipairs(t.inputso) do
		ru = f.alloc(6)

		if not ru then
			cerror(t, "couldn't allocate input "..name)
			return false
		end

		local rn = "r"..tostring(ru)

		table.insert(inv, 1, rn)

		cproc.autos[name] = ru

		cproc.allocr[#cproc.allocr + 1] = rn

		cproc.ralloc[ru] = true

		ru = ru + 1
	end

	for _,name in pairs(t.outputso) do
		ru = f.alloc(6)

		if not ru then
			cerror(t, "couldn't allocate output "..name)
			return false
		end

		local rn = "r"..tostring(ru)

		cproc.autos[name] = ru

		cproc.allocr[#cproc.allocr + 1] = rn

		cproc.outo[#cproc.outo + 1] = rn

		cproc.ralloc[ru] = true

		ru = ru + 1
	end

	for name,_ in pairs(t.autos) do
		ru = f.alloc(6)

		if not ru then
			cerror(t, "couldn't allocate auto "..name)
			return false
		end

		local rn = "r"..tostring(ru)

		cproc.autos[name] = ru

		cproc.allocr[#cproc.allocr + 1] = rn

		cproc.ralloc[ru] = true

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

	for i = 0, regcount do
		topframe.regs[i] = true
	end

	topframe.regs[5] = false -- dragonfruit stack pointer

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

	return cg.c .. "\n" .. cg.d .. "\n" .. cg.b
end

return codegen