[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourcePath,
    [string]$Locator,
    [string]$Quote,
    [string]$ExpectedSourceSha256,
    [string]$ExpectedPdfPath,
    [string]$ExpectedPdfSha256,
    [ValidateRange(0, 2)]
    [int]$Tolerance = 2,
    [switch]$ValidateOnly,
    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'

function New-Result([string]$Verdict, [string]$Code, [string]$Detail, [int]$Page = 0, [int]$From = 0, [int]$To = 0) {
    return [pscustomobject]@{
        Schema = 'K1_LITE_EVIDENCE_CHECK_V1'
        Verdict = $Verdict
        Code = $Code
        Detail = $Detail
        Page = $Page
        FromLine = $From
        ToLine = $To
    }
}

function Get-NormalizedText([string]$Value) {
    return $Value.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($algorithm.ComputeHash($Bytes))) } finally { $algorithm.Dispose() }
}

function Get-ProjectRoot([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = [IO.Directory]::GetParent($full)
    while ($cursor) {
        if ($cursor.Name.Equals('sources', [StringComparison]::OrdinalIgnoreCase) -or $cursor.Name.Equals('_work', [StringComparison]::OrdinalIgnoreCase)) {
            if ($cursor.Parent) { return $cursor.Parent.FullName }
        }
        $cursor = $cursor.Parent
    }
    return $null
}

function Test-Within([string]$Candidate, [string]$Root) {
    $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root), [IO.Path]::GetFullPath($Candidate))
    return -not (
        [IO.Path]::IsPathRooted($relative) -or
        $relative -eq '..' -or
        $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)", [StringComparison]::Ordinal) -or
        $relative.StartsWith("..$([IO.Path]::AltDirectorySeparatorChar)", [StringComparison]::Ordinal)
    )
}

function Test-NoReparsePoint([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if (-not $parent -or $parent.FullName -eq $cursor) { break }
        $cursor = $parent.FullName
    }
    return $true
}

