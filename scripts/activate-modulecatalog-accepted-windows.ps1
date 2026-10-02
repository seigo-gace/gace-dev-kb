param(
    [string]$Root = 'F:\G-ACE-KB',
    [Parameter(Mandatory=$true)][string]$AcceptedRoot,
    [Parameter(Mandatory=$true)][string]$ReceiptPath
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$SnapshotBuilder = Join-Path $Repo 'scripts\replace_modulecatalog_reusable_snapshot.py'
$PreservedCorpusCopier = Join-Path $Repo 'scripts\copy_preserved_kb_runtime_corpus.py'
$RuntimeLinkPrefixer = Join-Path $Repo 'scripts\prefix_modulecatalog_runtime_links.py'
$SafetyPatch = Join-Path $Repo 'scripts\patch-mvs-windows-trial-safety.ps1'
$RecoveryScript = Join-Path $Repo 'scripts\recover-modulecatalog-activation-windows.ps1'
$HistoryProbe = Join-Path $Repo 'tests\mcp_knowledge_client_e2e.py'
$ReusableProbe = Join-Path $Repo 'tests\mcp_reusable_asset_e2e.py'

$AcceptedState = Join-Path $AcceptedRoot 'state.json'
$Projection = Join-Path $AcceptedRoot 'projection'
$NewRecords = Join-Path $Projection 'knowledge-records.jsonl'
$NewMetadata = Join-Path $Projection 'knowledge-metadata.jsonl'
$NewRelationships = Join-Path $Projection 'relationships.jsonl'
$NewCases = Join-Path $Projection 'cases.jsonl'
$NewCorpus = Join-Path $Projection 'records'
$DeliveryManifest = Join-Path $AcceptedRoot 'delivery-manifest.json'

$FormalJsonl = Join-Path $Root 'data\knowledge-records\formal-kb.jsonl'
$NextFormal = Join-Path $Root 'data\knowledge-records\formal-kb.reusable-next.jsonl'
$BaseFormal = Join-Path $Root 'data\knowledge-records\formal-kb.reusable-base-next.jsonl'
$CurrentSearch = Join-Path $Root 'data\knowledge-search'
$CurrentRecords = Join-Path $CurrentSearch 'records'
$StagingSearch = Join-Path $Root 'data\knowledge-search.reusable-staging'
$StagingRecords = Join-Path $StagingSearch 'records'
$AcceptedSources = Join-Path $Root 'data\knowledge-sources\accepted'
$CurrentReusableSnapshot = Join-Path $AcceptedSources 'modulecatalog-reusable-current'
$StagingReusableSnapshot = Join-Path $AcceptedSources 'modulecatalog-reusable-staging'
$ActivationMarker = Join-Path $Root 'data\knowledge-records\modulecatalog-reusable-active.json'
$ActivationJournal = Join-Path $Root 'data\knowledge-intake\modulecatalog\activation-transaction.json'
$ReusableCorpusPrefix = 'accepted-modulecatalog-reusable-'
$ModuleCatalogRepository = 'seigo-gace/modular-catalog'

foreach ($path in @($Repo,$RuntimePython,$Mvs,$SnapshotBuilder,$PreservedCorpusCopier,$RuntimeLinkPrefixer,$SafetyPatch,$RecoveryScript,$HistoryProbe,$ReusableProbe,$AcceptedState,$NewRecords,$NewMetadata,$NewRelationships,$NewCases,$NewCorpus,$DeliveryManifest,$FormalJsonl,$CurrentSearch,$CurrentRecords)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}

function Get-Sha256 { param([string]$Path) return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash }
function Restore-EnvironmentValue {
    param([string]$Name,[AllowNull()][string]$Value)
    if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue } else { Set-Item "Env:$Name" $Value }
}
function Write-JsonAtomic {
    param([object]$Value,[string]$Path)
    $directory = Split-Path $Path
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $tag = "$PID.$([Guid]::NewGuid().ToString('N'))"
    $temp = "$Path.tmp.$tag"
    $backup = "$Path.replace-backup.$tag"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    try {
        $json = $Value | ConvertTo-Json -Depth 16
        [System.IO.File]::WriteAllText($temp, $json + [Environment]::NewLine, $encoding)
        if (Test-Path -LiteralPath $Path) {
            [System.IO.File]::Replace($temp, $Path, $backup)
        }
        else {
            [System.IO.File]::Move($temp, $Path)
        }
    }
    finally {
        Remove-Item $temp,$backup -Force -ErrorAction SilentlyContinue
    }
}
function Invoke-MvsCapture {
    param([string[]]$Arguments,[int]$TimeoutSeconds = 2400,[string]$WorkingDirectory = $StagingSearch)
    $tag = [Guid]::NewGuid().ToString('N')
    $stdout = Join-Path $env:TEMP "gace-activate-$tag.stdout.log"
    $stderr = Join-Path $env:TEMP "gace-activate-$tag.stderr.log"
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
        $process.WaitForExit(); $process.Refresh()
        [string]$out = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { '' }
        [string]$err = if (Test-Path $stderr) { Get-Content $stderr -Raw } else { '' }
        [string]$all = ($out + [Environment]::NewLine + $err).Trim()
        if ($all) { Write-Host $all }
        return [pscustomobject]@{ ExitCode=[int]$process.ExitCode; Output=$all }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}
