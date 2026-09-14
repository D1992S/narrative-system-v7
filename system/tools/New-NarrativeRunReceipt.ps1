[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$ModelId,
    [Parameter(Mandatory)][string]$ModelRevision,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ModelSettingsSha256,
    [Parameter(Mandatory)][string]$PromptRevision,
    [Parameter(Mandatory)][ValidateSet('CLAUDE','CHATGPT_CODEX')][string]$ActorRole,
    [Parameter(Mandatory)][DateTimeOffset]$StartedAt,
    [string]$TelemetryPath='',
    [string]$Note='BRAK'
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$metaPath=Join-Path $project 'meta.md';$manifestPath=Join-Path $project "_work\narrative-runs\$RunId\input-manifest.json";$outputFull=[IO.Path]::GetFullPath($OutputPath);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $outputFull
foreach($path in @($metaPath,$manifestPath,$outputFull)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "RUN_RECEIPT_INPUT_MISSING: $path"}}
$inputSnapshot=[ordered]@{meta=(Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash;manifest=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash;output=(Get-FileHash -LiteralPath $outputFull -Algorithm SHA256).Hash}
$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$bundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $manifestPath
if(-not $bundle.Valid){throw "INPUT_BUNDLE_INVALID: $($bundle.Errors -join '; ')"}
$runType=[string]$bundle.Data.run_type
$expectedActor=if($runType -ceq 'GENERATE_ACT'){'CLAUDE'}else{'CHATGPT_CODEX'}
if($ActorRole -cne $expectedActor){throw "RUN_ROLE_INVALID: $runType requires $expectedActor"}
$expectedPromptRevision=[string]$script:SystemV7NarrativePromptRevisions[$runType]
if([string]::IsNullOrWhiteSpace($expectedPromptRevision) -or $PromptRevision -cne $expectedPromptRevision){throw "PROMPT_REVISION_INVALID: $runType requires $expectedPromptRevision"}
if($runType -ceq 'GENERATE_ACT'){
    if($ModelId -cne (Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_ID') -or $ModelRevision -cne (Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_REVISION') -or $ModelSettingsSha256.ToUpperInvariant() -cne (Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_SETTINGS_SHA256')){throw 'K3_MODEL_STALE'}
}
$OutputPath=$outputFull;$receiptPath=Join-Path $project "_work\narrative-runs\$RunId\run-receipt.json"
$stubPath=$null;$packetRecordPath=$null;$updatedStub=$null;$updatedRecord=$null;$stubBefore=$null;$recordBefore=$null;$beatStatePath=$null;$beatStateBefore=$null;$updatedBeatState=$null
if($runType -ceq 'CONSTRAINT_ATOMICITY_PREFLIGHT'){
    $output=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
    $requiredOutputFields=@('VERDICT','UNBUNDLED_CONSTRAINT_COUNT','MISSING_ACTIONS','BUNDLED_ACTIONS','CONFLICTS','REASON')
    foreach($field in $requiredOutputFields){if(@([regex]::Matches($output,"(?m)^${field}:\s*(.*?)\s*$")).Count -ne 1){throw "CONSTRAINT_PREFLIGHT_FIELD_COUNT_INVALID: $field"}}
    if($output -notmatch '(?m)^VERDICT:\s*PASS\s*$' -or $output -notmatch '(?m)^MISSING_ACTIONS:\s*BRAK\s*$' -or $output -notmatch '(?m)^BUNDLED_ACTIONS:\s*BRAK\s*$' -or $output -notmatch '(?m)^CONFLICTS:\s*BRAK\s*$'){throw 'CONSTRAINT_PREFLIGHT_NOT_PASS'}
    $packetEntry=@($bundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PACKET'});$ledgerEntry=@($bundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'CONSTRAINT_LEDGER'})
    if($packetEntry.Count -ne 1 -or $ledgerEntry.Count -ne 1){throw 'PREFLIGHT_INPUT_PROFILE_INVALID'}
    $packetData=Get-Content -LiteralPath (Join-Path $project ([string]$packetEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
    $ledgerData=Get-Content -LiteralPath (Join-Path $project ([string]$ledgerEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
    $atomicity=Get-SystemV7ConstraintAtomicityState -Packet $packetData -Ledger $ledgerData
    if(-not $atomicity.Valid){throw "CONSTRAINT_PREFLIGHT_DETERMINISTIC_FAIL: $($atomicity.Errors -join '; ')"}
    $countMatch=[regex]::Match($output,'(?m)^UNBUNDLED_CONSTRAINT_COUNT:\s*(\d+)\s*$');if(-not $countMatch.Success -or [int]$countMatch.Groups[1].Value -ne [int]$atomicity.UnbundledConstraintCount){throw 'CONSTRAINT_PREFLIGHT_COUNT_MISMATCH'}
    $reason=[regex]::Match($output,'(?m)^REASON:\s*(.*?)\s*$').Groups[1].Value;if(-not(Test-SystemV7ConcreteText $reason)){throw 'CONSTRAINT_PREFLIGHT_REASON_NOT_CONCRETE'}
    $actId=[string]$packetData.act_id;$packetRecordPath=Join-Path $project "_work\k3\packets\$actId.packet.json";$stubPath=Join-Path $project "_work\k3\packets\$actId.constraint-preflight.json"
    foreach($path in @($packetRecordPath,$stubPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "PREFLIGHT_STATE_MISSING: $path"}}
    $stubBefore=[IO.File]::ReadAllBytes($stubPath);$recordBefore=[IO.File]::ReadAllBytes($packetRecordPath)
    $packetRecord=Get-Content -LiteralPath $packetRecordPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String;$stub=Get-Content -LiteralPath $stubPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if([string]$packetRecord.status -cne 'PRECHECK_PENDING' -or [string]$stub.status -cne 'PENDING' -or [string]$stub.packet_sha256 -cne [string]$packetRecord.packet_sha256 -or [string]$stub.constraint_ledger_sha256 -cne (Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $ledgerData))){throw 'PREFLIGHT_STATE_STALE'}
    $updatedStub=[ordered]@{schema='CONSTRAINT_ATOMICITY_PREFLIGHT_V1';act_id=$actId;packet_sha256=[string]$stub.packet_sha256;constraint_ledger_sha256=[string]$stub.constraint_ledger_sha256;status='PASS';run_receipt_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $receiptPath);run_receipt_sha256='__RECEIPT_SHA_AFTER_WRITE__'}
    $updatedRecord=[ordered]@{schema=$packetRecord.schema;act_id=$packetRecord.act_id;prefix_sha256=$packetRecord.prefix_sha256;packet_sha256=$packetRecord.packet_sha256;act_projection_sha256=$packetRecord.act_projection_sha256;evidence_selection_sha256=$packetRecord.evidence_selection_sha256;narrative_action_registry_sha256=$packetRecord.narrative_action_registry_sha256;continuity_in_sha256=$packetRecord.continuity_in_sha256;model_id=$packetRecord.model_id;model_revision=$packetRecord.model_revision;model_settings_sha256=$packetRecord.model_settings_sha256;status='READY'}
}elseif($runType -ceq 'BEAT_PREFLIGHT'){
    $output=Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8;$requiredOutputFields=@('VERDICT','ACT_ID','SCHEMA_CHECK','IDENTIFIER_CHECK','STATE_TRANSITION_CHECK','NO_ADDED_SOURCE_OR_REVEAL','DISCREPANCIES','REASON')
    foreach($field in $requiredOutputFields){if(@([regex]::Matches($output,"(?m)^${field}:\s*(.*?)\s*$")).Count -ne 1){throw "BEAT_PREFLIGHT_FIELD_COUNT_INVALID: $field"}}
    foreach($field in @('VERDICT','SCHEMA_CHECK','IDENTIFIER_CHECK','STATE_TRANSITION_CHECK','NO_ADDED_SOURCE_OR_REVEAL')){if($output -notmatch "(?m)^${field}:\s*PASS\s*$"){throw "BEAT_PREFLIGHT_NOT_PASS: $field"}}
    if($output -notmatch '(?m)^DISCREPANCIES:\s*BRAK\s*$'){throw 'BEAT_PREFLIGHT_HAS_DISCREPANCIES'}
    $packetEntry=@($bundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PACKET'});$beatEntry=@($bundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'BEAT_SHEET'})
    if($packetEntry.Count -ne 1 -or $beatEntry.Count -ne 1){throw 'BEAT_PREFLIGHT_INPUT_PROFILE_INVALID'}
    $packetData=Get-Content -LiteralPath (Join-Path $project ([string]$packetEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$beatData=Get-Content -LiteralPath (Join-Path $project ([string]$beatEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$actId=[string]$packetData.act_id
    if([string]$packetData.complexity_flag -cne 'COMPLEX' -or [string]$beatData.act_id -cne $actId -or $output -notmatch "(?m)^ACT_ID:\s*$actId\s*$"){throw 'BEAT_PREFLIGHT_ACT_MISMATCH'}
    $reason=[regex]::Match($output,'(?m)^REASON:\s*(.*?)\s*$').Groups[1].Value;if(-not(Test-SystemV7ConcreteText $reason)){throw 'BEAT_PREFLIGHT_REASON_NOT_CONCRETE'}
    $beatStatePath=Join-Path $project "_work\k3\beats\$actId\state.json";$liveBeatPath=Join-Path $project "_work\k3\beats\$actId\beat-sheet.json";foreach($path in @($beatStatePath,$liveBeatPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "BEAT_PREFLIGHT_STATE_MISSING: $path"}}
    $liveBeatSha=(Get-FileHash -LiteralPath $liveBeatPath -Algorithm SHA256).Hash;if($liveBeatSha -cne [string]$beatEntry[0].sha256){throw 'BEAT_PREFLIGHT_LIVE_SHEET_CHANGED'}
    $beatStateBefore=[IO.File]::ReadAllBytes($beatStatePath);$beatState=Get-Content -LiteralPath $beatStatePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if([string]$beatState.status -cne 'AWAITING_BEAT_PREFLIGHT' -or [string]$beatState.generate_run_id -cne [string]$beatData.generate_run_id){throw 'BEAT_PREFLIGHT_STATE_STALE'}
    $updatedBeatState=[ordered]@{schema='K3_BEAT_STATE_V1';act_id=$actId;generate_run_id=[string]$beatState.generate_run_id;status='BEAT_PREFLIGHT_PASS';beat_sheet_sha256=[string]$beatState.beat_sheet_sha256;prefix_sha256=[string]$beatState.prefix_sha256;model_id=[string]$beatState.model_id;model_revision=[string]$beatState.model_revision;preflight_run_id=$RunId;preflight_receipt_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $receiptPath);preflight_receipt_sha256='__RECEIPT_SHA_AFTER_WRITE__'}
}
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
$receiptCreated=$false;$stubWritten=$false;$recordWritten=$false;$beatStateWritten=$false
try{
    foreach($pair in @(@($metaPath,$inputSnapshot.meta,'META'),@($manifestPath,$inputSnapshot.manifest,'MANIFEST'),@($outputFull,$inputSnapshot.output,'OUTPUT'))){if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -cne [string]$pair[1]){throw "RUN_RECEIPT_INPUT_CHANGED: $($pair[2])"}}
    $lockedBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $manifestPath -RequireLiveSource;if(-not $lockedBundle.Valid -or [string]$lockedBundle.FileSha256 -cne [string]$bundle.FileSha256){throw "RUN_RECEIPT_BUNDLE_CHANGED: $($lockedBundle.Errors -join '; ')"}
    if($runType -ceq 'CONSTRAINT_ATOMICITY_PREFLIGHT'){$semantic=Get-SystemV7ConstraintPreflightOutputState -ProjectPath $project -OutputPath $outputFull -BundleData $lockedBundle.Data;if(-not $semantic.Valid){throw "CONSTRAINT_PREFLIGHT_OUTPUT_CHANGED_OR_INVALID: $($semantic.Errors -join '; ')"}}
    elseif($runType -ceq 'BEAT_PREFLIGHT'){$semantic=Get-SystemV7BeatPreflightOutputState -ProjectPath $project -OutputPath $outputFull -BundleData $lockedBundle.Data;if(-not $semantic.Valid){throw "BEAT_PREFLIGHT_OUTPUT_CHANGED_OR_INVALID: $($semantic.Errors -join '; ')"};if((Get-FileHash -LiteralPath $liveBeatPath -Algorithm SHA256).Hash -cne $liveBeatSha){throw 'BEAT_PREFLIGHT_LIVE_SHEET_CHANGED_DURING_RECEIPT'}}
    elseif($runType -ceq 'CONTINUITY_ATTEST'){$semantic=Get-SystemV7ContinuityAttestOutputState -ProjectPath $project -OutputPath $outputFull -BundleData $lockedBundle.Data;if(-not $semantic.Valid){throw "CONTINUITY_ATTEST_OUTPUT_CHANGED_OR_INVALID: $($semantic.Errors -join '; ')"}}
    if(Test-Path -LiteralPath $receiptPath){throw 'RUN_RECEIPT_ALREADY_EXISTS'}
    $allReceipts=@(Get-ChildItem -LiteralPath (Join-Path $project '_work\narrative-runs') -Filter 'run-receipt.json' -File -Recurse -ErrorAction SilentlyContinue)
    foreach($receiptFile in $allReceipts){try{$prior=Get-Content -LiteralPath $receiptFile.FullName -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String}catch{continue};if([string]$prior.task_id -ceq $TaskId){throw "TASK_ID_ALREADY_USED: $TaskId"}}
    if($stubPath){if([Convert]::ToBase64String([IO.File]::ReadAllBytes($stubPath)) -cne [Convert]::ToBase64String($stubBefore) -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($packetRecordPath)) -cne [Convert]::ToBase64String($recordBefore)){throw 'PREFLIGHT_STATE_COMPARE_AND_SWAP_CONFLICT'}}
    if($beatStatePath -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($beatStatePath)) -cne [Convert]::ToBase64String($beatStateBefore)){throw 'BEAT_PREFLIGHT_STATE_COMPARE_AND_SWAP_CONFLICT'}
    $record=New-SystemV7NarrativeRunReceiptRecord -ProjectPath $project -ProjectOriginSha256 $origin.Sha256 -ManifestPath $manifestPath -OutputPath $OutputPath -TaskId $TaskId -ModelId $ModelId -ModelRevision $ModelRevision -ModelSettingsSha256 $ModelSettingsSha256.ToUpperInvariant() -PromptRevision $PromptRevision -ActorRole $ActorRole -StartedAt $StartedAt -TelemetryPath $TelemetryPath -Note $Note
    Write-SystemV7NarrativeCreateNewJson -Path $receiptPath -Value $record|Out-Null
    $receiptCreated=$true
    $writtenState=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $receiptPath -ExpectedRunType $runType -RequireLiveInputs
    if(-not $writtenState.Valid){throw "RUN_RECEIPT_POSTVALIDATION_FAILED: $($writtenState.Errors -join '; ')"}
    $receiptSha=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    if($stubPath){
        $updatedStub.run_receipt_sha256=$receiptSha
        Write-SystemV7NarrativeAtomicText -Path $stubPath -Text (ConvertTo-SystemV7CanonicalJson -Value $updatedStub)|Out-Null
        $stubWritten=$true
        Write-SystemV7NarrativeAtomicText -Path $packetRecordPath -Text (ConvertTo-SystemV7CanonicalJson -Value $updatedRecord)|Out-Null
        $recordWritten=$true
    }
    if($beatStatePath){$updatedBeatState.preflight_receipt_sha256=$receiptSha;Write-SystemV7NarrativeAtomicText -Path $beatStatePath -Text (ConvertTo-SystemV7CanonicalJson -Value $updatedBeatState)|Out-Null;$beatStateWritten=$true}
}catch{
    if($beatStateWritten){[IO.File]::WriteAllBytes($beatStatePath,$beatStateBefore)}
    if($recordWritten){[IO.File]::WriteAllBytes($packetRecordPath,$recordBefore)}
    if($stubWritten){[IO.File]::WriteAllBytes($stubPath,$stubBefore)}
    if($receiptCreated -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){[IO.File]::Delete($receiptPath)}
    throw
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
[pscustomobject]@{ReceiptPath=$receiptPath;ReceiptSha256=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash;RunType=$runType;RunId=$RunId;TaskId=$TaskId}
