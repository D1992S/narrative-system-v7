$script:SystemV7NarrativeWorkflowRevision = '2026-08-31_NARRATIVE_V2'
$script:SystemV7NarrativeArchitectureSchema = 'STORY_ENGINE_V2'
$script:SystemV7NarrativePacketSchema = 'K3_PACKET_V2'
$script:SystemV7NarrativeContinuitySchema = 'CONTINUITY_ATTEST_V1'
$script:SystemV7NarrativeK4Schema = 'THREE_LENS_QA_V1'
$script:SystemV7NarrativeMaxConstraints = 7
$script:SystemV7NarrativeBlockWordLimit = 220

function Test-SystemV7ExactMember {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][object[]]$Allowed)
    return [array]::IndexOf($Allowed,[string]$Value) -ge 0
}

function Get-SystemV7NarrativeInstructionRelativePaths {
    # To jest zamknięty, kodowy allowlist instrukcji mających wpływ na Narrative V2.
    # Manifest nie może sam rozszerzyć swojego zakresu przez dopisanie nowego pliku.
    $paths=[string[]]@(
        'AGENTS.md'
        '_SYSTEM/00-KONSTYTUCJA.md'
        '_SYSTEM/01-PIPELINE.md'
        '_SYSTEM/02-ROLE-I-ODPOWIEDZIALNOSC.md'
        '_SYSTEM/03-STAN-I-PLIKI.md'
        '_SYSTEM/04-START-I-KOMENDY.md'
        '_SYSTEM/05-PROFIL-KANALU.md'
        '_SYSTEM/06-AUTOMATYZACJE.md'
        '_SYSTEM/ROLES/CLAUDE.md'
        '_SYSTEM/ROLES/CODEX.md'
        '_SYSTEM/ROLES/DAWID.md'
        '_SYSTEM/STEPS/W0-POMYSL-I-ZRODLA.md'
        '_SYSTEM/STEPS/K0-FUNDAMENT.md'
        '_SYSTEM/STEPS/K1-BAZA-DOWODOW.md'
        '_SYSTEM/STEPS/K2-ARCHITEKTURA.md'
        '_SYSTEM/STEPS/K2B-SUPLEMENT.md'
        '_SYSTEM/STEPS/K3-SCENARIUSZ.md'
        '_SYSTEM/STEPS/K4-QA-FACTCHECK.md'
        '_SYSTEM/STEPS/K5-FINAL.md'
        '_SYSTEM/SKILLS/KANON-DRAMATURGII.md'
        '_SYSTEM/SKILLS/STORYTELLING.md'
        '_SYSTEM/SKILLS/PISMAK.md'
        '_SYSTEM/SKILLS/USTALENIA-STYLU.md'
        '_SYSTEM/SKILLS/DZIENNIKARSKI.md'
        'BIBLIA/README.md'
        'BIBLIA/01-TOZSAMOSC-DOKUMENTU.md'
        'BIBLIA/02-POMYSL-HIPOTEZA-I-POJEMNOSC-NARRACYJNA.md'
        'BIBLIA/03-RESEARCH-DOWODY-I-ETYKA.md'
        'BIBLIA/04-DRAMATURGIA-STRUKTURA-I-CZAS.md'
        'BIBLIA/05-BOHATER-WYWIAD-I-SWIADECTWO.md'
        'BIBLIA/06-NARRACJA-GLOS-I-JEZYK.md'
        'BIBLIA/12-BIBLIOTEKA-KSIAZEK.md'
        'BIBLIA/13-MASTER-CHECKLISTA-NARRACJI.md'
        '_SYSTEM/NARRATIVE/NARRATIVE-CONTRACT-V2.md'
        '_SYSTEM/NARRATIVE/K3-RULES-CORE.md'
        '_SYSTEM/NARRATIVE/VOICE-PROFILE-SCHEMA.md'
        '_SYSTEM/NARRATIVE/CONTINUITY-SCHEMA.md'
        '_SYSTEM/NARRATIVE/K4-INPUT-PROFILES.md'
        '_SYSTEM/NARRATIVE/CONSTRAINT-ATOMICITY-SCHEMA.md'
        '_SYSTEM/NARRATIVE/BEAT-PREFLIGHT-SCHEMA.md'
        '_SYSTEM/NARRATIVE/QA-IMPACT-SCHEMA.md'
        '_SYSTEM/NARRATIVE/RUN-TELEMETRY-SCHEMA.md'
        '_SYSTEM/NARRATIVE/EDITOR-CRITERIA.md'
        '_SYSTEM/NARRATIVE/EDITOR-OUTPUT-SCHEMA.md'
        '_SYSTEM/NARRATIVE/VERIFY-CRITERIA.md'
        '_SYSTEM/NARRATIVE/VERIFY-OUTPUT-SCHEMA.md'
        '_SYSTEM/NARRATIVE/COLD-READER-QUESTIONS.md'
        '_SYSTEM/NARRATIVE/COLD-READER-OUTPUT-SCHEMA.md'
        '_SYSTEM/NARRATIVE/AB-TEST-PROTOCOL.md'
        '_SYSTEM/NARRATIVE/AB-TEST-STATUS.json'
        'TEMPLATES/PROJECT/meta.md'
        'TEMPLATES/PROJECT/00-fundament-projektu.md'
        'TEMPLATES/PROJECT/01-baza-dowodow.md'
        'TEMPLATES/PROJECT/02-architektura-odcinka.md'
        'TEMPLATES/PROJECT/03-draft.md'
        'TEMPLATES/PROJECT/04-raport-qa.md'
        'TEMPLATES/PROJECT/04B-fact-check.md'
        'TEMPLATES/PROJECT/05-FINAL-SCRIPT.md'
    )
    [Array]::Sort($paths,[StringComparer]::Ordinal)
    return $paths
}

function Get-SystemV7NarrativeInstructionPathState {
    param([Parameter(Mandatory)][string]$SystemRoot,[Parameter(Mandatory)][string]$RelativePath)
    $root=[IO.Path]::GetFullPath($SystemRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $errors=[Collections.Generic.List[string]]::new()
    if([string]::IsNullOrWhiteSpace($RelativePath) -or $RelativePath -match '\\' -or $RelativePath -match '(^/|:|(?:^|/)\.\.?($|/))'){
        $errors.Add("INSTRUCTION_PATH_SYNTAX_INVALID: $RelativePath")
        return [pscustomobject]@{Valid=$false;Errors=@($errors);FullPath=''}
    }
    $full=[IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    $prefix=$root+[IO.Path]::DirectorySeparatorChar
    if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){$errors.Add("INSTRUCTION_PATH_OUTSIDE_ROOT: $RelativePath")}
    if($errors.Count -eq 0){
        $cursor=$root
        foreach($part in @($RelativePath -split '/')){
            $cursor=Join-Path $cursor $part
            if(Test-Path -LiteralPath $cursor){
                try{if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){$errors.Add("INSTRUCTION_PATH_REPARSE_FORBIDDEN: $RelativePath");break}}
                catch{$errors.Add("INSTRUCTION_PATH_INSPECTION_FAILED: $RelativePath/$($_.Exception.Message)");break}
            }
        }
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);FullPath=$full}
}

function Get-SystemV7NarrativeInstructionContractState {
    param([Parameter(Mandatory)][string]$SystemRoot)
    $errors=[Collections.Generic.List[string]]::new()
    $root=[IO.Path]::GetFullPath($SystemRoot)
    $agentsPath=Join-Path $root 'AGENTS.md'
    $contractPath=Join-Path $root '_SYSTEM\NARRATIVE\NARRATIVE-CONTRACT-V2.md'
    $manifestPath=Join-Path $root '_SYSTEM\NARRATIVE\NARRATIVE-INSTRUCTION-MANIFEST.json'
    $required=@(
        [pscustomobject]@{Path=$agentsPath;Label='AGENTS'},
        [pscustomobject]@{Path=$contractPath;Label='NARRATIVE_CONTRACT'}
    )
    foreach($item in $required){
        if(-not(Test-Path -LiteralPath $item.Path -PathType Leaf)){$errors.Add("INSTRUCTION_$($item.Label)_MISSING");continue}
        try{
            $bytes=[IO.File]::ReadAllBytes($item.Path)
            if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){$errors.Add("INSTRUCTION_$($item.Label)_UTF8_BOM_FORBIDDEN")}
            $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
            $contractMatches=@([regex]::Matches($text,'(?m)^NARRATIVE_V2_CONTRACT:\s*2026-08-31_NARRATIVE_V2\s*$'))
            $statusMatches=@([regex]::Matches($text,'(?m)^NARRATIVE_V2_STATUS:\s*PILOT_ONLY\s*$'))
            if($contractMatches.Count -ne 1){$errors.Add("INSTRUCTION_$($item.Label)_CONTRACT_MARKER_INVALID: $($contractMatches.Count)")}
            if($statusMatches.Count -ne 1){$errors.Add("INSTRUCTION_$($item.Label)_STATUS_MARKER_INVALID: $($statusMatches.Count)")}
            if($item.Label -ceq 'AGENTS' -and $text.IndexOf('_SYSTEM/NARRATIVE/NARRATIVE-CONTRACT-V2.md',[StringComparison]::Ordinal) -lt 0){$errors.Add('INSTRUCTION_AGENTS_ROUTE_MISSING')}
        }catch{$errors.Add("INSTRUCTION_$($item.Label)_READ_FAILED: $($_.Exception.Message)")}
    }
    $expectedPaths=@(Get-SystemV7NarrativeInstructionRelativePaths)
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){$errors.Add('INSTRUCTION_MANIFEST_MISSING')}
    else{
        try{
            $manifestPathState=Get-SystemV7NarrativeInstructionPathState -SystemRoot $root -RelativePath '_SYSTEM/NARRATIVE/NARRATIVE-INSTRUCTION-MANIFEST.json'
            foreach($problem in @($manifestPathState.Errors)){$errors.Add($problem)}
            $manifestBytes=[IO.File]::ReadAllBytes($manifestPath)
            if($manifestBytes.Length -ge 3 -and $manifestBytes[0] -eq 0xEF -and $manifestBytes[1] -eq 0xBB -and $manifestBytes[2] -eq 0xBF){$errors.Add('INSTRUCTION_MANIFEST_UTF8_BOM_FORBIDDEN')}
            $manifestText=[Text.UTF8Encoding]::new($false,$true).GetString($manifestBytes)
            $manifest=$manifestText|ConvertFrom-Json -DateKind String -Depth 64
            $manifestFields=[string[]]@('schema','workflow_revision','status','entries')
            if(@($manifest.PSObject.Properties.Name).Count -ne $manifestFields.Count -or @(Compare-Object -ReferenceObject $manifestFields -DifferenceObject @($manifest.PSObject.Properties.Name) -CaseSensitive).Count -gt 0){$errors.Add('INSTRUCTION_MANIFEST_FIELDS_INVALID')}
            if([string]$manifest.schema -cne 'NARRATIVE_INSTRUCTION_MANIFEST_V1'){$errors.Add('INSTRUCTION_MANIFEST_SCHEMA_INVALID')}
            if([string]$manifest.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision){$errors.Add('INSTRUCTION_MANIFEST_REVISION_INVALID')}
            if([string]$manifest.status -cne 'PILOT_ONLY'){$errors.Add('INSTRUCTION_MANIFEST_STATUS_INVALID')}
            $entries=@($manifest.entries)
            if($entries.Count -ne $expectedPaths.Count){$errors.Add("INSTRUCTION_MANIFEST_ENTRY_COUNT_INVALID: $($entries.Count)/$($expectedPaths.Count)")}
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $actualPaths=[Collections.Generic.List[string]]::new()
            foreach($entry in $entries){
                $entryFields=[string[]]@('path','sha256')
                if($null -eq $entry -or @($entry.PSObject.Properties.Name).Count -ne $entryFields.Count -or @(Compare-Object -ReferenceObject $entryFields -DifferenceObject @($entry.PSObject.Properties.Name) -CaseSensitive).Count -gt 0){$errors.Add('INSTRUCTION_MANIFEST_ENTRY_FIELDS_INVALID');continue}
                $relative=[string]$entry.path;$sha=[string]$entry.sha256
                $actualPaths.Add($relative)
                if(-not $seen.Add($relative)){$errors.Add("INSTRUCTION_MANIFEST_DUPLICATE_PATH: $relative")}
                if($sha -cnotmatch '^[A-F0-9]{64}$'){$errors.Add("INSTRUCTION_MANIFEST_SHA_FORMAT_INVALID: $relative")}
                $pathState=Get-SystemV7NarrativeInstructionPathState -SystemRoot $root -RelativePath $relative
                foreach($problem in @($pathState.Errors)){$errors.Add($problem)}
                if(-not $pathState.Valid){continue}
                if(-not(Test-Path -LiteralPath $pathState.FullPath -PathType Leaf)){$errors.Add("INSTRUCTION_FILE_MISSING: $relative");continue}
                try{
                    $bytes=[IO.File]::ReadAllBytes($pathState.FullPath)
                    if($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){$errors.Add("INSTRUCTION_FILE_UTF8_BOM_FORBIDDEN: $relative")}
                    $null=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
                    $actualSha=(Get-FileHash -LiteralPath $pathState.FullPath -Algorithm SHA256).Hash
                    if($actualSha -cne $sha){$errors.Add("INSTRUCTION_FILE_SHA_MISMATCH: $relative")}
                }catch{$errors.Add("INSTRUCTION_FILE_READ_FAILED: $relative/$($_.Exception.Message)")}
            }
            for($i=0;$i -lt [Math]::Min($actualPaths.Count,$expectedPaths.Count);$i++){
                if($actualPaths[$i] -cne $expectedPaths[$i]){$errors.Add("INSTRUCTION_MANIFEST_ALLOWLIST_OR_ORDER_INVALID: index=$i")}
            }
            if($actualPaths.Count -eq $expectedPaths.Count -and @(Compare-Object -ReferenceObject $expectedPaths -DifferenceObject @($actualPaths) -CaseSensitive).Count -gt 0){$errors.Add('INSTRUCTION_MANIFEST_ALLOWLIST_INVALID')}
            $canonical=ConvertTo-SystemV7CanonicalJson -Value $manifest
            if($manifestText -cne $canonical){$errors.Add('INSTRUCTION_MANIFEST_NON_CANONICAL_BYTES')}
        }catch{$errors.Add("INSTRUCTION_MANIFEST_READ_FAILED: $($_.Exception.Message)")}
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);SystemRoot=$root;AgentsPath=$agentsPath;ContractPath=$contractPath;ManifestPath=$manifestPath;ExpectedEntryCount=$expectedPaths.Count}
}

function Assert-SystemV7NarrativeInstructionContract {
    param([Parameter(Mandatory)][string]$SystemRoot)
    $state=Get-SystemV7NarrativeInstructionContractState -SystemRoot $SystemRoot
    if(-not $state.Valid){throw "NARRATIVE_INSTRUCTION_CONTRACT_INVALID: $($state.Errors -join '; ')"}
    return $state
}

function Assert-SystemV7NarrativeProjectInstructionContract {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [string]$SystemRoot=(Split-Path -Parent $PSScriptRoot)
    )
    $project=[IO.Path]::GetFullPath($ProjectPath)
    $metaPath=Join-Path $project 'meta.md'
    if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){throw "NARRATIVE_PROJECT_META_MISSING: $metaPath"}
    $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){throw 'WORKFLOW_REVISION_NOT_NARRATIVE_V2'}
    return Assert-SystemV7NarrativeInstructionContract -SystemRoot ([IO.Path]::GetFullPath($SystemRoot))
}

function Assert-SystemV7NarrativeInstructionContractIfV2 {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [string]$SystemRoot=(Split-Path -Parent $PSScriptRoot)
    )
    $project=[IO.Path]::GetFullPath($ProjectPath)
    $metaPath=Join-Path $project 'meta.md'
    if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){throw "NARRATIVE_PROJECT_META_MISSING: $metaPath"}
    $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    if(Test-SystemV7NarrativeV2Revision -MetaText $meta){
        return Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project -SystemRoot $SystemRoot
    }
    return $null
}

function Get-SystemV7NarrativeMoveRepetitionState {
    param([Parameter(Mandatory)][string]$ProjectPath)
    $project=[IO.Path]::GetFullPath($ProjectPath)
    $errors=[Collections.Generic.List[string]]::new()
    $metaPath=Join-Path $project 'meta.md'
    if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){$errors.Add('MOVE_REVIEW_META_MISSING');return [pscustomobject]@{Valid=$false;GateReady=$false;Errors=@($errors);ReviewAlerts=@()}}
    $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    if(-not(Test-SystemV7NarrativeV2Revision -MetaText $meta)){$errors.Add('MOVE_REVIEW_ONLY_NARRATIVE_V2');return [pscustomobject]@{Valid=$false;GateReady=$false;Errors=@($errors);ReviewAlerts=@()}}
    try{$origin=Get-SystemV7ProjectOriginState -ProjectPath $project;if(-not $origin.Valid){throw ($origin.Errors -join ',')};$originSha=[string]$origin.Sha256}catch{$originSha='';$errors.Add("MOVE_REVIEW_PROJECT_ORIGIN_INVALID: $($_.Exception.Message)")}
    try{$sequence=@((Get-SystemV7NarrativeMetaField -Text $meta -Name 'NARRATIVE_ACT_SEQUENCE') -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_ -match '^ACT-\d{3}$'})}catch{$sequence=@();$errors.Add("MOVE_REVIEW_SEQUENCE_INVALID: $($_.Exception.Message)")}
    if($sequence.Count -lt 1){$errors.Add('MOVE_REVIEW_SEQUENCE_EMPTY')}
    $entries=[Collections.Generic.List[object]]::new()
    foreach($actId in $sequence){
        $actDir=Join-Path $project "_work\k3\acts\$actId"
        $path=Join-Path $actDir 'out.json'
        $statePath=Join-Path $actDir 'state.json'
        $attestPath=Join-Path $project "_work\k3\continuity\$actId.attest.json"
        if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or -not(Test-Path -LiteralPath $statePath -PathType Leaf) -or -not(Test-Path -LiteralPath $attestPath -PathType Leaf)){
            $errors.Add("MOVE_REVIEW_ATTESTED_OUT_MISSING: $actId");continue
        }
        try{
            $data=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
            $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
            $attest=Get-Content -LiteralPath $attestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
            $outSha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            $attestSha=(Get-FileHash -LiteralPath $attestPath -Algorithm SHA256).Hash
            $attestRelative=[IO.Path]::GetRelativePath($project,$attestPath).Replace('\','/')
            if([string]$state.schema -cne 'K3_ACT_STATE_V1' -or [string]$state.act_id -cne $actId -or [string]$state.status -cne 'ATTESTED' -or
                [string]$state.continuity_out_sha256 -cne $outSha -or [string]$state.attest_record_relative -cne $attestRelative -or [string]$state.attest_record_sha256 -cne $attestSha -or
                [string]$attest.schema -cne 'CONTINUITY_ATTEST_RECORD_V1' -or [string]$attest.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or
                [string]$attest.act_id -cne $actId -or [string]$attest.verdict -cne 'PASS' -or [string]$attest.continuity_out_sha256 -cne $outSha){throw 'OUT_NOT_BOUND_TO_ACCEPTED_ATTEST'}
            if([string]$data.schema -cne 'CONTINUITY_OUT_V1' -or [string]$data.act_id -cne $actId -or -not (Test-SystemV7ExactMember -Value ([string]$data.opening_move_type) -Allowed @('SCENA','ANOMALIA','DOKUMENT','KONSEKWENCJA','KONTRAST','KONTAKT_Z_WIDZEM','POWRÓT_DO_MOTYWU')) -or -not (Test-SystemV7ExactMember -Value ([string]$data.closing_move_type) -Allowed @('DECYZJA','REVEAL','PAYOFF','KONSEKWENCJA','GRANICA_WIEDZY','NOWA_PĘTLA','POWRÓT_DO_MOTYWU'))){throw 'IDENTITY_OR_MOVE_INVALID'}
            # Group-Object rozpoznaje właściwości PSCustomObject, ale nie klucze
            # OrderedDictionary przekazanego bez rzutowania. Jawne rzutowanie
            # zapobiega pustym nazwom grup i fałszywym alertom powtórzeń.
            $entries.Add([pscustomobject][ordered]@{act_id=$actId;out_sha256=$outSha;opening_move_type=[string]$data.opening_move_type;closing_move_type=[string]$data.closing_move_type})
        }catch{$errors.Add("MOVE_REVIEW_ATTESTED_OUT_INVALID: $actId/$($_.Exception.Message)")}
    }
    $historyValue=[ordered]@{schema='MOVE_HISTORY_V1';project_origin_sha256=$originSha;sequence=@($sequence);entries=@($entries)}
    $historySha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $historyValue)
    $repetitions=[Collections.Generic.List[object]]::new()
    foreach($definition in @(
        [pscustomobject]@{Kind='OPENING_MOVE';Property='opening_move_type'},
        [pscustomobject]@{Kind='CLOSING_MOVE';Property='closing_move_type'}
    )){
        $moveProperty=[string]$definition.Property
        foreach($group in @($entries|Group-Object -Property $moveProperty|Where-Object{$_.Count -gt 1}|Sort-Object Name)){
            $bindings=@($group.Group|ForEach-Object{[ordered]@{act_id=[string]$_.act_id;out_sha256=[string]$_.out_sha256}})
            $repetitions.Add([ordered]@{kind=[string]$definition.Kind;move_type=[string]$group.Name;act_ids=@($bindings|ForEach-Object{$_.act_id});out_bindings=$bindings})
        }
    }
    $decisionPath=Join-Path $project "_work\k3\continuity\move-repetition-decisions\decision-$historySha.json"
    $decisionValid=$false;$decisionSha='BRAK';$decisionErrors=[Collections.Generic.List[string]]::new()
    if($repetitions.Count -eq 0){$decisionValid=$true}
    elseif(Test-Path -LiteralPath $decisionPath -PathType Leaf){
        try{
            $receipt=Get-Content -LiteralPath $decisionPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
            $fields=@('schema','workflow_revision','project_origin_sha256','history_sha256','actor','verdict','reason','repetitions','created_at_utc')
            if(@($receipt.PSObject.Properties.Name).Count -ne $fields.Count -or @(Compare-Object -ReferenceObject $fields -DifferenceObject @($receipt.PSObject.Properties.Name)).Count -gt 0){throw 'FIELDS_INVALID'}
            if([string]$receipt.schema -cne 'MOVE_REPETITION_DECISION_V1' -or [string]$receipt.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$receipt.project_origin_sha256 -cne $originSha -or [string]$receipt.history_sha256 -cne $historySha -or [string]$receipt.actor -cne 'DAWID' -or [string]$receipt.verdict -cne 'APPROVE_CONSCIOUS_REPETITION' -or -not(Test-SystemV7ConcreteText -Value ([string]$receipt.reason))){throw 'IDENTITY_OR_AUTHORITY_INVALID'}
            if((ConvertTo-SystemV7CanonicalJson -Value @($receipt.repetitions)) -cne (ConvertTo-SystemV7CanonicalJson -Value @($repetitions))){throw 'REPETITION_SET_MISMATCH'}
            $decisionSha=(Get-FileHash -LiteralPath $decisionPath -Algorithm SHA256).Hash;$decisionValid=$true
        }catch{$decisionErrors.Add($_.Exception.Message)}
    }
    foreach($problem in @($decisionErrors)){$errors.Add("MOVE_REPETITION_DECISION_INVALID: $problem")}
    $reviewStatus=if($repetitions.Count -eq 0){'PASS_NO_REPETITION'}elseif($decisionValid){'PASS_CONSCIOUS_REPETITION_APPROVED'}else{'REVIEW_ALERT'}
    [pscustomobject]@{
        Valid=$errors.Count -eq 0;GateReady=($errors.Count -eq 0 -and $decisionValid);Errors=@($errors);ReviewStatus=$reviewStatus
        ReviewAlerts=@($repetitions);ProjectOriginSha256=$originSha;HistorySha256=$historySha;History=@($entries);DecisionPath=$decisionPath;DecisionSha256=$decisionSha
    }
}

