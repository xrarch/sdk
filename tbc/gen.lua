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
	gen.currentblock = brackets

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

function gen.genType(typenode, name, arrayhack)
	local rootnode = gen.suffix == nil

	if rootnode then
		gen.suffix = newsb()
	end

	if type(typenode) == "string" then
		gen.output.append(typenode)

		if name then
			gen.output.append(" "..name)
		end
	elseif typenode.compound or typenode.enumtype then
		gen.output.append(typenode.name)

		if name then
			gen.output.append(" "..name)
		end
	elseif typenode.pointer then
		if typenode.base.funcdef then
			if not gen.genFunctionSignatureCommon(typenode.base.funcdef, name) then
				return false
			end
		else
			if not gen.genType(typenode.base) then
				return false
			end

			if (typenode.base.pointer or typenode.base.array) and name then
				gen.output.append("(")
			end

			gen.output.append("*")

			if name then
				gen.output.append(" "..name)
			end

			if (typenode.base.pointer or typenode.base.array) and name then
				gen.output.append(")")
			end
		end
	elseif typenode.primitive then
		gen.output.append(typenode.primitive.ctype)

		if name then
			gen.output.append(" "..name)
		end
	elseif typenode.array then
		if not gen.genType(typenode.base, name) then
			return false
		end

		local arsb = newsb()

		arsb.append("[")

		local oldout = gen.output
		gen.output = arsb

		if typenode.bounds then
			if not gen.generateExpression(typenode.bounds) then
				return false
			end
		end

		gen.output = oldout

		arsb.append("]")

		gen.suffix.prepend(arsb.tostring())
	elseif typenode.funcdef then
		-- coerce to pointer

		local newtypenode = {}
		newtypenode.pointer = true
		newtypenode.base = typenode
		
		if not gen.genType(newtypenode, name) then
			return false
		end
	else
		if not gen.genType(typenode.base) then
			return false
		end

		if name then
			gen.output.append(" "..name)
		end
	end

	if rootnode then
		gen.output.append(gen.suffix.tostring())
		gen.suffix = nil
	end

	return true
end

function gen.generateExpression(expr)
	return gen.genExprFunctions[expr.nodetype](expr)
end

function gen.getSymbol(scopeblock, name, errtoken, symtype)
	local sym = findSymbol(scopeblock, name)

	if not sym then
		--error("hm")
		gen.err(errtoken, string.format("undefined symbol %s", name))
		return false
	end

	if sym.symboltype ~= symtype then
		gen.err(errtoken, string.format("undefined symbol %s", name))
		return false
	end

	if (not sym.genned) and (not sym.funcdef) then
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

	if etype.enumtype then
		return etype
	end

	if type(etype.base) == "string" then
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
	if not gen.determineTypeFunctions[expr.nodetype] then
		error("uh "..expr.nodetype)
	end

	return gen.determineTypeFunctions[expr.nodetype](expr)
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

function gen.genFunctionSignatureCommon(funcdef, fnptrname)
	if funcdef.returntype then
		if not gen.genType(funcdef.returntype) then
			return false
		end

		gen.output.append(" ")
	else
		gen.output.append("void ")
	end

	if fnptrname then
		gen.output.append("(*")

		gen.output.append(fnptrname)

		gen.output.append(")")
	else
		gen.output.append(funcdef.name)
	end

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

function gen.determineTypeArith(expr)
	if expr.left.nodetype == "number" then
		return gen.determineType(expr.right)
	end

	return gen.determineType(expr.left)
end

function gen.generateArith(expr)
	local lefttype = gen.determineType(expr.left)

	if not lefttype then
		return false
	end

	local righttype = gen.determineType(expr.right)

	if not righttype then
		return false
	end

	-- In TOWER, pointer arithmetic is literal and loses the type, so we have
	-- to cast here to uint8_t* if we see that happen and then the result
	-- is casted to void*.

	local ptrconvert = (expr.nodetype == "+") or (expr.nodetype == "-")

	if ptrconvert and (lefttype.pointer or righttype.pointer) then
		gen.output.append("(void*)")
	end

	gen.output.append("(")

	if ptrconvert and lefttype.pointer then
		gen.output.append("(uint8_t*)(")
	end

	if not gen.generateExpression(expr.left) then
		return false
	end

	if ptrconvert and lefttype.pointer then
		gen.output.append(")")
	end

	if expr.nodetype == "AND" then
		gen.output.append(" && ")
	elseif expr.nodetype == "OR" then
		gen.output.append(" || ")
	elseif expr.nodetype == "$" then
		gen.output.append(" ^ ")
	else
		gen.output.append(" " .. expr.nodetype .. " ")
	end

	if ptrconvert and righttype.pointer then
		gen.output.append("(uint8_t*)(")
	end

	if not gen.generateExpression(expr.right) then
		return false
	end

	if ptrconvert and righttype.pointer then
		gen.output.append(")")
	end

	gen.output.append(")")

	return true
end

