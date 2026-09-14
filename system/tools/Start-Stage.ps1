[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$metaPath = Join-Path $project 'meta.md'
$systemRoot = Split-Path -Parent $PSScriptRoot
$templates = Join-Path $systemRoot 'TEMPLATES\PROJECT'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')

if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
    throw "Brak meta.md: $metaPath"
}
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project -SystemRoot $systemRoot | Out-Null

$projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
try {
$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
function Get-SingleMetaValue([string]$Name) {
    $matches = @([regex]::Matches($meta, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
    if ($matches.Count -ne 1) { throw "Pole meta $Name musi wystąpić dokładnie raz; znaleziono $($matches.Count)." }
    $value = $matches[0].Groups[1].Value.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { throw "Pole meta $Name nie może być puste." }
    return $value
}
$allMetaFieldNames = @([regex]::Matches($meta, '(?m)^(?<name>[A-Z][A-Z0-9_/-]*):') | ForEach-Object { $_.Groups['name'].Value })
$duplicates = @($allMetaFieldNames | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "Powtórzone pola meta: $($duplicates.Name -join ', ')." }

$stage = Get-SingleMetaValue 'CURRENT_STAGE'
$currentOwner = Get-SingleMetaValue 'STAGE_OWNER'
$ownerOverride = Get-SingleMetaValue 'OWNER_OVERRIDE'
$workflowRevision = Get-SingleMetaValue 'WORKFLOW_REVISION'
$evidenceSchema = Get-SingleMetaValue 'EVIDENCE_SCHEMA'
$isNarrativeV2 = $workflowRevision -ceq $script:SystemV7CurrentWorkflowRevision
$templateRelativePath = if ($isNarrativeV2) { 'TEMPLATES\PROJECT' } else { 'tools\compatibility\PROJECT-LEGACY-K1-LITE-V2' }
$templates = Join-Path $systemRoot $templateRelativePath
$usesK1LiteV2K1 = $workflowRevision -in @($script:SystemV7CurrentWorkflowRevision,$script:SystemV7PreviousProjectWorkflowRevision)
$k1ResearchMode = if ($usesK1LiteV2K1) { Get-SingleMetaValue 'K1_RESEARCH_MODE' } else { '' }
$fallbackReason = if ($usesK1LiteV2K1) { Get-SingleMetaValue 'K1_MANUAL_REASON' } else { '' }
if ($usesK1LiteV2K1) {
    $originState = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $meta
} elseif ($script:SystemV7LegacyWorkflowSchemaMap.Contains($workflowRevision) -and
    [string]$script:SystemV7LegacyWorkflowSchemaMap[$workflowRevision] -ceq $evidenceSchema) {
    $originState = Assert-SystemV7LegacyProjectOrigin -ProjectPath $project -MetaText $meta
    throw 'LEGACY_PROJECT_IS_VALIDATION_ONLY'
} else {
    throw "UNSUPPORTED_WORKFLOW_SCHEMA_PAIR: $workflowRevision + $evidenceSchema"
}

$ownerMap = @{
    'W0' = 'Dawid'
    'K0' = 'ChatGPT'
    'K1' = 'ChatGPT'
    'K2' = 'ChatGPT'
    'K2B' = 'ChatGPT'
    'K3' = 'Claude'
    'K4' = 'ChatGPT'
    'K5' = 'Dawid'
}

$map = @{
    'W0' = @()
    'K0' = @('00-fundament-projektu.md')
    'K1' = @('01-baza-dowodow.md')
    'K2' = @('02-architektura-odcinka.md')
    'K2B' = @()
    'K3' = @('03-draft.md')
    'K4' = @('04-raport-qa.md', '04B-fact-check.md')
    'K5' = @('05-FINAL-SCRIPT.md')
}
if ($isNarrativeV2) {
    # W Narrative V2 draft i raporty K4 tworzą wyłącznie deterministyczne
    # kompilatory po przejściu pełnych bramek; Start-Stage nie może podłożyć
    # pustego pliku, który wyglądałby jak gotowy artefakt.
    $map['K3'] = @()
    $map['K4'] = @()
}

if ($usesK1LiteV2K1 -and $stage -eq 'K1' -and $k1ResearchMode -eq 'K1_LITE_V2') {
    # Nowy K1 zaczyna się od izolowanego runu V2. Kanoniczny plik powstaje dopiero
    # przez kompilator po pełnym pokryciu, decyzjach i kontroli technicznej.
    $map['K1'] = @()
} elseif ($usesK1LiteV2K1 -and $stage -eq 'K1' -and $k1ResearchMode -eq 'MANUAL_APPROVED') {
    if ($fallbackReason -notmatch '^DAWID=TAK;\s*POWÓD=(.{15,})$') {
        throw 'MANUAL_APPROVED wymaga K1_MANUAL_REASON: DAWID=TAK; POWÓD=<min. 15 znaków>.'
    }
    $manualFallbackState = Get-K1ManualFallbackReceiptState -ProjectPath $project
    if (-not $manualFallbackState.Valid) { throw "MANUAL_APPROVED nie ma aktualnego receiptu Dawida: $($manualFallbackState.Errors -join '; ')" }
} elseif ($usesK1LiteV2K1 -and $stage -eq 'K1') {
    throw "Nieprawidłowy K1_RESEARCH_MODE dla nowej rewizji: '$k1ResearchMode'."
}

if (-not $map.ContainsKey($stage)) {
    throw "Etap $stage nie jest aktywnym etapem tworzenia narracji. System kończy się na K5, a potem przechodzi do COMPLETE."
}

if ($usesK1LiteV2K1) {
    $lastGate = Get-SingleMetaValue 'LAST_GATE'
    $w0Decision = Get-SingleMetaValue 'W0_DECISION'
    $requiredEntryGate = switch ($stage) {
        'W0' { 'PROJECT_INITIALIZED' }
        'K0' { if ($w0Decision -eq 'GO WARUNKOWE') { 'W0_GO_WARUNKOWE' } else { 'W0_GO' } }
        'K1' { 'K0_PASS' }
        'K2' { 'K1_PASS' }
        'K2B' { 'K2_PASS' }
        'K3' { 'K2B_PASS' }
        'K4' { 'K3_PASS' }
        'K5' { 'K4_PASS' }
    }
    if ($lastGate -ne $requiredEntryGate) { throw "Etap $stage wymaga LAST_GATE $requiredEntryGate, jest '$lastGate'." }
}

$stageFiles = @($map[$stage])
$expectedOwner = if ($ownerMap.ContainsKey($stage)) { $ownerMap[$stage] } else { '' }
$retiredOwnerNames = @(('Gemi' + 'ni'), ('Anti' + 'gravity'))
$hasRetiredOwner = @($retiredOwnerNames | Where-Object { $currentOwner -match [regex]::Escape($_) }).Count -gt 0
if ($hasRetiredOwner) {
    throw "STAGE_OWNER wskazuje usuniętą rolę: $currentOwner. Oczekiwany właściciel etapu $stage to $expectedOwner."
} elseif ($usesK1LiteV2K1) {
    $ownerReceiptState = Get-OwnerOverrideReceiptState -ProjectPath $project -MetaText $meta
    if (-not $ownerReceiptState.Valid) { throw "Nieprawidłowy właściciel/receipt zastępstwa: $($ownerReceiptState.Errors -join '; ')" }
    if ($ownerReceiptState.Required) { Write-Warning "STAGE_OWNER ma aktualne zastępstwo '$currentOwner' zamiast '$expectedOwner'." }
} elseif ($expectedOwner -and $currentOwner -and $currentOwner -ne $expectedOwner) {
    $overrideMatch = [regex]::Match($ownerOverride, '^DAWID=TAK;\s*OWNER=([^;]+);\s*POWÓD=(.{10,});\s*ZAKRES=(.{5,})$')
    $activeOwners = @('ChatGPT','Claude','Dawid')
    if ($overrideMatch.Success -and $overrideMatch.Groups[1].Value.Trim() -eq $currentOwner -and $currentOwner -in $activeOwners) {
        Write-Warning "STAGE_OWNER ma zatwierdzone zastępstwo '$currentOwner' zamiast '$expectedOwner': $ownerOverride"
    } else {
        throw "STAGE_OWNER ma wartość '$currentOwner'; kanoniczny właściciel etapu $stage to '$expectedOwner', a OWNER_OVERRIDE nie zawiera prawidłowej decyzji Dawida."
    }
} elseif ($expectedOwner -and $currentOwner -eq $expectedOwner -and $ownerOverride -and $ownerOverride -ne 'BRAK') {
    throw 'OWNER_OVERRIDE musi wrócić do BRAK, gdy STAGE_OWNER jest zgodny z macierzą.'
}

if ($usesK1LiteV2K1 -and $stage -eq 'K1' -and $k1ResearchMode -eq 'K1_LITE_V2') {
    $pendingDirectory = Join-Path $project '_work\K1\k1-lite-v2'
    Assert-SystemV7PathNoReparse -Path $pendingDirectory -ContainmentRoot $project | Out-Null
    if (-not (Test-Path -LiteralPath $pendingDirectory -PathType Container)) {
        [IO.Directory]::CreateDirectory($pendingDirectory) | Out-Null
        Assert-SystemV7PathNoReparse -Path $pendingDirectory -ContainmentRoot $project | Out-Null
    }
}

$created = @()
$existing = @()
foreach ($name in $stageFiles) {
    $source = Join-Path $templates $name
    $destination = Join-Path $project $name
    Assert-SystemV7PathNoReparse -Path $source -ContainmentRoot $systemRoot | Out-Null
    Assert-SystemV7PathNoReparse -Path $destination -ContainmentRoot $project | Out-Null
    if (Test-Path -LiteralPath $destination) {
        $existing += $name
        continue
    }
    Copy-Item -LiteralPath $source -Destination $destination
    $created += $name
}

[pscustomobject]@{
    Stage = $stage
    ExpectedOwner = $expectedOwner
    Created = ($created -join ', ')
    AlreadyExisted = ($existing -join ', ')
    NextAction = if ($usesK1LiteV2K1 -and $stage -eq 'K1' -and $k1ResearchMode -eq 'K1_LITE_V2') {
        'Uruchom Plan K1-Lite V2 2.1.0 z jawnym ProjectDirectory i osobnym ukończonym runem dla każdego aktywnego logicznego źródła. PDF przekazuj z kanonicznym --TEXT.md; samodzielny MD/TXT/SRT/VTT bez argumentu PDF. Dla jednego źródła użyj Compile-K1LiteV2 Preview, a dla wielu Compile-K1LiteV2Corpus; następnie opublikuj przez Compile-K1LiteV2 Publish. Nie twórz 01 ręcznie.'
    } elseif ($usesK1LiteV2K1 -and $stage -eq 'K1' -and $k1ResearchMode -eq 'MANUAL_APPROVED') {
        'Aktualny receipt Dawida został sprawdzony. Użyj lokalnych narzędzi fallback zgodnie z zapisanym powodem; nie twórz indeksu globalnego ani nie modyfikuj źródeł.'
    } elseif ($isNarrativeV2 -and $stage -eq 'K2B') {
        'Rozstrzygnij luki i ewentualny suplement. Ustaw manifest modelu K3, zbuduj tylko paczkę pierwszego aktu, wykonaj Constraint Atomicity Preflight i dopiero PASS otwiera K3.'
    } elseif ($isNarrativeV2 -and $stage -eq 'K3') {
        'Realizuj akty kolejno w świeżych kontekstach Claude: packet -> preflight -> proza/beat -> CONTINUITY_OUT -> niezależny attest. Po wszystkich atestach użyj Assemble-K3Draft.ps1.'
    } elseif ($isNarrativeV2 -and $stage -eq 'K4') {
        'Utwórz trzy odizolowane bundle Start-K4Lenses.ps1, wykonaj Editor, Verify i Cold Reader w różnych TASK_ID, a następnie Compile-K4Reports.ps1.'
    } else {
        'Uzupełnij artefakt bieżącego etapu i uruchom właściwy walidator przed zmianą CURRENT_STAGE.'
    }
}
} finally {
    Exit-SystemV7ProjectMetaLock -LockStream $projectLock
}
