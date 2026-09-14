param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$FixtureRoot
)
$ErrorActionPreference='Stop'
$systemRoot=[IO.Path]::GetFullPath($SystemRoot);$project=[IO.Path]::GetFullPath($ProjectPath);$fixture=[IO.Path]::GetFullPath($FixtureRoot)
$tools=Join-Path $systemRoot 'tools';[IO.Directory]::CreateDirectory($fixture)|Out-Null
. (Join-Path $tools 'Project-Origin.ps1')
. (Join-Path $tools 'Integrity-Receipts.ps1')
. (Join-Path $tools 'Narrative-Receipts.ps1')

function Write-Lf([string]$Path,[string]$Text){
    $value=ConvertTo-SystemV7LfText -Text $Text;if(-not $value.EndsWith("`n")){$value+="`n"}
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null
    [IO.File]::WriteAllText($Path,$value,[Text.UTF8Encoding]::new($false))
}
function Set-Meta([hashtable]$Values){
    $path=Join-Path $project 'meta.md';$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach($key in $Values.Keys){$text=Set-SystemV7NarrativeMetaField -Text $text -Name $key -Value ([string]$Values[$key])}
    Write-SystemV7NarrativeAtomicText -Path $path -Text $text|Out-Null
}
function Expect-Failure([scriptblock]$Action,[string]$Pattern){
    try{&$Action|Out-Null;return [pscustomobject]@{Pass=$false;Message='NO_ERROR'}}catch{return [pscustomobject]@{Pass=$_.Exception.Message -match $Pattern;Message=$_.Exception.Message}}
}
function Add-StatusRows($Rows){
    @($Rows|ForEach-Object{$copy=[ordered]@{};if($_ -is [Collections.IDictionary]){foreach($key in $_.Keys){$copy[[string]$key]=$_[$key]}}else{foreach($property in $_.PSObject.Properties){$copy[$property.Name]=$property.Value}};$copy.status='PASS';[pscustomobject]$copy})
}
function Machine-Rows([string]$Prefix,$Rows){
    $items=@($Rows|Where-Object{$null-ne$_});if($items.Count -eq 0){return "${Prefix}: BRAK"}
    (@(Add-StatusRows $items|ForEach-Object{"${Prefix}: $($_|ConvertTo-Json -Compress -Depth 32)"}) -join "`n")
}
function Machine-Body([string]$Prefix,$Rows,[string]$Analysis){(Machine-Rows $Prefix $Rows)+"`nANALYSIS: $Analysis"}
function New-VerifyText([string]$DraftSha,$Coverage,$Locators,[switch]$Generic){
    $coverageBody=if($Generic){'ANALYSIS: Ogólna deklaracja bez wymaganej zamkniętej mapy bloków i kart.'}else{Machine-Body 'COVERAGE_JSON' $Coverage 'Każdy blok porównano z dokładnym zestawem kart bez pominięć i obcych identyfikatorów.'}
    $locatorBody=Machine-Body 'LOCATOR_JSON' $Locators 'Każda użyta karta ma odtwarzalne źródło oraz dokładny lokalizator.'
@"
SCHEMA: K4_VERIFY_OUTPUT_V1
LENS: VERIFY
DRAFT_SHA256: $DraftSha
VERDICT: PASS
CRITICAL_COUNT: 0
MAJOR_COUNT: 0
MINOR_COUNT: 0
REVIEW_ALERT_COUNT: 0
## CLAIM_COVERAGE
$coverageBody
## SOURCE_LOCATORS_CHECKED
$locatorBody
## ATTRIBUTION_UNCERTAINTY
Atrybucje oraz poziom pewności pozostają zgodne z kartami i językiem narracji.
## CONTRADICTIONS
Porównanie wszystkich twierdzeń nie ujawniło sprzeczności zmieniających sens materiału.
## FINDINGS
BRAK
"@
}
function New-EditorText([string]$DraftSha,$Acts,$Nq,$Nr,$Vc,$Required,$Preflight,[switch]$Generic){
    $qr=(Machine-Rows 'NQ_JSON' $Nq)+"`n"+(Machine-Rows 'NR_JSON' $Nr)+"`nANALYSIS: Pytania i reveale mają jawne węzły, dowody oraz bloki realizacji."
    $actsBody=if($Generic){'ANALYSIS: Ogólna deklaracja bez dokładnych rekordów aktów.'}else{Machine-Body 'ACT_JSON' $Acts 'Każdy akt wiąże bloki, sceny oraz węzeł zmiany stanu.'}
@"
SCHEMA: K4_EDITOR_OUTPUT_V1
LENS: EDITOR
DRAFT_SHA256: $DraftSha
VERDICT: PASS
CRITICAL_COUNT: 0
MAJOR_COUNT: 0
MINOR_COUNT: 0
REVIEW_ALERT_COUNT: 0
## HOOK_AND_PROMISE
Otwarcie jasno przedstawia stawkę, obietnicę oraz konkretny kierunek dalszej narracji.
## QUESTION_REVEAL_LOGIC
$qr
## TWO_AXES_AND_STATE_CHANGE
$actsBody
## EXPOSITION_TRANSITIONS
$(Machine-Body 'REQUIRED_JSON' $Required 'Każdy wymagany dowód ma funkcję, konieczność oraz blok realizacji w odpowiednim akcie.')
## VOICE_VIEWER_CONTACT
    $((Machine-Rows 'VC_JSON' $Vc)+"`n"+(Machine-Rows 'PREFLIGHT_JSON' $Preflight)+"`nANALYSIS: Każdy kontakt i alert preflight sprawdzono względem funkcji, głosu oraz jawnie przypisanego bloku.")
## FINALE
Finał rozwiązuje główne pytanie, wypłaca obietnicę i pozostawia konkretny obraz.
## FINDINGS
BRAK
"@
}
function New-ColdText([string]$DraftSha,[switch]$BraK){
    $lines=[Collections.Generic.List[string]]::new();foreach($line in @('SCHEMA: K4_COLD_READER_OUTPUT_V1','LENS: COLD_READER',"DRAFT_SHA256: $DraftSha",'VERDICT: PASS','CRITICAL_COUNT: 0','MAJOR_COUNT: 0','MINOR_COUNT: 0','REVIEW_ALERT_COUNT: 0')){$lines.Add($line)}
    foreach($i in 1..10){$id='Q{0:D2}' -f $i;$response=if($BraK -and $i -eq 1){'BRAK'}else{"Odpowiedź $i jest konkretna i potwierdza czytelność narracji."};$lines.Add("${id}_RESPONSE: $response");$lines.Add("${id}_EVIDENCE: Konkretne zdanie narracji stanowi punkt odniesienia dla odpowiedzi $i.")}
    foreach($line in @('## CONFUSION_AND_DROPOFF','Narracja pozostaje czytelna i nie tworzy punktu porzucenia.','## PAYOFF_AND_MEMORY','Najważniejsza obietnica otrzymuje wyraźną i zapamiętywalną wypłatę na końcu opowieści dla widza.','## FINDINGS','BRAK')){$lines.Add($line)}
    ($lines -join "`n")+"`n"
}
function New-ImpactText([object]$Impact){
    $changed=@($Impact.changed_block_ids) -join ',';if([string]::IsNullOrWhiteSpace($changed)){$changed='BRAK'}
@"
SCHEMA: QA_IMPACT_OUTPUT_V1
DIFF_SHA256: $($Impact.diff_sha256)
OLD_DRAFT_SHA256: $($Impact.old_draft_sha256)
NEW_DRAFT_SHA256: $($Impact.new_draft_sha256)
CHANGE_CLASS: $($Impact.change_class)
CHANGED_BLOCK_IDS: $changed
EDITOR_DECISION: CARRYFORWARD_ALLOWED
EDITOR_REASON: Kontrolny review dopuszcza carry tylko po warunkiem niezmienionego deterministycznego odcisku zależności.
EDITOR_AFFECTED_SCOPE: Jedno zdanie testowe oraz kontrolowana zmiana semantic preflight.
EDITOR_CONFIDENCE: HIGH
VERIFY_DECISION: CARRYFORWARD_ALLOWED
VERIFY_REASON: Zmiana fixture nie dodaje nowego twierdzenia źródłowego ani lokalizatora.
VERIFY_AFFECTED_SCOPE: Brak zmiany kart i lokalizatorów w syntetycznym materiale.
VERIFY_CONFIDENCE: HIGH
COLD_READER_DECISION: CARRYFORWARD_ALLOWED
COLD_READER_REASON: Krótka zmiana kontrolna nie narusza czytelności syntetycznej narracji.
COLD_READER_AFFECTED_SCOPE: Jedno zdanie kontrolne bez zmiany konstrukcji aktu.
COLD_READER_CONFIDENCE: HIGH
"@
}
function Get-Bundle([string]$Manifest){
    $state=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $Manifest -RequireLiveSource
    if(-not $state.Valid){throw "K4_BUNDLE_INVALID: $($state.Errors -join '; ')"};$state
}
function New-RunReceipt([string]$RunId,[string]$Output,[string]$Task,[string]$Prompt,[char]$Settings,[string]$TelemetryPath=''){
    $arguments=@{ProjectPath=$project;RunId=$RunId;OutputPath=$Output;TaskId=$Task;ModelId='CHATGPT-CODEX-TEST';ModelRevision='NARRATIVE-V2-REGRESSION';ModelSettingsSha256=(([string]$Settings)*64);PromptRevision=$Prompt;ActorRole='CHATGPT_CODEX';StartedAt=[DateTimeOffset]::UtcNow.AddMinutes(-2);Note='Syntetyczny niezależny run trwałej regresji Narrative V2.'}
    if($TelemetryPath){$arguments.TelemetryPath=$TelemetryPath}
    & (Join-Path $tools 'New-NarrativeRunReceipt.ps1') @arguments|Out-Null
    Join-Path $project "_work\narrative-runs\$RunId\run-receipt.json"
}

