local lexer = require("lexer")

local parser = {}

local LEFT  = 1
local RIGHT = 2

local function astnode_t(type, errtoken)
	-- create and initialize an AST node

	local node = {}
	node.nodetype = type
	node.errtoken = errtoken

	return node
end

local function def_t(name, symboltype, errtoken)
	-- create and initialize a symbol definition

	local def = {}
	def.name = name
	def.symboltype = symboltype

	def.const = false
	def.funcdef = nil
	def.type = nil
	def.value = nil
	def.extern = false
	def.ignore = false
	def.decltype = nil
	def.errtoken = errtoken

	return def
end

local function typedef_t(name, type, errtoken)
	local def = def_t(name, symboltypes.SYM_TYPE, errtoken)
	def.value = type
	def.decltype = "type"

	return def
end

local function idnode_t(name, errtoken)
	local node = astnode_t("id", errtoken)
	node.name = name

	return node
end

local function type_t()
	local type = {}
	type.pointer = false
	type.array = false
	type.funcdef = nil
	type.arraybounds = nil
	type.primitive = nil
	type.base = nil

	return type
end

local function funcdef_t(name, errtoken)
	local funcdef = {}
	funcdef.args = {}
	funcdef.returntype = nil
	funcdef.name = name
	funcdef.errtoken = errtoken

	return funcdef
end

local function numnode_t(number, errtoken)
	local node = astnode_t("number", errtoken)
	node.value = number

	return node
end

function parser.err(token, err)
	print(string.format("tbc: %s:%d: %s", token.filename, token.linenumber, err))
end

function parser.checkToken(token, canbenumerical)
	if token.eof then
		parser.err(token, "unexpected EOF")
		return false
	end

	if not canbenumerical then
		if token.value then
			parser.err(token, "unexpected numerical token")
			return false
		end
	end

	return true
end

function parser.parse(filename, file, incdir, libdir, symbols)
	local gtype = type_t()
	gtype.base = "ubyte"
	gtype.primitive = primitivetypes.UBYTE

	local type = type_t()
	type.pointer = true
	type.base = gtype

	_G.stringtype = type

	type = type_t()
	type.base = "LONG"
	type.primitive = primitivetypes.LONG

	_G.defnumtype = type

	type = type_t()
	type.pointer = true

	_G.defptrtype = type

	local lex = lexer.new(filename, file, incdir, libdir, symbols)

	if not lex then
		return false
	end

	parser.loopdepth = 0

	return parser.parseBlock(lex)
end

function parser.parseBlock(lex, terminators, func)
	-- each statement in a block is one of the following:
	-- declaration
	-- assignment
	-- expression with side effects (i.e. a function call)
	-- if statement
	-- while loop

	terminators = terminators or {}

	local block = astnode_t("block")
	block.statements = {}
	block.scope = {}
	block.iscope = {}
	block.errtoken = nil

	if func then
		parser.funcblock = block
	end

	local lastblock = parser.currentblock
	parser.currentblock = block

	block.parentblock = lastblock

	local terminated = false

	while true do
		local token = lex.nextToken()

		if token.eof then
			if block.parentblock then
				parser.err(token, "unexpected EOF")
				return false
			end

			break
		end

		if token.value then
			parser.err(token, "unexpected numerical token")
			return false
		end

		if not block.errtoken then
			block.errtoken = token
		end

		parser.errtoken = token

		local stmt = nil

		local kw = parser.keywords[token.str]

		local nexttoken

		if kw then
			stmt = kw(lex)
		elseif token.str == "@" then
			-- label declaration

			if not parser.funcblock then
				parser.err(token, "labels can only be declared in function scope")
				return false
			end

			nexttoken = lex.nextToken()

			if not parser.checkToken(nexttoken) then
				return false
			end

			local def = def_t(nexttoken.str, symboltypes.SYM_LABEL, token)
			def.decltype = "label"

			if not defineSymbol(parser.funcblock, def, false) then
				parser.err(token, "label name already declared")
				return false
			end

			stmt = astnode_t("label", token)
			stmt.def = def
			def.node = stmt
		else
			for k,v in ipairs(terminators) do
				if token.str == v then
					-- block is terminated.
					-- allow caller to consume terminator token.
					-- NOTE: maybe return terminator token instead?

					terminated = true

					lex.lastToken(token)

					break
				end
			end

			if terminated then
				break
			end

			-- this is either a declaration, an assignment, or an expression.

			nexttoken = lex.nextToken()

			lex.lastToken(nexttoken)
			lex.lastToken(token)

			if nexttoken.str == ":" then
				-- declaration

				local def = parser.parseDeclaration(lex)

				if not def then
					return false
				end

				if block.parentblock then
					-- this declaration happened somewhere other than the root
					-- block, so we want to generate an assign node if there's
					-- a value.

					if def.value then
						stmt = astnode_t("=", token)

						stmt.left = idnode_t(def.name, token)
						stmt.right = def.value

						def.dontinitialize = true
					end
				end
			else
				-- this is an atom of some kind.

				local atom = parser.parseExpression(lex)

				if not atom then
					return false
				end

				-- is the atom the entire statement, or is this an assignment?

				nexttoken = lex.nextToken()

				if parser.assigns[nexttoken.str] then
					-- assignment

					stmt = astnode_t(nexttoken.str, token)

					stmt.left = atom
					stmt.right = parser.parseExpression(lex, nil, true)

					if not stmt.right then
						return false
					end
				else
					lex.lastToken(nexttoken)

					stmt = atom
				end
			end
		end

		-- stmt can be nil, but not false.

		if stmt == false then
			return false
		end

		if stmt then
			table.insert(block.statements, stmt)
		end
	end

	if func then
		parser.funcblock = nil
	end

	parser.currentblock = lastblock

	return block
