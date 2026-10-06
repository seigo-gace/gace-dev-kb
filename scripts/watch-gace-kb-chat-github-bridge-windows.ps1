param(
    [string]$Root = 'F:\\G-ACE-KB',
    [string]$ControlBranch = 'control/gace-kb-chat-bridge-v1',
    [ValidateRange(5,3600)][int]$PollSeconds = 15,
    [ValidateRange(10,900)][int]$RequestTimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Processor = Join-Path $Repo 'scripts\\process-gace-kb-chat-github-bridge-windows.ps1'
$BridgeRoot = Join-Path $Root 'data\\knowledge-intake\\chat-bridge'
$LockPath = Join-Path $BridgeRoot 'watcher.lock'
$LogPath = Join-Path $BridgeRoot 'watcher.jsonl'
$StopPath = Join-Path $BridgeRoot 'watcher.stop'

foreach ($path in @($Root,$Repo,$Processor)) {
    if (-not (Test-Path $path)) { throw "CHAT_BRIDGE_WATCHER_REQUIRED_PATH_MISSING=$path" }
}
New-Item -ItemType Directory -Path $BridgeRoot -Force | Out-Null

function Write-BridgeEvent {
    param([string]$Status,[string]$Detail='')
    $event = [ordered]@{
        schema_version = 'gace.kb.chat-bridge-event.v1'
        status = $Status
        atUtc = [DateTime]::UtcNow.ToString('o')
        detail = $Detail
    } | ConvertTo-Json -Compress
    Add-Content -Path $LogPath -Value $event -Encoding UTF8
}

$lock = $null
try {
    try {
        $lock = [System.IO.File]::Open($LockPath,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    } catch {
        throw "CHAT_BRIDGE_WATCHER_ALREADY_RUNNING=$LockPath"
    }
    Remove-Item $StopPath -Force -ErrorAction SilentlyContinue
    Write-BridgeEvent -Status 'STARTED' -Detail ("branch={0}" -f $ControlBranch)
    while ($true) {
        if (Test-Path $StopPath) {
            Write-BridgeEvent -Status 'STOPPED' -Detail 'stop-marker'
            break
        }
        try {
            $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Processor -Root $Root -ControlBranch $ControlBranch -MaxRequests 10 -TimeoutSeconds $RequestTimeoutSeconds 2>&1)
            $code = $LASTEXITCODE
            $detail = ($output -join [Environment]::NewLine)
            if ($detail.Length -gt 4000) { $detail = $detail.Substring($detail.Length - 4000) }
            if ($code -eq 0) { Write-BridgeEvent -Status 'POLL_PASS' -Detail $detail }
            else { Write-BridgeEvent -Status 'POLL_FAIL' -Detail ("exit={0} {1}" -f $code,$detail) }
        } catch {
            Write-BridgeEvent -Status 'POLL_EXCEPTION' -Detail $_.Exception.Message
        }
        Start-Sleep -Seconds $PollSeconds
    }
}
finally {
    if ($null -ne $lock) { $lock.Dispose() }
    Remove-Item $LockPath -Force -ErrorAction SilentlyContinue
}
