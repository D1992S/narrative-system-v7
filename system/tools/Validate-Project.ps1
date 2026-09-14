[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [ValidateNotNullOrEmpty()]
    [string]$PythonPath = 'python.exe',

    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'K1-PublishIntegrity.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')

function Get-MetaValue {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Get-MarkdownSectionBody {
    param([string]$Text, [string]$HeadingPattern)
    $match = [regex]::Match($Text, "(?ms)^##\s+$HeadingPattern\s*\r?\n(.*?)(?=^##\s+|\z)")
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Test-SubstantiveMarkdown {
    param([AllowNull()][string]$Text, [int]$MinimumWords = 4, [int]$MinimumCharacters = 20)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $clean = [regex]::Replace($Text, '<!--[\s\S]*?-->', ' ')
    $clean = [regex]::Replace($clean, '(?m)^\s*\|?(?:\s*:?-+:?\s*\|)+\s*$', ' ')
    $clean = [regex]::Replace($clean, '(?m)^\s*[-*]\s*(?:Q[0-2]|Największe ryzyko)\s*:\s*$', ' ')
    $clean = [regex]::Replace($clean, '[\[\]`*_#>|]', ' ')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    if ($clean.Length -lt $MinimumCharacters -or $clean -match '^(?i:brak|none|n/?a|todo|tbd|placeholder|do uzupełnienia)$') { return $false }
    return [regex]::Matches($clean, '[\p{L}\p{N}]+').Count -ge $MinimumWords
}

function ConvertFrom-MarkdownTableRow {
    param([string]$Line)
    if ($Line -notmatch '^\s*\|.*\|\s*$') { return @() }
    return @(($Line.Trim() -replace '^\|','' -replace '\|$','') -split '\|' | ForEach-Object { $_.Trim() })
}

function Test-ConcreteTableCell {
    param([AllowNull()][string]$Text, [int]$MinimumLength = 3)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $value = $Text.Trim()
    return $value.Length -ge $MinimumLength -and $value -notmatch '^(?i:-+|\.{2,}|brak danych|todo|tbd|placeholder|do uzupełnienia|\[.*\])$'
}

function Get-K3NarrationWordCount {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
    $clean = [regex]::Replace($Text, '<!--[\s\S]*?-->', ' ')
    $clean = [regex]::Replace($clean, '(?m)^#{1,6}\s+.*$', ' ')
    $clean = [regex]::Replace($clean, '(?m)^\s*\|.*\|\s*$', ' ')
    $clean = [regex]::Replace($clean, '(?m)^\s*\[[^\]]*\]\s*$', ' ')
    $clean = [regex]::Replace($clean, '[`*_\[\]{}()>#]', ' ')
    return [regex]::Matches($clean, "[\p{L}\p{N}]+(?:[-'’][\p{L}\p{N}]+)*(?:[.,]\p{N}+)*").Count
}

$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
    $errors.Add('Brak meta.md.')
    $meta = ''
} else {
    $metaItem = Get-Item -LiteralPath $metaPath -Force
    if (($metaItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $errors.Add('meta.md nie może być dowiązaniem ani reparse pointem.') }
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
}

# NARRATIVE_V2 ma odrębny, zamknięty kontrakt. Nie wolno przepuszczać go przez
# walidator poprzedniej rewizji, bo ten rozpoznaje dawne budżety aktów i stary
# model K3/K4. Legacy pozostaje poniżej w trybie zgodnym ze swoją rewizją.
$dispatchWorkflowRevision = Get-MetaValue -Text $meta -Name 'WORKFLOW_REVISION'
if ($dispatchWorkflowRevision -ceq '2026-08-31_NARRATIVE_V2') {
    $narrativeValidator = Join-Path $PSScriptRoot 'Validate-NarrativeV2Project.ps1'
    if (-not (Test-Path -LiteralPath $narrativeValidator -PathType Leaf)) {
        throw 'NARRATIVE_V2_VALIDATOR_MISSING'
    }
    $narrativeResult = & $narrativeValidator -ProjectPath $project -PythonPath $PythonPath -NoExit
    $narrativeResult
    if ($narrativeResult.Verdict -ne 'PASS' -and -not $NoExit) { exit 1 }
    return
}

$requiredFields = @('SYSTEM_VERSION','PROJECT_NAME','PROJECT_PATH','CURRENT_STAGE','STAGE_OWNER','CHANNEL','FORMAT','TARGET_MINUTES','REAL_WPM','WPM_STATUS','RESEARCH_MODE','VERIFICATION_POLICY','REFERENCE_SCRIPT','K2B_DECISION','LAST_GATE','LAST_UPDATED','NEXT_ACTION')
foreach ($field in $requiredFields) {
    $matches = @([regex]::Matches($meta, "(?m)^$([regex]::Escape($field)):\s*(.*?)\s*$"))
    if ($matches.Count -ne 1) {
        $errors.Add("Pole meta $field musi wystąpić dokładnie raz; znaleziono $($matches.Count).")
    } elseif ([string]::IsNullOrWhiteSpace($matches[0].Groups[1].Value)) {
        $errors.Add("Brak wartości pola meta: $field")
    }
}
$allMetaFieldNames = @([regex]::Matches($meta, '(?m)^(?<name>[A-Z][A-Z0-9_/-]*):') | ForEach-Object { $_.Groups['name'].Value })
foreach ($duplicateField in @($allMetaFieldNames | Group-Object | Where-Object Count -gt 1)) {
    $errors.Add("Pole meta $($duplicateField.Name) jest powtórzone $($duplicateField.Count) razy.")
}

$stages = @('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE','BLOCKED')
$stage = Get-MetaValue -Text $meta -Name 'CURRENT_STAGE'
if ($stage -match '^P[1-5]$') { $errors.Add("Nieprawidłowy CURRENT_STAGE: $stage. Etapy realizacyjne zostały usunięte; po zatwierdzeniu K5 ustaw COMPLETE.") }
elseif ($stage -and [array]::IndexOf($stages, $stage) -lt 0) { $errors.Add("Nieprawidłowy CURRENT_STAGE: $stage") }
if ($stage -eq 'BLOCKED') { $errors.Add('Projekt ma status BLOCKED — wymaga decyzji Dawida; walidacja etapowa jest wstrzymana do odblokowania.') }

$workflowRevision = Get-MetaValue -Text $meta -Name 'WORKFLOW_REVISION'
$evidenceSchema = Get-MetaValue -Text $meta -Name 'EVIDENCE_SCHEMA'
$currentWorkflowRevision = '2026-08-30_K1_LITE_V2'
$currentEvidenceSchema = 'MINIMAL_EVIDENCE_V4_PAGELOC'
$previousCompactRevisions = @('2026-08-22_MINIMAL_EVIDENCE', '2026-08-19_SELECTION_FIRST_K1', '2026-08-17_CHATGPT_NARRATION_ONLY', '2026-08-17_CHATGPT_COMPACT_K1')
$supportedCompactRevisions = @($currentWorkflowRevision) + $previousCompactRevisions
$compactSchemas = @('COMPACT_EVIDENCE_V1', 'COMPACT_EVIDENCE_V2', 'MINIMAL_EVIDENCE_V3', 'MINIMAL_EVIDENCE_V4_PAGELOC')
$workflowSchemaMap = @{
    '2026-08-30_K1_LITE_V2' = @('MINIMAL_EVIDENCE_V4_PAGELOC')
    '2026-08-22_MINIMAL_EVIDENCE' = @('MINIMAL_EVIDENCE_V3')
    '2026-08-19_SELECTION_FIRST_K1' = @('COMPACT_EVIDENCE_V2')
    '2026-08-17_CHATGPT_NARRATION_ONLY' = @('COMPACT_EVIDENCE_V1')
    '2026-08-17_CHATGPT_COMPACT_K1' = @('COMPACT_EVIDENCE_V1')
}
$isNarrationOnlyWorkflow = $workflowRevision -in @($currentWorkflowRevision, '2026-08-22_MINIMAL_EVIDENCE', '2026-08-19_SELECTION_FIRST_K1', '2026-08-17_CHATGPT_NARRATION_ONLY')
$isCompactWorkflow = $evidenceSchema -in $compactSchemas
$isK1LiteV2Workflow = $workflowRevision -eq $currentWorkflowRevision
$requiresIntegrityReceipts = $isK1LiteV2Workflow -or (Get-MetaValue -Text $meta -Name 'K1_ENGINE_VERSION') -eq '2.1.0'
$hasCurrentWorkflowMarkers = Test-SystemV7CurrentMarkers -ProjectPath $project -MetaText $meta
$projectOriginState = $null
if ($hasCurrentWorkflowMarkers -or $isK1LiteV2Workflow) {
    try {
        $projectOriginState = Assert-SystemV7CurrentProjectOrigin -ProjectPath $project -MetaText $meta
    } catch {
        $errors.Add("Pochodzenie projektu bieżącej rewizji jest nieprawidłowe: $($_.Exception.Message)")
    }
    if ($workflowRevision -ne $currentWorkflowRevision -or $evidenceSchema -ne $currentEvidenceSchema) {
        $errors.Add("Projekt z markerami bieżącej rewizji nie może zostać zdegradowany: wymagane WORKFLOW_REVISION=$currentWorkflowRevision i EVIDENCE_SCHEMA=$currentEvidenceSchema.")
    }
    if ($projectOriginState) {
        foreach ($treeRelative in @('.system-v7','sources','_work')) {
            $treePath = Join-Path $project $treeRelative
            if (Test-Path -LiteralPath $treePath) {
                try { Assert-SystemV7TreeNoReparse -RootPath $treePath -ContainmentRoot $project | Out-Null }
                catch { $errors.Add("Bezpieczeństwo ścieżek projektu: $($_.Exception.Message)") }
            }
        }
        foreach ($artifactName in @('00-fundament-projektu.md','01-baza-dowodow.md','02-architektura-odcinka.md','03-draft.md','04-raport-qa.md','04B-fact-check.md','05-FINAL-SCRIPT.md')) {
            $artifactPath = Join-Path $project $artifactName
            if (Test-Path -LiteralPath $artifactPath) {
                try { Assert-SystemV7PathNoReparse -Path $artifactPath -ContainmentRoot $project | Out-Null }
                catch { $errors.Add("Bezpieczeństwo ścieżek projektu: $($_.Exception.Message)") }
            }
        }
    }
} elseif ($workflowRevision -in $previousCompactRevisions) {
    try {
        $projectOriginState = Assert-SystemV7LegacyProjectOrigin -ProjectPath $project -MetaText $meta
    } catch {
        $errors.Add("Projekt historyczny wymaga jednorazowej rejestracji pochodzenia przez Register-LegacyProject.ps1: $($_.Exception.Message)")
    }
    if ($projectOriginState) {
        foreach ($treeRelative in @('.system-v7','sources','_work')) {
            $treePath = Join-Path $project $treeRelative
            if (Test-Path -LiteralPath $treePath) {
                try { Assert-SystemV7TreeNoReparse -RootPath $treePath -ContainmentRoot $project | Out-Null }
                catch { $errors.Add("Bezpieczeństwo ścieżek projektu historycznego: $($_.Exception.Message)") }
            }
        }
        foreach ($artifactName in @('00-fundament-projektu.md','01-baza-dowodow.md','02-architektura-odcinka.md','03-draft.md','04-raport-qa.md','04B-fact-check.md','05-FINAL-SCRIPT.md')) {
            $artifactPath = Join-Path $project $artifactName
            if (Test-Path -LiteralPath $artifactPath) {
                try { Assert-SystemV7PathNoReparse -Path $artifactPath -ContainmentRoot $project | Out-Null }
                catch { $errors.Add("Bezpieczeństwo ścieżek projektu historycznego: $($_.Exception.Message)") }
            }
        }
    }
}
$foundationProbePath = Join-Path $project '00-fundament-projektu.md'
$hasCompactFoundation = (Test-Path -LiteralPath $foundationProbePath -PathType Leaf) -and ((Get-Content -LiteralPath $foundationProbePath -Raw -Encoding UTF8) -match '(?m)^ZGODNOŚĆ_Z_W0:')
if (-not $workflowRevision) { $errors.Add('Projekt nie ma WORKFLOW_REVISION. Cichy tryb legacy jest wyłączony; projekt wymaga jawnej migracji albo rejestracji wspieranej rewizji historycznej.') }
if (-not $evidenceSchema) { $errors.Add('Projekt nie ma EVIDENCE_SCHEMA. Cichy tryb legacy jest wyłączony; projekt wymaga jawnej migracji albo rejestracji wspieranej rewizji historycznej.') }
if ($isCompactWorkflow -and $workflowRevision -notin $supportedCompactRevisions) { $errors.Add("Projekt $evidenceSchema ma niewspieraną WORKFLOW_REVISION: $workflowRevision.") }
if ($isCompactWorkflow -and $workflowRevision -in $previousCompactRevisions) { $warnings.Add("Projekt korzysta z poprzedniej rewizji K1. Jego artefakty pozostają zgodne i nie należy ich przepisywać; nowe projekty startują z $currentEvidenceSchema.") }
if ($workflowSchemaMap.ContainsKey($workflowRevision) -and $evidenceSchema -notin $workflowSchemaMap[$workflowRevision]) {
    $errors.Add("WORKFLOW_REVISION $workflowRevision nie obsługuje EVIDENCE_SCHEMA: $evidenceSchema. Dozwolone: $($workflowSchemaMap[$workflowRevision] -join ', ').")
}
if ($workflowRevision -and -not $workflowSchemaMap.ContainsKey($workflowRevision)) {
    $errors.Add("Nierozpoznana WORKFLOW_REVISION '$workflowRevision'. Starszy projekt musi używać jednej z jawnie wspieranych rewizji albo nie deklarować rewizji historycznej.")
}
if ($evidenceSchema -and $evidenceSchema -notin $compactSchemas) {
    $errors.Add("Nierozpoznany EVIDENCE_SCHEMA '$evidenceSchema'. Dowolna etykieta legacy nie może wyłączyć aktywnych bramek.")
}
if ($hasCompactFoundation -and ($workflowRevision -notin $supportedCompactRevisions -or -not $isCompactWorkflow)) {
    $errors.Add('Projekt zawiera fundament bieżącego Compact K1, więc nie może zostać zdegradowany do legacy przez usunięcie lub zmianę WORKFLOW_REVISION/EVIDENCE_SCHEMA.')
}

if ($isK1LiteV2Workflow) {
    foreach ($field in @(
        'OWNER_OVERRIDE','OWNER_OVERRIDE_RECEIPT_PATH','OWNER_OVERRIDE_RECEIPT_SHA256',
        'LAST_STATE_RECEIPT_PATH','LAST_STATE_RECEIPT_SHA256',
        'W0_DECISION','W0_CONDITIONS','W0_CONDITION_STATUS','W0_CONDITION_RESULT','W0_CONDITION_CLOSED_AT','W0_CONDITION_RECEIPT_PATH','W0_CONDITION_RECEIPT_SHA256',
        'K1_RESEARCH_MODE','K1_ENGINE_VERSION','K1_RUN_PATH','K1_LEDGER_SHA256','K1_PUBLISH_RECEIPT_PATH','K1_PUBLISH_RECEIPT_SHA256','K1_MANUAL_REASON',
        'BLOCKED_FROM_STAGE','BLOCKED_REASON'
    )) {
        $matches = @([regex]::Matches($meta, "(?m)^$([regex]::Escape($field)):\s*(.*?)\s*$"))
        if ($matches.Count -ne 1) {
            $errors.Add("Pole meta bieżącej rewizji $field musi wystąpić dokładnie raz; znaleziono $($matches.Count).")
        } elseif ([string]::IsNullOrWhiteSpace($matches[0].Groups[1].Value)) {
            $errors.Add("Brak wartości pola meta nowego K1: $field")
        }
    }
    $k1ResearchMode = Get-MetaValue -Text $meta -Name 'K1_RESEARCH_MODE'
    $k1EngineVersion = Get-MetaValue -Text $meta -Name 'K1_ENGINE_VERSION'
    $fallbackReason = Get-MetaValue -Text $meta -Name 'K1_MANUAL_REASON'
    if ($k1ResearchMode -notin @('K1_LITE_V2','MANUAL_APPROVED')) { $errors.Add("K1_RESEARCH_MODE ma niedozwoloną wartość '$k1ResearchMode'.") }
    try {
        if ([version]$k1EngineVersion -ne [version]'2.1.0') { $errors.Add("K1_ENGINE_VERSION musi mieć dokładnie 2.1.0 w bieżącej rewizji, jest '$k1EngineVersion'.") }
    } catch { $errors.Add("K1_ENGINE_VERSION nie jest poprawną wersją: '$k1EngineVersion'.") }
    if ($k1ResearchMode -eq 'K1_LITE_V2' -and $fallbackReason -ne 'BRAK') { $errors.Add('K1_MANUAL_REASON musi mieć BRAK w trybie podstawowym.') }
    if ($k1ResearchMode -eq 'MANUAL_APPROVED' -and $fallbackReason -notmatch '^DAWID=TAK;\s*POWÓD=(.{15,})$') {
        $errors.Add('MANUAL_APPROVED wymaga K1_MANUAL_REASON w formacie: DAWID=TAK; POWÓD=<min. 15 znaków>.')
    }
}

$stageOwner = Get-MetaValue -Text $meta -Name 'STAGE_OWNER'
$retiredOwnerNames = @(('Gemi' + 'ni'), ('Anti' + 'gravity'))
$hasRetiredOwner = @($retiredOwnerNames | Where-Object { $stageOwner -match [regex]::Escape($_) }).Count -gt 0
if ($hasRetiredOwner) {
    if ($stage -eq 'COMPLETE') {
        $warnings.Add("Historyczny STAGE_OWNER ukończonego projektu wskazuje dawną rolę: $stageOwner. Nie przepisuj historii.")
    } else {
        $errors.Add("STAGE_OWNER wskazuje usuniętą rolę: $stageOwner")
    }
}
$ownerMap = @{
    'W0' = 'Dawid'; 'K0' = 'ChatGPT'; 'K1' = 'ChatGPT'; 'K2' = 'ChatGPT';
    'K2B' = 'ChatGPT'; 'K3' = 'Claude'; 'K4' = 'ChatGPT'; 'K5' = 'Dawid';
    'COMPLETE' = 'Dawid'; 'BLOCKED' = 'Dawid'
}
$ownerOverride = Get-MetaValue -Text $meta -Name 'OWNER_OVERRIDE'
if ($isCompactWorkflow -and [string]::IsNullOrWhiteSpace($ownerOverride)) { $errors.Add('Projekt COMPACT_EVIDENCE_V1 nie ma pola OWNER_OVERRIDE.') }
if ($isK1LiteV2Workflow -and $ownerMap.ContainsKey($stage)) {
    $ownerReceiptState = Get-OwnerOverrideReceiptState -ProjectPath $project -MetaText $meta
    foreach ($ownerProblem in @($ownerReceiptState.Errors)) { $errors.Add("Właściciel etapu: $ownerProblem") }
    if ($ownerReceiptState.Valid -and $ownerReceiptState.Required) {
        $warnings.Add("STAGE_OWNER '$stageOwner' ma aktualny receipt zastępstwa Dawida dla etapu $stage.")
    }
} elseif ($ownerMap.ContainsKey($stage) -and $stageOwner -and $stageOwner -ne $ownerMap[$stage]) {
    if ($isCompactWorkflow) {
        $overrideMatch = [regex]::Match($ownerOverride, '^DAWID=TAK;\s*OWNER=([^;]+);\s*POWÓD=(.{10,});\s*ZAKRES=(.{5,})$')
        $activeOwners = @('ChatGPT','Claude','Dawid')
        if ($overrideMatch.Success -and $overrideMatch.Groups[1].Value.Trim() -eq $stageOwner -and $stageOwner -in $activeOwners) {
            $warnings.Add("STAGE_OWNER '$stageOwner' zastępuje kanonicznego '$($ownerMap[$stage])' dla etapu $stage na podstawie jawnego OWNER_OVERRIDE.")
        } else {
            $errors.Add("STAGE_OWNER '$stageOwner' różni się od kanonicznego '$($ownerMap[$stage])' dla etapu $stage, a OWNER_OVERRIDE nie ma formatu: DAWID=TAK; OWNER=<aktywny właściciel>; POWÓD=<min. 10 znaków>; ZAKRES=<min. 5 znaków>.")
        }
    } elseif ($stageOwner -match '(?i)Codex') {
        $warnings.Add("Starszy identyfikator właściciela '$stageOwner' odpowiada obecnej roli ChatGPT; nie przepisuj historii, ale przed Start-Stage użyj aktualnej nazwy.")
    } else {
        $warnings.Add("Starszy projekt ma niekanoniczny STAGE_OWNER '$stageOwner' dla etapu $stage; przed Start-Stage ustaw '$($ownerMap[$stage])' albo jawne zastępstwo.")
    }
} elseif (-not $isK1LiteV2Workflow -and $isCompactWorkflow -and $ownerMap.ContainsKey($stage) -and $ownerOverride -and $ownerOverride -ne 'BRAK') {
    $errors.Add('OWNER_OVERRIDE musi wrócić do BRAK, gdy STAGE_OWNER jest zgodny z macierzą.')
}

$version = Get-MetaValue -Text $meta -Name 'SYSTEM_VERSION'
if ($version -and $version -ne '7.0') { $errors.Add("Projekt deklaruje SYSTEM_VERSION $version zamiast 7.0.") }

if ($isK1LiteV2Workflow) {
    $channel = Get-MetaValue -Text $meta -Name 'CHANNEL'
    $format = Get-MetaValue -Text $meta -Name 'FORMAT'
    $researchMode = Get-MetaValue -Text $meta -Name 'RESEARCH_MODE'
    $wpmStatus = Get-MetaValue -Text $meta -Name 'WPM_STATUS'
    if ($channel -notin @('dawid_soltan','polska_news','inny')) { $errors.Add("Nieprawidłowy CHANNEL '$channel' w bieżącej rewizji.") }
    if ($format -notin @('STORYTELLING','DZIENNIKARSKI')) { $errors.Add("Nieprawidłowy FORMAT '$format' w bieżącej rewizji.") }
    if ($researchMode -notin @('SOURCES_ONLY','SOURCES_PLUS_WEB_AFTER_CONFIRMATION')) { $errors.Add("Nieprawidłowy RESEARCH_MODE '$researchMode'.") }
    if ($wpmStatus -notin @('ZAŁOŻENIE','POMIAR')) { $errors.Add("Nieprawidłowy WPM_STATUS '$wpmStatus'; dozwolone ZAŁOŻENIE albo POMIAR.") }
    $targetMinutes = 0
    $realWpm = 0
    if (-not [int]::TryParse((Get-MetaValue -Text $meta -Name 'TARGET_MINUTES'), [ref]$targetMinutes) -or $targetMinutes -lt 1 -or $targetMinutes -gt 240) {
        $errors.Add('TARGET_MINUTES musi być liczbą całkowitą 1–240.')
    }
    if (-not [int]::TryParse((Get-MetaValue -Text $meta -Name 'REAL_WPM'), [ref]$realWpm) -or $realWpm -lt 1 -or $realWpm -gt 240) {
        $errors.Add('REAL_WPM musi być liczbą całkowitą 1–240.')
    }
    $lastUpdated = Get-MetaValue -Text $meta -Name 'LAST_UPDATED'
    $lastUpdatedDate = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($lastUpdated, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$lastUpdatedDate) -or
        $lastUpdatedDate.Date -gt [DateTime]::UtcNow.Date) {
        $errors.Add("LAST_UPDATED musi być prawidłową, niefuturystyczną datą YYYY-MM-DD, jest '$lastUpdated'.")
    } elseif ($projectOriginState -and $projectOriginState.Valid) {
        $originCreated = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse([string]$projectOriginState.Data.created_at_utc, [ref]$originCreated) -and
            $lastUpdatedDate.Date -lt $originCreated.UtcDateTime.Date) {
            $errors.Add('LAST_UPDATED nie może poprzedzać daty utworzenia project-origin.')
        }
    }
    if (-not (Test-ConcreteNote -Text (Get-MetaValue -Text $meta -Name 'NEXT_ACTION') -MinimumLength 10)) {
        $errors.Add('NEXT_ACTION musi zawierać konkretną następną czynność, nie placeholder.')
    }
}