$k3Preview=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project
if([string]$k3Preview.Mode -cne 'PREVIEW' -or [string]$k3Preview.FromStage -cne 'K3' -or [string]$k3Preview.ToStage -cne 'K4'){throw 'OFFICIAL_CHAIN_K3_PREVIEW_INVALID'}
$k3Apply=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -Apply
if([string]$k3Apply.Mode -cne 'APPLIED' -or [string]$k3Apply.FromStage -cne 'K3' -or [string]$k3Apply.ToStage -cne 'K4'){throw 'OFFICIAL_CHAIN_K3_APPLY_INVALID'}
$runIds=[ordered]@{Editor='EDITOR.REGRESSION.0001';Verify='VERIFY.REGRESSION.0001';Cold='COLD.REGRESSION.0001'}
$started=& (Join-Path $tools 'Start-K4Lenses.ps1') -ProjectPath $project -EditorRunId $runIds.Editor -VerifyRunId $runIds.Verify -ColdReaderRunId $runIds.Cold
$draftSha=[string]$started.DraftSha256
$editorBundle=Get-Bundle $started.EditorManifest;$verifyBundle=Get-Bundle $started.VerifyManifest;$coldBundle=Get-Bundle $started.ColdReaderManifest
$editorInventory=Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens EDITOR -BundleData $editorBundle.Data
$verifyInventory=Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens VERIFY -BundleData $verifyBundle.Data
if(-not $editorInventory.Valid -or -not $verifyInventory.Valid){throw "K4_INVENTORY_INVALID: $($editorInventory.Errors+$verifyInventory.Errors -join '; ')"}

