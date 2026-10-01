param(
    [string]$Root = 'F:\G-ACE-KB'
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'

if (-not (Test-Path $Repo)) { throw "REPO_NOT_FOUND=$Repo" }
if (-not (Test-Path $Mvs)) { throw "MVS_NOT_FOUND=$Mvs" }

function Write-NewLogLines {
    param(
        [string]$Path,
        [ref]$Offset,
        [System.Collections.ArrayList]$Collector
    )

    if (-not (Test-Path $Path)) { return }

    $lines = @(Get-Content -Path $Path -ErrorAction SilentlyContinue)
    for ($i = $Offset.Value; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        Write-Host $line
        [void]$Collector.Add($line)
    }
    $Offset.Value = $lines.Count
}

function Invoke-MvsStreaming {
    param(
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 600
    )

    $tag = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $env:TEMP "gace-mvs-$tag.stdout.log"
    $stderrPath = Join-Path $env:TEMP "gace-mvs-$tag.stderr.log"
    $collector = New-Object System.Collections.ArrayList
    $stdoutOffset = 0
    $stderrOffset = 0
    $process = $null
    $startedAt = Get-Date

    try {
        $quotedArguments = @(
            foreach ($argument in $Arguments) {
                '"' + ([string]$argument).Replace('"', '\"') + '"'
            }
        )

        $process = Start-Process `
            -FilePath $Mvs `
            -ArgumentList $quotedArguments `
            -WorkingDirectory $Repo `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        while (-not $process.HasExited) {
            Write-NewLogLines -Path $stdoutPath -Offset ([ref]$stdoutOffset) -Collector $collector
            Write-NewLogLines -Path $stderrPath -Offset ([ref]$stderrOffset) -Collector $collector

            if (((Get-Date) - $startedAt).TotalSeconds -ge $TimeoutSeconds) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                throw "MVS_TIMEOUT=${TimeoutSeconds}s ARGS=$($Arguments -join ' ')"
            }

            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }

        $process.WaitForExit()
        Write-NewLogLines -Path $stdoutPath -Offset ([ref]$stdoutOffset) -Collector $collector
        Write-NewLogLines -Path $stderrPath -Offset ([ref]$stderrOffset) -Collector $collector

        $elapsed = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
        Write-Host "COMMAND_EXIT=$($process.ExitCode) ELAPSED_SEC=$elapsed ARGS=$($Arguments -join ' ')"

        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = ($collector -join [Environment]::NewLine)
        }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
    }
}

Push-Location $Repo
try {
    Write-Host '=== INDEX REGRESSION ==='
    $indexResult = Invoke-MvsStreaming -Arguments @('index') -TimeoutSeconds 600
    if ($indexResult.ExitCode -ne 0) { throw "INDEX_FAILED=$($indexResult.ExitCode)" }
    if ($indexResult.Output -notmatch 'Reindex complete:') { throw 'INDEX_COMPLETION_MARKER_MISSING' }
    if ($indexResult.Output -match 'CodeEntity node delete failed') { throw 'KNOWLEDGE_GRAPH_WINDOWS_PATH_WARNING_PRESENT' }
    if ($indexResult.Output -notmatch 'Knowledge graph built successfully') { throw 'KNOWLEDGE_GRAPH_COMPLETION_MARKER_MISSING' }

    Write-Host '=== STATUS ==='
    $statusResult = Invoke-MvsStreaming -Arguments @('status') -TimeoutSeconds 120
    if ($statusResult.ExitCode -ne 0) { throw "STATUS_FAILED=$($statusResult.ExitCode)" }
    if ($statusResult.Output -notmatch 'Indexed Files:\s+\d+/\d+') { throw 'STATUS_INDEX_COUNT_MISSING' }
    if ($statusResult.Output -notmatch 'Version:\s+4\.1\.14') { throw 'STATUS_VERSION_MISMATCH' }

    Write-Host '=== SEARCH DESIGN ==='
    $designResult = Invoke-MvsStreaming -Arguments @('search', 'design baseline implementation drift Design Delta') -TimeoutSeconds 180
    if ($designResult.ExitCode -ne 0) { throw "SEARCH_DESIGN_FAILED=$($designResult.ExitCode)" }
    if ($designResult.Output -notmatch 'CURRENT_DESIGN\.md') { throw 'SEARCH_DESIGN_EXPECTED_DOCUMENT_MISSING' }

    Write-Host '=== SEARCH FAILURE ==='
    $failureResult = Invoke-MvsStreaming -Arguments @('search', 'failure root cause fix validation commit evidence') -TimeoutSeconds 180
    if ($failureResult.ExitCode -ne 0) { throw "SEARCH_FAILURE_FAILED=$($failureResult.ExitCode)" }
    if ($failureResult.Output -notmatch '(CURRENT_DESIGN\.md|DESIGN_DELTA\.md|README\.md)') {
        throw 'SEARCH_FAILURE_EXPECTED_DOCUMENT_MISSING'
    }

    Write-Host 'MVS_REAL_REGRESSION=PASS'
}
finally {
    Pop-Location
}
