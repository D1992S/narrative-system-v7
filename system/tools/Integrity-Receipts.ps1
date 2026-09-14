function Get-Sha256HexFromBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($sha.ComputeHash($Bytes))) }
    finally { $sha.Dispose() }
}

function Get-Sha256HexFromText {
    param([Parameter(Mandatory)][string]$Text)

    Get-Sha256HexFromBytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-ActiveSourceCorpusState {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $sources = [IO.Path]::GetFullPath((Join-Path $project 'sources'))
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        Assert-SystemV7PathNoReparse -Path $project | Out-Null
        Assert-SystemV7PathNoReparse -Path $sources -ContainmentRoot $project | Out-Null
    }
    if (-not (Test-Path -LiteralPath $sources -PathType Container)) {
        throw "SOURCES_DIRECTORY_MISSING: $sources"
    }

    $supported = @('.pdf', '.md', '.txt', '.srt', '.vtt')
    $nested = @(Get-ChildItem -LiteralPath $sources -Recurse -File | Where-Object {
        $_.DirectoryName -ne $sources -and
        $_.FullName -notmatch '\\_oryginaly(?:\\|$)' -and
        $_.Extension.ToLowerInvariant() -in $supported
    })
    if ($nested.Count -gt 0) {
        throw "SUPPORTED_SOURCE_IN_SUBDIRECTORY: $($nested.FullName -join '; ')"
    }

    $files = @(Get-ChildItem -LiteralPath $sources -File | Where-Object {
        $_.Length -gt 0 -and $_.Extension.ToLowerInvariant() -in $supported
    } | Sort-Object FullName)
    if ($files.Count -eq 0) { throw 'ACTIVE_SOURCE_CORPUS_EMPTY' }

    $rows = foreach ($file in $files) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "SOURCE_REPARSE_POINT_BLOCKED: $($file.FullName)" }
        $relative = ([IO.Path]::GetRelativePath($project, $file.FullName)).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        "$relative`t$hash"
    }
    $canonical = ($rows -join "`n") + "`n"
    [pscustomobject]@{
        Schema = 'SYSTEM_V7_SOURCE_CORPUS_STATE_V1'
        Sha256 = Get-Sha256HexFromText -Text $canonical
        FileCount = $files.Count
        Rows = @($rows)
    }
}

function Write-NewUtf8Json {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Value
    )

    $target = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "RECEIPT_DIRECTORY_MISSING: $directory" }
    $json = ($Value | ConvertTo-Json -Depth 16) + "`n"
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $existingJson = Get-Content -LiteralPath $target -Raw -Encoding UTF8
        if ($existingJson -cne $json) {
            try {
                $existingData = $existingJson | ConvertFrom-Json -DateKind String
                $incomingData = $json | ConvertFrom-Json -DateKind String
                if ($existingData.PSObject.Properties.Name -contains 'created_at_utc' -and
                    $incomingData.PSObject.Properties.Name -contains 'created_at_utc') {
                    $incomingData.created_at_utc = $existingData.created_at_utc
                    $normalizedIncoming = ($incomingData | ConvertTo-Json -Depth 8) + "`n"
                    if ($existingJson -cne $normalizedIncoming -or -not (Test-Utf8FileCanonicalBytes -Path $target -ExpectedText $normalizedIncoming)) { throw 'different' }
                    return
                }
            } catch { throw "RECEIPT_ALREADY_EXISTS_DIFFERENT: $target" }
            throw "RECEIPT_ALREADY_EXISTS_DIFFERENT: $target"
        }
        if (-not (Test-Utf8FileCanonicalBytes -Path $target -ExpectedText $json)) {
            throw "RECEIPT_ALREADY_EXISTS_NONCANONICAL_BYTES: $target"
        }
        return
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    $tempPath = Join-Path $directory ('.receipt-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $stream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    try {
        [IO.File]::Move($tempPath, $target)
    } catch {
        if ((Test-Path -LiteralPath $target -PathType Leaf) -and
            ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -ceq [Convert]::ToBase64String($bytes))) {
            return
        }
        throw
    } finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) { [IO.File]::Delete($tempPath) }
    }
}

function Test-Utf8FileCanonicalBytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedText
    )
    $actual = [IO.File]::ReadAllBytes([IO.Path]::GetFullPath($Path))
    $expected = [Text.UTF8Encoding]::new($false).GetBytes($ExpectedText)
    if ($actual.Length -ne $expected.Length) { return $false }
    for ($index = 0; $index -lt $actual.Length; $index++) {
        if ($actual[$index] -ne $expected[$index]) { return $false }
    }
    return $true
}

function Get-SystemV7MetaTransactionPaths {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $root = Join-Path $project '.system-v7\meta-transactions'
    [pscustomobject]@{
        Root = $root
        Pending = Join-Path $root 'pending'
        History = Join-Path $root 'history'
        Conflicts = Join-Path $root 'conflicts'
    }
}

function Assert-SystemV7MetaTransactionNamespaceSafe {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $paths = Get-SystemV7MetaTransactionPaths -ProjectPath $project
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        foreach ($path in @($paths.Root,$paths.Pending,$paths.History,$paths.Conflicts)) {
            Assert-SystemV7PathNoReparse -Path $path -ContainmentRoot $project | Out-Null
        }
        if ((Test-Path -LiteralPath $paths.Root -PathType Container) -and
            $null -ne (Get-Command Assert-SystemV7TreeNoReparse -ErrorAction SilentlyContinue)) {
            Assert-SystemV7TreeNoReparse -RootPath $paths.Root -ContainmentRoot $project | Out-Null
        }
    } elseif (Test-Path -LiteralPath $paths.Root -PathType Container) {
        $rootItem = Get-Item -LiteralPath $paths.Root -Force
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "META_TRANSACTION_REPARSE_POINT_BLOCKED: $($rootItem.FullName)"
        }
        foreach ($entry in @(Get-ChildItem -LiteralPath $paths.Root -Force -Recurse)) {
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "META_TRANSACTION_REPARSE_POINT_BLOCKED: $($entry.FullName)"
            }
        }
    }
    return $paths
}

function Write-SystemV7DurableBytesCreateNew {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    $target = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "META_TRANSACTION_DIRECTORY_MISSING: $parent"
    }
    $stream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
}

function Write-SystemV7DurableJsonCreateNew {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Value
    )

    $json = ($Value | ConvertTo-Json -Depth 8 -Compress) + "`n"
    Write-SystemV7DurableBytesCreateNew -Path $Path -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($json))
}

function Get-SystemV7FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    Get-Sha256HexFromBytes -Bytes ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($Path)))
}

function Move-SystemV7MetaTransactionToArchive {
    param(
        [Parameter(Mandatory)][string]$TransactionPath,
        [Parameter(Mandatory)][string]$ArchiveRoot
    )

    [IO.Directory]::CreateDirectory($ArchiveRoot) | Out-Null
    $destination = Join-Path $ArchiveRoot (Split-Path -Leaf $TransactionPath)
    if (Test-Path -LiteralPath $destination) { throw "META_TRANSACTION_ARCHIVE_EXISTS: $destination" }
    [IO.Directory]::Move($TransactionPath, $destination)
    return $destination
}

function Write-SystemV7MetaTransactionMarker {
    param(
        [Parameter(Mandatory)][string]$TransactionPath,
        [Parameter(Mandatory)][ValidateSet('COMMITTED','ABORTED')][string]$Marker,
        [Parameter(Mandatory)][string]$Reason
    )

    $markerPath = Join-Path $TransactionPath ($Marker + '.json')
    if (Test-Path -LiteralPath $markerPath -PathType Leaf) { return }
    Write-SystemV7DurableJsonCreateNew -Path $markerPath -Value ([ordered]@{
        schema = 'SYSTEM_V7_META_TRANSACTION_RESULT_V1'
        result = $Marker
        reason = $Reason
        recorded_at_utc = [DateTime]::UtcNow.ToString('o')
    })
}

function Invoke-SystemV7PreservingMetaRestore {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$TransactionPath,
        [Parameter(Mandatory)][string]$RestoreSourcePath,
        [Parameter(Mandatory)][string]$ExpectedTargetSha256
    )

    $source = $RestoreSourcePath
    $expectedTarget = $ExpectedTargetSha256.ToUpperInvariant()
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "META_TRANSACTION_RECOVERY_REQUIRED: restore source missing: $source"
        }
        if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
            throw "META_TRANSACTION_RECOVERY_REQUIRED: meta target missing: $TargetPath"
        }

        # File.Replace konsumuje plik źródłowy. Kopia trwała gwarantuje, że
        # żadna wersja wyparta podczas wyścigu nie zniknie nawet po awarii.
        $sourceBytes = [IO.File]::ReadAllBytes($source)
        $sourceSha = Get-Sha256HexFromBytes -Bytes $sourceBytes
        $sourceCopy = Join-Path $TransactionPath ("restore-source-$attempt.bin")
        if (-not (Test-Path -LiteralPath $sourceCopy -PathType Leaf)) {
            Write-SystemV7DurableBytesCreateNew -Path $sourceCopy -Bytes $sourceBytes
        }

        $displaced = Join-Path $TransactionPath ("restore-displaced-$attempt.bin")
        [IO.File]::Replace($source, $TargetPath, $displaced, $true)
        $actualDisplacedSha = Get-SystemV7FileSha256 -Path $displaced
        $actualTargetSha = Get-SystemV7FileSha256 -Path $TargetPath
        if ($actualTargetSha -ne $sourceSha) {
            throw "META_TRANSACTION_RECOVERY_REQUIRED: target changed during preserving restore"
        }
        if ($actualDisplacedSha -eq $expectedTarget) {
            return [pscustomobject]@{
                RestoredSha256 = $sourceSha
                DisplacedSha256 = $actualDisplacedSha
                Attempts = $attempt
            }
        }

        # Kolejny obcy zapis wygrał wyścig. Jest zachowany w backupie; przywróć
        # go w następnym atomowym kroku, zachowując również bieżącą wersję.
        $source = $displaced
        $expectedTarget = $sourceSha
    }
    throw 'META_TRANSACTION_RECOVERY_REQUIRED: too many concurrent meta writers during preserving restore'
}

function Resolve-SystemV7PendingMetaTransactions {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $paths = Assert-SystemV7MetaTransactionNamespaceSafe -ProjectPath $project
    if (-not (Test-Path -LiteralPath $paths.Pending -PathType Container)) { return }
    $pending = @(Get-ChildItem -LiteralPath $paths.Pending -Directory -Force | Sort-Object Name)
    if ($pending.Count -eq 0) { return }

    $transactionPath = $pending[0].FullName
    $transactionId = $pending[0].Name
    $committedMarker = Join-Path $transactionPath 'COMMITTED.json'
    $abortedMarker = Join-Path $transactionPath 'ABORTED.json'
    if (Test-Path -LiteralPath $committedMarker -PathType Leaf) {
        Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.History | Out-Null
        throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: committed $transactionId"
    }
    if (Test-Path -LiteralPath $abortedMarker -PathType Leaf) {
        Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
        throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: aborted $transactionId"
    }

    $preparedPath = Join-Path $transactionPath 'PREPARED.json'
    $candidatePath = Join-Path $transactionPath 'candidate.bin'
    $replacePath = Join-Path $transactionPath 'replace.bin'
    $displacedPath = Join-Path $transactionPath 'displaced.bin'
    $targetPath = Join-Path $project 'meta.md'

    if (-not (Test-Path -LiteralPath $preparedPath -PathType Leaf)) {
        # PREPARED jest zapisywany dopiero po obu payloadach, a File.Replace
        # uruchamia się dopiero po PREPARED. Bez displaced operacja na pewno
        # nie podmieniła meta, nawet jeśli awaria zostawiła pusty albo częściowy katalog.
        if (-not (Test-Path -LiteralPath $displacedPath -PathType Leaf)) {
            Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'incomplete_before_prepare'
            Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
            throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: incomplete $transactionId"
        }
        throw "META_TRANSACTION_RECOVERY_REQUIRED: malformed transaction $transactionId"
    }

    try { $prepared = Get-Content -LiteralPath $preparedPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String }
    catch {
        if ((Test-Path -LiteralPath $replacePath -PathType Leaf) -and
            -not (Test-Path -LiteralPath $displacedPath -PathType Leaf)) {
            Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'incomplete_prepared_json_before_replace'
            Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
            throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: incomplete PREPARED $transactionId"
        }
        throw "META_TRANSACTION_RECOVERY_REQUIRED: invalid PREPARED.json in $transactionId"
    }
    $required = @('schema','transaction_id','target_relative_path','expected_sha256','candidate_sha256')
    foreach ($name in $required) {
        if ($prepared.PSObject.Properties.Name -notcontains $name) {
            throw "META_TRANSACTION_RECOVERY_REQUIRED: PREPARED missing $name in $transactionId"
        }
    }
    if ([string]$prepared.schema -cne 'SYSTEM_V7_META_TRANSACTION_V1' -or
        [string]$prepared.transaction_id -cne $transactionId -or
        [string]$prepared.target_relative_path -cne 'meta.md' -or
        [string]$prepared.expected_sha256 -notmatch '^[A-F0-9]{64}$' -or
        [string]$prepared.candidate_sha256 -notmatch '^[A-F0-9]{64}$') {
        throw "META_TRANSACTION_RECOVERY_REQUIRED: PREPARED contract invalid in $transactionId"
    }
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf) -or
        (Get-SystemV7FileSha256 -Path $candidatePath) -ne [string]$prepared.candidate_sha256) {
        throw "META_TRANSACTION_RECOVERY_REQUIRED: candidate invalid in $transactionId"
    }
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw "META_TRANSACTION_RECOVERY_REQUIRED: meta.md missing in $transactionId"
    }

    $targetSha = Get-SystemV7FileSha256 -Path $targetPath
    if (Test-Path -LiteralPath $displacedPath -PathType Leaf) {
        $displacedSha = Get-SystemV7FileSha256 -Path $displacedPath
        if ($targetSha -eq [string]$prepared.candidate_sha256) {
            if ($displacedSha -eq [string]$prepared.expected_sha256) {
                Invoke-SystemV7PreservingMetaRestore -TargetPath $targetPath -TransactionPath $transactionPath -RestoreSourcePath $displacedPath -ExpectedTargetSha256 ([string]$prepared.candidate_sha256) | Out-Null
                Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'recovered_unaccepted_atomic_replace'
                Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
                throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: rolled back unaccepted $transactionId"
            }
            Invoke-SystemV7PreservingMetaRestore -TargetPath $targetPath -TransactionPath $transactionPath -RestoreSourcePath $displacedPath -ExpectedTargetSha256 ([string]$prepared.candidate_sha256) | Out-Null
            Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'recovered_compare_and_swap_conflict'
            Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
            throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: conflict $transactionId"
        }

        # Po replace mógł nadejść obcy zapis. Nie cofamy go, a brak trwałego
        # COMMITTED oznacza, że caller nie zaakceptował jeszcze operacji.
        if ($displacedSha -eq [string]$prepared.expected_sha256) {
            Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'unaccepted_replace_then_external_change_preserved'
            Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
            throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: unaccepted then changed $transactionId"
        }
        Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'conflict_with_later_external_change_preserved'
        Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
        throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: conflict preserved $transactionId"
    }

    if (Test-Path -LiteralPath $replacePath -PathType Leaf) {
        Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'atomic_replace_not_started'
        Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
        throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: not started $transactionId"
    }

    $firstRestoreBackup = Join-Path $transactionPath 'restore-displaced-1.bin'
    if ((Test-Path -LiteralPath $firstRestoreBackup -PathType Leaf) -and
        (Get-SystemV7FileSha256 -Path $firstRestoreBackup) -eq [string]$prepared.candidate_sha256) {
        Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'conflict_rollback_completed_before_crash'
        Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
        throw "META_TRANSACTION_RECOVERED_RETRY_REQUIRED: rolled back $transactionId"
    }
    throw "META_TRANSACTION_RECOVERY_REQUIRED: ambiguous transaction $transactionId"
}

