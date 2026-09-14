[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [switch]$Write,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$sourceDir = Join-Path $project 'sources'
$outputDir = Join-Path $project '_work\K1'
$outputPath = Join-Path $outputDir 'source-inventory.generated.md'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')

$projectLock = if ($Write) { Enter-SystemV7ProjectMetaLock -ProjectPath $project } else { $null }
try {

function Get-TextSha256 {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','')
    } finally {
        $sha.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
    throw "Brak katalogu sources/: $sourceDir"
}

$files = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File | Sort-Object FullName)
$records = [System.Collections.Generic.List[object]]::new()
$firstByHash = @{}

foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($sourceDir, $file.FullName).Replace('\','/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $duplicateOf = $null
    if ($firstByHash.ContainsKey($hash)) {
        $duplicateOf = $firstByHash[$hash]
    } else {
        $firstByHash[$hash] = $relative
    }
    $records.Add([pscustomobject]@{
        File = $relative
        Bytes = $file.Length
        Type = if ($file.Extension) { $file.Extension.TrimStart('.').ToUpperInvariant() } else { 'BRAK' }
        SHA256 = $hash
        ExactDuplicateOf = $duplicateOf
    })
}

$duplicateCount = @($records | Where-Object { $_.ExactDuplicateOf }).Count
$sourceTreePayload = @($records | ForEach-Object { "$($_.File)`t$($_.Bytes)`t$($_.SHA256)" }) -join "`n"
$sourceTreeSha256 = Get-TextSha256 -Text $sourceTreePayload
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# K1A — GENEROWANY INWENTARZ PLIKÓW ŹRÓDŁOWYCH')
$lines.Add('')
$lines.Add('STATUS: TECHNICZNY — NIE JEST KANONICZNĄ BAZĄ DOWODÓW')
$lines.Add("FILES: $($records.Count)")
$lines.Add("UNIQUE_HASHES: $($firstByHash.Count)")
$lines.Add("EXACT_DUPLICATES: $duplicateCount")
$lines.Add("SOURCE_TREE_SHA256: $sourceTreeSha256")
$lines.Add('')
$lines.Add('Każdy wiersz opisuje plik. W K1A człowiek lub ChatGPT scala oryginał i ekstrakty techniczne w jeden logiczny rekord `#S` w `01-baza-dowodow.md`.')
$lines.Add('')
$lines.Add('| Plik w sources/ | Bajty | Typ | SHA-256 | Dokładny duplikat pliku |')
$lines.Add('|---|---:|---|---|---|')
foreach ($record in $records) {
    $safeFile = $record.File.Replace('|','\|')
    $safeDuplicate = if ($record.ExactDuplicateOf) { $record.ExactDuplicateOf.Replace('|','\|') } else { 'BRAK' }
    $lines.Add("| $safeFile | $($record.Bytes) | $($record.Type) | $($record.SHA256) | $safeDuplicate |")
}
$markdown = $lines -join "`r`n"

$mode = 'PREVIEW'
if ($Write) {
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }
    if ((Test-Path -LiteralPath $outputPath -PathType Leaf) -and -not $Force) {
        throw "Inwentarz już istnieje; użyj -Force po sprawdzeniu podglądu: $outputPath"
    }
    Set-Content -LiteralPath $outputPath -Value $markdown -Encoding UTF8
    $mode = 'WRITE'
}

[pscustomobject]@{
    ProjectPath = $project
    Mode = $mode
    Files = $records.Count
    UniqueHashes = $firstByHash.Count
    ExactDuplicates = $duplicateCount
    SourceTreeSha256 = $sourceTreeSha256
    OutputPath = $outputPath
    Records = $records
    Markdown = $markdown
}
} finally {
    if ($Write) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
}