$editorText=New-EditorText $draftSha $editorInventory.Acts $editorInventory.Questions $editorInventory.Reveals $editorInventory.ViewerContacts $editorInventory.Required $editorInventory.SemanticFindings
$verifyText=New-VerifyText $draftSha $verifyInventory.Coverage $verifyInventory.Locators
$coldText=New-ColdText $draftSha
$editorOutput=Get-SystemV7NarrativeExpectedRunOutputPath -ProjectPath $project -BundleData $editorBundle.Data
$verifyOutput=Get-SystemV7NarrativeExpectedRunOutputPath -ProjectPath $project -BundleData $verifyBundle.Data
$coldOutput=Get-SystemV7NarrativeExpectedRunOutputPath -ProjectPath $project -BundleData $coldBundle.Data
Write-Lf $editorOutput $editorText;Write-Lf $verifyOutput $verifyText;Write-Lf $coldOutput $coldText
$editorState=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens EDITOR -OutputPath $editorOutput -ExpectedDraftSha256 $draftSha -BundleData $editorBundle.Data
$verifyState=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens VERIFY -OutputPath $verifyOutput -ExpectedDraftSha256 $draftSha -BundleData $verifyBundle.Data
$coldState=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens COLD_READER -OutputPath $coldOutput -ExpectedDraftSha256 $draftSha -BundleData $coldBundle.Data
if(-not $editorState.Valid -or -not $verifyState.Valid -or -not $coldState.Valid){throw "K4_POSITIVE_OUTPUT_INVALID: $($editorState.Errors+$verifyState.Errors+$coldState.Errors -join '; ')"}

$negativeDir=Join-Path $fixture 'negative';[IO.Directory]::CreateDirectory($negativeDir)|Out-Null
$verifyMissing=Join-Path $negativeDir 'verify-missing.md';$missingCoverage=@($verifyInventory.Coverage);if($missingCoverage.Count -gt 0){$missingCoverage=@($missingCoverage[0..([math]::Max(0,$missingCoverage.Count-2))])};Write-Lf $verifyMissing (New-VerifyText $draftSha $missingCoverage $verifyInventory.Locators)
$verifyMissingState=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens VERIFY -OutputPath $verifyMissing -ExpectedDraftSha256 $draftSha -BundleData $verifyBundle.Data
$editorGeneric=Join-Path $negativeDir 'editor-generic.md';Write-Lf $editorGeneric (New-EditorText $draftSha $editorInventory.Acts $editorInventory.Questions $editorInventory.Reveals $editorInventory.ViewerContacts $editorInventory.Required $editorInventory.SemanticFindings -Generic)
$editorGenericState=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens EDITOR -OutputPath $editorGeneric -ExpectedDraftSha256 $draftSha -BundleData $editorBundle.Data
$coldBrak=Join-Path $negativeDir 'cold-brak.md';Write-Lf $coldBrak (New-ColdText $draftSha -BraK)
$coldBrakState=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens COLD_READER -OutputPath $coldBrak -ExpectedDraftSha256 $draftSha -BundleData $coldBundle.Data
if($verifyMissingState.Valid -or $editorGenericState.Valid -or $coldBrakState.Valid){throw 'K4_KEY_NEGATIVE_FALSE_PASS'}

