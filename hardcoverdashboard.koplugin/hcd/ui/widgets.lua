local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local RenderImage = require("ui/renderimage")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local logger = require("logger")
local C = require("hcd.constants")
local Covers = require("hcd.covers")

local M = {}

function M.scale(px)
    if Device.screen and Device.screen.scaleBySize then
        return Device.screen:scaleBySize(px)
    end
    return px
end

function M.is_color()
    if not Device:hasColorScreen() then return false end
    if G_reader_settings and G_reader_settings:has("color_rendering") and not G_reader_settings:isTrue("color_rendering") then
        return false
    end
    return true
end

function M.hex(value)
    if type(value) ~= "string" then return Blitbuffer.COLOR_BLACK end
    if Blitbuffer.colorFromString then
        local ok, c = pcall(Blitbuffer.colorFromString, value)
        if ok and c then return c end
    end
    local r, g, b = value:match("#(%x%x)(%x%x)(%x%x)")
    if r and Blitbuffer.ColorRGB32 then
        return Blitbuffer.ColorRGB32(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), 0xFF)
    end
    return Blitbuffer.COLOR_BLACK
end

function M.theme()
    local raw = M.is_color() and C.THEME_COLOR or C.THEME_GRAY
    local t = {}
    for k, v in pairs(raw) do t[k] = M.hex(v) end
    return t
end

local function paint_rounded(bb, x, y, w, h, color, radius)
    if w <= 0 or h <= 0 then return end
    local r = math.min(radius or 0, math.floor(math.min(w, h) / 2))
    if Blitbuffer.isColor8 and Blitbuffer.isColor8(color) then
        if bb.paintRoundedRect then
            bb:paintRoundedRect(x, y, w, h, color, r)
        else
            bb:paintRect(x, y, w, h, color)
        end
    else
        if bb.paintRoundedRectRGB32 then
            bb:paintRoundedRectRGB32(x, y, w, h, color, r)
        elseif bb.paintRectRGB32 then
            bb:paintRectRGB32(x, y, w, h, color)
        else
            bb:paintRect(x, y, w, h, color)
        end
    end
end
M.paint_rounded = paint_rounded

