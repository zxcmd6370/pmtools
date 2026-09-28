# Ignitools — confirm an unlock was applied by the hot-reloading loader.
#
# The Ignitools/OpenSteamTool loader makes the client treat the appid as owned,
# which is exactly what SteamClient.Apps.GetIsSubscribedApp(appid) reports.
# Once the loader hot-reloads a new stplug-in script that call flips to true
# for the appid, so this script polls it over Steam's OWN CDP (the
# steamwebhelper devtools port, 8080 by default — NOT a Millennium service;
# awaitPromise so the async call resolves) and writes the outcome to the
# marker file — the backend never trusts a blind grace period.
#
# This script is fully standalone: it needs only a running Steam client with
# its devtools port reachable. No Millennium, no Lua backend, no loader
# required to RUN it (the loader only needs to exist for the answer to be
# "true").
#
#   {"applied":true}                 -> confirmed live
#   {"applied":false,"error":"..."}  -> loader never picked it up (backend shows
#                                        the restart button as the fallback)
#   {"applied":null,"error":"cdp-unreachable"} -> couldn't verify; backend falls
#                                        back to the historical grace period
#
# Usage (detached, from installer.lua, or by hand):
#   powershell -NoProfile -ExecutionPolicy Bypass -File confirm_applied.ps1
#       -AppId 1234 -MarkerFile "C:\...\temp_dl\1234_apply.json" [-Port 8080]

param(
    [Parameter(Mandatory = $true)][string]$AppId,
    [Parameter(Mandatory = $true)][string]$MarkerFile,
    [string]$Port = "8080"
)

$ErrorActionPreference = "Stop"

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
    $target, $usedPort = Find-Target
    if (-not $target) {
        Write-Marker @{ applied = $null; error = "cdp-unreachable" }
        exit 0
    }

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, [System.Threading.CancellationToken]::None).Wait()

    # Poll the real subscription API the loader drives. The DLL hot-reloads
    # instantly, but Steam's GetIsSubscribedApp can take a few seconds to
    # reflect the new subscription after the loader injects the license.
    $expr = "typeof SteamClient !== 'undefined' && SteamClient.Apps && typeof SteamClient.Apps.GetIsSubscribedApp === 'function' ? SteamClient.Apps.GetIsSubscribedApp($AppId) : null"
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $probe = Send-CdpEval $ws $expr 1
        if ($probe -match '"value"\s*:\s*true') {
            Write-Marker @{ applied = $true }
            exit 0
        }
    }

    Write-Marker @{ applied = $false; error = "not-subscribed-timeout" }
}
catch {
    Write-Marker @{ applied = $false; error = $_.Exception.Message }
}
