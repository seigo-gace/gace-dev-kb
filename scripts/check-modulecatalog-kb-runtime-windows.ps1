param(
    [string]$Root = 'F:\G-ACE-KB',
    [switch]$Deep
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$CurrentSearch = Join-Path $Root 'data\knowledge-search'
$CurrentRecords = Join-Path $CurrentSearch 'records'
$FormalJsonl = Join-Path $Root 'data\knowledge-records\formal-kb.jsonl'
$ActivationMarker = Join-Path $Root 'data\knowledge-records\modulecatalog-reusable-active.json'
$ActivationJournal = Join-Path $Root 'data\knowledge-intake\modulecatalog\activation-transaction.json'
$CurrentReusable = Join-Path $Root 'data\knowledge-sources\accepted\modulecatalog-reusable-current'
$ReusableRecords = Join-Path $CurrentReusable 'knowledge-records.jsonl'
$ReusableMetadata = Join-Path $CurrentReusable 'knowledge-metadata.jsonl'
$ReusableRelationships = Join-Path $CurrentReusable 'relationships.jsonl'
$ReusableCases = Join-Path $CurrentReusable 'cases.jsonl'
$ReusableCorpus = Join-Path $CurrentReusable 'records'
$RuntimeState = Join-Path $CurrentReusable 'runtime-state.json'
$HistoryProbe = Join-Path $Repo 'tests\mcp_knowledge_client_e2e.py'
$ReusableProbe = Join-Path $Repo 'tests\mcp_reusable_asset_e2e.py'
$ReceiptsRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog\receipts'

foreach ($path in @($Repo,$RuntimePython,$Mvs,$CurrentSearch,$CurrentRecords,$FormalJsonl,$ActivationMarker,$CurrentReusable,$ReusableRecords,$ReusableMetadata,$ReusableRelationships,$ReusableCases,$ReusableCorpus,$RuntimeState,$ReceiptsRoot)) {
    if (-not (Test-Path $path)) { throw "RUNTIME_REQUIRED_PATH_MISSING=$path" }
}
if (Test-Path $ActivationJournal) { throw "RUNTIME_UNRESOLVED_ACTIVATION_JOURNAL=$ActivationJournal" }

function Get-Sha256 { param([string]$Path) return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash }
function Invoke-MvsStatus {
    $tag = [Guid]::NewGuid().ToString('N')
    $stdout = Join-Path $env:TEMP "gace-runtime-health-$tag.stdout.log"
    $stderr = Join-Path $env:TEMP "gace-runtime-health-$tag.stderr.log"
    $process = $null
    try {
        $process = Start-Process -FilePath $Mvs -ArgumentList @('status') -WorkingDirectory $CurrentSearch -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $process.WaitForExit(180000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            throw 'RUNTIME_MVS_STATUS_TIMEOUT=180s'
        }
        $process.Refresh()
        [string]$out = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { '' }
        [string]$err = if (Test-Path $stderr) { Get-Content $stderr -Raw } else { '' }
        [string]$all = ($out + [Environment]::NewLine + $err).Trim()
        if ($process.ExitCode -ne 0) { throw "RUNTIME_MVS_STATUS_FAILED=$($process.ExitCode) OUTPUT=$all" }
        return $all
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
        Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

$Marker = Get-Content $ActivationMarker -Raw | ConvertFrom-Json
$State = Get-Content $RuntimeState -Raw | ConvertFrom-Json
if ([string]$Marker.status -ne 'ACTIVE') { throw "RUNTIME_MARKER_STATUS_INVALID=$($Marker.status)" }
if ([string]$State.status -ne 'ACTIVE') { throw "RUNTIME_STATE_STATUS_INVALID=$($State.status)" }
if ([int]$Marker.projectionSchemaVersion -ne 2 -or [int]$State.projectionSchemaVersion -ne 2) {
    throw "RUNTIME_PROJECTION_SCHEMA_UNSUPPORTED marker=$($Marker.projectionSchemaVersion) state=$($State.projectionSchemaVersion)"
}
$Commit = [string]$Marker.catalogCommit
if ($Commit.Length -ne 40) { throw "RUNTIME_COMMIT_INVALID=$Commit" }
if ([string]$State.catalogCommit -ne $Commit) { throw "RUNTIME_STATE_COMMIT_MISMATCH marker=$Commit state=$($State.catalogCommit)" }

$ReceiptPath = Join-Path $ReceiptsRoot "$Commit.json"
if (-not (Test-Path $ReceiptPath)) { throw "RUNTIME_ACTIVE_RECEIPT_MISSING=$ReceiptPath" }
$Receipt = Get-Content $ReceiptPath -Raw | ConvertFrom-Json
if ([string]$Receipt.status -ne 'ACTIVE') { throw "RUNTIME_RECEIPT_STATUS_INVALID=$($Receipt.status)" }
if ([string]$Receipt.catalogCommit -ne $Commit) { throw "RUNTIME_RECEIPT_COMMIT_MISMATCH=$($Receipt.catalogCommit)" }
if ([int]$Receipt.projectionSchemaVersion -ne 2) { throw "RUNTIME_RECEIPT_PROJECTION_SCHEMA_UNSUPPORTED=$($Receipt.projectionSchemaVersion)" }

foreach ($name in @('formalKbSha256','knowledgeRecordsSha256','knowledgeMetadataSha256','relationshipsSha256','casesSha256','deliveryManifestSha256')) {
    if ([string]$Marker.$name -ne [string]$State.$name -or [string]$Marker.$name -ne [string]$Receipt.$name) {
        throw "RUNTIME_AUTHORITY_FIELD_MISMATCH=$name"
    }
}
if ((Get-Sha256 $FormalJsonl) -ne [string]$Marker.formalKbSha256) { throw 'RUNTIME_FORMAL_KB_HASH_MISMATCH' }
if ((Get-Sha256 $ReusableRecords) -ne [string]$Marker.knowledgeRecordsSha256) { throw 'RUNTIME_REUSABLE_RECORDS_HASH_MISMATCH' }
if ((Get-Sha256 $ReusableMetadata) -ne [string]$Marker.knowledgeMetadataSha256) { throw 'RUNTIME_REUSABLE_METADATA_HASH_MISMATCH' }
if ((Get-Sha256 $ReusableRelationships) -ne [string]$Marker.relationshipsSha256) { throw 'RUNTIME_REUSABLE_RELATIONSHIPS_HASH_MISMATCH' }
if ((Get-Sha256 $ReusableCases) -ne [string]$Marker.casesSha256) { throw 'RUNTIME_REUSABLE_CASES_HASH_MISMATCH' }
$DeliveryManifest = Join-Path $CurrentReusable 'delivery-manifest.json'
if (-not (Test-Path $DeliveryManifest)) { throw "RUNTIME_DELIVERY_MANIFEST_MISSING=$DeliveryManifest" }
if ((Get-Sha256 $DeliveryManifest) -ne [string]$Marker.deliveryManifestSha256) { throw 'RUNTIME_DELIVERY_MANIFEST_HASH_MISMATCH' }

$ExpectedTotal = [int]$Marker.totalFormalRecordCount
$ExpectedReusable = [int]$Marker.knowledgeUnitCount
$ExpectedRelationships = [int]$Marker.relationshipCount
$ExpectedCases = [int]$Marker.caseCount
$FormalCount = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() }).Count
$SearchCorpusCount = @(Get-ChildItem $CurrentRecords -Filter '*.md' -File).Count
$ReusableCount = @(Get-Content $ReusableRecords | Where-Object { $_.Trim() }).Count
$MetadataCount = @(Get-Content $ReusableMetadata | Where-Object { $_.Trim() }).Count
$RelationshipCount = @(Get-Content $ReusableRelationships | Where-Object { $_.Trim() }).Count
$CaseCount = @(Get-Content $ReusableCases | Where-Object { $_.Trim() }).Count
$ReusableCorpusFiles = @(Get-ChildItem $ReusableCorpus -Filter '*.md' -File)
if ($FormalCount -ne $ExpectedTotal -or $SearchCorpusCount -ne $ExpectedTotal) {
    throw "RUNTIME_TOTAL_COUNT_MISMATCH expected=$ExpectedTotal formal=$FormalCount corpus=$SearchCorpusCount"
}
if ($ReusableCount -ne $ExpectedReusable -or $MetadataCount -ne $ExpectedReusable -or $ReusableCorpusFiles.Count -ne $ExpectedReusable) {
    throw "RUNTIME_REUSABLE_COUNT_MISMATCH expected=$ExpectedReusable records=$ReusableCount metadata=$MetadataCount corpus=$($ReusableCorpusFiles.Count)"
}
if ($RelationshipCount -ne $ExpectedRelationships) {
    throw "RUNTIME_RELATIONSHIP_COUNT_MISMATCH expected=$ExpectedRelationships actual=$RelationshipCount"
}
if ($CaseCount -ne $ExpectedCases) {
    throw "RUNTIME_CASE_COUNT_MISMATCH expected=$ExpectedCases actual=$CaseCount"
}
foreach ($file in $ReusableCorpusFiles) {
    $head = Get-Content $file.FullName -TotalCount 16 -Raw
    if (-not $head.StartsWith("---`n") -and -not $head.StartsWith("---`r`n")) {
        throw "RUNTIME_REUSABLE_FRONTMATTER_MISSING=$($file.Name)"
    }
    if ($head -notmatch 'gace-reusable-asset') {
        throw "RUNTIME_REUSABLE_KG_TAG_MISSING=$($file.Name)"
    }
}

$Status = Invoke-MvsStatus
if ($Status -notmatch "Indexed Files:\s+$ExpectedTotal/$ExpectedTotal") { throw "RUNTIME_INDEX_COUNT_MISMATCH expected=$ExpectedTotal" }
if ($Status -match 'BM25 index building failed') { throw 'RUNTIME_BM25_WARNING_PRESENT' }
if ($Status -match 'Hybrid search will fall back to vector-only mode') { throw 'RUNTIME_VECTOR_ONLY_FALLBACK_PRESENT' }

if ($Deep) {
    foreach ($path in @($HistoryProbe,$ReusableProbe)) {
        if (-not (Test-Path $path)) { throw "DEEP_PROBE_MISSING=$path" }
    }
    & $RuntimePython -B $HistoryProbe --python $RuntimePython --project-root $CurrentSearch --timeout 180
    if ($LASTEXITCODE -ne 0) { throw "RUNTIME_DEEP_HISTORY_MCP_FAILED=$LASTEXITCODE" }
    & $RuntimePython -B $ReusableProbe --python $RuntimePython --project-root $CurrentSearch --metadata $ReusableMetadata --expected-count $ExpectedReusable --timeout 180
    if ($LASTEXITCODE -ne 0) { throw "RUNTIME_DEEP_REUSABLE_MCP_FAILED=$LASTEXITCODE" }
    Write-Host "GACE_MODULECATALOG_RUNTIME_DEEP=PASS COMMIT=$Commit RECORDS=$ExpectedReusable MODES=BM25,VECTOR,HYBRID KG=PASS"
}

Write-Host "GACE_MODULECATALOG_RUNTIME_HEALTH=PASS COMMIT=$Commit REUSABLE=$ExpectedReusable RELATIONSHIPS=$ExpectedRelationships CASES=$ExpectedCases TOTAL=$ExpectedTotal JOURNAL=NONE KG_READY=YES"
