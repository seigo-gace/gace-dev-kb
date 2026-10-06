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
$BasePromote = Join-Path $Repo 'scripts\promote-verified-skills-to-formal-kb-windows.ps1'
$Importer = Join-Path $Repo 'scripts\import_reusable_asset_bundle.py'
$Combiner = Join-Path $Repo 'scripts\combine_knowledge_records.py'
$SafetyPatch = Join-Path $Repo 'scripts\patch-mvs-windows-trial-safety.ps1'
$HistoryProbe = Join-Path $Repo 'tests\mcp_knowledge_client_e2e.py'
$SkillProbe = Join-Path $Repo 'tests\mcp_verified_skill_trial_e2e.py'
$ReusableProbe = Join-Path $Repo 'tests\mcp_reusable_asset_e2e.py'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$FormalJsonl = Join-Path $Root 'data\knowledge-records\formal-kb.jsonl'
$SearchRoot = Join-Path $Root 'data\knowledge-search'
$Corpus = Join-Path $SearchRoot 'records'
$Catalog = Join-Path $Root 'assets\modular-catalog-reusable-asset-formal'
$SafeBundle = ($BundlePath -replace '[^0-9A-Za-z._-]', '-')
$SourceId = "reusable-$($CatalogCommit.Substring(0,12))-$SafeBundle"
$OutputRoot = Join-Path $Root "data\knowledge-sources\accepted\$SourceId"
$OldSkillRecords = Join-Path $Root 'data\knowledge-sources\accepted\debugai-code-repair-verification-skill-pack\knowledge-records.jsonl'

foreach ($path in @($Repo,$Python,$BasePromote,$Importer,$Combiner,$SafetyPatch,$HistoryProbe,$SkillProbe,$ReusableProbe,$RuntimePython,$Mvs)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}

function Restore-EnvironmentValue {
    param([string]$Name,[AllowNull()][string]$Value)
    if ($null -eq $Value) { Remove-Item "Env:$Name" -ErrorAction SilentlyContinue }
    else { Set-Item "Env:$Name" $Value }
}

