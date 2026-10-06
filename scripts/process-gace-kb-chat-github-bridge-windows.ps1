param(
    [string]$Root = 'F:\\G-ACE-KB',
    [string]$ControlBranch = 'control/gace-kb-chat-bridge-v1',
    [int]$MaxRequests = 10,
    [int]$TimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'

$Repo = Join-Path $Root 'repo'
$RuntimePython = Join-Path $Root 'runtime\\mcp-vector-search\\Scripts\\python.exe'
$Bridge = Join-Path $Repo 'scripts\\gace_kb_chat_bridge.py'
$SearchRoot = Join-Path $Root 'data\\knowledge-search'
$CurrentReusable = Join-Path $Root 'data\\knowledge-sources\\accepted\\modulecatalog-reusable-current'
$Metadata = Join-Path $CurrentReusable 'knowledge-metadata.jsonl'
$Relationships = Join-Path $CurrentReusable 'relationships.jsonl'
$Cases = Join-Path $CurrentReusable 'cases.jsonl'
$ScratchRoot = Join-Path $Root 'data\\knowledge-intake\\chat-bridge\\tmp'
$RemoteRef = "refs/remotes/origin/$ControlBranch"
$RequestPathPattern = '^\.gace-control/requests/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json
foreach ($path in @($Repo,$RuntimePython,$Bridge,$SearchRoot,$Metadata,$Relationships,$Cases)) {
    if (-not (Test-Path $path)) { throw "CHAT_BRIDGE_REQUIRED_PATH_MISSING=$path" }
}
if ($MaxRequests -lt 1 -or $MaxRequests -gt 100) { throw "CHAT_BRIDGE_MAX_REQUESTS_INVALID=$MaxRequests" }
if ($TimeoutSeconds -lt 10 -or $TimeoutSeconds -gt 900) { throw "CHAT_BRIDGE_TIMEOUT_INVALID=$TimeoutSeconds" }

New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null

function Invoke-Git {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $Repo @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($code -ne 0) {
        throw "CHAT_BRIDGE_GIT_FAILED=$code ARGS=$($Arguments -join ' ') OUTPUT=$($output -join [Environment]::NewLine)"
    }
    return $output
}

$fetchSpec = ('refs/heads/{0}:{1}' -f $ControlBranch,$RemoteRef)
Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
$requestPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/requests') |
        Where-Object { $_ -match '^\.gace-control/requests/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json
)
$resultPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/results') |
        Where-Object { $_ -match '^\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
 }
)
$resultPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/results') |
        Where-Object { $_ -match '^\\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\.json$' }
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
 }
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
 }
)
$resultPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/results') |
        Where-Object { $_ -match '^\\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\.json$' }
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"

$ResultPathPattern = '^\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json
foreach ($path in @($Repo,$RuntimePython,$Bridge,$SearchRoot,$Metadata,$Relationships,$Cases)) {
    if (-not (Test-Path $path)) { throw "CHAT_BRIDGE_REQUIRED_PATH_MISSING=$path" }
}
if ($MaxRequests -lt 1 -or $MaxRequests -gt 100) { throw "CHAT_BRIDGE_MAX_REQUESTS_INVALID=$MaxRequests" }
if ($TimeoutSeconds -lt 10 -or $TimeoutSeconds -gt 900) { throw "CHAT_BRIDGE_TIMEOUT_INVALID=$TimeoutSeconds" }

New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null

function Invoke-Git {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $Repo @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($code -ne 0) {
        throw "CHAT_BRIDGE_GIT_FAILED=$code ARGS=$($Arguments -join ' ') OUTPUT=$($output -join [Environment]::NewLine)"
    }
    return $output
}

$fetchSpec = ('refs/heads/{0}:{1}' -f $ControlBranch,$RemoteRef)
Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
$requestPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/requests') |
        Where-Object { $_ -match '^\.gace-control/requests/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json
)
$resultPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/results') |
        Where-Object { $_ -match '^\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
 }
)
$resultPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/results') |
        Where-Object { $_ -match '^\\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\.json$' }
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
 }
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
 }
)
$resultPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/results') |
        Where-Object { $_ -match '^\\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\.json$' }
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"


foreach ($path in @($Repo,$RuntimePython,$Bridge,$SearchRoot,$Metadata,$Relationships,$Cases)) {
    if (-not (Test-Path $path)) { throw "CHAT_BRIDGE_REQUIRED_PATH_MISSING=$path" }
}
if ($MaxRequests -lt 1 -or $MaxRequests -gt 100) { throw "CHAT_BRIDGE_MAX_REQUESTS_INVALID=$MaxRequests" }
if ($TimeoutSeconds -lt 10 -or $TimeoutSeconds -gt 900) { throw "CHAT_BRIDGE_TIMEOUT_INVALID=$TimeoutSeconds" }

