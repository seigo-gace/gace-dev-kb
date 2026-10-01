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
$McpServer = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\mcp\server.py'

foreach ($p in @($Py,$Mvs,$Main,$Output,$KnowledgeGraph,$ChunkProcessor,$McpServer)) {
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
Write-Host 'MVS_WINDOWS_COMPAT_VERIFY=PASS'