function Get-SystemV7NarrativeSemanticPreflightState {
    param(
        [Parameter(Mandatory)][object]$ArchitectureData,
        [Parameter(Mandatory)][object[]]$Blocks,
        [AllowEmptyString()][Parameter(Mandatory)][string]$VoiceExemplarsText,
        [Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$DraftSha256
    )
    $errors=[Collections.Generic.List[string]]::new();$findings=[Collections.Generic.List[object]]::new();$findingIndex=0
    $wordTokens={param([AllowEmptyString()][string]$Text)@([regex]::Matches($Text.ToLowerInvariant(),'[\p{L}\p{N}]+')|ForEach-Object{$_.Value})}
    $exemplarNgrams=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $exemplarTokens=@(&$wordTokens $VoiceExemplarsText)
    if($exemplarTokens.Count -ge 8){for($i=0;$i -le $exemplarTokens.Count-8;$i++){$null=$exemplarNgrams.Add(($exemplarTokens[$i..($i+7)] -join ' '))}}
    $acts=@{};foreach($act in @($ArchitectureData.acts)){$acts[[string]$act.act_id]=$act}
    foreach($block in @($Blocks)){
        $blockId=[string]$block.block_id;$actId=if([string]$block.act_id){[string]$block.act_id}else{[regex]::Match($blockId,'^BLOCK-(ACT-\d{3})-\d{3}$').Groups[1].Value}
        if($blockId -notmatch '^BLOCK-ACT-\d{3}-\d{3}$' -or -not $acts.ContainsKey($actId)){$errors.Add("SEMANTIC_PREFLIGHT_BLOCK_IDENTITY_INVALID: $blockId");continue}
        $prose=[string]$block.prose;$refs=@([string[]]@($block.narrative_refs))
        if([string]::IsNullOrWhiteSpace($prose)){$errors.Add("SEMANTIC_PREFLIGHT_PROSE_EMPTY: $blockId");continue}
        $tokens=@(&$wordTokens $prose);$overlap=$null
        if($tokens.Count -ge 8 -and $exemplarNgrams.Count -gt 0){for($i=0;$i -le $tokens.Count-8;$i++){$candidate=$tokens[$i..($i+7)] -join ' ';if($exemplarNgrams.Contains($candidate)){$overlap=$candidate;break}}}
        if($overlap){$findingIndex++;$findings.Add([ordered]@{finding_id=('SP-{0:D3}' -f $findingIndex);class='REVIEW_ALERT';rule_id='VOICE_EXEMPLAR_8GRAM_OVERLAP';act_id=$actId;block_id=$blockId;evidence=$overlap})}
        $directPattern='(?i)(?:\b(?:ty|tobie|ciebie|twoj|twój|twoja|twoje|twoim|twoich|twoją|wy|wam|was|wasz|wasza|wasze|waszym|waszych)\b|\b(?:wyobraź|spójrz|zobacz|pomyśl|przypomnij|zauważ|posłuchaj)(?:cie|my|\s+sobie)?\b)'
        if($prose -match $directPattern -and @($refs|Where-Object{$_ -match '^VC-\d{3}$'}).Count -eq 0){$findingIndex++;$matchText=[regex]::Match($prose,$directPattern).Value;$findings.Add([ordered]@{finding_id=('SP-{0:D3}' -f $findingIndex);class='REVIEW_ALERT';rule_id='UNPLANNED_DIRECT_VIEWER_CONTACT';act_id=$actId;block_id=$blockId;evidence=$matchText})}
        $clearHumorPattern='(?i)(?:\b(?:żartuję|oczywiście\s+żart|to\s+był\s+żart|ha[ -]?ha|hehe+)\b|[😂🤣])'
        if([string]$acts[$actId].humor_mode -ceq 'FORBIDDEN' -and $prose -match $clearHumorPattern){$findingIndex++;$matchText=[regex]::Match($prose,$clearHumorPattern).Value;$findings.Add([ordered]@{finding_id=('SP-{0:D3}' -f $findingIndex);class='HARD_FAIL';rule_id='HUMOR_FORBIDDEN_CLEAR_SIGNAL';act_id=$actId;block_id=$blockId;evidence=$matchText});$errors.Add("HUMOR_FORBIDDEN_CLEAR_SIGNAL: $blockId/$matchText")}
    }
    $data=[ordered]@{schema='NARRATIVE_SEMANTIC_PREFLIGHT_V1';draft_sha256=$DraftSha256;architecture_revision=[string]$ArchitectureData.architecture_revision;voice_exemplars_sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7LfText -Text $VoiceExemplarsText));findings=@($findings)}
    [pscustomobject]@{Valid=$errors.Count -eq 0;GateReady=$errors.Count -eq 0;Errors=@($errors);ReviewAlerts=@($findings|Where-Object{[string]$_.class -ceq 'REVIEW_ALERT'});Data=$data}
}

function Get-SystemV7NarrativeSha256Text {
    param([AllowEmptyString()][Parameter(Mandatory)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text))) }
    finally { $sha.Dispose() }
}

function ConvertTo-SystemV7LfText {
    param([AllowEmptyString()][Parameter(Mandatory)][string]$Text)
    return (($Text -replace "`r`n", "`n") -replace "`r", "`n")
}

function ConvertTo-SystemV7CanonicalNode {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IDictionary]) {
        $ordered = [ordered]@{}
        $names = [string[]]@($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($names, [StringComparer]::Ordinal)
        foreach ($name in $names) { $ordered[$name] = ConvertTo-SystemV7CanonicalNode -Value $Value[$name] }
        return $ordered
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $items=[Collections.Generic.List[object]]::new()
        foreach($item in $Value){$items.Add((ConvertTo-SystemV7CanonicalNode -Value $item))}
        return ,$items.ToArray()
    }
    $ordered = [ordered]@{}
    $names = [string[]]@($Value.PSObject.Properties.Name)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    foreach ($name in $names) { $ordered[$name] = ConvertTo-SystemV7CanonicalNode -Value $Value.$name }
    return $ordered
}

function ConvertTo-SystemV7CanonicalJson {
    param([Parameter(Mandatory)][object]$Value)
    $node = ConvertTo-SystemV7CanonicalNode -Value $Value
    return (($node | ConvertTo-Json -Depth 64 -Compress) + "`n")
}

function Write-SystemV7NarrativeAtomicText {
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowEmptyString()][Parameter(Mandatory)][string]$Text
    )
    $target = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $target
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temp = Join-Path $directory ('.narrative-v2-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temp, (ConvertTo-SystemV7LfText -Text $Text), [Text.UTF8Encoding]::new($false))
    try {
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $backup = Join-Path $directory ('.narrative-v2-backup-' + [guid]::NewGuid().ToString('N') + '.tmp')
            try { [IO.File]::Replace($temp, $target, $backup, $true) }
            finally { if (Test-Path -LiteralPath $backup -PathType Leaf) { [IO.File]::Delete($backup) } }
        } else { [IO.File]::Move($temp, $target) }
    } finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) { [IO.File]::Delete($temp) }
    }
    return $target
}

function Get-SystemV7NarrativeMetaField {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Name)
    $matches = @([regex]::Matches($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
    if ($matches.Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $Name=$($matches.Count)" }
    return $matches[0].Groups[1].Value.Trim()
}

function Set-SystemV7NarrativeMetaField {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Name, [AllowEmptyString()][Parameter(Mandatory)][string]$Value)
    $pattern = "(?m)^$([regex]::Escape($Name)):\s*.*$"
    $matches = @([regex]::Matches($Text, $pattern))
    if ($matches.Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $Name=$($matches.Count)" }
    return [regex]::Replace($Text, $pattern, "$Name`: $Value", 1)
}

function Test-SystemV7NarrativeV2Revision {
    param([Parameter(Mandatory)][string]$MetaText)
    try { return (Get-SystemV7NarrativeMetaField -Text $MetaText -Name 'WORKFLOW_REVISION') -ceq $script:SystemV7NarrativeWorkflowRevision }
    catch { return $false }
}

function Get-SystemV7NarrativeArchitecture {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "ARCHITECTURE_MISSING: $Path" }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match = [regex]::Match($text, '(?s)<!--\s*NARRATIVE_V2_JSON_BEGIN\s*-->\s*```json\s*(?<json>.*?)\s*```\s*<!--\s*NARRATIVE_V2_JSON_END\s*-->')
    if (-not $match.Success) { throw 'NARRATIVE_V2_JSON_BLOCK_MISSING' }
    try { $data = $match.Groups['json'].Value | ConvertFrom-Json -DateKind String -Depth 64 }
    catch { throw "NARRATIVE_V2_JSON_INVALID: $($_.Exception.Message)" }
    $canonical = ConvertTo-SystemV7CanonicalJson -Value $data
    [pscustomobject]@{
        Path = [IO.Path]::GetFullPath($Path)
        Text = $text
        Data = $data
        CanonicalJson = $canonical
        ArchitectureSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        CanonicalSha256 = Get-SystemV7NarrativeSha256Text -Text $canonical
    }
}

function Get-SystemV7EvidenceRegistry {
    param([Parameter(Mandatory)][string]$EvidencePath)
    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) { throw "EVIDENCE_BASE_MISSING: $EvidencePath" }
    $text = Get-Content -LiteralPath $EvidencePath -Raw -Encoding UTF8
    $cards = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $cardPattern = '(?ms)^###\s+(#P-\d{3,})\s*\r?\n(?<body>.*?)(?=^###\s+#P-\d{3,}\s*$|^##\s+|\z)'
    foreach ($match in [regex]::Matches($text, $cardPattern)) {
        $id = $match.Groups[1].Value
        $body = $match.Groups['body'].Value
        $get = {
            param($name)
            $m = [regex]::Match($body, "(?m)^$([regex]::Escape($name)):\s*(.*?)\s*$")
            if ($m.Success) { $m.Groups[1].Value.Trim() } else { '' }
        }
        $cards.Add($id, [pscustomobject]@{
            p_id = $id
            content = & $get 'TREŚĆ'
            source_id = & $get 'ŹRÓDŁO_ID'
            locator = & $get 'LOKALIZACJA'
            qa_k1 = & $get 'QA_K1'
        })
    }
    $sources = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -notmatch '^\|\s*(#S-\d{3,})\s*\|') { continue }
        $id = $Matches[1]
        if (-not $sources.ContainsKey($id)) { $sources.Add($id, $line.Trim()) }
    }
    [pscustomobject]@{
        Text = $text
        EvidenceSha256 = (Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash
        Cards = $cards
        Sources = $sources
    }
}

function Test-SystemV7ConcreteText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $false }
    $text = ([string]$Value).Trim()
    return $text.Length -ge 2 -and $text -notmatch '^(?:BRAK|NIEUSTALONE|DO UZUPEŁNIENIA|\[.*\])$'
}

function Test-SystemV7SingleObligationText {
    param([AllowNull()][object]$Value)
    if(-not(Test-SystemV7ConcreteText -Value $Value)){return $false}
    $text=([string]$Value).Trim()
    # Only the heuristic projection changes; the original obligation is retained.
    $text=[regex]::Replace($text,'(?<=\d),(?=\d)','·')
    $text=[regex]::Replace($text,'\b(\d{4})/(\d{2}|\d{4})\b','$1–$2')
    $text=[regex]::Replace($text,'\bI(?=\s+(?:wojn\w*|Rzeczpospolit\w*|wieku|wiek\b))','Ⅰ')
    $text=[regex]::Replace($text,'(?i)\b(?:dr|prof|mgr|inż|r|np|tj|tzn|itd|itp)\.',{param($m)$m.Value.Replace('.','·')})
    $text=[regex]::Replace($text,'(?i)\bSodoma i Gomora\b','Sodoma & Gomora')
    $text=[regex]::Replace($text,'(?i)\braz i na zawsze\b','definitywnie')
    if($text -match '[;/\r\n•]' -or $text -match '(?:^|\s)\d+[.)]\s' -or $text -match '\b(?:po pierwsze|po drugie|po trzecie)\b'){return $false}
    # Odrzucamy wyliczenie czterech obowiązków (dwa przecinki plus końcowe
    # „i/oraz”) oraz dłuższe listy. Dwa przecinki pozostają legalne tylko bez
    # takiej końcowej enumeracji, np. w opisie zależnej transformacji ACT.
    if(@([regex]::Matches($text,',')).Count -gt 2){return $false}
    if($text -match ',[^,]+,\s*[^,]+\b(?:i|oraz)\b'){return $false}
    if(@([regex]::Matches($text,'(?i)\b(?:i|oraz|lub|albo|a\s+także)\b')).Count -gt 1){return $false}
    if(@([regex]::Matches($text,'[.!?](?:\s+|$)')).Count -gt 1){return $false}
    return $true
}

function Test-SystemV7AtomicPacketFieldText {
    param([AllowNull()][object]$Value)
    if(-not(Test-SystemV7SingleObligationText -Value $Value)){return $false}
    $text=([string]$Value).Trim()
    # Pola pakietu są pojedynczymi kontraktami, a nie miejscem na listę zadań.
    # Dwa przecinki wystarczają, aby ukryć trzy osobne rozkazy bez spójnika
    # (np. „ujawnij, pokaż, domknij”), dlatego tutaj obowiązuje reguła
    # ostrzejsza niż dla opisowych pól rejestru CID.
    if(@([regex]::Matches($text,',')).Count -gt 1){return $false}
    return $true
}

function Test-SystemV7ConstraintActionClosedForm {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$SourceField,
        [Parameter(Mandatory)][string[]]$ObjectIds,
        [Parameter(Mandatory)][string]$ActId
    )
    if(-not(Test-SystemV7SingleObligationText -Value $Action)){return $false}
    $text=$Action.Trim().TrimEnd('.')
    $tokens=@($ObjectIds)
    if($tokens.Count -eq 1){
        # Jedno CID z jednym obiektem nie może ukrywać drugiej komendy po
        # przecinku, ukośniku ani spójniku. To jest celowo fail-closed.
        return $text -notmatch '[,/]' -and $text -notmatch '(?i)\b(?:i|oraz|lub|albo|a\s+także)\b'
    }
    if($SourceField -ceq 'ACT_FUNCTION'){
        $required=@("ACT_FUNCTION:$ActId","VIEWER_STATE:$ActId","BRIDGE:$ActId")
        if(@($required|Where-Object{$_ -notin $tokens}).Count -gt 0){return $false}
        $hasCompletion='COMPLETION:001' -in $tokens
        $expected=if($hasCompletion){'Zrealizuj funkcję aktu, zmianę stanu i most, a completion potraktuj jako kryterium odbioru tej samej transformacji'}else{'Zrealizuj funkcję aktu, zmianę stanu i most'}
        return $text -ceq $expected
    }
    if($SourceField -ceq 'SW'){
        $swTokens=@($tokens|Where-Object{$_ -match '^SW:(SW-\d{3})$'})
        if($swTokens.Count -ne 1 -or @($tokens|Where-Object{$_ -notmatch '^(?:SW:|REQUIRED:)'}).Count -gt 0){return $false}
        $swId=$swTokens[0].Substring(3)
        return $text -ceq "Wykonaj jednostkę $swId z kompletem przypisanych dowodów"
    }
    if($SourceField -ceq 'NR'){
        $nrTokens=@($tokens|Where-Object{$_ -match '^NR:SETUP:(NR-\d{3})$'})
        $embargoTokens=@($tokens|Where-Object{$_ -match '^DO_NOT_REVEAL:\d{3}$'})
        if($nrTokens.Count -ne 1 -or $embargoTokens.Count -ne 1 -or $tokens.Count -ne 2){return $false}
        $nrId=([regex]::Match($nrTokens[0],'^NR:SETUP:(NR-\d{3})$')).Groups[1].Value
        return $text -ceq "Wykonaj przygotowanie $nrId z przypisanym embargiem"
    }
    return $false
}

function Get-SystemV7ConstraintAtomicityState {
    param([Parameter(Mandatory)][object]$Packet,[Parameter(Mandatory)][object]$Ledger)
    $errors=[Collections.Generic.List[string]]::new();$actId=[string]$Packet.act_id
    $expected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($token in @("ACT_FUNCTION:$actId","VIEWER_STATE:$actId","BRIDGE:$actId","CONTINUITY_OUT:$actId")){$null=$expected.Add($token)}
    $completion=@($Packet.completion_criteria)
    if($completion.Count -ne 1 -or -not(Test-SystemV7AtomicPacketFieldText -Value ([string]$completion[0]))){$errors.Add("ATOMIC_COMPLETION_COUNT_OR_FORM_INVALID: $($completion.Count)")}
    for($i=0;$i -lt $completion.Count;$i++){
        $value=[string]$completion[$i]
        if(-not(Test-SystemV7AtomicPacketFieldText -Value $value)){$errors.Add("ATOMIC_COMPLETION_LIST_LIKE: $($i+1)")}
        $null=$expected.Add(('COMPLETION:{0:D3}' -f ($i+1)))
    }
    $sceneIds=@([string[]]@($Packet.scene_weave_ids));$seenScene=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($swId in $sceneIds){if(-not $seenScene.Add($swId)){$errors.Add("ATOMIC_SW_DUPLICATE: $swId")};$null=$expected.Add("SW:$swId")}
    $sceneRequired=@{}
    foreach($scene in @($Packet.scene_contracts)){
        $swId=[string]$scene.sw_id
        if($swId -notin $sceneIds){$errors.Add("ATOMIC_SCENE_CONTRACT_UNEXPECTED: $swId");continue}
        if($sceneRequired.ContainsKey($swId)){$errors.Add("ATOMIC_SCENE_CONTRACT_DUPLICATE: $swId");continue}
        $required=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($evidenceId in @($scene.required_p)){if(-not $required.Add([string]$evidenceId)){$errors.Add("ATOMIC_REQUIRED_DUPLICATE: $swId/$evidenceId")};$null=$expected.Add("REQUIRED:$swId/$evidenceId")}
        $sceneRequired[$swId]=$required
        foreach($field in @('function','bridge_out','completion_criteria')){if(@($scene.PSObject.Properties.Name) -contains $field -and -not(Test-SystemV7AtomicPacketFieldText -Value ([string]$scene.$field))){$errors.Add("ATOMIC_SCENE_FIELD_NOT_SINGLE_PURPOSE: $swId/$field")}}
    }
    foreach($swId in $sceneIds){if(-not $sceneRequired.ContainsKey($swId)){$errors.Add("ATOMIC_SCENE_CONTRACT_MISSING: $swId")}}
    foreach($action in @($Packet.nq_actions)){$null=$expected.Add("NQ:$action")}
    foreach($action in @($Packet.nr_actions)){$null=$expected.Add("NR:$action")}
    foreach($vc in @($Packet.vc_ids)){$null=$expected.Add("VC:$vc")}
    if([string]$Packet.humor_mode -ceq 'FORBIDDEN'){$null=$expected.Add("HUMOR_MODE:$actId")}
    if([string]$Packet.narrator_mode -cne 'DEFAULT'){$null=$expected.Add("NARRATOR_MODE:$actId")}
    foreach($field in @('act_function','bridge_out')){if(@($Packet.PSObject.Properties.Name) -contains $field -and -not(Test-SystemV7AtomicPacketFieldText -Value ([string]$Packet.$field))){$errors.Add("ATOMIC_ACT_FIELD_NOT_SINGLE_PURPOSE: $field")}}
    $doNot=@();if(@($Packet.PSObject.Properties.Name) -contains 'do_not_reveal'){$doNot=@($Packet.do_not_reveal)}
    $embargoNrByToken=@{};$embargoNrSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for($i=0;$i -lt $doNot.Count;$i++){
        $token='DO_NOT_REVEAL:{0:D3}' -f ($i+1);$null=$expected.Add($token);$value=[string]$doNot[$i]
        $match=[regex]::Match($value,'^(NR-\d{3}) przed (SW-\d{3})$')
        if(-not $match.Success){$errors.Add("ATOMIC_EMBARGO_FORMAT_INVALID: $token")}
        else{$nrId=$match.Groups[1].Value;if(-not $embargoNrSeen.Add($nrId)){$errors.Add("ATOMIC_MULTIPLE_EMBARGOS_FOR_ONE_REVEAL: $nrId")};$embargoNrByToken[$token]=$nrId}
    }
    $constraints=@($Ledger.constraints)
    if([string]$Ledger.schema -cne 'CONSTRAINT_LEDGER_V1' -or [string]$Ledger.act_id -cne $actId -or [int]$Ledger.max_total -ne $script:SystemV7NarrativeMaxConstraints -or [int]$Ledger.actual_total -ne $constraints.Count){$errors.Add('ATOMIC_LEDGER_HEADER_INVALID')}
    if($constraints.Count -lt 1 -or $constraints.Count -gt $script:SystemV7NarrativeMaxConstraints){$errors.Add("ATOMIC_CONSTRAINT_COUNT_INVALID: $($constraints.Count)")}
    $covered=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$cidSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$continuityCount=0;$unbundledCount=0
    for($index=0;$index -lt $constraints.Count;$index++){
        $constraint=$constraints[$index];$cid=[string]$constraint.cid;$source=[string]$constraint.source_field
        $fields=@('cid','source_field','action','object_ids','why_hard','atomicity_reason','verification')
        if(@($constraint.PSObject.Properties.Name).Count -ne $fields.Count -or @(Compare-Object -ReferenceObject $fields -DifferenceObject @($constraint.PSObject.Properties.Name)).Count -gt 0){$errors.Add("ATOMIC_CID_FIELDS_INVALID: $cid")}
        $expectedCid='CID-{0:D3}' -f ($index+1);if($cid -cne $expectedCid -or -not $cidSeen.Add($cid)){$errors.Add("ATOMIC_CID_SEQUENCE_INVALID: $cid")}
        foreach($field in @('action','why_hard','atomicity_reason','verification')){if(-not(Test-SystemV7SingleObligationText -Value ([string]$constraint.$field))){$errors.Add("ATOMIC_CID_TEXT_NOT_SINGLE_PURPOSE: $cid/$field")}}
        $tokens=@([string[]]@($constraint.object_ids));$tokenSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        if($tokens.Count -eq 0){$errors.Add("ATOMIC_CID_OBJECTS_EMPTY: $cid")}
        foreach($token in $tokens){if(-not $tokenSet.Add($token)){$errors.Add("ATOMIC_CID_OBJECT_DUPLICATE: $cid/$token")};if(-not $expected.Contains($token)){$errors.Add("ATOMIC_CID_OBJECT_UNEXPECTED: $cid/$token")}elseif(-not $covered.Add($token)){$errors.Add("ATOMIC_CID_COVERAGE_DUPLICATE: $token")}}
        $legal=$false
        if($source -ceq 'ACT_FUNCTION'){
            $base=@("ACT_FUNCTION:$actId","VIEWER_STATE:$actId","BRIDGE:$actId");$allowed=@($base);if($completion.Count -eq 1){$allowed+=@('COMPLETION:001')}
            $legal=($tokens.Count -eq $base.Count -or $tokens.Count -eq $allowed.Count) -and @($tokens|Where-Object{$_ -notin $allowed}).Count -eq 0 -and @($base|Where-Object{-not $tokenSet.Contains($_)}).Count -eq 0
        }elseif($source -ceq 'SW'){
            $swTokens=@($tokens|Where-Object{$_ -match '^SW:'})
            if($swTokens.Count -eq 1){$swId=$swTokens[0].Substring(3);$allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$null=$allowed.Add("SW:$swId");if($sceneRequired.ContainsKey($swId)){foreach($p in @($sceneRequired[$swId])){$null=$allowed.Add("REQUIRED:$swId/$p")}};$legal=$tokens.Count -eq $allowed.Count -and @($tokens|Where-Object{-not $allowed.Contains($_)}).Count -eq 0}
        }elseif($source -ceq 'NR'){
            $nrTokens=@($tokens|Where-Object{$_ -match '^NR:'});$embargoTokens=@($tokens|Where-Object{$_ -match '^DO_NOT_REVEAL:'})
            if($nrTokens.Count -eq 1 -and $tokens.Count -le 2){$nrMatch=[regex]::Match($nrTokens[0],'^NR:SETUP:(NR-\d{3})$');$legal=$tokens.Count -eq 1 -or ($nrMatch.Success -and $embargoTokens.Count -eq 1 -and $embargoNrByToken.ContainsKey($embargoTokens[0]) -and [string]$embargoNrByToken[$embargoTokens[0]] -ceq $nrMatch.Groups[1].Value)}
        }else{$legal=$tokens.Count -eq 1 -and ([string]$tokens[0]).StartsWith(($source+':'),[StringComparison]::Ordinal)}
        if(-not(Test-SystemV7ConstraintActionClosedForm -Action ([string]$constraint.action) -SourceField $source -ObjectIds $tokens -ActId $actId)){$errors.Add("ATOMIC_CID_ACTION_CLOSED_FORM_INVALID: $cid")}
        if(-not $legal){$errors.Add("ATOMIC_CID_BUNDLES_INDEPENDENT_ACTIONS: $cid");$unbundledCount+=[math]::Max(1,$tokens.Count)}else{$unbundledCount++}
        if($source -ceq 'CONTINUITY_OUT'){$continuityCount++}
    }
    foreach($token in @($expected)){if(-not $covered.Contains($token)){$errors.Add("ATOMIC_REQUIRED_OBJECT_MISSING: $token")}}
    if($continuityCount -ne 1){$errors.Add("ATOMIC_CONTINUITY_COUNT_INVALID: $continuityCount")}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);ActId=$actId;AtomicCount=$constraints.Count;UnbundledConstraintCount=$unbundledCount;ExpectedObjects=@($expected);CoveredObjects=@($covered)}
}

