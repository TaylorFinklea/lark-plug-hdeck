-- Harness Deck: Inbox — reports that need you right now.
--
-- "Need you" = status awaiting-review OR at least one open ask. Same
-- filter the harness-deck dashboard's inbox view uses, so the lark
-- picker is a thin remote-control for what's already on screen there.
--
-- Helpers are inlined from lib.lua because the larkline sandbox has
-- no `require`. When updating, copy the new version from lib.lua into
-- every command file.

-- Helpers (SHARED — copy from lib.lua) --------------------------------------

local function hdeck_base()
    return lark.env("HARNESS_DECK_URL") or "http://127.0.0.1:7420"
end

local function error_item(opts)
    return {
        label = opts.label,
        detail = opts.detail,
        icon = opts.icon or "!",
        retry_action = opts.retry_action,
        help_url = opts.help_url or "https://github.com/TaylorFinklea/harness-deck",
    }
end

local function hd_get(path)
    local base = hdeck_base()
    local resp = lark.http.get(base .. path, { timeout = 5 })
    if not resp or resp.status == nil then
        return nil, error_item({
            label = "harness-deck unreachable",
            detail = base .. " — set HARNESS_DECK_URL or start `harness-deck serve`",
        })
    end
    if resp.status ~= 200 then
        return nil, error_item({ label = "HTTP " .. tostring(resp.status), detail = base .. path })
    end
    local ok, data = pcall(lark.json.decode, resp.body)
    if not ok or not data then
        return nil, error_item({ label = "Bad JSON from harness-deck", detail = base .. path })
    end
    return data, nil
end

local function status_icon(s)
    if s == "awaiting-review" then return "🟡" end
    if s == "answered" then return "🔵" end
    if s == "done" then return "🟢" end
    if s == "draft" then return "⚪" end
    return "·"
end

local function is_live(r)
    if not r.live or not r.live.updated then return false end
    local now_raw = lark.exec("date", { "+%s" })
    local now = tonumber((now_raw or ""):match("(%d+)"))
    if not now then return false end
    local epoch_raw = lark.exec("date", { "-j", "-f", "%Y-%m-%dT%H:%M:%SZ", r.live.updated, "+%s" })
    local epoch = tonumber((epoch_raw or ""):match("(%d+)"))
    if not epoch then return false end
    return (now - epoch) < 60
end

local function report_item(r)
    local base = hdeck_base()
    local url = base .. "/r/" .. r.project .. "/" .. r.run
    local parts = { r.project }
    if r.kind and r.kind ~= "" then parts[#parts + 1] = r.kind end
    if r.open_asks and r.open_asks > 0 then parts[#parts + 1] = r.open_asks .. " open" end
    if is_live(r) and r.live.step then parts[#parts + 1] = "● " .. r.live.step end
    parts[#parts + 1] = (r.created or ""):sub(1, 10)
    return {
        label = r.title or r.run,
        detail = table.concat(parts, "  ·  "),
        icon = status_icon(r.status),
        url = url,
        actions = {
            { label = "Open in browser", command = "open", args = { url } },
            { label = "Copy URL",       command = "clipboard", args = { url } },
        },
    }
end

-- Sort: items with open asks first (most urgent), then awaiting-review,
-- then by recency. Mirrors the prioritization the user is already used
-- to in the dashboard.
local function compare_inbox(a, b)
    local a_asks = (a.open_asks or 0)
    local b_asks = (b.open_asks or 0)
    if a_asks ~= b_asks then return a_asks > b_asks end
    if a.status ~= b.status then
        if a.status == "awaiting-review" then return true end
        if b.status == "awaiting-review" then return false end
    end
    return (a.created or "") > (b.created or "")
end

-- Plugin body -----------------------------------------------------------------

lark.register({
    on_run = function()
        local data, err = hd_get("/api/reports")
        if err then
            return { title = "harness-deck inbox", items = { err } }
        end

        local reports = data.reports or {}
        local needs_you = {}
        for _, r in ipairs(reports) do
            if not r.archived and (r.status == "awaiting-review" or (r.open_asks or 0) > 0) then
                needs_you[#needs_you + 1] = r
            end
        end

        if #needs_you == 0 then
            return {
                title = "harness-deck inbox — nothing needs you",
                items = {
                    {
                        label = "Inbox clear",
                        detail = "no awaiting-review reports, no open asks",
                        icon = "✓",
                        actions = {
                            { label = "Open dashboard", command = "open", args = { hdeck_base() } },
                        },
                    },
                },
            }
        end

        table.sort(needs_you, compare_inbox)

        local items = {}
        for _, r in ipairs(needs_you) do items[#items + 1] = report_item(r) end

        local open_asks_total = 0
        for _, r in ipairs(needs_you) do open_asks_total = open_asks_total + (r.open_asks or 0) end
        local title = "harness-deck inbox — " .. #needs_you .. " report"
            .. (#needs_you == 1 and "" or "s")
        if open_asks_total > 0 then
            title = title .. ", " .. open_asks_total .. " open ask"
                .. (open_asks_total == 1 and "" or "s")
        end

        return { title = title, items = items }
    end,
})
