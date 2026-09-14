param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$VoiceProfilePath,
    [string]$PythonPath='python.exe'
)
$ErrorActionPreference='Stop'

$systemRoot=[IO.Path]::GetFullPath($SystemRoot)
$tools=Join-Path $systemRoot 'tools'
$sourceFixture=Join-Path $systemRoot '_SYSTEM\NARRATIVE\TEST-FIXTURES'
. (Join-Path $tools 'Narrative-Receipts.ps1')

function Write-Utf8Lf([string]$Path,[string]$Text){
    $value=(ConvertTo-SystemV7LfText -Text $Text)
    if(-not $value.EndsWith("`n")){$value+="`n"}
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null
    [IO.File]::WriteAllText($Path,$value,[Text.UTF8Encoding]::new($false))
}
function Set-Meta([string]$Project,[hashtable]$Values){
    $path=Join-Path $Project 'meta.md';$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach($key in $Values.Keys){$text=Set-SystemV7NarrativeMetaField -Text $text -Name $key -Value ([string]$Values[$key])}
    Write-SystemV7NarrativeAtomicText -Path $path -Text $text|Out-Null
}

$fixtureRoot=[IO.Path]::GetFullPath($FixtureRoot)
[IO.Directory]::CreateDirectory($fixtureRoot)|Out-Null
$projectName='PROJECT-COMPLEX'
$project=Join-Path $fixtureRoot $projectName
& (Join-Path $tools 'New-Project.ps1') -ProjectName $projectName -DestinationRoot $fixtureRoot -TargetMinutes 10 -RealWpm 130 -NarrativeV2Pilot|Out-Null
& (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -ProjectPath $project -ProfilePath $VoiceProfilePath -ApprovalNote 'Jawny wybór zatwierdzonego profilu w regresji Narrative V2.' -DawidApproved|Out-Null

$foundationPath=Join-Path $project '00-fundament-projektu.md'
Write-Utf8Lf -Path $foundationPath -Text @"
# 00 — KONTRAKT RESEARCHOWY

STATUS: GOTOWY
ZGODNOŚĆ_Z_W0: POTWIERDZONA
ESKALACJA_DO_DAWIDA: NIE

## Rdzeń filmu

- PYTANIE GŁÓWNE: Jak trzy niezależne ślady budują jedną sprawdzalną zmianę modelu widza?
- OBIETNICA: Pokażemy drogę trzech dowodów od źródeł do złożonego aktu.
- KONFLIKT/NAPIĘCIE: Konkretne ślady ścierają się z ryzykiem pustej, nieweryfikowalnej opowieści.
- W FILMIE: Trzy kontrolne ślady, ich funkcje sceniczne i wynik bramki.
- POZA FILMEM: Wszystkie wątki niezwiązane z kontrolowanym przebiegiem regresji.
- WĄTKI OBOWIĄZKOWE: Lokalizacja, atrybucja, niepewność i konsekwencja zmiany modelu.
- TEMAT ANALIZY K1-LITE V2: droga trzech kontrolnych konkretów od źródł do bazy dowodowej

## Cele badawcze K1

| ID | Pytanie badawcze | Co zmieni odpowiedź | Minimalny warunek pokrycia | Priorytet | Hasła wyszukiwania |
|---|---|---|---|---|---|
| Q-001 | Czy źródła zawierają konkretne ślady zdarzenia? | Ustali materiał scen | Trzy karty z lokalizacją | MUST | zdarzenie; ślad; data |
| Q-002 | Czy każdy ślad ma jawne pochodzenie? | Ustali atrybucję | Rejestr źródła przy każdej karcie | MUST | autor; pochodzenie; źródło |
| Q-003 | Czy materiał zachowuje granicę pewności? | Ochroni uczciwość narracji | Lokalizator i forma twierdzenia | MUST | pewność; hipoteza; lokalizacja |
| Q-004 | Czy trzy karty wystarczają do aktu złożonego? | Otworzy architekturę K2 | Trzy gotowe karty rdzeniowe | OPCJONALNY | architektura; akt; scena |

## Parametry

- TRYB RESEARCHU: SOURCES_ONLY
- ZGODA NA WEB: NIE
- POLITYKA WERYFIKACJI: SOURCE_FIRST_K4
- TARGET_DURATION_MODE: GUIDE
- TARGET_MINUTES: 10

## Bramka

- WERDYKT: PASS
"@
Set-Meta -Project $project -Values @{W0_DECISION='GO';W0_CONDITIONS='BRAK';W0_CONDITION_STATUS='NOT_APPLICABLE';LAST_GATE='PROJECT_INITIALIZED'}

$fixtureScript=Join-Path $tools 'k1-lite-v2\tests\make_system_fixture.py'
$k1Runs=[Collections.Generic.List[object]]::new()
$runSpecs=@(
    [pscustomobject]@{Name='full-chain-source-1';Candidate='first';Stem='full-chain-source-1'},
    [pscustomobject]@{Name='full-chain-source-2';Candidate='second';Stem='full-chain-source-2'},
    [pscustomobject]@{Name='full-chain-source-3';Candidate='first';Stem='full-chain-source-3'}
)
foreach($spec in $runSpecs){
    $raw=& $PythonPath $fixtureScript --project $project --run-name $spec.Name --candidate $spec.Candidate --source-stem $spec.Stem --source-kind txt
    if($LASTEXITCODE -ne 0){throw "K1_FIXTURE_CREATION_FAILED: $($spec.Name)"}
    $fixtureJson=($raw|ForEach-Object{$_.ToString()}) -join "`n"
    $k1Runs.Add(($fixtureJson|ConvertFrom-Json -DateKind String -Depth 32))
}

$advanceW0=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -PythonPath $PythonPath -Apply -DawidApproved
if([string]$advanceW0.FromStage -cne 'W0' -or [string]$advanceW0.ToStage -cne 'K0'){throw 'FULL_CHAIN_W0_TO_K0_FAILED'}
$advanceK0=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -PythonPath $PythonPath -Apply
if([string]$advanceK0.FromStage -cne 'K0' -or [string]$advanceK0.ToStage -cne 'K1'){throw 'FULL_CHAIN_K0_TO_K1_FAILED'}

$corpusOutput=Join-Path $project '_work\K1\k1-lite-v2\full-chain-corpus'
$corpus=& (Join-Path $tools 'Compile-K1LiteV2Corpus.ps1') -ProjectPath $project -RunDirectories @($k1Runs|ForEach-Object{[string]$_.run_dir}) -ExpectedLedgerSha256s @($k1Runs|ForEach-Object{[string]$_.ledger_sha256}) -OutputDirectory $corpusOutput -PythonPath $PythonPath
if([string]$corpus.Status -cne 'CORPUS_PREVIEW_READY' -or [int]$corpus.Cards -ne 3){throw "FULL_CHAIN_K1_CORPUS_INVALID: status=$($corpus.Status) cards=$($corpus.Cards)"}
$published=& (Join-Path $tools 'Compile-K1LiteV2.ps1') -Action Publish -ProjectPath $project -RunDirectory $corpus.RunDirectory -ExpectedLedgerSha256 $corpus.LedgerSha256 -PreviewPath $corpus.PreviewPath -ExpectedPreviewSha256 $corpus.PreviewSha256 -PythonPath $PythonPath
if([string]$published.Status -notmatch '^PUBLISHED_' -or [int]$published.Cards -ne 3){throw "FULL_CHAIN_K1_PUBLISH_INVALID: status=$($published.Status) cards=$($published.Cards)"}
$advanceK1=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -PythonPath $PythonPath -Apply
if([string]$advanceK1.FromStage -cne 'K1' -or [string]$advanceK1.ToStage -cne 'K2'){throw 'FULL_CHAIN_K1_TO_K2_FAILED'}

$authorText='I teraz sam zdecyduj, co z tym zrobić.'
$authorReceipt=& (Join-Path $tools 'Approve-AuthorText.ps1') -ProjectPath $project -VcId 'VC-001' -AuthorText $authorText -ApprovalNote 'Akceptacja wyłącznie dla syntetycznego fixture regresyjnego.' -DawidApproved

$sourceArchitecture=Join-Path $sourceFixture 'complex-architecture.md'
$sourceText=Get-Content -LiteralPath $sourceArchitecture -Raw -Encoding UTF8
$match=[regex]::Match($sourceText,'(?s)<!--\s*NARRATIVE_V2_JSON_BEGIN\s*-->\s*```json\s*(?<json>.*?)\s*```\s*<!--\s*NARRATIVE_V2_JSON_END\s*-->')
if(-not $match.Success){throw 'SOURCE_ARCHITECTURE_JSON_MISSING'}
$architecture=$match.Groups['json'].Value|ConvertFrom-Json -DateKind String -Depth 64
$vc=@($architecture.viewer_contacts|Where-Object{[string]$_.vc_id -ceq 'VC-001'})
if($vc.Count -ne 1){throw 'SOURCE_VC_MISSING'}
$vc[0].author_text=$authorReceipt.AuthorText
$vc[0].approval='DAWID_APPROVED'
$vc[0].approval_receipt_relative=$authorReceipt.ReceiptRelative
$vc[0].approval_receipt_sha256=$authorReceipt.ReceiptSha256
# Keep the COMPLEX mapping case while adapting the old source fixture to the
# deterministic closed-group atomicity contract.  The reveal lifecycle is
# exercised by dedicated fixtures; this act covers three SW groups, one VC,
# one act transformation and one continuity obligation (six atoms total).
$architecture.reveals=[object[]]@()
foreach($scene in @($architecture.scene_weave)){$scene.nr_action='BRAK'}
$act=@($architecture.acts|Where-Object{[string]$_.act_id -ceq 'ACT-001'})[0]
$act.nr_actions=[object[]]@()
$act.do_not_reveal=[object[]]@()
$architecture.k2b=[pscustomobject][ordered]@{
    decision='SUPLEMENT NIEWYMAGANY'
    reason='Trzy opublikowane i zlokalizowane karty dowodowe wystarczają do wszystkich trzech jednostek złożonego aktu.'
    gaps=[object[]]@()
}
$act.constraints=@(
    [ordered]@{cid='CID-001';source_field='ACT_FUNCTION';action='Zrealizuj funkcję aktu, zmianę stanu i most, a completion potraktuj jako kryterium odbioru tej samej transformacji';object_ids=@('ACT_FUNCTION:ACT-001','VIEWER_STATE:ACT-001','BRIDGE:ACT-001','COMPLETION:001');why_hard='Akt musi zmienić model widza';atomicity_reason='Jedna zależna transformacja aktu z jednym kryterium odbioru';verification='Stan wyjściowy, most i kryterium są spełnione'},
    [ordered]@{cid='CID-002';source_field='SW';action='Wykonaj jednostkę SW-001 z kompletem przypisanych dowodów';object_ids=@('SW:SW-001','REQUIRED:SW-001/#P-001');why_hard='Scena bez dowodu nie działa';atomicity_reason='Dowód zasila tę samą scenę';verification='SW-001 i karta występują razem'},
    [ordered]@{cid='CID-003';source_field='SW';action='Wykonaj jednostkę SW-002 z kompletem przypisanych dowodów';object_ids=@('SW:SW-002','REQUIRED:SW-002/#P-002');why_hard='Scena bez dowodu nie działa';atomicity_reason='Dowód zasila tę samą scenę';verification='SW-002 i karta występują razem'},
    [ordered]@{cid='CID-004';source_field='SW';action='Wykonaj jednostkę SW-003 z kompletem przypisanych dowodów';object_ids=@('SW:SW-003','REQUIRED:SW-003/#P-003');why_hard='Scena bez dowodu nie działa';atomicity_reason='Dowód zasila tę samą scenę';verification='SW-003 i karta występują razem'},
    [ordered]@{cid='CID-005';source_field='VC';action='Wprowadź zatwierdzony kontakt autorski';object_ids=@('VC:VC-001');why_hard='Kontakt angażuje widza w osąd';atomicity_reason='Jedna funkcja kontaktu';verification='VC-001 występuje dosłownie i ma ślad'},
    [ordered]@{cid='CID-006';source_field='CONTINUITY_OUT';action='Zwróć pełny CONTINUITY_OUT';object_ids=@('CONTINUITY_OUT:ACT-001');why_hard='Bez stanu nie wolno odblokować kolejnego aktu';atomicity_reason='Jeden obowiązek protokołu';verification='OUT przechodzi schemat'}
)
$architecturePath=Join-Path $project '02-architektura-odcinka.md'
$architectureText=@('STATUS: GOTOWA','WYBRANY_KIERUNEK: DIR_A','ONE_DIRECTION_APPROVAL:','<!-- NARRATIVE_V2_JSON_BEGIN -->','```json',(ConvertTo-SystemV7CanonicalJson -Value $architecture).Trim(),'```','<!-- NARRATIVE_V2_JSON_END -->') -join "`n"
Write-Utf8Lf -Path $architecturePath -Text $architectureText
$architectureState=Test-SystemV7NarrativeArchitecture -ArchitecturePath $architecturePath -EvidencePath (Join-Path $project '01-baza-dowodow.md')
if(-not $architectureState.GateReady){throw "ARCHITECTURE_NOT_GREEN: $($architectureState.ErrorDetails -join '; ')"}
$clone={param($value)(ConvertTo-SystemV7CanonicalJson -Value $value)|ConvertFrom-Json -DateKind String -Depth 64}
$architectureCasePath=Join-Path $project '02-architecture-case-mutant.md';$architectureCaseExact=$true
foreach($case in @(
    [pscustomobject]@{Name='VC_FUNCTION';Error='VC_FUNCTION_INVALID';Mutate={param($d)$d.viewer_contacts[0].function='author'}},
    [pscustomobject]@{Name='VC_LEVEL';Error='VC_LEVEL_INVALID';Mutate={param($d)$d.viewer_contacts[0].level='authorial'}},
    [pscustomobject]@{Name='COMPLEXITY';Error='ACT_COMPLEXITY_INVALID';Mutate={param($d)$d.acts[0].complexity_flag='complex'}},
    [pscustomobject]@{Name='HUMOR';Error='ACT_HUMOR_MODE_INVALID';Mutate={param($d)$d.acts[0].humor_mode='forbidden'}},
    [pscustomobject]@{Name='NQ_ENUMS';Error='NQ_(?:STATUS|EXPECTED_FORM)_INVALID';Mutate={param($d)$d.questions=@([pscustomobject][ordered]@{nq_id='NQ-999';question='Czy test zachowuje kontrakt?';opened_at='SW-001';why_care='Chroni cykl pytania.';expected_form='answer';payoff_node='SW-003';status='open'})}}
)){
    $mutant=&$clone $architecture;$mutator=$case.Mutate;&$mutator $mutant
    $mutantText=@('STATUS: GOTOWA','WYBRANY_KIERUNEK: DIR_A','ONE_DIRECTION_APPROVAL:','<!-- NARRATIVE_V2_JSON_BEGIN -->','```json',(ConvertTo-SystemV7CanonicalJson -Value $mutant).Trim(),'```','<!-- NARRATIVE_V2_JSON_END -->') -join "`n"
    Write-Utf8Lf -Path $architectureCasePath -Text $mutantText
    $mutantState=Test-SystemV7NarrativeArchitecture -ArchitecturePath $architectureCasePath -EvidencePath (Join-Path $project '01-baza-dowodow.md')
    $architectureCaseExact=$architectureCaseExact -and (-not $mutantState.GateReady) -and (($mutantState.ErrorDetails -join ';') -match $case.Error)
}
if(Test-Path -LiteralPath $architectureCasePath -PathType Leaf){[IO.File]::Delete($architectureCasePath)}
if(-not $architectureCaseExact){throw 'ARCHITECTURE_CASE_ENUM_NOT_EXACT'}
$baseSpine=Get-SystemV7StorySpineProjection -ArchitectureData $architecture
$baseActProjection=Get-SystemV7ActProjection -ArchitectureData $architecture -ActId 'ACT-001'
$revisionOnly=&$clone $architecture;$revisionOnly.architecture_revision='BOOKKEEPING-ONLY-REVISION'
$revisionSpine=Get-SystemV7StorySpineProjection -ArchitectureData $revisionOnly;$revisionAct=Get-SystemV7ActProjection -ArchitectureData $revisionOnly -ActId 'ACT-001'
$localOnly=&$clone $architecture;$localOnly.acts[0].label='Lokalnie zmieniona etykieta aktu'
$localSpine=Get-SystemV7StorySpineProjection -ArchitectureData $localOnly;$localAct=Get-SystemV7ActProjection -ArchitectureData $localOnly -ActId 'ACT-001'
$globalOnly=&$clone $architecture;$globalOnly.story_dna.central_question='Globalnie zmienione pytanie centralne'
$globalSpine=Get-SystemV7StorySpineProjection -ArchitectureData $globalOnly

$voicePath=Join-Path $project '_work\test-voice.md'
$exemplar=('To jest syntetyczny fragment próbny, który pokazuje jasny rytm opowieści, zmianę stanu wiedzy oraz sposób prowadzenia widza przez konkretny dowód. ' * 6).Trim()
$voiceRules="Pisz jasno, konkretnie i wiąż każde twierdzenie z materiałem przekazanym w paczce.`n"
$exemplarText=$exemplar+"`n"
$voiceFence='```'
$exemplarRegistry=[ordered]@{
    schema='VOICE_EXEMPLAR_REGISTRY_V1'
    exemplars=@([ordered]@{
        exemplar_id='EX-001';project_name='TEST-FIXTURE';artifact_path='TEST-FIXTURE/05-FINAL-SCRIPT.md';artifact_sha256=('A'*64)
        exact_text_sha256=(Get-SystemV7NarrativeSha256Text -Text $exemplarText);approval_status='TEST_APPROVED'
        demonstrates=@('STRONG_OPENING','SCENE','UNCERTAINTY','KNOWLEDGE_BOUNDARY','VIEWER_CONTACT','TRANSITION','PAYOFF');exact_text=$exemplar
    })
}
$exemplarRegistryJson=ConvertTo-SystemV7CanonicalJson -Value $exemplarRegistry
Write-Utf8Lf -Path $voicePath -Text @"
VOICE_PROFILE_SCHEMA: SYSTEM_V7_VOICE_PROFILE_V1
VOICE_PROFILE_REVISION: TEST-V1
STATUS: TEST_APPROVED
APPROVED_BY: TEST_FIXTURE
APPROVAL_RECEIPT_PATH: BRAK
APPROVAL_RECEIPT_SHA256: BRAK
RULES_SHA256: $(Get-SystemV7NarrativeSha256Text -Text $voiceRules)
EXEMPLAR_REGISTRY_SHA256: $(Get-SystemV7NarrativeSha256Text -Text $exemplarRegistryJson)
EXEMPLARS_SHA256: $(Get-SystemV7NarrativeSha256Text -Text $exemplarText)

## VOICE RULES

$($voiceRules.TrimEnd())

## VOICE EXEMPLARS

$($voiceFence)json
$($exemplarRegistryJson.TrimEnd())
$voiceFence
"@

$settingsPath=Join-Path $fixtureRoot 'model-settings.json'
Write-Utf8Lf -Path $settingsPath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{temperature=0;max_output_tokens=4096;seed=42}))
$fixtureModelSettingsSha=(Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash
Set-Meta -Project $project -Values @{K2B_DECISION='SUPLEMENT NIEWYMAGANY'}
$advanceK2=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -PythonPath $PythonPath -Apply
if([string]$advanceK2.FromStage -cne 'K2' -or [string]$advanceK2.ToStage -cne 'K2B'){throw 'FULL_CHAIN_K2_TO_K2B_FAILED'}
$model=& (Join-Path $tools 'Set-K3ModelManifest.ps1') -ProjectPath $project -ModelId 'CLAUDE-TEST' -ModelRevision 'TEST-2026-08-31' -ModelSettingsPath $settingsPath
$packetBuild=& (Join-Path $tools 'Build-K3PacketsV2.ps1') -ProjectPath $project -ActId 'ACT-001' -VoiceProfilePath $VoiceProfilePath -Write
$preflightRun='PREFLIGHT.ACT001.0001'
$null=& (Join-Path $tools 'Start-K3ConstraintPreflight.ps1') -ProjectPath $project -ActId 'ACT-001' -RunId $preflightRun
$preflightPacket=Get-Content -LiteralPath (Join-Path $project '_work\k3\packets\ACT-001.act-packet.json') -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$preflightLedger=Get-Content -LiteralPath (Join-Path $project '_work\k3\packets\ACT-001.constraint-ledger.json') -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$preflightAtomicity=Get-SystemV7ConstraintAtomicityState -Packet $preflightPacket -Ledger $preflightLedger
if(-not $preflightAtomicity.Valid){throw "PREFLIGHT_ATOMICITY_NOT_GREEN: $($preflightAtomicity.Errors -join '; ')"}
$outputDir=Join-Path $project '_work\test-outputs';[IO.Directory]::CreateDirectory($outputDir)|Out-Null
$preflightOutput=Join-Path $project "_work\narrative-runs\$preflightRun\output.md"
Write-Utf8Lf -Path $preflightOutput -Text @"
VERDICT: PASS
UNBUNDLED_CONSTRAINT_COUNT: $($preflightAtomicity.UnbundledConstraintCount)
MISSING_ACTIONS: BRAK
BUNDLED_ACTIONS: BRAK
CONFLICTS: BRAK
REASON: Każdy obowiązek jest atomowy i znajduje się w zamkniętej paczce aktu.
"@
$started=[DateTimeOffset]::UtcNow.AddMinutes(-5)
$preflightRun='PREFLIGHT.ACT001.0001'
$preflightOutput=Join-Path $project "_work\narrative-runs\$preflightRun\output.md"
$null=& (Join-Path $tools 'New-NarrativeRunReceipt.ps1') -ProjectPath $project -RunId $preflightRun -OutputPath $preflightOutput -TaskId 'TASK.PREFLIGHT.ACT001.0001' -ModelId 'CHATGPT-CODEX-TEST' -ModelRevision 'TEST-2026-08-31' -ModelSettingsSha256 $fixtureModelSettingsSha -PromptRevision 'CONSTRAINT_PREFLIGHT_V1' -ActorRole CHATGPT_CODEX -StartedAt $started -Note 'Syntetyczny preflight fixture.'

$advanceK2B=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -PythonPath $PythonPath -Apply
if([string]$advanceK2B.FromStage -cne 'K2B' -or [string]$advanceK2B.ToStage -cne 'K3'){throw 'FULL_CHAIN_K2B_TO_K3_FAILED'}

$generateRun='GENERATE.ACT001.0001'
$null=& (Join-Path $tools 'Start-K3Act.ps1') -ProjectPath $project -ActId 'ACT-001' -RunId $generateRun
$packetPath=Join-Path $project '_work\k3\packets\ACT-001.act-packet.json'
$packet=Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$beats=[Collections.Generic.List[object]]::new();$beatNo=0
foreach($scene in @($packet.scene_contracts)){
    $beatNo++
    $tokens=[Collections.Generic.List[string]]::new()
    if([string]$scene.nq_action -cne 'BRAK'){$tokens.Add([string]$scene.nq_action)}
    if([string]$scene.nr_action -cne 'BRAK'){$tokens.Add([string]$scene.nr_action)}
    foreach($id in @($scene.vc_ids)){$tokens.Add([string]$id)}
    $beats.Add([ordered]@{beat_id=('BEAT-{0:D3}' -f $beatNo);sw_id=[string]$scene.sw_id;function=[string]$scene.function;source_p_ids=@($scene.required_p)+@($scene.supporting_p);state_before=[string]$scene.entry_knowledge_state;state_after=[string]$scene.exit_knowledge_state;nq_nr_vc_ids=@($tokens)})
}
$beatSubmission=Join-Path $outputDir 'beat-submission.json'
Write-Utf8Lf -Path $beatSubmission -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='K3_BEAT_SHEET_V1';act_id='ACT-001';packet_status='BEAT_SHEET_READY';beats=@($beats)}))
$null=& (Join-Path $tools 'Import-K3BeatSheet.ps1') -ProjectPath $project -ActId 'ACT-001' -GenerateRunId $generateRun -BeatSheetPath $beatSubmission
$beatPreflightRun='BEATPREF.ACT001.0001'
$null=& (Join-Path $tools 'Start-K3BeatPreflight.ps1') -ProjectPath $project -ActId 'ACT-001' -RunId $beatPreflightRun
$beatPreflightOutput=Join-Path $project "_work\narrative-runs\$beatPreflightRun\output.md"
Write-Utf8Lf -Path $beatPreflightOutput -Text @"
VERDICT: PASS
ACT_ID: ACT-001
SCHEMA_CHECK: PASS
IDENTIFIER_CHECK: PASS
STATE_TRANSITION_CHECK: PASS
NO_ADDED_SOURCE_OR_REVEAL: PASS
DISCREPANCIES: BRAK
REASON: Każdy beat zachowuje kolejność SW, źródła, działania oraz przejścia stanu.
"@
$null=& (Join-Path $tools 'New-NarrativeRunReceipt.ps1') -ProjectPath $project -RunId $beatPreflightRun -OutputPath $beatPreflightOutput -TaskId 'TASK.BEATPREF.ACT001.0001' -ModelId 'CHATGPT-CODEX-TEST' -ModelRevision 'TEST-2026-08-31' -ModelSettingsSha256 $fixtureModelSettingsSha -PromptRevision 'BEAT_PREFLIGHT_V1' -ActorRole CHATGPT_CODEX -StartedAt $started -Note 'Syntetyczny beat preflight fixture.'

