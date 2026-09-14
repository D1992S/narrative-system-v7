param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$SourceProjectPath,
    [Parameter(Mandatory)][string]$ExactText,
    [Parameter(Mandatory)][string]$FixtureRoot
)
$ErrorActionPreference='Stop'
$systemRoot=[IO.Path]::GetFullPath($SystemRoot);$project=[IO.Path]::GetFullPath($ProjectPath);$profile=[IO.Path]::GetFullPath($ProfilePath)
$tools=Join-Path $systemRoot 'tools';[IO.Directory]::CreateDirectory($FixtureRoot)|Out-Null
. (Join-Path $tools 'Project-Origin.ps1')
. (Join-Path $tools 'Integrity-Receipts.ps1')
. (Join-Path $tools 'Narrative-V2.ps1')

function Write-Lf([string]$Path,[string]$Text){
    $value=ConvertTo-SystemV7LfText -Text $Text;if(-not $value.EndsWith("`n")){$value+="`n"}
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null
    [IO.File]::WriteAllText($Path,$value,[Text.UTF8Encoding]::new($false))
}

$validator=Join-Path $tools 'Validate-NarrativeV2Project.ps1'
$baselineProfile=Get-SystemV7VoiceProfileState -ProfilePath $profile
if(-not $baselineProfile.Valid){throw "PREFIX_BASELINE_PROFILE_INVALID: $($baselineProfile.Errors -join '; ')"}
$baseline=& $validator -ProjectPath $project -NoExit
$baselineRelevant=@($baseline.ErrorDetails|Where-Object{$_ -match 'VOICE_PROFILE|K3_PREFIX'})
if($baselineRelevant.Count -gt 0){throw "PREFIX_BASELINE_ALREADY_INVALID: $($baselineRelevant -join '; ')"}

$oldBytes=[IO.File]::ReadAllBytes($profile);$mutantState=$null;$mutated=$null;$restored=$null
try{
    $revision=$baselineProfile.Revision
    Write-Lf -Path $profile -Text @"
# Profil testowy po legalnej zmianie

VOICE_PROFILE_SCHEMA: SYSTEM_V7_VOICE_PROFILE_V1
VOICE_PROFILE_REVISION: $revision
STATUS: CANDIDATE
APPROVED_BY: BRAK
APPROVAL_RECEIPT_PATH: BRAK
APPROVAL_RECEIPT_SHA256: BRAK
RULES_SHA256: PENDING
EXEMPLAR_REGISTRY_SHA256: PENDING
EXEMPLARS_SHA256: PENDING

## VOICE RULES

Pisz jasno, konkretnie i po zmianie reguły zachowaj ten sam identyfikator rewizji wyłącznie w teście stale.

## VOICE EXEMPLARS

BRAK
"@
    $specPath=Join-Path $FixtureRoot 'mutant-profile-spec.json'
    $spec=[ordered]@{schema='VOICE_EXEMPLAR_APPROVAL_INPUT_V1';voice_profile_revision=$revision;exemplars=@([ordered]@{exemplar_id='EX-001';project_name=(Split-Path $SourceProjectPath -Leaf);artifact_path=(Join-Path $SourceProjectPath '05-FINAL-SCRIPT.md');exact_text=$ExactText;demonstrates=@('STRONG_OPENING','SCENE','UNCERTAINTY','KNOWLEDGE_BOUNDARY','VIEWER_CONTACT','TRANSITION','PAYOFF')})}
    Write-Lf -Path $specPath -Text (ConvertTo-SystemV7CanonicalJson -Value $spec)
    $null=& (Join-Path $tools 'Approve-VoiceProfile.ps1') -ProfilePath $profile -ExemplarSpecPath $specPath -ApprovalNote 'Legalny mutant tej samej rewizji wyłącznie do regresji prefix stale.' -DawidApproved
    $mutantState=Get-SystemV7VoiceProfileState -ProfilePath $profile
    if(-not $mutantState.Valid){throw "PREFIX_MUTANT_PROFILE_INVALID: $($mutantState.Errors -join '; ')"}
    $mutated=& $validator -ProjectPath $project -NoExit
}finally{
    [IO.File]::WriteAllBytes($profile,$oldBytes)
}
$restoreProfile=Get-SystemV7VoiceProfileState -ProfilePath $profile
$restored=& $validator -ProjectPath $project -NoExit
$mutatedRelevant=@($mutated.ErrorDetails|Where-Object{$_ -match 'VOICE_PROFILE|K3_PREFIX'})
$restoredRelevant=@($restored.ErrorDetails|Where-Object{$_ -match 'VOICE_PROFILE|K3_PREFIX'})
[pscustomobject]@{
    BaselineProfileValid=$baselineProfile.Valid
    BaselineRelevantErrors=$baselineRelevant
    MutantProfileValid=$mutantState.Valid
    MutatedRelevantErrors=$mutatedRelevant
    StaleDetected=@($mutatedRelevant|Where-Object{$_ -ceq 'K3_PREFIX_LIVE_VOICE_PROFILE_STALE'}).Count -eq 1
    RestoreProfileValid=$restoreProfile.Valid
    RestoredRelevantErrors=$restoredRelevant
    RestoreMatchesBaseline=(($restoredRelevant -join "`n") -ceq ($baselineRelevant -join "`n"))
}
