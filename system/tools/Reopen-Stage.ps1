[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateSet('K2B','K3')][string]$TargetStage,
    [Parameter(Mandatory)][ValidateSet('MISSING_EVIDENCE','ARCHITECTURE_CONFLICT','OVERLOADED_PACKET','UNSUPPORTED_BRIDGE','PROSE_CORRECTION','SOURCE_CHANGE','SCOPE_CHANGE','SCENE_WEAVE_CHANGE','QUESTION_REVEAL_CHANGE','SIGNIFICANT_K5_CORRECTION')][string]$ReasonCode,
    [Parameter(Mandatory)][string]$Scope,
    [ValidatePattern('^$|^ACT-\d{3}$')][string]$FromActId='',
    [switch]$DawidApproved
)
$TargetStage=$TargetStage.ToUpperInvariant();$ReasonCode=$ReasonCode.ToUpperInvariant()
$ErrorActionPreference='Stop';if($Scope.Trim().Length -lt 8){throw 'REOPEN_SCOPE_NOT_CONCRETE'}
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1');. (Join-Path $PSScriptRoot 'Narrative-V2.ps1');. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1');. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
$dispatchMetaPath=Join-Path $project 'meta.md'
if(-not(Test-Path -LiteralPath $dispatchMetaPath -PathType Leaf)){throw "META_MISSING: $dispatchMetaPath"}
$dispatchMeta=Get-Content -LiteralPath $dispatchMetaPath -Raw -Encoding UTF8
$dispatchWorkflow=Get-SystemV7NarrativeMetaField -Text $dispatchMeta -Name 'WORKFLOW_REVISION'
if($dispatchWorkflow -ceq '2026-08-30_K1_LITE_V2'){
    . (Join-Path $PSScriptRoot 'Legacy-Reopen.ps1')
    Invoke-SystemV7LegacyStageReopen -ProjectPath $project -TargetStage $TargetStage -ReasonCode $ReasonCode -Scope $Scope -FromActId $FromActId -DawidApproved:$DawidApproved
    return
}
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
try{
$metaPath=Join-Path $project 'meta.md';$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$metaSha=(Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash;$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'REOPEN_ONLY_NARRATIVE_V2'}
$from=Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE';$route="$from>$TargetStage";$allowed=@('K3>K2B','K4>K3','K4>K2B','K5>K3','K5>K2B');if($route -notin $allowed){throw "REOPEN_ROUTE_INVALID: $route"}
$actSequence=@((Get-SystemV7NarrativeMetaField -Text $meta -Name 'NARRATIVE_ACT_SEQUENCE') -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_ -match '^ACT-\d{3}$'})
$firstAffectedAct='ALL'
$localizedK2B=$false
if($TargetStage -ceq 'K2B' -and [string]::IsNullOrWhiteSpace($FromActId)){
    $scopeIds=@([regex]::Matches($Scope,'(?<![A-Z0-9-])ACT-\d{3}(?![A-Z0-9-])')|ForEach-Object{$_.Value}|Select-Object -Unique)
    if($scopeIds.Count -eq 1){$FromActId=$scopeIds[0]}
}
if($TargetStage -ceq 'K2B' -and -not [string]::IsNullOrWhiteSpace($FromActId)){$localizedK2B=$true}
if($TargetStage -ceq 'K3' -or $localizedK2B){
    if([string]::IsNullOrWhiteSpace($FromActId)){
        $scopeIds=@([regex]::Matches($Scope,'(?<![A-Z0-9-])ACT-\d{3}(?![A-Z0-9-])')|ForEach-Object{$_.Value}|Select-Object -Unique)
        $FromActId=if($scopeIds.Count -eq 1){$scopeIds[0]}elseif($actSequence.Count -gt 0){$actSequence[0]}else{''}
    }
    if([string]::IsNullOrWhiteSpace($FromActId) -or $FromActId -notin $actSequence){throw "REOPEN_FROM_ACT_INVALID: $FromActId"}
    $firstAffectedAct=$FromActId
}
$reasonRoutes=@{
    'K3>K2B'=@('MISSING_EVIDENCE','ARCHITECTURE_CONFLICT','OVERLOADED_PACKET','UNSUPPORTED_BRIDGE','SOURCE_CHANGE','SCOPE_CHANGE','SCENE_WEAVE_CHANGE','QUESTION_REVEAL_CHANGE')
    'K4>K3'=@('PROSE_CORRECTION');'K4>K2B'=@('SOURCE_CHANGE','SCOPE_CHANGE','SCENE_WEAVE_CHANGE','QUESTION_REVEAL_CHANGE','ARCHITECTURE_CONFLICT')
    'K5>K3'=@('SIGNIFICANT_K5_CORRECTION','PROSE_CORRECTION');'K5>K2B'=@('SOURCE_CHANGE','SCOPE_CHANGE','SCENE_WEAVE_CHANGE','QUESTION_REVEAL_CHANGE','SIGNIFICANT_K5_CORRECTION')
}
if($ReasonCode -notin @($reasonRoutes[$route])){throw "REOPEN_REASON_NOT_ALLOWED_FOR_ROUTE: $route/$ReasonCode"}
$approvalMode=if($from -ceq 'K5' -or $ReasonCode -in @('SCOPE_CHANGE','SOURCE_CHANGE')){'DAWID_REQUIRED'}else{'SYSTEM_ROUTE'};if($approvalMode -ceq 'DAWID_REQUIRED' -and -not $DawidApproved){throw 'DAWID_APPROVAL_REQUIRED'}
$previousPath=Get-SystemV7NarrativeMetaField -Text $meta -Name 'LAST_STATE_RECEIPT_PATH';$previousSha=Get-SystemV7NarrativeMetaField -Text $meta -Name 'LAST_STATE_RECEIPT_SHA256';if(($previousPath -ceq 'BRAK') -xor ($previousSha -ceq 'BRAK')){throw 'STATE_RECEIPT_HEAD_POINTER_INCOMPLETE'}
if($previousPath -cne 'BRAK'){$head=Get-StateReceiptHeadState -ProjectPath $project -MetaText $meta;if(-not $head.Valid){throw "CURRENT_STATE_RECEIPT_INVALID: $($head.Errors -join '; ')"}}
$artifacts=[Collections.Generic.List[object]]::new();foreach($relative in @('00-fundament-projektu.md','01-baza-dowodow.md','02-architektura-odcinka.md','03-draft.md','04-raport-qa.md','04B-fact-check.md','05-FINAL-SCRIPT.md')){$p=Join-Path $project $relative;if(Test-Path -LiteralPath $p -PathType Leaf){$artifacts.Add([ordered]@{relative=$relative;sha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash})}}
$invalidations=[Collections.Generic.List[object]]::new()
if($TargetStage -ceq 'K2B'){
    foreach($item in @('02 act projections in scope','K3 packets in scope','K3 prose and downstream acts','continuity attest chain from scope','04 Editor and Cold Reader','04B Verify','05 final')){$invalidations.Add([ordered]@{artifact=$item;status='STALE';scope=$Scope.Trim()})}
}else{
    foreach($item in @('K3 prose in scope','continuity attest chain from scope','04 Editor proof','04B Verify proof','04 Cold Reader proof','05 final')){$invalidations.Add([ordered]@{artifact=$item;status=if($item -match 'proof'){'RERUN_OR_CARRYFORWARD_REQUIRED'}else{'STALE'};scope=$Scope.Trim()})}
}
$getMoveFingerprint={param([string]$Path,[bool]$IsDirectory)if(-not $IsDirectory){$item=Get-Item -LiteralPath $Path -Force;return "FILE|$($item.Length)|$((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash)"};$root=[IO.Path]::GetFullPath($Path);$records=[Collections.Generic.List[object]]::new();foreach($item in @(Get-ChildItem -LiteralPath $root -Recurse -Force|Sort-Object FullName)){$relative=[IO.Path]::GetRelativePath($root,$item.FullName).Replace('\','/');if($item.PSIsContainer){$records.Add([ordered]@{kind='D';relative=$relative})}else{$records.Add([ordered]@{kind='F';relative=$relative;bytes=[int64]$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash})}};return (Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($records)))}
$movePlan=[Collections.Generic.List[object]]::new();$moveSources=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$addMove={param([string]$source,[string]$archiveRelative)
    if(-not(Test-Path -LiteralPath $source)){return}
    $sourceFull=[IO.Path]::GetFullPath($source);$sourceRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $sourceFull
    $isDirectory=Test-Path -LiteralPath $sourceFull -PathType Container;if($isDirectory){$null=Assert-SystemV7TreeNoReparse -RootPath $sourceFull -ContainmentRoot $project}else{$null=Assert-SystemV7PathNoReparse -Path $sourceFull -ContainmentRoot $project}
    if($moveSources.Add($sourceFull)){$movePlan.Add([pscustomobject]@{Source=$sourceFull;SourceRelative=$sourceRelative;ArchiveRelative=$archiveRelative;IsDirectory=$isDirectory;Fingerprint=(&$getMoveFingerprint $sourceFull $isDirectory)});$invalidations.Add([ordered]@{artifact=$sourceRelative;status='ARCHIVE_ON_COMMIT';scope=$Scope.Trim()})}
}
if($TargetStage -ceq 'K2B' -and -not $localizedK2B){
    &$addMove (Join-Path $project '_work\k3') 'k3'
}else{
    $fromIndex=[Array]::IndexOf([string[]]$actSequence,$firstAffectedAct);$affectedActs=@($actSequence[$fromIndex..($actSequence.Count-1)])
    foreach($act in $affectedActs){
        &$addMove (Join-Path $project "_work\k3\acts\$act") "k3/acts/$act"
        &$addMove (Join-Path $project "_work\k3\beats\$act") "k3/beats/$act"
        foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $project '_work\k3\packets') -File -Force -ErrorAction SilentlyContinue|Where-Object{$_.Name.StartsWith("$act.",[StringComparison]::Ordinal)})){&$addMove $file.FullName "k3/packets/$($file.Name)"}
        foreach($suffix in @('in.json','attest.json')){&$addMove (Join-Path $project "_work\k3\continuity\$act.$suffix") "k3/continuity/$act.$suffix"}
    }
    &$addMove (Join-Path $project '_work\k3\assembly') 'k3/assembly'
}
# Bundle, output i receipt runów są immutable provenance i pozostają pod
# stabilnymi ścieżkami, aby legalny QA carry-forward mógł do nich wrócić.
# Z aktywnego namespace znikają natomiast kanoniczne, już nieaktualne wyniki.
foreach($artifact in @('03-draft.md','04-raport-qa.md','04B-fact-check.md','05-FINAL-SCRIPT.md')){&$addMove (Join-Path $project $artifact) "canonical/$artifact"}
$owner=if($TargetStage -ceq 'K2B'){'ChatGPT'}else{'Claude'};$resultGate=if($TargetStage -ceq 'K2B'){'REOPEN_K2B_REQUIRED'}else{'REOPEN_K3_REQUIRED'}
$put={param($text,$name,$value)Set-SystemV7NarrativeMetaField -Text $text -Name $name -Value $value}
$nextAction=if($TargetStage -ceq 'K2B'){'Napraw wskazany zakres w K2B, przebuduj projekcje i ponownie przejdź przez K3.'}else{"Claude regeneruje od $firstAffectedAct; potem odtwórz downstream akty, atesty i wymagane dowody K4."}
$updated=&$put $meta 'CURRENT_STAGE' $TargetStage;$updated=&$put $updated 'STAGE_OWNER' $owner;$updated=&$put $updated 'OWNER_OVERRIDE' 'BRAK';$updated=&$put $updated 'OWNER_OVERRIDE_RECEIPT_PATH' 'BRAK';$updated=&$put $updated 'OWNER_OVERRIDE_RECEIPT_SHA256' 'BRAK';$updated=&$put $updated 'LAST_STATE_RECEIPT_PATH' 'BRAK';$updated=&$put $updated 'LAST_STATE_RECEIPT_SHA256' 'BRAK';$updated=&$put $updated 'LAST_GATE' $resultGate;$updated=&$put $updated 'LAST_UPDATED' ([DateTime]::UtcNow.ToString('yyyy-MM-dd'));$updated=&$put $updated 'NEXT_ACTION' $nextAction
$updated=&$put $updated 'K4_EDITOR_PROOF' 'BRAK';$updated=&$put $updated 'K4_VERIFY_PROOF' 'BRAK';$updated=&$put $updated 'K4_COLD_READER_PROOF' 'BRAK';$updated=&$put $updated 'K4_PROOF_SET_SHA256' 'BRAK';$updated=&$put $updated 'CONTINUITY_STATUS' 'STALE'
$firstAffectedIndex=[Array]::IndexOf([string[]]$actSequence,$firstAffectedAct);$lastAttestedAfterReopen=if(($TargetStage -ceq 'K2B' -and -not $localizedK2B) -or $firstAffectedIndex -le 0){'BRAK'}else{$actSequence[$firstAffectedIndex-1]}
$updated=&$put $updated 'K3_LAST_ATTESTED_ACT' $lastAttestedAfterReopen
if($TargetStage -ceq 'K2B' -and -not $localizedK2B){$updated=&$put $updated 'K3_PREFIX_SHA256' 'BRAK';$updated=&$put $updated 'NARRATIVE_ACT_SEQUENCE' 'BRAK'}
$handoffOwner='(?m)^- Właściciel:\s*.*$';$handoffTask='(?m)^- Zadanie:\s*.*$';if([regex]::Matches($updated,$handoffOwner).Count -ne 1 -or [regex]::Matches($updated,$handoffTask).Count -ne 1){throw 'HANDOFF_FIELDS_INVALID'};$updated=[regex]::Replace($updated,$handoffOwner,"- Właściciel: $owner",1);$updated=[regex]::Replace($updated,$handoffTask,"- Zadanie: REOPEN $route — $ReasonCode — $($Scope.Trim())",1)
$contextSha=Get-StateReceiptMetaContextSha256 -MetaText $updated;$created=[DateTime]::UtcNow.ToString('o');$record=New-SystemV7ReopenDecisionReceiptRecord -ProjectOriginSha256 $origin.Sha256 -InputMetaSha256 $metaSha -ResultMetaContextSha256 $contextSha -PreviousStateReceiptPath $previousPath -PreviousStateReceiptSha256 $previousSha -FromStage $from -TargetStage $TargetStage -PreviousLastGate (Get-SystemV7NarrativeMetaField -Text $meta -Name 'LAST_GATE') -ResultLastGate $resultGate -ReasonCode $ReasonCode -Scope $Scope.Trim() -ApprovalMode $approvalMode -ArtifactHashesBefore @($artifacts) -InvalidationManifest @($invalidations) -CreatedAtUtc $created
$intent=[string]$record.intent_sha256;$dir=Join-Path $project '_work\system\state-decisions';[IO.Directory]::CreateDirectory($dir)|Out-Null;$receiptPath=Join-Path $dir "reopen-$intent.json";$receiptCreated=$false
$receiptSha='';$relative=''
$archiveRoot=Join-Path $project "_work\system\reopen-archives\reopen-$intent";$moved=[Collections.Generic.List[object]]::new();$archiveCreated=$false;$metaWritten=$false;$metaBeforeBytes=[IO.File]::ReadAllBytes($metaPath)
try{
    if((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -cne $metaSha){throw 'REOPEN_COMPARE_AND_SWAP_CONFLICT'}
    if(Test-Path -LiteralPath $archiveRoot){throw 'REOPEN_ARCHIVE_COLLISION'}
    [IO.Directory]::CreateDirectory($archiveRoot)|Out-Null;$archiveCreated=$true
    foreach($entry in @($movePlan)){
        if(-not(Test-Path -LiteralPath $entry.Source)){throw "REOPEN_SOURCE_CHANGED: $($entry.SourceRelative)"};$liveIsDirectory=Test-Path -LiteralPath $entry.Source -PathType Container;if($liveIsDirectory -ne [bool]$entry.IsDirectory -or (&$getMoveFingerprint $entry.Source $liveIsDirectory) -cne [string]$entry.Fingerprint){throw "REOPEN_SOURCE_CHANGED: $($entry.SourceRelative)"}
        $target=Join-Path $archiveRoot ([string]$entry.ArchiveRelative);$targetParent=Split-Path -Parent $target;[IO.Directory]::CreateDirectory($targetParent)|Out-Null
        if(Test-Path -LiteralPath $target){throw "REOPEN_ARCHIVE_TARGET_EXISTS: $($entry.ArchiveRelative)"}
        if($entry.IsDirectory){[IO.Directory]::Move([string]$entry.Source,$target)}else{[IO.File]::Move([string]$entry.Source,$target)}
        $moved.Add([pscustomobject]@{Source=[string]$entry.Source;Target=$target;IsDirectory=[bool]$entry.IsDirectory})
    }
    Write-NewUtf8Json -Path $receiptPath -Value $record;$receiptCreated=$true
    $receiptSha=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash;$relative=([IO.Path]::GetRelativePath($project,$receiptPath)).Replace('\','/')
    $updated=&$put $updated 'LAST_STATE_RECEIPT_PATH' $relative;$updated=&$put $updated 'LAST_STATE_RECEIPT_SHA256' $receiptSha
    if((Get-StateReceiptMetaContextSha256 -MetaText $updated) -cne $contextSha){throw 'REOPEN_RESULT_META_CONTEXT_INTERNAL_MISMATCH'}
    Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text (ConvertTo-SystemV7LfText -Text $updated) -ExpectedCurrentSha256 $metaSha -HeldLockStream $lock|Out-Null
    $metaWritten=$true
    $liveMeta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$headState=Get-StateReceiptHeadState -ProjectPath $project -MetaText $liveMeta;if(-not $headState.Valid -or (Get-SystemV7NarrativeMetaField -Text $liveMeta -Name 'CURRENT_STAGE') -cne $TargetStage -or (Get-SystemV7NarrativeMetaField -Text $liveMeta -Name 'LAST_GATE') -cne $resultGate){throw "REOPEN_POSTVALIDATION_FAILED: $($headState.Errors -join '; ')"};foreach($entry in @($moved)){if((Test-Path -LiteralPath $entry.Source) -or -not(Test-Path -LiteralPath $entry.Target)){throw "REOPEN_ARCHIVE_POSTVALIDATION_FAILED: $($entry.Source)"}}
}catch{
    if($metaWritten){[IO.File]::WriteAllBytes($metaPath,$metaBeforeBytes)}
    if($receiptCreated -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){[IO.File]::Delete($receiptPath)}
    for($i=$moved.Count-1;$i -ge 0;$i--){$entry=$moved[$i];if(Test-Path -LiteralPath $entry.Target){[IO.Directory]::CreateDirectory((Split-Path -Parent $entry.Source))|Out-Null;if($entry.IsDirectory){[IO.Directory]::Move($entry.Target,$entry.Source)}else{[IO.File]::Move($entry.Target,$entry.Source)}}}
    if($archiveCreated -and (Test-Path -LiteralPath $archiveRoot -PathType Container)){$archiveRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $archiveRoot;if($archiveRelative -notmatch '^_work/system/reopen-archives/reopen-[A-F0-9]{64}$'){throw 'REOPEN_ARCHIVE_ROLLBACK_PATH_UNSAFE'};[IO.Directory]::Delete($archiveRoot,$true)}
    throw
}
[pscustomobject]@{Status='STAGE_REOPENED';FromStage=$from;TargetStage=$TargetStage;FromActId=$firstAffectedAct;ReasonCode=$ReasonCode;Scope=$Scope.Trim();ReceiptPath=$receiptPath;ReceiptSha256=$receiptSha;ArchivePath=$archiveRoot;ArchivedItems=$moved.Count;Invalidations=@($invalidations)}
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
