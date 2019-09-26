local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

dofile(sd.."misc.lua")

local block = dofile(sd.."block.lua")

local superblock_s = struct {
	{1, "version"},
	{4, "magic"},
	{4, "size"},
	{4, "numfiles"},
	{1, "dirty"},
	{4, "blocksused"},
	{4, "numdirs"},
	{4, "reservedblocks"},
	{4, "fatstart"},
	{4, "fatsize"},
	{4, "rootstart"},
	{4, "datastart"},
}

local dirent_s = struct {
	{1, "type"},
	{1, "permissions"},
	{4, "uid"},
	{4, "reserved"},
	{4, "timestamp"},
	{4, "startblock"},
	{4, "size"},
	{4, "bytesize"},
	{37, "name"},
	{1, "nullterm"}
}

local fat_s = struct {
	{4, "block"}
}

local fat = {}

function fat.mount(image)
	local fs = {}

	fs.image = block.new(image, 4096)
	local img = fs.image

	fs.rSuperblock = img:readBlock(0)
	fs.superblock = cast(superblock_s, fs.rSuperblock, 0)
	local superblock = fs.superblock

	if superblock.gv("magic") ~= 0xAFBBAFBB then
		print("couldn't mount image: bad magic")
		return false
	elseif superblock.gv("version") ~= 0x4 then
		print("couldn't mount image: bad version")
		return false
	end

	local fatstart = superblock.gv("fatstart")
	local fatsize = superblock.gv("fatsize")
	local datastart = superblock.gv("datastart")
	local rootstart = superblock.gv("rootstart")

	local function fatblockbybn(bn)
		return math.floor((bn * 4)/4096)
	end

	fs.rootDir = img:readBlock(superblock.gv("rootstart"))
	local rootDir = fs.rootDir

	fs.fat = {}
	for i = 0, fatsize-1 do
		fs.fat[i] = img:readBlock(i+fatstart)
	end

	function fs:changeNumFiles(off)
		superblock.sv("numfiles", superblock.gv("numfiles") + off)
	end

	function fs:changeNumDirs(off)
		superblock.sv("numdirs", superblock.gv("numdirs") + off)
	end

	function fs:getBlockStatus(bn)
		local rFAT = self.fat[fatblockbybn(bn)]

		local b = cast(fat_s, rFAT, (bn % 1024)*4)

		return b.gv("block")
	end

	function fs:setBlockStatus(bn, status)
		local rFAT = self.fat[fatblockbybn(bn)]

		local b = cast(fat_s, rFAT, (bn % 1024)*4)

		b.sv("block", status)
	end

	function fs:freeBlock(bn)
		local o = fs:getBlockStatus(bn)
		fs:setBlockStatus(bn, 0)
		superblock.sv("blocksused", superblock.gv("blocksused") - 1)
		return o
	end

	function fs:allocateBlock(link)
		link = link or 0xFFFFFFFF

		for i = 0, img.blocks-1 do
			if fs:getBlockStatus(i) == 0 then
				fs:setBlockStatus(i, link)
				img:writeBlock(i, {[0]=0}) -- zero out block
				superblock.sv("blocksused", superblock.gv("blocksused") + 1)
				return i
			end
		end
		return -1 -- no blocks left
	end

	function fs:allocateBlocks(count, link)
		local blocklist = {}
		local last = link or 0xFFFFFFFF
		for i = 1, count do
			last = fs:allocateBlock(last)
			if last < 0 then
				for k,v in pairs(blocklist) do
					fs:freeBlock(v)
				end
				return -1
			end
			table.insert(blocklist, 1, last)
		end
		return blocklist
	end

	function fs:freeBlockChain(entry)
		while entry ~= 0xFFFFFFFF do
			entry = fs:freeBlock(entry)
		end
	end

	function fs:pullChain(entry)
		local chain = {entry}
		while entry ~= 0xFFFFFFFF do
			entry = fs:getBlockStatus(entry)
			if entry ~= 0xFFFFFFFF then
				chain[#chain + 1] = entry
			end
		end
		return chain
	end

	function fs:writeData(data)
		local datas = #data
		print("length: "..tostring(datas).." bytes")
		local blocks = math.ceil(datas / 4096)
		print("blocks: "..tostring(blocks))
		if blocks == 0 then blocks = 1 end

		local bc = fs:allocateBlocks(blocks)
		if not bc then
			return false
		end

		local bb = {}
		for i = 1, blocks do
			bb[i] = {bc[i], {}}
		end

		for i = 0, datas-1 do
			local c = data:sub(i+1,i+1)

			local bp = math.floor(i/4096)
			local bo = i % 4096

			bb[bp+1][2][bo] = string.byte(c)
		end

		for i = 1, blocks do
			img:writeBlock(bb[i][1], bb[i][2])
		end

		return blocks, datas, bc[1]
	end

	function fs:readData(start)
		local e = self:pullChain(start)

		local out = ""

		for k,v in ipairs(e) do
			local b = img:readBlock(v)
			for i = 0, 4095 do
				out = out..string.char(b[i])
			end
		end

		return out
	end

	function fs:bdir(bn) -- make bdirectory object from block number
		local dir = {}
		dir.bn = bn
		dir.block = img:readBlock(bn)

		dir.type = "dir"

		function dir:entry(name, st) -- look for entry of given name in directory, return casted struct
			if name == "" then
				return false
			end

			name = name:sub(1, 36)

			st = st or 1

			local lf = false
			for i = 0, 63 do
				local dirent = cast(dirent_s, self.block, i*64)
				if dirent.gv("type") ~= 0 then
					if dirent.gs("name") == name then
						return dirent
					end
				else
					lf = i*64
				end
			end
			
			-- noope, find DOOT yee

			if not lf then -- no free entries
				return false
			end

			local dirent = cast(dirent_s, self.block, lf)

			if st == 1 then
				fs:changeNumFiles(1)
			elseif st == 2 then
				fs:changeNumDirs(1)
			end

			print("fs: created "..name)
			dirent.ss("name", name)
			dirent.sv("type", st)
			local sblock = fs:allocateBlock()
			dirent.sv("startblock", sblock)
			dirent.sv("size", 1)

			if st == 1 then
				dirent.sv("bytesize", 0)
			elseif st == 2 then
				dirent.sv("bytesize", 4096)
			end

			return dirent
		end

		function dir:file(name)
			local f = self:entry(name, 1)

			if not f then
				return false
			end

			local file = {}
			file.f = f

			if f.gv("type") == 1 then
				file.type = "file"

				function file:write(data)
					fs:freeBlockChain(f.gv("startblock"))

					local ls, bs, ss = fs:writeData(data)
					f.sv("startblock", ss)
					f.sv("bytesize", bs)
					f.sv("size", ls)
				end

				function file:read()
					return fs:readData(f.gv("startblock")):sub(1, f.gv("bytesize"))
				end
			else
				file.type = "dir"
			end

			function file:delete()
				print("fsutil: deleting "..self.f.gs("name"))

				if self.type == "file" then
					fs:changeNumFiles(-1)
				elseif self.type == "dir" then
					local mdir = fs:bdir(self.f.gv("startblock"))
					local e = mdir:list()
					for k,v in ipairs(e) do
						local fe = mdir:file(v[2])
						fe:delete()
					end
					mdir:close()

					fs:changeNumDirs(-1)
				end

				fs:freeBlockChain(f.gv("startblock"))
				f.sv("type", 0)
			end

			return file
		end

		function dir:list()
			local list = {}

			for i = 0, 63 do
				local dirent = cast(dirent_s, self.block, i*64)
				if dirent.gv("type") ~= 0 then
					list[#list + 1] = {dirent.gv("type"), dirent.gs("name")}
				end
			end

			return list
		end

		function dir:close()
			img:writeBlock(self.bn, self.block)
			self = nil
		end

		return dir
	end

	function fs:path(path, sp)
		while path:sub(1,1) == "/" do -- skip trailing slashes
			path = path:sub(2)
		end

		local pt = 0

		if path:sub(-1,-1) == "/" then -- last character is a slash, this is a directory
			pt = 2
		else
			pt = 1 -- this is a file
		end

		while path:sub(-1,-1) == "/" do
			path = path:sub(1,-2)
		end

		local pc = explode("/", path)

		local cdir = self:bdir(rootstart)

		if #path == 0 then
			return cdir
		end

		for k,v in ipairs(pc) do
			if (k == #pc) and (sp) then -- stop penultimate
				return cdir, v
			end

			if (k == #pc) and (pt == 1) then
				local o = cdir:file(v)
				return o, cdir
			else
				local ndir = cdir:entry(v, 2)
				if not ndir then
					cdir:close()
					return false
				end
				cdir:close()

				if ndir.gv("type") == 2 then
					cdir = self:bdir(ndir.gv("startblock"))
				else
					return false
				end
			end
		end

		return cdir
	end

	function fs:dumpinfo()
		print(string.format([[general info:
	partition size: %d blocks
	blocks used: %d blocks
	number of reserved blocks: %d blocks
specific info:
	%d files
	%d directories]],
			superblock.gv("size"),
			superblock.gv("blocksused"),
			superblock.gv("reservedblocks"),
			superblock.gv("numfiles"),
			superblock.gv("numdirs")
		))
	end

	function fs:unmount()
		img:writeBlock(0, self.rSuperblock)
		for i = 0, fatsize-1 do
			img:writeBlock(fatstart+i, self.fat[i])
		end
		self = nil
	end

	return fs
end

function fat.format(image)
	print("formatting...")

	local img = block.new(image, 4096)

	local rSuperblock = {}
	for i = 0, 4095 do
		rSuperblock[i] = 0
	end

	local superblock = cast(superblock_s, rSuperblock, 0)

	local reservedblocks = 15

	superblock.sv("magic", 0xAFBBAFBB)
	superblock.sv("version", 0x4)
	superblock.sv("size", img.blocks)
	superblock.sv("reservedblocks", reservedblocks)
	superblock.sv("fatstart", reservedblocks + 1)
	local fsize = math.ceil((img.blocks*4) / 4096)
	superblock.sv("fatsize", fsize)
	superblock.sv("rootstart", fsize + reservedblocks + 1)
	superblock.sv("datastart", fsize + reservedblocks + 2)
	superblock.sv("blocksused", fsize + reservedblocks + 1)

	print("writing superblock")
	img:writeBlock(0, rSuperblock)

	print("zeroing FAT")
	for i = 16, 16+fsize-1 do
		img:writeBlock(i, {[0]=0})
	end

	print("zeroing root")
	img:writeBlock(fsize+16, {[0]=0})

	print("mounting")
	local fs = fat.mount(image)

	print("reserving blocks")
	for i = 0, reservedblocks do
		fs:setBlockStatus(i, 0xFFFFFFFF)
	end

	print("reserving FAT")
	for i = reservedblocks+1, reservedblocks+fsize do
		fs:setBlockStatus(i, 0xFFFFFFFF)
	end

	print("reserving root")
	fs:setBlockStatus(fsize+16, 0xFFFFFFFF)

	print("unmounting")
	fs:unmount()

	print("done")
end

return fat