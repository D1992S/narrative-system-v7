[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('InspectNative', 'OcrPreview', 'Publish')]
    [string]$Action,

    [string]$PdfPath,
    [string]$ExpectedPdfSha256,
    [string]$OcrPages,
    [string]$OcrLanguages,
    [ValidateRange(150, 600)]
    [int]$Dpi = 300,
    [ValidateRange(1, 13)]
    [int]$Psm = 3,
    [ValidateRange(0, 1000000)]
    [int]$NativeTextThreshold = 80,
    [string]$WorkDirectory,
    [string]$PreviewPath,
    [string]$ExpectedPreviewSha256,
    [string]$DestinationPath,
    [string]$PythonPath = 'python.exe',
    [string]$TesseractPath = 'tesseract.exe'
)

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptRoot 'pdf_to_markdown.py'
$verifierScript = Join-Path $scriptRoot 'Test-K1LiteEvidence.ps1'
. (Join-Path (Split-Path -Parent $scriptRoot) 'Integrity-Receipts.ps1')
. (Join-Path (Split-Path -Parent $scriptRoot) 'Native-Python.ps1')

function Stop-K1Lite([string]$Code, [string]$Detail = '') {
    if ($Detail) { throw "${Code}: $Detail" }
    throw $Code
}

function Resolve-Application([string]$Value, [string]$ErrorCode) {
    if ([string]::IsNullOrWhiteSpace($Value)) { Stop-K1Lite $ErrorCode 'pusta ścieżka' }
    if ([IO.Path]::IsPathRooted($Value)) {
        if (-not (Test-Path -LiteralPath $Value -PathType Leaf)) { Stop-K1Lite $ErrorCode $Value }
        return (Resolve-Path -LiteralPath $Value).Path
    }
    $command = Get-Command -Name $Value -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { Stop-K1Lite $ErrorCode $Value }
    return $command.Source
}

function Get-FullPath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { Stop-K1Lite 'PATH_REQUIRED' }
    return [IO.Path]::GetFullPath($Value)
}

function Assert-NoReparsePoint([string]$Path) {
    $cursor = Get-FullPath $Path
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Stop-K1Lite 'REPARSE_POINT_BLOCKED' $item.FullName
            }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if (-not $parent) { break }
        if ($parent.FullName -eq $cursor) { break }
        $cursor = $parent.FullName
    }
}

function Assert-Within([string]$Candidate, [string]$Root, [switch]$AllowEqual) {
    $candidateFull = Get-FullPath $Candidate
    $rootFull = Get-FullPath $Root
    $relative = [IO.Path]::GetRelativePath($rootFull, $candidateFull)
    $escapes = [IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or
        $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::Ordinal) -or
        $relative.StartsWith("..$([IO.Path]::AltDirectorySeparatorChar)", [StringComparison]::Ordinal)
    if ($escapes -or ((-not $AllowEqual) -and $relative -eq '.')) {
        Stop-K1Lite 'PATH_OUTSIDE_PROJECT' "$candidateFull nie mieści się w $rootFull"
    }
}

function Find-NamedAncestor([string]$Path, [string]$Name) {
    $full = Get-FullPath $Path
    $cursor = if (Test-Path -LiteralPath $full -PathType Container) { [IO.DirectoryInfo]$full } else { [IO.Directory]::GetParent($full) }
    while ($cursor) {
        if ($cursor.Name.Equals($Name, [StringComparison]::OrdinalIgnoreCase)) { return $cursor }
        $cursor = $cursor.Parent
    }
    return $null
}

function Get-ProjectFromSourcesPath([string]$Path) {
    $sourcesDirectory = Find-NamedAncestor -Path $Path -Name 'sources'
    if (-not $sourcesDirectory -or -not $sourcesDirectory.Parent) {
        Stop-K1Lite 'SOURCE_NOT_IN_PROJECT_SOURCES' $Path
    }
    Assert-Within -Candidate $Path -Root $sourcesDirectory.FullName -AllowEqual
    return [pscustomobject]@{ Project = $sourcesDirectory.Parent.FullName; Sources = $sourcesDirectory.FullName }
}

