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

foreach ($p in @($Main, $Output, $KnowledgeGraph, $ChunkProcessor)) {
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
    # Match the two upstream lines independent of CRLF/LF and indentation.
    # This is intentionally narrow: only the file_paths -> escaped -> path_list
    # block in delete_entities_for_files() is eligible for replacement.
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
    # Upstream 4.1.14 treats every non-macOS platform as Linux and requests
    # multiprocessing context "fork". Windows supports "spawn", not "fork".
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

& $Mvs --help *> $null
if ($LASTEXITCODE -ne 0) { throw "MVS_HELP_FAILED=$LASTEXITCODE" }

& $Mvs doctor
if ($LASTEXITCODE -ne 0) { throw "MVS_DOCTOR_FAILED=$LASTEXITCODE" }

$mpContext = (& $Py -c 'from mcp_vector_search.core.chunk_processor import _get_mp_context; print(_get_mp_context()._name)' 2>&1 | Select-Object -Last 1).ToString().Trim()
if ($LASTEXITCODE -ne 0) { throw "MVS_MP_CONTEXT_PROBE_FAILED=$LASTEXITCODE" }
if ($mpContext -ne 'spawn') { throw "WINDOWS_MP_CONTEXT_NOT_SPAWN=$mpContext" }

Write-Host 'MVS_WINDOWS_BOOTSTRAP=PASS'
Write-Host "RUNTIME=$Runtime"
Write-Host 'VERSION=4.1.14'
Write-Host "MP_CONTEXT=$mpContext"
