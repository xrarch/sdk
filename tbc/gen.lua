-- C generator for the TOWER Bootstrap Compiler

require("sb")

local gen = {}

function gen.err(token, err)
	print(string.format("tbc: %s:%d: %s", token.filename, token.linenumber, err))
end

function gen.generate(filename, ast)
	gen.output = newsb()
	gen.forwards = newsb()

	gen.forwards.append("#include <stdint.h>\n")

	if not gen.genBlock(ast) then
		return false
	end

	gen.forwards.append(gen.output.tostring())

	return gen.forwards.tostring()
end

function gen.genBlock(block)
	local brackets = gen.currentblock

	gen.currentblock = block

	local oldout = gen.output
	local oldforwards = gen.forwards

	block.output = newsb()
	block.forwards = newsb()

	gen.output = block.output
	gen.forwards = block.forwards

	if brackets then
		gen.forwards.append("{\n")
	end

	if not gen.genScope() then
		return false
	end

	for i = 1, #block.statements do
		local stmt = block.statements[i]

		print("w",stmt.nodetype)

		if not gen.genExprFunctions[stmt.nodetype](stmt) then
			return false
		end

		gen.output.append(";\n")
	end

	if brackets then
		gen.output.append("}\n")
	end

	gen.forwards.append(gen.output.tostring())
	oldout.append(gen.forwards.tostring())

	gen.output = oldout
	gen.forwards = oldforwards

	return true
end

function gen.genScope()
	for k,v in ipairs(gen.currentblock.iscope) do
		if not gen.genDeclaration(v) then
			return false
		end
	end

	return true
end

function gen.genDeclaration(decl)
	if decl.genned then
		return true
	end

	decl.genned = true

	print(decl.decltype)

	local oldout = gen.output
	local oldforwards = gen.forwards

	gen.output = decl.scopeblock.output
	gen.forwards = decl.scopeblock.forwards

	if not gen.genFunctions[decl.decltype](decl) then
		return false
	end

	gen.output = oldout
	gen.forwards = oldforwards

	return true
end

function gen.genType(typenode, name)
	local aname = name or ""

	if type(typenode) == "string" then
		gen.output.append(typenode.." "..aname)

		return true
	end

	if typenode.compound then
		gen.output.append(typenode.name.." "..aname)

		return true
	end

	if typenode.pointer then
		if not gen.genType(typenode.base) then
			return false
		end

		gen.output.append("*" .. aname)
	elseif typenode.primitive then
		gen.output.append(typenode.primitive.ctype.." "..aname)
	else
		if not gen.genType(typenode.base) then
			return false
		end

		if name then
			gen.output.append(name)
		end
	end

	if typenode.array then
		for i = 1, typenode.dimensions do
			gen.output.append("[")

			if typenode.bounds[i] then
				if not gen.generateExpression(typenode.bounds[i]) then
					return false
				end
			end

			gen.output.append("]")
		end
	end

	return true
end

function gen.generateExpression(expr)
	print(expr.nodetype)

	return gen.genExprFunctions[expr.nodetype](expr)
end

function gen.getSymbol(scopeblock, name, errtoken, symtype)
	local sym = findSymbol(scopeblock, name)

	if not sym then
		gen.err(errtoken, string.format("undefined symbol %s", name))
		return false
	end

	if sym.symboltype ~= symtype then
		gen.err(errtoken, string.format("undefined symbol %s", name))
		return false
	end

	if not sym.genned then
		if not gen.genDeclaration(sym) then
			return false
		end
	end

	return sym
end

function gen.evaluateType(etype, errtoken)
	if etype.primitive then
		return etype
	end

	if type(etype.base) == "string" then
		print(etype.base)

		local sym = gen.getSymbol(gen.currentblock, etype.base, errtoken, symboltypes.SYM_TYPE)

		if not sym then
			return false
		end

		if etype.simple then
			return sym.value
		end

		etype.base = sym.value
	elseif etype.base then
		gen.evaluateType(etype.base, errtoken)
	end

	return etype
end

