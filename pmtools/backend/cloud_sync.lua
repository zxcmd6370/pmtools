-- Ignitools BYOS Cloud Vault Manager
-- Coordinates background workers for personal storage operations:
--   - Google Drive
--   - WebDAV
--   - Local Directory / NAS / USB

local fs          = require("fs")
local m_utils     = require("utils")
local logger      = require("plugin_logger")
local paths       = require("paths")
local steam_utils = require("steam_utils")
local cjson       = require("json")
local spawn       = require("spawn")

local cloud_sync = {}

local function secrets_file()
    return paths.backend_path("secrets.local.json")
end

local function status_file()
    return paths.backend_path("cloud_status.json")
end

local function temp_dir()
    local dir = paths.backend_path("temp_dl")
    if not fs.exists(dir) then pcall(fs.create_directories, dir) end
    return dir
end

-- Read secrets.local.json
local function load_secrets()
    local ok, content = pcall(m_utils.read_file, secrets_file())
    if ok and content and content ~= "" then
        local ok_json, data = pcall(cjson.decode, content)
        if ok_json and type(data) == "table" then
            return data
        end
    end
    return {}
end

-- Save secrets.local.json
local function save_secrets(data)
    local ok = pcall(m_utils.write_file, secrets_file(), cjson.encode(data))
    return ok
end

-- Get current Cloud Vault config
function cloud_sync.get_config()
    local s = load_secrets()
    local cloud = s.cloud or (s.provider and s) or {}
    return {
        provider   = cloud.provider or "local",
        enabled    = cloud.enabled == true,
        localPath  = cloud.localPath or "",
        gdrive     = cloud.gdrive or {},
        webdav     = cloud.webdav or { url = "", username = "", password = "" },
    }
end

-- Save Cloud Vault config
function cloud_sync.set_config(cfg)
    if type(cfg) ~= "table" then return false, "invalid-config" end
    local s = load_secrets()
    local current = s.cloud or (s.provider and s) or {}

    current.provider  = cfg.provider or current.provider or "local"
    current.enabled   = cfg.enabled == true
    if cfg.localPath ~= nil then current.localPath = tostring(cfg.localPath) end

    if type(cfg.gdrive) == "table" then
        current.gdrive = current.gdrive or {}
        if cfg.gdrive.clientId ~= nil then current.gdrive.clientId = tostring(cfg.gdrive.clientId) end
        if cfg.gdrive.clientSecret ~= nil then current.gdrive.clientSecret = tostring(cfg.gdrive.clientSecret) end
        if cfg.gdrive.refreshToken ~= nil then current.gdrive.refreshToken = tostring(cfg.gdrive.refreshToken) end
        if cfg.gdrive.email ~= nil then current.gdrive.email = tostring(cfg.gdrive.email) end
        if cfg.gdrive.connected ~= nil then current.gdrive.connected = cfg.gdrive.connected == true end
    end

    if type(cfg.webdav) == "table" then
        current.webdav = current.webdav or {}
        if cfg.webdav.url ~= nil then current.webdav.url = tostring(cfg.webdav.url) end
        if cfg.webdav.username ~= nil then current.webdav.username = tostring(cfg.webdav.username) end
        if cfg.webdav.password ~= nil and cfg.webdav.password ~= "" and not cfg.webdav.password:match("^%*+$") then
            current.webdav.password = tostring(cfg.webdav.password)
        end
    end

    s.cloud = current
    if not save_secrets(s) then return false, "write-failed" end
    logger.log("Pmtools: Cloud Vault config saved for provider=" .. tostring(current.provider))
    return true
end

-- Dispatch a background task to cloud_worker.ps1
function cloud_sync.dispatch_task(action, params)
    local cfg = cloud_sync.get_config()
    local taskId = "cloud_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    local stFile = fs.join(temp_dir(), taskId .. "_status.json")
    local cfgFile = fs.join(temp_dir(), taskId .. "_cfg.json")

    local steam_path = steam_utils.detect_steam_install_path()
    if not steam_path or steam_path == "" then
        return { success = false, error = "no-steam-path" }
    end

    local workerPayload = {
        taskId           = taskId,
        action           = action,
        steamPath        = steam_path,
        tempDir          = temp_dir(),
        statusFile       = stFile,
        provider         = cfg.provider,
        settings         = {
            localPath = cfg.localPath,
            gdrive    = cfg.gdrive,
            webdav    = cfg.webdav,
        },
        appid            = params and params.appid or nil,
        title            = params and params.title or nil,
        includeManifests = params and params.includeManifests ~= false,
        includeSaves     = params and params.includeSaves ~= false,
    }

    -- Write initial starting status
    local initStatus = {
        id        = taskId,
        action    = action,
        status    = "starting",
        progress  = 0,
        message   = "Initializing background task...",
        error     = nil,
        updatedAt = os.time(),
    }
    m_utils.write_file(stFile, cjson.encode(initStatus))
    m_utils.write_file(cfgFile, cjson.encode(workerPayload))

    local scriptPath = paths.backend_path("cloud_worker.ps1")
    local launcherPath = paths.backend_path("launch_detached.ps1")
    local cmd = 'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' .. launcherPath .. '" -Script "' .. scriptPath .. '" -ConfigFile "' .. cfgFile .. '"'

    local ok = spawn.exec(cmd)
    if not ok then
        return { success = false, error = "spawn-failed" }
    end

    logger.log("Pmtools: dispatched cloud task " .. taskId .. " (" .. action .. ")")
    return { success = true, taskId = taskId }
end

-- Read task status from temp_dl
function cloud_sync.get_task_status(taskId)
    if type(taskId) ~= "string" or taskId == "" then
        return { success = false, error = "bad-task-id" }
    end
    local stFile = fs.join(temp_dir(), taskId .. "_status.json")
    local ok, content = pcall(m_utils.read_file, stFile)
    if ok and content and content ~= "" then
        local ok_json, data = pcall(cjson.decode, content)
        if ok_json and type(data) == "table" then
            return { success = true, task = data }
        end
    end
    return { success = false, error = "task-not-found" }
end

-- Read persistent status map (local cache of what has been vaulted)
function cloud_sync.get_status_map()
    local ok, content = pcall(m_utils.read_file, status_file())
    if ok and content and content ~= "" then
        local ok_json, data = pcall(cjson.decode, content)
        if ok_json and type(data) == "table" then
            return data
        end
    end
    return {}
end

-- Update persistent status map
function cloud_sync.update_status(appid, info)
    local map = cloud_sync.get_status_map()
    map[tostring(appid)] = info
    pcall(m_utils.write_file, status_file(), cjson.encode(map))
end

return cloud_sync
