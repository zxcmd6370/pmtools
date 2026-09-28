-- Ignitools manifest request-code resolver.
--
-- When Steam needs a depot manifest it doesn't have cached (e.g. a game that
-- got a new build after the provider's zip was made), it asks the content
-- server for a "manifest request code". The loader (Ignitools.dll) intercepts
-- that request and resolves the code here, in priority order:
--
--   1. fetch_manifest_code_ex(app_id, depot_id, gid)   <- this file
--   2. fetch_manifest_code(gid)                        <- this file
--   3. [manifest] url in ignitools.toml (C++ native fetch)
--
-- Provider status (checked 2026-08-19):
--   opensteamtool  https://manifest.opensteamtool.com/{gid}  -> 403, dead
--   steamrun       https://manifest.steam.run/api/manifest/{gid} -> 404, dead
--   wudrm          http://gmrc.wudrm.com/manifest/{gid}      -> 200, ONLY live one
--
-- Every provider tried before wudrm is pure blocking latency added to a
-- hooked Steam call (the loader's Lua VM is single-threaded), so this file
-- goes straight to wudrm. If wudrm dies too, return nil instantly: the
-- loader then falls back to its own C++ resolver ([manifest] url in
-- ignitools.toml), which is faster than a doomed retry chain here.
--
-- Resolutions are cached: Steam re-asks the same gid across page views and
-- boot re-scans; all gids in one scan burst are unique, so the cache mainly
-- speeds up REPEAT views (library re-render, revisiting a game page).
--
-- Return the code as a digit STRING: the loader parses it with from_chars,
-- and tonumber() would lose precision above 2^53.

local POSITIVE_TTL = 3600 -- a resolved code is reused for 1h
local NEGATIVE_TTL = 60   -- a failed gid is not retried for 1min
local MAX_ENTRIES  = 4096 -- memory cap; one oldest entry evicted on overflow

local cache = {}        -- gid string -> { code = string, at = time }
local neg_cache = {}    -- gid string -> last-failed time
local cache_count = 0

local function try_wudrm(gid_s)
    local body, status = http_get("http://gmrc.wudrm.com/manifest/" .. gid_s)
    if status == 200 and body then
        return body:match("^%s*(%d+)%s*$")
    end
    return nil
end

local function try_ignihub(gid_s)
    local body, status = http_get("https://ignihub.vercel.app/api/manifest?gid=" .. gid_s)
    if status == 200 and body then
        return body:match("^%s*(%d+)%s*$")
    end
    return nil
end

local function resolve(gid)
    local gid_s = tostring(gid)
    local now = os.time()

    local hit = cache[gid_s]
    if hit and (now - hit.at) < POSITIVE_TTL then
        return hit.code
    end
    local neg_at = neg_cache[gid_s]
    if neg_at and (now - neg_at) < NEGATIVE_TTL then
        -- wudrm just failed for this gid; return nil so the loader's own
        -- C++ resolver gets a shot instead of us blocking again.
        return nil
    end

    local code = try_wudrm(gid_s)
    if not code then code = try_ignihub(gid_s) end

    if code then
        if hit == nil then
            cache_count = cache_count + 1
            if cache_count > MAX_ENTRIES then
                -- evict one oldest entry (rare: only past the cap)
                local oldest_key, oldest_at = nil, math.maxinteger
                for k, v in pairs(cache) do
                    if v.at < oldest_at then
                        oldest_at = v.at
                        oldest_key = k
                    end
                end
                if oldest_key then
                    cache[oldest_key] = nil
                    cache_count = cache_count - 1
                end
            end
        end
        cache[gid_s] = { code = code, at = now }
        neg_cache[gid_s] = nil
    else
        neg_cache[gid_s] = now
    end

    return code
end

function fetch_manifest_code(gid)
    return resolve(gid)
end

function fetch_manifest_code_ex(app_id, depot_id, gid)
    return resolve(gid)
end
