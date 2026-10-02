param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$InboxRoot = '',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe'
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
        $Deliveries = @($AllReady | Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') })
        $Incomplete = @($AllReady | Where-Object { -not (Test-Path (Join-Path $_.FullName 'manifest.json')) })
        foreach ($item in $Incomplete) { Write-Host "GACE_MODULECATALOG_INBOX_PENDING=NO_MANIFEST DELIVERY=$($item.FullName)" }
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
        $processedPath = Join-Path $ProcessedRoot $deliveryName
        if (Test-Path $processingPath) { throw "PROCESSING_DELIVERY_ALREADY_EXISTS=$processingPath" }
        if (Test-Path $processedPath) { throw "PROCESSED_DELIVERY_ALREADY_EXISTS=$processedPath" }
        Write-Host "=== CLAIM DELIVERY: $deliveryName ==="
        Move-Item $delivery.FullName $processingPath
    }

    $processedPath = Join-Path $ProcessedRoot $deliveryName
    if (Test-Path $processedPath) { throw "PROCESSED_DELIVERY_ALREADY_EXISTS=$processedPath" }

    $attemptTag = "{0}-{1}" -f (Get-Date).ToString('yyyyMMdd-HHmmss'),([Guid]::NewGuid().ToString('N').Substring(0,8))
    $receiverStdoutName = "kb-receiver-$attemptTag.stdout.log"
    $receiverStderrName = "kb-receiver-$attemptTag.stderr.log"
    $receiverStdout = Join-Path $processingPath $receiverStdoutName
    $receiverStderr = Join-Path $processingPath $receiverStderrName
    $activated = $false
    $retryable = $false

    try {
        Write-Host "=== PROCESS DELIVERY: $deliveryName ==="
        $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Quote-ProcessArgument $Receiver),'-Root',(Quote-ProcessArgument $Root),'-Python',(Quote-ProcessArgument $Python),'-DeliveryRoot',(Quote-ProcessArgument $processingPath))
        $process = Start-Process -FilePath $PowerShellHost -ArgumentList $args -WorkingDirectory $Repo -NoNewWindow -PassThru -RedirectStandardOutput $receiverStdout -RedirectStandardError $receiverStderr
        $process.WaitForExit(); $process.Refresh()
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
}
finally {
    if ($null -ne $ProcessorLock) { $ProcessorLock.Dispose(); $ProcessorLock = $null }
    if ($OwnsProcessorLock) { Remove-Item $ProcessorLockPath -Force -ErrorAction SilentlyContinue }
}
