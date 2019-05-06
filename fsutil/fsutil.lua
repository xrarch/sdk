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

if #arg < 2 then
	usage()
	return
end

local cmd = arg[2]

if cmd == "f" then -- format
	fat.format(dimg)
else
	local fs = fat.mount(dimg)
	if not fs then
		print("error: couldn't mount image")
		return
	end

	if cmd == "ls" then
		if arg[3] then
			local d = fs:path(arg[3])
			if not d then
				print("couldn't open "..arg[3].." as a directory")
			elseif d.type ~= "dir" then
				print("not a directory")
			else
				local l = d:list()
				d:close()

				print("listing for "..arg[3]..":")
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
		end
	elseif cmd == "w" then
		if arg[3] and arg[4] then
			local f, dir = fs:path(arg[3])
			if not f then
				print("couldn't open "..arg[3])
			else
				local inf = io.open(arg[4], "rb")
				if not inf then
					print("couldn't open "..arg[4])
				else
					f:write(inf:read("*all"))
					inf:close()
				end
			end
			if dir then dir:close() end
		else
			usage()
		end
	elseif cmd == "r" then
		if arg[3] then
			local f, dir = fs:path(arg[3])
			if not f then
				print("couldn't open "..arg[3])
			else
				io.write(f:read())
			end
			if dir then dir:close() end
		else
			usage()
		end
	elseif cmd == "d" then
		if arg[3] then
			local f, dir = fs:path(arg[3])
			if not f then
				print("couldn't open "..arg[3])
			else
				f:delete()
			end
			if dir then dir:close() end
		else
			usage()
		end
	elseif cmd == "i" then
		fs:dumpinfo()
	end

	fs:unmount()
end