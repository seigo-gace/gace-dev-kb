$ErrorActionPreference='Stop'
$r='F:\G-ACE-KB\repo'
$ref='refs/remotes/origin/ops/p014-diagnostic-reflect-command-20261007'
$tmp=Join-Path $env:TEMP 'gace-p014-diagnostic-reflect.ps1'
Set-Location $r
& git fetch --no-tags origin 'refs/heads/ops/p014-diagnostic-reflect-command-20261007:refs/remotes/origin/ops/p014-diagnostic-reflect-command-20261007'
if($LASTEXITCODE -ne 0){throw 'COMMAND_FETCH_FAILED'}
$spec=$ref + ':.gace-control/command-validation/master-pc-p014-diagnostic-reflect.ps1'
& git show $spec > $tmp
if($LASTEXITCODE -ne 0){throw 'COMMAND_MATERIALIZE_FAILED'}
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp
    $rc=$LASTEXITCODE
}
finally {Remove-Item $tmp -Force -ErrorAction SilentlyContinue}
if($rc -ne 0){throw "P014_REFLECT_FAILED=$rc"}
