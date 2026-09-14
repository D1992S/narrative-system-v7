[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [ValidatePattern('^ACT-\d{3}$')]
    [string]$ActId,

    [string]$VoiceProfilePath,

    [switch]$AllowTestVoiceProfile,

    [switch]$Write,
    [switch]$Force,
    [switch]$PruneOrphans
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$dispatchMetaPath = Join-Path $project 'meta.md'
if (Test-Path -LiteralPath $dispatchMetaPath -PathType Leaf) {
    . (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
    $dispatchMeta = Get-Content -LiteralPath $dispatchMetaPath -Raw -Encoding UTF8
    if (Test-SystemV7NarrativeV2Revision -MetaText $dispatchMeta) {
        if ($PruneOrphans) { throw 'PRUNE_ORPHANS_NOT_SUPPORTED_IN_NARRATIVE_V2' }
        & (Join-Path $PSScriptRoot 'Build-K3PacketsV2.ps1') -ProjectPath $project -ActId $ActId -VoiceProfilePath $VoiceProfilePath -AllowTestVoiceProfile:$AllowTestVoiceProfile -Write:$Write -Force:$Force
        return
    }
}
$basePath = Join-Path $project '01-baza-dowodow.md'
$architecturePath = Join-Path $project '02-architektura-odcinka.md'
$validator = Join-Path $PSScriptRoot 'Validate-EvidenceBase.ps1'
$architectureValidator = Join-Path $PSScriptRoot 'Validate-Architecture.ps1'
$outputDir = Join-Path $project '_work\k3-pakiety'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')

$projectLock = if ($Write) { Enter-SystemV7ProjectMetaLock -ProjectPath $project } else { $null }
try {

function Get-CardFieldValue {
    param([string]$Text, [string]$Name)
    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function ConvertFrom-PacketTableRow {
    param([string]$Line)
    if ($Line -notmatch '^\s*\|.*\|\s*$') { return @() }
    return @(($Line.Trim() -replace '^\|','' -replace '\|$','') -split '\|' | ForEach-Object { $_.Trim() })
}

foreach ($required in @($basePath, $architecturePath, $validator, $architectureValidator)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Brak wymaganego pliku: $required" }
}

$validation = & $validator -ProjectPath $project -NoExit
if ($validation.StructureVerdict -ne 'STRUCTURE_PASS') {
    throw "Baza K1 nie ma STRUCTURE_PASS: $($validation.ErrorDetails -join '; ')"
}
if (
    $validation.PSObject.Properties.Name -contains 'ManualCheckCards' -and
    [int]$validation.ManualCheckCards -ne 0
) {
    throw "Baza K1 ma ManualCheckCards: $($validation.ManualCheckCards). Paczki K3 wymagają pełnej kontroli maszynowej (ManualCheckCards: 0)."
}
if (-not $validation.GateReady) {
    throw 'Baza K1 nie ma GATE_READY. Wymagane: STRUCTURE_CHECK, SOURCE_FIDELITY_CHECK, SATURATION_CHECK oraz K1_VERDICT.'
}
$architectureValidation = & $architectureValidator -ProjectPath $project -NoExit
if (-not $architectureValidation.GateReady) {
    throw "Architektura nie ma ARCHITECTURE_PASS: $($architectureValidation.ErrorDetails -join '; ')"
}

$base = Get-Content -LiteralPath $basePath -Raw -Encoding UTF8
$cardPattern = '(?ms)^###\s+(#P-\d{3,})\s*\r?\n(.*?)(?=^###\s+#P-\d{3,}\s*$|^##\s+|\z)'
$cards = @{}
$cardMeta = @{}
# Odległość w liniach, poniżej której dwie karty uznajemy za jeden ciągły fragment
# źródła. Kanoniczny plik ma jeden akapit w linii, więc sąsiednie akapity dzielą
# dwie linie; dwanaście mieści kilka akapitów tej samej sceny.
$contiguityGap = 12

foreach ($match in [regex]::Matches($base, $cardPattern)) {
    $id = $match.Groups[1].Value
    $body = $match.Groups[2].Value.Trim()

    # Paczka dla autora ma whitelistę. Nawet jeżeli starsza lub ręcznie zmieniona
    # karta zawiera dodatkowe pola/notatki, do K3 przechodzą tylko dosłowna treść
    # i identyfikator jej źródła. QA oraz lokalizator pozostają w bazie dla K4.
    $cardText = Get-CardFieldValue -Text $body -Name 'TREŚĆ'
    $sourceRefValue = Get-CardFieldValue -Text $body -Name 'ŹRÓDŁO_ID'
    if ([string]::IsNullOrWhiteSpace($cardText)) { throw "Brak TREŚĆ w karcie $id." }
    if ($sourceRefValue -notmatch '^#?S-\d{3,}$') { throw "Nieprawidłowe ŹRÓDŁO_ID w karcie ${id}: '$sourceRefValue'." }
    $sourceRef = '#' + $sourceRefValue.TrimStart('#')
    $cards[$id] = "### $id`r`n`r`nTREŚĆ: $cardText`r`nŹRÓDŁO_ID: $sourceRef"

    $from = 0; $to = 0
    $lineMatch = [regex]::Match($body, '(?m)^LOKALIZACJA:.*?\bL(\d+)(?:\s*[-–]\s*L?(\d+))?')
    if ($lineMatch.Success) {
        $from = [int]$lineMatch.Groups[1].Value
        $to = if ($lineMatch.Groups[2].Success) { [int]$lineMatch.Groups[2].Value } else { $from }
    }
    $cardMeta[$id] = [pscustomobject]@{ Source = $sourceRef; From = $from; To = $to }
}

# Karta minimalna niesie tylko `ŹRÓDŁO_ID`, więc bez tych wierszy autor K3
# dostawałby sam kod `#S-001` i nie mógłby podać atrybucji, nie zmyślając jej.
# Do paczki trafiają wyłącznie źródła, na które powołują się jej karty.
$sourceRows = @{}
foreach ($match in [regex]::Matches($base, '(?m)^\|\s*(#?S-\d{3,})\s*\|.*\|\s*$')) {
    $id = '#' + $match.Groups[1].Value.TrimStart('#')
    if (-not $sourceRows.ContainsKey($id)) {
        $cells = @(ConvertFrom-PacketTableRow -Line $match.Value)
        if ($cells.Count -ge 5) {
            $sourceRows[$id] = "| $id | $($cells[1]) | $($cells[2]) | $($cells[3]) | $($cells[4]) |"
        }
    }
}
$packetPlans = @($architectureValidation.ActPlans)
$baseHash = (Get-FileHash -LiteralPath $basePath -Algorithm SHA256).Hash
$architectureHash = (Get-FileHash -LiteralPath $architecturePath -Algorithm SHA256).Hash
$expectedPacketNames = @($packetPlans | ForEach-Object {
    $safeName = ($_.Act -replace '[^\p{L}\p{Nd}._-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'AKT' }
    "$safeName.md"
})
$packetNameCollisions = @($expectedPacketNames | Group-Object | Where-Object Count -gt 1)
if ($packetNameCollisions.Count -gt 0) {
    throw "Co najmniej dwa akty mapują się na tę samą nazwę paczki po bezpiecznej normalizacji: $($packetNameCollisions.Name -join ', '). Zmień nazwy aktów przed zapisem."
}
$orphanedFiles = if (Test-Path -LiteralPath $outputDir -PathType Container) {
    @(Get-ChildItem -LiteralPath $outputDir -File -Filter '*.md' | Where-Object Name -notin $expectedPacketNames)
} else { @() }
$unexpectedEntries = if (Test-Path -LiteralPath $outputDir -PathType Container) {
    @(Get-ChildItem -LiteralPath $outputDir -Force | Where-Object {
        $_.PSIsContainer -or $_.Name -notin $expectedPacketNames -or $_.Extension -ne '.md'
    })
} else { @() }
$nonPrunableEntries = @($unexpectedEntries | Where-Object { $_.PSIsContainer -or $_.Extension -ne '.md' })

if ($PruneOrphans -and (-not $Write -or -not $Force)) { throw '-PruneOrphans wymaga jawnego -Write -Force.' }

$utf8NoBom = [Text.UTF8Encoding]::new($false)
$expectedPackets = [System.Collections.Generic.List[object]]::new()
foreach ($plan in $packetPlans) {
    $safeName = ($plan.Act -replace '[^\p{L}\p{Nd}._-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'AKT' }
    $fileName = "$safeName.md"
    $destination = Join-Path $outputDir $fileName

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("# PAKIET K3 — $($plan.Act)")
    $parts.Add('')
    $parts.Add("K1_SHA256: $baseHash")
    $parts.Add("K2_SHA256: $architectureHash")
    $parts.Add("ACT_ID: $($plan.Act)")
    $parts.Add("PRIMARY_CARD_IDS: $($plan.CardIds)")
    $parts.Add('')
    $parts.Add('Wygenerowano z kanonicznej architektury i kart `QA_K1: GOTOWA`. Nie dodawaj researchu ani kart spoza pakietu.')
    $parts.Add('')
    $parts.Add('## Wiersz architektury')
    $parts.Add('')
    $parts.Add($plan.ArchitectureRow)
    $parts.Add('')
    $parts.Add('## Karty')
    $parts.Add('')
    $usedSourceIds = [System.Collections.Generic.List[string]]::new()
    foreach ($id in ($plan.CardIds -split ',\s*')) {
        $card = $cards[$id]
        if ([string]::IsNullOrWhiteSpace($card)) { throw "Brak treści karty $id wymaganej przez akt '$($plan.Act)'." }
        $parts.Add($card)
        $parts.Add('')
        $sourceId = [string]$cardMeta[$id].Source
        if (-not [string]::IsNullOrWhiteSpace($sourceId) -and -not $usedSourceIds.Contains($sourceId)) { $usedSourceIds.Add($sourceId) }
    }

    # Karty z jednego ciągłego miejsca w źródle opisują najczęściej to samo
    # zdarzenie. Podane osobno dają wyliczankę faktów; wskazane jako jeden
    # fragment pozwalają zbudować z nich scenę.
    $passages = [System.Collections.Generic.List[string]]::new()
    $located = @($plan.CardIds -split ',\s*' | Where-Object { $cardMeta.ContainsKey($_) -and $cardMeta[$_].From -gt 0 })
    foreach ($sourceGroup in $located | Group-Object { $cardMeta[$_].Source }) {
        $ordered = @($sourceGroup.Group | Sort-Object { $cardMeta[$_].From })
        $run = [System.Collections.Generic.List[string]]::new()
        $runEnd = [int]::MinValue
        foreach ($cardId in $ordered) {
            $cardLocation = $cardMeta[$cardId]
            if ($run.Count -gt 0 -and ($cardLocation.From - $runEnd) -le $contiguityGap) {
                $run.Add($cardId)
            } else {
                if ($run.Count -gt 1) {
                    $first = $cardMeta[$run[0]]
                    $passages.Add("- $($run -join ' + ') — jeden ciągły fragment $($sourceGroup.Name), linie $($first.From)–$runEnd.")
                }
                $run = [System.Collections.Generic.List[string]]::new()
                $run.Add($cardId)
                $runEnd = [int]::MinValue
            }
            if ($cardLocation.To -gt $runEnd) { $runEnd = $cardLocation.To }
        }
        if ($run.Count -gt 1) {
            $first = $cardMeta[$run[0]]
            $passages.Add("- $($run -join ' + ') — jeden ciągły fragment $($sourceGroup.Name), linie $($first.From)–$runEnd.")
        }
    }
    if ($passages.Count -gt 0) {
        $parts.Add('## Ciągłe fragmenty')
        $parts.Add('')
        $parts.Add('Poniższe karty pochodzą z tego samego miejsca w źródle i najpewniej opisują to samo zdarzenie. Możesz złożyć je w jedną scenę zamiast wyliczać osobno.')
        $parts.Add('')
        foreach ($passage in $passages) { $parts.Add($passage) }
        $parts.Add('')
    }

    $parts.Add('## Źródła tych kart')
    $parts.Add('')
    $parts.Add('Atrybucja pochodzi stąd. Nie przypisuj treści autorowi, którego nie ma w tej tabeli.')
    $parts.Add('')
    $parts.Add('| ID | Plik/URL | Autor/instytucja | Data | Klasa A–D |')
    $parts.Add('|---|---|---|---|---|')
    foreach ($sourceId in $usedSourceIds) {
        if ($sourceRows.ContainsKey($sourceId)) { $parts.Add($sourceRows[$sourceId]) }
        else { $parts.Add("| $sourceId | NIEZNANE ŹRÓDŁO — sprawdź rejestr K1 |  |  |  |") }
    }
    $parts.Add('')
    $parts.Add('## Rezerwa niezaładowana')
    $parts.Add('')
    $parts.Add($(if ($plan.ReserveCardIds) { $plan.ReserveCardIds } else { 'BRAK' }))
    $parts.Add('Pełne rekordy RESERVE nie są częścią paczki. Ich użycie wymaga decyzji K2/K2B i ponownego wygenerowania paczki po awansie do PRIMARY.')
    $parts.Add('')

    # Jeden kanoniczny zapis: UTF-8 bez BOM, CRLF i dokładnie jeden końcowy newline.
    $content = ($parts -join "`r`n").TrimEnd() + "`r`n"
    $bytes = $utf8NoBom.GetBytes($content)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $expectedHash = ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
    $expectedPackets.Add([pscustomobject]@{
        Act = $plan.Act
        FileName = $fileName
        Path = $destination
        ExpectedSha256 = $expectedHash
        ByteLength = $bytes.Length
        ExpectedBytes = $bytes
    })
}

$writtenFiles = [System.Collections.Generic.List[string]]::new()
$prunedFiles = [System.Collections.Generic.List[string]]::new()
if ($Write) {
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }
    if ($orphanedFiles.Count -gt 0 -and -not $PruneOrphans) {
        throw "Znaleziono osierocone paczki po zmianie architektury: $($orphanedFiles.Name -join ', '). Sprawdź podgląd i użyj -Write -Force -PruneOrphans, aby usunąć wyłącznie te generowane pliki."
    }
    if ($nonPrunableEntries.Count -gt 0) {
        throw "Katalog paczek zawiera niedozwolone pliki lub podkatalogi, których generator nie usunie automatycznie: $($nonPrunableEntries.Name -join ', '). Usuń je jawnie po sprawdzeniu."
    }
    if ($PruneOrphans) {
        $resolvedOutputDir = [IO.Path]::GetFullPath($outputDir).TrimEnd('\')
        foreach ($orphan in $orphanedFiles) {
            if ([IO.Path]::GetFullPath($orphan.DirectoryName).TrimEnd('\') -ne $resolvedOutputDir) { throw "Niebezpieczna ścieżka osieroconej paczki: $($orphan.FullName)" }
            Remove-Item -LiteralPath $orphan.FullName -Force
            $prunedFiles.Add($orphan.FullName)
        }
    }

    foreach ($expectedPacket in $expectedPackets) {
        $destination = $expectedPacket.Path
        if ((Test-Path -LiteralPath $destination) -and -not $Force) {
            throw "Pakiet już istnieje; użyj -Force po sprawdzeniu: $destination"
        }
        [IO.File]::WriteAllBytes($destination, [byte[]]$expectedPacket.ExpectedBytes)
        $writtenFiles.Add($destination)
    }
}

[pscustomobject]@{
    ProjectPath = $project
    Mode = if ($Write) { 'WRITE' } else { 'PREVIEW' }
    PacketCount = $packetPlans.Count
    Packets = $packetPlans
    ExpectedPackets = $expectedPackets
    OrphanedFiles = @($orphanedFiles.FullName)
    UnexpectedEntries = @($unexpectedEntries.FullName)
    PrunedFiles = $prunedFiles
    WrittenFiles = $writtenFiles
}
} finally {
    if ($Write) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
}
