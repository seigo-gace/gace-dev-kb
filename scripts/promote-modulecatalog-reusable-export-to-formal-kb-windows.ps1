param(
    [string]$Root = 'F:\G-ACE-KB',
    [Parameter(Mandatory=$true)][string]$CatalogCommit,
    [int]$ExpectedAssetCount = 80,
    [int]$ExpectedRecordCount = 720
)

$ErrorActionPreference = 'Stop'
if ($ExpectedAssetCount -lt 1) { throw "EXPECTED_ASSET_COUNT_INVALID=$ExpectedAssetCount" }
if ($ExpectedRecordCount -lt 1) { throw "EXPECTED_RECORD_COUNT_INVALID=$ExpectedRecordCount" }

$Repo = Join-Path $Root 'repo'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$Combiner = Join-Path $Repo 'scripts\combine_knowledge_records.py'
$SafetyPatch = Join-Path $Repo 'scripts\patch-mvs-windows-trial-safety.ps1'
$HistoryProbe = Join-Path $Repo 'tests\mcp_knowledge_client_e2e.py'
$SkillProbe = Join-Path $Repo 'tests\mcp_verified_skill_trial_e2e.py'
$ReusableProbe = Join-Path $Repo 'tests\mcp_reusable_asset_e2e.py'

$TrialRoot = Join-Path $Root 'data\modulecatalog-reusable-trial'
$TrialMarker = Join-Path $TrialRoot 'trial-pass.json'
$TrialExportManifest = Join-Path $TrialRoot 'export\manifest.json'
$TrialImport = Join-Path $TrialRoot 'import'
$NewRecords = Join-Path $TrialImport 'knowledge-records.jsonl'
$NewMetadata = Join-Path $TrialImport 'knowledge-metadata.jsonl'
$NewCorpus = Join-Path $TrialImport 'records'

$FormalJsonl = Join-Path $Root 'data\knowledge-records\formal-kb.jsonl'
$NextFormal = Join-Path $Root 'data\knowledge-records\formal-kb.reusable-next.jsonl'
$CurrentSearch = Join-Path $Root 'data\knowledge-search'
$CurrentRecords = Join-Path $CurrentSearch 'records'
$StagingSearch = Join-Path $Root 'data\knowledge-search.reusable-staging'
$StagingRecords = Join-Path $StagingSearch 'records'
$OldSkillRecords = Join-Path $Root 'data\knowledge-sources\accepted\debugai-code-repair-verification-skill-pack\knowledge-records.jsonl'
$PromotionMarker = Join-Path $Root 'data\knowledge-records\modulecatalog-reusable-promotion-pass.json'

foreach ($path in @($Repo,$RuntimePython,$Mvs,$Combiner,$SafetyPatch,$HistoryProbe,$SkillProbe,$ReusableProbe,$TrialMarker,$TrialExportManifest,$NewRecords,$NewMetadata,$NewCorpus,$FormalJsonl,$CurrentSearch,$CurrentRecords)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash
}

function Restore-EnvironmentValue {
    param([string]$Name,[AllowNull()][string]$Value)
    if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$Name" $Value }
}

