$script:K1PublishScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:K1PublishScriptRoot 'Project-Origin.ps1')

$script:K1PublishReceiptSchema = 'K1_LITE_V2_PUBLISH_RECEIPT_V1'
$script:K1PublishWorkflowRevisions = @(
    '2026-08-31_NARRATIVE_V2',
    '2026-08-30_K1_LITE_V2'
)
$script:K1PublishGateNames = @(
    'coverage_ready',
    'quotes_ready',
    'decisions_current',
    'selected_visual_ready',
    'selected_conflicts_acknowledged',
    'editorial_review_ready'
)

function Get-K1PublishProjectWorkflowRevision {
    param([Parameter(Mandatory)][string]$ProjectPath)
    $metaPath = Join-Path ([IO.Path]::GetFullPath($ProjectPath)) 'meta.md'
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "K1_PUBLISH_META_MISSING: $metaPath" }
    $metaText = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $matches = @([regex]::Matches($metaText, '(?m)^WORKFLOW_REVISION:\s*(.*?)\s*$'))
    if ($matches.Count -ne 1) { throw "K1_PUBLISH_WORKFLOW_REVISION_COUNT_INVALID: $($matches.Count)" }
    $workflowRevision = $matches[0].Groups[1].Value.Trim()
    if ($script:K1PublishWorkflowRevisions -cnotcontains $workflowRevision) {
        throw "K1_PUBLISH_WORKFLOW_REVISION_UNSUPPORTED: $workflowRevision"
    }
    return $workflowRevision
}

function Get-K1PublishSha256 {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "K1_PUBLISH_FILE_MISSING: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-K1PublishBytesSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-K1PublishLedgerHistoryState {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )
    if ($ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'K1_LEDGER_HISTORY_SHA_INVALID' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "K1_PUBLISH_FILE_MISSING: $Path" }
    $expected = $ExpectedSha256.ToUpperInvariant()
    $bytes = [IO.File]::ReadAllBytes($Path)
    $actual = Get-K1PublishBytesSha256 $bytes
    if ($actual -eq $expected) {
        return [pscustomobject][ordered]@{
            ActualSha256 = $actual
            HistoricalSha256 = $expected
            HistoricalLength = [long]$bytes.LongLength
            IsExact = $true
        }
    }

    # Ledgery są JSONL i są rozszerzane wyłącznie całymi rekordami. Hash
    # historyczny może więc odpowiadać tylko prefiksowi kończącemu się LF.
    # IncrementalHash pozwala sprawdzać granice bez kwadratowego ponownego
    # hashowania coraz dłuższych prefiksów.
    $incremental = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $segmentStart = 0
        for ($index = 0; $index -lt $bytes.Length; $index++) {
            if ($bytes[$index] -ne 10) { continue }
            $segmentLength = $index - $segmentStart + 1
            $incremental.AppendData($bytes, $segmentStart, $segmentLength)
            $segmentStart = $index + 1
            $prefixSha = ([BitConverter]::ToString($incremental.GetCurrentHash())).Replace('-','')
            if ($prefixSha -eq $expected) {
                return [pscustomobject][ordered]@{
                    ActualSha256 = $actual
                    HistoricalSha256 = $expected
                    HistoricalLength = [long]($index + 1)
                    IsExact = $false
                }
            }
        }
    } finally {
        $incremental.Dispose()
    }
    return $null
}

function Get-K1PublishRelativePath {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$Path
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $project.TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "K1_PUBLISH_PATH_OUTSIDE_PROJECT: $full"
    }
    return [IO.Path]::GetRelativePath($project, $full).Replace('\','/')
}

function Resolve-K1PublishRelativePath {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Code,
        [switch]$Directory
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains('\')) {
        throw "${Code}_RELATIVE_INVALID"
    }
    $full = [IO.Path]::GetFullPath((Join-Path $project $RelativePath))
    $canonical = Get-K1PublishRelativePath -ProjectPath $project -Path $full
    if ($canonical -cne $RelativePath) { throw "${Code}_RELATIVE_NONCANONICAL" }
    $expectedType = if ($Directory) { 'Container' } else { 'Leaf' }
    if (-not (Test-Path -LiteralPath $full -PathType $expectedType)) { throw "${Code}_MISSING: $full" }
    $cursor = Get-Item -LiteralPath $full -Force
    while ($cursor -and $cursor.FullName.StartsWith($project, [StringComparison]::OrdinalIgnoreCase)) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "${Code}_REPARSE_POINT_BLOCKED: $($cursor.FullName)" }
        if ($cursor.FullName.Equals($project, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = $cursor.Parent
    }
    return $full
}

