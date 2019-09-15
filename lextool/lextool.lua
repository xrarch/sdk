local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local lex = dofile(sd.."lex.lua")

local dimg = arg[1]

local function usage()
	print("== lextool.lua ==")
	print("utility to manipulate LIMN EXecutable (LEX) images")
	print("usage: lextool.lua [command] [args] ...")
	print([[commands:
	symbols [lex]: dump symbols
	fixups [lex]: dump hanging symbols
	flatten [lex] <relocation base>: flatten a lex file (convert to raw binary) !!! OVERWRITES ORIGINAL !!!
	link [output] [lex1 lex2 ... ]: link 2 or more lex files
]])
end

if #arg < 1 then
	usage()
	return
end

if arg[1] == "symbols" then
	if not arg[2] then
		usage()
		return
	end

	local image = lex.new(arg[2])
	if not image then
		return
	end

	if not image:load() then
		return
	end

	local x = false

	for k,v in pairs(image.symbols) do
		print(string.format("%s = $%X", k, v))
		x = true
	end

	if not x then
		print("lextool: no symbols exposed!")
	end
elseif arg[1] == "fixups" then
	if not arg[2] then
		usage()
		return
	end

	local image = lex.new(arg[2])
	if not image then
		return
	end

	if not image:load() then
		return
	end

	local x = false

	for k,v in ipairs(image.fixups) do
		print(string.format("%s @ $%X", v[1], v[2]))
		x = true
	end

	if not x then
		print("lextool: no unresolved symbols!")
	end
elseif arg[1] == "flatten" then
	if not arg[2] then
		usage()
		return
	end

	local image = lex.new(arg[2])
	if not image then
		return
	end

	if not image:load() then
		return
	end

	if not image:flatten(tonumber(arg[3])) then
		return
	end
elseif arg[1] == "link" then
	if not (arg[2] and arg[3] and arg[4]) then
		usage()
		return
	end

	local out = lex.new(arg[2])
	if not out then
		return
	end

	for i = 3, #arg do
		local image = lex.new(arg[i])
		if not image then
			return
		end

		if not image:load() then
			return
		end

		if not out:link(image) then
			return
		end

		if not out:write() then
			return
		end
	end
else
	print("lextool: not a command: "..arg[1])
	usage()
	return
end