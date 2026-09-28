param(
    [string]$PmtoolsPackageUrl = "https://pmtools-tools.vercel.app/pmtools.zip",
    [string]$SteamPath = "",
    [switch]$NoStartSteam,
    [switch]$Force
)

# Force TLS 1.2 early — older PowerShell defaults to SSL3/TLS1.0 which
# Vercel and most modern CDNs reject.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

$ErrorActionPreference = "Stop"

# ── Terminal UI helpers ────────────────────────────────────────────────────────

$script:ESC = [char]27
$script:HasColor = $false
try { $script:HasColor = $Host.UI.SupportsVirtualTerminal } catch { $script:HasColor = $false }

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:GLYPH_CHECK  = [char]0x2713
$script:GLYPH_CROSS  = [char]0x2717
$script:GLYPH_ARROW  = [char]0x25B8
$script:GLYPH_DOT    = [char]0x25CF
$script:GLYPH_HBAR   = [char]0x2500
$script:GLYPH_VBAR   = [char]0x2502
$script:GLYPH_TL     = [char]0x250C
$script:GLYPH_TR     = [char]0x2510
$script:GLYPH_BL     = [char]0x2514
$script:GLYPH_BR     = [char]0x2518
$script:GLYPH_DIAMOND = [char]0x25C6

$script:COL = @{
    cyan    = "96"; brightCyan  = "96"
    blue    = "94"; green       = "92"
    yellow  = "93"; red         = "91"
    magenta = "95"; white       = "97"
    bold    = "1";  dim         = "2"
    none    = ""
}

function Write-Term([string]$Text, [string]$Color = "none") {
    if ($script:HasColor -and $Color -and $Color -ne "none") {
        Write-Host ("{0}[{1}m{2}{0}[0m" -f $script:ESC, $script:COL[$Color], $Text)
    } else {
        Write-Host $Text
    }
}

function Write-Info([string]$Text)   { Write-Term $Text "cyan" }
function Write-Success([string]$Text) { Write-Term $Text "green" }
function Write-Warn([string]$Text)   { Write-Term $Text "yellow" }
function Write-Error([string]$Text)  { Write-Term $Text "red" }
function Write-Dim([string]$Text)    { Write-Term $Text "dim" }

function Write-Rule {
    $w = 60
    try { $w = [Math]::Min(72, $Host.UI.RawUI.WindowSize.Width - 2) } catch { }
    if ($w -lt 20) { $w = 60 }
    Write-Term (( [string]$script:GLYPH_HBAR) * $w) "dim"
}

function Show-Banner {
    $inner = 44
    $hbar = [string]$script:GLYPH_HBAR
    $vbar = [string]$script:GLYPH_VBAR

    function Frame([string]$Text) {
        if ($Text.Length -ge $inner) { return "  $vbar $($Text.Substring(0, $inner)) $vbar" }
        $left = [Math]::Floor(($inner - $Text.Length) / 2)
        $right = $inner - $Text.Length - $left
        return "  $vbar " + (' ' * $left) + $Text + (' ' * $right) + " $vbar"
    }

    Write-Host ""
    Write-Term ("  " + $script:GLYPH_TL + ($hbar * ($inner + 2)) + $script:GLYPH_TR) "cyan"
    Write-Term (Frame("  " + $script:GLYPH_DIAMOND + "PMTOOLS " + $script:GLYPH_DIAMOND + "  ")) "cyan"
    Write-Term (Frame("Standalone Steam unlock plugin")) "cyan"
    Write-Term (Frame("by zxcmd6370")) "dim"
    Write-Term ("  " + $script:GLYPH_BL + ($hbar * ($inner + 2)) + $script:GLYPH_BR) "cyan"
    Write-Host ""
}

$script:StepCount = 0
$script:StepTotal = 0
function Start-Step([string]$Label) {
    $script:StepCount++
    Write-Host ""
    $prefix = "[$script:StepCount/$script:StepTotal]  "
    Write-Term ($prefix + $Label) "bold"
}

function Complete-Step([string]$Detail = "") {
    if ($Detail) {
        Write-Term ("     " + $script:GLYPH_CHECK + "  " + $Detail) "green"
    } else {
        Write-Term ("     " + $script:GLYPH_CHECK + "  done") "green"
    }
}

function Fail-Step([string]$Detail = "") {
    Write-Term ("     " + $script:GLYPH_CROSS + "  " + $Detail) "red"
}

