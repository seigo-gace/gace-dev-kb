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

# Exercise the actual hydration block with fixture User values; never alter User scope.
$tokens = $null
$parseErrors = $null
$watcherAst = [System.Management.Automation.Language.Parser]::ParseFile($watcherPath,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'CHAT_BRIDGE_WATCHER_PARSE_FAILED' }
$hydration = $watcherAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.ForEachStatementAst] -and
    $node.Extent.Text.Contains("[Environment]::GetEnvironmentVariable(`$name,'User')")
},$true)
if ($null -eq $hydration) { throw 'CHAT_BRIDGE_USER_ENV_IMPORT_MISSING' }
$envNames = @('GACE_EVENT_GATEWAY_URL','GACE_EVENT_GATEWAY_TOKEN')
$importedNames = @($hydration.Condition.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
},$true) | ForEach-Object { $_.Value })
if (($importedNames -join ',') -ne ($envNames -join ',')) { throw 'CHAT_BRIDGE_ENV_IMPORT_ALLOWLIST_INVALID' }
if (-not $hydration.Extent.Text.Contains("[Environment]::SetEnvironmentVariable(`$name,`$userValue,'Process')")) {
    throw 'CHAT_BRIDGE_PROCESS_ENV_IMPORT_MISSING'
}
if ($hydration.Extent.StartOffset -gt $watcherSource.IndexOf('while ($true)')) { throw 'CHAT_BRIDGE_ENV_IMPORT_TOO_LATE' }
if ($hydration.Extent.Text -match '(Write-|Add-Content|Out-|Set-Content)') { throw 'CHAT_BRIDGE_ENV_IMPORT_OUTPUT_FORBIDDEN' }
$hydrationProbe = [scriptblock]::Create($hydration.Extent.Text.Replace(
    "[Environment]::GetEnvironmentVariable(`$name,'User')", '$fixtureUserValues[$name]'))
$savedEnv = @{}
foreach ($name in $envNames) { $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    $fixtureUserValues = @{
        GACE_EVENT_GATEWAY_URL = 'https://fixture.invalid'
        GACE_EVENT_GATEWAY_TOKEN = 'FIXTURE_NOT_A_REAL_SECRET'
    }
    $hydrationOutput = @(. $hydrationProbe 6>&1)
    if ($hydrationOutput.Count -ne 0) { throw 'CHAT_BRIDGE_ENV_VALUE_OUTPUT_DETECTED' }
    foreach ($name in $envNames) {
        if ([Environment]::GetEnvironmentVariable($name,'Process') -ne $fixtureUserValues[$name]) {
            throw 'CHAT_BRIDGE_ENV_HYDRATION_FAILED'
        }
    }
    $fixtureUserValues = @{}
    $hydrationOutput = @(. $hydrationProbe 6>&1)
    if ($hydrationOutput.Count -ne 0) { throw 'CHAT_BRIDGE_ABSENT_ENV_OUTPUT_DETECTED' }
    foreach ($name in $envNames) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name,'Process'))) {
            throw 'CHAT_BRIDGE_ABSENT_USER_ENV_NOT_CLEARED'
        }
    }
} finally {
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name,$savedEnv[$name],'Process') }
}
Write-Host 'GACE_KB_CHAT_USER_PROCESS_ENV=PASS SECRET_OUTPUT=NO'

# Reuse the watcher's complete poll try/catch, changing only the native child
# command to a harmless Python fixture. Keep stderr capture and classification.
$pollAst = $watcherAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.TryStatementAst] -and
    $node.CatchClauses.Count -gt 0 -and
    $node.Body.Extent.Text.Contains("Write-BridgeEvent -Status 'POLL_PASS'")
},$true)
if ($null -eq $pollAst) { throw 'CHAT_BRIDGE_POLL_CAPTURE_MISSING' }
$childLine = ($pollAst.Extent.Text -split "`r?`n" | Where-Object { $_ -match '\$output = @\(& powershell[.]exe ' })
if (@($childLine).Count -ne 1) { throw 'CHAT_BRIDGE_NATIVE_CAPTURE_AMBIGUOUS' }
$pollProbe = [scriptblock]::Create($pollAst.Extent.Text.Replace(
    $childLine.Trim(), '$output = @(& python -c $nativeProbe 2>&1)'))