function Invoke-MvsCapture {
    param([string[]]$Arguments,[int]$TimeoutSeconds = 1800,[string]$WorkingDirectory = $StagingSearch)
    $tag = [Guid]::NewGuid().ToString('N')
    $stdout = Join-Path $env:TEMP "gace-formal-reusable-$tag.stdout.log"
    $stderr = Join-Path $env:TEMP "gace-formal-reusable-$tag.stderr.log"
    $process = $null
    $started = Get-Date
    try {
        $quoted = @(foreach ($argument in $Arguments) { '"' + ([string]$argument).Replace('"','\"') + '"' })
        $process = Start-Process -FilePath $Mvs -ArgumentList $quoted -WorkingDirectory $WorkingDirectory -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        while (-not $process.HasExited) {
            if (((Get-Date) - $started).TotalSeconds -ge $TimeoutSeconds) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                throw "MVS_TIMEOUT=${TimeoutSeconds}s ARGS=$($Arguments -join ' ')"
            }
            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }
        $process.WaitForExit()
        $process.Refresh()
        [string]$out = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { '' }
        [string]$err = if (Test-Path $stderr) { Get-Content $stderr -Raw } else { '' }
        [string]$all = ($out + [Environment]::NewLine + $err).Trim()
        if ($all) { Write-Host $all }
        [pscustomobject]@{ ExitCode=[int]$process.ExitCode; Output=$all }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '=== VERIFY ISOLATED TRIAL AUTHORITY ==='
$Marker = Get-Content $TrialMarker -Raw | ConvertFrom-Json
if ($Marker.schemaVersion -ne 1 -or [string]$Marker.status -ne 'PASS') { throw 'TRIAL_MARKER_INVALID' }
if ([string]$Marker.catalogCommit -ne $CatalogCommit) { throw "TRIAL_COMMIT_MISMATCH expected=$CatalogCommit actual=$($Marker.catalogCommit)" }
if ([int]$Marker.assetCount -ne $ExpectedAssetCount) { throw "TRIAL_ASSET_COUNT_MISMATCH expected=$ExpectedAssetCount actual=$($Marker.assetCount)" }
if ([int]$Marker.recordCount -ne $ExpectedRecordCount) { throw "TRIAL_RECORD_COUNT_MISMATCH expected=$ExpectedRecordCount actual=$($Marker.recordCount)" }
if ((Get-Sha256 $TrialExportManifest) -ne [string]$Marker.exportManifestSha256) { throw 'TRIAL_EXPORT_MANIFEST_HASH_MISMATCH' }
if ((Get-Sha256 $NewRecords) -ne [string]$Marker.knowledgeRecordsSha256) { throw 'TRIAL_KNOWLEDGE_RECORDS_HASH_MISMATCH' }
if ((Get-Sha256 $NewMetadata) -ne [string]$Marker.knowledgeMetadataSha256) { throw 'TRIAL_KNOWLEDGE_METADATA_HASH_MISMATCH' }
$CurrentFormalHash = Get-Sha256 $FormalJsonl
if ($CurrentFormalHash -ne [string]$Marker.formalKbAfterSha256) { throw "FORMAL_KB_CHANGED_SINCE_TRIAL current=$CurrentFormalHash trial=$($Marker.formalKbAfterSha256)" }
Write-Host "TRIAL_AUTHORITY=PASS COMMIT=$CatalogCommit ASSETS=$ExpectedAssetCount RECORDS=$ExpectedRecordCount"

$BaseCount = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() }).Count
$BaseCorpusCount = @(Get-ChildItem $CurrentRecords -Filter '*.md' -File).Count
if ($BaseCount -lt 1) { throw 'BASE_FORMAL_RECORD_COUNT_ZERO' }
if ($BaseCorpusCount -ne $BaseCount) { throw "BASE_FORMAL_CORPUS_COUNT_MISMATCH records=$BaseCount corpus=$BaseCorpusCount" }
$ExpectedTotal = $BaseCount + $ExpectedRecordCount
Write-Host "BASE_FORMAL_KB=PASS RECORDS=$BaseCount CORPUS=$BaseCorpusCount EXPECTED_TOTAL=$ExpectedTotal"

Write-Host '=== BUILD NEXT FORMAL RECORD SET ==='
Remove-Item $NextFormal -Force -ErrorAction SilentlyContinue
& $RuntimePython -B $Combiner --input $FormalJsonl --input $NewRecords --output $NextFormal
if ($LASTEXITCODE -ne 0) { throw "FORMAL_REUSABLE_COMBINE_FAILED=$LASTEXITCODE" }
$NextCount = @(Get-Content $NextFormal | Where-Object { $_.Trim() }).Count
if ($NextCount -ne $ExpectedTotal) { throw "FORMAL_REUSABLE_COUNT_MISMATCH expected=$ExpectedTotal actual=$NextCount" }
Write-Host "NEXT_FORMAL_RECORDS=PASS RECORDS=$NextCount"

