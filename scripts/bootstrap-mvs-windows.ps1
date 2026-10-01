param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe'
)

$ErrorActionPreference = 'Stop'
$Runtime = Join-Path $Root 'runtime\mcp-vector-search'
$Py = Join-Path $Runtime 'Scripts\python.exe'
$Mvs = Join-Path $Runtime 'Scripts\mcp-vector-search.exe'

if (-not (Test-Path $Python)) { throw "PYTHON_NOT_FOUND=$Python" }

if (-not (Test-Path $Py)) {
    & $Python -m venv $Runtime
    if ($LASTEXITCODE -ne 0) { throw "VENV_CREATE_FAILED=$LASTEXITCODE" }
}

& $Py -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "PIP_UPGRADE_FAILED=$LASTEXITCODE" }

& $Py -m pip install 'mcp-vector-search==4.1.14'
if ($LASTEXITCODE -ne 0) { throw "MVS_INSTALL_FAILED=$LASTEXITCODE" }

$Site = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search'
$Main = Join-Path $Site 'cli\main.py'
$Output = Join-Path $Site 'cli\output.py'
$KnowledgeGraph = Join-Path $Site 'core\knowledge_graph.py'
$ChunkProcessor = Join-Path $Site 'core\chunk_processor.py'
$McpServer = Join-Path $Site 'mcp\server.py'

foreach ($p in @($Main, $Output, $KnowledgeGraph, $ChunkProcessor, $McpServer)) {
    if (-not (Test-Path $p)) { throw "MVS_SOURCE_NOT_FOUND=$p" }
}

$mainText = Get-Content $Main -Raw
if ($mainText -match '(?m)^import resource\s*$') {
    $resourceGuard = @'
if sys.platform != "win32":
    import resource
'@
    $mainText = [regex]::Replace($mainText, '(?m)^import resource\s*$', $resourceGuard)
    Set-Content $Main -Value $mainText -Encoding UTF8
}

$outputText = Get-Content $Output -Raw
$needle = @'
            relevance_score = result._original_similarity
            combined_score = result.similarity_score
'@
$replacement = @'
            relevance_score = result._original_similarity
            combined_score = result.similarity_score

            # G-ACE Windows/docs compatibility: documentation chunks can
            # have no original similarity. Use the final score for display.
            if relevance_score is None:
                relevance_score = combined_score
'@
if ($outputText.Contains($needle) -and -not $outputText.Contains('if relevance_score is None:')) {
    $outputText = $outputText.Replace($needle, $replacement)
    Set-Content $Output -Value $outputText -Encoding UTF8
}

$kgText = Get-Content $KnowledgeGraph -Raw
$kgMarker = 'normalized_paths = [p.replace("\\", "/") for p in file_paths]'
if (-not $kgText.Contains($kgMarker)) {
    $kgPattern = '(?ms)^(?<indent>[ \t]*)escaped\s*=\s*\[p\.replace\([^\r\n]+\)\s+for\s+p\s+in\s+file_paths\]\r?\n\k<indent>path_list\s*=\s*[^\r\n]+$'
    $kgReplacement = @'
${indent}# G-ACE Windows compatibility: Kuzu inline string literals must not
${indent}# receive Windows backslash-separated relative paths.
${indent}normalized_paths = [p.replace("\\", "/") for p in file_paths]
${indent}escaped = [p.replace("'", "\\'") for p in normalized_paths]
${indent}path_list = "[" + ", ".join(f"'{p}'" for p in escaped) + "]"
'@
    $patchedKgText = [regex]::Replace($kgText, $kgPattern, $kgReplacement, 1)
    if ($patchedKgText -eq $kgText) {
        throw 'KUZU_PATH_PATCH_TARGET_NOT_FOUND'
    }
    Set-Content $KnowledgeGraph -Value $patchedKgText -Encoding UTF8
    $kgText = $patchedKgText
}

if (-not $kgText.Contains($kgMarker)) {
    throw 'KUZU_PATH_PATCH_POSTCONDITION_FAILED'
}

$chunkText = Get-Content $ChunkProcessor -Raw
$spawnMarker = 'if sys.platform in {"darwin", "win32"}:'
if (-not $chunkText.Contains($spawnMarker)) {
    $chunkPattern = '(?m)^(?<indent>[ \t]*)if\s+sys\.platform\s*==\s*["'']darwin["'']\s*:\s*$'
    $chunkReplacement = '${indent}if sys.platform in {"darwin", "win32"}:'
    $patchedChunkText = [regex]::Replace($chunkText, $chunkPattern, $chunkReplacement, 1)
    if ($patchedChunkText -eq $chunkText) {
        throw 'WINDOWS_MP_CONTEXT_PATCH_TARGET_NOT_FOUND'
    }
    Set-Content $ChunkProcessor -Value $patchedChunkText -Encoding UTF8
    $chunkText = $patchedChunkText
}

if (-not $chunkText.Contains($spawnMarker)) {
    throw 'WINDOWS_MP_CONTEXT_PATCH_POSTCONDITION_FAILED'
}

