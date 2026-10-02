$ErrorActionPreference = 'Stop'

$Recovery = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\recover-modulecatalog-activation-windows.ps1')).Path
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-activation-recovery-" + [Guid]::NewGuid().ToString('N'))

function Write-Text {
    param([string]$Path,[string]$Text)
    $dir = Split-Path $Path
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path,$Text,$encoding)
}

function Write-Json {
    param([string]$Path,[object]$Value)
    Write-Text -Path $Path -Text (($Value | ConvertTo-Json -Depth 16) + [Environment]::NewLine)
}

function New-JournalFixture {
    param([string]$Base,[string]$Target,[bool]$Committed)

    $currentSearch = Join-Path $Base 'data\knowledge-search'
    $backupSearch = Join-Path $Base 'data\knowledge-search.previous-test'
    $formal = Join-Path $Base 'data\knowledge-records\formal-kb.jsonl'
    $backupFormal = Join-Path $Base 'data\knowledge-records\formal-kb.previous-test.jsonl'
    $currentReusable = Join-Path $Base 'data\knowledge-sources\accepted\modulecatalog-reusable-current'
    $backupReusable = Join-Path $Base 'data\knowledge-sources\accepted\modulecatalog-reusable.previous-test'
    $marker = Join-Path $Base 'data\knowledge-records\modulecatalog-reusable-active.json'
    $backupMarker = "$marker.rollback-test"
    $receipt = Join-Path $Base "data\knowledge-intake\modulecatalog\receipts\$Target.json"
    $backupReceipt = "$receipt.rollback-test"
    $stagingSearch = Join-Path $Base 'data\knowledge-search.reusable-staging'
    $stagingReusable = Join-Path $Base 'data\knowledge-sources\accepted\modulecatalog-reusable-staging'
    $nextFormal = Join-Path $Base 'data\knowledge-records\formal-kb.reusable-next.jsonl'
    $journal = Join-Path $Base 'data\knowledge-intake\modulecatalog\activation-transaction.json'

    New-Item -ItemType Directory -Path $currentSearch,$backupSearch,$currentReusable,$backupReusable,$stagingSearch,$stagingReusable -Force | Out-Null
    Write-Text (Join-Path $currentSearch 'state.txt') 'new-search'
    Write-Text (Join-Path $backupSearch 'state.txt') 'old-search'
    Write-Text $formal 'new-formal'
    Write-Text $backupFormal 'old-formal'
    Write-Text (Join-Path $currentReusable 'state.txt') 'new-reusable'
    Write-Text (Join-Path $backupReusable 'state.txt') 'old-reusable'
    Write-Text $nextFormal 'staging-formal'

    $oldMarker = [ordered]@{ status='ACTIVE'; catalogCommit=('a' * 40) }
    $acceptedReceipt = [ordered]@{ status='ACCEPTED'; catalogCommit=$Target }
    Write-Json $backupMarker $oldMarker
    Write-Json $backupReceipt $acceptedReceipt

    if ($Committed) {
        $active = [ordered]@{ status='ACTIVE'; catalogCommit=$Target }
        Write-Json $marker $active
        Write-Json $receipt $active
        Write-Json (Join-Path $currentReusable 'runtime-state.json') $active
    }
    else {
        Write-Json $marker ([ordered]@{ status='ACTIVE'; catalogCommit=('b' * 40) })
        Write-Json $receipt ([ordered]@{ status='ACCEPTED'; catalogCommit=$Target })
    }

    $j = [ordered]@{
        schemaVersion=1
        status='PREPARED'
        targetCommit=$Target
        currentSearch=$currentSearch
        backupSearch=$backupSearch
        formalJsonl=$formal
        backupFormal=$backupFormal
        currentReusable=$currentReusable
        backupReusable=$backupReusable
        activationMarker=$marker
        backupActivationMarker=$backupMarker
        receiptPath=$receipt
        backupReceipt=$backupReceipt
        stagingSearch=$stagingSearch
        stagingReusable=$stagingReusable
        nextFormal=$nextFormal
        hadCurrentReusable=$true
        hadActivationMarker=$true
    }
    Write-Json $journal $j
    return [pscustomobject]@{
        Journal=$journal; CurrentSearch=$currentSearch; Formal=$formal; CurrentReusable=$currentReusable;
        Marker=$marker; Receipt=$receipt; BackupSearch=$backupSearch; BackupFormal=$backupFormal;
        BackupReusable=$backupReusable; BackupMarker=$backupMarker; BackupReceipt=$backupReceipt
    }
}