$verificationPolicy = Get-MetaValue -Text $meta -Name 'VERIFICATION_POLICY'
if ($verificationPolicy -and $verificationPolicy -ne 'SOURCE_FIRST_K4') {
    $errors.Add("Nieprawidłowa VERIFICATION_POLICY: $verificationPolicy. Wymagane SOURCE_FIRST_K4.")
}

$declaredPath = Get-MetaValue -Text $meta -Name 'PROJECT_PATH'
if ($declaredPath) {
    try {
        if (-not [IO.Path]::GetFullPath($declaredPath).Equals($project, [StringComparison]::OrdinalIgnoreCase)) {
            if ($isK1LiteV2Workflow) { $errors.Add('PROJECT_PATH różni się od sprawdzanej ścieżki; sklonowany projekt wymaga jawnego ponownego powiązania, nie cichego PASS.') }
            else { $warnings.Add('PROJECT_PATH różni się od sprawdzanej ścieżki.') }
        }
    } catch { $errors.Add('PROJECT_PATH nie jest prawidłową ścieżką.') }
}

$order = @('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE')
$requiredByStage = [ordered]@{
    'K0' = '00-fundament-projektu.md'
    'K1' = '01-baza-dowodow.md'
    'K2' = '02-architektura-odcinka.md'
    'K3' = '03-draft.md'
    'K4' = '04-raport-qa.md'
    'K5' = '05-FINAL-SCRIPT.md'
}