function Assert-IndexHealthy {
    param([string]$Output,[string]$Stage)
    if ($Output -notmatch 'Reindex complete:') { throw "${Stage}_INDEX_COMPLETION_MARKER_MISSING" }
    if ($Output -match 'BM25 index building failed') { throw "${Stage}_BM25_BUILD_WARNING_PRESENT" }
    if ($Output -match 'Hybrid search will fall back to vector-only mode') { throw "${Stage}_VECTOR_ONLY_FALLBACK_PRESENT" }
    if ($Output -match 'cannot find context for ''fork''') { throw "${Stage}_WINDOWS_FORK_CONTEXT_ERROR_PRESENT" }
}

# A hard process/PC interruption may leave a prepared cutover journal. Resolve it
# before reading current counts or constructing a new staging runtime.
if (Test-Path $ActivationJournal) {
    Write-Host '=== RECOVER INTERRUPTED ACTIVATION ==='
    & $RecoveryScript -Root $Root -JournalPath $ActivationJournal
}

$State = Get-Content $AcceptedState -Raw | ConvertFrom-Json
if ([string]$State.status -ne 'ACCEPTED') { throw "ACCEPTED_STATE_INVALID=$($State.status)" }
if ([string]$State.catalogRepository -ne $ModuleCatalogRepository) { throw "ACCEPTED_REPOSITORY_INVALID=$($State.catalogRepository)" }
if ([int]$State.projectionSchemaVersion -ne 2) { throw "ACCEPTED_PROJECTION_SCHEMA_UNSUPPORTED=$($State.projectionSchemaVersion)" }
$CatalogCommit = [string]$State.catalogCommit
$ExpectedAssetCount = [int]$State.assetCount
$ExpectedRecordCount = [int]$State.knowledgeUnitCount
$ExpectedRelationshipCount = [int]$State.relationshipCount
$ExpectedCaseCount = [int]$State.caseCount
if ($CatalogCommit.Length -ne 40 -or $ExpectedAssetCount -lt 1 -or $ExpectedRecordCount -lt 1 -or $ExpectedRelationshipCount -lt 0 -or $ExpectedCaseCount -lt 0) { throw 'ACCEPTED_STATE_CARDINALITY_INVALID' }
if ((Get-Sha256 $NewRecords) -ne [string]$State.knowledgeRecordsSha256) { throw 'ACCEPTED_RECORDS_HASH_MISMATCH' }
if ((Get-Sha256 $NewMetadata) -ne [string]$State.knowledgeMetadataSha256) { throw 'ACCEPTED_METADATA_HASH_MISMATCH' }
if ((Get-Sha256 $NewRelationships) -ne [string]$State.relationshipsSha256) { throw 'ACCEPTED_RELATIONSHIPS_HASH_MISMATCH' }
if ((Get-Sha256 $NewCases) -ne [string]$State.casesSha256) { throw 'ACCEPTED_CASES_HASH_MISMATCH' }
$NewRelationshipCount = @(Get-Content $NewRelationships | Where-Object { $_.Trim() }).Count
$NewCaseCount = @(Get-Content $NewCases | Where-Object { $_.Trim() }).Count
if ($NewRelationshipCount -ne $ExpectedRelationshipCount) { throw "ACCEPTED_RELATIONSHIP_COUNT_MISMATCH expected=$ExpectedRelationshipCount actual=$NewRelationshipCount" }
if ($NewCaseCount -ne $ExpectedCaseCount) { throw "ACCEPTED_CASE_COUNT_MISMATCH expected=$ExpectedCaseCount actual=$NewCaseCount" }
$NewCorpusCount = @(Get-ChildItem $NewCorpus -Filter '*.md' -File).Count
if ($NewCorpusCount -ne $ExpectedRecordCount) { throw "ACCEPTED_CORPUS_COUNT_MISMATCH expected=$ExpectedRecordCount actual=$NewCorpusCount" }
Write-Host "GACE_DELIVERY_ACCEPTANCE_AUTHORITY=PASS COMMIT=$CatalogCommit ASSETS=$ExpectedAssetCount RECORDS=$ExpectedRecordCount RELATIONSHIPS=$ExpectedRelationshipCount CASES=$ExpectedCaseCount"