Write-Host '=== BUILD STAGING SEARCH CORPUS ==='
if (Test-Path $StagingSearch) { Remove-Item $StagingSearch -Recurse -Force }
New-Item -ItemType Directory -Path $StagingSearch -Force | Out-Null
$init = Invoke-MvsCapture -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') -TimeoutSeconds 180
if ($init.ExitCode -ne 0) { throw "STAGING_MVS_INIT_FAILED=$($init.ExitCode)" }
New-Item -ItemType Directory -Path $StagingRecords -Force | Out-Null
Copy-Item (Join-Path $CurrentRecords '*.md') $StagingRecords -Force
$prefix = "accepted-modulecatalog-reusable-$($CatalogCommit.Substring(0,12))-"
foreach ($file in Get-ChildItem $NewCorpus -Filter '*.md' -File) {
    Copy-Item $file.FullName (Join-Path $StagingRecords ($prefix + $file.Name)) -Force
}
$StagingCorpusCount = @(Get-ChildItem $StagingRecords -Filter '*.md' -File).Count
if ($StagingCorpusCount -ne $ExpectedTotal) { throw "STAGING_CORPUS_COUNT_MISMATCH expected=$ExpectedTotal actual=$StagingCorpusCount" }
Write-Host "STAGING_CORPUS=PASS RECORDS=$StagingCorpusCount"

Write-Host '=== INDEX STAGING FORMAL KB ==='
& $SafetyPatch -Root $Root
$names = @('MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING','MCP_VECTOR_SEARCH_WORKERS','MCP_VECTOR_SEARCH_MAX_WORKERS','MCP_VECTOR_SEARCH_BATCH_SIZE','MCP_VECTOR_SEARCH_FILE_BATCH_SIZE','OMP_NUM_THREADS','MKL_NUM_THREADS','OPENBLAS_NUM_THREADS','NUMEXPR_NUM_THREADS','TOKENIZERS_PARALLELISM')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    $env:MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING='1'
    $env:MCP_VECTOR_SEARCH_WORKERS='1'
    $env:MCP_VECTOR_SEARCH_MAX_WORKERS='1'
    $env:MCP_VECTOR_SEARCH_BATCH_SIZE='8'
    $env:MCP_VECTOR_SEARCH_FILE_BATCH_SIZE='16'
    $env:OMP_NUM_THREADS='1'
    $env:MKL_NUM_THREADS='1'
    $env:OPENBLAS_NUM_THREADS='1'
    $env:NUMEXPR_NUM_THREADS='1'
    $env:TOKENIZERS_PARALLELISM='false'

    $index = Invoke-MvsCapture -Arguments @('index','--force') -TimeoutSeconds 2400
    if ($index.ExitCode -ne 0) { throw "STAGING_MVS_INDEX_FAILED=$($index.ExitCode)" }
    if ($index.Output -notmatch 'Reindex complete:') { throw 'STAGING_INDEX_COMPLETION_MARKER_MISSING' }
    if ($index.Output -match 'BM25 index building failed') { throw 'STAGING_BM25_BUILD_WARNING_PRESENT' }
    if ($index.Output -match 'Hybrid search will fall back to vector-only mode') { throw 'STAGING_VECTOR_ONLY_FALLBACK_PRESENT' }

    $status = Invoke-MvsCapture -Arguments @('status') -TimeoutSeconds 180
    if ($status.ExitCode -ne 0) { throw "STAGING_MVS_STATUS_FAILED=$($status.ExitCode)" }
    if ($status.Output -notmatch "Indexed Files:\s+$ExpectedTotal/$ExpectedTotal") { throw "STAGING_INDEX_COUNT_MISMATCH expected=$ExpectedTotal" }
}
finally {
    foreach ($name in $names) { Restore-EnvironmentValue -Name $name -Value $previous[$name] }
}

Write-Host '=== STAGING MCP REGRESSION: REPOSITORY HISTORY ==='
& $RuntimePython -B $HistoryProbe --python $RuntimePython --project-root $StagingSearch --timeout 180
if ($LASTEXITCODE -ne 0) { throw "STAGING_HISTORY_MCP_FAILED=$LASTEXITCODE" }

