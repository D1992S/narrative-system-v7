$script:SystemV7CurrentWorkflowRevision = '2026-08-31_NARRATIVE_V2'
$script:SystemV7PreviousProjectWorkflowRevision = '2026-08-30_K1_LITE_V2'
$script:SystemV7CurrentEvidenceSchema = 'MINIMAL_EVIDENCE_V4_PAGELOC'
$script:SystemV7CurrentArchitectureSchema = 'STORY_ENGINE_V2'
$script:SystemV7CurrentK3PacketSchema = 'K3_PACKET_V2'
$script:SystemV7CurrentContinuitySchema = 'CONTINUITY_ATTEST_V1'
$script:SystemV7CurrentK4Schema = 'THREE_LENS_QA_V1'
$script:SystemV7ProjectOriginWorkflowSchemaMap = [ordered]@{
    '2026-08-31_NARRATIVE_V2' = 'MINIMAL_EVIDENCE_V4_PAGELOC'
    '2026-08-30_K1_LITE_V2' = 'MINIMAL_EVIDENCE_V4_PAGELOC'
}
$script:SystemV7ProjectOriginSchema = 'SYSTEM_V7_PROJECT_ORIGIN_V1'
$script:SystemV7ProjectOriginRelative = '.system-v7/project-origin.json'
$script:SystemV7LegacyOriginSchema = 'SYSTEM_V7_LEGACY_ORIGIN_V1'
$script:SystemV7LegacyOriginRelative = '.system-v7/legacy-origin.json'
$script:SystemV7LegacyWorkflowSchemaMap = [ordered]@{
    '2026-08-22_MINIMAL_EVIDENCE' = 'MINIMAL_EVIDENCE_V3'
    '2026-08-19_SELECTION_FIRST_K1' = 'COMPACT_EVIDENCE_V2'
    '2026-08-17_CHATGPT_NARRATION_ONLY' = 'COMPACT_EVIDENCE_V1'
    '2026-08-17_CHATGPT_COMPACT_K1' = 'COMPACT_EVIDENCE_V1'
}

function Test-SystemV7ExactMapKey {
    param([Parameter(Mandatory)][Collections.IDictionary]$Map,[AllowNull()][object]$Key)
    return [array]::IndexOf([string[]]@($Map.Keys),[string]$Key) -ge 0
}

function Get-SystemV7TextSha256 {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        return ([Convert]::ToHexString($sha.ComputeHash($bytes)))
    } finally { $sha.Dispose() }
}

function Get-SystemV7SingleMetaField {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Name
    )
    $matches = @([regex]::Matches($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
    if ($matches.Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $Name=$($matches.Count)" }
    $value = $matches[0].Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { throw "META_FIELD_EMPTY: $Name" }
    return $value
}

function Assert-SystemV7PathNoReparse {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ContainmentRoot
    )
    $target = [IO.Path]::GetFullPath($Path)
    $root = if ([string]::IsNullOrWhiteSpace($ContainmentRoot)) {
        [IO.Path]::GetFullPath([IO.Path]::GetPathRoot($target))
    } else {
        [IO.Path]::GetFullPath($ContainmentRoot)
    }
    $rootPrefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $target.Equals($root, [StringComparison]::OrdinalIgnoreCase) -and
        -not $target.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "PATH_OUTSIDE_CONTAINMENT_ROOT: $target"
    }
    $current = $target
    while ($true) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "REPARSE_POINT_BLOCKED: $current"
        }
        if ($current.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent)) { throw "PATH_PARENT_CHAIN_INVALID: $current" }
        $parent = [IO.Path]::GetFullPath($parent)
        if ($parent.Equals($current, [StringComparison]::OrdinalIgnoreCase)) { throw "PATH_PARENT_CHAIN_LOOP: $current" }
        $current = $parent
    }
    return $target
}

function Assert-SystemV7TreeNoReparse {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$ContainmentRoot
    )
    $tree = Assert-SystemV7PathNoReparse -Path $RootPath -ContainmentRoot $ContainmentRoot
    if (-not (Test-Path -LiteralPath $tree -PathType Container)) { return $tree }
    foreach ($entry in @(Get-ChildItem -LiteralPath $tree -Force -Recurse -ErrorAction Stop)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "REPARSE_POINT_BLOCKED: $($entry.FullName)"
        }
    }
    return $tree
}