$stageIndex = [array]::IndexOf($order, $stage)
$resolvedK1Run = $null
$actualK1LedgerHash = ''
$k1PublishReceiptState = $null
$k1FreshGateResults = @()
if ($isK1LiteV2Workflow -and $k1ResearchMode -eq 'MANUAL_APPROVED') {
    foreach ($field in @('K1_RUN_PATH','K1_LEDGER_SHA256','K1_PUBLISH_RECEIPT_PATH','K1_PUBLISH_RECEIPT_SHA256')) {
        if ((Get-MetaValue -Text $meta -Name $field) -ne 'BRAK') { $errors.Add("MANUAL_APPROVED wymaga ${field}: BRAK; automatyczny publish i fallback nie mogą być aktywne jednocześnie.") }
    }
    if ($stageIndex -ge [array]::IndexOf($order,'K1')) {
        $manualFallbackState = Get-K1ManualFallbackReceiptState -ProjectPath $project
        foreach ($manualProblem in @($manualFallbackState.Errors)) { $errors.Add("K1 manual fallback: $manualProblem") }
    }
} elseif ($isK1LiteV2Workflow -and $k1ResearchMode -eq 'K1_LITE_V2' -and $stageIndex -ge 0 -and $stageIndex -lt [array]::IndexOf($order,'K1')) {
    foreach ($field in @('K1_RUN_PATH','K1_LEDGER_SHA256','K1_PUBLISH_RECEIPT_PATH','K1_PUBLISH_RECEIPT_SHA256')) {
        if ((Get-MetaValue -Text $meta -Name $field) -ne 'BRAK') { $errors.Add("Przed K1 pole $field musi mieć BRAK; opublikowany artefakt nie może wyprzedzać etapu.") }
    }
}
if ($isK1LiteV2Workflow -and $stageIndex -ge [array]::IndexOf($order,'K1') -and $k1ResearchMode -eq 'K1_LITE_V2') {
    $exportPathValue = Get-MetaValue -Text $meta -Name 'K1_RUN_PATH'
    $exportHashValue = Get-MetaValue -Text $meta -Name 'K1_LEDGER_SHA256'
    if ([string]::IsNullOrWhiteSpace($exportPathValue) -or $exportPathValue -eq 'BRAK') {
        $errors.Add('K1: brak K1_RUN_PATH; run K1-Lite V2 nie został bezpiecznie skompilowany.')
    } else {
        try {
            $resolvedExport = if ([IO.Path]::IsPathRooted($exportPathValue)) { [IO.Path]::GetFullPath($exportPathValue) } else { [IO.Path]::GetFullPath((Join-Path $project $exportPathValue)) }
            $exportRoot = [IO.Path]::GetFullPath((Join-Path $project '_work\K1\k1-lite-v2'))
            $exportPrefix = $exportRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            if (-not $resolvedExport.StartsWith($exportPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                $errors.Add('K1: K1_RUN_PATH musi wskazywać katalog runu w _work/K1/k1-lite-v2/.')
            } elseif (-not (Test-Path -LiteralPath $resolvedExport -PathType Container)) {
                $errors.Add("K1: zapisany run K1-Lite V2 nie istnieje: $resolvedExport")
            } else {
                $resolvedK1Run = $resolvedExport
                $exportItem = Get-Item -LiteralPath $resolvedExport -Force
                if (($exportItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $errors.Add('K1: run K1-Lite V2 nie może być dowiązaniem ani reparse pointem.') }
                $ledgerFile = Join-Path $resolvedExport 'ledger.jsonl'
                if (-not (Test-Path -LiteralPath $ledgerFile -PathType Leaf)) { $errors.Add('K1: run nie zawiera ledger.jsonl.') }
                $actualExportHash = if (Test-Path -LiteralPath $ledgerFile -PathType Leaf) { (Get-FileHash -LiteralPath $ledgerFile -Algorithm SHA256).Hash } else { '' }
                $actualK1LedgerHash = $actualExportHash
                if ($exportHashValue -notmatch '^[A-Fa-f0-9]{64}$' -or $actualExportHash -ne $exportHashValue.ToUpperInvariant()) {
                    $errors.Add('K1: K1_LEDGER_SHA256 nie odpowiada zachowanemu ledger.jsonl.')
                }
            }
        } catch {
            $errors.Add("K1: nieprawidłowa ścieżka eksportu K1-Lite V2: $($_.Exception.Message)")
        }
    }

    $publishReceiptRelative = Get-MetaValue -Text $meta -Name 'K1_PUBLISH_RECEIPT_PATH'
    $publishReceiptSha256 = Get-MetaValue -Text $meta -Name 'K1_PUBLISH_RECEIPT_SHA256'
    if ([string]::IsNullOrWhiteSpace($publishReceiptRelative) -or $publishReceiptRelative -eq 'BRAK' -or
        [string]::IsNullOrWhiteSpace($publishReceiptSha256) -or $publishReceiptSha256 -eq 'BRAK') {
        $errors.Add('K1: meta.md nie zawiera aktywnego K1 publish receiptu związanego z opublikowaną bazą.')
    } elseif ($resolvedK1Run) {
        try {
            $k1PublishReceiptState = Assert-K1PublishReceiptCurrent `
                -ProjectPath $project `
                -ReceiptRelative $publishReceiptRelative `
                -ExpectedReceiptSha256 $publishReceiptSha256

            $receiptRun = [IO.Path]::GetFullPath((Split-Path -Parent $k1PublishReceiptState.Path))
            if (-not $receiptRun.Equals($resolvedK1Run, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'K1_PUBLISH_RECEIPT_META_RUN_MISMATCH'
            }
            if ([string]$k1PublishReceiptState.Data.publication_ledger_sha256 -ne $actualK1LedgerHash -or
                [string]$k1PublishReceiptState.Data.publication_ledger_sha256 -ne $exportHashValue.ToUpperInvariant()) {
                throw 'K1_PUBLISH_RECEIPT_META_LEDGER_MISMATCH'
            }
            $receiptLedger = Resolve-K1PublishRelativePath `
                -ProjectPath $project `
                -RelativePath ([string]$k1PublishReceiptState.Data.publication_ledger_relative) `
                -Code 'K1_PUBLISH_LEDGER'
            $expectedCurrentLedger = [IO.Path]::GetFullPath((Join-Path $resolvedK1Run 'ledger.jsonl'))
            if (-not $receiptLedger.Equals($expectedCurrentLedger, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'K1_PUBLISH_RECEIPT_META_LEDGER_PATH_MISMATCH'
            }

            $k1EnginePath = Join-Path $PSScriptRoot 'k1-lite-v2\Invoke-K1LiteV2.ps1'
            if (-not (Test-Path -LiteralPath $k1EnginePath -PathType Leaf)) { throw 'K1_VALIDATE_RUN_ENGINE_MISSING' }
            $k1FreshGateResults = @(Invoke-K1FreshLineageGates `
                -EnginePath $k1EnginePath `
                -ProjectPath $project `
                -Lineage @($k1PublishReceiptState.Lineage) `
                -PythonPath $PythonPath)
            if ($k1FreshGateResults.Count -ne @($k1PublishReceiptState.Lineage).Count) {
                throw 'K1_FRESH_LINEAGE_RESULT_COUNT_MISMATCH'
            }
        } catch {
            $errors.Add("K1: publish receipt albo świeża walidacja sześciu bramek jest nieprawidłowa: $($_.Exception.Message)")
            $k1PublishReceiptState = $null
            $k1FreshGateResults = @()
        }
    }
}
if ($isCompactWorkflow -and $stageIndex -ge 0) {
    $w0Decision = Get-MetaValue -Text $meta -Name 'W0_DECISION'
    if ($w0Decision -notin @('GO','GO WARUNKOWE')) { $errors.Add("W0: W0_DECISION musi mieć GO albo GO WARUNKOWE przed przejściem dalej, jest '$w0Decision'.") }
    if ($isK1LiteV2Workflow) {
        $w0Conditions = Get-MetaValue -Text $meta -Name 'W0_CONDITIONS'
        $w0ConditionState = Get-W0ConditionClosureState -ProjectPath $project -MetaText $meta
        foreach ($conditionProblem in @($w0ConditionState.Errors)) { $errors.Add("W0: $conditionProblem") }
        if ($w0Decision -eq 'GO' -and $w0Conditions -ne 'BRAK') {
            $errors.Add("W0: przy decyzji GO pole W0_CONDITIONS musi mieć dokładnie BRAK, jest '$w0Conditions'.")
        }
        if ($w0Decision -eq 'GO WARUNKOWE') {
            $conditionMatch = [regex]::Match([string]$w0Conditions, '^WARUNEK=(?<condition>.{10,});\s*OWNER=(?<owner>.{2,});\s*TERMIN=(?<date>\d{4}-\d{2}-\d{2})$')
            $conditionDate = [datetime]::MinValue
            $dateValid = $conditionMatch.Success -and [datetime]::TryParseExact(
                $conditionMatch.Groups['date'].Value,
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None,
                [ref]$conditionDate
            )
            if (-not $conditionMatch.Success -or -not $dateValid) {
                $errors.Add('W0: GO WARUNKOWE wymaga W0_CONDITIONS w formacie WARUNEK=<min. 10 znaków>; OWNER=<min. 2 znaki>; TERMIN=YYYY-MM-DD.')
            } elseif ($w0ConditionState.Status -eq 'OPEN' -and $conditionDate.Date -lt [datetime]::UtcNow.Date) {
                $errors.Add("W0: TERMIN warunku jest w przeszłości: $($conditionMatch.Groups['date'].Value).")
            }
            if ($stageIndex -ge [array]::IndexOf($order,'K1') -and $w0ConditionState.Status -ne 'CLOSED') {
                $errors.Add('W0: warunek GO WARUNKOWE musi zostać zamknięty aktualnym receiptem Dawida najpóźniej przed zaliczeniem K1.')
            }
        }

        $sourceDir = Join-Path $project 'sources'
        if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
            $errors.Add('W0: brak katalogu sources/.')
        } else {
            $supportedExtensions = @('.pdf','.md','.txt','.srt','.vtt')
            $sourceRootFull = [IO.Path]::GetFullPath($sourceDir)
            $nestedSupported = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                $_.DirectoryName -ne $sourceRootFull -and
                $_.FullName -notmatch '[\\/]_oryginaly(?:[\\/]|$)' -and
                $_.Extension.ToLowerInvariant() -in $supportedExtensions
            })
            foreach ($nestedSource in $nestedSupported) {
                $errors.Add("W0: wspierany plik źródłowy jest w niedozwolonym podfolderze sources/: $($nestedSource.FullName).")
            }
            $activeSourceFiles = @(Get-ChildItem -LiteralPath $sourceDir -File -ErrorAction SilentlyContinue | Where-Object {
                $_.Length -gt 0 -and $_.Extension.ToLowerInvariant() -in $supportedExtensions
            })
            if ($activeSourceFiles.Count -eq 0) {
                $errors.Add('W0: sources/ nie zawiera bezpośrednio aktywnego, niepustego materiału PDF/MD/TXT/SRT/VTT.')
            }
        }
    }
    if ($stage -eq 'W0') {
        $lastGate = Get-MetaValue -Text $meta -Name 'LAST_GATE'
        if ($lastGate -ne 'PROJECT_INITIALIZED') {
            $errors.Add("W0: LAST_GATE pozostaje PROJECT_INITIALIZED do chwili Advance-Stage; jest '$lastGate'.")
        }
    }
}

if ($isK1LiteV2Workflow) {
    $lastGate = Get-MetaValue -Text $meta -Name 'LAST_GATE'
    $expectedGateByStage = @{
        K1='K0_PASS'; K2='K1_PASS'; K2B='K2_PASS'; K3='K2B_PASS'; K4='K3_PASS'; K5='K4_PASS'; COMPLETE='K5_PASS'
    }
    if ($stage -eq 'K0') {
        $allowedW0Gate = if ($w0Decision -eq 'GO') { 'W0_GO' } elseif ($w0Decision -eq 'GO WARUNKOWE') { 'W0_GO_WARUNKOWE' } else { '' }
        if (-not $allowedW0Gate -or $lastGate -ne $allowedW0Gate) { $errors.Add("Stan: K0 wymaga LAST_GATE odpowiadającego decyzji W0 ('$allowedW0Gate'), jest '$lastGate'.") }
    } elseif ($expectedGateByStage.ContainsKey($stage) -and $lastGate -ne $expectedGateByStage[$stage]) {
        $errors.Add("Stan: CURRENT_STAGE $stage wymaga LAST_GATE $($expectedGateByStage[$stage]), jest '$lastGate'.")
    }

    $blockedFrom = Get-MetaValue -Text $meta -Name 'BLOCKED_FROM_STAGE'
    $blockedReason = Get-MetaValue -Text $meta -Name 'BLOCKED_REASON'
    $stateReceiptHead = Get-StateReceiptHeadState -ProjectPath $project -MetaText $meta
    $stateReceiptLabel = if ($stage -eq 'BLOCKED') { 'BLOCKED receipt' } else { 'State receipt' }
    foreach ($stateReceiptProblem in @($stateReceiptHead.Errors)) { $errors.Add("${stateReceiptLabel}: $stateReceiptProblem") }
    if ($stage -eq 'BLOCKED') {
        if ($blockedFrom -notin @('W0','K0','K1','K2','K2B','K3','K4','K5')) { $errors.Add("BLOCKED_FROM_STAGE ma niedozwoloną wartość '$blockedFrom'.") }
        if (-not (Test-ConcreteNote -Text $blockedReason -MinimumLength 12)) { $errors.Add('BLOCKED_REASON musi zawierać konkretny powód blokady.') }
        if ($blockedFrom -eq 'W0') {
            $expectedBlockedW0Gate = if ((Get-MetaValue -Text $meta -Name 'W0_DECISION') -eq 'NO-GO') { 'W0_NO_GO' } else { 'PROJECT_INITIALIZED' }
            if (-not $expectedBlockedW0Gate -or $lastGate -ne $expectedBlockedW0Gate) {
                $errors.Add("BLOCKED z W0 ma niespójną decyzję/bramkę; oczekiwano '$expectedBlockedW0Gate', jest '$lastGate'.")
            }
        } else {
            $entryGateByStage = @{
                K0 = if ((Get-MetaValue -Text $meta -Name 'W0_DECISION') -eq 'GO WARUNKOWE') { 'W0_GO_WARUNKOWE' } else { 'W0_GO' }
                K1='K0_PASS'; K2='K1_PASS'; K2B='K2_PASS'; K3='K2B_PASS'; K4='K3_PASS'; K5='K4_PASS'
            }
            if ($entryGateByStage.ContainsKey($blockedFrom) -and $lastGate -ne $entryGateByStage[$blockedFrom]) {
                $errors.Add("BLOCKED z etapu $blockedFrom wymaga zachowania ostatniej prawdziwej bramki $($entryGateByStage[$blockedFrom]), jest '$lastGate'.")
            }
        }
    } elseif ($blockedFrom -ne 'BRAK' -or $blockedReason -ne 'BRAK') {
        $errors.Add('BLOCKED_FROM_STAGE i BLOCKED_REASON muszą mieć BRAK poza stanem BLOCKED.')
    }
}

if ($isK1LiteV2Workflow -and $ownerMap.ContainsKey($stage)) {
    $handoffOwnerMatches = @([regex]::Matches($meta, '(?m)^- Właściciel:\s*(.*?)\s*$'))
    $handoffTaskMatches = @([regex]::Matches($meta, '(?m)^- Zadanie:\s*(.*?)\s*$'))
    if ($handoffOwnerMatches.Count -ne 1) {
        $errors.Add("AKTYWNY HANDOFF musi mieć dokładnie jeden wpis Właściciel; znaleziono $($handoffOwnerMatches.Count).")
    } elseif ($handoffOwnerMatches[0].Groups[1].Value.Trim() -cne $stageOwner) {
        $errors.Add("AKTYWNY HANDOFF ma właściciela '$($handoffOwnerMatches[0].Groups[1].Value.Trim())', a STAGE_OWNER ma '$stageOwner'.")
    }
    if ($handoffTaskMatches.Count -ne 1) {
        $errors.Add("AKTYWNY HANDOFF musi mieć dokładnie jeden wpis Zadanie; znaleziono $($handoffTaskMatches.Count).")
    } else {
        $handoffTask = $handoffTaskMatches[0].Groups[1].Value.Trim()
        if ($handoffTask -notmatch "^$([regex]::Escape($stage))(?:\s|—|-|$)") {
            $errors.Add("AKTYWNY HANDOFF nie odpowiada CURRENT_STAGE ${stage}: '$handoffTask'.")
        }
    }
}
foreach ($entry in $requiredByStage.GetEnumerator()) {
    $requiredIndex = [array]::IndexOf($order, $entry.Key)
    if ($stageIndex -ge $requiredIndex -and -not (Test-Path -LiteralPath (Join-Path $project $entry.Value) -PathType Leaf)) {
        $errors.Add("Etap $stage wymaga pliku $($entry.Value).")
    }
}

