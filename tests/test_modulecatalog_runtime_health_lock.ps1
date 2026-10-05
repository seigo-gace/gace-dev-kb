$ErrorActionPreference = 'Stop'

$Repo = Split-Path -Parent $PSScriptRoot
$HealthScript = Join-Path $Repo 'scripts\check-modulecatalog-kb-runtime-windows.ps1'
if (-not (Test-Path $HealthScript)) { throw "HEALTH_SCRIPT_MISSING=$HealthScript" }

$HealthSource = Get-Content $HealthScript -Raw
if ($HealthSource -match 'Get-Content\s+\$file\.FullName\s+-TotalCount\s+\d+\s+-Raw') {
    throw 'HEALTH_GET_CONTENT_INCOMPATIBLE_TOTALCOUNT_RAW_PRESENT'
}
if ($HealthSource -match 'Get-Content\s+\$file\.FullName\s+-TotalCount\s+\d+') {
    throw 'HEALTH_FRONTMATTER_FIXED_LINE_LIMIT_PRESENT'
}
if ($HealthSource -notmatch 'function\s+Get-MarkdownFrontmatter') {
    throw 'HEALTH_FRONTMATTER_READER_MISSING'
}
if ($HealthSource -notmatch 'RUNTIME_REUSABLE_FRONTMATTER_UNTERMINATED') {
    throw 'HEALTH_FRONTMATTER_TERMINATOR_GATE_MISSING'
}
if ($HealthSource -notmatch '\(\?m\)\^\\s\*\-\\s\*"gace-reusable-asset"\\s\*\$') {
    throw 'HEALTH_EXACT_REUSABLE_TAG_GATE_MISSING'
}
if ($HealthSource -match 'Start-Process[^\r\n]+-NoNewWindow') {
    throw 'HEALTH_MVS_STATUS_NONEWWINDOW_EXITCODE_HAZARD_PRESENT'
}
if ($HealthSource -notmatch 'Start-Process[^\r\n]+-WindowStyle\s+Hidden') {
    throw 'HEALTH_MVS_STATUS_HIDDEN_PROCESS_GATE_MISSING'
}
if ($HealthSource -notmatch 'RUNTIME_MVS_STATUS_EXIT_CODE_MISSING') {
    throw 'HEALTH_MVS_STATUS_EXITCODE_NULL_GATE_MISSING'
}

function Invoke-HiddenExitCodeProbe {
    param([Parameter(Mandatory=$true)][int]$Expected)
    if (-not $env:ComSpec -or -not (Test-Path $env:ComSpec)) { throw "COMSPEC_MISSING=$env:ComSpec" }
    $tag = [Guid]::NewGuid().ToString('N')
    $stdout = Join-Path $env:TEMP "gace-exitcode-$tag.stdout.log"
    $stderr = Join-Path $env:TEMP "gace-exitcode-$tag.stderr.log"
    $process = $null
    try {
        $process = Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',"exit $Expected") -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $process.WaitForExit(30000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw "HIDDEN_EXITCODE_PROBE_TIMEOUT=$Expected"
        }
        $process.WaitForExit()
        $process.Refresh()
        $actual = $process.ExitCode
        if ($null -eq $actual) { throw "HIDDEN_EXITCODE_PROBE_NULL=$Expected" }
        if ([int]$actual -ne $Expected) { throw "HIDDEN_EXITCODE_PROBE_MISMATCH expected=$Expected actual=$actual" }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

if ($env:OS -eq 'Windows_NT') {
    Invoke-HiddenExitCodeProbe -Expected 0
    Invoke-HiddenExitCodeProbe -Expected 7
    Write-Host 'MODULECATALOG_RUNTIME_HEALTH_EXITCODE_PROBE=PASS OS=WINDOWS'
}
else {
    Write-Host 'MODULECATALOG_RUNTIME_HEALTH_EXITCODE_PROBE=SKIP OS=NON_WINDOWS'
}

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
