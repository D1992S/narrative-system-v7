. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Efficiency.ps1')

$script:SystemV7NarrativeRunTypes = @('GENERATE_ACT','CONSTRAINT_ATOMICITY_PREFLIGHT','BEAT_PREFLIGHT','CONTINUITY_ATTEST','EDITOR','VERIFY','COLD_READER','QA_IMPACT_REVIEW')
$script:SystemV7NarrativeInputProfiles = [ordered]@{
    GENERATE_ACT = [ordered]@{ name='K3_ACT_V2'; required=@('CORE','STORY_SPINE','VOICE_RULES','VOICE_EXEMPLARS','CONTINUITY_IN','EVIDENCE_SELECTION','ACT_PACKET','ACT_HARD_CONSTRAINTS','DO_NOT_REVEAL','WRITE_COMMAND') }
    CONSTRAINT_ATOMICITY_PREFLIGHT = [ordered]@{ name='CONSTRAINT_PREFLIGHT_V1'; required=@('ACT_PACKET','CONSTRAINT_LEDGER','ATOMICITY_SCHEMA') }
    BEAT_PREFLIGHT = [ordered]@{ name='BEAT_PREFLIGHT_V1'; required=@('ACT_PACKET','BEAT_SHEET','BEAT_SCHEMA') }
    CONTINUITY_ATTEST = [ordered]@{ name='CONTINUITY_BLIND_V1'; required=@('ACT_PROSE_BLOCKS','CONTINUITY_IN','CONTINUITY_OUT','CONTINUITY_SCHEMA') }
    EDITOR = [ordered]@{ name='EDITOR_V2'; required=@('FUNDAMENT','ARCHITECTURE','CLEAN_DRAFT','BLOCK_MAP','STORY_SPINE','NQ_NR_VC','VOICE_RULES','VOICE_EXEMPLARS','CONTINUITY_CHAIN','SEMANTIC_PREFLIGHT','EDITOR_CRITERIA','EDITOR_OUTPUT_SCHEMA'); optional=@('RUN_CONTEXT','RESPONSE_TEMPLATE') }
    VERIFY = [ordered]@{ name='VERIFY_SOURCE_FIRST_V1'; required=@('DRAFT_BLOCKS','EVIDENCE_BASE','SOURCE_FILES','SOURCE_LOCATORS','VERIFY_CRITERIA','VERIFY_OUTPUT_SCHEMA'); optional=@('RUN_CONTEXT','RESPONSE_TEMPLATE') }
    COLD_READER = [ordered]@{ name='COLD_READER_BLIND_V1'; required=@('CLEAN_NARRATION','COLD_READER_QUESTIONS','COLD_READER_OUTPUT_SCHEMA'); optional=@('RUN_CONTEXT','RESPONSE_TEMPLATE') }
    QA_IMPACT_REVIEW = [ordered]@{ name='QA_IMPACT_V1'; required=@('OLD_DRAFT','NEW_DRAFT','IMMUTABLE_DIFF','IMPACT_SCHEMA') }
}
$script:SystemV7NarrativePromptRevisions = [ordered]@{
    GENERATE_ACT='K3_ACT_V2';CONSTRAINT_ATOMICITY_PREFLIGHT='CONSTRAINT_PREFLIGHT_V1';BEAT_PREFLIGHT='BEAT_PREFLIGHT_V1';CONTINUITY_ATTEST='CONTINUITY_ATTEST_V1'
    EDITOR='EDITOR_V2';VERIFY='VERIFY_SOURCE_FIRST_V1';COLD_READER='COLD_READER_V1';QA_IMPACT_REVIEW='QA_IMPACT_V1'
}

function Get-SystemV7NarrativeRelativePath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $pathFull = [IO.Path]::GetFullPath($Path)
    $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $pathFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "PATH_OUTSIDE_PROJECT: $pathFull" }
    return $pathFull.Substring($prefix.Length).Replace('\','/')
}

function Get-SystemV7NarrativeCanonicalInputSourceState {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$RunType,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$SourcePath,
        [switch]$RequireLiveBinding
    )
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath);$systemRoot=Split-Path -Parent $PSScriptRoot
    try{$source=[IO.Path]::GetFullPath($SourcePath);$relative=Get-SystemV7NarrativeRelativePath -Root $project -Path $source}catch{return [pscustomobject]@{Valid=$false;Errors=@('CANONICAL_SOURCE_OUTSIDE_PROJECT');Relative=$null;ActId=$null}}
    $role=$Role.ToUpperInvariant();$key="$RunType/$role";$actId=$null
    $exact=@{
        'GENERATE_ACT/CORE'='_work/k3/prefix/K3_RULES_CORE.md';'GENERATE_ACT/STORY_SPINE'='_work/k3/prefix/PROJECT_STORY_SPINE.json';'GENERATE_ACT/VOICE_RULES'='_work/k3/prefix/VOICE_RULES.md';'GENERATE_ACT/VOICE_EXEMPLARS'='_work/k3/prefix/VOICE_EXEMPLARS.md'
        'EDITOR/FUNDAMENT'='00-fundament-projektu.md';'EDITOR/ARCHITECTURE'='02-architektura-odcinka.md';'EDITOR/STORY_SPINE'='_work/k3/prefix/PROJECT_STORY_SPINE.json';'EDITOR/VOICE_RULES'='_work/k3/prefix/VOICE_RULES.md';'EDITOR/VOICE_EXEMPLARS'='_work/k3/prefix/VOICE_EXEMPLARS.md'
        'VERIFY/DRAFT_BLOCKS'='03-draft.md';'VERIFY/EVIDENCE_BASE'='01-baza-dowodow.md';'VERIFY/SOURCE_FILES'='sources'
        'QA_IMPACT_REVIEW/NEW_DRAFT'='03-draft.md'
    }
    if($exact.ContainsKey($key)){
        if($relative -cne [string]$exact[$key]){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}
    }else{
        switch($key){
            {$_ -in @('EDITOR/RESPONSE_TEMPLATE','VERIFY/RESPONSE_TEMPLATE','COLD_READER/RESPONSE_TEMPLATE')} {
                if($relative -cnotmatch '^_work/narrative-runs/[A-Z0-9][A-Z0-9._-]{7,80}/inputs/RESPONSE_TEMPLATE\.md$'){$errors.Add('RESPONSE_TEMPLATE_PATH_INVALID')}
            }
            {$_ -in @('EDITOR/RUN_CONTEXT','VERIFY/RUN_CONTEXT','COLD_READER/RUN_CONTEXT')} {
                if($relative -cnotmatch '^_work/k4/inputs/run-context-(?<sha>[A-F0-9]{64})\.json$'){$errors.Add('K4_RUN_CONTEXT_PATH_INVALID')}
                elseif($RequireLiveBinding -and (Test-Path -LiteralPath $source -PathType Leaf)){
                    $expected=ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='K4_RUN_CONTEXT_V1';draft_sha256=[string]$Matches.sha})
                    if([IO.File]::ReadAllText($source) -cne $expected){$errors.Add('K4_RUN_CONTEXT_CONTENT_INVALID')}
                }elseif($RequireLiveBinding){$errors.Add('K4_RUN_CONTEXT_MISSING')}
            }
            'GENERATE_ACT/CONTINUITY_IN' {if($relative -cmatch '^_work/k3/continuity/(?<act>ACT-\d{3})\.in\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'GENERATE_ACT/EVIDENCE_SELECTION' {if($relative -cmatch '^_work/k3/packets/(?<act>ACT-\d{3})\.evidence-selection\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'GENERATE_ACT/ACT_PACKET' {if($relative -cmatch '^_work/k3/packets/(?<act>ACT-\d{3})\.act-packet\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'GENERATE_ACT/ACT_HARD_CONSTRAINTS' {if($relative -cmatch '^_work/k3/packets/(?<act>ACT-\d{3})\.constraint-ledger\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'GENERATE_ACT/DO_NOT_REVEAL' {if($relative -cmatch '^_work/k3/packets/(?<act>ACT-\d{3})\.do-not-reveal\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'GENERATE_ACT/WRITE_COMMAND' {if($relative -cmatch '^_work/k3/packets/(?<act>ACT-\d{3})\.write-command\.md$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'CONSTRAINT_ATOMICITY_PREFLIGHT/ACT_PACKET' {if($relative -cmatch '^_work/k3/packets/(?<act>ACT-\d{3})\.act-packet\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'CONSTRAINT_ATOMICITY_PREFLIGHT/CONSTRAINT_LEDGER' {if($relative -cmatch '^_work/k3/packets/(?<act>ACT-\d{3})\.constraint-ledger\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'BEAT_PREFLIGHT/ACT_PACKET' {if($relative -cnotmatch '^_work/narrative-runs/[A-Z0-9][A-Z0-9._-]{7,80}/inputs/ACT_PACKET\.json$'){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'BEAT_PREFLIGHT/BEAT_SHEET' {if($relative -cmatch '^_work/k3/beats/(?<act>ACT-\d{3})/beat-sheet\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'CONTINUITY_ATTEST/ACT_PROSE_BLOCKS' {if($relative -cmatch '^_work/k3/acts/(?<act>ACT-\d{3})/blocks\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'CONTINUITY_ATTEST/CONTINUITY_IN' {if($relative -cmatch '^_work/k3/continuity/(?<act>ACT-\d{3})\.in\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'CONTINUITY_ATTEST/CONTINUITY_OUT' {if($relative -cmatch '^_work/k3/acts/(?<act>ACT-\d{3})/out\.json$'){$actId=$Matches.act}else{$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'EDITOR/CLEAN_DRAFT' {if($relative -cnotmatch '^_work/k4/inputs/clean-narration-[A-F0-9]{64}\.md$'){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'EDITOR/BLOCK_MAP' {if($relative -cnotmatch '^_work/k4/inputs/block-map-[A-F0-9]{64}\.json$'){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'EDITOR/NQ_NR_VC' {if($relative -cnotmatch '^_work/k4/inputs/nq-nr-vc-[A-F0-9]{64}\.json$'){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'EDITOR/CONTINUITY_CHAIN' {if($relative -cnotmatch '^_work/k4/inputs/continuity-chain-[A-F0-9]{64}\.json$'){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'EDITOR/SEMANTIC_PREFLIGHT' {if($relative -cnotmatch '^_work/k4/inputs/semantic-preflight-[A-F0-9]{64}\.json$'){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'VERIFY/SOURCE_LOCATORS' {if($relative -cnotmatch '^_work/k4/inputs/source-locators-[A-F0-9]{64}\.json$'){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'QA_IMPACT_REVIEW/OLD_DRAFT' {if($relative -cnotmatch '^_work/k4/baselines/[A-F0-9]{64}\.md$'){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            'QA_IMPACT_REVIEW/IMMUTABLE_DIFF' {if($relative -cnotmatch '^_work/k4/impact/[A-F0-9]{64}\.impact\.json$'){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}}
            default {
                $systemRoleMap=@{
                    'CONSTRAINT_ATOMICITY_PREFLIGHT/ATOMICITY_SCHEMA'=@('_SYSTEM/NARRATIVE/CONSTRAINT-ATOMICITY-SCHEMA.md','^_work/k3/preflight-inputs/constraint-atomicity-schema-(?<sha>[A-F0-9]{64})\.md$')
                    'BEAT_PREFLIGHT/BEAT_SCHEMA'=@('_SYSTEM/NARRATIVE/BEAT-PREFLIGHT-SCHEMA.md','^_work/k3/preflight-inputs/beat-preflight-schema-(?<sha>[A-F0-9]{64})\.md$')
                    'CONTINUITY_ATTEST/CONTINUITY_SCHEMA'=@('_SYSTEM/NARRATIVE/CONTINUITY-SCHEMA.md','^_work/k3/attest-inputs/continuity-schema-(?<sha>[A-F0-9]{64})\.md$')
                    'EDITOR/EDITOR_CRITERIA'=@('_SYSTEM/NARRATIVE/EDITOR-CRITERIA.md','^_work/k4/inputs/editor-criteria-(?<sha>[A-F0-9]{64})\.md$')
                    'EDITOR/EDITOR_OUTPUT_SCHEMA'=@('_SYSTEM/NARRATIVE/EDITOR-OUTPUT-SCHEMA.md','^_work/k4/inputs/editor-output-schema-(?<sha>[A-F0-9]{64})\.md$')
                    'VERIFY/VERIFY_CRITERIA'=@('_SYSTEM/NARRATIVE/VERIFY-CRITERIA.md','^_work/k4/inputs/verify-criteria-(?<sha>[A-F0-9]{64})\.md$')
                    'VERIFY/VERIFY_OUTPUT_SCHEMA'=@('_SYSTEM/NARRATIVE/VERIFY-OUTPUT-SCHEMA.md','^_work/k4/inputs/verify-output-schema-(?<sha>[A-F0-9]{64})\.md$')
                    'COLD_READER/COLD_READER_QUESTIONS'=@('_SYSTEM/NARRATIVE/COLD-READER-QUESTIONS.md','^_work/k4/inputs/cold-reader-questions-(?<sha>[A-F0-9]{64})\.md$')
                    'COLD_READER/COLD_READER_OUTPUT_SCHEMA'=@('_SYSTEM/NARRATIVE/COLD-READER-OUTPUT-SCHEMA.md','^_work/k4/inputs/cold-reader-output-schema-(?<sha>[A-F0-9]{64})\.md$')
                    'COLD_READER/CLEAN_NARRATION'=@($null,'^_work/k4/inputs/clean-narration-[A-F0-9]{64}\.md$')
                    'QA_IMPACT_REVIEW/IMPACT_SCHEMA'=@('_SYSTEM/NARRATIVE/QA-IMPACT-SCHEMA.md','^_work/k4/inputs/qa-impact-schema-(?<sha>[A-F0-9]{64})\.md$')
                }
                if(-not $systemRoleMap.ContainsKey($key)){$errors.Add("CANONICAL_SOURCE_ROLE_UNSUPPORTED: $key")}
                else{
                    $spec=$systemRoleMap[$key];if($relative -cnotmatch [string]$spec[1]){$errors.Add("CANONICAL_SOURCE_PATH_MISMATCH: $key/$relative")}
                    elseif($spec[0] -and $RequireLiveBinding){$central=Join-Path $systemRoot ([string]$spec[0]);if(-not(Test-Path -LiteralPath $central -PathType Leaf)){$errors.Add("CANONICAL_SYSTEM_SOURCE_MISSING: $key")}else{$centralSha=(Get-FileHash -LiteralPath $central -Algorithm SHA256).Hash;if([string]$Matches.sha -cne $centralSha -or -not(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $centralSha){$errors.Add("CANONICAL_SYSTEM_SNAPSHOT_STALE: $key")}}}
                }
            }
        }
    }
    if($RequireLiveBinding -and $RunType -in @('EDITOR','VERIFY','COLD_READER')){
        $draftPath=Join-Path $project '03-draft.md'
        if(-not(Test-Path -LiteralPath $draftPath -PathType Leaf)){$errors.Add('CANONICAL_CURRENT_DRAFT_MISSING')}
        else{
            $draftSha=(Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash
            if($key -in @('EDITOR/CLEAN_DRAFT','EDITOR/BLOCK_MAP','EDITOR/NQ_NR_VC','EDITOR/CONTINUITY_CHAIN','EDITOR/SEMANTIC_PREFLIGHT','VERIFY/SOURCE_LOCATORS','COLD_READER/CLEAN_NARRATION','EDITOR/RUN_CONTEXT','VERIFY/RUN_CONTEXT','COLD_READER/RUN_CONTEXT') -and $relative -cnotmatch [regex]::Escape($draftSha)){$errors.Add("CANONICAL_DERIVED_DRAFT_BINDING_MISMATCH: $key")}
            if($key -in @('EDITOR/CLEAN_DRAFT','COLD_READER/CLEAN_NARRATION') -and (Test-Path -LiteralPath $source -PathType Leaf)){
                $expectedClean=Get-SystemV7CleanNarrationFromDraft -DraftText (Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8);$actualClean=Get-Content -LiteralPath $source -Raw -Encoding UTF8
                if((ConvertTo-SystemV7LfText -Text $actualClean) -cne (ConvertTo-SystemV7LfText -Text $expectedClean)){$errors.Add("CANONICAL_CLEAN_NARRATION_CONTENT_MISMATCH: $key")}
            }
        }
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Relative=$relative;ActId=$actId}
}

function Assert-SystemV7NarrativeRunCreationStage {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][string]$RunType)
    Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $ProjectPath | Out-Null
    $meta=Get-Content -LiteralPath (Join-Path $ProjectPath 'meta.md') -Raw -Encoding UTF8;$stage=Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE'
    $allowed=switch($RunType){
        'CONSTRAINT_ATOMICITY_PREFLIGHT' {@('K2B','K3')}
        {$_ -in @('GENERATE_ACT','BEAT_PREFLIGHT','CONTINUITY_ATTEST')} {@('K3')}
        {$_ -in @('EDITOR','VERIFY','COLD_READER')} {@('K4')}
        'QA_IMPACT_REVIEW' {@('K4','K5')}
        default {@()}
    }
    if($stage -notin $allowed){throw "RUN_CREATION_STAGE_INVALID: $RunType/$stage"}
}

function Get-SystemV7NarrativeReceiptBinding {
    param([Parameter(Mandatory)][object]$Record)
    $copy = [ordered]@{}
    foreach ($property in $Record.PSObject.Properties) {
        if ($property.Name -ceq 'binding_sha256') { continue }
        $copy[$property.Name] = $property.Value
    }
    return Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)
}

function Write-SystemV7NarrativeCreateNewJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value)
    $target = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $target) { throw "RECEIPT_ALREADY_EXISTS: $target" }
    $directory = Split-Path -Parent $target
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temp = Join-Path $directory ('.receipt-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temp, (ConvertTo-SystemV7CanonicalJson -Value $Value), [Text.UTF8Encoding]::new($false))
    try { [IO.File]::Move($temp, $target) }
    finally { if (Test-Path -LiteralPath $temp -PathType Leaf) { [IO.File]::Delete($temp) } }
    return $target
}

function New-SystemV7NarrativeInputBundle {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][ValidateSet('GENERATE_ACT','CONSTRAINT_ATOMICITY_PREFLIGHT','BEAT_PREFLIGHT','CONTINUITY_ATTEST','EDITOR','VERIFY','COLD_READER','QA_IMPACT_REVIEW')][string]$RunType,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][hashtable]$Inputs
    )
    if ($RunId -notmatch '^[A-Z0-9][A-Z0-9._-]{7,80}$') { throw 'RUN_ID_INVALID' }
    $project = [IO.Path]::GetFullPath($ProjectPath)
    Assert-SystemV7NarrativeRunCreationStage -ProjectPath $project -RunType $RunType
    $profile = $script:SystemV7NarrativeInputProfiles[$RunType]
    $required = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($role in @($profile.required)) { $null = $required.Add([string]$role) }
    $actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in $Inputs.Keys) {
        $role = ([string]$key).ToUpperInvariant()
        if (-not $required.Contains($role) -and $role -notin @($profile.optional)) { throw "CONTEXT_CONTAMINATION: $RunType does not allow $role" }
        if (-not $actual.Add($role)) { throw "INPUT_ROLE_DUPLICATE: $role" }
    }
    $missing = @($required | Where-Object { -not $actual.Contains($_) })
    if ($missing.Count -gt 0) { throw "INPUT_PROFILE_INCOMPLETE: $($missing -join ',')" }

    $canonicalActs=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($key in $Inputs.Keys){
        $role=([string]$key).ToUpperInvariant();$canonical=Get-SystemV7NarrativeCanonicalInputSourceState -ProjectPath $project -RunType $RunType -Role $role -SourcePath ([string]$Inputs[$key]) -RequireLiveBinding
        if(-not $canonical.Valid){throw "NONCANONICAL_INPUT_SOURCE: $($canonical.Errors -join '; ')"}
        if($canonical.ActId){$null=$canonicalActs.Add([string]$canonical.ActId)}
    }
    if($canonicalActs.Count -gt 1){throw "INPUT_ACT_ID_MIXED: $($canonicalActs -join ',')"}

    $bundleRoot = Join-Path $project ("_work\narrative-runs\$RunId\inputs")
    $runRoot=Split-Path -Parent $bundleRoot;$runParent=Split-Path -Parent $runRoot
    $null=Assert-SystemV7PathNoReparse -Path $runParent -ContainmentRoot $project;$null=Assert-SystemV7PathNoReparse -Path $runRoot -ContainmentRoot $project
    if (Test-Path -LiteralPath $runRoot) { throw "RUN_BUNDLE_ALREADY_EXISTS: $RunId" }
    [IO.Directory]::CreateDirectory($bundleRoot) | Out-Null
    $null=Assert-SystemV7PathNoReparse -Path $bundleRoot -ContainmentRoot $project
    $entries = [Collections.Generic.List[object]]::new()
    try {
        $roles = [string[]]@($actual)
        [Array]::Sort($roles, [StringComparer]::Ordinal)
        foreach ($role in $roles) {
            $source = [IO.Path]::GetFullPath([string]$Inputs[$role])
            $null=Assert-SystemV7PathNoReparse -Path $source -ContainmentRoot $project
            if (Test-Path -LiteralPath $source -PathType Leaf) {
                $extension = [IO.Path]::GetExtension($source)
                if ([string]::IsNullOrWhiteSpace($extension)) { $extension = '.txt' }
                $bundleName = $role + $extension.ToLowerInvariant()
                $destination = Join-Path $bundleRoot $bundleName
                [IO.File]::Copy($source, $destination, $false)
                $entries.Add([ordered]@{
                    scope = 'BUNDLE_COPY'; content_role = $role; kind='FILE'
                    source_relative = Get-SystemV7NarrativeRelativePath -Root $project -Path $source
                    bundle_relative = Get-SystemV7NarrativeRelativePath -Root $project -Path $destination
                    sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
                    bytes = (Get-Item -LiteralPath $destination).Length
                    files = @()
                })
            } elseif (Test-Path -LiteralPath $source -PathType Container) {
                $null=Assert-SystemV7TreeNoReparse -RootPath $source -ContainmentRoot $project
                $destination = Join-Path $bundleRoot $role
                [IO.Directory]::CreateDirectory($destination) | Out-Null
                $fileRecords=[Collections.Generic.List[object]]::new();$totalBytes=[int64]0
                $sourcePrefix=$source.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
                $sourceFilePaths = [string[]]@(Get-ChildItem -LiteralPath $source -File -Recurse -Force | ForEach-Object { $_.FullName })
                [Array]::Sort($sourceFilePaths, [StringComparer]::Ordinal)
                foreach($sourceFilePath in $sourceFilePaths){
                    $sourceFile = Get-Item -LiteralPath $sourceFilePath -Force
                    $relative=$sourceFile.FullName.Substring($sourcePrefix.Length).Replace('\','/')
                    if($relative -match '(^|/)(?:__pycache__|\.git)(/|$)'){continue}
                    $targetFile=Join-Path $destination $relative;[IO.Directory]::CreateDirectory((Split-Path -Parent $targetFile))|Out-Null;[IO.File]::Copy($sourceFile.FullName,$targetFile,$false)
                    $bytes=(Get-Item -LiteralPath $targetFile).Length;$totalBytes+=$bytes
                    $fileRecords.Add([ordered]@{relative=$relative;sha256=(Get-FileHash -LiteralPath $targetFile -Algorithm SHA256).Hash;bytes=$bytes})
                }
                $directorySha=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($fileRecords))
                $entries.Add([ordered]@{
                    scope='BUNDLE_COPY';content_role=$role;kind='DIRECTORY';source_relative=Get-SystemV7NarrativeRelativePath -Root $project -Path $source
                    bundle_relative=Get-SystemV7NarrativeRelativePath -Root $project -Path $destination;sha256=$directorySha;bytes=$totalBytes;files=@($fileRecords)
                })
            } else { throw "INPUT_PATH_MISSING: $role/$source" }
        }
        if($RunType -in @('EDITOR','VERIFY','COLD_READER') -and $actual.Contains('RUN_CONTEXT') -and -not $actual.Contains('RESPONSE_TEMPLATE')){
            $template=Get-SystemV7K4ResponseTemplate -ProjectPath $project -BundleData ([pscustomobject]@{run_type=$RunType;entries=@($entries)})
            $destination=Join-Path $bundleRoot 'RESPONSE_TEMPLATE.md'
            [IO.File]::WriteAllText($destination,$template,[Text.UTF8Encoding]::new($false))
            $relative=Get-SystemV7NarrativeRelativePath -Root $project -Path $destination
            $entries.Add([ordered]@{scope='BUNDLE_COPY';content_role='RESPONSE_TEMPLATE';kind='FILE';source_relative=$relative;bundle_relative=$relative;sha256=(Get-FileHash -LiteralPath $destination).Hash;bytes=(Get-Item -LiteralPath $destination).Length;files=@()})
        }
        $manifestCore = [ordered]@{
            schema = 'SYSTEM_V7_NARRATIVE_INPUT_BUNDLE_V1'
            workflow_revision = $script:SystemV7NarrativeWorkflowRevision
            run_type = $RunType
            run_id = $RunId
            input_profile = [string]$profile.name
            entries = @($entries)
        }
        $manifestSha = Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $manifestCore)
        $manifest = [ordered]@{}
        foreach ($key in $manifestCore.Keys) { $manifest[$key] = $manifestCore[$key] }
        $manifest['input_manifest_sha256'] = $manifestSha
        $manifestPath = Join-Path (Split-Path -Parent $bundleRoot) 'input-manifest.json'
        Write-SystemV7NarrativeCreateNewJson -Path $manifestPath -Value $manifest | Out-Null
        [pscustomobject]@{ Path=$manifestPath; Sha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash; InputManifestSha256=$manifestSha; Profile=$profile.name; Entries=@($entries) }
    } catch {
        if ((Get-SystemV7NarrativeRelativePath -Root $project -Path $runRoot) -ceq "_work/narrative-runs/$RunId" -and (Test-Path -LiteralPath $runRoot -PathType Container)) {$null=Assert-SystemV7TreeNoReparse -RootPath $runRoot -ContainmentRoot $project;[IO.Directory]::Delete($runRoot, $true) }
        throw
    }
}

function Get-SystemV7NarrativeInputBundleState {
    param([Parameter(Mandatory)][string]$ProjectPath, [Parameter(Mandatory)][string]$ManifestPath,[switch]$RequireLiveSource)
    $errors = [Collections.Generic.List[string]]::new()
    $project = [IO.Path]::GetFullPath($ProjectPath)
    try { $manifestFull = [IO.Path]::GetFullPath($ManifestPath); $null = Get-SystemV7NarrativeRelativePath -Root $project -Path $manifestFull }
    catch { return [pscustomobject]@{ Valid=$false; Errors=@($_.Exception.Message); Data=$null } }
    if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) { return [pscustomobject]@{ Valid=$false; Errors=@('INPUT_MANIFEST_MISSING'); Data=$null } }
    try{$null=Assert-SystemV7TreeNoReparse -RootPath (Split-Path -Parent $manifestFull) -ContainmentRoot $project}catch{return [pscustomobject]@{Valid=$false;Errors=@('INPUT_BUNDLE_REPARSE_BLOCKED');Data=$null}}
    try { $data = Get-Content -LiteralPath $manifestFull -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 32 }
    catch { return [pscustomobject]@{ Valid=$false; Errors=@('INPUT_MANIFEST_INVALID_JSON'); Data=$null } }
    $expectedFields = @('schema','workflow_revision','run_type','run_id','input_profile','entries','input_manifest_sha256')
    if (@(Compare-Object -ReferenceObject $expectedFields -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0 -or @($data.PSObject.Properties.Name).Count -ne $expectedFields.Count) { $errors.Add('INPUT_MANIFEST_FIELDS_INVALID') }
    if ([string]$data.schema -cne 'SYSTEM_V7_NARRATIVE_INPUT_BUNDLE_V1' -or [string]$data.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision) { $errors.Add('INPUT_MANIFEST_SCHEMA_INVALID') }
    if ([string]$data.run_type -notin $script:SystemV7NarrativeRunTypes) { $errors.Add('INPUT_MANIFEST_RUN_TYPE_INVALID') }
    $expectedManifestRelative="_work/narrative-runs/$([string]$data.run_id)/input-manifest.json"
    try{$actualManifestRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $manifestFull;if($actualManifestRelative -cne $expectedManifestRelative){$errors.Add('INPUT_MANIFEST_NONCANONICAL_PATH')}}catch{$errors.Add('INPUT_MANIFEST_NONCANONICAL_PATH')}
    $profile = $script:SystemV7NarrativeInputProfiles[[string]$data.run_type]
    if ($null -eq $profile -or [string]$data.input_profile -cne [string]$profile.name) { $errors.Add('INPUT_PROFILE_INVALID') }
    $roles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$canonicalActs=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($data.entries)) {
        $entryFields=@('scope','content_role','kind','source_relative','bundle_relative','sha256','bytes','files')
        if(@(Compare-Object -ReferenceObject $entryFields -DifferenceObject @($entry.PSObject.Properties.Name)).Count -gt 0 -or @($entry.PSObject.Properties.Name).Count -ne $entryFields.Count){$errors.Add('INPUT_ENTRY_FIELDS_INVALID')}
        $role = [string]$entry.content_role
        if([string]$entry.scope -cne 'BUNDLE_COPY' -or $role -cne $role.ToUpperInvariant() -or [string]$entry.sha256 -notmatch '^[A-F0-9]{64}$' -or [int64]$entry.bytes -lt 0){$errors.Add("INPUT_ENTRY_IDENTITY_INVALID: $role")}
        if (-not $roles.Add($role)) { $errors.Add("INPUT_ROLE_DUPLICATE: $role") }
        if ($null -ne $profile -and $role -notin (@($profile.required)+@($profile.optional))) { $errors.Add("CONTEXT_CONTAMINATION: $role") }
        $source=$null
        try{$source=Join-Path $project ([string]$entry.source_relative);$canonical=Get-SystemV7NarrativeCanonicalInputSourceState -ProjectPath $project -RunType ([string]$data.run_type) -Role $role -SourcePath $source -RequireLiveBinding:$RequireLiveSource;if(-not $canonical.Valid){foreach($problem in $canonical.Errors){$errors.Add([string]$problem)}}elseif($canonical.ActId){$null=$canonicalActs.Add([string]$canonical.ActId)}}catch{$errors.Add("INPUT_SOURCE_PATH_INVALID: $role")}
        try { $path = Join-Path $project ([string]$entry.bundle_relative); $null=Get-SystemV7NarrativeRelativePath -Root $project -Path $path }
        catch { $errors.Add("INPUT_BUNDLE_PATH_INVALID: $role"); continue }
        $bundleRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $path;$bundlePrefix="_work/narrative-runs/$([string]$data.run_id)/inputs/"
        if([string]$entry.kind -ceq 'DIRECTORY'){if($bundleRelative -cne ($bundlePrefix+$role)){$errors.Add("INPUT_BUNDLE_NONCANONICAL_PATH: $role")}}
        elseif($bundleRelative -cnotmatch ('^'+[regex]::Escape($bundlePrefix+$role)+'\.[a-z0-9]+$')){$errors.Add("INPUT_BUNDLE_NONCANONICAL_PATH: $role")}
        if([string]$entry.kind -ceq 'FILE'){
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("INPUT_BUNDLE_FILE_MISSING: $role"); continue }
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne [string]$entry.sha256) { $errors.Add("INPUT_BUNDLE_HASH_MISMATCH: $role") }
            if ((Get-Item -LiteralPath $path).Length -ne [int64]$entry.bytes) { $errors.Add("INPUT_BUNDLE_SIZE_MISMATCH: $role") }
            if($RequireLiveSource -and (-not $source -or -not(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne [string]$entry.sha256 -or (Get-Item -LiteralPath $source).Length -ne [int64]$entry.bytes)){$errors.Add("INPUT_SOURCE_STALE: $role")}
        }elseif([string]$entry.kind -ceq 'DIRECTORY'){
            if(-not(Test-Path -LiteralPath $path -PathType Container)){$errors.Add("INPUT_BUNDLE_DIRECTORY_MISSING: $role");continue}
            $actual=[Collections.Generic.List[object]]::new();$total=[int64]0
            $declaredFiles=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($fileRecord in @($entry.files)){
                if(-not $declaredFiles.Add([string]$fileRecord.relative)){$errors.Add("INPUT_DIRECTORY_DUPLICATE_FILE: $role/$($fileRecord.relative)");continue}
                $filePath=Join-Path $path ([string]$fileRecord.relative)
                try{$null=Get-SystemV7NarrativeRelativePath -Root $path -Path $filePath}catch{$errors.Add("INPUT_DIRECTORY_PATH_INVALID: $role/$($fileRecord.relative)");continue}
                if(-not(Test-Path -LiteralPath $filePath -PathType Leaf)){$errors.Add("INPUT_DIRECTORY_FILE_MISSING: $role/$($fileRecord.relative)");continue}
                $bytes=(Get-Item -LiteralPath $filePath).Length;$total+=$bytes;$sha=(Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
                if($bytes -ne [int64]$fileRecord.bytes -or $sha -cne [string]$fileRecord.sha256){$errors.Add("INPUT_DIRECTORY_FILE_STALE: $role/$($fileRecord.relative)")}
                $actual.Add([ordered]@{relative=[string]$fileRecord.relative;sha256=$sha;bytes=$bytes})
            }
            $pathPrefix=[IO.Path]::GetFullPath($path).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
            $actualFilePaths=[string[]]@(Get-ChildItem -LiteralPath $path -File -Recurse -Force | ForEach-Object { $_.FullName })
            [Array]::Sort($actualFilePaths,[StringComparer]::Ordinal)
            foreach($actualFilePath in $actualFilePaths){
                $actualRelative=$actualFilePath.Substring($pathPrefix.Length).Replace('\','/')
                if(-not $declaredFiles.Contains($actualRelative)){$errors.Add("INPUT_DIRECTORY_UNDECLARED_FILE: $role/$actualRelative")}
            }
            if($actualFilePaths.Count -ne $declaredFiles.Count){$errors.Add("INPUT_DIRECTORY_FILE_COUNT_MISMATCH: $role")}
            if($total -ne [int64]$entry.bytes -or (Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($actual))) -cne [string]$entry.sha256){$errors.Add("INPUT_DIRECTORY_BINDING_MISMATCH: $role")}
            if($RequireLiveSource -and (-not $source -or -not(Test-Path -LiteralPath $source -PathType Container))){$errors.Add("INPUT_SOURCE_STALE: $role")}
            elseif($RequireLiveSource){
                $sourcePrefix=[IO.Path]::GetFullPath($source).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;$sourceRecords=[Collections.Generic.List[object]]::new();$sourceTotal=[int64]0
                $sourceFiles=[string[]]@(Get-ChildItem -LiteralPath $source -File -Recurse -Force|ForEach-Object{$_.FullName});[Array]::Sort($sourceFiles,[StringComparer]::Ordinal)
                foreach($sourceFile in $sourceFiles){$sourceRelative=$sourceFile.Substring($sourcePrefix.Length).Replace('\','/');if($sourceRelative -match '(^|/)(?:__pycache__|\.git)(/|$)'){continue};$sourceBytes=(Get-Item -LiteralPath $sourceFile).Length;$sourceTotal+=$sourceBytes;$sourceRecords.Add([ordered]@{relative=$sourceRelative;sha256=(Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash;bytes=$sourceBytes})}
                if($sourceTotal -ne [int64]$entry.bytes -or (Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($sourceRecords))) -cne [string]$entry.sha256){$errors.Add("INPUT_SOURCE_STALE: $role")}
            }
        }else{$errors.Add("INPUT_KIND_INVALID: $role")}
    }
    if($roles.Contains('RUN_CONTEXT') -and [string]$data.run_type -in @('EDITOR','VERIFY','COLD_READER')){
        try{
            $identity=Get-SystemV7K4BundleDraftIdentityState -Lens ([string]$data.run_type) -BundleData $data
            if(-not $identity.Valid){throw 'identity'}
            $entry=@($data.entries|Where-Object content_role -CEQ 'RUN_CONTEXT')[0]
            $expected=ConvertTo-SystemV7CanonicalJson -Value ([ordered]@{schema='K4_RUN_CONTEXT_V1';draft_sha256=$identity.Sha256})
            if([IO.File]::ReadAllText((Join-Path $project $entry.bundle_relative)) -cne $expected){throw 'content'}
        }catch{$errors.Add('K4_RUN_CONTEXT_BINDING_INVALID')}
    }
    if($roles.Contains('RESPONSE_TEMPLATE')){
        try{
            $entry=@($data.entries|Where-Object content_role -CEQ 'RESPONSE_TEMPLATE')[0]
            $expected=Get-SystemV7K4ResponseTemplate -ProjectPath $project -BundleData $data
            if([IO.File]::ReadAllText((Join-Path $project $entry.bundle_relative)) -cne $expected){throw 'content'}
        }catch{$errors.Add('RESPONSE_TEMPLATE_BINDING_INVALID')}
    }
    if($canonicalActs.Count -gt 1){$errors.Add('INPUT_ACT_ID_MIXED')}
    if ($null -ne $profile) { foreach ($required in @($profile.required)) { if (-not $roles.Contains([string]$required)) { $errors.Add("INPUT_PROFILE_INCOMPLETE: $required") } } }
    $core = [ordered]@{ schema=$data.schema; workflow_revision=$data.workflow_revision; run_type=$data.run_type; run_id=$data.run_id; input_profile=$data.input_profile; entries=@($data.entries) }
    if ((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $core)) -cne [string]$data.input_manifest_sha256) { $errors.Add('INPUT_MANIFEST_BINDING_MISMATCH') }
    [pscustomobject]@{ Valid=$errors.Count -eq 0; Errors=@($errors); Data=$data; Path=$manifestFull; FileSha256=(Get-FileHash -LiteralPath $manifestFull -Algorithm SHA256).Hash }
}

function Get-SystemV7NarrativeExpectedRunOutputPath {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][object]$BundleData)
    $project=[IO.Path]::GetFullPath($ProjectPath);$runType=[string]$BundleData.run_type;$runId=[string]$BundleData.run_id
    $extension=if($runType -ceq 'GENERATE_ACT'){'.json'}else{'.md'}
    return Join-Path $project "_work\narrative-runs\$runId\output$extension"
}

