param(
    [string]$Root = 'F:\G-ACE-KB'
)

$ErrorActionPreference = 'Stop'
$Runtime = Join-Path $Root 'runtime\mcp-vector-search'
$Py = Join-Path $Runtime 'Scripts\python.exe'
$Mvs = Join-Path $Runtime 'Scripts\mcp-vector-search.exe'
$Main = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\cli\main.py'
$Output = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\cli\output.py'
$KnowledgeGraph = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\core\knowledge_graph.py'
$ChunkProcessor = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\core\chunk_processor.py'

foreach ($p in @($Py,$Mvs,$Main,$Output,$KnowledgeGraph,$ChunkProcessor)) {
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

$kgText = Get-Content $KnowledgeGraph -Raw
if ($kgText -notmatch 'normalized_paths\s*=\s*\[p\.replace\("\\\\",\s*"/"\)\s+for\s+p\s+in\s+file_paths\]') {
    throw 'WINDOWS_KUZU_PATH_NORMALIZATION_MISSING'
}

$chunkText = Get-Content $ChunkProcessor -Raw
if ($chunkText -notmatch 'sys\.platform\s+in\s+\{["'']darwin["''],\s*["'']win32["'']\}') {
    throw 'WINDOWS_MP_CONTEXT_PATCH_MISSING'
}

$mpOutput = @(& $Py -c 'from mcp_vector_search.core.chunk_processor import _get_mp_context; print(_get_mp_context()._name)' 2>&1)
if ($LASTEXITCODE -ne 0) { throw "WINDOWS_MP_CONTEXT_PROBE_FAILED=$LASTEXITCODE" }
$mpContext = ([string]$mpOutput[-1]).Trim()
if ($mpContext -ne 'spawn') { throw "WINDOWS_MP_CONTEXT_NOT_SPAWN=$mpContext" }

& $Mvs --help *> $null
if ($LASTEXITCODE -ne 0) { throw "MVS_HELP_FAILED=$LASTEXITCODE" }

Write-Host "MVS_WINDOWS_MP_CONTEXT=$mpContext"
Write-Host 'MVS_WINDOWS_COMPAT_VERIFY=PASS'
