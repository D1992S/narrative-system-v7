[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
    [Parameter(Mandatory)][string]$RunId
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
$trackedInputs=@{}
$trackInput={param([string]$Path,[string]$Code)
    $full=[IO.Path]::GetFullPath($Path);if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "CONTINUITY_INPUT_MISSING: $Code"}
    $sha=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    if($trackedInputs.ContainsKey($full) -and [string]$trackedInputs[$full] -cne $sha){throw "CONTINUITY_INPUT_CHANGED_DURING_READ: $Code"}
    $trackedInputs[$full]=$sha;return $sha
}
try{
$metaPath=Join-Path $project 'meta.md'
$null=&$trackInput $metaPath 'META';$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$null=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$receiptPath=Join-Path $project "_work\narrative-runs\$RunId\run-receipt.json"
$null=&$trackInput $receiptPath 'ATTEST_RUN_RECEIPT'
$proof=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $receiptPath -ExpectedRunType 'CONTINUITY_ATTEST' -RequireLiveInputs
if(-not $proof.Valid){throw "CONTINUITY_ATTEST_RECEIPT_INVALID: $($proof.Errors -join '; ')"}
$outputPath=Join-Path $project ([string]$proof.Data.output_relative)
$null=&$trackInput $outputPath 'ATTEST_OUTPUT'
try{$result=Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{throw 'CONTINUITY_ATTEST_RESULT_INVALID_JSON'}
$fields=@('schema','act_id','verdict','record_results','missing_state_change','question_arithmetic_verdict','reason')
if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($result.PSObject.Properties.Name)).Count -gt 0 -or @($result.PSObject.Properties.Name).Count -ne $fields.Count){throw 'CONTINUITY_ATTEST_RESULT_FIELDS_INVALID'}
if([string]$result.schema -cne 'CONTINUITY_ATTEST_RESULT_V1' -or [string]$result.act_id -cne $ActId -or [string]$result.verdict -cne 'PASS' -or $result.missing_state_change -cne $false -or [string]$result.question_arithmetic_verdict -cne 'PASS'){throw 'CONTINUITY_ATTEST_NOT_PASS'}
if(-not(Test-SystemV7ConcreteText -Value ([string]$result.reason))){throw 'CONTINUITY_ATTEST_REASON_NOT_CONCRETE'}
$actDir=Join-Path $project "_work\k3\acts\$ActId";$statePath=Join-Path $actDir 'state.json'
$stateSha=&$trackInput $statePath 'ACT_STATE';$stateBeforeBytes=[IO.File]::ReadAllBytes($statePath);$metaSha=[string]$trackedInputs[[IO.Path]::GetFullPath($metaPath)];$metaBeforeBytes=[IO.File]::ReadAllBytes($metaPath)
$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if([string]$state.status -cne 'AWAITING_ATTEST'){throw "ACT_STATE_NOT_AWAITING_ATTEST: $($state.status)"}
$generateProofPath=Join-Path $project ([string]$state.generate_run_receipt_relative)
$null=&$trackInput $generateProofPath 'GENERATE_RUN_RECEIPT'
$generateProof=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $generateProofPath -ExpectedRunType 'GENERATE_ACT' -RequireLiveInputs
if(-not $generateProof.Valid){throw 'GENERATE_ACT_PROOF_STALE'}
if([string]$generateProof.Sha256 -cne [string]$state.generate_run_receipt_sha256 -or [string]$generateProof.Data.run_id -cne [string]$state.run_id){throw 'GENERATE_ACT_PROOF_BINDING_MISMATCH'}
if([string]$generateProof.Data.task_id -ceq [string]$proof.Data.task_id){throw 'ATTEST_AND_GENERATE_TASK_ID_COLLISION'}
$blocksPath=Join-Path $actDir 'blocks.json';$outPath=Join-Path $actDir 'out.json';$inPath=Join-Path $project "_work\k3\continuity\$ActId.in.json"
$null=&$trackInput $blocksPath 'BLOCKS';$null=&$trackInput $outPath 'CONTINUITY_OUT';$null=&$trackInput $inPath 'CONTINUITY_IN'
$blocks=Get-Content -LiteralPath $blocksPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$out=Get-Content -LiteralPath $outPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$continuityIn=Get-Content -LiteralPath $inPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$attestManifestPath=Join-Path $project ([string]$proof.Data.input_manifest_relative);$null=&$trackInput $attestManifestPath 'ATTEST_INPUT_MANIFEST'
$attestBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $attestManifestPath
if(-not $attestBundle.Valid){throw "CONTINUITY_ATTEST_BUNDLE_INVALID: $($attestBundle.Errors -join '; ')"}
$expectedAttestInputs=[ordered]@{ACT_PROSE_BLOCKS=$blocksPath;CONTINUITY_IN=$inPath;CONTINUITY_OUT=$outPath}
foreach($role in $expectedAttestInputs.Keys){$entry=@($attestBundle.Data.entries|Where-Object{[string]$_.content_role -ceq $role});$expectedRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $expectedAttestInputs[$role];if($entry.Count -ne 1 -or [string]$entry[0].source_relative -cne $expectedRelative -or [string]$entry[0].sha256 -cne (Get-FileHash -LiteralPath $expectedAttestInputs[$role] -Algorithm SHA256).Hash){throw "CONTINUITY_ATTEST_INPUT_MISMATCH: $role"}}
$schemaEntry=@($attestBundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'CONTINUITY_SCHEMA'});$schemaSource=Join-Path (Split-Path -Parent $PSScriptRoot) '_SYSTEM\NARRATIVE\CONTINUITY-SCHEMA.md'
$null=&$trackInput $schemaSource 'CONTINUITY_SCHEMA'
if($schemaEntry.Count -ne 1 -or [string]$schemaEntry[0].sha256 -cne (Get-FileHash -LiteralPath $schemaSource -Algorithm SHA256).Hash){throw 'CONTINUITY_ATTEST_SCHEMA_MISMATCH'}
$stateIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($record in @($out.records)){$null=$stateIds.Add([string]$record.state_id)}
foreach($record in @($out.character_and_world_state)){$null=$stateIds.Add([string]$record.world_state_id)}
foreach($record in @($out.uncertainties_preserved)){$null=$stateIds.Add([string]$record.uncertainty_id)}
foreach($special in @('BRIDGE','OPENING_MOVE','CLOSING_MOVE')){$null=$stateIds.Add($special)}
$resultIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($recordResult in @($result.record_results)){
    $rf=@('state_id','verdict','reason')
    if(@(Compare-Object -ReferenceObject $rf -DifferenceObject @($recordResult.PSObject.Properties.Name)).Count -gt 0 -or @($recordResult.PSObject.Properties.Name).Count -ne $rf.Count){throw 'ATTEST_RECORD_RESULT_FIELDS_INVALID'}
    $sid=[string]$recordResult.state_id
    if(-not $stateIds.Contains($sid) -or -not $resultIds.Add($sid)){throw "ATTEST_RECORD_ID_INVALID: $sid"}
    if([string]$recordResult.verdict -cne 'PASS'){throw "ATTEST_RECORD_NOT_PASS: $sid/$($recordResult.verdict)"}
    if(-not(Test-SystemV7ConcreteText -Value ([string]$recordResult.reason))){throw "ATTEST_RECORD_REASON_NOT_CONCRETE: $sid"}
}
if($resultIds.Count -ne $stateIds.Count){throw 'ATTEST_RECORD_COVERAGE_INCOMPLETE'}

