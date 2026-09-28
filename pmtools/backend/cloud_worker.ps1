# Ignitools BYOS Cloud Vault Background Worker
# Handles packaging, synchronization, uploading, and downloading
# for game saves and unlock manifests across personal storage providers:
#   - Local folder / External USB / Network Share (NAS)
#   - Google Drive (Google Drive for Desktop)
#   - WebDAV (Nextcloud, ownCloud, Koofr)

param(
    [Parameter(Mandatory = $true)][string]$ConfigFile
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction SilentlyContinue
Add-Type -AssemblyName "System.IO.Compression" -ErrorAction SilentlyContinue
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::DefaultConnectionLimit = 64

if (-not (Test-Path -LiteralPath $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile"
    exit 1
}

$cfg = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
$statusFile = $cfg.statusFile
$taskId = $cfg.taskId
$action = $cfg.action
$steamPath = $cfg.steamPath
$tempDir = $cfg.tempDir
$provider = $cfg.provider
$settings = $cfg.settings

function Update-Status {
    param(
        [string]$Status,
        [int]$Progress = 0,
        [string]$Message = "",
        [string]$ErrorMsg = $null,
        $Data = $null
    )
    $obj = @{
        id = $taskId
        action = $action
        status = $Status
        progress = $Progress
        message = $Message
        error = $ErrorMsg
        data = $Data
        updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    $json = $obj | ConvertTo-Json -Compress -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($statusFile, $json, $utf8NoBom)
}

Update-Status -Status "running" -Progress 5 -Message "Starting $action..."

# ── Unified Storage Client Abstraction ───────────────────────────────────────

$script:gdriveToken = $null
$script:gdriveFolderCache = @{}
$script:gdriveFileCache = @{}
$script:gdrivePopulatedFolders = @{}

function Invoke-DriveApiWithRetry([scriptblock]$ScriptBlock, [int]$MaxRetries = 6) {
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return (& $ScriptBlock)
        }
        catch {
            $ex = $_.Exception
            $isRateLimit = $false
            $body = ""
            $statusCode = 0

            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $body = $_.ErrorDetails.Message
            }
            if ($ex -and $ex.Response) {
                try { $statusCode = [int]$ex.Response.StatusCode } catch {}
                if (-not $body) {
                    try {
                        $stream = $ex.Response.GetResponseStream()
                        if ($stream) {
                            $reader = New-Object System.IO.StreamReader($stream)
                            $body = $reader.ReadToEnd()
                        }
                    } catch {}
                }
            }

            if ($statusCode -eq 429 -or $statusCode -eq 403 -or $body -match 'rateLimit' -or $body -match 'quota' -or $body -match 'RATE_LIMIT_EXCEEDED') {
                $isRateLimit = $true
            }

            if ($isRateLimit -and $attempt -le $MaxRetries) {
                $sleepSec = if ($attempt -eq 1) { 25 } elseif ($attempt -eq 2) { 40 } else { 60 }
                try {
                    Update-Status -Status "running" -Progress -1 -Message "Google Drive quota reached. Pausing ${sleepSec}s for window reset (retry $attempt/$MaxRetries)..."
                } catch {}
                Start-Sleep -Seconds $sleepSec
                continue
            }
            throw
        }
    }
}

function Get-GdriveAccessToken() {
    if ($script:gdriveToken) { return $script:gdriveToken }
    $gd = $settings.gdrive
    if (-not $gd -or -not $gd.refreshToken) {
        throw "Google Drive is not connected. Please click 'Sign in with Google' in Cloud Sync."
    }
    # Project permanent client ID and secret — unchangeable by users
    $cId = "300276148036-jf0gkng2fr97e28v0if1u83kuqb7lo83.apps.googleusercontent.com"
    $cSec = "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"
    $tokenBody = @{
        client_id     = $cId
        client_secret = $cSec
        refresh_token = $gd.refreshToken
        grant_type    = "refresh_token"
    }
    try {
        $tokenRes = Invoke-DriveApiWithRetry { Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body $tokenBody -TimeoutSec 30 }
        if ($tokenRes -and $tokenRes.access_token) {
            $script:gdriveToken = $tokenRes.access_token
            return $script:gdriveToken
        }
    } catch {
        throw "Failed to refresh Google Drive access token: $($_.Exception.Message)"
    }
    throw "Google Drive authentication failed (no access token returned)."
}

function Get-GdriveHeaders() {
    $tok = Get-GdriveAccessToken
    return @{ "Authorization" = "Bearer $tok" }
}

function Populate-DriveFolderCache($folderId) {
    if (-not $folderId) { return }
    $headers = Get-GdriveHeaders
    $pageToken = $null
    do {
        $tokenParam = if ($pageToken) { "&pageToken=$pageToken" } else { "" }
        $q = "'$folderId' in parents and trashed = false"
        $searchUri = "https://www.googleapis.com/drive/v3/files?q=" + [System.Uri]::EscapeDataString($q) + "&pageSize=1000&fields=nextPageToken,files(id,name,size)" + $tokenParam
        $res = Invoke-DriveApiWithRetry { Invoke-RestMethod -Uri $searchUri -Method Get -Headers $headers -TimeoutSec 30 }
        if ($res.files) {
            foreach ($f in $res.files) {
                $sz = 0
                if ($f.size) { $sz = [int64]$f.size }
                $script:gdriveFileCache["$folderId/$($f.name)"] = @{ id = $f.id; size = $sz }
            }
        }
        $pageToken = $res.nextPageToken
    } while ($pageToken)
    $script:gdrivePopulatedFolders[$folderId] = $true
}

function Get-OrCreateDriveFolder($folderName, $parentId = "root") {
    $cacheKey = "$parentId/$folderName"
    if ($script:gdriveFolderCache.ContainsKey($cacheKey)) {
        return $script:gdriveFolderCache[$cacheKey]
    }
    $headers = Get-GdriveHeaders
    # Search for existing folder
    $q = if ($parentId -eq "root") {
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
    } else {
        "name = '$folderName' and '$parentId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
    }
    $searchUri = "https://www.googleapis.com/drive/v3/files?q=" + [System.Uri]::EscapeDataString($q) + "&fields=files(id,name)"
    $res = Invoke-DriveApiWithRetry { Invoke-RestMethod -Uri $searchUri -Method Get -Headers $headers -TimeoutSec 30 }
    if ($res.files -and $res.files.Count -gt 0) {
        $id = $res.files[0].id
        $script:gdriveFolderCache[$cacheKey] = $id
        return $id
    }
    # Create folder
    $metaProps = @{
        name     = $folderName
        mimeType = "application/vnd.google-apps.folder"
    }
    if ($parentId -ne "root") {
        $metaProps["parents"] = @($parentId)
    }
    $meta = $metaProps | ConvertTo-Json
    $createRes = Invoke-DriveApiWithRetry { Invoke-RestMethod -Uri "https://www.googleapis.com/drive/v3/files" -Method Post -Headers $headers -Body $meta -ContentType "application/json; charset=utf-8" -TimeoutSec 30 }
    if ($createRes -and $createRes.id) {
        $id = $createRes.id
        $script:gdriveFolderCache[$cacheKey] = $id
        return $id
    }
    throw "Failed to create Google Drive folder: $folderName"
}

