param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [ValidateRange(1,3600)][int]$PollSeconds = 10,
    [ValidateRange(1,3600)][int]$RetryBackoffSeconds = 60,
    [ValidateRange(1,86400)][int]$HeartbeatSeconds = 300,
    [ValidateRange(0,86400)][int]$RuntimeHealthSeconds = 300,
    [ValidateRange(0,604800)][int]$RetentionSeconds = 3600,
    [ValidateRange(1,50)][int]$KeepActivationBackups = 3,
    [ValidateRange(1,500)][int]$KeepProcessedDeliveries = 20,
    [ValidateRange(1,500)][int]$KeepFailedDeliveries = 20,
    [ValidateRange(1,100)][int]$KeepAcceptedSnapshots = 5,
    [ValidateRange(1,999)][int]$RestartCount = 12,
    [ValidateRange(1,60)][int]$RestartIntervalMinutes = 1,
    [ValidateRange(5,120)][int]$StartupVerifySeconds = 20,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

if (-not $env:WINDIR) { throw 'WINDOWS_REQUIRED' }
foreach ($command in @(
    'Register-ScheduledTask',
    'Unregister-ScheduledTask',
    'Start-ScheduledTask',
    'Stop-ScheduledTask',
    'Get-ScheduledTask',
    'New-ScheduledTaskAction',
    'New-ScheduledTaskTrigger',
    'New-ScheduledTaskSettingsSet',
    'New-ScheduledTaskPrincipal'
)) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "SCHEDULED_TASK_COMMAND_MISSING=$command" }
}

$TaskPath = '\'
$TaskName = 'G-ACE-KB-ModuleCatalogReceiver'
$Repo = Join-Path $Root 'repo'
$Watcher = Join-Path $Repo 'scripts\watch-modulecatalog-kb-inbox-windows.ps1'
$IntakeRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog'
$StopPath = Join-Path $IntakeRoot 'receiver.stop'
$ServiceLockPath = Join-Path $IntakeRoot 'receiver-service.lock'
$ServiceLogPath = Join-Path $IntakeRoot 'receiver-service.jsonl'
$WindowsIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$CurrentIdentity = $WindowsIdentity.Name
$CurrentSid = if ($null -ne $WindowsIdentity.User) { $WindowsIdentity.User.Value } else { $null }
if (-not $CurrentIdentity) { throw 'CURRENT_WINDOWS_IDENTITY_MISSING' }
if (-not $CurrentSid) { throw 'CURRENT_WINDOWS_SID_MISSING' }

if ($Uninstall) {
    Stop-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $IntakeRoot -Force | Out-Null
    Set-Content -Path $StopPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ASCII
    Write-Host "GACE_MODULECATALOG_RECEIVER_TASK=UNINSTALLED TASK=${TaskPath}${TaskName}"
    exit 0
}

foreach ($path in @($Root,$Repo,$Watcher,$Python)) {
    if (-not (Test-Path $path)) { throw "RECEIVER_TASK_REQUIRED_PATH_MISSING=$path" }
}
New-Item -ItemType Directory -Path $IntakeRoot -Force | Out-Null
Remove-Item $StopPath -Force -ErrorAction SilentlyContinue

$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path $PowerShellExe)) { throw "WINDOWS_POWERSHELL_MISSING=$PowerShellExe" }

$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy','Bypass',
    '-File',('"' + $Watcher + '"'),
    '-Root',('"' + $Root + '"'),
    '-Python',('"' + $Python + '"'),
    '-PollSeconds',[string]$PollSeconds,
    '-RetryBackoffSeconds',[string]$RetryBackoffSeconds,
    '-HeartbeatSeconds',[string]$HeartbeatSeconds,
    '-RuntimeHealthSeconds',[string]$RuntimeHealthSeconds,
    '-RetentionSeconds',[string]$RetentionSeconds,
    '-KeepActivationBackups',[string]$KeepActivationBackups,
    '-KeepProcessedDeliveries',[string]$KeepProcessedDeliveries,
    '-KeepFailedDeliveries',[string]$KeepFailedDeliveries,
    '-KeepAcceptedSnapshots',[string]$KeepAcceptedSnapshots
) -join ' '

$action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $arguments -WorkingDirectory $Repo
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $CurrentIdentity
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -RestartCount $RestartCount `
    -RestartInterval (New-TimeSpan -Minutes $RestartIntervalMinutes) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal `
    -UserId $CurrentIdentity `
    -LogonType Interactive `
    -RunLevel Limited

