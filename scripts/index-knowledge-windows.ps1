param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [int]$MaxCount = 0
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$ExportScript = Join-Path $Repo 'scripts\export-knowledge-windows.ps1'
$Renderer = Join-Path $Repo 'scripts\render_knowledge_corpus.py'
$BootstrapScript = Join-Path $Repo 'scripts\bootstrap-mvs-windows.ps1'
$VerifyScript = Join-Path $Repo 'tests\verify-mvs-windows.ps1'
$Jsonl = Join-Path $Root 'data\knowledge-records\gace-dev-kb.jsonl'
$SearchRoot = Join-Path $Root 'data\knowledge-search'
$Corpus = Join-Path $SearchRoot 'records'
$Config = Join-Path $SearchRoot '.mcp-vector-search\config.json'
$Bm25Index = Join-Path $SearchRoot '.mcp-vector-search\bm25_index.pkl'
$KnownKuzuCommit = '74e81717473b500642c565bfd228409d59151789'
$KnownAdapterCommit = '4912a442fc44be5fd2bd8e8796af8bd807e954c8'

foreach ($p in @($Python, $Repo, $Mvs, $ExportScript, $Renderer, $BootstrapScript, $VerifyScript)) {
    if (-not (Test-Path $p)) { throw "REQUIRED_PATH_MISSING=$p" }
}
if ($MaxCount -lt 0) { throw "MAX_COUNT_INVALID=$MaxCount" }

function Invoke-MvsCapture {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutSeconds = 600
    )

    $tag = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $env:TEMP "gace-kb-mvs-$tag.stdout.log"
    $stderrPath = Join-Path $env:TEMP "gace-kb-mvs-$tag.stderr.log"
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
            if (((Get-Date) - $startedAt).TotalSeconds -ge $TimeoutSeconds) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                throw "MVS_TIMEOUT=${TimeoutSeconds}s ARGS=$($Arguments -join ' ')"
            }
            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }

        $process.WaitForExit()
        $process.Refresh()
        $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { '' }
        $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { '' }
        $output = ($stdout + [Environment]::NewLine + $stderr).Trim()
        if ($output) { Write-Host $output }

        $exitCode = [int]$process.ExitCode
        $elapsed = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
        Write-Host "COMMAND_EXIT=$exitCode ELAPSED_SEC=$elapsed ARGS=$($Arguments -join ' ')"

        [pscustomobject]@{
            ExitCode = $exitCode
            Stdout   = $stdout
            Stderr   = $stderr
            Output   = $output
        }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Assert-NoClosedWarningRegression {
    param(
        [string]$Output,
        [string]$Stage
    )

    if ($Output -match 'BM25 index building failed') {
        throw "BM25_BUILD_WARNING_PRESENT STAGE=$Stage"
    }
    if ($Output -match 'Hybrid search will fall back to vector-only mode') {
        throw "BM25_VECTOR_FALLBACK_PRESENT STAGE=$Stage"
    }
    if ($Output -match 'get_sentence_embedding_dimension') {
        throw "EMBEDDING_DIMENSION_FUTUREWARNING_PRESENT STAGE=$Stage"
    }
    if ($Output -match 'Could not find entity matching') {
        throw "DOC_ONLY_KG_ENTITY_WARNING_PRESENT STAGE=$Stage"
    }
}

function Assert-CliJsonContainsCommit {
    param(
        [pscustomobject]$Result,
        [string]$Commit,
        [string]$Label
    )

    if ($Result.ExitCode -ne 0) {
        throw "${Label}_CLI_EXIT=$($Result.ExitCode)"
    }
    if (-not $Result.Stdout.Trim()) {
        throw "${Label}_CLI_JSON_EMPTY"
    }

    try {
        $rows = @($Result.Stdout | ConvertFrom-Json)
    }
    catch {
        throw "${Label}_CLI_JSON_INVALID=$($_.Exception.Message)"
    }

    if ($rows.Count -lt 1) {
        throw "${Label}_CLI_NO_RESULTS"
    }

    $jsonText = $Result.Stdout
    if (-not $jsonText.Contains($Commit)) {
        throw "${Label}_CLI_COMMIT_MISSING=$Commit"
    }
}

