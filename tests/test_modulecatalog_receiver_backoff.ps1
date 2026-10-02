$ErrorActionPreference = 'Stop'

$SourceRepo = Split-Path -Parent $PSScriptRoot
$WatcherSource = Join-Path $SourceRepo 'scripts\watch-modulecatalog-kb-inbox-windows.ps1'
if (-not (Test-Path $WatcherSource)) { throw "WATCHER_SOURCE_MISSING=$WatcherSource" }

$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-receiver-backoff-" + [Guid]::NewGuid().ToString('N'))
$Repo = Join-Path $Root 'repo'
$Scripts = Join-Path $Repo 'scripts'
$Python = Join-Path $Root 'python.exe'
$Ticks = Join-Path $Root 'processor-ticks.txt'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path $Scripts -Force | Out-Null
New-Item -ItemType File -Path $Python -Force | Out-Null
Copy-Item $WatcherSource (Join-Path $Scripts 'watch-modulecatalog-kb-inbox-windows.ps1') -Force

$processor = @'
param([string]$Root,[string]$Python)
$ErrorActionPreference = 'Stop'
$ticksPath = Join-Path $Root 'processor-ticks.txt'
$count = if (Test-Path $ticksPath) { @(Get-Content $ticksPath | Where-Object { $_.Trim() }).Count } else { 0 }
Add-Content -Path $ticksPath -Value ([DateTime]::UtcNow.Ticks) -Encoding ASCII
if ($count -eq 0) {
    Write-Error 'FIXTURE_TRANSIENT_FAILURE'
    exit 1
}
$intake = Join-Path $Root 'data\knowledge-intake\modulecatalog'
New-Item -ItemType Directory -Path $intake -Force | Out-Null
Set-Content -Path (Join-Path $intake 'receiver.stop') -Value 'stop-after-backoff-proof' -Encoding ASCII
Write-Host 'FIXTURE_SECOND_POLL_PASS'
exit 0
'@
[System.IO.File]::WriteAllText((Join-Path $Scripts 'process-modulecatalog-inbox-windows.ps1'), $processor, $Utf8)

try {
    $Watcher = Join-Path $Scripts 'watch-modulecatalog-kb-inbox-windows.ps1'
    & (Get-Process -Id $PID).Path `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $Watcher `
        -Root $Root `
        -Python $Python `
        -PollSeconds 1 `
        -RetryBackoffSeconds 2 `
        -HeartbeatSeconds 60
    if ($LASTEXITCODE -ne 0) { throw "RECEIVER_BACKOFF_RUN_FAILED=$LASTEXITCODE" }

    $ticks = @(Get-Content $Ticks | Where-Object { $_.Trim() } | ForEach-Object { [int64]$_ })
    if ($ticks.Count -ne 2) { throw "RECEIVER_BACKOFF_POLL_COUNT_INVALID=$($ticks.Count)" }
    $elapsed = [TimeSpan]::FromTicks($ticks[1] - $ticks[0]).TotalSeconds
    if ($elapsed -lt 1.8) { throw "RECEIVER_BACKOFF_TOO_SHORT=$elapsed" }

    $log = Join-Path $Root 'data\knowledge-intake\modulecatalog\receiver-service.jsonl'
    $events = @(Get-Content $log | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    if (@($events | Where-Object { $_.status -eq 'POLL_FAILED' }).Count -ne 1) { throw 'RECEIVER_BACKOFF_FAILURE_EVENT_MISSING' }
    if (@($events | Where-Object { $_.status -eq 'STOPPED' }).Count -ne 1) { throw 'RECEIVER_BACKOFF_STOP_EVENT_MISSING' }

    Write-Host ("GACE_MODULECATALOG_RECEIVER_BACKOFF=PASS ELAPSED_SEC={0:N2}" -f $elapsed)
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
