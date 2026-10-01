param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [string]$Node = 'node.exe',
    [Parameter(Mandatory=$true)][string]$CatalogCommit,
    [int]$ExpectedAssetCount = 80,
    [int]$ExpectedRecordCount = 720,
    [string]$CatalogRepository = 'seigo-gace/modular-catalog'
)

$ErrorActionPreference = 'Stop'
if ($ExpectedAssetCount -lt 1) { throw "EXPECTED_ASSET_COUNT_INVALID=$ExpectedAssetCount" }
if ($ExpectedRecordCount -lt 1) { throw "EXPECTED_RECORD_COUNT_INVALID=$ExpectedRecordCount" }

$Repo = Join-Path $Root 'repo'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$Bridge = Join-Path $Repo 'scripts\run_modulecatalog_reusable_export.mjs'
$Importer = Join-Path $Repo 'scripts\import_modulecatalog_reusable_export.py'
$Probe = Join-Path $Repo 'tests\mcp_reusable_asset_e2e.py'
$SafetyPatch = Join-Path $Repo 'scripts\patch-mvs-windows-trial-safety.ps1'
$Catalog = Join-Path $Root 'assets\modular-catalog-reusable-trial'
$TrialRoot = Join-Path $Root 'data\modulecatalog-reusable-trial'
$ExportRoot = Join-Path $TrialRoot 'export'
$ImportRoot = Join-Path $TrialRoot 'import'
$SearchRoot = Join-Path $TrialRoot 'search'
$SearchRecords = Join-Path $SearchRoot 'records'
$Metadata = Join-Path $ImportRoot 'knowledge-metadata.jsonl'
$KnowledgeRecords = Join-Path $ImportRoot 'knowledge-records.jsonl'
$FormalJsonl = Join-Path $Root 'data\knowledge-records\formal-kb.jsonl'

foreach ($path in @($Repo,$Python,$RuntimePython,$Mvs,$Bridge,$Importer,$Probe,$SafetyPatch)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}
$nodeCommand = Get-Command $Node -ErrorAction Stop
$NodePath = $nodeCommand.Source
if (-not $NodePath) { $NodePath = $nodeCommand.Path }
if (-not $NodePath) { throw "NODE_COMMAND_UNRESOLVED=$Node" }

function Get-OptionalSha256 {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash
}

function Restore-EnvironmentValue {
    param([string]$Name,[AllowNull()][string]$Value)
    if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$Name" $Value }
}