if ($isCompactWorkflow -and $stageIndex -ge [array]::IndexOf($order,'K0')) {
    $foundationPath = Join-Path $project '00-fundament-projektu.md'
    if (Test-Path -LiteralPath $foundationPath -PathType Leaf) {
        $foundation = Get-Content -LiteralPath $foundationPath -Raw -Encoding UTF8
        $foundationStatus = Get-MetaValue -Text $foundation -Name 'STATUS'
        $foundationAgreement = Get-MetaValue -Text $foundation -Name 'ZGODNOŚĆ_Z_W0'
        if ($foundationStatus -ne 'GOTOWY') { $errors.Add("K0: STATUS musi mieć GOTOWY przed K1, jest '$foundationStatus'.") }
        if ($foundationAgreement -notin @('POTWIERDZONA','TAK')) { $errors.Add("K0: ZGODNOŚĆ_Z_W0 musi być potwierdzona przed K1, jest '$foundationAgreement'.") }

        $foundationFields = @('PYTANIE GŁÓWNE','OBIETNICA','KONFLIKT/NAPIĘCIE','W FILMIE','POZA FILMEM','WĄTKI OBOWIĄZKOWE','TRYB RESEARCHU','ZGODA NA WEB','POLITYKA WERYFIKACJI')
        if ($isK1LiteV2Workflow) { $foundationFields += 'TEMAT ANALIZY K1-LITE V2' }
        foreach ($field in $foundationFields) {
            $match = [regex]::Match($foundation, "(?m)^\s*-\s*$([regex]::Escape($field)):\s*(.*?)\s*$")
            $value = if ($match.Success) { $match.Groups[1].Value.Trim() } else { '' }
            if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^NIEUSTALONE$|^DO UZUPEŁNIENIA$|^\[.*\]$') {
                $errors.Add("K0: brak konkretnej wartości pola $field.")
            }
            if ($field -eq 'POLITYKA WERYFIKACJI' -and $value -and $value -ne 'SOURCE_FIRST_K4') {
                $errors.Add("K0: POLITYKA WERYFIKACJI musi mieć SOURCE_FIRST_K4, jest '$value'.")
            }
        }

        if ($isK1LiteV2Workflow) {
            $foundationResearchMode = [regex]::Match($foundation, '(?m)^\s*-\s*TRYB RESEARCHU:\s*(.*?)\s*$').Groups[1].Value.Trim()
            $foundationWebConsent = [regex]::Match($foundation, '(?m)^\s*-\s*ZGODA NA WEB:\s*(.*?)\s*$').Groups[1].Value.Trim()
            $foundationVerdict = [regex]::Match($foundation, '(?m)^\s*-\s*WERDYKT:\s*(.*?)\s*$').Groups[1].Value.Trim()
            $metaResearchMode = Get-MetaValue -Text $meta -Name 'RESEARCH_MODE'
            if ($foundationVerdict -ne 'PASS') {
                $errors.Add("K0: WERDYKT musi mieć dokładnie PASS, jest '$foundationVerdict'.")
            }
            if ($foundationResearchMode -notin @('SOURCES_ONLY','SOURCES_PLUS_WEB_AFTER_CONFIRMATION')) {
                $errors.Add("K0: TRYB RESEARCHU ma niedozwoloną wartość '$foundationResearchMode'.")
            } elseif ($foundationResearchMode -ne $metaResearchMode) {
                $errors.Add("K0: TRYB RESEARCHU '$foundationResearchMode' nie odpowiada RESEARCH_MODE '$metaResearchMode' w meta.md.")
            }
            $expectedWebConsent = switch ($foundationResearchMode) {
                'SOURCES_ONLY' { 'NIE' }
                'SOURCES_PLUS_WEB_AFTER_CONFIRMATION' { 'TYLKO PO POTWIERDZENIU DAWIDA' }
                default { $null }
            }
            if ($expectedWebConsent -and $foundationWebConsent -ne $expectedWebConsent) {
                $errors.Add("K0: dla TRYB RESEARCHU '$foundationResearchMode' pole ZGODA NA WEB musi mieć dokładnie '$expectedWebConsent', jest '$foundationWebConsent'.")
            }
        }

        $foundationGoals = [regex]::Matches($foundation, '(?m)^\|\s*(Q-\d{3,})\s*\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*([^|]*)\|\s*$')
        if ($foundationGoals.Count -lt 4 -or $foundationGoals.Count -gt 8) {
            $errors.Add("K0: wymagane są 4–8 celów badawczych, znaleziono $($foundationGoals.Count).")
        }
        foreach ($duplicate in @($foundationGoals | ForEach-Object { $_.Groups[1].Value }) | Group-Object | Where-Object Count -gt 1) {
            $errors.Add("K0: powtórzony cel badawczy $($duplicate.Name).")
        }
        foreach ($goal in $foundationGoals) {
            foreach ($cellIndex in 2..6) {
                $value = $goal.Groups[$cellIndex].Value.Trim()
                if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^NIEUSTALONE$|^DO UZUPEŁNIENIA$|^\[.*\]$') {
                    $errors.Add("K0: $($goal.Groups[1].Value) ma puste albo pozorne pole celu badawczego.")
                    break
                }
            }
            $priority = $goal.Groups[5].Value.Trim()
            if ($priority -notin @('MUST','OPCJONALNY')) { $errors.Add("K0: $($goal.Groups[1].Value) ma niedozwolony priorytet '$priority'.") }
        }
    }
}

if ($stageIndex -ge [array]::IndexOf($order,'K4')) {
    foreach ($name in @('04-raport-qa.md','04B-fact-check.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $project $name) -PathType Leaf)) { $errors.Add("Etap K4 i późniejsze wymagają pliku kontroli: $name") }
    }
}

$k2b = Get-MetaValue -Text $meta -Name 'K2B_DECISION'
$k2bIndex = [array]::IndexOf($order,'K2B')
$architecture = $null
$architectureDecision = ''
$k2bGapIds = @()
$k2bResolvedCardIds = @()
$k2bUsesExplicitDecision = $false
if ($stageIndex -ge $k2bIndex -and $k2b -notin @('SUPLEMENT WYMAGANY','SUPLEMENT NIEWYMAGANY')) {
    $errors.Add('Bramka K2B wymaga rozstrzygniętego K2B_DECISION.')
}
if ($stageIndex -ge $k2bIndex) {
    $architecturePath = Join-Path $project '02-architektura-odcinka.md'
    if (Test-Path -LiteralPath $architecturePath) {
        $architecture = Get-Content -LiteralPath $architecturePath -Raw -Encoding UTF8
        $architectureDecision = [regex]::Match($architecture,'(?m)^K2B_DECISION:\s*(.*?)\s*$').Groups[1].Value
        $architectureJustification = [regex]::Match($architecture,'(?m)^UZASADNIENIE:\s*(.*?)\s*$').Groups[1].Value
        if (-not $architectureDecision) {
            $errors.Add('Architektura nie ma pola K2B_DECISION.')
        } elseif ($k2b -ne $architectureDecision) {
            $errors.Add("K2B_DECISION różni się między meta ($k2b) i architekturą ($architectureDecision).")
        }
        if ([string]::IsNullOrWhiteSpace($architectureJustification) -or $architectureJustification.Length -lt 15 -or $architectureJustification -match '^BRAK$|^NIEUSTALONE$|^DO UZUPEŁNIENIA$|^\[.*\]$') {
            $errors.Add('K2B: UZASADNIENIE decyzji musi być konkretne i mieć co najmniej 15 znaków.')
        }
        if ($architectureDecision -eq 'SUPLEMENT WYMAGANY') {
            $gapRows = [regex]::Matches($architecture, '(?m)^\|\s*(L-\d{3,})\s*\|(.*?)\|\s*$')
            if ($gapRows.Count -eq 0) { $errors.Add('K2B: SUPLEMENT WYMAGANY nie ma kompletnego wiersza luki L-...') }
            $gapIds = @()
            $knownK2BCards = @()
            $k2bBasePath = Join-Path $project '01-baza-dowodow.md'
            if (Test-Path -LiteralPath $k2bBasePath -PathType Leaf) {
                $knownK2BCards = @([regex]::Matches((Get-Content -LiteralPath $k2bBasePath -Raw -Encoding UTF8), '(?m)^###\s+(#P-\d{3,})\s*$') | ForEach-Object { $_.Groups[1].Value })
            }
            foreach ($gap in $gapRows) {
                $cells = @(("$($gap.Groups[1].Value)|$($gap.Groups[2].Value)").Split('|') | ForEach-Object { $_.Trim() })
                $gapIds += $cells[0]
                if ($cells.Count -lt 8) { $errors.Add("K2B: luka '$($cells[0])' ma mniej niż 8 kolumn."); continue }
                foreach ($index in 1..7) {
                    if ([string]::IsNullOrWhiteSpace($cells[$index]) -or $cells[$index] -match '^BRAK$|^NIEUSTALONE$|^DO UZUPEŁNIENIA$|^\[.*\]$') {
                        $errors.Add("K2B: luka '$($cells[0])' ma puste albo pozorne pole w kolumnie $($index + 1).")
                    }
                }
                if ($isK1LiteV2Workflow) {
                    $resultCell = $cells[7]
                    $resultCardIds = @([regex]::Matches($resultCell, '#P-\d{3,}') | ForEach-Object Value | Select-Object -Unique)
                    if ($resultCardIds.Count -gt 0) {
                        $k2bResolvedCardIds += $resultCardIds
                        foreach ($resultCardId in $resultCardIds) {
                            if ($resultCardId -notin $knownK2BCards) {
                                $errors.Add("K2B: wynik luki '$($cells[0])' wskazuje nieistniejącą kartę $resultCardId w aktualnej 01-baza-dowodow.md.")
                            }
                        }
                    } elseif ($resultCell -match '^(?i:DECYZJA:\s*(?:ZMIANA[_ ]ARCHITEKTURY|LUKA[_ ]JAWNA))(?:\s*(?:;|—|-)\s*.+)?$') {
                        $k2bUsesExplicitDecision = $true
                    } else {
                        $errors.Add("K2B: wynik luki '$($cells[0])' musi wskazywać istniejące #P albo jawną decyzję 'DECYZJA: ZMIANA_ARCHITEKTURY' / 'DECYZJA: LUKA_JAWNA'.")
                    }
                }
            }
            foreach ($duplicate in $gapIds | Group-Object | Where-Object Count -gt 1) { $errors.Add("K2B: powtórzone ID luki '$($duplicate.Name)'.") }
            $k2bGapIds = @($gapIds)

            if ($isK1LiteV2Workflow) {
                $currentLedgerHash = Get-MetaValue -Text $meta -Name 'K1_LEDGER_SHA256'
                $k2bChangelogLines = @([regex]::Matches($architecture, '(?m)^\s*-\s*K2B:\s*(.*?)\s*$') | ForEach-Object { $_.Groups[1].Value.Trim() })
                $currentK2BReceipt = @($k2bChangelogLines | Where-Object {
                    $currentLedgerHash -match '^[A-Fa-f0-9]{64}$' -and $_.IndexOf($currentLedgerHash, [StringComparison]::OrdinalIgnoreCase) -ge 0
                }) | Select-Object -First 1
                if (-not $currentK2BReceipt) {
                    $errors.Add('K2B: changelog musi zawierać wpis "- K2B:" z aktualnym K1_LEDGER_SHA256.')
                } else {
                    $receiptHasKnownId = $false
                    foreach ($receiptId in @($k2bGapIds) + @($k2bResolvedCardIds)) {
                        if ($receiptId -and $currentK2BReceipt -match "(?<![A-Z0-9-])$([regex]::Escape($receiptId))(?![A-Z0-9-])") {
                            $receiptHasKnownId = $true
                            break
                        }
                    }
                    if (-not $receiptHasKnownId -and $currentK2BReceipt -notmatch '(?i)\bZAKRES\s*=\s*[^;,\r\n]{3,}') {
                        $errors.Add('K2B: aktualny wpis changelogu musi wskazywać zakres (ZAKRES=...) albo ID rozwiązanej luki/karty.')
                    }
                }
            }
        }
    }
}
$legacy = Get-ChildItem -LiteralPath $project -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $isK1LiteTechnicalQa = $_.FullName -match '(?i)[\\/]_work[\\/]K1[\\/]k1-lite-v2[\\/].+[\\/]qa[\\/]'
    $_.Name -match '(?i)draft[-_ ]?v\d|final[-_ ]?v\d|master[-_ ]?lista|ostateczna[-_ ]kontrola' -or
    ($_.FullName -match '[\\/]QA[\\/]' -and -not $isK1LiteTechnicalQa)
}
foreach ($file in $legacy) { $errors.Add("Niedozwolony artefakt starego systemu: $($file.FullName)") }