function Write-SystemV7JsonCreateNewAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Value
    )
    $target = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "ORIGIN_DIRECTORY_MISSING: $directory" }
    if (Test-Path -LiteralPath $target) { throw "ORIGIN_ALREADY_EXISTS: $target" }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes((($Value | ConvertTo-Json -Depth 4) + "`n"))
    $temp = Join-Path $directory ('.origin-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $stream = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    try { [IO.File]::Move($temp, $target) }
    finally { if (Test-Path -LiteralPath $temp -PathType Leaf) { [IO.File]::Delete($temp) } }
}

function Get-SystemV7OriginBindingText {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$CreatedAtUtc,
        [string]$WorkflowRevision = $script:SystemV7CurrentWorkflowRevision,
        [string]$EvidenceSchema = $script:SystemV7CurrentEvidenceSchema
    )
    $canonicalPath = [IO.Path]::GetFullPath($ProjectPath)
    return "SCHEMA=$script:SystemV7ProjectOriginSchema`nPROJECT_ID=$ProjectId`nPROJECT_NAME=$ProjectName`nPROJECT_PATH=$canonicalPath`nCREATED_AT_UTC=$CreatedAtUtc`nSYSTEM_VERSION=7.0`nWORKFLOW_REVISION=$WorkflowRevision`nEVIDENCE_SCHEMA=$EvidenceSchema`n"
}

function Get-SystemV7LegacyOriginBindingText {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$RegisteredAtUtc,
        [Parameter(Mandatory)][string]$WorkflowRevision,
        [Parameter(Mandatory)][string]$EvidenceSchema,
        [Parameter(Mandatory)][string]$Reason
    )
    $canonicalPath = [IO.Path]::GetFullPath($ProjectPath)
    return "SCHEMA=$script:SystemV7LegacyOriginSchema`nPROJECT_ID=$ProjectId`nPROJECT_NAME=$ProjectName`nPROJECT_PATH=$canonicalPath`nREGISTERED_AT_UTC=$RegisteredAtUtc`nSYSTEM_VERSION=7.0`nWORKFLOW_REVISION=$WorkflowRevision`nEVIDENCE_SCHEMA=$EvidenceSchema`nREASON=$Reason`nACTOR=DAWID`nATTESTATION_SCOPE=AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY`n"
}

function New-SystemV7ProjectOrigin {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ProjectName,
        [string]$BindingProjectPath,
        [string]$WorkflowRevision = $script:SystemV7CurrentWorkflowRevision,
        [string]$EvidenceSchema = $script:SystemV7CurrentEvidenceSchema
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $boundProject = if ([string]::IsNullOrWhiteSpace($BindingProjectPath)) { $project } else { [IO.Path]::GetFullPath($BindingProjectPath) }
    Assert-SystemV7PathNoReparse -Path $project | Out-Null
    if (-not (Test-Path -LiteralPath $project -PathType Container)) { throw "PROJECT_DIRECTORY_MISSING: $project" }
    $directory = Join-Path $project '.system-v7'
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    Assert-SystemV7PathNoReparse -Path $directory -ContainmentRoot $project | Out-Null
    $path = Join-Path $directory 'project-origin.json'
    if (Test-Path -LiteralPath $path) { throw "PROJECT_ORIGIN_ALREADY_EXISTS: $path" }
    if (-not (Test-SystemV7ExactMapKey -Map $script:SystemV7ProjectOriginWorkflowSchemaMap -Key $WorkflowRevision) -or
        [string]$script:SystemV7ProjectOriginWorkflowSchemaMap[$WorkflowRevision] -cne $EvidenceSchema) {
        throw "PROJECT_ORIGIN_CREATE_CONTRACT_INVALID: WORKFLOW_REVISION=$WorkflowRevision; EVIDENCE_SCHEMA=$EvidenceSchema"
    }

    $projectId = [guid]::NewGuid().ToString('D')
    $createdAt = [DateTime]::UtcNow.ToString('o')
    $bindingText = Get-SystemV7OriginBindingText -ProjectId $projectId -ProjectName $ProjectName -ProjectPath $boundProject -CreatedAtUtc $createdAt -WorkflowRevision $WorkflowRevision -EvidenceSchema $EvidenceSchema
    $record = [ordered]@{
        schema = $script:SystemV7ProjectOriginSchema
        project_id = $projectId
        project_name = $ProjectName
        project_path = $boundProject
        created_at_utc = $createdAt
        system_version = '7.0'
        origin_workflow_revision = $WorkflowRevision
        origin_evidence_schema = $EvidenceSchema
        binding_sha256 = Get-SystemV7TextSha256 -Text $bindingText
    }
    Write-SystemV7JsonCreateNewAtomic -Path $path -Value $record
    return [pscustomobject]@{
        Path = $path
        Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        ProjectId = $projectId
    }
}