function Assert-SystemV7DeferredMetaTransaction {
    param([Parameter(Mandatory)][object]$Transaction)

    $required = @('Schema','ProjectPath','TargetPath','TransactionPath','ExpectedSha256','CandidateSha256')
    foreach ($name in $required) {
        if ($Transaction.PSObject.Properties.Name -notcontains $name) { throw "META_TRANSACTION_HANDLE_INVALID: missing $name" }
    }
    if ([string]$Transaction.Schema -cne 'SYSTEM_V7_DEFERRED_META_TRANSACTION_V1') { throw 'META_TRANSACTION_HANDLE_SCHEMA_INVALID' }
    $project = [IO.Path]::GetFullPath([string]$Transaction.ProjectPath)
    $target = [IO.Path]::GetFullPath([string]$Transaction.TargetPath)
    $transactionPath = [IO.Path]::GetFullPath([string]$Transaction.TransactionPath)
    $paths = Assert-SystemV7MetaTransactionNamespaceSafe -ProjectPath $project
    $pendingPrefix = [IO.Path]::GetFullPath($paths.Pending).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (-not $target.Equals((Join-Path $project 'meta.md'), [StringComparison]::OrdinalIgnoreCase) -or
        -not $transactionPath.StartsWith($pendingPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $transactionPath) -notmatch '^[a-f0-9]{32}$') {
        throw 'META_TRANSACTION_HANDLE_PATH_INVALID'
    }
    if ([string]$Transaction.ExpectedSha256 -notmatch '^[A-F0-9]{64}$' -or
        [string]$Transaction.CandidateSha256 -notmatch '^[A-F0-9]{64}$') {
        throw 'META_TRANSACTION_HANDLE_HASH_INVALID'
    }
    if (-not (Test-Path -LiteralPath $transactionPath -PathType Container)) { throw 'META_TRANSACTION_HANDLE_NOT_PENDING' }
    [pscustomobject]@{
        Project = $project
        Target = $target
        TransactionPath = $transactionPath
        Paths = $paths
        ExpectedSha256 = [string]$Transaction.ExpectedSha256
        CandidateSha256 = [string]$Transaction.CandidateSha256
    }
}

function Complete-SystemV7DeferredMetaTransaction {
    param([Parameter(Mandatory)][object]$Transaction)

    $tx = Assert-SystemV7DeferredMetaTransaction -Transaction $Transaction
    $displacedPath = Join-Path $tx.TransactionPath 'displaced.bin'
    if ((Get-SystemV7FileSha256 -Path $tx.Target) -ne $tx.CandidateSha256) { throw 'META_TRANSACTION_COMMIT_TARGET_CHANGED' }
    if (-not (Test-Path -LiteralPath $displacedPath -PathType Leaf) -or
        (Get-SystemV7FileSha256 -Path $displacedPath) -ne $tx.ExpectedSha256) {
        throw 'META_TRANSACTION_COMMIT_PREIMAGE_INVALID'
    }
    Write-SystemV7MetaTransactionMarker -TransactionPath $tx.TransactionPath -Marker COMMITTED -Reason 'caller_postchecks_passed'
    Move-SystemV7MetaTransactionToArchive -TransactionPath $tx.TransactionPath -ArchiveRoot $tx.Paths.History | Out-Null
}

function Abort-SystemV7DeferredMetaTransaction {
    param(
        [Parameter(Mandatory)][object]$Transaction,
        [Parameter(Mandatory)][string]$Reason
    )

    $tx = Assert-SystemV7DeferredMetaTransaction -Transaction $Transaction
    $displacedPath = Join-Path $tx.TransactionPath 'displaced.bin'
    $targetSha = Get-SystemV7FileSha256 -Path $tx.Target
    if ($targetSha -ne $tx.CandidateSha256) {
        Write-SystemV7MetaTransactionMarker -TransactionPath $tx.TransactionPath -Marker ABORTED -Reason ('caller_abort_external_target_preserved: ' + $Reason)
        Move-SystemV7MetaTransactionToArchive -TransactionPath $tx.TransactionPath -ArchiveRoot $tx.Paths.Conflicts | Out-Null
        throw "META_TRANSACTION_ABORT_TARGET_CHANGED: expected=$($tx.CandidateSha256) actual=$targetSha"
    }
    if (-not (Test-Path -LiteralPath $displacedPath -PathType Leaf) -or
        (Get-SystemV7FileSha256 -Path $displacedPath) -ne $tx.ExpectedSha256) {
        throw 'META_TRANSACTION_ABORT_PREIMAGE_INVALID'
    }
    Invoke-SystemV7PreservingMetaRestore -TargetPath $tx.Target -TransactionPath $tx.TransactionPath -RestoreSourcePath $displacedPath -ExpectedTargetSha256 $tx.CandidateSha256 | Out-Null
    Write-SystemV7MetaTransactionMarker -TransactionPath $tx.TransactionPath -Marker ABORTED -Reason ('caller_postcheck_failed: ' + $Reason)
    Move-SystemV7MetaTransactionToArchive -TransactionPath $tx.TransactionPath -ArchiveRoot $tx.Paths.Conflicts | Out-Null
}

function Enter-SystemV7ProjectMetaLock {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [int]$TimeoutMilliseconds = 5000
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $lockDirectory = Join-Path $project '.system-v7'
    if (-not (Test-Path -LiteralPath $lockDirectory -PathType Container)) { throw "PROJECT_LOCK_DIRECTORY_MISSING: $lockDirectory" }
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        Assert-SystemV7PathNoReparse -Path $lockDirectory -ContainmentRoot $project | Out-Null
    }
    $lockPath = Join-Path $lockDirectory 'meta-write.lock'
    $existingLockItem = Get-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    if ($existingLockItem -and ($existingLockItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "PROJECT_META_LOCK_REPARSE_POINT_BLOCKED: $lockPath"
    }
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        Assert-SystemV7PathNoReparse -Path $lockPath -ContainmentRoot $project | Out-Null
    }
    $stream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    $createdLockItem = Get-Item -LiteralPath $lockPath -Force
    if (($createdLockItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $stream.Dispose()
        throw "PROJECT_META_LOCK_REPARSE_POINT_BLOCKED: $lockPath"
    }
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        try { Assert-SystemV7PathNoReparse -Path $lockPath -ContainmentRoot $project | Out-Null }
        catch { $stream.Dispose(); throw }
    }
    $attempts = [Math]::Max(1, [int][Math]::Ceiling($TimeoutMilliseconds / 50.0))
    try {
        for ($attempt = 0; $attempt -lt $attempts; $attempt++) {
            try {
                $stream.Lock(0, 1)
                Resolve-SystemV7PendingMetaTransactions -ProjectPath $project
                return $stream
            } catch [IO.IOException] {
                if ($attempt -eq $attempts - 1) { throw 'PROJECT_META_LOCK_TIMEOUT' }
                Start-Sleep -Milliseconds 50
            }
        }
    } catch {
        $stream.Dispose()
        throw
    }
}

function Exit-SystemV7ProjectMetaLock {
    param([AllowNull()][IO.FileStream]$LockStream)
    if ($null -eq $LockStream) { return }
    try { $LockStream.Unlock(0, 1) } catch {}
    $LockStream.Dispose()
}

function Write-BytesAtomicCompareAndSwap {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$ExpectedCurrentSha256,
        [IO.FileStream]$HeldLockStream,
        [scriptblock]$InternalBeforeReplaceTestHook,
        [switch]$DeferFinalization
    )
    if ($ExpectedCurrentSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'EXPECTED_CURRENT_SHA_INVALID' }
    $target = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "COMPARE_AND_SWAP_TARGET_MISSING: $target" }
    $project = Split-Path -Parent $target
    if (-not $target.Equals((Join-Path $project 'meta.md'), [StringComparison]::OrdinalIgnoreCase)) {
        throw "COMPARE_AND_SWAP_TARGET_NOT_PROJECT_META: $target"
    }
    $expected = $ExpectedCurrentSha256.ToUpperInvariant()
    $candidateSha = Get-Sha256HexFromBytes -Bytes $Bytes
    $paths = Assert-SystemV7MetaTransactionNamespaceSafe -ProjectPath $project
    $transactionPath = $null
    try {
        $ownsLock = $null -eq $HeldLockStream
        $lockStream = if ($ownsLock) { Enter-SystemV7ProjectMetaLock -ProjectPath $project } else { $HeldLockStream }
        try {
            $actualCurrent = Get-SystemV7FileSha256 -Path $target
            if ($actualCurrent -ne $expected) {
                throw "COMPARE_AND_SWAP_CONFLICT: expected=$expected actual=$actualCurrent"
            }

            [IO.Directory]::CreateDirectory($paths.Pending) | Out-Null
            [IO.Directory]::CreateDirectory($paths.History) | Out-Null
            [IO.Directory]::CreateDirectory($paths.Conflicts) | Out-Null
            Assert-SystemV7MetaTransactionNamespaceSafe -ProjectPath $project | Out-Null
            $transactionId = [guid]::NewGuid().ToString('N')
            $transactionPath = Join-Path $paths.Pending $transactionId
            [IO.Directory]::CreateDirectory($transactionPath) | Out-Null
            Assert-SystemV7MetaTransactionNamespaceSafe -ProjectPath $project | Out-Null
            $candidatePath = Join-Path $transactionPath 'candidate.bin'
            $replacePath = Join-Path $transactionPath 'replace.bin'
            $displacedPath = Join-Path $transactionPath 'displaced.bin'
            Write-SystemV7DurableBytesCreateNew -Path $candidatePath -Bytes $Bytes
            Write-SystemV7DurableBytesCreateNew -Path $replacePath -Bytes $Bytes
            Write-SystemV7DurableJsonCreateNew -Path (Join-Path $transactionPath 'PREPARED.json') -Value ([ordered]@{
                schema = 'SYSTEM_V7_META_TRANSACTION_V1'
                transaction_id = $transactionId
                target_relative_path = 'meta.md'
                expected_sha256 = $expected
                candidate_sha256 = $candidateSha
                prepared_at_utc = [DateTime]::UtcNow.ToString('o')
            })

            if ($null -ne $InternalBeforeReplaceTestHook) { & $InternalBeforeReplaceTestHook }
            try {
                [IO.File]::Replace($replacePath, $target, $displacedPath, $true)
            } catch {
                if (Test-Path -LiteralPath $replacePath -PathType Leaf) {
                    Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'file_replace_failed_before_consuming_candidate'
                    Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
                    $transactionPath = $null
                }
                throw "COMPARE_AND_SWAP_REPLACE_FAILED: $($_.Exception.Message)"
            }

            $displacedSha = Get-SystemV7FileSha256 -Path $displacedPath
            $targetSha = Get-SystemV7FileSha256 -Path $target
            if ($targetSha -ne $candidateSha) {
                Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'post_replace_external_change_preserved'
                Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
                $transactionPath = $null
                throw "COMPARE_AND_SWAP_POST_REPLACE_TARGET_CHANGED: expected_candidate=$candidateSha actual=$targetSha"
            }
            if ($displacedSha -ne $expected) {
                Invoke-SystemV7PreservingMetaRestore -TargetPath $target -TransactionPath $transactionPath -RestoreSourcePath $displacedPath -ExpectedTargetSha256 $candidateSha | Out-Null
                Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker ABORTED -Reason 'compare_and_swap_conflict_rolled_back_without_data_loss'
                Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.Conflicts | Out-Null
                $transactionPath = $null
                throw "COMPARE_AND_SWAP_CONFLICT: expected=$expected actual=$displacedSha"
            }

            if ($DeferFinalization) {
                $result = [pscustomobject]@{
                    Schema = 'SYSTEM_V7_DEFERRED_META_TRANSACTION_V1'
                    ProjectPath = $project
                    TargetPath = $target
                    TransactionPath = $transactionPath
                    ExpectedSha256 = $expected
                    CandidateSha256 = $candidateSha
                }
                $transactionPath = $null
                return $result
            }
            Write-SystemV7MetaTransactionMarker -TransactionPath $transactionPath -Marker COMMITTED -Reason 'atomic_replace_verified'
            Move-SystemV7MetaTransactionToArchive -TransactionPath $transactionPath -ArchiveRoot $paths.History | Out-Null
            $transactionPath = $null
        } finally {
            if ($ownsLock) { Exit-SystemV7ProjectMetaLock -LockStream $lockStream }
        }
    } catch {
        # Nie kasuj niejednoznacznej transakcji. Recovery przy kolejnym wejściu
        # zachowa wszystkie wersje albo zatrzyma mutatory do ręcznego audytu.
        throw
    }
}