Stop-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
$stopDeadline = [DateTime]::UtcNow.AddSeconds(10)
do {
    $existing = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $existing -or $existing.State -ne 'Running') { break }
    Start-Sleep -Milliseconds 250
} while ([DateTime]::UtcNow -lt $stopDeadline)
if ($null -ne $existing -and $existing.State -eq 'Running') {
    throw "RECEIVER_TASK_OLD_INSTANCE_DID_NOT_STOP=${TaskPath}${TaskName}"
}

Register-ScheduledTask `
    -TaskPath $TaskPath `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description 'Consumes transported ModuleCatalog KBData, activates it through the existing G-ACE KB runtime, continuously verifies active runtime health, and bounds operational backup/archive retention.' `
    -Force | Out-Null

$registered = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
if (@($registered.Actions).Count -ne 1) { throw "RECEIVER_TASK_ACTION_COUNT_INVALID=$(@($registered.Actions).Count)" }
$registeredAction = @($registered.Actions)[0]
if ([string]$registeredAction.Execute -ine $PowerShellExe) {
    throw "RECEIVER_TASK_EXECUTE_MISMATCH expected=$PowerShellExe actual=$($registeredAction.Execute)"
}
if ([string]$registeredAction.Arguments -ne $arguments) {
    throw "RECEIVER_TASK_ARGUMENTS_MISMATCH expected=$arguments actual=$($registeredAction.Arguments)"
}
if ([string]$registeredAction.WorkingDirectory -ine $Repo) {
    throw "RECEIVER_TASK_WORKDIR_MISMATCH expected=$Repo actual=$($registeredAction.WorkingDirectory)"
}
try {
    $registeredAccount = New-Object System.Security.Principal.NTAccount([string]$registered.Principal.UserId)
    $registeredSid = $registeredAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
}
catch {
    throw "RECEIVER_TASK_PRINCIPAL_SID_RESOLUTION_FAILED user=$($registered.Principal.UserId) error=$($_.Exception.Message)"
}
if ($registeredSid -ne $CurrentSid) {
    throw "RECEIVER_TASK_PRINCIPAL_MISMATCH expectedSid=$CurrentSid actualSid=$registeredSid storedUser=$($registered.Principal.UserId) currentUser=$CurrentIdentity"
}

$StartRequestedUtc = [DateTime]::UtcNow
Start-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
$deadline = [DateTime]::UtcNow.AddSeconds($StartupVerifySeconds)
$startupVerified = $false
$task = $null
do {
    Start-Sleep -Milliseconds 250
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
    if ($task.State -ne 'Running') { continue }
    if (-not (Test-Path $ServiceLockPath) -or -not (Test-Path $ServiceLogPath)) { continue }

    $events = @()
    foreach ($line in @(Get-Content $ServiceLogPath -Tail 50 -ErrorAction SilentlyContinue)) {
        if (-not $line.Trim()) { continue }
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $event) { $events += $event }
        }
        catch { continue }
    }
    $recentStarted = @($events | Where-Object {
        if ($_.status -ne 'STARTED' -or -not $_.atUtc) { return $false }
        try { return ([DateTime]$_.atUtc).ToUniversalTime() -ge $StartRequestedUtc.AddSeconds(-2) }
        catch { return $false }
    })
    if ($recentStarted.Count -gt 0) {
        $startupVerified = $true
        break
    }
} while ([DateTime]::UtcNow -lt $deadline)

if (-not $startupVerified) {
    Stop-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    throw "RECEIVER_TASK_STARTUP_HEALTH_NOT_VERIFIED STATE=$($task.State) LOCK=$ServiceLockPath LOG=$ServiceLogPath"
}

Write-Host "GACE_MODULECATALOG_RECEIVER_TASK=INSTALLED TASK=${TaskPath}${TaskName} STATE=$($task.State) STARTUP=VERIFIED PRINCIPAL_SID=VERIFIED POLL_SECONDS=$PollSeconds RETRY_BACKOFF_SECONDS=$RetryBackoffSeconds HEARTBEAT_SECONDS=$HeartbeatSeconds RUNTIME_HEALTH_SECONDS=$RuntimeHealthSeconds RETENTION_SECONDS=$RetentionSeconds KEEP_BACKUPS=$KeepActivationBackups KEEP_PROCESSED=$KeepProcessedDeliveries KEEP_FAILED=$KeepFailedDeliveries KEEP_ACCEPTED=$KeepAcceptedSnapshots RESTART_COUNT=$RestartCount RESTART_INTERVAL_MIN=$RestartIntervalMinutes"
Write-Host "WATCHER=$Watcher"
Write-Host "STOP_MARKER=$StopPath"
Write-Host "SERVICE_LOG=$ServiceLogPath"