function Resolve-GdriveLocation($remoteRelPath) {
    # Base Ignitools directory in Google Drive root
    $pmtoolsId = Get-OrCreateDriveFolder "Pmtools" "root"
    $normalized = $remoteRelPath.Replace("\", "/")
    if ($normalized.StartsWith("vault/")) {
        $vaultId = Get-OrCreateDriveFolder "vault" $pmtoolsId
        $fileName = $normalized.Substring(6)
        return @{ ParentId = $vaultId; FileName = $fileName }
    } elseif ($normalized.StartsWith("save/") -or $normalized.StartsWith("saves/")) {
        $saveId = Get-OrCreateDriveFolder "save" $pmtoolsId
        $fileName = $normalized.Substring($normalized.IndexOf("/") + 1)
        return @{ ParentId = $saveId; FileName = $fileName }
    } else {
        $fileName = Split-Path $normalized -Leaf
        return @{ ParentId = $pmtoolsId; FileName = $fileName }
    }
}

function Storage-PutFile($localFilePath, $remoteRelPath) {
    if (-not (Test-Path -LiteralPath $localFilePath)) { throw "Local file not found: $localFilePath" }

    if ($provider -eq "local") {
        $root = $settings.localPath
        $dest = Join-Path $root $remoteRelPath
        $parent = Split-Path $dest -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $localFilePath -Destination $dest -Force
        return @{ skipped = $false }
    }
    elseif ($provider -eq "gdrive") {
        $loc = Resolve-GdriveLocation $remoteRelPath
        $parentId = $loc.ParentId
        $fileName = $loc.FileName
        $headers = Get-GdriveHeaders

        $cacheKey = "$parentId/$fileName"
        $existing = $null
        if ($script:gdriveFileCache.ContainsKey($cacheKey)) {
            $existing = $script:gdriveFileCache[$cacheKey]
        } elseif (-not $script:gdrivePopulatedFolders.ContainsKey($parentId)) {
            $q = "name = '$fileName' and '$parentId' in parents and trashed = false"
            $searchUri = "https://www.googleapis.com/drive/v3/files?q=" + [System.Uri]::EscapeDataString($q) + "&fields=files(id,name,size)"
            $res = Invoke-DriveApiWithRetry { Invoke-RestMethod -Uri $searchUri -Method Get -Headers $headers -TimeoutSec 30 }
            if ($res.files -and $res.files.Count -gt 0) {
                $f = $res.files[0]
                $sz = 0; if ($f.size) { $sz = [int64]$f.size }
                $existing = @{ id = $f.id; size = $sz }
                $script:gdriveFileCache[$cacheKey] = $existing
            }
        }

        $localFileInfo = Get-Item -LiteralPath $localFilePath
        $localSize = $localFileInfo.Length

        # SPEED OPTIMIZATION 1: Skip unchanged files
        if ($existing -and $existing.size -eq $localSize -and $localSize -gt 0) {
            return @{ skipped = $true; id = $existing.id }
        }

        # SPEED OPTIMIZATION 2: Atomic Multipart Upload for new files
        if (-not $existing -or -not $existing.id) {
            $boundary = [System.Guid]::NewGuid().ToString()
            $LF = "`r`n"
            $metaJson = @{ name = $fileName; parents = @($parentId) } | ConvertTo-Json -Compress

            $headBytes = [System.Text.Encoding]::UTF8.GetBytes(
                "--$boundary$LF" +
                "Content-Type: application/json; charset=UTF-8$LF$LF" +
                "$metaJson$LF" +
                "--$boundary$LF" +
                "Content-Type: application/octet-stream$LF$LF"
            )
            $fileBytes = [System.IO.File]::ReadAllBytes($localFilePath)
            $endBytes = [System.Text.Encoding]::UTF8.GetBytes("$LF--$boundary--$LF")

            $ms = New-Object System.IO.MemoryStream
            $ms.Write($headBytes, 0, $headBytes.Length)
            $ms.Write($fileBytes, 0, $fileBytes.Length)
            $ms.Write($endBytes, 0, $endBytes.Length)
            $payload = $ms.ToArray()
            $ms.Dispose()

            $uploadHeaders = @{ "Authorization" = $headers.Authorization }
            $uploadUri = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
            $createRes = Invoke-DriveApiWithRetry {
                Invoke-RestMethod -Uri $uploadUri -Method Post -Headers $uploadHeaders -Body $payload -ContentType "multipart/related; boundary=$boundary" -TimeoutSec 300
            }

            if ($createRes -and $createRes.id) {
                $script:gdriveFileCache[$cacheKey] = @{ id = $createRes.id; size = $localSize }
                return @{ skipped = $false; id = $createRes.id }
            }
            throw "Failed to upload $fileName via multipart to Google Drive."
        }
        else {
            # File exists but size was 0 or different: upload content in single PATCH request
            $fileId = $existing.id
            $uploadUri = "https://www.googleapis.com/upload/drive/v3/files/$fileId`?uploadType=media"
            Invoke-DriveApiWithRetry {
                Invoke-RestMethod -Uri $uploadUri -Method Patch -Headers $headers -InFile $localFilePath -ContentType "application/octet-stream" -TimeoutSec 300 | Out-Null
            }
            $existing.size = $localSize
            $script:gdriveFileCache[$cacheKey] = $existing
            return @{ skipped = $false; id = $fileId }
        }
    }
    elseif ($provider -eq "webdav") {
        $bytes = [System.IO.File]::ReadAllBytes($localFilePath)
        $url = $settings.webdav.url.TrimEnd('/') + "/" + $remoteRelPath.TrimStart('/')
        $cred = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($settings.webdav.username):$($settings.webdav.password)"))
        $headers = @{ "Authorization" = "Basic $cred" }
        $res = Invoke-WebRequest -Uri $url -Method Put -Headers $headers -Body $bytes -TimeoutSec 120 -UseBasicParsing
        return @{ skipped = $false }
    }
    throw "Unsupported provider: $provider"
}

function Storage-GetFile($remoteRelPath, $localDestPath) {
    $parent = Split-Path $localDestPath -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    if ($provider -eq "local") {
        $src = Join-Path $settings.localPath $remoteRelPath
        if (-not (Test-Path -LiteralPath $src)) { return $false }
        Copy-Item -LiteralPath $src -Destination $localDestPath -Force
        return $true
    }
    elseif ($provider -eq "gdrive") {
        $loc = Resolve-GdriveLocation $remoteRelPath
        $parentId = $loc.ParentId
        $fileName = $loc.FileName
        $headers = Get-GdriveHeaders

        $cacheKey = "$parentId/$fileName"
        $fileId = $null
        if ($script:gdriveFileCache.ContainsKey($cacheKey)) {
            $item = $script:gdriveFileCache[$cacheKey]
            $fileId = if ($item -is [hashtable]) { $item.id } else { $item }
        } elseif (-not $script:gdrivePopulatedFolders.ContainsKey($parentId)) {
            $q = "name = '$fileName' and '$parentId' in parents and trashed = false"
            $searchUri = "https://www.googleapis.com/drive/v3/files?q=" + [System.Uri]::EscapeDataString($q) + "&fields=files(id,name,size)"
            $res = Invoke-DriveApiWithRetry { Invoke-RestMethod -Uri $searchUri -Method Get -Headers $headers -TimeoutSec 30 }
            if ($res.files -and $res.files.Count -gt 0) {
                $f = $res.files[0]
                $fSize = 0; if ($f.size) { $fSize = [int64]$f.size }
                $fileId = $f.id
                $script:gdriveFileCache[$cacheKey] = @{ id = $fileId; size = $fSize }
            }
        }

        if (-not $fileId) {
            return $false
        }

        $downloadUri = "https://www.googleapis.com/drive/v3/files/$fileId`?alt=media"
        Invoke-DriveApiWithRetry { Invoke-WebRequest -Uri $downloadUri -Method Get -Headers $headers -OutFile $localDestPath -TimeoutSec 300 -UseBasicParsing | Out-Null }
        return (Test-Path -LiteralPath $localDestPath)
    }
    elseif ($provider -eq "webdav") {
        $url = $settings.webdav.url.TrimEnd('/') + "/" + $remoteRelPath.TrimStart('/')
        $cred = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($settings.webdav.username):$($settings.webdav.password)"))
        $headers = @{ "Authorization" = "Basic $cred" }
        try {
            Invoke-WebRequest -Uri $url -Method Get -Headers $headers -OutFile $localDestPath -TimeoutSec 120 -UseBasicParsing | Out-Null
            return $true
        } catch {
            return $false
        }
    }
    return $false
}

function Storage-RemoteFileExists($remoteRelPath) {
    if ($provider -eq "local") {
        $dest = Join-Path $settings.localPath $remoteRelPath
        if (Test-Path -LiteralPath $dest) {
            $item = Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue
            return ($item -and $item.Length -gt 0)
        }
        return $false
    }
    elseif ($provider -eq "gdrive") {
        $loc = Resolve-GdriveLocation $remoteRelPath
        $parentId = $loc.ParentId
        $fileName = $loc.FileName
        $cacheKey = "$parentId/$fileName"
        if ($script:gdriveFileCache.ContainsKey($cacheKey)) {
            $item = $script:gdriveFileCache[$cacheKey]
            $sz = if ($item -is [hashtable]) { $item.size } else { 0 }
            return ($sz -gt 0)
        }
        return $false
    }
    return $false
}

function Storage-TestConnection() {
    if ($provider -eq "local") {
        $path = $settings.localPath
        if ([string]::IsNullOrWhiteSpace($path)) { throw "Local vault directory not specified." }
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        $vaultDir = Join-Path $path "vault"
        $saveDir = Join-Path $path "save"
        if (-not (Test-Path -LiteralPath $vaultDir)) { New-Item -ItemType Directory -Path $vaultDir -Force | Out-Null }
        if (-not (Test-Path -LiteralPath $saveDir)) { New-Item -ItemType Directory -Path $saveDir -Force | Out-Null }

        $testFile = Join-Path $path ".ignitools_test"
        [System.IO.File]::WriteAllText($testFile, "OK")
        Remove-Item -LiteralPath $testFile -Force
        return $true
    }
    elseif ($provider -eq "gdrive") {
        $token = Get-GdriveAccessToken
        if (-not $token) { throw "Unable to get Google Drive access token." }
        $loc = Resolve-GdriveLocation "vault_index.json"
        if (-not $loc.ParentId) { throw "Unable to initialize Ignitools folder in Google Drive." }
        return $true
    }
    elseif ($provider -eq "webdav") {
        $url = $settings.webdav.url.TrimEnd('/') + "/"
        $cred = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($settings.webdav.username):$($settings.webdav.password)"))
        $headers = @{ "Authorization" = "Basic $cred" }
        $res = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -TimeoutSec 15 -UseBasicParsing
        return ($res.StatusCode -ge 200 -and $res.StatusCode -lt 300)
    }
    throw "Unsupported provider: $provider"
}

# ── Index Management ─────────────────────────────────────────────────────────

function Get-VaultIndex() {
    $tempIndex = Join-Path $tempDir "vault_index_download.json"
    if (Test-Path $tempIndex) { Remove-Item $tempIndex -Force }
    $ok = Storage-GetFile "vault_index.json" $tempIndex
    if ($ok -and (Test-Path $tempIndex)) {
        try {
            $raw = Get-Content $tempIndex -Raw
            return ($raw | ConvertFrom-Json)
        } catch {}
    }
    return [PSCustomObject]@{
        version = 1
        updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        device = $env:COMPUTERNAME
        games = [PSCustomObject]@{}
    }
}

function Save-VaultIndex($indexObj) {
    $tempIndex = Join-Path $tempDir "vault_index_upload.json"
    $indexObj.updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $indexObj.device = $env:COMPUTERNAME
    $json = $indexObj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($tempIndex, $json, [System.Text.Encoding]::UTF8)
    Storage-PutFile $tempIndex "vault_index.json" | Out-Null
    if (Test-Path $tempIndex) { Remove-Item $tempIndex -Force }
}

# ── Packaging & Vaulting Logic ───────────────────────────────────────────────

function Backup-SingleGame($appId, [string]$title = "", [double]$ProgressBase = 0, [double]$ProgressSpan = 100, [string]$PrefixMsg = "", $VaultIndexRef = $null, [bool]$DeferIndexSave = $false) {
    $appId = "$appId".Trim()

    $ReportProgress = {
        param([double]$fraction, [string]$subMsg)
        $pct = [math]::Min(99, [math]::Max(5, [math]::Round($ProgressBase + ($fraction * $ProgressSpan))))
        $display = if ($PrefixMsg) { "$PrefixMsg - $subMsg" } else { $subMsg }
        Update-Status -Status "running" -Progress $pct -Message $display
    }

    & $ReportProgress 0.15 "Collecting manifests & config for $appId..."

    $workDir = Join-Path $tempDir "vault_pack_$appId"
    if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    $manifestFilesCount = 0
    $saveFilesCount = 0

    # 1. Package Manifests & Unlock Config
    if ($cfg.includeManifests -ne $false) {
        $manifestRemotePath = "vault/${appId}_manifests.zip"
        if ($action -eq "backup_all" -and (Storage-RemoteFileExists $manifestRemotePath)) {
            $manifestFilesCount = 1
            & $ReportProgress 0.60 "Verified in vault ($appId)"
        } else {
            $mDir = Join-Path $workDir "manifest_payload"
            New-Item -ItemType Directory -Path $mDir -Force | Out-Null

            # config/stplug-in/<appid>.lua
            $luaPath = Join-Path $steamPath "config\stplug-in\$appId.lua"
            if (Test-Path $luaPath) {
                $destLuaDir = Join-Path $mDir "stplug-in"
                New-Item -ItemType Directory -Path $destLuaDir -Force | Out-Null
                Copy-Item -LiteralPath $luaPath -Destination (Join-Path $destLuaDir "$appId.lua") -Force
                $manifestFilesCount++

                # Parse referenced depots from .lua to accurately collect matching manifests
                $luaContent = Get-Content $luaPath -Raw
                $depotIds = @()
                $matches = [regex]::Matches($luaContent, 'addappid\(\s*(\d+)')
                foreach ($m in $matches) { $depotIds += $m.Groups[1].Value }
                $depotIds = $depotIds | Select-Object -Unique

                $depotCache = Join-Path $steamPath "depotcache"
                if (Test-Path $depotCache) {
                    $destDepot = Join-Path $mDir "depotcache"
                    New-Item -ItemType Directory -Path $destDepot -Force | Out-Null
                    foreach ($did in $depotIds) {
                        Get-ChildItem -Path $depotCache -Filter "${did}_*.manifest" -File -ErrorAction SilentlyContinue | ForEach-Object {
                            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destDepot $_.Name) -Force
                            $manifestFilesCount++
                        }
                    }
                    Get-ChildItem -Path $depotCache -Filter "${appId}_*.manifest" -File -ErrorAction SilentlyContinue | ForEach-Object {
                        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destDepot $_.Name) -Force
                        $manifestFilesCount++
                    }
                }
            }

            # steamapps/appmanifest_<appid>.acf
            $acfPath = Join-Path $steamPath "steamapps\appmanifest_$appId.acf"
            if (Test-Path $acfPath) {
                $destAcf = Join-Path $mDir "steamapps"
                New-Item -ItemType Directory -Path $destAcf -Force | Out-Null
                Copy-Item -LiteralPath $acfPath -Destination (Join-Path $destAcf "appmanifest_$appId.acf") -Force
                $manifestFilesCount++
            }

            if ($manifestFilesCount -gt 0) {
                $zipManifest = Join-Path $workDir "${appId}_manifests.zip"
                [System.IO.Compression.ZipFile]::CreateFromDirectory($mDir, $zipManifest, [System.IO.Compression.CompressionLevel]::Fastest, $false)
                & $ReportProgress 0.60 "Syncing manifests for $appId..."
                $mRes = Storage-PutFile $zipManifest "vault/${appId}_manifests.zip"
                if ($mRes -and -not $mRes.skipped) {
                    Start-Sleep -Milliseconds 60
                }
            }
        }
    }

    # 2. Package Game Saves
    if ($cfg.includeSaves -ne $false) {
        $saveRemotePath = "save/${appId}_save.zip"
        if ($action -eq "backup_all" -and (Storage-RemoteFileExists $saveRemotePath)) {
            $saveFilesCount = 1
            & $ReportProgress 0.85 "Saves verified in vault ($appId)"
        } else {
            $sDir = Join-Path $workDir "save_payload"
            New-Item -ItemType Directory -Path $sDir -Force | Out-Null

            # Steam userdata
            $userdata = Join-Path $steamPath "userdata"
            if (Test-Path $userdata) {
                Get-ChildItem -Path $userdata -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $accId = $_.Name
                    $appSaveDir = Join-Path $_.FullName $appId
                    if (Test-Path $appSaveDir) {
                        $dest = Join-Path $sDir "userdata\$accId\$appId"
                        New-Item -ItemType Directory -Path $dest -Force | Out-Null
                        Copy-Item -Path "$appSaveDir\*" -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
                        $saveFilesCount++
                    }
                }
            }

            # Common external save locations (AppData, Saved Games, Documents)
            $externalCandidates = @(
                (Join-Path $env:LOCALAPPDATA $appId),
                (Join-Path $env:APPDATA $appId)
            )
            if ($title) {
                $cleanTitle = $title -replace '[^\w\s-]', ''
                $externalCandidates += (Join-Path (Join-Path $env:USERPROFILE "Saved Games") $cleanTitle)
                $externalCandidates += (Join-Path (Join-Path $env:USERPROFILE "Documents\My Games") $cleanTitle)
                $externalCandidates += (Join-Path $env:LOCALAPPDATA $cleanTitle)
            }
            foreach ($c in $externalCandidates) {
                if ($c -and (Test-Path -LiteralPath $c)) {
                    $folderName = Split-Path $c -Leaf
                    $dest = Join-Path $sDir "external\$folderName"
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    Copy-Item -Path "$c\*" -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
                    $saveFilesCount++
                }
            }

            if ($saveFilesCount -gt 0) {
                $zipSave = Join-Path $workDir "${appId}_save.zip"
                [System.IO.Compression.ZipFile]::CreateFromDirectory($sDir, $zipSave, [System.IO.Compression.CompressionLevel]::Fastest, $false)
                & $ReportProgress 0.85 "Syncing game saves for $appId..."
                $sRes = Storage-PutFile $zipSave "save/${appId}_save.zip"
                if ($sRes -and -not $sRes.skipped) {
                    Start-Sleep -Milliseconds 60
                }
            }
        }
    }

    # 3. Update Vault Index
    $index = if ($VaultIndexRef) { $VaultIndexRef } else { Get-VaultIndex }
    if (-not $index.games.$appId) {
        $index.games | Add-Member -MemberType NoteProperty -Name $appId -Value ([PSCustomObject]@{}) -Force
    }
    $gameObj = $index.games.$appId
    if ($title) { $gameObj | Add-Member -MemberType NoteProperty -Name "title" -Value $title -Force }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($manifestFilesCount -gt 0) {
        $gameObj | Add-Member -MemberType NoteProperty -Name "manifestVault" -Value ([PSCustomObject]@{ updatedAt = $now; files = $manifestFilesCount }) -Force
    }
    if ($saveFilesCount -gt 0) {
        $gameObj | Add-Member -MemberType NoteProperty -Name "saveVault" -Value ([PSCustomObject]@{ updatedAt = $now; files = $saveFilesCount }) -Force
    }
    if (-not $DeferIndexSave) {
        Save-VaultIndex $index
    }

    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue

    return @{
        appId = $appId
        manifestFiles = $manifestFilesCount
        saveFiles = $saveFilesCount
    }
}