function Read-K1LiteDocument([string]$Path) {
    $raw = Get-NormalizedText ([IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false)))
    $lines = @($raw -split "`n")
    if ($lines.Count -lt 4 -or $lines[0] -ne '---') { throw 'FRONTMATTER_INVALID: opening delimiter missing' }
    $frontmatterEnd = -1
    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq '---') { $frontmatterEnd = $index; break }
    }
    if ($frontmatterEnd -lt 0) { throw 'FRONTMATTER_INVALID: closing delimiter missing' }
    $frontmatter = @{}
    for ($index = 1; $index -lt $frontmatterEnd; $index++) {
        $match = [regex]::Match($lines[$index], '^(?<key>[A-Z0-9_]+):\s*(?<value>.*)$')
        if ($match.Success) {
            $key = $match.Groups['key'].Value
            $value = $match.Groups['value'].Value.Trim()
            if ($value.StartsWith('"')) {
                try { $value = $value | ConvertFrom-Json -DateKind String } catch { throw "FRONTMATTER_JSON_STRING_INVALID: $key" }
            }
            $frontmatter[$key] = $value
        }
    }
    foreach ($required in 'PDF_TEXT_SCHEMA', 'ORIGINAL_PDF', 'ORIGINAL_PDF_SHA256', 'PHYSICAL_PAGES', 'OCR_LANGUAGES', 'OCR_ENGINE') {
        if (-not $frontmatter.ContainsKey($required)) { throw "FRONTMATTER_FIELD_MISSING: $required" }
    }
    if ($frontmatter.PDF_TEXT_SCHEMA -ne 'K1_LITE_PDF_TEXT_V1') { throw "SCHEMA_UNSUPPORTED: $($frontmatter.PDF_TEXT_SCHEMA)" }
    if ($frontmatter.ORIGINAL_PDF_SHA256 -notmatch '^[0-9A-F]{64}$') { throw 'FRONTMATTER_PDF_SHA_INVALID' }
    if ($frontmatter.OCR_ENGINE -ne 'tesseract') { throw "OCR_ENGINE_INVALID: $($frontmatter.OCR_ENGINE)" }
    if ($frontmatter.OCR_LANGUAGES -notmatch '^[a-z0-9_]+(?:\+[a-z0-9_]+)*$' -or (($frontmatter.OCR_LANGUAGES -split '\+') -contains 'osd')) {
        throw "OCR_LANGUAGES_INVALID: $($frontmatter.OCR_LANGUAGES)"
    }
    $physicalPages = 0
    if (-not [int]::TryParse($frontmatter.PHYSICAL_PAGES, [ref]$physicalPages) -or $physicalPages -lt 1) { throw 'PHYSICAL_PAGES_INVALID' }

    $cursor = $frontmatterEnd + 1
    if ($cursor -lt $lines.Count -and $lines[$cursor] -eq '') { $cursor++ }
    $pages = @{}
    $expectedPage = 1
    $beginPattern = '^<!-- PDF_PAGE_BEGIN: P(?<page>\d{4}); METHOD: (?<method>NATIVE|OCR); PAGE_TEXT_SHA256: (?<sha>[0-9A-F]{64}); FLAGS: (?<flags>NONE|LAYOUT_REVIEW_REQUIRED) -->$'
    $endPattern = '^<!-- PDF_PAGE_END: P(?<page>\d{4}) -->$'

    while ($cursor -lt $lines.Count) {
        if ($cursor -eq ($lines.Count - 1) -and $lines[$cursor] -eq '') { break }
        $begin = [regex]::Match($lines[$cursor], $beginPattern)
        if (-not $begin.Success) { throw "PAGE_BEGIN_INVALID: physical line $($cursor + 1)" }
        $pageNumber = [int]$begin.Groups['page'].Value
        if ($pageNumber -ne $expectedPage) { throw "PAGE_ORDER_INVALID: expected=P$($expectedPage.ToString('0000')) actual=P$($pageNumber.ToString('0000'))" }
        $method = $begin.Groups['method'].Value
        $flags = $begin.Groups['flags'].Value
        if ($method -eq 'OCR' -and $flags -ne 'LAYOUT_REVIEW_REQUIRED') { throw "OCR_LAYOUT_FLAG_MISSING: P$($pageNumber.ToString('0000'))" }
        if ($method -eq 'NATIVE' -and $flags -ne 'NONE') { throw "NATIVE_FLAGS_INVALID: P$($pageNumber.ToString('0000'))" }
        $expectedPageHash = $begin.Groups['sha'].Value
        $cursor++
        $body = [System.Collections.Generic.List[string]]::new()
        $foundEnd = $false
        while ($cursor -lt $lines.Count) {
            if ($lines[$cursor] -match '^<!-- PDF_PAGE_BEGIN:') { throw "NESTED_PAGE_BEGIN: P$($pageNumber.ToString('0000'))" }
            $end = [regex]::Match($lines[$cursor], $endPattern)
            if ($end.Success) {
                $endNumber = [int]$end.Groups['page'].Value
                if ($endNumber -ne $pageNumber) { throw "PAGE_END_MISMATCH: begin=P$($pageNumber.ToString('0000')) end=P$($endNumber.ToString('0000'))" }
                $foundEnd = $true
                break
            }
            if ($lines[$cursor] -match '^<!-- PDF_PAGE_END:') { throw "PAGE_END_INVALID: physical line $($cursor + 1)" }
            if ($lines[$cursor].EndsWith(' ') -or $lines[$cursor].EndsWith("`t")) { throw "PAGE_BODY_NOT_NORMALIZED: P$($pageNumber.ToString('0000'))" }
            $body.Add($lines[$cursor])
            $cursor++
        }
        if (-not $foundEnd) { throw "PAGE_END_MISSING: P$($pageNumber.ToString('0000'))" }
        if ($body.Count -gt 0 -and ($body[0] -eq '' -or $body[$body.Count - 1] -eq '')) { throw "PAGE_BODY_EDGE_BLANK: P$($pageNumber.ToString('0000'))" }
        $bodyText = if ($body.Count -eq 0) { '' } else { ($body -join "`n") + "`n" }
        $actualPageHash = Get-Sha256Bytes ([Text.UTF8Encoding]::new($false).GetBytes($bodyText))
        if ($actualPageHash -ne $expectedPageHash) { throw "PAGE_TEXT_SHA_MISMATCH: P$($pageNumber.ToString('0000'))" }
        $pages[$pageNumber] = [pscustomobject]@{
            Number = $pageNumber
            Method = $method
            Flags = $flags
            Hash = $actualPageHash
            Lines = @($body)
        }
        $expectedPage++
        $cursor++
        if ($cursor -lt $lines.Count -and $lines[$cursor] -eq '') { $cursor++ }
    }
    if ($pages.Count -ne $physicalPages) { throw "PAGE_COUNT_MISMATCH: frontmatter=$physicalPages blocks=$($pages.Count)" }
    $ocrPageCount = @($pages.Values | Where-Object Method -eq 'OCR').Count
    if ($frontmatter.OCR_LANGUAGES -eq 'none' -and $ocrPageCount -ne 0) { throw 'OCR_LANGUAGE_PAGE_CONSISTENCY_INVALID' }
    if ($frontmatter.OCR_LANGUAGES -ne 'none' -and $ocrPageCount -eq 0) { throw 'OCR_LANGUAGE_PAGE_CONSISTENCY_INVALID' }
    return [pscustomobject]@{ Raw = $raw; Frontmatter = $frontmatter; Pages = $pages; PhysicalPages = $physicalPages }
}

