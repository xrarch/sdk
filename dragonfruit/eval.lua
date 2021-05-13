
-- symbolically evaluates the even more symbolic definitions that the parser gives us

local function lerror(token, err)
	print(string.format("dragonc: eval: %s:%d: %s", token[4], token[3], err))
end

local eval = {}

local def = {}

local const = {}

local symb

local curblock

local currentfn

local function defined(ident, kind)
	if not currentfn then
		currentfn = {}
		currentfn.symb = {}
	end

	local id = currentfn.symb[ident] or symb[ident]

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

local function stacknode_t(kind, ident, errtok, opk, ...)
	local n = {}

	n.kind = kind
	n.ident = ident
	n.errtok = errtok
	n.op = opk
	n.opers = {...}

	return n
end

local function stack_t()
	local s = {}

	s.stack = {}

	s.size = 0

	function s.pop(errtok)
		if s.size == 0 then
			lerror(errtok, "stack underflow!")
			return false
		end

		s.size = s.size - 1

		return table.remove(s.stack)
	end

	function s.push(v)
		s.stack[#s.stack + 1] = v

		s.size = s.size + 1
	end

	return s
end

local function op_t(errtok, operation, ...)
	local op = {}

	op.errtok = errtok

	op.kind = operation

	op.opers = {...}

	return op
end

eval.immop = {
	["swap"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		s.push(op1)
		s.push(op2)

		return
	end,
	["dup"] = function (s, tok, b)
		b.simple = false

		local op1 = s.pop(tok)
		if not op1 then return false end

		op1.refs = (op1.refs or 1) + 1

		s.push(op1)
		s.push(op1)

		return
	end,
	["drop"] = function (s, tok, b)
		b.simple = false

		local op1 = s.pop(tok)
		if not op1 then return false end

		-- sometimes a node is referenced elsewhere, this tells whatever references it
		-- to disregard it cuz its dropped and not used
		op1.dropped = true
	end,
	["bswap"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		if op1.kind == "num" then
			local value = 
				bor(rshift(op1.ident, 24),
				bor(band(lshift(op1.ident, 8), 0xFF0000),
				bor(band(rshift(op1.ident, 8), 0xFF00),
				band(lshift(op1.ident, 24), 0xFF000000))))
			s.push(stacknode_t("num", value, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "bswap", op1, op2))

		return
	end,
	["~"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		if op1.kind == "num" then
			s.push(stacknode_t("num", bnot(op1.ident), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "~", op1, op2))

		return
	end,
	["~~"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		if op1.kind == "num" then
			local n = 1

			if op1.ident ~= 0 then
				n = 0
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "~~", op1, op2))

		return
	end,
	["&"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", band(op1.ident, op2.ident), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "&", op1, op2))

		return
	end,
	["&&"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if (op1.ident ~= 0) and (op2.ident ~= 0) then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		elseif op1.kind == "num" then
			if op1.ident == 0 then
				s.push(stacknode_t("num", 0, tok))
			else
				s.push(stacknode_t("op", nil, tok, "~=", op2, stacknode_t("num", 0, tok)))
			end
			return
		elseif op2.kind == "num" then
			if op2.ident == 0 then
				s.push(stacknode_t("num", 0, tok))
			else
				s.push(stacknode_t("op", nil, tok, "~=", op1, stacknode_t("num", 0, tok)))
			end
			return
		end

		s.push(stacknode_t("op", nil, tok, "&&", op1, op2))

		return
	end,
	["|"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", bor(op1.ident, op2.ident), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "|", op1, op2))

		return
	end,
	["^"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", bxor(op1.ident, op2.ident), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "^", op1, op2))

		return
	end,
	["||"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") or (op2.kind == "num") then
			local n = 0

			if ((op1.kind == "num") and (op1.ident ~= 0)) or ((op2.kind == "num") and (op2.ident ~= 0)) then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "||", op1, op2))

		return
	end,
	[">>"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", rshift(op2.ident, op1.ident), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, ">>", op2, op1))

		return
	end,
	["<<"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", lshift(op2.ident, op1.ident), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "<<", op2, op1))

		return
	end,
	["=="] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op1.ident == op2.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "==", op1, op2))

		return
	end,
	["~="] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op1.ident ~= op2.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "~=", op1, op2))

		return
	end,
	[">"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op2.ident > op1.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, ">", op2, op1))

		return
	end,
	["<"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op2.ident < op1.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "<", op2, op1))

		return
	end,
	[">="] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op2.ident >= op1.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, ">=", op2, op1))

		return
	end,
	["<="] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op2.ident <= op1.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "<=", op2, op1))

		return
	end,
	["s>"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op2.ident > op1.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "s>", op2, op1))

		return
	end,
	["s<"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op2.ident < op1.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "s<", op2, op1))

		return
	end,
	["s>="] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op2.ident >= op1.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "s>=", op2, op1))

		return
	end,
	["s<="] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			local n = 0

			if op2.ident <= op1.ident then
				n = 1
			end

			s.push(stacknode_t("num", n, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "s<=", op2, op1))

		return
	end,
	["+"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		local n
		local nid
		local k

		if op1.kind == "num" then
			n = op1
			nid = op1.ident
			
			if nid == 0 then
				s.push(op2)
				return
			end

			k = op2
		elseif op2.kind == "num" then
			n = op2
			nid = op2.ident
			
			if nid == 0 then
				s.push(op1)
				return
			end

			k = op1
		end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", op1.ident + op2.ident, tok))
			return
		elseif (op1.opers[3]) and (op2.kind == "num") then
			local q = op1.opers[4] + op2.ident

			op1.opers[3].ident = math.abs(q)
			op1.opers[4] = q

			if q < 0 then
				op1.op = "-"
			elseif q == 0 then
				s.push(op1.opers[5])
				return
			elseif q > 0 then
				op1.op = "+"
			end

			s.push(op1)
			return
		elseif (op2.opers[3]) and (op1.kind == "num") then
			local q = op2.opers[4] + op1.ident

			op2.opers[3].ident = math.abs(q)
			op2.opers[4] = q

			if q < 0 then
				op2.op = "-"
			elseif q == 0 then
				s.push(op2.opers[5])
				return
			elseif q > 0 then
				op2.op = "+"
			end

			s.push(op2)
			return
		end

		s.push(stacknode_t("op", nil, tok, "+", op1, op2, n, nid, k))

		return
	end,
	["-"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		local n
		local nid
		local k

		if op1.kind == "num" then
			n = op1
			nid = -op1.ident

			if nid == 0 then
				s.push(op2)
				return
			end

			k = op2
		end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", op2.ident - op1.ident, tok))
			return
		elseif (op2.opers[3]) and (op1.kind == "num") then
			local q = op2.opers[4] - op1.ident

			op2.opers[3].ident = math.abs(q)
			op2.opers[4] = q

			if q < 0 then
				op2.op = "-"
			elseif q == 0 then
				s.push(op2.opers[5])
				return
			elseif q > 0 then
				op2.op = "+"
			end

			s.push(op2)
			return
		end

		s.push(stacknode_t("op", nil, tok, "-", op2, op1, n, nid, k))

		return
	end,
	["*"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", op1.ident * op2.ident, tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "*", op1, op2))

		return
	end,
	["/"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", math.floor(op2.ident / op1.ident), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "/", op2, op1))

		return
	end,
	["%"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", math.floor(op2.ident % op1.ident), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "%", op2, op1))

		return
	end,
	["@"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		s.push(stacknode_t("op", nil, tok, "@", op1))

		return
	end,
	["gi"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		s.push(stacknode_t("op", nil, tok, "gi", op1))

		return
	end,
	["gb"] = function (s, tok)
		local op1 = s.pop(tok)
		if not op1 then return false end

		s.push(stacknode_t("op", nil, tok, "gb", op1))

		return
	end,
	["!"] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		if (dest.kind == "auto") and (src.kind == "auto") then
			if dest.ident == src.ident then
				return
			end
		end

		return op_t(tok, "!", dest, src)
	end,
	["si"] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "si", dest, src)
	end,
	["sb"] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "sb", dest, src)
	end,
	["+="] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "+=", dest, src)
	end,
	["-="] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "-=", dest, src)
	end,
	["*="] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "*=", dest, src)
	end,
	["/="] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "/=", dest, src)
	end,
	["%="] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "%=", dest, src)
	end,
	["&="] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "&=", dest, src)
	end,
	["|="] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "|=", dest, src)
	end,
	[">>="] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, ">>=", dest, src)
	end,
	["<<="] = function (s, tok)
		local dest = s.pop(tok)
		if not dest then return false end

		local src = s.pop(tok)
		if not src then return false end

		return op_t(tok, "<<=", dest, src)
	end,
	["return"] = function (s, tok)
		if s.size > 0 then
			lerror(tok, "can't return with "..tostring(s.size).." item(s) on stack")
			return false
		end

		return op_t(tok, "return")
	end,
	["continue"] = function (s, tok)
		if s.size > 0 then
			lerror(tok, "can't continue with "..tostring(s.size).." item(s) on stack")
			return false
		end

		return op_t(tok, "continue")
	end,
	["break"] = function (s, tok)
		if s.size > 0 then
			lerror(tok, "can't break with "..tostring(s.size).." item(s) on stack")
			return false
		end

		return op_t(tok, "break")
	end,

	["bitget"] = function (s, tok) -- (v bit -- bit)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", band(rshift(op2.ident, op1.ident), 1), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "bitget", op2, op1))
	end,
	["bitset"] = function (s, tok) -- (v bit -- v)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", bor(op1.ident, lshift(1, op2.ident)), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "bitset", op2, op1))
	end,
	["bitclear"] = function (s, tok) -- (v bit -- v)
		local op1 = s.pop(tok)
		if not op1 then return false end

		local op2 = s.pop(tok)
		if not op2 then return false end

		if (op1.kind == "num") and (op2.kind == "num") then
			s.push(stacknode_t("num", band(op1.ident, bnot(lshift(1, op2.ident))), tok))
			return
		end

		s.push(stacknode_t("op", nil, tok, "bitclear", op2, op1))
	end,
	["alloc"] = function (s, tok) -- (size -- ptr)
		local size = s.pop(tok)
		if not size then return false end

		if size.kind ~= "num" then
			lerror(tok, "can only allocate a static number of bytes on the stack")
			return false
		end

		s.push(stacknode_t("op", nil, tok, "alloc", stacknode_t("num", currentfn.allocated, tok)))

		currentfn.allocated = currentfn.allocated + size.ident
	end,
}
local immop = eval.immop

