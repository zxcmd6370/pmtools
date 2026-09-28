# Ignitools — apply an unlock WITHOUT restarting Steam, entirely standalone.
#
# This is the fallback path that needs NEITHER Millennium NOR the loader:
#   * Millennium  -> not used at all. Steam path comes from the registry, the
#                    apply is driven over Steam's OWN devtools CDP (port 8080,
#                    steamwebhelper), and the result is written to a JSON file.
#   * Loader      -> optional. If a hot-reloading loader is installed it has
#                    already applied the new stplug-in script by itself; this
#                    script just CONFIRMS via GetIsSubscribedApp. If no loader
#                    exists, it drives the offline->online cycle so Steam
#                    re-syncs licenses and picks up the staged lua.
#
# Usage (anywhere, no Millennium, no Lua VM):
#   powershell -NoProfile -ExecutionPolicy Bypass -File apply_no_restart.ps1
#       -AppId 440 [-SteamPath "C:\Program Files (x86)\Steam"]
#       [-MarkerFile "...\440_apply.json"] [-Port 8080]
#
# Result file (MarkerFile): {"applied":true} or {"applied":false,"error":"..."}

param(
    [Parameter(Mandatory = $true)][string]$AppId,
    [string]$SteamPath = "",
    [string]$MarkerFile = "",
    [string]$Port = "8080"
)

$ErrorActionPreference = "Stop"

if (-not $MarkerFile) {
    $MarkerFile = Join-Path $env:TEMP ("pmtools_apply_" + $AppId + ".json")
}

function Write-Marker($obj) {
    try { Set-Content -Path $MarkerFile -Value ($obj | ConvertTo-Json -Compress) } catch {}
}

function Get-SteamPath {
    if ($SteamPath -and (Test-Path $SteamPath)) { return $SteamPath }
    try {
        $p = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
        if ($p -and (Test-Path $p)) { return $p }
    } catch {}
    return ""
}

function Send-CdpEval($ws, $expr, $id) {
    $msg = @{ id = $id; method = "Runtime.evaluate"; params = @{ expression = $expr; returnByValue = $true; awaitPromise = $true } } | ConvertTo-Json -Compress -Depth 5
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $seg = [System.ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()
    $buf = New-Object byte[] 131072
    $recvSeg = [System.ArraySegment[byte]]::new($buf)
    $res = $ws.ReceiveAsync($recvSeg, [System.Threading.CancellationToken]::None).Result
    return [System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)
}

function Find-Target {
    $candidates = @($Port, "9222", "9229", "8081", "8082", "8083", "8084", "8085", "8086")
    foreach ($p in $candidates) {
        try {
            $json = Invoke-RestMethod -Uri "http://127.0.0.1:$p/json" -TimeoutSec 2
            $target = $json | Where-Object { $_.title -eq "SharedJSContext" -or ($_.url -like "*steamloopback*") } | Select-Object -First 1
            if ($target) { return $target, $p }
        } catch {}
    }
    return $null, $null
}

# A hot-reloading loader (Ignitools/OpenSteamTool/BetterSteamTools) is present
# when the Steam root carries the full file set AND a toml whose [lua] section
# points at config/stplug-in. Mirrors installer.lua's loader_health().
function Test-LoaderCapable($steamPath) {
    if (-not $steamPath) { return $false }
    $main = Join-Path $steamPath "pmtoolstools.dll"
    if (-not (Test-Path $main)) { $main = Join-Path $steamPath "OpenSteamTool.dll" }
    if (-not (Test-Path $main)) { return $false }
    foreach ($d in @("dwmapi.dll", "xinput1_4.dll")) {
        if (-not (Test-Path (Join-Path $steamPath $d))) { return $false }
    }
    $toml = Join-Path $steamPath "pmtools.toml"
    if (-not (Test-Path $toml)) { $toml = Join-Path $steamPath "opensteamtool.toml" }
    if (-not (Test-Path $toml)) { return $false }
    $content = Get-Content $toml -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return $false }
    return ($content -match '\[lua\]' -and $content -match 'stplug-in')
}

try {
    $sp = Get-SteamPath
    Write-Host "[Pmtools] Steam path: $sp"

    $target, $usedPort = Find-Target
    if (-not $target) { throw "Steam CDP not reachable (is Steam running?)" }
    Write-Host "[Pmtools] Steam CDP on port $usedPort"

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, [System.Threading.CancellationToken]::None).Wait()

    $apiProbe = Send-CdpEval $ws "typeof SteamClient === 'undefined' || !SteamClient.User ? 'missing' : 'ok'" 0
    if ($apiProbe -match '"missing"') { throw "SteamClient.User not available in CDP context" }

    $loaderCapable = Test-LoaderCapable $sp
    Write-Host "[Pmtools] hot-reloading loader: $loaderCapable"

    if (-not $loaderCapable) {
        # No loader — drive a fast offline->online cycle (1.5s vs old 6s).
        Write-Host "[Pmtools] fast offline->online cycle..."
        Send-CdpEval $ws "SteamClient.User.GoOffline()" 1 | Out-Null
        Start-Sleep -Seconds 1.5
        Send-CdpEval $ws "SteamClient.User.GoOnline()" 3 | Out-Null
    } else {
        # The loader hot-reloads instantly; skip the wait entirely.
        Write-Host "[Pmtools] loader detected — instant apply"
    }

    # Confirm via the real subscription API (loader patches it, and the
    # offline->online re-sync also flips it once the script is registered).
    $expr = "typeof SteamClient !== 'undefined' && SteamClient.Apps && typeof SteamClient.Apps.GetIsSubscribedApp === 'function' ? SteamClient.Apps.GetIsSubscribedApp($AppId) : null"
    $subscribed = $false
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        $probe = Send-CdpEval $ws $expr 5
        if ($probe -match '"value"\s*:\s*true') { $subscribed = $true; break }
    }
    if (-not $subscribed) { throw "app $AppId not subscribed after apply" }

    try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", [System.Threading.CancellationToken]::None).Wait() } catch {}
    Write-Marker @{ applied = $true }
    Write-Host "[Pmtools] applied: $AppId confirmed subscribed"
}
catch {
    Write-Marker @{ applied = $false; error = $_.Exception.Message }
    Write-Host "[Pmtools] FAILED: $($_.Exception.Message)"
    exit 1
}