function Invoke-MvsCapture {
    param([string[]]$Arguments,[int]$TimeoutSeconds = 1800)
    $tag = [Guid]::NewGuid().ToString('N')
    $stdout = Join-Path $env:TEMP "gace-modulecatalog-$tag.stdout.log"
    $stderr = Join-Path $env:TEMP "gace-modulecatalog-$tag.stderr.log"
    $process = $null
    $started = Get-Date
    try {
        $quoted = @(foreach ($argument in $Arguments) { '"' + ([string]$argument).Replace('"','\"') + '"' })
        $process = Start-Process -FilePath $Mvs -ArgumentList $quoted -WorkingDirectory $SearchRoot -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
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

$FormalBefore = Get-OptionalSha256 -Path $FormalJsonl

Write-Host '=== MODULECATALOG PINNED CHECKOUT ==='
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
Write-Host "MODULECATALOG_PIN=PASS COMMIT=$ActualCommit"

Write-Host '=== GENERATE REUSABLE ASSET EXPORT ==='
if (Test-Path $TrialRoot) { Remove-Item $TrialRoot -Recurse -Force }
New-Item -ItemType Directory -Path $TrialRoot -Force | Out-Null
& $NodePath $Bridge --catalog-root $Catalog --output-root $ExportRoot --catalog-commit $CatalogCommit --expected-asset-count $ExpectedAssetCount
if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_EXPORT_FAILED=$LASTEXITCODE" }
if (-not (Test-Path (Join-Path $ExportRoot 'manifest.json'))) { throw 'MODULECATALOG_EXPORT_MANIFEST_MISSING' }

Write-Host '=== IMPORT REUSABLE ASSET EXPORT INTO KB PROJECTION ==='
& $Python -B $Importer --export-root $ExportRoot --output-root $ImportRoot --expected-catalog-commit $CatalogCommit --expected-asset-count $ExpectedAssetCount --expected-record-count $ExpectedRecordCount
if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_REUSABLE_IMPORT_FAILED=$LASTEXITCODE" }
foreach ($path in @($Metadata,$KnowledgeRecords,(Join-Path $ImportRoot 'records'))) {
    if (-not (Test-Path $path)) { throw "REUSABLE_IMPORT_OUTPUT_MISSING=$path" }
}
$MetadataCount = @(Get-Content $Metadata | Where-Object { $_.Trim() }).Count
$RecordCount = @(Get-Content $KnowledgeRecords | Where-Object { $_.Trim() }).Count
$CorpusCount = @(Get-ChildItem (Join-Path $ImportRoot 'records') -Filter '*.md' -File).Count
if ($MetadataCount -ne $ExpectedRecordCount -or $RecordCount -ne $ExpectedRecordCount -or $CorpusCount -ne $ExpectedRecordCount) {
    throw "REUSABLE_IMPORT_COUNT_MISMATCH metadata=$MetadataCount records=$RecordCount corpus=$CorpusCount expected=$ExpectedRecordCount"
}
Write-Host "MODULECATALOG_REUSABLE_DATA=PASS ASSETS=$ExpectedAssetCount RECORDS=$RecordCount CORPUS=$CorpusCount"

Write-Host '=== BUILD ISOLATED SEARCH PROJECT ==='
New-Item -ItemType Directory -Path $SearchRoot -Force | Out-Null
$init = Invoke-MvsCapture -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') -TimeoutSeconds 180
if ($init.ExitCode -ne 0) { throw "TRIAL_MVS_INIT_FAILED=$($init.ExitCode)" }
New-Item -ItemType Directory -Path $SearchRecords -Force | Out-Null
Copy-Item (Join-Path $ImportRoot 'records\*.md') $SearchRecords -Force

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

    $index = Invoke-MvsCapture -Arguments @('index','--force') -TimeoutSeconds 1800
    if ($index.ExitCode -ne 0) { throw "TRIAL_MVS_INDEX_FAILED=$($index.ExitCode)" }
    if ($index.Output -notmatch 'Reindex complete:') { throw 'TRIAL_MVS_INDEX_COMPLETION_MARKER_MISSING' }
    if ($index.Output -match 'BM25 index building failed') { throw 'TRIAL_BM25_BUILD_WARNING_PRESENT' }
    if ($index.Output -match 'Hybrid search will fall back to vector-only mode') { throw 'TRIAL_VECTOR_ONLY_FALLBACK_PRESENT' }

    $status = Invoke-MvsCapture -Arguments @('status') -TimeoutSeconds 180
    if ($status.ExitCode -ne 0) { throw "TRIAL_MVS_STATUS_FAILED=$($status.ExitCode)" }
    if ($status.Output -notmatch "Indexed Files:\s+$ExpectedRecordCount/$ExpectedRecordCount") {
        throw "TRIAL_MVS_INDEX_COUNT_MISMATCH expected=$ExpectedRecordCount"
    }
}
finally {
    foreach ($name in $names) { Restore-EnvironmentValue -Name $name -Value $previous[$name] }
}

Write-Host '=== MCP REUSABLE ASSET RETRIEVAL ==='
& $RuntimePython -B $Probe --python $RuntimePython --project-root $SearchRoot --metadata $Metadata --expected-count $ExpectedRecordCount --timeout 180
if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_REUSABLE_MCP_E2E_FAILED=$LASTEXITCODE" }

$FormalAfter = Get-OptionalSha256 -Path $FormalJsonl
if ($FormalBefore -ne $FormalAfter) { throw 'FORMAL_KB_CHANGED_DURING_TRIAL' }

Write-Host "GACE_MODULECATALOG_REUSABLE_TRIAL=PASS ASSETS=$ExpectedAssetCount RECORDS=$ExpectedRecordCount"
Write-Host "PINNED_MODULECATALOG_COMMIT=$CatalogCommit"
Write-Host "TRIAL_ROOT=$TrialRoot"
Write-Host 'FORMAL_KB_UNCHANGED=YES'