$editorTelemetryPath=Join-Path $project "_work\narrative-runs\$($runIds.Editor)\provider-telemetry.json"
$editorTelemetry=[ordered]@{schema='MODEL_RUN_TELEMETRY_V1';input_tokens=1200;prefix_tokens=300;source_card_tokens=420;output_tokens=640;cache_read_tokens=0;cache_write_tokens=0;retry_count=0;cost_amount=$null;cost_currency='BRAK'}
Write-Lf -Path $editorTelemetryPath -Text (ConvertTo-SystemV7CanonicalJson -Value $editorTelemetry)
$verifyTelemetryPath=Join-Path $project "_work\narrative-runs\$($runIds.Verify)\provider-telemetry.json"
Write-Lf -Path $verifyTelemetryPath -Text '{NIEPOPRAWNA_TELEMETRIA'
$editorReceipt=New-RunReceipt $runIds.Editor $editorOutput 'TASK.EDITOR.REGRESSION.0001' 'EDITOR_V2' '1' $editorTelemetryPath
$verifyReceipt=New-RunReceipt $runIds.Verify $verifyOutput 'TASK.VERIFY.REGRESSION.0001' 'VERIFY_SOURCE_FIRST_V1' '2' $verifyTelemetryPath
$coldReceipt=New-RunReceipt $runIds.Cold $coldOutput 'TASK.COLD.REGRESSION.0001' 'COLD_READER_V1' '3'
$editorTelemetryReceiptState=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $editorReceipt -ExpectedRunType EDITOR -ExpectedDraftSha256 $draftSha
$verifyTelemetryReceiptState=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $verifyReceipt -ExpectedRunType VERIFY -ExpectedDraftSha256 $draftSha
$coldTelemetryReceiptState=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $coldReceipt -ExpectedRunType COLD_READER -ExpectedDraftSha256 $draftSha
$telemetryProviderPass=$editorTelemetryReceiptState.Valid -and [string]$editorTelemetryReceiptState.Data.telemetry.collection_status -ceq 'PROVIDER_REPORTED'
$cacheMissNonBlocking=$telemetryProviderPass -and [string]$editorTelemetryReceiptState.Data.telemetry.cache_status -ceq 'MISS'
$telemetryFailureNonBlocking=$verifyTelemetryReceiptState.Valid -and [string]$verifyTelemetryReceiptState.Data.telemetry.collection_status -ceq 'PROVIDER_REJECTED_NON_BLOCKING' -and [string]$verifyTelemetryReceiptState.Data.telemetry.provider_error_code -ceq 'INVALID_JSON_OR_SCHEMA' -and (Test-Path -LiteralPath $verifyOutput -PathType Leaf)
$telemetryDefaultPass=$coldTelemetryReceiptState.Valid -and [string]$coldTelemetryReceiptState.Data.telemetry.collection_status -ceq 'AUTOMATIC_ONLY'
foreach($state in @($telemetryProviderPass,$cacheMissNonBlocking,$telemetryFailureNonBlocking,$telemetryDefaultPass)){if(-not $state){throw "K4_TELEMETRY_ASSERT_FAILED: provider=$telemetryProviderPass cacheMiss=$cacheMissNonBlocking failureNonBlocking=$telemetryFailureNonBlocking default=$telemetryDefaultPass"}}
$compiled=& (Join-Path $tools 'Compile-K4ProofSet.ps1') -ProjectPath $project -EditorProofPath $editorReceipt -VerifyProofPath $verifyReceipt -ColdReaderProofPath $coldReceipt
$proof=Get-SystemV7K4ProofSetState -ProjectPath $project -ProofSetSha256 $compiled.ProofSetSha256 -ExpectedDraftSha256 $draftSha
if(-not $proof.Valid){throw "K4_PROOF_SET_INVALID: $($proof.Errors -join '; ')"}

