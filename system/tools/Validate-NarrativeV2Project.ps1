[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [ValidateNotNullOrEmpty()]
    [string]$PythonPath = 'python.exe',

    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'K1-PublishIntegrity.ps1')

$project = [IO.Path]::GetFullPath($ProjectPath)
$errors = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()
$runReceiptCache = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
$runTaskOwners = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)

function Add-NV2Error {
    param([Parameter(Mandatory)][string]$Message)
    [void]$errors.Add($Message)
}

function Add-NV2Warning {
    param([Parameter(Mandatory)][string]$Message)
    [void]$warnings.Add($Message)
}

$instructionContract=Get-SystemV7NarrativeInstructionContractState -SystemRoot (Split-Path -Parent $PSScriptRoot)
foreach($problem in @($instructionContract.Errors)){Add-NV2Error "NARRATIVE_INSTRUCTION_CONTRACT_INVALID: $problem"}

function Get-NV2SingleField {
    param(
        [AllowEmptyString()][Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Name,
        [switch]$AllowMissing
    )
    $matches = @([regex]::Matches($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
    if ($matches.Count -ne 1) {
        if (-not $AllowMissing) { Add-NV2Error "META_FIELD_COUNT_INVALID: $Name=$($matches.Count)" }
        return $null
    }
    $value = $matches[0].Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($value) -and -not $AllowMissing) { Add-NV2Error "META_FIELD_EMPTY: $Name" }
    return $value
}

function Get-NV2DocumentField {
    param(
        [AllowEmptyString()][Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Name
    )
    $matches = @([regex]::Matches($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
    if ($matches.Count -ne 1) { return $null }
    return $matches[0].Groups[1].Value.Trim()
}

function Get-NV2FirstField {
    param(
        [AllowEmptyString()][Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Name
    )
    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$")
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value.Trim()
}

function Test-NV2Concrete {
    param([AllowNull()][object]$Value, [int]$MinimumLength = 2)
    if ($null -eq $Value) { return $false }
    $text = ([string]$Value).Trim()
    return $text.Length -ge $MinimumLength -and $text -notmatch '^(?i:BRAK|NIEUSTALONE|DO UZUPEŁNIENIA|TODO|TBD|PLACEHOLDER|\[.*\])$'
}

function Test-NV2ExactMember {
    param([AllowNull()][object]$Value,[Parameter(Mandatory)][object[]]$Allowed)
    return [array]::IndexOf($Allowed,[string]$Value) -ge 0
}

function Test-NV2ExactPropertySet {
    param([Parameter(Mandatory)][object]$Object, [Parameter(Mandatory)][string[]]$Expected)
    $actual = [string[]]@($Object.PSObject.Properties.Name)
    if ($actual.Count -ne $Expected.Count) { return $false }
    return @(Compare-Object -ReferenceObject $Expected -DifferenceObject $actual).Count -eq 0
}

function Read-NV2Json {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Code)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-NV2Error "${Code}_MISSING: $Path"
        return $null
    }
    # Preserve ISO timestamps byte-for-byte for canonical receipt binding.
    # PowerShell 7 otherwise materializes them as DateTime and normalizes the
    # fractional part on re-serialization, creating a false hash mismatch.
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 64 }
    catch {
        Add-NV2Error "${Code}_INVALID_JSON: $($_.Exception.Message)"
        return $null
    }
}

function Test-NV2CanonicalJsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Data, [Parameter(Mandatory)][string]$Code)
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Add-NV2Error "${Code}_UTF8_BOM_FORBIDDEN"
            return
        }
        $actual = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $expected = ConvertTo-SystemV7CanonicalJson -Value $Data
        if ($actual -cne $expected) { Add-NV2Error "${Code}_CANONICAL_BYTES_MISMATCH" }
    } catch { Add-NV2Error "${Code}_CANONICAL_CHECK_FAILED: $($_.Exception.Message)" }
}

function Get-NV2FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-NV2WordCount {
    param([AllowEmptyString()][Parameter(Mandatory)][string]$Text)
    # .NET regex is Unicode-aware for \p{} categories by default; `(?u)` is a
    # Python flag and is an invalid inline option in PowerShell/.NET.
    return @([regex]::Matches($Text, "\b[\p{L}\p{N}][\p{L}\p{N}\p{M}’'-]*\b")).Count
}

function Test-NV2DurationValue {
    param([AllowNull()][string]$Declared, [Parameter(Mandatory)][double]$Expected)
    if ([string]::IsNullOrWhiteSpace($Declared)) { return $false }
    $match = [regex]::Match($Declared.Trim(), '^(?<number>\d+(?:[.,]\d+)?)\s*(?:min)?$')
    if (-not $match.Success) { return $false }
    $actual = 0.0
    if (-not [double]::TryParse($match.Groups['number'].Value.Replace(',','.'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$actual)) { return $false }
    return [math]::Abs($actual - $Expected) -lt 0.005
}

function Test-NV2StringSetEqual {
    param([AllowNull()][object[]]$Left, [AllowNull()][object[]]$Right)
    $leftSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $rightSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($value in @($Left)) { if (-not $leftSet.Add([string]$value)) { return $false } }
    foreach ($value in @($Right)) { if (-not $rightSet.Add([string]$value)) { return $false } }
    if ($leftSet.Count -ne $rightSet.Count) { return $false }
    return @($leftSet | Where-Object { -not $rightSet.Contains($_) }).Count -eq 0
}

function Resolve-NV2ProjectRelativePath {
    param([Parameter(Mandatory)][string]$Relative, [Parameter(Mandatory)][string]$Code)
    try {
        if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative)) { throw 'relative path required' }
        $full = [IO.Path]::GetFullPath((Join-Path $project $Relative))
        $null = Get-SystemV7NarrativeRelativePath -Root $project -Path $full
        return $full
    } catch {
        Add-NV2Error "${Code}_PATH_INVALID: $Relative"
        return $null
    }
}

function Get-NV2RunReceiptState {
    param([Parameter(Mandatory)][string]$ReceiptPath, [switch]$HistoricalQAImpact)
    $full = [IO.Path]::GetFullPath($ReceiptPath)
    $cacheKey = $full + '|HISTORICAL_QA_IMPACT=' + ([bool]$HistoricalQAImpact).ToString().ToUpperInvariant()
    if ($runReceiptCache.ContainsKey($cacheKey)) { return $runReceiptCache[$cacheKey] }

    $state = $null
    try { $state = Get-SystemV7NarrativeRunReceiptState -ProjectPath $project -ReceiptPath $full -HistoricalQAImpact:$HistoricalQAImpact }
    catch {
        Add-NV2Error "RUN_RECEIPT_VALIDATION_FAILED: $full :: $($_.Exception.Message)"
        $state = [pscustomobject]@{ Valid=$false; Errors=@($_.Exception.Message); Data=$null; Path=$full; Sha256=$null }
    }
    if (-not $state.Valid) {
        foreach ($problem in @($state.Errors)) { Add-NV2Error "RUN_RECEIPT_INVALID: $full :: $problem" }
    }
    if ($state.Data) {
        Test-NV2CanonicalJsonFile -Path $full -Data $state.Data -Code 'RUN_RECEIPT'
        if ([string]$state.Data.project_origin_sha256 -cne [string]$script:NV2OriginSha256) { Add-NV2Error "RUN_RECEIPT_ORIGIN_MISMATCH: $full" }
        if ([string]$state.Data.execution_status -cne 'COMPLETED') { Add-NV2Error "RUN_RECEIPT_NOT_COMPLETED: $full" }
        if ([string]$state.Data.independence_declaration -cne 'FRESH_CONTEXT_DECLARED; INPUTS_FROM_BOUND_BUNDLE_ONLY; NOT_CRYPTOGRAPHIC_IDENTITY_PROOF') {
            Add-NV2Error "RUN_RECEIPT_INDEPENDENCE_DECLARATION_INVALID: $full"
        }
        $expectedActor = if ([string]$state.Data.run_type -ceq 'GENERATE_ACT') { 'CLAUDE' } else { 'CHATGPT_CODEX' }
        if ([string]$state.Data.actor_role -cne $expectedActor) { Add-NV2Error "RUN_RECEIPT_ACTOR_INVALID: $full" }
        if ([string]$state.Data.model_settings_sha256 -notmatch '^[A-F0-9]{64}$') { Add-NV2Error "RUN_RECEIPT_MODEL_SETTINGS_INVALID: $full" }
        if (-not (Test-NV2Concrete $state.Data.task_id) -or -not (Test-NV2Concrete $state.Data.model_id) -or -not (Test-NV2Concrete $state.Data.model_revision)) {
            Add-NV2Error "RUN_RECEIPT_IDENTITY_INCOMPLETE: $full"
        }
        $started = [DateTimeOffset]::MinValue
        $completed = [DateTimeOffset]::MinValue
        $startedOk = [DateTimeOffset]::TryParse([string]$state.Data.started_at_utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$started)
        $completedOk = [DateTimeOffset]::TryParse([string]$state.Data.completed_at_utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$completed)
        if (-not $startedOk -or -not $completedOk -or $started -ge $completed -or $completed.UtcDateTime -gt [DateTime]::UtcNow.AddMinutes(5)) {
            Add-NV2Error "RUN_RECEIPT_TIME_RANGE_INVALID: $full"
        }
        $taskId = [string]$state.Data.task_id
        if ($runTaskOwners.ContainsKey($taskId) -and -not $runTaskOwners[$taskId].Equals($full, [StringComparison]::OrdinalIgnoreCase)) {
            Add-NV2Error "RUN_RECEIPT_TASK_ID_REUSED: $taskId"
        } elseif (-not $runTaskOwners.ContainsKey($taskId)) { $runTaskOwners.Add($taskId, $full) }
        $expectedDirectory = Split-Path -Parent $full
        if ([IO.Path]::GetFileName($expectedDirectory) -cne [string]$state.Data.run_id -or [IO.Path]::GetFileName($full) -cne 'run-receipt.json') {
            Add-NV2Error "RUN_RECEIPT_LOCATION_MISMATCH: $full"
        }
    }
    $runReceiptCache.Add($cacheKey, $state)
    return $state
}

function Test-NV2CurrentModelRebaseGate {
    param(
        [Parameter(Mandatory)][string]$MetaText,
        [Parameter(Mandatory)][string]$OriginSha256
    )
    $startErrors = $errors.Count
    $directory = Join-Path $project '_work\system\model-rebase'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { Add-NV2Error 'MODEL_REBASE_GATE_RECEIPT_DIRECTORY_MISSING'; return $false }
    $currentModelId = Get-NV2DocumentField -Text $MetaText -Name 'K3_MODEL_ID'
    $currentModelRevision = Get-NV2DocumentField -Text $MetaText -Name 'K3_MODEL_REVISION'
    $currentSettingsSha = Get-NV2DocumentField -Text $MetaText -Name 'K3_MODEL_SETTINGS_SHA256'
    $currentManifestRelative = Get-NV2DocumentField -Text $MetaText -Name 'K3_MODEL_MANIFEST_PATH'
    $matching = [Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter 'model-rebase-*.json' -File -Force)) {
        $data = Read-NV2Json -Path $file.FullName -Code 'MODEL_REBASE_RECEIPT'
        if (-not $data) { continue }
        if ([string]$data.schema -cne 'SYSTEM_V7_MODEL_REBASE_RECEIPT_V1') { Add-NV2Error "MODEL_REBASE_RECEIPT_SCHEMA_INVALID: $($file.FullName)"; continue }
        if ([string]$data.new_model_id -ceq $currentModelId -and [string]$data.new_model_revision -ceq $currentModelRevision -and [string]$data.new_settings_sha256 -ceq $currentSettingsSha -and [string]$data.model_manifest_relative -ceq $currentManifestRelative) {
            [void]$matching.Add([pscustomobject]@{Path=$file.FullName;Data=$data})
        }
    }
    if ($matching.Count -ne 1) { Add-NV2Error "MODEL_REBASE_GATE_CURRENT_RECEIPT_COUNT_INVALID: $($matching.Count)"; return $false }
    $receiptPath = [string]$matching[0].Path
    $data = $matching[0].Data
    Test-NV2CanonicalJsonFile -Path $receiptPath -Data $data -Code 'MODEL_REBASE_RECEIPT'
    $fields = @('operation','project_origin_sha256','input_meta_sha256','old_model_id','old_model_revision','old_settings_sha256','new_model_id','new_model_revision','new_settings_sha256','representative_act_id','trial_sha256','comparison_sha256','impact_sha256','old_k3_tree_sha256','reason','schema','actor','comparison_task_id','impact_task_id','archive_relative','model_manifest_relative','created_at_utc','binding_sha256')
    if (-not (Test-NV2ExactPropertySet -Object $data -Expected $fields)) { Add-NV2Error 'MODEL_REBASE_RECEIPT_FIELDS_INVALID' }
    if ([string]$data.operation -cne 'MODEL_REBASE' -or [string]$data.actor -cne 'DAWID' -or [string]$data.project_origin_sha256 -cne $OriginSha256 -or [string]$data.representative_act_id -notmatch '^ACT-\d{3}$') { Add-NV2Error 'MODEL_REBASE_RECEIPT_IDENTITY_INVALID' }
    foreach ($shaField in @('input_meta_sha256','old_settings_sha256','new_settings_sha256','trial_sha256','comparison_sha256','impact_sha256','old_k3_tree_sha256','binding_sha256')) {
        if ([string]$data.$shaField -notmatch '^[A-F0-9]{64}$') { Add-NV2Error "MODEL_REBASE_RECEIPT_SHA_INVALID: $shaField" }
    }
    $intent = [ordered]@{operation='MODEL_REBASE';project_origin_sha256=[string]$data.project_origin_sha256;input_meta_sha256=[string]$data.input_meta_sha256;old_model_id=[string]$data.old_model_id;old_model_revision=[string]$data.old_model_revision;old_settings_sha256=[string]$data.old_settings_sha256;new_model_id=[string]$data.new_model_id;new_model_revision=[string]$data.new_model_revision;new_settings_sha256=[string]$data.new_settings_sha256;representative_act_id=[string]$data.representative_act_id;trial_sha256=[string]$data.trial_sha256;comparison_sha256=[string]$data.comparison_sha256;impact_sha256=[string]$data.impact_sha256;old_k3_tree_sha256=[string]$data.old_k3_tree_sha256;reason=[string]$data.reason}
    $intentSha = Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $intent)
    if ([IO.Path]::GetFileName($receiptPath) -cne "model-rebase-$intentSha.json") { Add-NV2Error 'MODEL_REBASE_RECEIPT_FILENAME_OR_INTENT_MISMATCH' }
    $bindingCore = [ordered]@{}
    foreach ($property in $data.PSObject.Properties) { if ($property.Name -cne 'binding_sha256') { $bindingCore[$property.Name]=$property.Value } }
    if ((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $bindingCore)) -cne [string]$data.binding_sha256) { Add-NV2Error 'MODEL_REBASE_RECEIPT_BINDING_MISMATCH' }
    if (-not (Test-NV2Concrete $data.reason 15) -or -not (Test-NV2Concrete $data.old_model_id) -or -not (Test-NV2Concrete $data.old_model_revision) -or -not (Test-NV2Concrete $data.new_model_id) -or -not (Test-NV2Concrete $data.new_model_revision) -or
        ([string]$data.old_model_id -ceq [string]$data.new_model_id -and [string]$data.old_model_revision -ceq [string]$data.new_model_revision)) { Add-NV2Error 'MODEL_REBASE_RECEIPT_DECISION_INVALID' }
    if ([string]$data.comparison_task_id -notmatch '^[A-Z0-9][A-Z0-9._-]{7,120}$' -or [string]$data.impact_task_id -notmatch '^[A-Z0-9][A-Z0-9._-]{7,120}$' -or [string]$data.comparison_task_id -ceq [string]$data.impact_task_id) { Add-NV2Error 'MODEL_REBASE_RECEIPT_TASK_SEPARATION_INVALID' }
    $created = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$data.created_at_utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$created) -or $created.UtcDateTime -gt [DateTime]::UtcNow.AddMinutes(5)) { Add-NV2Error 'MODEL_REBASE_RECEIPT_CREATED_AT_INVALID' }
    $archivePath = Resolve-NV2ProjectRelativePath -Relative ([string]$data.archive_relative) -Code 'MODEL_REBASE_ARCHIVE'
    if ([string]$data.archive_relative -notmatch '^_work/k3-model-stale/' -or -not $archivePath -or -not (Test-Path -LiteralPath $archivePath -PathType Container)) { Add-NV2Error 'MODEL_REBASE_ARCHIVE_MISSING_OR_INVALID' }
    else {
        $rows = [Collections.Generic.List[object]]::new()
        $archivePrefix = $archivePath.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
        $paths = [string[]]@(Get-ChildItem -LiteralPath $archivePath -File -Recurse -Force | ForEach-Object FullName)
        [Array]::Sort($paths, [StringComparer]::Ordinal)
        foreach ($path in $paths) { $item=Get-Item -LiteralPath $path -Force;[void]$rows.Add([ordered]@{relative=$path.Substring($archivePrefix.Length).Replace('\','/');sha256=(Get-NV2FileSha256 $path);bytes=$item.Length}) }
        if ((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($rows))) -cne [string]$data.old_k3_tree_sha256) { Add-NV2Error 'MODEL_REBASE_ARCHIVE_TREE_STALE' }
    }
    return $errors.Count -eq $startErrors
}

$meta = ''
$stage = $null
$stageIndex = -1
$origin = $null
$script:NV2OriginSha256 = ''

$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $project -PathType Container)) {
    Add-NV2Error "PROJECT_DIRECTORY_MISSING: $project"
} elseif (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
    Add-NV2Error "META_MISSING: $metaPath"
} else {
    try {
        Assert-SystemV7PathNoReparse -Path $metaPath -ContainmentRoot $project | Out-Null
        $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    } catch { Add-NV2Error "META_READ_FAILED: $($_.Exception.Message)" }
}