function Get-SystemV7ConstraintPreflightOutputState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][object]$BundleData)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    try{$output=[IO.Path]::GetFullPath($OutputPath);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $output}catch{return [pscustomobject]@{Valid=$false;Errors=@('CONSTRAINT_PREFLIGHT_OUTPUT_PATH_INVALID')}}
    if(-not(Test-Path -LiteralPath $output -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('CONSTRAINT_PREFLIGHT_OUTPUT_MISSING')}}
    $packetEntry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PACKET'});$ledgerEntry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq 'CONSTRAINT_LEDGER'})
    if($packetEntry.Count -ne 1 -or $ledgerEntry.Count -ne 1){return [pscustomobject]@{Valid=$false;Errors=@('CONSTRAINT_PREFLIGHT_BUNDLE_ROLES_INVALID')}}
    try{$packet=Get-Content -LiteralPath (Join-Path $project ([string]$packetEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$ledger=Get-Content -LiteralPath (Join-Path $project ([string]$ledgerEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('CONSTRAINT_PREFLIGHT_BUNDLE_JSON_INVALID')}}
    $ledgerFields=@('schema','act_id','max_total','actual_total','constraints');if(@(Compare-Object -ReferenceObject $ledgerFields -DifferenceObject @($ledger.PSObject.Properties.Name)).Count -gt 0 -or @($ledger.PSObject.Properties.Name).Count -ne $ledgerFields.Count -or [string]$ledger.schema -cne 'CONSTRAINT_LEDGER_V1' -or [string]$ledger.act_id -cne [string]$packet.act_id -or [int]$ledger.max_total -ne 7 -or [int]$ledger.actual_total -ne @($ledger.constraints).Count -or [int]$ledger.actual_total -gt 7){$errors.Add('CONSTRAINT_PREFLIGHT_LEDGER_INVALID')}
    $atomicity=Get-SystemV7ConstraintAtomicityState -Packet $packet -Ledger $ledger
    if(-not $atomicity.Valid){foreach($problem in @($atomicity.Errors)){$errors.Add("CONSTRAINT_PREFLIGHT_DETERMINISTIC_FAIL: $problem")}}
    $text=(ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $output -Raw -Encoding UTF8)).Trim();$lines=@($text -split "`n")
    $names=@('VERDICT','UNBUNDLED_CONSTRAINT_COUNT','MISSING_ACTIONS','BUNDLED_ACTIONS','CONFLICTS','REASON');if($lines.Count -ne $names.Count){$errors.Add('CONSTRAINT_PREFLIGHT_OUTPUT_LINE_COUNT_INVALID')}
    $values=@{};for($i=0;$i -lt [math]::Min($lines.Count,$names.Count);$i++){$m=[regex]::Match($lines[$i],"^$($names[$i]):\s*(.*?)\s*$");if(-not $m.Success){$errors.Add("CONSTRAINT_PREFLIGHT_OUTPUT_FIELD_INVALID: $($names[$i])")}else{$values[$names[$i]]=$m.Groups[1].Value}}
    $declaredUnbundled=0
    if(-not[int]::TryParse([string]$values.UNBUNDLED_CONSTRAINT_COUNT,[ref]$declaredUnbundled) -or $declaredUnbundled -ne [int]$atomicity.UnbundledConstraintCount){$errors.Add('CONSTRAINT_PREFLIGHT_UNBUNDLED_COUNT_MISMATCH')}
    if([string]$values.VERDICT -cne 'PASS' -or [string]$values.MISSING_ACTIONS -cne 'BRAK' -or [string]$values.BUNDLED_ACTIONS -cne 'BRAK' -or [string]$values.CONFLICTS -cne 'BRAK'){$errors.Add('CONSTRAINT_PREFLIGHT_OUTPUT_NOT_PASS')}
    if(-not(Test-SystemV7ConcreteText -Value ([string]$values.REASON))){$errors.Add('CONSTRAINT_PREFLIGHT_REASON_NOT_CONCRETE')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);ActId=[string]$packet.act_id;Packet=$packet;Ledger=$ledger;Path=$output;Sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
}

function Get-SystemV7BeatPreflightOutputState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][object]$BundleData)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    try{$output=[IO.Path]::GetFullPath($OutputPath);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $output}catch{return [pscustomobject]@{Valid=$false;Errors=@('BEAT_PREFLIGHT_OUTPUT_PATH_INVALID')}}
    if(-not(Test-Path -LiteralPath $output -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('BEAT_PREFLIGHT_OUTPUT_MISSING')}}
    $packetEntry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PACKET'});$beatEntry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq 'BEAT_SHEET'})
    if($packetEntry.Count -ne 1 -or $beatEntry.Count -ne 1){return [pscustomobject]@{Valid=$false;Errors=@('BEAT_PREFLIGHT_BUNDLE_ROLES_INVALID')}}
    try{$packet=Get-Content -LiteralPath (Join-Path $project ([string]$packetEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$beat=Get-Content -LiteralPath (Join-Path $project ([string]$beatEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('BEAT_PREFLIGHT_BUNDLE_JSON_INVALID')}}
    $semantic=Get-SystemV7BeatSheetSemanticState -Packet $packet -BeatSheet $beat -ActId ([string]$packet.act_id) -ExpectedGenerateRunId ([string]$beat.generate_run_id);if(-not $semantic.Valid){foreach($problem in $semantic.Errors){$errors.Add("BEAT_PREFLIGHT_BUNDLE_CONTENT_INVALID: $problem")}}
    $text=(ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $output -Raw -Encoding UTF8)).Trim();$lines=@($text -split "`n")
    $names=@('VERDICT','ACT_ID','SCHEMA_CHECK','IDENTIFIER_CHECK','STATE_TRANSITION_CHECK','NO_ADDED_SOURCE_OR_REVEAL','DISCREPANCIES','REASON');if($lines.Count -ne $names.Count){$errors.Add('BEAT_PREFLIGHT_OUTPUT_LINE_COUNT_INVALID')}
    $values=@{};for($i=0;$i -lt [math]::Min($lines.Count,$names.Count);$i++){$m=[regex]::Match($lines[$i],"^$($names[$i]):\s*(.*?)\s*$");if(-not $m.Success){$errors.Add("BEAT_PREFLIGHT_OUTPUT_FIELD_INVALID: $($names[$i])")}else{$values[$names[$i]]=$m.Groups[1].Value}}
    foreach($name in @('VERDICT','SCHEMA_CHECK','IDENTIFIER_CHECK','STATE_TRANSITION_CHECK','NO_ADDED_SOURCE_OR_REVEAL')){if([string]$values[$name] -cne 'PASS'){$errors.Add("BEAT_PREFLIGHT_OUTPUT_NOT_PASS: $name")}}
    if([string]$values.ACT_ID -cne [string]$packet.act_id -or [string]$values.DISCREPANCIES -cne 'BRAK'){$errors.Add('BEAT_PREFLIGHT_OUTPUT_ACT_OR_DISCREPANCIES_INVALID')}
    if(-not(Test-SystemV7ConcreteText -Value ([string]$values.REASON))){$errors.Add('BEAT_PREFLIGHT_REASON_NOT_CONCRETE')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);ActId=[string]$packet.act_id;Packet=$packet;Beat=$beat;Path=$output;Sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
}

function Get-SystemV7ContinuityAttestOutputState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][object]$BundleData)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    try{$output=[IO.Path]::GetFullPath($OutputPath);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $output}catch{return [pscustomobject]@{Valid=$false;Errors=@('CONTINUITY_ATTEST_OUTPUT_PATH_INVALID')}}
    if(-not(Test-Path -LiteralPath $output -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('CONTINUITY_ATTEST_OUTPUT_MISSING')}}
    $blocksEntry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq 'ACT_PROSE_BLOCKS'});$outEntry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq 'CONTINUITY_OUT'})
    if($blocksEntry.Count -ne 1 -or $outEntry.Count -ne 1){return [pscustomobject]@{Valid=$false;Errors=@('CONTINUITY_ATTEST_BUNDLE_ROLES_INVALID')}}
    try{$blocks=Get-Content -LiteralPath (Join-Path $project ([string]$blocksEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$continuityOut=Get-Content -LiteralPath (Join-Path $project ([string]$outEntry[0].bundle_relative)) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$raw=Get-Content -LiteralPath $output -Raw -Encoding UTF8;$result=$raw|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('CONTINUITY_ATTEST_OUTPUT_OR_BUNDLE_JSON_INVALID')}}
    if((ConvertTo-SystemV7CanonicalJson -Value $result) -cne (ConvertTo-SystemV7LfText -Text $raw)){$errors.Add('CONTINUITY_ATTEST_OUTPUT_NOT_CANONICAL_JSON')}
    $fields=@('schema','act_id','verdict','record_results','missing_state_change','question_arithmetic_verdict','reason');if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($result.PSObject.Properties.Name)).Count -gt 0 -or @($result.PSObject.Properties.Name).Count -ne $fields.Count){$errors.Add('CONTINUITY_ATTEST_RESULT_FIELDS_INVALID')}
    if([string]$result.schema -cne 'CONTINUITY_ATTEST_RESULT_V1' -or [string]$result.act_id -cne [string]$continuityOut.act_id -or [string]$result.verdict -cne 'PASS' -or $result.missing_state_change -cne $false -or [string]$result.question_arithmetic_verdict -cne 'PASS'){$errors.Add('CONTINUITY_ATTEST_RESULT_NOT_PASS')}
    if(-not(Test-SystemV7ConcreteText -Value ([string]$result.reason))){$errors.Add('CONTINUITY_ATTEST_REASON_NOT_CONCRETE')}
    $stateIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($record in @($continuityOut.records)){if([string]$record.state_id -notmatch '^STATE-\d{3}$' -or -not $stateIds.Add([string]$record.state_id)){$errors.Add("CONTINUITY_ATTEST_INPUT_STATE_ID_INVALID: $($record.state_id)")}}
    foreach($record in @($continuityOut.character_and_world_state)){if([string]$record.world_state_id -notmatch '^WORLD-\d{3}$' -or -not $stateIds.Add([string]$record.world_state_id)){$errors.Add("CONTINUITY_ATTEST_INPUT_WORLD_STATE_ID_INVALID: $($record.world_state_id)")}}
    foreach($record in @($continuityOut.uncertainties_preserved)){if([string]$record.uncertainty_id -notmatch '^UNCERTAINTY-\d{3}$' -or -not $stateIds.Add([string]$record.uncertainty_id)){$errors.Add("CONTINUITY_ATTEST_INPUT_UNCERTAINTY_ID_INVALID: $($record.uncertainty_id)")}}
    foreach($special in @('BRIDGE','OPENING_MOVE','CLOSING_MOVE')){if(-not $stateIds.Add($special)){$errors.Add("CONTINUITY_ATTEST_SPECIAL_STATE_ID_COLLISION: $special")}}
    $resultIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($recordResult in @($result.record_results)){$recordFields=@('state_id','verdict','reason');$sid=[string]$recordResult.state_id;if(@(Compare-Object -ReferenceObject $recordFields -DifferenceObject @($recordResult.PSObject.Properties.Name)).Count -gt 0 -or @($recordResult.PSObject.Properties.Name).Count -ne $recordFields.Count){$errors.Add("CONTINUITY_ATTEST_RECORD_RESULT_FIELDS_INVALID: $sid");continue};if(-not $stateIds.Contains($sid) -or -not $resultIds.Add($sid)){$errors.Add("CONTINUITY_ATTEST_RECORD_RESULT_ID_INVALID: $sid")};if([string]$recordResult.verdict -cne 'PASS'){$errors.Add("CONTINUITY_ATTEST_RECORD_RESULT_NOT_PASS: $sid")};if(-not(Test-SystemV7ConcreteText -Value ([string]$recordResult.reason))){$errors.Add("CONTINUITY_ATTEST_RECORD_REASON_NOT_CONCRETE: $sid")}}
    if($resultIds.Count -ne $stateIds.Count){$errors.Add('CONTINUITY_ATTEST_RECORD_COVERAGE_INCOMPLETE')}
    if([string]$blocks.act_id -cne [string]$continuityOut.act_id -or @($blocks.blocks).Count -eq 0){$errors.Add('CONTINUITY_ATTEST_BLOCKS_IDENTITY_INVALID')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);ActId=[string]$continuityOut.act_id;Result=$result;Path=$output;Sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
}

