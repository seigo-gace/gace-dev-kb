$ErrorActionPreference = 'Stop'

$Processor = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\process-modulecatalog-inbox-windows.ps1')).Path
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-inbox-test-" + [Guid]::NewGuid().ToString('N'))
$RepoScripts = Join-Path $Root 'repo\scripts'
$InboxBase = Join-Path $Root 'data\knowledge-inbox\modulecatalog'
$Ready = Join-Path $InboxBase 'ready'
$Processing = Join-Path $InboxBase 'processing'
$Processed = Join-Path $InboxBase 'processed'
$Failed = Join-Path $InboxBase 'failed'

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

    # Fixture receiver: successful deliveries emit ACTIVE; fail-* deliberately fail.
    $receiver = @'
param(
    [string]$Root,
    [string]$Python,
    [string]$DeliveryRoot
)
$ErrorActionPreference = 'Stop'
Write-Host "FIXTURE_RECEIVER_START DELIVERY=$DeliveryRoot"
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
Write-Host "FIXTURE_RECEIVER_PASS COMMIT=$commit"
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
    $successStdout = @(Get-ChildItem $ResumeProcessed -File -Filter 'kb-receiver-*.stdout.log')
    $successStderr = @(Get-ChildItem $ResumeProcessed -File -Filter 'kb-receiver-*.stderr.log')
    if ($successStdout.Count -ne 1 -or $successStderr.Count -ne 1) {
        throw "RESUMED_RECEIVER_LOG_COUNT_INVALID stdout=$($successStdout.Count) stderr=$($successStderr.Count)"
    }
    if ((Get-Content $successStdout[0].FullName -Raw) -notmatch 'FIXTURE_RECEIVER_PASS') {
        throw 'RESUMED_RECEIVER_STDOUT_EVIDENCE_MISSING'
    }

    # A failed resumed delivery is preserved with machine-readable failure evidence
    # and the exact child-process stdout/stderr from the failed receiver attempt.
    $FailCommit = 'd' * 40
    $FailProcessing = Join-Path $Processing 'fail-resume'
    Write-Manifest -Directory $FailProcessing -Commit $FailCommit
    $failureOutput = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready 2>&1)
    $failureCode = $LASTEXITCODE
    if ($failureCode -eq 0) { throw 'FAILED_RESUME_DID_NOT_FAIL' }
    $FailedArchives = @(Get-ChildItem $Failed -Directory -Filter 'fail-resume-*')
    if ($FailedArchives.Count -ne 1) { throw "FAILED_ARCHIVE_COUNT_INVALID=$($FailedArchives.Count)" }
    $failureJsonPath = Join-Path $FailedArchives[0].FullName 'kb-failure.json'
    if (-not (Test-Path $failureJsonPath)) { throw 'FAILED_ARCHIVE_EVIDENCE_MISSING' }
    $failureData = Get-Content $failureJsonPath -Raw | ConvertFrom-Json
    if (-not [string]$failureData.receiverStdoutLog -or -not [string]$failureData.receiverStderrLog) {
        throw 'FAILED_RECEIVER_LOG_REFERENCE_MISSING'
    }
    $failedStdout = Join-Path $FailedArchives[0].FullName ([string]$failureData.receiverStdoutLog)
    $failedStderr = Join-Path $FailedArchives[0].FullName ([string]$failureData.receiverStderrLog)
    if (-not (Test-Path $failedStdout) -or -not (Test-Path $failedStderr)) {
        throw 'FAILED_RECEIVER_LOG_FILE_MISSING'
    }
    if ((Get-Content $failedStderr -Raw) -notmatch 'FIXTURE_RECEIVER_FAILURE') {
        throw 'FAILED_RECEIVER_STDERR_EVIDENCE_MISSING'
    }

    if (Test-Path (Join-Path $InboxBase 'processor.lock')) {
        throw 'PROCESSOR_LOCK_NOT_RELEASED'
    }

    Write-Host 'GACE_MODULECATALOG_INBOX_LIFECYCLE=PASS RECEIVER_DIAGNOSTICS=PASS'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
