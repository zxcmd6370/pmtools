-- Ignitools — self-contained Steam unlock plugin for Millennium.
--
-- Everything runs inside the plugin's own Lua backend:
--   * sources.lua   — source catalog (bundled + remote refresh)
--   * installer.lua — the unlock engine (download → extract → install)
--
-- The frontend (public/ignitools.js, injected into the store webkit context)
-- talks to this backend through window.Millennium.callServerMethod("ignitools",
-- "<Name>", args). Millennium dispatches those to GLOBAL Lua functions named
-- exactly "<Name>", so every RPC below must be a top-level function.

local millennium  = require("millennium")
local fs          = require("fs")
local m_utils     = require("utils")
local logger      = require("plugin_logger")
local paths       = require("paths")
local steam_utils = require("steam_utils")
local http        = require("http")
local sources     = require("sources")
local installer   = require("installer")
local titles      = require("titles")
local cloud_sync  = require("cloud_sync")

local VERSION = "2.5"

-- ── Helpers ───────────────────────────────────────────────────────────────────

local cjson = require("json")
pcall(function() cjson.encode_empty_table_as_object(false) end)

local function cjson_encode(value)
    local ok, encoded = pcall(cjson.encode, value)
    if not ok or not encoded then
        logger.warn("Pmtools: cjson encode failed: " .. tostring(encoded))
        return "{}"
    end
    return encoded
end

-- ── RPC handlers (global functions — Millennium looks these up by name) ──────