function New-SystemV7NarrativeRunTelemetry {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][object]$BundleData,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][DateTimeOffset]$StartedAt,
        [Parameter(Mandatory)][DateTimeOffset]$CompletedAt,
        [string]$TelemetryPath=''
    )
    $project=[IO.Path]::GetFullPath($ProjectPath)
    $inputBytes=[int64]0;foreach($entry in @($BundleData.entries)){$inputBytes+=[int64]$entry.bytes}
    $outputBytes=[int64](Get-Item -LiteralPath $OutputPath).Length
    $inputEstimate=[int64][math]::Ceiling($inputBytes/4.0)
    $outputEstimate=[int64][math]::Ceiling($outputBytes/4.0)
    $durationMs=[int64][math]::Round(($CompletedAt-$StartedAt).TotalMilliseconds,0,[MidpointRounding]::AwayFromZero)
    $status='AUTOMATIC_ONLY';$providerError='BRAK';$providerRelative='BRAK';$providerSha='BRAK'
    $inputTokens=$null;$prefixTokens=$null;$sourceCardTokens=$null;$outputTokens=$null;$cacheRead=$null;$cacheWrite=$null;$retryCount=$null;$costAmount=$null;$costCurrency='BRAK';$cacheStatus='NOT_REPORTED'
    if(-not [string]::IsNullOrWhiteSpace($TelemetryPath)){
        try{
            $providerFull=[IO.Path]::GetFullPath($TelemetryPath)
            $expectedProvider=Join-Path $project "_work\narrative-runs\$([string]$BundleData.run_id)\provider-telemetry.json"
            if(-not $providerFull.Equals([IO.Path]::GetFullPath($expectedProvider),[StringComparison]::OrdinalIgnoreCase)){throw 'PATH_INVALID'}
            $providerRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $providerFull
            if(-not(Test-Path -LiteralPath $providerFull -PathType Leaf)){throw 'SOURCE_MISSING'}
            $providerBytes=[IO.File]::ReadAllBytes($providerFull);$providerSha=(Get-FileHash -LiteralPath $providerFull -Algorithm SHA256).Hash
            if($providerBytes.Length -ge 3 -and $providerBytes[0] -eq 0xEF -and $providerBytes[1] -eq 0xBB -and $providerBytes[2] -eq 0xBF){throw 'UTF8_BOM_FORBIDDEN'}
            $providerText=[Text.UTF8Encoding]::new($false,$true).GetString($providerBytes)
            try{$provider=$providerText|ConvertFrom-Json -DateKind String -Depth 16}catch{throw 'INVALID_JSON_OR_SCHEMA'}
            $providerFields=@('schema','input_tokens','prefix_tokens','source_card_tokens','output_tokens','cache_read_tokens','cache_write_tokens','retry_count','cost_amount','cost_currency')
            if(@($provider.PSObject.Properties.Name).Count -ne $providerFields.Count -or @(Compare-Object -ReferenceObject $providerFields -DifferenceObject @($provider.PSObject.Properties.Name) -CaseSensitive).Count -gt 0 -or [string]$provider.schema -cne 'MODEL_RUN_TELEMETRY_V1'){throw 'INVALID_JSON_OR_SCHEMA'}
            foreach($name in @('input_tokens','prefix_tokens','source_card_tokens','output_tokens','cache_read_tokens','cache_write_tokens','retry_count')){
                $value=$provider.$name
                if(($value -isnot [int]) -and ($value -isnot [long]) -and ($value -isnot [uint32]) -and ($value -isnot [uint64])){throw 'INVALID_JSON_OR_SCHEMA'}
                if([int64]$value -lt 0){throw 'INVALID_JSON_OR_SCHEMA'}
            }
            if([int64]$provider.retry_count -gt 100){throw 'INVALID_JSON_OR_SCHEMA'}
            if($null -eq $provider.cost_amount){if([string]$provider.cost_currency -cne 'BRAK'){throw 'INVALID_JSON_OR_SCHEMA'}}
            else{
                $parsedCost=[decimal]0
                if(-not[decimal]::TryParse([string]$provider.cost_amount,[Globalization.NumberStyles]::Number,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsedCost) -or $parsedCost -lt 0 -or [string]$provider.cost_currency -cnotmatch '^[A-Z]{3}$'){throw 'INVALID_JSON_OR_SCHEMA'}
                $costAmount=$parsedCost;$costCurrency=[string]$provider.cost_currency
            }
            $inputTokens=[int64]$provider.input_tokens;$prefixTokens=[int64]$provider.prefix_tokens;$sourceCardTokens=[int64]$provider.source_card_tokens;$outputTokens=[int64]$provider.output_tokens
            $cacheRead=[int64]$provider.cache_read_tokens;$cacheWrite=[int64]$provider.cache_write_tokens;$retryCount=[int]$provider.retry_count
            $cacheStatus=if($cacheRead -gt 0){'HIT'}elseif($cacheWrite -gt 0){'WRITE_ONLY'}else{'MISS'}
            $status='PROVIDER_REPORTED'
        }catch{
            $known=@('PATH_INVALID','SOURCE_MISSING','UTF8_BOM_FORBIDDEN','INVALID_JSON_OR_SCHEMA')
            $providerError=if($_.Exception.Message -in $known){$_.Exception.Message}else{'INVALID_JSON_OR_SCHEMA'}
            $status='PROVIDER_REJECTED_NON_BLOCKING'
            $inputTokens=$null;$prefixTokens=$null;$sourceCardTokens=$null;$outputTokens=$null;$cacheRead=$null;$cacheWrite=$null;$retryCount=$null;$costAmount=$null;$costCurrency='BRAK';$cacheStatus='NOT_REPORTED'
        }
    }
    [pscustomobject][ordered]@{
        schema='NARRATIVE_RUN_TELEMETRY_V1';collection_status=$status;provider_error_code=$providerError;provider_source_relative=$providerRelative;provider_source_sha256=$providerSha
        input_bytes=$inputBytes;input_tokens_estimated=$inputEstimate;output_bytes=$outputBytes;output_tokens_estimated=$outputEstimate;token_estimate_method='UTF8_BYTES_DIV4_CEILING'
        input_tokens_reported=$inputTokens;prefix_tokens_reported=$prefixTokens;source_card_tokens_reported=$sourceCardTokens;output_tokens_reported=$outputTokens
        duration_ms=$durationMs;cache_read_tokens_reported=$cacheRead;cache_write_tokens_reported=$cacheWrite;cache_status=$cacheStatus;retry_count_reported=$retryCount
        run_status='COMPLETED';failure_or_repack_reason='BRAK';cost_amount_reported=$costAmount;cost_currency=$costCurrency
    }
}

function New-SystemV7NarrativeRunReceiptRecord {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ModelId,
        [Parameter(Mandatory)][string]$ModelRevision,
        [Parameter(Mandatory)][string]$ModelSettingsSha256,
        [Parameter(Mandatory)][string]$PromptRevision,
        [Parameter(Mandatory)][string]$ActorRole,
        [Parameter(Mandatory)][DateTimeOffset]$StartedAt,
        [string]$TelemetryPath = '',
        [string]$Note = 'BRAK'
    )
    Assert-SystemV7NarrativeRunCreationStage -ProjectPath ([IO.Path]::GetFullPath($ProjectPath)) -RunType ((Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32).run_type)
    $bundle = Get-SystemV7NarrativeInputBundleState -ProjectPath $ProjectPath -ManifestPath $ManifestPath -RequireLiveSource
    if (-not $bundle.Valid) { throw "INPUT_BUNDLE_INVALID: $($bundle.Errors -join '; ')" }
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $originState=Get-SystemV7ProjectOriginState -ProjectPath $project
    if(-not $originState.Valid -or [string]$originState.Sha256 -cne $ProjectOriginSha256){throw 'RUN_RECEIPT_PROJECT_ORIGIN_MISMATCH'}
    if($TaskId -notmatch '^[A-Z0-9][A-Z0-9._-]{7,120}$'){throw 'RUN_TASK_ID_INVALID'}
    if(-not(Test-SystemV7ConcreteText $ModelId) -or -not(Test-SystemV7ConcreteText $ModelRevision) -or $ModelSettingsSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or -not(Test-SystemV7ConcreteText $PromptRevision)){throw 'RUN_MODEL_OR_PROMPT_MANIFEST_INVALID'}
    $expectedActor=if([string]$bundle.Data.run_type -ceq 'GENERATE_ACT'){'CLAUDE'}else{'CHATGPT_CODEX'}
    if($ActorRole -cne $expectedActor){throw "RUN_ACTOR_ROLE_INVALID: $($bundle.Data.run_type)/$ActorRole"}
    $output = [IO.Path]::GetFullPath($OutputPath)
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw 'RUN_OUTPUT_MISSING' }
    $expectedOutput=Get-SystemV7NarrativeExpectedRunOutputPath -ProjectPath $project -BundleData $bundle.Data
    if(-not $output.Equals([IO.Path]::GetFullPath($expectedOutput),[StringComparison]::OrdinalIgnoreCase)){throw "RUN_OUTPUT_NONCANONICAL_PATH: $output"}
    if([string]$bundle.Data.run_type -ceq 'CONSTRAINT_ATOMICITY_PREFLIGHT'){$preflight=Get-SystemV7ConstraintPreflightOutputState -ProjectPath $project -OutputPath $output -BundleData $bundle.Data;if(-not $preflight.Valid){throw "CONSTRAINT_PREFLIGHT_OUTPUT_INVALID: $($preflight.Errors -join '; ')"}}
    elseif([string]$bundle.Data.run_type -ceq 'BEAT_PREFLIGHT'){$preflight=Get-SystemV7BeatPreflightOutputState -ProjectPath $project -OutputPath $output -BundleData $bundle.Data;if(-not $preflight.Valid){throw "BEAT_PREFLIGHT_OUTPUT_INVALID: $($preflight.Errors -join '; ')"}}
    elseif([string]$bundle.Data.run_type -ceq 'CONTINUITY_ATTEST'){$attestOutput=Get-SystemV7ContinuityAttestOutputState -ProjectPath $project -OutputPath $output -BundleData $bundle.Data;if(-not $attestOutput.Valid){throw "CONTINUITY_ATTEST_OUTPUT_INVALID: $($attestOutput.Errors -join '; ')"}}
    elseif([string]$bundle.Data.run_type -in @('EDITOR','VERIFY','COLD_READER')){
        $draftPath=Join-Path $project '03-draft.md';if(-not(Test-Path -LiteralPath $draftPath -PathType Leaf)){throw 'K4_DRAFT_MISSING'};$draftSha=(Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash
        $lensState=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens ([string]$bundle.Data.run_type) -OutputPath $output -ExpectedDraftSha256 $draftSha -BundleData $bundle.Data
        if(-not $lensState.Valid){throw "K4_LENS_OUTPUT_INVALID: $($lensState.Errors -join '; ')"}
    }elseif([string]$bundle.Data.run_type -ceq 'QA_IMPACT_REVIEW'){
        $impactOutput=Get-SystemV7QAImpactOutputState -ProjectPath $project -OutputPath $output -BundleData $bundle.Data
        if(-not $impactOutput.Valid){throw "QA_IMPACT_OUTPUT_INVALID: $($impactOutput.Errors -join '; ')"}
    }
    $outputRelative = Get-SystemV7NarrativeRelativePath -Root $project -Path $output
    $now = [DateTimeOffset]::UtcNow
    if ($StartedAt -gt $now.AddMinutes(1) -or $StartedAt -ge $now -or $StartedAt -lt $now.AddDays(-30)) { throw 'RUN_TIME_RANGE_INVALID' }
    $telemetry=New-SystemV7NarrativeRunTelemetry -ProjectPath $project -BundleData $bundle.Data -OutputPath $output -StartedAt $StartedAt -CompletedAt $now -TelemetryPath $TelemetryPath
    $record = [ordered]@{
        schema = 'SYSTEM_V7_NARRATIVE_RUN_RECEIPT_V1'
        workflow_revision = $script:SystemV7NarrativeWorkflowRevision
        project_origin_sha256 = $ProjectOriginSha256
        run_type = [string]$bundle.Data.run_type
        actor_role = $ActorRole
        run_id = [string]$bundle.Data.run_id
        task_id = $TaskId
        model_id = $ModelId
        model_revision = $ModelRevision
        model_settings_sha256 = $ModelSettingsSha256
        prompt_revision = $PromptRevision
        input_profile = [string]$bundle.Data.input_profile
        input_manifest_relative = Get-SystemV7NarrativeRelativePath -Root $project -Path $bundle.Path
        input_manifest_file_sha256 = $bundle.FileSha256
        input_manifest_sha256 = [string]$bundle.Data.input_manifest_sha256
        output_relative = $outputRelative
        output_sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
        started_at_utc = $StartedAt.UtcDateTime.ToString('o')
        completed_at_utc = $now.UtcDateTime.ToString('o')
        independence_declaration = 'FRESH_CONTEXT_DECLARED; INPUTS_FROM_BOUND_BUNDLE_ONLY; NOT_CRYPTOGRAPHIC_IDENTITY_PROOF'
        execution_status = 'COMPLETED'
        telemetry = $telemetry
        note = $Note
    }
    $record['binding_sha256'] = Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $record)
    return [pscustomobject]$record
}

