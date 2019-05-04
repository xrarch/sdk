--[[

	the most stupid assembler in the history of mankind, literally garbo
	don't @ me

	also don't try to read it or you'll lose faith in humanity
	and also question my intelligence

	its this bad since its a frankenstein with 100 things shoehorned in

	should definitely be entirely replaced with something sane eventually

]]

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

local tinst = dofile(sd.."inst.lua")
local inst, regs = tinst[1], tinst[2]

local asm = {}

local labels = {}
local lc = {}
local llabels = {}

local strucs = {}
local strucsz = {}

local bd = ""

local function BitNOT(n)
    local p,c=1,0
    for i = 0, 31 do
        local r=n%2
        if r<1 then c=c+p end
        n,p=(n-r)/2,p*2
    end
    return c
end

local function tc(n) -- two's complement
	n = tonumber(n)

	if n < 0 then
		n = BitNOT(math.abs(n))+1
	end

	return n
end

local function pass1(source) --turn into lines
	return lineate(source)
end

local function pass2(lines, file) --format and tokenize src code (remove tabs and comments)
	local out = {}
	for k,v in ipairs(lines) do
		if v ~= "" then
			local sc = v:sub(1,1)
			if (sc ~= ";") and (sc ~= "#") then
				local lout = ""
				while (v:sub(1,1) == "\t") or (v:sub(1,1) == " ") do
					v = v:sub(2)
				end
				if v:sub(1,3) ~= ".ds" then
					while (v:sub(-1,-1) == "\t") or (v:sub(-1,-1) == " ") do
						v = v:sub(1,-2)
					end
				end
				local tokens = tokenize(v)
				if tokens[1] ~= ".ds" then
					for k2,v2 in ipairs(tokens) do
						if v2:sub(-1,-1) == "," then
							v2 = v2:sub(1,-2)
						end

						if v2:sub(1,1) == ";" then
							break
						else
							if k2 == 1 then
								lout = v2
							else
								lout = lout.." "..v2
							end
						end
					end
				else
					lout = v
				end
				if lout ~= "" then
					out[#out+1] = {["lit"] = lout, ["loc"] = k, ["file"] = file}
				end
			end
		end
	end
	return out
end

local function passi(tokens) --include files
	local out = {}
	for k,ln in ipairs(tokens) do
		local line = ln.lit
		local tt = tokenize(line)
		if tt[1] == ".include" then
			local inc = passi(pass2(pass1(io.open(bd..tt[2], "r"):read("*a"))), bd)
			for k2,line2 in ipairs(inc) do
				line2.file = tt[2]
				out[#out+1] = line2
			end
		else
			out[#out+1] = ln
		end
	end
	return out
end

local function pass3(tokens) --register labels
	local out = {}
	local bc = 0 --byte count
	local istr = false
	local strc = 0
	local clabel = ""
	for k,ln in ipairs(tokens) do
		local line = ln.lit
		local tt = tokenize(line)
		if istr then
			if line == "end-struct" then
				strucsz[istr] = strc
				labels[istr.."_sizeof"] = strc
				istr = false
				strc = 0
			else
				labels[istr.."_"..tt[1]] = strc
				strucs[istr][tt[1]] = strc
				strc = strc + tonumber(tt[2])
			end
		else
			if tt[1]:sub(-1,-1) == ":" then
				if tt[1]:sub(1,1) == "." then -- local label
					local t = llabels[clabel]

					t[tt[1]:sub(2,-2)] = bc
				else
					if not labels[tt[1]:sub(1,-2)] then
						clabel = tt[1]:sub(1,-2)
						labels[tt[1]:sub(1,-2)] = bc
						llabels[tt[1]:sub(1,-2)] = {}
						lc[tt[1]:sub(1,-2)] = true
						out[#out+1] = ln
					else
						error("attempt to define label "..tt[1]:sub(1,-2).." twice.")
					end
				end
			elseif tt[2] == "===" then
				if tt[3] then
					if not labels[tt[1]] then
						if tt[3]:sub(1,1) == "#" then
							labels[tt[1]] = io.open(bd..tt[3]:sub(2), "r"):read("*a")
						else
							labels[tt[1]] = tt[3]
						end
					else
						error("attempt to define constant "..tt[1].." twice.")
					end
				else
					error("Error: Unfinished constant definition")
				end
			elseif tt[1] == ".struct" then
				strucs[tt[2]] = {}
				istr = tt[2]
			elseif tt[1] == ".static" then
				print(bd..tt[2])
				bc = bc + #io.open(bd..tt[2], "r"):read("*a")
				out[#out+1] = ln
			elseif tt[1] == ".db" then
				bc = bc + (#tt - 1)
				out[#out+1] = ln
			elseif tt[1] == ".di" then
				bc = bc + ((#tt - 1) * 2)
				out[#out+1] = ln
			elseif tt[1] == ".dl" then
				bc = bc + ((#tt - 1) * 4)
				out[#out+1] = ln
			elseif tt[1] == ".ds" then
				bc = bc + #line:sub(5)
				out[#out+1] = ln
			elseif tt[1] == ".ds$" then
				bc = bc + #tostring(labels[tt[2]])
				out[#out+1] = ln
			elseif tt[1] == ".bytes" then
				if tonumber(tt[2]) then
					bc = bc + tonumber(tt[2])
					out[#out+1] = ln
				else
					error("Error: Invalid number at bytes")
				end
			elseif tt[1] == ".fill" then
				if tonumber(tt[2]) then
					bc = tonumber(tt[2])
					out[#out+1] = ln
				else
					error("Error: Invalid number at fill")
				end
			elseif tt[1] == ".org" then
				if tt[2] then
					if tonumber(tt[2]) then
						bc = tonumber(tt[2])
					else
						error("Error: Invalid number at org")
					end
				else
					error("Error: Unfinished org")
				end
			elseif tt[1] == ".bc" then
				if tt[2] == "@" then
					ln.lit = ".bc "..tostring(bc)
				end
				out[#out+1] = ln
			else
				local e = inst[tt[1]]

				if e then
					bc = bc + e[1]
				else
					error("Error: Not an instruction "..tt[1])
				end
				out[#out+1] = ln
			end
		end
	end
	return out
end

local function pass4(tokens) --decode labels, registers, and also strings
	local out = {}

	local clabel = ""

	for k,ln in ipairs(tokens) do
		ln.sym = ""
		local line = ln.lit
		local tt = tokenize(line)
		local lout = ""

		if tt[1]:sub(-1,-1) == ":" then
			clabel = tt[1]:sub(1,-2)
		else
			for k,v in ipairs(tt) do
				if k == 1 then
					lout = v
				else
					if tt[1] == ".ds" then
						lout = line
					elseif tt[1] == ".ds$" then
						lout = ".ds "..tostring(labels[tt[2]])
					else
						if v:sub(1,1) == '"' then
							if #v == 3 then
								if v:sub(-1,-1) == '"' then
									lout = lout.." "..string.byte(v:sub(2,2))
								else
									error("Error: Unfinished char")
								end
							else
								error("Error: Cannot use a multi-byte char")
							end
						else
							if tonumber(v) then
								lout = lout.." "..v
							else
								if v:sub(1,1) == "." then -- local label
									if llabels[clabel][v:sub(2)] then
										lout = lout.." "..tostring(llabels[clabel][v:sub(2)])
									else
										error("Error: Not a local label "..v:sub(2))
									end
								elseif regs[v] then
									lout = lout.." "..tostring(regs[v])
								elseif labels[v] then
									lout = lout.." "..labels[v]
									if lc[v] then
										ln.sym = labels[v]
									end
								else
									lout = lout.." "..v
									print("warning: unclear what "..v.." is")
								end
							end
						end
					end
				end
			end
			ln.lit = lout
			out[#out+1] = ln
		end
	end
	return out
end

local function pass5(lines, sym) --generate binary
	local out = ""
	local bc = 0
	local s = {}
	for k,ln in ipairs(lines) do
		local line = ln.lit
		local tt = tokenize(line)
		if tt[1] == ".static" then
			local f = io.open(bd..tt[2], "r"):read("*a")
			out = out..f
			bc = bc + #f
		elseif tt[1] == ".db" then
			for i = 2, #tt do
				local v = tt[i]
				if v:sub(1,1) == '"' and v:sub(-1,-1) == '"' and #v == 3 then
					out = out..v:sub(2,2)
					bc = bc + 1
				else
					if tonumber(v) then
						out = out..string.char(tc(v))
						bc = bc + 1
					else
						error("Error: Invalid bytelist!")
					end
				end
			end
		elseif tt[1] == ".di" then
			for i = 2, #tt do
				local v = tt[i]
				if tonumber(v) then
					local u1, u2 = splitInt16(tc(v))

					out = out..string.char(u2)..string.char(u1)
					bc = bc + 2
				else
					error("Error: Invalid intlist!")
				end
			end
		elseif tt[1] == ".dl" then
			for i = 2, #tt do
				local v = tt[i]
				if tonumber(v) then
					local u1, u2, u3, u4 = splitInt32(tc(v))

					out = out..string.char(u4)..string.char(u3)..string.char(u2)..string.char(u1)
					bc = bc + 4
				else
					error("Error: Invalid longlist!")
				end
			end
		elseif tt[1] == ".ds" then
			local contents = line:sub(5)
			out = out..contents
			bc = bc + #contents
		elseif tt[1] == ".bytes" then
			for i = 1, tonumber(tt[2]) do
				out = out..string.char(tonumber(tt[3]))
				bc = bc + 1
			end
		elseif tt[1] == ".fill" then
			if bc > tonumber(tt[2]) then
				error("Fill tried to go to "..tt[2]..", bc already at "..string.format("%x",bc))
			elseif bc == tonumber(tt[2]) then

			else
				repeat
					out = out..string.char(tt[3])
					bc = bc + 1
				until bc == tonumber(tt[2])
			end
		elseif tt[1] == ".bc" then
			if #tt == 1 then
				print("bytecount: "..string.format("%x",bc))
			elseif #tt == 2 then
				print("bytecount: "..string.format("%x",tt[2]))
			end
		else
			local e = inst[tt[1]]

			if not e then
				error("what the fuck? "..tt[1])
			end

			out = out..string.char(e[2])

			local rands = e[3] -- the names 'rand, operand

			if #tt-1 ~= #rands then
				error("Operand count mismatch on a "..tt[1])
			end

			for k,v in ipairs(rands) do
				if v == 1 then

					out = out..string.char(tc(tt[k+1]))
				elseif v == 2 then
					local u1, u2 = splitInt16(tc(tt[k+1]))

					out = out..string.char(u2)..string.char(u1)
				elseif v == 4 then
					local u1, u2, u3, u4 = splitInt32(tc(tt[k+1]))

					out = out..string.char(u4)..string.char(u3)..string.char(u2)..string.char(u1)
				end
			end

			bc = bc + e[1]
		end
	end
	if sym == true then
		return {out, s}
	else
		return out
	end
end

function asm.as(source, sym, p)
	labels = {}
	lc = {}
	strucs = {}
	strucs2 = {}
	llabels = {}

	labels["__DATE"] = os.date()

	local sp = getdirectory(p)

	bd = sp

	if sym == true then
		return pass5(pass4(pass3(passi(pass2(pass1(source)), "root"))), true), labels
	else
		return pass5(pass4(pass3(passi(pass2(pass1(source))))))
	end
end

return asm