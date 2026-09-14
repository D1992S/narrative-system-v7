param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$FixtureRoot
)
$ErrorActionPreference='Stop'
$systemRoot=[IO.Path]::GetFullPath($SystemRoot);$fixtureRoot=[IO.Path]::GetFullPath($FixtureRoot);$tools=Join-Path $systemRoot 'tools'
. (Join-Path $tools 'Narrative-V2.ps1')

function Set-Meta([string]$Project,[hashtable]$Values){
    $path=Join-Path $Project 'meta.md';$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach($key in $Values.Keys){$text=Set-SystemV7NarrativeMetaField -Text $text -Name $key -Value ([string]$Values[$key])}
    [IO.File]::WriteAllText($path,(ConvertTo-SystemV7LfText -Text $text),[Text.UTF8Encoding]::new($false))
}
function Get-DurationErrors([string]$Project){
    $validation=& (Join-Path $tools 'Validate-NarrativeV2Project.ps1') -ProjectPath $Project -NoExit
    @($validation.ErrorDetails|Where-Object{$_ -like 'DURATION_POLICY_*' -or $_ -like 'META_FOUNDATION_DURATION_*'})
}

[IO.Directory]::CreateDirectory($fixtureRoot)|Out-Null
$project=Join-Path $fixtureRoot 'PROJECT-DURATION'
& (Join-Path $tools 'New-Project.ps1') -ProjectName 'PROJECT-DURATION' -DestinationRoot $fixtureRoot -TargetDurationMode guide -NarrativeV2Pilot|Out-Null
[IO.File]::WriteAllText((Join-Path $project 'sources\source.md'),'Syntetyczny materiał wejściowy do legalnego przejścia W0.',[Text.UTF8Encoding]::new($false))
Set-Meta -Project $project -Values @{W0_DECISION='GO';W0_CONDITIONS='BRAK';W0_CONDITION_STATUS='NOT_APPLICABLE';LAST_GATE='PROJECT_INITIALIZED'}
$advance=& (Join-Path $tools 'Advance-Stage.ps1') -ProjectPath $project -Apply -DawidApproved
$metaPath=Join-Path $project 'meta.md';$foundationPath=Join-Path $project '00-fundament-projektu.md'
$initialMeta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$initialFoundation=Get-Content -LiteralPath $foundationPath -Raw -Encoding UTF8
$newProjectModeNormalized=([regex]::Match($initialMeta,'(?m)^TARGET_DURATION_MODE:\s*(.*?)\s*$').Groups[1].Value.Trim() -ceq 'GUIDE') -and ([regex]::Match($initialFoundation,'(?m)^- TARGET_DURATION_MODE:\s*(.*?)\s*$').Groups[1].Value.Trim() -ceq 'GUIDE')
$beforeNoFlagMeta=[IO.File]::ReadAllBytes($metaPath);$beforeNoFlagFoundation=[IO.File]::ReadAllBytes($foundationPath);$noFlagFailed=$false
try{$null=& (Join-Path $tools 'Set-DurationPolicy.ps1') -ProjectPath $project -Mode HARD_MAX -TargetMinutes 12 -Reason 'Syntetyczny limit czasu zatwierdzony dla regresji.'}catch{$noFlagFailed=$_.Exception.Message -match '^DAWID_APPROVAL_REQUIRED$'}
$noFlagNoMutation=([Convert]::ToBase64String([IO.File]::ReadAllBytes($metaPath)) -ceq [Convert]::ToBase64String($beforeNoFlagMeta)) -and ([Convert]::ToBase64String([IO.File]::ReadAllBytes($foundationPath)) -ceq [Convert]::ToBase64String($beforeNoFlagFoundation))
$result=& (Join-Path $tools 'Set-DurationPolicy.ps1') -ProjectPath $project -Mode guide -TargetMinutes 12 -Reason 'Syntetyczny limit czasu zatwierdzony dla regresji.' -DawidApproved
$baselineErrors=Get-DurationErrors -Project $project
$metaBytes=[IO.File]::ReadAllBytes($metaPath);$foundationBytes=[IO.File]::ReadAllBytes($foundationPath);$receiptBytes=[IO.File]::ReadAllBytes($result.ReceiptPath)

$metaText=[Text.UTF8Encoding]::new($false,$true).GetString($metaBytes);$metaMutant=Set-SystemV7NarrativeMetaField -Text $metaText -Name 'TARGET_MINUTES' -Value '13';[IO.File]::WriteAllText($metaPath,$metaMutant,[Text.UTF8Encoding]::new($false))
$metaTamperErrors=Get-DurationErrors -Project $project
[IO.File]::WriteAllBytes($metaPath,$metaBytes)

$foundation=[Text.UTF8Encoding]::new($false,$true).GetString($foundationBytes);$foundationMutant=[regex]::Replace($foundation,'(?m)^- TARGET_MINUTES:\s*.*$','- TARGET_MINUTES: 13',1);if($foundationMutant -ceq $foundation){throw 'DURATION_FOUNDATION_TAMPER_PATTERN_MISSING'};[IO.File]::WriteAllText($foundationPath,$foundationMutant,[Text.UTF8Encoding]::new($false))
$foundationTamperErrors=Get-DurationErrors -Project $project
[IO.File]::WriteAllBytes($foundationPath,$foundationBytes)
$restoredErrors=Get-DurationErrors -Project $project

[pscustomobject]@{
    ProjectPath=$project
    AdvanceApplied=([string]$advance.Mode -ceq 'APPLIED' -and [string]$advance.ToStage -ceq 'K0')
    NewProjectModeNormalized=$newProjectModeNormalized
    NoFlagFailed=$noFlagFailed
    NoFlagNoMutation=$noFlagNoMutation
    PolicyStatus=([string]$result.Status)
    ModeNormalized=([string]$result.Mode -ceq 'GUIDE' -and [regex]::Match((Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8),'(?m)^TARGET_DURATION_MODE:\s*(.*?)\s*$').Groups[1].Value.Trim() -ceq 'GUIDE')
    ReceiptExists=(Test-Path -LiteralPath $result.ReceiptPath -PathType Leaf)
    ReceiptUnchanged=([Convert]::ToBase64String([IO.File]::ReadAllBytes($result.ReceiptPath)) -ceq [Convert]::ToBase64String($receiptBytes))
    BaselineDurationClean=(@($baselineErrors).Count -eq 0)
    MetaTamperRejected=(@($metaTamperErrors|Where-Object{$_ -ceq 'DURATION_POLICY_RECEIPT_CURRENT_POLICY_MISMATCH'}).Count -eq 1)
    FoundationTamperRejected=(@($foundationTamperErrors|Where-Object{$_ -ceq 'DURATION_POLICY_RECEIPT_FOUNDATION_STALE'}).Count -eq 1)
    RestoreDurationClean=(@($restoredErrors).Count -eq 0)
    RestoreExact=((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ceq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($metaBytes)) -and (Get-FileHash -LiteralPath $foundationPath -Algorithm SHA256).Hash -ceq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($foundationBytes)))
}