function Assert-K1StringArraysEqual {
    param([object[]]$Expected, [object[]]$Actual, [Parameter(Mandatory)][string]$Code)
    if ($Expected.Count -ne $Actual.Count) { throw $Code }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ([string]$Expected[$index] -cne [string]$Actual[$index]) { throw $Code }
    }
}

function Resolve-K1PublishLineage {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$PublicationRunDirectory,
        [Parameter(Mandatory)][object]$PublicationRunData,
        [Parameter(Mandatory)][string]$ExpectedPublicationLedgerSha256
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $publicationRun = [IO.Path]::GetFullPath($PublicationRunDirectory)
    $runRoot = [IO.Path]::GetFullPath((Join-Path $project '_work\K1\k1-lite-v2'))
    $runPrefix = $runRoot.TrimEnd('\') + '\'
    if (-not $publicationRun.StartsWith($runPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'K1_PUBLICATION_RUN_OUTSIDE_ROOT' }
    $publicationLedger = Join-Path $publicationRun 'ledger.jsonl'
    $publicationLedgerSha = Get-K1PublishSha256 $publicationLedger
    if ($ExpectedPublicationLedgerSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'K1_PUBLICATION_LEDGER_SHA_MISMATCH'
    }
    $expectedPublicationLedgerSha = $ExpectedPublicationLedgerSha256.ToUpperInvariant()
    if ($publicationLedgerSha -ne $expectedPublicationLedgerSha) {
        if ([string]$PublicationRunData.schema -ne 'K1_LITE_V2_RUN_V1' -or
            $null -eq (Get-K1PublishLedgerHistoryState -Path $publicationLedger -ExpectedSha256 $expectedPublicationLedgerSha)) {
            throw 'K1_PUBLICATION_LEDGER_SHA_MISMATCH'
        }
    }

    $sourceRunIds = @()
    $sourceRunRelatives = @()
    $sourceLedgerHashes = @()
    if ([string]$PublicationRunData.schema -eq 'K1_LITE_V2_RUN_V1') {
        $sourceRunIds = @([string]$PublicationRunData.run_id)
        $sourceRunRelatives = @(Get-K1PublishRelativePath -ProjectPath $project -Path $publicationRun)
        $sourceLedgerHashes = @($expectedPublicationLedgerSha)
    } elseif ([string]$PublicationRunData.run_type -in @('CORPUS_COMPILE','SUPPLEMENT_AGGREGATE')) {
        if ([string]$PublicationRunData.engine_version -ne '2.1.0' -or [string]$PublicationRunData.locator_policy -ne 'MIXED_V1' -or [string]$PublicationRunData.ledger_sha256 -ne $publicationLedgerSha) {
            throw 'K1_AGGREGATE_RUN_CONTRACT_INVALID'
        }
        $sourceRunIds = @($PublicationRunData.source_runs | ForEach-Object { [string]$_ })
        $sourceRunRelatives = @($PublicationRunData.source_run_relatives | ForEach-Object { [string]$_ })
        $sourceLedgerHashes = @($PublicationRunData.source_ledger_sha256s | ForEach-Object { ([string]$_).ToUpperInvariant() })
        if ($sourceRunIds.Count -lt 1 -or $sourceRunRelatives.Count -ne $sourceRunIds.Count -or $sourceLedgerHashes.Count -ne $sourceRunIds.Count) {
            throw 'K1_AGGREGATE_LINEAGE_COUNT_INVALID'
        }
        if (($sourceRunIds | Select-Object -Unique).Count -ne $sourceRunIds.Count) { throw 'K1_AGGREGATE_LINEAGE_RUN_ID_DUPLICATE' }
        if ([string]$PublicationRunData.run_type -eq 'SUPPLEMENT_AGGREGATE') {
            $supplementMode = if ([string]::IsNullOrWhiteSpace([string]$PublicationRunData.supplement_mode)) { 'ADD_RUN' } else { [string]$PublicationRunData.supplement_mode }
            $supplementSourceRun = [string]$PublicationRunData.supplement_source_run
            if ($supplementMode -notin @('ADD_RUN','APPEND_EXISTING') -or
                ($supplementMode -eq 'ADD_RUN' -and ($sourceRunIds.Count -lt 2 -or $supplementSourceRun -cne $sourceRunIds[-1])) -or
                ($supplementMode -eq 'APPEND_EXISTING' -and ($sourceRunIds.Count -lt 1 -or $supplementSourceRun -cnotin $sourceRunIds))) {
                throw 'K1_SUPPLEMENT_LINEAGE_ORDER_INVALID'
            }
        }
    } else {
        throw 'K1_PUBLICATION_RUN_TYPE_UNSUPPORTED'
    }

    $ledgerRunIds = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $publicationLedger -Encoding UTF8) {
        if (-not $line.Trim()) { continue }
        $event = $line | ConvertFrom-Json -DateKind String
        $eventRunId = [string]$event.run_id
        if ([string]::IsNullOrWhiteSpace($eventRunId)) { throw 'K1_PUBLICATION_LEDGER_RUN_ID_MISSING' }
        if (-not $ledgerRunIds.Contains($eventRunId)) { $ledgerRunIds.Add($eventRunId) }
    }
    Assert-K1StringArraysEqual -Expected $sourceRunIds -Actual $ledgerRunIds.ToArray() -Code 'K1_PUBLICATION_LEDGER_RUN_SET_MISMATCH'

    $lineage = [System.Collections.Generic.List[object]]::new()
    $seenPaths = @{}
    for ($index = 0; $index -lt $sourceRunIds.Count; $index++) {
        $runId = $sourceRunIds[$index]
        $relative = $sourceRunRelatives[$index]
        $declaredLedgerSha = $sourceLedgerHashes[$index]
        if ([string]::IsNullOrWhiteSpace($runId) -or $declaredLedgerSha -notmatch '^[A-F0-9]{64}$') { throw 'K1_SOURCE_LINEAGE_FIELDS_INVALID' }
        $sourceRun = Resolve-K1PublishRelativePath -ProjectPath $project -RelativePath $relative -Code 'K1_SOURCE_RUN' -Directory
        if (-not $sourceRun.StartsWith($runPrefix, [StringComparison]::OrdinalIgnoreCase) -or $seenPaths.ContainsKey($sourceRun.ToLowerInvariant())) {
            throw 'K1_SOURCE_LINEAGE_PATH_INVALID'
        }
        $seenPaths[$sourceRun.ToLowerInvariant()] = $true
        $sourceRunJson = Join-Path $sourceRun 'run.json'
        $sourceLedger = Join-Path $sourceRun 'ledger.jsonl'
        foreach ($required in @($sourceRunJson,$sourceLedger)) {
            if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "K1_SOURCE_LINEAGE_FILE_MISSING: $required" }
        }
        $sourceRunData = Get-Content -LiteralPath $sourceRunJson -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
        if ([string]$sourceRunData.schema -ne 'K1_LITE_V2_RUN_V1' -or [string]$sourceRunData.engine_version -ne '2.1.0' -or [string]$sourceRunData.run_id -cne $runId) {
            throw 'K1_SOURCE_LINEAGE_RUN_INVALID'
        }
        $ledgerHistory = Get-K1PublishLedgerHistoryState -Path $sourceLedger -ExpectedSha256 $declaredLedgerSha
        if ($null -eq $ledgerHistory) { throw 'K1_SOURCE_LINEAGE_LEDGER_SHA_MISMATCH' }
        $actualLedgerSha = [string]$ledgerHistory.ActualSha256
        $lineage.Add([pscustomobject][ordered]@{
            RunId = $runId
            RunRelative = $relative
            RunDirectory = $sourceRun
            RunJsonPath = $sourceRunJson
            RunJsonSha256 = Get-K1PublishSha256 $sourceRunJson
            LedgerPath = $sourceLedger
            LedgerSha256 = $actualLedgerSha
            DeclaredLedgerSha256 = $declaredLedgerSha
            HistoricalLedgerLength = [long]$ledgerHistory.HistoricalLength
            IsAppendOnlyExtension = -not [bool]$ledgerHistory.IsExact
        })
    }
    return @($lineage)
}