$result = $null
try {
    $resolvedSource = [IO.Path]::GetFullPath($SourcePath)
    if (-not (Test-Path -LiteralPath $resolvedSource -PathType Leaf)) { throw "SOURCE_NOT_FOUND: $resolvedSource" }
    if (-not (Test-NoReparsePoint $resolvedSource)) { throw "REPARSE_POINT_BLOCKED: $resolvedSource" }
    if (-not $ExpectedSourceSha256) { throw 'EXPECTED_SOURCE_SHA_REQUIRED' }
    if ($ExpectedSourceSha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'EXPECTED_SOURCE_SHA_INVALID' }
    $sourceHash = (Get-FileHash -LiteralPath $resolvedSource -Algorithm SHA256).Hash
    if ($sourceHash -ne $ExpectedSourceSha256.ToUpperInvariant()) { throw "SOURCE_HASH_MISMATCH: expected=$($ExpectedSourceSha256.ToUpperInvariant()) actual=$sourceHash" }
    $document = Read-K1LiteDocument $resolvedSource

    if (-not $ExpectedPdfPath -or -not $ExpectedPdfSha256) { throw 'PDF_PROVENANCE_PAIR_REQUIRED' }
    if ($ExpectedPdfSha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'EXPECTED_PDF_SHA_INVALID' }
    $projectRoot = Get-ProjectRoot $resolvedSource
    if (-not $projectRoot) { throw 'PROJECT_ROOT_NOT_FOUND' }
    $frontmatterPdf = $document.Frontmatter.ORIGINAL_PDF.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::IsPathRooted($frontmatterPdf)) { throw 'ORIGINAL_PDF_ABSOLUTE_BLOCKED' }
    $resolvedFrontmatterPdf = [IO.Path]::GetFullPath((Join-Path $projectRoot $frontmatterPdf))
    $resolvedExpectedPdf = [IO.Path]::GetFullPath($ExpectedPdfPath)
    if (-not (Test-Within $resolvedFrontmatterPdf (Join-Path $projectRoot 'sources'))) { throw 'BACKING_PDF_OUTSIDE_PROJECT' }
    if ($resolvedFrontmatterPdf -ne $resolvedExpectedPdf) { throw 'BACKING_PDF_PATH_MISMATCH' }
    if (-not (Test-NoReparsePoint $resolvedExpectedPdf)) { throw 'REPARSE_POINT_BLOCKED' }
    if (-not (Test-Path -LiteralPath $resolvedExpectedPdf -PathType Leaf)) { throw 'BACKING_PDF_NOT_FOUND' }
    $actualPdfHash = (Get-FileHash -LiteralPath $resolvedExpectedPdf -Algorithm SHA256).Hash
    if ($actualPdfHash -ne $ExpectedPdfSha256.ToUpperInvariant()) { throw 'BACKING_PDF_HASH_MISMATCH' }
    if ($document.Frontmatter.ORIGINAL_PDF_SHA256 -ne $actualPdfHash) { throw 'FRONTMATTER_PDF_HASH_MISMATCH' }

    if ($ValidateOnly) {
        $result = New-Result 'PASS' 'DOCUMENT_VALID' "pages=$($document.PhysicalPages)"
    } else {
        if ([string]::IsNullOrWhiteSpace($Locator) -or $null -eq $Quote) { throw 'LOCATOR_AND_QUOTE_REQUIRED' }
        $locatorMatch = [regex]::Match($Locator, '^P(?<page>\d{4})/L(?<from>[1-9]\d*)-L(?<to>[1-9]\d*)$')
        if (-not $locatorMatch.Success) { throw "LOCATOR_INVALID: $Locator" }
        $pageNumber = [int]$locatorMatch.Groups['page'].Value
        $from = [int]$locatorMatch.Groups['from'].Value
        $to = [int]$locatorMatch.Groups['to'].Value
        if ($to -lt $from) { throw 'LOCATOR_RANGE_INVALID' }
        if (-not $document.Pages.Contains($pageNumber)) { throw 'LOCATOR_PAGE_OUT_OF_RANGE' }
        $page = $document.Pages[$pageNumber]
        $pageLines = @($page.Lines)
        if ($from -gt $pageLines.Count -or $to -gt $pageLines.Count) { throw 'LOCATOR_LINE_OUT_OF_RANGE' }
        $windowFrom = [Math]::Max(1, $from - $Tolerance)
        $windowTo = [Math]::Min($pageLines.Count, $to + $Tolerance)
        $window = if ($windowTo -ge $windowFrom) { ($pageLines[($windowFrom - 1)..($windowTo - 1)] -join "`n") } else { '' }
        $normalizedQuote = (Get-NormalizedText $Quote).Trim("`n")
        if ([string]::IsNullOrEmpty($normalizedQuote)) { throw 'QUOTE_EMPTY' }
        if ($window.IndexOf($normalizedQuote, [StringComparison]::Ordinal) -lt 0) { throw 'QUOTE_NOT_FOUND_IN_PAGE_LOCAL_WINDOW' }
        $result = New-Result 'PASS' 'QUOTE_VERIFIED' "window=L$windowFrom-L$windowTo" $pageNumber $from $to
    }
} catch {
    $baseMessage = $_.Exception.Message
    $code = ($baseMessage -split ':', 2)[0]
    $message = $baseMessage
    if ($_.ScriptStackTrace) { $message = "$message @ $($_.ScriptStackTrace -replace "`r?`n", ' | ')" }
    $result = New-Result 'FAIL' $code $message
}

$result
if ($result.Verdict -eq 'FAIL' -and -not $NoExit) {
    throw "K1_LITE_EVIDENCE_FAIL: $($result.Code)"
}
