local codegen = {}

local cg = {}

local cproc

local function cerror(t, err)
	print(string.format("dragonc: cg-limn2k: %s:%d: %s", (t.file or "not specified"), (t.line or "not specified"), err))
end

local e_extern

local e_defproc

local bpushdown = {}

local cpushdown = {}

local framepushdown = {}

local regcount = 25

local topframe = {}
topframe.regs = {}

local thisframe

local cblock

local function rs(r)
	if not r then error("code gen bug") end

	return "r"..tostring(r)
end

local function putimm(dest, imm)
	if (type(imm) == "number") and (imm >= 0) then
		if imm < 0x10000 then
			cg:code("li "..rs(dest)..", "..imm)
		elseif band(imm, 0xFFFF) == 0 then
			cg:code("lui "..rs(dest)..", "..imm)
		else
			cg:code("la "..rs(dest)..", "..imm)
		end
	else
		cg:code("la "..rs(dest)..", "..imm)
	end
end

local function imm(im, max)
	if (type(im) == "number") then
		if (im < max) and (im >= 0) then
			return true
		elseif band(im, 0xFFFF) == 0 then
			cg:code("lui at, "..tostring(im))
			return false
		else
			cg:code("la at, "..tostring(im))
			return false
		end
	else
		cg:code("la at, "..im)
		return false
	end
end

local DIRECT,REGISTER,LAZYADDITION = 1,2,3