function Get-SystemV7NarrativeRunReceiptState {
    param([Parameter(Mandatory)][string]$ProjectPath, [Parameter(Mandatory)][string]$ReceiptPath, [string]$ExpectedRunType, [string]$ExpectedOutputSha256,[string]$ExpectedDraftSha256,[switch]$RequireLiveInputs,[switch]$HistoricalQAImpact)
    $errors = [Collections.Generic.List[string]]::new()
    $project = [IO.Path]::GetFullPath($ProjectPath)
    try{$receiptFull=[IO.Path]::GetFullPath($ReceiptPath);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $receiptFull}catch{return [pscustomobject]@{Valid=$false;Errors=@('RUN_RECEIPT_PATH_INVALID');Data=$null}}
    if (-not (Test-Path -LiteralPath $receiptFull -PathType Leaf)) { return [pscustomobject]@{ Valid=$false; Errors=@('RUN_RECEIPT_MISSING'); Data=$null } }
    try { $data = Get-Content -LiteralPath $receiptFull -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 32 }
    catch { return [pscustomobject]@{ Valid=$false; Errors=@('RUN_RECEIPT_INVALID_JSON'); Data=$null } }
    $expected = @('schema','workflow_revision','project_origin_sha256','run_type','actor_role','run_id','task_id','model_id','model_revision','model_settings_sha256','prompt_revision','input_profile','input_manifest_relative','input_manifest_file_sha256','input_manifest_sha256','output_relative','output_sha256','started_at_utc','completed_at_utc','independence_declaration','execution_status','telemetry','note','binding_sha256')
    if (@(Compare-Object -ReferenceObject $expected -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0 -or @($data.PSObject.Properties.Name).Count -ne $expected.Count) { $errors.Add('RUN_RECEIPT_FIELDS_INVALID') }
    if ([string]$data.schema -cne 'SYSTEM_V7_NARRATIVE_RUN_RECEIPT_V1' -or [string]$data.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision) { $errors.Add('RUN_RECEIPT_SCHEMA_INVALID') }
    $expectedActor=if([string]$data.run_type -ceq 'GENERATE_ACT'){'CLAUDE'}else{'CHATGPT_CODEX'}
    if([string]$data.actor_role -cne $expectedActor -or [string]$data.execution_status -cne 'COMPLETED' -or [string]$data.independence_declaration -cne 'FRESH_CONTEXT_DECLARED; INPUTS_FROM_BOUND_BUNDLE_ONLY; NOT_CRYPTOGRAPHIC_IDENTITY_PROOF'){$errors.Add('RUN_RECEIPT_EXECUTION_DECLARATION_INVALID')}
    if([string]$data.run_id -notmatch '^[A-Z0-9][A-Z0-9._-]{7,80}$' -or [string]$data.task_id -notmatch '^[A-Z0-9][A-Z0-9._-]{7,120}$' -or [string]$data.model_settings_sha256 -notmatch '^[A-Fa-f0-9]{64}$'){$errors.Add('RUN_RECEIPT_IDENTIFIER_INVALID')}
    if ($ExpectedRunType -and [string]$data.run_type -cne $ExpectedRunType) { $errors.Add('RUN_RECEIPT_TYPE_MISMATCH') }
    if($script:SystemV7NarrativePromptRevisions.Contains([string]$data.run_type) -and [string]$data.prompt_revision -cne [string]$script:SystemV7NarrativePromptRevisions[[string]$data.run_type]){$errors.Add('RUN_RECEIPT_PROMPT_REVISION_INVALID')}
    if ($ExpectedOutputSha256 -and [string]$data.output_sha256 -cne $ExpectedOutputSha256) { $errors.Add('RUN_RECEIPT_OUTPUT_EXPECTATION_MISMATCH') }
    $copy = [ordered]@{}
    foreach ($property in $data.PSObject.Properties) { if ($property.Name -cne 'binding_sha256') { $copy[$property.Name]=$property.Value } }
    if ((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)) -cne [string]$data.binding_sha256) { $errors.Add('RUN_RECEIPT_BINDING_MISMATCH') }
    $originState=Get-SystemV7ProjectOriginState -ProjectPath $project;if(-not $originState.Valid -or [string]$originState.Sha256 -cne [string]$data.project_origin_sha256){$errors.Add('RUN_RECEIPT_PROJECT_ORIGIN_MISMATCH')}
    $started=[DateTimeOffset]::MinValue;$completed=[DateTimeOffset]::MinValue
    $startedOk=[DateTimeOffset]::TryParse([string]$data.started_at_utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$started)
    $completedOk=[DateTimeOffset]::TryParse([string]$data.completed_at_utc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$completed)
    if(-not $startedOk -or -not $completedOk -or $started -ge $completed -or $completed -gt [DateTimeOffset]::UtcNow.AddMinutes(5) -or $started -lt $completed.AddDays(-30)){$errors.Add('RUN_RECEIPT_TIME_RANGE_INVALID')}
    try { $manifest = Join-Path $project ([string]$data.input_manifest_relative); $bundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $manifest -RequireLiveSource:$RequireLiveInputs; if(-not $bundle.Valid){$errors.Add("RUN_RECEIPT_BUNDLE_INVALID: $($bundle.Errors -join ',')")} }
    catch { $errors.Add("RUN_RECEIPT_BUNDLE_PATH_INVALID: $($_.Exception.Message)") }
    if ($bundle -and $bundle.Valid) {
        if ($bundle.FileSha256 -cne [string]$data.input_manifest_file_sha256 -or [string]$bundle.Data.input_manifest_sha256 -cne [string]$data.input_manifest_sha256) { $errors.Add('RUN_RECEIPT_INPUT_MANIFEST_MISMATCH') }
        if ([string]$bundle.Data.run_id -cne [string]$data.run_id -or [string]$bundle.Data.run_type -cne [string]$data.run_type -or [string]$bundle.Data.input_profile -cne [string]$data.input_profile) { $errors.Add('RUN_RECEIPT_BUNDLE_IDENTITY_MISMATCH') }
    }
    $telemetry=$data.telemetry
    $telemetryFields=@('schema','collection_status','provider_error_code','provider_source_relative','provider_source_sha256','input_bytes','input_tokens_estimated','output_bytes','output_tokens_estimated','token_estimate_method','input_tokens_reported','prefix_tokens_reported','source_card_tokens_reported','output_tokens_reported','duration_ms','cache_read_tokens_reported','cache_write_tokens_reported','cache_status','retry_count_reported','run_status','failure_or_repack_reason','cost_amount_reported','cost_currency')
    if($null -eq $telemetry -or @($telemetry.PSObject.Properties.Name).Count -ne $telemetryFields.Count -or @(Compare-Object -ReferenceObject $telemetryFields -DifferenceObject @($telemetry.PSObject.Properties.Name) -CaseSensitive).Count -gt 0){$errors.Add('RUN_TELEMETRY_FIELDS_INVALID')}
    else{
        if([string]$telemetry.schema -cne 'NARRATIVE_RUN_TELEMETRY_V1' -or [string]$telemetry.collection_status -notin @('AUTOMATIC_ONLY','PROVIDER_REPORTED','PROVIDER_REJECTED_NON_BLOCKING') -or [string]$telemetry.run_status -cne 'COMPLETED' -or [string]$telemetry.failure_or_repack_reason -cne 'BRAK' -or [string]$telemetry.token_estimate_method -cne 'UTF8_BYTES_DIV4_CEILING'){$errors.Add('RUN_TELEMETRY_IDENTITY_INVALID')}
        $expectedInputBytes=if($bundle -and $bundle.Valid){[int64](@($bundle.Data.entries|Measure-Object -Property bytes -Sum).Sum)}else{[int64]-1}
        try{
            if($expectedInputBytes -ge 0 -and ([int64]$telemetry.input_bytes -ne $expectedInputBytes -or [int64]$telemetry.input_tokens_estimated -ne [int64][math]::Ceiling($expectedInputBytes/4.0))){$errors.Add('RUN_TELEMETRY_INPUT_BINDING_INVALID')}
        }catch{$errors.Add('RUN_TELEMETRY_INPUT_BINDING_INVALID')}
        try{
            if($startedOk -and $completedOk -and [int64]$telemetry.duration_ms -ne [int64][math]::Round(($completed-$started).TotalMilliseconds,0,[MidpointRounding]::AwayFromZero)){$errors.Add('RUN_TELEMETRY_DURATION_INVALID')}
        }catch{$errors.Add('RUN_TELEMETRY_DURATION_INVALID')}
        foreach($name in @('input_bytes','input_tokens_estimated','output_bytes','output_tokens_estimated','duration_ms')){try{if([int64]$telemetry.$name -lt 0){throw 'negative'}}catch{$errors.Add("RUN_TELEMETRY_AUTOMATIC_VALUE_INVALID: $name")}}
        foreach($name in @('input_tokens_reported','prefix_tokens_reported','source_card_tokens_reported','output_tokens_reported','cache_read_tokens_reported','cache_write_tokens_reported','retry_count_reported')){if($null -ne $telemetry.$name){try{if([int64]$telemetry.$name -lt 0){throw 'negative'}}catch{$errors.Add("RUN_TELEMETRY_REPORTED_VALUE_INVALID: $name")}}}
        if($null -ne $telemetry.retry_count_reported -and [int64]$telemetry.retry_count_reported -gt 100){$errors.Add('RUN_TELEMETRY_RETRY_COUNT_INVALID')}
        if([string]$telemetry.collection_status -ceq 'PROVIDER_REPORTED'){
            $missingProviderValues=@(@('input_tokens_reported','prefix_tokens_reported','source_card_tokens_reported','output_tokens_reported','cache_read_tokens_reported','cache_write_tokens_reported','retry_count_reported')|Where-Object{$null -eq $telemetry.$_})
            if([string]$telemetry.provider_error_code -cne 'BRAK' -or [string]$telemetry.provider_source_relative -cnotmatch ('^_work/narrative-runs/'+[regex]::Escape([string]$data.run_id)+'/provider-telemetry\.json$') -or [string]$telemetry.provider_source_sha256 -cnotmatch '^[A-F0-9]{64}$' -or $missingProviderValues.Count -gt 0){$errors.Add('RUN_TELEMETRY_PROVIDER_BINDING_INVALID')}
            $expectedCache=if([int64]$telemetry.cache_read_tokens_reported -gt 0){'HIT'}elseif([int64]$telemetry.cache_write_tokens_reported -gt 0){'WRITE_ONLY'}else{'MISS'};if([string]$telemetry.cache_status -cne $expectedCache){$errors.Add('RUN_TELEMETRY_CACHE_STATUS_INVALID')}
        }else{
            $unexpectedProviderValues=@(@('input_tokens_reported','prefix_tokens_reported','source_card_tokens_reported','output_tokens_reported','cache_read_tokens_reported','cache_write_tokens_reported','retry_count_reported','cost_amount_reported')|Where-Object{$null -ne $telemetry.$_})
            if([string]$telemetry.cache_status -cne 'NOT_REPORTED' -or $unexpectedProviderValues.Count -gt 0){$errors.Add('RUN_TELEMETRY_UNREPORTED_VALUES_INVALID')}
            if([string]$telemetry.collection_status -ceq 'AUTOMATIC_ONLY' -and ([string]$telemetry.provider_error_code -cne 'BRAK' -or [string]$telemetry.provider_source_relative -cne 'BRAK' -or [string]$telemetry.provider_source_sha256 -cne 'BRAK')){$errors.Add('RUN_TELEMETRY_AUTOMATIC_SOURCE_INVALID')}
            if([string]$telemetry.collection_status -ceq 'PROVIDER_REJECTED_NON_BLOCKING'){
                $rejectionCode=[string]$telemetry.provider_error_code
                $expectedProviderRelativePattern='^_work/narrative-runs/'+[regex]::Escape([string]$data.run_id)+'/provider-telemetry\.json$'
                if($rejectionCode -notin @('PATH_INVALID','SOURCE_MISSING','UTF8_BOM_FORBIDDEN','INVALID_JSON_OR_SCHEMA')){$errors.Add('RUN_TELEMETRY_REJECTION_CODE_INVALID')}
                elseif($rejectionCode -ceq 'PATH_INVALID' -and ([string]$telemetry.provider_source_relative -cne 'BRAK' -or [string]$telemetry.provider_source_sha256 -cne 'BRAK')){$errors.Add('RUN_TELEMETRY_REJECTED_SOURCE_BINDING_INVALID')}
                elseif($rejectionCode -ceq 'SOURCE_MISSING' -and ([string]$telemetry.provider_source_relative -cnotmatch $expectedProviderRelativePattern -or [string]$telemetry.provider_source_sha256 -cne 'BRAK')){$errors.Add('RUN_TELEMETRY_REJECTED_SOURCE_BINDING_INVALID')}
                elseif($rejectionCode -in @('UTF8_BOM_FORBIDDEN','INVALID_JSON_OR_SCHEMA') -and ([string]$telemetry.provider_source_relative -cnotmatch $expectedProviderRelativePattern -or [string]$telemetry.provider_source_sha256 -cnotmatch '^[A-F0-9]{64}$')){$errors.Add('RUN_TELEMETRY_REJECTED_SOURCE_BINDING_INVALID')}
            }
        }
        if($null -eq $telemetry.cost_amount_reported){
            if([string]$telemetry.cost_currency -cne 'BRAK'){$errors.Add('RUN_TELEMETRY_COST_INVALID')}
        }else{
            $parsedTelemetryCost=[decimal]0
            if(-not[decimal]::TryParse([string]$telemetry.cost_amount_reported,[Globalization.NumberStyles]::Number,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsedTelemetryCost) -or $parsedTelemetryCost -lt 0 -or [string]$telemetry.cost_currency -cnotmatch '^[A-Z]{3}$'){$errors.Add('RUN_TELEMETRY_COST_INVALID')}
        }
    }
    try {
        $output=Join-Path $project ([string]$data.output_relative)
        $null=Get-SystemV7NarrativeRelativePath -Root $project -Path $output
        if(-not(Test-Path -LiteralPath $output -PathType Leaf)){throw 'missing'}
        if((Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash -cne [string]$data.output_sha256){$errors.Add('RUN_RECEIPT_OUTPUT_STALE')}
        $actualOutputBytes=[int64](Get-Item -LiteralPath $output).Length
        try{
            if([int64]$telemetry.output_bytes -ne $actualOutputBytes -or [int64]$telemetry.output_tokens_estimated -ne [int64][math]::Ceiling($actualOutputBytes/4.0)){$errors.Add('RUN_TELEMETRY_OUTPUT_BINDING_INVALID')}
        }catch{$errors.Add('RUN_TELEMETRY_OUTPUT_BINDING_INVALID')}
        if($bundle -and $bundle.Valid){$expectedOutput=Get-SystemV7NarrativeExpectedRunOutputPath -ProjectPath $project -BundleData $bundle.Data;if(-not([IO.Path]::GetFullPath($output)).Equals([IO.Path]::GetFullPath($expectedOutput),[StringComparison]::OrdinalIgnoreCase)){$errors.Add('RUN_RECEIPT_OUTPUT_NONCANONICAL')}}
    }
    catch { $errors.Add('RUN_RECEIPT_OUTPUT_INVALID') }
    if($bundle -and $bundle.Valid -and [string]$data.run_type -ceq 'CONSTRAINT_ATOMICITY_PREFLIGHT'){$preflight=Get-SystemV7ConstraintPreflightOutputState -ProjectPath $project -OutputPath $output -BundleData $bundle.Data;if(-not $preflight.Valid){foreach($problem in $preflight.Errors){$errors.Add([string]$problem)}}}
    elseif($bundle -and $bundle.Valid -and [string]$data.run_type -ceq 'BEAT_PREFLIGHT'){$preflight=Get-SystemV7BeatPreflightOutputState -ProjectPath $project -OutputPath $output -BundleData $bundle.Data;if(-not $preflight.Valid){foreach($problem in $preflight.Errors){$errors.Add([string]$problem)}}}
    elseif($bundle -and $bundle.Valid -and [string]$data.run_type -ceq 'CONTINUITY_ATTEST'){$attestOutput=Get-SystemV7ContinuityAttestOutputState -ProjectPath $project -OutputPath $output -BundleData $bundle.Data;if(-not $attestOutput.Valid){foreach($problem in $attestOutput.Errors){$errors.Add([string]$problem)}}}
    elseif($bundle -and $bundle.Valid -and [string]$data.run_type -in @('EDITOR','VERIFY','COLD_READER')){
        $draftIdentity=Get-SystemV7K4BundleDraftIdentityState -Lens ([string]$data.run_type) -BundleData $bundle.Data;$draftExpectation=[string]$draftIdentity.Sha256
        if(-not $draftIdentity.Valid){$errors.Add('K4_OUTPUT_BUNDLE_DRAFT_BINDING_MISSING')}
        else{
            if($ExpectedDraftSha256 -and $draftExpectation -cne $ExpectedDraftSha256.ToUpperInvariant()){$errors.Add('K4_OUTPUT_EXPECTED_DRAFT_MISMATCH')}
            $lensState=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens ([string]$data.run_type) -OutputPath $output -ExpectedDraftSha256 $draftExpectation.ToUpperInvariant() -BundleData $bundle.Data;if(-not $lensState.Valid){foreach($problem in $lensState.Errors){$errors.Add([string]$problem)} }
        }
    }elseif($bundle -and $bundle.Valid -and [string]$data.run_type -ceq 'QA_IMPACT_REVIEW'){
        $impactOutput=Get-SystemV7QAImpactOutputState -ProjectPath $project -OutputPath $output -BundleData $bundle.Data -HistoricalImpact:$HistoricalQAImpact
        if(-not $impactOutput.Valid){foreach($problem in $impactOutput.Errors){$errors.Add([string]$problem)}}
    }
    [pscustomobject]@{ Valid=$errors.Count -eq 0; Errors=@($errors); Data=$data; Path=$receiptFull; Sha256=(Get-FileHash -LiteralPath $receiptFull -Algorithm SHA256).Hash }
}

function Get-SystemV7K4BundleDraftIdentityState {
    param([Parameter(Mandatory)][ValidateSet('EDITOR','VERIFY','COLD_READER')][string]$Lens,[Parameter(Mandatory)][object]$BundleData)
    $role=if($Lens -ceq 'VERIFY'){'DRAFT_BLOCKS'}elseif($Lens -ceq 'EDITOR'){'CLEAN_DRAFT'}else{'CLEAN_NARRATION'};$entry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq $role})
    if($entry.Count -ne 1){return [pscustomobject]@{Valid=$false;Errors=@('K4_BUNDLE_DRAFT_ROLE_INVALID');Sha256=''}}
    if($Lens -ceq 'VERIFY'){$sha=[string]$entry[0].sha256}else{$m=[regex]::Match([string]$entry[0].source_relative,'(?:^|/)clean-narration-(?<sha>[A-F0-9]{64})\.md$');$sha=if($m.Success){[string]$m.Groups['sha'].Value}else{''}}
    if($sha -notmatch '^[A-F0-9]{64}$'){return [pscustomobject]@{Valid=$false;Errors=@('K4_BUNDLE_DRAFT_IDENTITY_INVALID');Sha256=$sha}}
    [pscustomobject]@{Valid=$true;Errors=@();Sha256=$sha;Role=$role;Entry=$entry[0]}
}

function Get-SystemV7K4BundleInventoryState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][ValidateSet('EDITOR','VERIFY')][string]$Lens,[Parameter(Mandatory)][object]$BundleData)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    $readEntry={param([string]$Role,[ValidateSet('JSON','TEXT','ARCHITECTURE')][string]$Kind)$entries=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq $Role});if($entries.Count -ne 1){$errors.Add("K4_INVENTORY_ROLE_INVALID: $Role");return $null};try{$path=Join-Path $project ([string]$entries[0].bundle_relative);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $path;if(-not(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne [string]$entries[0].sha256){throw 'missing-or-stale'};switch($Kind){'JSON'{return (Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64)}'ARCHITECTURE'{return (Get-SystemV7NarrativeArchitecture -Path $path).Data}default{return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)}}}catch{$errors.Add("K4_INVENTORY_ROLE_UNREADABLE: $Role/$($_.Exception.Message)");return $null}}
    $blockMap=$null
    if($Lens -ceq 'VERIFY'){
        $draft=&$readEntry 'DRAFT_BLOCKS' 'TEXT';if($draft){$match=[regex]::Match([string]$draft,'(?s)<!--\s*K3_BLOCK_MAP_BEGIN\s*-->\s*```json\s*(?<json>.*?)\s*```\s*<!--\s*K3_BLOCK_MAP_END\s*-->');if(-not $match.Success){$errors.Add('K4_INVENTORY_DRAFT_BLOCK_MAP_MISSING')}else{try{$blockMap=$match.Groups['json'].Value|ConvertFrom-Json -DateKind String -Depth 64}catch{$errors.Add('K4_INVENTORY_DRAFT_BLOCK_MAP_INVALID')}}}
    }else{$blockMap=&$readEntry 'BLOCK_MAP' 'JSON'}
    $blocks=[Collections.Generic.List[object]]::new()
    if($blockMap){
        $mapFields=@('schema','prefix_sha256','model_id','model_revision','acts')
        if([string]$blockMap.schema -cne 'K3_BLOCK_MAP_V1' -or @(Compare-Object -ReferenceObject $mapFields -DifferenceObject @($blockMap.PSObject.Properties.Name)).Count -gt 0 -or @($blockMap.PSObject.Properties.Name).Count -ne $mapFields.Count){$errors.Add('K4_INVENTORY_BLOCK_MAP_SCHEMA_INVALID')}
        $blockSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($act in @($blockMap.acts)){
            $actFields=@('act_id','prose_sha256','blocks_sha256','attest_sha256','blocks');$actId=[string]$act.act_id
            if(@(Compare-Object -ReferenceObject $actFields -DifferenceObject @($act.PSObject.Properties.Name)).Count -gt 0 -or @($act.PSObject.Properties.Name).Count -ne $actFields.Count -or $actId -notmatch '^ACT-\d{3}$' -or @($act.blocks).Count -eq 0){$errors.Add("K4_INVENTORY_ACT_FIELDS_INVALID: $actId");continue}
            foreach($block in @($act.blocks)){
                $fields=@('block_id','block_sha256','word_count','trace_refs','sw_ids','source_p_ids','narrative_refs');$blockId=[string]$block.block_id
                if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($block.PSObject.Properties.Name)).Count -gt 0 -or @($block.PSObject.Properties.Name).Count -ne $fields.Count -or $blockId -notmatch "^BLOCK-$([regex]::Escape($actId))-\d{3}$" -or -not $blockSeen.Add($blockId)){$errors.Add("K4_INVENTORY_BLOCK_FIELDS_INVALID: $blockId");continue}
                foreach($arrayField in @('trace_refs','sw_ids','source_p_ids','narrative_refs')){$valueSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($value in @($block.$arrayField)){if(-not(Test-SystemV7ConcreteText -Value ([string]$value)) -or -not $valueSeen.Add([string]$value)){$errors.Add("K4_INVENTORY_BLOCK_ARRAY_INVALID: $blockId/$arrayField/$value")}}}
                if(@($block.sw_ids).Count -eq 0){$errors.Add("K4_INVENTORY_BLOCK_SW_IDS_EMPTY: $blockId")};foreach($swId in @($block.sw_ids)){if([string]$swId -notmatch '^SW-\d{3}$'){$errors.Add("K4_INVENTORY_BLOCK_SW_ID_INVALID: $blockId/$swId")}}
                foreach($p in @($block.source_p_ids)){if([string]$p -notmatch '^#P-\d{3,}$'){$errors.Add("K4_INVENTORY_BLOCK_P_ID_INVALID: $blockId/$p")}}
                $blocks.Add([pscustomobject]@{act_id=$actId;block_id=$blockId;trace_refs=@([string[]]@($block.trace_refs));sw_ids=@([string[]]@($block.sw_ids));source_p_ids=@([string[]]@($block.source_p_ids));narrative_refs=@([string[]]@($block.narrative_refs))})
            }
        }
    }
    $coverage=[Collections.Generic.List[object]]::new();$locators=[Collections.Generic.List[object]]::new();$acts=[Collections.Generic.List[object]]::new();$questions=[Collections.Generic.List[object]]::new();$reveals=[Collections.Generic.List[object]]::new();$contacts=[Collections.Generic.List[object]]::new();$required=[Collections.Generic.List[object]]::new();$semanticFindings=[Collections.Generic.List[object]]::new()
    if($Lens -ceq 'VERIFY'){
        foreach($block in $blocks){$coverage.Add([ordered]@{block_id=$block.block_id;p_ids=@($block.source_p_ids)})}
        $locatorData=&$readEntry 'SOURCE_LOCATORS' 'JSON';$locatorById=@{};if($locatorData){$locatorFields=@('schema','evidence_sha256','cards');if([string]$locatorData.schema -cne 'SOURCE_LOCATORS_V1' -or @(Compare-Object -ReferenceObject $locatorFields -DifferenceObject @($locatorData.PSObject.Properties.Name)).Count -gt 0 -or @($locatorData.PSObject.Properties.Name).Count -ne $locatorFields.Count){$errors.Add('K4_INVENTORY_LOCATOR_SCHEMA_INVALID')};foreach($card in @($locatorData.cards)){$cardFields=@('p_id','source_id','locator','qa_k1');$id=[string]$card.p_id;if(@(Compare-Object -ReferenceObject $cardFields -DifferenceObject @($card.PSObject.Properties.Name)).Count -gt 0 -or @($card.PSObject.Properties.Name).Count -ne $cardFields.Count -or $id -notmatch '^#P-\d{3,}$' -or -not(Test-SystemV7ConcreteText -Value ([string]$card.source_id)) -or -not(Test-SystemV7ConcreteText -Value ([string]$card.locator))){$errors.Add("K4_INVENTORY_LOCATOR_CARD_INVALID: $id")}elseif($locatorById.ContainsKey($id)){$errors.Add("K4_INVENTORY_LOCATOR_DUPLICATE: $id")}else{$locatorById[$id]=$card}}}
        $seenP=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($block in $blocks){foreach($p in @($block.source_p_ids)){if($seenP.Add([string]$p)){if(-not $locatorById.ContainsKey([string]$p)){$errors.Add("K4_INVENTORY_LOCATOR_MISSING: $p")}else{$card=$locatorById[[string]$p];$locators.Add([ordered]@{p_id=[string]$p;source_id=[string]$card.source_id;locator=[string]$card.locator})}}}}
    }else{
        $architecture=&$readEntry 'ARCHITECTURE' 'ARCHITECTURE';$projection=&$readEntry 'NQ_NR_VC' 'JSON';$semantic=&$readEntry 'SEMANTIC_PREFLIGHT' 'JSON';$voiceExemplars=&$readEntry 'VOICE_EXEMPLARS' 'TEXT'
        if($architecture -and $projection){$projectionExpected=[ordered]@{schema='K4_NQ_NR_VC_PROJECTION_V1';questions=@($architecture.questions);reveals=@($architecture.reveals);viewer_contacts=@($architecture.viewer_contacts)};if((ConvertTo-SystemV7CanonicalJson -Value $projection) -cne (ConvertTo-SystemV7CanonicalJson -Value $projectionExpected)){$errors.Add('K4_INVENTORY_NQ_NR_VC_PROJECTION_MISMATCH')}}
        if($semantic){
            $semanticFields=@('schema','draft_sha256','architecture_revision','voice_exemplars_sha256','findings')
            $draftIdentity=Get-SystemV7K4BundleDraftIdentityState -Lens EDITOR -BundleData $BundleData
            $expectedVoiceSha=if($null -ne $voiceExemplars){Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7LfText -Text ([string]$voiceExemplars))}else{''}
            if(@(Compare-Object -ReferenceObject $semanticFields -DifferenceObject @($semantic.PSObject.Properties.Name)).Count -gt 0 -or @($semantic.PSObject.Properties.Name).Count -ne $semanticFields.Count -or [string]$semantic.schema -cne 'NARRATIVE_SEMANTIC_PREFLIGHT_V1' -or $null -eq $architecture -or [string]$semantic.architecture_revision -cne [string]$architecture.architecture_revision -or -not $draftIdentity.Valid -or [string]$semantic.draft_sha256 -cne [string]$draftIdentity.Sha256 -or [string]$semantic.voice_exemplars_sha256 -cne $expectedVoiceSha){
                $errors.Add('K4_INVENTORY_SEMANTIC_PREFLIGHT_SCHEMA_OR_BINDING_INVALID')
            }else{
                $semanticActIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($semanticAct in @($architecture.acts)){$null=$semanticActIds.Add([string]$semanticAct.act_id)}
                $semanticBlockOwner=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);foreach($semanticBlock in $blocks){if(-not $semanticBlockOwner.ContainsKey([string]$semanticBlock.block_id)){$semanticBlockOwner.Add([string]$semanticBlock.block_id,[string]$semanticBlock.act_id)}}
                $semanticFindingIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$semanticOrdinal=0
                foreach($finding in @($semantic.findings)){
                    $semanticOrdinal++;$fields=@('finding_id','class','rule_id','act_id','block_id','evidence');$findingId=[string]$finding.finding_id;$ruleId=[string]$finding.rule_id;$findingAct=[string]$finding.act_id;$findingBlock=[string]$finding.block_id;$findingEvidence=[string]$finding.evidence
                    $expectedFindingId='SP-{0:D3}' -f $semanticOrdinal
                    $findingValid=@(Compare-Object -ReferenceObject $fields -DifferenceObject @($finding.PSObject.Properties.Name)).Count -eq 0 -and @($finding.PSObject.Properties.Name).Count -eq $fields.Count -and $findingId -ceq $expectedFindingId -and $semanticFindingIds.Add($findingId) -and [string]$finding.class -ceq 'REVIEW_ALERT' -and @('VOICE_EXEMPLAR_8GRAM_OVERLAP','UNPLANNED_DIRECT_VIEWER_CONTACT') -ccontains $ruleId -and $semanticActIds.Contains($findingAct) -and $semanticBlockOwner.ContainsKey($findingBlock) -and [string]$semanticBlockOwner[$findingBlock] -ceq $findingAct -and (Test-SystemV7ConcreteText -Value $findingEvidence)
                    if($findingValid -and $ruleId -ceq 'VOICE_EXEMPLAR_8GRAM_OVERLAP' -and @([regex]::Matches($findingEvidence,'[\p{L}\p{N}]+')).Count -ne 8){$findingValid=$false}
                    if($findingValid -and $ruleId -ceq 'UNPLANNED_DIRECT_VIEWER_CONTACT' -and $findingEvidence -notmatch '(?i)(?:\b(?:ty|tobie|ciebie|twoj|twój|twoja|twoje|twoim|twoich|twoją|wy|wam|was|wasz|wasza|wasze|waszym|waszych)\b|\b(?:wyobraź|spójrz|zobacz|pomyśl|przypomnij|zauważ|posłuchaj)(?:cie|my|\s+sobie)?\b)'){$findingValid=$false}
                    if(-not $findingValid){$errors.Add("K4_INVENTORY_SEMANTIC_FINDING_INVALID: $findingId")}else{$semanticFindings.Add([ordered]@{finding_id=$findingId;rule_id=$ruleId;act_id=$findingAct;block_id=$findingBlock;evidence=$findingEvidence})}
                }
            }
        }
        if($architecture){
            $swOwner=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
            foreach($sw in @($architecture.scene_weave)){try{$swOwner.Add([string]$sw.sw_id,[string]$sw.act_id)}catch{$errors.Add("K4_INVENTORY_ARCHITECTURE_SW_DUPLICATE: $([string]$sw.sw_id)")}}
            foreach($block in $blocks){foreach($swId in @($block.sw_ids)){if(-not $swOwner.ContainsKey([string]$swId)){$errors.Add("K4_INVENTORY_BLOCK_SW_UNKNOWN: $($block.block_id)/$swId")}elseif([string]$swOwner[[string]$swId] -cne [string]$block.act_id){$errors.Add("K4_INVENTORY_BLOCK_SW_OWNER_MISMATCH: $($block.block_id)/$swId")}}}
            foreach($act in @($architecture.acts)){$actBlocks=@($blocks|Where-Object{$_.act_id -ceq [string]$act.act_id}|ForEach-Object{$_.block_id});if($actBlocks.Count -eq 0){$errors.Add("K4_INVENTORY_ACT_BLOCK_MAPPING_EMPTY: $([string]$act.act_id)")};$acts.Add([ordered]@{act_id=[string]$act.act_id;block_ids=$actBlocks;scene_weave_ids=@([string[]]@($act.scene_weave_ids));state_change_sw_id=[string]$act.state_change_evidence})}
            foreach($q in @($architecture.questions)){$qBlocks=@($blocks|Where-Object{@($_.narrative_refs|Where-Object{[string]$_ -match "(?<![A-Z0-9-])$([regex]::Escape([string]$q.nq_id))(?![A-Z0-9-])"}).Count -gt 0}|ForEach-Object{$_.block_id});if($qBlocks.Count -eq 0){$errors.Add("K4_INVENTORY_NQ_BLOCK_MAPPING_EMPTY: $([string]$q.nq_id)")};$questions.Add([ordered]@{nq_id=[string]$q.nq_id;opened_at=[string]$q.opened_at;payoff_node=[string]$q.payoff_node;block_ids=$qBlocks})}
            foreach($r in @($architecture.reveals)){$rBlocks=@($blocks|Where-Object{@($_.narrative_refs|Where-Object{[string]$_ -match "(?<![A-Z0-9-])$([regex]::Escape([string]$r.nr_id))(?![A-Z0-9-])"}).Count -gt 0}|ForEach-Object{$_.block_id});if($rBlocks.Count -eq 0){$errors.Add("K4_INVENTORY_NR_BLOCK_MAPPING_EMPTY: $([string]$r.nr_id)")};$reveals.Add([ordered]@{nr_id=[string]$r.nr_id;target_node=[string]$r.target_node;evidence_p_ids=@([string[]]@($r.evidence_p_ids));block_ids=$rBlocks})}
            foreach($vc in @($architecture.viewer_contacts)){$vcBlocks=@($blocks|Where-Object{@($_.narrative_refs) -ccontains [string]$vc.vc_id}|ForEach-Object{$_.block_id});if($vcBlocks.Count -eq 0){$errors.Add("K4_INVENTORY_VC_BLOCK_MAPPING_EMPTY: $([string]$vc.vc_id)")};$contacts.Add([ordered]@{vc_id=[string]$vc.vc_id;node=[string]$vc.node;function=[string]$vc.function;level=[string]$vc.level;block_ids=$vcBlocks})}
            foreach($sw in @($architecture.scene_weave)){foreach($item in @($sw.required_evidence)){$owner=[string]$sw.act_id;$mappedBlocks=@($blocks|Where-Object{$_.act_id -ceq $owner -and @($_.sw_ids) -ccontains [string]$sw.sw_id -and @($_.source_p_ids) -ccontains [string]$item.p_id}|ForEach-Object{$_.block_id});if($mappedBlocks.Count -eq 0){$errors.Add("K4_INVENTORY_REQUIRED_BLOCK_MAPPING_EMPTY: $([string]$sw.sw_id)/$([string]$item.p_id)")};$required.Add([ordered]@{sw_id=[string]$sw.sw_id;p_id=[string]$item.p_id;function=[string]$item.function;necessity=[string]$item.necessity;block_ids=$mappedBlocks})}}
        }
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);BlockMap=$blockMap;Blocks=@($blocks);Coverage=@($coverage);Locators=@($locators);Acts=@($acts);Questions=@($questions);Reveals=@($reveals);ViewerContacts=@($contacts);Required=@($required);SemanticFindings=@($semanticFindings)}
}