end

function parser.parseExpression(lex, minprec, assign)
	minprec = minprec or 0

	local atom = parser.parseAtom(lex, assign, minprec)

	if not atom then
		return false
	end

	local optoken = lex.nextToken()

	local op = parser.operators[optoken.str]

	if assign and atom.nodetype == "initializer" and op then
		parser.err(optoken, "unexpected token after initializer")
		return false
	end

	while op do
		if op.precedence < minprec then
			break
		end

		local node = astnode_t(optoken.str, optoken)
		node.left = atom

		local nextminprec

		if op.associativity == LEFT then
			nextminprec = op.precedence + 1
		else
			nextminprec = op.precedence
		end

		if op.parse then
			if not op.parse(lex, nextminprec, node) then
				return false
			end
		else
			node.right = parser.parseExpression(lex, nextminprec)

			if not node.right then
				return false
			end
		end

		optoken = lex.nextToken()

		op = parser.operators[optoken.str]

		atom = node
	end

	lex.lastToken(optoken)

	return atom
end

function parser.parseAtom(lex, assign, minprec)
	-- an atom here means any individual value, such as an array reference,
	-- a variable reference, a numerical constant, or a parenthesized
	-- expression. lvalues and rvalues are parsed identically and are checked
	-- during a later stage of the compiler.

	local atom

	local token = lex.nextToken()

	if not parser.checkToken(token, true) then
		return false
	end

	local leftop = parser.leftoperators[token.str]

	if leftop then
		atom = astnode_t(token.str, token)
		atom.left = parser.parseExpression(lex, leftop.precedence)

		if not atom.left then
			return false
		end

		if leftop.parse then
			if not leftop.parse(lex, leftop.precedence, atom) then
				return false
			end
		end
	elseif token.literal then
		-- string

		atom = astnode_t("string", token)

		atom.value = token.str

		return atom
	elseif token.str == "{" then
		-- initializer

		if not assign then
			parser.err(token, "unexpected initializer")
			return false
		end

		return parser.parseInitializer(lex, token)
	elseif token.str == "TRUE" then
		return numnode_t(1, token)
	elseif token.str == "FALSE" then
		return numnode_t(0, token)
	elseif token.str == "(" then
		-- parenthesized expression

		atom = parser.parseExpression(lex)

		if not atom then
			return false
		end

		-- check for closing parenthesis

		token = lex.nextToken()

		if not parser.checkToken(token) then
			return false
		end

		if token.str ~= ")" then
			parser.err(token, "unexpected token, expected )")
			return false
		end
	elseif token.value then
		-- numerical value

		atom = astnode_t("number", token)

		atom.value = token.value

		return atom
	else
		-- identifier

		atom = idnode_t(token.str, token)
	end

	return atom