function Invoke-K1FreshLineageGates {
    param(
        [Parameter(Mandatory)][string]$EnginePath,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][object[]]$Lineage,
        [Parameter(Mandatory)][string]$PythonPath
    )
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Lineage) {
        if ((Get-K1PublishSha256 $entry.RunJsonPath) -ne [string]$entry.RunJsonSha256 -or
            (Get-K1PublishSha256 $entry.LedgerPath) -ne [string]$entry.LedgerSha256) {
            throw "K1_SOURCE_LINEAGE_CHANGED_BEFORE_GATE: $($entry.RunId)"
        }
        $raw = & $EnginePath -Action ValidateRun -ProjectDirectory $ProjectPath -RunDirectory $entry.RunDirectory -PythonPath $PythonPath
        $validationText = ($raw | ForEach-Object { $_.ToString() }) -join "`n"
        try { $validation = $validationText | ConvertFrom-Json -DateKind String }
        catch { throw "K1_SOURCE_VALIDATE_RUN_OUTPUT_INVALID: $($entry.RunId)" }
        if ([string]$validation.schema -ne 'K1_LITE_V2_RUN_VALIDATION_V1' -or [string]$validation.run_id -cne [string]$entry.RunId -or
            [string]$validation.verdict -ne 'PASS' -or [string]$validation.ledger_sha256 -ne [string]$entry.LedgerSha256) {
            throw "K1_SOURCE_VALIDATE_RUN_INVALID: $($entry.RunId)"
        }
        foreach ($gate in $script:K1PublishGateNames) {
            if ($validation.gates.PSObject.Properties.Name -notcontains $gate -or -not [bool]$validation.gates.$gate) {
                throw "K1_SOURCE_GATE_FAIL: $($entry.RunId):$gate"
            }
        }
        # A reviewed source with zero selected cards is valid lineage inside a
        # corpus: it proves that the active file was covered without inventing
        # evidence. Non-empty runs must still be compile-ready. The public
        # single-run compiler separately blocks publishing an empty database.
        $selectedCount = [int]$validation.counts.selected
        if (-not [bool]$validation.gate_ready -or ($selectedCount -gt 0 -and -not [bool]$validation.compile_ready)) {
            throw "K1_SOURCE_NOT_COMPILE_READY: $($entry.RunId)"
        }
        if ((Get-K1PublishSha256 $entry.RunJsonPath) -ne [string]$entry.RunJsonSha256 -or
            (Get-K1PublishSha256 $entry.LedgerPath) -ne [string]$entry.LedgerSha256) {
            throw "K1_SOURCE_LINEAGE_CHANGED_DURING_GATE: $($entry.RunId)"
        }
        $results.Add($validation)
    }
    return @($results)
}

