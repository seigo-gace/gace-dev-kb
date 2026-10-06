param(
    [string]$ProcessorPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\process-gace-kb-chat-github-bridge-windows.ps1'),
    [string]$TaskInstallerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\configure-gace-kb-chat-github-bridge-task-windows.ps1')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ProcessorPath)) { throw "CHAT_BRIDGE_PROCESSOR_MISSING=$ProcessorPath" }

$requestPattern = '^[.]gace-control/requests/[A-Za-z0-9][A-Za-z0-9._-]{0,127}[.]json$'
$resultPattern = '^[.]gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}[.]json$'
$source = Get-Content -Path $ProcessorPath -Raw
$taskInstallerSource = Get-Content -Path $TaskInstallerPath -Raw

if (-not $source.Contains($requestPattern)) { throw 'CHAT_BRIDGE_REQUEST_FILTER_SOURCE_MISMATCH' }
if (-not $source.Contains($resultPattern)) { throw 'CHAT_BRIDGE_RESULT_FILTER_SOURCE_MISMATCH' }

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
    if ($path -notmatch $requestPattern) { throw "CHAT_BRIDGE_VALID_REQUEST_REJECTED=$path" }
}
foreach ($path in $invalidRequests) {
    if ($path -match $requestPattern) { throw "CHAT_BRIDGE_INVALID_REQUEST_ACCEPTED=$path" }
}
foreach ($path in $validResults) {
    if ($path -notmatch $resultPattern) { throw "CHAT_BRIDGE_VALID_RESULT_REJECTED=$path" }
}
foreach ($path in $invalidResults) {
    if ($path -match $resultPattern) { throw "CHAT_BRIDGE_INVALID_RESULT_ACCEPTED=$path" }
}

if (-not $taskInstallerSource.Contains("`$TaskPath = '\'")) { throw 'CHAT_BRIDGE_TASK_ROOT_PATH_INVALID' }
if ($taskInstallerSource.Contains("`$TaskPath = '\\'")) { throw 'CHAT_BRIDGE_TASK_ROOT_PATH_DOUBLE_SEPARATOR' }

Write-Host 'GACE_KB_CHAT_PATH_FILTER=PASS'
if (-not $taskInstallerSource.Contains("'-WindowStyle','Hidden'")) { throw 'CHAT_BRIDGE_TASK_WINDOWSTYLE_NOT_HIDDEN' }
$watcherPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\watch-gace-kb-chat-github-bridge-windows.ps1'
$watcherSource = Get-Content -Path $watcherPath -Raw
if (-not $watcherSource.Contains('-WindowStyle Hidden')) { throw 'CHAT_BRIDGE_WATCHER_CHILD_WINDOWSTYLE_NOT_HIDDEN' }

Write-Host 'GACE_KB_CHAT_TASK_PATH=PASS'
Write-Host 'GACE_KB_CHAT_HIDDEN_WINDOW=PASS'
