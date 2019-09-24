local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local aixo = dofile(sd.."aixo.lua")

local dimg = arg[1]

local function usage()
	print("== objtool.lua ==")
	print("utility to manipulate AIsiX Object (AIXO) images")
	print("usage: objtool.lua [command] [args] ...")
	print([[commands:
	symbols [aixo]: dump symbols
	fixups [aixo]: dump hanging symbols
	flatten [aixo] <relocation base>: flatten an aixo file (convert to raw binary)
	link [output] [aixo1 aixo2 ... ]: link 2 or more aixo files
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

	local image = aixo.new(arg[2])
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
		print("objtool: no symbols exposed!")
	end
elseif arg[1] == "fixups" then
	if not arg[2] then
		usage()
		return
	end

	local image = aixo.new(arg[2])
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
		print("objtool: no unresolved symbols!")
	end
elseif arg[1] == "flatten" then
	if not arg[2] then
		usage()
		return
	end

	local image = aixo.new(arg[2])
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

	local out = aixo.new(arg[2])
	if not out then
		return
	end

	for i = 3, #arg do
		local image = aixo.new(arg[i])
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
	print("objtool: not a command: "..arg[1])
	usage()
	return
end

return true