end

function parser.parseDeclaration(lex, const, public, extern)
	-- returns a def, caller decides whether to turn that into a statement.
	-- does define the symbol for you.

	local nametoken = lex.nextToken()

	if not parser.checkToken(nametoken) then
		return false
	end

	local def = def_t(nametoken.str, symboltypes.SYM_VAR, nametoken)
	def.const = const
	def.public = public
	def.extern = extern
	def.decltype = "var"

	local colontoken = lex.nextToken()

	if not parser.checkToken(colontoken) then
		return false
	end

	if colontoken.str ~= ":" then
		parser.err(colontoken, "unexpected token, expected :")
		return false
	end

	local eqtoken = lex.nextToken()

	if not parser.checkToken(eqtoken) then
		return false
	end

	if eqtoken.str ~= "=" then
		-- explicit type

		lex.lastToken(eqtoken)

		def.type = parser.parseType(lex)

		if not def.type then
			return false
		end

		eqtoken = lex.nextToken()
	end

	if not eqtoken.eof then
		if not parser.checkToken(eqtoken) then
			return false
		end

		if eqtoken.str ~= "=" then
			-- uninitialized variable

			lex.lastToken(eqtoken)
		else
			def.value = parser.parseExpression(lex, nil, true)

			if not def.value then
				return false
			end
		end
	end

	local nocheck = not const

	if nocheck then
		local sym = findSymbol(parser.currentblock, def.name)

		if sym then
			if not sym.extern then
				parser.err(nametoken, string.format("%s already defined", def.name))
				return false
			end

			if parser.funcblock then
				parser.err(nametoken, string.format("%s already defined", def.name))
				return false
			end

			if not def.type then
				parser.err(nametoken, string.format("%s already defined", def.name))
				return false
			end

			if not compareTypes(sym.type, def.type) then
				parser.err(nametoken, string.format("type mismatch with previously declared extern for %s", def.name))
				return false
			end
		end
	end

	if not defineSymbol(parser.currentblock, def, nocheck) then
		parser.err(nametoken, string.format("%s already defined", def.name))
		return false
	end

	return def
end

function parser.parseType(lex, depth)
	depth = depth or 0

	local type = type_t()

	local token = lex.nextToken()

	if not parser.checkToken(token) then
		return false
	end

	if token.str == "(" then
		type = parser.parseType(lex)

		if not type then
			return false
		end

		token = lex.nextToken()

		if token.str ~= ")" then
			parser.err(token, "expected )")
			return false
		end

		return type
	elseif token.str == "^" then
		type.pointer = true
		type.base = parser.parseType(lex, depth + 1)

		if not type.base then
			return false
		end
	else
		local base = token.str
		type.base = base

		if primitivetypes[base] then
			type.primitive = primitivetypes[base]
		else
			type.simple = true
		end
	end

	if depth > 0 then
		return type
	end

	-- collect all of the array parts

	token = lex.nextToken()

	if token.str ~= "[" then
		lex.lastToken(token)

		return type
	end

	local firstarraytype = nil
	local lastarraytype = nil
	local dimensions = 0

	while token.str == "[" do
		local arraytype = type_t()
		arraytype.array = true
		arraytype.bounds = nil
		arraytype.base = type

		dimensions = dimensions + 1

		if not firstarraytype then
			firstarraytype = arraytype
		else
			if not lastarraytype.bounds then
				parser.err(token, "multidimensional array types must specify all bounds")
				return false
			end

			lastarraytype.base = arraytype
		end

		token = lex.nextToken()

		if token.str ~= "]" then
			lex.lastToken(token)

			arraytype.bounds = parser.parseExpression(lex)

			if not arraytype.bounds then
				return false
			end

			token = lex.nextToken()

			if token.str ~= "]" then
				parser.err(token, "expected ]")
				return false
			end
		elseif dimensions > 1 then
			parser.err(token, "multidimensional array types must specify all bounds")
			return false
		end

		lastarraytype = arraytype

		token = lex.nextToken()
	end

	lex.lastToken(token)

	return firstarraytype
end

