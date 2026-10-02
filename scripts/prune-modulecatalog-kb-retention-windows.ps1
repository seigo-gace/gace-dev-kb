param(
    [string]$Root = 'F:\G-ACE-KB',
    [ValidateRange(1,50)][int]$KeepActivationBackups = 3,
    [ValidateRange(1,500)][int]$KeepProcessedDeliveries = 20,
    [ValidateRange(1,500)][int]$KeepFailedDeliveries = 20,
    [ValidateRange(1,100)][int]$KeepAcceptedSnapshots = 5,
    [ValidateRange(0,50)][int]$KeepFailedRuntimeBackups = 2,
    [switch]$DryRun,
    [switch]$AssumeReceiveLockHeld
)

$ErrorActionPreference = 'Stop'

$DataRoot = Join-Path $Root 'data'
$KnowledgeRecordsRoot = Join-Path $DataRoot 'knowledge-records'
$KnowledgeSourcesRoot = Join-Path $DataRoot 'knowledge-sources\accepted'
$IntakeRoot = Join-Path $DataRoot 'knowledge-intake\modulecatalog'
$InboxRoot = Join-Path $DataRoot 'knowledge-inbox\modulecatalog'
$AcceptedRoot = Join-Path $IntakeRoot 'accepted'
$ProcessedRoot = Join-Path $InboxRoot 'processed'
$FailedRoot = Join-Path $InboxRoot 'failed'
$ActivationMarker = Join-Path $KnowledgeRecordsRoot 'modulecatalog-reusable-active.json'
$ActivationJournal = Join-Path $IntakeRoot 'activation-transaction.json'
$ReceiveLockPath = Join-Path $IntakeRoot 'receive.lock'

foreach ($path in @($DataRoot,$KnowledgeRecordsRoot,$IntakeRoot)) {
    if (-not (Test-Path $path)) { throw "RETENTION_REQUIRED_PATH_MISSING=$path" }
}

