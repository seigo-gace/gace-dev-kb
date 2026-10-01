param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [string]$SourceRepoUrl = 'https://github.com/seigo-gace/Astera.git',
    [string]$SourceRepository = 'seigo-gace/Astera',
    [string]$SourceCommit = '5ef89073',
    [int]$CurrentMaxCount = 80,
    [int]$SourceMaxCount = 20,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$Adapter = Join-Path $Repo 'scripts\gace_knowledge_adapter.py'
$Combiner = Join-Path $Repo 'scripts\combine_knowledge_records.py'
$Renderer = Join-Path $Repo 'scripts\render_knowledge_corpus.py'
$McpTest = Join-Path $Repo 'tests\mcp_cross_repo_reuse_e2e.py'
$Bootstrap = Join-Path $Repo 'scripts\bootstrap-mvs-windows.ps1'
$Verify = Join-Path $Repo 'tests\verify-mvs-windows.ps1'

foreach ($p in @($Python,$Repo,$RuntimePython,$Mvs,$Adapter,$Combiner,$Renderer,$McpTest,$Bootstrap,$Verify)) {
    if (-not (Test-Path $p)) { throw "REQUIRED_PATH_MISSING=$p" }
}

function Invoke-MvsCapture {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [int]$Timeout = 600
    )

    $tag = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $env:TEMP "gace-cross-mvs-$tag.stdout.log"
    $stderrPath = Join-Path $env:TEMP "gace-cross-mvs-$tag.stderr.log"
    $process = $null
    $startedAt = Get-Date

    try {
        $quotedArguments = @(
            foreach ($argument in $Arguments) {
                '"' + ([string]$argument).Replace('"', '\"') + '"'
            }
        )
        $process = Start-Process `
            -FilePath $Mvs `
            -ArgumentList $quotedArguments `
            -WorkingDirectory $WorkingDirectory `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        while (-not $process.HasExited) {
            if (((Get-Date) - $startedAt).TotalSeconds -ge $Timeout) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                throw "MVS_TIMEOUT=${Timeout}s ARGS=$($Arguments -join ' ')"
            }
            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }

        $process.WaitForExit()
        $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { '' }
        $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { '' }
        $output = ($stdout + [Environment]::NewLine + $stderr).Trim()
        if ($output) { Write-Host $output }
        $exitCode = [int]$process.ExitCode
        Write-Host "COMMAND_EXIT=$exitCode ARGS=$($Arguments -join ' ')"
        [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '=== VERIFY MCP/MVS RUNTIME ==='
try {
    & $Verify -Root $Root
}
catch {
    Write-Host "COMPAT_VERIFY_NEEDS_REPAIR=$($_.Exception.Message)"
    & $Bootstrap -Root $Root -Python $Python
    & $Verify -Root $Root
}

$TempRoot = Join-Path $env:TEMP ("gace-cross-repo-" + [Guid]::NewGuid().ToString('N'))
$SourceRepo = Join-Path $TempRoot 'source-repo'
$CurrentJsonl = Join-Path $TempRoot 'current.jsonl'
$SourceJsonl = Join-Path $TempRoot 'source.jsonl'
$CombinedJsonl = Join-Path $TempRoot 'combined.jsonl'
$SearchRoot = Join-Path $TempRoot 'search'
$Corpus = Join-Path $SearchRoot 'records'
$Config = Join-Path $SearchRoot '.mcp-vector-search\config.json'
$success = $false

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
    Write-Host "CROSS_REPO_TEMP_ROOT=$TempRoot"

    Write-Host '=== CLONE SECOND REPOSITORY ==='
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $cloneOutput = & git clone --depth $SourceMaxCount --no-tags $SourceRepoUrl $SourceRepo 2>&1 | Out-String
        $cloneExit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($cloneOutput.Trim()) { Write-Host $cloneOutput.Trim() }
    if ($cloneExit -ne 0) { throw "CROSS_REPO_CLONE_FAILED=$cloneExit" }

    & git -C $SourceRepo cat-file -e "$SourceCommit^{commit}"
    if ($LASTEXITCODE -ne 0) { throw "CROSS_REPO_SOURCE_COMMIT_MISSING=$SourceCommit" }
    Write-Host "CROSS_REPO_SOURCE_COMMIT=PASS COMMIT=$SourceCommit REPOSITORY=$SourceRepository"

    Write-Host '=== EXPORT CURRENT REPOSITORY ==='
    & $Python -B $Adapter --repo $Repo --revision HEAD --max-count $CurrentMaxCount --output $CurrentJsonl
    if ($LASTEXITCODE -ne 0) { throw "CURRENT_REPO_EXPORT_FAILED=$LASTEXITCODE" }

    Write-Host '=== EXPORT SECOND REPOSITORY ==='
    & $Python -B $Adapter --repo $SourceRepo --revision HEAD --max-count $SourceMaxCount --output $SourceJsonl
    if ($LASTEXITCODE -ne 0) { throw "SOURCE_REPO_EXPORT_FAILED=$LASTEXITCODE" }

    Write-Host '=== COMBINE REPOSITORY KNOWLEDGE ==='
    & $Python -B $Combiner --input $CurrentJsonl --input $SourceJsonl --output $CombinedJsonl
    if ($LASTEXITCODE -ne 0) { throw "CROSS_REPO_COMBINE_FAILED=$LASTEXITCODE" }
    $recordCount = @(Get-Content $CombinedJsonl | Where-Object { $_.Trim() }).Count
    if ($recordCount -lt 2) { throw "CROSS_REPO_RECORD_COUNT_INVALID=$recordCount" }

    Write-Host '=== RENDER COMBINED CORPUS ==='
    New-Item -ItemType Directory -Path $SearchRoot -Force | Out-Null
    & $Python -B $Renderer --input $CombinedJsonl --output-dir $Corpus
    if ($LASTEXITCODE -ne 0) { throw "CROSS_REPO_RENDER_FAILED=$LASTEXITCODE" }
    $corpusCount = @(Get-ChildItem $Corpus -Filter '*.md' -File).Count
    if ($corpusCount -ne $recordCount) {
        throw "CROSS_REPO_CORPUS_COUNT_MISMATCH records=$recordCount corpus=$corpusCount"
    }

    Write-Host '=== INITIALIZE COMBINED SEARCH PROJECT ==='
    $init = Invoke-MvsCapture `
        -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') `
        -WorkingDirectory $SearchRoot `
        -Timeout 180
    if ($init.ExitCode -ne 0 -or -not (Test-Path $Config)) {
        throw "CROSS_REPO_MVS_INIT_FAILED=$($init.ExitCode)"
    }

    Write-Host '=== INDEX COMBINED CORPUS ==='
    $index = Invoke-MvsCapture -Arguments @('index','--force') -WorkingDirectory $SearchRoot -Timeout 600
    if ($index.ExitCode -ne 0) { throw "CROSS_REPO_MVS_INDEX_FAILED=$($index.ExitCode)" }
    if ($index.Output -notmatch 'Reindex complete:') { throw 'CROSS_REPO_INDEX_COMPLETION_MARKER_MISSING' }

    Write-Host '=== VERIFY COMBINED INDEX COUNT ==='
    $status = Invoke-MvsCapture -Arguments @('status') -WorkingDirectory $SearchRoot -Timeout 120
    if ($status.ExitCode -ne 0) { throw "CROSS_REPO_MVS_STATUS_FAILED=$($status.ExitCode)" }
    if ($status.Output -notmatch "Indexed Files:\s+$recordCount/$recordCount") {
        throw "CROSS_REPO_STATUS_COUNT_MISMATCH expected=$recordCount"
    }

    Write-Host '=== REAL MCP CROSS-REPOSITORY RETRIEVAL ==='
    & $RuntimePython -B $McpTest `
        --python $RuntimePython `
        --project-root $SearchRoot `
        --timeout $TimeoutSeconds `
        --check 'combine deterministic knowledge records across repositories' 'a017c934' 'seigo-gace/gace-dev-kb' `
        --check 'rewrite FAQ options pricing developer details' $SourceCommit $SourceRepository
    if ($LASTEXITCODE -ne 0) { throw "CROSS_REPO_MCP_REUSE_FAILED=$LASTEXITCODE" }

    Write-Host "GACE_CROSS_REPO_REUSE_E2E=PASS RECORDS=$recordCount REPOSITORIES=2"
    Write-Host "CROSS_REPO_SOURCE=$SourceRepository@$SourceCommit"
    $success = $true
}
finally {
    if (Test-Path $TempRoot) {
        Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($success) {
        Write-Host 'CROSS_REPO_TEMP_CLEANUP=PASS'
    }
}
