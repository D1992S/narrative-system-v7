[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [Parameter(Mandatory)][ValidateSet('K2_ONE_DIRECTION','K3_BUDGET_OVERRIDE','K4_Q1_ACCEPTANCE','K4_Q2_ACCEPTANCE','K4_FACTCHECK_DECISION')][string]$ExceptionType,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TargetId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Decision,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Scope,
    [switch]$DawidApproved
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
$ExceptionType = $ExceptionType.ToUpperInvariant()
if (-not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }
$decisionClean = $Decision.Trim(); $reasonClean = $Reason.Trim(); $scopeClean = $Scope.Trim(); $targetClean = $TargetId.Trim()
if ($decisionClean -match '[\x00-\x1F\x7F]' -or $decisionClean.Length -lt 3) { throw 'EDITORIAL_EXCEPTION_DECISION_INVALID' }
if (-not (Test-ConcreteNote -Text $reasonClean -MinimumLength 10)) { throw 'EDITORIAL_EXCEPTION_REASON_NOT_CONCRETE' }
if ($scopeClean -match '[\x00-\x1F\x7F]' -or $scopeClean.Length -lt 5 -or $scopeClean -match '^(?i:brak|none|n/?a|todo|tbd|placeholder)$') { throw 'EDITORIAL_EXCEPTION_SCOPE_NOT_CONCRETE' }
if ($targetClean -match '[\x00-\x1F\x7F]' -or $targetClean.Length -lt 1) { throw 'EDITORIAL_EXCEPTION_TARGET_INVALID' }

$project = [IO.Path]::GetFullPath($ProjectPath)
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project | Out-Null
$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
$metaBeforeLock = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
if (Test-SystemV7NarrativeV2Revision -MetaText $metaBeforeLock) {
    if ($ExceptionType -ceq 'K3_BUDGET_OVERRIDE') { throw 'K3_BUDGET_OVERRIDE_FORBIDDEN_IN_NARRATIVE_V2' }
    if ($ExceptionType -in @('K4_Q1_ACCEPTANCE','K4_Q2_ACCEPTANCE','K4_FACTCHECK_DECISION')) { throw 'LEGACY_K4_EXCEPTION_FORBIDDEN_IN_NARRATIVE_V2' }
}
$projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
try {
$lockedMeta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
if (Test-SystemV7NarrativeV2Revision -MetaText $lockedMeta) {
    if ($ExceptionType -ceq 'K3_BUDGET_OVERRIDE') { throw 'K3_BUDGET_OVERRIDE_FORBIDDEN_IN_NARRATIVE_V2' }
    if ($ExceptionType -in @('K4_Q1_ACCEPTANCE','K4_Q2_ACCEPTANCE','K4_FACTCHECK_DECISION')) { throw 'LEGACY_K4_EXCEPTION_FORBIDDEN_IN_NARRATIVE_V2' }
}
$origin = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $lockedMeta
$artifactName = switch ($ExceptionType) {
    'K2_ONE_DIRECTION' { '02-architektura-odcinka.md' }
    'K3_BUDGET_OVERRIDE' { '03-draft.md' }
    'K4_Q1_ACCEPTANCE' { '04-raport-qa.md' }
    'K4_Q2_ACCEPTANCE' { '04-raport-qa.md' }
    'K4_FACTCHECK_DECISION' { '04B-fact-check.md' }
}
$artifact = Join-Path $project $artifactName
Assert-SystemV7PathNoReparse -Path $artifact -ContainmentRoot $project | Out-Null
if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { throw "EDITORIAL_EXCEPTION_ARTIFACT_MISSING: $artifact" }
$artifactText = Get-Content -LiteralPath $artifact -Raw -Encoding UTF8

switch ($ExceptionType) {
    'K2_ONE_DIRECTION' {
        if ($decisionClean -cne 'ALLOW_ONE_DIRECTION' -or $scopeClean -cne 'JEDEN_KIERUNEK') { throw 'K2_ONE_DIRECTION_EXCEPTION_VALUES_INVALID' }
        if ($artifactText -notmatch "(?m)^WYBRANY_KIERUNEK:\s*$([regex]::Escape($targetClean))\s*$" -or
            $artifactText -notmatch "(?m)^ONE_DIRECTION_APPROVAL:\s*DAWID=TAK;\s*POWÓD=$([regex]::Escape($reasonClean))\s*$") {
            throw 'K2_ONE_DIRECTION_EXCEPTION_ARTIFACT_MISMATCH'
        }
    }
    'K3_BUDGET_OVERRIDE' {
        if ($decisionClean -cne 'ALLOW_BUDGET_OVERRIDE') { throw 'K3_BUDGET_EXCEPTION_DECISION_INVALID' }
        $expected = "DAWID=TAK; AKT=$targetClean; POWÓD=$reasonClean; ZAKRES=$scopeClean"
        if ($artifactText -notmatch "(?m)^K3_BUDGET_OVERRIDE:\s*$([regex]::Escape($expected))\s*$") { throw 'K3_BUDGET_EXCEPTION_ARTIFACT_MISMATCH' }
    }
    'K4_Q1_ACCEPTANCE' {
        if ($targetClean -notmatch '^QA-\d{3,}$' -or $decisionClean -cne 'ACCEPT_Q1' -or $scopeClean -cne 'QA_Q1') { throw 'K4_Q1_EXCEPTION_VALUES_INVALID' }
        $row = @($artifactText -split '\r?\n' | Where-Object { $_ -match "^\|\s*$([regex]::Escape($targetClean))\s*\|" })
        if ($row.Count -ne 1 -or $row[0] -notmatch '\|\s*Q1\s*\|' -or $row[0] -notmatch '\|\s*ZAAKCEPTOWANY_PRZEZ_DAWIDA\s*\|\s*$') { throw 'K4_Q1_EXCEPTION_ARTIFACT_MISMATCH' }
    }
    'K4_Q2_ACCEPTANCE' {
        if ($targetClean -notmatch '^QA-\d{3,}$' -or $decisionClean -cne 'ACCEPT_Q2' -or $scopeClean -cne 'QA_Q2') { throw 'K4_Q2_EXCEPTION_VALUES_INVALID' }
        $row = @($artifactText -split '\r?\n' | Where-Object { $_ -match "^\|\s*$([regex]::Escape($targetClean))\s*\|" })
        if ($row.Count -ne 1 -or $row[0] -notmatch '\|\s*Q2\s*\|' -or $row[0] -notmatch '\|\s*ZAAKCEPTOWANY_PRZEZ_DAWIDA\s*\|\s*$') { throw 'K4_Q2_EXCEPTION_ARTIFACT_MISMATCH' }
    }
    'K4_FACTCHECK_DECISION' {
        if ($targetClean -notmatch '^FC-\d{3,}$' -or $scopeClean -cne 'FACTCHECK_EXCEPTION') { throw 'K4_FACTCHECK_EXCEPTION_VALUES_INVALID' }
        $row = @($artifactText -split '\r?\n' | Where-Object { $_ -match "^\|\s*$([regex]::Escape($targetClean))\s*\|" })
        if ($row.Count -ne 1 -or $row[0] -notmatch "\|\s*DAWID=TAK;\s*DECYZJA=$([regex]::Escape($decisionClean))\s*\|\s*$") { throw 'K4_FACTCHECK_EXCEPTION_ARTIFACT_MISMATCH' }
    }
}

$artifactSha = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
$artifactRelative = ([IO.Path]::GetRelativePath($project, $artifact)).Replace('\','/')
$directory = Join-Path $project '_work\system\editorial-exceptions'
Assert-SystemV7PathNoReparse -Path $directory -ContainmentRoot $project | Out-Null
if (Test-Path -LiteralPath $directory -PathType Container) {
    $existingMatches = [Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -Force)) {
        try {
            $candidate = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
            if ([string]$candidate.exception_type -ceq $ExceptionType -and [string]$candidate.artifact_sha256 -eq $artifactSha -and [string]$candidate.target_id -ceq $targetClean) {
                $existingMatches.Add($candidate)
            }
        } catch { throw "EDITORIAL_EXCEPTION_EXISTING_RECEIPT_INVALID_JSON: $($file.FullName)" }
    }
    if ($existingMatches.Count -gt 0) {
        $existingState = Get-EditorialExceptionReceiptState -ProjectPath $project -ExceptionType $ExceptionType -ArtifactPath $artifact -TargetId $targetClean `
            -ExpectedDecision $decisionClean -ExpectedReason $reasonClean -ExpectedScope $scopeClean
        if (-not $existingState.Valid) { throw "EDITORIAL_EXCEPTION_ALREADY_EXISTS_OR_INVALID: $($existingState.Errors -join '; ')" }
        [pscustomobject]@{ Status='EDITORIAL_EXCEPTION_REUSED'; ExceptionType=$ExceptionType; TargetId=$targetClean; Artifact=$artifact; ArtifactSha256=$artifactSha; ReceiptPath=$existingState.ReceiptPath; ReceiptSha256=$existingState.ReceiptSha256 }
        return
    }
}
$createdAt = [DateTime]::UtcNow.ToString('o')
$bindingText = "ORIGIN=$($origin.Sha256)`nTYPE=$ExceptionType`nARTIFACT=$artifactRelative`nARTIFACT_SHA=$artifactSha`nTARGET=$targetClean`nDECISION=$decisionClean`nREASON=$reasonClean`nSCOPE=$scopeClean`nCREATED_AT_UTC=$createdAt`n"
$bindingHash = Get-Sha256HexFromText -Text $bindingText
[IO.Directory]::CreateDirectory($directory) | Out-Null
Assert-SystemV7PathNoReparse -Path $directory -ContainmentRoot $project | Out-Null
$receiptPath = Join-Path $directory "$($ExceptionType.ToLowerInvariant())-$artifactSha-$bindingHash.json"
$record = [ordered]@{
    schema='SYSTEM_V7_EDITORIAL_EXCEPTION_RECEIPT_V1'; actor='DAWID';
    attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'; verdict='APPROVED';
    project_origin_sha256=$origin.Sha256; exception_type=$ExceptionType; artifact_relative=$artifactRelative;
    artifact_sha256=$artifactSha; target_id=$targetClean; decision=$decisionClean; reason=$reasonClean; scope=$scopeClean;
    binding_sha256=$bindingHash; created_at_utc=$createdAt
}
Write-NewUtf8Json -Path $receiptPath -Value $record
if ((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash -ne $artifactSha) { throw 'EDITORIAL_EXCEPTION_ARTIFACT_CHANGED_DURING_APPROVAL' }
$state = Get-EditorialExceptionReceiptState -ProjectPath $project -ExceptionType $ExceptionType -ArtifactPath $artifact -TargetId $targetClean `
    -ExpectedDecision $decisionClean -ExpectedReason $reasonClean -ExpectedScope $scopeClean
if (-not $state.Valid) { throw "EDITORIAL_EXCEPTION_RECEIPT_INVALID: $($state.Errors -join '; ')" }
[pscustomobject]@{ Status='EDITORIAL_EXCEPTION_APPROVED'; ExceptionType=$ExceptionType; TargetId=$targetClean; Artifact=$artifact; ArtifactSha256=$artifactSha; ReceiptPath=$state.ReceiptPath; ReceiptSha256=$state.ReceiptSha256 }
} finally {
    Exit-SystemV7ProjectMetaLock -LockStream $projectLock
}
