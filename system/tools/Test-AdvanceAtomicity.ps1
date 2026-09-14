[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()][string]$PythonPath = 'python.exe'
)

$ErrorActionPreference = 'Stop'
$advancePath = Join-Path $PSScriptRoot 'Advance-Stage.ps1'
$newProjectPath = Join-Path $PSScriptRoot 'New-Project.ps1'
. (Join-Path $PSScriptRoot 'Integrity-Receipts.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('system-v7-advance-atomicity-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null

function Set-FixtureMetaValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    $text = [IO.File]::ReadAllText($Path)
    $pattern = "(?m)^$([regex]::Escape($Name)):\s*.*$"
    if ([regex]::Matches($text, $pattern).Count -ne 1) { throw "FIXTURE_META_FIELD_COUNT_INVALID: $Name" }
    $replacement = "${Name}: $Value"
    $text = [regex]::Replace($text, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement })
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

try {
    $created = & $newProjectPath -NarrativeV2Pilot:$false -ProjectName 'advance-atomicity' -DestinationRoot $testRoot
    $project = [string]$created.ProjectPath
    $metaPath = Join-Path $project 'meta.md'
    [IO.File]::WriteAllText(
        (Join-Path $project 'sources\source.md'),
        'Materiał wejściowy W0 z konkretną treścią do dalszej analizy.',
        [Text.UTF8Encoding]::new($false)
    )
    foreach ($entry in @(
        @('W0_DECISION','GO'),
        @('W0_CONDITIONS','BRAK'),
        @('W0_CONDITION_STATUS','NOT_APPLICABLE'),
        @('LAST_GATE','PROJECT_INITIALIZED')
    )) {
        Set-FixtureMetaValue -Path $metaPath -Name $entry[0] -Value $entry[1]
    }

    # Oba wejścia były wcześniej pomijane przez selektywny snapshot.
    $qaBaseline = Join-Path $project '_work\qa-baseline.md'
    $packetDirectory = Join-Path $project '_work\k3-pakiety'
    [IO.Directory]::CreateDirectory($packetDirectory) | Out-Null
    [IO.File]::WriteAllText($qaBaseline, 'Niezmienny baseline QA do testu wyścigu.', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $packetDirectory 'AKT-1.md'), 'Pakiet K3 objęty manifestem.', [Text.UTF8Encoding]::new($false))

    $metaBeforeContention = [IO.File]::ReadAllBytes($metaPath)
    $activeWriter = [IO.File]::Open($qaBaseline, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    $contentionError = $null
    try {
        $null = & $advancePath -ProjectPath $project -PythonPath $PythonPath -Apply -DawidApproved
    } catch {
        $contentionError = $_.Exception.Message
    } finally {
        $activeWriter.Dispose()
    }
    if (-not $contentionError) { throw 'ADVANCE_ACCEPTED_PROJECT_WITH_ACTIVE_QA_BASELINE_WRITER' }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($metaPath)) -cne [Convert]::ToBase64String($metaBeforeContention)) {
        throw 'ADVANCE_CHANGED_META_WHILE_INPUT_WRITER_WAS_ACTIVE'
    }

    $metaShaBeforePreview = (Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash
    $preview = & $advancePath -ProjectPath $project -PythonPath $PythonPath
    if ($preview.Mode -ne 'PREVIEW' -or $preview.FromStage -ne 'W0' -or $preview.ToStage -ne 'K0') {
        throw 'ADVANCE_PREVIEW_RESULT_INVALID'
    }
    if ((Get-FileHash -LiteralPath $metaPath -Algorithm SHA256).Hash -ne $metaShaBeforePreview) {
        throw 'ADVANCE_PREVIEW_CHANGED_META'
    }

    $applied = & $advancePath -ProjectPath $project -PythonPath $PythonPath -Apply -DawidApproved
    $metaAfter = [IO.File]::ReadAllText($metaPath)
    if ($applied.Mode -ne 'APPLIED' -or $applied.ToStage -ne 'K0' -or $metaAfter -notmatch '(?m)^CURRENT_STAGE:\s*K0\s*$') {
        throw 'ADVANCE_APPLY_RESULT_INVALID'
    }
    if (@(Get-ChildItem -LiteralPath $project -Recurse -Force -File | Where-Object Name -Like '.advance-rollback-*').Count -ne 0) {
        throw 'ADVANCE_ROLLBACK_TEMP_LEFTOVER'
    }

    # Deterministyczny wyścig: obcy zapis następuje po wstępnej kontroli SHA,
    # ale przed File.Replace. CAS ma go zachować i zgłosić konflikt.
    $casCreated = & $newProjectPath -NarrativeV2Pilot:$false -ProjectName 'cas-foreign-writer' -DestinationRoot $testRoot
    $casProject = [string]$casCreated.ProjectPath
    $casMetaPath = Join-Path $casProject 'meta.md'
    $originalBytes = [IO.File]::ReadAllBytes($casMetaPath)
    $originalText = [Text.UTF8Encoding]::new($false).GetString($originalBytes)
    $candidateText = [regex]::Replace($originalText, '(?m)^NEXT_ACTION:\s*.*$', 'NEXT_ACTION: CANDIDATE_FROM_SYSTEM')
    $foreignText = [regex]::Replace($originalText, '(?m)^NEXT_ACTION:\s*.*$', 'NEXT_ACTION: FOREIGN_WRITER_MUST_SURVIVE')
    $candidateBytes = [Text.UTF8Encoding]::new($false).GetBytes($candidateText)
    $foreignBytes = [Text.UTF8Encoding]::new($false).GetBytes($foreignText)
    $casHook = { [IO.File]::WriteAllBytes($casMetaPath, $foreignBytes) }.GetNewClosure()
    $casError = $null
    try {
        Write-BytesAtomicCompareAndSwap -Path $casMetaPath -Bytes $candidateBytes -ExpectedCurrentSha256 (Get-Sha256HexFromBytes -Bytes $originalBytes) -InternalBeforeReplaceTestHook $casHook
    } catch { $casError = $_.Exception.Message }
    if ($casError -notmatch '^COMPARE_AND_SWAP_CONFLICT:') {
        throw "FOREIGN_META_RACE_WRONG_RESULT: $casError"
    }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($casMetaPath)) -cne [Convert]::ToBase64String($foreignBytes)) {
        throw 'FOREIGN_META_RACE_WAS_NOT_PRESERVED_BYTE_FOR_BYTE'
    }
    $pendingRoot = Join-Path $casProject '.system-v7\meta-transactions\pending'
    if ((Test-Path -LiteralPath $pendingRoot -PathType Container) -and @(Get-ChildItem -LiteralPath $pendingRoot -Directory -Force).Count -ne 0) {
        throw 'FOREIGN_META_RACE_LEFT_PENDING_TRANSACTION'
    }

    # Awaria tuż po utworzeniu katalogu transakcji nie może zablokować projektu na stałe.
    $emptyCrashTransaction = Join-Path $pendingRoot ([guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($emptyCrashTransaction) | Out-Null
    $recoverySignal = $null
    try {
        $unexpectedLock = Enter-SystemV7ProjectMetaLock -ProjectPath $casProject
        Exit-SystemV7ProjectMetaLock -LockStream $unexpectedLock
    } catch { $recoverySignal = $_.Exception.Message }
    if ($recoverySignal -notmatch '^META_TRANSACTION_RECOVERED_RETRY_REQUIRED: incomplete ') {
        throw "EMPTY_TRANSACTION_RECOVERY_SIGNAL_INVALID: $recoverySignal"
    }
    $lockAfterRecovery = Enter-SystemV7ProjectMetaLock -ProjectPath $casProject
    Exit-SystemV7ProjectMetaLock -LockStream $lockAfterRecovery

    # Symulacja awarii Advance po File.Replace, ale przed postcheckiem/accept.
    # Niezaakceptowana transakcja musi zostać cofnięta przy następnym locku.
    $deferredCreated = & $newProjectPath -NarrativeV2Pilot:$false -ProjectName 'deferred-crash-recovery' -DestinationRoot $testRoot
    $deferredProject = [string]$deferredCreated.ProjectPath
    $deferredMetaPath = Join-Path $deferredProject 'meta.md'
    $deferredBefore = [IO.File]::ReadAllBytes($deferredMetaPath)
    $deferredText = [Text.UTF8Encoding]::new($false).GetString($deferredBefore)
    $deferredCandidateText = [regex]::Replace($deferredText, '(?m)^NEXT_ACTION:\s*.*$', 'NEXT_ACTION: UNACCEPTED_ADVANCE_CANDIDATE')
    $deferredCandidate = [Text.UTF8Encoding]::new($false).GetBytes($deferredCandidateText)
    $deferredLock = Enter-SystemV7ProjectMetaLock -ProjectPath $deferredProject
    try {
        $deferredHandle = Write-BytesAtomicCompareAndSwap -Path $deferredMetaPath -Bytes $deferredCandidate -ExpectedCurrentSha256 (Get-Sha256HexFromBytes -Bytes $deferredBefore) -HeldLockStream $deferredLock -DeferFinalization
        if ($deferredHandle.Schema -cne 'SYSTEM_V7_DEFERRED_META_TRANSACTION_V1') { throw 'DEFERRED_TRANSACTION_HANDLE_INVALID' }
    } finally { Exit-SystemV7ProjectMetaLock -LockStream $deferredLock }
    $deferredRecoverySignal = $null
    try {
        $unexpectedDeferredLock = Enter-SystemV7ProjectMetaLock -ProjectPath $deferredProject
        Exit-SystemV7ProjectMetaLock -LockStream $unexpectedDeferredLock
    } catch { $deferredRecoverySignal = $_.Exception.Message }
    if ($deferredRecoverySignal -notmatch '^META_TRANSACTION_RECOVERED_RETRY_REQUIRED: rolled back unaccepted ') {
        throw "DEFERRED_CRASH_RECOVERY_SIGNAL_INVALID: $deferredRecoverySignal"
    }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($deferredMetaPath)) -cne [Convert]::ToBase64String($deferredBefore)) {
        throw 'DEFERRED_CRASH_RECOVERY_DID_NOT_RESTORE_ORIGINAL_BYTES'
    }
    $lockAfterDeferredRecovery = Enter-SystemV7ProjectMetaLock -ProjectPath $deferredProject
    Exit-SystemV7ProjectMetaLock -LockStream $lockAfterDeferredRecovery

    # Zastrzeżony namespace journala nie może być junctionem poza projektem.
    $reparseCreated = & $newProjectPath -NarrativeV2Pilot:$false -ProjectName 'journal-reparse-guard' -DestinationRoot $testRoot
    $reparseProject = [string]$reparseCreated.ProjectPath
    $outsideJournalTarget = Join-Path $testRoot 'outside-journal-target'
    [IO.Directory]::CreateDirectory($outsideJournalTarget) | Out-Null
    $journalJunction = Join-Path $reparseProject '.system-v7\meta-transactions'
    $null = New-Item -ItemType Junction -Path $journalJunction -Target $outsideJournalTarget
    $reparseError = $null
    try {
        $unexpectedReparseLock = Enter-SystemV7ProjectMetaLock -ProjectPath $reparseProject
        Exit-SystemV7ProjectMetaLock -LockStream $unexpectedReparseLock
    } catch { $reparseError = $_.Exception.Message }
    if ($reparseError -notmatch 'REPARSE_POINT_BLOCKED') {
        throw "JOURNAL_REPARSE_GUARD_FAILED: $reparseError"
    }
    [IO.Directory]::Delete($journalJunction)

    [pscustomobject]@{
        Verdict='PASS'
        ActiveWriterRejected=$true
        PreviouslyOmittedInputsCovered=@('_work/qa-baseline.md','_work/k3-pakiety/AKT-1.md')
        Preview='PASS'
        Apply='PASS'
        ForeignMetaRacePreserved=$true
        EmptyTransactionRecovered=$true
        UnacceptedAdvanceRecovered=$true
        JournalReparseBlocked=$true
        FromStage='W0'
        ToStage='K0'
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ADVANCE_TEST_TEMP_CLEANUP_SCOPE_INVALID'
    }
    if ([IO.Directory]::Exists($resolved)) { [IO.Directory]::Delete($resolved, $true) }
}