New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null

function Invoke-Git {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $Repo @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($code -ne 0) {
        throw "CHAT_BRIDGE_GIT_FAILED=$code ARGS=$($Arguments -join ' ') OUTPUT=$($output -join [Environment]::NewLine)"
    }
    return $output
}

$fetchSpec = ('refs/heads/{0}:{1}' -f $ControlBranch,$RemoteRef)
Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
$requestPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/requests') |
        Where-Object { $_ -match '^\.gace-control/requests/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json
)
$resultPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/results') |
        Where-Object { $_ -match '^\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.json
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
 }
)
$resultPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/results') |
        Where-Object { $_ -match '^\\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\.json$' }
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
 }
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
 }
)
$resultPaths = @(
    Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--','.gace-control/results') |
        Where-Object { $_ -match '^\\.gace-control/results/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\.json$' }
)
$resultSet = @{}
foreach ($path in $resultPaths) { $resultSet[$path] = $true }
$pending = @(
    $requestPaths |
        Where-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_)
            -not $resultSet.ContainsKey(".gace-control/results/$name.json")
        } |
        Sort-Object
)

if ($pending.Count -eq 0) {
    Write-Host 'GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=0 PENDING=0'
    return
}

$processed = 0
foreach ($requestPath in $pending) {
    if ($processed -ge $MaxRequests) { break }
    $requestId = [System.IO.Path]::GetFileNameWithoutExtension($requestPath)
    $resultPath = ".gace-control/results/$requestId.json"
    $scratch = Join-Path $ScratchRoot ($requestId + '-' + [Guid]::NewGuid().ToString('N'))
    $requestFile = Join-Path $scratch 'request.json'
    $resultFile = Join-Path $scratch 'result.json'
    $worktree = Join-Path $scratch 'control'
    $localBranch = 'chat-bridge-worker-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $showSpec = ('{0}:{1}' -f $RemoteRef,$requestPath)
        $requestText = (Invoke-Git @('show',$showSpec) | Out-String)
        [System.IO.File]::WriteAllText($requestFile,$requestText,[System.Text.UTF8Encoding]::new($false))

        $bridgeArgs = @('-B',$Bridge,'--request',$requestFile,'--result',$resultFile,'--python',$RuntimePython,'--project-root',$SearchRoot,'--metadata',$Metadata,'--relationships',$Relationships,'--cases',$Cases,'--timeout',[string]$TimeoutSeconds)
        & $RuntimePython @bridgeArgs
        $bridgeExit = $LASTEXITCODE
        if (-not (Test-Path $resultFile)) { throw "CHAT_BRIDGE_RESULT_MISSING=$requestId" }

        Invoke-Git @('fetch','--no-tags','origin',$fetchSpec) | Out-Null
        $existing = @(Invoke-Git @('ls-tree','-r','--name-only',$RemoteRef,'--',$resultPath))
        if ($existing -contains $resultPath) {
            Write-Host "GACE_KB_CHAT_REQUEST=PASS REQUEST=$requestId STATUS=ALREADY_RESULT"
            $processed += 1
            continue
        }

        Invoke-Git @('worktree','add','-b',$localBranch,$worktree,$RemoteRef) | Out-Null
        $destination = Join-Path $worktree ($resultPath -replace '/','\\')
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        [System.IO.File]::WriteAllText($destination,[System.IO.File]::ReadAllText($resultFile,[System.Text.Encoding]::UTF8),[System.Text.UTF8Encoding]::new($false))
        & git -C $worktree add -- $resultPath
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_ADD_FAILED=$requestId" }
        & git -C $worktree -c user.name='G-ACE KB Chat Bridge' -c user.email='gace-kb-chat-bridge@users.noreply.github.com' commit -m "bridge: result $requestId"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_COMMIT_FAILED=$requestId" }
        & git -C $worktree push origin "HEAD:refs/heads/$ControlBranch"
        if ($LASTEXITCODE -ne 0) { throw "CHAT_BRIDGE_GIT_PUSH_FAILED=$requestId" }

        $status = if ($bridgeExit -eq 0) { 'PASS' } else { 'FAIL_RESULT_PUBLISHED' }
        Write-Host "GACE_KB_CHAT_REQUEST=$status REQUEST=$requestId RESULT=$resultPath"
        $processed += 1
    }
    finally {
        if (Test-Path $worktree) { & git -C $Repo worktree remove --force $worktree 2>$null | Out-Null }
        & git -C $Repo branch -D $localBranch 2>$null | Out-Null
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "GACE_KB_CHAT_GITHUB_BRIDGE=PASS PROCESSED=$processed PENDING=$($pending.Count - $processed)"
