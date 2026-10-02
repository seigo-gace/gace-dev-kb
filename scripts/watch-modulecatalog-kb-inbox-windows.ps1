param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [ValidateRange(1,3600)][int]$PollSeconds = 10,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Processor = Join-Path $Repo 'scripts\process-modulecatalog-inbox-windows.ps1'
$IntakeRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog'
$LogPath = Join-Path $IntakeRoot 'receiver-service.jsonl'
$StopPath = Join-Path $IntakeRoot 'receiver.stop'

foreach ($path in @($Repo,$Processor,$Python)) {
    if (-not (Test-Path $path)) { throw "RECEIVER_SERVICE_REQUIRED_PATH_MISSING=$path" }
}
New-Item -ItemType Directory -Path $IntakeRoot -Force | Out-Null

function Write-ServiceEvent {
    param([string]$Status,[string]$Message)
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

Write-ServiceEvent -Status 'STARTED' -Message "Root=$Root PollSeconds=$PollSeconds Once=$Once"
Write-Host "GACE_MODULECATALOG_RECEIVER_SERVICE=STARTED ROOT=$Root POLL_SECONDS=$PollSeconds ONCE=$Once"

while ($true) {
    if (Test-Path $StopPath) {
        Write-ServiceEvent -Status 'STOPPED' -Message "Stop marker detected: $StopPath"
        Write-Host "GACE_MODULECATALOG_RECEIVER_SERVICE=STOPPED MARKER=$StopPath"
        break
    }

    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Processor -Root $Root -Python $Python
        if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_INBOX_PROCESSOR_FAILED=$LASTEXITCODE" }
        Write-ServiceEvent -Status 'POLL_PASS' -Message 'Inbox processor completed.'
    }
    catch {
        $message = [string]$_.Exception.Message
        Write-ServiceEvent -Status 'POLL_FAILED' -Message $message
        Write-Host "GACE_MODULECATALOG_RECEIVER_SERVICE=POLL_FAILED ERROR=$message"
        if ($Once) { throw }
    }

    if ($Once) {
        Write-ServiceEvent -Status 'STOPPED' -Message 'One-shot receiver completed.'
        Write-Host 'GACE_MODULECATALOG_RECEIVER_SERVICE=PASS MODE=ONCE'
        break
    }

    Start-Sleep -Seconds $PollSeconds
}