function Write-Utf8TextAtomicCompareAndSwap {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$ExpectedCurrentSha256,
        [IO.FileStream]$HeldLockStream,
        [scriptblock]$InternalBeforeReplaceTestHook,
        [switch]$DeferFinalization
    )
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    Write-BytesAtomicCompareAndSwap -Path $Path -Bytes $bytes -ExpectedCurrentSha256 $ExpectedCurrentSha256 -HeldLockStream $HeldLockStream -InternalBeforeReplaceTestHook $InternalBeforeReplaceTestHook -DeferFinalization:$DeferFinalization
}

function Get-OwnerOverrideMetaContextSha256 {
    param(
        [Parameter(Mandatory)][string]$MetaText,
        [Parameter(Mandatory)][string]$CanonicalOwner
    )
    $normalized = $MetaText
    foreach ($entry in @(
        @('STAGE_OWNER',$CanonicalOwner),
        @('OWNER_OVERRIDE','BRAK'),
        @('OWNER_OVERRIDE_RECEIPT_PATH','BRAK'),
        @('OWNER_OVERRIDE_RECEIPT_SHA256','BRAK')
    )) {
        $pattern = "(?m)^$([regex]::Escape($entry[0])):\s*.*?$"
        if ([regex]::Matches($normalized, $pattern).Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $($entry[0])" }
        $normalized = [regex]::Replace($normalized, $pattern, "$($entry[0]): $($entry[1])")
    }
    $handoffPattern = '(?m)^- Właściciel:\s*.*?$'
    if ([regex]::Matches($normalized, $handoffPattern).Count -ne 1) { throw 'HANDOFF_FIELD_COUNT_INVALID: Właściciel' }
    $normalized = [regex]::Replace($normalized, $handoffPattern, "- Właściciel: $CanonicalOwner")
    return Get-Sha256HexFromText -Text $normalized
}

function Get-StateReceiptMetaContextSha256 {
    param([Parameter(Mandatory)][string]$MetaText)

    $normalized = $MetaText
    foreach ($field in @('LAST_STATE_RECEIPT_PATH','LAST_STATE_RECEIPT_SHA256')) {
        $pattern = "(?m)^$([regex]::Escape($field)):\s*.*?$"
        if ([regex]::Matches($normalized, $pattern).Count -ne 1) { throw "META_FIELD_COUNT_INVALID: $field" }
        $normalized = [regex]::Replace($normalized, $pattern, "${field}: BRAK")
    }
    Get-Sha256HexFromText -Text $normalized
}

function Get-SystemV7BlockDecisionIntentSha256 {
    param(
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][string]$InputMetaSha256,
        [Parameter(Mandatory)][string]$PreviousStateReceiptPath,
        [Parameter(Mandatory)][string]$PreviousStateReceiptSha256,
        [Parameter(Mandatory)][string]$FromStage,
        [Parameter(Mandatory)][string]$LastGate,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][bool]$NoGo
    )
    $intent = [ordered]@{
        operation='BLOCK'; project_origin_sha256=$ProjectOriginSha256; input_meta_sha256=$InputMetaSha256
        previous_state_receipt_path=$PreviousStateReceiptPath; previous_state_receipt_sha256=$PreviousStateReceiptSha256
        from_stage=$FromStage; to_stage='BLOCKED'; last_gate=$LastGate; reason=$Reason; no_go=$NoGo
    }
    Get-Sha256HexFromText -Text (($intent | ConvertTo-Json -Depth 8) + "`n")
}

function Get-SystemV7UnblockDecisionIntentSha256 {
    param(
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][string]$InputMetaSha256,
        [Parameter(Mandatory)][string]$PreviousStateReceiptPath,
        [Parameter(Mandatory)][string]$PreviousStateReceiptSha256,
        [Parameter(Mandatory)][string]$RestoreStage,
        [Parameter(Mandatory)][string]$BlockedLastGate,
        [Parameter(Mandatory)][string]$ResultLastGate,
        [Parameter(Mandatory)][string]$BlockReceiptSha256,
        [Parameter(Mandatory)][string]$Resolution
    )
    $intent = [ordered]@{
        operation='UNBLOCK'; project_origin_sha256=$ProjectOriginSha256; input_meta_sha256=$InputMetaSha256
        previous_state_receipt_path=$PreviousStateReceiptPath; previous_state_receipt_sha256=$PreviousStateReceiptSha256
        restore_stage=$RestoreStage; blocked_last_gate=$BlockedLastGate; result_last_gate=$ResultLastGate
        block_receipt_sha256=$BlockReceiptSha256; resolution=$Resolution
    }
    Get-Sha256HexFromText -Text (($intent | ConvertTo-Json -Depth 8) + "`n")
}

function New-SystemV7BlockDecisionReceiptRecord {
    param(
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][string]$InputMetaSha256,
        [Parameter(Mandatory)][string]$ResultMetaContextSha256,
        [Parameter(Mandatory)][string]$PreviousStateReceiptPath,
        [Parameter(Mandatory)][string]$PreviousStateReceiptSha256,
        [Parameter(Mandatory)][string]$FromStage,
        [Parameter(Mandatory)][string]$LastGate,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][bool]$NoGo,
        [Parameter(Mandatory)][string]$CreatedAtUtc
    )
    $intentSha = Get-SystemV7BlockDecisionIntentSha256 -ProjectOriginSha256 $ProjectOriginSha256 `
        -InputMetaSha256 $InputMetaSha256 -PreviousStateReceiptPath $PreviousStateReceiptPath `
        -PreviousStateReceiptSha256 $PreviousStateReceiptSha256 -FromStage $FromStage -LastGate $LastGate `
        -Reason $Reason -NoGo $NoGo
    $payload = [ordered]@{
        schema='SYSTEM_V7_BLOCK_DECISION_RECEIPT_V1'; actor='DAWID'
        attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'; verdict='APPROVED'
        intent_sha256=$intentSha
        project_origin_sha256=$ProjectOriginSha256; input_meta_sha256=$InputMetaSha256
        result_meta_context_sha256=$ResultMetaContextSha256
        previous_state_receipt_path=$PreviousStateReceiptPath; previous_state_receipt_sha256=$PreviousStateReceiptSha256
        from_stage=$FromStage; to_stage='BLOCKED'; last_gate=$LastGate; reason=$Reason; no_go=$NoGo
        created_at_utc=$CreatedAtUtc
    }
    $binding = Get-Sha256HexFromText -Text (($payload | ConvertTo-Json -Depth 8) + "`n")
    $record = [ordered]@{}
    foreach ($entry in $payload.GetEnumerator()) { $record[$entry.Key] = $entry.Value }
    $record.binding_sha256 = $binding
    [pscustomobject]$record
}

function New-SystemV7UnblockDecisionReceiptRecord {
    param(
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][string]$InputMetaSha256,
        [Parameter(Mandatory)][string]$ResultMetaContextSha256,
        [Parameter(Mandatory)][string]$PreviousStateReceiptPath,
        [Parameter(Mandatory)][string]$PreviousStateReceiptSha256,
        [Parameter(Mandatory)][string]$RestoreStage,
        [Parameter(Mandatory)][string]$BlockedLastGate,
        [Parameter(Mandatory)][string]$ResultLastGate,
        [Parameter(Mandatory)][string]$BlockReceiptSha256,
        [Parameter(Mandatory)][string]$Resolution,
        [Parameter(Mandatory)][string]$CreatedAtUtc
    )
    $intentSha = Get-SystemV7UnblockDecisionIntentSha256 -ProjectOriginSha256 $ProjectOriginSha256 `
        -InputMetaSha256 $InputMetaSha256 -PreviousStateReceiptPath $PreviousStateReceiptPath `
        -PreviousStateReceiptSha256 $PreviousStateReceiptSha256 -RestoreStage $RestoreStage `
        -BlockedLastGate $BlockedLastGate -ResultLastGate $ResultLastGate `
        -BlockReceiptSha256 $BlockReceiptSha256 -Resolution $Resolution
    $payload = [ordered]@{
        schema='SYSTEM_V7_UNBLOCK_DECISION_RECEIPT_V1'; actor='DAWID'
        attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'; verdict='APPROVED'
        intent_sha256=$intentSha
        project_origin_sha256=$ProjectOriginSha256; input_meta_sha256=$InputMetaSha256
        result_meta_context_sha256=$ResultMetaContextSha256
        previous_state_receipt_path=$PreviousStateReceiptPath; previous_state_receipt_sha256=$PreviousStateReceiptSha256
        restore_stage=$RestoreStage; blocked_last_gate=$BlockedLastGate; result_last_gate=$ResultLastGate
        block_receipt_sha256=$BlockReceiptSha256; resolution=$Resolution; created_at_utc=$CreatedAtUtc
    }
    $binding = Get-Sha256HexFromText -Text (($payload | ConvertTo-Json -Depth 8) + "`n")
    $record = [ordered]@{}
    foreach ($entry in $payload.GetEnumerator()) { $record[$entry.Key] = $entry.Value }
    $record.binding_sha256 = $binding
    [pscustomobject]$record
}

function New-SystemV7ReopenDecisionReceiptRecord {
    param(
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][string]$InputMetaSha256,
        [Parameter(Mandatory)][string]$ResultMetaContextSha256,
        [Parameter(Mandatory)][string]$PreviousStateReceiptPath,
        [Parameter(Mandatory)][string]$PreviousStateReceiptSha256,
        [Parameter(Mandatory)][string]$FromStage,
        [Parameter(Mandatory)][string]$TargetStage,
        [Parameter(Mandatory)][string]$PreviousLastGate,
        [Parameter(Mandatory)][string]$ResultLastGate,
        [Parameter(Mandatory)][string]$ReasonCode,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$ApprovalMode,
        [Parameter(Mandatory)][object[]]$ArtifactHashesBefore,
        [Parameter(Mandatory)][object[]]$InvalidationManifest,
        [Parameter(Mandatory)][string]$CreatedAtUtc
    )
    $intent=[ordered]@{operation='REOPEN';project_origin_sha256=$ProjectOriginSha256;input_meta_sha256=$InputMetaSha256;previous_state_receipt_path=$PreviousStateReceiptPath;previous_state_receipt_sha256=$PreviousStateReceiptSha256;from_stage=$FromStage;target_stage=$TargetStage;previous_last_gate=$PreviousLastGate;result_last_gate=$ResultLastGate;reason_code=$ReasonCode;scope=$Scope;approval_mode=$ApprovalMode;artifact_hashes_before=@($ArtifactHashesBefore);invalidation_manifest=@($InvalidationManifest)}
    $intentSha=Get-Sha256HexFromText -Text (($intent|ConvertTo-Json -Depth 16)+"`n")
    $payload=[ordered]@{schema='SYSTEM_V7_STAGE_REOPEN_RECEIPT_V1';actor='DAWID';attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY';verdict='APPROVED';intent_sha256=$intentSha;project_origin_sha256=$ProjectOriginSha256;input_meta_sha256=$InputMetaSha256;result_meta_context_sha256=$ResultMetaContextSha256;previous_state_receipt_path=$PreviousStateReceiptPath;previous_state_receipt_sha256=$PreviousStateReceiptSha256;from_stage=$FromStage;target_stage=$TargetStage;previous_last_gate=$PreviousLastGate;result_last_gate=$ResultLastGate;reason_code=$ReasonCode;scope=$Scope;approval_mode=$ApprovalMode;artifact_hashes_before=@($ArtifactHashesBefore);invalidation_manifest=@($InvalidationManifest);created_at_utc=$CreatedAtUtc}
    $binding=Get-Sha256HexFromText -Text (($payload|ConvertTo-Json -Depth 16)+"`n");$record=[ordered]@{};foreach($entry in $payload.GetEnumerator()){$record[$entry.Key]=$entry.Value};$record.binding_sha256=$binding;[pscustomobject]$record
}

