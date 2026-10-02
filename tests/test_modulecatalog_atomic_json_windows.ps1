$ErrorActionPreference = 'Stop'

$Activator = Resolve-Path (Join-Path $PSScriptRoot '..\scripts\activate-modulecatalog-accepted-windows.ps1')
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $Activator,
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_.Message }
    throw 'ACTIVATOR_PARSE_FAILED'
}
$functionAst = $ast.Find(
    {
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Write-JsonAtomic'
    },
    $true
)
if ($null -eq $functionAst) { throw 'WRITE_JSON_ATOMIC_FUNCTION_MISSING' }
Invoke-Expression $functionAst.Extent.Text

$Root = Join-Path $env:TEMP ('gace-atomic-json-' + [Guid]::NewGuid().ToString('N'))
$Existing = Join-Path $Root 'receipt.json'
$New = Join-Path $Root 'marker.json'
$encoding = New-Object System.Text.UTF8Encoding($false)

try {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    [System.IO.File]::WriteAllText(
        $Existing,
        (([ordered]@{ status = 'ACCEPTED'; generation = 1 } | ConvertTo-Json) + [Environment]::NewLine),
        $encoding
    )

    Write-JsonAtomic -Value ([ordered]@{ status = 'ACTIVE'; generation = 2 }) -Path $Existing
    $existingState = Get-Content $Existing -Raw | ConvertFrom-Json
    if ([string]$existingState.status -ne 'ACTIVE' -or [int]$existingState.generation -ne 2) {
        throw 'EXISTING_JSON_REPLACE_CONTENT_MISMATCH'
    }

    Write-JsonAtomic -Value ([ordered]@{ status = 'ACTIVE'; generation = 1 }) -Path $New
    $newState = Get-Content $New -Raw | ConvertFrom-Json
    if ([string]$newState.status -ne 'ACTIVE' -or [int]$newState.generation -ne 1) {
        throw 'NEW_JSON_ATOMIC_CONTENT_MISMATCH'
    }

    $leftovers = @(Get-ChildItem $Root -File | Where-Object {
        $_.Name -like '*.tmp.*' -or $_.Name -like '*.replace-backup.*'
    })
    if ($leftovers.Count -ne 0) {
        throw ('ATOMIC_JSON_TEMP_LEFTOVERS=' + (($leftovers | Select-Object -ExpandProperty Name) -join ','))
    }

    Write-Host 'GACE_ATOMIC_JSON_WINDOWS_REGRESSION=PASS EXISTING_REPLACE=PASS NEW_FILE=PASS CLEANUP=PASS'
}
finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}
