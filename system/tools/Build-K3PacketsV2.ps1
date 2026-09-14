[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [ValidatePattern('^ACT-\d{3}$')][string]$ActId,
    [string]$VoiceProfilePath,
    [switch]$AllowTestVoiceProfile,
    [switch]$AuditExistingAct,
    [switch]$Write,
    [switch]$Force
)

$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
$systemRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')

Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project -SystemRoot $systemRoot | Out-Null

$metaPath=Join-Path $project 'meta.md'
$architecturePath=Join-Path $project '02-architektura-odcinka.md'
$evidencePath=Join-Path $project '01-baza-dowodow.md'
foreach($path in @($metaPath,$architecturePath,$evidencePath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "REQUIRED_FILE_MISSING: $path"}}
$inputSnapshot=if($Write){[ordered]@{
    meta=(Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash
    architecture=(Get-FileHash -LiteralPath $architecturePath -Algorithm SHA256).Hash
    evidence=(Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash
    prior_attests=@{}
}}else{$null}
$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'WORKFLOW_REVISION_NOT_NARRATIVE_V2'}
$origin=if($Write){Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta}else{Assert-SystemV7CurrentProjectOrigin -ProjectPath $project -MetaText $meta}
$assertWritePolicy={param([string]$MetaText)
    $stage=Get-SystemV7NarrativeMetaField -Text $MetaText -Name 'CURRENT_STAGE';$gate=Get-SystemV7NarrativeMetaField -Text $MetaText -Name 'LAST_GATE'
    if($stage -ceq 'K2B'){
        if($gate -notin @('K2_PASS','REOPEN_K2B_REQUIRED')){throw "K3_PACKET_WRITE_GATE_INVALID: $stage/$gate"}
    }elseif($stage -ceq 'K3'){
        if($gate -notin @('K2B_PASS','REOPEN_K3_REQUIRED','MODEL_REBASE_REQUIRED_REGENERATION')){throw "K3_PACKET_WRITE_GATE_INVALID: $stage/$gate"}
    }else{throw "K3_PACKET_WRITE_STAGE_INVALID: $stage"}
    if($gate -in @('REOPEN_K2B_REQUIRED','REOPEN_K3_REQUIRED')){$head=Get-StateReceiptHeadState -ProjectPath $project;if(-not $head.Valid -or $head.Kind -cne 'REOPEN' -or [string]$head.Data.target_stage -cne $stage){throw "K3_PACKET_REOPEN_HEAD_INVALID: $($head.Problems -join '; ')"}}
}
if($Write){&$assertWritePolicy $meta}

$architectureStatus=Get-SystemV7NarrativeMetaField -Text (Get-Content -LiteralPath $architecturePath -Raw -Encoding UTF8) -Name 'STATUS'
if($architectureStatus -cne 'GOTOWA'){throw "ARCHITECTURE_NOT_READY: $architectureStatus"}
$validation=Test-SystemV7NarrativeArchitecture -ArchitecturePath $architecturePath -EvidencePath $evidencePath
if(-not $validation.GateReady){throw "ARCHITECTURE_FAIL: $($validation.ErrorDetails -join '; ')"}
$architecture=$validation.Architecture
$evidence=$validation.Evidence
$actIds=@($validation.ActIds)

$nextAct=$null
foreach($candidate in $actIds){$attest=Join-Path $project ("_work\k3\continuity\$candidate.attest.json");if(-not(Test-Path -LiteralPath $attest -PathType Leaf)){$nextAct=$candidate;break};if($Write){$inputSnapshot.prior_attests[$candidate]=(Get-FileHash -LiteralPath $attest -Algorithm SHA256).Hash};$priorState=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $candidate;if(-not $priorState.Valid){throw "EXISTING_ATTEST_INVALID: $candidate/$($priorState.Errors -join '; ')"}}
if($AuditExistingAct){
    if($Write){throw 'AUDIT_EXISTING_ACT_IS_READ_ONLY'}
    if([string]::IsNullOrWhiteSpace($ActId)){throw 'AUDIT_EXISTING_ACT_REQUIRES_ACT_ID'}
}else{
    if(-not $nextAct){throw 'ALL_ACTS_ALREADY_ATTESTED'}
    if([string]::IsNullOrWhiteSpace($ActId)){$ActId=$nextAct}elseif($ActId -cne $nextAct){throw "ACT_NOT_NEXT_IN_ATTEST_SEQUENCE: requested=$ActId expected=$nextAct"}
}
if($ActId -notin $actIds){throw "ACT_NOT_IN_ARCHITECTURE: $ActId"}
$actIndex=[Array]::IndexOf([string[]]$actIds,$ActId)
if($actIndex -lt 0){throw "ACT_NOT_IN_SEQUENCE: $ActId"}

$modelId=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_ID'
$modelRevision=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_REVISION'
$modelSettingsSha=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_SETTINGS_SHA256'
if(-not(Test-SystemV7ConcreteText $modelId) -or -not(Test-SystemV7ConcreteText $modelRevision) -or $modelSettingsSha -notmatch '^[A-F0-9]{64}$'){throw 'K3_MODEL_MANIFEST_INCOMPLETE'}
$modelManifestRelative=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_MANIFEST_PATH'
$modelManifestCandidate=[IO.Path]::GetFullPath((Join-Path $project $modelManifestRelative));$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $modelManifestCandidate
if(-not(Test-Path -LiteralPath $modelManifestCandidate -PathType Leaf)){throw 'K3_MODEL_MANIFEST_MISSING'}
if($Write){$inputSnapshot.model_manifest=(Get-FileHash -LiteralPath $modelManifestCandidate -Algorithm SHA256).Hash}
$modelManifest=Get-SystemV7K3ModelManifestState -ProjectPath $project -MetaText $meta
if(-not $modelManifest.Valid){throw "K3_MODEL_MANIFEST_INVALID: $($modelManifest.Errors -join '; ')"}
if($Write){$inputSnapshot.model_settings=[string]$modelManifest.Data.settings_sha256}

$continuityDir=Join-Path $project '_work\k3\continuity'
$actsDir=Join-Path $project '_work\k3\acts'
$packetsDir=Join-Path $project '_work\k3\packets'
$prefixDir=Join-Path $project '_work\k3\prefix'
if($actIndex -eq 0){
    $continuityIn=[ordered]@{schema='CONTINUITY_IN_V1';act_id=$ActId;source_act_id='NONE';source_act_sha256='NONE';source_attest_sha256='NONE';text_states=@();viewer_inferences=@();open_nq_ids=@();prepared_nr_ids=@();active_embargoes=@();world_state=@();bridge='START';opening_move_history=@();closing_move_history=@();emotional_pressure='START'}
}else{
    for($i=0;$i -lt $actIndex;$i++){
        $previousId=$actIds[$i]
        $priorAttestState=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $previousId
        if(-not $priorAttestState.Valid){throw "SEQUENTIAL_GATE_FAIL: invalid attest for $previousId/$($priorAttestState.Errors -join '; ')"}
    }
    $previousId=$actIds[$actIndex-1]
    $attestPath=Join-Path $continuityDir "$previousId.attest.json"
    $priorAttestState=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $previousId
    if(-not $priorAttestState.Valid){throw "SEQUENTIAL_GATE_FAIL: invalid immediate prior attest/$($priorAttestState.Errors -join '; ')"}
    $attest=$priorAttestState.Data
    $continuityIn=$attest.next_continuity_in
    $continuityIn.source_attest_sha256=(Get-FileHash -LiteralPath $attestPath -Algorithm SHA256).Hash
    if([string]$continuityIn.act_id -cne $ActId){throw "CONTINUITY_NEXT_ACT_MISMATCH: $ActId"}
}
$continuityJson=ConvertTo-SystemV7CanonicalJson -Value $continuityIn
$continuitySha=Get-SystemV7NarrativeSha256Text -Text $continuityJson

if([string]::IsNullOrWhiteSpace($VoiceProfilePath)){
    $declaredRevisionForPath=Get-SystemV7NarrativeMetaField -Text $meta -Name 'VOICE_PROFILE_REVISION'
    $VoiceProfilePath=Join-Path $systemRoot "_SYSTEM\NARRATIVE\VOICE-PROFILES\$declaredRevisionForPath.md"
}
if($Write){if(-not(Test-Path -LiteralPath $VoiceProfilePath -PathType Leaf)){throw 'VOICE_PROFILE_MISSING'};$inputSnapshot.voice=(Get-FileHash -LiteralPath $VoiceProfilePath -Algorithm SHA256).Hash}
$voice=Get-SystemV7VoiceProfileState -ProfilePath $VoiceProfilePath -AllowTestApproved:$AllowTestVoiceProfile
if(-not $voice.Valid){throw "VOICE_PROFILE_INVALID: $($voice.Errors -join '; ')"}
$declaredVoiceRevision=Get-SystemV7NarrativeMetaField -Text $meta -Name 'VOICE_PROFILE_REVISION'
if($declaredVoiceRevision -cne $voice.Revision){throw "VOICE_PROFILE_REVISION_MISMATCH: meta=$declaredVoiceRevision profile=$($voice.Revision)"}
if(-not $AllowTestVoiceProfile){
    $selection=Get-SystemV7VoiceProfileSelectionState -ProjectPath $project -MetaText $meta
    if(-not $selection.Valid){throw "VOICE_PROFILE_SELECTION_INVALID: $($selection.Errors -join '; ')"}
}

$corePath=Join-Path $systemRoot '_SYSTEM\NARRATIVE\K3-RULES-CORE.md'
if($Write){$inputSnapshot.core=(Get-FileHash -LiteralPath $corePath -Algorithm SHA256).Hash}
$core=(ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $corePath -Raw -Encoding UTF8)).Trim()+"`n"
$spine=Get-SystemV7StorySpineProjection -ArchitectureData $architecture.Data
$prefixText=@(
    '<!-- SYSTEM_V7_STABLE_PREFIX_V2 -->'
    '## K3_RULES_CORE'
    $core.TrimEnd()
    '## PROJECT_STORY_SPINE'
    $spine.Json.TrimEnd()
    '## VOICE_RULES'
    $voice.Rules.TrimEnd()
    '## VOICE_EXEMPLARS'
    $voice.Exemplars.TrimEnd()
    '<!-- END_SYSTEM_V7_STABLE_PREFIX_V2 -->'
) -join "`n"
$prefixText=$prefixText.TrimEnd()+"`n"
$prefixSha=Get-SystemV7NarrativeSha256Text -Text $prefixText

