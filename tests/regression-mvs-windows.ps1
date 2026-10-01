param(
    [string]$Root = 'F:\G-ACE-KB'
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'

if (-not (Test-Path $Repo)) { throw "REPO_NOT_FOUND=$Repo" }
if (-not (Test-Path $Mvs)) { throw "MVS_NOT_FOUND=$Mvs" }

function Invoke-MvsCapture {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & $Mvs @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output   = ($lines | Out-String)
    }
}

Push-Location $Repo
try {
    Write-Host '=== INDEX REGRESSION ==='
    $indexResult = Invoke-MvsCapture 'index'
    Write-Host $indexResult.Output
    if ($indexResult.ExitCode -ne 0) { throw "INDEX_FAILED=$($indexResult.ExitCode)" }
    if ($indexResult.Output -notmatch 'Reindex complete:') { throw 'INDEX_COMPLETION_MARKER_MISSING' }
    if ($indexResult.Output -match 'CodeEntity node delete failed') { throw 'KNOWLEDGE_GRAPH_WINDOWS_PATH_WARNING_PRESENT' }
    if ($indexResult.Output -notmatch 'Knowledge graph built successfully') { throw 'KNOWLEDGE_GRAPH_COMPLETION_MARKER_MISSING' }

    Write-Host '=== STATUS ==='
    $statusResult = Invoke-MvsCapture 'status'
    Write-Host $statusResult.Output
    if ($statusResult.ExitCode -ne 0) { throw "STATUS_FAILED=$($statusResult.ExitCode)" }
    if ($statusResult.Output -notmatch 'Indexed Files:\s+\d+/\d+') { throw 'STATUS_INDEX_COUNT_MISSING' }
    if ($statusResult.Output -notmatch 'Version:\s+4\.1\.14') { throw 'STATUS_VERSION_MISMATCH' }

    Write-Host '=== SEARCH DESIGN ==='
    $designResult = Invoke-MvsCapture 'search' 'design baseline implementation drift Design Delta'
    Write-Host $designResult.Output
    if ($designResult.ExitCode -ne 0) { throw "SEARCH_DESIGN_FAILED=$($designResult.ExitCode)" }
    if ($designResult.Output -notmatch 'CURRENT_DESIGN\.md') { throw 'SEARCH_DESIGN_EXPECTED_DOCUMENT_MISSING' }

    Write-Host '=== SEARCH FAILURE ==='
    $failureResult = Invoke-MvsCapture 'search' 'failure root cause fix validation commit evidence'
    Write-Host $failureResult.Output
    if ($failureResult.ExitCode -ne 0) { throw "SEARCH_FAILURE_FAILED=$($failureResult.ExitCode)" }
    if ($failureResult.Output -notmatch '(CURRENT_DESIGN\.md|DESIGN_DELTA\.md|README\.md)') {
        throw 'SEARCH_FAILURE_EXPECTED_DOCUMENT_MISSING'
    }

    Write-Host 'MVS_REAL_REGRESSION=PASS'
}
finally {
    Pop-Location
}
