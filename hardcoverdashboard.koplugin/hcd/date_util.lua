local M = {}
local months = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
local weekdays = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}

function M.is_leap(y) return y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0) end
function M.days_in_month(y, m)
    if m == 2 then return M.is_leap(y) and 29 or 28 end
    if m == 4 or m == 6 or m == 9 or m == 11 then return 30 end
    return 31
end
function M.valid(s)
    if type(s) ~= "string" then return false end
    local y,m,d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    y,m,d = tonumber(y),tonumber(m),tonumber(d)
    return y ~= nil and y >= 1 and m >= 1 and m <= 12 and d >= 1 and d <= M.days_in_month(y,m)
end
function M.iso_day(s)
    if type(s) ~= "string" then return nil end
    local day = s:match("^(%d%d%d%d%-%d%d%-%d%d)")
    return M.valid(day) and day or nil
end
function M.parse(s)
    local day = M.iso_day(s)
    if not day then return nil end
    local y,m,d = day:match("^(%d+)%-(%d+)%-(%d+)$")
    return tonumber(y),tonumber(m),tonumber(d)
end
-- Civil-date arithmetic avoids local timezone and DST transitions.
function M.ordinal(y,m,d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = m + (m > 2 and -3 or 9)
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    return era * 146097 + yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy - 719468
end
function M.from_ordinal(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe/1460) + math.floor(doe/36524) - math.floor(doe/146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365*yoe + math.floor(yoe/4) - math.floor(yoe/100))
    local mp = math.floor((5*doy + 2)/153)
    local d = doy - math.floor((153*mp+2)/5) + 1
    local m = mp + (mp < 10 and 3 or -9)
    if m <= 2 then y = y + 1 end
    return string.format("%04d-%02d-%02d",y,m,d)
end
function M.add_days(day, n)
    local y,m,d = M.parse(day)
    if not y then return nil end
    return M.from_ordinal(M.ordinal(y,m,d)+n)
end
function M.weekday(day)
    local y,m,d = M.parse(day)
    if not y then return nil end
    return (M.ordinal(y,m,d)+4) % 7 + 1 -- Sunday=1
end
function M.month_grid(y,m,week_start)
    local first = string.format("%04d-%02d-01",y,m)
    local offset = (M.weekday(first) - (week_start or 1)) % 7
    local n = math.ceil((offset + M.days_in_month(y,m))/7)*7
    local grid = {}
    for i=1,n do grid[i] = M.add_days(first,i-offset-1) end
    return grid
end
function M.month_shift(y,m,n)
    local v = y*12 + m-1+n
    return math.floor(v/12),v%12+1
end
function M.month_title(y,m) return months[m] .. " " .. y end
function M.format(day, full)
    local y,m,d = M.parse(day)
    if not y then return "" end
    if full then return weekdays[M.weekday(day)]..", "..months[m].." "..d..", "..y end
    return months[m]:sub(1,3).." "..d..", "..y
end
function M.range(a,b)
    if not M.iso_day(a) then return "" end
    local first = M.format(M.iso_day(a))
    if M.iso_day(b) and M.iso_day(b) ~= M.iso_day(a) then return first.." – "..M.format(M.iso_day(b)) end
    return first
end
function M.today() return os.date("%Y-%m-%d") end
return M
