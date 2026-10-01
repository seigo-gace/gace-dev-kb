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
$SafetyPatch = Join-Path $Repo 'scripts\patch-mvs-windows-trial-safety.ps1'
$HistoryProbe = Join-Path $Repo 'tests\mcp_knowledge_client_e2e.py'
$SkillProbe = Join-Path $Repo 'tests\mcp_verified_skill_trial_e2e.py'
$ReusableProbe = Join-Path $Repo 'tests\mcp_reusable_asset_e2e.py'

$AcceptedState = Join-Path $AcceptedRoot 'state.json'
$Projection = Join-Path $AcceptedRoot 'projection'
$NewRecords = Join-Path $Projection 'knowledge-records.jsonl'
$NewMetadata = Join-Path $Projection 'knowledge-metadata.jsonl'
$NewCorpus = Join-Path $Projection 'records'
$DeliveryManifest = Join-Path $AcceptedRoot 'delivery-manifest.json'

$FormalJsonl = Join-Path $Root 'data\knowledge-records\formal-kb.jsonl'
$NextFormal = Join-Path $Root 'data\knowledge-records\formal-kb.reusable-next.jsonl'
$CurrentSearch = Join-Path $Root 'data\knowledge-search'
$CurrentRecords = Join-Path $CurrentSearch 'records'
$StagingSearch = Join-Path $Root 'data\knowledge-search.reusable-staging'
$StagingRecords = Join-Path $StagingSearch 'records'
$AcceptedSources = Join-Path $Root 'data\knowledge-sources\accepted'
$OldSkillRecords = Join-Path $AcceptedSources 'debugai-code-repair-verification-skill-pack\knowledge-records.jsonl'
$CurrentReusableSnapshot = Join-Path $AcceptedSources 'modulecatalog-reusable-current'
$StagingReusableSnapshot = Join-Path $AcceptedSources 'modulecatalog-reusable-staging'
$ActivationMarker = Join-Path $Root 'data\knowledge-records\modulecatalog-reusable-active.json'
$ReusableCorpusPrefix = 'accepted-modulecatalog-reusable-'
$ModuleCatalogRepository = 'seigo-gace/modular-catalog'

foreach ($path in @($Repo,$RuntimePython,$Mvs,$SnapshotBuilder,$SafetyPatch,$HistoryProbe,$ReusableProbe,$AcceptedState,$NewRecords,$NewMetadata,$NewCorpus,$DeliveryManifest,$FormalJsonl,$CurrentSearch,$CurrentRecords)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}

function Get-Sha256 { param([string]$Path) return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash }
function Restore-EnvironmentValue {
    param([string]$Name,[AllowNull()][string]$Value)
    if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue } else { Set-Item "Env:$Name" $Value }
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

$State = Get-Content $AcceptedState -Raw | ConvertFrom-Json
if ([string]$State.status -ne 'ACCEPTED') { throw "ACCEPTED_STATE_INVALID=$($State.status)" }
if ([string]$State.catalogRepository -ne $ModuleCatalogRepository) { throw "ACCEPTED_REPOSITORY_INVALID=$($State.catalogRepository)" }
$CatalogCommit = [string]$State.catalogCommit
$ExpectedAssetCount = [int]$State.assetCount
$ExpectedRecordCount = [int]$State.knowledgeUnitCount
if ($CatalogCommit.Length -ne 40 -or $ExpectedAssetCount -lt 1 -or $ExpectedRecordCount -lt 1) { throw 'ACCEPTED_STATE_CARDINALITY_INVALID' }
if ((Get-Sha256 $NewRecords) -ne [string]$State.knowledgeRecordsSha256) { throw 'ACCEPTED_RECORDS_HASH_MISMATCH' }
if ((Get-Sha256 $NewMetadata) -ne [string]$State.knowledgeMetadataSha256) { throw 'ACCEPTED_METADATA_HASH_MISMATCH' }
$NewCorpusCount = @(Get-ChildItem $NewCorpus -Filter '*.md' -File).Count
if ($NewCorpusCount -ne $ExpectedRecordCount) { throw "ACCEPTED_CORPUS_COUNT_MISMATCH expected=$ExpectedRecordCount actual=$NewCorpusCount" }
Write-Host "GACE_DELIVERY_ACCEPTANCE_AUTHORITY=PASS COMMIT=$CatalogCommit ASSETS=$ExpectedAssetCount RECORDS=$ExpectedRecordCount"

