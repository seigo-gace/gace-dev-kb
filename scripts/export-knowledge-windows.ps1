param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [string]$Revision = 'HEAD',
    [int]$MaxCount = 50
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$Adapter = Join-Path $Repo 'scripts\gace_knowledge_adapter.py'
$OutputDir = Join-Path $Root 'data\knowledge-records'
$Output = Join-Path $OutputDir 'gace-dev-kb.jsonl'

foreach ($p in @($Python, $Repo, $Adapter)) {
    if (-not (Test-Path $p)) { throw "REQUIRED_PATH_MISSING=$p" }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

& $Python $Adapter `
    --repo $Repo `
    --revision $Revision `
    --max-count $MaxCount `
    --output $Output

if ($LASTEXITCODE -ne 0) {
    throw "GACE_KNOWLEDGE_EXPORT_FAILED=$LASTEXITCODE"
}

if (-not (Test-Path $Output)) {
    throw "GACE_KNOWLEDGE_OUTPUT_MISSING=$Output"
}

$records = @(Get-Content $Output | Where-Object { $_.Trim() })
if ($records.Count -eq 0) {
    throw 'GACE_KNOWLEDGE_OUTPUT_EMPTY'
}

Write-Host "GACE_KNOWLEDGE_WINDOWS_EXPORT=PASS RECORDS=$($records.Count)"
Write-Host "OUTPUT=$Output"