$proseBySw=@{
    'SW-001'='Pierwszy ślad buduje kontekst i pokazuje początek zagadki.'
    'SW-002'="Dokument zmienia model wydarzeń. Nie wiadomo, kto sporządził dokument. $authorText"
    'SW-003'='Konsekwencja zmiany domyka rozumowanie i prowadzi widza do końcowego wniosku.'
}
$submissionBlocks=[Collections.Generic.List[object]]::new()
foreach($beat in @($beats)){$submissionBlocks.Add([ordered]@{trace_refs=@([string]$beat.beat_id);source_p_ids=@($beat.source_p_ids);narrative_refs=@($beat.nq_nr_vc_ids);prose=[string]$proseBySw[[string]$beat.sw_id]})}
$submissionPath=Join-Path $outputDir 'act-submission.json'
Write-Utf8Lf -Path $submissionPath -Text (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='K3_ACT_SUBMISSION_V2';act_id='ACT-001';packet_status='PROSE_READY';self_check='PASS';blocks=@($submissionBlocks)}))
$null=& (Join-Path $tools 'Import-K3Act.ps1') -ProjectPath $project -ActId 'ACT-001' -RunId $generateRun -SubmissionPath $submissionPath

$blocksPath=Join-Path $project '_work\k3\acts\ACT-001\blocks.json'
$blocks=Get-Content -LiteralPath $blocksPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$ref={param($Block)[ordered]@{block_id=[string]$Block.block_id;block_sha256=[string]$Block.block_sha256}}
$out=[ordered]@{
    schema='CONTINUITY_OUT_V1';act_id='ACT-001';records=@([ordered]@{state_id='STATE-001';category='FACT';value='Dokument zmienia model wydarzeń.';class='TEXT_ASSERTED';block_refs=@((&$ref $blocks.blocks[1]),(&$ref $blocks.blocks[2]));related_ids=@('SW-002','SW-003','VC-001');source_p_ids=@('#P-002','#P-003')})
    nq_paid=@();nq_opened=@();nq_reframed=@();open_nq_ids_out=@();nr_revealed=@();nr_consequences=@();nr_setup_only=@();character_and_world_state=@()
    bridge_realized='Ta zmiana prowadzi do finału.';bridge_block_refs=@(&$ref $blocks.blocks[2]);opening_move_type='SCENA';opening_block_refs=@(&$ref $blocks.blocks[0]);closing_move_type='KONSEKWENCJA';closing_block_refs=@(&$ref $blocks.blocks[2])
    uncertainties_preserved=@([ordered]@{uncertainty_id='UNCERTAINTY-001';value='Nie wiadomo, kto sporządził dokument.';block_refs=@(&$ref $blocks.blocks[1]);source_p_ids=@('#P-002')})
}
$classMutant=&$clone $out;$classMutant.records[0].class='text_asserted';$classMutant.records[0].source_p_ids=@();$classMutant.records[0].value='Nieobecna kotwica kontrolna.'
$classMutantState=Get-SystemV7ContinuityOutStructuralState -ActId ACT-001 -ContinuityOut $classMutant -BlocksData $blocks -ArchitectureData $architecture
$categoryMutant=&$clone $out;$categoryMutant.records[0].category='reveal';$categoryMutant.records[0].related_ids=@();$categoryMutant.records[0].source_p_ids=@()
$categoryMutantState=Get-SystemV7ContinuityOutStructuralState -ActId ACT-001 -ContinuityOut $categoryMutant -BlocksData $blocks -ArchitectureData $architecture
$worldMutant=&$clone $out;$worldMutant.character_and_world_state=@([pscustomobject][ordered]@{world_state_id='WORLD-999';value='Nieobecna kotwica świata.';class='text_asserted';block_refs=@(&$ref $blocks.blocks[0]);source_p_ids=@()})
$worldMutantState=Get-SystemV7ContinuityOutStructuralState -ActId ACT-001 -ContinuityOut $worldMutant -BlocksData $blocks -ArchitectureData $architecture
$continuityCaseExact=(-not $classMutantState.Valid) -and (($classMutantState.Errors -join ';') -match 'CONTINUITY_OUT_CLASS_INVALID') -and (-not $categoryMutantState.Valid) -and (($categoryMutantState.Errors -join ';') -match 'CONTINUITY_OUT_CLASS_INVALID') -and (-not $worldMutantState.Valid) -and (($worldMutantState.Errors -join ';') -match 'CONTINUITY_OUT_WORLD_STATE_VALUE_OR_CLASS_INVALID')
if(-not $continuityCaseExact){throw 'CONTINUITY_CASE_ENUM_NOT_EXACT'}
$outPath=Join-Path $outputDir 'continuity-out.json';Write-Utf8Lf -Path $outPath -Text (ConvertTo-SystemV7CanonicalJson -Value $out)
$null=& (Join-Path $tools 'Import-K3Act.ps1') -ProjectPath $project -ActId 'ACT-001' -RunId $generateRun -ContinuityOutPath $outPath -TaskId 'TASK.GENERATE.ACT001.0001' -StartedAt $started