$FormalRows = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
$CurrentFormalCount = $FormalRows.Count
$CurrentCorpusCount = @(Get-ChildItem $CurrentRecords -Filter '*.md' -File).Count
if ($CurrentFormalCount -lt 1) { throw 'CURRENT_FORMAL_RECORD_COUNT_ZERO' }
if ($CurrentCorpusCount -ne $CurrentFormalCount) { throw "CURRENT_FORMAL_CORPUS_COUNT_MISMATCH records=$CurrentFormalCount corpus=$CurrentCorpusCount" }

Write-Host '=== BUILD ACTIVE SNAPSHOT CANDIDATE ==='
Remove-Item $NextFormal,$BaseFormal -Force -ErrorAction SilentlyContinue
& $RuntimePython -B $SnapshotBuilder `
    --current $FormalJsonl `
    --replacement $NewRecords `
    --output $NextFormal `
    --base-output $BaseFormal `
    --expected-replacement-count $ExpectedRecordCount
if ($LASTEXITCODE -ne 0) { throw "REUSABLE_SNAPSHOT_BUILD_FAILED=$LASTEXITCODE" }
$BaseCount = @(Get-Content $BaseFormal | Where-Object { $_.Trim() }).Count
if ($BaseCount -lt 1) { throw 'BASE_FORMAL_RECORD_COUNT_ZERO' }
$ExpectedTotal = $BaseCount + $ExpectedRecordCount
$NextCount = @(Get-Content $NextFormal | Where-Object { $_.Trim() }).Count
if ($NextCount -ne $ExpectedTotal) { throw "NEXT_FORMAL_COUNT_MISMATCH expected=$ExpectedTotal actual=$NextCount" }
Write-Host "GACE_MODULECATALOG_BASE_REBUILD=PASS CURRENT=$CurrentFormalCount BASE=$BaseCount REPLACEMENT=$ExpectedRecordCount TOTAL=$ExpectedTotal"

Write-Host '=== BUILD STAGING SEARCH RUNTIME ==='
if (Test-Path $StagingSearch) { Remove-Item $StagingSearch -Recurse -Force }
New-Item -ItemType Directory -Path $StagingSearch -Force | Out-Null
$init = Invoke-MvsCapture -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') -TimeoutSeconds 180
if ($init.ExitCode -ne 0) { throw "STAGING_MVS_INIT_FAILED=$($init.ExitCode)" }

# Preserve every non-ModuleCatalog current corpus document byte-for-byte. This
# avoids flattening any future rich accepted Knowledge that is not part of the
# replaceable Catalog snapshot into the legacy eight-field renderer.
& $RuntimePython -B $PreservedCorpusCopier --current $CurrentRecords --output $StagingRecords --expected-count $BaseCount
if ($LASTEXITCODE -ne 0) { throw "PRESERVED_BASE_CORPUS_COPY_FAILED=$LASTEXITCODE" }
$PreservedBaseCount = @(Get-ChildItem $StagingRecords -Filter '*.md' -File).Count
if ($PreservedBaseCount -ne $BaseCount) { throw "BASE_CORPUS_COUNT_MISMATCH expected=$BaseCount actual=$PreservedBaseCount" }
Remove-Item $BaseFormal -Force -ErrorAction SilentlyContinue

$prefix = "$ReusableCorpusPrefix$($CatalogCommit.Substring(0,12))-"
$StagingReusableCorpus = Join-Path $StagingSearch 'modulecatalog-runtime-source'
if (Test-Path $StagingReusableCorpus) { Remove-Item $StagingReusableCorpus -Recurse -Force }
New-Item -ItemType Directory -Path $StagingReusableCorpus -Force | Out-Null
Copy-Item (Join-Path $NewCorpus '*.md') $StagingReusableCorpus -Force
& $RuntimePython -B $RuntimeLinkPrefixer --corpus $StagingReusableCorpus --prefix $prefix
if ($LASTEXITCODE -ne 0) { throw "RUNTIME_LINK_PREFIX_FAILED=$LASTEXITCODE" }
foreach ($file in Get-ChildItem $StagingReusableCorpus -Filter '*.md' -File) {
    Copy-Item $file.FullName (Join-Path $StagingRecords ($prefix + $file.Name)) -Force
}
Remove-Item $StagingReusableCorpus -Recurse -Force

$StagingCorpusCount = @(Get-ChildItem $StagingRecords -Filter '*.md' -File).Count
if ($StagingCorpusCount -ne $ExpectedTotal) { throw "STAGING_CORPUS_COUNT_MISMATCH expected=$ExpectedTotal actual=$StagingCorpusCount" }

& $SafetyPatch -Root $Root
$names = @('MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING','MCP_VECTOR_SEARCH_WORKERS','MCP_VECTOR_SEARCH_MAX_WORKERS','MCP_VECTOR_SEARCH_BATCH_SIZE','MCP_VECTOR_SEARCH_FILE_BATCH_SIZE','OMP_NUM_THREADS','MKL_NUM_THREADS','OPENBLAS_NUM_THREADS','NUMEXPR_NUM_THREADS','TOKENIZERS_PARALLELISM')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    $env:MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING='1'; $env:MCP_VECTOR_SEARCH_WORKERS='1'; $env:MCP_VECTOR_SEARCH_MAX_WORKERS='1'
    $env:MCP_VECTOR_SEARCH_BATCH_SIZE='8'; $env:MCP_VECTOR_SEARCH_FILE_BATCH_SIZE='16'
    $env:OMP_NUM_THREADS='1'; $env:MKL_NUM_THREADS='1'; $env:OPENBLAS_NUM_THREADS='1'; $env:NUMEXPR_NUM_THREADS='1'; $env:TOKENIZERS_PARALLELISM='false'
    $index = Invoke-MvsCapture -Arguments @('index','--force')
    if ($index.ExitCode -ne 0) { throw "STAGING_MVS_INDEX_FAILED=$($index.ExitCode)" }
    Assert-IndexHealthy -Output $index.Output -Stage 'STAGING'
    $status = Invoke-MvsCapture -Arguments @('status') -TimeoutSeconds 180
    if ($status.ExitCode -ne 0) { throw "STAGING_MVS_STATUS_FAILED=$($status.ExitCode)" }
    if ($status.Output -notmatch "Indexed Files:\s+$ExpectedTotal/$ExpectedTotal") { throw "STAGING_INDEX_COUNT_MISMATCH expected=$ExpectedTotal" }
}
finally { foreach ($name in $names) { Restore-EnvironmentValue -Name $name -Value $previous[$name] } }

Write-Host '=== STAGING MCP OPERATIONAL GATES ==='
& $RuntimePython -B $HistoryProbe --python $RuntimePython --project-root $StagingSearch --timeout 180
if ($LASTEXITCODE -ne 0) { throw "STAGING_HISTORY_MCP_FAILED=$LASTEXITCODE" }
& $RuntimePython -B $ReusableProbe --python $RuntimePython --project-root $StagingSearch --metadata $NewMetadata --expected-count $ExpectedRecordCount --timeout 180
if ($LASTEXITCODE -ne 0) { throw "STAGING_REUSABLE_MCP_FAILED=$LASTEXITCODE" }
Write-Host "GACE_STAGING_RUNTIME=PASS TOTAL=$ExpectedTotal REUSABLE=$ExpectedRecordCount LEGACY_MODULECATALOG_ASSETS=RETIRED PRESERVED_BASE=BYTE_EXACT"

Write-Host '=== PREPARE STRUCTURED CURRENT SNAPSHOT ==='
if (Test-Path $StagingReusableSnapshot) { Remove-Item $StagingReusableSnapshot -Recurse -Force }
New-Item -ItemType Directory -Path $StagingReusableSnapshot -Force | Out-Null
Copy-Item $NewRecords (Join-Path $StagingReusableSnapshot 'knowledge-records.jsonl') -Force
Copy-Item $NewMetadata (Join-Path $StagingReusableSnapshot 'knowledge-metadata.jsonl') -Force
Copy-Item $NewRelationships (Join-Path $StagingReusableSnapshot 'relationships.jsonl') -Force
Copy-Item $NewCases (Join-Path $StagingReusableSnapshot 'cases.jsonl') -Force
Copy-Item $DeliveryManifest (Join-Path $StagingReusableSnapshot 'delivery-manifest.json') -Force
Copy-Item $AcceptedState (Join-Path $StagingReusableSnapshot 'acceptance-state.json') -Force
$SnapshotCorpus = Join-Path $StagingReusableSnapshot 'records'
New-Item -ItemType Directory -Path $SnapshotCorpus -Force | Out-Null
Copy-Item (Join-Path $NewCorpus '*.md') $SnapshotCorpus -Force

Write-Host '=== VERIFIED CUTOVER + POST-CUTOVER MCP ==='
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$BackupSearch = Join-Path $Root "data\knowledge-search.previous-$timestamp"
$BackupFormal = Join-Path $Root "data\knowledge-records\formal-kb.previous-$timestamp.jsonl"
$BackupReusable = Join-Path $AcceptedSources "modulecatalog-reusable.previous-$timestamp"
$BackupActivationMarker = "$ActivationMarker.rollback-$timestamp"
$BackupReceipt = "$ReceiptPath.rollback-$timestamp"
$HadActivationMarker = Test-Path $ActivationMarker
Copy-Item $FormalJsonl $BackupFormal -Force
Copy-Item $ReceiptPath $BackupReceipt -Force
if ($HadActivationMarker) { Copy-Item $ActivationMarker $BackupActivationMarker -Force }
$hadCurrentReusable = Test-Path $CurrentReusableSnapshot
$searchMoved = $false; $reusableMoved = $false

$Journal = [ordered]@{
    schemaVersion = 1
    status = 'PREPARED'
    targetCommit = $CatalogCommit
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    currentSearch = $CurrentSearch
    backupSearch = $BackupSearch
    formalJsonl = $FormalJsonl
    backupFormal = $BackupFormal
    currentReusable = $CurrentReusableSnapshot
    backupReusable = $BackupReusable
    activationMarker = $ActivationMarker
    backupActivationMarker = $BackupActivationMarker
    receiptPath = $ReceiptPath
    backupReceipt = $BackupReceipt
    stagingSearch = $StagingSearch
    stagingReusable = $StagingReusableSnapshot
    nextFormal = $NextFormal
    hadCurrentReusable = $hadCurrentReusable
    hadActivationMarker = $HadActivationMarker
}
Write-JsonAtomic -Value $Journal -Path $ActivationJournal

try {
    Move-Item $CurrentSearch $BackupSearch; $searchMoved = $true
    Move-Item $StagingSearch $CurrentSearch
    Move-Item $NextFormal $FormalJsonl -Force
    if ($hadCurrentReusable) { Move-Item $CurrentReusableSnapshot $BackupReusable; $reusableMoved = $true }
    Move-Item $StagingReusableSnapshot $CurrentReusableSnapshot

    $FinalCount = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() }).Count
    $FinalCorpusCount = @(Get-ChildItem (Join-Path $CurrentSearch 'records') -Filter '*.md' -File).Count
    if ($FinalCount -ne $ExpectedTotal -or $FinalCorpusCount -ne $ExpectedTotal) { throw "POST_CUTOVER_COUNT_MISMATCH records=$FinalCount corpus=$FinalCorpusCount expected=$ExpectedTotal" }

    & $RuntimePython -B $HistoryProbe --python $RuntimePython --project-root $CurrentSearch --timeout 180
    if ($LASTEXITCODE -ne 0) { throw "POST_CUTOVER_HISTORY_MCP_FAILED=$LASTEXITCODE" }
    & $RuntimePython -B $ReusableProbe --python $RuntimePython --project-root $CurrentSearch --metadata (Join-Path $CurrentReusableSnapshot 'knowledge-metadata.jsonl') --expected-count $ExpectedRecordCount --timeout 180
    if ($LASTEXITCODE -ne 0) { throw "POST_CUTOVER_REUSABLE_MCP_FAILED=$LASTEXITCODE" }

    $ActiveRelationships = Join-Path $CurrentReusableSnapshot 'relationships.jsonl'
    $ActiveCases = Join-Path $CurrentReusableSnapshot 'cases.jsonl'
    if (-not (Test-Path $ActiveRelationships) -or -not (Test-Path $ActiveCases)) { throw 'POST_CUTOVER_STRUCTURED_SIDECAR_MISSING' }
    $ActiveRelationshipCount = @(Get-Content $ActiveRelationships | Where-Object { $_.Trim() }).Count
    $ActiveCaseCount = @(Get-Content $ActiveCases | Where-Object { $_.Trim() }).Count
    if ($ActiveRelationshipCount -ne $ExpectedRelationshipCount) { throw "POST_CUTOVER_RELATIONSHIP_COUNT_MISMATCH expected=$ExpectedRelationshipCount actual=$ActiveRelationshipCount" }
    if ($ActiveCaseCount -ne $ExpectedCaseCount) { throw "POST_CUTOVER_CASE_COUNT_MISMATCH expected=$ExpectedCaseCount actual=$ActiveCaseCount" }

    $Active = [ordered]@{
        schemaVersion = 1
        projectionSchemaVersion = 2
        status = 'ACTIVE'
        catalogRepository = $ModuleCatalogRepository
        catalogCommit = $CatalogCommit
        assetCount = $ExpectedAssetCount
        knowledgeUnitCount = $ExpectedRecordCount
        relationshipCount = $ExpectedRelationshipCount
        caseCount = $ExpectedCaseCount
        corpusCount = $NewCorpusCount
        totalFormalRecordCount = $ExpectedTotal
        formalKbSha256 = Get-Sha256 $FormalJsonl
        knowledgeRecordsSha256 = Get-Sha256 (Join-Path $CurrentReusableSnapshot 'knowledge-records.jsonl')
        knowledgeMetadataSha256 = Get-Sha256 (Join-Path $CurrentReusableSnapshot 'knowledge-metadata.jsonl')
        relationshipsSha256 = Get-Sha256 $ActiveRelationships
        casesSha256 = Get-Sha256 $ActiveCases
        deliveryManifestSha256 = Get-Sha256 $DeliveryManifest
        acceptedRoot = $AcceptedRoot
        activatedAtUtc = [DateTime]::UtcNow.ToString('o')
        backupFormal = $BackupFormal
        backupSearch = $BackupSearch
    }
    Write-JsonAtomic -Value $Active -Path (Join-Path $CurrentReusableSnapshot 'runtime-state.json')
    Write-JsonAtomic -Value $Active -Path $ActivationMarker
    Write-JsonAtomic -Value $Active -Path $ReceiptPath

    $ReceiptCheck = Get-Content $ReceiptPath -Raw | ConvertFrom-Json
    $MarkerCheck = Get-Content $ActivationMarker -Raw | ConvertFrom-Json
    if ([string]$ReceiptCheck.status -ne 'ACTIVE' -or [string]$ReceiptCheck.catalogCommit -ne $CatalogCommit) { throw 'ACTIVE_RECEIPT_WRITE_VERIFY_FAILED' }
    if ([string]$MarkerCheck.status -ne 'ACTIVE' -or [string]$MarkerCheck.catalogCommit -ne $CatalogCommit) { throw 'ACTIVE_MARKER_WRITE_VERIFY_FAILED' }
    foreach ($name in @('knowledgeRecordsSha256','knowledgeMetadataSha256','relationshipsSha256','casesSha256','deliveryManifestSha256')) {
        if ([string]$ReceiptCheck.$name -ne [string]$Active.$name -or [string]$MarkerCheck.$name -ne [string]$Active.$name) {
            throw "ACTIVE_AUTHORITY_HASH_VERIFY_FAILED=$name"
        }
    }
}
catch {
    $failure = $_
    if (Test-Path $CurrentSearch) { Move-Item $CurrentSearch (Join-Path $Root "data\knowledge-search.failed-$timestamp") -ErrorAction SilentlyContinue }
    if ($searchMoved -and (Test-Path $BackupSearch)) { Move-Item $BackupSearch $CurrentSearch -ErrorAction SilentlyContinue }
    if (Test-Path $BackupFormal) { Copy-Item $BackupFormal $FormalJsonl -Force -ErrorAction SilentlyContinue }
    if (Test-Path $CurrentReusableSnapshot) { Remove-Item $CurrentReusableSnapshot -Recurse -Force -ErrorAction SilentlyContinue }
    if ($reusableMoved -and (Test-Path $BackupReusable)) { Move-Item $BackupReusable $CurrentReusableSnapshot -ErrorAction SilentlyContinue }
    if ($HadActivationMarker -and (Test-Path $BackupActivationMarker)) {
        Copy-Item $BackupActivationMarker $ActivationMarker -Force -ErrorAction SilentlyContinue
    }
    elseif (-not $HadActivationMarker) {
        Remove-Item $ActivationMarker -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $BackupReceipt) { Copy-Item $BackupReceipt $ReceiptPath -Force -ErrorAction SilentlyContinue }
    Remove-Item $BackupActivationMarker,$BackupReceipt -Force -ErrorAction SilentlyContinue
    Remove-Item $ActivationJournal -Force -ErrorAction SilentlyContinue
    throw $failure
}

Remove-Item $BackupActivationMarker,$BackupReceipt,$BaseFormal -Force -ErrorAction SilentlyContinue
Remove-Item $ActivationJournal -Force -ErrorAction SilentlyContinue
Write-Host "GACE_MODULECATALOG_RUNTIME_ACTIVATION=PASS COMMIT=$CatalogCommit ASSETS=$ExpectedAssetCount REUSABLE=$ExpectedRecordCount RELATIONSHIPS=$ExpectedRelationshipCount CASES=$ExpectedCaseCount TOTAL=$ExpectedTotal"
Write-Host "GACE_MODULECATALOG_POST_CUTOVER_MCP=PASS"
Write-Host "RECEIPT=$ReceiptPath"
