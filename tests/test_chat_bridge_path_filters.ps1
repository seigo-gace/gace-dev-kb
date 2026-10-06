param(
    [string]$ProcessorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\process-gace-kb-chat-github-bridge-windows.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ProcessorPath)) { throw "CHAT_BRIDGE_PROCESSOR_MISSING=$ProcessorPath" }

$source = Get-Content -Path $ProcessorPath -Raw
$requestMatch = [regex]::Match($source, '\$RequestPathPattern\s*=\s*''([^'']+)''')
$resultMatch = [regex]::Match($source, '\$ResultPathPattern\s*=\s*''([^'']+)''')
if (-not $requestMatch.Success) { throw 'CHAT_BRIDGE_REQUEST_PATTERN_NOT_FOUND' }
if (-not $resultMatch.Success) { throw 'CHAT_BRIDGE_RESULT_PATTERN_NOT_FOUND' }

$requestPattern = $requestMatch.Groups[1].Value
$resultPattern = $resultMatch.Groups[1].Value

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
