# Ignitools — probe every source for an appid IN PARALLEL and write a JSON
# result file the Lua backend can consume.
#
# Why: Millennium's Lua `http` module is single-threaded, so probing sources
# sequentially costs the SUM of all probe latencies (2-4s). This script fires
# one detached curl.exe per source, so all probes run concurrently and the
# total is roughly the SLOWEST source. It is launched fully detached via
# launch_detached.ps1 so the backend never blocks on it.
#
# Why curl.exe instead of .NET HttpClient: on some machines HttpClient stalls
# for seconds on certain CDNs (e.g. raw.githubusercontent.com — IPv6-first /
# connection quirk) while curl answers in <1s. HttpClient also throws an
# AggregateException from WaitAll when ANY task faults or times out — combined
# with $ErrorActionPreference="Stop" that used to kill the whole script before
# it wrote the result file, which made the Lua backend wait its full deadline
# and then fall back to slow sequential probes. curl.exe sidesteps both
# problems: it never aborts the batch, and each probe self-terminates via
# --max-time. If curl.exe is missing we write nothing and the Lua backend's
# sequential fallback takes over.
#
# Probe kinds (config file JSON — same contract as before):
#   { "probes": [ { "id": "sushi", "kind": "range"|"status", "url": "...", "key": "..." }, ... ] }
#   * range  -> HEAD first (lightweight — a 1-byte ranged GET would be fine too,
#               but some servers IGNORE the Range header and stream the whole
#               bundle, e.g. a manifest backend that serves the full ~1.5 MB zip
#               even for a 0-0 range probe, taking ~2.5s, while HEAD is ~0.5s).
#               HEAD works on GitHub raw and the manifest APIs with accurate
#               200/404 semantics. If a host rejects HEAD (405/501/403) or the
#               request fails (code 0), we retry once with a 1-byte ranged GET.
#               200/206 = have it.
#   * status -> plain GET of an availability endpoint (Hubcap's /status, which
#               is FREE and does NOT count against the download limit), with the
#               api key as a Bearer header. 200 + body.manifest_file_exists==true
#               = have it; 429 = daily limit hit.
#
# Result file (JSON): { "<id>": { "code": 200, "body": "...", "ms": 123 } }

param(
    [Parameter(Mandatory = $true)][string]$ConfigFile,
    [Parameter(Mandatory = $true)][string]$ResultFile
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    # No curl.exe (pre-1803 Windows) — write nothing so the Lua backend's
    # sequential fallback handles the probes instead.
    exit 0
}

$config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
$probes = @($config.probes)

$procs = @()
foreach ($p in $probes) {
    $curlArgs = @("-s", "--max-time", "3", "-w", "%{http_code}")
    $bodyFile = $null
    $fallback = $false
    if ($p.kind -eq "status") {
        # Status probes need the body too (manifest_file_exists). Capture it to
        # a temp file so the code (stdout) and body stay separate, and cap the
        # read-back below so a misbehaving endpoint can't balloon the result.
        $bodyFile = $ResultFile + "." + $p.id + ".body"
        Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
        # NB: quote the body path — Steam's install dir (and these temp files
        # under it) contains spaces ("Program Files (x86)"), and an unquoted
        # -o value makes curl write to the first token and treat the rest as
        # extra URLs, so the body never lands and status probes always read as
        # "not available". Same for the -H value: build it with REAL quotes
        # (not backslash-quotes, which curl sends verbatim → 401 on Hubcap).
        $curlArgs += @("-o", ('"' + $bodyFile + '"'))
        if ($p.key) {
            # Bearer key (e.g. Hubcap's api key) — quote so special chars survive.
            $curlArgs += @("-H", ('"Authorization: Bearer ' + $p.key + '"'))
        }
    } else {
        # Range-kind probe: HEAD first (fast, avoids servers that ignore Range).
        # Recorded as a HEAD probe; the result loop falls back to a ranged GET
        # if HEAD is rejected (405/501/403) or fails entirely.
        # NB: use -X HEAD, NOT -I — -I dumps the response headers to stdout,
        # which would corrupt the -w "%{http_code}" output and make every HEAD
        # probe look like it failed (code 0 -> spurious ranged-GET fallbacks).
        $curlArgs += @("-X", "HEAD", "-o", "NUL")
        $fallback = $true
    }
    # Quote the URL so query strings / special chars survive the command line.
    $curlArgs += ('"' + $p.url + '"')

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "curl.exe"
    $psi.Arguments = $curlArgs -join " "
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $procs += , @{ proc = $proc; id = $p.id; kind = $p.kind; bodyFile = $bodyFile; fallback = $fallback; url = $p.url; sw = [System.Diagnostics.Stopwatch]::StartNew() }
    } catch {
        # Failed to spawn this probe (rare) — record it as unavailable below.
        $procs += , @{ proc = $null; id = $p.id; kind = $p.kind; bodyFile = $bodyFile; fallback = $fallback; url = $p.url; sw = [System.Diagnostics.Stopwatch]::StartNew() }
    }
}

