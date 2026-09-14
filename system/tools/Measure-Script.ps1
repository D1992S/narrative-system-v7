[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath,

    [ValidateRange(60, 240)]
    [double]$WordsPerMinute = 130,

    [string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$path = [IO.Path]::GetFullPath($ScriptPath)
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Brak pliku: $path"
}

# Tempo i budżet czyta się z meta.md projektu: jawnie podanego albo z katalogu pliku.
$metaDir = if ($ProjectPath) { [IO.Path]::GetFullPath($ProjectPath) } else { Split-Path -Parent $path }
$metaPath = Join-Path $metaDir 'meta.md'
$metaFound = Test-Path -LiteralPath $metaPath -PathType Leaf
$channel = $null
$targetMinutes = $null
$durationMode = $null
$workflowRevision = $null
$wpmSource = if ($PSBoundParameters.ContainsKey('WordsPerMinute')) { 'parametr' } else { 'domyślne 130' }

if ($metaFound) {
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $channel = [regex]::Match($meta, '(?m)^CHANNEL:\s*(\S+)').Groups[1].Value
    $workflowRevision = [regex]::Match($meta, '(?m)^WORKFLOW_REVISION:\s*(\S+)').Groups[1].Value
    $durationMode = [regex]::Match($meta, '(?m)^TARGET_DURATION_MODE:\s*(\S+)').Groups[1].Value
    $tm = [regex]::Match($meta, '(?m)^TARGET_MINUTES:\s*(\d+)').Groups[1].Value
    if ($tm) { $targetMinutes = [int]$tm }
    if (-not $PSBoundParameters.ContainsKey('WordsPerMinute')) {
        $metaWpm = [regex]::Match($meta, '(?m)^REAL_WPM:\s*(\d+)').Groups[1].Value
        if ($metaWpm -and [int]$metaWpm -ge 60 -and [int]$metaWpm -le 240) {
            $WordsPerMinute = [int]$metaWpm
            $wpmSource = 'meta.md'
        }
    }
}

$rawText = Get-Content -LiteralPath $path -Raw -Encoding UTF8
$text = $rawText

# Narracja zaczyna się po pierwszym separatorze; bez separatora usuwa się linie metadanych.
$parts = [regex]::Split($text, '(?m)^---\s*$')
if ($parts.Count -gt 1) {
    $text = ($parts | Select-Object -Skip 1) -join "`n"
} else {
    $text = [regex]::Replace($text, '(?m)^[A-ZĄĆĘŁŃÓŚŹŻ][A-ZĄĆĘŁŃÓŚŹŻ0-9_ /-]*:\s*.*$', ' ')
}

$text = [regex]::Replace($text, '<!--[\s\S]*?-->', ' ')
$text = [regex]::Replace($text, '(?m)^#{1,6}\s+.*$', ' ')
$text = [regex]::Replace($text, '(?m)^\s*\|.*\|\s*$', ' ')
$text = [regex]::Replace($text, '(?m)^\s*\[[^\]]*\]\s*$', ' ')
$text = [regex]::Replace($text, '[`*_\[\]{}()>#]', ' ')

# Liczba typu 3,5 albo 1.000.000 to jedno słowo; COVID-19 i d'Artagnan również.
$wordMatches = [regex]::Matches($text, "[\p{L}\p{N}]+(?:[-'’][\p{L}\p{N}]+)*(?:[.,]\p{N}+)*")
$wordCount = $wordMatches.Count
if ($workflowRevision -eq '2026-08-31_NARRATIVE_V2') {
    . (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
    if ($rawText -match '(?m)^## NARRACJA ROBOCZA\s*$') {
        $narration=Get-SystemV7CleanNarrationFromDraft -DraftText $rawText
    } elseif ($rawText -match '(?ms)^## NARRACJA DO NAGRANIA\r?\n(?<body>.*)\z') {
        $narration=$Matches.body
    } else { $narration=$rawText }
    $measurement=Get-SystemV7DurationState -Narration $narration -TargetMinutes ([math]::Max(1,[int]$targetMinutes)) -RealWpm ([int]$WordsPerMinute) -Mode GUIDE
    $wordCount=$measurement.WordCount
}
$minutes = if ($WordsPerMinute -gt 0) { $wordCount / $WordsPerMinute } else { 0 }
$duration = [TimeSpan]::FromMinutes($minutes)

$result = [ordered]@{
    ScriptPath = $path
    WordCount = $wordCount
    WordsPerMinute = $WordsPerMinute
    WpmSource = $wpmSource
    Duration = ('{0:00}:{1:00}:{2:00}' -f [math]::Floor($duration.TotalHours), $duration.Minutes, $duration.Seconds)
    DurationMinutes = [math]::Round($minutes, 2)
}
if ($channel) { $result.Channel = $channel }
if ($targetMinutes) {
    $result.TargetMinutes = $targetMinutes
    if ($workflowRevision -eq '2026-08-31_NARRATIVE_V2') {
        if ($durationMode -notin @('GUIDE','HARD_MAX')) { throw "TARGET_DURATION_MODE_INVALID: $durationMode" }
        $result.TargetDurationMode = $durationMode
        $result.TargetDeltaMinutes = [math]::Round($minutes - $targetMinutes, 2)
        $result.HardMaxPass = ($durationMode -eq 'GUIDE' -or $minutes -le $targetMinutes)
        $result.GuideAlert = ($durationMode -eq 'GUIDE' -and [math]::Abs($minutes - $targetMinutes) -ge [math]::Max(2, $targetMinutes * 0.25))
    } else {
        $budgetWords = [int][math]::Round($targetMinutes * $WordsPerMinute)
        $result.BudgetWords = $budgetWords
        $result.BudgetPercent = [math]::Round(100.0 * $wordCount / [math]::Max($budgetWords, 1), 1)
    }
}
[pscustomobject]$result
