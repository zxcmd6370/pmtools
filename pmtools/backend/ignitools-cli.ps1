# Ignitools - standalone CLI. Add / remove / list / status unlocks with
# NEITHER Millennium NOR the loader required at runtime.
#
# This is a PowerShell port of the backend engine (sources.lua + installer.lua)
# so the whole flow works from a plain console - no Steam store UI, no plugin:
#   * Steam path  -> registry (HKCU:\Software\Valve\Steam\SteamPath)
#   * sources     -> the same bundled catalog + backend/sources.local.json +
#                    backend/secrets.local.json overrides the plugin reads
#   * download    -> curl.exe, extracted with System32 bsdtar / Expand-Archive
#   * install     -> *.manifest -> <Steam>\depotcache, {appid}.lua ->
#                    config\stplug-in (depot-key check + setManifestid de-pin,
#                    identical to installer.lua)
#   * apply       -> delegates to apply_no_restart.ps1 (loader confirm, or
#                    offline->online if no loader)
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File ignitools-cli.ps1 add 440 [sourceId] [-SteamPath X]
#   powershell -NoProfile -ExecutionPolicy Bypass -File ignitools-cli.ps1 remove 440
#   powershell -NoProfile -ExecutionPolicy Bypass -File ignitools-cli.ps1 list
#   powershell -NoProfile -ExecutionPolicy Bypass -File ignitools-cli.ps1 status 440
#   powershell -NoProfile -ExecutionPolicy Bypass -File ignitools-cli.ps1 sources
#   powershell -NoProfile -ExecutionPolicy Bypass -File ignitools-cli.ps1 diagnostics

