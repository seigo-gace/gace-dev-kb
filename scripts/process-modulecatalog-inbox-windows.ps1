param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$InboxRoot = '',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe'
)

$ErrorActionPreference = 'Stop'
if (-not $InboxRoot) { $InboxRoot = Join-Path $Root 'data\knowledge-inbox\modulecatalog\ready' }
$Repo = Join-Path $Root 'repo'
$Receiver = Join-Path $Repo 'scripts\receive-modulecatalog-kbdata-windows.ps1'
if (-not (Test-Path $Receiver)) { throw "RECEIVER_MISSING=$Receiver" }
New-Item -ItemType Directory -Path $InboxRoot -Force | Out-Null

$Deliveries = @(Get-ChildItem $InboxRoot -Directory | Sort-Object Name)
if ($Deliveries.Count -eq 0) {
    Write-Host "GACE_MODULECATALOG_INBOX=PASS READY=0 ROOT=$InboxRoot"
    exit 0
}

$Processed = 0
foreach ($delivery in $Deliveries) {
    $manifest = Join-Path $delivery.FullName 'manifest.json'
    if (-not (Test-Path $manifest)) {
        Write-Host "GACE_MODULECATALOG_INBOX_SKIP=NO_MANIFEST DELIVERY=$($delivery.FullName)"
        continue
    }
    Write-Host "=== PROCESS DELIVERY: $($delivery.Name) ==="
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Receiver -Root $Root -Python $Python -DeliveryRoot $delivery.FullName
    if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_INBOX_DELIVERY_FAILED=$($delivery.FullName):$LASTEXITCODE" }
    $Processed++
}
Write-Host "GACE_MODULECATALOG_INBOX=PASS READY=$($Deliveries.Count) PROCESSED=$Processed ROOT=$InboxRoot"