if ($meta) {
    $requiredMetaFields = @(
        'SYSTEM_VERSION','WORKFLOW_REVISION','WORKFLOW_ACTIVATION','EVIDENCE_SCHEMA','ARCHITECTURE_SCHEMA','K3_PACKET_SCHEMA','CONTINUITY_SCHEMA','K4_QA_SCHEMA',
        'VOICE_PROFILE_REVISION','VOICE_PROFILE_STATUS','VOICE_PROFILE_SELECTION_RECEIPT_PATH','VOICE_PROFILE_SELECTION_RECEIPT_SHA256','PROJECT_NAME','PROJECT_PATH','CURRENT_STAGE','STAGE_OWNER','OWNER_OVERRIDE','OWNER_OVERRIDE_RECEIPT_PATH','OWNER_OVERRIDE_RECEIPT_SHA256',
        'LAST_STATE_RECEIPT_PATH','LAST_STATE_RECEIPT_SHA256','W0_DECISION','W0_CONDITIONS','W0_CONDITION_STATUS','W0_CONDITION_RESULT','W0_CONDITION_CLOSED_AT','W0_CONDITION_RECEIPT_PATH','W0_CONDITION_RECEIPT_SHA256',
        'CHANNEL','FORMAT','TARGET_MINUTES','TARGET_DURATION_MODE','DURATION_POLICY_RECEIPT_PATH','DURATION_POLICY_RECEIPT_SHA256','REAL_WPM','WPM_STATUS','RESEARCH_MODE','VERIFICATION_POLICY',
        'K1_RESEARCH_MODE','K1_ENGINE_VERSION','K1_RUN_PATH','K1_LEDGER_SHA256','K1_PUBLISH_RECEIPT_PATH','K1_PUBLISH_RECEIPT_SHA256','K1_MANUAL_REASON','REFERENCE_SCRIPT',
        'K3_MODEL_ID','K3_MODEL_REVISION','K3_MODEL_SETTINGS_SHA256','K3_MODEL_MANIFEST_PATH','K3_MODEL_MANIFEST_SHA256','K3_PREFIX_SHA256','K3_LAST_ATTESTED_ACT','NARRATIVE_ACT_SEQUENCE','CONTINUITY_STATUS',
        'K4_EDITOR_PROOF','K4_VERIFY_PROOF','K4_COLD_READER_PROOF','K4_PROOF_SET_SHA256','K2B_DECISION','BLOCKED_FROM_STAGE','BLOCKED_REASON','LAST_GATE','LAST_UPDATED','NEXT_ACTION'
    )
    foreach ($field in $requiredMetaFields) { $null = Get-NV2SingleField -Text $meta -Name $field }
    $allNames = @([regex]::Matches($meta, '(?m)^(?<name>[A-Z][A-Z0-9_/-]*):') | ForEach-Object { $_.Groups['name'].Value })
    foreach ($duplicate in @($allNames | Group-Object | Where-Object Count -gt 1)) { Add-NV2Error "META_FIELD_DUPLICATE: $($duplicate.Name)=$($duplicate.Count)" }

    $closedValues = [ordered]@{
        SYSTEM_VERSION='7.0'; WORKFLOW_REVISION='2026-08-31_NARRATIVE_V2'; WORKFLOW_ACTIVATION='PILOT_ONLY'; EVIDENCE_SCHEMA='MINIMAL_EVIDENCE_V4_PAGELOC'
        ARCHITECTURE_SCHEMA='STORY_ENGINE_V2'; K3_PACKET_SCHEMA='K3_PACKET_V2'; CONTINUITY_SCHEMA='CONTINUITY_ATTEST_V1'; K4_QA_SCHEMA='THREE_LENS_QA_V1'
        VERIFICATION_POLICY='SOURCE_FIRST_K4'; K1_ENGINE_VERSION='2.1.0'
    }
    foreach ($entry in $closedValues.GetEnumerator()) {
        $actual = Get-NV2DocumentField -Text $meta -Name $entry.Key
        if ([string]$actual -cne [string]$entry.Value) { Add-NV2Error "META_CONTRACT_MISMATCH: $($entry.Key)='$actual' expected='$($entry.Value)'" }
    }
    if (Test-Path -LiteralPath (Join-Path $project '.system-v7\legacy-origin.json') -PathType Leaf) { Add-NV2Error 'MIXED_ORIGIN_MARKERS: legacy-origin.json is forbidden in a Narrative V2 project' }
    if (Test-Path -LiteralPath (Join-Path $project '_work\k3-pakiety')) { Add-NV2Error 'MIXED_SCHEMA_LEGACY_K3_PACKET_DIRECTORY: _work/k3-pakiety is forbidden in a Narrative V2 project' }
    try {
        $origin = Assert-SystemV7CurrentProjectOrigin -ProjectPath $project -MetaText $meta
        if ([string]$origin.Data.origin_workflow_revision -cne '2026-08-31_NARRATIVE_V2') { throw 'PROJECT_ORIGIN_NOT_NARRATIVE_V2' }
        $script:NV2OriginSha256 = [string]$origin.Sha256
    } catch { Add-NV2Error "PROJECT_ORIGIN_INVALID: $($_.Exception.Message)" }

    foreach ($treeRelative in @('.system-v7','sources','_work')) {
        $treePath = Join-Path $project $treeRelative
        if (Test-Path -LiteralPath $treePath) {
            try { Assert-SystemV7TreeNoReparse -RootPath $treePath -ContainmentRoot $project | Out-Null }
            catch { Add-NV2Error "PROJECT_PATH_SAFETY: $($_.Exception.Message)" }
        }
    }

    $stage = Get-NV2DocumentField -Text $meta -Name 'CURRENT_STAGE'
    $stages = @('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE','BLOCKED')
    $stageAllowed = [Array]::IndexOf($stages, $stage) -ge 0
    if (-not $stageAllowed) { Add-NV2Error "CURRENT_STAGE_INVALID: $stage" }
    if ($stage -ceq 'BLOCKED') { Add-NV2Error 'PROJECT_BLOCKED: walidacja etapowa jest wstrzymana do legalnego Unblock' }
    $order = @('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE')
    $stageIndex = if ($stageAllowed) { [Array]::IndexOf($order, $stage) } else { -1 }

    $declaredPath = Get-NV2DocumentField -Text $meta -Name 'PROJECT_PATH'
    try {
        if (-not [IO.Path]::GetFullPath($declaredPath).Equals($project, [StringComparison]::OrdinalIgnoreCase)) { Add-NV2Error 'PROJECT_PATH_MISMATCH' }
    } catch { Add-NV2Error 'PROJECT_PATH_INVALID' }

    $ownerMap = @{W0='Dawid';K0='ChatGPT';K1='ChatGPT';K2='ChatGPT';K2B='ChatGPT';K3='Claude';K4='ChatGPT';K5='Dawid';COMPLETE='Dawid';BLOCKED='Dawid'}
    if ($ownerMap.ContainsKey($stage)) {
        try {
            $ownerState = Get-OwnerOverrideReceiptState -ProjectPath $project -MetaText $meta
            foreach ($problem in @($ownerState.Errors)) { Add-NV2Error "OWNER_STATE_INVALID: $problem" }
        } catch { Add-NV2Error "OWNER_STATE_CHECK_FAILED: $($_.Exception.Message)" }
    }
    $stateHead = $null
    try {
        $stateHead = Get-StateReceiptHeadState -ProjectPath $project -MetaText $meta
        foreach ($problem in @($stateHead.Errors)) { Add-NV2Error "STATE_RECEIPT_CHAIN_INVALID: $problem" }
    } catch { Add-NV2Error "STATE_RECEIPT_CHAIN_CHECK_FAILED: $($_.Exception.Message)" }

    $lastGate = Get-NV2DocumentField -Text $meta -Name 'LAST_GATE'
    $w0Decision = Get-NV2DocumentField -Text $meta -Name 'W0_DECISION'
    $expectedGate = switch ($stage) {
        'W0' { 'PROJECT_INITIALIZED' }
        'K0' { if ($w0Decision -ceq 'GO WARUNKOWE') { 'W0_GO_WARUNKOWE' } else { 'W0_GO' } }
        'K1' { 'K0_PASS' }; 'K2' { 'K1_PASS' }; 'K2B' { 'K2_PASS' }; 'K3' { 'K2B_PASS' }; 'K4' { 'K3_PASS' }; 'K5' { 'K4_PASS' }; 'COMPLETE' { 'K5_PASS' }
        default { $null }
    }
    if ($expectedGate -and [string]$lastGate -cne [string]$expectedGate) {
        $specialGateValid = $false
        if (Test-NV2ExactMember -Value $lastGate -Allowed @('REOPEN_K3_REQUIRED','REOPEN_K2B_REQUIRED')) {
            $targetStage = if ($lastGate -ceq 'REOPEN_K3_REQUIRED') { 'K3' } else { 'K2B' }
            if ($stage -ceq $targetStage -and $stateHead -and $stateHead.Valid -and [string]$stateHead.Kind -ceq 'REOPEN' -and
                [string]$stateHead.Data.target_stage -ceq $targetStage -and [string]$stateHead.Data.result_last_gate -ceq $lastGate) { $specialGateValid = $true }
            else { Add-NV2Error "STATE_REOPEN_GATE_WITHOUT_VALID_HEAD: gate=$lastGate stage=$stage" }
        } elseif ($lastGate -ceq 'MODEL_REBASE_REQUIRED_REGENERATION') {
            if ($stage -ceq 'K3' -and $script:NV2OriginSha256 -match '^[A-F0-9]{64}$' -and (Test-NV2CurrentModelRebaseGate -MetaText $meta -OriginSha256 $script:NV2OriginSha256)) { $specialGateValid = $true }
            else { Add-NV2Error "STATE_MODEL_REBASE_GATE_INVALID: stage=$stage" }
        }
        if (-not $specialGateValid -and -not (Test-NV2ExactMember -Value $lastGate -Allowed @('REOPEN_K3_REQUIRED','REOPEN_K2B_REQUIRED','MODEL_REBASE_REQUIRED_REGENERATION'))) { Add-NV2Error "STATE_GATE_MISMATCH: stage=$stage expected=$expectedGate actual=$lastGate" }
    }

    $handoffOwner = @([regex]::Matches($meta, '(?m)^- Właściciel:\s*(.*?)\s*$'))
    $handoffTask = @([regex]::Matches($meta, '(?m)^- Zadanie:\s*(.*?)\s*$'))
    if ($handoffOwner.Count -ne 1 -or [string]$handoffOwner[0].Groups[1].Value.Trim() -cne (Get-NV2DocumentField -Text $meta -Name 'STAGE_OWNER')) { Add-NV2Error 'ACTIVE_HANDOFF_OWNER_MISMATCH' }
    if ($handoffTask.Count -ne 1 -or [string]$handoffTask[0].Groups[1].Value.Trim() -notmatch "^$([regex]::Escape($stage))(?:\s|—|-|$)") { Add-NV2Error 'ACTIVE_HANDOFF_STAGE_MISMATCH' }

    $channel = Get-NV2DocumentField -Text $meta -Name 'CHANNEL'
    $format = Get-NV2DocumentField -Text $meta -Name 'FORMAT'
    $researchMode = Get-NV2DocumentField -Text $meta -Name 'RESEARCH_MODE'
    $wpmStatus = Get-NV2DocumentField -Text $meta -Name 'WPM_STATUS'
    if (-not (Test-NV2ExactMember -Value $channel -Allowed @('dawid_soltan','polska_news','inny'))) { Add-NV2Error "CHANNEL_INVALID: $channel" }
    if (-not (Test-NV2ExactMember -Value $format -Allowed @('STORYTELLING','DZIENNIKARSKI'))) { Add-NV2Error "FORMAT_INVALID: $format" }
    if (-not (Test-NV2ExactMember -Value $researchMode -Allowed @('SOURCES_ONLY','SOURCES_PLUS_WEB_AFTER_CONFIRMATION'))) { Add-NV2Error "RESEARCH_MODE_INVALID: $researchMode" }
    if (-not (Test-NV2ExactMember -Value $wpmStatus -Allowed @('ZAŁOŻENIE','POMIAR'))) { Add-NV2Error "WPM_STATUS_INVALID: $wpmStatus" }
    $targetMinutes = 0
    $realWpm = 0
    if (-not [int]::TryParse((Get-NV2DocumentField -Text $meta -Name 'TARGET_MINUTES'), [ref]$targetMinutes) -or $targetMinutes -lt 1 -or $targetMinutes -gt 240) { Add-NV2Error 'TARGET_MINUTES_INVALID' }
    if (-not [int]::TryParse((Get-NV2DocumentField -Text $meta -Name 'REAL_WPM'), [ref]$realWpm) -or $realWpm -lt 1 -or $realWpm -gt 240) { Add-NV2Error 'REAL_WPM_INVALID' }
    $durationMode = Get-NV2DocumentField -Text $meta -Name 'TARGET_DURATION_MODE'
    if ($durationMode -cne 'GUIDE' -and $durationMode -cne 'HARD_MAX') { Add-NV2Error "TARGET_DURATION_MODE_INVALID: $durationMode" }
    $lastUpdated = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact((Get-NV2DocumentField -Text $meta -Name 'LAST_UPDATED'), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$lastUpdated) -or $lastUpdated.Date -gt [DateTime]::UtcNow.Date) { Add-NV2Error 'LAST_UPDATED_INVALID' }
    if (-not (Test-NV2Concrete (Get-NV2DocumentField -Text $meta -Name 'NEXT_ACTION') 10)) { Add-NV2Error 'NEXT_ACTION_NOT_CONCRETE' }

    # W0 has no separate validator script. These are the same read-only source and decision gates
    # used by Validate-Project; K1 below is delegated to the existing evidence/publish validators.
    if ($stageIndex -ge 0) {
        if (-not (Test-NV2ExactMember -Value $w0Decision -Allowed @('GO','GO WARUNKOWE'))) { Add-NV2Error "W0_DECISION_NOT_READY: $w0Decision" }
        $sourceDir = Join-Path $project 'sources'
        if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { Add-NV2Error 'W0_SOURCES_DIRECTORY_MISSING' }
        else {
            $supported = @('.pdf','.md','.txt','.srt','.vtt')
            $sourceRoot = [IO.Path]::GetFullPath($sourceDir)
            $active = @(Get-ChildItem -LiteralPath $sourceDir -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 -and $_.Extension.ToLowerInvariant() -in $supported })
            if ($active.Count -eq 0) { Add-NV2Error 'W0_ACTIVE_SOURCE_MISSING' }
            foreach ($nested in @(Get-ChildItem -LiteralPath $sourceDir -File -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.DirectoryName -ne $sourceRoot -and $_.FullName -notmatch '[\\/]_oryginaly(?:[\\/]|$)' -and $_.Extension.ToLowerInvariant() -in $supported
            })) { Add-NV2Error "W0_NESTED_ACTIVE_SOURCE_FORBIDDEN: $($nested.FullName)" }
        }
        try {
            $conditionState = Get-W0ConditionClosureState -ProjectPath $project -MetaText $meta
            foreach ($problem in @($conditionState.Errors)) { Add-NV2Error "W0_CONDITION_INVALID: $problem" }
            if ($stageIndex -ge [Array]::IndexOf($order,'K1') -and $w0Decision -ceq 'GO WARUNKOWE' -and [string]$conditionState.Status -cne 'CLOSED') { Add-NV2Error 'W0_CONDITION_NOT_CLOSED_BEFORE_K1' }
        } catch { Add-NV2Error "W0_CONDITION_CHECK_FAILED: $($_.Exception.Message)" }
    }

    $foundationPath = Join-Path $project '00-fundament-projektu.md'
    $foundation = ''
    if ($stageIndex -ge [Array]::IndexOf($order,'K0')) {
        if (-not (Test-Path -LiteralPath $foundationPath -PathType Leaf)) { Add-NV2Error 'K0_FOUNDATION_MISSING' }
        else {
            $foundation = Get-Content -LiteralPath $foundationPath -Raw -Encoding UTF8
            if ((Get-NV2DocumentField -Text $foundation -Name 'STATUS') -cne 'GOTOWY') { Add-NV2Error 'K0_STATUS_NOT_READY' }
            if (-not (Test-NV2ExactMember -Value (Get-NV2DocumentField -Text $foundation -Name 'ZGODNOŚĆ_Z_W0') -Allowed @('POTWIERDZONA','TAK'))) { Add-NV2Error 'K0_W0_AGREEMENT_NOT_CONFIRMED' }
            foreach ($field in @('PYTANIE GŁÓWNE','OBIETNICA','KONFLIKT/NAPIĘCIE','W FILMIE','POZA FILMEM','WĄTKI OBOWIĄZKOWE','TEMAT ANALIZY K1-LITE V2','TRYB RESEARCHU','ZGODA NA WEB','POLITYKA WERYFIKACJI')) {
                $match = [regex]::Match($foundation, "(?m)^\s*-\s*$([regex]::Escape($field)):\s*(.*?)\s*$")
                if (-not $match.Success -or -not (Test-NV2Concrete $match.Groups[1].Value)) { Add-NV2Error "K0_FIELD_MISSING: $field" }
            }
            if ([regex]::Match($foundation, '(?m)^\s*-\s*WERDYKT:\s*(.*?)\s*$').Groups[1].Value.Trim() -cne 'PASS') { Add-NV2Error 'K0_VERDICT_NOT_PASS' }
            $foundationResearch = [regex]::Match($foundation, '(?m)^\s*-\s*TRYB RESEARCHU:\s*(.*?)\s*$').Groups[1].Value.Trim()
            if ($foundationResearch -cne $researchMode) { Add-NV2Error 'K0_RESEARCH_MODE_MISMATCH' }
            $expectedWeb = if ($researchMode -ceq 'SOURCES_ONLY') { 'NIE' } else { 'TYLKO PO POTWIERDZENIU DAWIDA' }
            if ([regex]::Match($foundation, '(?m)^\s*-\s*ZGODA NA WEB:\s*(.*?)\s*$').Groups[1].Value.Trim() -cne $expectedWeb) { Add-NV2Error 'K0_WEB_CONSENT_MISMATCH' }
            if ([regex]::Match($foundation, '(?m)^\s*-\s*POLITYKA WERYFIKACJI:\s*(.*?)\s*$').Groups[1].Value.Trim() -cne 'SOURCE_FIRST_K4') { Add-NV2Error 'K0_VERIFICATION_POLICY_MISMATCH' }
            $goals = @([regex]::Matches($foundation, '(?m)^\|\s*(Q-\d{3,})\s*\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*$'))
            if ($goals.Count -lt 4 -or $goals.Count -gt 8) { Add-NV2Error "K0_RESEARCH_GOAL_COUNT_INVALID: $($goals.Count)" }
            foreach ($duplicate in @($goals | ForEach-Object { $_.Groups[1].Value } | Group-Object | Where-Object Count -gt 1)) { Add-NV2Error "K0_RESEARCH_GOAL_DUPLICATE: $($duplicate.Name)" }
            foreach ($goal in $goals) {
                foreach ($cell in 2..6) { if (-not (Test-NV2Concrete $goal.Groups[$cell].Value)) { Add-NV2Error "K0_RESEARCH_GOAL_FIELD_EMPTY: $($goal.Groups[1].Value)"; break } }
                if (-not (Test-NV2ExactMember -Value $goal.Groups[5].Value.Trim() -Allowed @('MUST','OPCJONALNY'))) { Add-NV2Error "K0_RESEARCH_GOAL_PRIORITY_INVALID: $($goal.Groups[1].Value)" }
            }
        }
    }

    if ($foundation) {
        $foundationMode = [regex]::Match($foundation, '(?m)^\s*-\s*TARGET_DURATION_MODE:\s*(.*?)\s*$').Groups[1].Value.Trim()
        $foundationMinutes = [regex]::Match($foundation, '(?m)^\s*-\s*TARGET_MINUTES:\s*(.*?)\s*$').Groups[1].Value.Trim()
        if ($foundationMode -cne $durationMode -or $foundationMinutes -cne [string]$targetMinutes) { Add-NV2Error 'DURATION_POLICY_META_FOUNDATION_MISMATCH' }
    }

    if ($stageIndex -ge [Array]::IndexOf($order,'K1')) {
        $evidenceValidator = Join-Path $PSScriptRoot 'Validate-EvidenceBase.ps1'
        if (-not (Test-Path -LiteralPath $evidenceValidator -PathType Leaf)) { Add-NV2Error 'K1_EVIDENCE_VALIDATOR_MISSING' }
        else {
            try {
                $evidenceResult = @(& $evidenceValidator -ProjectPath $project -NoExit) | Select-Object -Last 1
                foreach ($problem in @($evidenceResult.ErrorDetails)) { Add-NV2Error "K1_EVIDENCE: $problem" }
                foreach ($problem in @($evidenceResult.WarningDetails)) { Add-NV2Warning "K1_EVIDENCE: $problem" }
                if (-not [bool]$evidenceResult.GateReady) { Add-NV2Error 'K1_EVIDENCE_GATE_NOT_READY' }
            } catch { Add-NV2Error "K1_EVIDENCE_VALIDATOR_FAILED: $($_.Exception.Message)" }
        }
        $k1Mode = Get-NV2DocumentField -Text $meta -Name 'K1_RESEARCH_MODE'
        if ($k1Mode -ceq 'MANUAL_APPROVED') {
            try {
                $fallback = Get-K1ManualFallbackReceiptState -ProjectPath $project
                foreach ($problem in @($fallback.Errors)) { Add-NV2Error "K1_MANUAL_FALLBACK: $problem" }
            } catch { Add-NV2Error "K1_MANUAL_FALLBACK_CHECK_FAILED: $($_.Exception.Message)" }
        } elseif ($k1Mode -ceq 'K1_LITE_V2') {
            try {
                $publishState = Assert-K1PublishReceiptCurrent -ProjectPath $project -ReceiptRelative (Get-NV2DocumentField -Text $meta -Name 'K1_PUBLISH_RECEIPT_PATH') -ExpectedReceiptSha256 (Get-NV2DocumentField -Text $meta -Name 'K1_PUBLISH_RECEIPT_SHA256')
                $enginePath = Join-Path $PSScriptRoot 'k1-lite-v2\Invoke-K1LiteV2.ps1'
                if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) { throw 'K1_VALIDATE_RUN_ENGINE_MISSING' }
                $fresh = @(Invoke-K1FreshLineageGates -EnginePath $enginePath -ProjectPath $project -Lineage @($publishState.Lineage) -PythonPath $PythonPath)
                if ($fresh.Count -ne @($publishState.Lineage).Count) { throw 'K1_FRESH_LINEAGE_RESULT_COUNT_MISMATCH' }
            } catch { Add-NV2Error "K1_PUBLISH_OR_FRESH_GATES_INVALID: $($_.Exception.Message)" }
        } else { Add-NV2Error "K1_RESEARCH_MODE_INVALID: $k1Mode" }
    }
}