$draftPath = Join-Path $project '03-draft.md'
$qaPath = Join-Path $project '04-raport-qa.md'
$fcPath = Join-Path $project '04B-fact-check.md'
if ((Test-Path -LiteralPath $draftPath) -and (Test-Path -LiteralPath $qaPath)) {
    $draft = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
    $qa = Get-Content -LiteralPath $qaPath -Raw -Encoding UTF8
    $draftRev = [regex]::Match($draft,'(?m)^CONTENT_REVISION:\s*(\S+)').Groups[1].Value
    $qaRev = [regex]::Match($qa,'(?m)^DRAFT_REVISION:\s*(\S+)').Groups[1].Value
    $qaHash = ''
    $leadAgent = ''
    if ($stageIndex -ge [array]::IndexOf($order,'K4')) {
        if (-not $draftRev) { $errors.Add('K4: draft nie ma CONTENT_REVISION.') }
        if (-not $qaRev) { $errors.Add('K4: raport QA nie ma DRAFT_REVISION.') }
        if ($draftRev -and $qaRev -and $draftRev -ne $qaRev) { $errors.Add("K4: QA dotyczy rewizji $qaRev, a draft ma rewizję $draftRev.") }
        $qaVerdict = [regex]::Match($qa,'(?m)^AKTUALNY_WERDYKT:\s*(.*?)\s*$').Groups[1].Value
        if ($isCompactWorkflow -and $qaVerdict -ne 'GOTOWE DO K5') { $errors.Add("K4: raport QA musi mieć AKTUALNY_WERDYKT: GOTOWE DO K5, jest '$qaVerdict'.") }
        elseif (-not $isCompactWorkflow -and ([string]::IsNullOrWhiteSpace($qaVerdict) -or $qaVerdict -eq 'NIEURUCHOMIONY')) { $errors.Add('K4 legacy: raport QA nie ma zakończonego werdyktu.') }
        if ($isCompactWorkflow) {
            $qaHash = [regex]::Match($qa,'(?m)^DRAFT_SHA256:\s*(\S+)').Groups[1].Value
            $leadAgent = [regex]::Match($qa,'(?m)^LEAD_AGENT_ID:\s*(\S+)').Groups[1].Value
            $openQ0 = Get-MetaValue -Text $qa -Name 'OPEN_Q0'
            $openQ1Unapproved = Get-MetaValue -Text $qa -Name 'OPEN_Q1_UNAPPROVED'
            if (-not $qaHash) { $errors.Add('K4: raport QA nie ma DRAFT_SHA256.') }
            if (-not $leadAgent) { $errors.Add('K4: raport QA nie ma LEAD_AGENT_ID.') }
            $openQ0Number = -1
            $openQ1UnapprovedNumber = -1
            if (-not [int]::TryParse($openQ0, [ref]$openQ0Number) -or $openQ0Number -ne 0) { $errors.Add("K4: OPEN_Q0 musi wynosić 0, jest '$openQ0'.") }
            if (-not [int]::TryParse($openQ1Unapproved, [ref]$openQ1UnapprovedNumber) -or $openQ1UnapprovedNumber -ne 0) { $errors.Add("K4: OPEN_Q1_UNAPPROVED musi wynosić 0, jest '$openQ1Unapproved'.") }
            $baselineMarker = Get-MetaValue -Text $draft -Name 'BASELINE_FOR_QA'
            $changeScope = Get-MetaValue -Text $draft -Name 'CHANGE_SCOPE_PERCENT'
            $baselinePath = Join-Path $project '_work\qa-baseline.md'
            if ($baselineMarker -ne '_work/qa-baseline.md' -or -not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) {
                $errors.Add('K4: brak niezmiennego baseline QA w _work/qa-baseline.md albo BASELINE_FOR_QA nie wskazuje go dokładnie.')
            }

            $changeScopeNumber = -1.0
            $parsedScope = [double]::TryParse($changeScope, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$changeScopeNumber)
            if (-not $parsedScope) { $parsedScope = [double]::TryParse($changeScope, [ref]$changeScopeNumber) }
            if (-not $parsedScope -or $changeScopeNumber -lt 0 -or $changeScopeNumber -gt 20) {
                $errors.Add("K4: CHANGE_SCOPE_PERCENT musi mieścić się w 0–20 po aktualnym pełnym przebiegu K4, jest '$changeScope'.")
            }
            try {
                $measuredScope = & (Join-Path $PSScriptRoot 'Compare-Draft.ps1') -ProjectPath $project
                if ($parsedScope -and [Math]::Abs($changeScopeNumber - [double]$measuredScope.ChangeScopePercent) -gt 0.05) {
                    $errors.Add("K4: CHANGE_SCOPE_PERCENT '$changeScope' nie odpowiada pomiarowi $($measuredScope.ChangeScopePercent).")
                }
                if ([double]$measuredScope.ChangeScopePercent -gt 20) {
                    $errors.Add("K4: rzeczywisty zakres zmiany $($measuredScope.ChangeScopePercent)% przekracza 20%; wymagany pełny nowy K4 i baseline.")
                }
            } catch {
                $errors.Add("K4: baseline QA lub jego receipt jest nieprawidłowy: $($_.Exception.Message)")
            }

            if ($requiresIntegrityReceipts) {
                foreach ($section in @(
                    @('Podsumowanie','Podsumowanie\b',6,35),
                    @('A','A\.\s+Zgodność[^\r\n]*',4,20),
                    @('B','B\.\s+Architektura[^\r\n]*',4,20),
                    @('C','C\.\s+Retencja[^\r\n]*',4,20),
                    @('D','D\.\s+Język[^\r\n]*',4,20)
                )) {
                    $body = Get-MarkdownSectionBody -Text $qa -HeadingPattern $section[1]
                    if (-not (Test-SubstantiveMarkdown -Text $body -MinimumWords $section[2] -MinimumCharacters $section[3])) {
                        $errors.Add("K4: sekcja QA '$($section[0])' nie zawiera konkretnego wyniku kontroli.")
                    }
                }
                $summaryBody = Get-MarkdownSectionBody -Text $qa -HeadingPattern 'Podsumowanie\b'
                foreach ($summaryField in @('Q0','Q1','Q2','Największe ryzyko')) {
                    $summaryValue = [regex]::Match([string]$summaryBody, "(?m)^\s*[-*]\s*$([regex]::Escape($summaryField)):\s*(.+?)\s*$").Groups[1].Value
                    if (-not (Test-ConcreteTableCell -Text $summaryValue -MinimumLength 4)) {
                        $errors.Add("K4: Podsumowanie QA nie ma konkretnej wartości '$summaryField'.")
                    }
                }

                $qaRegistry = Get-MarkdownSectionBody -Text $qa -HeadingPattern 'Rejestr\b'
                $qaRows = [Collections.Generic.List[object]]::new()
                foreach ($line in @([regex]::Split([string]$qaRegistry, '\r?\n'))) {
                    $cells = @(ConvertFrom-MarkdownTableRow -Line $line)
                    if ($cells.Count -eq 0 -or $cells[0] -in @('ID','---') -or $cells[0] -match '^:?-+:?$') { continue }
                    if ($cells.Count -ne 8) { $errors.Add("K4: nieprawidłowy wiersz rejestru QA (wymagane 8 kolumn): $line"); continue }
                    $qaRows.Add($cells)
                }
                if ($qaRows.Count -eq 0) { $errors.Add('K4: rejestr QA musi zawierać co najmniej jeden rzeczywisty wiersz.') }
                $seenQaIds = @{}
                $actualOpenQ0 = 0
                $actualOpenQ1 = 0
                foreach ($cells in $qaRows) {
                    if ($cells[0] -notmatch '^QA-\d{3,}$' -or $seenQaIds.ContainsKey($cells[0])) { $errors.Add("K4: ID rejestru QA jest nieprawidłowe lub powtórzone: '$($cells[0])'.") } else { $seenQaIds[$cells[0]] = $true }
                    if ($cells[1] -notin @('Q0','Q1','Q2')) { $errors.Add("K4: niedozwolony priorytet QA '$($cells[1])' w $($cells[0]).") }
                    foreach ($index in 2..6) { if (-not (Test-ConcreteTableCell -Text $cells[$index])) { $errors.Add("K4: $($cells[0]) ma pustą lub pozorną kolumnę $($index + 1).") } }
                    if ($cells[7] -notin @('OPEN','ZAMKNIĘTY','ZAAKCEPTOWANY_PRZEZ_DAWIDA')) { $errors.Add("K4: niedozwolony status QA '$($cells[7])' w $($cells[0]).") }
                    if ($cells[1] -eq 'Q0' -and $cells[7] -eq 'ZAAKCEPTOWANY_PRZEZ_DAWIDA') { $errors.Add("K4: Q0 nie może zostać zaakceptowane zamiast zamknięcia: $($cells[0]).") }
                    if ($cells[1] -in @('Q1','Q2') -and $cells[7] -eq 'ZAAKCEPTOWANY_PRZEZ_DAWIDA') {
                        $exceptionType = "K4_$($cells[1])_ACCEPTANCE"
                        $exceptionState = Get-EditorialExceptionReceiptState -ProjectPath $project -ExceptionType $exceptionType `
                            -ArtifactPath $qaPath -TargetId $cells[0] -ExpectedDecision "ACCEPT_$($cells[1])" -ExpectedScope "QA_$($cells[1])"
                        foreach ($problem in @($exceptionState.Errors)) { $errors.Add("K4: wyjątek $($cells[1]) $($cells[0]): $problem") }
                    }
                    if ($cells[7] -eq 'OPEN' -and $cells[1] -eq 'Q0') { $actualOpenQ0++ }
                    if ($cells[7] -eq 'OPEN' -and $cells[1] -eq 'Q1') { $actualOpenQ1++ }
                }
                if ($openQ0Number -ge 0 -and $openQ0Number -ne $actualOpenQ0) { $errors.Add("K4: OPEN_Q0 nie odpowiada rejestrowi (deklaracja $openQ0Number, pomiar $actualOpenQ0).") }
                if ($openQ1UnapprovedNumber -ge 0 -and $openQ1UnapprovedNumber -ne $actualOpenQ1) { $errors.Add("K4: OPEN_Q1_UNAPPROVED nie odpowiada rejestrowi (deklaracja $openQ1UnapprovedNumber, pomiar $actualOpenQ1).") }

                $qaDate = Get-MetaValue -Text $qa -Name 'DATE'
                $qaWordCount = Get-MetaValue -Text $qa -Name 'WORD_COUNT_VERIFIED'
                if ([string]::IsNullOrWhiteSpace($qaDate)) { $errors.Add('K4: raport QA nie ma DATE.') }
                try {
                    $draftMeasurement = & (Join-Path $PSScriptRoot 'Measure-Script.ps1') -ScriptPath $draftPath -ProjectPath $project
                    $qaWordCountNumber = -1
                    if (-not [int]::TryParse($qaWordCount, [ref]$qaWordCountNumber) -or $qaWordCountNumber -ne $draftMeasurement.WordCount) {
                        $errors.Add("K4: WORD_COUNT_VERIFIED '$qaWordCount' nie odpowiada pomiarowi $($draftMeasurement.WordCount).")
                    }
                } catch { $errors.Add("K4: nie udało się sprawdzić WORD_COUNT_VERIFIED: $($_.Exception.Message)") }
            }
        }
    }
    if ($stageIndex -ge [array]::IndexOf($order,'K4') -and (Test-Path -LiteralPath $fcPath)) {
        $fc = Get-Content -LiteralPath $fcPath -Raw -Encoding UTF8
        $fcRev = [regex]::Match($fc,'(?m)^DRAFT_REVISION:\s*(\S+)').Groups[1].Value
        if (-not $fcRev) { $errors.Add('K4: fact-check nie ma DRAFT_REVISION.') }
        if ($draftRev -and $fcRev -and $draftRev -ne $fcRev) { $errors.Add("K4: fact-check dotyczy rewizji $fcRev, a draft ma rewizję $draftRev.") }
        $fcVerdict = [regex]::Match($fc,'(?m)^AKTUALNY_WERDYKT:\s*(.*?)\s*$').Groups[1].Value
        if ($isCompactWorkflow -and $fcVerdict -ne 'GOTOWE DO K5') { $errors.Add("K4: fact-check musi mieć AKTUALNY_WERDYKT: GOTOWE DO K5, jest '$fcVerdict'.") }
        elseif (-not $isCompactWorkflow -and ([string]::IsNullOrWhiteSpace($fcVerdict) -or $fcVerdict -eq 'NIEURUCHOMIONY')) { $errors.Add('K4 legacy: fact-check nie ma zakończonego werdyktu.') }
        if ($isCompactWorkflow) {
            $actualHash = (Get-FileHash -LiteralPath $draftPath -Algorithm SHA256).Hash
            $qaHash = [regex]::Match($qa,'(?m)^DRAFT_SHA256:\s*(\S+)').Groups[1].Value
            $fcHash = [regex]::Match($fc,'(?m)^DRAFT_SHA256:\s*(\S+)').Groups[1].Value
            $verifyAgent = [regex]::Match($fc,'(?m)^VERIFY_AGENT_ID:\s*(\S+)').Groups[1].Value
            $verifyTask = [regex]::Match($fc,'(?m)^VERIFY_TASK_ID:\s*(\S+)').Groups[1].Value
            $noK3 = [regex]::Match($fc,'(?m)^BRAK_UDZIAŁU_W_K3:\s*(.*?)\s*$').Groups[1].Value
            $sourcesAvailable = [regex]::Match($fc,'(?m)^ŹRÓDŁA_DOSTĘPNE:\s*(.*?)\s*$').Groups[1].Value
            if (-not $fcHash) { $errors.Add('K4: fact-check nie ma DRAFT_SHA256.') }
            if ($qaHash -and $actualHash -and $qaHash -ne $actualHash) { $errors.Add('K4: DRAFT_SHA256 raportu QA nie odpowiada aktualnemu draftowi.') }
            if ($fcHash -and $actualHash -and $fcHash -ne $actualHash) { $errors.Add('K4: DRAFT_SHA256 fact-checku nie odpowiada aktualnemu draftowi.') }
            if (-not $verifyAgent) { $errors.Add('K4: fact-check nie ma VERIFY_AGENT_ID.') }
            if ($leadAgent -and $verifyAgent -and $leadAgent -eq $verifyAgent) { $errors.Add('K4: LEAD_AGENT_ID i VERIFY_AGENT_ID muszą wskazywać różne konteksty.') }
            if ($noK3 -ne 'TAK') { $errors.Add('K4: fact-checker nie potwierdził BRAK_UDZIAŁU_W_K3: TAK.') }
            if ($sourcesAvailable -ne 'TAK') { $errors.Add('K4: fact-check wymaga ŹRÓDŁA_DOSTĘPNE: TAK.') }

            if ($requiresIntegrityReceipts) {
                if ($verifyTask.Trim().Length -lt 8) { $errors.Add('K4: fact-check nie ma konkretnego VERIFY_TASK_ID (minimum 8 znaków).') }
                $fcRegistry = Get-MarkdownSectionBody -Text $fc -HeadingPattern 'Rejestr\b'
                $fcRows = [Collections.Generic.List[object]]::new()
                foreach ($line in @([regex]::Split([string]$fcRegistry, '\r?\n'))) {
                    $cells = @(ConvertFrom-MarkdownTableRow -Line $line)
                    if ($cells.Count -eq 0 -or $cells[0] -in @('ID','---') -or $cells[0] -match '^:?-+:?$') { continue }
                    if ($cells.Count -ne 8) { $errors.Add("K4: nieprawidłowy wiersz fact-checku (wymagane 8 kolumn): $line"); continue }
                    $fcRows.Add($cells)
                }
                if ($fcRows.Count -eq 0) { $errors.Add('K4: fact-check musi zawierać co najmniej jeden rzeczywisty wiersz.') }
                $allowedFcStatuses = @('POTWIERDZONE','CZĘŚCIOWO','ZGODNE ZE ŹRÓDŁEM — NIEZWERYFIKOWANE','SPRZECZNE','NIEZGODNE ZE ŹRÓDŁEM','NIE DOTYCZY')
                $seenFcIds = @{}
                $coveredCards = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($cells in $fcRows) {
                    if ($cells[0] -notmatch '^FC-\d{3,}$' -or $seenFcIds.ContainsKey($cells[0])) { $errors.Add("K4: ID fact-checku jest nieprawidłowe lub powtórzone: '$($cells[0])'.") } else { $seenFcIds[$cells[0]] = $true }
                    foreach ($index in 1..4) { if (-not (Test-ConcreteTableCell -Text $cells[$index])) { $errors.Add("K4: $($cells[0]) ma pustą lub pozorną kolumnę $($index + 1).") } }
                    if ($cells[5] -notin $allowedFcStatuses) { $errors.Add("K4: niedozwolony status fact-checku '$($cells[5])' w $($cells[0]).") }
                    foreach ($cardMatch in [regex]::Matches($cells[3], '#P-\d{3,}')) { $null = $coveredCards.Add($cardMatch.Value) }
                    if ($cells[5] -in @('SPRZECZNE','NIEZGODNE ZE ŹRÓDŁEM')) {
                        if ($cells[7] -notmatch '^(?:POPRAWIONE:\s*.{12,}|DAWID=TAK;\s*DECYZJA=.{12,})$') {
                            $errors.Add("K4: wynik '$($cells[5])' w $($cells[0]) wymaga jawnego rozstrzygnięcia POPRAWIONE:<opis> albo DAWID=TAK; DECYZJA=<opis>.")
                        } elseif ($cells[7] -match '^DAWID=TAK;\s*DECYZJA=(?<decision>.{12,})$') {
                            $factDecision = $Matches['decision'].Trim()
                            $exceptionState = Get-EditorialExceptionReceiptState -ProjectPath $project -ExceptionType 'K4_FACTCHECK_DECISION' `
                                -ArtifactPath $fcPath -TargetId $cells[0] -ExpectedDecision $factDecision -ExpectedScope 'FACTCHECK_EXCEPTION'
                            foreach ($problem in @($exceptionState.Errors)) { $errors.Add("K4: wyjątek fact-check $($cells[0]): $problem") }
                        }
                    } elseif (-not (Test-ConcreteTableCell -Text $cells[7])) {
                        $errors.Add("K4: $($cells[0]) nie ma jawnego rozstrzygnięcia (użyj NIE DOTYCZY, jeśli korekta nie jest potrzebna).")
                    }
                    if (-not (Test-ConcreteTableCell -Text $cells[6])) { $errors.Add("K4: $($cells[0]) nie ma konkretnej minimalnej korekty lub adnotacji NIE DOTYCZY.") }
                }
                $draftPartsForFactCheck = [regex]::Split($draft, '(?m)^---\s*$')
                $draftNarrationForFactCheck = if ($draftPartsForFactCheck.Count -gt 1) { ($draftPartsForFactCheck | Select-Object -Skip 1) -join "`n" } else { $draft }
                $draftCards = @([regex]::Matches($draftNarrationForFactCheck, '#P-\d{3,}') | ForEach-Object Value | Select-Object -Unique)
                foreach ($draftCard in $draftCards) {
                    if (-not $coveredCards.Contains($draftCard)) { $errors.Add("K4: fact-check nie obejmuje użytej w drafcie karty $draftCard.") }
                }
                $qaFactCheckRevision = Get-MetaValue -Text $qa -Name 'FACTCHECK_REVISION'
                if ($qaFactCheckRevision -ne $fcRev) { $errors.Add("K4: FACTCHECK_REVISION raportu QA '$qaFactCheckRevision' nie odpowiada fact-checkowi '$fcRev'.") }

                $k4ReceiptState = Get-K4VerifyReceiptState -ProjectPath $project
                foreach ($receiptError in @($k4ReceiptState.Errors)) { $errors.Add("K4: brak świeżego receiptu VERIFY: $receiptError") }
            }
        }
    }
}

