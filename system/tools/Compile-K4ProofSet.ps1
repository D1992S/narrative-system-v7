[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$EditorProofPath,
    [Parameter(Mandatory)][string]$VerifyProofPath,
    [Parameter(Mandatory)][string]$ColdReaderProofPath
)

$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')

Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
$proofCreated=$false;$report04Written=$false;$report04BWritten=$false;$metaWritten=$false
$proofSetPath=$null;$report04Path=Join-Path $project '04-raport-qa.md';$report04BPath=Join-Path $project '04B-fact-check.md';$metaPath=Join-Path $project 'meta.md'
$report04Before=if(Test-Path -LiteralPath $report04Path -PathType Leaf){[IO.File]::ReadAllBytes($report04Path)}else{$null}
$report04BBefore=if(Test-Path -LiteralPath $report04BPath -PathType Leaf){[IO.File]::ReadAllBytes($report04BPath)}else{$null}
$metaBefore=$null
try{
    if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){throw 'K4_META_MISSING'}
    $metaBefore=[IO.File]::ReadAllBytes($metaPath);$metaSha=Get-Sha256HexFromBytes -Bytes $metaBefore;$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
    if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'COMPILE_K4_WRONG_WORKFLOW'}
    if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K4'){throw 'COMPILE_K4_REQUIRES_STAGE_K4'}
    if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CONTINUITY_STATUS') -cne 'COMPLETE'){throw 'COMPILE_K4_CONTINUITY_INCOMPLETE'}
    $draftPath=Join-Path $project '03-draft.md';if(-not(Test-Path -LiteralPath $draftPath -PathType Leaf)){throw 'K4_DRAFT_MISSING'};$draftSha=(Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash
    $chain=Get-SystemV7K4ContinuityChainState -ProjectPath $project -DraftSha256 $draftSha;if(-not $chain.Valid){throw "K4_CONTINUITY_CHAIN_INVALID: $($chain.Errors -join '; ')"}

    $proofs=[ordered]@{};$taskIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($item in @(@('EDITOR',$EditorProofPath),@('VERIFY',$VerifyProofPath),@('COLD_READER',$ColdReaderProofPath))){
        $lens=[string]$item[0];$path=[IO.Path]::GetFullPath([string]$item[1]);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $path
        $resolution=Get-SystemV7K4LensProofResolutionState -ProjectPath $project -Lens $lens -ProofPath $path -DraftSha256 $draftSha
        if(-not $resolution.Valid){throw "K4_PROOF_INVALID: $lens/$($resolution.Errors -join '; ')"}
        if(-not $taskIds.Add([string]$resolution.TaskId)){throw 'K4_TASK_ID_COLLISION'}
        $proofs[$lens]=$resolution
    }

    $proofCore=[ordered]@{
        schema='K4_PROOF_SET_V2';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_origin_sha256=$origin.Sha256;draft_sha256=$draftSha;continuity_chain_sha256=$chain.Sha256
        editor=[ordered]@{proof_kind=$proofs.EDITOR.Kind;proof_relative=$proofs.EDITOR.Relative;proof_sha256=$proofs.EDITOR.Sha256;output_sha256=$proofs.EDITOR.OutputSha256}
        verify=[ordered]@{proof_kind=$proofs.VERIFY.Kind;proof_relative=$proofs.VERIFY.Relative;proof_sha256=$proofs.VERIFY.Sha256;output_sha256=$proofs.VERIFY.OutputSha256}
        cold_reader=[ordered]@{proof_kind=$proofs.COLD_READER.Kind;proof_relative=$proofs.COLD_READER.Relative;proof_sha256=$proofs.COLD_READER.Sha256;output_sha256=$proofs.COLD_READER.OutputSha256}
        status='PASS'
    }
    $proofSetSha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $proofCore)
    $proofSet=[ordered]@{};foreach($key in $proofCore.Keys){$proofSet[$key]=$proofCore[$key]};$proofSet['proof_set_sha256']=$proofSetSha
    $proofDir=Join-Path $project '_work\k4\proof-sets';[IO.Directory]::CreateDirectory($proofDir)|Out-Null;$proofSetPath=Join-Path $proofDir "$proofSetSha.json"

    $report04=(ConvertTo-SystemV7LfText -Text @"
# 04 — RAPORT GLOBAL QA: EDITOR + COLD READER

AKTUALNY_WERDYKT: PASS
DRAFT_SHA256: $draftSha
K4_QA_SCHEMA: THREE_LENS_QA_V1
EDITOR_PROOF: $($proofs.EDITOR.Relative)
EDITOR_PROOF_KIND: $($proofs.EDITOR.Kind)
COLD_READER_PROOF: $($proofs.COLD_READER.Relative)
COLD_READER_PROOF_KIND: $($proofs.COLD_READER.Kind)
K4_PROOF_SET_SHA256: $proofSetSha

## EDITOR — perspektywa narracyjna

$($proofs.EDITOR.Report.Trim())

## COLD READER — ślepa perspektywa widza

$($proofs.COLD_READER.Report.Trim())

## Zasada korekt

K4 nie zmienia 03. Korekta wymaga formalnego reopen do K3 albo K2B.
"@)
    $report04B=(ConvertTo-SystemV7LfText -Text @"
# 04B — NIEZALEŻNY FACT-CHECK CHATGPT VERIFY

AKTUALNY_WERDYKT: PASS
DRAFT_SHA256: $draftSha
K4_QA_SCHEMA: THREE_LENS_QA_V1
VERIFY_PROOF: $($proofs.VERIFY.Relative)
VERIFY_PROOF_KIND: $($proofs.VERIFY.Kind)
K4_PROOF_SET_SHA256: $proofSetSha

## VERIFY — SOURCE_FIRST_K4

$($proofs.VERIFY.Report.Trim())
"@)

    if((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -cne $metaSha -or (Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash -cne $draftSha -or (Get-FileHash -LiteralPath $chain.Path -Algorithm SHA256).Hash -cne $chain.Sha256){throw 'K4_COMPILE_INPUT_CHANGED'}
    foreach($lens in @('EDITOR','VERIFY','COLD_READER')){if((Get-FileHash -LiteralPath $proofs[$lens].Path -Algorithm SHA256).Hash -cne [string]$proofs[$lens].Sha256){throw "K4_PROOF_CHANGED: $lens"}}

    if(Test-Path -LiteralPath $proofSetPath -PathType Leaf){
        $existing=Get-Content -LiteralPath $proofSetPath -Raw -Encoding UTF8
        if((ConvertTo-SystemV7LfText -Text $existing) -cne (ConvertTo-SystemV7CanonicalJson -Value $proofSet)){throw 'K4_PROOF_SET_COLLISION'}
    }else{Write-SystemV7NarrativeCreateNewJson -Path $proofSetPath -Value $proofSet|Out-Null;$proofCreated=$true}
    Write-SystemV7NarrativeAtomicText -Path $report04Path -Text $report04|Out-Null;$report04Written=$true
    Write-SystemV7NarrativeAtomicText -Path $report04BPath -Text $report04B|Out-Null;$report04BWritten=$true
    $updated=Set-SystemV7NarrativeMetaField -Text $meta -Name 'K4_EDITOR_PROOF' -Value $proofs.EDITOR.Relative
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_VERIFY_PROOF' -Value $proofs.VERIFY.Relative
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_COLD_READER_PROOF' -Value $proofs.COLD_READER.Relative
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_PROOF_SET_SHA256' -Value $proofSetSha
    Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text (ConvertTo-SystemV7LfText -Text $updated) -ExpectedCurrentSha256 $metaSha -HeldLockStream $lock|Out-Null;$metaWritten=$true

    $state=Get-SystemV7K4ProofSetState -ProjectPath $project -ProofSetSha256 $proofSetSha -ExpectedDraftSha256 $draftSha
    if(-not $state.Valid){throw "K4_PROOF_SET_POSTVALIDATION_FAILED: $($state.Errors -join '; ')"}
    if((Get-FileHash -LiteralPath $report04Path -Algorithm SHA256).Hash -cne (Get-SystemV7NarrativeSha256Text -Text $report04) -or (Get-FileHash -LiteralPath $report04BPath -Algorithm SHA256).Hash -cne (Get-SystemV7NarrativeSha256Text -Text $report04B)){throw 'K4_REPORT_POSTVALIDATION_FAILED'}
    $liveMeta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;if((Get-SystemV7NarrativeMetaField -Text $liveMeta -Name 'K4_PROOF_SET_SHA256') -cne $proofSetSha){throw 'K4_META_POSTVALIDATION_FAILED'}
    [pscustomobject]@{Status='PASS';DraftSha256=$draftSha;ProofSetPath=$proofSetPath;ProofSetSha256=$proofSetSha;Report04=$report04Path;Report04B=$report04BPath}
}catch{
    if($metaWritten -and $null -ne $metaBefore){[IO.File]::WriteAllBytes($metaPath,$metaBefore)}
    if($report04Written){if($null -eq $report04Before){if(Test-Path -LiteralPath $report04Path -PathType Leaf){[IO.File]::Delete($report04Path)}}else{[IO.File]::WriteAllBytes($report04Path,$report04Before)}}
    if($report04BWritten){if($null -eq $report04BBefore){if(Test-Path -LiteralPath $report04BPath -PathType Leaf){[IO.File]::Delete($report04BPath)}}else{[IO.File]::WriteAllBytes($report04BPath,$report04BBefore)}}
    if($proofCreated -and $proofSetPath -and (Test-Path -LiteralPath $proofSetPath -PathType Leaf)){[IO.File]::Delete($proofSetPath)}
    throw
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