$architecturePath=Join-Path $project '02-architektura-odcinka.md';$null=&$trackInput $architecturePath 'ARCHITECTURE'
$architecture=Get-SystemV7NarrativeArchitecture -Path $architecturePath
if([string]$architecture.Data.schema -cne 'STORY_ENGINE_V2'){throw 'CONTINUITY_ARCHITECTURE_SCHEMA_INVALID'}
$outStructure=Get-SystemV7ContinuityOutStructuralState -ActId $ActId -ContinuityOut $out -BlocksData $blocks -ArchitectureData $architecture.Data;if(-not $outStructure.Valid){throw "CONTINUITY_OUT_STRUCTURAL_INVALID: $($outStructure.Errors -join '; ')"}
$sequence=@((Get-SystemV7NarrativeMetaField -Text $meta -Name 'NARRATIVE_ACT_SEQUENCE') -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_});$index=[Array]::IndexOf([string[]]$sequence,$ActId);if($index -lt 0){throw 'ACT_SEQUENCE_MISSING'}
$outputsByAct=@{};$inputsByAct=@{}
for($replayIndex=0;$replayIndex -le $index;$replayIndex++){
    $replayActId=$sequence[$replayIndex]
    $replayOutPath=if($replayActId -ceq $ActId){$outPath}else{Join-Path $project "_work\k3\acts\$replayActId\out.json"}
    $replayInPath=if($replayActId -ceq $ActId){$inPath}else{Join-Path $project "_work\k3\continuity\$replayActId.in.json"}
    if($replayActId -cne $ActId){$priorAttestPath=Join-Path $project "_work\k3\continuity\$replayActId.attest.json";$null=&$trackInput $priorAttestPath "PRIOR_ATTEST/$replayActId";$priorAttest=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $replayActId;if(-not $priorAttest.Valid){throw "PRIOR_CONTINUITY_INVALID: $replayActId/$($priorAttest.Errors -join ',')"}}
    foreach($pair in @(@($replayOutPath,'OUT'),@($replayInPath,'IN'))){if(-not(Test-Path -LiteralPath $pair[0] -PathType Leaf)){throw "CONTINUITY_REPLAY_$($pair[1])_MISSING: $replayActId"}}
    $null=&$trackInput $replayOutPath "REPLAY_OUT/$replayActId";$null=&$trackInput $replayInPath "REPLAY_IN/$replayActId"
    $outputsByAct[$replayActId]=Get-Content -LiteralPath $replayOutPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
    $inputsByAct[$replayActId]=Get-Content -LiteralPath $replayInPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
}
$replay=Get-SystemV7OrderedContinuityReplayState -ArchitectureData $architecture.Data -ThroughActId $ActId -OutputsByAct $outputsByAct -ContinuityInputsByAct $inputsByAct -RequireOutputs -RequireContinuityInputs
if(-not $replay.Valid){throw "CONTINUITY_ORDERED_REPLAY_FAIL: $($replay.Errors -join '; ')"}
$declared=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($id in @($replay.OpenNqIds)){$null=$declared.Add([string]$id)}
$preparedNr=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($id in @($replay.PreparedNrIds)){$null=$preparedNr.Add([string]$id)}