function Get-ProjectFromWorkPath([string]$Path) {
    $workDirectory = Find-NamedAncestor -Path $Path -Name '_work'
    if (-not $workDirectory -or -not $workDirectory.Parent) {
        Stop-K1Lite 'PREVIEW_NOT_IN_PROJECT_WORK' $Path
    }
    return [pscustomobject]@{ Project = $workDirectory.Parent.FullName; Work = $workDirectory.FullName }
}

function Assert-Sha256([string]$Value, [string]$Code) {
    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') { Stop-K1Lite $Code $Value }
}

function Get-CanonicalOcrPages([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { Stop-K1Lite 'OCR_PAGES_REQUIRED' }
    if ($Value.Trim().Equals('NONE', [StringComparison]::OrdinalIgnoreCase)) { return 'NONE' }
    $compact = $Value.Replace(' ', '')
    if ($compact -notmatch '^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$') { Stop-K1Lite 'OCR_PAGES_INVALID' $Value }
    $pages = [System.Collections.Generic.SortedSet[int]]::new()
    foreach ($token in $compact.Split(',')) {
        if ($token.Contains('-')) {
            $bounds = $token.Split('-')
            $first = [int]$bounds[0]
            $last = [int]$bounds[1]
            if ($first -lt 1 -or $last -lt $first -or ($last - $first) -gt 100000) { Stop-K1Lite 'OCR_PAGES_INVALID' $token }
            foreach ($page in $first..$last) { [void]$pages.Add($page) }
        } else {
            $page = [int]$token
            if ($page -lt 1) { Stop-K1Lite 'OCR_PAGES_INVALID' $token }
            [void]$pages.Add($page)
        }
    }
    return (($pages | ForEach-Object { $_.ToString([Globalization.CultureInfo]::InvariantCulture) }) -join ',')
}

function Assert-OcrLanguages([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[a-z0-9_]+(?:\+[a-z0-9_]+)*$') {
        Stop-K1Lite 'OCR_LANGUAGES_INVALID' $Value
    }
    if (($Value -split '\+') -contains 'osd') { Stop-K1Lite 'OCR_LANGUAGE_INVALID' 'osd nie jest językiem treści' }
}

function Convert-ToRelativeUnix([string]$ProjectRoot, [string]$Path) {
    $relative = [IO.Path]::GetRelativePath((Get-FullPath $ProjectRoot), (Get-FullPath $Path))
    return $relative.Replace('\', '/')
}

function Invoke-K1LitePython([string[]]$Arguments) {
    $python = Resolve-Application -Value $PythonPath -ErrorCode 'PYTHON_UNAVAILABLE'
    if (-not (Test-Path -LiteralPath $pythonScript -PathType Leaf)) { Stop-K1Lite 'PYTHON_SCRIPT_MISSING' $pythonScript }
    $execution=Invoke-SystemV7PythonUtf8 -Python $python -Script $pythonScript -Arguments $Arguments
    if($execution.ExitCode -ne 0){ Stop-K1Lite 'K1_LITE_CONVERSION_FAILED' ($execution.Stderr+$execution.Stdout) }
    if($execution.Stderr){Write-Verbose $execution.Stderr}
    return $execution.Stdout
}

function Resolve-BackingPdfFromPreview([string]$ResolvedPreview, [string]$ProjectRoot) {
    $raw = [IO.File]::ReadAllText($ResolvedPreview, [Text.UTF8Encoding]::new($false)).Replace("`r`n", "`n").Replace("`r", "`n")
    $match = [regex]::Match($raw, '(?m)^ORIGINAL_PDF:\s*(?<value>.+)$')
    if (-not $match.Success) { Stop-K1Lite 'ORIGINAL_PDF_MISSING' }
    $value = $match.Groups['value'].Value.Trim()
    try {
        if ($value.StartsWith('"')) { $value = $value | ConvertFrom-Json -DateKind String }
    } catch {
        Stop-K1Lite 'ORIGINAL_PDF_INVALID' $_.Exception.Message
    }
    if ([string]::IsNullOrWhiteSpace($value) -or [IO.Path]::IsPathRooted($value)) { Stop-K1Lite 'ORIGINAL_PDF_INVALID' $value }
    $normalized = $value.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $backing = Get-FullPath (Join-Path $ProjectRoot $normalized)
    $sourcesRoot = Join-Path $ProjectRoot 'sources'
    Assert-Within -Candidate $backing -Root $sourcesRoot
    Assert-NoReparsePoint $backing
    if (-not (Test-Path -LiteralPath $backing -PathType Leaf)) { Stop-K1Lite 'ORIGINAL_PDF_MISSING' $backing }
    return $backing
}

switch ($Action) {
    'InspectNative' {
        if ([string]::IsNullOrWhiteSpace($PdfPath)) { Stop-K1Lite 'PDF_PATH_REQUIRED' }
        $resolvedPdf = Get-FullPath $PdfPath
        Assert-NoReparsePoint $resolvedPdf
        if (-not (Test-Path -LiteralPath $resolvedPdf -PathType Leaf)) { Stop-K1Lite 'PDF_NOT_FOUND' $resolvedPdf }
        $scope = Get-ProjectFromSourcesPath $resolvedPdf
        Assert-Within -Candidate $resolvedPdf -Root $scope.Sources
        Invoke-K1LitePython @('inspect', '--pdf', $resolvedPdf, '--threshold', $NativeTextThreshold.ToString([Globalization.CultureInfo]::InvariantCulture))
        break
    }
    'OcrPreview' {
        if ([string]::IsNullOrWhiteSpace($PdfPath)) { Stop-K1Lite 'PDF_PATH_REQUIRED' }
        if ([string]::IsNullOrWhiteSpace($ExpectedPdfSha256)) { Stop-K1Lite 'EXPECTED_PDF_SHA_REQUIRED' }
        if ([string]::IsNullOrWhiteSpace($WorkDirectory)) { Stop-K1Lite 'WORK_DIRECTORY_REQUIRED' }
        Assert-Sha256 -Value $ExpectedPdfSha256 -Code 'EXPECTED_PDF_SHA_INVALID'
        $canonicalPages = Get-CanonicalOcrPages $OcrPages
        if ($canonicalPages -eq 'NONE') {
            if (-not $OcrLanguages.Equals('none', [StringComparison]::OrdinalIgnoreCase)) {
                Stop-K1Lite 'OCR_LANGUAGES_MUST_BE_NONE' $OcrLanguages
            }
            $OcrLanguages = 'none'
        } else {
            if ($OcrLanguages.Equals('none', [StringComparison]::OrdinalIgnoreCase)) {
                Stop-K1Lite 'OCR_LANGUAGES_REQUIRED_FOR_SELECTED_PAGES'
            }
            Assert-OcrLanguages $OcrLanguages
        }
        $resolvedPdf = Get-FullPath $PdfPath
        Assert-NoReparsePoint $resolvedPdf
        if (-not (Test-Path -LiteralPath $resolvedPdf -PathType Leaf)) { Stop-K1Lite 'PDF_NOT_FOUND' $resolvedPdf }
        $scope = Get-ProjectFromSourcesPath $resolvedPdf
        $projectLock = if (Test-Path -LiteralPath (Join-Path $scope.Project '.system-v7') -PathType Container) {
            Enter-SystemV7ProjectMetaLock -ProjectPath $scope.Project
        } else { $null }
        try {
        $actualPdfHash = (Get-FileHash -LiteralPath $resolvedPdf -Algorithm SHA256).Hash
        if ($actualPdfHash -ne $ExpectedPdfSha256.ToUpperInvariant()) {
            Stop-K1Lite 'PDF_HASH_MISMATCH' "expected=$($ExpectedPdfSha256.ToUpperInvariant()) actual=$actualPdfHash"
        }
        $resolvedWork = Get-FullPath $WorkDirectory
        $allowedWorkRoot = Join-Path $scope.Project '_work\K1\k1-lite'
        Assert-Within -Candidate $resolvedWork -Root $allowedWorkRoot
        Assert-NoReparsePoint $resolvedWork
        $baseName = [IO.Path]::GetFileNameWithoutExtension($resolvedPdf)
        $resolvedPreview = Join-Path $resolvedWork ($baseName + '--TEXT.preview.md')
        $resolvedReport = Join-Path $resolvedWork 'conversion-report.json'
        if (Test-Path -LiteralPath $resolvedPreview) { Stop-K1Lite 'PREVIEW_OUTPUT_EXISTS' $resolvedPreview }
        if (Test-Path -LiteralPath $resolvedReport) { Stop-K1Lite 'PREVIEW_OUTPUT_EXISTS' $resolvedReport }
        $tesseract = if ($canonicalPages -eq 'NONE') { 'not-used' } else { Resolve-Application -Value $TesseractPath -ErrorCode 'TESSERACT_UNAVAILABLE' }
        $sourceReference = Convert-ToRelativeUnix -ProjectRoot $scope.Project -Path $resolvedPdf
        $previewReference = Convert-ToRelativeUnix -ProjectRoot $scope.Project -Path $resolvedPreview
        Invoke-K1LitePython @(
            'preview', '--pdf', $resolvedPdf,
            '--cache', (Join-Path $allowedWorkRoot 'page-cache.sqlite3'),
            '--expected-pdf-sha256', $ExpectedPdfSha256.ToUpperInvariant(),
            '--ocr-pages', $canonicalPages,
            '--ocr-languages', $OcrLanguages,
            '--dpi', $Dpi.ToString([Globalization.CultureInfo]::InvariantCulture),
            '--psm', $Psm.ToString([Globalization.CultureInfo]::InvariantCulture),
            '--tesseract', $tesseract,
            '--preview', $resolvedPreview,
            '--report', $resolvedReport,
            '--source-reference', $sourceReference,
            '--preview-reference', $previewReference
        )
        } finally {
            if ($null -ne $projectLock) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
        }
        break
    }
    'Publish' {
        if ([string]::IsNullOrWhiteSpace($PreviewPath)) { Stop-K1Lite 'PREVIEW_PATH_REQUIRED' }
        if ([string]::IsNullOrWhiteSpace($ExpectedPdfSha256)) { Stop-K1Lite 'EXPECTED_PDF_SHA_REQUIRED' }
        if ([string]::IsNullOrWhiteSpace($ExpectedPreviewSha256)) { Stop-K1Lite 'EXPECTED_PREVIEW_SHA_REQUIRED' }
        if ([string]::IsNullOrWhiteSpace($DestinationPath)) { Stop-K1Lite 'DESTINATION_PATH_REQUIRED' }
        Assert-Sha256 -Value $ExpectedPdfSha256 -Code 'EXPECTED_PDF_SHA_INVALID'
        Assert-Sha256 -Value $ExpectedPreviewSha256 -Code 'EXPECTED_PREVIEW_SHA_INVALID'
        $resolvedPreview = Get-FullPath $PreviewPath
        Assert-NoReparsePoint $resolvedPreview
        if (-not (Test-Path -LiteralPath $resolvedPreview -PathType Leaf)) { Stop-K1Lite 'PREVIEW_NOT_FOUND' $resolvedPreview }
        $workScope = Get-ProjectFromWorkPath $resolvedPreview
        $allowedPreviewRoot = Join-Path $workScope.Project '_work\K1\k1-lite'
        Assert-Within -Candidate $resolvedPreview -Root $allowedPreviewRoot
        $resolvedDestination = Get-FullPath $DestinationPath
        Assert-NoReparsePoint $resolvedDestination
        $destinationScope = Get-ProjectFromSourcesPath $resolvedDestination
        if ((Get-FullPath $destinationScope.Project) -ne (Get-FullPath $workScope.Project)) {
            Stop-K1Lite 'PROJECT_MISMATCH' "preview=$($workScope.Project) destination=$($destinationScope.Project)"
        }
        $projectLock = if (Test-Path -LiteralPath (Join-Path $workScope.Project '.system-v7') -PathType Container) {
            Enter-SystemV7ProjectMetaLock -ProjectPath $workScope.Project
        } else { $null }
        try {
        if (Test-Path -LiteralPath $resolvedDestination) { Stop-K1Lite 'DESTINATION_EXISTS' $resolvedDestination }
        $actualPreviewHash = (Get-FileHash -LiteralPath $resolvedPreview -Algorithm SHA256).Hash
        if ($actualPreviewHash -ne $ExpectedPreviewSha256.ToUpperInvariant()) {
            Stop-K1Lite 'PREVIEW_HASH_MISMATCH' "expected=$($ExpectedPreviewSha256.ToUpperInvariant()) actual=$actualPreviewHash"
        }
        $backingPdf = Resolve-BackingPdfFromPreview -ResolvedPreview $resolvedPreview -ProjectRoot $workScope.Project
        $actualPdfHash = (Get-FileHash -LiteralPath $backingPdf -Algorithm SHA256).Hash
        if ($actualPdfHash -ne $ExpectedPdfSha256.ToUpperInvariant()) {
            Stop-K1Lite 'PDF_HASH_MISMATCH' "expected=$($ExpectedPdfSha256.ToUpperInvariant()) actual=$actualPdfHash"
        }
        $expectedDestinationName = [IO.Path]::GetFileNameWithoutExtension($backingPdf) + '--TEXT.md'
        if (-not [IO.Path]::GetFileName($resolvedDestination).Equals($expectedDestinationName, [StringComparison]::OrdinalIgnoreCase)) {
            Stop-K1Lite 'DESTINATION_NAME_INVALID' "expected=$expectedDestinationName actual=$([IO.Path]::GetFileName($resolvedDestination))"
        }
        if (-not (Test-Path -LiteralPath $verifierScript -PathType Leaf)) { Stop-K1Lite 'VERIFIER_MISSING' $verifierScript }
        $validation = & $verifierScript -SourcePath $resolvedPreview -ValidateOnly -ExpectedSourceSha256 $actualPreviewHash -ExpectedPdfPath $backingPdf -ExpectedPdfSha256 $actualPdfHash -NoExit
        if ($validation.Verdict -ne 'PASS') {
            Stop-K1Lite 'PUBLISH_PREVIEW_INVALID' "$($validation.Code): $($validation.Detail)"
        }
        $created = $false
        try {
            $input = [IO.File]::Open($resolvedPreview, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            try {
                $output = [IO.File]::Open($resolvedDestination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $created = $true
                try { $input.CopyTo($output) } finally { $output.Dispose() }
            } finally { $input.Dispose() }
            $publishedHash = (Get-FileHash -LiteralPath $resolvedDestination -Algorithm SHA256).Hash
            if ($publishedHash -ne $actualPreviewHash) {
                Stop-K1Lite 'PUBLISH_HASH_MISMATCH' "preview=$actualPreviewHash destination=$publishedHash"
            }
            [pscustomobject]@{
                schema = 'K1_LITE_PUBLISH_RESULT_V1'
                destination = $resolvedDestination
                preview_sha256 = $actualPreviewHash
                pdf_sha256 = $actualPdfHash
                status = 'PUBLISHED_CREATE_NEW'
            } | ConvertTo-Json -Depth 3
        } catch {
            if ($created -and (Test-Path -LiteralPath $resolvedDestination)) {
                Remove-Item -LiteralPath $resolvedDestination -Force
            }
            throw
        }
        } finally {
            if ($null -ne $projectLock) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
        }
        break
    }
}