function Test-SystemV7StateDecisionReceiptFile {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][string]$ExpectedOriginSha256,
        [string]$ExpectedReceiptSha256
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $receipt = [IO.Path]::GetFullPath($ReceiptPath)
    $problems = [Collections.Generic.List[string]]::new()
    $data = $null
    $kind = $null
    if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
        $problems.Add('STATE_RECEIPT_FILE_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); ReceiptPath=$receipt; ReceiptSha256=$null; RelativePath=$null; Kind=$null; Data=$null }
    }
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        try { Assert-SystemV7PathNoReparse -Path $receipt -ContainmentRoot $project | Out-Null }
        catch { $problems.Add($_.Exception.Message) }
    }
    $relative = ([IO.Path]::GetRelativePath($project, $receipt)).Replace('\','/')
    if ($relative -notmatch '^_work/system/state-decisions/(?:block|unblock|reopen)-[A-F0-9]{64}\.json$') {
        $problems.Add('STATE_RECEIPT_PATH_INVALID')
    }
    $actualSha = (Get-FileHash -LiteralPath $receipt -Algorithm SHA256).Hash
    if ($ExpectedReceiptSha256 -and $actualSha -cne $ExpectedReceiptSha256) { $problems.Add('STATE_RECEIPT_SHA_MISMATCH') }
    $raw = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8
    try { $data = $raw | ConvertFrom-Json -DateKind String }
    catch {
        $problems.Add("STATE_RECEIPT_INVALID_JSON: $($_.Exception.Message)")
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); ReceiptPath=$receipt; ReceiptSha256=$actualSha; RelativePath=$relative; Kind=$null; Data=$null }
    }
    $schema = [string](Get-ObjectPropertyValue -Object $data -Name 'schema')
    $record = $null
    try {
        if ($schema -ceq 'SYSTEM_V7_BLOCK_DECISION_RECEIPT_V1') {
            $kind = 'BLOCK'
            if ((Get-ObjectPropertyValue -Object $data -Name 'no_go') -isnot [bool]) { throw 'BLOCK_DECISION_NO_GO_INVALID' }
            $record = New-SystemV7BlockDecisionReceiptRecord `
                -ProjectOriginSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'project_origin_sha256')) `
                -InputMetaSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'input_meta_sha256')) `
                -ResultMetaContextSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'result_meta_context_sha256')) `
                -PreviousStateReceiptPath ([string](Get-ObjectPropertyValue -Object $data -Name 'previous_state_receipt_path')) `
                -PreviousStateReceiptSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'previous_state_receipt_sha256')) `
                -FromStage ([string](Get-ObjectPropertyValue -Object $data -Name 'from_stage')) `
                -LastGate ([string](Get-ObjectPropertyValue -Object $data -Name 'last_gate')) `
                -Reason ([string](Get-ObjectPropertyValue -Object $data -Name 'reason')) `
                -NoGo ([bool](Get-ObjectPropertyValue -Object $data -Name 'no_go')) `
                -CreatedAtUtc ([string](Get-ObjectPropertyValue -Object $data -Name 'created_at_utc'))
        } elseif ($schema -ceq 'SYSTEM_V7_UNBLOCK_DECISION_RECEIPT_V1') {
            $kind = 'UNBLOCK'
            $record = New-SystemV7UnblockDecisionReceiptRecord `
                -ProjectOriginSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'project_origin_sha256')) `
                -InputMetaSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'input_meta_sha256')) `
                -ResultMetaContextSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'result_meta_context_sha256')) `
                -PreviousStateReceiptPath ([string](Get-ObjectPropertyValue -Object $data -Name 'previous_state_receipt_path')) `
                -PreviousStateReceiptSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'previous_state_receipt_sha256')) `
                -RestoreStage ([string](Get-ObjectPropertyValue -Object $data -Name 'restore_stage')) `
                -BlockedLastGate ([string](Get-ObjectPropertyValue -Object $data -Name 'blocked_last_gate')) `
                -ResultLastGate ([string](Get-ObjectPropertyValue -Object $data -Name 'result_last_gate')) `
                -BlockReceiptSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'block_receipt_sha256')) `
                -Resolution ([string](Get-ObjectPropertyValue -Object $data -Name 'resolution')) `
                -CreatedAtUtc ([string](Get-ObjectPropertyValue -Object $data -Name 'created_at_utc'))
        } elseif ($schema -ceq 'SYSTEM_V7_STAGE_REOPEN_RECEIPT_V1') {
            $kind = 'REOPEN'
            $record = New-SystemV7ReopenDecisionReceiptRecord `
                -ProjectOriginSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'project_origin_sha256')) `
                -InputMetaSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'input_meta_sha256')) `
                -ResultMetaContextSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'result_meta_context_sha256')) `
                -PreviousStateReceiptPath ([string](Get-ObjectPropertyValue -Object $data -Name 'previous_state_receipt_path')) `
                -PreviousStateReceiptSha256 ([string](Get-ObjectPropertyValue -Object $data -Name 'previous_state_receipt_sha256')) `
                -FromStage ([string](Get-ObjectPropertyValue -Object $data -Name 'from_stage')) `
                -TargetStage ([string](Get-ObjectPropertyValue -Object $data -Name 'target_stage')) `
                -PreviousLastGate ([string](Get-ObjectPropertyValue -Object $data -Name 'previous_last_gate')) `
                -ResultLastGate ([string](Get-ObjectPropertyValue -Object $data -Name 'result_last_gate')) `
                -ReasonCode ([string](Get-ObjectPropertyValue -Object $data -Name 'reason_code')) `
                -Scope ([string](Get-ObjectPropertyValue -Object $data -Name 'scope')) `
                -ApprovalMode ([string](Get-ObjectPropertyValue -Object $data -Name 'approval_mode')) `
                -ArtifactHashesBefore @((Get-ObjectPropertyValue -Object $data -Name 'artifact_hashes_before')) `
                -InvalidationManifest @((Get-ObjectPropertyValue -Object $data -Name 'invalidation_manifest')) `
                -CreatedAtUtc ([string](Get-ObjectPropertyValue -Object $data -Name 'created_at_utc'))
        } else {
            throw 'STATE_RECEIPT_SCHEMA_INVALID'
        }
    } catch { $problems.Add($_.Exception.Message) }

    if ($null -ne $record) {
        $expectedNames = @($record.PSObject.Properties.Name)
        $actualNames = @($data.PSObject.Properties.Name)
        if ($actualNames.Count -ne $expectedNames.Count -or @(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames).Count -gt 0) {
            $problems.Add("${kind}_DECISION_RECEIPT_FIELDS_INVALID")
        }
        $canonical = ($record | ConvertTo-Json -Depth 16) + "`n"
        if (-not (Test-Utf8FileCanonicalBytes -Path $receipt -ExpectedText $canonical)) { $problems.Add("${kind}_DECISION_RECEIPT_CANONICAL_BYTES_MISMATCH") }
        $binding = [string](Get-ObjectPropertyValue -Object $record -Name 'binding_sha256')
        if ([string](Get-ObjectPropertyValue -Object $data -Name 'binding_sha256') -cne $binding) { $problems.Add("${kind}_DECISION_RECEIPT_BINDING_MISMATCH") }
        $intent = [string](Get-ObjectPropertyValue -Object $record -Name 'intent_sha256')
        if ([IO.Path]::GetFileName($receipt) -cne "$($kind.ToLowerInvariant())-$intent.json") { $problems.Add("${kind}_DECISION_RECEIPT_FILENAME_MISMATCH") }
    }
    if ([string](Get-ObjectPropertyValue -Object $data -Name 'project_origin_sha256') -cne $ExpectedOriginSha256) { $problems.Add("${kind}_DECISION_PROJECT_ORIGIN_MISMATCH") }
    foreach ($hashField in @('intent_sha256','project_origin_sha256','input_meta_sha256','result_meta_context_sha256','binding_sha256')) {
        if ([string](Get-ObjectPropertyValue -Object $data -Name $hashField) -notmatch '^[A-F0-9]{64}$') { $problems.Add("${kind}_DECISION_HASH_INVALID: $hashField") }
    }
    $previousPath = [string](Get-ObjectPropertyValue -Object $data -Name 'previous_state_receipt_path')
    $previousSha = [string](Get-ObjectPropertyValue -Object $data -Name 'previous_state_receipt_sha256')
    if (($previousPath -eq 'BRAK') -xor ($previousSha -eq 'BRAK')) { $problems.Add("${kind}_DECISION_PREVIOUS_POINTER_INCOMPLETE") }
    if ($previousPath -ne 'BRAK' -and ($previousPath -notmatch '^_work/system/state-decisions/(?:block|unblock|reopen)-[A-F0-9]{64}\.json$' -or $previousSha -notmatch '^[A-F0-9]{64}$')) {
        $problems.Add("${kind}_DECISION_PREVIOUS_POINTER_INVALID")
    }
    if (-not (Test-ReceiptTimestamp -Value (Get-ObjectPropertyValue -Object $data -Name 'created_at_utc'))) { $problems.Add("${kind}_DECISION_CREATED_AT_INVALID") }
    if ($kind -eq 'BLOCK') {
        $fromStage = [string](Get-ObjectPropertyValue -Object $data -Name 'from_stage')
        $lastGate = [string](Get-ObjectPropertyValue -Object $data -Name 'last_gate')
        if ([array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5'), $fromStage) -lt 0) { $problems.Add('BLOCK_DECISION_FROM_STAGE_INVALID') }
        if (-not (Test-ConcreteNote -Text ([string](Get-ObjectPropertyValue -Object $data -Name 'reason')) -MinimumLength 12)) { $problems.Add('BLOCK_DECISION_REASON_INVALID') }
        $allowedGate = switch ($fromStage) {
            'W0' { if ([bool](Get-ObjectPropertyValue -Object $data -Name 'no_go')) { @('W0_NO_GO') } else { @('PROJECT_INITIALIZED') } }
            'K0' { @('W0_GO','W0_GO_WARUNKOWE') }
            'K1' { @('K0_PASS') }; 'K2' { @('K1_PASS') }; 'K2B' { @('K2_PASS') }
            'K3' { @('K2B_PASS') }; 'K4' { @('K3_PASS') }; 'K5' { @('K4_PASS') }
            default { @() }
        }
        if ([array]::IndexOf([object[]]$allowedGate, $lastGate) -lt 0) { $problems.Add('BLOCK_DECISION_LAST_GATE_INVALID') }
    } elseif ($kind -eq 'UNBLOCK') {
        $restoreStage = [string](Get-ObjectPropertyValue -Object $data -Name 'restore_stage')
        $blockedGate = [string](Get-ObjectPropertyValue -Object $data -Name 'blocked_last_gate')
        $resultGate = [string](Get-ObjectPropertyValue -Object $data -Name 'result_last_gate')
        if ([array]::IndexOf(@('W0','K0','K1','K2','K2B','K3','K4','K5'), $restoreStage) -lt 0) { $problems.Add('UNBLOCK_DECISION_RESTORE_STAGE_INVALID') }
        if (-not (Test-ConcreteNote -Text ([string](Get-ObjectPropertyValue -Object $data -Name 'resolution')) -MinimumLength 12)) { $problems.Add('UNBLOCK_DECISION_RESOLUTION_INVALID') }
        if ([string](Get-ObjectPropertyValue -Object $data -Name 'block_receipt_sha256') -notmatch '^[A-F0-9]{64}$') { $problems.Add('UNBLOCK_DECISION_BLOCK_SHA_INVALID') }
        $allowedBlockedGate = switch ($restoreStage) {
            'W0' { @('PROJECT_INITIALIZED','W0_NO_GO') }; 'K0' { @('W0_GO','W0_GO_WARUNKOWE') }
            'K1' { @('K0_PASS') }; 'K2' { @('K1_PASS') }; 'K2B' { @('K2_PASS') }
            'K3' { @('K2B_PASS') }; 'K4' { @('K3_PASS') }; 'K5' { @('K4_PASS') }
            default { @() }
        }
        if ([array]::IndexOf([object[]]$allowedBlockedGate, $blockedGate) -lt 0) { $problems.Add('UNBLOCK_DECISION_BLOCKED_GATE_INVALID') }
        $expectedResultGate = if ($restoreStage -eq 'W0' -and $blockedGate -eq 'W0_NO_GO') { 'PROJECT_INITIALIZED' } else { $blockedGate }
        if ($resultGate -cne $expectedResultGate) { $problems.Add('UNBLOCK_DECISION_RESULT_GATE_INVALID') }
    } elseif ($kind -eq 'REOPEN') {
        $fromStage=[string](Get-ObjectPropertyValue -Object $data -Name 'from_stage');$targetStage=[string](Get-ObjectPropertyValue -Object $data -Name 'target_stage')
        $allowed=@('K3>K2B','K4>K3','K4>K2B','K5>K3','K5>K2B')
        if([array]::IndexOf($allowed,"$fromStage>$targetStage") -lt 0){$problems.Add('REOPEN_ROUTE_INVALID')}
        if([array]::IndexOf(@('MISSING_EVIDENCE','ARCHITECTURE_CONFLICT','OVERLOADED_PACKET','UNSUPPORTED_BRIDGE','PROSE_CORRECTION','SOURCE_CHANGE','SCOPE_CHANGE','SCENE_WEAVE_CHANGE','QUESTION_REVEAL_CHANGE','SIGNIFICANT_K5_CORRECTION'),[string](Get-ObjectPropertyValue -Object $data -Name 'reason_code')) -lt 0){$problems.Add('REOPEN_REASON_CODE_INVALID')}
        if(-not(Test-ConcreteNote -Text ([string](Get-ObjectPropertyValue -Object $data -Name 'scope')) -MinimumLength 8)){$problems.Add('REOPEN_SCOPE_INVALID')}
        if(@((Get-ObjectPropertyValue -Object $data -Name 'artifact_hashes_before')).Count -eq 0 -or @((Get-ObjectPropertyValue -Object $data -Name 'invalidation_manifest')).Count -eq 0){$problems.Add('REOPEN_MANIFEST_EMPTY')}
    }
    [pscustomobject]@{ Valid=$problems.Count -eq 0; Errors=@($problems); ReceiptPath=$receipt; ReceiptSha256=$actualSha; RelativePath=$relative; Kind=$kind; Data=$data }
}

function Get-StateReceiptHeadState {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [string]$MetaText
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $metaPath = Join-Path $project 'meta.md'
    $problems = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        return [pscustomobject]@{ Valid=$false; Errors=@('STATE_RECEIPT_META_MISSING'); Required=$false; ReceiptPath=$null; ReceiptSha256=$null; Kind=$null; Data=$null }
    }
    if (-not $PSBoundParameters.ContainsKey('MetaText')) { $MetaText = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 }
    $getField = {
        param([string]$Name)
        $matches = @([regex]::Matches($MetaText, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$"))
        if ($matches.Count -ne 1) { $problems.Add("STATE_RECEIPT_META_FIELD_COUNT_INVALID: $Name=$($matches.Count)"); return $null }
        $matches[0].Groups[1].Value.Trim()
    }
    $headRelative = & $getField 'LAST_STATE_RECEIPT_PATH'
    $headSha = & $getField 'LAST_STATE_RECEIPT_SHA256'
    $directory = Join-Path $project '_work\system\state-decisions'
    $history = if (Test-Path -LiteralPath $directory -PathType Container) { @(Get-ChildItem -LiteralPath $directory -File -Force | Where-Object Name -Match '^(?:block|unblock|reopen)-[A-F0-9]{64}\.json$') } else { @() }
    if ($headRelative -eq 'BRAK' -or $headSha -eq 'BRAK') {
        if ($headRelative -ne 'BRAK' -or $headSha -ne 'BRAK') { $problems.Add('STATE_RECEIPT_HEAD_POINTER_INCOMPLETE') }
        if ($history.Count -gt 0) { $problems.Add('STATE_RECEIPT_HEAD_MISSING_WITH_HISTORY') }
        return [pscustomobject]@{ Valid=$problems.Count -eq 0; Errors=@($problems); Required=$history.Count -gt 0; ReceiptPath=$null; ReceiptSha256=$null; Kind=$null; Data=$null }
    }
    if ($headRelative -notmatch '^_work/system/state-decisions/(?:block|unblock|reopen)-[A-F0-9]{64}\.json$' -or $headSha -notmatch '^[A-F0-9]{64}$') {
        $problems.Add('STATE_RECEIPT_HEAD_POINTER_INVALID')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Required=$true; ReceiptPath=$null; ReceiptSha256=$headSha; Kind=$null; Data=$null }
    }
    $origin = if ($null -ne (Get-Command Get-SystemV7ProjectOriginState -ErrorAction SilentlyContinue)) { Get-SystemV7ProjectOriginState -ProjectPath $project } else { $null }
    if (-not $origin -or -not $origin.Valid) {
        $problems.Add('STATE_RECEIPT_PROJECT_ORIGIN_INVALID')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Required=$true; ReceiptPath=$null; ReceiptSha256=$headSha; Kind=$null; Data=$null }
    }
    $headPath = [IO.Path]::GetFullPath((Join-Path $project $headRelative.Replace('/','\')))
    $head = Test-SystemV7StateDecisionReceiptFile -ProjectPath $project -ReceiptPath $headPath -ExpectedOriginSha256 $origin.Sha256 -ExpectedReceiptSha256 $headSha
    foreach ($problem in @($head.Errors)) { $problems.Add($problem) }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $cursor = $head
    $childKind = $null
    while ($cursor -and $cursor.Data) {
        if (-not $seen.Add($cursor.RelativePath)) { $problems.Add('STATE_RECEIPT_CHAIN_CYCLE'); break }
        $previousRelative = [string](Get-ObjectPropertyValue -Object $cursor.Data -Name 'previous_state_receipt_path')
        $previousSha = [string](Get-ObjectPropertyValue -Object $cursor.Data -Name 'previous_state_receipt_sha256')
        if ($previousRelative -eq 'BRAK' -and $previousSha -eq 'BRAK') {
            break
        }
        if ($previousRelative -notmatch '^_work/system/state-decisions/(?:block|unblock|reopen)-[A-F0-9]{64}\.json$' -or $previousSha -notmatch '^[A-F0-9]{64}$') { break }
        $previousPath = [IO.Path]::GetFullPath((Join-Path $project $previousRelative.Replace('/','\')))
        $previous = Test-SystemV7StateDecisionReceiptFile -ProjectPath $project -ReceiptPath $previousPath -ExpectedOriginSha256 $origin.Sha256 -ExpectedReceiptSha256 $previousSha
        foreach ($problem in @($previous.Errors)) { $problems.Add("STATE_RECEIPT_CHAIN: $problem") }
        if ($cursor.Kind -eq 'UNBLOCK' -and [string](Get-ObjectPropertyValue -Object $cursor.Data -Name 'block_receipt_sha256') -cne $previousSha) {
            $problems.Add('STATE_RECEIPT_CHAIN_BLOCK_SHA_MISMATCH')
        }
        if ($cursor.Kind -eq 'UNBLOCK' -and $previous.Kind -eq 'BLOCK') {
            if ([string](Get-ObjectPropertyValue -Object $cursor.Data -Name 'restore_stage') -cne [string](Get-ObjectPropertyValue -Object $previous.Data -Name 'from_stage')) {
                $problems.Add('STATE_RECEIPT_CHAIN_RESTORE_STAGE_MISMATCH')
            }
            if ([string](Get-ObjectPropertyValue -Object $cursor.Data -Name 'blocked_last_gate') -cne [string](Get-ObjectPropertyValue -Object $previous.Data -Name 'last_gate')) {
                $problems.Add('STATE_RECEIPT_CHAIN_BLOCKED_GATE_MISMATCH')
            }
        }
        $childKind = $cursor.Kind
        $cursor = $previous
    }

    $stage = & $getField 'CURRENT_STAGE'
    if ($stage -eq 'BLOCKED') {
        if ($head.Kind -ne 'BLOCK') { $problems.Add('STATE_RECEIPT_HEAD_KIND_NOT_BLOCK') }
        if ($head.Data) {
            try {
                if ([string](Get-ObjectPropertyValue -Object $head.Data -Name 'result_meta_context_sha256') -cne (Get-StateReceiptMetaContextSha256 -MetaText $MetaText)) {
                    $problems.Add('BLOCK_DECISION_RESULT_META_CONTEXT_MISMATCH')
                }
            } catch { $problems.Add($_.Exception.Message) }
            if ([string](Get-ObjectPropertyValue -Object $head.Data -Name 'from_stage') -cne (& $getField 'BLOCKED_FROM_STAGE')) { $problems.Add('BLOCK_DECISION_FROM_STAGE_MISMATCH') }
            if ([string](Get-ObjectPropertyValue -Object $head.Data -Name 'reason') -cne (& $getField 'BLOCKED_REASON')) { $problems.Add('BLOCK_DECISION_REASON_MISMATCH') }
            if ([string](Get-ObjectPropertyValue -Object $head.Data -Name 'last_gate') -cne (& $getField 'LAST_GATE')) { $problems.Add('BLOCK_DECISION_LAST_GATE_MISMATCH') }
        }
    } elseif ($head.Kind -eq 'UNBLOCK') {
        if ($head.Kind -ne 'UNBLOCK') { $problems.Add('STATE_RECEIPT_HEAD_KIND_NOT_UNBLOCK') }
        if ($head.Data) {
            $restore = [string](Get-ObjectPropertyValue -Object $head.Data -Name 'restore_stage')
            $order = @('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE')
            if ([array]::IndexOf($order, $stage) -lt [array]::IndexOf($order, $restore)) { $problems.Add('STATE_RECEIPT_CURRENT_STAGE_PRECEDES_UNBLOCK_RESTORE') }
            $currentContext = $null
            try { $currentContext = Get-StateReceiptMetaContextSha256 -MetaText $MetaText } catch { $problems.Add($_.Exception.Message) }
            $resultContext = [string](Get-ObjectPropertyValue -Object $head.Data -Name 'result_meta_context_sha256')
            if ($currentContext -cne $resultContext -and [array]::IndexOf($order, $stage) -eq [array]::IndexOf($order, $restore)) {
                # Ten sam etap może legalnie uzupełniać pola robocze meta przed kolejnym Advance.
                # Stanowe pola CURRENT_STAGE/LAST_GATE/OWNER/BLOCKED są kontrolowane osobno przez Validate-Project.
                $resultGate = [string](Get-ObjectPropertyValue -Object $head.Data -Name 'result_last_gate')
                if ((& $getField 'LAST_GATE') -cne $resultGate) { $problems.Add('STATE_RECEIPT_SAME_STAGE_GATE_MISMATCH') }
            }
        }
    } elseif ($head.Kind -eq 'REOPEN') {
        if($head.Data){
            $target=[string](Get-ObjectPropertyValue -Object $head.Data -Name 'target_stage');$order=@('W0','K0','K1','K2','K2B','K3','K4','K5','COMPLETE');$currentIndex=[array]::IndexOf($order,$stage);$targetIndex=[array]::IndexOf($order,$target)
            if($targetIndex -lt 0 -or $currentIndex -lt $targetIndex){$problems.Add('STATE_RECEIPT_CURRENT_STAGE_PRECEDES_REOPEN_TARGET')}
            elseif($currentIndex -eq $targetIndex){
                # Na etapie docelowym reopen jest aktywnym transient gate. Pola
                # robocze (prefix, act sequence, continuity) zmieniają się w
                # trakcie legalnej regeneracji, więc historycznego pełnego
                # context SHA nie porównujemy do żywego meta. Kontrolujemy
                # nadal etap, dokładny gate i cały immutable receipt chain.
                if(([string](Get-ObjectPropertyValue -Object $head.Data -Name 'result_last_gate')) -cne (&$getField 'LAST_GATE')){$problems.Add('REOPEN_DECISION_RESULT_GATE_MISMATCH')}
            }
        }
    } else {
        # Aktywny etap po BLOCK musi wynikać z legalnego UNBLOCK. Samo ręczne
        # przestawienie CURRENT_STAGE nie może ominąć decyzji i receiptu.
        $problems.Add('STATE_RECEIPT_HEAD_KIND_NOT_UNBLOCK')
    }
    [pscustomobject]@{ Valid=$problems.Count -eq 0; Errors=@($problems); Required=$true; ReceiptPath=$head.ReceiptPath; ReceiptSha256=$head.ReceiptSha256; Kind=$head.Kind; Data=$head.Data }
}

function Get-AppliedBlockDecisionReceiptState {
    param([Parameter(Mandatory)][string]$ProjectPath)
    $state = Get-StateReceiptHeadState -ProjectPath $ProjectPath
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($problem in @($state.Errors)) { $problems.Add($problem) }
    if ($state.Kind -ne 'BLOCK') { $problems.Add('BLOCK_DECISION_RECEIPT_HEAD_NOT_BLOCK') }
    [pscustomobject]@{ Valid=$problems.Count -eq 0; Errors=@($problems); ReceiptPath=$state.ReceiptPath; ReceiptSha256=$state.ReceiptSha256; Data=$state.Data }
}

function Get-EditorialExceptionReceiptState {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][ValidateSet('K2_ONE_DIRECTION','K3_BUDGET_OVERRIDE','K4_Q1_ACCEPTANCE','K4_Q2_ACCEPTANCE','K4_FACTCHECK_DECISION')][string]$ExceptionType,
        [Parameter(Mandatory)][string]$ArtifactPath,
        [Parameter(Mandatory)][string]$TargetId,
        [string]$ExpectedDecision,
        [string]$ExpectedReason,
        [string]$ExpectedScope
    )
    $ExceptionType = $ExceptionType.ToUpperInvariant()
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $artifact = [IO.Path]::GetFullPath($ArtifactPath)
    $problems = [Collections.Generic.List[string]]::new()
    if ($ExceptionType -ne 'K2_ONE_DIRECTION') {
        $metaPath = Join-Path $project 'meta.md'
        if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
            $metaText = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
            $workflowMatches = @([regex]::Matches($metaText, '(?m)^WORKFLOW_REVISION:\s*(.*?)\s*$'))
            if ($workflowMatches.Count -eq 1 -and $workflowMatches[0].Groups[1].Value.Trim() -ceq '2026-08-31_NARRATIVE_V2') {
                $problems.Add($(if($ExceptionType -ceq 'K3_BUDGET_OVERRIDE'){'K3_BUDGET_OVERRIDE_FORBIDDEN_IN_NARRATIVE_V2'}else{'LEGACY_K4_EXCEPTION_FORBIDDEN_IN_NARRATIVE_V2'}))
                return [pscustomobject]@{ Valid=$false; Errors=@($problems); ReceiptPath=$null; ReceiptSha256=$null; Data=$null }
            }
        }
    }
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        try { Assert-SystemV7PathNoReparse -Path $artifact -ContainmentRoot $project | Out-Null }
        catch { $problems.Add($_.Exception.Message) }
    }
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
        $problems.Add('EDITORIAL_EXCEPTION_ARTIFACT_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); ReceiptPath=$null; ReceiptSha256=$null; Data=$null }
    }
    $artifactSha = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
    $artifactRelative = ([IO.Path]::GetRelativePath($project, $artifact)).Replace('\','/')
    $directory = Join-Path $project '_work\system\editorial-exceptions'
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        try { Assert-SystemV7PathNoReparse -Path $directory -ContainmentRoot $project | Out-Null }
        catch { $problems.Add($_.Exception.Message) }
    }
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $problems.Add('EDITORIAL_EXCEPTION_RECEIPT_DIRECTORY_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); ReceiptPath=$null; ReceiptSha256=$null; Data=$null }
    }
    $matches = [Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -Force)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $problems.Add("EDITORIAL_EXCEPTION_RECEIPT_REPARSE_POINT: $($file.FullName)"); continue }
        try {
            $data = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
            if ([string]$data.exception_type -ceq $ExceptionType -and [string]$data.artifact_sha256 -eq $artifactSha -and [string]$data.target_id -ceq $TargetId) {
                $matches.Add([pscustomobject]@{ File=$file; Data=$data })
            }
        } catch { $problems.Add("EDITORIAL_EXCEPTION_RECEIPT_INVALID_JSON: $($file.FullName)") }
    }
    if ($matches.Count -ne 1) {
        $problems.Add("EDITORIAL_EXCEPTION_RECEIPT_MATCH_COUNT_INVALID: $($matches.Count)")
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); ReceiptPath=$null; ReceiptSha256=$null; Data=$null }
    }
    $match = $matches[0]
    $data = $match.Data
    $origin = if ($null -ne (Get-Command Get-SystemV7ProjectOriginState -ErrorAction SilentlyContinue)) { Get-SystemV7ProjectOriginState -ProjectPath $project } else { $null }
    if (-not $origin -or -not $origin.Valid) { $problems.Add('EDITORIAL_EXCEPTION_PROJECT_ORIGIN_INVALID') }
    $originSha = if ($origin -and $origin.Valid) { $origin.Sha256 } else { '' }
    $decision = [string]$data.decision
    $reason = [string]$data.reason
    $scope = [string]$data.scope
    $createdRaw = $data.created_at_utc
    $createdAt = if ($createdRaw -is [DateTime]) { $createdRaw.ToUniversalTime().ToString('o') } elseif ($createdRaw -is [DateTimeOffset]) { $createdRaw.UtcDateTime.ToString('o') } else { [string]$createdRaw }
    $bindingText = "ORIGIN=$originSha`nTYPE=$ExceptionType`nARTIFACT=$artifactRelative`nARTIFACT_SHA=$artifactSha`nTARGET=$TargetId`nDECISION=$decision`nREASON=$reason`nSCOPE=$scope`nCREATED_AT_UTC=$createdAt`n"
    $bindingHash = Get-Sha256HexFromText -Text $bindingText
    $expected = [ordered]@{
        schema='SYSTEM_V7_EDITORIAL_EXCEPTION_RECEIPT_V1'; actor='DAWID';
        attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'; verdict='APPROVED';
        project_origin_sha256=$originSha; exception_type=$ExceptionType; artifact_relative=$artifactRelative;
        artifact_sha256=$artifactSha; target_id=$TargetId; decision=$decision; reason=$reason; scope=$scope;
        binding_sha256=$bindingHash; created_at_utc=$createdAt
    }
    foreach ($entry in $expected.GetEnumerator()) {
        $actualValue = if ($entry.Key -eq 'created_at_utc') { $createdAt } else { [string](Get-ObjectPropertyValue -Object $data -Name $entry.Key) }
        if ([string]$actualValue -cne [string]$entry.Value) {
            $problems.Add("EDITORIAL_EXCEPTION_RECEIPT_FIELD_MISMATCH: $($entry.Key)")
        }
    }
    if ($ExpectedDecision -and $decision -cne $ExpectedDecision) { $problems.Add('EDITORIAL_EXCEPTION_DECISION_MISMATCH') }
    if ($ExpectedReason -and $reason -cne $ExpectedReason) { $problems.Add('EDITORIAL_EXCEPTION_REASON_MISMATCH') }
    if ($ExpectedScope -and $scope -cne $ExpectedScope) { $problems.Add('EDITORIAL_EXCEPTION_SCOPE_MISMATCH') }
    if (-not (Test-ConcreteNote -Text $reason -MinimumLength 10) -or $scope -match '[\x00-\x1F\x7F]' -or
        $scope.Trim().Length -lt 5 -or $scope.Trim() -match '^(?i:brak|none|n/?a|todo|tbd|placeholder)$') {
        $problems.Add('EDITORIAL_EXCEPTION_JUSTIFICATION_INVALID')
    }
    if ($decision -match '[\x00-\x1F\x7F]' -or $decision.Trim().Length -lt 3) { $problems.Add('EDITORIAL_EXCEPTION_DECISION_INVALID') }
    if (-not (Test-ReceiptTimestamp -Value $createdAt)) { $problems.Add('EDITORIAL_EXCEPTION_CREATED_AT_INVALID') }
    $expectedName = "$($ExceptionType.ToLowerInvariant())-$artifactSha-$bindingHash.json"
    if ($match.File.Name -cne $expectedName) { $problems.Add('EDITORIAL_EXCEPTION_RECEIPT_FILENAME_MISMATCH') }
    $expectedProperties = @('schema','actor','attestation_scope','verdict','project_origin_sha256','exception_type','artifact_relative','artifact_sha256','target_id','decision','reason','scope','binding_sha256','created_at_utc')
    $actualProperties = @($data.PSObject.Properties.Name)
    if ($actualProperties.Count -ne $expectedProperties.Count -or @(Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties).Count -gt 0) {
        $problems.Add('EDITORIAL_EXCEPTION_RECEIPT_FIELDS_INVALID')
    } else {
        $canonicalJson = ($expected | ConvertTo-Json -Depth 8) + "`n"
        $actualJson = Get-Content -LiteralPath $match.File.FullName -Raw -Encoding UTF8
        if ($actualJson -cne $canonicalJson) { $problems.Add('EDITORIAL_EXCEPTION_RECEIPT_CANONICAL_BYTES_MISMATCH') }
    }
    [pscustomobject]@{
        Valid=$problems.Count -eq 0; Errors=@($problems); ReceiptPath=$match.File.FullName;
        ReceiptSha256=(Get-FileHash -LiteralPath $match.File.FullName -Algorithm SHA256).Hash; Data=$data
    }
}