# mcp-vector-search 4.1.14 still uses the MCP SDK 1.x decorator API
# (server.list_tools()/server.call_tool()), while its dependency constraint
# allows MCP SDK 2.x. MCP 2.x removed those decorators and accepts handlers in
# the Server constructor. Adapt the installed OSS runtime without creating a
# second MCP server implementation.
$mcpText = Get-Content $McpServer -Raw
$mcpMarker = 'on_list_tools=handle_list_tools'
if (-not $mcpText.Contains($mcpMarker)) {
    if ($mcpText -notmatch '(?m)^\s*ListToolsResult,\s*$') {
        $mcpText = [regex]::Replace(
            $mcpText,
            '(?m)^(\s*)LoggingCapability,\s*$',
            '${1}LoggingCapability,' + [Environment]::NewLine + '${1}ListToolsResult,',
            1
        )
    }

    $mcpFunctionPattern = '(?ms)^def create_mcp_server\(.*?^    return server\r?\n\r?\n\r?\n(?=async def run_mcp_server\()'
    $mcpFunctionReplacement = @'
def create_mcp_server(
    project_root: Path | None = None, enable_file_watching: bool | None = None
) -> Server:
    """Create and configure the MCP server."""
    mcp_server = MCPVectorSearchServer(project_root, enable_file_watching)

    async def handle_list_tools(ctx, params):
        return ListToolsResult(tools=mcp_server.get_tools())

    async def handle_call_tool(ctx, params):
        call_request = CallToolRequest(
            params=CallToolRequestParams(
                name=params.name, arguments=params.arguments or {}
            )
        )
        return await mcp_server.call_tool(call_request)

    server = Server(
        "mcp-vector-search",
        version="0.4.0",
        on_list_tools=handle_list_tools,
        on_call_tool=handle_call_tool,
    )

    server._mcp_server = mcp_server  # type: ignore[reportAttributeAccessIssue]
    return server


'@
    $patchedMcpText = [regex]::Replace($mcpText, $mcpFunctionPattern, $mcpFunctionReplacement, 1)
    if ($patchedMcpText -eq $mcpText) {
        throw 'MCP_SDK2_SERVER_PATCH_TARGET_NOT_FOUND'
    }

    $patchedMcpText = [regex]::Replace(
        $patchedMcpText,
        '(?ms)^    # Create initialization options with proper capabilities\r?\n    init_options = InitializationOptions\(.*?^    \)\r?\n',
        '    init_options = server.create_initialization_options()' + [Environment]::NewLine,
        1
    )

    Set-Content $McpServer -Value $patchedMcpText -Encoding UTF8
    $mcpText = $patchedMcpText
}

if (-not $mcpText.Contains($mcpMarker)) {
    throw 'MCP_SDK2_SERVER_PATCH_POSTCONDITION_FAILED'
}
if (-not $mcpText.Contains('server.create_initialization_options()')) {
    throw 'MCP_SDK2_INIT_OPTIONS_PATCH_POSTCONDITION_FAILED'
}

& $Mvs --help *> $null
if ($LASTEXITCODE -ne 0) { throw "MVS_HELP_FAILED=$LASTEXITCODE" }

& $Mvs doctor
if ($LASTEXITCODE -ne 0) { throw "MVS_DOCTOR_FAILED=$LASTEXITCODE" }

$mpContext = (& $Py -c 'from mcp_vector_search.core.chunk_processor import _get_mp_context; print(_get_mp_context()._name)' 2>&1 | Select-Object -Last 1).ToString().Trim()
if ($LASTEXITCODE -ne 0) { throw "MVS_MP_CONTEXT_PROBE_FAILED=$LASTEXITCODE" }
if ($mpContext -ne 'spawn') { throw "WINDOWS_MP_CONTEXT_NOT_SPAWN=$mpContext" }

$previousErrorActionPreference = $ErrorActionPreference
try {
    # MCPVectorSearchServer logs an informational line to stderr when no
    # project root is supplied. Under PowerShell Stop mode, native stderr is
    # promoted to NativeCommandError even when Python exits 0. Capture it
    # without turning a successful compatibility probe into a false failure.
    $ErrorActionPreference = 'Continue'
    $mcpServerProbe = @(& $Py -c 'from mcp_vector_search.mcp.server import create_mcp_server; s=create_mcp_server(enable_file_watching=False); print(type(s).__name__)' 2>&1)
    $mcpServerProbeExit = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
if ($mcpServerProbeExit -ne 0) {
    Write-Host ($mcpServerProbe -join [Environment]::NewLine)
    throw "MVS_MCP_SERVER_CREATE_PROBE_FAILED=$mcpServerProbeExit"
}
$mcpServerType = @($mcpServerProbe | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -eq 'Server' } | Select-Object -Last 1)
if ($mcpServerType.Count -ne 1 -or $mcpServerType[0] -ne 'Server') {
    Write-Host ($mcpServerProbe -join [Environment]::NewLine)
    throw 'MVS_MCP_SERVER_TYPE_UNEXPECTED'
}

Write-Host 'MVS_WINDOWS_BOOTSTRAP=PASS'
Write-Host "RUNTIME=$Runtime"
Write-Host 'VERSION=4.1.14'
Write-Host "MP_CONTEXT=$mpContext"
Write-Host 'MCP_SDK2_COMPAT=PASS'
