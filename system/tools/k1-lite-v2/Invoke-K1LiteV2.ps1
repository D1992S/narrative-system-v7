[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Plan','NextWork','ImportBatch','ImportResult','AddDecisions','AddVisual','AddReview','BuildViews','ValidateRun','VerifyBatch','InspectLayout','CompareTextTwins')]
    [string]$Action,
    [string]$SourcePath,
    [string]$ExpectedSourceSha256,
    [string]$PdfPath,
    [string]$ExpectedPdfSha256,
    [string]$RunDirectory,
    [string]$K0Path,
    [string]$ExpectedK0Sha256,
    [ValidateRange(1000, 1000000)]
    [int]$TargetMinCharacters = 12000,
    [ValidateRange(1000, 1000000)]
    [int]$TargetMaxCharacters = 18000,
    [ValidateSet(2,4,8)]
    [int]$CandidateLimit = 2,
    [string]$ResultPath,
    [string[]]$ResultPaths,
    [string]$DecisionPath,
    [string]$ReceiptPath,
    [string]$OutputDirectory,
    [string]$OutputPath,
    [string]$ExpectedLedgerSha256,
    [string]$FirstTextPath,
    [string]$FirstTextSha256,
    [string]$SecondTextPath,
    [string]$SecondTextSha256,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectDirectory,
    [string]$PythonPath = 'python.exe',
    [IO.FileStream]$InternalHeldProjectLock
)

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$isolationRoot = [IO.Path]::GetFullPath($ProjectDirectory)
if (-not (Test-Path -LiteralPath $isolationRoot -PathType Container)) {
    throw "PROJECT_DIRECTORY_NOT_FOUND: $isolationRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $isolationRoot 'sources') -PathType Container)) {
    throw "PROJECT_SOURCES_NOT_FOUND: $isolationRoot"
}
$projectItem = Get-Item -LiteralPath $isolationRoot -Force
if (($projectItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "PROJECT_REPARSE_POINT_BLOCKED: $isolationRoot"
}
$pythonScript = Join-Path $scriptRoot 'k1_lite_v2.py'
. (Join-Path (Split-Path -Parent $scriptRoot) 'Integrity-Receipts.ps1')
. (Join-Path (Split-Path -Parent $scriptRoot) 'Native-Python.ps1')
if ($null -ne $InternalHeldProjectLock) {
    $callerPath = if ($MyInvocation.ScriptName) { [IO.Path]::GetFullPath($MyInvocation.ScriptName) } else { '' }
    $allowedCaller = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $scriptRoot) 'Compile-K1LiteV2.ps1'))
    if (-not $callerPath.Equals($allowedCaller, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'INTERNAL_HELD_PROJECT_LOCK_UNAUTHORIZED'
    }
}

function Stop-V2([string]$Code, [string]$Detail = '') {
    if ($Detail) { throw "${Code}: $Detail" }
    throw $Code
}

function Resolve-Python([string]$Value) {
    if ([IO.Path]::IsPathRooted($Value)) {
        if (-not (Test-Path -LiteralPath $Value -PathType Leaf)) { Stop-V2 'PYTHON_UNAVAILABLE' $Value }
        return (Resolve-Path -LiteralPath $Value).Path
    }
    $command = Get-Command -Name $Value -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { Stop-V2 'PYTHON_UNAVAILABLE' $Value }
    return $command.Source
}

function Require([string]$Value, [string]$Code) {
    if ([string]::IsNullOrWhiteSpace($Value)) { Stop-V2 $Code }
}

function Assert-Sha([string]$Value, [string]$Code, [switch]$AllowCreateNew) {
    if ($AllowCreateNew -and $Value -eq 'CREATE_NEW') { return }
    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') { Stop-V2 $Code $Value }
}

