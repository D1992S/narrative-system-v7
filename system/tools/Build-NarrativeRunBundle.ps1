[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateSet('GENERATE_ACT','CONSTRAINT_ATOMICITY_PREFLIGHT','BEAT_PREFLIGHT','CONTINUITY_ATTEST','EDITOR','VERIFY','COLD_READER','QA_IMPACT_REVIEW')][string]$RunType,
    [Parameter(Mandatory)][ValidatePattern('^[A-Z0-9][A-Z0-9._-]{7,80}$')][string]$RunId,
    [Parameter(Mandatory)][string[]]$Input
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$metaPath=Join-Path $project 'meta.md'
$meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$null=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'WORKFLOW_REVISION_NOT_NARRATIVE_V2'}
$supportedWrapper=switch($RunType){
    'GENERATE_ACT' {'Start-K3Act.ps1'}
    'CONSTRAINT_ATOMICITY_PREFLIGHT' {'Start-K3ConstraintPreflight.ps1'}
    'BEAT_PREFLIGHT' {'Start-K3BeatPreflight.ps1'}
    'CONTINUITY_ATTEST' {'Start-ContinuityAttest.ps1'}
    {$_ -in @('EDITOR','VERIFY','COLD_READER')} {'Start-K4Lenses.ps1'}
    'QA_IMPACT_REVIEW' {'Start-QAImpactReview.ps1'}
}
throw "GENERIC_NARRATIVE_BUNDLE_DISABLED: use $supportedWrapper so role-to-source bindings remain canonical"
$map=@{}
foreach($item in $Input){
    $split=$item.IndexOf('=')
    if($split -lt 1){throw "INPUT_ASSIGNMENT_INVALID: $item"}
    $role=$item.Substring(0,$split).Trim().ToUpperInvariant();$path=$item.Substring($split+1).Trim()
    if($map.ContainsKey($role)){throw "INPUT_ROLE_DUPLICATE: $role"}
    $map[$role]=$path
}
New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType $RunType -RunId $RunId -Inputs $map