function Get-SystemV7AuthorTextApprovalState {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][ValidatePattern('^VC-\d{3}$')][string]$ExpectedVcId,
        [Parameter(Mandatory)][string]$ExpectedAuthorText
    )
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    try{$path=[IO.Path]::GetFullPath($ReceiptPath);$authorRoot=[IO.Path]::GetFullPath((Join-Path $project '_work\k2\author-text'));$prefix=$authorRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;if(-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'outside-project-author-text-root'}}catch{return [pscustomobject]@{Valid=$false;Errors=@('AUTHOR_TEXT_RECEIPT_PATH_INVALID');Data=$null;Path=$null}}
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('AUTHOR_TEXT_RECEIPT_MISSING');Data=$null;Path=$path}}
    try{$raw=Get-Content -LiteralPath $path -Raw -Encoding UTF8;$data=$raw|ConvertFrom-Json -DateKind String -Depth 32}catch{return [pscustomobject]@{Valid=$false;Errors=@('AUTHOR_TEXT_RECEIPT_INVALID_JSON');Data=$null;Path=$path}}
    $fields=@('schema','workflow_revision','actor','attestation_scope','project_origin_sha256','reuse_policy','vc_id','author_text','author_text_sha256','approval_note','approved_at_utc','binding_sha256')
    if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0 -or @($data.PSObject.Properties.Name).Count -ne $fields.Count){$errors.Add('AUTHOR_TEXT_RECEIPT_FIELDS_INVALID')}
    if((ConvertTo-SystemV7CanonicalJson -Value $data) -cne (ConvertTo-SystemV7LfText -Text $raw)){$errors.Add('AUTHOR_TEXT_RECEIPT_NOT_CANONICAL')}
    $origin=if($null -ne (Get-Command Get-SystemV7ProjectOriginState -ErrorAction SilentlyContinue)){Get-SystemV7ProjectOriginState -ProjectPath $project}else{$null}
    if($null -eq $origin -or -not $origin.Valid){$errors.Add('AUTHOR_TEXT_PROJECT_ORIGIN_INVALID')}
    $text=((ConvertTo-SystemV7LfText -Text $ExpectedAuthorText).Trim()+"`n");$textSha=Get-SystemV7NarrativeSha256Text -Text $text
    $expectedRelative="_work/k2/author-text/$ExpectedVcId-$textSha.json";$actualRelative=[IO.Path]::GetRelativePath($project,$path).Replace('\','/')
    if($actualRelative -cne $expectedRelative){$errors.Add('AUTHOR_TEXT_RECEIPT_FILENAME_BINDING_INVALID')}
    if([string]$data.schema -cne 'SYSTEM_V7_AUTHOR_TEXT_APPROVAL_V1' -or [string]$data.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$data.actor -cne 'DAWID' -or [string]$data.attestation_scope -cne 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY' -or [string]$data.reuse_policy -cne 'PROJECT_ONLY' -or [string]$data.vc_id -cne $ExpectedVcId -or [string]$data.author_text -cne $ExpectedAuthorText -or [string]$data.author_text_sha256 -cne $textSha){$errors.Add('AUTHOR_TEXT_RECEIPT_IDENTITY_INVALID')}
    if($origin -and $origin.Valid -and [string]$data.project_origin_sha256 -cne [string]$origin.Sha256){$errors.Add('AUTHOR_TEXT_RECEIPT_PROJECT_ORIGIN_MISMATCH')}
    if(-not(Test-SystemV7ConcreteText -Value ([string]$data.approval_note)) -or [string]$data.approval_note.Length -lt 12){$errors.Add('AUTHOR_TEXT_RECEIPT_NOTE_INVALID')}
    $approved=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse([string]$data.approved_at_utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$approved) -or $approved -gt [DateTimeOffset]::UtcNow.AddMinutes(5)){$errors.Add('AUTHOR_TEXT_RECEIPT_TIME_INVALID')}
    $copy=[ordered]@{};foreach($property in $data.PSObject.Properties){if($property.Name -cne 'binding_sha256'){$copy[$property.Name]=$property.Value}}
    if([string]$data.binding_sha256 -cne (Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy))){$errors.Add('AUTHOR_TEXT_RECEIPT_BINDING_INVALID')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Data=$data;Path=$path;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;AuthorTextSha256=$textSha}
}

function Test-SystemV7NarrativeArchitecture {
    param(
        [Parameter(Mandatory)][string]$ArchitecturePath,
        [Parameter(Mandatory)][string]$EvidencePath
    )
    $errors = [Collections.Generic.List[string]]::new()
    $warnings = [Collections.Generic.List[string]]::new()
    try { $architecture = Get-SystemV7NarrativeArchitecture -Path $ArchitecturePath }
    catch {
        $errors.Add($_.Exception.Message)
        return [pscustomobject]@{ Verdict='ARCHITECTURE_FAIL'; GateReady=$false; Errors=$errors.Count; Warnings=0; ErrorDetails=@($errors); WarningDetails=@(); Architecture=$null }
    }
    try { $evidence = Get-SystemV7EvidenceRegistry -EvidencePath $EvidencePath }
    catch {
        $errors.Add($_.Exception.Message)
        return [pscustomobject]@{ Verdict='ARCHITECTURE_FAIL'; GateReady=$false; Errors=$errors.Count; Warnings=0; ErrorDetails=@($errors); WarningDetails=@(); Architecture=$architecture }
    }
    $data = $architecture.Data
    if ([string]$data.schema -cne $script:SystemV7NarrativeArchitectureSchema) { $errors.Add('SCHEMA_REVISION_MISMATCH: architecture schema') }
    $testExact={param($object,[string[]]$expected,[string]$code)if($null -eq $object -or @(Compare-Object -ReferenceObject $expected -DifferenceObject @($object.PSObject.Properties.Name)).Count -gt 0 -or @($object.PSObject.Properties.Name).Count -ne $expected.Count){$errors.Add("${code}_FIELDS_INVALID");return $false};return $true}
    $null=&$testExact $data @('schema','architecture_revision','selected_direction','directions','story_dna','hook_contract','final_contract','questions','reveals','viewer_contacts','scene_weave','acts','k2b') 'ARCHITECTURE'
    if ($architecture.Text -match '(?i)K3_BUDGET_OVERRIDE|Budżet\s+słów|WORD_BUDGET|CHARACTER_BUDGET|EXPOSITION_BUDGET|NEW_NAMES_BUDGET|HARD_MIN') {
        $errors.Add('MIXED_SCHEMA: Narrative V2 nie dopuszcza pól budżetowych ani HARD_MIN.')
    }

    $storyFields = @('central_question','viewer_promise','starting_model','destabilizing_fact','deeper_model','human_stake','external_stake','value_conflict','knowledge_boundary','final_transformation','final_image_or_thought')
    foreach ($field in $storyFields) {
        if (-not (Test-SystemV7ConcreteText $data.story_dna.$field)) { $errors.Add("STORY_DNA_FIELD_MISSING: $field") }
    }
    foreach ($field in @('concrete_anomaly_or_consequence','honest_promise','why_it_matters','minimum_context','first_question_or_model_shift','embargo')) {
        if (-not (Test-SystemV7ConcreteText $data.hook_contract.$field)) { $errors.Add("HOOK_CONTRACT_FIELD_MISSING: $field") }
    }
    foreach ($field in @('central_question_resolution','reveal_consequence','knowledge_boundary','hook_payoff','new_model_or_final_image')) {
        if (-not (Test-SystemV7ConcreteText $data.final_contract.$field)) { $errors.Add("FINAL_CONTRACT_FIELD_MISSING: $field") }
    }
    if ($data.final_contract.must_not_open_new_major_topic -cne $true) { $errors.Add('FINAL_CONTRACT_MUST_BLOCK_NEW_MAJOR_TOPIC') }

    $directionIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($direction in @($data.directions)){
        $null=&$testExact $direction @('direction_id','axis','conflict','promise','core_p_ids','narrative_concrete','risk_advantage') 'DIRECTION'
        $directionId=[string]$direction.direction_id;if($directionId -notmatch '^[A-Z][A-Z0-9_-]{0,15}$' -or -not $directionIds.Add($directionId)){$errors.Add("DIRECTION_ID_INVALID_OR_DUPLICATE: $directionId")}
        foreach($field in @('axis','conflict','promise','narrative_concrete','risk_advantage')){if(-not(Test-SystemV7ConcreteText $direction.$field)){$errors.Add("DIRECTION_FIELD_MISSING: $directionId/$field")}}
        if(@($direction.core_p_ids).Count -eq 0){$errors.Add("DIRECTION_CORE_EMPTY: $directionId")};foreach($p in @($direction.core_p_ids)){if(-not $evidence.Cards.ContainsKey([string]$p)){$errors.Add("DIRECTION_CARD_MISSING: $directionId/$p")}}
    }
    if($directionIds.Count -lt 1){$errors.Add('DIRECTION_COUNT_TOO_SMALL')}
    elseif($directionIds.Count -eq 1){
        $project=Split-Path -Parent ([IO.Path]::GetFullPath($ArchitecturePath));$target=[string]$data.selected_direction
        if($null -eq (Get-Command Get-EditorialExceptionReceiptState -ErrorAction SilentlyContinue)){$errors.Add('ONE_DIRECTION_RECEIPT_VALIDATOR_UNAVAILABLE')}
        else{
            $oneDirection=Get-EditorialExceptionReceiptState -ProjectPath $project -ExceptionType K2_ONE_DIRECTION -ArtifactPath $ArchitecturePath -TargetId $target -ExpectedDecision 'ALLOW_ONE_DIRECTION' -ExpectedScope 'JEDEN_KIERUNEK'
            if(-not $oneDirection.Valid){$errors.Add("ONE_DIRECTION_RECEIPT_INVALID: $($oneDirection.Errors -join ',')")}
        }
    }
    if(-not $directionIds.Contains([string]$data.selected_direction)){$errors.Add('SELECTED_DIRECTION_MISSING')}

    $idSets = @{
        NQ = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        NR = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        VC = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        SW = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        ACT = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    }
    foreach ($q in @($data.questions)) {
        $null=&$testExact $q @('nq_id','question','opened_at','why_care','expected_form','payoff_node','status') 'NQ'
        $id = [string]$q.nq_id
        if ($id -notmatch '^NQ-\d{3}$' -or -not $idSets.NQ.Add($id)) { $errors.Add("NQ_ID_INVALID_OR_DUPLICATE: $id") }
        foreach ($f in @('question','opened_at','why_care','expected_form','payoff_node','status')) { if (-not (Test-SystemV7ConcreteText $q.$f)) { $errors.Add("NQ_FIELD_MISSING: $id/$f") } }
        if (-not (Test-SystemV7ExactMember -Value ([string]$q.status) -Allowed @('CLOSED','OPEN','REFRAMED','UNRESOLVABLE'))) { $errors.Add("NQ_STATUS_INVALID: $id") }
        if(-not (Test-SystemV7ExactMember -Value ([string]$q.expected_form) -Allowed @('ANSWER','REFRAME','UNRESOLVABLE'))){$errors.Add("NQ_EXPECTED_FORM_INVALID: $id")}
    }
    foreach ($reveal in @($data.reveals)) {
        $null=&$testExact $reveal @('nr_id','reveal','evidence_p_ids','earliest_legal_node','target_node','setup_required','do_not_reveal_before','consequence','uncertainty_form') 'NR'
        $id = [string]$reveal.nr_id
        if ($id -notmatch '^NR-\d{3}$' -or -not $idSets.NR.Add($id)) { $errors.Add("NR_ID_INVALID_OR_DUPLICATE: $id") }
        foreach ($f in @('reveal','earliest_legal_node','target_node','setup_required','do_not_reveal_before','consequence','uncertainty_form')) { if (-not (Test-SystemV7ConcreteText $reveal.$f) -and -not ($f -ceq 'setup_required' -and [string]$reveal.$f -ceq 'BRAK')) { $errors.Add("NR_FIELD_MISSING: $id/$f") } }
        if([string]$reveal.setup_required -in @('YES','NO','TAK','NIE')){$errors.Add("NR_SETUP_REQUIRED_MUST_BE_CONTENT_OR_BRAK: $id")}
        if(@($reveal.evidence_p_ids).Count -eq 0){$errors.Add("NR_EVIDENCE_EMPTY: $id")};foreach ($p in @($reveal.evidence_p_ids)) { if (-not $evidence.Cards.ContainsKey([string]$p)) { $errors.Add("NR_CARD_MISSING: $id/$p") } }
    }
    foreach ($vc in @($data.viewer_contacts)) {
        $null=&$testExact $vc @('vc_id','node','function','level','purpose','risk','author_text','approval','approval_receipt_relative','approval_receipt_sha256') 'VC'
        $id = [string]$vc.vc_id
        if ($id -notmatch '^VC-\d{3}$' -or -not $idSets.VC.Add($id)) { $errors.Add("VC_ID_INVALID_OR_DUPLICATE: $id") }
        foreach ($f in @('node','function','level','purpose','risk','approval')) { if (-not (Test-SystemV7ConcreteText $vc.$f)) { $errors.Add("VC_FIELD_MISSING: $id/$f") } }
        if(-not (Test-SystemV7ExactMember -Value ([string]$vc.function) -Allowed @('ORIENT','PREDICT','RECALL','REFRAME','KNOWLEDGE','AUTHOR'))){$errors.Add("VC_FUNCTION_INVALID: $id")}
        if(-not (Test-SystemV7ExactMember -Value ([string]$vc.level) -Allowed @('MICRO','STRUCTURAL','AUTHORIAL'))){$errors.Add("VC_LEVEL_INVALID: $id")}
        $requiresAuthor=[string]$vc.function -ceq 'AUTHOR' -or [string]$vc.level -ceq 'AUTHORIAL'
        if($requiresAuthor){
            if(-not(Test-SystemV7ConcreteText $vc.author_text) -or [string]$vc.author_text -ceq 'BRAK' -or [string]$vc.approval -cne 'DAWID_APPROVED'){$errors.Add("AUTHOR_TEXT_REQUIRED_EXACT_APPROVAL: $id")}
            $receiptRelative=[string]$vc.approval_receipt_relative;$receiptSha=[string]$vc.approval_receipt_sha256
            try{$projectRoot=Split-Path -Parent ([IO.Path]::GetFullPath($ArchitecturePath));$receiptPath=[IO.Path]::GetFullPath((Join-Path $projectRoot $receiptRelative));$receiptState=Get-SystemV7AuthorTextApprovalState -ProjectPath $projectRoot -ReceiptPath $receiptPath -ExpectedVcId $id -ExpectedAuthorText ([string]$vc.author_text);if(-not $receiptState.Valid -or $receiptSha -notmatch '^[A-F0-9]{64}$' -or [string]$receiptState.Sha256 -cne $receiptSha){throw ($receiptState.Errors -join ',')}}catch{$errors.Add("AUTHOR_TEXT_APPROVAL_RECEIPT_INVALID: $id/$($_.Exception.Message)")}
        } elseif([string]$vc.author_text -cne 'BRAK' -or [string]$vc.approval -cne 'NOT_REQUIRED' -or [string]$vc.approval_receipt_relative -cne 'BRAK' -or [string]$vc.approval_receipt_sha256 -cne 'BRAK'){$errors.Add("AUTHOR_TEXT_UNEXPECTED_WITHOUT_AUTHORIAL_VC: $id")}
    }

    foreach ($sw in @($data.scene_weave)) {
        $null=&$testExact $sw @('sw_id','act_id','scene_or_unit','function','entry_knowledge_state','exit_knowledge_state','emotional_pressure','required_evidence','supporting_p_ids','reserve_p_ids','nq_action','nr_action','local_stake','bridge_out','completion_criteria') 'SW'
        $id = [string]$sw.sw_id
        if ($id -notmatch '^SW-\d{3}$' -or -not $idSets.SW.Add($id)) { $errors.Add("SW_ID_INVALID_OR_DUPLICATE: $id") }
        foreach ($f in @('act_id','scene_or_unit','function','entry_knowledge_state','exit_knowledge_state','emotional_pressure','local_stake','bridge_out','completion_criteria')) { if (-not (Test-SystemV7ConcreteText $sw.$f)) { $errors.Add("SW_FIELD_MISSING: $id/$f") } }
        if ([string]$sw.entry_knowledge_state -ceq [string]$sw.exit_knowledge_state) { $errors.Add("SW_STATE_DOES_NOT_CHANGE: $id") }
        $seenP = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($required in @($sw.required_evidence)) {
            $null=&$testExact $required @('p_id','function','necessity') 'SW_REQUIRED'
            $p = [string]$required.p_id
            if (-not $seenP.Add($p)) { $errors.Add("SW_REQUIRED_DUPLICATE: $id/$p") }
            if (-not $evidence.Cards.ContainsKey($p)) { $errors.Add("SW_REQUIRED_CARD_MISSING: $id/$p") }
            elseif ([string]$evidence.Cards[$p].qa_k1 -cne 'GOTOWA') { $errors.Add("SW_REQUIRED_CARD_NOT_READY: $id/$p") }
            if (-not (Test-SystemV7ConcreteText $required.function) -or -not (Test-SystemV7ConcreteText $required.necessity)) { $errors.Add("SW_REQUIRED_FUNCTION_MISSING: $id/$p") }
        }
        if (@($sw.required_evidence).Count -eq 0) { $errors.Add("SW_WITHOUT_REQUIRED: $id") }
        foreach ($p in @($sw.supporting_p_ids)) {
            if (-not $evidence.Cards.ContainsKey([string]$p)) { $errors.Add("SW_SUPPORTING_CARD_MISSING: $id/$p") }
            elseif ([string]$evidence.Cards[[string]$p].qa_k1 -cne 'GOTOWA') { $errors.Add("SW_SUPPORTING_CARD_NOT_READY: $id/$p") }
            if (-not $seenP.Add([string]$p)) { $errors.Add("SW_EVIDENCE_ROLE_CONFLICT: $id/$p") }
        }
        foreach ($p in @($sw.reserve_p_ids)) {
            if (-not $evidence.Cards.ContainsKey([string]$p)) { $errors.Add("SW_RESERVE_CARD_MISSING: $id/$p") }
            if (-not $seenP.Add([string]$p)) { $errors.Add("SW_EVIDENCE_ROLE_CONFLICT: $id/$p") }
        }
    }

    $acts = @($data.acts)
    for ($index = 0; $index -lt $acts.Count; $index++) {
        $act = $acts[$index]
        $null=&$testExact $act @('act_id','label','act_function','entry_knowledge_state','intended_emotional_pressure_in','exit_knowledge_state','intended_emotional_pressure_out','state_change_evidence','failure_if_removed','relative_weight','exposition_risk','new_names','complexity_flag','scene_weave_ids','open_nq_ids','nq_actions','nr_actions','vc_ids','humor_mode','narrator_mode','completion_criteria','bridge_out','do_not_reveal','constraints') 'ACT'
        $id = [string]$act.act_id
        $expectedId = 'ACT-{0:D3}' -f ($index + 1)
        if ($id -cne $expectedId -or -not $idSets.ACT.Add($id)) { $errors.Add("ACT_ID_SEQUENCE_INVALID: expected=$expectedId actual=$id") }
        foreach ($f in @('label','act_function','entry_knowledge_state','intended_emotional_pressure_in','exit_knowledge_state','intended_emotional_pressure_out','state_change_evidence','failure_if_removed','relative_weight','exposition_risk','complexity_flag','bridge_out')) { if (-not (Test-SystemV7ConcreteText $act.$f)) { $errors.Add("ACT_FIELD_MISSING: $id/$f") } }
        if ([string]$act.entry_knowledge_state -ceq [string]$act.exit_knowledge_state) { $errors.Add("ACT_STATE_DOES_NOT_CHANGE: $id") }
        if (-not (Test-SystemV7ExactMember -Value ([string]$act.relative_weight) -Allowed @('LIGHT','MEDIUM','HEAVY'))) { $errors.Add("ACT_WEIGHT_INVALID: $id") }
        if (-not (Test-SystemV7ExactMember -Value ([string]$act.exposition_risk) -Allowed @('LOW','MEDIUM','HIGH'))) { $errors.Add("ACT_EXPOSITION_RISK_INVALID: $id") }
        if (-not (Test-SystemV7ExactMember -Value ([string]$act.complexity_flag) -Allowed @('SIMPLE','COMPLEX'))) { $errors.Add("ACT_COMPLEXITY_INVALID: $id") }
        if (-not (Test-SystemV7ExactMember -Value ([string]$act.humor_mode) -Allowed @('FORBIDDEN','ALLOWED'))) { $errors.Add("ACT_HUMOR_MODE_INVALID: $id") }
        if(-not (Test-SystemV7ExactMember -Value ([string]$act.narrator_mode) -Allowed @('DEFAULT','NEUTRAL','AUTHOR_TEXT_ONLY'))){$errors.Add("ACT_NARRATOR_MODE_INVALID: $id")}
        if (@($act.scene_weave_ids).Count -eq 0) { $errors.Add("ACT_WITHOUT_SCENE_WEAVE: $id") }
        $actSwSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($swId in @($act.scene_weave_ids)) {
            if(-not $actSwSet.Add([string]$swId)){$errors.Add("ACT_SW_DUPLICATE: $id/$swId")}
            if (-not $idSets.SW.Contains([string]$swId)) { $errors.Add("ACT_SW_MISSING: $id/$swId") }
            $owner = @($data.scene_weave | Where-Object { [string]$_.sw_id -ceq [string]$swId } | Select-Object -First 1)
            if ($owner.Count -eq 1 -and [string]$owner[0].act_id -cne $id) { $errors.Add("ACT_SW_OWNER_MISMATCH: $id/$swId") }
        }
        if(-not $actSwSet.Contains([string]$act.state_change_evidence)){$errors.Add("ACT_STATE_CHANGE_EVIDENCE_INVALID: $id/$($act.state_change_evidence)")}
        $orderedActSw=@($act.scene_weave_ids|ForEach-Object{$swId=$_;@($data.scene_weave|Where-Object{[string]$_.sw_id -ceq [string]$swId}|Select-Object -First 1)}|Where-Object{$_})
        if($orderedActSw.Count -gt 0){if([string]$orderedActSw[0].entry_knowledge_state -cne [string]$act.entry_knowledge_state){$errors.Add("ACT_ENTRY_STATE_SW_MISMATCH: $id")};if([string]$orderedActSw[-1].exit_knowledge_state -cne [string]$act.exit_knowledge_state){$errors.Add("ACT_EXIT_STATE_SW_MISMATCH: $id")}}
        foreach($nq in @($act.open_nq_ids)){if(-not $idSets.NQ.Contains([string]$nq)){$errors.Add("ACT_OPEN_NQ_MISSING: $id/$nq")}}
        foreach($action in @($act.nq_actions)){$match=[regex]::Match([string]$action,'^(?:OPEN|PAY):(NQ-\d{3})$|^REFRAME:(NQ-\d{3})(?:->(NQ-\d{3}))?$');if(-not $match.Success){$errors.Add("ACT_NQ_ACTION_INVALID: $id/$action")}else{foreach($group in @($match.Groups[1],$match.Groups[2],$match.Groups[3])){if($group.Success -and -not $idSets.NQ.Contains($group.Value)){$errors.Add("ACT_NQ_ACTION_REF_MISSING: $id/$($group.Value)")}}}}
        foreach($action in @($act.nr_actions)){$match=[regex]::Match([string]$action,'^(?:SETUP|REVEAL|CONSEQUENCE):(NR-\d{3})$');if(-not $match.Success -or -not $idSets.NR.Contains($match.Groups[1].Value)){$errors.Add("ACT_NR_ACTION_INVALID: $id/$action")}}
        foreach($vc in @($act.vc_ids)){if(-not $idSets.VC.Contains([string]$vc)){$errors.Add("ACT_VC_MISSING: $id/$vc")}}
        if (@($act.completion_criteria).Count -eq 0 -or @($act.completion_criteria | Where-Object { Test-SystemV7ConcreteText $_ }).Count -ne @($act.completion_criteria).Count) { $errors.Add("ACT_COMPLETION_CRITERIA_INVALID: $id") }

        $constraints = @($act.constraints)
        if ($constraints.Count -lt 1) { $errors.Add("CONSTRAINT_LEDGER_EMPTY: $id") }
        if ($constraints.Count -gt $script:SystemV7NarrativeMaxConstraints) { $errors.Add("OVERLOADED_ACT_PACKET: $id/$($constraints.Count)") }
        $cidSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $continuityCount = 0
        $expectedObjects=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($token in @("ACT_FUNCTION:$id","VIEWER_STATE:$id","BRIDGE:$id","CONTINUITY_OUT:$id")){$null=$expectedObjects.Add($token)}
        foreach($swId in @($act.scene_weave_ids)){$null=$expectedObjects.Add("SW:$swId");$sw=@($data.scene_weave|Where-Object{[string]$_.sw_id -ceq [string]$swId}|Select-Object -First 1);if($sw.Count -eq 1){foreach($required in @($sw[0].required_evidence)){$null=$expectedObjects.Add("REQUIRED:$swId/$([string]$required.p_id)")}}}
        foreach($action in @($act.nq_actions)){$null=$expectedObjects.Add("NQ:$action")};foreach($action in @($act.nr_actions)){$null=$expectedObjects.Add("NR:$action")};foreach($vc in @($act.vc_ids)){$null=$expectedObjects.Add("VC:$vc")}
        for($criterionIndex=0;$criterionIndex -lt @($act.completion_criteria).Count;$criterionIndex++){$null=$expectedObjects.Add(('COMPLETION:{0:D3}' -f ($criterionIndex+1)))}
        for($embargoIndex=0;$embargoIndex -lt @($act.do_not_reveal).Count;$embargoIndex++){$null=$expectedObjects.Add(('DO_NOT_REVEAL:{0:D3}' -f ($embargoIndex+1)))}
        if([string]$act.humor_mode -ceq 'FORBIDDEN'){$null=$expectedObjects.Add("HUMOR_MODE:$id")};if([string]$act.narrator_mode -cne 'DEFAULT'){$null=$expectedObjects.Add("NARRATOR_MODE:$id")}
        $coveredObjects=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        for($constraintIndex=0;$constraintIndex -lt $constraints.Count;$constraintIndex++) {
            $constraint=$constraints[$constraintIndex]
            $null=&$testExact $constraint @('cid','source_field','action','object_ids','why_hard','atomicity_reason','verification') 'CID'
            $cid = [string]$constraint.cid
            $expectedCid='CID-{0:D3}' -f ($constraintIndex+1);if ($cid -cne $expectedCid -or -not $cidSet.Add($cid)) { $errors.Add("CID_INVALID_OR_DUPLICATE: $id/$cid expected=$expectedCid") }
            if (-not (Test-SystemV7ExactMember -Value ([string]$constraint.source_field) -Allowed @('ACT_FUNCTION','VIEWER_STATE','SW','REQUIRED','NQ','NR','VC','COMPLETION','BRIDGE','DO_NOT_REVEAL','HUMOR_MODE','NARRATOR_MODE','CONTINUITY_OUT'))) { $errors.Add("CID_SOURCE_FIELD_INVALID: $id/$cid") }
            foreach ($f in @('action','why_hard','atomicity_reason','verification')) { if (-not (Test-SystemV7ConcreteText $constraint.$f)) { $errors.Add("CID_FIELD_MISSING: $id/$cid/$f") } }
            if (@($constraint.object_ids).Count -eq 0) { $errors.Add("CID_OBJECT_IDS_EMPTY: $id/$cid") }
            $hasPrimary=$false;foreach($objectId in @($constraint.object_ids)){$token=[string]$objectId;if($token.StartsWith(([string]$constraint.source_field+':'),[StringComparison]::Ordinal)){$hasPrimary=$true};if(-not $expectedObjects.Contains($token)){$errors.Add("CID_OBJECT_UNEXPECTED: $id/$cid/$token")}elseif(-not $coveredObjects.Add($token)){$errors.Add("CID_OBJECT_DUPLICATE_COVERAGE: $id/$token")}}
            if(-not $hasPrimary){$errors.Add("CID_SOURCE_FIELD_WITHOUT_OWN_OBJECT: $id/$cid")}
            if ([string]$constraint.source_field -ceq 'CONTINUITY_OUT') { $continuityCount++ }
        }
        foreach($token in @($expectedObjects)){if(-not $coveredObjects.Contains($token)){$errors.Add("CID_REQUIRED_OBJECT_MISSING: $id/$token")}}
        if ($continuityCount -ne 1) { $errors.Add("CONTINUITY_OUT_CID_COUNT_INVALID: $id/$continuityCount") }
        $atomicScenes=[Collections.Generic.List[object]]::new()
        foreach($swId in @($act.scene_weave_ids)){
            $sw=@($data.scene_weave|Where-Object{[string]$_.sw_id -ceq [string]$swId}|Select-Object -First 1)
            if($sw.Count -eq 1){$atomicScenes.Add([pscustomobject]@{sw_id=[string]$swId;required_p=@($sw[0].required_evidence|ForEach-Object{[string]$_.p_id});function=[string]$sw[0].function;bridge_out=[string]$sw[0].bridge_out;completion_criteria=[string]$sw[0].completion_criteria})}
        }
        $atomicPacket=[pscustomobject]@{act_id=$id;act_function=[string]$act.act_function;scene_weave_ids=@($act.scene_weave_ids);scene_contracts=@($atomicScenes);nq_actions=@($act.nq_actions);nr_actions=@($act.nr_actions);vc_ids=@($act.vc_ids);humor_mode=[string]$act.humor_mode;narrator_mode=[string]$act.narrator_mode;completion_criteria=@($act.completion_criteria);bridge_out=[string]$act.bridge_out;do_not_reveal=@($act.do_not_reveal)}
        $atomicLedger=[pscustomobject]@{schema='CONSTRAINT_LEDGER_V1';act_id=$id;max_total=$script:SystemV7NarrativeMaxConstraints;actual_total=$constraints.Count;constraints=$constraints}
        $atomicity=Get-SystemV7ConstraintAtomicityState -Packet $atomicPacket -Ledger $atomicLedger
        foreach($problem in @($atomicity.Errors)){$errors.Add("CONSTRAINT_ATOMICITY_INVALID: $id/$problem")}
    }
    $swUseCounts=@{};foreach($act in @($data.acts)){foreach($swId in @($act.scene_weave_ids)){$key=[string]$swId;$swUseCounts[$key]=if($swUseCounts.ContainsKey($key)){$swUseCounts[$key]+1}else{1}}}
    $swById=@{};foreach($sw in @($data.scene_weave)){$swById[[string]$sw.sw_id]=$sw}
    foreach ($sw in @($data.scene_weave)) { if (-not $idSets.ACT.Contains([string]$sw.act_id)) { $errors.Add("SW_ACT_MISSING: $($sw.sw_id)/$($sw.act_id)") };$count=if($swUseCounts.ContainsKey([string]$sw.sw_id)){$swUseCounts[[string]$sw.sw_id]}else{0};if($count -ne 1){$errors.Add("SW_ACT_MEMBERSHIP_COUNT_INVALID: $($sw.sw_id)/$count")} }
    $orderedSw=[Collections.Generic.List[object]]::new();$swIndex=@{};$ordinal=0
    foreach($act in @($data.acts)){foreach($swId in @($act.scene_weave_ids)){if($swById.ContainsKey([string]$swId)){$sw=$swById[[string]$swId];$orderedSw.Add($sw);$swIndex[[string]$swId]=$ordinal;$ordinal++}}}
    for($actOrdinal=0;$actOrdinal -lt @($data.acts).Count;$actOrdinal++){
        $act=$data.acts[$actOrdinal];$actId=[string]$act.act_id;$actSw=@($act.scene_weave_ids|ForEach-Object{if($swById.ContainsKey([string]$_)){$swById[[string]$_]}}|Where-Object{$_})
        for($swOrdinal=1;$swOrdinal -lt $actSw.Count;$swOrdinal++){if([string]$actSw[$swOrdinal-1].exit_knowledge_state -cne [string]$actSw[$swOrdinal].entry_knowledge_state){$errors.Add("SW_KNOWLEDGE_STATE_CHAIN_BROKEN: $actId/$([string]$actSw[$swOrdinal-1].sw_id)->$([string]$actSw[$swOrdinal].sw_id)")}}
        if($actOrdinal -gt 0){$previous=$data.acts[$actOrdinal-1];if([string]$previous.exit_knowledge_state -cne [string]$act.entry_knowledge_state){$errors.Add("ACT_KNOWLEDGE_STATE_CHAIN_BROKEN: $([string]$previous.act_id)->$actId")};if([string]$previous.intended_emotional_pressure_out -cne [string]$act.intended_emotional_pressure_in){$errors.Add("ACT_EMOTIONAL_PRESSURE_CHAIN_BROKEN: $([string]$previous.act_id)->$actId")}}
        $expectedVc=@($data.viewer_contacts|Where-Object{$act.scene_weave_ids -ccontains [string]$_.node}|ForEach-Object{[string]$_.vc_id});$declaredVc=@([string[]]@($act.vc_ids));if(($declaredVc -join '|') -cne ($expectedVc -join '|')){$errors.Add("ACT_VC_EXACT_OWNERSHIP_MISMATCH: $actId")}
    }
    $vcUseCounts=@{};foreach($act in @($data.acts)){foreach($vcId in @($act.vc_ids)){$key=[string]$vcId;$vcUseCounts[$key]=if($vcUseCounts.ContainsKey($key)){$vcUseCounts[$key]+1}else{1}}};foreach($vc in @($data.viewer_contacts)){$count=if($vcUseCounts.ContainsKey([string]$vc.vc_id)){$vcUseCounts[[string]$vc.vc_id]}else{0};if($count -ne 1){$errors.Add("VC_ACT_MEMBERSHIP_COUNT_INVALID: $([string]$vc.vc_id)/$count")}}
    foreach($reveal in @($data.reveals)){
        $target=[string]$reveal.target_node;if(-not $swById.ContainsKey($target)){continue};$required=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($item in @($swById[$target].required_evidence)){$null=$required.Add([string]$item.p_id)};foreach($p in @($reveal.evidence_p_ids)){if(-not $required.Contains([string]$p)){$errors.Add("NR_TARGET_REQUIRED_EVIDENCE_MISSING: $([string]$reveal.nr_id)/$target/$p")}}
    }
    $questionById=@{};foreach($q in @($data.questions)){$questionById[[string]$q.nq_id]=$q;if(-not $swIndex.ContainsKey([string]$q.opened_at) -or -not $swIndex.ContainsKey([string]$q.payoff_node)){$errors.Add("NQ_NODE_MISSING: $($q.nq_id)")}elseif([int]$swIndex[[string]$q.opened_at] -gt [int]$swIndex[[string]$q.payoff_node]){$errors.Add("NQ_NODE_ORDER_INVALID: $($q.nq_id)")}}
    $revealById=@{};foreach($r in @($data.reveals)){$revealById[[string]$r.nr_id]=$r;foreach($nodeField in @('earliest_legal_node','target_node','do_not_reveal_before')){if(-not $swIndex.ContainsKey([string]$r.$nodeField)){$errors.Add("NR_NODE_MISSING: $($r.nr_id)/$nodeField")}};if($swIndex.ContainsKey([string]$r.earliest_legal_node) -and $swIndex.ContainsKey([string]$r.target_node) -and [int]$swIndex[[string]$r.earliest_legal_node] -gt [int]$swIndex[[string]$r.target_node]){$errors.Add("NR_NODE_ORDER_INVALID: $($r.nr_id)")}}
    $openNq=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$openedNq=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$paidNq=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$reframedNq=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $preparedNr=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$revealedNr=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$consequenceNr=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($act in @($data.acts)){
        $actId=[string]$act.act_id;$declaredOpen=@([string[]]@($act.open_nq_ids)|Sort-Object);$actualOpen=@([string[]]@($openNq)|Sort-Object);if(($declaredOpen -join '|') -cne ($actualOpen -join '|')){$errors.Add("ACT_OPEN_NQ_ENTRY_STATE_MISMATCH: $actId")}
        $swNq=@();$swNr=@();foreach($swId in @($act.scene_weave_ids)){$sw=$swById[[string]$swId];if([string]$sw.nq_action -and [string]$sw.nq_action -cne 'BRAK'){$swNq+=[string]$sw.nq_action};if([string]$sw.nr_action -and [string]$sw.nr_action -cne 'BRAK'){$swNr+=[string]$sw.nr_action}}
        if((@([string[]]@($act.nq_actions)) -join '|') -cne ($swNq -join '|')){$errors.Add("ACT_SW_NQ_ACTIONS_MISMATCH: $actId")};if((@([string[]]@($act.nr_actions)) -join '|') -cne ($swNr -join '|')){$errors.Add("ACT_SW_NR_ACTIONS_MISMATCH: $actId")}
        foreach($swId in @($act.scene_weave_ids)){
            $sw=$swById[[string]$swId];$node=[string]$sw.sw_id;$nqAction=[string]$sw.nq_action
            if($nqAction -and $nqAction -cne 'BRAK'){
                $m=[regex]::Match($nqAction,'^(OPEN|PAY):(NQ-\d{3})$|^REFRAME:(NQ-\d{3})(?:->(NQ-\d{3}))?$')
                if(-not $m.Success){$errors.Add("SW_NQ_ACTION_INVALID: $node/$nqAction")}elseif($m.Groups[1].Success){$kind=$m.Groups[1].Value;$id=$m.Groups[2].Value;if(-not $questionById.ContainsKey($id)){$errors.Add("SW_NQ_ACTION_REF_MISSING: $node/$id")}else{$q=$questionById[$id];switch($kind){'OPEN'{if($node -cne [string]$q.opened_at -or $openNq.Contains($id) -or -not $openedNq.Add($id)){$errors.Add("NQ_OPEN_LIFECYCLE_INVALID: $node/$id")}else{$null=$openNq.Add($id)}}'PAY'{if($node -cne [string]$q.payoff_node -or -not $openNq.Remove($id) -or -not $paidNq.Add($id)){$errors.Add("NQ_PAY_LIFECYCLE_INVALID: $node/$id")}}}}}
                else{$old=$m.Groups[3].Value;$new=$m.Groups[4].Value;if(-not $questionById.ContainsKey($old) -or $node -cne [string]$questionById[$old].payoff_node -or -not $openNq.Remove($old) -or -not $reframedNq.Add($old)){$errors.Add("NQ_REFRAME_LIFECYCLE_INVALID: $node/$old")};if($new){if(-not $questionById.ContainsKey($new) -or $node -cne [string]$questionById[$new].opened_at -or $openNq.Contains($new) -or -not $openedNq.Add($new)){$errors.Add("NQ_REFRAME_TARGET_INVALID: $node/$new")}else{$null=$openNq.Add($new)}}else{$null=$openNq.Add($old)}}
            }
            $nrAction=[string]$sw.nr_action
            if($nrAction -and $nrAction -cne 'BRAK'){$m=[regex]::Match($nrAction,'^(SETUP|REVEAL|CONSEQUENCE):(NR-\d{3})$');if(-not $m.Success){$errors.Add("SW_NR_ACTION_INVALID: $node/$nrAction")}else{$kind=$m.Groups[1].Value;$id=$m.Groups[2].Value;if(-not $revealById.ContainsKey($id)){$errors.Add("SW_NR_ACTION_REF_MISSING: $node/$id")}else{$nr=$revealById[$id];switch($kind){'SETUP'{if([string]$nr.setup_required -ceq 'BRAK' -or $revealedNr.Contains($id) -or -not $preparedNr.Add($id) -or [int]$swIndex[$node] -ge [int]$swIndex[[string]$nr.target_node]){$errors.Add("NR_SETUP_LIFECYCLE_INVALID: $node/$id")}}'REVEAL'{if($node -cne [string]$nr.target_node -or [int]$swIndex[$node] -lt [int]$swIndex[[string]$nr.earliest_legal_node] -or [int]$swIndex[$node] -lt [int]$swIndex[[string]$nr.do_not_reveal_before] -or $revealedNr.Contains($id) -or ([string]$nr.setup_required -cne 'BRAK' -and -not $preparedNr.Contains($id))){$errors.Add("NR_REVEAL_LIFECYCLE_INVALID: $node/$id")}else{$null=$revealedNr.Add($id);$null=$preparedNr.Remove($id)}}'CONSEQUENCE'{if(-not $revealedNr.Contains($id) -or [int]$swIndex[$node] -le [int]$swIndex[[string]$nr.target_node] -or -not $consequenceNr.Add($id)){$errors.Add("NR_CONSEQUENCE_LIFECYCLE_INVALID: $node/$id")}}}}}}
        }
    }
    foreach($q in @($data.questions)){$id=[string]$q.nq_id;if(-not $openedNq.Contains($id)){$errors.Add("NQ_NEVER_OPENED: $id")};if([string]$q.expected_form -ceq 'ANSWER' -and -not $paidNq.Contains($id)){$errors.Add("NQ_EXPECTED_ANSWER_NOT_PAID: $id")};if([string]$q.expected_form -ceq 'REFRAME' -and -not $reframedNq.Contains($id)){$errors.Add("NQ_EXPECTED_REFRAME_MISSING: $id")};if([string]$q.status -ceq 'CLOSED' -and $openNq.Contains($id)){$errors.Add("NQ_DECLARED_CLOSED_BUT_OPEN: $id")};if([string]$q.status -ceq 'OPEN' -and -not $openNq.Contains($id)){$errors.Add("NQ_DECLARED_OPEN_BUT_CLOSED: $id")}}
    foreach($r in @($data.reveals)){if(-not $revealedNr.Contains([string]$r.nr_id)){$errors.Add("NR_TARGET_REVEAL_MISSING: $($r.nr_id)")};if(-not $consequenceNr.Contains([string]$r.nr_id)){$errors.Add("NR_CONSEQUENCE_ACTION_MISSING: $($r.nr_id)")}}
    foreach($vc in @($data.viewer_contacts)){if(-not $idSets.SW.Contains([string]$vc.node)){$errors.Add("VC_NODE_MISSING: $($vc.vc_id)/$($vc.node)")}}

    [pscustomobject]@{
        Verdict = if ($errors.Count -eq 0) { 'ARCHITECTURE_PASS' } else { 'ARCHITECTURE_FAIL' }
        GateReady = $errors.Count -eq 0
        Errors = $errors.Count
        Warnings = $warnings.Count
        ErrorDetails = @($errors)
        WarningDetails = @($warnings)
        Architecture = $architecture
        Evidence = $evidence
        Acts = $acts.Count
        ActIds = @($acts | ForEach-Object { [string]$_.act_id })
    }
}

