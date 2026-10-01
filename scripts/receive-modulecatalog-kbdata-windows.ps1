param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe',
    [Parameter(Mandatory=$true)][string]$DeliveryRoot
)

$ErrorActionPreference = 'Stop'
$Repo = Join-Path $Root 'repo'
$Acceptor = Join-Path $Repo 'scripts\accept_modulecatalog_delivery.py'
$Activator = Join-Path $Repo 'scripts\activate-modulecatalog-accepted-windows.ps1'
$ManifestPath = Join-Path $DeliveryRoot 'manifest.json'
foreach ($path in @($Repo,$Python,$Acceptor,$Activator,$DeliveryRoot,$ManifestPath)) {
    if (-not (Test-Path $path)) { throw "REQUIRED_PATH_MISSING=$path" }
}

$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
if ([int]$Manifest.schema_version -ne 1 -or [string]$Manifest.format -ne 'gace.reusable-asset.v1') { throw 'DELIVERY_MANIFEST_FORMAT_UNSUPPORTED' }
if ([string]$Manifest.catalog.repository -ne 'seigo-gace/modular-catalog') { throw "DELIVERY_CATALOG_REPOSITORY_MISMATCH=$($Manifest.catalog.repository)" }
$CatalogCommit = [string]$Manifest.catalog.commit
if ($CatalogCommit.Length -ne 40) { throw "DELIVERY_CATALOG_COMMIT_INVALID=$CatalogCommit" }

$IntakeRoot = Join-Path $Root 'data\knowledge-intake\modulecatalog'
$AcceptedRoot = Join-Path $IntakeRoot "accepted\$CatalogCommit"
$ReceiptPath = Join-Path $IntakeRoot "receipts\$CatalogCommit.json"
New-Item -ItemType Directory -Path (Split-Path $AcceptedRoot) -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $ReceiptPath) -Force | Out-Null

Write-Host '=== KB RECEIVE: VALIDATE + ACCEPT TRANSPORTED DATA ==='
& $Python -B $Acceptor --delivery-root $DeliveryRoot --accepted-root $AcceptedRoot --receipt $ReceiptPath
if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_DELIVERY_ACCEPT_FAILED=$LASTEXITCODE" }
$Receipt = Get-Content $ReceiptPath -Raw | ConvertFrom-Json
if ([string]$Receipt.status -eq 'ACTIVE') {
    Write-Host "GACE_MODULECATALOG_RECEIVE=PASS IDEMPOTENT=YES STATUS=ACTIVE COMMIT=$CatalogCommit"
    Write-Host "RECEIPT=$ReceiptPath"
    exit 0
}
if ([string]$Receipt.status -ne 'ACCEPTED') { throw "DELIVERY_RECEIPT_STATUS_INVALID=$($Receipt.status)" }

Write-Host '=== KB OPERATE: INDEX + MCP + ATOMIC CURRENT SWITCH ==='
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Activator -Root $Root -AcceptedRoot $AcceptedRoot -ReceiptPath $ReceiptPath
if ($LASTEXITCODE -ne 0) { throw "MODULECATALOG_DELIVERY_ACTIVATION_FAILED=$LASTEXITCODE" }

$FinalReceipt = Get-Content $ReceiptPath -Raw | ConvertFrom-Json
if ([string]$FinalReceipt.status -ne 'ACTIVE' -or [string]$FinalReceipt.catalogCommit -ne $CatalogCommit) { throw 'FINAL_RECEIPT_NOT_ACTIVE' }
Write-Host "GACE_MODULECATALOG_RECEIVE=PASS STATUS=ACTIVE COMMIT=$CatalogCommit ASSETS=$($FinalReceipt.assetCount) RECORDS=$($FinalReceipt.knowledgeUnitCount)"
Write-Host "RECEIPT=$ReceiptPath"
