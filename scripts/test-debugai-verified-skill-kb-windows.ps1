param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [string]$CatalogCommit = 'bd258ec91b6970853d14a7bf4e65731312a487e3',
    [string]$AssetId = 'debugai-code-repair-verification-skill-pack',
    [int]$ExpectedSkillCount = 13
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$Catalog = Join-Path $Root 'assets\modular-catalog-debugai-trial'
$TrialRoot = Join-Path $Root 'data\debugai-skill-trial'
$Records = Join-Path $TrialRoot 'knowledge-records.jsonl'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$Importer = Join-Path $Repo 'scripts\import_verified_modulecatalog_skills.py'
$Probe = Join-Path $Repo 'tests\mcp_verified_skill_trial_e2e.py'
$VerifyScript = Join-Path $Repo 'tests\verify-mvs-windows.ps1'
$BootstrapScript = Join-Path $Repo 'scripts\bootstrap-mvs-windows.ps1'
$TrialSafetyScript = Join-Path $Repo 'scripts\patch-mvs-windows-trial-safety.ps1'

foreach ($path in @($Repo, $Python, $RuntimePython, $Mvs, $Importer, $Probe, $VerifyScript, $BootstrapScript, $TrialSafetyScript)) {
    if (-not (Test-Path $path)) {
        throw "REQUIRED_PATH_MISSING=$path"
    }
}
if ($ExpectedSkillCount -lt 1) {
    throw "EXPECTED_SKILL_COUNT_INVALID=$ExpectedSkillCount"
}

function Invoke-MvsCapture {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$LogPrefix,
        [int]$TimeoutSeconds = 600
    )

    $stdoutPath = Join-Path $WorkingDirectory "$LogPrefix.stdout.log"
    $stderrPath = Join-Path $WorkingDirectory "$LogPrefix.stderr.log"
    Remove-Item $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

    $quotedArguments = @(
        foreach ($argument in $Arguments) {
            '"' + ([string]$argument).Replace('"', '\"') + '"'
        }
    )

    $process = $null
    $startedAt = Get-Date
    try {
        $process = Start-Process `
            -FilePath $Mvs `
            -ArgumentList $quotedArguments `
            -WorkingDirectory $WorkingDirectory `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        while (-not $process.HasExited) {
            if (((Get-Date) - $startedAt).TotalSeconds -ge $TimeoutSeconds) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                throw "MVS_TIMEOUT=${TimeoutSeconds}s ARGS=$($Arguments -join ' ') STDOUT=$stdoutPath STDERR=$stderrPath"
            }
            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }

        $process.WaitForExit()
        $process.Refresh()
        [string]$stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { '' }
        [string]$stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { '' }

        [pscustomobject]@{
            ExitCode   = [int]$process.ExitCode
            Stdout     = $stdout
            Stderr     = $stderr
            StdoutPath = $stdoutPath
            StderrPath = $stderrPath
        }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Restore-EnvironmentValue {
    param(
        [string]$Name,
        [AllowNull()][string]$Value
    )

    if ($null -eq $Value) {
        Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
    }
    else {
        Set-Item "Env:$Name" $Value
    }
}

Write-Host '=== PREPARE PINNED MODULECATALOG SOURCE ==='
New-Item -ItemType Directory -Path (Split-Path $Catalog) -Force | Out-Null
if (Test-Path $Catalog) {
    Remove-Item $Catalog -Recurse -Force
}

git -c core.autocrlf=false clone --no-checkout https://github.com/seigo-gace/modular-catalog.git $Catalog
if ($LASTEXITCODE -ne 0) {
    throw "MODULECATALOG_CLONE_FAILED=$LASTEXITCODE"
}
git -C $Catalog config core.autocrlf false

git -C $Catalog checkout --detach $CatalogCommit
if ($LASTEXITCODE -ne 0) {
    throw "MODULECATALOG_CHECKOUT_FAILED=$LASTEXITCODE"
}

$actualCatalogCommit = (git -C $Catalog rev-parse HEAD).Trim()
if ($actualCatalogCommit -ne $CatalogCommit) {
    throw "MODULECATALOG_COMMIT_MISMATCH expected=$CatalogCommit actual=$actualCatalogCommit"
}
Write-Host "MODULECATALOG_PINNED=PASS COMMIT=$actualCatalogCommit"

Write-Host "`n=== VERIFY WINDOWS MVS COMPATIBILITY ==="
try {
    & $VerifyScript -Root $Root
}
catch {
    Write-Host "COMPAT_VERIFY_NEEDS_REPAIR=$($_.Exception.Message)"
    & $BootstrapScript -Root $Root -Python $Python
    & $VerifyScript -Root $Root
}

Write-Host "`n=== APPLY ISOLATED WINDOWS TRIAL SAFETY GATE ==="
& $TrialSafetyScript -Root $Root

