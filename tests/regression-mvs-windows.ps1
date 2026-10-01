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
        $process.Refresh()
        Write-NewLogLines -Path $stdoutPath -Offset ([ref]$stdoutOffset) -Collector $collector
        Write-NewLogLines -Path $stderrPath -Offset ([ref]$stderrOffset) -Collector $collector

        $exitCode = [int]$process.ExitCode
        $elapsed = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
        Write-Host "COMMAND_EXIT=$exitCode ELAPSED_SEC=$elapsed ARGS=$($Arguments -join ' ')"

        [pscustomobject]@{
            ExitCode = $exitCode
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

$originalRespectGitignore = $null
$restoreRespectGitignore = $false

Push-Location $Repo
try {
    Write-Host '=== REGRESSION PREFLIGHT ==='
    $trackedDocs = @(& git -C $Repo ls-files -- 'README.md' 'docs/*.md')
    if ($LASTEXITCODE -ne 0) { throw "GIT_LS_FILES_FAILED=$LASTEXITCODE" }
    Write-Host "TRACKED_KB_DOCS=$($trackedDocs.Count)"
    $trackedDocs | ForEach-Object { Write-Host "TRACKED_KB_DOC=$_" }
    if ($trackedDocs.Count -eq 0) { throw 'TRACKED_KB_DOCS_MISSING' }

    $configGet = Invoke-MvsStreaming -Arguments @('config','get','respect_gitignore') -TimeoutSeconds 60
    if ($configGet.ExitCode -ne 0) { throw "CONFIG_GET_RESPECT_GITIGNORE_FAILED=$($configGet.ExitCode)" }
    if ($configGet.Output -match '(?i)respect_gitignore\s*:\s*(True|False)') {
        $originalRespectGitignore = $Matches[1].ToLowerInvariant()
    }
    else {
        throw 'CONFIG_GET_RESPECT_GITIGNORE_UNPARSEABLE'
    }

    # Regression must validate the tracked KB corpus independently of a local,
    # untracked .gitignore. Restore the user's project setting in finally.
    if ($originalRespectGitignore -ne 'false') {
        $configSet = Invoke-MvsStreaming -Arguments @('config','set','respect_gitignore','false') -TimeoutSeconds 60
        if ($configSet.ExitCode -ne 0) { throw "CONFIG_SET_RESPECT_GITIGNORE_FAILED=$($configSet.ExitCode)" }
        $restoreRespectGitignore = $true
    }

    Write-Host '=== INDEX REGRESSION ==='
    $indexResult = Invoke-MvsStreaming -Arguments @('index','--force') -TimeoutSeconds 600
    if ($indexResult.ExitCode -ne 0) { throw "INDEX_FAILED=$($indexResult.ExitCode)" }
    if ($indexResult.Output -notmatch 'Reindex complete:') { throw 'INDEX_COMPLETION_MARKER_MISSING' }
    if ($indexResult.Output -match 'Reindex complete:\s*0 files,\s*0 chunks') { throw 'INDEX_ZERO_CORPUS' }
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
    if ($restoreRespectGitignore -and $null -ne $originalRespectGitignore) {
        try {
            $restoreResult = Invoke-MvsStreaming -Arguments @('config','set','respect_gitignore',$originalRespectGitignore) -TimeoutSeconds 60
            if ($restoreResult.ExitCode -ne 0) {
                Write-Warning "RESPECT_GITIGNORE_RESTORE_FAILED=$($restoreResult.ExitCode)"
            }
            else {
                Write-Host "RESPECT_GITIGNORE_RESTORED=$originalRespectGitignore"
            }
        }
        catch {
            Write-Warning "RESPECT_GITIGNORE_RESTORE_EXCEPTION=$($_.Exception.Message)"
        }
    }
    Pop-Location
}