# Give every probe a chance to finish. curl's own --max-time caps each at 3s;
# this deadline is just a safety net for a hung process. No exception can abort
# the batch — each result is recorded individually below.
$deadline = (Get-Date).AddSeconds(5)
foreach ($e in $procs) {
    if ($e.proc) {
        $remaining = [Math]::Max(1, [int]($deadline - (Get-Date)).TotalMilliseconds)
        $e.proc.WaitForExit($remaining) | Out-Null
        if (-not $e.proc.HasExited) { try { $e.proc.Kill() } catch {} }
        # Stop the stopwatch as soon as THIS process is done — otherwise every
        # probe reports the whole batch's wall time (the slowest source) instead
        # of its own latency, which corrupts the health/latency display.
        $e.sw.Stop()
    }
}

# Read the code out of each process. HEAD probes that were rejected fall back
# to a 1-byte ranged GET (sequential — only fires for hosts that refuse HEAD,
# and the per-request --max-time keeps it bounded).
foreach ($e in $procs) {
    if ($e.proc -and $e.proc.HasExited) {
        $codeText = ""
        try { $codeText = $e.proc.StandardOutput.ReadToEnd().Trim() } catch {}
        $parsed = 0
        [int]::TryParse($codeText, [ref]$parsed) | Out-Null
        $e.code = $parsed
    } else {
        $e.code = 0
    }
    $e.body = ""

    if ($e.fallback -and ($e.code -eq 0 -or $e.code -eq 403 -or $e.code -eq 405 -or $e.code -eq 501)) {
        # Host rejected HEAD (or the HEAD failed) — retry with a 1-byte ranged
        # GET. Discard the body (-o NUL) so a server that ignores Range and
        # streams the whole bundle can never bloat the result file (which
        # previously crashed the Lua JSON parser — EXCEPTION_ACCESS_VIOLATION).
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "curl.exe"
        $psi.Arguments = ('-s --max-time 3 -w "%{http_code}" -r 0-0 -o NUL "' + $e.url + '"')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        try {
            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.WaitForExit(3500) | Out-Null
            if (-not $proc.HasExited) { try { $proc.Kill() } catch {} }
            $codeText = ""
            try { $codeText = $proc.StandardOutput.ReadToEnd().Trim() } catch {}
            $parsed = 0
            [int]::TryParse($codeText, [ref]$parsed) | Out-Null
            if ($parsed -ne 0) { $e.code = $parsed }
        } catch { }
    }

    if ($e.kind -eq "status" -and $e.bodyFile -and (Test-Path -LiteralPath $e.bodyFile)) {
        try {
            $e.body = [System.IO.File]::ReadAllText($e.bodyFile)
            # Cap status bodies (Hubcap's /status is small JSON; never let a
            # misbehaving endpoint balloon the result file).
            if ($e.body.Length -gt 131072) { $e.body = $e.body.Substring(0, 131072) }
        } catch { $e.body = "" }
        Remove-Item -LiteralPath $e.bodyFile -Force -ErrorAction SilentlyContinue
    }
}

$results = @{}
foreach ($e in $procs) {
    $results[$e.id] = @{ code = $e.code; body = $e.body; ms = [int]$e.sw.ElapsedMilliseconds }
}

$results | ConvertTo-Json -Compress -Depth 5 | Set-Content -LiteralPath $ResultFile
