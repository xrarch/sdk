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

local function def_t(name, symboltype)
	-- create and initialize a symbol definition

	local def = {}
	def.name = name
	def.symboltype = symboltype

	def.const = false
	def.funcdef = nil
	def.type = nil
	def.value = nil
	def.extern = false

	return def
end

local function typedef_t(name, type)
	local def = def_t(name, symboltypes.SYM_TYPE)
	def.value = type

	return def
end

local function idnode_t(name, errtoken)
	local node = astnode_t("id", errtoken)
	node.names = {}
	node.names[1] = name

	return node
end

local function type_t()
	local type = {}
	type.pointer = false
	type.array = false
	type.funcdef = nil
	type.arraybounds = nil
	type.primitive = nil

	return type
end

local function funcdef_t(name)
	local funcdef = {}
	funcdef.args = {}
	funcdef.returntype = nil
	funcdef.name = name

	return funcdef
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
	local lex = lexer.new(filename, file, incdir, libdir, symbols)

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

			local def = def_t(nexttoken.str, symboltypes.SYM_LABEL)

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

			lex.lastToken(token)
			lex.lastToken(nexttoken)

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
						stmt = astnode_t("assign", token)

						stmt.dest = idnode_t(def.name)
						stmt.src = def.value
					end
				end
			else
				-- this is an atom of some kind.

				local atom = parser.parseAtom(lex)

				if not atom then
					return false
				end

				-- is the atom the entire statement, or is this an assignment?

				nexttoken = lex.nextToken()

				if nexttoken.str == "=" then
					-- assignment

					stmt = astnode_t("assign", token)

					stmt.dest = atom
					stmt.src = parser.parseExpression(lex)

					if not stmt.src then
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

function parser.parseExpression(lex, minprec)
	minprec = minprec or 0

	local atom = parser.parseAtom(lex)

	if not atom then
		return false
	end

	local optoken = lex.nextToken()

	local op = parser.operators[optoken.str]

	while op do
		if op.precedence < minprec then
			break
		end

		local node = astnode_t(optoken.str, optoken)
		node.left = atom

		local nextmaxprec

		if op.associativity == LEFT then
			nextmaxprec = op.precedence + 1
		else
			nextmaxprec = op.precedence
		end

		node.right = parser.parseExpression(lex, nextmaxprec)

		optoken = lex.nextToken()

		op = parser.operators[optoken.str]

		atom = node
	end

	lex.lastToken(optoken)

	return atom
end

function parser.parseAtom(lex)
	-- an atom here means any individual value, such as an array reference,
	-- a variable reference, a numerical constant, or a parenthesized
	-- expression. lvalues and rvalues are parsed identically and are checked
	-- during a later stage of the compiler.

	local atom

	local token = lex.nextToken()

	if not parser.checkToken(token, true) then
		return false
	end

	if token.literal then
		-- string

		atom = astnode_t("string", token)

		atom.value = token.str

		return atom
	elseif token.str == "true" then
		atom = astnode_t("number", token)

		atom.value = 1

		return atom
	elseif token.str == "false" then
		atom = astnode_t("number", token)

		atom.value = 0

		return atom
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
	elseif token.str == "cast" then
		atom = astnode_t("cast", token)

		atom.expr = parser.parseExpression(lex)

		token = lex.nextToken()

		if not parser.checkToken(token) then
			return false
		end

		if token.str ~= "to" then
			parser.err(token, "unexpected token, expected 'to'")
			return false
		end

		atom.type = parser.parseType(lex)

		return atom
	elseif token.str == "not" then
		-- unary logical not

		atom = astnode_t("not", token)

		atom.expr = parser.parseAtom(lex)

		if not atom.expr then
			return false
		end

		return atom
	elseif token.str == "~" then
		-- unary bitwise not

		atom = astnode_t("bitnot", token)

		atom.expr = parser.parseAtom(lex)

		if not atom.expr then
			return false
		end

		return atom
	elseif token.str == "-" then
		-- unary inverse

		atom = astnode_t("inverse", token)

		atom.expr = parser.parseAtom(lex)

		if not atom.expr then
			return false
		end

		return atom
	elseif token.str == "^" then
		-- pointer unwrap

		atom = astnode_t("deref", token)

		atom.expr = parser.parseAtom(lex)

		if not atom.expr then
			return false
		end

		return atom
	elseif token.str == "&" then
		-- pointer wrap

		atom = astnode_t("addrof", token)

		atom.expr = parser.parseAtom(lex)

		if not atom.expr then
			return false
		end

		return atom
	elseif token.value then
		-- numerical value

		atom = astnode_t("number", token)

		atom.value = token.value

		return atom
	else
		-- identifier

		atom = idnode_t(token.str, token)

		local aheadtoken = lex.nextToken()

		while aheadtoken.str == "." do
			-- more names!

			local nametoken = lex.nextToken()

			if not parser.checkToken(nametoken) then
				return false
			end

			table.insert(atom.names, nametoken.str)

			aheadtoken = lex.nextToken()
		end

		lex.lastToken(aheadtoken)
	end

	-- we have to look ahead one token to determine whether this is an
	-- array ref, a function call, a struct ref, or an identifier.
	-- there could be an arbitrary combination of some of these, so check
	-- in a loop until we don't find anything.

	while true do
		local aheadtoken = lex.nextToken()
		local realatom

		if aheadtoken.str == "[" then
			-- its an array reference. if there's a chain of array indices to
			-- consume, we need to consume them all here to make sure the tree
			-- is generated in an order such that the right-most array index
			-- is the lowest element in the tree, so that when going down the
			-- tree it "unwraps" the array type correctly.

			realatom = astnode_t("arrayref", token)
			realatom.base = atom
			realatom.indices = {}

			while aheadtoken.str == "[" do
				local index = {}

				index.expr = parser.parseExpression(lex)

				if not index.expr then
					return false
				end

				-- check for closing bracket

				token = lex.nextToken()

				if not parser.checkToken(token) then
					return false
				end

				if token.str ~= "]" then
					parser.err(token, "unexpected token, expected ]")
					return false
				end

				table.insert(realatom.indices, index)

				aheadtoken = lex.nextToken()
			end

			lex.lastToken(aheadtoken)
		elseif aheadtoken.str == "(" then
			-- its a function call

			realatom = astnode_t("call", token)

			realatom.funcname = atom
			realatom.args = {}

			-- parse argument list

			while true do
				aheadtoken = lex.nextToken()

				if not parser.checkToken(token, true) then
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

				table.insert(realatom.args, expr)

				aheadtoken = lex.nextToken()

				if aheadtoken.str == ")" then
					break
				elseif aheadtoken.str ~= "," then
					parser.err(aheadtoken, "unexpected token, expected ','")
					return false
				end
			end
		else
			lex.lastToken(aheadtoken)

			break
		end

		atom = realatom
	end

	return atom
