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
$SnapshotBuilder = Join-Path $Repo 'scripts\replace_modulecatalog_reusable_snapshot.py'
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
$AcceptedRoot = Join-Path $Root 'data\knowledge-sources\accepted'
$OldSkillRecords = Join-Path $AcceptedRoot 'debugai-code-repair-verification-skill-pack\knowledge-records.jsonl'
$CurrentReusableSnapshot = Join-Path $AcceptedRoot 'modulecatalog-reusable-current'
$StagingReusableSnapshot = Join-Path $AcceptedRoot 'modulecatalog-reusable-staging'
$PromotionMarker = Join-Path $Root 'data\knowledge-records\modulecatalog-reusable-promotion-pass.json'
$ReusableCorpusPrefix = 'accepted-modulecatalog-reusable-'
$ModuleCatalogRepository = 'seigo-gace/modular-catalog'

foreach ($path in @($Repo,$RuntimePython,$Mvs,$SnapshotBuilder,$SafetyPatch,$HistoryProbe,$SkillProbe,$ReusableProbe,$TrialMarker,$TrialExportManifest,$NewRecords,$NewMetadata,$NewCorpus,$FormalJsonl,$CurrentSearch,$CurrentRecords)) {
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

$FormalRows = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
$CurrentFormalCount = $FormalRows.Count
$ExistingReusableCount = @($FormalRows | Where-Object { [string]$_.type -eq 'reusable_asset' -and [string]$_.repository -eq $ModuleCatalogRepository }).Count
$BaseCount = $CurrentFormalCount - $ExistingReusableCount
$CurrentCorpusCount = @(Get-ChildItem $CurrentRecords -Filter '*.md' -File).Count
if ($BaseCount -lt 1) { throw 'BASE_FORMAL_RECORD_COUNT_ZERO' }
if ($CurrentCorpusCount -ne $CurrentFormalCount) { throw "CURRENT_FORMAL_CORPUS_COUNT_MISMATCH records=$CurrentFormalCount corpus=$CurrentCorpusCount" }
$ExpectedTotal = $BaseCount + $ExpectedRecordCount
Write-Host "BASE_FORMAL_KB=PASS TOTAL=$CurrentFormalCount ACTIVE_REUSABLE=$ExistingReusableCount BASE=$BaseCount EXPECTED_TOTAL=$ExpectedTotal"

Write-Host '=== BUILD REPLACEABLE NEXT FORMAL RECORD SET ==='
Remove-Item $NextFormal -Force -ErrorAction SilentlyContinue
& $RuntimePython -B $SnapshotBuilder --current $FormalJsonl --replacement $NewRecords --output $NextFormal --expected-replacement-count $ExpectedRecordCount
if ($LASTEXITCODE -ne 0) { throw "FORMAL_REUSABLE_SNAPSHOT_BUILD_FAILED=$LASTEXITCODE" }
$NextCount = @(Get-Content $NextFormal | Where-Object { $_.Trim() }).Count
if ($NextCount -ne $ExpectedTotal) { throw "FORMAL_REUSABLE_COUNT_MISMATCH expected=$ExpectedTotal actual=$NextCount" }
Write-Host "NEXT_FORMAL_RECORDS=PASS RECORDS=$NextCount REPLACED=$ExistingReusableCount ADDED=$ExpectedRecordCount"

Write-Host '=== BUILD STAGING SEARCH CORPUS ==='
if (Test-Path $StagingSearch) { Remove-Item $StagingSearch -Recurse -Force }
New-Item -ItemType Directory -Path $StagingSearch -Force | Out-Null
$init = Invoke-MvsCapture -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') -TimeoutSeconds 180
if ($init.ExitCode -ne 0) { throw "STAGING_MVS_INIT_FAILED=$($init.ExitCode)" }
New-Item -ItemType Directory -Path $StagingRecords -Force | Out-Null

$BaseCorpusFiles = @(Get-ChildItem $CurrentRecords -Filter '*.md' -File | Where-Object { -not $_.Name.StartsWith($ReusableCorpusPrefix) })
foreach ($file in $BaseCorpusFiles) { Copy-Item $file.FullName (Join-Path $StagingRecords $file.Name) -Force }
if ($BaseCorpusFiles.Count -ne $BaseCount) { throw "BASE_CORPUS_AFTER_REUSABLE_REMOVAL_MISMATCH expected=$BaseCount actual=$($BaseCorpusFiles.Count)" }

$prefix = "$ReusableCorpusPrefix$($CatalogCommit.Substring(0,12))-"
foreach ($file in Get-ChildItem $NewCorpus -Filter '*.md' -File) {
    Copy-Item $file.FullName (Join-Path $StagingRecords ($prefix + $file.Name)) -Force
}
$StagingCorpusCount = @(Get-ChildItem $StagingRecords -Filter '*.md' -File).Count
if ($StagingCorpusCount -ne $ExpectedTotal) { throw "STAGING_CORPUS_COUNT_MISMATCH expected=$ExpectedTotal actual=$StagingCorpusCount" }
Write-Host "STAGING_CORPUS=PASS BASE=$BaseCount REUSABLE=$ExpectedRecordCount TOTAL=$StagingCorpusCount"

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

Write-Host '=== PREPARE CURRENT REUSABLE STRUCTURED SNAPSHOT ==='
if (Test-Path $StagingReusableSnapshot) { Remove-Item $StagingReusableSnapshot -Recurse -Force }
New-Item -ItemType Directory -Path $StagingReusableSnapshot -Force | Out-Null
Copy-Item $NewRecords (Join-Path $StagingReusableSnapshot 'knowledge-records.jsonl') -Force
Copy-Item $NewMetadata (Join-Path $StagingReusableSnapshot 'knowledge-metadata.jsonl') -Force
Copy-Item $TrialExportManifest (Join-Path $StagingReusableSnapshot 'export-manifest.json') -Force
Copy-Item $TrialMarker (Join-Path $StagingReusableSnapshot 'trial-pass.json') -Force
$SnapshotCorpus = Join-Path $StagingReusableSnapshot 'records'
New-Item -ItemType Directory -Path $SnapshotCorpus -Force | Out-Null
Copy-Item (Join-Path $NewCorpus '*.md') $SnapshotCorpus -Force
$SnapshotState = [ordered]@{
    schemaVersion = 1
    status = 'STAGED'
    catalogRepository = $ModuleCatalogRepository
    catalogCommit = $CatalogCommit
    assetCount = $ExpectedAssetCount
    recordCount = $ExpectedRecordCount
    knowledgeRecordsSha256 = Get-Sha256 $NewRecords
    knowledgeMetadataSha256 = Get-Sha256 $NewMetadata
    exportManifestSha256 = Get-Sha256 $TrialExportManifest
    stagedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$SnapshotState | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $StagingReusableSnapshot 'state.json') -Encoding UTF8
Write-Host "REUSABLE_STRUCTURED_SNAPSHOT=STAGED RECORDS=$ExpectedRecordCount"

Write-Host '=== VERIFIED CUTOVER ==='
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$BackupSearch = Join-Path $Root "data\knowledge-search.previous-$timestamp"
$BackupFormal = Join-Path $Root "data\knowledge-records\formal-kb.previous-$timestamp.jsonl"
$BackupReusableSnapshot = Join-Path $AcceptedRoot "modulecatalog-reusable.previous-$timestamp"
Copy-Item $FormalJsonl $BackupFormal -Force
$SearchMoved = $false
$SnapshotMoved = $false
try {
    Move-Item $CurrentSearch $BackupSearch
    $SearchMoved = $true
    Move-Item $StagingSearch $CurrentSearch
    Move-Item $NextFormal $FormalJsonl -Force

    if (Test-Path $CurrentReusableSnapshot) {
        Move-Item $CurrentReusableSnapshot $BackupReusableSnapshot
        $SnapshotMoved = $true
    }
    Move-Item $StagingReusableSnapshot $CurrentReusableSnapshot
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

    if (Test-Path $CurrentReusableSnapshot) {
        $FailedSnapshot = Join-Path $AcceptedRoot "modulecatalog-reusable.failed-cutover-$timestamp"
        Move-Item $CurrentReusableSnapshot $FailedSnapshot -ErrorAction SilentlyContinue
    }
    if ($SnapshotMoved -and (Test-Path $BackupReusableSnapshot) -and -not (Test-Path $CurrentReusableSnapshot)) {
        Move-Item $BackupReusableSnapshot $CurrentReusableSnapshot -ErrorAction SilentlyContinue
    }
    throw
}

$FinalCount = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() }).Count
$FinalCorpusCount = @(Get-ChildItem (Join-Path $CurrentSearch 'records') -Filter '*.md' -File).Count
$CurrentMetadata = Join-Path $CurrentReusableSnapshot 'knowledge-metadata.jsonl'
$CurrentStructuredRecords = Join-Path $CurrentReusableSnapshot 'knowledge-records.jsonl'
if (-not (Test-Path $CurrentMetadata) -or -not (Test-Path $CurrentStructuredRecords)) { throw 'CURRENT_REUSABLE_STRUCTURED_SNAPSHOT_MISSING' }
$FinalMetadataCount = @(Get-Content $CurrentMetadata | Where-Object { $_.Trim() }).Count
$FinalStructuredCount = @(Get-Content $CurrentStructuredRecords | Where-Object { $_.Trim() }).Count
if ($FinalCount -ne $ExpectedTotal -or $FinalCorpusCount -ne $ExpectedTotal) {
    throw "POST_CUTOVER_COUNT_MISMATCH records=$FinalCount corpus=$FinalCorpusCount expected=$ExpectedTotal"
}
if ($FinalMetadataCount -ne $ExpectedRecordCount -or $FinalStructuredCount -ne $ExpectedRecordCount) {
    throw "POST_CUTOVER_REUSABLE_SNAPSHOT_COUNT_MISMATCH metadata=$FinalMetadataCount records=$FinalStructuredCount expected=$ExpectedRecordCount"
}

