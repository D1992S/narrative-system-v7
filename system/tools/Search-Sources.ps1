[CmdletBinding(DefaultParameterSetName = 'SingleQuery')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    # Pojedyncze pytanie: hasła rozdzielone średnikiem.
    [Parameter(Mandatory = $true, ParameterSetName = 'SingleQuery')]
    [ValidateNotNullOrEmpty()]
    [string]$Terms,

    # Pakiet pytań K0: plik, w którym każda linia ma postać `Q-001 = hasło; hasło`.
    # Korpus jest wtedy czytany i normalizowany jeden raz dla wszystkich celów.
    [Parameter(Mandatory = $true, ParameterSetName = 'QueryPack')]
    [ValidateNotNullOrEmpty()]
    [string]$QueryPack,

    [ValidateRange(1, 100)]
    [int]$MaxFragments = 8,

    [ValidateRange(1, 50)]
    [int]$MaxPerSource = 3,

    [ValidateRange(0, 20)]
    [int]$ContextLines = 2,

    # Twardy limit długości jednego fragmentu. Chroni przed zwróceniem
    # kilkusetliniowego bloku, gdy trafienia są gęsto rozsiane po źródle.
    [ValidateRange(2, 500)]
    [int]$MaxFragmentLines = 30,

    [string]$SourceFilter,

    [switch]$CountOnly
)

# Awaryjna wyszukiwarka fragmentów dla K1/K2B.
# Zamiast czytać całe źródła, agent pyta o hasła z pakietu K0 i dostaje
# najlepiej pasujące fragmenty z plikiem, zakresem linii i timestampem.
# Dopasowanie ignoruje wielkość liter i polskie znaki diakrytyczne.
# Narzędzie nie modyfikuje sources/ i nie tworzy żadnych plików.

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
$metaForAuthorization = Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8
$workflowRevision = Get-DocumentField -Text $metaForAuthorization -Name 'WORKFLOW_REVISION'
$k1LiteV2WorkflowRevisions = @('2026-08-31_NARRATIVE_V2','2026-08-30_K1_LITE_V2')
if ($workflowRevision -in $k1LiteV2WorkflowRevisions) {
    $originAuthorization = Assert-SystemV7CurrentProjectOrigin -ProjectPath $project -MetaText $metaForAuthorization
}
if ($workflowRevision -in $k1LiteV2WorkflowRevisions) {
    $fallbackState = Get-K1ManualFallbackReceiptState -ProjectPath $project
    if (-not $fallbackState.Valid) { throw "K1_MANUAL_FALLBACK_NOT_AUTHORIZED: $($fallbackState.Errors -join '; ')" }
    $fallbackAuthorization = [pscustomobject]@{ Required=$true; Valid=$true; ReceiptPath=$fallbackState.ReceiptPath; ReceiptSha256=$fallbackState.ReceiptSha256 }
} else {
    $fallbackAuthorization = Assert-K1ManualFallbackAuthorized -ProjectPath $project
}
$sourceDir = Join-Path $project 'sources'
$backupDirName = '_oryginaly'
$canonicalExtensions = @('.md', '.txt')
$mergeGap = 3

if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
    throw "Brak katalogu sources/: $sourceDir"
}

$combiningMarks = [regex]::new('\p{Mn}', [Text.RegularExpressions.RegexOptions]::Compiled)
function Get-NormalizedText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    # Całość w .NET: pętla znak po znaku w PowerShellu kosztowałaby sekundy na
    # każdym megabajcie korpusu. Normalizacja zachowuje znaki końca linii,
    # więc numery linii pozostają zgodne z plikiem oryginalnym.
    $stripped = $combiningMarks.Replace($Text.Normalize([Text.NormalizationForm]::FormD), '')
    $flat = $stripped.Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
    return $flat.Replace('ł','l').Replace('–','-').Replace('—','-')
}

function Get-LineIndex {
    param([int[]]$LineStarts, [int]$Offset)
    $low = 0; $high = $LineStarts.Length - 1
    while ($low -lt $high) {
        $mid = [int](($low + $high + 1) / 2)
        if ($LineStarts[$mid] -le $Offset) { $low = $mid } else { $high = $mid - 1 }
    }
    return $low
}