function gen.determineType(expr)
	if expr.nodetype == "string" then
		return stringtype
	end

	if expr.nodetype == "number" then
		return defnumtype
	end

	if expr.nodetype == "cast" then
		return expr.type
	end

	if expr.nodetype == "addrof" then
		local type = {}
		type.pointer = true
		type.base = gen.determineType(expr.expr)

		if not type.base then
			return false
		end

		return type
	end

	if expr.nodetype == "deref" then
		local type = gen.determineType(expr.expr)

		if not type then
			return false
		end

		if not type.pointer then
			gen.err(expr.errtoken, "attempt to deref a non-pointer type")
			return false
		end

		return type.base
	end

	if expr.nodetype == "id" then
		local varname = expr.names[1]

		local sym = gen.getSymbol(gen.currentblock, varname, expr.errtoken, symboltypes.SYM_VAR)

		if not sym then
			return false
		end

		local type

		if sym.funcdef then
			type = {}
			type.pointer = true
			type.funcdef = sym.funcdef
		else
			type = sym.type
		end

		for i = 2, #expr.names do
			print(expr.names[i])

			if not type.compound then
				gen.err(expr.errtoken, "attempt to access a field in a non compound type")
				return false
			end
		end

		return type
	end

	tprint(expr)
end

function gen.genCompoundType(decl)
	local type = decl.value

	-- evaluate all of the types first

	for k,element in ipairs(type.elements) do
		element.type = gen.evaluateType(element.type, decl.errtoken)

		if not element.type then
			return false
		end
	end

	-- now generate the struct/union

	gen.output.append(type.compound .. " _" .. decl.name .. " {\n")

	for k,element in ipairs(type.elements) do
		gen.genType(element.type, element.name)

		gen.output.append(";\n")
	end

	gen.output.append("};\n")

	gen.forwards.append("typedef " .. type.compound .. " _" ..decl.name .. " " .. decl.name .. ";\n")

	return true
end

function gen.genFunctionSignature(funcdef, extern)
	-- evaluate types first

	local returntype

	if funcdef.returntype then
		funcdef.returntype = gen.evaluateType(funcdef.returntype, funcdef.errtoken)

		if not funcdef.returntype then
			return false
		end
	end

	for i = 1, #funcdef.args do
		local arg = funcdef.args[i]

		arg.type = gen.evaluateType(arg.type, funcdef.errtoken)

		if not arg.type then
			return false
		end
	end

	-- if extern is true, only generate the forward declaration

	local oldout = gen.output
	gen.output = gen.forwards

	if not gen.genFunctionSignatureCommon(funcdef) then
		return false
	end

	gen.output.append(";\n")

	gen.output = oldout

	if extern then
		return true
	end

	return gen.genFunctionSignatureCommon(funcdef)
end

function gen.genFunctionSignatureCommon(funcdef)
	if funcdef.returntype then
		if not gen.genType(funcdef.returntype) then
			return false
		end

		gen.output.append(" ")
	else
		gen.output.append("void ")
	end

	gen.output.append(funcdef.name)

	gen.output.append("(")

	for i = 1, #funcdef.args do
		local arg = funcdef.args[i]

		if not gen.genType(arg.type, arg.name) then
			return false
		end

		if i ~= #funcdef.args then
			gen.output.append(", ")
		end
	end

	if funcdef.varargs then
		if #funcdef.args then
			gen.output.append(", ")
		end

		gen.output.append("...")
	end

	gen.output.append(")")

	return true
end

function gen.generateArith(expr)
	gen.output.append("(")

	if not gen.generateExpression(expr.left) then
		return false
	end

	if expr.nodetype == "AND" then
		gen.output.append(" && ")
	elseif expr.nodetype == "OR" then
		gen.output.append(" || ")
	else
		gen.output.append(" " .. expr.nodetype .. " ")
	end

	if not gen.generateExpression(expr.right) then
		return false
	end

	gen.output.append(")")

	return true
end

function gen.generateAssign (expr)
	if not gen.generateExpression(expr.left) then
		return false
	end

	if expr.nodetype == ".=" then
		gen.output.append(" ^= ")
	else
		gen.output.append(" " .. expr.nodetype .. " ")
	end

	return gen.generateExpression(expr.right)
end