local mustend = {
	["break"] = true,
	["continue"] = true,
	["return"] = true,
}

local function stackdump(s)
	for k,v in ipairs(s.stack) do
		print(string.format(" pushed at %s:%d", v.errtok[4], v.errtok[3]))
	end
end

function eval.blockeval(block, errtok, constant, rets, ixb)
	local sposed = 0

	if rets then sposed = 1 end

	if block.defines then
		if not constant then
			error("defined but not constant")
		end

		if const[block.defines] then -- already evaluated this constant
			return const[block.defines]
		end

		errtok = symb[block.defines].errtok
	end

	local b = {}

	if curblock then
		b.ixb = curblock.ixb or ixb
		b.simple = curblock.simple or true
	else
		b.ixb = ixb
		b.simple = true
	end

	ixb = b.ixb

	b.rets = rets

	b.stack = stack_t()

	b.calls = 0

	local oblock = curblock

	curblock = b

	b.ops = {}

	local s = b.stack

	for k,v in ipairs(block.block) do
		if v.kind == "lazy" then
			local tok = v.ident

			local sym = defined(tok[1])

			if tok[2] == "number" then
				s.push(stacknode_t("num", tok[1], tok))
			elseif tok[2] == "string" then
				s.push(stacknode_t("str", tok[1], tok))
			elseif immop[tok[1]] then
				if (mustend[tok[1]]) and (k ~= #block.block) then
					lerror(tok, tok[1].." must be at the end of a block")
					return false
				end

				local r = immop[tok[1]](s, tok, b)

				-- r can be nil, but it can't be false, which are not equivalent in lua
				if r == false then return false end

				if r and ixb then
					lerror(errtok, "can't do a mutating operation in an index block")
					return false
				end

				b.ops[#b.ops + 1] = r
			elseif sym then
				if sym.kind == "const" then
					if type(sym.value) == "number" then
						s.push(stacknode_t("num", sym.value, tok))
					else
						s.push(stacknode_t("num", eval.blockeval(sym.value, sym.errtok, true), tok))
					end
				elseif (sym.kind == "var") or (sym.kind == "externconst") or (sym.kind == "buffer") or (sym.kind == "table") then
					s.push(stacknode_t("ptr", tok[1], tok))
				elseif sym.kind == "auto" then
					s.push(stacknode_t("auto", sym, tok))
				elseif (sym.kind == "fn") or (sym.kind == "extern") or (sym.kind == "fnptr") then
					b.simple = false

					if ixb then
						lerror(errtok, "can't call a function inside of an index block")
						return false
					end

					local ptr

					if sym.kind == "fnptr" then
						ptr = s.pop(tok)

						if not ptr then return false end
					end

					local fn = sym.value

					local argc = 0

					local fin = {}

					for i = #fn.fin, 1, -1 do
						local n = s.pop(tok)

						if not n then return false end

						local f = {}
						f.name = fn.fin[i]
						f.node = n
						fin[#fin + 1] = f

						argc = argc + 1
					end

					local argvs = 0

					local argv = {}

					if fn.varin then
						argc = argc + 1 -- argc isnt counted above

						local stackdepth = #s.stack

						for i = 1, stackdepth do
							local n = s.pop(tok)

							if not n then return false end

							local f = {}
							f.node = n
							argv[#argv + 1] = f

							argvs = argvs + 1
						end
					end

					local cq = "call"

					local call = op_t(v.errtok, "call")

					call.rets = {}

					call.ptr = ptr

					call.argv = argv

					call.argvs = argvs

					call.fin = fin

					call.fn = sym.value

					local oc = 0

					for i = 1, #fn.out do
						local sn = stacknode_t("op", nil, tok, "retvalue")

						call.rets[#call.rets + 1] = sn

						s.push(sn)

						oc = oc + 1
					end

					b.ops[#b.ops + 1] = call

					local cgconvenient = {}
					cgconvenient.varin = fn.varin
					cgconvenient.args = argc
					cgconvenient.argvs = argvs
					cgconvenient.os = oc

					currentfn.calls[#currentfn.calls + 1] = cgconvenient

					b.calls = b.calls + 1
				else
					lerror(tok, "w")
					error("TODO "..tok[1].." "..sym.kind)
				end
			else
				lerror(tok, "undefined word: "..tostring(tok[1]))
				return false
			end
		elseif v.kind == "pointerof" then
			s.push(stacknode_t("ptr", v.value, tok))
		elseif v.kind == "index" then
			b.simple = false

			local sym = defined(v.name, "table")

			if not sym then
				sym = defined(v.name, "externconst")
			end

			if not sym then
				sym = defined(v.name, "buffer")
			end

			if not sym then
				lerror(v.errtok, tostring(v.name).." isn't a table or buffer")
				return false
			end

			local oblock = eval.blockeval(v.block, v.errtok, false, true, true)

			if not oblock then
				return false
			end

			s.push(stacknode_t("op", nil, tok, "index", sym, oblock))
		elseif ixb then
			lerror(errtok, "can't do a "..v.kind.." inside of an index block")
			return false
		elseif v.kind == "while" then
			b.simple = false

			local op = op_t(v.errtok, "while")

			op.conditional = eval.blockeval(v.w.conditional, v.errtok, false, true)

			if not op.conditional then return false end

			local tos = op.conditional.stack.stack[1]

			if not tos then
				error("no tos")
			end

			if (tos.kind == "num") and (tos.ident == 0) then
				-- forget this ever happened, this while loop will never run
				-- the opposite optimization, for if the conditional is just 1,
				-- is a burden of the backend
			else
				if (tos.kind == "num") then
					op.conditional.simple = false
				end

				op.body = eval.blockeval(v.w.body, v.errtok, varin, varout)

				if not op.body then return false end

				b.ops[#b.ops + 1] = op
			end
		elseif v.kind == "if" then
			b.simple = false

			local op = op_t(v.errtok, "if")

			op.ifs = {}

			for i = 1, #v.ifs do
				local c = {}

				local f = v.ifs[i]

				c.conditional = eval.blockeval(f.conditional, f.errtok, false, true)

				if not c.conditional then
					return false
				end

				local tos = c.conditional.stack.stack[1]

				if not tos then
					error("no tos")
				end

				local done = false

				if (tos.kind == "num") and (tos.ident == 0) then
					-- forget this ever happened, this if block will never run
				else
					if (tos.kind == "num") and (tos.ident ~= 0) then -- this block will always run eventually, so dont bother including the other conditionals
						done = true
					end

					c.body = eval.blockeval(f.body, f.errtok)

					if not c.body then return false end

					op.ifs[#op.ifs + 1] = c
				end

				if done then break end
			end

			if v.default then
				op.default = eval.blockeval(v.default, v.default.errtok)

				if not op.default then return false end
			end

			b.ops[#b.ops + 1] = op
		else
			error("TODO "..v.kind)
		end
	end

	curblock = oblock

	if curblock then
		curblock.calls = curblock.calls + b.calls
	end

	if constant then
		if s.size ~= 1 then
			lerror(errtok, "constant expression needs to have exactly 1 item on stack after evaluation, had "..tostring(s.size).." items")
			return false
		end

		local tos = s.stack[1]

		if tos.kind ~= "num" then
			lerror(errtok, "constant expression needs to evaluate to a number, evaluated to "..tostring(tos.kind))
			return false
		end

		if block.defines then
			const[block.defines] = tos.ident
		end

		return tos.ident
	end

	if (s.size ~= sposed) then
		lerror(errtok, "block exits with "..tostring(s.size).." item(s) on stack, expected "..tostring(sposed))

		for k,v in ipairs(s.stack) do
			print(string.format(" pushed at %s:%d", v.errtok[4], v.errtok[3]))
		end

		return false
	end

	return b
end


local basicdefs = {
	["buffer"] = true,
	["var"] = true,
	["table"] = true,
}

local function basicdef(symdef)
	local mb = {}
	mb.name = symdef.ident
	mb.kind = symdef.kind

	local c = symdef.value

	if symdef.kind == "table" then
		if symdef.value.count then
			c = symdef.value.count
		else
			mb.words = {}

			local w = symdef.value.words

			for i = 1, #w do
				if (w[i].typ == "const") or (w[i].typ == "block") then
					mb.words[i] = {}
					mb.words[i].typ = "num"
					mb.words[i].errtok = w[i].errtok
					if type(w[i].name) == "number" then
						mb.words[i].name = w[i].name
					else
						mb.words[i].name = eval.blockeval(w[i].name, w[i].errtok, true)
					end

					if not mb.words[i].name then return false end
				else
					mb.words[i] = w[i]
				end
			end

			def[mb.name] = mb
			return true
		end
	end

	if type(c) == "number" then
		mb.value = c
	else
		mb.value = eval.blockeval(c, symdef.errtok, true)
	end

	if not mb.value then
		return false
	end

	def[mb.name] = mb

	return true
end

function eval.eval(symdeftab, public, extern, structs, asms)
	if not symdeftab then return false end

	symb = symdeftab

	for k,struc in ipairs(structs) do
		local off = 0

		for k2,elem in ipairs(struc) do
			const[elem.name] = off

			elem.valblock.block[1] = {kind="lazy", ident={off, "number"}}

			if type(elem.size) == "number" then
				off = off + elem.size
			else
				local v = eval.blockeval(elem.size, elem.tok, true)

				if not v then
					return false
				end

				off = off + v
			end
		end
	end

	for k,v in pairs(symdeftab) do
		if v.kind == "const" then
			if not const[v.ident] then
				if type(v.value) == "number" then
					const[v.ident] = v.value
				else
					const[v.ident] = eval.blockeval(v.value, v.errtok, true)

					if not const[v.ident] then return false end
				end
			end
		elseif basicdefs[v.kind] then
			if not basicdef(v) then return false end
		elseif v.kind == "fn" then
			local fn = {}

			fn.name = v.ident

			fn.kind = "fn"

			fn.symb = v.value.def

			fn.isymb = v.value.idef

			fn.fin = v.value.fin

			fn.out = v.value.out

			fn.varin = v.value.varin

			fn.public = v.value.public

			fn.calls = {}

			fn.allocated = 0

			currentfn = fn

			fn.block = eval.blockeval(v.value.block, v.errtok, false)

			if not fn.block then return false end

			def[v.ident] = fn
		else
			--error("eval "..tostring(v.kind))
		end
	end

	for k,v in pairs(public) do
		if not def[k] then
			lerror(v, k.." is undefined")
			return false
		end
	end

	return def, public, extern, asms, const
end

return eval