$FormalRows = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
$CurrentFormalCount = $FormalRows.Count
$ExistingReusableCount = @($FormalRows | Where-Object { [string]$_.type -eq 'reusable_asset' -and [string]$_.repository -eq $ModuleCatalogRepository }).Count
$BaseCount = $CurrentFormalCount - $ExistingReusableCount
$CurrentCorpusCount = @(Get-ChildItem $CurrentRecords -Filter '*.md' -File).Count
if ($BaseCount -lt 1) { throw 'BASE_FORMAL_RECORD_COUNT_ZERO' }
if ($CurrentCorpusCount -ne $CurrentFormalCount) { throw "CURRENT_FORMAL_CORPUS_COUNT_MISMATCH records=$CurrentFormalCount corpus=$CurrentCorpusCount" }
$ExpectedTotal = $BaseCount + $ExpectedRecordCount

Write-Host '=== BUILD ACTIVE SNAPSHOT CANDIDATE ==='
Remove-Item $NextFormal -Force -ErrorAction SilentlyContinue
& $RuntimePython -B $SnapshotBuilder --current $FormalJsonl --replacement $NewRecords --output $NextFormal --expected-replacement-count $ExpectedRecordCount
if ($LASTEXITCODE -ne 0) { throw "REUSABLE_SNAPSHOT_BUILD_FAILED=$LASTEXITCODE" }
$NextCount = @(Get-Content $NextFormal | Where-Object { $_.Trim() }).Count
if ($NextCount -ne $ExpectedTotal) { throw "NEXT_FORMAL_COUNT_MISMATCH expected=$ExpectedTotal actual=$NextCount" }

Write-Host '=== BUILD STAGING SEARCH RUNTIME ==='
if (Test-Path $StagingSearch) { Remove-Item $StagingSearch -Recurse -Force }
New-Item -ItemType Directory -Path $StagingSearch -Force | Out-Null
$init = Invoke-MvsCapture -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') -TimeoutSeconds 180
if ($init.ExitCode -ne 0) { throw "STAGING_MVS_INIT_FAILED=$($init.ExitCode)" }
New-Item -ItemType Directory -Path $StagingRecords -Force | Out-Null
$BaseCorpusFiles = @(Get-ChildItem $CurrentRecords -Filter '*.md' -File | Where-Object { -not $_.Name.StartsWith($ReusableCorpusPrefix) })
if ($BaseCorpusFiles.Count -ne $BaseCount) { throw "BASE_CORPUS_COUNT_MISMATCH expected=$BaseCount actual=$($BaseCorpusFiles.Count)" }
foreach ($file in $BaseCorpusFiles) { Copy-Item $file.FullName (Join-Path $StagingRecords $file.Name) -Force }
$prefix = "$ReusableCorpusPrefix$($CatalogCommit.Substring(0,12))-"
foreach ($file in Get-ChildItem $NewCorpus -Filter '*.md' -File) { Copy-Item $file.FullName (Join-Path $StagingRecords ($prefix + $file.Name)) -Force }
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
if (Test-Path $OldSkillRecords) {
    $OldSkillCount = @(Get-Content $OldSkillRecords | Where-Object { $_.Trim() }).Count
    & $RuntimePython -B $SkillProbe --python $RuntimePython --project-root $StagingSearch --records $OldSkillRecords --expected-count $OldSkillCount --timeout 180
    if ($LASTEXITCODE -ne 0) { throw "STAGING_EXISTING_SKILL_MCP_FAILED=$LASTEXITCODE" }
}
& $RuntimePython -B $ReusableProbe --python $RuntimePython --project-root $StagingSearch --metadata $NewMetadata --expected-count $ExpectedRecordCount --timeout 180
if ($LASTEXITCODE -ne 0) { throw "STAGING_REUSABLE_MCP_FAILED=$LASTEXITCODE" }
Write-Host "GACE_STAGING_RUNTIME=PASS TOTAL=$ExpectedTotal REUSABLE=$ExpectedRecordCount"

