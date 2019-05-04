function reverse(l)
  local m = {}
  for i = #l, 1, -1 do table.insert(m, l[i]) end
  return m
end

function TableConcat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

function readBinFile(file)
	local out = {}
	local f = love.filesystem.read(file)
	for b in f:gmatch(".") do
		out[#out+1] = string.byte(b)
	end
	return out
end

function toInt32(byte1, byte2, byte3, byte4)
	return (byte1*0x1000000) + (byte2*0x10000) + (byte3*0x100) + byte4
end

function toInt16(byte1, byte2)
	return (byte1*0x100) + byte2
end

function splitInt32(n) 
	return (math.modf(n/16777216))%256, (math.modf(n/65536))%256, (math.modf(n/256))%256, n%256
end

function splitInt16(n)
	return (math.modf(n/256))%256, n%256
end

function trim(s)
  return s:match("^%s*(.-)%s*$")
end

function struct(stuff)
    local s = {}
    s.o = {}
    s.sz = {}
    local offset = 0
    for k,v in ipairs(stuff) do
        local size = v[1]
        local name = v[2]
        s.o[name] = offset
        s.sz[name] = size
        offset = offset + size
    end
    function s.size()
        return offset
    end
    return s
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

function tokenize(str)
	return explode(" ",str)
end

function lineate(str)
	return explode("\n",str)
end