function gen.generateAssign(expr)
	if not gen.generateExpression(expr.left) then
		return false
	end

	if expr.nodetype == "$=" then
		gen.output.append(" ^= ")
	else
		gen.output.append(" " .. expr.nodetype .. " ")
	end

	return gen.generateExpression(expr.right)
end

function gen.genEnum(decl)
	gen.output.append("enum _" .. decl.name .. " {\n")

	for i = 1, #decl.values do
		local val = decl.values[i]

		gen.output.append(val.name)

		if val.value then
			gen.output.append("=")

			if not gen.generateExpression(val.value) then
				return false
			end
		end

		gen.output.append(",\n")
	end

	gen.output.append("};\n")

	gen.forwards.append("typedef enum _" ..decl.name .. " " .. decl.name .. ";\n")

	return true
end

function gen.genFnPtr(decl)
	gen.forwards.append("typedef ")

	local oldout = gen.output
	gen.output = gen.forwards

	gen.genFunctionSignatureCommon(decl.value.funcdef, decl.name)

	gen.output = oldout

	gen.forwards.append(";\n")

	return true
end

gen.genExprFunctions = {
	["number"] = function (expr)
		gen.output.append(tostring(expr.value))

		return true
	end,
	["id"] = function (expr)
		local sym = gen.getSymbol(gen.currentblock, expr.name, expr.errtoken, symboltypes.SYM_VAR)

		if not sym then
			return false
		end

		gen.output.append(expr.name)

		return true
	end,
	["."] = function (expr)
		local type = gen.determineType(expr.left)

		if not type then
			return false
		end

		if type.pointer then
			gen.err(expr.errtoken, "attempt to access a field in a pointer type, use ^.")
			return false
		end

		if not type.compound then
			gen.err(expr.errtoken, "attempt to access a field in a non compound type")
			return false
		end

		if expr.right.nodetype ~= "id" then
			gen.err(expr.errtoken, "non-id right side of . operator")
			return false
		end

		if not gen.generateExpression(expr.left) then
			return false
		end

		local field = type.elementsbyname[expr.right.name]

		if not field then
			gen.err(expr.errtoken, "attempt to access a non-existent field")
			return false
		end

		gen.output.append("." .. expr.right.name)

		return true
	end,
	["addrof"] = function (expr)
		gen.output.append("&")

		return gen.generateExpression(expr.left)
	end,
	["label"] = function (expr)
		gen.output.append(expr.def.name..":\n")

		return true
	end,
	["("] = function (expr)
		if not gen.generateExpression(expr.left) then
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
		gen.output.append('(uint8_t*)("')

		for i = 1, #expr.value do
			local c = expr.value:sub(i,i)

			if c == "\n" then
				gen.output.append("\\n")
			elseif c == "\\" then
				gen.output.append("\\")
			elseif c == '"' then
				gen.output.append("\\\"")
			else
				gen.output.append(c)
			end
		end

		gen.output.append('")')

		return true
	end,
	["return"] = function (expr)
		gen.output.append("return ")

		return gen.generateExpression(expr.expr)
	end,
	["leave"] = function (expr)
		gen.output.append("return")

		return true
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

			if not gen.genBlock(body) then
				return false
			end

			if i ~= #expr.bodies then
				gen.output.append(" else if ")
			end
		end

		if expr.elseblock then
			gen.output.append(" else ")

			if not gen.genBlock(expr.elseblock) then
				return false
			end
		end

		return true
	end,
	["["] = function (expr)
		if not gen.generateExpression(expr.left) then
			return false
		end

		gen.output.append("[")

		if not gen.generateExpression(expr.expr) then
			return false
		end

		gen.output.append("]")

		return true
	end,
	["^"] = function (expr)
		gen.output.append("(*")

		if not gen.generateExpression(expr.left) then
			return false
		end

		gen.output.append(")")

		return true
	end,
	["inverse"] = function (expr)
		gen.output.append("-")

		return gen.generateExpression(expr.left)
	end,
	["~"] = function (expr)
		gen.output.append("(~")

		if not gen.generateExpression(expr.left) then
			return false
		end

		gen.output.append(")")

		return true
	end,
	["not"] = function (expr)
		gen.output.append("(!")

		if not gen.generateExpression(expr.left) then
			return false
		end

		gen.output.append(")")

		return true
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
	["block"] = function (expr)
		return gen.genBlock(expr)
	end,
	["goto"] = function (expr)
		gen.output.append("goto " .. expr.name)

		return true
	end,
	["cast"] = function (expr)
		gen.output.append("(")

		if not gen.genType(expr.type) then
			return false
		end

		gen.output.append(")(")

		if not gen.generateExpression(expr.left) then
			return false
		end

		gen.output.append(")")

		return true
	end,
	["sizeofvalue"] = function (expr)
		gen.output.append("sizeof(")

		if not gen.generateExpression(expr.left) then
			return false
		end

		gen.output.append(")")

		return true
	end,
	["sizeof"] = function (expr)
		gen.output.append("sizeof(")

		if not gen.genType(expr.value) then
			return false
		end

		gen.output.append(")")

		return true
	end,
	["initializer"] = function (expr)
		gen.output.append("{\n")

		for i = 1, #expr.vals do
			local val = expr.vals[i]

			if val.index then
				gen.output.append("[")

				if not gen.generateExpression(val.index) then
					return false
				end

				gen.output.append("] = ")
			end

			if not gen.generateExpression(val.value) then
				return false
			end

			gen.output.append(",\n")
		end

		gen.output.append("}")

		return true
	end,

	["nullptr"] = function (decl)
		gen.output.append("0")

		return true
	end,

	["="] = gen.generateAssign,
	["+="] = gen.generateAssign,
	["-="] = gen.generateAssign,
	["*="] = gen.generateAssign,
	["/="] = gen.generateAssign,
	["%="] = gen.generateAssign,
	["&="] = gen.generateAssign,
	["|="] = gen.generateAssign,
	["$="] = gen.generateAssign, -- xor equals
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
	["$"] = gen.generateArith,
	["|"] = gen.generateArith,
	["AND"] = gen.generateArith,
	["OR"] = gen.generateArith,
}

