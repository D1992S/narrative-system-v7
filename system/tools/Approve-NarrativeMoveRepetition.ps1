[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateLength(8,500)][string]$Reason,
    [switch]$DawidApproved
)

$ErrorActionPreference='Stop'
if(-not $DawidApproved){throw 'DAWID_APPROVAL_REQUIRED'}
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
try{
    $meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8
    $null=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
    if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -notin @('K3','K4')){throw 'MOVE_REPETITION_DECISION_STAGE_INVALID'}
    $state=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project
    if(-not $state.Valid){throw "MOVE_REPETITION_STATE_INVALID: $($state.Errors -join '; ')"}
    if(@($state.ReviewAlerts).Count -eq 0){throw 'MOVE_REPETITION_DECISION_NOT_REQUIRED'}
    if($state.GateReady){return [pscustomobject]@{Status='ALREADY_APPROVED';HistorySha256=$state.HistorySha256;ReceiptPath=$state.DecisionPath;ReceiptSha256=$state.DecisionSha256;ReviewAlerts=@($state.ReviewAlerts)}}
    $record=[ordered]@{
        schema='MOVE_REPETITION_DECISION_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_origin_sha256=$state.ProjectOriginSha256;history_sha256=$state.HistorySha256
        actor='DAWID';verdict='APPROVE_CONSCIOUS_REPETITION';reason=$Reason.Trim();repetitions=@($state.ReviewAlerts);created_at_utc=[DateTime]::UtcNow.ToString('o')
    }
    $path=[IO.Path]::GetFullPath($state.DecisionPath);$relative=[IO.Path]::GetRelativePath($project,$path).Replace('\','/')
    if($relative -notmatch '^_work/k3/continuity/move-repetition-decisions/decision-[A-F0-9]{64}\.json$'){throw 'MOVE_REPETITION_DECISION_PATH_UNSAFE'}
    if(Test-Path -LiteralPath $path){throw 'MOVE_REPETITION_DECISION_COLLISION'}
    Write-SystemV7NarrativeAtomicText -Path $path -Text (ConvertTo-SystemV7CanonicalJson -Value $record)|Out-Null
    $verified=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project
    if(-not $verified.GateReady){if(Test-Path -LiteralPath $path){[IO.File]::Delete($path)};throw "MOVE_REPETITION_DECISION_POSTVALIDATION_FAILED: $($verified.Errors -join '; ')"}
    [pscustomobject]@{Status='CONSCIOUS_REPETITION_APPROVED';HistorySha256=$verified.HistorySha256;ReceiptPath=$path;ReceiptSha256=$verified.DecisionSha256;ReviewAlerts=@($verified.ReviewAlerts)}
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
