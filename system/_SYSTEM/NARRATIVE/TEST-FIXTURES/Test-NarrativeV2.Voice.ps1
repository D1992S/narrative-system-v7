param(
    [Parameter(Mandatory)][string]$SystemRoot,
    [Parameter(Mandatory)][string]$FixtureRoot
)
$ErrorActionPreference='Stop'
$systemRoot=[IO.Path]::GetFullPath($SystemRoot)
$fixtureRoot=[IO.Path]::GetFullPath($FixtureRoot)
$projectsRoot=Join-Path $fixtureRoot 'projects'
[IO.Directory]::CreateDirectory($fixtureRoot)|Out-Null
[IO.Directory]::CreateDirectory($projectsRoot)|Out-Null
$tools=Join-Path $systemRoot 'tools'

. (Join-Path $tools 'Project-Origin.ps1')
. (Join-Path $tools 'Narrative-V2.ps1')
. (Join-Path $tools 'Integrity-Receipts.ps1')

function Write-Lf([string]$Path,[string]$Text){
    $value=(ConvertTo-SystemV7LfText -Text $Text)
    if(-not $value.EndsWith("`n")){$value+="`n"}
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))|Out-Null
    [IO.File]::WriteAllText($Path,$value,[Text.UTF8Encoding]::new($false))
}
function Set-MetaValueLocal([string]$Project,[hashtable]$Values){
    $path=Join-Path $Project 'meta.md';$text=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach($name in $Values.Keys){$text=Set-SystemV7NarrativeMetaField -Text $text -Name $name -Value ([string]$Values[$name])}
    Write-SystemV7NarrativeAtomicText -Path $path -Text $text|Out-Null
}
function Get-TreeState([string]$Root){
    if(-not(Test-Path -LiteralPath $Root -PathType Container)){return @()}
    @(
        Get-ChildItem -LiteralPath $Root -File -Recurse -Force |
        Sort-Object FullName |
        ForEach-Object { '{0}|{1}' -f ([IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')),((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash) }
    )
}
function Invoke-ExpectFailure([scriptblock]$Action,[string]$Pattern){
    try{&$Action|Out-Null;return [pscustomobject]@{Failed=$false;Error='NO_ERROR'}}catch{return [pscustomobject]@{Failed=($_.Exception.Message -match $Pattern);Error=$_.Exception.Message}}
}
function New-Candidate([string]$Path,[string]$Revision,[string]$Rule){
    Write-Lf $Path @"
# Profil testowy

VOICE_PROFILE_SCHEMA: SYSTEM_V7_VOICE_PROFILE_V1
VOICE_PROFILE_REVISION: $Revision
STATUS: CANDIDATE
APPROVED_BY: BRAK
APPROVAL_RECEIPT_PATH: BRAK
APPROVAL_RECEIPT_SHA256: BRAK
RULES_SHA256: PENDING
EXEMPLAR_REGISTRY_SHA256: PENDING
EXEMPLARS_SHA256: PENDING

## VOICE RULES

$Rule

## VOICE EXEMPLARS

BRAK
"@
}
function New-Spec([string]$Path,[string]$Revision,[string]$ProjectName,[string]$Artifact,[string]$Exact){
    $spec=[ordered]@{
        schema='VOICE_EXEMPLAR_APPROVAL_INPUT_V1';voice_profile_revision=$Revision
        exemplars=@([ordered]@{
            exemplar_id='EX-001';project_name=$ProjectName;artifact_path=$Artifact;exact_text=$Exact
            demonstrates=@('STRONG_OPENING','SCENE','UNCERTAINTY','KNOWLEDGE_BOUNDARY','VIEWER_CONTACT','TRANSITION','PAYOFF')
        })
    }
    Write-Lf $Path (ConvertTo-SystemV7CanonicalJson -Value $spec)
}

# Legalny, odizolowany legacy source z ważnymi receiptami K4 i K5.
$sourceName='VOICE-SOURCE-APPROVED'
$sourceProject=Join-Path $projectsRoot $sourceName
& (Join-Path $tools 'New-Project.ps1') -NarrativeV2Pilot:$false -ProjectName $sourceName -DestinationRoot $projectsRoot -TargetMinutes 10 -RealWpm 130|Out-Null
$sentence='Ten fragment prowadzi widza od konkretnego pytania przez dowód do jasnej konsekwencji bez zbędnego nadęcia.'
$exactLong=((1..28|ForEach-Object{$sentence}) -join ' ')
$exactShort=((1..27|ForEach-Object{$sentence}) -join ' ')
$longWords=@([regex]::Matches($exactLong,"\b[\p{L}\p{N}][\p{L}\p{N}\p{M}’'-]*\b")).Count
$shortWords=@([regex]::Matches($exactShort,"\b[\p{L}\p{N}][\p{L}\p{N}\p{M}’'-]*\b")).Count
if($longWords -lt 300 -or $longWords -gt 500 -or $shortWords -lt 300 -or $shortWords -gt 500){throw "VOICE_WORD_COUNT_FIXTURE_INVALID: $longWords/$shortWords"}

Write-Lf (Join-Path $sourceProject 'sources\source.txt') 'Źródło syntetyczne przeznaczone wyłącznie do odizolowanego testu receiptu.'
Write-Lf (Join-Path $sourceProject '01-baza-dowodow.md') "SCHEMA: MINIMAL_EVIDENCE_V4_PAGELOC`nSTATUS: GOTOWA`n#P-001: syntetyczna karta."
Write-Lf (Join-Path $sourceProject '03-draft.md') 'Syntetyczny draft legalnego źródła profilu głosu.'
Write-Lf (Join-Path $sourceProject '04-raport-qa.md') 'Syntetyczny raport QA przeznaczony wyłącznie do testu.'
$draftSha=(Get-FileHash -LiteralPath (Join-Path $sourceProject '03-draft.md') -Algorithm SHA256).Hash
$agent='CHATGPT-VERIFY-VOICE';$task='TASK.VOICE.SOURCE.0001'
Write-Lf (Join-Path $sourceProject '04B-fact-check.md') "VERIFY_AGENT_ID: $agent`nVERIFY_TASK_ID: $task`nDRAFT_SHA256: $draftSha`nBRAK_UDZIAŁU_W_K3: TAK`nŹRÓDŁA_DOSTĘPNE: TAK`nSTATUS: PASS"
$k4=& (Join-Path $tools 'New-K4VerifyReceipt.ps1') -ProjectPath $sourceProject -VerifyAgentId $agent -TaskId $task -Note 'Niezależny syntetyczny verify do testu profilu głosu.' -ConfirmIndependentVerify
$qaSha=(Get-FileHash -LiteralPath (Join-Path $sourceProject '04-raport-qa.md') -Algorithm SHA256).Hash
$fcSha=(Get-FileHash -LiteralPath (Join-Path $sourceProject '04B-fact-check.md') -Algorithm SHA256).Hash
Write-Lf (Join-Path $sourceProject '05-FINAL-SCRIPT.md') "STATUS: ZATWIERDZONY`nSOURCE_DRAFT_SHA256: $draftSha`nSOURCE_QA_SHA256: $qaSha`nSOURCE_FACTCHECK_SHA256: $fcSha`n`n## NARRACJA FINALNA`n`n$exactLong"
$k5=& (Join-Path $tools 'Approve-K5Final.ps1') -ProjectPath $sourceProject -ApprovalNote 'Jawna zgoda wyłącznie dla syntetycznego fixture testowego.' -DawidApproved
$k5State=Get-K5ApprovalReceiptState -ProjectPath $sourceProject
if(-not $k5State.Valid){throw "SOURCE_K5_NOT_VALID: $($k5State.Errors -join '; ')"}

$profiles=Join-Path $systemRoot '_SYSTEM\NARRATIVE\VOICE-PROFILES'
$specs=Join-Path $fixtureRoot 'specs';[IO.Directory]::CreateDirectory($specs)|Out-Null
$revision='TEST-VOICE-V1'
$profile=Join-Path $profiles "$revision.md"
$spec=Join-Path $specs "$revision.json"
New-Candidate $profile $revision 'Pisz jasno, konkretnie i bez mechanicznego nadęcia.'
New-Spec $spec $revision $sourceName (Join-Path $sourceProject '05-FINAL-SCRIPT.md') $exactLong
$positive=& (Join-Path $tools 'Approve-VoiceProfile.ps1') -ProfilePath $profile -ExemplarSpecPath $spec -ApprovalNote 'Jawna akceptacja syntetycznego profilu do testu.' -DawidApproved
$positiveState=Get-SystemV7VoiceProfileState -ProfilePath $profile
if(-not $positiveState.Valid){throw "VOICE_APPROVAL_POSITIVE_INVALID: $($positiveState.Errors -join '; ')"}
$approvedProfileBytes=[IO.File]::ReadAllBytes($profile)

# Brak flagi: zero mutacji.
$noFlagRevision='TEST-VOICE-NOFLAG-V1';$noFlagProfile=Join-Path $profiles "$noFlagRevision.md";$noFlagSpec=Join-Path $specs "$noFlagRevision.json"
New-Candidate $noFlagProfile $noFlagRevision 'Pisz zwięźle i wyjaśniaj niepewność.'
New-Spec $noFlagSpec $noFlagRevision $sourceName (Join-Path $sourceProject '05-FINAL-SCRIPT.md') $exactLong
$noFlagBefore=[IO.File]::ReadAllBytes($noFlagProfile);$treeBefore=Get-TreeState (Join-Path $profiles '_APPROVALS')
$noFlag=Invoke-ExpectFailure {& (Join-Path $tools 'Approve-VoiceProfile.ps1') -ProfilePath $noFlagProfile -ExemplarSpecPath $noFlagSpec -ApprovalNote 'Brak flagi powinien zawsze zostać odrzucony.'} 'VOICE_PROFILE_REQUIRES_EXPLICIT_DAWID_APPROVAL'
$noFlagNoMutation=([Convert]::ToBase64String([IO.File]::ReadAllBytes($noFlagProfile)) -ceq [Convert]::ToBase64String($noFlagBefore)) -and (@(Compare-Object $treeBefore (Get-TreeState (Join-Path $profiles '_APPROVALS'))).Count -eq 0)

# Book/competitor-like input: nie jest finalnym skryptem projektu.
$book=Join-Path $fixtureRoot 'book.txt';Write-Lf $book $exactLong
$bookRevision='TEST-VOICE-BOOK-V1';$bookProfile=Join-Path $profiles "$bookRevision.md";$bookSpec=Join-Path $specs "$bookRevision.json"
New-Candidate $bookProfile $bookRevision 'Nie kopiuj głosu z zewnętrznych publikacji.'
New-Spec $bookSpec $bookRevision 'BOOK' $book $exactLong
$bookFail=Invoke-ExpectFailure {& (Join-Path $tools 'Approve-VoiceProfile.ps1') -ProfilePath $bookProfile -ExemplarSpecPath $bookSpec -ApprovalNote 'Źródło książkowe ma zostać odrzucone.' -DawidApproved} 'VOICE_EXEMPLAR_NOT_FINAL_SCRIPT'

# Niezatwierdzony final.
$sourceFinal=Join-Path $sourceProject '05-FINAL-SCRIPT.md';$sourceFinalBytes=[IO.File]::ReadAllBytes($sourceFinal)
$unapprovedText=(Get-Content -LiteralPath $sourceFinal -Raw -Encoding UTF8).Replace('STATUS: ZATWIERDZONY','STATUS: ROBOCZY')
Write-Lf $sourceFinal $unapprovedText
$unapprovedRevision='TEST-VOICE-UNAPPROVED-V1';$unapprovedProfile=Join-Path $profiles "$unapprovedRevision.md";$unapprovedSpec=Join-Path $specs "$unapprovedRevision.json"
New-Candidate $unapprovedProfile $unapprovedRevision 'Używaj tylko prozy zatwierdzonej przez Dawida.'
New-Spec $unapprovedSpec $unapprovedRevision $sourceName $sourceFinal $exactLong
$unapprovedFail=Invoke-ExpectFailure {& (Join-Path $tools 'Approve-VoiceProfile.ps1') -ProfilePath $unapprovedProfile -ExemplarSpecPath $unapprovedSpec -ApprovalNote 'Niezatwierdzony final ma zostać odrzucony.' -DawidApproved} 'VOICE_EXEMPLAR_FINAL_NOT_DAWID_APPROVED'
[IO.File]::WriteAllBytes($sourceFinal,$sourceFinalBytes)

# Tamper zatwierdzonego źródła unieważnia live profil, restore przywraca PASS.
[IO.File]::AppendAllText($sourceFinal,"`nTAMPER",[Text.UTF8Encoding]::new($false))
$tamperedState=Get-SystemV7VoiceProfileState -ProfilePath $profile
[IO.File]::WriteAllBytes($sourceFinal,$sourceFinalBytes)
$restoredState=Get-SystemV7VoiceProfileState -ProfilePath $profile

# Approval rollback po wymuszonym błędzie postwalidacji.
$rollbackRevision='TEST-VOICE-ROLLBACK-V1';$rollbackProfile=Join-Path $profiles "$rollbackRevision.md";$rollbackSpec=Join-Path $specs "$rollbackRevision.json"
New-Candidate $rollbackProfile $rollbackRevision 'Rollback musi zachować kandydat bajt w bajt.'
New-Spec $rollbackSpec $rollbackRevision $sourceName $sourceFinal $exactLong
$rollbackBefore=[IO.File]::ReadAllBytes($rollbackProfile);$approvalTreeBefore=Get-TreeState (Join-Path $profiles '_APPROVALS')
$lib=Join-Path $tools 'Narrative-V2.ps1';$libBytes=[IO.File]::ReadAllBytes($lib);$libText=Get-Content -LiteralPath $lib -Raw -Encoding UTF8
$voiceNeedle='    $errors = [Collections.Generic.List[string]]::new()'
$voiceInjected=$libText.Replace($voiceNeedle,$voiceNeedle+"`n    if(`$env:SYSTEM_V7_TEST_FORCE_VOICE_PROFILE_INVALID -ceq '1'){`$errors.Add('INJECTED_VOICE_PROFILE_POSTVALIDATION_FAILURE')}")
if($voiceInjected -ceq $libText){throw 'VOICE_INJECTION_POINT_MISSING'}
[IO.File]::WriteAllText($lib,$voiceInjected,[Text.UTF8Encoding]::new($false));$env:SYSTEM_V7_TEST_FORCE_VOICE_PROFILE_INVALID='1'
try{$rollbackFail=Invoke-ExpectFailure {& (Join-Path $tools 'Approve-VoiceProfile.ps1') -ProfilePath $rollbackProfile -ExemplarSpecPath $rollbackSpec -ApprovalNote 'Wymuszony błąd ma uruchomić pełny rollback.' -DawidApproved} 'VOICE_PROFILE_POSTVALIDATION_FAILED'}finally{$env:SYSTEM_V7_TEST_FORCE_VOICE_PROFILE_INVALID=$null;[IO.File]::WriteAllBytes($lib,$libBytes)}
$approvalRollbackNoMutation=([Convert]::ToBase64String([IO.File]::ReadAllBytes($rollbackProfile)) -ceq [Convert]::ToBase64String($rollbackBefore)) -and (@(Compare-Object $approvalTreeBefore (Get-TreeState (Join-Path $profiles '_APPROVALS'))).Count -eq 0)

# Project selection: W0 i K2B positive, idempotence, missing approval, frozen/late i rollback.
$selectW0Name='SELECT-W0';$selectW0=Join-Path $projectsRoot $selectW0Name
& (Join-Path $tools 'New-Project.ps1') -ProjectName $selectW0Name -DestinationRoot $projectsRoot -NarrativeV2Pilot|Out-Null
$selectPositive=& (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -ProjectPath $selectW0 -ProfilePath $profile -ApprovalNote 'Jawny wybór profilu dla syntetycznego projektu W0.' -DawidApproved
$selectMetaBefore=[IO.File]::ReadAllBytes((Join-Path $selectW0 'meta.md'));$selectReceiptSha=$selectPositive.ReceiptSha256
$selectRepeat=& (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -ProjectPath $selectW0 -ProfilePath $profile -ApprovalNote 'Jawny wybór profilu dla syntetycznego projektu W0.' -DawidApproved
$selectIdempotent=$selectRepeat.Status -ceq 'VOICE_PROFILE_ALREADY_SELECTED' -and $selectRepeat.ReceiptSha256 -ceq $selectReceiptSha -and [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $selectW0 'meta.md'))) -ceq [Convert]::ToBase64String($selectMetaBefore)

$selectK2BName='SELECT-K2B';$selectK2B=Join-Path $projectsRoot $selectK2BName
& (Join-Path $tools 'New-Project.ps1') -ProjectName $selectK2BName -DestinationRoot $projectsRoot -NarrativeV2Pilot|Out-Null
Set-MetaValueLocal $selectK2B @{CURRENT_STAGE='K2B';LAST_GATE='K2_PASS'}
$selectK2BResult=& (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -ProjectPath $selectK2B -ProfilePath $profile -ApprovalNote 'Jawny wybór profilu dla syntetycznego projektu K2B.' -DawidApproved

$selectNoFlagName='SELECT-NOFLAG';$selectNoFlagProject=Join-Path $projectsRoot $selectNoFlagName
& (Join-Path $tools 'New-Project.ps1') -ProjectName $selectNoFlagName -DestinationRoot $projectsRoot -NarrativeV2Pilot|Out-Null
$selectNoFlagBefore=[IO.File]::ReadAllBytes((Join-Path $selectNoFlagProject 'meta.md'))
$selectNoFlag=Invoke-ExpectFailure {& (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -ProjectPath $selectNoFlagProject -ProfilePath $profile -ApprovalNote 'Brak flagi musi zostać odrzucony.'} 'VOICE_PROFILE_SELECTION_REQUIRES_EXPLICIT_DAWID_APPROVAL'
$selectNoFlagNoMutation=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $selectNoFlagProject 'meta.md'))) -ceq [Convert]::ToBase64String($selectNoFlagBefore) -and -not(Test-Path -LiteralPath (Join-Path $selectNoFlagProject '_work\system') -PathType Container)

$lateName='SELECT-LATE';$lateProject=Join-Path $projectsRoot $lateName
& (Join-Path $tools 'New-Project.ps1') -ProjectName $lateName -DestinationRoot $projectsRoot -NarrativeV2Pilot|Out-Null
Set-MetaValueLocal $lateProject @{CURRENT_STAGE='K3';LAST_GATE='K2B_PASS'};$lateBefore=[IO.File]::ReadAllBytes((Join-Path $lateProject 'meta.md'))
$lateFail=Invoke-ExpectFailure {& (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -ProjectPath $lateProject -ProfilePath $profile -ApprovalNote 'K3 jest za późnym etapem na wybór profilu.' -DawidApproved} 'VOICE_PROFILE_SELECTION_TOO_LATE'
$lateNoMutation=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $lateProject 'meta.md'))) -ceq [Convert]::ToBase64String($lateBefore)