$attestRun='ATTEST.ACT001.0001'
$null=& (Join-Path $tools 'Start-ContinuityAttest.ps1') -ProjectPath $project -ActId 'ACT-001' -RunId $attestRun
$attestOutput=Join-Path $project "_work\narrative-runs\$attestRun\output.md"
$attestRows=@('STATE-001','UNCERTAINTY-001','BRIDGE','OPENING_MOVE','CLOSING_MOVE')|ForEach-Object{[ordered]@{state_id=$_;verdict='PASS';reason='Rekord jest związany z właściwym blokiem oraz kompletnym śladem.'}}
$attestRaw=Join-Path $project "_work/narrative-runs/$attestRun/raw-response.json"
Write-Utf8Lf -Path $attestRaw -Text (([ordered]@{schema='CONTINUITY_ATTEST_RESULT_V1';act_id='ACT-001';verdict='PASS';record_results=@($attestRows);missing_state_change=$false;question_arithmetic_verdict='PASS';reason='Ślepy audyt potwierdza strukturę oraz kompletną zmianę stanu.'}|ConvertTo-Json -Depth 64))
$normalized=& (Join-Path $tools "Normalize-ContinuityResponse.ps1") -ProjectPath $project -RunId $attestRun -RawPath $attestRaw
if($normalized.Status -cne "FORMAT_NORMALIZED_REQUIRES_VALIDATION"){throw "NORMALIZER_INTEGRATION_FAILED"}
$null=& (Join-Path $tools 'New-NarrativeRunReceipt.ps1') -ProjectPath $project -RunId $attestRun -OutputPath $attestOutput -TaskId 'TASK.ATTEST.ACT001.0001' -ModelId 'CHATGPT-CODEX-TEST' -ModelRevision 'TEST-2026-08-31' -ModelSettingsSha256 $fixtureModelSettingsSha -PromptRevision 'CONTINUITY_ATTEST_V1' -ActorRole CHATGPT_CODEX -StartedAt $started -Note 'Syntetyczny blind attest fixture.'
$null=& (Join-Path $tools 'Accept-ContinuityAttest.ps1') -ProjectPath $project -ActId 'ACT-001' -RunId $attestRun
$assembly=& (Join-Path $tools 'Assemble-K3Draft.ps1') -ProjectPath $project