if ($stageIndex -ge [array]::IndexOf($order,'K5')) {
    $finalPath = Join-Path $project '05-FINAL-SCRIPT.md'
    if (Test-Path -LiteralPath $finalPath) {
        $final = Get-Content -LiteralPath $finalPath -Raw -Encoding UTF8
        $finalStatus = [regex]::Match($final,'(?m)^STATUS:\s*(.*?)\s*$').Groups[1].Value
        if ($finalStatus -ne 'ZATWIERDZONY') { $errors.Add('Bramka K5 wymaga 05-FINAL-SCRIPT.md ze STATUS: ZATWIERDZONY.') }
        if ($isCompactWorkflow) {
            $sourceDraftRevision = Get-MetaValue -Text $final -Name 'SOURCE_DRAFT_REVISION'
            $sourceDraftHash = Get-MetaValue -Text $final -Name 'SOURCE_DRAFT_SHA256'
            $sourceQaHash = Get-MetaValue -Text $final -Name 'SOURCE_QA_SHA256'
            $sourceFactCheckHash = Get-MetaValue -Text $final -Name 'SOURCE_FACTCHECK_SHA256'
            $finalDate = Get-MetaValue -Text $final -Name 'DATE'
            $finalWordCount = Get-MetaValue -Text $final -Name 'FINAL_WORD_COUNT'
            $finalWpm = Get-MetaValue -Text $final -Name 'REAL_WPM'
            $finalDuration = Get-MetaValue -Text $final -Name 'ESTIMATED_DURATION'
            if (-not $finalDate) { $errors.Add('K5: final nie ma DATE.') }
            if ($final -match '\[FINALNY TEKST') { $errors.Add('K5: final zawiera placeholder zamiast tekstu do nagrania.') }
            if ($final -match '#P-\d{3,}') { $errors.Add('K5: final zawiera techniczny ślad #P; usuń go z tekstu do nagrania.') }
            if (Test-Path -LiteralPath $draftPath -PathType Leaf) {
                $currentDraftRevision = Get-MetaValue -Text (Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8) -Name 'CONTENT_REVISION'
                if (-not $sourceDraftRevision -or $sourceDraftRevision -ne $currentDraftRevision) { $errors.Add("K5: SOURCE_DRAFT_REVISION '$sourceDraftRevision' nie odpowiada draftowi '$currentDraftRevision'.") }
            }
            if ($requiresIntegrityReceipts) {
                foreach ($binding in @(
                    @('SOURCE_DRAFT_SHA256', $sourceDraftHash, $draftPath),
                    @('SOURCE_QA_SHA256', $sourceQaHash, $qaPath),
                    @('SOURCE_FACTCHECK_SHA256', $sourceFactCheckHash, $fcPath)
                )) {
                    if (-not (Test-Path -LiteralPath $binding[2] -PathType Leaf)) { continue }
                    $actualBindingHash = (Get-FileHash -LiteralPath $binding[2] -Algorithm SHA256).Hash
                    if ($binding[1] -notmatch '^[A-Fa-f0-9]{64}$' -or $binding[1].ToUpperInvariant() -ne $actualBindingHash) {
                        $errors.Add("K5: $($binding[0]) nie odpowiada aktualnemu plikowi '$([IO.Path]::GetFileName($binding[2]))'.")
                    }
                }
                $k5ReceiptState = Get-K5ApprovalReceiptState -ProjectPath $project
                foreach ($receiptError in @($k5ReceiptState.Errors)) { $errors.Add("K5: brak świeżego receiptu zatwierdzenia Dawida: $receiptError") }
            }
            try {
                $finalMeasurement = & (Join-Path $PSScriptRoot 'Measure-Script.ps1') -ScriptPath $finalPath -ProjectPath $project
                if ($finalMeasurement.WordCount -lt 25) { $errors.Add("K5: final ma tylko $($finalMeasurement.WordCount) słów narracji.") }
                $finalCountNumber = 0
                if (-not [int]::TryParse($finalWordCount, [ref]$finalCountNumber) -or $finalCountNumber -ne $finalMeasurement.WordCount) { $errors.Add("K5: FINAL_WORD_COUNT '$finalWordCount' nie odpowiada pomiarowi $($finalMeasurement.WordCount).") }
                $finalWpmNumber = 0.0
                if (-not [double]::TryParse($finalWpm, [ref]$finalWpmNumber) -or $finalWpmNumber -ne $finalMeasurement.WordsPerMinute) { $errors.Add("K5: REAL_WPM '$finalWpm' nie odpowiada pomiarowi $($finalMeasurement.WordsPerMinute).") }
                if ($finalDuration -ne $finalMeasurement.Duration) { $errors.Add("K5: ESTIMATED_DURATION '$finalDuration' nie odpowiada pomiarowi $($finalMeasurement.Duration).") }
            } catch {
                $errors.Add("K5: nie udało się zmierzyć finalu: $($_.Exception.Message)")
            }
        } else {
            $warnings.Add('K5 ma starszy schemat; zachowano historyczny final i sprawdzono tylko STATUS: ZATWIERDZONY.')
        }
    }
}

$evidenceResult = $null
if ($stageIndex -ge [array]::IndexOf($order,'K1')) {
    $sourceDir = Join-Path $project 'sources'
    $sourceCount = if (Test-Path -LiteralPath $sourceDir) { @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File -ErrorAction SilentlyContinue).Count } else { 0 }
    if ($sourceCount -eq 0) { $warnings.Add('Projekt jest na K1 lub dalej, ale sources/ nie zawiera plików.') }

    $evidenceValidator = Join-Path $PSScriptRoot 'Validate-EvidenceBase.ps1'
    if (Test-Path -LiteralPath $evidenceValidator -PathType Leaf) {
        try {
            $evidenceResult = & $evidenceValidator -ProjectPath $project -NoExit
            if ($evidenceResult.Schema -in $compactSchemas) {
                foreach ($detail in @($evidenceResult.ErrorDetails)) { $errors.Add("K1: $detail") }
                foreach ($detail in @($evidenceResult.WarningDetails)) { $warnings.Add("K1: $detail") }
                if (-not $evidenceResult.GateReady) { $errors.Add('K1 nie ma GATE_READY: wymagane są PASS struktury, wierności, nasycenia i werdykt GOTOWE_DO_K2.') }
                if ($evidenceResult.Schema -in @('MINIMAL_EVIDENCE_V3','MINIMAL_EVIDENCE_V4_PAGELOC') -and $evidenceResult.ManualCheckCards -ne 0) { $errors.Add("K1 ma $($evidenceResult.ManualCheckCards) kart bez potwierdzenia maszynowego; K2 wymaga ManualCheckCards: 0.") }
                if ($evidenceSchema -in $compactSchemas -and $evidenceResult.Schema -ne $evidenceSchema) {
                    $errors.Add("meta.md deklaruje $evidenceSchema, ale 01-baza-dowodow.md ma K1_SCHEMA: $($evidenceResult.Schema).")
                }
                if ($isK1LiteV2Workflow -and $k1ResearchMode -eq 'K1_LITE_V2' -and (Test-Path -LiteralPath (Join-Path $project '01-baza-dowodow.md') -PathType Leaf)) {
                    $canonicalK1 = Get-Content -LiteralPath (Join-Path $project '01-baza-dowodow.md') -Raw -Encoding UTF8
                    $baseExportPath = Get-MetaValue -Text $canonicalK1 -Name 'K1_EXPORT_PATH'
                    $baseExportHash = Get-MetaValue -Text $canonicalK1 -Name 'K1_EXPORT_SHA256'
                    $metaExportPath = Get-MetaValue -Text $meta -Name 'K1_RUN_PATH'
                    $metaExportHash = Get-MetaValue -Text $meta -Name 'K1_LEDGER_SHA256'
                    $expectedLedgerPath = if ([IO.Path]::IsPathRooted($metaExportPath)) { Join-Path $metaExportPath 'ledger.jsonl' } else { Join-Path (Join-Path $project $metaExportPath) 'ledger.jsonl' }
                    $resolvedBaseExport = if ([IO.Path]::IsPathRooted($baseExportPath)) { [IO.Path]::GetFullPath($baseExportPath) } else { [IO.Path]::GetFullPath((Join-Path $project $baseExportPath)) }
                    if ($resolvedBaseExport -ne [IO.Path]::GetFullPath($expectedLedgerPath)) { $errors.Add('K1: K1_EXPORT_PATH w bazie nie wskazuje ledger.jsonl zapisanego runu z meta.md.') }
                    if ($baseExportHash -ne $metaExportHash) { $errors.Add('K1: K1_EXPORT_SHA256 w bazie różni się od K1_LEDGER_SHA256 w meta.md.') }
                }
            } elseif ($isCompactWorkflow) {
                $errors.Add("meta.md deklaruje $evidenceSchema, ale 01-baza-dowodow.md nie ma zgodnego K1_SCHEMA.")
            } else {
                $warnings.Add('K1 ma starszy schemat; walidator nie potwierdza integralności kart. Nie cofaj ukończonego projektu tylko z tego powodu.')
            }
        } catch {
            $errors.Add("Nie udało się zwalidować K1: $($_.Exception.Message)")
        }
    } else {
        $errors.Add('Brak narzędzia Validate-EvidenceBase.ps1.')
    }
}

$architectureResult = $null
if ($isCompactWorkflow -and $stageIndex -ge [array]::IndexOf($order,'K2')) {
    $architectureValidator = Join-Path $PSScriptRoot 'Validate-Architecture.ps1'
    if (-not (Test-Path -LiteralPath $architectureValidator -PathType Leaf)) {
        $errors.Add('Brak narzędzia Validate-Architecture.ps1.')
    } else {
        try {
            $architectureResult = & $architectureValidator -ProjectPath $project -NoExit
            foreach ($detail in @($architectureResult.ErrorDetails)) { $errors.Add("K2: $detail") }
            foreach ($detail in @($architectureResult.WarningDetails)) { $warnings.Add("K2: $detail") }
            if (-not $architectureResult.GateReady) { $errors.Add('K2 nie ma ARCHITECTURE_PASS.') }
        } catch {
            $errors.Add("Nie udało się zwalidować K2: $($_.Exception.Message)")
        }
    }
}

