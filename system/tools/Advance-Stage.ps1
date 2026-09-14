[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ProjectPath,
    [string]$PythonPath = 'python.exe',
    [switch]$Apply,
    [switch]$DawidApproved
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
$metaPath = Join-Path $project 'meta.md'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
. (Join-Path $PSScriptRoot 'Project-Origin.ps1')
. (Join-Path $PSScriptRoot 'Narrative-V2.ps1')
Assert-SystemV7NarrativeInstructionContractIfV2 -ProjectPath $project | Out-Null

function ConvertTo-TransitionPathToken {
    param([Parameter(Mandatory)][string]$RelativePath)
    return [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($RelativePath))
}

function Test-TransitionInputExcluded {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][bool]$IsDirectory
    )

    $relative = $RelativePath.Replace('\','/')
    if (-not $IsDirectory -and $relative.Equals('meta.md', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if (-not $IsDirectory -and $relative.Equals('.system-v7/meta-write.lock', [StringComparison]::OrdinalIgnoreCase)) { return $true }

    # Journal meta jest skutkiem samego commitu. Wykluczenie jest ograniczone
    # do jednego zarezerwowanego poddrzewa; podobne nazwy w sources nadal są wejściem.
    if ($relative -match '^\.system-v7/meta-transactions(?:/|$)') { return $true }
    return $false
}

function Get-TransitionInputInventory {
    $directories = [Collections.Generic.List[string]]::new()
    $files = [Collections.Generic.List[object]]::new()
    $directories.Add('.')

    foreach ($item in @(Get-ChildItem -LiteralPath $project -Force -Recurse -ErrorAction Stop)) {
        $relative = ([IO.Path]::GetRelativePath($project, $item.FullName)).Replace('\','/')
        $isDirectory = $item.PSIsContainer
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "PROJECT_INPUT_REPARSE_POINT_BLOCKED: $relative"
        }
        if (Test-TransitionInputExcluded -RelativePath $relative -IsDirectory $isDirectory) { continue }
        if ($isDirectory) {
            $directories.Add($relative)
        } else {
            $files.Add([pscustomobject]@{ Relative=$relative; FullName=$item.FullName })
        }
    }

    $directoryArray = $directories.ToArray()
    [Array]::Sort($directoryArray, [StringComparer]::Ordinal)
    $fileArray = $files.ToArray()
    [Array]::Sort($fileArray, [Comparison[object]]{
        param($left, $right)
        [StringComparer]::Ordinal.Compare([string]$left.Relative, [string]$right.Relative)
    })
    return [pscustomobject]@{ Directories=$directoryArray; Files=$fileArray }
}

function Get-TransitionInventoryIdentity {
    param([Parameter(Mandatory)][object]$Inventory)
    $rows = [Collections.Generic.List[string]]::new()
    foreach ($relative in @($Inventory.Directories)) {
        $rows.Add("D`t$(ConvertTo-TransitionPathToken -RelativePath $relative)")
    }
    foreach ($file in @($Inventory.Files)) {
        $rows.Add("F`t$(ConvertTo-TransitionPathToken -RelativePath ([string]$file.Relative))")
    }
    return Get-Sha256HexFromText -Text ("SYSTEM_V7_TRANSITION_INPUT_SET_V1`n" + ($rows -join "`n") + "`n")
}

function Enter-TransitionInputReadBarrier {
    $inventoryBefore = Get-TransitionInputInventory
    $handles = [Collections.Generic.List[object]]::new()
    try {
        foreach ($file in @($inventoryBefore.Files)) {
            # FileShare.Read pozwala walidatorom czytać, ale blokuje zapis, kasowanie
            # i atomiczną podmianę istniejącego wejścia do końca przejścia.
            $stream = [IO.File]::Open(
                [string]$file.FullName,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::Read
            )
            $handles.Add([pscustomobject]@{
                Relative=[string]$file.Relative
                FullName=[string]$file.FullName
                Stream=$stream
            })
        }

        $inventoryAfter = Get-TransitionInputInventory
        $identityBefore = Get-TransitionInventoryIdentity -Inventory $inventoryBefore
        $identityAfter = Get-TransitionInventoryIdentity -Inventory $inventoryAfter
        if ($identityAfter -ne $identityBefore) { throw 'PROJECT_INPUT_SET_CHANGED_WHILE_ACQUIRING_READ_BARRIER' }

        return [pscustomobject]@{
            Directories=@($inventoryBefore.Directories)
            Files=$handles.ToArray()
            InventoryIdentity=$identityBefore
        }
    } catch {
        foreach ($handle in @($handles)) {
            if ($null -ne $handle.Stream) { $handle.Stream.Dispose() }
        }
        throw
    }
}

function Exit-TransitionInputReadBarrier {
    param([AllowNull()][object]$Barrier)
    if ($null -eq $Barrier) { return }
    foreach ($file in @($Barrier.Files)) {
        if ($null -ne $file.Stream) { $file.Stream.Dispose() }
    }
}

function Get-TransitionInputSnapshot {
    param([Parameter(Mandatory)][object]$Barrier)

    $inventoryBeforeHash = Get-TransitionInputInventory
    $identityBeforeHash = Get-TransitionInventoryIdentity -Inventory $inventoryBeforeHash
    if ($identityBeforeHash -ne $Barrier.InventoryIdentity) { throw 'PROJECT_INPUT_SET_CHANGED_AFTER_READ_BARRIER' }

    $rows = [Collections.Generic.List[string]]::new()
    foreach ($relative in @($Barrier.Directories)) {
        $rows.Add("D`t$(ConvertTo-TransitionPathToken -RelativePath $relative)")
    }
    foreach ($file in @($Barrier.Files)) {
        $stream = [IO.FileStream]$file.Stream
        $stream.Position = 0
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $contentSha = [Convert]::ToHexString($sha.ComputeHash($stream)) }
        finally { $sha.Dispose() }
        $rows.Add("F`t$(ConvertTo-TransitionPathToken -RelativePath ([string]$file.Relative))`t$($stream.Length)`t$contentSha")
    }
    # Nowy plik lub katalog mógł powstać w czasie haszowania dużego PDF-a.
    # Drugi odczyt struktury sprawia, że taki wyścig również kończy operację.
    $inventoryAfterHash = Get-TransitionInputInventory
    $identityAfterHash = Get-TransitionInventoryIdentity -Inventory $inventoryAfterHash
    if ($identityAfterHash -ne $Barrier.InventoryIdentity) { throw 'PROJECT_INPUT_SET_CHANGED_DURING_MANIFEST_HASHING' }
    return Get-Sha256HexFromText -Text ("SYSTEM_V7_TRANSITION_INPUT_MANIFEST_V2`n" + ($rows -join "`n") + "`n")
}

$projectLock = $null
$inputBarrier = $null
$transitionMetaTransaction = $null
try {
$projectLock = Enter-SystemV7ProjectMetaLock -ProjectPath $project
if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "META_MISSING: $metaPath" }
$metaItem = Get-Item -LiteralPath $metaPath -Force
if (($metaItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'META_REPARSE_POINT_BLOCKED' }
$metaBytesBeforeValidation = [IO.File]::ReadAllBytes($metaPath)
$metaShaBeforeValidation = Get-Sha256HexFromBytes -Bytes $metaBytesBeforeValidation
$metaBeforeValidation = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
$null = Assert-SystemV7MutableProjectOrigin -ProjectPath $project -MetaText $metaBeforeValidation
$inputBarrier = Enter-TransitionInputReadBarrier
$transitionInputsBefore = Get-TransitionInputSnapshot -Barrier $inputBarrier
if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne $metaShaBeforeValidation) { throw 'META_CHANGED_BEFORE_STAGE_VALIDATION' }
$validation = & (Join-Path $PSScriptRoot 'Validate-Project.ps1') -ProjectPath $project -PythonPath $PythonPath -NoExit
if ($validation.Verdict -ne 'PASS') { throw "CURRENT_STAGE_NOT_READY: $($validation.ErrorDetails -join '; ')" }
if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne $metaShaBeforeValidation) { throw 'META_CHANGED_DURING_STAGE_VALIDATION' }
if ((Get-TransitionInputSnapshot -Barrier $inputBarrier) -ne $transitionInputsBefore) { throw 'PROJECT_INPUTS_CHANGED_DURING_STAGE_VALIDATION' }

$meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
function Get-SingleField([string]$Name) {
    $matches = @([regex]::Matches($meta, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
    if ($matches.Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $Name=$($matches.Count)" }
    return $matches[0].Groups[1].Value.Trim()
}
function Set-SingleField([string]$Text, [string]$Name, [string]$Value) {
    $pattern = "(?m)^$([regex]::Escape($Name)):\s*.*?$"
    if ([regex]::Matches($Text, $pattern).Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $Name" }
    $literal = "${Name}: $Value"
    return [regex]::Replace($Text, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $literal })
}

$stage = Get-SingleField 'CURRENT_STAGE'
$lastGateAtStart = Get-SingleField 'LAST_GATE'
if ($stage -eq 'W0' -and $lastGateAtStart -ne 'PROJECT_INITIALIZED') {
    throw "W0_GATE_MUST_REMAIN_PROJECT_INITIALIZED_UNTIL_ADVANCE: $lastGateAtStart"
}
if ($stage -eq 'W0' -and $Apply -and -not $DawidApproved) { throw 'DAWID_APPROVAL_REQUIRED' }
$w0ConditionStatus = Get-SingleField 'W0_CONDITION_STATUS'
if ($stage -eq 'K0' -and (Get-SingleField 'W0_DECISION') -eq 'GO WARUNKOWE' -and $w0ConditionStatus -ne 'CLOSED') {
    throw 'W0_CONDITION_MUST_BE_CLOSED_BEFORE_K1'
}
$nextMap = @{ W0='K0'; K0='K1'; K1='K2'; K2='K2B'; K2B='K3'; K3='K4'; K4='K5'; K5='COMPLETE' }
$gateMap = @{ K0='K0_PASS'; K1='K1_PASS'; K2='K2_PASS'; K2B='K2B_PASS'; K3='K3_PASS'; K4='K4_PASS'; K5='K5_PASS' }
$ownerMap = @{ K0='ChatGPT'; K1='ChatGPT'; K2='ChatGPT'; K2B='ChatGPT'; K3='Claude'; K4='ChatGPT'; K5='Dawid'; COMPLETE='Dawid' }
if (-not $nextMap.ContainsKey($stage)) { throw "STAGE_CANNOT_ADVANCE: $stage" }
$nextStage = $nextMap[$stage]
$completedGate = if ($stage -eq 'W0') {
    $decision = Get-SingleField 'W0_DECISION'
    if ($decision -eq 'GO') { 'W0_GO' } elseif ($decision -eq 'GO WARUNKOWE') { 'W0_GO_WARUNKOWE' } else { throw "W0_DECISION_CANNOT_ADVANCE: $decision" }
} else { $gateMap[$stage] }
$nextOwner = $ownerMap[$nextStage]
$nextActionMap = @{
    K0='Uzupełnij i zwaliduj 00-fundament-projektu.md.'
    K1='Wykonaj K1 zgodnie z aktywnym K1_RESEARCH_MODE i opublikuj zwalidowaną bazę dowodów.'
    K2='Zbuduj i zwaliduj 02-architektura-odcinka.md.'
    K2B='Rozstrzygnij luki K2B, wykonaj ewentualny suplement i wygeneruj świeże paczki K3.'
    K3='Napisz 03-draft.md wyłącznie z aktualnych paczek K3 i zwaliduj pełny draft.'
    K4='Wykonaj QA, niezależny fact-check, baseline i receipt VERIFY.'
    K5='Dawid finalizuje narrację i tworzy receipt zatwierdzenia finalu.'
    COMPLETE='Narracja ukończona — dalsza produkcja pozostaje poza System-v7.0.'
}

$updated = Set-SingleField $meta 'CURRENT_STAGE' $nextStage
$updated = Set-SingleField $updated 'STAGE_OWNER' $nextOwner
$updated = Set-SingleField $updated 'OWNER_OVERRIDE' 'BRAK'
$updated = Set-SingleField $updated 'OWNER_OVERRIDE_RECEIPT_PATH' 'BRAK'
$updated = Set-SingleField $updated 'OWNER_OVERRIDE_RECEIPT_SHA256' 'BRAK'
$updated = Set-SingleField $updated 'BLOCKED_FROM_STAGE' 'BRAK'
$updated = Set-SingleField $updated 'BLOCKED_REASON' 'BRAK'
$updated = Set-SingleField $updated 'LAST_GATE' $completedGate
$updated = Set-SingleField $updated 'LAST_UPDATED' ([DateTime]::UtcNow.ToString('yyyy-MM-dd'))
$updated = Set-SingleField $updated 'NEXT_ACTION' $nextActionMap[$nextStage]
$updated = [regex]::Replace($updated, '(?m)^- Właściciel:\s*.*$', "- Właściciel: $nextOwner")
$updated = [regex]::Replace($updated, '(?m)^- Zadanie:\s*.*$', "- Zadanie: $nextStage — $($nextActionMap[$nextStage])")

# To jest ostatnia kontrola po całej logice przejścia, bezpośrednio przed
# compare-and-swap. Nie polegamy na wcześniejszym wyniku walidatora.
if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne $metaShaBeforeValidation) {
    throw 'META_CHANGED_IMMEDIATELY_BEFORE_STAGE_COMMIT'
}
if ((Get-TransitionInputSnapshot -Barrier $inputBarrier) -ne $transitionInputsBefore) {
    throw 'PROJECT_INPUTS_CHANGED_IMMEDIATELY_BEFORE_STAGE_COMMIT'
}

if ($Apply) {
    $committedMetaSha256 = Get-Sha256HexFromText -Text $updated
    $transitionMetaTransaction = Write-Utf8TextAtomicCompareAndSwap -Path $metaPath -Text $updated -ExpectedCurrentSha256 $metaShaBeforeValidation -HeldLockStream $projectLock -DeferFinalization

    # Kontrola po CAS zamyka okno między ostatnim snapshotem a podmianą meta.
    # Jeśli w tym oknie powstało/zniknęło wejście, stan etapu wraca bajt w
    # bajt do wersji sprzed operacji. CAS rollback nigdy nie nadpisuje obcej zmiany.
    $postCommitProblem = $null
    try {
        $metaShaAfterCommit = (Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash
        if ($metaShaAfterCommit -ne $committedMetaSha256) {
            throw "META_CHANGED_AFTER_STAGE_COMMIT: expected=$committedMetaSha256 actual=$metaShaAfterCommit"
        }
        if ((Get-TransitionInputSnapshot -Barrier $inputBarrier) -ne $transitionInputsBefore) {
            throw 'PROJECT_INPUTS_CHANGED_AFTER_STAGE_COMMIT'
        }
    } catch {
        $postCommitProblem = $_.Exception.Message
    }
    if ($postCommitProblem) {
        try {
            Abort-SystemV7DeferredMetaTransaction -Transaction $transitionMetaTransaction -Reason $postCommitProblem
            $transitionMetaTransaction = $null
        } catch {
            throw "STAGE_COMMIT_POSTCHECK_FAILED_AND_ROLLBACK_CONFLICT: $postCommitProblem; $($_.Exception.Message)"
        }
        throw "STAGE_COMMIT_POSTCHECK_FAILED_ROLLED_BACK: $postCommitProblem"
    }
    Complete-SystemV7DeferredMetaTransaction -Transaction $transitionMetaTransaction
    $transitionMetaTransaction = $null
}

[pscustomobject]@{
    Mode = if ($Apply) { 'APPLIED' } else { 'PREVIEW' }
    FromStage = $stage
    ToStage = $nextStage
    LastGate = $completedGate
    StageOwner = $nextOwner
    NextAction = $nextActionMap[$nextStage]
}
} finally {
    try { Exit-TransitionInputReadBarrier -Barrier $inputBarrier }
    finally { Exit-SystemV7ProjectMetaLock -LockStream $projectLock }
}
