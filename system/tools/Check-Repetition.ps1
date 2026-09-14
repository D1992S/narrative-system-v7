[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [ValidateRange(4, 20)]
    [int]$PhraseLength = 8
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$metaPath = Join-Path $project 'meta.md'
if(Test-Path -LiteralPath $metaPath -PathType Leaf){
    . (Join-Path $PSScriptRoot 'Project-Origin.ps1')
    . (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
    $metaText=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    if(Test-SystemV7NarrativeV2Revision -MetaText $metaText){
        $state=Get-SystemV7NarrativeMoveRepetitionState -ProjectPath $project
        [pscustomobject]@{
            WorkflowRevision=$script:SystemV7NarrativeWorkflowRevision;Verdict=$state.ReviewStatus;GateReady=$state.GateReady
            ReviewAlerts=@($state.ReviewAlerts);HistorySha256=$state.HistorySha256;DecisionPath=$state.DecisionPath;DecisionSha256=$state.DecisionSha256;Errors=@($state.Errors)
            NextAction=if($state.GateReady){'BRAK'}else{'Dawid przegląda powtórzone typy ruchów; świadome powtórzenie zatwierdza Approve-NarrativeMoveRepetition.ps1.'}
        }
        return
    }
}
$draftPath = Join-Path $project '03-draft.md'
if (-not (Test-Path -LiteralPath $draftPath -PathType Leaf)) {
    throw "Brak pliku: $draftPath"
}

$raw = Get-Content -LiteralPath $draftPath -Raw -Encoding UTF8
$parts = [regex]::Split($raw, '(?m)^---\s*$')
if ($parts.Count -lt 2) { throw 'Draft nie ma separatora --- oddzielającego narrację od nagłówka.' }
$narr = ($parts | Select-Object -Skip 1) -join "`n"

# Podział na sekcje po nagłówkach ## (HOOK, AKT 1, ...)
$sections = [ordered]@{}
$current = '(przed pierwszym nagłówkiem)'
$sb = New-Object System.Text.StringBuilder
foreach ($line in ($narr -split "`n")) {
    $m = [regex]::Match($line, '^\s*##\s+(.+?)\s*$')
    if ($m.Success) {
        if ($sb.ToString().Trim().Length -gt 0) { $sections[$current] = $sb.ToString() }
        $current = $m.Groups[1].Value
        $sb = New-Object System.Text.StringBuilder
    } else {
        [void]$sb.AppendLine($line)
    }
}
if ($sb.ToString().Trim().Length -gt 0) { $sections[$current] = $sb.ToString() }

if ($sections.Count -lt 2) {
    [pscustomobject]@{
        Sections = $sections.Count
        Info = 'Za mało sekcji (## HOOK / ## AKT ...) do porównania.'
    }
    return
}

# 1) Karty #P używane w więcej niż jednej sekcji
$cardMap = @{}
foreach ($name in $sections.Keys) {
    foreach ($m in [regex]::Matches($sections[$name], '#P-\d+')) {
        $id = $m.Value
        if (-not $cardMap.ContainsKey($id)) { $cardMap[$id] = New-Object 'System.Collections.Generic.List[string]' }
        if (-not $cardMap[$id].Contains($name)) { $cardMap[$id].Add($name) }
    }
}
$sharedCards = @()
foreach ($id in $cardMap.Keys) {
    if ($cardMap[$id].Count -ge 2) { $sharedCards += "$id → " + ($cardMap[$id] -join ', ') }
}

# 2) Powtórzone frazy o długości N słów między sekcjami
function Get-WordList {
    param([string]$Text)
    $t = [regex]::Replace($Text, '<!--[\s\S]*?-->', ' ')
    $t = [regex]::Replace($t, '[`*_\[\]{}()>#|]', ' ')
    $out = foreach ($m in [regex]::Matches($t, "[\p{L}\p{N}]+(?:[-'’][\p{L}\p{N}]+)*")) { $m.Value.ToLowerInvariant() }
    return @($out)
}

$phraseSets = @{}
foreach ($name in $sections.Keys) {
    $w = Get-WordList $sections[$name]
    $set = [System.Collections.Generic.HashSet[string]]::new()
    for ($i = 0; $i -le $w.Count - $PhraseLength; $i++) {
        [void]$set.Add(($w[$i..($i + $PhraseLength - 1)] -join ' '))
    }
    $phraseSets[$name] = $set
}

$dupes = @()
$names = @($sections.Keys)
for ($i = 0; $i -lt $names.Count; $i++) {
    for ($j = $i + 1; $j -lt $names.Count; $j++) {
        $inter = [System.Collections.Generic.HashSet[string]]::new($phraseSets[$names[$i]])
        $inter.IntersectWith($phraseSets[$names[$j]])
        if ($inter.Count -gt 0) {
            $example = ($inter | Select-Object -First 1)
            $dupes += "$($names[$i]) ↔ $($names[$j]): $($inter.Count) wspólnych fraz po $PhraseLength słów, np. '$example'"
        }
    }
}

[pscustomobject]@{
    Sections = ($names -join ' | ')
    SharedCards = if ($sharedCards) { $sharedCards } else { @('BRAK') }
    RepeatedPhrases = if ($dupes) { $dupes } else { @('BRAK') }
    Note = 'Wspólna karta bywa celowym callbackiem — oceń, czy powtórzenie zmienia znaczenie. Powtórzone frazy przepisz albo usuń.'
}