function Invoke-V2([string[]]$Arguments) {
    $python = Resolve-Python $PythonPath
    if (-not (Test-Path -LiteralPath $pythonScript -PathType Leaf)) { Stop-V2 'V2_SCRIPT_MISSING' $pythonScript }
    $execution=Invoke-SystemV7PythonUtf8 -Python $python -Script $pythonScript -Arguments $Arguments
    if($execution.ExitCode -ne 0){ Stop-V2 'K1_LITE_V2_FAILED' ($execution.Stderr+$execution.Stdout) }
    if($execution.Stderr){Write-Verbose $execution.Stderr}
    return $execution.Stdout
}

$base = @('--isolation-root', $isolationRoot)
$mutatingActions = @('Plan','ImportBatch','ImportResult','AddDecisions','AddVisual','AddReview','BuildViews','VerifyBatch','InspectLayout')
$ownsProjectLock = $Action -in $mutatingActions -and $null -eq $InternalHeldProjectLock
$projectLock = if ($Action -in $mutatingActions) {
    if ($ownsProjectLock) { Enter-SystemV7ProjectMetaLock -ProjectPath $isolationRoot } else { $InternalHeldProjectLock }
} else { $null }
try {
switch ($Action) {
    'Plan' {
        Require $SourcePath 'SOURCE_PATH_REQUIRED'
        Require $ExpectedSourceSha256 'EXPECTED_SOURCE_SHA_REQUIRED'
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Assert-Sha $ExpectedSourceSha256 'EXPECTED_SOURCE_SHA_INVALID'
        $hasPdfPath = -not [string]::IsNullOrWhiteSpace($PdfPath)
        $hasPdfSha = -not [string]::IsNullOrWhiteSpace($ExpectedPdfSha256)
        if ($hasPdfPath -ne $hasPdfSha) { Stop-V2 'PDF_ARGUMENT_PAIR_REQUIRED' }
        if ($hasPdfSha) { Assert-Sha $ExpectedPdfSha256 'EXPECTED_PDF_SHA_INVALID' }
        if ($TargetMaxCharacters -lt $TargetMinCharacters) { Stop-V2 'CHUNK_TARGET_INVALID' }
        $arguments = @('plan') + $base + @(
            '--source', [IO.Path]::GetFullPath($SourcePath),
            '--expected-source-sha256', $ExpectedSourceSha256.ToUpperInvariant(),
            '--run-dir', [IO.Path]::GetFullPath($RunDirectory),
            '--candidate-limit', $CandidateLimit.ToString(),
            '--target-min', $TargetMinCharacters.ToString([Globalization.CultureInfo]::InvariantCulture),
            '--target-max', $TargetMaxCharacters.ToString([Globalization.CultureInfo]::InvariantCulture)
        )
        if ($hasPdfPath) {
            $arguments += @('--pdf', [IO.Path]::GetFullPath($PdfPath), '--expected-pdf-sha256', $ExpectedPdfSha256.ToUpperInvariant())
        }
        if (-not [string]::IsNullOrWhiteSpace($K0Path)) {
            Require $ExpectedK0Sha256 'EXPECTED_K0_SHA_REQUIRED'
            Assert-Sha $ExpectedK0Sha256 'EXPECTED_K0_SHA_INVALID'
            $arguments += @('--k0', [IO.Path]::GetFullPath($K0Path), '--expected-k0-sha256', $ExpectedK0Sha256.ToUpperInvariant())
        }
        Invoke-V2 $arguments
    }
    'NextWork' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Invoke-V2 (@('next-work') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory)))
    }
    'ImportBatch' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Require $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_REQUIRED'
        Assert-Sha $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_INVALID' -AllowCreateNew
        if (-not $ResultPaths -or $ResultPaths.Count -gt 100) { Stop-V2 'BATCH_SIZE_INVALID' }
        $arguments = @('import-batch') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory),'--expected-ledger-sha256',$ExpectedLedgerSha256)
        foreach ($item in $ResultPaths) { $arguments += @('--result',[IO.Path]::GetFullPath($item)) }
        Invoke-V2 $arguments
    }
    'ImportResult' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Require $ResultPath 'RESULT_PATH_REQUIRED'
        Require $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_REQUIRED'
        Assert-Sha $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_INVALID' -AllowCreateNew
        Invoke-V2 (@('import-result') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory),'--result',[IO.Path]::GetFullPath($ResultPath),'--expected-ledger-sha256',$ExpectedLedgerSha256))
    }
    'AddDecisions' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Require $DecisionPath 'DECISION_PATH_REQUIRED'
        Require $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_REQUIRED'
        Assert-Sha $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_INVALID'
        Invoke-V2 (@('add-decisions') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory),'--decisions',[IO.Path]::GetFullPath($DecisionPath),'--expected-ledger-sha256',$ExpectedLedgerSha256))
    }
    'AddVisual' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Require $ReceiptPath 'RECEIPT_PATH_REQUIRED'
        Require $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_REQUIRED'
        Assert-Sha $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_INVALID'
        Invoke-V2 (@('add-visual') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory),'--receipt',[IO.Path]::GetFullPath($ReceiptPath),'--expected-ledger-sha256',$ExpectedLedgerSha256))
    }
    'AddReview' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Require $ReceiptPath 'RECEIPT_PATH_REQUIRED'
        Require $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_REQUIRED'
        Assert-Sha $ExpectedLedgerSha256 'EXPECTED_LEDGER_SHA_INVALID'
        Invoke-V2 (@('add-review') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory),'--receipt',[IO.Path]::GetFullPath($ReceiptPath),'--expected-ledger-sha256',$ExpectedLedgerSha256))
    }
    'BuildViews' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Require $OutputDirectory 'OUTPUT_DIRECTORY_REQUIRED'
        Invoke-V2 (@('build-views') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory),'--output-dir',[IO.Path]::GetFullPath($OutputDirectory)))
    }
    'ValidateRun' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Invoke-V2 (@('validate-run') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory)))
    }
    'VerifyBatch' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Require $OutputPath 'OUTPUT_PATH_REQUIRED'
        Invoke-V2 (@('verify-batch') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory),'--output',[IO.Path]::GetFullPath($OutputPath)))
    }
    'InspectLayout' {
        Require $RunDirectory 'RUN_DIRECTORY_REQUIRED'
        Require $OutputPath 'OUTPUT_PATH_REQUIRED'
        Invoke-V2 (@('inspect-layout') + $base + @('--run-dir',[IO.Path]::GetFullPath($RunDirectory),'--output',[IO.Path]::GetFullPath($OutputPath)))
    }
    'CompareTextTwins' {
        Require $FirstTextPath 'FIRST_TEXT_PATH_REQUIRED'
        Require $FirstTextSha256 'FIRST_TEXT_SHA_REQUIRED'
        Require $SecondTextPath 'SECOND_TEXT_PATH_REQUIRED'
        Require $SecondTextSha256 'SECOND_TEXT_SHA_REQUIRED'
        Require $ExpectedPdfSha256 'EXPECTED_PDF_SHA_REQUIRED'
        Assert-Sha $FirstTextSha256 'FIRST_TEXT_SHA_INVALID'
        Assert-Sha $SecondTextSha256 'SECOND_TEXT_SHA_INVALID'
        Assert-Sha $ExpectedPdfSha256 'EXPECTED_PDF_SHA_INVALID'
        Invoke-V2 (@('compare-text-twins') + $base + @(
            '--first',[IO.Path]::GetFullPath($FirstTextPath),'--first-sha256',$FirstTextSha256,
            '--second',[IO.Path]::GetFullPath($SecondTextPath),'--second-sha256',$SecondTextSha256,
            '--pdf-sha256',$ExpectedPdfSha256
        ))
    }
}
} finally {
    if ($ownsProjectLock) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
}
