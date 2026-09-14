[CmdletBinding()]
param(
    [string]$PythonPath = "python.exe",
    [string]$TesseractPath = "tesseract.exe",
    [switch]$KeepTestDirectory
)

$ErrorActionPreference = 'Stop'
$env:PYTHONDONTWRITEBYTECODE = '1'
$testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolRoot = Split-Path -Parent $testRoot
$wrapper = Join-Path $toolRoot 'Convert-PdfToMarkdown.ps1'
$verifier = Join-Path $toolRoot 'Test-K1LiteEvidence.ps1'
$fixtureBuilder = Join-Path $testRoot 'New-K1LiteFixture.py'
$pythonUnitTests = Join-Path $testRoot 'Test-PdfToMarkdownUnit.py'
& $PythonPath -B (Join-Path $testRoot 'test_page_cache.py')
if ($LASTEXITCODE -ne 0) { throw 'PAGE_CACHE_TEST_FAIL' }
$runRoot = Join-Path ([IO.Path]::GetTempPath()) ("k1-lite-test-" + [guid]::NewGuid().ToString('N'))
$projectRoot = Join-Path $runRoot 'project-a'
$sources = Join-Path $projectRoot 'sources'
$work = Join-Path $projectRoot '_work\K1\k1-lite\fixture'
$pdf = Join-Path $sources 'k1-lite-fixture.pdf'
$preview = Join-Path $work 'k1-lite-fixture--TEXT.preview.md'
$report = Join-Path $work 'conversion-report.json'
$published = Join-Path $sources 'k1-lite-fixture--TEXT.md'
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result([string]$Name, [bool]$Passed, [string]$Detail) {
    $script:results.Add([pscustomobject]@{ Test = $Name; Result = $(if ($Passed) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
    if (-not $Passed) { throw "TEST_FAILED[$Name]: $Detail" }
}

function Expect-Failure([string]$Name, [scriptblock]$Action, [string]$Pattern) {
    try {
        & $Action
        Add-Result $Name $false 'Operacja niespodziewanie zakończyła się sukcesem.'
    } catch {
        $message = $_.Exception.Message
        Add-Result $Name ($message -match $Pattern) $message
    }
}

function Get-PageLines([string]$Path, [int]$PageNumber) {
    $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false)).Replace("`r`n", "`n").Replace("`r", "`n")
    $p = $PageNumber.ToString('0000')
    $pattern = "(?ms)^<!-- PDF_PAGE_BEGIN: P$p;[^\n]* -->\n(?<body>.*?)^<!-- PDF_PAGE_END: P$p -->$"
    $match = [regex]::Match($raw, $pattern)
    if (-not $match.Success) { throw "Nie znaleziono bloku P$p" }
    $body = $match.Groups['body'].Value
    if ($body.EndsWith("`n")) { $body = $body.Substring(0, $body.Length - 1) }
    if ($body.Length -eq 0) { return @() }
    return @($body -split "`n")
}

function Get-LocatorForText([string]$Path, [int]$PageNumber, [string]$Text) {
    $lines = @(Get-PageLines -Path $Path -PageNumber $PageNumber)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq $Text) {
            $line = $index + 1
            return "P$($PageNumber.ToString('0000'))/L$line-L$line"
        }
    }
    throw "Nie znaleziono dokładnego tekstu na stronie ${PageNumber}: $Text"
}

function Assert-InvalidDocument([string]$Name, [string]$Text, [string]$ExpectedCode) {
    $path = Join-Path $work ($Name + '.preview.md')
    [IO.File]::WriteAllText($path, $Text, [Text.UTF8Encoding]::new($false))
    $variantHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $check = & $verifier -SourcePath $path -ValidateOnly -ExpectedSourceSha256 $variantHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result $Name (($check.Verdict -eq 'FAIL') -and ($check.Code -match $ExpectedCode)) ($check | ConvertTo-Json -Compress)
}

