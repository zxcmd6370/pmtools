-- Ignitools source catalog.
--
-- A "source" is where depot manifests for an appid come from. Two kinds:
--   * AppIdZip  — a URL template with a {appid} placeholder that points at a
--                 zip containing {appid}.lua + *.manifest files.
--   * LuaFolder — a GitHub browse source (owner/repo/branch/path) hosting the
--                 same payload as loose files.
--
-- The catalog ships bundled (sources.json, loaded at boot). If a refresh URL
-- is configured it is fetched once at boot and merged over the bundle, so the
-- list can be updated without a plugin update. A plugin-local override file
-- (backend/sources.local.json) wins over everything — useful for private hosts.

local fs     = require("fs")
local http   = require("http")
local m_util = require("utils")
local logger = require("plugin_logger")
local paths  = require("paths")
local cjson  = require("json")
local spawn  = require("spawn")

local sources = {}

-- ── Bundled catalog ───────────────────────────────────────────────────────────

local DEFAULT_CATALOG = {
    version = 2,
    sources = {
        {
            id = "hubcap",
            name = "Hubcap",
            kind = "AppIdZip",
            urlTemplate = "https://hubcapmanifest.com/api/v1/manifest/{appid}?api_key=",
            availabilityUrl = "https://hubcapmanifest.com/api/v1/status/{appid}",
            usageUrl = "https://hubcapmanifest.com/api/v1/user/stats?api_key=",
            usageFields = { used = "daily_usage", limit = "daily_limit", expires = "api_key_expires_at" },
            enabled = false, -- visible to users, but requires a local API key in backend/secrets.local.json
        },
        {
            id = "ignihub",
            name = "Ignihub",
            kind = "AppIdZip",
            urlTemplate = "https://ignihub.vercel.app/api/manifest-file?appid={appid}",
            availabilityUrl = "",
            usageUrl = "https://ignihub.vercel.app/api/usage",
            usageFields = { remaining = "remaining", limit = "limit", expires = "resetAt" },
            enabled = true,
        },
        {
            id = "sushi",
            name = "Sushi",
            kind = "AppIdZip",
            urlTemplate = "https://raw.githubusercontent.com/sushi-dev55-alt/sushitools-games-repo-alt/refs/heads/main/{appid}.zip",
            enabled = true,
        },
        {
            id = "luagen",
            name = "LuaGen",
            kind = "AppIdZip",
            urlTemplate = "https://api.luagen.revobd.club/{appid}.zip",
            enabled = true,
        },
        {
            id = "ryuu",
            name = "Ryuu",
            kind = "AppIdZip",
            urlTemplate = "http://167.235.229.108/{appid}",
            enabled = true,
        },
    },
}

-- Optional: refresh the catalog from a remote JSON list at boot.
local REFRESH_URL = ""

-- ── Catalog storage ───────────────────────────────────────────────────────────

local loaded = nil

local function validate_entry(entry)
    if type(entry) ~= "table" or type(entry.id) ~= "string" or entry.id == "" then
        return false
    end
    if entry.kind == "AppIdZip" then
        return type(entry.urlTemplate) == "string" and entry.urlTemplate ~= ""
    end
    if entry.kind == "LuaFolder" then
        return type(entry.owner) == "string" and type(entry.repo) == "string"
    end
    return false
end

local function merge_catalog(entries)
    local merged = {}
    local seen = {}
    local function add(entry)
        if validate_entry(entry) and not seen[entry.id] then
            seen[entry.id] = true
            table.insert(merged, entry)
        end
    end

    -- bundle first (lowest priority), then refresh, then local override.
    for _, e in ipairs(DEFAULT_CATALOG.sources) do add(e) end
    for _, e in ipairs(entries or {}) do add(e) end
    return merged
end

local function read_json_file(path)
    local ok, content = pcall(m_util.read_file, path)
    if not ok or not content or content == "" then return nil end
    local ok_decode, value = pcall(cjson.decode, content)
    if not ok_decode then
        logger.warn("Pmtools: failed to parse " .. path .. ": " .. tostring(value))
        return nil
    end
    return value
end

