[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
    [switch]$DawidApproved
)

$ErrorActionPreference = 'Stop'
if (-not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }
$project = [IO.Path]::GetFullPath($ProjectPath)
$metaPath = Join-Path $project 'meta.md'
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
Assert-SystemV7PathNoReparse -Path $project | Out-Null
Assert-SystemV7PathNoReparse -Path $metaPath -ContainmentRoot $project | Out-Null
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }

$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$metaSha = (Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash
$workflow = Get-SystemV7SingleMetaField -Text $meta -Name 'WORKFLOW_REVISION'
$schema = Get-SystemV7SingleMetaField -Text $meta -Name 'EVIDENCE_SCHEMA'
$name = Get-SystemV7SingleMetaField -Text $meta -Name 'PROJECT_NAME'
$declaredPath = Get-SystemV7SingleMetaField -Text $meta -Name 'PROJECT_PATH'
$allFieldNames = @([regex]::Matches($meta, '(?m)^(?<name>[A-Z][A-Z0-9_/-]*):') | ForEach-Object { $_.Groups['name'].Value })
$duplicates = @($allFieldNames | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "LEGACY_META_DUPLICATE_FIELDS: $($duplicates.Name -join ', ')" }
if (-not [IO.Path]::GetFullPath($declaredPath).Equals($project, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'LEGACY_PROJECT_PATH_MISMATCH'
}
if (Test-SystemV7CurrentMarkers -ProjectPath $project -MetaText $meta) {
    throw 'CURRENT_PROJECT_CANNOT_BE_REGISTERED_AS_LEGACY'
}

$origin = $null
try {
    if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne $metaSha) { throw 'LEGACY_META_CHANGED_BEFORE_REGISTRATION' }
    $origin = New-SystemV7LegacyOrigin -ProjectPath $project -ProjectName $name -WorkflowRevision $workflow -EvidenceSchema $schema -Reason $Reason
    if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne $metaSha) { throw 'LEGACY_META_CHANGED_DURING_REGISTRATION' }
    $state = Assert-SystemV7LegacyProjectOrigin -ProjectPath $project -MetaText $meta
} catch {
    if ($origin -and (Test-Path -LiteralPath $origin.Path -PathType Leaf) -and
        (Get-FileHash -LiteralPath $origin.Path -Algorithm SHA256).Hash -eq $origin.Sha256) {
        [IO.File]::Delete($origin.Path)
    }
    throw
}
[pscustomobject]@{
    Status = 'LEGACY_PROJECT_REGISTERED'
    ProjectId = $origin.ProjectId
    WorkflowRevision = $workflow
    EvidenceSchema = $schema
    OriginPath = $origin.Path
    OriginSha256 = $state.Sha256
}