-- Ping/health check + plugin version.
function PmtoolsPing()
    return '{"ok":true,"version":"' .. VERSION .. '","sources":' .. cjson_encode(#sources.enabled()) .. '}'
end

-- ── Self-update check ────────────────────────────────────────────────────────
-- Compare the installed plugin version against the version.json served next to
-- the distribution zip on the deploy host (vercel-host/version.json). Cached
-- for a few minutes so the settings UI can poll without hammering the host.
-- Returns { ok, updateAvailable, current, latest, url } — updateAvailable is
-- false when the host is unreachable so a network blip never looks like an
-- update.
local UPDATE_URL = "https://pmtools-tools.vercel.app/version.json"
local UPDATE_TTL_SECONDS = 300
local update_cache = { at = 0, data = nil }

local function version_lt(a, b)
    -- Split "1.0.2" into numeric parts and compare lexicographically.
    local function parts(v)
        local out = {}
        for p in tostring(v):gmatch("%d+") do table.insert(out, tonumber(p)) end
        return out
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y end
    end
    return false
end

function GetPmtoolsUpdateInfo()
    local now = os.time()
    if now - update_cache.at > UPDATE_TTL_SECONDS then
        local ok, resp = pcall(http.get, UPDATE_URL, { timeout = 5 })
        if ok and resp and resp.status == 200 and resp.body then
            local ok_decode, data = pcall(cjson.decode, resp.body)
            if ok_decode and type(data) == "table" and type(data.version) == "string" then
                update_cache = { at = now, data = data }
            end
        end
    end
    local data = update_cache.data
    if not data then
        return '{"ok":true,"updateAvailable":false,"error":"unreachable"}'
    end
    local latest = data.version
    local available = version_lt(VERSION, latest)
    return cjson_encode({
        ok = true,
        updateAvailable = available,
        current = VERSION,
        latest = latest,
        url = type(data.url) == "string" and data.url or UPDATE_URL:gsub("version.json", "pmtools.zip"),
    })
end

-- Has this app been unlocked? { added: bool }
function HasPmtoolsForApp(appid)
    local added = installer.has(appid)
    return '{"added":' .. tostring(added) .. '}'
end

-- Start adding (unlocking) an app via a named source.
function StartPmtoolsAdd(appid, sourceId)
    local source = sources.get(sourceId)
    if not source then
        return '{"success":false,"error":"unknown-source"}'
    end
    local result = installer.install(appid, source)
    return cjson_encode(result)
end

-- Poll add status: { success, state: { status, error, api, manifests, installedPath } }
function GetPmtoolsAddStatus(appid)
    local state = installer.poll(appid)
    return '{"success":true,"state":' .. (state and cjson_encode(state) or "null") .. '}'
end

-- Cancel an in-flight add (kills the temp download; no-op if already done).
function CancelPmtoolsAdd(appid)
    local state = installer.get_state(appid)
    if state and (state.status == "downloading" or state.status == "extracting") then
        installer.cancel(appid)
        return '{"success":true,"cancelled":true}'
    end
    return '{"success":true,"cancelled":false}'
end

-- Remove the unlock for an app.
function DeletePmtoolsForApp(appid)
    local result = installer.remove(appid)
    return cjson_encode(result)
end

-- Restart Steam (detached, so the backend survives the kill).
function RestartSteam()
    local result = installer.restart_steam()
    return cjson_encode(result)
end

-- List enabled sources for the settings UI.
function GetPmtoolsSources()
    local out = {}
    for _, s in ipairs(sources.enabled()) do
        table.insert(out, { id = s.id, name = s.name, kind = s.kind })
    end
    return cjson_encode({ success = true, sources = out })
end

-- Per-source availability for an appid (lightweight ranged probe), so the Add
-- popup can show which sources actually have the game before the user picks.
function GetPmtoolsSourceAvailability(appid)
    local out = sources.check_availability(appid)
    return cjson_encode({ success = true, appid = tostring(appid), sources = out })
end

-- Account-wide usage/limits for ALL sources (no appid needed) — for the
-- settings UI, e.g. Hubcap's remaining daily downloads and key expiry. Every
-- source is returned (not just enabled ones) with its `enabled` flag so the
-- UI can render the per-source toggle and re-enable a disabled source.
function GetPmtoolsSourceUsage()
    local out = {}
    for _, s in ipairs(sources.list()) do
        local enabled = s.enabled ~= false
        local usage = (enabled or sources.key_gated(s)) and sources.check_usage(s) or nil
        table.insert(out, {
            id = s.id,
            name = s.name,
            kind = s.kind,
            enabled = enabled,
            usage = usage, -- always fetch for key-gated so the UI can show key status
            keyGated = sources.key_gated(s), -- has an api_key= placeholder (e.g. Hubcap)
            hasKey = sources.has_key(s),     -- key-gated and a key is actually set
            keyInvalid = sources.is_key_invalid and sources.is_key_invalid(s) or false,
            health = sources.health_of(s.id),
        })
    end
    return cjson_encode({ success = true, sources = out })
end

-- Enable/disable a source at runtime. Persists the toggle to
-- backend/sources.local.json (partial override — just {id, enabled}) and
-- reloads the catalog, so the change applies to the next manifest fetch /
-- availability check without a Steam restart.
-- NB: Millennium's server bridge forwards only ONE scalar arg per call, so
-- the frontend sends a JSON string payload (same convention as
-- SaveIgnitoolsTitles) and this decodes it.
function SetPmtoolsSourceEnabled(payload)
    local id, enabled
    if type(payload) == "table" and payload.payload and not payload.id then
        payload = payload.payload
    end
    if type(payload) == "string" and payload ~= "" then
        local ok, decoded = pcall(cjson.decode, payload)
        if ok and type(decoded) == "table" then
            id = decoded.id
            enabled = decoded.enabled
        end
    elseif type(payload) == "table" then
        -- CLI / tests / direct bridge pass a plain table.
        id = payload.id
        enabled = payload.enabled
    end
    local ok, err = sources.set_enabled(id, enabled == true or enabled == "true")
    if not ok then
        return cjson_encode({ success = false, error = err or "bad-payload" })
    end
    sources.invalidate_caches()
    logger.log("Pmtools: source " .. tostring(id) .. " set enabled=" .. tostring(enabled == true or enabled == "true"))
    return '{"success":true}'
end

-- The frontend sends appids as a comma-joined string: Millennium's server
-- bridge forwards only scalar args (arrays arrive as nil), so this splits the
-- string into a list. A plain table (CLI, tests) passes through untouched.
local function parse_appid_list(arg)
    if type(arg) == "table" then return arg end
    local out = {}
    if type(arg) == "string" then
        for id in arg:gmatch("[^,]+%s*") do
            local trimmed = id:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then table.insert(out, trimmed) end
        end
    end
    return out
end

-- Backend-managed title names for a list of appids. PURE CACHE READ — this
-- never hits Steam, so it returns instantly even for a large library. Appids
-- without a cached name are listed in `missing`; the frontend shows the appid
-- itself for those.
-- cjson encodes an empty Lua table as {} (object) — but the frontend needs an
-- ARRAY for `missing`. Force a JSON array.
local function as_json_array(t)
    local n = #(t or {})
    if n == 0 then return "[]" end
    return cjson_encode(t)
end

function GetPmtoolsTitles(appids)
    local result = titles.cached(parse_appid_list(appids))
    return '{' ..
        '"success":true,' ..
        '"titles":' .. cjson_encode(result.titles) .. ',' ..
        '"pending":' .. tostring(result.pending or 0) .. ',' ..
        '"missing":' .. as_json_array(result.missing) .. '}'
end

-- Store names the frontend fetched itself (parallel direct Steam requests)
-- so the backend cache stays warm across sessions. Payload is a JSON string
-- (Millennium only forwards scalar args, so the UI must send it as a string;
-- a plain table is accepted for CLI/tests) that is either
--   * a plain map:           { [appid] = name }
--   * a structured payload:  { names = { [appid] = name }, failed = { appid, ... } }
-- where `failed` lists appids Steam definitively 404s on (kept out of
-- `missing` so they aren't re-requested every boot).
function SavePmtoolsTitles(payload)
    local names = {}
    local failed = {}
    if type(payload) == "table" then
        if type(payload.names) == "table" then
            names = payload.names
            failed = payload.failed or {}
        else
            names = payload
        end
    elseif type(payload) == "string" and payload ~= "" then
        local ok, decoded = pcall(cjson.decode, payload)
        if ok and type(decoded) == "table" then
            if type(decoded.names) == "table" then
                names = decoded.names
                failed = decoded.failed or {}
            else
                names = decoded
            end
        end
    end
    local saved = titles.save_results(names, failed)
    return cjson_encode({ success = true, saved = saved })
end

-- Forget failed lookups for the given appids — the "Refresh titles" button
-- in the unlocked-games page. Clear-only: no refetch, no Steam calls.
function RefreshPmtoolsTitles(appids)
    local result = titles.refresh(parse_appid_list(appids))
    return '{' ..
        '"success":true,' ..
        '"titles":' .. cjson_encode(result.titles) .. ',' ..
        '"pending":' .. tostring(result.pending or 0) .. ',' ..
        '"missing":' .. as_json_array(result.missing) .. '}'
end

-- List every installed unlock: scan config/stplug-in/*.lua (and *.lua.disabled).
function ListPmtoolsInstalled()
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then
        return '{"success":false,"error":"no-steam-path"}'
    end
    local dir = fs.join(base, "config", "stplug-in")
    local out = {}
    local ok, files = pcall(fs.list_recursive, dir)
    if ok and files then
        for _, e in ipairs(files) do
            -- NB: no quantified capture groups here — `(x)?` after a capture is
            -- unsupported in this Lua runtime and silently fails to match.
            -- Strip any directory prefix to handle both "12345.lua" and
            -- "stplug-in/12345.lua" from fs.list_recursive.
            local name = e.name or ""
            local basename = name:match("([^/\\]+)$") or name
            local appid = basename:match("^(%d+)%.lua$")
            local disabled = false
            if not appid then
                appid = basename:match("^(%d+)%.lua%.disabled$")
                disabled = appid ~= nil
            end
            if appid then
                table.insert(out, {
                    appid = appid,
                    disabled = disabled,
                    installedAt = installer.installed_at(appid) or 0,
                })
            end
        end
    end
    -- Backfill metadata for games installed before the meta feature.
    -- Use appid as a heuristic: higher appid = newer game.
    local maxId = 0
    for _, g in ipairs(out) do
        local n = tonumber(g.appid) or 0
        if n > maxId then maxId = n end
    end
    local needsSave = false
    for _, g in ipairs(out) do
        if g.installedAt == 0 then
            g.installedAt = tonumber(g.appid) or 0
            needsSave = true
        end
    end
    if needsSave then
        installer.backfill_meta(out)
    end
    table.sort(out, function(a, b) return tonumber(a.appid) < tonumber(b.appid) end)
    return cjson_encode({ success = true, apps = out })
end

-- Clear the temp download folder (cached zips / extraction leftovers).
function ClearPmtoolsTemp()
    local dir = paths.backend_path("temp_dl")
    local removed = 0
    local ok, files = pcall(fs.list_recursive, dir)
    if ok and files then
        for _, e in ipairs(files) do
            if e.path and e.path ~= dir then
                local ok_rm = pcall(fs.remove_all, e.path)
                if ok_rm then removed = removed + 1 end
            end
        end
    end
    return cjson_encode({ success = true, removed = removed })
end

-- Tail the plugin's activity log for the Settings viewer.
function GetPmtoolsLog(lines)
    local n = tonumber(lines) or 60
    local log_file = fs.join(fs.join(paths.get_plugin_dir(), "..", ".."), "logs", "pmtools_log.log")
    local ok, content = pcall(m_utils.read_file, log_file)
    if not ok or not content then
        return '{"success":false,"error":"no-log"}'
    end
    -- split into lines, drop CR, keep the last n
    local lines_out = {}
    for line in content:gmatch("([^\r\n]*)\r?\n?") do
        if line ~= "" then table.insert(lines_out, line) end
    end
    local start = math.max(1, #lines_out - n + 1)
    local out = {}
    for i = start, #lines_out do table.insert(out, lines_out[i]) end
    return cjson_encode({ success = true, lines = out })
end

-- Persist a UI setting (theme / language) via Millennium's config store.
function SetIgnitoolsSetting(key, value)
    if type(key) ~= "string" or key == "" then
        return '{"success":false,"error":"bad-key"}'
    end
    millennium.config.set("pmtools." .. key, value)
    return '{"success":true}'
end

function GetPmtoolsSettings()
    -- millennium.config.get_all() returns this plugin's own config table (keys
    -- stored with the "ignitools." prefix), NOT a global map — so index it
    -- directly and strip the prefix so the frontend sees plain keys.
    local all = millennium.config.get_all() or {}
    local out = {}
    for k, v in pairs(all) do
        local short = tostring(k):gsub("^pmtools%.", "")
        out[short] = v
    end
    return cjson_encode({ success = true, settings = out })
end

-- Update the Hubcap API key at runtime. Persists to backend/secrets.local.json
-- (gitignored) and reloads the source catalog so the new key is used by the
-- next manifest fetch / usage check — no Steam restart needed.
function SetPmtoolsHubcapKey(key)
    if type(key) == "table" then
        key = key.key or key.payload or key[1] or ""
    end
    if type(key) ~= "string" then
        return '{"success":false,"error":"bad-key"}'
    end
    key = key:match("^%s*(.-)%s*$") -- trim surrounding whitespace
    if key == "" then
        return '{"success":false,"error":"empty-key"}'
    end
    local secrets_path = paths.backend_path("secrets.local.json")
    local secrets = {}
    local ok_read, content = pcall(m_utils.read_file, secrets_path)
    if ok_read and content and content ~= "" then
        local ok_decode, existing = pcall(cjson.decode, content)
        if ok_decode and type(existing) == "table" then secrets = existing end
    end
    secrets.hubcapKey = key
    local ok_write = pcall(m_utils.write_file, secrets_path, cjson.encode(secrets))
    if not ok_write then
        logger.warn("Pmtools: failed to persist secrets.local.json")
        return '{"success":false,"error":"write-failed"}'
    end
    pcall(m_utils.write_file, "C:/Program Files (x86)/Steam/Pmtools/secrets.local.json", cjson.encode(secrets))
    sources.reload()
    -- Drop cached usage/availability so the UI re-fetches with the new key
    -- instead of serving a stale (possibly failed) result for the TTL.
    sources.invalidate_caches()
    logger.log("Pmtools: Hubcap API key updated")
    return '{"success":true}'
end

-- the source list immediately at Steam startup instead of waiting for the
-- first menu-open fetch.
local function preload_sources()
    local ok, err = pcall(sources.reload)
    if not ok then
        logger.warn("Pmtools: startup source preload failed: " .. tostring(err))
    end
end

preload_sources()

-- The loader resolves "manifest request codes" (MCRs) through the Lua
-- functions fetch_manifest_code / fetch_manifest_code_ex before falling back
-- to the [manifest] url in ignitools.toml. Ship manifest.lua into
-- config/stplug-in so Steam can always fetch the CURRENT depot manifest for a
-- game whose cached manifest is stale (otherwise the download fails with a
-- "network connection error" / Access Denied on the manifest request code).
local function ensure_manifest_lua()
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then return end
    local dest = fs.join(base, "config", "stplug-in", "manifest.lua")
    local src = paths.backend_path("manifest.lua")
    if not fs.exists(src) then return end -- very old deploy without the bundled resolver
    local ok, content = pcall(m_utils.read_file, src)
    if not ok or not content then return end
    -- Refresh when the content differs, not only when missing: a stale
    -- installed resolver (e.g. a slow provider order) otherwise survives
    -- every plugin update.
    local ok_d, current = pcall(m_utils.read_file, dest)
    if ok_d and current == content then return end
    if pcall(m_utils.write_file, dest, content) then
        logger.log("Pmtools: installed/updated manifest.lua (MCR resolver) into config/stplug-in")
    end
end

function SelfUpdatePmtools()
    local is_windows = os.getenv("OS") == "Windows_NT"
    if not is_windows then return cjson_encode({ ok = false, error = "windows-only" }) end

    -- 1. Check for update
    local updateData = nil
    local ok_u, uResp = pcall(http.get, UPDATE_URL, { timeout = 10 })
    if ok_u and uResp and uResp.status == 200 and uResp.body then
        local ok_d, d = pcall(cjson.decode, uResp.body)
        if ok_d and type(d) == "table" then updateData = d end
    end
    if not updateData or not updateData.version then
        return cjson_encode({ ok = false, error = "cannot-check-update" })
    end
    if not version_lt(VERSION, updateData.version) then
        return cjson_encode({ ok = false, error = "already-latest" })
    end

    -- 2. Download install-plugin.ps1 and run it via schtasks.
    --    schtasks creates a process completely independent of Steam's job
    --    object, so it survives Steam being killed during the update.
    local installUrl = UPDATE_URL:gsub("version.json", "install-plugin.ps1")
    local tempBase = paths.backend_path("temp_dl")
    pcall(fs.create_directories, tempBase)
    local psFile = fs.join(tempBase, "_self_update.ps1")
    local ok_dl, dlResp = pcall(http.get, installUrl, { timeout = 30 })
    if not ok_dl or not dlResp or dlResp.status ~= 200 or not dlResp.body then
        return cjson_encode({ ok = false, error = "download-installer-failed" })
    end
    pcall(m_utils.write_file, psFile, dlResp.body)

    -- Write .cmd launcher to %TEMP% (no spaces in path, required by schtasks).
    local tempDir = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
    local base = steam_utils.detect_steam_install_path()
    local baseWin = (base or ""):gsub("/", "\\")
    local psWin = psFile:gsub("/", "\\")
    local cmdFile = tempDir .. "\\pmtools_update.cmd"
    local batFile = tempDir .. "\\pmtools_run_update.bat"
    local taskName = "PmtoolsUpdate"
    local cmdContent = '@echo off\r\npowershell -NoProfile -ExecutionPolicy Bypass -File "' .. psWin .. '" -Force -SteamPath "' .. baseWin .. '"\r\nschtasks /delete /tn "' .. taskName .. '" /f >nul 2>&1\r\n'
    pcall(m_utils.write_file, cmdFile, cmdContent)
    -- Write .bat that creates and runs the scheduled task
    local batContent = '@echo off\r\nschtasks /create /tn "' .. taskName .. '" /tr "' .. cmdFile .. '" /sc once /st 00:00 /f\r\nschtasks /run /tn "' .. taskName .. '"\r\n'
    pcall(m_utils.write_file, batFile, batContent)
    os.execute('cmd /c "' .. batFile .. '"')

    logger.log("Pmtools: self-update started via schtasks")
    return cjson_encode({ ok = true, version = updateData.version })
end

-- ── Backup / Restore ────────────────────────────────────────────────────────

-- Export all unlocked games as a JSON array of appid strings.
function ExportPmtoolsGames()
    local res = cjson.decode(ListPmtoolsInstalled())
    if not res or not res.success then
        return cjson_encode({ ok = false, error = "cannot-list" })
    end
    local list = {}
    for _, g in ipairs(res.apps or {}) do
        table.insert(list, g.appid)
    end
    return cjson_encode({ ok = true, games = list, count = #list })
end

-- Import a JSON array of appid strings. Returns how many were new.
function ImportIgnitoolsGames(appids)
    local incoming = {}
    if type(appids) == "string" then
        local ok, decoded = pcall(cjson.decode, appids)
        if ok and type(decoded) == "table" then incoming = decoded end
    elseif type(appids) == "table" then
        incoming = appids
    end
    if #incoming == 0 then
        return cjson_encode({ ok = false, error = "no-games" })
    end
    -- Filter to only games not already installed
    local existing = {}
    local listRes = cjson.decode(ListPmtoolsInstalled())
    if listRes and listRes.success and listRes.apps then
        for _, g in ipairs(listRes.apps) do existing[g.appid] = true end
    end
    local newGames = {}
    for _, id in ipairs(incoming) do
        local sid = tostring(id)
        if not existing[sid] then table.insert(newGames, sid) end
    end
    return cjson_encode({ ok = true, imported = #newGames, skipped = #incoming - #newGames, games = newGames })
end

-- ── Bulk Operations ──────────────────────────────────────────────────────────

-- Remove multiple games at once. Accepts a JSON array of appid strings.
function BulkRemovePmtoolsGames(appids)
    local list = {}
    if type(appids) == "string" then
        local ok, decoded = pcall(cjson.decode, appids)
        if ok and type(decoded) == "table" then list = decoded end
    elseif type(appids) == "table" then
        list = appids
    end
    local removed = 0
    local failed = 0
    for _, id in ipairs(list) do
        local sid = tostring(id)
        local ok_rm = pcall(installer.remove, sid)
        if ok_rm then removed = removed + 1 else failed = failed + 1 end
    end
    return cjson_encode({ ok = true, removed = removed, failed = failed })
end

-- ── Cloud Vault (BYOS) ───────────────────────────────────────────────────────

function GetPmtoolsCloudConfig()
    local cfg = cloud_sync.get_config()
    return cjson_encode({ success = true, config = cfg })
end

function SetPmtoolsCloudConfig(payload)
    local data = payload
    if type(payload) == "string" and payload ~= "" then
        local ok, decoded = pcall(cjson.decode, payload)
        if ok and type(decoded) == "table" then data = decoded end
    end
    local ok, err = cloud_sync.set_config(data)
    if not ok then
        return cjson_encode({ success = false, error = err or "save-failed" })
    end
    return '{"success":true}'
end

function TestPmtoolsCloudConnection()
    local res = cloud_sync.dispatch_task("test_connection")
    return cjson_encode(res)
end

function BackupPmtoolsGame(payload)
    local data = {}
    if type(payload) == "string" and payload ~= "" then
        local ok, decoded = pcall(cjson.decode, payload)
        if ok and type(decoded) == "table" then data = decoded else data.appid = payload end
    elseif type(payload) == "table" then
        data = payload
    else
        data.appid = tostring(payload)
    end
    local res = cloud_sync.dispatch_task("backup_game", data)
    return cjson_encode(res)
end

function RestorePmtoolsGame(payload)
    local data = {}
    if type(payload) == "string" and payload ~= "" then
        local ok, decoded = pcall(cjson.decode, payload)
        if ok and type(decoded) == "table" then data = decoded else data.appid = payload end
    elseif type(payload) == "table" then
        data = payload
    else
        data.appid = tostring(payload)
    end
    local res = cloud_sync.dispatch_task("restore_game", data)
    return cjson_encode(res)
end

function BackupAllPmtoolsVault()
    local res = cloud_sync.dispatch_task("backup_all")
    return cjson_encode(res)
end

function RestoreAllPmtoolsVault()
    local res = cloud_sync.dispatch_task("restore_all")
    return cjson_encode(res)
end

function GetPmtoolsCloudTaskStatus(taskId)
    local res = cloud_sync.get_task_status(tostring(taskId or ""))
    return cjson_encode(res)
end

function GetPmtoolsCloudStatusMap()
    local map = cloud_sync.get_status_map()
    return cjson_encode({ success = true, map = map })
end

local function on_load()
    logger.log("Pmtools loading (millennium " .. tostring(millennium.version()) .. ", v" .. VERSION .. ")")
    preload_sources()
    ensure_manifest_lua()
    millennium.ready()
end

local function on_unload()
    logger.log("Pmtools unloading")
end

return {
    on_load   = on_load,
    on_unload = on_unload,
}
