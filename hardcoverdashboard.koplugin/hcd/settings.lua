local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local C = require("hcd.constants")
local M={}
local path=DataStorage:getSettingsDir().."/hardcoverdashboard.lua"
local db
local function open() if not db then db=LuaSettings:open(path) end; return db end
function M.get(k) return open():readSetting(k,C.DEFAULTS[k]) end
function M.set(k,v) open():saveSetting(k,v); open():flush() end
function M.normalize_token(s)
    if type(s)~="string" then return nil end
    s=s:gsub("^%s*Bearer%s+",""):gsub("^%s+",""):gsub("%s+$","")
    return s~="" and s or nil
end
function M.token() return M.normalize_token(M.get("token")) end
function M.import_token()
    local config_paths={DataStorage:getDataDir().."/plugins/hardcoverapp.koplugin/hardcover_config.lua"}
    for _,file in ipairs(config_paths) do
        local f=io.open(file,"r")
        if f then
            f:close()
            local ok,cfg=pcall(dofile,file)
            if ok and type(cfg)=="table" then
                local value=M.normalize_token(cfg.token)
                if value then M.set("token",value); return true end
            end
        end
    end
    local candidates={DataStorage:getSettingsDir().."/hardcoversync_settings.lua",DataStorage:getSettingsDir().."/hardcoverapp.lua",DataStorage:getSettingsDir().."/hardcover.lua"}
    for _,file in ipairs(candidates) do
        local f=io.open(file,"r")
        if f then
            f:close()
            local ok,other=pcall(LuaSettings.open,LuaSettings,file)
            if ok and other then
                for _,key in ipairs({"api_token","token","hardcover_token","pat"}) do
                    local value=M.normalize_token(other:readSetting(key))
                    if value then M.set("token",value); return true end
                end
            end
        end
    end
    return false
end
return M