end

function parser.parseDeclaration(lex, const)
	-- returns a def, caller decides whether to turn that into a statement.
	-- does define the symbol for you.

	local nametoken = lex.nextToken()

	if not parser.checkToken(nametoken) then
		return false
	end

	local def = def_t(nametoken.str, symboltypes.SYM_VAR)
	def.const = const

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
	else
		-- implicit type

		lex.lastToken(eqtoken)
	end

	local eqtoken = lex.nextToken()

	if not eqtoken.eof then
		if not parser.checkToken(eqtoken) then
			return false
		end

		if eqtoken.str ~= "=" then
			-- uninitialized variable

			lex.lastToken(eqtoken)
		else
			def.value = parser.parseExpression(lex)

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

			sym.ignore = true
		end
	end

	if not defineSymbol(parser.currentblock, def, nocheck) then
		parser.err(nametoken, string.format("%s already defined", def.name))
		return false
	end

	return def
end

function parser.parseType(lex)
	local type = type_t()

	local token = lex.nextToken()

	if not parser.checkToken(token) then
		return false
	end

	if token.str == "^" then
		type.pointer = true
		type.base = parser.parseType(lex)

		return type
	end

	local base = token.str

	type.base = base

	local curtype = type

	-- collect all of the array parts

	token = lex.nextToken()

	while token.str == "[" do
		local arrtype = type_t()
		curtype.base = arrtype
		arrtype.base = base
		arrtype.array = true

		curtype = arrtype

		token = lex.nextToken()

		if token.str == "]" then
			return type
		end

		lex.lastToken(token)

		arrtype.arraybounds = parser.parseExpression(lex)

		if not arrtype.arraybounds then
			return false
		end

		token = lex.nextToken()

		if not parser.checkToken(token) then
			return false
		end

		if token.str ~= "]" then
			parser.err(token, "expected ]")
			return false
		end

		token = lex.nextToken()
	end

	lex.lastToken(token)

	return type
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

		if not fntype.funcdef then
			parser.err(aheadtoken, string.format("%s is not a function type"), fnptrname)
			return false
		end

		aheadtoken = lex.nextToken()

		if not parser.checkToken(aheadtoken) then
			return false
		end
	end

	local funcdef = funcdef_t(aheadtoken.str)

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

			if (aheadtoken.str == "in") or
				(aheadtoken.str == "out") then

				if aheadtoken.str == "in" then
					arg.inspec = true
				else
					arg.outspec = true
				end

				aheadtoken = lex.nextToken()

				if not parser.checkToken(aheadtoken, true) then
					return false
				end
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

