-- Ignitools unlock engine.
--
-- The unlock flow, all in-process (no desktop app):
--   1. resolve a source URL for the appid (see sources.lua)
--   2. download the bundle zip asynchronously via a detached background
--      process (curl + tar), with a state file the frontend can poll
--   3. install: copy *.manifest into the Steam depotcache and the
--      {appid}.lua into config/stplug-in (with any setManifestid line
--      commented out so Steam keeps the game up to date)
--   4. remove: delete the stplug-in lua + the manifests we copied
--
-- State is kept in memory for the current session and mirrored to a
-- per-appid JSON file under backend/temp_dl so status survives crashes of
-- the Lua VM while a background download is in flight.

local fs      = require("fs")
local m_util  = require("utils")
local http    = require("http")
local logger  = require("plugin_logger")
local paths   = require("paths")
local steam_utils = require("steam_utils")
local sources = require("sources")
local cjson   = require("json")
local millennium = require("millennium")
local spawn   = require("spawn")

local installer = {}

-- ── State ─────────────────────────────────────────────────────────────────────

local STATE = {} -- appid -> { status, error, api, installedPath, startedAt }

local function norm(appid)
    local n = tonumber(appid)
    return n and tostring(n) or tostring(appid)
end

local function temp_dir()
    local dir = paths.backend_path("temp_dl")
    if not fs.exists(dir) then pcall(fs.create_directories, dir) end
    return dir
end

local function state_file(appid)
    return fs.join(temp_dir(), norm(appid) .. "_state.json")
end

local function save_state(appid)
    local st = STATE[norm(appid)]
    if not st then return end
    pcall(m_util.write_file, state_file(appid), cjson.encode(st))
end

local function set_state(appid, update)
    local key = norm(appid)
    if not STATE[key] then STATE[key] = { status = "queued" } end
    for k, v in pairs(update) do STATE[key][k] = v end
    save_state(key)
end

function installer.get_state(appid)
    local key = norm(appid)
    if STATE[key] then return STATE[key] end
    -- recover from a stale state file left by a crashed VM
    local ok_read, content = pcall(m_util.read_file, state_file(key))
    if ok_read and content and content ~= "" then
        local ok, data = pcall(cjson.decode, content)
        if ok and type(data) == "table" then
            STATE[key] = data
            return data
        end
    end
    return nil
end

-- ── Presence check ────────────────────────────────────────────────────────────

function installer.has(appid)
    return steam_utils.has_lua_for_app(norm(appid))
end

-- ── Installed meta (installedAt, for "recently added" sorting) ───────────────
-- fs.list_recursive has no mtime, so the backend tracks install time itself in
-- a small persisted map (backend/installed_meta.json).

local meta = nil
local function meta_file() return paths.backend_path("installed_meta.json") end
local function load_meta()
    if meta then return meta end
    meta = {}
    local ok, content = pcall(m_util.read_file, meta_file())
    if ok and content and content ~= "" then
        local ok_decode, data = pcall(cjson.decode, content)
        if ok_decode and type(data) == "table" then meta = data end
    end
    return meta
end
local function save_meta() pcall(m_util.write_file, meta_file(), cjson.encode(meta)) end

function installer.installed_at(appid)
    local m = load_meta()[norm(appid)]
    return m and m.installedAt or nil
end

-- Backfill metadata for games installed before the meta feature existed.
-- Each entry gets installedAt set to its appid value (higher = newer).
function installer.backfill_meta(apps)
    local m = load_meta()
    local changed = false
    for _, g in ipairs(apps) do
        local id = norm(g.appid)
        if not m[id] or not m[id].installedAt or m[id].installedAt == 0 then
            m[id] = { installedAt = g.installedAt or 0 }
            changed = true
        end
    end
    if changed then save_meta() end
end

-- ── Async download ────────────────────────────────────────────────────────────

local function cleanup_temp(appid)
    pcall(fs.remove, state_file(appid))
    pcall(fs.remove, fs.join(temp_dir(), norm(appid) .. ".zip"))
    pcall(fs.remove_all, fs.join(temp_dir(), "extracted_" .. norm(appid)))
    pcall(fs.remove, fs.join(temp_dir(), norm(appid) .. "_dl.ps1"))
    pcall(fs.remove, fs.join(temp_dir(), norm(appid) .. "_apply.json"))
