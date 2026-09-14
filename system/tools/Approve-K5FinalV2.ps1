[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ApprovalNote,
    [switch]$DawidApproved
)

$ErrorActionPreference='Stop'
if(-not $DawidApproved){throw 'DAWID_APPROVAL_REQUIRED'}
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
$receiptCreated=$false
try{

$metaPath=Join-Path $project 'meta.md';$draftPath=Join-Path $project '03-draft.md';$qaPath=Join-Path $project '04-raport-qa.md';$factPath=Join-Path $project '04B-fact-check.md';$finalPath=Join-Path $project '05-FINAL-SCRIPT.md'
foreach($path in @($metaPath,$draftPath,$qaPath,$factPath,$finalPath)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "K5_REQUIRED_FILE_MISSING: $path"};Assert-SystemV7PathNoReparse -Path $path -ContainmentRoot $project|Out-Null}
$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'K5_V2_WRONG_WORKFLOW'}
if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K5'){throw 'K5_APPROVAL_REQUIRES_STAGE_K5'}
if(-not(Test-SystemV7ConcreteText $ApprovalNote) -or $ApprovalNote.Trim().Length -lt 12){throw 'K5_APPROVAL_NOTE_NOT_CONCRETE'}
if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CONTINUITY_STATUS') -cne 'COMPLETE'){throw 'K5_CONTINUITY_NOT_COMPLETE'}

