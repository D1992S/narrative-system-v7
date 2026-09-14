[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [string]$EvidencePath,

    [switch]$PendingReview,

    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$canonicalBasePath = Join-Path $project '01-baza-dowodow.md'
$basePath = if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $canonicalBasePath
} elseif ([IO.Path]::IsPathRooted($EvidencePath)) {
    [IO.Path]::GetFullPath($EvidencePath)
} else {
    [IO.Path]::GetFullPath((Join-Path $project $EvidencePath))
}
$contractPath = Join-Path $project '00-fundament-projektu.md'
$sourceDir = Join-Path $project 'sources'
$metaPath = Join-Path $project 'meta.md'
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')

$projectPrefix = $project.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($basePath -ne $canonicalBasePath -and -not $basePath.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'EvidencePath musi wskazywać plik wewnątrz projektu.'
}
if ($PendingReview) {
    $pendingRoot = [IO.Path]::GetFullPath((Join-Path $project '_work\K1\k1-lite-v2'))
    $pendingPrefix = $pendingRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $basePath.StartsWith($pendingPrefix, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($basePath) -notlike 'K1-COMPILED-*.md') {
        throw 'Tryb PendingReview przyjmuje wyłącznie K1-COMPILED-*.md z _work/K1/k1-lite-v2/.'
    }
} elseif ($basePath -ne $canonicalBasePath) {
    throw 'EvidencePath poza kanonicznym 01-baza-dowodow.md wymaga przełącznika PendingReview.'
}