$draftPath=Join-Path $project '03-draft.md';$draft=Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
$mapMatch=[regex]::Match($draft,'(?s)<!--\s*K3_BLOCK_MAP_BEGIN\s*-->\s*```json\s*(?<json>.*?)\s*```\s*<!--\s*K3_BLOCK_MAP_END\s*-->')
$map=$mapMatch.Groups['json'].Value|ConvertFrom-Json -DateKind String -Depth 64
$mapped=@($map.acts[0].blocks|ForEach-Object{[pscustomobject]@{BlockId=$_.block_id;Trace=@($_.trace_refs)-join',';SwIds=@($_.sw_ids)-join',';SwArrayType=$_.sw_ids.GetType().FullName}})
$mappingPass=$mapped.Count -eq 3 -and $mapped[0].Trace -ceq 'BEAT-001' -and $mapped[0].SwIds -ceq 'SW-001' -and $mapped[1].Trace -ceq 'BEAT-002' -and $mapped[1].SwIds -ceq 'SW-002' -and $mapped[2].Trace -ceq 'BEAT-003' -and $mapped[2].SwIds -ceq 'SW-003'

$baselineValidation=& (Join-Path $tools 'Validate-NarrativeV2Project.ps1') -ProjectPath $project -NoExit
$tampered=$draft.Replace('"sw_ids":["SW-002"]','"sw_ids":["SW-001"]')
if($tampered -ceq $draft){throw 'DRAFT_SW_TAMPER_PATTERN_MISSING'}
Write-Utf8Lf -Path $draftPath -Text $tampered
$tamperedValidation=& (Join-Path $tools 'Validate-NarrativeV2Project.ps1') -ProjectPath $project -NoExit
Write-Utf8Lf -Path $draftPath -Text $draft
$tamperDetected=@($tamperedValidation.ErrorDetails|Where-Object{$_ -ceq 'K3_DRAFT_BLOCK_MAP_STALE'}).Count -eq 1

