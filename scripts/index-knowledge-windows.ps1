param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [int]$MaxCount = 0
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$ExportScript = Join-Path $Repo 'scripts\export-knowledge-windows.ps1'
$Renderer = Join-Path $Repo 'scripts\render_knowledge_corpus.py'
$Combiner = Join-Path $Repo 'scripts\combine_knowledge_records.py'
$Importer = Join-Path $Repo 'scripts\import_verified_modulecatalog_skills.py'
$BootstrapScript = Join-Path $Repo 'scripts\bootstrap-mvs-windows.ps1'
$VerifyScript = Join-Path $Repo 'tests\verify-mvs-windows.ps1'
$Bm25Probe = Join-Path $Repo 'tests\bm25_knowledge_retention_probe.py'
$McpHistoryProbe = Join-Path $Repo 'tests\mcp_knowledge_client_e2e.py'
$McpSkillProbe = Join-Path $Repo 'tests\mcp_verified_skill_trial_e2e.py'
$AcceptedConfig = Join-Path $Repo 'config\accepted-knowledge-sources.json'

$RepoJsonl = Join-Path $Root 'data\knowledge-records\gace-dev-kb.jsonl'
$FormalJsonl = Join-Path $Root 'data\knowledge-records\formal-kb.jsonl'
$AcceptedRoot = Join-Path $Root 'data\knowledge-sources\accepted'
$SearchRoot = Join-Path $Root 'data\knowledge-search'
$Corpus = Join-Path $SearchRoot 'records'
$Config = Join-Path $SearchRoot '.mcp-vector-search\config.json'
$Bm25Index = Join-Path $SearchRoot '.mcp-vector-search\bm25_index.pkl'
$KnownKuzuCommit = '74e81717473b500642c565bfd228409d59151789'
$KnownAdapterCommit = '4912a442fc44be5fd2bd8e8796af8bd807e954c8'

