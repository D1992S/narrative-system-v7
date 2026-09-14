[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9._-]{7,80}$')][string]$RunId
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
$systemRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project -SystemRoot $systemRoot | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
$bundleCreated=$false;$runRoot=Join-Path $project "_work\narrative-runs\$RunId"
try{
$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $runRoot
if(Test-Path -LiteralPath $runRoot){throw "RUN_BUNDLE_ALREADY_EXISTS: $RunId"}
$meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8
$null=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K3'){throw 'START_K3_ACT_REQUIRES_STAGE_K3'}
$packetDir=Join-Path $project '_work\k3\packets'
$recordPath=Join-Path $packetDir "$ActId.packet.json"
$preflightPath=Join-Path $packetDir "$ActId.constraint-preflight.json"
foreach($p in @($recordPath,$preflightPath)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "K3_PACKET_COMPONENT_MISSING: $p"}}
$record=Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
$preflight=Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if([string]$record.status -cne 'READY' -or [string]$preflight.status -cne 'PASS'){throw 'CONSTRAINT_PREFLIGHT_REQUIRED'}
$proofPath=Join-Path $project ([string]$preflight.run_receipt_relative)
$proof=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $proofPath -ExpectedRunType 'CONSTRAINT_ATOMICITY_PREFLIGHT' -RequireLiveInputs
if(-not $proof.Valid -or $proof.Sha256 -cne [string]$preflight.run_receipt_sha256){throw "CONSTRAINT_PREFLIGHT_RECEIPT_INVALID: $($proof.Errors -join '; ')"}
$recordFields=@('schema','act_id','prefix_sha256','packet_sha256','act_projection_sha256','evidence_selection_sha256','narrative_action_registry_sha256','continuity_in_sha256','model_id','model_revision','model_settings_sha256','status');$preflightFields=@('schema','act_id','packet_sha256','constraint_ledger_sha256','status','run_receipt_relative','run_receipt_sha256')
if(@(Compare-Object -ReferenceObject $recordFields -DifferenceObject @($record.PSObject.Properties.Name)).Count -gt 0 -or @($record.PSObject.Properties.Name).Count -ne $recordFields.Count -or @(Compare-Object -ReferenceObject $preflightFields -DifferenceObject @($preflight.PSObject.Properties.Name)).Count -gt 0 -or @($preflight.PSObject.Properties.Name).Count -ne $preflightFields.Count){throw 'K3_PACKET_OR_PREFLIGHT_FIELDS_INVALID'}
$packetMarkdown=Join-Path $packetDir "$ActId.packet.md";$actPacketPath=Join-Path $packetDir "$ActId.act-packet.json";$actionRegistryPath=Join-Path $packetDir "$ActId.narrative-action-registry.json";$ledgerPath=Join-Path $packetDir "$ActId.constraint-ledger.json"
if([string]$record.act_id -cne $ActId -or [string]$preflight.act_id -cne $ActId -or [string]$preflight.packet_sha256 -cne [string]$record.packet_sha256 -or (Get-FileHash -LiteralPath $packetMarkdown -Algorithm SHA256).Hash -cne [string]$record.packet_sha256 -or (Get-FileHash -LiteralPath $actionRegistryPath -Algorithm SHA256).Hash -cne [string]$record.narrative_action_registry_sha256 -or (Get-FileHash -LiteralPath $ledgerPath -Algorithm SHA256).Hash -cne [string]$preflight.constraint_ledger_sha256){throw 'CONSTRAINT_PREFLIGHT_CURRENT_PACKET_BINDING_INVALID'}
$proofBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath (Join-Path $project ([string]$proof.Data.input_manifest_relative)) -RequireLiveSource;if(-not $proofBundle.Valid){throw 'CONSTRAINT_PREFLIGHT_BUNDLE_NOT_LIVE'};$proofPacket=@($proofBundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PACKET'});$proofLedger=@($proofBundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'CONSTRAINT_LEDGER'});if($proofPacket.Count -ne 1 -or $proofLedger.Count -ne 1 -or [string]$proofPacket[0].sha256 -cne (Get-FileHash -LiteralPath $actPacketPath -Algorithm SHA256).Hash -or [string]$proofLedger[0].sha256 -cne (Get-FileHash -LiteralPath $ledgerPath -Algorithm SHA256).Hash){throw 'CONSTRAINT_PREFLIGHT_BUNDLE_CURRENT_INPUT_MISMATCH'}
if([string]$record.prefix_sha256 -cne (Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_PREFIX_SHA256')){throw 'PREFIX_STALE'}
if([string]$record.model_id -cne (Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_ID') -or [string]$record.model_revision -cne (Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_REVISION')){throw 'MODEL_STALE'}
$prefixDir=Join-Path $project '_work\k3\prefix';$continuityDir=Join-Path $project '_work\k3\continuity'
$inputs=@{
    CORE=Join-Path $prefixDir 'K3_RULES_CORE.md';STORY_SPINE=Join-Path $prefixDir 'PROJECT_STORY_SPINE.json';VOICE_RULES=Join-Path $prefixDir 'VOICE_RULES.md';VOICE_EXEMPLARS=Join-Path $prefixDir 'VOICE_EXEMPLARS.md'
    CONTINUITY_IN=Join-Path $continuityDir "$ActId.in.json";EVIDENCE_SELECTION=Join-Path $packetDir "$ActId.evidence-selection.json";ACT_PACKET=$actPacketPath
    ACT_HARD_CONSTRAINTS=$ledgerPath;DO_NOT_REVEAL=Join-Path $packetDir "$ActId.do-not-reveal.json";WRITE_COMMAND=Join-Path $packetDir "$ActId.write-command.md"
}
$bundle=New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType GENERATE_ACT -RunId $RunId -Inputs $inputs
$bundleCreated=$true
$bundleState=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $bundle.Path -RequireLiveSource;if(-not $bundleState.Valid){throw "GENERATE_ACT_BUNDLE_POSTVALIDATION_FAILED: $($bundleState.Errors -join '; ')"}
$actPacket=Get-Content -LiteralPath (Join-Path $packetDir "$ActId.act-packet.json") -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32
$instruction=if([string]$actPacket.complexity_flag -ceq 'COMPLEX'){'Uruchom jeden nowy kontekst Claude wyłącznie z bundle. Pierwsza tura zwraca tylko K3_BEAT_SHEET_V1; zachowaj tę samą sesję do prozy po niezależnym PASS Beat Preflight.'}else{'Uruchom jeden nowy kontekst Claude wyłącznie z plikami bundle. Nie używaj rozmowy poprzedniego aktu.'}
[pscustomobject]@{Status='FRESH_CONTEXT_BUNDLE_READY';ActId=$ActId;RunId=$RunId;Complexity=[string]$actPacket.complexity_flag;InputManifestPath=$bundle.Path;InputManifestSha256=$bundle.InputManifestSha256;ModelId=[string]$record.model_id;ModelRevision=[string]$record.model_revision;Instruction=$instruction}
}catch{if($bundleCreated -and (Test-Path -LiteralPath $runRoot -PathType Container)){$null=Assert-SystemV7TreeNoReparse -RootPath $runRoot -ContainmentRoot $project;[IO.Directory]::Delete($runRoot,$true)};throw}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
