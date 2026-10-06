param(
    [string]$ProcessorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\process-gace-kb-chat-github-bridge-windows.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ProcessorPath)) { throw "CHAT_BRIDGE_PROCESSOR_MISSING=$ProcessorPath" }

$sourceLines = @(Get-Content -Path $ProcessorPath)
$requestLine = @($sourceLines | Where-Object { $_ -like '$RequestPathPattern = *' })
$resultLine = @($sourceLines | Where-Object { $_ -like '$ResultPathPattern = *' })
if ($requestLine.Count -ne 1) { throw "CHAT_BRIDGE_REQUEST_PATTERN_LINE_COUNT=$($requestLine.Count)" }
if ($resultLine.Count -ne 1) { throw "CHAT_BRIDGE_RESULT_PATTERN_LINE_COUNT=$($resultLine.Count)" }

$requestPattern = (($requestLine[0] -split '=',2)[1]).Trim().Trim("'")
$resultPattern = (($resultLine[0] -split '=',2)[1]).Trim().Trim("'")

$validRequests = @(
    '.gace-control/requests/req-chat-kb-e2e-search-001.json',
    '.gace-control/requests/a.json',
    '.gace-control/requests/A_1-2.3.json'
)
$invalidRequests = @(
    'gace-control/requests/req.json',
    '.gace-control/request/req.json',
    '.gace-control/requests/.json',
    '.gace-control/requests/../req.json',
    '.gace-control/requests/req.txt'
)
$validResults = @(
    '.gace-control/results/req-chat-kb-e2e-search-001.json',
    '.gace-control/results/a.json'
)
$invalidResults = @(
    'gace-control/results/req.json',
    '.gace-control/result/req.json',
    '.gace-control/results/.json',
    '.gace-control/results/req.txt'
)

foreach ($path in $validRequests) {
    if ($path -notmatch $requestPattern) { throw "CHAT_BRIDGE_VALID_REQUEST_REJECTED=$path PATTERN=$requestPattern" }
}
foreach ($path in $invalidRequests) {
    if ($path -match $requestPattern) { throw "CHAT_BRIDGE_INVALID_REQUEST_ACCEPTED=$path PATTERN=$requestPattern" }
}
foreach ($path in $validResults) {
    if ($path -notmatch $resultPattern) { throw "CHAT_BRIDGE_VALID_RESULT_REJECTED=$path PATTERN=$resultPattern" }
}
foreach ($path in $invalidResults) {
    if ($path -match $resultPattern) { throw "CHAT_BRIDGE_INVALID_RESULT_ACCEPTED=$path PATTERN=$resultPattern" }
}

Write-Host "GACE_KB_CHAT_PATH_FILTER=PASS REQUEST_PATTERN=$requestPattern RESULT_PATTERN=$resultPattern"