function Write-BytesCreateNewAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$Bytes
    )
    $target = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "ATOMIC_DIRECTORY_MISSING: $directory" }
    if (Test-Path -LiteralPath $target) { throw "ATOMIC_TARGET_ALREADY_EXISTS: $target" }
    $tempPath = Join-Path $directory ('.create-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $stream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    try { [IO.File]::Move($tempPath, $target) }
    finally { if (Test-Path -LiteralPath $tempPath -PathType Leaf) { [IO.File]::Delete($tempPath) } }
}

function Get-DocumentField {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Name
    )

    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Name)):\s*(.*?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-ObjectPropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-ConcreteNote {
    param(
        [AllowNull()][string]$Text,
        [int]$MinimumLength = 12
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $trimmed = $Text.Trim()
    # Wartości z tego walidatora trafiają również do jednoliniowych pól meta.md.
    # Kontrolne znaki (w tym CR/LF) mogłyby dopisać fałszywe pole stanu.
    if ($trimmed -match '[\x00-\x1F\x7F]') { return $false }
    return $trimmed.Length -ge $MinimumLength -and
        $trimmed.Split(' ', [StringSplitOptions]::RemoveEmptyEntries).Count -ge 2 -and
        $trimmed -notmatch '^(?i:brak|none|n/?a|todo|tbd|placeholder|do uzupełnienia)$'
}

function Test-ReceiptTimestamp {
    param([AllowNull()][object]$Value)
    $parsed = [DateTimeOffset]::MinValue
    if ($Value -is [DateTime]) { $parsed = [DateTimeOffset]$Value }
    elseif ($Value -is [DateTimeOffset]) { $parsed = $Value }
    elseif (-not [DateTimeOffset]::TryParse(
        [string]$Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )) { return $false }
    return $parsed.UtcDateTime -le [DateTime]::UtcNow.AddMinutes(5)
}

function New-SystemV7K4VerifyReceiptRecord {
    param(
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][string]$VerifyAgentId,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$DraftSha256,
        [Parameter(Mandatory)][string]$EvidenceSha256,
        [Parameter(Mandatory)][string]$SourceCorpusSha256,
        [Parameter(Mandatory)][int]$SourceFileCount,
        [Parameter(Mandatory)][string[]]$SourceFiles,
        [Parameter(Mandatory)][string]$FactCheckSha256,
        [Parameter(Mandatory)][string]$Note,
        [Parameter(Mandatory)][string]$CreatedAtUtc
    )
    $payload = [ordered]@{
        schema='SYSTEM_V7_K4_VERIFY_RECEIPT_V1'; actor='CHATGPT_VERIFY'
        attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'; verdict='PASS'
        project_origin_sha256=$ProjectOriginSha256; verify_agent_id=$VerifyAgentId; task_id=$TaskId
        draft_sha256=$DraftSha256; evidence_sha256=$EvidenceSha256; source_corpus_sha256=$SourceCorpusSha256
        source_file_count=$SourceFileCount; source_files=@($SourceFiles); fact_check_sha256=$FactCheckSha256
        note=$Note; created_at_utc=$CreatedAtUtc
    }
    $binding = Get-Sha256HexFromText -Text (($payload | ConvertTo-Json -Depth 8) + "`n")
    $record = [ordered]@{}
    foreach ($entry in $payload.GetEnumerator()) { $record[$entry.Key] = $entry.Value }
    $record.binding_sha256 = $binding
    [pscustomobject]$record
}

function New-SystemV7K5ApprovalReceiptRecord {
    param(
        [Parameter(Mandatory)][string]$ProjectOriginSha256,
        [Parameter(Mandatory)][string]$FinalSha256,
        [Parameter(Mandatory)][string]$DraftSha256,
        [Parameter(Mandatory)][string]$QaSha256,
        [Parameter(Mandatory)][string]$FactCheckSha256,
        [Parameter(Mandatory)][string]$K4VerifyReceiptSha256,
        [Parameter(Mandatory)][string]$Note,
        [Parameter(Mandatory)][string]$CreatedAtUtc
    )
    $payload = [ordered]@{
        schema='SYSTEM_V7_K5_APPROVAL_RECEIPT_V1'; actor='DAWID'
        attestation_scope='AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'; verdict='APPROVED'
        project_origin_sha256=$ProjectOriginSha256; final_sha256=$FinalSha256; draft_sha256=$DraftSha256
        qa_sha256=$QaSha256; fact_check_sha256=$FactCheckSha256; k4_verify_receipt_sha256=$K4VerifyReceiptSha256
        note=$Note; created_at_utc=$CreatedAtUtc
    }
    $binding = Get-Sha256HexFromText -Text (($payload | ConvertTo-Json -Depth 8) + "`n")
    $record = [ordered]@{}
    foreach ($entry in $payload.GetEnumerator()) { $record[$entry.Key] = $entry.Value }
    $record.binding_sha256 = $binding
    [pscustomobject]$record
}

function Get-K4VerifyReceiptState {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $draft = Join-Path $project '03-draft.md'
    $evidence = Join-Path $project '01-baza-dowodow.md'
    $factCheck = Join-Path $project '04B-fact-check.md'
    $stateErrors = [Collections.Generic.List[string]]::new()
    $origin = $null
    if ($null -eq (Get-Command Get-SystemV7ProjectOriginState -ErrorAction SilentlyContinue)) {
        $stateErrors.Add('PROJECT_ORIGIN_HELPER_NOT_LOADED')
    } else {
        $origin = Get-SystemV7ProjectOriginState -ProjectPath $project
        if (-not $origin.Valid) { $stateErrors.Add("PROJECT_ORIGIN_INVALID: $($origin.Errors -join '; ')") }
    }
    foreach ($required in @($draft, $evidence, $factCheck)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            $stateErrors.Add("REQUIRED_FILE_MISSING: $required")
        } elseif ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
            try { Assert-SystemV7PathNoReparse -Path $required -ContainmentRoot $project | Out-Null }
            catch { $stateErrors.Add($_.Exception.Message) }
        }
    }
    if ($stateErrors.Count -gt 0) {
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$null; ReceiptSha256=$null; Data=$null }
    }

    $draftHash = (Get-FileHash -LiteralPath $draft -Algorithm SHA256).Hash
    $evidenceHash = (Get-FileHash -LiteralPath $evidence -Algorithm SHA256).Hash
    $factCheckHash = (Get-FileHash -LiteralPath $factCheck -Algorithm SHA256).Hash
    try { $corpus = Get-ActiveSourceCorpusState -ProjectPath $project }
    catch {
        $stateErrors.Add($_.Exception.Message)
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$null; ReceiptSha256=$null; Data=$null }
    }

    $receiptPath = Join-Path $project "_work\K4\verify-$factCheckHash.json"
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        try { Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null }
        catch { $stateErrors.Add($_.Exception.Message) }
    }
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        $stateErrors.Add('K4_VERIFY_RECEIPT_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$receiptPath; ReceiptSha256=$null; Data=$null }
    }

    $data = $null
    $rawReceipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8
    try { $data = $rawReceipt | ConvertFrom-Json -DateKind String }
    catch { $stateErrors.Add("K4_VERIFY_RECEIPT_INVALID_JSON: $($_.Exception.Message)") }
    if ($null -ne $data) {
        $verifyAgent = [string](Get-ObjectPropertyValue -Object $data -Name 'verify_agent_id')
        $taskId = [string](Get-ObjectPropertyValue -Object $data -Name 'task_id')
        $note = [string](Get-ObjectPropertyValue -Object $data -Name 'note')
        $createdAt = [string](Get-ObjectPropertyValue -Object $data -Name 'created_at_utc')
        $declaredRows = @((Get-ObjectPropertyValue -Object $data -Name 'source_files') | ForEach-Object { [string]$_ })
        $factCheckText = Get-Content -LiteralPath $factCheck -Raw -Encoding UTF8
        $agentMatches = @([regex]::Matches($factCheckText, '(?m)^VERIFY_AGENT_ID:\s*(.*?)\s*$'))
        $taskMatches = @([regex]::Matches($factCheckText, '(?m)^VERIFY_TASK_ID:\s*(.*?)\s*$'))
        if ($agentMatches.Count -ne 1) { $stateErrors.Add("K4_VERIFY_SOURCE_FIELD_COUNT_INVALID: VERIFY_AGENT_ID=$($agentMatches.Count)") }
        if ($taskMatches.Count -ne 1) { $stateErrors.Add("K4_VERIFY_SOURCE_FIELD_COUNT_INVALID: VERIFY_TASK_ID=$($taskMatches.Count)") }
        $declaredVerifyAgent = if ($agentMatches.Count -eq 1) { $agentMatches[0].Groups[1].Value.Trim() } else { '' }
        $declaredTaskId = if ($taskMatches.Count -eq 1) { $taskMatches[0].Groups[1].Value.Trim() } else { '' }
        if ($verifyAgent -cne $declaredVerifyAgent) { $stateErrors.Add('K4_VERIFY_RECEIPT_FIELD_MISMATCH: verify_agent_id') }
        if ($taskId -cne $declaredTaskId) { $stateErrors.Add('K4_VERIFY_RECEIPT_FIELD_MISMATCH: task_id') }
        if (-not (Test-ConcreteNote -Text $note)) {
            $stateErrors.Add('K4_VERIFY_RECEIPT_NOTE_NOT_CONCRETE')
        }
        if (-not (Test-ReceiptTimestamp -Value $createdAt)) {
            $stateErrors.Add('K4_VERIFY_RECEIPT_CREATED_AT_INVALID')
        }
        if ($verifyAgent.Trim().Length -lt 3) { $stateErrors.Add('K4_VERIFY_RECEIPT_AGENT_INVALID') }
        if ($taskId.Trim().Length -lt 8) { $stateErrors.Add('K4_VERIFY_RECEIPT_TASK_INVALID') }
        if ($declaredRows.Count -ne $corpus.Rows.Count -or ($declaredRows -join "`n") -cne ($corpus.Rows -join "`n")) {
            $stateErrors.Add('K4_VERIFY_RECEIPT_SOURCE_FILES_MISMATCH')
        }
        $expectedRecord = $null
        try {
            $expectedRecord = New-SystemV7K4VerifyReceiptRecord `
                -ProjectOriginSha256 $(if ($origin -and $origin.Valid) { $origin.Sha256 } else { ('0' * 64) }) `
                -VerifyAgentId $(if ($declaredVerifyAgent) { $declaredVerifyAgent } else { '__INVALID_AGENT__' }) `
                -TaskId $(if ($declaredTaskId) { $declaredTaskId } else { '__INVALID_TASK__' }) -DraftSha256 $draftHash `
                -EvidenceSha256 $evidenceHash -SourceCorpusSha256 $corpus.Sha256 -SourceFileCount $corpus.FileCount `
                -SourceFiles @($corpus.Rows) -FactCheckSha256 $factCheckHash `
                -Note $(if ($note) { $note } else { '__INVALID_NOTE__' }) `
                -CreatedAtUtc $(if ($createdAt) { $createdAt } else { '__INVALID_TIMESTAMP__' })
        } catch { $stateErrors.Add("K4_VERIFY_RECEIPT_CANONICAL_BUILD_FAILED: $($_.Exception.Message)") }
        if ($null -ne $expectedRecord) {
        $expectedNames = @($expectedRecord.PSObject.Properties.Name)
        $actualNames = @($data.PSObject.Properties.Name)
        if ($actualNames.Count -ne $expectedNames.Count -or @(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames).Count -gt 0) {
            $stateErrors.Add('K4_VERIFY_RECEIPT_FIELDS_INVALID')
        }
        foreach ($entry in $expectedRecord.PSObject.Properties) {
            if ($entry.Name -eq 'source_files') { continue }
            if ([string](Get-ObjectPropertyValue -Object $data -Name $entry.Name) -cne [string]$entry.Value) {
                $stateErrors.Add("K4_VERIFY_RECEIPT_FIELD_MISMATCH: $($entry.Name)")
            }
        }
        $canonical = ($expectedRecord | ConvertTo-Json -Depth 8) + "`n"
        if (-not (Test-Utf8FileCanonicalBytes -Path $receiptPath -ExpectedText $canonical)) {
            $stateErrors.Add('K4_VERIFY_RECEIPT_CANONICAL_BYTES_MISMATCH')
        }
        }
    }

    [pscustomobject]@{
        Valid = $stateErrors.Count -eq 0
        Errors = @($stateErrors)
        ReceiptPath = $receiptPath
        ReceiptSha256 = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
        Data = $data
    }
}