function Get-SystemV7OrderedContinuityReplayState {
    <#
    Deterministyczny reduktor stanu NQ/NR. Źródłem kolejności jest wyłącznie
    scene_weave_ids aktu. CONTINUITY_OUT jest deklaracją pokrycia i stanu
    końcowego, nigdy źródłem kolejności zdarzeń.
    #>
    param(
        [Parameter(Mandatory)][object]$ArchitectureData,
        [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ThroughActId,
        [hashtable]$OutputsByAct,
        [hashtable]$ContinuityInputsByAct,
        [switch]$RequireOutputs,
        [switch]$RequireContinuityInputs
    )
    $errors=[Collections.Generic.List[string]]::new()
    $results=[Collections.Generic.List[object]]::new()
    $setEqual={
        param([object[]]$Left,[object[]]$Right,[string]$Code)
        $leftRaw=@([string[]]@($Left));$rightRaw=@([string[]]@($Right))
        $leftValues=@($leftRaw|Sort-Object -Unique)
        $rightValues=@($rightRaw|Sort-Object -Unique)
        if($leftValues.Count -ne $leftRaw.Count -or $rightValues.Count -ne $rightRaw.Count){$errors.Add("${Code}_DUPLICATE");return $false}
        if(($leftValues -join '|') -cne ($rightValues -join '|')){$errors.Add("${Code}_MISMATCH");return $false}
        return $true
    }
    $swById=@{};foreach($sw in @($ArchitectureData.scene_weave)){$swById[[string]$sw.sw_id]=$sw}
    $questionById=@{};foreach($q in @($ArchitectureData.questions)){$questionById[[string]$q.nq_id]=$q}
    $revealById=@{};foreach($r in @($ArchitectureData.reveals)){$revealById[[string]$r.nr_id]=$r}
    $acts=@($ArchitectureData.acts);$targetIndex=-1
    for($i=0;$i -lt $acts.Count;$i++){if([string]$acts[$i].act_id -ceq $ThroughActId){$targetIndex=$i;break}}
    if($targetIndex -lt 0){return [pscustomobject]@{Valid=$false;Errors=@("CONTINUITY_REPLAY_ACT_MISSING: $ThroughActId");ActResults=@();OpenNqIds=@();PreparedNrIds=@();RevealedNrIds=@()}}

    $openNq=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $openedNq=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $closedNq=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $preparedNr=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $revealedNr=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $consequenceNr=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    for($actIndex=0;$actIndex -le $targetIndex;$actIndex++){
        $act=$acts[$actIndex];$actId=[string]$act.act_id
        $inputOpen=@($openNq|Sort-Object);$inputPrepared=@($preparedNr|Sort-Object)
        $hasInput=$null -ne $ContinuityInputsByAct -and $ContinuityInputsByAct.ContainsKey($actId)
        if($RequireContinuityInputs -and -not $hasInput){$errors.Add("CONTINUITY_REPLAY_INPUT_MISSING: $actId")}
        if($hasInput){
            $input=$ContinuityInputsByAct[$actId]
            $null=&$setEqual @($input.open_nq_ids) $inputOpen "CONTINUITY_REPLAY_INPUT_OPEN_NQ_$actId"
            $null=&$setEqual @($input.prepared_nr_ids) $inputPrepared "CONTINUITY_REPLAY_INPUT_PREPARED_NR_$actId"
        }

        $expectedNqOpened=[Collections.Generic.List[string]]::new()
        $expectedNqPaid=[Collections.Generic.List[string]]::new()
        $expectedNqReframed=[Collections.Generic.List[object]]::new()
        $expectedNrRevealed=[Collections.Generic.List[string]]::new()
        $expectedNrConsequences=[Collections.Generic.List[string]]::new()
        $setupThisAct=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $orderedNq=[Collections.Generic.List[string]]::new();$orderedNr=[Collections.Generic.List[string]]::new()

        foreach($swIdRaw in @($act.scene_weave_ids)){
            $swId=[string]$swIdRaw
            if(-not $swById.ContainsKey($swId)){$errors.Add("CONTINUITY_REPLAY_SW_MISSING: $actId/$swId");continue}
            $sw=$swById[$swId]
            $nqAction=[string]$sw.nq_action
            if($nqAction -and $nqAction -cne 'BRAK'){
                $orderedNq.Add($nqAction)
                $match=[regex]::Match($nqAction,'^(OPEN|PAY):(NQ-\d{3})$|^REFRAME:(NQ-\d{3})(?:->(NQ-\d{3}))?$')
                if(-not $match.Success){$errors.Add("CONTINUITY_REPLAY_NQ_ACTION_INVALID: $actId/$swId/$nqAction")}
                elseif($match.Groups[1].Success){
                    $kind=$match.Groups[1].Value;$id=$match.Groups[2].Value
                    if(-not $questionById.ContainsKey($id)){$errors.Add("CONTINUITY_REPLAY_NQ_UNKNOWN: $actId/$swId/$id");continue}
                    switch($kind){
                        'OPEN' { if($openedNq.Contains($id) -or $openNq.Contains($id)){$errors.Add("CONTINUITY_REPLAY_NQ_OPEN_INVALID: $actId/$swId/$id")}else{$null=$openedNq.Add($id);$null=$openNq.Add($id);$expectedNqOpened.Add($id)} }
                        'PAY' { if(-not $openNq.Remove($id) -or $closedNq.Contains($id)){$errors.Add("CONTINUITY_REPLAY_NQ_PAY_WITHOUT_OPEN: $actId/$swId/$id")}else{$null=$closedNq.Add($id);$expectedNqPaid.Add($id)} }
                    }
                }else{
                    $from=$match.Groups[3].Value;$to=$match.Groups[4].Value
                    if(-not $questionById.ContainsKey($from) -or -not $openNq.Contains($from)){$errors.Add("CONTINUITY_REPLAY_NQ_REFRAME_FROM_INVALID: $actId/$swId/$from")}
                    elseif($to){
                        if(-not $questionById.ContainsKey($to) -or $openedNq.Contains($to) -or $openNq.Contains($to)){$errors.Add("CONTINUITY_REPLAY_NQ_REFRAME_TARGET_INVALID: $actId/$swId/$to")}
                        else{$null=$openNq.Remove($from);$null=$closedNq.Add($from);$null=$openedNq.Add($to);$null=$openNq.Add($to);$expectedNqReframed.Add([pscustomobject]@{from_id=$from;to_id=$to;close_from=$true})}
                    }else{$expectedNqReframed.Add([pscustomobject]@{from_id=$from;to_id='BRAK';close_from=$false})}
                }
            }

            $nrAction=[string]$sw.nr_action
            if($nrAction -and $nrAction -cne 'BRAK'){
                $orderedNr.Add($nrAction)
                $match=[regex]::Match($nrAction,'^(SETUP|REVEAL|CONSEQUENCE):(NR-\d{3})$')
                if(-not $match.Success){$errors.Add("CONTINUITY_REPLAY_NR_ACTION_INVALID: $actId/$swId/$nrAction");continue}
                $kind=$match.Groups[1].Value;$id=$match.Groups[2].Value
                if(-not $revealById.ContainsKey($id)){$errors.Add("CONTINUITY_REPLAY_NR_UNKNOWN: $actId/$swId/$id");continue}
                if($kind -cne 'CONSEQUENCE' -and $revealedNr.Contains($id)){$errors.Add("CONTINUITY_REPLAY_NR_AFTER_REVEAL: $actId/$swId/$id");continue}
                switch($kind){
                    'SETUP' { if([string]$revealById[$id].setup_required -ceq 'BRAK' -or $preparedNr.Contains($id) -or -not $preparedNr.Add($id)){$errors.Add("CONTINUITY_REPLAY_NR_SETUP_DUPLICATE_OR_UNNEEDED: $actId/$swId/$id")}else{$null=$setupThisAct.Add($id)} }
                    'REVEAL' { $needsSetup=[string]$revealById[$id].setup_required -cne 'BRAK';if($needsSetup -and -not $preparedNr.Contains($id)){$errors.Add("CONTINUITY_REPLAY_NR_REVEAL_WITHOUT_SETUP: $actId/$swId/$id")}else{$null=$preparedNr.Remove($id);$null=$revealedNr.Add($id);$expectedNrRevealed.Add($id)} }
                    'CONSEQUENCE' { if(-not $revealedNr.Contains($id) -or -not $consequenceNr.Add($id)){$errors.Add("CONTINUITY_REPLAY_NR_CONSEQUENCE_INVALID: $actId/$swId/$id")}else{$expectedNrConsequences.Add($id)} }
                }
            }
        }

        $declaredNqActions=@([string[]]@($act.nq_actions));if(($declaredNqActions -join '|') -cne (@($orderedNq) -join '|')){$errors.Add("CONTINUITY_REPLAY_ACT_NQ_SEQUENCE_MISMATCH: $actId")}
        $declaredNrActions=@([string[]]@($act.nr_actions));if(($declaredNrActions -join '|') -cne (@($orderedNr) -join '|')){$errors.Add("CONTINUITY_REPLAY_ACT_NR_SEQUENCE_MISMATCH: $actId")}
        $expectedSetupOnly=@($setupThisAct|Where-Object{$preparedNr.Contains([string]$_)}|Sort-Object)
        $outputResult=[pscustomobject]@{
            ActId=$actId;InputOpenNqIds=$inputOpen;InputPreparedNrIds=$inputPrepared
            ExpectedNqOpened=@($expectedNqOpened);ExpectedNqPaid=@($expectedNqPaid);ExpectedNqReframed=@($expectedNqReframed)
            ExpectedOpenNqIdsOut=@($openNq|Sort-Object);ExpectedNrRevealed=@($expectedNrRevealed);ExpectedNrConsequences=@($expectedNrConsequences);ExpectedNrSetupOnly=$expectedSetupOnly
            OpenNqIdsOut=@($openNq|Sort-Object);PreparedNrIdsOut=@($preparedNr|Sort-Object);RevealedNrIds=@($revealedNr|Sort-Object);ConsequenceNrIds=@($consequenceNr|Sort-Object)
        }
        $results.Add($outputResult)

        $hasOutput=$null -ne $OutputsByAct -and $OutputsByAct.ContainsKey($actId)
        if($RequireOutputs -and -not $hasOutput){$errors.Add("CONTINUITY_REPLAY_OUTPUT_MISSING: $actId")}
        if($hasOutput){
            $out=$OutputsByAct[$actId]
            if([string]$out.schema -cne 'CONTINUITY_OUT_V1' -or [string]$out.act_id -cne $actId){$errors.Add("CONTINUITY_REPLAY_OUTPUT_IDENTITY_INVALID: $actId")}
            $null=&$setEqual @($out.nq_opened) @($expectedNqOpened) "CONTINUITY_REPLAY_NQ_OPENED_$actId"
            $null=&$setEqual @($out.nq_paid) @($expectedNqPaid) "CONTINUITY_REPLAY_NQ_PAID_$actId"
            $null=&$setEqual @($out.open_nq_ids_out) @($openNq) "CONTINUITY_REPLAY_OPEN_NQ_OUT_$actId"
            $null=&$setEqual @($out.nr_revealed) @($expectedNrRevealed) "CONTINUITY_REPLAY_NR_REVEALED_$actId"
            $null=&$setEqual @($out.nr_consequences) @($expectedNrConsequences) "CONTINUITY_REPLAY_NR_CONSEQUENCES_$actId"
            $null=&$setEqual @($out.nr_setup_only) $expectedSetupOnly "CONTINUITY_REPLAY_NR_SETUP_ONLY_$actId"
            $actualReframes=@($out.nq_reframed)
            if($actualReframes.Count -ne $expectedNqReframed.Count){$errors.Add("CONTINUITY_REPLAY_NQ_REFRAME_COUNT_MISMATCH: $actId")}
            else{
                for($ri=0;$ri -lt $expectedNqReframed.Count;$ri++){
                    $actual=$actualReframes[$ri];$expected=$expectedNqReframed[$ri];$fields=@('from_id','to_id','close_from')
                    if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($actual.PSObject.Properties.Name)).Count -gt 0 -or @($actual.PSObject.Properties.Name).Count -ne $fields.Count -or [string]$actual.from_id -cne [string]$expected.from_id -or [string]$actual.to_id -cne [string]$expected.to_id -or $actual.close_from -cne $expected.close_from){$errors.Add("CONTINUITY_REPLAY_NQ_REFRAME_MISMATCH: $actId/$ri")}
                }
            }
        }
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);ActResults=@($results);OpenNqIds=@($openNq|Sort-Object);PreparedNrIds=@($preparedNr|Sort-Object);RevealedNrIds=@($revealedNr|Sort-Object);ConsequenceNrIds=@($consequenceNr|Sort-Object)}
}

