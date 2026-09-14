[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
    [switch]$DawidApproved
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')

$project = [IO.Path]::GetFullPath($ProjectPath)
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project | Out-Null
if (-not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }
$cleanReason = $Reason.Trim()
if (-not (Test-ConcreteNote -Text $cleanReason -MinimumLength 15) -or
    $cleanReason.Split(' ', [StringSplitOptions]::RemoveEmptyEntries).Count -lt 3) {
    throw 'MANUAL_FALLBACK_REASON_NOT_CONCRETE'
}

$metaPath = Join-Path $project 'meta.md'
$k0Path = Join-Path $project '00-fundament-projektu.md'
foreach ($required in @($metaPath, $k0Path)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "REQUIRED_FILE_MISSING: $required" }
}
$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$originState = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
$projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
try {
$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$originState = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
if ((Get-DocumentField -Text $meta -Name 'K1_RESEARCH_MODE') -ne 'MANUAL_APPROVED') {
    throw 'K1_RESEARCH_MODE_NOT_MANUAL_APPROVED'
}
$expectedMetaReason = "DAWID=TAK; POWÓD=$cleanReason"
if ((Get-DocumentField -Text $meta -Name 'K1_MANUAL_REASON') -ne $expectedMetaReason) {
    throw 'K1_MANUAL_REASON_MISMATCH'
}

$k0Hash = (Get-FileHash -LiteralPath $k0Path -Algorithm SHA256).Hash
$corpus = Get-ActiveSourceCorpusState -ProjectPath $project
$bindingText = "ORIGIN=$($originState.Sha256)`nK0=$k0Hash`nSOURCES=$($corpus.Sha256)`nREASON=$cleanReason`n"
$bindingHash = Get-Sha256HexFromText -Text $bindingText
$receiptDirectory = Join-Path $project '_work\K1\manual-fallback'
Assert-SystemV7PathNoReparse -Path $receiptDirectory -ContainmentRoot $project | Out-Null
[IO.Directory]::CreateDirectory($receiptDirectory) | Out-Null
Assert-SystemV7PathNoReparse -Path $receiptDirectory -ContainmentRoot $project | Out-Null
$receiptPath = Join-Path $receiptDirectory "approval-$bindingHash.json"
Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null
$record = [ordered]@{
    schema = 'SYSTEM_V7_K1_MANUAL_FALLBACK_RECEIPT_V1'
    actor = 'DAWID'
    attestation_scope = 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'
    verdict = 'APPROVED'
    project_origin_sha256 = $originState.Sha256
    binding_sha256 = $bindingHash
    k0_sha256 = $k0Hash
    source_corpus_sha256 = $corpus.Sha256
    source_file_count = $corpus.FileCount
    source_files = @($corpus.Rows)
    reason = $cleanReason
    created_at_utc = [DateTime]::UtcNow.ToString('o')
}
Write-NewUtf8Json -Path $receiptPath -Value $record

[pscustomobject]@{
    Status = 'K1_MANUAL_FALLBACK_RECEIPT_CREATED'
    ReceiptPath = $receiptPath
    ReceiptSha256 = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    BindingSha256 = $bindingHash
}
} finally {
    Exit-SystemV7ProjectMetaLock -LockStream $projectLock
}
