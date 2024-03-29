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
	{4, "dirty"},
	{4, "reservedblocks"},
	{4, "fatstart"},
	{4, "fatsize"},
	{4, "istart"},
	{4, "icount"},
	{4, "datastart"},
	{4, "datasize"},
	{4, "volsize"}
}

local dirent_s = struct {
	{4, "inum"},
	{60, "name"},
}

local inode_s = struct {
	{4, "type"},
	{4, "permissions"},
	{4, "uid"},
	{4, "iparent"},
	{4, "timestamp"},
	{4, "startblock"},
	{4, "gid"},
	{4, "bytesize"},
}

local fat_s = struct {
	{4, "block"}
}

local fat = {}

function fat.mount(image, offset, noroot)
	local fs = {}

	fs.image = block.new(image, 512, offset)
	local img = fs.image

	if not img then
		print("couldn't open image "..image)
		return false
	end

	fs.superblock_b = img:readBlock(0)
	fs.superblock = cast(superblock_s, fs.superblock_b, 0)
	local superblock = fs.superblock

	if superblock.gv("magic") ~= 0xAFBBAFBB then
		print(string.format("couldn't mount image: bad magic %x", superblock.gv("magic")))
		return false
	elseif superblock.gv("version") ~= 0x6 then
		print(string.format("couldn't mount image: bad version %d, wanted 6", superblock.gv("version")))
		return false
	end

	local ballochint = 0

	local fatstart = superblock.gv("fatstart")
	local fatsize = superblock.gv("fatsize")
	local datastart = superblock.gv("datastart")
	local istart = superblock.gv("istart")
	local icount = superblock.gv("icount")
	local isize = math.ceil((icount * inode_s.size())/512)

	local fat = {}

	local iblk = {}

	local cnodes = {}

	local function fatblockbybn(bn)
		return math.floor((bn * 4)/512)
	end

	function fs.getblockstatus(bn)
		local fbn = fatblockbybn(bn)

		local fat_b = fat[fbn]

		if not fat_b then
			fat[fbn] = img:readBlock(fbn+fatstart)
			fat_b = fat[fbn]
		end

		local b = cast(fat_s, fat_b, (bn % 128)*4)

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

		local b = cast(fat_s, fat_b, (bn % 128)*4)

		b.sv("block", status)
	end
	local setblockstatus = fs.setblockstatus

	local function bfree(bn)
		setblockstatus(bn, 0)
	end

	local function balloc(link)
		link = link or 0xFFFFFFFF

		for i = ballochint, img.blocks-1 do
			if getblockstatus(i) == 0 then
				ballochint = i
				setblockstatus(i, link)
				img:writeBlock(i, {[0]=0}) -- zero out block
				return i
			end
		end

		if ballochint ~= 0 then
			for i = 0, ballochint-1 do
				if getblockstatus(i) == 0 then
					ballochint = i
					setblockstatus(i, link)
					img:writeBlock(i, {[0]=0}) -- zero out block
					return i
				end
			end
		end

		error("ran out of blocks, TODO handle this nicer")

		return -1 -- no blocks left
	end

	function fs.iget(inum)
		if inum == 0 then
			error("inum = 0")
		end

		if inum >= icount then
			error("inum >= icount")
		end

		local ino = cnodes[inum]

		if not ino then
			local ioffb = inum * inode_s.size()

			local ibn = math.floor(ioffb / 512) + istart

			local ioff = ioffb % 512

			local i_b = iblk[ibn]

			if not i_b then
				iblk[ibn] = img:readBlock(ibn)
				i_b = iblk[ibn]
			end

			local in_s = cast(inode_s, i_b, ioff)
			ino = fs.node_t(in_s, inum)
			cnodes[inum] = ino
		end

		return ino
	end
	local iget = fs.iget

	function fs.isetup(parent, ino, kind)
		local uid
		local gid
		local permissions
		local iparent

		if parent then
			uid = parent.uid
			gid = parent.gid
			permissions = parent.permissions
			iparent = parent.inum
		else
			uid = 0
			gid = 0
			permissions = 493
			iparent = 1 -- root inode, iparent is 1 (itself)
		end

		if kind == "file" then
			permissions = band(permissions, 438)
		end

		ino.kind = kind
		ino.entry = 0xFFFFFFFF
		ino.uid = uid
		ino.gid = gid
		ino.permissions = permissions
		ino.size = 0
		ino.iparent = iparent
		ino.timestamp = getepoch()

		ino.dirty = true
	end
	local isetup = fs.isetup

	local function ialloc(parent, kind)
		for i = 2, icount-1 do -- no inode 0, and inode 1 is root, so start looking at inode 2
			local ino = iget(i)

			if ino.kind == "empty" then
				isetup(parent, ino, kind)
				return ino
			end
		end

		return nil -- no inodes left
	end

	function fs.node_t(ino_s, inum)
		local node = {}

		node.inum = inum
		node.entry = 0xFFFFFFFF
		node.timestamp = 0
		node.parent = parent
		node.size = 0
		node.uid = 0
		node.gid = 0
		node.permissions = 0
		node.dirty = false
		node.blocks = {}
		node.children = {}

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

			for i = 1, 2048 do -- 2048 is maxsearch
				local direns, dirent = dir_getent(off, true)

				if direns.gv("inum") == 0 then
					return direns, dirent, off
				end

				off = off + dirent_s.size()
			end
		end

		node.permissions = ino_s.gv("permissions")
		node.uid = ino_s.gv("uid")
		node.gid = ino_s.gv("gid")
		node.entry = ino_s.gv("startblock")
		node.size = ino_s.gv("bytesize")
		node.iparent = ino_s.gv("iparent")
		node.timestamp = ino_s.gv("timestamp")

		local kind = ino_s.gv("type")

		if kind == 1 then
			node.kind = "file"
		elseif kind == 2 then
			node.kind = "dir"
		elseif kind == 0 then
			node.kind = "empty"
		else
			error("oh no what even is "..tostring(kind))
		end

		function node.chmod(bits)
			node.permissions = bits

			node.dirty = true

			return true
		end

		function node.chown(uid)
			node.uid = uid

			node.dirty = true

			return true
		end

		function node.chgrp(gid)
			node.gid = gid

			node.dirty = true

			return true
		end

		function node.delete()
			if inum == 1 then
				return false, "can't delete root"
			end

			if node.kind == "dir" then -- check to make sure we contain no entries
				local off = 0

				while off < node.size do
					local direns, dirent = dir_getent(off)

					if direns.gv("inum") ~= 0 then
						return false, "can't delete a directory with entries"
					end

					off = off + dirent_s.size()
				end
			end

			node.trunc()

			node.kind = "empty"

			node.deleted = true

			return true
		end

		function node.update()
			if not node.dirty then return end

			if node.deleted then return end

			if node.kind == "dir" then
				ino_s.sv("type", 2)
			elseif node.kind == "file" then
				ino_s.sv("type", 1)
			else
				error("oh no what even is "..tostring(node.kind))
			end

			ino_s.sv("permissions", node.permissions)
			ino_s.sv("uid", node.uid)
			ino_s.sv("gid", node.gid)
			ino_s.sv("startblock", node.entry)
			ino_s.sv("bytesize", node.size)
			ino_s.sv("iparent", node.iparent)
			ino_s.sv("timestamp", node.timestamp)

			for k,v in pairs(node.blocks) do
				if v.dirty then
					img:writeBlock(v.bn, v)
					v.dirty = false
				end
			end

			ino_s.t.dirty = true

			node.dirty = false
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
				local b = ngetb(math.floor(off/512), true)

				local m = math.min(bytes - tot, 512 - (off % 512))

				for i = 0, m-1 do
					tab[tabindx + i] = b[(off % 512) + i]
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
				local b, ent = ngetb(math.floor(off/512))

				local m = math.min(bytes - tot, 512 - (off % 512))

				for i = 0, m-1 do
					if zeroes then
						b[(off % 512) + i] = 0
					else
						b[(off % 512) + i] = tab[tabindx + i]
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

			node.timestamp = getepoch()

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

			node.blocks = {}

			node.dirty = true
		end

		function node.lookdir(name)
			if node.kind ~= "dir" then
				error("oh no im not a directory u cant do that")
			end

			if name == "." then
				return node
			end

			if name == ".." then
				return iget(node.iparent)
			end

			local off = 0

			while off < node.size do
				local direns, dirent = dir_getent(off)

				if direns.gv("inum") ~= 0 then
					if direns.gs("name") == name then
						local n = iget(direns.gv("inum"))

						return n
					end
				end

				off = off + dirent_s.size()
			end
		end

		function node.deletechild(name)
			if node.kind ~= "dir" then
				error("oh no im not a directory u cant do that")
			end

			local off = 0

			while off < node.size do
				local direns, dirent = dir_getent(off)

				if direns.gv("inum") ~= 0 then
					if direns.gs("name") == name then
						local n = iget(direns.gv("inum"))

						local r, m = n.delete()

						if not r then
							return false, m
						end

						direns.sv("inum", 0)

						node.write(dirent_s.size(), dirent, off)

						return true
					end
				end

				off = off + dirent_s.size()
			end

			return false, "no such file or directory"
		end

		function node.createchild(name, kind)
			local ino = ialloc(node, kind)

			if not ino then
				return false
			end

			local direns, dirent, off = dir_allocent()

			direns.ss("name", name)
			direns.sv("inum", ino.inum)

			node.write(dirent_s.size(), dirent, off)

			node.dirty = true

			return ino
		end

		function node.dirlist()
			if node.kind ~= "dir" then
				return false, "not a directory"
			end

			local list = {}

			local off = 0

			while off < node.size do
				local direns, dirent = dir_getent(off)

				local dinum = direns.gv("inum")

				if dinum ~= 0 then
					local ino = iget(dinum)

					list[#list + 1] = {ino.kind, direns.gs("name")}
				end

				off = off + dirent_s.size()
			end

			return list
		end

		return node
	end
	local node_t = fs.node_t

	if not noroot then
		fs.rootdir = iget(1)
	end

	local rootdir = fs.rootdir

	function fs:path(path, create, dir)
		local node = rootdir

		local str = true
		local off = 1

		local ln = rootdir

		local lnm = "/"

		local created = false

		while str do
			str, off = strtok(path, "/", off)

			if (not str) or (#str == 0) then
				break
			end

			ln = node

			if node.kind ~= "dir" then
				return false, lnm.." is not a directory"
			end

			local nn = node.lookdir(str)

			-- not in dirent
			if not nn then
				if create then -- create
					local kind

					if path:sub(off,off) == "/" then
						kind = "dir"
					else
						kind = "file"
					end

					nn = node.createchild(str, kind)

					created = true

					-- print("created "..str)
				else
					return false, str.." does not exist"
				end
			end

			node = nn
			lnm = str
		end

		return node, nil, ln, lnm, created
	end

	function fs:update()
		for k,v in pairs(cnodes) do
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

		for i = istart, istart+isize-1 do
			if iblk[i] and iblk[i].dirty then
				img:writeBlock(i, iblk[i])
				iblk[i].dirty = false
			end
		end
	end

	return fs
end

function fat.format(image, offset)
	print("formatting...")

	local img = block.new(image, 512, offset)

	local superblock_b = {}
	for i = 0, 511 do
		superblock_b[i] = 0
	end

	local superblock = cast(superblock_s, superblock_b, 0)

	local reservedblocks = 63

	local fatsize = math.ceil((img.blocks*4) / 512)

	local fatstart = reservedblocks + 1

	local istart = fatstart + fatsize

	local icount = math.floor(img.blocks/32)

	local isize = math.ceil((icount * inode_s.size()) / 512)

	local datastart = istart + isize

	superblock.sv("magic", 0xAFBBAFBB)
	superblock.sv("version", 0x6)
	superblock.sv("reservedblocks", reservedblocks)
	superblock.sv("fatstart", fatstart)
	superblock.sv("fatsize", fatsize)
	superblock.sv("istart", istart)
	superblock.sv("icount", icount)
	superblock.sv("datastart", datastart)
	superblock.sv("datasize", img.blocks)
	superblock.sv("volsize", img.blocks)

	print("size: "..tostring(img.blocks * 512))

	print("writing superblock")
	img:writeBlock(0, superblock_b)

	print("zeroing FAT")
	for i = fatstart, fatstart+fatsize-1 do
		img:writeBlock(i, {[0]=0})
	end

	print("fatsize: "..tostring(fatsize))

	print("zeroing ilist")
	for i = istart, istart+isize-1 do
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
	for i = fatstart, fatstart+fatsize-1 do
		fsm.setblockstatus(i, 0xFFFFFFFF)
	end

	print("reserving ilist")
	for i = istart, istart+isize-1 do
		fsm.setblockstatus(i, 0xFFFFFFFF)
	end

	fsm.isetup(nil, fsm.rootdir, "dir")

	print("updating")
	fsm:update()

	print("done")

	return true
end

return fat