local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("json")
local socketutil = require("socketutil")
local logger = require("logger")
local C = require("hcd.constants")

local M = {}

-- KOReader's rapidjson decodes JSON null as json.null (a truthy function).
-- Recursively strip all null sentinels so downstream Lua code sees real nil.
local function strip_nulls(value)
    if value == nil or value == json.null or type(value) == "function" or type(value) == "userdata" then
        return nil
    end
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        local cleaned = strip_nulls(v)
        if cleaned ~= nil then
            out[k] = cleaned
        end
    end
    return out
end

M.strip_nulls = strip_nulls

local function request(token, query, variables)
    local body = json.encode({ query = query, variables = variables or {} })
    local chunks = {}
    local req = {
        url = C.API_URL,
        method = "POST",
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(chunks),
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#body),
            ["Authorization"] = "Bearer " .. token,
            ["User-Agent"] = C.USER_AGENT,
        },
    }
    socketutil:set_timeout(10, 30)
    local ok, res, code = pcall(https.request, req)
    socketutil:reset_timeout()

    if not ok or not res then
        logger.warn("HardcoverDashboard: HTTP request failed", ok, res, code)
        return nil, "Connection timed out or failed. Try again online."
    end

    local raw = table.concat(chunks)
    local status = tonumber(code)
    if status == 401 then
        return nil, "Your Hardcover token is invalid or expired. Set a new API token."
    end
    if status == 403 then
        local scope = raw:match("insufficient_scope[^%w:]+([%w:]+)") or raw:match("required.scope[^%w:]+([%w:]+)")
        return nil, "Token is missing a read scope" .. (scope and (": " .. scope) or "") .. "."
    end
    if status == 429 then
        return nil, "Hardcover rate limit reached. Try again in a moment."
    end
    if status ~= 200 then
        logger.warn("HardcoverDashboard: unexpected HTTP status", code, raw:sub(1, 200))
        return nil, "Hardcover returned HTTP " .. tostring(code) .. "."
    end

    local decoded_ok, parsed = pcall(json.decode, raw)
    if not decoded_ok or type(parsed) ~= "table" then
        logger.warn("HardcoverDashboard: JSON decode failed")
        return nil, "Hardcover returned an unreadable response."
    end

    parsed = strip_nulls(parsed)
    if parsed.errors and #parsed.errors > 0 then
        local e = parsed.errors[1]
        local msg = type(e) == "table" and (e.message or "GraphQL error") or tostring(e)
        logger.warn("HardcoverDashboard: GraphQL error", msg)
        return nil, "Hardcover: " .. tostring(msg)
    end
    return parsed.data, nil
end

M.request = request

function M.profile(token)
    local data, err = request(token, "query { me { id username name timezone } }")
    return data and data.me and data.me[1] or nil, err
end

function M.goals(token, user_id)
    local q = [[query($userId: Int!) {
        goals(where: {user_id: {_eq: $userId}, archived: {_eq: false}}, order_by: {end_date: desc}) {
            id metric goal progress description start_date end_date state completed_at conditions archived
        }
    }]]
    local data, err = request(token, q, { userId = user_id })
    return data and data.goals or nil, err
end

function M.reading(token, user_id)
    local q = [[query($userId: Int!) {
        user_books(where: {user_id: {_eq: $userId}, status_id: {_eq: 2}}, order_by: {updated_at: desc_nulls_last}, limit: 50) {
            id book_id edition_id status_id updated_at
            book { id title pages audio_seconds cached_image cached_contributors }
            edition { id title pages audio_seconds reading_format_id cached_image }
            user_book_reads(order_by: {id: desc}) {
                id started_at finished_at paused_at progress progress_pages progress_seconds edition_id
                edition { id pages audio_seconds reading_format_id cached_image }
            }
        }
    }]]
    local data, err = request(token, q, { userId = user_id })
    return data and data.user_books or nil, err
end

function M.journals(token, user_id, start_at, end_at)
    local q = [[query($userId: Int!, $start: timestamptz!, $end: timestamptz!, $offset: Int!) {
        reading_journals(
            where: {
                user_id: {_eq: $userId},
                action_at: {_gte: $start, _lt: $end},
                event: {_in: ["progress_updated", "user_book_read_started", "user_book_read_finished", "status_currently_reading", "status_read"]}
            },
            order_by: [{action_at: asc}, {id: asc}],
            limit: 100,
            offset: $offset
        ) {
            id book_id edition_id event action_at journal_date metadata
            book { id title pages cached_image cached_contributors }
            edition { id pages reading_format_id cached_image }
        }
    }]]
    local rows = {}
    for page = 0, C.MAX_JOURNAL_PAGES - 1 do
        local data, err = request(token, q, {
            userId = user_id,
            start = start_at,
            ["end"] = end_at,
            offset = page * 100,
        })
        if not data then return nil, err end
        local batch = data.reading_journals or {}
        for _, row in ipairs(batch) do rows[#rows + 1] = row end
        if #batch < 100 then break end
    end
    return rows
end

function M.month_reads(token, user_id, month_start)
    local q = [[query($userId: Int!, $start: date!) {
        user_book_reads(
            where: {
                user_book: {user_id: {_eq: $userId}},
                _or: [{finished_at: {_is_null: true}}, {finished_at: {_gte: $start}}, {started_at: {_gte: $start}}]
            },
            limit: 200
        ) {
            id started_at finished_at
            edition { id cached_image }
            user_book { book_id book { id title cached_image cached_contributors } }
        }
    }]]
    local data, err = request(token, q, { userId = user_id, start = month_start })
    return data and data.user_book_reads or nil, err
end

function M.streak_days(token, user_id)
    local q = [[query($userId: Int!, $offset: Int!) {
        reading_journals(
            where: {
                user_id: {_eq: $userId},
                event: {_eq: "progress_updated"}
            },
            order_by: [{action_at: desc}, {id: desc}],
            limit: 100,
            offset: $offset
        ) { action_at journal_date event }
    }]]
    local days = {}
    for page = 0, C.MAX_STREAK_PAGES - 1 do
        local data, err = request(token, q, { userId = user_id, offset = page * 100 })
        if not data then return nil, err end
        local rows = data.reading_journals or {}
        for _, r in ipairs(rows) do
            local day = (type(r.journal_date) == "string" and r.journal_date:match("^%d%d%d%d%-%d%d%-%d%d"))
                or (type(r.action_at) == "string" and r.action_at:match("^%d%d%d%d%-%d%d%-%d%d"))
            if day then
                days[day] = { active = true }
            end
        end
        if #rows < 100 then break end
    end
    return days
end

return M
