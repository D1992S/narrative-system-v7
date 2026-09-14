[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Preview','Publish')]
    [string]$Action,
    [Parameter(Mandatory)]
    [string]$ProjectPath,
    [Parameter(Mandatory)]
    [string]$RunDirectory,
    [Parameter(Mandatory)]
    [string]$ExpectedLedgerSha256,
    [string]$OutputDirectory,
    [string]$PreviewPath,
    [string]$ExpectedPreviewSha256,
    [string]$PythonPath = 'python.exe',
    [switch]$InternalAllowCorpusSubset,
    [IO.FileStream]$InternalHeldProjectLock
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$run = [IO.Path]::GetFullPath($RunDirectory)
$allowedRunRoot = [IO.Path]::GetFullPath((Join-Path $project '_work\K1\k1-lite-v2'))
$runPrefix = $allowedRunRoot.TrimEnd('\') + '\'
if (-not (Test-Path -LiteralPath $project -PathType Container)) { throw "PROJECT_NOT_FOUND: $project" }
if (-not $run.StartsWith($runPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "RUN_OUTSIDE_PROJECT: $run" }
if ($ExpectedLedgerSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'EXPECTED_LEDGER_SHA_INVALID' }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot 'Project-Origin.ps1')
. (Join-Path $scriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $scriptRoot 'Narrative-V2.ps1')
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project -SystemRoot (Split-Path -Parent $scriptRoot) | Out-Null
$projectMetaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $projectMetaPath -PathType Leaf)) { throw "META_MISSING: $projectMetaPath" }
$projectMeta = Get-Content -LiteralPath $projectMetaPath -Raw -Encoding UTF8
$projectOrigin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $projectMeta
if ($null -ne $InternalHeldProjectLock) {
    $callerPathForLock = if ($MyInvocation.ScriptName) { [IO.Path]::GetFullPath($MyInvocation.ScriptName) } else { '' }
    $allowedLockCallers = @(
        [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path),
        [IO.Path]::GetFullPath((Join-Path $scriptRoot 'Compile-K1LiteV2Corpus.ps1')),
        [IO.Path]::GetFullPath((Join-Path $scriptRoot 'Merge-K1LiteV2Supplement.ps1'))
    )
    if (-not @($allowedLockCallers | Where-Object { $_.Equals($callerPathForLock, [StringComparison]::OrdinalIgnoreCase) }).Count) {
        throw 'INTERNAL_HELD_PROJECT_LOCK_UNAUTHORIZED'
    }
}
$ownsProjectLock = $null -eq $InternalHeldProjectLock
$projectLock = if ($ownsProjectLock) { Enter-SystemV7ProjectMetaLock -ProjectPath $project } else { $InternalHeldProjectLock }
try {
$projectMeta = Get-Content -LiteralPath $projectMetaPath -Raw -Encoding UTF8
$projectOrigin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $projectMeta
Assert-SystemV7PathNoReparse -Path $allowedRunRoot -ContainmentRoot $project | Out-Null
Assert-SystemV7TreeNoReparse -RootPath $run -ContainmentRoot $project | Out-Null
$internalCaller = if ($MyInvocation.ScriptName) { [IO.Path]::GetFullPath($MyInvocation.ScriptName) } else { '' }
$allowedInternalCallers = @(
    [IO.Path]::GetFullPath((Join-Path $scriptRoot 'Compile-K1LiteV2Corpus.ps1')),
    [IO.Path]::GetFullPath((Join-Path $scriptRoot 'Merge-K1LiteV2Supplement.ps1'))
)
if ($InternalAllowCorpusSubset -and -not ($allowedInternalCallers | Where-Object { $_.Equals($internalCaller, [StringComparison]::OrdinalIgnoreCase) })) {
    throw 'INTERNAL_CORPUS_SUBSET_UNAUTHORIZED'
}
$currentStage = Get-SystemV7SingleMetaField -Text $projectMeta -Name 'CURRENT_STAGE'
$mergeCaller = [IO.Path]::GetFullPath((Join-Path $scriptRoot 'Merge-K1LiteV2Supplement.ps1'))
$corpusCaller = [IO.Path]::GetFullPath((Join-Path $scriptRoot 'Compile-K1LiteV2Corpus.ps1'))
if ($Action -eq 'Publish' -and $currentStage -cne 'K1') {
    throw "K1_COMPILE_STAGE_UNAUTHORIZED: action=Publish stage=$currentStage expected=K1"
}
if (-not $InternalAllowCorpusSubset -and $currentStage -cne 'K1') {
    throw "K1_COMPILE_STAGE_UNAUTHORIZED: action=$Action stage=$currentStage expected=K1"
}
if ($InternalAllowCorpusSubset -and $internalCaller.Equals($mergeCaller, [StringComparison]::OrdinalIgnoreCase) -and $currentStage -cne 'K2B') {
    throw "K1_SUPPLEMENT_INTERNAL_STAGE_UNAUTHORIZED: stage=$currentStage expected=K2B"
}
if ($InternalAllowCorpusSubset -and $internalCaller.Equals($corpusCaller, [StringComparison]::OrdinalIgnoreCase) -and $currentStage -notin @('K1','K2B')) {
    throw "K1_CORPUS_INTERNAL_STAGE_UNAUTHORIZED: stage=$currentStage expected=K1_or_K2B"
}
$engine = Join-Path $scriptRoot 'k1-lite-v2\Invoke-K1LiteV2.ps1'
$validator = Join-Path $scriptRoot 'Validate-EvidenceBase.ps1'
$publishIntegrity = Join-Path $scriptRoot 'K1-PublishIntegrity.ps1'
$ledgerPath = Join-Path $run 'ledger.jsonl'
$runPath = Join-Path $run 'run.json'
foreach ($required in @($engine,$validator,$publishIntegrity,$ledgerPath,$runPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "REQUIRED_FILE_MISSING: $required" }
    Assert-SystemV7PathNoReparse -Path $required -ContainmentRoot $(if ($required.StartsWith($project, [StringComparison]::OrdinalIgnoreCase)) { $project } else { Split-Path -Parent $scriptRoot }) | Out-Null
}
. $publishIntegrity
$ledgerHash = (Get-FileHash -LiteralPath $ledgerPath -Algorithm SHA256).Hash
if ($ledgerHash -ne $ExpectedLedgerSha256.ToUpperInvariant()) { throw "LEDGER_SHA_MISMATCH: expected=$($ExpectedLedgerSha256.ToUpperInvariant()) actual=$ledgerHash" }

function Get-RelativeUnix([string]$Base, [string]$Path) {
    ([IO.Path]::GetRelativePath($Base, $Path)).Replace('\','/')
}

function Get-RunCreatedUtcDateFromJson([string]$Json) {
    $document = $null
    try {
        $document = [Text.Json.JsonDocument]::Parse($Json)
        $createdAt = [string]$document.RootElement.GetProperty('created_at').GetString()
    } catch {
        throw 'RUN_CREATED_AT_INVALID'
    } finally {
        if ($null -ne $document) { $document.Dispose() }
    }
    $formats = [string[]]@("yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'")
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParseExact($createdAt, $formats, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        throw 'RUN_CREATED_AT_INVALID'
    }
    return $parsed.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
}

function Escape-Table([string]$Value) {
    if ($null -eq $Value) { return '' }
    return $Value.Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
}

function Set-MetaField([string]$Text, [string]$Name, [string]$Value) {
    $pattern = "(?m)^$([regex]::Escape($Name)):\s*.*$"
    if ([regex]::IsMatch($Text, $pattern)) {
        $literal = "${Name}: $Value"
        return [regex]::Replace($Text, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $literal }, 1)
    }
    $anchor = '(?m)^SYSTEM_VERSION:\s*.*$'
    if ([regex]::IsMatch($Text, $anchor)) { return [regex]::Replace($Text, $anchor, { param($m) $m.Value + "`r`n${Name}: $Value" }, 1) }
    throw "META_ANCHOR_MISSING: $Name"
}

function Get-PublishVerificationDirectory([string]$TargetRun) {
    $target = Join-Path $TargetRun ('.publish-verify-' + [guid]::NewGuid().ToString('N'))
    $target = [IO.Path]::GetFullPath($target)
    if (-not ([IO.Path]::GetFullPath((Split-Path -Parent $target))).Equals([IO.Path]::GetFullPath($TargetRun), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'PUBLISH_VERIFICATION_DIRECTORY_INVALID'
    }
    if (Test-Path -LiteralPath $target) { throw 'PUBLISH_VERIFICATION_DIRECTORY_EXISTS' }
    return $target
}

function Remove-PublishVerificationDirectory([string]$TargetRun, [string]$Target) {
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) { return }
    $resolvedRun = [IO.Path]::GetFullPath($TargetRun)
    $resolvedTarget = [IO.Path]::GetFullPath($Target)
    $parent = [IO.Path]::GetFullPath((Split-Path -Parent $resolvedTarget))
    $leaf = Split-Path -Leaf $resolvedTarget
    if (-not $parent.Equals($resolvedRun, [StringComparison]::OrdinalIgnoreCase) -or $leaf -notmatch '^\.publish-verify-[a-f0-9]{32}$') {
        throw "UNSAFE_PUBLISH_VERIFICATION_CLEANUP: $resolvedTarget"
    }
    [IO.Directory]::Delete($resolvedTarget, $true)
}

function Assert-FilesByteIdentical([string]$Expected, [string]$Actual, [string]$ErrorCode) {
    $expectedBytes = [IO.File]::ReadAllBytes($Expected)
    $actualBytes = [IO.File]::ReadAllBytes($Actual)
    if ($expectedBytes.Length -ne $actualBytes.Length) { throw $ErrorCode }
    for ($index = 0; $index -lt $expectedBytes.Length; $index++) {
        if ($expectedBytes[$index] -ne $actualBytes[$index]) { throw $ErrorCode }
    }
}

function Get-NormalizedAggregatePreview([string]$Path) {
    $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    return [regex]::Replace($text, '(?m)^K1_EXPORT_PATH:[^\r\n]*', 'K1_EXPORT_PATH: <PUBLISH-VERIFICATION-PATH>')
}

function Assert-AggregatePreviewsEquivalent([string]$Expected, [string]$Actual, [string]$ErrorCode) {
    if ((Get-NormalizedAggregatePreview $Expected) -cne (Get-NormalizedAggregatePreview $Actual)) { throw $ErrorCode }
}

function Get-SelectedCandidates([object[]]$Events) {
    $candidates = @{}
    foreach ($event in $Events) {
        if ($event.event_type -eq 'candidate') {
            if ($event.supersedes) { [void]$candidates.Remove([string]$event.supersedes) }
            $candidates[[string]$event.candidate_id] = $event
        }
    }
    $editorial = @{}
    $recommendations = @{}
    foreach ($event in $Events) {
        if ($event.event_type -ne 'decision') { continue }
        if ($event.decision -eq 'KEY_CHATGPT') { $recommendations[[string]$event.candidate_id] = $event }
        else { $editorial[[string]$event.candidate_id] = $event }
    }
    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($id in @($candidates.Keys | Sort-Object)) {
        $choice = $null
        if ($editorial.ContainsKey($id)) {
            if ($editorial[$id].decision -in @('MUST_INCLUDE','IMPORTANT_SIDE')) { $choice = $editorial[$id] }
        } elseif ($recommendations.ContainsKey($id)) {
            $choice = $recommendations[$id]
        }
        if ($choice) { $selected.Add([pscustomobject]@{ Id=$id; Candidate=$candidates[$id]; Choice=$choice }) }
    }
    return @($selected)
}

$compileGates = @('coverage_ready','quotes_ready','decisions_current','selected_visual_ready','selected_conflicts_acknowledged','editorial_review_ready')

function Assert-CurrentRunGates([string]$TargetRun) {
    $targetRunData = Get-Content -LiteralPath (Join-Path $TargetRun 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    $targetLedgerSha = (Get-FileHash -LiteralPath (Join-Path $TargetRun 'ledger.jsonl') -Algorithm SHA256).Hash
    $targetLineage = @(Resolve-K1PublishLineage -ProjectPath $project -PublicationRunDirectory $TargetRun -PublicationRunData $targetRunData -ExpectedPublicationLedgerSha256 $targetLedgerSha)
    Invoke-K1FreshLineageGates -EnginePath $engine -ProjectPath $project -Lineage $targetLineage -PythonPath $PythonPath | Out-Null
}

function Assert-CorpusSourceRunGates([object]$CorpusRunData) {
    $corpusLineage = @(Resolve-K1PublishLineage -ProjectPath $project -PublicationRunDirectory $run -PublicationRunData $CorpusRunData -ExpectedPublicationLedgerSha256 $ledgerHash)
    Invoke-K1FreshLineageGates -EnginePath $engine -ProjectPath $project -Lineage $corpusLineage -PythonPath $PythonPath | Out-Null
}

if ($Action -eq 'Preview') {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { throw 'OUTPUT_DIRECTORY_REQUIRED' }
    $output = [IO.Path]::GetFullPath($OutputDirectory)
    $outputPrefix = $run.TrimEnd('\') + '\'
    $allowedOutputPrefix = if ($InternalAllowCorpusSubset) { $allowedRunRoot.TrimEnd('\') + '\' } else { $outputPrefix }
    if (-not $output.StartsWith($allowedOutputPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "OUTPUT_OUTSIDE_RUN: $output" }
    if (Test-Path -LiteralPath $output) { throw "OUTPUT_EXISTS: $output" }

    & $engine -Action ValidateRun -ProjectDirectory $project -RunDirectory $run -PythonPath $PythonPath | Out-Null
    & $engine -Action BuildViews -ProjectDirectory $project -RunDirectory $run -OutputDirectory $output -PythonPath $PythonPath -InternalHeldProjectLock $projectLock | Out-Null

    $reportPath = Join-Path $output 'compile-report.json'
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    foreach ($gate in $compileGates) {
        if (-not $report.gates.$gate) { throw "COMPILE_GATE_FAIL: $gate" }
    }
    # A corpus compile must be able to account for a fully reviewed source that
    # yielded no selected evidence. The public single-run compiler still
    # refuses an empty publication; only the authenticated corpus path may
    # carry such a run forward as coverage with zero cards.
    if ([int]$report.counts.selected -lt 1 -and -not $InternalAllowCorpusSubset) {
        throw 'COMPILE_NO_SELECTED_CANDIDATES'
    }

    $runJsonText = Get-Content -LiteralPath $runPath -Raw -Encoding UTF8
    $runData = $runJsonText | ConvertFrom-Json -DateKind String
    if ([string]$runData.engine_version -ne '2.1.0') { throw "RUN_ENGINE_VERSION_UNSUPPORTED: $($runData.engine_version)" }
    $engineVersion = [string]$runData.engine_version
    $runDate = Get-RunCreatedUtcDateFromJson $runJsonText
    $events = @(Get-Content -LiteralPath $ledgerPath -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String })
    $selected = @(Get-SelectedCandidates $events)
    if ($selected.Count -ne [int]$report.counts.selected) { throw "SELECTED_COUNT_MISMATCH: ledger=$($selected.Count) report=$($report.counts.selected)" }

    $sourceFull = [IO.Path]::GetFullPath((Join-Path $project ([string]$runData.source_relative)))
    if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) { throw "SOURCE_MISSING: $sourceFull" }
    if ((Get-FileHash -LiteralPath $sourceFull -Algorithm SHA256).Hash -ne [string]$runData.source_sha256) { throw 'SOURCE_SHA_STALE' }

    $sourcesRoot = [IO.Path]::GetFullPath((Join-Path $project 'sources'))
    $supportedExtensions = @('.pdf','.md','.txt','.srt','.vtt')
    $nestedSupported = @(Get-ChildItem -LiteralPath $sourcesRoot -Recurse -File | Where-Object {
        $_.DirectoryName -ne $sourcesRoot -and $_.FullName -notmatch '\\_oryginaly(?:\\|$)' -and $_.Extension.ToLowerInvariant() -in $supportedExtensions
    })
    if ($nestedSupported.Count -gt 0) { throw "SUPPORTED_SOURCE_IN_SUBDIRECTORY: $($nestedSupported.FullName -join '; ')" }
    $sourceFiles = @(Get-ChildItem -LiteralPath $sourcesRoot -File | Where-Object { $_.Extension.ToLowerInvariant() -in $supportedExtensions } | Sort-Object FullName)
    $pdfFull = if ($runData.pdf_relative) { [IO.Path]::GetFullPath((Join-Path $project ([string]$runData.pdf_relative))) } else { $null }
    if (-not $InternalAllowCorpusSubset) {
        $unanalysed = @($sourceFiles | Where-Object {
            -not $_.FullName.Equals($sourceFull, [StringComparison]::OrdinalIgnoreCase) -and
            (-not $pdfFull -or -not $_.FullName.Equals($pdfFull, [StringComparison]::OrdinalIgnoreCase))
        })
        if ($unanalysed.Count -gt 0) {
            throw "CORPUS_REQUIRES_MULTI_RUN_COMPILER: $($unanalysed.FullName -join '; ')"
        }
    }
    $sourceRows = [System.Collections.Generic.List[string]]::new()
    $sourceIdByPath = @{}
    $index = 1
    foreach ($file in $sourceFiles) {
        $id = 'S-{0:D3}' -f $index
        $sourceIdByPath[$file.FullName.ToLowerInvariant()] = $id
        $relative = Get-RelativeUnix $project $file.FullName
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $isCanonical = $file.FullName.Equals($sourceFull, [StringComparison]::OrdinalIgnoreCase)
        $role = if ($isCanonical) { 'RDZEŃ' } elseif ($file.Extension -eq '.pdf') { 'TECHNICZNE' } else { 'REZERWA' }
        # Brak jawnych metadanych o autorze/instytucji nie uzasadnia automatycznej klasy B.
        $class = if ($isCanonical) { 'D' } else { '—' }
        $range = if ($isCanonical) {
            if (-not [string]::IsNullOrWhiteSpace([string]$runData.source_coverage)) { [string]$runData.source_coverage }
            elseif ([string]$runData.locator_kind -eq 'PAGE' -or -not $runData.locator_kind) { "P0001-$('P{0:D4}' -f [int]$runData.physical_pages)" }
            else { throw 'RUN_SOURCE_COVERAGE_MISSING' }
        } else { '—' }
        $cards = if ($isCanonical) { ($selected | ForEach-Object -Begin {$n=0} -Process {$n++; '#P-{0:D3}' -f $n}) -join ', ' } else { '—' }
        $sourceRows.Add("| #$id | $(Escape-Table $relative) | NIEUSTALONE | NIEUSTALONE | $class | $role | $range | $hash | $cards | wygenerowano przez K1-Lite V2 |")
        $index++
    }
    $canonicalSourceId = $sourceIdByPath[$sourceFull.ToLowerInvariant()]
    if (-not $canonicalSourceId) { throw 'CANONICAL_SOURCE_NOT_REGISTERED' }

    $k0Path = Join-Path $project '00-fundament-projektu.md'
    $k0 = Get-Content -LiteralPath $k0Path -Raw -Encoding UTF8
    $goalIds = @([regex]::Matches($k0, '(?m)^\|\s*(Q-\d{3,})\s*\|') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    if ($goalIds.Count -eq 0) { throw 'K0_GOALS_MISSING' }
    $cardsByGoal = @{}
    for ($selectedIndex = 0; $selectedIndex -lt $selected.Count; $selectedIndex++) {
        $cardId = '#P-{0:D3}' -f ($selectedIndex + 1)
        foreach ($goalMatch in [regex]::Matches([string]$selected[$selectedIndex].Candidate.k0_target, 'Q-\d{3,}')) {
            $goalId = $goalMatch.Value
            if (-not $cardsByGoal.ContainsKey($goalId)) { $cardsByGoal[$goalId] = [System.Collections.Generic.List[string]]::new() }
            if (-not $cardsByGoal[$goalId].Contains($cardId)) { $cardsByGoal[$goalId].Add($cardId) }
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    @(
        '# 01 — MINIMALNA BAZA DOWODÓW', '',
        'K1_SCHEMA: MINIMAL_EVIDENCE_V4_PAGELOC', 'LOCATOR_POLICY: MIXED_V1', 'STATUS: GOTOWY', "DATA_ODCIĘCIA: $runDate",
        'LEAD_AGENT_ID: chatgpt-k1-lite-v2', 'VERIFY_AGENT_ID: local-exact-quote-verifier', 'RESEARCH_ROUNDS: 1',
        'STOP_REASON: Pełne pokrycie pakietów, aktualne decyzje, cytaty, kontrola wizualna, konflikty i hash-bound przegląd Dawida przeszły bramki kompilatora.',
        'STRUCTURE_CHECK: PASS', 'SOURCE_FIDELITY_CHECK: PASS', 'SATURATION_CHECK: PASS', 'K1_VERDICT: GOTOWE_DO_K2',
        'K1_ORIGIN: K1_LITE_V2', "K1_ORIGIN_VERSION: $engineVersion", "K1_EXPORT_PATH: $(Get-RelativeUnix $project $ledgerPath)",
        "K1_EXPORT_SHA256: $ledgerHash", 'CORPUS_COVERAGE_REVIEWED: TAK', 'K0_COVERAGE_REVIEWED: TAK', 'SOURCE_CLASSES_REVIEWED: TAK', '',
        '## 1. Pokrycie celów i handoff K2', '', 'NIEROZLICZONE_ŹRÓDŁA: 0', '',
        '| Cel | Status: POKRYTY / LUKA JAWNA / POZA ZAKRESEM | Najważniejsze #P | Luka/uwaga |', '|---|---|---|---|'
    ) | ForEach-Object { $lines.Add($_) }
    foreach ($goal in $goalIds) {
        if ($cardsByGoal.ContainsKey($goal) -and $cardsByGoal[$goal].Count -gt 0) {
            $lines.Add("| $goal | POKRYTY | $($cardsByGoal[$goal] -join ', ') | Pokrycie wynika z pola k0_target zweryfikowanych kandydatów. |")
        } else {
            $lines.Add("| $goal | LUKA JAWNA | — | Brak wybranej karty przypisanej do tego celu. |")
        }
    }
    @('', '### Najważniejsze ustalenia', '', '- Patrz karty wybrane przez Dawida lub oznaczone jako kluczowe przez ChatGPT.', '',
      '### Sceny-kotwice i wypłaty', '', '- Do ustalenia w K2.', '', '### Sprzeczności i jawne luki', '',
      '- Konflikty wybranych kart zostały jawnie rozstrzygnięte przed kompilacją.', '', '### Kolejka K4', '', '- Zweryfikować prawdziwość i niezależność twierdzeń; K1 potwierdza wierność źródłu, nie prawdę.', '',
      '## 2. Rejestr logicznych źródeł', '',
      '| ID | Plik/URL i zaplecze | Autor/instytucja | Data | Klasa A–D | Rola: RDZEŃ/CELOWE/REZERWA/WYŁĄCZONE/TECHNICZNE | Zakres sprawdzony | SHA-256 źródła | Karty/wynik | Uwagi |',
      '|---|---|---|---|---|---|---|---|---|---|') | ForEach-Object { $lines.Add($_) }
    foreach ($row in $sourceRows) { $lines.Add($row) }
    @('', '## 3. Karty dowodowe', '') | ForEach-Object { $lines.Add($_) }
    $cardNo = 1
    foreach ($item in $selected) {
        $quote = ([string]$item.Candidate.quote).Replace("`r",' ').Replace("`n",' ')
        $quote = [regex]::Replace($quote, '\s+', ' ').Trim()
        $lines.Add("### #P-$($cardNo.ToString('D3'))")
        $lines.Add('')
        $lines.Add("TREŚĆ: $quote")
        $lines.Add("ŹRÓDŁO_ID: #$canonicalSourceId")
        $lines.Add("LOKALIZACJA: $($item.Candidate.locator)")
        $lines.Add('QA_K1: GOTOWA')
        $lines.Add('')
        $cardNo++
    }
    @('## 4. Changelog', '', "- $runDate — kompilacja z runu $($runData.run_id); ledger $ledgerHash.") | ForEach-Object { $lines.Add($_) }
    $compiledPath = Join-Path $output ("K1-COMPILED-$($runData.run_id).md")
    [IO.File]::WriteAllText($compiledPath, (($lines -join "`r`n") + "`r`n"), [Text.UTF8Encoding]::new($false))
    if (-not ($InternalAllowCorpusSubset -and $selected.Count -eq 0)) {
        $validation = & $validator -ProjectPath $project -EvidencePath $compiledPath -PendingReview -NoExit
        if ($validation.Errors -gt 0 -or -not $validation.ReadyForImport) { throw "COMPILED_PREVIEW_INVALID: $($validation.ErrorDetails -join '; ')" }
    }
    [pscustomobject]@{ Status='PREVIEW_READY'; PreviewPath=$compiledPath; PreviewSha256=(Get-FileHash -LiteralPath $compiledPath -Algorithm SHA256).Hash; LedgerSha256=$ledgerHash; Cards=$selected.Count }
    return
}

if ([string]::IsNullOrWhiteSpace($PreviewPath)) { throw 'PREVIEW_PATH_REQUIRED' }
if ($ExpectedPreviewSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'EXPECTED_PREVIEW_SHA_INVALID' }
$preview = [IO.Path]::GetFullPath($PreviewPath)
if (-not $preview.StartsWith($run.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'PREVIEW_OUTSIDE_RUN' }
if ((Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash -ne $ExpectedPreviewSha256.ToUpperInvariant()) { throw 'PREVIEW_SHA_MISMATCH' }
$preflight = & $validator -ProjectPath $project -EvidencePath $preview -PendingReview -NoExit
if ($preflight.Errors -gt 0 -or -not $preflight.ReadyForImport) { throw "PREVIEW_NOT_READY: $($preflight.ErrorDetails -join '; ')" }
$destination = Join-Path $project '01-baza-dowodow.md'
if ((Test-Path -LiteralPath $destination) -and -not (Test-Path -LiteralPath $destination -PathType Leaf)) {
    throw "CANONICAL_EVIDENCE_PATH_INVALID: $destination"
}
Assert-SystemV7PathNoReparse -Path $destination -ContainmentRoot $project | Out-Null
if ((Test-Path -LiteralPath $destination -PathType Leaf) -and
    (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $ExpectedPreviewSha256.ToUpperInvariant()) {
    throw "CANONICAL_EVIDENCE_EXISTS_DIFFERENT: $destination"
}
$publishRunData = Get-Content -LiteralPath $runPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
if ([string]$publishRunData.engine_version -ne '2.1.0') { throw "RUN_ENGINE_VERSION_UNSUPPORTED: $($publishRunData.engine_version)" }
$publishPreviewText = Get-Content -LiteralPath $preview -Raw -Encoding UTF8
$previewExportPathMatch = [regex]::Match($publishPreviewText, '(?m)^K1_EXPORT_PATH:\s*(.*?)\s*$')
$previewExportHashMatch = [regex]::Match($publishPreviewText, '(?m)^K1_EXPORT_SHA256:\s*([A-Fa-f0-9]{64})\s*$')
if (-not $previewExportPathMatch.Success -or -not $previewExportHashMatch.Success) { throw 'PREVIEW_EXPORT_BINDING_MISSING' }
$previewExportPathValue = $previewExportPathMatch.Groups[1].Value.Trim()
$resolvedPreviewExport = if ([IO.Path]::IsPathRooted($previewExportPathValue)) {
    [IO.Path]::GetFullPath($previewExportPathValue)
} else {
    [IO.Path]::GetFullPath((Join-Path $project $previewExportPathValue))
}
if (-not $resolvedPreviewExport.Equals([IO.Path]::GetFullPath($ledgerPath), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'PREVIEW_EXPORT_PATH_MISMATCH'
}
if ($previewExportHashMatch.Groups[1].Value.ToUpperInvariant() -ne $ledgerHash) { throw 'PREVIEW_EXPORT_SHA_MISMATCH' }
$verificationDirectory = Get-PublishVerificationDirectory $run
try {
    if ([string]$publishRunData.schema -eq 'K1_LITE_V2_RUN_V1') {
        $regenerated = & $MyInvocation.MyCommand.Path -Action Preview -ProjectPath $project -RunDirectory $run -ExpectedLedgerSha256 $ledgerHash -OutputDirectory $verificationDirectory -PythonPath $PythonPath -InternalHeldProjectLock $projectLock
        Assert-FilesByteIdentical $preview ([string]$regenerated.PreviewPath) 'PUBLISH_DERIVATION_MISMATCH'
        if ([string]$regenerated.PreviewSha256 -ne $ExpectedPreviewSha256.ToUpperInvariant()) { throw 'PUBLISH_DERIVATION_SHA_MISMATCH' }
    } elseif ([string]$publishRunData.run_type -eq 'CORPUS_COMPILE') {
        $sourceRunIds = @($publishRunData.source_runs | ForEach-Object { [string]$_ })
        $sourceRunRelatives = @($publishRunData.source_run_relatives | ForEach-Object { [string]$_ })
        $sourceLedgerHashes = @($publishRunData.source_ledger_sha256s | ForEach-Object { ([string]$_).ToUpperInvariant() })
        if ($sourceRunIds.Count -lt 1 -or $sourceRunRelatives.Count -ne $sourceRunIds.Count -or $sourceLedgerHashes.Count -ne $sourceRunIds.Count) { throw 'CORPUS_SOURCE_LINEAGE_INVALID' }
        $lineageRuns = [System.Collections.Generic.List[string]]::new()
        $lineageHashes = [System.Collections.Generic.List[string]]::new()
        $seenLineagePaths = @{}
        for ($lineageIndex = 0; $lineageIndex -lt $sourceRunIds.Count; $lineageIndex++) {
            $relative = $sourceRunRelatives[$lineageIndex]
            $entryRunId = $sourceRunIds[$lineageIndex]
            $entryHash = $sourceLedgerHashes[$lineageIndex]
            if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $entryHash -notmatch '^[A-F0-9]{64}$') { throw 'CORPUS_SOURCE_LINEAGE_INVALID' }
            $entryRun = [IO.Path]::GetFullPath((Join-Path $project $relative))
            if (-not $entryRun.StartsWith($allowedRunRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $seenLineagePaths.ContainsKey($entryRun.ToLowerInvariant())) { throw 'CORPUS_SOURCE_LINEAGE_PATH_INVALID' }
            $seenLineagePaths[$entryRun.ToLowerInvariant()] = $true
            $entryRunJson = Join-Path $entryRun 'run.json'
            $entryLedger = Join-Path $entryRun 'ledger.jsonl'
            foreach ($required in @($entryRunJson,$entryLedger)) { if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "CORPUS_SOURCE_LINEAGE_FILE_MISSING: $required" } }
            $entryRunData = Get-Content -LiteralPath $entryRunJson -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
            if ($entryRunId -ne $sourceRunIds[$lineageIndex] -or [string]$entryRunData.run_id -ne $entryRunId) { throw 'CORPUS_SOURCE_LINEAGE_RUN_ID_MISMATCH' }
            if ((Get-FileHash -LiteralPath $entryLedger -Algorithm SHA256).Hash -ne $entryHash) { throw 'CORPUS_SOURCE_LINEAGE_LEDGER_MISMATCH' }
            $lineageRuns.Add($entryRun)
            $lineageHashes.Add($entryHash)
        }
        $corpusCompiler = Join-Path $scriptRoot 'Compile-K1LiteV2Corpus.ps1'
        $regenerated = & $corpusCompiler -ProjectPath $project -RunDirectories $lineageRuns.ToArray() -ExpectedLedgerSha256s $lineageHashes.ToArray() -OutputDirectory $verificationDirectory -PythonPath $PythonPath -InternalHeldProjectLock $projectLock
        if ([string]$regenerated.LedgerSha256 -ne $ledgerHash) { throw 'CORPUS_DERIVATION_LEDGER_SHA_MISMATCH' }
        Assert-FilesByteIdentical $ledgerPath (Join-Path $verificationDirectory 'ledger.jsonl') 'CORPUS_DERIVATION_LEDGER_MISMATCH'
        Assert-AggregatePreviewsEquivalent $preview ([string]$regenerated.PreviewPath) 'CORPUS_DERIVATION_MISMATCH'
    } else {
        throw 'PUBLISH_RUN_TYPE_UNSUPPORTED'
    }
} finally {
    Remove-PublishVerificationDirectory $run $verificationDirectory
}
$metaPath = Join-Path $project 'meta.md'
$metaBefore = [IO.File]::ReadAllBytes($metaPath)
$metaBeforeSha = Get-Sha256HexFromBytes -Bytes $metaBefore
$metaText = [Text.Encoding]::UTF8.GetString($metaBefore)
$projectOrigin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $metaText
if ([string]$publishRunData.schema -ne 'K1_LITE_V2_RUN_V1' -and [string]$publishRunData.run_type -ne 'CORPUS_COMPILE') {
    throw 'PUBLISH_RUN_TYPE_UNSUPPORTED'
}
$publishLineage = @(Resolve-K1PublishLineage -ProjectPath $project -PublicationRunDirectory $run -PublicationRunData $publishRunData -ExpectedPublicationLedgerSha256 $ledgerHash)
Invoke-K1FreshLineageGates -EnginePath $engine -ProjectPath $project -Lineage $publishLineage -PythonPath $PythonPath | Out-Null
$publicationKind = if ([string]$publishRunData.schema -eq 'K1_LITE_V2_RUN_V1') { 'SINGLE' } else { 'CORPUS' }
$receiptPath = Join-Path $run 'publish-receipt.json'
$receiptExistedBefore = Test-Path -LiteralPath $receiptPath -PathType Leaf
$receiptPayload = New-K1PublishReceiptPayload `
    -PublicationKind $publicationKind -ProjectPath $project -PublicationRunDirectory $run -PublicationRunData $publishRunData `
    -PublicationLedgerPath $ledgerPath -PublicationLedgerSha256 $ledgerHash `
    -PreviewPath $preview -PreviewSha256 $ExpectedPreviewSha256 `
    -CanonicalPath $destination -CanonicalSha256 $ExpectedPreviewSha256 -Lineage $publishLineage
$receiptBytes = ConvertTo-K1PublishReceiptBytes $receiptPayload
$receiptSha = Get-K1PublishBytesSha256 $receiptBytes
$receiptRelative = Get-K1PublishRelativePath -ProjectPath $project -Path $receiptPath
$publishEngineVersion = [string]$publishRunData.engine_version
$metaText = Set-MetaField $metaText 'EVIDENCE_SCHEMA' 'MINIMAL_EVIDENCE_V4_PAGELOC'
$metaText = Set-MetaField $metaText 'K1_RESEARCH_MODE' 'K1_LITE_V2'
$metaText = Set-MetaField $metaText 'K1_ENGINE_VERSION' $publishEngineVersion
$metaText = Set-MetaField $metaText 'K1_RUN_PATH' (Get-RelativeUnix $project $run)
$metaText = Set-MetaField $metaText 'K1_LEDGER_SHA256' $ledgerHash
$metaText = Set-MetaField $metaText 'K1_PUBLISH_RECEIPT_PATH' $receiptRelative
$metaText = Set-MetaField $metaText 'K1_PUBLISH_RECEIPT_SHA256' $receiptSha
$metaText = Set-MetaField $metaText 'K1_MANUAL_REASON' 'BRAK'
$created = $false
$recoveredOrReused = $false
$receiptAttempted = $false
$metaWritten = $false
$canonicalTemp = Join-Path $project ('.k1-publish-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    if ((Get-FileHash -LiteralPath $ledgerPath -Algorithm SHA256).Hash -ne $ledgerHash) { throw 'LEDGER_CHANGED_BEFORE_PUBLISH' }
    if ((Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash -ne $ExpectedPreviewSha256.ToUpperInvariant()) { throw 'PREVIEW_CHANGED_BEFORE_PUBLISH' }
    if ((Get-FileHash -LiteralPath $runPath -Algorithm SHA256).Hash -ne [string]$receiptPayload.publication_run_json_sha256) { throw 'RUN_JSON_CHANGED_BEFORE_PUBLISH' }
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        Assert-SystemV7PathNoReparse -Path $destination -ContainmentRoot $project | Out-Null
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $ExpectedPreviewSha256.ToUpperInvariant()) {
            throw 'CANONICAL_EVIDENCE_CHANGED_BEFORE_PUBLISH'
        }
        $recoveredOrReused = $true
    } else {
        if (Test-Path -LiteralPath $destination) { throw 'CANONICAL_EVIDENCE_PATH_INVALID' }
        $input = [IO.File]::OpenRead($preview)
        try {
            $output = [IO.File]::Open($canonicalTemp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($output); $output.Flush($true) } finally { $output.Dispose() }
        } finally { $input.Dispose() }
        [IO.File]::Move($canonicalTemp, $destination)
        $created = $true
    }
    Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text $metaText -ExpectedCurrentSha256 $metaBeforeSha -HeldLockStream $projectLock
    $metaWritten = $true
    $final = & $validator -ProjectPath $project -NoExit
    if ($final.Errors -gt 0 -or -not $final.GateReady) { throw "CANONICAL_VALIDATION_FAIL: $($final.ErrorDetails -join '; ')" }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $ExpectedPreviewSha256.ToUpperInvariant()) { throw 'CANONICAL_SHA_CHANGED_BEFORE_RECEIPT' }
    $receiptAttempted = $true
    $writtenReceipt = Write-K1PublishReceiptCreateNew -ProjectPath $project -PublicationRunDirectory $run -Bytes $receiptBytes -ExpectedSha256 $receiptSha
    $receiptState = Assert-K1PublishReceiptCurrent -ProjectPath $project -ReceiptRelative $receiptRelative -ExpectedReceiptSha256 $receiptSha
    [pscustomobject]@{
        Status=$(if ($recoveredOrReused) { 'PUBLISHED_RECOVERED_OR_REUSED' } else { 'PUBLISHED_CREATE_NEW' }); Destination=$destination; Sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        LedgerSha256=$ledgerHash; Cards=$final.Cards; PublishReceipt=$writtenReceipt.Path; PublishReceiptSha256=$receiptState.Sha256
    }
} catch {
    $rollbackOwned = $false
    if ($metaWritten) {
        $publishedMetaSha = Get-Sha256HexFromText -Text $metaText
        if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -eq $publishedMetaSha) {
            Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text ([Text.UTF8Encoding]::new($false).GetString($metaBefore)) -ExpectedCurrentSha256 $publishedMetaSha -HeldLockStream $projectLock
            $rollbackOwned = $true
        }
    } elseif ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -eq $metaBeforeSha) {
        $rollbackOwned = $true
    }
    if ($rollbackOwned -and $receiptAttempted -and -not $receiptExistedBefore -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { [IO.File]::Delete($receiptPath) }
    if ($rollbackOwned -and $created -and (Test-Path -LiteralPath $destination -PathType Leaf) -and
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $ExpectedPreviewSha256.ToUpperInvariant()) {
        [IO.File]::Delete($destination)
    }
    if (Test-Path -LiteralPath $canonicalTemp -PathType Leaf) { [IO.File]::Delete($canonicalTemp) }
    throw
}
} finally {
    if ($ownsProjectLock) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
}
