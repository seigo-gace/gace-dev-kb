Set-Location 'F:\G-ACE-KB\repo'
$project='Catalog'
$expectedBeforeBranch='feat/reusable-asset-kb-schema-20261001'
$expectedBeforeHead='93230420430ecbf6f7a5c0303b01ca637da45775'
$targetBranch='feat/chat-github-kb-bridge-20261006'
$targetHead='56f30280c39ab5d9c095ecae75cc2b36d9dd330a'
$controlBranch='control/gace-kb-chat-bridge-v1'
$searchId='req-chat-kb-e2e-search-001'
$exactId='req-chat-kb-e2e-exact-001'
$gaceRc=0
$gaceError='NONE'
Write-Output '========== GACE_RESULT_BEGIN =========='
Write-Output "PROJECT=$project"
Write-Output "PWD=$(Get-Location)"
Write-Output 'ACTION=CHAT_GITHUB_KB_BRIDGE_ONE_SHOT_E2E'
$currentBranch=(& git branch --show-current 2>$null | Select-Object -First 1)
$before=(& git rev-parse HEAD 2>$null | Select-Object -First 1)
$dirty=@(& git status --porcelain --untracked-files=no 2>$null)
Write-Output "BEFORE_BRANCH=$currentBranch"
Write-Output "BEFORE_HEAD=$before"
if($currentBranch -ne $expectedBeforeBranch){$gaceRc=2;$gaceError='KB_BRANCH_MISMATCH'}
if($gaceRc -eq 0 -and $before -ne $expectedBeforeHead){$gaceRc=3;$gaceError='KB_HEAD_CHANGED'}
if($gaceRc -eq 0 -and $dirty.Count -ne 0){$gaceRc=4;$gaceError='KB_TRACKED_DIRTY'}
if($gaceRc -eq 0){& git fetch --no-tags origin "refs/heads/$targetBranch";if($LASTEXITCODE -ne 0){$gaceRc=5;$gaceError='KB_FETCH_FAILED'}}
if($gaceRc -eq 0){$remote=(& git rev-parse FETCH_HEAD 2>$null|Select-Object -First 1);Write-Output "REMOTE_HEAD=$remote";if($remote -ne $targetHead){$gaceRc=6;$gaceError='KB_REMOTE_HEAD_NOT_EXPECTED'}}
if($gaceRc -eq 0){& git show-ref --verify --quiet "refs/heads/$targetBranch";$exists=($LASTEXITCODE -eq 0);if($exists){$local=(& git rev-parse "refs/heads/$targetBranch" 2>$null|Select-Object -First 1);if($local -ne $targetHead){$gaceRc=7;$gaceError='KB_LOCAL_TARGET_BRANCH_CONFLICT'}else{& git switch $targetBranch;if($LASTEXITCODE -ne 0){$gaceRc=8;$gaceError='KB_SWITCH_FAILED'}}}else{& git switch -c $targetBranch --track "origin/$targetBranch";if($LASTEXITCODE -ne 0){$gaceRc=9;$gaceError='KB_CREATE_TRACKING_BRANCH_FAILED'}}}
$after=(& git rev-parse HEAD 2>$null|Select-Object -First 1)
Write-Output "AFTER_HEAD=$after"
if($gaceRc -eq 0 -and $after -ne $targetHead){$gaceRc=10;$gaceError='KB_POST_SWITCH_HEAD_MISMATCH'}
if($gaceRc -eq 0){$processor='F:\G-ACE-KB\repo\scripts\process-gace-kb-chat-github-bridge-windows.ps1';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $processor -Root 'F:\G-ACE-KB' -ControlBranch $controlBranch -MaxRequests 10 -TimeoutSeconds 240;$processorRc=$LASTEXITCODE;Write-Output "PROCESSOR_EXIT=$processorRc";if($processorRc -ne 0){$gaceRc=11;$gaceError='CHAT_BRIDGE_PROCESSOR_FAILED'}}
if($gaceRc -eq 0){& git fetch --no-tags origin "refs/heads/$controlBranch`:refs/remotes/origin/$controlBranch";if($LASTEXITCODE -ne 0){$gaceRc=12;$gaceError='CONTROL_FETCH_FAILED'}}
if($gaceRc -eq 0){$searchText=(& git show "refs/remotes/origin/$controlBranch`:.gace-control/results/$searchId.json" 2>$null|Out-String);if($LASTEXITCODE -ne 0){$gaceRc=13;$gaceError='SEARCH_RESULT_MISSING'}else{$search=$searchText|ConvertFrom-Json;Write-Output "SEARCH_STATUS=$($search.status)";if($search.status -ne 'PASS' -or [string]$search.result.mcp_text -notmatch 'approval-route-resolver'){$gaceRc=14;$gaceError='SEARCH_RESULT_INVALID'}}}
if($gaceRc -eq 0){$exactText=(& git show "refs/remotes/origin/$controlBranch`:.gace-control/results/$exactId.json" 2>$null|Out-String);if($LASTEXITCODE -ne 0){$gaceRc=15;$gaceError='EXACT_RESULT_MISSING'}else{$exact=$exactText|ConvertFrom-Json;Write-Output "EXACT_STATUS=$($exact.status)";Write-Output "EXACT_KNOWLEDGE_ID=$($exact.result.knowledge_id)";Write-Output "EXACT_RELATIONSHIPS=$(@($exact.result.relationships).Count)";Write-Output "EXACT_CASES=$(@($exact.result.cases).Count)";if($exact.status -ne 'PASS' -or $exact.result.knowledge_id -ne 'approval-route-resolver::logic'){$gaceRc=16;$gaceError='EXACT_RESULT_INVALID'}}}
$verify=if($gaceRc -eq 0){'CHAT_GITHUB_KB_BRIDGE_ONE_SHOT_PASS'}else{'FAIL'}
Write-Output "VERIFY=$verify"
Write-Output "EXIT_CODE=$gaceRc"
Write-Output "ERROR=$gaceError"
Write-Output "PROJECT_END=$project"
Write-Output '========== GACE_RESULT_END =========='