# A legal EDITOR proof for draft A must never be carried to draft B when the
# deterministic semantic preflight changes, even if a QA-impact reviewer
# declares the prose delta carryable. This closes the stale semantic alert
# bypass at the public carry creator, not only at a lower-level hash helper.
$editorBundleDependency=Get-SystemV7K4LensBundleDependencyFingerprintState -ProjectPath $project -Lens EDITOR -BundleData $editorBundle.Data
$editorLiveDependencyA=Get-SystemV7K4LensLiveDependencyFingerprintState -ProjectPath $project -Lens EDITOR
if(-not $editorBundleDependency.Valid -or -not $editorLiveDependencyA.Valid -or [string]$editorBundleDependency.Sha256 -cne [string]$editorLiveDependencyA.Sha256){throw 'EDITOR_SEMANTIC_CARRY_BASELINE_DEPENDENCY_INVALID'}
$editorSemanticAEmpty=@($editorInventory.SemanticFindings).Count -eq 0
if(-not $editorSemanticAEmpty){throw 'EDITOR_SEMANTIC_CARRY_BASELINE_HAS_ALERT'}
$draftPathForCarry=Join-Path $project '03-draft.md';$voicePathForCarry=Join-Path $project '_work\k3\prefix\VOICE_EXEMPLARS.md'
$draftBytesForCarry=[IO.File]::ReadAllBytes($draftPathForCarry);$voiceBytesForCarry=[IO.File]::ReadAllBytes($voicePathForCarry)
$baselineA=& (Join-Path $tools 'Compare-DraftV2.ps1') -ProjectPath $project -SaveBaseline
$editorCarryDependencyRejected=$false;$editorCarryNoReceipt=$false;$editorSemanticBAlert=$false;$editorDependencyRestore=$false;$editorProofRestore=$false;$editorCarryError=''
try{
    $blocksForCarry=Get-Content -LiteralPath (Join-Path $project '_work\k3\acts\ACT-001\blocks.json') -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
    $firstProse=[string]$blocksForCarry.blocks[0].prose;$tokens=@([regex]::Matches($firstProse,'[\p{L}\p{N}]+')|ForEach-Object{$_.Value})
    if($tokens.Count -lt 8){throw 'EDITOR_SEMANTIC_CARRY_PROSE_TOO_SHORT'}
    $overlap=$tokens[0..7] -join ' '
    $voiceBefore=Get-Content -LiteralPath $voicePathForCarry -Raw -Encoding UTF8;Write-Lf -Path $voicePathForCarry -Text ($voiceBefore+"`n$overlap`n")
    $draftBefore=Get-Content -LiteralPath $draftPathForCarry -Raw -Encoding UTF8;Write-Lf -Path $draftPathForCarry -Text ($draftBefore+"`nTy widzisz ten kontrolny sygnał zmiany, ale nie jest on częścią dowodu.`n")
    $shaB=(Get-FileHash -LiteralPath $draftPathForCarry -Algorithm SHA256).Hash
    $semanticBlocks=@($blocksForCarry.blocks|ForEach-Object{[pscustomobject]@{act_id='ACT-001';block_id=[string]$_.block_id;narrative_refs=@([string[]]@($_.narrative_refs));prose=[string]$_.prose}})
    $architectureForCarry=Get-SystemV7NarrativeArchitecture -Path (Join-Path $project '02-architektura-odcinka.md')
    $semanticB=Get-SystemV7NarrativeSemanticPreflightState -ArchitectureData $architectureForCarry.Data -Blocks $semanticBlocks -VoiceExemplarsText (Get-Content -LiteralPath $voicePathForCarry -Raw -Encoding UTF8) -DraftSha256 $shaB
    $editorSemanticBAlert=$semanticB.Valid -and @($semanticB.ReviewAlerts).Count -gt 0
    if(-not $editorSemanticBAlert){throw 'EDITOR_SEMANTIC_CARRY_NEW_ALERT_NOT_CREATED'}
    $impactResult=& (Join-Path $tools 'Compare-DraftV2.ps1') -ProjectPath $project -OldDraftPath $baselineA.BaselinePath -WriteImpact
    $impact=Get-Content -LiteralPath $impactResult.ImpactPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
    $impactRunId='IMPACT.EDITOR.SEMANTIC.0001';$impactStart=& (Join-Path $tools 'Start-QAImpactReview.ps1') -ProjectPath $project -ImpactPath $impactResult.ImpactPath -RunId $impactRunId
    $impactBundle=Get-Bundle $impactStart.ManifestPath;$impactOutput=Get-SystemV7NarrativeExpectedRunOutputPath -ProjectPath $project -BundleData $impactBundle.Data
    Write-Lf -Path $impactOutput -Text (New-ImpactText -Impact $impact)
    $impactReceipt=New-RunReceipt $impactRunId $impactOutput 'TASK.IMPACT.EDITOR.SEMANTIC.0001' 'QA_IMPACT_V1' '4'
    $carryCountBefore=@(Get-ChildItem -LiteralPath (Join-Path $project '_work\k4\receipts') -Filter 'EDITOR.*.carryforward.json' -File -ErrorAction SilentlyContinue).Count
    $carryAttempt=Expect-Failure {& (Join-Path $tools 'New-QACarryForwardReceipt.ps1') -ProjectPath $project -ImpactPath $impactResult.ImpactPath -Lens EDITOR -PriorProofPath $editorReceipt -Justification 'Kontrolna próba ma zostać zablokowana przez zmianę semantic preflight.' -ImpactReviewRunId $impactRunId} '^CARRYFORWARD_DEPENDENCY_CHANGED_RERUN_REQUIRED$'
    $editorCarryDependencyRejected=$carryAttempt.Pass;$editorCarryError=$carryAttempt.Message
    $carryCountAfter=@(Get-ChildItem -LiteralPath (Join-Path $project '_work\k4\receipts') -Filter 'EDITOR.*.carryforward.json' -File -ErrorAction SilentlyContinue).Count
    $editorCarryNoReceipt=$carryCountAfter -eq $carryCountBefore
    $null=& (Join-Path $tools 'Compare-DraftV2.ps1') -ProjectPath $project -SaveBaseline
}finally{
    [IO.File]::WriteAllBytes($draftPathForCarry,$draftBytesForCarry);[IO.File]::WriteAllBytes($voicePathForCarry,$voiceBytesForCarry)
}
$editorLiveDependencyRestored=Get-SystemV7K4LensLiveDependencyFingerprintState -ProjectPath $project -Lens EDITOR
$editorDependencyRestore=$editorLiveDependencyRestored.Valid -and [string]$editorLiveDependencyRestored.Sha256 -ceq [string]$editorBundleDependency.Sha256
$editorProofRestored=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $editorReceipt -ExpectedRunType EDITOR -ExpectedDraftSha256 $draftSha
$editorProofRestore=$editorProofRestored.Valid
foreach($state in @($editorCarryDependencyRejected,$editorCarryNoReceipt,$editorSemanticBAlert,$editorDependencyRestore,$editorProofRestore)){if(-not $state){throw "EDITOR_SEMANTIC_CARRY_ASSERT_FAILED: rejected=$editorCarryDependencyRejected noReceipt=$editorCarryNoReceipt alert=$editorSemanticBAlert dependencyRestore=$editorDependencyRestore proofRestore=$editorProofRestore error=$editorCarryError"}}

