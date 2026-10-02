param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$InboxRoot = '',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [ValidateRange(1,86400)][int]$ReceiverTimeoutSeconds = 7200
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Receiver = Join-Path $Repo 'scripts\receive-modulecatalog-kbdata-windows.ps1'
if (-not (Test-Path $Receiver)) { throw "RECEIVER_MISSING=$Receiver" }
$PowerShellHost = (Get-Process -Id $PID).Path
if (-not $PowerShellHost -or -not (Test-Path $PowerShellHost)) { throw "INBOX_PROCESSOR_POWERSHELL_HOST_MISSING=$PowerShellHost" }

$InboxBase = Join-Path $Root 'data\knowledge-inbox\modulecatalog'
if (-not $InboxRoot) { $InboxRoot = Join-Path $InboxBase 'ready' }
$ProcessingRoot = Join-Path $InboxBase 'processing'
$ProcessedRoot = Join-Path $InboxBase 'processed'
$FailedRoot = Join-Path $InboxBase 'failed'
foreach ($path in @($InboxRoot,$ProcessingRoot,$ProcessedRoot,$FailedRoot)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }

function Quote-ProcessArgument { param([string]$Value) return '"' + $Value.Replace('"','\"') + '"' }
function Read-LogTail {
    param([string]$Path,[int]$Lines = 40)
    if (-not (Test-Path $Path)) { return '' }
    return ((Get-Content $Path -Tail $Lines -ErrorAction SilentlyContinue) -join "`n").Trim()
}
function Write-JsonUtf8 {
    param([object]$Value,[string]$Path)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine, $encoding)
}
function Unique-FailedPath {
    param([string]$Name)
    return Join-Path $FailedRoot ("{0}-{1}-{2}" -f $Name,(Get-Date).ToString('yyyyMMdd-HHmmss'),([Guid]::NewGuid().ToString('N').Substring(0,8)))
}
function Resolve-ProcessedArchivePath {
    param([string]$Name)
    $base = Join-Path $ProcessedRoot $Name
    if (-not (Test-Path $base)) { return $base }
    $existing = Get-Item $base -ErrorAction Stop
    if (-not $existing.PSIsContainer) {
        # A non-directory collision is an archive error, not a prior delivery.
        return $base
    }
    return Join-Path $ProcessedRoot ("{0}-replay-{1}-{2}" -f $Name,(Get-Date).ToString('yyyyMMdd-HHmmss'),([Guid]::NewGuid().ToString('N').Substring(0,8)))
}
function Get-DeliveryReadiness {
    param([System.IO.DirectoryInfo]$Directory)

    $manifestPath = Join-Path $Directory.FullName 'manifest.json'
    if (-not (Test-Path $manifestPath)) {
        return [pscustomobject]@{ Directory=$Directory; Ready=$false; Reason='NO_MANIFEST' }
    }

    try { $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json }
    catch { return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason='MANIFEST_PRESENT_UNREADABLE' } }

    $assets = @($manifest.assets)
    $declaredAssetCount = -1
    try { $declaredAssetCount = [int]$manifest.assetCount } catch { }
    if ($declaredAssetCount -lt 1 -or $assets.Count -ne $declaredAssetCount) {
        return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason='MANIFEST_CARDINALITY_INVALID' }
    }

    foreach ($asset in $assets) {
        $assetId = [string]$asset.id
        if (-not $assetId) {
            return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason='MANIFEST_ASSET_ID_INVALID' }
        }
        $assetDir = Join-Path $Directory.FullName (Join-Path 'assets' $assetId)
        $bundleManifestPath = Join-Path $assetDir 'manifest.json'
        if (-not (Test-Path $assetDir)) {
            return [pscustomobject]@{ Directory=$Directory; Ready=$false; Reason="MISSING_ASSET_DIR:$assetId" }
        }
        if (-not (Test-Path $bundleManifestPath)) {
            return [pscustomobject]@{ Directory=$Directory; Ready=$false; Reason="MISSING_ASSET_MANIFEST:$assetId" }
        }

        try { $bundleManifest = Get-Content $bundleManifestPath -Raw | ConvertFrom-Json }
        catch { return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason="ASSET_MANIFEST_UNREADABLE:$assetId" } }
        $files = @($bundleManifest.files)
        if ($files.Count -eq 0) {
            return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason="ASSET_MANIFEST_FILES_INVALID:$assetId" }
        }

        $assetRootFull = [System.IO.Path]::GetFullPath($assetDir)
        if (-not $assetRootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $assetRootFull += [System.IO.Path]::DirectorySeparatorChar
        }

        foreach ($file in $files) {
            $relative = [string]$file.path
            if (-not $relative) {
                return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason="ASSET_MANIFEST_PATH_INVALID:$assetId" }
            }

            $normalizedRelative = $relative -replace '/', '\'
            if ([System.IO.Path]::IsPathRooted($normalizedRelative) -or $normalizedRelative -match '(^|\\)\.\.(\\|$)') {
                return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason="ASSET_MANIFEST_PATH_UNSAFE:${assetId}:$relative" }
            }
            try { $targetFull = [System.IO.Path]::GetFullPath((Join-Path $assetDir $normalizedRelative)) }
            catch { return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason="ASSET_MANIFEST_PATH_INVALID:${assetId}:$relative" } }
            if (-not $targetFull.StartsWith($assetRootFull,[System.StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason="ASSET_MANIFEST_PATH_ESCAPE:${assetId}:$relative" }
            }

            if (-not (Test-Path $targetFull -PathType Leaf)) {
                return [pscustomobject]@{ Directory=$Directory; Ready=$false; Reason="MISSING_BUNDLE_FILE:${assetId}:$relative" }
            }
            $expectedSize = -1L
            try { $expectedSize = [long]$file.size } catch { }
            if ($expectedSize -lt 0) {
                return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason="ASSET_MANIFEST_SIZE_INVALID:${assetId}:$relative" }
            }
            $actualSize = (Get-Item $targetFull).Length
            if ($actualSize -lt $expectedSize) {
                return [pscustomobject]@{ Directory=$Directory; Ready=$false; Reason="BUNDLE_FILE_STILL_COPYING:${assetId}:${relative}:$actualSize/$expectedSize" }
            }
        }
    }

    return [pscustomobject]@{ Directory=$Directory; Ready=$true; Reason='TRANSPORT_COMPLETE' }
}

