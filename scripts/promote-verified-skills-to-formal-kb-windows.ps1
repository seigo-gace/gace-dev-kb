param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [string]$RepositoryRevision = 'origin/main'
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$IndexScript = Join-Path $Repo 'scripts\index-knowledge-windows.ps1'
$CombineTest = Join-Path $Repo 'tests\test_combine_knowledge_records.py'
$ImportTest = Join-Path $Repo 'tests\test_import_verified_modulecatalog_skills.py'
$AcceptedConfig = Join-Path $Repo 'config\accepted-knowledge-sources.json'

foreach ($path in @($Repo,$Python,$IndexScript,$CombineTest,$ImportTest,$AcceptedConfig)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}

$RepositoryRevision = $RepositoryRevision.Trim()
if (-not $RepositoryRevision) { throw 'REPOSITORY_REVISION_EMPTY' }

Write-Host '=== FORMAL KB PROMOTION PREFLIGHT ==='
$trackedDirty = @(git -C $Repo status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) { throw "GIT_STATUS_FAILED=$LASTEXITCODE" }
if ($trackedDirty.Count -gt 0) {
    throw "TRACKED_WORKTREE_DIRTY=$($trackedDirty -join ';')"
}

if ($RepositoryRevision -eq 'origin/main') {
    git -C $Repo fetch origin main
    if ($LASTEXITCODE -ne 0) { throw "FETCH_ORIGIN_MAIN_FAILED=$LASTEXITCODE" }
}

$resolvedRevision = (& git -C $Repo rev-parse --verify $RepositoryRevision 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $resolvedRevision) {
    throw "REPOSITORY_REVISION_NOT_FOUND=$RepositoryRevision"
}
$resolvedRevision = $resolvedRevision.Trim()
Write-Host "FORMAL_REPOSITORY_REVISION=PASS REF=$RepositoryRevision COMMIT=$resolvedRevision"

$registry = Get-Content $AcceptedConfig -Raw | ConvertFrom-Json
if ($registry.schemaVersion -ne 1) { throw "ACCEPTED_SOURCE_SCHEMA_UNSUPPORTED=$($registry.schemaVersion)" }
$sources = @($registry.sources)
if ($sources.Count -lt 1) { throw 'ACCEPTED_SOURCE_REGISTRY_EMPTY' }
foreach ($source in $sources) {
    if ([string]$source.admission -ne 'verified') {
        throw "ACCEPTED_SOURCE_NOT_VERIFIED=$($source.id)"
    }
    if (-not [string]$source.validationBoundary) {
        throw "ACCEPTED_SOURCE_VALIDATION_BOUNDARY_MISSING=$($source.id)"
    }
}
Write-Host "ACCEPTED_SOURCE_REGISTRY=PASS SOURCES=$($sources.Count)"

Write-Host '=== STATIC/UNIT REGRESSION ==='
& $Python -B $CombineTest
if ($LASTEXITCODE -ne 0) { throw "COMBINE_TEST_FAILED=$LASTEXITCODE" }
& $Python -B $ImportTest
if ($LASTEXITCODE -ne 0) { throw "IMPORT_TEST_FAILED=$LASTEXITCODE" }
Write-Host 'FORMAL_KB_UNIT_GATES=PASS'

Write-Host '=== PROMOTE VERIFIED SOURCES INTO FORMAL KB ==='
$previousRevision = $env:GACE_KNOWLEDGE_REVISION
try {
    $env:GACE_KNOWLEDGE_REVISION = $resolvedRevision
    & $IndexScript -Root $Root -Python $Python -MaxCount 0
    if ($LASTEXITCODE -ne 0) { throw "FORMAL_KB_INDEX_FAILED=$LASTEXITCODE" }
}
finally {
    if ($null -eq $previousRevision) {
        Remove-Item Env:GACE_KNOWLEDGE_REVISION -ErrorAction SilentlyContinue
    }
    else {
        $env:GACE_KNOWLEDGE_REVISION = $previousRevision
    }
}

$formalJsonl = Join-Path $Root 'data\knowledge-records\formal-kb.jsonl'
$searchRoot = Join-Path $Root 'data\knowledge-search'
if (-not (Test-Path $formalJsonl)) { throw "FORMAL_JSONL_MISSING=$formalJsonl" }
if (-not (Test-Path $searchRoot)) { throw "FORMAL_SEARCH_ROOT_MISSING=$searchRoot" }

$formalCount = @(Get-Content $formalJsonl | Where-Object { $_.Trim() }).Count
if ($formalCount -lt 1) { throw 'FORMAL_KB_RECORD_COUNT_ZERO' }

Write-Host '=== FORMAL KB PROMOTION COMPLETE ==='
Write-Host "GACE_FORMAL_KB_PROMOTION=PASS RECORDS=$formalCount"
Write-Host "FORMAL_REPOSITORY_COMMIT=$resolvedRevision"
Write-Host "FORMAL_JSONL=$formalJsonl"
Write-Host "SEARCH_ROOT=$searchRoot"
