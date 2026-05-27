-- Canonical helper module for lark-plug-hdeck.
--
-- The larkline Lua sandbox has no `require`, so this file is the
-- single source of truth that every command (`inbox.lua`, `all.lua`,
-- `live.lua`) inlines verbatim. When you update a helper here, copy
-- the new version into every command file in the plugin.
--
-- The helpers cluster around three concerns:
--   1. talking to harness-deck (`hdeck_base`, `hd_get`)
--   2. shaping report rows for larkline (`status_icon`, `report_item`)
--   3. standard error rows (`error_item`)

-- hdeck_base — where the dashboard lives. Defaults to localhost which
-- only works for users who run `harness-deck serve` without TLS;
-- everyone with the iOS-push setup (TLS + tailnet hostname) should
-- export HARNESS_DECK_URL to their actual base URL.
local function hdeck_base()
    return lark.env("HARNESS_DECK_URL") or "http://127.0.0.1:7420"
end

-- error_item — canonical structured-error row for harness-deck failures.
-- Same shape as larkline's _shared/errors.lua; help_url points at
-- harness-deck docs so `o` jumps to the README from the failure row.
local function error_item(opts)
    return {
        label = opts.label,
        detail = opts.detail,
        icon = opts.icon or "!",
        retry_action = opts.retry_action,
        help_url = opts.help_url or "https://github.com/TaylorFinklea/harness-deck",
    }
end

-- hd_get — GET /api/<path> and decode JSON. Returns (data, nil) on
-- success or (nil, error_row) on any failure, so callers can append the
-- error directly to their items array.
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
        return nil, error_item({
            label = "HTTP " .. tostring(resp.status),
            detail = base .. path,
        })
    end
    local ok, data = pcall(lark.json.decode, resp.body)
    if not ok or not data then
        return nil, error_item({
            label = "Bad JSON from harness-deck",
            detail = base .. path,
        })
    end
    return data, nil
end

-- status_icon — the colored dot CSS class harness-deck uses for inbox
-- rows, translated to emoji. Keeps the picker visually consistent with
-- the web dashboard so muscle memory transfers in both directions.
local function status_icon(s)
    if s == "awaiting-review" then return "🟡" end
    if s == "answered" then return "🔵" end
    if s == "done" then return "🟢" end
    if s == "draft" then return "⚪" end
    return "·"
end

-- is_live — true when a report's `live.updated` is within the
-- harness-deck "live window" (60s). Mirrors the same cutoff the
-- dashboard uses for its pulsing-dot heuristic.
local function is_live(r)
    if not r.live or not r.live.updated then return false end
    local now_raw = lark.exec("date", { "+%s" })
    local now = tonumber((now_raw or ""):match("(%d+)"))
    if not now then return false end
    -- live.updated is RFC3339; convert to epoch via `date -j -f`.
    local epoch_raw = lark.exec("date", { "-j", "-f", "%Y-%m-%dT%H:%M:%SZ", r.live.updated, "+%s" })
    local epoch = tonumber((epoch_raw or ""):match("(%d+)"))
    if not epoch then return false end
    return (now - epoch) < 60
end

-- report_item — one report shaped as a larkline picker row.
-- Detail row: project · kind · open-asks (if any) · YYYY-MM-DD.
-- Primary action opens the report URL; secondary action copies it.
local function report_item(r)
    local base = hdeck_base()
    local url = base .. "/r/" .. r.project .. "/" .. r.run

    local parts = { r.project }
    if r.kind and r.kind ~= "" then parts[#parts + 1] = r.kind end
    if r.open_asks and r.open_asks > 0 then
        parts[#parts + 1] = r.open_asks .. " open"
    end
    if is_live(r) and r.live.step then
        parts[#parts + 1] = "● " .. r.live.step
    end
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

-- compare_created_desc — newest first by RFC3339 created stamp; the
-- string compare works because the timestamps share a fixed format.
local function compare_created_desc(a, b)
    return (a.created or "") > (b.created or "")
end

-- Return the helpers as a table so this file can also be read /
-- studied during development. Live commands inline the function
-- definitions above; they do NOT call into this table.
return {
    hdeck_base = hdeck_base,
    error_item = error_item,
    hd_get = hd_get,
    status_icon = status_icon,
    is_live = is_live,
    report_item = report_item,
    compare_created_desc = compare_created_desc,
}
