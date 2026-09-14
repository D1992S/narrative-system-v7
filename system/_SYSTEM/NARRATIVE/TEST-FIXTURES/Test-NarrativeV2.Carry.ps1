param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$FixtureRoot
)
$ErrorActionPreference = 'Stop'
$systemRoot = [IO.Path]::GetFullPath($SystemRoot)
$tools = Join-Path $systemRoot 'tools'
$fixtureRoot = [IO.Path]::GetFullPath($FixtureRoot)
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null

function Write-Utf8Lf([string]$Path, [string]$Text) {
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function New-DraftText([string]$Marker, [char]$HashChar) {
    $blockSha = ([string]$HashChar) * 64
    @"
SCHEMA: K3_ASSEMBLED_DRAFT_V2
<!-- K3_BLOCK_MAP_BEGIN -->
```json
{"schema":"K3_BLOCK_MAP_V1","acts":[{"act_id":"ACT-001","blocks":[{"block_id":"BLOCK-ACT-001-001","block_sha256":"$blockSha"}]}]}
```
<!-- K3_BLOCK_MAP_END -->
## NARRACJA ROBOCZA
To jest spójna narracja wariantu $Marker. Zdanie pozostaje konkretne i nadaje się do testu czytelnika.
"@
}

function New-ColdOutput([string]$DraftSha) {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in @(
        'SCHEMA: K4_COLD_READER_OUTPUT_V1',
        'LENS: COLD_READER',
        "DRAFT_SHA256: $DraftSha",
        'VERDICT: PASS',
        'CRITICAL_COUNT: 0',
        'MAJOR_COUNT: 0',
        'MINOR_COUNT: 0',
        'REVIEW_ALERT_COUNT: 0'
    )) { $lines.Add($line) }
    foreach ($i in 1..10) {
        $id = 'Q{0:D2}' -f $i
        $lines.Add("${id}_RESPONSE: Odpowiedź $i jest jednoznaczna i nie ujawnia problemu narracyjnego.")
        $lines.Add("${id}_EVIDENCE: Zdanie wariantu A stanowi konkretny punkt odniesienia dla odpowiedzi $i.")
    }
    foreach ($line in @(
        '## CONFUSION_AND_DROPOFF',
        'Narracja jest krótka, czytelna i nie tworzy punktu porzucenia.',
        '## PAYOFF_AND_MEMORY',
        'Wariant A pozostaje łatwy do zapamiętania po jednokrotnym odczycie.',
        '## FINDINGS',
        'BRAK'
    )) { $lines.Add($line) }
    return ($lines -join "`n") + "`n"
}

function New-ImpactOutput([object]$Impact) {
    $changed = @($Impact.changed_block_ids) -join ','
    if ([string]::IsNullOrWhiteSpace($changed)) { $changed = 'BRAK' }
    @"
SCHEMA: QA_IMPACT_OUTPUT_V1
DIFF_SHA256: $($Impact.diff_sha256)
OLD_DRAFT_SHA256: $($Impact.old_draft_sha256)
NEW_DRAFT_SHA256: $($Impact.new_draft_sha256)
CHANGE_CLASS: $($Impact.change_class)
CHANGED_BLOCK_IDS: $changed
EDITOR_DECISION: CARRYFORWARD_ALLOWED
EDITOR_REASON: Zmiana wariantu nie wpływa na kryteria redaktorskie kontrolowane przez ten test.
EDITOR_AFFECTED_SCOPE: Wyłącznie pojedyncze zdanie oznaczenia wariantu w bloku testowym.
EDITOR_CONFIDENCE: HIGH
VERIFY_DECISION: CARRYFORWARD_ALLOWED
VERIFY_REASON: Zmiana nie modyfikuje żadnego twierdzenia źródłowego w syntetycznym materiale.
VERIFY_AFFECTED_SCOPE: Brak wpływu na twierdzenia i lokalizatory źródłowe w tym teście.
VERIFY_CONFIDENCE: HIGH
COLD_READER_DECISION: CARRYFORWARD_ALLOWED
COLD_READER_REASON: Zmiana zachowuje znaczenie, rytm i czytelność krótkiej narracji testowej.
COLD_READER_AFFECTED_SCOPE: Jedno oznaczenie wariantu bez wpływu na odbiór czytelnika.
COLD_READER_CONFIDENCE: HIGH
"@
}

