local DataStorage=require("datastorage")
local json=require("json")
local lfs=require("libs/libkoreader-lfs")
local util=require("util")
local M={}
local root=DataStorage:getDataDir().."/cache/hardcoverdashboard"
local function ensure() if lfs.attributes(root,"mode")~="directory" then util.makePath(root) end end
local function path(kind,key) return root.."/"..kind.."_"..tostring(key or "default"):gsub("[^%w_-]","_")..".json" end
function M.read(kind,key)
    local f=io.open(path(kind,key),"rb")
    if not f then return nil end
    local raw=f:read("*a"); f:close()
    local ok,v=pcall(json.decode,raw)
    return ok and type(v)=="table" and v or nil
end
function M.write(kind,key,value)
    ensure()
    local raw=json.encode(value)
    local temp=path(kind,key)..".tmp"
    local f=io.open(temp,"wb")
    if not f then return false end
    f:write(raw); f:close()
    local ok=os.rename(temp,path(kind,key))
    return ok and true or false
end
function M.clear()
    if lfs.attributes(root,"mode")~="directory" then return end
    for name in lfs.dir(root) do if name~="." and name~=".." then os.remove(root.."/"..name) end end
end
return M