$k4Preview=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project
if([string]$k4Preview.Mode -cne 'PREVIEW' -or [string]$k4Preview.FromStage -cne 'K4' -or [string]$k4Preview.ToStage -cne 'K5'){throw 'OFFICIAL_CHAIN_K4_PREVIEW_INVALID'}
$k4Apply=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -Apply
if([string]$k4Apply.Mode -cne 'APPLIED' -or [string]$k4Apply.FromStage -cne 'K4' -or [string]$k4Apply.ToStage -cne 'K5'){throw 'OFFICIAL_CHAIN_K4_APPLY_INVALID'}
$draftPath=Join-Path $project '03-draft.md';$draft=Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8;$cleanExact=Get-SystemV7CleanNarrationFromDraft -DraftText $draft;$clean=$cleanExact.Trim()
$meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8;$minutes=[int](Get-SystemV7NarrativeMetaField -Text $meta -Name 'TARGET_MINUTES');$wpm=[int](Get-SystemV7NarrativeMetaField -Text $meta -Name 'REAL_WPM');$mode=Get-SystemV7NarrativeMetaField -Text $meta -Name 'TARGET_DURATION_MODE'
$duration=Get-SystemV7DurationState -Narration $clean -TargetMinutes $minutes -RealWpm $wpm -Mode $mode
$revision=[regex]::Match($draft,'(?m)^CONTENT_REVISION:\s*(\S+)\s*$').Groups[1].Value
$qa=Join-Path $project '04-raport-qa.md';$fact=Join-Path $project '04B-fact-check.md';$final=Join-Path $project '05-FINAL-SCRIPT.md'
$header=@"
STATUS: ZATWIERDZONY
SOURCE_DRAFT_REVISION: $revision
SOURCE_DRAFT_SHA256: $draftSha
SOURCE_QA_SHA256: $((Get-FileHash -LiteralPath $qa -Algorithm SHA256).Hash)
SOURCE_FACTCHECK_SHA256: $((Get-FileHash -LiteralPath $fact -Algorithm SHA256).Hash)
K4_PROOF_SET_SHA256: $($compiled.ProofSetSha256)
CONTINUITY_CHAIN_SHA256: $($proof.Data.continuity_chain_sha256)
CONTINUITY_STATUS: PASS
FINAL_WORD_COUNT: $($duration.WordCount)
REAL_WPM: $wpm
ESTIMATED_DURATION: $([math]::Round($duration.EstimatedMinutes,2)) min

