[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [string]$OldDraftPath,

    [string]$NewDraftPath,

    [switch]$WriteImpact,

    [switch]$SaveBaseline
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$dispatchMetaPath = Join-Path $project 'meta.md'
if (Test-Path -LiteralPath $dispatchMetaPath -PathType Leaf) {
    . (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
    $dispatchMeta = Get-Content -LiteralPath $dispatchMetaPath -Raw -Encoding UTF8
    if (Test-SystemV7NarrativeV2Revision -MetaText $dispatchMeta) {
        & (Join-Path $PSScriptRoot 'Compare-DraftV2.ps1') -ProjectPath $project -SaveBaseline:$SaveBaseline -OldDraftPath $OldDraftPath -NewDraftPath $NewDraftPath -WriteImpact:$WriteImpact
        return
    }
}
$draftPath = Join-Path $project '03-draft.md'
$workDir = Join-Path $project '_work'
$baselinePath = Join-Path $workDir 'qa-baseline.md'
$baselineReceiptPath = Join-Path $workDir 'qa-baseline.receipt.json'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
$projectLock = if ($SaveBaseline) { Enter-SystemV7ProjectMetaLock -ProjectPath $project } else { $null }
try {
$origin = Assert-SystemV7CurrentProjectOrigin -ProjectPath $project -MetaText (Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8)
foreach ($controlledPath in @($draftPath,$workDir,$baselinePath,$baselineReceiptPath)) {
    Assert-SystemV7PathNoReparse -Path $controlledPath -ContainmentRoot $project | Out-Null
}

if (-not (Test-Path -LiteralPath $draftPath -PathType Leaf)) {
    throw "Brak pliku: $draftPath"
}

function Get-Narration {
    param([string]$Path)
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $parts = [regex]::Split($text, '(?m)^---\s*$')
    if ($parts.Count -gt 1) { $text = ($parts | Select-Object -Skip 1) -join "`n" }
    $text = [regex]::Replace($text, '<!--[\s\S]*?-->', ' ')
    $text = [regex]::Replace($text, '(?m)^#{1,6}\s+.*$', ' ')
    $text = [regex]::Replace($text, '(?m)^\s*\|.*\|\s*$', ' ')
    $text = [regex]::Replace($text, '(?m)^\s*\[[^\]]*\]\s*$', ' ')
    $text = [regex]::Replace($text, '[`*_\[\]{}()>#]', ' ')
    return $text
}

function Get-Words {
    param([string]$Text)
    $found = [regex]::Matches($Text, "[\p{L}\p{N}]+(?:[-'’][\p{L}\p{N}]+)*(?:[.,]\p{N}+)*")
    $list = foreach ($m in $found) { $m.Value.ToLowerInvariant() }
    return @($list)
}

if ($SaveBaseline) {
    if (-not (Test-Path -LiteralPath $workDir)) { [IO.Directory]::CreateDirectory($workDir) | Out-Null }
    Assert-SystemV7PathNoReparse -Path $workDir -ContainmentRoot $project | Out-Null
    if (Test-Path -LiteralPath $baselineReceiptPath) { throw 'BASELINE_RECEIPT_ALREADY_EXISTS: zapis K4 jest jednokrotny.' }
    $draftText = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
    $rev = [regex]::Match($draftText, '(?m)^CONTENT_REVISION:\s*(\S+)').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($rev)) { throw 'DRAFT_REVISION_MISSING' }
    $draftBytes = [IO.File]::ReadAllBytes($draftPath)
    $baselineCreatedNow = $false
    if (Test-Path -LiteralPath $baselinePath -PathType Leaf) {
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($baselinePath)) -cne [Convert]::ToBase64String($draftBytes)) {
            throw 'ORPHAN_BASELINE_DIFFERS_FROM_CURRENT_DRAFT'
        }
    } else {
        Write-BytesCreateNewAtomic -Path $baselinePath -Bytes $draftBytes
        $baselineCreatedNow = $true
    }
    $baselineHash = (Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash
    try {
        Write-NewUtf8Json -Path $baselineReceiptPath -Value ([ordered]@{
            schema = 'SYSTEM_V7_QA_BASELINE_RECEIPT_V1'
            project_origin_sha256 = $origin.Sha256
            baseline_relative = '_work/qa-baseline.md'
            baseline_sha256 = $baselineHash
            source_draft_sha256 = (Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash
            source_draft_revision = $rev
            created_at_utc = [DateTime]::UtcNow.ToString('o')
        })
    } catch {
        if ($baselineCreatedNow -and (Test-Path -LiteralPath $baselinePath -PathType Leaf)) { Remove-Item -LiteralPath $baselinePath -Force }
        throw
    }
    [pscustomobject]@{
        Baseline = $baselinePath
        BaselineSha256 = $baselineHash
        Receipt = $baselineReceiptPath
        DraftRevision = $rev
        Info = 'Niezmienny baseline i receipt zapisane. Po poprawkach uruchom skrypt bez -SaveBaseline.'
    }
    return
}

if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
    throw "Brak baseline'u: $baselinePath. Najpierw, w momencie werdyktu K4, uruchom skrypt z -SaveBaseline."
}
if (-not (Test-Path -LiteralPath $baselineReceiptPath -PathType Leaf)) {
    throw "Brak receiptu baseline'u: $baselineReceiptPath."
}
$baselineReceipt = try { Get-Content -LiteralPath $baselineReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String } catch { throw "Nieprawidłowy receipt baseline'u: $($_.Exception.Message)" }
$baselineHash = (Get-FileHash -LiteralPath $baselinePath -Algorithm SHA256).Hash
if ($baselineReceipt.schema -ne 'SYSTEM_V7_QA_BASELINE_RECEIPT_V1' -or
    $baselineReceipt.project_origin_sha256 -ne $origin.Sha256 -or
    $baselineReceipt.baseline_relative -ne '_work/qa-baseline.md' -or
    $baselineReceipt.baseline_sha256 -ne $baselineHash -or
    $baselineReceipt.source_draft_sha256 -ne $baselineHash -or
    [string]::IsNullOrWhiteSpace([string]$baselineReceipt.source_draft_revision)) {
    throw "Baseline QA lub jego receipt został podmieniony."
}

$baseWords = Get-Words (Get-Narration $baselinePath)
$currWords = Get-Words (Get-Narration $draftPath)
if ($baseWords.Count -eq 0) { throw 'Baseline nie zawiera narracji (brak tekstu po separatorze ---).' }

# Porównanie na trójkach kolejnych słów: wykrywa przepisanie i przestawienie, nie tylko podmianę słów.
function Get-Shingles {
    param([string[]]$Words, [int]$N = 3)
    $out = New-Object 'System.Collections.Generic.Dictionary[string,int]'
    if ($Words.Count -lt $N) {
        $key = ($Words -join ' ')
        if ($key) { $out[$key] = 1 }
        return $out
    }
    for ($i = 0; $i -le $Words.Count - $N; $i++) {
        $key = ($Words[$i..($i + $N - 1)] -join ' ')
        if ($out.ContainsKey($key)) { $out[$key]++ } else { $out[$key] = 1 }
    }
    return $out
}

$a = Get-Shingles $baseWords
$b = Get-Shingles $currWords
$common = 0
foreach ($k in $a.Keys) { if ($b.ContainsKey($k)) { $common += [Math]::Min($a[$k], $b[$k]) } }
$aTotal = 0; foreach ($v in $a.Values) { $aTotal += $v }
$bTotal = 0; foreach ($v in $b.Values) { $bTotal += $v }
$changed = [Math]::Max($aTotal - $common, $bTotal - $common)
$pct = [Math]::Round(100.0 * $changed / [Math]::Max($aTotal, 1), 1)
if ($pct -gt 100) { $pct = 100 }

$verdict = if ($pct -gt 20) { 'PONAD 20% — WYMAGANY PEŁNY K4 I NOWY FACT-CHECK' } else { 'W GRANICACH JEDNEJ PĘTLI (<= 20%)' }

[pscustomobject]@{
    BaselineWords = $baseWords.Count
    CurrentWords = $currWords.Count
    ChangeScopePercent = $pct
    Verdict = $verdict
    BaselineSha256 = $baselineHash
    BaselineReceiptSha256 = (Get-FileHash -LiteralPath $baselineReceiptPath -Algorithm SHA256).Hash
    Note = 'Wpisz ChangeScopePercent do nagłówka 03-draft.md (pole CHANGE_SCOPE_PERCENT).'
}
} finally {
    if ($SaveBaseline) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
}
