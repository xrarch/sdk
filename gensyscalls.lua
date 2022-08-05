local function printhelp()
	print("== gensyscalls.lua ==")
	print("generates syscall stubs and trampolines for MINTIA from a header file.")
	print("usage: gensyscalls.lua [sysheader] [stubs] [trampolines]")
end

-- the stubs are for OSDLL.dll to be able to call into the kernel.

-- the trampolines are for the kernel to get the arguments set up properly.
-- they assume the kernel exception handler placed the trapframe in s17.

-- supports up to 27 arguments and return values.

local FIRSTREG   = 2
local FIRSTSAVED = 11
local LASTREG    = 27
local ARGCOUNT   = 4
local FIRSTARG   = 7

local regnames = {
	"t0", "t1", "t2", "t3", "t4", "t5",
	"a0", "a1", "a2", "a3",
	"s0", "s1",
	"s2", "s3",
	"s4", "s5",
	"s6", "s7",
	"s8", "s9",
	"s10", "s11",
	"s12", "s13",
	"s14", "s15",
	"s16",
}

if (#arg < 3) then
	print("argument mismatch")
	printhelp()
	return
end

local sysheader = io.open(arg[1], "r")

if not sysheader then
	print("failed to open "..arg[1])
	return
end

local stubs

if arg[2] ~= "NO" then
	stubs = io.open(arg[2], "w")

	if not stubs then
		print("failed to open "..arg[2])
		return
	end
end

local trampolines

if arg[3] ~= "NO" then
	trampolines = io.open(arg[3], "w")

	if not trampolines then
		print("failed to open "..arg[3])
		return
	end
end

local function explode(d,p)
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

local syscalls = {}

local line = sysheader:read("*l")

local sysnumber = 1

while line do
	if line:sub(1,7) == "extern " then
		local syscall = {}

		local linecomp = explode(" ", line)

		syscall.name = linecomp[2]
		syscall.args = {}
		syscall.rets = {}
		syscall.n = sysnumber

		sysnumber = sysnumber + 1

		local i = 4
		local n = 0

		while true do
			if not linecomp[i] then
				error("bad sysheader")
			end

			if linecomp[i] == "--" then
				break
			end

			local sysarg = {}

			sysarg.name = linecomp[i]
			sysarg.n = n

			syscall.args[#syscall.args + 1] = sysarg

			i = i + 1
			n = n + 1
		end

		i = i + 1
		n = 0

		while true do
			if not linecomp[i] then
				error("bad sysheader")
			end

			if linecomp[i] == "}" then
				break
			end

			local sysret = {}

			sysret.name = linecomp[i]
			sysret.n = n

			syscall.rets[#syscall.rets + 1] = sysret

			i = i + 1
		end

		syscalls[#syscalls + 1] = syscall
	end

	line = sysheader:read("*l")
end

if stubs then
	stubs:write("; AUTOMATICALLY GENERATED -- DO NOT EDIT\n\n")
	stubs:write(".section text\n\n")
end

if trampolines then
	trampolines:write("; AUTOMATICALLY GENERATED -- DO NOT EDIT\n\n")
	trampolines:write(".section PAGE$text\n\n")
end

if stubs then
	-- generate stubs

	for i = 1, #syscalls do
		local sys = syscalls[i]

		stubs:write(string.format("%s:\n.global %s\n", sys.name, sys.name))

		local savedneeded = math.max(#sys.args, #sys.rets) - FIRSTSAVED + FIRSTREG

		local stackoffset = 4

		if savedneeded > 0 then
			stackoffset = stackoffset + savedneeded*4 + 4

			stubs:write(string.format("\tsubi sp, sp, %d\n", savedneeded*4 + 4))
			stubs:write(string.format("\tmov  long [sp], lr\n"))

			for reg = 0, savedneeded-1 do
				stubs:write(string.format("\tmov  long [sp + %d], %s\n", reg*4 + 4, regnames[reg + FIRSTSAVED]))
			end

			stubs:write("\n")
		end

		local saveoffset = stackoffset
		local regnum = FIRSTREG

		for argn = #sys.args, 1, -1 do
			local sysarg = sys.args[argn]

			if regnum < ARGCOUNT+FIRSTREG then
				stubs:write(string.format("\tmov  %s, %s\n", regnames[regnum], regnames[regnum+FIRSTARG-FIRSTREG]))
			else
				stubs:write(string.format("\tmov  %s, long [sp + %d]\n", regnames[regnum], saveoffset))
				saveoffset = saveoffset + 4
			end

			regnum = regnum + 1
		end

		stubs:write(string.format("\n\tli   t0, %d\n", sys.n))
		stubs:write("\tsys  0\n\n")

		regnum = FIRSTREG + #sys.rets - 1

		saveoffset = stackoffset + (#sys.rets - ARGCOUNT - 1)*4

		for retn = #sys.rets, 1, -1 do
			local sysret = sys.rets[retn]

			if regnum < ARGCOUNT+FIRSTREG then
				stubs:write(string.format("\tmov  %s, %s\n", regnames[regnum+FIRSTARG-FIRSTREG], regnames[regnum]))
			else
				stubs:write(string.format("\tmov  long [sp + %d], %s\n", saveoffset, regnames[regnum]))
				saveoffset = saveoffset - 4
			end

			regnum = regnum - 1
		end

		stubs:write("\n")

		if savedneeded > 0 then
			for reg = 0, savedneeded-1 do
				stubs:write(string.format("\tmov  %s, long [sp + %d]\n", regnames[reg + FIRSTSAVED], reg*4 + 4))
			end

			stubs:write(string.format("\taddi sp, sp, %d\n", savedneeded*4 + 4))
		end

		stubs:write("\tret\n\n")
	end
end

if trampolines then
	-- generate trampoline externs

	for i = 1, #syscalls do
		local sys = syscalls[i]

		trampolines:write(string.format(".extern %s\n", sys.name))
	end

	-- generate trampoline table


	trampolines:write(string.format("\nOSCallCount:\n.global OSCallCount\n\t.dl %d\n", #syscalls))

	trampolines:write("\nOSCallTable:\n.global OSCallTable\n")

	trampolines:write(string.format("\t.dl %-48s ;0\n", "0"))

	for i = 1, #syscalls do
		local sys = syscalls[i]

		trampolines:write(string.format("\t.dl %-48s ;%d\n", "OST"..sys.name, sys.n))
	end

	trampolines:write("\n\n")

	-- generate trampolines

	for i = 1, #syscalls do
		local sys = syscalls[i]

		trampolines:write(string.format("OST%s:\n.global OST%s\n", sys.name, sys.name))

		local tfoffset = (FIRSTREG-1)*4

		-- move all the arguments from the trapframe to their proper ABI register
		-- or the stack

		local stackneeded = math.max((math.max(#sys.args, #sys.rets) - ARGCOUNT)*4, 0)

		trampolines:write(string.format("\tsubi sp, sp, %d\n", stackneeded + 4))
		trampolines:write(string.format("\tmov  long [sp], lr\n"))

		local stackoffset = 4

		local saveoffset = 4
		local regnum = FIRSTREG

		for argn = #sys.args, 1, -1 do
			local sysarg = sys.args[argn]

			if regnum < ARGCOUNT+FIRSTREG then
				trampolines:write(string.format("\tmov  %s, long [s17 + %d] ;%s\n", regnames[regnum+FIRSTARG-FIRSTREG], tfoffset, regnames[tfoffset/4+1]))
			else
				trampolines:write(string.format("\n\tmov  t0, long [s17 + %d] ;%s\n", tfoffset, regnames[tfoffset/4+1]))
				trampolines:write(string.format("\tmov  long [sp + %d], t0\n", saveoffset))
				saveoffset = saveoffset + 4
			end

			tfoffset = tfoffset + 4
			regnum = regnum + 1
		end

		trampolines:write(string.format("\n\tjal  %s\n\n", sys.name))

		regnum = FIRSTREG

		saveoffset = stackoffset
		tfoffset = (FIRSTREG-1)*4

		for retn = 1, #sys.rets do
			local sysret = sys.rets[retn]

			if regnum < ARGCOUNT+FIRSTREG then
				trampolines:write(string.format("\tmov  long [s17 + %d], %s ;%s\n", tfoffset, regnames[regnum+FIRSTARG-FIRSTREG], regnames[tfoffset/4+1]))
			else
				trampolines:write(string.format("\n\tmov  t0, long [sp + %d]\n", saveoffset))
				trampolines:write(string.format("\tmov  long [s17 + %d], t0 ;%s\n", tfoffset, regnames[tfoffset/4+1]))
				saveoffset = saveoffset + 4
			end

			tfoffset = tfoffset + 4
			regnum = regnum + 1
		end

		trampolines:write("\n")

		trampolines:write(string.format("\tmov  lr, long [sp]\n"))
		trampolines:write(string.format("\taddi sp, sp, %d\n", stackneeded + 4))
		trampolines:write("\tret\n\n")
	end
end