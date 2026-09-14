[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$architecturePath = Join-Path $project '02-architektura-odcinka.md'
$basePath = Join-Path $project '01-baza-dowodow.md'
$metaPath = Join-Path $project 'meta.md'
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$actPlans = [System.Collections.Generic.List[object]]::new()
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')

if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
    $dispatchMeta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    if (Test-SystemV7NarrativeV2Revision -MetaText $dispatchMeta) {
        $result = Test-SystemV7NarrativeArchitecture -ArchitecturePath $architecturePath -EvidencePath $basePath
        $result
        if (-not $result.GateReady -and -not $NoExit) { exit 1 }
        return
    }
}

function Get-FieldValue {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-BulletValue {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, "(?m)^\s*-\s*$([regex]::Escape($Name)):\s*(.*?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Test-ConcreteValue {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch '^BRAK$|^NIEUSTALONE$|^DO UZUPEŁNIENIA$|^\[.*\]$'
}

if (-not (Test-Path -LiteralPath $architecturePath -PathType Leaf)) {
    $errors.Add('Brak 02-architektura-odcinka.md.')
    $architecture = ''
} else {
    $architecture = Get-Content -LiteralPath $architecturePath -Raw -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $basePath -PathType Leaf)) {
    $errors.Add('Brak 01-baza-dowodow.md.')
    $base = ''
} else {
    $base = Get-Content -LiteralPath $basePath -Raw -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
    $errors.Add('Brak meta.md potrzebnego do wyliczenia budżetu K2.')
    $meta = ''
} else {
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
}

$cardQa = @{}
$cardPattern = '(?ms)^###\s+(#P-\d{3,})\s*\r?\n(.*?)(?=^###\s+#P-\d{3,}\s*$|^##\s+|\z)'
foreach ($card in [regex]::Matches($base, $cardPattern)) {
    $cardQa[$card.Groups[1].Value] = Get-FieldValue -Text $card.Groups[2].Value -Name 'QA_K1'
}

$status = Get-FieldValue -Text $architecture -Name 'STATUS'
$selectedDirection = Get-FieldValue -Text $architecture -Name 'WYBRANY_KIERUNEK'
$oneDirectionApproval = Get-FieldValue -Text $architecture -Name 'ONE_DIRECTION_APPROVAL'
if ($status -ne 'GOTOWA') { $errors.Add("K2: STATUS musi mieć GOTOWA, jest '$status'.") }
if (-not (Test-ConcreteValue $selectedDirection)) { $errors.Add('K2: brak WYBRANY_KIERUNEK.') }

$directionSection = [regex]::Match($architecture, '(?ms)^##\s+Kierunki.*?\r?\n(.*?)(?=^##\s+|\z)')
$directionIds = [System.Collections.Generic.List[string]]::new()
if (-not $directionSection.Success) {
    $errors.Add('K2: brak sekcji kierunków.')
} else {
    foreach ($line in ($directionSection.Groups[1].Value -split '\r?\n')) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith('|') -or $trimmed -match '^\|\s*-{3,}') { continue }
        $cells = @($trimmed.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -eq 0 -or $cells[0] -eq 'Kierunek') { continue }
        if ($cells.Count -lt 7) {
            $errors.Add("K2: kierunek '$($cells[0])' ma mniej niż 7 kolumn.")
            continue
        }
        $directionIds.Add($cells[0])
        foreach ($index in 0..6) {
            if (-not (Test-ConcreteValue $cells[$index])) {
                $errors.Add("K2: kierunek '$($cells[0])' ma puste pole w kolumnie $($index + 1).")
            }
        }
        $directionCards = @([regex]::Matches($cells[4], '#P-\d{3,}') | ForEach-Object Value | Select-Object -Unique)
        if ($directionCards.Count -eq 0) { $errors.Add("K2: kierunek '$($cells[0])' nie wskazuje rdzenia #P.") }
        foreach ($id in $directionCards) {
            if (-not $cardQa.ContainsKey($id)) { $errors.Add("K2: kierunek '$($cells[0])' wskazuje nieistniejącą kartę $id.") }
            elseif ($cardQa[$id] -ne 'GOTOWA') { $errors.Add("K2: kierunek '$($cells[0])' wskazuje kartę bez QA_K1 GOTOWA: $id.") }
        }
    }
}
$directionIdValues = @($directionIds)
foreach ($duplicate in $directionIdValues | Group-Object | Where-Object Count -gt 1) { $errors.Add("K2: powtórzony identyfikator kierunku '$($duplicate.Name)'.") }
$uniqueDirectionIds = @($directionIdValues | Select-Object -Unique)
if ($uniqueDirectionIds.Count -lt 1 -or $uniqueDirectionIds.Count -gt 3) { $errors.Add("K2: wymagany jest 1–3 realnych kierunków, znaleziono $($uniqueDirectionIds.Count).") }
if ($uniqueDirectionIds.Count -eq 1) {
    $approvalMatch = [regex]::Match([string]$oneDirectionApproval, '^DAWID=TAK;\s*POWÓD=(?<reason>.{10,})$')
    if (-not $approvalMatch.Success) {
        $errors.Add('K2: jeden kierunek wymaga ONE_DIRECTION_APPROVAL w formacie DAWID=TAK; POWÓD=<konkretne uzasadnienie>.')
    } elseif ((Get-FieldValue -Text $meta -Name 'WORKFLOW_REVISION') -eq '2026-08-30_K1_LITE_V2') {
        $exceptionState = Get-EditorialExceptionReceiptState -ProjectPath $project -ExceptionType 'K2_ONE_DIRECTION' `
            -ArtifactPath $architecturePath -TargetId $selectedDirection -ExpectedDecision 'ALLOW_ONE_DIRECTION' `
            -ExpectedReason $approvalMatch.Groups['reason'].Value.Trim() -ExpectedScope 'JEDEN_KIERUNEK'
        foreach ($problem in @($exceptionState.Errors)) { $errors.Add("K2: wyjątek jednego kierunku: $problem") }
    }
}
if ($uniqueDirectionIds.Count -ge 2 -and $oneDirectionApproval -ne 'BRAK') { $errors.Add("K2: przy co najmniej dwóch kierunkach ONE_DIRECTION_APPROVAL musi mieć BRAK, jest '$oneDirectionApproval'.") }
if ($selectedDirection -and $selectedDirection -notin $uniqueDirectionIds) { $errors.Add("K2: WYBRANY_KIERUNEK '$selectedDirection' nie istnieje w tabeli kierunków.") }

