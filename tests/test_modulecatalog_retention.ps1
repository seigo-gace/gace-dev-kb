$ErrorActionPreference = 'Stop'

$Repo = Split-Path $PSScriptRoot -Parent
$Script = Join-Path $Repo 'scripts\prune-modulecatalog-kb-retention-windows.ps1'
if (-not (Test-Path $Script)) { throw "RETENTION_SCRIPT_MISSING=$Script" }

$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-retention-test-" + [Guid]::NewGuid().ToString('N'))
try {
    $Data = Join-Path $Root 'data'
    $Records = Join-Path $Data 'knowledge-records'
    $Sources = Join-Path $Data 'knowledge-sources\accepted'
    $Intake = Join-Path $Data 'knowledge-intake\modulecatalog'
    $Accepted = Join-Path $Intake 'accepted'
    $Processed = Join-Path $Data 'knowledge-inbox\modulecatalog\processed'
    $Failed = Join-Path $Data 'knowledge-inbox\modulecatalog\failed'
    foreach ($path in @($Records,$Sources,$Intake,$Accepted,$Processed,$Failed)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }

    function New-TestDirectory {
        param([string]$Path,[int]$MinutesAgo)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Set-Content -Path (Join-Path $Path 'evidence.txt') -Value $Path
        (Get-Item $Path).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-$MinutesAgo)
    }
    function New-TestFile {
        param([string]$Path,[int]$MinutesAgo)
        Set-Content -Path $Path -Value $Path
        (Get-Item $Path).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-$MinutesAgo)
    }
    function Assert-Equal {
        param($Actual,$Expected,[string]$Label)
        if ($Actual -ne $Expected) { throw "ASSERT_EQUAL_FAILED=$Label expected=$Expected actual=$Actual" }
    }
    function Assert-True {
        param([bool]$Value,[string]$Label)
        if (-not $Value) { throw "ASSERT_TRUE_FAILED=$Label" }
    }

    $CurrentCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $ProtectedSearch = Join-Path $Data 'knowledge-search.previous-20260101-000001'
    $ProtectedFormal = Join-Path $Records 'formal-kb.previous-20260101-000001.jsonl'
    $ProtectedReusable = Join-Path $Sources 'modulecatalog-reusable.previous-20260101-000001'
    $CurrentAccepted = Join-Path $Accepted $CurrentCommit

    for ($i = 1; $i -le 5; $i++) {
        $stamp = "20260101-00000$i"
        $minutes = 100 - $i
        $search = Join-Path $Data "knowledge-search.previous-$stamp"
        if ($search -ne $ProtectedSearch) { New-TestDirectory -Path $search -MinutesAgo $minutes }
        $formal = Join-Path $Records "formal-kb.previous-$stamp.jsonl"
        if ($formal -ne $ProtectedFormal) { New-TestFile -Path $formal -MinutesAgo $minutes }
        $reusable = Join-Path $Sources "modulecatalog-reusable.previous-$stamp"
        if ($reusable -ne $ProtectedReusable) { New-TestDirectory -Path $reusable -MinutesAgo $minutes }
        New-TestDirectory -Path (Join-Path $Processed "delivery-$i") -MinutesAgo $minutes
        New-TestDirectory -Path (Join-Path $Failed "failed-$i") -MinutesAgo $minutes
        New-TestDirectory -Path (Join-Path $Accepted (('{0:x40}' -f $i))) -MinutesAgo $minutes
    }
    New-TestDirectory -Path $ProtectedSearch -MinutesAgo 500
    New-TestFile -Path $ProtectedFormal -MinutesAgo 500
    New-TestDirectory -Path $ProtectedReusable -MinutesAgo 500
    New-TestDirectory -Path $CurrentAccepted -MinutesAgo 500

    for ($i = 1; $i -le 4; $i++) {
        New-TestDirectory -Path (Join-Path $Data "knowledge-search.failed-20260101-00000$i") -MinutesAgo (200-$i)
    }

    New-TestDirectory -Path (Join-Path $Data 'knowledge-search.reusable-staging') -MinutesAgo 1000
    New-TestDirectory -Path (Join-Path $Sources 'modulecatalog-reusable-staging') -MinutesAgo 1000
    New-TestFile -Path (Join-Path $Records 'formal-kb.reusable-next.jsonl') -MinutesAgo 1000
    New-TestFile -Path (Join-Path $Records 'formal-kb.reusable-base-next.jsonl') -MinutesAgo 1000

    $Marker = [ordered]@{
        schemaVersion = 1
        status = 'ACTIVE'
        catalogCommit = $CurrentCommit
        backupFormal = $ProtectedFormal
        backupSearch = $ProtectedSearch
        backupReusable = $ProtectedReusable
        acceptedRoot = $CurrentAccepted
    }
    $Marker | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $Records 'modulecatalog-reusable-active.json') -Encoding UTF8

    & pwsh -NoProfile -File $Script -Root $Root -KeepActivationBackups 2 -KeepProcessedDeliveries 2 -KeepFailedDeliveries 2 -KeepAcceptedSnapshots 2 -KeepFailedRuntimeBackups 1
    if ($LASTEXITCODE -ne 0) { throw "RETENTION_RUN_FAILED=$LASTEXITCODE" }

    Assert-True (Test-Path $ProtectedSearch) 'protected search backup'
    Assert-True (Test-Path $ProtectedFormal) 'protected formal backup'
    Assert-True (Test-Path $ProtectedReusable) 'protected reusable backup'
    Assert-True (Test-Path $CurrentAccepted) 'current accepted root'

    Assert-Equal @(Get-ChildItem $Data -Directory -Filter 'knowledge-search.previous-*').Count 3 'search backups'
    Assert-Equal @(Get-ChildItem $Records -File -Filter 'formal-kb.previous-*.jsonl').Count 3 'formal backups'
    Assert-Equal @(Get-ChildItem $Sources -Directory -Filter 'modulecatalog-reusable.previous-*').Count 3 'reusable backups'
    Assert-Equal @(Get-ChildItem $Processed -Directory).Count 2 'processed deliveries'
    Assert-Equal @(Get-ChildItem $Failed -Directory).Count 2 'failed deliveries'
    Assert-Equal @(Get-ChildItem $Accepted -Directory).Count 3 'accepted snapshots'
    Assert-Equal @(Get-ChildItem $Data -Directory -Filter 'knowledge-search.failed-*').Count 1 'failed runtime backups'

    Assert-True (-not (Test-Path (Join-Path $Data 'knowledge-search.reusable-staging'))) 'stale search staging removed'
    Assert-True (-not (Test-Path (Join-Path $Sources 'modulecatalog-reusable-staging'))) 'stale reusable staging removed'
    Assert-True (-not (Test-Path (Join-Path $Records 'formal-kb.reusable-next.jsonl'))) 'stale next formal removed'
    Assert-True (-not (Test-Path (Join-Path $Records 'formal-kb.reusable-base-next.jsonl'))) 'stale base formal removed'

    # A second pass must be idempotent and must never prune protected rollback/current authority.
    & pwsh -NoProfile -File $Script -Root $Root -KeepActivationBackups 2 -KeepProcessedDeliveries 2 -KeepFailedDeliveries 2 -KeepAcceptedSnapshots 2 -KeepFailedRuntimeBackups 1
    if ($LASTEXITCODE -ne 0) { throw "RETENTION_SECOND_RUN_FAILED=$LASTEXITCODE" }
    Assert-True (Test-Path $ProtectedSearch) 'protected search after replay'
    Assert-True (Test-Path $CurrentAccepted) 'current accepted after replay'
    Assert-Equal @(Get-ChildItem $Processed -Directory).Count 2 'processed stable after replay'

    Write-Host 'GACE_MODULECATALOG_RETENTION_TEST=PASS'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