$draftText=Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
try{$finalBytes=[IO.File]::ReadAllBytes($finalPath);$finalText=[Text.UTF8Encoding]::new($false,$true).GetString($finalBytes)}catch{throw 'K5_FINAL_NOT_STRICT_UTF8'}
$getFinalField={param($name)$matches=@([regex]::Matches($finalText,"(?m)^$([regex]::Escape($name)):\s*(.*?)\s*$"));if($matches.Count -ne 1){throw "K5_FINAL_FIELD_COUNT_INVALID: $name"};$matches[0].Groups[1].Value.Trim()}
$draftSha=(Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash;$qaSha=(Get-FileHash -LiteralPath $qaPath -Algorithm SHA256).Hash;$factSha=(Get-FileHash -LiteralPath $factPath -Algorithm SHA256).Hash
$draftRevisionMatch=[regex]::Match($draftText,'(?m)^CONTENT_REVISION:\s*(\S+)\s*$');if(-not $draftRevisionMatch.Success){throw 'K5_DRAFT_REVISION_MISSING'}
foreach($binding in @(@('SOURCE_DRAFT_REVISION',$draftRevisionMatch.Groups[1].Value),@('SOURCE_DRAFT_SHA256',$draftSha),@('SOURCE_QA_SHA256',$qaSha),@('SOURCE_FACTCHECK_SHA256',$factSha))){if((&$getFinalField $binding[0]) -cne $binding[1]){throw "K5_SOURCE_BINDING_MISMATCH: $($binding[0])"}}
if((&$getFinalField 'STATUS') -cne 'ZATWIERDZONY'){throw 'K5_STATUS_NOT_APPROVED'}

$sections=@([regex]::Matches($finalText,'(?ms)^## NARRACJA DO NAGRANIA\n(?<body>.*)\z'));if($sections.Count -ne 1){throw 'K5_NARRATION_SECTION_MISSING_OR_NONCANONICAL'}
$finalNarration=$sections[0].Groups['body'].Value
if(-not(Test-SystemV7ConcreteText $finalNarration) -or $finalNarration -match '^\[WYŁĄCZNIE FINALNY TEKST'){throw 'K5_FINAL_NARRATION_EMPTY'}
if($finalNarration -match '(?im)^\s*#{1,6}\s|<!--|-->|#P-\d{3,}|\bBLOCK-(?:ACT-)?\d|^\s*\|.*\|\s*$|^(?:STATUS|SOURCE_[A-Z_]+|FINAL_WORD_COUNT|REAL_WPM|ESTIMATED_DURATION|K4_PROOF_SET_SHA256|CONTINUITY_\w+):'){throw 'K5_FINAL_TECHNICAL_RESIDUE'}
$null=Assert-SystemV7PlainSpokenText -Text $finalNarration -Context 'K5_FINAL'
$draftNarration=Get-SystemV7CleanNarrationFromDraft -DraftText $draftText
$finalNarrationBytes=[Text.UTF8Encoding]::new($false).GetBytes($finalNarration);$draftNarrationBytes=[Text.UTF8Encoding]::new($false).GetBytes($draftNarration)
if([Convert]::ToBase64String($finalNarrationBytes) -cne [Convert]::ToBase64String($draftNarrationBytes)){throw 'K5_ANY_TEXT_CHANGE_REQUIRES_REOPEN_K3'};$changeClass='BYTE_IDENTICAL'

$proofSha=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K4_PROOF_SET_SHA256';$proof=Get-SystemV7K4ProofSetState -ProjectPath $project -ProofSetSha256 $proofSha -ExpectedDraftSha256 $draftSha
if(-not $proof.Valid){throw "K5_K4_PROOF_INVALID: $($proof.Errors -join '; ')"}
if((&$getFinalField 'K4_PROOF_SET_SHA256') -cne $proofSha){throw 'K5_PROOF_SET_HEADER_MISMATCH'}
if((&$getFinalField 'CONTINUITY_CHAIN_SHA256') -cne [string]$proof.Data.continuity_chain_sha256 -or (&$getFinalField 'CONTINUITY_STATUS') -cne 'PASS'){throw 'K5_CONTINUITY_HEADER_MISMATCH'}

$mode=Get-SystemV7NarrativeMetaField -Text $meta -Name 'TARGET_DURATION_MODE';$minutes=[int](Get-SystemV7NarrativeMetaField -Text $meta -Name 'TARGET_MINUTES');$wpm=[int](Get-SystemV7NarrativeMetaField -Text $meta -Name 'REAL_WPM')
$duration=Get-SystemV7DurationState -Narration $finalNarration -TargetMinutes $minutes -RealWpm $wpm -Mode $mode
if(-not $duration.Pass){throw "K5_HARD_MAX_EXCEEDED: $($duration.WordCount)>$($duration.MaximumWords)"}
if([int](&$getFinalField 'FINAL_WORD_COUNT') -ne $duration.WordCount -or [int](&$getFinalField 'REAL_WPM') -ne $wpm){throw 'K5_FINAL_MEASUREMENT_HEADER_MISMATCH'}
$declaredDuration=&$getFinalField 'ESTIMATED_DURATION';if($declaredDuration -notmatch '^([0-9]+(?:[.,][0-9]+)?)\s*(?:min)?$' -or [math]::Abs(([double]($matches[1].Replace(',','.')))-[double]$duration.EstimatedMinutes) -gt 0.01){throw 'K5_ESTIMATED_DURATION_HEADER_MISMATCH'}

$inputHashes=[ordered]@{meta=(Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash;draft=$draftSha;qa=$qaSha;fact=$factSha;final=(Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash;proof=$proof.FileSha256}
$createdAt=[DateTime]::UtcNow.ToString('o')
$record=New-SystemV7K5ApprovalV2Record -ProjectOriginSha256 $origin.Sha256 -FinalSha256 $inputHashes.final -DraftSha256 $draftSha -QaSha256 $qaSha -FactCheckSha256 $factSha -K4ProofSetSha256 $proofSha -K4ProofSetFileSha256 $proof.FileSha256 -ContinuityChainSha256 ([string]$proof.Data.continuity_chain_sha256) -DurationMode $mode -FinalWordCount $duration.WordCount -MaximumWords $duration.MaximumWords -ChangeClass $changeClass -ApprovalNote $ApprovalNote.Trim() -CreatedAtUtc $createdAt
$directory=Join-Path $project '_work\K5';[IO.Directory]::CreateDirectory($directory)|Out-Null;$receiptPath=Join-Path $directory "v2-approval-$($inputHashes.final).json"
    foreach($pair in $inputHashes.GetEnumerator()){
        $live=if($pair.Key -ceq 'meta'){(Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash}elseif($pair.Key -ceq 'draft'){(Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash}elseif($pair.Key -ceq 'qa'){(Get-FileHash -LiteralPath $qaPath -Algorithm SHA256).Hash}elseif($pair.Key -ceq 'fact'){(Get-FileHash -LiteralPath $factPath -Algorithm SHA256).Hash}elseif($pair.Key -ceq 'final'){(Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash}else{(Get-FileHash -LiteralPath $proof.Path -Algorithm SHA256).Hash}
        if($live -cne [string]$pair.Value){throw "K5_INPUT_CHANGED_DURING_APPROVAL: $($pair.Key)"}
    }
    if(Test-Path -LiteralPath $receiptPath -PathType Leaf){$existing=Get-SystemV7K5ApprovalV2State -ProjectPath $project;if(-not $existing.Valid){throw "K5_EXISTING_RECEIPT_INVALID: $($existing.Errors -join '; ')"}}
    else{Write-SystemV7NarrativeCreateNewJson -Path $receiptPath -Value $record|Out-Null;$receiptCreated=$true}
$state=Get-SystemV7K5ApprovalV2State -ProjectPath $project;if(-not $state.Valid){throw "K5_APPROVAL_RECEIPT_INVALID: $($state.Errors -join '; ')"}
foreach($pair in $inputHashes.GetEnumerator()){$live=if($pair.Key -ceq 'meta'){(Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash}elseif($pair.Key -ceq 'draft'){(Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash}elseif($pair.Key -ceq 'qa'){(Get-FileHash -LiteralPath $qaPath -Algorithm SHA256).Hash}elseif($pair.Key -ceq 'fact'){(Get-FileHash -LiteralPath $factPath -Algorithm SHA256).Hash}elseif($pair.Key -ceq 'final'){(Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash}else{(Get-FileHash -LiteralPath $proof.Path -Algorithm SHA256).Hash};if($live -cne [string]$pair.Value){throw "K5_INPUT_CHANGED_DURING_APPROVAL: $($pair.Key)"}}
[pscustomobject]@{Status='K5_APPROVAL_V2_CREATED';ReceiptPath=$state.Path;ReceiptSha256=$state.Sha256;FinalSha256=$inputHashes.final;ChangeClass=$changeClass;WordCount=$duration.WordCount;DurationMode=$mode}
}catch{if($receiptCreated -and $receiptPath -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){[IO.File]::Delete($receiptPath)};throw}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