function Get-SystemV7ProjectOriginState {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $path = Join-Path $project '.system-v7\project-origin.json'
    $problems = [Collections.Generic.List[string]]::new()
    try {
        Assert-SystemV7PathNoReparse -Path $project | Out-Null
        Assert-SystemV7PathNoReparse -Path $path -ContainmentRoot $project | Out-Null
    } catch { $problems.Add($_.Exception.Message) }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $problems.Add('PROJECT_ORIGIN_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Path=$path; Sha256=$null; ProjectId=$null; Data=$null }
    }
    $originDirectory = Get-Item -LiteralPath (Split-Path -Parent $path) -Force
    if (($originDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $problems.Add('PROJECT_ORIGIN_DIRECTORY_REPARSE_POINT') }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $problems.Add('PROJECT_ORIGIN_REPARSE_POINT') }
    $data = $null
    try { $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String }
    catch { $problems.Add("PROJECT_ORIGIN_INVALID_JSON: $($_.Exception.Message)") }
    if ($null -ne $data) {
        $expectedProperties = @('schema','project_id','project_name','project_path','created_at_utc','system_version','origin_workflow_revision','origin_evidence_schema','binding_sha256')
        $actualProperties = @($data.PSObject.Properties.Name)
        if ($actualProperties.Count -ne $expectedProperties.Count -or
            @(Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties).Count -gt 0) {
            $problems.Add('PROJECT_ORIGIN_FIELDS_INVALID')
        }
        $projectId = [string]$data.project_id
        $projectName = [string]$data.project_name
        $projectPathValue = [string]$data.project_path
        $createdAtRaw = $data.created_at_utc
        $createdAtCanonical = if ($createdAtRaw -is [DateTime]) { $createdAtRaw.ToUniversalTime().ToString('o') } else { [string]$createdAtRaw }
        if ($projectId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { $problems.Add('PROJECT_ORIGIN_ID_INVALID') }
        if ([string]::IsNullOrWhiteSpace($projectName)) { $problems.Add('PROJECT_ORIGIN_NAME_INVALID') }
        $createdAtValue = [DateTimeOffset]::MinValue
        $createdAtValid = [DateTimeOffset]::TryParse(
            $createdAtCanonical,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$createdAtValue
        )
        if (-not $createdAtValid -or $createdAtValue.UtcDateTime -gt [DateTime]::UtcNow.AddMinutes(5)) { $problems.Add('PROJECT_ORIGIN_CREATED_AT_INVALID') }
        $resolvedDeclaredPath = $null
        try {
            if (-not [IO.Path]::IsPathRooted($projectPathValue)) { throw 'not rooted' }
            $resolvedDeclaredPath = [IO.Path]::GetFullPath($projectPathValue)
        }
        catch { $problems.Add('PROJECT_ORIGIN_PATH_INVALID') }
        if ($resolvedDeclaredPath -and -not $resolvedDeclaredPath.Equals($project, [StringComparison]::OrdinalIgnoreCase)) { $problems.Add('PROJECT_ORIGIN_PATH_MISMATCH') }
        $originWorkflow = [string]$data.origin_workflow_revision
        $originEvidence = [string]$data.origin_evidence_schema
        if ([string]$data.schema -cne $script:SystemV7ProjectOriginSchema -or [string]$data.system_version -cne '7.0' -or
            -not (Test-SystemV7ExactMapKey -Map $script:SystemV7ProjectOriginWorkflowSchemaMap -Key $originWorkflow) -or
            [string]$script:SystemV7ProjectOriginWorkflowSchemaMap[$originWorkflow] -cne $originEvidence) {
            $problems.Add('PROJECT_ORIGIN_CONTRACT_INVALID')
        }
        if ($resolvedDeclaredPath -and $projectId -and $projectName -and $createdAtCanonical) {
            $expectedBinding = Get-SystemV7TextSha256 -Text (Get-SystemV7OriginBindingText -ProjectId $projectId -ProjectName $projectName -ProjectPath $resolvedDeclaredPath -CreatedAtUtc $createdAtCanonical -WorkflowRevision $originWorkflow -EvidenceSchema $originEvidence)
            if ([string]$data.binding_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$data.binding_sha256 -ne $expectedBinding) { $problems.Add('PROJECT_ORIGIN_BINDING_MISMATCH') }
        } else { $problems.Add('PROJECT_ORIGIN_BINDING_INPUT_INVALID') }
    }
    [pscustomobject]@{
        Valid = $problems.Count -eq 0
        Errors = @($problems)
        Path = $path
        Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        ProjectId = if ($data) { [string]$data.project_id } else { $null }
        Data = $data
    }
}

function New-SystemV7LegacyOrigin {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$WorkflowRevision,
        [Parameter(Mandatory)][string]$EvidenceSchema,
        [Parameter(Mandatory)][string]$Reason
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    Assert-SystemV7PathNoReparse -Path $project | Out-Null
    if (-not (Test-Path -LiteralPath $project -PathType Container)) { throw "PROJECT_DIRECTORY_MISSING: $project" }
    if (-not (Test-SystemV7ExactMapKey -Map $script:SystemV7LegacyWorkflowSchemaMap -Key $WorkflowRevision) -or
        [string]$script:SystemV7LegacyWorkflowSchemaMap[$WorkflowRevision] -cne $EvidenceSchema) {
        throw "LEGACY_WORKFLOW_SCHEMA_PAIR_UNSUPPORTED: $WorkflowRevision + $EvidenceSchema"
    }
    if ($Reason.Trim() -match '[\x00-\x1F\x7F]' -or $Reason.Trim().Length -lt 15 -or
        $Reason.Trim().Split(' ', [StringSplitOptions]::RemoveEmptyEntries).Count -lt 3) {
        throw 'LEGACY_REGISTRATION_REASON_NOT_CONCRETE'
    }
    $currentPath = Join-Path $project $script:SystemV7ProjectOriginRelative
    if (Test-Path -LiteralPath $currentPath) { throw "CURRENT_PROJECT_ORIGIN_ALREADY_EXISTS: $currentPath" }
    $directory = Join-Path $project '.system-v7'
    if (Test-Path -LiteralPath $directory) {
        $directoryItem = Get-Item -LiteralPath $directory -Force
        if (($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'LEGACY_ORIGIN_DIRECTORY_REPARSE_POINT' }
    } else {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    Assert-SystemV7PathNoReparse -Path $directory -ContainmentRoot $project | Out-Null
    $path = Join-Path $directory 'legacy-origin.json'
    if (Test-Path -LiteralPath $path) { throw "LEGACY_PROJECT_ORIGIN_ALREADY_EXISTS: $path" }

    $projectId = [guid]::NewGuid().ToString('D')
    $registeredAt = [DateTime]::UtcNow.ToString('o')
    $cleanReason = $Reason.Trim()
    $bindingText = Get-SystemV7LegacyOriginBindingText -ProjectId $projectId -ProjectName $ProjectName -ProjectPath $project `
        -RegisteredAtUtc $registeredAt -WorkflowRevision $WorkflowRevision -EvidenceSchema $EvidenceSchema -Reason $cleanReason
    $record = [ordered]@{
        schema = $script:SystemV7LegacyOriginSchema
        project_id = $projectId
        project_name = $ProjectName
        project_path = $project
        registered_at_utc = $registeredAt
        system_version = '7.0'
        workflow_revision = $WorkflowRevision
        evidence_schema = $EvidenceSchema
        reason = $cleanReason
        actor = 'DAWID'
        attestation_scope = 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'
        binding_sha256 = Get-SystemV7TextSha256 -Text $bindingText
    }
    Write-SystemV7JsonCreateNewAtomic -Path $path -Value $record
    return [pscustomobject]@{ Path=$path; Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash; ProjectId=$projectId }
}

function Get-SystemV7LegacyOriginState {
    param([Parameter(Mandatory)][string]$ProjectPath)
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $path = Join-Path $project $script:SystemV7LegacyOriginRelative
    $problems = [Collections.Generic.List[string]]::new()
    try {
        Assert-SystemV7PathNoReparse -Path $project | Out-Null
        Assert-SystemV7PathNoReparse -Path $path -ContainmentRoot $project | Out-Null
    } catch { $problems.Add($_.Exception.Message) }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $problems.Add('LEGACY_PROJECT_ORIGIN_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Path=$path; Sha256=$null; ProjectId=$null; Data=$null }
    }
    if (Test-Path -LiteralPath (Join-Path $project $script:SystemV7ProjectOriginRelative)) { $problems.Add('CURRENT_AND_LEGACY_ORIGIN_MUTUALLY_EXCLUSIVE') }
    $directoryItem = Get-Item -LiteralPath (Split-Path -Parent $path) -Force
    if (($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $problems.Add('LEGACY_ORIGIN_DIRECTORY_REPARSE_POINT') }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $problems.Add('LEGACY_ORIGIN_REPARSE_POINT') }
    $data = $null
    try { $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String }
    catch { $problems.Add("LEGACY_ORIGIN_INVALID_JSON: $($_.Exception.Message)") }
    if ($data) {
        $expectedProperties = @('schema','project_id','project_name','project_path','registered_at_utc','system_version','workflow_revision','evidence_schema','reason','actor','attestation_scope','binding_sha256')
        $actualProperties = @($data.PSObject.Properties.Name)
        if ($actualProperties.Count -ne $expectedProperties.Count -or
            @(Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties).Count -gt 0) {
            $problems.Add('LEGACY_ORIGIN_FIELDS_INVALID')
        }
        $projectId = [string]$data.project_id
        $projectName = [string]$data.project_name
        $declaredPath = [string]$data.project_path
        $workflow = [string]$data.workflow_revision
        $schema = [string]$data.evidence_schema
        $reason = [string]$data.reason
        $registeredRaw = $data.registered_at_utc
        $registeredCanonical = if ($registeredRaw -is [DateTime]) { $registeredRaw.ToUniversalTime().ToString('o') } else { [string]$registeredRaw }
        if ([string]$data.schema -cne $script:SystemV7LegacyOriginSchema -or [string]$data.system_version -cne '7.0' -or
            [string]$data.actor -cne 'DAWID' -or [string]$data.attestation_scope -cne 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY') {
            $problems.Add('LEGACY_ORIGIN_CONTRACT_INVALID')
        }
        if ($projectId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { $problems.Add('LEGACY_ORIGIN_ID_INVALID') }
        if ([string]::IsNullOrWhiteSpace($projectName)) { $problems.Add('LEGACY_ORIGIN_NAME_INVALID') }
        if ($reason.Trim().Length -lt 15 -or $reason.Trim().Split(' ', [StringSplitOptions]::RemoveEmptyEntries).Count -lt 3) { $problems.Add('LEGACY_ORIGIN_REASON_INVALID') }
        if (-not (Test-SystemV7ExactMapKey -Map $script:SystemV7LegacyWorkflowSchemaMap -Key $workflow) -or [string]$script:SystemV7LegacyWorkflowSchemaMap[$workflow] -cne $schema) {
            $problems.Add('LEGACY_ORIGIN_WORKFLOW_SCHEMA_PAIR_INVALID')
        }
        $registeredValue = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse($registeredCanonical, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$registeredValue) -or
            $registeredValue.UtcDateTime -gt [DateTime]::UtcNow.AddMinutes(5)) { $problems.Add('LEGACY_ORIGIN_REGISTERED_AT_INVALID') }
        $resolvedDeclared = $null
        try {
            if (-not [IO.Path]::IsPathRooted($declaredPath)) { throw 'not rooted' }
            $resolvedDeclared = [IO.Path]::GetFullPath($declaredPath)
        } catch { $problems.Add('LEGACY_ORIGIN_PATH_INVALID') }
        if ($resolvedDeclared -and -not $resolvedDeclared.Equals($project, [StringComparison]::OrdinalIgnoreCase)) { $problems.Add('LEGACY_ORIGIN_PATH_MISMATCH') }
        if ($resolvedDeclared -and $projectId -and $projectName -and $registeredCanonical -and $workflow -and $schema -and $reason) {
            $expectedBinding = Get-SystemV7TextSha256 -Text (Get-SystemV7LegacyOriginBindingText -ProjectId $projectId -ProjectName $projectName `
                -ProjectPath $resolvedDeclared -RegisteredAtUtc $registeredCanonical -WorkflowRevision $workflow -EvidenceSchema $schema -Reason $reason)
            if ([string]$data.binding_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$data.binding_sha256 -ne $expectedBinding) {
                $problems.Add('LEGACY_ORIGIN_BINDING_MISMATCH')
            }
        } else { $problems.Add('LEGACY_ORIGIN_BINDING_INPUT_INVALID') }
    }
    [pscustomobject]@{
        Valid=$problems.Count -eq 0
        Errors=@($problems)
        Path=$path
        Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        ProjectId=if($data){[string]$data.project_id}else{$null}
        Data=$data
    }
}

