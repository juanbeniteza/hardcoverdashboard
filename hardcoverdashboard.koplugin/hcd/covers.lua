local DataStorage=require("datastorage")
local lfs=require("libs/libkoreader-lfs")
local util=require("util")
local https=require("ssl.https")
local socketutil=require("socketutil")
local ltn12=require("ltn12")
local M={}
local root=DataStorage:getDataDir().."/cache/hardcoverdashboard_covers"
local function key(url)
    local h=5381
    for i=1,#url do h=(h*33+url:byte(i))%4294967296 end
    return string.format("%08x",h)
end
function M.path(url)
    if type(url)~="string" or not url:match("^https://") then return nil end
    local ext=url:match("%.(jpe?g|png|webp)") or "jpg"
    local path=root.."/"..key(url).."."..ext
    if lfs.attributes(path,"mode")=="file" then return path end
    return nil
end
function M.download(url)
    if not url or not url:match("^https://") then return nil end
    local existing=M.path(url)
    if existing then return existing end
    if lfs.attributes(root,"mode")~="directory" then util.makePath(root) end
    local ext=url:match("%.(jpe?g|png|webp)") or "jpg"
    local path=root.."/"..key(url).."."..ext
    local chunks={}
    socketutil:set_timeout(10,30)
    local ok,res,code=pcall(https.request,{url=url,method="GET",sink=ltn12.sink.table(chunks),headers={["User-Agent"]="hardcoverdashboard.koplugin/0.1.0"}})
    socketutil:reset_timeout()
    if not ok or not res or tonumber(code)~=200 then return nil end
    local body=table.concat(chunks)
    if #body<32 or #body>3000000 then return nil end
    local f=io.open(path..".tmp","wb")
    if not f then return nil end
    f:write(body); f:close(); os.rename(path..".tmp",path)
    return path
end
return M
