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
	print("== fsutil.lua ==")
	print("utility to manipulate aisixfat images")
	print("usage: fsutil.lua [image] [command] [args] ...")
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
		print("fsutil: error: couldn't mount image")
		os.exit(1)
	end

	if cmd == "ls" then
		if arg[3] then
			local d, dir = fs:path(arg[3])
			if not d then
				print("fsutil: couldn't open "..arg[3])
			elseif d.type ~= "dir" then
				print("fsutil: "..arg[3].." not a directory")
			elseif d.f then
				print("fsutil: "..arg[3].." not opened as a directory, add a slash to the end")
			else
				local l = d:list()
				d:close()

				print("fsutil: listing for "..arg[3]..":")
				for k,v in ipairs(l) do
					io.write("\t"..v[2])
					if v[1] == 2 then
						print("/")
					else
						print("")
					end
				end
			end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "w" then
		if arg[3] and arg[4] then
			local f, dir = fs:path(arg[3])
			if not f then
				print("fsutil: couldn't open "..arg[3])
				os.exit(1)
			elseif f.type == "dir" then
				print("fsutil: "..arg[3].." is a directory")
				os.exit(1)
			else
				local inf = io.open(arg[4], "rb")
				if not inf then
					print("fsutil: couldn't open "..arg[4])
					os.exit(1)
				else
					f:write(inf:read("*all"))
					inf:close()
				end
			end
			if dir then dir:close() end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "r" then
		if arg[3] then
			local f, dir = fs:path(arg[3])
			if not f then
				print("fsutil: couldn't open "..arg[3])
				os.exit(1)
			elseif f.type == "dir" then
				print("fsutil: "..arg[3].." is a directory")
				os.exit(1)
			else
				io.write(f:read())
			end
			if dir then dir:close() end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "d" then
		if arg[3] then
			local f, dir = fs:path(arg[3])
			if not f then
				print("fsutil: couldn't open "..arg[3])
				os.exit(1)
			elseif not f.f then
				print("fsutil: couldn't open "..arg[3].." for deletion; remove any slashes at the end of the path")
				os.exit(1)
			else
				f:delete()
			end
			if dir then dir:close() end
		else
			usage()
			os.exit(1)
		end
	elseif cmd == "i" then
		fs:dumpinfo()
	end

	fs:unmount()
end