function Write-BridgeEvent {
    param([string]$Status,[string]$Detail='')
    $script:probeEvent = @{ status=$Status; detail=$Detail }
}
foreach ($exitCode in @(0,7)) {
    $nativeProbe = "import sys; print('GACE_KB_TGZERO_LOG=SENT'); sys.stderr.write('To https://github.com/test/repo.git\n'); sys.exit($exitCode)"
    $script:probeEvent = $null
    . $pollProbe
    $expected = if ($exitCode -eq 0) { 'POLL_PASS' } else { 'POLL_FAIL' }
    if ($script:probeEvent.status -ne $expected) { throw 'CHAT_BRIDGE_NATIVE_EXIT_CLASSIFICATION_FAILED' }
    if (-not $script:probeEvent.detail.Contains('To https://github.com/test/repo.git')) { throw 'CHAT_BRIDGE_STDERR_DIAGNOSTIC_LOST' }
    if (-not $script:probeEvent.detail.Contains('GACE_KB_TGZERO_LOG=SENT')) { throw 'CHAT_BRIDGE_LOG_MARKER_LOST' }
    if ($ErrorActionPreference -ne 'Stop') { throw 'CHAT_BRIDGE_ERROR_PREFERENCE_NOT_RESTORED' }
}
foreach ($marker in @('SENT','DISABLED','FAILED')) {
    foreach ($exitCode in @(0,7)) {
        $nativeProbe = "import sys; print('GACE_KB_TGZERO_LOG=$marker'); print('x' * 5000); sys.exit($exitCode)"
        . $pollProbe
        if ($script:probeEvent.detail.Length -gt 4000) { throw 'CHAT_BRIDGE_DETAIL_BOUND_EXCEEDED' }
        if (-not $script:probeEvent.detail.Contains("GACE_KB_TGZERO_LOG=$marker")) { throw 'CHAT_BRIDGE_BOUNDED_LOG_MARKER_LOST' }
    }
}
$exceptionProbe = [scriptblock]::Create($pollAst.Extent.Text.Replace($childLine.Trim(), "throw 'FIXTURE_EXCEPTION'"))
. $exceptionProbe
if ($script:probeEvent.status -ne 'POLL_EXCEPTION') { throw 'CHAT_BRIDGE_REAL_EXCEPTION_NOT_PRESERVED' }
Write-Host 'GACE_KB_CHAT_NATIVE_STDERR=PASS EXIT_FAILURE=PASS DETAIL_BOUND=PASS'

$processorAst = [System.Management.Automation.Language.Parser]::ParseFile($ProcessorPath,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'CHAT_BRIDGE_PROCESSOR_PARSE_FAILED' }
$pushAst = $processorAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.TryStatementAst] -and
    $null -ne $node.Finally -and
    $node.Finally.Extent.Text.Contains('$ErrorActionPreference = $previousPreference') -and
    $node.Body.Extent.Text.Contains('$pushOutput = @(& git ')
},$true)
if ($null -eq $pushAst) { throw 'CHAT_BRIDGE_PUSH_CAPTURE_MISSING' }
$pushLine = ($pushAst.Extent.Text -split "`r?`n" | Where-Object { $_ -match '\$pushOutput = @\(& git ' })
$pushProbe = [scriptblock]::Create($pushAst.Extent.Text.Replace(
    $pushLine.Trim(), '$pushOutput = @(& python -c $nativeProbe 2>&1)'))
foreach ($exitCode in @(0,7)) {
    $nativeProbe = "import sys; sys.stderr.write('To https://github.com/test/repo.git\n'); sys.exit($exitCode)"
    $previousPreference = $ErrorActionPreference
    . $pushProbe
    if ($pushExit -ne $exitCode) { throw 'CHAT_BRIDGE_PUSH_EXIT_CODE_LOST' }
    if ($ErrorActionPreference -ne 'Stop') { throw 'CHAT_BRIDGE_PUSH_PREFERENCE_NOT_RESTORED' }
}
if (-not $source.Contains('if ($pushExit -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }')) {
    throw 'CHAT_BRIDGE_PUSH_FAILURE_GUARD_MISSING'
}
Write-Host 'GACE_KB_CHAT_GIT_PUSH_STDERR=PASS REAL_FAILURE_GUARD=PASS'
