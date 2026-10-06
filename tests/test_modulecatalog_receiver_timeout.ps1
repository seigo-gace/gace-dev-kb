$ErrorActionPreference = 'Stop'

$Processor = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\process-modulecatalog-inbox-windows.ps1')).Path
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-receiver-timeout-" + [Guid]::NewGuid().ToString('N'))
$RepoScripts = Join-Path $Root 'repo\scripts'
$InboxBase = Join-Path $Root 'data\knowledge-inbox\modulecatalog'
$Ready = Join-Path $InboxBase 'ready'
$Processing = Join-Path $InboxBase 'processing'
$Processed = Join-Path $InboxBase 'processed'
$Failed = Join-Path $InboxBase 'failed'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-JsonUtf8 {
    param([object]$Value,[string]$Path)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20) + [Environment]::NewLine, $Utf8)
}

function Write-MinimalManifest {
    param([string]$Directory,[string]$Commit)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    # Invalid cardinality is deliberately claimable by transport preflight; the
    # fixture receiver, not production admission, owns this isolated timeout test.
    $manifest = [ordered]@{
        schema_version = 1
        format = 'gace.reusable-asset.v1'
        catalog = [ordered]@{ repository='seigo-gace/modular-catalog'; commit=$Commit }
    }
    Write-JsonUtf8 -Value $manifest -Path (Join-Path $Directory 'manifest.json')
}

function Write-Receiver {
    param([bool]$Slow)
    $sleepLine = if ($Slow) { 'Start-Sleep -Seconds 5' } else { '' }
    $body = @"
param([string]`$Root,[string]`$Python,[string]`$DeliveryRoot)
`$ErrorActionPreference = 'Stop'
$sleepLine
`$manifest = Get-Content (Join-Path `$DeliveryRoot 'manifest.json') -Raw | ConvertFrom-Json
`$commit = [string]`$manifest.catalog.commit
`$receiptRoot = Join-Path `$Root 'data\knowledge-intake\modulecatalog\receipts'
New-Item -ItemType Directory -Path `$receiptRoot -Force | Out-Null
`$receipt = [ordered]@{ status='ACTIVE'; catalogCommit=`$commit; assetCount=1; knowledgeUnitCount=1 }
`$encoding = New-Object System.Text.UTF8Encoding(`$false)
[System.IO.File]::WriteAllText((Join-Path `$receiptRoot "`$commit.json"), (`$receipt | ConvertTo-Json) + [Environment]::NewLine, `$encoding)
Write-Host "FIXTURE_RECEIVER_PASS COMMIT=`$commit"
"@
    [System.IO.File]::WriteAllText((Join-Path $RepoScripts 'receive-modulecatalog-kbdata-windows.ps1'), $body, $Utf8)
}

try {
    New-Item -ItemType Directory -Path $RepoScripts,$Ready,$Processing,$Processed,$Failed -Force | Out-Null
    $commit = '7' * 40
    Write-MinimalManifest -Directory (Join-Path $Ready 'timeout-retry') -Commit $commit
    Write-Receiver -Slow $true

    $first = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready -ReceiverTimeoutSeconds 1 2>&1)
    $firstCode = $LASTEXITCODE
    if ($firstCode -eq 0) { throw 'RECEIVER_TIMEOUT_FALSE_PASS' }
    $processingDelivery = Join-Path $Processing 'timeout-retry'
    if (-not (Test-Path $processingDelivery)) { throw 'TIMED_OUT_DELIVERY_NOT_LEFT_PROCESSING' }
    $retryable = Join-Path $processingDelivery 'kb-retryable.json'
    if (-not (Test-Path $retryable)) { throw 'TIMED_OUT_DELIVERY_RETRYABLE_MARKER_MISSING' }
    $retryData = Get-Content $retryable -Raw | ConvertFrom-Json
    if ([string]$retryData.status -ne 'RETRYABLE') { throw "TIMED_OUT_STATUS_INVALID=$($retryData.status)" }
    if ([string]$retryData.error -notmatch 'MODULECATALOG_RECEIVER_TIMEOUT=1s') { throw "TIMED_OUT_REASON_INVALID=$($retryData.error)" }
    if (@(Get-ChildItem $Failed -Directory).Count -ne 0) { throw 'TIMED_OUT_DELIVERY_WRONGLY_FAILED' }

    Write-Receiver -Slow $false
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready -ReceiverTimeoutSeconds 5
    if ($LASTEXITCODE -ne 0) { throw "RECEIVER_TIMEOUT_RETRY_FAILED=$LASTEXITCODE" }
    if (Test-Path $processingDelivery) { throw 'RETRIED_DELIVERY_STILL_PROCESSING' }
    if (-not (Test-Path (Join-Path $Processed 'timeout-retry\kb-active-receipt.json'))) { throw 'RETRIED_DELIVERY_NOT_PROCESSED' }

    Write-Host 'GACE_MODULECATALOG_RECEIVER_TIMEOUT=PASS TIMEOUT_RETRYABLE=PASS RESUME=PASS'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