function Get-SystemV7K4MachineSectionState {
    param(
        [AllowEmptyString()][Parameter(Mandatory)][string]$Body,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][Collections.IDictionary]$Specs
    )
    $errors=[Collections.Generic.List[string]]::new()
    $rowsByPrefix=[ordered]@{}
    $brakCounts=@{}
    foreach($prefix in $Specs.Keys){$rowsByPrefix[$prefix]=[Collections.Generic.List[object]]::new();$brakCounts[$prefix]=0}
    $analysisValues=[Collections.Generic.List[string]]::new()
    foreach($rawLine in @($Body -split "`n")){
        $line=$rawLine.Trim()
        if([string]::IsNullOrWhiteSpace($line)){continue}
        $analysisMatch=[regex]::Match($line,'^ANALYSIS:\s*(\S.*?)\s*$')
        if($analysisMatch.Success){$analysisValues.Add([string]$analysisMatch.Groups[1].Value);continue}
        $matched=$false
        foreach($prefix in $Specs.Keys){
            $marker="$prefix`:"
            if($line.StartsWith($marker,[StringComparison]::Ordinal)){
                $matched=$true
                $payload=$line.Substring($marker.Length).Trim()
                if($payload -ceq 'BRAK'){$brakCounts[$prefix]=[int]$brakCounts[$prefix]+1;continue}
                if([string]::IsNullOrWhiteSpace($payload)){$errors.Add("K4_MACHINE_ROW_EMPTY: $Section/$prefix");continue}
                try{$row=$payload|ConvertFrom-Json -DateKind String -Depth 32}catch{$errors.Add("K4_MACHINE_ROW_JSON_INVALID: $Section/$prefix");continue}
                if($row -is [Collections.IEnumerable] -and $row -isnot [string] -and $row -isnot [pscustomobject]){$errors.Add("K4_MACHINE_ROW_NOT_OBJECT: $Section/$prefix");continue}
                $rowsByPrefix[$prefix].Add($row)
                continue
            }
        }
        if(-not $matched){$errors.Add("K4_MACHINE_SECTION_LINE_INVALID: $Section")}
    }
    if($analysisValues.Count -ne 1){$errors.Add("K4_MACHINE_ANALYSIS_COUNT_INVALID: $Section")}
    else{
        $analysis=[string]$analysisValues[0]
        $wordCount=@([regex]::Matches($analysis,'\b[\p{L}\p{N}]+\b')).Count
        if(-not(Test-SystemV7ConcreteText -Value $analysis) -or $analysis.Length -lt 50 -or $wordCount -lt 8 -or $analysis -match '^(?i:OK|PASS|BRAK|WSZYSTKO DOBRZE)[.!]?$'){$errors.Add("K4_MACHINE_ANALYSIS_NOT_SUBSTANTIVE: $Section")}
    }
    $statuses=[Collections.Generic.List[string]]::new()
    foreach($prefix in $Specs.Keys){
        $spec=$Specs[$prefix]
        $expected=@($spec.Expected)
        $actual=@($rowsByPrefix[$prefix])
        $fields=@([string[]]@($spec.Fields))
        if($expected.Count -eq 0){
            if([int]$brakCounts[$prefix] -ne 1 -or $actual.Count -ne 0){$errors.Add("K4_MACHINE_EMPTY_SET_MARKER_INVALID: $Section/$prefix")}
            continue
        }
        if([int]$brakCounts[$prefix] -ne 0){$errors.Add("K4_MACHINE_BRAK_WITH_EXPECTED_ROWS: $Section/$prefix")}
        if($actual.Count -ne $expected.Count){$errors.Add("K4_MACHINE_ROW_COUNT_MISMATCH: $Section/$prefix/expected=$($expected.Count)/actual=$($actual.Count)")}
        $limit=[Math]::Min($actual.Count,$expected.Count)
        for($index=0;$index -lt $limit;$index++){
            $row=$actual[$index]
            $expectedFields=@($fields+@('status'))
            if($null -eq $row -or @(Compare-Object -ReferenceObject $expectedFields -DifferenceObject @($row.PSObject.Properties.Name)).Count -gt 0 -or @($row.PSObject.Properties.Name).Count -ne $expectedFields.Count){$errors.Add("K4_MACHINE_ROW_FIELDS_INVALID: $Section/$prefix/$($index+1)");continue}
            $status=[string]$row.status
            if($status -notin @('PASS','FAIL')){$errors.Add("K4_MACHINE_ROW_STATUS_INVALID: $Section/$prefix/$($index+1)")}else{$statuses.Add($status)}
            $actualCore=[ordered]@{};$expectedCore=[ordered]@{}
            foreach($field in $fields){$actualCore[$field]=$row.$field;$expectedCore[$field]=$expected[$index].$field}
            if((ConvertTo-SystemV7CanonicalJson -Value $actualCore) -cne (ConvertTo-SystemV7CanonicalJson -Value $expectedCore)){$errors.Add("K4_MACHINE_ROW_MAPPING_MISMATCH: $Section/$prefix/$($index+1)")}
        }
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Rows=[pscustomobject]$rowsByPrefix;Statuses=@($statuses);Analysis=if($analysisValues.Count -eq 1){[string]$analysisValues[0]}else{''}}
}

function Get-SystemV7K4LensOutputState {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][ValidateSet('EDITOR','VERIFY','COLD_READER')][string]$Lens,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$ExpectedDraftSha256,
        [object]$BundleData
    )
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    try{$path=[IO.Path]::GetFullPath($OutputPath);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $path}catch{return [pscustomobject]@{Valid=$false;Errors=@('K4_OUTPUT_PATH_INVALID');Path=$null}}
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('K4_OUTPUT_MISSING');Path=$path}}
    $text=(ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $path -Raw -Encoding UTF8)).Trim()+"`n";$lines=@($text -split "`n"|Where-Object{-not [string]::IsNullOrWhiteSpace($_)})
    $schema="K4_${Lens}_OUTPUT_V1";$headers=[ordered]@{SCHEMA=$schema;LENS=$Lens;DRAFT_SHA256=$ExpectedDraftSha256;VERDICT='(?:PASS|FAIL)';CRITICAL_COUNT='\d+';MAJOR_COUNT='\d+';MINOR_COUNT='\d+';REVIEW_ALERT_COUNT='\d+'}
    $values=@{};$headerIndex=0
    foreach($name in $headers.Keys){$pattern='^'+[regex]::Escape($name)+':\s*('+[string]$headers[$name]+')\s*$';$match=if($headerIndex -lt $lines.Count){[regex]::Match([string]$lines[$headerIndex],$pattern)}else{$null};if($null -eq $match -or -not $match.Success){$errors.Add("K4_OUTPUT_HEADER_ORDER_OR_VALUE_INVALID: $name")}else{$values[$name]=[string]$match.Groups[1].Value};if(@([regex]::Matches($text,"(?m)^$([regex]::Escape($name)):\s*.*$")).Count -ne 1){$errors.Add("K4_OUTPUT_HEADER_COUNT_INVALID: $name")};$headerIndex++}
    foreach($name in @('CRITICAL_COUNT','MAJOR_COUNT','MINOR_COUNT','REVIEW_ALERT_COUNT')){if($values.ContainsKey($name)){$parsed=0;if(-not [int]::TryParse([string]$values[$name],[ref]$parsed)){$errors.Add("K4_OUTPUT_COUNT_RANGE_INVALID: $name")}else{$values[$name]=$parsed}}}
    $sectionMap=@{EDITOR=@('HOOK_AND_PROMISE','QUESTION_REVEAL_LOGIC','TWO_AXES_AND_STATE_CHANGE','EXPOSITION_TRANSITIONS','VOICE_VIEWER_CONTACT','FINALE','FINDINGS');VERIFY=@('CLAIM_COVERAGE','SOURCE_LOCATORS_CHECKED','ATTRIBUTION_UNCERTAINTY','CONTRADICTIONS','FINDINGS');COLD_READER=@('CONFUSION_AND_DROPOFF','PAYOFF_AND_MEMORY','FINDINGS')}
    $requiredSections=@($sectionMap[$Lens]);$allHeadingMatches=@([regex]::Matches($text,'(?m)^##\s+([^\r\n]+?)\s*$'));$actualSections=@($allHeadingMatches|ForEach-Object{$_.Groups[1].Value.Trim()})
    if(($actualSections -join '|') -cne ($requiredSections -join '|')){$errors.Add('K4_OUTPUT_SECTION_ORDER_OR_ALLOWLIST_INVALID')}
    $coldFields=[ordered]@{};$expectedPrefixCount=$headers.Count
    if($Lens -ceq 'COLD_READER'){
        foreach($i in 1..10){$id='Q{0:D2}' -f $i;foreach($suffix in @('RESPONSE','EVIDENCE')){$field="${id}_${suffix}";$lineIndex=$expectedPrefixCount;$expectedPrefixCount++;$m=if($lineIndex -lt $lines.Count){[regex]::Match([string]$lines[$lineIndex],'^'+$field+':\s*(\S.*?)\s*$')}else{$null};if($null -eq $m -or -not $m.Success){$errors.Add("K4_COLD_FIELD_ORDER_OR_VALUE_INVALID: $field")}else{$value=[string]$m.Groups[1].Value;if(-not(Test-SystemV7ConcreteText -Value $value) -or $value -match '^(?i:OK|BRAK|NIE WIEM)$' -or $value.Length -lt 12){$errors.Add("K4_COLD_FIELD_NOT_SUBSTANTIVE: $field")}else{$coldFields[$field]=$value}};if(@([regex]::Matches($text,"(?m)^${field}:\s*.*$")).Count -ne 1){$errors.Add("K4_COLD_FIELD_COUNT_INVALID: $field")}}}
    }
    if($expectedPrefixCount -ge $lines.Count -or [string]$lines[$expectedPrefixCount] -cne "## $($requiredSections[0])"){$errors.Add('K4_OUTPUT_UNCONSUMED_PREFIX_OR_FIRST_SECTION_INVALID')}
    $sectionBodies=[ordered]@{};$reservedLine='^(?:SCHEMA|LENS|DRAFT_SHA256|VERDICT|CRITICAL_COUNT|MAJOR_COUNT|MINOR_COUNT|REVIEW_ALERT_COUNT|EDITOR_PROOF|VERIFY_PROOF|COLD_READER_PROOF|K4_PROOF_SET_SHA256|AKTUALNY_WERDYKT|PROOF_KIND|CARRYFORWARD_RECEIPT|DIFF_SHA256|Q\d{2}_(?:RESPONSE|EVIDENCE))\s*:'
    foreach($section in $requiredSections){$m=[regex]::Match($text,"(?ms)^##\s+$([regex]::Escape($section))\s*`n(?<body>.*?)(?=^##\s+|\z)");$body=if($m.Success){$m.Groups['body'].Value.Trim()}else{''};if(-not $m.Success -or [string]::IsNullOrWhiteSpace($body)){$errors.Add("K4_OUTPUT_SECTION_EMPTY: $section");continue};if($section -ne 'FINDINGS'){$wordCount=@([regex]::Matches($body,'\b[\p{L}\p{N}]+\b')).Count;if($body.Length -lt 50 -or $wordCount -lt 8){$errors.Add("K4_OUTPUT_SECTION_NOT_SUBSTANTIVE: $section")};if($body -match "(?m)$reservedLine" -or $body -match '(?m)^#{1,6}\s+'){$errors.Add("K4_OUTPUT_SECTION_RESERVED_INJECTION: $section")}};$sectionBodies[$section]=$body}
    $machineStatuses=[Collections.Generic.List[string]]::new()
    if($Lens -in @('EDITOR','VERIFY')){
        if($null -eq $BundleData){$errors.Add('K4_OUTPUT_BUNDLE_DATA_REQUIRED')}
        else{
            $inventory=Get-SystemV7K4BundleInventoryState -ProjectPath $project -Lens $Lens -BundleData $BundleData
            if(-not $inventory.Valid){foreach($problem in @($inventory.Errors)){$errors.Add("K4_OUTPUT_INVENTORY_INVALID: $problem")}}
            elseif($Lens -ceq 'VERIFY'){
                $coverageState=Get-SystemV7K4MachineSectionState -Body ([string]$sectionBodies.CLAIM_COVERAGE) -Section 'CLAIM_COVERAGE' -Specs ([ordered]@{
                    COVERAGE_JSON=[ordered]@{Expected=@($inventory.Coverage);Fields=@('block_id','p_ids')}
                })
                $locatorState=Get-SystemV7K4MachineSectionState -Body ([string]$sectionBodies.SOURCE_LOCATORS_CHECKED) -Section 'SOURCE_LOCATORS_CHECKED' -Specs ([ordered]@{
                    LOCATOR_JSON=[ordered]@{Expected=@($inventory.Locators);Fields=@('p_id','source_id','locator')}
                })
                foreach($state in @($coverageState,$locatorState)){foreach($problem in @($state.Errors)){$errors.Add([string]$problem)};foreach($status in @($state.Statuses)){$machineStatuses.Add([string]$status)}}
            }else{
                $questionRevealState=Get-SystemV7K4MachineSectionState -Body ([string]$sectionBodies.QUESTION_REVEAL_LOGIC) -Section 'QUESTION_REVEAL_LOGIC' -Specs ([ordered]@{
                    NQ_JSON=[ordered]@{Expected=@($inventory.Questions);Fields=@('nq_id','opened_at','payoff_node','block_ids')}
                    NR_JSON=[ordered]@{Expected=@($inventory.Reveals);Fields=@('nr_id','target_node','evidence_p_ids','block_ids')}
                })
                $actState=Get-SystemV7K4MachineSectionState -Body ([string]$sectionBodies.TWO_AXES_AND_STATE_CHANGE) -Section 'TWO_AXES_AND_STATE_CHANGE' -Specs ([ordered]@{
                    ACT_JSON=[ordered]@{Expected=@($inventory.Acts);Fields=@('act_id','block_ids','scene_weave_ids','state_change_sw_id')}
                })
                $requiredState=Get-SystemV7K4MachineSectionState -Body ([string]$sectionBodies.EXPOSITION_TRANSITIONS) -Section 'EXPOSITION_TRANSITIONS' -Specs ([ordered]@{
                    REQUIRED_JSON=[ordered]@{Expected=@($inventory.Required);Fields=@('sw_id','p_id','function','necessity','block_ids')}
                })
                $viewerState=Get-SystemV7K4MachineSectionState -Body ([string]$sectionBodies.VOICE_VIEWER_CONTACT) -Section 'VOICE_VIEWER_CONTACT' -Specs ([ordered]@{
                    VC_JSON=[ordered]@{Expected=@($inventory.ViewerContacts);Fields=@('vc_id','node','function','level','block_ids')}
                    PREFLIGHT_JSON=[ordered]@{Expected=@($inventory.SemanticFindings);Fields=@('finding_id','rule_id','act_id','block_id','evidence')}
                })
                foreach($state in @($questionRevealState,$actState,$requiredState,$viewerState)){foreach($problem in @($state.Errors)){$errors.Add([string]$problem)};foreach($status in @($state.Statuses)){$machineStatuses.Add([string]$status)}}
            }
        }
    }
    $findingBody=[string]$sectionBodies.FINDINGS;$findingLines=@($findingBody -split "`n"|ForEach-Object{$_.Trim()}|Where-Object{$_});$findingPattern=switch($Lens){'EDITOR'{'^FINDING:\s*E-\d{3}\s*\|\s*SEVERITY:\s*(CRITICAL|MAJOR|MINOR|REVIEW_ALERT)\s*\|\s*BLOCK_ID:\s*(?:BLOCK-ACT-\d{3}-\d{3}|GLOBAL)\s*\|\s*CRITERION:\s*\S.+?\s*\|\s*OBSERVATION:\s*\S.+?\s*\|\s*CLOSURE:\s*\S.+$'}'VERIFY'{'^FINDING:\s*V-\d{3}\s*\|\s*SEVERITY:\s*(CRITICAL|MAJOR|MINOR|REVIEW_ALERT)\s*\|\s*BLOCK_ID:\s*BLOCK-ACT-\d{3}-\d{3}\s*\|\s*P_ID:\s*(?:#P-\d{3,}|BRAK)\s*\|\s*SOURCE_ID:\s*\S.+?\s*\|\s*LOCATOR:\s*\S.+?\s*\|\s*OBSERVATION:\s*\S.+?\s*\|\s*CLOSURE:\s*\S.+$'}'COLD_READER'{'^FINDING:\s*C-\d{3}\s*\|\s*SEVERITY:\s*(CRITICAL|MAJOR|MINOR|REVIEW_ALERT)\s*\|\s*LOCATION:\s*\S.+?\s*\|\s*OBSERVATION:\s*\S.+?\s*\|\s*CLOSURE:\s*\S.+$'}}
    $counts=@{CRITICAL=0;MAJOR=0;MINOR=0;REVIEW_ALERT=0};$ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if($findingLines.Count -eq 1 -and $findingLines[0] -ceq 'BRAK'){}elseif($findingLines.Count -eq 0){$errors.Add('K4_OUTPUT_FINDINGS_EMPTY')}else{foreach($line in $findingLines){$findingMatch=[regex]::Match($line,$findingPattern);if(-not $findingMatch.Success){$errors.Add('K4_OUTPUT_FINDING_FORMAT_INVALID');continue};$severity=[string]$findingMatch.Groups[1].Value;$counts[$severity]++;$id=[regex]::Match($line,'^FINDING:\s*([ECV]-\d{3})').Groups[1].Value;if(-not $ids.Add($id)){$errors.Add("K4_OUTPUT_FINDING_ID_DUPLICATE: $id")}}}
    foreach($severity in @('CRITICAL','MAJOR','MINOR','REVIEW_ALERT')){if(-not $values.ContainsKey("${severity}_COUNT") -or [int]$values["${severity}_COUNT"] -ne [int]$counts[$severity]){$errors.Add("K4_OUTPUT_${severity}_COUNT_MISMATCH")}}
    if($values.ContainsKey('VERDICT') -and $values.VERDICT -ceq 'PASS' -and ($counts.CRITICAL -ne 0 -or $counts.MAJOR -ne 0 -or -not $values.ContainsKey('REVIEW_ALERT_COUNT') -or [int]$values.REVIEW_ALERT_COUNT -ne 0 -or @($machineStatuses|Where-Object{$_ -cne 'PASS'}).Count -gt 0)){$errors.Add('K4_OUTPUT_FALSE_PASS')}
    $normalized=[Collections.Generic.List[string]]::new();foreach($name in $headers.Keys){if($values.ContainsKey($name)){$normalized.Add("${name}: $($values[$name])")}};foreach($field in $coldFields.Keys){$normalized.Add("${field}: $($coldFields[$field])")};foreach($section in $requiredSections){$normalized.Add("## $section");$normalized.Add([string]$sectionBodies[$section])}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Path=$path;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;Verdict=$values.VERDICT;Counts=[pscustomobject]$counts;Headers=[pscustomobject]$values;Sections=[pscustomobject]$sectionBodies;ColdFields=[pscustomobject]$coldFields;NormalizedReport=(($normalized -join "`n`n").Trim()+"`n")}
}

