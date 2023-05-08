local lexer = require("lexer")

local parser = {}

local function astnode_t(type)
	-- create and initialize an AST node

	local node = {}
	node.nodetype = type

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

			if not parser.checkToken(nexttoken, true) then return false end

			if nexttoken.str == ":" then
				-- declaration

				stmt = parser.parseDeclaration(lex)
			elseif nexttoken.str == "=" then
				-- assignment

				stmt = parser.parseAssignment(lex)
			else
				-- expression

				stmt = parser.parseExpression(lex)
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

function parser.parseAssignment(lex)
	error("unimp")
end

function parser.parseExpression(lex)
	error("unimp")
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

	local node = astnode_t("decl")
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
		type.derived = parser.parseType(lex)

		return type
	end

	type.derived = token.str

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
		local node = astnode_t("return")

		node.expr = parser.parseExpression(lex)

		if not node.expr then return false end

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

		if not fndef then return false end

		fndef.type = "macro"

		return fndef
	end,
}

parser.decls = {
	["fn"] = parser.parseFunctionSignature,
}

return parser