$ErrorActionPreference = 'Stop'

$Processor = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\process-modulecatalog-inbox-windows.ps1')).Path
$Root = Join-Path ([System.IO.Path]::GetTempPath()) ("gace-transport-readiness-" + [Guid]::NewGuid().ToString('N'))
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

function Write-Delivery {
    param(
        [string]$Directory,
        [string]$Commit,
        [int]$ExpectedPayloadSize,
        [string]$Payload
    )
    $assetId = 'asset-a'
    $assetDir = Join-Path $Directory "assets\$assetId"
    New-Item -ItemType Directory -Path $assetDir -Force | Out-Null
    $bundle = [ordered]@{
        schema_version = 1
        format = 'gace.reusable-asset.v1'
        asset_id = $assetId
        files = @(
            [ordered]@{ path='payload.txt'; size=$ExpectedPayloadSize; sha256=('0' * 64) }
        )
    }
    Write-JsonUtf8 -Value $bundle -Path (Join-Path $assetDir 'manifest.json')
    [System.IO.File]::WriteAllText((Join-Path $assetDir 'payload.txt'), $Payload, $Utf8)
    $manifest = [ordered]@{
        schema_version = 1
        format = 'gace.reusable-asset.v1'
        catalog = [ordered]@{ repository='seigo-gace/modular-catalog'; commit=$Commit }
        assetCount = 1
        assets = @([ordered]@{ id=$assetId; knowledgeUnits=1; relationships=1; cases=1 })
    }
    Write-JsonUtf8 -Value $manifest -Path (Join-Path $Directory 'manifest.json')
}

try {
    New-Item -ItemType Directory -Path $RepoScripts,$Ready,$Processing,$Processed,$Failed -Force | Out-Null
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

    # A top-level manifest may arrive before a bundle file finishes copying. The
    # receiver must not claim it into processing or classify it FAILED.
    $Partial = Join-Path $Ready 'partial-copy'
    $PartialCommit = '1' * 40
    Write-Delivery -Directory $Partial -Commit $PartialCommit -ExpectedPayloadSize 10 -Payload 'abc'
    $pendingOutput = @(& pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "PARTIAL_DELIVERY_POLL_FAILED=$LASTEXITCODE OUTPUT=$($pendingOutput -join ' | ')" }
    if (-not (Test-Path $Partial)) { throw 'PARTIAL_DELIVERY_WAS_CLAIMED' }
    if (Test-Path (Join-Path $Processing 'partial-copy')) { throw 'PARTIAL_DELIVERY_MOVED_TO_PROCESSING' }
    if (@(Get-ChildItem $Failed -Directory).Count -ne 0) { throw 'PARTIAL_DELIVERY_WRONGLY_FAILED' }
    if (($pendingOutput -join "`n") -notmatch 'BUNDLE_FILE_STILL_COPYING') { throw "PARTIAL_PENDING_REASON_MISSING=$($pendingOutput -join ' | ')" }

    # Once the declared size is present, the same delivery becomes claimable and
    # proceeds through the normal receiver/archive path.
    [System.IO.File]::WriteAllText((Join-Path $Partial 'assets\asset-a\payload.txt'), '0123456789', $Utf8)
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "COMPLETED_DELIVERY_PROCESS_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path (Join-Path $Processed 'partial-copy\kb-active-receipt.json'))) { throw 'COMPLETED_DELIVERY_NOT_ARCHIVED' }

    # A partial transport must not create false multi-ready ambiguity beside one
    # actually complete delivery.
    $Partial2 = Join-Path $Ready 'partial-beside-complete'
    Write-Delivery -Directory $Partial2 -Commit ('2' * 40) -ExpectedPayloadSize 9 -Payload 'x'
    $Complete = Join-Path $Ready 'complete'
    Write-Delivery -Directory $Complete -Commit ('3' * 40) -ExpectedPayloadSize 4 -Payload 'done'
    & pwsh -NoProfile -File $Processor -Root $Root -InboxRoot $Ready
    if ($LASTEXITCODE -ne 0) { throw "COMPLETE_WITH_PARTIAL_NEIGHBOR_FAILED=$LASTEXITCODE" }
    if (-not (Test-Path (Join-Path $Processed 'complete\kb-active-receipt.json'))) { throw 'COMPLETE_NEIGHBOR_NOT_PROCESSED' }
    if (-not (Test-Path $Partial2)) { throw 'PARTIAL_NEIGHBOR_WAS_CONSUMED' }

    Write-Host 'GACE_MODULECATALOG_TRANSPORT_READINESS=PASS PARTIAL_PENDING=PASS COMPLETE_CLAIM=PASS MIXED_READY=PASS'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
