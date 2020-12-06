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
  wd [dest] [src]: write files to directory dest as specified in file src
  w [dest] [src]: write file from src to dest
  r [path]: read contents of file at path
  ls [path]: list contents of directory at path
  d [path]: delete file at path
  chmod [path] [bits]: change permissions bits
  chown [path] [uid]: change owner
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

local function writefile(fs, destpath, srcpath)
	local node, errmsg = fs:path(destpath, true)
	if not node then
		print("fstool: "..errmsg)
		os.exit(1)
	elseif node.kind == "dir" then
		print("fstool: "..arg[3].." is a directory")
		os.exit(1)
	end

	local inf = io.open(srcpath, "rb")
	if not inf then
		print("fstool: couldn't open "..srcpath)
		os.exit(1)
	else
		node.trunc()

		local tab = {}

		local s = inf:read("*a")

		for i = 1, #s do
			tab[i-1] = string.byte(s:sub(i,i))
		end

		if node.write(#s, tab, 0) < 0 then
			print("fstool: couldn't write "..node.name)
			os.exit(1)
		end
	end
end

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
				print("fstool: "..errmsg)
				os.exit(1)
			end

			local l, err = node.dirlist()

			if not l then
				print("fstool: "..err)
				os.exit(1)
			end

			print("fstool: listing for "..arg[3]..":")
			for k,v in ipairs(l) do
				io.write("\t"..v[2])
				if v[1] == "dir" then
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
			writefile(fs, arg[3], arg[4])
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "wd" then
		if arg[3] and arg[4] then
			local inf = io.open(arg[4], "r")

			if not inf then
				print("fstool: couldn't open "..arg[4])
				os.exit(1)
			end

			local line = inf:read("*l")

			while line do
				if (#line > 0) and (line:sub(1,1) ~= "#") then
					local comp = explode(" ", line)

					if #comp == 2 then
						writefile(fs, arg[3].."/"..comp[1], comp[2])
					end
				end

				line = inf:read("*l")
			end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "test" then
		if arg[3] then
			local node, errmsg = fs:path(arg[3], true)
			if not node then
				print("fstool: "..errmsg)
				os.exit(1)
			elseif node.kind ~= "dir" then
				print("fstool: "..arg[3].." isn't a directory")
				os.exit(1)
			end

			for i = 1, 1025 do
				node.createchild("t"..tostring(i), "file")
			end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "r" then
		if arg[3] then
			local node, errmsg = fs:path(arg[3])
			if not node then
				print("fstool: "..errmsg)
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
			local node, errmsg, dirnode, fname = fs:path(arg[3])
			if not node then
				print("fstool: "..errmsg)
				os.exit(1)
			end

			local ok, errmsg = dirnode.deletechild(fname)

			if not ok then
				print("fstool: "..errmsg)
				os.exit(1)
			end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "chmod" then
		if arg[3] and tonumber(arg[4]) then
			local node, errmsg = fs:path(arg[3])
			if not node then
				print("fstool: "..errmsg)
				os.exit(1)
			end

			local ok, errmsg = node.chmod(tonumber(arg[4]))

			if not ok then
				print("fstool: "..errmsg)
				os.exit(1)
			end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "chown" then
		if arg[3] and tonumber(arg[4]) then
			local node, errmsg = fs:path(arg[3])
			if not node then
				print("fstool: "..errmsg)
				os.exit(1)
			end

			local ok, errmsg = node.chown(tonumber(arg[4]))

			if not ok then
				print("fstool: "..errmsg)
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