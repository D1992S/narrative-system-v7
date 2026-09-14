[CmdletBinding()]
param([Parameter(Mandatory)][string]$ProjectPath)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')

Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
$trackedInputs=@{}
$trackInput={param([string]$Path,[string]$Code)
    $full=[IO.Path]::GetFullPath($Path);if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "ASSEMBLY_INPUT_MISSING: $Code/$full"}
    $sha=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    if($trackedInputs.ContainsKey($full) -and [string]$trackedInputs[$full] -cne $sha){throw "ASSEMBLY_INPUT_CHANGED_DURING_READ: $Code"}
    $trackedInputs[$full]=$sha;return $sha
}
try{
    $metaPath=Join-Path $project 'meta.md';$null=&$trackInput $metaPath 'META'
    $architecturePath=Join-Path $project '02-architektura-odcinka.md';$null=&$trackInput $architecturePath 'ARCHITECTURE'
    $evidencePath=Join-Path $project '01-baza-dowodow.md';$null=&$trackInput $evidencePath 'EVIDENCE'
    $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $origin=Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
    if((Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE') -cne 'K3'){throw 'ASSEMBLY_REQUIRES_STAGE_K3'}
    $sequence=@((Get-SystemV7NarrativeMetaField -Text $meta -Name 'NARRATIVE_ACT_SEQUENCE') -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_})
    if($sequence.Count -eq 0){throw 'NARRATIVE_ACT_SEQUENCE_EMPTY'}
    $prefix=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_PREFIX_SHA256';$model=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_ID';$modelRevision=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_REVISION'
    $assemblyActs=[Collections.Generic.List[object]]::new();$narrationParts=[Collections.Generic.List[string]]::new();$mapActs=[Collections.Generic.List[object]]::new()
    $sourceWordCounts=[Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal);$attestSnapshots=@{}
    foreach($actId in $sequence){
        $actDir=Join-Path $project "_work\k3\acts\$actId";$statePath=Join-Path $actDir 'state.json';$prosePath=Join-Path $actDir 'prose.md';$blocksPath=Join-Path $actDir 'blocks.json';$outPath=Join-Path $actDir 'out.json';$attestPath=Join-Path $project "_work\k3\continuity\$actId.attest.json";$packetPath=Join-Path $project "_work\k3\packets\$actId.act-packet.json"
        foreach($pair in @(@($statePath,'STATE'),@($prosePath,'PROSE'),@($blocksPath,'BLOCKS'),@($outPath,'OUT'),@($attestPath,'ATTEST'),@($packetPath,'PACKET'))){$null=&$trackInput $pair[0] "$actId/$($pair[1])"}
        $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        $attestState=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $actId
        if(-not $attestState.Valid){throw "ACT_ATTEST_SEMANTIC_INVALID: $actId/$($attestState.Errors -join ',')"}
        $attest=$attestState.Data;$attestSnapshots[$actId]=$attestState.Sha256
        if([string]$state.status -cne 'ATTESTED' -or [string]$attest.verdict -cne 'PASS'){throw "ACT_NOT_ATTESTED: $actId"}
        if([string]$state.prefix_sha256 -cne $prefix -or [string]$attest.prefix_sha256 -cne $prefix){throw "PREFIX_STALE: $actId"}
        if([string]$state.model_id -cne $model -or [string]$state.model_revision -cne $modelRevision){throw "MODEL_STALE: $actId"}
        $proseBinding=Get-SystemV7ActProseBindingState -ActId $actId -BlocksPath $blocksPath -ProsePath $prosePath
        if(-not $proseBinding.Valid){throw "ASSEMBLY_PROSE_BINDING_INVALID: $actId/$($proseBinding.Errors -join ',')"}
        $blocks=$proseBinding.Blocks;$prose=$proseBinding.ExpectedProse.Trim();$packet=Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
        $traceToSw=@{};if([string]$packet.complexity_flag -ceq 'COMPLEX'){$beatPath=Join-Path $project "_work\k3\beats\$actId\beat-sheet.json";$null=&$trackInput $beatPath "$actId/BEAT_SHEET";$beatSheet=Get-Content -LiteralPath $beatPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;foreach($beat in @($beatSheet.beats)){$traceToSw[[string]$beat.beat_id]=[string]$beat.sw_id}}else{foreach($swId in @($packet.scene_weave_ids)){$traceToSw[[string]$swId]=[string]$swId}}
        $null=Assert-SystemV7PlainSpokenText -Text $prose -Context "ASSEMBLY_$actId"
        $narrationParts.Add("### $actId`n`n$prose")
        $mapBlocks=@()
        foreach($block in @($blocks.blocks)){
            foreach($p in @($block.source_p_ids)){if(-not $sourceWordCounts.ContainsKey([string]$p)){$sourceWordCounts.Add([string]$p,0)};$sourceWordCounts[[string]$p]+=[int]$block.word_count}
            $swIds=[Collections.Generic.List[string]]::new();$swSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($traceRef in @($block.trace_refs)){if(-not $traceToSw.ContainsKey([string]$traceRef)){throw "ASSEMBLY_TRACE_TO_SW_MISSING: $actId/$traceRef"};$swId=[string]$traceToSw[[string]$traceRef];if($swSeen.Add($swId)){$swIds.Add($swId)}}
            if((@([string[]]@($block.sw_ids)) -join '|') -cne (@([string[]]@($swIds)) -join '|')){throw "ASSEMBLY_BLOCK_SW_IDS_STALE: $actId/$($block.block_id)"}
            $mapBlocks+=[ordered]@{block_id=$block.block_id;block_sha256=$block.block_sha256;word_count=$block.word_count;trace_refs=@($block.trace_refs);sw_ids=@($block.sw_ids);source_p_ids=@($block.source_p_ids);narrative_refs=@($block.narrative_refs)}
        }
        $mapActs.Add([ordered]@{act_id=$actId;prose_sha256=$proseBinding.ProseSha256;blocks_sha256=$proseBinding.BlocksSha256;attest_sha256=$attestState.Sha256;blocks=$mapBlocks})
        $assemblyActs.Add([ordered]@{act_id=$actId;prose_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $prosePath);prose_sha256=$proseBinding.ProseSha256;blocks_sha256=$proseBinding.BlocksSha256;attest_sha256=$attestState.Sha256})
    }
    $narration=($narrationParts -join "`n`n")+"`n"
    $wordCount=@([regex]::Matches($narration,"\b[\p{L}\p{N}][\p{L}\p{N}\p{M}’'-]*\b")).Count-$sequence.Count
    $realWpm=[int](Get-SystemV7NarrativeMetaField -Text $meta -Name 'REAL_WPM');if($realWpm -lt 1){throw 'ASSEMBLY_REAL_WPM_INVALID'};$estimated=[math]::Round($wordCount/[double]$realWpm,2)
    $blockMap=[ordered]@{schema='K3_BLOCK_MAP_V1';prefix_sha256=$prefix;model_id=$model;model_revision=$modelRevision;acts=@($mapActs)}
    $assemblyCore=[ordered]@{schema='K3_ASSEMBLY_MANIFEST_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_origin_sha256=$origin.Sha256;prefix_sha256=$prefix;model_id=$model;model_revision=$modelRevision;acts=@($assemblyActs);block_map_content_sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $blockMap));narration_sha256=(Get-SystemV7NarrativeSha256Text -Text $narration)}
    $assemblySha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $assemblyCore)
    $assembly=[ordered]@{};foreach($k in $assemblyCore.Keys){$assembly[$k]=$assemblyCore[$k]};$assembly['assembly_manifest_sha256']=$assemblySha
    $draftPath=Join-Path $project '03-draft.md';$revision=1;$draftBefore=$null
    if(Test-Path -LiteralPath $draftPath -PathType Leaf){$null=&$trackInput $draftPath 'EXISTING_DRAFT';$draftBefore=[IO.File]::ReadAllBytes($draftPath);$old=Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8;$m=[regex]::Match($old,'(?m)^CONTENT_REVISION:\s*(\d+)\s*$');if($m.Success){$revision=[int]$m.Groups[1].Value+1}}
    $fence='```'
    $draft=@"
# 03 — DRAFT TECHNICZNY

CONTENT_REVISION: $revision
DATE: $([DateTime]::UtcNow.ToString('yyyy-MM-dd'))
WORD_COUNT: $wordCount
WORDS_PER_MINUTE: $realWpm
ESTIMATED_DURATION: $estimated min
BASELINE_FOR_QA: NONE
CHANGE_SCOPE_PERCENT: 0
VERIFICATION_STATUS: NIEURUCHOMIONA — K4
WORKFLOW_REVISION: $script:SystemV7NarrativeWorkflowRevision
EVIDENCE_SCHEMA: MINIMAL_EVIDENCE_V4_PAGELOC
PREFIX_SHA256: $prefix
K3_MODEL_ID: $model
K3_MODEL_REVISION: $modelRevision
CONTINUITY_CHAIN_STATUS: COMPLETE
ASSEMBLY_MANIFEST_SHA256: $assemblySha

## Changelog

- R${revision}: deterministyczny montaż aktów z ważnymi atestami.

## Mapa aktów i bloków — warstwa techniczna

<!-- K3_BLOCK_MAP_BEGIN -->
${fence}json
$((ConvertTo-SystemV7CanonicalJson -Value $blockMap).TrimEnd())
$fence
<!-- K3_BLOCK_MAP_END -->

---

## NARRACJA ROBOCZA

$($narration.TrimEnd())
"@
    $assemblyDir=Join-Path $project '_work\k3\assembly';$null=Assert-SystemV7PathNoReparse -Path $assemblyDir -ContainmentRoot $project;[IO.Directory]::CreateDirectory($assemblyDir)|Out-Null;$manifestPath=Join-Path $assemblyDir "$assemblySha.json"
    foreach($trackedPath in @($trackedInputs.Keys)){if(-not(Test-Path -LiteralPath $trackedPath -PathType Leaf) -or (Get-FileHash -LiteralPath $trackedPath -Algorithm SHA256).Hash -cne [string]$trackedInputs[$trackedPath]){throw "ASSEMBLY_COMPARE_AND_SWAP_CONFLICT: $trackedPath"}}
    foreach($actId in $sequence){$fresh=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $actId;if(-not $fresh.Valid -or [string]$fresh.Sha256 -cne [string]$attestSnapshots[$actId]){throw "ASSEMBLY_ATTEST_CHANGED: $actId/$($fresh.Errors -join ',')"}}
    $manifestCreated=$false;$draftWritten=$false
    try{
        if(Test-Path -LiteralPath $manifestPath -PathType Leaf){$existing=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;if((ConvertTo-SystemV7CanonicalJson -Value $existing) -cne (ConvertTo-SystemV7CanonicalJson -Value $assembly)){throw 'ASSEMBLY_MANIFEST_HASH_COLLISION'}}
        else{Write-SystemV7NarrativeCreateNewJson -Path $manifestPath -Value $assembly|Out-Null;$manifestCreated=$true}
        Write-SystemV7NarrativeAtomicText -Path $draftPath -Text $draft|Out-Null;$draftWritten=$true
        $writtenDraft=Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
        if((ConvertTo-SystemV7LfText -Text $writtenDraft).TrimEnd() -cne (ConvertTo-SystemV7LfText -Text $draft).TrimEnd()){throw 'ASSEMBLY_DRAFT_POSTVALIDATION_MISMATCH'}
        $writtenManifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
        if((ConvertTo-SystemV7CanonicalJson -Value $writtenManifest) -cne (ConvertTo-SystemV7CanonicalJson -Value $assembly)){throw 'ASSEMBLY_MANIFEST_POSTVALIDATION_MISMATCH'}
    }catch{
        if($draftWritten){if($null -eq $draftBefore){if(Test-Path -LiteralPath $draftPath -PathType Leaf){[IO.File]::Delete($draftPath)}}else{[IO.File]::WriteAllBytes($draftPath,$draftBefore)}}
        if($manifestCreated -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)){[IO.File]::Delete($manifestPath)}
        throw
    }
    $alerts=@($sourceWordCounts.GetEnumerator()|Where-Object{$_.Value -gt 300}|ForEach-Object{"SOURCE_DENSITY_REVIEW: $($_.Key) -> $($_.Value) words"})
    [pscustomobject]@{Status='K3_DRAFT_ASSEMBLED';DraftPath=$draftPath;DraftSha256=(Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash;AssemblyManifestPath=$manifestPath;AssemblyManifestSha256=$assemblySha;ActCount=$sequence.Count;WordCount=$wordCount;EstimatedMinutes=$estimated;SourceDensityAlerts=$alerts}
}finally{Exit-SystemV7ProjectMetaLock -LockStream $lock}