$architectureState = $null
$architectureData = $null
$evidenceRegistry = $null
$actIds = @()
if ($meta -and $stageIndex -ge [Array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE'),'K2')) {
    $architecturePath = Join-Path $project '02-architektura-odcinka.md'
    $evidencePath = Join-Path $project '01-baza-dowodow.md'
    try {
        $architectureStatus = Get-SystemV7NarrativeMetaField -Text (Get-Content -LiteralPath $architecturePath -Raw -Encoding UTF8) -Name 'STATUS'
        if ($architectureStatus -cne 'GOTOWA') { Add-NV2Error "K2_ARCHITECTURE_STATUS_NOT_READY: $architectureStatus" }
        $architectureState = Test-SystemV7NarrativeArchitecture -ArchitecturePath $architecturePath -EvidencePath $evidencePath
        foreach ($problem in @($architectureState.ErrorDetails)) { Add-NV2Error "K2_STORY_ENGINE: $problem" }
        foreach ($problem in @($architectureState.WarningDetails)) { Add-NV2Warning "K2_STORY_ENGINE: $problem" }
        if ($architectureState.GateReady) {
            $architectureData = $architectureState.Architecture.Data
            $evidenceRegistry = $architectureState.Evidence
            $actIds = @($architectureState.ActIds)
            $directions = @($architectureData.directions)
            if ($directions.Count -lt 2 -or $directions.Count -gt 3) { Add-NV2Error "K2_DIRECTION_COUNT_INVALID: $($directions.Count)" }
            $directionIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($direction in $directions) {
                if (-not (Test-NV2Concrete $direction.direction_id) -or -not $directionIds.Add([string]$direction.direction_id)) { Add-NV2Error "K2_DIRECTION_ID_INVALID_OR_DUPLICATE: $($direction.direction_id)" }
                foreach ($field in @('axis','conflict','promise','narrative_concrete','risk_advantage')) { if (-not (Test-NV2Concrete $direction.$field)) { Add-NV2Error "K2_DIRECTION_FIELD_MISSING: $($direction.direction_id)/$field" } }
                foreach ($evidenceId in @($direction.core_p_ids)) { if (-not $evidenceRegistry.Cards.ContainsKey([string]$evidenceId)) { Add-NV2Error "K2_DIRECTION_CARD_MISSING: $($direction.direction_id)/$evidenceId" } }
            }
            if (-not $directionIds.Contains([string]$architectureData.selected_direction)) { Add-NV2Error 'K2_SELECTED_DIRECTION_NOT_DECLARED' }
            $topSelected = Get-NV2DocumentField -Text $architectureState.Architecture.Text -Name 'WYBRANY_KIERUNEK'
            if ([string]$topSelected -cne [string]$architectureData.selected_direction) { Add-NV2Error 'K2_SELECTED_DIRECTION_METADATA_MISMATCH' }
        }
    } catch { Add-NV2Error "K2_STORY_ENGINE_VALIDATION_FAILED: $($_.Exception.Message)" }
}

function Test-NV2DurationPolicyReceipt {
    if (-not $meta) { return }
    $relative = Get-NV2DocumentField -Text $meta -Name 'DURATION_POLICY_RECEIPT_PATH'
    $declaredSha = Get-NV2DocumentField -Text $meta -Name 'DURATION_POLICY_RECEIPT_SHA256'
    if ($relative -ceq 'BRAK' -and $declaredSha -ceq 'BRAK') { return }
    if ($relative -ceq 'BRAK' -or $declaredSha -ceq 'BRAK') { Add-NV2Error 'DURATION_POLICY_RECEIPT_POINTER_PARTIAL'; return }
    $path = Resolve-NV2ProjectRelativePath -Relative $relative -Code 'DURATION_POLICY_RECEIPT'
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-NV2Error 'DURATION_POLICY_RECEIPT_MISSING'; return }
    if ($declaredSha -notmatch '^[A-F0-9]{64}$' -or (Get-NV2FileSha256 $path) -cne $declaredSha) { Add-NV2Error 'DURATION_POLICY_RECEIPT_SHA_MISMATCH' }
    $data = Read-NV2Json -Path $path -Code 'DURATION_POLICY_RECEIPT'
    if (-not $data) { return }
    Test-NV2CanonicalJsonFile -Path $path -Data $data -Code 'DURATION_POLICY_RECEIPT'
    $expectedFields = @('schema','workflow_revision','intent_sha256','project_origin_sha256','input_meta_sha256','input_fundament_sha256','result_meta_context_sha256','result_fundament_sha256','mode','target_minutes','reason','actor','attestation_scope','created_at_utc','binding_sha256')
    if (-not (Test-NV2ExactPropertySet -Object $data -Expected $expectedFields)) { Add-NV2Error 'DURATION_POLICY_RECEIPT_FIELDS_INVALID' }
    $copy = [ordered]@{}
    foreach ($property in $data.PSObject.Properties) { if ($property.Name -cne 'binding_sha256') { $copy[$property.Name] = $property.Value } }
    if ((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $copy)) -cne [string]$data.binding_sha256) { Add-NV2Error 'DURATION_POLICY_RECEIPT_BINDING_MISMATCH' }
    if ([string]$data.schema -cne 'SYSTEM_V7_DURATION_POLICY_RECEIPT_V1' -or [string]$data.workflow_revision -cne '2026-08-31_NARRATIVE_V2' -or
        [string]$data.project_origin_sha256 -cne $script:NV2OriginSha256 -or [string]$data.actor -cne 'DAWID' -or
        [string]$data.attestation_scope -cne 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY') { Add-NV2Error 'DURATION_POLICY_RECEIPT_CONTRACT_INVALID' }
    if ([string]$data.mode -cne (Get-NV2DocumentField -Text $meta -Name 'TARGET_DURATION_MODE') -or [int]$data.target_minutes -ne $targetMinutes) { Add-NV2Error 'DURATION_POLICY_RECEIPT_CURRENT_POLICY_MISMATCH' }
    foreach ($shaField in @('intent_sha256','input_meta_sha256','input_fundament_sha256','result_meta_context_sha256','result_fundament_sha256','binding_sha256')) {
        if ([string]$data.$shaField -notmatch '^[A-F0-9]{64}$') { Add-NV2Error "DURATION_POLICY_RECEIPT_SHA_FIELD_INVALID: $shaField" }
    }
    $intent = [ordered]@{operation='SET_DURATION_POLICY';project_origin_sha256=[string]$data.project_origin_sha256;input_meta_sha256=[string]$data.input_meta_sha256;input_fundament_sha256=[string]$data.input_fundament_sha256;mode=[string]$data.mode;target_minutes=[int]$data.target_minutes;reason=[string]$data.reason;actor=[string]$data.actor}
    if ((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $intent)) -cne [string]$data.intent_sha256) { Add-NV2Error 'DURATION_POLICY_RECEIPT_INTENT_BINDING_MISMATCH' }
    # result_meta_context_sha256 is a historical CAS witness. Later Advance/Reopen
    # operations legitimately change unrelated meta fields, so it must not be
    # compared with the whole current meta. The live policy projection is bound
    # by mode + target in meta, the same fields in 00, and the current receipt.
    if (-not (Test-Path -LiteralPath $foundationPath -PathType Leaf) -or (Get-NV2FileSha256 $foundationPath) -cne [string]$data.result_fundament_sha256) { Add-NV2Error 'DURATION_POLICY_RECEIPT_FOUNDATION_STALE' }
}

if ($meta) { Test-NV2DurationPolicyReceipt }

# Reject legacy K3 length controls wherever they could still steer the active V2 path.
foreach ($artifactName in @('02-architektura-odcinka.md','03-draft.md')) {
    $artifactPath = Join-Path $project $artifactName
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { continue }
    $artifactText = Get-Content -LiteralPath $artifactPath -Raw -Encoding UTF8
    if ($artifactText -match '(?i)K3_BUDGET_OVERRIDE|Budżet\s+słów|WORD_BUDGET|CHARACTER_BUDGET|EXPOSITION_BUDGET|NEW_NAMES_BUDGET|HARD_MIN|70\s*[–-]\s*140\s*%|300\s+słów\s+na\s+kart') {
        Add-NV2Error "MIXED_SCHEMA_LEGACY_K3_LIMIT: $artifactName"
    }
}

# Validate every provenance receipt already present, including receipts not yet referenced by a gate.
$runRoot = Join-Path $project '_work\narrative-runs'
if (Test-Path -LiteralPath $runRoot -PathType Container) {
    $liveDraftPathForReceipts = Join-Path $project '03-draft.md'
    $liveDraftShaForReceipts = if (Test-Path -LiteralPath $liveDraftPathForReceipts -PathType Leaf) { Get-NV2FileSha256 $liveDraftPathForReceipts } else { $null }
    $receiptPaths = [string[]]@(Get-ChildItem -LiteralPath $runRoot -Filter 'run-receipt.json' -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object FullName)
    [Array]::Sort($receiptPaths, [StringComparer]::Ordinal)
    foreach ($receiptPath in $receiptPaths) {
        $historicalQAImpact = $false
        try {
            $receiptProbe = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 32
            if ([string]$receiptProbe.run_type -ceq 'QA_IMPACT_REVIEW') {
                $manifestProbePath = Resolve-NV2ProjectRelativePath -Relative ([string]$receiptProbe.input_manifest_relative) -Code 'RUN_RECEIPT_HISTORY_PROBE'
                $manifestProbe = if ($manifestProbePath) { Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $manifestProbePath } else { $null }
                $newDraftEntries = if ($manifestProbe -and $manifestProbe.Valid) { @($manifestProbe.Data.entries | Where-Object { [string]$_.content_role -ceq 'NEW_DRAFT' }) } else { @() }
                if ($newDraftEntries.Count -eq 1 -and $liveDraftShaForReceipts -and [string]$newDraftEntries[0].sha256 -cne $liveDraftShaForReceipts) { $historicalQAImpact = $true }
            }
        } catch {
            # The normal receipt validator below reports the authoritative error.
        }
        $null = Get-NV2RunReceiptState -ReceiptPath $receiptPath -HistoricalQAImpact:$historicalQAImpact
    }
}

$prefixSha = if ($meta) { Get-NV2DocumentField -Text $meta -Name 'K3_PREFIX_SHA256' } else { '' }
$modelId = if ($meta) { Get-NV2DocumentField -Text $meta -Name 'K3_MODEL_ID' } else { '' }
$modelRevision = if ($meta) { Get-NV2DocumentField -Text $meta -Name 'K3_MODEL_REVISION' } else { '' }
$modelSettingsSha = if ($meta) { Get-NV2DocumentField -Text $meta -Name 'K3_MODEL_SETTINGS_SHA256' } else { '' }
$modelManifestState = $null
$sequence = @()
$packetRecords = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
$actStates = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
$beatStates = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)

