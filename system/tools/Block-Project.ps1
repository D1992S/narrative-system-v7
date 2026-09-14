[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
    [switch]$NoGo,
    [switch]$DawidApproved
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
if (-not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }
$cleanReason = $Reason.Trim()
if (-not (Test-ConcreteNote -Text $cleanReason -MinimumLength 12)) { throw 'BLOCK_REASON_NOT_CONCRETE' }

$project = [IO.Path]::GetFullPath($ProjectPath)
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project | Out-Null
$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
$metaItem = Get-Item -LiteralPath $metaPath -Force
if (($metaItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'META_REPARSE_POINT_BLOCKED' }
$metaShaBefore = (Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash
$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$origin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
try {
if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne $metaShaBefore) { throw 'META_CHANGED_BEFORE_BLOCK' }

function Get-One([string]$Name) {
    $matches = @([regex]::Matches($meta, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
    if ($matches.Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $Name=$($matches.Count)" }
    return $matches[0].Groups[1].Value.Trim()
}
function Put([string]$Text, [string]$Name, [string]$Value) {
    $pattern = "(?m)^$([regex]::Escape($Name)):\s*.*?$"
    if ([regex]::Matches($Text, $pattern).Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $Name" }
    $literal = "${Name}: $Value"
    return [regex]::Replace($Text, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $literal })
}
function Put-Handoff([string]$Text, [string]$Name, [string]$Value) {
    $pattern = "(?m)^- $([regex]::Escape($Name)):\s*.*?$"
    if ([regex]::Matches($Text, $pattern).Count -ne 1) { throw "HANDOFF_FIELD_COUNT_INVALID: $Name" }
    $literal = "- ${Name}: $Value"
    return [regex]::Replace($Text, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $literal })
}

$fromStage = Get-One 'CURRENT_STAGE'
if ([array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5'), $fromStage) -lt 0) { throw "STAGE_CANNOT_BLOCK: $fromStage" }
if ($NoGo -and $fromStage -ne 'W0') { throw 'NO_GO_ONLY_ALLOWED_FROM_W0' }
$decision = Get-One 'W0_DECISION'
if ($fromStage -eq 'W0' -and -not $NoGo -and $decision -eq 'NO-GO') {
    throw 'W0_NO_GO_REQUIRES_NO_GO_SWITCH'
}
$previousStateReceiptPath = Get-One 'LAST_STATE_RECEIPT_PATH'
$previousStateReceiptSha = Get-One 'LAST_STATE_RECEIPT_SHA256'
if (($previousStateReceiptPath -eq 'BRAK') -xor ($previousStateReceiptSha -eq 'BRAK')) { throw 'STATE_RECEIPT_HEAD_POINTER_INCOMPLETE' }
if ($previousStateReceiptPath -ne 'BRAK') {
    $currentStateReceipt = Get-StateReceiptHeadState -ProjectPath $project -MetaText $meta
    if (-not $currentStateReceipt.Valid) { throw "CURRENT_STATE_RECEIPT_INVALID: $($currentStateReceipt.Errors -join '; ')" }
}
$currentGate = Get-One 'LAST_GATE'
if (-not $NoGo) {
    $expectedGate = switch ($fromStage) {
        'W0' {
            'PROJECT_INITIALIZED'
        }
        'K0' { if ($decision -eq 'GO WARUNKOWE') { 'W0_GO_WARUNKOWE' } else { 'W0_GO' } }
        'K1' { 'K0_PASS' }
        'K2' { 'K1_PASS' }
        'K2B' { 'K2_PASS' }
        'K3' { 'K2B_PASS' }
        'K4' { 'K3_PASS' }
        'K5' { 'K4_PASS' }
    }
    if (-not $expectedGate -or $currentGate -ne $expectedGate) {
        throw "STAGE_GATE_INCONSISTENT_BEFORE_BLOCK: stage=$fromStage expected=$expectedGate actual=$currentGate"
    }
}
$lastGate = if ($NoGo) { 'W0_NO_GO' } else { $currentGate }

$decisionDirectory = Join-Path $project '_work\system\state-decisions'
Assert-SystemV7PathNoReparse -Path $decisionDirectory -ContainmentRoot $project | Out-Null
[IO.Directory]::CreateDirectory($decisionDirectory) | Out-Null
Assert-SystemV7PathNoReparse -Path $decisionDirectory -ContainmentRoot $project | Out-Null
$intentHash = Get-SystemV7BlockDecisionIntentSha256 -ProjectOriginSha256 $origin.Sha256 `
    -InputMetaSha256 $metaShaBefore -PreviousStateReceiptPath $previousStateReceiptPath `
    -PreviousStateReceiptSha256 $previousStateReceiptSha -FromStage $fromStage -LastGate $lastGate `
    -Reason $cleanReason -NoGo ([bool]$NoGo)
$decisionReceipt = Join-Path $decisionDirectory "block-$intentHash.json"
$receiptReused = Test-Path -LiteralPath $decisionReceipt -PathType Leaf
$decisionCreatedAt = if ($receiptReused) {
    try { [string]((Get-Content -LiteralPath $decisionReceipt -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String).created_at_utc) }
    catch { throw "BLOCK_ORPHAN_RECEIPT_INVALID_JSON: $($_.Exception.Message)" }
} else { [DateTime]::UtcNow.ToString('o') }
if (-not (Test-ReceiptTimestamp -Value $decisionCreatedAt)) { throw 'BLOCK_ORPHAN_RECEIPT_TIMESTAMP_INVALID' }
$decisionTimestamp = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse($decisionCreatedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$decisionTimestamp)) {
    throw 'BLOCK_ORPHAN_RECEIPT_TIMESTAMP_INVALID'
}
$decisionDate = $decisionTimestamp.UtcDateTime.ToString('yyyy-MM-dd')

$updated = Put $meta 'CURRENT_STAGE' 'BLOCKED'
$updated = Put $updated 'STAGE_OWNER' 'Dawid'
$updated = Put $updated 'OWNER_OVERRIDE' 'BRAK'
$updated = Put $updated 'OWNER_OVERRIDE_RECEIPT_PATH' 'BRAK'
$updated = Put $updated 'OWNER_OVERRIDE_RECEIPT_SHA256' 'BRAK'
$updated = Put $updated 'LAST_STATE_RECEIPT_PATH' 'BRAK'
$updated = Put $updated 'LAST_STATE_RECEIPT_SHA256' 'BRAK'
$updated = Put $updated 'BLOCKED_FROM_STAGE' $fromStage
$updated = Put $updated 'BLOCKED_REASON' $cleanReason
$updated = Put $updated 'LAST_GATE' $lastGate
$updated = Put $updated 'LAST_UPDATED' $decisionDate
$updated = Put $updated 'NEXT_ACTION' 'Dawid rozstrzyga blokadę; bez jawnego odblokowania żaden etap nie może wystartować.'
if ($NoGo) {
    $updated = Put $updated 'W0_DECISION' 'NO-GO'
    $updated = Put $updated 'W0_CONDITIONS' 'BRAK'
    $updated = Put $updated 'W0_CONDITION_STATUS' 'NOT_APPLICABLE'
    $updated = Put $updated 'W0_CONDITION_RESULT' 'BRAK'
    $updated = Put $updated 'W0_CONDITION_CLOSED_AT' 'BRAK'
    $updated = Put $updated 'W0_CONDITION_RECEIPT_PATH' 'BRAK'
    $updated = Put $updated 'W0_CONDITION_RECEIPT_SHA256' 'BRAK'
}
$updated = Put-Handoff $updated 'Właściciel' 'Dawid'
$updated = Put-Handoff $updated 'Zadanie' 'BLOCKED — Dawid rozstrzyga zapisaną blokadę.'

$resultMetaContextSha = Get-StateReceiptMetaContextSha256 -MetaText $updated
$record = New-SystemV7BlockDecisionReceiptRecord -ProjectOriginSha256 $origin.Sha256 `
    -InputMetaSha256 $metaShaBefore -ResultMetaContextSha256 $resultMetaContextSha `
    -PreviousStateReceiptPath $previousStateReceiptPath -PreviousStateReceiptSha256 $previousStateReceiptSha `
    -FromStage $fromStage -LastGate $lastGate -Reason $cleanReason -NoGo ([bool]$NoGo) `
    -CreatedAtUtc $decisionCreatedAt
Write-NewUtf8Json -Path $decisionReceipt -Value $record
$decisionReceiptSha = (Get-FileHash -LiteralPath $decisionReceipt -Algorithm SHA256).Hash
$decisionReceiptRelative = ([IO.Path]::GetRelativePath($project, $decisionReceipt)).Replace('\','/')
$updated = Put $updated 'LAST_STATE_RECEIPT_PATH' $decisionReceiptRelative
$updated = Put $updated 'LAST_STATE_RECEIPT_SHA256' $decisionReceiptSha
if ((Get-StateReceiptMetaContextSha256 -MetaText $updated) -cne $resultMetaContextSha) { throw 'BLOCK_RESULT_META_CONTEXT_INTERNAL_MISMATCH' }

Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text $updated -ExpectedCurrentSha256 $metaShaBefore -HeldLockStream $projectLock

[pscustomobject]@{ Status='BLOCKED'; FromStage=$fromStage; LastGate=$lastGate; Reason=$cleanReason; ProjectOriginSha256=$origin.Sha256; DecisionReceipt=$decisionReceipt; DecisionReceiptSha256=$decisionReceiptSha; DecisionReceiptReused=$receiptReused }
} finally {
    Exit-SystemV7ProjectMetaLock -LockStream $projectLock
}