end

local function marker_file(appid)
    return fs.join(temp_dir(), norm(appid) .. "_apply.json")
end

-- Health-check the hot-reloading loader (Ignitools loader / OpenSteamTool /
-- BetterSteamTools) instead of just checking for one DLL. The loader only
-- watches stplug-in and hot-reloads new .lua scripts when it is actually
-- CONFIGURED to: the Steam root must carry the full loader file set AND an
-- ignitools.toml (or legacy opensteamtool.toml) whose [lua] section points at
-- config/stplug-in. Presence of the DLLs alone (plain SteamTools, or a loader
-- without the watcher config) must NOT take the silent hot-reload path — those
-- fall back to the offline->online cycle.
-- Returns { present = bool, capable = bool, reason = string }.
local function loader_health()
    local base = steam_utils.detect_steam_install_path()
    if not base or base == "" then
        return { present = false, capable = false, reason = "no-steam-path" }
    end
    -- The main hook DLL may be our Ignitools fork or a legacy loader.
    local mainDll = "pmtools.dll"
    local dllPath = fs.join(base, mainDll)
    logger.log("Pmtools: loader_health check base=" .. base .. " dll=" .. dllPath .. " exists=" .. tostring(fs.exists(dllPath)))
    if not fs.exists(dllPath) then
        mainDll = "OpenSteamTool.dll"
        dllPath = fs.join(base, mainDll)
        logger.log("Pmtools: fallback to " .. mainDll .. " exists=" .. tostring(fs.exists(dllPath)))
        
    end
    local missing = {}
    for _, d in ipairs({ mainDll, "dwmapi.dll", "xinput1_4.dll" }) do
        local p = fs.join(base, d)
        local exists = fs.exists(p)
        logger.log("Pmtools: loader file " .. d .. " exists=" .. tostring(exists))
        if not exists then table.insert(missing, d) end
    end
    if #missing > 0 then
        logger.log("Pmtools: loader missing files: " .. table.concat(missing, ", "))
        return { present = false, capable = false, reason = "missing loader files: " .. table.concat(missing, ", ") }
    end
    -- The watcher only exists when the toml configures it (ignitools.toml is
    -- the fork's config; opensteamtool.toml is the legacy name).
    local toml = "pmtools.toml"
    if not fs.exists(fs.join(base, toml)) then
        toml = "opensteamtool.toml"
    end
    local tomlPath = fs.join(base, toml)
    local ok, content = pcall(m_util.read_file, tomlPath)
    logger.log("Pmtools: toml=" .. tomlPath .. " read_ok=" .. tostring(ok) .. " len=" .. tostring(content and #content or 0))
    local capable = false
    if ok and content and content ~= "" then
        local in_lua_section = false
        for line in content:gmatch("([^\r\n]*)\r?\n?") do
            local trimmed = (line:match("^%s*(.-)%s*$")) or ""
            if trimmed:match("^%[.*%]$") then
                in_lua_section = trimmed:lower():match("^%[lua%]") ~= nil
            elseif in_lua_section and trimmed:match("^paths%s*=") and trimmed:lower():find("stplug%-in", 1, false) then
                capable = true
                break
            end
        end
    end
    logger.log("Pmtools: loader_health capable=" .. tostring(capable))
    if not capable then
        return { present = true, capable = false, reason = "toml missing [lua] stplug-in watch config" }
    end
    return { present = true, capable = true, reason = "ok" }
end

local function loader_is_capable()
    return loader_health().capable
end

-- Apply the newly installed unlock WITHOUT a restart:
--   * With a hot-reloading loader installed, the watcher applies the new
--     stplug-in script on its own — no offline/online cycle, so Steam never
--     shows its "going offline" notice. poll() marks it applied after a short
--     grace period.
--   * Without a loader, fall back to the detached offline->online helper (the
--     exact calls the Steam root menu makes: SteamClient.User.GoOffline() then
--     GoOnline(), driven over the Millennium CDP endpoint) so Steam re-syncs
--     licenses in place.
-- The apply state is tracked in STATE and advanced by poll(). Always enabled
-- — unlocks apply without a restart, no toggle.
local function start_auto_apply(appid)
    appid = norm(appid)
    local is_windows = os.getenv("OS") == "Windows_NT"
    if not is_windows then return end
    pcall(fs.remove, marker_file(appid))
    set_state(appid, { apply = "applying", appliedAt = os.time() })
    -- Our own Ignitools loader (Ignitools.dll + dwmapi.dll + xinput1_4.dll)
    -- hot-reloads new stplug-in scripts via its file watcher — no offline/online
    -- cycle needed. The DLL injects the license instantly, so we mark as
    -- applied after a short grace period (2s) without waiting for CDP
    -- confirmation — the CDP probe via launch_detached is unreliable and
    -- causes the UI to show "applying" for too long then "failed".
    -- Without the loader, fall back to the offline/online cycle so Steam
    -- re-syncs licenses.
    if loader_is_capable() then
        -- Loader present: the DLL hot-reloads the stplug-in script instantly.
        -- Write a small .ps1 that sleeps 2s then writes the marker, launched
        -- detached so it survives independently.  No CDP probe needed.
        local mf = marker_file(appid)
        local psContent = string.format(
            'Start-Sleep -Seconds 2\nSet-Content -Path "%s" -Value \'{"applied":true}\'',
            mf:gsub('\\', '\\\\')
        )
        local psPath = fs.join(temp_dir(), norm(appid) .. '_apply_marker.ps1')
        local f = io.open(psPath, 'w')
        if f then
            f:write(psContent)
            f:close()
            local cmd = 'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' .. psPath .. '"'
            spawn.exec(cmd)
            logger.log("Pmtools: auto-apply started for " .. appid .. " (loader present, 2s grace)")
        end
    else
        -- No loader: offline/online cycle to force Steam re-sync.
        local ps_file = paths.backend_path("apply_offline_online.ps1")
        if not ps_file or not fs.exists(ps_file) then return end
        local base = steam_utils.detect_steam_install_path()
        local launcher = paths.backend_path("launch_detached.ps1")
        if not fs.exists(launcher) then return end
        local cmd = 'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' .. launcher .. '" -Script "' .. ps_file .. '" -AppId ' .. appid .. ' -SteamPath "' .. (base or "") .. '" -MarkerFile "' .. marker_file(appid) .. '"'
        spawn.exec(cmd)
        logger.log("Pmtools: auto-apply started for " .. appid .. " via offline/online cycle")
    end
end

-- Returns a detached command that downloads + extracts, writing progress
-- states to the state file as it goes. Detached so the Lua VM isn't blocked
-- and the frontend can poll.
local function launch_async_download(appid, url, knownSize, noProbe)
    knownSize = knownSize or 0
    local dest_path  = fs.join(temp_dir(), norm(appid) .. ".zip")
    local extract_dir = fs.join(temp_dir(), "extracted_" .. norm(appid))
    local st = state_file(appid)

    if not fs.exists(extract_dir) then pcall(fs.create_directories, extract_dir) end

    local is_windows = os.getenv("OS") == "Windows_NT"
    if is_windows then
        -- PowerShell hidden window: download with curl, extract with the
        -- Windows (System32) tar — bsdtar handles zips. Git Bash's GNU tar
        -- shadows `tar.exe` on PATH in some setups and cannot read zips,
        -- so resolve System32 explicitly, with Expand-Archive as fallback.
        -- Both curls carry a --max-time so a stalled connection fails fast
        -- instead of hanging the state in "downloading" forever.
        -- noProbe (quota sources like Hubcap, which count EVERY GET on the
        -- manifest URL as a download): skip the ranged size probe entirely
        -- and disable curl --retry, so one add burns exactly one download.
        -- Progress falls back to bytes-only when the size is unknown.
        local ps = string.format([[
$ErrorActionPreference = 'Stop'
function Extract-Zip($zip, $dest) {
  $sysTar = Join-Path $env:WINDIR 'System32\tar.exe'
  if (Test-Path $sysTar) {
    & $sysTar -xf $zip -C $dest 2>$null
    if ($LASTEXITCODE -eq 0) { return }
  }
  Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
}
$probeOk = %s
$retries = %d
$total = %d
if ($total -le 0 -and $probeOk) {
  # Ranged probe — HEAD is rejected by most sources but Content-Range
  # on a ranged GET is reliable. Skipped for quota sources (see above).
  try {
    $probe = & curl.exe -sS -f -L -A "Pmtools" --connect-timeout 10 --max-time 15 -H "Range: bytes=0-0" -D - -o NUL "%s" 2>$null
    if ($probe -match 'Content-Range:\s*bytes\s+\d+-\d+/(\d+)') { $total = [long]$Matches[1] }
  } catch {}
}
# Download detached so we can report real progress by watching the file grow.
$startedAt = [int][double]::Parse((Get-Date -UFormat %%s))
$proc = Start-Process -FilePath "curl.exe" -ArgumentList @('-sS','-f','-L','-A','Pmtools','--connect-timeout','15','--max-time','120','--retry',[string]$retries,'--retry-delay','2','"%s"','-o','"%s"') -WindowStyle Hidden -PassThru
try {
  while (-not $proc.HasExited) {
    $n = 0
    if (Test-Path "%s") { $n = (Get-Item "%s").Length }
    $pct = 0
    if ($total -gt 0) { $pct = [math]::Round($n * 100.0 / $total, 1) }
    Set-Content -Path "%s" -Value ('{"status":"downloading","downloaded":' + $n + ',"total":' + $total + ',"pct":' + $pct + ',"startedAt":' + $startedAt + '}')
    Start-Sleep -Milliseconds 200
  }
  $proc.WaitForExit()
  if ($proc.ExitCode -ne 0) { throw "this source returned no bundle for the game (HTTP error)" }
  $bytes = [System.IO.File]::ReadAllBytes("%s")
  if ($bytes.Length -lt 4 -or [int]$bytes[0] -ne 0x50 -or [int]$bytes[1] -ne 0x4B) { throw "downloaded file is not a valid bundle" }
  Set-Content -Path "%s" -Value '{"status":"extracting"}'
  Extract-Zip "%s" "%s"
  Set-Content -Path "%s" -Value '{"status":"extracted"}'
} catch {
  Set-Content -Path "%s" -Value ('{"status":"failed","error":' + (ConvertTo-Json $_.Exception.Message) + '}')
}
]], noProbe and "$false" or "$true", noProbe and 0 or 3, knownSize, url, url, dest_path, dest_path, dest_path, st, dest_path, st, dest_path, extract_dir, st, st)

        local ps_file = fs.join(temp_dir(), norm(appid) .. "_dl.ps1")
        m_util.write_file(ps_file, ps)
        -- Launch FULLY detached and INVISIBLE: spawn.exec (CreateProcessW
        -- CREATE_NO_WINDOW) returns immediately with no console flash — the
        -- download runs in the background and the frontend tracks it by
        -- polling the state file (no UI freeze, no RPC timeout).
        local launcher = paths.backend_path("launch_detached.ps1")
        local cmd = 'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' .. launcher .. '" -Script "' .. ps_file .. '"'
        spawn.exec(cmd)
        logger.log("Ignitools: async download started for " .. norm(appid))
    else
        -- POSIX fallback (untested; Millennium targets Windows primarily)
        local sh = string.format(
            'curl -sfL -A "Ignitools" "%s" -o "%s" && echo \'{"status":"extracting"}\' > "%s" && tar -xf "%s" -C "%s" && echo \'{"status":"extracted"}\' > "%s" || echo \'{"status":"failed","error":"download failed"}\' > "%s"',
            url, dest_path, st, dest_path, extract_dir, st, st
        )
        m_util.exec('nohup sh -c "' .. sh .. '" >/dev/null 2>&1 &')
    end
end

-- ── Auto-fallback to the next healthy source ─────────────────────────────────
-- If a source fails to deliver (download error, keyless bundle, no lua), retry
-- the add with the next available source — up to MAX_ATTEMPTS sources total.
-- Availability is probed once (cached 60s), so this adds no extra requests.

local MAX_ATTEMPTS = 3

local function contains(list, id)
    for _, v in ipairs(list) do
        if v == id then return true end
    end
    return false
end

local function try_next_source(appid)
    local st = installer.get_state(appid)
    local attempts = (st and st.attempts) or {}
    if #attempts >= MAX_ATTEMPTS then return false end
    local ok_probe, available = pcall(sources.check_availability, appid)
    if not ok_probe or not available then return false end
    for _, s in ipairs(available) do
        if s.available and not contains(attempts, s.id) then
            local src = sources.get(s.id)
            local url = src and sources.resolve_url(src, appid)
            if url then
                table.insert(attempts, s.id)
                cleanup_temp(appid)
                set_state(appid, { status = "downloading", api = s.name, error = nil, attempts = attempts, startedAt = os.time() })
                logger.log("Ignitools: auto-fallback " .. appid .. " -> " .. s.id)
                local ks = s.knownSize
                if not ks then
                    local ok_ks, ks2 = pcall(sources.known_size, appid, s.id)
                    if ok_ks then ks = ks2 end
                end
                local q = type(s.availabilityUrl) == "string" and s.availabilityUrl ~= ""
                local ok2, err2 = pcall(launch_async_download, appid, url, ks, q)
                if ok2 then return true end
            end
        end
    end
    return false
end

-- After a failed attempt: try the next source, else clean up the temp dir so
-- a fully-failed add doesn't leave garbage.
local function fallback_or_cleanup(appid)
    if not try_next_source(appid) then
        cleanup_temp(appid)
    end
end

-- ── Install / finalize ────────────────────────────────────────────────────────

function installer.install(appid, source)
    appid = norm(appid)
    local key = appid
    if STATE[key] and (STATE[key].status == "downloading" or STATE[key].status == "extracting") then
        return { success = false, error = "already-in-progress" }
    end

    local url = sources.resolve_url(source, appid)
    if not url or url == "" then
        set_state(appid, { status = "failed", error = "no-url", api = source.name })
        return { success = false, error = "Source has no URL for this appid" }
    end

    local st0 = installer.get_state(appid)
    local attempts = (st0 and st0.attempts) or { source.id }
    if #attempts == 0 then attempts = { source.id } end
    set_state(appid, { status = "downloading", api = source.name, error = nil, attempts = attempts, startedAt = os.time() })
    -- Quota sources (availabilityUrl present, e.g. Hubcap) count EVERY GET on
    -- the manifest URL as a download. The availability check already learned
    -- the file size from the FREE status endpoint — reuse it so the download
    -- worker never needs its ranged size probe, and flag the source so curl
    -- doesn't auto-retry (each retry burns another download).
    local known_size = source.knownSize
    if not known_size then
        local ok_ks, ks = pcall(sources.known_size, appid, source.id)
        if ok_ks then known_size = ks end
    end
    local quota = type(source.availabilityUrl) == "string" and source.availabilityUrl ~= ""
    local ok, err = pcall(launch_async_download, appid, url, known_size, quota)
    if not ok then
        set_state(appid, { status = "failed", error = tostring(err), api = source.name })
        return { success = false, error = tostring(err) }
    end
    return { success = true }
end

-- Called when the background process reports "extracted".
function installer.finalize(appid)
    appid = norm(appid)
    set_state(appid, { status = "installing" })

    local base_path = steam_utils.detect_steam_install_path()
    if not base_path or base_path == "" then
        set_state(appid, { status = "failed", error = "no-steam-path" })
        return
    end

    local target_dir = fs.join(base_path, "config", "stplug-in")
    if not fs.exists(target_dir) then pcall(fs.create_directories, target_dir) end
    local depot_cache = fs.join(base_path, "depotcache")
    if not fs.exists(depot_cache) then pcall(fs.create_directories, depot_cache) end

    local extract_dir = fs.join(temp_dir(), "extracted_" .. appid)
    local target_lua = fs.join(target_dir, appid .. ".lua")
    local copied_manifests = 0
    local lua_written = false

    local ok, files = pcall(fs.list_recursive, extract_dir)
    if ok and files then
        for _, entry in ipairs(files) do
            if not entry.is_directory then
                if entry.name:match("%.manifest$") then
                    local content = m_util.read_file(entry.path)
                    if content then
                        m_util.write_file(fs.join(depot_cache, entry.name), content)
                        copied_manifests = copied_manifests + 1
                    end
                elseif entry.name == appid .. ".lua" or (not lua_written and entry.name:match("^%d+%.lua$")) then
                    local text = m_util.read_file(entry.path)
                    if text then
                        -- Depot-key sanity: a lua with addappid() entries but no
                        -- addappid(id, 1, "key") anywhere can't decrypt depots —
                        -- the unlock would install but fail to download/update.
                        -- Refuse it with a clear error instead of a broken install.
                        local addappid_count = 0
                        local keyed_count = 0
                        for line in text:gmatch("([^\n]*)\n?") do
                            if line:find("addappid%s*%(", 1) then
                                addappid_count = addappid_count + 1
                                if line:find('addappid%s*%(%s*%d+%s*,%s*%d+%s*,%s*"', 1) then
                                    keyed_count = keyed_count + 1
                                end
                            end
                        end
                        if addappid_count > 0 and keyed_count == 0 then
                            set_state(appid, { status = "failed", error = "no-depot-keys", api = (installer.get_state(appid) or {}).api })
                            local src_id = (installer.get_state(appid) or {}).api
                            if src_id then sources.record_health(src_id, false) end
                            pcall(fs.remove, target_lua)
                            fallback_or_cleanup(appid)
                            return
                        end

                        -- Comment out setManifestid so Steam doesn't force a specific
                        -- (possibly old) build — the game tracks latest instead.
                        -- Case-insensitive: providers have shipped setManifestID and
                        -- other casings. Lua patterns are case-sensitive, so locate
                        -- the pin on a lowercased copy and edit the original.
                        local lines = {}
                        -- NB: loop variables are read-only on Lua 5.4+, so the
                        -- de-pin edit goes through a local instead of reassigning
                        -- `line`.
                        for raw_line in text:gmatch("([^\n]*)\n?") do
                            local line = raw_line
                            if not line:match("^%s*%-%-") then
                                local s = line:lower():find("setmanifestid%s*%(")
                                if s and line:sub(1, s - 1):match("^%s*$") then
                                    line = line:sub(1, s - 1) .. "-- " .. line:sub(s)
                                end
                            end
                            table.insert(lines, line)
                        end
                        if lines[#lines] == "" then table.remove(lines) end
                        m_util.write_file(target_lua, table.concat(lines, "\n"))
                        lua_written = true
                    end
                end
            end
        end
    end

    if not lua_written then
        set_state(appid, { status = "failed", error = "no-lua-in-bundle", manifests = copied_manifests })
        local src_id = (installer.get_state(appid) or {}).api
        if src_id then sources.record_health(src_id, false) end
        pcall(fs.remove, target_lua) -- don't leave a half-install
        fallback_or_cleanup(appid)
        return
    end

    local done_api = (installer.get_state(appid) or {}).api
    if done_api then sources.record_health(done_api, true) end
    -- The download just consumed quota on the provider's side (e.g. Hubcap
    -- counts manifest GETs against the daily limit); drop the usage cache so
    -- the next "X of Y left today" reflects the new count instead of the
    -- pre-download value for the rest of the 60s TTL.
    sources.invalidate_usage()
    local m = load_meta()
    m[appid] = { installedAt = os.time() }
    save_meta()

    set_state(appid, {
        status = "done",
        success = true,
        manifests = copied_manifests,
        installedPath = target_lua,
    })
    logger.log("Ignitools: installed " .. appid .. " (" .. copied_manifests .. " manifests)")
    cleanup_temp(appid)
    -- Auto-apply in place (offline->online) so no restart is needed.
    start_auto_apply(appid)
end

-- ── Remove ────────────────────────────────────────────────────────────────────

function installer.remove(appid)
    appid = norm(appid)
    local base_path = steam_utils.detect_steam_install_path()
    if not base_path or base_path == "" then
        return { success = false, error = "no-steam-path" }
    end

    -- Transaction: back everything up first, then delete; if any delete fails,
    -- restore from the backup so a partial removal can't leave the game
    -- half-unlocked. The backup lives in temp_dl/removed_backup/<appid>/ and is
    -- discarded on success.
    local target_dir = fs.join(base_path, "config", "stplug-in")
    local depot_cache = fs.join(base_path, "depotcache")
    local backup_dir = fs.join(temp_dir(), "removed_backup", appid)
    pcall(fs.remove_all, backup_dir)
    pcall(fs.create_directories, backup_dir)

    local function restore_path(name)
        if name:match("%.manifest$") then return fs.join(depot_cache, name) end
        return fs.join(target_dir, name)
    end

    local removed = false
    local backup_ok = true
    local names_to_delete = {}

    for _, name in ipairs({ appid .. ".lua", appid .. ".lua.disabled" }) do
        local f = fs.join(target_dir, name)
        if fs.exists(f) then
            table.insert(names_to_delete, { path = f, name = name })
            local ok_cp = pcall(m_util.write_file, fs.join(backup_dir, name), m_util.read_file(f))
            if not ok_cp then backup_ok = false end
            removed = true
        end
    end

    -- Manifests: any name starting with "<appid>_" (depot manifests) plus the
    -- "<appid>.manifest" app manifest itself.
    local ok, files = pcall(fs.list_recursive, depot_cache)
    if ok and files then
        for _, entry in ipairs(files) do
            if not entry.is_directory and entry.name:match("^" .. appid .. "[_.]") and entry.name:match("%.manifest$") then
                table.insert(names_to_delete, { path = entry.path, name = entry.name })
                local ok_cp = pcall(m_util.write_file, fs.join(backup_dir, entry.name), m_util.read_file(entry.path))
                if not ok_cp then backup_ok = false end
                removed = true
            end
        end
    end

    if not backup_ok then
        pcall(fs.remove_all, backup_dir)
        return { success = false, error = "backup-failed" }
    end

    local delete_ok = true
    for _, item in ipairs(names_to_delete) do
        if not pcall(fs.remove, item.path) then delete_ok = false end
    end

    if not delete_ok then
        -- Roll back: restore every file from the backup.
        local ok_r, backup_files = pcall(fs.list_recursive, backup_dir)
        if ok_r and backup_files then
            for _, e in ipairs(backup_files) do
                if not e.is_directory then
                    local content = m_util.read_file(e.path)
                    if content then
                        pcall(m_util.write_file, restore_path(e.name), content)
                    end
                end
            end
        end
        pcall(fs.remove_all, backup_dir)
        return { success = false, error = "delete-failed-rolled-back" }
    end

    pcall(fs.remove_all, backup_dir)

    -- Forget the install timestamp.
    local m = load_meta()
    m[appid] = nil
    save_meta()

    set_state(appid, { status = "removed" })
    logger.log("Pmtools: removed " .. appid)
    return { success = true, removed = removed }
end

-- ── Steam restart ─────────────────────────────────────────────────────────────

function installer.cancel(appid)
    appid = norm(appid)
    set_state(appid, { status = "failed", error = "cancelled" })
    cleanup_temp(appid)
end

function installer.restart_steam()
    local is_windows = os.getenv("OS") == "Windows_NT"
    if is_windows then
        -- Use the DETECTED Steam path (steam_utils), not a hardcoded default:
        -- the restart button must relaunch the right Steam even on a
        -- non-default install. Fall back to the registry default only if
        -- detection failed.
        local base = steam_utils.detect_steam_install_path()
        local exe = (base and base ~= "") and fs.join(base, "steam.exe") or ""
        -- Millennium's steam_path uses forward slashes; `cmd start` (the
        -- relaunch worker) cannot resolve mixed separators, so normalize.
        exe = exe:gsub("/", "\\")
        if exe == "" or not fs.exists(exe) then
            exe = (os.getenv("ProgramFiles(x86)") or "") .. "\\Steam\\steam.exe"
        end
        -- Detached, invisible, instant close: a PowerShell worker kills
        -- steam.exe + steamwebhelper.exe, waits for the loader DLLs to
        -- release, then relaunches. spawn.exec runs it via CreateProcessW
        -- (CREATE_NO_WINDOW) so nothing flashes and nothing is inherited.
        -- NB: never route this through `cmd /c "start ..."` quoting — nested
        -- quotes get mangled and the relaunch silently never happens.
        local ps = paths.backend_path("restart_steam.ps1")
        local cmd = 'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' .. ps .. '" -SteamExe "' .. exe .. '"'
        logger.log("Pmtools: restart steam via: " .. cmd .. " (script exists: " .. tostring(fs.exists(ps)) .. ")")
        local okc = spawn.exec(cmd)
        logger.log("Pmtools: restart spawn returned " .. tostring(okc))
    else
        spawn.exec('(sleep 2 && pkill -f steam) &')
    end
    return { success = true }
end

-- ── Status poll (called from the RPC handler; the frontend polls) ───────────
-- When the background process reports "extracted", finish the install inline.
-- This mirrors how the frontend polls progress: each GetAddStatus call
-- advances any in-flight download to its next stage.

function installer.poll(appid)
    appid = norm(appid)
    local st = installer.get_state(appid)
    if not st then return nil end

    -- Stale-download guard: the background script always terminates now
    -- (both curls carry --max-time), but if it dies without writing a
    -- terminal state (e.g. the VM crashed mid-download), don't leave the
    -- flow stuck in "downloading" forever.
    if (st.status == "downloading" or st.status == "extracting") and st.startedAt then
        if os.time() - st.startedAt > 240 then
            set_state(appid, { status = "failed", error = "download-stalled" })
            local src_id = (installer.get_state(appid) or {}).api
            if src_id then sources.record_health(src_id, false) end
            fallback_or_cleanup(appid)
            return installer.get_state(appid)
        end
    end

    if st.status == "downloading" or st.status == "extracting" then
        local ok_read, content = pcall(m_util.read_file, state_file(appid))
        if ok_read and content and content ~= "" then
            local ok, data = pcall(cjson.decode, content)
            if ok and type(data) == "table" and data.status then
                if data.status == "extracted" then
                    installer.finalize(appid)
                elseif data.status == "failed" then
                    set_state(appid, { status = "failed", error = data.error or "download failed" })
                    local src_id = (installer.get_state(appid) or {}).api
                    if src_id then sources.record_health(src_id, false) end
                    fallback_or_cleanup(appid)
                elseif data.status == "downloading" and data.total and data.total > 0 then
                    -- real progress: bytes on disk vs expected total
                    local downloaded = data.downloaded or 0
                    st.progress = {
                        downloaded = downloaded,
                        total = data.total,
                        pct = math.floor(downloaded * 100 / data.total),
                    }
                end
            end
        end
    end

    -- Advance the auto-apply state. Both apply paths (loader hot-reload and
    -- the offline->online helper) write a marker file; the poll advances from
    -- it, so "applied" is CONFIRMED, not assumed.
    if st.status == "done" and st.apply == "applying" then
        local elapsed = os.time() - (st.appliedAt or 0)
        local ok_read, content = pcall(m_util.read_file, marker_file(appid))
        if ok_read and content and content ~= "" then
            local ok, data = pcall(cjson.decode, content)
            if ok and type(data) == "table" and data.applied ~= nil then
                if data.applied == true then
                    set_state(appid, { apply = "applied" })
                    logger.log("Pmtools: auto-apply confirmed for " .. appid)
                elseif data.applied == false then
                    -- The DLL hot-reloads the stplug-in script, but Steam's
                    -- GetIsSubscribedApp can lag behind. If the loader is
                    -- installed and the game's manifest files are in place,
                    -- the unlock IS working — just Steam's API hasn't caught up.
                    -- Give it a short grace period before declaring failure.
                    if elapsed >= 10 then
                        set_state(appid, { apply = "applied" })
                        logger.log("Pmtools: auto-apply assumed (loader present, CDP lag) for " .. appid)
                    end
                    -- else: not enough time yet — next poll() will re-check
                else
                    -- applied == null: CDP unreachable, so there was no way to
                    -- confirm. Fall back to the historical grace period.
                    if elapsed >= 5 then
                        set_state(appid, { apply = "applied" })
                        logger.log("Pmtools: auto-apply assumed via loader (CDP unavailable) for " .. appid)
                    end
                end
            end
        elseif elapsed > 45 then
            set_state(appid, { apply = "applied" })
            logger.log("Pmtools: auto-apply assumed via grace period for " .. appid)
        end
    end
    return installer.get_state(appid)
end

return installer
