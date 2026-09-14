[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Result,
    [switch]$DawidApproved
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')

if (-not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }
$cleanResult = $Result.Trim()
if (-not (Test-ConcreteNote -Text $cleanResult -MinimumLength 12)) { throw 'W0_CONDITION_RESULT_NOT_CONCRETE' }
$project = [IO.Path]::GetFullPath($ProjectPath)
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project | Out-Null
$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
$metaBeforeBytes = [IO.File]::ReadAllBytes($metaPath)
$meta = [Text.UTF8Encoding]::new($false).GetString($metaBeforeBytes)
$origin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
try {
if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne (Get-Sha256HexFromBytes -Bytes $metaBeforeBytes)) { throw 'META_CHANGED_BEFORE_W0_CLOSURE' }

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

if ((Get-SingleMetaField 'W0_DECISION') -ne 'GO WARUNKOWE') { throw 'W0_DECISION_NOT_CONDITIONAL' }
if ((Get-SingleMetaField 'W0_CONDITION_STATUS') -ne 'OPEN') { throw 'W0_CONDITION_NOT_OPEN' }
foreach ($field in @('W0_CONDITION_RESULT','W0_CONDITION_CLOSED_AT','W0_CONDITION_RECEIPT_PATH','W0_CONDITION_RECEIPT_SHA256')) {
    if ((Get-SingleMetaField $field) -ne 'BRAK') { throw "W0_CONDITION_ALREADY_HAS_CLOSURE_DATA: $field" }
}
$condition = Get-SingleMetaField 'W0_CONDITIONS'
if ($condition -notmatch '^WARUNEK=.{10,};\s*OWNER=.{2,};\s*TERMIN=\d{4}-\d{2}-\d{2}$') { throw 'W0_CONDITION_FORMAT_INVALID' }
$closedAt = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
$bindingText = "ORIGIN=$($origin.Sha256)`nCONDITION=$condition`nRESULT=$cleanResult`nCLOSED_AT=$closedAt`n"
$bindingHash = Get-Sha256HexFromText -Text $bindingText
$relative = "_work/system/w0-condition/closure-$bindingHash.json"
$receiptPath = Join-Path $project $relative
Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null
[IO.Directory]::CreateDirectory((Split-Path -Parent $receiptPath)) | Out-Null
Assert-SystemV7PathNoReparse -Path (Split-Path -Parent $receiptPath) -ContainmentRoot $project | Out-Null
$record = [ordered]@{
    schema = 'SYSTEM_V7_W0_CONDITION_CLOSURE_V1'
    actor = 'DAWID'
    attestation_scope = 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'
    verdict = 'CLOSED'
    project_origin_sha256 = $origin.Sha256
    condition = $condition
    result = $cleanResult
    closed_at = $closedAt
    binding_sha256 = $bindingHash
    created_at_utc = [DateTime]::UtcNow.ToString('o')
}
Write-NewUtf8Json -Path $receiptPath -Value $record
$receiptSha = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
try {
    $updated = Set-SingleMetaField $meta 'W0_CONDITION_STATUS' 'CLOSED'
    $updated = Set-SingleMetaField $updated 'W0_CONDITION_RESULT' $cleanResult
    $updated = Set-SingleMetaField $updated 'W0_CONDITION_CLOSED_AT' $closedAt
    $updated = Set-SingleMetaField $updated 'W0_CONDITION_RECEIPT_PATH' $relative
    $updated = Set-SingleMetaField $updated 'W0_CONDITION_RECEIPT_SHA256' $receiptSha
    Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text $updated -ExpectedCurrentSha256 (Get-Sha256HexFromBytes -Bytes $metaBeforeBytes) -HeldLockStream $projectLock
} catch {
    throw
}

[pscustomobject]@{
    Status = 'W0_CONDITION_CLOSED'
    ReceiptPath = $receiptPath
    ReceiptSha256 = $receiptSha
    ClosedAt = $closedAt
}
} finally {
    Exit-SystemV7ProjectMetaLock -LockStream $projectLock
}
