[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ApprovalNote,
    [switch]$DawidApproved
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
$dispatchMetaPath = Join-Path ([IO.Path]::GetFullPath($ProjectPath)) 'meta.md'
if (Test-Path -LiteralPath $dispatchMetaPath -PathType Leaf) {
    $dispatchMeta = Get-Content -LiteralPath $dispatchMetaPath -Raw -Encoding UTF8
    if (Test-SystemV7NarrativeV2Revision -MetaText $dispatchMeta) {
        & (Join-Path $PSScriptRoot 'Approve-K5FinalV2.ps1') -ProjectPath $ProjectPath -ApprovalNote $ApprovalNote -DawidApproved:$DawidApproved
        return
    }
}
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')

$project = [IO.Path]::GetFullPath($ProjectPath)
$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
$projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
try {
$origin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText (Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8)
if (-not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }
if (-not (Test-ConcreteNote -Text $ApprovalNote)) {
    throw 'K5_APPROVAL_NOTE_NOT_CONCRETE'
}

$draft = Join-Path $project '03-draft.md'
$qa = Join-Path $project '04-raport-qa.md'
$factCheck = Join-Path $project '04B-fact-check.md'
$final = Join-Path $project '05-FINAL-SCRIPT.md'
foreach ($required in @($draft, $qa, $factCheck, $final)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "REQUIRED_FILE_MISSING: $required" }
    Assert-SystemV7PathNoReparse -Path $required -ContainmentRoot $project | Out-Null
}

$draftHash = (Get-FileHash -LiteralPath $draft -Algorithm SHA256).Hash
$qaHash = (Get-FileHash -LiteralPath $qa -Algorithm SHA256).Hash
$factCheckHash = (Get-FileHash -LiteralPath $factCheck -Algorithm SHA256).Hash
$finalHash = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash
$finalText = Get-Content -LiteralPath $final -Raw -Encoding UTF8
foreach ($binding in @(
    @('SOURCE_DRAFT_SHA256', $draftHash),
    @('SOURCE_QA_SHA256', $qaHash),
    @('SOURCE_FACTCHECK_SHA256', $factCheckHash)
)) {
    if ((Get-DocumentField -Text $finalText -Name $binding[0]) -ne $binding[1]) {
        throw "K5_SOURCE_BINDING_MISMATCH: $($binding[0])"
    }
}
if ((Get-DocumentField -Text $finalText -Name 'STATUS') -ne 'ZATWIERDZONY') { throw 'K5_STATUS_NOT_APPROVED' }

$k4State = Get-K4VerifyReceiptState -ProjectPath $project
if (-not $k4State.Valid) { throw "K4_VERIFY_RECEIPT_STALE_OR_INVALID: $($k4State.Errors -join '; ')" }
$verifyReceipt = $k4State.ReceiptPath

$receiptDirectory = Join-Path $project '_work\K5'
Assert-SystemV7PathNoReparse -Path $receiptDirectory -ContainmentRoot $project | Out-Null
[IO.Directory]::CreateDirectory($receiptDirectory) | Out-Null
Assert-SystemV7PathNoReparse -Path $receiptDirectory -ContainmentRoot $project | Out-Null
$receiptPath = Join-Path $receiptDirectory "approval-$finalHash.json"
Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null
$receiptCreatedAt = if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
    try { [string]((Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String).created_at_utc) }
    catch { throw "K5_EXISTING_RECEIPT_INVALID_JSON: $($_.Exception.Message)" }
} else { [DateTime]::UtcNow.ToString('o') }
if (-not (Test-ReceiptTimestamp -Value $receiptCreatedAt)) { throw 'K5_EXISTING_RECEIPT_TIMESTAMP_INVALID' }
$record = New-SystemV7K5ApprovalReceiptRecord -ProjectOriginSha256 $origin.Sha256 `
    -FinalSha256 $finalHash -DraftSha256 $draftHash -QaSha256 $qaHash -FactCheckSha256 $factCheckHash `
    -K4VerifyReceiptSha256 (Get-FileHash -LiteralPath $verifyReceipt -Algorithm SHA256).Hash `
    -Note $ApprovalNote.Trim() -CreatedAtUtc $receiptCreatedAt
Write-NewUtf8Json -Path $receiptPath -Value $record

[pscustomobject]@{
    Status = 'K5_APPROVAL_RECEIPT_CREATED'
    ReceiptPath = $receiptPath
    ReceiptSha256 = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    FinalSha256 = $finalHash
}
} finally {
    Exit-SystemV7ProjectMetaLock -LockStream $projectLock
}
