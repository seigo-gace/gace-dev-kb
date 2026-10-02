param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [Parameter(Mandatory=$true)][string]$DeliveryRoot
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Acceptor = Join-Path $Repo 'scripts\accept_modulecatalog_delivery.py'
$Activator = Join-Path $Repo 'scripts\activate-modulecatalog-accepted-windows.ps1'
$Recovery = Join-Path $Repo 'scripts\recover-modulecatalog-activation-windows.ps1'
$ManifestPath = Join-Path $DeliveryRoot 'manifest.json'
foreach ($path in @($Repo,$Python,$Acceptor,$Activator,$Recovery,$DeliveryRoot,$ManifestPath)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}
$PowerShellHost = (Get-Process -Id $PID).Path
if (-not $PowerShellHost -or -not (Test-Path $PowerShellHost)) {
    throw "MODULECATALOG_RECEIVER_POWERSHELL_HOST_MISSING=$PowerShellHost"
}

$IntakeRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog'
$ActivationMarker = Join-Path $Root 'data\knowledge-records\modulecatalog-reusable-active.json'
$ActivationJournal = Join-Path $IntakeRoot 'activation-transaction.json'
New-Item -ItemType Directory -Path $IntakeRoot -Force | Out-Null
$LockPath = Join-Path $IntakeRoot 'receive.lock'
$LockStream = $null
$OwnsReceiveLock = $false
try {
    try {
        $LockStream = [System.IO.File]::Open(
            $LockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        $OwnsReceiveLock = $true
    }
    catch {
        throw "MODULECATALOG_RECEIVER_BUSY=$LockPath"
    }

    # Resolve any interrupted previous cutover before trusting receipts/markers.
    # This is intentionally before the idempotent ACTIVE shortcut.
    if (Test-Path $ActivationJournal) {
        Write-Host '=== KB RECEIVE: RECOVER INTERRUPTED ACTIVATION ==='
        & $Recovery -Root $Root -JournalPath $ActivationJournal
        if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_ACTIVATION_RECOVERY_FAILED=$LASTEXITCODE" }
        if (Test-Path $ActivationJournal) { throw "ACTIVATION_JOURNAL_STILL_PRESENT=$ActivationJournal" }
    }

    $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    if ([int]$Manifest.schema_version -ne 1 -or [string]$Manifest.format -ne 'gace.reusable-asset.v1') { throw 'DELIVERY_MANIFEST_FORMAT_UNSUPPORTED' }
    if ([string]$Manifest.catalog.repository -ne 'seigo-gace/modular-catalog') { throw "DELIVERY_CATALOG_REPOSITORY_MISMATCH=$($Manifest.catalog.repository)" }
    $CatalogCommit = [string]$Manifest.catalog.commit
    if ($CatalogCommit.Length -ne 40) { throw "DELIVERY_CATALOG_COMMIT_INVALID=$CatalogCommit" }

    $AcceptedRoot = Join-Path $IntakeRoot "accepted\$CatalogCommit"
    $ReceiptPath = Join-Path $IntakeRoot "receipts\$CatalogCommit.json"
    New-Item -ItemType Directory -Path (Split-Path $AcceptedRoot) -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path $ReceiptPath) -Force | Out-Null

    Write-Host '=== KB RECEIVE: VALIDATE + ACCEPT TRANSPORTED DATA ==='
    & $Python -B $Acceptor --delivery-root $DeliveryRoot --accepted-root $AcceptedRoot --receipt $ReceiptPath
    if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_DELIVERY_ACCEPT_FAILED=$LASTEXITCODE" }

    $Receipt = Get-Content $ReceiptPath -Raw | ConvertFrom-Json
    if ([string]$Receipt.status -eq 'ACTIVE') {
        if (-not (Test-Path $ActivationMarker)) {
            throw "ACTIVE_RECEIPT_WITHOUT_CURRENT_MARKER=$ReceiptPath"
        }
        $Current = Get-Content $ActivationMarker -Raw | ConvertFrom-Json
        if ([string]$Current.status -ne 'ACTIVE') {
            throw "CURRENT_MARKER_STATUS_INVALID=$($Current.status)"
        }
        if ([string]$Current.catalogCommit -ne $CatalogCommit) {
            throw "PREVIOUSLY_ACTIVE_DELIVERY_IS_NOT_CURRENT incoming=$CatalogCommit current=$($Current.catalogCommit)"
        }
        if (Test-Path $ActivationJournal) { throw "ACTIVE_WITH_UNRESOLVED_JOURNAL=$ActivationJournal" }
        Write-Host "GACE_MODULECATALOG_RECEIVE=PASS IDEMPOTENT=YES STATUS=ACTIVE COMMIT=$CatalogCommit"
        Write-Host "RECEIPT=$ReceiptPath"
        return
    }
    if ([string]$Receipt.status -ne 'ACCEPTED') { throw "DELIVERY_RECEIPT_STATUS_INVALID=$($Receipt.status)" }

    # Keep the accepted projection immutable after admission. Runtime filename/link
    # adaptation belongs to activation's staging copy, never to accepted authority.
    $AcceptedCorpus = Join-Path $AcceptedRoot 'projection\records'
    if (-not (Test-Path $AcceptedCorpus)) { throw "ACCEPTED_CORPUS_MISSING=$AcceptedCorpus" }

    Write-Host '=== KB OPERATE: INDEX + MCP + ATOMIC CURRENT SWITCH ==='
    & $PowerShellHost -NoProfile -ExecutionPolicy Bypass -File $Activator -Root $Root -AcceptedRoot $AcceptedRoot -ReceiptPath $ReceiptPath
    if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_DELIVERY_ACTIVATION_FAILED=$LASTEXITCODE" }

    $FinalReceipt = Get-Content $ReceiptPath -Raw | ConvertFrom-Json
    if ([string]$FinalReceipt.status -ne 'ACTIVE' -or [string]$FinalReceipt.catalogCommit -ne $CatalogCommit) { throw 'FINAL_RECEIPT_NOT_ACTIVE' }
    if (-not (Test-Path $ActivationMarker)) { throw "FINAL_CURRENT_MARKER_MISSING=$ActivationMarker" }
    $FinalCurrent = Get-Content $ActivationMarker -Raw | ConvertFrom-Json
    if ([string]$FinalCurrent.status -ne 'ACTIVE' -or [string]$FinalCurrent.catalogCommit -ne $CatalogCommit) { throw 'FINAL_CURRENT_MARKER_MISMATCH' }
    if (Test-Path $ActivationJournal) { throw "FINAL_ACTIVATION_JOURNAL_PRESENT=$ActivationJournal" }
    Write-Host "GACE_MODULECATALOG_RECEIVE=PASS STATUS=ACTIVE COMMIT=$CatalogCommit ASSETS=$($FinalReceipt.assetCount) RECORDS=$($FinalReceipt.knowledgeUnitCount)"
    Write-Host "RECEIPT=$ReceiptPath"
}
finally {
    if ($null -ne $LockStream) {
        $LockStream.Dispose()
        $LockStream = $null
    }
    if ($OwnsReceiveLock) {
        Remove-Item $LockPath -Force -ErrorAction SilentlyContinue
    }
}
