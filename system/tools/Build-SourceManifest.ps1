[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectPath,

    [switch]$Write,
    [switch]$Force,
    [scriptblock]$InternalBeforeManifestReplaceTestHook
)

# Awaryjny manifest logicznych źródeł dla aktualnego schematu K1.
# Jedno logiczne źródło = jeden kanoniczny plik tekstowy w sources/ (najlepiej .md).
# Zaplecze w sources/_oryginaly/ nie jest rozliczane jednostkowo.
# Narzędzie niczego nie konwertuje i nie czyta semantycznie treści.

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project | Out-Null
if ($null -ne $InternalBeforeManifestReplaceTestHook) {
    $callerPath = if ($MyInvocation.ScriptName) { [IO.Path]::GetFullPath($MyInvocation.ScriptName) } else { '' }
    $allowedTestCaller = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Test-System.ps1'))
    if (-not $callerPath.Equals($allowedTestCaller, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'INTERNAL_MANIFEST_REPLACE_TEST_HOOK_UNAUTHORIZED'
    }
}
$metaPath = Join-Path $project 'meta.md'
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "PROJECT_META_MISSING: $metaPath" }
$metaForAuthorization = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$workflowRevision = Get-DocumentField -Text $metaForAuthorization -Name 'WORKFLOW_REVISION'
$k1LiteV2WorkflowRevisions = @('2026-08-31_NARRATIVE_V2','2026-08-30_K1_LITE_V2')
if ($Write) {
    $originAuthorization = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $metaForAuthorization
} elseif ($workflowRevision -in $k1LiteV2WorkflowRevisions) {
    $originAuthorization = Assert-SystemV7CurrentProjectOrigin -ProjectPath $project -MetaText $metaForAuthorization
}
$projectLock = if ($Write) { Enter-SystemV7ProjectMetaLock -ProjectPath $project } else { $null }
try {
if ($Write) {
    $metaForAuthorization = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $workflowRevision = Get-DocumentField -Text $metaForAuthorization -Name 'WORKFLOW_REVISION'
    $originAuthorization = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $metaForAuthorization
}
if ($workflowRevision -in $k1LiteV2WorkflowRevisions) {
    $fallbackState = Get-K1ManualFallbackReceiptState -ProjectPath $project
    if (-not $fallbackState.Valid) { throw "K1_MANUAL_FALLBACK_NOT_AUTHORIZED: $($fallbackState.Errors -join '; ')" }
    $fallbackAuthorization = [pscustomobject]@{ Required=$true; Valid=$true; ReceiptPath=$fallbackState.ReceiptPath; ReceiptSha256=$fallbackState.ReceiptSha256 }
} else {
    $fallbackAuthorization = Assert-K1ManualFallbackAuthorized -ProjectPath $project
}
$sourceDir = Join-Path $project 'sources'
$outputDir = Join-Path $project '_work\K1'
$outputPath = Join-Path $outputDir 'manifest-zrodel.generated.md'
$backupDirName = '_oryginaly'
$canonicalExtensions = @('.md', '.txt')

if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) {
    throw "Brak katalogu sources/: $sourceDir"
}

function Get-HeaderValue {
    param([string[]]$Lines, [string]$Name)
    $limit = [Math]::Min(30, $Lines.Count)
    for ($i = 0; $i -lt $limit; $i++) {
        $match = [regex]::Match($Lines[$i], "^\s*$([regex]::Escape($Name)):\s*(.+?)\s*$")
        if ($match.Success) { return $match.Groups[1].Value }
    }
    return $null
}