function Restore-SingleGame($appId, [double]$ProgressBase = 0, [double]$ProgressSpan = 100, [string]$PrefixMsg = "") {
    $appId = "$appId".Trim()

    $ReportProgress = {
        param([double]$fraction, [string]$subMsg)
        $pct = [math]::Min(99, [math]::Max(5, [math]::Round($ProgressBase + ($fraction * $ProgressSpan))))
        $display = if ($PrefixMsg) { "$PrefixMsg - $subMsg" } else { $subMsg }
        Update-Status -Status "running" -Progress $pct -Message $display
    }

    & $ReportProgress 0.25 "Downloading bundle for $appId..."

    $workDir = Join-Path $tempDir "vault_unpack_$appId"
    if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    $restoredManifests = 0
    $restoredSaves = 0

    # 1. Restore Manifests & Config
    $localManifestZip = Join-Path $workDir "${appId}_manifests.zip"
    $gotManifest = Storage-GetFile "vault/${appId}_manifests.zip" $localManifestZip
    if (-not $gotManifest) {
        $gotManifest = Storage-GetFile "manifests/${appId}_manifests.zip" $localManifestZip
    }
    if ($gotManifest) {
        & $ReportProgress 0.65 "Restoring manifests for $appId..."
        $mExtract = Join-Path $workDir "manifest_extract"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($localManifestZip, $mExtract)

        # Restore stplug-in
        $srcLua = Join-Path $mExtract "stplug-in\$appId.lua"
        if (Test-Path $srcLua) {
            $destLuaDir = Join-Path $steamPath "config\stplug-in"
            if (-not (Test-Path $destLuaDir)) { New-Item -ItemType Directory -Path $destLuaDir -Force | Out-Null }
            Copy-Item -LiteralPath $srcLua -Destination (Join-Path $destLuaDir "$appId.lua") -Force
            $restoredManifests++
        }

        # Restore depotcache
        $srcDepot = Join-Path $mExtract "depotcache"
        if (Test-Path $srcDepot) {
            $destDepot = Join-Path $steamPath "depotcache"
            if (-not (Test-Path $destDepot)) { New-Item -ItemType Directory -Path $destDepot -Force | Out-Null }
            Get-ChildItem -Path $srcDepot -File | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destDepot $_.Name) -Force
                $restoredManifests++
            }
        }

        # Restore steamapps acf
        $srcAcf = Join-Path $mExtract "steamapps\appmanifest_$appId.acf"
        if (Test-Path $srcAcf) {
            $destSteamapps = Join-Path $steamPath "steamapps"
            if (-not (Test-Path $destSteamapps)) { New-Item -ItemType Directory -Path $destSteamapps -Force | Out-Null }
            Copy-Item -LiteralPath $srcAcf -Destination (Join-Path $destSteamapps "appmanifest_$appId.acf") -Force
            $restoredManifests++
        }
    }

    # 2. Restore Game Saves
    $localSaveZip = Join-Path $workDir "${appId}_save.zip"
    $gotSave = Storage-GetFile "save/${appId}_save.zip" $localSaveZip
    if (-not $gotSave) {
        $gotSave = Storage-GetFile "saves/${appId}_save.zip" $localSaveZip
    }
    if ($gotSave) {
        & $ReportProgress 0.85 "Restoring saves for $appId..."
        $sExtract = Join-Path $workDir "save_extract"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($localSaveZip, $sExtract)

        # Restore userdata
        $srcUserdata = Join-Path $sExtract "userdata"
        if (Test-Path $srcUserdata) {
            Get-ChildItem -Path $srcUserdata -Directory | ForEach-Object {
                $accId = $_.Name
                $destApp = Join-Path (Join-Path $steamPath "userdata\$accId") $appId
                if (-not (Test-Path $destApp)) { New-Item -ItemType Directory -Path $destApp -Force | Out-Null }
                Copy-Item -Path "$($_.FullName)\$appId\*" -Destination $destApp -Recurse -Force -ErrorAction SilentlyContinue
                $restoredSaves++
            }
        }
    }

    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue

    return @{
        appId = $appId
        manifests = $restoredManifests
        saves = $restoredSaves
    }
}

