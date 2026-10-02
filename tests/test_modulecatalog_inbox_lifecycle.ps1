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
    $manifest = [ordered]@{ schema_version=1; format='gace.reusable-asset.v1'; catalog=[ordered]@{ repository='seigo-gace/modular-catalog'; commit=$Commit } }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $Directory 'manifest.json'), ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $encoding)
}

try {
    New-Item -ItemType Directory -Path $RepoScripts,$Ready,$Processing,$Processed,$Failed -Force | Out-Null

    $receiver = @'
param([string]$Root,[string]$Python,[string]$DeliveryRoot)
$ErrorActionPreference = 'Stop'
$leaf = Split-Path $DeliveryRoot -Leaf
Write-Host "FIXTURE_RECEIVER_START DELIVERY=$DeliveryRoot"
if ($leaf -like 'fail-*') { throw 'FIXTURE_RECEIVER_FAILURE' }
if ($leaf -eq 'busy-once') {
    $busySeen = Join-Path $DeliveryRoot '.busy-seen'
    if (-not (Test-Path $busySeen)) {
        Set-Content -Path $busySeen -Value 'seen'
        throw 'MODULECATALOG_RECEIVER_BUSY=fixture'
    }
}
$manifest = Get-Content (Join-Path $DeliveryRoot 'manifest.json') -Raw | ConvertFrom-Json
$commit = [string]$manifest.catalog.commit
$receiptRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog\receipts'
New-Item -ItemType Directory -Path $receiptRoot -Force | Out-Null
$receipt = [ordered]@{ status='ACTIVE'; catalogCommit=$commit; assetCount=1; knowledgeUnitCount=1 }
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $receiptRoot "$commit.json"), ($receipt | ConvertTo-Json) + [Environment]::NewLine, $encoding)
if ($leaf -eq 'archive-race') {
    $raceSeen = Join-Path $DeliveryRoot '.archive-race-seen'
    if (-not (Test-Path $raceSeen)) {
        Set-Content -Path $raceSeen -Value 'seen'
        $processedRoot = Join-Path $Root 'data\knowledge-inbox\modulecatalog\processed'
        New-Item -ItemType Directory -Path $processedRoot -Force | Out-Null
        Set-Content -Path (Join-Path $processedRoot $leaf) -Value 'collision'
    }
}
Write-Host "FIXTURE_RECEIVER_PASS COMMIT=$commit"
'@
    [System.IO.File]::WriteAllText((Join-Path $RepoScripts 'receive-modulecatalog-kbdata-windows.ps1'), $receiver, (New-Object System.Text.UTF8Encoding($false)))

    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "EMPTY_INBOX_FAILED=$LASTEXITCODE" }

    $ProcessorLockPath = Join-Path $InboxBase 'processor.lock'
    $heldProcessorLock = [System.IO.File]::Open($ProcessorLockPath,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    try {
        $busyOutput = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready 2>&1)
        $busyCode = $LASTEXITCODE
        if ($busyCode -eq 0) { throw 'PROCESSOR_BUSY_GATE_DID_NOT_FAIL' }
        if (($busyOutput -join "`n") -notmatch 'MODULECATALOG_INBOX_PROCESSOR_BUSY') { throw "PROCESSOR_BUSY_WRONG_FAILURE=$($busyOutput -join ' | ')" }
        if (-not (Test-Path $ProcessorLockPath)) { throw 'PROCESSOR_FOREIGN_LOCK_WAS_REMOVED' }
    }
    finally { $heldProcessorLock.Dispose(); Remove-Item $ProcessorLockPath -Force -ErrorAction SilentlyContinue }

    $Incomplete = Join-Path $Ready 'incomplete'
    New-Item -ItemType Directory -Path $Incomplete -Force | Out-Null
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "INCOMPLETE_INBOX_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path $Incomplete)) { throw 'INCOMPLETE_DELIVERY_WAS_CONSUMED' }

    Write-Manifest -Directory (Join-Path $Ready 'delivery-a') -Commit ('a' * 40)
    Write-Manifest -Directory (Join-Path $Ready 'delivery-b') -Commit ('b' * 40)
    $output = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready 2>&1)
    if ($LASTEXITCODE -eq 0) { throw 'MULTIPLE_READY_GATE_DID_NOT_FAIL' }
    if (($output -join "`n") -notmatch 'MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY') { throw "MULTIPLE_READY_WRONG_FAILURE=$($output -join ' | ')" }
    Remove-Item (Join-Path $Ready 'delivery-a'),(Join-Path $Ready 'delivery-b') -Recurse -Force

    $ResumeCommit = 'c' * 40
    $ResumeProcessing = Join-Path $Processing 'resume-a'
    Write-Manifest -Directory $ResumeProcessing -Commit $ResumeCommit
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "PROCESSING_RESUME_FAILED=$LASTEXITCODE" }
    $ResumeProcessed = Join-Path $Processed 'resume-a'
    if (Test-Path $ResumeProcessing) { throw 'RESUMED_DELIVERY_STILL_PROCESSING' }
    if (-not (Test-Path (Join-Path $ResumeProcessed 'kb-active-receipt.json'))) { throw 'RESUMED_ACTIVE_RECEIPT_ARCHIVE_MISSING' }
    $successStdout = @(Get-ChildItem $ResumeProcessed -File -Filter 'kb-receiver-*.stdout.log')
    $successStderr = @(Get-ChildItem $ResumeProcessed -File -Filter 'kb-receiver-*.stderr.log')
    if ($successStdout.Count -ne 1 -or $successStderr.Count -ne 1) { throw "RESUMED_RECEIVER_LOG_COUNT_INVALID stdout=$($successStdout.Count) stderr=$($successStderr.Count)" }
    if ((Get-Content $successStdout[0].FullName -Raw) -notmatch 'FIXTURE_RECEIVER_PASS') { throw 'RESUMED_RECEIVER_STDOUT_EVIDENCE_MISSING' }

    # Busy is transient: keep the claim in processing and retry it instead of
    # falsely archiving a valid delivery as FAILED.
    $BusyCommit = 'e' * 40
    $BusyReady = Join-Path $Ready 'busy-once'
    Write-Manifest -Directory $BusyReady -Commit $BusyCommit
    $busyAttempt = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready 2>&1)
    if ($LASTEXITCODE -eq 0) { throw 'BUSY_ONCE_FIRST_ATTEMPT_FALSE_PASS' }
    $BusyProcessing = Join-Path $Processing 'busy-once'
    if (-not (Test-Path $BusyProcessing)) { throw 'BUSY_ONCE_NOT_LEFT_PROCESSING' }
    if (-not (Test-Path (Join-Path $BusyProcessing 'kb-retryable.json'))) { throw 'BUSY_ONCE_RETRYABLE_EVIDENCE_MISSING' }
    if (@(Get-ChildItem $Failed -Directory -Filter 'busy-once-*').Count -ne 0) { throw 'BUSY_ONCE_WRONGLY_FAILED' }
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "BUSY_ONCE_RETRY_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path (Join-Path $Processed 'busy-once\kb-active-receipt.json'))) { throw 'BUSY_ONCE_NOT_PROCESSED_AFTER_RETRY' }

    # If ACTIVE is already established but the archive move fails, preserve the
    # delivery in processing as ACTIVE_ARCHIVE_PENDING. It must never be relabeled
    # FAILED because the KB runtime is already active.
    $ArchiveCommit = 'f' * 40
    $ArchiveReady = Join-Path $Ready 'archive-race'
    Write-Manifest -Directory $ArchiveReady -Commit $ArchiveCommit
    $archiveAttempt = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready 2>&1)
    if ($LASTEXITCODE -eq 0) { throw 'ARCHIVE_RACE_FIRST_ATTEMPT_FALSE_PASS' }
    $ArchiveProcessing = Join-Path $Processing 'archive-race'
    if (-not (Test-Path $ArchiveProcessing)) { throw 'ARCHIVE_RACE_NOT_LEFT_PROCESSING' }
    if (-not (Test-Path (Join-Path $ArchiveProcessing 'kb-active-receipt.json')) -or -not (Test-Path (Join-Path $ArchiveProcessing 'kb-archive-pending.json'))) { throw 'ARCHIVE_RACE_ACTIVE_EVIDENCE_MISSING' }
    if (@(Get-ChildItem $Failed -Directory -Filter 'archive-race-*').Count -ne 0) { throw 'ARCHIVE_RACE_WRONGLY_FAILED' }
    Remove-Item (Join-Path $Processed 'archive-race') -Force
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "ARCHIVE_RACE_RECOVERY_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path (Join-Path $Processed 'archive-race\kb-active-receipt.json'))) { throw 'ARCHIVE_RACE_NOT_PROCESSED_AFTER_RECOVERY' }

    $FailCommit = 'd' * 40
    $FailProcessing = Join-Path $Processing 'fail-resume'
    Write-Manifest -Directory $FailProcessing -Commit $FailCommit
    $failureOutput = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready 2>&1)
    if ($LASTEXITCODE -eq 0) { throw 'FAILED_RESUME_DID_NOT_FAIL' }
    $FailedArchives = @(Get-ChildItem $Failed -Directory -Filter 'fail-resume-*')
    if ($FailedArchives.Count -ne 1) { throw "FAILED_ARCHIVE_COUNT_INVALID=$($FailedArchives.Count)" }
    $failureJsonPath = Join-Path $FailedArchives[0].FullName 'kb-failure.json'
    if (-not (Test-Path $failureJsonPath)) { throw 'FAILED_ARCHIVE_EVIDENCE_MISSING' }
    $failureData = Get-Content $failureJsonPath -Raw | ConvertFrom-Json
    $failedStdout = Join-Path $FailedArchives[0].FullName ([string]$failureData.receiverStdoutLog)
    $failedStderr = Join-Path $FailedArchives[0].FullName ([string]$failureData.receiverStderrLog)
    if (-not (Test-Path $failedStdout) -or -not (Test-Path $failedStderr)) { throw 'FAILED_RECEIVER_LOG_FILE_MISSING' }
    if ((Get-Content $failedStderr -Raw) -notmatch 'FIXTURE_RECEIVER_FAILURE') { throw 'FAILED_RECEIVER_STDERR_EVIDENCE_MISSING' }

    if (Test-Path (Join-Path $InboxBase 'processor.lock')) { throw 'PROCESSOR_LOCK_NOT_RELEASED' }
    Write-Host 'GACE_MODULECATALOG_INBOX_LIFECYCLE=PASS RETRYABLE=PASS ACTIVE_ARCHIVE_RECOVERY=PASS RECEIVER_DIAGNOSTICS=PASS PROCESSOR_LOCK=PASS'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
