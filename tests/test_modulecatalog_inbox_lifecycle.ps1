$ErrorActionPreference = 'Stop'

$Processor = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\process-modulecatalog-inbox-windows.ps1')).Path
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-inbox-test-" + [Guid]::NewGuid().ToString('N'))
$RepoScripts = Join-Path $Root 'repo\scripts'
$InboxBase = Join-Path $Root 'data\knowledge-inbox\modulecatalog'
$Ready = Join-Path $InboxBase 'ready'
$Processing = Join-Path $InboxBase 'processing'
$Processed = Join-Path $InboxBase 'processed'
$Failed = Join-Path $InboxBase 'failed'
$OriginalPath = $env:PATH

function Write-Manifest {
    param([string]$Directory,[string]$Commit)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $manifest = [ordered]@{
        schema_version = 1
        format = 'gace.reusable-asset.v1'
        catalog = [ordered]@{
            repository = 'seigo-gace/modular-catalog'
            commit = $Commit
        }
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        (Join-Path $Directory 'manifest.json'),
        ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine,
        $encoding
    )
}

try {
    New-Item -ItemType Directory -Path $RepoScripts,$Ready,$Processing,$Processed,$Failed -Force | Out-Null

    # The production processor launches Windows PowerShell. GitHub's Linux runner
    # has pwsh instead, so provide a test-only compatibility shim.
    if (-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $ShimDir = Join-Path $Root 'shim'
        New-Item -ItemType Directory -Path $ShimDir -Force | Out-Null
        $Shim = Join-Path $ShimDir 'powershell.exe'
        $shimText = @'
#!/usr/bin/env bash
exec pwsh "$@"
'@
        [System.IO.File]::WriteAllText($Shim, $shimText, (New-Object System.Text.UTF8Encoding($false)))
        & chmod +x $Shim
        if ($LASTEXITCODE -ne 0) { throw "POWERSHELL_SHIM_CHMOD_FAILED=$LASTEXITCODE" }
        $env:PATH = "$ShimDir$([System.IO.Path]::PathSeparator)$env:PATH"
    }

    # Fixture receiver: successful deliveries emit ACTIVE; fail-* deliberately fail.
    $receiver = @'
param(
    [string]$Root,
    [string]$Python,
    [string]$DeliveryRoot
)
$ErrorActionPreference = 'Stop'
if ((Split-Path $DeliveryRoot -Leaf) -like 'fail-*') {
    throw 'FIXTURE_RECEIVER_FAILURE'
}
$manifest = Get-Content (Join-Path $DeliveryRoot 'manifest.json') -Raw | ConvertFrom-Json
$commit = [string]$manifest.catalog.commit
$receiptRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog\receipts'
New-Item -ItemType Directory -Path $receiptRoot -Force | Out-Null
$receipt = [ordered]@{ status='ACTIVE'; catalogCommit=$commit; assetCount=1; knowledgeUnitCount=1 }
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $receiptRoot "$commit.json"), ($receipt | ConvertTo-Json) + [Environment]::NewLine, $encoding)
'@
    [System.IO.File]::WriteAllText(
        (Join-Path $RepoScripts 'receive-modulecatalog-kbdata-windows.ps1'),
        $receiver,
        (New-Object System.Text.UTF8Encoding($false))
    )

    # Empty inbox is healthy.
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "EMPTY_INBOX_FAILED=$LASTEXITCODE" }

    # Incomplete transport is left pending, not claimed.
    $Incomplete = Join-Path $Ready 'incomplete'
    New-Item -ItemType Directory -Path $Incomplete -Force | Out-Null
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "INCOMPLETE_INBOX_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path $Incomplete)) { throw 'INCOMPLETE_DELIVERY_WAS_CONSUMED' }

    # Multiple complete ready deliveries are ambiguous without ordering authority.
    Write-Manifest -Directory (Join-Path $Ready 'delivery-a') -Commit ('a' * 40)
    Write-Manifest -Directory (Join-Path $Ready 'delivery-b') -Commit ('b' * 40)
    $output = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready 2>&1)
    $code = $LASTEXITCODE
    if ($code -eq 0) { throw 'MULTIPLE_READY_GATE_DID_NOT_FAIL' }
    if (($output -join "`n") -notmatch 'MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY') {
        throw "MULTIPLE_READY_WRONG_FAILURE=$($output -join ' | ')"
    }
    Remove-Item (Join-Path $Ready 'delivery-a'),(Join-Path $Ready 'delivery-b') -Recurse -Force

    # A delivery left in processing by an interrupted prior process is resumed.
    $ResumeCommit = 'c' * 40
    $ResumeProcessing = Join-Path $Processing 'resume-a'
    Write-Manifest -Directory $ResumeProcessing -Commit $ResumeCommit
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "PROCESSING_RESUME_FAILED=$LASTEXITCODE" }
    $ResumeProcessed = Join-Path $Processed 'resume-a'
    if (Test-Path $ResumeProcessing) { throw 'RESUMED_DELIVERY_STILL_PROCESSING' }
    if (-not (Test-Path $ResumeProcessed)) { throw 'RESUMED_DELIVERY_NOT_PROCESSED' }
    if (-not (Test-Path (Join-Path $ResumeProcessed 'kb-active-receipt.json'))) {
        throw 'RESUMED_ACTIVE_RECEIPT_ARCHIVE_MISSING'
    }

    # A failed resumed delivery is preserved with machine-readable failure evidence.
    $FailCommit = 'd' * 40
    $FailProcessing = Join-Path $Processing 'fail-resume'
    Write-Manifest -Directory $FailProcessing -Commit $FailCommit
    $failureOutput = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready 2>&1)
    $failureCode = $LASTEXITCODE
    if ($failureCode -eq 0) { throw 'FAILED_RESUME_DID_NOT_FAIL' }
    $FailedArchives = @(Get-ChildItem $Failed -Directory -Filter 'fail-resume-*')
    if ($FailedArchives.Count -ne 1) { throw "FAILED_ARCHIVE_COUNT_INVALID=$($FailedArchives.Count)" }
    if (-not (Test-Path (Join-Path $FailedArchives[0].FullName 'kb-failure.json'))) {
        throw 'FAILED_ARCHIVE_EVIDENCE_MISSING'
    }

    if (Test-Path (Join-Path $InboxBase 'processor.lock')) {
        throw 'PROCESSOR_LOCK_NOT_RELEASED'
    }

    Write-Host 'GACE_MODULECATALOG_INBOX_LIFECYCLE=PASS'
}
finally {
    $env:PATH = $OriginalPath
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