function New-ReviewRun([string]$Project, [string]$ImpactPath, [string]$RunId, [string]$TaskId) {
    $bundleResult = & (Join-Path $tools 'Start-QAImpactReview.ps1') -ProjectPath $Project -ImpactPath $ImpactPath -RunId $RunId
    $impact = Get-Content -LiteralPath $ImpactPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 64
    $manifest = Get-Content -LiteralPath $bundleResult.ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 64
    $output = Get-SystemV7NarrativeExpectedRunOutputPath -ProjectPath $Project -BundleData $manifest
    Write-Utf8Lf -Path $output -Text (New-ImpactOutput -Impact $impact)
    & (Join-Path $tools 'New-NarrativeRunReceipt.ps1') -ProjectPath $Project -RunId $RunId -OutputPath $output -TaskId $TaskId -ModelId 'gpt-test' -ModelRevision 'qa-fixture' -ModelSettingsSha256 ('B' * 64) -PromptRevision 'QA_IMPACT_V1' -ActorRole 'CHATGPT_CODEX' -StartedAt ([DateTimeOffset]::UtcNow.AddMinutes(-2)) | Out-Null
    return Join-Path $Project "_work\narrative-runs\$RunId\run-receipt.json"
}

try {
    & (Join-Path $tools 'New-Project.ps1') -ProjectName 'project' -DestinationRoot $fixtureRoot -NarrativeV2Pilot | Out-Null
    $project = Join-Path $fixtureRoot 'project'
    . (Join-Path $tools 'Project-Origin.ps1')
    . (Join-Path $tools 'Narrative-V2.ps1')
    . (Join-Path $tools 'Narrative-Receipts.ps1')

    $metaPath = Join-Path $project 'meta.md'
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $meta = Set-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE' -Value 'K4'
    $meta = Set-SystemV7NarrativeMetaField -Text $meta -Name 'STAGE_OWNER' -Value 'ChatGPT'
    Write-Utf8Lf -Path $metaPath -Text $meta

    $draftPath = Join-Path $project '03-draft.md'
    Write-Utf8Lf -Path $draftPath -Text (New-DraftText -Marker 'A' -HashChar 'A')
    $shaA = (Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash

    $inputs = Join-Path $project '_work\k4\inputs'
    [IO.Directory]::CreateDirectory($inputs) | Out-Null
    $cleanPath = Join-Path $inputs "clean-narration-$shaA.md"
    $clean = Get-SystemV7CleanNarrationFromDraft -DraftText (Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8)
    Write-Utf8Lf -Path $cleanPath -Text $clean
    $questionsSource = Join-Path $systemRoot '_SYSTEM\NARRATIVE\COLD-READER-QUESTIONS.md'
    $schemaSource = Join-Path $systemRoot '_SYSTEM\NARRATIVE\COLD-READER-OUTPUT-SCHEMA.md'
    $questionsSha = (Get-FileHash -LiteralPath $questionsSource -Algorithm SHA256).Hash
    $schemaSha = (Get-FileHash -LiteralPath $schemaSource -Algorithm SHA256).Hash
    $questionsSnapshot = Join-Path $inputs "cold-reader-questions-$questionsSha.md"
    $schemaSnapshot = Join-Path $inputs "cold-reader-output-schema-$schemaSha.md"
    [IO.File]::Copy($questionsSource, $questionsSnapshot, $false)
    [IO.File]::Copy($schemaSource, $schemaSnapshot, $false)
    $coldRunId = 'COLD.A.0001'
    $coldBundle = New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType 'COLD_READER' -RunId $coldRunId -Inputs @{
        CLEAN_NARRATION = $cleanPath
        COLD_READER_QUESTIONS = $questionsSnapshot
        COLD_READER_OUTPUT_SCHEMA = $schemaSnapshot
    }
    $coldBundleData = Get-Content -LiteralPath $coldBundle.Path -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 64
    $coldOutput = Get-SystemV7NarrativeExpectedRunOutputPath -ProjectPath $project -BundleData $coldBundleData
    Write-Utf8Lf -Path $coldOutput -Text (New-ColdOutput -DraftSha $shaA)
    & (Join-Path $tools 'New-NarrativeRunReceipt.ps1') -ProjectPath $project -RunId $coldRunId -OutputPath $coldOutput -TaskId 'TASK.COLD.A.0001' -ModelId 'gpt-test' -ModelRevision 'qa-fixture' -ModelSettingsSha256 ('A' * 64) -PromptRevision 'COLD_READER_V1' -ActorRole 'CHATGPT_CODEX' -StartedAt ([DateTimeOffset]::UtcNow.AddMinutes(-2)) | Out-Null
    $coldReceipt = Join-Path $project "_work\narrative-runs\$coldRunId\run-receipt.json"

    $baselineA = & (Join-Path $tools 'Compare-DraftV2.ps1') -ProjectPath $project -SaveBaseline
    Write-Utf8Lf -Path $draftPath -Text (New-DraftText -Marker 'B' -HashChar 'B')
    $impactABResult = & (Join-Path $tools 'Compare-DraftV2.ps1') -ProjectPath $project -OldDraftPath $baselineA.BaselinePath -WriteImpact
    $reviewAB = New-ReviewRun -Project $project -ImpactPath $impactABResult.ImpactPath -RunId 'IMPACT.AB.0001' -TaskId 'TASK.IMPACT.AB.0001'
    $carryAB = & (Join-Path $tools 'New-QACarryForwardReceipt.ps1') -ProjectPath $project -ImpactPath $impactABResult.ImpactPath -Lens 'COLD_READER' -PriorProofPath $coldReceipt -Justification 'Syntetyczny przegląd potwierdza brak wpływu zmiany A do B na soczewkę Cold Reader.' -ImpactReviewRunId 'IMPACT.AB.0001'
    $resolutionAB = Get-SystemV7K4LensProofResolutionState -ProjectPath $project -Lens 'COLD_READER' -ProofPath $carryAB.Path -DraftSha256 $impactABResult.NewDraftSha256
    $rootBundleState = Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $coldBundle.Path
    $rootIdentityState = Get-SystemV7K4BundleDraftIdentityState -Lens 'COLD_READER' -BundleData $rootBundleState.Data
    $rootCleanEntry = @($rootBundleState.Data.entries | Where-Object { [string]$_.content_role -ceq 'CLEAN_NARRATION' })[0]
    $rootWrongCleanIdentityState = Get-SystemV7K4LensOutputState -ProjectPath $project -Lens 'COLD_READER' -OutputPath $coldOutput -ExpectedDraftSha256 ([string]$rootCleanEntry.sha256) -BundleData $rootBundleState.Data

    $baselineB = & (Join-Path $tools 'Compare-DraftV2.ps1') -ProjectPath $project -SaveBaseline
    Write-Utf8Lf -Path $draftPath -Text (New-DraftText -Marker 'C' -HashChar 'C')
    $impactBCResult = & (Join-Path $tools 'Compare-DraftV2.ps1') -ProjectPath $project -OldDraftPath $baselineB.BaselinePath -WriteImpact
    $reviewBC = New-ReviewRun -Project $project -ImpactPath $impactBCResult.ImpactPath -RunId 'IMPACT.BC.0001' -TaskId 'TASK.IMPACT.BC.0001'

    $creator2Succeeded = $false
    $creator2Error = $null
    try {
        $carryBC = & (Join-Path $tools 'New-QACarryForwardReceipt.ps1') -ProjectPath $project -ImpactPath $impactBCResult.ImpactPath -Lens 'COLD_READER' -PriorProofPath $carryAB.Path -Justification 'Syntetyczny przegląd potwierdza brak wpływu zmiany B do C na soczewkę Cold Reader.' -ImpactReviewRunId 'IMPACT.BC.0001'
        $creator2Succeeded = $true
    } catch { $creator2Error = $_.Exception.Message }

    $creator2State = if ($creator2Succeeded) {
        Get-SystemV7QACarryForwardState -ProjectPath $project -ReceiptPath $carryBC.Path -ExpectedLens 'COLD_READER' -ExpectedNewDraftSha256 $impactBCResult.NewDraftSha256
    } else { $null }
    $resolutionBC = if ($creator2Succeeded) { Get-SystemV7K4LensProofResolutionState -ProjectPath $project -Lens 'COLD_READER' -ProofPath $carryBC.Path -DraftSha256 $impactBCResult.NewDraftSha256 } else { $null }

    $priorAtDepth0 = Get-SystemV7QACarryForwardState -ProjectPath $project -ReceiptPath $carryAB.Path -ExpectedLens 'COLD_READER' -ExpectedNewDraftSha256 $impactABResult.NewDraftSha256
    $priorAtDepth1 = Get-SystemV7QACarryForwardState -ProjectPath $project -ReceiptPath $carryAB.Path -ExpectedLens 'COLD_READER' -ExpectedNewDraftSha256 $impactABResult.NewDraftSha256 -Depth 1

    $impactBC = Get-Content -LiteralPath $impactBCResult.ImpactPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 64
    $origin = Get-SystemV7ProjectOriginState -ProjectPath $project
    $reviewBCState = Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $reviewBC -ExpectedRunType 'QA_IMPACT_REVIEW'
    $carryABStateJson = Get-Content -LiteralPath $carryAB.Path -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 32
    $manualScope = @($impactBC.changed_block_ids) -join ','
    if ([string]::IsNullOrWhiteSpace($manualScope)) { $manualScope = 'NO_BLOCK_CHANGE' }
    $manualRecord = New-SystemV7QACarryForwardRecord -ProjectOriginSha256 $origin.Sha256 -Lens 'COLD_READER' -OldDraftSha256 $impactBC.old_draft_sha256 -NewDraftSha256 $impactBC.new_draft_sha256 -DiffSha256 $impactBC.diff_sha256 -ChangeClass 'STYLE_ONLY' -ChangeScope $manualScope -PriorProofRelative (Get-SystemV7NarrativeRelativePath -Root $project -Path $carryAB.Path) -PriorProofSha256 ((Get-FileHash -LiteralPath $carryAB.Path -Algorithm SHA256).Hash) -PriorOutputSha256 $carryABStateJson.prior_output_sha256 -ImpactRelative (Get-SystemV7NarrativeRelativePath -Root $project -Path $impactBCResult.ImpactPath) -ImpactSha256 ((Get-FileHash -LiteralPath $impactBCResult.ImpactPath -Algorithm SHA256).Hash) -LensDependencySha256 $carryABStateJson.lens_dependency_sha256 -RuleId 'IMPACT_REVIEW_NO_LENS_EFFECT' -Justification 'Ręczny rekord wyłącznie do sprawdzenia walidatora pełnego łańcucha A do B do C.' -ImpactReviewRunId 'IMPACT.BC.0001' -ImpactReviewReceiptRelative (Get-SystemV7NarrativeRelativePath -Root $project -Path $reviewBC) -ImpactReviewReceiptSha256 $reviewBCState.Sha256
    $manualPath = Join-Path $project '_work\k4\receipts\COLD_READER.manual.BC.carryforward.json'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $manualPath)) | Out-Null
    Write-SystemV7NarrativeCreateNewJson -Path $manualPath -Value $manualRecord | Out-Null
    $manualHeadState = Get-SystemV7QACarryForwardState -ProjectPath $project -ReceiptPath $manualPath -ExpectedLens 'COLD_READER' -ExpectedNewDraftSha256 $impactBC.new_draft_sha256

    [pscustomobject]@{
        FixturePath = $project
        ShaA = $shaA
        ShaB = $impactABResult.NewDraftSha256
        ShaC = $impactBCResult.NewDraftSha256
        BaselineBExists = Test-Path -LiteralPath $baselineB.BaselinePath -PathType Leaf
        BaselineBReceiptExists = Test-Path -LiteralPath $baselineB.ReceiptPath -PathType Leaf
        CarryABCreated = Test-Path -LiteralPath $carryAB.Path -PathType Leaf
        CarryABProofResolutionValid = $resolutionAB.Valid
        CarryABProofResolutionErrors = @($resolutionAB.Errors)
        RootRawDraftIdentitySha256 = $rootIdentityState.Sha256
        RootCleanSnapshotSha256 = [string]$rootCleanEntry.sha256
        RootRawAndCleanDiffer = [string]$rootIdentityState.Sha256 -cne [string]$rootCleanEntry.sha256
        RootOutputAgainstCleanIdentityValid = $rootWrongCleanIdentityState.Valid
        RootOutputAgainstCleanIdentityErrors = @($rootWrongCleanIdentityState.Errors)
        Creator2Succeeded = $creator2Succeeded
        Creator2Error = $creator2Error
        Creator2Path = if ($creator2Succeeded) { $carryBC.Path } else { $null }
        Creator2HeadValid = if ($creator2State) { $creator2State.Valid } else { $false }
        Creator2HeadErrors = if ($creator2State) { @($creator2State.Errors) } else { @() }
        Creator2ProofResolutionValid = if ($resolutionBC) { $resolutionBC.Valid } else { $false }
        Creator2ProofResolutionErrors = if ($resolutionBC) { @($resolutionBC.Errors) } else { @() }
        PriorAtDepth0Valid = $priorAtDepth0.Valid
        PriorAtDepth0Errors = @($priorAtDepth0.Errors)
        PriorAtDepth1Valid = $priorAtDepth1.Valid
        PriorAtDepth1Errors = @($priorAtDepth1.Errors)
        ManualHeadValid = $manualHeadState.Valid
        ManualHeadErrors = @($manualHeadState.Errors)
    }
} catch {
    throw
}

