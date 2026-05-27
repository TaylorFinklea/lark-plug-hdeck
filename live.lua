-- Harness Deck: In Flight — reports whose live telemetry says they're
-- actively running (live.updated within the last 60 seconds).
--
-- Use case: you've kicked off a few long-running agents and want to
-- glance at "what's happening right now" without opening the dashboard.
-- Fuzzy-search this list to jump to the one you want to watch.

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

-- live_item — variant of report_item that leads with the live step
-- (what's happening *right now*) instead of the project name. The
-- detail row shows step · elapsed · tokens · cost so the picker
-- doubles as a status pane.
local function live_item(r)
    local base = hdeck_base()
    local url = base .. "/r/" .. r.project .. "/" .. r.run
    local parts = {}
    if r.live and r.live.step then parts[#parts + 1] = "● " .. r.live.step end
    parts[#parts + 1] = r.project
    if r.live and r.live.tokens then parts[#parts + 1] = tostring(r.live.tokens) .. " tok" end
    if r.live and r.live.cost_usd and r.live.cost_usd ~= "" then
        parts[#parts + 1] = "$" .. r.live.cost_usd
    end
    return {
        label = r.title or r.run,
        detail = table.concat(parts, "  ·  "),
        icon = "🟢",
        url = url,
        actions = {
            { label = "Open in browser", command = "open", args = { url } },
            { label = "Copy URL",       command = "clipboard", args = { url } },
        },
    }
end

-- Plugin body -----------------------------------------------------------------

lark.register({
    on_run = function()
        local data, err = hd_get("/api/reports")
        if err then
            return { title = "harness-deck — in flight", items = { err } }
        end

        local in_flight = {}
        for _, r in ipairs(data.reports or {}) do
            if not r.archived and is_live(r) then in_flight[#in_flight + 1] = r end
        end

        if #in_flight == 0 then
            return {
                title = "harness-deck — nothing in flight",
                items = {
                    {
                        label = "No live reports",
                        detail = "publish to `live.updated` within the last 60s to appear here",
                        icon = "💤",
                        actions = {
                            { label = "Open dashboard", command = "open", args = { hdeck_base() } },
                        },
                    },
                },
            }
        end

        local items = {}
        for _, r in ipairs(in_flight) do items[#items + 1] = live_item(r) end
        return {
            title = "harness-deck — " .. #in_flight .. " in flight",
            items = items,
        }
    end,
})
