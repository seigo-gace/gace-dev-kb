param(
    [string]$Root = 'F:\G-ACE-KB',
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$RuntimePython = Join-Path $Root 'runtime\mcp-vector-search\Scripts\python.exe'
$SearchRoot = Join-Path $Root 'data\knowledge-search'
$Config = Join-Path $SearchRoot '.mcp-vector-search\config.json'
$Test = Join-Path $Repo 'tests\mcp_knowledge_client_e2e.py'
$Verify = Join-Path $Repo 'tests\verify-mvs-windows.ps1'
$Bootstrap = Join-Path $Repo 'scripts\bootstrap-mvs-windows.ps1'

foreach ($p in @($Repo, $RuntimePython, $SearchRoot, $Config, $Test, $Verify, $Bootstrap)) {
    if (-not (Test-Path $p)) { throw "REQUIRED_PATH_MISSING=$p" }
}

Write-Host '=== VERIFY MCP RUNTIME COMPATIBILITY ==='
$needsRepair = $false
try {
    & $Verify -Root $Root
}
catch {
    $needsRepair = $true
    Write-Host "MCP_COMPAT_VERIFY_NEEDS_REPAIR=$($_.Exception.Message)"
}

if ($needsRepair) {
    Write-Host '=== REPAIR MCP RUNTIME COMPATIBILITY ==='
    & $Bootstrap -Root $Root
    if ($LASTEXITCODE -ne 0) { throw "MCP_COMPAT_BOOTSTRAP_FAILED=$LASTEXITCODE" }

    Write-Host '=== REVERIFY MCP RUNTIME COMPATIBILITY ==='
    & $Verify -Root $Root
}

Write-Host '=== MCP KNOWLEDGE CLIENT E2E ==='
$env:PYTHONDONTWRITEBYTECODE = '1'

& $RuntimePython -B $Test `
    --python $RuntimePython `
    --project-root $SearchRoot `
    --timeout $TimeoutSeconds

if ($LASTEXITCODE -ne 0) {
    throw "GACE_MCP_CLIENT_E2E_FAILED=$LASTEXITCODE"
}

Write-Host 'GACE_MCP_WINDOWS_E2E=PASS'
