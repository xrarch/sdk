local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local apt = dofile(sd.."apt.lua")

local function usage()
	print("== apttool.lua ==")
	print("utility to manipulate APT images")
	print("usage: apttool.lua [image] [command] [args] ...")
	print([[commands:
  f     [label] [part0label] [part0len] ...: format
  wb    [bin]: write a boot binary
]])
end

if #arg < 2 then
	usage()
	os.exit(1)
end

local dimg = arg[1]
local cmd = arg[2]

if cmd == "f" then
	if #arg < 3 then
		usage()
		os.exit(1)
	end

	if (#arg-3) % 2 == 1 then
		usage()
		os.exit(1)
	end

	local parts = {}

	for i = 4, #arg, 2 do
		local p = {}

		p.label = arg[i]
		p.blocks = tonumber(arg[i+1])

		if not p.blocks then
			usage()
			os.exit(1)
		end

		parts[#parts+1] = p
	end

	apt.format(dimg, arg[3], parts)
elseif cmd == "wb" then
	if #arg < 3 then
		usage()
		os.exit(1)
	end

	apt.writeboot(dimg, arg[3])
end