Write-Host '=== PREPARE STRUCTURED CURRENT SNAPSHOT ==='
if (Test-Path $StagingReusableSnapshot) { Remove-Item $StagingReusableSnapshot -Recurse -Force }
New-Item -ItemType Directory -Path $StagingReusableSnapshot -Force | Out-Null
Copy-Item $NewRecords (Join-Path $StagingReusableSnapshot 'knowledge-records.jsonl') -Force
Copy-Item $NewMetadata (Join-Path $StagingReusableSnapshot 'knowledge-metadata.jsonl') -Force
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
Copy-Item $FormalJsonl $BackupFormal -Force
$hadCurrentReusable = Test-Path $CurrentReusableSnapshot
$searchMoved = $false; $reusableMoved = $false
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
}
catch {
    $failure = $_
    if (Test-Path $CurrentSearch) { Move-Item $CurrentSearch (Join-Path $Root "data\knowledge-search.failed-$timestamp") -ErrorAction SilentlyContinue }
    if ($searchMoved -and (Test-Path $BackupSearch)) { Move-Item $BackupSearch $CurrentSearch -ErrorAction SilentlyContinue }
    if (Test-Path $BackupFormal) { Copy-Item $BackupFormal $FormalJsonl -Force -ErrorAction SilentlyContinue }
    if (Test-Path $CurrentReusableSnapshot) { Remove-Item $CurrentReusableSnapshot -Recurse -Force -ErrorAction SilentlyContinue }
    if ($reusableMoved -and (Test-Path $BackupReusable)) { Move-Item $BackupReusable $CurrentReusableSnapshot -ErrorAction SilentlyContinue }
    throw $failure
}

$Active = [ordered]@{
    schemaVersion = 1; status = 'ACTIVE'; catalogRepository = $ModuleCatalogRepository; catalogCommit = $CatalogCommit
    assetCount = $ExpectedAssetCount; knowledgeUnitCount = $ExpectedRecordCount; totalFormalRecordCount = $ExpectedTotal
    formalKbSha256 = Get-Sha256 $FormalJsonl; knowledgeRecordsSha256 = Get-Sha256 (Join-Path $CurrentReusableSnapshot 'knowledge-records.jsonl')
    knowledgeMetadataSha256 = Get-Sha256 (Join-Path $CurrentReusableSnapshot 'knowledge-metadata.jsonl'); deliveryManifestSha256 = Get-Sha256 $DeliveryManifest
    activatedAtUtc = [DateTime]::UtcNow.ToString('o'); backupFormal = $BackupFormal; backupSearch = $BackupSearch
}
$Active | ConvertTo-Json -Depth 8 | Set-Content -Path $ActivationMarker -Encoding UTF8
$Active | ConvertTo-Json -Depth 8 | Set-Content -Path $ReceiptPath -Encoding UTF8
Write-Host "GACE_MODULECATALOG_RUNTIME_ACTIVATION=PASS COMMIT=$CatalogCommit ASSETS=$ExpectedAssetCount REUSABLE=$ExpectedRecordCount TOTAL=$ExpectedTotal"
Write-Host "GACE_MODULECATALOG_POST_CUTOVER_MCP=PASS"
Write-Host "RECEIPT=$ReceiptPath"