if ($architectureData -and $stageIndex -ge [Array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE'),'K2B')) {
    $metaK2B = Get-NV2DocumentField -Text $meta -Name 'K2B_DECISION'
    if (-not (Test-NV2ExactMember -Value $metaK2B -Allowed @('SUPLEMENT WYMAGANY','SUPLEMENT NIEWYMAGANY'))) { Add-NV2Error "K2B_DECISION_INVALID: $metaK2B" }
    if ([string]$architectureData.k2b.decision -cne $metaK2B) { Add-NV2Error 'K2B_DECISION_ARCHITECTURE_MISMATCH' }
    if (-not (Test-NV2Concrete $architectureData.k2b.reason 12)) { Add-NV2Error 'K2B_REASON_NOT_CONCRETE' }
    if ($metaK2B -ceq 'SUPLEMENT WYMAGANY' -and @($architectureData.k2b.gaps).Count -eq 0) { Add-NV2Error 'K2B_REQUIRED_SUPPLEMENT_WITHOUT_GAPS' }

    $sequenceRaw = Get-NV2DocumentField -Text $meta -Name 'NARRATIVE_ACT_SEQUENCE'
    $sequence = @($sequenceRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($sequence.Count -ne $actIds.Count) { Add-NV2Error 'NARRATIVE_ACT_SEQUENCE_COUNT_MISMATCH' }
    else {
        for ($index=0; $index -lt $actIds.Count; $index++) { if ([string]$sequence[$index] -cne [string]$actIds[$index]) { Add-NV2Error "NARRATIVE_ACT_SEQUENCE_MISMATCH: index=$index" } }
    }
    if (@($sequence | Select-Object -Unique).Count -ne $sequence.Count) { Add-NV2Error 'NARRATIVE_ACT_SEQUENCE_DUPLICATE' }
    if (-not (Test-NV2Concrete $modelId) -or -not (Test-NV2Concrete $modelRevision) -or $modelSettingsSha -notmatch '^[A-F0-9]{64}$') { Add-NV2Error 'K3_MODEL_MANIFEST_INCOMPLETE' }
    try {
        $modelManifestState = Get-SystemV7K3ModelManifestState -ProjectPath $project -MetaText $meta
        if (-not $modelManifestState.Valid) {
            foreach ($problem in @($modelManifestState.Errors)) { Add-NV2Error "K3_MODEL_MANIFEST_INVALID: $problem" }
        } elseif ($modelManifestState.Data) {
            $declaredManifestRelative = Get-NV2DocumentField -Text $meta -Name 'K3_MODEL_MANIFEST_PATH'
            $declaredManifestSha = Get-NV2DocumentField -Text $meta -Name 'K3_MODEL_MANIFEST_SHA256'
            $resolvedManifest = Resolve-NV2ProjectRelativePath -Relative $declaredManifestRelative -Code 'K3_MODEL_MANIFEST'
            if (-not $resolvedManifest -or -not $resolvedManifest.Equals([string]$modelManifestState.Path, [StringComparison]::OrdinalIgnoreCase)) { Add-NV2Error 'K3_MODEL_MANIFEST_PATH_MISMATCH' }
            if ($declaredManifestSha -notmatch '^[A-F0-9]{64}$' -or [string]$modelManifestState.Sha256 -cne $declaredManifestSha) { Add-NV2Error 'K3_MODEL_MANIFEST_SHA_MISMATCH' }
            Test-NV2CanonicalJsonFile -Path ([string]$modelManifestState.Path) -Data $modelManifestState.Data -Code 'K3_MODEL_MANIFEST'
            $manifestFields = @('schema','workflow_revision','project_origin_sha256','model_id','model_revision','settings_relative','settings_sha256','created_at_utc','binding_sha256')
            if (-not (Test-NV2ExactPropertySet -Object $modelManifestState.Data -Expected $manifestFields)) { Add-NV2Error 'K3_MODEL_MANIFEST_FIELDS_INVALID' }
            $manifestCreated = [DateTimeOffset]::MinValue
            if (-not [DateTimeOffset]::TryParse([string]$modelManifestState.Data.created_at_utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$manifestCreated) -or $manifestCreated.UtcDateTime -gt [DateTime]::UtcNow.AddMinutes(5)) {
                Add-NV2Error 'K3_MODEL_MANIFEST_CREATED_AT_INVALID'
            }
        }
    } catch { Add-NV2Error "K3_MODEL_MANIFEST_CHECK_FAILED: $($_.Exception.Message)" }

    $voice = $null
    $voiceRevision = Get-NV2DocumentField -Text $meta -Name 'VOICE_PROFILE_REVISION'
    $voiceProfilePath = Join-Path (Split-Path -Parent $PSScriptRoot) "_SYSTEM\NARRATIVE\VOICE-PROFILES\$voiceRevision.md"
    try {
        $voice = Get-SystemV7VoiceProfileState -ProfilePath $voiceProfilePath
        foreach ($problem in @($voice.Errors)) { Add-NV2Error "VOICE_PROFILE_INVALID: $problem" }
        if ([string]$voice.Revision -cne (Get-NV2DocumentField -Text $meta -Name 'VOICE_PROFILE_REVISION')) { Add-NV2Error 'VOICE_PROFILE_REVISION_MISMATCH' }
        if ((Get-NV2DocumentField -Text $meta -Name 'VOICE_PROFILE_STATUS') -cne 'APPROVED') { Add-NV2Error 'VOICE_PROFILE_META_NOT_APPROVED' }
        $selection=Get-SystemV7VoiceProfileSelectionState -ProjectPath $project -MetaText $meta
        foreach($problem in @($selection.Errors)){Add-NV2Error "VOICE_PROFILE_SELECTION_INVALID: $problem"}
    } catch { Add-NV2Error "VOICE_PROFILE_CHECK_FAILED: $($_.Exception.Message)" }

    $prefixDir = Join-Path $project '_work\k3\prefix'
    $prefixManifestPath = Join-Path $prefixDir 'prefix.manifest.json'
    $prefixManifest = Read-NV2Json -Path $prefixManifestPath -Code 'K3_PREFIX_MANIFEST'
    if ($prefixManifest) {
        Test-NV2CanonicalJsonFile -Path $prefixManifestPath -Data $prefixManifest -Code 'K3_PREFIX_MANIFEST'
        $prefixFields = @('schema','workflow_revision','project_id','voice_profile_revision','voice_profile_sha256','voice_exemplar_registry_sha256','core_sha256','story_spine_content_sha256','voice_rules_sha256','voice_exemplars_sha256','prefix_sha256')
        if (-not (Test-NV2ExactPropertySet -Object $prefixManifest -Expected $prefixFields)) { Add-NV2Error 'K3_PREFIX_MANIFEST_FIELDS_INVALID' }
        if ([string]$prefixManifest.schema -cne 'K3_PREFIX_MANIFEST_V2' -or [string]$prefixManifest.workflow_revision -cne '2026-08-31_NARRATIVE_V2' -or
            [string]$prefixManifest.project_id -cne [string]$origin.ProjectId -or [string]$prefixManifest.prefix_sha256 -cne $prefixSha) { Add-NV2Error 'K3_PREFIX_MANIFEST_IDENTITY_MISMATCH' }
        if($voice -and ($prefixManifest.voice_profile_revision -cne $voice.Revision -or
            $prefixManifest.voice_profile_sha256 -cne $voice.ProfileSha256 -or
            $prefixManifest.voice_exemplar_registry_sha256 -cne $voice.ExemplarRegistrySha256 -or
            $prefixManifest.voice_rules_sha256 -cne $voice.RulesSha256 -or
            $prefixManifest.voice_exemplars_sha256 -cne $voice.ExemplarsSha256)){
            Add-NV2Error 'K3_PREFIX_LIVE_VOICE_PROFILE_STALE'
        }
        $prefixComponents = [ordered]@{
            'K3_RULES_CORE.md'='core_sha256'; 'PROJECT_STORY_SPINE.json'='story_spine_content_sha256'; 'VOICE_RULES.md'='voice_rules_sha256'; 'VOICE_EXEMPLARS.md'='voice_exemplars_sha256'; 'prefix.bundle.md'='prefix_sha256'
        }
        foreach ($entry in $prefixComponents.GetEnumerator()) {
            $path = Join-Path $prefixDir $entry.Key
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-NV2Error "K3_PREFIX_COMPONENT_MISSING: $($entry.Key)"; continue }
            if ((Get-NV2FileSha256 $path) -cne [string]$prefixManifest.($entry.Value)) { Add-NV2Error "K3_PREFIX_COMPONENT_STALE: $($entry.Key)" }
        }
        if (Test-Path -LiteralPath (Join-Path $prefixDir 'PROJECT_STORY_SPINE.json') -PathType Leaf) {
            $expectedSpine = Get-SystemV7StorySpineProjection -ArchitectureData $architectureData
            if ((Get-NV2FileSha256 (Join-Path $prefixDir 'PROJECT_STORY_SPINE.json')) -cne $expectedSpine.Sha256) { Add-NV2Error 'K3_PREFIX_STORY_SPINE_STALE' }
        }
    }

    $actsRoot = Join-Path $project '_work\k3\acts'
    foreach ($actId in $sequence) {
        $statePath = Join-Path $actsRoot "$actId\state.json"
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            $state = Read-NV2Json -Path $statePath -Code "K3_ACT_STATE_$actId"
            if ($state) {
                Test-NV2CanonicalJsonFile -Path $statePath -Data $state -Code "K3_ACT_STATE_$actId"
                if ([string]$state.schema -cne 'K3_ACT_STATE_V1' -or [string]$state.act_id -cne $actId) { Add-NV2Error "K3_ACT_STATE_IDENTITY_INVALID: $actId" }
                $stateFields = switch ([string]$state.status) {
                    'PACKET_INSUFFICIENT' { @('schema','act_id','run_id','status','prefix_sha256','model_id','model_revision','submission_sha256') }
                    'AWAITING_CONTINUITY_OUT' { @('schema','act_id','run_id','status','prefix_sha256','model_id','model_revision','submission_sha256','blocks_sha256') }
                    'AWAITING_ATTEST' { @('schema','act_id','run_id','status','prefix_sha256','model_id','model_revision','submission_sha256','blocks_sha256','continuity_out_sha256','generate_run_receipt_relative','generate_run_receipt_sha256') }
                    'ATTESTED' { @('schema','act_id','run_id','status','prefix_sha256','model_id','model_revision','submission_sha256','blocks_sha256','continuity_out_sha256','generate_run_receipt_relative','generate_run_receipt_sha256','attest_run_id','attest_receipt_relative','attest_receipt_sha256','attest_record_relative','attest_record_sha256') }
                    default { $null }
                }
                if ($null -eq $stateFields -or -not (Test-NV2ExactPropertySet -Object $state -Expected $stateFields)) { Add-NV2Error "K3_ACT_STATE_FIELDS_INVALID: $actId/$($state.status)" }
                if ([string]$state.prefix_sha256 -cne $prefixSha -or [string]$state.model_id -cne $modelId -or [string]$state.model_revision -cne $modelRevision) { Add-NV2Error "K3_ACT_STATE_PREFIX_OR_MODEL_STALE: $actId" }
                $actStates.Add($actId, $state)
            }
        }
    }

    $packetsDir = Join-Path $project '_work\k3\packets'
    if (-not (Test-Path -LiteralPath $packetsDir -PathType Container)) { Add-NV2Error 'K3_PACKET_DIRECTORY_MISSING' }
    else {
        foreach ($file in @(Get-ChildItem -LiteralPath $packetsDir -Filter '*.packet.json' -File -Force)) {
            if ($file.Name -notmatch '^(ACT-\d{3})\.packet\.json$') { Add-NV2Error "K3_PACKET_RECORD_NAME_INVALID: $($file.Name)"; continue }
            $actId = $Matches[1]
            if ($actId -notin $sequence) { Add-NV2Error "K3_PACKET_ORPHAN: $actId"; continue }
            $record = Read-NV2Json -Path $file.FullName -Code "K3_PACKET_RECORD_$actId"
            if (-not $record) { continue }
            Test-NV2CanonicalJsonFile -Path $file.FullName -Data $record -Code "K3_PACKET_RECORD_$actId"
            $recordFields = @('schema','act_id','prefix_sha256','packet_sha256','act_projection_sha256','evidence_selection_sha256','narrative_action_registry_sha256','continuity_in_sha256','model_id','model_revision','model_settings_sha256','status')
            if (-not (Test-NV2ExactPropertySet -Object $record -Expected $recordFields)) { Add-NV2Error "K3_PACKET_RECORD_FIELDS_INVALID: $actId" }
            if ([string]$record.schema -cne 'K3_PACKET_RECORD_V2' -or [string]$record.act_id -cne $actId) { Add-NV2Error "K3_PACKET_RECORD_IDENTITY_INVALID: $actId" }
            if ([string]$record.prefix_sha256 -cne $prefixSha -or [string]$record.model_id -cne $modelId -or [string]$record.model_revision -cne $modelRevision -or [string]$record.model_settings_sha256 -cne $modelSettingsSha) { Add-NV2Error "K3_PACKET_PREFIX_OR_MODEL_STALE: $actId" }
            if (-not (Test-NV2ExactMember -Value ([string]$record.status) -Allowed @('PRECHECK_PENDING','READY'))) { Add-NV2Error "K3_PACKET_STATUS_INVALID: $actId/$($record.status)" }
            try {
                $packetPreview = @(& (Join-Path $PSScriptRoot 'Build-K3PacketsV2.ps1') -ProjectPath $project -ActId $actId -AuditExistingAct) | Select-Object -Last 1
                if (-not $packetPreview -or [string]$packetPreview.PacketSha256 -cne [string]$record.packet_sha256 -or [string]$packetPreview.PrefixSha256 -cne [string]$record.prefix_sha256 -or
                    [string]$packetPreview.ActProjectionSha256 -cne [string]$record.act_projection_sha256 -or [string]$packetPreview.EvidenceSelectionSha256 -cne [string]$record.evidence_selection_sha256 -or [string]$packetPreview.NarrativeActionRegistrySha256 -cne [string]$record.narrative_action_registry_sha256 -or [string]$packetPreview.ContinuityInSha256 -cne [string]$record.continuity_in_sha256) {
                    Add-NV2Error "K3_PACKET_NOT_DETERMINISTIC_FROM_CURRENT_INPUTS: $actId"
                }
            } catch { Add-NV2Error "K3_PACKET_PREVIEW_FAILED: $actId :: $($_.Exception.Message)" }
            $packetMarkdown = Join-Path $packetsDir "$actId.packet.md"
            if (-not (Test-Path -LiteralPath $packetMarkdown -PathType Leaf) -or (Get-NV2FileSha256 $packetMarkdown) -cne [string]$record.packet_sha256) { Add-NV2Error "K3_PACKET_MARKDOWN_STALE: $actId" }
            $writeCommandPath = Join-Path $packetsDir "$actId.write-command.md"
            if (-not (Test-Path -LiteralPath $writeCommandPath -PathType Leaf) -or -not (Test-Path -LiteralPath $packetMarkdown -PathType Leaf)) { Add-NV2Error "K3_WRITE_COMMAND_MISSING: $actId" }
            else {
                $packetMarkdownText = Get-Content -LiteralPath $packetMarkdown -Raw -Encoding UTF8
                $commandMatch = [regex]::Match($packetMarkdownText, '(?ms)^## POLECENIE PISANIA I FORMAT WYNIKU\s*\r?\n(?<body>.*)\z')
                $liveCommand = (ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $writeCommandPath -Raw -Encoding UTF8)).Trim() + "`n"
                $embeddedCommand = if ($commandMatch.Success) { (ConvertTo-SystemV7LfText -Text $commandMatch.Groups['body'].Value).Trim() + "`n" } else { '' }
                if (-not $commandMatch.Success -or $liveCommand -cne $embeddedCommand) { Add-NV2Error "K3_WRITE_COMMAND_STALE: $actId" }
            }
            $expectedProjection = $null
            try {
                $expectedProjection = Get-SystemV7ActProjection -ArchitectureData $architectureData -ActId $actId
                $expectedSelection = Get-SystemV7EvidenceSelectionProjection -ActProjection $expectedProjection -EvidenceRegistry $evidenceRegistry
                if ([string]$record.act_projection_sha256 -cne $expectedProjection.Sha256) { Add-NV2Error "K3_ACT_PROJECTION_STALE: $actId" }
                if ([string]$record.evidence_selection_sha256 -cne $expectedSelection.Sha256) { Add-NV2Error "K3_EVIDENCE_SELECTION_STALE: $actId" }
                $selectionPath = Join-Path $packetsDir "$actId.evidence-selection.json"
                if (-not (Test-Path -LiteralPath $selectionPath -PathType Leaf) -or (Get-NV2FileSha256 $selectionPath) -cne $expectedSelection.Sha256) { Add-NV2Error "K3_EVIDENCE_SELECTION_FILE_STALE: $actId" }
                $actionRegistryPath=Join-Path $packetsDir "$actId.narrative-action-registry.json"
                if(-not(Test-Path -LiteralPath $actionRegistryPath -PathType Leaf) -or (Get-NV2FileSha256 $actionRegistryPath) -cne [string]$record.narrative_action_registry_sha256){Add-NV2Error "K3_NARRATIVE_ACTION_REGISTRY_FILE_STALE: $actId"}
            } catch { Add-NV2Error "K3_PACKET_PROJECTION_CHECK_FAILED: $actId :: $($_.Exception.Message)" }
            $continuityInPath = Join-Path $project "_work\k3\continuity\$actId.in.json"
            if (-not (Test-Path -LiteralPath $continuityInPath -PathType Leaf) -or (Get-NV2FileSha256 $continuityInPath) -cne [string]$record.continuity_in_sha256) { Add-NV2Error "K3_CONTINUITY_IN_STALE: $actId" }
            $packetCorePath = Join-Path $packetsDir "$actId.act-packet.json"
            $packetCore = Read-NV2Json -Path $packetCorePath -Code "K3_ACT_PACKET_$actId"
            if ($packetCore) {
                Test-NV2CanonicalJsonFile -Path $packetCorePath -Data $packetCore -Code "K3_ACT_PACKET_$actId"
                $packetCoreFields = @('packet_schema','workflow_revision','project_id','act_id','act_function','entry_knowledge_state','exit_knowledge_state','intended_emotional_pressure_in','intended_emotional_pressure_out','scene_weave_ids','scene_contracts','narrative_action_registry','narrative_action_registry_sha256','constraint_ids','required_p','supporting_p','open_nq_ids','nq_actions','nr_actions','vc_ids','humor_mode','narrator_mode','new_names','exposition_risk','complexity_flag','completion_criteria','bridge_out','do_not_reveal','continuity_in_sha256','prefix_sha256','act_projection_sha256','evidence_selection_sha256','model_id','model_revision','model_settings_sha256','packet_status')
                if (-not (Test-NV2ExactPropertySet -Object $packetCore -Expected $packetCoreFields)) { Add-NV2Error "K3_ACT_PACKET_FIELDS_INVALID: $actId" }
                if ([string]$packetCore.packet_schema -cne 'K3_PACKET_V2' -or [string]$packetCore.workflow_revision -cne '2026-08-31_NARRATIVE_V2' -or [string]$packetCore.act_id -cne $actId -or
                    [string]$packetCore.project_id -cne [string]$origin.ProjectId -or [string]$packetCore.prefix_sha256 -cne $prefixSha -or [string]$packetCore.model_id -cne $modelId -or [string]$packetCore.model_revision -cne $modelRevision -or [string]$packetCore.model_settings_sha256 -cne $modelSettingsSha -or [string]$packetCore.packet_status -cne 'PRECHECK_PENDING') { Add-NV2Error "K3_ACT_PACKET_IDENTITY_INVALID: $actId" }
                if ([string]$packetCore.act_projection_sha256 -cne [string]$record.act_projection_sha256 -or [string]$packetCore.evidence_selection_sha256 -cne [string]$record.evidence_selection_sha256 -or [string]$packetCore.narrative_action_registry_sha256 -cne [string]$record.narrative_action_registry_sha256 -or [string]$packetCore.continuity_in_sha256 -cne [string]$record.continuity_in_sha256) { Add-NV2Error "K3_ACT_PACKET_HASH_LINK_INVALID: $actId" }
                $sceneContractState=Get-SystemV7PacketSceneContractState -Packet $packetCore
                if(-not $sceneContractState.Valid){foreach($problem in @($sceneContractState.Errors)){Add-NV2Error "K3_ACT_PACKET_SCENE_CONTRACT_INVALID: $actId/$problem"}}
            }
            $constraintPath = Join-Path $packetsDir "$actId.constraint-ledger.json"
            $constraint = Read-NV2Json -Path $constraintPath -Code "K3_CONSTRAINT_LEDGER_$actId"
            $constraintFileSha = if (Test-Path -LiteralPath $constraintPath -PathType Leaf) { Get-NV2FileSha256 $constraintPath } else { '' }
            if ($constraint -and ([string]$constraint.schema -cne 'CONSTRAINT_LEDGER_V1' -or [string]$constraint.act_id -cne $actId -or [int]$constraint.max_total -ne 7 -or [int]$constraint.actual_total -ne @($constraint.constraints).Count -or @($constraint.constraints).Count -gt 7)) { Add-NV2Error "K3_CONSTRAINT_LEDGER_INVALID: $actId" }
            if ($constraint -and $expectedProjection) {
                $expectedConstraint = [ordered]@{schema='CONSTRAINT_LEDGER_V1';act_id=$actId;max_total=7;actual_total=@($expectedProjection.Act.constraints).Count;constraints=@($expectedProjection.Act.constraints)}
                if ((ConvertTo-SystemV7CanonicalJson -Value $constraint) -cne (ConvertTo-SystemV7CanonicalJson -Value $expectedConstraint)) { Add-NV2Error "K3_CONSTRAINT_LEDGER_STALE: $actId" }
            }
            if($packetCore -and $constraint){
                $atomicity=Get-SystemV7ConstraintAtomicityState -Packet $packetCore -Ledger $constraint
                foreach($problem in @($atomicity.Errors)){Add-NV2Error "K3_CONSTRAINT_ATOMICITY_INVALID: $actId/$problem"}
            }
            $embargoPath = Join-Path $packetsDir "$actId.do-not-reveal.json"
            $embargo = Read-NV2Json -Path $embargoPath -Code "K3_DO_NOT_REVEAL_$actId"
            if ($embargo -and $expectedProjection) {
                Test-NV2CanonicalJsonFile -Path $embargoPath -Data $embargo -Code "K3_DO_NOT_REVEAL_$actId"
                $expectedEmbargo = [ordered]@{schema='DO_NOT_REVEAL_V1';act_id=$actId;items=@($expectedProjection.Act.do_not_reveal)}
                if ((ConvertTo-SystemV7CanonicalJson -Value $embargo) -cne (ConvertTo-SystemV7CanonicalJson -Value $expectedEmbargo)) { Add-NV2Error "K3_DO_NOT_REVEAL_STALE: $actId" }
            }
            $preflightPath = Join-Path $packetsDir "$actId.constraint-preflight.json"
            $preflight = Read-NV2Json -Path $preflightPath -Code "K3_CONSTRAINT_PREFLIGHT_$actId"
            if ($preflight) {
                Test-NV2CanonicalJsonFile -Path $preflightPath -Data $preflight -Code "K3_CONSTRAINT_PREFLIGHT_$actId"
                if ([string]$preflight.schema -cne 'CONSTRAINT_ATOMICITY_PREFLIGHT_V1' -or [string]$preflight.act_id -cne $actId -or [string]$preflight.packet_sha256 -cne [string]$record.packet_sha256 -or
                    [string]$preflight.constraint_ledger_sha256 -cne $constraintFileSha) { Add-NV2Error "K3_CONSTRAINT_PREFLIGHT_IDENTITY_INVALID: $actId" }
                if ([string]$record.status -ceq 'READY') {
                    if ([string]$preflight.status -cne 'PASS') { Add-NV2Error "K3_CONSTRAINT_PREFLIGHT_NOT_PASS: $actId" }
                    else {
                        $proofPath = Resolve-NV2ProjectRelativePath -Relative ([string]$preflight.run_receipt_relative) -Code "K3_CONSTRAINT_PREFLIGHT_$actId"
                        if ($proofPath) {
                            $proof = Get-NV2RunReceiptState -ReceiptPath $proofPath
                            if (-not $proof.Valid -or [string]$proof.Data.run_type -cne 'CONSTRAINT_ATOMICITY_PREFLIGHT' -or [string]$proof.Sha256 -cne [string]$preflight.run_receipt_sha256) { Add-NV2Error "K3_CONSTRAINT_PREFLIGHT_PROOF_INVALID: $actId" }
                            elseif ((Get-Content -LiteralPath (Join-Path $project ([string]$proof.Data.output_relative)) -Raw -Encoding UTF8) -notmatch '(?m)^VERDICT:\s*PASS\s*$') { Add-NV2Error "K3_CONSTRAINT_PREFLIGHT_OUTPUT_NOT_PASS: $actId" }
                        }
                    }
                } else { Add-NV2Error "K3_PACKET_NOT_READY: $actId" }
            }
            $packetRecords.Add($actId, $record)
        }
    }

    function Test-NV2BeatFlow {
        param([Parameter(Mandatory)][object]$Act)

        $actId = [string]$Act.act_id
        $complexity = [string]$Act.complexity_flag
        $beatDir = Join-Path $project "_work\k3\beats\$actId"
        $beatDirExists = Test-Path -LiteralPath $beatDir -PathType Container
        if ($complexity -cne 'COMPLEX') {
            if ($beatDirExists) { Add-NV2Error "K3_SIMPLE_ACT_HAS_UNEXPECTED_BEAT_STATE: $actId" }
            return
        }
        if (-not $beatDirExists) {
            $actStatus = if ($actStates.ContainsKey($actId)) { [string]$actStates[$actId].status } else { '' }
            if ($actStatus -and $actStatus -cne 'PACKET_INSUFFICIENT') { Add-NV2Error "K3_COMPLEX_BEAT_STATE_MISSING: $actId/$actStatus" }
            elseif ($stageIndex -ge [Array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE'),'K3')) { Add-NV2Error "K3_COMPLEX_BEAT_STATE_MISSING: $actId" }
            return
        }

        try { Assert-SystemV7TreeNoReparse -RootPath $beatDir -ContainmentRoot $project | Out-Null }
        catch { Add-NV2Error "K3_BEAT_PATH_SAFETY: $actId :: $($_.Exception.Message)" }
        foreach ($entry in @(Get-ChildItem -LiteralPath $beatDir -Force)) {
            if ($entry.PSIsContainer -or -not (Test-NV2ExactMember -Value $entry.Name -Allowed @('beat-sheet.json','state.json'))) { Add-NV2Error "K3_BEAT_DIRECTORY_ENTRY_FORBIDDEN: $actId/$($entry.Name)" }
        }

        $sheetPath = Join-Path $beatDir 'beat-sheet.json'
        $statePath = Join-Path $beatDir 'state.json'
        $sheet = Read-NV2Json -Path $sheetPath -Code "K3_BEAT_SHEET_$actId"
        $beatState = Read-NV2Json -Path $statePath -Code "K3_BEAT_STATE_$actId"
        if (-not $sheet -or -not $beatState) { return }
        Test-NV2CanonicalJsonFile -Path $sheetPath -Data $sheet -Code "K3_BEAT_SHEET_$actId"
        Test-NV2CanonicalJsonFile -Path $statePath -Data $beatState -Code "K3_BEAT_STATE_$actId"

        $sheetFields = @('schema','act_id','packet_status','generate_run_id','beats')
        $stateFields = @('schema','act_id','generate_run_id','status','beat_sheet_sha256','prefix_sha256','model_id','model_revision','preflight_run_id','preflight_receipt_relative','preflight_receipt_sha256')
        if (-not (Test-NV2ExactPropertySet -Object $sheet -Expected $sheetFields)) { Add-NV2Error "K3_BEAT_SHEET_FIELDS_INVALID: $actId" }
        if (-not (Test-NV2ExactPropertySet -Object $beatState -Expected $stateFields)) { Add-NV2Error "K3_BEAT_STATE_FIELDS_INVALID: $actId" }
        if ([string]$sheet.schema -cne 'K3_BEAT_SHEET_V1' -or [string]$sheet.act_id -cne $actId -or [string]$sheet.packet_status -cne 'BEAT_SHEET_READY' -or @($sheet.beats).Count -eq 0) { Add-NV2Error "K3_BEAT_SHEET_IDENTITY_INVALID: $actId" }
        if ([string]$beatState.schema -cne 'K3_BEAT_STATE_V1' -or [string]$beatState.act_id -cne $actId -or [string]$beatState.generate_run_id -cne [string]$sheet.generate_run_id) { Add-NV2Error "K3_BEAT_STATE_IDENTITY_INVALID: $actId" }
        if ([string]$beatState.beat_sheet_sha256 -cne (Get-NV2FileSha256 $sheetPath)) { Add-NV2Error "K3_BEAT_SHEET_SHA_STALE: $actId" }
        if ([string]$beatState.prefix_sha256 -cne $prefixSha -or [string]$beatState.model_id -cne $modelId -or [string]$beatState.model_revision -cne $modelRevision) { Add-NV2Error "K3_BEAT_PREFIX_OR_MODEL_STALE: $actId" }
        if (-not $beatStates.ContainsKey($actId)) { $beatStates.Add($actId, $beatState) }

        $packetPath = Join-Path $project "_work\k3\packets\$actId.act-packet.json"
        $packet = Read-NV2Json -Path $packetPath -Code "K3_BEAT_PACKET_$actId"
        $packetCurrentSha = if (Test-Path -LiteralPath $packetPath -PathType Leaf) { Get-NV2FileSha256 $packetPath } else { '' }
        if ($packet) {
            if ([string]$packet.complexity_flag -cne 'COMPLEX' -or [string]$packet.act_id -cne $actId -or [string]$packet.prefix_sha256 -cne [string]$beatState.prefix_sha256 -or
                [string]$packet.model_id -cne [string]$beatState.model_id -or [string]$packet.model_revision -cne [string]$beatState.model_revision) { Add-NV2Error "K3_BEAT_PACKET_BINDING_INVALID: $actId" }

            $semanticBeat=Get-SystemV7BeatSheetSemanticState -Packet $packet -BeatSheet $sheet -ActId $actId -ExpectedGenerateRunId ([string]$beatState.generate_run_id)
            if(-not $semanticBeat.Valid){foreach($problem in $semanticBeat.Errors){Add-NV2Error "K3_BEAT_SEMANTIC_INVALID: $actId/$problem"}}
        }

        $generateRunId = [string]$beatState.generate_run_id
        $generateManifestPath = Join-Path $project "_work\narrative-runs\$generateRunId\input-manifest.json"
        $generateBundle = Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $generateManifestPath
        if (-not $generateBundle.Valid -or [string]$generateBundle.Data.run_type -cne 'GENERATE_ACT' -or [string]$generateBundle.Data.run_id -cne $generateRunId) {
            Add-NV2Error "K3_BEAT_GENERATE_BUNDLE_INVALID: $actId/$($generateBundle.Errors -join ',')"
        } else {
            $packetEntries = @($generateBundle.Data.entries | Where-Object { [string]$_.content_role -ceq 'ACT_PACKET' })
            if ($packetEntries.Count -ne 1) { Add-NV2Error "K3_BEAT_GENERATE_PACKET_INPUT_INVALID: $actId" }
            else {
                $snapshot = Resolve-NV2ProjectRelativePath -Relative ([string]$packetEntries[0].bundle_relative) -Code "K3_BEAT_GENERATE_PACKET_$actId"
                $snapshotPacket = if ($snapshot) { Read-NV2Json -Path $snapshot -Code "K3_BEAT_GENERATE_PACKET_$actId" } else { $null }
                if ([string]$packetEntries[0].sha256 -cne $packetCurrentSha -or ($snapshotPacket -and ([string]$snapshotPacket.act_id -cne $actId -or [string]$snapshotPacket.complexity_flag -cne 'COMPLEX' -or [string]$snapshotPacket.prefix_sha256 -cne [string]$beatState.prefix_sha256 -or [string]$snapshotPacket.model_id -cne [string]$beatState.model_id -or [string]$snapshotPacket.model_revision -cne [string]$beatState.model_revision))) { Add-NV2Error "K3_BEAT_GENERATE_PACKET_STALE: $actId" }
            }
        }

        if ([string]$beatState.status -ceq 'AWAITING_BEAT_PREFLIGHT') {
            foreach ($field in @('preflight_run_id','preflight_receipt_relative','preflight_receipt_sha256')) { if ([string]$beatState.$field -cne 'BRAK') { Add-NV2Error "K3_BEAT_PENDING_HAS_PROOF: $actId/$field" } }
        } elseif ([string]$beatState.status -ceq 'BEAT_PREFLIGHT_PASS') {
            $preflightRunId = [string]$beatState.preflight_run_id
            $receiptPath = Resolve-NV2ProjectRelativePath -Relative ([string]$beatState.preflight_receipt_relative) -Code "K3_BEAT_PREFLIGHT_RECEIPT_$actId"
            $expectedReceiptPath = Join-Path $project "_work\narrative-runs\$preflightRunId\run-receipt.json"
            if (-not $receiptPath -or -not $receiptPath.Equals($expectedReceiptPath, [StringComparison]::OrdinalIgnoreCase)) { Add-NV2Error "K3_BEAT_PREFLIGHT_RECEIPT_PATH_MISMATCH: $actId" }
            $proof = if ($receiptPath) { Get-NV2RunReceiptState -ReceiptPath $receiptPath } else { $null }
            if (-not $proof -or -not $proof.Valid -or [string]$proof.Data.run_type -cne 'BEAT_PREFLIGHT' -or [string]$proof.Data.run_id -cne $preflightRunId -or [string]$proof.Sha256 -cne [string]$beatState.preflight_receipt_sha256) {
                Add-NV2Error "K3_BEAT_PREFLIGHT_RECEIPT_INVALID: $actId"
            } else {
                $preflightManifestPath = Resolve-NV2ProjectRelativePath -Relative ([string]$proof.Data.input_manifest_relative) -Code "K3_BEAT_PREFLIGHT_BUNDLE_$actId"
                $preflightBundle = if ($preflightManifestPath) { Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $preflightManifestPath } else { $null }
                if (-not $preflightBundle -or -not $preflightBundle.Valid -or [string]$preflightBundle.Data.run_type -cne 'BEAT_PREFLIGHT') { Add-NV2Error "K3_BEAT_PREFLIGHT_BUNDLE_INVALID: $actId" }
                else {
                    $roles = @($preflightBundle.Data.entries | ForEach-Object { [string]$_.content_role })
                    if (-not (Test-NV2StringSetEqual -Left $roles -Right @('ACT_PACKET','BEAT_SHEET','BEAT_SCHEMA'))) { Add-NV2Error "K3_BEAT_PREFLIGHT_INPUT_PROFILE_INVALID: $actId" }
                    $beatEntry = @($preflightBundle.Data.entries | Where-Object { [string]$_.content_role -ceq 'BEAT_SHEET' })
                    if ($beatEntry.Count -ne 1 -or [string]$beatEntry[0].sha256 -cne (Get-NV2FileSha256 $sheetPath)) { Add-NV2Error "K3_BEAT_PREFLIGHT_SHEET_STALE: $actId" }
                    $preflightPacketEntry = @($preflightBundle.Data.entries | Where-Object { [string]$_.content_role -ceq 'ACT_PACKET' })
                    if ($preflightPacketEntry.Count -ne 1 -or [string]$preflightPacketEntry[0].sha256 -cne $packetCurrentSha) { Add-NV2Error "K3_BEAT_PREFLIGHT_PACKET_STALE: $actId" }
                }
                $outputPath = Resolve-NV2ProjectRelativePath -Relative ([string]$proof.Data.output_relative) -Code "K3_BEAT_PREFLIGHT_OUTPUT_$actId"
                $output = if ($outputPath -and (Test-Path -LiteralPath $outputPath -PathType Leaf)) { Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 } else { '' }
                foreach ($field in @('VERDICT','ACT_ID','SCHEMA_CHECK','IDENTIFIER_CHECK','STATE_TRANSITION_CHECK','NO_ADDED_SOURCE_OR_REVEAL','DISCREPANCIES','REASON')) {
                    if (@([regex]::Matches($output, "(?m)^${field}:\s*(.*?)\s*$")).Count -ne 1) { Add-NV2Error "K3_BEAT_PREFLIGHT_OUTPUT_FIELD_COUNT_INVALID: $actId/$field" }
                }
                foreach ($field in @('VERDICT','SCHEMA_CHECK','IDENTIFIER_CHECK','STATE_TRANSITION_CHECK','NO_ADDED_SOURCE_OR_REVEAL')) { if ($output -notmatch "(?m)^${field}:\s*PASS\s*$") { Add-NV2Error "K3_BEAT_PREFLIGHT_OUTPUT_NOT_PASS: $actId/$field" } }
                if ($output -notmatch "(?m)^ACT_ID:\s*$([regex]::Escape($actId))\s*$" -or $output -notmatch '(?m)^DISCREPANCIES:\s*BRAK\s*$') { Add-NV2Error "K3_BEAT_PREFLIGHT_OUTPUT_ID_OR_DISCREPANCIES_INVALID: $actId" }
                $reasonMatch = [regex]::Match($output, '(?m)^REASON:\s*(.*?)\s*$')
                if (-not $reasonMatch.Success -or -not (Test-NV2Concrete $reasonMatch.Groups[1].Value)) { Add-NV2Error "K3_BEAT_PREFLIGHT_REASON_NOT_CONCRETE: $actId" }
            }
        } else { Add-NV2Error "K3_BEAT_STATE_STATUS_INVALID: $actId/$($beatState.status)" }
    }

    foreach ($act in @($architectureData.acts)) { Test-NV2BeatFlow -Act $act }
    $beatsRoot = Join-Path $project '_work\k3\beats'
    if (Test-Path -LiteralPath $beatsRoot -PathType Container) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $beatsRoot -Force)) {
            if (-not $entry.PSIsContainer -or $entry.Name -notin $sequence) { Add-NV2Error "K3_BEAT_ORPHAN_OR_LEGACY_ENTRY: $($entry.Name)" }
        }
    }
}