Write-Host "`n=== IMPORT VERIFIED DEBUGAI SKILLS ==="
if (Test-Path $TrialRoot) {
    Remove-Item $TrialRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $TrialRoot -Force | Out-Null

& $Python -B $Importer `
    --catalog-root $Catalog `
    --asset-id $AssetId `
    --output-root $TrialRoot `
    --expected-skill-count $ExpectedSkillCount
if ($LASTEXITCODE -ne 0) {
    throw "DEBUGAI_SKILL_IMPORT_FAILED=$LASTEXITCODE"
}

if (-not (Test-Path $Records)) {
    throw "DEBUGAI_SKILL_RECORDS_MISSING=$Records"
}
$recordCount = @(Get-Content $Records | Where-Object { $_.Trim() }).Count
$corpusCount = @(Get-ChildItem (Join-Path $TrialRoot 'records') -Filter '*.md' -File).Count
if ($recordCount -ne $ExpectedSkillCount) {
    throw "DEBUGAI_SKILL_RECORD_COUNT_MISMATCH expected=$ExpectedSkillCount actual=$recordCount"
}
if ($corpusCount -ne $ExpectedSkillCount) {
    throw "DEBUGAI_SKILL_CORPUS_COUNT_MISMATCH expected=$ExpectedSkillCount actual=$corpusCount"
}
Write-Host "DEBUGAI_SKILL_DATA=PASS RECORDS=$recordCount CORPUS=$corpusCount"

# This trial has only 13 Markdown documents. Disable the MVS parser ProcessPool
# entirely for this Windows trial so a native child-process crash cannot fan out
# access-violation messages or flood the interactive console. Worker limits remain
# pinned to 1 as a secondary guard. All values are scoped to this process and are
# restored after the trial; normal formal-KB indexing keeps its existing behavior.
$previousDisableMultiprocessing = $env:MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING
$previousWorkers = $env:MCP_VECTOR_SEARCH_WORKERS
$previousMaxWorkers = $env:MCP_VECTOR_SEARCH_MAX_WORKERS
$previousFaulthandler = $env:PYTHONFAULTHANDLER
$env:MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING = '1'
$env:MCP_VECTOR_SEARCH_WORKERS = '1'
$env:MCP_VECTOR_SEARCH_MAX_WORKERS = '1'
$env:PYTHONFAULTHANDLER = '1'

try {
    Write-Host "`n=== INITIALIZE ISOLATED TRIAL KB ==="
    $initResult = Invoke-MvsCapture `
        -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') `
        -WorkingDirectory $TrialRoot `
        -LogPrefix 'mvs-init' `
        -TimeoutSeconds 180
    if ($initResult.ExitCode -ne 0) {
        throw "DEBUGAI_SKILL_MVS_INIT_FAILED=$($initResult.ExitCode) STDOUT=$($initResult.StdoutPath) STDERR=$($initResult.StderrPath)"
    }

    Write-Host "`n=== INDEX VERIFIED DEBUGAI SKILLS ==="
    $indexResult = Invoke-MvsCapture `
        -Arguments @('index','--force') `
        -WorkingDirectory $TrialRoot `
        -LogPrefix 'mvs-index' `
        -TimeoutSeconds 600
    if ($indexResult.ExitCode -ne 0) {
        throw "DEBUGAI_SKILL_MVS_INDEX_FAILED=$($indexResult.ExitCode) STDOUT=$($indexResult.StdoutPath) STDERR=$($indexResult.StderrPath)"
    }
    if ($indexResult.Stdout -notmatch 'Reindex complete:') {
        throw "DEBUGAI_SKILL_MVS_INDEX_COMPLETION_MISSING STDOUT=$($indexResult.StdoutPath) STDERR=$($indexResult.StderrPath)"
    }

    Write-Host "`n=== VERIFY INDEX STATUS ==="
    $statusResult = Invoke-MvsCapture `
        -Arguments @('status') `
        -WorkingDirectory $TrialRoot `
        -LogPrefix 'mvs-status' `
        -TimeoutSeconds 120
    if ($statusResult.ExitCode -ne 0) {
        throw "DEBUGAI_SKILL_MVS_STATUS_FAILED=$($statusResult.ExitCode) STDOUT=$($statusResult.StdoutPath) STDERR=$($statusResult.StderrPath)"
    }
    $status = ($statusResult.Stdout + [Environment]::NewLine + $statusResult.Stderr).Trim()
    if ($status -notmatch "Indexed Files:\s+$ExpectedSkillCount/$ExpectedSkillCount") {
        throw "DEBUGAI_SKILL_INDEX_COUNT_MISMATCH expected=$ExpectedSkillCount STDOUT=$($statusResult.StdoutPath) STDERR=$($statusResult.StderrPath)"
    }
    Write-Host "DEBUGAI_SKILL_MVS_INDEX=PASS FILES=$ExpectedSkillCount MULTIPROCESSING=DISABLED"
}
finally {
    Restore-EnvironmentValue -Name 'MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING' -Value $previousDisableMultiprocessing
    Restore-EnvironmentValue -Name 'MCP_VECTOR_SEARCH_WORKERS' -Value $previousWorkers
    Restore-EnvironmentValue -Name 'MCP_VECTOR_SEARCH_MAX_WORKERS' -Value $previousMaxWorkers
    Restore-EnvironmentValue -Name 'PYTHONFAULTHANDLER' -Value $previousFaulthandler
}

Write-Host "`n=== REAL MCP RETRIEVAL: ALL 13 + NATURAL QUERIES ==="
& $RuntimePython -B $Probe `
    --python $RuntimePython `
    --project-root $TrialRoot `
    --records $Records `
    --expected-count $ExpectedSkillCount
if ($LASTEXITCODE -ne 0) {
    throw "DEBUGAI_SKILL_MCP_E2E_FAILED=$LASTEXITCODE"
}

Write-Host "`n=== FINAL ==="
Write-Host "GACE_DEBUGAI_VERIFIED_SKILL_TRIAL=PASS SKILLS=$ExpectedSkillCount"
Write-Host "PINNED_MODULECATALOG_COMMIT=$CatalogCommit"
Write-Host "TRIAL_ROOT=$TrialRoot"
Write-Host 'FORMAL_KB_UNCHANGED=YES'