function M.book_color_index(book_id)
    local s = tostring(book_id or 1)
    local n = tonumber(s)
    if n then return (math.abs(math.floor(n)) % #C.COLORS) + 1 end
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 100000 end
    return (h % #C.COLORS) + 1
end

function M.color(book_id)
    local idx = M.book_color_index(book_id)
    local palette = M.is_color() and C.COLORS or C.GRAYS
    return M.hex(palette[idx])
end

function M.serif_face(size, bold)
    local name = bold and "noto/NotoSerif-Bold.ttf" or "noto/NotoSerif-Regular.ttf"
    local ok, face = pcall(Font.getFace, Font, name, size or 16)
    if ok and face then return face end
    return Font:getFace(bold and "tfont" or "cfont", size or 16)
end

function M.sans_face(size, bold)
    local name = bold and "smalltfont" or "cfont"
    return Font:getFace(name, size or 12)
end

function M.serif(s, size, bold, max_width, color)
    return TextWidget:new{
        text = tostring(s or ""),
        face = M.serif_face(size, bold),
        max_width = max_width,
        fgcolor = color or M.theme().text_primary,
        padding = 0,
    }
end

function M.sans(s, size, bold, max_width, color)
    return TextWidget:new{
        text = tostring(s or ""),
        face = M.sans_face(size, bold),
        bold = bold or false,
        max_width = max_width,
        fgcolor = color or M.theme().text_primary,
        padding = 0,
    }
end

-- Custom rounded progress bar (indigo for reading, gold for goals)
local RoundedBar = Widget:extend{
    width = 200,
    height = 10,
    percent = 0,
    track_color = nil,
    fill_color = nil,
    radius = 5,
}

function RoundedBar:init()
    self.dimen = Geom:new{ w = math.max(10, self.width), h = math.max(4, self.height) }
end

function RoundedBar:paintTo(bb, x, y)
    local w, h = self.dimen.w, self.dimen.h
    local t = M.theme()
    paint_rounded(bb, x, y, w, h, self.track_color or t.progress_track, self.radius or math.floor(h / 2))
    local pct = math.max(0, math.min(100, tonumber(self.percent) or 0))
    if pct > 0 then
        local fw = math.max(h, math.floor(w * pct / 100 + 0.5))
        fw = math.min(w, fw)
        paint_rounded(bb, x, y, fw, h, self.fill_color or t.progress_reading, self.radius or math.floor(h / 2))
    end
end

function M.progress_bar(percent, width, height, fill_color)
    local t = M.theme()
    local h = height or M.scale(6)
    return RoundedBar:new{
        width = width,
        height = h,
        percent = percent or 0,
        track_color = t.progress_track,
        fill_color = fill_color or t.progress_reading,
        radius = math.floor(h / 2),
    }
end

-- Custom colored dot for Day Detail book titles
local ColorDot = Widget:extend{
    size = 10,
    color = nil,
}

function ColorDot:init()
    self.dimen = Geom:new{ w = self.size, h = self.size }
end

function ColorDot:paintTo(bb, x, y)
    local r = math.max(2, math.floor(self.size / 2))
    paint_rounded(bb, x, y, self.size, self.size, self.color or Blitbuffer.COLOR_BLACK, r)
end

function M.dot(size, color)
    return ColorDot:new{ size = size or M.scale(6), color = color }
end

-- Custom continuous rounded span bar for calendar weeks
local SpanBar = Widget:extend{
    width = 40,
    height = 8,
    color = nil,
    radius = 4,
}

function SpanBar:init()
    self.dimen = Geom:new{ w = math.max(4, self.width), h = math.max(4, self.height) }
end

function SpanBar:paintTo(bb, x, y)
    paint_rounded(bb, x, y, self.dimen.w, self.dimen.h, self.color or Blitbuffer.COLOR_BLACK, self.radius or math.floor(self.dimen.h / 2))
end
M.SpanBar = SpanBar

-- Sleek tappable rounded pill button
local PillButton = InputContainer:extend{
    text = "",
    icon = nil,
    icon_size = nil,
    font_size = 10,
    bold = false,
    bg = nil,
    fg = nil,
    border_color = nil,
    bordersize = 0,
    radius = nil,
    padding_h = nil,
    padding_v = nil,
    width = nil,
    callback = nil,
}

function PillButton:init()
    local t = M.theme()
    local icon_sz = self.icon_size or M.scale(14)
    local pad_h = self.padding_h or M.scale(7)
    local pad_v = self.padding_v or M.scale(4)
    local rad = self.radius or M.scale(5)

    local row = HorizontalGroup:new{ align = "center" }
    if self.icon then
        row[#row + 1] = IconWidget:new{
            icon = self.icon,
            width = icon_sz,
            height = icon_sz,
            alpha = true,
        }
        if self.text and self.text ~= "" then
            row[#row + 1] = HorizontalSpan:new{ width = M.scale(3) }
        end
    end
    if self.text and self.text ~= "" then
        row[#row + 1] = M.sans(self.text, self.font_size, self.bold, self.width and (self.width - pad_h * 2) or nil, self.fg or t.pill_text)
    end
    local row_size = row:getSize()
    local inner = self.width and CenterContainer:new{
        dimen = Geom:new{ w = math.max(10, self.width - pad_h * 2), h = row_size.h },
        row,
    } or row
    self[1] = FrameContainer:new{
        background = self.bg or t.pill_bg,
        color = self.border_color or t.card_border,
        bordersize = self.bordersize or 0,
        radius = rad,
        padding_left = pad_h,
        padding_right = pad_h,
        padding_top = pad_v,
        padding_bottom = pad_v,
        margin = 0,
        inner,
    }
    self.dimen = self[1]:getSize()
    if self.callback then
        self.ges_events.Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        }
    end
end

function PillButton:onTap()
    if self.callback then self.callback() end
    return true
end

function M.pill(opts)
    return PillButton:new(opts)
end

-- Dark charcoal page-count badge for active calendar days
function M.page_badge(pages, font_size)
    local t = M.theme()
    local sz = font_size or 8
    return FrameContainer:new{
        background = t.page_badge_bg,
        bordersize = 0,
        radius = M.scale(3),
        padding_left = M.scale(4),
        padding_right = M.scale(4),
        padding_top = M.scale(1),
        padding_bottom = M.scale(1),
        margin = 0,
        M.sans(tostring(pages), sz, true, nil, t.page_badge_text),
    }
end

-- Soft rounded card container
function M.card(child, width, height, padding)
    local t = M.theme()
    local pad = padding or M.scale(8)
    local child_size = child:getSize()
    local inner_w = math.max(10, width - pad * 2 - 2)
    local inner_h = height and math.max(child_size.h, height - pad * 2 - 2) or child_size.h
    local inner = LeftContainer:new{
        dimen = Geom:new{ w = inner_w, h = inner_h },
        child,
    }
    return FrameContainer:new{
        width = width,
        height = height,
        background = t.card_bg,
        color = t.card_border,
        bordersize = 1,
        radius = M.scale(8),
        padding = pad,
        margin = 0,
        inner,
    }
end

-- Safe cover renderer: decodes directly at thumbnail size via RenderImage to avoid
-- overflowing KOReader's 8 MiB ImageCache on high-resolution Hardcover covers.
function M.cover(url, w, h, title, color)
    local t = M.theme()
    local inner_w = math.max(8, math.floor(w - 2))
    local inner_h = math.max(8, math.floor(h - 2))
    local path = url and Covers.path(url) or nil
    if path then
        local ok, bb = pcall(RenderImage.renderImageFile, RenderImage, path, false, inner_w, inner_h)
        if ok and bb then
            return FrameContainer:new{
                width = w,
                height = h,
                background = t.card_bg,
                color = t.card_border,
                bordersize = 1,
                radius = M.scale(2),
                padding = 0,
                margin = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = inner_w, h = inner_h },
                    ImageWidget:new{
                        image = bb,
                        width = inner_w,
                        height = inner_h,
                        scale_factor = 0,
                        image_disposable = true,
                    },
                },
            }
        else
            logger.dbg("HardcoverDashboard: cover render fallback for", path, bb)
        end
    end

    -- Tasteful colored miniature placeholder with book initials
    local initials = ""
    for word in tostring(title or "B"):gmatch("%S+") do
        initials = initials .. word:sub(1, 1):upper()
        if #initials >= 2 then break end
    end
    if initials == "" then initials = "B" end
    local bg = color or t.pill_bg
    local fg = color and Blitbuffer.COLOR_WHITE or t.text_secondary
    local font_sz = math.max(7, math.min(11, math.floor(inner_w / M.scale(6))))
    return FrameContainer:new{
        width = w,
        height = h,
        background = bg,
        color = t.card_bg,
        bordersize = 1,
        radius = M.scale(2),
        padding = 0,
        margin = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            M.sans(initials, font_sz, true, inner_w - 2, fg),
        },
    }
end

-- Forward unhandled gestures (custom KOReader Gesture Manager zones and Screenshoter)
-- to the parent FileManager / ReaderUI without letting plain taps trigger page turns.
function M.forward_gesture(ui, ev)
    if not ui or type(ev) ~= "table" then return false end
    local ges = ev.ges
    local zones = ui._ordered_touch_zones
    if type(zones) == "table" then
        for _, tzone in ipairs(zones) do
            local id = (tzone.def and tzone.def.id) or tzone.id or ""
            local allow = (ges ~= "tap") or (type(id) == "string" and (id:match("^tap_") or id:match("corner")))
            if allow and tzone.gs_range and tzone.gs_range:match(ev) then
                if tzone.handler and tzone.handler(ev) then
                    return true
                end
            end
        end
    end
    -- Also check active_widgets (e.g. KOReader's built-in Screenshoter)
    if type(ui.active_widgets) == "table" then
        local Event = require("ui/event")
        for _, aw in ipairs(ui.active_widgets) do
            if aw and aw.handleEvent and aw:handleEvent(Event:new("Gesture", ev)) then
                return true
            end
        end
    end
    return false
end

return M
