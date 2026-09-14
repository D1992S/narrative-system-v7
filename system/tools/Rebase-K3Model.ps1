[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$NewModelId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$NewModelRevision,
    [Parameter(Mandatory)][string]$NewModelSettingsPath,
    [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$RepresentativeActId,
    [Parameter(Mandatory)][string]$TrialActPath,
    [Parameter(Mandatory)][string]$BlindComparisonPath,
    [Parameter(Mandatory)][string]$ImpactReviewPath,
    [Parameter(Mandatory)][string]$Reason,
    [switch]$DawidApproved
)
$ErrorActionPreference='Stop';if(-not $DawidApproved){throw 'DAWID_APPROVAL_REQUIRED'};if($Reason.Trim().Length -lt 15){throw 'MODEL_REBASE_REASON_NOT_CONCRETE'}
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1');. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1');. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
try{
$metaPath=Join-Path $project 'meta.md';$metaBytes=[IO.File]::ReadAllBytes($metaPath);$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$metaSha=Get-Sha256HexFromBytes -Bytes $metaBytes;$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K3'){throw 'MODEL_REBASE_REQUIRES_STAGE_K3; use Reopen-Stage first'}
$oldManifest=Get-SystemV7K3ModelManifestState -ProjectPath $project -MetaText $meta;if(-not $oldManifest.Valid){throw "OLD_MODEL_MANIFEST_INVALID: $($oldManifest.Errors -join '; ')"}
$oldModelId=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_ID';$oldModelRevision=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_REVISION';$oldSettingsSha=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_SETTINGS_SHA256'
$k3Root=Join-Path $project '_work\k3';if(-not(Test-Path -LiteralPath $k3Root -PathType Container) -or @(Get-ChildItem -LiteralPath $k3Root -File -Recurse -Force).Count -eq 0){throw 'MODEL_REBASE_NOT_NEEDED_USE_SET_MODEL_MANIFEST'}
if($NewModelId.Trim() -ceq $oldModelId -and $NewModelRevision.Trim() -ceq $oldModelRevision){throw 'MODEL_REBASE_NEW_MODEL_EQUALS_OLD'}
$inputs=[ordered]@{settings=[IO.Path]::GetFullPath($NewModelSettingsPath);trial=[IO.Path]::GetFullPath($TrialActPath);comparison=[IO.Path]::GetFullPath($BlindComparisonPath);impact=[IO.Path]::GetFullPath($ImpactReviewPath)}
foreach($entry in $inputs.GetEnumerator()){if(-not(Test-Path -LiteralPath $entry.Value -PathType Leaf)){throw "MODEL_REBASE_INPUT_MISSING: $($entry.Key)"};if(((Get-Item -LiteralPath $entry.Value -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "MODEL_REBASE_INPUT_REPARSE_POINT: $($entry.Key)"};if($entry.Key -ne 'settings'){$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $entry.Value}}
try{$settingsData=Get-Content -LiteralPath $inputs.settings -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32}catch{throw 'NEW_MODEL_SETTINGS_INVALID_JSON'};if(@($settingsData.PSObject.Properties).Count -eq 0){throw 'NEW_MODEL_SETTINGS_EMPTY'}
$comparison=Get-Content -LiteralPath $inputs.comparison -Raw -Encoding UTF8;$impact=Get-Content -LiteralPath $inputs.impact -Raw -Encoding UTF8
$getRequired={param($text,$name)$m=@([regex]::Matches($text,"(?m)^$([regex]::Escape($name)):\s*(.*?)\s*$"));if($m.Count -ne 1){throw "MODEL_REBASE_FIELD_COUNT_INVALID: $name"};$m[0].Groups[1].Value.Trim()}
foreach($pair in @(@('VERDICT','PASS'),@('TRIAL_ACT_ID',$RepresentativeActId),@('OLD_MODEL_ID',$oldModelId),@('NEW_MODEL_ID',$NewModelId.Trim()),@('OLD_MODEL_REVISION',$oldModelRevision),@('NEW_MODEL_REVISION',$NewModelRevision.Trim()),@('VOICE_MATCH','PASS'),@('FUNCTION_MATCH','PASS'))){if((&$getRequired $comparison $pair[0]) -cne $pair[1]){throw "MODEL_REBASE_COMPARISON_FAIL: $($pair[0])"}}
if((&$getRequired $impact 'VERDICT') -cne 'PASS' -or (&$getRequired $impact 'SCOPE') -cne 'FULL_DRAFT'){throw 'MODEL_REBASE_IMPACT_REVIEW_FAIL'}
$comparisonTask=&$getRequired $comparison 'TASK_ID';$impactTask=&$getRequired $impact 'TASK_ID';if($comparisonTask -ceq $impactTask -or $comparisonTask -notmatch '^[A-Z0-9][A-Z0-9._-]{7,120}$' -or $impactTask -notmatch '^[A-Z0-9][A-Z0-9._-]{7,120}$'){throw 'MODEL_REBASE_TASK_SEPARATION_INVALID'}

$getK3TreeSha={param([string]$Root)$fileRows=[Collections.Generic.List[object]]::new();$k3Prefix=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;$paths=[string[]]@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force|ForEach-Object{$_.FullName});[Array]::Sort($paths,[StringComparer]::Ordinal);foreach($path in $paths){$fileRows.Add([ordered]@{relative=$path.Substring($k3Prefix.Length).Replace('\','/');sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $path).Length})};Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($fileRows))}
$oldTreeSha=&$getK3TreeSha $k3Root;$newSettingsSha=(Get-FileHash -LiteralPath $inputs.settings -Algorithm SHA256).Hash
$intentCore=[ordered]@{operation='MODEL_REBASE';project_origin_sha256=$origin.Sha256;input_meta_sha256=$metaSha;old_model_id=$oldModelId;old_model_revision=$oldModelRevision;old_settings_sha256=$oldSettingsSha;new_model_id=$NewModelId.Trim();new_model_revision=$NewModelRevision.Trim();new_settings_sha256=$newSettingsSha;representative_act_id=$RepresentativeActId;trial_sha256=(Get-FileHash -LiteralPath $inputs.trial -Algorithm SHA256).Hash;comparison_sha256=(Get-FileHash -LiteralPath $inputs.comparison -Algorithm SHA256).Hash;impact_sha256=(Get-FileHash -LiteralPath $inputs.impact -Algorithm SHA256).Hash;old_k3_tree_sha256=$oldTreeSha;reason=$Reason.Trim()};$intentSha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $intentCore)
$archiveRelative="_work/k3-model-stale/$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))-$($intentSha.Substring(0,16))";$archive=Join-Path $project $archiveRelative;$archiveParent=Split-Path -Parent $archive
$modelDir=Join-Path $project '_work\model-manifests';$rebaseDir=Join-Path $project '_work\system\model-rebase';[IO.Directory]::CreateDirectory($modelDir)|Out-Null;[IO.Directory]::CreateDirectory($rebaseDir)|Out-Null;[IO.Directory]::CreateDirectory($archiveParent)|Out-Null
$settingsSnapshot=Join-Path $modelDir "k3-settings-$newSettingsSha.json";$modelRecord=[ordered]@{schema='K3_MODEL_MANIFEST_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_origin_sha256=$origin.Sha256;model_id=$NewModelId.Trim();model_revision=$NewModelRevision.Trim();settings_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $settingsSnapshot);settings_sha256=$newSettingsSha;created_at_utc=[DateTime]::UtcNow.ToString('o')};$modelRecord['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $modelRecord);$modelPath=Join-Path $modelDir "k3-model-$($modelRecord.binding_sha256).json"
$receipt=[ordered]@{};foreach($key in $intentCore.Keys){$receipt[$key]=$intentCore[$key]};$receipt['schema']='SYSTEM_V7_MODEL_REBASE_RECEIPT_V1';$receipt['actor']='DAWID';$receipt['comparison_task_id']=$comparisonTask;$receipt['impact_task_id']=$impactTask;$receipt['archive_relative']=$archiveRelative;$receipt['model_manifest_relative']=Get-SystemV7NarrativeRelativePath -Root $project -Path $modelPath;$receipt['created_at_utc']=[DateTime]::UtcNow.ToString('o');$receipt['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $receipt);$receiptPath=Join-Path $rebaseDir "model-rebase-$intentSha.json"
$settingsCreated=$false;$modelCreated=$false;$receiptCreated=$false;$moved=$false;$metaWritten=$false
try{
    if((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -cne $metaSha){throw 'MODEL_REBASE_META_CONFLICT'}
    if((&$getK3TreeSha $k3Root) -cne $oldTreeSha){throw 'MODEL_REBASE_K3_TREE_CHANGED'}
    foreach($entry in $inputs.GetEnumerator()){if((Get-FileHash -LiteralPath $entry.Value -Algorithm SHA256).Hash -cne [string]$intentCore.("$($entry.Key)_sha256")){if($entry.Key -eq 'settings'){if((Get-FileHash -LiteralPath $entry.Value -Algorithm SHA256).Hash -cne $newSettingsSha){throw 'MODEL_REBASE_INPUT_CHANGED'}}else{throw "MODEL_REBASE_INPUT_CHANGED: $($entry.Key)"}}}
    if(Test-Path -LiteralPath $archive){throw 'MODEL_REBASE_ARCHIVE_COLLISION'}
    if(Test-Path -LiteralPath $settingsSnapshot -PathType Leaf){if((Get-FileHash -LiteralPath $settingsSnapshot -Algorithm SHA256).Hash -cne $newSettingsSha){throw 'MODEL_SETTINGS_SNAPSHOT_COLLISION'}}else{[IO.File]::Copy($inputs.settings,$settingsSnapshot,$false);$settingsCreated=$true}
    Write-SystemV7NarrativeCreateNewJson -Path $modelPath -Value $modelRecord|Out-Null;$modelCreated=$true;Write-SystemV7NarrativeCreateNewJson -Path $receiptPath -Value $receipt|Out-Null;$receiptCreated=$true
    [IO.Directory]::Move($k3Root,$archive);$moved=$true
    $modelManifestSha=(Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash;$updated=Set-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_ID' -Value $NewModelId.Trim();$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_MODEL_REVISION' -Value $NewModelRevision.Trim();$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_MODEL_SETTINGS_SHA256' -Value $newSettingsSha;$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_MODEL_MANIFEST_PATH' -Value (Get-SystemV7NarrativeRelativePath -Root $project -Path $modelPath);$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_MODEL_MANIFEST_SHA256' -Value $modelManifestSha;$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_PREFIX_SHA256' -Value 'BRAK';$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_LAST_ATTESTED_ACT' -Value 'BRAK';$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'CONTINUITY_STATUS' -Value 'STALE';$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_EDITOR_PROOF' -Value 'BRAK';$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_VERIFY_PROOF' -Value 'BRAK';$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_COLD_READER_PROOF' -Value 'BRAK';$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_PROOF_SET_SHA256' -Value 'BRAK';$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'LAST_GATE' -Value 'MODEL_REBASE_REQUIRED_REGENERATION';$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'NEXT_ACTION' -Value 'Przepisz wszystkie akty nowym modelem; nie mieszaj autorów ani starych atestów.'
    Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text (ConvertTo-SystemV7LfText -Text $updated) -ExpectedCurrentSha256 $metaSha -HeldLockStream $lock|Out-Null
    $metaWritten=$true
    $liveMeta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$postManifest=Get-SystemV7K3ModelManifestState -ProjectPath $project -MetaText $liveMeta;if(-not $postManifest.Valid -or [string]$postManifest.Path -cne [string]$modelPath -or (Test-Path -LiteralPath $k3Root) -or -not(Test-Path -LiteralPath $archive -PathType Container) -or (&$getK3TreeSha $archive) -cne $oldTreeSha){throw "MODEL_REBASE_POSTVALIDATION_FAILED: $($postManifest.Errors -join '; ')"}
}catch{
    if($metaWritten){[IO.File]::WriteAllBytes($metaPath,$metaBytes)}
    if($moved -and -not(Test-Path -LiteralPath $k3Root) -and (Test-Path -LiteralPath $archive -PathType Container)){[IO.Directory]::Move($archive,$k3Root)}
    if($receiptCreated -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){[IO.File]::Delete($receiptPath)};if($modelCreated -and (Test-Path -LiteralPath $modelPath -PathType Leaf)){[IO.File]::Delete($modelPath)};if($settingsCreated -and (Test-Path -LiteralPath $settingsSnapshot -PathType Leaf)){[IO.File]::Delete($settingsSnapshot)}
    throw
}
[pscustomobject]@{Status='MODEL_REBASE_COMMITTED_REGENERATION_REQUIRED';OldModelId=$oldModelId;NewModelId=$NewModelId.Trim();ArchivePath=$archive;ReceiptPath=$receiptPath;ReceiptSha256=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash;ContinuityStatus='STALE'}
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