function Get-SystemV7QAImpactState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][string]$ImpactPath,[switch]$HistoricalNewDraft)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    try{$path=[IO.Path]::GetFullPath($ImpactPath);$relative=Get-SystemV7NarrativeRelativePath -Root $project -Path $path}catch{return [pscustomobject]@{Valid=$false;Errors=@('QA_IMPACT_PATH_INVALID');Data=$null}}
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('QA_IMPACT_MISSING');Data=$null;Path=$path}}
    try{$data=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('QA_IMPACT_INVALID_JSON');Data=$null;Path=$path}}
    $fields=@('schema','workflow_revision','project_origin_sha256','old_draft_relative','old_draft_sha256','new_draft_relative','new_draft_sha256','change_class','changed_block_ids','word_count_delta_percent','over_twenty_percent','decisions','impact_review_required','diff_sha256')
    if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0 -or @($data.PSObject.Properties.Name).Count -ne $fields.Count){$errors.Add('QA_IMPACT_FIELDS_INVALID')}
    $origin=Get-SystemV7ProjectOriginState -ProjectPath $project;if(-not $origin.Valid -or [string]$data.project_origin_sha256 -cne [string]$origin.Sha256){$errors.Add('QA_IMPACT_ORIGIN_MISMATCH')}
    $oldRelative=[string]$data.old_draft_relative;$newRelative=[string]$data.new_draft_relative
    if($oldRelative -cnotmatch '^_work/k4/baselines/(?<oldName>[A-F0-9]{64})\.md$' -or [string]$Matches.oldName -cne [string]$data.old_draft_sha256){$errors.Add('QA_IMPACT_OLD_BASELINE_PATH_INVALID')}
    if($newRelative -cne '03-draft.md'){$errors.Add('QA_IMPACT_NEW_DRAFT_PATH_INVALID')}
    try{$oldPath=[IO.Path]::GetFullPath((Join-Path $project $oldRelative));$newPath=if($HistoricalNewDraft){[IO.Path]::GetFullPath((Join-Path $project "_work\k4\baselines\$([string]$data.new_draft_sha256).md"))}else{[IO.Path]::GetFullPath((Join-Path $project $newRelative))};$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $oldPath;$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $newPath}catch{$oldPath=$null;$newPath=$null;$errors.Add('QA_IMPACT_DRAFT_PATH_OUTSIDE_PROJECT')}
    $readSnapshot={param([string]$Path,[string]$Code)if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "${Code}_MISSING"};$bytes=[IO.File]::ReadAllBytes($Path);$sha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes);[pscustomobject]@{Sha256=$sha;Text=(ConvertTo-SystemV7LfText -Text $text)}}
    try{$old=&$readSnapshot $oldPath 'OLD_DRAFT';$new=&$readSnapshot $newPath 'NEW_DRAFT'}catch{$old=$null;$new=$null;$errors.Add("QA_IMPACT_DRAFT_READ_FAILED: $($_.Exception.Message)")}
    if($old -and $new){
        if($old.Sha256 -cne [string]$data.old_draft_sha256 -or $new.Sha256 -cne [string]$data.new_draft_sha256){$errors.Add('QA_IMPACT_DRAFT_SHA_MISMATCH')}
        $receiptPath=Join-Path (Split-Path -Parent $oldPath) "$($old.Sha256).receipt.json"
        if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)){$errors.Add('QA_IMPACT_BASELINE_RECEIPT_MISSING')}
        else{try{$baseline=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32}catch{$baseline=$null;$errors.Add('QA_IMPACT_BASELINE_RECEIPT_INVALID_JSON')};if($baseline){$baselineFields=@('schema','workflow_revision','project_origin_sha256','baseline_relative','baseline_sha256','created_at_utc','binding_sha256');if(@(Compare-Object -ReferenceObject $baselineFields -DifferenceObject @($baseline.PSObject.Properties.Name)).Count -gt 0 -or @($baseline.PSObject.Properties.Name).Count -ne $baselineFields.Count){$errors.Add('QA_IMPACT_BASELINE_RECEIPT_FIELDS_INVALID')};$copy=[ordered]@{};foreach($p in $baseline.PSObject.Properties){if($p.Name -cne 'binding_sha256'){$copy[$p.Name]=$p.Value}};if([string]$baseline.schema -cne 'SYSTEM_V7_QA_BASELINE_RECEIPT_V2' -or [string]$baseline.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$baseline.project_origin_sha256 -cne [string]$origin.Sha256 -or [string]$baseline.baseline_relative -cne $oldRelative -or [string]$baseline.baseline_sha256 -cne $old.Sha256 -or (Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)) -cne [string]$baseline.binding_sha256){$errors.Add('QA_IMPACT_BASELINE_RECEIPT_BINDING_INVALID')}}}
        if($HistoricalNewDraft){$newBaselineRelative="_work/k4/baselines/$($new.Sha256).md";$newReceiptPath=Join-Path (Split-Path -Parent $newPath) "$($new.Sha256).receipt.json";if(-not(Test-Path -LiteralPath $newReceiptPath -PathType Leaf)){$errors.Add('QA_IMPACT_HISTORICAL_NEW_BASELINE_RECEIPT_MISSING')}else{try{$newBaseline=Get-Content -LiteralPath $newReceiptPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32}catch{$newBaseline=$null;$errors.Add('QA_IMPACT_HISTORICAL_NEW_BASELINE_RECEIPT_INVALID_JSON')};if($newBaseline){$baselineFields=@('schema','workflow_revision','project_origin_sha256','baseline_relative','baseline_sha256','created_at_utc','binding_sha256');$copy=[ordered]@{};foreach($p in $newBaseline.PSObject.Properties){if($p.Name -cne 'binding_sha256'){$copy[$p.Name]=$p.Value}};if(@(Compare-Object -ReferenceObject $baselineFields -DifferenceObject @($newBaseline.PSObject.Properties.Name)).Count -gt 0 -or @($newBaseline.PSObject.Properties.Name).Count -ne $baselineFields.Count -or [string]$newBaseline.schema -cne 'SYSTEM_V7_QA_BASELINE_RECEIPT_V2' -or [string]$newBaseline.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$newBaseline.project_origin_sha256 -cne [string]$origin.Sha256 -or [string]$newBaseline.baseline_relative -cne $newBaselineRelative -or [string]$newBaseline.baseline_sha256 -cne $new.Sha256 -or (Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)) -cne [string]$newBaseline.binding_sha256){$errors.Add('QA_IMPACT_HISTORICAL_NEW_BASELINE_RECEIPT_BINDING_INVALID')}}}}
        $extractMap={param([string]$Text)$m=[regex]::Match($Text,'(?s)<!--\s*K3_BLOCK_MAP_BEGIN\s*-->\s*```json\s*(?<json>.*?)\s*```\s*<!--\s*K3_BLOCK_MAP_END\s*-->');if($m.Success){$m.Groups['json'].Value|ConvertFrom-Json -DateKind String -Depth 64}else{$null}}
        try{$oldMap=&$extractMap $old.Text;$newMap=&$extractMap $new.Text}catch{$oldMap=$null;$newMap=$null;$errors.Add('QA_IMPACT_BLOCK_MAP_INVALID')}
        $oldBlocks=@{};if($oldMap){foreach($a in @($oldMap.acts)){foreach($b in @($a.blocks)){$oldBlocks[[string]$b.block_id]=[string]$b.block_sha256}}};$newBlocks=@{};if($newMap){foreach($a in @($newMap.acts)){foreach($b in @($a.blocks)){$newBlocks[[string]$b.block_id]=[string]$b.block_sha256}}}
        $changed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($id in @($oldBlocks.Keys+$newBlocks.Keys|Select-Object -Unique)){if(-not $oldBlocks.ContainsKey($id) -or -not $newBlocks.ContainsKey($id) -or [string]$oldBlocks[$id] -cne [string]$newBlocks[$id]){$null=$changed.Add([string]$id)}}
        $oldWords=@([regex]::Matches($old.Text,'\b[\p{L}\p{N}]+\b')).Count;$newWords=@([regex]::Matches($new.Text,'\b[\p{L}\p{N}]+\b')).Count;$scope=[math]::Round(100*[math]::Abs($newWords-$oldWords)/[math]::Max(1,$oldWords),1)
        $class=if($old.Sha256 -ceq $new.Sha256){'BYTE_IDENTICAL'}else{'SEMANTIC_REVIEW_REQUIRED'};$decisions=if($class -ceq 'BYTE_IDENTICAL'){[ordered]@{EDITOR='CARRYFORWARD_ALLOWED';VERIFY='CARRYFORWARD_ALLOWED';COLD_READER='CARRYFORWARD_ALLOWED'}}else{[ordered]@{EDITOR='RERUN_REQUIRED';VERIFY='RERUN_REQUIRED';COLD_READER='RERUN_REQUIRED'}}
        $expectedCore=[ordered]@{schema='QA_IMPACT_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;project_origin_sha256=$origin.Sha256;old_draft_relative=$oldRelative;old_draft_sha256=$old.Sha256;new_draft_relative='03-draft.md';new_draft_sha256=$new.Sha256;change_class=$class;changed_block_ids=@($changed|Sort-Object);word_count_delta_percent=$scope;over_twenty_percent=($scope -gt 20);decisions=$decisions;impact_review_required=($class -ceq 'SEMANTIC_REVIEW_REQUIRED')}
        $diff=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $expectedCore);$expected=[ordered]@{};foreach($k in $expectedCore.Keys){$expected[$k]=$expectedCore[$k]};$expected.diff_sha256=$diff
        if((ConvertTo-SystemV7CanonicalJson -Value $data) -cne (ConvertTo-SystemV7CanonicalJson -Value $expected)){$errors.Add('QA_IMPACT_DETERMINISTIC_RECOMPUTE_MISMATCH')}
        if($relative -cne "_work/k4/impact/$diff.impact.json"){$errors.Add('QA_IMPACT_FILENAME_BINDING_INVALID')}
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Data=$data;Path=$path;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}

function Get-SystemV7QAImpactOutputState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][object]$BundleData,[switch]$HistoricalImpact)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    try{$output=[IO.Path]::GetFullPath($OutputPath);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $output}catch{return [pscustomobject]@{Valid=$false;Errors=@('QA_IMPACT_OUTPUT_PATH_INVALID')}}
    if(-not(Test-Path -LiteralPath $output -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('QA_IMPACT_OUTPUT_MISSING')}}
    $diffEntry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq 'IMMUTABLE_DIFF'});$oldEntry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq 'OLD_DRAFT'});$newEntry=@($BundleData.entries|Where-Object{[string]$_.content_role -ceq 'NEW_DRAFT'})
    if($diffEntry.Count -ne 1 -or $oldEntry.Count -ne 1 -or $newEntry.Count -ne 1){return [pscustomobject]@{Valid=$false;Errors=@('QA_IMPACT_BUNDLE_ROLE_COUNT_INVALID')}}
    try{$impactPath=Join-Path $project ([string]$diffEntry[0].bundle_relative);$impact=Get-Content -LiteralPath $impactPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('QA_IMPACT_BUNDLE_DIFF_JSON_INVALID')}}
    $impactLivePath=Join-Path $project ([string]$diffEntry[0].source_relative);$impactState=Get-SystemV7QAImpactState -ProjectPath $project -ImpactPath $impactLivePath -HistoricalNewDraft:$HistoricalImpact
    if(-not $impactState.Valid){foreach($e in $impactState.Errors){$errors.Add("QA_IMPACT_ARTIFACT_$e")}}
    elseif((ConvertTo-SystemV7CanonicalJson -Value $impact) -cne (ConvertTo-SystemV7CanonicalJson -Value $impactState.Data)){$errors.Add('QA_IMPACT_BUNDLE_COPY_NOT_LIVE_ARTIFACT')}
    $impactFields=@('schema','workflow_revision','project_origin_sha256','old_draft_relative','old_draft_sha256','new_draft_relative','new_draft_sha256','change_class','changed_block_ids','word_count_delta_percent','over_twenty_percent','decisions','impact_review_required','diff_sha256')
    if(@(Compare-Object -ReferenceObject $impactFields -DifferenceObject @($impact.PSObject.Properties.Name)).Count -gt 0 -or @($impact.PSObject.Properties.Name).Count -ne $impactFields.Count){$errors.Add('QA_IMPACT_ARTIFACT_FIELDS_INVALID')}
    $impactCore=[ordered]@{};foreach($property in $impact.PSObject.Properties){if($property.Name -cne 'diff_sha256'){$impactCore[$property.Name]=$property.Value}}
    $computedDiff=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $impactCore)
    if([string]$impact.schema -cne 'QA_IMPACT_V1' -or [string]$impact.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$impact.diff_sha256 -cne $computedDiff){$errors.Add('QA_IMPACT_ARTIFACT_BINDING_INVALID')}
    if([string]$oldEntry[0].sha256 -cne [string]$impact.old_draft_sha256 -or [string]$newEntry[0].sha256 -cne [string]$impact.new_draft_sha256){$errors.Add('QA_IMPACT_BUNDLE_DRAFT_SHA_MISMATCH')}
    if([string]$oldEntry[0].source_relative -cne [string]$impact.old_draft_relative -or [string]$newEntry[0].source_relative -cne [string]$impact.new_draft_relative){$errors.Add('QA_IMPACT_BUNDLE_DRAFT_PATH_MISMATCH')}
    $impactSourceRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path (Join-Path $project ([string]$diffEntry[0].source_relative))
    if($impactSourceRelative -cne [string]$diffEntry[0].source_relative -or [string]$diffEntry[0].sha256 -cne (Get-FileHash -LiteralPath $impactPath -Algorithm SHA256).Hash){$errors.Add('QA_IMPACT_BUNDLE_DIFF_BINDING_MISMATCH')}
    if([string]$impact.change_class -notin @('BYTE_IDENTICAL','SEMANTIC_REVIEW_REQUIRED')){$errors.Add('QA_IMPACT_CHANGE_CLASS_INVALID')}
    if(([string]$impact.change_class -ceq 'BYTE_IDENTICAL') -ne ([string]$impact.old_draft_sha256 -ceq [string]$impact.new_draft_sha256)){$errors.Add('QA_IMPACT_CHANGE_CLASS_SHA_CONTRADICTION')}
    $decisionFields=@('EDITOR','VERIFY','COLD_READER');if($null -eq $impact.decisions -or @(Compare-Object -ReferenceObject $decisionFields -DifferenceObject @($impact.decisions.PSObject.Properties.Name)).Count -gt 0 -or @($impact.decisions.PSObject.Properties.Name).Count -ne $decisionFields.Count){$errors.Add('QA_IMPACT_DECISIONS_FIELDS_INVALID')}
    else{foreach($lens in $decisionFields){$expectedDecision=if([string]$impact.change_class -ceq 'BYTE_IDENTICAL'){'CARRYFORWARD_ALLOWED'}else{'RERUN_REQUIRED'};if([string]$impact.decisions.$lens -cne $expectedDecision){$errors.Add("QA_IMPACT_DEFAULT_DECISION_INVALID: $lens")}}}
    if($impact.impact_review_required -cne ([string]$impact.change_class -ceq 'SEMANTIC_REVIEW_REQUIRED')){$errors.Add('QA_IMPACT_REVIEW_FLAG_INVALID')}
    $text=ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $output -Raw -Encoding UTF8)
    $expected=[ordered]@{SCHEMA='QA_IMPACT_OUTPUT_V1';DIFF_SHA256=[string]$impact.diff_sha256;OLD_DRAFT_SHA256=[string]$impact.old_draft_sha256;NEW_DRAFT_SHA256=[string]$impact.new_draft_sha256;CHANGE_CLASS=[string]$impact.change_class}
    $values=@{}
    foreach($name in $expected.Keys){$matches=@([regex]::Matches($text,"(?m)^$([regex]::Escape($name)):\s*(.*?)\s*$"));if($matches.Count -ne 1 -or [string]$matches[0].Groups[1].Value -cne [string]$expected[$name]){$errors.Add("QA_IMPACT_OUTPUT_FIELD_INVALID: $name")}else{$values[$name]=[string]$matches[0].Groups[1].Value}}
    $changedMatches=@([regex]::Matches($text,'(?m)^CHANGED_BLOCK_IDS:\s*(.*?)\s*$'));if($changedMatches.Count -ne 1){$errors.Add('QA_IMPACT_OUTPUT_CHANGED_BLOCKS_INVALID')}
    else{$actual=@($changedMatches[0].Groups[1].Value -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_ -and $_ -cne 'BRAK'}|Sort-Object -Unique);$declared=@([string[]]@($impact.changed_block_ids)|Where-Object{-not [string]::IsNullOrWhiteSpace($_)}|Sort-Object -Unique);if(@(Compare-Object -ReferenceObject $declared -DifferenceObject $actual).Count -gt 0 -or $actual.Count -ne $declared.Count){$errors.Add('QA_IMPACT_OUTPUT_CHANGED_BLOCKS_MISMATCH')}}
    $decisions=@{}
    foreach($lens in @('EDITOR','VERIFY','COLD_READER')){
        foreach($suffix in @('DECISION','REASON','AFFECTED_SCOPE','CONFIDENCE')){$field="${lens}_${suffix}";$matches=@([regex]::Matches($text,"(?m)^${field}:\s*(.*?)\s*$"));if($matches.Count -ne 1){$errors.Add("QA_IMPACT_OUTPUT_FIELD_INVALID: $field");continue};$values[$field]=[string]$matches[0].Groups[1].Value}
        $decision=[string]$values["${lens}_DECISION"];$confidence=[string]$values["${lens}_CONFIDENCE"];$reason=[string]$values["${lens}_REASON"];$scope=[string]$values["${lens}_AFFECTED_SCOPE"]
        if($decision -notin @('RERUN_REQUIRED','CARRYFORWARD_ALLOWED')){$errors.Add("QA_IMPACT_OUTPUT_DECISION_INVALID: $lens")}
        if($confidence -notin @('HIGH','MEDIUM','LOW')){$errors.Add("QA_IMPACT_OUTPUT_CONFIDENCE_INVALID: $lens")}
        if(-not(Test-SystemV7ConcreteText -Value $reason) -or -not(Test-SystemV7ConcreteText -Value $scope)){$errors.Add("QA_IMPACT_OUTPUT_REASON_OR_SCOPE_INVALID: $lens")}
        if($decision -ceq 'CARRYFORWARD_ALLOWED' -and $confidence -cne 'HIGH'){$errors.Add("QA_IMPACT_OUTPUT_UNSAFE_CARRYFORWARD: $lens")}
        $decisions[$lens]=$decision
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Path=$output;Sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;Impact=$impact;Decisions=$decisions}
}

function Get-SystemV7ContinuityAttestState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][ValidatePattern('^ACT-\d{3}$')][string]$ActId)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    $metaPath=Join-Path $project 'meta.md';if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('ATTEST_META_MISSING');Data=$null}}
    $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8;$prefix=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_PREFIX_SHA256';$modelId=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_ID';$modelRevision=Get-SystemV7NarrativeMetaField -Text $meta -Name 'K3_MODEL_REVISION'
    $actDir=Join-Path $project "_work\k3\acts\$ActId";$statePath=Join-Path $actDir 'state.json';$blocksPath=Join-Path $actDir 'blocks.json';$prosePath=Join-Path $actDir 'prose.md';$outPath=Join-Path $actDir 'out.json';$inPath=Join-Path $project "_work\k3\continuity\$ActId.in.json";$attestPath=Join-Path $project "_work\k3\continuity\$ActId.attest.json"
    foreach($pair in @(@($statePath,'STATE'),@($blocksPath,'BLOCKS'),@($prosePath,'PROSE'),@($outPath,'OUT'),@($inPath,'IN'),@($attestPath,'ATTEST'))){if(-not(Test-Path -LiteralPath $pair[0] -PathType Leaf)){$errors.Add("ATTEST_$($pair[1])_MISSING")}}
    if($errors.Count -gt 0){return [pscustomobject]@{Valid=$false;Errors=@($errors);Data=$null;Path=$attestPath}}
    try{$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$attest=Get-Content -LiteralPath $attestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('ATTEST_STATE_OR_RECORD_INVALID_JSON');Data=$null;Path=$attestPath}}
    if([string]$state.schema -cne 'K3_ACT_STATE_V1' -or [string]$state.act_id -cne $ActId -or [string]$state.status -cne 'ATTESTED'){$errors.Add('ATTEST_ACT_STATE_INVALID')}
    $attestFields=@('schema','workflow_revision','act_id','verdict','prefix_sha256','model_id','model_revision','blocks_sha256','continuity_in_sha256','continuity_out_sha256','attest_output_sha256','run_receipt_relative','run_receipt_sha256','next_continuity_in')
    if(@(Compare-Object -ReferenceObject $attestFields -DifferenceObject @($attest.PSObject.Properties.Name)).Count -gt 0 -or @($attest.PSObject.Properties.Name).Count -ne $attestFields.Count){$errors.Add('ATTEST_RECORD_FIELDS_INVALID')}
    if([string]$attest.schema -cne 'CONTINUITY_ATTEST_RECORD_V1' -or [string]$attest.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$attest.act_id -cne $ActId -or [string]$attest.verdict -cne 'PASS'){$errors.Add('ATTEST_RECORD_IDENTITY_INVALID')}
    if([string]$state.prefix_sha256 -cne $prefix -or [string]$attest.prefix_sha256 -cne $prefix -or [string]$state.model_id -cne $modelId -or [string]$attest.model_id -cne $modelId -or [string]$state.model_revision -cne $modelRevision -or [string]$attest.model_revision -cne $modelRevision){$errors.Add('ATTEST_PREFIX_OR_MODEL_STALE')}
    $hashes=@{blocks_sha256=(Get-FileHash -LiteralPath $blocksPath -Algorithm SHA256).Hash;continuity_in_sha256=(Get-FileHash -LiteralPath $inPath -Algorithm SHA256).Hash;continuity_out_sha256=(Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash}
    foreach($name in $hashes.Keys){if([string]$attest.$name -cne [string]$hashes[$name]){$errors.Add("ATTEST_${name}_MISMATCH")}}
    if([string]$state.blocks_sha256 -cne [string]$hashes.blocks_sha256 -or [string]$state.continuity_out_sha256 -cne [string]$hashes.continuity_out_sha256){$errors.Add('ATTEST_STATE_ARTIFACT_BINDING_MISMATCH')}
    $proseBinding=Get-SystemV7ActProseBindingState -ActId $ActId -BlocksPath $blocksPath -ProsePath $prosePath;if(-not $proseBinding.Valid){$errors.Add("ATTEST_PROSE_BLOCK_BINDING_INVALID: $($proseBinding.Errors -join ',')")}
    try{$tracePacketPath=Join-Path $project "_work\k3\packets\$ActId.act-packet.json";$tracePacket=Get-Content -LiteralPath $tracePacketPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$traceBeat=$null;if([string]$tracePacket.complexity_flag -ceq 'COMPLEX'){$traceBeat=Get-Content -LiteralPath (Join-Path $project "_work\k3\beats\$ActId\beat-sheet.json") -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64};$traceState=Get-SystemV7ActSubmissionTraceState -Packet $tracePacket -Blocks @($proseBinding.Blocks.blocks) -BeatSheet $traceBeat;if(-not $traceState.Valid){$errors.Add("ATTEST_ACT_TRACE_INVALID: $($traceState.Errors -join ',')")}}catch{$errors.Add("ATTEST_ACT_TRACE_UNREADABLE: $($_.Exception.Message)")}
    $generateReceipt=Join-Path $project ([string]$state.generate_run_receipt_relative);$generate=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $generateReceipt -ExpectedRunType 'GENERATE_ACT' -RequireLiveInputs
    if(-not $generate.Valid){$errors.Add("ATTEST_GENERATE_PROOF_INVALID: $($generate.Errors -join ',')")}elseif([string]$generate.Sha256 -cne [string]$state.generate_run_receipt_sha256 -or [string]$generate.Data.run_id -cne [string]$state.run_id -or [string]$generate.Data.model_id -cne $modelId -or [string]$generate.Data.model_revision -cne $modelRevision){$errors.Add('ATTEST_GENERATE_PROOF_BINDING_MISMATCH')}
    $attestReceipt=Join-Path $project ([string]$attest.run_receipt_relative);$proof=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $attestReceipt -ExpectedRunType 'CONTINUITY_ATTEST' -RequireLiveInputs
    if(-not $proof.Valid){$errors.Add("ATTEST_RUN_PROOF_INVALID: $($proof.Errors -join ',')")}else{
        if([string]$proof.Sha256 -cne [string]$attest.run_receipt_sha256 -or [string]$proof.Sha256 -cne [string]$state.attest_receipt_sha256 -or [string]$proof.Data.run_id -cne [string]$state.attest_run_id -or [string]$generate.Data.task_id -ceq [string]$proof.Data.task_id){$errors.Add('ATTEST_RUN_PROOF_BINDING_MISMATCH')}
        if([string]$proof.Data.output_sha256 -cne [string]$attest.attest_output_sha256){$errors.Add('ATTEST_OUTPUT_BINDING_MISMATCH')}
        $manifest=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath (Join-Path $project ([string]$proof.Data.input_manifest_relative))
        if(-not $manifest.Valid){$errors.Add('ATTEST_INPUT_BUNDLE_INVALID')}else{
            $expectedInputs=[ordered]@{ACT_PROSE_BLOCKS=$blocksPath;CONTINUITY_IN=$inPath;CONTINUITY_OUT=$outPath}
            foreach($role in $expectedInputs.Keys){$entry=@($manifest.Data.entries|Where-Object{[string]$_.content_role -ceq $role});if($entry.Count -ne 1){$errors.Add("ATTEST_INPUT_ROLE_INVALID: $role");continue};$expectedRelative=Get-SystemV7NarrativeRelativePath -Root $project -Path $expectedInputs[$role];if([string]$entry[0].source_relative -cne $expectedRelative -or [string]$entry[0].sha256 -cne (Get-FileHash -LiteralPath $expectedInputs[$role] -Algorithm SHA256).Hash){$errors.Add("ATTEST_INPUT_BINDING_MISMATCH: $role")}}
            $schemaEntry=@($manifest.Data.entries|Where-Object{[string]$_.content_role -ceq 'CONTINUITY_SCHEMA'});$schemaSource=Join-Path (Split-Path -Parent $PSScriptRoot) '_SYSTEM\NARRATIVE\CONTINUITY-SCHEMA.md';if($schemaEntry.Count -ne 1 -or [string]$schemaEntry[0].sha256 -cne (Get-FileHash -LiteralPath $schemaSource -Algorithm SHA256).Hash){$errors.Add('ATTEST_SCHEMA_BINDING_MISMATCH')}
        }
    }
    if([string]$state.attest_record_relative -cne (Get-SystemV7NarrativeRelativePath -Root $project -Path $attestPath) -or [string]$state.attest_record_sha256 -cne (Get-FileHash -LiteralPath $attestPath -Algorithm SHA256).Hash){$errors.Add('ATTEST_STATE_RECORD_BINDING_MISMATCH')}
    $sequence=@((Get-SystemV7NarrativeMetaField -Text $meta -Name 'NARRATIVE_ACT_SEQUENCE') -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_});$index=[Array]::IndexOf([string[]]$sequence,$ActId);$next=if($index -ge 0 -and $index+1 -lt $sequence.Count){$sequence[$index+1]}elseif($index -eq $sequence.Count-1){'COMPLETE'}else{'INVALID'}
    if([string]$attest.next_continuity_in.schema -cne 'CONTINUITY_IN_V1' -or [string]$attest.next_continuity_in.source_act_id -cne $ActId -or [string]$attest.next_continuity_in.act_id -cne $next){$errors.Add('ATTEST_NEXT_CONTINUITY_IDENTITY_INVALID')}
    if($index -ge 0){
        $architecturePath=Join-Path $project '02-architektura-odcinka.md';$evidencePath=Join-Path $project '01-baza-dowodow.md'
        $architectureValidation=Test-SystemV7NarrativeArchitecture -ArchitecturePath $architecturePath -EvidencePath $evidencePath
        if(-not $architectureValidation.GateReady){$errors.Add("ATTEST_ARCHITECTURE_INVALID: $($architectureValidation.ErrorDetails -join ',')")}
        else{
            $architectureSequence=@($architectureValidation.ActIds)
            if(($architectureSequence -join '|') -cne ($sequence -join '|')){$errors.Add('ATTEST_ACT_SEQUENCE_ARCHITECTURE_MISMATCH')}
            $outputsByAct=@{};$inputsByAct=@{};$chainReadable=$true
            for($chainIndex=0;$chainIndex -le $index;$chainIndex++){
                $chainActId=$sequence[$chainIndex];$chainOutPath=Join-Path $project "_work\k3\acts\$chainActId\out.json";$chainInPath=Join-Path $project "_work\k3\continuity\$chainActId.in.json"
                try{$outputsByAct[$chainActId]=Get-Content -LiteralPath $chainOutPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$inputsByAct[$chainActId]=Get-Content -LiteralPath $chainInPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{$errors.Add("ATTEST_CONTINUITY_CHAIN_UNREADABLE: $chainActId");$chainReadable=$false;break}
            }
            if($chainReadable){
                $currentStructure=Get-SystemV7ContinuityOutStructuralState -ActId $ActId -ContinuityOut $outputsByAct[$ActId] -BlocksData $proseBinding.Blocks -ArchitectureData $architectureValidation.Architecture.Data;if(-not $currentStructure.Valid){$errors.Add("ATTEST_CONTINUITY_OUT_STRUCTURAL_INVALID: $($currentStructure.Errors -join ',')")}
                $orderedReplay=Get-SystemV7OrderedContinuityReplayState -ArchitectureData $architectureValidation.Architecture.Data -ThroughActId $ActId -OutputsByAct $outputsByAct -ContinuityInputsByAct $inputsByAct -RequireOutputs -RequireContinuityInputs
                if(-not $orderedReplay.Valid){$errors.Add("ATTEST_ORDERED_REPLAY_INVALID: $($orderedReplay.Errors -join ',')")}
                else{
                    $actualIn=$inputsByAct[$ActId]
                    if($index -eq 0){
                        $expectedIn=[ordered]@{schema='CONTINUITY_IN_V1';act_id=$ActId;source_act_id='NONE';source_act_sha256='NONE';source_attest_sha256='NONE';text_states=@();viewer_inferences=@();open_nq_ids=@();prepared_nr_ids=@();active_embargoes=@();world_state=@();bridge='START';opening_move_history=@();closing_move_history=@();emotional_pressure='START'}
                    }else{
                        $previousId=$sequence[$index-1];$previousState=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $previousId
                        if(-not $previousState.Valid){$errors.Add("ATTEST_PREVIOUS_SEMANTIC_STATE_INVALID: $previousId/$($previousState.Errors -join ',')");$expectedIn=$null}
                        else{$expectedIn=(ConvertTo-SystemV7CanonicalJson -Value $previousState.Data.next_continuity_in|ConvertFrom-Json -DateKind String -Depth 64);$expectedIn.source_attest_sha256=$previousState.Sha256}
                    }
                    if($null -ne $expectedIn -and (ConvertTo-SystemV7CanonicalJson -Value $actualIn) -cne (ConvertTo-SystemV7CanonicalJson -Value $expectedIn)){$errors.Add('ATTEST_CONTINUITY_IN_FULL_BINDING_MISMATCH')}
                    $packetPath=Join-Path $project "_work\k3\packets\$ActId.act-packet.json";$prosePath=Join-Path $project "_work\k3\acts\$ActId\prose.md"
                    try{$packet=Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$proseSha=(Get-FileHash -LiteralPath $prosePath -Algorithm SHA256).Hash
                        $expectedNext=Get-SystemV7ExpectedNextContinuityIn -ActId $ActId -NextActId $next -ContinuityIn $actualIn -ContinuityOut $outputsByAct[$ActId] -ActPacket $packet -ProseSha256 $proseSha -OpenNqIds @($orderedReplay.OpenNqIds) -PreparedNrIds @($orderedReplay.PreparedNrIds)
                        if($expectedNext.CanonicalJson -cne (ConvertTo-SystemV7CanonicalJson -Value $attest.next_continuity_in)){$errors.Add('ATTEST_NEXT_CONTINUITY_FULL_BINDING_MISMATCH')}
                    }catch{$errors.Add("ATTEST_NEXT_CONTINUITY_RECOMPUTE_FAILED: $($_.Exception.Message)")}
                }
            }
        }
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Data=$attest;State=$state;Path=$attestPath;Sha256=(Get-FileHash -LiteralPath $attestPath -Algorithm SHA256).Hash;NextAct=$next}
}

