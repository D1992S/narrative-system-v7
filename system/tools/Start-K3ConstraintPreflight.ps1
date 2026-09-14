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
$stage=Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE';if($stage -notin @('K2B','K3')){throw 'CONSTRAINT_PREFLIGHT_REQUIRES_K2B_OR_K3'}
$packetDir=Join-Path $project '_work\k3\packets';$packetRecordPath=Join-Path $packetDir "$ActId.packet.json";$actPacketPath=Join-Path $packetDir "$ActId.act-packet.json";$ledgerPath=Join-Path $packetDir "$ActId.constraint-ledger.json";$stubPath=Join-Path $packetDir "$ActId.constraint-preflight.json"
foreach($path in @($packetRecordPath,$actPacketPath,$ledgerPath,$stubPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "CONSTRAINT_PREFLIGHT_INPUT_MISSING: $path"}}
$record=Get-Content -LiteralPath $packetRecordPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String;$stub=Get-Content -LiteralPath $stubPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if([string]$record.act_id -cne $ActId -or [string]$record.status -cne 'PRECHECK_PENDING' -or [string]$stub.status -cne 'PENDING'){throw 'CONSTRAINT_PREFLIGHT_STATE_INVALID'}
$schemaSource=Join-Path $systemRoot '_SYSTEM\NARRATIVE\CONSTRAINT-ATOMICITY-SCHEMA.md';if(-not(Test-Path -LiteralPath $schemaSource -PathType Leaf)){throw 'CONSTRAINT_PREFLIGHT_SCHEMA_MISSING'}
$schemaSha=(Get-FileHash -LiteralPath $schemaSource -Algorithm SHA256).Hash;$snapshotDir=Join-Path $project '_work\k3\preflight-inputs';[IO.Directory]::CreateDirectory($snapshotDir)|Out-Null;$schemaSnapshot=Join-Path $snapshotDir "constraint-atomicity-schema-$schemaSha.md"
if(Test-Path -LiteralPath $schemaSnapshot -PathType Leaf){if((Get-FileHash -LiteralPath $schemaSnapshot -Algorithm SHA256).Hash -cne $schemaSha){throw 'CONSTRAINT_PREFLIGHT_SCHEMA_SNAPSHOT_STALE'}}else{$temp=Join-Path $snapshotDir ('.schema-'+[guid]::NewGuid().ToString('N')+'.tmp');try{[IO.File]::Copy($schemaSource,$temp,$false);[IO.File]::Move($temp,$schemaSnapshot);$snapshotCreated=$true}finally{if(Test-Path -LiteralPath $temp -PathType Leaf){[IO.File]::Delete($temp)}}}
$bundle=New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType CONSTRAINT_ATOMICITY_PREFLIGHT -RunId $RunId -Inputs @{ACT_PACKET=$actPacketPath;CONSTRAINT_LEDGER=$ledgerPath;ATOMICITY_SCHEMA=$schemaSnapshot}
$bundleCreated=$true;$post=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $bundle.Path -RequireLiveSource;if(-not $post.Valid){throw "CONSTRAINT_PREFLIGHT_BUNDLE_POSTVALIDATION_FAILED: $($post.Errors -join '; ')"}
[pscustomobject]@{Status='CONSTRAINT_PREFLIGHT_BUNDLE_READY';ActId=$ActId;RunId=$RunId;InputManifestPath=$bundle.Path;InputManifestSha256=$bundle.InputManifestSha256;Instruction='Uruchom świeży kontekst ChatGPT/Codex wyłącznie z bundle. Zwróć dokładnie sześć pól wymaganych przez ATOMICITY_SCHEMA, bez prozy. Następnie utwórz receipt przez New-NarrativeRunReceipt.ps1.'}
}catch{if($bundleCreated -and (Test-Path -LiteralPath $runRoot -PathType Container)){$null=Assert-SystemV7TreeNoReparse -RootPath $runRoot -ContainmentRoot $project;[IO.Directory]::Delete($runRoot,$true)};if($snapshotCreated -and (Test-Path -LiteralPath $schemaSnapshot -PathType Leaf)){[IO.File]::Delete($schemaSnapshot)};throw}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