function Get-K5ApprovalReceiptState {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $draft = Join-Path $project '03-draft.md'
    $qa = Join-Path $project '04-raport-qa.md'
    $factCheck = Join-Path $project '04B-fact-check.md'
    $final = Join-Path $project '05-FINAL-SCRIPT.md'
    $stateErrors = [Collections.Generic.List[string]]::new()
    $origin = $null
    if ($null -eq (Get-Command Get-SystemV7ProjectOriginState -ErrorAction SilentlyContinue)) {
        $stateErrors.Add('PROJECT_ORIGIN_HELPER_NOT_LOADED')
    } else {
        $origin = Get-SystemV7ProjectOriginState -ProjectPath $project
        if (-not $origin.Valid) { $stateErrors.Add("PROJECT_ORIGIN_INVALID: $($origin.Errors -join '; ')") }
    }
    foreach ($required in @($draft, $qa, $factCheck, $final)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { $stateErrors.Add("REQUIRED_FILE_MISSING: $required") }
        elseif ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
            try { Assert-SystemV7PathNoReparse -Path $required -ContainmentRoot $project | Out-Null }
            catch { $stateErrors.Add($_.Exception.Message) }
        }
    }
    if ($stateErrors.Count -gt 0) {
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$null; ReceiptSha256=$null; Data=$null }
    }

    $draftHash = (Get-FileHash -LiteralPath $draft -Algorithm SHA256).Hash
    $qaHash = (Get-FileHash -LiteralPath $qa -Algorithm SHA256).Hash
    $factCheckHash = (Get-FileHash -LiteralPath $factCheck -Algorithm SHA256).Hash
    $finalHash = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash
    $k4State = Get-K4VerifyReceiptState -ProjectPath $project
    foreach ($problem in @($k4State.Errors)) { $stateErrors.Add("K4:$problem") }

    $receiptPath = Join-Path $project "_work\K5\approval-$finalHash.json"
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        try { Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null }
        catch { $stateErrors.Add($_.Exception.Message) }
    }
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        $stateErrors.Add('K5_APPROVAL_RECEIPT_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$receiptPath; ReceiptSha256=$null; Data=$null }
    }

    $data = $null
    $rawReceipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8
    try { $data = $rawReceipt | ConvertFrom-Json -DateKind String }
    catch { $stateErrors.Add("K5_APPROVAL_RECEIPT_INVALID_JSON: $($_.Exception.Message)") }
    if ($null -ne $data) {
        $note = [string](Get-ObjectPropertyValue -Object $data -Name 'note')
        $createdAt = [string](Get-ObjectPropertyValue -Object $data -Name 'created_at_utc')
        if (-not (Test-ConcreteNote -Text $note)) {
            $stateErrors.Add('K5_APPROVAL_RECEIPT_NOTE_NOT_CONCRETE')
        }
        if (-not (Test-ReceiptTimestamp -Value $createdAt)) {
            $stateErrors.Add('K5_APPROVAL_RECEIPT_CREATED_AT_INVALID')
        }
        $expectedRecord = $null
        try {
            $expectedRecord = New-SystemV7K5ApprovalReceiptRecord `
                -ProjectOriginSha256 $(if ($origin -and $origin.Valid) { $origin.Sha256 } else { ('0' * 64) }) `
                -FinalSha256 $finalHash -DraftSha256 $draftHash -QaSha256 $qaHash `
                -FactCheckSha256 $factCheckHash `
                -K4VerifyReceiptSha256 $(if ($k4State.ReceiptSha256) { $k4State.ReceiptSha256 } else { ('0' * 64) }) `
                -Note $(if ($note) { $note } else { '__INVALID_NOTE__' }) `
                -CreatedAtUtc $(if ($createdAt) { $createdAt } else { '__INVALID_TIMESTAMP__' })
        } catch { $stateErrors.Add("K5_APPROVAL_RECEIPT_CANONICAL_BUILD_FAILED: $($_.Exception.Message)") }
        if ($null -ne $expectedRecord) {
        $expectedNames = @($expectedRecord.PSObject.Properties.Name)
        $actualNames = @($data.PSObject.Properties.Name)
        if ($actualNames.Count -ne $expectedNames.Count -or @(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames).Count -gt 0) {
            $stateErrors.Add('K5_APPROVAL_RECEIPT_FIELDS_INVALID')
        }
        foreach ($entry in $expectedRecord.PSObject.Properties) {
            if ([string](Get-ObjectPropertyValue -Object $data -Name $entry.Name) -cne [string]$entry.Value) {
                $stateErrors.Add("K5_APPROVAL_RECEIPT_FIELD_MISMATCH: $($entry.Name)")
            }
        }
        $canonical = ($expectedRecord | ConvertTo-Json -Depth 8) + "`n"
        if (-not (Test-Utf8FileCanonicalBytes -Path $receiptPath -ExpectedText $canonical)) {
            $stateErrors.Add('K5_APPROVAL_RECEIPT_CANONICAL_BYTES_MISMATCH')
        }
        }
    }

    [pscustomobject]@{
        Valid = $stateErrors.Count -eq 0
        Errors = @($stateErrors)
        ReceiptPath = $receiptPath
        ReceiptSha256 = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
        Data = $data
    }
}