function New-SystemV7QACarryForwardRecord {
    param(
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][ValidateSet('EDITOR','VERIFY','COLD_READER')][string]$Lens,
        [Parameter(Mandatory)][string]$OldDraftSha256,
        [Parameter(Mandatory)][string]$NewDraftSha256,
        [Parameter(Mandatory)][string]$DiffSha256,
        [Parameter(Mandatory)][ValidateSet('TYPO_ONLY','STYLE_ONLY','CLAIM_PARAPHRASE','STRUCTURE','EVIDENCE','REVEAL','SCOPE')][string]$ChangeClass,
        [Parameter(Mandatory)][string]$ChangeScope,
        [Parameter(Mandatory)][string]$PriorProofRelative,
        [Parameter(Mandatory)][string]$PriorProofSha256,
        [Parameter(Mandatory)][string]$PriorOutputSha256,
        [Parameter(Mandatory)][string]$ImpactRelative,
        [Parameter(Mandatory)][string]$ImpactSha256,
        [Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$LensDependencySha256,
        [Parameter(Mandatory)][string]$RuleId,
        [Parameter(Mandatory)][string]$Justification,
        [string]$ImpactReviewRunId = 'NOT_REQUIRED',
        [string]$ImpactReviewReceiptRelative = 'BRAK',
        [string]$ImpactReviewReceiptSha256 = 'BRAK'
    )
    if ($ChangeClass -cne 'TYPO_ONLY' -and $ImpactReviewRunId -ceq 'NOT_REQUIRED') { throw 'IMPACT_REVIEW_REQUIRED_FOR_NON_MECHANICAL_CHANGE' }
    $record = [ordered]@{
        schema='SYSTEM_V7_QA_CARRYFORWARD_V2'; workflow_revision=$script:SystemV7NarrativeWorkflowRevision; project_origin_sha256=$ProjectOriginSha256
        lens=$Lens; old_draft_sha256=$OldDraftSha256; new_draft_sha256=$NewDraftSha256; diff_sha256=$DiffSha256; change_class=$ChangeClass
        change_scope=$ChangeScope; prior_proof_relative=$PriorProofRelative; prior_proof_sha256=$PriorProofSha256; prior_output_sha256=$PriorOutputSha256
        impact_relative=$ImpactRelative;impact_sha256=$ImpactSha256;lens_dependency_sha256=$LensDependencySha256;rule_id=$RuleId; justification=$Justification; impact_review_run_id=$ImpactReviewRunId
        impact_review_receipt_relative=$ImpactReviewReceiptRelative;impact_review_receipt_sha256=$ImpactReviewReceiptSha256;status='VALID'; created_at_utc=[DateTime]::UtcNow.ToString('o')
    }
    $record['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $record)
    return [pscustomobject]$record
}

function Get-SystemV7K4LensBundleDependencyFingerprintState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][ValidateSet('EDITOR','VERIFY','COLD_READER')][string]$Lens,[Parameter(Mandatory)][object]$BundleData)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath);$items=[Collections.Generic.List[object]]::new()
    if([string]$BundleData.run_type -cne $Lens){$errors.Add('K4_DEPENDENCY_BUNDLE_LENS_MISMATCH')}
    $entryByRole=@{};foreach($entry in @($BundleData.entries)){$role=[string]$entry.content_role;if($entryByRole.ContainsKey($role)){$errors.Add("K4_DEPENDENCY_ROLE_DUPLICATE: $role")}else{$entryByRole[$role]=$entry}}
    $addEntry={param([string]$Role)if(-not $entryByRole.ContainsKey($Role)){$errors.Add("K4_DEPENDENCY_ROLE_MISSING: $Role");return};$entry=$entryByRole[$Role];$items.Add([ordered]@{name=$Role;sha256=[string]$entry.sha256})}
    $addJsonSemantic={param([string]$Role)if(-not $entryByRole.ContainsKey($Role)){$errors.Add("K4_DEPENDENCY_ROLE_MISSING: $Role");return};try{$path=Join-Path $project ([string]$entryByRole[$Role].bundle_relative);$value=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$items.Add([ordered]@{name=$Role;sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $value))})}catch{$errors.Add("K4_DEPENDENCY_JSON_INVALID: $Role/$($_.Exception.Message)")}}
    if($Lens -ceq 'EDITOR'){
        foreach($role in @('FUNDAMENT','ARCHITECTURE','STORY_SPINE')){&$addEntry $role};&$addJsonSemantic 'NQ_NR_VC';&$addJsonSemantic 'SEMANTIC_PREFLIGHT';foreach($role in @('VOICE_RULES','VOICE_EXEMPLARS','EDITOR_CRITERIA','EDITOR_OUTPUT_SCHEMA')){&$addEntry $role}
        if(-not $entryByRole.ContainsKey('CONTINUITY_CHAIN')){$errors.Add('K4_DEPENDENCY_ROLE_MISSING: CONTINUITY_CHAIN')}
        else{
            try{$chainPath=Join-Path $project ([string]$entryByRole.CONTINUITY_CHAIN.bundle_relative);$chain=Get-Content -LiteralPath $chainPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$records=@($chain.records|ForEach-Object{[ordered]@{act_id=[string]$_.act_id;sha256=[string]$_.sha256}});if($records.Count -eq 0){throw 'empty'};$items.Add([ordered]@{name='CONTINUITY_ATTESTS';sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $records))})}catch{$errors.Add("K4_DEPENDENCY_CONTINUITY_CHAIN_INVALID: $($_.Exception.Message)")}
        }
    }elseif($Lens -ceq 'VERIFY'){
        foreach($role in @('EVIDENCE_BASE','SOURCE_FILES')){&$addEntry $role};&$addJsonSemantic 'SOURCE_LOCATORS';foreach($role in @('VERIFY_CRITERIA','VERIFY_OUTPUT_SCHEMA')){&$addEntry $role}
    }else{
        foreach($role in @('COLD_READER_QUESTIONS','COLD_READER_OUTPUT_SCHEMA')){&$addEntry $role}
    }
    $core=[ordered]@{schema='K4_LENS_DEPENDENCY_FINGERPRINT_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;lens=$Lens;items=@($items)}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Core=[pscustomobject]$core;Sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $core))}
}

function Get-SystemV7K4LensLiveDependencyFingerprintState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][ValidateSet('EDITOR','VERIFY','COLD_READER')][string]$Lens)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath);$systemRoot=Split-Path -Parent $PSScriptRoot;$items=[Collections.Generic.List[object]]::new()
    $addFile={param([string]$Name,[string]$Path)try{$full=[IO.Path]::GetFullPath($Path);$containmentRoot=if($full.StartsWith($project,[StringComparison]::OrdinalIgnoreCase)){$project}else{$systemRoot};$null=Get-SystemV7NarrativeRelativePath -Root $containmentRoot -Path $full;if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw 'missing'};$items.Add([ordered]@{name=$Name;sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash})}catch{$errors.Add("K4_DEPENDENCY_FILE_INVALID: $Name/$($_.Exception.Message)")}}
    if($Lens -ceq 'EDITOR'){
        &$addFile 'FUNDAMENT' (Join-Path $project '00-fundament-projektu.md');&$addFile 'ARCHITECTURE' (Join-Path $project '02-architektura-odcinka.md')
        &$addFile 'STORY_SPINE' (Join-Path $project '_work\k3\prefix\PROJECT_STORY_SPINE.json')
        try{$architecture=Get-SystemV7NarrativeArchitecture -Path (Join-Path $project '02-architektura-odcinka.md');$registries=[ordered]@{schema='K4_NQ_NR_VC_PROJECTION_V1';questions=@($architecture.Data.questions);reveals=@($architecture.Data.reveals);viewer_contacts=@($architecture.Data.viewer_contacts)};$items.Add([ordered]@{name='NQ_NR_VC';sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $registries))})}catch{$errors.Add("K4_DEPENDENCY_NQ_NR_VC_INVALID: $($_.Exception.Message)")}
        try{
            $metaForSemantic=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8
            $semanticArchitecture=Get-SystemV7NarrativeArchitecture -Path (Join-Path $project '02-architektura-odcinka.md')
            $semanticBlocks=[Collections.Generic.List[object]]::new()
            $semanticSequence=@((Get-SystemV7NarrativeMetaField -Text $metaForSemantic -Name 'NARRATIVE_ACT_SEQUENCE') -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_})
            foreach($semanticActId in $semanticSequence){
                $semanticBlocksPath=Join-Path $project "_work\k3\acts\$semanticActId\blocks.json"
                if(-not(Test-Path -LiteralPath $semanticBlocksPath -PathType Leaf)){throw "missing blocks $semanticActId"}
                $semanticActBlocks=Get-Content -LiteralPath $semanticBlocksPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64
                foreach($semanticBlock in @($semanticActBlocks.blocks)){$semanticBlocks.Add([pscustomobject]@{act_id=$semanticActId;block_id=[string]$semanticBlock.block_id;narrative_refs=@([string[]]@($semanticBlock.narrative_refs));prose=[string]$semanticBlock.prose})}
            }
            if($semanticBlocks.Count -eq 0){throw 'empty blocks'}
            $semanticDraftSha=(Get-FileHash -LiteralPath (Join-Path $project '03-draft.md') -Algorithm SHA256).Hash
            $semanticVoice=Get-Content -LiteralPath (Join-Path $project '_work\k3\prefix\VOICE_EXEMPLARS.md') -Raw -Encoding UTF8
            $semanticState=Get-SystemV7NarrativeSemanticPreflightState -ArchitectureData $semanticArchitecture.Data -Blocks @($semanticBlocks) -VoiceExemplarsText $semanticVoice -DraftSha256 $semanticDraftSha
            if(-not $semanticState.Valid){throw ($semanticState.Errors -join '; ')}
            $items.Add([ordered]@{name='SEMANTIC_PREFLIGHT';sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $semanticState.Data))})
        }catch{$errors.Add("K4_DEPENDENCY_SEMANTIC_PREFLIGHT_LIVE_INVALID: $($_.Exception.Message)")}
        &$addFile 'VOICE_RULES' (Join-Path $project '_work\k3\prefix\VOICE_RULES.md');&$addFile 'VOICE_EXEMPLARS' (Join-Path $project '_work\k3\prefix\VOICE_EXEMPLARS.md')
        &$addFile 'EDITOR_CRITERIA' (Join-Path $systemRoot '_SYSTEM\NARRATIVE\EDITOR-CRITERIA.md');&$addFile 'EDITOR_OUTPUT_SCHEMA' (Join-Path $systemRoot '_SYSTEM\NARRATIVE\EDITOR-OUTPUT-SCHEMA.md')
        try{$meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8;$sequence=@((Get-SystemV7NarrativeMetaField -Text $meta -Name 'NARRATIVE_ACT_SEQUENCE') -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_});$records=[Collections.Generic.List[object]]::new();foreach($actId in $sequence){$path=Join-Path $project "_work\k3\continuity\$actId.attest.json";if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "missing $actId"};$records.Add([ordered]@{act_id=$actId;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash})};if($records.Count -eq 0){throw 'empty'};$items.Add([ordered]@{name='CONTINUITY_ATTESTS';sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($records)))})}catch{$errors.Add("K4_DEPENDENCY_CONTINUITY_LIVE_INVALID: $($_.Exception.Message)")}
    }elseif($Lens -ceq 'VERIFY'){
        &$addFile 'EVIDENCE_BASE' (Join-Path $project '01-baza-dowodow.md')
        try{$source=Join-Path $project 'sources';$null=Assert-SystemV7TreeNoReparse -RootPath $source -ContainmentRoot $project;$prefix=[IO.Path]::GetFullPath($source).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;$rows=[Collections.Generic.List[object]]::new();$paths=[string[]]@(Get-ChildItem -LiteralPath $source -File -Recurse -Force|ForEach-Object{$_.FullName});[Array]::Sort($paths,[StringComparer]::Ordinal);foreach($path in $paths){$relative=$path.Substring($prefix.Length).Replace('\','/');if($relative -match '(^|/)(?:__pycache__|\.git)(/|$)'){continue};$rows.Add([ordered]@{relative=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $path).Length})};$items.Add([ordered]@{name='SOURCE_FILES';sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($rows)))})}catch{$errors.Add("K4_DEPENDENCY_SOURCE_TREE_INVALID: $($_.Exception.Message)")}
        try{$registry=Get-SystemV7EvidenceRegistry -EvidencePath (Join-Path $project '01-baza-dowodow.md');$locatorValue=[ordered]@{schema='SOURCE_LOCATORS_V1';evidence_sha256=$registry.EvidenceSha256;cards=@($registry.Cards.Values|ForEach-Object{[ordered]@{p_id=$_.p_id;source_id=$_.source_id;locator=$_.locator;qa_k1=$_.qa_k1}})};$items.Add([ordered]@{name='SOURCE_LOCATORS';sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $locatorValue))})}catch{$errors.Add("K4_DEPENDENCY_SOURCE_LOCATORS_INVALID: $($_.Exception.Message)")}
        &$addFile 'VERIFY_CRITERIA' (Join-Path $systemRoot '_SYSTEM\NARRATIVE\VERIFY-CRITERIA.md');&$addFile 'VERIFY_OUTPUT_SCHEMA' (Join-Path $systemRoot '_SYSTEM\NARRATIVE\VERIFY-OUTPUT-SCHEMA.md')
    }else{
        &$addFile 'COLD_READER_QUESTIONS' (Join-Path $systemRoot '_SYSTEM\NARRATIVE\COLD-READER-QUESTIONS.md');&$addFile 'COLD_READER_OUTPUT_SCHEMA' (Join-Path $systemRoot '_SYSTEM\NARRATIVE\COLD-READER-OUTPUT-SCHEMA.md')
    }
    $core=[ordered]@{schema='K4_LENS_DEPENDENCY_FINGERPRINT_V1';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;lens=$Lens;items=@($items)}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Core=[pscustomobject]$core;Sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $core))}
}

function Get-SystemV7QACarryForwardState {
    param([Parameter(Mandatory)][string]$ProjectPath, [Parameter(Mandatory)][string]$ReceiptPath, [string]$ExpectedLens, [string]$ExpectedNewDraftSha256, [Collections.Generic.HashSet[string]]$Visited, [int]$Depth=0)
    $errors=[Collections.Generic.List[string]]::new()
    if($Depth -gt 32){return [pscustomobject]@{Valid=$false;Errors=@('CARRYFORWARD_CHAIN_TOO_DEEP');Data=$null}}
    if($null -eq $Visited){$Visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
    $full=[IO.Path]::GetFullPath($ReceiptPath)
    if(-not $Visited.Add($full)){return [pscustomobject]@{Valid=$false;Errors=@('CARRYFORWARD_CYCLE');Data=$null}}
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('CARRYFORWARD_MISSING');Data=$null}}
    try{$data=Get-Content -LiteralPath $full -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32}catch{return [pscustomobject]@{Valid=$false;Errors=@('CARRYFORWARD_INVALID_JSON');Data=$null}}
    $expectedFields=@('schema','workflow_revision','project_origin_sha256','lens','old_draft_sha256','new_draft_sha256','diff_sha256','change_class','change_scope','prior_proof_relative','prior_proof_sha256','prior_output_sha256','impact_relative','impact_sha256','lens_dependency_sha256','rule_id','justification','impact_review_run_id','impact_review_receipt_relative','impact_review_receipt_sha256','status','created_at_utc','binding_sha256')
    if(@(Compare-Object -ReferenceObject $expectedFields -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0 -or @($data.PSObject.Properties.Name).Count -ne $expectedFields.Count){$errors.Add('CARRYFORWARD_FIELDS_INVALID')}
    $copy=[ordered]@{};foreach($p in $data.PSObject.Properties){if($p.Name -cne 'binding_sha256'){$copy[$p.Name]=$p.Value}}
    if((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)) -cne [string]$data.binding_sha256){$errors.Add('CARRYFORWARD_BINDING_MISMATCH')}
    if([string]$data.schema -cne 'SYSTEM_V7_QA_CARRYFORWARD_V2' -or [string]$data.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$data.status -cne 'VALID' -or [string]$data.lens_dependency_sha256 -notmatch '^[A-F0-9]{64}$'){$errors.Add('CARRYFORWARD_SCHEMA_INVALID')}
    if($ExpectedLens -and [string]$data.lens -cne $ExpectedLens){$errors.Add('CARRYFORWARD_LENS_MISMATCH')}
    if($ExpectedNewDraftSha256 -and [string]$data.new_draft_sha256 -cne $ExpectedNewDraftSha256){$errors.Add('CARRYFORWARD_DRAFT_MISMATCH')}
    if([string]$data.change_class -cne 'TYPO_ONLY' -and [string]$data.impact_review_run_id -ceq 'NOT_REQUIRED'){$errors.Add('CARRYFORWARD_MISSING_IMPACT_REVIEW')}
    $project=[IO.Path]::GetFullPath($ProjectPath);$prior=Join-Path $project ([string]$data.prior_proof_relative)
    $origin=Get-SystemV7ProjectOriginState -ProjectPath $project;if(-not $origin.Valid -or [string]$origin.Sha256 -cne [string]$data.project_origin_sha256){$errors.Add('CARRYFORWARD_ORIGIN_MISMATCH')}
    if($Depth -eq 0){$liveDependency=Get-SystemV7K4LensLiveDependencyFingerprintState -ProjectPath $project -Lens ([string]$data.lens);if(-not $liveDependency.Valid){$errors.Add("CARRYFORWARD_LIVE_DEPENDENCY_INVALID: $($liveDependency.Errors -join ',')")}elseif([string]$liveDependency.Sha256 -cne [string]$data.lens_dependency_sha256){$errors.Add('CARRYFORWARD_DEPENDENCY_CHANGED')}}
    try{$impact=Join-Path $project ([string]$data.impact_relative);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $impact}catch{$impact=$null;$errors.Add('CARRYFORWARD_IMPACT_PATH_INVALID')}
    if($impact){$impactState=Get-SystemV7QAImpactState -ProjectPath $project -ImpactPath $impact -HistoricalNewDraft:($Depth -gt 0);if(-not $impactState.Valid){$errors.Add("CARRYFORWARD_IMPACT_INVALID: $($impactState.Errors -join ',')")}elseif([string]$impactState.Sha256 -cne [string]$data.impact_sha256 -or [string]$impactState.Data.diff_sha256 -cne [string]$data.diff_sha256 -or [string]$impactState.Data.old_draft_sha256 -cne [string]$data.old_draft_sha256 -or [string]$impactState.Data.new_draft_sha256 -cne [string]$data.new_draft_sha256){$errors.Add('CARRYFORWARD_IMPACT_BINDING_MISMATCH')}elseif([string]$data.change_class -ceq 'TYPO_ONLY' -and ([string]$impactState.Data.change_class -cne 'BYTE_IDENTICAL' -or [string]$impactState.Data.decisions.([string]$data.lens) -cne 'CARRYFORWARD_ALLOWED')){$errors.Add('CARRYFORWARD_MECHANICAL_CLASS_INVALID')}elseif([string]$data.change_class -cne 'TYPO_ONLY' -and [string]$impactState.Data.change_class -cne 'SEMANTIC_REVIEW_REQUIRED'){$errors.Add('CARRYFORWARD_SEMANTIC_CLASS_INVALID')}}
    if([string]$data.change_class -cne 'TYPO_ONLY'){
        try{$reviewPath=Join-Path $project ([string]$data.impact_review_receipt_relative);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $reviewPath}catch{$reviewPath=$null;$errors.Add('CARRYFORWARD_REVIEW_PATH_INVALID')}
        if($reviewPath){$review=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $reviewPath -ExpectedRunType 'QA_IMPACT_REVIEW' -HistoricalQAImpact:($Depth -gt 0);if(-not $review.Valid){$errors.Add("CARRYFORWARD_REVIEW_INVALID: $($review.Errors -join ',')")}elseif([string]$review.Sha256 -cne [string]$data.impact_review_receipt_sha256 -or [string]$review.Data.run_id -cne [string]$data.impact_review_run_id){$errors.Add('CARRYFORWARD_REVIEW_BINDING_MISMATCH')}else{$reviewBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath (Join-Path $project ([string]$review.Data.input_manifest_relative));$reviewOutputState=if($reviewBundle.Valid){Get-SystemV7QAImpactOutputState -ProjectPath $project -OutputPath (Join-Path $project ([string]$review.Data.output_relative)) -BundleData $reviewBundle.Data -HistoricalImpact:($Depth -gt 0)}else{$null};if($null -eq $reviewOutputState -or -not $reviewOutputState.Valid -or [string]$reviewOutputState.Impact.diff_sha256 -cne [string]$data.diff_sha256 -or [string]$reviewOutputState.Decisions.([string]$data.lens) -cne 'CARRYFORWARD_ALLOWED'){$errors.Add('CARRYFORWARD_REVIEW_DOES_NOT_ALLOW')}}}
    }elseif([string]$data.impact_review_receipt_relative -cne 'BRAK' -or [string]$data.impact_review_receipt_sha256 -cne 'BRAK'){$errors.Add('CARRYFORWARD_UNEXPECTED_REVIEW_BINDING')}
    try{$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $prior}catch{$errors.Add('CARRYFORWARD_PRIOR_PATH_INVALID')}
    if(-not(Test-Path -LiteralPath $prior -PathType Leaf)){$errors.Add('CARRYFORWARD_PRIOR_MISSING')}
    elseif((Get-FileHash -LiteralPath $prior -Algorithm SHA256).Hash -cne [string]$data.prior_proof_sha256){$errors.Add('CARRYFORWARD_PRIOR_HASH_MISMATCH')}
    elseif([IO.Path]::GetExtension($prior) -ceq '.json'){
        try{$priorData=Get-Content -LiteralPath $prior -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32}catch{$priorData=$null}
        if($priorData -and [string]$priorData.schema -ceq 'SYSTEM_V7_QA_CARRYFORWARD_V2'){
            $priorState=Get-SystemV7QACarryForwardState -ProjectPath $project -ReceiptPath $prior -ExpectedLens ([string]$data.lens) -ExpectedNewDraftSha256 ([string]$data.old_draft_sha256) -Visited $Visited -Depth ($Depth+1)
            if(-not $priorState.Valid){foreach($e in $priorState.Errors){$errors.Add("PRIOR_$e")}}
            elseif([string]$priorState.Data.prior_output_sha256 -cne [string]$data.prior_output_sha256){$errors.Add('CARRYFORWARD_PRIOR_OUTPUT_MISMATCH')}
            elseif([string]$priorState.Data.lens_dependency_sha256 -cne [string]$data.lens_dependency_sha256){$errors.Add('CARRYFORWARD_PRIOR_DEPENDENCY_MISMATCH')}
        } elseif($priorData -and [string]$priorData.schema -ceq 'SYSTEM_V7_NARRATIVE_RUN_RECEIPT_V1') {
            $runState=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $prior -ExpectedRunType ([string]$data.lens) -ExpectedDraftSha256 ([string]$data.old_draft_sha256)
            if(-not $runState.Valid){foreach($e in $runState.Errors){$errors.Add("PRIOR_$e")}}
            elseif([string]$runState.Data.output_sha256 -cne [string]$data.prior_output_sha256){$errors.Add('CARRYFORWARD_PRIOR_OUTPUT_MISMATCH')}
            else{$priorBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath (Join-Path $project ([string]$runState.Data.input_manifest_relative));$priorDependency=if($priorBundle.Valid){Get-SystemV7K4LensBundleDependencyFingerprintState -ProjectPath $project -Lens ([string]$data.lens) -BundleData $priorBundle.Data}else{$null};if($null -eq $priorDependency -or -not $priorDependency.Valid -or [string]$priorDependency.Sha256 -cne [string]$data.lens_dependency_sha256){$errors.Add('CARRYFORWARD_PRIOR_DEPENDENCY_MISMATCH')}}
        } else {$errors.Add('CARRYFORWARD_PRIOR_SCHEMA_INVALID')}
    }
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Data=$data;Path=$full;Sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash}
}

