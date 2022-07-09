-- preproc.lua [source] [dest]
-- tested under luaJIT 5.1

local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end
local sd = getdirectory(arg[0])

local function printhelp()
	print("== preproc.lua ==")
	print("preprocessor for LIMNstation cross-toolchain")
end

function explode(d,p)
    local t, ll
    t={}
    ll=0
    if(#p == 1) then return {p} end
        while true do
            l=string.find(p,d,ll,true) -- find the next d in the string
            if l~=nil then -- if "not not" found then..
                table.insert(t, string.sub(p,ll,l-1)) -- Save it in our array.
                ll=l+1 -- save just after where we found it for searching next time.
            else
                table.insert(t, string.sub(p,ll)) -- Save what's left in our array.
                break -- Break at end, as it should be, according to the lua manual.
            end
        end
    return t
end

local incdir = {}
local narg = {}

for k,v in ipairs(arg) do
	if v:sub(1,7) == "incdir=" then
		local incs = v:sub(8)

		incdir = explode(":", incs)
	else
		narg[#narg + 1] = v
	end
end

arg = narg

if #arg < 2 then
	print("dragonc_pp: argument mismatch")
	printhelp()
	os.exit(1)
end

local symbols = {}

local source = arg[1]
local dest = arg[2]

local srcf = io.open(source, "r")

if not srcf then
	print(string.format("dragonc_pp: error opening source file %s", source))
	os.exit(1)
end

local destf = io.open(dest, "w")

if not destf then
	print(string.format("dragonc_pp: error opening destination file %s", dest))
	os.exit(1)
end

function preproc(name, srcf, destf)
	local multilinecomment = false
	local comment = false
	local startofline = true
	local directive = false

	local linebuffer = ""
	local basedir = getdirectory(name)

	local mlcterm1 = false
	local c1 = false
	local mlc1 = false

	local instring = false
	local escape = false

	local ifdefstack = {true}

	local line = 1

	destf:write(string.format("#%s %d\n", name, 1))

	while true do
		local c = srcf:read(1)

		if not c then
			if not startofline then
				-- so files that dont end with a newline are treated properly
				c = "\n"
			else
				return true
			end
		end

		if c1 then
			if c == "/" then
				comment = true
			else
				destf:write("/")
			end
		elseif mlc1 then
			if c == "*" then
				multilinecomment = true
			else
				destf:write("(")
			end
		end

		mlc1 = false
		c1 = false

		if c == "\n" then
			line = line + 1
			destf:write("\n")

			if directive then
				local dirtab = explode(" ", linebuffer)

				local dir = dirtab[1]

				if dir == "include" then
					local inc = dirtab[2]

					if (#inc > 2) and (inc:sub(1,1) == '"') and (inc:sub(-1,-1) == '"') then
						local incpath = inc:sub(2,-2)

						local f

						if incpath:sub(1,5) == "<df>/" then
							f = io.open(sd.."/../headers/dfrt/"..incpath:sub(6), "r")
						elseif incpath:sub(1,5) == "<ll>/" then
							f = io.open(sd.."/../headers/"..incpath:sub(6), "r")
						elseif incpath:sub(1,6) == "<inc>/" then
							local rpath = incpath:sub(7)

							for _,path in ipairs(incdir) do
								f = io.open(path.."/"..rpath)

								if f then break end
							end
						else
							f = io.open(basedir.."/"..incpath)
						end

						if not f then
							print(string.format("dragonc_pp: %s:%d: failed to open '%s'", name, line, incpath))
							return
						end

						if not preproc(incpath, f, destf) then return false end

						destf:write(string.format("#%s %d\n", name, line))
					else
						print(string.format("dragonc_pp: %s:%d: malformed include", name, line))
						return
					end
				elseif dir == "define" then
					if dirtab[2] then
						if dirtab[3] then
							symbols[dirtab[2]] = dirtab[3]
						else
							symbols[dirtab[2]] = true
						end
					end
				elseif dir == "undef" then
					symbols[dirtab[2]] = nil
				elseif dir == "ifdef" then
					if symbols[dirtab[2]] then
						ifdefstack[#ifdefstack+1] = true
					else
						ifdefstack[#ifdefstack+1] = false
					end
				elseif dir == "ifndef" then
					if symbols[dirtab[2]] then
						ifdefstack[#ifdefstack+1] = false
					else
						ifdefstack[#ifdefstack+1] = true
					end
				elseif dir == "else" then
					if #ifdefstack == 1 then
						print(string.format("dragonc_pp: %s:%d: no matching ifdef", name, line))
					end

					ifdefstack[#ifdefstack] = not ifdefstack[#ifdefstack]
				elseif dir == "endif" then
					if #ifdefstack == 1 then
						print(string.format("dragonc_pp: %s:%d: no matching ifdef", name, line))
					end

					ifdefstack[#ifdefstack] = nil
				else
					print(string.format("dragonc_pp: %s:%d: unknown directive '%s'", name, line, dir))
					return
				end
			end

			startofline = true
			comment = false
			mlcterm1 = false
			directive = false
			escape = false

			linebuffer = ""
		elseif not comment then
			if multilinecomment then
				if c == "*" then
					mlcterm1 = true
				elseif c == ")" then
					if mlcterm1 then
						multilinecomment = false
					end
				else
					mlcterm1 = false
				end
			elseif directive then
				linebuffer = linebuffer .. c
			else
				if (not instring) and ((c == "#") and startofline) then
					directive = true
				elseif ifdefstack[#ifdefstack] then
					if (not escape) and (c == '"') then
						instring = not instring
					end

					if (not escape) and (not instring) and (c == "/") then
						c1 = true
					elseif (not escape) and (not instring) and (c == "(") then
						mlc1 = true
					else
						if (not escape) and (c == "\\") then
							escape = true
						else
							escape = false
						end

						destf:write(c)
					end
				end

				startofline = false
			end
		end
	end
end

if not preproc(source, srcf, destf) then
	os.exit(1)
end