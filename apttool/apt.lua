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

local aptv1_s = struct {
	{16, "label"},
	{128, "ptable"},
	{4, "magic"}
}

local aptv2_s = struct {
	{15, "bootcode"},
	{1, "ffifvariant"},
	{128, "ptable"},
	{4, "magic"},
	{16, "label"}
}

local aptpte_s = struct {
	{8, "label"},
	{4, "blocks"},
	{4, "status"}
}

local APTMAGIC = 0x4E4D494D
local PARTMAX = 8

local apt = {}

function apt.format(image, label, partitions)
	if #partitions > PARTMAX then
		print(string.format("apttool: too many partitions, maximum is 8"))
		return false
	end

	print("formatting with "..#partitions.." partitions...")

	local img = block.new(image, 512)

	if not img then
		print(string.format("apttool: %s: failed to open", image))
		return false
	end

	local vdb_b = img:readBlock(0)

	local vdb = cast(aptv2_s, vdb_b, 0)

	vdb.sv("ffifvariant", 0xFF)
	vdb.sv("magic", APTMAGIC)
	vdb.ss("label", label)

	local offset = 4

	for i = 0, PARTMAX-1 do
		local part = partitions[i+1]

		local pte = cast(aptpte_s, vdb_b, vdb.offsetof("ptable") + i*aptpte_s.size())

		if not part then
			pte.sv("status", 0)
		else
			pte.sv("status", 2)

			if part.blocks == -1 then
				pte.sv("blocks", img.blocks - offset)
			else
				pte.sv("blocks", part.blocks)
			end
			
			pte.ss("label", part.label)

			offset = offset + part.blocks
		end
	end

	img:writeBlock(0, vdb_b)
end

function apt.writeboot(image, binary)
	-- write a boot binary *around* the APT structures.

	local img = block.new(image, 512)

	if not img then
		print(string.format("apttool: %s: failed to open", image))
		return false
	end

	local bin = block.new(binary, 512)

	if not bin then
		print(string.format("apttool: %s: failed to open", binary))
		return false
	end

	local vdb_b = img:readBlock(0)
	local bin_b = bin:readBlock(0)

	for i = 0, 14 do
		-- write bootcode first part
		vdb_b[i] = bin_b[i]
	end

	for i = 164, 511 do
		-- write bootcode second part
		vdb_b[i] = bin_b[i]
	end

	img:writeBlock(0, vdb_b)
end

return apt