[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ModelId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ModelRevision,
    [Parameter(Mandatory)][string]$ModelSettingsPath
)
$ErrorActionPreference='Stop';$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1');. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1');. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project;$snapshotCreated=$false;$manifestCreated=$false;$metaWritten=$false
try{
$metaPath=Join-Path $project 'meta.md';$metaSha=(Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash;$metaBytes=[IO.File]::ReadAllBytes($metaPath);$meta=[Text.UTF8Encoding]::new($false,$true).GetString($metaBytes);$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K2B'){throw 'MODEL_MANIFEST_MUST_BE_SET_IN_K2B'}
if(-not(Test-SystemV7ConcreteText $ModelId) -or -not(Test-SystemV7ConcreteText $ModelRevision)){throw 'MODEL_MANIFEST_ID_INVALID'}
$settings=[IO.Path]::GetFullPath($ModelSettingsPath);if(-not(Test-Path -LiteralPath $settings -PathType Leaf)){throw 'MODEL_SETTINGS_FILE_MISSING'};if(((Get-Item -LiteralPath $settings -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'MODEL_SETTINGS_REPARSE_POINT_BLOCKED'}
$settingsBytes=[IO.File]::ReadAllBytes($settings);$settingsSha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($settingsBytes))
try{$settingsText=[Text.UTF8Encoding]::new($false,$true).GetString($settingsBytes);$settingsJson=$settingsText|ConvertFrom-Json -DateKind String -Depth 32}catch{throw 'MODEL_SETTINGS_INVALID_JSON'}
if($null -eq $settingsJson -or @($settingsJson.PSObject.Properties).Count -eq 0){throw 'MODEL_SETTINGS_EMPTY'}
$k3Root=Join-Path $project '_work\k3';if(Test-Path -LiteralPath $k3Root -PathType Container){$existing=@(Get-ChildItem -LiteralPath $k3Root -File -Recurse -Force);if($existing.Count -gt 0){throw 'MODEL_MANIFEST_ALREADY_IN_USE_REBASE_REQUIRED'}}
$manifestDir=Join-Path $project '_work\model-manifests';[IO.Directory]::CreateDirectory($manifestDir)|Out-Null;$snapshot=Join-Path $manifestDir "k3-settings-$settingsSha.json"
$manifestCore=[ordered]@{schema='K3_MODEL_MANIFEST_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_origin_sha256=$origin.Sha256;model_id=$ModelId.Trim();model_revision=$ModelRevision.Trim();settings_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $snapshot);settings_sha256=$settingsSha;created_at_utc=[DateTime]::UtcNow.ToString('o')};$manifestCore['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $manifestCore);$manifestPath=Join-Path $manifestDir "k3-model-$($manifestCore.binding_sha256).json"
    if((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -cne $metaSha){throw 'MODEL_MANIFEST_META_CONFLICT'}
    if((Get-FileHash -LiteralPath $settings -Algorithm SHA256).Hash -cne $settingsSha){throw 'MODEL_SETTINGS_SOURCE_CHANGED'}
    if(Test-Path -LiteralPath $k3Root -PathType Container){$lockedExisting=@(Get-ChildItem -LiteralPath $k3Root -File -Recurse -Force);if($lockedExisting.Count -gt 0){throw 'MODEL_MANIFEST_BECAME_IN_USE_REBASE_REQUIRED'}}
    if(Test-Path -LiteralPath $snapshot -PathType Leaf){if((Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash -cne $settingsSha){throw 'MODEL_SETTINGS_SNAPSHOT_COLLISION'}}else{$temp=Join-Path $manifestDir ('.settings-'+[guid]::NewGuid().ToString('N')+'.tmp');try{[IO.File]::WriteAllBytes($temp,$settingsBytes);if((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash -cne $settingsSha){throw 'MODEL_SETTINGS_STAGED_HASH_MISMATCH'};[IO.File]::Move($temp,$snapshot);$snapshotCreated=$true}finally{if(Test-Path -LiteralPath $temp -PathType Leaf){[IO.File]::Delete($temp)}}}
    if(Test-Path -LiteralPath $manifestPath -PathType Leaf){throw 'MODEL_MANIFEST_ALREADY_EXISTS'};Write-SystemV7NarrativeCreateNewJson -Path $manifestPath -Value $manifestCore|Out-Null;$manifestCreated=$true
    $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    $updated=Set-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_ID' -Value $ModelId.Trim();$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_MODEL_REVISION' -Value $ModelRevision.Trim();$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_MODEL_SETTINGS_SHA256' -Value $settingsSha;$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_MODEL_MANIFEST_PATH' -Value (Get-SystemV7NarrativeRelativePath -Root $project -Path $manifestPath);$updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K3_MODEL_MANIFEST_SHA256' -Value $manifestSha
    Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text (ConvertTo-SystemV7LfText -Text $updated) -ExpectedCurrentSha256 $metaSha -HeldLockStream $lock|Out-Null
    $metaWritten=$true;$post=Get-SystemV7K3ModelManifestState -ProjectPath $project;if(-not $post.Valid -or [string]$post.Path -cne [string]$manifestPath){throw "MODEL_MANIFEST_POSTVALIDATION_FAILED: $($post.Errors -join '; ')"}
[pscustomobject]@{Status='K3_MODEL_MANIFEST_SET';ModelId=$ModelId.Trim();ModelRevision=$ModelRevision.Trim();SettingsSha256=$settingsSha;ManifestPath=$manifestPath;SettingsSnapshot=$snapshot}
}catch{if($metaWritten){[IO.File]::WriteAllBytes($metaPath,$metaBytes)};if($manifestCreated -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)){[IO.File]::Delete($manifestPath)};if($snapshotCreated -and (Test-Path -LiteralPath $snapshot -PathType Leaf)){[IO.File]::Delete($snapshot)};throw}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