function parser.compareFunctionSignatures(funcdef1, funcdef2, cmpfnptr)
	-- compares the function signatures of both funcdefs

	if #funcdef1.args ~= #funcdef2.args then
		return false
	end

	if funcdef1.returntype then
		if not funcdef2.returntype then
			return false
		end

		if not compareTypes(funcdef1.returntype, funcdef2.returntype) then
			return false
		end
	elseif funcdef2.returntype then
		return false
	end

	if cmpfnptr then
		if funcdef1.fnptrtype ~= funcdef2.fnptrtype then
			return false
		end
	end

	for i, arg in ipairs(funcdef1.args) do
		local arg2 = funcdef2.args[i]

		if arg.name ~= arg2.name then
			return false
		end

		if not compareTypes(arg.type, arg2.type) then
			return false
		end
	end

	return true
end

function parser.parseFunctionSignature(lex)
	-- returns a funcdef representing the function signature.

	local aheadtoken = lex.nextToken()

	if not parser.checkToken(aheadtoken) then
		return false
	end

	if parser.funcblock then
		parser.err(aheadtoken, "nested function definitions are forbidden")
		return false
	end

	local fntype = nil

	if aheadtoken.str == "(" then
		-- theres a reference fnptr we want to compare with

		local fnptrtoken = lex.nextToken()

		if not parser.checkToken(fnptrtoken) then
			return false
		end

		aheadtoken = lex.nextToken()

		if aheadtoken.str ~= ")" then
			parser.err(aheadtoken, "expected )")
			return false
		end

		local fnptrname = fnptrtoken.str

		local fnptrsym = findSymbol(parser.currentblock, fnptrname)

		if not fnptrsym then
			parser.err(aheadtoken, string.format("%s is not a declared symbol", fnptrname))
			return false
		end

		if fnptrsym.symboltype ~= symboltypes.SYM_TYPE then
			parser.err(aheadtoken, string.format("%s is not a type", fnptrname))
			return false
		end

		fntype = fnptrsym.value

		if not fntype.pointer then
			parser.err(aheadtoken, string.format("%s is not a pointer type"), fnptrname)
			return false
		end

		fntype = fntype.base

		if not fntype.funcdef then
			parser.err(aheadtoken, string.format("%s is not a function type"), fnptrname)
			return false
		end

		aheadtoken = lex.nextToken()

		if not parser.checkToken(aheadtoken) then
			return false
		end
	end

	local funcdef = funcdef_t(aheadtoken.str, aheadtoken)

	funcdef.fnptrtype = fntype

	aheadtoken = lex.nextToken()

	if aheadtoken.str ~= "(" then
		parser.err(token, "expected (")
		return false
	end

	-- parse the argument list, which is of the form:
	-- name : type(,)
	-- until a close parenthesis is found.

	while true do
		aheadtoken = lex.nextToken()

		if not parser.checkToken(aheadtoken) then
			return false
		end

		if aheadtoken.str == ")" then
			break
		end

		if funcdef.varargs then
			parser.err(nametoken, "extra arguments after varargs specified")
			return false
		end

		if aheadtoken.str == "..." then
			funcdef.varargs = true
		else
			local arg = {}

			if aheadtoken.str == "IN" then
				arg.inspec = true
			elseif aheadtoken.str == "OUT" then
				arg.outspec = true
			elseif aheadtoken.str == "INOUT" then
				arg.inspec = true
				arg.outspec = true
			else
				parser.err(aheadtoken, "expected IN, OUT, or INOUT")
				return false
			end

			aheadtoken = lex.nextToken()

			if not parser.checkToken(aheadtoken, true) then
				return false
			end

			arg.name = aheadtoken.str

			aheadtoken = lex.nextToken()

			if aheadtoken.str ~= ":" then
				parser.err(aheadtoken, "expected :")
				return false
			end

			arg.type = parser.parseType(lex)

			if not arg.type then
				return false
			end

			if arg.outspec then
				if not arg.type.pointer then
					parser.err(aheadtoken, "out argument has non-pointer type")
					return false
				end
			end

			table.insert(funcdef.args, arg)
		end

		aheadtoken = lex.nextToken()

		if aheadtoken.str == ")" then
			break
		elseif aheadtoken.str ~= "," then
			parser.err(aheadtoken, "unexpected token, expected ','")
			return false
		end
	end

	-- check if there is a return type specified or not

	aheadtoken = lex.nextToken()

	if aheadtoken.str == ":" then
		-- there is one

		funcdef.returntype = parser.parseType(lex)

		if not funcdef.returntype then
			return false
		end
	else
		-- there ain't one

		lex.lastToken(aheadtoken)
	end

	if fntype then
		if not parser.compareFunctionSignatures(funcdef, fntype.funcdef) then
			parser.err(aheadtoken, "mismatched function signatures")
			return false
		end
	end

	return funcdef
