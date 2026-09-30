param(
    [string]$Root = 'F:\G-ACE-KB',
    [string]$Python = 'D:\Development\Runtime\Python313\python.exe'
)

$ErrorActionPreference = 'Stop'
$Runtime = Join-Path $Root 'runtime\mcp-vector-search'
$Py = Join-Path $Runtime 'Scripts\python.exe'
$Mvs = Join-Path $Runtime 'Scripts\mcp-vector-search.exe'

if (-not (Test-Path $Python)) { throw "PYTHON_NOT_FOUND=$Python" }

if (-not (Test-Path $Py)) {
    & $Python -m venv $Runtime
    if ($LASTEXITCODE -ne 0) { throw "VENV_CREATE_FAILED=$LASTEXITCODE" }
}

& $Py -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "PIP_UPGRADE_FAILED=$LASTEXITCODE" }

& $Py -m pip install 'mcp-vector-search==4.1.14'
if ($LASTEXITCODE -ne 0) { throw "MVS_INSTALL_FAILED=$LASTEXITCODE" }

$Site = Join-Path $Runtime 'Lib\site-packages\mcp_vector_search'
$Main = Join-Path $Site 'cli\main.py'
$Output = Join-Path $Site 'cli\output.py'

if (-not (Test-Path $Main)) { throw "MVS_MAIN_NOT_FOUND=$Main" }
if (-not (Test-Path $Output)) { throw "MVS_OUTPUT_NOT_FOUND=$Output" }

$mainText = Get-Content $Main -Raw
if ($mainText -match '(?m)^import resource\s*$') {
    $mainText = $mainText -replace '(?m)^import resource\s*$', "if sys.platform != \"win32\":`r`n    import resource"
    Set-Content $Main -Value $mainText -Encoding UTF8
}

$outputText = Get-Content $Output -Raw
$needle = @'
            relevance_score = result._original_similarity
            combined_score = result.similarity_score
'@
$replacement = @'
            relevance_score = result._original_similarity
            combined_score = result.similarity_score

            # G-ACE Windows/docs compatibility: documentation chunks can
            # have no original similarity. Use the final score for display.
            if relevance_score is None:
                relevance_score = combined_score
'@
if ($outputText.Contains($needle) -and -not $outputText.Contains('if relevance_score is None:')) {
    $outputText = $outputText.Replace($needle, $replacement)
    Set-Content $Output -Value $outputText -Encoding UTF8
}

& $Mvs --help *> $null
if ($LASTEXITCODE -ne 0) { throw "MVS_HELP_FAILED=$LASTEXITCODE" }

& $Mvs doctor
if ($LASTEXITCODE -ne 0) { throw "MVS_DOCTOR_FAILED=$LASTEXITCODE" }

Write-Host 'MVS_WINDOWS_BOOTSTRAP=PASS'
Write-Host "RUNTIME=$Runtime"
Write-Host 'VERSION=4.1.14'
