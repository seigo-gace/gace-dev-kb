param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [string]$CatalogCommit = 'bd258ec91b6970853d14a7bf4e65731312a487e3',
    [string]$AssetId = 'debugai-code-repair-verification-skill-pack',
    [int]$ExpectedSkillCount = 13
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$Catalog = Join-Path $Root 'assets\modular-catalog-debugai-trial'
$TrialRoot = Join-Path $Root 'data\debugai-skill-trial'
$Records = Join-Path $TrialRoot 'knowledge-records.jsonl'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$Importer = Join-Path $Repo 'scripts\import_verified_modulecatalog_skills.py'
$Probe = Join-Path $Repo 'tests\mcp_verified_skill_trial_e2e.py'
$VerifyScript = Join-Path $Repo 'tests\verify-mvs-windows.ps1'
$BootstrapScript = Join-Path $Repo 'scripts\bootstrap-mvs-windows.ps1'

foreach ($path in @($Repo, $Python, $RuntimePython, $Mvs, $Importer, $Probe, $VerifyScript, $BootstrapScript)) {
    if (-not (Test-Path $path)) {
        throw "REQUIRED_PATH_MISSING=$path"
    }
}
if ($ExpectedSkillCount -lt 1) {
    throw "EXPECTED_SKILL_COUNT_INVALID=$ExpectedSkillCount"
}

Write-Host '=== PREPARE PINNED MODULECATALOG SOURCE ==='
New-Item -ItemType Directory -Path (Split-Path $Catalog) -Force | Out-Null
if (Test-Path $Catalog) {
    Remove-Item $Catalog -Recurse -Force
}

git -c core.autocrlf=false clone --no-checkout https://github.com/seigo-gace/modular-catalog.git $Catalog
if ($LASTEXITCODE -ne 0) {
    throw "MODULECATALOG_CLONE_FAILED=$LASTEXITCODE"
}
git -C $Catalog config core.autocrlf false

git -C $Catalog checkout --detach $CatalogCommit
if ($LASTEXITCODE -ne 0) {
    throw "MODULECATALOG_CHECKOUT_FAILED=$LASTEXITCODE"
}

$actualCatalogCommit = (git -C $Catalog rev-parse HEAD).Trim()
if ($actualCatalogCommit -ne $CatalogCommit) {
    throw "MODULECATALOG_COMMIT_MISMATCH expected=$CatalogCommit actual=$actualCatalogCommit"
}
Write-Host "MODULECATALOG_PINNED=PASS COMMIT=$actualCatalogCommit"

Write-Host "`n=== VERIFY WINDOWS MVS COMPATIBILITY ==="
try {
    & $VerifyScript -Root $Root
}
catch {
    Write-Host "COMPAT_VERIFY_NEEDS_REPAIR=$($_.Exception.Message)"
    & $BootstrapScript -Root $Root -Python $Python
    & $VerifyScript -Root $Root
}

Write-Host "`n=== IMPORT VERIFIED DEBUGAI SKILLS ==="
if (Test-Path $TrialRoot) {
    Remove-Item $TrialRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $TrialRoot -Force | Out-Null

& $Python -B $Importer `
    --catalog-root $Catalog `
    --asset-id $AssetId `
    --output-root $TrialRoot `
    --expected-skill-count $ExpectedSkillCount
if ($LASTEXITCODE -ne 0) {
    throw "DEBUGAI_SKILL_IMPORT_FAILED=$LASTEXITCODE"
}

if (-not (Test-Path $Records)) {
    throw "DEBUGAI_SKILL_RECORDS_MISSING=$Records"
}
$recordCount = @(Get-Content $Records | Where-Object { $_.Trim() }).Count
$corpusCount = @(Get-ChildItem (Join-Path $TrialRoot 'records') -Filter '*.md' -File).Count
if ($recordCount -ne $ExpectedSkillCount) {
    throw "DEBUGAI_SKILL_RECORD_COUNT_MISMATCH expected=$ExpectedSkillCount actual=$recordCount"
}
if ($corpusCount -ne $ExpectedSkillCount) {
    throw "DEBUGAI_SKILL_CORPUS_COUNT_MISMATCH expected=$ExpectedSkillCount actual=$corpusCount"
}
Write-Host "DEBUGAI_SKILL_DATA=PASS RECORDS=$recordCount CORPUS=$corpusCount"

Write-Host "`n=== INITIALIZE ISOLATED TRIAL KB ==="
Push-Location $TrialRoot
try {
    & $Mvs init --force --extensions .md --no-auto-index --no-mcp --no-auto-indexing
    if ($LASTEXITCODE -ne 0) {
        throw "DEBUGAI_SKILL_MVS_INIT_FAILED=$LASTEXITCODE"
    }

    Write-Host "`n=== INDEX VERIFIED DEBUGAI SKILLS ==="
    & $Mvs index --force
    if ($LASTEXITCODE -ne 0) {
        throw "DEBUGAI_SKILL_MVS_INDEX_FAILED=$LASTEXITCODE"
    }

    Write-Host "`n=== VERIFY INDEX STATUS ==="
    $status = (& $Mvs status 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "DEBUGAI_SKILL_MVS_STATUS_FAILED=$LASTEXITCODE"
    }
    Write-Host $status
    if ($status -notmatch "Indexed Files:\s+$ExpectedSkillCount/$ExpectedSkillCount") {
        throw "DEBUGAI_SKILL_INDEX_COUNT_MISMATCH expected=$ExpectedSkillCount"
    }
}
finally {
    Pop-Location
}

Write-Host "`n=== REAL MCP RETRIEVAL: ALL 13 + NATURAL QUERIES ==="
& $RuntimePython -B $Probe `
    --python $RuntimePython `
    --project-root $TrialRoot `
    --records $Records `
    --expected-count $ExpectedSkillCount
if ($LASTEXITCODE -ne 0) {
    throw "DEBUGAI_SKILL_MCP_E2E_FAILED=$LASTEXITCODE"
}

Write-Host "`n=== FINAL ==="
Write-Host "GACE_DEBUGAI_VERIFIED_SKILL_TRIAL=PASS SKILLS=$ExpectedSkillCount"
Write-Host "PINNED_MODULECATALOG_COMMIT=$CatalogCommit"
Write-Host "TRIAL_ROOT=$TrialRoot"
Write-Host 'FORMAL_KB_UNCHANGED=YES'