Write-Host '=== VERIFY WINDOWS MVS COMPATIBILITY ==='
try {
    & $VerifyScript -Root $Root
}
catch {
    Write-Host "COMPAT_VERIFY_NEEDS_REPAIR=$($_.Exception.Message)"
    Write-Host '=== REPAIR WINDOWS MVS COMPATIBILITY ==='
    & $BootstrapScript -Root $Root -Python $Python
    Write-Host '=== REVERIFY WINDOWS MVS COMPATIBILITY ==='
    & $VerifyScript -Root $Root
}

Write-Host '=== EXPORT KNOWLEDGE ==='
& $ExportScript -Root $Root -Python $Python -MaxCount $MaxCount
if ($LASTEXITCODE -ne 0) { throw "KNOWLEDGE_EXPORT_FAILED=$LASTEXITCODE" }
if (-not (Test-Path $Jsonl)) { throw "KNOWLEDGE_JSONL_MISSING=$Jsonl" }

$records = @(Get-Content $Jsonl | Where-Object { $_.Trim() })
$recordCount = $records.Count
if ($recordCount -lt 1) { throw 'KNOWLEDGE_RECORD_COUNT_ZERO' }
$knowledgeText = $records -join "`n"
if (-not $knowledgeText.Contains($KnownKuzuCommit)) {
    throw "KNOWLEDGE_HISTORY_RETENTION_MISSING=$KnownKuzuCommit"
}
if (-not $knowledgeText.Contains($KnownAdapterCommit)) {
    throw "KNOWLEDGE_HISTORY_RETENTION_MISSING=$KnownAdapterCommit"
}
Write-Host "KNOWLEDGE_RECORDS=$recordCount"
Write-Host 'GACE_KNOWLEDGE_HISTORY_RETENTION=PASS COMMIT=74e8171'
Write-Host 'GACE_KNOWLEDGE_HISTORY_RETENTION=PASS COMMIT=4912a442'

Write-Host '=== RENDER SEARCH CORPUS ==='
New-Item -ItemType Directory -Path $SearchRoot -Force | Out-Null
& $Python -B $Renderer --input $Jsonl --output-dir $Corpus
if ($LASTEXITCODE -ne 0) { throw "KNOWLEDGE_CORPUS_RENDER_FAILED=$LASTEXITCODE" }
$corpusCount = @(Get-ChildItem $Corpus -Filter '*.md' -File).Count
if ($corpusCount -ne $recordCount) {
    throw "KNOWLEDGE_CORPUS_COUNT_MISMATCH records=$recordCount corpus=$corpusCount"
}

