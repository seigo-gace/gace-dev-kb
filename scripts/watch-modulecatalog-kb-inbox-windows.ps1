param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [ValidateRange(1,3600)][int]$PollSeconds = 10,
    [ValidateRange(1,3600)][int]$RetryBackoffSeconds = 60,
    [ValidateRange(1,86400)][int]$HeartbeatSeconds = 300,
    [ValidateRange(0,86400)][int]$RuntimeHealthSeconds = 300,
    [ValidateRange(1024,1073741824)][long]$MaxLogBytes = 5242880,
    [ValidateRange(1,20)][int]$MaxLogFiles = 5,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Processor = Join-Path $Repo 'scripts\process-modulecatalog-inbox-windows.ps1'
$HealthCheck = Join-Path $Repo 'scripts\check-modulecatalog-kb-runtime-windows.ps1'
$ActivationMarker = Join-Path $Root 'data\knowledge-records\modulecatalog-reusable-active.json'
$IntakeRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog'
$LogPath = Join-Path $IntakeRoot 'receiver-service.jsonl'
$StopPath = Join-Path $IntakeRoot 'receiver.stop'
$ServiceLockPath = Join-Path $IntakeRoot 'receiver-service.lock'

$required = @($Repo,$Processor,$Python)
if ($RuntimeHealthSeconds -gt 0) { $required += $HealthCheck }
foreach ($path in $required) {
    if (-not (Test-Path $path)) { throw "RECEIVER_SERVICE_REQUIRED_PATH_MISSING=$path" }
}
$PowerShellHost = (Get-Process -Id $PID).Path
if (-not $PowerShellHost -or -not (Test-Path $PowerShellHost)) {
    throw "RECEIVER_SERVICE_POWERSHELL_HOST_MISSING=$PowerShellHost"
}
New-Item -ItemType Directory -Path $IntakeRoot -Force | Out-Null

$ServiceLock = $null
$OwnsServiceLock = $false
try {
    try {
        $ServiceLock = [System.IO.File]::Open(
            $ServiceLockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        $OwnsServiceLock = $true
    }
    catch {
        throw "MODULECATALOG_RECEIVER_SERVICE_BUSY=$ServiceLockPath"
    }

    function Invoke-LogRotation {
        if (-not (Test-Path $LogPath)) { return }
        $length = (Get-Item $LogPath).Length
        if ($length -lt $MaxLogBytes) { return }

        $oldest = "$LogPath.$MaxLogFiles"
        Remove-Item $oldest -Force -ErrorAction SilentlyContinue
        for ($index = $MaxLogFiles - 1; $index -ge 1; $index--) {
            $source = "$LogPath.$index"
            $target = "$LogPath.$($index + 1)"
            if (Test-Path $source) { Move-Item $source $target -Force }
        }
        Move-Item $LogPath "$LogPath.1" -Force
    }

    function Write-ServiceEvent {
        param([string]$Status,[string]$Message)
        Invoke-LogRotation
        $event = [ordered]@{
            schemaVersion = 1
            atUtc = [DateTime]::UtcNow.ToString('o')
            status = $Status
            message = $Message
            pid = $PID
        }
        $json = $event | ConvertTo-Json -Compress
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $stream = New-Object System.IO.FileStream($LogPath,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,[System.IO.FileShare]::ReadWrite)
        try {
            $writer = New-Object System.IO.StreamWriter($stream,$encoding)
            try { $writer.WriteLine($json); $writer.Flush() } finally { $writer.Dispose() }
        }
        finally { $stream.Dispose() }
    }

    Write-ServiceEvent -Status 'STARTED' -Message "Root=$Root PollSeconds=$PollSeconds RetryBackoffSeconds=$RetryBackoffSeconds HeartbeatSeconds=$HeartbeatSeconds RuntimeHealthSeconds=$RuntimeHealthSeconds Once=$Once Host=$PowerShellHost"
    Write-Host "GACE_MODULECATALOG_RECEIVER_SERVICE=STARTED ROOT=$Root POLL_SECONDS=$PollSeconds RETRY_BACKOFF_SECONDS=$RetryBackoffSeconds HEARTBEAT_SECONDS=$HeartbeatSeconds RUNTIME_HEALTH_SECONDS=$RuntimeHealthSeconds ONCE=$Once HOST=$PowerShellHost"

    $LastPassLogUtc = [DateTime]::MinValue
    $LastHealthUtc = [DateTime]::MinValue
    while ($true) {
        if (Test-Path $StopPath) {
            Write-ServiceEvent -Status 'STOPPED' -Message "Stop marker detected: $StopPath"
            Write-Host "GACE_MODULECATALOG_RECEIVER_SERVICE=STOPPED MARKER=$StopPath"
            break
        }

        $nextSleepSeconds = $PollSeconds
        try {
            & $PowerShellHost -NoProfile -ExecutionPolicy Bypass -File $Processor -Root $Root -Python $Python
            if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_INBOX_PROCESSOR_FAILED=$LASTEXITCODE" }

            $now = [DateTime]::UtcNow
            if ($RuntimeHealthSeconds -gt 0 -and (Test-Path $ActivationMarker) -and (($now - $LastHealthUtc).TotalSeconds -ge $RuntimeHealthSeconds)) {
                & $PowerShellHost -NoProfile -ExecutionPolicy Bypass -File $HealthCheck -Root $Root
                if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_RUNTIME_HEALTH_FAILED=$LASTEXITCODE" }
                $LastHealthUtc = [DateTime]::UtcNow
                Write-ServiceEvent -Status 'HEALTH_PASS' -Message "Active KB runtime health passed. Marker=$ActivationMarker"
                Write-Host "GACE_MODULECATALOG_RECEIVER_SERVICE=HEALTH_PASS MARKER=$ActivationMarker"
            }

            $now = [DateTime]::UtcNow
            if ($Once -or (($now - $LastPassLogUtc).TotalSeconds -ge $HeartbeatSeconds)) {
                Write-ServiceEvent -Status 'POLL_PASS' -Message 'Inbox processor completed.'
                $LastPassLogUtc = $now
            }
        }
        catch {
            $message = [string]$_.Exception.Message
            $status = if ($message -match 'MODULECATALOG_RUNTIME_HEALTH_FAILED|RUNTIME_') { 'HEALTH_FAILED' } else { 'POLL_FAILED' }
            Write-ServiceEvent -Status $status -Message $message
            Write-Host "GACE_MODULECATALOG_RECEIVER_SERVICE=$status ERROR=$message"
            if ($Once) { throw }
            $nextSleepSeconds = [Math]::Max($PollSeconds,$RetryBackoffSeconds)
            Write-Host "GACE_MODULECATALOG_RECEIVER_SERVICE=BACKOFF SECONDS=$nextSleepSeconds"
        }

        if ($Once) {
            Write-ServiceEvent -Status 'STOPPED' -Message 'One-shot receiver completed.'
            Write-Host 'GACE_MODULECATALOG_RECEIVER_SERVICE=PASS MODE=ONCE'
            break
        }

        Start-Sleep -Seconds $nextSleepSeconds
    }
}
finally {
    if ($null -ne $ServiceLock) {
        $ServiceLock.Dispose()
        $ServiceLock = $null
    }
    if ($OwnsServiceLock) {
        Remove-Item $ServiceLockPath -Force -ErrorAction SilentlyContinue
    }
}