if (Test-Path $OldSkillRecords) {
    $OldSkillCount = @(Get-Content $OldSkillRecords | Where-Object { $_.Trim() }).Count
    Write-Host '=== STAGING MCP REGRESSION: EXISTING ACCEPTED SKILLS ==='
    & $RuntimePython -B $SkillProbe --python $RuntimePython --project-root $StagingSearch --records $OldSkillRecords --expected-count $OldSkillCount --timeout 180
    if ($LASTEXITCODE -ne 0) { throw "STAGING_EXISTING_SKILL_MCP_FAILED=$LASTEXITCODE" }
}

Write-Host '=== STAGING MCP: MODULECATALOG REUSABLE ASSETS ==='
& $RuntimePython -B $ReusableProbe --python $RuntimePython --project-root $StagingSearch --metadata $NewMetadata --expected-count $ExpectedRecordCount --timeout 180
if ($LASTEXITCODE -ne 0) { throw "STAGING_REUSABLE_MCP_FAILED=$LASTEXITCODE" }
Write-Host 'STAGING_FORMAL_KB=PASS'

Write-Host '=== VERIFIED CUTOVER ==='
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$BackupSearch = Join-Path $Root "data\knowledge-search.previous-$timestamp"
$BackupFormal = Join-Path $Root "data\knowledge-records\formal-kb.previous-$timestamp.jsonl"
Copy-Item $FormalJsonl $BackupFormal -Force
$SearchMoved = $false
try {
    Move-Item $CurrentSearch $BackupSearch
    $SearchMoved = $true
    Move-Item $StagingSearch $CurrentSearch
    Move-Item $NextFormal $FormalJsonl -Force
}
catch {
    if (Test-Path $CurrentSearch) {
        $FailedSearch = Join-Path $Root "data\knowledge-search.failed-cutover-$timestamp"
        Move-Item $CurrentSearch $FailedSearch -ErrorAction SilentlyContinue
    }
    if ($SearchMoved -and (Test-Path $BackupSearch) -and -not (Test-Path $CurrentSearch)) {
        Move-Item $BackupSearch $CurrentSearch -ErrorAction SilentlyContinue
    }
    if (Test-Path $BackupFormal) { Copy-Item $BackupFormal $FormalJsonl -Force -ErrorAction SilentlyContinue }
    throw
}

$FinalCount = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() }).Count
$FinalCorpusCount = @(Get-ChildItem (Join-Path $CurrentSearch 'records') -Filter '*.md' -File).Count
if ($FinalCount -ne $ExpectedTotal -or $FinalCorpusCount -ne $ExpectedTotal) {
    throw "POST_CUTOVER_COUNT_MISMATCH records=$FinalCount corpus=$FinalCorpusCount expected=$ExpectedTotal"
}

$Promotion = [ordered]@{
    schemaVersion = 1
    status = 'PASS'
    catalogCommit = $CatalogCommit
    assetCount = $ExpectedAssetCount
    reusableRecordCount = $ExpectedRecordCount
    baseRecordCount = $BaseCount
    totalRecordCount = $ExpectedTotal
    formalKbSha256 = Get-Sha256 $FormalJsonl
    trialMarkerSha256 = Get-Sha256 $TrialMarker
    backupFormal = $BackupFormal
    backupSearch = $BackupSearch
    promotedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$Promotion | ConvertTo-Json -Depth 8 | Set-Content -Path $PromotionMarker -Encoding UTF8

Write-Host "GACE_MODULECATALOG_REUSABLE_FORMAL_PROMOTION=PASS BASE=$BaseCount ADDED=$ExpectedRecordCount TOTAL=$ExpectedTotal"
Write-Host "PINNED_MODULECATALOG_COMMIT=$CatalogCommit"
Write-Host "BACKUP_FORMAL=$BackupFormal"
Write-Host "BACKUP_SEARCH=$BackupSearch"
Write-Host "PROMOTION_MARKER=$PromotionMarker"