end

function parser.parseFunction(lex, extern)
	local funcdef = parser.parseFunctionSignature(lex)

	if not funcdef then
		return false
	end

	funcdef.body = parser.parseBlock(lex, {"END"}, true)

	if not funcdef.body then
		return false
	end

	for i = 1, #funcdef.args do
		local arg = funcdef.args[i]

		local argdef = def_t(arg.name, symboltypes.SYM_VAR, funcdef.errtoken)
		argdef.decltype = "var"
		argdef.ignore = true
		argdef.type = arg.type

		if not defineSymbol(funcdef.body, argdef) then
			parser.err(funcdef.errtoken, string.format("%s already defined", argdef.name))
			return false
		end
	end

	-- consume the token for end

	local tok = lex.nextToken()

	local def = def_t(funcdef.name, symboltypes.SYM_VAR, funcdef.errtoken)
	def.funcdef = funcdef
	def.decltype = "fn"

	local sym = findSymbol(parser.currentblock, def.name)

	if sym then
		if not sym.extern then
			parser.err(tok, string.format("%s already defined", def.name))
			return false
		end

		if not sym.funcdef then
			parser.err(tok, string.format("%s already defined", def.name))
			return false
		end

		if not parser.compareFunctionSignatures(funcdef, sym.funcdef, true) then
			parser.err(tok, string.format("function signature mismatch with previously declared extern"))
			return false
		end

		sym.ignore = true
	end

	if not defineSymbol(parser.currentblock, def, true) then
		parser.err(funcdef.errtoken, string.format("%s already defined", def.name))
		return false
	end
end

function parser.parseCompoundType(lex, compound)
	local type = type_t()
	type.compound = compound
	type.elements = {}
	type.elementsbyname = {}

	local nametoken = lex.nextToken()

	if not parser.checkToken(nametoken) then
		return false
	end

	if nametoken.str == "PACKED" then
		if compound ~= "struct" then
			parser.err(nametoken, "union specified as packed")
			return false
		end

		type.packed = true

		nametoken = lex.nextToken()

		if not parser.checkToken(nametoken) then
			return false
		end
	end

	type.name = nametoken.str

	while true do
		local aheadtoken = lex.nextToken()

		if not parser.checkToken(aheadtoken, true) then
			return false
		end

		if aheadtoken.str == "END" then
			break
		end

		local element = {}
		element.name = aheadtoken.str

		aheadtoken = lex.nextToken()

		if aheadtoken.str ~= ":" then
			parser.err(aheadtoken, "unexpected token, expected ':'")
			return false
		end

		element.type = parser.parseType(lex)

		if not element.type then
			return false
		end

		table.insert(type.elements, element)
		type.elementsbyname[element.name] = element

		aheadtoken = lex.nextToken()

		if aheadtoken.str == "END" then
			break
		elseif aheadtoken.str ~= "," then
			parser.err(aheadtoken, "unexpected token, expected ','")
			return false
		end
	end

	local def = typedef_t(nametoken.str, type, nametoken)

	if not defineSymbol(parser.currentblock, def, false) then
		parser.err(nametoken, string.format("%s already defined", def.name))
		return false
	end

	return true
end

