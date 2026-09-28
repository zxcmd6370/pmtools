# Ignitools — apply an unlock without restarting Steam (fallback path, used
# when no hot-reloading loader watcher is installed).
#
# Steam only re-reads stplug-in scripts when it re-syncs licenses, which the
# client does when it comes back online. The manual trick is: Steam menu ->
# Go Offline -> Go Online. The root menu itself just calls
# SteamClient.User.GoOffline() / GoOnline() in the client's SharedJSContext
# (verified in steamui/chunk~2dcc5aaf7.js). This script drives the exact same
# calls over Steam's OWN CDP endpoint (the steamwebhelper devtools port, 8080
# by default — NOT a Millennium service; Millennium just connects to the same
# port), so the unlock applies in place.
#
# This script is fully standalone: it needs only a running Steam client with
# its devtools port reachable. It does NOT require Millennium, the plugin's
# Lua backend, or the loader. You can run it by hand:
#   powershell -NoProfile -ExecutionPolicy Bypass -File apply_offline_online.ps1
#       -AppId 440 -SteamPath "C:\Program Files (x86)\Steam" [-Port 8080]
#       [-MarkerFile "...\_apply.json"]
#
# This is the most fragile line in the codebase (Steam's PRIVATE UI JS API,
# which changes with client updates), so every step is guarded:
#   * SteamClient availability is checked before any call.
#   * Success is CONFIRMED via SteamClient.Apps.GetIsSubscribedApp(appid) —
#     the async call is awaited, and it only turns true once the re-sync
#     (i.e. coming back online) has picked up the new stplug-in script.
#   * Note: this Steam version has no public offline-state getter, so the
#     offline transition is given a fixed settle window instead of polled.
# On any failure the marker gets {"applied":false,"error":...} and the backend
# surfaces the Restart Steam button as the recovery path.
#
# Writes {"applied":true} to the marker file on success, or
# {"applied":false,"error":"..."} on failure.

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

function Send-CdpEval($ws, $expr, $id) {
    # awaitPromise: GetIsSubscribedApp is async — without it we'd get a Promise
    # object back, never a boolean.
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
    # Steam's own devtools port is 8080 (steamwebhelper launches with
    # --remote-debugging-port=8080). Scan a few common alternatives too, in
    # case a future Steam version moves it.
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

try {
    # Sanity: if a SteamPath was given, make sure the app's lua is actually
    # staged before we bounce Steam's connection — no point going offline for
    # a script that isn't there.
    if ($SteamPath -and (Test-Path $SteamPath)) {
        $luaFile = Join-Path $SteamPath ("config\stplug-in\" + $AppId + ".lua")
        if (-not (Test-Path $luaFile)) {
            Write-Host "[Pmtools] warn: $luaFile not found; continuing anyway (loader may serve it from elsewhere)"
        }
    }

    $target, $usedPort = Find-Target
    if (-not $target) { throw "Steam CDP endpoint not reachable (is Steam running with devtools?)" }
    Write-Host "[Pmtools] connected to Steam CDP on port $usedPort"

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, [System.Threading.CancellationToken]::None).Wait()

    # Guard: Steam's internal API is what we're driving — if it's absent the
    # context is wrong and every call would silently no-op. Fail loudly.
    $apiProbe = Send-CdpEval $ws "typeof SteamClient === 'undefined' || !SteamClient.User ? 'missing' : 'ok'" 0
    if ($apiProbe -match '"missing"') { throw "SteamClient.User not available in CDP context" }

    # 1. Go offline (no-op if already offline).
    Send-CdpEval $ws "SteamClient.User.GoOffline()" 1 | Out-Null
    Write-Host "[Pmtools] went offline"

    # 2. Give the offline transition time to settle. This Steam version exposes
    #    no public offline-state getter (BIsOfflineMode was removed), so a
    #    fixed window replaces the old polling loop.
    Start-Sleep -Seconds 1.5

    # 3. Go back online — license re-sync happens here, picking up the new
    #    stplug-in script.
    Send-CdpEval $ws "SteamClient.User.GoOnline()" 3 | Out-Null
    Write-Host "[Pmtools] back online; confirming subscription..."

    # 4. CONFIRM the unlock: GetIsSubscribedApp only turns true after the
    #    re-sync (i.e. after the client is back online) has registered the new
    #    script. Await the async call; hard cap so we never hang.
    $expr = "typeof SteamClient !== 'undefined' && SteamClient.Apps && typeof SteamClient.Apps.GetIsSubscribedApp === 'function' ? SteamClient.Apps.GetIsSubscribedApp($AppId) : null"
    $subscribed = $false
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        $probe = Send-CdpEval $ws $expr 5
        if ($probe -match '"value"\s*:\s*true') { $subscribed = $true; break }
    }
    if (-not $subscribed) { throw "app $AppId not subscribed after offline->online cycle" }

    try { $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", [System.Threading.CancellationToken]::None).Wait() } catch {}
    Write-Marker @{ applied = $true }
    Write-Host "[Pmtools] applied: $AppId confirmed subscribed"
}
catch {
    Write-Marker @{ applied = $false; error = $_.Exception.Message }
    Write-Host "[Pmtools] FAILED: $($_.Exception.Message)"
    exit 1
}