$CurrentStatePath = Join-Path $CurrentReusableSnapshot 'state.json'
$CurrentState = Get-Content $CurrentStatePath -Raw | ConvertFrom-Json
$CurrentState.status = 'ACTIVE'
$CurrentState | ConvertTo-Json -Depth 8 | Set-Content -Path $CurrentStatePath -Encoding UTF8

$Promotion = [ordered]@{
    schemaVersion = 1
    status = 'PASS'
    catalogCommit = $CatalogCommit
    assetCount = $ExpectedAssetCount
    reusableRecordCount = $ExpectedRecordCount
    replacedReusableRecordCount = $ExistingReusableCount
    baseRecordCount = $BaseCount
    totalRecordCount = $ExpectedTotal
    formalKbSha256 = Get-Sha256 $FormalJsonl
    reusableMetadataSha256 = Get-Sha256 $CurrentMetadata
    reusableRecordsSha256 = Get-Sha256 $CurrentStructuredRecords
    trialMarkerSha256 = Get-Sha256 $TrialMarker
    currentReusableSnapshot = $CurrentReusableSnapshot
    backupFormal = $BackupFormal
    backupSearch = $BackupSearch
    backupReusableSnapshot = if ($SnapshotMoved) { $BackupReusableSnapshot } else { $null }
    promotedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$Promotion | ConvertTo-Json -Depth 8 | Set-Content -Path $PromotionMarker -Encoding UTF8

Write-Host "GACE_MODULECATALOG_REUSABLE_FORMAL_PROMOTION=PASS BASE=$BaseCount REPLACED=$ExistingReusableCount ADDED=$ExpectedRecordCount TOTAL=$ExpectedTotal"
Write-Host "PINNED_MODULECATALOG_COMMIT=$CatalogCommit"
Write-Host "CURRENT_REUSABLE_SNAPSHOT=$CurrentReusableSnapshot"
Write-Host "BACKUP_FORMAL=$BackupFormal"
Write-Host "BACKUP_SEARCH=$BackupSearch"
Write-Host "PROMOTION_MARKER=$PromotionMarker"
