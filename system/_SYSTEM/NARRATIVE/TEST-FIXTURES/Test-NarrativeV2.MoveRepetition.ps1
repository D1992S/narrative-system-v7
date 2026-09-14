param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$FixtureRoot
)
$ErrorActionPreference='Stop'
$systemRoot=[IO.Path]::GetFullPath($SystemRoot);$fixtureRoot=[IO.Path]::GetFullPath($FixtureRoot);$tools=Join-Path $systemRoot 'tools'
. (Join-Path $tools 'Project-Origin.ps1')
. (Join-Path $tools 'Narrative-V2.ps1')

function Write-Utf8Lf([string]$Path,[string]$Text){
    $value=(ConvertTo-SystemV7LfText -Text $Text);if(-not $value.EndsWith("`n")){$value+="`n"};[IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null;[IO.File]::WriteAllText($Path,$value,[Text.UTF8Encoding]::new($false))
}
function Set-Meta([string]$Project,[hashtable]$Values){
    $path=Join-Path $Project 'meta.md';$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8;foreach($key in $Values.Keys){$text=Set-SystemV7NarrativeMetaField -Text $text -Name $key -Value ([string]$Values[$key])};Write-SystemV7NarrativeAtomicText -Path $path -Text $text|Out-Null
}
function Write-Out([string]$Project,[string]$Act,[string]$Opening,[string]$Closing,[string]$Note='BASELINE'){
    $value=[ordered]@{schema='CONTINUITY_OUT_V1';act_id=$Act;opening_move_type=$Opening;closing_move_type=$Closing;test_note=$Note}
    $actDir=Join-Path $Project "_work\k3\acts\$Act";$outPath=Join-Path $actDir 'out.json';$statePath=Join-Path $actDir 'state.json';$attestPath=Join-Path $Project "_work\k3\continuity\$Act.attest.json"
    Write-Utf8Lf -Path $outPath -Text (ConvertTo-SystemV7CanonicalJson -Value $value)
    $outSha=(Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash
    $attest=[ordered]@{schema='CONTINUITY_ATTEST_RECORD_V1';workflow_revision='2026-08-31_NARRATIVE_V2';act_id=$Act;verdict='PASS';continuity_out_sha256=$outSha}
    Write-Utf8Lf -Path $attestPath -Text (ConvertTo-SystemV7CanonicalJson -Value $attest)
    $state=[ordered]@{schema='K3_ACT_STATE_V1';act_id=$Act;status='ATTESTED';continuity_out_sha256=$outSha;attest_record_relative=([IO.Path]::GetRelativePath($Project,$attestPath).Replace('\','/'));attest_record_sha256=(Get-FileHash -LiteralPath $attestPath -Algorithm SHA256).Hash}
    Write-Utf8Lf -Path $statePath -Text (ConvertTo-SystemV7CanonicalJson -Value $state)
}

[IO.Directory]::CreateDirectory($fixtureRoot)|Out-Null
$project=Join-Path $fixtureRoot 'PROJECT-MOVE-REPETITION'
& (Join-Path $tools 'New-Project.ps1') -ProjectName 'PROJECT-MOVE-REPETITION' -DestinationRoot $fixtureRoot -NarrativeV2Pilot|Out-Null
Set-Meta -Project $project -Values @{CURRENT_STAGE='K4';LAST_GATE='K3_PASS';NARRATIVE_ACT_SEQUENCE='ACT-001,ACT-002';CONTINUITY_STATUS='COMPLETE'}
Write-Utf8Lf -Path (Join-Path $project '01-baza-dowodow.md') -Text 'Syntetyczna baza; bramka repetycji ma zatrzymać K4 przed jej analizą.'
Write-Utf8Lf -Path (Join-Path $project '02-architektura-odcinka.md') -Text 'STATUS: TESTOWA; bramka repetycji ma zatrzymać K4 przed jej analizą.'
Write-Utf8Lf -Path (Join-Path $project '03-draft.md') -Text 'Syntetyczny draft do sprawdzenia bramki repetycji przed uruchomieniem K4.'
Write-Out -Project $project -Act 'ACT-001' -Opening 'SCENA' -Closing 'DECYZJA'
Write-Out -Project $project -Act 'ACT-002' -Opening 'DOKUMENT' -Closing 'PAYOFF'
$noRepeat=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project

Write-Out -Project $project -Act 'ACT-002' -Opening 'SCENA' -Closing 'PAYOFF'
$repeat=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project
$k4Blocked=$false;$k4Error=''
try{
    $null=& (Join-Path $tools 'Start-K4Lenses.ps1') -ProjectPath $project -EditorRunId 'EDITOR.MOVE.0001' -VerifyRunId 'VERIFY.MOVE.0001' -ColdReaderRunId 'COLD.MOVE.0001'
}catch{$k4Error=$_.Exception.Message;$k4Blocked=$k4Error -match '^MOVE_REPETITION_REVIEW_ALERT:'}
$validator=& (Join-Path $tools 'Validate-NarrativeV2Project.ps1') -ProjectPath $project -NoExit
$validatorBlocked=@($validator.ErrorDetails|Where-Object{$_ -ceq 'MOVE_REPETITION_REVIEW_ALERT_UNRESOLVED: REVIEW_ALERT'}).Count -eq 1
$noRunsCreated=-not(Test-Path -LiteralPath (Join-Path $project '_work\narrative-runs\EDITOR.MOVE.0001')) -and -not(Test-Path -LiteralPath (Join-Path $project '_work\narrative-runs\VERIFY.MOVE.0001')) -and -not(Test-Path -LiteralPath (Join-Path $project '_work\narrative-runs\COLD.MOVE.0001'))

$decisionDir=Join-Path $project '_work\k3\continuity\move-repetition-decisions';$beforeNoFlag=@(Get-ChildItem -LiteralPath $decisionDir -File -ErrorAction SilentlyContinue).Count;$noFlagFailed=$false
try{$null=& (Join-Path $tools 'Approve-NarrativeMoveRepetition.ps1') -ProjectPath $project -Reason 'Świadoma repetycja otwarcia w syntetycznym teście regresyjnym.'}catch{$noFlagFailed=$_.Exception.Message -match '^DAWID_APPROVAL_REQUIRED$'}
$noFlagNoMutation=@(Get-ChildItem -LiteralPath $decisionDir -File -ErrorAction SilentlyContinue).Count -eq $beforeNoFlag
$approval=& (Join-Path $tools 'Approve-NarrativeMoveRepetition.ps1') -ProjectPath $project -Reason 'Świadoma repetycja otwarcia w syntetycznym teście regresyjnym.' -DawidApproved
$approved=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project

$replayProject=Join-Path $fixtureRoot 'PROJECT-MOVE-REPLAY'
& (Join-Path $tools 'New-Project.ps1') -ProjectName 'PROJECT-MOVE-REPLAY' -DestinationRoot $fixtureRoot -NarrativeV2Pilot|Out-Null
Set-Meta -Project $replayProject -Values @{CURRENT_STAGE='K4';LAST_GATE='K3_PASS';NARRATIVE_ACT_SEQUENCE='ACT-001,ACT-002';CONTINUITY_STATUS='COMPLETE'}
Write-Out -Project $replayProject -Act 'ACT-001' -Opening 'SCENA' -Closing 'DECYZJA'
Write-Out -Project $replayProject -Act 'ACT-002' -Opening 'SCENA' -Closing 'PAYOFF'
$replayBefore=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $replayProject
[IO.Directory]::CreateDirectory((Split-Path -Parent $replayBefore.DecisionPath))|Out-Null
[IO.File]::Copy($approval.ReceiptPath,$replayBefore.DecisionPath,$false)
$replayAfter=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $replayProject
$crossProjectReplayRejected=(-not [bool]$replayAfter.Valid) -and (-not [bool]$replayAfter.GateReady) -and @($replayAfter.Errors|Where-Object{$_ -like 'MOVE_REPETITION_DECISION_INVALID:*'}).Count -gt 0 -and [string]$replayBefore.HistorySha256 -cne [string]$approval.HistorySha256

$out2=Join-Path $project '_work\k3\acts\ACT-002\out.json';$state2=Join-Path $project '_work\k3\acts\ACT-002\state.json';$attest2=Join-Path $project '_work\k3\continuity\ACT-002.attest.json';$out2Bytes=[IO.File]::ReadAllBytes($out2);$state2Bytes=[IO.File]::ReadAllBytes($state2);$attest2Bytes=[IO.File]::ReadAllBytes($attest2)
Write-Out -Project $project -Act 'ACT-002' -Opening 'SCENA' -Closing 'PAYOFF' -Note 'HASH-CHANGED-WITH-SAME-MOVE'
$stale=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project
[IO.File]::WriteAllBytes($out2,$out2Bytes);[IO.File]::WriteAllBytes($state2,$state2Bytes);[IO.File]::WriteAllBytes($attest2,$attest2Bytes)
$restored=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project

[pscustomobject]@{
    ProjectPath=$project
    NoRepeatPass=([bool]$noRepeat.Valid -and [bool]$noRepeat.GateReady -and [string]$noRepeat.ReviewStatus -ceq 'PASS_NO_REPETITION' -and @($noRepeat.ReviewAlerts).Count -eq 0)
    RepeatReviewAlert=([bool]$repeat.Valid -and -not [bool]$repeat.GateReady -and [string]$repeat.ReviewStatus -ceq 'REVIEW_ALERT' -and @($repeat.ReviewAlerts).Count -eq 1)
    K4Blocked=$k4Blocked
    K4Error=$k4Error
    ValidatorBlocked=$validatorBlocked
    NoRunsCreated=$noRunsCreated
    NoFlagFailed=$noFlagFailed
    NoFlagNoMutation=$noFlagNoMutation
    ApprovalStatus=[string]$approval.Status
    ApprovalReceiptExists=(Test-Path -LiteralPath $approval.ReceiptPath -PathType Leaf)
    ApprovedGateReady=([bool]$approved.Valid -and [bool]$approved.GateReady -and [string]$approved.ReviewStatus -ceq 'PASS_CONSCIOUS_REPETITION_APPROVED')
    CrossProjectReplayRejected=$crossProjectReplayRejected
    ChangedOutInvalidates=(-not [bool]$stale.GateReady -and [string]$stale.ReviewStatus -ceq 'REVIEW_ALERT' -and [string]$stale.HistorySha256 -cne [string]$approval.HistorySha256)
    RestoreRevalidates=([bool]$restored.Valid -and [bool]$restored.GateReady -and [string]$restored.DecisionSha256 -ceq [string]$approval.ReceiptSha256)
}
