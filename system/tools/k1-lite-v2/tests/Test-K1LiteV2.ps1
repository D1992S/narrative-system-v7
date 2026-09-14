[CmdletBinding()]
param([string]$PythonPath = 'python.exe')

$ErrorActionPreference = 'Stop'
$python = if ([IO.Path]::IsPathRooted($PythonPath)) {
    (Resolve-Path -LiteralPath $PythonPath).Path
} else {
    (Get-Command -Name $PythonPath -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
}

$testPath = Join-Path $PSScriptRoot 'test_k1_lite_v2.py'
$pdfLayoutTestPath = Join-Path $PSScriptRoot 'test_pdf_layout_fixtures.py'
$previousNoBytecode = [Environment]::GetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', 'Process')
try {
    [Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', '1', 'Process')
    & $python $testPath
    if ($LASTEXITCODE -ne 0) { throw "K1_LITE_V2_TEST_FAIL: exit=$LASTEXITCODE" }
    & $python (Join-Path $PSScriptRoot 'test_efficiency.py')
    if ($LASTEXITCODE -ne 0) { throw 'K1_EFFICIENCY_TEST_FAIL' }
    & $python (Join-Path $PSScriptRoot 'test_work_cycle.py')
    if ($LASTEXITCODE -ne 0) { throw 'K1_WORK_CYCLE_TEST_FAIL' }
    & $python $pdfLayoutTestPath
    if ($LASTEXITCODE -ne 0) { throw "K1_LITE_V2_PDF_LAYOUT_TEST_FAIL: exit=$LASTEXITCODE" }
} finally {
    [Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', $previousNoBytecode, 'Process')
}
'K1_LITE_V2_TEST_PASS'