$nextAct=if($index+1 -lt $sequence.Count){$sequence[$index+1]}else{'COMPLETE'}
$packetPath=Join-Path $project "_work\k3\packets\$ActId.act-packet.json";$null=&$trackInput $packetPath 'ACT_PACKET'
$packet=Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
$prosePath=Join-Path $actDir 'prose.md';$proseSha=&$trackInput $prosePath 'ACT_PROSE'
$proseBinding=Get-SystemV7ActProseBindingState -ActId $ActId -BlocksPath $blocksPath -ProsePath $prosePath;if(-not $proseBinding.Valid){throw "ACT_PROSE_BINDING_INVALID: $($proseBinding.Errors -join '; ')"}
$traceBeat=$null;if([string]$packet.complexity_flag -ceq 'COMPLEX'){$traceBeatPath=Join-Path $project "_work\k3\beats\$ActId\beat-sheet.json";$null=&$trackInput $traceBeatPath 'BEAT_SHEET';$traceBeat=Get-Content -LiteralPath $traceBeatPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64};$traceState=Get-SystemV7ActSubmissionTraceState -Packet $packet -Blocks @($proseBinding.Blocks.blocks) -BeatSheet $traceBeat;if(-not $traceState.Valid){throw "ACT_TRACE_BINDING_INVALID: $($traceState.Errors -join '; ')"}
$expectedNext=Get-SystemV7ExpectedNextContinuityIn -ActId $ActId -NextActId $nextAct -ContinuityIn $continuityIn -ContinuityOut $out -ActPacket $packet -ProseSha256 $proseSha -OpenNqIds @($replay.OpenNqIds) -PreparedNrIds @($replay.PreparedNrIds)
$nextIn=$expectedNext.Value;$openingHistory=@($nextIn.opening_move_history);$closingHistory=@($nextIn.closing_move_history)
$attestCore=[ordered]@{schema='CONTINUITY_ATTEST_RECORD_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;act_id=$ActId;verdict='PASS';prefix_sha256=[string]$state.prefix_sha256;model_id=[string]$state.model_id;model_revision=[string]$state.model_revision;blocks_sha256=(Get-FileHash -LiteralPath $blocksPath -Algorithm SHA256).Hash;continuity_in_sha256=(Get-FileHash -LiteralPath $inPath -Algorithm SHA256).Hash;continuity_out_sha256=(Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash;attest_output_sha256=(Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash;run_receipt_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $receiptPath);run_receipt_sha256=$proof.Sha256;next_continuity_in=$nextIn}
$attestPath=Join-Path $project "_work\k3\continuity\$ActId.attest.json"
if(Test-Path -LiteralPath $attestPath){throw 'CONTINUITY_ATTEST_ALREADY_ACCEPTED'}
$attestCreated=$false;$stateWritten=$false;$metaWritten=$false
try{
    foreach($trackedPath in @($trackedInputs.Keys)){if(-not(Test-Path -LiteralPath $trackedPath -PathType Leaf) -or (Get-FileHash -LiteralPath $trackedPath -Algorithm SHA256).Hash -cne [string]$trackedInputs[$trackedPath]){throw "CONTINUITY_ACCEPT_INPUT_CHANGED: $trackedPath"}}
    $lockedProof=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $receiptPath -ExpectedRunType 'CONTINUITY_ATTEST' -RequireLiveInputs;if(-not $lockedProof.Valid -or [string]$lockedProof.Sha256 -cne [string]$proof.Sha256){throw 'CONTINUITY_ATTEST_PROOF_CHANGED'}
    $lockedGenerate=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $generateProofPath -ExpectedRunType 'GENERATE_ACT' -RequireLiveInputs;if(-not $lockedGenerate.Valid -or [string]$lockedGenerate.Sha256 -cne [string]$generateProof.Sha256){throw 'GENERATE_ACT_PROOF_CHANGED'}
    $lockedState=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if([string]$lockedState.status -cne 'AWAITING_ATTEST' -or [string]$lockedState.run_id -cne [string]$state.run_id){throw 'ACT_STATE_CHANGED_BEFORE_ATTEST_ACCEPT'}
    Write-SystemV7NarrativeCreateNewJson -Path $attestPath -Value $attestCore|Out-Null
    $attestCreated=$true
    $newState=[ordered]@{schema='K3_ACT_STATE_V1';act_id=$ActId;run_id=[string]$state.run_id;status='ATTESTED';prefix_sha256=[string]$state.prefix_sha256;model_id=[string]$state.model_id;model_revision=[string]$state.model_revision;submission_sha256=[string]$state.submission_sha256;blocks_sha256=[string]$state.blocks_sha256;continuity_out_sha256=[string]$state.continuity_out_sha256;generate_run_receipt_relative=[string]$state.generate_run_receipt_relative;generate_run_receipt_sha256=[string]$state.generate_run_receipt_sha256;attest_run_id=$RunId;attest_receipt_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $receiptPath);attest_receipt_sha256=$proof.Sha256;attest_record_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $attestPath);attest_record_sha256=(Get-FileHash -LiteralPath $attestPath -Algorithm SHA256).Hash}
    Write-SystemV7NarrativeAtomicText -Path $statePath -Text (ConvertTo-SystemV7CanonicalJson -Value $newState)|Out-Null
    $stateWritten=$true
    $updated=Set-SystemV7NarrativeMetaField -Text $meta -Name 'K3_LAST_ATTESTED_ACT' -Value $ActId
    $continuityStatus=if($nextAct -ceq 'COMPLETE'){'COMPLETE'}else{'IN_PROGRESS'};$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'CONTINUITY_STATUS' -Value $continuityStatus
    Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text (ConvertTo-SystemV7LfText -Text $updated) -ExpectedCurrentSha256 $metaSha -HeldLockStream $lock|Out-Null
    $metaWritten=$true
    $accepted=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $ActId
    if(-not $accepted.Valid){throw "CONTINUITY_POSTVALIDATION_FAIL: $($accepted.Errors -join '; ')"}
}catch{
    if($metaWritten){[IO.File]::WriteAllBytes($metaPath,$metaBeforeBytes)}
    if($stateWritten){[IO.File]::WriteAllBytes($statePath,$stateBeforeBytes)}
    if($attestCreated -and (Test-Path -LiteralPath $attestPath -PathType Leaf)){[IO.File]::Delete($attestPath)}
    throw
}
[pscustomobject]@{Status='CONTINUITY_ATTEST_ACCEPTED';ActId=$ActId;NextAct=$nextAct;AttestPath=$attestPath;AttestSha256=(Get-FileHash -LiteralPath $attestPath -Algorithm SHA256).Hash;OpeningRepeatAlert=($openingHistory.Count -ge 2 -and $openingHistory[-1] -ceq $openingHistory[-2]);ClosingRepeatAlert=($closingHistory.Count -ge 2 -and $closingHistory[-1] -ceq $closingHistory[-2])}
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
