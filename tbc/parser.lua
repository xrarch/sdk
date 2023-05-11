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

function parser.parseBlock(lex, terminators)
	-- each statement in a block is one of the following:
	-- declaration
	-- assignment
	-- expression with side effects (i.e. a function call)
	-- if statement
	-- while loop

	local lastblock = parser.currentblock

	terminators = terminators or {}

	local block = astnode_t("block")
	block.statements = {}
	block.scope = {}
	block.errtoken = nil

	local lastblock = parser.currentblock
	parser.currentblock = block

	block.parentblock = lastblock

	while true do
		local token = lex.nextToken()

		if token.eof then
			break
		end

		if token.value then
			parser.err(token, "unexpected numerical token")
			return false
		end

		if not block.errtoken then
			block.errtoken = token
		end

		local stmt = nil

		local kw = parser.keywords[token.str]

		if kw then
			stmt = kw(lex)
		else
			for k,v in ipairs(terminators) do
				if token.str == v then
					-- block is terminated.
					-- allow caller to consume terminator token.

					lex.lastToken(token)

					break
				end
			end

			-- this is either a declaration, an assignment, or an expression.

			local nexttoken = lex.nextToken()

			lex.lastToken(token)
			lex.lastToken(nexttoken)

			if nexttoken.str == ":" then
				-- declaration

				stmt = parser.parseDeclaration(lex)
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

					stmt = astnode_t("assign", atom.errtoken)

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

		if not stmt then
			return false
		end

		block.statements[#block.statements + 1] = stmt
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

function parser.parseAtom(lex, depth)
	-- an atom here means any individual value, such as an array reference,
	-- a variable reference, a numerical constant, or a parenthesized
	-- expression. lvalues and rvalues are parsed identically and are checked
	-- during a later stage of the compiler.

	depth = depth or 0

	local atom

	local token = lex.nextToken()

	if not parser.checkToken(token, true) then
		return false
	end

	if token.str == "(" then
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
		atom.precedence = math.huge

		return atom
	else
		-- identifier

		atom = astnode_t("id", token)

		atom.name = token.str
	end

	-- we have to look ahead one token to determine whether this is an
	-- array ref, a function call, a struct ref, or an identifier.
	-- there could be an arbitrary combination of some of these, so check
	-- in a loop until we don't find anything.

	local aheadtoken = lex.nextToken()

	local realatom

	while true do
		local gotnone = true

		if aheadtoken.str == "." then
			-- struct ref

			local realatom = astnode_t("structref", token)

			realatom.left = atom
			realatom.right = parser.parseAtom(lex, depth + 1)

			if not realatom.right then
				return false
			end

			atom = realatom

			aheadtoken = lex.nextToken()

			gotnone = false
		end

		if aheadtoken.str == "[" then
			-- its an array reference

			if depth > 0 then
				lex.lastToken(aheadtoken)

				return atom
			end

			realatom = astnode_t("arrayref", token)

			realatom.array = atom
			realatom.index = parser.parseExpression(lex)

			if not realatom.index then
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

			atom = realatom

			aheadtoken = lex.nextToken()

			gotnone = false
		end

		if aheadtoken.str == "(" then
			-- its a function call

			if depth > 0 then
				lex.lastToken(aheadtoken)

				return atom
			end

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

			atom = realatom

			aheadtoken = lex.nextToken()

			gotnone = false
		end

		if gotnone then
			lex.lastToken(aheadtoken)

			break
		end
	end

	return atom
end

function parser.parseDeclaration(lex, const)
	local def = {}
	def.const = const

	local nametoken = lex.nextToken()

	if not parser.checkToken(nametoken) then
		return false
	end

	def.name = nametoken.str

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
			def.value = parser.parseExpression()

			if not def.value then
				return false
			end
		end
	end

	local node = astnode_t("decl", nametoken)
	node.def = def

	if not defineSymbol(parser.currentblock, def.name, def) then
		parser.err(nametoken, string.format("%s already defined", def.name))
		return false
	end

	return node
end

function parser.parseType(lex)
	local type = {}
	type.pointer = false
	type.array = false
	type.arraybounds = nil
	type.primitive = nil

	local token = lex.nextToken()

	if not parser.checkToken(token) then
		return false
	end

	if token.str == "^" then
		type.pointer = true
		type.base = parser.parseType(lex)

		return type
	end

	type.base = token.str

	token = lex.nextToken()

	if token.str ~= "[" then
		lex.lastToken(token)

		return type
	end

	type.array = true

	token = lex.nextToken()

	if token.str == "]" then
		return type
	end

	lex.lastToken(token)

	type.arraybounds = parser.parseExpression(lex)

	if not type.arraybounds then
		return false
	end

	token = lex.nextToken()

	if token.str ~= "]" then
		parser.err(token, "expected ]")
		return false
	end

	return type
end

function parser.parseFunction(lex)
	error("unimp")
end

parser.keywords = {
	["if"] = function ()

	end,
	["while"] = function ()

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

	end,
	["struct"] = function (lex)

	end,
	["extern"] = function (lex)

	end,
	["const"] = function (lex)
		return parser.parseDeclaration(lex, true)
	end,

	["fn"] = parser.parseFunction,

	["macro"] = function (lex)
		local fndef = parser.parseFunction(lex)

		if not fndef then
			return false
		end

		fndef.nodetype = "macro"

		return fndef
	end,
}

parser.operators = {
	["*"] = {
		precedence = 10,
		associativity = LEFT,
	},
	["/"] = {
		precedence = 10,
		associativity = LEFT,
	},
	["%"] = {
		precedence = 10,
		associativity = LEFT,
	},
	["+"] = {
		precedence = 9,
		associativity = LEFT,
	},
	["-"] = {
		precedence = 9,
		associativity = LEFT,
	},
	["<<"] = {
		precedence = 8,
		associativity = LEFT,
	},
	[">>"] = {
		precedence = 8,
		associativity = LEFT,
	},
	["<"] = {
		precedence = 7,
		associativity = LEFT,
	},
	[">"] = {
		precedence = 7,
		associativity = LEFT,
	},
	["<="] = {
		precedence = 7,
		associativity = LEFT,
	},
	[">="] = {
		precedence = 7,
		associativity = LEFT,
	},
	["=="] = {
		precedence = 6,
		associativity = LEFT,
	},
	["!="] = {
		precedence = 6,
		associativity = LEFT,
	},
	["&"] = {
		precedence = 5,
		associativity = LEFT,
	},
	["^"] = {
		precedence = 4,
		associativity = LEFT,
	},
	["|"] = {
		precedence = 3,
		associativity = LEFT,
	},
	["and"] = {
		precedence = 2,
		associativity = LEFT,
	},
	["or"] = {
		precedence = 1,
		associativity = LEFT,
	}
}

parser.decls = {
	["fn"] = parser.parseFunctionSignature,
}

return parser