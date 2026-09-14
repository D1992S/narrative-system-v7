[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$ApprovalNote,
    [switch]$DawidApproved
)

$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
$systemRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$profileRoot=[IO.Path]::GetFullPath((Join-Path $systemRoot '_SYSTEM\NARRATIVE\VOICE-PROFILES'))
$profile=[IO.Path]::GetFullPath($ProfilePath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project -SystemRoot $systemRoot | Out-Null

if(-not $DawidApproved){throw 'VOICE_PROFILE_SELECTION_REQUIRES_EXPLICIT_DAWID_APPROVAL'}
if(-not(Test-SystemV7ConcreteText -Value $ApprovalNote) -or $ApprovalNote.Trim().Length -lt 12){throw 'VOICE_PROFILE_SELECTION_NOTE_NOT_CONCRETE'}
$profilePrefix=$profileRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
if(-not $profile.StartsWith($profilePrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'VOICE_PROFILE_PATH_OUTSIDE_PROFILE_ROOT'}
Assert-SystemV7PathNoReparse -Path $profile -ContainmentRoot $profileRoot|Out-Null
$voice=Get-SystemV7VoiceProfileState -ProfilePath $profile
if(-not $voice.Valid){throw "VOICE_PROFILE_NOT_APPROVED: $($voice.Errors -join '; ')"}

$voiceLockPath=Join-Path $profileRoot '.voice-profile.lock';$voiceLock=$null;$projectLock=$null;$receiptCreated=$false;$metaWritten=$false
$metaPath=Join-Path $project 'meta.md';$receiptPath=$null;$metaBytes=$null
function Restore-BytesAtomic([string]$Path,[byte[]]$Bytes){
    $directory=Split-Path -Parent $Path;$temp=Join-Path $directory ('.voice-restore-'+[guid]::NewGuid().ToString('N')+'.tmp');$backup=Join-Path $directory ('.voice-restore-backup-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{[IO.File]::WriteAllBytes($temp,$Bytes);[IO.File]::Replace($temp,$Path,$backup,$true)}finally{if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)};if(Test-Path -LiteralPath $backup){[IO.File]::Delete($backup)}}
}
try{
    $voiceLock=[IO.File]::Open($voiceLockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $projectLock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
    $lockedVoice=Get-SystemV7VoiceProfileState -ProfilePath $profile
    if(-not $lockedVoice.Valid -or $lockedVoice.ProfileSha256 -cne $voice.ProfileSha256){throw 'VOICE_PROFILE_CHANGED_DURING_SELECTION'}
    if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){throw 'PROJECT_META_MISSING'}
    $metaBytes=[IO.File]::ReadAllBytes($metaPath);$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'VOICE_PROFILE_SELECTION_REQUIRES_NARRATIVE_V2'}
    $origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
    $stage=Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE'
    if($stage -notin @('W0','K0','K1','K2','K2B')){throw "VOICE_PROFILE_SELECTION_TOO_LATE: $stage"}
    if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_PREFIX_SHA256') -cne 'BRAK' -or (Test-Path -LiteralPath (Join-Path $project '_work\k3\prefix\prefix.manifest.json') -PathType Leaf)){throw 'VOICE_PROFILE_SELECTION_AFTER_PREFIX_FREEZE'}

    $pathFieldCount=@([regex]::Matches($meta,'(?m)^VOICE_PROFILE_SELECTION_RECEIPT_PATH:')).Count
    $shaFieldCount=@([regex]::Matches($meta,'(?m)^VOICE_PROFILE_SELECTION_RECEIPT_SHA256:')).Count
    if($pathFieldCount -eq 0 -and $shaFieldCount -eq 0){
        $statusMatch=[regex]::Match($meta,'(?m)^VOICE_PROFILE_STATUS:.*$')
        if(-not $statusMatch.Success){throw 'VOICE_PROFILE_STATUS_FIELD_MISSING'}
        $insert="VOICE_PROFILE_STATUS: $((Get-SystemV7NarrativeMetaField -Text $meta -Name 'VOICE_PROFILE_STATUS'))`nVOICE_PROFILE_SELECTION_RECEIPT_PATH: BRAK`nVOICE_PROFILE_SELECTION_RECEIPT_SHA256: BRAK"
        $meta=$meta.Remove($statusMatch.Index,$statusMatch.Length).Insert($statusMatch.Index,$insert)
    }elseif($pathFieldCount -ne 1 -or $shaFieldCount -ne 1){throw 'VOICE_PROFILE_SELECTION_META_FIELDS_INVALID'}

    if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'VOICE_PROFILE_STATUS') -ceq 'APPROVED'){
        $existing=Get-SystemV7VoiceProfileSelectionState -ProjectPath $project -MetaText $meta
        if($existing.Valid -and [string]$existing.Data.voice_profile_sha256 -ceq $lockedVoice.ProfileSha256){
            [pscustomobject]@{Status='VOICE_PROFILE_ALREADY_SELECTED';ProjectPath=$project;Revision=$lockedVoice.Revision;ReceiptPath=$existing.Path;ReceiptSha256=$existing.Sha256}
            return
        }
        throw "EXISTING_VOICE_PROFILE_SELECTION_INVALID: $($existing.Errors -join '; ')"
    }

    $selectedAt=[DateTime]::UtcNow.ToString('o')
    $record=[ordered]@{schema='SYSTEM_V7_VOICE_PROFILE_SELECTION_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;actor='DAWID';attestation_scope='PROJECT_VOICE_PROFILE_ACTIVATION';project_origin_sha256=[string]$origin.Sha256;voice_profile_revision=$lockedVoice.Revision;voice_profile_sha256=$lockedVoice.ProfileSha256;approval_note=$ApprovalNote.Trim();selected_at_utc=$selectedAt}
    $record['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $record)
    $relative="_work/system/voice-profile-selection-$($lockedVoice.ProfileSha256).json";$receiptPath=Join-Path $project $relative.Replace('/','\')
    if(Test-Path -LiteralPath $receiptPath){throw 'VOICE_PROFILE_SELECTION_RECEIPT_ALREADY_EXISTS_WITHOUT_VALID_META'}
    $receiptDirectory=Split-Path -Parent $receiptPath
    [IO.Directory]::CreateDirectory($receiptDirectory)|Out-Null
    Assert-SystemV7PathNoReparse -Path $receiptDirectory -ContainmentRoot $project|Out-Null
    $recordText=ConvertTo-SystemV7CanonicalJson -Value $record
    Write-BytesCreateNewAtomic -Path $receiptPath -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($recordText));$receiptCreated=$true
    $receiptSha=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    $updated=Set-SystemV7NarrativeMetaField -Text $meta -Name 'VOICE_PROFILE_REVISION' -Value $lockedVoice.Revision
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'VOICE_PROFILE_STATUS' -Value 'APPROVED'
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'VOICE_PROFILE_SELECTION_RECEIPT_PATH' -Value $relative
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'VOICE_PROFILE_SELECTION_RECEIPT_SHA256' -Value $receiptSha
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'LAST_UPDATED' -Value ([DateTime]::UtcNow.ToString('yyyy-MM-dd'))
    Write-SystemV7NarrativeAtomicText -Path $metaPath -Text $updated|Out-Null;$metaWritten=$true
    $state=Get-SystemV7VoiceProfileSelectionState -ProjectPath $project -MetaText $updated
    if(-not $state.Valid){throw "VOICE_PROFILE_SELECTION_POSTVALIDATION_FAILED: $($state.Errors -join '; ')"}
    [pscustomobject]@{Status='VOICE_PROFILE_SELECTED';ProjectPath=$project;Revision=$lockedVoice.Revision;ProfileSha256=$lockedVoice.ProfileSha256;ReceiptPath=$state.Path;ReceiptSha256=$state.Sha256}
}catch{
    if($metaWritten -and $metaBytes){Restore-BytesAtomic -Path $metaPath -Bytes $metaBytes}
    if($receiptCreated -and $receiptPath -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){[IO.File]::Delete($receiptPath)}
    throw
}finally{
    if($projectLock){$projectLock.Dispose()}
    if($voiceLock){$voiceLock.Dispose()}
}