function codegen.frame(parent, clone)
	local f = {}

	f.regs = {}

	f.stack = {}

	f.used = {}

	f.scratch = {}

	for i = 1, regcount do
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
			e.op1 = v.op1
			e.op2 = v.op2

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

		if not r then error("code generator flaw") end -- ran out of registers to allocate, this means somebody isn't freeing something

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

	function f.invalidreg(r)
		for k,v in ipairs(f.stack) do
			if (v.method == REGISTER) and (v.rvalue == r) then
				if v.mutable then
					cg:code("mov "..rs(v.value)..", "..rs(r))
					f.mutate(v)
				else
					v.value = f.allocscratch()
					v.rvalue = v.value

					cg:code("mov "..rs(v.value)..", "..rs(r))
				end
			end
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

	function f.makelazy(op1, op2)
		local e = {}

		e.method = LAZYADDITION

		e.op1 = op1

		e.op2 = op2

		return e
	end

	local function pull()
		if #f.stack > 0 then
			local top = table.remove(f.stack, #f.stack)

			if top.method == LAZYADDITION then
				top = f.lazyeval(top)
			end

			return top
		end

		local r = f.allocscratch()

		local e = {}

		if r then
			e = f.makereg(r)

			cg:code("lwi.l "..rs(r)..", vs, zero")
		else
			error("aa")
		end

		return e
	end

	function f.pop(reglabels, mutable, invallow, lazyallow)
		if #f.stack > 0 then
			local top = table.remove(f.stack, #f.stack)

			if (not reglabels) and (top.method == DIRECT) and (type(top.value) ~= "number") then
				top.method = REGISTER

				local c = top.value

				top.value = f.allocscratch()

				top.rvalue = top.value

				cg:code("la "..rs(top.value)..", "..c)
			end
			
			if (top.method == REGISTER) and (top.auto) and (mutable) then
				top.rvalue = top.value

				top.value = f.allocscratch()

				top.mutable = true
			end
			
			if (top.inverse) and not (invallow) then
				cg:code("not "..rs(top.value)..", "..rs(top.value))
				top.inverse = false
			end

			if (top.method == LAZYADDITION) and not (lazyallow) then
				top = f.lazyeval(top)
			end

			return top
		end

		local r = f.allocscratch()

		local e = {}

		if r then
			e = f.makereg(r)

			cg:code("lwi.l "..rs(r)..", vs, zero")
		end

		return e
	end

	function f.flush(drr)
		for k,v in ipairs(f.stack) do
			if v.method == LAZYADDITION then
				v = f.lazyeval(v)
			end

			if v.method == DIRECT then
				if type(v.value) == "number" then
					if (v.value < 0x10000) and (v.value >= 0) then
						cg:code("swdi.l vs, "..tostring(v.value))
					elseif band(v.value, 0xFFFF) == 0 then
						cg:code("lui at, "..tostring(v.value))
						cg:code("swd.l vs, zero, at")
					else
						cg:code("la at, "..tostring(v.value))
						cg:code("swd.l vs, zero, at")
					end
				else
					cg:code("la at, "..v.value)
					cg:code("swd.l vs, zero, at")
				end
			elseif v.method == REGISTER then
				cg:code("swd.l vs, zero, r"..tostring(v.value))
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
		local o1 = f.pop(true)
		local o2 = f.pop(true)

		f.push(o1)
		f.push(o2)
	end

	function f.drop()
		local top = f.pop(true, false)

		if top.method == REGISTER then
			f.release(top.value)
		end
	end

	local offmax = {
		["b"] = 128,
		["i"] = 256,
		["l"] = 512,
	}

	function f.store(s, dest, src)
		local r1 = dest.value

		if dest.method == DIRECT then
			r1 = f.allocscratch()
			putimm(r1, dest.value)
		end

		if src.method == DIRECT then
			if type(src.value) == "number" then
				if imm(src.value, 65536) then
					if (src.value > 255) and (s ~= "b") then
						cg:code("si16."..s.." "..rs(r1)..", zero, "..src.value)
					else
						cg:code("si."..s.." "..rs(r1)..", zero, "..src.value)
					end
				else
					cg:code("s."..s.." "..rs(r1)..", zero, at")
				end
			else
				cg:code("la at, "..src.value)
				cg:code("s."..s.." "..rs(r1)..", zero, at")
			end
		else
			cg:code("s."..s.." "..rs(r1)..", zero, "..rs(src.value))
			f.release(src.value)
		end

		f.release(r1)
	end

	function f.loadmut(s, src)
		local r1, r2, im = src.rvalue
		local tr1 = src.value

		local o = src

		if src.method == LAZYADDITION then
			local op1, op2 = src.op1, src.op2

			local rv1, rv2, imv = op1, op2

			if op1.method == DIRECT then
				rv1 = rv2
				imv = op1
			elseif op2.method == DIRECT then
				rv2 = nil
				imv = op2
			end

			if imv then
				if imm(imv.value, offmax[s]) then
					cg:code("lio."..s.." "..rs(rv1.value)..", "..rs(rv1.rvalue)..", "..imv.value)
				else
					cg:code("l."..s.." "..rs(rv1.value)..", "..rs(rv1.rvalue)..", at")
				end
			else
				cg:code("l."..s.." "..rs(rv1.value)..", "..rs(rv1.rvalue)..", "..rs(rv2.rvalue))

				f.mutate(rv2)
				f.release(rv2.value)
			end

			f.mutate(rv1)

			o = rv1
		else
			if src.method == DIRECT then
				r1 = f.allocscratch()
				tr1 = r1
				putimm(r1, src.value)
				o = f.makereg(r1)
			end

			cg:code("l."..s.." "..rs(tr1)..", zero, "..rs(r1))

			f.mutate(src)
		end

		return o
	end

	function f.load(s, src)
		local o = f.makereg(f.allocscratch())

		if src.method == DIRECT then
			putimm(o.value, src.value)
		elseif src.method == REGISTER then
			cg:code("mov "..rs(o.value)..", "..rs(src.rvalue))
			f.release(src.value)
		elseif src.method == LAZYADDITION then
			error("cg bug")
		end

		return f.loadmut(s, o)
	end

	function f.lazyeval(lazy)
		local op1, op2 = lazy.op1, lazy.op2

		local rv1, rv2, imv = op1, op2

		if op1.method == DIRECT then
			rv1 = rv2
			imv = op1
		elseif op2.method == DIRECT then
			rv2 = nil
			imv = op2
		end

		if imv then
			if imm(imv.value, 256) then
				cg:code("addi "..rs(rv1.value)..", "..rs(rv1.rvalue)..", "..imv.value)
			else
				cg:code("add "..rs(rv1.value)..", "..rs(rv1.rvalue)..", at")
			end
		else
			cg:code("add "..rs(rv1.value)..", "..rs(rv1.rvalue)..", "..rs(rv2.rvalue))

			f.release(rv2.value)
			f.mutate(rv2)
		end

		f.mutate(rv1)

		return rv1
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
	cg:bss(".align 4")
	cg:data(".align 4")

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

	cg:bss(".align 4")
	cg:data(".align 4")

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
			cg:code("jal "..tostring(c.value))
		elseif c.method == REGISTER then
			cg:code("jalr "..rs(c.value))
		end
	end,
	["+="] = function (rn)
		local dest = thisframe.pop()
		local src = thisframe.pop(true)

		local dc = thisframe.load("l", dest)

		if src.method == DIRECT then
			if imm(src.value, 0x10000) then
				cg:code("addi.i "..rs(dc.value)..", "..src.value)
			else
				cg:code("add "..rs(dc.value)..", "..rs(dc.value)..", at")
			end
		elseif src.method == REGISTER then
			cg:code("add "..rs(dc.value)..", "..rs(dc.value)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		thisframe.store("l", dest, dc)
	end,
	["-="] = function (rn)
		local dest = thisframe.pop()
		local src = thisframe.pop(true)

		local dc = thisframe.load("l", dest)

		if src.method == DIRECT then
			if imm(src.value, 0x10000) then
				cg:code("subi.i "..rs(dc.value)..", "..src.value)
			else
				cg:code("sub "..rs(dc.value)..", "..rs(dc.value)..", at")
			end
		elseif src.method == REGISTER then
			cg:code("sub "..rs(dc.value)..", "..rs(dc.value)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		thisframe.store("l", dest, dc)
	end,
	["*="] = function (rn)
		local dest = thisframe.pop()
		local src = thisframe.pop(true)

		local dc = thisframe.load("l", dest)

		if src.method == DIRECT then
			if imm(src.value, 0x10000) then
				cg:code("muli.i "..rs(dc.value)..", "..src.value)
			else
				cg:code("mul "..rs(dc.value)..", "..rs(dc.value)..", at")
			end
		elseif src.method == REGISTER then
			cg:code("mul "..rs(dc.value)..", "..rs(dc.value)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		thisframe.store("l", dest, dc)
	end,
	["/="] = function (rn)
		local dest = thisframe.pop()
		local src = thisframe.pop(true)

		local dc = thisframe.load("l", dest)

		if src.method == DIRECT then
			if imm(src.value, 0x10000) then
				cg:code("divi.i "..rs(dc.value)..", "..src.value)
			else
				cg:code("div "..rs(dc.value)..", "..rs(dc.value)..", at")
			end
		elseif src.method == REGISTER then
			cg:code("div "..rs(dc.value)..", "..rs(dc.value)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		thisframe.store("l", dest, dc)
	end,
	["%="] = function (rn)
		local dest = thisframe.pop()
		local src = thisframe.pop(true)

		local dc = thisframe.load("l", dest)

		if src.method == DIRECT then
			if imm(src.value, 0x10000) then
				cg:code("modi.i "..rs(dc.value)..", "..src.value)
			else
				cg:code("mod "..rs(dc.value)..", "..rs(dc.value)..", at")
			end
		elseif src.method == REGISTER then
			cg:code("mod "..rs(dc.value)..", "..rs(dc.value)..", "..rs(src.value))

			thisframe.release(src.value)
		end

		thisframe.store("l", dest, dc)
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("seq "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

			thisframe.release(r1)
			thisframe.release(r2)
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("sne "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

			thisframe.release(r1)
			thisframe.release(r2)
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("slt "..rs(r.value)..", "..rs(r2)..", "..rs(r1))

			thisframe.release(r1)
			thisframe.release(r2)
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("slt "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

			thisframe.release(r1)
			thisframe.release(r2)
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("slt "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

			thisframe.release(r1)
			thisframe.release(r2)

			r.inverse = true
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("slt "..rs(r.value)..", "..rs(r2)..", "..rs(r1))

			thisframe.release(r1)
			thisframe.release(r2)

			r.inverse = true
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("slt.s "..rs(r.value)..", "..rs(r2)..", "..rs(r1))

			thisframe.release(r1)
			thisframe.release(r2)
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("slt.s "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

			thisframe.release(r1)
			thisframe.release(r2)
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("slt.s "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

			thisframe.release(r1)
			thisframe.release(r2)

			r.inverse = true
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
			local r1,r2 = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				r2 = thisframe.allocscratch()
				putimm(r2, src2.value)
			end

			cg:code("slt.s "..rs(r.value)..", "..rs(r2)..", "..rs(r1))

			thisframe.release(r1)
			thisframe.release(r2)

			r.inverse = true
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
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				im = src1.value
				r1 = r2
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("ori "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("or "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("or "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
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
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				im = src1.value
				r1 = r2
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("ori "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("or "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("or "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end

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
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				im = src1.value
				r1 = r2
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("andi "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("and "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("and "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
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
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				im = src1.value
				r1 = r2
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("andi "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("and "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("and "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end

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
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("rshi "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("rsh "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("rsh "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
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
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("lshi "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("lsh "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("lsh "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
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
		local src1 = thisframe.pop(false, true)
		local src2 = thisframe.pop(false, true)

		if (src1.method == DIRECT) and (src2.method == DIRECT) then
			thisframe.push(thisframe.makeconst(src1.value + src2.value))
		else
			thisframe.push(thisframe.makelazy(src1, src2))
		end
	end,
	["-"] = function (rn)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = src1.value - src2.value
		elseif r.method == REGISTER then
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("subi "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("sub "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("sub "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
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
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				im = src1.value
				r1 = r2
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("muli "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("mul "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("mul "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
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
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("divi "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("div "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("div "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
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
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("modi "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("mod "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("mod "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
		end

		thisframe.push(r)
	end,
	["gb"] = function (rn)
		local o = thisframe.pop(true, true, false, true)

		thisframe.push(thisframe.loadmut("b", o))
	end,
	["gi"] = function (rn)
		local o = thisframe.pop(true, true, false, true)

		thisframe.push(thisframe.loadmut("i", o))
	end,
	["@"] = function (rn)
		local o = thisframe.pop(true, true, false, true)

		thisframe.push(thisframe.loadmut("l", o))
	end,
	["sb"] = function (rn)
		local op1 = thisframe.pop(true)
		local op2 = thisframe.pop(true)

		thisframe.store("b", op1, op2)
	end,
	["si"] = function (rn)
		local op1 = thisframe.pop(true)
		local op2 = thisframe.pop(true)

		thisframe.store("i", op1, op2)
	end,
	["!"] = function (rn)
		local op1 = thisframe.pop(true)
		local op2 = thisframe.pop(true)

		thisframe.store("l", op1, op2)
	end,
	["bitget"] = function (rn) -- (v bit -- bit)
		local src2 = thisframe.pop()
		local src1 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = band(rshift(src1.value, src2.value), 1)
		elseif r.method == REGISTER then
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("bgeti "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("bget "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("bget "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
		end

		thisframe.push(r)
	end,
	["bitset"] = function (rn) -- (v bit -- v)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = bor(src2.value, lshift(1, src1.value))
		elseif r.method == REGISTER then
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("bseti "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("bset "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("bset "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
		end

		thisframe.push(r)
	end,
	["bitclear"] = function (rn) -- (v bit -- v)
		local src1 = thisframe.pop()
		local src2 = thisframe.pop()

		local r = thisframe.result(src1, src2)

		if r.method == DIRECT then
			r.value = band(src2.value, bnot(lshift(1, src1.value)))
		elseif r.method == REGISTER then
			local r1,r2,im = src1.value, src2.value

			if src1.method == DIRECT then
				r1 = thisframe.allocscratch()
				putimm(r1, src1.value)
			elseif src2.method == DIRECT then
				im = src2.value
			end

			thisframe.release(r1)

			if im then
				if imm(im, 256) then
					cg:code("bclri "..rs(r.value)..", "..rs(r1)..", "..im)
				else
					cg:code("bclr "..rs(r.value)..", "..rs(r1)..", at")
				end
			else
				cg:code("bclr "..rs(r.value)..", "..rs(r1)..", "..rs(r2))

				thisframe.release(r2)
			end
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
		thisframe.invalidreg(rn)

		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("mov "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			putimm(rn, c.value)
		end
	end,
	["+="] = function (rn)
		thisframe.invalidreg(rn)

		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("add "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			if imm(c.value, 0x10000) then
				cg:code("addi.i "..rs(rn)..", "..tostring(c.value))
			else
				cg:code("add "..rs(rn)..", "..rs(rn)..", at")
			end
		end
	end,
	["-="] = function (rn)
		thisframe.invalidreg(rn)

		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("sub "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			if imm(c.value, 0x10000) then
				cg:code("subi.i "..rs(rn)..", "..tostring(c.value))
			else
				cg:code("sub "..rs(rn)..", "..rs(rn)..", at")
			end
		end
	end,
	["*="] = function (rn)
		thisframe.invalidreg(rn)

		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("mul "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			if imm(c.value, 0x10000) then
				cg:code("muli.i "..rs(rn)..", "..tostring(c.value))
			else
				cg:code("mul "..rs(rn)..", "..rs(rn)..", at")
			end
		end
	end,
	["/="] = function (rn)
		thisframe.invalidreg(rn)

		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("div "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			if imm(c.value, 0x10000) then
				cg:code("divi.i "..rs(rn)..", "..tostring(c.value))
			else
				cg:code("div "..rs(rn)..", "..rs(rn)..", at")
			end
		end
	end,
	["%="] = function (rn)
		thisframe.invalidreg(rn)

		local c = thisframe.pop(true)

		if c.method == REGISTER then
			cg:code("mod "..rs(rn)..", "..rs(rn)..", "..rs(c.value))

			thisframe.release(c.value)
		elseif c.method == DIRECT then
			if imm(c.value, 0x10000) then
				cg:code("modi.i "..rs(rn)..", "..tostring(c.value))
			else
				cg:code("mod "..rs(rn)..", "..rs(rn)..", at")
			end
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

		local ins = "._df_ifin_"..tostring(inn)

		inn = inn + 1

		local cframe = codegen.frame(thisframe)

		codegen.setframe(cframe)

		codegen.block(v.conditional)

		local c = thisframe.pop(false, false, true)

		if c.method == DIRECT then
			if c.value ~= 0 then
				codegen.block(v.body)

				codegen.restoreframe()

				nopedone = true
				break
			end
		elseif c.method == REGISTER then
			cg:code("mov tf, "..rs(c.value))

			if not c.inverse then
				cg:code("bf "..nex)
			else
				cg:code("bt "..nex)
			end

			local nf = codegen.frame(thisframe, true)

			codegen.block(v.body)

			codegen.restoreframe()

			cg:code("b "..out)

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

	local ins = "._df_wins_"..tostring(wnn)

	wnn = wnn + 1

	cg:code(loop..":")

	local cframe = codegen.frame(thisframe)

	codegen.setframe(cframe)

	codegen.block(wn.w.conditional)

	local r = cframe.pop(false, false, true)

	if r.method == DIRECT then
		if r.value ~= 0 then
			codegen.block(wn.w.body)

			cg:code("b "..loop)

			cg:code(out..":")

			codegen.restoreframe()
		end
	elseif r.method == REGISTER then
		cg:code("mov tf, "..rs(r.value))

		if not r.inverse then
			cg:code("bf "..out)
		else
			cg:code("bt "..out)
		end

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
					cg:code("jal "..v.name)
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

					putimm(r0, v.tab.name)

					if imm(r.value*4, 0x10000) then
						cg:code("addi.i "..rs0..", "..tostring(r.value * 4))
					else
						cg:code("add "..rs0..", "..rs0..", at")
					end

					r = thisframe.makereg(r0)
				elseif r.method == REGISTER then
					cg:code("lshi "..rs(r.value)..", "..rs(r.rvalue)..", 2")
					imm(v.tab.name,-1)
					cg:code("add "..rs(r.value)..", "..rs(r.value)..", at")

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

function codegen.restoreframe(drr)
	thisframe.flush(drr)

	thisframe = framepushdown[#framepushdown]

	framepushdown[#framepushdown] = nil
end

function codegen.save()
	if not cproc.leaf then
		cg:code("push lr")
	end

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
		cg:code("swd.l vs, zero, "..cproc.outo[i])
	end

	codegen.restoreframe()

	codegen.restore()

	if not cproc.leaf then
		cg:code("pop lr")
	end

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

	cproc.leaf = true

	for k,v in pairs(t.calls) do
		if (k == "Call") or (not prim_ops[k]) then
			cproc.leaf = false
			break
		end
	end

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
		cg:code("lwi.l "..inv[i]..", vs, zero")
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

	topframe.regs[27] = false -- dragonfruit stack pointer

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