param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [ValidateRange(1,3600)][int]$PollSeconds = 10,
    [ValidateRange(1,86400)][int]$HeartbeatSeconds = 300,
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

# Use the root Task Scheduler folder so first-time setup does not depend on a
# pre-created custom scheduler folder. The task name remains G-ACE-specific.
$TaskPath = '\'
$TaskName = 'G-ACE-KB-ModuleCatalogReceiver'
$Repo = Join-Path $Root 'repo'
$Watcher = Join-Path $Repo 'scripts\watch-modulecatalog-kb-inbox-windows.ps1'
$IntakeRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog'
$StopPath = Join-Path $IntakeRoot 'receiver.stop'
$CurrentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if (-not $CurrentIdentity) { throw 'CURRENT_WINDOWS_IDENTITY_MISSING' }

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
    '-HeartbeatSeconds',[string]$HeartbeatSeconds
) -join ' '

$action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $arguments -WorkingDirectory $Repo
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $CurrentIdentity
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal `
    -UserId $CurrentIdentity `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskPath $TaskPath `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description 'Consumes transported ModuleCatalog KBData and activates it through the existing G-ACE KB runtime.' `
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
if ([string]$registered.Principal.UserId -ine $CurrentIdentity) {
    throw "RECEIVER_TASK_PRINCIPAL_MISMATCH expected=$CurrentIdentity actual=$($registered.Principal.UserId)"
}

Start-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
$deadline = [DateTime]::UtcNow.AddSeconds(10)
do {
    Start-Sleep -Milliseconds 250
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
    if ($task.State -eq 'Running') { break }
} while ([DateTime]::UtcNow -lt $deadline)

if ($task.State -ne 'Running') {
    throw "RECEIVER_TASK_NOT_RUNNING_AFTER_START=$($task.State)"
}

Write-Host "GACE_MODULECATALOG_RECEIVER_TASK=INSTALLED TASK=${TaskPath}${TaskName} STATE=$($task.State) POLL_SECONDS=$PollSeconds HEARTBEAT_SECONDS=$HeartbeatSeconds"
Write-Host "WATCHER=$Watcher"
Write-Host "STOP_MARKER=$StopPath"
