param(
    [string]$Root = 'F:\G-ACE-KB'
)

$ErrorActionPreference = 'Stop'

$Runtime = Join-Path $Root 'runtime\mcp-vector-search'
$Py = Join-Path $Runtime 'Scripts\python.exe'
$Indexer = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search\core\indexer.py'

foreach ($path in @($Py, $Indexer)) {
    if (-not (Test-Path $path)) {
        throw "REQUIRED_PATH_MISSING=$path"
    }
}

$marker = '# G-ACE Windows trial safety: environment-gated multiprocessing disable.'
$indexerText = Get-Content $Indexer -Raw

if (-not $indexerText.Contains($marker)) {
    $pattern = '(?m)^(?<indent>        )# Resolve config: use provided config or build from env vars \(backward compat\)\s*$'
    $replacement = @'
        # G-ACE Windows trial safety: environment-gated multiprocessing disable.
        # mcp-vector-search 4.1.14 uses ProcessPoolExecutor for parsing even with
        # one worker. A native Windows worker crash can therefore fan out fatal
        # access-violation messages. This opt-in gate is used only by the isolated
        # DebugAI skill trial; normal KB indexing is unchanged when the variable
        # is absent.
        if (
            sys.platform == "win32"
            and os.environ.get(
                "MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING", ""
            ).lower()
            in {"1", "true", "yes"}
        ):
            use_multiprocessing = False
            logger.warning(
                "Windows trial safety enabled: multiprocessing parser disabled"
            )

        # Resolve config: use provided config or build from env vars (backward compat)
'@

    $patched = [regex]::Replace($indexerText, $pattern, $replacement, 1)
    if ($patched -eq $indexerText) {
        throw 'WINDOWS_TRIAL_SAFETY_PATCH_TARGET_NOT_FOUND'
    }
    Set-Content $Indexer -Value $patched -Encoding UTF8
    $indexerText = $patched
}

if (-not $indexerText.Contains($marker)) {
    throw 'WINDOWS_TRIAL_SAFETY_PATCH_POSTCONDITION_FAILED'
}
if ($indexerText -notmatch 'MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING') {
    throw 'WINDOWS_TRIAL_SAFETY_ENV_GUARD_MISSING'
}
if ($indexerText -notmatch 'use_multiprocessing\s*=\s*False') {
    throw 'WINDOWS_TRIAL_SAFETY_DISABLE_MISSING'
}

& $Py -m py_compile $Indexer
if ($LASTEXITCODE -ne 0) {
    throw "WINDOWS_TRIAL_SAFETY_PY_COMPILE_FAILED=$LASTEXITCODE"
}

Write-Host 'MVS_WINDOWS_TRIAL_SAFETY_PATCH=PASS'
Write-Host 'MVS_WINDOWS_TRIAL_MULTIPROCESSING_GATE=MCP_VECTOR_SEARCH_DISABLE_MULTIPROCESSING'
