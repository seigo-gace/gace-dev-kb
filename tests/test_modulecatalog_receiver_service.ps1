$ErrorActionPreference = 'Stop'

$SourceRepo = Split-Path -Parent $PSScriptRoot
$WatcherSource = Join-Path $SourceRepo 'scripts\watch-modulecatalog-kb-inbox-windows.ps1'
if (-not (Test-Path $WatcherSource)) { throw "WATCHER_SOURCE_MISSING=$WatcherSource" }

$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-receiver-service-" + [Guid]::NewGuid().ToString('N'))
$Repo = Join-Path $Root 'repo'
$Scripts = Join-Path $Repo 'scripts'
$Marker = Join-Path $Root 'processor-called.txt'
$HealthMarker = Join-Path $Root 'health-called.txt'
$DeepHealthMarker = Join-Path $Root 'deep-health-called.txt'
$Python = Join-Path $Root 'python.exe'
$ActivationDir = Join-Path $Root 'data\knowledge-records'
$ActivationMarker = Join-Path $ActivationDir 'modulecatalog-reusable-active.json'
New-Item -ItemType Directory -Path $Scripts -Force | Out-Null
New-Item -ItemType Directory -Path $ActivationDir -Force | Out-Null
New-Item -ItemType File -Path $Python -Force | Out-Null
Copy-Item $WatcherSource (Join-Path $Scripts 'watch-modulecatalog-kb-inbox-windows.ps1') -Force

$processor = @'
param([string]$Root,[string]$Python)
Set-Content -Path (Join-Path $Root 'processor-called.txt') -Value "ROOT=$Root`nPYTHON=$Python" -Encoding UTF8
Write-Host 'MOCK_INBOX_PROCESSOR=PASS'
exit 0
'@
Set-Content -Path (Join-Path $Scripts 'process-modulecatalog-inbox-windows.ps1') -Value $processor -Encoding UTF8

$health = @'
param([string]$Root,[switch]$Deep)
if ($Deep) {
    Set-Content -Path (Join-Path $Root 'deep-health-called.txt') -Value "ROOT=$Root`nDEEP=YES" -Encoding UTF8
    Write-Host 'MOCK_RUNTIME_DEEP_HEALTH=PASS'
}
else {
    Set-Content -Path (Join-Path $Root 'health-called.txt') -Value "ROOT=$Root`nDEEP=NO" -Encoding UTF8
    Write-Host 'MOCK_RUNTIME_HEALTH=PASS'
}
exit 0
'@
Set-Content -Path (Join-Path $Scripts 'check-modulecatalog-kb-runtime-windows.ps1') -Value $health -Encoding UTF8
Set-Content -Path $ActivationMarker -Value '{"status":"ACTIVE"}' -Encoding UTF8

try {
    $Watcher = Join-Path $Scripts 'watch-modulecatalog-kb-inbox-windows.ps1'
    & (Get-Process -Id $PID).Path `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $Watcher `
        -Root $Root `
        -Python $Python `
        -PollSeconds 1 `
        -HeartbeatSeconds 60 `
        -RuntimeHealthSeconds 1 `
        -DeepRuntimeHealthSeconds 1 `
        -RetentionSeconds 0 `
        -Once
    if ($LASTEXITCODE -ne 0) { throw "RECEIVER_SERVICE_ONCE_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path $Marker)) { throw "RECEIVER_SERVICE_PROCESSOR_NOT_CALLED=$Marker" }
    if (-not (Test-Path $HealthMarker)) { throw "RECEIVER_SERVICE_HEALTH_NOT_CALLED=$HealthMarker" }
    if (-not (Test-Path $DeepHealthMarker)) { throw "RECEIVER_SERVICE_DEEP_HEALTH_NOT_CALLED=$DeepHealthMarker" }

    $intake = Join-Path $Root 'data\knowledge-intake\modulecatalog'
    $log = Join-Path $intake 'receiver-service.jsonl'
    $lock = Join-Path $intake 'receiver-service.lock'
    if (-not (Test-Path $log)) { throw "RECEIVER_SERVICE_LOG_MISSING=$log" }
    if (Test-Path $lock) { throw "RECEIVER_SERVICE_LOCK_NOT_RELEASED=$lock" }
    $events = @(Get-Content $log | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    if (@($events | Where-Object { $_.status -eq 'STARTED' }).Count -ne 1) { throw 'RECEIVER_SERVICE_STARTED_EVENT_MISSING' }
    if (@($events | Where-Object { $_.status -eq 'HEALTH_PASS' }).Count -ne 1) { throw 'RECEIVER_SERVICE_HEALTH_PASS_EVENT_MISSING' }
    if (@($events | Where-Object { $_.status -eq 'DEEP_HEALTH_PASS' }).Count -ne 1) { throw 'RECEIVER_SERVICE_DEEP_HEALTH_PASS_EVENT_MISSING' }
    if (@($events | Where-Object { $_.status -eq 'POLL_PASS' }).Count -ne 1) { throw 'RECEIVER_SERVICE_POLL_PASS_EVENT_MISSING' }
    if (@($events | Where-Object { $_.status -eq 'STOPPED' }).Count -ne 1) { throw 'RECEIVER_SERVICE_STOPPED_EVENT_MISSING' }

    $held = [System.IO.File]::Open(
        $lock,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    try {
        $busyOutput = (& (Get-Process -Id $PID).Path `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $Watcher `
            -Root $Root `
            -Python $Python `
            -PollSeconds 1 `
            -RuntimeHealthSeconds 0 `
            -DeepRuntimeHealthSeconds 0 `
            -RetentionSeconds 0 `
            -Once 2>&1 | Out-String)
        $busyExit = $LASTEXITCODE
        if ($busyExit -eq 0) { throw 'RECEIVER_SERVICE_SINGLETON_DID_NOT_FAIL' }
        if ($busyOutput -notmatch 'MODULECATALOG_RECEIVER_SERVICE_BUSY') {
            throw "RECEIVER_SERVICE_BUSY_MARKER_MISSING=$busyOutput"
        }
    }
    finally {
        $held.Dispose()
        Remove-Item $lock -Force -ErrorAction SilentlyContinue
    }

    [System.IO.File]::WriteAllText($log, ('x' * 2048), [System.Text.UTF8Encoding]::new($false))
    & (Get-Process -Id $PID).Path `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $Watcher `
        -Root $Root `
        -Python $Python `
        -PollSeconds 1 `
        -RuntimeHealthSeconds 0 `
        -DeepRuntimeHealthSeconds 0 `
        -RetentionSeconds 0 `
        -MaxLogBytes 1024 `
        -MaxLogFiles 2 `
        -Once
    if ($LASTEXITCODE -ne 0) { throw "RECEIVER_SERVICE_ROTATION_RUN_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path "$log.1")) { throw 'RECEIVER_SERVICE_ROTATED_LOG_MISSING' }
    if (-not (Test-Path $log)) { throw 'RECEIVER_SERVICE_CURRENT_LOG_MISSING_AFTER_ROTATION' }
    if ((Get-Item "$log.1").Length -lt 2048) { throw 'RECEIVER_SERVICE_ROTATED_LOG_TRUNCATED' }

    Write-Host 'MODULECATALOG_RECEIVER_SERVICE_TEST=PASS SINGLETON=PASS ROTATION=PASS HEALTH=PASS DEEP_HEALTH=PASS'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
