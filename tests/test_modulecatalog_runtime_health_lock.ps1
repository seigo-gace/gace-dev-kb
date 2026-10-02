$ErrorActionPreference = 'Stop'

$Repo = Split-Path -Parent $PSScriptRoot
$HealthScript = Join-Path $Repo 'scripts\check-modulecatalog-kb-runtime-windows.ps1'
if (-not (Test-Path $HealthScript)) { throw "HEALTH_SCRIPT_MISSING=$HealthScript" }

$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-health-lock-" + [Guid]::NewGuid().ToString('N'))
$Intake = Join-Path $Root 'data\knowledge-intake\modulecatalog'
$LockPath = Join-Path $Intake 'receive.lock'
New-Item -ItemType Directory -Path $Intake -Force | Out-Null

$Held = $null
try {
    $Held = [System.IO.File]::Open(
        $LockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )

    $output = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HealthScript -Root $Root 2>&1 | Out-String)
    $code = $LASTEXITCODE
    if ($code -eq 0) { throw "HEALTH_LOCK_GATE_FALSE_PASS OUTPUT=$output" }
    if ($output -notmatch 'RUNTIME_RECEIVER_BUSY=') {
        throw "HEALTH_LOCK_GATE_WRONG_ERROR EXIT=$code OUTPUT=$output"
    }
    Write-Host 'MODULECATALOG_RUNTIME_HEALTH_LOCK=PASS'
}
finally {
    if ($null -ne $Held) { $Held.Dispose() }
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
