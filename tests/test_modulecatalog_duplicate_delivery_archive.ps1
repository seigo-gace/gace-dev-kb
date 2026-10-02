$ErrorActionPreference = 'Stop'

$Processor = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\process-modulecatalog-inbox-windows.ps1')).Path
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-duplicate-delivery-" + [Guid]::NewGuid().ToString('N'))
$RepoScripts = Join-Path $Root 'repo\scripts'
$InboxBase = Join-Path $Root 'data\knowledge-inbox\modulecatalog'
$Ready = Join-Path $InboxBase 'ready'
$Processed = Join-Path $InboxBase 'processed'
$Failed = Join-Path $InboxBase 'failed'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Manifest {
    param([string]$Directory,[string]$Commit)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $manifest = [ordered]@{
        schema_version = 1
        format = 'gace.reusable-asset.v1'
        catalog = [ordered]@{ repository='seigo-gace/modular-catalog'; commit=$Commit }
    }
    [System.IO.File]::WriteAllText((Join-Path $Directory 'manifest.json'), ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine, $Utf8)
}

try {
    New-Item -ItemType Directory -Path $RepoScripts,$Ready,$Processed,$Failed -Force | Out-Null
    $receiver = @'
param([string]$Root,[string]$Python,[string]$DeliveryRoot)
$ErrorActionPreference = 'Stop'
$manifest = Get-Content (Join-Path $DeliveryRoot 'manifest.json') -Raw | ConvertFrom-Json
$commit = [string]$manifest.catalog.commit
$receiptRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog\receipts'
New-Item -ItemType Directory -Path $receiptRoot -Force | Out-Null
$receipt = [ordered]@{ status='ACTIVE'; catalogCommit=$commit; assetCount=1; knowledgeUnitCount=1 }
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $receiptRoot "$commit.json"), ($receipt | ConvertTo-Json) + [Environment]::NewLine, $encoding)
Write-Host "FIXTURE_RECEIVER_PASS COMMIT=$commit"
'@
    [System.IO.File]::WriteAllText((Join-Path $RepoScripts 'receive-modulecatalog-kbdata-windows.ps1'), $receiver, $Utf8)

    $commit = '8' * 40
    Write-Manifest -Directory (Join-Path $Ready 'same-delivery') -Commit $commit
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "FIRST_DELIVERY_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path (Join-Path $Processed 'same-delivery\kb-active-receipt.json'))) { throw 'FIRST_DELIVERY_ARCHIVE_MISSING' }

    # A transport retry may reuse the same delivery-id (for example the Catalog
    # commit). The first processed archive is evidence and must not be overwritten,
    # but the replay must still be allowed through the idempotent receiver path.
    Write-Manifest -Directory (Join-Path $Ready 'same-delivery') -Commit $commit
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "REPLAY_DELIVERY_FAILED=$LASTEXITCODE" }

    $archives = @(Get-ChildItem $Processed -Directory | Where-Object { $_.Name -like 'same-delivery*' })
    if ($archives.Count -ne 2) { throw "REPLAY_ARCHIVE_COUNT_INVALID=$($archives.Count)" }
    if (@($archives | Where-Object { Test-Path (Join-Path $_.FullName 'kb-active-receipt.json') }).Count -ne 2) { throw 'REPLAY_ACTIVE_RECEIPT_ARCHIVE_MISSING' }
    if (@(Get-ChildItem $Failed -Directory).Count -ne 0) { throw 'REPLAY_WRONGLY_FAILED' }

    Write-Host 'GACE_MODULECATALOG_DUPLICATE_DELIVERY=PASS ORIGINAL_PRESERVED=YES REPLAY_ARCHIVED=YES'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
