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
    [string]$ExpectedCanonicalSha256,
    [string]$PythonPath = 'python.exe',
    [switch]$InternalRecoveryPreview,
    [string]$InternalBaseCanonicalPath,
    [string]$InternalExpectedBaseCanonicalSha256,
    [string]$InternalBaseReceiptRelative,
    [string]$InternalBaseReceiptSha256,
    [string]$InternalSupersededCanonicalSha256,
    [IO.FileStream]$InternalHeldProjectLock
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$run = [IO.Path]::GetFullPath($RunDirectory)
$allowedRunRoot = [IO.Path]::GetFullPath((Join-Path $project '_work\K1\k1-lite-v2'))
if (-not $run.StartsWith($allowedRunRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'RUN_OUTSIDE_PROJECT' }
foreach ($value in @($ExpectedLedgerSha256)) {
    if ($value -notmatch '^[A-Fa-f0-9]{64}$') { throw 'EXPECTED_LEDGER_SHA_INVALID' }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot 'Project-Origin.ps1')
. (Join-Path $scriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $scriptRoot 'Narrative-V2.ps1')
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project -SystemRoot (Split-Path -Parent $scriptRoot) | Out-Null
if ($null -ne $InternalHeldProjectLock) {
    $callerPathForLock = if ($MyInvocation.ScriptName) { [IO.Path]::GetFullPath($MyInvocation.ScriptName) } else { '' }
    $selfPathForLock = [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
    if (-not $callerPathForLock.Equals($selfPathForLock, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'INTERNAL_HELD_PROJECT_LOCK_UNAUTHORIZED'
    }
}
$authorizationMetaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $authorizationMetaPath -PathType Leaf)) { throw "META_MISSING: $authorizationMetaPath" }
$authorizationMeta = Get-Content -LiteralPath $authorizationMetaPath -Raw -Encoding UTF8
$originAuthorization = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $authorizationMeta
$authorizationStage = Get-SystemV7SingleMetaField -Text $authorizationMeta -Name 'CURRENT_STAGE'
if ($authorizationStage -cne 'K2B') { throw "K1_SUPPLEMENT_STAGE_UNAUTHORIZED: stage=$authorizationStage expected=K2B" }
$ownsProjectLock = $null -eq $InternalHeldProjectLock
$projectLock = if ($ownsProjectLock) { Enter-SystemV7ProjectMetaLock -ProjectPath $project } else { $InternalHeldProjectLock }
try {
$compiler = Join-Path $scriptRoot 'Compile-K1LiteV2.ps1'
$validator = Join-Path $scriptRoot 'Validate-EvidenceBase.ps1'
$engine = Join-Path $scriptRoot 'k1-lite-v2\Invoke-K1LiteV2.ps1'
$publishIntegrity = Join-Path $scriptRoot 'K1-PublishIntegrity.ps1'
$canonical = Join-Path $project '01-baza-dowodow.md'
$metaPath = Join-Path $project 'meta.md'
$ledger = Join-Path $run 'ledger.jsonl'
$runJson = Join-Path $run 'run.json'
foreach ($required in @($compiler,$validator,$engine,$publishIntegrity,$canonical,$metaPath,$ledger,$runJson)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "REQUIRED_FILE_MISSING: $required" }
}
. $publishIntegrity
$internalRecoveryValues = @(
    $InternalBaseCanonicalPath,
    $InternalExpectedBaseCanonicalSha256,
    $InternalBaseReceiptRelative,
    $InternalBaseReceiptSha256,
    $InternalSupersededCanonicalSha256
)
$internalRecoveryRequested = $InternalRecoveryPreview -or @($internalRecoveryValues | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0
$previewBaseCanonical = $canonical
if ($internalRecoveryRequested) {
    $selfPath = [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
    $callerPath = if ($MyInvocation.ScriptName) { [IO.Path]::GetFullPath($MyInvocation.ScriptName) } else { '' }
    if (-not $InternalRecoveryPreview -or $Action -ne 'Preview' -or -not $callerPath.Equals($selfPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'INTERNAL_RECOVERY_PREVIEW_UNAUTHORIZED'
    }
    foreach ($requiredInternalValue in $internalRecoveryValues) {
        if ([string]::IsNullOrWhiteSpace([string]$requiredInternalValue)) { throw 'INTERNAL_RECOVERY_PREVIEW_ARGUMENT_MISSING' }
    }
    foreach ($internalSha in @($InternalExpectedBaseCanonicalSha256,$InternalBaseReceiptSha256,$InternalSupersededCanonicalSha256)) {
        if ($internalSha -notmatch '^[A-Fa-f0-9]{64}$') { throw 'INTERNAL_RECOVERY_PREVIEW_SHA_INVALID' }
    }
    $previewBaseCanonical = [IO.Path]::GetFullPath($InternalBaseCanonicalPath)
    $expectedInternalBackupName = "canonical-before-supplement-$($InternalExpectedBaseCanonicalSha256.ToUpperInvariant()).md"
    if (-not $previewBaseCanonical.StartsWith($run.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($previewBaseCanonical) -cne $expectedInternalBackupName -or
        -not (Test-Path -LiteralPath $previewBaseCanonical -PathType Leaf)) {
        throw 'INTERNAL_RECOVERY_BASE_CANONICAL_PATH_INVALID'
    }
    Assert-SystemV7PathNoReparse -Path $previewBaseCanonical -ContainmentRoot $project | Out-Null
    if ((Get-FileHash -LiteralPath $previewBaseCanonical -Algorithm SHA256).Hash -ne $InternalExpectedBaseCanonicalSha256.ToUpperInvariant()) {
        throw 'INTERNAL_RECOVERY_BASE_CANONICAL_SHA_MISMATCH'
    }
    if ((Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash -ne $InternalSupersededCanonicalSha256.ToUpperInvariant()) {
        throw 'INTERNAL_RECOVERY_SUPERSEDED_CANONICAL_SHA_MISMATCH'
    }
}
$projectMeta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$projectOrigin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $projectMeta
$lockedStage = Get-SystemV7SingleMetaField -Text $projectMeta -Name 'CURRENT_STAGE'
if ($lockedStage -cne 'K2B') { throw "K1_SUPPLEMENT_STAGE_UNAUTHORIZED: stage=$lockedStage expected=K2B" }
Assert-SystemV7PathNoReparse -Path $allowedRunRoot -ContainmentRoot $project | Out-Null
Assert-SystemV7TreeNoReparse -RootPath $run -ContainmentRoot $project | Out-Null
foreach ($projectFile in @($canonical,$metaPath,$ledger,$runJson)) {
    Assert-SystemV7PathNoReparse -Path $projectFile -ContainmentRoot $project | Out-Null
}
$ledgerHash = (Get-FileHash -LiteralPath $ledger -Algorithm SHA256).Hash
if ($ledgerHash -ne $ExpectedLedgerSha256.ToUpperInvariant()) { throw 'LEDGER_SHA_MISMATCH' }

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

function Set-MetaField([string]$Text, [string]$Name, [string]$Value) {
    $pattern = "(?m)^$([regex]::Escape($Name)):\s*.*$"
    if ([regex]::IsMatch($Text, $pattern)) {
        $literal = "${Name}: $Value"
        return [regex]::Replace($Text, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $literal }, 1)
    }
    throw "META_FIELD_MISSING: $Name"
}

function Get-FieldValue([string]$Text, [string]$Name) {
    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-PublishVerificationDirectory([string]$TargetRun) {
    $target = [IO.Path]::GetFullPath((Join-Path $TargetRun ('.publish-verify-' + [guid]::NewGuid().ToString('N'))))
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

function Assert-StringArraysEqual([object[]]$Expected, [object[]]$Actual, [string]$ErrorCode) {
    if ($Expected.Count -ne $Actual.Count) { throw $ErrorCode }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ([string]$Expected[$index] -cne [string]$Actual[$index]) { throw $ErrorCode }
    }
}

function ConvertFrom-SourceRow([string]$Line) {
    $cells = @($Line -split '(?<!\\)\|')
    if ($cells.Count -lt 12) { throw "SOURCE_ROW_INVALID: $Line" }
    [pscustomobject]@{
        Cells = $cells
        Id = $cells[1].Trim().TrimStart('#')
        Hash = $cells[8].Trim().ToUpperInvariant()
    }
}

function ConvertTo-SourceRow([object]$Row) {
    ($Row.Cells -join '|')
}

function ConvertFrom-CoverageRow([string]$Line) {
    $cells = @($Line -split '(?<!\\)\|')
    if ($cells.Count -lt 6) { throw "COVERAGE_ROW_INVALID: $Line" }
    $goal = $cells[1].Trim()
    $status = $cells[2].Trim()
    if ($goal -notmatch '^Q-\d{3,}$' -or $status -notin @('POKRYTY','LUKA JAWNA','POZA ZAKRESEM')) {
        throw "COVERAGE_ROW_INVALID: $Line"
    }
    $references = @([regex]::Matches($cells[3], '#P-\d{3,}') | ForEach-Object { $_.Value } | Select-Object -Unique)
    [pscustomobject]@{
        Cells = $cells
        Goal = $goal
        Status = $status
        References = $references
    }
}

function ConvertTo-CoverageRow([object]$Row) {
    ($Row.Cells -join '|')
}

function Get-CardRecords([string]$Text) {
    $records = [System.Collections.Generic.List[object]]::new()
    $pattern = '(?ms)^### #P-(?<id>\d{3,})\r?\n\r?\n(?<body>.*?)(?=^### #P-|^## 4\.)'
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        $body = $match.Groups['body'].Value.TrimEnd()
        $source = [regex]::Match($body, '(?m)^ŹRÓDŁO_ID:\s*#(?<id>S-\d{3,})\s*$').Groups['id'].Value
        $locator = [regex]::Match($body, '(?m)^LOKALIZACJA:\s*(?<v>.+?)\s*$').Groups['v'].Value.Trim()
        $content = [regex]::Match($body, '(?m)^TREŚĆ:\s*(?<v>.+?)\s*$').Groups['v'].Value.Trim()
        if (-not $source -or -not $locator -or -not $content) { throw "CARD_INVALID: #P-$($match.Groups['id'].Value)" }
        $records.Add([pscustomobject]@{ Id=[int]$match.Groups['id'].Value; Source=$source; Locator=$locator; Content=$content; Body=$body })
    }
    return @($records)
}

if ($Action -eq 'Preview') {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { throw 'OUTPUT_DIRECTORY_REQUIRED' }
    $output = [IO.Path]::GetFullPath($OutputDirectory)
    if (-not $output.StartsWith($run.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'OUTPUT_OUTSIDE_RUN' }
    if (Test-Path -LiteralPath $output) { throw 'OUTPUT_EXISTS' }

    $baseValidation = & $validator -ProjectPath $project -NoExit
    $baseBlockingErrors = @($baseValidation.ErrorDetails | Where-Object { $_ -notmatch '^Nierozliczony plik sources/:' })
    $baseGateWarnings = @($baseValidation.WarningDetails | Where-Object { $_ -match '^(STRUCTURE_CHECK|SOURCE_FIDELITY_CHECK|SATURATION_CHECK|K1_VERDICT)' })
    if ($baseValidation.Schema -ne 'MINIMAL_EVIDENCE_V4_PAGELOC' -or $baseValidation.ManualCheckCards -ne 0 -or $baseBlockingErrors.Count -gt 0 -or $baseGateWarnings.Count -gt 0) {
        throw "CANONICAL_NOT_GATE_READY: $($baseValidation.ErrorDetails -join '; ')"
    }
    $baseMetaText = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $baseReceiptRelative = if ($InternalRecoveryPreview) { $InternalBaseReceiptRelative } else { Get-FieldValue $baseMetaText 'K1_PUBLISH_RECEIPT_PATH' }
    $baseReceiptSha = if ($InternalRecoveryPreview) { $InternalBaseReceiptSha256 } else { Get-FieldValue $baseMetaText 'K1_PUBLISH_RECEIPT_SHA256' }
    $baseReceiptState = if ($InternalRecoveryPreview) {
        Assert-K1PublishReceiptCurrent -ProjectPath $project -ReceiptRelative $baseReceiptRelative -ExpectedReceiptSha256 $baseReceiptSha -AllowCanonicalSupersededBySha256 $InternalSupersededCanonicalSha256
    } else {
        Assert-K1PublishReceiptCurrent -ProjectPath $project -ReceiptRelative $baseReceiptRelative -ExpectedReceiptSha256 $baseReceiptSha
    }
    Invoke-K1FreshLineageGates -EnginePath $engine -ProjectPath $project -Lineage @($baseReceiptState.Lineage) -PythonPath $PythonPath | Out-Null

    $runJsonText = Get-Content -LiteralPath $runJson -Raw -Encoding UTF8
    $runData = $runJsonText | ConvertFrom-Json -DateKind String
    if ([string]$runData.engine_version -ne '2.1.0') { throw "RUN_ENGINE_VERSION_UNSUPPORTED: $($runData.engine_version)" }
    $supplementDate = Get-RunCreatedUtcDateFromJson $runJsonText
    $coveredByRun = @{}
    foreach ($relative in @([string]$runData.source_relative, [string]$runData.pdf_relative)) {
        if ($relative) {
            $coveredPath = [IO.Path]::GetFullPath((Join-Path $project $relative))
            $coveredByRun[$coveredPath.ToLowerInvariant()] = $true
        }
    }
    $unanalysedSupplementFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($errorText in @($baseValidation.ErrorDetails | Where-Object { $_ -match '^Nierozliczony plik sources/:' })) {
        $match = [regex]::Match([string]$errorText, '^Nierozliczony plik sources/:\s*(?<path>.+?)(?:\. Rozlicz go.*)?$')
        if (-not $match.Success) { throw "UNACCOUNTED_SOURCE_ERROR_UNPARSEABLE: $errorText" }
        $unaccountedPath = [IO.Path]::GetFullPath($match.Groups['path'].Value)
        if (-not $coveredByRun.ContainsKey($unaccountedPath.ToLowerInvariant())) { $unanalysedSupplementFiles.Add($unaccountedPath) }
    }
    if ($unanalysedSupplementFiles.Count -gt 0) {
        throw "SUPPLEMENT_UNANALYSED_FILES: $($unanalysedSupplementFiles -join '; ')"
    }

    $rawDirectory = Join-Path $output '_standalone'
    $standalone = & $compiler -Action Preview -ProjectPath $project -RunDirectory $run -ExpectedLedgerSha256 $ledgerHash -OutputDirectory $rawDirectory -PythonPath $PythonPath -InternalAllowCorpusSubset -InternalHeldProjectLock $projectLock
    $baseText = Get-Content -LiteralPath $previewBaseCanonical -Raw -Encoding UTF8
    $baseCutoffDate = Get-FieldValue $baseText 'DATA_ODCIĘCIA'
    $parsedBaseCutoff = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($baseCutoffDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedBaseCutoff)) {
        throw 'BASE_CUTOFF_DATE_INVALID'
    }
    $aggregateCutoffDate = if ([string]::CompareOrdinal($baseCutoffDate, $supplementDate) -ge 0) { $baseCutoffDate } else { $supplementDate }
    $newText = Get-Content -LiteralPath $standalone.PreviewPath -Raw -Encoding UTF8
    $baseLines = @($baseText -split '\r?\n')
    $newLines = @($newText -split '\r?\n')
    $baseCoverageByGoal = @{}
    $newCoverageByGoal = @{}
    for ($lineIndex = 0; $lineIndex -lt $baseLines.Count; $lineIndex++) {
        if ($baseLines[$lineIndex] -notmatch '^\|\s*Q-\d{3,}\s*\|') { continue }
        $coverage = ConvertFrom-CoverageRow $baseLines[$lineIndex]
        if ($baseCoverageByGoal.ContainsKey($coverage.Goal)) { throw "BASE_COVERAGE_GOAL_DUPLICATE: $($coverage.Goal)" }
        $baseCoverageByGoal[$coverage.Goal] = [pscustomobject]@{ LineIndex=$lineIndex; Row=$coverage }
    }
    for ($lineIndex = 0; $lineIndex -lt $newLines.Count; $lineIndex++) {
        if ($newLines[$lineIndex] -notmatch '^\|\s*Q-\d{3,}\s*\|') { continue }
        $coverage = ConvertFrom-CoverageRow $newLines[$lineIndex]
        if ($newCoverageByGoal.ContainsKey($coverage.Goal)) { throw "SUPPLEMENT_COVERAGE_GOAL_DUPLICATE: $($coverage.Goal)" }
        $newCoverageByGoal[$coverage.Goal] = $coverage
    }
    if ($baseCoverageByGoal.Count -eq 0 -or $newCoverageByGoal.Count -ne $baseCoverageByGoal.Count) {
        throw 'SUPPLEMENT_COVERAGE_GOAL_SET_MISMATCH'
    }
    foreach ($goal in $baseCoverageByGoal.Keys) {
        if (-not $newCoverageByGoal.ContainsKey($goal)) { throw "SUPPLEMENT_COVERAGE_GOAL_MISSING: $goal" }
    }
    $baseRows = [System.Collections.Generic.List[object]]::new()
    $newRows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in $baseLines) { if ($line -match '^\| #S-\d{3,}\s+\|') { $baseRows.Add((ConvertFrom-SourceRow $line)) } }
    foreach ($line in $newLines) { if ($line -match '^\| #S-\d{3,}\s+\|') { $newRows.Add((ConvertFrom-SourceRow $line)) } }
    if ($baseRows.Count -eq 0 -or $newRows.Count -eq 0) { throw 'SOURCE_REGISTRY_MISSING' }

    $sourceMap = @{}
    $byKey = @{}
    $maxSource = 0
    foreach ($row in $baseRows) {
        $key = $row.Cells[2].Trim().ToLowerInvariant() + '|' + $row.Hash
        $byKey[$key] = $row
        $maxSource = [Math]::Max($maxSource, [int]($row.Id -replace '^S-',''))
    }
    foreach ($row in $newRows) {
        $originalId = $row.Id
        $key = $row.Cells[2].Trim().ToLowerInvariant() + '|' + $row.Hash
        if ($byKey.ContainsKey($key)) {
            $existing = $byKey[$key]
            if ($row.Cells[6].Trim() -eq 'RDZEŃ' -and $existing.Cells[6].Trim() -notin @('RDZEŃ','CELOWE')) {
                $existing.Cells[5] = $row.Cells[5]
                $existing.Cells[6] = ' RDZEŃ '
                $existing.Cells[7] = $row.Cells[7]
                $existing.Cells[10] = ' awansowano po pełnym runie K1-Lite V2 '
            }
            $sourceMap[$originalId] = $existing.Id
        } else {
            $maxSource++
            $newId = 'S-{0:D3}' -f $maxSource
            $row.Cells[1] = " #$newId "
            $row.Cells[9] = ' — '
            $row.Id = $newId
            $baseRows.Add($row)
            $byKey[$key] = $row
            $sourceMap[$originalId] = $newId
        }
    }

    $baseCards = @(Get-CardRecords $baseText)
    $incomingCards = @(Get-CardRecords $newText)
    $maxCard = if ($baseCards.Count) { ($baseCards | Measure-Object -Property Id -Maximum).Maximum } else { 0 }
    $existingCardIdByKey = @{}
    foreach ($card in $baseCards) {
        $key = "$($card.Source)|$($card.Locator)|$($card.Content)"
        if (-not $existingCardIdByKey.ContainsKey($key)) { $existingCardIdByKey[$key] = [int]$card.Id }
    }
    $incomingCardIdMap = @{}
    $added = [System.Collections.Generic.List[object]]::new()
    foreach ($card in $incomingCards) {
        $incomingCardId = [int]$card.Id
        if ($incomingCardIdMap.ContainsKey($incomingCardId)) { throw "SUPPLEMENT_CARD_ID_DUPLICATE: #P-$('{0:D3}' -f $incomingCardId)" }
        $mappedSource = $sourceMap[$card.Source]
        if (-not $mappedSource) { throw "SOURCE_REMAP_MISSING: $($card.Source)" }
        $key = "$mappedSource|$($card.Locator)|$($card.Content)"
        if ($existingCardIdByKey.ContainsKey($key)) {
            $incomingCardIdMap[$incomingCardId] = [int]$existingCardIdByKey[$key]
            continue
        }
        $maxCard++
        $body = [regex]::Replace($card.Body, '(?m)^ŹRÓDŁO_ID:\s*#S-\d{3,}\s*$', "ŹRÓDŁO_ID: #$mappedSource")
        $added.Add([pscustomobject]@{ Id=$maxCard; Source=$mappedSource; Body=$body })
        $incomingCardIdMap[$incomingCardId] = [int]$maxCard
        $existingCardIdByKey[$key] = [int]$maxCard
    }
    if ($added.Count -eq 0) { throw 'SUPPLEMENT_NO_NEW_UNIQUE_CARDS' }

    foreach ($goal in @($newCoverageByGoal.Keys | Sort-Object)) {
        $incomingCoverage = $newCoverageByGoal[$goal]
        if ($incomingCoverage.Status -ne 'POKRYTY') { continue }
        $baseCoverageEntry = $baseCoverageByGoal[$goal]
        $baseCoverage = $baseCoverageEntry.Row
        if ($baseCoverage.Status -eq 'POZA ZAKRESEM') { throw "SUPPLEMENT_COVERAGE_SCOPE_CONFLICT: $goal" }
        $mergedReferences = [System.Collections.Generic.List[string]]::new()
        foreach ($reference in @($baseCoverage.References)) {
            if (-not $mergedReferences.Contains($reference)) { $mergedReferences.Add($reference) }
        }
        foreach ($reference in @($incomingCoverage.References)) {
            $incomingCardId = [int]($reference -replace '^#P-','')
            if (-not $incomingCardIdMap.ContainsKey($incomingCardId)) { throw "SUPPLEMENT_COVERAGE_CARD_REMAP_MISSING: $goal/$reference" }
            $mappedReference = '#P-{0:D3}' -f ([int]$incomingCardIdMap[$incomingCardId])
            if (-not $mergedReferences.Contains($mappedReference)) { $mergedReferences.Add($mappedReference) }
        }
        if ($mergedReferences.Count -eq 0) { throw "SUPPLEMENT_COVERAGE_REFERENCES_MISSING: $goal" }
        $wasCovered = $baseCoverage.Status -eq 'POKRYTY'
        $baseCoverage.Cells[2] = ' POKRYTY '
        $baseCoverage.Cells[3] = " $($mergedReferences -join ', ') "
        if (-not $wasCovered) { $baseCoverage.Cells[4] = $incomingCoverage.Cells[4] }
        $baseLines[$baseCoverageEntry.LineIndex] = ConvertTo-CoverageRow $baseCoverage
    }

    foreach ($row in $baseRows) {
        $newIds = @($added | Where-Object Source -eq $row.Id | ForEach-Object { '#P-{0:D3}' -f ([int]$_.Id) })
        if ($newIds.Count) {
            $current = $row.Cells[9].Trim()
            $row.Cells[9] = if ($current -and $current -ne '—') { " $current, $($newIds -join ', ') " } else { " $($newIds -join ', ') " }
        }
    }

    $firstRow = -1; $cardHeader = -1; $changeHeader = -1
    for ($i=0; $i -lt $baseLines.Count; $i++) {
        if ($firstRow -lt 0 -and $baseLines[$i] -match '^\| #S-\d{3,}\s+\|') { $firstRow = $i }
        if ($baseLines[$i] -eq '## 3. Karty dowodowe') { $cardHeader = $i }
        if ($baseLines[$i] -eq '## 4. Changelog') { $changeHeader = $i }
    }
    if ($firstRow -lt 0 -or $cardHeader -lt 0 -or $changeHeader -lt 0) { throw 'CANONICAL_SECTIONS_INVALID' }

    $runData = Get-Content -LiteralPath $runJson -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    $engineVersion = [string]$runData.engine_version
    $hasLocatorPolicy = [bool]($baseLines | Where-Object { $_ -match '^LOCATOR_POLICY:' } | Select-Object -First 1)

    # Eksport suplementu musi zachować ledger bazowy oraz dołączyć nowy run.
    $baseExportValue = Get-FieldValue $baseText 'K1_EXPORT_PATH'
    $baseExportHash = Get-FieldValue $baseText 'K1_EXPORT_SHA256'
    if ([string]::IsNullOrWhiteSpace($baseExportValue) -or $baseExportHash -notmatch '^[A-Fa-f0-9]{64}$') { throw 'BASE_EXPORT_LEDGER_INVALID' }
    $baseLedger = if ([IO.Path]::IsPathRooted($baseExportValue)) { [IO.Path]::GetFullPath($baseExportValue) } else { [IO.Path]::GetFullPath((Join-Path $project $baseExportValue)) }
    if (-not $baseLedger.StartsWith($allowedRunRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $baseLedger -PathType Leaf)) { throw 'BASE_EXPORT_LEDGER_OUTSIDE_RUN_ROOT_OR_MISSING' }
    if ((Get-FileHash -LiteralPath $baseLedger -Algorithm SHA256).Hash -ne $baseExportHash.ToUpperInvariant()) { throw 'BASE_EXPORT_LEDGER_SHA_MISMATCH' }
    $baseLedgerLines = @(Get-Content -LiteralPath $baseLedger -Encoding UTF8 | Where-Object { $_.Trim() })
    $newLedgerLines = @(Get-Content -LiteralPath $ledger -Encoding UTF8 | Where-Object { $_.Trim() })
    $baseRunIds = @($baseLedgerLines | ForEach-Object { ($_ | ConvertFrom-Json -DateKind String).run_id } | Where-Object { $_ } | Select-Object -Unique)
    if ($baseRunIds.Count -lt 1) { throw 'BASE_EXPORT_RUNS_MISSING' }
    $supplementExistingIndex = -1
    for ($baseRunIndex = 0; $baseRunIndex -lt $baseRunIds.Count; $baseRunIndex++) {
        if ([string]$baseRunIds[$baseRunIndex] -ceq [string]$runData.run_id) { $supplementExistingIndex = $baseRunIndex; break }
    }
    $supplementMode = if ($supplementExistingIndex -ge 0) { 'APPEND_EXISTING' } else { 'ADD_RUN' }

    $baseRunDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $baseLedger))
    $baseRunJson = Join-Path $baseRunDirectory 'run.json'
    if (-not (Test-Path -LiteralPath $baseRunJson -PathType Leaf)) { throw 'BASE_EXPORT_RUN_JSON_MISSING' }
    $baseRunData = Get-Content -LiteralPath $baseRunJson -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    $baseRunRelatives = @()
    $baseLedgerHashes = @()
    if ([string]$baseRunData.schema -eq 'K1_LITE_V2_RUN_V1') {
        if ($baseRunIds.Count -ne 1 -or [string]$baseRunData.run_id -ne [string]$baseRunIds[0] -or -not $baseLedger.Equals([IO.Path]::GetFullPath((Join-Path $baseRunDirectory 'ledger.jsonl')), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'BASE_SINGLE_RUN_LINEAGE_INVALID'
        }
        $baseRunRelatives = @(Get-RelativeUnix $project $baseRunDirectory)
        $baseLedgerHashes = @($baseExportHash.ToUpperInvariant())
    } elseif ([string]$baseRunData.run_type -in @('CORPUS_COMPILE','SUPPLEMENT_AGGREGATE')) {
        $declaredBaseIds = @($baseRunData.source_runs | ForEach-Object { [string]$_ })
        $baseRunRelatives = @($baseRunData.source_run_relatives | ForEach-Object { [string]$_ })
        $baseLedgerHashes = @($baseRunData.source_ledger_sha256s | ForEach-Object { ([string]$_).ToUpperInvariant() })
        Assert-StringArraysEqual $baseRunIds $declaredBaseIds 'BASE_AGGREGATE_RUN_IDS_MISMATCH'
        if ($baseRunRelatives.Count -ne $baseRunIds.Count -or $baseLedgerHashes.Count -ne $baseRunIds.Count) { throw 'BASE_AGGREGATE_LINEAGE_INVALID' }
    } else {
        throw 'BASE_EXPORT_RUN_TYPE_UNSUPPORTED'
    }
    $seenBaseRunPaths = @{}
    $currentBaseLedgerHashes = [System.Collections.Generic.List[string]]::new()
    $currentBaseLedgerLines = [System.Collections.Generic.List[string]]::new()
    for ($baseIndex = 0; $baseIndex -lt $baseRunIds.Count; $baseIndex++) {
        $baseRelative = $baseRunRelatives[$baseIndex]
        $baseSourceHash = $baseLedgerHashes[$baseIndex]
        if ([string]::IsNullOrWhiteSpace($baseRelative) -or [IO.Path]::IsPathRooted($baseRelative) -or $baseSourceHash -notmatch '^[A-F0-9]{64}$') { throw 'BASE_AGGREGATE_LINEAGE_INVALID' }
        $baseSourceRun = [IO.Path]::GetFullPath((Join-Path $project $baseRelative))
        if (-not $baseSourceRun.StartsWith($allowedRunRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $seenBaseRunPaths.ContainsKey($baseSourceRun.ToLowerInvariant())) { throw 'BASE_AGGREGATE_LINEAGE_PATH_INVALID' }
        $seenBaseRunPaths[$baseSourceRun.ToLowerInvariant()] = $true
        $baseSourceRunJson = Join-Path $baseSourceRun 'run.json'
        $baseSourceLedger = Join-Path $baseSourceRun 'ledger.jsonl'
        foreach ($required in @($baseSourceRunJson,$baseSourceLedger)) { if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "BASE_AGGREGATE_LINEAGE_FILE_MISSING: $required" } }
        $baseSourceRunData = Get-Content -LiteralPath $baseSourceRunJson -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
        if ([string]$baseSourceRunData.run_id -ne [string]$baseRunIds[$baseIndex]) { throw 'BASE_AGGREGATE_LINEAGE_RUN_ID_MISMATCH' }
        $baseLedgerHistory = Get-K1PublishLedgerHistoryState -Path $baseSourceLedger -ExpectedSha256 $baseSourceHash
        if ($null -eq $baseLedgerHistory) { throw 'BASE_AGGREGATE_LINEAGE_LEDGER_MISMATCH' }
        $currentBaseLedgerHashes.Add([string]$baseLedgerHistory.ActualSha256)
        foreach ($currentLine in Get-Content -LiteralPath $baseSourceLedger -Encoding UTF8) {
            if ($currentLine.Trim()) { $currentBaseLedgerLines.Add($currentLine) }
        }
    }
    # Każda nowa publikacja zamyka świeżą linię pochodzenia: historyczne
    # hashe wolno wykorzystać wyłącznie do udowodnienia identycznego prefiksu,
    # natomiast nowy aggregate zapisuje już pełne, aktualne hashe.
    $baseLedgerHashes = @($currentBaseLedgerHashes.ToArray())
    $newRunRelative = Get-RelativeUnix $project $run
    if ($supplementMode -eq 'ADD_RUN' -and $seenBaseRunPaths.ContainsKey($run.ToLowerInvariant())) { throw 'SUPPLEMENT_RUN_PATH_ALREADY_IN_EXPORT' }
    if ($supplementMode -eq 'APPEND_EXISTING') {
        if (-not $seenBaseRunPaths.ContainsKey($run.ToLowerInvariant()) -or
            [string]$baseLedgerHashes[$supplementExistingIndex] -ne $ledgerHash -or
            $added.Count -lt 1) {
            throw 'SUPPLEMENT_EXISTING_RUN_NOT_APPEND_ONLY_EXTENSION'
        }
        # Hash może być już świeży, jeżeli wcześniejszy suplement odświeżył
        # pełną lineage całego batcha. Bezpieczeństwo zapewniają: identyczna
        # tożsamość run/path/hash, wcześniejsza kontrola historycznego prefiksu
        # oraz co najmniej jedna nowa unikalna karta względem canonical.
    }
    $aggregateSourceRuns = if ($supplementMode -eq 'APPEND_EXISTING') { @($baseRunIds) } else { @($baseRunIds + [string]$runData.run_id) }
    $aggregateSourceRunRelatives = if ($supplementMode -eq 'APPEND_EXISTING') { @($baseRunRelatives) } else { @($baseRunRelatives + $newRunRelative) }
    $aggregateSourceLedgerHashes = if ($supplementMode -eq 'APPEND_EXISTING') { @($baseLedgerHashes) } else { @($baseLedgerHashes + $ledgerHash) }
    $aggregateLedgerLines = if ($supplementMode -eq 'APPEND_EXISTING') { @($currentBaseLedgerLines.ToArray()) } else { @($currentBaseLedgerLines.ToArray() + $newLedgerLines) }
    $aggregateLedger = Join-Path $output 'ledger.jsonl'
    [IO.File]::WriteAllText($aggregateLedger, (($aggregateLedgerLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    $aggregateLedgerHash = (Get-FileHash -LiteralPath $aggregateLedger -Algorithm SHA256).Hash
    $aggregateRunId = 'supplement-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $canonicalBeforeHash = (Get-FileHash -LiteralPath $previewBaseCanonical -Algorithm SHA256).Hash
    $backupName = "canonical-before-supplement-$canonicalBeforeHash.md"
    $aggregateBackup = Join-Path $output $backupName
    Write-BytesCreateNewAtomic -Path $aggregateBackup -Bytes ([IO.File]::ReadAllBytes($previewBaseCanonical))
    $aggregateRun = [ordered]@{
        run_id = $aggregateRunId; run_type = 'SUPPLEMENT_AGGREGATE'; engine_version = $engineVersion
        locator_policy = 'MIXED_V1'; source_runs = $aggregateSourceRuns
        source_run_relatives = $aggregateSourceRunRelatives
        source_ledger_sha256s = $aggregateSourceLedgerHashes
        ledger_sha256 = $aggregateLedgerHash; supplement_source_run = [string]$runData.run_id
        supplement_mode = $supplementMode
        canonical_backup_relative = $backupName; canonical_backup_sha256 = $canonicalBeforeHash
        base_publish_receipt_relative = $baseReceiptRelative
        base_publish_receipt_sha256 = $baseReceiptSha.ToUpperInvariant()
    }
    [IO.File]::WriteAllText((Join-Path $output 'run.json'), (($aggregateRun | ConvertTo-Json -Depth 5) + "`n"), [Text.UTF8Encoding]::new($false))
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $baseLines[0..($firstRow-1)]) {
        if ($line -match '^K1_SCHEMA:' -and -not $hasLocatorPolicy) { $result.Add($line); $result.Add('LOCATOR_POLICY: MIXED_V1') }
        elseif ($line -match '^K1_ORIGIN_VERSION:') { $result.Add("K1_ORIGIN_VERSION: $engineVersion") }
        elseif ($line -match '^DATA_ODCIĘCIA:') { $result.Add("DATA_ODCIĘCIA: $aggregateCutoffDate") }
        elseif ($line -match '^K1_EXPORT_PATH:') { $result.Add("K1_EXPORT_PATH: $(Get-RelativeUnix $project $aggregateLedger)") }
        elseif ($line -match '^K1_EXPORT_SHA256:') { $result.Add("K1_EXPORT_SHA256: $aggregateLedgerHash") }
        else { $result.Add($line) }
    }
    foreach ($row in $baseRows) { $result.Add((ConvertTo-SourceRow $row)) }
    $result.Add('')
    foreach ($line in $baseLines[$cardHeader..($changeHeader-1)]) { $result.Add($line) }
    foreach ($card in $added) {
        $result.Add(('### #P-{0:D3}' -f ([int]$card.Id)))
        $result.Add('')
        foreach ($line in @($card.Body -split '\r?\n')) { $result.Add($line) }
        $result.Add('')
    }
    foreach ($line in $baseLines[$changeHeader..($baseLines.Count-1)]) { $result.Add($line) }
    $result.Add("- $supplementDate — suplement z runu $($runData.run_id); dodano $($added.Count) kart; ledger zagregowany $aggregateLedgerHash.")

    $preview = Join-Path $output ("K1-COMPILED-SUPPLEMENT-$($runData.run_id).md")
    [IO.File]::WriteAllText($preview, (($result -join "`r`n").TrimEnd() + "`r`n"), [Text.UTF8Encoding]::new($false))
    [IO.Directory]::Delete($rawDirectory, $true)
    $check = & $validator -ProjectPath $project -EvidencePath $preview -PendingReview -NoExit
    if ($check.Errors -gt 0 -or -not $check.ReadyForImport) { throw "SUPPLEMENT_PREVIEW_INVALID: $($check.ErrorDetails -join '; ')" }
    [pscustomobject]@{ Status='SUPPLEMENT_PREVIEW_READY'; PreviewPath=$preview; PreviewSha256=(Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash; CanonicalSha256=(Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash; LedgerSha256=$aggregateLedgerHash; SourceLedgerSha256=$ledgerHash; AddedCards=$added.Count }
    return
}

foreach ($value in @($ExpectedPreviewSha256,$ExpectedCanonicalSha256)) {
    if ($value -notmatch '^[A-Fa-f0-9]{64}$') { throw 'EXPECTED_PUBLISH_SHA_INVALID' }
}
$expectedPublishedSha = $ExpectedPreviewSha256.ToUpperInvariant()
$expectedPreviousSha = $ExpectedCanonicalSha256.ToUpperInvariant()
if ([string]::IsNullOrWhiteSpace($PreviewPath)) { throw 'PREVIEW_PATH_REQUIRED' }
$preview = [IO.Path]::GetFullPath($PreviewPath)
if (-not $preview.StartsWith($run.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'PREVIEW_OUTSIDE_RUN' }
if ((Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash -ne $expectedPublishedSha) { throw 'PREVIEW_SHA_MISMATCH' }
$canonicalShaBeforeLock = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
if ($canonicalShaBeforeLock -notin @($expectedPreviousSha,$expectedPublishedSha)) { throw 'CANONICAL_SHA_MISMATCH' }
$preflight = & $validator -ProjectPath $project -EvidencePath $preview -PendingReview -NoExit
if ($preflight.Errors -gt 0 -or -not $preflight.ReadyForImport) { throw "SUPPLEMENT_PREVIEW_NOT_READY: $($preflight.ErrorDetails -join '; ')" }
$previewText = Get-Content -LiteralPath $preview -Raw -Encoding UTF8
$aggregateExportValue = Get-FieldValue $previewText 'K1_EXPORT_PATH'
$aggregateExportHash = Get-FieldValue $previewText 'K1_EXPORT_SHA256'
$aggregateLedger = if ([IO.Path]::IsPathRooted($aggregateExportValue)) { [IO.Path]::GetFullPath($aggregateExportValue) } else { [IO.Path]::GetFullPath((Join-Path $project $aggregateExportValue)) }
$aggregateRunDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $preview))
$expectedAggregateLedger = [IO.Path]::GetFullPath((Join-Path $aggregateRunDirectory 'ledger.jsonl'))
if ($aggregateLedger -ne $expectedAggregateLedger -or -not (Test-Path -LiteralPath $aggregateLedger -PathType Leaf)) { throw 'SUPPLEMENT_AGGREGATE_LEDGER_INVALID' }
$actualAggregateHash = (Get-FileHash -LiteralPath $aggregateLedger -Algorithm SHA256).Hash
if ($aggregateExportHash -notmatch '^[A-Fa-f0-9]{64}$' -or $actualAggregateHash -ne $aggregateExportHash.ToUpperInvariant()) { throw 'SUPPLEMENT_AGGREGATE_LEDGER_SHA_MISMATCH' }
$aggregateRunJson = Join-Path $aggregateRunDirectory 'run.json'
if (-not (Test-Path -LiteralPath $aggregateRunJson -PathType Leaf)) { throw 'SUPPLEMENT_AGGREGATE_RUN_MISSING' }
$aggregateRunData = Get-Content -LiteralPath $aggregateRunJson -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
if ([string]$aggregateRunData.engine_version -ne '2.1.0' -or [string]$aggregateRunData.run_type -ne 'SUPPLEMENT_AGGREGATE') { throw 'SUPPLEMENT_AGGREGATE_RUN_VERSION_INVALID' }
if ([string]$aggregateRunData.ledger_sha256 -ne $actualAggregateHash) { throw 'SUPPLEMENT_AGGREGATE_RUN_LEDGER_MISMATCH' }
$aggregateSourceRunIds = @($aggregateRunData.source_runs | ForEach-Object { [string]$_ })
$aggregateSourceRunRelatives = @($aggregateRunData.source_run_relatives | ForEach-Object { [string]$_ })
$aggregateSourceLedgerHashes = @($aggregateRunData.source_ledger_sha256s | ForEach-Object { ([string]$_).ToUpperInvariant() })
$aggregateSupplementMode = if ([string]::IsNullOrWhiteSpace([string]$aggregateRunData.supplement_mode)) { 'ADD_RUN' } else { [string]$aggregateRunData.supplement_mode }
if ($aggregateSourceRunIds.Count -lt 1 -or $aggregateSourceRunRelatives.Count -ne $aggregateSourceRunIds.Count -or $aggregateSourceLedgerHashes.Count -ne $aggregateSourceRunIds.Count) { throw 'SUPPLEMENT_AGGREGATE_LINEAGE_INVALID' }
if (($aggregateSourceRunIds | Select-Object -Unique).Count -ne $aggregateSourceRunIds.Count -or
    $aggregateSupplementMode -notin @('ADD_RUN','APPEND_EXISTING') -or
    ($aggregateSupplementMode -eq 'ADD_RUN' -and ($aggregateSourceRunIds.Count -lt 2 -or [string]$aggregateRunData.supplement_source_run -ne $aggregateSourceRunIds[-1])) -or
    ($aggregateSupplementMode -eq 'APPEND_EXISTING' -and [string]$aggregateRunData.supplement_source_run -notin $aggregateSourceRunIds)) {
    throw 'SUPPLEMENT_AGGREGATE_RUN_SET_INVALID'
}
$seenAggregatePaths = @{}
for ($aggregateIndex = 0; $aggregateIndex -lt $aggregateSourceRunIds.Count; $aggregateIndex++) {
    $relative = $aggregateSourceRunRelatives[$aggregateIndex]
    $sourceHash = $aggregateSourceLedgerHashes[$aggregateIndex]
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $sourceHash -notmatch '^[A-F0-9]{64}$') { throw 'SUPPLEMENT_AGGREGATE_LINEAGE_INVALID' }
    $sourceRun = [IO.Path]::GetFullPath((Join-Path $project $relative))
    if (-not $sourceRun.StartsWith($allowedRunRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $seenAggregatePaths.ContainsKey($sourceRun.ToLowerInvariant())) { throw 'SUPPLEMENT_AGGREGATE_LINEAGE_PATH_INVALID' }
    $seenAggregatePaths[$sourceRun.ToLowerInvariant()] = $true
    $sourceRunJson = Join-Path $sourceRun 'run.json'
    $sourceLedger = Join-Path $sourceRun 'ledger.jsonl'
    foreach ($required in @($sourceRunJson,$sourceLedger)) { if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "SUPPLEMENT_AGGREGATE_LINEAGE_FILE_MISSING: $required" } }
    $sourceRunData = Get-Content -LiteralPath $sourceRunJson -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    if ([string]$sourceRunData.run_id -ne $aggregateSourceRunIds[$aggregateIndex]) { throw 'SUPPLEMENT_AGGREGATE_LINEAGE_RUN_ID_MISMATCH' }
    if ((Get-FileHash -LiteralPath $sourceLedger -Algorithm SHA256).Hash -ne $sourceHash) { throw 'SUPPLEMENT_AGGREGATE_LINEAGE_LEDGER_MISMATCH' }
}
$aggregateLineage = @(Resolve-K1PublishLineage -ProjectPath $project -PublicationRunDirectory $aggregateRunDirectory -PublicationRunData $aggregateRunData -ExpectedPublicationLedgerSha256 $actualAggregateHash)
Invoke-K1FreshLineageGates -EnginePath $engine -ProjectPath $project -Lineage $aggregateLineage -PythonPath $PythonPath | Out-Null
$baseReceiptRelative = [string]$aggregateRunData.base_publish_receipt_relative
$baseReceiptSha = [string]$aggregateRunData.base_publish_receipt_sha256
$canonicalShaAtCommit = (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
if ($canonicalShaAtCommit -notin @($expectedPreviousSha,$expectedPublishedSha)) { throw 'CANONICAL_CHANGED_BEFORE_PUBLISH' }
$recoveryMode = $canonicalShaAtCommit -eq $expectedPublishedSha
$currentMetaText = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$metaBefore = [Text.UTF8Encoding]::new($false).GetBytes($currentMetaText)
$metaBeforeSha = Get-Sha256HexFromBytes -Bytes $metaBefore
$projectOrigin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $currentMetaText
$currentMetaReceiptPath = Get-FieldValue $currentMetaText 'K1_PUBLISH_RECEIPT_PATH'
$currentMetaReceiptSha = Get-FieldValue $currentMetaText 'K1_PUBLISH_RECEIPT_SHA256'
$metaPointsToBaseReceipt = $currentMetaReceiptPath -ceq $baseReceiptRelative -and $currentMetaReceiptSha -eq $baseReceiptSha
if (-not $metaPointsToBaseReceipt -and -not $recoveryMode) {
    throw 'SUPPLEMENT_BASE_PUBLISH_RECEIPT_META_MISMATCH'
}
$baseReceiptState = if ($recoveryMode) {
    Assert-K1PublishReceiptCurrent -ProjectPath $project -ReceiptRelative $baseReceiptRelative -ExpectedReceiptSha256 $baseReceiptSha -AllowCanonicalSupersededBySha256 $expectedPublishedSha
} else {
    Assert-K1PublishReceiptCurrent -ProjectPath $project -ReceiptRelative $baseReceiptRelative -ExpectedReceiptSha256 $baseReceiptSha
}
$baseLineage = @($baseReceiptState.Lineage)
$expectedAggregateLineageCount = if ($aggregateSupplementMode -eq 'APPEND_EXISTING') { $baseLineage.Count } else { $baseLineage.Count + 1 }
if ($aggregateLineage.Count -ne $expectedAggregateLineageCount) { throw 'SUPPLEMENT_BASE_PUBLISH_LINEAGE_COUNT_MISMATCH' }
for ($baseLineageIndex = 0; $baseLineageIndex -lt $baseLineage.Count; $baseLineageIndex++) {
    if ([string]$baseLineage[$baseLineageIndex].RunId -cne [string]$aggregateLineage[$baseLineageIndex].RunId -or
        [string]$baseLineage[$baseLineageIndex].RunRelative -cne [string]$aggregateLineage[$baseLineageIndex].RunRelative -or
        [string]$baseLineage[$baseLineageIndex].RunJsonSha256 -ne [string]$aggregateLineage[$baseLineageIndex].RunJsonSha256 -or
        [string]$baseLineage[$baseLineageIndex].LedgerSha256 -ne [string]$aggregateLineage[$baseLineageIndex].LedgerSha256) {
        throw 'SUPPLEMENT_BASE_PUBLISH_LINEAGE_MISMATCH'
    }
}

$backup = Join-Path $aggregateRunDirectory ([string]$aggregateRunData.canonical_backup_relative)
if ([IO.Path]::GetFullPath($backup) -ne [IO.Path]::GetFullPath((Join-Path $aggregateRunDirectory ("canonical-before-supplement-$expectedPreviousSha.md")))) { throw 'RECOVERY_BACKUP_PATH_INVALID' }
Assert-SystemV7PathNoReparse -Path $backup -ContainmentRoot $project | Out-Null
if ($recoveryMode) {
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw 'RECOVERY_BACKUP_MISSING_AFTER_CANONICAL_REPLACEMENT' }
    $canonicalBefore = [IO.File]::ReadAllBytes($backup)
} else {
    $canonicalBefore = [IO.File]::ReadAllBytes($canonical)
    if (-not (Test-Path -LiteralPath $backup)) {
        Write-BytesCreateNewAtomic -Path $backup -Bytes $canonicalBefore
    }
}
if ([string]$aggregateRunData.canonical_backup_sha256 -ne $expectedPreviousSha -or
    (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $expectedPreviousSha) {
    throw 'RECOVERY_BACKUP_HASH_MISMATCH'
}

$verificationDirectory = Get-PublishVerificationDirectory $run
try {
    $regenerationParameters = @{
        Action = 'Preview'
        ProjectPath = $project
        RunDirectory = $run
        ExpectedLedgerSha256 = $ledgerHash
        OutputDirectory = $verificationDirectory
        PythonPath = $PythonPath
    }
    if ($recoveryMode) {
        $regenerationParameters.InternalRecoveryPreview = $true
        $regenerationParameters.InternalBaseCanonicalPath = $backup
        $regenerationParameters.InternalExpectedBaseCanonicalSha256 = $expectedPreviousSha
        $regenerationParameters.InternalBaseReceiptRelative = $baseReceiptRelative
        $regenerationParameters.InternalBaseReceiptSha256 = $baseReceiptSha
        $regenerationParameters.InternalSupersededCanonicalSha256 = $expectedPublishedSha
    }
    $regenerationParameters.InternalHeldProjectLock = $projectLock
    $regenerated = & $MyInvocation.MyCommand.Path @regenerationParameters
    if ([string]$regenerated.LedgerSha256 -ne $actualAggregateHash) { throw 'SUPPLEMENT_DERIVATION_LEDGER_SHA_MISMATCH' }
    Assert-FilesByteIdentical $aggregateLedger (Join-Path $verificationDirectory 'ledger.jsonl') 'SUPPLEMENT_DERIVATION_LEDGER_MISMATCH'
    $expectedNormalizedPreview = Get-NormalizedAggregatePreview $preview
    $actualNormalizedPreview = Get-NormalizedAggregatePreview ([string]$regenerated.PreviewPath)
    if ($expectedNormalizedPreview -cne $actualNormalizedPreview) {
        $differenceIndex = 0
        $sharedLength = [Math]::Min($expectedNormalizedPreview.Length, $actualNormalizedPreview.Length)
        while ($differenceIndex -lt $sharedLength -and $expectedNormalizedPreview[$differenceIndex] -ceq $actualNormalizedPreview[$differenceIndex]) { $differenceIndex++ }
        $expectedFragment = if ($differenceIndex -lt $expectedNormalizedPreview.Length) { $expectedNormalizedPreview.Substring($differenceIndex, [Math]::Min(80, $expectedNormalizedPreview.Length - $differenceIndex)).Replace("`r",'<CR>').Replace("`n",'<LF>') } else { '<EOF>' }
        $actualFragment = if ($differenceIndex -lt $actualNormalizedPreview.Length) { $actualNormalizedPreview.Substring($differenceIndex, [Math]::Min(80, $actualNormalizedPreview.Length - $differenceIndex)).Replace("`r",'<CR>').Replace("`n",'<LF>') } else { '<EOF>' }
        throw "SUPPLEMENT_DERIVATION_MISMATCH: offset=$differenceIndex expected=$expectedFragment actual=$actualFragment"
    }
    $regeneratedRunData = Get-Content -LiteralPath (Join-Path $verificationDirectory 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    Assert-StringArraysEqual $aggregateSourceRunIds @($regeneratedRunData.source_runs) 'SUPPLEMENT_DERIVATION_LINEAGE_MISMATCH'
    Assert-StringArraysEqual $aggregateSourceRunRelatives @($regeneratedRunData.source_run_relatives) 'SUPPLEMENT_DERIVATION_LINEAGE_MISMATCH'
    Assert-StringArraysEqual $aggregateSourceLedgerHashes @($regeneratedRunData.source_ledger_sha256s) 'SUPPLEMENT_DERIVATION_LINEAGE_MISMATCH'
    if ([string]$aggregateRunData.supplement_source_run -cne [string]$regeneratedRunData.supplement_source_run -or
        [string]$aggregateRunData.supplement_mode -cne [string]$regeneratedRunData.supplement_mode -or
        [string]$aggregateRunData.canonical_backup_relative -cne [string]$regeneratedRunData.canonical_backup_relative -or
        [string]$aggregateRunData.canonical_backup_sha256 -cne [string]$regeneratedRunData.canonical_backup_sha256 -or
        [string]$aggregateRunData.base_publish_receipt_relative -cne [string]$regeneratedRunData.base_publish_receipt_relative -or
        [string]$aggregateRunData.base_publish_receipt_sha256 -cne [string]$regeneratedRunData.base_publish_receipt_sha256) {
        throw 'SUPPLEMENT_DERIVATION_RUN_METADATA_MISMATCH'
    }
} finally {
    Remove-PublishVerificationDirectory $run $verificationDirectory
}
Invoke-K1FreshLineageGates -EnginePath $engine -ProjectPath $project -Lineage $aggregateLineage -PythonPath $PythonPath | Out-Null
$receiptPath = Join-Path $aggregateRunDirectory 'publish-receipt.json'
$receiptExistedBefore = Test-Path -LiteralPath $receiptPath -PathType Leaf
$receiptExtra = [ordered]@{
    base_publish_receipt_relative = $baseReceiptRelative
    base_publish_receipt_sha256 = $baseReceiptSha.ToUpperInvariant()
    canonical_previous_sha256 = $ExpectedCanonicalSha256.ToUpperInvariant()
    recovery_backup_relative = Get-RelativeUnix $project $backup
    recovery_backup_sha256 = $ExpectedCanonicalSha256.ToUpperInvariant()
    supplement_source_run = [string]$aggregateRunData.supplement_source_run
    supplement_mode = [string]$aggregateRunData.supplement_mode
}
$receiptPayload = New-K1PublishReceiptPayload `
    -PublicationKind 'SUPPLEMENT' -ProjectPath $project -PublicationRunDirectory $aggregateRunDirectory -PublicationRunData $aggregateRunData `
    -PublicationLedgerPath $aggregateLedger -PublicationLedgerSha256 $actualAggregateHash `
    -PreviewPath $preview -PreviewSha256 $ExpectedPreviewSha256 `
    -CanonicalPath $canonical -CanonicalSha256 $ExpectedPreviewSha256 -Lineage $aggregateLineage -Extra $receiptExtra
$receiptBytes = ConvertTo-K1PublishReceiptBytes $receiptPayload
$receiptSha = Get-K1PublishBytesSha256 $receiptBytes
$receiptRelative = Get-K1PublishRelativePath -ProjectPath $project -Path $receiptPath
if (-not $metaPointsToBaseReceipt -and
    ($currentMetaReceiptPath -cne $receiptRelative -or $currentMetaReceiptSha -ne $receiptSha)) {
    throw 'SUPPLEMENT_RECOVERY_META_RECEIPT_MISMATCH'
}
$metaText = [Text.Encoding]::UTF8.GetString($metaBefore)
$publishRunData = Get-Content -LiteralPath $runJson -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
$publishEngineVersion = [string]$publishRunData.engine_version
if ($publishEngineVersion -ne '2.1.0') { throw "RUN_ENGINE_VERSION_UNSUPPORTED: $publishEngineVersion" }
$metaText = Set-MetaField $metaText 'K1_ENGINE_VERSION' $publishEngineVersion
$metaText = Set-MetaField $metaText 'K1_RUN_PATH' (Get-RelativeUnix $project $aggregateRunDirectory)
$metaText = Set-MetaField $metaText 'K1_LEDGER_SHA256' $actualAggregateHash
$metaText = Set-MetaField $metaText 'K1_PUBLISH_RECEIPT_PATH' $receiptRelative
$metaText = Set-MetaField $metaText 'K1_PUBLISH_RECEIPT_SHA256' $receiptSha
$temporary = Join-Path $project ('.k1-supplement-' + [guid]::NewGuid().ToString('N') + '.tmp')
$receiptAttempted = $false
$metaWritten = $false
$canonicalReplaced = $false
try {
    if ((Get-FileHash -LiteralPath $ledger -Algorithm SHA256).Hash -ne $ledgerHash) { throw 'LEDGER_CHANGED_BEFORE_PUBLISH' }
    if ((Get-FileHash -LiteralPath $aggregateLedger -Algorithm SHA256).Hash -ne $actualAggregateHash) { throw 'AGGREGATE_LEDGER_CHANGED_BEFORE_PUBLISH' }
    if ((Get-FileHash -LiteralPath $preview -Algorithm SHA256).Hash -ne $expectedPublishedSha) { throw 'PREVIEW_CHANGED_BEFORE_PUBLISH' }
    $requiredCanonicalSha = if ($recoveryMode) { $expectedPublishedSha } else { $expectedPreviousSha }
    if ((Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash -ne $requiredCanonicalSha) { throw 'CANONICAL_CHANGED_BEFORE_PUBLISH' }
    if ((Get-FileHash -LiteralPath $aggregateRunJson -Algorithm SHA256).Hash -ne [string]$receiptPayload.publication_run_json_sha256) { throw 'AGGREGATE_RUN_JSON_CHANGED_BEFORE_PUBLISH' }
    if (-not $recoveryMode) {
        $previewStream = [IO.File]::OpenRead($preview)
        try {
            $temporaryStream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $previewStream.CopyTo($temporaryStream); $temporaryStream.Flush($true) } finally { $temporaryStream.Dispose() }
        } finally { $previewStream.Dispose() }
        [IO.File]::Move($temporary, $canonical, $true)
        $canonicalReplaced = $true
    }
    Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text $metaText -ExpectedCurrentSha256 $metaBeforeSha -HeldLockStream $projectLock
    $metaWritten = $true
    $final = & $validator -ProjectPath $project -NoExit
    if ($final.Errors -gt 0 -or -not $final.GateReady) { throw "SUPPLEMENT_CANONICAL_VALIDATION_FAIL: $($final.ErrorDetails -join '; ')" }
    if ((Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash -ne $ExpectedPreviewSha256.ToUpperInvariant()) { throw 'SUPPLEMENT_CANONICAL_SHA_CHANGED_BEFORE_RECEIPT' }
    $receiptAttempted = $true
    $writtenReceipt = Write-K1PublishReceiptCreateNew -ProjectPath $project -PublicationRunDirectory $aggregateRunDirectory -Bytes $receiptBytes -ExpectedSha256 $receiptSha
    $receiptState = Assert-K1PublishReceiptCurrent -ProjectPath $project -ReceiptRelative $receiptRelative -ExpectedReceiptSha256 $receiptSha
    [pscustomobject]@{
        Status=$(if ($recoveryMode) { 'SUPPLEMENT_PUBLISHED_RECOVERED_OR_REUSED' } else { 'SUPPLEMENT_PUBLISHED_ADD_ONLY' }); Destination=$canonical; Sha256=(Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash
        RecoveryBackup=$backup; LedgerSha256=$actualAggregateHash; SourceLedgerSha256=$ledgerHash; Cards=$final.Cards
        PublishReceipt=$writtenReceipt.Path; PublishReceiptSha256=$receiptState.Sha256
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
    if ($rollbackOwned -and $canonicalReplaced -and (Test-Path -LiteralPath $canonical -PathType Leaf) -and
        (Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash -eq $expectedPublishedSha) {
        $rollbackTemp = Join-Path $project ('.k1-rollback-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            $rollbackStream = [IO.File]::Open($rollbackTemp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $rollbackStream.Write($canonicalBefore, 0, $canonicalBefore.Length); $rollbackStream.Flush($true) } finally { $rollbackStream.Dispose() }
            [IO.File]::Move($rollbackTemp, $canonical, $true)
        } finally {
            if (Test-Path -LiteralPath $rollbackTemp -PathType Leaf) { [IO.File]::Delete($rollbackTemp) }
        }
    }
    if ($rollbackOwned -and $receiptAttempted -and -not $receiptExistedBefore -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { [IO.File]::Delete($receiptPath) }
    if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) }
    throw
}
} finally {
    if ($ownsProjectLock) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
}