# ── Main Action Router ───────────────────────────────────────────────────────

try {
    switch ($action) {
        "test_connection" {
            Update-Status -Status "running" -Progress 50 -Message "Testing connection to $provider..."
            $ok = Storage-TestConnection
            if ($ok) {
                Update-Status -Status "completed" -Progress 100 -Message "Connection successful!"
            } else {
                Update-Status -Status "failed" -Progress 100 -ErrorMsg "Connection check returned false."
            }
        }

        "backup_game" {
            $gameTitle = if ($cfg.title) { $cfg.title } else { "" }
            $res = Backup-SingleGame -appId $cfg.appid -title $gameTitle
            Update-Status -Status "completed" -Progress 100 -Message "Game $($cfg.appid) vaulted successfully" -Data $res
        }

        "restore_game" {
            $res = Restore-SingleGame -appId $cfg.appid
            Update-Status -Status "completed" -Progress 100 -Message "Game $($cfg.appid) restored successfully" -Data $res
        }

        "backup_all" {
            Update-Status -Status "running" -Progress 5 -Message "Scanning unlocked library..."
            $luaDir = Join-Path $steamPath "config\stplug-in"
            $games = @()
            if (Test-Path $luaDir) {
                Get-ChildItem -Path $luaDir -Filter "*.lua" | ForEach-Object {
                    if ($_.Name -match '^(\d+)\.lua$') {
                        $games += $matches[1]
                    }
                }
            }
            $total = $games.Count
            if ($total -eq 0) {
                Update-Status -Status "completed" -Progress 100 -Message "No unlocked games found to vault." -Data @{ count = 0; games = @() }
                return
            }

            # Validate connection & pre-warm Google Drive caches to avoid rate-limiting
            if ($provider -eq "gdrive") {
                try {
                    Update-Status -Status "running" -Progress 5 -Message "Authenticating with Google Drive..."
                    $null = Get-GdriveAccessToken
                    Update-Status -Status "running" -Progress 6 -Message "Indexing existing files on Google Drive..."
                    $pmtoolsId = Get-OrCreateDriveFolder "Pmtools" "root"
                    $vaultId = Get-OrCreateDriveFolder "vault" $pmtoolsId
                    $saveId = Get-OrCreateDriveFolder "save" $pmtoolsId
                    Populate-DriveFolderCache $vaultId
                    Populate-DriveFolderCache $saveId
                } catch {
                    Update-Status -Status "failed" -Progress 100 -ErrorMsg "Google Drive initialization failed: $($_.Exception.Message)"
                    return
                }
            }

            # Optional: resolve titles from titles_cache.json for friendly progress messages
            $titlesCache = @{}
            $titlesFile = Join-Path $steamPath "pmtools\titles_cache.json"
            if (Test-Path $titlesFile) {
                try {
                    $json = Get-Content $titlesFile -Raw | ConvertFrom-Json
                    foreach ($prop in $json.PSObject.Properties) {
                        $titlesCache[$prop.Name] = $prop.Value
                    }
                } catch {}
            }

            $spanPerGame = 90.0 / $total
            $curr = 0
            $successCount = 0
            $failCount = 0
            $backedUp = @()
            $index = Get-VaultIndex
            $maxWorkers = 6
            $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $maxWorkers)
            $pool.Open()

            $remoteCacheSync = [hashtable]::Synchronized($script:gdriveFileCache)
            $gdriveToken = if ($provider -eq "gdrive") { Get-GdriveAccessToken } else { "" }
            $locPath = if ($provider -eq "local") { $settings.localPath } else { "" }

            $context = @{
                SteamPath        = $steamPath
                TempDir          = $tempDir
                Provider         = $provider
                Token            = $gdriveToken
                VaultId          = $vaultId
                SaveId           = $saveId
                FileCache        = $remoteCacheSync
                LocalPath        = $locPath
                IncludeManifests = ($cfg.includeManifests -ne $false)
                IncludeSaves     = ($cfg.includeSaves -ne $false)
            }

            $workerScript = {
                param($item, $ctx)

                Add-Type -AssemblyName "System.IO.Compression.FileSystem" -ErrorAction SilentlyContinue
                Add-Type -AssemblyName "System.IO.Compression" -ErrorAction SilentlyContinue
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
                [System.Net.ServicePointManager]::DefaultConnectionLimit = 64

                $appId = $item.AppId
                $title = $item.Title
                $steamPath = $ctx.SteamPath
                $tempDir = $ctx.TempDir
                $provider = $ctx.Provider
                $token = $ctx.Token
                $vaultId = $ctx.VaultId
                $saveId = $ctx.SaveId
                $fileCache = $ctx.FileCache
                $localPath = $ctx.LocalPath

                $manifestCount = 0
                $saveCount = 0

                $guid = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
                $workDir = Join-Path $tempDir "vp_${appId}_${guid}"
                New-Item -ItemType Directory -Path $workDir -Force | Out-Null

                try {
                    # 1. Package & Upload Manifests
                    if ($ctx.IncludeManifests) {
                        $manifestRemoteKey = "$vaultId/${appId}_manifests.zip"
                        if ($provider -eq "gdrive" -and $fileCache.ContainsKey($manifestRemoteKey) -and $fileCache[$manifestRemoteKey].size -gt 0) {
                            $manifestCount = 1
                        } elseif ($provider -eq "local" -and (Test-Path -LiteralPath (Join-Path $localPath "vault\${appId}_manifests.zip"))) {
                            $manifestCount = 1
                        } else {
                            $mDir = Join-Path $workDir "manifest_payload"
                            New-Item -ItemType Directory -Path $mDir -Force | Out-Null

                            $luaPath = Join-Path $steamPath "config\stplug-in\$appId.lua"
                            if (Test-Path $luaPath) {
                                $destLuaDir = Join-Path $mDir "stplug-in"
                                New-Item -ItemType Directory -Path $destLuaDir -Force | Out-Null
                                Copy-Item -LiteralPath $luaPath -Destination (Join-Path $destLuaDir "$appId.lua") -Force
                                $manifestCount++

                                $luaContent = Get-Content $luaPath -Raw
                                $depotIds = @()
                                $matches = [regex]::Matches($luaContent, 'addappid\(\s*(\d+)')
                                foreach ($m in $matches) { $depotIds += $m.Groups[1].Value }
                                $depotIds = $depotIds | Select-Object -Unique

                                $depotCache = Join-Path $steamPath "depotcache"
                                if (Test-Path $depotCache) {
                                    $destDepot = Join-Path $mDir "depotcache"
                                    New-Item -ItemType Directory -Path $destDepot -Force | Out-Null
                                    foreach ($did in $depotIds) {
                                        Get-ChildItem -Path $depotCache -Filter "${did}_*.manifest" -File -ErrorAction SilentlyContinue | ForEach-Object {
                                            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destDepot $_.Name) -Force
                                            $manifestCount++
                                        }
                                    }
                                    Get-ChildItem -Path $depotCache -Filter "${appId}_*.manifest" -File -ErrorAction SilentlyContinue | ForEach-Object {
                                        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destDepot $_.Name) -Force
                                        $manifestCount++
                                    }
                                }
                            }

                            $acfPath = Join-Path $steamPath "steamapps\appmanifest_$appId.acf"
                            if (Test-Path $acfPath) {
                                $destAcf = Join-Path $mDir "steamapps"
                                New-Item -ItemType Directory -Path $destAcf -Force | Out-Null
                                Copy-Item -LiteralPath $acfPath -Destination (Join-Path $destAcf "appmanifest_$appId.acf") -Force
                                $manifestCount++
                            }

                            if ($manifestCount -gt 0) {
                                $zipManifest = Join-Path $workDir "${appId}_manifests.zip"
                                [System.IO.Compression.ZipFile]::CreateFromDirectory($mDir, $zipManifest, [System.IO.Compression.CompressionLevel]::Fastest, $false)
                                $localSize = (Get-Item -LiteralPath $zipManifest).Length

                                if ($provider -eq "gdrive") {
                                    $boundary = [System.Guid]::NewGuid().ToString()
                                    $LF = "`r`n"
                                    $metaJson = @{ name = "${appId}_manifests.zip"; parents = @($vaultId) } | ConvertTo-Json -Compress
                                    $headBytes = [System.Text.Encoding]::UTF8.GetBytes("--$boundary$LF" + "Content-Type: application/json; charset=UTF-8$LF$LF" + "$metaJson$LF" + "--$boundary$LF" + "Content-Type: application/octet-stream$LF$LF")
                                    $fileBytes = [System.IO.File]::ReadAllBytes($zipManifest)
                                    $endBytes = [System.Text.Encoding]::UTF8.GetBytes("$LF--$boundary--$LF")
                                    $ms = New-Object System.IO.MemoryStream
                                    $ms.Write($headBytes, 0, $headBytes.Length)
                                    $ms.Write($fileBytes, 0, $fileBytes.Length)
                                    $ms.Write($endBytes, 0, $endBytes.Length)
                                    $payload = $ms.ToArray()
                                    $ms.Dispose()

                                    $uploadUri = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
                                    $uploadHeaders = @{ "Authorization" = "Bearer $token" }
                                    for ($attempt = 0; $attempt -lt 4; $attempt++) {
                                        try {
                                            $uRes = Invoke-RestMethod -Uri $uploadUri -Method Post -Headers $uploadHeaders -Body $payload -ContentType "multipart/related; boundary=$boundary" -TimeoutSec 120
                                            if ($uRes -and $uRes.id) {
                                                $fileCache[$manifestRemoteKey] = @{ id = $uRes.id; size = $localSize }
                                                break
                                            }
                                        } catch {
                                            if ($attempt -ge 3) { throw }
                                            Start-Sleep -Seconds (5 * ($attempt + 1))
                                        }
                                    }
                                } elseif ($provider -eq "local") {
                                    $destPath = Join-Path $localPath "vault\${appId}_manifests.zip"
                                    $destDir = Split-Path $destPath -Parent
                                    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                                    Copy-Item -LiteralPath $zipManifest -Destination $destPath -Force
                                    $fileCache[$manifestRemoteKey] = @{ id = $destPath; size = $localSize }
                                }
                            }
                        }
                    }

                    # 2. Package & Upload Saves
                    if ($ctx.IncludeSaves) {
                        $saveRemoteKey = "$saveId/${appId}_save.zip"
                        if ($provider -eq "gdrive" -and $fileCache.ContainsKey($saveRemoteKey) -and $fileCache[$saveRemoteKey].size -gt 0) {
                            $saveCount = 1
                        } elseif ($provider -eq "local" -and (Test-Path -LiteralPath (Join-Path $localPath "save\${appId}_save.zip"))) {
                            $saveCount = 1
                        } else {
                            $sDir = Join-Path $workDir "save_payload"
                            New-Item -ItemType Directory -Path $sDir -Force | Out-Null

                            $userdata = Join-Path $steamPath "userdata"
                            if (Test-Path $userdata) {
                                Get-ChildItem -Path $userdata -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                                    $accId = $_.Name
                                    $appSaveDir = Join-Path $_.FullName $appId
                                    if (Test-Path $appSaveDir) {
                                        $dest = Join-Path $sDir "userdata\$accId\$appId"
                                        New-Item -ItemType Directory -Path $dest -Force | Out-Null
                                        Copy-Item -Path "$appSaveDir\*" -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
                                        $saveCount++
                                    }
                                }
                            }

                            $externalCandidates = @(
                                (Join-Path $env:LOCALAPPDATA $appId),
                                (Join-Path $env:APPDATA $appId)
                            )
                            if ($title) {
                                $cleanTitle = $title -replace '[^\w\s-]', ''
                                $externalCandidates += (Join-Path (Join-Path $env:USERPROFILE "Saved Games") $cleanTitle)
                                $externalCandidates += (Join-Path (Join-Path $env:USERPROFILE "Documents\My Games") $cleanTitle)
                                $externalCandidates += (Join-Path $env:LOCALAPPDATA $cleanTitle)
                            }
                            foreach ($c in $externalCandidates) {
                                if ($c -and (Test-Path -LiteralPath $c)) {
                                    $folderName = Split-Path $c -Leaf
                                    $dest = Join-Path $sDir "external\$folderName"
                                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                                    Copy-Item -Path "$c\*" -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
                                    $saveCount++
                                }
                            }

                            if ($saveCount -gt 0) {
                                $zipSave = Join-Path $workDir "${appId}_save.zip"
                                [System.IO.Compression.ZipFile]::CreateFromDirectory($sDir, $zipSave, [System.IO.Compression.CompressionLevel]::Fastest, $false)
                                $localSaveSize = (Get-Item -LiteralPath $zipSave).Length

                                if ($provider -eq "gdrive") {
                                    $boundary = [System.Guid]::NewGuid().ToString()
                                    $LF = "`r`n"
                                    $metaJson = @{ name = "${appId}_save.zip"; parents = @($saveId) } | ConvertTo-Json -Compress
                                    $headBytes = [System.Text.Encoding]::UTF8.GetBytes("--$boundary$LF" + "Content-Type: application/json; charset=UTF-8$LF$LF" + "$metaJson$LF" + "--$boundary$LF" + "Content-Type: application/octet-stream$LF$LF")
                                    $fileBytes = [System.IO.File]::ReadAllBytes($zipSave)
                                    $endBytes = [System.Text.Encoding]::UTF8.GetBytes("$LF--$boundary--$LF")
                                    $ms = New-Object System.IO.MemoryStream
                                    $ms.Write($headBytes, 0, $headBytes.Length)
                                    $ms.Write($fileBytes, 0, $fileBytes.Length)
                                    $ms.Write($endBytes, 0, $endBytes.Length)
                                    $payload = $ms.ToArray()
                                    $ms.Dispose()

                                    $uploadUri = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
                                    $uploadHeaders = @{ "Authorization" = "Bearer $token" }
                                    for ($attempt = 0; $attempt -lt 4; $attempt++) {
                                        try {
                                            $uRes = Invoke-RestMethod -Uri $uploadUri -Method Post -Headers $uploadHeaders -Body $payload -ContentType "multipart/related; boundary=$boundary" -TimeoutSec 120
                                            if ($uRes -and $uRes.id) {
                                                $fileCache[$saveRemoteKey] = @{ id = $uRes.id; size = $localSaveSize }
                                                break
                                            }
                                        } catch {
                                            if ($attempt -ge 3) { throw }
                                            Start-Sleep -Seconds (5 * ($attempt + 1))
                                        }
                                    }
                                } elseif ($provider -eq "local") {
                                    $destPath = Join-Path $localPath "save\${appId}_save.zip"
                                    $destDir = Split-Path $destPath -Parent
                                    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                                    Copy-Item -LiteralPath $zipSave -Destination $destPath -Force
                                    $fileCache[$saveRemoteKey] = @{ id = $destPath; size = $localSaveSize }
                                }
                            }
                        }
                    }

                    return @{
                        appId     = $appId
                        title     = $title
                        manifests = $manifestCount
                        saves     = $saveCount
                        ok        = $true
                    }
                }
                catch {
                    return @{
                        appId     = $appId
                        title     = $title
                        manifests = 0
                        saves     = 0
                        ok        = $false
                        error     = $_.Exception.Message
                    }
                }
                finally {
                    if (Test-Path $workDir) {
                        Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            # Queue all items
            $queue = [System.Collections.Queue]::new()
            foreach ($gid in $games) {
                $gameTitle = if ($titlesCache.ContainsKey($gid)) { $titlesCache[$gid] } else { "" }
                $queue.Enqueue(@{ AppId = $gid; Title = $gameTitle })
            }

            $activeTasks = [System.Collections.ArrayList]::new()
            $completedCount = 0
            $successCount = 0
            $failCount = 0
            $backedUp = @()

            while ($queue.Count -gt 0 -or $activeTasks.Count -gt 0) {
                while ($activeTasks.Count -lt $maxWorkers -and $queue.Count -gt 0) {
                    $item = $queue.Dequeue()
                    $ps = [powershell]::Create()
                    $ps.RunspacePool = $pool
                    [void]$ps.AddScript($workerScript)
                    [void]$ps.AddArgument($item)
                    [void]$ps.AddArgument($context)
                    $handle = $ps.BeginInvoke()
                    $label = if ($item.Title) { "$($item.Title) ($($item.AppId))" } else { "AppID $($item.AppId)" }
                    [void]$activeTasks.Add(@{ PS = $ps; Handle = $handle; Item = $item; Label = $label })
                }

                $toRemove = @()
                foreach ($t in $activeTasks) {
                    if ($t.Handle.IsCompleted) {
                        try {
                            $out = $t.PS.EndInvoke($t.Handle)
                            $r = if ($out -is [System.Collections.IList] -and $out.Count -gt 0) { $out[0] } else { $out }
                            $isOk = ($r -and ($r.ok -eq $true -or $r.ok -eq "True" -or $r['ok'] -eq $true))
                            if ($isOk) {
                                $successCount++
                                $backedUp += $r
                                try {
                                    $gObj = [PSCustomObject]@{
                                        title     = $r.title
                                        updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                                        manifests = ($r.manifests -gt 0)
                                        saves     = ($r.saves -gt 0)
                                    }
                                    if ($index.games -is [System.Management.Automation.PSCustomObject]) {
                                        $index.games | Add-Member -MemberType NoteProperty -Name ([string]$r.appId) -Value $gObj -Force
                                    } elseif ($index.games -is [System.Collections.IDictionary]) {
                                        $index.games[[string]$r.appId] = $gObj
                                    }
                                } catch {}
                            } else {
                                $failCount++
                            }
                        } catch {
                            $failCount++
                        } finally {
                            $t.PS.Dispose()
                            $toRemove += $t
                            $completedCount++
                            $pct = [math]::Min(99, [math]::Max(5, [math]::Round(5.0 + (($completedCount / $total) * 90.0))))
                            Update-Status -Status "running" -Progress $pct -Message "[$completedCount/$total] Vaulted $($t.Label)"
                        }
                    }
                }

                foreach ($rem in $toRemove) {
                    $activeTasks.Remove($rem)
                }

                if ($toRemove.Count -eq 0) {
                    Start-Sleep -Milliseconds 40
                }
            }

            $pool.Close()
            $pool.Dispose()

            try {
                Save-VaultIndex $index
            } catch {}

            $finalMsg = if ($failCount -gt 0) {
                "Vaulted $successCount games ($failCount skipped/failed)."
            } else {
                "Vaulted all $successCount games to personal storage."
            }
            Update-Status -Status "completed" -Progress 100 -Message $finalMsg -Data @{ count = $successCount; failed = $failCount; games = $backedUp }
        }

        "restore_all" {
            Update-Status -Status "running" -Progress 5 -Message "Fetching vault index from storage..."
            if ($provider -eq "gdrive") {
                try {
                    $null = Get-GdriveAccessToken
                    $pmtoolsId = Get-OrCreateDriveFolder "Pmtools" "root"
                    $vaultId = Get-OrCreateDriveFolder "vault" $pmtoolsId
                    $saveId = Get-OrCreateDriveFolder "save" $pmtoolsId
                    Populate-DriveFolderCache $vaultId
                    Populate-DriveFolderCache $saveId
                } catch {
                    Update-Status -Status "failed" -Progress 100 -ErrorMsg "Google Drive initialization failed: $($_.Exception.Message)"
                    return
                }
            }

            $index = Get-VaultIndex
            $gameIds = @()
            if ($index.games) {
                $gameIds = @($index.games.PSObject.Properties | Select-Object -ExpandProperty Name)
            }
            $total = $gameIds.Count
            if ($total -eq 0) {
                Update-Status -Status "completed" -Progress 100 -Message "No games found in vault." -Data @{ count = 0; games = @() }
                return
            }

            $spanPerGame = 90.0 / $total
            $curr = 0
            $successCount = 0
            $failCount = 0
            $restored = @()
            foreach ($gid in $gameIds) {
                $base = 5.0 + ($curr * $spanPerGame)
                $curr++
                $gameTitle = if ($index.games.$gid.title) { $index.games.$gid.title } else { "" }
                $label = if ($gameTitle) { "$gameTitle ($gid)" } else { "AppID $gid" }
                $prefix = "[$curr/$total] $label"
                try {
                    $r = Restore-SingleGame -appId $gid -ProgressBase $base -ProgressSpan $spanPerGame -PrefixMsg $prefix
                    $restored += $r
                    $successCount++
                } catch {
                    $failCount++
                }
                Start-Sleep -Milliseconds 40
            }

            $finalMsg = if ($failCount -gt 0) {
                "Restored $successCount games ($failCount skipped/failed)."
            } else {
                "Restored all $successCount games from personal vault."
            }
            Update-Status -Status "completed" -Progress 100 -Message $finalMsg -Data @{ count = $successCount; failed = $failCount; games = $restored }
        }

        "get_index" {
            $index = Get-VaultIndex
            Update-Status -Status "completed" -Progress 100 -Message "Index retrieved" -Data $index
        }

        default {
            throw "Unknown action: $action"
        }
    }
}
catch {
    Update-Status -Status "failed" -Progress 100 -ErrorMsg $_.Exception.Message
    exit 1
}