function parser.parseFunction(lex, macro)
	local funcdef = parser.parseFunctionSignature(lex)

	if not funcdef then
		return false
	end

	funcdef.body = parser.parseBlock(lex, {"end"}, true)

	if not funcdef.body then
		return false
	end

	-- consume the token for end

	local tok = lex.nextToken()

	local def = def_t(funcdef.name, symboltypes.SYM_VAR)
	def.const = macro
	def.funcdef = funcdef

	local nocheck = not macro

	if nocheck then
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
	end

	if not defineSymbol(parser.currentblock, def, nocheck) then
		parser.err(nametoken, string.format("%s already defined", def.name))
		return false
	end
end

parser.keywords = {
	["if"] = function (lex)
		local expr = parser.parseExpression(lex)

		if not expr then
			return false
		end

		local aheadtoken = lex.nextToken()

		if aheadtoken.str ~= "then" then
			parser.err(aheadtoken, "expected 'then'")
			return false
		end

		local node = astnode_t("if", expr.errtoken)

		node.bodies = {}
		node.elseblock = nil

		local elseblock = false

		local terminators = {
			"end",
			"else",
			"elseif"
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

			if aheadtoken.str == "end" then
				break
			elseif aheadtoken.str == "else" then
				if elseblock then
					parser.err(aheadtoken, "already declared an else block")
					return false
				end

				elseblock = true
			elseif aheadtoken.str == "elseif" then
				expr = parser.parseExpression(lex)

				if not expr then
					return false
				end

				aheadtoken = lex.nextToken()

				if aheadtoken.str ~= "then" then
					parser.err(aheadtoken, "expected 'then'")
					return false
				end
			end
		end

		return node
	end,

	["while"] = function (lex)
		local expr = parser.parseExpression(lex)

		if not expr then
			return false
		end

		local aheadtoken = lex.nextToken()

		if aheadtoken.str ~= "do" then
			parser.err(aheadtoken, "expected 'do'")
			return false
		end

		local node = astnode_t("while", expr.errtoken)

		local block = parser.parseBlock(lex, {"end"})

		if not block then
			return false
		end

		block.conditional = expr

		node.block = block

		-- eat the end token

		lex.nextToken()

		return node
	end,

	["goto"] = function (lex)
		local nametoken = lex.nextToken()

		if not parser.checkToken(nametoken) then
			return false
		end

		local node = astnode_t("goto", nametoken)

		node.name = nametoken.str

		return node
	end,

	["break"] = function (lex)
		return astnode_t("break", parser.errtoken)
	end,

	["continue"] = function (lex)
		return astnode_t("continue", parser.errtoken)
	end,

	["return"] = function (lex)
		local expr = parser.parseExpression(lex)

		if not expr then
			return false
		end

		local node = astnode_t("return", expr.errtoken)

		node.expr = expr

		return node
	end,

	["type"] = function (lex)
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

		local def = typedef_t(nametoken.str, type)

		if not defineSymbol(parser.currentblock, def, false) then
			parser.err(nametoken, string.format("%s already defined", def.name))
			return false
		end

		return nil
	end,

	["struct"] = function (lex)
		error("unimp")
	end,

	["union"] = function (lex)
		error("unimp")
	end,

	["fnptr"] = function (lex)
		local funcdef = parser.parseFunctionSignature(lex)

		if not funcdef then
			return false
		end

		local type = type_t()
		type.funcdef = funcdef
		type.pointer = true

		local def = typedef_t(funcdef.name, type)

		if not defineSymbol(parser.currentblock, def, false) then
			parser.err(nametoken, string.format("%s already defined", def.name))
			return false
		end

		return nil
	end,

	["extern"] = function (lex)
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

			def = parser.parseDeclaration(lex)

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

		def.extern = true

		return nil
	end,

	["const"] = function (lex)
		parser.parseDeclaration(lex, true)

		return nil
	end,

	["begin"] = function (lex)
		local node = parser.parseBlock(lex, {"end"})

		if not node then
			return false
		end

		-- eat the end token

		lex.nextToken()

		return node
	end,

	["fn"] = parser.parseFunction,

	["macro"] = function (lex)
		return parser.parseFunction(lex, true)
	end,
}

parser.operators = {
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
	["^"] = {
		precedence = 14,
		associativity = LEFT,
	},
	["|"] = {
		precedence = 13,
		associativity = LEFT,
	},
	["and"] = {
		precedence = 12,
		associativity = LEFT,
	},
	["or"] = {
		precedence = 11,
		associativity = LEFT,
	},
}

parser.decls = {
	["fn"] = function (lex)
		local funcdef = parser.parseFunctionSignature(lex)

		if not funcdef then
			return false
		end

		local def = def_t(funcdef.name, symboltypes.SYM_VAR)
		def.funcdef = funcdef

		if not defineSymbol(parser.currentblock, def, false) then
			parser.err(nametoken, string.format("%s already defined", def.name))
			return false
		end

		return def
	end,
}

return parser