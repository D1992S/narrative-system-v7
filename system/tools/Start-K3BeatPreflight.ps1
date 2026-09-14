[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9._-]{7,80}$')][string]$RunId
)
$ErrorActionPreference='Stop';$project=[IO.Path]::GetFullPath($ProjectPath);$systemRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Project-Origin.ps1');. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1');. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project -SystemRoot $systemRoot | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project;$snapshotCreated=$false;$bundleCreated=$false;$runRoot=Join-Path $project "_work\narrative-runs\$RunId"
try{
if(Test-Path -LiteralPath $runRoot){throw "RUN_BUNDLE_ALREADY_EXISTS: $RunId"}
$meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8;$null=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$beatDir=Join-Path $project "_work\k3\beats\$ActId";$statePath=Join-Path $beatDir 'state.json';$beatPath=Join-Path $beatDir 'beat-sheet.json';foreach($path in @($statePath,$beatPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "BEAT_PREFLIGHT_INPUT_MISSING: $path"}}
$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String;if([string]$state.status -cne 'AWAITING_BEAT_PREFLIGHT'){throw "BEAT_PREFLIGHT_STATE_INVALID: $($state.status)"}
$generateManifest=Join-Path $project "_work\narrative-runs\$([string]$state.generate_run_id)\input-manifest.json";$generateBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $generateManifest -RequireLiveSource;if(-not $generateBundle.Valid){throw "GENERATE_BUNDLE_INVALID: $($generateBundle.Errors -join '; ')"}
$packetEntry=@($generateBundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PACKET'});if($packetEntry.Count -ne 1){throw 'GENERATE_ACT_PACKET_INPUT_INVALID'};$packetSnapshot=Join-Path $project ([string]$packetEntry[0].bundle_relative)
$packet=Get-Content -LiteralPath $packetSnapshot -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$beat=Get-Content -LiteralPath $beatPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$beatSemantic=Get-SystemV7BeatSheetSemanticState -Packet $packet -BeatSheet $beat -ActId $ActId -ExpectedGenerateRunId ([string]$state.generate_run_id);if(-not $beatSemantic.Valid){throw "BEAT_PREFLIGHT_INPUT_SEMANTIC_INVALID: $($beatSemantic.Errors -join '; ')"};if((Get-FileHash -LiteralPath $beatPath -Algorithm SHA256).Hash -cne [string]$state.beat_sheet_sha256){throw 'BEAT_PREFLIGHT_STATE_SHEET_HASH_MISMATCH'}
$schemaSource=Join-Path $systemRoot '_SYSTEM\NARRATIVE\BEAT-PREFLIGHT-SCHEMA.md';$schemaSha=(Get-FileHash -LiteralPath $schemaSource -Algorithm SHA256).Hash;$inputDir=Join-Path $project '_work\k3\preflight-inputs';[IO.Directory]::CreateDirectory($inputDir)|Out-Null;$schemaSnapshot=Join-Path $inputDir "beat-preflight-schema-$schemaSha.md"
if(Test-Path -LiteralPath $schemaSnapshot -PathType Leaf){if((Get-FileHash -LiteralPath $schemaSnapshot -Algorithm SHA256).Hash -cne $schemaSha){throw 'BEAT_PREFLIGHT_SCHEMA_SNAPSHOT_STALE'}}else{$temp=Join-Path $inputDir ('.schema-'+[guid]::NewGuid().ToString('N')+'.tmp');try{[IO.File]::Copy($schemaSource,$temp,$false);[IO.File]::Move($temp,$schemaSnapshot);$snapshotCreated=$true}finally{if(Test-Path -LiteralPath $temp -PathType Leaf){[IO.File]::Delete($temp)}}}
$bundle=New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType BEAT_PREFLIGHT -RunId $RunId -Inputs @{ACT_PACKET=$packetSnapshot;BEAT_SHEET=$beatPath;BEAT_SCHEMA=$schemaSnapshot}
$bundleCreated=$true;$post=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $bundle.Path -RequireLiveSource;if(-not $post.Valid){throw "BEAT_PREFLIGHT_BUNDLE_POSTVALIDATION_FAILED: $($post.Errors -join '; ')"}
[pscustomobject]@{Status='BEAT_PREFLIGHT_BUNDLE_READY';ActId=$ActId;RunId=$RunId;GenerateRunId=[string]$state.generate_run_id;InputManifestPath=$bundle.Path;Instruction='Uruchom osobny świeży kontekst ChatGPT/Codex tylko z bundle. Po PASS utwórz receipt przez New-NarrativeRunReceipt.ps1, a następnie wróć do tej samej sesji Claude aktu.'}
}catch{if($bundleCreated -and (Test-Path -LiteralPath $runRoot -PathType Container)){$null=Assert-SystemV7TreeNoReparse -RootPath $runRoot -ContainmentRoot $project;[IO.Directory]::Delete($runRoot,$true)};if($snapshotCreated -and (Test-Path -LiteralPath $schemaSnapshot -PathType Leaf)){[IO.File]::Delete($schemaSnapshot)};throw}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
