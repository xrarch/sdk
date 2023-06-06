local function getdirectory(p)
	for i = #p, 1, -1 do
		if p:sub(i,i) == "/" then
			return p:sub(1,i)
		end
	end

	return "./"
end

local includedalready

require("sb")

local preproc = {}

function preproc.pp(name, srcf, incdir, libdir, symbols, first)
	if first then
		includedalready = {}
	end

	local srctext = newsb()

	local comment = false
	local startofline = true
	local directive = false

	local linebuffer = ""
	local basedir = getdirectory(name)

	local c1 = false

	local instring = false
	local escape = false

	local ifdefstack = {true}

	local line = 1

	if first then
		for k,v in pairs(symbols) do
			if v then
				if tonumber(v) then
					srctext.append("const "..k.." : int = "..v.."\n")
				else
					srctext.append("const "..k.." : int = 1\n")
				end
			else
				srctext.append("const "..k.." : int = 0\n")
			end
		end
	end

	srctext.append(string.format("#%s %d\n", name, 1))

	while true do
		local c = srcf:read(1)

		if not c then
			if not startofline then
				-- so files that dont end with a newline are treated properly
				c = "\n"
			else
				return srctext.tostring()
			end
		end

		if c1 then
			if c == "/" then
				comment = true
			else
				srctext.append("/")
			end
		end

		c1 = false

		if c == "\n" then
			if directive then
				local dirtab = explode(" ", linebuffer)

				local dir = dirtab[1]

				if dir == "IFDEF" then
					if not ifdefstack[#ifdefstack] then
						ifdefstack[#ifdefstack+1] = false
					elseif symbols[dirtab[2]] then
						ifdefstack[#ifdefstack+1] = true
					else
						ifdefstack[#ifdefstack+1] = false
					end
				elseif dir == "IFNDEF" then
					if not ifdefstack[#ifdefstack] then
						ifdefstack[#ifdefstack+1] = false
					elseif symbols[dirtab[2]] then
						ifdefstack[#ifdefstack+1] = false
					else
						ifdefstack[#ifdefstack+1] = true
					end
				elseif dir == "ELSE" then
					if #ifdefstack == 1 then
						print(string.format("tbc: %s:%d: no matching ifdef", name, line))
						return false
					end

					if ifdefstack[#ifdefstack-1] then
						ifdefstack[#ifdefstack] = not ifdefstack[#ifdefstack]
					end
				elseif dir == "ENDIF" then
					if #ifdefstack == 1 then
						print(string.format("tbc: %s:%d: no matching ifdef", name, line))
						return false
					end

					ifdefstack[#ifdefstack] = nil
				elseif ifdefstack[#ifdefstack] then
					if dir == "INCLUDE" then
						local inc = dirtab[2]

						if (#inc > 2) and (inc:sub(1,1) == '"') and (inc:sub(-1,-1) == '"') then
							local incpath = inc:sub(2,-2)

							if not includedalready[incpath] then
								includedalready[incpath] = true

								local realpath

								local f

								if incpath:sub(1,5) == "<ll>/" then
									local rpath = incpath:sub(6)

									for _,path in ipairs(libdir) do
										realpath = path.."/"..rpath

										f = io.open(realpath)

										if f then break end
									end

									if not f then
										realpath = sd.."/../headers/"..rpath
										f = io.open(realpath, "r")
									end
								elseif incpath:sub(1,6) == "<inc>/" then
									local rpath = incpath:sub(7)

									for _,path in ipairs(incdir) do
										realpath = path.."/"..rpath

										f = io.open(realpath)

										if f then break end
									end
								else
									realpath = basedir..incpath

									f = io.open(realpath)
								end

								if not f then
									print(string.format("tbc: %s:%d: failed to open '%s'", name, line, incpath))
									return
								end

								local npp = preproc.pp(realpath, f, incdir, libdir, symbols, false)

								if not npp then return false end

								srctext.append(npp)

								srctext.append(string.format("#%s %d\n", name, line))
							end
						else
							print(string.format("tbc: %s:%d: malformed include", name, line))
							return
						end
					elseif dir == "DEFINE" then
						if dirtab[2] then
							if dirtab[3] then
								if dirtab[3] ~= "0" then
									symbols[dirtab[2]] = dirtab[3]
								else
									symbols[dirtab[2]] = false
								end
							else
								symbols[dirtab[2]] = true
							end

							if symbols[dirtab[2]] then
								srctext.append("const "..dirtab[2].." : int = 1")
							else
								srctext.append("const "..dirtab[2].." : int = 0")
							end
						end
					elseif dir == "UNDEF" then
						symbols[dirtab[2]] = nil
					else
						print(string.format("tbc: %s:%d: unknown directive '%s'", name, line, dir))
						return
					end
				end
			end

			line = line + 1

			srctext.append("\n")

			startofline = true
			comment = false
			directive = false
			escape = false

			linebuffer = ""
		elseif not comment then
			if directive then
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
					else
						if (not escape) and (c == "\\") then
							escape = true
						else
							escape = false
						end

						srctext.append(c)
					end
				end

				startofline = false
			end
		end
	end

	return srctext.tostring()
end

return preproc