local function fetch_remote_catalog()
    if REFRESH_URL == "" then return {} end
    local response, err = http.get(REFRESH_URL, { timeout = 10 })
    if not response then
        logger.warn("Pmtools: source catalog refresh failed: " .. tostring(err))
        return {}
    end
    if response.status ~= 200 then
        logger.warn("Pmtools: source catalog refresh returned status " .. tostring(response.status))
        return {}
    end
    local ok, data = pcall(cjson.decode, response.body)
    if not ok or type(data) ~= "table" then return {} end
    return data.sources or {}
end

-- API keys (e.g. Hubcap) live in backend/secrets.local.json, which is
-- gitignored — never commit keys into the catalog files. When a source's
-- urlTemplate/usageUrl carry an `api_key=` placeholder, the key is injected
-- at reload time, so the shipped catalog stays key-free. Re-reading the file
-- on every reload lets the key be updated at runtime (SetIgnitoolsHubcapKey)
-- without a Steam restart.
local hubcap_key = ""

local function load_secrets()
    local secrets = read_json_file(paths.backend_path("secrets.local.json")) or {}
    hubcap_key = secrets.hubcapKey or ""
    if hubcap_key == "" then
        local steam_secrets = read_json_file("C:/Program Files (x86)/Steam/Pmtools/secrets.local.json")
        if steam_secrets and steam_secrets.hubcapKey then
            hubcap_key = steam_secrets.hubcapKey
        end
    end
end