function Get-FieldValue {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-TextSha256 {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','')
    } finally {
        $sha.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $basePath -PathType Leaf)) {
    $errors.Add("Brak pliku bazy dowodów: $basePath")
    $content = ''
} else {
    $baseItem = Get-Item -LiteralPath $basePath -Force
    if (($baseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Plik bazy dowodów nie może być dowiązaniem ani reparse pointem.'
    }
    $content = Get-Content -LiteralPath $basePath -Raw -Encoding UTF8
}

$meta = if (Test-Path -LiteralPath $metaPath -PathType Leaf) { Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 } else { '' }
$workflowRevision = Get-FieldValue -Text $meta -Name 'WORKFLOW_REVISION'
$metaEvidenceSchema = Get-FieldValue -Text $meta -Name 'EVIDENCE_SCHEMA'
$k1ResearchMode = Get-FieldValue -Text $meta -Name 'K1_RESEARCH_MODE'
$k1LiteV2WorkflowRevisions = @(
    '2026-08-31_NARRATIVE_V2',
    '2026-08-30_K1_LITE_V2'
)
$isK1LiteV2Workflow = $workflowRevision -in $k1LiteV2WorkflowRevisions
try {
    if ($isK1LiteV2Workflow -and $metaEvidenceSchema -eq 'MINIMAL_EVIDENCE_V4_PAGELOC') {
        $originState = Assert-SystemV7CurrentProjectOrigin -ProjectPath $project -MetaText $meta
    } elseif ($script:SystemV7LegacyWorkflowSchemaMap.Contains($workflowRevision) -and
        [string]$script:SystemV7LegacyWorkflowSchemaMap[$workflowRevision] -ceq $metaEvidenceSchema) {
        $originState = Assert-SystemV7LegacyProjectOrigin -ProjectPath $project -MetaText $meta
    } else {
        throw "UNSUPPORTED_WORKFLOW_SCHEMA_PAIR: $workflowRevision + $metaEvidenceSchema"
    }
} catch {
    $errors.Add("Pochodzenie projektu: $($_.Exception.Message)")
}
if ($isK1LiteV2Workflow -and $k1ResearchMode -eq 'MANUAL_APPROVED') {
    $manualFallbackState = Get-K1ManualFallbackReceiptState -ProjectPath $project
    foreach ($manualProblem in @($manualFallbackState.Errors)) { $errors.Add("MANUAL_APPROVED: $manualProblem") }
}

$schema = Get-FieldValue -Text $content -Name 'K1_SCHEMA'
if (-not $PendingReview -and $content -match '(?m)^#\s+01\s+—.*K1-COMPILED') {
    $errors.Add('Kanoniczny 01-baza-dowodow.md nie może zachować oznaczenia K1-COMPILED.')
}
if (-not $schema) {
    $warnings.Add('Baza nie deklaruje K1_SCHEMA; traktowana jako starszy format bez walidacji semantycznej Compact K1.')
    $legacyResult = [pscustomobject]@{
        ProjectPath = $project
        EvidencePath = $basePath
        PendingReview = [bool]$PendingReview
        Schema = 'LEGACY'
        Sources = 0
        Cards = 0
        CoreCards = 0
        Errors = $errors.Count
        Warnings = $warnings.Count
        ErrorDetails = $errors
        WarningDetails = $warnings
        StructureVerdict = if ($errors.Count -eq 0) { 'LEGACY_UNCHECKED' } else { 'STRUCTURE_FAIL' }
        GateReady = $false
        ReadyForImport = $false
    }
    $legacyResult
    if ($errors.Count -gt 0 -and -not $NoExit) { exit 1 }
    return
}

if ($schema -in @('COMPACT_EVIDENCE_V2', 'MINIMAL_EVIDENCE_V3', 'MINIMAL_EVIDENCE_V4_PAGELOC')) {
    # ============ Schematy kompaktowe V2/V3 oraz aktualny V4 ============
    # Hash liczony per źródło zamiast jednej sygnatury całego drzewa.
    # Zmiana jednego pliku unieważnia wyłącznie jego rekord i karty.
    # `sources/_oryginaly/` to zaplecze: nie wymaga rozliczania jednostkowego.
    #
    # Rejestr źródeł jest wspólny dla obu schematów. Różni je wyłącznie rekord karty:
    # V2 opisuje kartę dziewięcioma polami i pozwala na parafrazę, którą musi ocenić
    # człowiek. V3 zostawia cztery pola, wymaga dosłownej TREŚCI i dzięki temu całą
    # kontrolę wierności wykonuje maszyna.

    $isMinimalV3 = $schema -eq 'MINIMAL_EVIDENCE_V3'
    $isMinimalV4 = $schema -eq 'MINIMAL_EVIDENCE_V4_PAGELOC'
    $isMinimal = $isMinimalV3 -or $isMinimalV4

    # V4 jest schematem zamkniętym. Pierwszy znaleziony wpis nie może po cichu
    # przesłonić duplikatu, a obce pole w nagłówku nie może zostać zignorowane.
    if ($isMinimalV4) {
        $firstSection = [regex]::Match($content, '(?m)^##\s+')
        $headerText = if ($firstSection.Success) { $content.Substring(0, $firstSection.Index) } else { $content }
        $headerFieldMatches = [regex]::Matches($headerText, '(?m)^(?<name>[\p{Lu}\d_ĄĆĘŁŃÓŚŹŻ]+):[ \t]*(?<value>.*)$')
        $allowedHeaderFields = @(
            'K1_SCHEMA','LOCATOR_POLICY','STATUS','DATA_ODCIĘCIA','LEAD_AGENT_ID','VERIFY_AGENT_ID',
            'RESEARCH_ROUNDS','STOP_REASON','STRUCTURE_CHECK','SOURCE_FIDELITY_CHECK','SATURATION_CHECK',
            'K1_VERDICT','K1_ORIGIN','K1_ORIGIN_VERSION','K1_EXPORT_PATH','K1_EXPORT_SHA256',
            'CORPUS_COVERAGE_REVIEWED','K0_COVERAGE_REVIEWED','SOURCE_CLASSES_REVIEWED'
        )
        # Nagłówek V4 ma gramatykę zamkniętą: dokładny tytuł, puste linie i
        # wyłącznie jawnie dozwolone pola zapisane z dokładną wielkością liter.
        # Dzięki temu zwykłe zdanie albo mixed-case pole nie może zostać
        # potraktowane jak niewidzialna instrukcja przed pierwszą sekcją.
        $headerLines = @($headerText -split "`r?`n")
        $expectedHeaderTitle = '# 01 — MINIMALNA BAZA DOWODÓW'
        $headerTitleCount = @($headerLines | Where-Object { $_ -ceq $expectedHeaderTitle }).Count
        if ($headerTitleCount -ne 1) {
            $errors.Add("V4_HEADER_TITLE_COUNT_INVALID: count=$headerTitleCount expected=1")
        }
        foreach ($headerLine in $headerLines) {
            if ([string]::IsNullOrWhiteSpace($headerLine) -or $headerLine -ceq $expectedHeaderTitle) { continue }
            $allowedLine = $false
            foreach ($allowedHeaderField in $allowedHeaderFields) {
                if ($headerLine -cmatch ('^' + [regex]::Escape($allowedHeaderField) + ':[ \t]*.*$')) {
                    $allowedLine = $true
                    break
                }
            }
            if (-not $allowedLine) {
                $errors.Add("V4_HEADER_RESIDUE_OR_UNKNOWN_LINE: $($headerLine.Trim())")
            }
        }
        $requiredHeaderFields = @($allowedHeaderFields | Where-Object { $_ -ne 'VERIFY_AGENT_ID' })
        $headerFieldNames = @($headerFieldMatches | ForEach-Object { $_.Groups['name'].Value })
        foreach ($unknownHeaderField in @($headerFieldNames | Where-Object { $_ -notin $allowedHeaderFields } | Select-Object -Unique)) {
            $errors.Add("V4_HEADER_UNKNOWN_FIELD: $unknownHeaderField")
        }
        foreach ($requiredHeaderField in $requiredHeaderFields) {
            $fieldCount = @($headerFieldNames | Where-Object { $_ -ceq $requiredHeaderField }).Count
            if ($fieldCount -ne 1) { $errors.Add("V4_HEADER_FIELD_COUNT_INVALID: $requiredHeaderField count=$fieldCount expected=1") }
        }
        $verifyAgentFieldCount = @($headerFieldNames | Where-Object { $_ -ceq 'VERIFY_AGENT_ID' }).Count
        if ($verifyAgentFieldCount -gt 1) { $errors.Add("V4_HEADER_FIELD_COUNT_INVALID: VERIFY_AGENT_ID count=$verifyAgentFieldCount expected=0_or_1") }

        # Po usunięciu całych bloków kart żaden drugi obszar dokumentu nie może
        # przemycać własnych pól sterujących. Pozwala to wykryć także duplikat
        # STATUS dopisany pod pierwszym nagłówkiem, którego Get-FieldValue nie widzi.
        $contentWithoutCards = [regex]::Replace($content, '(?ms)^###\s+#P-\d{3,}\s*\r?\n.*?(?=^###\s+#P-\d{3,}\s*$|^##\s+|\z)', '')
        # Poza kartami każda lewostronna linia wyglądająca jak pole `nazwa:`
        # jest polem sterującym, niezależnie od wielkości liter. Dopuszczenie
        # wyłącznie exact allowlisty zamyka bypass typu `Instrukcja:`.
        $documentFieldMatches = [regex]::Matches($contentWithoutCards, '(?m)^(?<name>[\p{L}\d_/-]+):[ \t]*(?<value>.*)$')
        $documentFieldNames = @($documentFieldMatches | ForEach-Object { $_.Groups['name'].Value })
        $allowedDocumentFields = @($allowedHeaderFields + 'NIEROZLICZONE_ŹRÓDŁA')
        foreach ($unknownDocumentField in @($documentFieldNames | Where-Object { $_ -cnotin $allowedDocumentFields } | Select-Object -Unique)) {
            $errors.Add("V4_DOCUMENT_UNKNOWN_FIELD: $unknownDocumentField")
        }
        foreach ($headerField in $allowedHeaderFields) {
            $globalCount = @($documentFieldNames | Where-Object { $_ -ceq $headerField }).Count
            $inHeaderCount = @($headerFieldNames | Where-Object { $_ -ceq $headerField }).Count
            if ($globalCount -ne $inHeaderCount) {
                $errors.Add("V4_HEADER_FIELD_OUTSIDE_HEADER: $headerField global=$globalCount header=$inHeaderCount")
            }
        }
        $unaccountedFieldCount = @($documentFieldNames | Where-Object { $_ -ceq 'NIEROZLICZONE_ŹRÓDŁA' }).Count
        if ($unaccountedFieldCount -ne 1) { $errors.Add("V4_DOCUMENT_FIELD_COUNT_INVALID: NIEROZLICZONE_ŹRÓDŁA count=$unaccountedFieldCount expected=1") }
    }
    $locatorPolicy = Get-FieldValue -Text $content -Name 'LOCATOR_POLICY'
    $effectiveLocatorPolicy = if ([string]::IsNullOrWhiteSpace($locatorPolicy)) { 'PAGE_ONLY_V1' } else { $locatorPolicy }
    if ($isMinimalV4 -and $effectiveLocatorPolicy -notin @('PAGE_ONLY_V1','MIXED_V1')) {
        $errors.Add("LOCATOR_POLICY ma niedozwoloną wartość '$locatorPolicy'.")
    }
    $originForLocatorPolicy = Get-FieldValue -Text $content -Name 'K1_ORIGIN'
    $versionForLocatorPolicy = Get-FieldValue -Text $content -Name 'K1_ORIGIN_VERSION'
    if ($isMinimalV4 -and $originForLocatorPolicy -eq 'K1_LITE_V2' -and $versionForLocatorPolicy -match '^\d+\.\d+\.\d+') {
        try {
            if ([version](($versionForLocatorPolicy -split '\+')[0]) -ge [version]'2.1.0' -and $locatorPolicy -ne 'MIXED_V1') {
                $errors.Add("K1-Lite V2 od wersji 2.1.0 wymaga LOCATOR_POLICY: MIXED_V1, jest '$locatorPolicy'.")
            }
        } catch { $errors.Add("K1_ORIGIN_VERSION nie pozwala ustalić polityki lokalizatorów: '$versionForLocatorPolicy'.") }
    }
    if ($PendingReview -and -not $isMinimalV4) {
        $errors.Add('Tryb PendingReview nowego K1 obsługuje wyłącznie MINIMAL_EVIDENCE_V4_PAGELOC.')
    }
    $backupDirName = '_oryginaly'
    $canonicalExtensions = @('.md', '.txt', '.srt', '.vtt')

    function Get-NormalizedText {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text)) { return '' }
        $formD = $Text.Normalize([Text.NormalizationForm]::FormD)
        $builder = [System.Text.StringBuilder]::new($formD.Length)
        foreach ($char in $formD.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
                [void]$builder.Append($char)
            }
        }
        $flat = $builder.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
        $flat = $flat.Replace('ł','l')
        $flat = [regex]::Replace($flat, '[„""''`’‚>*_#]', '')
        $flat = $flat.Replace('–','-').Replace('—','-').Replace('…','...')
        $flat = [regex]::Replace($flat, '\s+', ' ')
        return $flat.Trim()
    }

    function Get-ExactComparableText {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text)) { return '' }
        # V4 obiecuje fragment dosłowny. Dopuszczamy wyłącznie różnice techniczne
        # kodowania Unicode i białych znaków, nie usuwamy interpunkcji ani znaków.
        $flat = $Text.Normalize([Text.NormalizationForm]::FormKC)
        $flat = [regex]::Replace($flat, '\s+', ' ')
        return $flat.Trim()
    }

    function ConvertTo-CanonicalSubtitleTimestamp {
        param([Parameter(Mandatory)][string]$Value)
        $match = [regex]::Match($Value.Trim(), '^(?:(?<h>\d{1,2}):)?(?<m>\d{2}):(?<s>\d{2})[,.](?<ms>\d{3})$')
        if (-not $match.Success) { throw "SUBTITLE_TIMESTAMP_INVALID: $Value" }
        $hours = if ($match.Groups['h'].Success) { [int]$match.Groups['h'].Value } else { 0 }
        $minutes = [int]$match.Groups['m'].Value
        $seconds = [int]$match.Groups['s'].Value
        $milliseconds = [int]$match.Groups['ms'].Value
        if ($minutes -gt 59 -or $seconds -gt 59) { throw "SUBTITLE_TIMESTAMP_INVALID: $Value" }
        [pscustomobject]@{
            Text = '{0:D2}:{1:D2}:{2:D2}.{3:D3}' -f $hours,$minutes,$seconds,$milliseconds
            Milliseconds = ((($hours * 60 + $minutes) * 60 + $seconds) * 1000 + $milliseconds)
        }
    }

    function Get-SubtitleCues {
        param([Parameter(Mandatory)][string]$Path)
        $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false)).Replace("`r`n","`n").Replace("`r","`n")
        $lines = @($raw -split "`n")
        $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
        $cursor = 0
        if ($extension -eq '.vtt' -and $lines.Count -gt 0 -and $lines[0].Trim().StartsWith('WEBVTT')) { $cursor = 1 }
        $cues = [System.Collections.Generic.List[object]]::new()
        while ($cursor -lt $lines.Count) {
            while ($cursor -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$cursor])) { $cursor++ }
            if ($cursor -ge $lines.Count) { break }
            $marker = $lines[$cursor].Trim()
            if ($extension -eq '.vtt' -and $marker -match '^(NOTE|STYLE|REGION)(?:\s|$)') {
                $cursor++
                while ($cursor -lt $lines.Count -and -not [string]::IsNullOrWhiteSpace($lines[$cursor])) { $cursor++ }
                continue
            }
            $timestampPattern = '^(?<start>(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3})\s*-->\s*(?<end>(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3})(?:\s+.*)?$'
            $timeMatch = [regex]::Match($marker, $timestampPattern)
            if (-not $timeMatch.Success -and $cursor + 1 -lt $lines.Count) {
                $possible = $lines[$cursor + 1].Trim()
                $timeMatch = [regex]::Match($possible, $timestampPattern)
                if ($timeMatch.Success) { $cursor++ }
            }
            if (-not $timeMatch.Success) { throw "SUBTITLE_CUE_INVALID_AT_LINE: $($cursor + 1)" }
            $start = ConvertTo-CanonicalSubtitleTimestamp $timeMatch.Groups['start'].Value
            $end = ConvertTo-CanonicalSubtitleTimestamp $timeMatch.Groups['end'].Value
            if ($end.Milliseconds -le $start.Milliseconds) { throw "SUBTITLE_CUE_RANGE_INVALID_AT_LINE: $($cursor + 1)" }
            $cursor++
            $textLines = [System.Collections.Generic.List[string]]::new()
            while ($cursor -lt $lines.Count -and -not [string]::IsNullOrWhiteSpace($lines[$cursor])) {
                if ($lines[$cursor] -match '-->') { throw "SUBTITLE_CUE_SEPARATOR_MISSING_AT_LINE: $($cursor + 1)" }
                $textLines.Add($lines[$cursor]); $cursor++
            }
            if ($textLines.Count -eq 0) { throw "SUBTITLE_CUE_TEXT_EMPTY_AT_LINE: $($cursor + 1)" }
            $cues.Add([pscustomobject]@{ Start=$start.Text; End=$end.Text; StartMs=$start.Milliseconds; EndMs=$end.Milliseconds; Lines=@($textLines) })
        }
        if ($cues.Count -eq 0) { throw 'SUBTITLE_NO_CUES' }
        return @($cues)
    }

    $isPlaceholder = { param($v) [string]::IsNullOrWhiteSpace($v) -or $v -match '^\[.*\]$|^DO UZUPEŁNIENIA$' }
    $isDash = { param($v) $v -in @('—','-','BRAK','NIE DOTYCZY') }

    $sourceFiles = @()
    $backupFileCount = 0
    if (Test-Path -LiteralPath $sourceDir -PathType Container) {
        $supportedExtensions = @('.pdf') + $canonicalExtensions
        $backupRoot = Join-Path $sourceDir $backupDirName
        if (Test-Path -LiteralPath $backupRoot -PathType Container) {
            $backupFileCount = @(Get-ChildItem -LiteralPath $backupRoot -Recurse -File -ErrorAction SilentlyContinue).Count
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)) {
            $relative = [IO.Path]::GetRelativePath($sourceDir, $file.FullName).Replace('\','/')
            if ($relative -like "$backupDirName/*") { continue }
            if ($file.DirectoryName -ne [IO.Path]::GetFullPath($sourceDir) -and $file.Extension.ToLowerInvariant() -in $supportedExtensions) {
                $errors.Add("Wspierany plik źródłowy jest w niedozwolonym podfolderze sources/: $($file.FullName). Przenieś go bezpośrednio do sources/ albo do sources/$backupDirName/.")
                continue
            }
            if ($file.DirectoryName -ne [IO.Path]::GetFullPath($sourceDir) -or $file.Extension.ToLowerInvariant() -notin $supportedExtensions) { continue }
            $sourceFiles += [pscustomobject]@{ File = $file; Relative = $relative; Name = $file.Name }
        }
    } else {
        $errors.Add('Brak katalogu sources/.')
    }
    $duplicateSourceNames = @($sourceFiles | Group-Object Name | Where-Object Count -gt 1 | ForEach-Object Name)

    if ($content -match '(?m)^VERIFIED_SOURCE_TREE_SHA256:') {
        $warnings.Add('COMPACT_EVIDENCE_V2 nie używa VERIFIED_SOURCE_TREE_SHA256; usuń przestarzałe pole. Kontrolę pełnią hashe per źródło.')
    }

    $sourceMatches = [regex]::Matches($content, '(?m)^\|\s*#?(S-\d{3,})\s*\|(.*?)\|\s*$')
    $sourceIds = [System.Collections.Generic.List[string]]::new()
    $sourceRows = [System.Collections.Generic.List[object]]::new()
    $allowedSourceClasses = @('A','B','C','D')
    $allowedSourceRoles = @('RDZEŃ','CELOWE','REZERWA','WYŁĄCZONE','TECHNICZNE')
    $hashVerified = 0

    foreach ($match in $sourceMatches) {
        $id = $match.Groups[1].Value
        $cells = @(("$id|$($match.Groups[2].Value)").Split('|') | ForEach-Object { $_.Trim() })
        $sourceIds.Add($id)
        if ($cells.Count -ne 10) {
            $errors.Add("${id}: wiersz rejestru V2 musi mieć dokładnie 10 kolumn (ID, plik, autor, data, klasa, rola, zakres, SHA-256, karty, uwagi); ma $($cells.Count)")
            continue
        }
        $fileRef = $cells[1]
        $author = $cells[2]
        $date = $cells[3]
        $sourceClass = $cells[4]
        $sourceRole = $cells[5]
        $checkedRange = $cells[6]
        $sha = $cells[7]
        $notes = $cells[9]

        if (& $isPlaceholder $fileRef) { $errors.Add("${id}: brak konkretnego pliku lub URL w rejestrze") }
        if ($sourceRole -notin $allowedSourceRoles) { $errors.Add("${id}: niedozwolona rola źródła '$sourceRole'") }

        $normalizedRef = $fileRef.Replace('\','/')
        $hasUrl = $normalizedRef -match '(?i)https?://'
        $isSubtree = $normalizedRef -match '/\*\*'
        $subtreePrefixes = @()
        if ($isSubtree) {
            foreach ($m in [regex]::Matches($normalizedRef, '([^;|]+?)/\*\*')) {
                $prefix = $m.Groups[1].Value.Trim().TrimStart('/')
                $prefix = $prefix -replace '^sources/', ''
                if ($prefix) { $subtreePrefixes += $prefix }
            }
            if ($sourceRole -ne 'TECHNICZNE') { $errors.Add("${id}: wzorzec 'katalog/**' jest dozwolony tylko dla roli TECHNICZNE") }
        }

        # Kanoniczny plik lokalny = pierwszy pasujący plik wskazany najwcześniej w komórce.
        $canonicalFile = $null
        $canonicalPos = [int]::MaxValue
        $matchedFiles = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $sourceFiles) {
            $namePattern = '(?i)(?<![\p{L}\p{N}_.-])' + [regex]::Escape($entry.Name) + '(?![\p{L}\p{N}_.-])'
            $relativePattern = '(?i)(?<![\p{L}\p{N}_.-])' + [regex]::Escape($entry.Relative) + '(?![\p{L}\p{N}_.-])'
            $pos = -1
            $relMatch = [regex]::Match($normalizedRef, $relativePattern)
            if ($relMatch.Success) { $pos = $relMatch.Index }
            elseif ($entry.Name -notin $duplicateSourceNames) {
                $nameMatch = [regex]::Match($normalizedRef, $namePattern)
                if ($nameMatch.Success) { $pos = $nameMatch.Index }
            }
            if ($pos -ge 0) {
                $matchedFiles.Add($entry.Relative)
                if ($pos -lt $canonicalPos) { $canonicalPos = $pos; $canonicalFile = $entry }
            }
        }

        $requiresFull = $sourceRole -in @('RDZEŃ','CELOWE')
        if ($requiresFull) {
            if ((& $isPlaceholder $author) -and -not ($author -eq 'NIEUSTALONE')) { $errors.Add("${id}: brak autora/instytucji albo jawnego NIEUSTALONE") }
            if ((& $isPlaceholder $date) -and -not ($date -eq 'NIEUSTALONE')) { $errors.Add("${id}: brak daty albo jawnego NIEUSTALONE") }
            $isTimedRange = $checkedRange -match '^\[(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3}\s*-\s*(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3}\]$'
            if (((& $isPlaceholder $checkedRange) -and -not $isTimedRange) -or $checkedRange -match '^NIEUSTALONE$') { $errors.Add("${id}: brak konkretnego zakresu sprawdzonego") }
            if ($sourceClass -notin $allowedSourceClasses) { $errors.Add("${id}: klasa źródła musi mieć A, B, C albo D, jest '$sourceClass'") }
        } elseif ($sourceClass -and -not (& $isDash $sourceClass) -and -not (& $isPlaceholder $sourceClass) -and $sourceClass -notin $allowedSourceClasses) {
            $errors.Add("${id}: klasa źródła musi mieć A, B, C, D albo '—', jest '$sourceClass'")
        }
        if ($sourceRole -eq 'WYŁĄCZONE' -and ((& $isPlaceholder $notes) -or $notes -match '^BRAK$|^NIEUSTALONE$')) {
            $errors.Add("${id}: źródło WYŁĄCZONE nie ma konkretnego powodu")
        }

        $hasSha = $sha -match '^[A-Fa-f0-9]{64}$'
        if ($requiresFull) {
            if (-not $hasSha) { $errors.Add("${id}: rola $sourceRole wymaga SHA-256 kanonicznego pliku źródła") }
        }
        if ($hasSha) {
            if ($isSubtree) {
                $errors.Add("${id}: wiersz z wzorcem 'katalog/**' nie może deklarować pojedynczego SHA-256")
            } elseif ($null -eq $canonicalFile) {
                if (-not $hasUrl) { $errors.Add("${id}: zadeklarowano SHA-256, ale wpis nie wskazuje istniejącego pliku w sources/") }
                else { $errors.Add("${id}: zadeklarowano SHA-256 bez lokalnego pliku; zapisz lokalny snapshot źródła") }
            } else {
                $actualHash = (Get-FileHash -LiteralPath $canonicalFile.File.FullName -Algorithm SHA256).Hash
                if ($actualHash -ne $sha.ToUpperInvariant()) {
                    $errors.Add("${id}: SHA-256 nie zgadza się z plikiem '$($canonicalFile.Relative)'; źródło zmieniono po kontroli — zaktualizuj rekord i ponów kontrolę tego źródła")
                } else {
                    $hashVerified++
                }
            }
        } elseif (-not $requiresFull -and -not $hasUrl -and -not $isSubtree -and $null -ne $canonicalFile -and -not (& $isDash $sha) -and (& $isPlaceholder $sha)) {
            $warnings.Add("${id}: lokalny plik bez SHA-256; hash pozwala unieważniać per źródło")
        }

        if (-not $hasUrl -and -not $isSubtree -and $null -eq $canonicalFile) {
            $errors.Add("${id}: wpis nie wskazuje istniejącego pliku w sources/ ani URL")
        }

        $sourceRows.Add([pscustomobject]@{
            Id = $id; FileRef = $fileRef; Role = $sourceRole; CheckedRange = $checkedRange
            Sha = $sha; Notes = $notes
            CanonicalFile = if ($canonicalFile) { $canonicalFile.Relative } else { $null }
            CanonicalFullPath = if ($canonicalFile) { $canonicalFile.File.FullName } else { $null }
            MatchedFiles = $matchedFiles
            SubtreePrefixes = $subtreePrefixes
        })
    }

    foreach ($duplicate in $sourceIds | Group-Object | Where-Object Count -gt 1) {
        $errors.Add("Powtórzone ID źródła: $($duplicate.Name)")
    }
    if ($sourceIds.Count -eq 0) { $errors.Add('Rejestr nie zawiera żadnego ID #S-...') }
    $sourceNumbers = @($sourceIds | ForEach-Object { [int]($_ -replace '^S-','') } | Sort-Object)
    for ($i = 0; $i -lt $sourceNumbers.Count; $i++) {
        if ($sourceNumbers[$i] -ne ($i + 1)) { $errors.Add("ID źródeł nie są ciągłe od S-001; oczekiwano S-$('{0:D3}' -f ($i+1)), znaleziono S-$('{0:D3}' -f $sourceNumbers[$i])."); break }
    }

    # Kanoniczny transcript PDF jest jednym źródłem logicznym z dokładnie wskazanym backing PDF.
    # Sama zgodność hasha nie wystarcza: ścieżka z frontmatter musi odpowiadać zarejestrowanemu plikowi.
    foreach ($row in $sourceRows) {
        if (-not $row.CanonicalFullPath -or [IO.Path]::GetExtension($row.CanonicalFullPath).ToLowerInvariant() -ne '.md') { continue }
        $sourceRaw = [IO.File]::ReadAllText($row.CanonicalFullPath, [Text.UTF8Encoding]::new($false))
        if ($sourceRaw -notmatch '(?m)^PDF_TEXT_SCHEMA:\s*K1_LITE_PDF_TEXT_V1\s*$') { continue }
        $pathMatch = [regex]::Match($sourceRaw, '(?m)^ORIGINAL_PDF:\s*"?(?<path>[^"\r\n]+?)"?\s*$')
        $shaMatch = [regex]::Match($sourceRaw, '(?m)^ORIGINAL_PDF_SHA256:\s*(?<sha>[A-Fa-f0-9]{64})\s*$')
        if (-not $pathMatch.Success -or -not $shaMatch.Success) {
            $errors.Add("$($row.Id): transcript PDF nie ma poprawnych ORIGINAL_PDF i ORIGINAL_PDF_SHA256")
            continue
        }
        $declaredRelative = $pathMatch.Groups['path'].Value.Trim().Replace('/','\')
        if ([IO.Path]::IsPathRooted($declaredRelative)) {
            $errors.Add("$($row.Id): ORIGINAL_PDF musi być ścieżką względną wewnątrz projektu")
            continue
        }
        $declaredFull = [IO.Path]::GetFullPath((Join-Path $project $declaredRelative))
        if (-not $declaredFull.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $declaredFull -PathType Leaf)) {
            $errors.Add("$($row.Id): ORIGINAL_PDF nie wskazuje istniejącego pliku wewnątrz projektu: '$($pathMatch.Groups['path'].Value)'")
            continue
        }
        $actualPdfHash = (Get-FileHash -LiteralPath $declaredFull -Algorithm SHA256).Hash
        if ($actualPdfHash -ne $shaMatch.Groups['sha'].Value.ToUpperInvariant()) {
            $errors.Add("$($row.Id): ORIGINAL_PDF_SHA256 nie zgadza się z backing PDF '$($pathMatch.Groups['path'].Value)'")
        }
        $backingRows = @($sourceRows | Where-Object {
            $_.CanonicalFullPath -and $_.CanonicalFullPath.Equals($declaredFull, [StringComparison]::OrdinalIgnoreCase) -and
            $_.Role -eq 'TECHNICZNE' -and $_.Sha.ToUpperInvariant() -eq $actualPdfHash
        })
        if ($backingRows.Count -ne 1) {
            $errors.Add("$($row.Id): backing PDF musi mieć dokładnie jeden wiersz TECHNICZNE z aktualnym SHA-256")
        }
        $strictPdfTranscriptValidator = Join-Path $PSScriptRoot 'k1-lite\Test-K1LiteEvidence.ps1'
        if (-not (Test-Path -LiteralPath $strictPdfTranscriptValidator -PathType Leaf)) {
            $errors.Add("$($row.Id): brak walidatora pełnej struktury transcriptu PDF")
        } elseif ($row.Sha -notmatch '^[A-Fa-f0-9]{64}$') {
            $errors.Add("$($row.Id): transcript PDF nie ma przypiętego SHA-256 źródła")
        } else {
            $strictTranscriptState = & $strictPdfTranscriptValidator -SourcePath $row.CanonicalFullPath `
                -ExpectedSourceSha256 $row.Sha -ExpectedPdfPath $declaredFull -ExpectedPdfSha256 $actualPdfHash `
                -ValidateOnly -NoExit
            if ([string]$strictTranscriptState.Verdict -cne 'PASS') {
                $errors.Add("$($row.Id): PDF_TRANSCRIPT_STRUCTURE_INVALID: $($strictTranscriptState.Code) — $($strictTranscriptState.Detail)")
            }
        }
    }

    # Rozliczenie plików: wprost, wzorcem katalog/** albo przynależnością do _oryginaly/.
    foreach ($entry in $sourceFiles) {
        $accounted = $false
        foreach ($row in $sourceRows) {
            if ($row.MatchedFiles -contains $entry.Relative) { $accounted = $true; break }
            foreach ($prefix in $row.SubtreePrefixes) {
                if ($entry.Relative -like "$prefix/*") { $accounted = $true; break }
            }
            if ($accounted) { break }
        }
        if (-not $accounted) {
            $errors.Add("Nierozliczony plik sources/: $($entry.File.FullName). Rozlicz go w rejestrze, wierszem 'katalog/**' (TECHNICZNE) albo przenieś do sources/$backupDirName/.")
        }
    }

    # ===== Karty =====
    $cardPattern = '(?ms)^###\s+(#P-\d{3,})\s*\r?\n(.*?)(?=^###\s+#P-\d{3,}\s*$|^##\s+|\z)'
    $cardMatches = [regex]::Matches($content, $cardPattern)
    $cardIds = [System.Collections.Generic.List[string]]::new()
    $coreCount = 0
    $autoCheckedCards = 0
    $manualCards = 0
    $pendingQaCards = 0
    $allowedWeights = @('RDZEŃ','WSPARCIE','REZERWA')
    $allowedStatuses = @('Fakt','Relacja','Stanowisko','Zarzut','Hipoteza','Legenda','Model','Rekonstrukcja','Spekulacja','Sprzeczność')
    $allowedForms = @('CYTAT','PARAFRAZA','DANE','OBRAZ-DOKUMENT')
    $allowedUseTags = @('HOOK','SCENA','BOHATER','MECHANIZM','KONTEKST','SKALA','SPRZECZNOŚĆ','ZWROT','WYPŁATA','FINAŁ')
    # V3: karta minimalna. Wszystko, co nie bierze udziału w blokowaniu zmyślonych
    # konkretów, zostało usunięte. Autor, data i klasa źródła żyją w rejestrze #S.
    $requiredCardFields = if ($isMinimal) {
        @('TREŚĆ','ŹRÓDŁO_ID','LOKALIZACJA','QA_K1')
    } else {
        @('WAGA','STATUS_W_ŹRÓDLE','TREŚĆ','ŹRÓDŁO_ID','LOKALIZACJA','FORMA','ATRYBUCJA','UŻYCIE_K2','QA_K1')
    }
    $retiredCardFields = @('WAGA','STATUS_W_ŹRÓDLE','FORMA','ATRYBUCJA','UŻYCIE_K2','CYTAT_DOSŁOWNY','OGRANICZENIE','FLAGI_K4','SPRZECZNE_Z')
    $sourceRowById = @{}
    foreach ($row in $sourceRows) { $sourceRowById[$row.Id] = $row }
    $sourceLinesCache = @{}

    foreach ($card in $cardMatches) {
        $cardId = $card.Groups[1].Value
        $block = $card.Groups[2].Value
        $cardIds.Add($cardId)

        if ($isMinimalV4) {
            foreach($cardLine in @($block -split "`r?`n")){
                if([string]::IsNullOrWhiteSpace($cardLine)){continue}
                if($cardLine -cnotmatch '^(?:TREŚĆ|ŹRÓDŁO_ID|LOKALIZACJA|QA_K1):[ \t]*.*$'){
                    $errors.Add("${cardId}: V4_CARD_RESIDUE_OR_UNKNOWN_LINE: $($cardLine.Trim())")
                }
            }
            $declaredCardFields = @([regex]::Matches($block, '(?m)^(?<name>[\p{Lu}\d_ĄĆĘŁŃÓŚŹŻ]+):[ \t]*(?<value>.*)$') | ForEach-Object { $_.Groups['name'].Value })
            foreach ($unknownCardField in @($declaredCardFields | Where-Object { $_ -notin $requiredCardFields } | Select-Object -Unique)) {
                $errors.Add("${cardId}: V4_CARD_UNKNOWN_FIELD: $unknownCardField")
            }
            foreach ($closedCardField in $requiredCardFields) {
                $closedFieldCount = @($declaredCardFields | Where-Object { $_ -ceq $closedCardField }).Count
                if ($closedFieldCount -ne 1) {
                    $errors.Add("${cardId}: V4_CARD_FIELD_COUNT_INVALID: $closedCardField count=$closedFieldCount expected=1")
                }
            }
        }

        $values = @{}
        foreach ($field in $requiredCardFields) {
            $values[$field] = Get-FieldValue -Text $block -Name $field
            if ([string]::IsNullOrWhiteSpace($values[$field])) {
                $errors.Add("${cardId}: brak pola lub wartości $field")
            }
        }
        # V3: TREŚĆ jest dosłownym fragmentem, więc sama pełni rolę cytatu do kontroli.
        # V2: cytat mieszka w osobnym polu, bo TREŚĆ mogła być parafrazą.
        $quote = if ($isMinimal) { $values['TREŚĆ'] } else { Get-FieldValue -Text $block -Name 'CYTAT_DOSŁOWNY' }

        if ($isMinimalV3) {
            foreach ($retired in $retiredCardFields) {
                if ($null -ne (Get-FieldValue -Text $block -Name $retired)) {
                    $warnings.Add("${cardId}: pole '$retired' nie należy do $schema; karta ma pozostać minimalna.")
                }
            }
        } else {
            if ($values['WAGA'] -and $values['WAGA'] -notin $allowedWeights) { $errors.Add("${cardId}: niedozwolona WAGA '$($values['WAGA'])'") }
            if ($values['WAGA'] -eq 'RDZEŃ') { $coreCount++ }
            if ($values['STATUS_W_ŹRÓDLE'] -and $values['STATUS_W_ŹRÓDLE'] -notin $allowedStatuses) { $errors.Add("${cardId}: niedozwolony STATUS_W_ŹRÓDLE '$($values['STATUS_W_ŹRÓDLE'])'") }
            if ($values['FORMA'] -and $values['FORMA'] -notin $allowedForms) { $errors.Add("${cardId}: niedozwolona FORMA '$($values['FORMA'])'") }
            if ($values['FORMA'] -eq 'CYTAT' -and [string]::IsNullOrWhiteSpace($quote)) {
                $errors.Add("${cardId}: FORMA CYTAT wymaga pola CYTAT_DOSŁOWNY do mechanicznej kontroli wierności")
            }
            if ($values['UŻYCIE_K2']) {
                $useTags = @($values['UŻYCIE_K2'] -split '\s*[,;/+]\s*' | Where-Object { $_ })
                foreach ($tag in $useTags) {
                    if ($tag -notin $allowedUseTags) { $errors.Add("${cardId}: niedozwolony tag UŻYCIE_K2 '$tag'") }
                }
            }
        }
        if ($values['QA_K1']) {
            if ($PendingReview) {
                if ($values['QA_K1'] -notin @('DO_SPRAWDZENIA','GOTOWA')) {
                    $errors.Add("${cardId}: w K1-COMPILED QA_K1 musi mieć DO_SPRAWDZENIA albo GOTOWA, jest '$($values['QA_K1'])'")
                } elseif ($values['QA_K1'] -eq 'DO_SPRAWDZENIA') {
                    $pendingQaCards++
                }
            } elseif ($values['QA_K1'] -ne 'GOTOWA') {
                $errors.Add("${cardId}: QA_K1 musi mieć GOTOWA przed K2, jest '$($values['QA_K1'])'")
            }
        }

        $sourceRef = if ($values['ŹRÓDŁO_ID']) { $values['ŹRÓDŁO_ID'].TrimStart('#') } else { '' }
        if ($sourceRef -and $sourceRef -notin $sourceIds) {
            $errors.Add("${cardId}: nieznane ŹRÓDŁO_ID '$($values['ŹRÓDŁO_ID'])'")
        }
        $isMachineTimestampLocator = $isMinimalV4 -and $values['LOKALIZACJA'] -match '^\[(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3}\s*-\s*(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3}\]$'
        if ($values['LOKALIZACJA'] -match '^(BRAK|NIE DOTYCZY|DO UZUPEŁNIENIA|NIEUSTALONE)$' -or
            ($values['LOKALIZACJA'] -match '^\[.*\]$' -and -not $isMachineTimestampLocator)) {
            $errors.Add("${cardId}: lokalizacja jest pozorna: '$($values['LOKALIZACJA'])'")
        }
        if ($values['TREŚĆ'] -and $values['TREŚĆ'].Length -lt 15) {
            $warnings.Add("${cardId}: TREŚĆ jest bardzo krótka; sprawdź, czy karta jest konkretna.")
        }

        # ===== Mechaniczna kontrola lokalizacji i cytatu (auto-fidelity) =====
        $row = if ($sourceRef -and $sourceRowById.ContainsKey($sourceRef)) { $sourceRowById[$sourceRef] } else { $null }
        if ($row -and $row.Role -notin @('RDZEŃ','CELOWE')) {
            $errors.Add("${cardId}: karta wskazuje źródło o roli '$($row.Role)'; dowody mogą pochodzić wyłącznie ze źródeł RDZEŃ albo CELOWE")
        }
        $textPath = $null
        if ($row -and $row.CanonicalFullPath -and ([IO.Path]::GetExtension($row.CanonicalFullPath).ToLowerInvariant() -in $canonicalExtensions)) {
            $textPath = $row.CanonicalFullPath
        }
        $autoChecked = $false
        $quoteVerified = $false
        if ($textPath) {
            if (-not $sourceLinesCache.ContainsKey($textPath)) { $sourceLinesCache[$textPath] = [IO.File]::ReadAllLines($textPath) }
            $sourceLines = $sourceLinesCache[$textPath]
            $rangeStart = 0; $rangeEnd = $sourceLines.Count - 1; $hasRange = $false

            $locator = if ($values['LOKALIZACJA']) { $values['LOKALIZACJA'] } else { '' }
            if ($isMinimalV4) {
                $extension = [IO.Path]::GetExtension($textPath).ToLowerInvariant()
                $sourceRaw = [IO.File]::ReadAllText($textPath, [Text.UTF8Encoding]::new($false)).Replace("`r`n","`n").Replace("`r","`n")
                $isPageTranscript = $sourceRaw -match '(?m)^PDF_TEXT_SCHEMA:\s*K1_LITE_PDF_TEXT_V1\s*$' -or $sourceRaw -match '(?m)^<!-- PDF_PAGE_BEGIN: P\d{4};'
                if ($isPageTranscript) {
                    $pageMatch = [regex]::Match($locator, '^(P\d{4})/L(\d+)(?:[-–]L?(\d+))?$')
                    if (-not $pageMatch.Success) {
                        $errors.Add("${cardId}: transcript PDF wymaga lokalizacji Pxxxx/Lx-Ly, jest '$locator'")
                    } else {
                        $pageId = $pageMatch.Groups[1].Value
                        $pageNumber = $pageId.Substring(1)
                        $pageBlock = [regex]::Match($sourceRaw, "(?ms)^<!-- PDF_PAGE_BEGIN: P$pageNumber;[^\n]*-->\n(?<body>.*?)^<!-- PDF_PAGE_END: P$pageNumber -->$")
                        if (-not $pageBlock.Success) {
                            $errors.Add("${cardId}: brak strony $pageId w '$($row.CanonicalFile)'")
                        } else {
                            $pageLines = @($pageBlock.Groups['body'].Value -split "`n")
                            $from = [int]$pageMatch.Groups[2].Value
                            $to = if ($pageMatch.Groups[3].Success) { [int]$pageMatch.Groups[3].Value } else { $from }
                            if ($from -lt 1 -or $to -lt $from -or $to -gt $pageLines.Count) {
                                $errors.Add("${cardId}: lokalizacja '$locator' wychodzi poza $pageId ($($pageLines.Count) linii)")
                            } else {
                                $rangeStart = $from - 1; $rangeEnd = $to - 1; $hasRange = $true; $autoChecked = $true
                                $sourceLines = $pageLines
                            }
                        }
                    }
                } elseif ($extension -in @('.srt','.vtt')) {
                    if ($effectiveLocatorPolicy -ne 'MIXED_V1') {
                        $errors.Add("${cardId}: lokalizacja timestamp wymaga LOCATOR_POLICY: MIXED_V1")
                    }
                    $timeMatch = [regex]::Match($locator, '^\[(?<start>(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3})\s*-\s*(?<end>(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3})\]$')
                    if (-not $timeMatch.Success) {
                        $errors.Add("${cardId}: napisy wymagają lokalizacji [HH:MM:SS.mmm-HH:MM:SS.mmm], jest '$locator'")
                    } else {
                        try {
                            $declaredStart = ConvertTo-CanonicalSubtitleTimestamp $timeMatch.Groups['start'].Value
                            $declaredEnd = ConvertTo-CanonicalSubtitleTimestamp $timeMatch.Groups['end'].Value
                            $cues = @(Get-SubtitleCues $textPath)
                            $matchingScopes = [System.Collections.Generic.List[object]]::new()
                            for ($cueStart = 0; $cueStart -lt $cues.Count; $cueStart++) {
                                if ($cues[$cueStart].Start -ne $declaredStart.Text) { continue }
                                for ($cueEnd = $cueStart; $cueEnd -lt $cues.Count; $cueEnd++) {
                                    if ($cues[$cueEnd].End -eq $declaredEnd.Text) { $matchingScopes.Add([pscustomobject]@{ From=$cueStart; To=$cueEnd }) }
                                    if ($cues[$cueEnd].EndMs -gt $declaredEnd.Milliseconds) { break }
                                }
                            }
                            if ($matchingScopes.Count -ne 1) {
                                $errors.Add("${cardId}: timestamp '$locator' nie wskazuje dokładnie jednego ciągłego zakresu cue w '$($row.CanonicalFile)'")
                            } else {
                                $selectedCueLines = [System.Collections.Generic.List[string]]::new()
                                $scope = $matchingScopes[0]
                                for ($cueIndex = $scope.From; $cueIndex -le $scope.To; $cueIndex++) {
                                    foreach ($cueLine in $cues[$cueIndex].Lines) { $selectedCueLines.Add([string]$cueLine) }
                                }
                                $sourceLines = @($selectedCueLines)
                                $rangeStart = 0; $rangeEnd = $sourceLines.Count - 1; $hasRange = $true; $autoChecked = $true
                            }
                        } catch {
                            $errors.Add("${cardId}: nie można zweryfikować napisów '$($row.CanonicalFile)': $($_.Exception.Message)")
                        }
                    }
                } else {
                    if ($effectiveLocatorPolicy -ne 'MIXED_V1') {
                        $errors.Add("${cardId}: globalna lokalizacja linii wymaga LOCATOR_POLICY: MIXED_V1")
                    }
                    $lineMatch = [regex]::Match($locator, '^L(\d+)(?:[-–]L?(\d+))?$')
                    if (-not $lineMatch.Success) {
                        $errors.Add("${cardId}: samodzielny MD/TXT wymaga lokalizacji Lx-Ly, jest '$locator'")
                    } else {
                        $from = [int]$lineMatch.Groups[1].Value
                        $to = if ($lineMatch.Groups[2].Success) { [int]$lineMatch.Groups[2].Value } else { $from }
                        if ($from -lt 1 -or $to -lt $from -or $to -gt $sourceLines.Count) {
                            $errors.Add("${cardId}: lokalizacja '$locator' wychodzi poza plik '$($row.CanonicalFile)' ($($sourceLines.Count) linii)")
                        } else {
                            $rangeStart = $from - 1; $rangeEnd = $to - 1; $hasRange = $true; $autoChecked = $true
                        }
                    }
                }
            }
            $rangeMatch = if ($isMinimalV4) { [regex]::Match('', 'a^') } else { [regex]::Match($locator, '(?i)(?:\bL(\d+)\s*(?:[-–]\s*L?(\d+))?)|(?:\blini[ae]\s+(\d+)\s*(?:[-–]\s*(\d+))?)') }
            if ($rangeMatch.Success) {
                $hasRange = $true
                $from = if ($rangeMatch.Groups[1].Success) { [int]$rangeMatch.Groups[1].Value } else { [int]$rangeMatch.Groups[3].Value }
                $to = if ($rangeMatch.Groups[2].Success) { [int]$rangeMatch.Groups[2].Value }
                      elseif ($rangeMatch.Groups[4].Success) { [int]$rangeMatch.Groups[4].Value }
                      else { $from }
                if ($from -lt 1 -or $to -lt $from -or $to -gt $sourceLines.Count) {
                    $errors.Add("${cardId}: lokalizacja '$locator' wychodzi poza plik '$($row.CanonicalFile)' ($($sourceLines.Count) linii)")
                } else {
                    $rangeStart = $from - 1; $rangeEnd = $to - 1; $autoChecked = $true
                }
            }
            foreach ($tsMatch in $(if ($isMinimalV4) { @() } else { [regex]::Matches($locator, '\[(\d{1,2}:\d{2}(?::\d{2})?)\]') })) {
                $stamp = $tsMatch.Groups[1].Value
                $stampFound = $false
                foreach ($line in $sourceLines) { if ($line.Contains($stamp)) { $stampFound = $true; break } }
                if (-not $stampFound) { $errors.Add("${cardId}: timestamp [$stamp] z lokalizacji nie występuje w pliku '$($row.CanonicalFile)'") }
                else { $autoChecked = $true }
            }
            $quoteField = if ($isMinimal) { 'TREŚĆ' } else { 'CYTAT_DOSŁOWNY' }
            if (-not [string]::IsNullOrWhiteSpace($quote)) {
                $scopeLines = if ($hasRange -and $rangeEnd -ge $rangeStart) {
                    $padStart = if ($isMinimalV4) { $rangeStart } else { [Math]::Max(0, $rangeStart - 2) }
                    $padEnd = if ($isMinimalV4) { $rangeEnd } else { [Math]::Min($sourceLines.Count - 1, $rangeEnd + 2) }
                    $sourceLines[$padStart..$padEnd]
                } else { $sourceLines }
                $scopeText = if ($isMinimalV4) {
                    Get-ExactComparableText -Text ($scopeLines -join ' ')
                } else {
                    Get-NormalizedText -Text ($scopeLines -join ' ')
                }
                $parts = if ($isMinimalV4) {
                    @((Get-ExactComparableText -Text $quote))
                } else {
                    @([regex]::Split($quote, '\[(?:\.\.\.|…)\]|\.\.\.|…') | ForEach-Object { Get-NormalizedText -Text $_ } | Where-Object { $_.Length -ge 6 })
                }
                $parts = @($parts | Where-Object { $_.Length -ge 6 })
                if ($parts.Count -eq 0) {
                    $warnings.Add("${cardId}: ${quoteField} jest za krótkie do mechanicznej kontroli")
                } else {
                    $searchFrom = 0
                    $quoteOk = $true
                    foreach ($part in $parts) {
                        $foundAt = $scopeText.IndexOf($part, $searchFrom)
                        if ($foundAt -lt 0) { $quoteOk = $false; break }
                        $searchFrom = $foundAt + $part.Length
                    }
                    if (-not $quoteOk) {
                        $errors.Add("${cardId}: ${quoteField} nie występuje we wskazanym miejscu źródła '$($row.CanonicalFile)'")
                        if ($isMinimal) { $autoChecked = $false }
                    } else {
                        $autoChecked = $true
                        $quoteVerified = $true
                    }
                }
            }
        }
        # V3 nie zna kart „do ręcznego sprawdzenia”: jeżeli źródło jest kanonicznym
        # plikiem tekstowym, dosłowna TREŚĆ musi zostać odnaleziona na miejscu.
        # Inaczej cała gwarancja „konkret pochodzi ze źródła Dawida” jest deklaracją.
        if ($isMinimal) {
            $autoChecked = $quoteVerified
            if (-not $quoteVerified) {
                if ($textPath) {
                    if (-not [string]::IsNullOrWhiteSpace($values['TREŚĆ'])) {
                        $errors.Add("${cardId}: TREŚĆ nie została potwierdzona maszynowo w '$($row.CanonicalFile)'; $schema wymaga dosłownego fragmentu z podanej lokalizacji")
                    }
                } elseif ($row) {
                    $warnings.Add("${cardId}: źródło '$($row.FileRef)' nie jest kanonicznym plikiem tekstowym, więc karty nie da się sprawdzić maszynowo; SOURCE_FIDELITY_CHECK nie może mieć PASS")
                }
            }
        }
        if ($autoChecked) { $autoCheckedCards++ } else { $manualCards++ }
    }

    foreach ($duplicate in $cardIds | Group-Object | Where-Object Count -gt 1) {
        $errors.Add("Powtórzone ID karty: $($duplicate.Name)")
    }
    $cardNumbers = @($cardIds | ForEach-Object { [int]($_ -replace '^#P-','') } | Sort-Object)
    for ($i = 0; $i -lt $cardNumbers.Count; $i++) {
        if ($cardNumbers[$i] -ne ($i + 1)) { $errors.Add("ID kart nie są ciągłe od #P-001; oczekiwano #P-$('{0:D3}' -f ($i+1)), znaleziono #P-$('{0:D3}' -f $cardNumbers[$i])."); break }
    }
    if ($cardIds.Count -eq 0) { $errors.Add('Baza nie zawiera żadnej karty #P-...') }
    if (-not $isMinimal -and $coreCount -eq 0) { $errors.Add('Baza nie zawiera żadnej karty WAGA: RDZEŃ.') }

    # ===== Pokrycie celów K0 =====
    $goalMatches = [regex]::Matches($content, '(?m)^\|\s*(Q-\d{3,})\s*\|\s*(POKRYTY|LUKA JAWNA|POZA ZAKRESEM)\s*\|\s*([^|]*)\|')
    if ($goalMatches.Count -eq 0) { $errors.Add('Tabela pokrycia nie zawiera żadnego zamkniętego celu Q-...') }
    $coveredGoalIds = @($goalMatches | ForEach-Object { $_.Groups[1].Value })
    foreach ($duplicate in $coveredGoalIds | Group-Object | Where-Object Count -gt 1) {
        $errors.Add("Powtórzony cel w tabeli pokrycia: $($duplicate.Name)")
    }
    foreach ($goal in $goalMatches) {
        if ($goal.Groups[2].Value -eq 'POKRYTY') {
            $refs = @([regex]::Matches($goal.Groups[3].Value, '#P-\d{3,}') | ForEach-Object Value | Select-Object -Unique)
            if ($refs.Count -eq 0) { $errors.Add("$($goal.Groups[1].Value): status POKRYTY nie wskazuje żadnej karty #P") }
            foreach ($ref in $refs) {
                if ($ref -notin $cardIds) { $errors.Add("$($goal.Groups[1].Value): odwołanie do nieistniejącej karty $ref") }
            }
        }
    }

    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
        $errors.Add('Brak 00-fundament-projektu.md potrzebnego do kontroli celów K0.')
    } else {
        $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8
        $contractGoalIds = @([regex]::Matches($contract, '(?m)^\|\s*(Q-\d{3,})\s*\|') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        if ($contractGoalIds.Count -eq 0) { $errors.Add('Kontrakt K0 nie zawiera żadnego celu Q-...') }
        foreach ($id in $contractGoalIds) {
            if ($id -notin $coveredGoalIds) { $errors.Add("Cel K0 nie jest rozliczony w K1: $id") }
        }
        foreach ($id in $coveredGoalIds) {
            if ($id -notin $contractGoalIds) { $errors.Add("K1 rozlicza cel nieobecny w kontrakcie K0: $id") }
        }
    }

    $unaccounted = Get-FieldValue -Text $content -Name 'NIEROZLICZONE_ŹRÓDŁA'
    if ($unaccounted -ne '0') { $errors.Add("NIEROZLICZONE_ŹRÓDŁA musi wynosić 0, jest '$unaccounted'.") }

    $structureDeclared = Get-FieldValue -Text $content -Name 'STRUCTURE_CHECK'
    $fidelity = Get-FieldValue -Text $content -Name 'SOURCE_FIDELITY_CHECK'
    $saturation = Get-FieldValue -Text $content -Name 'SATURATION_CHECK'
    $k1Verdict = Get-FieldValue -Text $content -Name 'K1_VERDICT'
    $leadAgent = Get-FieldValue -Text $content -Name 'LEAD_AGENT_ID'
    $verifyAgent = Get-FieldValue -Text $content -Name 'VERIFY_AGENT_ID'
    $researchRounds = Get-FieldValue -Text $content -Name 'RESEARCH_ROUNDS'
    $stopReason = Get-FieldValue -Text $content -Name 'STOP_REASON'
    if ($isK1LiteV2Workflow -and -not $PendingReview) {
        foreach ($reviewField in @('CORPUS_COVERAGE_REVIEWED','K0_COVERAGE_REVIEWED','SOURCE_CLASSES_REVIEWED')) {
            $reviewValue = Get-FieldValue -Text $content -Name $reviewField
            if ($reviewValue -ne 'TAK') { $errors.Add("$reviewField musi mieć TAK przed K2, jest '$reviewValue'.") }
        }
        $origin = Get-FieldValue -Text $content -Name 'K1_ORIGIN'
        if ($k1ResearchMode -eq 'K1_LITE_V2') {
            if ($origin -ne 'K1_LITE_V2') { $errors.Add("K1_ORIGIN musi mieć K1_LITE_V2 w trybie K1_LITE_V2, jest '$origin'.") }
            $originVersion = Get-FieldValue -Text $content -Name 'K1_ORIGIN_VERSION'
            try {
                if ($originVersion -notmatch '^\d+\.\d+\.\d+$' -or [version]$originVersion -ne [version]'2.1.0') {
                    $errors.Add("K1_ORIGIN_VERSION musi mieć dokładnie 2.1.0 w bieżącej rewizji, jest '$originVersion'.")
                }
            } catch {
                $errors.Add("K1_ORIGIN_VERSION nie jest poprawną wersją: '$originVersion'.")
            }
            $originExport = Get-FieldValue -Text $content -Name 'K1_EXPORT_PATH'
            $originHash = Get-FieldValue -Text $content -Name 'K1_EXPORT_SHA256'
            if ([string]::IsNullOrWhiteSpace($originExport) -or $originExport -eq 'BRAK') { $errors.Add('Brak K1_EXPORT_PATH w kanonicznej bazie.') }
            if ($originHash -notmatch '^[A-Fa-f0-9]{64}$') { $errors.Add('Brak poprawnego K1_EXPORT_SHA256 w kanonicznej bazie.') }
        } elseif ($k1ResearchMode -eq 'MANUAL_APPROVED' -and $origin -ne 'MANUAL_APPROVED') {
            $errors.Add("K1_ORIGIN musi mieć MANUAL_APPROVED w zatwierdzonym trybie awaryjnym, jest '$origin'.")
        }
    }
    if ($fidelity -eq 'PASS') {
        if ($isMinimal) {
            # V3 nie ma parafraz, więc nie ma czego oceniać semantycznie. Kontrolerem
            # jest walidator, a jedynym dopuszczalnym dowodem PASS jest to, że każda
            # karta została odnaleziona w źródle. Zero kart „na słowo”.
            if ($manualCards -gt 0) {
                $errors.Add("SOURCE_FIDELITY_CHECK ma PASS, ale $manualCards kart nie zostało potwierdzonych maszynowo. W MINIMAL_EVIDENCE_V3 kontrolę wierności wykonuje walidator, nie osobny kontekst.")
            }
            if ([string]::IsNullOrWhiteSpace($leadAgent)) { $errors.Add('SOURCE_FIDELITY_CHECK ma PASS, ale brak LEAD_AGENT_ID.') }
        } else {
            if ([string]::IsNullOrWhiteSpace($leadAgent)) { $errors.Add('SOURCE_FIDELITY_CHECK ma PASS, ale brak LEAD_AGENT_ID.') }
            if ([string]::IsNullOrWhiteSpace($verifyAgent)) { $errors.Add('SOURCE_FIDELITY_CHECK ma PASS, ale brak VERIFY_AGENT_ID.') }
            if ($leadAgent -and $verifyAgent -and $leadAgent -eq $verifyAgent) { $errors.Add('LEAD_AGENT_ID i VERIFY_AGENT_ID muszą wskazywać różne konteksty.') }
        }
    }
    if ($saturation -eq 'PASS' -and ([string]::IsNullOrWhiteSpace($stopReason) -or $stopReason.Length -lt 15 -or $stopReason -match '^\[.*\]$|^NIEUSTALONE$|^DO UZUPEŁNIENIA\b')) {
        $errors.Add('SATURATION_CHECK ma PASS, ale brak konkretnego STOP_REASON.')
    }
    $researchRoundsNumber = 0
    if (-not [int]::TryParse($researchRounds, [ref]$researchRoundsNumber) -or $researchRoundsNumber -lt 1 -or $researchRoundsNumber -gt 2) {
        $errors.Add("RESEARCH_ROUNDS musi wynosić 1 albo 2, jest '$researchRounds'.")
    }
    $gateReady = -not $PendingReview -and $errors.Count -eq 0 -and $structureDeclared -eq 'PASS' -and $fidelity -eq 'PASS' -and $saturation -eq 'PASS' -and $k1Verdict -eq 'GOTOWE_DO_K2'
    $readyForImport = [bool]($PendingReview -and $errors.Count -eq 0 -and $manualCards -eq 0)

    if ($structureDeclared -ne 'PASS') { $warnings.Add("STRUCTURE_CHECK nie ma PASS: '$structureDeclared'") }
    if ($fidelity -ne 'PASS') { $warnings.Add("SOURCE_FIDELITY_CHECK nie ma PASS: '$fidelity'") }
    if ($saturation -ne 'PASS') { $warnings.Add("SATURATION_CHECK nie ma PASS: '$saturation'") }
    if ($k1Verdict -ne 'GOTOWE_DO_K2') { $warnings.Add("K1_VERDICT nie ma GOTOWE_DO_K2: '$k1Verdict'") }

    $result = [pscustomobject]@{
        ProjectPath = $project
        EvidencePath = $basePath
        PendingReview = [bool]$PendingReview
        Schema = $schema
        Sources = $sourceIds.Count
        SourceFiles = $sourceFiles.Count
        BackupFiles = $backupFileCount
        HashVerifiedSources = $hashVerified
        Cards = $cardIds.Count
        CoreCards = $coreCount
        AutoCheckedCards = $autoCheckedCards
        ManualCheckCards = $manualCards
        PendingQaCards = $pendingQaCards
        Errors = $errors.Count
        Warnings = $warnings.Count
        ErrorDetails = $errors
        WarningDetails = $warnings
        StructureVerdict = if ($errors.Count -eq 0) { 'STRUCTURE_PASS' } else { 'STRUCTURE_FAIL' }
        GateReady = $gateReady
        ReadyForImport = $readyForImport
    }

    $result
    if ($errors.Count -gt 0 -and -not $NoExit) { exit 1 }
    return
}

