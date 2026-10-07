$ErrorActionPreference='Stop'
$project='G-ACE Development Platform'
$r='F:\G-ACE-KB\repo'
$task='G-ACE-KB-ChatGitHubBridge'
$expected='f7ed3958b762306910c0938ad7780c2bf72d98af'
$rc=0
$err='NONE'
$stopped=$false
Write-Output '========== GACE_RESULT_BEGIN =========='
Write-Output "PROJECT=$project"
Write-Output 'ACTION=P014_DIAGNOSTIC_SOURCE_REFLECT'
try {
    Set-Location $r
    Write-Output "PWD=$(Get-Location)"
    $dirty=@(& git status --porcelain --untracked-files=no)
    if($dirty.Count -ne 0){throw 'TRACKED_DIRTY_ABORT'}
    & git fetch --no-tags origin 'refs/heads/main:refs/remotes/origin/main'
    if($LASTEXITCODE -ne 0){throw 'MAIN_FETCH_FAILED'}
    $remote=(& git rev-parse 'refs/remotes/origin/main').Trim()
    if($remote -ne $expected){throw "REMOTE_HEAD_MISMATCH=$remote"}
    Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
    $stopped=$true
    & git switch -C 'runtime/p014-live-e2e-20261007' 'origin/main'
    if($LASTEXITCODE -ne 0){throw 'SOURCE_SWITCH_FAILED'}
    $head=(& git rev-parse HEAD).Trim()
    if($head -ne $expected){throw "HEAD_MISMATCH=$head"}
    Start-ScheduledTask -TaskName $task
    $stopped=$false
    Start-Sleep -Seconds 3
    $state=(Get-ScheduledTask -TaskName $task).State
    if($state -ne 'Running'){throw "TASK_NOT_RUNNING=$state"}
    $url=if([Environment]::GetEnvironmentVariable('GACE_EVENT_GATEWAY_URL','User')){'CONFIGURED'}else{'MISSING'}
    $token=if([Environment]::GetEnvironmentVariable('GACE_EVENT_GATEWAY_TOKEN','User')){'CONFIGURED'}else{'MISSING'}
    Write-Output "HEAD=$head"
    Write-Output "TASK_STATE=$state"
    Write-Output "GATEWAY_URL=$url"
    Write-Output "GATEWAY_TOKEN=$token"
    Write-Output 'VERIFY=P014_DIAGNOSTIC_SOURCE_READY'
}
catch {
    $rc=1
    $err=$_.Exception.Message
    Write-Output 'VERIFY=FAIL'
}
finally {
    if($stopped){Start-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue}
    Write-Output "EXIT_CODE=$rc"
    Write-Output "ERROR=$err"
    Write-Output "PROJECT_END=$project"
    Write-Output '========== GACE_RESULT_END =========='
}
if($rc -ne 0){throw $err}
