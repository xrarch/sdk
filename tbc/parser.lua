local lexer = require("lexer")

local parser = {}

local function astnode_t()
	-- create and initialize an AST node

	local node = {}

	return node
end

function parser.err(token, err)
	print(string.format("tbc: %s:%d: %s", token.filename, token.linenumber, err))
end

function parser.parse(filename, file, incdir, libdir, symbols)
	local lex = lexer.new(filename, file, incdir, libdir, symbols)

	return parser.parseBlock(lex)
end

function parser.parseBlock(lex)
	-- each statement in a block is one of the following:
	-- declaration
	-- assignment
	-- function call
	-- if statement
	-- while loop

	local block = astnode_t()

	return block
end

return parser