function Get-K1ManualFallbackReceiptState {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $metaPath = Join-Path $project 'meta.md'
    $k0Path = Join-Path $project '00-fundament-projektu.md'
    $stateErrors = [Collections.Generic.List[string]]::new()
    foreach ($required in @($metaPath, $k0Path)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            $stateErrors.Add("REQUIRED_FILE_MISSING: $required")
        }
    }
    if ($stateErrors.Count -gt 0) {
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$null; ReceiptSha256=$null; BindingSha256=$null; Data=$null }
    }

    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    if ((Get-DocumentField -Text $meta -Name 'K1_RESEARCH_MODE') -ne 'MANUAL_APPROVED') {
        $stateErrors.Add('K1_RESEARCH_MODE_NOT_MANUAL_APPROVED')
    }
    $reasonField = [string](Get-DocumentField -Text $meta -Name 'K1_MANUAL_REASON')
    $reasonMatch = [regex]::Match($reasonField, '^DAWID=TAK;\s*POWÓD=(?<reason>.{15,})$')
    $reason = if ($reasonMatch.Success) { $reasonMatch.Groups['reason'].Value.Trim() } else { '' }
    if (-not $reasonMatch.Success -or -not (Test-ConcreteNote -Text $reason -MinimumLength 15) -or
        $reason.Split(' ', [StringSplitOptions]::RemoveEmptyEntries).Count -lt 3) {
        $stateErrors.Add('K1_MANUAL_REASON_NOT_CONCRETE')
    }

    $corpus = $null
    try { $corpus = Get-ActiveSourceCorpusState -ProjectPath $project }
    catch { $stateErrors.Add($_.Exception.Message) }
    if ($null -eq $corpus -or -not $reason) {
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$null; ReceiptSha256=$null; BindingSha256=$null; Data=$null }
    }

    if ($null -eq (Get-Command Get-SystemV7ProjectOriginState -ErrorAction SilentlyContinue)) {
        $stateErrors.Add('PROJECT_ORIGIN_HELPER_NOT_LOADED')
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$null; ReceiptSha256=$null; BindingSha256=$null; Data=$null }
    }
    $origin = Get-SystemV7ProjectOriginState -ProjectPath $project
    if (-not $origin.Valid) {
        $stateErrors.Add("PROJECT_ORIGIN_INVALID: $($origin.Errors -join '; ')")
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$null; ReceiptSha256=$null; BindingSha256=$null; Data=$null }
    }

    $k0Hash = (Get-FileHash -LiteralPath $k0Path -Algorithm SHA256).Hash
    $bindingText = "ORIGIN=$($origin.Sha256)`nK0=$k0Hash`nSOURCES=$($corpus.Sha256)`nREASON=$reason`n"
    $bindingHash = Get-Sha256HexFromText -Text $bindingText
    $receiptPath = Join-Path $project "_work\K1\manual-fallback\approval-$bindingHash.json"
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        try { Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null }
        catch { $stateErrors.Add($_.Exception.Message) }
    }
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        $stateErrors.Add('K1_MANUAL_FALLBACK_RECEIPT_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($stateErrors); ReceiptPath=$receiptPath; ReceiptSha256=$null; BindingSha256=$bindingHash; Data=$null }
    }
    $receiptItem = Get-Item -LiteralPath $receiptPath -Force
    if (($receiptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $stateErrors.Add('K1_MANUAL_FALLBACK_RECEIPT_REPARSE_POINT')
    }

    $data = $null
    try { $data = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String }
    catch { $stateErrors.Add("K1_MANUAL_FALLBACK_RECEIPT_INVALID_JSON: $($_.Exception.Message)") }
    if ($null -ne $data) {
        $expected = [ordered]@{
            schema = 'SYSTEM_V7_K1_MANUAL_FALLBACK_RECEIPT_V1'
            actor = 'DAWID'
            attestation_scope = 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'
            verdict = 'APPROVED'
            project_origin_sha256 = $origin.Sha256
            binding_sha256 = $bindingHash
            k0_sha256 = $k0Hash
            source_corpus_sha256 = $corpus.Sha256
            source_file_count = $corpus.FileCount
            reason = $reason
        }
        foreach ($entry in $expected.GetEnumerator()) {
            $actual = Get-ObjectPropertyValue -Object $data -Name $entry.Key
            if ([string]$actual -ne [string]$entry.Value) {
                $stateErrors.Add("K1_MANUAL_FALLBACK_RECEIPT_FIELD_MISMATCH: $($entry.Key)")
            }
        }
        $declaredRows = @((Get-ObjectPropertyValue -Object $data -Name 'source_files') | ForEach-Object { [string]$_ })
        if ($declaredRows.Count -ne $corpus.Rows.Count -or ($declaredRows -join "`n") -cne ($corpus.Rows -join "`n")) {
            $stateErrors.Add('K1_MANUAL_FALLBACK_RECEIPT_SOURCE_FILES_MISMATCH')
        }
        if (-not (Test-ReceiptTimestamp -Value (Get-ObjectPropertyValue -Object $data -Name 'created_at_utc'))) {
            $stateErrors.Add('K1_MANUAL_FALLBACK_RECEIPT_CREATED_AT_INVALID')
        }
    }

    [pscustomobject]@{
        Valid = $stateErrors.Count -eq 0
        Errors = @($stateErrors)
        ReceiptPath = $receiptPath
        ReceiptSha256 = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
        BindingSha256 = $bindingHash
        Data = $data
    }
}