function Get-SystemV7ExpectedNextContinuityIn {
    param(
        [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
        [Parameter(Mandatory)][ValidatePattern('^(?:ACT-\d{3}|COMPLETE)$')][string]$NextActId,
        [Parameter(Mandatory)][object]$ContinuityIn,
        [Parameter(Mandatory)][object]$ContinuityOut,
        [Parameter(Mandatory)][object]$ActPacket,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ProseSha256,
        [object[]]$OpenNqIds,
        [object[]]$PreparedNrIds
    )
    $textStates=@($ContinuityIn.text_states)+@($ContinuityOut.records|Where-Object{[string]$_.class -ceq 'TEXT_ASSERTED'}|ForEach-Object{[ordered]@{source_act_id=$ActId;state_id=$_.state_id;category=$_.category;value=$_.value;block_refs=$_.block_refs;source_p_ids=$_.source_p_ids}})+@($ContinuityOut.uncertainties_preserved|ForEach-Object{[ordered]@{source_act_id=$ActId;state_id=$_.uncertainty_id;category='KNOWLEDGE_BOUNDARY';value=$_.value;block_refs=$_.block_refs;source_p_ids=$_.source_p_ids}})
    $inferences=@($ContinuityIn.viewer_inferences)+@($ContinuityOut.records|Where-Object{[string]$_.class -ceq 'VIEWER_INFERENCE'}|ForEach-Object{[ordered]@{source_act_id=$ActId;state_id=$_.state_id;category=$_.category;value=$_.value;block_refs=$_.block_refs;source_p_ids=$_.source_p_ids}})
    $embargoes=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($item in @($ContinuityIn.active_embargoes)+@($ActPacket.do_not_reveal)){if(Test-SystemV7ConcreteText -Value ([string]$item)){$null=$embargoes.Add([string]$item)}}
    foreach($revealed in @($ContinuityOut.nr_revealed)){foreach($embargo in @($embargoes|Where-Object{$_ -match "(?<![A-Z0-9-])$([regex]::Escape([string]$revealed))(?![A-Z0-9-])"})){$null=$embargoes.Remove([string]$embargo)}}
    $worldState=[Collections.Generic.List[object]]::new();$worldSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($item in @($ContinuityIn.world_state)){$key="$([string]$item.source_act_id)|$([string]$item.world_state_id)";if($worldSeen.Add($key)){$worldState.Add($item)}}
    foreach($item in @($ContinuityOut.character_and_world_state)){$projected=[ordered]@{source_act_id=$ActId;world_state_id=$item.world_state_id;value=$item.value;class=$item.class;block_refs=$item.block_refs;source_p_ids=$item.source_p_ids};$key="$ActId|$([string]$item.world_state_id)";if($worldSeen.Add($key)){$worldState.Add($projected)}}
    $value=[ordered]@{
        schema='CONTINUITY_IN_V1';act_id=$NextActId;source_act_id=$ActId;source_act_sha256=$ProseSha256.ToUpperInvariant();source_attest_sha256='BOUND_ON_CONSUMPTION'
        text_states=$textStates;viewer_inferences=$inferences;open_nq_ids=@([string[]]@($OpenNqIds)|Sort-Object);prepared_nr_ids=@([string[]]@($PreparedNrIds)|Sort-Object)
        active_embargoes=@($embargoes|Sort-Object);world_state=@($worldState);bridge=[string]$ContinuityOut.bridge_realized
        opening_move_history=@($ContinuityIn.opening_move_history)+@([string]$ContinuityOut.opening_move_type)
        closing_move_history=@($ContinuityIn.closing_move_history)+@([string]$ContinuityOut.closing_move_type)
        emotional_pressure=[string]$ActPacket.intended_emotional_pressure_out
    }
    [pscustomobject]@{Value=[pscustomobject]$value;CanonicalJson=(ConvertTo-SystemV7CanonicalJson -Value $value)}
}

function Get-SystemV7PacketSceneContractState {
    param([Parameter(Mandatory)][object]$Packet)
    $errors=[Collections.Generic.List[string]]::new()
    $setEqual={param($Left,$Right,[string]$Code)$a=@([string[]]@($Left)|Sort-Object -CaseSensitive);$b=@([string[]]@($Right)|Sort-Object -CaseSensitive);if(($a -join '|') -cne ($b -join '|')){$errors.Add($Code);return $false};return $true}
    $packetSw=@([string[]]@($Packet.scene_weave_ids));$allowedSw=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($id in $packetSw){if($id -notmatch '^SW-\d{3}$' -or -not $allowedSw.Add($id)){$errors.Add("PACKET_SCENE_SW_INVALID_OR_DUPLICATE: $id")}}

    $registry=$Packet.narrative_action_registry;$registryFields=@('schema','act_id','questions','reveals','viewer_contacts')
    if($null -eq $registry -or @(Compare-Object -ReferenceObject $registryFields -DifferenceObject @($registry.PSObject.Properties.Name)).Count -gt 0 -or @($registry.PSObject.Properties.Name).Count -ne $registryFields.Count){$errors.Add('PACKET_ACTION_REGISTRY_FIELDS_INVALID')}
    elseif([string]$registry.schema -cne 'NARRATIVE_ACTION_REGISTRY_V1' -or [string]$registry.act_id -cne [string]$Packet.act_id){$errors.Add('PACKET_ACTION_REGISTRY_IDENTITY_INVALID')}
    if($null -eq $registry){$registry=[pscustomobject]@{questions=@();reveals=@();viewer_contacts=@()}}
    $registryJson=ConvertTo-SystemV7CanonicalJson -Value $registry
    if([string]$Packet.narrative_action_registry_sha256 -notmatch '^[A-F0-9]{64}$' -or [string]$Packet.narrative_action_registry_sha256 -cne (Get-SystemV7NarrativeSha256Text -Text $registryJson)){$errors.Add('PACKET_ACTION_REGISTRY_SHA_INVALID')}

    $questionById=@{};foreach($q in @($registry.questions)){$fields=@('nq_id','question','opened_at','why_care','expected_form','payoff_node','status');$id=[string]$q.nq_id;if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($q.PSObject.Properties.Name)).Count -gt 0 -or @($q.PSObject.Properties.Name).Count -ne $fields.Count -or $id -notmatch '^NQ-\d{3}$' -or $questionById.ContainsKey($id)){$errors.Add("PACKET_ACTION_REGISTRY_NQ_INVALID_OR_DUPLICATE: $id")}else{$questionById[$id]=$q}}
    $revealById=@{};foreach($r in @($registry.reveals)){$fields=@('nr_id','reveal','evidence_p_ids','earliest_legal_node','target_node','setup_required','do_not_reveal_before','consequence','uncertainty_form');$id=[string]$r.nr_id;if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($r.PSObject.Properties.Name)).Count -gt 0 -or @($r.PSObject.Properties.Name).Count -ne $fields.Count -or $id -notmatch '^NR-\d{3}$' -or $revealById.ContainsKey($id)){$errors.Add("PACKET_ACTION_REGISTRY_NR_INVALID_OR_DUPLICATE: $id")}else{$revealById[$id]=$r}}
    $vcById=@{};foreach($vc in @($registry.viewer_contacts)){$fields=@('vc_id','node','function','level','purpose','risk','author_text','approval','approval_receipt_relative','approval_receipt_sha256');$id=[string]$vc.vc_id;if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($vc.PSObject.Properties.Name)).Count -gt 0 -or @($vc.PSObject.Properties.Name).Count -ne $fields.Count -or $id -notmatch '^VC-\d{3}$' -or $vcById.ContainsKey($id)){$errors.Add("PACKET_ACTION_REGISTRY_VC_INVALID_OR_DUPLICATE: $id")}else{$vcById[$id]=$vc}}
    $expectedNq=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($action in @($Packet.nq_actions)){foreach($m in [regex]::Matches([string]$action,'NQ-\d{3}')){$null=$expectedNq.Add([string]$m.Value)}};foreach($id in @($Packet.open_nq_ids)){$null=$expectedNq.Add([string]$id)}
    $expectedNr=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($action in @($Packet.nr_actions)){foreach($m in [regex]::Matches([string]$action,'NR-\d{3}')){$null=$expectedNr.Add([string]$m.Value)}}
    $null=&$setEqual @($questionById.Keys) @($expectedNq) 'PACKET_ACTION_REGISTRY_NQ_SET_MISMATCH';$null=&$setEqual @($revealById.Keys) @($expectedNr) 'PACKET_ACTION_REGISTRY_NR_SET_MISMATCH';$null=&$setEqual @($vcById.Keys) @($Packet.vc_ids) 'PACKET_ACTION_REGISTRY_VC_SET_MISMATCH'

    $contractBySw=@{};$contractOrder=[Collections.Generic.List[string]]::new();$aggregateRequired=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$allSupporting=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$aggregateNq=[Collections.Generic.List[string]]::new();$aggregateNr=[Collections.Generic.List[string]]::new();$aggregateVc=[Collections.Generic.List[string]]::new()
    $sceneContracts=@($Packet.scene_contracts|Where-Object{$null -ne $_});if($sceneContracts.Count -eq 0){$errors.Add('PACKET_SCENE_CONTRACTS_MISSING')}
    foreach($contract in $sceneContracts){
        $fields=@('sw_id','scene_or_unit','function','entry_knowledge_state','exit_knowledge_state','emotional_pressure','required_p','supporting_p','nq_action','nr_action','nr_evidence_p','vc_ids','local_stake','bridge_out','completion_criteria');$sw=[string]$contract.sw_id
        if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($contract.PSObject.Properties.Name)).Count -gt 0 -or @($contract.PSObject.Properties.Name).Count -ne $fields.Count){$errors.Add("PACKET_SCENE_CONTRACT_FIELDS_INVALID: $sw");continue}
        if(-not $allowedSw.Contains($sw) -or $contractBySw.ContainsKey($sw)){$errors.Add("PACKET_SCENE_CONTRACT_SW_INVALID_OR_DUPLICATE: $sw");continue}
        foreach($field in @('scene_or_unit','function','entry_knowledge_state','exit_knowledge_state','emotional_pressure','local_stake','bridge_out','completion_criteria')){if(-not(Test-SystemV7ConcreteText -Value ([string]$contract.$field))){$errors.Add("PACKET_SCENE_CONTRACT_FIELD_NOT_CONCRETE: $sw/$field")}}
        if([string]$contract.entry_knowledge_state -ceq [string]$contract.exit_knowledge_state){$errors.Add("PACKET_SCENE_CONTRACT_STATE_DOES_NOT_CHANGE: $sw")}
        $requiredSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($p in @($contract.required_p)){$value=[string]$p;if($value -notmatch '^#P-\d{3,}$' -or -not $requiredSeen.Add($value)){$errors.Add("PACKET_SCENE_CONTRACT_REQUIRED_INVALID: $sw/$value")}else{$null=$aggregateRequired.Add($value)}}
        if($requiredSeen.Count -eq 0){$errors.Add("PACKET_SCENE_CONTRACT_REQUIRED_EMPTY: $sw")}
        $supportingSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($p in @($contract.supporting_p)){$value=[string]$p;if($value -notmatch '^#P-\d{3,}$' -or $requiredSeen.Contains($value) -or -not $supportingSeen.Add($value)){$errors.Add("PACKET_SCENE_CONTRACT_SUPPORTING_INVALID: $sw/$value")}else{$null=$allSupporting.Add($value)}}
        $nq=[string]$contract.nq_action;$nr=[string]$contract.nr_action
        if($nq -ne 'BRAK' -and $nq -notmatch '^(?:(?:OPEN|PAY):NQ-\d{3}|REFRAME:NQ-\d{3}(?:->NQ-\d{3})?)$'){$errors.Add("PACKET_SCENE_CONTRACT_NQ_INVALID: $sw/$nq")}elseif($nq -ne 'BRAK'){$aggregateNq.Add($nq)}
        if($nr -ne 'BRAK' -and $nr -notmatch '^(?:SETUP|REVEAL|CONSEQUENCE):NR-\d{3}$'){$errors.Add("PACKET_SCENE_CONTRACT_NR_INVALID: $sw/$nr")}elseif($nr -ne 'BRAK'){$aggregateNr.Add($nr)}
        $evidenceSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($p in @($contract.nr_evidence_p)){$value=[string]$p;if($value -notmatch '^#P-\d{3,}$' -or -not $evidenceSeen.Add($value)){$errors.Add("PACKET_SCENE_CONTRACT_NR_EVIDENCE_INVALID: $sw/$value")}}
        if($nr -match '^REVEAL:(NR-\d{3})$'){$id=[string]$Matches[1];if(-not $revealById.ContainsKey($id)){$errors.Add("PACKET_SCENE_CONTRACT_REVEAL_REGISTRY_MISSING: $sw/$id")}else{$null=&$setEqual @($evidenceSeen) @($revealById[$id].evidence_p_ids) "PACKET_SCENE_CONTRACT_REVEAL_EVIDENCE_MISMATCH: $sw/$id";foreach($p in @($evidenceSeen)){if(-not $requiredSeen.Contains([string]$p)){$errors.Add("PACKET_SCENE_CONTRACT_REVEAL_EVIDENCE_NOT_REQUIRED: $sw/$id/$p")}}}}elseif($evidenceSeen.Count -ne 0){$errors.Add("PACKET_SCENE_CONTRACT_UNEXPECTED_NR_EVIDENCE: $sw")}
        $actualVc=@([string[]]@($contract.vc_ids));$expectedVc=@($registry.viewer_contacts|Where-Object{[string]$_.node -ceq $sw}|ForEach-Object{[string]$_.vc_id});if(($actualVc -join '|') -cne ($expectedVc -join '|')){$errors.Add("PACKET_SCENE_CONTRACT_VC_MAP_MISMATCH: $sw")};foreach($vc in $actualVc){$aggregateVc.Add($vc)}
        $contractBySw[$sw]=$contract;$contractOrder.Add($sw)
    }
    if(($contractOrder -join '|') -cne ($packetSw -join '|')){$errors.Add('PACKET_SCENE_CONTRACT_ORDER_INVALID')}
    for($i=1;$i -lt $packetSw.Count;$i++){if($contractBySw.ContainsKey($packetSw[$i-1]) -and $contractBySw.ContainsKey($packetSw[$i]) -and [string]$contractBySw[$packetSw[$i-1]].exit_knowledge_state -cne [string]$contractBySw[$packetSw[$i]].entry_knowledge_state){$errors.Add("PACKET_SCENE_CONTRACT_STATE_CHAIN_BROKEN: $($packetSw[$i-1])->$($packetSw[$i])")}}
    $aggregateSupporting=@($allSupporting|Where-Object{-not $aggregateRequired.Contains([string]$_)})
    $null=&$setEqual @($aggregateRequired) @($Packet.required_p) 'PACKET_SCENE_CONTRACT_REQUIRED_AGGREGATE_MISMATCH';$null=&$setEqual $aggregateSupporting @($Packet.supporting_p) 'PACKET_SCENE_CONTRACT_SUPPORTING_AGGREGATE_MISMATCH'
    if(($aggregateNq -join '|') -cne (@([string[]]@($Packet.nq_actions)) -join '|')){$errors.Add('PACKET_SCENE_CONTRACT_NQ_AGGREGATE_MISMATCH')};if(($aggregateNr -join '|') -cne (@([string[]]@($Packet.nr_actions)) -join '|')){$errors.Add('PACKET_SCENE_CONTRACT_NR_AGGREGATE_MISMATCH')};if(($aggregateVc -join '|') -cne (@([string[]]@($Packet.vc_ids)) -join '|')){$errors.Add('PACKET_SCENE_CONTRACT_VC_AGGREGATE_MISMATCH')}
    if($packetSw.Count -gt 0 -and $contractBySw.ContainsKey($packetSw[0]) -and ([string]$contractBySw[$packetSw[0]].entry_knowledge_state -cne [string]$Packet.entry_knowledge_state -or [string]$contractBySw[$packetSw[-1]].exit_knowledge_state -cne [string]$Packet.exit_knowledge_state)){$errors.Add('PACKET_SCENE_CONTRACT_ACT_BOUNDARY_MISMATCH')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);SceneIds=$packetSw;ContractBySw=$contractBySw;Registry=$registry;QuestionById=$questionById;RevealById=$revealById;ViewerContactById=$vcById}
}

