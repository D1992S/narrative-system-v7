[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9._-]{7,80}$')][string]$GenerateRunId,
    [Parameter(Mandatory)][string]$BeatSheetPath
)
$ErrorActionPreference='Stop';$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1');. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1');. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
try{
$meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8;$null=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K3'){throw 'BEAT_IMPORT_REQUIRES_STAGE_K3'}
$manifestPath=Join-Path $project "_work\narrative-runs\$GenerateRunId\input-manifest.json";$bundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $manifestPath -RequireLiveSource
if(-not $bundle.Valid -or [string]$bundle.Data.run_type -cne 'GENERATE_ACT'){throw "GENERATE_BUNDLE_INVALID: $($bundle.Errors -join '; ')"}
$packetEntry=@($bundle.Data.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PACKET'});if($packetEntry.Count -ne 1){throw 'GENERATE_BUNDLE_ACT_PACKET_INVALID'}
$packet=Get-Content -LiteralPath (Join-Path $project ([string]$packetEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
if([string]$packet.act_id -cne $ActId -or [string]$packet.complexity_flag -cne 'COMPLEX'){throw 'BEAT_SHEET_NOT_ALLOWED_FOR_PACKET'}
if(-not(Test-Path -LiteralPath $BeatSheetPath -PathType Leaf)){throw 'BEAT_SHEET_SUBMISSION_MISSING'}
try{$sheet=Get-Content -LiteralPath $BeatSheetPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{throw 'BEAT_SHEET_INVALID_JSON'}
$semantic=Get-SystemV7BeatSheetSemanticState -Packet $packet -BeatSheet $sheet -ActId $ActId;if(-not $semantic.Valid){throw "BEAT_SHEET_SEMANTIC_INVALID: $($semantic.Errors -join '; ')"}
$value=[ordered]@{schema='K3_BEAT_SHEET_V1';act_id=$ActId;packet_status='BEAT_SHEET_READY';generate_run_id=$GenerateRunId;beats=@($semantic.NormalizedBeats)};$beatJson=ConvertTo-SystemV7CanonicalJson -Value $value;$beatDir=Join-Path $project "_work\k3\beats\$ActId";$state=[ordered]@{schema='K3_BEAT_STATE_V1';act_id=$ActId;generate_run_id=$GenerateRunId;status='AWAITING_BEAT_PREFLIGHT';beat_sheet_sha256=(Get-SystemV7NarrativeSha256Text -Text $beatJson);prefix_sha256=[string]$packet.prefix_sha256;model_id=[string]$packet.model_id;model_revision=[string]$packet.model_revision;preflight_run_id='BRAK';preflight_receipt_relative='BRAK';preflight_receipt_sha256='BRAK'}
if(Test-Path -LiteralPath $beatDir){throw 'BEAT_STATE_ALREADY_EXISTS'};$stageDir=Join-Path (Split-Path -Parent $beatDir) ('.beat-'+$ActId+'-'+[guid]::NewGuid().ToString('N'));$beatCreated=$false
try{[IO.Directory]::CreateDirectory($stageDir)|Out-Null;Write-SystemV7NarrativeAtomicText -Path (Join-Path $stageDir 'beat-sheet.json') -Text $beatJson|Out-Null;Write-SystemV7NarrativeAtomicText -Path (Join-Path $stageDir 'state.json') -Text (ConvertTo-SystemV7CanonicalJson -Value $state)|Out-Null;[IO.Directory]::Move($stageDir,$beatDir);$beatCreated=$true;$liveSheet=Get-Content -LiteralPath (Join-Path $beatDir 'beat-sheet.json') -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$liveSemantic=Get-SystemV7BeatSheetSemanticState -Packet $packet -BeatSheet $liveSheet -ActId $ActId -ExpectedGenerateRunId $GenerateRunId;if(-not $liveSemantic.Valid -or (Get-FileHash -LiteralPath (Join-Path $beatDir 'beat-sheet.json') -Algorithm SHA256).Hash -cne (Get-SystemV7NarrativeSha256Text -Text $beatJson)){throw "BEAT_IMPORT_POSTVALIDATION_FAILED: $($liveSemantic.Errors -join '; ')"}}catch{if($beatCreated -and (Test-Path -LiteralPath $beatDir -PathType Container)){$null=Assert-SystemV7TreeNoReparse -RootPath $beatDir -ContainmentRoot $project;[IO.Directory]::Delete($beatDir,$true)};throw}finally{if(Test-Path -LiteralPath $stageDir -PathType Container){[IO.Directory]::Delete($stageDir,$true)}}
[pscustomobject]@{Status='AWAITING_BEAT_PREFLIGHT';ActId=$ActId;GenerateRunId=$GenerateRunId;BeatSheetPath=Join-Path $beatDir 'beat-sheet.json';BeatCount=$semantic.NormalizedBeats.Count}
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