$frozenName='SELECT-FROZEN';$frozenProject=Join-Path $projectsRoot $frozenName
& (Join-Path $tools 'New-Project.ps1') -ProjectName $frozenName -DestinationRoot $projectsRoot -NarrativeV2Pilot|Out-Null
Set-MetaValueLocal $frozenProject @{CURRENT_STAGE='K2B';LAST_GATE='K2_PASS';K3_PREFIX_SHA256=('A'*64)};$frozenBefore=[IO.File]::ReadAllBytes((Join-Path $frozenProject 'meta.md'))
$frozenFail=Invoke-ExpectFailure {& (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -ProjectPath $frozenProject -ProfilePath $profile -ApprovalNote 'Prefix jest już zamrożony, więc wybór ma zawieść.' -DawidApproved} 'VOICE_PROFILE_SELECTION_AFTER_PREFIX_FREEZE'
$frozenNoMutation=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $frozenProject 'meta.md'))) -ceq [Convert]::ToBase64String($frozenBefore)

$selectionRollbackName='SELECT-ROLLBACK';$selectionRollbackProject=Join-Path $projectsRoot $selectionRollbackName
& (Join-Path $tools 'New-Project.ps1') -ProjectName $selectionRollbackName -DestinationRoot $projectsRoot -NarrativeV2Pilot|Out-Null
$selectionMetaBefore=[IO.File]::ReadAllBytes((Join-Path $selectionRollbackProject 'meta.md'));$selectionTreeBefore=Get-TreeState (Join-Path $selectionRollbackProject '_work')
$libBytes=[IO.File]::ReadAllBytes($lib);$libText=Get-Content -LiteralPath $lib -Raw -Encoding UTF8
$selectionNeedle='    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)'
$selectionInjected=$libText.Replace($selectionNeedle,$selectionNeedle+"`n    if(`$env:SYSTEM_V7_TEST_FORCE_SELECTION_INVALID -ceq '1'){return [pscustomobject]@{Valid=`$false;Errors=@('INJECTED_SELECTION_POSTVALIDATION_FAILURE');Data=`$null}}")
if($selectionInjected -ceq $libText){throw 'SELECTION_INJECTION_POINT_MISSING'}
[IO.File]::WriteAllText($lib,$selectionInjected,[Text.UTF8Encoding]::new($false));$env:SYSTEM_V7_TEST_FORCE_SELECTION_INVALID='1'
try{$selectionRollbackFail=Invoke-ExpectFailure {& (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -ProjectPath $selectionRollbackProject -ProfilePath $profile -ApprovalNote 'Wymuszony błąd ma cofnąć meta oraz receipt.' -DawidApproved} 'VOICE_PROFILE_SELECTION_POSTVALIDATION_FAILED'}finally{$env:SYSTEM_V7_TEST_FORCE_SELECTION_INVALID=$null;[IO.File]::WriteAllBytes($lib,$libBytes)}
$selectionRollbackNoMutation=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $selectionRollbackProject 'meta.md'))) -ceq [Convert]::ToBase64String($selectionMetaBefore) -and ((@($selectionTreeBefore) -join "`n") -ceq (@(Get-TreeState (Join-Path $selectionRollbackProject '_work')) -join "`n"))