function Invoke-MvsCapture {
    param([string[]]$Arguments,[int]$TimeoutSeconds = 900)
    $tag=[Guid]::NewGuid().ToString('N')
    $stdout=Join-Path $env:TEMP "gace-reusable-$tag.stdout.log"
    $stderr=Join-Path $env:TEMP "gace-reusable-$tag.stderr.log"
    $process=$null; $started=Get-Date
    try {
        $quoted=@(foreach($argument in $Arguments){ '"'+([string]$argument).Replace('"','\"')+'"' })
        $process=Start-Process -FilePath $Mvs -ArgumentList $quoted -WorkingDirectory $SearchRoot -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        while(-not $process.HasExited){
            if(((Get-Date)-$started).TotalSeconds -ge $TimeoutSeconds){ Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue; throw "MVS_TIMEOUT=${TimeoutSeconds}s" }
            Start-Sleep -Milliseconds 500; $process.Refresh()
        }
        $process.WaitForExit(); $process.Refresh()
        [string]$out=if(Test-Path $stdout){Get-Content $stdout -Raw}else{''}; [string]$err=if(Test-Path $stderr){Get-Content $stderr -Raw}else{''}; [string]$all=($out+[Environment]::NewLine+$err).Trim()
        if($all){Write-Host $all}
        return [pscustomobject]@{ExitCode=[int]$process.ExitCode;Output=$all}
    }
    finally {
        if($null -ne $process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
        Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '=== REBUILD VERIFIED BASE FORMAL KB ==='
& $BasePromote -Root $Root -Python $Python
if ($LASTEXITCODE -ne 0) { throw "BASE_FORMAL_PROMOTION_FAILED=$LASTEXITCODE" }
if (-not (Test-Path $FormalJsonl)) { throw "BASE_FORMAL_JSONL_MISSING=$FormalJsonl" }
$BaseCount = @(Get-Content $FormalJsonl | Where-Object { $_.Trim() }).Count
if ($BaseCount -lt 1) { throw 'BASE_FORMAL_RECORD_COUNT_ZERO' }
Write-Host "BASE_FORMAL_KB=PASS RECORDS=$BaseCount"

Write-Host '=== CHECKOUT PINNED MODULECATALOG BUNDLE ==='
if (Test-Path $Catalog) { Remove-Item $Catalog -Recurse -Force }
New-Item -ItemType Directory -Path (Split-Path $Catalog) -Force | Out-Null
git -c core.autocrlf=false clone --no-checkout "https://github.com/$CatalogRepository.git" $Catalog
if ($LASTEXITCODE -ne 0) { throw "CATALOG_CLONE_FAILED=$LASTEXITCODE" }
git -C $Catalog config core.autocrlf false
git -C $Catalog checkout --detach $CatalogCommit
if ($LASTEXITCODE -ne 0) { throw "CATALOG_CHECKOUT_FAILED=$LASTEXITCODE" }
$ActualCommit=(git -C $Catalog rev-parse HEAD).Trim()
if ($ActualCommit -ne $CatalogCommit) { throw "CATALOG_COMMIT_MISMATCH expected=$CatalogCommit actual=$ActualCommit" }
Write-Host "REUSABLE_ASSET_CATALOG_PIN=PASS COMMIT=$ActualCommit"

Write-Host '=== IMPORT REUSABLE ASSET BUNDLE ==='
if (Test-Path $OutputRoot) { Remove-Item $OutputRoot -Recurse -Force }
& $Python -B $Importer --catalog-root $Catalog --bundle-path $BundlePath --output-root $OutputRoot --expected-record-count $ExpectedRecordCount
if ($LASTEXITCODE -ne 0) { throw "REUSABLE_ASSET_IMPORT_FAILED=$LASTEXITCODE" }
$NewRecords = Join-Path $OutputRoot 'knowledge-records.jsonl'
$Metadata = Join-Path $OutputRoot 'knowledge-metadata.jsonl'
$NewCorpus = Join-Path $OutputRoot 'records'
foreach($path in @($NewRecords,$Metadata,$NewCorpus)){if(-not(Test-Path $path)){throw "REUSABLE_ASSET_OUTPUT_MISSING=$path"}}

Write-Host '=== COMBINE INTO FORMAL KNOWLEDGE ==='
$NextFormal = Join-Path $Root 'data\knowledge-records\formal-kb.next.jsonl'
& $Python -B $Combiner --input $FormalJsonl --input $NewRecords --output $NextFormal
if ($LASTEXITCODE -ne 0) { throw "REUSABLE_ASSET_COMBINE_FAILED=$LASTEXITCODE" }
$ExpectedFormal = $BaseCount + $ExpectedRecordCount
$NextCount = @(Get-Content $NextFormal | Where-Object { $_.Trim() }).Count
if ($NextCount -ne $ExpectedFormal) { throw "REUSABLE_ASSET_FORMAL_COUNT_MISMATCH expected=$ExpectedFormal actual=$NextCount" }
Move-Item $NextFormal $FormalJsonl -Force

Get-ChildItem $Corpus -Filter "accepted-$SourceId-*" -File -ErrorAction SilentlyContinue | Remove-Item -Force
foreach($file in Get-ChildItem $NewCorpus -Filter '*.md' -File){ Copy-Item $file.FullName (Join-Path $Corpus "accepted-$SourceId-$($file.Name)") -Force }
$CorpusCount=@(Get-ChildItem $Corpus -Filter '*.md' -File).Count
if($CorpusCount -ne $ExpectedFormal){throw "REUSABLE_ASSET_CORPUS_COUNT_MISMATCH expected=$ExpectedFormal actual=$CorpusCount"}
Write-Host "GACE_REUSABLE_ASSET_FORMAL_CORPUS=PASS RECORDS=$ExpectedFormal"

Write-Host '=== REINDEX FORMAL KB WITH WINDOWS SAFETY ==='
& $SafetyPatch -Root $Root
$names=@('MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING','MCP_VECTOR_SEARCH_WORKERS','MCP_VECTOR_SEARCH_MAX_WORKERS','MCP_VECTOR_SEARCH_BATCH_SIZE','MCP_VECTOR_SEARCH_FILE_BATCH_SIZE','OMP_NUM_THREADS','MKL_NUM_THREADS','OPENBLAS_NUM_THREADS','NUMEXPR_NUM_THREADS','TOKENIZERS_PARALLELISM')
$previous=@{}; foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try {
    $env:MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING='1'; $env:MCP_VECTOR_SEARCH_WORKERS='1'; $env:MCP_VECTOR_SEARCH_MAX_WORKERS='1'; $env:MCP_VECTOR_SEARCH_BATCH_SIZE='8'; $env:MCP_VECTOR_SEARCH_FILE_BATCH_SIZE='16'; $env:OMP_NUM_THREADS='1'; $env:MKL_NUM_THREADS='1'; $env:OPENBLAS_NUM_THREADS='1'; $env:NUMEXPR_NUM_THREADS='1'; $env:TOKENIZERS_PARALLELISM='false'
    $IndexResult=Invoke-MvsCapture -Arguments @('index','--force') -TimeoutSeconds 900
    if($IndexResult.ExitCode -ne 0){throw "REUSABLE_ASSET_MVS_INDEX_FAILED=$($IndexResult.ExitCode)"}
    if($IndexResult.Output -notmatch 'Reindex complete:'){throw 'REUSABLE_ASSET_INDEX_COMPLETION_MARKER_MISSING'}
    $StatusResult=Invoke-MvsCapture -Arguments @('status') -TimeoutSeconds 180
    if($StatusResult.ExitCode -ne 0){throw "REUSABLE_ASSET_MVS_STATUS_FAILED=$($StatusResult.ExitCode)"}
    if($StatusResult.Output -notmatch "Indexed Files:\s+$ExpectedFormal/$ExpectedFormal"){throw "REUSABLE_ASSET_INDEX_COUNT_MISMATCH expected=$ExpectedFormal"}
}
finally { foreach($name in $names){Restore-EnvironmentValue -Name $name -Value $previous[$name]} }

Write-Host '=== MCP REGRESSION: HISTORY ==='
& $RuntimePython -B $HistoryProbe --python $RuntimePython --project-root $SearchRoot --timeout 180
if ($LASTEXITCODE -ne 0) { throw "MCP_HISTORY_REGRESSION_FAILED=$LASTEXITCODE" }

if (Test-Path $OldSkillRecords) {
    $OldCount=@(Get-Content $OldSkillRecords | Where-Object { $_.Trim() }).Count
    Write-Host '=== MCP REGRESSION: EXISTING ACCEPTED SKILLS ==='
    & $RuntimePython -B $SkillProbe --python $RuntimePython --project-root $SearchRoot --records $OldSkillRecords --expected-count $OldCount --timeout 180
    if ($LASTEXITCODE -ne 0) { throw "MCP_EXISTING_SKILL_REGRESSION_FAILED=$LASTEXITCODE" }
}

Write-Host '=== MCP RETRIEVAL: REUSABLE ASSETS ==='
& $RuntimePython -B $ReusableProbe --python $RuntimePython --project-root $SearchRoot --metadata $Metadata --expected-count $ExpectedRecordCount --timeout 180
if ($LASTEXITCODE -ne 0) { throw "MCP_REUSABLE_ASSET_E2E_FAILED=$LASTEXITCODE" }

Write-Host "GACE_REUSABLE_ASSET_FORMAL_PROMOTION=PASS BASE=$BaseCount ADDED=$ExpectedRecordCount TOTAL=$ExpectedFormal"
Write-Host "PINNED_MODULECATALOG_COMMIT=$CatalogCommit"
Write-Host "BUNDLE_PATH=$BundlePath"
Write-Host "FORMAL_JSONL=$FormalJsonl"
Write-Host "SEARCH_ROOT=$SearchRoot"
