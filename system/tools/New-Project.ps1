[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DestinationRoot,

    [ValidateSet('dawid_soltan', 'polska_news', 'inny')]
    [string]$Channel = 'dawid_soltan',

    [ValidateSet('STORYTELLING', 'DZIENNIKARSKI')]
    [string]$Format = 'STORYTELLING',

    [ValidateRange(1, 240)]
    [int]$TargetMinutes = 45,

    [ValidateSet('GUIDE', 'HARD_MAX')]
    [string]$TargetDurationMode = 'GUIDE',

    [ValidateRange(0, 240)]
    [int]$RealWpm = 0,

    [switch]$NarrativeV2Pilot = $true
)

$ErrorActionPreference = 'Stop'
$Channel = $Channel.ToLowerInvariant()
$Format = $Format.ToUpperInvariant()
$TargetDurationMode = $TargetDurationMode.ToUpperInvariant()
$RealWpm = if ($RealWpm -gt 0) { $RealWpm } elseif ($Channel -eq 'polska_news') { 145 } else { 130 }
$systemRoot = Split-Path -Parent $PSScriptRoot
$templateRelativePath = if ($NarrativeV2Pilot) { 'TEMPLATES\PROJECT' } else { 'tools\compatibility\PROJECT-LEGACY-K1-LITE-V2' }
$templateRoot = Join-Path $systemRoot $templateRelativePath
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')

if($NarrativeV2Pilot){Assert-SystemV7NarrativeInstructionContract -SystemRoot $systemRoot | Out-Null}

if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
    throw "Brak katalogu szablonów: $templateRoot"
}
Assert-SystemV7TreeNoReparse -RootPath $templateRoot -ContainmentRoot $systemRoot | Out-Null

$rootFull = [IO.Path]::GetFullPath($DestinationRoot)
Assert-SystemV7PathNoReparse -Path $rootFull | Out-Null
if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
    throw "Katalog docelowy nie istnieje: $rootFull"
}

$cleanProjectName = $ProjectName.Trim()
$invalidNameCharacters = [IO.Path]::GetInvalidFileNameChars()
$containsInvalidNameCharacter = $cleanProjectName.IndexOfAny($invalidNameCharacters) -ge 0
if (
    $cleanProjectName -ne $ProjectName -or
    [string]::IsNullOrWhiteSpace($cleanProjectName) -or
    $cleanProjectName -in @('.', '..') -or
    $containsInvalidNameCharacter -or
    $cleanProjectName.EndsWith('.') -or
    $cleanProjectName.EndsWith(' ') -or
    $cleanProjectName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$'
) {
    throw 'ProjectName musi być pojedynczą, bezpieczną nazwą katalogu bez separatorów, znaków sterujących, nazw urządzeń ani końcowej kropki/spacji.'
}