function Confirm-Prompt([string]$Question, [string]$Default = "y") {
    $suffix = if ($Default -eq "y") { "[Y/n]" } else { "[y/N]" }
    Write-Host ""
    Write-Term ("  ?  " + $Question + "  " + $suffix) "yellow"
    $answer = Read-Host "  > "
    if ($answer -eq "") { $answer = $Default }
    return ($answer -match "^(?i:y|yes)$")
}

function Start-Download([string]$Url, [string]$OutputPath, [string]$Label) {
    if (-not $Url) { throw "Download URL was not provided." }
    Remove-IfExists $OutputPath

    try {
        Write-Info ("     " + $script:GLYPH_ARROW + "  Downloading " + (Split-Path -Leaf $Url))
        $progressPreferenceBak = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
        } finally {
            $ProgressPreference = $progressPreferenceBak
        }
    } catch {
        throw "Could not download from $Url. $($_.Exception.Message)"
    }

    if (-not (Test-Path $OutputPath) -or (Get-Item $OutputPath).Length -eq 0) {
        throw "Download failed: $OutputPath was not created or is empty."
    }
}

# ── Install logic ─────────────────────────────────────────────────────────────

function Stop-SteamIfRunning {
    $steamProcesses = @(Get-Process -Name steam -ErrorAction SilentlyContinue)
    if ($steamProcesses.Count -eq 0) { return }

    Write-Warn ("  " + $script:GLYPH_ARROW + "  Steam is running - closing it before continuing...")
    foreach ($proc in $steamProcesses) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop }
        catch { Write-Error ("      could not stop Steam process " + $proc.Id + ": " + $_.Exception.Message) }
    }

    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $remaining = @(Get-Process -Name steam -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    }

    $stillRunning = @(Get-Process -Name steam -ErrorAction SilentlyContinue)
    if ($stillRunning.Count -gt 0) {
        Write-Warn "  Steam is still running after shutdown attempt. Continuing anyway."
    }
}

function Get-SteamInstallPath {
    if ($SteamPath -and (Test-Path $SteamPath)) {
        return (Resolve-Path $SteamPath).Path
    }

    $steamProp = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -ErrorAction SilentlyContinue
    if ($steamProp -and $steamProp.SteamPath) { return $steamProp.SteamPath }

    $steamProp = Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name 'InstallPath' -ErrorAction SilentlyContinue
    if ($steamProp -and $steamProp.InstallPath) { return $steamProp.InstallPath }

    $guess = "$env:ProgramFiles(x86)\Steam"
    if (Test-Path $guess) { return $guess }

    throw "Could not detect Steam install path. Pass -SteamPath to override."
}

function Remove-IfExists([string]$Path) {
    if (Test-Path $Path) { Remove-Item -Path $Path -Recurse -Force }
}

function New-TempDirectory([string]$BaseName) {
    $path = Join-Path $env:TEMP $BaseName
    Remove-IfExists $path
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Get-ExtractRoot([string]$ExtractDir) {
    $entries = Get-ChildItem -Path $ExtractDir -Force
    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) {
        return Join-Path $ExtractDir $entries[0].Name
    }
    return $ExtractDir
}

