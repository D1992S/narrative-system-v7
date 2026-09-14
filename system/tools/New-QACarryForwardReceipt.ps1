[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$ImpactPath,
    [Parameter(Mandatory)][ValidateSet('EDITOR','VERIFY','COLD_READER')][string]$Lens,
    [Parameter(Mandatory)][string]$PriorProofPath,
    [Parameter(Mandatory)][string]$Justification,
    [string]$ImpactReviewRunId='NOT_REQUIRED'
)
$ErrorActionPreference='Stop';$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1');. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1');. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8;$origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$stage=Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE';if($stage -notin @('K4','K5')){throw "CARRYFORWARD_STAGE_INVALID: $stage"};if(-not(Test-SystemV7ConcreteText -Value $Justification)) {throw 'CARRYFORWARD_JUSTIFICATION_NOT_CONCRETE'}
$impactFull=[IO.Path]::GetFullPath($ImpactPath);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $impactFull
$impactState=Get-SystemV7QAImpactState -ProjectPath $project -ImpactPath $impactFull;if(-not $impactState.Valid){throw "QA_IMPACT_INVALID: $($impactState.Errors -join '; ')"};$impact=$impactState.Data
$currentDraft=Join-Path $project '03-draft.md';if(-not(Test-Path -LiteralPath $currentDraft -PathType Leaf) -or (Get-FileHash -LiteralPath $currentDraft -Algorithm SHA256).Hash -cne [string]$impact.new_draft_sha256){throw 'QA_IMPACT_NEW_DRAFT_NOT_CURRENT'}
$decision=[string]$impact.decisions.$Lens
$reviewReceiptRelative='BRAK';$reviewReceiptSha='BRAK'
if($decision -cne 'CARRYFORWARD_ALLOWED'){
    if($ImpactReviewRunId -ceq 'NOT_REQUIRED'){throw 'QA_IMPACT_REVIEW_REQUIRED'}
    $reviewReceipt=Join-Path $project "_work\narrative-runs\$ImpactReviewRunId\run-receipt.json";$review=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $reviewReceipt -ExpectedRunType 'QA_IMPACT_REVIEW'
    if(-not $review.Valid){throw "QA_IMPACT_REVIEW_PROOF_INVALID: $($review.Errors -join '; ')"}
    $reviewBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath (Join-Path $project ([string]$review.Data.input_manifest_relative));if(-not $reviewBundle.Valid){throw 'QA_IMPACT_REVIEW_BUNDLE_INVALID'}
    $reviewOutputState=Get-SystemV7QAImpactOutputState -ProjectPath $project -OutputPath (Join-Path $project ([string]$review.Data.output_relative)) -BundleData $reviewBundle.Data
    if(-not $reviewOutputState.Valid -or [string]$reviewOutputState.Impact.diff_sha256 -cne [string]$impact.diff_sha256 -or [string]$reviewOutputState.Decisions.$Lens -cne 'CARRYFORWARD_ALLOWED'){throw 'QA_IMPACT_REVIEW_DOES_NOT_ALLOW_LENS'}
    $reviewReceiptRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $reviewReceipt;$reviewReceiptSha=$review.Sha256
}
$priorFull=[IO.Path]::GetFullPath($PriorProofPath);$priorRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $priorFull
if(-not(Test-Path -LiteralPath $priorFull -PathType Leaf)){throw 'PRIOR_PROOF_MISSING'};$priorSha=(Get-FileHash -LiteralPath $priorFull -Algorithm SHA256).Hash
$priorData=Get-Content -LiteralPath $priorFull -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32
if([string]$priorData.schema -ceq 'SYSTEM_V7_NARRATIVE_RUN_RECEIPT_V1'){
    $priorState=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $priorFull -ExpectedRunType $Lens -ExpectedDraftSha256 ([string]$impact.old_draft_sha256)
    if(-not $priorState.Valid){throw "PRIOR_RUN_PROOF_INVALID: $($priorState.Errors -join '; ')"};$priorOutput=[string]$priorState.Data.output_sha256
    $priorOutputText=Get-Content -LiteralPath (Join-Path $project ([string]$priorState.Data.output_relative)) -Raw -Encoding UTF8
    if($priorOutputText -notmatch "(?m)^DRAFT_SHA256:\s*$([regex]::Escape([string]$impact.old_draft_sha256))\s*$"){throw 'PRIOR_PROOF_OLD_DRAFT_MISMATCH'}
    $priorBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath (Join-Path $project ([string]$priorState.Data.input_manifest_relative));$priorDependency=if($priorBundle.Valid){Get-SystemV7K4LensBundleDependencyFingerprintState -ProjectPath $project -Lens $Lens -BundleData $priorBundle.Data}else{$null};if($null -eq $priorDependency -or -not $priorDependency.Valid){throw 'PRIOR_RUN_DEPENDENCY_FINGERPRINT_INVALID'}
}elseif([string]$priorData.schema -ceq 'SYSTEM_V7_QA_CARRYFORWARD_V2'){
    $priorState=Get-SystemV7QACarryForwardState -ProjectPath $project -ReceiptPath $priorFull -ExpectedLens $Lens -ExpectedNewDraftSha256 ([string]$impact.old_draft_sha256) -Depth 1
    if(-not $priorState.Valid){throw "PRIOR_CARRYFORWARD_INVALID: $($priorState.Errors -join '; ')"};$priorOutput=[string]$priorState.Data.prior_output_sha256;$priorDependency=[pscustomobject]@{Valid=$true;Sha256=[string]$priorState.Data.lens_dependency_sha256}
}else{throw 'PRIOR_PROOF_SCHEMA_INVALID'}
$liveDependency=Get-SystemV7K4LensLiveDependencyFingerprintState -ProjectPath $project -Lens $Lens;if(-not $liveDependency.Valid){throw "LIVE_LENS_DEPENDENCY_FINGERPRINT_INVALID: $($liveDependency.Errors -join '; ')"};if([string]$liveDependency.Sha256 -cne [string]$priorDependency.Sha256){throw 'CARRYFORWARD_DEPENDENCY_CHANGED_RERUN_REQUIRED'}
$changeClass=if([string]$impact.change_class -ceq 'BYTE_IDENTICAL'){'TYPO_ONLY'}else{'STYLE_ONLY'}
$ruleId=if($changeClass -ceq 'TYPO_ONLY'){'MECHANICAL_NO_SEMANTIC_DELTA'}else{'IMPACT_REVIEW_NO_LENS_EFFECT'}
$record=New-SystemV7QACarryForwardRecord -ProjectOriginSha256 $origin.Sha256 -Lens $Lens -OldDraftSha256 ([string]$impact.old_draft_sha256) -NewDraftSha256 ([string]$impact.new_draft_sha256) -DiffSha256 ([string]$impact.diff_sha256) -ChangeClass $changeClass -ChangeScope ((@($impact.changed_block_ids) -join ',')|ForEach-Object{if($_){$_}else{'NO_BLOCK_CHANGE'}}) -PriorProofRelative $priorRelative -PriorProofSha256 $priorSha -PriorOutputSha256 $priorOutput -ImpactRelative (Get-SystemV7NarrativeRelativePath -Root $project -Path $impactFull) -ImpactSha256 (Get-FileHash -LiteralPath $impactFull -Algorithm SHA256).Hash -LensDependencySha256 ([string]$liveDependency.Sha256) -RuleId $ruleId -Justification $Justification -ImpactReviewRunId $ImpactReviewRunId -ImpactReviewReceiptRelative $reviewReceiptRelative -ImpactReviewReceiptSha256 $reviewReceiptSha
$dir=Join-Path $project '_work\k4\receipts';[IO.Directory]::CreateDirectory($dir)|Out-Null;$path=Join-Path $dir ("{0}.{1}.{2}.carryforward.json" -f $Lens,[string]$impact.new_draft_sha256,[guid]::NewGuid().ToString('N'))
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project;$created=$false
try{if((Get-FileHash -LiteralPath $impactFull -Algorithm SHA256).Hash -cne [string]$record.impact_sha256 -or (Get-FileHash -LiteralPath $priorFull -Algorithm SHA256).Hash -cne $priorSha -or (Get-FileHash -LiteralPath $currentDraft -Algorithm SHA256).Hash -cne [string]$impact.new_draft_sha256){throw 'CARRYFORWARD_INPUT_CHANGED'};Write-SystemV7NarrativeCreateNewJson -Path $path -Value $record|Out-Null;$created=$true;$state=Get-SystemV7QACarryForwardState -ProjectPath $project -ReceiptPath $path -ExpectedLens $Lens -ExpectedNewDraftSha256 ([string]$impact.new_draft_sha256);if(-not $state.Valid){throw "CARRYFORWARD_POSTVALIDATION_FAILED: $($state.Errors -join '; ')"}}catch{if($created -and (Test-Path -LiteralPath $path -PathType Leaf)){[IO.File]::Delete($path)};throw}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
[pscustomobject]@{Status='QA_CARRYFORWARD_CREATED';Lens=$Lens;Path=$path;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;NewDraftSha256=[string]$impact.new_draft_sha256;PriorProof=$priorFull}
