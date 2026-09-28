-- Ignitools title cache (backend-managed).
--
-- The unlocked-games page needs a display name for every unlocked appid.
-- Reads are PURE CACHE LOOKUPS — titles.cached() never touches Steam, so
-- opening the page returns instantly even for a huge library. Unknown
-- appids render as their appid on the frontend (no blank "…" placeholders).
--
-- The cache is filled two ways:
--   * SaveIgnitoolsTitles — the frontend pushes names it resolved itself
--   * titles.resolve()    — an explicit backfill path (tooling/CLI)
-- Failed lookups are remembered (failed = true) and stay out of `missing`
-- until the user asks for a refresh, which clears the failure flag so the
-- title can be retried (no endless hammering of Steam's API).

local fs     = require("fs")
local http   = require("http")
local m_util = require("utils")
local logger = require("plugin_logger")
local paths  = require("paths")
local cjson  = require("json")

local titles = {}

local CACHE_FILE = "titles_cache.json"
local MAX_FETCH_PER_CALL = 8   -- appids fetched per backfill call
local REQUEST_TIMEOUT = 8      -- seconds

local cache = nil -- { entries = { [appid] = { name=string, fetchedAt=number, failed=bool } } }

local function cache_path()
    return paths.backend_path(CACHE_FILE)
end

local function load()
    if cache then return cache end
    cache = { entries = {} }
    local ok, content = pcall(m_util.read_file, cache_path())
    if ok and content and content ~= "" then
        local ok_decode, data = pcall(cjson.decode, content)
        if ok_decode and type(data) == "table" and type(data.entries) == "table" then
            cache = data
        end
    end
    return cache
end

local function save()
    pcall(m_util.write_file, cache_path(), cjson.encode(cache))
end

-- Pure cache read — never fetches. Returns
--   { titles = { appid = name }, pending = n, missing = { appid, ... } }
-- where missing lists the appids that are WORTH retrying (no name, not
-- marked failed). Permanently-failed appids stay out of missing until the
-- user asks for a refresh.
function titles.cached(appids)
    local c = load()
    local out = {}
    local missing = {}
    local pending = 0
    for _, id in ipairs(appids or {}) do
        local key = tostring(id)
        local entry = c.entries[key]
        if entry and entry.name then
            out[key] = entry.name
        else
            pending = pending + 1
            if not (entry and entry.failed) then
                table.insert(missing, key)
            end
        end
    end
    return { titles = out, pending = pending, missing = missing }
end

-- Store names pushed from the frontend (SaveIgnitoolsTitles). Merges the
-- appid -> name map into the cache (overwriting any failure marker) and
-- persists. `failed` is an optional list of appids that DEFINITIVELY don't
-- exist (Steam answered success:false) — they're marked failed so they stay
-- out of `missing` and aren't re-requested on every boot. Returns how many
-- names were stored.
function titles.save_results(names, failed)
    local c = load()
    local saved = 0
    for id, name in pairs(names or {}) do
        if type(name) == "string" and name ~= "" then
            c.entries[tostring(id)] = { name = name, fetchedAt = os.time() }
            saved = saved + 1
        end
    end
    local changed = saved > 0
    for _, id in ipairs(failed or {}) do
        local key = tostring(id)
        local entry = c.entries[key]
        if not (entry and entry.name) then
            c.entries[key] = { failed = true, fetchedAt = os.time() }
            changed = true
        end
    end
    if changed then save() end
    return saved
end

-- Clear the failure marker for the given appids so they become worth
-- retrying again. Pure cache mutation — no fetching. Returns the cached
-- state (same shape as cached()) so callers can re-render immediately.
function titles.refresh(appids)
    local c = load()
    for _, id in ipairs(appids or {}) do
        local key = tostring(id)
        local entry = c.entries[key]
        if entry and entry.failed then
            entry.failed = nil
        end
    end
    save()
    return titles.cached(appids)
end

-- Fetch a single appid from Steam's appdetails API. Returns name or nil.
-- The response shape is { "<appid>": { success: bool, data: { name: string } } }.
local function fetch_one(appid)
    local url = "https://store.steampowered.com/api/appdetails?appids=" .. appid .. "&l=english&filters=basic"
    local ok, resp = pcall(http.get, url, { timeout = REQUEST_TIMEOUT })
    if not ok or not resp or resp.status ~= 200 or not resp.body then
        return nil
    end
    local ok_decode, data = pcall(cjson.decode, resp.body)
    if not ok_decode or type(data) ~= "table" then return nil end
    local entry = data[appid]
    if type(entry) ~= "table" or entry.success ~= true or type(entry.data) ~= "table" then
        return nil
    end
    local name = entry.data.name
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Explicit backfill: fetch unknown titles from Steam (one at a time,
-- bounded per call) and store them. The RPC layer is cached-only and does
-- NOT call this — it exists for tooling/CLI backfills. Returns the same
-- shape as cached() plus `pending`.
function titles.resolve(appids)
    local c = load()
    local out = {}
    local missing = {}
    for _, id in ipairs(appids or {}) do
        local key = tostring(id)
        local entry = c.entries[key]
        if entry and entry.name then
            out[key] = entry.name
        elseif not (entry and entry.failed) then
            table.insert(missing, key)
        end
    end
    local fetched = 0
    for _, id in ipairs(missing) do
        if fetched >= MAX_FETCH_PER_CALL then break end
        local name = fetch_one(id)
        if name then
            c.entries[id] = { name = name, fetchedAt = os.time() }
            out[id] = name
        else
            c.entries[id] = { failed = true, fetchedAt = os.time() }
        end
        fetched = fetched + 1
    end
    save()
    local still_missing = {}
    local pending = 0
    for _, id in ipairs(appids or {}) do
        local key = tostring(id)
        local entry = c.entries[key]
        if not (entry and entry.name) then
            pending = pending + 1
            if not (entry and entry.failed) then
                table.insert(still_missing, key)
            end
        end
    end
    logger.log("Pmtools: title backfill fetched " .. fetched .. " (pending " .. pending .. ")")
    return { titles = out, pending = pending, missing = still_missing }
end

-- Total cached count (for the "N unlocked" badge).
function titles.cached_count()
    local c = load()
    local n = 0
    for _, e in pairs(c.entries) do
        if e.name then n = n + 1 end
    end
    return n
end

return titles