function New-K1PublishReceiptPayload {
    param(
        [Parameter(Mandatory)][ValidateSet('SINGLE','CORPUS','SUPPLEMENT')][string]$PublicationKind,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$PublicationRunDirectory,
        [Parameter(Mandatory)][object]$PublicationRunData,
        [Parameter(Mandatory)][string]$PublicationLedgerPath,
        [Parameter(Mandatory)][string]$PublicationLedgerSha256,
        [Parameter(Mandatory)][string]$PreviewPath,
        [Parameter(Mandatory)][string]$PreviewSha256,
        [Parameter(Mandatory)][string]$CanonicalPath,
        [Parameter(Mandatory)][string]$CanonicalSha256,
        [Parameter(Mandatory)][object[]]$Lineage,
        [Collections.IDictionary]$Extra
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $publicationRun = [IO.Path]::GetFullPath($PublicationRunDirectory)
    $runJsonPath = Join-Path $publicationRun 'run.json'
    $workflowRevision = Get-K1PublishProjectWorkflowRevision -ProjectPath $project
    $payload = [ordered]@{
        schema = $script:K1PublishReceiptSchema
        workflow_revision = $workflowRevision
        engine_version = '2.1.0'
        locator_policy = 'MIXED_V1'
        publication_kind = $PublicationKind
        publication_run_id = [string]$PublicationRunData.run_id
        publication_run_relative = Get-K1PublishRelativePath -ProjectPath $project -Path $publicationRun
        publication_run_json_sha256 = Get-K1PublishSha256 $runJsonPath
        publication_ledger_relative = Get-K1PublishRelativePath -ProjectPath $project -Path $PublicationLedgerPath
        publication_ledger_sha256 = $PublicationLedgerSha256.ToUpperInvariant()
        preview_relative = Get-K1PublishRelativePath -ProjectPath $project -Path $PreviewPath
        preview_sha256 = $PreviewSha256.ToUpperInvariant()
        canonical_relative = Get-K1PublishRelativePath -ProjectPath $project -Path $CanonicalPath
        canonical_sha256 = $CanonicalSha256.ToUpperInvariant()
        source_lineage = @($Lineage | ForEach-Object {
            [ordered]@{
                run_id = [string]$_.RunId
                run_relative = [string]$_.RunRelative
                run_json_sha256 = [string]$_.RunJsonSha256
                ledger_sha256 = [string]$_.LedgerSha256
            }
        })
    }
    if ($Extra) {
        foreach ($key in @($Extra.Keys | Sort-Object)) { $payload[[string]$key] = $Extra[$key] }
    }
    return $payload
}

function ConvertTo-K1PublishReceiptBytes {
    param([Parameter(Mandatory)][Collections.IDictionary]$Payload)
    return [Text.UTF8Encoding]::new($false).GetBytes((($Payload | ConvertTo-Json -Depth 12 -Compress) + "`n"))
}

function Write-K1PublishReceiptCreateNew {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$PublicationRunDirectory,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $metaPath = Join-Path $project 'meta.md'
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "K1_PUBLISH_META_MISSING: $metaPath" }
    $metaText = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $originAuthorization = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $metaText
    $run = [IO.Path]::GetFullPath($PublicationRunDirectory)
    $runPrefix = $project.TrimEnd('\') + '\'
    if (-not $run.StartsWith($runPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'K1_PUBLISH_RUN_OUTSIDE_PROJECT' }
    $path = [IO.Path]::GetFullPath((Join-Path $run 'publish-receipt.json'))
    if (-not ([IO.Path]::GetFullPath((Split-Path -Parent $path))).Equals($run, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'K1_PUBLISH_RECEIPT_PATH_INVALID'
    }
    $bytesSha = Get-K1PublishBytesSha256 $Bytes
    if ($ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $bytesSha -ne $ExpectedSha256.ToUpperInvariant()) {
        throw 'K1_PUBLISH_RECEIPT_BYTES_SHA_MISMATCH'
    }
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        if ((Get-K1PublishSha256 $path) -eq $bytesSha -and
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ceq [Convert]::ToBase64String($Bytes)) {
            return [pscustomobject]@{ Path=$path; Sha256=$bytesSha; Reused=$true }
        }
        throw 'K1_PUBLISH_RECEIPT_ALREADY_EXISTS_DIFFERENT'
    }
    $tempPath = Join-Path $run ('.publish-receipt-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $stream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    try { [IO.File]::Move($tempPath, $path) }
    finally { if (Test-Path -LiteralPath $tempPath -PathType Leaf) { [IO.File]::Delete($tempPath) } }
    if ((Get-K1PublishSha256 $path) -ne $bytesSha) { throw 'K1_PUBLISH_RECEIPT_WRITE_SHA_MISMATCH' }
    return [pscustomobject]@{ Path=$path; Sha256=$bytesSha; Reused=$false }
}

function Assert-K1PublishReceiptCurrent {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ReceiptRelative,
        [Parameter(Mandatory)][string]$ExpectedReceiptSha256,
        [string]$AllowCanonicalSupersededBySha256
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $receiptPath = Resolve-K1PublishRelativePath -ProjectPath $project -RelativePath $ReceiptRelative -Code 'K1_PUBLISH_RECEIPT'
    if ([IO.Path]::GetFileName($receiptPath) -cne 'publish-receipt.json' -or $ExpectedReceiptSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'K1_PUBLISH_RECEIPT_BINDING_INVALID'
    }
    $actualReceiptSha = Get-K1PublishSha256 $receiptPath
    if ($actualReceiptSha -ne $ExpectedReceiptSha256.ToUpperInvariant()) { throw 'K1_PUBLISH_RECEIPT_SHA_MISMATCH' }
    $data = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    $projectWorkflowRevision = Get-K1PublishProjectWorkflowRevision -ProjectPath $project
    if ([string]$data.schema -ne $script:K1PublishReceiptSchema -or [string]$data.engine_version -ne '2.1.0' -or
        $script:K1PublishWorkflowRevisions -cnotcontains [string]$data.workflow_revision -or
        [string]$data.workflow_revision -cne $projectWorkflowRevision -or [string]$data.locator_policy -ne 'MIXED_V1' -or
        [string]$data.publication_kind -notin @('SINGLE','CORPUS','SUPPLEMENT')) {
        throw 'K1_PUBLISH_RECEIPT_SCHEMA_INVALID'
    }
    $publicationRun = Resolve-K1PublishRelativePath -ProjectPath $project -RelativePath ([string]$data.publication_run_relative) -Code 'K1_PUBLISH_RUN' -Directory
    if (-not ([IO.Path]::GetFullPath((Split-Path -Parent $receiptPath))).Equals($publicationRun, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'K1_PUBLISH_RECEIPT_RUN_PATH_MISMATCH'
    }
    $runJsonPath = Join-Path $publicationRun 'run.json'
    if ((Get-K1PublishSha256 $runJsonPath) -ne [string]$data.publication_run_json_sha256) { throw 'K1_PUBLISH_RUN_JSON_SHA_MISMATCH' }
    $runData = Get-Content -LiteralPath $runJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    if ([string]$runData.run_id -cne [string]$data.publication_run_id) { throw 'K1_PUBLISH_RUN_ID_MISMATCH' }
    $expectedKind = if ([string]$runData.schema -eq 'K1_LITE_V2_RUN_V1') { 'SINGLE' }
        elseif ([string]$runData.run_type -eq 'CORPUS_COMPILE') { 'CORPUS' }
        elseif ([string]$runData.run_type -eq 'SUPPLEMENT_AGGREGATE') { 'SUPPLEMENT' }
        else { throw 'K1_PUBLISH_RECEIPT_RUN_TYPE_INVALID' }
    if ([string]$data.publication_kind -cne $expectedKind) { throw 'K1_PUBLISH_RECEIPT_KIND_MISMATCH' }
    $ledgerPath = Resolve-K1PublishRelativePath -ProjectPath $project -RelativePath ([string]$data.publication_ledger_relative) -Code 'K1_PUBLISH_LEDGER'
    $publicationLedgerBindingValid = (Get-K1PublishSha256 $ledgerPath) -eq [string]$data.publication_ledger_sha256
    if (-not $publicationLedgerBindingValid -and $expectedKind -eq 'SINGLE') {
        $publicationLedgerBindingValid = $null -ne (Get-K1PublishLedgerHistoryState -Path $ledgerPath -ExpectedSha256 ([string]$data.publication_ledger_sha256))
    }
    if (-not ([IO.Path]::GetFullPath((Split-Path -Parent $ledgerPath))).Equals($publicationRun, [StringComparison]::OrdinalIgnoreCase) -or
        -not $publicationLedgerBindingValid) {
        throw 'K1_PUBLISH_LEDGER_BINDING_INVALID'
    }
    $previewPath = Resolve-K1PublishRelativePath -ProjectPath $project -RelativePath ([string]$data.preview_relative) -Code 'K1_PUBLISH_PREVIEW'
    $canonicalPath = Resolve-K1PublishRelativePath -ProjectPath $project -RelativePath ([string]$data.canonical_relative) -Code 'K1_PUBLISH_CANONICAL'
    if (-not [string]::IsNullOrWhiteSpace($AllowCanonicalSupersededBySha256) -and $AllowCanonicalSupersededBySha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'K1_PUBLISH_SUPERSEDED_CANONICAL_SHA_INVALID'
    }
    $actualCanonicalSha = Get-K1PublishSha256 $canonicalPath
    $canonicalBindingCurrent = $actualCanonicalSha -eq [string]$data.canonical_sha256
    $canonicalBindingSuperseded = -not [string]::IsNullOrWhiteSpace($AllowCanonicalSupersededBySha256) -and
        $actualCanonicalSha -eq $AllowCanonicalSupersededBySha256.ToUpperInvariant()
    if (-not $canonicalPath.Equals([IO.Path]::GetFullPath((Join-Path $project '01-baza-dowodow.md')), [StringComparison]::OrdinalIgnoreCase) -or
        -not $previewPath.StartsWith($publicationRun.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [string]$data.preview_sha256 -ne [string]$data.canonical_sha256 -or
        (Get-K1PublishSha256 $previewPath) -ne [string]$data.preview_sha256 -or
        (-not $canonicalBindingCurrent -and -not $canonicalBindingSuperseded)) {
        throw 'K1_PUBLISH_ARTIFACT_BINDING_INVALID'
    }
    $lineage = @(Resolve-K1PublishLineage -ProjectPath $project -PublicationRunDirectory $publicationRun -PublicationRunData $runData -ExpectedPublicationLedgerSha256 ([string]$data.publication_ledger_sha256))
    $declared = @($data.source_lineage)
    if ($declared.Count -ne $lineage.Count) { throw 'K1_PUBLISH_RECEIPT_LINEAGE_COUNT_INVALID' }
    for ($index = 0; $index -lt $lineage.Count; $index++) {
        if ([string]$declared[$index].run_id -cne [string]$lineage[$index].RunId -or
            [string]$declared[$index].run_relative -cne [string]$lineage[$index].RunRelative -or
            [string]$declared[$index].run_json_sha256 -ne [string]$lineage[$index].RunJsonSha256 -or
            [string]$declared[$index].ledger_sha256 -ne [string]$lineage[$index].DeclaredLedgerSha256) {
            throw 'K1_PUBLISH_RECEIPT_LINEAGE_MISMATCH'
        }
    }
    if ($expectedKind -eq 'SUPPLEMENT') {
        if ([string]$data.supplement_source_run -cne [string]$runData.supplement_source_run -or
            [string]$data.supplement_mode -cne [string]$runData.supplement_mode -or
            [string]$data.base_publish_receipt_relative -cne [string]$runData.base_publish_receipt_relative -or
            [string]$data.base_publish_receipt_sha256 -ne [string]$runData.base_publish_receipt_sha256 -or
            [string]$data.canonical_previous_sha256 -ne [string]$runData.canonical_backup_sha256 -or
            [string]$data.recovery_backup_sha256 -ne [string]$runData.canonical_backup_sha256) {
            throw 'K1_PUBLISH_SUPPLEMENT_METADATA_MISMATCH'
        }
        $backupPath = Resolve-K1PublishRelativePath -ProjectPath $project -RelativePath ([string]$data.recovery_backup_relative) -Code 'K1_PUBLISH_RECOVERY_BACKUP'
        if (-not ([IO.Path]::GetFullPath((Split-Path -Parent $backupPath))).Equals($publicationRun, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($backupPath) -cne [string]$runData.canonical_backup_relative -or
            (Get-K1PublishSha256 $backupPath) -ne [string]$data.recovery_backup_sha256) {
            throw 'K1_PUBLISH_RECOVERY_BACKUP_BINDING_INVALID'
        }
        $baseReceiptPath = Resolve-K1PublishRelativePath -ProjectPath $project -RelativePath ([string]$data.base_publish_receipt_relative) -Code 'K1_BASE_PUBLISH_RECEIPT'
        if ($baseReceiptPath.Equals($receiptPath, [StringComparison]::OrdinalIgnoreCase) -or
            (Get-K1PublishSha256 $baseReceiptPath) -ne [string]$data.base_publish_receipt_sha256) {
            throw 'K1_BASE_PUBLISH_RECEIPT_BINDING_INVALID'
        }
        $baseReceiptData = Get-Content -LiteralPath $baseReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
        if ([string]$baseReceiptData.schema -ne $script:K1PublishReceiptSchema -or
            [string]$baseReceiptData.canonical_sha256 -ne [string]$data.canonical_previous_sha256) {
            throw 'K1_BASE_PUBLISH_RECEIPT_CANONICAL_MISMATCH'
        }
    }
    return [pscustomobject]@{ Path=$receiptPath; Sha256=$actualReceiptSha; Data=$data; Lineage=$lineage }
}
