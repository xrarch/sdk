lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol = bit.lshift, bit.rshift, bit.tohex, bit.arshift, bit.band, bit.bxor, bit.bor, bit.bnot, bit.ror, bit.rol

function bnor(a,b)
    return bnot(bor(a,b))
end

function bnand(a,b)
    return bnot(band(a,b))
end

function toInt32(byte4, byte3, byte2, byte1)
    return lshift(byte1, 24) + lshift(byte2, 16) + lshift(byte3, 8) + byte4
end

function toInt16(byte2, byte1)
    return lshift(byte1, 8) + byte2
end

function splitInt32(n) 
    return band(rshift(n, 24), 0xFF), band(rshift(n, 16), 0xFF), band(rshift(n, 8), 0xFF), band(n, 0xFF)
end

function splitInt16(n)
    return band(rshift(n, 8), 0xFF), band(n, 0xFF)
end

function splitInt24(n) 
    return band(rshift(n, 16), 0xFF), band(rshift(n, 8), 0xFF), band(n, 0xFF)
end

function strtok(str, del, off)
    off = off or 1

    if off > #str then
        return nil
    end

    while str:sub(off,off) == del do
        off = off + 1
    end

    local nstr = ""

    while str:sub(off,off) ~= del do
        if off > #str then
            break
        end

        nstr = nstr .. str:sub(off,off)

        off = off + 1
    end

    return nstr, off
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

function tods(dat)
    if type(dat) == "string" then return dat end
    local out = ""
    for k,v in pairs(dat) do
        out = out..string.char(v)
    end
    return out
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

function cast(struct, tab, offset)
    local s = {}

    s.s = struct
    s.t = tab
    s.o = offset or 0

    function s.ss(n, str)
        for i = 0, s.s.sz[n]-1 do
            if str:sub(i+1,i+1) then
                s.t[s.s.o[n] + i + s.o] = str:sub(i+1,i+1):byte()
            else
                s.t[s.s.o[n] + i + s.o] = 0
            end
        end
    end

    function s.sv(n, val)
        local sz = s.s.sz[n]

        local t = s.t
        local o = s.s.o
        local off = s.o

        for i = 0, sz-1 do
            t[o[n] + i + off] = val % 256
            val = math.floor(val/256)
        end
    end

    function s.st(n, tab, ux)
        ux = ux or 1
        if ux == 1 then
            for i = 0, #tab do
                s.t[s.s.o[n] + s.o + i] = tab[i]
            end
        elseif ux == 4 then
            for i = 0, #tab do
                local b = i*4
                local b1,b2,b3,b4 = splitInt32(tab[i] or 0)
                s.t[s.s.o[n] + s.o + b] = b4
                s.t[s.s.o[n] + s.o + b + 1] = b3
                s.t[s.s.o[n] + s.o + b + 2] = b2
                s.t[s.s.o[n] + s.o + b + 3] = b1
            end
        else
            error("no support for vals size "..tostring(ux))
        end
    end

    function s.gs(n)
        local str = ""
        for i = 0, s.s.sz[n]-1 do
            local ch = s.t[s.s.o[n] + i + s.o] or 0
            if ch == 0 then break end
            str = str .. string.char(ch)
        end
        return str
    end

    function s.gv(n)
        local v = 0
        for i = s.s.sz[n]-1, 0, -1 do
            v = v*0x100 + (s.t[s.s.o[n] + i + s.o] or 0)
        end
        return v
    end

    function s.gc()
        return s.t
    end

    function s.gt(n, ux)
        local t = {}
        ux = ux or 1
        if ux == 1 then
            for i = s.s.sz[n]-1, 0, -1 do
                t[i] = (s.t[s.s.o[n] + i + s.o] or 0)
            end
        else
            for i = 0, (s.s.sz[n]/ux)-1 do
                local v = 0
                for j = ux-1, 0, -1 do
                    v = (v * 0x100) + (s.t[s.s.o[n] + (i*4) + j + s.o] or 0)
                end
                t[i] = v
            end
        end
        return t
    end

    return s
end