## NARRACJA DO NAGRANIA

"@
$receiptCountBeforeResidue=@(Get-ChildItem -LiteralPath (Join-Path $project '_work\K5') -Filter 'v2-approval-*.json' -File -ErrorAction SilentlyContinue).Count
$headerLf=ConvertTo-SystemV7LfText -Text $header
[IO.File]::WriteAllText($final,($headerLf+$cleanExact.Replace("`n","`r`n")),[Text.UTF8Encoding]::new($false))
$byteCrlf=Expect-Failure {& (Join-Path $tools 'Approve-K5FinalV2.ps1') -ProjectPath $project -ApprovalNote 'Negatyw różnicy bajtowej CRLF w finalnym tekście.' -DawidApproved} 'K5_ANY_TEXT_CHANGE_REQUIRES_REOPEN_K3'
[IO.File]::WriteAllText($final,($headerLf+' '+$cleanExact),[Text.UTF8Encoding]::new($false))
$edgeWhitespace=Expect-Failure {& (Join-Path $tools 'Approve-K5FinalV2.ps1') -ProjectPath $project -ApprovalNote 'Negatyw spacji brzegowej w finalnym tekście.' -DawidApproved} 'K5_ANY_TEXT_CHANGE_REQUIRES_REOPEN_K3'
Write-Lf $final ($header+"# Niedozwolony nagłówek`n"+$clean)
$residue=Expect-Failure {& (Join-Path $tools 'Approve-K5FinalV2.ps1') -ProjectPath $project -ApprovalNote 'Negatyw technicznego osadu w finalnym tekście.' -DawidApproved} 'K5_FINAL_TECHNICAL_RESIDUE'
$productionResidueRejected=$true
foreach($productionLabel in @('MONTAŻ: pokaż dokument archiwalny.','KARTA WYMOWY: nazwa kontrolna.','DIDASKALIA: cisza.','INSTRUKCJA MONTAŻOWA: cięcie.','INSTRUKCJA WYKONAWCZA: szeptem.','REŻYSERIA: zbliżenie.','NAPIS NA EKRANIE: data.','PLANSZA: mapa.','VOICE OVER: tekst.','VO: tekst.','[MONTAŻ: pokaż dokument]','[KARTA WYMOWY: nazwa]')){
    Write-Lf $final ($header+$productionLabel+"`n"+$clean)
    $productionAttempt=Expect-Failure {& (Join-Path $tools 'Approve-K5FinalV2.ps1') -ProjectPath $project -ApprovalNote 'Negatyw etykiety produkcyjnej w finalnym tekście.' -DawidApproved} 'K5_FINAL_(?:TECHNICAL_RESIDUE|NOT_PLAIN_SPOKEN_TEXT)'
    $productionResidueRejected=$productionResidueRejected -and $productionAttempt.Pass
}
$preReceiptCount=@(Get-ChildItem -LiteralPath (Join-Path $project '_work\K5') -Filter 'v2-approval-*.json' -File -ErrorAction SilentlyContinue).Count
Write-Lf $final ($header+$clean)
$noFlag=Expect-Failure {& (Join-Path $tools 'Approve-K5FinalV2.ps1') -ProjectPath $project -ApprovalNote 'Brak flagi musi zostać odrzucony.'} 'DAWID_APPROVAL_REQUIRED'
$approval=& (Join-Path $tools 'Approve-K5FinalV2.ps1') -ProjectPath $project -ApprovalNote 'Jawna akceptacja wyłącznie syntetycznego finalu trwałej regresji.' -DawidApproved
$k5=Get-SystemV7K5ApprovalV2State -ProjectPath $project
if(-not $k5.Valid){throw "K5_APPROVAL_INVALID: $($k5.Errors -join '; ')"}
$finalBytes=[IO.File]::ReadAllBytes($final);[IO.File]::AppendAllText($final,"`nTAMPER",[Text.UTF8Encoding]::new($false));$tampered=Get-SystemV7K5ApprovalV2State -ProjectPath $project;[IO.File]::WriteAllBytes($final,$finalBytes);$restored=Get-SystemV7K5ApprovalV2State -ProjectPath $project
$finalLive=Get-Content -LiteralPath $final -Raw -Encoding UTF8;$finalMatch=[regex]::Match($finalLive,'(?ms)^##\s+NARRACJA DO NAGRANIA\s*\r?\n(?<body>.*)\z')
$k5Preview=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -DawidApproved
if([string]$k5Preview.Mode -cne 'PREVIEW' -or [string]$k5Preview.FromStage -cne 'K5' -or [string]$k5Preview.ToStage -cne 'COMPLETE'){throw 'OFFICIAL_CHAIN_K5_PREVIEW_INVALID'}
$k5Apply=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -Apply -DawidApproved
if([string]$k5Apply.Mode -cne 'APPLIED' -or [string]$k5Apply.FromStage -cne 'K5' -or [string]$k5Apply.ToStage -cne 'COMPLETE'){throw 'OFFICIAL_CHAIN_K5_APPLY_INVALID'}
$completeValidation=& (Join-Path $tools 'Validate-Project.ps1') -ProjectPath $project -NoExit
$finalMeta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8
$completeMetaExact=(Get-SystemV7NarrativeMetaField -Text $finalMeta -Name 'CURRENT_STAGE') -ceq 'COMPLETE' -and (Get-SystemV7NarrativeMetaField -Text $finalMeta -Name 'LAST_GATE') -ceq 'K5_PASS' -and (Get-SystemV7NarrativeMetaField -Text $finalMeta -Name 'STAGE_OWNER') -ceq 'Dawid'
$result=[pscustomobject]@{
    ProjectPath=$project;DraftSha256=$draftSha
    EditorValid=$editorState.Valid;VerifyValid=$verifyState.Valid;ColdReaderValid=$coldState.Valid
    VerifyMissingRejected=(-not $verifyMissingState.Valid);EditorGenericRejected=(-not $editorGenericState.Valid);ColdBrakRejected=(-not $coldBrakState.Valid)
    ProofSetValid=$proof.Valid;ProofSetSha256=$compiled.ProofSetSha256
    TelemetryProviderPass=$telemetryProviderPass;CacheMissNonBlocking=$cacheMissNonBlocking;TelemetryFailureNonBlocking=$telemetryFailureNonBlocking;TelemetryDefaultPass=$telemetryDefaultPass
    EditorSemanticAEmpty=$editorSemanticAEmpty;EditorSemanticBAlert=$editorSemanticBAlert;EditorCarryDependencyRejected=$editorCarryDependencyRejected;EditorCarryNoReceipt=$editorCarryNoReceipt;EditorDependencyRestore=$editorDependencyRestore;EditorProofRestore=$editorProofRestore;EditorCarryError=$editorCarryError
    ByteCrlfRejected=$byteCrlf.Pass;EdgeWhitespaceRejected=$edgeWhitespace.Pass;ResidueRejected=$residue.Pass;ProductionResidueMatrixRejected=$productionResidueRejected;ResidueCreatedNoReceipt=($preReceiptCount -eq $receiptCountBeforeResidue);NoFlagRejected=$noFlag.Pass
    K5Valid=$k5.Valid;K5Status=$approval.Status;FinalMatchesClean=($finalMatch.Success -and $finalMatch.Groups['body'].Value -ceq $cleanExact)
    K5TamperRejected=(-not $tampered.Valid);K5RestoreValid=$restored.Valid;K5TamperErrors=@($tampered.Errors)
    OfficialK3ToK4=([string]$k3Apply.ToStage -ceq 'K4');OfficialK4ToK5=([string]$k4Apply.ToStage -ceq 'K5');OfficialK5ToComplete=([string]$k5Apply.ToStage -ceq 'COMPLETE')
    CompleteValidationPass=([string]$completeValidation.Verdict -ceq 'PASS' -and [string]$completeValidation.Stage -ceq 'COMPLETE');CompleteMetaExact=$completeMetaExact;CompleteValidationErrors=@($completeValidation.ErrorDetails)
}
foreach($name in @('EditorValid','VerifyValid','ColdReaderValid','VerifyMissingRejected','EditorGenericRejected','ColdBrakRejected','ProofSetValid','TelemetryProviderPass','CacheMissNonBlocking','TelemetryFailureNonBlocking','TelemetryDefaultPass','EditorSemanticAEmpty','EditorSemanticBAlert','EditorCarryDependencyRejected','EditorCarryNoReceipt','EditorDependencyRestore','EditorProofRestore','ByteCrlfRejected','EdgeWhitespaceRejected','ResidueRejected','ProductionResidueMatrixRejected','ResidueCreatedNoReceipt','NoFlagRejected','K5Valid','FinalMatchesClean','K5TamperRejected','K5RestoreValid','OfficialK3ToK4','OfficialK4ToK5','OfficialK5ToComplete','CompleteValidationPass','CompleteMetaExact')){if(-not [bool]$result.$name){throw "K4K5_ASSERT_FAILED: $name"}}
$result