try {
    if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
        throw 'RED_EXPECTED: brak Convert-PdfToMarkdown.ps1'
    }
    if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
        throw 'RED_EXPECTED: brak Test-K1LiteEvidence.ps1'
    }

    [IO.Directory]::CreateDirectory($sources) | Out-Null
    & $PythonPath $fixtureBuilder --output $pdf
    if ($LASTEXITCODE -ne 0) { throw "FIXTURE_BUILD_FAILED: exit=$LASTEXITCODE" }
    $pdfHashBefore = (Get-FileHash -LiteralPath $pdf -Algorithm SHA256).Hash

    $env:K1_LITE_TEST_FIXTURE = $pdf
    $unitOutput = & $PythonPath $pythonUnitTests 2>&1
    if ($LASTEXITCODE -ne 0) { throw "PYTHON_UNIT_TEST_FAILED: $($unitOutput -join "`n")" }
    Add-Result 'PythonFailClosedUnitTests' (($unitOutput -join "`n") -match 'OK') (($unitOutput -join ' | '))

    $inspectRaw = & $wrapper -Action InspectNative -PdfPath $pdf -NativeTextThreshold 80 -PythonPath $PythonPath -TesseractPath 'X:\must-not-be-used\tesseract.exe'
    $inspect = ($inspectRaw -join "`n") | ConvertFrom-Json -DateKind String
    Add-Result 'InspectNativePages' ($inspect.pdf_pages -eq 10) "pdf_pages=$($inspect.pdf_pages)"
    Add-Result 'InspectNativeHash' ($inspect.pdf_sha256 -eq $pdfHashBefore) "sha=$($inspect.pdf_sha256)"
    $suggestions = @($inspect.ocr_suggestions)
    Add-Result 'InspectSuggestsScans' (($suggestions -contains 3) -and ($suggestions -contains 9)) ("suggestions=" + ($suggestions -join ','))
    Add-Result 'InspectSuggestsBlank' ($suggestions -contains 4) ("suggestions=" + ($suggestions -join ','))
    Add-Result 'InspectIsReadOnly' ((Get-ChildItem -LiteralPath $projectRoot -File -Recurse).Count -eq 1) 'InspectNative nie utworzył plików.'

    Expect-Failure 'PreviewRequiresExpectedPdfHash' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -OcrPages '3,9' -OcrLanguages 'pol+eng' -Dpi 300 -WorkDirectory $work -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'ExpectedPdfSha256|EXPECTED_PDF_SHA_REQUIRED'

    Expect-Failure 'OcrPagesRejectInjection' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3;Write-Output HACK' -OcrLanguages 'pol+eng' -Dpi 300 -WorkDirectory $work -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'OCR_PAGES_INVALID'
    Expect-Failure 'OcrLanguagesRejectInjection' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3' -OcrLanguages 'pol;eng' -Dpi 300 -WorkDirectory (Join-Path $projectRoot '_work\K1\k1-lite\bad-language') -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'OCR_LANGUAGES_INVALID'
    Expect-Failure 'OsdRejectedAsContentLanguage' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3' -OcrLanguages 'osd' -Dpi 300 -WorkDirectory (Join-Path $projectRoot '_work\K1\k1-lite\osd') -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'OCR_LANGUAGE_INVALID'
    Expect-Failure 'SelectedPagesRejectNoneLanguage' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3' -OcrLanguages 'none' -Dpi 300 -WorkDirectory (Join-Path $projectRoot '_work\K1\k1-lite\page-with-none') -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'OCR_LANGUAGES_REQUIRED_FOR_SELECTED_PAGES'
    Expect-Failure 'NoPagesRequireNoneLanguage' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages 'NONE' -OcrLanguages 'eng' -Dpi 300 -WorkDirectory (Join-Path $projectRoot '_work\K1\k1-lite\none-with-language') -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'OCR_LANGUAGES_MUST_BE_NONE'
    Expect-Failure 'DpiOutOfRangeFails' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3' -OcrLanguages 'pol' -Dpi 149 -WorkDirectory (Join-Path $projectRoot '_work\K1\k1-lite\bad-dpi') -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'Dpi|range|ValidateRange'
    Expect-Failure 'PsmOutOfRangeFails' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3' -OcrLanguages 'pol' -Dpi 300 -Psm 14 -WorkDirectory (Join-Path $projectRoot '_work\K1\k1-lite\bad-psm') -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'Psm|range|ValidateRange'
    Expect-Failure 'OcrPageOutOfRangeFails' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '11' -OcrLanguages 'pol' -Dpi 300 -WorkDirectory (Join-Path $projectRoot '_work\K1\k1-lite\bad-page') -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'OCR_PAGE_OUT_OF_RANGE'

    $collisionWork = Join-Path $projectRoot '_work\K1\k1-lite\report-collision'
    [IO.Directory]::CreateDirectory($collisionWork) | Out-Null
    [IO.File]::WriteAllText((Join-Path $collisionWork 'conversion-report.json'), '{}', [Text.UTF8Encoding]::new($false))
    Expect-Failure 'ReportCollisionLeavesNoPreview' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3' -OcrLanguages 'pol' -Dpi 300 -WorkDirectory $collisionWork -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'PREVIEW_OUTPUT_EXISTS'
    Add-Result 'ReportCollisionNoPartialPreview' (-not (Test-Path -LiteralPath (Join-Path $collisionWork 'k1-lite-fixture--TEXT.preview.md'))) 'Nie powstał częściowy preview.'

    & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3,9' -OcrLanguages 'pol+eng' -Dpi 300 -WorkDirectory $work -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    Add-Result 'PreviewCreated' ((Test-Path -LiteralPath $preview -PathType Leaf) -and (Test-Path -LiteralPath $report -PathType Leaf)) 'Preview i raport istnieją.'
    $pdfHashAfterPreview = (Get-FileHash -LiteralPath $pdf -Algorithm SHA256).Hash
    Add-Result 'PdfUnchangedByOcr' ($pdfHashAfterPreview -eq $pdfHashBefore) "before=$pdfHashBefore after=$pdfHashAfterPreview"

    $reportData = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    Add-Result 'ReportSchema' ($reportData.schema -eq 'K1_LITE_CONVERSION_REPORT_V1') $reportData.schema
    Add-Result 'ReportOcrPages' ((@($reportData.ocr_pages) -join ',') -eq '3,9') ((@($reportData.ocr_pages) -join ','))
    $previewHash = (Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash
    Add-Result 'ReportPreviewHash' ($reportData.preview_sha256 -eq $previewHash) $reportData.preview_sha256
    Expect-Failure 'PreviewCreateNew' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3,9' -OcrLanguages 'pol+eng' -Dpi 300 -WorkDirectory $work -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'PREVIEW_OUTPUT_EXISTS'

    $determinismProject = Join-Path $runRoot 'project-d'
    $determinismSources = Join-Path $determinismProject 'sources'
    $determinismWork = Join-Path $determinismProject '_work\K1\k1-lite\fixture'
    [IO.Directory]::CreateDirectory($determinismSources) | Out-Null
    $determinismPdf = Join-Path $determinismSources 'k1-lite-fixture.pdf'
    Copy-Item -LiteralPath $pdf -Destination $determinismPdf
    & $wrapper -Action OcrPreview -PdfPath $determinismPdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3,9' -OcrLanguages 'pol+eng' -Dpi 300 -WorkDirectory $determinismWork -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    $determinismPreview = Join-Path $determinismWork 'k1-lite-fixture--TEXT.preview.md'
    $determinismHash = (Get-FileHash -LiteralPath $determinismPreview -Algorithm SHA256).Hash
    Add-Result 'DeterministicPreviewHash' ($determinismHash -eq $previewHash) "first=$previewHash second=$determinismHash"

    $nativeOnlyProject = Join-Path $runRoot 'project-native-only'
    $nativeOnlySources = Join-Path $nativeOnlyProject 'sources'
    $nativeOnlyWork = Join-Path $nativeOnlyProject '_work\K1\k1-lite\fixture'
    [IO.Directory]::CreateDirectory($nativeOnlySources) | Out-Null
    $nativeOnlyPdf = Join-Path $nativeOnlySources 'k1-lite-fixture.pdf'
    Copy-Item -LiteralPath $pdf -Destination $nativeOnlyPdf
    & $wrapper -Action OcrPreview -PdfPath $nativeOnlyPdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages 'NONE' -OcrLanguages 'none' -Dpi 300 -WorkDirectory $nativeOnlyWork -PythonPath $PythonPath -TesseractPath 'X:\must-not-be-used\tesseract.exe' | Out-Null
    $nativeOnlyPreview = Join-Path $nativeOnlyWork 'k1-lite-fixture--TEXT.preview.md'
    $nativeOnlyReportPath = Join-Path $nativeOnlyWork 'conversion-report.json'
    $nativeOnlyReport = Get-Content -LiteralPath $nativeOnlyReportPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    $nativeOnlyRaw = [IO.File]::ReadAllText($nativeOnlyPreview, [Text.UTF8Encoding]::new($false))
    $nativeOnlySha = (Get-FileHash -LiteralPath $nativeOnlyPreview -Algorithm SHA256).Hash
    $nativeOnlyValidation = & $verifier -SourcePath $nativeOnlyPreview -ValidateOnly -ExpectedSourceSha256 $nativeOnlySha -ExpectedPdfPath $nativeOnlyPdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'NativeOnlySkipsTesseract' (($nativeOnlyReport.tool_versions.tesseract -eq 'not_used') -and (@($nativeOnlyReport.ocr_pages).Count -eq 0)) ($nativeOnlyReport | ConvertTo-Json -Compress)
    Add-Result 'NativeOnlyAllPagesNative' (([regex]::Matches($nativeOnlyRaw, '(?m)^<!-- PDF_PAGE_BEGIN: P\d{4}; METHOD: NATIVE;')).Count -eq 10) 'NATIVE=10'
    Add-Result 'NativeOnlyDocumentValid' ($nativeOnlyValidation.Verdict -eq 'PASS') ($nativeOnlyValidation | ConvertTo-Json -Compress)

    $validation = & $verifier -SourcePath $preview -ValidateOnly -ExpectedSourceSha256 $previewHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'CompletePageStructure' ($validation.Verdict -eq 'PASS') ($validation | ConvertTo-Json -Compress)
    $unpinned = & $verifier -SourcePath $preview -ValidateOnly -NoExit
    Add-Result 'UnpinnedVerifierFails' ($unpinned.Verdict -eq 'FAIL' -and $unpinned.Code -eq 'EXPECTED_SOURCE_SHA_REQUIRED') ($unpinned | ConvertTo-Json -Compress)
    $rawPreview = [IO.File]::ReadAllText($preview, [Text.UTF8Encoding]::new($false))
    $uniqueQuote = 'Wyjątkowy cytat tylko na stronie pierwszej.'
    Add-Result 'TenBeginMarkers' (([regex]::Matches($rawPreview, '(?m)^<!-- PDF_PAGE_BEGIN:')).Count -eq 10) 'BEGIN=10'
    Add-Result 'TenEndMarkers' (([regex]::Matches($rawPreview, '(?m)^<!-- PDF_PAGE_END:')).Count -eq 10) 'END=10'
    Add-Result 'OnlySelectedPagesUseOcr' (([regex]::Matches($rawPreview, '(?m)^<!-- PDF_PAGE_BEGIN: P(0003|0009); METHOD: OCR;[^\n]*FLAGS: LAYOUT_REVIEW_REQUIRED -->$')).Count -eq 2) 'OCR=P0003,P0009'
    Add-Result 'OtherPagesRemainNative' (([regex]::Matches($rawPreview, '(?m)^<!-- PDF_PAGE_BEGIN: P(?!0003|0009)\d{4}; METHOD: NATIVE;')).Count -eq 8) 'NATIVE=8'
    Add-Result 'BlankPagePreserved' ((Get-PageLines -Path $preview -PageNumber 4).Count -eq 0) 'P0004 ma pusty blok.'

    $block4Pattern = '(?ms)<!-- PDF_PAGE_BEGIN: P0004;.*?<!-- PDF_PAGE_END: P0004 -->\n?'
    Assert-InvalidDocument 'MissingPageBlockFails' ([regex]::Replace($rawPreview, $block4Pattern, '', 1)) 'PAGE_BEGIN_INVALID|PAGE_ORDER_INVALID|PAGE_COUNT_MISMATCH'
    $block4 = [regex]::Match($rawPreview, $block4Pattern).Value
    Assert-InvalidDocument 'DuplicatePageBlockFails' ($rawPreview.Replace($block4, $block4 + $block4)) 'PAGE_BEGIN_INVALID|PAGE_ORDER_INVALID'
    Assert-InvalidDocument 'MismatchedEndFails' ($rawPreview.Replace('<!-- PDF_PAGE_END: P0004 -->', '<!-- PDF_PAGE_END: P0005 -->')) 'PAGE_END_MISMATCH'
    Assert-InvalidDocument 'OutOfOrderPageFails' ($rawPreview.Replace('<!-- PDF_PAGE_BEGIN: P0004;', '<!-- PDF_PAGE_BEGIN: P0005;')) 'PAGE_ORDER_INVALID'
    $ocrFlagRemoved = [regex]::Replace($rawPreview, '(?m)^(<!-- PDF_PAGE_BEGIN: P0003; METHOD: OCR; PAGE_TEXT_SHA256: [0-9A-F]{64}; FLAGS: )LAYOUT_REVIEW_REQUIRED( -->)$', '$1NONE$2')
    Assert-InvalidDocument 'OcrWithoutLayoutFlagFails' $ocrFlagRemoved 'OCR_LAYOUT_FLAG_MISSING'
    Assert-InvalidDocument 'InvalidOcrEngineFails' ($rawPreview.Replace('OCR_ENGINE: tesseract', 'OCR_ENGINE: other')) 'OCR_ENGINE_INVALID'
    Assert-InvalidDocument 'InvalidFrontmatterOcrLanguagesFails' ($rawPreview.Replace('OCR_LANGUAGES: pol+eng', 'OCR_LANGUAGES: pol;eng')) 'OCR_LANGUAGES_INVALID'
    Assert-InvalidDocument 'TrailingWhitespaceFails' ($rawPreview.Replace($uniqueQuote, $uniqueQuote + ' ')) 'PAGE_BODY_NOT_NORMALIZED'
    Assert-InvalidDocument 'BodyEdgeBlankFails' ($rawPreview.Replace("FLAGS: NONE -->`nSTRONA 1", "FLAGS: NONE -->`n`nSTRONA 1")) 'PAGE_BODY_EDGE_BLANK'

    $uniqueLocator = Get-LocatorForText -Path $preview -PageNumber 1 -Text $uniqueQuote
    $quotePass = & $verifier -SourcePath $preview -Locator $uniqueLocator -Quote $uniqueQuote -ExpectedSourceSha256 $previewHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'PageLocalQuotePass' ($quotePass.Verdict -eq 'PASS') ($quotePass | ConvertTo-Json -Compress)
    $wrongLocator = $uniqueLocator -replace '^P0001', 'P0002'
    $quoteWrong = & $verifier -SourcePath $preview -Locator $wrongLocator -Quote $uniqueQuote -ExpectedSourceSha256 $previewHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'QuoteOnlyOtherPageFails' ($quoteWrong.Verdict -eq 'FAIL') ($quoteWrong | ConvertTo-Json -Compress)
    $v3Locator = & $verifier -SourcePath $preview -Locator 'L1-L2' -Quote $uniqueQuote -ExpectedSourceSha256 $previewHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'V3LocatorRejectedForV4' ($v3Locator.Verdict -eq 'FAIL' -and $v3Locator.Code -eq 'LOCATOR_INVALID') ($v3Locator | ConvertTo-Json -Compress)
    $page1Lines = @(Get-PageLines -Path $preview -PageNumber 1)
    $edgeLocator = "P0001/L$($page1Lines.Count)-L$($page1Lines.Count)"
    $crossPage = & $verifier -SourcePath $preview -Locator $edgeLocator -Quote 'PAGE 2 — NATIVE ENGLISH TEXT' -ExpectedSourceSha256 $previewHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'ToleranceNeverCrossesPage' ($crossPage.Verdict -eq 'FAIL') ($crossPage | ConvertTo-Json -Compress)
    $crossEndLocator = "P0001/L$($page1Lines.Count)-L$($page1Lines.Count + 1)"
    $crossEnd = & $verifier -SourcePath $preview -Locator $crossEndLocator -Quote $page1Lines[-1] -ExpectedSourceSha256 $previewHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'LocatorCannotCrossEnd' ($crossEnd.Verdict -eq 'FAIL' -and $crossEnd.Code -eq 'LOCATOR_LINE_OUT_OF_RANGE') ($crossEnd | ConvertTo-Json -Compress)

    $duplicateQuote = 'The same sentence appears on two physical pages.'
    foreach ($pageNumber in 2, 8) {
        $locator = Get-LocatorForText -Path $preview -PageNumber $pageNumber -Text $duplicateQuote
        $duplicateResult = & $verifier -SourcePath $preview -Locator $locator -Quote $duplicateQuote -ExpectedSourceSha256 $previewHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
        Add-Result "DuplicateQuotePage$pageNumber" (($duplicateResult.Verdict -eq 'PASS') -and ($duplicateResult.Page -eq $pageNumber)) ($duplicateResult | ConvertTo-Json -Compress)
    }

    $markerResult = & $verifier -SourcePath $preview -Locator 'P0010/L1-L3' -Quote 'PDF_PAGE_BEGIN:' -ExpectedSourceSha256 $previewHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'MarkerCannotBeQuoted' ($markerResult.Verdict -eq 'FAIL') ($markerResult | ConvertTo-Json -Compress)
    $rangeResult = & $verifier -SourcePath $preview -Locator 'P0001/L999-L1000' -Quote $uniqueQuote -ExpectedSourceSha256 $previewHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'OutOfRangeFails' ($rangeResult.Verdict -eq 'FAIL') ($rangeResult | ConvertTo-Json -Compress)

    $tampered = Join-Path $work 'tampered.preview.md'
    $tamperedText = $rawPreview.Replace($uniqueQuote, 'Zmieniony cytat tylko na stronie pierwszej.')
    [IO.File]::WriteAllText($tampered, $tamperedText, [Text.UTF8Encoding]::new($false))
    $tamperedHash = (Get-FileHash -LiteralPath $tampered -Algorithm SHA256).Hash
    $tamperResult = & $verifier -SourcePath $tampered -ValidateOnly -ExpectedSourceSha256 $tamperedHash -ExpectedPdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -NoExit
    Add-Result 'PageHashTamperFails' ($tamperResult.Verdict -eq 'FAIL') ($tamperResult | ConvertTo-Json -Compress)

    Expect-Failure 'PublishRejectsInvalidPageHashWithPinnedPreview' {
        & $wrapper -Action Publish -PreviewPath $tampered -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $tamperedHash -DestinationPath $published | Out-Null
    } 'PUBLISH_PREVIEW_INVALID'
    Add-Result 'InvalidPageHashCreatesNoDestination' (-not (Test-Path -LiteralPath $published)) 'Cel nie powstał.'

    $badFrontmatter = Join-Path $work 'bad-frontmatter.preview.md'
    $badFrontmatterText = $rawPreview.Replace($pdfHashBefore, ('0' * 64))
    [IO.File]::WriteAllText($badFrontmatter, $badFrontmatterText, [Text.UTF8Encoding]::new($false))
    $badFrontmatterHash = (Get-FileHash -LiteralPath $badFrontmatter -Algorithm SHA256).Hash
    Expect-Failure 'PublishRejectsFrontmatterPdfHash' {
        & $wrapper -Action Publish -PreviewPath $badFrontmatter -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $badFrontmatterHash -DestinationPath $published | Out-Null
    } 'PUBLISH_PREVIEW_INVALID'
    Add-Result 'InvalidFrontmatterCreatesNoDestination' (-not (Test-Path -LiteralPath $published)) 'Cel nie powstał.'

    $badMarker = Join-Path $work 'bad-marker.preview.md'
    $badMarkerText = $rawPreview.Replace('<!-- PDF_PAGE_END: P0004 -->', '<!-- PDF_PAGE_END: P0005 -->')
    [IO.File]::WriteAllText($badMarker, $badMarkerText, [Text.UTF8Encoding]::new($false))
    $badMarkerHash = (Get-FileHash -LiteralPath $badMarker -Algorithm SHA256).Hash
    Expect-Failure 'PublishRejectsInvalidMarkerWithPinnedPreview' {
        & $wrapper -Action Publish -PreviewPath $badMarker -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $badMarkerHash -DestinationPath $published | Out-Null
    } 'PUBLISH_PREVIEW_INVALID'
    Add-Result 'InvalidMarkerCreatesNoDestination' (-not (Test-Path -LiteralPath $published)) 'Cel nie powstał.'

    Expect-Failure 'PublishRejectsWrongBasename' {
        & $wrapper -Action Publish -PreviewPath $preview -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $previewHash -DestinationPath (Join-Path $sources 'inna-nazwa--TEXT.md') | Out-Null
    } 'DESTINATION_NAME_INVALID'
    Expect-Failure 'PublishRejectsWrongExtension' {
        & $wrapper -Action Publish -PreviewPath $preview -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $previewHash -DestinationPath (Join-Path $sources 'k1-lite-fixture--TEXT.txt') | Out-Null
    } 'DESTINATION_NAME_INVALID'

    $changedPreview = Join-Path $work 'changed-hash.preview.md'
    [IO.File]::WriteAllText($changedPreview, $rawPreview + "`n", [Text.UTF8Encoding]::new($false))
    $changedPreviewDestination = Join-Path $sources 'changed-hash--TEXT.md'
    Expect-Failure 'ChangedPreviewBeforePublishFails' {
        & $wrapper -Action Publish -PreviewPath $changedPreview -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $previewHash -DestinationPath $changedPreviewDestination | Out-Null
    } 'PREVIEW_HASH_MISMATCH'

    & $wrapper -Action Publish -PreviewPath $preview -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $previewHash -DestinationPath $published -PythonPath $PythonPath | Out-Null
    $publishedHash = (Get-FileHash -LiteralPath $published -Algorithm SHA256).Hash
    Add-Result 'PublishByteIdentical' ($publishedHash -eq $previewHash) "published=$publishedHash preview=$previewHash"
    Expect-Failure 'PublishCreateNew' {
        & $wrapper -Action Publish -PreviewPath $preview -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $previewHash -DestinationPath $published -PythonPath $PythonPath | Out-Null
    } 'DESTINATION_EXISTS|istnieje'
    Add-Result 'PublishDidNotOverwrite' ((Get-FileHash -LiteralPath $published -Algorithm SHA256).Hash -eq $publishedHash) $publishedHash

    $changedProject = Join-Path $runRoot 'project-c'
    $changedSources = Join-Path $changedProject 'sources'
    $changedWork = Join-Path $changedProject '_work\K1\k1-lite\fixture'
    [IO.Directory]::CreateDirectory($changedSources) | Out-Null
    [IO.Directory]::CreateDirectory($changedWork) | Out-Null
    $changedPdf = Join-Path $changedSources 'k1-lite-fixture.pdf'
    $changedProjectPreview = Join-Path $changedWork 'k1-lite-fixture--TEXT.preview.md'
    Copy-Item -LiteralPath $pdf -Destination $changedPdf
    Copy-Item -LiteralPath $preview -Destination $changedProjectPreview
    $appendStream = [IO.File]::Open($changedPdf, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $appendStream.WriteByte(0) } finally { $appendStream.Dispose() }
    Expect-Failure 'ChangedPdfBeforePreviewFails' {
        & $wrapper -Action OcrPreview -PdfPath $changedPdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3' -OcrLanguages 'pol+eng' -Dpi 300 -WorkDirectory (Join-Path $changedProject '_work\K1\k1-lite\new-preview') -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'PDF_HASH_MISMATCH'
    Expect-Failure 'ChangedPdfBeforePublishFails' {
        & $wrapper -Action Publish -PreviewPath $changedProjectPreview -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $previewHash -DestinationPath (Join-Path $changedSources 'k1-lite-fixture--TEXT.md') | Out-Null
    } 'PDF_HASH_MISMATCH'

    $otherSources = Join-Path $runRoot 'project-b\sources'
    [IO.Directory]::CreateDirectory($otherSources) | Out-Null
    $crossProject = Join-Path $otherSources 'forbidden--TEXT.md'
    Expect-Failure 'PublishCrossProjectBlocked' {
        & $wrapper -Action Publish -PreviewPath $preview -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $previewHash -DestinationPath $crossProject -PythonPath $PythonPath | Out-Null
    } 'PATH_OUTSIDE_PROJECT|PROJECT_MISMATCH'

    $junctionTarget = Join-Path $runRoot 'junction-target'
    [IO.Directory]::CreateDirectory($junctionTarget) | Out-Null
    $junctionPath = Join-Path $projectRoot '_work\K1\k1-lite\blocked-junction'
    New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget | Out-Null
    Expect-Failure 'ReparsePointWorkDirectoryBlocked' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3' -OcrLanguages 'pol+eng' -Dpi 300 -WorkDirectory (Join-Path $junctionPath 'child') -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'REPARSE_POINT_BLOCKED'
    $destinationJunctionTarget = Join-Path $runRoot 'destination-junction-target'
    [IO.Directory]::CreateDirectory($destinationJunctionTarget) | Out-Null
    $destinationJunction = Join-Path $sources 'blocked-junction'
    New-Item -ItemType Junction -Path $destinationJunction -Target $destinationJunctionTarget | Out-Null
    Expect-Failure 'ReparsePointDestinationBlocked' {
        & $wrapper -Action Publish -PreviewPath $preview -ExpectedPdfSha256 $pdfHashBefore -ExpectedPreviewSha256 $previewHash -DestinationPath (Join-Path $destinationJunction 'k1-lite-fixture--TEXT.md') | Out-Null
    } 'REPARSE_POINT_BLOCKED'

    $rusWork = Join-Path $projectRoot '_work\K1\k1-lite\rus-missing'
    Expect-Failure 'MissingOcrLanguageFailsClosed' {
        & $wrapper -Action OcrPreview -PdfPath $pdf -ExpectedPdfSha256 $pdfHashBefore -OcrPages '3' -OcrLanguages 'rus' -Dpi 300 -WorkDirectory $rusWork -PythonPath $PythonPath -TesseractPath $TesseractPath | Out-Null
    } 'OCR_LANGUAGE_MISSING'
    Add-Result 'MissingLanguageCreatesNoPreview' (-not (Test-Path -LiteralPath $rusWork)) 'Brak katalogu roboczego po błędzie języka.'

    $badPdf = Join-Path $sources 'corrupt.pdf'
    [IO.File]::WriteAllBytes($badPdf, [byte[]](1, 2, 3, 4, 5))
    Expect-Failure 'CorruptPdfFailsClosed' {
        & $wrapper -Action InspectNative -PdfPath $badPdf -PythonPath $PythonPath | Out-Null
    } 'PDF_OPEN_FAILED|PDF_INVALID'

    $results | Format-Table -AutoSize
    Write-Output "RESULT: K1_LITE_TEST_PASS ($($results.Count) assertions)"
} finally {
    if ($KeepTestDirectory) {
        Write-Output "TEST_DIRECTORY: $runRoot"
    } elseif (Test-Path -LiteralPath $runRoot) {
        $resolved = [IO.Path]::GetFullPath($runRoot)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or $resolved -eq $tempRoot) {
            throw "UNSAFE_TEST_CLEANUP: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
