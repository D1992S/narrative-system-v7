[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9._-]{7,80}$')][string]$RunId
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project;$snapshotCreated=$false;$bundleCreated=$false;$runRoot=Join-Path $project "_work\narrative-runs\$RunId"
try{
if(Test-Path -LiteralPath $runRoot){throw "RUN_BUNDLE_ALREADY_EXISTS: $RunId"}
$meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8
$null=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$actDir=Join-Path $project "_work\k3\acts\$ActId";$statePath=Join-Path $actDir 'state.json'
if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'ACT_STATE_MISSING'}
$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if([string]$state.status -cne 'AWAITING_ATTEST'){throw "ACT_NOT_AWAITING_ATTEST: $($state.status)"}
$generateReceipt=Join-Path $project ([string]$state.generate_run_receipt_relative)
$generateProof=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $generateReceipt -ExpectedRunType 'GENERATE_ACT' -RequireLiveInputs
if(-not $generateProof.Valid -or $generateProof.Sha256 -cne [string]$state.generate_run_receipt_sha256){throw "GENERATE_ACT_PROOF_INVALID: $($generateProof.Errors -join '; ')"}
$systemSchema=Join-Path (Split-Path -Parent $PSScriptRoot) '_SYSTEM\NARRATIVE\CONTINUITY-SCHEMA.md'
if(-not(Test-Path -LiteralPath $systemSchema -PathType Leaf)){throw 'CONTINUITY_SCHEMA_SOURCE_MISSING'}
$schemaSha=(Get-FileHash -LiteralPath $systemSchema -Algorithm SHA256).Hash
$attestInputDir=Join-Path $project '_work\k3\attest-inputs';[IO.Directory]::CreateDirectory($attestInputDir)|Out-Null
$schemaSnapshot=Join-Path $attestInputDir "continuity-schema-$schemaSha.md"
if(Test-Path -LiteralPath $schemaSnapshot -PathType Leaf){if((Get-FileHash -LiteralPath $schemaSnapshot -Algorithm SHA256).Hash -cne $schemaSha){throw 'CONTINUITY_SCHEMA_SNAPSHOT_STALE'}}else{$schemaTemp=Join-Path $attestInputDir ('.schema-'+[guid]::NewGuid().ToString('N')+'.tmp');try{[IO.File]::Copy($systemSchema,$schemaTemp,$false);[IO.File]::Move($schemaTemp,$schemaSnapshot);$snapshotCreated=$true}finally{if(Test-Path -LiteralPath $schemaTemp -PathType Leaf){[IO.File]::Delete($schemaTemp)}}}
$inputs=@{
    ACT_PROSE_BLOCKS=Join-Path $actDir 'blocks.json'
    CONTINUITY_IN=Join-Path $project "_work\k3\continuity\$ActId.in.json"
    CONTINUITY_OUT=Join-Path $actDir 'out.json'
    CONTINUITY_SCHEMA=$schemaSnapshot
}
$blocks=Get-Content -LiteralPath $inputs.ACT_PROSE_BLOCKS -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$out=Get-Content -LiteralPath $inputs.CONTINUITY_OUT -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$packet=Get-Content -LiteralPath (Join-Path $project "_work\k3\packets\$ActId.act-packet.json") -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
if((Get-FileHash -LiteralPath $inputs.ACT_PROSE_BLOCKS -Algorithm SHA256).Hash -cne [string]$state.blocks_sha256 -or (Get-FileHash -LiteralPath $inputs.CONTINUITY_OUT -Algorithm SHA256).Hash -cne [string]$state.continuity_out_sha256){throw 'ATTEST_START_STATE_ARTIFACT_BINDING_MISMATCH'}
$prosePath=Join-Path $actDir 'prose.md';$proseBinding=Get-SystemV7ActProseBindingState -ActId $ActId -BlocksPath $inputs.ACT_PROSE_BLOCKS -ProsePath $prosePath;if(-not $proseBinding.Valid){throw "ATTEST_START_PROSE_BINDING_INVALID: $($proseBinding.Errors -join '; ')"};$traceBeat=$null;if([string]$packet.complexity_flag -ceq 'COMPLEX'){$traceBeat=Get-Content -LiteralPath (Join-Path $project "_work\k3\beats\$ActId\beat-sheet.json") -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64};$trace=Get-SystemV7ActSubmissionTraceState -Packet $packet -Blocks @($blocks.blocks) -BeatSheet $traceBeat;if(-not $trace.Valid){throw "ATTEST_START_TRACE_INVALID: $($trace.Errors -join '; ')"}
$architecture=Get-SystemV7NarrativeArchitecture -Path (Join-Path $project '02-architektura-odcinka.md');$outState=Get-SystemV7ContinuityOutStructuralState -ActId $ActId -ContinuityOut $out -BlocksData $blocks -ArchitectureData $architecture.Data;if(-not $outState.Valid){throw "ATTEST_START_CONTINUITY_OUT_INVALID: $($outState.Errors -join '; ')"}
$bundle=New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType CONTINUITY_ATTEST -RunId $RunId -Inputs $inputs
$bundleCreated=$true;$post=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $bundle.Path -RequireLiveSource;if(-not $post.Valid){throw "CONTINUITY_ATTEST_BUNDLE_POSTVALIDATION_FAILED: $($post.Errors -join '; ')"}
[pscustomobject]@{Status='FRESH_ATTEST_CONTEXT_BUNDLE_READY';ActId=$ActId;RunId=$RunId;InputManifestPath=$bundle.Path;Instruction='Uruchom świeży kontekst ChatGPT/Codex wyłącznie z tym bundle. Nie podawaj Story Spine, packetu ani planu revealów.'}
}catch{if($bundleCreated -and (Test-Path -LiteralPath $runRoot -PathType Container)){$null=Assert-SystemV7TreeNoReparse -RootPath $runRoot -ContainmentRoot $project;[IO.Directory]::Delete($runRoot,$true)};if($snapshotCreated -and (Test-Path -LiteralPath $schemaSnapshot -PathType Leaf)){[IO.File]::Delete($schemaSnapshot)};throw}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