gen.genExprFunctions = {
	["number"] = function (expr)
		gen.output.append(tostring(expr.value))

		return true
	end,
	["id"] = function (expr)
		gen.output.append(expr.names[1])

		for i = 2, #expr.names do
			gen.output.append("." .. expr.names[i])
		end

		return true
	end,
	["addrof"] = function (expr)
		gen.output.append("&")

		return gen.generateExpression(expr.expr)
	end,
	["label"] = function (expr)
		gen.output.append(expr.def.name..":\n")

		return true
	end,
	["call"] = function (expr)
		if not gen.generateExpression(expr.funcname) then
			return false
		end

		gen.output.append("(")

		for i = 1, #expr.args do
			if not gen.generateExpression(expr.args[i]) then
				return false
			end

			if i ~= #expr.args then
				gen.output.append(", ")
			end
		end

		gen.output.append(")")

		return true
	end,
	["string"] = function (expr)
		gen.output.append('"')

		for i = 1, #expr.value do
			local c = expr.value:sub(i,i)

			if c == "\n" then
				gen.output.append("\\n")
			else
				gen.output.append(c)
			end
		end

		gen.output.append('"')

		return true
	end,
	["return"] = function (expr)
		gen.output.append("return ")

		return gen.generateExpression(expr.expr)
	end,
	["if"] = function (expr)
		gen.output.append("if ")

		for i = 1, #expr.bodies do
			local body = expr.bodies[i]

			gen.output.append("(")

			if not gen.generateExpression(body.conditional) then
				return false
			end

			gen.output.append(")")

			gen.genBlock(body)

			if i ~= #expr.bodies then
				gen.output.append(" else if ")
			end
		end

		if expr.elseblock then
			gen.output.append(" else ")

			gen.genBlock(expr.elseblock)
		end

		return true
	end,
	["arrayref"] = function (expr)
		if not gen.generateExpression(expr.base) then
			return false
		end

		for i = 1, #expr.indices do
			local index = expr.indices[1]

			gen.output.append("[")

			if not gen.generateExpression(index.expr) then
				return false
			end

			gen.output.append("]")
		end

		return true
	end,
	["deref"] = function (expr)
		gen.output.append("*")

		return gen.generateExpression(expr.expr)
	end,
	["continue"] = function (expr)
		gen.output.append("continue")

		return true
	end,
	["break"] = function (expr)
		gen.output.append("break")

		return true
	end,
	["while"] = function (expr)
		gen.output.append("while (")

		if not gen.generateExpression(expr.block.conditional) then
			return false
		end

		gen.output.append(")")

		return gen.genBlock(expr.block)
	end,

	["="] = gen.generateAssign,
	["+="] = gen.generateAssign,
	["*="] = gen.generateAssign,
	["/="] = gen.generateAssign,
	["%="] = gen.generateAssign,
	["&="] = gen.generateAssign,
	["|="] = gen.generateAssign,
	[".="] = gen.generateAssign, -- xor equals
	[">>="] = gen.generateAssign,
	["<<="] = gen.generateAssign,

	["*"] = gen.generateArith,
	["/"] = gen.generateArith,
	["%"] = gen.generateArith,
	["+"] = gen.generateArith,
	["-"] = gen.generateArith,
	["<<"] = gen.generateArith,
	[">>"] = gen.generateArith,
	["<"] = gen.generateArith,
	[">"] = gen.generateArith,
	["<="] = gen.generateArith,
	[">="] = gen.generateArith,
	["=="] = gen.generateArith,
	["!="] = gen.generateArith,
	["&"] = gen.generateArith,
	["^"] = gen.generateArith,
	["|"] = gen.generateArith,
	["AND"] = gen.generateArith,
	["OR"] = gen.generateArith,
}

gen.genFunctions = {
	["var"] = function (decl)
		if decl.enumconst then
			return true
		end

		if decl.const then
			gen.output.append("const ")
		end

		local type = decl.type

		if not type then
			decl.type = gen.determineType(decl.value)
			type = decl.type

			if not type then
				return false
			end
		end

		decl.type = gen.evaluateType(type, decl.errtoken)
		type = decl.type

		if not gen.genType(type, decl.name) then
			return false
		end

		if decl.value then
			gen.output.append(" = ")

			gen.generateExpression(decl.value)
		end

		gen.output.append(";\n")

		return true
	end,
	["type"] = function (decl)
		local type = decl.value

		if type.compound then
			return gen.genCompoundType(decl)
		end

		if type.funcdef then
			return gen.genFnPtr(decl)
		end

		if type.values then
			return gen.genEnum(decl)
		end

		type = gen.evaluateType(type, decl.errtoken)

		if not type then
			return false
		end

		local oldout = gen.output
		gen.output = gen.forwards

		gen.output.append("typedef ")

		gen.genType(type, decl.name)

		gen.output.append(";\n")

		gen.output = oldout

		return true
	end,
	["fn"] = function (decl)
		local funcdef = decl.funcdef

		if decl.extern then
			return gen.genFunctionSignature(funcdef, true)
		end

		if not gen.genFunctionSignature(funcdef) then
			return false
		end

		-- generate the block

		if not gen.genBlock(funcdef.body) then
			return false
		end

		return true
	end,
	["label"] = function (decl)
		return true
	end,
}

return gen