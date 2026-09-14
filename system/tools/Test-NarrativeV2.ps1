[CmdletBinding()]
param([switch]$KeepFixture,[string]$PythonPath='python.exe')

$ErrorActionPreference='Stop'
$sourceSystemRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$fixtureRelative='_SYSTEM\NARRATIVE\TEST-FIXTURES'
$started=[Diagnostics.Stopwatch]::StartNew()
$runRoot=Join-Path ([IO.Path]::GetTempPath()) ('system-v7-narrative-v2-regression-'+[guid]::NewGuid().ToString('N'))
$tempSystemRoot=Join-Path $runRoot 'System-v7.0'
$result=$null;$cleanup='NOT_RUN';$caught=$null

function Assert-True([bool]$Condition,[string]$Code){if(-not $Condition){throw "NARRATIVE_V2_TEST_FAILED: $Code"}}
function Get-MetaField([string]$Project,[string]$Name){
    $text=Get-Content -LiteralPath (Join-Path $Project 'meta.md') -Raw -Encoding UTF8
    $m=[regex]::Match($text,"(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$");if($m.Success){$m.Groups[1].Value.Trim()}else{''}
}
function Get-TreeFingerprint([string]$Root){
    @(
        Get-ChildItem -LiteralPath $Root -File -Recurse -Force|Sort-Object FullName|ForEach-Object{
            '{0}|{1}' -f ([IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')),((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)
        }
    )
}
function Get-DurableSourceFingerprint([string]$Root){
    @(
        Get-ChildItem -LiteralPath $Root -File -Recurse -Force|ForEach-Object{
            $relative=[IO.Path]::GetRelativePath($Root,$_.FullName).Replace('\','/')
            # Test-System ma jeden dokładnie nazwany, efemeryczny sandbox w
            # korzeniu. Równoległy test może w nim trzymać lock; nie jest to
            # trwały plik produkcyjny ani powód do wyłączenia szerszych ścieżek.
            if($relative.StartsWith('_test-run/',[StringComparison]::OrdinalIgnoreCase)){return}
            if($relative -match '(^|/)(?:\.git|__pycache__|_work|tmp|temp|logs?)(/|$)' -or $relative -match '(?i)\.(?:tmp|log)$'){return}
            [pscustomobject]@{Relative=$relative;FullName=$_.FullName}
        }|Sort-Object Relative|ForEach-Object{
            '{0}|{1}' -f $_.Relative,((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)
        }
    )
}
function Assert-TempRoot([string]$Path){
    $full=[IO.Path]::GetFullPath($Path);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw "TEST_ROOT_OUTSIDE_TEMP: $full"}
    if($full -eq [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')){throw 'TEST_ROOT_TOO_BROAD'}
}
function Assert-UnderRunRoot([string]$Path,[string]$Code){
    $full=[IO.Path]::GetFullPath($Path);$prefix=[IO.Path]::GetFullPath($runRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "NARRATIVE_V2_TEST_FAILED: OUTSIDE_TEMP/$Code/$full"}
}

$critical=@('tools\Narrative-V2.ps1','tools\Narrative-Receipts.ps1','tools\Validate-NarrativeV2Project.ps1','tools\New-NarrativeRunReceipt.ps1','tools\Build-K3PacketsV2.ps1','tools\Build-SourceManifest.ps1','tools\Start-K4Lenses.ps1','tools\Approve-K5FinalV2.ps1')
$criticalSource=[ordered]@{};foreach($relative in $critical){$criticalSource[$relative]=(Get-FileHash -LiteralPath (Join-Path $sourceSystemRoot $relative) -Algorithm SHA256).Hash}
$protectedSourceRoot=Join-Path $sourceSystemRoot '_SYSTEM\NARRATIVE\VOICE-PROFILES'
$protectedSourceBefore=Get-TreeFingerprint $protectedSourceRoot
$durableSourceBefore=Get-DurableSourceFingerprint $sourceSystemRoot

try{
    Assert-TempRoot $runRoot
    [IO.Directory]::CreateDirectory($runRoot)|Out-Null
    Copy-Item -LiteralPath $sourceSystemRoot -Destination $tempSystemRoot -Recurse
    $tempTools=Join-Path $tempSystemRoot 'tools';$tempFixtures=Join-Path $tempSystemRoot $fixtureRelative
    foreach($relative in $critical){Assert-True ((Get-FileHash -LiteralPath (Join-Path $tempSystemRoot $relative) -Algorithm SHA256).Hash -ceq $criticalSource[$relative]) "COPY_HASH_MISMATCH/$relative"}

    $instructionContract=& (Join-Path $tempFixtures 'Test-NarrativeV2.InstructionContract.ps1') -SystemRoot $tempSystemRoot
    foreach($name in @('BaselineValid','MarkerRejected','RouteRejected','StatusRejected','ControlledFileRejected','ManifestHashRejected','ManifestAllowlistRejected','ExactRestore')){Assert-True ([bool]$instructionContract.$name) "INSTRUCTION_CONTRACT/$name"}

    # Nie istnieje bezpieczny, autoryzowany hook dokładnie pomiędzy pre-readem
    # meta a wejściem pod lock w Build-SourceManifest. Trwały guard sprawdza
    # więc fizycznie, że ścieżka WRITE ponownie czyta revision i origin już po
    # utworzeniu projectLock, zanim wybierze dispatcher K1.
    $sourceManifestText=Get-Content -LiteralPath (Join-Path $tempTools 'Build-SourceManifest.ps1') -Raw -Encoding UTF8
    $sourceManifestRereadGuard=[regex]::IsMatch($sourceManifestText,'(?s)\$projectLock\s*=\s*if\s*\(\$Write\).*?try\s*\{\s*if\s*\(\$Write\)\s*\{\s*\$metaForAuthorization\s*=\s*Get-Content.*?\$workflowRevision\s*=\s*Get-DocumentField.*?\$originAuthorization\s*=\s*Assert-SystemV7MutableProjectOrigin.*?\}\s*if\s*\(\$workflowRevision\s+-in\s+\$k1LiteV2WorkflowRevisions\)')
    Assert-True $sourceManifestRereadGuard 'SOURCE_MANIFEST/REVISION_NOT_REREAD_UNDER_LOCK'

    # Dispatch legacy/V2 przez ten sam publiczny Validate-Project.
    $dispatchRoot=Join-Path $runRoot 'dispatch';[IO.Directory]::CreateDirectory($dispatchRoot)|Out-Null
    & (Join-Path $tempTools 'New-Project.ps1') -NarrativeV2Pilot:$false -ProjectName 'LEGACY-DISPATCH' -DestinationRoot $dispatchRoot|Out-Null
    & (Join-Path $tempTools 'New-Project.ps1') -ProjectName 'V2-DISPATCH' -DestinationRoot $dispatchRoot|Out-Null
    $legacyProject=Join-Path $dispatchRoot 'LEGACY-DISPATCH';$v2Project=Join-Path $dispatchRoot 'V2-DISPATCH'
    . (Join-Path $tempTools 'Integrity-Receipts.ps1');$warmLock=Enter-SystemV7ProjectMetaLock -ProjectPath $v2Project;Exit-SystemV7ProjectMetaLock -LockStream $warmLock
    $legacyBefore=Get-TreeFingerprint $legacyProject;$v2Before=Get-TreeFingerprint $v2Project
    $legacyDispatch=& (Join-Path $tempTools 'Validate-Project.ps1') -ProjectPath $legacyProject -NoExit
    $v2Dispatch=& (Join-Path $tempTools 'Validate-Project.ps1') -ProjectPath $v2Project -NoExit
    Assert-True ((Get-MetaField $legacyProject 'WORKFLOW_REVISION') -ceq '2026-08-30_K1_LITE_V2') 'LEGACY_REVISION_DISPATCH'
    Assert-True ((Get-MetaField $v2Project 'WORKFLOW_REVISION') -ceq '2026-08-31_NARRATIVE_V2') 'V2_REVISION_DISPATCH'
    Assert-True ((Get-MetaField $v2Project 'WORKFLOW_ACTIVATION') -ceq 'PILOT_ONLY') 'V2_ACTIVATION_DISPATCH'
    Assert-True (@($legacyDispatch.ErrorDetails|Where-Object{$_ -like 'W0:*'}).Count -gt 0) 'LEGACY_VALIDATOR_NOT_USED'
    Assert-True (@($v2Dispatch.ErrorDetails|Where-Object{$_ -ceq 'W0_DECISION_NOT_READY: NIEUSTALONE'}).Count -eq 1) 'V2_VALIDATOR_NOT_USED'
    Assert-True ((Get-TreeFingerprint $legacyProject) -join "`n" -ceq ($legacyBefore -join "`n")) 'LEGACY_VALIDATOR_MUTATED_PROJECT'
    . (Join-Path $tempTools 'Project-Origin.ps1')
    . (Join-Path $tempTools 'Narrative-V2.ps1')
    $v2CaseMetaPath=Join-Path $v2Project 'meta.md';$v2CaseOriginPath=Join-Path $v2Project '.system-v7\project-origin.json';$v2CaseMetaBytes=[IO.File]::ReadAllBytes($v2CaseMetaPath);$v2CaseOriginBytes=[IO.File]::ReadAllBytes($v2CaseOriginPath)
    try{
        $badWorkflow='2026-08-31_narrative_v2';$caseMeta=Get-Content -LiteralPath $v2CaseMetaPath -Raw -Encoding UTF8;$caseMeta=[regex]::Replace($caseMeta,'(?m)^WORKFLOW_REVISION:\s*.*$',"WORKFLOW_REVISION: $badWorkflow",1);[IO.File]::WriteAllText($v2CaseMetaPath,$caseMeta,[Text.UTF8Encoding]::new($false))
        $caseOrigin=Get-Content -LiteralPath $v2CaseOriginPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 16;$caseOrigin.origin_workflow_revision=$badWorkflow
        $binding=Get-SystemV7OriginBindingText -ProjectId ([string]$caseOrigin.project_id) -ProjectName ([string]$caseOrigin.project_name) -ProjectPath ([string]$caseOrigin.project_path) -CreatedAtUtc ([string]$caseOrigin.created_at_utc) -WorkflowRevision $badWorkflow -EvidenceSchema ([string]$caseOrigin.origin_evidence_schema)
        $caseOrigin.binding_sha256=Get-SystemV7TextSha256 -Text $binding;[IO.File]::WriteAllText($v2CaseOriginPath,(($caseOrigin|ConvertTo-Json -Depth 16)+"`n"),[Text.UTF8Encoding]::new($false))
        $caseBefore=Get-TreeFingerprint $v2Project;$caseValidation=& (Join-Path $tempTools 'Validate-Project.ps1') -ProjectPath $v2Project -NoExit;$caseAdvanceRejected=$false;$caseBlockRejected=$false
        try{$null=& (Join-Path $tempTools 'Advance-Stage.ps1') -ProjectPath $v2Project -Apply -DawidApproved}catch{$caseAdvanceRejected=$true};try{$null=& (Join-Path $tempTools 'Block-Project.ps1') -ProjectPath $v2Project -Reason 'Niekanoniczna rewizja musi zostać odrzucona bez mutacji.' -DawidApproved}catch{$caseBlockRejected=$true}
        Assert-True ([string]$caseValidation.Verdict -ceq 'FAIL' -and $caseAdvanceRejected -and $caseBlockRejected) 'V2_WORKFLOW_CASE_DISPATCH_NOT_REJECTED'
        Assert-True (((Get-TreeFingerprint $v2Project)-join "`n") -ceq ($caseBefore-join "`n")) 'V2_WORKFLOW_CASE_REJECTION_MUTATED_PROJECT'
    }finally{[IO.File]::WriteAllBytes($v2CaseMetaPath,$v2CaseMetaBytes);[IO.File]::WriteAllBytes($v2CaseOriginPath,$v2CaseOriginBytes)}
    Assert-True ((Get-TreeFingerprint $v2Project) -join "`n" -ceq ($v2Before -join "`n")) 'V2_VALIDATOR_MUTATED_PROJECT'

    $voice=& (Join-Path $tempFixtures 'Test-NarrativeV2.Voice.ps1') -SystemRoot $tempSystemRoot -FixtureRoot (Join-Path $runRoot 'voice')
    Assert-UnderRunRoot $voice.ApprovedProfilePath 'VOICE_PROFILE';Assert-UnderRunRoot $voice.SourceProjectPath 'VOICE_SOURCE'
    foreach($name in @('SourceK5Valid','PositiveProfileValid','NoFlagFailed','NoFlagNoMutation','BookFailed','UnapprovedFailed','SourceTamperInvalid','SourceRestoreValid','ApprovalRollbackFailed','ApprovalRollbackNoMutation','SelectIdempotent','SelectNoFlagFailed','SelectNoFlagNoMutation','SelectLateFailed','SelectLateNoMutation','SelectFrozenFailed','SelectFrozenNoMutation','SelectionRollbackFailed','SelectionRollbackNoMutation')){Assert-True ([bool]$voice.$name) "VOICE/$name"}
    Assert-True ([string]$voice.SelectW0Status -ceq 'VOICE_PROFILE_SELECTED') 'VOICE/SELECT_W0'
    Assert-True ([string]$voice.SelectK2BStatus -ceq 'VOICE_PROFILE_SELECTED') 'VOICE/SELECT_K2B'
    Assert-True ([int]$voice.ExemplarWordCount -ge 300 -and [int]$voice.ExemplarWordCount -le 500) 'VOICE/EXEMPLAR_WORD_COUNT'

    $duration=& (Join-Path $tempFixtures 'Test-NarrativeV2.Duration.ps1') -SystemRoot $tempSystemRoot -FixtureRoot (Join-Path $runRoot 'duration')
    Assert-UnderRunRoot $duration.ProjectPath 'DURATION_PROJECT'
    foreach($name in @('AdvanceApplied','NewProjectModeNormalized','NoFlagFailed','NoFlagNoMutation','ReceiptExists','ReceiptUnchanged','ModeNormalized','BaselineDurationClean','MetaTamperRejected','FoundationTamperRejected','RestoreDurationClean','RestoreExact')){Assert-True ([bool]$duration.$name) "DURATION/$name"}
    Assert-True ([string]$duration.PolicyStatus -ceq 'DURATION_POLICY_UPDATED') 'DURATION/STATUS'

    $k3=& (Join-Path $tempFixtures 'Test-NarrativeV2.K3.ps1') -SystemRoot $tempSystemRoot -FixtureRoot (Join-Path $runRoot 'k3') -VoiceProfilePath $voice.ApprovedProfilePath -PythonPath $PythonPath
    Assert-UnderRunRoot $k3.FixturePath 'K3_PROJECT'
    foreach($name in @('ArchitectureGateReady','ArchitectureCaseExact','ContinuityCaseExact','MappingPass','TamperDetected','RevisionSpineStable','RevisionActStable','LocalSpineStable','LocalActInvalidated','GlobalSpineInvalidated')){Assert-True ([bool]$k3.$name) "K3/$name"}
    Assert-True ([string]$k3.AssemblyStatus -ceq 'K3_DRAFT_ASSEMBLED') 'K3/ASSEMBLY_STATUS'
    Assert-True (@($k3.BaselineAssemblyErrors).Count -eq 0) 'K3/BASELINE_ASSEMBLY_ERRORS'
    Assert-True (@($k3.MappedBlocks).Count -eq 3) 'K3/COMPLEX_BLOCK_COUNT'

    # CURRENT_STAGE jest polem kanonicznym. Binder i hashtabele PowerShell są
    # case-insensitive, więc walidator musi jawnie odrzucać małe/mieszane litery.
    $stageMetaPath=Join-Path $k3.FixturePath 'meta.md';$stageMetaExact=[IO.File]::ReadAllBytes($stageMetaPath);$stageCaseRejected=$true;$stageCaseNoMutation=$true
    foreach($badStage in @('k3','k2B')){
        [IO.File]::WriteAllBytes($stageMetaPath,$stageMetaExact)
        $stageText=Get-Content -LiteralPath $stageMetaPath -Raw -Encoding UTF8;$stageMutant=[regex]::Replace($stageText,'(?m)^CURRENT_STAGE:\s*K3\s*$',"CURRENT_STAGE: $badStage",1)
        if($stageMutant -ceq $stageText){throw 'K3/STAGE_CASE_TAMPER_PATTERN_MISSING'}
        [IO.File]::WriteAllText($stageMetaPath,$stageMutant,[Text.UTF8Encoding]::new($false))
        $mutantBefore=Get-TreeFingerprint $k3.FixturePath;$validation=& (Join-Path $tempTools 'Validate-NarrativeV2Project.ps1') -ProjectPath $k3.FixturePath -NoExit
        $previewRejected=$false;$applyRejected=$false;$blockRejected=$false
        try{$null=& (Join-Path $tempTools 'Advance-Stage.ps1') -ProjectPath $k3.FixturePath}catch{$previewRejected=$true}
        try{$null=& (Join-Path $tempTools 'Advance-Stage.ps1') -ProjectPath $k3.FixturePath -Apply}catch{$applyRejected=$true}
        try{$null=& (Join-Path $tempTools 'Block-Project.ps1') -ProjectPath $k3.FixturePath -Reason 'Niekanoniczny etap musi zostać odrzucony bez mutacji.' -DawidApproved}catch{$blockRejected=$true}
        $stageCaseRejected=$stageCaseRejected -and ([string]$validation.Verdict -ceq 'FAIL') -and (($validation.ErrorDetails -join ';') -match 'CURRENT_STAGE_INVALID') -and $previewRejected -and $applyRejected -and $blockRejected
        $stageCaseNoMutation=$stageCaseNoMutation -and (((Get-TreeFingerprint $k3.FixturePath)-join "`n") -ceq ($mutantBefore-join "`n"))
    }
    [IO.File]::WriteAllBytes($stageMetaPath,$stageMetaExact)
    Assert-True $stageCaseRejected 'K3/STAGE_CASE_NOT_REJECTED'
    Assert-True $stageCaseNoMutation 'K3/STAGE_CASE_REJECTION_MUTATED_PROJECT'

    # Polityka źródeł i decyzja K2B są zamkniętymi enumami. Zmiana wielkości
    # liter nie może odwrócić zgody na web ani ominąć wymaganych gaps.
    $policyMetaPath=Join-Path $k3.FixturePath 'meta.md';$policyFoundationPath=Join-Path $k3.FixturePath '00-fundament-projektu.md';$policyArchitecturePath=Join-Path $k3.FixturePath '02-architektura-odcinka.md'
    $policyMetaBytes=[IO.File]::ReadAllBytes($policyMetaPath);$policyFoundationBytes=[IO.File]::ReadAllBytes($policyFoundationPath);$policyArchitectureBytes=[IO.File]::ReadAllBytes($policyArchitecturePath)
    $researchPolicyRejected=$false;$k2bPolicyRejected=$false;$policyNoMutation=$true
    try{
        $policyMeta=Get-Content -LiteralPath $policyMetaPath -Raw -Encoding UTF8;$policyMeta=[regex]::Replace($policyMeta,'(?m)^RESEARCH_MODE:\s*.*$','RESEARCH_MODE: sources_only',1);[IO.File]::WriteAllText($policyMetaPath,$policyMeta,[Text.UTF8Encoding]::new($false))
        $policyFoundation=Get-Content -LiteralPath $policyFoundationPath -Raw -Encoding UTF8;$policyFoundation=[regex]::Replace($policyFoundation,'(?m)^- TRYB RESEARCHU:\s*.*$','- TRYB RESEARCHU: sources_only',1);$policyFoundation=[regex]::Replace($policyFoundation,'(?m)^- ZGODA NA WEB:\s*.*$','- ZGODA NA WEB: TYLKO PO POTWIERDZENIU DAWIDA',1);[IO.File]::WriteAllText($policyFoundationPath,$policyFoundation,[Text.UTF8Encoding]::new($false))
        $researchBefore=Get-TreeFingerprint $k3.FixturePath;$researchState=& (Join-Path $tempTools 'Validate-NarrativeV2Project.ps1') -ProjectPath $k3.FixturePath -NoExit;$researchAdvanceRejected=$false
        try{$null=& (Join-Path $tempTools 'Advance-Stage.ps1') -ProjectPath $k3.FixturePath -Apply}catch{$researchAdvanceRejected=$true}
        $researchPolicyRejected=([string]$researchState.Verdict -ceq 'FAIL') -and (($researchState.ErrorDetails -join ';') -match 'RESEARCH_MODE_INVALID') -and $researchAdvanceRejected
        $policyNoMutation=$policyNoMutation -and (((Get-TreeFingerprint $k3.FixturePath)-join "`n") -ceq ($researchBefore-join "`n"))
    }finally{[IO.File]::WriteAllBytes($policyMetaPath,$policyMetaBytes);[IO.File]::WriteAllBytes($policyFoundationPath,$policyFoundationBytes)}
    try{
        $policyMeta=Get-Content -LiteralPath $policyMetaPath -Raw -Encoding UTF8;$policyMeta=[regex]::Replace($policyMeta,'(?m)^K2B_DECISION:\s*.*$','K2B_DECISION: suplement wymagany',1);[IO.File]::WriteAllText($policyMetaPath,$policyMeta,[Text.UTF8Encoding]::new($false))
        $architectureText=Get-Content -LiteralPath $policyArchitecturePath -Raw -Encoding UTF8;$jsonMatch=[regex]::Match($architectureText,'(?s)(?<=<!--\s*NARRATIVE_V2_JSON_BEGIN\s*-->\s*```json\s*).*?(?=\s*```\s*<!--\s*NARRATIVE_V2_JSON_END\s*-->)');if(-not $jsonMatch.Success){throw 'K2B_POLICY_JSON_MISSING'}
        $architectureData=$jsonMatch.Value|ConvertFrom-Json -DateKind String -Depth 64;$architectureData.k2b.decision='suplement wymagany';$architectureData.k2b.gaps=@();$caseJson=ConvertTo-SystemV7CanonicalJson -Value $architectureData;$architectureText=$architectureText.Substring(0,$jsonMatch.Index)+$caseJson+$architectureText.Substring($jsonMatch.Index+$jsonMatch.Length);[IO.File]::WriteAllText($policyArchitecturePath,$architectureText,[Text.UTF8Encoding]::new($false))
        $k2bBefore=Get-TreeFingerprint $k3.FixturePath;$k2bState=& (Join-Path $tempTools 'Validate-NarrativeV2Project.ps1') -ProjectPath $k3.FixturePath -NoExit;$k2bAdvanceRejected=$false
        try{$null=& (Join-Path $tempTools 'Advance-Stage.ps1') -ProjectPath $k3.FixturePath -Apply}catch{$k2bAdvanceRejected=$true}
        $k2bPolicyRejected=([string]$k2bState.Verdict -ceq 'FAIL') -and (($k2bState.ErrorDetails -join ';') -match 'K2B_DECISION_INVALID') -and $k2bAdvanceRejected
        $policyNoMutation=$policyNoMutation -and (((Get-TreeFingerprint $k3.FixturePath)-join "`n") -ceq ($k2bBefore-join "`n"))
    }finally{[IO.File]::WriteAllBytes($policyMetaPath,$policyMetaBytes);[IO.File]::WriteAllBytes($policyArchitecturePath,$policyArchitectureBytes)}
    Assert-True ($researchPolicyRejected -and $k2bPolicyRejected) 'POLICY_CASE_ENUM_NOT_REJECTED'
    Assert-True $policyNoMutation 'POLICY_CASE_REJECTION_MUTATED_PROJECT'

    # Narrative V2 nie może reaktywować starego wyjątku długości nawet przez
    # publiczny, współdzielony entrypoint legacy.
    $budgetBefore=Get-TreeFingerprint $k3.FixturePath;$budgetOverrideRejected=$true
    foreach($budgetCase in @('K3_BUDGET_OVERRIDE','k3_budget_override','K3_Budget_Override')){
        $caseRejected=$false
        try{
            $null=& (Join-Path $tempTools 'Approve-EditorialException.ps1') -ProjectPath $k3.FixturePath -ExceptionType $budgetCase -TargetId ACT-001 `
                -Decision ALLOW_BUDGET_OVERRIDE -Reason 'Regresyjna próba starego limitu długości.' -Scope 'CAŁY_AKT' -DawidApproved
        }catch{$caseRejected=$_.Exception.Message -match '^K3_BUDGET_OVERRIDE_FORBIDDEN_IN_NARRATIVE_V2$'}
        $budgetOverrideRejected=$budgetOverrideRejected -and $caseRejected
    }
    Assert-True $budgetOverrideRejected 'K3/BUDGET_OVERRIDE_NOT_REJECTED'
    Assert-True (((Get-TreeFingerprint $k3.FixturePath)-join "`n") -ceq ($budgetBefore-join "`n")) 'K3/BUDGET_OVERRIDE_MUTATED_PROJECT'

    # Jeden uczciwy kierunek jest legalny wyłącznie z hash-bound decyzją Dawida.
    $oneDirectionBefore=Get-TreeFingerprint $k3.FixturePath;$architecturePath=Join-Path $k3.FixturePath '02-architektura-odcinka.md';$architectureExact=[IO.File]::ReadAllBytes($architecturePath)
    $exceptionDir=Join-Path $k3.FixturePath '_work\system\editorial-exceptions';$exceptionDirExisted=Test-Path -LiteralPath $exceptionDir -PathType Container;$oneDirectionReceipt=$null;$oneDirectionValid=$false
    try{
        $architectureText=[Text.UTF8Encoding]::new($false,$true).GetString($architectureExact);$jsonMatch=[regex]::Match($architectureText,'(?s)(?<=<!--\s*NARRATIVE_V2_JSON_BEGIN\s*-->\s*```json\s*).*?(?=\s*```\s*<!--\s*NARRATIVE_V2_JSON_END\s*-->)')
        if(-not $jsonMatch.Success){throw 'TEST_ONE_DIRECTION_JSON_MISSING'}
        $architectureData=$jsonMatch.Value|ConvertFrom-Json -DateKind String -Depth 64;$directionId=[string]$architectureData.directions[0].direction_id;$architectureData.directions=@($architectureData.directions[0]);$architectureData.selected_direction=$directionId
        $oneReason='Jedyny uczciwy kierunek wynika z dostępnych dowodów.';$oneJson=$architectureData|ConvertTo-Json -Depth 64
        $oneText=$architectureText.Substring(0,$jsonMatch.Index)+$oneJson+$architectureText.Substring($jsonMatch.Index+$jsonMatch.Length)
        $oneText=[regex]::Replace($oneText,'(?m)^WYBRANY_KIERUNEK:[ \t]*.*$',"WYBRANY_KIERUNEK: $directionId",1)
        $oneText=[regex]::Replace($oneText,'(?m)^ONE_DIRECTION_APPROVAL:[ \t]*.*$',"ONE_DIRECTION_APPROVAL: DAWID=TAK; POWÓD=$oneReason",1)
        [IO.File]::WriteAllText($architecturePath,$oneText,[Text.UTF8Encoding]::new($false))
        $oneDirectionReceipt=& (Join-Path $tempTools 'Approve-EditorialException.ps1') -ProjectPath $k3.FixturePath -ExceptionType k2_one_direction -TargetId $directionId -Decision ALLOW_ONE_DIRECTION -Reason $oneReason -Scope JEDEN_KIERUNEK -DawidApproved
        $oneState=& { . (Join-Path $tempTools 'Project-Origin.ps1');. (Join-Path $tempTools 'Integrity-Receipts.ps1');. (Join-Path $tempTools 'Narrative-V2.ps1');Test-SystemV7NarrativeArchitecture -ArchitecturePath $architecturePath -EvidencePath (Join-Path $k3.FixturePath '01-baza-dowodow.md') }
        $oneDirectionValid=$oneState.GateReady -and @($oneState.ErrorDetails).Count -eq 0
    }finally{
        [IO.File]::WriteAllBytes($architecturePath,$architectureExact)
        if($oneDirectionReceipt -and (Test-Path -LiteralPath $oneDirectionReceipt.ReceiptPath -PathType Leaf)){[IO.File]::Delete($oneDirectionReceipt.ReceiptPath)}
        if(-not $exceptionDirExisted -and (Test-Path -LiteralPath $exceptionDir -PathType Container) -and @(Get-ChildItem -LiteralPath $exceptionDir -Force).Count -eq 0){[IO.Directory]::Delete($exceptionDir)}
    }
    Assert-True $oneDirectionValid 'K2/ONE_DIRECTION_RECEIPT_NOT_ACCEPTED'
    Assert-True (((Get-TreeFingerprint $k3.FixturePath)-join "`n") -ceq ($oneDirectionBefore-join "`n")) 'K2/ONE_DIRECTION_TEST_NOT_RESTORED'

    $legacyK4Before=Get-TreeFingerprint $k3.FixturePath;$legacyK4CreatorRejected=$false;$legacyK4ExceptionRejected=$false
    try{$null=& (Join-Path $tempTools 'New-K4VerifyReceipt.ps1') -ProjectPath $k3.FixturePath -VerifyAgentId AGENT-X -TaskId TASK-00000001 -Note 'Regresyjna próba V1 w V2.' -ConfirmIndependentVerify}catch{$legacyK4CreatorRejected=$_.Exception.Message -match '^LEGACY_K4_VERIFY_RECEIPT_FORBIDDEN_IN_NARRATIVE_V2$'}
    try{$null=& (Join-Path $tempTools 'Approve-EditorialException.ps1') -ProjectPath $k3.FixturePath -ExceptionType k4_q1_acceptance -TargetId QA-001 -Decision ACCEPT_Q1 -Reason 'Regresyjna próba wyjątku V1 w V2.' -Scope QA_Q1 -DawidApproved}catch{$legacyK4ExceptionRejected=$_.Exception.Message -match '^LEGACY_K4_EXCEPTION_FORBIDDEN_IN_NARRATIVE_V2$'}
    Assert-True ($legacyK4CreatorRejected -and $legacyK4ExceptionRejected) 'K4/LEGACY_V1_ENTRYPOINT_NOT_REJECTED'
    Assert-True (((Get-TreeFingerprint $k3.FixturePath)-join "`n") -ceq ($legacyK4Before-join "`n")) 'K4/LEGACY_V1_REJECTION_MUTATED_PROJECT'

    # To jest regresja prawdziwego entrypointu, nie samego helpera: po zmianie
    # chronionej instrukcji Start-* musi zatrzymać się przed lockiem i bundle.
    $agentsPath=Join-Path $tempSystemRoot 'AGENTS.md';$agentsExact=[IO.File]::ReadAllBytes($agentsPath);$entrypointBefore=Get-TreeFingerprint $k3.FixturePath;$realEntrypointTamperRejected=$false
    try{
        [IO.File]::WriteAllText($agentsPath,([Text.UTF8Encoding]::new($false,$true).GetString($agentsExact)+"`nTAMPER_REAL_ENTRYPOINT`n"),[Text.UTF8Encoding]::new($false))
        try{$null=& (Join-Path $tempTools 'Start-K3ConstraintPreflight.ps1') -ProjectPath $k3.FixturePath -ActId ACT-001 -RunId 'TAMPER-GUARD-0001'}catch{$realEntrypointTamperRejected=$_.Exception.Message -match '^NARRATIVE_INSTRUCTION_CONTRACT_INVALID:'}
    }finally{[IO.File]::WriteAllBytes($agentsPath,$agentsExact)}
    Assert-True $realEntrypointTamperRejected 'INSTRUCTION_CONTRACT/REAL_ENTRYPOINT_TAMPER_NOT_REJECTED'
    Assert-True (((Get-TreeFingerprint $k3.FixturePath)-join "`n") -ceq ($entrypointBefore-join "`n")) 'INSTRUCTION_CONTRACT/REAL_ENTRYPOINT_TAMPER_MUTATED_PROJECT'
    $instructionAfterRealEntry=& { . (Join-Path $tempTools 'Project-Origin.ps1');. (Join-Path $tempTools 'Narrative-V2.ps1');Get-SystemV7NarrativeInstructionContractState -SystemRoot $tempSystemRoot }
    Assert-True $instructionAfterRealEntry.Valid 'INSTRUCTION_CONTRACT/REAL_ENTRYPOINT_RESTORE_INVALID'

    $atomic=& (Join-Path $tempFixtures 'Test-NarrativeV2.Atomicity.ps1') -SystemRoot $tempSystemRoot -ProjectPath $k3.FixturePath
    Assert-True ([int]$atomic.Total -ge 11) 'ATOMICITY/MINIMUM_CASE_COUNT'
    Assert-True ([int]$atomic.Passed -eq [int]$atomic.Total) 'ATOMICITY/MATRIX'
    Assert-True (@($atomic.Cases|Where-Object{-not $_.Pass}).Count -eq 0) 'ATOMICITY/FALSE_PASS'

    $semanticPreflight=& (Join-Path $tempFixtures 'Test-NarrativeV2.SemanticPreflight.ps1') -SystemRoot $tempSystemRoot -FixtureRoot (Join-Path $runRoot 'semantic-preflight')
    Assert-UnderRunRoot (Join-Path $runRoot 'semantic-preflight') 'SEMANTIC_PREFLIGHT_FIXTURE'
    Assert-True ([int]$semanticPreflight.Total -eq 5 -and [int]$semanticPreflight.Passed -eq 5 -and [int]$semanticPreflight.Failed -eq 0) 'SEMANTIC_PREFLIGHT/MATRIX'
    Assert-True (@($semanticPreflight.Cases|Where-Object{-not $_.Pass}).Count -eq 0) 'SEMANTIC_PREFLIGHT/FALSE_PASS'

    $invalidation=& (Join-Path $tempFixtures 'Test-NarrativeV2.Invalidation.ps1') -SystemRoot $tempSystemRoot -FixtureRoot (Join-Path $runRoot 'invalidation') -VoiceProfilePath $voice.ApprovedProfilePath
    Assert-UnderRunRoot $invalidation.CacheProjectPath 'INVALIDATION_CACHE_PROJECT';Assert-UnderRunRoot $invalidation.LocalProjectPath 'INVALIDATION_LOCAL_PROJECT';Assert-UnderRunRoot $invalidation.GlobalProjectPath 'INVALIDATION_GLOBAL_PROJECT'
    foreach($name in @('CacheArchitectureGateReady','OtherActPacketStable','UnusedEvidencePacketStable','SelectedEvidencePacketInvalidated','PrefixStableAcrossLocalEdits','LocalBytesPreserved','LocalAffectedRemoved','LocalArchiveComplete','LocalMetaPreserved','LocalHeadValid','GlobalK3Removed','GlobalArchiveComplete','GlobalMetaCleared','GlobalHeadValid')){Assert-True ([bool]$invalidation.$name) "INVALIDATION/$name"}
    Assert-True ([string]$invalidation.LocalReopenStatus -ceq 'STAGE_REOPENED' -and [string]$invalidation.LocalFromActId -ceq 'ACT-003') 'INVALIDATION/LOCAL_ROUTE'
    Assert-True ([string]$invalidation.GlobalReopenStatus -ceq 'STAGE_REOPENED' -and [string]$invalidation.GlobalFromActId -ceq 'ALL') 'INVALIDATION/GLOBAL_ROUTE'

    $moveRepetition=& (Join-Path $tempFixtures 'Test-NarrativeV2.MoveRepetition.ps1') -SystemRoot $tempSystemRoot -FixtureRoot (Join-Path $runRoot 'move-repetition')
    Assert-UnderRunRoot $moveRepetition.ProjectPath 'MOVE_REPETITION_PROJECT'
    foreach($name in @('NoRepeatPass','RepeatReviewAlert','K4Blocked','ValidatorBlocked','NoRunsCreated','NoFlagFailed','NoFlagNoMutation','ApprovalReceiptExists','ApprovedGateReady','CrossProjectReplayRejected','ChangedOutInvalidates','RestoreRevalidates')){Assert-True ([bool]$moveRepetition.$name) "MOVE_REPETITION/$name"}
    Assert-True ([string]$moveRepetition.ApprovalStatus -ceq 'CONSCIOUS_REPETITION_APPROVED') 'MOVE_REPETITION/APPROVAL_STATUS'

    $prefix=& (Join-Path $tempFixtures 'Test-NarrativeV2.PrefixStale.ps1') -SystemRoot $tempSystemRoot -ProjectPath $k3.FixturePath -ProfilePath $voice.ApprovedProfilePath -SourceProjectPath $voice.SourceProjectPath -ExactText $voice.ExactShort -FixtureRoot (Join-Path $runRoot 'prefix-stale')
    foreach($name in @('BaselineProfileValid','MutantProfileValid','StaleDetected','RestoreProfileValid','RestoreMatchesBaseline')){Assert-True ([bool]$prefix.$name) "PREFIX/$name"}
    Assert-True (@($prefix.BaselineRelevantErrors).Count -eq 0 -and @($prefix.RestoredRelevantErrors).Count -eq 0) 'PREFIX/BASELINE_OR_RESTORE_ERRORS'

    $k4Exact=& (Join-Path $tempFixtures 'Test-NarrativeV2.K4Exact.ps1') -SystemRoot $tempSystemRoot -FixtureRoot (Join-Path $runRoot 'k4-exact')
    Assert-UnderRunRoot $k4Exact.FixturePath 'K4_EXACT_PROJECT'
    Assert-True ([int]$k4Exact.Total -ge 50 -and [int]$k4Exact.Passed -eq [int]$k4Exact.Total -and [int]$k4Exact.Failed -eq 0) 'K4_EXACT/MATRIX'
    Assert-True (@($k4Exact.Cases|Where-Object{-not $_.Pass}).Count -eq 0) 'K4_EXACT/FALSE_PASS'

    $carry=& (Join-Path $tempFixtures 'Test-NarrativeV2.Carry.ps1') -SystemRoot $tempSystemRoot -FixtureRoot (Join-Path $runRoot 'carry')
    Assert-UnderRunRoot $carry.FixturePath 'CARRY_PROJECT'
    foreach($name in @('BaselineBExists','BaselineBReceiptExists','CarryABCreated','CarryABProofResolutionValid','RootRawAndCleanDiffer','Creator2Succeeded','Creator2HeadValid','Creator2ProofResolutionValid','PriorAtDepth1Valid','ManualHeadValid')){Assert-True ([bool]$carry.$name) "CARRY/$name"}
    Assert-True (-not [bool]$carry.RootOutputAgainstCleanIdentityValid) 'CARRY/CLEAN_SNAPSHOT_FALSE_PASS'
    Assert-True (-not [bool]$carry.PriorAtDepth0Valid) 'CARRY/HISTORICAL_LIVE_FALSE_PASS'
    Assert-True ([string]$carry.RootRawDraftIdentitySha256 -ceq [string]$carry.ShaA) 'CARRY/ROOT_RAW_IDENTITY'

    $k4k5=& (Join-Path $tempFixtures 'Test-NarrativeV2.K4K5.ps1') -SystemRoot $tempSystemRoot -ProjectPath $k3.FixturePath -FixtureRoot (Join-Path $runRoot 'k4-k5')
    Assert-UnderRunRoot $k4k5.ProjectPath 'K4K5_PROJECT'
    foreach($name in @('EditorValid','VerifyValid','ColdReaderValid','VerifyMissingRejected','EditorGenericRejected','ColdBrakRejected','ProofSetValid','TelemetryProviderPass','CacheMissNonBlocking','TelemetryFailureNonBlocking','TelemetryDefaultPass','EditorSemanticAEmpty','EditorSemanticBAlert','EditorCarryDependencyRejected','EditorCarryNoReceipt','EditorDependencyRestore','EditorProofRestore','ResidueRejected','ResidueCreatedNoReceipt','NoFlagRejected','K5Valid','FinalMatchesClean','K5TamperRejected','K5RestoreValid','OfficialK3ToK4','OfficialK4ToK5','OfficialK5ToComplete','CompleteValidationPass','CompleteMetaExact')){Assert-True ([bool]$k4k5.$name) "K4K5/$name"}

    . (Join-Path $tempSystemRoot 'tools/Narrative-Receipts.ps1')
    $efficiency=& (Join-Path $tempSystemRoot 'tools/Test-NarrativeEfficiency.ps1') -PythonPath $PythonPath
    Assert-True ($efficiency.Verdict -ceq 'PASS') 'EFFICIENCY_UNIT_CHECKS'
    $newBundles=0;$templateTamperChecks=0
    foreach($manifest in @(Get-ChildItem -LiteralPath (Join-Path $k4k5.ProjectPath '_work/narrative-runs') -Filter input-manifest.json -Recurse)){
        $bundleData=Get-Content -LiteralPath $manifest.FullName -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        if([string]$bundleData.run_type -notin @('EDITOR','VERIFY','COLD_READER')){continue}
        $context=@($bundleData.entries|Where-Object content_role -CEQ 'RUN_CONTEXT')
        if($context.Count -eq 0){continue}
        $template=@($bundleData.entries|Where-Object content_role -CEQ 'RESPONSE_TEMPLATE')
        Assert-True ($template.Count -eq 1) 'K4_TEMPLATE_MISSING'
        $state=Get-SystemV7NarrativeInputBundleState -ProjectPath $k4k5.ProjectPath -ManifestPath $manifest.FullName
        Assert-True $state.Valid 'K4_ENRICHED_BUNDLE_INVALID'
        $text=Get-Content -LiteralPath (Join-Path $k4k5.ProjectPath $template[0].bundle_relative) -Raw -Encoding UTF8
        Assert-True ($text.Contains('VERDICT: <PASS|FAIL>') -and $text.Contains('DRAFT_SHA256: ')) 'K4_TEMPLATE_PREMATURE_PASS'
        if($newBundles -eq 0){
            foreach($role in @('RUN_CONTEXT','RESPONSE_TEMPLATE')){
                $manifestBefore=[IO.File]::ReadAllBytes($manifest.FullName)
                $entry=@($bundleData.entries|Where-Object content_role -CEQ $role)[0]
                $target=Join-Path $k4k5.ProjectPath $entry.bundle_relative
                $before=[IO.File]::ReadAllBytes($target)
                try{
                    $altered=if($role -eq 'RUN_CONTEXT'){[Text.Encoding]::UTF8.GetString($before) -replace '[A-F0-9]{64}',('0'*64)}else{[Text.Encoding]::UTF8.GetString($before).Replace('<PASS|FAIL>','PASS')}
                    [IO.File]::WriteAllText($target,$altered,[Text.UTF8Encoding]::new($false))
                    $entry.sha256=(Get-FileHash -LiteralPath $target).Hash;$entry.bytes=(Get-Item -LiteralPath $target).Length
                    $core=[ordered]@{schema=$bundleData.schema;workflow_revision=$bundleData.workflow_revision;run_type=$bundleData.run_type;run_id=$bundleData.run_id;input_profile=$bundleData.input_profile;entries=@($bundleData.entries)}
                    $bundleData.input_manifest_sha256=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $core)
                    [IO.File]::WriteAllText($manifest.FullName,(ConvertTo-SystemV7CanonicalJson -Value $bundleData),[Text.UTF8Encoding]::new($false))
                    $bad=Get-SystemV7NarrativeInputBundleState -ProjectPath $k4k5.ProjectPath -ManifestPath $manifest.FullName
                    $expectedError=if($role -eq 'RUN_CONTEXT'){'K4_RUN_CONTEXT_BINDING_INVALID'}else{'RESPONSE_TEMPLATE_BINDING_INVALID'}
                    Assert-True (-not $bad.Valid -and $bad.Errors -contains $expectedError) 'K4_TEMPLATE_FORGED_MANIFEST_ACCEPTED'
                    $templateTamperChecks++
                }finally{
                    [IO.File]::WriteAllBytes($target,$before);[IO.File]::WriteAllBytes($manifest.FullName,$manifestBefore)
                    $bundleData=Get-Content -LiteralPath $manifest.FullName -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
                }
            }
        }
        $newBundles++
    }
    Assert-True ($newBundles -ge 3) 'K4_ENRICHED_BUNDLES_NOT_EXERCISED'
    foreach($command in @(Get-ChildItem -LiteralPath $runRoot -Filter '*.write-command.md' -Recurse)){
        $text=Get-Content -LiteralPath $command.FullName -Raw -Encoding UTF8
        Assert-True ($text -notmatch '(?m)^(q_nr_vc_ids|r_evidence_p)') 'K3_COMMAND_IDENTIFIER_DAMAGED'
    }
    $protectedSourceAfter=Get-TreeFingerprint $protectedSourceRoot
    Assert-True (($protectedSourceAfter -join "`n") -ceq ($protectedSourceBefore -join "`n")) 'CANONICAL_VOICE_PROFILE_TREE_MUTATED'
    $durableSourceAfter=Get-DurableSourceFingerprint $sourceSystemRoot
    $durableSourceDiff=@(Compare-Object -ReferenceObject $durableSourceBefore -DifferenceObject $durableSourceAfter)
    $durableDiffHint=@($durableSourceDiff|Select-Object -First 6|ForEach-Object{"$($_.SideIndicator)$($_.InputObject)"}) -join ';'
    Assert-True ($durableSourceDiff.Count -eq 0) "DURABLE_PRODUCTION_TREE_MUTATED/$durableDiffHint"
    $started.Stop()
    $result=[pscustomobject]@{
        Efficiency=[pscustomobject]@{Checks=$efficiency.Checks;EnrichedBundles=$newBundles;TamperChecks=$templateTamperChecks}
        Verdict='PASS';DurationSeconds=[math]::Round($started.Elapsed.TotalSeconds,2)
        SourceSystemRoot=$sourceSystemRoot;FixtureRoot=if($KeepFixture){$runRoot}else{'REMOVED_AFTER_PASS'}
        ProductionTreeUnchanged=$true;TempOnly=$true;Cleanup=if($KeepFixture){'SKIPPED_BY_SWITCH'}else{'PENDING'}
        Dispatch=[pscustomobject]@{LegacyRevision=(Get-MetaField $legacyProject 'WORKFLOW_REVISION');V2Revision=(Get-MetaField $v2Project 'WORKFLOW_REVISION');V2Activation=(Get-MetaField $v2Project 'WORKFLOW_ACTIVATION');ReadOnly=$true}
        InstructionContract=[pscustomobject]@{MarkerRejected=$instructionContract.MarkerRejected;RouteRejected=$instructionContract.RouteRejected;StatusRejected=$instructionContract.StatusRejected;ControlledFileRejected=$instructionContract.ControlledFileRejected;ManifestHashRejected=$instructionContract.ManifestHashRejected;ManifestAllowlistRejected=$instructionContract.ManifestAllowlistRejected;RealEntrypointRejected=$realEntrypointTamperRejected;Restored=($instructionContract.ExactRestore -and $instructionAfterRealEntry.Valid)}
        SourceManifest=[pscustomobject]@{RevisionAndOriginRereadUnderLock=$sourceManifestRereadGuard;RaceHookStatus='STATIC_GUARD_NO_AUTHORIZED_PRELOCK_HOOK'}
        Voice=[pscustomobject]@{ExemplarWordCount=$voice.ExemplarWordCount;ProfileApproval=$voice.PositiveProfileValid;SelectionRollback=$voice.SelectionRollbackNoMutation;ApprovalRollback=$voice.ApprovalRollbackNoMutation}
        Duration=[pscustomobject]@{LegalW0ToK0=$duration.AdvanceApplied;ReceiptClean=$duration.BaselineDurationClean;MetaTamperRejected=$duration.MetaTamperRejected;FoundationTamperRejected=$duration.FoundationTamperRejected;RestoreExact=$duration.RestoreExact}
        Atomicity=[pscustomobject]@{Passed=$atomic.Passed;Total=$atomic.Total}
        SemanticPreflight=[pscustomobject]@{Passed=$semanticPreflight.Passed;Total=$semanticPreflight.Total;NoAlert=$semanticPreflight.Cases[0].Pass;ExemplarAlert=$semanticPreflight.Cases[1].Pass;DirectContactAlert=$semanticPreflight.Cases[2].Pass;PlannedContactPass=$semanticPreflight.Cases[3].Pass;HumorForbiddenFail=$semanticPreflight.Cases[4].Pass}
        Invalidation=[pscustomobject]@{OtherActPacketStable=$invalidation.OtherActPacketStable;UnusedEvidencePacketStable=$invalidation.UnusedEvidencePacketStable;SelectedEvidencePacketInvalidated=$invalidation.SelectedEvidencePacketInvalidated;LocalReopenPreserved=$invalidation.LocalBytesPreserved;GlobalReopenCleared=$invalidation.GlobalK3Removed}
        MoveRepetition=[pscustomobject]@{NoRepeatPass=$moveRepetition.NoRepeatPass;UnresolvedBlocksK4=$moveRepetition.K4Blocked;ValidatorAlert=$moveRepetition.ValidatorBlocked;DawidReceipt=$moveRepetition.ApprovedGateReady;CrossProjectReplayRejected=$moveRepetition.CrossProjectReplayRejected;OutChangeInvalidates=$moveRepetition.ChangedOutInvalidates}
        ComplexK3=[pscustomobject]@{Assembly=$k3.AssemblyStatus;Blocks=@($k3.MappedBlocks).Count;MapTamperRejected=$k3.TamperDetected;BudgetOverrideRejected=$budgetOverrideRejected;OneDirectionReceipt=$oneDirectionValid}
        K4=[pscustomobject]@{ExactPassed=$k4Exact.Passed;ExactTotal=$k4Exact.Total;CarryTwoHop=$carry.Creator2ProofResolutionValid;EditorSemanticDependencyReject=$k4k5.EditorCarryDependencyRejected;EditorSemanticNewAlert=$k4k5.EditorSemanticBAlert;ProofSet=$k4k5.ProofSetValid;TelemetryProvider=$k4k5.TelemetryProviderPass;CacheMissNonBlocking=$k4k5.CacheMissNonBlocking;TelemetryFailureNonBlocking=$k4k5.TelemetryFailureNonBlocking}
        K5=[pscustomobject]@{Approval=$k4k5.K5Valid;CleanFinal=$k4k5.FinalMatchesClean;TamperRejected=$k4k5.K5TamperRejected;OfficialChain="$($k4k5.OfficialK3ToK4)/$($k4k5.OfficialK4ToK5)/$($k4k5.OfficialK5ToComplete)";CompleteValidation=$k4k5.CompleteValidationPass;CompleteMetaExact=$k4k5.CompleteMetaExact}
        HumanABStatus='NOT_TESTED_REQUIRES_REAL_DAWID_DECISIONS';CanonicalVoiceProfileStatus='NOT_CHANGED_TEMP_FIXTURE_ONLY'
        CriticalSourceSha256=$criticalSource
    }
} catch {
    $caught=$_
} finally {
    if(-not $KeepFixture -and (Test-Path -LiteralPath $runRoot -PathType Container)){
        Assert-TempRoot $runRoot
        $item=Get-Item -LiteralPath $runRoot -Force;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'TEST_ROOT_REPARSE_BLOCKED'}
        foreach($entry in @(Get-ChildItem -LiteralPath $runRoot -Force -Recurse -ErrorAction Stop)){
            if($entry.Attributes -band [IO.FileAttributes]::ReadOnly){$entry.Attributes=$entry.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)}
        }
        [IO.Directory]::Delete($runRoot,$true);$cleanup='PASS'
    }elseif($KeepFixture){$cleanup='SKIPPED_BY_SWITCH'}else{$cleanup='NOT_NEEDED'}
}

if($caught){throw $caught}
if($result){$result.Cleanup=$cleanup;$result}
