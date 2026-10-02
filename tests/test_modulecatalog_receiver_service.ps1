$ErrorActionPreference = 'Stop'

$SourceRepo = Split-Path -Parent $PSScriptRoot
$WatcherSource = Join-Path $SourceRepo 'scripts\watch-modulecatalog-kb-inbox-windows.ps1'
if (-not (Test-Path $WatcherSource)) { throw "WATCHER_SOURCE_MISSING=$WatcherSource" }

$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-receiver-service-" + [Guid]::NewGuid().ToString('N'))
$Repo = Join-Path $Root 'repo'
$Scripts = Join-Path $Repo 'scripts'
$Marker = Join-Path $Root 'processor-called.txt'
$Python = Join-Path $Root 'python.exe'
New-Item -ItemType Directory -Path $Scripts -Force | Out-Null
New-Item -ItemType File -Path $Python -Force | Out-Null
Copy-Item $WatcherSource (Join-Path $Scripts 'watch-modulecatalog-kb-inbox-windows.ps1') -Force

$processor = @'
param([string]$Root,[string]$Python)
Set-Content -Path (Join-Path $Root 'processor-called.txt') -Value "ROOT=$Root`nPYTHON=$Python" -Encoding UTF8
Write-Host 'MOCK_INBOX_PROCESSOR=PASS'
exit 0
'@
Set-Content -Path (Join-Path $Scripts 'process-modulecatalog-inbox-windows.ps1') -Value $processor -Encoding UTF8

try {
    & (Get-Process -Id $PID).Path `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $Scripts 'watch-modulecatalog-kb-inbox-windows.ps1') `
        -Root $Root `
        -Python $Python `
        -PollSeconds 1 `
        -Once
    if ($LASTEXITCODE -ne 0) { throw "RECEIVER_SERVICE_ONCE_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path $Marker)) { throw "RECEIVER_SERVICE_PROCESSOR_NOT_CALLED=$Marker" }

    $log = Join-Path $Root 'data\knowledge-intake\modulecatalog\receiver-service.jsonl'
    if (-not (Test-Path $log)) { throw "RECEIVER_SERVICE_LOG_MISSING=$log" }
    $events = @(Get-Content $log | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    if (@($events | Where-Object { $_.status -eq 'STARTED' }).Count -ne 1) { throw 'RECEIVER_SERVICE_STARTED_EVENT_MISSING' }
    if (@($events | Where-Object { $_.status -eq 'POLL_PASS' }).Count -ne 1) { throw 'RECEIVER_SERVICE_POLL_PASS_EVENT_MISSING' }
    if (@($events | Where-Object { $_.status -eq 'STOPPED' }).Count -ne 1) { throw 'RECEIVER_SERVICE_STOPPED_EVENT_MISSING' }

    Write-Host 'MODULECATALOG_RECEIVER_SERVICE_TEST=PASS'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
