[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateSet('ChatGPT','Claude','Dawid')][string]$Owner,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Scope,
    [switch]$DawidApproved
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
if (-not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }
$cleanReason = $Reason.Trim(); $cleanScope = $Scope.Trim()
if (-not (Test-ConcreteNote -Text $cleanReason -MinimumLength 10)) { throw 'OWNER_OVERRIDE_REASON_NOT_CONCRETE' }
if (-not (Test-ConcreteNote -Text $cleanScope -MinimumLength 5)) { throw 'OWNER_OVERRIDE_SCOPE_NOT_CONCRETE' }
if ($cleanReason.Contains(';') -or $cleanScope.Contains(';')) { throw 'OWNER_OVERRIDE_VALUE_CONTAINS_RESERVED_SEPARATOR' }
$project = [IO.Path]::GetFullPath($ProjectPath)
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project | Out-Null
$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
$metaBefore = [IO.File]::ReadAllBytes($metaPath)
$meta = [Text.UTF8Encoding]::new($false).GetString($metaBefore)
$origin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
try {
if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne (Get-Sha256HexFromBytes -Bytes $metaBefore)) { throw 'META_CHANGED_BEFORE_OWNER_OVERRIDE' }

function Get-SingleMetaField([string]$Name) {
    $matches = @([regex]::Matches($meta, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
    if ($matches.Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $Name=$($matches.Count)" }
    return $matches[0].Groups[1].Value.Trim()
}
function Set-SingleMetaField([string]$Text, [string]$Name, [string]$Value) {
    $pattern = "(?m)^$([regex]::Escape($Name)):\s*.*?$"
    if ([regex]::Matches($Text, $pattern).Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $Name" }
    $literal = "${Name}: $Value"
    return [regex]::Replace($Text, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $literal })
}
function Set-SingleHandoffField([string]$Text, [string]$Name, [string]$Value) {
    $pattern = "(?m)^- $([regex]::Escape($Name)):\s*.*?$"
    if ([regex]::Matches($Text, $pattern).Count -ne 1) { throw "HANDOFF_FIELD_COUNT_INVALID: $Name" }
    $literal = "- ${Name}: $Value"
    return [regex]::Replace($Text, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $literal })
}

$stage = Get-SingleMetaField 'CURRENT_STAGE'
$ownerMap = @{ W0='Dawid'; K0='ChatGPT'; K1='ChatGPT'; K2='ChatGPT'; K2B='ChatGPT'; K3='Claude'; K4='ChatGPT'; K5='Dawid' }
if (-not $ownerMap.ContainsKey($stage)) { throw "OWNER_OVERRIDE_STAGE_NOT_ACTIVE: $stage" }
$canonicalOwner = $ownerMap[$stage]
if ($Owner -eq $canonicalOwner) { throw 'OWNER_OVERRIDE_TARGET_EQUALS_CANONICAL' }
if ((Get-SingleMetaField 'STAGE_OWNER') -ne $canonicalOwner -or (Get-SingleMetaField 'OWNER_OVERRIDE') -ne 'BRAK' -or
    (Get-SingleMetaField 'OWNER_OVERRIDE_RECEIPT_PATH') -ne 'BRAK' -or (Get-SingleMetaField 'OWNER_OVERRIDE_RECEIPT_SHA256') -ne 'BRAK') {
    throw 'OWNER_OVERRIDE_REQUIRES_CLEAN_CANONICAL_STATE'
}
$override = "DAWID=TAK; OWNER=$Owner; POWÓD=$cleanReason; ZAKRES=$cleanScope"
$metaContextSha = Get-OwnerOverrideMetaContextSha256 -MetaText $meta -CanonicalOwner $canonicalOwner
$bindingText = "ORIGIN=$($origin.Sha256)`nMETA_CONTEXT=$metaContextSha`nSTAGE=$stage`nCANONICAL_OWNER=$canonicalOwner`nOWNER=$Owner`nREASON=$cleanReason`nSCOPE=$cleanScope`n"
$bindingHash = Get-Sha256HexFromText -Text $bindingText
$relative = "_work/system/owner-override/$stage-$bindingHash.json"
$receiptPath = Join-Path $project $relative
Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null
[IO.Directory]::CreateDirectory((Split-Path -Parent $receiptPath)) | Out-Null
Assert-SystemV7PathNoReparse -Path (Split-Path -Parent $receiptPath) -ContainmentRoot $project | Out-Null
$record = [ordered]@{
    schema = 'SYSTEM_V7_OWNER_OVERRIDE_RECEIPT_V1'
    actor = 'DAWID'
    attestation_scope = 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'
    verdict = 'APPROVED'
    project_origin_sha256 = $origin.Sha256
    meta_context_sha256 = $metaContextSha
    stage = $stage
    canonical_owner = $canonicalOwner
    owner = $Owner
    reason = $cleanReason
    scope = $cleanScope
    binding_sha256 = $bindingHash
    created_at_utc = [DateTime]::UtcNow.ToString('o')
}
Write-NewUtf8Json -Path $receiptPath -Value $record
$receiptSha = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
try {
    $updated = Set-SingleMetaField $meta 'STAGE_OWNER' $Owner
    $updated = Set-SingleMetaField $updated 'OWNER_OVERRIDE' $override
    $updated = Set-SingleMetaField $updated 'OWNER_OVERRIDE_RECEIPT_PATH' $relative
    $updated = Set-SingleMetaField $updated 'OWNER_OVERRIDE_RECEIPT_SHA256' $receiptSha
    $updated = Set-SingleHandoffField $updated 'Właściciel' $Owner
    Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text $updated -ExpectedCurrentSha256 (Get-Sha256HexFromBytes -Bytes $metaBefore) -HeldLockStream $projectLock
} catch {
    throw
}
[pscustomobject]@{ Status='OWNER_OVERRIDE_APPROVED'; Stage=$stage; CanonicalOwner=$canonicalOwner; Owner=$Owner; ReceiptPath=$receiptPath; ReceiptSha256=$receiptSha }
} finally {
    Exit-SystemV7ProjectMetaLock -LockStream $projectLock
}