function Test-SystemV7CurrentMarkers {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$MetaText
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    if ($MetaText -match '(?m)^WORKFLOW_REVISION:\s*2026-08-(?:30_K1_LITE_V2|31_NARRATIVE_V2)\s*$' -or
        $MetaText -match '(?m)^EVIDENCE_SCHEMA:\s*MINIMAL_EVIDENCE_V4_PAGELOC\s*$' -or
        $MetaText -match '(?m)^K1_ENGINE_VERSION:\s*2\.1\.0\s*$' -or
        $MetaText -match '(?m)^K1_PUBLISH_RECEIPT_(?:PATH|SHA256):' -or
        $MetaText -match '(?m)^W0_CONDITIONS:' -or
        (Test-Path -LiteralPath (Join-Path $project '.system-v7\project-origin.json')) -or
        (Test-Path -LiteralPath (Join-Path $project '_work\K1\k1-lite-v2') -PathType Container)) {
        return $true
    }
    return $false
}

function Assert-SystemV7CurrentProjectOrigin {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [string]$MetaText
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    Assert-SystemV7PathNoReparse -Path $project | Out-Null
    if ([string]::IsNullOrWhiteSpace($MetaText)) {
        $metaPath = Join-Path $project 'meta.md'
        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "PROJECT_META_MISSING: $metaPath" }
        $MetaText = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    }
    $metaItem = Get-Item -LiteralPath (Join-Path $project 'meta.md') -Force
    if (($metaItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'CURRENT_PROJECT_META_REPARSE_POINT' }
    $allFieldNames = @([regex]::Matches($MetaText, '(?m)^(?<name>[A-Z][A-Z0-9_/-]*):') | ForEach-Object { $_.Groups['name'].Value })
    $duplicateFields = @($allFieldNames | Group-Object | Where-Object Count -gt 1)
    if ($duplicateFields.Count -gt 0) { throw "CURRENT_PROJECT_META_DUPLICATE_FIELDS: $($duplicateFields.Name -join ', ')" }
    $workflow = Get-SystemV7SingleMetaField -Text $MetaText -Name 'WORKFLOW_REVISION'
    $schema = Get-SystemV7SingleMetaField -Text $MetaText -Name 'EVIDENCE_SCHEMA'
    $name = Get-SystemV7SingleMetaField -Text $MetaText -Name 'PROJECT_NAME'
    $declaredPath = Get-SystemV7SingleMetaField -Text $MetaText -Name 'PROJECT_PATH'
    if (-not (Test-SystemV7ExactMapKey -Map $script:SystemV7ProjectOriginWorkflowSchemaMap -Key $workflow) -or
        [string]$script:SystemV7ProjectOriginWorkflowSchemaMap[$workflow] -cne $schema) {
        throw "PROJECT_ORIGIN_META_CONTRACT_INVALID: WORKFLOW_REVISION=$workflow; EVIDENCE_SCHEMA=$schema"
    }
    if ([string]::IsNullOrWhiteSpace($name)) { throw 'CURRENT_PROJECT_NAME_MISSING' }
    try { $resolvedDeclared = [IO.Path]::GetFullPath($declaredPath) }
    catch { throw 'CURRENT_PROJECT_PATH_INVALID' }
    if (-not $resolvedDeclared.Equals($project, [StringComparison]::OrdinalIgnoreCase)) { throw 'CURRENT_PROJECT_PATH_MISMATCH' }
    $state = Get-SystemV7ProjectOriginState -ProjectPath $project
    if (-not $state.Valid) { throw "CURRENT_PROJECT_ORIGIN_INVALID: $($state.Errors -join '; ')" }
    if ([string]$state.Data.project_name -cne $name) { throw 'CURRENT_PROJECT_ORIGIN_NAME_MISMATCH' }
    if ([string]$state.Data.origin_workflow_revision -cne $workflow -or
        [string]$state.Data.origin_evidence_schema -cne $schema) {
        throw 'PROJECT_ORIGIN_META_MISMATCH'
    }
    return $state
}