function Get-NormalizedFullPath {
    param([string]$Path)
    if (-not $Path) { return $null }
    try { return [System.IO.Path]::GetFullPath($Path).TrimEnd('\','/') }
    catch { return $null }
}

function Test-PathUnderRoot {
    param([string]$Path,[string]$AllowedRoot)
    $candidate = Get-NormalizedFullPath -Path $Path
    $root = Get-NormalizedFullPath -Path $AllowedRoot
    if (-not $candidate -or -not $root) { return $false }
    if ($candidate -eq $root) { return $true }
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    return $candidate.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-SafeItem {
    param([System.IO.FileSystemInfo]$Item,[string]$AllowedRoot,[hashtable]$Protected,[ref]$Removed)
    $full = Get-NormalizedFullPath -Path $Item.FullName
    if (-not (Test-PathUnderRoot -Path $full -AllowedRoot $AllowedRoot)) {
        throw "RETENTION_PATH_ESCAPE=$full ROOT=$AllowedRoot"
    }
    if ($Protected.ContainsKey($full)) { return }
    if ($DryRun) {
        Write-Host "GACE_RETENTION_DRYRUN_REMOVE=$full"
    }
    else {
        Remove-Item $Item.FullName -Recurse -Force
    }
    $Removed.Value++
}

function Prune-Collection {
    param(
        [System.IO.FileSystemInfo[]]$Items,
        [int]$Keep,
        [string]$AllowedRoot,
        [hashtable]$Protected,
        [ref]$Removed
    )
    $ordered = @(
        $Items | Sort-Object `
            @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true }, `
            @{ Expression = { $_.Name }; Descending = $false }
    )
    $keptByRank = 0
    foreach ($item in $ordered) {
        $full = Get-NormalizedFullPath -Path $item.FullName
        if ($Protected.ContainsKey($full)) { continue }
        if ($keptByRank -lt $Keep) {
            $keptByRank++
            continue
        }
        Remove-SafeItem -Item $item -AllowedRoot $AllowedRoot -Protected $Protected -Removed $Removed
    }
}

$ReceiveLock = $null
$OwnsReceiveLock = $false
try {
    if (-not $AssumeReceiveLockHeld) {
        New-Item -ItemType Directory -Path $IntakeRoot -Force | Out-Null
        try {
            $ReceiveLock = [System.IO.File]::Open(
                $ReceiveLockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            $OwnsReceiveLock = $true
        }
        catch {
            Write-Host "GACE_MODULECATALOG_RETENTION=SKIP REASON=RECEIVER_BUSY LOCK=$ReceiveLockPath"
            return
        }
    }

    if (Test-Path $ActivationJournal) {
        Write-Host "GACE_MODULECATALOG_RETENTION=SKIP REASON=ACTIVATION_JOURNAL_PRESENT JOURNAL=$ActivationJournal"
        return
    }

    $Protected = @{}
    $CurrentCommit = ''
    if (Test-Path $ActivationMarker) {
        $marker = Get-Content $ActivationMarker -Raw | ConvertFrom-Json
        if ([string]$marker.status -eq 'ACTIVE') {
            $CurrentCommit = [string]$marker.catalogCommit
            foreach ($field in @('backupFormal','backupSearch','backupReusable','acceptedRoot')) {
                $value = [string]$marker.$field
                $normalized = Get-NormalizedFullPath -Path $value
                if ($normalized) { $Protected[$normalized] = $true }
            }

            # Older ACTIVE marker schema records backupSearch/formal but not the
            # reusable rollback path. All three activation backups share the same
            # timestamp suffix, so derive and protect that exact sibling rather
            # than allowing retention ranking to delete rollback authority.
            $backupSearchValue = [string]$marker.backupSearch
            $backupSearchName = if ($backupSearchValue) { [System.IO.Path]::GetFileName($backupSearchValue) } else { '' }
            if ($backupSearchName -match '^knowledge-search\.previous-(.+)$') {
                $derivedReusable = Get-NormalizedFullPath -Path (Join-Path $KnowledgeSourcesRoot ("modulecatalog-reusable.previous-{0}" -f $Matches[1]))
                if ($derivedReusable -and (Test-Path $derivedReusable)) {
                    $Protected[$derivedReusable] = $true
                }
            }
        }
    }
    if ($CurrentCommit.Length -eq 40) {
        $currentAccepted = Get-NormalizedFullPath -Path (Join-Path $AcceptedRoot $CurrentCommit)
        if ($currentAccepted) { $Protected[$currentAccepted] = $true }
    }

    $Removed = 0

    if (Test-Path $DataRoot) {
        $searchBackups = @(Get-ChildItem $DataRoot -Directory -Filter 'knowledge-search.previous-*' -ErrorAction SilentlyContinue)
        Prune-Collection -Items $searchBackups -Keep $KeepActivationBackups -AllowedRoot $DataRoot -Protected $Protected -Removed ([ref]$Removed)

        $failedRuntime = @(Get-ChildItem $DataRoot -Directory -Filter 'knowledge-search.failed-*' -ErrorAction SilentlyContinue)
        Prune-Collection -Items $failedRuntime -Keep $KeepFailedRuntimeBackups -AllowedRoot $DataRoot -Protected $Protected -Removed ([ref]$Removed)
    }

    if (Test-Path $KnowledgeRecordsRoot) {
        $formalBackups = @(Get-ChildItem $KnowledgeRecordsRoot -File -Filter 'formal-kb.previous-*.jsonl' -ErrorAction SilentlyContinue)
        Prune-Collection -Items $formalBackups -Keep $KeepActivationBackups -AllowedRoot $KnowledgeRecordsRoot -Protected $Protected -Removed ([ref]$Removed)
    }

    if (Test-Path $KnowledgeSourcesRoot) {
        $reusableBackups = @(Get-ChildItem $KnowledgeSourcesRoot -Directory -Filter 'modulecatalog-reusable.previous-*' -ErrorAction SilentlyContinue)
        Prune-Collection -Items $reusableBackups -Keep $KeepActivationBackups -AllowedRoot $KnowledgeSourcesRoot -Protected $Protected -Removed ([ref]$Removed)
    }

    if (Test-Path $AcceptedRoot) {
        $accepted = @(Get-ChildItem $AcceptedRoot -Directory -ErrorAction SilentlyContinue)
        Prune-Collection -Items $accepted -Keep $KeepAcceptedSnapshots -AllowedRoot $AcceptedRoot -Protected $Protected -Removed ([ref]$Removed)
    }

    if (Test-Path $ProcessedRoot) {
        $processed = @(Get-ChildItem $ProcessedRoot -Directory -ErrorAction SilentlyContinue)
        Prune-Collection -Items $processed -Keep $KeepProcessedDeliveries -AllowedRoot $ProcessedRoot -Protected $Protected -Removed ([ref]$Removed)
    }

    if (Test-Path $FailedRoot) {
        $failed = @(Get-ChildItem $FailedRoot -Directory -ErrorAction SilentlyContinue)
        Prune-Collection -Items $failed -Keep $KeepFailedDeliveries -AllowedRoot $FailedRoot -Protected $Protected -Removed ([ref]$Removed)
    }

    foreach ($stale in @(
        (Join-Path $DataRoot 'knowledge-search.reusable-staging'),
        (Join-Path $KnowledgeSourcesRoot 'modulecatalog-reusable-staging'),
        (Join-Path $KnowledgeRecordsRoot 'formal-kb.reusable-next.jsonl'),
        (Join-Path $KnowledgeRecordsRoot 'formal-kb.reusable-base-next.jsonl')
    )) {
        if (Test-Path $stale) {
            $item = Get-Item $stale
            $allowed = if (Test-PathUnderRoot -Path $stale -AllowedRoot $KnowledgeRecordsRoot) { $KnowledgeRecordsRoot } elseif (Test-PathUnderRoot -Path $stale -AllowedRoot $KnowledgeSourcesRoot) { $KnowledgeSourcesRoot } else { $DataRoot }
            Remove-SafeItem -Item $item -AllowedRoot $allowed -Protected $Protected -Removed ([ref]$Removed)
        }
    }

    Write-Host ((
        "GACE_MODULECATALOG_RETENTION=PASS REMOVED={0} DRYRUN={1} KEEP_BACKUPS={2} " +
        "KEEP_PROCESSED={3} KEEP_FAILED={4} KEEP_ACCEPTED={5} CURRENT_COMMIT={6}"
    ) -f $Removed,[bool]$DryRun,$KeepActivationBackups,$KeepProcessedDeliveries,$KeepFailedDeliveries,$KeepAcceptedSnapshots,$CurrentCommit)
}
finally {
    if ($null -ne $ReceiveLock) { $ReceiveLock.Dispose(); $ReceiveLock = $null }
    if ($OwnsReceiveLock) { Remove-Item $ReceiveLockPath -Force -ErrorAction SilentlyContinue }
}