function parser.parseInitializer(lex, errtoken)
	local node = astnode_t("initializer", errtoken)
	node.vals = {}

	while true do
		local token = lex.nextToken()

		if not parser.checkToken(token, true) then
			return false
		end

		if token.str == "}" then
			break
		end

		local field = {}

		if token.str == "[" then
			local expr = parser.parseExpression(lex)

			if not expr then
				return false
			end

			field.index = expr

			token = lex.nextToken()

			if not parser.checkToken(token) then
				return false
			end

			if not token.str == "]" then
				parser.err(token, "expected ]")
				return false
			end

			token = lex.nextToken()

			if not parser.checkToken(token) then
				return false
			end

			if not token.str == "=" then
				parser.err(token, "expected =")
				return false
			end

			field.value = parser.parseExpression(lex, nil, true)
		else
			lex.lastToken(token)

			field.index = nil
			field.value = parser.parseExpression(lex)
		end

		if not field.value then
			return false
		end

		table.insert(node.vals, field)

		token = lex.nextToken()

		if token.str == "}" then
			break
		elseif token.str ~= "," then
			parser.err(token, "unexpected token, expected ','")
			return false
		end
	end

	return node
end

parser.keywords = {
	["IF"] = function (lex)
		local expr = parser.parseExpression(lex)

		if not expr then
			return false
		end

		local aheadtoken = lex.nextToken()

		if aheadtoken.str ~= "THEN" then
			parser.err(aheadtoken, "expected 'THEN'")
			return false
		end

		local node = astnode_t("if", expr.errtoken)

		node.bodies = {}
		node.elseblock = nil

		local elseblock = false

		local terminators = {
			"END",
			"ELSE",
			"ELSEIF"
		}

		while true do
			local block = parser.parseBlock(lex, terminators)

			if not block then
				return false
			end

			if elseblock then
				node.elseblock = block
			else
				block.conditional = expr
				table.insert(node.bodies, block)
			end

			aheadtoken = lex.nextToken()

			if aheadtoken.str == "END" then
				break
			elseif aheadtoken.str == "ELSE" then
				if elseblock then
					parser.err(aheadtoken, "already declared an else block")
					return false
				end

				elseblock = true
			elseif aheadtoken.str == "ELSEIF" then
				if elseblock then
					parser.err(aheadtoken, "already declared an else block")
					return false
				end

				expr = parser.parseExpression(lex)

				if not expr then
					return false
				end

				aheadtoken = lex.nextToken()

				if aheadtoken.str ~= "THEN" then
					parser.err(aheadtoken, "expected 'THEN'")
					return false
				end
			end
		end

		return node
	end,

	["WHILE"] = function (lex)
		local expr = parser.parseExpression(lex)

		if not expr then
			return false
		end

		local aheadtoken = lex.nextToken()

		if aheadtoken.str ~= "DO" then
			parser.err(aheadtoken, "expected 'DO'")
			return false
		end

		local node = astnode_t("while", expr.errtoken)

		parser.loopdepth = parser.loopdepth + 1

		local block = parser.parseBlock(lex, {"END"})

		parser.loopdepth = parser.loopdepth - 1

		if not block then
			return false
		end

		block.conditional = expr

		node.block = block

		-- eat the end token

		lex.nextToken()

		return node
	end,

	["GOTO"] = function (lex)
		local nametoken = lex.nextToken()

		if not parser.checkToken(nametoken) then
			return false
		end

		local node = astnode_t("goto", nametoken)

		node.name = nametoken.str

		return node
	end,

	["BREAK"] = function (lex)
		if parser.loopdepth == 0 then
			parser.err(parser.errtoken, "break outside of loop")
			return false
		end

		return astnode_t("break", parser.errtoken)
	end,

	["CONTINUE"] = function (lex)
		if parser.loopdepth == 0 then
			parser.err(parser.errtoken, "continue outside of loop")
			return false
		end

		return astnode_t("continue", parser.errtoken)
	end,

	["RETURN"] = function (lex)
		local expr = parser.parseExpression(lex)

		if not expr then
			return false
		end

		local node = astnode_t("return", expr.errtoken)

		node.expr = expr

		return node
	end,

	["TYPE"] = function (lex)
		local nametoken = lex.nextToken()

		if not parser.checkToken(nametoken) then
			return false
		end

		local colontoken = lex.nextToken()

		if not parser.checkToken(colontoken) then
			return false
		end

		if colontoken.str ~= ":" then
			parser.err(colontoken, "unexpected token, expected :")
			return false
		end

		local type = parser.parseType(lex)

		if not type then
			return false
		end

		local def = typedef_t(nametoken.str, type, nametoken)

		if not defineSymbol(parser.currentblock, def, false) then
			parser.err(nametoken, string.format("%s already defined", def.name))
			return false
		end

		return nil
	end,

	["STRUCT"] = function (lex)
		if not parser.parseCompoundType(lex, "struct") then
			return false
		end

		return nil
	end,

	["UNION"] = function (lex)
		if not parser.parseCompoundType(lex, "union") then
			return false
		end

		return nil
	end,

	["FNPTR"] = function (lex)
		local funcdef = parser.parseFunctionSignature(lex)

		if not funcdef then
			return false
		end

		local ftype = type_t()
		ftype.funcdef = funcdef

		local type = type_t()
		type.pointer = true
		type.base = ftype
		type.fnptr = true
		type.name = funcdef.name

		local def = typedef_t(funcdef.name, type, funcdef.errtoken)

		if not defineSymbol(parser.currentblock, def, false) then
			parser.err(nametoken, string.format("%s already defined", def.name))
			return false
		end

		return nil
	end,

	["EXTERN"] = function (lex)
		local nametoken = lex.nextToken()

		if not parser.checkToken(nametoken) then
			return false
		end

		local declop = parser.decls[nametoken.str]
		local def

		if declop then
			def = declop(lex)
		else
			lex.lastToken(nametoken)

			def = parser.parseDeclaration(lex, nil, nil, true)

			if def and (not def.type) then
				parser.err(nametoken, "implicit types are not allowed in extern definitions")
				return false
			end

			if def.value then
				parser.err(nametoken, "initialization is not allowed in extern definitions")
				return false
			end
		end

		if not def then
			return false
		end

		return nil
	end,

	["PUBLIC"] = function (lex)
		parser.parseDeclaration(lex, false, true)

		return nil
	end,

	["CONST"] = function (lex)
		parser.parseDeclaration(lex, true)

		return nil
	end,

	["ENUM"] = function (lex)
		local nametoken = lex.nextToken()

		if not parser.checkToken(nametoken) then
			return false
		end

		local token = lex.nextToken()

		if token.str ~= ":" then
			parser.err(token, "expected ':'")
			return false
		end

		local basetype = parser.parseType(lex)

		if not basetype then
			return false
		end

		if not basetype.primitive then
			parser.err(token, "enum must have primitive underlying type")
			return false
		end

		local type = type_t()
		type.base = basetype
		type.enumtype = true
		type.name = nametoken.str

		local def = typedef_t(nametoken.str, type, nametoken)

		if not defineSymbol(parser.currentblock, def, false) then
			parser.err(nametoken, string.format("%s already defined", def.name))
			return false
		end

		def.values = {}
		local vals = def.values

		while true do
			local token = lex.nextToken()

			if not parser.checkToken(token, true) then
				return false
			end

			if token.str == "END" then
				break
			end

			local def = def_t(token.str, symboltypes.SYM_VAR, token)
			def.ignore = true
			def.const = true
			def.type = type
			def.decltype = "var"

			if not defineSymbol(parser.currentblock, def, false) then
				parser.err(nametoken, string.format("%s already defined", def.name))
				return false
			end

			token = lex.nextToken()

			if token.str == "=" then
				-- explicit value

				def.value = parser.parseExpression(lex)

				if not def.value then
					return false
				end

				token = lex.nextToken()
			end

			table.insert(vals, def)

			if token.str == "END" then
				break
			elseif token.str ~= "," then
				parser.err(token, "unexpected token, expected ','")
				return false
			end
		end

		return nil
	end,

	["BEGIN"] = function (lex)
		local node = parser.parseBlock(lex, {"END"})

		if not node then
			return false
		end

		-- eat the end token

		lex.nextToken()

		return node
	end,

	["FN"] = parser.parseFunction,
}