gen.genFunctions = {
	["var"] = function (decl)
		if decl.ignore then
			return true
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

		if decl.const then
			gen.output.append("#define " .. decl.name .. " ")

			if not gen.generateExpression(decl.value) then
				return false
			end

			gen.output.append("\n")

			return true
		elseif decl.extern then
			gen.output.append("extern ")
		end

		if not gen.genType(type, decl.name) then
			return false
		end

		if decl.value and not decl.dontinitialize then
			gen.output.append(" = ")

			if not gen.generateExpression(decl.value) then
				return false
			end
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

		if decl.values then
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

gen.determineTypeFunctions = {
	["string"] = function (expr)
		return stringtype
	end,
	["number"] = function (expr)
		return defnumtype
	end,
	["cast"] = function (expr)
		return gen.evaluateType(expr.type, expr.errtoken)
	end,
	["addrof"] = function (expr)
		local type = {}
		type.pointer = true
		type.base = gen.determineType(expr.left)

		if not type.base then
			return false
		end

		return type
	end,
	["sizeof"] = function (expr)
		return defnumtype
	end,
	["nullptr"] = function (expr)
		return nullptrtype
	end,
	["^"] = function (expr)
		local type = gen.determineType(expr.left)

		if not type then
			return false
		end

		if not type.pointer then
			gen.err(expr.errtoken, "attempt to deref a non-pointer type")
			return false
		end

		return gen.evaluateType(type.base)
	end,
	["id"] = function (expr)
		local varname = expr.name

		local sym = gen.getSymbol(gen.currentblock, varname, expr.errtoken, symboltypes.SYM_VAR)

		if not sym then
			return false
		end

		local type

		if sym.funcdef then
			type = {}
			type.funcdef = sym.funcdef
		else
			type = gen.evaluateType(sym.type, expr.errtoken)

			if not type then
				return false
			end
		end

		return type
	end,
	["."] = function (expr)
		local type = gen.determineType(expr.left)

		if not type then
			return false
		end

		if type.pointer then
			gen.err(expr.errtoken, "attempt to access a field in a pointer type, use ^.")
			return false
		end

		if not type.compound then
			gen.err(expr.errtoken, "attempt to access a field in a non compound type")
			return false
		end

		if expr.right.nodetype ~= "id" then
			gen.err(expr.errtoken, "non-id right side of . operator")
			return false
		end

		local field = type.elementsbyname[expr.right.name]

		if not field then
			gen.err(expr.errtoken, "attempt to access a non-existent field")
			return false
		end

		return gen.evaluateType(field.type, expr.errtoken)
	end,
	["["] = function (expr)
		local type = gen.determineType(expr.left)

		if not type then
			return false
		end

		if not type.array and not type.pointer then
			gen.err(expr.errtoken, "attempt to index non-array, non-pointer type")
			return false
		end

		return gen.evaluateType(type.base)
	end,
	["("] = function (expr)
		local type = gen.determineType(expr.left)

		if not type then
			return false
		end

		if not type.funcdef then
			gen.err(expr.errtoken, "attempt to call non-function type")
			return false
		end

		if not type.funcdef.returntype then
			gen.err(expr.errtoken, "attempt to take type of void function")
			return false
		end

		return gen.evaluateType(type.funcdef.returntype)
	end,

	["*"] = gen.determineTypeArith,
	["/"] = gen.determineTypeArith,
	["%"] = gen.determineTypeArith,
	["+"] = gen.determineTypeArith,
	["-"] = gen.determineTypeArith,
	["<<"] = gen.determineTypeArith,
	[">>"] = gen.determineTypeArith,
	["<"] = gen.determineTypeArith,
	[">"] = gen.determineTypeArith,
	["<="] = gen.determineTypeArith,
	[">="] = gen.determineTypeArith,
	["=="] = gen.determineTypeArith,
	["!="] = gen.determineTypeArith,
	["&"] = gen.determineTypeArith,
	["$"] = gen.determineTypeArith,
	["|"] = gen.determineTypeArith,
	["AND"] = gen.determineTypeArith,
	["OR"] = gen.determineTypeArith,
}

return gen