try {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null

    # No journal is a healthy no-op.
    & pwsh -NoProfile -File $Recovery -Root $Root
    if ($LASTEXITCODE -ne 0) { throw "NO_JOURNAL_RECOVERY_FAILED=$LASTEXITCODE" }

    # Non-committed transaction restores the last known current state.
    $rollbackRoot = Join-Path $Root 'rollback'
    $targetRollback = 'c' * 40
    $r = New-JournalFixture -Base $rollbackRoot -Target $targetRollback -Committed $false
    & pwsh -NoProfile -File $Recovery -Root $rollbackRoot -JournalPath $r.Journal
    if ($LASTEXITCODE -ne 0) { throw "ROLLBACK_RECOVERY_FAILED=$LASTEXITCODE" }
    if ((Get-Content (Join-Path $r.CurrentSearch 'state.txt') -Raw).Trim() -ne 'old-search') { throw 'ROLLBACK_SEARCH_NOT_RESTORED' }
    if ((Get-Content $r.Formal -Raw).Trim() -ne 'old-formal') { throw 'ROLLBACK_FORMAL_NOT_RESTORED' }
    if ((Get-Content (Join-Path $r.CurrentReusable 'state.txt') -Raw).Trim() -ne 'old-reusable') { throw 'ROLLBACK_REUSABLE_NOT_RESTORED' }
    $restoredMarker = Get-Content $r.Marker -Raw | ConvertFrom-Json
    if ([string]$restoredMarker.catalogCommit -ne ('a' * 40)) { throw 'ROLLBACK_MARKER_NOT_RESTORED' }
    $restoredReceipt = Get-Content $r.Receipt -Raw | ConvertFrom-Json
    if ([string]$restoredReceipt.status -ne 'ACCEPTED') { throw 'ROLLBACK_RECEIPT_NOT_RESTORED' }
    if (Test-Path $r.Journal) { throw 'ROLLBACK_JOURNAL_NOT_REMOVED' }

    # Fully committed authority is finalized, never rolled backward.
    $commitRoot = Join-Path $Root 'committed'
    $targetCommit = 'd' * 40
    $c = New-JournalFixture -Base $commitRoot -Target $targetCommit -Committed $true
    & pwsh -NoProfile -File $Recovery -Root $commitRoot -JournalPath $c.Journal
    if ($LASTEXITCODE -ne 0) { throw "COMMITTED_RECOVERY_FAILED=$LASTEXITCODE" }
    if ((Get-Content (Join-Path $c.CurrentSearch 'state.txt') -Raw).Trim() -ne 'new-search') { throw 'COMMITTED_SEARCH_WAS_ROLLED_BACK' }
    if ((Get-Content $c.Formal -Raw).Trim() -ne 'new-formal') { throw 'COMMITTED_FORMAL_WAS_ROLLED_BACK' }
    if ((Get-Content (Join-Path $c.CurrentReusable 'state.txt') -Raw).Trim() -ne 'new-reusable') { throw 'COMMITTED_REUSABLE_WAS_ROLLED_BACK' }
    $finalMarker = Get-Content $c.Marker -Raw | ConvertFrom-Json
    if ([string]$finalMarker.catalogCommit -ne $targetCommit) { throw 'COMMITTED_MARKER_CHANGED' }
    if (Test-Path $c.Journal) { throw 'COMMITTED_JOURNAL_NOT_REMOVED' }
    if (Test-Path $c.BackupMarker) { throw 'COMMITTED_TEMP_MARKER_BACKUP_NOT_REMOVED' }
    if (Test-Path $c.BackupReceipt) { throw 'COMMITTED_TEMP_RECEIPT_BACKUP_NOT_REMOVED' }

    Write-Host 'GACE_MODULECATALOG_ACTIVATION_RECOVERY_TEST=PASS'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
