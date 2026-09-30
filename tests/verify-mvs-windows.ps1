param(
    [string]$Root = 'F:\G-ACE-KB'
)

$ErrorActionPreference = 'Stop'
$Runtime = Join-Path $Root 'runtime\mcp-vector-search'
$Py = Join-Path $Runtime 'Scripts\python.exe'
$Mvs = Join-Path $Runtime 'Scripts\mcp-vector-search.exe'
$Main = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\cli\main.py'
$Output = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\cli\output.py'

foreach ($p in @($Py,$Mvs,$Main,$Output)) {
    if (-not (Test-Path $p)) { throw "REQUIRED_PATH_MISSING=$p" }
}

$mainText = Get-Content $Main -Raw
if ($mainText -match '(?m)^import resource\s*$') {
    throw 'WINDOWS_RESOURCE_PATCH_MISSING'
}
if ($mainText -notmatch 'sys\.platform\s*!=\s*["'']win32["'']') {
    throw 'WINDOWS_RESOURCE_GUARD_MISSING'
}

$outputText = Get-Content $Output -Raw
if ($outputText -notmatch 'if relevance_score is None:') {
    throw 'SEARCH_NONE_FALLBACK_MISSING'
}

& $Mvs --help *> $null
if ($LASTEXITCODE -ne 0) { throw "MVS_HELP_FAILED=$LASTEXITCODE" }

Write-Host 'MVS_WINDOWS_COMPAT_VERIFY=PASS'