[pscustomobject]@{
    FixturePath=$project
    NarrativeV2Sha256=(Get-FileHash -LiteralPath (Join-Path $tools 'Narrative-V2.ps1') -Algorithm SHA256).Hash
    NarrativeReceiptsSha256=(Get-FileHash -LiteralPath (Join-Path $tools 'Narrative-Receipts.ps1') -Algorithm SHA256).Hash
    AssembleSha256=(Get-FileHash -LiteralPath (Join-Path $tools 'Assemble-K3Draft.ps1') -Algorithm SHA256).Hash
    ValidatorSha256=(Get-FileHash -LiteralPath (Join-Path $tools 'Validate-NarrativeV2Project.ps1') -Algorithm SHA256).Hash
    ArchitectureGateReady=$architectureState.GateReady
    ArchitectureCaseExact=$architectureCaseExact
    ContinuityCaseExact=$continuityCaseExact
    RevisionSpineStable=($revisionSpine.Sha256 -ceq $baseSpine.Sha256)
    RevisionActStable=($revisionAct.Sha256 -ceq $baseActProjection.Sha256)
    LocalSpineStable=($localSpine.Sha256 -ceq $baseSpine.Sha256)
    LocalActInvalidated=($localAct.Sha256 -cne $baseActProjection.Sha256)
    GlobalSpineInvalidated=($globalSpine.Sha256 -cne $baseSpine.Sha256)
    AssemblyStatus=$assembly.Status
    MappingPass=$mappingPass
    MappedBlocks=$mapped
    BaselineValidatorVerdict=$baselineValidation.Verdict
    BaselineAssemblyErrors=@($baselineValidation.ErrorDetails|Where-Object{$_ -like 'K3_DRAFT_*' -or $_ -like 'K3_ASSEMBLY_*'})
    TamperDetected=$tamperDetected
    TamperAssemblyErrors=@($tamperedValidation.ErrorDetails|Where-Object{$_ -like 'K3_DRAFT_*' -or $_ -like 'K3_ASSEMBLY_*'})
}