if (-not (Test-Path $Config)) {
    Write-Host '=== INITIALIZE KNOWLEDGE SEARCH PROJECT ==='
    $initResult = Invoke-MvsCapture `
        -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') `
        -WorkingDirectory $SearchRoot `
        -TimeoutSeconds 180
    if ($initResult.ExitCode -ne 0) { throw "KNOWLEDGE_MVS_INIT_FAILED=$($initResult.ExitCode)" }
    Assert-NoClosedWarningRegression -Output $initResult.Output -Stage 'init'
}

Write-Host '=== INDEX KNOWLEDGE CORPUS ==='
$indexResult = Invoke-MvsCapture -Arguments @('index','--force') -WorkingDirectory $SearchRoot -TimeoutSeconds 600
if ($indexResult.ExitCode -ne 0) { throw "KNOWLEDGE_MVS_INDEX_FAILED=$($indexResult.ExitCode)" }
Assert-NoClosedWarningRegression -Output $indexResult.Output -Stage 'index'
if ($indexResult.Output -match "cannot find context for 'fork'") { throw 'WINDOWS_FORK_CONTEXT_ERROR_PRESENT' }
if ($indexResult.Output -notmatch 'Reindex complete:') { throw 'KNOWLEDGE_INDEX_COMPLETION_MARKER_MISSING' }
if ($indexResult.Output -match 'Reindex complete:\s*0 files,\s*0 chunks') { throw 'KNOWLEDGE_INDEX_ZERO_CORPUS' }
if (-not (Test-Path $Bm25Index)) { throw "BM25_INDEX_MISSING=$Bm25Index" }
Write-Host "MVS_BM25_INDEX=PASS PATH=$Bm25Index"

Write-Host '=== KNOWLEDGE SEARCH STATUS ==='
$statusResult = Invoke-MvsCapture -Arguments @('status') -WorkingDirectory $SearchRoot -TimeoutSeconds 120
if ($statusResult.ExitCode -ne 0) { throw "KNOWLEDGE_MVS_STATUS_FAILED=$($statusResult.ExitCode)" }
Assert-NoClosedWarningRegression -Output $statusResult.Output -Stage 'status'
if ($statusResult.Output -notmatch "Indexed Files:\s+$recordCount/$recordCount") {
    throw "KNOWLEDGE_STATUS_COUNT_MISMATCH expected=$recordCount"
}

# This gate verifies durable identity retrieval, not semantic ranking quality.
# Query the unique full commit IDs directly, request machine-readable JSON, and
# keep semantic phrase retrieval in the MCP E2E where it is already proven.
$deterministicSearchOptions = @(
    '--project-root',$SearchRoot,
    '--limit','100',
    '--threshold','0.0',
    '--search-mode','bm25',
    '--no-expand',
    '--no-rerank',
    '--no-mmr',
    '--quality-weight','0',
    '--no-daemon',
    '--json'
)

Write-Host '=== CLI BM25 IDENTITY SEARCH: WINDOWS KUZU FIX ==='
$kuzuResult = Invoke-MvsCapture `
    -Arguments (@('search',$KnownKuzuCommit) + $deterministicSearchOptions) `
    -WorkingDirectory $SearchRoot `
    -TimeoutSeconds 180
Assert-NoClosedWarningRegression -Output $kuzuResult.Output -Stage 'search-kuzu'
Assert-CliJsonContainsCommit -Result $kuzuResult -Commit $KnownKuzuCommit -Label 'KNOWLEDGE_SEARCH_KUZU'
Write-Host 'KNOWLEDGE_SEARCH_KUZU=PASS COMMIT=74e8171 MODE=bm25 QUERY=full-commit-id'

Write-Host '=== CLI BM25 IDENTITY SEARCH: G-ACE ADAPTER ==='
$adapterResult = Invoke-MvsCapture `
    -Arguments (@('search',$KnownAdapterCommit) + $deterministicSearchOptions) `
    -WorkingDirectory $SearchRoot `
    -TimeoutSeconds 180
Assert-NoClosedWarningRegression -Output $adapterResult.Output -Stage 'search-adapter'
Assert-CliJsonContainsCommit -Result $adapterResult -Commit $KnownAdapterCommit -Label 'KNOWLEDGE_SEARCH_ADAPTER'
Write-Host 'KNOWLEDGE_SEARCH_ADAPTER=PASS COMMIT=4912a442 MODE=bm25 QUERY=full-commit-id'

Write-Host 'MVS_BM25_WARNING_REGRESSION=PASS'
Write-Host 'MVS_EMBEDDING_FUTUREWARNING_REGRESSION=PASS'
Write-Host 'MVS_DOC_ONLY_KG_WARNING_REGRESSION=PASS'
Write-Host "GACE_KNOWLEDGE_INDEX=PASS RECORDS=$recordCount"
Write-Host "SEARCH_ROOT=$SearchRoot"
