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
$Embeddings = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\core\embeddings.py'
$Indexer = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\core\indexer.py'
$SearchEngine = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\core\search.py'
$McpServer = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\mcp\server.py'

foreach ($p in @($Py,$Mvs,$Main,$Output,$KnowledgeGraph,$ChunkProcessor,$Embeddings,$Indexer,$SearchEngine,$McpServer)) {
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

$embeddingText = Get-Content $Embeddings -Raw
if ($embeddingText -notmatch 'if hasattr\(self\.model,\s*["'']get_embedding_dimension["'']\):') {
    throw 'EMBEDDING_DIMENSION_API_PATCH_MISSING'
}

$indexerText = Get-Content $Indexer -Raw
if ($indexerText -notmatch 'G-ACE atomic rebuild compatibility: reopen final Lance paths before BM25') {
    throw 'ATOMIC_BM25_BACKEND_REOPEN_PATCH_MISSING'
}
if ($indexerText -notmatch 'self\.chunks_backend\s*=\s*ChunksBackend\(lance_path\)') {
    throw 'ATOMIC_BM25_CHUNKS_REOPEN_MISSING'
}
if ($indexerText -notmatch 'self\.vectors_backend\s*=\s*VectorsBackend\(lance_path\)') {
    throw 'ATOMIC_BM25_VECTORS_REOPEN_MISSING'
}

$searchText = Get-Content $SearchEngine -Raw
if ($searchText -notmatch 'G-ACE docs-only KG compatibility: no CodeEntity nodes means no code KG boost') {
    throw 'DOC_ONLY_KG_ENHANCEMENT_PATCH_MISSING'
}
if ($searchText -notmatch 'kg_stats\s*=\s*await\s+self\._kg\.get_stats\(\)') {
    throw 'DOC_ONLY_KG_STATS_GATE_MISSING'
}
if ($searchText -notmatch 'code_entities') {
    throw 'DOC_ONLY_KG_CODE_ENTITY_GATE_MISSING'
}

$mpOutput = @(& $Py -c 'from mcp_vector_search.core.chunk_processor import _get_mp_context; print(_get_mp_context()._name)' 2>&1)
if ($LASTEXITCODE -ne 0) { throw "WINDOWS_MP_CONTEXT_PROBE_FAILED=$LASTEXITCODE" }
$mpContext = ([string]$mpOutput[-1]).Trim()
if ($mpContext -ne 'spawn') { throw "WINDOWS_MP_CONTEXT_NOT_SPAWN=$mpContext" }

$mcpText = Get-Content $McpServer -Raw
if ($mcpText -notmatch 'on_list_tools\s*=\s*handle_list_tools') {
    throw 'MCP_SDK2_SERVER_PATCH_MISSING'
}
if ($mcpText -notmatch 'server\.create_initialization_options\(\)') {
    throw 'MCP_SDK2_INIT_OPTIONS_PATCH_MISSING'
}

$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $mcpProbe = @(& $Py -c 'from mcp_vector_search.mcp.server import create_mcp_server; s=create_mcp_server(enable_file_watching=False); print(type(s).__name__)' 2>&1)
    $mcpProbeExit = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($mcpProbeExit -ne 0) {
    Write-Host ($mcpProbe -join [Environment]::NewLine)
    throw "MCP_SDK2_SERVER_CREATE_PROBE_FAILED=$mcpProbeExit"
}
$mcpServerType = @($mcpProbe | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -eq 'Server' } | Select-Object -Last 1)
if ($mcpServerType.Count -ne 1 -or $mcpServerType[0] -ne 'Server') {
    Write-Host ($mcpProbe -join [Environment]::NewLine)
    throw 'MCP_SERVER_TYPE_UNEXPECTED'
}

& $Mvs --help *> $null
if ($LASTEXITCODE -ne 0) { throw "MVS_HELP_FAILED=$LASTEXITCODE" }

Write-Host "MVS_WINDOWS_MP_CONTEXT=$mpContext"
Write-Host 'MVS_MCP_SDK2_COMPAT=PASS'
Write-Host 'MVS_EMBEDDING_DIMENSION_API=PASS'
Write-Host 'MVS_ATOMIC_BM25_BACKEND_REOPEN=PASS'
Write-Host 'MVS_DOC_ONLY_KG_ENHANCEMENT=PASS'
Write-Host 'MVS_WINDOWS_COMPAT_VERIFY=PASS'