foreach ($p in @(
    $Python,$RuntimePython,$Repo,$Mvs,$ExportScript,$Renderer,$Combiner,$Importer,
    $BootstrapScript,$VerifyScript,$Bm25Probe,$McpHistoryProbe,$McpSkillProbe,$AcceptedConfig
)) {
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
        [string]$stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { '' }
        [string]$stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { '' }
        [string]$output = ($stdout + [Environment]::NewLine + $stderr).Trim()
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

function Get-SafeId {
    param([string]$Value)
    return ($Value -replace '[^0-9A-Za-z._-]', '-')
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

Write-Host '=== EXPORT REPOSITORY KNOWLEDGE ==='
& $ExportScript -Root $Root -Python $Python -MaxCount $MaxCount
if ($LASTEXITCODE -ne 0) { throw "KNOWLEDGE_EXPORT_FAILED=$LASTEXITCODE" }
if (-not (Test-Path $RepoJsonl)) { throw "KNOWLEDGE_JSONL_MISSING=$RepoJsonl" }

$repoRecords = @(Get-Content $RepoJsonl | Where-Object { $_.Trim() })
$repoRecordCount = $repoRecords.Count
if ($repoRecordCount -lt 1) { throw 'KNOWLEDGE_RECORD_COUNT_ZERO' }
Write-Host "REPOSITORY_KNOWLEDGE_RECORDS=$repoRecordCount"

Write-Host '=== IMPORT ACCEPTED KNOWLEDGE SOURCES ==='
$registry = Get-Content $AcceptedConfig -Raw | ConvertFrom-Json
if ($registry.schemaVersion -ne 1) { throw "ACCEPTED_SOURCE_SCHEMA_UNSUPPORTED=$($registry.schemaVersion)" }
$sources = @($registry.sources)
if ($sources.Count -lt 1) { throw 'ACCEPTED_SOURCE_REGISTRY_EMPTY' }

New-Item -ItemType Directory -Path $AcceptedRoot -Force | Out-Null
$acceptedInfos = @()

foreach ($source in $sources) {
    if ([string]$source.admission -ne 'verified') {
        throw "ACCEPTED_SOURCE_NOT_VERIFIED=$($source.id)"
    }
    if ([string]$source.kind -ne 'modulecatalog-exported-functions') {
        throw "ACCEPTED_SOURCE_KIND_UNSUPPORTED=$($source.kind)"
    }

    $sourceId = [string]$source.id
    $repository = [string]$source.repository
    $commit = [string]$source.commit
    $assetId = [string]$source.assetId
    $expectedCount = [int]$source.expectedSkillCount
    if (-not $sourceId -or -not $repository -or -not $commit -or -not $assetId -or $expectedCount -lt 1) {
        throw "ACCEPTED_SOURCE_INVALID=$sourceId"
    }

    $safeId = Get-SafeId $sourceId
    $catalogRoot = Join-Path $Root "assets\accepted-$safeId"
    $outputRoot = Join-Path $AcceptedRoot $safeId

    # ModuleCatalog manifests hash canonical Git blob bytes. A Windows checkout
    # with core.autocrlf=true rewrites LF to CRLF and invalidates otherwise-valid
    # manifest size/hash checks. Make the index path independently safe even when
    # it is invoked without the higher-level promotion wrapper.
    if (-not (Test-Path (Join-Path $catalogRoot '.git'))) {
        New-Item -ItemType Directory -Path (Split-Path $catalogRoot) -Force | Out-Null
        git -c core.autocrlf=false clone "https://github.com/$repository.git" $catalogRoot
        if ($LASTEXITCODE -ne 0) { throw "ACCEPTED_SOURCE_CLONE_FAILED=$sourceId" }
    }

    git -C $catalogRoot config core.autocrlf false
    if ($LASTEXITCODE -ne 0) { throw "ACCEPTED_SOURCE_AUTOCRLF_CONFIG_FAILED=$sourceId" }

    git -C $catalogRoot fetch origin
    if ($LASTEXITCODE -ne 0) { throw "ACCEPTED_SOURCE_FETCH_FAILED=$sourceId" }
    git -C $catalogRoot checkout -f --detach $commit
    if ($LASTEXITCODE -ne 0) { throw "ACCEPTED_SOURCE_CHECKOUT_FAILED=$sourceId" }
    git -C $catalogRoot reset --hard $commit
    if ($LASTEXITCODE -ne 0) { throw "ACCEPTED_SOURCE_RESET_FAILED=$sourceId" }

    $actualCommit = (git -C $catalogRoot rev-parse HEAD).Trim()
    if ($actualCommit -ne $commit) {
        throw "ACCEPTED_SOURCE_COMMIT_MISMATCH id=$sourceId expected=$commit actual=$actualCommit"
    }

    $autoCrlf = (git -C $catalogRoot config --get core.autocrlf).Trim()
    if ($autoCrlf -ne 'false') {
        throw "ACCEPTED_SOURCE_AUTOCRLF_NOT_DISABLED id=$sourceId actual=$autoCrlf"
    }
    Write-Host "ACCEPTED_SOURCE_CANONICAL_CHECKOUT=PASS ID=$sourceId COMMIT=$actualCommit AUTOCRLF=$autoCrlf"

    if (Test-Path $outputRoot) { Remove-Item $outputRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

    & $Python -B $Importer `
        --catalog-root $catalogRoot `
        --asset-id $assetId `
        --output-root $outputRoot `
        --expected-skill-count $expectedCount
    if ($LASTEXITCODE -ne 0) { throw "ACCEPTED_SOURCE_IMPORT_FAILED=$sourceId" }

    $recordsPath = Join-Path $outputRoot 'knowledge-records.jsonl'
    $corpusPath = Join-Path $outputRoot 'records'
    $actualRecords = @(Get-Content $recordsPath | Where-Object { $_.Trim() }).Count
    $actualCorpus = @(Get-ChildItem $corpusPath -Filter '*.md' -File).Count
    if ($actualRecords -ne $expectedCount -or $actualCorpus -ne $expectedCount) {
        throw "ACCEPTED_SOURCE_COUNT_MISMATCH id=$sourceId records=$actualRecords corpus=$actualCorpus expected=$expectedCount"
    }

    $acceptedInfos += [pscustomobject]@{
        Id = $safeId
        Records = $recordsPath
        Corpus = $corpusPath
        ExpectedCount = $expectedCount
    }
    Write-Host "GACE_ACCEPTED_SOURCE=PASS ID=$sourceId RECORDS=$actualRecords COMMIT=$actualCommit"
}

Write-Host '=== ASSEMBLE FORMAL KNOWLEDGE RECORDS ==='
$combineArgs = @()
$combineArgs += '--input'
$combineArgs += $RepoJsonl
foreach ($info in $acceptedInfos) {
    $combineArgs += '--input'
    $combineArgs += $info.Records
}
$combineArgs += '--output'
$combineArgs += $FormalJsonl

& $Python -B $Combiner @combineArgs
if ($LASTEXITCODE -ne 0) { throw "FORMAL_KNOWLEDGE_COMBINE_FAILED=$LASTEXITCODE" }
if (-not (Test-Path $FormalJsonl)) { throw "FORMAL_KNOWLEDGE_JSONL_MISSING=$FormalJsonl" }

$formalRecords = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() })
$recordCount = $formalRecords.Count
$expectedFormalCount = $repoRecordCount + (($acceptedInfos | Measure-Object -Property ExpectedCount -Sum).Sum)
if ($recordCount -ne $expectedFormalCount) {
    throw "FORMAL_KNOWLEDGE_COUNT_MISMATCH actual=$recordCount expected=$expectedFormalCount"
}

$knowledgeText = $formalRecords -join "`n"
if (-not $knowledgeText.Contains($KnownKuzuCommit)) {
    throw "KNOWLEDGE_HISTORY_RETENTION_MISSING=$KnownKuzuCommit"
}
if (-not $knowledgeText.Contains($KnownAdapterCommit)) {
    throw "KNOWLEDGE_HISTORY_RETENTION_MISSING=$KnownAdapterCommit"
}
Write-Host "FORMAL_KNOWLEDGE_RECORDS=$recordCount"
Write-Host 'GACE_KNOWLEDGE_HISTORY_RETENTION=PASS COMMIT=74e8171'
Write-Host 'GACE_KNOWLEDGE_HISTORY_RETENTION=PASS COMMIT=4912a442'

Write-Host '=== RENDER FORMAL SEARCH CORPUS ==='
New-Item -ItemType Directory -Path $SearchRoot -Force | Out-Null
# Repository history uses the canonical renderer. Accepted ModuleCatalog sources
# keep their richer verified design/source/evidence Markdown produced by importer.
& $Python -B $Renderer --input $RepoJsonl --output-dir $Corpus
if ($LASTEXITCODE -ne 0) { throw "KNOWLEDGE_CORPUS_RENDER_FAILED=$LASTEXITCODE" }

foreach ($info in $acceptedInfos) {
    foreach ($file in Get-ChildItem $info.Corpus -Filter '*.md' -File) {
        $destination = Join-Path $Corpus ("accepted-$($info.Id)-$($file.Name)")
        Copy-Item $file.FullName $destination -Force
    }
}

$corpusCount = @(Get-ChildItem $Corpus -Filter '*.md' -File).Count
if ($corpusCount -ne $recordCount) {
    throw "KNOWLEDGE_CORPUS_COUNT_MISMATCH records=$recordCount corpus=$corpusCount"
}
Write-Host "GACE_FORMAL_CORPUS=PASS RECORDS=$recordCount CORPUS=$corpusCount"

if (-not (Test-Path $Config)) {
    Write-Host '=== INITIALIZE KNOWLEDGE SEARCH PROJECT ==='
    $initResult = Invoke-MvsCapture `
        -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') `
        -WorkingDirectory $SearchRoot `
        -TimeoutSeconds 180
    if ($initResult.ExitCode -ne 0) { throw "KNOWLEDGE_MVS_INIT_FAILED=$($initResult.ExitCode)" }
    Assert-NoClosedWarningRegression -Output $initResult.Output -Stage 'init'
}

Write-Host '=== INDEX FORMAL KNOWLEDGE CORPUS ==='
$indexResult = Invoke-MvsCapture -Arguments @('index','--force') -WorkingDirectory $SearchRoot -TimeoutSeconds 900
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

Write-Host '=== DIRECT BM25 RETENTION PROBE: WINDOWS KUZU FIX ==='
& $RuntimePython -B $Bm25Probe `
    --search-root $SearchRoot `
    --commit $KnownKuzuCommit `
    --label 'WINDOWS_KUZU_FIX' `
    --limit 100
if ($LASTEXITCODE -ne 0) { throw "BM25_KUZU_PROBE_FAILED=$LASTEXITCODE" }

Write-Host '=== DIRECT BM25 RETENTION PROBE: G-ACE ADAPTER ==='
& $RuntimePython -B $Bm25Probe `
    --search-root $SearchRoot `
    --commit $KnownAdapterCommit `
    --label 'GACE_ADAPTER' `
    --limit 100
if ($LASTEXITCODE -ne 0) { throw "BM25_ADAPTER_PROBE_FAILED=$LASTEXITCODE" }

Write-Host '=== MCP RETRIEVAL: REPOSITORY HISTORY ==='
& $RuntimePython -B $McpHistoryProbe `
    --python $RuntimePython `
    --project-root $SearchRoot `
    --timeout 180
if ($LASTEXITCODE -ne 0) { throw "MCP_HISTORY_E2E_FAILED=$LASTEXITCODE" }

Write-Host '=== MCP RETRIEVAL: ACCEPTED SKILLS ==='
foreach ($info in $acceptedInfos) {
    & $RuntimePython -B $McpSkillProbe `
        --python $RuntimePython `
        --project-root $SearchRoot `
        --records $info.Records `
        --expected-count $info.ExpectedCount `
        --timeout 180
    if ($LASTEXITCODE -ne 0) { throw "MCP_ACCEPTED_SKILL_E2E_FAILED=$($info.Id):$LASTEXITCODE" }
}

Write-Host 'MVS_BM25_WARNING_REGRESSION=PASS'
Write-Host 'MVS_EMBEDDING_FUTUREWARNING_REGRESSION=PASS'
Write-Host 'MVS_DOC_ONLY_KG_WARNING_REGRESSION=PASS'
Write-Host "GACE_KNOWLEDGE_INDEX=PASS RECORDS=$recordCount"
Write-Host "FORMAL_JSONL=$FormalJsonl"
Write-Host "SEARCH_ROOT=$SearchRoot"
