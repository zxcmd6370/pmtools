# Ignitools - restart Steam fast and clean (no inherited pipes, no console).
#
# Why this shape: a force-kill (taskkill /F / Stop-Process -Force) makes the
# next Steam launch spend ~30s in crash-recovery/relaunch loops. So there is
# NO force-kill here: webhelpers are killed first (they are what makes a
# graceful shutdown drag on for ~15s), then the client is told to shut down
# via `steam.exe -shutdown` - it exits gracefully in a few seconds, and a
# relaunch after a CLEAN exit boots immediately (no recovery).
#
# Why the relaunch travels through the shell: Steam runs its process tree
# inside a Windows Job. When steam.exe dies, the job closes and kills every
# child in it - including this PowerShell (the backend luavm is in that job).
# So a worker is handed off FIRST via WMI (Win32_Process.Create spawns it as
# a child of WmiPrvSE.exe - a service host outside the job). The worker runs
# the poll loop in a hidden window (via wscript), waits for steam.exe to be
# gone, then starts it.
# Called by the backend's RestartSteam RPC via spawn.exec (CreateProcessW,
# CREATE_NO_WINDOW); this script may itself die with the job - fine, the
# worker was already handed off.

param(
    [Parameter(Mandatory = $true)][string]$SteamExe
)

# Millennium's steam_path returns mixed separators (c:/program files (x86)/steam)
# and `cmd start` cannot resolve that path - normalize before anything else.
$SteamExe = $SteamExe -replace "/", "\"

$marker = Join-Path (Split-Path -Parent $PSCommandPath) "restart_log.txt"
function Log($msg) {
    Add-Content -Path $marker -Value ((Get-Date -Format "HH:mm:ss") + " [pid $PID] " + $msg) -ErrorAction SilentlyContinue
}

Log "begin exe=$SteamExe exists=$(Test-Path -LiteralPath $SteamExe)"
if (-not (Test-Path -LiteralPath $SteamExe)) {
    Log "FATAL: steam executable not found"
    exit 1
}

# 1. Write the poll worker: plain batch; the quoted Steam path is handled by
#    cmd natively (this file is executed by the shell, not passed through any
#    /TR-style parser).
$worker = Join-Path (Split-Path -Parent $PSCommandPath) "relaunch_steam_worker.cmd"
$wlog = Join-Path (Split-Path -Parent $PSCommandPath) "worker_log.txt"
$workerBody = @"
@echo off
setlocal EnableDelayedExpansion
echo %date% %time% worker START >> "$wlog"
ping -n 2 127.0.0.1 >nul
set /a n=0
:waitloop
tasklist /FI "IMAGENAME eq steam.exe" 2>nul | findstr /I /C:"steam.exe" >nul
if not errorlevel 1 (
  set /a n+=1
  echo %date% %time% alive n=!n! >> "$wlog"
  if !n! geq 40 goto force
  ping -n 2 127.0.0.1 >nul
  goto waitloop
)
echo %date% %time% exit-detected, starting steam >> "$wlog"
start "" "$SteamExe"
echo %date% %time% started >> "$wlog"
exit /b
:force
echo %date% %time% force path >> "$wlog"
taskkill /IM steam.exe /F >nul 2>nul
ping -n 2 127.0.0.1 >nul
start "" "$SteamExe"
echo %date% %time% started-after-force >> "$wlog"
"@
Set-Content -Path $worker -Value $workerBody -Encoding ASCII

# 2. Wrapper vbs runs the worker cmd with a HIDDEN window (style 0) so the
#    user never sees a console flash; wscript itself never shows a window.
$workerVbs = Join-Path (Split-Path -Parent $PSCommandPath) "relaunch_steam_worker.vbs"
Set-Content -Path $workerVbs -Value ('Set sh = CreateObject("WScript.Shell")' + [Environment]::NewLine +
    'sh.Run """' + $worker + '""", 0, False') -Encoding ASCII

# 3. Hand the worker over OUTSIDE Steam's job so it survives steam.exe dying.
#    Primary: Task Scheduler via /XML. The task XML carries the command and
#    arguments as separate elements, so no command-line quoting is involved —
#    the classic schtasks /TR quoting trap (PowerShell passes the quoted path
#    and schtasks strips the inner quotes, e.g. "Invalid argument/option -
#    'Files'") cannot happen. schtasks spawns the worker under the Task
#    Scheduler service (svchost.exe), which is never inside Steam's job, and
#    runs as the logged-in user with a hidden window (wscript style 0). Needs
#    no admin for a one-shot task; deleting the task after /Run does NOT kill
#    the already-running worker (verified 2026-08-16).
#    Fallbacks: WMI (Win32_Process.Create under WmiPrvSE — also outside the
#    job, but flaky: observed returning 8 "unknown failure" intermittently),
#    then ShellExecute (spawns the worker as a child of the caller, which IS
#    in the job — the worker dies with the job when Steam exits, so the
#    restart never happens; kept only as a last resort).
$taskName = "PmtoolsRestartSteam"
$taskXmlPath = Join-Path (Split-Path -Parent $PSCommandPath) "relaunch_task.xml"
$taskXml = @'
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers />
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>&quot;__VBS_PATH__&quot;</Arguments>
    </Exec>
  </Actions>
</Task>
'@
$taskXml = $taskXml.Replace('__VBS_PATH__', $workerVbs)
Set-Content -Path $taskXmlPath -Value $taskXml -Encoding Unicode
schtasks /Create /TN $taskName /XML $taskXmlPath /F 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    schtasks /Run /TN $taskName 2>$null | Out-Null
    Log "worker handed off via Task Scheduler ($taskName)"
    # One-shot task already fired — remove it so it can't re-run later. The
    # running worker is unaffected (it is not a child of the task anymore).
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null
} else {
    Log "schtasks failed ($LASTEXITCODE), trying WMI"
    try {
        $cmd = 'wscript.exe "' + $workerVbs + '"'
        $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd }
        Log "worker created via WMI ret=$($r.ReturnValue) pid=$($r.ProcessId)"
        if ($r.ReturnValue -ne 0 -and $r.ReturnValue -ne 4) {
            Log "WMI returned $($r.ReturnValue), falling back to ShellExecute"
            (New-Object -ComObject Shell.Application).ShellExecute($worker, "", (Split-Path -Parent $worker), "open", 1)
        }
    } catch {
        Log "WMI ERROR: $($_.Exception.Message), falling back to ShellExecute"
        (New-Object -ComObject Shell.Application).ShellExecute($worker, "", (Split-Path -Parent $worker), "open", 1)
    }
}

# 4. Kill webhelpers first (they drag out a graceful shutdown for ~15s),
#    then ask the client to shut down - exits clean in a few seconds.
Get-Process -Name steamwebhelper -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process -FilePath $SteamExe -ArgumentList "-shutdown"
Log "graceful shutdown requested"