if ($isK1LiteV2Workflow -and $stageIndex -ge $k2bIndex -and $architectureDecision -eq 'SUPLEMENT WYMAGANY') {
    if ($k1PublishReceiptState -and [string]$k1PublishReceiptState.Data.publication_kind -ne 'SUPPLEMENT') {
        $errors.Add("K2B: SUPLEMENT WYMAGANY wymaga aktualnego publish receiptu typu SUPPLEMENT, jest '$($k1PublishReceiptState.Data.publication_kind)'.")
    }
    if (-not $evidenceResult -or -not $evidenceResult.GateReady) {
        $errors.Add('K2B: baza po suplemencie nie przeszła ponownie pełnego GATE_READY.')
    }
    if (-not $resolvedK1Run) {
        $errors.Add('K2B: meta.md nie wskazuje aktualnego, zweryfikowanego runu suplementu.')
    } else {
        $runJsonPath = Join-Path $resolvedK1Run 'run.json'
        $k2bRunData = $null
        if (-not (Test-Path -LiteralPath $runJsonPath -PathType Leaf)) {
            $errors.Add('K2B: aktualny run suplementu nie zawiera run.json.')
        } else {
            try {
                $k2bRunData = Get-Content -LiteralPath $runJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
                if ([string]$k2bRunData.run_type -ne 'SUPPLEMENT_AGGREGATE') { $errors.Add("K2B: run_type musi mieć SUPPLEMENT_AGGREGATE, jest '$($k2bRunData.run_type)'.") }
                if ([string]$k2bRunData.engine_version -ne '2.1.0') { $errors.Add("K2B: aggregate run musi mieć engine_version 2.1.0, jest '$($k2bRunData.engine_version)'.") }
                if ([string]$k2bRunData.locator_policy -ne 'MIXED_V1') { $errors.Add("K2B: aggregate run musi mieć locator_policy MIXED_V1, jest '$($k2bRunData.locator_policy)'.") }
                if ([string]$k2bRunData.ledger_sha256 -ne $actualK1LedgerHash) { $errors.Add('K2B: run.json nie jest związany z aktualnym aggregate ledgerem.') }
                $sourceRunIds = @($k2bRunData.source_runs | ForEach-Object { [string]$_ } | Where-Object { $_ })
                $supplementSourceRun = [string]$k2bRunData.supplement_source_run
                if ($sourceRunIds.Count -lt 2 -or @($sourceRunIds | Select-Object -Unique).Count -ne $sourceRunIds.Count) {
                    $errors.Add('K2B: aggregate run musi zawierać co najmniej dwa unikalne source_runs.')
                }
                if ([string]::IsNullOrWhiteSpace($supplementSourceRun) -or $supplementSourceRun -notin $sourceRunIds) {
                    $errors.Add('K2B: supplement_source_run musi wskazywać jeden z source_runs.')
                }
                $aggregateLedgerEvents = @(Get-Content -LiteralPath (Join-Path $resolvedK1Run 'ledger.jsonl') -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String })
                $ledgerRunIds = @($aggregateLedgerEvents | ForEach-Object { [string]$_.run_id } | Where-Object { $_ } | Select-Object -Unique)
                foreach ($sourceRunId in $sourceRunIds) {
                    if ($sourceRunId -notin $ledgerRunIds) { $errors.Add("K2B: aggregate ledger nie zawiera zadeklarowanego source_run '$sourceRunId'.") }
                }
                if (-not @($aggregateLedgerEvents | Where-Object { $_.run_id -eq $supplementSourceRun -and $_.event_type -eq 'candidate' })) {
                    $errors.Add('K2B: aggregate ledger nie zawiera kandydata z bieżącego supplement_source_run.')
                }
            } catch {
                $errors.Add("K2B: run.json/ledger agregatu jest nieprawidłowy: $($_.Exception.Message)")
            }
        }
        $validRecoveryBackups = @()
        foreach ($backup in @(Get-ChildItem -LiteralPath $resolvedK1Run -File -Filter 'canonical-before-supplement-*.md' -ErrorAction SilentlyContinue)) {
            $backupNameMatch = [regex]::Match($backup.Name, '^canonical-before-supplement-([A-Fa-f0-9]{64})\.md$')
            if ($backupNameMatch.Success -and (Get-FileHash -LiteralPath $backup.FullName -Algorithm SHA256).Hash -eq $backupNameMatch.Groups[1].Value.ToUpperInvariant()) {
                $validRecoveryBackups += $backup.FullName
            }
        }
        if ($validRecoveryBackups.Count -eq 0) {
            $errors.Add('K2B: brak potwierdzonego merge suplementu — aktualny run nie ma poprawnej kopii canonical-before-supplement-<SHA256>.md.')
        } else {
            if ($k2bRunData) {
                $declaredBackup = [string]$k2bRunData.canonical_backup_relative
                $declaredBackupHash = [string]$k2bRunData.canonical_backup_sha256
                if ([string]::IsNullOrWhiteSpace($declaredBackup) -or [IO.Path]::GetFileName($declaredBackup) -ne $declaredBackup) {
                    $errors.Add('K2B: canonical_backup_relative musi wskazywać pojedynczy plik wewnątrz aggregate runu.')
                } else {
                    $declaredBackupPath = Join-Path $resolvedK1Run $declaredBackup
                    if ($declaredBackupPath -notin $validRecoveryBackups -or $declaredBackupHash -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $declaredBackupPath -Algorithm SHA256).Hash -ne $declaredBackupHash.ToUpperInvariant()) {
                        $errors.Add('K2B: run.json nie jest poprawnie związany z kopią bazy sprzed suplementu.')
                    }
                }
            }
            if (-not $k2bUsesExplicitDecision -and $k2bResolvedCardIds.Count -gt 0) {
                $cardsBeforeSupplement = @($validRecoveryBackups | ForEach-Object {
                    [regex]::Matches((Get-Content -LiteralPath $_ -Raw -Encoding UTF8), '(?m)^###\s+(#P-\d{3,})\s*$') | ForEach-Object { $_.Groups[1].Value }
                } | Select-Object -Unique)
                $newReferencedCards = @($k2bResolvedCardIds | Where-Object { $_ -notin $cardsBeforeSupplement } | Select-Object -Unique)
                if ($newReferencedCards.Count -eq 0) {
                    $errors.Add('K2B: SUPLEMENT WYMAGANY musi wskazywać co najmniej jedną nową kartę nieobecną w kopii bazy sprzed merge albo jawną decyzję zmiany architektury/luki.')
                }
            }
        }
    }
    $canonicalK1Path = Join-Path $project '01-baza-dowodow.md'
    if (Test-Path -LiteralPath $canonicalK1Path -PathType Leaf) {
        $canonicalK1ForK2B = Get-Content -LiteralPath $canonicalK1Path -Raw -Encoding UTF8
        $baseK2BHash = Get-MetaValue -Text $canonicalK1ForK2B -Name 'K1_EXPORT_SHA256'
        $metaK2BHash = Get-MetaValue -Text $meta -Name 'K1_LEDGER_SHA256'
        if ($baseK2BHash -ne $metaK2BHash -or $metaK2BHash -ne $actualK1LedgerHash) {
            $errors.Add('K2B: meta, baza i aktualny ledger nie wskazują tego samego runu po suplemencie.')
        }
    }
}

$packetGateIndex = if ($isK1LiteV2Workflow) { $k2bIndex } else { [array]::IndexOf($order,'K3') }
if ($isCompactWorkflow -and $stageIndex -ge $packetGateIndex) {
    $basePath = Join-Path $project '01-baza-dowodow.md'
    $architecturePath = Join-Path $project '02-architektura-odcinka.md'
    $packetDir = Join-Path $project '_work\k3-pakiety'
    $packetErrorPrefix = if ($stageIndex -eq $k2bIndex) { 'K2B' } else { 'K3' }
    if ($architectureResult -and $architectureResult.GateReady -and (Test-Path -LiteralPath $basePath) -and (Test-Path -LiteralPath $architecturePath)) {
        $baseHash = (Get-FileHash -LiteralPath $basePath -Algorithm SHA256).Hash
        $architectureHash = (Get-FileHash -LiteralPath $architecturePath -Algorithm SHA256).Hash
        $expectedPacketNames = [System.Collections.Generic.List[string]]::new()
        $expectedPacketByName = @{}
        $packetBuilder = Join-Path $PSScriptRoot 'Build-K3Packets.ps1'
        try {
            $packetPreview = & $packetBuilder -ProjectPath $project
            foreach ($expectedPacket in @($packetPreview.ExpectedPackets)) {
                if ($expectedPacketByName.ContainsKey([string]$expectedPacket.FileName)) {
                    $errors.Add("${packetErrorPrefix}: dwa akty mapują się na tę samą nazwę paczki '$($expectedPacket.FileName)'.")
                } else {
                    $expectedPacketByName[[string]$expectedPacket.FileName] = $expectedPacket
                }
            }
        } catch {
            $errors.Add("${packetErrorPrefix}: nie udało się deterministycznie odtworzyć paczek K3: $($_.Exception.Message)")
        }
        foreach ($plan in @($architectureResult.ActPlans)) {
            $safeName = ($plan.Act -replace '[^\p{L}\p{Nd}._-]+', '_').Trim('_')
            if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'AKT' }
            $packetName = "$safeName.md"
            $expectedPacketNames.Add($packetName)
            $packetPath = Join-Path $packetDir $packetName
            if (-not (Test-Path -LiteralPath $packetPath -PathType Leaf)) {
                $errors.Add("${packetErrorPrefix}: brak wygenerowanej paczki aktu '$($plan.Act)': $packetPath")
                continue
            }
            $packet = Get-Content -LiteralPath $packetPath -Raw -Encoding UTF8
            $packetBaseHash = Get-MetaValue -Text $packet -Name 'K1_SHA256'
            $packetArchitectureHash = Get-MetaValue -Text $packet -Name 'K2_SHA256'
            $packetAct = Get-MetaValue -Text $packet -Name 'ACT_ID'
            $packetCards = Get-MetaValue -Text $packet -Name 'PRIMARY_CARD_IDS'
            if ($packetBaseHash -ne $baseHash) { $errors.Add("${packetErrorPrefix}: paczka '$($plan.Act)' jest nieaktualna względem 01-baza-dowodow.md.") }
            if ($packetArchitectureHash -ne $architectureHash) { $errors.Add("${packetErrorPrefix}: paczka '$($plan.Act)' jest nieaktualna względem 02-architektura-odcinka.md.") }
            if ($packetAct -ne $plan.Act) { $errors.Add("${packetErrorPrefix}: ACT_ID paczki '$packetAct' nie odpowiada aktowi '$($plan.Act)'.") }
            if ($packetCards -ne $plan.CardIds) { $errors.Add("${packetErrorPrefix}: PRIMARY_CARD_IDS paczki '$($plan.Act)' nie odpowiada architekturze.") }
            if (-not $expectedPacketByName.ContainsKey($packetName)) {
                $errors.Add("${packetErrorPrefix}: brak deterministycznego wzorca paczki '$packetName'.")
            } else {
                $expectedPacket = $expectedPacketByName[$packetName]
                $actualBytes = [IO.File]::ReadAllBytes($packetPath)
                $expectedBytes = [byte[]]$expectedPacket.ExpectedBytes
                $actualHash = (Get-FileHash -LiteralPath $packetPath -Algorithm SHA256).Hash
                $sameBytes = $actualBytes.Length -eq $expectedBytes.Length -and
                    [Convert]::ToBase64String($actualBytes) -ceq [Convert]::ToBase64String($expectedBytes)
                if (-not $sameBytes -or $actualHash -ne [string]$expectedPacket.ExpectedSha256) {
                    $errors.Add("${packetErrorPrefix}: paczka '$($plan.Act)' nie odpowiada deterministycznie wygenerowanym bajtom z aktualnych 01 i 02 (oczekiwany SHA-256 $($expectedPacket.ExpectedSha256), jest $actualHash).")
                }
            }
        }
        if (Test-Path -LiteralPath $packetDir -PathType Container) {
            foreach ($packetEntry in Get-ChildItem -LiteralPath $packetDir -Force) {
                if ($packetEntry.PSIsContainer) {
                    $errors.Add("${packetErrorPrefix}: katalog paczek zawiera niedozwolony podkatalog: $($packetEntry.FullName)")
                } elseif ($packetEntry.Extension -ne '.md') {
                    $errors.Add("${packetErrorPrefix}: katalog paczek zawiera niedozwolony plik inny niż oczekiwana paczka .md: $($packetEntry.FullName)")
                } elseif ($packetEntry.Name -notin @($expectedPacketNames)) {
                    $errors.Add("${packetErrorPrefix}: osierocona paczka nie odpowiada żadnemu aktualnemu aktowi: $($packetEntry.FullName)")
                } elseif (($packetEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    $errors.Add("${packetErrorPrefix}: paczka nie może być dowiązaniem ani reparse pointem: $($packetEntry.FullName)")
                }
            }
        }
    }

}