$target = [IO.Path]::GetFullPath((Join-Path $rootFull $cleanProjectName))
Assert-SystemV7PathNoReparse -Path $target -ContainmentRoot $rootFull | Out-Null
$targetParent = [IO.Path]::GetFullPath((Split-Path -Parent $target))
if (-not $targetParent.Equals($rootFull.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Wyliczona ścieżka projektu nie jest bezpośrednim dzieckiem DestinationRoot.'
}

if (Test-Path -LiteralPath $target) {
    throw "Projekt już istnieje; niczego nie nadpisano: $target"
}

$staging = Join-Path $rootFull ('.system-v7-new-' + [guid]::NewGuid().ToString('N') + '.tmp')
Assert-SystemV7PathNoReparse -Path $staging -ContainmentRoot $rootFull | Out-Null
$createdStaging = $false
$movedToTarget = $false
try {
    [IO.Directory]::CreateDirectory($staging) | Out-Null
    $createdStaging = $true
    foreach ($dir in @('sources', 'sources\_oryginaly', '_work', '_work\K1', '_work\K1\k1-lite-v2')) {
        [IO.Directory]::CreateDirectory((Join-Path $staging $dir)) | Out-Null
    }

    $initialFiles = @('meta.md', '00-fundament-projektu.md')
    foreach ($name in $initialFiles) {
        Copy-Item -LiteralPath (Join-Path $templateRoot $name) -Destination (Join-Path $staging $name)
    }

    $metaPath = Join-Path $staging 'meta.md'
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $replacements = [ordered]@{
        '{{PROJECT_NAME}}'   = $cleanProjectName
        '{{PROJECT_PATH}}'   = $target
        '{{CHANNEL}}'        = $Channel
        '{{FORMAT}}'         = $Format
        '{{TARGET_MINUTES}}' = [string]$TargetMinutes
        '{{TARGET_DURATION_MODE}}' = $TargetDurationMode
        '{{REAL_WPM}}'       = [string]$RealWpm
        '{{DATE}}'           = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
    }

    foreach ($entry in $replacements.GetEnumerator()) {
        $meta = $meta.Replace($entry.Key, $entry.Value)
    }

    Write-SystemV7NarrativeAtomicText -Path $metaPath -Text $meta | Out-Null
    $fundamentPath = Join-Path $staging '00-fundament-projektu.md'
    $fundament = Get-Content -LiteralPath $fundamentPath -Raw -Encoding UTF8
    foreach ($entry in $replacements.GetEnumerator()) { $fundament = $fundament.Replace($entry.Key, $entry.Value) }
    $fundament = $fundament.Replace('DECYZJA_DAWIDA: DO UZUPEŁNIENIA W W0', 'DECYZJA_DAWIDA: WYBRANE_PRZY_TWORZENIU_PROJEKTU; DO POTWIERDZENIA PRZY ZAMKNIĘCIU W0')
    Write-SystemV7NarrativeAtomicText -Path $fundamentPath -Text $fundament | Out-Null
    $selectedWorkflowRevision = if ($NarrativeV2Pilot) { $script:SystemV7CurrentWorkflowRevision } else { $script:SystemV7PreviousProjectWorkflowRevision }
    $origin = New-SystemV7ProjectOrigin -ProjectPath $staging -ProjectName $cleanProjectName -BindingProjectPath $target -WorkflowRevision $selectedWorkflowRevision -EvidenceSchema $script:SystemV7CurrentEvidenceSchema
    [IO.Directory]::Move($staging, $target)
    $movedToTarget = $true
} catch {
    if ($movedToTarget -and (Test-Path -LiteralPath $target) -and
        [IO.Path]::GetFullPath((Split-Path -Parent $target)).Equals($rootFull.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
        [IO.Directory]::Delete($target, $true)
    } elseif ($createdStaging -and (Test-Path -LiteralPath $staging) -and
        [IO.Path]::GetFullPath((Split-Path -Parent $staging)).Equals($rootFull.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
        [IO.Directory]::Delete($staging, $true)
    }
    throw
}

[pscustomobject]@{
    ProjectPath = $target
    CurrentStage = 'W0'
    WorkflowRevision = if($NarrativeV2Pilot){$script:SystemV7CurrentWorkflowRevision}else{$script:SystemV7PreviousProjectWorkflowRevision}
    WorkflowActivation = if($NarrativeV2Pilot){'PILOT_ONLY'}else{'PRODUCTION_LEGACY'}
    EvidenceSchema = 'MINIMAL_EVIDENCE_V4_PAGELOC'
    ArchitectureSchema = if($NarrativeV2Pilot){'STORY_ENGINE_V2'}else{'LEGACY_ARCHITECTURE'}
    TargetDurationMode = $TargetDurationMode
    K1ResearchMode = 'K1_LITE_V2'
    ProjectId = $origin.ProjectId
    ProjectOriginPath = Join-Path $target '.system-v7\project-origin.json'
    NextAction = 'Dostarcz aktywne materiały PDF/MD/TXT/SRT/VTT do sources/ (wyłącznie zaplecze techniczne do sources/_oryginaly/), wykonaj W0 i zapisz W0_DECISION; inicjalizacja nie jest PASS bramki W0.'
}
