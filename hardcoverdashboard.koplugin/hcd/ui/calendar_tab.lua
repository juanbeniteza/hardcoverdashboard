local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local W = require("hcd.ui.widgets")
local D = require("hcd.date_util")
local Data = require("hcd.data")
local Detail = require("hcd.ui.day_detail_dialog")

local M = {}
local WEEKDAY_NAMES = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

local DayCell = InputContainer:extend{
    width = 80,
    height = 80,
    content = nil,
    callback = nil,
}

function DayCell:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self[1] = self.content
    if self.callback then
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        }
    end
end

function DayCell:onTap()
    if self.callback then self.callback() end
    return true
end

local function build_week_row(week_days, month_prefix, today, month_data, lanes_map, cell_w, cell_h, gap, show_covers)
    local t = W.theme()
    local row_w = cell_w * 7 + gap * 6
    local cells_row = HorizontalGroup:new{ align = "top" }
    local cell_pad = W.scale(4)
    local cell_radius = W.scale(5)

    for col = 1, 7 do
        local day = week_days[col]
        local in_month = day:sub(1, 7) == month_prefix
        local entry = in_month and month_data.days[day] or nil
        local is_today = in_month and (day == today)
        local detail = in_month and lanes_map[day] or nil

        if not in_month then
            cells_row[#cells_row + 1] = HorizontalSpan:new{ width = cell_w }
        else
            local day_num = tonumber(day:sub(9, 10))
            local day_color = is_today and t.today_text or t.text_secondary
            local day_text = W.sans(tostring(day_num), 15, is_today, cell_w - cell_pad * 2, day_color)

            local border_sz = is_today and 2 or 1
            local inner_w = math.max(10, cell_w - cell_pad * 2 - border_sz * 2)
            local inner_h = math.max(10, cell_h - cell_pad * 2 - border_sz * 2)

            local cell_overlaps = OverlapGroup:new{
                dimen = Geom:new{ w = inner_w, h = inner_h },
                day_text,
            }

            if entry and (entry.total_pages or 0) > 0 then
                local badge = W.page_badge(entry.total_pages, 13)
                badge.overlap_align = "right"
                cell_overlaps[#cell_overlaps + 1] = badge
            end

            if detail and (detail.overflow or 0) > 0 then
                local more = W.sans("+" .. detail.overflow, 12, true, inner_w, t.text_muted)
                more.overlap_offset = { 0, math.max(0, inner_h - more:getSize().h) }
                cell_overlaps[#cell_overlaps + 1] = more
            end

            local frame = FrameContainer:new{
                width = cell_w,
                height = cell_h,
                background = is_today and t.today_bg or t.cell_bg,
                color = is_today and t.today_border or t.cell_border,
                bordersize = border_sz,
                radius = cell_radius,
                padding = cell_pad,
                margin = 0,
                cell_overlaps,
            }
            cells_row[#cells_row + 1] = DayCell:new{
                width = cell_w,
                height = cell_h,
                content = frame,
                callback = function()
                    UIManager:show(Detail:new{
                        day = day,
                        entry = entry,
                        show_covers = show_covers,
                    })
                end,
            }
        end

        if col < 7 then
            cells_row[#cells_row + 1] = HorizontalSpan:new{ width = gap }
        end
    end

    local week_overlap = OverlapGroup:new{
        dimen = Geom:new{ w = row_w, h = cell_h },
        cells_row,
    }

    -- Continuous rounded colored span bars across consecutive reading days
    local bar_h = math.max(W.scale(4), math.min(W.scale(6), math.floor(cell_h * 0.08)))
    local lane_gap = math.max(W.scale(2), math.floor(bar_h * 0.55))
    local inset = W.scale(4)

    local max_lane_used = 1
    for col = 1, 7 do
        local day = week_days[col]
        if day:sub(1, 7) == month_prefix and lanes_map[day] then
            for _, ln in pairs(lanes_map[day].lanes or {}) do
                if ln > max_lane_used then max_lane_used = ln end
            end
        end
    end
    local total_bars_h = max_lane_used * bar_h + (max_lane_used - 1) * lane_gap
    local bar_area_top = math.max(math.floor(cell_h * 0.36), math.floor(cell_h * 0.58) - math.floor(total_bars_h / 2))

    for lane = 1, 3 do
        local col = 1
        while col <= 7 do
            local day = week_days[col]
            local in_month = day:sub(1, 7) == month_prefix
            local book_id = nil
            if in_month and lanes_map[day] then
                for id, ln in pairs(lanes_map[day].lanes or {}) do
                    if ln == lane then
                        book_id = id
                        break
                    end
                end
            end

            if book_id then
                local start_col = col
                local end_col = col
                while end_col < 7 do
                    local next_day = week_days[end_col + 1]
                    if next_day:sub(1, 7) == month_prefix and lanes_map[next_day] and lanes_map[next_day].lanes and lanes_map[next_day].lanes[book_id] == lane then
                        end_col = end_col + 1
                    else
                        break
                    end
                end

                local prev_day = D.add_days(week_days[start_col], -1)
                local continues_prev = start_col == 1 and month_data.days[prev_day] ~= nil and (function()
                    for _, b in ipairs(month_data.days[prev_day].books or {}) do
                        if tostring(b.book_id) == book_id then return true end
                    end
                    return false
                end)()
                local next_day = D.add_days(week_days[end_col], 1)
                local continues_next = end_col == 7 and month_data.days[next_day] ~= nil and (function()
                    for _, b in ipairs(month_data.days[next_day].books or {}) do
                        if tostring(b.book_id) == book_id then return true end
                    end
                    return false
                end)()

                local left_x = (start_col - 1) * (cell_w + gap) + (continues_prev and 1 or inset)
                local right_x = end_col * cell_w + (end_col - 1) * gap - (continues_next and 1 or inset)
                local span_w = math.max(8, right_x - left_x)
                local bar_y = bar_area_top + (lane - 1) * (bar_h + lane_gap)

                local bar = W.SpanBar:new{
                    width = span_w,
                    height = bar_h,
                    color = W.color(book_id),
                    radius = math.floor(bar_h / 2),
                }
                bar.overlap_offset = { left_x, bar_y }
                week_overlap[#week_overlap + 1] = bar

                col = end_col + 1
            else
                col = col + 1
            end
        end
    end

    -- Finish / last-active day cover thumbnails centered over the span bar
    if show_covers and cell_h >= W.scale(48) then
        local cover_h = math.min(math.floor(cell_h * 0.56), W.scale(52))
        local cover_w = math.max(W.scale(16), math.floor(cover_h * 0.67))
        for col = 1, 7 do
            local day = week_days[col]
            if day:sub(1, 7) == month_prefix and lanes_map[day] then
                local finishes = lanes_map[day].finishes or {}
                if #finishes > 0 then
                    local count = math.min(#finishes, 2)
                    local cell_left = (col - 1) * (cell_w + gap)
                    local cover_y = math.max(math.floor(cell_h * 0.30), math.floor(cell_h * 0.58) - math.floor(cover_h / 2))
                    if count == 1 then
                        local b = finishes[1]
                        local cw = W.cover(b.cover, cover_w, cover_h, b.title, W.color(b.book_id))
                        cw.overlap_offset = { cell_left + math.floor((cell_w - cover_w) / 2), cover_y }
                        week_overlap[#week_overlap + 1] = cw
                    else
                        local mini_w = math.max(W.scale(14), math.min(cover_w, math.floor((cell_w - W.scale(6)) * 0.56)))
                        local mini_h = math.min(cover_h, math.floor(mini_w * 1.48))
                        local overlap_px = W.scale(4)
                        local total_w = mini_w * 2 - overlap_px
                        local start_x = cell_left + math.floor((cell_w - total_w) / 2)
                        for k = 1, 2 do
                            local b = finishes[k]
                            local cw = W.cover(b.cover, mini_w, mini_h, b.title, W.color(b.book_id))
                            cw.overlap_offset = { start_x + (k - 1) * (mini_w - overlap_px), cover_y + (k - 1) * 2 }
                            week_overlap[#week_overlap + 1] = cw
                        end
                    end
                end
            end
        end
    end

    return week_overlap
end

function M.build(view, width, height)
    local t = W.theme()
    local pad = W.scale(10)
    local inner_w = width - pad * 2 - 2
    local y, m = view.year, view.month
    local month_prefix = string.format("%04d-%02d", y, m)
    local today = D.today()
    local today_prefix = today:sub(1, 7)
    local month = view.model.month or { days = {}, total_pages = 0, active_days = 0, book_count = 0 }
    local grid = D.month_grid(y, m, view.settings.week_start)
    local lanes = Data.lanes(month, grid)
    local num_weeks = math.floor(#grid / 7)

    -- 1) Top Row: Serif "Reading Activity" + Streak Pill
    local streak_val = view.model.streak or 0
    local streak_label = string.format("%d %s", streak_val, streak_val == 1 and "day" or "days")
    local streak_pill = W.pill{
        icon = "star.full",
        icon_size = W.scale(16),
        text = streak_label,
        font_size = 15,
        bold = true,
        bg = t.pill_bg,
        fg = t.pill_text,
        radius = W.scale(6),
        padding_h = W.scale(10),
        padding_v = W.scale(5),
    }
    local top_title_w = math.max(80, inner_w - streak_pill:getSize().w - W.scale(6))
    local heading = W.serif("Reading Activity", 21, false, top_title_w, t.text_primary)
    local card_header = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = top_title_w, h = heading:getSize().h },
            heading,
        },
        HorizontalSpan:new{ width = W.scale(6) },
        streak_pill,
    }

    -- 2) Month Navigation Row
    local prev_btn = W.pill{
        icon = "chevron.left",
        icon_size = W.scale(20),
        bg = t.card_bg,
        padding_h = W.scale(8),
        padding_v = W.scale(4),
        callback = function() view:shift_month(-1) end,
    }
    local next_btn = W.pill{
        icon = "chevron.right",
        icon_size = W.scale(20),
        bg = t.card_bg,
        padding_h = W.scale(8),
        padding_v = W.scale(4),
        callback = function() view:shift_month(1) end,
    }
    local nav_mid_w = math.max(60, inner_w - prev_btn:getSize().w - next_btn:getSize().w)
    local mid_items = HorizontalGroup:new{
        align = "center",
        W.sans(D.month_title(y, m), 19, true, nav_mid_w - W.scale(70), t.text_primary),
    }
    if month_prefix ~= today_prefix then
        mid_items[#mid_items + 1] = HorizontalSpan:new{ width = W.scale(8) }
        mid_items[#mid_items + 1] = W.pill{
            text = "Today",
            font_size = 14,
            bold = true,
            bg = t.pill_bg,
            fg = t.today_text,
            padding_h = W.scale(8),
            padding_v = W.scale(3),
            callback = function() view:go_today() end,
        }
    end
    local nav_row = HorizontalGroup:new{
        align = "center",
        prev_btn,
        CenterContainer:new{
            dimen = Geom:new{ w = nav_mid_w, h = math.max(prev_btn:getSize().h, mid_items:getSize().h) },
            mid_items,
        },
        next_btn,
    }

    -- 3) Clean borderless Weekday Header Row
    local gap = W.scale(4)
    local cell_w = math.floor((inner_w - gap * 6) / 7)
    local sample_wd = W.sans("Wed", 15, false, cell_w, t.text_secondary)
    local wd_h = sample_wd:getSize().h
    local weekday_row = HorizontalGroup:new{ align = "center" }
    for i = 1, 7 do
        local name = WEEKDAY_NAMES[(i + (view.settings.week_start or 1) - 2) % 7 + 1]
        weekday_row[#weekday_row + 1] = CenterContainer:new{
            dimen = Geom:new{ w = cell_w, h = wd_h },
            W.sans(name, 15, false, cell_w, t.text_secondary),
        }
        if i < 7 then
            weekday_row[#weekday_row + 1] = HorizontalSpan:new{ width = gap }
        end
    end

    -- 4) Footer summary line
    local footer_text = string.format(
        "%s · %d pages · %d active %s · %d %s",
        D.month_title(y, m),
        month.total_pages or 0,
        month.active_days or 0,
        (month.active_days == 1) and "day" or "days",
        month.book_count or 0,
        (month.book_count == 1) and "book" or "books"
    )
    local footer_w = W.sans(footer_text, 14, false, inner_w, t.text_secondary)

    local s1, s2, s3, s4 = W.scale(5), W.scale(5), W.scale(4), W.scale(6)
    local fixed_h = pad * 2 + 2
        + card_header:getSize().h + s1
        + nav_row:getSize().h + s2
        + weekday_row:getSize().h + s3
        + footer_w:getSize().h + s4
        + gap * (num_weeks - 1)
    local cell_h = math.max(W.scale(38), math.floor((height - fixed_h) / num_weeks))

    local body = VerticalGroup:new{
        align = "left",
        card_header,
        VerticalSpan:new{ width = s1 },
        nav_row,
        VerticalSpan:new{ width = s2 },
        weekday_row,
        VerticalSpan:new{ width = s3 },
    }

    for week = 1, num_weeks do
        local week_days = {}
        for col = 1, 7 do
            week_days[col] = grid[(week - 1) * 7 + col]
        end
        body[#body + 1] = build_week_row(
            week_days,
            month_prefix,
            today,
            month,
            lanes,
            cell_w,
            cell_h,
            gap,
            view.settings.show_covers
        )
        if week < num_weeks then
            body[#body + 1] = VerticalSpan:new{ width = gap }
        end
    end

    body[#body + 1] = VerticalSpan:new{ width = s4 }
    body[#body + 1] = CenterContainer:new{
        dimen = Geom:new{ w = inner_w, h = footer_w:getSize().h },
        footer_w,
    }

    return W.card(body, width, height, pad)
end

return M
