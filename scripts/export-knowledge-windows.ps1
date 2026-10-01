param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [string]$Revision = $(if ($env:GACE_KNOWLEDGE_REVISION) { $env:GACE_KNOWLEDGE_REVISION } else { 'HEAD' }),
    [int]$MaxCount = 0
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$Adapter = Join-Path $Repo 'scripts\gace_knowledge_adapter.py'
$OutputDir = Join-Path $Root 'data\knowledge-records'
$Output = Join-Path $OutputDir 'gace-dev-kb.jsonl'

foreach ($p in @($Python, $Repo, $Adapter)) {
    if (-not (Test-Path $p)) { throw "REQUIRED_PATH_MISSING=$p" }
}

if ($MaxCount -lt 0) { throw "MAX_COUNT_INVALID=$MaxCount" }
$Revision = $Revision.Trim()
if (-not $Revision) { throw 'REVISION_EMPTY' }

$resolvedRevision = (& git -C $Repo rev-parse --verify $Revision 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $resolvedRevision) {
    throw "REVISION_NOT_FOUND=$Revision"
}
$resolvedRevision = $resolvedRevision.Trim()

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

& $Python $Adapter `
    --repo $Repo `
    --revision $resolvedRevision `
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

$mode = if ($MaxCount -eq 0) { 'FULL_HISTORY' } else { "BOUNDED_$MaxCount" }
Write-Host "GACE_KNOWLEDGE_WINDOWS_EXPORT=PASS RECORDS=$($records.Count) MODE=$mode"
Write-Host "REVISION=$Revision"
Write-Host "RESOLVED_COMMIT=$resolvedRevision"
Write-Host "OUTPUT=$Output"
