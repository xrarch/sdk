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
	{4, "version"},
	{4, "magic"},
	{4, "size"},
	{4, "numfiles"},
	{4, "dirty"},
	{4, "blocksused"},
	{4, "numdirs"},
	{4, "reservedblocks"},
	{4, "fatstart"},
	{4, "fatsize"},
	{4, "rootstart"},
	{4, "datastart"},
	{4, "rootsize"},
}

local dirent_s = struct {
	{4, "type"},
	{4, "permissions"},
	{4, "uid"},
	{4, "reserved"},
	{4, "timestamp"},
	{4, "startblock"},
	{4, "size"},
	{4, "bytesize"},
	{32, "name"},
}

local fat_s = struct {
	{4, "block"}
}

local fat = {}

function fat.mount(image, offset)
	local fs = {}

	fs.image = block.new(image, 4096, offset)
	local img = fs.image

	fs.superblock_b = img:readBlock(0)
	fs.superblock = cast(superblock_s, fs.superblock_b, 0)
	local superblock = fs.superblock

	if superblock.gv("magic") ~= 0xAFBBAFBB then
		print(string.format("couldn't mount image: bad magic %x", superblock.gv("magic")))
		return false
	elseif superblock.gv("version") ~= 0x5 then
		print(string.format("couldn't mount image: bad version %d, wanted 5", superblock.gv("version")))
		return false
	end

	local fatstart = superblock.gv("fatstart")
	local fatsize = superblock.gv("fatsize")
	local datastart = superblock.gv("datastart")
	local rootstart = superblock.gv("rootstart")
	local rootsize = superblock.gv("rootsize")

	local fat = {}

	local cnodes = {}

	local function fatblockbybn(bn)
		return math.floor((bn * 4)/4096)
	end

	function fs.getblockstatus(bn)
		local fbn = fatblockbybn(bn)

		local fat_b = fat[fbn]

		if not fat_b then
			fat[fbn] = img:readBlock(fbn+fatstart)
			fat_b = fat[fbn]
		end

		local b = cast(fat_s, fat_b, (bn % 1024)*4)

		return b.gv("block")
	end
	local getblockstatus = fs.getblockstatus

	function fs.setblockstatus(bn, status)
		local fbn = fatblockbybn(bn)

		local fat_b = fat[fbn]

		if not fat_b then
			fat[fbn] = img:readBlock(fbn+fatstart)
			fat_b = fat[fbn]
		end

		fat_b.dirty = true

		local b = cast(fat_s, fat_b, (bn % 1024)*4)

		b.sv("block", status)
	end
	local setblockstatus = fs.setblockstatus

	local function bfree(bn)
		setblockstatus(bn, 0)
	end

	local function balloc(link)
		link = link or 0xFFFFFFFF

		for i = 0, img.blocks-1 do
			if getblockstatus(i) == 0 then
				setblockstatus(i, link)
				img:writeBlock(i, {[0]=0}) -- zero out block
				return i
			end
		end

		error("ran out of blocks, TODO handle this nicer")

		return -1 -- no blocks left
	end

	function fs.node_t(parent, direntoff)
		local node = {}

		node.entry = 0xFFFFFFFF
		node.parent = parent
		node.direntoff = direntoff
		node.size = 0
		node.uid = 0
		node.permissions = 0
		node.dirty = false
		node.blocks = {}
		node.children = {}

		local function getdirent()
			if not node.parent then return end

			local dirent = {}

			if node.parent.read(dirent_s.size(), dirent, node.direntoff) < dirent_s.size() then
				error("oh no my parent didn't give me my dirent")
			end

			local direns = cast(dirent_s, dirent)

			return direns, dirent
		end

		local function dir_writeent(dirent, dir, off)
			if dir.write(dirent_s.size(), dirent, off) < dirent_s.size() then
				error("oh no my parent didn't let me write my dirent")
			end

			dir.dirty = true
		end

		local function writedirent(dirent)
			if not node.parent then error("oh no") end

			dir_writeent(dirent, node.parent, node.direntoff)
		end

		local function dir_getent(off, extend)
			local dirent = {}

			local br = node.read(dirent_s.size(), dirent, off)

			if br < dirent_s.size() then
				if (br == -1) and extend then
					node.write(dirent_s.size(), nil, off, true)
					br = node.read(dirent_s.size(), dirent, off)

					if br == -1 then
						error("couldn't extend dir")
					end
				else
					error("oh no i didn't give me a dirent")
				end
			end

			local direns = cast(dirent_s, dirent)

			return direns, dirent
		end

		local function dir_allocent()
			local off = 0

			for i = 1, 256 do -- 256 is maxsearch
				local direns, dirent = dir_getent(off, true)

				if direns.gv("type") == 0 then
					return direns, dirent, off
				end

				off = off + dirent_s.size()
			end
		end

		if parent then -- populate
			local direns, dirent = getdirent()

			if not direns then error("oh no") end

			node.permissions = direns.gv("permissions")
			node.uid = direns.gv("uid")
			node.entry = direns.gv("startblock")
			node.size = direns.gv("bytesize")
			node.name = direns.gs("name")

			local kind = direns.gv("type")

			if kind == 1 then
				node.kind = "file"
			elseif kind == 2 then
				node.kind = "dir"
			else
				error("oh no what even is "..tostring(kind))
			end
		end

		function node.delete()
			if node.root then
				return false, "can't delete root"
			end

			if node.kind == "dir" then -- check to make sure we contain no entries
				local off = 0

				while off < node.size do
					local direns, dirent = dir_getent(off)

					if direns.gv("type") ~= 0 then
						return false, "can't delete a directory with entries"
					end

					off = off + dirent_s.size()
				end
			end

			local direns, dirent = getdirent()

			if not direns then
				error("no dirent??")
			end

			node.trunc()

			direns.sv("type", 0)

			writedirent(dirent)

			node.deleted = true

			return true
		end

		local function rootupdate()
			superblock.sv("rootstart", node.entry)
			superblock.sv("rootsize", node.size)
			fs.superblock_b.dirty = true
		end

		function node.update(final)
			if not node.dirty then return end

			if node.deleted then return end

			if node.root then
				rootupdate()
			else
				local direns, dirent = getdirent()

				if not direns then return end

				if node.kind == "dir" then
					direns.sv("type", 2)
				elseif node.kind == "file" then
					direns.sv("type", 1)
				else
					error("oh no what even is "..tostring(node.kind))
				end

				direns.sv("permissions", node.permissions)
				direns.sv("uid", node.uid)
				direns.sv("startblock", node.entry)
				direns.sv("size", math.ceil(node.size / 4096))
				direns.sv("bytesize", node.size)
				direns.ss("name", node.name)

				writedirent(dirent)

				if node.parent then
					node.parent.update(final)
				end
			end

			for k,v in pairs(node.blocks) do
				if v.dirty then
					img:writeBlock(v.bn, v)
					v.dirty = false
				end
			end

			node.dirty = false
		end

		local function nextent(bn)
			if node.blocks[bn] then

			end
		end

		local function ngetb(bn, reading)
			if node.blocks[bn] then -- already cached
				return node.blocks[bn], node.blocks[bn].bn
			end

			local ent

			if bn == 0 then
				if node.entry == 0xFFFFFFFF then
					if reading then
						error("balloc on read")
					end

					ent = balloc()
					node.entry = ent
				else
					ent = node.entry
				end
			else
				local last, e = ngetb(bn-1, reading)

				ent = getblockstatus(e)

				if ent == 0xFFFFFFFF then
					if reading then
						error("balloc on read")
					end

					ent = balloc()
					setblockstatus(e, ent)
				end
			end

			node.blocks[bn] = img:readBlock(ent)
			node.blocks[bn].bn = ent
			return node.blocks[bn], ent
		end

		function node.read(bytes, tab, off)
			if off >= node.size then
				return -1
			end

			if (off + bytes) > node.size then
				bytes = node.size - off
			end

			if bytes == 0 then
				return 0
			end

			local tot = 0

			local tabindx = 0

			while tot < bytes do
				local b = ngetb(math.floor(off/4096), true)

				local m = math.min(bytes - tot, 4096 - (off % 4096))

				for i = 0, m-1 do
					tab[tabindx + i] = b[(off % 4096) + i]
				end

				tabindx = tabindx + m
				off = off + m
				tot = tot + m
			end

			return bytes
		end

		function node.write(bytes, tab, off, zeroes)
			if off > node.size then
				return -1
			end

			if bytes == 0 then
				return 0
			end

			local tot = 0

			local tabindx = 0

			while tot < bytes do
				local b, ent = ngetb(math.floor(off/4096))

				local m = math.min(bytes - tot, 4096 - (off % 4096))

				for i = 0, m-1 do
					if zeroes then
						b[(off % 4096) + i] = 0
					else
						b[(off % 4096) + i] = tab[tabindx + i]
					end
				end

				b.dirty = true

				tabindx = tabindx + m
				off = off + m
				tot = tot + m
			end

			if off > node.size then
				node.size = off
			end

			node.dirty = true

			return bytes
		end

		function node.trunc()
			local ent = node.entry

			while ent ~= 0xFFFFFFFF do
				local lent = ent
				ent = getblockstatus(ent)
				bfree(lent)
			end

			node.entry = 0xFFFFFFFF
			node.size = 0

			node.dirty = true
		end

		function node.lookdir(name)
			if node.kind ~= "dir" then
				error("oh no im not a directory u cant do that")
			end

			local off = 0

			while off < node.size do
				local direns, dirent = dir_getent(off)

				if direns.gv("type") ~= 0 then
					if direns.gs("name") == name then
						local n = fs.node_t(node, off)

						node.children[#node.children + 1] = n

						return n
					end
				end

				off = off + dirent_s.size()
			end
		end

		function node.createchild(name, kind)
			local direns, dirent, off = dir_allocent()

			direns.sv("type", kind)
			direns.sv("startblock", 0xFFFFFFFF)
			direns.sv("uid", node.uid)
			direns.sv("permissions", node.permissions)
			direns.sv("size", 0)
			direns.sv("bytesize", 0)
			direns.ss("name", name)

			node.write(dirent_s.size(), dirent, off)

			local child = fs.node_t(node, off)

			child.dirty = true

			node.dirty = true

			node.children[#node.children + 1] = child

			return child
		end

		function node.dirlist()
			local list = {}

			local off = 0

			while off < node.size do
				local direns, dirent = dir_getent(off)

				if direns.gv("type") ~= 0 then
					list[#list + 1] = {direns.gv("type"), direns.gs("name")}
				end

				off = off + dirent_s.size()
			end

			return list
		end

		cnodes[#cnodes + 1] = node

		return node
	end
	local node_t = fs.node_t

	fs.rootdir = node_t()
	local rootdir = fs.rootdir

	rootdir.entry = rootstart

	rootdir.root = true

	rootdir.kind = "dir"
	rootdir.size = rootsize

	function fs:path(path, create)
		local node = rootdir

		local str = true
		local off = 1

		while str do
			str, off = strtok(path, "/", off)

			if (not str) or (#str == 0) then
				break
			end

			if node.kind ~= "dir" then
				return false, node.name.." is not a directory"
			end

			local nn = nil

			-- check if node is already cached in parent dir's children
			for k,v in ipairs(node.children) do
				if (not v.deleted) and (v.name == str) then
					nn = v
				end
			end

			-- not so, try to get from dirent
			if not nn then
				nn = node.lookdir(str)
			end

			-- not in dirent either
			if not nn then
				if create then -- create
					local kind

					if path:sub(off,off) == "/" then
						kind = 2
					else
						kind = 1
					end

					nn = node.createchild(str, kind)

					print("created "..str)
				else
					return false, str.." does not exist"
				end
			end

			node = nn
		end

		return node
	end

	function fs:update()
		for k,v in ipairs(cnodes) do
			v.update()
		end

		if self.superblock_b.dirty then
			img:writeBlock(0, self.superblock_b)
			self.superblock_b.dirty = false
		end

		for i = 0, fatsize-1 do
			if fat[i] and fat[i].dirty then
				img:writeBlock(fatstart+i, fat[i])
				fat[i].dirty = false
			end
		end
	end

	return fs
end

function fat.format(image, offset)
	print("formatting...")

	local img = block.new(image, 4096, offset)

	local superblock_b = {}
	for i = 0, 4095 do
		superblock_b[i] = 0
	end

	local superblock = cast(superblock_s, superblock_b, 0)

	local reservedblocks = 15

	superblock.sv("magic", 0xAFBBAFBB)
	superblock.sv("version", 0x5)
	superblock.sv("size", img.blocks)
	superblock.sv("reservedblocks", reservedblocks)
	superblock.sv("fatstart", reservedblocks + 1)
	local fsize = math.ceil((img.blocks*4) / 4096)
	superblock.sv("fatsize", fsize)
	superblock.sv("rootstart", 0xFFFFFFFF)
	superblock.sv("datastart", fsize + reservedblocks + 2)
	superblock.sv("blocksused", fsize + reservedblocks + 1)
	superblock.sv("rootsize", 0)

	print("writing superblock")
	img:writeBlock(0, superblock_b)

	print("zeroing FAT")
	for i = 16, 16+fsize-1 do
		img:writeBlock(i, {[0]=0})
	end

	img:close()

	print("mounting")
	local fsm = fat.mount(image, offset)

	if not fsm then
		return false
	end

	print("reserving boot blocks")
	for i = 0, reservedblocks do
		fsm.setblockstatus(i, 0xFFFFFFFF)
	end

	print("reserving FAT")
	for i = reservedblocks+1, reservedblocks+fsize do
		fsm.setblockstatus(i, 0xFFFFFFFF)
	end

	print("updating")
	fsm:update()

	print("done")

	return true
end

return fat