function Get-SystemV7BeatSheetSemanticState {
    param(
        [Parameter(Mandatory)][object]$Packet,
        [Parameter(Mandatory)][object]$BeatSheet,
        [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
        [string]$ExpectedGenerateRunId
    )
    $errors=[Collections.Generic.List[string]]::new()
    $normalized=[Collections.Generic.List[object]]::new()
    $sheetFields=if($ExpectedGenerateRunId){@('schema','act_id','packet_status','generate_run_id','beats')}else{@('schema','act_id','packet_status','beats')}
    if(@(Compare-Object -ReferenceObject $sheetFields -DifferenceObject @($BeatSheet.PSObject.Properties.Name)).Count -gt 0 -or @($BeatSheet.PSObject.Properties.Name).Count -ne $sheetFields.Count){$errors.Add('BEAT_SHEET_FIELDS_INVALID')}
    if([string]$BeatSheet.schema -cne 'K3_BEAT_SHEET_V1' -or [string]$BeatSheet.act_id -cne $ActId -or [string]$BeatSheet.packet_status -cne 'BEAT_SHEET_READY' -or @($BeatSheet.beats).Count -eq 0){$errors.Add('BEAT_SHEET_IDENTITY_INVALID')}
    if($ExpectedGenerateRunId -and [string]$BeatSheet.generate_run_id -cne $ExpectedGenerateRunId){$errors.Add('BEAT_SHEET_GENERATE_RUN_ID_MISMATCH')}
    if([string]$Packet.act_id -cne $ActId -or [string]$Packet.complexity_flag -cne 'COMPLEX'){$errors.Add('BEAT_PACKET_IDENTITY_INVALID')}

    $contractState=Get-SystemV7PacketSceneContractState -Packet $Packet
    foreach($problem in @($contractState.Errors)){$errors.Add("BEAT_$problem")}
    $packetSw=@($contractState.SceneIds);$contractBySw=$contractState.ContractBySw
    $allowedSw=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($id in $packetSw){$null=$allowedSw.Add([string]$id)}

    $seenBeat=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seenSw=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $firstUse=[Collections.Generic.List[string]]::new()
    $swOrdinal=@{};for($ordinal=0;$ordinal -lt $packetSw.Count;$ordinal++){$swOrdinal[$packetSw[$ordinal]]=$ordinal};$lastSwOrdinal=-1;$firstBeatBySw=@{};$lastBeatBySw=@{}
    $sourceCoverage=@{};$narrativeCoverage=@{};foreach($sw in $packetSw){$sourceCoverage[$sw]=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$narrativeCoverage[$sw]=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)}
    $previousAfter=$null;$index=0
    foreach($beat in @($BeatSheet.beats)){
        $index++;$expectedId='BEAT-{0:D3}' -f $index
        $fields=@('beat_id','sw_id','function','source_p_ids','state_before','state_after','nq_nr_vc_ids')
        if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($beat.PSObject.Properties.Name)).Count -gt 0 -or @($beat.PSObject.Properties.Name).Count -ne $fields.Count){$errors.Add("BEAT_FIELDS_INVALID: $expectedId");continue}
        if([string]$beat.beat_id -cne $expectedId -or -not $seenBeat.Add([string]$beat.beat_id)){$errors.Add("BEAT_ID_SEQUENCE_INVALID: $([string]$beat.beat_id)")}
        $sw=[string]$beat.sw_id
        if(-not $allowedSw.Contains($sw)){$errors.Add("BEAT_SW_ILLEGAL: $expectedId/$sw")}else{$currentOrdinal=[int]$swOrdinal[$sw];if($currentOrdinal -lt $lastSwOrdinal){$errors.Add("BEAT_SW_ORDER_REGRESSION: $expectedId/$sw")}elseif($currentOrdinal -gt $lastSwOrdinal){$lastSwOrdinal=$currentOrdinal};if($seenSw.Add($sw)){$firstUse.Add($sw);$firstBeatBySw[$sw]=$beat};$lastBeatBySw[$sw]=$beat}
        foreach($field in @('function','state_before','state_after')){if(-not(Test-SystemV7ConcreteText -Value ([string]$beat.$field))){$errors.Add("BEAT_FIELD_NOT_CONCRETE: $expectedId/$field")}}
        if([string]$beat.state_before -ceq [string]$beat.state_after){$errors.Add("BEAT_STATE_DOES_NOT_CHANGE: $expectedId")}
        if($index -gt 1 -and [string]$beat.state_before -cne [string]$previousAfter){$errors.Add("BEAT_STATE_CHAIN_BROKEN: $expectedId")}
        $previousAfter=[string]$beat.state_after

        $sourceIds=@([string[]]@($beat.source_p_ids));$sourceSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$contractAllowedP=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);if($contractBySw.ContainsKey($sw)){foreach($p in @($contractBySw[$sw].required_p)+@($contractBySw[$sw].supporting_p)){$null=$contractAllowedP.Add([string]$p)}}
        foreach($id in $sourceIds){if(-not $sourceSeen.Add($id)){$errors.Add("BEAT_SOURCE_DUPLICATE: $expectedId/$id")}elseif(-not $contractAllowedP.Contains($id)){$errors.Add("BEAT_SOURCE_WRONG_SW_OR_ILLEGAL: $expectedId/$sw/$id")}else{$null=$sourceCoverage[$sw].Add($id)}}
        $narrativeIds=@([string[]]@($beat.nq_nr_vc_ids));$narrativeSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$contractNarrative=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);if($contractBySw.ContainsKey($sw)){$contract=$contractBySw[$sw];foreach($token in @([string]$contract.nq_action,[string]$contract.nr_action)+@($contract.vc_ids)){if($token -and $token -cne 'BRAK'){$null=$contractNarrative.Add([string]$token)}}}
        foreach($id in $narrativeIds){if(-not $narrativeSeen.Add($id)){$errors.Add("BEAT_NARRATIVE_ID_DUPLICATE: $expectedId/$id")}elseif(-not $contractNarrative.Contains($id)){$errors.Add("BEAT_NQ_NR_VC_WRONG_SW_OR_ILLEGAL: $expectedId/$sw/$id")}else{$null=$narrativeCoverage[$sw].Add($id)}}
        if($contractBySw.ContainsKey($sw) -and [string]$contractBySw[$sw].nr_action -match '^REVEAL:NR-\d{3}$' -and $narrativeSeen.Contains([string]$contractBySw[$sw].nr_action)){foreach($p in @($contractBySw[$sw].nr_evidence_p)){if(-not $sourceSeen.Contains([string]$p)){$errors.Add("BEAT_REVEAL_EVIDENCE_NOT_COOCCURRENT: $expectedId/$sw/$p")}}}
        $normalized.Add([ordered]@{beat_id=$expectedId;sw_id=$sw;function=[string]$beat.function;source_p_ids=$sourceIds;state_before=[string]$beat.state_before;state_after=[string]$beat.state_after;nq_nr_vc_ids=$narrativeIds})
    }
    foreach($sw in $packetSw){if(-not $seenSw.Contains($sw)){$errors.Add("BEAT_SW_NOT_COVERED: $sw")}elseif($contractBySw.ContainsKey($sw)){if([string]$firstBeatBySw[$sw].state_before -cne [string]$contractBySw[$sw].entry_knowledge_state){$errors.Add("BEAT_SW_ENTRY_STATE_MISMATCH: $sw")};if([string]$lastBeatBySw[$sw].state_after -cne [string]$contractBySw[$sw].exit_knowledge_state){$errors.Add("BEAT_SW_EXIT_STATE_MISMATCH: $sw")}}}
    foreach($sw in $packetSw){if(-not $contractBySw.ContainsKey($sw)){continue};$contract=$contractBySw[$sw];foreach($p in @($contract.required_p)){if(-not $sourceCoverage[$sw].Contains([string]$p)){$errors.Add("BEAT_REQUIRED_SOURCE_NOT_COVERED: $sw/$p")}};foreach($token in @([string]$contract.nq_action,[string]$contract.nr_action)+@($contract.vc_ids)){if($token -and $token -cne 'BRAK' -and -not $narrativeCoverage[$sw].Contains([string]$token)){$errors.Add("BEAT_NARRATIVE_TOKEN_NOT_COVERED: $sw/$token")}}}
    if(($firstUse -join '|') -cne ($packetSw -join '|')){$errors.Add("BEAT_SW_FIRST_USE_ORDER_INVALID: expected=$($packetSw -join ',');actual=$($firstUse -join ',')")}
    if(@($BeatSheet.beats).Count -gt 0 -and ([string]$BeatSheet.beats[0].state_before -cne [string]$Packet.entry_knowledge_state -or [string]$BeatSheet.beats[-1].state_after -cne [string]$Packet.exit_knowledge_state)){$errors.Add('BEAT_ACT_BOUNDARY_STATE_MISMATCH')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);NormalizedBeats=@($normalized);FirstUseSwIds=@($firstUse)}
}

function Get-SystemV7ActSubmissionTraceState {
    param(
        [Parameter(Mandatory)][object]$Packet,
        [Parameter(Mandatory)][object[]]$Blocks,
        [object]$BeatSheet
    )
    $errors=[Collections.Generic.List[string]]::new();$isComplex=[string]$Packet.complexity_flag -ceq 'COMPLEX'
    $contractState=Get-SystemV7PacketSceneContractState -Packet $Packet;foreach($problem in @($contractState.Errors)){$errors.Add("ACT_TRACE_$problem")}
    $expectedByTrace=@{};$traceOrder=[Collections.Generic.List[string]]::new()
    if($isComplex){
        if($null -eq $BeatSheet){return [pscustomobject]@{Valid=$false;Errors=@('ACT_TRACE_BEAT_SHEET_REQUIRED')}}
        $beatState=Get-SystemV7BeatSheetSemanticState -Packet $Packet -BeatSheet $BeatSheet -ActId ([string]$Packet.act_id) -ExpectedGenerateRunId ([string]$BeatSheet.generate_run_id)
        if(-not $beatState.Valid){foreach($problem in $beatState.Errors){$errors.Add("ACT_TRACE_BEAT_INVALID: $problem")}}
        foreach($beat in @($BeatSheet.beats)){$id=[string]$beat.beat_id;if($expectedByTrace.ContainsKey($id)){$errors.Add("ACT_TRACE_BEAT_DUPLICATE: $id");continue};$expectedByTrace[$id]=[pscustomobject]@{SwId=[string]$beat.sw_id;Sources=@([string[]]@($beat.source_p_ids));Narrative=@([string[]]@($beat.nq_nr_vc_ids))};$traceOrder.Add($id)}
    }else{
        $contractBySw=$contractState.ContractBySw
        foreach($swRaw in @($Packet.scene_weave_ids)){$sw=[string]$swRaw;if(-not $contractBySw.ContainsKey($sw)){$errors.Add("ACT_TRACE_SCENE_CONTRACT_MISSING: $sw");continue};$contract=$contractBySw[$sw];$tokens=[Collections.Generic.List[string]]::new();foreach($token in @([string]$contract.nq_action,[string]$contract.nr_action)+@($contract.vc_ids)){if($token -and $token -cne 'BRAK'){$tokens.Add([string]$token)}};$expectedByTrace[$sw]=[pscustomobject]@{SwId=$sw;Sources=@([string[]]@($contract.required_p));AllowedSources=@([string[]]@($contract.required_p)+[string[]]@($contract.supporting_p));Narrative=@($tokens)};$traceOrder.Add($sw)}
    }
    $coveredTrace=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$firstUse=[Collections.Generic.List[string]]::new();$traceOrdinal=@{};for($ordinal=0;$ordinal -lt $traceOrder.Count;$ordinal++){$traceOrdinal[$traceOrder[$ordinal]]=$ordinal};$lastOrdinal=-1;$sourceCoverage=@{};$narrativeCoverage=@{};foreach($id in $traceOrder){$sourceCoverage[$id]=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$narrativeCoverage[$id]=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)}
    $blockIndex=0
    foreach($block in $Blocks){
        $blockIndex++;$label='BLOCK_INPUT-{0:D3}' -f $blockIndex
        $traceRefs=@([string[]]@($block.trace_refs));$traceSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$validRefs=[Collections.Generic.List[string]]::new()
        if($traceRefs.Count -eq 0){$errors.Add("ACT_TRACE_REFS_EMPTY: $label")}
        foreach($ref in $traceRefs){if(-not $traceSeen.Add($ref)){$errors.Add("ACT_TRACE_REF_DUPLICATE: $label/$ref")}elseif(-not $expectedByTrace.ContainsKey($ref)){$errors.Add("ACT_TRACE_REF_ILLEGAL: $label/$ref")}else{$validRefs.Add($ref);$ordinal=[int]$traceOrdinal[$ref];if($ordinal -lt $lastOrdinal){$errors.Add("ACT_TRACE_ORDER_REGRESSION: $label/$ref")}elseif($ordinal -gt $lastOrdinal){$lastOrdinal=$ordinal};if($coveredTrace.Add($ref)){$firstUse.Add($ref)}}}
        $allowedSources=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$allowedNarrative=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($ref in $validRefs){$expect=$expectedByTrace[$ref];$sourceList=if($isComplex){@($expect.Sources)}else{@($expect.AllowedSources)};foreach($p in $sourceList){$null=$allowedSources.Add([string]$p)};foreach($token in @($expect.Narrative)){$null=$allowedNarrative.Add([string]$token)}}
        $sourceSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($p in @([string[]]@($block.source_p_ids))){if(-not $sourceSeen.Add($p)){$errors.Add("ACT_TRACE_SOURCE_DUPLICATE: $label/$p")}elseif(-not $allowedSources.Contains($p)){$errors.Add("ACT_TRACE_SOURCE_NOT_IN_REFERENCED_UNIT: $label/$p")}else{foreach($ref in $validRefs){if([string]$p -in @([string[]]@($expectedByTrace[$ref].Sources)) -or (-not $isComplex -and [string]$p -in @([string[]]@($expectedByTrace[$ref].AllowedSources)))){$null=$sourceCoverage[$ref].Add($p)}}}}
        $narrativeSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($token in @([string[]]@($block.narrative_refs))){if(-not $narrativeSeen.Add($token)){$errors.Add("ACT_TRACE_NARRATIVE_DUPLICATE: $label/$token")}elseif(-not $allowedNarrative.Contains($token)){$errors.Add("ACT_TRACE_NARRATIVE_NOT_IN_REFERENCED_UNIT: $label/$token")}else{foreach($ref in $validRefs){if([string]$token -in @([string[]]@($expectedByTrace[$ref].Narrative))){$null=$narrativeCoverage[$ref].Add($token)}}}}
        foreach($token in @($narrativeSeen)){
            if([string]$token -match '^REVEAL:NR-\d{3}$'){$requiredRevealEvidence=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($ref in $validRefs){$sw=[string]$expectedByTrace[$ref].SwId;if($contractState.ContractBySw.ContainsKey($sw) -and [string]$contractState.ContractBySw[$sw].nr_action -ceq [string]$token){foreach($p in @($contractState.ContractBySw[$sw].nr_evidence_p)){$null=$requiredRevealEvidence.Add([string]$p)}}};foreach($p in @($requiredRevealEvidence)){if(-not $sourceSeen.Contains([string]$p)){$errors.Add("ACT_TRACE_REVEAL_EVIDENCE_NOT_COOCCURRENT: $label/$token/$p")}}}
            if([string]$token -match '^VC-\d{3}$' -and $contractState.ViewerContactById.ContainsKey([string]$token)){$vc=$contractState.ViewerContactById[[string]$token];if(([string]$vc.function -ceq 'AUTHOR' -or [string]$vc.level -ceq 'AUTHORIAL') -and ([string]$block.prose).IndexOf([string]$vc.author_text,[StringComparison]::Ordinal) -lt 0){$errors.Add("ACT_TRACE_AUTHOR_TEXT_NOT_LITERAL: $label/$token")}}
        }
        foreach($vc in @($contractState.Registry.viewer_contacts)){if(([string]$vc.function -ceq 'AUTHOR' -or [string]$vc.level -ceq 'AUTHORIAL') -and ([string]$block.prose).IndexOf([string]$vc.author_text,[StringComparison]::Ordinal) -ge 0 -and -not $narrativeSeen.Contains([string]$vc.vc_id)){$errors.Add("ACT_TRACE_AUTHOR_TEXT_WITHOUT_VC_REF: $label/$([string]$vc.vc_id)")}}
    }
    if(($firstUse -join '|') -cne ($traceOrder -join '|')){$errors.Add("ACT_TRACE_FIRST_USE_ORDER_INVALID: expected=$($traceOrder -join ',');actual=$($firstUse -join ',')")}
    foreach($trace in $traceOrder){if(-not $coveredTrace.Contains($trace)){$errors.Add("ACT_TRACE_UNIT_NOT_COVERED: $trace")};foreach($p in @($expectedByTrace[$trace].Sources)){if(-not $sourceCoverage[$trace].Contains([string]$p)){$errors.Add("ACT_TRACE_SOURCE_NOT_REALIZED: $trace/$p")}};foreach($token in @($expectedByTrace[$trace].Narrative)){if(-not $narrativeCoverage[$trace].Contains([string]$token)){$errors.Add("ACT_TRACE_NARRATIVE_NOT_REALIZED: $trace/$token")}}}
    $traceToSw=[ordered]@{};foreach($traceId in $traceOrder){if($expectedByTrace.ContainsKey([string]$traceId)){$traceToSw[[string]$traceId]=[string]$expectedByTrace[[string]$traceId].SwId}}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);TraceIds=@($traceOrder);TraceToSw=$traceToSw}
}

function Get-SystemV7ContinuityOutStructuralState {
    param(
        [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
        [Parameter(Mandatory)][object]$ContinuityOut,
        [Parameter(Mandatory)][object]$BlocksData,
        [Parameter(Mandatory)][object]$ArchitectureData
    )
    $errors=[Collections.Generic.List[string]]::new();$out=$ContinuityOut
    $outFields=@('schema','act_id','records','nq_paid','nq_opened','nq_reframed','open_nq_ids_out','nr_revealed','nr_consequences','nr_setup_only','character_and_world_state','bridge_realized','bridge_block_refs','opening_move_type','opening_block_refs','closing_move_type','closing_block_refs','uncertainties_preserved')
    if(@(Compare-Object -ReferenceObject $outFields -DifferenceObject @($out.PSObject.Properties.Name)).Count -gt 0 -or @($out.PSObject.Properties.Name).Count -ne $outFields.Count){$errors.Add('CONTINUITY_OUT_FIELDS_INVALID')}
    if([string]$out.schema -cne 'CONTINUITY_OUT_V1' -or [string]$out.act_id -cne $ActId){$errors.Add('CONTINUITY_OUT_IDENTITY_INVALID')}
    if(@($out.records).Count -eq 0){$errors.Add('CONTINUITY_OUT_RECORDS_EMPTY')}
    if(-not (Test-SystemV7ExactMember -Value ([string]$out.opening_move_type) -Allowed @('SCENA','ANOMALIA','DOKUMENT','KONSEKWENCJA','KONTRAST','KONTAKT_Z_WIDZEM','POWRÓT_DO_MOTYWU'))){$errors.Add('CONTINUITY_OUT_OPENING_MOVE_INVALID')}
    if(-not (Test-SystemV7ExactMember -Value ([string]$out.closing_move_type) -Allowed @('DECYZJA','REVEAL','PAYOFF','KONSEKWENCJA','GRANICA_WIEDZY','NOWA_PĘTLA','POWRÓT_DO_MOTYWU'))){$errors.Add('CONTINUITY_OUT_CLOSING_MOVE_INVALID')}
    if(-not(Test-SystemV7ConcreteText -Value ([string]$out.bridge_realized))){$errors.Add('CONTINUITY_OUT_BRIDGE_NOT_CONCRETE')}
    $orderedBlocks=@($BlocksData.blocks);$blockIndex=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);foreach($block in $orderedBlocks){try{$blockIndex.Add([string]$block.block_id,$block)}catch{$errors.Add("CONTINUITY_OUT_BLOCK_MAP_DUPLICATE: $($block.block_id)")}}
    $firstBlockId=if($orderedBlocks.Count -gt 0){[string]$orderedBlocks[0].block_id}else{''};$lastBlockId=if($orderedBlocks.Count -gt 0){[string]$orderedBlocks[-1].block_id}else{''}
    $architectureAct=@($ArchitectureData.acts|Where-Object{[string]$_.act_id -ceq $ActId})
    $architectureSw=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($sw in @($ArchitectureData.scene_weave|Where-Object{[string]$_.act_id -ceq $ActId})){$null=$architectureSw.Add([string]$sw.sw_id)}
    foreach($block in $orderedBlocks){if($block.PSObject.Properties.Name -notcontains 'sw_ids' -or @($block.sw_ids).Count -eq 0){$errors.Add("CONTINUITY_OUT_BLOCK_SW_IDS_MISSING: $($block.block_id)");continue};$swSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($swId in @($block.sw_ids)){if([string]$swId -notmatch '^SW-\d{3}$' -or -not $swSeen.Add([string]$swId) -or -not $architectureSw.Contains([string]$swId)){$errors.Add("CONTINUITY_OUT_BLOCK_SW_ID_INVALID: $($block.block_id)/$swId")}}}
    $globalRelated=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($collection in @(@($ArchitectureData.questions),@($ArchitectureData.reveals),@($ArchitectureData.viewer_contacts),@($ArchitectureData.scene_weave))){foreach($item in $collection){foreach($name in @('nq_id','nr_id','vc_id','sw_id')){if($item.PSObject.Properties.Name -ccontains $name){$null=$globalRelated.Add([string]$item.$name)}}}}
    $allowedRelated=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if($architectureAct.Count -eq 1){$actContract=$architectureAct[0];foreach($id in @($actContract.scene_weave_ids)+@($actContract.open_nq_ids)+@($actContract.vc_ids)){$null=$allowedRelated.Add([string]$id)};foreach($action in @($actContract.nq_actions)+@($actContract.nr_actions)){foreach($match in [regex]::Matches([string]$action,'(?:NQ|NR)-\d{3}')){$null=$allowedRelated.Add([string]$match.Value)}}}
    $stateIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$coveredSw=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $getBoundSources={param($Refs,[string]$Code,[switch]$RequireAny)$available=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);if($RequireAny -and @($Refs).Count -eq 0){$errors.Add("${Code}_EMPTY")};foreach($ref in @($Refs)){$fields=@('block_id','block_sha256');$bid=[string]$ref.block_id;if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($ref.PSObject.Properties.Name)).Count -gt 0 -or @($ref.PSObject.Properties.Name).Count -ne $fields.Count -or -not $seen.Add($bid) -or -not $blockIndex.ContainsKey($bid) -or [string]$blockIndex[$bid].block_sha256 -cne [string]$ref.block_sha256){$errors.Add("${Code}_INVALID: $bid")}elseif($blockIndex.ContainsKey($bid)){foreach($p in @($blockIndex[$bid].source_p_ids)){$null=$available.Add([string]$p)}}};return ,$available}
    foreach($record in @($out.records)){
        $fields=@('state_id','category','value','class','block_refs','related_ids','source_p_ids');if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($record.PSObject.Properties.Name)).Count -gt 0 -or @($record.PSObject.Properties.Name).Count -ne $fields.Count){$errors.Add('CONTINUITY_OUT_RECORD_FIELDS_INVALID');continue}
        $sid=[string]$record.state_id;if($sid -notmatch '^STATE-\d{3}$' -or -not $stateIds.Add($sid)){$errors.Add("CONTINUITY_OUT_STATE_ID_INVALID: $sid")}
        if(-not (Test-SystemV7ExactMember -Value ([string]$record.category) -Allowed @('FACT','INFERENCE','QUESTION','REVEAL','BRIDGE','WORLD_STATE','KNOWLEDGE_BOUNDARY')) -or -not (Test-SystemV7ExactMember -Value ([string]$record.class) -Allowed @('TEXT_ASSERTED','VIEWER_INFERENCE'))){$errors.Add("CONTINUITY_OUT_CLASS_INVALID: $sid")}
        if(-not(Test-SystemV7ConcreteText -Value ([string]$record.value))){$errors.Add("CONTINUITY_OUT_VALUE_NOT_CONCRETE: $sid")}
        $refSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$availableSources=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$availableNarrative=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$availableSw=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$boundProse=[Collections.Generic.List[string]]::new()
        if(@($record.block_refs).Count -eq 0){$errors.Add("CONTINUITY_OUT_BLOCK_REFS_EMPTY: $sid")}
        foreach($ref in @($record.block_refs)){$rf=@('block_id','block_sha256');$bid=[string]$ref.block_id;if(@(Compare-Object -ReferenceObject $rf -DifferenceObject @($ref.PSObject.Properties.Name)).Count -gt 0 -or @($ref.PSObject.Properties.Name).Count -ne $rf.Count -or -not $refSeen.Add($bid) -or -not $blockIndex.ContainsKey($bid) -or [string]$blockIndex[$bid].block_sha256 -cne [string]$ref.block_sha256){$errors.Add("CONTINUITY_OUT_BLOCK_REF_INVALID: $sid/$bid")}elseif($blockIndex.ContainsKey($bid)){foreach($p in @($blockIndex[$bid].source_p_ids)){$null=$availableSources.Add([string]$p)};foreach($token in @($blockIndex[$bid].narrative_refs)){$null=$availableNarrative.Add([string]$token)};foreach($swId in @($blockIndex[$bid].sw_ids)){$null=$availableSw.Add([string]$swId)};$boundProse.Add([string]$blockIndex[$bid].prose)}}
        $relatedSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($id in @($record.related_ids)){$value=[string]$id;if($value -notmatch '^(?:NQ|NR|VC|SW)-\d{3}$' -or -not $relatedSeen.Add($value) -or -not $globalRelated.Contains($value) -or -not $allowedRelated.Contains($value)){$errors.Add("CONTINUITY_OUT_RELATED_ID_INVALID: $sid/$value")}elseif($value -match '^SW-'){if(-not $availableSw.Contains($value)){$errors.Add("CONTINUITY_OUT_RELATED_SW_NOT_IN_BOUND_BLOCKS: $sid/$value")}else{$null=$coveredSw.Add($value)}}}
        $sourceSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($p in @($record.source_p_ids)){$value=[string]$p;if($value -notmatch '^#P-\d{3,}$' -or -not $sourceSeen.Add($value) -or -not $availableSources.Contains($value)){$errors.Add("CONTINUITY_OUT_SOURCE_ID_INVALID: $sid/$value")}}
        if((Test-SystemV7ExactMember -Value ([string]$record.category) -Allowed @('FACT','REVEAL')) -and $sourceSeen.Count -eq 0){$errors.Add("CONTINUITY_OUT_SOURCE_REQUIRED: $sid")}
        if([string]$record.class -ceq 'TEXT_ASSERTED' -and @($boundProse|Where-Object{$_.IndexOf([string]$record.value,[StringComparison]::Ordinal) -ge 0}).Count -eq 0){$errors.Add("CONTINUITY_OUT_TEXT_ASSERTED_NOT_VERBATIM_BOUND: $sid")}
        if([string]$record.category -ceq 'REVEAL'){$nrIds=@($record.related_ids|Where-Object{[string]$_ -match '^NR-\d{3}$'});if($nrIds.Count -ne 1){$errors.Add("CONTINUITY_OUT_REVEAL_RELATED_NR_INVALID: $sid")}else{$nrId=[string]$nrIds[0];$nr=@($ArchitectureData.reveals|Where-Object{[string]$_.nr_id -ceq $nrId});if($nr.Count -ne 1 -or [string]$nrId -cnotin @([string[]]@($out.nr_revealed)) -or -not $availableNarrative.Contains("REVEAL:$nrId")){$errors.Add("CONTINUITY_OUT_REVEAL_BINDING_INVALID: $sid/$nrId")}elseif($nr.Count -eq 1){foreach($p in @($nr[0].evidence_p_ids)){if(-not $sourceSeen.Contains([string]$p)){$errors.Add("CONTINUITY_OUT_REVEAL_EVIDENCE_MISSING: $sid/$nrId/$p")}}}}}
    }
    $act=$architectureAct;if($act.Count -ne 1){$errors.Add('CONTINUITY_OUT_ARCHITECTURE_ACT_MISSING')}else{if(-not $coveredSw.Contains([string]$act[0].state_change_evidence)){$errors.Add("CONTINUITY_OUT_STATE_CHANGE_SW_NOT_COVERED: $($act[0].state_change_evidence)")};if([string]$out.bridge_realized -cne [string]$act[0].bridge_out){$errors.Add('CONTINUITY_OUT_BRIDGE_CONTRACT_MISMATCH')}}
    foreach($binding in @(@('BRIDGE',$out.bridge_block_refs),@('OPENING_MOVE',$out.opening_block_refs),@('CLOSING_MOVE',$out.closing_block_refs))){$null=&$getBoundSources $binding[1] "CONTINUITY_OUT_$($binding[0])_BLOCK_REFS" -RequireAny}
    if($firstBlockId -and @($out.opening_block_refs|Where-Object{[string]$_.block_id -ceq $firstBlockId}).Count -eq 0){$errors.Add('CONTINUITY_OUT_OPENING_NOT_BOUND_TO_FIRST_BLOCK')};if($lastBlockId -and @($out.closing_block_refs|Where-Object{[string]$_.block_id -ceq $lastBlockId}).Count -eq 0){$errors.Add('CONTINUITY_OUT_CLOSING_NOT_BOUND_TO_LAST_BLOCK')};if($lastBlockId -and @($out.bridge_block_refs|Where-Object{[string]$_.block_id -ceq $lastBlockId}).Count -eq 0){$errors.Add('CONTINUITY_OUT_BRIDGE_NOT_BOUND_TO_LAST_BLOCK')}
    $worldIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($item in @($out.character_and_world_state)){$fields=@('world_state_id','value','class','block_refs','source_p_ids');$id=[string]$item.world_state_id;if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($item.PSObject.Properties.Name)).Count -gt 0 -or @($item.PSObject.Properties.Name).Count -ne $fields.Count -or $id -notmatch '^WORLD-\d{3}$' -or -not $worldIds.Add($id) -or -not $stateIds.Add($id)){$errors.Add("CONTINUITY_OUT_WORLD_STATE_FIELDS_OR_ID_INVALID: $id");continue};if(-not(Test-SystemV7ConcreteText -Value ([string]$item.value)) -or -not (Test-SystemV7ExactMember -Value ([string]$item.class) -Allowed @('TEXT_ASSERTED','VIEWER_INFERENCE'))){$errors.Add("CONTINUITY_OUT_WORLD_STATE_VALUE_OR_CLASS_INVALID: $id")};$available=&$getBoundSources $item.block_refs "CONTINUITY_OUT_WORLD_STATE_BLOCK_REFS/$id" -RequireAny;$sourceSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($p in @($item.source_p_ids)){$value=[string]$p;if($value -notmatch '^#P-\d{3,}$' -or -not $sourceSeen.Add($value) -or -not $available.Contains($value)){$errors.Add("CONTINUITY_OUT_WORLD_STATE_SOURCE_INVALID: $id/$value")}};if([string]$item.class -ceq 'TEXT_ASSERTED' -and $sourceSeen.Count -eq 0){$errors.Add("CONTINUITY_OUT_WORLD_STATE_SOURCE_REQUIRED: $id")};if([string]$item.class -ceq 'TEXT_ASSERTED'){$anchors=@($item.block_refs|ForEach-Object{if($blockIndex.ContainsKey([string]$_.block_id)){[string]$blockIndex[[string]$_.block_id].prose}}|Where-Object{$_.IndexOf([string]$item.value,[StringComparison]::Ordinal) -ge 0});if($anchors.Count -eq 0){$errors.Add("CONTINUITY_OUT_WORLD_STATE_NOT_VERBATIM_BOUND: $id")}}}
    $uncertaintyIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($item in @($out.uncertainties_preserved)){$fields=@('uncertainty_id','value','block_refs','source_p_ids');$id=[string]$item.uncertainty_id;if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($item.PSObject.Properties.Name)).Count -gt 0 -or @($item.PSObject.Properties.Name).Count -ne $fields.Count -or $id -notmatch '^UNCERTAINTY-\d{3}$' -or -not $uncertaintyIds.Add($id) -or -not $stateIds.Add($id)){$errors.Add("CONTINUITY_OUT_UNCERTAINTY_FIELDS_OR_ID_INVALID: $id");continue};if(-not(Test-SystemV7ConcreteText -Value ([string]$item.value))){$errors.Add("CONTINUITY_OUT_UNCERTAINTY_VALUE_INVALID: $id")};$available=&$getBoundSources $item.block_refs "CONTINUITY_OUT_UNCERTAINTY_BLOCK_REFS/$id" -RequireAny;$sourceSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($p in @($item.source_p_ids)){$value=[string]$p;if($value -notmatch '^#P-\d{3,}$' -or -not $sourceSeen.Add($value) -or -not $available.Contains($value)){$errors.Add("CONTINUITY_OUT_UNCERTAINTY_SOURCE_INVALID: $id/$value")}};$anchors=@($item.block_refs|ForEach-Object{if($blockIndex.ContainsKey([string]$_.block_id)){[string]$blockIndex[[string]$_.block_id].prose}}|Where-Object{$_.IndexOf([string]$item.value,[StringComparison]::Ordinal) -ge 0});if($anchors.Count -eq 0){$errors.Add("CONTINUITY_OUT_UNCERTAINTY_NOT_VERBATIM_BOUND: $id")}}
    foreach($special in @('BRIDGE','OPENING_MOVE','CLOSING_MOVE')){$null=$stateIds.Add($special)}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);StateIds=@($stateIds);CoveredSwIds=@($coveredSw)}
}

