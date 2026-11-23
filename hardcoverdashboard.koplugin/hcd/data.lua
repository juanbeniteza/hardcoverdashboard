local D = require("hcd.date_util")
local M = {}

local function number(x)
    if type(x) == "number" then return x end
    if type(x) == "string" then return tonumber(x) end
    return nil
end

local function str(x)
    return type(x) == "string" and x ~= "" and x or nil
end

local function object(x)
    return type(x) == "table" and x or {}
end

local function image_url(x)
    x = object(x)
    return str(x.url)
end
M.image_url = image_url

function M.authors(c)
    c = object(c)
    local preferred, fallback = {}, {}
    for _, v in ipairs(c) do
        if type(v) == "table" then
            local name = str(object(v.author).name) or str(v.name)
            if name then
                fallback[#fallback + 1] = name
                if v.primary == true or v.contribution == nil or v.contribution == "Author" then
                    preferred[#preferred + 1] = name
                end
            end
        end
    end
    if #preferred == 0 then preferred = fallback end
    return table.concat(preferred, ", ")
end

function M.reading(rows)
    local result = {}
    for _, ub in ipairs(rows or {}) do
        if type(ub) == "table" then
            local reads = type(ub.user_book_reads) == "table" and ub.user_book_reads or {}
            local active
            for _, r in ipairs(reads) do
                if type(r) == "table" and D.iso_day(r.started_at) and not D.iso_day(r.finished_at) then
                    if not active or (number(r.id) or 0) > (number(active.id) or 0) then
                        active = r
                    end
                end
            end
            active = active or (type(reads[1]) == "table" and reads[1]) or {}
            local book = object(ub.book)
            local edition = object(ub.edition)
            local read_edition = object(active.edition)
            local pages = number(read_edition.pages) or number(edition.pages) or number(book.pages)
            local seconds = number(read_edition.audio_seconds) or number(edition.audio_seconds) or number(book.audio_seconds)
            local progress_pages = number(active.progress_pages) or 0
            local progress_seconds = number(active.progress_seconds) or 0
            local audio = (number(read_edition.reading_format_id) or number(edition.reading_format_id)) == 2
                or (not pages and seconds and seconds > 0)
            local fraction
            if audio then
                fraction = (seconds and seconds > 0) and (progress_seconds / seconds) or (number(active.progress) or 0)
            else
                fraction = (pages and pages > 0) and (progress_pages / pages) or (number(active.progress) or 0)
            end
            if fraction > 1 then fraction = fraction / 100 end
            fraction = math.max(0, math.min(1, fraction))
            result[#result + 1] = {
                id = ub.id,
                book_id = ub.book_id,
                title = str(edition.title) or str(book.title) or "Untitled",
                author = M.authors(book.cached_contributors),
                cover = image_url(read_edition.cached_image) or image_url(edition.cached_image) or image_url(book.cached_image),
                pages = pages,
                seconds = seconds,
                progress_pages = math.floor(progress_pages + 0.5),
                progress_seconds = math.floor(progress_seconds + 0.5),
                audio = audio,
                percent = math.floor(fraction * 100 + 0.5),
                started_at = D.iso_day(active.started_at),
                updated_at = str(ub.updated_at),
            }
        end
    end
    return result
end

function M.goals(rows, year)
    local result = {}
    for _, g in ipairs(rows or {}) do
        if type(g) == "table" and g.archived ~= true then
            local goal = number(g.goal) or 0
            local progress = number(g.progress) or 0
            local metric = str(g.metric) or "book"
            if metric == "hour" then
                progress = math.floor((progress / 3600) * 10 + 0.5) / 10
            end
            local end_date = D.iso_day(g.end_date)
            local start_date = D.iso_day(g.start_date)
            local completed_at = D.iso_day(g.completed_at)
            local state = str(g.state) or "active"
            local end_year = end_date and tonumber(end_date:sub(1, 4)) or nil
            local active = (state == "active" or state == "in_progress" or end_year == year) and 1 or 0
            local is_completed = (state == "completed") or (completed_at ~= nil) or (goal > 0 and progress >= goal)
            result[#result + 1] = {
                id = g.id,
                metric = metric,
                goal = goal,
                progress = progress,
                description = str(g.description),
                state = state,
                completed_at = completed_at,
                is_completed = is_completed,
                start_date = start_date,
                end_date = end_date,
                percent = goal > 0 and math.min(100, math.floor(progress / goal * 100 + 0.5)) or 0,
                rank = active,
            }
        end
    end
    table.sort(result, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        return (a.end_date or "") > (b.end_date or "")
    end)
    return result
end

local function metadata(x) return object(x) end

local function day_of(j)
    if type(j) ~= "table" then return nil end
    if D.valid(j.journal_date) then return j.journal_date end
    return D.iso_day(j.action_at)
end

local function page_value(meta, pages)
    local current = number(meta.progress_pages) or number(meta.page)
    if current then return current end
    local p = number(meta.progress)
    if p and pages then
        if p <= 1 then return p * pages end
        if p <= 100 then return p / 100 * pages end
    end
    return p
end

local function delta(meta, pages, last)
    meta = object(meta)
    for _, k in ipairs({ "pages_read", "pages_delta", "delta_pages", "pages_diff" }) do
        local v = number(meta[k])
        if v then return math.max(0, v) end
    end
    local to = number(meta.progress_pages) or number(meta.to_page) or number(meta.end_page) or number(meta.page)
    local from = number(meta.previous_progress_pages) or number(meta.from_page) or number(meta.start_page) or number(meta.previous_page)
    if to and from then return math.max(0, to - from) end
    local p = number(meta.progress) or number(meta.percentage)
    local prev = number(meta.previous_progress)
    if p and prev and pages then
        local scale = (p <= 1 and prev <= 1) and 1 or 100
        return math.max(0, (p - prev) / scale * pages)
    end
    local current = page_value(meta, pages)
    if current then return math.max(0, current - (last or 0)) end
    return 0
end
M.journal_delta = delta

function M.activity(journals, reads, month_start, month_end)
    local days, books = {}, {}
    local ordered = {}
    for _, j in ipairs(journals or {}) do
        if type(j) == "table" then ordered[#ordered + 1] = j end
    end
    table.sort(ordered, function(a, b)
        local ta = str(a.action_at) or ""
        local tb = str(b.action_at) or ""
        if ta == tb then return (number(a.id) or 0) < (number(b.id) or 0) end
        return ta < tb
    end)

    local watermarks = {}
    for _, j in ipairs(ordered) do
        local day = day_of(j)
        local book_obj = object(j.book)
        local edition_obj = object(j.edition)
        local raw_id = j.book_id or book_obj.id or "unknown"
        local id = tostring(raw_id)
        local meta = metadata(j.metadata)
        local pages = number(edition_obj.pages) or number(book_obj.pages)
        if j.event == "user_book_read_started" or j.event == "status_currently_reading" then
            watermarks[id] = 0
        end
        local n = math.floor(delta(meta, pages, watermarks[id]) + 0.5)
        local current = page_value(meta, pages)
        if current then
            watermarks[id] = current
        elseif n > 0 then
            watermarks[id] = (watermarks[id] or 0) + n
        end
        if n > 0 and day and (not month_start or day >= month_start) and (not month_end or day <= month_end) then
            local entry = days[day] or { date = day, total_pages = 0, books = {}, active = true }
            days[day] = entry
            local b = entry.books[id]
            if not b then
                b = {
                    book_id = raw_id,
                    title = str(book_obj.title) or "Untitled",
                    author = M.authors(book_obj.cached_contributors),
                    cover = image_url(edition_obj.cached_image) or image_url(book_obj.cached_image),
                    pages_on_date = 0,
                }
                entry.books[id] = b
            end
            b.pages_on_date = b.pages_on_date + n
            entry.total_pages = entry.total_pages + n
            books[id] = true
        end
    end

    -- Attach started_at / finished_at date ranges ONLY to books that already have
    -- page progress on a day; never add 0-page status/shelf books to the calendar.
    for _, r in ipairs(reads or {}) do
        if type(r) == "table" then
            local ub = object(r.user_book)
            local raw_id = r.book_id or ub.book_id or "unknown"
            local id = tostring(raw_id)
            local start = D.iso_day(r.started_at)
            local finish = D.iso_day(r.finished_at)
            if start then
                for day, entry in pairs(days) do
                    if day >= start and (not finish or day <= finish) then
                        local b = entry.books[id]
                        if b then
                            b.started_at = start
                            b.finished_at = finish
                        end
                    end
                end
            end
        end
    end

    local active, total = 0, 0
    for _, entry in pairs(days) do
        local list = {}
        for _, b in pairs(entry.books) do list[#list + 1] = b end
        table.sort(list, function(a, b) return tostring(a.book_id) < tostring(b.book_id) end)
        entry.books = list
        active = active + 1
        total = total + entry.total_pages
    end
    local count = 0
    for _ in pairs(books) do count = count + 1 end
    return { days = days, active_days = active, total_pages = total, book_count = count }
end

function M.lanes(activity, grid)
    local result = {}
    local previous = {}
    for _, day in ipairs(grid) do
        local current = {}
        local used = {}
        local entry = activity and activity.days and activity.days[day] or nil
        local day_books = entry and entry.books or {}
        for _, book in ipairs(day_books) do
            local id = tostring(book.book_id)
            local lane = previous[id]
            if lane and not used[lane] then
                current[id] = lane
                used[lane] = true
            end
        end
        for _, book in ipairs(day_books) do
            local id = tostring(book.book_id)
            if not current[id] then
                for lane = 1, 3 do
                    if not used[lane] then
                        current[id] = lane
                        used[lane] = true
                        break
                    end
                end
            end
        end
        result[day] = {
            lanes = current,
            overflow = math.max(0, #day_books - 3),
            finishes = {},
        }
        for _, book in ipairs(day_books) do
            local nextday = D.add_days(day, 1)
            local nextentry = activity and activity.days and activity.days[nextday] or nil
            local continues = false
            if nextentry and nextentry.books then
                for _, b in ipairs(nextentry.books) do
                    if tostring(b.book_id) == tostring(book.book_id) then
                        continues = true
                        break
                    end
                end
            end
            if not continues then
                result[day].finishes[#result[day].finishes + 1] = book
            end
        end
        previous = current
    end
    return result
end

function M.streak(days, today)
    local active = {}
    for day, v in pairs(days or {}) do
        if type(day) == "string" and D.valid(day) and v and (v == true or (type(v) == "table" and (v.active or (number(v.total_pages) or 0) > 0))) then
            active[day] = true
        end
    end
    local start = active[today] and today or D.add_days(today, -1)
    local current = 0
    while start and active[start] do
        current = current + 1
        start = D.add_days(start, -1)
    end
    local keys = {}
    for day in pairs(active) do keys[#keys + 1] = day end
    table.sort(keys)
    local best, run, last = 0, 0, nil
    for _, day in ipairs(keys) do
        run = (last and D.add_days(last, 1) == day) and (run + 1) or 1
        if run > best then best = run end
        last = day
    end
    return current, best
end

return M