[pscustomobject]@{
    FixtureRoot=$fixtureRoot
    ApprovedProfilePath=$profile
    SourceProjectPath=$sourceProject
    ExactShort=$exactShort
    ExactLong=$exactLong
    ApproveVoiceSha256=(Get-FileHash -LiteralPath (Join-Path $tools 'Approve-VoiceProfile.ps1') -Algorithm SHA256).Hash
    SetVoiceSha256=(Get-FileHash -LiteralPath (Join-Path $tools 'Set-VoiceProfileForProject.ps1') -Algorithm SHA256).Hash
    NarrativeV2Sha256=(Get-FileHash -LiteralPath (Join-Path $tools 'Narrative-V2.ps1') -Algorithm SHA256).Hash
    SourceK5Valid=$k5State.Valid;ExemplarWordCount=$positive.ExemplarWordCount;PositiveProfileValid=$positiveState.Valid
    NoFlagFailed=$noFlag.Failed;NoFlagError=$noFlag.Error;NoFlagNoMutation=$noFlagNoMutation
    BookFailed=$bookFail.Failed;BookError=$bookFail.Error
    UnapprovedFailed=$unapprovedFail.Failed;UnapprovedError=$unapprovedFail.Error
    SourceTamperInvalid=(-not $tamperedState.Valid);SourceTamperErrors=@($tamperedState.Errors);SourceRestoreValid=$restoredState.Valid
    ApprovalRollbackFailed=$rollbackFail.Failed;ApprovalRollbackError=$rollbackFail.Error;ApprovalRollbackNoMutation=$approvalRollbackNoMutation
    SelectW0Status=$selectPositive.Status;SelectK2BStatus=$selectK2BResult.Status;SelectIdempotent=$selectIdempotent
    SelectNoFlagFailed=$selectNoFlag.Failed;SelectNoFlagNoMutation=$selectNoFlagNoMutation
    SelectLateFailed=$lateFail.Failed;SelectLateNoMutation=$lateNoMutation
    SelectFrozenFailed=$frozenFail.Failed;SelectFrozenNoMutation=$frozenNoMutation
    SelectionRollbackFailed=$selectionRollbackFail.Failed;SelectionRollbackError=$selectionRollbackFail.Error;SelectionRollbackNoMutation=$selectionRollbackNoMutation
}