function Get-SourceTreeSnapshot {
    $snapshotFiles = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File | Sort-Object FullName)
    return (@($snapshotFiles | ForEach-Object {
        $snapshotRelative = [IO.Path]::GetRelativePath($sourceDir, $_.FullName).Replace('\','/')
        "$snapshotRelative|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    }) -join "`n")
}

$allFiles = @(Get-ChildItem -LiteralPath $sourceDir -Recurse -File | Sort-Object FullName)
$sourceSnapshot = Get-SourceTreeSnapshot
$generatedEvidenceArtifacts = @($allFiles | Where-Object {
    $_.Name -ieq '01-baza-dowodow.md' -or
    $_.Name -like 'K1-COMPILED-*.md' -or
    $_.Name -like '.K1-COMPILED-*.partial'
})
if ($generatedEvidenceArtifacts.Count -gt 0) {
    $relativeArtifacts = @($generatedEvidenceArtifacts | ForEach-Object {
        [IO.Path]::GetRelativePath($sourceDir, $_.FullName).Replace('\','/')
    })
    throw "W sources/ znaleziono artefakt bazy dowodów, który nie może być źródłem: $($relativeArtifacts -join ', '). Przenieś plik poza sources/; niczego nie zmieniono."
}
$canonical = [System.Collections.Generic.List[object]]::new()
$backupCount = 0
$backupBytes = [long]0
$otherFiles = [System.Collections.Generic.List[string]]::new()
$firstByHash = @{}

foreach ($file in $allFiles) {
    $relative = [IO.Path]::GetRelativePath($sourceDir, $file.FullName).Replace('\','/')
    if ($relative -like "$backupDirName/*") {
        $backupCount++
        $backupBytes += $file.Length
        continue
    }
    $isCanonical = $file.Extension.ToLowerInvariant() -in $canonicalExtensions
    if (-not $isCanonical) {
        $otherFiles.Add($relative)
    }

    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $duplicateOf = $null
    if ($firstByHash.ContainsKey($hash)) {
        $duplicateOf = $firstByHash[$hash]
    } else {
        $firstByHash[$hash] = $relative
    }

    $lineCount = 0
    $title = $null; $author = $null; $date = $null; $type = $null
    if ($isCanonical) {
        $lines = [IO.File]::ReadAllLines($file.FullName)
        $lineCount = $lines.Count
        $title = Get-HeaderValue -Lines $lines -Name 'ŹRÓDŁO-TYTUŁ'
        $author = Get-HeaderValue -Lines $lines -Name 'ŹRÓDŁO-AUTOR'
        $date = Get-HeaderValue -Lines $lines -Name 'ŹRÓDŁO-DATA'
        $type = Get-HeaderValue -Lines $lines -Name 'ŹRÓDŁO-TYP'
    }

    $canonical.Add([pscustomobject]@{
        File = $relative
        Bytes = $file.Length
        Lines = $lineCount
        Canonical = $isCanonical
        SHA256 = $hash
        ExactDuplicateOf = $duplicateOf
        Title = $title
        Author = $author
        Date = $date
        Type = $type
    })
}

$duplicateCount = @($canonical | Where-Object { $_.ExactDuplicateOf }).Count

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# K1A — GENEROWANY MANIFEST LOGICZNYCH ŹRÓDEŁ')
$lines.Add('')
$lines.Add('STATUS: TECHNICZNY — NIE JEST KANONICZNĄ BAZĄ DOWODÓW')
$lines.Add("SCHEMAT: MINIMAL_EVIDENCE_V4_PAGELOC")
$lines.Add("ŹRÓDŁA_KANONICZNE: $(@($canonical | Where-Object Canonical).Count)")
$lines.Add("PLIKI_NIEKANONICZNE_POZA_ZAPLECZEM: $($otherFiles.Count)")
$lines.Add("PLIKI_ZAPLECZA (_oryginaly/): $backupCount ($([Math]::Round($backupBytes / 1MB, 1)) MiB)")
$lines.Add("DOKŁADNE_DUPLIKATY: $duplicateCount")
$lines.Add('')
$lines.Add('Hash liczony per źródło. Zmiana jednego pliku unieważnia wyłącznie jego rekord i karty.')
$lines.Add('Wiersze poniżej wklej do rejestru w `01-baza-dowodow.md` i uzupełnij rolę oraz metadane.')
$lines.Add('')
$lines.Add('| ID | Plik/URL i zaplecze | Autor/instytucja | Data | Klasa A–D | Rola | Zakres sprawdzony | SHA-256 źródła | Karty/wynik | Uwagi |')
$lines.Add('|---|---|---|---|---|---|---|---|---|---|')
$index = 0
foreach ($record in $canonical | Where-Object Canonical) {
    $index++
    $id = '#S-{0:d3}' -f $index
    $safeFile = $record.File.Replace('|','\|')
    $author = if ($record.Author) { $record.Author.Replace('|','\|') } else { 'NIEUSTALONE' }
    $date = if ($record.Date) { $record.Date.Replace('|','\|') } else { 'NIEUSTALONE' }
    $note = if ($record.ExactDuplicateOf) { "Dokładny duplikat: $($record.ExactDuplicateOf.Replace('|','\|'))" } elseif ($record.Title) { $record.Title.Replace('|','\|') } else { 'BRAK' }
    $lines.Add("| $id | $safeFile | $author | $date |  |  |  | $($record.SHA256) |  | $note |")
}
if ($otherFiles.Count -gt 0) {
    $lines.Add('')
    $lines.Add('## Pliki niekanoniczne poza `_oryginaly/`')
    $lines.Add('')
    $lines.Add('Docelowo: przenieś do `sources/_oryginaly/` albo rozlicz jawnie w rejestrze (np. rolą TECHNICZNE lub wierszem `katalog/**`).')
    $lines.Add('')
    foreach ($other in $otherFiles) { $lines.Add("- $other") }
}
$markdown = $lines -join "`r`n"

function Invoke-ManifestFileReplaceWithRetry {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$BackupPath,
        [scriptblock]$BeforeAttempt,
        [ValidateRange(1,10)][int]$MaxAttempts=5
    )
    for($attempt=1;$attempt -le $MaxAttempts;$attempt++){
        if($null -ne $BeforeAttempt){&$BeforeAttempt}
        try{
            [IO.File]::Replace($SourcePath,$DestinationPath,$BackupPath,$true)
            return
        }catch [IO.IOException]{
            $nativeCode=$_.Exception.HResult -band 0xFFFF
            if($nativeCode -notin @(32,33) -or $attempt -ge $MaxAttempts){throw}
            [Threading.Thread]::Sleep(20*$attempt)
        }
    }
}

function Write-ManifestAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][bool]$ReplaceExisting,
        [Parameter(Mandatory)][string]$ExpectedSourceSnapshot,
        [Parameter(Mandatory)][scriptblock]$SourceSnapshotProvider,
        [scriptblock]$BeforeReplaceTestHook
    )
    $target = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $target
    Assert-SystemV7PathNoReparse -Path $directory -ContainmentRoot $project | Out-Null
    Assert-SystemV7PathNoReparse -Path $target -ContainmentRoot $project | Out-Null
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "MANIFEST_DIRECTORY_MISSING: $directory" }
    $exists = Test-Path -LiteralPath $target
    if ($exists -and -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "MANIFEST_TARGET_NOT_FILE: $target" }
    if ($exists -and -not $ReplaceExisting) { throw "MANIFEST_ALREADY_EXISTS: $target" }
    $targetBeforeSha = if ($exists) { (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash } else { $null }

    $expectedSha = Get-Sha256HexFromBytes -Bytes $Bytes
    $tempPath = Join-Path $directory ('.manifest-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $displacedPath = Join-Path $directory ('.manifest-' + [guid]::NewGuid().ToString('N') + '.displaced')
    $failedCandidatePath = Join-Path $directory ('.manifest-' + [guid]::NewGuid().ToString('N') + '.failed')
    $stream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    try {
        if ((Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash -cne $expectedSha) { throw 'MANIFEST_STAGED_HASH_MISMATCH' }
        if ($null -ne $BeforeReplaceTestHook) { & $BeforeReplaceTestHook }
        # Ostatnia kontrola musi następować po hooku i bezpośrednio przed
        # atomową podmianą. W przeciwnym razie manifest może opisywać starszy
        # stan korpusu, mimo że sam plik docelowy zapisze się poprawnie.
        if ((& $SourceSnapshotProvider) -cne $ExpectedSourceSnapshot) {
            throw 'SOURCE_TREE_CHANGED_DURING_MANIFEST_COMMIT'
        }
        if ($exists) {
            # File.Replace podmienia wyłącznie wpis katalogowy. Jeżeli stary plik był
            # hardlinkiem, pozostałe linki zachowują stare bajty i nie są modyfikowane.
            Invoke-ManifestFileReplaceWithRetry -SourcePath $tempPath -DestinationPath $target -BackupPath $displacedPath -BeforeAttempt {
                if ((& $SourceSnapshotProvider) -cne $ExpectedSourceSnapshot) { throw 'SOURCE_TREE_CHANGED_DURING_MANIFEST_COMMIT' }
            }
            $displacedSha = (Get-FileHash -LiteralPath $displacedPath -Algorithm SHA256).Hash
            if ($displacedSha -cne $targetBeforeSha) {
                $targetAfterConflictSha = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
                if ($targetAfterConflictSha -ceq $expectedSha) {
                    Invoke-ManifestFileReplaceWithRetry -SourcePath $displacedPath -DestinationPath $target -BackupPath $failedCandidatePath -BeforeAttempt {
                        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $expectedSha) { throw 'MANIFEST_ROLLBACK_TARGET_CHANGED' }
                    }
                    if (Test-Path -LiteralPath $failedCandidatePath -PathType Leaf) { [IO.File]::Delete($failedCandidatePath) }
                    throw "MANIFEST_COMPARE_AND_SWAP_CONFLICT_ROLLED_BACK: expected_preimage=$targetBeforeSha displaced=$displacedSha"
                }
                throw "MANIFEST_COMPARE_AND_SWAP_CONFLICT_PRESERVED: expected_preimage=$targetBeforeSha displaced=$displacedSha recovery=$displacedPath"
            }
        } else {
            [IO.File]::Move($tempPath, $target)
        }
        # Zewnętrzne programy nie respektują blokady projektu. Kontrola po
        # podmianie zamyka okno między ostatnim snapshotem i operacją katalogową;
        # przy zmianie korpusu przywracamy poprzedni manifest albo usuwamy nowy.
        if ((& $SourceSnapshotProvider) -cne $ExpectedSourceSnapshot) {
            if ($exists -and (Test-Path -LiteralPath $displacedPath -PathType Leaf)) {
                if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ceq $expectedSha) {
                    Invoke-ManifestFileReplaceWithRetry -SourcePath $displacedPath -DestinationPath $target -BackupPath $failedCandidatePath -BeforeAttempt {
                        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $expectedSha) { throw 'MANIFEST_ROLLBACK_TARGET_CHANGED' }
                    }
                    if (Test-Path -LiteralPath $failedCandidatePath -PathType Leaf) { [IO.File]::Delete($failedCandidatePath) }
                    throw 'SOURCE_TREE_CHANGED_DURING_MANIFEST_COMMIT_ROLLED_BACK'
                }
                throw "SOURCE_TREE_CHANGED_DURING_MANIFEST_COMMIT_PRESERVED: recovery=$displacedPath"
            }
            if (-not $exists -and (Test-Path -LiteralPath $target -PathType Leaf)) {
                if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ceq $expectedSha) {
                    [IO.File]::Delete($target)
                    throw 'SOURCE_TREE_CHANGED_DURING_MANIFEST_COMMIT_ROLLED_BACK'
                }
                throw 'SOURCE_TREE_CHANGED_DURING_MANIFEST_COMMIT_PRESERVED'
            }
            throw 'SOURCE_TREE_CHANGED_DURING_MANIFEST_COMMIT'
        }
        Assert-SystemV7PathNoReparse -Path $target -ContainmentRoot $project | Out-Null
        $actualSha = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($actualSha -cne $expectedSha) {
            if ($exists -and (Test-Path -LiteralPath $displacedPath -PathType Leaf)) {
                # Przy zmianie zewnętrznej nie nadpisujemy jej po cichu. Zachowujemy
                # preimage obok celu do jawnego odzyskania.
                if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ceq $expectedSha) {
                    Invoke-ManifestFileReplaceWithRetry -SourcePath $displacedPath -DestinationPath $target -BackupPath $failedCandidatePath -BeforeAttempt {
                        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $expectedSha) { throw 'MANIFEST_ROLLBACK_TARGET_CHANGED' }
                    }
                }
            } elseif (-not $exists -and (Test-Path -LiteralPath $target -PathType Leaf)) {
                [IO.File]::Delete($target)
            }
            throw "MANIFEST_POSTVALIDATION_FAILED: expected=$expectedSha actual=$actualSha"
        }
        if (Test-Path -LiteralPath $displacedPath -PathType Leaf) { [IO.File]::Delete($displacedPath) }
        if (Test-Path -LiteralPath $failedCandidatePath -PathType Leaf) { [IO.File]::Delete($failedCandidatePath) }
    } finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) { [IO.File]::Delete($tempPath) }
    }
}

$mode = 'PREVIEW'
if ($Write) {
    Assert-SystemV7PathNoReparse -Path $outputDir -ContainmentRoot $project | Out-Null
    if (-not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }
    Assert-SystemV7PathNoReparse -Path $outputDir -ContainmentRoot $project | Out-Null
    if ((Test-Path -LiteralPath $outputPath -PathType Leaf) -and -not $Force) {
        throw "Manifest już istnieje; użyj -Force po sprawdzeniu podglądu: $outputPath"
    }
    $currentSourceSnapshot = Get-SourceTreeSnapshot
    if ($currentSourceSnapshot -cne $sourceSnapshot) { throw 'SOURCE_TREE_CHANGED_DURING_MANIFEST_BUILD' }
    $manifestBytes = [Text.UTF8Encoding]::new($false).GetBytes($markdown)
    Write-ManifestAtomic -Path $outputPath -Bytes $manifestBytes -ReplaceExisting ([bool]$Force) `
        -ExpectedSourceSnapshot $sourceSnapshot -SourceSnapshotProvider ${function:Get-SourceTreeSnapshot} `
        -BeforeReplaceTestHook $InternalBeforeManifestReplaceTestHook
    $mode = 'WRITE'
}

[pscustomobject]@{
    ProjectPath = $project
    Mode = $mode
    CanonicalSources = @($canonical | Where-Object Canonical).Count
    NonCanonicalFiles = $otherFiles.Count
    BackupFiles = $backupCount
    ExactDuplicates = $duplicateCount
    OutputPath = $outputPath
    Records = $canonical
    Markdown = $markdown
}
} finally {
    if ($Write) { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
}