function Test-NV2AttestedAct {
    param(
        [Parameter(Mandatory)][string]$ActId,
        [Parameter(Mandatory)][int]$ActIndex
    )
    if (-not $actStates.ContainsKey($ActId)) { return $false }
    $state = $actStates[$ActId]
    $architectureAct = @($architectureData.acts | Where-Object { [string]$_.act_id -ceq $ActId })
    $isComplexAct = $architectureAct.Count -eq 1 -and [string]$architectureAct[0].complexity_flag -ceq 'COMPLEX'
    $actDir = Join-Path $project "_work\k3\acts\$ActId"
    if ([string]$state.status -ceq 'PACKET_INSUFFICIENT') {
        $insufficientPath = Join-Path $actDir 'packet-insufficient.json'
        $insufficient = Read-NV2Json -Path $insufficientPath -Code "K3_PACKET_INSUFFICIENT_$ActId"
        if ($insufficient) {
            $expected = @('schema','act_id','packet_status','no_prose_generated','blocks','reason_code','sw_id','exact_gap','why_blocking','affected_ids','repair_route')
            if (-not (Test-NV2ExactPropertySet -Object $insufficient -Expected $expected) -or [string]$insufficient.schema -cne 'K3_ACT_SUBMISSION_V2' -or
                [string]$insufficient.packet_status -cne 'PACKET_INSUFFICIENT' -or $insufficient.no_prose_generated -cne $true -or @($insufficient.blocks).Count -ne 0) {
                Add-NV2Error "K3_PACKET_INSUFFICIENT_RECORD_INVALID: $ActId"
            }
        }
        foreach ($forbidden in @('prose.md','blocks.json','out.json','session-output.json')) { if (Test-Path -LiteralPath (Join-Path $actDir $forbidden)) { Add-NV2Error "K3_PACKET_INSUFFICIENT_WITH_PROSE_ARTIFACT: $ActId/$forbidden" } }
        Add-NV2Error "K3_PACKET_INSUFFICIENT_BLOCKS_GATE: $ActId"
        return $false
    }
    if ([string]$state.status -cne 'ATTESTED') {
        if (-not (Test-NV2ExactMember -Value ([string]$state.status) -Allowed @('AWAITING_CONTINUITY_OUT','AWAITING_ATTEST'))) { Add-NV2Error "K3_ACT_STATUS_INVALID: $ActId/$($state.status)" }
        return $false
    }
    if ($isComplexAct -and (-not $beatStates.ContainsKey($ActId) -or [string]$beatStates[$ActId].status -cne 'BEAT_PREFLIGHT_PASS')) { Add-NV2Error "K3_COMPLEX_ACT_WITHOUT_PASS_BEAT_PREFLIGHT: $ActId" }
    if (-not $isComplexAct -and $beatStates.ContainsKey($ActId)) { Add-NV2Error "K3_SIMPLE_ACT_WITH_BEAT_STATE: $ActId" }

    $blocksPath = Join-Path $actDir 'blocks.json'
    $prosePath = Join-Path $actDir 'prose.md'
    $outPath = Join-Path $actDir 'out.json'
    $sessionPath = Join-Path $project "_work\narrative-runs\$([string]$state.run_id)\output.json"
    $inPath = Join-Path $project "_work\k3\continuity\$ActId.in.json"
    $attestPath = Join-Path $project "_work\k3\continuity\$ActId.attest.json"
    foreach ($path in @($blocksPath,$prosePath,$outPath,$sessionPath,$inPath,$attestPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-NV2Error "K3_ATTESTED_ACT_ARTIFACT_MISSING: $ActId/$path" }
    }
    $missingActArtifacts = @(@($blocksPath,$prosePath,$outPath,$sessionPath,$inPath,$attestPath) | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missingActArtifacts.Count -gt 0) { return $false }

    $blocks = Read-NV2Json -Path $blocksPath -Code "K3_BLOCKS_$ActId"
    $out = Read-NV2Json -Path $outPath -Code "K3_CONTINUITY_OUT_$ActId"
    $continuityIn = Read-NV2Json -Path $inPath -Code "K3_CONTINUITY_IN_$ActId"
    $attest = Read-NV2Json -Path $attestPath -Code "K3_CONTINUITY_ATTEST_$ActId"
    $session = Read-NV2Json -Path $sessionPath -Code "K3_GENERATE_SESSION_$ActId"
    if (-not $blocks -or -not $out -or -not $continuityIn -or -not $attest -or -not $session) { return $false }
    foreach ($pair in @(@($blocksPath,$blocks,"K3_BLOCKS_$ActId"),@($outPath,$out,"K3_CONTINUITY_OUT_$ActId"),@($inPath,$continuityIn,"K3_CONTINUITY_IN_$ActId"),@($attestPath,$attest,"K3_CONTINUITY_ATTEST_$ActId"),@($sessionPath,$session,"K3_GENERATE_SESSION_$ActId"))) {
        Test-NV2CanonicalJsonFile -Path $pair[0] -Data $pair[1] -Code $pair[2]
    }

    if (-not (Test-NV2ExactPropertySet -Object $blocks -Expected @('schema','act_id','run_id','prefix_sha256','model_id','model_revision','submission_sha256','blocks'))) { Add-NV2Error "K3_BLOCK_MAP_FIELDS_INVALID: $ActId" }
    if ([string]$blocks.schema -cne 'K3_ACT_BLOCKS_V1' -or [string]$blocks.act_id -cne $ActId -or [string]$blocks.run_id -cne [string]$state.run_id -or [string]$blocks.submission_sha256 -cne [string]$state.submission_sha256 -or [string]$blocks.prefix_sha256 -cne $prefixSha -or
        [string]$blocks.model_id -cne $modelId -or [string]$blocks.model_revision -cne $modelRevision) { Add-NV2Error "K3_BLOCK_MAP_IDENTITY_INVALID: $ActId" }
    $selectionPath = Join-Path $project "_work\k3\packets\$ActId.evidence-selection.json"
    $selection = Read-NV2Json -Path $selectionPath -Code "K3_SELECTION_FOR_BLOCKS_$ActId"
    $allowedSources = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($selection) { foreach ($card in @($selection.cards)) { [void]$allowedSources.Add([string]$card.p_id) } }
    $proseParts = [Collections.Generic.List[string]]::new()
    $blockIndex = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $blockNumber = 0
    foreach ($block in @($blocks.blocks)) {
        $blockNumber++
        $expectedBlockId = 'BLOCK-{0}-{1:D3}' -f $ActId,$blockNumber
        if (-not (Test-NV2ExactPropertySet -Object $block -Expected @('block_id','block_sha256','word_count','trace_refs','sw_ids','source_p_ids','narrative_refs','prose'))) { Add-NV2Error "K3_BLOCK_FIELDS_INVALID: $ActId/$expectedBlockId"; continue }
        if ([string]$block.block_id -cne $expectedBlockId -or $blockIndex.ContainsKey([string]$block.block_id)) { Add-NV2Error "K3_BLOCK_ID_INVALID_OR_DUPLICATE: $ActId/$($block.block_id)"; continue }
        $blockIndex.Add([string]$block.block_id, $block)
        $blockProse = (ConvertTo-SystemV7LfText -Text ([string]$block.prose)).Trim()
        $actualBlockSha = Get-SystemV7NarrativeSha256Text -Text ($blockProse + "`n")
        if ($actualBlockSha -cne [string]$block.block_sha256) { Add-NV2Error "K3_BLOCK_SHA_STALE: $($block.block_id)" }
        $words = Get-NV2WordCount -Text $blockProse
        if ([int]$block.word_count -ne $words -or $words -gt 220) { Add-NV2Error "K3_BLOCK_GRANULARITY_INVALID: $($block.block_id)/$words" }
        if (@($block.source_p_ids).Count -eq 0) { Add-NV2Error "K3_BLOCK_SOURCE_TRACE_EMPTY: $($block.block_id)" }
        if (@($block.sw_ids).Count -eq 0 -or @($block.sw_ids | Where-Object { [string]$_ -notmatch '^SW-\d{3}$' }).Count -gt 0 -or @($block.sw_ids | Select-Object -Unique).Count -ne @($block.sw_ids).Count) { Add-NV2Error "K3_BLOCK_SW_IDS_INVALID: $($block.block_id)" }
        if (@($block.source_p_ids | Select-Object -Unique).Count -ne @($block.source_p_ids).Count) { Add-NV2Error "K3_BLOCK_SOURCE_TRACE_DUPLICATE: $($block.block_id)" }
        foreach ($evidenceId in @($block.source_p_ids)) { if (-not $allowedSources.Contains([string]$evidenceId)) { Add-NV2Error "K3_BLOCK_SOURCE_OUTSIDE_PACKET: $($block.block_id)/$evidenceId" } }
        [void]$proseParts.Add($blockProse)
    }
    if ($blockNumber -eq 0) { Add-NV2Error "K3_BLOCK_MAP_EMPTY: $ActId" }
    $expectedProse = (($proseParts -join "`n`n") + "`n")
    $actualProse = ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $prosePath -Raw -Encoding UTF8)
    if ($actualProse -cne $expectedProse) { Add-NV2Error "K3_PROSE_NOT_DETERMINISTIC_FROM_BLOCKS: $ActId" }
    if ($actualProse -match '(?i)#P-\d{3}|\bBLOCK-(?:ACT-)?\d|<!--|PACKET_STATUS|SELF_CHECK') { Add-NV2Error "K3_PROSE_TECHNICAL_RESIDUE: $ActId" }
    $spokenState=Get-SystemV7PlainSpokenTextState -Text $actualProse;if(-not $spokenState.Valid){Add-NV2Error "K3_PROSE_NOT_PLAIN_SPOKEN_TEXT: $ActId/$($spokenState.Errors -join ',')"}
    $tracePacket=Read-NV2Json -Path (Join-Path $project "_work\k3\packets\$ActId.act-packet.json") -Code "K3_TRACE_PACKET_$ActId"
    if($tracePacket){$traceBeat=$null;if([string]$tracePacket.complexity_flag -ceq 'COMPLEX'){$traceBeat=Read-NV2Json -Path (Join-Path $project "_work\k3\beats\$ActId\beat-sheet.json") -Code "K3_TRACE_BEAT_$ActId"};$traceState=Get-SystemV7ActSubmissionTraceState -Packet $tracePacket -Blocks @($blocks.blocks) -BeatSheet $traceBeat;if(-not $traceState.Valid){foreach($problem in $traceState.Errors){Add-NV2Error "K3_ACT_TRACE_INVALID: $ActId/$problem"}}else{foreach($block in @($blocks.blocks)){$expectedSw=[Collections.Generic.List[string]]::new();$seenSw=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($traceRef in @($block.trace_refs)){if($traceState.TraceToSw.Contains([string]$traceRef)){$swId=[string]$traceState.TraceToSw[[string]$traceRef];if($seenSw.Add($swId)){$expectedSw.Add($swId)}}};if((@([string[]]@($block.sw_ids)) -join '|') -cne (@([string[]]@($expectedSw)) -join '|')){Add-NV2Error "K3_BLOCK_SW_IDS_STALE: $ActId/$($block.block_id)"}}}}

    $continuityOutFields = @('schema','act_id','records','nq_paid','nq_opened','nq_reframed','open_nq_ids_out','nr_revealed','nr_consequences','nr_setup_only','character_and_world_state','bridge_realized','bridge_block_refs','opening_move_type','opening_block_refs','closing_move_type','closing_block_refs','uncertainties_preserved')
    if (-not (Test-NV2ExactPropertySet -Object $out -Expected $continuityOutFields)) { Add-NV2Error "K3_CONTINUITY_OUT_FIELDS_INVALID: $ActId" }
    if ([string]$out.schema -cne 'CONTINUITY_OUT_V1' -or [string]$out.act_id -cne $ActId) { Add-NV2Error "K3_CONTINUITY_OUT_IDENTITY_INVALID: $ActId" }
    if (-not (Test-NV2ExactMember -Value ([string]$out.opening_move_type) -Allowed @('SCENA','ANOMALIA','DOKUMENT','KONSEKWENCJA','KONTRAST','KONTAKT_Z_WIDZEM','POWRÓT_DO_MOTYWU'))) { Add-NV2Error "K3_OPENING_MOVE_TYPE_INVALID: $ActId/$($out.opening_move_type)" }
    if (-not (Test-NV2ExactMember -Value ([string]$out.closing_move_type) -Allowed @('DECYZJA','REVEAL','PAYOFF','KONSEKWENCJA','GRANICA_WIEDZY','NOWA_PĘTLA','POWRÓT_DO_MOTYWU'))) { Add-NV2Error "K3_CLOSING_MOVE_TYPE_INVALID: $ActId/$($out.closing_move_type)" }
    $outStructuralState=Get-SystemV7ContinuityOutStructuralState -ActId $ActId -ContinuityOut $out -BlocksData $blocks -ArchitectureData $architectureData
    foreach($problem in @($outStructuralState.Errors)){Add-NV2Error "K3_CONTINUITY_OUT_STRUCTURAL_INVALID: $ActId/$problem"}
    $attestStateIds=@([string[]]@($outStructuralState.StateIds))
    $stateIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in @($out.records)) {
        $fields = @('state_id','category','value','class','block_refs','related_ids','source_p_ids')
        if (-not (Test-NV2ExactPropertySet -Object $record -Expected $fields) -or [string]$record.state_id -notmatch '^STATE-\d{3}$' -or -not $stateIds.Add([string]$record.state_id)) { Add-NV2Error "K3_CONTINUITY_RECORD_INVALID: $ActId/$($record.state_id)"; continue }
        if (-not (Test-NV2ExactMember -Value ([string]$record.category) -Allowed @('FACT','INFERENCE','QUESTION','REVEAL','BRIDGE','WORLD_STATE','KNOWLEDGE_BOUNDARY')) -or -not (Test-NV2ExactMember -Value ([string]$record.class) -Allowed @('TEXT_ASSERTED','VIEWER_INFERENCE'))) { Add-NV2Error "K3_CONTINUITY_RECORD_CLASS_INVALID: $ActId/$($record.state_id)" }
        if (-not (Test-NV2Concrete $record.value) -or @($record.block_refs).Count -eq 0) { Add-NV2Error "K3_CONTINUITY_RECORD_CONTENT_INVALID: $ActId/$($record.state_id)" }
        $available = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($ref in @($record.block_refs)) {
            if (-not (Test-NV2ExactPropertySet -Object $ref -Expected @('block_id','block_sha256'))) { Add-NV2Error "K3_CONTINUITY_BLOCK_REF_FIELDS_INVALID: $ActId/$($record.state_id)"; continue }
            $blockId = [string]$ref.block_id
            if (-not $blockIndex.ContainsKey($blockId)) { Add-NV2Error "K3_CONTINUITY_BLOCK_REF_MISSING: $ActId/$blockId"; continue }
            if ([string]$blockIndex[$blockId].block_sha256 -cne [string]$ref.block_sha256) { Add-NV2Error "K3_CONTINUITY_BLOCK_REF_STALE: $ActId/$blockId" }
            foreach ($evidenceId in @($blockIndex[$blockId].source_p_ids)) { [void]$available.Add([string]$evidenceId) }
        }
        foreach ($evidenceId in @($record.source_p_ids)) { if (-not $available.Contains([string]$evidenceId)) { Add-NV2Error "K3_CONTINUITY_SOURCE_OUTSIDE_BLOCK_REFS: $ActId/$($record.state_id)/$evidenceId" } }
        if ((Test-NV2ExactMember -Value ([string]$record.category) -Allowed @('FACT','REVEAL')) -and @($record.source_p_ids).Count -eq 0) { Add-NV2Error "K3_CONTINUITY_SOURCE_REQUIRED: $ActId/$($record.state_id)" }
    }

    $continuityInFields = @('schema','act_id','source_act_id','source_act_sha256','source_attest_sha256','text_states','viewer_inferences','open_nq_ids','prepared_nr_ids','active_embargoes','world_state','bridge','opening_move_history','closing_move_history','emotional_pressure')
    if (-not (Test-NV2ExactPropertySet -Object $continuityIn -Expected $continuityInFields)) { Add-NV2Error "K3_CONTINUITY_IN_FIELDS_INVALID: $ActId" }
    if ([string]$continuityIn.schema -cne 'CONTINUITY_IN_V1' -or [string]$continuityIn.act_id -cne $ActId) { Add-NV2Error "K3_CONTINUITY_IN_IDENTITY_INVALID: $ActId" }
    if ($ActIndex -eq 0) {
        if ([string]$continuityIn.source_act_id -cne 'NONE' -or [string]$continuityIn.source_attest_sha256 -cne 'NONE') { Add-NV2Error 'K3_FIRST_CONTINUITY_IN_NOT_ROOT' }
    } else {
        $previousAct = [string]$sequence[$ActIndex - 1]
        $previousAttestPath = Join-Path $project "_work\k3\continuity\$previousAct.attest.json"
        $previousProsePath = Join-Path $project "_work\k3\acts\$previousAct\prose.md"
        if (-not (Test-Path -LiteralPath $previousAttestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $previousProsePath -PathType Leaf)) {
            Add-NV2Error "K3_CONTINUITY_PRIOR_ARTIFACT_MISSING: $previousAct->$ActId"
        } else {
            if ([string]$continuityIn.source_act_id -cne $previousAct -or [string]$continuityIn.source_attest_sha256 -cne (Get-NV2FileSha256 $previousAttestPath) -or [string]$continuityIn.source_act_sha256 -cne (Get-NV2FileSha256 $previousProsePath)) { Add-NV2Error "K3_CONTINUITY_CHAIN_LINK_INVALID: $previousAct->$ActId" }
            $previousAttest = Read-NV2Json -Path $previousAttestPath -Code "K3_PRIOR_ATTEST_$previousAct"
            if ($previousAttest) {
                $expectedIn = ConvertTo-SystemV7CanonicalNode -Value $previousAttest.next_continuity_in
                $expectedIn.source_attest_sha256 = Get-NV2FileSha256 $previousAttestPath
                if ((ConvertTo-SystemV7CanonicalJson -Value $expectedIn) -cne (ConvertTo-SystemV7CanonicalJson -Value $continuityIn)) { Add-NV2Error "K3_CONTINUITY_IN_NOT_DERIVED_FROM_PRIOR_ATTEST: $ActId" }
            }
        }
    }

    $generatePath = Resolve-NV2ProjectRelativePath -Relative ([string]$state.generate_run_receipt_relative) -Code "K3_GENERATE_RECEIPT_$ActId"
    $generateProof = if ($generatePath) { Get-NV2RunReceiptState -ReceiptPath $generatePath } else { $null }
    if (-not $generateProof -or -not $generateProof.Valid -or [string]$generateProof.Data.run_type -cne 'GENERATE_ACT' -or [string]$generateProof.Sha256 -cne [string]$state.generate_run_receipt_sha256 -or
        [string]$generateProof.Data.run_id -cne [string]$state.run_id -or [string]$generateProof.Data.model_id -cne $modelId -or [string]$generateProof.Data.model_revision -cne $modelRevision -or [string]$generateProof.Data.model_settings_sha256 -cne $modelSettingsSha) { Add-NV2Error "K3_GENERATE_RECEIPT_INVALID: $ActId" }
    $expectedBeatSheetSha = if ($isComplexAct -and $beatStates.ContainsKey($ActId)) { [string]$beatStates[$ActId].beat_sheet_sha256 } else { 'NOT_APPLICABLE' }
    if (-not (Test-NV2ExactPropertySet -Object $session -Expected @('schema','act_id','run_id','beat_sheet_sha256','prose_submission_sha256','blocks_file_sha256','continuity_out_submission_sha256','continuity_out_content_sha256'))) { Add-NV2Error "K3_GENERATE_SESSION_OUTPUT_FIELDS_INVALID: $ActId" }
    if ([string]$session.schema -cne 'K3_GENERATE_ACT_SESSION_OUTPUT_V1' -or [string]$session.act_id -cne $ActId -or [string]$session.run_id -cne [string]$state.run_id -or [string]$session.beat_sheet_sha256 -cne $expectedBeatSheetSha -or [string]$session.prose_submission_sha256 -cne [string]$state.submission_sha256 -or
        [string]$session.blocks_file_sha256 -cne (Get-NV2FileSha256 $blocksPath) -or [string]$session.continuity_out_content_sha256 -cne (Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $out))) { Add-NV2Error "K3_GENERATE_SESSION_OUTPUT_INVALID: $ActId" }
    if ($generateProof -and [string]$generateProof.Data.output_sha256 -cne (Get-NV2FileSha256 $sessionPath)) { Add-NV2Error "K3_GENERATE_RECEIPT_OUTPUT_STALE: $ActId" }

    if (-not (Test-NV2ExactPropertySet -Object $attest -Expected @('schema','workflow_revision','act_id','verdict','prefix_sha256','model_id','model_revision','blocks_sha256','continuity_in_sha256','continuity_out_sha256','attest_output_sha256','run_receipt_relative','run_receipt_sha256','next_continuity_in'))) { Add-NV2Error "K3_ATTEST_RECORD_FIELDS_INVALID: $ActId" }
    if ([string]$attest.schema -cne 'CONTINUITY_ATTEST_RECORD_V1' -or [string]$attest.workflow_revision -cne '2026-08-31_NARRATIVE_V2' -or [string]$attest.act_id -cne $ActId -or [string]$attest.verdict -cne 'PASS' -or
        [string]$attest.prefix_sha256 -cne $prefixSha -or [string]$attest.model_id -cne $modelId -or [string]$attest.model_revision -cne $modelRevision -or
        [string]$attest.blocks_sha256 -cne (Get-NV2FileSha256 $blocksPath) -or [string]$attest.continuity_in_sha256 -cne (Get-NV2FileSha256 $inPath) -or [string]$attest.continuity_out_sha256 -cne (Get-NV2FileSha256 $outPath)) { Add-NV2Error "K3_ATTEST_RECORD_INVALID: $ActId" }
    $attestReceiptPath = Resolve-NV2ProjectRelativePath -Relative ([string]$attest.run_receipt_relative) -Code "K3_ATTEST_RECEIPT_$ActId"
    $attestProof = if ($attestReceiptPath) { Get-NV2RunReceiptState -ReceiptPath $attestReceiptPath } else { $null }
    if (-not $attestProof -or -not $attestProof.Valid -or [string]$attestProof.Data.run_type -cne 'CONTINUITY_ATTEST' -or [string]$attestProof.Data.run_id -cne [string]$state.attest_run_id -or [string]$attestProof.Sha256 -cne [string]$attest.run_receipt_sha256) { Add-NV2Error "K3_ATTEST_RECEIPT_INVALID: $ActId" }
    elseif ($generateProof -and [string]$generateProof.Data.task_id -ceq [string]$attestProof.Data.task_id) { Add-NV2Error "K3_GENERATE_ATTEST_TASK_COLLISION: $ActId" }
    if ($attestProof) {
        $attestOutputPath = Resolve-NV2ProjectRelativePath -Relative ([string]$attestProof.Data.output_relative) -Code "K3_ATTEST_OUTPUT_$ActId"
        $attestResult = if ($attestOutputPath) { Read-NV2Json -Path $attestOutputPath -Code "K3_ATTEST_RESULT_$ActId" } else { $null }
        if ($attestResult) {
            $resultFields = @('schema','act_id','verdict','record_results','missing_state_change','question_arithmetic_verdict','reason')
            if (-not (Test-NV2ExactPropertySet -Object $attestResult -Expected $resultFields) -or [string]$attestResult.schema -cne 'CONTINUITY_ATTEST_RESULT_V1' -or [string]$attestResult.act_id -cne $ActId -or
                [string]$attestResult.verdict -cne 'PASS' -or $attestResult.missing_state_change -cne $false -or [string]$attestResult.question_arithmetic_verdict -cne 'PASS') { Add-NV2Error "K3_ATTEST_RESULT_NOT_PASS: $ActId" }
            $resultIds = @($attestResult.record_results | ForEach-Object { [string]$_.state_id })
            if (-not (Test-NV2StringSetEqual -Left $attestStateIds -Right $resultIds) -or @($attestResult.record_results | Where-Object { [string]$_.verdict -cne 'PASS' }).Count -gt 0) { Add-NV2Error "K3_ATTEST_RECORD_COVERAGE_INVALID: $ActId" }
            if ([string]$attest.attest_output_sha256 -cne (Get-NV2FileSha256 $attestOutputPath)) { Add-NV2Error "K3_ATTEST_OUTPUT_HASH_STALE: $ActId" }
        }
    }
    $expectedAttestRecordRelative = Get-SystemV7NarrativeRelativePath -Root $project -Path $attestPath
    if ([string]$state.blocks_sha256 -cne (Get-NV2FileSha256 $blocksPath) -or [string]$state.continuity_out_sha256 -cne (Get-NV2FileSha256 $outPath) -or
        [string]$state.attest_record_relative -cne $expectedAttestRecordRelative -or [string]$state.attest_record_sha256 -cne (Get-NV2FileSha256 $attestPath) -or
        [string]$state.attest_receipt_relative -cne [string]$attest.run_receipt_relative -or [string]$state.attest_receipt_sha256 -cne [string]$attest.run_receipt_sha256) { Add-NV2Error "K3_ATTESTED_STATE_POINTER_STALE: $ActId" }

    $expectedNext = if ($ActIndex + 1 -lt $sequence.Count) { [string]$sequence[$ActIndex + 1] } else { 'COMPLETE' }
    if ([string]$attest.next_continuity_in.act_id -cne $expectedNext -or [string]$attest.next_continuity_in.source_act_id -cne $ActId -or [string]$attest.next_continuity_in.source_attest_sha256 -cne 'BOUND_ON_CONSUMPTION') { Add-NV2Error "K3_ATTEST_NEXT_CONTINUITY_INVALID: $ActId" }
    return $true
}

