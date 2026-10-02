$ErrorActionPreference = 'Stop'

$Repo = Split-Path -Parent $PSScriptRoot
$HealthScript = Join-Path $Repo 'scripts\check-modulecatalog-kb-runtime-windows.ps1'
if (-not (Test-Path $HealthScript)) { throw "HEALTH_SCRIPT_MISSING=$HealthScript" }

$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-health-lock-" + [Guid]::NewGuid().ToString('N'))
$Intake = Join-Path $Root 'data\knowledge-intake\modulecatalog'
$LockPath = Join-Path $Intake 'receive.lock'
New-Item -ItemType Directory -Path $Intake -Force | Out-Null

$HostExe = (Get-Process -Id $PID).Path
if (-not $HostExe -or -not (Test-Path $HostExe)) { throw "CURRENT_POWERSHELL_HOST_MISSING=$HostExe" }

$Held = $null
try {
    $Held = [System.IO.File]::Open($LockPath,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)

    $output = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $HealthScript -Root $Root 2>&1 | Out-String)
    $code = $LASTEXITCODE
    if ($code -eq 0) { throw "HEALTH_LOCK_GATE_FALSE_PASS OUTPUT=$output" }
    if ($output -notmatch 'RUNTIME_RECEIVER_BUSY=') { throw "HEALTH_LOCK_GATE_WRONG_ERROR EXIT=$code OUTPUT=$output" }
    if (-not (Test-Path $LockPath)) { throw 'HEALTH_EXTERNAL_CHECK_REMOVED_FOREIGN_LOCK' }

    # Internal receiver mode must reuse the already-held lock instead of deadlocking
    # against itself. This fixture intentionally lacks runtime files, so the expected
    # failure moves past locking and reaches the required-path gate.
    $internal = (& $HostExe -NoProfile -ExecutionPolicy Bypass -File $HealthScript -Root $Root -AssumeReceiveLockHeld 2>&1 | Out-String)
    $internalCode = $LASTEXITCODE
    if ($internalCode -eq 0) { throw "HEALTH_INHERITED_LOCK_FALSE_PASS OUTPUT=$internal" }
    if ($internal -match 'RUNTIME_RECEIVER_BUSY=') { throw "HEALTH_INHERITED_LOCK_SELF_DEADLOCK=$internal" }
    if ($internal -notmatch 'RUNTIME_REQUIRED_PATH_MISSING=') { throw "HEALTH_INHERITED_LOCK_WRONG_FAILURE=$internal" }
    if (-not (Test-Path $LockPath)) { throw 'HEALTH_INHERITED_CHECK_REMOVED_RECEIVER_LOCK' }

    Write-Host "MODULECATALOG_RUNTIME_HEALTH_LOCK=PASS OWNED_GATE=PASS INHERITED_GATE=PASS HOST=$HostExe"
}
finally {
    if ($null -ne $Held) { $Held.Dispose() }
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