$ProcessorLockPath = Join-Path $InboxBase 'processor.lock'
$ProcessorLock = $null
$OwnsProcessorLock = $false
try {
    try {
        $ProcessorLock = [System.IO.File]::Open($ProcessorLockPath,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
        $OwnsProcessorLock = $true
    }
    catch { throw "MODULECATALOG_INBOX_PROCESSOR_BUSY=$ProcessorLockPath" }

    $ProcessingDeliveries = @(Get-ChildItem $ProcessingRoot -Directory | Sort-Object Name)
    if ($ProcessingDeliveries.Count -gt 1) {
        $names = ($ProcessingDeliveries | ForEach-Object { $_.Name }) -join ','
        throw "MULTIPLE_PROCESSING_DELIVERIES_REQUIRE_RECOVERY=$names"
    }

    $deliveryName = $null
    $processingPath = $null
    $processedPath = $null
    $resumed = $false
    if ($ProcessingDeliveries.Count -eq 1) {
        $processingPath = $ProcessingDeliveries[0].FullName
        $deliveryName = $ProcessingDeliveries[0].Name
        if (-not (Test-Path (Join-Path $processingPath 'manifest.json'))) { throw "PROCESSING_DELIVERY_MANIFEST_MISSING=$processingPath" }
        $resumed = $true
        Write-Host "GACE_MODULECATALOG_INBOX_RESUME=YES DELIVERY=$processingPath"
    }
    else {
        $AllReady = @(Get-ChildItem $InboxRoot -Directory | Sort-Object Name)
        $Readiness = @($AllReady | ForEach-Object { Get-DeliveryReadiness -Directory $_ })
        $Deliveries = @($Readiness | Where-Object { $_.Ready } | ForEach-Object { $_.Directory })
        $Incomplete = @($Readiness | Where-Object { -not $_.Ready })
        foreach ($item in $Incomplete) {
            Write-Host "GACE_MODULECATALOG_INBOX_PENDING=$($item.Reason) DELIVERY=$($item.Directory.FullName)"
        }
        if ($Deliveries.Count -eq 0) {
            Write-Host "GACE_MODULECATALOG_INBOX=PASS READY=0 PENDING=$($Incomplete.Count) ROOT=$InboxRoot"
            return
        }
        if ($Deliveries.Count -gt 1) {
            $names = ($Deliveries | ForEach-Object { $_.Name }) -join ','
            throw "MULTIPLE_READY_DELIVERIES_REQUIRE_ORDER_AUTHORITY=$names"
        }
        $delivery = $Deliveries[0]
        $deliveryName = $delivery.Name
        $processingPath = Join-Path $ProcessingRoot $deliveryName
        if (Test-Path $processingPath) { throw "PROCESSING_DELIVERY_ALREADY_EXISTS=$processingPath" }
        Write-Host "=== CLAIM DELIVERY: $deliveryName ==="
        Move-Item $delivery.FullName $processingPath
    }

    $processedPath = Resolve-ProcessedArchivePath -Name $deliveryName
    if (Test-Path $processedPath) { throw "PROCESSED_DELIVERY_ARCHIVE_COLLISION=$processedPath" }

    $attemptTag = "{0}-{1}" -f (Get-Date).ToString('yyyyMMdd-HHmmss'),([Guid]::NewGuid().ToString('N').Substring(0,8))
    $receiverStdoutName = "kb-receiver-$attemptTag.stdout.log"
    $receiverStderrName = "kb-receiver-$attemptTag.stderr.log"
    $receiverStdout = Join-Path $processingPath $receiverStdoutName
    $receiverStderr = Join-Path $processingPath $receiverStderrName
    $activated = $false
    $retryable = $false
    $process = $null

    try {
        Write-Host "=== PROCESS DELIVERY: $deliveryName ==="
        $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-ProcessArgument $Receiver),'-Root',(Quote-ProcessArgument $Root),'-Python',(Quote-ProcessArgument $Python),'-DeliveryRoot',(Quote-ProcessArgument $processingPath))
        $process = Start-Process -FilePath $PowerShellHost -ArgumentList $args -WorkingDirectory $Repo -NoNewWindow -PassThru -RedirectStandardOutput $receiverStdout -RedirectStandardError $receiverStderr
        $waitMilliseconds = [int64]$ReceiverTimeoutSeconds * 1000
        if ($waitMilliseconds -gt [int]::MaxValue) { throw "RECEIVER_TIMEOUT_TOO_LARGE_SECONDS=$ReceiverTimeoutSeconds" }
        if (-not $process.WaitForExit([int]$waitMilliseconds)) {
            $retryable = $true
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            try { $process.WaitForExit(10000) | Out-Null } catch { }
            throw "MODULECATALOG_RECEIVER_TIMEOUT=${ReceiverTimeoutSeconds}s DELIVERY=$processingPath"
        }
        $process.Refresh()
        $exitCode = [int]$process.ExitCode
        if ($exitCode -ne 0) {
            $stderrTail = Read-LogTail -Path $receiverStderr
            $stdoutTail = Read-LogTail -Path $receiverStdout
            $combined = "$stderrTail`n$stdoutTail"
            if ($combined -match 'MODULECATALOG_RECEIVER_BUSY|RUNTIME_RECEIVER_BUSY|IDEMPOTENT_ACTIVE_RUNTIME_UNHEALTHY|FINAL_ACTIVE_RUNTIME_HEALTH_FAILED|RUNTIME_UNRESOLVED_ACTIVATION_JOURNAL') {
                $retryable = $true
            }
            throw ("MODULECATALOG_INBOX_DELIVERY_FAILED={0} EXIT={1} STDERR={2} STDOUT={3}" -f $processingPath,$exitCode,$stderrTail,$stdoutTail)
        }

        $manifest = Get-Content (Join-Path $processingPath 'manifest.json') -Raw | ConvertFrom-Json
        $commit = [string]$manifest.catalog.commit
        if ($commit.Length -ne 40) { throw "PROCESSED_DELIVERY_COMMIT_INVALID=$commit" }
        $receipt = Join-Path $Root "data\knowledge-intake\modulecatalog\receipts\$commit.json"
        if (-not (Test-Path $receipt)) { throw "ACTIVE_RECEIPT_MISSING=$receipt" }
        $receiptData = Get-Content $receipt -Raw | ConvertFrom-Json
        if ([string]$receiptData.status -ne 'ACTIVE') { throw "ACTIVE_RECEIPT_STATUS_INVALID=$($receiptData.status)" }
        if ([string]$receiptData.catalogCommit -ne $commit) { throw "ACTIVE_RECEIPT_COMMIT_MISMATCH=$($receiptData.catalogCommit)" }
        $activated = $true

        Copy-Item $receipt (Join-Path $processingPath 'kb-active-receipt.json') -Force
        Remove-Item (Join-Path $processingPath 'kb-retryable.json'),(Join-Path $processingPath 'kb-archive-pending.json') -Force -ErrorAction SilentlyContinue
        Move-Item $processingPath $processedPath
        Write-Host "GACE_MODULECATALOG_INBOX=PASS READY=1 PROCESSED=1 RESUMED=$resumed STATUS=ACTIVE COMMIT=$commit ARCHIVE=$processedPath RECEIVER_STDOUT=$receiverStdoutName RECEIVER_STDERR=$receiverStderrName"
    }
    catch {
        $failure = $_
        if (Test-Path $processingPath) {
            $record = [ordered]@{
                schemaVersion = 1
                deliveryName = $deliveryName
                resumed = $resumed
                recordedAtUtc = [DateTime]::UtcNow.ToString('o')
                error = [string]$failure.Exception.Message
                receiverStdoutLog = $receiverStdoutName
                receiverStderrLog = $receiverStderrName
            }
            if ($activated) {
                $record.status = 'ACTIVE_ARCHIVE_PENDING'
                Write-JsonUtf8 -Value $record -Path (Join-Path $processingPath 'kb-archive-pending.json')
                Write-Host "GACE_MODULECATALOG_INBOX=ACTIVE_ARCHIVE_PENDING DELIVERY=$processingPath"
                throw $failure
            }
            if ($retryable) {
                $record.status = 'RETRYABLE'
                Write-JsonUtf8 -Value $record -Path (Join-Path $processingPath 'kb-retryable.json')
                Write-Host "GACE_MODULECATALOG_INBOX=RETRYABLE DELIVERY=$processingPath"
                throw $failure
            }
            $record.status = 'FAILED'
            Write-JsonUtf8 -Value $record -Path (Join-Path $processingPath 'kb-failure.json')
            $failedPath = Unique-FailedPath -Name $deliveryName
            Move-Item $processingPath $failedPath
            Write-Host "GACE_MODULECATALOG_INBOX=FAILED ARCHIVE=$failedPath RECEIVER_STDOUT=$receiverStdoutName RECEIVER_STDERR=$receiverStderrName"
        }
        throw $failure
    }
    finally {
        if ($null -ne $process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
finally {
    if ($null -ne $ProcessorLock) { $ProcessorLock.Dispose(); $ProcessorLock = $null }
    if ($OwnsProcessorLock) { Remove-Item $ProcessorLockPath -Force -ErrorAction SilentlyContinue }
}