$architectureSection = [regex]::Match($architecture, '(?ms)^##\s+Architektura\s*\r?\n(.*?)(?=^##\s+|\z)')
$requiredHeaders = @('Akt','Funkcja','Stan przed → po','Pytanie/tarcie','Wypłata/most','PRIMARY #P','RESERVE #P','Scena/konkret narracyjny','Budżet słów')
$headerSeen = $false
if (-not $architectureSection.Success) {
    $errors.Add('K2: brak sekcji ## Architektura.')
} else {
    foreach ($line in ($architectureSection.Groups[1].Value -split '\r?\n')) {
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith('|') -or $trimmed -match '^\|\s*-{3,}') { continue }
        $cells = @($trimmed.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if (-not $headerSeen) {
            $headerSeen = $true
            if ($cells.Count -ne $requiredHeaders.Count) {
                $errors.Add("K2: tabela architektury musi mieć $($requiredHeaders.Count) kanonicznych kolumn, ma $($cells.Count).")
            } else {
                for ($i = 0; $i -lt $requiredHeaders.Count; $i++) {
                    if ($cells[$i] -ne $requiredHeaders[$i]) { $errors.Add("K2: kolumna $($i + 1) musi nazywać się '$($requiredHeaders[$i])', jest '$($cells[$i])'.") }
                }
            }
            continue
        }
        if ($cells.Count -lt 9) {
            $errors.Add("K2: wiersz aktu '$($cells[0])' ma mniej niż 9 kolumn.")
            continue
        }
        $act = $cells[0]
        foreach ($index in @(0,1,2,3,4,5,7,8)) {
            if (-not (Test-ConcreteValue $cells[$index])) { $errors.Add("K2: akt '$act' ma puste pole w kolumnie '$($requiredHeaders[$index])'.") }
        }
        $budget = 0
        $budgetIsValid = [int]::TryParse($cells[8], [ref]$budget) -and $budget -gt 0
        if (-not $budgetIsValid) { $errors.Add("K2: akt '$act' ma nieprawidłowy budżet '$($cells[8])'.") }

        $primaryIds = @([regex]::Matches($cells[5], '#P-\d{3,}') | ForEach-Object Value | Select-Object -Unique)
        $reserveIds = @([regex]::Matches($cells[6], '#P-\d{3,}') | ForEach-Object Value | Select-Object -Unique)
        if ($primaryIds.Count -eq 0) { $errors.Add("K2: akt '$act' nie ma PRIMARY #P.") }
        if ($budgetIsValid -and $primaryIds.Count -gt 0 -and $budget -gt (300 * $primaryIds.Count)) {
            $errors.Add("K2: akt '$act' ma budżet $budget słów przy $($primaryIds.Count) unikalnych PRIMARY; maksimum to 300 słów na kartę ($((300 * $primaryIds.Count))).")
        }
        foreach ($id in @($primaryIds + $reserveIds | Select-Object -Unique)) {
            if (-not $cardQa.ContainsKey($id)) { $errors.Add("K2: akt '$act' wskazuje nieistniejącą kartę $id.") }
            elseif ($cardQa[$id] -ne 'GOTOWA') { $errors.Add("K2: akt '$act' wskazuje kartę bez QA_K1 GOTOWA: $id.") }
        }
        $actPlans.Add([pscustomobject]@{
            Act = $act
            Function = $cells[1]
            StateChange = $cells[2]
            Question = $cells[3]
            Payoff = $cells[4]
            CardIds = ($primaryIds -join ', ')
            CardCount = $primaryIds.Count
            ReserveCardIds = ($reserveIds -join ', ')
            NarrativeAnchor = $cells[7]
            Budget = $budget
            ArchitectureRow = $trimmed
        })
    }
}
if (-not $headerSeen) { $errors.Add('K2: tabela architektury nie ma nagłówka.') }
if ($actPlans.Count -eq 0) { $errors.Add('K2: architektura nie zawiera żadnego kompletnego aktu.') }
foreach ($duplicate in @($actPlans.Act) | Group-Object | Where-Object Count -gt 1) { $errors.Add("K2: powtórzona nazwa aktu '$($duplicate.Name)'.") }