$k3ActMetrics = [System.Collections.Generic.List[object]]::new()
if ($isCompactWorkflow -and $stageIndex -ge [array]::IndexOf($order,'K3')) {
    $basePath = Join-Path $project '01-baza-dowodow.md'
    if (Test-Path -LiteralPath $draftPath -PathType Leaf) {
        $draft = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
        $draftRevision = Get-MetaValue -Text $draft -Name 'CONTENT_REVISION'
        $draftDate = Get-MetaValue -Text $draft -Name 'DATE'
        $declaredWordCount = Get-MetaValue -Text $draft -Name 'WORD_COUNT'
        $declaredWpm = Get-MetaValue -Text $draft -Name 'WORDS_PER_MINUTE'
        $declaredDuration = Get-MetaValue -Text $draft -Name 'ESTIMATED_DURATION'
        if (-not $draftRevision) { $errors.Add('K3: brak CONTENT_REVISION.') }
        if (-not $draftDate) { $errors.Add('K3: brak DATE.') }
        if ($draft -match '\[TEKST\]|\[FINALNY TEKST') { $errors.Add('K3: draft zawiera placeholder zamiast narracji.') }
        $measurement = $null
        try {
            $measurement = & (Join-Path $PSScriptRoot 'Measure-Script.ps1') -ScriptPath $draftPath -ProjectPath $project
            if ($measurement.WordCount -lt 25) { $errors.Add("K3: draft ma tylko $($measurement.WordCount) słów narracji; wygląda na pusty lub testowy.") }
            $declaredCountNumber = 0
            if (-not [int]::TryParse($declaredWordCount, [ref]$declaredCountNumber) -or $declaredCountNumber -ne $measurement.WordCount) {
                $errors.Add("K3: WORD_COUNT '$declaredWordCount' nie odpowiada pomiarowi $($measurement.WordCount).")
            }
            $declaredWpmNumber = 0.0
            if (-not [double]::TryParse($declaredWpm, [ref]$declaredWpmNumber) -or $declaredWpmNumber -ne $measurement.WordsPerMinute) {
                $errors.Add("K3: WORDS_PER_MINUTE '$declaredWpm' nie odpowiada pomiarowi $($measurement.WordsPerMinute).")
            }
            if ($declaredDuration -ne $measurement.Duration) { $errors.Add("K3: ESTIMATED_DURATION '$declaredDuration' nie odpowiada pomiarowi $($measurement.Duration).") }
        } catch {
            $errors.Add("K3: nie udało się zmierzyć draftu: $($_.Exception.Message)")
        }

        $knownCards = if (Test-Path -LiteralPath $basePath) {
            @([regex]::Matches((Get-Content -LiteralPath $basePath -Raw -Encoding UTF8), '(?m)^###\s+(#P-\d{3,})\s*$') | ForEach-Object { $_.Groups[1].Value })
        } else { @() }

        if ($architectureResult -and $architectureResult.GateReady) {
            $separator = [regex]::Match($draft, '(?m)^---\s*$')
            $budgetOverrideValue = $null
            $budgetOverrideAct = $null
            $budgetOverrideValid = $false
            $budgetOverrideMatches = @([regex]::Matches($draft, '(?m)^K3_BUDGET_OVERRIDE:\s*(.*?)\s*$'))
            if ($budgetOverrideMatches.Count -ne 1) {
                $errors.Add("K3: wymagane jest dokładnie jedno pole K3_BUDGET_OVERRIDE, znaleziono $($budgetOverrideMatches.Count).")
            } else {
                $budgetOverrideValue = $budgetOverrideMatches[0].Groups[1].Value.Trim()
                if ($separator.Success -and $budgetOverrideMatches[0].Index -gt $separator.Index) {
                    $errors.Add('K3: K3_BUDGET_OVERRIDE musi znajdować się w metadanych przed separatorem narracji.')
                }
                if ($budgetOverrideValue -eq 'BRAK') {
                    $budgetOverrideValid = $false
                    } else {
                        $overrideMatch = [regex]::Match($budgetOverrideValue, '^DAWID=TAK;\s*AKT=([^;]+);\s*POWÓD=([^;]{15,});\s*ZAKRES=(.{5,})$')
                    if (-not $overrideMatch.Success) {
                        $errors.Add('K3: K3_BUDGET_OVERRIDE musi mieć BRAK albo format DAWID=TAK; AKT=<id>; POWÓD=<min. 15 znaków>; ZAKRES=<min. 5 znaków>.')
                    } else {
                        $budgetOverrideAct = $overrideMatch.Groups[1].Value.Trim()
                        $budgetOverrideValid = $true
                        $exceptionState = Get-EditorialExceptionReceiptState -ProjectPath $project -ExceptionType 'K3_BUDGET_OVERRIDE' `
                            -ArtifactPath $draftPath -TargetId $budgetOverrideAct -ExpectedDecision 'ALLOW_BUDGET_OVERRIDE' `
                            -ExpectedReason $overrideMatch.Groups[2].Value.Trim() -ExpectedScope $overrideMatch.Groups[3].Value.Trim()
                        if (-not $exceptionState.Valid) {
                            $budgetOverrideValid = $false
                            foreach ($problem in @($exceptionState.Errors)) { $errors.Add("K3: wyjątek budżetu: $problem") }
                        }
                    }
                }
            }

            if (-not $separator.Success) {
                $errors.Add('K3: brak separatora --- oddzielającego metadane od narracji.')
            } else {
                $draftPreamble = $draft.Substring(0, $separator.Index)
                if ($draftPreamble -match '(?m)^##\s+Budżet słów\s*$') {
                    $errors.Add('K3: ręczna tabela Budżet słów jest niedozwolona; rzeczywiste wykonanie per akt pochodzi wyłącznie z K3ActMetrics walidatora.')
                }
                $narrationBody = $draft.Substring($separator.Index + $separator.Length)
                $headingMatches = @([regex]::Matches($narrationBody, '(?m)^##[ \t]+([^\r\n]+?)[ \t]*\r?$'))
                $sections = [System.Collections.Generic.List[object]]::new()
                if ($headingMatches.Count -eq 0) {
                    if (-not [string]::IsNullOrWhiteSpace($narrationBody)) { $errors.Add('K3: narracja po separatorze nie jest przypisana do żadnej sekcji aktu.') }
                } else {
                    $prefix = $narrationBody.Substring(0, $headingMatches[0].Index)
                    if (-not [string]::IsNullOrWhiteSpace($prefix)) { $errors.Add('K3: tekst narracyjny przed pierwszym aktem nie należy do architektury.') }
                    for ($headingIndex = 0; $headingIndex -lt $headingMatches.Count; $headingIndex++) {
                        $heading = $headingMatches[$headingIndex]
                        $bodyStart = $heading.Index + $heading.Length
                        $bodyEnd = if ($headingIndex + 1 -lt $headingMatches.Count) { $headingMatches[$headingIndex + 1].Index } else { $narrationBody.Length }
                        $sections.Add([pscustomobject]@{
                            Name = $heading.Groups[1].Value.Trim()
                            Body = $narrationBody.Substring($bodyStart, $bodyEnd - $bodyStart)
                        })
                    }
                }

                $expectedActs = @($architectureResult.ActPlans | ForEach-Object { [string]$_.Act })
                foreach ($section in $sections) {
                    if ([array]::IndexOf($expectedActs, [string]$section.Name) -lt 0) {
                        $errors.Add("K3: dodatkowa sekcja narracji '$($section.Name)' nie istnieje w architekturze.")
                    }
                }
                foreach ($duplicateSection in @($sections.Name) | Group-Object | Where-Object Count -gt 1) {
                    $errors.Add("K3: sekcja aktu '$($duplicateSection.Name)' występuje więcej niż raz.")
                }

                $outOfRangeActs = [System.Collections.Generic.List[object]]::new()
                $sumActWords = 0
                $tracePattern = '^<!-- ślad #P:\s*(#P-\d{3,}(?:\s*(?:,|\+)\s*#P-\d{3,})*)\s*-->$'
                foreach ($plan in @($architectureResult.ActPlans)) {
                    $planAct = [string]$plan.Act
                    $matchingSections = @($sections | Where-Object { $_.Name -ceq $planAct })
                    if ($matchingSections.Count -ne 1) {
                        if ($matchingSections.Count -eq 0) { $errors.Add("K3: draft nie zawiera sekcji aktu '$planAct'.") }
                        continue
                    }

                    $actBody = [string]$matchingSections[0].Body
                    $allowedCards = @($plan.CardIds -split ',\s*' | Where-Object { $_ })
                    $validTracedCards = [System.Collections.Generic.List[string]]::new()
                    $actWordCount = Get-K3NarrationWordCount -Text $actBody
                    $sumActWords += $actWordCount
                    $blockWordSum = 0
                    $narrativeBlockCount = 0
                    $lines = @($actBody -split '\r?\n')
                    $lineIndex = 0
                    while ($lineIndex -lt $lines.Count) {
                        while ($lineIndex -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$lineIndex])) { $lineIndex++ }
                        if ($lineIndex -ge $lines.Count) { break }

                        $trimmedLine = $lines[$lineIndex].Trim()
                        if ($trimmedLine -match '^#{3,6}\s+') { $lineIndex++; continue }
                        if ($trimmedLine -match '^<!--') {
                            $errors.Add("K3: akt '$planAct' zawiera osierocony albo nieprawidłowy komentarz; dozwolony jest wyłącznie ślad bezpośrednio po bloku.")
                            $lineIndex++
                            continue
                        }

                        $blockLines = [System.Collections.Generic.List[string]]::new()
                        while ($lineIndex -lt $lines.Count) {
                            $candidateLine = $lines[$lineIndex]
                            $candidateTrimmed = $candidateLine.Trim()
                            if ([string]::IsNullOrWhiteSpace($candidateLine) -or $candidateTrimmed -match '^#{3,6}\s+' -or $candidateTrimmed -match $tracePattern) { break }
                            $blockLines.Add($candidateLine)
                            $lineIndex++
                        }
                        $blockText = ($blockLines -join "`n").Trim()
                        $blockWords = Get-K3NarrationWordCount -Text $blockText
                        $narrativeBlockCount++
                        $blockWordSum += $blockWords
                        if ($blockWords -eq 0) { $errors.Add("K3: akt '$planAct' zawiera pusty lub nienarracyjny blok.") }
                        if ($blockWords -gt 220) { $errors.Add("K3: blok $narrativeBlockCount w akcie '$planAct' ma $blockWords słów; maksimum to 220.") }
                        if ($blockText -match '#P-\d{3,}') { $errors.Add("K3: blok $narrativeBlockCount w akcie '$planAct' zawiera zwykły #P w prozie; liczy się wyłącznie osobny komentarz śladu po bloku.") }

                        while ($lineIndex -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$lineIndex])) { $lineIndex++ }
                        if ($lineIndex -ge $lines.Count -or $lines[$lineIndex].Trim() -notmatch $tracePattern) {
                            $errors.Add("K3: blok $narrativeBlockCount w akcie '$planAct' nie ma bezpośrednio po sobie dokładnego komentarza <!-- ślad #P: ... -->.")
                            continue
                        }

                        $traceMatch = [regex]::Match($lines[$lineIndex].Trim(), $tracePattern)
                        $traceIds = @($traceMatch.Groups[1].Value -split '\s*(?:,|\+)\s*' | Where-Object { $_ })
                        if (@($traceIds | Select-Object -Unique).Count -ne $traceIds.Count) {
                            $errors.Add("K3: blok $narrativeBlockCount w akcie '$planAct' powtarza ten sam identyfikator w komentarzu śladu.")
                        }
                        foreach ($id in $traceIds) {
                            if ($id -notin $knownCards) {
                                $errors.Add("K3: blok $narrativeBlockCount w akcie '$planAct' odwołuje się do nieistniejącej karty $id.")
                            } elseif ($id -notin $allowedCards) {
                                $errors.Add("K3: blok $narrativeBlockCount w akcie '$planAct' używa karty spoza PRIMARY swojej paczki: $id.")
                            } elseif (-not $validTracedCards.Contains($id)) {
                                $validTracedCards.Add($id)
                            }
                        }
                        $lineIndex++
                    }

                    if ($narrativeBlockCount -eq 0) { $errors.Add("K3: akt '$planAct' nie zawiera żadnego bloku narracji.") }
                    if ($blockWordSum -ne $actWordCount) {
                        $errors.Add("K3: nie cała narracja aktu '$planAct' została objęta blokami ze śladem ($blockWordSum z $actWordCount słów).")
                    }
                    if ($validTracedCards.Count -eq 0) { $errors.Add("K3: akt '$planAct' nie ma poprawnego śladu PRIMARY #P.") }
                    if ($validTracedCards.Count -gt 0 -and $actWordCount -gt (300 * $validTracedCards.Count)) {
                        $errors.Add("K3: akt '$planAct' ma $actWordCount słów przy $($validTracedCards.Count) unikalnych użytych PRIMARY; maksimum to 300 słów na kartę.")
                    }

                    $budget = [int]$plan.Budget
                    $percent = if ($budget -gt 0) { [math]::Round(100.0 * $actWordCount / $budget, 1) } else { 0 }
                    $inRange = $budget -gt 0 -and $actWordCount -ge (0.7 * $budget) -and $actWordCount -le (1.4 * $budget)
                    if (-not $inRange) {
                        $outOfRangeActs.Add([pscustomobject]@{ Act = $planAct; Actual = $actWordCount; Budget = $budget; Percent = $percent })
                    }
                    $k3ActMetrics.Add([pscustomobject]@{
                        Act = $planAct
                        Budget = $budget
                        ActualWords = $actWordCount
                        BudgetPercent = $percent
                        Blocks = $narrativeBlockCount
                        UniquePrimaryUsed = $validTracedCards.Count
                    })
                }

                if ($measurement -and $sumActWords -ne [int]$measurement.WordCount) {
                    $errors.Add("K3: suma rzeczywistych słów aktów $sumActWords nie odpowiada globalnemu pomiarowi $($measurement.WordCount); istnieje narracja poza dozwolonymi aktami albo nieobjęta parserem.")
                }

                foreach ($outlier in $outOfRangeActs) {
                    if ($budgetOverrideValid -and $budgetOverrideAct -ceq $outlier.Act) {
                        $warnings.Add("K3: Dawid jawnie zaakceptował odchylenie budżetu aktu '$($outlier.Act)': $($outlier.Actual)/$($outlier.Budget) słów ($($outlier.Percent)%).")
                    } else {
                        $errors.Add("K3: akt '$($outlier.Act)' ma $($outlier.Actual) słów przy budżecie $($outlier.Budget) ($($outlier.Percent)%); wymagane 70–140% albo pasujący K3_BUDGET_OVERRIDE Dawida.")
                    }
                }
                if ($budgetOverrideValid) {
                    if ($budgetOverrideAct -notin $expectedActs) {
                        $errors.Add("K3: K3_BUDGET_OVERRIDE wskazuje nieistniejący akt '$budgetOverrideAct'.")
                    } elseif (-not @($outOfRangeActs | Where-Object { $_.Act -ceq $budgetOverrideAct })) {
                        $errors.Add("K3: K3_BUDGET_OVERRIDE dla aktu '$budgetOverrideAct' jest zbędny lub nieaktualny, bo akt mieści się w 70–140% budżetu.")
                    }
                }
            }
        }
    }
}

if ($isNarrationOnlyWorkflow -and $stage -eq 'COMPLETE') {
    $lastGate = Get-MetaValue -Text $meta -Name 'LAST_GATE'
    if ($stageOwner -ne 'Dawid') { $errors.Add("COMPLETE: STAGE_OWNER musi mieć Dawid, jest '$stageOwner'.") }
    if ($ownerOverride -ne 'BRAK') { $errors.Add('COMPLETE: OWNER_OVERRIDE musi mieć BRAK.') }
    if ($lastGate -ne 'K5_PASS') { $errors.Add("COMPLETE: LAST_GATE musi mieć K5_PASS, jest '$lastGate'.") }
}

# Automatyczna kontrola powtórzeń między aktami, gdy istnieje draft.
if (Test-Path -LiteralPath $draftPath -PathType Leaf) {
    try {
        $repetition = & (Join-Path $PSScriptRoot 'Check-Repetition.ps1') -ProjectPath $project
        if ($repetition.PSObject.Properties.Name -contains 'RepeatedPhrases') {
            foreach ($item in @($repetition.RepeatedPhrases)) {
                if ($item -ne 'BRAK') { $warnings.Add("Powtórzona fraza między aktami: $item") }
            }
            foreach ($item in @($repetition.SharedCards)) {
                if ($item -ne 'BRAK') { $warnings.Add("Karta użyta w wielu aktach: $item") }
            }
        }
    } catch {
        $warnings.Add("Nie udało się sprawdzić powtórzeń: $($_.Exception.Message)")
    }
}

$result = [pscustomobject]@{
    ProjectPath = $project
    Stage = $stage
    Errors = $errors.Count
    Warnings = $warnings.Count
    ErrorDetails = $errors
    WarningDetails = $warnings
    K3ActMetrics = @($k3ActMetrics)
    Verdict = if ($errors.Count -eq 0) { 'PASS' } else { 'FAIL' }
}

$result
if ($errors.Count -gt 0 -and -not $NoExit) { exit 1 }
