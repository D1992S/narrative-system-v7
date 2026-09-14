[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$EditorRunId,
    [Parameter(Mandatory)][string]$VerifyRunId,
    [Parameter(Mandatory)][string]$ColdReaderRunId
)

$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
$systemRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project -SystemRoot $systemRoot | Out-Null

if(@(@($EditorRunId,$VerifyRunId,$ColdReaderRunId)|Select-Object -Unique).Count -ne 3){throw 'K4_RUN_IDS_MUST_BE_UNIQUE'}
foreach($runId in @($EditorRunId,$VerifyRunId,$ColdReaderRunId)){if($runId -notmatch '^[A-Z0-9][A-Z0-9._-]{7,80}$'){throw "RUN_ID_INVALID: $runId"}}

$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
$createdFiles=[Collections.Generic.List[string]]::new()
$createdRunRoots=[Collections.Generic.List[string]]::new()
$trackedInputs=@{}
$trackInput={
    param([string]$Path,[string]$Code)
    $full=[IO.Path]::GetFullPath($Path)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "K4_INPUT_MISSING: $Code/$full"}
    $null=Assert-SystemV7PathNoReparse -Path $full -ContainmentRoot $project
    $sha=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    if($trackedInputs.ContainsKey($full) -and [string]$trackedInputs[$full] -cne $sha){throw "K4_INPUT_CHANGED_DURING_READ: $Code"}
    $trackedInputs[$full]=$sha
    return $sha
}
$ensureImmutableBytes={
    param([string]$Path,[byte[]]$Bytes,[string]$Code)
    $full=[IO.Path]::GetFullPath($Path);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $full
    $expected=Get-Sha256HexFromBytes -Bytes $Bytes
    if(Test-Path -LiteralPath $full -PathType Leaf){if((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -cne $expected){throw "K4_IMMUTABLE_DERIVED_COLLISION: $Code/$full"};return $full}
    [IO.Directory]::CreateDirectory((Split-Path -Parent $full))|Out-Null
    $temp=Join-Path (Split-Path -Parent $full) ('.k4-stage-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{[IO.File]::WriteAllBytes($temp,$Bytes);[IO.File]::Move($temp,$full);$createdFiles.Add($full)}finally{if(Test-Path -LiteralPath $temp -PathType Leaf){[IO.File]::Delete($temp)}}
    if((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -cne $expected){throw "K4_DERIVED_WRITE_VERIFY_FAILED: $Code"}
    return $full
}
$ensureImmutableText={param([string]$Path,[string]$Text,[string]$Code)&$ensureImmutableBytes $Path ([Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-SystemV7LfText -Text $Text))) $Code}

try{
    $metaPath=Join-Path $project 'meta.md';$draftPath=Join-Path $project '03-draft.md';$architecturePath=Join-Path $project '02-architektura-odcinka.md';$evidencePath=Join-Path $project '01-baza-dowodow.md';$fundamentPath=Join-Path $project '00-fundament-projektu.md'
    foreach($pair in @(@($metaPath,'META'),@($draftPath,'DRAFT'),@($architecturePath,'ARCHITECTURE'),@($evidencePath,'EVIDENCE'),@($fundamentPath,'FUNDAMENT'))){$null=&$trackInput $pair[0] $pair[1]}
    $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $null=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
    if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'START_K4_LENSES_WRONG_WORKFLOW'}
    if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K4'){throw 'START_K4_LENSES_REQUIRES_STAGE_K4'}
    if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CONTINUITY_STATUS') -cne 'COMPLETE'){throw 'CONTINUITY_CHAIN_INCOMPLETE'}
    $moveReview=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project
    if(-not $moveReview.Valid){throw "MOVE_REPETITION_REVIEW_INVALID: $($moveReview.Errors -join '; ')"}
    if(-not $moveReview.GateReady){throw "MOVE_REPETITION_REVIEW_ALERT: $($moveReview.ReviewAlerts|ConvertTo-Json -Compress -Depth 12)"}
    if($moveReview.DecisionSha256 -ne 'BRAK'){$null=&$trackInput $moveReview.DecisionPath 'MOVE_REPETITION_DECISION'}
    foreach($runId in @($EditorRunId,$VerifyRunId,$ColdReaderRunId)){$runRoot=Join-Path $project "_work\narrative-runs\$runId";if(Test-Path -LiteralPath $runRoot){throw "RUN_BUNDLE_ALREADY_EXISTS: $runId"}}

    $architectureState=Test-SystemV7NarrativeArchitecture -ArchitecturePath $architecturePath -EvidencePath $evidencePath
    if(-not $architectureState.GateReady){throw "K4_ARCHITECTURE_INVALID: $($architectureState.ErrorDetails -join '; ')"}
    $architecture=$architectureState.Architecture
    $draft=Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8;$draftSha=[string]$trackedInputs[[IO.Path]::GetFullPath($draftPath)]
    $clean=Get-SystemV7CleanNarrationFromDraft -DraftText $draft
    if($clean -match '(?i)#P-\d{3}|\bBLOCK-(?:ACT-)?\d|<!--|^#{1,6}\s'){throw 'CLEAN_NARRATION_EXPORT_CONTAMINATED'}
    $blockMatch=[regex]::Match($draft,'(?s)<!--\s*K3_BLOCK_MAP_BEGIN\s*-->\s*```json\s*(?<json>.*?)\s*```\s*<!--\s*K3_BLOCK_MAP_END\s*-->')
    if(-not $blockMatch.Success){throw 'DRAFT_BLOCK_MAP_MISSING'}
    try{$blockMap=$blockMatch.Groups['json'].Value|ConvertFrom-Json -DateKind String -Depth 64}catch{throw 'DRAFT_BLOCK_MAP_INVALID_JSON'}
    if([string]$blockMap.schema -cne 'K3_BLOCK_MAP_V1'){throw 'DRAFT_BLOCK_MAP_SCHEMA_INVALID'}

    $work=Join-Path $project '_work\k4\inputs';[IO.Directory]::CreateDirectory($work)|Out-Null
    $cleanPath=Join-Path $work "clean-narration-$draftSha.md";$null=&$ensureImmutableText $cleanPath $clean 'CLEAN_NARRATION'
    $blockMapPath=Join-Path $work "block-map-$draftSha.json";$null=&$ensureImmutableText $blockMapPath (ConvertTo-SystemV7CanonicalJson -Value $blockMap) 'BLOCK_MAP'
    $registries=[ordered]@{schema='K4_NQ_NR_VC_PROJECTION_V1';questions=@($architecture.Data.questions);reveals=@($architecture.Data.reveals);viewer_contacts=@($architecture.Data.viewer_contacts)}
    $registriesPath=Join-Path $work "nq-nr-vc-$draftSha.json";$null=&$ensureImmutableText $registriesPath (ConvertTo-SystemV7CanonicalJson -Value $registries) 'NQ_NR_VC'

    $sequence=@((Get-SystemV7NarrativeMetaField -Text $meta -Name 'NARRATIVE_ACT_SEQUENCE') -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_})
    $continuityRecords=[Collections.Generic.List[object]]::new()
    $semanticBlocks=[Collections.Generic.List[object]]::new()
    foreach($actId in $sequence){
        $attestPath=Join-Path $project "_work\k3\continuity\$actId.attest.json";$blocksPath=Join-Path $project "_work\k3\acts\$actId\blocks.json";$null=&$trackInput $attestPath "ATTEST/$actId";$null=&$trackInput $blocksPath "BLOCKS/$actId"
        $attestState=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $actId
        if(-not $attestState.Valid){throw "ATTEST_INVALID: $actId/$($attestState.Errors -join '; ')"}
        $actBlocks=Get-Content -LiteralPath $blocksPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
        foreach($block in @($actBlocks.blocks)){$semanticBlocks.Add([pscustomobject]@{act_id=$actId;block_id=[string]$block.block_id;narrative_refs=@([string[]]@($block.narrative_refs));prose=[string]$block.prose})}
        $continuityRecords.Add([ordered]@{act_id=$actId;relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $attestPath);sha256=$attestState.Sha256;record=$attestState.Data})
    }
    $chain=[ordered]@{schema='CONTINUITY_CHAIN_V1';draft_sha256=$draftSha;records=@($continuityRecords)}
    $chainPath=Join-Path $work "continuity-chain-$draftSha.json";$null=&$ensureImmutableText $chainPath (ConvertTo-SystemV7CanonicalJson -Value $chain) 'CONTINUITY_CHAIN'
    $chainState=Get-SystemV7K4ContinuityChainState -ProjectPath $project -DraftSha256 $draftSha;if(-not $chainState.Valid){throw "K4_CONTINUITY_CHAIN_INVALID: $($chainState.Errors -join '; ')"}

    $locator=Get-SystemV7EvidenceRegistry -EvidencePath $evidencePath
    $locatorValue=[ordered]@{schema='SOURCE_LOCATORS_V1';evidence_sha256=$locator.EvidenceSha256;cards=@($locator.Cards.Values|ForEach-Object{[ordered]@{p_id=$_.p_id;source_id=$_.source_id;locator=$_.locator;qa_k1=$_.qa_k1}})}
    $locatorPath=Join-Path $work "source-locators-$draftSha.json";$null=&$ensureImmutableText $locatorPath (ConvertTo-SystemV7CanonicalJson -Value $locatorValue) 'SOURCE_LOCATORS'

    $runContextPath=Join-Path $work "run-context-$draftSha.json"
    $null=&$ensureImmutableText $runContextPath (ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='K4_RUN_CONTEXT_V1';draft_sha256=$draftSha})) 'RUN_CONTEXT'
    $controlSpecs=@(
        @('editorCriteria','EDITOR-CRITERIA.md','editor-criteria'),@('editorOutputSchema','EDITOR-OUTPUT-SCHEMA.md','editor-output-schema'),
        @('verifyCriteria','VERIFY-CRITERIA.md','verify-criteria'),@('verifyOutputSchema','VERIFY-OUTPUT-SCHEMA.md','verify-output-schema'),
        @('coldQuestions','COLD-READER-QUESTIONS.md','cold-reader-questions'),@('coldOutputSchema','COLD-READER-OUTPUT-SCHEMA.md','cold-reader-output-schema')
    );$controlPaths=@{}
    foreach($spec in $controlSpecs){$source=Join-Path $systemRoot ('_SYSTEM\NARRATIVE\'+$spec[1]);if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "K4_CONTROL_SOURCE_MISSING: $source"};$bytes=[IO.File]::ReadAllBytes($source);$sha=Get-Sha256HexFromBytes -Bytes $bytes;$target=Join-Path $work ($spec[2]+'-'+$sha+'.md');$null=&$ensureImmutableBytes $target $bytes "CONTROL/$($spec[0])";$controlPaths[$spec[0]]=$target}

    $prefixDir=Join-Path $project '_work\k3\prefix';$sourceDir=Join-Path $project 'sources';$null=Assert-SystemV7TreeNoReparse -RootPath $sourceDir -ContainmentRoot $project
    foreach($pair in @(@((Join-Path $prefixDir 'PROJECT_STORY_SPINE.json'),'STORY_SPINE'),@((Join-Path $prefixDir 'VOICE_RULES.md'),'VOICE_RULES'),@((Join-Path $prefixDir 'VOICE_EXEMPLARS.md'),'VOICE_EXEMPLARS'))){$null=&$trackInput $pair[0] $pair[1]}
    $voiceExemplarsPath=Join-Path $prefixDir 'VOICE_EXEMPLARS.md';$semanticState=Get-SystemV7NarrativeSemanticPreflightState -ArchitectureData $architecture.Data -Blocks @($semanticBlocks) -VoiceExemplarsText (Get-Content -LiteralPath $voiceExemplarsPath -Raw -Encoding UTF8) -DraftSha256 $draftSha
    if(-not $semanticState.Valid){throw "K4_SEMANTIC_PREFLIGHT_FAIL: $($semanticState.Errors -join '; ')"}
    $semanticPath=Join-Path $work "semantic-preflight-$draftSha.json";$null=&$ensureImmutableText $semanticPath (ConvertTo-SystemV7CanonicalJson -Value $semanticState.Data) 'SEMANTIC_PREFLIGHT'

    $editor=New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType EDITOR -RunId $EditorRunId -Inputs @{
        RUN_CONTEXT=$runContextPath;FUNDAMENT=$fundamentPath;ARCHITECTURE=$architecturePath;CLEAN_DRAFT=$cleanPath;BLOCK_MAP=$blockMapPath;STORY_SPINE=Join-Path $prefixDir 'PROJECT_STORY_SPINE.json';NQ_NR_VC=$registriesPath
        VOICE_RULES=Join-Path $prefixDir 'VOICE_RULES.md';VOICE_EXEMPLARS=$voiceExemplarsPath;CONTINUITY_CHAIN=$chainPath;SEMANTIC_PREFLIGHT=$semanticPath;EDITOR_CRITERIA=$controlPaths.editorCriteria;EDITOR_OUTPUT_SCHEMA=$controlPaths.editorOutputSchema
    };$createdRunRoots.Add((Split-Path -Parent $editor.Path))
    $verify=New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType VERIFY -RunId $VerifyRunId -Inputs @{RUN_CONTEXT=$runContextPath;DRAFT_BLOCKS=$draftPath;EVIDENCE_BASE=$evidencePath;SOURCE_FILES=$sourceDir;SOURCE_LOCATORS=$locatorPath;VERIFY_CRITERIA=$controlPaths.verifyCriteria;VERIFY_OUTPUT_SCHEMA=$controlPaths.verifyOutputSchema};$createdRunRoots.Add((Split-Path -Parent $verify.Path))
    $cold=New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType COLD_READER -RunId $ColdReaderRunId -Inputs @{RUN_CONTEXT=$runContextPath;CLEAN_NARRATION=$cleanPath;COLD_READER_QUESTIONS=$controlPaths.coldQuestions;COLD_READER_OUTPUT_SCHEMA=$controlPaths.coldOutputSchema};$createdRunRoots.Add((Split-Path -Parent $cold.Path))

    foreach($bundle in @($editor,$verify,$cold)){$state=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $bundle.Path -RequireLiveSource;if(-not $state.Valid){throw "K4_BUNDLE_POSTVALIDATION_FAILED: $($state.Errors -join '; ')"}}
    foreach($trackedPath in @($trackedInputs.Keys)){if(-not(Test-Path -LiteralPath $trackedPath -PathType Leaf) -or (Get-FileHash -LiteralPath $trackedPath -Algorithm SHA256).Hash -cne [string]$trackedInputs[$trackedPath]){throw "K4_INPUT_CHANGED_DURING_TRANSACTION: $trackedPath"}}
    [pscustomobject]@{Status='THREE_LENS_BUNDLES_READY';DraftSha256=$draftSha;MoveReviewStatus=$moveReview.ReviewStatus;MoveReviewDecisionSha256=$moveReview.DecisionSha256;SemanticReviewAlerts=@($semanticState.ReviewAlerts);EditorManifest=$editor.Path;VerifyManifest=$verify.Path;ColdReaderManifest=$cold.Path;Instruction='Uruchom trzy niezależne świeże konteksty. Nie przekazuj wyników jednej soczewki drugiej.'}
}catch{
    for($index=$createdRunRoots.Count-1;$index -ge 0;$index--){$dir=$createdRunRoots[$index];if((Test-Path -LiteralPath $dir -PathType Container) -and (Get-SystemV7NarrativeRelativePath -Root $project -Path $dir) -match '^_work/narrative-runs/[A-Z0-9][A-Z0-9._-]{7,80}$'){$null=Assert-SystemV7TreeNoReparse -RootPath $dir -ContainmentRoot $project;[IO.Directory]::Delete($dir,$true)}}
    for($index=$createdFiles.Count-1;$index -ge 0;$index--){$file=$createdFiles[$index];if(Test-Path -LiteralPath $file -PathType Leaf){[IO.File]::Delete($file)}}
    throw
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