# ===== Pytania =====
$queries = [System.Collections.Generic.List[object]]::new()
if ($PSCmdlet.ParameterSetName -eq 'QueryPack') {
    $packPath = [IO.Path]::GetFullPath($QueryPack)
    if (-not (Test-Path -LiteralPath $packPath -PathType Leaf)) { throw "Brak pakietu pytań: $packPath" }
    foreach ($line in [IO.File]::ReadAllLines($packPath)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $match = [regex]::Match($trimmed, '^(?<id>[^=]+?)\s*=\s*(?<terms>.+)$')
        if (-not $match.Success) { throw "Nieprawidłowa linia pakietu pytań (oczekiwano 'Q-001 = hasło; hasło'): $trimmed" }
        $goalId = $match.Groups['id'].Value.Trim()
        # Uwaga: nazwa zmiennej nie może kolidować z parametrem [string]$Terms,
        # bo PowerShell skleiłby tablicę haseł z powrotem w jeden ciąg.
        $parsedTerms = @($match.Groups['terms'].Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($parsedTerms.Count -eq 0) { throw "Cel '$goalId' nie ma żadnego hasła." }
        $queries.Add([pscustomobject]@{ Id = $goalId; Terms = $parsedTerms })
    }
    if ($queries.Count -eq 0) { throw "Pakiet pytań nie zawiera żadnego celu: $packPath" }
} else {
    $parsedTerms = @($Terms -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parsedTerms.Count -eq 0) { throw 'Podaj przynajmniej jedno hasło w -Terms (separator ";").' }
    $queries.Add([pscustomobject]@{ Id = ''; Terms = $parsedTerms })
}

# Jeden skompilowany regex na pytanie, z nazwaną grupą na hasło. Skanowanie
# odbywa się w kodzie .NET, a nie w pętli PowerShella.
foreach ($query in $queries) {
    $normalizedTerms = @($query.Terms | ForEach-Object { Get-NormalizedText -Text $_ })
    $alternatives = for ($t = 0; $t -lt $normalizedTerms.Count; $t++) { "(?<t$t>$([regex]::Escape($normalizedTerms[$t])))" }
    Add-Member -InputObject $query -NotePropertyName 'Regex' -NotePropertyValue ([regex]::new(($alternatives -join '|'), [Text.RegularExpressions.RegexOptions]::Compiled))
    Add-Member -InputObject $query -NotePropertyName 'Candidates' -NotePropertyValue ([System.Collections.Generic.List[object]]::new())
    Add-Member -InputObject $query -NotePropertyName 'CountRows' -NotePropertyValue ([System.Collections.Generic.List[object]]::new())
}

# ===== Pliki =====
$discoveredFiles = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File | Sort-Object FullName)
$generatedEvidenceArtifacts = @($discoveredFiles | Where-Object {
    $_.Name -ieq '01-baza-dowodow.md' -or
    $_.Name -like 'K1-COMPILED-*.md' -or
    $_.Name -like '.K1-COMPILED-*.partial'
})
if ($generatedEvidenceArtifacts.Count -gt 0) {
    $relativeArtifacts = @($generatedEvidenceArtifacts | ForEach-Object {
        [IO.Path]::GetRelativePath($sourceDir, $_.FullName).Replace('\','/')
    })
    throw "W sources/ znaleziono artefakt bazy dowodów, który nie może być przeszukiwany jako źródło: $($relativeArtifacts -join ', '). Przenieś plik poza sources/; niczego nie zmieniono."
}
$files = @($discoveredFiles | Where-Object {
    $relative = [IO.Path]::GetRelativePath($sourceDir, $_.FullName).Replace('\','/')
    -not ($relative -like "$backupDirName/*") -and $_.Extension.ToLowerInvariant() -in $canonicalExtensions
})
if ($SourceFilter) {
    $files = @($files | Where-Object {
        $relative = [IO.Path]::GetRelativePath($sourceDir, $_.FullName).Replace('\','/')
        $relative -like "*$SourceFilter*"
    })
}

# Opcjonalne mapowanie plik -> #S z rejestru, jeżeli baza już istnieje.
$sourceIdByFile = @{}
$basePath = Join-Path $project '01-baza-dowodow.md'
if (Test-Path -LiteralPath $basePath -PathType Leaf) {
    $base = Get-Content -LiteralPath $basePath -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($base, '(?m)^\|\s*#?(S-\d{3,})\s*\|\s*([^|]*)\|')) {
        $refCell = $match.Groups[2].Value.Trim().Replace('\','/')
        foreach ($file in $files) {
            $relative = [IO.Path]::GetRelativePath($sourceDir, $file.FullName).Replace('\','/')
            if ($refCell -match [regex]::Escape($relative) -or $refCell -match [regex]::Escape($file.Name)) {
                if (-not $sourceIdByFile.ContainsKey($relative)) { $sourceIdByFile[$relative] = '#' + $match.Groups[1].Value }
            }
        }
    }
}

$timestampPattern = [regex]::new('\[(\d{1,2}:\d{2}(?::\d{2})?)\]', [Text.RegularExpressions.RegexOptions]::Compiled)
$linesByFile = @{}
$scannedFiles = 0
$scannedLines = 0

# Pętla zewnętrzna po plikach: każdy plik czytamy i normalizujemy dokładnie raz,
# niezależnie od liczby celów K0 w pakiecie.
foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($sourceDir, $file.FullName).Replace('\','/')
    $rawText = [IO.File]::ReadAllText($file.FullName)
    $lines = $rawText -split "\r?\n"
    $normalizedText = Get-NormalizedText -Text $rawText
    $linesByFile[$relative] = $lines
    $scannedFiles++
    $scannedLines += $lines.Count

    $lineStarts = [System.Collections.Generic.List[int]]::new()
    $lineStarts.Add(0)
    $newlineAt = $normalizedText.IndexOf("`n")
    while ($newlineAt -ge 0) {
        $lineStarts.Add($newlineAt + 1)
        $newlineAt = $normalizedText.IndexOf("`n", $newlineAt + 1)
    }
    $lineStartArray = $lineStarts.ToArray()

    $lastTimestamp = $null

    foreach ($query in $queries) {
        $termCount = $query.Terms.Count
        $hitTermsByLine = @{}
        $termHitCounts = @(0) * $termCount
        foreach ($match in $query.Regex.Matches($normalizedText)) {
            for ($t = 0; $t -lt $termCount; $t++) {
                if (-not $match.Groups["t$t"].Success) { continue }
                $termHitCounts[$t]++
                $lineIndex = Get-LineIndex -LineStarts $lineStartArray -Offset $match.Index
                $existing = $hitTermsByLine[$lineIndex]
                if ($null -eq $existing) {
                    $existing = [System.Collections.Generic.HashSet[int]]::new()
                    $hitTermsByLine[$lineIndex] = $existing
                }
                [void]$existing.Add($t)
            }
        }

        if ($CountOnly) {
            $summary = for ($t = 0; $t -lt $termCount; $t++) { "$($query.Terms[$t])=$($termHitCounts[$t])" }
            $query.CountRows.Add([pscustomobject]@{
                SourceId = if ($sourceIdByFile.ContainsKey($relative)) { $sourceIdByFile[$relative] } else { '' }
                File = $relative
                Lines = $lines.Count
                HitLines = $hitTermsByLine.Count
                PerTerm = ($summary -join '; ')
            })
            continue
        }
        if ($hitTermsByLine.Count -eq 0) { continue }

        # Indeks ostatniego timestampu w linii i wcześniej — liczony leniwie i
        # tylko raz na plik.
        if ($null -eq $lastTimestamp) {
            $lastTimestamp = [string[]]::new($lines.Count)
            $current = ''
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $tsMatch = $timestampPattern.Match($lines[$i])
                if ($tsMatch.Success) { $current = $tsMatch.Groups[1].Value }
                $lastTimestamp[$i] = $current
            }
        }

        # Scal bliskie trafienia w jeden fragment.
        $hitLines = @($hitTermsByLine.Keys | Sort-Object)
        $groups = [System.Collections.Generic.List[object]]::new()
        $start = $hitLines[0]; $end = $hitLines[0]
        $groupTerms = [System.Collections.Generic.HashSet[int]]::new()
        $groupHits = 1
        foreach ($t in $hitTermsByLine[$hitLines[0]]) { [void]$groupTerms.Add($t) }
        for ($h = 1; $h -lt $hitLines.Count; $h++) {
            $line = $hitLines[$h]
            # Nowy fragment, gdy trafienia się rozjeżdżają albo gdy bieżący
            # fragment osiągnął limit długości.
            if (($line - $end -le $mergeGap) -and (($line - $start + 1) -le $MaxFragmentLines)) {
                $end = $line
                $groupHits++
            } else {
                $groups.Add([pscustomobject]@{ Start = $start; End = $end; Terms = @($groupTerms); Hits = $groupHits })
                $start = $line; $end = $line
                $groupHits = 1
                $groupTerms = [System.Collections.Generic.HashSet[int]]::new()
            }
            foreach ($t in $hitTermsByLine[$line]) { [void]$groupTerms.Add($t) }
        }
        $groups.Add([pscustomobject]@{ Start = $start; End = $end; Terms = @($groupTerms); Hits = $groupHits })

        # Tekst fragmentu wycinamy dopiero po wyborze najlepszych trafień.
        # Ranking: najpierw liczba różnych haseł, potem gęstość trafień.
        # Sama długość fragmentu nie podnosi wyniku.
        foreach ($group in $groups) {
            $distinct = @($group.Terms).Count
            $span = $group.End - $group.Start + 1
            $density = [Math]::Round((100.0 * $group.Hits) / $span)
            $query.Candidates.Add([pscustomobject]@{
                File = $relative
                Start = $group.Start
                End = $group.End
                Terms = $group.Terms
                Timestamp = $lastTimestamp[$group.Start]
                DistinctTerms = $distinct
                Hits = $group.Hits
                Score = ($distinct * 10000) + [Math]::Min($group.Hits, 50) * 100 + $density
            })
        }
    }
}

function Select-Fragments {
    param([object]$Query)
    $selected = [System.Collections.Generic.List[object]]::new()
    $perSource = @{}
    foreach ($candidate in ($Query.Candidates | Sort-Object Score, DistinctTerms -Descending)) {
        if ($selected.Count -ge $MaxFragments) { break }
        if (-not $perSource.ContainsKey($candidate.File)) { $perSource[$candidate.File] = 0 }
        if ($perSource[$candidate.File] -ge $MaxPerSource) { continue }
        $perSource[$candidate.File]++

        $lines = $linesByFile[$candidate.File]
        $fromLine = [Math]::Max(0, $candidate.Start - $ContextLines)
        $toLine = [Math]::Min($lines.Count - 1, $candidate.End + $ContextLines)
        $selected.Add([pscustomobject]@{
            SourceId = if ($sourceIdByFile.ContainsKey($candidate.File)) { $sourceIdByFile[$candidate.File] } else { '' }
            File = $candidate.File
            FromLine = $fromLine + 1
            ToLine = $toLine + 1
            Locator = "L$($fromLine + 1)-L$($toLine + 1)"
            Timestamp = $candidate.Timestamp
            DistinctTerms = $candidate.DistinctTerms
            Hits = $candidate.Hits
            MatchedTerms = (@($candidate.Terms | Sort-Object | ForEach-Object { $Query.Terms[$_] }) -join ', ')
            Score = $candidate.Score
            Text = ($lines[$fromLine..$toLine] -join "`n").Trim()
        })
    }
    return $selected
}

if ($CountOnly) {
    if ($PSCmdlet.ParameterSetName -eq 'QueryPack') {
        return [pscustomobject]@{
            ProjectPath = $project
            ScannedFiles = $scannedFiles
            ScannedLines = $scannedLines
            Results = @($queries | ForEach-Object {
                [pscustomobject]@{ Goal = $_.Id; Terms = $_.Terms; Counts = ($_.CountRows | Sort-Object HitLines -Descending) }
            })
        }
    }
    return [pscustomobject]@{
        ProjectPath = $project
        Terms = $queries[0].Terms
        ScannedFiles = $scannedFiles
        ScannedLines = $scannedLines
        Counts = ($queries[0].CountRows | Sort-Object HitLines -Descending)
    }
}

if ($PSCmdlet.ParameterSetName -eq 'QueryPack') {
    $results = foreach ($query in $queries) {
        $selected = Select-Fragments -Query $query
        [pscustomobject]@{
            Goal = $query.Id
            Terms = $query.Terms
            TotalFragments = $query.Candidates.Count
            Returned = $selected.Count
            Fragments = $selected
        }
    }
    return [pscustomobject]@{
        ProjectPath = $project
        ScannedFiles = $scannedFiles
        ScannedLines = $scannedLines
        Goals = $queries.Count
        TotalReturned = (@($results | Measure-Object Returned -Sum).Sum)
        Results = @($results)
    }
}

$selected = Select-Fragments -Query $queries[0]
[pscustomobject]@{
    ProjectPath = $project
    Terms = $queries[0].Terms
    ScannedFiles = $scannedFiles
    ScannedLines = $scannedLines
    TotalFragments = $queries[0].Candidates.Count
    Returned = $selected.Count
    Fragments = $selected
}
