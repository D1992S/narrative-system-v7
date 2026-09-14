[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Resolution,
    [switch]$DawidApproved
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
if (-not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }
$cleanResolution = $Resolution.Trim()
if (-not (Test-ConcreteNote -Text $cleanResolution -MinimumLength 12)) { throw 'UNBLOCK_RESOLUTION_NOT_CONCRETE' }

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
if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne $metaShaBefore) { throw 'META_CHANGED_BEFORE_UNBLOCK' }

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

if ((Get-One 'CURRENT_STAGE') -cne 'BLOCKED') { throw 'PROJECT_NOT_BLOCKED' }
if ((Get-One 'STAGE_OWNER') -cne 'Dawid' -or (Get-One 'OWNER_OVERRIDE') -cne 'BRAK') { throw 'BLOCKED_OWNER_STATE_INVALID' }
if (-not (Test-ConcreteNote -Text (Get-One 'BLOCKED_REASON') -MinimumLength 12)) { throw 'BLOCKED_REASON_INVALID' }
$restore = Get-One 'BLOCKED_FROM_STAGE'
if ([array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5'), $restore) -lt 0) { throw 'BLOCKED_FROM_STAGE_INVALID' }
$decision = Get-One 'W0_DECISION'
$actualGate = Get-One 'LAST_GATE'
$expectedGate = switch ($restore) {
    'W0' {
        if ($decision -eq 'NO-GO') { 'W0_NO_GO' } else { 'PROJECT_INITIALIZED' }
    }
    'K0' { if ($decision -eq 'GO WARUNKOWE') { 'W0_GO_WARUNKOWE' } else { 'W0_GO' } }
    'K1' { 'K0_PASS' }
    'K2' { 'K1_PASS' }
    'K2B' { 'K2_PASS' }
    'K3' { 'K2B_PASS' }
    'K4' { 'K3_PASS' }
    'K5' { 'K4_PASS' }
}
if (-not $expectedGate -or $actualGate -ne $expectedGate) {
    throw "BLOCKED_GATE_INCONSISTENT: restore=$restore expected=$expectedGate actual=$actualGate"
}
$blockDecisionState = Get-AppliedBlockDecisionReceiptState -ProjectPath $project
if (-not $blockDecisionState.Valid) { throw "APPLIED_BLOCK_DECISION_RECEIPT_INVALID: $($blockDecisionState.Errors -join '; ')" }
$previousStateReceiptPath = Get-One 'LAST_STATE_RECEIPT_PATH'
$previousStateReceiptSha = Get-One 'LAST_STATE_RECEIPT_SHA256'
if ($previousStateReceiptPath -eq 'BRAK' -or $previousStateReceiptSha -eq 'BRAK' -or
    $previousStateReceiptSha -cne $blockDecisionState.ReceiptSha256) {
    throw 'APPLIED_BLOCK_DECISION_POINTER_MISMATCH'
}

$ownerMap = @{ W0='Dawid'; K0='ChatGPT'; K1='ChatGPT'; K2='ChatGPT'; K2B='ChatGPT'; K3='Claude'; K4='ChatGPT'; K5='Dawid' }
$nextAction = "Wznowiono etap $restore po decyzji Dawida: $cleanResolution"
$resultLastGate = if ($restore -eq 'W0' -and $decision -eq 'NO-GO') { 'PROJECT_INITIALIZED' } else { $actualGate }
$decisionDirectory = Join-Path $project '_work\system\state-decisions'
Assert-SystemV7PathNoReparse -Path $decisionDirectory -ContainmentRoot $project | Out-Null
$intentHash = Get-SystemV7UnblockDecisionIntentSha256 -ProjectOriginSha256 $origin.Sha256 `
    -InputMetaSha256 $metaShaBefore -PreviousStateReceiptPath $previousStateReceiptPath `
    -PreviousStateReceiptSha256 $previousStateReceiptSha -RestoreStage $restore `
    -BlockedLastGate $actualGate -ResultLastGate $resultLastGate `
    -BlockReceiptSha256 $blockDecisionState.ReceiptSha256 -Resolution $cleanResolution
$decisionReceipt = Join-Path $decisionDirectory "unblock-$intentHash.json"
$receiptReused = Test-Path -LiteralPath $decisionReceipt -PathType Leaf
$decisionCreatedAt = if ($receiptReused) {
    try { [string]((Get-Content -LiteralPath $decisionReceipt -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String).created_at_utc) }
    catch { throw "UNBLOCK_ORPHAN_RECEIPT_INVALID_JSON: $($_.Exception.Message)" }
} else { [DateTime]::UtcNow.ToString('o') }
if (-not (Test-ReceiptTimestamp -Value $decisionCreatedAt)) { throw 'UNBLOCK_ORPHAN_RECEIPT_TIMESTAMP_INVALID' }
$decisionTimestamp = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse($decisionCreatedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$decisionTimestamp)) {
    throw 'UNBLOCK_ORPHAN_RECEIPT_TIMESTAMP_INVALID'
}
$decisionDate = $decisionTimestamp.UtcDateTime.ToString('yyyy-MM-dd')

$updated = Put $meta 'CURRENT_STAGE' $restore
$updated = Put $updated 'STAGE_OWNER' $ownerMap[$restore]
$updated = Put $updated 'OWNER_OVERRIDE' 'BRAK'
$updated = Put $updated 'OWNER_OVERRIDE_RECEIPT_PATH' 'BRAK'
$updated = Put $updated 'OWNER_OVERRIDE_RECEIPT_SHA256' 'BRAK'
$updated = Put $updated 'LAST_STATE_RECEIPT_PATH' 'BRAK'
$updated = Put $updated 'LAST_STATE_RECEIPT_SHA256' 'BRAK'
$updated = Put $updated 'BLOCKED_FROM_STAGE' 'BRAK'
$updated = Put $updated 'BLOCKED_REASON' 'BRAK'
$updated = Put $updated 'LAST_UPDATED' $decisionDate
$updated = Put $updated 'NEXT_ACTION' $nextAction
if ($restore -eq 'W0' -and $decision -eq 'NO-GO') {
    $updated = Put $updated 'W0_DECISION' 'NIEUSTALONE'
    $updated = Put $updated 'LAST_GATE' 'PROJECT_INITIALIZED'
    $updated = Put $updated 'W0_CONDITIONS' 'BRAK'
    $updated = Put $updated 'W0_CONDITION_STATUS' 'NOT_APPLICABLE'
    $updated = Put $updated 'W0_CONDITION_RESULT' 'BRAK'
    $updated = Put $updated 'W0_CONDITION_CLOSED_AT' 'BRAK'
    $updated = Put $updated 'W0_CONDITION_RECEIPT_PATH' 'BRAK'
    $updated = Put $updated 'W0_CONDITION_RECEIPT_SHA256' 'BRAK'
}
$updated = Put-Handoff $updated 'Właściciel' $ownerMap[$restore]
$updated = Put-Handoff $updated 'Zadanie' "$restore — $nextAction"

$resultMetaContextSha = Get-StateReceiptMetaContextSha256 -MetaText $updated
$record = New-SystemV7UnblockDecisionReceiptRecord -ProjectOriginSha256 $origin.Sha256 `
    -InputMetaSha256 $metaShaBefore -ResultMetaContextSha256 $resultMetaContextSha `
    -PreviousStateReceiptPath $previousStateReceiptPath -PreviousStateReceiptSha256 $previousStateReceiptSha `
    -RestoreStage $restore -BlockedLastGate $actualGate -ResultLastGate $resultLastGate `
    -BlockReceiptSha256 $blockDecisionState.ReceiptSha256 -Resolution $cleanResolution `
    -CreatedAtUtc $decisionCreatedAt
Write-NewUtf8Json -Path $decisionReceipt -Value $record
$decisionReceiptSha = (Get-FileHash -LiteralPath $decisionReceipt -Algorithm SHA256).Hash
$decisionReceiptRelative = ([IO.Path]::GetRelativePath($project, $decisionReceipt)).Replace('\','/')
$updated = Put $updated 'LAST_STATE_RECEIPT_PATH' $decisionReceiptRelative
$updated = Put $updated 'LAST_STATE_RECEIPT_SHA256' $decisionReceiptSha
if ((Get-StateReceiptMetaContextSha256 -MetaText $updated) -cne $resultMetaContextSha) { throw 'UNBLOCK_RESULT_META_CONTEXT_INTERNAL_MISMATCH' }

Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text $updated -ExpectedCurrentSha256 $metaShaBefore -HeldLockStream $projectLock

[pscustomobject]@{ Status='UNBLOCKED'; RestoredStage=$restore; Resolution=$cleanResolution; ProjectOriginSha256=$origin.Sha256; DecisionReceipt=$decisionReceipt; DecisionReceiptSha256=$decisionReceiptSha; DecisionReceiptReused=$receiptReused }
} finally {
    Exit-SystemV7ProjectMetaLock -LockStream $projectLock
}