function Assert-SystemV7MutableProjectOrigin {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$MetaText
    )
    $workflow = $null
    try { $workflow = Get-SystemV7SingleMetaField -Text $MetaText -Name 'WORKFLOW_REVISION' }
    catch { throw }
    if ($workflow -ceq '2026-08-31_NARRATIVE_V2') {
        if ($null -eq (Get-Command Assert-SystemV7NarrativeInstructionContract -ErrorAction SilentlyContinue)) {
            $narrativeLibrary = Join-Path $PSScriptRoot 'Narrative-V2.ps1'
            if (-not (Test-Path -LiteralPath $narrativeLibrary -PathType Leaf)) { throw 'NARRATIVE_INSTRUCTION_GUARD_LIBRARY_MISSING' }
            . $narrativeLibrary
        }
        Assert-SystemV7NarrativeInstructionContract -SystemRoot (Split-Path -Parent $PSScriptRoot) | Out-Null
    }
    if ([array]::IndexOf(@($script:SystemV7CurrentWorkflowRevision, $script:SystemV7PreviousProjectWorkflowRevision),$workflow) -lt 0) {
        throw 'LEGACY_PROJECT_IS_VALIDATION_ONLY'
    }
    return Assert-SystemV7CurrentProjectOrigin -ProjectPath $ProjectPath -MetaText $MetaText
}