function Get-SystemV7StorySpineProjection {
    param([Parameter(Mandatory)][object]$ArchitectureData)
    $value = [ordered]@{
        schema = 'PROJECT_STORY_SPINE_V2'
        # Revision jest identyfikatorem pełnego pliku 02, nie treścią Story
        # Spine. Gdyby wchodziła do projekcji, każda lokalna korekta jednego
        # aktu unieważniałaby wspólny prefix i prozę wszystkich pozostałych
        # aktów. Pełny 02 nadal jest osobno wiązany hashem w manifestach.
        story_dna = $ArchitectureData.story_dna
        hook_contract = $ArchitectureData.hook_contract
        final_contract = $ArchitectureData.final_contract
        questions = @($ArchitectureData.questions | ForEach-Object { [ordered]@{ nq_id=$_.nq_id; question=$_.question; expected_form=$_.expected_form; payoff_node=$_.payoff_node } })
        reveals = @($ArchitectureData.reveals | ForEach-Object { [ordered]@{ nr_id=$_.nr_id; target_node=$_.target_node; consequence=$_.consequence; uncertainty_form=$_.uncertainty_form } })
    }
    $json = ConvertTo-SystemV7CanonicalJson -Value $value
    [pscustomobject]@{ Value=$value; Json=$json; Sha256=(Get-SystemV7NarrativeSha256Text -Text $json) }
}

function Get-SystemV7ActProjection {
    param([Parameter(Mandatory)][object]$ArchitectureData, [Parameter(Mandatory)][string]$ActId)
    $act = @($ArchitectureData.acts | Where-Object { [string]$_.act_id -ceq $ActId })
    if ($act.Count -ne 1) { throw "ACT_NOT_UNIQUE_OR_MISSING: $ActId" }
    $swIds = @($act[0].scene_weave_ids | ForEach-Object { [string]$_ })
    $weave = @($ArchitectureData.scene_weave | Where-Object { [string]$_.sw_id -cin $swIds })
    $value = [ordered]@{ schema='ACT_PROJECTION_V2'; act=$act[0]; scene_weave=$weave }
    $json = ConvertTo-SystemV7CanonicalJson -Value $value
    [pscustomobject]@{ Value=$value; Json=$json; Sha256=(Get-SystemV7NarrativeSha256Text -Text $json); Act=$act[0]; SceneWeave=$weave }
}

function Get-SystemV7EvidenceSelectionProjection {
    param([Parameter(Mandatory)][object]$ActProjection, [Parameter(Mandatory)][object]$EvidenceRegistry)
    $required = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $supporting = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($sw in @($ActProjection.SceneWeave)) {
        foreach ($entry in @($sw.required_evidence)) { $null = $required.Add([string]$entry.p_id) }
        foreach ($id in @($sw.supporting_p_ids)) { $null = $supporting.Add([string]$id) }
    }
    foreach($id in @($required)){$null=$supporting.Remove([string]$id)}
    $ids = [string[]]@(@($required) + @($supporting) | Select-Object -Unique)
    [Array]::Sort($ids, [StringComparer]::Ordinal)
    $cards = foreach ($id in $ids) {
        if (-not $EvidenceRegistry.Cards.ContainsKey($id)) { throw "EVIDENCE_CARD_MISSING: $id" }
        $card = $EvidenceRegistry.Cards[$id]
        if ([string]$card.qa_k1 -cne 'GOTOWA') { throw "EVIDENCE_CARD_NOT_READY: $id" }
        [ordered]@{
            p_id = $id
            role = if ($required.Contains($id)) { 'REQUIRED' } else { 'SUPPORTING' }
            content = $card.content
            source_id = $card.source_id
            source_registry_row = if ($EvidenceRegistry.Sources.ContainsKey([string]$card.source_id)) { $EvidenceRegistry.Sources[[string]$card.source_id] } else { '' }
            locator = $card.locator
            qa_k1 = $card.qa_k1
        }
    }
    $value = [ordered]@{ schema='EVIDENCE_SELECTION_V2'; cards=@($cards) }
    $json = ConvertTo-SystemV7CanonicalJson -Value $value
    [pscustomobject]@{ Value=$value; Json=$json; Sha256=(Get-SystemV7NarrativeSha256Text -Text $json); RequiredIds=@($required); SupportingIds=@($supporting) }
}

function Get-SystemV7VoiceProfileState {
    param([Parameter(Mandatory)][string]$ProfilePath, [switch]$AllowTestApproved)
    $errors = [Collections.Generic.List[string]]::new()
    $full=[IO.Path]::GetFullPath($ProfilePath)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return [pscustomobject]@{ Valid=$false; Errors=@('VOICE_PROFILE_MISSING'); Rules=''; Exemplars=''; Revision=''; Path=$full } }
    try{$bytes=[IO.File]::ReadAllBytes($full);$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}catch{return [pscustomobject]@{Valid=$false;Errors=@('VOICE_PROFILE_NOT_STRICT_UTF8');Rules='';Exemplars='';Revision='';Path=$full}}
    $text=ConvertTo-SystemV7LfText -Text $text
    $headerNames=@('VOICE_PROFILE_SCHEMA','VOICE_PROFILE_REVISION','STATUS','APPROVED_BY','APPROVAL_RECEIPT_PATH','APPROVAL_RECEIPT_SHA256','RULES_SHA256','EXEMPLAR_REGISTRY_SHA256','EXEMPLARS_SHA256');$header=@{}
    foreach($name in $headerNames){$matches=@([regex]::Matches($text,"(?m)^$([regex]::Escape($name)):\s*(.*?)\s*$"));if($matches.Count -ne 1){$errors.Add("VOICE_PROFILE_HEADER_FIELD_COUNT_INVALID: $name");$header[$name]=''}else{$header[$name]=$matches[0].Groups[1].Value.Trim()}}
    $revision=[string]$header.VOICE_PROFILE_REVISION;$status=[string]$header.STATUS;$approvedBy=[string]$header.APPROVED_BY
    if([string]$header.VOICE_PROFILE_SCHEMA -cne 'SYSTEM_V7_VOICE_PROFILE_V1'){$errors.Add('VOICE_PROFILE_SCHEMA_INVALID')}
    if($revision -notmatch '^[A-Z0-9][A-Z0-9._-]{2,80}$'){$errors.Add('VOICE_PROFILE_REVISION_INVALID')}
    $testApproved=$AllowTestApproved -and $status -ceq 'TEST_APPROVED' -and $approvedBy -ceq 'TEST_FIXTURE'
    if(-not $testApproved -and ($status -cne 'APPROVED' -or $approvedBy -cne 'DAWID')){$errors.Add('VOICE_PROFILE_NOT_DAWID_APPROVED')}
    if($testApproved -and ([string]$header.APPROVAL_RECEIPT_PATH -cne 'BRAK' -or [string]$header.APPROVAL_RECEIPT_SHA256 -cne 'BRAK')){$errors.Add('VOICE_PROFILE_TEST_RECEIPT_FIELDS_INVALID')}

    $rulesMatch=[regex]::Match($text,'(?ms)^##\s+VOICE RULES\s*\n(?<body>.*?)(?=^##\s+VOICE EXEMPLARS\s*$)')
    $registryMatch=[regex]::Match($text,'(?ms)^##\s+VOICE EXEMPLARS\s*\n\s*```json\s*\n(?<json>.*?)\n```\s*(?=^##\s+|\z)')
    $rules=if($rulesMatch.Success){(ConvertTo-SystemV7LfText -Text $rulesMatch.Groups['body'].Value).Trim()+"`n"}else{''}
    if(-not $rulesMatch.Success -or -not(Test-SystemV7ConcreteText -Value $rules)){$errors.Add('VOICE_RULES_MISSING')}
    $registry=$null;if(-not $registryMatch.Success){$errors.Add('VOICE_EXEMPLAR_REGISTRY_MISSING')}else{try{$registry=$registryMatch.Groups['json'].Value|ConvertFrom-Json -DateKind String -Depth 64}catch{$errors.Add('VOICE_EXEMPLAR_REGISTRY_INVALID_JSON')}}
    $registryJson='';$compiled=[Collections.Generic.List[string]]::new();$sourceBindings=[Collections.Generic.List[object]]::new();$coverage=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $allowedCoverage=@('STRONG_OPENING','SCENE','UNCERTAINTY','KNOWLEDGE_BOUNDARY','VIEWER_CONTACT','TRANSITION','PAYOFF')
    if($registry){
        $registryFields=@('schema','exemplars');if(@(Compare-Object -ReferenceObject $registryFields -DifferenceObject @($registry.PSObject.Properties.Name)).Count -gt 0 -or @($registry.PSObject.Properties.Name).Count -ne $registryFields.Count -or [string]$registry.schema -cne 'VOICE_EXEMPLAR_REGISTRY_V1' -or @($registry.exemplars).Count -eq 0){$errors.Add('VOICE_EXEMPLAR_REGISTRY_SCHEMA_INVALID')}
        foreach($item in @($registry.exemplars)){
            $fields=@('exemplar_id','project_name','artifact_path','artifact_sha256','exact_text_sha256','approval_status','demonstrates','exact_text');$id=[string]$item.exemplar_id
            if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($item.PSObject.Properties.Name)).Count -gt 0 -or @($item.PSObject.Properties.Name).Count -ne $fields.Count -or $id -notmatch '^EX-\d{3}$' -or -not $ids.Add($id)){$errors.Add("VOICE_EXEMPLAR_FIELDS_OR_ID_INVALID: $id");continue}
            $exact=(ConvertTo-SystemV7LfText -Text ([string]$item.exact_text)).Trim();$exactSha=if($exact){Get-SystemV7NarrativeSha256Text -Text ($exact+"`n")}else{''}
            if(-not(Test-SystemV7ConcreteText -Value ([string]$item.project_name)) -or -not(Test-SystemV7ConcreteText -Value $exact) -or [string]$item.exact_text_sha256 -cne $exactSha){$errors.Add("VOICE_EXEMPLAR_TEXT_OR_HASH_INVALID: $id")}
            $demonstrates=@([string[]]@($item.demonstrates));$seenFunctions=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);if($demonstrates.Count -eq 0){$errors.Add("VOICE_EXEMPLAR_DEMONSTRATES_EMPTY: $id")};foreach($function in $demonstrates){if($function -notin $allowedCoverage -or -not $seenFunctions.Add($function)){$errors.Add("VOICE_EXEMPLAR_DEMONSTRATES_INVALID: $id/$function")}else{$null=$coverage.Add($function)}}
            $expectedApproval=if($testApproved){'TEST_APPROVED'}else{'DAWID_APPROVED'};if([string]$item.approval_status -cne $expectedApproval){$errors.Add("VOICE_EXEMPLAR_APPROVAL_INVALID: $id")}
            $artifact=[string]$item.artifact_path;$artifactSha=[string]$item.artifact_sha256
            $sourceBinding=$null
            if(-not $testApproved){
                try{$artifact=[IO.Path]::GetFullPath($artifact)}catch{$errors.Add("VOICE_EXEMPLAR_ARTIFACT_PATH_INVALID: $id");$artifact=''}
                if(-not $artifact -or -not(Test-Path -LiteralPath $artifact -PathType Leaf) -or [IO.Path]::GetFileName($artifact) -cne '05-FINAL-SCRIPT.md'){$errors.Add("VOICE_EXEMPLAR_ARTIFACT_NOT_FINAL: $id")}
                else{
                    $projectRoot=Split-Path -Parent $artifact
                    $metaPath=Join-Path $projectRoot 'meta.md';$originState=$null;$workflow='';$k5State=$null;$k5Path='';$k5Sha=''
                    if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){$errors.Add("VOICE_EXEMPLAR_PROJECT_META_MISSING: $id")}
                    else{
                        try{
                            $metaText=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
                            $workflow=Get-SystemV7SingleMetaField -Text $metaText -Name 'WORKFLOW_REVISION'
                            $metaProjectName=Get-SystemV7SingleMetaField -Text $metaText -Name 'PROJECT_NAME'
                            if($metaProjectName -cne [string]$item.project_name){$errors.Add("VOICE_EXEMPLAR_PROJECT_NAME_MISMATCH: $id")}
                            $originState=Assert-SystemV7CurrentProjectOrigin -ProjectPath $projectRoot -MetaText $metaText
                            $finalStatusMatches=@([regex]::Matches((Get-Content -LiteralPath $artifact -Raw -Encoding UTF8),'(?m)^STATUS:\s*(.*?)\s*$'))
                            if($finalStatusMatches.Count -ne 1 -or $finalStatusMatches[0].Groups[1].Value.Trim() -cne 'ZATWIERDZONY'){$errors.Add("VOICE_EXEMPLAR_FINAL_NOT_DAWID_APPROVED: $id")}
                            if($workflow -ceq $script:SystemV7NarrativeWorkflowRevision){
                                if($null -eq (Get-Command Get-SystemV7K5ApprovalV2State -ErrorAction SilentlyContinue)){throw 'K5_V2_HELPER_NOT_LOADED'}
                                $k5State=Get-SystemV7K5ApprovalV2State -ProjectPath $projectRoot
                                if($k5State.Valid){$k5Path=[string]$k5State.Path;$k5Sha=[string]$k5State.Sha256}
                            }elseif($workflow -ceq $script:SystemV7PreviousProjectWorkflowRevision){
                                if($null -eq (Get-Command Get-K5ApprovalReceiptState -ErrorAction SilentlyContinue)){throw 'K5_LEGACY_HELPER_NOT_LOADED'}
                                $k5State=Get-K5ApprovalReceiptState -ProjectPath $projectRoot
                                if($k5State.Valid){$k5Path=[string]$k5State.ReceiptPath;$k5Sha=[string]$k5State.ReceiptSha256}
                            }else{throw "UNSUPPORTED_EXEMPLAR_WORKFLOW: $workflow"}
                            if(-not $k5State.Valid){$errors.Add("VOICE_EXEMPLAR_K5_APPROVAL_INVALID: $id/$($k5State.Errors -join ',')")}
                        }catch{$errors.Add("VOICE_EXEMPLAR_PROJECT_OR_K5_INVALID: $id/$($_.Exception.Message)")}
                    }
                    $liveSha=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash;if($liveSha -cne $artifactSha){$errors.Add("VOICE_EXEMPLAR_ARTIFACT_SHA_INVALID: $id")}
                    $artifactText=ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $artifact -Raw -Encoding UTF8);if($exact -and $artifactText.IndexOf($exact,[StringComparison]::Ordinal) -lt 0){$errors.Add("VOICE_EXEMPLAR_TEXT_NOT_VERBATIM_IN_ARTIFACT: $id")}
                    if($originState -and $originState.Valid -and $k5State -and $k5State.Valid){
                        $sourceBinding=[ordered]@{exemplar_id=$id;project_name=[string]$item.project_name;project_origin_sha256=[string]$originState.Sha256;workflow_revision=$workflow;artifact_path=$artifact;artifact_sha256=$artifactSha;k5_approval_receipt_path=$k5Path;k5_approval_receipt_sha256=$k5Sha;exact_text_sha256=$exactSha}
                    }
                }
            }elseif($artifactSha -notmatch '^[A-F0-9]{64}$'){$errors.Add("VOICE_EXEMPLAR_TEST_ARTIFACT_SHA_INVALID: $id")}
            if($exact){$compiled.Add($exact)}
            if($sourceBinding){$sourceBindings.Add($sourceBinding)}elseif($testApproved){$sourceBindings.Add([ordered]@{exemplar_id=$id;artifact_path=[string]$item.artifact_path;artifact_sha256=$artifactSha;exact_text_sha256=$exactSha})}
        }
        foreach($requiredFunction in $allowedCoverage){if(-not $coverage.Contains($requiredFunction)){$errors.Add("VOICE_EXEMPLAR_FUNCTION_COVERAGE_MISSING: $requiredFunction")}}
        $registryJson=ConvertTo-SystemV7CanonicalJson -Value $registry
    }
    $exemplars=if($compiled.Count){($compiled -join "`n`n")+"`n"}else{''};$rulesSha=if($rules){Get-SystemV7NarrativeSha256Text -Text $rules}else{''};$registrySha=if($registryJson){Get-SystemV7NarrativeSha256Text -Text $registryJson}else{''};$exemplarsSha=if($exemplars){Get-SystemV7NarrativeSha256Text -Text $exemplars}else{''}
    if([string]$header.RULES_SHA256 -cne $rulesSha){$errors.Add('VOICE_RULES_SHA_MISMATCH')};if([string]$header.EXEMPLAR_REGISTRY_SHA256 -cne $registrySha){$errors.Add('VOICE_EXEMPLAR_REGISTRY_SHA_MISMATCH')};if([string]$header.EXEMPLARS_SHA256 -cne $exemplarsSha){$errors.Add('VOICE_EXEMPLARS_SHA_MISMATCH')}
    if(-not $testApproved){
        $systemRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$systemPrefix=$systemRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
        try{$receiptPath=[IO.Path]::GetFullPath((Join-Path $systemRoot ([string]$header.APPROVAL_RECEIPT_PATH)))}catch{$receiptPath='';$errors.Add('VOICE_PROFILE_RECEIPT_PATH_INVALID')}
        if(-not $receiptPath -or -not $receiptPath.StartsWith($systemPrefix,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $receiptPath -PathType Leaf)){$errors.Add('VOICE_PROFILE_RECEIPT_MISSING')}
        else{
            $receiptSha=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash;if($receiptSha -cne [string]$header.APPROVAL_RECEIPT_SHA256){$errors.Add('VOICE_PROFILE_RECEIPT_SHA_MISMATCH')}
            try{$receiptRaw=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8;$receipt=$receiptRaw|ConvertFrom-Json -DateKind String -Depth 64}catch{$receipt=$null;$errors.Add('VOICE_PROFILE_RECEIPT_INVALID_JSON')}
            if($receipt){$receiptFields=@('schema','actor','attestation_scope','voice_profile_revision','profile_relative','rules_sha256','exemplar_registry_sha256','exemplars_sha256','exemplar_sources','approval_note','approved_at_utc','binding_sha256');if(@(Compare-Object -ReferenceObject $receiptFields -DifferenceObject @($receipt.PSObject.Properties.Name)).Count -gt 0 -or @($receipt.PSObject.Properties.Name).Count -ne $receiptFields.Count){$errors.Add('VOICE_PROFILE_RECEIPT_FIELDS_INVALID')};$profileRelative=[IO.Path]::GetRelativePath($systemRoot,$full).Replace('\','/');if([string]$receipt.schema -cne 'SYSTEM_V7_VOICE_PROFILE_APPROVAL_V1' -or [string]$receipt.actor -cne 'DAWID' -or [string]$receipt.attestation_scope -cne 'RULES_AND_EXACT_EXEMPLARS' -or [string]$receipt.voice_profile_revision -cne $revision -or [string]$receipt.profile_relative -cne $profileRelative -or [string]$receipt.rules_sha256 -cne $rulesSha -or [string]$receipt.exemplar_registry_sha256 -cne $registrySha -or [string]$receipt.exemplars_sha256 -cne $exemplarsSha -or (ConvertTo-SystemV7CanonicalJson -Value @($receipt.exemplar_sources)) -cne (ConvertTo-SystemV7CanonicalJson -Value @($sourceBindings)) -or -not(Test-SystemV7ConcreteText -Value ([string]$receipt.approval_note))){$errors.Add('VOICE_PROFILE_RECEIPT_BINDINGS_INVALID')};$copy=[ordered]@{};foreach($property in $receipt.PSObject.Properties){if($property.Name -cne 'binding_sha256'){$copy[$property.Name]=$property.Value}};if((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)) -cne [string]$receipt.binding_sha256 -or (ConvertTo-SystemV7CanonicalJson -Value $receipt) -cne (ConvertTo-SystemV7LfText -Text $receiptRaw)){$errors.Add('VOICE_PROFILE_RECEIPT_CANONICAL_BINDING_INVALID')}}
        }
    }
    [pscustomobject]@{
        Valid=$errors.Count -eq 0; Errors=@($errors); Revision=$revision; Status=$status; Rules=$rules; Exemplars=$exemplars; Registry=$registry
        RulesSha256=$rulesSha; ExemplarRegistrySha256=$registrySha; ExemplarsSha256=$exemplarsSha; SourceBindings=@($sourceBindings)
        Path=$full; ProfileSha256=([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))); Text=$text
    }
}