$actProjection=Get-SystemV7ActProjection -ArchitectureData $architecture.Data -ActId $ActId
$selection=Get-SystemV7EvidenceSelectionProjection -ActProjection $actProjection -EvidenceRegistry $evidence
$act=$actProjection.Act
$constraints=@($act.constraints)
if($constraints.Count -gt $script:SystemV7NarrativeMaxConstraints){throw "OVERLOADED_ACT_PACKET: $ActId"}
$continuityCid=@($constraints|Where-Object{[string]$_.source_field -ceq 'CONTINUITY_OUT'})
if($continuityCid.Count -ne 1){throw "CONTINUITY_OUT_CID_COUNT_INVALID: $ActId"}
$nqRegistryIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($action in @($act.nq_actions)){foreach($m in [regex]::Matches([string]$action,'NQ-\d{3}')){$null=$nqRegistryIds.Add([string]$m.Value)}}
foreach($id in @($act.open_nq_ids)){$null=$nqRegistryIds.Add([string]$id)}
$nrRegistryIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($action in @($act.nr_actions)){foreach($m in [regex]::Matches([string]$action,'NR-\d{3}')){$null=$nrRegistryIds.Add([string]$m.Value)}}
$vcRegistryIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($id in @($act.vc_ids)){$null=$vcRegistryIds.Add([string]$id)}
$actionRegistry=[ordered]@{
    schema='NARRATIVE_ACTION_REGISTRY_V1';act_id=$ActId
    questions=@($architecture.Data.questions|Where-Object{$nqRegistryIds.Contains([string]$_.nq_id)})
    reveals=@($architecture.Data.reveals|Where-Object{$nrRegistryIds.Contains([string]$_.nr_id)})
    viewer_contacts=@($architecture.Data.viewer_contacts|Where-Object{$vcRegistryIds.Contains([string]$_.vc_id)})
}
$actionRegistryJson=ConvertTo-SystemV7CanonicalJson -Value $actionRegistry
$actionRegistrySha=Get-SystemV7NarrativeSha256Text -Text $actionRegistryJson
$sceneContracts=[Collections.Generic.List[object]]::new()
foreach($swId in @($act.scene_weave_ids)){
    $sw=@($architecture.Data.scene_weave|Where-Object{[string]$_.sw_id -ceq [string]$swId})
    if($sw.Count -ne 1){throw "SCENE_CONTRACT_SW_INVALID: $swId"}
    $vcIds=@($architecture.Data.viewer_contacts|Where-Object{[string]$_.node -ceq [string]$swId -and $vcRegistryIds.Contains([string]$_.vc_id)}|ForEach-Object{[string]$_.vc_id})
    $nrAction=if([string]::IsNullOrWhiteSpace([string]$sw[0].nr_action)){'BRAK'}else{[string]$sw[0].nr_action}
    $nrEvidence=@()
    if($nrAction -match '^REVEAL:(NR-\d{3})$'){
        $nrRecord=@($actionRegistry.reveals|Where-Object{[string]$_.nr_id -ceq [string]$Matches[1]})
        if($nrRecord.Count -ne 1){throw "SCENE_CONTRACT_REVEAL_REGISTRY_MISSING: $swId/$nrAction"}
        $nrEvidence=@([string[]]@($nrRecord[0].evidence_p_ids))
    }
    $sceneContracts.Add([ordered]@{
        sw_id=[string]$swId;scene_or_unit=[string]$sw[0].scene_or_unit;function=[string]$sw[0].function
        entry_knowledge_state=[string]$sw[0].entry_knowledge_state;exit_knowledge_state=[string]$sw[0].exit_knowledge_state;emotional_pressure=[string]$sw[0].emotional_pressure
        required_p=@($sw[0].required_evidence|ForEach-Object{[string]$_.p_id});supporting_p=@($sw[0].supporting_p_ids|ForEach-Object{[string]$_})
        nq_action=if([string]::IsNullOrWhiteSpace([string]$sw[0].nq_action)){'BRAK'}else{[string]$sw[0].nq_action};nr_action=$nrAction;nr_evidence_p=$nrEvidence;vc_ids=$vcIds
        local_stake=[string]$sw[0].local_stake;bridge_out=[string]$sw[0].bridge_out;completion_criteria=[string]$sw[0].completion_criteria
    })
}

