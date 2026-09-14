[CmdletBinding()]
param([string]$PythonPath = 'python.exe')

$ErrorActionPreference = 'Stop'
$systemRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$compiler = Join-Path $systemRoot 'tools\Compile-K1LiteV2.ps1'
$corpusCompiler = Join-Path $systemRoot 'tools\Compile-K1LiteV2Corpus.ps1'
$merger = Join-Path $systemRoot 'tools\Merge-K1LiteV2Supplement.ps1'
$validator = Join-Path $systemRoot 'tools\Validate-EvidenceBase.ps1'
$engine = Join-Path $systemRoot 'tools\k1-lite-v2\Invoke-K1LiteV2.ps1'
$publishIntegrity = Join-Path $systemRoot 'tools\K1-PublishIntegrity.ps1'
$fixtureScript = Join-Path $PSScriptRoot 'make_system_fixture.py'
. $publishIntegrity
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("k1-lite-v2-system-" + [guid]::NewGuid().ToString('N'))
$previousNoBytecode = [Environment]::GetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', 'Process')
[Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', '1', 'Process')
$project = Join-Path $temporary 'project'
New-Item -ItemType Directory -Path $project -Force | Out-Null
function Assert-NoPublishVerificationDirectory([string]$RunDirectory) {
    $leftovers = @(Get-ChildItem -LiteralPath $RunDirectory -Directory -Filter '.publish-verify-*')
    if ($leftovers.Count -gt 0) { throw "PUBLISH_VERIFICATION_DIRECTORY_NOT_CLEANED: $($leftovers.FullName -join '; ')" }
}
function Assert-PublishReceiptState([string]$ProjectPath, [string]$ExpectedKind, [int]$ExpectedLineageCount) {
    $metaText = Get-Content -LiteralPath (Join-Path $ProjectPath 'meta.md') -Raw -Encoding UTF8
    $relative = [regex]::Match($metaText, '(?m)^K1_PUBLISH_RECEIPT_PATH:\s*(?<v>.+?)\s*$').Groups['v'].Value
    $sha = [regex]::Match($metaText, '(?m)^K1_PUBLISH_RECEIPT_SHA256:\s*(?<v>[A-Fa-f0-9]{64})\s*$').Groups['v'].Value
    $state = Assert-K1PublishReceiptCurrent -ProjectPath $ProjectPath -ReceiptRelative $relative -ExpectedReceiptSha256 $sha
    if ([string]$state.Data.publication_kind -ne $ExpectedKind -or @($state.Lineage).Count -ne $ExpectedLineageCount) {
        throw "PUBLISH_RECEIPT_STATE_INVALID: kind=$($state.Data.publication_kind) lineage=$(@($state.Lineage).Count)"
    }
    return $state
}
function Add-SelectedAppendCandidateFixture([string]$ProjectPath, [string]$RunDirectory, [switch]$PdfVisual) {
    $runData = Get-Content -LiteralPath (Join-Path $RunDirectory 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    $chunk = Get-Content -LiteralPath (Join-Path $RunDirectory 'chunks.jsonl') -Encoding UTF8 | Select-Object -First 1 | ConvertFrom-Json -DateKind String
    $ledgerPath = Join-Path $RunDirectory 'ledger.jsonl'
    $continuation = @(Get-Content -LiteralPath $ledgerPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json -DateKind String } | Where-Object { $_.event_type -eq 'chunk_result' -and $_.chunk_id -eq $chunk.chunk_id }).Count
    $candidateId = '{0}-{1:D2}-B' -f ([string]$chunk.chunk_id),$continuation
    $suffix = 'batch-append-{0:D2}' -f $continuation
    $resultPath = Join-Path $RunDirectory "incoming\$suffix-result.json"
    $resultData = [ordered]@{
        schema='K1_LITE_V2_WORKER_RESULT_V1'; run_id=[string]$runData.run_id; chunk_id=[string]$chunk.chunk_id
        chunk_sha256=[string]$chunk.chunk_sha256; continuation_no=$continuation; status='CANDIDATE'; more_strong_candidates=$false
        probe_answers=[ordered]@{}
        candidates=@([ordered]@{
            local_id='B'; claim='Źródło opisuje porę zapisu świadka.'; page='P0001'
            quote='A second passage says the witness recorded the event before sunrise.'
            category='TARGETED'; k0_target='Q-001'; film_value=3; risk=1; speaker_mode='AUTHOR_CLAIM'
            genealogy='Bezpośrednie twierdzenie źródła.'
            facts=@([ordered]@{key='record_time';value='before sunrise';subject_terms=@('witness','recorded')})
        })
        metrics=[ordered]@{model='gpt-5.6-luna';effort='medium';measurement='MEASURED';input_tokens=300;cached_input_tokens=0;output_tokens=80;elapsed_ms=200;retry=0}
    }
    [IO.File]::WriteAllText($resultPath, (($resultData | ConvertTo-Json -Depth 10) + "`n"), [Text.UTF8Encoding]::new($false))
    $imported = (& $engine -Action ImportResult -ProjectDirectory $ProjectPath -RunDirectory $RunDirectory -ResultPath $resultPath -ExpectedLedgerSha256 (Get-FileHash -LiteralPath $ledgerPath -Algorithm SHA256).Hash -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $candidate = Get-Content -LiteralPath $ledgerPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json -DateKind String } | Where-Object candidate_id -eq $candidateId | Select-Object -First 1
    if ($null -eq $candidate) { throw 'BATCH_APPEND_CANDIDATE_NOT_IMPORTED' }

    $chatGptPath = Join-Path $RunDirectory "incoming\$suffix-chatgpt.json"
    $chatGptData = [ordered]@{schema='K1_LITE_V2_DECISION_BATCH_V1';run_id=[string]$runData.run_id;decisions=@([ordered]@{candidate_id=$candidateId;decision='KEY_CHATGPT';actor='CHATGPT';reason='Kluczowy dowód batch append-only.';conflict_acknowledged=$false})}
    [IO.File]::WriteAllText($chatGptPath, (($chatGptData | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    $chatGpt = (& $engine -Action AddDecisions -ProjectDirectory $ProjectPath -RunDirectory $RunDirectory -DecisionPath $chatGptPath -ExpectedLedgerSha256 ([string]$imported.ledger_sha256) -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $dawidPath = Join-Path $RunDirectory "incoming\$suffix-dawid.json"
    $dawidData = [ordered]@{schema='K1_LITE_V2_DECISION_BATCH_V1';run_id=[string]$runData.run_id;decisions=@([ordered]@{candidate_id=$candidateId;decision='MUST_INCLUDE';actor='DAWID';reason='Dawid zatwierdza dowód batch append-only.';conflict_acknowledged=$true})}
    [IO.File]::WriteAllText($dawidPath, (($dawidData | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    $dawid = (& $engine -Action AddDecisions -ProjectDirectory $ProjectPath -RunDirectory $RunDirectory -DecisionPath $dawidPath -ExpectedLedgerSha256 ([string]$chatGpt.ledger_sha256) -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $currentLedgerSha = [string]$dawid.ledger_sha256

    if ($PdfVisual) {
        $full = Join-Path $RunDirectory 'qa\full.png'
        $crop = Join-Path $RunDirectory 'qa\crop.png'
        $visualPath = Join-Path $RunDirectory "incoming\$suffix-visual.json"
        $visualData = [ordered]@{
            schema='K1_LITE_V2_VISUAL_RECEIPT_V1';run_id=[string]$runData.run_id;candidate_id=$candidateId;quote_sha256=[string]$candidate.quote_sha256
            full_render_relative=([IO.Path]::GetRelativePath($ProjectPath,$full)).Replace('\','/');full_render_sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
            crop_relative=([IO.Path]::GetRelativePath($ProjectPath,$crop)).Replace('\','/');crop_sha256=(Get-FileHash -LiteralPath $crop -Algorithm SHA256).Hash
            reviewer='fixture-controller';verdict='PASS'
        }
        [IO.File]::WriteAllText($visualPath, (($visualData | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
        $visual = (& $engine -Action AddVisual -ProjectDirectory $ProjectPath -RunDirectory $RunDirectory -ReceiptPath $visualPath -ExpectedLedgerSha256 $currentLedgerSha -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
        $currentLedgerSha = [string]$visual.ledger_sha256
    }

    $reviewView = Join-Path $RunDirectory "views\$suffix-review"
    $reviewReport = (& $engine -Action BuildViews -ProjectDirectory $ProjectPath -RunDirectory $RunDirectory -OutputDirectory $reviewView -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $reviewArtifact = Join-Path $reviewView 'editorial-review.md'
    $reviewReceipt = Join-Path $RunDirectory "incoming\$suffix-review.json"
    $reviewData = [ordered]@{
        schema='K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1';run_id=[string]$runData.run_id;snapshot_sha256=[string]$reviewReport.editorial_review.snapshot_sha256
        review_artifact_relative=([IO.Path]::GetRelativePath($RunDirectory,$reviewArtifact)).Replace('\','/');review_artifact_sha256=(Get-FileHash -LiteralPath $reviewArtifact -Algorithm SHA256).Hash
        actor='DAWID';verdict='REVIEWED';note='Dawid zatwierdza batch append-only po pełnym przeglądzie.'
    }
    [IO.File]::WriteAllText($reviewReceipt, (($reviewData | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    $review = (& $engine -Action AddReview -ProjectDirectory $ProjectPath -RunDirectory $RunDirectory -ReceiptPath $reviewReceipt -ExpectedLedgerSha256 $currentLedgerSha -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $validation = (& $engine -Action ValidateRun -ProjectDirectory $ProjectPath -RunDirectory $RunDirectory -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    if ([string]$validation.verdict -ne 'PASS' -or -not [bool]$validation.compile_ready) { throw 'BATCH_APPEND_RUN_NOT_GATE_READY' }
    return [pscustomobject]@{CandidateId=$candidateId;LedgerSha256=[string]$review.ledger_sha256;RunId=[string]$runData.run_id}
}
try {
    $noReviewProject = Join-Path $temporary 'project-no-editorial-review'
    New-Item -ItemType Directory -Path $noReviewProject -Force | Out-Null
    $noReviewFixture = (& $PythonPath $fixtureScript --project $noReviewProject --source-kind txt --omit-review) | ConvertFrom-Json -DateKind String
    if ($LASTEXITCODE -ne 0) { throw 'NO_REVIEW_FIXTURE_BUILD_FAILED' }
    try {
        & $compiler -Action Preview -ProjectPath $noReviewProject -RunDirectory $noReviewFixture.run_dir -ExpectedLedgerSha256 $noReviewFixture.ledger_sha256 -OutputDirectory (Join-Path $noReviewFixture.run_dir 'must-fail-no-review') -PythonPath $PythonPath | Out-Null
        throw 'MISSING_EDITORIAL_REVIEW_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'COMPILE_GATE_FAIL: editorial_review_ready') { throw }
    }

    $fixture = (& $PythonPath $fixtureScript --project $project) | ConvertFrom-Json -DateKind String
    if ($LASTEXITCODE -ne 0) { throw 'FIXTURE_BUILD_FAILED' }
    $previewDir = Join-Path $fixture.run_dir 'system-v7-preview-001'
    $preview = & $compiler -Action Preview -ProjectPath $project -RunDirectory $fixture.run_dir -ExpectedLedgerSha256 $fixture.ledger_sha256 -OutputDirectory $previewDir -PythonPath $PythonPath
    if ($preview.Status -ne 'PREVIEW_READY' -or $preview.Cards -ne 1) { throw 'PREVIEW_RESULT_INVALID' }
    $handcraftedPreview = Join-Path $previewDir 'K1-COMPILED-HANDCRAFTED-VALID.md'
    $handcraftedText = (Get-Content -LiteralPath $preview.PreviewPath -Raw -Encoding UTF8).Replace('wygenerowano przez K1-Lite V2','ręcznie spreparowano')
    [IO.File]::WriteAllText($handcraftedPreview, $handcraftedText, [Text.UTF8Encoding]::new($false))
    $handcraftedCheck = & $validator -ProjectPath $project -EvidencePath $handcraftedPreview -PendingReview -NoExit
    if ($handcraftedCheck.Errors -gt 0 -or -not $handcraftedCheck.ReadyForImport) { throw 'HANDCRAFTED_PREVIEW_TEST_FIXTURE_NOT_STRUCTURALLY_VALID' }
    try {
        & $compiler -Action Publish -ProjectPath $project -RunDirectory $fixture.run_dir -ExpectedLedgerSha256 $fixture.ledger_sha256 -PreviewPath $handcraftedPreview -ExpectedPreviewSha256 (Get-FileHash -LiteralPath $handcraftedPreview -Algorithm SHA256).Hash -PythonPath $PythonPath | Out-Null
        throw 'HANDCRAFTED_PREVIEW_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'PUBLISH_DERIVATION_MISMATCH') { throw }
    }
    Assert-NoPublishVerificationDirectory $fixture.run_dir
    $published = & $compiler -Action Publish -ProjectPath $project -RunDirectory $fixture.run_dir -ExpectedLedgerSha256 $fixture.ledger_sha256 -PreviewPath $preview.PreviewPath -ExpectedPreviewSha256 $preview.PreviewSha256 -PythonPath $PythonPath
    Assert-NoPublishVerificationDirectory $fixture.run_dir
    if ($published.Status -ne 'PUBLISHED_CREATE_NEW' -or $published.Cards -ne 1) { throw 'PUBLISH_RESULT_INVALID' }
    $singleReceiptState = Assert-PublishReceiptState $project 'SINGLE' 1
    if ($published.PublishReceiptSha256 -ne $singleReceiptState.Sha256) { throw 'SINGLE_PUBLISH_RECEIPT_RESULT_MISMATCH' }
    if ((Get-Content -LiteralPath (Join-Path $project '01-baza-dowodow.md') -Raw -Encoding UTF8) -notmatch '(?m)^\| Q-001 \| POKRYTY \| #P-001 \|') { throw 'K0_TARGET_NOT_COMPILED' }
    $validation = & $validator -ProjectPath $project -NoExit
    if (-not $validation.GateReady -or $validation.ManualCheckCards -ne 0) { throw 'FINAL_GATE_NOT_READY' }
    $canonicalForReceiptTest = Join-Path $project '01-baza-dowodow.md'
    $canonicalReceiptBytes = [IO.File]::ReadAllBytes($canonicalForReceiptTest)
    try {
        [IO.File]::AppendAllText($canonicalForReceiptTest, "`r`nTAMPER`r`n", [Text.UTF8Encoding]::new($false))
        try {
            Assert-K1PublishReceiptCurrent -ProjectPath $project -ReceiptRelative ([string]$singleReceiptState.Data.publication_run_relative + '/publish-receipt.json') -ExpectedReceiptSha256 $singleReceiptState.Sha256 | Out-Null
            throw 'CANONICAL_TAMPER_WAS_NOT_BLOCKED_BY_PUBLISH_RECEIPT'
        } catch {
            if ($_.Exception.Message -notmatch 'K1_PUBLISH_ARTIFACT_BINDING_INVALID') { throw }
        }
    } finally {
        [IO.File]::WriteAllBytes($canonicalForReceiptTest, $canonicalReceiptBytes)
    }
    $fullVisualPath = Join-Path $fixture.run_dir 'qa\full.png'
    $fullVisualBytes = [IO.File]::ReadAllBytes($fullVisualPath)
    try {
        [IO.File]::WriteAllBytes($fullVisualPath, [byte[]](9,8,7,6))
        try {
            Invoke-K1FreshLineageGates -EnginePath $engine -ProjectPath $project -Lineage @($singleReceiptState.Lineage) -PythonPath $PythonPath | Out-Null
            throw 'VISUAL_TAMPER_WAS_NOT_BLOCKED_BY_FRESH_VALIDATE_RUN'
        } catch {
            if ($_.Exception.Message -notmatch 'K1_SOURCE_GATE_FAIL: .*:selected_visual_ready') { throw }
        }
    } finally {
        [IO.File]::WriteAllBytes($fullVisualPath, $fullVisualBytes)
    }
    $reusedPublish = & $compiler -Action Publish -ProjectPath $project -RunDirectory $fixture.run_dir -ExpectedLedgerSha256 $fixture.ledger_sha256 -PreviewPath $preview.PreviewPath -ExpectedPreviewSha256 $preview.PreviewSha256 -PythonPath $PythonPath
    if ([string]$reusedPublish.Status -cne 'PUBLISHED_RECOVERED_OR_REUSED') { throw 'IDENTICAL_PUBLISH_WAS_NOT_REUSED' }
    if ([string]$reusedPublish.PublishReceiptSha256 -ne $singleReceiptState.Sha256 -or
        -not ([IO.Path]::GetFullPath([string]$reusedPublish.PublishReceipt)).Equals([IO.Path]::GetFullPath([string]$singleReceiptState.Path), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'IDENTICAL_PUBLISH_RECEIPT_CHANGED'
    }
    if ((Get-FileHash -LiteralPath $canonicalForReceiptTest -Algorithm SHA256).Hash -ne $preview.PreviewSha256) { throw 'IDENTICAL_PUBLISH_CANONICAL_CHANGED' }
    $secondFixture = (& $PythonPath $fixtureScript --project $project --run-name fixture-run-2 --candidate second --source-stem supplement) | ConvertFrom-Json -DateKind String
    if ($LASTEXITCODE -ne 0) { throw 'SECOND_FIXTURE_BUILD_FAILED' }
    # Suplement jest legalny wyłącznie w oknie K2B. Fixture bazowy kończy
    # publikację K1 na etapie K1, więc test jawnie przechodzi do właściwego
    # etapu przed pierwszą próbą Merge i utrzymuje ten stan dla całej serii.
    $supplementMetaPath = Join-Path $project 'meta.md'
    $supplementMeta = Get-Content -LiteralPath $supplementMetaPath -Raw -Encoding UTF8
    $supplementMeta = [regex]::Replace($supplementMeta, '(?m)^CURRENT_STAGE:\s*.*$', 'CURRENT_STAGE: K2B')
    [IO.File]::WriteAllText($supplementMetaPath, $supplementMeta, [Text.UTF8Encoding]::new($false))
    $supplementDir = Join-Path $secondFixture.run_dir 'system-v7-supplement-001'
    $canonicalPath = Join-Path $project '01-baza-dowodow.md'
    $canonicalGood = Get-Content -LiteralPath $canonicalPath -Raw -Encoding UTF8
    [IO.File]::WriteAllText($canonicalPath, $canonicalGood.Replace('SATURATION_CHECK: PASS','SATURATION_CHECK: NIEURUCHOMIONY'), [Text.UTF8Encoding]::new($false))
    try {
        & $merger -Action Preview -ProjectPath $project -RunDirectory $secondFixture.run_dir -ExpectedLedgerSha256 $secondFixture.ledger_sha256 -OutputDirectory $supplementDir -PythonPath $PythonPath | Out-Null
        throw 'NON_GATE_READY_BASE_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'CANONICAL_NOT_GATE_READY') { throw }
    }
    [IO.File]::WriteAllText($canonicalPath, $canonicalGood, [Text.UTF8Encoding]::new($false))
    $orphanFixture = (& $PythonPath $fixtureScript --project $project --run-name fixture-run-orphan --candidate second --source-stem orphan) | ConvertFrom-Json -DateKind String
    if ($LASTEXITCODE -ne 0) { throw 'ORPHAN_FIXTURE_BUILD_FAILED' }
    try {
        & $merger -Action Preview -ProjectPath $project -RunDirectory $secondFixture.run_dir -ExpectedLedgerSha256 $secondFixture.ledger_sha256 -OutputDirectory $supplementDir -PythonPath $PythonPath | Out-Null
        throw 'UNANALYSED_SUPPLEMENT_FILE_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'SUPPLEMENT_UNANALYSED_FILES') { throw }
    }
    [IO.File]::Delete((Join-Path $project 'sources\orphan.pdf'))
    [IO.File]::Delete((Join-Path $project 'sources\orphan--TEXT.md'))
    [IO.Directory]::Delete([string]$orphanFixture.run_dir, $true)
    $supplement = & $merger -Action Preview -ProjectPath $project -RunDirectory $secondFixture.run_dir -ExpectedLedgerSha256 $secondFixture.ledger_sha256 -OutputDirectory $supplementDir -PythonPath $PythonPath
    if ($supplement.Status -ne 'SUPPLEMENT_PREVIEW_READY' -or $supplement.AddedCards -ne 1) { throw 'SUPPLEMENT_PREVIEW_INVALID' }
    $supplementPreviewText = Get-Content -LiteralPath $supplement.PreviewPath -Raw -Encoding UTF8
    if ($supplementPreviewText -notmatch '(?m)^\|\s*Q-001\s*\|\s*POKRYTY\s*\|\s*#P-001,\s*#P-002\s*\|') { throw 'SUPPLEMENT_PREVIEW_COVERAGE_NOT_UPDATED' }
    $handcraftedSupplement = Join-Path $supplementDir 'K1-COMPILED-SUPPLEMENT-HANDCRAFTED-VALID.md'
    $handcraftedSupplementText = (Get-Content -LiteralPath $supplement.PreviewPath -Raw -Encoding UTF8).Replace('wygenerowano przez K1-Lite V2','ręcznie spreparowano')
    [IO.File]::WriteAllText($handcraftedSupplement, $handcraftedSupplementText, [Text.UTF8Encoding]::new($false))
    $handcraftedSupplementCheck = & $validator -ProjectPath $project -EvidencePath $handcraftedSupplement -PendingReview -NoExit
    if ($handcraftedSupplementCheck.Errors -gt 0 -or -not $handcraftedSupplementCheck.ReadyForImport) { throw 'HANDCRAFTED_SUPPLEMENT_TEST_FIXTURE_NOT_STRUCTURALLY_VALID' }
    try {
        & $merger -Action Publish -ProjectPath $project -RunDirectory $secondFixture.run_dir -ExpectedLedgerSha256 $secondFixture.ledger_sha256 -PreviewPath $handcraftedSupplement -ExpectedPreviewSha256 (Get-FileHash -LiteralPath $handcraftedSupplement -Algorithm SHA256).Hash -ExpectedCanonicalSha256 $supplement.CanonicalSha256 -PythonPath $PythonPath | Out-Null
        throw 'HANDCRAFTED_SUPPLEMENT_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'SUPPLEMENT_DERIVATION_MISMATCH') { throw }
    }
    Assert-NoPublishVerificationDirectory $secondFixture.run_dir
    $expectedBackup = Join-Path $supplementDir ("canonical-before-supplement-$($supplement.CanonicalSha256).md")
    [IO.File]::WriteAllText($expectedBackup, 'corrupt', [Text.UTF8Encoding]::new($false))
    try {
        & $merger -Action Publish -ProjectPath $project -RunDirectory $secondFixture.run_dir -ExpectedLedgerSha256 $secondFixture.ledger_sha256 -PreviewPath $supplement.PreviewPath -ExpectedPreviewSha256 $supplement.PreviewSha256 -ExpectedCanonicalSha256 $supplement.CanonicalSha256 -PythonPath $PythonPath | Out-Null
        throw 'CORRUPT_RECOVERY_BACKUP_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'RECOVERY_BACKUP_HASH_MISMATCH') { throw }
    }
    [IO.File]::Delete($expectedBackup)
    $supplementPublished = & $merger -Action Publish -ProjectPath $project -RunDirectory $secondFixture.run_dir -ExpectedLedgerSha256 $secondFixture.ledger_sha256 -PreviewPath $supplement.PreviewPath -ExpectedPreviewSha256 $supplement.PreviewSha256 -ExpectedCanonicalSha256 $supplement.CanonicalSha256 -PythonPath $PythonPath
    Assert-NoPublishVerificationDirectory $secondFixture.run_dir
    if ($supplementPublished.Status -ne 'SUPPLEMENT_PUBLISHED_ADD_ONLY' -or $supplementPublished.Cards -ne 2) { throw 'SUPPLEMENT_PUBLISH_INVALID' }
    $supplementReceiptState = Assert-PublishReceiptState $project 'SUPPLEMENT' 2
    if ($supplementPublished.PublishReceiptSha256 -ne $supplementReceiptState.Sha256) { throw 'SUPPLEMENT_PUBLISH_RECEIPT_RESULT_MISMATCH' }
    if (-not (Test-Path -LiteralPath $supplementPublished.RecoveryBackup -PathType Leaf)) { throw 'SUPPLEMENT_RECOVERY_BACKUP_MISSING' }
    if ((Get-FileHash -LiteralPath $supplementPublished.RecoveryBackup -Algorithm SHA256).Hash -ne $supplement.CanonicalSha256) { throw 'SUPPLEMENT_RECOVERY_BACKUP_HASH_INVALID' }
    $supplementValidation = & $validator -ProjectPath $project -NoExit
    if (-not $supplementValidation.GateReady -or $supplementValidation.Cards -ne 2) { throw 'SUPPLEMENT_FINAL_GATE_NOT_READY' }
    $canonicalText = Get-Content -LiteralPath (Join-Path $project '01-baza-dowodow.md') -Raw -Encoding UTF8
    if ($canonicalText -notmatch '(?m)^\|\s*Q-001\s*\|\s*POKRYTY\s*\|\s*#P-001,\s*#P-002\s*\|') { throw 'SUPPLEMENT_PUBLISHED_COVERAGE_NOT_UPDATED' }
    if (([regex]::Matches($canonicalText, '(?m)^\| #S-\d{3}\s+\|')).Count -ne 4) { throw 'SUPPLEMENT_NEW_SOURCE_ROWS_NOT_PRESERVED' }
    if ($canonicalText -notmatch '(?ms)^### #P-002.*?^ŹRÓDŁO_ID:\s*#S-003\s*$') { throw 'SUPPLEMENT_NEW_CARD_SOURCE_REMAP_INVALID' }
    $firstAggregateRel = [regex]::Match($canonicalText, '(?m)^K1_EXPORT_PATH:\s*(?<v>.+?)\s*$').Groups['v'].Value
    $firstAggregateHash = [regex]::Match($canonicalText, '(?m)^K1_EXPORT_SHA256:\s*(?<v>[A-Fa-f0-9]{64})\s*$').Groups['v'].Value.ToUpperInvariant()
    $firstAggregateLedger = [IO.Path]::GetFullPath((Join-Path $project $firstAggregateRel))
    if (-not (Test-Path -LiteralPath $firstAggregateLedger -PathType Leaf) -or (Get-FileHash -LiteralPath $firstAggregateLedger -Algorithm SHA256).Hash -ne $firstAggregateHash) { throw 'SUPPLEMENT_AGGREGATE_LEDGER_NOT_HASH_BOUND' }
    $firstAggregateCandidates = @(Get-Content -LiteralPath $firstAggregateLedger -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String } | Where-Object event_type -eq 'candidate')
    if ($firstAggregateCandidates.Count -ne 2) { throw 'SUPPLEMENT_BASE_LINEAGE_WAS_NOT_PRESERVED' }

    $nativeSupplementFixture = (& $PythonPath $fixtureScript --project $project --run-name fixture-run-native-supplement --candidate second --source-stem native-supplement --source-kind txt) | ConvertFrom-Json -DateKind String
    if ($LASTEXITCODE -ne 0) { throw 'NATIVE_SUPPLEMENT_FIXTURE_BUILD_FAILED' }
    $nativeSupplementDir = Join-Path $nativeSupplementFixture.run_dir 'system-v7-supplement-native'

    # Opublikowany wcześniej run pozostaje append-only. Dodajemy świeży,
    # poprawny receipt recenzji po pierwszej publikacji suplementu, aby hash
    # fizycznego ledgeru różnił się od historycznego hasha w bazowym receipcie.
    $publishedSourceLedger = Join-Path $fixture.run_dir 'ledger.jsonl'
    $historicalPublishedSourceBytes = [IO.File]::ReadAllBytes($publishedSourceLedger)
    $appendReviewView = Join-Path $fixture.run_dir 'views\append-only-regression-review'
    $appendReviewReport = (& $engine -Action BuildViews -ProjectDirectory $project -RunDirectory $fixture.run_dir -OutputDirectory $appendReviewView -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $appendReviewArtifact = Join-Path $appendReviewView 'editorial-review.md'
    $appendReviewReceipt = Join-Path $fixture.run_dir 'incoming\append-only-regression-review.json'
    $appendReviewReceiptData = [ordered]@{
        schema = 'K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1'
        run_id = [string](Get-Content -LiteralPath (Join-Path $fixture.run_dir 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String).run_id
        snapshot_sha256 = [string]$appendReviewReport.editorial_review.snapshot_sha256
        review_artifact_relative = ([IO.Path]::GetRelativePath($fixture.run_dir, $appendReviewArtifact)).Replace('\','/')
        review_artifact_sha256 = (Get-FileHash -LiteralPath $appendReviewArtifact -Algorithm SHA256).Hash
        actor = 'DAWID'
        verdict = 'REVIEWED'
        note = 'Regresja bezpiecznego rozszerzenia append-only po publikacji.'
    }
    [IO.File]::WriteAllText($appendReviewReceipt, (($appendReviewReceiptData | ConvertTo-Json -Depth 5) + "`n"), [Text.UTF8Encoding]::new($false))
    $appendReviewResult = (& $engine -Action AddReview -ProjectDirectory $project -RunDirectory $fixture.run_dir -ReceiptPath $appendReviewReceipt -ExpectedLedgerSha256 (Get-FileHash -LiteralPath $publishedSourceLedger -Algorithm SHA256).Hash -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $currentPublishedSourceSha = [string]$appendReviewResult.ledger_sha256
    if ($currentPublishedSourceSha -eq $singleReceiptState.Data.source_lineage[0].ledger_sha256 -or
        (Get-FileHash -LiteralPath $publishedSourceLedger -Algorithm SHA256).Hash -ne $currentPublishedSourceSha) {
        throw 'APPEND_ONLY_REGRESSION_LEDGER_WAS_NOT_EXTENDED'
    }

    # Sama zgodność strukturalna JSONL nie wystarcza: modyfikacja dowolnego
    # historycznego bajtu ma być odrzucona, nawet gdy na końcu pozostaje legalny
    # nowy rekord.
    $validAppendedLedgerBytes = [IO.File]::ReadAllBytes($publishedSourceLedger)
    try {
        $mutatedLedgerText = [Text.UTF8Encoding]::new($false, $true).GetString($validAppendedLedgerBytes).Replace('Kluczowy dowód testowy.','Xluchowy dowód testowy.')
        if ($mutatedLedgerText -notmatch 'Xluchowy dowód testowy\.') { throw 'APPEND_ONLY_MUTATION_FIXTURE_INVALID' }
        [IO.File]::WriteAllText($publishedSourceLedger, $mutatedLedgerText, [Text.UTF8Encoding]::new($false))
        try {
            & $merger -Action Preview -ProjectPath $project -RunDirectory $nativeSupplementFixture.run_dir -ExpectedLedgerSha256 $nativeSupplementFixture.ledger_sha256 -OutputDirectory $nativeSupplementDir -PythonPath $PythonPath | Out-Null
            throw 'MUTATED_HISTORY_PREFIX_WAS_NOT_BLOCKED'
        } catch {
            if ($_.Exception.Message -notmatch 'K1_SOURCE_LINEAGE_LEDGER_SHA_MISMATCH') { throw }
        }
    } finally {
        [IO.File]::WriteAllBytes($publishedSourceLedger, $validAppendedLedgerBytes)
    }
    if ([IO.File]::ReadAllBytes($publishedSourceLedger).Length -le $historicalPublishedSourceBytes.Length) { throw 'APPEND_ONLY_REGRESSION_PREFIX_NOT_LONGER' }

    $nativeSupplement = & $merger -Action Preview -ProjectPath $project -RunDirectory $nativeSupplementFixture.run_dir -ExpectedLedgerSha256 $nativeSupplementFixture.ledger_sha256 -OutputDirectory $nativeSupplementDir -PythonPath $PythonPath
    if ($nativeSupplement.Status -ne 'SUPPLEMENT_PREVIEW_READY' -or $nativeSupplement.AddedCards -ne 1) { throw 'NATIVE_SUPPLEMENT_PREVIEW_INVALID' }
    $nativeSupplementText = Get-Content -LiteralPath $nativeSupplement.PreviewPath -Raw -Encoding UTF8
    if ($nativeSupplementText -notmatch '(?m)^LOKALIZACJA:\s*L4-L4\s*$' -or $nativeSupplementText -notmatch '(?m)^LOCATOR_POLICY:\s*MIXED_V1\s*$') { throw 'NATIVE_SUPPLEMENT_LOCATOR_INVALID' }
    $nativeSupplementPublished = & $merger -Action Publish -ProjectPath $project -RunDirectory $nativeSupplementFixture.run_dir -ExpectedLedgerSha256 $nativeSupplementFixture.ledger_sha256 -PreviewPath $nativeSupplement.PreviewPath -ExpectedPreviewSha256 $nativeSupplement.PreviewSha256 -ExpectedCanonicalSha256 $nativeSupplement.CanonicalSha256 -PythonPath $PythonPath
    $nativeSupplementValidation = & $validator -ProjectPath $project -NoExit
    if ($nativeSupplementPublished.Status -ne 'SUPPLEMENT_PUBLISHED_ADD_ONLY' -or $nativeSupplementPublished.Cards -ne 3 -or -not $nativeSupplementValidation.GateReady) { throw 'NATIVE_SUPPLEMENT_FINAL_GATE_NOT_READY' }
    $nativeSupplementReceiptState = Assert-PublishReceiptState $project 'SUPPLEMENT' 3
    if ($nativeSupplementPublished.PublishReceiptSha256 -ne $nativeSupplementReceiptState.Sha256) { throw 'NATIVE_SUPPLEMENT_PUBLISH_RECEIPT_RESULT_MISMATCH' }
    $nativeCanonicalText = Get-Content -LiteralPath (Join-Path $project '01-baza-dowodow.md') -Raw -Encoding UTF8
    $nativeAggregateRel = [regex]::Match($nativeCanonicalText, '(?m)^K1_EXPORT_PATH:\s*(?<v>.+?)\s*$').Groups['v'].Value
    $nativeAggregateLedger = [IO.Path]::GetFullPath((Join-Path $project $nativeAggregateRel))
    $nativeAggregateCandidates = @(Get-Content -LiteralPath $nativeAggregateLedger -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String } | Where-Object event_type -eq 'candidate')
    if ($nativeAggregateCandidates.Count -ne 3 -or (Get-FileHash -LiteralPath $nativeAggregateLedger -Algorithm SHA256).Hash -ne $nativeSupplementPublished.LedgerSha256) { throw 'NATIVE_SUPPLEMENT_FULL_LINEAGE_INVALID' }
    $nativeAggregateRunData = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $nativeAggregateLedger) 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    $publishedSourceRunId = [string](Get-Content -LiteralPath (Join-Path $fixture.run_dir 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String).run_id
    $publishedSourceIndex = [Array]::IndexOf([object[]]@($nativeAggregateRunData.source_runs), $publishedSourceRunId)
    if ($publishedSourceIndex -lt 0 -or [string]$nativeAggregateRunData.source_ledger_sha256s[$publishedSourceIndex] -ne $currentPublishedSourceSha) {
        throw 'APPEND_ONLY_CURRENT_SOURCE_HASH_NOT_REFRESHED'
    }
    if ([string]$nativeSupplementReceiptState.Data.source_lineage[$publishedSourceIndex].ledger_sha256 -ne $currentPublishedSourceSha) {
        throw 'APPEND_ONLY_CURRENT_SOURCE_HASH_NOT_BOUND_IN_RECEIPT'
    }
    $nativeAggregateReviews = @(Get-Content -LiteralPath $nativeAggregateLedger -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String } | Where-Object event_type -eq 'editorial_review_receipt')
    if ($nativeAggregateReviews.Count -lt 3) { throw 'APPEND_ONLY_CURRENT_LEDGER_NOT_MATERIALIZED_IN_AGGREGATE' }

    # Ten sam opublikowany run może później dostać nowego kandydata. Merger ma
    # wówczas wziąć tylko logiczny przyrost, nie duplikować run_id, a nowy
    # aggregate ma zmaterializować pełny aktualny ledger dokładnie raz.
    $nativeRunData = Get-Content -LiteralPath (Join-Path $nativeSupplementFixture.run_dir 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    $nativeChunk = Get-Content -LiteralPath (Join-Path $nativeSupplementFixture.run_dir 'chunks.jsonl') -Encoding UTF8 | Select-Object -First 1 | ConvertFrom-Json -DateKind String
    $nativeAppendResultPath = Join-Path $nativeSupplementFixture.run_dir 'incoming\append-existing-result.json'
    $nativeAppendResultData = [ordered]@{
        schema = 'K1_LITE_V2_WORKER_RESULT_V1'
        run_id = [string]$nativeRunData.run_id
        chunk_id = [string]$nativeChunk.chunk_id
        chunk_sha256 = [string]$nativeChunk.chunk_sha256
        continuation_no = 1
        status = 'CANDIDATE'
        more_strong_candidates = $false
        probe_answers = [ordered]@{}
        candidates = @([ordered]@{
            local_id = 'B'
            claim = 'Źródło podaje datę zdarzenia.'
            page = 'P0001'
            quote = 'The source states that the test event happened in 7640 bc.'
            category = 'TARGETED'
            k0_target = 'Q-001'
            film_value = 3
            risk = 1
            speaker_mode = 'AUTHOR_CLAIM'
            genealogy = 'Bezpośrednie twierdzenie źródła.'
            facts = @([ordered]@{ key='event_date'; value='7640 bc'; subject_terms=@('event','happened') })
        })
        metrics = [ordered]@{ model='gpt-5.6-luna'; effort='medium'; measurement='MEASURED'; input_tokens=300; cached_input_tokens=0; output_tokens=80; elapsed_ms=200; retry=0 }
    }
    [IO.File]::WriteAllText($nativeAppendResultPath, (($nativeAppendResultData | ConvertTo-Json -Depth 10) + "`n"), [Text.UTF8Encoding]::new($false))
    $nativeAppendImport = (& $engine -Action ImportResult -ProjectDirectory $project -RunDirectory $nativeSupplementFixture.run_dir -ResultPath $nativeAppendResultPath -ExpectedLedgerSha256 (Get-FileHash -LiteralPath (Join-Path $nativeSupplementFixture.run_dir 'ledger.jsonl') -Algorithm SHA256).Hash -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $nativeAppendCandidateId = "$([string]$nativeChunk.chunk_id)-01-B"
    $nativeAppendCandidate = Get-Content -LiteralPath (Join-Path $nativeSupplementFixture.run_dir 'ledger.jsonl') -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json -DateKind String } | Where-Object candidate_id -eq $nativeAppendCandidateId | Select-Object -First 1
    if ($null -eq $nativeAppendCandidate) { throw 'APPEND_EXISTING_CANDIDATE_NOT_IMPORTED' }
    $nativeAppendChatGptDecision = Join-Path $nativeSupplementFixture.run_dir 'incoming\append-existing-chatgpt.json'
    $nativeAppendChatGptDecisionData = [ordered]@{ schema='K1_LITE_V2_DECISION_BATCH_V1'; run_id=[string]$nativeRunData.run_id; decisions=@([ordered]@{ candidate_id=$nativeAppendCandidateId; decision='KEY_CHATGPT'; actor='CHATGPT'; reason='Kluczowy dowód regresji append-only.'; conflict_acknowledged=$false }) }
    [IO.File]::WriteAllText($nativeAppendChatGptDecision, (($nativeAppendChatGptDecisionData | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    $nativeAppendChatGpt = (& $engine -Action AddDecisions -ProjectDirectory $project -RunDirectory $nativeSupplementFixture.run_dir -DecisionPath $nativeAppendChatGptDecision -ExpectedLedgerSha256 ([string]$nativeAppendImport.ledger_sha256) -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $nativeAppendDawidDecision = Join-Path $nativeSupplementFixture.run_dir 'incoming\append-existing-dawid.json'
    $nativeAppendDawidDecisionData = [ordered]@{ schema='K1_LITE_V2_DECISION_BATCH_V1'; run_id=[string]$nativeRunData.run_id; decisions=@([ordered]@{ candidate_id=$nativeAppendCandidateId; decision='MUST_INCLUDE'; actor='DAWID'; reason='Dawid zatwierdza regresję append-only.'; conflict_acknowledged=$true }) }
    [IO.File]::WriteAllText($nativeAppendDawidDecision, (($nativeAppendDawidDecisionData | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    $nativeAppendDawid = (& $engine -Action AddDecisions -ProjectDirectory $project -RunDirectory $nativeSupplementFixture.run_dir -DecisionPath $nativeAppendDawidDecision -ExpectedLedgerSha256 ([string]$nativeAppendChatGpt.ledger_sha256) -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $nativeAppendReviewView = Join-Path $nativeSupplementFixture.run_dir 'views\append-existing-review'
    $nativeAppendReviewReport = (& $engine -Action BuildViews -ProjectDirectory $project -RunDirectory $nativeSupplementFixture.run_dir -OutputDirectory $nativeAppendReviewView -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $nativeAppendReviewArtifact = Join-Path $nativeAppendReviewView 'editorial-review.md'
    $nativeAppendReviewReceipt = Join-Path $nativeSupplementFixture.run_dir 'incoming\append-existing-review.json'
    $nativeAppendReviewReceiptData = [ordered]@{
        schema='K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1'; run_id=[string]$nativeRunData.run_id
        snapshot_sha256=[string]$nativeAppendReviewReport.editorial_review.snapshot_sha256
        review_artifact_relative=([IO.Path]::GetRelativePath($nativeSupplementFixture.run_dir,$nativeAppendReviewArtifact)).Replace('\','/')
        review_artifact_sha256=(Get-FileHash -LiteralPath $nativeAppendReviewArtifact -Algorithm SHA256).Hash
        actor='DAWID'; verdict='REVIEWED'; note='Dawid zatwierdza pełny aktualny snapshot po przyroście.'
    }
    [IO.File]::WriteAllText($nativeAppendReviewReceipt, (($nativeAppendReviewReceiptData | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
    $nativeAppendReview = (& $engine -Action AddReview -ProjectDirectory $project -RunDirectory $nativeSupplementFixture.run_dir -ReceiptPath $nativeAppendReviewReceipt -ExpectedLedgerSha256 ([string]$nativeAppendDawid.ledger_sha256) -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    $nativeAppendValidation = (& $engine -Action ValidateRun -ProjectDirectory $project -RunDirectory $nativeSupplementFixture.run_dir -PythonPath $PythonPath) | ConvertFrom-Json -DateKind String
    if ([string]$nativeAppendValidation.verdict -ne 'PASS' -or -not [bool]$nativeAppendValidation.compile_ready -or [int]$nativeAppendValidation.counts.selected -ne 2) { throw 'APPEND_EXISTING_RUN_NOT_GATE_READY' }

    # Drugi, wcześniej opublikowany run rozszerzamy jeszcze przed pierwszym
    # APPEND_EXISTING. Pierwszy publish odświeży więc hash obu runów naraz,
    # chociaż kartę tego drugiego do canonical dodamy dopiero w kolejnym kroku.
    $secondBatchAppend = Add-SelectedAppendCandidateFixture -ProjectPath $project -RunDirectory $fixture.run_dir -PdfVisual

    $appendExistingDir = Join-Path $nativeSupplementFixture.run_dir 'system-v7-supplement-append-existing'
    $appendExistingPreview = & $merger -Action Preview -ProjectPath $project -RunDirectory $nativeSupplementFixture.run_dir -ExpectedLedgerSha256 ([string]$nativeAppendReview.ledger_sha256) -OutputDirectory $appendExistingDir -PythonPath $PythonPath
    if ($appendExistingPreview.Status -ne 'SUPPLEMENT_PREVIEW_READY' -or $appendExistingPreview.AddedCards -ne 1) { throw 'APPEND_EXISTING_PREVIEW_INVALID' }
    $appendExistingPublish = & $merger -Action Publish -ProjectPath $project -RunDirectory $nativeSupplementFixture.run_dir -ExpectedLedgerSha256 ([string]$nativeAppendReview.ledger_sha256) -PreviewPath $appendExistingPreview.PreviewPath -ExpectedPreviewSha256 $appendExistingPreview.PreviewSha256 -ExpectedCanonicalSha256 $appendExistingPreview.CanonicalSha256 -PythonPath $PythonPath
    if ($appendExistingPublish.Status -ne 'SUPPLEMENT_PUBLISHED_ADD_ONLY' -or $appendExistingPublish.Cards -ne 4) { throw 'APPEND_EXISTING_PUBLISH_INVALID' }
    $appendExistingReceiptState = Assert-PublishReceiptState $project 'SUPPLEMENT' 3
    $appendExistingCanonical = Get-Content -LiteralPath (Join-Path $project '01-baza-dowodow.md') -Raw -Encoding UTF8
    if ($appendExistingCanonical -notmatch '(?m)^### #P-004\s*$') { throw 'APPEND_EXISTING_CARD_NOT_PUBLISHED' }
    $appendExistingRunData = Get-Content -LiteralPath (Join-Path $appendExistingDir 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    if ([string]$appendExistingRunData.supplement_mode -ne 'APPEND_EXISTING' -or
        @($appendExistingRunData.source_runs | Where-Object { [string]$_ -ceq [string]$nativeRunData.run_id }).Count -ne 1 -or
        [string]$appendExistingReceiptState.Data.supplement_mode -ne 'APPEND_EXISTING') {
        throw 'APPEND_EXISTING_LINEAGE_IDENTITY_INVALID'
    }
    $appendExistingLedgerEvents = @(Get-Content -LiteralPath (Join-Path $appendExistingDir 'ledger.jsonl') -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String })
    if (@($appendExistingLedgerEvents | Where-Object { $_.candidate_id -eq $nativeAppendCandidateId -and $_.run_id -eq $nativeRunData.run_id }).Count -ne 3) {
        throw 'APPEND_EXISTING_LEDGER_EVENT_MULTIPLICITY_INVALID'
    }
    $secondBatchIndexAfterFirstPublish = [Array]::IndexOf([object[]]@($appendExistingRunData.source_runs), [string]$secondBatchAppend.RunId)
    if ($secondBatchIndexAfterFirstPublish -lt 0 -or
        [string]$appendExistingRunData.source_ledger_sha256s[$secondBatchIndexAfterFirstPublish] -ne [string]$secondBatchAppend.LedgerSha256) {
        throw 'BATCH_SECOND_RUN_HASH_NOT_REFRESHED_BY_FIRST_PUBLISH'
    }

    $secondBatchDir = Join-Path $fixture.run_dir 'system-v7-supplement-batch-second'
    $secondBatchPreview = & $merger -Action Preview -ProjectPath $project -RunDirectory $fixture.run_dir -ExpectedLedgerSha256 ([string]$secondBatchAppend.LedgerSha256) -OutputDirectory $secondBatchDir -PythonPath $PythonPath
    if ($secondBatchPreview.Status -ne 'SUPPLEMENT_PREVIEW_READY' -or $secondBatchPreview.AddedCards -ne 1) { throw 'BATCH_SECOND_PREVIEW_INVALID' }
    $secondBatchPublish = & $merger -Action Publish -ProjectPath $project -RunDirectory $fixture.run_dir -ExpectedLedgerSha256 ([string]$secondBatchAppend.LedgerSha256) -PreviewPath $secondBatchPreview.PreviewPath -ExpectedPreviewSha256 $secondBatchPreview.PreviewSha256 -ExpectedCanonicalSha256 $secondBatchPreview.CanonicalSha256 -PythonPath $PythonPath
    if ($secondBatchPublish.Status -ne 'SUPPLEMENT_PUBLISHED_ADD_ONLY' -or $secondBatchPublish.Cards -ne 5) { throw 'BATCH_SECOND_PUBLISH_INVALID' }
    $secondBatchReceiptState = Assert-PublishReceiptState $project 'SUPPLEMENT' 3
    $secondBatchRunData = Get-Content -LiteralPath (Join-Path $secondBatchDir 'run.json') -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    if ([string]$secondBatchRunData.supplement_mode -ne 'APPEND_EXISTING' -or
        @($secondBatchRunData.source_runs | Where-Object { [string]$_ -ceq [string]$secondBatchAppend.RunId }).Count -ne 1 -or
        [string]$secondBatchReceiptState.Data.supplement_mode -ne 'APPEND_EXISTING') {
        throw 'BATCH_SECOND_LINEAGE_IDENTITY_INVALID'
    }
    $secondBatchCanonical = Get-Content -LiteralPath (Join-Path $project '01-baza-dowodow.md') -Raw -Encoding UTF8
    if ($secondBatchCanonical -notmatch '(?m)^### #P-005\s*$') { throw 'BATCH_SECOND_CARD_NOT_PUBLISHED' }
    $secondBatchLedgerEvents = @(Get-Content -LiteralPath (Join-Path $secondBatchDir 'ledger.jsonl') -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String })
    if (@($secondBatchLedgerEvents | Where-Object { $_.candidate_id -eq [string]$secondBatchAppend.CandidateId -and $_.run_id -eq [string]$secondBatchAppend.RunId }).Count -ne 4) {
        throw 'BATCH_SECOND_LEDGER_EVENT_MULTIPLICITY_INVALID'
    }

    $corpusProject = Join-Path $temporary 'corpus-project'
    New-Item -ItemType Directory -Path $corpusProject -Force | Out-Null
    $corpusA = (& $PythonPath $fixtureScript --project $corpusProject --run-name run-a --candidate first --source-stem book) | ConvertFrom-Json -DateKind String
    $corpusB = (& $PythonPath $fixtureScript --project $corpusProject --run-name run-b --candidate second --source-stem supplement) | ConvertFrom-Json -DateKind String
    try {
        & $compiler -Action Preview -ProjectPath $corpusProject -RunDirectory $corpusA.run_dir -ExpectedLedgerSha256 $corpusA.ledger_sha256 -OutputDirectory (Join-Path $corpusA.run_dir 'invalid-internal-preview') -PythonPath $PythonPath -InternalAllowCorpusSubset | Out-Null
        throw 'PUBLIC_INTERNAL_BYPASS_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'INTERNAL_CORPUS_SUBSET_UNAUTHORIZED') { throw }
    }
    try {
        & $compiler -Action Preview -ProjectPath $corpusProject -RunDirectory $corpusA.run_dir -ExpectedLedgerSha256 $corpusA.ledger_sha256 -OutputDirectory (Join-Path $corpusA.run_dir 'invalid-single-preview') -PythonPath $PythonPath | Out-Null
        throw 'SINGLE_RUN_CORPUS_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'CORPUS_REQUIRES_MULTI_RUN_COMPILER') { throw }
    }
    $corpusOut = Join-Path $corpusProject '_work\K1\k1-lite-v2\corpus-compile-001'
    $corpusPreview = & $corpusCompiler -ProjectPath $corpusProject -RunDirectories @($corpusA.run_dir,$corpusB.run_dir) -ExpectedLedgerSha256s @($corpusA.ledger_sha256,$corpusB.ledger_sha256) -OutputDirectory $corpusOut -PythonPath $PythonPath
    if ($corpusPreview.Status -ne 'CORPUS_PREVIEW_READY' -or $corpusPreview.Runs -ne 2 -or $corpusPreview.Cards -ne 2) { throw 'CORPUS_PREVIEW_RESULT_INVALID' }
    $handcraftedCorpus = Join-Path $corpusOut 'K1-COMPILED-CORPUS-HANDCRAFTED-VALID.md'
    $handcraftedCorpusText = (Get-Content -LiteralPath $corpusPreview.PreviewPath -Raw -Encoding UTF8).Replace('wygenerowano przez K1-Lite V2','ręcznie spreparowano')
    [IO.File]::WriteAllText($handcraftedCorpus, $handcraftedCorpusText, [Text.UTF8Encoding]::new($false))
    $handcraftedCorpusCheck = & $validator -ProjectPath $corpusProject -EvidencePath $handcraftedCorpus -PendingReview -NoExit
    if ($handcraftedCorpusCheck.Errors -gt 0 -or -not $handcraftedCorpusCheck.ReadyForImport) { throw 'HANDCRAFTED_CORPUS_TEST_FIXTURE_NOT_STRUCTURALLY_VALID' }
    try {
        & $compiler -Action Publish -ProjectPath $corpusProject -RunDirectory $corpusPreview.RunDirectory -ExpectedLedgerSha256 $corpusPreview.LedgerSha256 -PreviewPath $handcraftedCorpus -ExpectedPreviewSha256 (Get-FileHash -LiteralPath $handcraftedCorpus -Algorithm SHA256).Hash -PythonPath $PythonPath | Out-Null
        throw 'HANDCRAFTED_CORPUS_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'CORPUS_DERIVATION_MISMATCH') { throw }
    }
    Assert-NoPublishVerificationDirectory $corpusPreview.RunDirectory
    $corpusPublished = & $compiler -Action Publish -ProjectPath $corpusProject -RunDirectory $corpusPreview.RunDirectory -ExpectedLedgerSha256 $corpusPreview.LedgerSha256 -PreviewPath $corpusPreview.PreviewPath -ExpectedPreviewSha256 $corpusPreview.PreviewSha256 -PythonPath $PythonPath
    Assert-NoPublishVerificationDirectory $corpusPreview.RunDirectory
    if ($corpusPublished.Status -ne 'PUBLISHED_CREATE_NEW' -or $corpusPublished.Cards -ne 2) { throw 'CORPUS_PUBLISH_RESULT_INVALID' }
    $corpusReceiptState = Assert-PublishReceiptState $corpusProject 'CORPUS' 2
    if ($corpusPublished.PublishReceiptSha256 -ne $corpusReceiptState.Sha256) { throw 'CORPUS_PUBLISH_RECEIPT_RESULT_MISMATCH' }
    $corpusValidation = & $validator -ProjectPath $corpusProject -NoExit
    if (-not $corpusValidation.GateReady -or $corpusValidation.Cards -ne 2) { throw 'CORPUS_FINAL_GATE_NOT_READY' }
    $corpusCanonical = Join-Path $corpusProject '01-baza-dowodow.md'
    $corpusGood = Get-Content -LiteralPath $corpusCanonical -Raw -Encoding UTF8
    [IO.File]::WriteAllText($corpusCanonical, ($corpusGood -replace '#S-002','#S-005'), [Text.UTF8Encoding]::new($false))
    if ((& $validator -ProjectPath $corpusProject -NoExit).StructureVerdict -ne 'STRUCTURE_FAIL') { throw 'SOURCE_ID_GAP_WAS_NOT_BLOCKED' }
    [IO.File]::WriteAllText($corpusCanonical, ($corpusGood -replace '#P-002','#P-004'), [Text.UTF8Encoding]::new($false))
    if ((& $validator -ProjectPath $corpusProject -NoExit).StructureVerdict -ne 'STRUCTURE_FAIL') { throw 'CARD_ID_GAP_WAS_NOT_BLOCKED' }
    [IO.File]::WriteAllText($corpusCanonical, $corpusGood, [Text.UTF8Encoding]::new($false))

    # Samodzielny MD: pełna publikacja bez PDF i bez fikcyjnego potwierdzenia obrazu.
    $nativeProject = Join-Path $temporary 'native-project'
    New-Item -ItemType Directory -Path $nativeProject -Force | Out-Null
    $nativeFixture = (& $PythonPath $fixtureScript --project $nativeProject --run-name native-md --source-stem article --source-kind md) | ConvertFrom-Json -DateKind String
    if ($LASTEXITCODE -ne 0) { throw 'NATIVE_FIXTURE_BUILD_FAILED' }
    $nativePreview = & $compiler -Action Preview -ProjectPath $nativeProject -RunDirectory $nativeFixture.run_dir -ExpectedLedgerSha256 $nativeFixture.ledger_sha256 -OutputDirectory (Join-Path $nativeFixture.run_dir 'preview') -PythonPath $PythonPath
    $nativeText = Get-Content -LiteralPath $nativePreview.PreviewPath -Raw -Encoding UTF8
    if ($nativeText -notmatch '(?m)^LOKALIZACJA:\s*L2-L2\s*$') { throw 'NATIVE_LINE_LOCATOR_NOT_COMPILED' }
    if ($nativeText -notmatch '(?m)^\| #S-001 .*?\| D \| RDZEŃ \| L1-L4 \|') { throw 'NATIVE_SOURCE_CLASS_OR_RANGE_INVALID' }
    $nativePublished = & $compiler -Action Publish -ProjectPath $nativeProject -RunDirectory $nativeFixture.run_dir -ExpectedLedgerSha256 $nativeFixture.ledger_sha256 -PreviewPath $nativePreview.PreviewPath -ExpectedPreviewSha256 $nativePreview.PreviewSha256 -PythonPath $PythonPath
    $nativeValidation = & $validator -ProjectPath $nativeProject -NoExit
    if ($nativePublished.Status -ne 'PUBLISHED_CREATE_NEW' -or -not $nativeValidation.GateReady -or $nativeValidation.ManualCheckCards -ne 0) { throw 'NATIVE_FINAL_GATE_NOT_READY' }
    if ((Get-Content -LiteralPath (Join-Path $nativeProject 'meta.md') -Raw -Encoding UTF8) -notmatch '(?m)^K1_ENGINE_VERSION:\s*2\.1\.0\s*$') { throw 'NATIVE_ENGINE_VERSION_NOT_PUBLISHED' }
    [IO.File]::WriteAllText((Join-Path $nativeProject 'sources\technical.json'), '{"technical":true}', [Text.UTF8Encoding]::new($false))
    $nativeWithTechnical = & $validator -ProjectPath $nativeProject -NoExit
    if (-not $nativeWithTechnical.GateReady -or $nativeWithTechnical.SourceFiles -ne 1) { throw 'UNSUPPORTED_TECHNICAL_FILE_WAS_TREATED_AS_ACTIVE_SOURCE' }

    # Mieszany korpus: jedna para PDF+sidecar, jeden TXT i jedne napisy SRT.
    $mixedProject = Join-Path $temporary 'mixed-project'
    New-Item -ItemType Directory -Path $mixedProject -Force | Out-Null
    $mixedPdf = (& $PythonPath $fixtureScript --project $mixedProject --run-name mixed-pdf --source-stem book --source-kind pdf) | ConvertFrom-Json -DateKind String
    $mixedTxt = (& $PythonPath $fixtureScript --project $mixedProject --run-name mixed-txt --source-stem article --source-kind txt --candidate second) | ConvertFrom-Json -DateKind String
    $mixedSrt = (& $PythonPath $fixtureScript --project $mixedProject --run-name mixed-srt --source-stem captions --source-kind srt) | ConvertFrom-Json -DateKind String
    if ($LASTEXITCODE -ne 0) { throw 'MIXED_FIXTURE_BUILD_FAILED' }
    $mixedRuns = @($mixedPdf.run_dir,$mixedTxt.run_dir,$mixedSrt.run_dir)
    $mixedHashes = @($mixedPdf.ledger_sha256,$mixedTxt.ledger_sha256,$mixedSrt.ledger_sha256)

    [IO.File]::WriteAllText((Join-Path $mixedProject 'sources\technical.json'), '{"technical":true}', [Text.UTF8Encoding]::new($false))
    $nestedSourceDirectory = Join-Path $mixedProject 'sources\nested'
    [IO.Directory]::CreateDirectory($nestedSourceDirectory) | Out-Null
    [IO.File]::WriteAllText((Join-Path $nestedSourceDirectory 'blocked.md'), 'Wspierany format w podfolderze jest niedozwolony.', [Text.UTF8Encoding]::new($false))
    try {
        & $corpusCompiler -ProjectPath $mixedProject -RunDirectories $mixedRuns -ExpectedLedgerSha256s $mixedHashes -OutputDirectory (Join-Path $mixedProject '_work\K1\k1-lite-v2\mixed-nested') -PythonPath $PythonPath | Out-Null
        throw 'NESTED_SUPPORTED_SOURCE_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'SUPPORTED_SOURCE_IN_SUBDIRECTORY') { throw }
    }
    [IO.Directory]::Delete($nestedSourceDirectory, $true)

    $orphanPath = Join-Path $mixedProject 'sources\unanalysed.md'
    [IO.File]::WriteAllText($orphanPath, 'Niezależny aktywny plik wymaga własnego runu.', [Text.UTF8Encoding]::new($false))
    try {
        & $corpusCompiler -ProjectPath $mixedProject -RunDirectories $mixedRuns -ExpectedLedgerSha256s $mixedHashes -OutputDirectory (Join-Path $mixedProject '_work\K1\k1-lite-v2\mixed-with-orphan') -PythonPath $PythonPath | Out-Null
        throw 'MIXED_ORPHAN_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'CORPUS_UNANALYSED_FILES') { throw }
    }
    [IO.File]::Delete($orphanPath)

    try {
        & $corpusCompiler -ProjectPath $mixedProject -RunDirectories @($mixedPdf.run_dir,$mixedPdf.run_dir) -ExpectedLedgerSha256s @($mixedPdf.ledger_sha256,$mixedPdf.ledger_sha256) -OutputDirectory (Join-Path $mixedProject '_work\K1\k1-lite-v2\mixed-duplicate') -PythonPath $PythonPath | Out-Null
        throw 'DUPLICATE_LOGICAL_RUN_WAS_NOT_BLOCKED'
    } catch {
        if ($_.Exception.Message -notmatch 'CORPUS_FILE_COVERED_BY_MULTIPLE_RUNS') { throw }
    }

    $mixedOut = Join-Path $mixedProject '_work\K1\k1-lite-v2\mixed-valid'
    $mixedPreview = & $corpusCompiler -ProjectPath $mixedProject -RunDirectories $mixedRuns -ExpectedLedgerSha256s $mixedHashes -OutputDirectory $mixedOut -PythonPath $PythonPath
    if ($mixedPreview.Status -ne 'CORPUS_PREVIEW_READY' -or $mixedPreview.Runs -ne 3 -or $mixedPreview.Cards -ne 3 -or $mixedPreview.Sources -ne 4) { throw 'MIXED_CORPUS_PREVIEW_INVALID' }
    $mixedText = Get-Content -LiteralPath $mixedPreview.PreviewPath -Raw -Encoding UTF8
    if ($mixedText -notmatch '(?m)^LOCATOR_POLICY:\s*MIXED_V1\s*$' -or $mixedText -notmatch '(?m)^LOKALIZACJA:\s*L4-L4\s*$' -or $mixedText -notmatch '(?m)^LOKALIZACJA:\s*\[00:00:01\.000-00:00:05\.000\]\s*$') { throw 'MIXED_LOCATORS_NOT_COMPILED' }
    $mixedPublished = & $compiler -Action Publish -ProjectPath $mixedProject -RunDirectory $mixedPreview.RunDirectory -ExpectedLedgerSha256 $mixedPreview.LedgerSha256 -PreviewPath $mixedPreview.PreviewPath -ExpectedPreviewSha256 $mixedPreview.PreviewSha256 -PythonPath $PythonPath
    $mixedValidation = & $validator -ProjectPath $mixedProject -NoExit
    if ($mixedPublished.Status -ne 'PUBLISHED_CREATE_NEW' -or -not $mixedValidation.GateReady -or $mixedValidation.ManualCheckCards -ne 0) { throw 'MIXED_FINAL_GATE_NOT_READY' }
    $mixedCanonical = Join-Path $mixedProject '01-baza-dowodow.md'
    $mixedGood = Get-Content -LiteralPath $mixedCanonical -Raw -Encoding UTF8
    [IO.File]::WriteAllText($mixedCanonical, $mixedGood.Replace('LOKALIZACJA: L4-L4','LOKALIZACJA: P0001/L4-L4'), [Text.UTF8Encoding]::new($false))
    if ((& $validator -ProjectPath $mixedProject -NoExit).StructureVerdict -ne 'STRUCTURE_FAIL') { throw 'WRONG_TEXT_LOCATOR_KIND_WAS_NOT_BLOCKED' }
    [IO.File]::WriteAllText($mixedCanonical, $mixedGood.Replace('LOKALIZACJA: [00:00:01.000-00:00:05.000]','LOKALIZACJA: L1-L1'), [Text.UTF8Encoding]::new($false))
    if ((& $validator -ProjectPath $mixedProject -NoExit).StructureVerdict -ne 'STRUCTURE_FAIL') { throw 'WRONG_SUBTITLE_LOCATOR_KIND_WAS_NOT_BLOCKED' }
    [IO.File]::WriteAllText($mixedCanonical, $mixedGood.Replace('LOCATOR_POLICY: MIXED_V1','LOCATOR_POLICY: UNKNOWN'), [Text.UTF8Encoding]::new($false))
    if ((& $validator -ProjectPath $mixedProject -NoExit).StructureVerdict -ne 'STRUCTURE_FAIL') { throw 'INVALID_LOCATOR_POLICY_WAS_NOT_BLOCKED' }
    [IO.File]::WriteAllText($mixedCanonical, $mixedGood, [Text.UTF8Encoding]::new($false))
    'K1_LITE_V2_SYSTEM_INTEGRATION_PASS'
} finally {
    if (Test-Path -LiteralPath $temporary) { [IO.Directory]::Delete($temporary, $true) }
    [Environment]::SetEnvironmentVariable('PYTHONDONTWRITEBYTECODE', $previousNoBytecode, 'Process')
}
