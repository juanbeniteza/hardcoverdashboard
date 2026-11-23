local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local InputDialog = require("ui/widget/inputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")

local Settings = require("hcd.settings")
local Cache = require("hcd.cache")
local API = require("hcd.api")
local Data = require("hcd.data")
local Date = require("hcd.date_util")
local C = require("hcd.constants")
local Covers = require("hcd.covers")
local Dashboard = require("hcd.ui.dashboard")

local Plugin = WidgetContainer:extend{
    name = "hardcoverdashboard",
    is_doc_only = false,
}

local function notice(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function Plugin:init()
    Dispatcher:registerAction("hardcover_dashboard_open", {
        category = "none",
        event = "ShowHardcoverDashboard",
        title = "Hardcover Dashboard",
        general = true,
    })
    self.ui.menu:registerToMainMenu(self)
end

function Plugin:addToMainMenu(menu_items)
    menu_items.hardcover_dashboard = {
        text = "Hardcover Dashboard",
        sorting_hint = "tools",
        callback = function() self:onShowHardcoverDashboard() end,
    }
end

function Plugin:onShowHardcoverDashboard()
    local token = Settings.token()
    if not token then
        self:token_dialog()
        return true
    end
    local today = Date.today()
    local y, m = Date.parse(today)
    local key = string.format("%04d-%02d", y, m)
    local cached_profile = Cache.read("profile")
    local cached_month = Cache.read("month", key)
    local model = {
        profile = cached_profile,
        reading = Cache.read("reading") or {},
        goals = Cache.read("goals") or {},
        month = cached_month or { days = {}, active_days = 0, total_pages = 0, book_count = 0 },
        streak = 0,
        best_streak = 0,
        offline = true,
    }
    local streak = Cache.read("streak")
    if streak then
        model.streak = streak.current or 0
        model.best_streak = streak.best or 0
    end
    local view = Dashboard:new{
        plugin = self,
        model = model,
        settings = {
            week_start = Settings.get("week_start"),
            show_covers = Settings.get("show_covers"),
        },
    }
    UIManager:show(view)
    -- Force sync if we don't have cached data yet; otherwise refresh if stale
    self:refresh(view, (cached_profile == nil or cached_month == nil))
    return true
end

function Plugin:load_month(y, m, view)
    local key = string.format("%04d-%02d", y, m)
    local cached = Cache.read("month", key)
    if cached then
        view.model.month = cached
        view.model.offline = true
    else
        view.model.month = { days = {}, active_days = 0, total_pages = 0, book_count = 0 }
        self:refresh(view, true)
    end
end

function Plugin:refresh(view, force)
    local token = Settings.token()
    if not token then
        self:token_dialog()
        return
    end
    local y, m = view.year, view.month
    local key = string.format("%04d-%02d", y, m)
    local old = Cache.read("timestamp", key)
    if not force and old and os.time() - (old.at or 0) < C.CACHE_TTL then
        return
    end

    NetworkMgr:runWhenOnline(function()
        Trapper:wrap(function()
            local completed, result = Trapper:dismissableRunInSubprocess(function()
                local profile, err = API.profile(token)
                if not profile then return { error = err or "Could not fetch Hardcover profile." } end

                local goals, gerr = API.goals(token, profile.id)
                local reading, rerr = API.reading(token, profile.id)
                local first = string.format("%04d-%02d-01", y, m)
                local ny, nm = Date.month_shift(y, m, 1)
                local nextfirst = string.format("%04d-%02d-01", ny, nm)
                local start_at = Date.add_days(first, -45) .. "T00:00:00Z"
                local journals, jerr = API.journals(token, profile.id, start_at, nextfirst .. "T00:00:00Z")
                local reads, readerr = API.month_reads(token, profile.id, first)
                local streak_days, serr = API.streak_days(token, profile.id)

                if not goals or not reading or not journals or not reads or not streak_days then
                    return { error = gerr or rerr or jerr or readerr or serr or "Failed to load Hardcover data." }
                end

                local month = Data.activity(journals, reads, first, Date.add_days(nextfirst, -1))
                local reading_cards = Data.reading(reading)

                if Settings.get("show_covers") then
                    local urls = {}
                    for _, b in ipairs(reading_cards) do
                        if b.cover then urls[b.cover] = true end
                    end
                    for _, day in pairs(month.days) do
                        for _, b in ipairs(day.books) do
                            if b.cover then urls[b.cover] = true end
                        end
                    end
                    local fetched = 0
                    for url in pairs(urls) do
                        Covers.download(url)
                        fetched = fetched + 1
                        if fetched >= 24 then break end
                    end
                end

                for day, entry in pairs(month.days) do
                    if type(day) == "string" then
                        streak_days[day] = entry
                    end
                end
                local current, best = Data.streak(streak_days, Date.today())

                return {
                    profile = profile,
                    goals = Data.goals(goals, tonumber(Date.today():sub(1, 4))),
                    reading = reading_cards,
                    month = month,
                    streak = current,
                    best_streak = best,
                }
            end, "Syncing Hardcover dashboard…")

            if not completed then return end
            if not result or result.error then
                logger.warn("HardcoverDashboard: sync failed:", result and result.error)
                notice(result and result.error or "Could not sync Hardcover.")
                return
            end

            Cache.write("profile", nil, result.profile)
            Cache.write("goals", nil, result.goals)
            Cache.write("reading", nil, result.reading)
            Cache.write("month", key, result.month)
            Cache.write("streak", nil, { current = result.streak, best = result.best_streak })
            Cache.write("timestamp", key, { at = os.time() })

            for k, v in pairs(result) do
                view.model[k] = v
            end
            view.model.offline = false
            view.model.synced = os.date("%H:%M")
            view:render()
        end)
    end)
end

function Plugin:token_dialog()
    local dialog
    dialog = InputDialog:new{
        title = "Hardcover API token",
        input = Settings.token() or "",
        input_hint = "Paste a read-only Personal Access Token",
        buttons = {
            {
                {
                    text = "Cancel",
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = "Save",
                    is_enter_default = true,
                    callback = function()
                        local token = Settings.normalize_token(dialog:getInputText())
                        if token then
                            Settings.set("token", token)
                            UIManager:close(dialog)
                            self:onShowHardcoverDashboard()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Plugin:show_actions(view)
    local dialog
    local function close() UIManager:close(dialog) end
    dialog = ButtonDialog:new{
        title = "Hardcover Dashboard",
        buttons = {
            { { text = "Sync Now", callback = function() close(); view:refresh(true) end } },
            { { text = "Take Screenshot", callback = function()
                close()
                UIManager:nextTick(function()
                    view:take_screenshot()
                end)
            end } },
            { { text = "Set API Token", callback = function() close(); self:token_dialog() end } },
            { { text = "Import Token from Hardcover Plugin", callback = function()
                close()
                if Settings.import_token() then
                    notice("Token imported. Syncing…")
                    view:refresh(true)
                else
                    notice("No Hardcover plugin token found.")
                end
            end } },
            { { text = "Week starts: " .. (view.settings.week_start == 1 and "Sunday" or "Monday"), callback = function()
                close()
                view.settings.week_start = view.settings.week_start == 1 and 2 or 1
                Settings.set("week_start", view.settings.week_start)
                view:render()
            end } },
            { { text = "Book covers: " .. (view.settings.show_covers and "On" or "Off"), callback = function()
                close()
                view.settings.show_covers = not view.settings.show_covers
                Settings.set("show_covers", view.settings.show_covers)
                view:render()
            end } },
            { { text = "Clear Cache", callback = function()
                close()
                Cache.clear()
                notice("Dashboard cache cleared.")
            end } },
        },
    }
    UIManager:show(dialog)
end

return Plugin
