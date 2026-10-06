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
$HealthCheck = Join-Path $Repo 'scripts\check-modulecatalog-kb-runtime-windows.ps1'
$ManifestPath = Join-Path $DeliveryRoot 'manifest.json'
foreach ($path in @($Repo,$Python,$Acceptor,$Activator,$Recovery,$HealthCheck,$DeliveryRoot,$ManifestPath)) {
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
$ReceiverExitCode = 0
$ReceiverFailure = $null
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
        if (-not (Test-Path $ActivationMarker)) { throw "ACTIVE_RECEIPT_WITHOUT_CURRENT_MARKER=$ReceiptPath" }
        $Current = Get-Content $ActivationMarker -Raw | ConvertFrom-Json
        if ([string]$Current.status -ne 'ACTIVE') { throw "CURRENT_MARKER_STATUS_INVALID=$($Current.status)" }
        if ([string]$Current.catalogCommit -ne $CatalogCommit) {
            throw "PREVIOUSLY_ACTIVE_DELIVERY_IS_NOT_CURRENT incoming=$CatalogCommit current=$($Current.catalogCommit)"
        }
        if (Test-Path $ActivationJournal) { throw "ACTIVE_WITH_UNRESOLVED_JOURNAL=$ActivationJournal" }

        # ACTIVE is an operational claim, not a cached receipt. Re-check the real
        # current runtime under the receiver's already-held lock before accepting
        # a replay as idempotent success.
        Write-Host '=== KB RECEIVE: REVERIFY CURRENT ACTIVE RUNTIME ==='
        & $PowerShellHost -NoProfile -ExecutionPolicy Bypass -File $HealthCheck -Root $Root -Deep -AssumeReceiveLockHeld
        if ($LASTEXITCODE -ne 0) { throw "IDEMPOTENT_ACTIVE_RUNTIME_UNHEALTHY=$LASTEXITCODE" }
        Write-Host "GACE_MODULECATALOG_RECEIVE=PASS IDEMPOTENT=YES STATUS=ACTIVE HEALTH=DEEP COMMIT=$CatalogCommit"
        Write-Host "RECEIPT=$ReceiptPath"
        return
    }
    if ([string]$Receipt.status -ne 'ACCEPTED') { throw "DELIVERY_RECEIPT_STATUS_INVALID=$($Receipt.status)" }

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

    # Activation already performs post-cutover MCP verification. Run the complete
    # non-mutating health gate once more on the final current authority so receipt
    # success and health-check success have exactly the same boundary.
    & $PowerShellHost -NoProfile -ExecutionPolicy Bypass -File $HealthCheck -Root $Root -AssumeReceiveLockHeld
    if ($LASTEXITCODE -ne 0) { throw "FINAL_ACTIVE_RUNTIME_HEALTH_FAILED=$LASTEXITCODE" }
    Write-Host "GACE_MODULECATALOG_RECEIVE=PASS STATUS=ACTIVE HEALTH=PASS COMMIT=$CatalogCommit ASSETS=$($FinalReceipt.assetCount) RECORDS=$($FinalReceipt.knowledgeUnitCount)"
    Write-Host "RECEIPT=$ReceiptPath"
}
catch {
    $ReceiverExitCode = 1
    $ReceiverFailure = $_
}
finally {
    if ($null -ne $LockStream) { $LockStream.Dispose(); $LockStream = $null }
    if ($OwnsReceiveLock) { Remove-Item $LockPath -Force -ErrorAction SilentlyContinue }
}
if ($ReceiverExitCode -ne 0) {
    Write-Error -ErrorRecord $ReceiverFailure
    exit $ReceiverExitCode
}