foreach ($field in @('Funkcja całości','Kolejność nienaruszalna','Karta/dowód kulminacyjny','Czego nie ujawniać za wcześnie','Zasady tonu','Budżet całkowity')) {
    $value = Get-BulletValue -Text $architecture -Name $field
    if (-not (Test-ConcreteValue $value)) { $errors.Add("K2: handoff K3 nie ma konkretnej wartości '$field'.") }
}
$culmination = Get-BulletValue -Text $architecture -Name 'Karta/dowód kulminacyjny'
if ($culmination -and $culmination -notmatch '#P-\d{3,}') { $errors.Add('K2: karta/dowód kulminacyjny nie wskazuje #P.') }
$declaredTotalBudget = Get-BulletValue -Text $architecture -Name 'Budżet całkowity'
$declaredTotalBudgetNumber = 0
$calculatedTotalBudget = [int](($actPlans | Measure-Object -Property Budget -Sum).Sum)
$expectedTotalBudget = 0
if (-not [int]::TryParse($declaredTotalBudget, [ref]$declaredTotalBudgetNumber) -or $declaredTotalBudgetNumber -le 0) {
    $errors.Add("K2: Budżet całkowity musi być dodatnią liczbą całkowitą, jest '$declaredTotalBudget'.")
} elseif ($declaredTotalBudgetNumber -ne $calculatedTotalBudget) {
    $errors.Add("K2: Budżet całkowity $declaredTotalBudgetNumber nie odpowiada sumie budżetów aktów $calculatedTotalBudget.")
}

$targetMinutes = 0
$realWpm = 0
$targetMinutesValue = Get-FieldValue -Text $meta -Name 'TARGET_MINUTES'
$realWpmValue = Get-FieldValue -Text $meta -Name 'REAL_WPM'
$targetMinutesValid = [int]::TryParse($targetMinutesValue, [ref]$targetMinutes) -and $targetMinutes -ge 1 -and $targetMinutes -le 240
$realWpmValid = [int]::TryParse($realWpmValue, [ref]$realWpm) -and $realWpm -ge 60 -and $realWpm -le 240
if (-not $targetMinutesValid) {
    $errors.Add("K2: TARGET_MINUTES musi być liczbą całkowitą 1–240, jest '$targetMinutesValue'.")
}
if (-not $realWpmValid) {
    $errors.Add("K2: REAL_WPM musi być liczbą całkowitą 60–240, jest '$realWpmValue'.")
}
if ($targetMinutesValid -and $realWpmValid) {
    $expectedTotalBudget = [int][math]::Round($targetMinutes * $realWpm)
    if ($declaredTotalBudgetNumber -gt 0 -and $declaredTotalBudgetNumber -ne $expectedTotalBudget) {
        $errors.Add("K2: Budżet całkowity musi wynosić dokładnie TARGET_MINUTES × REAL_WPM = $targetMinutes × $realWpm = $expectedTotalBudget, jest $declaredTotalBudgetNumber.")
    }
}

$result = [pscustomobject]@{
    ProjectPath = $project
    Directions = $uniqueDirectionIds.Count
    Acts = $actPlans.Count
    ActPlans = $actPlans
    TotalBudget = $calculatedTotalBudget
    ExpectedTotalBudget = $expectedTotalBudget
    Errors = $errors.Count
    Warnings = $warnings.Count
    ErrorDetails = $errors
    WarningDetails = $warnings
    GateReady = $errors.Count -eq 0
    Verdict = if ($errors.Count -eq 0) { 'ARCHITECTURE_PASS' } else { 'ARCHITECTURE_FAIL' }
}

$result
if ($errors.Count -gt 0 -and -not $NoExit) { exit 1 }
