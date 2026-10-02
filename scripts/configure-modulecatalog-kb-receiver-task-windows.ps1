param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [ValidateRange(1,3600)][int]$PollSeconds = 10,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

if (-not $env:WINDIR) { throw 'WINDOWS_REQUIRED' }
foreach ($command in @('Register-ScheduledTask','Unregister-ScheduledTask','New-ScheduledTaskAction','New-ScheduledTaskTrigger','New-ScheduledTaskSettingsSet','New-ScheduledTaskPrincipal')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "SCHEDULED_TASK_COMMAND_MISSING=$command" }
}

$TaskPath = '\G-ACE-KB\'
$TaskName = 'ModuleCatalogReceiver'
$Repo = Join-Path $Root 'repo'
$Watcher = Join-Path $Repo 'scripts\watch-modulecatalog-kb-inbox-windows.ps1'
$IntakeRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog'
$StopPath = Join-Path $IntakeRoot 'receiver.stop'

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
    '-PollSeconds',[string]$PollSeconds
) -join ' '

$action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $arguments -WorkingDirectory $Repo
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal `
    -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
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

Start-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
$task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
if ($task.State -notin @('Running','Ready')) { throw "RECEIVER_TASK_STATE_INVALID=$($task.State)" }

Write-Host "GACE_MODULECATALOG_RECEIVER_TASK=INSTALLED TASK=${TaskPath}${TaskName} STATE=$($task.State) POLL_SECONDS=$PollSeconds"
Write-Host "WATCHER=$Watcher"
Write-Host "STOP_MARKER=$StopPath"