param(
    [Parameter(Position = 0)][string]$Command = "list",
    [Parameter(Position = 1)][string]$AppId = "",
    [Parameter(Position = 2)][string]$SourceId = "",
    [string]$SteamPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Steam path (registry - no Millennium) ------------------------------------

function Get-SteamPath {
    if ($SteamPath -and (Test-Path $SteamPath)) { return $SteamPath }
    try {
        $p = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
        if ($p -and (Test-Path $p)) { return $p }
    } catch {}
    return ""
}

# --- Source catalog (mirror of sources.lua DEFAULT_CATALOG + overrides) -------

$DEFAULT_CATALOG = @(
    @{ id = "sushi";     name = "Sushi";            kind = "AppIdZip"; urlTemplate = "https://raw.githubusercontent.com/sushi-dev55-alt/sushitools-games-repo-alt/refs/heads/main/{appid}.zip"; enabled = $true },
    @{ id = "ryuu";     name = "Ryuu";             kind = "AppIdZip"; urlTemplate = "http://167.235.229.108/{appid}";                     enabled = $true }
)

function Read-JsonFile($path) {
    if (-not (Test-Path $path)) { return $null }
    try { return Get-Content $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Get-Catalog {
    $catalog = @()
    foreach ($e in $DEFAULT_CATALOG) { $catalog += $e }

    # local override file wins by id (same merge semantics as sources.lua)
    $local = Read-JsonFile (Join-Path $ScriptDir "sources.local.json")
    if ($local -and $local.sources) {
        foreach ($e in $local.sources) {
            $found = $catalog | Where-Object { $_.id -eq $e.id }
            if ($found) {
                $i = [Array]::IndexOf($catalog, $found)
                $catalog[$i] = $e
            } else {
                $catalog += $e
            }
        }
    }

    # inject API keys from secrets.local.json into api_key= placeholders
    $secrets = Read-JsonFile (Join-Path $ScriptDir "secrets.local.json")
    $key = ""
    if ($secrets) { $key = [string]$secrets.hubcapKey }
    if ($key -ne "") {
        foreach ($e in $catalog) {
            if ($e.urlTemplate -match "api_key=") { $e.urlTemplate = $e.urlTemplate -replace "api_key=[\w_]*", "api_key=$key" }
            if ($e.usageUrl -match "api_key=")     { $e.usageUrl     = $e.usageUrl     -replace "api_key=[\w_]*", "api_key=$key" }
        }
    }
    return $catalog
}

function Get-EnabledSources {
    return @((Get-Catalog) | Where-Object { $_.enabled -ne $false })
}

function Resolve-Url($source, $appid) {
    if ($source.kind -eq "AppIdZip") {
        return $source.urlTemplate.Replace("{appid}", $appid).Replace("<appid>", $appid)
    }
    if ($source.kind -eq "LuaFolder") {
        $branch = if ($source.branch) { $source.branch } else { "main" }
        $path = if ($source.path) { $source.path } else { "" }
        $rel = if ($path -ne "") { "$path/$appid.zip" } else { "$appid.zip" }
        return "https://raw.githubusercontent.com/$($source.owner)/$($source.repo)/$branch/$rel"
    }
    return ""
}

# --- Install helpers (mirror of installer.lua finalize) -----------------------

function Extract-Zip($zip, $dest) {
    $sysTar = Join-Path $env:WINDIR "System32\tar.exe"
    if (Test-Path $sysTar) {
        & $sysTar -xf $zip -C $dest 2>$null
        if ($LASTEXITCODE -eq 0) { return }
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
}

# Comment out setManifestid (any casing) when it is the first token on a line,
# so Steam tracks the latest build instead of a pinned one.
function Remove-Pin($text) {
    $out = @()
    foreach ($line in ($text -split "`n")) {
        $t = $line.Trim()
        if ($t -notmatch "^--") {
            $m = [regex]::Match($line, "(?im)^\s*setmanifestid\s*\(")
            if ($m.Success) {
                $out += $line.Substring(0, $m.Index) + "-- " + $line.Substring($m.Index)
                continue
            }
        }
        $out += $line
    }
    return ($out -join "`n")
}

# A lua with addappid() entries but zero addappid(id, 1, "key") calls can't
# decrypt depots - refuse it (same check as installer.lua).
function Test-DepotKeys($text) {
    $addappid = 0
    $keyed = 0
    foreach ($line in ($text -split "`n")) {
        if ($line -match "addappid\s*\(") {
            $addappid++
            if ($line -match 'addappid\s*\(\s*\d+\s*,\s*\d+\s*,\s*"') { $keyed++ }
        }
    }
    return ($addappid -eq 0 -or $keyed -gt 0)
}

function Install-Bundle($sp, $appid, $extractDir) {
    $targetDir = Join-Path $sp "config\stplug-in"
    $depotCache = Join-Path $sp "depotcache"
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    New-Item -ItemType Directory -Force -Path $depotCache | Out-Null

    $targetLua = Join-Path $targetDir "$appid.lua"
    $copied = 0
    $luaWritten = $false

    foreach ($file in (Get-ChildItem -Path $extractDir -Recurse -File -ErrorAction SilentlyContinue)) {
        if ($file.Extension -eq ".manifest") {
            Copy-Item $file.FullName (Join-Path $depotCache $file.Name) -Force
            $copied++
        }
        elseif ($file.Name -eq "$appid.lua" -or (-not $luaWritten -and $file.Name -match "^\d+\.lua$")) {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            if (-not (Test-DepotKeys $text)) {
                Write-Host "[Pmtools] FAILED: bundle has no depot keys (addappid without a key) - refusing broken install"
                return $false
            }
            $text = Remove-Pin $text
            [System.IO.File]::WriteAllText($targetLua, $text)
            $luaWritten = $true
        }
    }

    if (-not $luaWritten) {
        if (Test-Path $targetLua) { Remove-Item $targetLua -Force }
        Write-Host "[Pmtools] FAILED: no {appid}.lua in bundle"
        return $false
    }
    Write-Host "[Pmtools] installed $appid ($copied manifests)"
    return $true
}

function Remove-Unlock($sp, $appid) {
    $removed = $false
    $targetDir = Join-Path $sp "config\stplug-in"
    foreach ($name in @("$appid.lua", "$appid.lua.disabled")) {
        $f = Join-Path $targetDir $name
        if (Test-Path $f) { Remove-Item $f -Force; $removed = $true }
    }
    $depotCache = Join-Path $sp "depotcache"
    if (Test-Path $depotCache) {
        Get-ChildItem $depotCache -Filter "*" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^$appid[_.].*\.manifest$" } |
            ForEach-Object { Remove-Item $_.FullName -Force; $removed = $true }
    }
    return $removed
}

# --- Commands -----------------------------------------------------------------

function Write-Help {
    Write-Host @"
Pmtools standalone CLI (no Millennium needed)
  add <appid> [sourceId]   download + install + apply without restart
  remove <appid>           delete the unlock (lua + manifests)
  list                     show every installed unlock
  status <appid>           is it unlocked?
  sources                  show enabled sources
"@
}

$sp = Get-SteamPath
if (-not $sp) {
    Write-Host "[Pmtools] ERROR: could not locate Steam (registry SteamPath missing)"
    exit 1
}

switch ($Command.ToLower()) {
    "add" {
        if (-not $AppId -or $AppId -notmatch "^\d+$") { Write-Help; exit 1 }
        $sources = @(Get-EnabledSources)
        $source = $null
        if ($SourceId) { $source = $sources | Where-Object { $_.id -eq $SourceId } | Select-Object -First 1 }
        if (-not $source) {
            Write-Host "[Pmtools] picking source for $AppId... available:"
            foreach ($s in $sources) { Write-Host "  $($s.id) ($($s.name))" }
            $source = $sources | Select-Object -First 1
        }
        if (-not $source) { Write-Host "[Pmtools] ERROR: no sources enabled"; exit 1 }

        $url = Resolve-Url $source $AppId
        Write-Host "[Pmtools] $($source.name) -> $url"
        $tmp = Join-Path $env:TEMP "pmtools_cli_$AppId"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $zip = Join-Path $tmp "$AppId.zip"
        $extract = Join-Path $tmp "extracted"

        Write-Host "[Pmtools] downloading bundle..."
        # Native stderr under $ErrorActionPreference=Stop becomes a terminating
        # error in PS 5.1 when redirected with 2>&1 - run curl in a child scope
        # with EAP relaxed and judge success purely on the exit code + file.
        & { $ErrorActionPreference = "Continue"; & curl.exe -sS -f -L -A "Pmtools" --connect-timeout 15 --retry 3 --retry-delay 2 $url -o $zip 2>$null }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zip)) {
            Write-Host "[Pmtools] FAILED: this source returned no bundle for the game (HTTP error)"
            exit 1
        }
        $bytes = [System.IO.File]::ReadAllBytes($zip)
        if ($bytes.Length -lt 4 -or $bytes[0] -ne 0x50 -or $bytes[1] -ne 0x4B) {
            Write-Host "[Pmtools] FAILED: downloaded file is not a valid bundle"
            exit 1
        }
        Write-Host "[Pmtools] extracting..."
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $extract | Out-Null
        Extract-Zip $zip $extract

        if (-not (Install-Bundle $sp $AppId $extract)) { exit 1 }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

        # apply without restart (loader confirm or offline->online, standalone)
        $apply = Join-Path $ScriptDir "apply_no_restart.ps1"
        if (Test-Path $apply) {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $apply -AppId $AppId -SteamPath $sp
            exit $LASTEXITCODE
        }
        Write-Host "[Pmtools] applied (files in place; restart Steam to pick up)"
        exit 0
    }
    "remove" {
        if (-not $AppId -or $AppId -notmatch "^\d+$") { Write-Help; exit 1 }
        $removed = Remove-Unlock $sp $AppId
        if ($removed) { Write-Host "[Pmtools] removed $AppId" } else { Write-Host "[Pmtools] $AppId was not unlocked" }
        exit 0
    }
    "list" {
        $dir = Join-Path $sp "config\stplug-in"
        if (Test-Path $dir) {
            Get-ChildItem $dir -File | Where-Object { $_.Name -match "^\d+\.lua(\.disabled)?$" } |
                Sort-Object { [int]($_.Name -split "\.")[0] } |
                ForEach-Object {
                    $disabled = $_.Name -like "*.disabled"
                    $appid = ($_.Name -split "\.")[0]
                    Write-Host ("{0}  {1}" -f $appid, $(if ($disabled) { "(disabled)" } else { "" }))
                }
        }
        exit 0
    }
    "status" {
        if (-not $AppId) { Write-Help; exit 1 }
        $f = Join-Path $sp "config\stplug-in\$AppId.lua"
        $d = Join-Path $sp "config\stplug-in\$AppId.lua.disabled"
        if (Test-Path $f) { Write-Host "[Pmtools] $AppId unlocked" }
        elseif (Test-Path $d) { Write-Host "[Pmtools] $AppId unlocked (disabled)" }
        else { Write-Host "[Pmtools] $AppId not unlocked" }
        exit 0
    }
    "sources" {
        foreach ($s in @(Get-EnabledSources)) {
            Write-Host "  $($s.id) ($($s.name)) - $($s.urlTemplate)"
        }
        exit 0
    }
    "diagnostics" {
        # Exportable report: Steam build, loader presence/version/hashes,
        # signature + IPC files, loader diagnostics.txt, plugin version + log.
        $report = @()
        $report += "Pmtools diagnostics - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $report += "Steam path: $sp"
        $pkg = Join-Path $sp "package\steam_client_win32"
        if (Test-Path $pkg) { $report += "Steam package: $((Get-Content $pkg -Raw).Trim())" }
        $loader = Join-Path $sp "pmtools.dll"
        if (Test-Path $loader) {
            $report += "Loader: pmtools.dll present"
            $v = (Get-Item $loader).VersionInfo
            if ($v) { $report += "  file version: $($v.FileVersion)  product: $($v.ProductVersion)" }
            $report += "  sha256: $((Get-FileHash $loader -Algorithm SHA256).Hash)"
            foreach ($proxy in @("dwmapi.dll", "xinput1_4.dll")) {
                $p = Join-Path $sp $proxy
                $report += "  $proxy : $(if (Test-Path $p) { 'present' } else { 'MISSING' })"
            }
            $toml = Join-Path $sp "pmtools.toml"
            $report += "  ignitools.toml : $(if (Test-Path $toml) { 'present' } else { 'MISSING' })"
        } else {
            $report += "Loader: pmtools.dll MISSING (legacy OpenSteamTool.dll present: $((Test-Path (Join-Path $sp 'OpenSteamTool.dll'))))"
        }
        $sig = Join-Path $sp "pmtools"
        foreach ($sub in @("pattern", "ipc")) {
            $d = Join-Path $sig $sub
            $n = 0
            if (Test-Path $d) { $n = @(Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue).Count }
            $report += "  pmtools/$sub/ : $n files"
        }
        $diag = Join-Path $sig "diagnostics.txt"
        if (Test-Path $diag) {
            $report += "Loader diagnostics.txt:"
            Get-Content $diag | ForEach-Object { $report += "  $_" }
        } else {
            $report += "Loader diagnostics.txt: not written yet"
        }
        $pluginJson = Join-Path $ScriptDir "..\plugin.json"
        if (Test-Path $pluginJson) {
            $j = Get-Content $pluginJson -Raw | ConvertFrom-Json
            $report += "Plugin version: $($j.version)"
        }
        $log = Join-Path $sp "millennium\logs\pmtools_log.log"
        if (Test-Path $log) {
            $report += "Backend log (last 8 lines):"
            Get-Content $log -Tail 8 | ForEach-Object { $report += "  $_" }
        }
        $out = "pmtools_diagnostics.txt"
        $report | Set-Content -Path $out -Encoding UTF8
        $report | ForEach-Object { Write-Host $_ }
        Write-Host ""
        Write-Host "[Pmtools] report written to: $((Resolve-Path $out).Path)"
        exit 0
    }
    default { Write-Help; exit 1 }
}
