# pmtools Uninstaller — github.com/Contrary7/SteamDaddy-Backup
# Safely removes pmtools activation DLLs from the Steam directory.
$ErrorActionPreference = "Stop"

# Ensure Administrator privileges so system DLL locks can be released
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[pmtools Uninstaller] Requesting Administrator privileges for file cleanup..." -ForegroundColor Yellow
    try {
        if ($PSCommandPath) {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
            exit
        } else {
            $tmpScript = Join-Path$env:TEMP "pmtools_Uninstall.ps1"
            (New-Object System.Net.WebClient).DownloadFile(
                "https://raw.githubusercontent.com/zxcmd6370/pmtools/main/uninstall.ps1",
                $tmpScript
            )
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmpScript`"" -Verb RunAs -ErrorAction Stop
            exit
        }
    } catch {
        Write-Host "[pmtools Uninstaller] Continuing without elevated permissions..." -ForegroundColor Yellow
    }
}

Write-Host "[pmtools Uninstaller] Locating Steam installation directory..." -ForegroundColor Cyan

# Locate Steam root directory from Windows Registry
$steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
if (-not $steamPath) {$steamPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
}
if (-not $steamPath) {$steamPath = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
}
if (-not $steamPath) {$steamPath = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
}

# Fallback default locations if registry key is missing
if (-not $steamPath -or -not (Test-Path $steamPath)) {$fallbackPaths = @(
        "C:\Program Files (x86)\Steam",
        "C:\Program Files\Steam",
        "C:\Steam"
    )
    foreach ($fb in$fallbackPaths) {
        if (Test-Path $fb) {
            $steamPath =$fb
            break
        }
    }
}

if (-not $steamPath -or -not (Test-Path$steamPath)) {
    Write-Host "[pmtools Uninstaller] Error: Steam installation directory could not be found." -ForegroundColor Red
    exit 1
}

Write-Host "[pmtools Uninstaller] Found Steam installation at: $steamPath" -ForegroundColor Green

# Close Steam process if running to release DLL file handles
$steamProc = Get-Process -Name "steam" -ErrorAction SilentlyContinue
if ($steamProc) {
    Write-Host "[pmtools Uninstaller] Stopping Steam process to unlock DLL files..." -ForegroundColor Yellow
    Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$sdProc = Get-Process -Name "pmtools" -ErrorAction SilentlyContinue
if ($sdProc) {
    Stop-Process -Name "pmtools" -Force -ErrorAction SilentlyContinue
}

# List of DLL files to uninstall from Steam root directory
$targetDlls = @(
    "steamdaddy.dll",
    "dwmapi.dll",
    "xinput1_4.dll"
)

$removedCount = 0

foreach ($dll in $targetDlls) {$dllPath = Join-Path $steamPath$dll
    if (Test-Path $dllPath) {
        try {
            Remove-Item -Path $dllPath -Force -ErrorAction Stop
            Write-Host "[pmtools Uninstaller] Successfully deleted: $dll" -ForegroundColor Green
            $removedCount++
        } catch {
            Write-Host "[pmtools Uninstaller] Failed to delete $dll :$_" -ForegroundColor Red
        }
    } else {
        Write-Host "[pmtools Uninstaller] File not found (already uninstalled): $dll" -ForegroundColor DarkGray
    }
}

Write-Host ""
if ($removedCount -gt 0) {
    Write-Host "[pmtools Uninstaller] Uninstall complete! Removed $removedCount DLL file(s) from Steam." -ForegroundColor Magenta
} else {
    Write-Host "[pmtools Uninstaller] Clean! No pmtools DLL files were found in Steam directory." -ForegroundColor Green
}
