[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidatePattern('^VC-\d{3}$')][string]$VcId,
    [Parameter(Mandatory)][string]$AuthorText,
    [Parameter(Mandatory)][string]$ApprovalNote,
    [switch]$DawidApproved
)

$ErrorActionPreference='Stop'
if(-not $DawidApproved){throw 'DAWID_APPROVAL_REQUIRED'}
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null

$normalizedText=(ConvertTo-SystemV7LfText -Text $AuthorText).Trim()
if(-not(Test-SystemV7ConcreteText -Value $normalizedText) -or $normalizedText.Length -lt 12){throw 'AUTHOR_TEXT_NOT_CONCRETE'}
$null=Assert-SystemV7PlainSpokenText -Text $normalizedText -Context 'AUTHOR_TEXT_APPROVAL'
if(-not(Test-SystemV7ConcreteText -Value $ApprovalNote) -or $ApprovalNote.Trim().Length -lt 12){throw 'AUTHOR_TEXT_APPROVAL_NOTE_NOT_CONCRETE'}

$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
$created=$false;$receiptPath=$null
try{
    $metaPath=Join-Path $project 'meta.md';if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){throw 'AUTHOR_TEXT_META_MISSING'}
    $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
    if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'AUTHOR_TEXT_WRONG_WORKFLOW'}
    $stage=Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE';if($stage -notin @('K2','K2B')){throw "AUTHOR_TEXT_APPROVAL_REQUIRES_K2_OR_K2B: $stage"}
    $textSha=Get-SystemV7NarrativeSha256Text -Text ($normalizedText+"`n")
    $relative="_work/k2/author-text/$VcId-$textSha.json";$receiptPath=Join-Path $project $relative
    $record=[ordered]@{
        schema='SYSTEM_V7_AUTHOR_TEXT_APPROVAL_V1'
        workflow_revision=$script:SystemV7NarrativeWorkflowRevision
        actor='DAWID'
        attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'
        project_origin_sha256=$origin.Sha256
        reuse_policy='PROJECT_ONLY'
        vc_id=$VcId
        author_text=$normalizedText
        author_text_sha256=$textSha
        approval_note=$ApprovalNote.Trim()
        approved_at_utc=[DateTime]::UtcNow.ToString('o')
    }
    $record['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $record)
    if(Test-Path -LiteralPath $receiptPath -PathType Leaf){
        $existing=Get-SystemV7AuthorTextApprovalState -ProjectPath $project -ReceiptPath $receiptPath -ExpectedVcId $VcId -ExpectedAuthorText $normalizedText
        if(-not $existing.Valid){throw "AUTHOR_TEXT_EXISTING_RECEIPT_INVALID: $($existing.Errors -join '; ')"}
    }else{Write-SystemV7NarrativeCreateNewJson -Path $receiptPath -Value $record|Out-Null;$created=$true}
    $state=Get-SystemV7AuthorTextApprovalState -ProjectPath $project -ReceiptPath $receiptPath -ExpectedVcId $VcId -ExpectedAuthorText $normalizedText
    if(-not $state.Valid){throw "AUTHOR_TEXT_RECEIPT_POSTVALIDATION_FAILED: $($state.Errors -join '; ')"}
    [pscustomobject]@{Status='AUTHOR_TEXT_APPROVED_PROJECT_ONLY';VcId=$VcId;AuthorText=$normalizedText;AuthorTextSha256=$textSha;ReceiptPath=$state.Path;ReceiptRelative=$relative;ReceiptSha256=$state.Sha256;ReusePolicy='PROJECT_ONLY';Instruction='Wpisz zwrócone author_text, DAWID_APPROVED, ReceiptRelative i ReceiptSha256 do tego samego VC w 02.'}
}catch{if($created -and $receiptPath -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){[IO.File]::Delete($receiptPath)};throw}
finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
