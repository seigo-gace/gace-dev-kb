param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [string]$RepositoryRevision = 'origin/main'
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$IndexScript = Join-Path $Repo 'scripts\index-knowledge-windows.ps1'
$Importer = Join-Path $Repo 'scripts\import_verified_modulecatalog_skills.py'
$CombineTest = Join-Path $Repo 'tests\test_combine_knowledge_records.py'
$ImportTest = Join-Path $Repo 'tests\test_import_verified_modulecatalog_skills.py'
$AcceptedConfig = Join-Path $Repo 'config\accepted-knowledge-sources.json'

foreach ($path in @($Repo,$Python,$IndexScript,$Importer,$CombineTest,$ImportTest,$AcceptedConfig)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}

$RepositoryRevision = $RepositoryRevision.Trim()
if (-not $RepositoryRevision) { throw 'REPOSITORY_REVISION_EMPTY' }

function Get-SafeId {
    param([string]$Value)
    return ($Value -replace '[^0-9A-Za-z._-]', '-')
}

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

# ModuleCatalog manifests hash canonical Git blob bytes (LF). On Windows,
# core.autocrlf=true rewrites text files to CRLF and causes false manifest
# size/hash failures. Canonicalize every accepted source before promotion.
Write-Host '=== PREPARE CANONICAL ACCEPTED SOURCE CHECKOUTS ==='
foreach ($source in $sources) {
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

    $preflightRoot = Join-Path $env:TEMP ("gace-kb-accepted-preflight-" + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $preflightRoot -Force | Out-Null
        & $Python -B $Importer `
            --catalog-root $catalogRoot `
            --asset-id $assetId `
            --output-root $preflightRoot `
            --expected-skill-count $expectedCount
        if ($LASTEXITCODE -ne 0) {
            throw "ACCEPTED_SOURCE_MANIFEST_PREFLIGHT_FAILED=$sourceId"
        }

        $preflightRecords = @(Get-Content (Join-Path $preflightRoot 'knowledge-records.jsonl') | Where-Object { $_.Trim() }).Count
        if ($preflightRecords -ne $expectedCount) {
            throw "ACCEPTED_SOURCE_PREFLIGHT_COUNT_MISMATCH id=$sourceId actual=$preflightRecords expected=$expectedCount"
        }
    }
    finally {
        Remove-Item $preflightRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "ACCEPTED_SOURCE_CANONICAL_CHECKOUT=PASS ID=$sourceId COMMIT=$actualCommit AUTOCRLF=$autoCrlf"
    Write-Host "ACCEPTED_SOURCE_MANIFEST_PREFLIGHT=PASS ID=$sourceId RECORDS=$expectedCount"
}

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
