param(
    [string]$Root = 'F:\\G-ACE-KB',
    [string]$ControlBranch = 'control/gace-kb-chat-bridge-v1',
    [ValidateRange(5,3600)][int]$PollSeconds = 15,
    [ValidateRange(10,900)][int]$RequestTimeoutSeconds = 240,
    [ValidateRange(1,999)][int]$RestartCount = 12,
    [ValidateRange(1,60)][int]$RestartIntervalMinutes = 1,
    [ValidateRange(5,120)][int]$StartupVerifySeconds = 20,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
if (-not $env:WINDIR) { throw 'WINDOWS_REQUIRED' }
foreach ($command in @('Register-ScheduledTask','Unregister-ScheduledTask','Start-ScheduledTask','Stop-ScheduledTask','Get-ScheduledTask','New-ScheduledTaskAction','New-ScheduledTaskTrigger','New-ScheduledTaskSettingsSet','New-ScheduledTaskPrincipal')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "CHAT_BRIDGE_TASK_COMMAND_MISSING=$command" }
}

$TaskPath = '\'
$TaskName = 'G-ACE-KB-ChatGitHubBridge'
$Repo = Join-Path $Root 'repo'
$Watcher = Join-Path $Repo 'scripts\\watch-gace-kb-chat-github-bridge-windows.ps1'
$BridgeRoot = Join-Path $Root 'data\\knowledge-intake\\chat-bridge'
$StopPath = Join-Path $BridgeRoot 'watcher.stop'
$LockPath = Join-Path $BridgeRoot 'watcher.lock'
$LogPath = Join-Path $BridgeRoot 'watcher.jsonl'
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$CurrentUser = $Identity.Name
$CurrentSid = if ($null -ne $Identity.User) { $Identity.User.Value } else { $null }
if (-not $CurrentUser -or -not $CurrentSid) { throw 'CHAT_BRIDGE_CURRENT_IDENTITY_MISSING' }

New-Item -ItemType Directory -Path $BridgeRoot -Force | Out-Null
if ($Uninstall) {
    Set-Content -Path $StopPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ASCII
    Stop-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "GACE_KB_CHAT_BRIDGE_TASK=UNINSTALLED TASK=${TaskPath}${TaskName}"
    return
}

foreach ($path in @($Root,$Repo,$Watcher)) {
    if (-not (Test-Path $path)) { throw "CHAT_BRIDGE_TASK_REQUIRED_PATH_MISSING=$path" }
}
Remove-Item $StopPath -Force -ErrorAction SilentlyContinue
$PowerShellExe = Join-Path $env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'
if (-not (Test-Path $PowerShellExe)) { throw "CHAT_BRIDGE_WINDOWS_POWERSHELL_MISSING=$PowerShellExe" }

$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy','Bypass',
    '-File',('"' + $Watcher + '"'),
    '-Root',('"' + $Root + '"'),
    '-ControlBranch',('"' + $ControlBranch + '"'),
    '-PollSeconds',[string]$PollSeconds,
    '-RequestTimeoutSeconds',[string]$RequestTimeoutSeconds
) -join ' '

$action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $arguments -WorkingDirectory $Repo
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount $RestartCount -RestartInterval (New-TimeSpan -Minutes $RestartIntervalMinutes) -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited

Stop-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Relays GPT CHAT GitHub requests to the local G-ACE KB MCP search/exact retrieval runtime and publishes bounded results back to the GitHub control branch.' -Force | Out-Null
$registered = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
if (@($registered.Actions).Count -ne 1) { throw 'CHAT_BRIDGE_TASK_ACTION_COUNT_INVALID' }
$registeredAction = @($registered.Actions)[0]
if ([string]$registeredAction.Execute -ine $PowerShellExe) { throw 'CHAT_BRIDGE_TASK_EXECUTE_MISMATCH' }
if ([string]$registeredAction.Arguments -ne $arguments) { throw 'CHAT_BRIDGE_TASK_ARGUMENTS_MISMATCH' }
if ([string]$registeredAction.WorkingDirectory -ine $Repo) { throw 'CHAT_BRIDGE_TASK_WORKDIR_MISMATCH' }
$registeredAccount = New-Object System.Security.Principal.NTAccount([string]$registered.Principal.UserId)
$registeredSid = $registeredAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
if ($registeredSid -ne $CurrentSid) { throw "CHAT_BRIDGE_TASK_PRINCIPAL_MISMATCH=$registeredSid" }

$StartedUtc = [DateTime]::UtcNow
Start-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
$deadline = [DateTime]::UtcNow.AddSeconds($StartupVerifySeconds)
$verified = $false
do {
    Start-Sleep -Milliseconds 250
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
    if ($task.State -ne 'Running' -or -not (Test-Path $LockPath) -or -not (Test-Path $LogPath)) { continue }
    foreach ($line in @(Get-Content $LogPath -Tail 50 -ErrorAction SilentlyContinue)) {
        if (-not $line.Trim()) { continue }
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
            if ($event.status -eq 'STARTED' -and $event.atUtc -and ([DateTime]$event.atUtc).ToUniversalTime() -ge $StartedUtc.AddSeconds(-2)) { $verified = $true; break }
        } catch {}
    }
    if ($verified) { break }
} while ([DateTime]::UtcNow -lt $deadline)

if (-not $verified) {
    Stop-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    throw "CHAT_BRIDGE_TASK_STARTUP_NOT_VERIFIED LOCK=$LockPath LOG=$LogPath"
}
Write-Host "GACE_KB_CHAT_BRIDGE_TASK=INSTALLED TASK=${TaskPath}${TaskName} STATE=$($task.State) STARTUP=VERIFIED PRINCIPAL_SID=VERIFIED POLL_SECONDS=$PollSeconds CONTROL_BRANCH=$ControlBranch"
