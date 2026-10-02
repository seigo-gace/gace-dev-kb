param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [Parameter(Mandatory=$true)][string]$CatalogCommit,
    [Parameter(Mandatory=$true)][string]$BundlePath,
    [Parameter(Mandatory=$true)][int]$ExpectedRecordCount,
    [string]$CatalogRepository = 'seigo-gace/modular-catalog'
)

$ErrorActionPreference = 'Stop'
if ($ExpectedRecordCount -lt 1) { throw "EXPECTED_RECORD_COUNT_INVALID=$ExpectedRecordCount" }

$Repo = Join-Path $Root 'repo'
$Catalog = Join-Path $Root 'assets\modular-catalog-reusable-asset-trial'
$TrialRoot = Join-Path $Root 'data\reusable-asset-trial'
$Importer = Join-Path $Repo 'scripts\import_reusable_asset_bundle.py'
$Probe = Join-Path $Repo 'tests\mcp_reusable_asset_e2e.py'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$Verify = Join-Path $Repo 'tests\verify-mvs-windows.ps1'
$Bootstrap = Join-Path $Repo 'scripts\bootstrap-mvs-windows.ps1'

foreach ($path in @($Repo,$Python,$Importer,$Probe,$RuntimePython,$Mvs,$Verify,$Bootstrap)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}

Write-Host '=== REUSABLE ASSET KB TRIAL PREFLIGHT ==='
try {
    & $Verify -Root $Root
}
catch {
    Write-Host "COMPAT_VERIFY_NEEDS_REPAIR=$($_.Exception.Message)"
    & $Bootstrap -Root $Root -Python $Python
    & $Verify -Root $Root
}

if (Test-Path $Catalog) { Remove-Item $Catalog -Recurse -Force }
New-Item -ItemType Directory -Path (Split-Path $Catalog) -Force | Out-Null

git -c core.autocrlf=false clone --no-checkout "https://github.com/$CatalogRepository.git" $Catalog
if ($LASTEXITCODE -ne 0) { throw "CATALOG_CLONE_FAILED=$LASTEXITCODE" }
git -C $Catalog config core.autocrlf false
if ($LASTEXITCODE -ne 0) { throw "CATALOG_AUTOCRLF_CONFIG_FAILED=$LASTEXITCODE" }
git -C $Catalog checkout --detach $CatalogCommit
if ($LASTEXITCODE -ne 0) { throw "CATALOG_CHECKOUT_FAILED=$LASTEXITCODE" }
$ActualCommit = (git -C $Catalog rev-parse HEAD).Trim()
if ($ActualCommit -ne $CatalogCommit) { throw "CATALOG_COMMIT_MISMATCH expected=$CatalogCommit actual=$ActualCommit" }
Write-Host "REUSABLE_ASSET_CATALOG_PIN=PASS COMMIT=$ActualCommit AUTOCRLF=false"

if (Test-Path $TrialRoot) { Remove-Item $TrialRoot -Recurse -Force }
New-Item -ItemType Directory -Path $TrialRoot -Force | Out-Null

& $Python -B $Importer `
    --catalog-root $Catalog `
    --bundle-path $BundlePath `
    --output-root $TrialRoot `
    --expected-record-count $ExpectedRecordCount
if ($LASTEXITCODE -ne 0) { throw "REUSABLE_ASSET_IMPORT_FAILED=$LASTEXITCODE" }

$Records = Join-Path $TrialRoot 'knowledge-records.jsonl'
$Metadata = Join-Path $TrialRoot 'knowledge-metadata.jsonl'
$Corpus = Join-Path $TrialRoot 'records'
$RecordCount = @(Get-Content $Records | Where-Object { $_.Trim() }).Count
$MetadataCount = @(Get-Content $Metadata | Where-Object { $_.Trim() }).Count
$CorpusCount = @(Get-ChildItem $Corpus -Filter '*.md' -File).Count
if ($RecordCount -ne $ExpectedRecordCount -or $MetadataCount -ne $ExpectedRecordCount -or $CorpusCount -ne $ExpectedRecordCount) {
    throw "REUSABLE_ASSET_OUTPUT_COUNT_MISMATCH records=$RecordCount metadata=$MetadataCount corpus=$CorpusCount expected=$ExpectedRecordCount"
}
Write-Host "REUSABLE_ASSET_DATA=PASS RECORDS=$RecordCount METADATA=$MetadataCount CORPUS=$CorpusCount"

Push-Location $TrialRoot
try {
    & $Mvs init --force --extensions .md --no-auto-index --no-mcp --no-auto-indexing
    if ($LASTEXITCODE -ne 0) { throw "REUSABLE_ASSET_MVS_INIT_FAILED=$LASTEXITCODE" }
    & $Mvs index --force
    if ($LASTEXITCODE -ne 0) { throw "REUSABLE_ASSET_MVS_INDEX_FAILED=$LASTEXITCODE" }
    $Status = (& $Mvs status | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "REUSABLE_ASSET_MVS_STATUS_FAILED=$LASTEXITCODE" }
    Write-Host $Status
    if ($Status -notmatch "Indexed Files:\s+$ExpectedRecordCount/$ExpectedRecordCount") {
        throw "REUSABLE_ASSET_INDEX_COUNT_MISMATCH expected=$ExpectedRecordCount"
    }
}
finally {
    Pop-Location
}

& $RuntimePython -B $Probe `
    --python $RuntimePython `
    --project-root $TrialRoot `
    --metadata $Metadata `
    --expected-count $ExpectedRecordCount `
    --timeout 180
if ($LASTEXITCODE -ne 0) { throw "REUSABLE_ASSET_MCP_E2E_FAILED=$LASTEXITCODE" }

Write-Host "GACE_REUSABLE_ASSET_KB_TRIAL=PASS RECORDS=$ExpectedRecordCount"
Write-Host "PINNED_MODULECATALOG_COMMIT=$CatalogCommit"
Write-Host "BUNDLE_PATH=$BundlePath"
Write-Host "TRIAL_ROOT=$TrialRoot"
Write-Host 'FORMAL_KB_UNCHANGED=YES'
