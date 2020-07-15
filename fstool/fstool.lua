local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local fat = dofile(sd.."aisixfat.lua")

local dimg = arg[1]

local function usage()
	print("== fstool.lua ==")
	print("utility to manipulate aisixfat images")
	print("usage: fstool.lua [image] [command] [args] ...")
	print([[commands:
	f: format
	i: dump superblock info
	w [dest] [src]: write file from src to dest
	r [path]: read contents of file at path
	ls [path]: list contents of directory at path
	d [path]: delete file at path
]])
end

local offset = 0

local narg = {}

for k,v in ipairs(arg) do
	if v:sub(1,7) == "offset=" then
		offset = tonumber(v:sub(8))
	else
		narg[#narg + 1] = v
	end
end

arg = narg

if #arg < 2 then
	usage()
	os.exit(1)
end

local cmd = arg[2]

if cmd == "f" then -- format
	fat.format(dimg, offset)
else
	local fs = fat.mount(dimg, offset)
	if not fs then
		print("fstool: error: couldn't mount image")
		os.exit(1)
	end

	if cmd == "ls" then
		if arg[3] then
			local node, errmsg = fs:path(arg[3])
			if not node then
				print("fsutil: "..errmsg)
				os.exit(1)
			elseif node.kind ~= "dir" then
				print("fsutil: "..node.name.." isn't a directory")
				os.exit(1)
			end

			local l = node.dirlist()

			print("fsutil: listing for "..arg[3]..":")
			for k,v in ipairs(l) do
				io.write("\t"..v[2])
				if v[1] == 2 then
					print("/")
				else
					print("")
				end
			end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "w" then
		if arg[3] and arg[4] then
			local node, errmsg = fs:path(arg[3], true)
			if not node then
				print("fsutil: "..errmsg)
				os.exit(1)
			elseif node.kind == "dir" then
				print("fsutil: "..arg[3].." is a directory")
				os.exit(1)
			end

			local inf = io.open(arg[4], "rb")
			if not inf then
				print("fsutil: couldn't open "..arg[4])
				os.exit(1)
			else
				node.trunc()

				local tab = {}

				local s = inf:read("*a")

				for i = 1, #s do
					tab[i-1] = string.byte(s:sub(i,i))
				end

				if node.write(#s, tab, 0) < 0 then
					print("fsutil: couldn't write "..node.name)
				end
			end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "r" then
		if arg[3] then
			local node, errmsg = fs:path(arg[3])
			if not node then
				print("fsutil: "..errmsg)
				os.exit(1)
			end

			local tab = {}

			node.read(node.size, tab, 0)

			for i = 0, node.size-1 do
				io.write(string.char(tab[i]))
			end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "d" then
		if arg[3] then
			local node, errmsg = fs:path(arg[3])
			if not node then
				print("fsutil: "..errmsg)
				os.exit(1)
			end

			local ok, errmsg = node.delete()

			if not ok then
				print("fsutil: "..errmsg)
				os.exit(1)
			end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "i" then
		fs:dumpinfo()
	end

	fs:update()
end