function Install-Pmtools {
    $zipPath = Join-Path $env:TEMP "pmtools-install.zip"
    $extractDir = New-TempDirectory "pmtools-install"

    Start-Download $PmtoolsPackageUrl $zipPath "Pmtools"
    Write-Info ("     " + $script:GLYPH_ARROW + "  Extracting...")
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $sourceRoot = Get-ExtractRoot $extractDir

    # Verify this looks like a valid v2 package (needs at least the DLLs)
    $dllNames = @("pmtools.dll", "dwmapi.dll", "xinput1_4.dll")
    $foundDll = $false
    foreach ($dll in $dllNames) {
        if (Test-Path (Join-Path $sourceRoot $dll)) { $foundDll = $true; break }
    }
    if (-not $foundDll) {
        throw "The Pmtools package does not contain the required DLLs. It does not look like a valid package."
    }

    # Backup existing DLLs before overwriting
    foreach ($dll in $dllNames) {
        $dest = Join-Path $script:SteamRoot $dll
        $bak = "$dest.bak"
        if (Test-Path $dest) {
            Copy-Item $dest $bak -Force
            Write-Dim ("     backed up " + $dll + " -> " + $dll + ".bak")
        }
    }

    # Copy DLLs to Steam root
    Write-Info ("     " + $script:GLYPH_ARROW + "  Installing loader DLLs...")
    foreach ($dll in $dllNames) {
        $src = Join-Path $sourceRoot $dll
        if (Test-Path $src) {
            $dest = Join-Path $script:SteamRoot $dll
            Copy-Item $src $dest -Force
            Write-Dim ("         " + $dll + " (" + [math]::Round((Get-Item $dest).Length / 1KB) + " KB)")
        }
    }

    # Preserve user-local files (API keys, source config, settings)
    $preserveTargets = @("pmtools\secrets.local.json", "pmtools\sources.local.json", "pmtools\settings.json", "config\stplug-in\secrets.local.json")
    $tempPreserve = New-TempDirectory "pmtools-preserve"
    $preserved = @()
    foreach ($rel in $preserveTargets) {
        $src = Join-Path $script:SteamRoot $rel
        if (Test-Path $src) {
            $destTemp = Join-Path $tempPreserve $rel
            $destTempDir = Split-Path $destTemp -Parent
            if (-not (Test-Path $destTempDir)) { New-Item -ItemType Directory -Path $destTempDir -Force | Out-Null }
            Copy-Item $src $destTemp -Force
            $preserved += $rel
        }
    }

    # Ensure ignitools/ directory exists (DLL extracts CDP helper there at runtime)
    $pmtoolsDir = Join-Path $script:SteamRoot "[pmtools"
    if (-not (Test-Path $pmtoolsDir)) {
        New-Item -ItemType Directory -Path $pmtoolsDir -Force | Out-Null
    }
    Complete-Step "Pmtools directory ready"

    # Ensure CDP is enabled for UI injection
    $cdpJunction = Join-Path $script:SteamRoot ".cef-enable-remote-debugging"
    if (-not (Test-Path $cdpJunction)) {
        cmd /c mklink /j "$cdpJunction" "C:\nonexistent" 2>&1 | Out-Null
        if (Test-Path $cdpJunction) {
            Complete-Step "CDP enabled for UI injection"
        } else {
            Write-Warn "     Could not create CDP junction (may need admin) - UI injection may not work"
        }
    } else {
        Complete-Step "CDP already enabled"
    }

    # Restore preserved files
    foreach ($rel in $preserved) {
        $src = Join-Path $tempPreserve $rel
        $dest = Join-Path $script:SteamRoot $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item $src $dest -Force
    }
    Remove-IfExists $tempPreserve

    $kb = [math]::Round((Get-Item $zipPath).Length / 1KB)
    Complete-Step ("Pmtools installed (" + $kb + " KB)")
}

function Start-SteamAfterInstall {
    if ($NoStartSteam) {
        Write-Dim ("     " + $script:GLYPH_ARROW + "  Steam will start when you launch it (skipped via -NoStartSteam).")
        return
    }

    $steamExe = Join-Path $script:SteamRoot "steam.exe"
    if (-not (Test-Path $steamExe)) {
        Write-Warn "     Steam.exe was not found at $steamExe - start Steam manually."
        return
    }

    # Wait for Steam to fully stop
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline -and @(Get-Process -Name steam -ErrorAction SilentlyContinue).Count -gt 0) {
        Start-Sleep -Milliseconds 250
    }

    Write-Info ("     " + $script:GLYPH_ARROW + "  Starting Steam...")
    Start-Process $steamExe
    Complete-Step "Steam launched"
}

# ── Main flow ─────────────────────────────────────────────────────────────────

Show-Banner

$script:StepTotal = 3
$script:StepCount = 0

Start-Step "Steam"
Stop-SteamIfRunning
$script:SteamRoot = Get-SteamInstallPath
Complete-Step ("Steam found: " + $script:SteamRoot)

Start-Step "Pmtools"
Install-Pmtools

Start-Step "Finish"
Start-SteamAfterInstall
Complete-Step "Ready"

Write-Host ""
Write-Rule
Write-Host ""
Write-Success ("  " + $script:GLYPH_CHECK + "  Installation complete! Pmtools is ready.")
Write-Host ""
Write-Term ("  " + $script:GLYPH_ARROW + "  Next steps:") "bold"
Write-Dim ("     " + $script:GLYPH_DOT + "  Steam is starting - the Pmtools menu will appear on store pages")
Write-Dim ("     " + $script:GLYPH_DOT + "  Click the Pmtools icon on any game's store page to add/remove games")
Write-Dim ("     " + $script:GLYPH_DOT + "  No Millennium required - fully standalone")
Write-Dim ("     " + $script:GLYPH_DOT + "  Need help? https://pmtools-tools.vercel.app")
Write-Host ""
Write-Term ("  " + $script:GLYPH_ARROW + "  If the plugin does not load immediately, restart Steam.") "dim"
Write-Host ""
