[CmdletBinding(DefaultParameterSetName='PROSE')]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9._-]{7,80}$')][string]$RunId,
    [Parameter(Mandatory,ParameterSetName='PROSE')][string]$SubmissionPath,
    [Parameter(Mandatory,ParameterSetName='FINALIZE')][string]$ContinuityOutPath,
    [Parameter(Mandatory,ParameterSetName='FINALIZE')][string]$TaskId,
    [Parameter(Mandatory,ParameterSetName='FINALIZE')][DateTimeOffset]$StartedAt
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$mutationLock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
try{
$metaPath=Join-Path $project 'meta.md';$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K3'){throw 'IMPORT_K3_ACT_REQUIRES_STAGE_K3'}
$manifestPath=Join-Path $project "_work\narrative-runs\$RunId\input-manifest.json"
$bundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $manifestPath -RequireLiveSource
if(-not $bundle.Valid -or [string]$bundle.Data.run_type -cne 'GENERATE_ACT'){throw "GENERATE_BUNDLE_INVALID: $($bundle.Errors -join '; ')"}
$packetEntry=@($bundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PACKET'})
if($packetEntry.Count -ne 1){throw 'GENERATE_BUNDLE_ACT_PACKET_INVALID'}
$packet=Get-Content -LiteralPath (Join-Path $project ([string]$packetEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
if([string]$packet.act_id -cne $ActId){throw 'RUN_ACT_ID_MISMATCH'}
if([string]$packet.prefix_sha256 -cne (Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_PREFIX_SHA256')){throw 'PREFIX_STALE'}
if([string]$packet.model_id -cne (Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_ID') -or [string]$packet.model_revision -cne (Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_REVISION')){throw 'MODEL_STALE'}
$actDir=Join-Path $project "_work\k3\acts\$ActId"

if($PSCmdlet.ParameterSetName -ceq 'PROSE'){
    if(Test-Path -LiteralPath $actDir){throw "ACT_WORK_STATE_ALREADY_EXISTS: $ActId"}
    if(-not(Test-Path -LiteralPath $SubmissionPath -PathType Leaf)){throw 'K3_SUBMISSION_MISSING'}
    try{$submission=Get-Content -LiteralPath $SubmissionPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{throw "K3_SUBMISSION_INVALID_JSON: $($_.Exception.Message)"}
    if([string]$submission.schema -cne 'K3_ACT_SUBMISSION_V2' -or [string]$submission.act_id -cne $ActId){throw 'K3_SUBMISSION_SCHEMA_OR_ACT_INVALID'}
    $packetStatus=[string]$submission.packet_status
    $stageDir=Join-Path (Split-Path -Parent $actDir) ('.stage-'+$ActId+'-'+[guid]::NewGuid().ToString('N'))
    $actCreated=$false
    [IO.Directory]::CreateDirectory($stageDir)|Out-Null
    try{
        if($packetStatus -ceq 'PACKET_INSUFFICIENT'){
            $expected=@('schema','act_id','packet_status','no_prose_generated','blocks','reason_code','sw_id','exact_gap','why_blocking','affected_ids','repair_route')
            if(@(Compare-Object -ReferenceObject $expected -DifferenceObject @($submission.PSObject.Properties.Name)).Count -gt 0 -or @($submission.PSObject.Properties.Name).Count -ne $expected.Count){throw 'PACKET_INSUFFICIENT_FIELDS_INVALID'}
            if($submission.no_prose_generated -cne $true -or @($submission.blocks).Count -ne 0){throw 'PACKET_INSUFFICIENT_WITH_PROSE'}
            if([string]$submission.reason_code -notin @('MISSING_EVIDENCE','CONTRADICTORY_CONSTRAINTS','INSUFFICIENT_FUEL','UNSUPPORTED_BRIDGE','CONTINUITY_CONFLICT')){throw 'PACKET_INSUFFICIENT_REASON_INVALID'}
            if([string]$submission.repair_route -notin @('K2B_REPACK','PROMOTE_RESERVE_BY_DECISION','REWRITE_SCENE_WEAVE','REDUCE_SCOPE')){throw 'PACKET_INSUFFICIENT_ROUTE_INVALID'}
            Write-SystemV7NarrativeAtomicText -Path (Join-Path $stageDir 'packet-insufficient.json') -Text (ConvertTo-SystemV7CanonicalJson -Value $submission)|Out-Null
            $state=[ordered]@{schema='K3_ACT_STATE_V1';act_id=$ActId;run_id=$RunId;status='PACKET_INSUFFICIENT';prefix_sha256=[string]$packet.prefix_sha256;model_id=[string]$packet.model_id;model_revision=[string]$packet.model_revision;submission_sha256=(Get-FileHash -LiteralPath $SubmissionPath -Algorithm SHA256).Hash}
            Write-SystemV7NarrativeAtomicText -Path (Join-Path $stageDir 'state.json') -Text (ConvertTo-SystemV7CanonicalJson -Value $state)|Out-Null
            [IO.Directory]::Move($stageDir,$actDir);$actCreated=$true
            $liveState=Get-Content -LiteralPath (Join-Path $actDir 'state.json') -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String;if([string]$liveState.status -cne 'PACKET_INSUFFICIENT' -or [string]$liveState.run_id -cne $RunId){throw 'PACKET_INSUFFICIENT_POSTVALIDATION_FAILED'}
            [pscustomobject]@{Status='PACKET_INSUFFICIENT';ActId=$ActId;RunId=$RunId;RepairRoute=[string]$submission.repair_route;StatePath=(Join-Path $actDir 'state.json')}
            return
        }
        if($packetStatus -cne 'PROSE_READY' -or [string]$submission.self_check -cne 'PASS'){throw 'K3_PROSE_SUBMISSION_NOT_READY'}
        $beatSheetSha='NOT_APPLICABLE';$beatSheetForTrace=$null
        if([string]$packet.complexity_flag -ceq 'COMPLEX'){
            $beatDir=Join-Path $project "_work\k3\beats\$ActId";$beatStatePath=Join-Path $beatDir 'state.json';$beatSheetLive=Join-Path $beatDir 'beat-sheet.json'
            foreach($path in @($beatStatePath,$beatSheetLive)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "COMPLEX_ACT_BEAT_PREFLIGHT_MISSING: $path"}}
            $beatState=Get-Content -LiteralPath $beatStatePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
            if([string]$beatState.status -cne 'BEAT_PREFLIGHT_PASS' -or [string]$beatState.generate_run_id -cne $RunId -or [string]$beatState.prefix_sha256 -cne [string]$packet.prefix_sha256 -or [string]$beatState.model_id -cne [string]$packet.model_id -or [string]$beatState.model_revision -cne [string]$packet.model_revision){throw 'COMPLEX_ACT_BEAT_STATE_STALE'}
            $beatReceiptPath=Join-Path $project ([string]$beatState.preflight_receipt_relative);$beatProof=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $beatReceiptPath -ExpectedRunType 'BEAT_PREFLIGHT' -RequireLiveInputs
            if(-not $beatProof.Valid -or [string]$beatProof.Sha256 -cne [string]$beatState.preflight_receipt_sha256){throw "COMPLEX_ACT_BEAT_RECEIPT_INVALID: $($beatProof.Errors -join '; ')"}
            $beatText=Get-Content -LiteralPath $beatSheetLive -Raw -Encoding UTF8;$beatSheetSha=Get-SystemV7NarrativeSha256Text -Text $beatText;$beatSheetForTrace=$beatText|ConvertFrom-Json -DateKind String -Depth 64
            if($beatSheetSha -cne [string]$beatState.beat_sheet_sha256){throw 'COMPLEX_ACT_BEAT_SHEET_STALE'}
            $beatBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath (Join-Path $project ([string]$beatProof.Data.input_manifest_relative)) -RequireLiveSource;if(-not $beatBundle.Valid){throw 'COMPLEX_ACT_BEAT_BUNDLE_NOT_LIVE'};$beatPacketEntry=@($beatBundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PACKET'});$beatSheetEntry=@($beatBundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'BEAT_SHEET'});if($beatPacketEntry.Count -ne 1 -or $beatSheetEntry.Count -ne 1 -or [string]$beatPacketEntry[0].sha256 -cne (Get-FileHash -LiteralPath (Join-Path $project "_work\k3\packets\$ActId.act-packet.json") -Algorithm SHA256).Hash -or [string]$beatSheetEntry[0].sha256 -cne $beatSheetSha){throw 'COMPLEX_ACT_BEAT_PROOF_CURRENT_INPUT_MISMATCH'}
        }elseif(Test-Path -LiteralPath (Join-Path $project "_work\k3\beats\$ActId") -PathType Container){throw 'SIMPLE_ACT_HAS_UNEXPECTED_BEAT_STATE'}
        $expected=@('schema','act_id','packet_status','self_check','blocks')
        if(@(Compare-Object -ReferenceObject $expected -DifferenceObject @($submission.PSObject.Properties.Name)).Count -gt 0 -or @($submission.PSObject.Properties.Name).Count -ne $expected.Count){throw 'K3_PROSE_SUBMISSION_FIELDS_INVALID'}
        if(@($submission.blocks).Count -eq 0){throw 'ACT_PROSE_EMPTY'}
        $selectionPath=Join-Path $project "_work\k3\packets\$ActId.evidence-selection.json"
        $selection=Get-Content -LiteralPath $selectionPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
        $allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($card in @($selection.cards)){$null=$allowed.Add([string]$card.p_id)}
        $rawBlockRecords=[Collections.Generic.List[object]]::new();$clean=[Collections.Generic.List[string]]::new();$idx=0
        $traceInputBlocks=[Collections.Generic.List[object]]::new()
        foreach($block in @($submission.blocks)){
            $fields=@('trace_refs','source_p_ids','narrative_refs','prose')
            if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($block.PSObject.Properties.Name)).Count -gt 0 -or @($block.PSObject.Properties.Name).Count -ne $fields.Count){throw 'K3_BLOCK_FIELDS_INVALID'}
            $prose=(ConvertTo-SystemV7LfText -Text ([string]$block.prose)).Trim()
            if([string]::IsNullOrWhiteSpace($prose)){throw 'K3_BLOCK_PROSE_EMPTY'}
            if($prose -match '(?i)\bBLOCK-(?:ACT-)?\d|#P-\d{3}|<!--|PACKET_STATUS|SELF_CHECK'){throw 'K3_BLOCK_TECHNICAL_RESIDUE'}
            $null=Assert-SystemV7PlainSpokenText -Text $prose -Context "K3_BLOCK_$ActId"
            $words=@([regex]::Matches($prose,"\b[\p{L}\p{N}][\p{L}\p{N}\p{M}’'-]*\b")).Count
            if($words -gt $script:SystemV7NarrativeBlockWordLimit){throw "BLOCK_TRACE_GRANULARITY_EXCEEDED: $words"}
            $traceRefs=@([string[]]@($block.trace_refs));$sourceIds=@([string[]]@($block.source_p_ids));$narrativeRefs=@([string[]]@($block.narrative_refs))
            if($sourceIds.Count -eq 0){throw 'K3_BLOCK_WITHOUT_SOURCE_TRACE'}
            foreach($p in $sourceIds){if($p -notmatch '^#P-\d{3,}$' -or -not $allowed.Contains($p)){throw "K3_BLOCK_ILLEGAL_SOURCE: $p"}}
            $idx++;$blockId='BLOCK-{0}-{1:D3}' -f $ActId,$idx;$blockSha=Get-SystemV7NarrativeSha256Text -Text ($prose+"`n")
            $traceInputBlocks.Add([pscustomobject]@{trace_refs=$traceRefs;source_p_ids=$sourceIds;narrative_refs=$narrativeRefs;prose=$prose})
            $rawBlockRecords.Add([ordered]@{block_id=$blockId;block_sha256=$blockSha;word_count=$words;trace_refs=$traceRefs;source_p_ids=$sourceIds;narrative_refs=$narrativeRefs;prose=$prose});$clean.Add($prose)
        }
        $traceState=Get-SystemV7ActSubmissionTraceState -Packet $packet -Blocks @($traceInputBlocks) -BeatSheet $beatSheetForTrace;if(-not $traceState.Valid){throw "K3_ACT_TRACE_INVALID: $($traceState.Errors -join '; ')"}
        $blockRecords=[Collections.Generic.List[object]]::new()
        foreach($rawBlock in $rawBlockRecords){$swIds=[Collections.Generic.List[string]]::new();$swSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($traceRef in @($rawBlock.trace_refs)){if(-not $traceState.TraceToSw.Contains([string]$traceRef)){throw "K3_TRACE_TO_SW_MISSING: $traceRef"};$swId=[string]$traceState.TraceToSw[[string]$traceRef];if($swSeen.Add($swId)){$swIds.Add($swId)}};if($swIds.Count -eq 0){throw "K3_BLOCK_SW_IDS_EMPTY: $($rawBlock.block_id)"};$blockRecords.Add([ordered]@{block_id=$rawBlock.block_id;block_sha256=$rawBlock.block_sha256;word_count=$rawBlock.word_count;trace_refs=@($rawBlock.trace_refs);sw_ids=@($swIds);source_p_ids=@($rawBlock.source_p_ids);narrative_refs=@($rawBlock.narrative_refs);prose=$rawBlock.prose})}
        $blockMap=[ordered]@{schema='K3_ACT_BLOCKS_V1';act_id=$ActId;run_id=$RunId;prefix_sha256=[string]$packet.prefix_sha256;model_id=[string]$packet.model_id;model_revision=[string]$packet.model_revision;submission_sha256=(Get-FileHash -LiteralPath $SubmissionPath -Algorithm SHA256).Hash;blocks=@($blockRecords)}
        Write-SystemV7NarrativeAtomicText -Path (Join-Path $stageDir 'blocks.json') -Text (ConvertTo-SystemV7CanonicalJson -Value $blockMap)|Out-Null
        Write-SystemV7NarrativeAtomicText -Path (Join-Path $stageDir 'prose.md') -Text (($clean -join "`n`n")+"`n")|Out-Null
        $stageBinding=Get-SystemV7ActProseBindingState -ActId $ActId -BlocksPath (Join-Path $stageDir 'blocks.json') -ProsePath (Join-Path $stageDir 'prose.md');if(-not $stageBinding.Valid){throw "K3_STAGE_PROSE_BINDING_INVALID: $($stageBinding.Errors -join '; ')"}
        $request=@"
# CONTINUITY_OUT — druga tura tej samej sesji Claude'a

Nie przepisuj prozy. Użyj dokładnie poniższej mapy. Zwróć jeden obiekt JSON `CONTINUITY_OUT_V1` z polami: schema, act_id, records[], nq_paid[], nq_opened[], nq_reframed[], open_nq_ids_out[], nr_revealed[], nr_consequences[], nr_setup_only[], character_and_world_state[], bridge_realized, bridge_block_refs[], opening_move_type, opening_block_refs[], closing_move_type, closing_block_refs[], uncertainties_preserved[]. Każdy rekord records[] ma dokładnie state_id, category, value, class, block_refs[], related_ids[], source_p_ids[]. Każdy element character_and_world_state[] ma dokładnie world_state_id, value, class, block_refs[], source_p_ids[]. Każdy element uncertainties_preserved[] ma dokładnie uncertainty_id, value, block_refs[], source_p_ids[]. Bridge oraz typy otwarcia i zamknięcia muszą wskazywać co najmniej jeden dokładny BLOCK_ID/BLOCK_SHA.

## Mapa bloków

$((ConvertTo-SystemV7CanonicalJson -Value $blockMap).TrimEnd())
"@
        Write-SystemV7NarrativeAtomicText -Path (Join-Path $stageDir 'continuity-out-request.md') -Text $request|Out-Null
        $state=[ordered]@{schema='K3_ACT_STATE_V1';act_id=$ActId;run_id=$RunId;status='AWAITING_CONTINUITY_OUT';prefix_sha256=[string]$packet.prefix_sha256;model_id=[string]$packet.model_id;model_revision=[string]$packet.model_revision;submission_sha256=(Get-FileHash -LiteralPath $SubmissionPath -Algorithm SHA256).Hash;blocks_sha256=(Get-FileHash -LiteralPath (Join-Path $stageDir 'blocks.json') -Algorithm SHA256).Hash}
        Write-SystemV7NarrativeAtomicText -Path (Join-Path $stageDir 'state.json') -Text (ConvertTo-SystemV7CanonicalJson -Value $state)|Out-Null
        [IO.Directory]::Move($stageDir,$actDir);$actCreated=$true
        $liveBinding=Get-SystemV7ActProseBindingState -ActId $ActId -BlocksPath (Join-Path $actDir 'blocks.json') -ProsePath (Join-Path $actDir 'prose.md');if(-not $liveBinding.Valid){throw "K3_IMPORT_POSTVALIDATION_FAILED: $($liveBinding.Errors -join '; ')"}
        $liveState=Get-Content -LiteralPath (Join-Path $actDir 'state.json') -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String;if([string]$liveState.status -cne 'AWAITING_CONTINUITY_OUT' -or [string]$liveState.blocks_sha256 -cne (Get-FileHash -LiteralPath (Join-Path $actDir 'blocks.json') -Algorithm SHA256).Hash){throw 'K3_IMPORT_STATE_POSTVALIDATION_FAILED'}
        [pscustomobject]@{Status='AWAITING_CONTINUITY_OUT';ActId=$ActId;RunId=$RunId;BlockCount=$blockRecords.Count;BlockMapPath=(Join-Path $actDir 'blocks.json');ContinuationPromptPath=(Join-Path $actDir 'continuity-out-request.md')}
    }catch{if($actCreated -and (Test-Path -LiteralPath $actDir -PathType Container)){$null=Assert-SystemV7TreeNoReparse -RootPath $actDir -ContainmentRoot $project;[IO.Directory]::Delete($actDir,$true)};if(Test-Path -LiteralPath $stageDir -PathType Container){[IO.Directory]::Delete($stageDir,$true)};throw}
    return
}

if(-not(Test-Path -LiteralPath $actDir -PathType Container)){throw 'ACT_PROSE_PHASE_NOT_IMPORTED'}
$statePath=Join-Path $actDir 'state.json';$stateBefore=[IO.File]::ReadAllBytes($statePath);$statePathSha=(Get-Sha256HexFromBytes -Bytes $stateBefore);$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if([string]$state.status -cne 'AWAITING_CONTINUITY_OUT' -or [string]$state.run_id -cne $RunId){throw 'ACT_STATE_NOT_AWAITING_OUT'}
if(-not(Test-Path -LiteralPath $ContinuityOutPath -PathType Leaf)){throw 'CONTINUITY_OUT_SUBMISSION_MISSING'}
try{$out=Get-Content -LiteralPath $ContinuityOutPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{throw 'CONTINUITY_OUT_INVALID_JSON'}
$outFields=@('schema','act_id','records','nq_paid','nq_opened','nq_reframed','open_nq_ids_out','nr_revealed','nr_consequences','nr_setup_only','character_and_world_state','bridge_realized','bridge_block_refs','opening_move_type','opening_block_refs','closing_move_type','closing_block_refs','uncertainties_preserved')
if(@(Compare-Object -ReferenceObject $outFields -DifferenceObject @($out.PSObject.Properties.Name)).Count -gt 0 -or @($out.PSObject.Properties.Name).Count -ne $outFields.Count){throw 'CONTINUITY_OUT_FIELDS_INVALID'}
if([string]$out.schema -cne 'CONTINUITY_OUT_V1' -or [string]$out.act_id -cne $ActId){throw 'CONTINUITY_OUT_SCHEMA_OR_ACT_INVALID'}
if([string]$out.opening_move_type -notin @('SCENA','ANOMALIA','DOKUMENT','KONSEKWENCJA','KONTRAST','KONTAKT_Z_WIDZEM','POWRÓT_DO_MOTYWU')){throw 'OPENING_MOVE_TYPE_INVALID'}
if([string]$out.closing_move_type -notin @('DECYZJA','REVEAL','PAYOFF','KONSEKWENCJA','GRANICA_WIEDZY','NOWA_PĘTLA','POWRÓT_DO_MOTYWU')){throw 'CLOSING_MOVE_TYPE_INVALID'}
$blocks=Get-Content -LiteralPath (Join-Path $actDir 'blocks.json') -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$liveProseBinding=Get-SystemV7ActProseBindingState -ActId $ActId -BlocksPath (Join-Path $actDir 'blocks.json') -ProsePath (Join-Path $actDir 'prose.md');if(-not $liveProseBinding.Valid){throw "K3_LIVE_PROSE_BINDING_INVALID: $($liveProseBinding.Errors -join '; ')"}
$continuityArchitecture=Get-SystemV7NarrativeArchitecture -Path (Join-Path $project '02-architektura-odcinka.md');$outStructure=Get-SystemV7ContinuityOutStructuralState -ActId $ActId -ContinuityOut $out -BlocksData $blocks -ArchitectureData $continuityArchitecture.Data;if(-not $outStructure.Valid){throw "CONTINUITY_OUT_STRUCTURAL_INVALID: $($outStructure.Errors -join '; ')"}
$blockIndex=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach($b in @($blocks.blocks)){$blockIndex.Add([string]$b.block_id,$b)}
$stateIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($record in @($out.records)){
    $fields=@('state_id','category','value','class','block_refs','related_ids','source_p_ids')
    if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($record.PSObject.Properties.Name)).Count -gt 0 -or @($record.PSObject.Properties.Name).Count -ne $fields.Count){throw 'CONTINUITY_OUT_RECORD_FIELDS_INVALID'}
    if([string]$record.state_id -notmatch '^STATE-\d{3}$' -or -not $stateIds.Add([string]$record.state_id)){throw 'CONTINUITY_STATE_ID_INVALID_OR_DUPLICATE'}
    if([string]$record.category -notin @('FACT','INFERENCE','QUESTION','REVEAL','BRIDGE','WORLD_STATE','KNOWLEDGE_BOUNDARY') -or [string]$record.class -notin @('TEXT_ASSERTED','VIEWER_INFERENCE')){throw 'CONTINUITY_STATE_CLASS_INVALID'}
    if(@($record.block_refs).Count -eq 0){throw "CONTINUITY_BLOCK_REFS_EMPTY: $($record.state_id)"}
    $availableSources=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($ref in @($record.block_refs)){
        if(@($ref.PSObject.Properties.Name).Count -ne 2 -or 'block_id' -notin @($ref.PSObject.Properties.Name) -or 'block_sha256' -notin @($ref.PSObject.Properties.Name)){throw 'CONTINUITY_BLOCK_REF_FIELDS_INVALID'}
        $bid=[string]$ref.block_id;if(-not $blockIndex.ContainsKey($bid)){throw "CONTINUITY_BLOCK_ID_MISSING: $bid"}
        if([string]$blockIndex[$bid].block_sha256 -cne [string]$ref.block_sha256){throw "CONTINUITY_BLOCK_SHA_STALE: $bid"}
        foreach($p in @($blockIndex[$bid].source_p_ids)){$null=$availableSources.Add([string]$p)}
    }
    foreach($p in @($record.source_p_ids)){if(-not $availableSources.Contains([string]$p)){throw "CONTINUITY_SOURCE_NOT_IN_BLOCK_REFS: $($record.state_id)/$p"}}
    if([string]$record.category -in @('FACT','REVEAL') -and @($record.source_p_ids).Count -eq 0){throw "CONTINUITY_SOURCE_REQUIRED: $($record.state_id)"}
}
$outJson=ConvertTo-SystemV7CanonicalJson -Value $out
$beatSheetShaForSession='NOT_APPLICABLE';$beatStatePathForSession=Join-Path $project "_work\k3\beats\$ActId\state.json";if(Test-Path -LiteralPath $beatStatePathForSession -PathType Leaf){$beatStateForSession=Get-Content -LiteralPath $beatStatePathForSession -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String;$beatSheetShaForSession=[string]$beatStateForSession.beat_sheet_sha256}
$sessionOutput=[ordered]@{schema='K3_GENERATE_ACT_SESSION_OUTPUT_V1';act_id=$ActId;run_id=$RunId;beat_sheet_sha256=$beatSheetShaForSession;prose_submission_sha256=[string]$state.submission_sha256;blocks_file_sha256=(Get-FileHash -LiteralPath (Join-Path $actDir 'blocks.json') -Algorithm SHA256).Hash;continuity_out_submission_sha256=(Get-FileHash -LiteralPath $ContinuityOutPath -Algorithm SHA256).Hash;continuity_out_content_sha256=(Get-SystemV7NarrativeSha256Text -Text $outJson)}
  $outTarget=Join-Path $actDir 'out.json';$sessionTarget=Join-Path $project "_work\narrative-runs\$RunId\output.json";$receiptPath=Join-Path $project "_work\narrative-runs\$RunId\run-receipt.json"
$allReceipts=@(Get-ChildItem -LiteralPath (Join-Path $project '_work\narrative-runs') -Filter 'run-receipt.json' -File -Recurse -ErrorAction SilentlyContinue)
foreach($f in $allReceipts){try{$prior=Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String}catch{continue};if([string]$prior.task_id -ceq $TaskId){throw "TASK_ID_ALREADY_USED: $TaskId"}}
$receiptCreated=$false;$sessionCreated=$false;$outCreated=$false
try{
    if((Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash -cne $statePathSha){throw 'ACT_STATE_COMPARE_AND_SWAP_CONFLICT'}
    $lockedState=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if([string]$lockedState.status -cne 'AWAITING_CONTINUITY_OUT' -or [string]$lockedState.run_id -cne $RunId){throw 'ACT_STATE_NOT_AWAITING_OUT'}
    foreach($target in @($receiptPath,$sessionTarget,$outTarget)){if(Test-Path -LiteralPath $target){throw "GENERATE_ACT_OUTPUT_ALREADY_EXISTS: $target"}}
    $allReceiptsLocked=@(Get-ChildItem -LiteralPath (Join-Path $project '_work\narrative-runs') -Filter 'run-receipt.json' -File -Recurse -ErrorAction SilentlyContinue)
    foreach($receiptFile in $allReceiptsLocked){try{$prior=Get-Content -LiteralPath $receiptFile.FullName -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String}catch{continue};if([string]$prior.task_id -ceq $TaskId){throw "TASK_ID_ALREADY_USED: $TaskId"}}
    Write-SystemV7NarrativeAtomicText -Path $outTarget -Text $outJson|Out-Null
    $outCreated=$true
    Write-SystemV7NarrativeAtomicText -Path $sessionTarget -Text (ConvertTo-SystemV7CanonicalJson -Value $sessionOutput)|Out-Null
    $sessionCreated=$true
    $receipt=New-SystemV7NarrativeRunReceiptRecord -ProjectPath $project -ProjectOriginSha256 $origin.Sha256 -ManifestPath $manifestPath -OutputPath $sessionTarget -TaskId $TaskId -ModelId ([string]$packet.model_id) -ModelRevision ([string]$packet.model_revision) -ModelSettingsSha256 ([string]$packet.model_settings_sha256) -PromptRevision 'K3_ACT_V2' -ActorRole 'CLAUDE' -StartedAt $StartedAt -Note "Two-turn fresh context for $ActId"
    Write-SystemV7NarrativeCreateNewJson -Path $receiptPath -Value $receipt|Out-Null
    $receiptCreated=$true
    $newState=[ordered]@{schema='K3_ACT_STATE_V1';act_id=$ActId;run_id=$RunId;status='AWAITING_ATTEST';prefix_sha256=[string]$packet.prefix_sha256;model_id=[string]$packet.model_id;model_revision=[string]$packet.model_revision;submission_sha256=[string]$state.submission_sha256;blocks_sha256=(Get-FileHash -LiteralPath (Join-Path $actDir 'blocks.json') -Algorithm SHA256).Hash;continuity_out_sha256=(Get-FileHash -LiteralPath $outTarget -Algorithm SHA256).Hash;generate_run_receipt_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $receiptPath);generate_run_receipt_sha256=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash}
    Write-SystemV7NarrativeAtomicText -Path $statePath -Text (ConvertTo-SystemV7CanonicalJson -Value $newState)|Out-Null
    $liveState=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String;$liveReceipt=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $receiptPath -ExpectedRunType 'GENERATE_ACT' -RequireLiveInputs;if([string]$liveState.status -cne 'AWAITING_ATTEST' -or -not $liveReceipt.Valid -or [string]$liveState.generate_run_receipt_sha256 -cne [string]$liveReceipt.Sha256){throw "GENERATE_ACT_POSTVALIDATION_FAILED: $($liveReceipt.Errors -join '; ')"}
}catch{
    if((Test-Path -LiteralPath $statePath -PathType Leaf) -and (Get-FileHash -LiteralPath $statePath -Algorithm SHA256).Hash -cne $statePathSha){[IO.File]::WriteAllBytes($statePath,$stateBefore)}
    if($receiptCreated -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){[IO.File]::Delete($receiptPath)}
    if($sessionCreated -and (Test-Path -LiteralPath $sessionTarget -PathType Leaf)){[IO.File]::Delete($sessionTarget)}
    if($outCreated -and (Test-Path -LiteralPath $outTarget -PathType Leaf)){[IO.File]::Delete($outTarget)}
    throw
}
[pscustomobject]@{Status='AWAITING_ATTEST';ActId=$ActId;RunId=$RunId;ContinuityOutPath=$outTarget;GenerateRunReceiptPath=$receiptPath;NextAction='Build a fresh CONTINUITY_ATTEST bundle.'}
}finally{Exit-SystemV7ProjectMetaLock -LockStream $mutationLock}
