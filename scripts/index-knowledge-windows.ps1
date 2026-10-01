param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [int]$MaxCount = 50
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$Mvs = Join-Path $Root 'runtime\mcp-vector-search\Scripts\mcp-vector-search.exe'
$ExportScript = Join-Path $Repo 'scripts\export-knowledge-windows.ps1'
$Renderer = Join-Path $Repo 'scripts\render_knowledge_corpus.py'
$BootstrapScript = Join-Path $Repo 'scripts\bootstrap-mvs-windows.ps1'
$VerifyScript = Join-Path $Repo 'tests\verify-mvs-windows.ps1'
$Jsonl = Join-Path $Root 'data\knowledge-records\gace-dev-kb.jsonl'
$SearchRoot = Join-Path $Root 'data\knowledge-search'
$Corpus = Join-Path $SearchRoot 'records'
$Config = Join-Path $SearchRoot '.mcp-vector-search\config.json'

foreach ($p in @($Python, $Repo, $Mvs, $ExportScript, $Renderer, $BootstrapScript, $VerifyScript)) {
    if (-not (Test-Path $p)) { throw "REQUIRED_PATH_MISSING=$p" }
}

function Invoke-MvsCapture {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [int]$TimeoutSeconds = 600
    )

    $tag = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $env:TEMP "gace-kb-mvs-$tag.stdout.log"
    $stderrPath = Join-Path $env:TEMP "gace-kb-mvs-$tag.stderr.log"
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
            -WorkingDirectory $WorkingDirectory `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        while (-not $process.HasExited) {
            if (((Get-Date) - $startedAt).TotalSeconds -ge $TimeoutSeconds) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                throw "MVS_TIMEOUT=${TimeoutSeconds}s ARGS=$($Arguments -join ' ')"
            }
            Start-Sleep -Milliseconds 500
            $process.Refresh()
        }

        $process.WaitForExit()
        $process.Refresh()
        $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { '' }
        $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { '' }
        $output = ($stdout + [Environment]::NewLine + $stderr).Trim()
        if ($output) { Write-Host $output }

        $exitCode = [int]$process.ExitCode
        $elapsed = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
        Write-Host "COMMAND_EXIT=$exitCode ELAPSED_SEC=$elapsed ARGS=$($Arguments -join ' ')"

        [pscustomobject]@{
            ExitCode = $exitCode
            Output   = $output
        }
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '=== VERIFY WINDOWS MVS COMPATIBILITY ==='
try {
    & $VerifyScript -Root $Root
}
catch {
    Write-Host "COMPAT_VERIFY_NEEDS_REPAIR=$($_.Exception.Message)"
    Write-Host '=== REPAIR WINDOWS MVS COMPATIBILITY ==='
    & $BootstrapScript -Root $Root -Python $Python
    Write-Host '=== REVERIFY WINDOWS MVS COMPATIBILITY ==='
    & $VerifyScript -Root $Root
}

Write-Host '=== EXPORT KNOWLEDGE ==='
& $ExportScript -Root $Root -Python $Python -MaxCount $MaxCount
if ($LASTEXITCODE -ne 0) { throw "KNOWLEDGE_EXPORT_FAILED=$LASTEXITCODE" }
if (-not (Test-Path $Jsonl)) { throw "KNOWLEDGE_JSONL_MISSING=$Jsonl" }

$recordCount = @(Get-Content $Jsonl | Where-Object { $_.Trim() }).Count
if ($recordCount -lt 1) { throw 'KNOWLEDGE_RECORD_COUNT_ZERO' }
Write-Host "KNOWLEDGE_RECORDS=$recordCount"

Write-Host '=== RENDER SEARCH CORPUS ==='
New-Item -ItemType Directory -Path $SearchRoot -Force | Out-Null
& $Python -B $Renderer --input $Jsonl --output-dir $Corpus
if ($LASTEXITCODE -ne 0) { throw "KNOWLEDGE_CORPUS_RENDER_FAILED=$LASTEXITCODE" }
$corpusCount = @(Get-ChildItem $Corpus -Filter '*.md' -File).Count
if ($corpusCount -ne $recordCount) {
    throw "KNOWLEDGE_CORPUS_COUNT_MISMATCH records=$recordCount corpus=$corpusCount"
}

if (-not (Test-Path $Config)) {
    Write-Host '=== INITIALIZE KNOWLEDGE SEARCH PROJECT ==='
    $initResult = Invoke-MvsCapture `
        -Arguments @('init','--force','--extensions','.md','--no-auto-index','--no-mcp','--no-auto-indexing') `
        -WorkingDirectory $SearchRoot `
        -TimeoutSeconds 180
    if ($initResult.ExitCode -ne 0) { throw "KNOWLEDGE_MVS_INIT_FAILED=$($initResult.ExitCode)" }
}

Write-Host '=== INDEX KNOWLEDGE CORPUS ==='
$indexResult = Invoke-MvsCapture -Arguments @('index','--force') -WorkingDirectory $SearchRoot -TimeoutSeconds 600
if ($indexResult.ExitCode -ne 0) { throw "KNOWLEDGE_MVS_INDEX_FAILED=$($indexResult.ExitCode)" }
if ($indexResult.Output -match "cannot find context for 'fork'") { throw 'WINDOWS_FORK_CONTEXT_ERROR_PRESENT' }
if ($indexResult.Output -notmatch 'Reindex complete:') { throw 'KNOWLEDGE_INDEX_COMPLETION_MARKER_MISSING' }
if ($indexResult.Output -match 'Reindex complete:\s*0 files,\s*0 chunks') { throw 'KNOWLEDGE_INDEX_ZERO_CORPUS' }

Write-Host '=== KNOWLEDGE SEARCH STATUS ==='
$statusResult = Invoke-MvsCapture -Arguments @('status') -WorkingDirectory $SearchRoot -TimeoutSeconds 120
if ($statusResult.ExitCode -ne 0) { throw "KNOWLEDGE_MVS_STATUS_FAILED=$($statusResult.ExitCode)" }
if ($statusResult.Output -notmatch "Indexed Files:\s+$recordCount/$recordCount") {
    throw "KNOWLEDGE_STATUS_COUNT_MISMATCH expected=$recordCount"
}

Write-Host '=== SEARCH WINDOWS KUZU FIX ==='
$kuzuResult = Invoke-MvsCapture `
    -Arguments @('search','normalize Windows paths Kuzu graph cleanup') `
    -WorkingDirectory $SearchRoot `
    -TimeoutSeconds 180
if ($kuzuResult.ExitCode -ne 0) { throw "KNOWLEDGE_SEARCH_KUZU_FAILED=$($kuzuResult.ExitCode)" }
if ($kuzuResult.Output -notmatch '74e8171') { throw 'KNOWLEDGE_SEARCH_KUZU_RECORD_MISSING' }

Write-Host '=== SEARCH G-ACE ADAPTER ==='
$adapterResult = Invoke-MvsCapture `
    -Arguments @('search','deterministic G-ACE repository knowledge adapter') `
    -WorkingDirectory $SearchRoot `
    -TimeoutSeconds 180
if ($adapterResult.ExitCode -ne 0) { throw "KNOWLEDGE_SEARCH_ADAPTER_FAILED=$($adapterResult.ExitCode)" }
if ($adapterResult.Output -notmatch '4912a442') { throw 'KNOWLEDGE_SEARCH_ADAPTER_RECORD_MISSING' }

Write-Host "GACE_KNOWLEDGE_INDEX=PASS RECORDS=$recordCount"
Write-Host "SEARCH_ROOT=$SearchRoot"
