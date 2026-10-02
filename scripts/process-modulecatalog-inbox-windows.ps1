param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$InboxRoot = '',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe'
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Receiver = Join-Path $Repo 'scripts\receive-modulecatalog-kbdata-windows.ps1'
if (-not (Test-Path $Receiver)) { throw "RECEIVER_MISSING=$Receiver" }

$InboxBase = Join-Path $Root 'data\knowledge-inbox\modulecatalog'
if (-not $InboxRoot) { $InboxRoot = Join-Path $InboxBase 'ready' }
$ProcessingRoot = Join-Path $InboxBase 'processing'
$ProcessedRoot = Join-Path $InboxBase 'processed'
$FailedRoot = Join-Path $InboxBase 'failed'
foreach ($path in @($InboxRoot,$ProcessingRoot,$ProcessedRoot,$FailedRoot)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}

$AllReady = @(Get-ChildItem $InboxRoot -Directory | Sort-Object Name)
$Deliveries = @($AllReady | Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') })
$Incomplete = @($AllReady | Where-Object { -not (Test-Path (Join-Path $_.FullName 'manifest.json')) })
foreach ($item in $Incomplete) {
    Write-Host "GACE_MODULECATALOG_INBOX_PENDING=NO_MANIFEST DELIVERY=$($item.FullName)"
}

if ($Deliveries.Count -eq 0) {
    Write-Host "GACE_MODULECATALOG_INBOX=PASS READY=0 PENDING=$($Incomplete.Count) ROOT=$InboxRoot"
    exit 0
}

# The active KB is a single-current-snapshot runtime. Without an ordering field in
# the producer manifest, processing multiple different ready snapshots would make
# the final active version depend on directory ordering. Refuse that ambiguity.
if ($Deliveries.Count -gt 1) {
    $names = ($Deliveries | ForEach-Object { $_.Name }) -join ','
    throw "MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY=$names"
}

$delivery = $Deliveries[0]
$processingPath = Join-Path $ProcessingRoot $delivery.Name
$processedPath = Join-Path $ProcessedRoot $delivery.Name
if (Test-Path $processingPath) { throw "PROCESSING_DELIVERY_ALREADY_EXISTS=$processingPath" }
if (Test-Path $processedPath) { throw "PROCESSED_DELIVERY_ALREADY_EXISTS=$processedPath" }

Write-Host "=== CLAIM DELIVERY: $($delivery.Name) ==="
Move-Item $delivery.FullName $processingPath

try {
    Write-Host "=== PROCESS DELIVERY: $($delivery.Name) ==="
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Receiver -Root $Root -Python $Python -DeliveryRoot $processingPath
    if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_INBOX_DELIVERY_FAILED=$processingPath:$LASTEXITCODE" }

    $manifest = Get-Content (Join-Path $processingPath 'manifest.json') -Raw | ConvertFrom-Json
    $commit = [string]$manifest.catalog.commit
    if ($commit.Length -ne 40) { throw "PROCESSED_DELIVERY_COMMIT_INVALID=$commit" }
    $receipt = Join-Path $Root "data\knowledge-intake\modulecatalog\receipts\$commit.json"
    if (-not (Test-Path $receipt)) { throw "ACTIVE_RECEIPT_MISSING=$receipt" }
    $receiptData = Get-Content $receipt -Raw | ConvertFrom-Json
    if ([string]$receiptData.status -ne 'ACTIVE') { throw "ACTIVE_RECEIPT_STATUS_INVALID=$($receiptData.status)" }
    if ([string]$receiptData.catalogCommit -ne $commit) { throw "ACTIVE_RECEIPT_COMMIT_MISMATCH=$($receiptData.catalogCommit)" }

    Move-Item $processingPath $processedPath
    Write-Host "GACE_MODULECATALOG_INBOX=PASS READY=1 PROCESSED=1 STATUS=ACTIVE COMMIT=$commit ARCHIVE=$processedPath"
}
catch {
    $failure = $_
    if (Test-Path $processingPath) {
        $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $failedPath = Join-Path $FailedRoot "$($delivery.Name)-$timestamp"
        Move-Item $processingPath $failedPath -ErrorAction SilentlyContinue
        Write-Host "GACE_MODULECATALOG_INBOX=FAILED ARCHIVE=$failedPath"
    }
    throw $failure
}