function sources.reload()
    load_secrets()
    local remote = fetch_remote_catalog()
    local local_override = read_json_file(paths.backend_path("sources.local.json"))
    local override_entries = {}
    if local_override and type(local_override.sources) == "table" then
        override_entries = local_override.sources
    end
    loaded = merge_catalog(remote)
    -- local override: replace entries by id, keeping order from the merged list,
    -- and append any ids the bundle/refresh didn't ship (private sources).
    -- Partial entries that only carry `enabled` (a toggle persisted by
    -- SetIgnitoolsSourceEnabled) are applied as field overrides instead of
    -- full replacements — so a bundled source can be disabled without the
    -- override having to duplicate its whole definition.
    local by_id = {}
    local enabled_flags = {}
    for _, e in ipairs(override_entries) do
        if validate_entry(e) then
            by_id[e.id] = e
        elseif type(e) == "table" and type(e.id) == "string" and e.id ~= "" and e.enabled ~= nil then
            enabled_flags[e.id] = e.enabled == true
        end
    end
    for i, e in ipairs(loaded) do
        if by_id[e.id] then
            loaded[i] = by_id[e.id]
            by_id[e.id] = nil
        elseif enabled_flags[e.id] ~= nil then
            e.enabled = enabled_flags[e.id]
        end
    end
    for _, e in ipairs(override_entries) do
        if validate_entry(e) and by_id[e.id] then
            table.insert(loaded, e)
        end
    end
    -- Inject API keys (e.g. Hubcap) from secrets into any api_key= placeholder
    -- AFTER the override pass, so the keyless catalog entries get their key.
    if hubcap_key ~= "" then
        for _, e in ipairs(loaded) do
            if e.urlTemplate and e.urlTemplate:find("api_key=", 1, true) then
                e.urlTemplate = e.urlTemplate:gsub("api_key=[^&]*", "api_key=" .. hubcap_key)
            end
            if e.usageUrl and e.usageUrl:find("api_key=", 1, true) then
                e.usageUrl = e.usageUrl:gsub("api_key=[^&]*", "api_key=" .. hubcap_key)
            end
        end
    end
    logger.log("Pmtools: catalog loaded with " .. tostring(#loaded) .. " sources")
end

function sources.list()
    if not loaded then sources.reload() end
    return loaded
end

function sources.enabled()
    local out = {}
    for _, s in ipairs(sources.list()) do
        if s.enabled ~= false then table.insert(out, s) end
    end
    return out
end

-- Persist an enable/disable toggle for a source into sources.local.json and
-- reload. The persisted entry only carries `id` + `enabled` — the reload's
-- partial-override pass applies it over the bundled/full definition, so a
-- bundled source (e.g. Sushi) can be toggled without duplicating its config.
-- Returns (true) or (false, error).
function sources.set_enabled(id, enabled)
    if type(id) ~= "string" or id == "" then return false, "bad-id" end
    if not sources.get(id) then return false, "unknown-source" end
    local path = paths.backend_path("sources.local.json")
    local data = read_json_file(path) or { sources = {} }
    local list = data.sources
    if type(list) ~= "table" then list = {} end
    local found = false
    for _, e in ipairs(list) do
        if e.id == id then
            e.enabled = enabled and true or false
            found = true
            break
        end
    end
    if not found then
        table.insert(list, { id = id, enabled = enabled and true or false })
    end
    data.sources = list
    local ok_write = pcall(m_util.write_file, path, cjson.encode(data))
    if not ok_write then return false, "write-failed" end
    sources.reload()
    return true
end

function sources.get(id)
    for _, s in ipairs(sources.list()) do
        if s.id == id then return s end
    end
    return nil
end

-- Resolve a source to a concrete URL for an appid, or nil if it can't.
function sources.resolve_url(source, appid)
    appid = tostring(appid)
    if source.kind == "AppIdZip" then
        local url = source.urlTemplate:gsub("{appid}", appid)
        url = url:gsub("<appid>", appid) -- tolerate legacy placeholder
        return url
    end
    if source.kind == "LuaFolder" then
        -- Raw GitHub file serving for a loose-file folder source.
        local branch = source.branch or "main"
        local path = source.path or ""
        local parts = {}
        if path ~= "" then parts = { path } end
        table.insert(parts, appid .. ".zip")
        local rel = table.concat(parts, "/")
        return "https://raw.githubusercontent.com/" .. source.owner .. "/" .. source.repo .. "/" .. branch .. "/" .. rel
    end
    return nil
end

-- True when the source's URL template carries an api_key= placeholder at all
-- (e.g. Hubcap). Distinguishes key-gated sources from plain ones.
function sources.key_gated(source)
    return (source.urlTemplate or ""):find("api_key=", 1, true) ~= nil
end

-- Return the raw API key for a key-gated source (e.g. Hubcap), or nil.
-- The key lives in the module-level hubcap_key variable (loaded from
-- secrets.local.json) — we never re-extract it from the URL template
-- because the regex api_key=([%w_]+) silently fails for keys that contain
-- non-word characters (hyphens, dots, etc.).
function sources.get_key(source)
    if not sources.key_gated(source) then return nil end
    -- For now all key-gated sources share hubcap_key.
    -- A per-source key store can be added later if needed.
    if hubcap_key ~= "" then return hubcap_key end
    -- Fallback: try the URL template (for sources loaded without secrets)
    return (source.urlTemplate or ""):match("api_key=([%w_]+)")
end

-- True when a key-gated source has a non-empty injected API key (e.g. Hubcap
-- after the secrets reload). Lets the UI distinguish "no key set" from "key
-- set but the usage fetch failed" on key-based sources.
function sources.has_key(source)
    return sources.get_key(source) ~= nil
end

-- ── Availability probing ──────────────────────────────────────────────────────

local availability_cache = {} -- appid -> { at = os.time(), result = {...} }
local AVAILABILITY_TTL_SECONDS = 60
-- Matches the probe script's own caps (3s per probe via curl --max-time, 5s
-- batch deadline) plus a small margin for PowerShell startup — if the parallel
-- batch hasn't written results by now, something is wrong and the sequential
-- fallback takes over sooner rather than making the user stare at
-- "Checking sources…".
local PROBE_DEADLINE_SECONDS = 6

-- Fast parallel probing via probe_sources.ps1 (launched fully detached, so
-- the Lua VM never blocks on it — it polls the result file for up to
-- PROBE_DEADLINE_SECONDS). Returns a map id -> { code, body, ms }, or nil if
-- the probe can't run / times out — the caller falls back to the sequential
-- Lua http probes.
local function probe_parallel(appid)
    local script   = paths.backend_path("probe_sources.ps1")
    local launcher = paths.backend_path("launch_detached.ps1")
    if not fs.exists(script) or not fs.exists(launcher) then return nil end
    if os.getenv("OS") ~= "Windows_NT" then return nil end

    local dir = paths.backend_path("temp_dl")
    if not fs.exists(dir) then pcall(fs.create_directories, dir) end
    local cfg_file = fs.join(dir, "probe_" .. appid .. ".json")
    local res_file = fs.join(dir, "probe_" .. appid .. ".result.json")

    local probes = {}
    for _, s in ipairs(sources.enabled()) do
        local kind, url, key = "range", nil, nil
        if s.availabilityUrl and s.availabilityUrl ~= "" then
            kind = "status"
            url = s.availabilityUrl:gsub("{appid}", appid)
            key = sources.get_key(s) or ""
        else
            url = sources.resolve_url(s, appid)
        end
        if url then
            table.insert(probes, { id = s.id, kind = kind, url = url, key = key })
        end
    end
    if #probes == 0 then return nil end

    pcall(fs.remove, res_file)
    local ok_write = pcall(m_util.write_file, cfg_file, cjson.encode({ probes = probes }))
    if not ok_write then return nil end

    local cmd = 'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' .. launcher .. '" -Script "' .. script .. '" -ConfigFile "' .. cfg_file .. '" -ResultFile "' .. res_file .. '"'
    -- spawn.exec: CreateProcessW CREATE_NO_WINDOW — invisible AND non-blocking.
    local ok_exec = spawn.exec(cmd)
    if not ok_exec then return nil end

    local deadline = os.time() + PROBE_DEADLINE_SECONDS
    while os.time() < deadline do
        if fs.exists(res_file) then
            local ok_read, content = pcall(m_util.read_file, res_file)
            if ok_read and content and content ~= "" then
                local ok_json, data = pcall(cjson.decode, content)
                pcall(fs.remove, cfg_file)
                pcall(fs.remove, res_file)
                if ok_json and type(data) == "table" then return data end
            end
        end
        pcall(m_util.sleep, 100)
    end
    pcall(fs.remove, cfg_file)
    pcall(fs.remove, res_file)
    return nil
end

-- Probe each enabled source for the appid. Two probe kinds:
--   * availabilityUrl sources (e.g. Hubcap's free /api/v1/status endpoint): GET
--     that with the source's api key in a Bearer header. A 200 means the source
--     can serve the bundle. These sources MUST NOT be probed via their manifest
--     URL — Hubcap counts manifest GETs against the daily download limit, so a
--     ranged probe there would burn a download for every availability check.
--   * everything else: a 1-byte ranged GET (lightweight — HEAD is rejected by
--     GitHub raw and the manifest API). A 200/206 means available.
-- Anything else (404, 5xx, timeout) means it can't right now. Results are
-- cached briefly so re-opening the add popup doesn't re-hit every source.
--
-- The probes run IN PARALLEL through probe_sources.ps1 (total time = slowest
-- source instead of the sum) with the sequential Lua http loop as fallback.
function sources.check_availability(appid)
    appid = tostring(appid)
    local knownSize = nil -- file_size from status endpoint (avoids extra ranged probe)
    local cached = availability_cache[appid]
    if cached and (os.time() - cached.at) < AVAILABILITY_TTL_SECONDS then
        return cached.result
    end

    local out = {}
    local probes = probe_parallel(appid)
    if probes then
        for _, s in ipairs(sources.enabled()) do
            local r = probes[s.id]
            local available = false
            local limitReached = false
            local usage = sources.check_usage(s)
            if s.availabilityUrl and s.availabilityUrl ~= "" then
                if usage and usage.remaining <= 0 then
                    -- Daily quota already spent — the status endpoint would
                    -- just refuse (429); the user needs to know it's the
                    -- LIMIT, not the game, that's the problem.
                    limitReached = true
                elseif r then
                    if r.code == 429 then
                        limitReached = true
                    elseif r.code == 200 and r.body then
                        -- 200 EVEN for games it doesn't have
                        -- ({"status":"not_found", ...}) — available only when
                        -- the body actually claims the manifest exists.
                        local ok_decode, data = pcall(cjson.decode, r.body)
                        if ok_decode and type(data) == "table" then
                            available = data.manifest_file_exists == true
                            if type(data.file_size) == "number" then knownSize = data.file_size end
                        end
                    end
                end
            else
                if r then
                    available = (r.code == 200 or r.code == 206)
                end
            end
            sources.record_health(s.id, available, r and r.ms or nil)
            table.insert(out, {
                id = s.id,
                name = s.name,
                available = available,
                limitReached = limitReached or nil,
                usage = usage,
                health = sources.health_of(s.id),
                keyGated = sources.key_gated(s),
                hasKey = sources.has_key(s),
                knownSize = knownSize,
            })
        end
    else
        -- Fallback (also the path exercised by the unit tests): sequential
        -- probes through Millennium's Lua http module.
        for _, s in ipairs(sources.enabled()) do
            local available = false
            local limitReached = false
            local started = os.clock()
            local usage = sources.check_usage(s)
            if s.availabilityUrl and s.availabilityUrl ~= "" then
                if usage and usage.remaining <= 0 then
                    limitReached = true
                else
                    local status_url = s.availabilityUrl:gsub("{appid}", appid)
                    local key = sources.get_key(s)
                    local headers = {}
                    if key then headers = { ["Authorization"] = "Bearer " .. key } end
                    local ok, resp = pcall(http.request, status_url, { method = "GET", timeout = 3, headers = headers })
                    if ok and resp then
                        if resp.status == 200 and resp.body then
                            local ok_decode, data = pcall(cjson.decode, resp.body)
                            if ok_decode and type(data) == "table" then
                                available = data.manifest_file_exists == true
                                if type(data.file_size) == "number" then knownSize = data.file_size end
                            end
                        elseif resp.status == 429 then
                            limitReached = true
                        end
                    end
                end
            else
                local url = sources.resolve_url(s, appid)
                if url then
                    local ok, resp = pcall(http.request, url, {
                        method = "GET",
                        timeout = 3,
                        headers = { ["Range"] = "bytes=0-0" },
                    })
                    if ok and resp and (resp.status == 200 or resp.status == 206) then
                        available = true
                    end
                end
            end
            sources.record_health(s.id, available, (os.clock() - started) * 1000)
            table.insert(out, {
                id = s.id,
                name = s.name,
                available = available,
                limitReached = limitReached or nil,
                usage = usage,
                health = sources.health_of(s.id),                keyGated = sources.key_gated(s),
                hasKey = sources.has_key(s),
                knownSize = knownSize,
            })
        end

    end

    availability_cache[appid] = { at = os.time(), result = out }
    return out
end

-- Pure cache read (no HTTP): the file_size the last fresh availability check
-- learned for this source from its FREE status endpoint (e.g. Hubcap's
-- /status). The installer uses it to skip the ranged size probe on the
-- manifest URL — quota sources count EVERY GET on that URL as a download, so
-- probing there burns one of the user's daily downloads. Returns nil when
-- there is no fresh entry; callers fall back to "size unknown".
function sources.known_size(appid, source_id)
    appid = tostring(appid)
    local cached = availability_cache[appid]
    if not cached or (os.time() - cached.at) >= AVAILABILITY_TTL_SECONDS then
        return nil
    end
    local result = cached.result
    if type(result) ~= "table" then return nil end
    for _, s in ipairs(result) do
        if s.id == source_id then return s.knownSize end
    end
    return nil
end

-- ── Source usage / limits ─────────────────────────────────────────────────────

local usage_cache = {} -- source id -> { at = os.time(), usage = {...}|nil }
local USAGE_TTL_SECONDS = 60

-- Optional per-source usage reporting: if a source entry carries a `usageUrl`
-- (a JSON endpoint that returns {used-field, limit-field} — e.g. Hubcap's
-- /api/v1/user/stats, which manifest downloads count against), fetch it so the
-- UI can show how much of the daily limit is left. Returns nil for sources
-- without usageUrl or when the fetch/parse fails.
function sources.check_usage(source)
    if not source.usageUrl or source.usageUrl == "" then return nil end
    -- Key-gated endpoints can't report usage without a key; skip the pointless
    -- request (it would just 401) so the UI can show the "no key" state.
    if (source.usageUrl or ""):find("api_key=", 1, true) and not sources.has_key(source) then
        return nil
    end
    local cached = usage_cache[source.id]
    if cached and (os.time() - cached.at) < USAGE_TTL_SECONDS then
        return cached.usage
    end

    local usage = nil
    local key_invalid = false
    local ok, resp = pcall(http.request, source.usageUrl, { method = "GET", timeout = 5 })
    if ok and resp then
        if resp.status == 200 then
            local ok_decode, data = pcall(cjson.decode, resp.body)
            if ok_decode and type(data) == "table" then
                local fields = source.usageFields or { used = "usage", limit = "limit" }
                local limit = data[fields.limit]
                local used = data[fields.used]
                local remaining = data[fields.remaining or "remaining"]
                if type(limit) == "number" and limit > 0 then
                    if type(remaining) == "number" then
                        used = math.max(limit - remaining, 0)
                    elseif type(used) == "number" then
                        remaining = math.max(limit - used, 0)
                    end
                    if type(used) == "number" and type(remaining) == "number" then
                        usage = { used = used, limit = limit, remaining = remaining }
                        local expField = fields.expires or "resetAt"
                        if type(data[expField]) == "string" then
                            usage.expiresAt = data[expField]
                        end
                    end
                end
            end
        elseif resp.status == 401 or resp.status == 403 then
            key_invalid = true
        end
    end

    usage_cache[source.id] = { at = os.time(), usage = usage, key_invalid = key_invalid }
    return usage
end

function sources.is_key_invalid(source)
    local id = type(source) == "table" and source.id or source
    local cached = usage_cache[id]
    return cached and cached.key_invalid == true or false
end

-- Drop the usage + availability caches so the next call re-fetches with fresh
-- data. Called after a runtime key update — otherwise a failed usage fetch
-- (bad/expired key) stays cached for the TTL and the UI keeps showing stale
-- quota (or none) right after the user saves a working key.
function sources.invalidate_caches()
    usage_cache = {}
    availability_cache = {}
end

-- Drop ONLY the usage cache. A successful download consumes quota on the
-- provider's side, but nothing else would tell the plugin — without this the
-- UI keeps showing the pre-download "X of Y left" for up to the usage TTL.
function sources.invalidate_usage()
    usage_cache = {}
end

-- ── Source health tracking ────────────────────────────────────────────────────
-- Per-source health is recorded on every probe/download outcome so the settings
-- UI can show online/offline status, latency, availability %, last success /
-- failure, and last catalog refresh — and the add flow can auto-fall back to a
-- healthy source. Persisted to backend/source_health.json so it survives restarts.

local health_store = nil -- id -> { online, lastOk, lastFail, lastMs, availabilityPct, checks, okChecks, lastRefresh }

local function health_file()
    return paths.backend_path("source_health.json")
end

local function load_health()
    if health_store then return health_store end
    health_store = {}
    local ok, content = pcall(m_util.read_file, health_file())
    if ok and content and content ~= "" then
        local ok_decode, data = pcall(cjson.decode, content)
        if ok_decode and type(data) == "table" then
            health_store = data
        end
    end
    return health_store
end

local function save_health()
    pcall(m_util.write_file, health_file(), cjson.encode(health_store))
end

-- Record one outcome for a source. ok=true on any successful request, ok=false
-- on any failure. ms is best-effort wall latency (os.clock delta over a blocking
-- request is a fine approximation).
function sources.record_health(id, ok, ms)
    local store = load_health()
    local h = store[id] or { checks = 0, okChecks = 0 }
    h.checks = (h.checks or 0) + 1
    if ok then
        h.okChecks = (h.okChecks or 0) + 1
        h.online = true
        h.lastOk = os.time()
        if ms then h.lastMs = math.floor(ms) end
    else
        h.online = false
        h.lastFail = os.time()
    end
    local total = h.checks
    local good = h.okChecks
    h.availabilityPct = total > 0 and math.floor(good * 100 / total) or nil
    store[id] = h
    save_health()
end

function sources.health_of(id)
    return load_health()[id]
end

-- Mark a catalog refresh time for the given source (called after a refresh).
function sources.mark_refresh(id)
    local store = load_health()
    store[id] = store[id] or {}
    store[id].lastRefresh = os.time()
    save_health()
end

return sources