function Assert-K1ManualFallbackAuthorized {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $project = [IO.Path]::GetFullPath($ProjectPath)
    $metaPath = Join-Path $project 'meta.md'
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw "REQUIRED_FILE_MISSING: $metaPath" }
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8
    $workflowRevision = Get-DocumentField -Text $meta -Name 'WORKFLOW_REVISION'
    if ($workflowRevision -ne '2026-08-30_K1_LITE_V2') {
        return [pscustomobject]@{ Required=$false; Valid=$true; ReceiptPath=$null; ReceiptSha256=$null }
    }
    $state = Get-K1ManualFallbackReceiptState -ProjectPath $project
    if (-not $state.Valid) { throw "K1_MANUAL_FALLBACK_NOT_AUTHORIZED: $($state.Errors -join '; ')" }
    [pscustomobject]@{ Required=$true; Valid=$true; ReceiptPath=$state.ReceiptPath; ReceiptSha256=$state.ReceiptSha256 }
}

function Get-W0ConditionClosureState {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$MetaText
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $problems = [Collections.Generic.List[string]]::new()
    $decision = [string](Get-DocumentField -Text $MetaText -Name 'W0_DECISION')
    $condition = [string](Get-DocumentField -Text $MetaText -Name 'W0_CONDITIONS')
    $status = [string](Get-DocumentField -Text $MetaText -Name 'W0_CONDITION_STATUS')
    $result = [string](Get-DocumentField -Text $MetaText -Name 'W0_CONDITION_RESULT')
    $closedAt = [string](Get-DocumentField -Text $MetaText -Name 'W0_CONDITION_CLOSED_AT')
    $receiptRelative = [string](Get-DocumentField -Text $MetaText -Name 'W0_CONDITION_RECEIPT_PATH')
    $receiptSha = [string](Get-DocumentField -Text $MetaText -Name 'W0_CONDITION_RECEIPT_SHA256')

    if ($decision -ne 'GO WARUNKOWE') {
        if ($status -ne 'NOT_APPLICABLE' -or $result -ne 'BRAK' -or $closedAt -ne 'BRAK' -or
            $receiptRelative -ne 'BRAK' -or $receiptSha -ne 'BRAK') {
            $problems.Add('W0_CONDITION_FIELDS_MUST_BE_NOT_APPLICABLE')
        }
        return [pscustomobject]@{ Valid=$problems.Count -eq 0; Errors=@($problems); Status=$status; ReceiptPath=$null; ReceiptSha256=$null }
    }

    if ($status -eq 'OPEN') {
        if ($result -ne 'BRAK' -or $closedAt -ne 'BRAK' -or $receiptRelative -ne 'BRAK' -or $receiptSha -ne 'BRAK') {
            $problems.Add('W0_OPEN_CONDITION_HAS_CLOSURE_DATA')
        }
        return [pscustomobject]@{ Valid=$problems.Count -eq 0; Errors=@($problems); Status=$status; ReceiptPath=$null; ReceiptSha256=$null }
    }
    if ($status -ne 'CLOSED') {
        $problems.Add('W0_CONDITION_STATUS_INVALID')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Status=$status; ReceiptPath=$null; ReceiptSha256=$null }
    }
    if (-not (Test-ConcreteNote -Text $result -MinimumLength 12)) { $problems.Add('W0_CONDITION_RESULT_NOT_CONCRETE') }
    $closedDate = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($closedAt, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$closedDate) -or
        $closedDate.Date -gt [DateTime]::UtcNow.Date) {
        $problems.Add('W0_CONDITION_CLOSED_AT_INVALID')
    }
    if ($null -eq (Get-Command Get-SystemV7ProjectOriginState -ErrorAction SilentlyContinue)) {
        $problems.Add('PROJECT_ORIGIN_HELPER_NOT_LOADED')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Status=$status; ReceiptPath=$null; ReceiptSha256=$null }
    }
    $origin = Get-SystemV7ProjectOriginState -ProjectPath $project
    if (-not $origin.Valid) { $problems.Add("PROJECT_ORIGIN_INVALID: $($origin.Errors -join '; ')") }
    $originSha = if ($origin.Valid) { $origin.Sha256 } else { '' }
    $bindingText = "ORIGIN=$originSha`nCONDITION=$condition`nRESULT=$result`nCLOSED_AT=$closedAt`n"
    $bindingHash = Get-Sha256HexFromText -Text $bindingText
    $expectedRelative = "_work/system/w0-condition/closure-$bindingHash.json"
    if ($receiptRelative -cne $expectedRelative) { $problems.Add('W0_CONDITION_RECEIPT_PATH_MISMATCH') }
    if ($receiptSha -notmatch '^[A-Fa-f0-9]{64}$') { $problems.Add('W0_CONDITION_RECEIPT_SHA_INVALID') }
    $receiptPath = [IO.Path]::GetFullPath((Join-Path $project $expectedRelative))
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        try { Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null }
        catch { $problems.Add($_.Exception.Message) }
    }
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        $problems.Add('W0_CONDITION_RECEIPT_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Status=$status; ReceiptPath=$receiptPath; ReceiptSha256=$null }
    }
    $item = Get-Item -LiteralPath $receiptPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $problems.Add('W0_CONDITION_RECEIPT_REPARSE_POINT') }
    $actualSha = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    if ($receiptSha -notmatch '^[A-Fa-f0-9]{64}$' -or $actualSha -ne $receiptSha.ToUpperInvariant()) { $problems.Add('W0_CONDITION_RECEIPT_SHA_MISMATCH') }
    $data = $null
    try { $data = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String }
    catch { $problems.Add("W0_CONDITION_RECEIPT_INVALID_JSON: $($_.Exception.Message)") }
    if ($data) {
        $expected = [ordered]@{
            schema = 'SYSTEM_V7_W0_CONDITION_CLOSURE_V1'
            actor = 'DAWID'
            attestation_scope = 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'
            verdict = 'CLOSED'
            project_origin_sha256 = $originSha
            condition = $condition
            result = $result
            closed_at = $closedAt
            binding_sha256 = $bindingHash
        }
        foreach ($entry in $expected.GetEnumerator()) {
            if ([string](Get-ObjectPropertyValue -Object $data -Name $entry.Key) -cne [string]$entry.Value) {
                $problems.Add("W0_CONDITION_RECEIPT_FIELD_MISMATCH: $($entry.Key)")
            }
        }
        if (-not (Test-ReceiptTimestamp -Value (Get-ObjectPropertyValue -Object $data -Name 'created_at_utc'))) {
            $problems.Add('W0_CONDITION_RECEIPT_CREATED_AT_INVALID')
        }
    }
    [pscustomobject]@{ Valid=$problems.Count -eq 0; Errors=@($problems); Status=$status; ReceiptPath=$receiptPath; ReceiptSha256=$actualSha }
}

function Get-OwnerOverrideReceiptState {
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$MetaText
    )
    $project = [IO.Path]::GetFullPath($ProjectPath)
    $problems = [Collections.Generic.List[string]]::new()
    $stage = [string](Get-DocumentField -Text $MetaText -Name 'CURRENT_STAGE')
    $owner = [string](Get-DocumentField -Text $MetaText -Name 'STAGE_OWNER')
    $override = [string](Get-DocumentField -Text $MetaText -Name 'OWNER_OVERRIDE')
    $receiptRelative = [string](Get-DocumentField -Text $MetaText -Name 'OWNER_OVERRIDE_RECEIPT_PATH')
    $receiptSha = [string](Get-DocumentField -Text $MetaText -Name 'OWNER_OVERRIDE_RECEIPT_SHA256')
    $ownerMap = @{
        W0='Dawid'; K0='ChatGPT'; K1='ChatGPT'; K2='ChatGPT'; K2B='ChatGPT';
        K3='Claude'; K4='ChatGPT'; K5='Dawid'; COMPLETE='Dawid'; BLOCKED='Dawid'
    }
    if (-not $ownerMap.ContainsKey($stage)) {
        $problems.Add('OWNER_OVERRIDE_STAGE_INVALID')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Required=$false; ReceiptPath=$null; ReceiptSha256=$null }
    }
    $canonicalOwner = $ownerMap[$stage]
    if ($owner -eq $canonicalOwner) {
        if ($override -ne 'BRAK' -or $receiptRelative -ne 'BRAK' -or $receiptSha -ne 'BRAK') {
            $problems.Add('OWNER_OVERRIDE_DATA_MUST_BE_BRAK_FOR_CANONICAL_OWNER')
        }
        return [pscustomobject]@{ Valid=$problems.Count -eq 0; Errors=@($problems); Required=$false; ReceiptPath=$null; ReceiptSha256=$null }
    }
    if ($stage -in @('COMPLETE','BLOCKED')) { $problems.Add('OWNER_OVERRIDE_NOT_ALLOWED_FOR_TERMINAL_STAGE') }
    if ($owner -notin @('ChatGPT','Claude','Dawid')) { $problems.Add('OWNER_OVERRIDE_TARGET_INVALID') }
    $match = [regex]::Match($override, '^DAWID=TAK;\s*OWNER=(?<owner>[^;]+);\s*POWÓD=(?<reason>[^;]{10,});\s*ZAKRES=(?<scope>.{5,})$')
    if (-not $match.Success -or $match.Groups['owner'].Value.Trim() -ne $owner -or
        -not (Test-ConcreteNote -Text $match.Groups['reason'].Value -MinimumLength 10) -or
        -not (Test-ConcreteNote -Text $match.Groups['scope'].Value -MinimumLength 5)) {
        $problems.Add('OWNER_OVERRIDE_FORMAT_INVALID')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Required=$true; ReceiptPath=$null; ReceiptSha256=$null }
    }
    $reason = $match.Groups['reason'].Value.Trim()
    $scope = $match.Groups['scope'].Value.Trim()
    if ($null -eq (Get-Command Get-SystemV7ProjectOriginState -ErrorAction SilentlyContinue)) {
        $problems.Add('PROJECT_ORIGIN_HELPER_NOT_LOADED')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Required=$true; ReceiptPath=$null; ReceiptSha256=$null }
    }
    $origin = Get-SystemV7ProjectOriginState -ProjectPath $project
    if (-not $origin.Valid) { $problems.Add("PROJECT_ORIGIN_INVALID: $($origin.Errors -join '; ')") }
    $originSha = if ($origin.Valid) { $origin.Sha256 } else { '' }
    $metaContextSha = $null
    try { $metaContextSha = Get-OwnerOverrideMetaContextSha256 -MetaText $MetaText -CanonicalOwner $canonicalOwner }
    catch { $problems.Add($_.Exception.Message) }
    if (-not $metaContextSha) {
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Required=$true; ReceiptPath=$null; ReceiptSha256=$null }
    }
    $bindingText = "ORIGIN=$originSha`nMETA_CONTEXT=$metaContextSha`nSTAGE=$stage`nCANONICAL_OWNER=$canonicalOwner`nOWNER=$owner`nREASON=$reason`nSCOPE=$scope`n"
    $bindingHash = Get-Sha256HexFromText -Text $bindingText
    $expectedRelative = "_work/system/owner-override/$stage-$bindingHash.json"
    if ($receiptRelative -cne $expectedRelative) { $problems.Add('OWNER_OVERRIDE_RECEIPT_PATH_MISMATCH') }
    $receiptPath = [IO.Path]::GetFullPath((Join-Path $project $expectedRelative))
    if ($null -ne (Get-Command Assert-SystemV7PathNoReparse -ErrorAction SilentlyContinue)) {
        try { Assert-SystemV7PathNoReparse -Path $receiptPath -ContainmentRoot $project | Out-Null }
        catch { $problems.Add($_.Exception.Message) }
    }
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
        $problems.Add('OWNER_OVERRIDE_RECEIPT_MISSING')
        return [pscustomobject]@{ Valid=$false; Errors=@($problems); Required=$true; ReceiptPath=$receiptPath; ReceiptSha256=$null }
    }
    $item = Get-Item -LiteralPath $receiptPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $problems.Add('OWNER_OVERRIDE_RECEIPT_REPARSE_POINT') }
    $actualSha = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    if ($receiptSha -notmatch '^[A-Fa-f0-9]{64}$' -or $actualSha -ne $receiptSha.ToUpperInvariant()) { $problems.Add('OWNER_OVERRIDE_RECEIPT_SHA_MISMATCH') }
    $data = $null
    try { $data = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String }
    catch { $problems.Add("OWNER_OVERRIDE_RECEIPT_INVALID_JSON: $($_.Exception.Message)") }
    if ($data) {
        $expected = [ordered]@{
            schema = 'SYSTEM_V7_OWNER_OVERRIDE_RECEIPT_V1'
            actor = 'DAWID'
            attestation_scope = 'AUDITABLE_ACKNOWLEDGEMENT_NOT_CRYPTOGRAPHIC_IDENTITY'
            verdict = 'APPROVED'
            project_origin_sha256 = $originSha
            meta_context_sha256 = $metaContextSha
            stage = $stage
            canonical_owner = $canonicalOwner
            owner = $owner
            reason = $reason
            scope = $scope
            binding_sha256 = $bindingHash
        }
        foreach ($entry in $expected.GetEnumerator()) {
            if ([string](Get-ObjectPropertyValue -Object $data -Name $entry.Key) -cne [string]$entry.Value) {
                $problems.Add("OWNER_OVERRIDE_RECEIPT_FIELD_MISMATCH: $($entry.Key)")
            }
        }
        if (-not (Test-ReceiptTimestamp -Value (Get-ObjectPropertyValue -Object $data -Name 'created_at_utc'))) {
            $problems.Add('OWNER_OVERRIDE_RECEIPT_CREATED_AT_INVALID')
        }
    }
    [pscustomobject]@{ Valid=$problems.Count -eq 0; Errors=@($problems); Required=$true; ReceiptPath=$receiptPath; ReceiptSha256=$actualSha }
}
