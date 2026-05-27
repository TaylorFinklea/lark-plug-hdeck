-- Harness Deck: All Reports — every non-archived report, newest first.
--
-- The picker's fuzzy-search becomes the navigation layer: type any
-- substring of project, title, or kind and larkline narrows down. For
-- the inbox-style "needs you" view, see inbox.lua.

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

local function compare_created_desc(a, b)
    return (a.created or "") > (b.created or "")
end

-- Plugin body -----------------------------------------------------------------

lark.register({
    on_run = function()
        local data, err = hd_get("/api/reports")
        if err then
            return { title = "harness-deck — all reports", items = { err } }
        end

        local reports = {}
        for _, r in ipairs(data.reports or {}) do
            if not r.archived then reports[#reports + 1] = r end
        end
        table.sort(reports, compare_created_desc)

        if #reports == 0 then
            return {
                title = "harness-deck — no reports",
                items = {
                    {
                        label = "No reports indexed",
                        detail = "publish a report.json or check scan_roots in config",
                        icon = "📭",
                        actions = {
                            { label = "Open dashboard", command = "open", args = { hdeck_base() } },
                        },
                    },
                },
            }
        end

        local items = {}
        for _, r in ipairs(reports) do items[#items + 1] = report_item(r) end
        return {
            title = "harness-deck — " .. #reports .. " report" .. (#reports == 1 and "" or "s"),
            items = items,
        }
    end,
})
