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
	os.exit(1)
end

if arg[1] == "symbols" then
	if not arg[2] then
		usage()
		os.exit(1)
	end

	local image = aixo.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
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
		os.exit(1)
	end

	local image = aixo.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
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
		os.exit(1)
	end

	local image = aixo.new(arg[2])
	if not image then
		os.exit(1)
	end

	if not image:load() then
		os.exit(1)
	end

	if not image:flatten(tonumber(arg[3])) then
		os.exit(1)
	end
elseif arg[1] == "link" then
	local fragment = false

	if arg[2] == "-f" then
		fragment = true
		table.remove(arg, 2)
	end

	if not (arg[2] and arg[3]) then
		usage()
		return
	end

	local linked = {}

	local out = aixo.new(arg[2])
	if not out then
		return
	end

	for i = 3, #arg do
		local imgname = arg[i]

		if linked[arg[i]] then
			print("objtool: warning: ignoring duplicate object "..arg[i])
		else
			linked[arg[i]] = true

			if imgname:sub(1,2) == "L/" then
				imgname = sd.."../dragonfruit/runtime/lib/"..imgname:sub(3)
			end

			local image = aixo.new(imgname)
			if not image then
				os.exit(1)
			end

			if not image:load() then
				os.exit(1)
			end

			if not out:link(image) then
				os.exit(1)
			end
		end
	end

	if out.fixupCount > 0 then
		if not fragment then
			print("objtool: error: unresolved symbols:")

			for k,v in ipairs(out.fixups) do
				print("  "..v[1].." in "..v[3])
			end

			os.exit(1)
		end
	end

	if not out:write() then
		os.exit(1)
	end
else
	print("objtool: not a command: "..arg[1])
	usage()
	
	os.exit(1)
end

return true