local DataStorage = require("datastorage")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local W = require("hcd.ui.widgets")
local D = require("hcd.date_util")
local Calendar = require("hcd.ui.calendar_tab")

local View = InputContainer:extend{}

local GOAL_UNITS = { book = "books", page = "pages", hour = "hours" }

local function format_duration(seconds)
    local mins = math.floor((seconds or 0) / 60)
    return string.format("%dh %dm", math.floor(mins / 60), mins % 60)
end

function View:init()
    self.year, self.month = D.parse(D.today())
    self.reading_idx = 1
    self.goal_idx = 1
    self:render()
end

-- Build the Currently Reading card (read-only, cycles cleanly if >1 book)
function View:build_reading_card(card_w, card_h)
    local t = W.theme()
    local pad = W.scale(9)
    local inner_w = card_w - pad * 2 - 2
    local rows = self.model.reading or {}

    local title_w_widget = W.serif("Currently Reading", 21, false, inner_w, t.text_primary)
    if #rows == 0 then
        local body = VerticalGroup:new{
            align = "left",
            title_w_widget,
            VerticalSpan:new{ width = W.scale(8) },
            W.sans("No books currently reading.", 16, false, inner_w, t.text_secondary),
        }
        return W.card(body, card_w, card_h, pad)
    end

    self.reading_idx = math.max(1, math.min(self.reading_idx or 1, #rows))
    local b = rows[self.reading_idx]

    -- Card Header: "Currently Reading" + optional cycle pill "1 / 2 ›"
    local right_ctrl = nil
    if #rows > 1 then
        right_ctrl = W.pill{
            text = string.format("%d / %d ›", self.reading_idx, #rows),
            font_size = 15,
            bold = true,
            bg = t.pill_bg,
            fg = t.pill_text,
            padding_h = W.scale(8),
            padding_v = W.scale(4),
            callback = function()
                self.reading_idx = (self.reading_idx % #rows) + 1
                self:render()
            end,
        }
    end
    local title_max_w = right_ctrl and (inner_w - right_ctrl:getSize().w - W.scale(6)) or inner_w
    local heading = W.serif("Currently Reading", 21, false, title_max_w, t.text_primary)
    local header = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = title_max_w, h = heading:getSize().h },
            heading,
        },
    }
    if right_ctrl then
        header[#header + 1] = HorizontalSpan:new{ width = W.scale(6) }
        header[#header + 1] = right_ctrl
    end

    -- Book content sized cleanly for DPI
    local cover_w = math.min(W.scale(66), math.floor(inner_w * 0.25))
    local cover_h = math.floor(cover_w * 1.48)
    local gap_x = W.scale(10)
    local info_w = math.max(60, inner_w - cover_w - gap_x)

    local progress_text
    if b.audio then
        progress_text = string.format("%s of %s (%d%%)", format_duration(b.progress_seconds), format_duration(b.seconds), b.percent or 0)
    elseif b.pages and b.pages > 0 then
        progress_text = string.format("Page %d of %d (%d%%)", b.progress_pages or 0, b.pages, b.percent or 0)
    else
        progress_text = string.format("%d%% complete", b.percent or 0)
    end

    local info = VerticalGroup:new{
        align = "left",
        W.sans(b.title or "Untitled", 18, true, info_w, t.text_primary),
    }
    if b.author and b.author ~= "" then
        info[#info + 1] = VerticalSpan:new{ width = W.scale(2) }
        info[#info + 1] = W.sans(b.author, 15, false, info_w, t.text_secondary)
    end
    info[#info + 1] = VerticalSpan:new{ width = W.scale(7) }
    info[#info + 1] = W.sans(progress_text, 15, false, info_w, t.text_primary)
    info[#info + 1] = VerticalSpan:new{ width = W.scale(5) }
    info[#info + 1] = W.progress_bar(b.percent or 0, info_w, W.scale(7), t.progress_reading)
    if b.started_at then
        info[#info + 1] = VerticalSpan:new{ width = W.scale(5) }
        info[#info + 1] = W.sans("Started " .. D.format(b.started_at), 13, false, info_w, t.text_muted)
    end

    local body = VerticalGroup:new{
        align = "left",
        header,
        VerticalSpan:new{ width = W.scale(8) },
        HorizontalGroup:new{
            align = "top",
            W.cover(self.settings.show_covers and b.cover or nil, cover_w, cover_h, b.title, W.color(b.book_id)),
            HorizontalSpan:new{ width = gap_x },
            info,
        },
    }

    if #rows > 1 then
        local next_b = rows[(self.reading_idx % #rows) + 1]
        body[#body + 1] = VerticalSpan:new{ width = W.scale(6) }
        body[#body + 1] = W.sans(
            string.format("Next: %s (%d%%)", next_b.title or "Untitled", next_b.percent or 0),
            13,
            false,
            inner_w,
            t.text_muted
        )
    end

    return W.card(body, card_w, card_h, pad)
end

-- Build the Reading Goals card (gold progress bar + completion status)
function View:build_goals_card(card_w, card_h)
    local t = W.theme()
    local pad = W.scale(9)
    local inner_w = card_w - pad * 2 - 2
    local goals = self.model.goals or {}

    if #goals == 0 then
        local body = VerticalGroup:new{
            align = "left",
            W.serif("Reading Goals", 21, false, inner_w, t.text_primary),
            VerticalSpan:new{ width = W.scale(8) },
            W.sans("No active reading goals.", 16, false, inner_w, t.text_secondary),
        }
        return W.card(body, card_w, card_h, pad)
    end

    self.goal_idx = math.max(1, math.min(self.goal_idx or 1, #goals))
    local g = goals[self.goal_idx]
    local unit = GOAL_UNITS[g.metric] or g.metric or "books"
    local goal_title = g.description or (((g.end_date or ""):sub(1, 4)) .. " Reading Goal")
    local count_text = string.format("%g of %g %s", g.progress or 0, g.goal or 0, unit)

    local right_ctrl = nil
    if #goals > 1 then
        right_ctrl = W.pill{
            text = string.format("%d / %d ›", self.goal_idx, #goals),
            font_size = 15,
            bold = true,
            bg = t.pill_bg,
            fg = t.pill_text,
            padding_h = W.scale(8),
            padding_v = W.scale(4),
            callback = function()
                self.goal_idx = (self.goal_idx % #goals) + 1
                self:render()
            end,
        }
    end
    local title_max_w = right_ctrl and (inner_w - right_ctrl:getSize().w - W.scale(6)) or inner_w
    local heading = W.serif("Reading Goals", 21, false, title_max_w, t.text_primary)
    local header = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = title_max_w, h = heading:getSize().h },
            heading,
        },
    }
    if right_ctrl then
        header[#header + 1] = HorizontalSpan:new{ width = W.scale(6) }
        header[#header + 1] = right_ctrl
    end

    local count_w = W.sans(count_text, 15, true, math.floor(inner_w * 0.46), t.text_primary)
    local gtitle_max_w = math.max(40, inner_w - count_w:getSize().w - W.scale(4))
    local gtitle_w = W.sans(goal_title, 15, true, gtitle_max_w, t.text_primary)
    local goal_row = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = gtitle_max_w, h = gtitle_w:getSize().h },
            gtitle_w,
        },
        HorizontalSpan:new{ width = W.scale(4) },
        count_w,
    }

    local status_line
    if g.is_completed then
        status_line = g.end_date
            and string.format("Read %g %s by %s · Completed!", g.goal or 0, unit, D.format(g.end_date))
            or "Goal completed!"
    else
        local remaining = math.max(0, (g.goal or 0) - (g.progress or 0))
        status_line = g.end_date
            and string.format("%g %s to go · Due %s", remaining, unit, D.format(g.end_date))
            or string.format("%g %s remaining", remaining, unit)
    end

    local body = VerticalGroup:new{
        align = "left",
        header,
        VerticalSpan:new{ width = W.scale(10) },
        goal_row,
        VerticalSpan:new{ width = W.scale(7) },
        W.progress_bar(g.percent or 0, inner_w, W.scale(8), t.progress_goal),
        VerticalSpan:new{ width = W.scale(8) },
        W.sans(status_line, 14, false, inner_w, t.text_secondary),
    }

    local best = self.model.best_streak or 0
    if best > 0 then
        body[#body + 1] = VerticalSpan:new{ width = W.scale(7) }
        body[#body + 1] = W.sans(
            string.format("Streak: %d days · Best: %d days", self.model.streak or 0, best),
            14,
            false,
            inner_w,
            t.text_muted
        )
    end

    return W.card(body, card_w, card_h, pad)
end

function View:render()
    if self[1] and self[1].free then self[1]:free() end
    local t = W.theme()
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    local margin = W.scale(10)
    local gap = W.scale(8)
    local content_w = screen_w - margin * 2

    -- Editorial Header: "Hi Juan Benitez" + subtitle on left, compact action pills on right
    local profile = self.model.profile
    local name = (profile and (profile.name or profile.username)) or "Reader"
    local status_suffix = self.model.offline
        and "Offline (cached)"
        or ("Synced " .. (self.model.synced or "just now"))
    local subtitle_text = "Welcome to your reading dashboard! · " .. status_suffix

    local sync_btn = W.pill{
        text = "Sync",
        font_size = 15,
        bold = true,
        bg = t.card_bg,
        fg = t.text_primary,
        border_color = t.card_border,
        bordersize = 1,
        radius = W.scale(6),
        padding_h = W.scale(10),
        padding_v = W.scale(6),
        callback = function() self:refresh(true) end,
    }
    local settings_btn = W.pill{
        icon = "appbar.settings",
        icon_size = W.scale(20),
        bg = t.card_bg,
        border_color = t.card_border,
        bordersize = 1,
        radius = W.scale(6),
        padding_h = W.scale(7),
        padding_v = W.scale(6),
        callback = function() self:actions() end,
    }
    local close_btn = W.pill{
        icon = "close",
        icon_size = W.scale(20),
        bg = t.card_bg,
        border_color = t.card_border,
        bordersize = 1,
        radius = W.scale(6),
        padding_h = W.scale(7),
        padding_v = W.scale(6),
        callback = function() self:onClose() end,
    }
    local actions_row = HorizontalGroup:new{
        align = "center",
        sync_btn,
        HorizontalSpan:new{ width = W.scale(5) },
        settings_btn,
        HorizontalSpan:new{ width = W.scale(5) },
        close_btn,
    }

    local greet_w = math.max(100, content_w - actions_row:getSize().w - W.scale(8))
    local greet_stack = VerticalGroup:new{
        align = "left",
        W.serif("Hi " .. name, 25, false, greet_w, t.text_primary),
        VerticalSpan:new{ width = W.scale(2) },
        W.sans(subtitle_text, 15, false, greet_w, t.text_secondary),
    }
    local header = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = greet_w, h = greet_stack:getSize().h },
            greet_stack,
        },
        HorizontalSpan:new{ width = W.scale(8) },
        actions_row,
    }

    local main_h = screen_h - margin * 2 - header:getSize().h - gap
    local main_body

    if screen_w >= screen_h then
        -- Landscape: Screenshot 1 two-column layout
        local left_w = math.floor((content_w - gap) * 0.36)
        local right_w = content_w - gap - left_w
        local reading_h = math.floor((main_h - gap) * 0.56)
        local goals_h = main_h - gap - reading_h
        local left_col = VerticalGroup:new{
            align = "left",
            self:build_reading_card(left_w, reading_h),
            VerticalSpan:new{ width = gap },
            self:build_goals_card(left_w, goals_h),
        }
        main_body = HorizontalGroup:new{
            align = "top",
            left_col,
            HorizontalSpan:new{ width = gap },
            Calendar.build(self, right_w, main_h),
        }
    else
        -- Portrait (e.g., Kobo Libra Colour 1264x1680):
        -- Measure natural height of top cards so NOTHING ever clips or overlaps!
        local read_w = math.floor((content_w - gap) * 0.56)
        local goal_w = content_w - gap - read_w
        local probe_read = self:build_reading_card(read_w, nil)
        local probe_goal = self:build_goals_card(goal_w, nil)
        local top_h = math.max(probe_read:getSize().h, probe_goal:getSize().h)
        if probe_read.free then probe_read:free() end
        if probe_goal.free then probe_goal:free() end

        local cal_h = math.max(W.scale(260), main_h - top_h - gap)
        local top_row = HorizontalGroup:new{
            align = "top",
            self:build_reading_card(read_w, top_h),
            HorizontalSpan:new{ width = gap },
            self:build_goals_card(goal_w, top_h),
        }
        main_body = VerticalGroup:new{
            align = "left",
            top_row,
            VerticalSpan:new{ width = gap },
            Calendar.build(self, content_w, cal_h),
        }
    end

    local page = VerticalGroup:new{
        align = "left",
        header,
        VerticalSpan:new{ width = gap },
        main_body,
    }

    self.dimen = Geom:new{ w = screen_w, h = screen_h }
    self[1] = FrameContainer:new{
        width = screen_w,
        height = screen_h,
        background = t.canvas_bg,
        bordersize = 0,
        padding = margin,
        margin = 0,
        page,
    }

    local diagonal = math.sqrt(screen_w ^ 2 + screen_h ^ 2)
    self.ges_events.TapDiagonal = {
        GestureRange:new{
            ges = "two_finger_tap",
            scale = { diagonal - W.scale(200), diagonal },
            rate = 1.0,
        },
    }
    self.ges_events.SwipeDiagonal = {
        GestureRange:new{
            ges = "swipe",
            scale = { diagonal - W.scale(200), diagonal },
            rate = 1.0,
        },
    }
    self.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            range = self.dimen,
        },
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
        self.key_events.NextPage = { { Device.input.group.PgFwd } }
        self.key_events.PrevPage = { { Device.input.group.PgBack } }
    end
    UIManager:setDirty(self, "ui")
end

function View:take_screenshot()
    local custom_dir = G_reader_settings and G_reader_settings:readSetting("screenshot_dir")
    local dir = (type(custom_dir) == "string" and custom_dir ~= "" and custom_dir:gsub("/$", ""))
        or (DataStorage:getFullDataDir() .. "/screenshots")
    util.makePath(dir)
    local path = os.date(dir .. "/HardcoverDashboard_%Y-%m-%d_%H%M%S.png")
    local ok, err = pcall(function()
        Device.screen:shot(path)
    end)
    if ok then
        UIManager:show(InfoMessage:new{ text = "Screenshot saved to:\n" .. path })
    else
        UIManager:show(InfoMessage:new{ text = "Could not save screenshot:\n" .. tostring(err) })
    end
    return true
end

View.onTapDiagonal = View.take_screenshot
View.onSwipeDiagonal = View.take_screenshot

function View:shift_month(n)
    self.year, self.month = D.month_shift(self.year, self.month, n)
    self.plugin:load_month(self.year, self.month, self)
    self:render()
end

function View:go_today()
    self.year, self.month = D.parse(D.today())
    self.plugin:load_month(self.year, self.month, self)
    self:render()
end

function View:refresh(force) self.plugin:refresh(self, force) end
function View:actions() self.plugin:show_actions(self) end

function View:onSwipe(_, ges)
    if ges.direction == "west" then
        self:shift_month(1)
        return true
    elseif ges.direction == "east" then
        self:shift_month(-1)
        return true
    end
    -- Let diagonal / vertical gestures propagate to KOReader (e.g., Screenshoter)
    return false
end

function View:onPageFwd()
    self:shift_month(1)
    return true
end

function View:onPageBack()
    self:shift_month(-1)
    return true
end

View.onNextPage = View.onPageFwd
View.onPrevPage = View.onPageBack

function View:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    return true
end

function View:onScreenResize()
    self:render()
    return true
end

return View