function Assert-SystemV7LegacyProjectOrigin {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [string]$MetaText
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    Assert-SystemV7PathNoReparse -Path $project | Out-Null
    $metaPath = Join-Path $project 'meta.md'
    if ([string]::IsNullOrWhiteSpace($MetaText)) {
        if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "PROJECT_META_MISSING: $metaPath" }
        $MetaText = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    }
    $metaItem = Get-Item -LiteralPath $metaPath -Force
    if (($metaItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'LEGACY_PROJECT_META_REPARSE_POINT' }
    $allFieldNames = @([regex]::Matches($MetaText, '(?m)^(?<name>[A-Z][A-Z0-9_/-]*):') | ForEach-Object { $_.Groups['name'].Value })
    $duplicateFields = @($allFieldNames | Group-Object | Where-Object Count -gt 1)
    if ($duplicateFields.Count -gt 0) { throw "LEGACY_PROJECT_META_DUPLICATE_FIELDS: $($duplicateFields.Name -join ', ')" }
    $workflow = Get-SystemV7SingleMetaField -Text $MetaText -Name 'WORKFLOW_REVISION'
    $schema = Get-SystemV7SingleMetaField -Text $MetaText -Name 'EVIDENCE_SCHEMA'
    $name = Get-SystemV7SingleMetaField -Text $MetaText -Name 'PROJECT_NAME'
    $declaredPath = Get-SystemV7SingleMetaField -Text $MetaText -Name 'PROJECT_PATH'
    if (-not (Test-SystemV7ExactMapKey -Map $script:SystemV7LegacyWorkflowSchemaMap -Key $workflow) -or
        [string]$script:SystemV7LegacyWorkflowSchemaMap[$workflow] -cne $schema) {
        throw "LEGACY_PROJECT_META_CONTRACT_INVALID: WORKFLOW_REVISION=$workflow; EVIDENCE_SCHEMA=$schema"
    }
    try { $resolvedDeclared = [IO.Path]::GetFullPath($declaredPath) }
    catch { throw 'LEGACY_PROJECT_PATH_INVALID' }
    if (-not $resolvedDeclared.Equals($project, [StringComparison]::OrdinalIgnoreCase)) { throw 'LEGACY_PROJECT_PATH_MISMATCH' }
    if (Test-SystemV7CurrentMarkers -ProjectPath $project -MetaText $MetaText) { throw 'LEGACY_PROJECT_HAS_CURRENT_MARKERS' }
    $state = Get-SystemV7LegacyOriginState -ProjectPath $project
    if (-not $state.Valid) { throw "LEGACY_PROJECT_ORIGIN_INVALID: $($state.Errors -join '; ')" }
    if ([string]$state.Data.project_name -cne $name) { throw 'LEGACY_PROJECT_ORIGIN_NAME_MISMATCH' }
    if ([string]$state.Data.workflow_revision -cne $workflow -or [string]$state.Data.evidence_schema -cne $schema) {
        throw 'LEGACY_PROJECT_ORIGIN_CONTRACT_MISMATCH'
    }
    return $state
}