function Get-SystemV7VoiceProfileSelectionState {
    param([Parameter(Mandatory)][string]$ProjectPath,[string]$MetaText)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    $metaPath=Join-Path $project 'meta.md'
    if([string]::IsNullOrWhiteSpace($MetaText)){
        if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('VOICE_PROFILE_SELECTION_META_MISSING');Data=$null}}
        $MetaText=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    }
    try{
        $revision=Get-SystemV7NarrativeMetaField -Text $MetaText -Name 'VOICE_PROFILE_REVISION'
        $status=Get-SystemV7NarrativeMetaField -Text $MetaText -Name 'VOICE_PROFILE_STATUS'
        $relative=Get-SystemV7NarrativeMetaField -Text $MetaText -Name 'VOICE_PROFILE_SELECTION_RECEIPT_PATH'
        $declaredSha=Get-SystemV7NarrativeMetaField -Text $MetaText -Name 'VOICE_PROFILE_SELECTION_RECEIPT_SHA256'
    }catch{return [pscustomobject]@{Valid=$false;Errors=@("VOICE_PROFILE_SELECTION_META_INVALID: $($_.Exception.Message)");Data=$null}}
    if($status -cne 'APPROVED'){$errors.Add('VOICE_PROFILE_SELECTION_META_NOT_APPROVED')}
    if($relative -notmatch '^_work/system/voice-profile-selection-[A-F0-9]{64}\.json$' -or $declaredSha -notmatch '^[A-F0-9]{64}$'){$errors.Add('VOICE_PROFILE_SELECTION_RECEIPT_REFERENCE_INVALID')}
    $path=$null
    try{$path=[IO.Path]::GetFullPath((Join-Path $project $relative.Replace('/','\')));Assert-SystemV7PathNoReparse -Path $path -ContainmentRoot $project|Out-Null}catch{$errors.Add("VOICE_PROFILE_SELECTION_PATH_INVALID: $($_.Exception.Message)")}
    if(-not $path -or -not(Test-Path -LiteralPath $path -PathType Leaf)){$errors.Add('VOICE_PROFILE_SELECTION_RECEIPT_MISSING');return [pscustomobject]@{Valid=$false;Errors=@($errors);Data=$null;Path=$path}}
    $raw=Get-Content -LiteralPath $path -Raw -Encoding UTF8;$sha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($sha -cne $declaredSha){$errors.Add('VOICE_PROFILE_SELECTION_RECEIPT_SHA_MISMATCH')}
    try{$data=$raw|ConvertFrom-Json -DateKind String -Depth 64}catch{$errors.Add('VOICE_PROFILE_SELECTION_RECEIPT_INVALID_JSON');$data=$null}
    if($data){
        $fields=@('schema','workflow_revision','actor','attestation_scope','project_origin_sha256','voice_profile_revision','voice_profile_sha256','approval_note','selected_at_utc','binding_sha256')
        if(@($data.PSObject.Properties.Name).Count -ne $fields.Count -or @(Compare-Object -ReferenceObject $fields -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0){$errors.Add('VOICE_PROFILE_SELECTION_RECEIPT_FIELDS_INVALID')}
        $origin=Get-SystemV7ProjectOriginState -ProjectPath $project
        $systemRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$voicePath=Join-Path $systemRoot "_SYSTEM\NARRATIVE\VOICE-PROFILES\$revision.md";$voice=Get-SystemV7VoiceProfileState -ProfilePath $voicePath
        if(-not $origin.Valid -or [string]$data.project_origin_sha256 -cne [string]$origin.Sha256){$errors.Add('VOICE_PROFILE_SELECTION_ORIGIN_INVALID')}
        if(-not $voice.Valid -or [string]$data.voice_profile_revision -cne $revision -or [string]$data.voice_profile_sha256 -cne [string]$voice.ProfileSha256){$errors.Add('VOICE_PROFILE_SELECTION_LIVE_PROFILE_INVALID')}
        if([string]$data.schema -cne 'SYSTEM_V7_VOICE_PROFILE_SELECTION_V1' -or [string]$data.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$data.actor -cne 'DAWID' -or [string]$data.attestation_scope -cne 'PROJECT_VOICE_PROFILE_ACTIVATION' -or -not(Test-SystemV7ConcreteText -Value ([string]$data.approval_note))){$errors.Add('VOICE_PROFILE_SELECTION_RECEIPT_CONTRACT_INVALID')}
        $selected=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$data.selected_at_utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$selected) -or $selected.UtcDateTime -gt [DateTime]::UtcNow.AddMinutes(5)){$errors.Add('VOICE_PROFILE_SELECTION_TIMESTAMP_INVALID')}
        $copy=[ordered]@{};foreach($property in $data.PSObject.Properties){if($property.Name -cne 'binding_sha256'){$copy[$property.Name]=$property.Value}}
        if((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)) -cne [string]$data.binding_sha256 -or (ConvertTo-SystemV7CanonicalJson -Value $data) -cne (ConvertTo-SystemV7LfText -Text $raw)){$errors.Add('VOICE_PROFILE_SELECTION_CANONICAL_BINDING_INVALID')}
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Data=$data;Path=$path;Sha256=$sha}
}

function Get-SystemV7DraftBlocks {
    param([Parameter(Mandatory)][string]$ActId, [Parameter(Mandatory)][string]$RawProse)
    if ($ActId -notmatch '^ACT-\d{3}$') { throw "ACT_ID_INVALID: $ActId" }
    $text = ConvertTo-SystemV7LfText -Text $RawProse
    $pattern = '(?ms)(?:^<!--\s*SOURCE_P_IDS:\s*(?<ids>[^>]+?)\s*-->\s*\n)?(?<prose>[^\n](?:.*?))(?=\n\s*\n|\z)'
    $blocks = [Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($match in [regex]::Matches($text.Trim(), $pattern)) {
        $prose = $match.Groups['prose'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($prose) -or $prose -match '^(?:PACKET_STATUS|SELF_CHECK):') { continue }
        if ($prose -match '<!--|-->|\bBLOCK-(?:ACT-)?\d') { throw 'MODEL_SUPPLIED_BLOCK_ID_OR_TECHNICAL_MARKUP' }
        $spokenState=Get-SystemV7PlainSpokenTextState -Text $prose;if(-not $spokenState.Valid){throw "MODEL_PROSE_NOT_PLAIN_SPOKEN_TEXT: $($spokenState.Errors -join ',')"}
        $wordCount = @([regex]::Matches($prose, "\b[\p{L}\p{N}][\p{L}\p{N}\p{M}’'-]*\b")).Count
        if ($wordCount -gt $script:SystemV7NarrativeBlockWordLimit) { throw "BLOCK_TRACE_GRANULARITY_EXCEEDED: words=$wordCount max=$script:SystemV7NarrativeBlockWordLimit" }
        $index++
        $blockId = 'BLOCK-{0}-{1:D3}' -f $ActId, $index
        $ids = @([regex]::Matches($match.Groups['ids'].Value, '#P-\d{3,}') | ForEach-Object Value | Select-Object -Unique)
        $blocks.Add([pscustomobject]@{ block_id=$blockId; block_sha256=(Get-SystemV7NarrativeSha256Text -Text ($prose + "`n")); word_count=$wordCount; source_p_ids=$ids; prose=$prose })
    }
    if ($blocks.Count -eq 0) { throw 'ACT_PROSE_EMPTY' }
    return @($blocks)
}

function Get-SystemV7PlainSpokenTextState {
    param([AllowEmptyString()][Parameter(Mandatory)][string]$Text)
    $errors=[Collections.Generic.List[string]]::new();$value=ConvertTo-SystemV7LfText -Text $Text
    $checks=[ordered]@{
        EMPTY='^\s*$'
        HEADING='(?m)^\s*#{1,6}\s+'
        CODE_FENCE='(?m)^\s*(?:```|~~~)'
        BLOCKQUOTE='(?m)^\s*>'
        LIST_MARKER='(?m)^\s*(?:[-+*]|\d+[.)])\s+'
        UNICODE_LIST_MARKER='(?m)^\s*[•◦▪▫‣⁃∙]\s+'
        HORIZONTAL_RULE='(?m)^\s*(?:-{3,}|\*{3,}|_{3,})\s*$'
        TABLE='(?m)^\s*\|.*\|\s*$'
        MARKDOWN_EMPHASIS='(?:\*\*|__|`)'
        MARKDOWN_SINGLE_EMPHASIS='(?<!\*)\*[^*\r\n]+\*(?!\*)|(?<!_)_[^_\r\n]+_(?!_)'
        MARKDOWN_LINK='!?\[[^\]\r\n]+\]\([^\)\r\n]+\)'
        HTML_OR_COMMENT='<!--|-->|<\/?[A-Za-z][^>]*>'
        STAGE_BRACKET='(?i)\[\s*(?:PAUZA|SFX|MUZYKA|DŹWIĘK|B-?ROLL|UJĘCIE|GRAFIKA|CISZA|LEKTOR|WESTCHNIENIE|ŚMIECH|ODDECH|MONTAŻ|MONTAZ|DIDASKALIA|INSTRUKCJA\s+(?:MONTAŻOWA|MONTAZOWA|WYKONAWCZA)|KARTA\s+WYMOWY|PRONUNCIATION|REŻYSERIA|REZYSERIA|NAPIS\s+NA\s+EKRANIE|PLANSZA|VOICE\s+OVER|VO)\b[^\]\r\n]*\]'
        BRACKET_ONLY_DIRECTION='(?m)^\s*\[[^\]\r\n]{2,80}\]\s*$'
        STAGE_PAREN='(?i)\(\s*(?:pauza|muzyka|dźwięk|sfx|cisza|ujęcie|grafika|b-?roll|śmieje\s+się|westchnienie|wzdycha|oddech|szeptem|głośniej|ciszej)\b[^\)\r\n]*\)'
        STAGE_KEY='(?i)(?<![\p{L}\p{N}_])(?:SFX|B-?ROLL|MUZYKA|DŹWIĘK|PAUZA|UJĘCIE|GRAFIKA|CISZA|LEKTOR|MONTAŻ|MONTAZ|DIDASKALIA|INSTRUKCJA\s+(?:MONTAŻOWA|MONTAZOWA|WYKONAWCZA)|KARTA\s+WYMOWY|PRONUNCIATION|REŻYSERIA|REZYSERIA|NAPIS\s+NA\s+EKRANIE|PLANSZA|VOICE\s+OVER|VO)\s*:'
        TECHNICAL_KEY='(?m)^\s*[A-ZĄĆĘŁŃÓŚŹŻ0-9]+(?:_[A-ZĄĆĘŁŃÓŚŹŻ0-9]+)+\s*:'
        TRACE_MARKER='(?i)#P-\d{3,}|\bBLOCK-(?:ACT-)?\d|PACKET_STATUS|SELF_CHECK|CONTINUITY_(?:IN|OUT)|K3_[A-Z_]+'
    }
    foreach($name in $checks.Keys){if([regex]::IsMatch($value,[string]$checks[$name])){$errors.Add("PLAIN_TEXT_$name")}}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors)}
}

function Assert-SystemV7PlainSpokenText {
    param([Parameter(Mandatory)][string]$Text,[string]$Context='NARRATION')
    $state=Get-SystemV7PlainSpokenTextState -Text $Text;if(-not $state.Valid){throw "${Context}_NOT_PLAIN_SPOKEN_TEXT: $($state.Errors -join ',')"};$state
}

function Get-SystemV7ActProseBindingState {
    param(
        [Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId,
        [Parameter(Mandatory)][string]$BlocksPath,
        [Parameter(Mandatory)][string]$ProsePath
    )
    $errors=[Collections.Generic.List[string]]::new()
    foreach($pair in @(@($BlocksPath,'BLOCKS'),@($ProsePath,'PROSE'))){if(-not(Test-Path -LiteralPath $pair[0] -PathType Leaf)){$errors.Add("ACT_PROSE_BINDING_$($pair[1])_MISSING")}}
    if($errors.Count -gt 0){return [pscustomobject]@{Valid=$false;Errors=@($errors)}}
    try{$blocks=Get-Content -LiteralPath $BlocksPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('ACT_PROSE_BINDING_BLOCKS_INVALID_JSON')}}
    $topFields=@('schema','act_id','run_id','prefix_sha256','model_id','model_revision','submission_sha256','blocks')
    if(@(Compare-Object -ReferenceObject $topFields -DifferenceObject @($blocks.PSObject.Properties.Name)).Count -gt 0 -or @($blocks.PSObject.Properties.Name).Count -ne $topFields.Count){$errors.Add('ACT_PROSE_BINDING_BLOCK_MAP_FIELDS_INVALID')}
    if([string]$blocks.schema -cne 'K3_ACT_BLOCKS_V1' -or [string]$blocks.act_id -cne $ActId){$errors.Add('ACT_PROSE_BINDING_BLOCK_MAP_IDENTITY_INVALID')}
    $parts=[Collections.Generic.List[string]]::new();$index=0
    foreach($block in @($blocks.blocks)){
        $index++;$expectedId='BLOCK-{0}-{1:D3}' -f $ActId,$index;$fields=@('block_id','block_sha256','word_count','trace_refs','sw_ids','source_p_ids','narrative_refs','prose')
        if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($block.PSObject.Properties.Name)).Count -gt 0 -or @($block.PSObject.Properties.Name).Count -ne $fields.Count){$errors.Add("ACT_PROSE_BINDING_BLOCK_FIELDS_INVALID: $expectedId");continue}
        $prose=(ConvertTo-SystemV7LfText -Text ([string]$block.prose)).Trim()
        if([string]$block.block_id -cne $expectedId){$errors.Add("ACT_PROSE_BINDING_BLOCK_ID_INVALID: $($block.block_id)")}
        $actualSha=Get-SystemV7NarrativeSha256Text -Text ($prose+"`n");if([string]$block.block_sha256 -cne $actualSha){$errors.Add("ACT_PROSE_BINDING_BLOCK_SHA_INVALID: $expectedId")}
        $words=@([regex]::Matches($prose,"\b[\p{L}\p{N}][\p{L}\p{N}\p{M}’'-]*\b")).Count;if([int]$block.word_count -ne $words -or $words -gt $script:SystemV7NarrativeBlockWordLimit){$errors.Add("ACT_PROSE_BINDING_WORD_COUNT_INVALID: $expectedId")}
        foreach($arrayField in @('trace_refs','sw_ids','source_p_ids','narrative_refs')){$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($value in @($block.$arrayField)){if(-not $seen.Add([string]$value)){$errors.Add("ACT_PROSE_BINDING_DUPLICATE_$($arrayField.ToUpperInvariant()): $expectedId/$value")}}}
        $swRaw=@([string[]]@($block.sw_ids));if($swRaw.Count -eq 0 -or @($swRaw|Where-Object{$_ -notmatch '^SW-\d{3}$'}).Count -gt 0){$errors.Add("ACT_PROSE_BINDING_SW_IDS_INVALID: $expectedId")}
        $sourceRaw=@([string[]]@($block.source_p_ids));$sourceUnique=@($sourceRaw|Sort-Object -Unique);if($sourceRaw.Count -eq 0 -or $sourceRaw.Count -ne $sourceUnique.Count -or @($sourceRaw|Where-Object{$_ -notmatch '^#P-\d{3,}$'}).Count -gt 0){$errors.Add("ACT_PROSE_BINDING_SOURCE_IDS_INVALID: $expectedId")}
        $spoken=Get-SystemV7PlainSpokenTextState -Text $prose;if(-not $spoken.Valid){$errors.Add("ACT_PROSE_BINDING_NOT_PLAIN: $expectedId/$($spoken.Errors -join ',')")}
        $parts.Add($prose)
    }
    if($parts.Count -eq 0){$errors.Add('ACT_PROSE_BINDING_EMPTY')}
    $expectedText=if($parts.Count -gt 0){($parts -join "`n`n")+"`n"}else{''}
    try{$bytes=[IO.File]::ReadAllBytes([IO.Path]::GetFullPath($ProsePath));$actualText=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}catch{$actualText='';$errors.Add('ACT_PROSE_BINDING_PROSE_NOT_STRICT_UTF8')}
    if($actualText -cne $expectedText){$errors.Add('ACT_PROSE_BINDING_PROSE_CONTENT_MISMATCH')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Blocks=$blocks;ExpectedProse=$expectedText;BlocksSha256=(Get-FileHash -LiteralPath $BlocksPath -Algorithm SHA256).Hash;ProseSha256=(Get-FileHash -LiteralPath $ProsePath -Algorithm SHA256).Hash;BlockCount=$parts.Count}
}

function Get-SystemV7CleanNarrationFromDraft {
    param([Parameter(Mandatory)][string]$DraftText)
    $match = [regex]::Match($DraftText, '(?ms)^##\s+NARRACJA ROBOCZA\s*\r?\n(?<body>.*)$')
    if (-not $match.Success) { throw 'DRAFT_NARRATION_SECTION_MISSING' }
    $body = ConvertTo-SystemV7LfText -Text $match.Groups['body'].Value
    $body = [regex]::Replace($body, '(?ms)<!--.*?-->', '')
    $body = [regex]::Replace($body, '(?m)^#{1,6}\s+.*$', '')
    $body = [regex]::Replace($body, '(?m)^\s*(?:BLOCK_ID|PREFIX_SHA256|K3_MODEL_|SOURCE_P_IDS):.*$', '')
    $body = [regex]::Replace($body, '\n{3,}', "`n`n").Trim()
    $null=Assert-SystemV7PlainSpokenText -Text $body -Context 'CLEAN_NARRATION'
    return $body + "`n"
}

function Get-SystemV7DurationState {
    param([Parameter(Mandatory)][string]$Narration, [Parameter(Mandatory)][int]$TargetMinutes, [Parameter(Mandatory)][int]$RealWpm, [Parameter(Mandatory)][ValidateSet('GUIDE','HARD_MAX')][string]$Mode)
    if ($TargetMinutes -lt 1 -or $RealWpm -lt 1) { throw 'DURATION_INPUT_INVALID' }
    $words = @([regex]::Matches($Narration, "\b[\p{L}\p{N}][\p{L}\p{N}\p{M}’'-]*\b")).Count
    $estimated = [math]::Round($words / [double]$RealWpm, 2)
    $maximumWords = $TargetMinutes * $RealWpm
    [pscustomobject]@{ Mode=$Mode; WordCount=$words; EstimatedMinutes=$estimated; TargetMinutes=$TargetMinutes; RealWpm=$RealWpm; MaximumWords=$maximumWords; Pass=($Mode -ceq 'GUIDE' -or $words -le $maximumWords); Alert=($Mode -ceq 'GUIDE' -and [math]::Abs($estimated-$TargetMinutes) -ge [math]::Max(2,$TargetMinutes*0.25)) }
}

function Get-SystemV7K3ModelManifestState {
    param([Parameter(Mandatory)][string]$ProjectPath,[string]$MetaText)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    if([string]::IsNullOrWhiteSpace($MetaText)){$metaPath=Join-Path $project 'meta.md';if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('MODEL_MANIFEST_META_MISSING');Data=$null}};$MetaText=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8}
    try{$relative=Get-SystemV7NarrativeMetaField -Text $MetaText -Name 'K3_MODEL_MANIFEST_PATH';$declaredSha=Get-SystemV7NarrativeMetaField -Text $MetaText -Name 'K3_MODEL_MANIFEST_SHA256'}catch{return [pscustomobject]@{Valid=$false;Errors=@($_.Exception.Message);Data=$null}}
    if($relative -ceq 'BRAK' -or $declaredSha -notmatch '^[A-Fa-f0-9]{64}$'){return [pscustomobject]@{Valid=$false;Errors=@('MODEL_MANIFEST_POINTER_MISSING');Data=$null}}
    try{$path=Join-Path $project $relative;$projectPrefix=$project.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;$full=[IO.Path]::GetFullPath($path);if(-not $full.StartsWith($projectPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'outside'}}catch{return [pscustomobject]@{Valid=$false;Errors=@('MODEL_MANIFEST_PATH_INVALID');Data=$null}}
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('MODEL_MANIFEST_MISSING');Data=$null;Path=$full}}
    $fileSha=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash;if($fileSha -cne $declaredSha.ToUpperInvariant()){$errors.Add('MODEL_MANIFEST_FILE_SHA_MISMATCH')}
    try{$data=Get-Content -LiteralPath $full -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32}catch{return [pscustomobject]@{Valid=$false;Errors=@('MODEL_MANIFEST_INVALID_JSON');Data=$null;Path=$full}}
    $expected=@('schema','workflow_revision','project_origin_sha256','model_id','model_revision','settings_relative','settings_sha256','created_at_utc','binding_sha256')
    if(@(Compare-Object -ReferenceObject $expected -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0 -or @($data.PSObject.Properties.Name).Count -ne $expected.Count){$errors.Add('MODEL_MANIFEST_FIELDS_INVALID')}
    if([string]$data.schema -cne 'K3_MODEL_MANIFEST_V1' -or [string]$data.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision){$errors.Add('MODEL_MANIFEST_SCHEMA_INVALID')}
    $copy=[ordered]@{};foreach($property in $data.PSObject.Properties){if($property.Name -cne 'binding_sha256'){$copy[$property.Name]=$property.Value}};if((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)) -cne [string]$data.binding_sha256){$errors.Add('MODEL_MANIFEST_BINDING_MISMATCH')}
    foreach($pair in @(@('model_id','K3_MODEL_ID'),@('model_revision','K3_MODEL_REVISION'),@('settings_sha256','K3_MODEL_SETTINGS_SHA256'))){if([string]$data.($pair[0]) -cne (Get-SystemV7NarrativeMetaField -Text $MetaText -Name $pair[1])){$errors.Add("MODEL_MANIFEST_META_MISMATCH: $($pair[1])")}}
    try{$settings=Join-Path $project ([string]$data.settings_relative);$settingsFull=[IO.Path]::GetFullPath($settings);if(-not $settingsFull.StartsWith($project.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'outside'}}catch{$settingsFull=$null;$errors.Add('MODEL_SETTINGS_PATH_INVALID')}
    if($settingsFull){if(-not(Test-Path -LiteralPath $settingsFull -PathType Leaf)){$errors.Add('MODEL_SETTINGS_SNAPSHOT_MISSING')}elseif((Get-FileHash -LiteralPath $settingsFull -Algorithm SHA256).Hash -cne [string]$data.settings_sha256){$errors.Add('MODEL_SETTINGS_SNAPSHOT_STALE')}}
    $origin=Get-SystemV7ProjectOriginState -ProjectPath $project;if(-not $origin.Valid -or [string]$origin.Sha256 -cne [string]$data.project_origin_sha256){$errors.Add('MODEL_MANIFEST_ORIGIN_MISMATCH')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Data=$data;Path=$full;Sha256=$fileSha;SettingsPath=$settingsFull}
}