parser.leftoperators = {
	["&"] = {
		precedence = 24,
		parse = function (lex, minprec, node)
			node.nodetype = "addrof"
			return true
		end,
	},
	["-"] = {
		precedence = 24,
		parse = function (lex, minprec, node)
			node.nodetype = "inverse"
			return true
		end,
	},
	["NOT"] = {
		precedence = 24,
		parse = function (lex, minprec, node)
			node.nodetype = "not"
			return true
		end,
	},
	["~"] = {
		precedence = 24,
	},
	["CAST"] = {
		precedence = 24,
		parse = function (lex, minprec, node)
			node.nodetype = "cast"

			token = lex.nextToken()

			if not parser.checkToken(token) then
				return false
			end

			if token.str ~= "TO" then
				parser.err(token, "unexpected token, expected 'TO'")
				return false
			end

			node.type = parser.parseType(lex)

			if not node.type then
				return false
			end

			return true
		end
	},
	["SIZEOF"] = {
		precedence = 24,
		parse = function (lex, minprec, node)
			node.nodetype = "sizeof"
			return true
		end,
	}
}

parser.operators = {
	["."] = {
		precedence = 25,
		associativity = LEFT,
	},
	["["] = {
		precedence = 25,
		associativity = LEFT,
		parse = function (lex, minprec, node)
			node.expr = parser.parseExpression(lex)

			if not node.expr then
				return false
			end

			token = lex.nextToken()

			if not token.str == "]" then
				parser.err(token, "expected ]")
				return false
			end

			return true
		end,
	},
	["("] = {
		precedence = 25,
		associativity = LEFT,
		parse = function (lex, minprec, node)
			node.args = {}

			-- parse argument list

			while true do
				aheadtoken = lex.nextToken()

				if not parser.checkToken(aheadtoken, true) then
					return false
				end

				if aheadtoken.str == ")" then
					break
				end

				lex.lastToken(aheadtoken)

				local expr = parser.parseExpression(lex)

				if not expr then
					return false
				end

				table.insert(node.args, expr)

				aheadtoken = lex.nextToken()

				if aheadtoken.str == ")" then
					break
				elseif aheadtoken.str ~= "," then
					parser.err(aheadtoken, "unexpected token, expected ','")
					return false
				end
			end

			return true
		end,
	},
	["^"] = {
		precedence = 25,
		associativity = LEFT,
		parse = function (lex, minprec, node)
			return true
		end,
	},
	["*"] = {
		precedence = 20,
		associativity = LEFT,
	},
	["/"] = {
		precedence = 20,
		associativity = LEFT,
	},
	["%"] = {
		precedence = 20,
		associativity = LEFT,
	},
	["+"] = {
		precedence = 19,
		associativity = LEFT,
	},
	["-"] = {
		precedence = 19,
		associativity = LEFT,
	},
	["<<"] = {
		precedence = 18,
		associativity = LEFT,
	},
	[">>"] = {
		precedence = 18,
		associativity = LEFT,
	},
	["<"] = {
		precedence = 17,
		associativity = LEFT,
	},
	[">"] = {
		precedence = 17,
		associativity = LEFT,
	},
	["<="] = {
		precedence = 17,
		associativity = LEFT,
	},
	[">="] = {
		precedence = 17,
		associativity = LEFT,
	},
	["=="] = {
		precedence = 16,
		associativity = LEFT,
	},
	["!="] = {
		precedence = 16,
		associativity = LEFT,
	},
	["&"] = {
		precedence = 15,
		associativity = LEFT,
	},
	["$"] = {
		precedence = 14,
		associativity = LEFT,
	},
	["|"] = {
		precedence = 13,
		associativity = LEFT,
	},
	["AND"] = {
		precedence = 12,
		associativity = LEFT,
	},
	["OR"] = {
		precedence = 11,
		associativity = LEFT,
	},
}

parser.decls = {
	["FN"] = function (lex)
		local funcdef = parser.parseFunctionSignature(lex)

		if not funcdef then
			return false
		end

		local def = def_t(funcdef.name, symboltypes.SYM_VAR, funcdef.errtoken)
		def.funcdef = funcdef
		def.decltype = "fn"
		def.extern = true

		if not defineSymbol(parser.currentblock, def, true) then
			parser.err(nametoken, string.format("%s already defined", def.name))
			return false
		end

		return def
	end,
}

parser.assigns = {
	["="] = true,
	["+="] = true,
	["*="] = true,
	["/="] = true,
	["%="] = true,
	["&="] = true,
	["|="] = true,
	["$="] = true, -- xor equals
	[">>="] = true,
	["<<="] = true,
}

return parser