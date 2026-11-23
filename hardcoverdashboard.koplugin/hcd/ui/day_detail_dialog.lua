local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local W = require("hcd.ui.widgets")
local D = require("hcd.date_util")

local Dialog = InputContainer:extend{}

function Dialog:init()
    self.page = 1
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:render()
end

function Dialog:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "ui")
    return true
end

function Dialog:render()
    if self[1] and self[1].free then self[1]:free() end
    local t = W.theme()
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    local modal_w = math.min(math.floor(screen_w * 0.88), W.scale(480))
    local pad = W.scale(14)
    local inner_w = modal_w - pad * 2 - 4

    local entry = self.entry or { total_pages = 0, books = {} }
    local books = entry.books or {}
    local per_page = 4
    local total_pages = math.max(1, math.ceil(#books / per_page))
    self.page = math.min(self.page, total_pages)

    local close_btn = W.pill{
        icon = "close",
        icon_size = W.scale(20),
        bg = t.card_bg,
        padding_h = W.scale(7),
        padding_v = W.scale(6),
        callback = function() self:onClose() end,
    }
    local title_w = math.max(80, inner_w - close_btn:getSize().w - W.scale(6))
    local title_widget = W.serif(D.format(self.day, true), 22, false, title_w, t.text_primary)
    local header = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = title_w, h = title_widget:getSize().h },
            title_widget,
        },
        HorizontalSpan:new{ width = W.scale(6) },
        close_btn,
    }

    local content = VerticalGroup:new{
        align = "left",
        header,
        VerticalSpan:new{ width = W.scale(4) },
    }

    if #books == 0 then
        content[#content + 1] = VerticalSpan:new{ width = W.scale(8) }
        content[#content + 1] = W.sans("No reading activity recorded on this date.", 16, false, inner_w, t.text_secondary)
        content[#content + 1] = VerticalSpan:new{ width = W.scale(4) }
    else
        local summary_text = string.format(
            "%d %s · %d %s",
            entry.total_pages or 0,
            (entry.total_pages == 1) and "page" or "pages",
            #books,
            (#books == 1) and "book" or "books"
        )
        content[#content + 1] = W.sans(summary_text, 16, false, inner_w, t.text_secondary)
        content[#content + 1] = VerticalSpan:new{ width = W.scale(10) }

        local cover_w = W.scale(60)
        local cover_h = W.scale(88)
        local gap_x = W.scale(12)
        local info_w = math.max(80, inner_w - cover_w - gap_x)

        for i = (self.page - 1) * per_page + 1, math.min(#books, self.page * per_page) do
            local b = books[i]
            local bcolor = W.color(b.book_id or i)
            local dot_sz = W.scale(8)
            local title_row = HorizontalGroup:new{
                align = "center",
                W.dot(dot_sz, bcolor),
                HorizontalSpan:new{ width = W.scale(6) },
                W.sans(b.title or "Untitled", 18, true, info_w - dot_sz - W.scale(7), t.text_primary),
            }
            local meta = VerticalGroup:new{
                align = "left",
                title_row,
            }
            if b.author and b.author ~= "" then
                meta[#meta + 1] = VerticalSpan:new{ width = W.scale(3) }
                meta[#meta + 1] = W.sans(b.author, 15, false, info_w, t.text_secondary)
            end
            local range = D.range(b.started_at, b.finished_at)
            if range ~= "" then
                meta[#meta + 1] = VerticalSpan:new{ width = W.scale(3) }
                meta[#meta + 1] = W.sans(range, 15, false, info_w, t.text_secondary)
            end
            meta[#meta + 1] = VerticalSpan:new{ width = W.scale(3) }
            local pages_label = (b.pages_on_date and b.pages_on_date > 0)
                and string.format("%d %s on this date", b.pages_on_date, b.pages_on_date == 1 and "page" or "pages")
                or "Reading activity logged"
            meta[#meta + 1] = W.sans(pages_label, 15, false, info_w, t.text_primary)

            local row = HorizontalGroup:new{
                align = "top",
                W.cover(self.show_covers and b.cover or nil, cover_w, cover_h, b.title, bcolor),
                HorizontalSpan:new{ width = gap_x },
                meta,
            }
            content[#content + 1] = row
            if i < math.min(#books, self.page * per_page) then
                content[#content + 1] = VerticalSpan:new{ width = W.scale(10) }
            end
        end

        if total_pages > 1 then
            content[#content + 1] = VerticalSpan:new{ width = W.scale(10) }
            local prev_btn = W.pill{
                text = "< Prev",
                font_size = 9,
                callback = function()
                    if self.page > 1 then
                        self.page = self.page - 1
                        self:render()
                        UIManager:setDirty(self, "ui")
                    end
                end,
            }
            local next_btn = W.pill{
                text = "Next >",
                font_size = 9,
                callback = function()
                    if self.page < total_pages then
                        self.page = self.page + 1
                        self:render()
                        UIManager:setDirty(self, "ui")
                    end
                end,
            }
            local mid_w = math.max(40, inner_w - prev_btn:getSize().w - next_btn:getSize().w)
            content[#content + 1] = HorizontalGroup:new{
                align = "center",
                prev_btn,
                CenterContainer:new{
                    dimen = Geom:new{ w = mid_w, h = prev_btn:getSize().h },
                    W.sans(string.format("Page %d of %d", self.page, total_pages), 9, false, mid_w, t.text_secondary),
                },
                next_btn,
            }
        end
    end

    self.box = FrameContainer:new{
        width = modal_w,
        background = t.card_bg,
        color = t.card_border,
        bordersize = 2,
        radius = W.scale(10),
        padding = pad,
        margin = 0,
        content,
    }
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    local diagonal = math.sqrt(screen_w ^ 2 + screen_h ^ 2)
    self.dimen = Geom:new{ w = screen_w, h = screen_h }
    self[1] = CenterContainer:new{
        dimen = self.dimen,
        self.box,
    }
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
    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        },
    }
end

function Dialog:take_screenshot()
    if self.on_screenshot then
        self.on_screenshot()
        return true
    end
    return false
end

Dialog.onTapDiagonal = Dialog.take_screenshot
Dialog.onSwipeDiagonal = Dialog.take_screenshot

function Dialog:onTapClose(_, ges)
    if self.box and self.box.dimen and not ges.pos:intersectWith(self.box.dimen) then
        -- Let corner-tap gestures (e.g., custom screenshot gesture) fire without closing the dialog
        if W.forward_gesture(self.ui, ges) then
            return true
        end
        return self:onClose()
    end
    return false
end

function Dialog:handleEvent(ev)
    if InputContainer.handleEvent(self, ev) then
        return true
    end
    if ev and ev.handler == "onGesture" and ev.args and ev.args[1] then
        return W.forward_gesture(self.ui, ev.args[1])
    end
    return false
end

return Dialog