function Get-SystemV7K4ContinuityChainState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$DraftSha256)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath);$path=Join-Path $project "_work\k4\inputs\continuity-chain-$DraftSha256.json"
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('K4_CONTINUITY_CHAIN_MISSING');Path=$path}}
    try{$raw=Get-Content -LiteralPath $path -Raw -Encoding UTF8;$data=$raw|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('K4_CONTINUITY_CHAIN_INVALID_JSON');Path=$path}}
    if((ConvertTo-SystemV7CanonicalJson -Value $data) -cne (ConvertTo-SystemV7LfText -Text $raw)){$errors.Add('K4_CONTINUITY_CHAIN_NOT_CANONICAL')}
    $fields=@('schema','draft_sha256','records');if(@(Compare-Object -ReferenceObject $fields -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0 -or @($data.PSObject.Properties.Name).Count -ne $fields.Count -or [string]$data.schema -cne 'CONTINUITY_CHAIN_V1' -or [string]$data.draft_sha256 -cne $DraftSha256){$errors.Add('K4_CONTINUITY_CHAIN_FIELDS_OR_IDENTITY_INVALID')}
    try{$meta=Get-Content -LiteralPath (Join-Path $project 'meta.md') -Raw -Encoding UTF8;$sequence=@((Get-SystemV7NarrativeMetaField -Text $meta -Name 'NARRATIVE_ACT_SEQUENCE') -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_})}catch{$sequence=@();$errors.Add('K4_CONTINUITY_CHAIN_META_UNREADABLE')}
    $actualActs=[Collections.Generic.List[string]]::new()
    foreach($entry in @($data.records)){$entryFields=@('act_id','relative','sha256','record');$actId=[string]$entry.act_id;if(@(Compare-Object -ReferenceObject $entryFields -DifferenceObject @($entry.PSObject.Properties.Name)).Count -gt 0 -or @($entry.PSObject.Properties.Name).Count -ne $entryFields.Count){$errors.Add("K4_CONTINUITY_CHAIN_ENTRY_FIELDS_INVALID: $actId");continue};$actualActs.Add($actId);$expectedRelative="_work/k3/continuity/$actId.attest.json";if([string]$entry.relative -cne $expectedRelative -or [string]$entry.sha256 -notmatch '^[A-F0-9]{64}$'){$errors.Add("K4_CONTINUITY_CHAIN_ENTRY_IDENTITY_INVALID: $actId");continue};$attestPath=Join-Path $project $expectedRelative;if(-not(Test-Path -LiteralPath $attestPath -PathType Leaf) -or (Get-FileHash -LiteralPath $attestPath -Algorithm SHA256).Hash -cne [string]$entry.sha256){$errors.Add("K4_CONTINUITY_CHAIN_ENTRY_STALE: $actId");continue};$attest=Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $actId;if(-not $attest.Valid){$errors.Add("K4_CONTINUITY_CHAIN_ATTEST_INVALID: $actId/$($attest.Errors -join ',')")}elseif((ConvertTo-SystemV7CanonicalJson -Value $entry.record) -cne (ConvertTo-SystemV7CanonicalJson -Value $attest.Data)){$errors.Add("K4_CONTINUITY_CHAIN_RECORD_MISMATCH: $actId")}}
    if(($actualActs -join '|') -cne ($sequence -join '|')){$errors.Add('K4_CONTINUITY_CHAIN_SEQUENCE_MISMATCH')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Data=$data;Path=$path;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}

function Get-SystemV7K4LensProofResolutionState {
    param([Parameter(Mandatory)][string]$ProjectPath,[Parameter(Mandatory)][ValidateSet('EDITOR','VERIFY','COLD_READER')][string]$Lens,[Parameter(Mandatory)][string]$ProofPath,[Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$DraftSha256)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    try{$path=[IO.Path]::GetFullPath($ProofPath);$relative=Get-SystemV7NarrativeRelativePath -Root $project -Path $path}catch{return [pscustomobject]@{Valid=$false;Errors=@('K4_PROOF_PATH_INVALID')}}
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('K4_PROOF_MISSING');Path=$path}}
    try{$data=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('K4_PROOF_INVALID_JSON');Path=$path}}
    $kind='';$outputSha='';$taskId='';$report=''
    if([string]$data.schema -ceq 'SYSTEM_V7_NARRATIVE_RUN_RECEIPT_V1'){
        $kind='RUN';$run=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $path -ExpectedRunType $Lens -ExpectedDraftSha256 $DraftSha256 -RequireLiveInputs
        if(-not $run.Valid){foreach($problem in $run.Errors){$errors.Add("K4_RUN_PROOF_INVALID: $problem")}}
        else{$runBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath (Join-Path $project ([string]$run.Data.input_manifest_relative)) -RequireLiveSource;if(-not $runBundle.Valid){$errors.Add('K4_RUN_BUNDLE_NOT_LIVE')}else{$outputPath=Join-Path $project ([string]$run.Data.output_relative);$lensOutput=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens $Lens -OutputPath $outputPath -ExpectedDraftSha256 $DraftSha256 -BundleData $runBundle.Data;if(-not $lensOutput.Valid){foreach($problem in $lensOutput.Errors){$errors.Add("K4_RUN_OUTPUT_INVALID: $problem")}}elseif([string]$lensOutput.Verdict -cne 'PASS'){$errors.Add('K4_RUN_OUTPUT_NOT_PASS')}else{$outputSha=[string]$run.Data.output_sha256;$taskId=[string]$run.Data.task_id;$report=[string]$lensOutput.NormalizedReport}}}
    }elseif([string]$data.schema -ceq 'SYSTEM_V7_QA_CARRYFORWARD_V2'){
        $kind='CARRYFORWARD';$carry=Get-SystemV7QACarryForwardState -ProjectPath $project -ReceiptPath $path -ExpectedLens $Lens -ExpectedNewDraftSha256 $DraftSha256
        if(-not $carry.Valid){foreach($problem in $carry.Errors){$errors.Add("K4_CARRYFORWARD_INVALID: $problem")}}
        else{
            $cursor=$path;$visited=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$rootRun=$null
            for($depth=0;$depth -le 32;$depth++){if(-not $visited.Add($cursor)){break};try{$cursorData=Get-Content -LiteralPath $cursor -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 32}catch{break};if([string]$cursorData.schema -ceq 'SYSTEM_V7_NARRATIVE_RUN_RECEIPT_V1'){$rootRun=Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $cursor -ExpectedRunType $Lens -ExpectedOutputSha256 ([string]$carry.Data.prior_output_sha256);break};if([string]$cursorData.schema -cne 'SYSTEM_V7_QA_CARRYFORWARD_V2'){break};try{$cursor=[IO.Path]::GetFullPath((Join-Path $project ([string]$cursorData.prior_proof_relative)));$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $cursor}catch{break}}
            if($null -eq $rootRun -or -not $rootRun.Valid){$errors.Add('K4_CARRYFORWARD_ROOT_RUN_INVALID')}
            else{
                $rootBundle=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath (Join-Path $project ([string]$rootRun.Data.input_manifest_relative))
                $rootIdentity=if($rootBundle.Valid){Get-SystemV7K4BundleDraftIdentityState -Lens $Lens -BundleData $rootBundle.Data}else{$null}
                if(-not $rootBundle.Valid -or $null -eq $rootIdentity -or -not $rootIdentity.Valid){$errors.Add('K4_CARRYFORWARD_ROOT_BUNDLE_IDENTITY_INVALID')}
                else{$rootOutput=Join-Path $project ([string]$rootRun.Data.output_relative);$rootLens=Get-SystemV7K4LensOutputState -ProjectPath $project -Lens $Lens -OutputPath $rootOutput -ExpectedDraftSha256 ([string]$rootIdentity.Sha256) -BundleData $rootBundle.Data;if(-not $rootLens.Valid -or [string]$rootLens.Verdict -cne 'PASS'){$errors.Add('K4_CARRYFORWARD_ROOT_OUTPUT_INVALID')}else{$outputSha=[string]$carry.Data.prior_output_sha256;$taskId=[string]$rootRun.Data.task_id;$report="LENS: $Lens`nVERDICT: PASS`nDRAFT_SHA256: $DraftSha256`nPROOF_KIND: CARRYFORWARD`nCARRYFORWARD_RECEIPT: $relative`nDIFF_SHA256: $([string]$carry.Data.diff_sha256)`nDEPENDENCY_SHA256: $([string]$carry.Data.lens_dependency_sha256)`nNOTE: Wynik przeniesiono po deterministycznym QA impact i niezmienionym odcisku zależności.`n"}}
            }
        }
    }else{$errors.Add('K4_PROOF_SCHEMA_UNSUPPORTED')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Kind=$kind;Path=$path;Relative=$relative;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;OutputSha256=$outputSha;TaskId=$taskId;Report=$report;Data=$data}
}

function Get-SystemV7K4ProofSetState {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ProofSetSha256,
        [string]$ExpectedDraftSha256
    )
    $errors=[Collections.Generic.List[string]]::new()
    $project=[IO.Path]::GetFullPath($ProjectPath)
    if($ProofSetSha256 -notmatch '^[A-Fa-f0-9]{64}$'){return [pscustomobject]@{Valid=$false;Errors=@('K4_PROOF_SET_SHA_INVALID');Data=$null}}
    $path=Join-Path $project "_work\k4\proof-sets\$($ProofSetSha256.ToUpperInvariant()).json"
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('K4_PROOF_SET_MISSING');Data=$null;Path=$path}}
    try{$data=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('K4_PROOF_SET_INVALID_JSON');Data=$null;Path=$path}}
    $expected=@('schema','workflow_revision','project_origin_sha256','draft_sha256','continuity_chain_sha256','editor','verify','cold_reader','status','proof_set_sha256')
    if(@(Compare-Object -ReferenceObject $expected -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0 -or @($data.PSObject.Properties.Name).Count -ne $expected.Count){$errors.Add('K4_PROOF_SET_FIELDS_INVALID')}
    if([string]$data.schema -cne 'K4_PROOF_SET_V2' -or [string]$data.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$data.status -cne 'PASS'){$errors.Add('K4_PROOF_SET_SCHEMA_OR_STATUS_INVALID')}
    if([string]$data.proof_set_sha256 -cne $ProofSetSha256.ToUpperInvariant()){$errors.Add('K4_PROOF_SET_DECLARED_SHA_MISMATCH')}
    $core=[ordered]@{schema=$data.schema;workflow_revision=$data.workflow_revision;project_origin_sha256=$data.project_origin_sha256;draft_sha256=$data.draft_sha256;continuity_chain_sha256=$data.continuity_chain_sha256;editor=$data.editor;verify=$data.verify;cold_reader=$data.cold_reader;status=$data.status}
    if((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $core)) -cne $ProofSetSha256.ToUpperInvariant()){$errors.Add('K4_PROOF_SET_BINDING_MISMATCH')}
    if($ExpectedDraftSha256 -and [string]$data.draft_sha256 -cne $ExpectedDraftSha256.ToUpperInvariant()){$errors.Add('K4_PROOF_SET_DRAFT_MISMATCH')}
    $origin=Get-SystemV7ProjectOriginState -ProjectPath $project
    if(-not $origin.Valid -or [string]$data.project_origin_sha256 -cne [string]$origin.Sha256){$errors.Add('K4_PROOF_SET_ORIGIN_MISMATCH')}
    $taskIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$resolutions=[ordered]@{}
    foreach($lensName in @('editor','verify','cold_reader')){
        $lens=$data.$lensName;$runType=if($lensName -ceq 'editor'){'EDITOR'}elseif($lensName -ceq 'verify'){'VERIFY'}else{'COLD_READER'}
        $lensFields=@('proof_kind','proof_relative','proof_sha256','output_sha256')
        if($null -eq $lens -or @(Compare-Object -ReferenceObject $lensFields -DifferenceObject @($lens.PSObject.Properties.Name)).Count -gt 0 -or @($lens.PSObject.Properties.Name).Count -ne $lensFields.Count){$errors.Add("K4_LENS_FIELDS_INVALID: $runType");continue}
        try{$proofPath=Join-Path $project ([string]$lens.proof_relative);$null=Get-SystemV7NarrativeRelativePath -Root $project -Path $proofPath}catch{$errors.Add("K4_LENS_PROOF_PATH_INVALID: $runType");continue}
        $resolution=Get-SystemV7K4LensProofResolutionState -ProjectPath $project -Lens $runType -ProofPath $proofPath -DraftSha256 ([string]$data.draft_sha256)
        if(-not $resolution.Valid){$errors.Add("K4_LENS_PROOF_INVALID: $runType/$($resolution.Errors -join ',')");continue};if([string]$lens.proof_kind -cne [string]$resolution.Kind -or [string]$lens.proof_sha256 -cne [string]$resolution.Sha256 -or [string]$lens.output_sha256 -cne [string]$resolution.OutputSha256){$errors.Add("K4_LENS_PROOF_BINDING_MISMATCH: $runType")};if(-not $taskIds.Add([string]$resolution.TaskId)){$errors.Add('K4_TASK_ID_COLLISION')};$resolutions[$runType]=$resolution
    }
    $chain=Get-SystemV7K4ContinuityChainState -ProjectPath $project -DraftSha256 ([string]$data.draft_sha256);if(-not $chain.Valid){$errors.Add("K4_CONTINUITY_CHAIN_INVALID: $($chain.Errors -join ',')")}elseif([string]$chain.Sha256 -cne [string]$data.continuity_chain_sha256){$errors.Add('K4_CONTINUITY_CHAIN_SHA_MISMATCH')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Data=$data;Path=$path;FileSha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;Sha256=$ProofSetSha256.ToUpperInvariant();Resolutions=[pscustomobject]$resolutions;Chain=$chain}
}

function New-SystemV7K5ApprovalV2Record {
    param(
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][string]$FinalSha256,
        [Parameter(Mandatory)][string]$DraftSha256,
        [Parameter(Mandatory)][string]$QaSha256,
        [Parameter(Mandatory)][string]$FactCheckSha256,
        [Parameter(Mandatory)][string]$K4ProofSetSha256,
        [Parameter(Mandatory)][string]$K4ProofSetFileSha256,
        [Parameter(Mandatory)][string]$ContinuityChainSha256,
        [Parameter(Mandatory)][ValidateSet('GUIDE','HARD_MAX')][string]$DurationMode,
        [Parameter(Mandatory)][int]$FinalWordCount,
        [Parameter(Mandatory)][int]$MaximumWords,
        [Parameter(Mandatory)][ValidateSet('BYTE_IDENTICAL')][string]$ChangeClass,
        [Parameter(Mandatory)][string]$ApprovalNote,
        [Parameter(Mandatory)][string]$CreatedAtUtc
    )
    $record=[ordered]@{
        schema='SYSTEM_V7_K5_APPROVAL_V2';workflow_revision=$script:SystemV7NarrativeWorkflowRevision;actor='DAWID';attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'
        project_origin_sha256=$ProjectOriginSha256;final_sha256=$FinalSha256;draft_sha256=$DraftSha256;qa_sha256=$QaSha256;factcheck_sha256=$FactCheckSha256
        k4_proof_set_sha256=$K4ProofSetSha256;k4_proof_set_file_sha256=$K4ProofSetFileSha256;continuity_chain_sha256=$ContinuityChainSha256
        duration_mode=$DurationMode;final_word_count=$FinalWordCount;maximum_words=$MaximumWords;duration_verdict='PASS';change_class=$ChangeClass;approval_note=$ApprovalNote
        created_at_utc=$CreatedAtUtc
    }
    $record['binding_sha256']=Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $record)
    [pscustomobject]$record
}

function Get-SystemV7K5ApprovalV2State {
    param([Parameter(Mandatory)][string]$ProjectPath)
    $errors=[Collections.Generic.List[string]]::new();$project=[IO.Path]::GetFullPath($ProjectPath)
    $finalPath=Join-Path $project '05-FINAL-SCRIPT.md'
    if(-not(Test-Path -LiteralPath $finalPath -PathType Leaf)){return [pscustomobject]@{Valid=$false;Errors=@('K5_FINAL_MISSING');Data=$null}}
    $finalSha=(Get-FileHash -LiteralPath $finalPath -Algorithm SHA256).Hash;$directory=Join-Path $project '_work\K5'
    $matches=if(Test-Path -LiteralPath $directory -PathType Container){@(Get-ChildItem -LiteralPath $directory -Filter "v2-approval-$finalSha.json" -File -Force)}else{@()}
    if($matches.Count -ne 1){return [pscustomobject]@{Valid=$false;Errors=@("K5_APPROVAL_RECEIPT_COUNT_INVALID: $($matches.Count)");Data=$null}}
    $path=$matches[0].FullName
    try{$data=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64}catch{return [pscustomobject]@{Valid=$false;Errors=@('K5_APPROVAL_INVALID_JSON');Data=$null;Path=$path}}
    $expected=@('schema','workflow_revision','actor','attestation_scope','project_origin_sha256','final_sha256','draft_sha256','qa_sha256','factcheck_sha256','k4_proof_set_sha256','k4_proof_set_file_sha256','continuity_chain_sha256','duration_mode','final_word_count','maximum_words','duration_verdict','change_class','approval_note','created_at_utc','binding_sha256')
    if(@(Compare-Object -ReferenceObject $expected -DifferenceObject @($data.PSObject.Properties.Name)).Count -gt 0 -or @($data.PSObject.Properties.Name).Count -ne $expected.Count){$errors.Add('K5_APPROVAL_FIELDS_INVALID')}
    if([string]$data.schema -cne 'SYSTEM_V7_K5_APPROVAL_V2' -or [string]$data.workflow_revision -cne $script:SystemV7NarrativeWorkflowRevision -or [string]$data.actor -cne 'DAWID' -or [string]$data.duration_verdict -cne 'PASS'){$errors.Add('K5_APPROVAL_SCHEMA_INVALID')}
    $copy=[ordered]@{};foreach($property in $data.PSObject.Properties){if($property.Name -cne 'binding_sha256'){$copy[$property.Name]=$property.Value}}
    if((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)) -cne [string]$data.binding_sha256){$errors.Add('K5_APPROVAL_BINDING_MISMATCH')}
    foreach($pair in @(@('final_sha256',$finalPath),@('draft_sha256',(Join-Path $project '03-draft.md')),@('qa_sha256',(Join-Path $project '04-raport-qa.md')),@('factcheck_sha256',(Join-Path $project '04B-fact-check.md')))){
        if(-not(Test-Path -LiteralPath $pair[1] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -cne [string]$data.($pair[0])){$errors.Add("K5_APPROVAL_ARTIFACT_STALE: $($pair[0])")}
    }
    $origin=Get-SystemV7ProjectOriginState -ProjectPath $project;if(-not $origin.Valid -or [string]$origin.Sha256 -cne [string]$data.project_origin_sha256){$errors.Add('K5_APPROVAL_ORIGIN_MISMATCH')}
    $proof=Get-SystemV7K4ProofSetState -ProjectPath $project -ProofSetSha256 ([string]$data.k4_proof_set_sha256) -ExpectedDraftSha256 ([string]$data.draft_sha256)
    if(-not $proof.Valid){$errors.Add("K5_APPROVAL_K4_PROOF_INVALID: $($proof.Errors -join ',')")}
    elseif([string]$proof.FileSha256 -cne [string]$data.k4_proof_set_file_sha256 -or [string]$proof.Data.continuity_chain_sha256 -cne [string]$data.continuity_chain_sha256){$errors.Add('K5_APPROVAL_K4_BINDING_MISMATCH')}
    if([string]$data.change_class -cne 'BYTE_IDENTICAL'){$errors.Add('K5_APPROVAL_CHANGE_CLASS_INVALID')}
    if([string]$data.duration_mode -ceq 'HARD_MAX' -and [int]$data.final_word_count -gt [int]$data.maximum_words){$errors.Add('K5_APPROVAL_HARD_MAX_EXCEEDED')}
    [pscustomobject]@{Valid=$errors.Count -eq 0;Errors=@($errors);Data=$data;Path=$path;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}