$attestedActIds = [Collections.Generic.List[string]]::new()
$continuityOutputsByAct = @{}
$continuityInputsByAct = @{}
if ($architectureData -and $stageIndex -ge [Array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE'),'K2B')) {
    $gapSeen = $false
    for ($index=0; $index -lt $sequence.Count; $index++) {
        $actId = [string]$sequence[$index]
        $validAttest = Test-NV2AttestedAct -ActId $actId -ActIndex $index
        if ($validAttest) {
            if ($gapSeen) { Add-NV2Error "K3_ATTEST_SEQUENCE_GAP: $actId" }
            [void]$attestedActIds.Add($actId)
        } else { $gapSeen = $true }
    }
    foreach ($actId in @($attestedActIds)) {
        $outPath = Join-Path $project "_work\k3\acts\$actId\out.json"
        $inPath = Join-Path $project "_work\k3\continuity\$actId.in.json"
        if (Test-Path -LiteralPath $outPath -PathType Leaf) { $continuityOutputsByAct[$actId] = Get-Content -LiteralPath $outPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 64 }
        if (Test-Path -LiteralPath $inPath -PathType Leaf) { $continuityInputsByAct[$actId] = Get-Content -LiteralPath $inPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 64 }
    }
    if ($attestedActIds.Count -gt 0) {
        $continuityHeadActId = [string]$attestedActIds[$attestedActIds.Count - 1]
        $continuityReplay = Get-SystemV7OrderedContinuityReplayState -ArchitectureData $architectureData -ThroughActId $continuityHeadActId -OutputsByAct $continuityOutputsByAct -ContinuityInputsByAct $continuityInputsByAct -RequireOutputs -RequireContinuityInputs
        foreach ($problem in @($continuityReplay.Errors)) { Add-NV2Error "K3_CONTINUITY_REPLAY: $problem" }
        # The shared state reader additionally recomputes the complete
        # next_continuity_in payload (including records, embargoes, world
        # state, move history and pressure) and recursively binds every IN to
        # the immutable prior attest. Checking the contiguous head validates
        # the whole accepted chain without maintaining a second reducer here.
        $continuityHeadState = Get-SystemV7ContinuityAttestState -ProjectPath $project -ActId $continuityHeadActId
        foreach ($problem in @($continuityHeadState.Errors)) { Add-NV2Error "K3_CONTINUITY_ATTEST_CHAIN: $problem" }
    }
    $expectedLast = if ($attestedActIds.Count -gt 0) { $attestedActIds[$attestedActIds.Count - 1] } else { 'BRAK' }
    if ((Get-NV2DocumentField -Text $meta -Name 'K3_LAST_ATTESTED_ACT') -cne $expectedLast) { Add-NV2Error "K3_LAST_ATTESTED_ACT_MISMATCH: expected=$expectedLast" }
    $continuityStatus = Get-NV2DocumentField -Text $meta -Name 'CONTINUITY_STATUS'
    if ($attestedActIds.Count -eq $sequence.Count -and $sequence.Count -gt 0) {
        if ($continuityStatus -cne 'COMPLETE') { Add-NV2Error 'CONTINUITY_STATUS_NOT_COMPLETE' }
    } elseif ($attestedActIds.Count -gt 0 -and $continuityStatus -cne 'IN_PROGRESS') { Add-NV2Error 'CONTINUITY_STATUS_NOT_IN_PROGRESS' }
    elseif ($attestedActIds.Count -eq 0 -and -not (Test-NV2ExactMember -Value $continuityStatus -Allowed @('NIEURUCHOMIONA','IN_PROGRESS'))) { Add-NV2Error "CONTINUITY_STATUS_INVALID_BEFORE_FIRST_ATTEST: $continuityStatus" }
    $firstIncompleteIndex = $attestedActIds.Count
    $activeReady = [Collections.Generic.List[string]]::new()
    foreach ($attestedActId in $attestedActIds) { if (-not $packetRecords.ContainsKey([string]$attestedActId)) { Add-NV2Error "K3_ATTESTED_ACT_PACKET_RECORD_MISSING: $attestedActId" } }
    foreach ($entry in $packetRecords.GetEnumerator()) {
        $packetIndex = [Array]::IndexOf([string[]]$sequence, [string]$entry.Key)
        if ($packetIndex -gt $firstIncompleteIndex) { Add-NV2Error "K3_FUTURE_PACKET_BEFORE_PRIOR_ATTEST: $($entry.Key)" }
        $stateStatus = if ($actStates.ContainsKey([string]$entry.Key)) { [string]$actStates[[string]$entry.Key].status } else { '' }
        if ([string]$entry.Value.status -ceq 'READY' -and $stateStatus -cne 'ATTESTED') { [void]$activeReady.Add([string]$entry.Key) }
    }
    if ($attestedActIds.Count -lt $sequence.Count) {
        if ($activeReady.Count -ne 1 -or [string]$activeReady[0] -cne [string]$sequence[$firstIncompleteIndex]) { Add-NV2Error "K3_READY_PACKET_UNIQUENESS_FAIL: ready=$($activeReady -join ',') expected=$($sequence[$firstIncompleteIndex])" }
    } elseif ($activeReady.Count -ne 0) { Add-NV2Error "K3_READY_PACKET_REMAINS_AFTER_COMPLETE: $($activeReady -join ',')" }
    if ($stage -ceq 'K2B' -and $attestedActIds.Count -gt 0) { Add-NV2Error 'K2B_MUST_NOT_CONTAIN_GENERATED_ATTESTED_ACTS' }
    if ($stageIndex -ge [Array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE'),'K3') -and $attestedActIds.Count -ne $sequence.Count) { Add-NV2Error "K3_ACT_SEQUENCE_INCOMPLETE: $($attestedActIds.Count)/$($sequence.Count)" }
}

# Ten gate jest niezależny od poprawności architektury. Na K4+ brak lub
# niezatwierdzona decyzja o powtórzeniach musi być widoczna nawet wtedy, gdy
# walidator równolegle raportuje uszkodzony artefakt K2B.
if($stage -in @('K4','K5','COMPLETE')){
    $moveReview=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project
    foreach($problem in @($moveReview.Errors)){Add-NV2Error "MOVE_REPETITION_REVIEW_INVALID: $problem"}
    if(-not $moveReview.GateReady){Add-NV2Error "MOVE_REPETITION_REVIEW_ALERT_UNRESOLVED: $($moveReview.ReviewStatus)"}
}

function Test-NV2Assembly {
    if ($sequence.Count -eq 0 -or $attestedActIds.Count -ne $sequence.Count) { return }
    $draftPath = Join-Path $project '03-draft.md'
    if (-not (Test-Path -LiteralPath $draftPath -PathType Leaf)) { Add-NV2Error 'K3_DRAFT_MISSING'; return }
    $draft = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
    $draftSha = Get-NV2FileSha256 $draftPath
    $contentRevision = 0
    if (-not [int]::TryParse((Get-NV2DocumentField -Text $draft -Name 'CONTENT_REVISION'), [ref]$contentRevision) -or $contentRevision -lt 1) { Add-NV2Error 'K3_DRAFT_CONTENT_REVISION_INVALID' }
    $draftDate = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact((Get-NV2DocumentField -Text $draft -Name 'DATE'), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$draftDate) -or $draftDate.Date -gt [DateTime]::UtcNow.Date) { Add-NV2Error 'K3_DRAFT_DATE_INVALID' }
    if ((Get-NV2DocumentField -Text $draft -Name 'BASELINE_FOR_QA') -cne 'NONE' -or (Get-NV2DocumentField -Text $draft -Name 'CHANGE_SCOPE_PERCENT') -cne '0') { Add-NV2Error 'K3_DRAFT_BASELINE_OR_CHANGE_SCOPE_INVALID' }
    if ((Get-NV2DocumentField -Text $draft -Name 'WORKFLOW_REVISION') -cne '2026-08-31_NARRATIVE_V2' -or (Get-NV2DocumentField -Text $draft -Name 'EVIDENCE_SCHEMA') -cne 'MINIMAL_EVIDENCE_V4_PAGELOC' -or
        (Get-NV2DocumentField -Text $draft -Name 'PREFIX_SHA256') -cne $prefixSha -or (Get-NV2DocumentField -Text $draft -Name 'K3_MODEL_ID') -cne $modelId -or
        (Get-NV2DocumentField -Text $draft -Name 'K3_MODEL_REVISION') -cne $modelRevision -or (Get-NV2DocumentField -Text $draft -Name 'CONTINUITY_CHAIN_STATUS') -cne 'COMPLETE') { Add-NV2Error 'K3_DRAFT_TECHNICAL_IDENTITY_INVALID' }
    $mapMatch = [regex]::Match($draft, '(?s)<!--\s*K3_BLOCK_MAP_BEGIN\s*-->\s*```json\s*(?<json>.*?)\s*```\s*<!--\s*K3_BLOCK_MAP_END\s*-->')
    if (-not $mapMatch.Success) { Add-NV2Error 'K3_DRAFT_BLOCK_MAP_MISSING'; return }
    try { $draftMap = $mapMatch.Groups['json'].Value | ConvertFrom-Json -DateKind String -Depth 64 }
    catch { Add-NV2Error "K3_DRAFT_BLOCK_MAP_INVALID_JSON: $($_.Exception.Message)"; return }
    $mapActs = [Collections.Generic.List[object]]::new()
    $assemblyActs = [Collections.Generic.List[object]]::new()
    $narrationParts = [Collections.Generic.List[string]]::new()
    foreach ($actId in $sequence) {
        $actDir = Join-Path $project "_work\k3\acts\$actId"
        $prosePath = Join-Path $actDir 'prose.md'
        $blocksPath = Join-Path $actDir 'blocks.json'
        $attestPath = Join-Path $project "_work\k3\continuity\$actId.attest.json"
        $blocks = Get-Content -LiteralPath $blocksPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 64
        $prose = (ConvertTo-SystemV7LfText -Text (Get-Content -LiteralPath $prosePath -Raw -Encoding UTF8)).Trim()
        [void]$narrationParts.Add("### $actId`n`n$prose")
        $packetPath=Join-Path $project "_work\k3\packets\$actId.act-packet.json";$packet=Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;$traceToSw=@{}
        if([string]$packet.complexity_flag -ceq 'COMPLEX'){$beatPath=Join-Path $project "_work\k3\beats\$actId\beat-sheet.json";$beatSheet=Get-Content -LiteralPath $beatPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String -Depth 64;foreach($beat in @($beatSheet.beats)){$traceToSw[[string]$beat.beat_id]=[string]$beat.sw_id}}else{foreach($swId in @($packet.scene_weave_ids)){$traceToSw[[string]$swId]=[string]$swId}}
        $mapBlocks = @($blocks.blocks | ForEach-Object {$sourceBlock=$_;$swIds=[Collections.Generic.List[string]]::new();$swSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($traceRef in @($sourceBlock.trace_refs)){if($traceToSw.ContainsKey([string]$traceRef)){$swId=[string]$traceToSw[[string]$traceRef];if($swSeen.Add($swId)){$swIds.Add($swId)}}else{Add-NV2Error "K3_DRAFT_TRACE_TO_SW_MISSING: $actId/$traceRef"}};if((@([string[]]@($sourceBlock.sw_ids)) -join '|') -cne (@([string[]]@($swIds)) -join '|')){Add-NV2Error "K3_DRAFT_BLOCK_SW_IDS_STALE: $actId/$($sourceBlock.block_id)"};[ordered]@{block_id=$sourceBlock.block_id;block_sha256=$sourceBlock.block_sha256;word_count=$sourceBlock.word_count;trace_refs=@($sourceBlock.trace_refs);sw_ids=@($sourceBlock.sw_ids);source_p_ids=@($sourceBlock.source_p_ids);narrative_refs=@($sourceBlock.narrative_refs)} })
        [void]$mapActs.Add([ordered]@{act_id=$actId;prose_sha256=(Get-NV2FileSha256 $prosePath);blocks_sha256=(Get-NV2FileSha256 $blocksPath);attest_sha256=(Get-NV2FileSha256 $attestPath);blocks=$mapBlocks})
        [void]$assemblyActs.Add([ordered]@{act_id=$actId;prose_relative=(Get-SystemV7NarrativeRelativePath -Root $project -Path $prosePath);prose_sha256=(Get-NV2FileSha256 $prosePath);blocks_sha256=(Get-NV2FileSha256 $blocksPath);attest_sha256=(Get-NV2FileSha256 $attestPath)})
    }
    $expectedMap = [ordered]@{schema='K3_BLOCK_MAP_V1';prefix_sha256=$prefixSha;model_id=$modelId;model_revision=$modelRevision;acts=@($mapActs)}
    if ((ConvertTo-SystemV7CanonicalJson -Value $draftMap) -cne (ConvertTo-SystemV7CanonicalJson -Value $expectedMap)) { Add-NV2Error 'K3_DRAFT_BLOCK_MAP_STALE' }
    $expectedNarration = (($narrationParts -join "`n`n") + "`n")
    $narrationMatch = [regex]::Match($draft, '(?ms)^##\s+NARRACJA ROBOCZA\s*\r?\n(?<body>.*)$')
    if (-not $narrationMatch.Success) { Add-NV2Error 'K3_DRAFT_NARRATION_SECTION_MISSING'; return }
    $actualNarration = (ConvertTo-SystemV7LfText -Text $narrationMatch.Groups['body'].Value).Trim() + "`n"
    if ($actualNarration -cne $expectedNarration) { Add-NV2Error 'K3_DRAFT_NOT_DETERMINISTIC_ASSEMBLY' }
    $clean = Get-SystemV7CleanNarrationFromDraft -DraftText $draft
    $wordCount = Get-NV2WordCount -Text $clean
    $declaredWords = 0
    if (-not [int]::TryParse((Get-NV2DocumentField -Text $draft -Name 'WORD_COUNT'), [ref]$declaredWords) -or $declaredWords -ne $wordCount) { Add-NV2Error "K3_DRAFT_WORD_COUNT_MISMATCH: declared=$declaredWords actual=$wordCount" }
    if ((Get-NV2DocumentField -Text $draft -Name 'WORDS_PER_MINUTE') -cne [string]$realWpm) { Add-NV2Error 'K3_DRAFT_WPM_MISMATCH' }
    if ($realWpm -gt 0) {
        $expectedMinutes = [math]::Round($wordCount / [double]$realWpm, 2)
        if (-not (Test-NV2DurationValue -Declared (Get-NV2DocumentField -Text $draft -Name 'ESTIMATED_DURATION') -Expected $expectedMinutes)) { Add-NV2Error 'K3_DRAFT_ESTIMATED_DURATION_MISMATCH' }
    } else { Add-NV2Error 'K3_DRAFT_DURATION_UNCHECKABLE_WITH_INVALID_WPM' }
    $assemblySha = Get-NV2DocumentField -Text $draft -Name 'ASSEMBLY_MANIFEST_SHA256'
    $manifestPath = Join-Path $project "_work\k3\assembly\$assemblySha.json"
    $manifest = Read-NV2Json -Path $manifestPath -Code 'K3_ASSEMBLY_MANIFEST'
    if ($manifest) {
        Test-NV2CanonicalJsonFile -Path $manifestPath -Data $manifest -Code 'K3_ASSEMBLY_MANIFEST'
        $core = [ordered]@{schema='K3_ASSEMBLY_MANIFEST_V1';workflow_revision='2026-08-31_NARRATIVE_V2';project_origin_sha256=$script:NV2OriginSha256;prefix_sha256=$prefixSha;model_id=$modelId;model_revision=$modelRevision;acts=@($assemblyActs);block_map_content_sha256=(Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $expectedMap));narration_sha256=(Get-SystemV7NarrativeSha256Text -Text $expectedNarration)}
        $expectedSha = Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $core)
        if ($assemblySha -cne $expectedSha -or [string]$manifest.assembly_manifest_sha256 -cne $expectedSha) { Add-NV2Error 'K3_ASSEMBLY_MANIFEST_BINDING_MISMATCH' }
        $actualCore = [ordered]@{}
        foreach ($property in $manifest.PSObject.Properties) { if ($property.Name -cne 'assembly_manifest_sha256') { $actualCore[$property.Name]=$property.Value } }
        if ((ConvertTo-SystemV7CanonicalJson -Value $actualCore) -cne (ConvertTo-SystemV7CanonicalJson -Value $core)) { Add-NV2Error 'K3_ASSEMBLY_MANIFEST_CONTENT_STALE' }
    }
    if ($durationMode -in @('GUIDE','HARD_MAX') -and $targetMinutes -gt 0 -and $realWpm -gt 0) {
        $duration = Get-SystemV7DurationState -Narration $clean -TargetMinutes $targetMinutes -RealWpm $realWpm -Mode $durationMode
        if ($durationMode -ceq 'GUIDE' -and $duration.Alert) { Add-NV2Warning "DURATION_GUIDE_ALERT: estimated=$($duration.EstimatedMinutes) target=$targetMinutes" }
        if ($durationMode -ceq 'HARD_MAX' -and -not $duration.Pass) {
            if ($stageIndex -ge [Array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE'),'K5')) { Add-NV2Error "DURATION_HARD_MAX_EXCEEDED: words=$($duration.WordCount) max=$($duration.MaximumWords)" }
            else { Add-NV2Warning "DURATION_HARD_MAX_EXCEEDED_BEFORE_K5: words=$($duration.WordCount) max=$($duration.MaximumWords)" }
        }
    }
    $script:NV2DraftPath = $draftPath
    $script:NV2DraftText = $draft
    $script:NV2DraftSha256 = $draftSha
    $script:NV2CleanNarration = $clean
}

$script:NV2DraftPath = $null
$script:NV2DraftText = $null
$script:NV2DraftSha256 = $null
$script:NV2CleanNarration = $null
if ($stageIndex -ge [Array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE'),'K3')) { Test-NV2Assembly }

function Test-NV2BundleSourceFreshness {
    param([Parameter(Mandatory)][object]$RunState, [Parameter(Mandatory)][string]$Label)
    if (-not $RunState.Valid -or -not $RunState.Data) { return }
    $manifestPath = Join-Path $project ([string]$RunState.Data.input_manifest_relative)
    $bundle = Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $manifestPath
    if (-not $bundle.Valid) { return }
    foreach ($entry in @($bundle.Data.entries)) {
        $sourcePath = Resolve-NV2ProjectRelativePath -Relative ([string]$entry.source_relative) -Code "${Label}_SOURCE"
        if (-not $sourcePath) { continue }
        if ([string]$entry.kind -ceq 'FILE') {
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or (Get-NV2FileSha256 $sourcePath) -cne [string]$entry.sha256) { Add-NV2Error "${Label}_SOURCE_STALE: $($entry.content_role)" }
        } elseif ([string]$entry.kind -ceq 'DIRECTORY') {
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) { Add-NV2Error "${Label}_SOURCE_DIRECTORY_MISSING: $($entry.content_role)"; continue }
            $records = [Collections.Generic.List[object]]::new()
            $rootPrefix = $sourcePath.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
            $paths = [string[]]@(Get-ChildItem -LiteralPath $sourcePath -File -Recurse -Force | ForEach-Object FullName)
            [Array]::Sort($paths, [StringComparer]::Ordinal)
            foreach ($path in $paths) {
                $relative = $path.Substring($rootPrefix.Length).Replace('\','/')
                if ($relative -match '(^|/)(?:__pycache__|\.git)(/|$)') { continue }
                $item = Get-Item -LiteralPath $path -Force
                [void]$records.Add([ordered]@{relative=$relative;sha256=(Get-NV2FileSha256 $path);bytes=$item.Length})
            }
            $sha = Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value @($records))
            if ($sha -cne [string]$entry.sha256) { Add-NV2Error "${Label}_SOURCE_DIRECTORY_STALE: $($entry.content_role)" }
        }
    }
}

# The generate and blind-attest receipts must still point to the exact packet/blocks/IN/OUT
# that form the accepted act, not merely to internally consistent stale bundle copies.
foreach ($actId in @($attestedActIds)) {
    if (-not $actStates.ContainsKey($actId)) { continue }
    $state = $actStates[$actId]
    $generatePath = Resolve-NV2ProjectRelativePath -Relative ([string]$state.generate_run_receipt_relative) -Code "K3_GENERATE_SOURCE_FRESHNESS_$actId"
    if ($generatePath) {
        $generateState = Get-NV2RunReceiptState -ReceiptPath $generatePath
        if ($generateState.Valid) { Test-NV2BundleSourceFreshness -RunState $generateState -Label "K3_GENERATE_$actId" }
    }
    $attestPath = Resolve-NV2ProjectRelativePath -Relative ([string]$state.attest_receipt_relative) -Code "K3_ATTEST_SOURCE_FRESHNESS_$actId"
    if ($attestPath) {
        $attestState = Get-NV2RunReceiptState -ReceiptPath $attestPath
        if ($attestState.Valid) { Test-NV2BundleSourceFreshness -RunState $attestState -Label "K3_ATTEST_$actId" }
    }
}

function Resolve-NV2LensProof {
    param(
        [Parameter(Mandatory)][ValidateSet('EDITOR','VERIFY','COLD_READER')][string]$Lens,
        [Parameter(Mandatory)][string]$ProofPath,
        [Parameter(Mandatory)][string]$ExpectedDraftSha256,
        [Collections.Generic.HashSet[string]]$Visited,
        [int]$Depth = 0
    )
    if ($Depth -gt 32) { Add-NV2Error "K4_CARRYFORWARD_CHAIN_TOO_DEEP: $Lens"; return $null }
    if ($null -eq $Visited) { $Visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }
    $full = [IO.Path]::GetFullPath($ProofPath)
    if (-not $Visited.Add($full)) { Add-NV2Error "K4_CARRYFORWARD_CYCLE: $Lens"; return $null }
    $data = Read-NV2Json -Path $full -Code "K4_${Lens}_PROOF"
    if (-not $data) { return $null }
    if ([string]$data.schema -ceq 'SYSTEM_V7_NARRATIVE_RUN_RECEIPT_V1') {
        $state = Get-NV2RunReceiptState -ReceiptPath $full
        if (-not $state.Valid -or [string]$state.Data.run_type -cne $Lens) { Add-NV2Error "K4_${Lens}_RUN_RECEIPT_INVALID"; return $null }
        # A current RUN must still bind the live draft. A RUN reached through a
        # carry-forward chain intentionally binds an older immutable bundle;
        # comparing its source_relative with today's 03-draft.md would reject
        # every legal carry-forward after the first draft change.
        if ($Depth -eq 0) { Test-NV2BundleSourceFreshness -RunState $state -Label "K4_${Lens}" }
        $outputPath = Resolve-NV2ProjectRelativePath -Relative ([string]$state.Data.output_relative) -Code "K4_${Lens}_OUTPUT"
        if (-not $outputPath -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { Add-NV2Error "K4_${Lens}_OUTPUT_MISSING"; return $null }
        $output = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
        if ($output -notmatch "(?m)^LENS:\s*$([regex]::Escape($Lens))\s*$" -or $output -notmatch '(?m)^VERDICT:\s*PASS\s*$' -or
            $output -notmatch "(?m)^DRAFT_SHA256:\s*$([regex]::Escape($ExpectedDraftSha256))\s*$") { Add-NV2Error "K4_${Lens}_OUTPUT_NOT_CURRENT_PASS" }
        return [pscustomobject]@{ProofType='RUN';ProofPath=$full;ProofSha256=$state.Sha256;OutputSha256=[string]$state.Data.output_sha256;BaseTaskId=[string]$state.Data.task_id;RunId=[string]$state.Data.run_id;OutputPath=$outputPath}
    }
    if ([string]$data.schema -cne 'SYSTEM_V7_QA_CARRYFORWARD_V2') { Add-NV2Error "K4_${Lens}_PROOF_SCHEMA_INVALID: $($data.schema)"; return $null }
    $carry = Get-SystemV7QACarryForwardState -ProjectPath $project -ReceiptPath $full -ExpectedLens $Lens -ExpectedNewDraftSha256 $ExpectedDraftSha256 -Depth $Depth
    if (-not $carry.Valid) { foreach ($problem in @($carry.Errors)) { Add-NV2Error "K4_${Lens}_CARRYFORWARD_INVALID: $problem" }; return $null }
    Test-NV2CanonicalJsonFile -Path $full -Data $carry.Data -Code "K4_${Lens}_CARRYFORWARD"
    if ([string]$carry.Data.project_origin_sha256 -cne $script:NV2OriginSha256) { Add-NV2Error "K4_${Lens}_CARRYFORWARD_ORIGIN_MISMATCH" }
    $impactPath = Join-Path $project "_work\k4\impact\$([string]$carry.Data.diff_sha256).impact.json"
    $impact = Read-NV2Json -Path $impactPath -Code "K4_${Lens}_IMPACT"
    if ($impact) {
        Test-NV2CanonicalJsonFile -Path $impactPath -Data $impact -Code "K4_${Lens}_IMPACT"
        $impactCore = [ordered]@{}
        foreach ($property in $impact.PSObject.Properties) { if ($property.Name -cne 'diff_sha256') { $impactCore[$property.Name]=$property.Value } }
        if ((Get-SystemV7NarrativeSha256Text -Text (ConvertTo-SystemV7CanonicalJson -Value $impactCore)) -cne [string]$impact.diff_sha256 -or [string]$impact.diff_sha256 -cne [string]$carry.Data.diff_sha256) { Add-NV2Error "K4_${Lens}_IMPACT_BINDING_MISMATCH" }
        if ([string]$impact.project_origin_sha256 -cne $script:NV2OriginSha256 -or [string]$impact.old_draft_sha256 -cne [string]$carry.Data.old_draft_sha256 -or [string]$impact.new_draft_sha256 -cne $ExpectedDraftSha256) { Add-NV2Error "K4_${Lens}_IMPACT_DRAFT_OR_ORIGIN_MISMATCH" }
        if ([string]$carry.Data.change_class -ceq 'TYPO_ONLY') {
            # V2 fail-closed policy: only byte-identical input is mechanical.
            # Even punctuation can change meaning and therefore needs a fresh
            # QA_IMPACT_REVIEW before a lens may be carried forward.
            if ([string]$impact.change_class -cne 'BYTE_IDENTICAL' -or [string]$impact.decisions.$Lens -cne 'CARRYFORWARD_ALLOWED') { Add-NV2Error "K4_${Lens}_MECHANICAL_CARRYFORWARD_NOT_ALLOWED" }
        } else {
            $reviewId = [string]$carry.Data.impact_review_run_id
            $reviewPath = Join-Path $project "_work\narrative-runs\$reviewId\run-receipt.json"
            $review = Get-NV2RunReceiptState -ReceiptPath $reviewPath -HistoricalQAImpact:($Depth -gt 0)
            if (-not $review.Valid -or [string]$review.Data.run_type -cne 'QA_IMPACT_REVIEW') { Add-NV2Error "K4_${Lens}_IMPACT_REVIEW_RECEIPT_INVALID" }
            else {
                $reviewOutputPath = Resolve-NV2ProjectRelativePath -Relative ([string]$review.Data.output_relative) -Code "K4_${Lens}_IMPACT_REVIEW_OUTPUT"
                $reviewManifestPath = Resolve-NV2ProjectRelativePath -Relative ([string]$review.Data.input_manifest_relative) -Code "K4_${Lens}_IMPACT_REVIEW_MANIFEST"
                $reviewBundle = if ($reviewManifestPath) { Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $reviewManifestPath } else { $null }
                if (-not $reviewOutputPath -or -not $reviewBundle -or -not $reviewBundle.Valid) {
                    Add-NV2Error "K4_${Lens}_IMPACT_REVIEW_BUNDLE_INVALID"
                } else {
                    $reviewOutputState = Get-SystemV7QAImpactOutputState -ProjectPath $project -OutputPath $reviewOutputPath -BundleData $reviewBundle.Data -HistoricalImpact:($Depth -gt 0)
                    if (-not $reviewOutputState.Valid -or [string]$reviewOutputState.Impact.diff_sha256 -cne [string]$impact.diff_sha256 -or [string]$reviewOutputState.Decisions.$Lens -cne 'CARRYFORWARD_ALLOWED') {
                        Add-NV2Error "K4_${Lens}_IMPACT_REVIEW_DOES_NOT_ALLOW_CARRYFORWARD"
                    }
                }
            }
        }
    }
    $priorPath = Resolve-NV2ProjectRelativePath -Relative ([string]$carry.Data.prior_proof_relative) -Code "K4_${Lens}_PRIOR_PROOF"
    if (-not $priorPath) { return $null }
    $prior = Resolve-NV2LensProof -Lens $Lens -ProofPath $priorPath -ExpectedDraftSha256 ([string]$carry.Data.old_draft_sha256) -Visited $Visited -Depth ($Depth + 1)
    if (-not $prior) { return $null }
    if ([string]$prior.OutputSha256 -cne [string]$carry.Data.prior_output_sha256) { Add-NV2Error "K4_${Lens}_CARRYFORWARD_PRIOR_OUTPUT_MISMATCH" }
    return [pscustomobject]@{ProofType='CARRYFORWARD';ProofPath=$full;ProofSha256=(Get-NV2FileSha256 $full);OutputSha256=[string]$carry.Data.prior_output_sha256;BaseTaskId=[string]$prior.BaseTaskId;RunId=[string]$prior.RunId;OutputPath=[string]$prior.OutputPath}
}

$script:NV2ContinuityChainPath = $null
$script:NV2ContinuityChainSha256 = $null
$script:NV2K4ProofSetSha256 = $null
if ($stageIndex -ge [Array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE'),'K4')) {
    if (-not $script:NV2DraftPath) { Add-NV2Error 'K4_CURRENT_DRAFT_UNAVAILABLE' }
    else {
        $chainPath = Join-Path $project "_work\k4\inputs\continuity-chain-$($script:NV2DraftSha256).json"
        $chain = Read-NV2Json -Path $chainPath -Code 'K4_CONTINUITY_CHAIN'
        if ($chain) {
            Test-NV2CanonicalJsonFile -Path $chainPath -Data $chain -Code 'K4_CONTINUITY_CHAIN'
            if (-not (Test-NV2ExactPropertySet -Object $chain -Expected @('schema','draft_sha256','records'))) { Add-NV2Error 'K4_CONTINUITY_CHAIN_FIELDS_INVALID' }
            if ([string]$chain.schema -cne 'CONTINUITY_CHAIN_V1' -or [string]$chain.draft_sha256 -cne $script:NV2DraftSha256 -or @($chain.records).Count -ne $sequence.Count) { Add-NV2Error 'K4_CONTINUITY_CHAIN_IDENTITY_INVALID' }
            else {
                for ($index=0; $index -lt $sequence.Count; $index++) {
                    $actId = [string]$sequence[$index]
                    $record = $chain.records[$index]
                    $attestPath = Join-Path $project "_work\k3\continuity\$actId.attest.json"
                    $expectedRelative = Get-SystemV7NarrativeRelativePath -Root $project -Path $attestPath
                    if (-not (Test-NV2ExactPropertySet -Object $record -Expected @('act_id','relative','sha256','record')) -or [string]$record.act_id -cne $actId -or [string]$record.relative -cne $expectedRelative -or [string]$record.sha256 -cne (Get-NV2FileSha256 $attestPath) -or
                        (ConvertTo-SystemV7CanonicalJson -Value $record.record) -cne (ConvertTo-SystemV7CanonicalJson -Value (Get-Content -LiteralPath $attestPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 64))) { Add-NV2Error "K4_CONTINUITY_CHAIN_RECORD_STALE: $actId" }
                }
            }
            $script:NV2ContinuityChainPath = $chainPath
            $script:NV2ContinuityChainSha256 = Get-NV2FileSha256 $chainPath
        }

        $lensProofs = [ordered]@{}
        foreach ($lensInfo in @(@('EDITOR','K4_EDITOR_PROOF'),@('VERIFY','K4_VERIFY_PROOF'),@('COLD_READER','K4_COLD_READER_PROOF'))) {
            $lens = $lensInfo[0]
            $relative = Get-NV2DocumentField -Text $meta -Name $lensInfo[1]
            if ([string]::IsNullOrWhiteSpace($relative) -or $relative -ceq 'BRAK') { Add-NV2Error "K4_${lens}_PROOF_MISSING"; continue }
            $path = Resolve-NV2ProjectRelativePath -Relative $relative -Code "K4_${lens}_PROOF"
            if ($path) {
                $proof = Resolve-NV2LensProof -Lens $lens -ProofPath $path -ExpectedDraftSha256 $script:NV2DraftSha256
                if ($proof) { $lensProofs[$lens]=$proof }
            }
        }
        if ($lensProofs.Count -eq 3) {
            $taskIds = @($lensProofs.Values | ForEach-Object { [string]$_.BaseTaskId })
            if (@($taskIds | Select-Object -Unique).Count -ne 3) { Add-NV2Error 'K4_LENS_TASK_ID_COLLISION' }
            if (@($lensProofs.Values | ForEach-Object { [string]$_.ProofPath } | Select-Object -Unique).Count -ne 3) { Add-NV2Error 'K4_LENS_PROOF_COLLISION' }
        }

        $proofSetSha = Get-NV2DocumentField -Text $meta -Name 'K4_PROOF_SET_SHA256'
        if ($proofSetSha -notmatch '^[A-F0-9]{64}$') { Add-NV2Error 'K4_PROOF_SET_SHA_INVALID' }
        else {
            $proofSetState = Get-SystemV7K4ProofSetState -ProjectPath $project -ProofSetSha256 $proofSetSha -ExpectedDraftSha256 $script:NV2DraftSha256
            if (-not $proofSetState.Valid) {
                foreach ($problem in @($proofSetState.Errors)) { Add-NV2Error "K4_PROOF_SET_INVALID: $problem" }
            } elseif ($proofSetState.Data) {
                $proofSetPath = [string]$proofSetState.Path
                $proofSet = $proofSetState.Data
                Test-NV2CanonicalJsonFile -Path $proofSetPath -Data $proofSet -Code 'K4_PROOF_SET'
                $proofSetFields = @('schema','workflow_revision','project_origin_sha256','draft_sha256','continuity_chain_sha256','editor','verify','cold_reader','status','proof_set_sha256')
                if (-not (Test-NV2ExactPropertySet -Object $proofSet -Expected $proofSetFields)) { Add-NV2Error 'K4_PROOF_SET_FIELDS_INVALID' }
                if ([string]$proofSet.schema -cne 'K4_PROOF_SET_V2' -or [string]$proofSet.workflow_revision -cne '2026-08-31_NARRATIVE_V2' -or [string]$proofSet.project_origin_sha256 -cne $script:NV2OriginSha256 -or
                    [string]$proofSet.draft_sha256 -cne $script:NV2DraftSha256 -or [string]$proofSet.continuity_chain_sha256 -cne $script:NV2ContinuityChainSha256 -or [string]$proofSet.status -cne 'PASS') { Add-NV2Error 'K4_PROOF_SET_V2_IDENTITY_OR_STATUS_INVALID' }
                foreach ($pair in @(@('EDITOR','editor'),@('VERIFY','verify'),@('COLD_READER','cold_reader'))) {
                    $lens=$pair[0];$property=$pair[1]
                    $entry=$proofSet.$property
                    if (-not $entry -or -not (Test-NV2ExactPropertySet -Object $entry -Expected @('proof_kind','proof_relative','proof_sha256','output_sha256'))) { Add-NV2Error "K4_PROOF_SET_${lens}_FIELDS_INVALID"; continue }
                    if (-not $lensProofs.Contains($lens)) { continue }
                    $proof=$lensProofs[$lens]
                    $expectedRelative = Get-SystemV7NarrativeRelativePath -Root $project -Path ([string]$proof.ProofPath)
                    if ([string]$entry.proof_kind -cne [string]$proof.ProofType -or [string]$entry.proof_relative -cne $expectedRelative -or [string]$entry.proof_sha256 -cne [string]$proof.ProofSha256 -or [string]$entry.output_sha256 -cne [string]$proof.OutputSha256) {
                        Add-NV2Error "K4_PROOF_SET_${lens}_STALE"
                    }
                    if (-not (Test-NV2ExactMember -Value ([string]$entry.proof_kind) -Allowed @('RUN','CARRYFORWARD'))) { Add-NV2Error "K4_PROOF_SET_${lens}_KIND_INVALID" }
                }
                $script:NV2K4ProofSetSha256 = $proofSetSha
            }
        }

        $qaPath = Join-Path $project '04-raport-qa.md'
        $factPath = Join-Path $project '04B-fact-check.md'
        foreach ($path in @($qaPath,$factPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-NV2Error "K4_REPORT_MISSING: $path" } }
        if ((Test-Path -LiteralPath $qaPath -PathType Leaf) -and (Test-Path -LiteralPath $factPath -PathType Leaf)) {
            $qa = Get-Content -LiteralPath $qaPath -Raw -Encoding UTF8
            $fact = Get-Content -LiteralPath $factPath -Raw -Encoding UTF8
            if ($qa -match '(?m)^(?:EDITOR_RUN_RECEIPT|COLD_READER_RUN_RECEIPT):' -or $fact -match '(?m)^VERIFY_RUN_RECEIPT:') { Add-NV2Error 'K4_REPORT_MIXED_LEGACY_PROOF_POINTERS' }
            foreach ($pair in @(@($qa,'EDITOR_PROOF','K4_EDITOR_PROOF'),@($qa,'COLD_READER_PROOF','K4_COLD_READER_PROOF'),@($fact,'VERIFY_PROOF','K4_VERIFY_PROOF'))) {
                if ((Get-NV2DocumentField -Text $pair[0] -Name $pair[1]) -cne (Get-NV2DocumentField -Text $meta -Name $pair[2])) { Add-NV2Error "K4_REPORT_PROOF_POINTER_MISMATCH: $($pair[1])" }
            }
            foreach ($report in @($qa,$fact)) {
                if ((Get-NV2DocumentField -Text $report -Name 'AKTUALNY_WERDYKT') -cne 'PASS' -or (Get-NV2FirstField -Text $report -Name 'DRAFT_SHA256') -cne $script:NV2DraftSha256 -or
                    (Get-NV2DocumentField -Text $report -Name 'K4_QA_SCHEMA') -cne 'THREE_LENS_QA_V1' -or (Get-NV2DocumentField -Text $report -Name 'K4_PROOF_SET_SHA256') -cne $script:NV2K4ProofSetSha256) { Add-NV2Error 'K4_REPORT_NOT_CURRENT_PASS' }
            }
            foreach ($pair in @(@($qa,'EDITOR_PROOF_KIND','EDITOR'),@($qa,'COLD_READER_PROOF_KIND','COLD_READER'),@($fact,'VERIFY_PROOF_KIND','VERIFY'))) {
                $kind = Get-NV2DocumentField -Text $pair[0] -Name $pair[1]
                if (-not (Test-NV2ExactMember -Value $kind -Allowed @('RUN','CARRYFORWARD')) -or ($lensProofs.Contains($pair[2]) -and $kind -cne [string]$lensProofs[$pair[2]].ProofType)) { Add-NV2Error "K4_REPORT_PROOF_KIND_INVALID: $($pair[1])" }
            }
        }
    }
}

if ($stageIndex -ge [Array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE'),'K5')) {
    $finalPath = Join-Path $project '05-FINAL-SCRIPT.md'
    if (-not (Test-Path -LiteralPath $finalPath -PathType Leaf)) { Add-NV2Error 'K5_FINAL_MISSING' }
    elseif (-not $script:NV2DraftPath) { Add-NV2Error 'K5_DRAFT_BINDING_UNAVAILABLE' }
    else {
        try{$finalBytes=[IO.File]::ReadAllBytes($finalPath);$final=[Text.UTF8Encoding]::new($false,$true).GetString($finalBytes)}catch{$final='';Add-NV2Error 'K5_FINAL_NOT_STRICT_UTF8'}
        $qaPath = Join-Path $project '04-raport-qa.md'
        $factPath = Join-Path $project '04B-fact-check.md'
        $finalSha = Get-NV2FileSha256 $finalPath
        $qaCurrentSha = if (Test-Path -LiteralPath $qaPath -PathType Leaf) { Get-NV2FileSha256 $qaPath } else { '' }
        $factCurrentSha = if (Test-Path -LiteralPath $factPath -PathType Leaf) { Get-NV2FileSha256 $factPath } else { '' }
        if (-not $qaCurrentSha -or -not $factCurrentSha) { Add-NV2Error 'K5_SOURCE_REPORT_MISSING' }
        if ((Get-NV2DocumentField -Text $final -Name 'STATUS') -cne 'ZATWIERDZONY') { Add-NV2Error 'K5_FINAL_STATUS_NOT_APPROVED' }
        if ((Get-NV2DocumentField -Text $final -Name 'SOURCE_DRAFT_REVISION') -cne (Get-NV2DocumentField -Text $script:NV2DraftText -Name 'CONTENT_REVISION') -or
            (Get-NV2DocumentField -Text $final -Name 'SOURCE_DRAFT_SHA256') -cne $script:NV2DraftSha256 -or
            (Get-NV2DocumentField -Text $final -Name 'SOURCE_QA_SHA256') -cne $qaCurrentSha -or
            (Get-NV2DocumentField -Text $final -Name 'SOURCE_FACTCHECK_SHA256') -cne $factCurrentSha) { Add-NV2Error 'K5_FINAL_SOURCE_BINDING_STALE' }
        if ((Get-NV2DocumentField -Text $final -Name 'K4_PROOF_SET_SHA256') -cne $script:NV2K4ProofSetSha256 -or (Get-NV2DocumentField -Text $final -Name 'CONTINUITY_CHAIN_SHA256') -cne $script:NV2ContinuityChainSha256 -or
            (Get-NV2DocumentField -Text $final -Name 'CONTINUITY_STATUS') -cne 'PASS') { Add-NV2Error 'K5_FINAL_NARRATIVE_V2_PROOF_BINDING_INVALID' }
        $narrationMatches = @([regex]::Matches($final, '(?ms)^## NARRACJA DO NAGRANIA\n(?<body>.*)\z'))
        $finalNarration = if ($narrationMatches.Count -eq 1) { $narrationMatches[0].Groups['body'].Value } else { '';Add-NV2Error 'K5_FINAL_NARRATION_SECTION_MISSING_OR_NONCANONICAL' }
        if (-not (Test-NV2Concrete $finalNarration 25)) { Add-NV2Error 'K5_FINAL_NARRATION_EMPTY' }
        if ($finalNarration -match '(?im)^\s*#{1,6}\s|<!--|-->|#P-\d{3,}|\bBLOCK-(?:ACT-)?\d|^\s*\|.*\|\s*$|^(?:STATUS|SOURCE_[A-Z_]+|FINAL_WORD_COUNT|REAL_WPM|ESTIMATED_DURATION|K4_PROOF_SET_SHA256|CONTINUITY_\w+):|PACKET_STATUS|SELF_CHECK') { Add-NV2Error 'K5_FINAL_TECHNICAL_RESIDUE' }
        $finalSpokenState=Get-SystemV7PlainSpokenTextState -Text $finalNarration;if(-not $finalSpokenState.Valid){Add-NV2Error "K5_FINAL_NOT_PLAIN_SPOKEN_TEXT: $($finalSpokenState.Errors -join ',')"}
        $finalWords = Get-NV2WordCount -Text $finalNarration
        $declaredFinalWords = 0
        if (-not [int]::TryParse((Get-NV2DocumentField -Text $final -Name 'FINAL_WORD_COUNT'), [ref]$declaredFinalWords) -or $declaredFinalWords -ne $finalWords) { Add-NV2Error "K5_FINAL_WORD_COUNT_MISMATCH: declared=$declaredFinalWords actual=$finalWords" }
        if ((Get-NV2DocumentField -Text $final -Name 'REAL_WPM') -cne [string]$realWpm) { Add-NV2Error 'K5_FINAL_WPM_MISMATCH' }
        if ($realWpm -gt 0) {
            $expectedFinalMinutes = [math]::Round($finalWords / [double]$realWpm, 2)
            if (-not (Test-NV2DurationValue -Declared (Get-NV2DocumentField -Text $final -Name 'ESTIMATED_DURATION') -Expected $expectedFinalMinutes)) { Add-NV2Error 'K5_FINAL_ESTIMATED_DURATION_MISMATCH' }
        } else { Add-NV2Error 'K5_FINAL_DURATION_UNCHECKABLE_WITH_INVALID_WPM' }
        if ($durationMode -in @('GUIDE','HARD_MAX') -and $targetMinutes -gt 0 -and $realWpm -gt 0) {
            $finalDuration = Get-SystemV7DurationState -Narration $finalNarration -TargetMinutes $targetMinutes -RealWpm $realWpm -Mode $durationMode
            if ($durationMode -ceq 'HARD_MAX' -and -not $finalDuration.Pass) { Add-NV2Error "K5_DURATION_HARD_MAX_EXCEEDED: words=$finalWords max=$($finalDuration.MaximumWords)" }
            elseif ($durationMode -ceq 'GUIDE' -and $finalDuration.Alert) { Add-NV2Warning "K5_DURATION_GUIDE_ALERT: estimated=$($finalDuration.EstimatedMinutes) target=$targetMinutes" }
        }
        $draftNarrationForDiff = [string]$script:NV2CleanNarration
        $finalNarrationForDiff = [string]$finalNarration
        $draftNarrationBytes=[Text.UTF8Encoding]::new($false).GetBytes($draftNarrationForDiff);$finalNarrationBytes=[Text.UTF8Encoding]::new($false).GetBytes($finalNarrationForDiff)
        $actualChangeClass = if ([Convert]::ToBase64String($finalNarrationBytes) -ceq [Convert]::ToBase64String($draftNarrationBytes)) { 'BYTE_IDENTICAL' } else { Add-NV2Error 'K5_ANY_TEXT_CHANGE_REQUIRES_REOPEN_K3';'SEMANTIC_REVIEW_REQUIRED' }

        $k5Directory = Join-Path $project '_work\K5'
        if (Test-Path -LiteralPath $k5Directory -PathType Container) {
            foreach ($candidate in @(Get-ChildItem -LiteralPath $k5Directory -Filter '*.json' -File -Force)) {
                try {
                    $candidateData = Get-Content -LiteralPath $candidate.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String -Depth 32
                    if ([string]$candidateData.schema -ceq 'SYSTEM_V7_K5_APPROVAL_RECEIPT_V1') { Add-NV2Error "K5_MIXED_LEGACY_APPROVAL_RECEIPT: $($candidate.FullName)" }
                } catch { Add-NV2Error "K5_APPROVAL_DIRECTORY_INVALID_JSON: $($candidate.FullName)" }
            }
        }
        try {
            $approval = Get-SystemV7K5ApprovalV2State -ProjectPath $project
            if (-not $approval.Valid) {
                foreach ($problem in @($approval.Errors)) { Add-NV2Error "K5_V2_APPROVAL_INVALID: $problem" }
            } elseif ($approval.Data) {
                Test-NV2CanonicalJsonFile -Path ([string]$approval.Path) -Data $approval.Data -Code 'K5_V2_APPROVAL'
                $expectedApprovalPath = Join-Path $project "_work\K5\v2-approval-$finalSha.json"
                if (-not ([string]$approval.Path).Equals($expectedApprovalPath, [StringComparison]::OrdinalIgnoreCase)) { Add-NV2Error 'K5_V2_APPROVAL_PATH_MISMATCH' }
                if ([string]$approval.Data.attestation_scope -cne 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY' -or [string]$approval.Data.project_origin_sha256 -cne $script:NV2OriginSha256) { Add-NV2Error 'K5_V2_APPROVAL_IDENTITY_INVALID' }
                if ([string]$approval.Data.final_sha256 -cne $finalSha -or [string]$approval.Data.draft_sha256 -cne $script:NV2DraftSha256 -or
                    [string]$approval.Data.k4_proof_set_sha256 -cne $script:NV2K4ProofSetSha256 -or [string]$approval.Data.continuity_chain_sha256 -cne $script:NV2ContinuityChainSha256) { Add-NV2Error 'K5_V2_APPROVAL_PROOF_BINDING_STALE' }
                if ([string]$approval.Data.duration_mode -cne $durationMode -or [int]$approval.Data.final_word_count -ne $finalWords -or [int]$approval.Data.maximum_words -ne ($targetMinutes * $realWpm) -or [string]$approval.Data.duration_verdict -cne 'PASS') { Add-NV2Error 'K5_V2_APPROVAL_DURATION_BINDING_INVALID' }
                if ([string]$approval.Data.change_class -cne $actualChangeClass) { Add-NV2Error "K5_V2_APPROVAL_CHANGE_CLASS_MISMATCH: declared=$($approval.Data.change_class) actual=$actualChangeClass" }
                if (-not (Test-NV2Concrete $approval.Data.approval_note 12)) { Add-NV2Error 'K5_V2_APPROVAL_NOTE_NOT_CONCRETE' }
                $approvalCreated = [DateTimeOffset]::MinValue
                if (-not [DateTimeOffset]::TryParse([string]$approval.Data.created_at_utc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$approvalCreated) -or $approvalCreated.UtcDateTime -gt [DateTime]::UtcNow.AddMinutes(5)) { Add-NV2Error 'K5_V2_APPROVAL_CREATED_AT_INVALID' }
            }
        } catch { Add-NV2Error "K5_V2_APPROVAL_CHECK_FAILED: $($_.Exception.Message)" }
    }
}

$result = [pscustomobject]@{
    ProjectPath = $project
    Stage = $stage
    Errors = $errors.Count
    Warnings = $warnings.Count
    ErrorDetails = @($errors)
    WarningDetails = @($warnings)
    Verdict = if ($errors.Count -eq 0) { 'PASS' } else { 'FAIL' }
}

$result
if ($errors.Count -gt 0 -and -not $NoExit) { exit 1 }
