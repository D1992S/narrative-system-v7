[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$EditorRunId,
    [Parameter(Mandatory)][string]$VerifyRunId,
    [Parameter(Mandatory)][string]$ColdReaderRunId
)

# Jedna ścieżka kompilacji dla świeżych runów i późniejszych carry-forward.
# Ten historyczny interfejs z RunId pozostaje dla ergonomii, ale deleguje do
# atomowego kompilatora K4_PROOF_SET_V2, aby nie utrzymywać dwóch kontraktów.
$projectFull = [IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $projectFull | Out-Null
$editorProof = Join-Path $projectFull "_work\narrative-runs\$EditorRunId\run-receipt.json"
$verifyProof = Join-Path $projectFull "_work\narrative-runs\$VerifyRunId\run-receipt.json"
$coldReaderProof = Join-Path $projectFull "_work\narrative-runs\$ColdReaderRunId\run-receipt.json"
$result = & (Join-Path $PSScriptRoot 'Compile-K4ProofSet.ps1') -ProjectPath $projectFull `
    -EditorProofPath $editorProof -VerifyProofPath $verifyProof -ColdReaderProofPath $coldReaderProof
$result
return

$ErrorActionPreference='Stop';$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1');. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1');. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
$metaPath=Join-Path $project 'meta.md';$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K4'){throw 'COMPILE_K4_REQUIRES_STAGE_K4'}
$draftPath=Join-Path $project '03-draft.md';$draftSha=(Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash
$proofs=[ordered]@{};$taskIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($pair in @(@('EDITOR',$EditorRunId),@('VERIFY',$VerifyRunId),@('COLD_READER',$ColdReaderRunId))){
    $lens=$pair[0];$runId=$pair[1];$receiptPath=Join-Path $project "_work\narrative-runs\$runId\run-receipt.json";$proof=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $receiptPath -ExpectedRunType $lens
    if(-not $proof.Valid){throw "K4_PROOF_INVALID: $lens/$($proof.Errors -join '; ')"};if(-not $taskIds.Add([string]$proof.Data.task_id)){throw 'K4_TASK_ID_COLLISION'}
    $outputPath=Join-Path $project ([string]$proof.Data.output_relative);$output=Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
    if($output -notmatch "(?m)^LENS:\s*$lens\s*$" -or $output -notmatch '(?m)^VERDICT:\s*(PASS|FAIL)\s*$' -or $output -notmatch "(?m)^DRAFT_SHA256:\s*$draftSha\s*$"){throw "K4_OUTPUT_HEADER_INVALID: $lens"}
    $verdict=[regex]::Match($output,'(?m)^VERDICT:\s*(PASS|FAIL)\s*$').Groups[1].Value
    $proofs[$lens]=[pscustomobject]@{ReceiptPath=$receiptPath;ReceiptSha256=$proof.Sha256;OutputPath=$outputPath;OutputSha256=[string]$proof.Data.output_sha256;Output=$output.Trim();Verdict=$verdict;RunId=$runId;TaskId=[string]$proof.Data.task_id}
}
$chainFile=@(Get-ChildItem -LiteralPath (Join-Path $project '_work\k4\inputs') -Filter "continuity-chain-$draftSha.json" -File)
if($chainFile.Count -ne 1){throw 'K4_CONTINUITY_CHAIN_INPUT_MISSING'};$chainSha=(Get-FileHash -LiteralPath $chainFile[0].FullName -Algorithm SHA256).Hash
$proofCore=[ordered]@{schema='K4_PROOF_SET_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_origin_sha256=$origin.Sha256;draft_sha256=$draftSha;continuity_chain_sha256=$chainSha;editor=[ordered]@{run_id=$proofs.EDITOR.RunId;receipt_sha256=$proofs.EDITOR.ReceiptSha256;output_sha256=$proofs.EDITOR.OutputSha256};verify=[ordered]@{run_id=$proofs.VERIFY.RunId;receipt_sha256=$proofs.VERIFY.ReceiptSha256;output_sha256=$proofs.VERIFY.OutputSha256};cold_reader=[ordered]@{run_id=$proofs.COLD_READER.RunId;receipt_sha256=$proofs.COLD_READER.ReceiptSha256;output_sha256=$proofs.COLD_READER.OutputSha256};status=if(@($proofs.Values|Where-Object{$_.Verdict -cne 'PASS'}).Count -eq 0){'PASS'}else{'FAIL'}}
$proofSetSha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $proofCore);$proofSet=[ordered]@{};foreach($k in $proofCore.Keys){$proofSet[$k]=$proofCore[$k]};$proofSet['proof_set_sha256']=$proofSetSha
$report04=@"
# 04 — RAPORT GLOBAL QA: EDITOR + COLD READER

AKTUALNY_WERDYKT: $($proofCore.status)
DRAFT_SHA256: $draftSha
K4_QA_SCHEMA: THREE_LENS_QA_V1
EDITOR_RUN_RECEIPT: $(Get-SystemV7NarrativeRelativePath -Root $project -Path $proofs.EDITOR.ReceiptPath)
EDITOR_PROOF_STATUS: $($proofs.EDITOR.Verdict)
COLD_READER_RUN_RECEIPT: $(Get-SystemV7NarrativeRelativePath -Root $project -Path $proofs.COLD_READER.ReceiptPath)
COLD_READER_PROOF_STATUS: $($proofs.COLD_READER.Verdict)
K4_PROOF_SET_SHA256: $proofSetSha

## EDITOR — perspektywa narracyjna

$($proofs.EDITOR.Output)

## COLD READER — ślepa perspektywa widza

$($proofs.COLD_READER.Output)

## Zasada korekt

K4 nie zmienia 03. Korekta wymaga formalnego reopen do K3 albo K2B.
"@
$report04b=@"
# 04B — NIEZALEŻNY FACT-CHECK CHATGPT VERIFY

AKTUALNY_WERDYKT: $($proofs.VERIFY.Verdict)
DRAFT_SHA256: $draftSha
K4_QA_SCHEMA: THREE_LENS_QA_V1
VERIFY_RUN_RECEIPT: $(Get-SystemV7NarrativeRelativePath -Root $project -Path $proofs.VERIFY.ReceiptPath)
VERIFY_PROOF_STATUS: $($proofs.VERIFY.Verdict)
K4_PROOF_SET_SHA256: $proofSetSha

## VERIFY — SOURCE_FIRST_K4

$($proofs.VERIFY.Output)
"@
$proofDir=Join-Path $project '_work\k4\proof-sets';[IO.Directory]::CreateDirectory($proofDir)|Out-Null;$proofSetPath=Join-Path $proofDir "$proofSetSha.json"
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
try{
    if(-not(Test-Path -LiteralPath $proofSetPath)){Write-SystemV7NarrativeCreateNewJson -Path $proofSetPath -Value $proofSet|Out-Null}
    Write-SystemV7NarrativeAtomicText -Path (Join-Path $project '04-raport-qa.md') -Text $report04|Out-Null;Write-SystemV7NarrativeAtomicText -Path (Join-Path $project '04B-fact-check.md') -Text $report04b|Out-Null
    $updated=Set-SystemV7NarrativeMetaField -Text $meta -Name 'K4_EDITOR_PROOF' -Value (Get-SystemV7NarrativeRelativePath -Root $project -Path $proofs.EDITOR.ReceiptPath)
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_VERIFY_PROOF' -Value (Get-SystemV7NarrativeRelativePath -Root $project -Path $proofs.VERIFY.ReceiptPath)
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_COLD_READER_PROOF' -Value (Get-SystemV7NarrativeRelativePath -Root $project -Path $proofs.COLD_READER.ReceiptPath)
    $updated=Set-SystemV7NarrativeMetaField -Text $updated -Name 'K4_PROOF_SET_SHA256' -Value $proofSetSha;Write-SystemV7NarrativeAtomicText -Path $metaPath -Text $updated|Out-Null
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
[pscustomobject]@{Status=$proofCore.status;DraftSha256=$draftSha;ProofSetPath=$proofSetPath;ProofSetSha256=$proofSetSha;Report04=Join-Path $project '04-raport-qa.md';Report04B=Join-Path $project '04B-fact-check.md'}
