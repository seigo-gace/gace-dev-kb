param(
    [string]$Root = 'F:\G-ACE-KB'
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'

if (-not (Test-Path $Repo)) { throw "REPO_NOT_FOUND=$Repo" }
if (-not (Test-Path $Mvs)) { throw "MVS_NOT_FOUND=$Mvs" }

Push-Location $Repo
try {
    Write-Host '=== INDEX REGRESSION ==='
    $indexOutput = (& $Mvs index 2>&1 | Out-String)
    $indexExit = $LASTEXITCODE
    Write-Host $indexOutput
    if ($indexExit -ne 0) { throw "INDEX_FAILED=$indexExit" }
    if ($indexOutput -notmatch 'Reindex complete:') { throw 'INDEX_COMPLETION_MARKER_MISSING' }
    if ($indexOutput -match 'CodeEntity node delete failed') { throw 'KNOWLEDGE_GRAPH_WINDOWS_PATH_WARNING_PRESENT' }
    if ($indexOutput -notmatch 'Knowledge graph built successfully') { throw 'KNOWLEDGE_GRAPH_COMPLETION_MARKER_MISSING' }

    Write-Host '=== STATUS ==='
    $statusOutput = (& $Mvs status 2>&1 | Out-String)
    $statusExit = $LASTEXITCODE
    Write-Host $statusOutput
    if ($statusExit -ne 0) { throw "STATUS_FAILED=$statusExit" }
    if ($statusOutput -notmatch 'Indexed Files:\s+\d+/\d+') { throw 'STATUS_INDEX_COUNT_MISSING' }
    if ($statusOutput -notmatch 'Version:\s+4\.1\.14') { throw 'STATUS_VERSION_MISMATCH' }

    Write-Host '=== SEARCH DESIGN ==='
    $designOutput = (& $Mvs search 'design baseline implementation drift Design Delta' 2>&1 | Out-String)
    $designExit = $LASTEXITCODE
    Write-Host $designOutput
    if ($designExit -ne 0) { throw "SEARCH_DESIGN_FAILED=$designExit" }
    if ($designOutput -notmatch 'CURRENT_DESIGN\.md') { throw 'SEARCH_DESIGN_EXPECTED_DOCUMENT_MISSING' }

    Write-Host '=== SEARCH FAILURE ==='
    $failureOutput = (& $Mvs search 'failure root cause fix validation commit evidence' 2>&1 | Out-String)
    $failureExit = $LASTEXITCODE
    Write-Host $failureOutput
    if ($failureExit -ne 0) { throw "SEARCH_FAILURE_FAILED=$failureExit" }
    if ($failureOutput -notmatch '(CURRENT_DESIGN\.md|DESIGN_DELTA\.md|README\.md)') {
        throw 'SEARCH_FAILURE_EXPECTED_DOCUMENT_MISSING'
    }

    Write-Host 'MVS_REAL_REGRESSION=PASS'
}
finally {
    Pop-Location
}
