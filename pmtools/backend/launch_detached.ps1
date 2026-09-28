# Ignitools — launch a PowerShell script FULLY DETACHED from the caller.
#
# Why this exists: the Lua backend launches background workers with
# utils.exec(), which uses _popen() and BLOCKS until every process that
# inherited the stdout pipe closes it. `start /B` chains still inherit the
# pipe, so exec() would block for the whole download/apply. This launcher
# breaks the chain: it writes a temp .cmd wrapper and launches it via
# `cmd /c start cmd /c`, which creates a fully independent process tree
# that survives the caller (Steam/Millennium) being killed.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File launch_detached.ps1 \
#       -Script "C:\...worker.ps1" [-Visible] [-Extra -Args ...]
#
# Extra args are forwarded verbatim to the worker (paths with spaces are
# quoted so they survive the .cmd round-trip).

param(
    [Parameter(Mandatory = $true)][string]$Script,
    [switch]$Visible,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$ExtraArgs
)

if (-not $Script -or -not (Test-Path -LiteralPath $Script)) { exit 1 }

# Quote args that contain spaces for the .cmd round-trip
$quoted = @()
foreach ($a in $ExtraArgs) {
    if ($a -match '\s') { $quoted += ('"' + $a + '"') } else { $quoted += $a }
}
if ($Script -match '\s') { $scriptArg = '"' + $Script + '"' } else { $scriptArg = $Script }

# Build the PowerShell command line
$psArgs = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $scriptArg
) + $quoted
$psCmdLine = $psArgs -join ' '

# Write a temp .cmd that launches PowerShell. Using `cmd /c start cmd /c`
# creates two layers of process detachment — guaranteed to survive the
# original caller (Steam) being killed mid-update.
$env:TEMP = [System.IO.Path]::GetTempPath()
$wrapperCmd = Join-Path $env:TEMP ("pmtools_launcher_" + ([System.Diagnostics.Process]::GetCurrentProcess().Id) + ".cmd")
$showCmd = if ($Visible) { "start" } else { "start /min" }

$cmdContent = "@echo off`r`n$showCmd \"\" powershell.exe $psCmdLine"
[System.IO.File]::WriteAllText($wrapperCmd, $cmdContent, [System.Text.Encoding]::ASCII)

# Launch via cmd /c start cmd /c — fully independent process tree
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "start", '""', "/c", "`"$wrapperCmd`""
