param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$JournalPath = ''
)

$ErrorActionPreference = 'Stop'
if (-not $JournalPath) {
    $JournalPath = Join-Path $Root 'data\knowledge-intake\modulecatalog\activation-transaction.json'
}
if (-not (Test-Path $JournalPath)) {
    Write-Host "GACE_MODULECATALOG_ACTIVATION_RECOVERY=PASS JOURNAL=NONE"
    return
}

function Read-JsonFile {
    param([string]$Path)
    return (Get-Content $Path -Raw | ConvertFrom-Json)
}

$Journal = Read-JsonFile $JournalPath
if ([int]$Journal.schemaVersion -ne 1 -or [string]$Journal.status -ne 'PREPARED') {
    throw "ACTIVATION_JOURNAL_INVALID=$JournalPath"
}
$TargetCommit = [string]$Journal.targetCommit
if ($TargetCommit.Length -ne 40) { throw "ACTIVATION_JOURNAL_TARGET_INVALID=$TargetCommit" }

$CurrentSearch = [string]$Journal.currentSearch
$BackupSearch = [string]$Journal.backupSearch
$FormalJsonl = [string]$Journal.formalJsonl
$BackupFormal = [string]$Journal.backupFormal
$CurrentReusable = [string]$Journal.currentReusable
$BackupReusable = [string]$Journal.backupReusable
$ActivationMarker = [string]$Journal.activationMarker
$BackupActivationMarker = [string]$Journal.backupActivationMarker
$ReceiptPath = [string]$Journal.receiptPath
$BackupReceipt = [string]$Journal.backupReceipt
$StagingSearch = [string]$Journal.stagingSearch
$StagingReusable = [string]$Journal.stagingReusable
$NextFormal = [string]$Journal.nextFormal
$HadCurrentReusable = [bool]$Journal.hadCurrentReusable
$HadActivationMarker = [bool]$Journal.hadActivationMarker

# If all three runtime authorities already agree on the target commit, the prior
# process died after the verified cutover had committed. Finalize instead of
# rolling a healthy current runtime backward.
$RuntimeState = Join-Path $CurrentReusable 'runtime-state.json'
$Committed = $false
if ((Test-Path $ActivationMarker) -and (Test-Path $ReceiptPath) -and (Test-Path $RuntimeState)) {
    try {
        $Marker = Read-JsonFile $ActivationMarker
        $Receipt = Read-JsonFile $ReceiptPath
        $State = Read-JsonFile $RuntimeState
        $Committed = (
            [string]$Marker.status -eq 'ACTIVE' -and
            [string]$Receipt.status -eq 'ACTIVE' -and
            [string]$State.status -eq 'ACTIVE' -and
            [string]$Marker.catalogCommit -eq $TargetCommit -and
            [string]$Receipt.catalogCommit -eq $TargetCommit -and
            [string]$State.catalogCommit -eq $TargetCommit
        )
    }
    catch {
        $Committed = $false
    }
}

if ($Committed) {
    Remove-Item $BackupActivationMarker,$BackupReceipt -Force -ErrorAction SilentlyContinue
    Remove-Item $JournalPath -Force
    Write-Host "GACE_MODULECATALOG_ACTIVATION_RECOVERY=PASS MODE=FINALIZE_COMMITTED COMMIT=$TargetCommit"
    return
}

# A non-committed journal means the previous process may have died anywhere in
# the move/copy sequence. Restore the last fully-known current state.
if (-not (Test-Path $BackupFormal)) {
    throw "ACTIVATION_RECOVERY_BACKUP_FORMAL_MISSING=$BackupFormal"
}
if (-not (Test-Path $BackupReceipt)) {
    throw "ACTIVATION_RECOVERY_BACKUP_RECEIPT_MISSING=$BackupReceipt"
}
if ($HadActivationMarker -and -not (Test-Path $BackupActivationMarker)) {
    throw "ACTIVATION_RECOVERY_BACKUP_MARKER_MISSING=$BackupActivationMarker"
}
if ($HadCurrentReusable -and -not (Test-Path $CurrentReusable) -and -not (Test-Path $BackupReusable)) {
    throw 'ACTIVATION_RECOVERY_REUSABLE_STATE_UNRECOVERABLE'
}
if (-not (Test-Path $CurrentSearch) -and -not (Test-Path $BackupSearch)) {
    throw 'ACTIVATION_RECOVERY_SEARCH_STATE_UNRECOVERABLE'
}

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
if (Test-Path $BackupSearch) {
    if (Test-Path $CurrentSearch) {
        $failedSearch = "$CurrentSearch.interrupted-$stamp"
        Move-Item $CurrentSearch $failedSearch
    }
    Move-Item $BackupSearch $CurrentSearch
}

Copy-Item $BackupFormal $FormalJsonl -Force

if (Test-Path $BackupReusable) {
    if (Test-Path $CurrentReusable) { Remove-Item $CurrentReusable -Recurse -Force }
    Move-Item $BackupReusable $CurrentReusable
}
elseif (-not $HadCurrentReusable -and (Test-Path $CurrentReusable)) {
    Remove-Item $CurrentReusable -Recurse -Force
}

if ($HadActivationMarker) {
    Copy-Item $BackupActivationMarker $ActivationMarker -Force
}
else {
    Remove-Item $ActivationMarker -Force -ErrorAction SilentlyContinue
}
Copy-Item $BackupReceipt $ReceiptPath -Force

Remove-Item $StagingSearch,$StagingReusable -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $NextFormal -Force -ErrorAction SilentlyContinue
Remove-Item $BackupActivationMarker,$BackupReceipt -Force -ErrorAction SilentlyContinue
Remove-Item $JournalPath -Force

Write-Host "GACE_MODULECATALOG_ACTIVATION_RECOVERY=PASS MODE=ROLLBACK COMMIT=$TargetCommit"
