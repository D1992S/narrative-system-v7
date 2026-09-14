[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ImpactPath,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{5,127}$')][string]$RunId
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$systemRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
Assert-SystemV7NarrativeProjectInstructionContract -ProjectPath $project -SystemRoot $systemRoot | Out-Null
$lock=Enter-SystemV7ProjectMetaLock -ProjectPath $project
$snapshotCreated=$false;$bundleCreated=$false;$runRoot=Join-Path $project "_work\narrative-runs\$RunId"
try {
if(Test-Path -LiteralPath $runRoot){throw "RUN_BUNDLE_ALREADY_EXISTS: $RunId"}

$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw 'META_MISSING' }
$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$null = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$stage = Get-SystemV7NarrativeMetaField -Text $meta -Name 'CURRENT_STAGE'
if ($stage -notin @('K4','K5')) { throw "QA_IMPACT_REVIEW_REQUIRES_STAGE_K4_OR_K5: $stage" }

$impactFull = [IO.Path]::GetFullPath($ImpactPath)
$null = Get-SystemV7NarrativeRelativePath -Root $project -Path $impactFull
if (-not (Test-Path -LiteralPath $impactFull -PathType Leaf)) { throw 'QA_IMPACT_MISSING' }
$impactState=Get-SystemV7QAImpactState -ProjectPath $project -ImpactPath $impactFull
if(-not $impactState.Valid){throw "QA_IMPACT_INVALID: $($impactState.Errors -join '; ')"}
$impact=$impactState.Data
if ([string]$impact.impact_review_required -cne 'True' -and [string]$impact.change_class -cne 'SEMANTIC_REVIEW_REQUIRED') {
    throw 'QA_IMPACT_REVIEW_NOT_REQUIRED_FOR_MECHANICAL_CHANGE'
}

$oldDraft = Join-Path $project ([string]$impact.old_draft_relative)
$newDraft = Join-Path $project ([string]$impact.new_draft_relative)
foreach ($binding in @(
    @($oldDraft, [string]$impact.old_draft_sha256, 'OLD_DRAFT'),
    @($newDraft, [string]$impact.new_draft_sha256, 'NEW_DRAFT')
)) {
    $full = [IO.Path]::GetFullPath([string]$binding[0])
    $null = Get-SystemV7NarrativeRelativePath -Root $project -Path $full
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "QA_IMPACT_$($binding[2])_MISSING" }
    if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -cne [string]$binding[1]) { throw "QA_IMPACT_$($binding[2])_SHA_MISMATCH" }
}

$schemaSource = Join-Path $systemRoot '_SYSTEM\NARRATIVE\QA-IMPACT-SCHEMA.md'
if (-not (Test-Path -LiteralPath $schemaSource -PathType Leaf)) { throw 'QA_IMPACT_SCHEMA_SOURCE_MISSING' }
$schemaSha = (Get-FileHash -LiteralPath $schemaSource -Algorithm SHA256).Hash
$inputsDir = Join-Path $project '_work\k4\inputs'
[IO.Directory]::CreateDirectory($inputsDir) | Out-Null
$schemaSnapshot = Join-Path $inputsDir "qa-impact-schema-$schemaSha.md"
if (Test-Path -LiteralPath $schemaSnapshot -PathType Leaf) {
    if ((Get-FileHash -LiteralPath $schemaSnapshot -Algorithm SHA256).Hash -cne $schemaSha) { throw 'QA_IMPACT_SCHEMA_SNAPSHOT_TAMPERED' }
} else {
    $temp = Join-Path $inputsDir ('.qa-impact-schema-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::Copy($schemaSource, $temp, $false)
        [IO.File]::Move($temp, $schemaSnapshot);$snapshotCreated=$true
    } finally {
        if (Test-Path -LiteralPath $temp -PathType Leaf) { [IO.File]::Delete($temp) }
    }
}

$bundle = New-SystemV7NarrativeInputBundle -ProjectPath $project -RunType 'QA_IMPACT_REVIEW' -RunId $RunId -Inputs @{
    OLD_DRAFT = $oldDraft
    NEW_DRAFT = $newDraft
    IMMUTABLE_DIFF = $impactFull
    IMPACT_SCHEMA = $schemaSnapshot
}
$bundleCreated=$true
$post=Get-SystemV7NarrativeInputBundleState -ProjectPath $project -ManifestPath $bundle.Path -RequireLiveSource
if(-not $post.Valid){throw "QA_IMPACT_BUNDLE_POSTVALIDATION_FAILED: $($post.Errors -join '; ')"}

[pscustomobject]@{
    Status = 'QA_IMPACT_REVIEW_BUNDLE_READY'
    RunId = $RunId
    DiffSha256 = [string]$impact.diff_sha256
    ManifestPath = $bundle.Path
    ManifestSha256 = $bundle.Sha256
    Instruction = 'Uruchom świeży kontekst ChatGPT. Zwróć DIFF_SHA256 oraz osobną decyzję EDITOR, VERIFY i COLD_READER: RERUN_REQUIRED albo CARRYFORWARD_ALLOWED. Niepewność oznacza RERUN_REQUIRED.'
}
} catch { if($bundleCreated -and (Test-Path -LiteralPath $runRoot -PathType Container)){$null=Assert-SystemV7TreeNoReparse -RootPath $runRoot -ContainmentRoot $project;[IO.Directory]::Delete($runRoot,$true)};if($snapshotCreated -and (Test-Path -LiteralPath $schemaSnapshot -PathType Leaf)){[IO.File]::Delete($schemaSnapshot)};throw } finally { Exit-SystemV7ProjectMetaLock -LockStream $lock }