if ($schema -ne 'COMPACT_EVIDENCE_V1') {
    $errors.Add("Nieobsługiwany K1_SCHEMA: $schema")
}

$sourceMatches = [regex]::Matches($content, '(?m)^\|\s*#?(S-\d{3,})\s*\|(.*?)\|\s*$')
$sourceIds = [System.Collections.Generic.List[string]]::new()
$sourceRows = [System.Collections.Generic.List[object]]::new()
$allowedSourceClasses = @('A','B','C','D')
$allowedSourceRoles = @('RDZEŃ','CELOWE','REZERWA','WYŁĄCZONE','TECHNICZNE')
foreach ($match in $sourceMatches) {
    $id = $match.Groups[1].Value
    $cells = @(("$id|$($match.Groups[2].Value)").Split('|') | ForEach-Object { $_.Trim() })
    $sourceIds.Add($id)
    if ($cells.Count -lt 10) {
        $errors.Add("${id}: wiersz rejestru źródeł ma mniej niż 10 kolumn")
        continue
    }
    $fileRef = $cells[1]
    $author = $cells[2]
    $date = $cells[3]
    $sourceClass = $cells[4]
    $sourceRole = $cells[5]
    $checkedRange = $cells[6]
    $locatorQuality = $cells[7]
    $notes = $cells[9]
    if ([string]::IsNullOrWhiteSpace($fileRef) -or $fileRef -match '^\[.*\]$|^DO UZUPEŁNIENIA$|^NIEUSTALONE$') {
        $errors.Add("${id}: brak konkretnego pliku lub URL w rejestrze")
    }
    if ($sourceClass -notin $allowedSourceClasses) {
        $errors.Add("${id}: klasa źródła musi mieć A, B, C albo D, jest '$sourceClass'")
    }
    if ($sourceRole -notin $allowedSourceRoles) {
        $errors.Add("${id}: niedozwolona rola źródła '$sourceRole'")
    }
    if ([string]::IsNullOrWhiteSpace($checkedRange) -or $checkedRange -match '^\[.*\]$|^DO UZUPEŁNIENIA$|^NIEUSTALONE$') {
        $errors.Add("${id}: brak konkretnego zakresu sprawdzonego")
    }
    if ([string]::IsNullOrWhiteSpace($author) -or $author -match '^\[.*\]$|^DO UZUPEŁNIENIA$') { $errors.Add("${id}: brak autora/instytucji albo jawnego NIEUSTALONE") }
    if ([string]::IsNullOrWhiteSpace($date) -or $date -match '^\[.*\]$|^DO UZUPEŁNIENIA$') { $errors.Add("${id}: brak daty albo jawnego NIEUSTALONE") }
    if ([string]::IsNullOrWhiteSpace($locatorQuality) -or $locatorQuality -match '^\[.*\]$|^DO UZUPEŁNIENIA$|^NIEUSTALONE$') { $errors.Add("${id}: brak oceny jakości lokalizatorów/OCR") }
    if ($sourceRole -eq 'WYŁĄCZONE' -and ([string]::IsNullOrWhiteSpace($notes) -or $notes -match '^BRAK$|^\[.*\]$|^DO UZUPEŁNIENIA$|^NIEUSTALONE$')) {
        $errors.Add("${id}: źródło WYŁĄCZONE nie ma konkretnego powodu")
    }
    $sourceRows.Add([pscustomobject]@{ Id = $id; FileRef = $fileRef; Class = $sourceClass; Role = $sourceRole; CheckedRange = $checkedRange; LocatorQuality = $locatorQuality; Notes = $notes })
}

