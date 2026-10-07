$ErrorActionPreference='Stop'
$project='G-ACE Development Platform'
$r='F:\G-ACE-KB\repo'
$ref='refs/remotes/origin/ops/p014-diagnostic-reflect-command-20261007'
$tmp=Join-Path $env:TEMP 'gace-p014-gateway-client-probe.py'
$rc=0
$err='NONE'
Write-Output '========== GACE_RESULT_BEGIN =========='
Write-Output "PROJECT=$project"
Write-Output 'ACTION=P014_GATEWAY_CLIENT_PROBE'
Write-Output "PWD=$r"
try {
    Set-Location $r
    & git fetch --no-tags origin 'refs/heads/ops/p014-diagnostic-reflect-command-20261007:refs/remotes/origin/ops/p014-diagnostic-reflect-command-20261007'
    if($LASTEXITCODE -ne 0){throw 'COMMAND_FETCH_FAILED'}
    $spec=$ref + ':.gace-control/command-validation/p014-gateway-client-probe.py'
    & git show $spec > $tmp
    if($LASTEXITCODE -ne 0){throw 'COMMAND_MATERIALIZE_FAILED'}
    & python $tmp
    $probeRc=$LASTEXITCODE
    if($probeRc -ne 0){throw "PYTHON_PROBE_FAILED=$probeRc"}
    Write-Output 'VERIFY=P014_GATEWAY_CLIENT_PROBE_COMPLETE'
}
catch {
    $rc=1
    $err=$_.Exception.Message
    Write-Output 'VERIFY=FAIL'
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Write-Output "EXIT_CODE=$rc"
    Write-Output "ERROR=$err"
    Write-Output "PROJECT_END=$project"
    Write-Output '========== GACE_RESULT_END =========='
}
if($rc -ne 0){throw $err}