$packetCore=[ordered]@{
    packet_schema=$script:SystemV7NarrativePacketSchema;workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_id=[string]$origin.ProjectId;act_id=$ActId
    act_function=$act.act_function;entry_knowledge_state=$act.entry_knowledge_state;exit_knowledge_state=$act.exit_knowledge_state
    intended_emotional_pressure_in=$act.intended_emotional_pressure_in;intended_emotional_pressure_out=$act.intended_emotional_pressure_out
    scene_weave_ids=@($act.scene_weave_ids);scene_contracts=@($sceneContracts);narrative_action_registry=$actionRegistry;narrative_action_registry_sha256=$actionRegistrySha;constraint_ids=@($constraints|ForEach-Object{[string]$_.cid})
    required_p=@($selection.RequiredIds);supporting_p=@($selection.SupportingIds);open_nq_ids=@($act.open_nq_ids);nq_actions=@($act.nq_actions);nr_actions=@($act.nr_actions);vc_ids=@($act.vc_ids)
    humor_mode=$act.humor_mode;narrator_mode=$act.narrator_mode;new_names=@($act.new_names);exposition_risk=$act.exposition_risk;complexity_flag=$act.complexity_flag
    completion_criteria=@($act.completion_criteria);bridge_out=$act.bridge_out;do_not_reveal=@($act.do_not_reveal);continuity_in_sha256=$continuitySha;prefix_sha256=$prefixSha
    # Pakiet wiąże wyłącznie semantyczne projekcje używane przez ten akt.
    # Pełne 02 i 01 są walidowane przed kompilacją, lecz ich globalne hashe nie
    # mogą unieważniać aktów, których treść ani wybór dowodów się nie zmieniły.
    act_projection_sha256=$actProjection.Sha256;evidence_selection_sha256=$selection.Sha256
    model_id=$modelId;model_revision=$modelRevision;model_settings_sha256=$modelSettingsSha;packet_status='PRECHECK_PENDING'
}
$packetCoreJson=ConvertTo-SystemV7CanonicalJson -Value $packetCore
$constraintJson=ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='CONSTRAINT_LEDGER_V1';act_id=$ActId;max_total=7;actual_total=$constraints.Count;constraints=$constraints})
$embargoJson=ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='DO_NOT_REVEAL_V1';act_id=$ActId;items=@($act.do_not_reveal)})
$writeCommand=if([string]$act.complexity_flag -ceq 'COMPLEX'){@"
Pracujesz wyłącznie nad aktem $ActId w jednym świeżym kontekście. Najpierw sprawdź wystarczalność paczki. Nie pisz jeszcze prozy.

Jeśli paczka wystarcza, pierwsza odpowiedź ma być jednym obiektem JSON `K3_BEAT_SHEET_V1`: schema, act_id, packet_status=`BEAT_SHEET_READY` oraz beats[]. Każdy beat ma dokładnie: beat_id (`BEAT-001`...), sw_id, function, source_p_ids[], state_before, state_after i nq_nr_vc_ids[]. W ``nq_nr_vc_ids[]`` wpisuj dokładne tokeny akcji z kontraktu sceny (np. `PAY:NQ-001`, `REFRAME:NQ-001->NQ-002`, `REVEAL:NR-001`, `CONSEQUENCE:NR-001`) oraz identyfikatory VC. `NARRATIVE_ACTION_REGISTRY` zawiera pełną treść pytań, ujawnień i kontaktów; dokładny zatwierdzony `AUTHOR_TEXT` ma wystąpić dosłownie. Każdy REQUIRED_P i każdy token akcji/VC musi być pokryty w swoim SW. `REVEAL:NR` musi wystąpić w tym samym beacie i później w tym samym bloku co wszystkie jego ``nr_evidence_p``. Nie dodawaj źródła, revealu ani obowiązku spoza paczki. Po imporcie i niezależnym PASS BEAT_PREFLIGHT wrócisz w tej samej sesji i dopiero wtedy zwrócisz `K3_ACT_SUBMISSION_V2` z packet_status=`PROSE_READY`, self_check=`PASS` oraz blocks[]. Każdy blok ma dokładnie: trace_refs[] (BEAT_ID), source_p_ids[], narrative_refs[] (dokładne tokeny z beatów) i prose.

Jeśli paczka nie wystarcza, zwróć jeden obiekt JSON: schema=`K3_ACT_SUBMISSION_V2`, act_id, packet_status=`PACKET_INSUFFICIENT`, no_prose_generated=true, blocks=[], reason_code, sw_id, exact_gap, why_blocking, affected_ids[] i repair_route. Nie dodawaj żadnej prozy.

Po imporcie prozy system zwróci mapę BLOCK_ID/BLOCK_SHA. W następnej turze tej samej sesji przygotuj jeden obiekt JSON `CONTINUITY_OUT_V1`. Nie zaczynaj nowego kontekstu Claude'a i nie przepisuj prozy.
"@}else{@"
Napisz wyłącznie akt $ActId w tym świeżym kontekście. Najpierw sprawdź wystarczalność paczki.

Jeśli paczka wystarcza, pierwsza odpowiedź ma być jednym obiektem JSON `K3_ACT_SUBMISSION_V2`: act_id, packet_status=`PROSE_READY`, self_check=`PASS` oraz blocks[]. Każdy blok ma dokładnie trace_refs[] (SW_ID), source_p_ids[], narrative_refs[] (dokładne tokeny akcji NQ/NR i identyfikatory VC z kontraktu SW) oraz prose. `NARRATIVE_ACTION_REGISTRY` zawiera pełną treść pytań, ujawnień i kontaktów; dokładny zatwierdzony `AUTHOR_TEXT` ma wystąpić dosłownie. Wszystkie REQUIRED_P, SW i tokeny akcji/VC muszą być pokryte, a `REVEAL:NR` ma współwystąpić w jednym bloku ze wszystkimi jego ``nr_evidence_p``. Blok jest techniczną jednostką śladu do 220 słów, nie limitem aktu. Nie nadawaj BLOCK_ID.

Jeśli paczka nie wystarcza, zwróć jeden obiekt JSON: schema=`K3_ACT_SUBMISSION_V2`, act_id, packet_status=`PACKET_INSUFFICIENT`, no_prose_generated=true, blocks=[], reason_code, sw_id, exact_gap, why_blocking, affected_ids[] i repair_route. Nie dodawaj żadnej prozy.

Po imporcie system zwróci mapę BLOCK_ID/BLOCK_SHA. Dopiero wtedy, w drugiej turze tej samej sesji, przygotuj jeden obiekt JSON `CONTINUITY_OUT_V1`. Nie zaczynaj nowego kontekstu Claude'a i nie przepisuj prozy.
"@}
$writeCommand=$writeCommand.Trim()+"`n"

$evidenceMarkdown=($selection.Value.cards|ForEach-Object{"### $($_.p_id) [$($_.role)]`nTREŚĆ: $($_.content)`nŹRÓDŁO_ID: $($_.source_id)`nREJESTR_ŹRÓDŁA: $($_.source_registry_row)`nLOKALIZACJA: $($_.locator)`nQA_K1: $($_.qa_k1)"}) -join "`n`n"
$packetMarkdown=$prefixText+@"
## CONTINUITY_IN
$($continuityJson.TrimEnd())

## DOSŁOWNE KARTY ŹRÓDŁOWE
$evidenceMarkdown

## ACT_PACKET
$($packetCoreJson.TrimEnd())

## ACT_HARD_CONSTRAINTS
$($constraintJson.TrimEnd())

## DO_NOT_REVEAL
$($embargoJson.TrimEnd())

## POLECENIE PISANIA I FORMAT WYNIKU
$($writeCommand.TrimEnd())
"@
$packetMarkdown=(ConvertTo-SystemV7LfText -Text $packetMarkdown).TrimEnd()+"`n"
$packetSha=Get-SystemV7NarrativeSha256Text -Text $packetMarkdown
$packetRecord=[ordered]@{schema='K3_PACKET_RECORD_V2';act_id=$ActId;prefix_sha256=$prefixSha;packet_sha256=$packetSha;act_projection_sha256=$actProjection.Sha256;evidence_selection_sha256=$selection.Sha256;narrative_action_registry_sha256=$actionRegistrySha;continuity_in_sha256=$continuitySha;model_id=$modelId;model_revision=$modelRevision;model_settings_sha256=$modelSettingsSha;status='PRECHECK_PENDING'}

$result=[ordered]@{Verdict='PACKET_PREVIEW_OK';ActId=$ActId;PrefixSha256=$prefixSha;PacketSha256=$packetSha;ConstraintCount=$constraints.Count;ContinuityInSha256=$continuitySha;ActProjectionSha256=$actProjection.Sha256;EvidenceSelectionSha256=$selection.Sha256;NarrativeActionRegistrySha256=$actionRegistrySha;Written=$false;PacketPath=(Join-Path $packetsDir "$ActId.packet.md")}
if($Write){
    $lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
    $transactionRoot=Join-Path $project '_work\k3-transactions';$transactionPath=Join-Path $transactionRoot ([guid]::NewGuid().ToString('N'));$writtenTargets=[Collections.Generic.List[string]]::new();$before=@{};$stageCreated=$false
    try{
        foreach($pair in @(@($metaPath,$inputSnapshot.meta,'META'),@($architecturePath,$inputSnapshot.architecture,'ARCHITECTURE'),@($evidencePath,$inputSnapshot.evidence,'EVIDENCE'),@($voice.Path,$inputSnapshot.voice,'VOICE'),@($corePath,$inputSnapshot.core,'CORE'),@($modelManifest.Path,$inputSnapshot.model_manifest,'MODEL_MANIFEST'),@($modelManifest.SettingsPath,$inputSnapshot.model_settings,'MODEL_SETTINGS'))){if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -cne $pair[1]){throw "K3_PACKET_INPUT_CHANGED: $($pair[2])"}}
        foreach($priorId in @($inputSnapshot.prior_attests.Keys)){if((Get-FileHash -LiteralPath (Join-Path $continuityDir "$priorId.attest.json") -Algorithm SHA256).Hash -cne [string]$inputSnapshot.prior_attests[$priorId]){throw "K3_PACKET_INPUT_CHANGED: PRIOR_ATTEST/$priorId"}}
        $lockedMeta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;&$assertWritePolicy $lockedMeta;$lockedModel=Get-SystemV7K3ModelManifestState -ProjectPath $project -MetaText $lockedMeta;if(-not $lockedModel.Valid){throw "K3_MODEL_MANIFEST_CHANGED: $($lockedModel.Errors -join '; ')"}
        $lockedVoice=Get-SystemV7VoiceProfileState -ProfilePath $voice.Path -AllowTestApproved:$AllowTestVoiceProfile;if(-not $lockedVoice.Valid -or $lockedVoice.Revision -cne $voice.Revision -or $lockedVoice.RulesSha256 -cne $voice.RulesSha256 -or $lockedVoice.ExemplarsSha256 -cne $voice.ExemplarsSha256){throw 'VOICE_PROFILE_CHANGED'}
        for($i=0;$i -lt $actIndex;$i++){$prior=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $actIds[$i];if(-not $prior.Valid){throw "SEQUENTIAL_GATE_CHANGED: $($actIds[$i])/$($prior.Errors -join '; ')"}}
        foreach($candidate in $actIds){$candidateAttest=Join-Path $project "_work\k3\continuity\$candidate.attest.json";if(-not(Test-Path -LiteralPath $candidateAttest -PathType Leaf)){if($candidate -cne $ActId){throw "NEXT_ACT_CHANGED_DURING_PACKET_BUILD: expected=$ActId actual=$candidate"};break}}
        foreach($dir in @($continuityDir,$actsDir,$packetsDir,$prefixDir)){[IO.Directory]::CreateDirectory($dir)|Out-Null}
        $existingActs=@(Get-ChildItem -LiteralPath $actsDir -File -Recurse -ErrorAction SilentlyContinue)
        $manifestPath=Join-Path $prefixDir 'prefix.manifest.json'
        if(Test-Path -LiteralPath $manifestPath -PathType Leaf){
            $existing=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
            $voiceBindingStale=([string]$existing.voice_profile_revision -cne $voice.Revision -or
                [string]$existing.voice_profile_sha256 -cne $voice.ProfileSha256 -or
                [string]$existing.voice_exemplar_registry_sha256 -cne $voice.ExemplarRegistrySha256 -or
                [string]$existing.voice_rules_sha256 -cne $voice.RulesSha256 -or
                [string]$existing.voice_exemplars_sha256 -cne $voice.ExemplarsSha256)
            if(($voiceBindingStale -or [string]$existing.prefix_sha256 -cne $prefixSha) -and $existingActs.Count -gt 0){throw 'PREFIX_STALE: existing prose requires full regeneration'}
        }
        $targetPacket=Join-Path $packetsDir "$ActId.packet.md"
        $targetRecord=Join-Path $packetsDir "$ActId.packet.json"
        $actWorkDir=Join-Path $actsDir $ActId
        if(Test-Path -LiteralPath $actWorkDir){throw "ACT_ALREADY_HAS_WORK_STATE: $ActId"}
        if((Test-Path -LiteralPath $targetPacket -PathType Leaf) -and -not $Force){throw "PACKET_ALREADY_EXISTS: $ActId"}
        $prefixManifest=[ordered]@{schema='K3_PREFIX_MANIFEST_V2';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_id=[string]$origin.ProjectId;voice_profile_revision=$voice.Revision;voice_profile_sha256=$voice.ProfileSha256;voice_exemplar_registry_sha256=$voice.ExemplarRegistrySha256;core_sha256=(Get-SystemV7NarrativeSha256Text -Text $core);story_spine_content_sha256=$spine.Sha256;voice_rules_sha256=$voice.RulesSha256;voice_exemplars_sha256=$voice.ExemplarsSha256;prefix_sha256=$prefixSha}
        $preflightStub=[ordered]@{schema='CONSTRAINT_ATOMICITY_PREFLIGHT_V1';act_id=$ActId;packet_sha256=$packetSha;constraint_ledger_sha256=(Get-SystemV7NarrativeSha256Text -Text $constraintJson);status='PENDING';run_receipt_relative='BRAK';run_receipt_sha256='BRAK'}
        $targets=[Collections.Generic.List[object]]::new()
        foreach($entry in @(
            @((Join-Path $prefixDir 'K3_RULES_CORE.md'),$core),@((Join-Path $prefixDir 'PROJECT_STORY_SPINE.json'),$spine.Json),@((Join-Path $prefixDir 'VOICE_RULES.md'),$voice.Rules),@((Join-Path $prefixDir 'VOICE_EXEMPLARS.md'),$voice.Exemplars),@((Join-Path $prefixDir 'prefix.bundle.md'),$prefixText),@($manifestPath,(ConvertTo-SystemV7CanonicalJson -Value $prefixManifest)),
            @((Join-Path $continuityDir "$ActId.in.json"),$continuityJson),@($targetPacket,$packetMarkdown),@($targetRecord,(ConvertTo-SystemV7CanonicalJson -Value $packetRecord)),@((Join-Path $packetsDir "$ActId.act-packet.json"),$packetCoreJson),@((Join-Path $packetsDir "$ActId.narrative-action-registry.json"),$actionRegistryJson),@((Join-Path $packetsDir "$ActId.evidence-selection.json"),$selection.Json),@((Join-Path $packetsDir "$ActId.constraint-ledger.json"),$constraintJson),@((Join-Path $packetsDir "$ActId.do-not-reveal.json"),$embargoJson),@((Join-Path $packetsDir "$ActId.write-command.md"),$writeCommand),@((Join-Path $packetsDir "$ActId.constraint-preflight.json"),(ConvertTo-SystemV7CanonicalJson -Value $preflightStub))
        )){$targets.Add([pscustomobject]@{Path=[string]$entry[0];Text=[string]$entry[1]})}
        [IO.Directory]::CreateDirectory($transactionPath)|Out-Null;$stageCreated=$true;$ordinal=0
        foreach($target in $targets){$ordinal++;$stage=Join-Path $transactionPath ("{0:D2}.staged" -f $ordinal);Write-SystemV7NarrativeAtomicText -Path $stage -Text $target.Text|Out-Null;$target|Add-Member -NotePropertyName StagePath -NotePropertyValue $stage}
        foreach($target in $targets){$before[$target.Path]=if(Test-Path -LiteralPath $target.Path -PathType Leaf){[IO.File]::ReadAllBytes($target.Path)}else{$null};Write-SystemV7NarrativeAtomicText -Path $target.Path -Text (Get-Content -LiteralPath $target.StagePath -Raw -Encoding UTF8)|Out-Null;$writtenTargets.Add($target.Path)}
        $updatedMeta=Set-SystemV7NarrativeMetaField -Text $lockedMeta -Name 'K3_PREFIX_SHA256' -Value $prefixSha
        $updatedMeta=Set-SystemV7NarrativeMetaField -Text $updatedMeta -Name 'NARRATIVE_ACT_SEQUENCE' -Value ($actIds -join ',')
        Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text (ConvertTo-SystemV7LfText -Text $updatedMeta) -ExpectedCurrentSha256 $inputSnapshot.meta -HeldLockStream $lock|Out-Null
        $result.Verdict='PACKET_WRITTEN_PRECHECK_PENDING';$result.Written=$true
    }catch{
        for($i=$writtenTargets.Count-1;$i -ge 0;$i--){$target=$writtenTargets[$i];$bytes=$before[$target];if($null -eq $bytes){if(Test-Path -LiteralPath $target -PathType Leaf){[IO.File]::Delete($target)}}else{[IO.File]::WriteAllBytes($target,$bytes)}}
        throw
    }finally{
        try{if($stageCreated -and (Test-Path -LiteralPath $transactionPath -PathType Container)){$relativeTx=Get-SystemV7NarrativeRelativePath -Root $project -Path $transactionPath;if($relativeTx -notmatch '^_work/k3-transactions/[a-f0-9]{32}$'){throw 'K3_TRANSACTION_CLEANUP_PATH_UNSAFE'};[IO.Directory]::Delete($transactionPath,$true)}}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
    }
}
[pscustomobject]$result