foreach ($duplicate in $sourceIds | Group-Object | Where-Object Count -gt 1) {
    $errors.Add("Powtórzone ID źródła: $($duplicate.Name)")
}
if ($sourceIds.Count -eq 0) { $errors.Add('Rejestr nie zawiera żadnego ID #S-...') }

$sourceFiles = if (Test-Path -LiteralPath $sourceDir -PathType Container) {
    @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName)
} else {
    @()
    $errors.Add('Brak katalogu sources/.')
}
$sourceTreeParts = @($sourceFiles | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($sourceDir, $_.FullName).Replace('\','/')
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    "$relative`t$($_.Length)`t$hash"
})
$sourceTreeSha256 = Get-TextSha256 -Text ($sourceTreeParts -join "`n")
$verifiedSourceTreeSha256 = Get-FieldValue -Text $content -Name 'VERIFIED_SOURCE_TREE_SHA256'
if ($verifiedSourceTreeSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    $errors.Add('Brak poprawnego VERIFIED_SOURCE_TREE_SHA256 zapisanego po kontroli K1 VERIFY.')
} elseif ($verifiedSourceTreeSha256 -ne $sourceTreeSha256) {
    $errors.Add('VERIFIED_SOURCE_TREE_SHA256 nie odpowiada aktualnej zawartości sources/; odśwież inwentarz i ponów kontrolę K1 VERIFY.')
}
$duplicateSourceNames = @($sourceFiles | Group-Object Name | Where-Object Count -gt 1 | ForEach-Object Name)

