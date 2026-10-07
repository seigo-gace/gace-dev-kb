$ErrorActionPreference='Stop'
$project='G-ACE Development Platform'
$log='F:\G-ACE-KB\data\knowledge-intake\chat-bridge\watcher.jsonl'
$task='G-ACE-KB-ChatGitHubBridge'
$request='req-p014-live-e2e-20261007-03'
$rc=0
$err='NONE'
Write-Output '========== GACE_RESULT_BEGIN =========='
Write-Output "PROJECT=$project"
Write-Output 'ACTION=P014_REQUEST_READBACK'
Write-Output "PWD=F:\G-ACE-KB\repo"
try {
    $state=(Get-ScheduledTask -TaskName $task).State
    Write-Output "TASK_STATE=$state"
    if(-not (Test-Path $log)){throw 'WATCHER_LOG_MISSING'}
    $line=Get-Content $log -Tail 120 | Where-Object { $_ -like "*$request*" } | Select-Object -Last 1
    if(-not $line){
        Write-Output 'REQUEST_LOG=NOT_FOUND'
        Write-Output 'LOGGER_STATUS=UNKNOWN'
        Write-Output 'LOGGER_REASON=UNKNOWN'
    }
    else {
        $obj=$line | ConvertFrom-Json
        $detail=[string]$obj.detail
        $status=[regex]::Match($detail,'GACE_KB_TGZERO_LOG=(SENT|DISABLED|FAILED)\b').Groups[1].Value
        $reason=[regex]::Match($detail,'REASON=([A-Z0-9_]+)\b').Groups[1].Value
        if(-not $status){$status='UNKNOWN'}
        if(-not $reason){$reason='UNKNOWN'}
        Write-Output 'REQUEST_LOG=FOUND'
        Write-Output "WATCHER_STATUS=$($obj.status)"
        Write-Output "LOGGER_STATUS=$status"
        Write-Output "LOGGER_REASON=$reason"
    }
    Write-Output 'VERIFY=P014_REQUEST_READBACK_COMPLETE'
}
catch {
    $rc=1
    $err=$_.Exception.Message
    Write-Output 'VERIFY=FAIL'
}
finally {
    Write-Output "EXIT_CODE=$rc"
    Write-Output "ERROR=$err"
    Write-Output "PROJECT_END=$project"
    Write-Output '========== GACE_RESULT_END =========='
}
if($rc -ne 0){throw $err}
