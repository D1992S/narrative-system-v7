[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$VerifyAgentId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TaskId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Note,
    [switch]$ConfirmIndependentVerify
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')

$project = [IO.Path]::GetFullPath($ProjectPath)
$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
$metaBeforeLock = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
if ((Get-SystemV7SingleMetaField -Text $metaBeforeLock -Name 'WORKFLOW_REVISION') -ceq '2026-08-31_NARRATIVE_V2') { throw 'LEGACY_K4_VERIFY_RECEIPT_FORBIDDEN_IN_NARRATIVE_V2' }
$projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
try {
$lockedMeta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
if ((Get-SystemV7SingleMetaField -Text $lockedMeta -Name 'WORKFLOW_REVISION') -ceq '2026-08-31_NARRATIVE_V2') { throw 'LEGACY_K4_VERIFY_RECEIPT_FORBIDDEN_IN_NARRATIVE_V2' }
$origin = Assert-SystemV7CurrentProjectOrigin -ProjectPath $project -MetaText $lockedMeta
if (-not $ConfirmIndependentVerify) { throw 'CONFIRM_INDEPENDENT_VERIFY_REQUIRED' }
if ($VerifyAgentId.Trim().Length -lt 3) { throw 'VERIFY_AGENT_ID_TOO_SHORT' }
if ($TaskId.Trim().Length -lt 8) { throw 'VERIFY_TASK_ID_TOO_SHORT' }
if (-not (Test-ConcreteNote -Text $Note)) {
    throw 'VERIFY_NOTE_NOT_CONCRETE'
}

$draft = Join-Path $project '03-draft.md'
$evidence = Join-Path $project '01-baza-dowodow.md'
$factCheck = Join-Path $project '04B-fact-check.md'
foreach ($required in @($draft, $evidence, $factCheck)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "REQUIRED_FILE_MISSING: $required" }
    Assert-SystemV7PathNoReparse -Path $required -ContainmentRoot $project | Out-Null
}

$fcText = Get-Content -LiteralPath $factCheck -Raw -Encoding UTF8
$declaredAgentMatches = @([regex]::Matches($fcText, '(?m)^VERIFY_AGENT_ID:\s*(.*?)\s*$'))
$declaredTaskMatches = @([regex]::Matches($fcText, '(?m)^VERIFY_TASK_ID:\s*(.*?)\s*$'))
if ($declaredAgentMatches.Count -ne 1) { throw "VERIFY_AGENT_ID_FIELD_COUNT_INVALID: $($declaredAgentMatches.Count)" }
if ($declaredTaskMatches.Count -ne 1) { throw "VERIFY_TASK_ID_FIELD_COUNT_INVALID: $($declaredTaskMatches.Count)" }
$declaredAgent = $declaredAgentMatches[0].Groups[1].Value.Trim()
$declaredTask = $declaredTaskMatches[0].Groups[1].Value.Trim()
$declaredDraft = Get-DocumentField -Text $fcText -Name 'DRAFT_SHA256'
$actualDraft = (Get-FileHash -LiteralPath $draft -Algorithm SHA256).Hash
if ($declaredAgent -cne $VerifyAgentId) { throw 'VERIFY_AGENT_ID_MISMATCH' }
if ($declaredTask -cne $TaskId) { throw 'VERIFY_TASK_ID_MISMATCH' }
if ($declaredDraft -ne $actualDraft) { throw 'VERIFY_DRAFT_SHA_MISMATCH' }
if ((Get-DocumentField -Text $fcText -Name 'BRAK_UDZIAŁU_W_K3') -ne 'TAK') { throw 'VERIFY_K3_INDEPENDENCE_NOT_CONFIRMED' }
if ((Get-DocumentField -Text $fcText -Name 'ŹRÓDŁA_DOSTĘPNE') -ne 'TAK') { throw 'VERIFY_SOURCES_NOT_CONFIRMED' }

$corpus = Get-ActiveSourceCorpusState -ProjectPath $project
$factCheckHash = (Get-FileHash -LiteralPath $factCheck -Algorithm SHA256).Hash
$receiptDirectory = Join-Path $project '_work\K4'
Assert-SystemV7PathNoReparse -Path $receiptDirectory -ContainmentRoot $project | Out-Null
[IO.Directory]::CreateDirectory($receiptDirectory) | Out-Null
Assert-SystemV7PathNoReparse -Path $receiptDirectory -ContainmentRoot $project | Out-Null
$receiptPath = Join-Path $receiptDirectory "verify-$factCheckHash.json"
Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null
$receiptCreatedAt = if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
    try { [string]((Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String).created_at_utc) }
    catch { throw "K4_EXISTING_RECEIPT_INVALID_JSON: $($_.Exception.Message)" }
} else { [DateTime]::UtcNow.ToString('o') }
if (-not (Test-ReceiptTimestamp -Value $receiptCreatedAt)) { throw 'K4_EXISTING_RECEIPT_TIMESTAMP_INVALID' }
$record = New-SystemV7K4VerifyReceiptRecord -ProjectOriginSha256 $origin.Sha256 `
    -VerifyAgentId $VerifyAgentId.Trim() -TaskId $TaskId.Trim() -DraftSha256 $actualDraft `
    -EvidenceSha256 (Get-FileHash -LiteralPath $evidence -Algorithm SHA256).Hash `
    -SourceCorpusSha256 $corpus.Sha256 -SourceFileCount $corpus.FileCount -SourceFiles @($corpus.Rows) `
    -FactCheckSha256 $factCheckHash -Note $Note.Trim() -CreatedAtUtc $receiptCreatedAt
Write-NewUtf8Json -Path $receiptPath -Value $record

[pscustomobject]@{
    Status = 'K4_VERIFY_RECEIPT_CREATED'
    ReceiptPath = $receiptPath
    ReceiptSha256 = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    DraftSha256 = $actualDraft
    FactCheckSha256 = $factCheckHash
    SourceCorpusSha256 = $corpus.Sha256
}
} finally {
    Exit-SystemV7ProjectMetaLock -LockStream $projectLock
}