foreach ($file in $sourceFiles) {
    $relative = [IO.Path]::GetRelativePath($sourceDir, $file.FullName).Replace('\','/')
    $namePattern = '(?i)(?<![\p{L}\p{N}_.-])' + [regex]::Escape($file.Name) + '(?![\p{L}\p{N}_.-])'
    $relativePattern = '(?i)(?<![\p{L}\p{N}_.-])' + [regex]::Escape($relative) + '(?![\p{L}\p{N}_.-])'
    $registered = @($sourceRows | Where-Object {
        $normalizedRef = $_.FileRef.Replace('\','/')
        [regex]::IsMatch($normalizedRef, $relativePattern) -or
        ($file.Name -notin $duplicateSourceNames -and [regex]::IsMatch($normalizedRef, $namePattern))
    }).Count -gt 0
    if (-not $registered) {
        $errors.Add("Nierozliczony plik sources/: $($file.FullName)")
    }
}

foreach ($row in $sourceRows) {
    $normalizedRef = $row.FileRef.Replace('\','/')
    $hasUrl = $normalizedRef -match '(?i)https?://'
    $hasExistingLocalFile = $false
    foreach ($file in $sourceFiles) {
        $relative = [IO.Path]::GetRelativePath($sourceDir, $file.FullName).Replace('\','/')
        $namePattern = '(?i)(?<![\p{L}\p{N}_.-])' + [regex]::Escape($file.Name) + '(?![\p{L}\p{N}_.-])'
        $relativePattern = '(?i)(?<![\p{L}\p{N}_.-])' + [regex]::Escape($relative) + '(?![\p{L}\p{N}_.-])'
        if ([regex]::IsMatch($normalizedRef, $relativePattern) -or ($file.Name -notin $duplicateSourceNames -and [regex]::IsMatch($normalizedRef, $namePattern))) {
            $hasExistingLocalFile = $true
            break
        }
    }
    if (-not $hasUrl -and -not $hasExistingLocalFile) { $errors.Add("$($row.Id): wpis nie wskazuje istniejącego pliku w sources/ ani URL") }
}

$cardPattern = '(?ms)^###\s+(#P-\d{3,})\s*\r?\n(.*?)(?=^###\s+#P-\d{3,}\s*$|^##\s+|\z)'
$cardMatches = [regex]::Matches($content, $cardPattern)
$cardIds = [System.Collections.Generic.List[string]]::new()
$coreCount = 0
$allowedWeights = @('RDZEŃ','WSPARCIE','REZERWA')
$allowedStatuses = @('Fakt','Relacja','Stanowisko','Zarzut','Hipoteza','Legenda','Model','Rekonstrukcja','Spekulacja','Sprzeczność')
$allowedForms = @('CYTAT','PARAFRAZA','DANE','OBRAZ-DOKUMENT')
$allowedUseTags = @('HOOK','SCENA','BOHATER','MECHANIZM','KONTEKST','SKALA','SPRZECZNOŚĆ','ZWROT','WYPŁATA','FINAŁ')
$requiredCardFields = @('WAGA','STATUS_W_ŹRÓDLE','TREŚĆ','ŹRÓDŁO_ID','LOKALIZACJA','FORMA','ATRYBUCJA','UŻYCIE_K2','QA_K1')

foreach ($card in $cardMatches) {
    $cardId = $card.Groups[1].Value
    $block = $card.Groups[2].Value
    $cardIds.Add($cardId)

    $values = @{}
    foreach ($field in $requiredCardFields) {
        $values[$field] = Get-FieldValue -Text $block -Name $field
        if ([string]::IsNullOrWhiteSpace($values[$field])) {
            $errors.Add("${cardId}: brak pola lub wartości $field")
        }
    }

    if ($values['WAGA'] -and $values['WAGA'] -notin $allowedWeights) {
        $errors.Add("${cardId}: niedozwolona WAGA '$($values['WAGA'])'")
    }
    if ($values['WAGA'] -eq 'RDZEŃ') { $coreCount++ }

    if ($values['STATUS_W_ŹRÓDLE'] -and $values['STATUS_W_ŹRÓDLE'] -notin $allowedStatuses) {
        $errors.Add("${cardId}: niedozwolony STATUS_W_ŹRÓDLE '$($values['STATUS_W_ŹRÓDLE'])'")
    }
    if ($values['FORMA'] -and $values['FORMA'] -notin $allowedForms) {
        $errors.Add("${cardId}: niedozwolona FORMA '$($values['FORMA'])'")
    }
    if ($values['UŻYCIE_K2']) {
        $useTags = @($values['UŻYCIE_K2'] -split '\s*[,;/+]\s*' | Where-Object { $_ })
        foreach ($tag in $useTags) {
            if ($tag -notin $allowedUseTags) { $errors.Add("${cardId}: niedozwolony tag UŻYCIE_K2 '$tag'") }
        }
    }
    if ($values['QA_K1'] -and $values['QA_K1'] -ne 'GOTOWA') {
        $errors.Add("${cardId}: QA_K1 musi mieć GOTOWA przed K2, jest '$($values['QA_K1'])'")
    }

    $sourceRef = if ($values['ŹRÓDŁO_ID']) { $values['ŹRÓDŁO_ID'].TrimStart('#') } else { '' }
    if ($sourceRef -and $sourceRef -notin $sourceIds) {
        $errors.Add("${cardId}: nieznane ŹRÓDŁO_ID '$($values['ŹRÓDŁO_ID'])'")
    }

    if ($values['LOKALIZACJA'] -match '^(BRAK|NIE DOTYCZY|DO UZUPEŁNIENIA|NIEUSTALONE|\[.*\])$') {
        $errors.Add("${cardId}: lokalizacja jest pozorna: '$($values['LOKALIZACJA'])'")
    }
    if ($values['TREŚĆ'] -and $values['TREŚĆ'].Length -lt 15) {
        $warnings.Add("${cardId}: TREŚĆ jest bardzo krótka; sprawdź, czy karta jest konkretna.")
    }
}

foreach ($duplicate in $cardIds | Group-Object | Where-Object Count -gt 1) {
    $errors.Add("Powtórzone ID karty: $($duplicate.Name)")
}
if ($cardIds.Count -eq 0) { $errors.Add('Baza nie zawiera żadnej karty #P-...') }
if ($coreCount -eq 0) { $errors.Add('Baza nie zawiera żadnej karty WAGA: RDZEŃ.') }

$goalMatches = [regex]::Matches($content, '(?m)^\|\s*(Q-\d{3,})\s*\|\s*(POKRYTY|LUKA JAWNA|POZA ZAKRESEM)\s*\|\s*([^|]*)\|')
if ($goalMatches.Count -eq 0) {
    $errors.Add('Tabela pokrycia nie zawiera żadnego zamkniętego celu Q-...')
}
$coveredGoalIds = @($goalMatches | ForEach-Object { $_.Groups[1].Value })
foreach ($duplicate in $coveredGoalIds | Group-Object | Where-Object Count -gt 1) {
    $errors.Add("Powtórzony cel w tabeli pokrycia: $($duplicate.Name)")
}
foreach ($goal in $goalMatches) {
    if ($goal.Groups[2].Value -eq 'POKRYTY') {
        $refs = @([regex]::Matches($goal.Groups[3].Value, '#P-\d{3,}') | ForEach-Object Value | Select-Object -Unique)
        if ($refs.Count -eq 0) { $errors.Add("$($goal.Groups[1].Value): status POKRYTY nie wskazuje żadnej karty #P") }
        foreach ($ref in $refs) {
            if ($ref -notin $cardIds) { $errors.Add("$($goal.Groups[1].Value): odwołanie do nieistniejącej karty $ref") }
        }
    }
}

if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    $errors.Add('Brak 00-fundament-projektu.md potrzebnego do kontroli celów K0.')
} else {
    $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8
    $contractGoalIds = @([regex]::Matches($contract, '(?m)^\|\s*(Q-\d{3,})\s*\|') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($contractGoalIds.Count -eq 0) { $errors.Add('Kontrakt K0 nie zawiera żadnego celu Q-...') }
    foreach ($id in $contractGoalIds) {
        if ($id -notin $coveredGoalIds) { $errors.Add("Cel K0 nie jest rozliczony w K1: $id") }
    }
    foreach ($id in $coveredGoalIds) {
        if ($id -notin $contractGoalIds) { $errors.Add("K1 rozlicza cel nieobecny w kontrakcie K0: $id") }
    }
}

$unaccounted = Get-FieldValue -Text $content -Name 'NIEROZLICZONE_ŹRÓDŁA'
if ($unaccounted -ne '0') { $errors.Add("NIEROZLICZONE_ŹRÓDŁA musi wynosić 0, jest '$unaccounted'.") }

$structureDeclared = Get-FieldValue -Text $content -Name 'STRUCTURE_CHECK'
$fidelity = Get-FieldValue -Text $content -Name 'SOURCE_FIDELITY_CHECK'
$saturation = Get-FieldValue -Text $content -Name 'SATURATION_CHECK'
$k1Verdict = Get-FieldValue -Text $content -Name 'K1_VERDICT'
$leadAgent = Get-FieldValue -Text $content -Name 'LEAD_AGENT_ID'
$verifyAgent = Get-FieldValue -Text $content -Name 'VERIFY_AGENT_ID'
$researchRounds = Get-FieldValue -Text $content -Name 'RESEARCH_ROUNDS'
$stopReason = Get-FieldValue -Text $content -Name 'STOP_REASON'
if ($fidelity -eq 'PASS') {
    if ([string]::IsNullOrWhiteSpace($leadAgent)) { $errors.Add('SOURCE_FIDELITY_CHECK ma PASS, ale brak LEAD_AGENT_ID.') }
    if ([string]::IsNullOrWhiteSpace($verifyAgent)) { $errors.Add('SOURCE_FIDELITY_CHECK ma PASS, ale brak VERIFY_AGENT_ID.') }
    if ($leadAgent -and $verifyAgent -and $leadAgent -eq $verifyAgent) { $errors.Add('LEAD_AGENT_ID i VERIFY_AGENT_ID muszą wskazywać różne konteksty.') }
}
if ($saturation -eq 'PASS' -and ([string]::IsNullOrWhiteSpace($stopReason) -or $stopReason.Length -lt 15 -or $stopReason -match '^\[.*\]$|^NIEUSTALONE$|^DO UZUPEŁNIENIA$')) {
    $errors.Add('SATURATION_CHECK ma PASS, ale brak konkretnego STOP_REASON.')
}
$researchRoundsNumber = 0
if (-not [int]::TryParse($researchRounds, [ref]$researchRoundsNumber) -or $researchRoundsNumber -lt 1 -or $researchRoundsNumber -gt 2) {
    $errors.Add("RESEARCH_ROUNDS musi wynosić 1 albo 2, jest '$researchRounds'.")
}
$gateReady = $errors.Count -eq 0 -and $structureDeclared -eq 'PASS' -and $fidelity -eq 'PASS' -and $saturation -eq 'PASS' -and $k1Verdict -eq 'GOTOWE_DO_K2'

if ($structureDeclared -ne 'PASS') { $warnings.Add("STRUCTURE_CHECK nie ma PASS: '$structureDeclared'") }
if ($fidelity -ne 'PASS') { $warnings.Add("SOURCE_FIDELITY_CHECK nie ma PASS: '$fidelity'") }
if ($saturation -ne 'PASS') { $warnings.Add("SATURATION_CHECK nie ma PASS: '$saturation'") }
if ($k1Verdict -ne 'GOTOWE_DO_K2') { $warnings.Add("K1_VERDICT nie ma GOTOWE_DO_K2: '$k1Verdict'") }

$result = [pscustomobject]@{
    ProjectPath = $project
    Schema = $schema
    Sources = $sourceIds.Count
    SourceFiles = $sourceFiles.Count
    SourceTreeSha256 = $sourceTreeSha256
    Cards = $cardIds.Count
    CoreCards = $coreCount
    Errors = $errors.Count
    Warnings = $warnings.Count
    ErrorDetails = $errors
    WarningDetails = $warnings
    StructureVerdict = if ($errors.Count -eq 0) { 'STRUCTURE_PASS' } else { 'STRUCTURE_FAIL' }
    GateReady = $gateReady
}

$result
if ($errors.Count -gt 0 -and -not $NoExit) { exit 1 }
